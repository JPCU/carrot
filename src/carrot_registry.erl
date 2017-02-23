-module(carrot_registry).
-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("carrot_internal.hrl").

%% API.
-export([typed_config/1,
         exchange_prefix/0,
         open_channel/1,
         start_link/3]).

%% gen_server.
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
          rabbit_host,
          rabbit_port,
          rabbit_cfg,
          connection,
          channels = #{}
}).

%% API

-spec typed_config({atom(), atom()}) -> {ok, map()}.
typed_config(TypedName) ->
    gen_server:call(?MODULE, {config, TypedName}).

-spec exchange_prefix() -> {ok, list()}.
exchange_prefix() -> gen_server:call(?MODULE, exchange_prefix).

-spec open_channel({atom(), atom(), atom()}) -> {ok, pid()}.
open_channel(ControllerSpec) ->
    gen_server:call(?MODULE, {open_channel, ControllerSpec}).

-spec start_link(string(), integer(), map()) -> {ok, pid()}.
start_link(RabbitHost, RabbitPort, RabbitCfg) ->
    catch ets:new(?MODULE, [named_table, public]),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [RabbitHost,
                                                      RabbitPort,
                                                      RabbitCfg], []).

%% gen_server.

init([RabbitHost, RabbitPort, RabbitCfg]) ->
    self() ! connect,
    {ok, #state{
            rabbit_host = RabbitHost,
            rabbit_port = RabbitPort,
            rabbit_cfg = RabbitCfg
           }}.

handle_call({config, TypeName},
            _From,
            #state{rabbit_cfg = Cfg} = State) ->
    TypedCfg = get_typed_cfg(Cfg, TypeName),
    {reply, TypedCfg, State};
handle_call(exchange_prefix,
            _From,
            #state{rabbit_cfg = Cfg} = State) ->
    {reply, {ok, get_exchange_prefix(Cfg)}, State};
handle_call({open_channel, ControllerSpec},
            {Pid, _},
            #state{channels   = Channels,
                   connection = Connection} = State) ->
    Ref = erlang:monitor(process, Pid),
    ets:insert(?MODULE, ControllerSpec),
    {ok, Channel} = amqp_connection:open_channel(Connection),
    UpdatedChannels = Channels#{Ref => Channel},
    {reply, {ok, Channel}, State#state{channels = UpdatedChannels}};
handle_call(Msg, _From, State) ->
    ?LOG_WARN("Ignored msg: ~p~n", [Msg]),
    {reply, ignored, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info(connect, #state{connection = undefined} = State) ->
    case connect(State#state.rabbit_host, State#state.rabbit_port) of
        {ok, Connection} ->
            ?LOG_DEBUG("Connected."),
            link(Connection),
            lists:foreach(
              fun({Module, Args}) ->
                      apply(Module, start, Args)
              end,
              ets:tab2list(?MODULE)),
            {noreply, State#state{connection=Connection}};
        {error, Reason} ->
            ?LOG_ERR("Failed to connect: ~p~n", [Reason]),
            _ = timer:send_after(1000, connect),
            {noreply, State}
    end;
handle_info({'DOWN', Ref, process, _Pid, _Reason},
            #state{channels = Channels} = State) ->
    Channel = maps:get(Ref, Channels),
    ?LOG_INFO("Closing channel ~p", [Channel]),
    amqp_channel:close(Channel),
    erlang:demonitor(Ref),
    UpdatedChannels = maps:remove(Ref, Channels),
    {noreply, State#state{channels = UpdatedChannels}};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    [begin
         ?LOG_INFO("Terminate closing channel ~p", [Channel]),
         amqp_channel:close(Channel)
     end || Channel <- maps:values(State#state.channels)],
    ?LOG_INFO("Closing connection ~p", [State#state.connection]),
    amqp_connection:close(State#state.connection),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Private
connect(Host, Port) ->
    ?LOG_INFO("Connecting to RabbitMQ (~p:~p)...~n", [Host, Port]),
    amqp_connection:start(
      #amqp_params_network{
         host      = Host,
         port      = Port,
         heartbeat = 30
        }).

get_typed_cfg(Cfg, {Type, Name}) ->
    ?LOG_INFO("Getting config for ~p of type ~p~ncfg: ~p~n", [Name, Type, Cfg]),
    get_value_from_list_by_name(maps:get(Type, Cfg, #{}), Name).

get_value_from_list_by_name(List, LookupName) ->
    case lists:dropwhile(
           fun(#{name := Name}) ->
                   LookupName /= Name
           end,
           List) of
        [] -> {error, "No such item in list: " ++ atom_to_list(LookupName)};
        [P | _] -> {ok, P}
    end.

get_exchange_prefix(#{exchange_prefix := ExchangePrefix} = _RabbitCfg) ->
    ExchangePrefix.
