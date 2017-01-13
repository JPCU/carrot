-module(carrot_rpc_SUITE).

-behaviour(carrot_rpc_server).
-behaviour(carrot_rpc_client).

-include("carrot_api.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

rpc_server_name() ->
    test_rpc_server.

rpc_client_name() ->
    test_rpc_client.

received_init_msg() ->
    gproc_ps:publish(l, ?MODULE, {connected, self()}),
    #{}.

serve_request(Payload, _PropsMap, UserState) ->
    #{} = UserState,
    ct:pal("RPC serve_request called with ~p", [Payload]),
    {<<"Hello, ", Payload/binary>>, #{}}.

all() ->
     [basic_test].

init_per_suite(Config) ->
    application:stop(carrot),
    application:set_env(
      carrot,
      rabbit_cfg,
      #{
        host => "localhost",
        port => 5672,
        exchange_prefix => "carrot_test",
        rpc_servers => [
                        #{name => test_rpc_server,
                          queue => #{
                            name => "carrot_test_rpc",
                            durable => false
                           }
                         }
                       ],
        rpc_clients => [
                        #{name => test_rpc_client,
                          rpc_server_queue => "carrot_test_rpc"
                         }
                       ]
       },
      [{persistent, true}]),
    application:ensure_all_started(carrot),
    application:ensure_started(gproc),
    Config.

basic_test(_Config) ->
    gproc_ps:subscribe(l, ?MODULE),

    {ok, Server} = ?CARROT_RPC_SERVER_START(),
    await_connected(Server),
    ct:pal("RPC server started"),

    ?CARROT_RPC_CLIENT_START(),
    ct:pal("RPC client started"),

    Payload = <<"world">>,
    <<"Hello, world">> = ?CARROT_RPC_CLIENT_CALL(Payload).

await_connected(Pid) ->
    ct:pal("waiting for pid ~p ...", [Pid]),
    receive
        {gproc_ps_event, ?MODULE, {connected, Pid}} ->
            ct:pal("~p connected.", [Pid])
    after 10000 -> exit(consumer_connect_timeout)
    end.
