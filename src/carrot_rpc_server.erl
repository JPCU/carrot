-module(carrot_rpc_server).

-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("carrot_internal.hrl").

%%
%% Consumer API
%%
-export([
         start/1,
         start/2,
         start_link/2
        ]).

-callback rpc_server_name() -> atom().

%% Must return initialized state
-callback received_init_msg() -> map().

%% Sync server (must return value, and user state)
-callback serve_request(any(), map(), any()) ->
    {any(), map()}.

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
          consumer_tag,
          user_state = #{}
}).

%% --------------------------------- < API > -----------------------------------

start(Module) -> start(Module, undefined).

start(Module, Id) ->
    carrot_channel_sup:start_child(
      {carrot:ref(?MODULE, Module:rpc_server_name(), Id),
       {?MODULE, start_link, [Module, Id]},
       temporary, 5000, worker, [?MODULE]}).

start_link(Module, Id) -> gen_server:start_link(?MODULE, [Module, Id], []).

%% ------------------------------ < gen_server > -------------------------------

init([Module, Id]) ->
    self() ! setup_channel,
    {ok, #state{id = Id,
                callback_module = Module}}.

handle_call(Msg, _From, State) ->
    ?LOG_INFO("Received message: ~p", [Msg]),
    {reply, ignored, State}.

handle_cast({ack_message, DeliveryTag},
            #state{
               channel = Channel} = State) ->
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = DeliveryTag}),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(setup_channel,
            #state{id = Id,
                   callback_module = Module,
                   channel = undefined} = State) ->
    Name = Module:rpc_server_name(),
    ?LOG_INFO("Starting RPC server (~p) ~p with module ~p at ~p...~n",
              [Id, Name, Module, self()]),

    {ok, #{queue := #{
             name := QueueName,
             durable := IsQueueDurable
            }}} = carrot_registry:typed_config({rpc_servers, Name}),

    {ok, ExchangePrefix} = carrot_registry:exchange_prefix(),

    {ok, Channel} = carrot_registry:open_channel({?MODULE, [Module, Id]}),

    {ok, Queue} = carrot:queue_declare(
                    Channel,
                    queue_name(ExchangePrefix, QueueName, Id),
                    IsQueueDurable),

    {ok, ConsumerTag} = carrot:queue_sub(Channel, Queue, self()),

    {noreply, State#state{
                channel = Channel,
                consumer_tag = ConsumerTag}};
handle_info(#'basic.consume_ok'{consumer_tag = ConsumerTag},
            #state{
               consumer_tag = ConsumerTag,
               callback_module = Module} = State) ->
    UserState = Module:received_init_msg(),
    {noreply, State#'state'{user_state = UserState}};
handle_info({#'basic.deliver'{consumer_tag = ConsumerTag,
                              delivery_tag = DeliveryTag},
             #amqp_msg{payload = Payload,
                       props = #'P_basic'{
                                  correlation_id = CorrelationId,
                                  reply_to = ReplyTo
                                 } = Props}},
            #state{
               consumer_tag = ConsumerTag,
               callback_module = Module,
               channel = Channel,
               user_state = UserState} = State) ->

    PropsMap = maps:from_list(record_to_proplist(Props)),

    {RpcReplyPayload, UpdatedUserState} =
        Module:serve_request(Payload, PropsMap, UserState),

    Publish = #'basic.publish'{routing_key = ReplyTo},

    ReplyProps = #'P_basic'{correlation_id = CorrelationId},

    amqp_channel:call(Channel, Publish, #amqp_msg{
                                           props = ReplyProps,
                                           payload = RpcReplyPayload}),
    ack_message(DeliveryTag),

    {noreply, State#'state'{user_state = UpdatedUserState}};
handle_info({Module, Msg},
            #state{callback_module = Module} = State) ->
    %% passthrough messages tagged for callback module
    Module:handle_info(Msg),
    {noreply, State};
handle_info(Msg, State) ->
    ?LOG_WARN("Received unexpected message: ~p", [Msg]),
    {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% ------------------------------ < internal > ---------------------------------

ack_message(Id) -> ack_message(self(), Id).

ack_message(Pid, Id) -> gen_server:cast(Pid, {ack_message, Id}).

queue_name(Prefix, Name, undefined) ->
    carrot:prefix_name_as_bin(Prefix, Name);
queue_name(Prefix, Name, Suffix) ->
    PrefixBin = list_to_binary(Prefix),
    NameBin = list_to_binary(Name),
    SuffixBin = list_to_binary(carrot:to_list(Suffix)),
    <<PrefixBin/binary, ".", NameBin/binary, ".", SuffixBin/binary>>.

record_to_proplist(#'P_basic'{} = Rec) ->
  lists:zip(record_info(fields, 'P_basic'), tl(tuple_to_list(Rec))).
