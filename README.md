Example config:

``` erlang
{rabbit_cfg, #{
   host => "localhost",
   port => 5672,
   exchange_prefix => "carrot_test",
   producers => [
                 #{name => some_producer,
                   routing_key => "some_key",
                   exchange => #{
                     name => "some_exchange",
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
                     name => "some_exchange",
                     type => "topic",
                     durable => false
                    },
                   queue => #{
                     name => "some_consumer",
                     durable => false
                    }
                  },
                 #{name => game_consumer,
                   routing_key => "coverage",
                   exchange => #{
                     name => "event_bus",
                     type => "topic",
                     durable => false
                    },
                   queue => #{
                     name => "game_consumer",
                     durable => false
                    }
                  }
                ],
   rpc_servers => [
                   #{name => rpc_server,
                     queue => #{
                       name => "some_rpc",
                       durable => false
                      }
                    }
                  ],
   rpc_clients => [
                   #{name => rpc_client,
                     rpc_server_queue => "some_rpc"
                    }
                  ]
  }}
```
