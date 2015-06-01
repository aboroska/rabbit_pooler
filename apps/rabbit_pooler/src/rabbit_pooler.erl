%%%-------------------------------------------------------------------
%%% @author aboroska
%%% @copyright (C) 2015, aboroska
%%% @doc
%%%
%%% @end
%%% Created : 2015-05-19 20:27:14.155584
%%%-------------------------------------------------------------------
-module(rabbit_pooler).

-behaviour(gen_server).

%% API
-export([start_link/0,
         send/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% Internal
-export([connect/2]).

-include_lib("amqp_client/include/amqp_client.hrl").

-define(SERVER, ?MODULE).

-record(broker, {name,
                 config,
                 state = down,
                 connection}).

-record(state, {brokers = []}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
        gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec send(Msg :: binary()) -> ok | {error, Reason :: any()}.
send(Msg) ->
    Brokers = gen_server:call(?SERVER, get_brokers, infinity),
    try_send(Msg, Brokers).

try_send(_Msg, []) ->
    {error, no_connection};
try_send(Msg, [Broker | Brokers]) ->
    Name = Broker#broker.name,
    case pooler:take_member(Name, 1000) of
        Channel when is_pid(Channel) ->
            try
                ack = gen_server:call(Channel, {send, Msg}),
                pooler:return_member(Name, Channel, ok),
                ok
            catch
                _C:_E ->
                    gen_server:call(?SERVER, {down, Broker}),
                    %pooler:return_member(Name, Channel, fail)
                    try_send(Msg, Brokers)
            end;
        _Error ->
            io:format("~p ~p No members _Error : '~p' ~n", [?MODULE, ?LINE, _Error ]),
            try_send(Msg, Brokers)
    end.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    self() ! connect,
    {ok, #state{brokers=make_brokers()}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(get_brokers, _From, State=#state{brokers=Brokers}) ->
    io:format("~p ~p Brokers: '~p' ~n", [?MODULE, ?LINE, Brokers]),
    Active = [B || B=#broker{state=up} <- Brokers],
    {reply, Active, State};
handle_call({down, Broker}, _From, State) ->
    NewState = handle_broker_down(Broker, State),
    {reply, ok, NewState};
handle_call(Msg, From = {Pid,_Ref}, State) ->
    error_logger:error_msg("Unexpected Msg:~p From:~p~n", [Msg,From]),
    error_logger:error_msg("From initial call:~p~n", [proc_lib:initial_call(Pid)]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
        {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(connect, State=#state{brokers=Brokers}) ->
    [spawn_link(?MODULE, connect, [self(), Broker#broker{state=connecting}])
     || Broker=#broker{state=down} <- Brokers],
    erlang:send_after(2000, self(), connect),
    {noreply, State};
handle_info({connect_result, ok, Broker}, State) ->
    NewState = update_state(Broker, State),
    {noreply, NewState};
handle_info({connect_result, Error, Broker}, State) ->
    io:format("~p ~p  Error: '~p' ~n", [?MODULE, ?LINE,  Error]),
    NewState = handle_broker_down(Broker, State),
    {noreply, NewState};
handle_info(Msg, State) ->
    error_logger:error_msg("Unexpected info Msg:~p~n", [Msg]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
        ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
        {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

connect(Parent, Broker=#broker{name=Name,config=Cfg}) ->
    io:format("~p ~p  Broker: '~p' ~n", [?MODULE, ?LINE,  Broker]),
    case amqp_connection:start(Cfg) of
        {ok, Conn} ->
            pooler:rm_pool(Name),
            io:format("~p ~p Name: '~p' ~n", [?MODULE, ?LINE, Name]),
            DefaultPoolCfg = application:get_env(rabbit_pooler, poolconfig, []),
            PoolCfg = [{name,Name},
                       {start_mfa,{rabbit_pooler_worker,start_link,[Conn]}}],
            pooler:new_pool(PoolCfg ++ DefaultPoolCfg),
            Parent ! {connect_result, ok, Broker#broker{state=up, connection=Conn}};
        Error ->
            io:format("~p ~p Error : '~p' ~n", [?MODULE, ?LINE, Error ]),
            Parent ! {connect_result, Error, Broker#broker{state=down}}
    end.

handle_broker_down(Broker, State) ->
    NewState = update_state(Broker#broker{state=down}, State),
    check_all_down(NewState#state.brokers),
    NewState.

check_all_down(Brokers) ->
    lists:all(fun(#broker{state=down}) -> true;
                 (#broker{}) -> false
              end,
              Brokers).

update_state(Broker=#broker{name=Name}, State=#state{brokers=Brokers}) ->
    NewBrokers = lists:keyreplace(Name, #broker.name, Brokers, Broker),
    State#state{brokers=NewBrokers}.

make_brokers() ->
    Defaults = #amqp_params_network{port=5672,heartbeat=5},
    DefPort = Defaults#amqp_params_network.port,
    {ok, Brokers} = application:get_env(rabbit_pooler, brokers),
    [#broker{name=Name,
             config=Defaults#amqp_params_network{
                       port=proplists:get_value(port,Params,DefPort)}}
     || {Name, Params} <- Brokers].



