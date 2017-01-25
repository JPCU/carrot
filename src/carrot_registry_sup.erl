-module(carrot_registry_sup).
-behaviour(supervisor).

-export([
         start_link/3
        ]).

-export([
         init/1
        ]).

start_link(RabbitHost, RabbitPort, RabbitCfg) ->
    supervisor:start_link(
      {local, ?MODULE},
      ?MODULE,
      [RabbitHost, RabbitPort, RabbitCfg]).

init([RabbitHost, RabbitPort, RabbitCfg]) ->
    {ok, {{rest_for_one, 1, 5},
          [worker(carrot_registry, transient, [RabbitHost, RabbitPort,
                                               RabbitCfg]),
           supervisor(carrot_channel_sup)]}}.

supervisor(Module) ->
    supervisor(Module, permanent).

supervisor(Module, Restart) ->
    {Module, {Module, start_link, []}, Restart, infinity, supervisor, [Module]}.

worker(Module, Restart, Parameters) ->
    worker(Module, Module, Restart, Parameters).

worker(Id, Module, Restart, Parameters) ->
    {Id, {Module, start_link, Parameters}, Restart, 5000, worker, [Module]}.
