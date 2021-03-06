%%%-------------------------------------------------------------------
%%% @copyright (C) 2012-2018, 2600Hz INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(fax_requests_sup).

-behaviour(supervisor).

-include("fax.hrl").

-define(SERVER, ?MODULE).

%% API
-export([start_link/0]).
-export([new/3]).
-export([workers/0]).

%% Supervisor callbacks
-export([init/1]).

-define(CHILDREN, [?WORKER_TYPE('fax_request', 'temporary')]).

%% ===================================================================
%% API functions
%% ===================================================================

%%--------------------------------------------------------------------
%% @public
%% @doc Starts the supervisor
%%--------------------------------------------------------------------
-spec start_link() -> startlink_ret().
start_link() ->
    supervisor:start_link({'local', ?SERVER}, ?MODULE, []).

-spec new(kapps_call:call(), kz_json:object(), fax_storage()) -> sup_startchild_ret().
new(Call, JObj, Storage) ->
    supervisor:start_child(?SERVER, [Call, JObj, Storage]).

-spec workers() -> pids().
workers() ->
    [ Pid || {_, Pid, 'worker', [_]} <- supervisor:which_children(?SERVER)].

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%% @end
%%--------------------------------------------------------------------
-spec init(any()) -> sup_init_ret().
init([]) ->
    RestartStrategy = 'simple_one_for_one',
    MaxRestarts = 0,
    MaxSecondsBetweenRestarts = 1,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    {'ok', {SupFlags, ?CHILDREN}}.
