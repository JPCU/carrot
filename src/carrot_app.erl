-module(carrot_app).

-behaviour(application).

-export([prep_stop/1,
         start/2,
         stop/1]).

start(_Type, _Args) ->
    RabbitHost = carrot:config(rabbit_host),
    RabbitPort = carrot:config(rabbit_port),
    RabbitCfg = carrot:config(rabbit_cfg),
    carrot_registry_sup:start_link(RabbitHost, RabbitPort, RabbitCfg).

prep_stop(State) ->
    gen_server:stop(carrot_registry, normal, 5000),
    State.

stop(_State) -> ok.
