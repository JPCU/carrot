-module(carrot_registry).
-behaviour(gen_server).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("carrot_internal.hrl").

%% API.
-export([typed_config/1,
         exchange_prefix/0,
         open_channel/1,
         request_connection/0,
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
    gen_server:call(carrot_registry, {config, TypedName}).

-spec exchange_prefix() -> {ok, list()}.
exchange_prefix() -> gen_server:call(carrot_registry, exchange_prefix).

-spec open_channel(pid()) -> {ok, pid()}.
open_channel(Connection) ->
    {ok, Channel} = amqp_connection:open_channel(Connection),
    ok = gen_server:call(carrot_registry, {register_channel, self(), Channel}),
    {ok, Channel}.

-spec start_link(string(), integer(), map()) -> {ok, pid()}.
start_link(RabbitHost, RabbitPort, RabbitCfg) ->
    gen_server:start_link({local, carrot_registry}, ?MODULE, [RabbitHost,
                                                              RabbitPort,
                                                              RabbitCfg], []).

request_connection() ->
    gen_server:cast(carrot_registry, {connection, self()}).

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
handle_call({register_channel, Pid, Channel},
            _From,
            #state{channels = Channels} = State) ->
    Ref = erlang:monitor(process, Pid),
    UpdatedChannels = Channels#{Ref => Channel},
    {reply, ok, State#state{channels = UpdatedChannels}};
handle_call(Msg, _From, State) ->
    ?LOG_WARN("Ignored msg: ~p~n", [Msg]),
    {reply, ignored, State}.

handle_cast({connection, Pid},
            #state{connection = Connection} = State)
  when Connection /= undefined->
    ?LOG_INFO("~p requesting Connection ~p", [Pid, Connection]),
    Pid ! {connection, Connection},
    {noreply, State};
handle_cast(_Msg, State) -> {noreply, State}.

handle_info(connect, #state{connection = undefined} = State) ->
    case connect(State#state.rabbit_host, State#state.rabbit_port) of
        {ok, Connection} ->
            ?LOG_DEBUG("Connected."),
            lists:foreach(
              fun({_, Child, _, _}) when is_pid(Child) ->
                      Child ! {connection, Connection};
                 (_) -> ok
              end,
              carrot_channel_sup:which_children()),
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
         host = Host,
         port = Port
        }).

get_typed_cfg(Cfg, {Type, Name}) ->
    get_value_from_list_by_name(maps:get(Type, Cfg, #{}), Name).

get_value_from_list_by_name(List, LookupName) ->
    case lists:dropwhile(
           fun(#{name := Name}) ->
                   LookupName /= Name
           end,
           List) of
        [] -> {error, "No such item in list: " ++ LookupName};
        [P | _] -> {ok, P}
    end.

get_exchange_prefix(#{exchange_prefix := ExchangePrefix} = _RabbitCfg) ->
    ExchangePrefix.
