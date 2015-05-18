%%%-------------------------------------------------------------------
%% @doc rabbit_pooler public API
%% @end
%%%-------------------------------------------------------------------

-module('rabbit_pooler_app').

-behaviour(application).

%% Application callbacks
-export([start/2
        ,stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    'rabbit_pooler_sup':start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================