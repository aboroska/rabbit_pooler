%%%-------------------------------------------------------------------
%% @doc rabbit_pooler top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module('rabbit_pooler_sup').

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    PoolerSup = {pooler_sup, {pooler_sup, start_link, []},
                 permanent, infinity, supervisor, [pooler_sup]},
    App = {rabbit_pooler, {rabbit_pooler, start_link, []},
                permanent, infinity, worker, [rabbit_pooler]},
    {ok, { {one_for_all, 0, 1}, [PoolerSup, App]} }.

%%====================================================================
%% Internal functions
%%====================================================================
