%%%-------------------------------------------------------------------
%%% @doc
%%% [C3I-SIL6] UOS Holon Root Supervisor (aṃśa-pūrṇa supervisor)
%%% Provides fail-safe OTP 29 supervision for uos_holon_node.
%%% Strategy: one_for_all (restarts node with backoff on failure).
%%% Runtime: Pure Erlang/OTP 29 (ERTS 17.0.5) ONLY.
%%% Mandates: SC-NIX-DEVENV-001, SC-MUDA-001
%%% @end
%%%-------------------------------------------------------------------
-module(uos_holon_sup).
-behaviour(supervisor).

%% API
-export([start_link/0, start_link/1, stop/0]).

%% supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).
-define(DEFAULT_PORT, 8088).

%%====================================================================
%% API functions
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(?DEFAULT_PORT).

-spec start_link(integer()) -> {ok, pid()} | {error, term()}.
start_link(Port) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, [Port]).

-spec stop() -> ok.
stop() ->
    case whereis(?SERVER) of
        undefined -> ok;
        Pid -> exit(Pid, shutdown)
    end.

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init([Port]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 10,
        period => 60
    },
    ChildSpecs = [
        #{
            id => uos_holon_node,
            start => {uos_holon_node, start_link, [Port]},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [uos_holon_node]
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.
