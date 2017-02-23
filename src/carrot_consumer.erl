-module(carrot_consumer).

-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("carrot_internal.hrl").

%%
%% Consumer API
%%
-export([
         start/1,
         start/2,
         stop/1,
         start_link/2,
         ack_message/1,
         ack_message/2
        ]).

-callback consumer_name() -> atom().

-callback received_init_msg() -> term().

%% responsible for calling ack_msg with the delivery tag
-callback received_msg(binary(), any(), map(), term()) -> atom().

%% gen_server.
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
          id,
          callback_module,
          channel,
          consumer_state,
          consumer_tag
}).

%% --------------------------------- < API > -----------------------------------

start(Module) -> start(Module, undefined).

start(Module, Id) ->
    carrot_channel_sup:start_child(
      {carrot:ref(?MODULE, Module:consumer_name(), Id),
       {?MODULE, start_link, [Module, Id]},
       transient, 5000, worker, [?MODULE]}).

stop(Pid) -> gen_server:cast(Pid, stop).

start_link(Module, Id) -> gen_server:start_link(?MODULE, [Module, Id], []).

ack_message(Id) -> ack_message(self(), Id).

ack_message(Pid, Id) -> gen_server:cast(Pid, {ack_message, Id}).

%% ------------------------------ < gen_server > -------------------------------

init([Module, Id]) ->
    carrot_registry:request_connection(),
    {ok, #state{ id = Id,
                 callback_module = Module }}.

handle_call(Msg, _From, State) ->
    ?LOG_INFO("Received message: ~p", [Msg]),
    {reply, ignored, State}.

handle_cast({ack_message, DeliveryTag},
            #state{channel = Channel} = State) ->
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = DeliveryTag}),
    {noreply, State};
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({connection, Connection},
            #state{
               id = Id,
               callback_module = Module,
               channel = undefined } = State) ->
    Name = Module:consumer_name(),
    ?LOG_INFO("Connecting consumer (~p) ~p with module ~p at ~p...~n",
              [Id, Name, Module, self()]),

    {ok, #{routing_key := RoutingKey,
           exchange := #{
             name := ExchangeName,
             type := ExchangeType,
             durable := IsExchangeDurable
            },
           queue := #{
             name := QueueName,
             durable := IsQueueDurable
            }}} = carrot_registry:typed_config({consumers, Name}),

    {ok, ExchangePrefix} = carrot_registry:exchange_prefix(),

    {ok, Channel} = carrot_registry:open_channel(Connection),

    ExchangeFullName = carrot:prefix_name_as_bin(ExchangePrefix, ExchangeName),
    ok = carrot:exchange_declare(Channel,
                                 ExchangeFullName,
                                 list_to_binary(ExchangeType),
                                 IsExchangeDurable),

    {ok, Queue} = carrot:queue_declare(
                    Channel,
                    queue_name(ExchangePrefix, QueueName, Id),
                    IsQueueDurable),

    ok = carrot:queue_bind(Channel, Queue, ExchangeFullName,
                           routing_key(RoutingKey, Id)),

    {ok, ConsumerTag} = carrot:queue_sub(Channel, Queue, self()),

    ?LOG_INFO("Consumer Tag = ~p", [ConsumerTag]),
    {noreply, State#state{
                channel = Channel,
                consumer_tag = ConsumerTag}};
handle_info(#'basic.consume_ok'{consumer_tag = ConsumerTag},
            #state{
               consumer_tag = ConsumerTag,
               callback_module = Module} = State) ->
    CState = Module:received_init_msg(),
    {noreply, State#state{consumer_state = CState}};
handle_info({#'basic.deliver'{consumer_tag = ConsumerTag,
                              delivery_tag = DeliveryTag},
            #amqp_msg{payload = Payload, props = Props}},
            #state{
               consumer_tag = ConsumerTag,
               consumer_state = CState,
               callback_module = Module} = State) ->
    PropsMap = maps:from_list(record_to_proplist(Props)),
    Module:received_msg(DeliveryTag, Payload, PropsMap, CState),
    {noreply, State};
handle_info({Module, Msg},
            #state{callback_module = Module} = State) ->
    %% passthrough messages tagged for callback module
    Module:handle_info(Msg),
    {noreply, State};
handle_info(Msg, State) ->
    ?LOG_INFO("~p received unexpected message: ~p", [self(), Msg]),
    {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% ------------------------------ < internal > ---------------------------------

queue_name(Prefix, Name, undefined) ->
    carrot:prefix_name_as_bin(Prefix, Name);
queue_name(Prefix, Name, Suffix) ->
    PrefixBin = list_to_binary(Prefix),
    NameBin = list_to_binary(Name),
    SuffixBin = list_to_binary(carrot:to_list(Suffix)),
    <<PrefixBin/binary, ".", NameBin/binary, ".", SuffixBin/binary>>.

routing_key(Name, undefined) -> list_to_binary(Name);
routing_key(Name, Suffix)    ->
    NameBin = list_to_binary(Name),
    SuffixBin = list_to_binary(carrot:to_list(Suffix)),
    <<NameBin/binary, ".", SuffixBin/binary>>.

record_to_proplist(#'P_basic'{} = Rec) ->
  lists:zip(record_info(fields, 'P_basic'), tl(tuple_to_list(Rec))).
