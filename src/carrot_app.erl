-module(carrot_app).

-behaviour(application).

-export([start/2,
         stop/1]).

start(_Type, _Args) ->
    RabbitHost = carrot:config(rabbit_host),
    RabbitPort = carrot:config(rabbit_port),
    RabbitCfg = carrot:config(rabbit_cfg),
    carrot_registry_sup:start_link(RabbitHost, RabbitPort, RabbitCfg).

stop(_State) -> ok.
