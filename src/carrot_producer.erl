-module(carrot_producer).

-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("carrot_internal.hrl").

-callback producer_name() -> atom().

%%
%% Producer API
%%
-export([
         start/1,
         start_link/1,
         send_message/2,
         send_message/3,
         send_message/4,
         sync_send_message/2,
         sync_send_message/3,
         sync_send_message/4
        ]).

%% gen_server.
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
          callback_module,
          channel,
          exchange,
          routing_key,
          props
}).

%% --------------------------------- < API > -----------------------------------

start(Module) ->
    carrot_channel_sup:start_child(
      {ref(Module), {?MODULE, start_link, [Module]},
       temporary, 5000, worker, [?MODULE]}).

start_link(Module) -> gen_server:start_link(?MODULE, [Module], []).

send_message(Module, Payload) -> send_message(Module, Payload, default, #{}).

send_message(Module, Payload, RoutingKey) ->
    send_message(Module, Payload, RoutingKey, #{}).

send_message(Module, Payload, RoutingKey, Props) ->
    gen_server:call(ref(Module),
                    {send_message, true, Payload, RoutingKey, Props}).

sync_send_message(Module, Payload) ->
    sync_send_message(Module, Payload, default, #{}).

sync_send_message(Module, Payload, RoutingKey) ->
    sync_send_message(Module, Payload, RoutingKey, #{}).

sync_send_message(Module, Payload, RoutingKey, Props) ->
    gen_server:call(ref(Module),
                    {send_message, false, Payload, RoutingKey, Props}).

%% ------------------------------ < gen_server > -------------------------------

init([Module]) ->
    register(ref(Module), self()),
    carrot_registry:request_connection(),
    {ok, #state{callback_module = Module}}.

handle_call({send_message, Async, Payload, RoutingKey, Props},
            _From,
            #state{channel = Channel,
                   exchange = ExchangeName,
                   routing_key = DefaultRoutingKey,
                   props = DefaultProps} = State) when Channel /= undefined ->
    ?LOG_INFO("Sending message to ~p...~n", [ExchangeName]),

    Publish = #'basic.publish'{
                 exchange = ExchangeName,
                 routing_key = maybe_default(
                                 RoutingKey, DefaultRoutingKey)},

    ConvertedProps = carrot:to_p_basic(maps:merge(DefaultProps, Props)),

    F = amqp_channel_call(Async),
    R = F(Channel, Publish, #amqp_msg{
                                props = ConvertedProps,
                                payload = Payload}),

    {reply, R, State};
handle_call(Msg, _From, State) ->
    ?LOG_WARN("Received message: ~p", [Msg]),
    {reply, ignored, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info({connection, Connection},
            #state{callback_module = Module,
                   channel = undefined} = State) ->
    Name = Module:producer_name(),
    ?LOG_INFO("Connecting producer ~p with module ~p at ~p...~n",
              [Name, Module, self()]),

    {ok, #{routing_key := RoutingKey,
           props := Props,
           exchange := #{
             name := ExchangeName,
             type := ExchangeType,
             durable := IsExchangeDurable
            }}} = carrot_registry:typed_config({producers, Name}),

    {ok, ExchangePrefix} = carrot_registry:exchange_prefix(),

    {ok, Channel} = carrot_registry:open_channel(Connection),

    ExchangeFullName = carrot:prefix_name_as_bin(ExchangePrefix, ExchangeName),

    ok = carrot:exchange_declare(Channel,
                                 ExchangeFullName,
                                 list_to_binary(ExchangeType),
                                 IsExchangeDurable),
    ?LOG_DEBUG("Exchange declared.~n"),

    {noreply, State#state{channel = Channel,
                          exchange = ExchangeFullName,
                          routing_key = list_to_binary(RoutingKey),
                          props = Props}};
handle_info(Msg, State) ->
    ?LOG_WARN("Received unexpected message: ~p", [Msg]),
    {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% ------------------------------ < internal > ---------------------------------

ref(Mod) -> carrot:ref(?MODULE, Mod:producer_name()).

maybe_default(default, Default) -> Default;
maybe_default(Other, _Default)  -> Other.

amqp_channel_call(true)  -> fun amqp_channel:cast/3;
amqp_channel_call(false) -> fun amqp_channel:call/3.
