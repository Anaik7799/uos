-module(uos_zlp_sup).
-behaviour(supervisor).
-export([start_link/1, ensure_started/0, ensure_started/1, stop/0, is_running/0, init/1]).

start_link(NumShards) when is_integer(NumShards), NumShards >= 1, NumShards =< 64 ->
    case uos_zlp_shard:resolve_port_executable() of
        {ok, _BinPath} ->
            supervisor:start_link({local, ?MODULE}, ?MODULE, NumShards);
        {error, Reason} ->
            {error, Reason}
    end.

ensure_started() ->
    ensure_started(4).

ensure_started(NumShards) ->
    case whereis(?MODULE) of
        Pid when is_pid(Pid) ->
            case is_process_alive(Pid) of
                true -> {ok, Pid};
                false -> start_unlinked(NumShards)
            end;
        undefined ->
            start_unlinked(NumShards)
    end.

start_unlinked(NumShards) ->
    case start_link(NumShards) of
        {ok, Pid} ->
            unlink(Pid),
            {ok, Pid};
        {error, {already_started, Pid}} ->
            {ok, Pid};
        {error, Reason} ->
            {error, Reason}
    end.

stop() ->
    case whereis(?MODULE) of
        Pid when is_pid(Pid) ->
            Ref = erlang:monitor(process, Pid),
            exit(Pid, shutdown),
            receive
                {'DOWN', Ref, process, Pid, _} -> ok
            after 3000 ->
                erlang:demonitor(Ref, [flush]),
                exit(Pid, kill),
                ok
            end;
        undefined ->
            ok
    end.

is_running() ->
    case whereis(?MODULE) of
        Pid when is_pid(Pid) -> is_process_alive(Pid);
        undefined -> false
    end.

init(NumShards) ->
    %% Durable supervisor-owned ETS table for automatic Zenoh subscription replay across SIGKILL restarts (Theorem T15)
    case ets:whereis(uos_zlp_subscriptions) of
        undefined ->
            ets:new(uos_zlp_subscriptions, [named_table, public, bag, {read_concurrency, true}]);
        _ ->
            ok
    end,
    persistent_term:put(uos_zlp_shard_count, NumShards),
    SupFlags = #{strategy => one_for_one, intensity => 20, period => 60},
    ChildSpecs = [
        #{id => {uos_zlp_shard, I},
          start => {uos_zlp_shard, start_link, [I]},
          restart => permanent,
          shutdown => 2000,
          type => worker,
          modules => [uos_zlp_shard]}
        || I <- lists:seq(0, NumShards - 1)
    ],
    {ok, {SupFlags, ChildSpecs}}.
