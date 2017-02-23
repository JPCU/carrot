-module(carrot_SUITE).

-behaviour(carrot_producer).
-behaviour(carrot_consumer).

-include("carrot_api.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

producer_name() -> some_producer.

consumer_name() -> some_consumer.

received_init_msg() ->
    gproc_ps:publish(l, carrots, connected),
    ok.

received_msg(DeliveryTag, Carrot, Props, ok) ->
    gproc_ps:publish(l, carrots, {DeliveryTag, Carrot, Props}),
    carrot_consumer:ack_message(DeliveryTag).

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
                       #{name => some_consumer,
                         routing_key => "some_key",
                         exchange => #{
                           name => "test_exchange",
                           type => "topic",
                           durable => false
                          },
                         queue => #{
                           name => "some_consumer",
                           durable => false
                          }
                        }
                      ]
       },
      [{persistent, true}]),
    application:ensure_all_started(carrot),
    application:ensure_started(gproc),
    Config.

basic_test(_Config) ->
    gproc_ps:subscribe(l, carrots),
    ?CARROT_PRODUCER_START(),
    ?CARROT_CONSUMER_START(),
    receive
        {gproc_ps_event, carrots, connected} -> ok
    after 15000 ->
            exit(connect_timeout)
    end,

    Carrot = <<"Hello, this is my payload">>,

    ?CARROT_PRODUCER_SEND_MESSAGE(Carrot),
    receive
        {gproc_ps_event, carrots, {_, Carrot, _}} -> ok
    after 5000 ->
            exit(timeout)
    end.
