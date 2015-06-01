%%%-------------------------------------------------------------------
%%% @author aboroska
%%% @copyright (C) 2015, aboroska
%%% @doc
%%%
%%% @end
%%% Created : 2015-05-19 21:29:38.625813
%%%-------------------------------------------------------------------
-module(rabbit_pooler_worker).

-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include_lib("amqp_client/include/amqp_client.hrl").

-define(SERVER, ?MODULE).

-record(state, {channel :: pid(),
                caller  :: pid(),
                publish}).

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
start_link(Connection) ->
        gen_server:start_link(?MODULE, Connection, []).

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
init(Connection) ->
    io:format("~p ~p Connection: '~p' ~n", [?MODULE, ?LINE, Connection]),
    {ok, Channel} = amqp_connection:open_channel(Connection),
    ok = amqp_channel:register_confirm_handler(Channel, self()),
    #'confirm.select_ok'{} = amqp_channel:call(Channel, #'confirm.select'{}),
    amqp_channel:call(Channel, #'exchange.declare'{exchange= <<"ricky">>}),
    Publish = #'basic.publish'{exchange = <<"ricky">>, routing_key= <<"">>},
    {ok, #state{channel=Channel,publish=Publish}}.

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
handle_call({send, Msg}, From, State=#state{channel=Channel,
                                            publish=Publish,
                                            caller=undefined}) ->
    ok = amqp_channel:cast(Channel,Publish,#amqp_msg{payload=Msg}),
    {noreply, State#state{caller=From}}.

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
handle_info(Unexpected, State=#state{caller=undefined}) ->
    io:format("~p ~p Unexpected: '~p' ~n", [?MODULE, ?LINE, Unexpected]),
    {noreply, State};
handle_info(#'basic.ack'{}, State=#state{caller=From}) ->
    %timer:sleep(100),
    gen_server:reply(From, ack),
    {noreply, State#state{caller=undefined}};
handle_info(#'basic.nack'{}, State=#state{caller=From}) ->
    gen_server:reply(From, nack),
    {noreply, State#state{caller=undefined}}.

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
terminate(_Reason, #state{channel=Channel}) ->
    amqp_channel:close(Channel),
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




