-module(carrot_rpc_client).

-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("carrot_internal.hrl").

-callback rpc_client_name() -> atom().

%%
%% Producer API
%%
-export([
         start/1,
         start_link/1,
         call_server/2
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
          callback_queue,
          caller,
          channel,
          expected_correlation_id,
          server_queue
}).

%% --------------------------------- < API > -----------------------------------

start(Module) ->
    carrot_channel_sup:start_child(
      {ref(Module), {?MODULE, start_link, [Module]},
       temporary, 5000, worker, [?MODULE]}).

start_link(Module) -> gen_server:start_link(?MODULE, [Module], []).

%% Sync call to remote
call_server(Module, Payload) ->
    gen_server:call(ref(Module),
                    {call_server, Payload}).

%% ------------------------------ < gen_server > -------------------------------

init([Module]) ->
    register(ref(Module), self()),
    self() ! setup_channel,
    {ok, #state{callback_module = Module}}.

handle_call({call_server, Payload},
            From,
            #state{channel = Channel,
                   callback_queue = CallbackQueue,
                   server_queue = RpcServerQueue
                  } = State) ->

    CorrelationId = list_to_binary(uuid:uuid_to_string(uuid:get_v4())),
    CallbackProps = #'P_basic'{
                       reply_to = CallbackQueue,
                       correlation_id = CorrelationId
                      },

    {ok, ExchangePrefix} = carrot_registry:exchange_prefix(),
    ExchangePrefixBinary = list_to_binary(ExchangePrefix),
    RpcRoutingKey = <<ExchangePrefixBinary/binary,
                      ".", RpcServerQueue/binary>>,

    Publish = #'basic.publish'{
                 exchange = <<"">>,
                 routing_key = RpcRoutingKey
                },

    amqp_channel:call(Channel, Publish, #amqp_msg{
                                           props = CallbackProps,
                                           payload = Payload}),

    {noreply, State#state{caller = From,
                          expected_correlation_id = CorrelationId}};
handle_call(Msg, _From, State) ->
    ?LOG_WARN("Received message: ~p", [Msg]),
    {reply, ignored, State}.

handle_cast({ack_message, DeliveryTag},
            #state{
               channel = Channel} = State) ->
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = DeliveryTag}),
    {noreply, State};
handle_cast(_Msg, State) -> {noreply, State}.


handle_info(setup_channel,
            #state{callback_module = Module,
                   channel = undefined} = State) ->
    Name = Module:rpc_client_name(),
    ?LOG_INFO("Starting RPC client ~p with module ~p at ~p...~n",
              [Name, Module, self()]),

    {ok, #{
       rpc_server_queue := RpcServerQueue
      }} = carrot_registry:typed_config({rpc_clients, Name}),
    RpcServerQueueBin = list_to_binary(RpcServerQueue),

    {ok, Channel} = carrot_registry:open_channel(),

    {ok, CallbackQueue} = carrot:callback_queue_declare(Channel),
    ?LOG_INFO("RPC Callback Queue declared: ~p~n", [CallbackQueue]),

    {ok, _ConsumerTag} = carrot:queue_sub(Channel, CallbackQueue, self()),

    {noreply, State#state{channel = Channel,
                          callback_queue = CallbackQueue,
                          server_queue = RpcServerQueueBin}};
handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};
handle_info({#'basic.deliver'{delivery_tag = DeliveryTag},
            #amqp_msg{payload = Payload,
                      props = #'P_basic'{correlation_id = CorrelationId}}},
            #state{caller = From,
                   expected_correlation_id = ExpectedCorrelationId
                  } = State)
  when CorrelationId =:= ExpectedCorrelationId ->
    gen_server:reply(From, Payload),
    ack_message(DeliveryTag),
    {noreply, State};
handle_info(Msg, State) ->
    ?LOG_WARN("Received unexpected message: ~p", [Msg]),
    {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% ------------------------------ < internal > ---------------------------------

ref(Mod) -> carrot:ref(?MODULE, Mod:rpc_client_name()).

ack_message(Id) -> ack_message(self(), Id).

ack_message(Pid, Id) -> gen_server:cast(Pid, {ack_message, Id}).
