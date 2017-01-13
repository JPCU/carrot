-module(carrot_channel_sup).

-behaviour(supervisor).

-export([
         start_link/0,
         start_child/1,
         which_children/0
        ]).

-export([
         init/1
        ]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {{one_for_one, 1, 5}, []}}.

start_child(ChildSpec) ->
    supervisor:start_child(?MODULE, ChildSpec).

which_children() ->
    supervisor:which_children(?MODULE).
