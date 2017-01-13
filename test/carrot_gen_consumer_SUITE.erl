-module(carrot_gen_consumer_SUITE).

-behaviour(carrot_producer).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-include("carrot_api.hrl").

-compile(export_all).

producer_name() -> some_producer.

all() -> [gen_consumer_test].

init_per_suite(Config) ->
    application:stop(carrot),
    application:set_env(
      carrot,
      rabbit_cfg,
      #{
         host => "localhost",
         port => 5672,
         exchange_prefix => "carrot_test",
         producers => [
                       #{name => some_producer,
                         routing_key => "some_key",
                         exchange => #{
                           name => "test_exchange",
                           type => "topic",
                           durable => false
                          },
                         props => #{
                           delivery_mode => 2
                          }
                        }
                      ],
         consumers => [
                       #{name => gen_consumer,
                         routing_key => "some_key",
                         exchange => #{
                           name => "test_exchange",
                           type => "topic",
                           durable => false
                          },
                         queue => #{
                           name => "gen_consumer",
                           durable => false
                          }
                        }
                      ]
       },
      [{persistent, true}]),
    application:ensure_all_started(carrot),
    application:ensure_started(gproc),
    ?CARROT_PRODUCER_START(),
    Config.

init_per_testcase(_Case, Config) ->
    gproc_ps:subscribe(l, gen_consumer),
    Config.

gen_consumer_test(_Config) ->
    {ok, Pid1} = gen_consumer:start(1),
    await_connected(Pid1),

    {ok, Pid2} = gen_consumer:start(<<"2">>),
    await_connected(Pid2),

    {ok, Pid3} = gen_consumer:start("three"),
    await_connected(Pid3),

    {ok, Pid4} = gen_consumer:start(four),
    await_connected(Pid4),

    CorrelationId = <<"some_correlationId">>,
    Message = <<"hello world">>,
    ?CARROT_PRODUCER_SEND_MESSAGE(Message, <<"some_key.1">>,
                                  #{correlation_id => CorrelationId}),
    await_msg(Message, Pid1, CorrelationId),
    ?CARROT_PRODUCER_SEND_MESSAGE(Message, <<"some_key.2">>,
                                  #{correlation_id => CorrelationId}),
    await_msg(Message, Pid2, CorrelationId),
    ?CARROT_PRODUCER_SEND_MESSAGE(Message, <<"some_key.three">>,
                                  #{correlation_id => CorrelationId}),
    await_msg(Message, Pid3, CorrelationId),
    ?CARROT_PRODUCER_SEND_MESSAGE(Message, <<"some_key.four">>,
                                  #{correlation_id => CorrelationId}),
    await_msg(Message, Pid4, CorrelationId),
    %% make sure no other message have arrived
    ?assertEqual(timeout, ensure_no_receive()).

await_connected(Pid) ->
    ct:pal("waiting for pid ~p ...", [Pid]),
    receive
        {gproc_ps_event, gen_consumer, {connected, Pid}} ->
            ct:pal("~p connected.", [Pid])
    after 10000 -> exit(consumer_connect_timeout)
    end.

await_msg(Message, Pid, CorrelationId) ->
    receive
        {gproc_ps_event, gen_consumer,
         {event, {Message, Pid, #{correlation_id := CorrelationId}}}} -> ok;
        Unexpected ->
            ct:pal("Unexpected message received: ~p", [Unexpected]),
            exit({unexpected, Unexpected})
    after 5000 -> exit(timeout)
    end.

ensure_no_receive() ->
    receive Foo -> exit(Foo)
    after 100 -> timeout
    end.
