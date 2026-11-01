-module(zlp_v3_test_ffi).
-export([
    is_zenoh_8080_reachable/0,
    run_two_lane_hol_bdd/0,
    run_sigkill_sse_replay_bdd/0,
    run_performance_quantiles/1,
    run_scalability_swarm/2,
    run_property_sliding_window/1,
    run_adversarial_fuzzing/1,
    run_multi_shard_chaos/1,
    test_indrajaal_native_zenoh_bridge/0
]).

is_zenoh_8080_reachable() ->
    case gen_tcp:connect({127, 0, 0, 1}, 8080, [binary, {active, false}], 300) of
        {ok, Sock} ->
            gen_tcp:close(Sock),
            true;
        {error, _} ->
            false
    end.

wait_for_new_pid(ShardId, OldPid, Attempts) when Attempts > 0 ->
    case uos_zlp_router:shard_health(ShardId) of
        {ok, #{os_pid := NewPid, excl := 1} = H} when NewPid =/= OldPid, NewPid > 0 ->
            {ok, H};
        _ ->
            timer:sleep(5),
            wait_for_new_pid(ShardId, OldPid, Attempts - 1)
    end;
wait_for_new_pid(_ShardId, _OldPid, 0) ->
    {error, respawn_timeout}.

%% Modality 4A (BDD): 200 Fast-Lane RPCs overtake an in-flight Heavy-Lane Lean 4 job on Shard 1
run_two_lane_hol_bdd() ->
    Parent = self(),
    Ref = make_ref(),
    HeavyBlob = binary:copy(<<"0123456789abcdef">>, 256),
    T0 = erlang:monotonic_time(microsecond),
    spawn_link(fun() ->
        Res = uos_zlp_router:heavy_graph_digest(1, 12000, HeavyBlob),
        Parent ! {zlp_heavy_done, Ref, erlang:monotonic_time(microsecond) - T0, Res}
    end),
    timer:sleep(2),
    FastLats = [
        begin
            Tf = erlang:monotonic_time(microsecond),
            {ok, #{excl := 1}} = uos_zlp_router:verify_frame_on_shard(1, 0, true, <<"{\"lane\":\"fast\"}">>),
            erlang:monotonic_time(microsecond) - Tf
        end || _ <- lists:seq(1, 200)
    ],
    FastElapsed = erlang:monotonic_time(microsecond) - T0,
    receive
        {zlp_heavy_done, Ref, HeavyElapsed, {ok, #{excl := 1, lane_or_sub := 2, value := HeavyDig}}}
          when HeavyDig > 0, FastElapsed < HeavyElapsed ->
            Sorted = lists:sort(FastLats),
            P50 = lists:nth(100, Sorted),
            {ok, {P50, FastElapsed, HeavyElapsed}};
        {zlp_heavy_done, Ref, HeavyElapsed, OtherRes} ->
            {error, unicode:characters_to_binary(io_lib:format("unexpected_bdd_4a: ~p (~p)", [OtherRes, HeavyElapsed]))}
    after 8000 ->
        {error, <<"heavy_lane_timeout">>}
    end.

%% Modality 4B (BDD): SIGKILL OS PID holding live Zenoh SSE stream & prove automatic Dual-ETS replay
run_sigkill_sse_replay_bdd() ->
    SubTopic = <<"uos/sandbox/zlp_v3_gleam_test/bdd/**">>,
    PubTopic = <<"uos/sandbox/zlp_v3_gleam_test/bdd/alpha">>,
    {ShardId, {ok, #{excl := 1}}} = uos_zlp_router:zenoh_subscribe(SubTopic, self()),
    timer:sleep(80),
    uos_zlp_router:gleam_flush_zenoh_pushes(),
    {ok, #{os_pid := PreKillPid}} = uos_zlp_router:shard_health(ShardId),
    uos_zlp_router:gleam_kill9_os_pid(PreKillPid),
    case wait_for_new_pid(ShardId, PreKillPid, 250) of
        {ok, #{os_pid := PostKillPid, active_subs := ReplayedSubs}} when ReplayedSubs >= 1 ->
            timer:sleep(80),
            uos_zlp_router:gleam_flush_zenoh_pushes(),
            {ok, #{excl := 1}} = uos_zlp_router:zenoh_publish(PubTopic, <<"{\"bdd\":\"post_sigkill_replayed\"}">>),
            receive
                {zlp_zenoh_push, ShardId, 1, Dig, JsonBin} when Dig > 0 ->
                    case binary:match(JsonBin, <<"post_sigkill_replayed">>) of
                        {_, _} -> {ok, {PreKillPid, PostKillPid}};
                        nomatch -> {error, <<"replayed_payload_mismatch">>}
                    end
            after 3000 ->
                {error, <<"post_sigkill_sse_push_timeout">>}
            end;
        Err ->
            {error, unicode:characters_to_binary(io_lib:format("respawn_failed: ~p", [Err]))}
    end.

%% Modality 5 (Performance): Measure p50 and p99 supervised RTT in microseconds
run_performance_quantiles(Count) ->
    _ = uos_zlp_router:reset_shard(2),
    LatsUs = [
        begin
            T0 = erlang:monotonic_time(nanosecond),
            {ok, #{excl := 1}} = uos_zlp_router:verify_frame_on_shard(2, I, true, <<"{\"perf\":1}">>),
            (erlang:monotonic_time(nanosecond) - T0) div 1000
        end || I <- lists:seq(1, Count)
    ],
    Sorted = lists:sort(LatsUs),
    P50 = lists:nth(max(1, Count div 2), Sorted),
    P99 = lists:nth(max(1, (Count * 99) div 100), Sorted),
    {ok, {P50, P99}}.

%% Modality 6 (Scalability): Concurrent BEAM actors hammering lock-free shard router
run_scalability_swarm(NumActors, CallsPerActor) ->
    _ = [uos_zlp_router:reset_shard(S) || S <- [0, 1, 2, 3]],
    Parent = self(),
    T0 = erlang:monotonic_time(microsecond),
    Workers = [
        spawn_link(fun() ->
            lists:foreach(fun(_) ->
                {ok, #{excl := 1}} = uos_zlp_router:verify_frame(0, false, <<"{\"swarm\":true,\"ok\":1}">>)
            end, lists:seq(1, CallsPerActor)),
            Parent ! {zlp_scale_done, self()}
        end) || _ <- lists:seq(1, NumActors)
    ],
    _ = [receive {zlp_scale_done, W} -> ok after 15000 -> error(scale_timeout) end || W <- Workers],
    ElapsedUs = max(1, erlang:monotonic_time(microsecond) - T0),
    TotalCalls = NumActors * CallsPerActor,
    Rps = (TotalCalls * 1000000) div ElapsedUs,
    {ok, Rps}.

%% Modality 7 (Property-Based): Pure reference oracle vs Lean 4 64-bitmap sliding anti-replay
oracle_replay_step({Init, High, SeenSet}, Seq) ->
    if
        Seq =:= 0 ->
            {reject, {Init, High, SeenSet}};
        not Init ->
            {accept, {true, Seq, #{Seq => true}}};
        Seq > High ->
            Pruned = maps:filter(fun(K, _) -> (Seq - K) < 64 end, SeenSet),
            {accept, {true, Seq, Pruned#{Seq => true}}};
        (High - Seq) >= 64 ->
            {reject, {Init, High, SeenSet}};
        true ->
            case maps:is_key(Seq, SeenSet) of
                true  -> {reject, {Init, High, SeenSet}};
                false -> {accept, {Init, High, SeenSet#{Seq => true}}}
            end
    end.

run_property_sliding_window(Trials) ->
    _ = rand:seed(exsss, {2026, 11, 1}),
    _ = uos_zlp_router:reset_shard(3),
    Res = lists:foldl(fun(_, Acc) ->
        case Acc of
            {error, _} = Err ->
                Err;
            {ok, OracleSt, BaseSeq, Checked} ->
                Delta = rand:uniform(90) - 45,
                CandidateSeq = max(1, BaseSeq + Delta),
                {Expected, NextOracleSt} = oracle_replay_step(OracleSt, CandidateSeq),
                Actual = case uos_zlp_router:verify_frame_on_shard(3, CandidateSeq, false, <<"{\"prop\":1}">>) of
                    {ok, #{excl := 1}} -> accept;
                    {error, {zlp_refused, 4, 1, 0}} -> reject;
                    Other -> {unexpected, Other}
                end,
                case Expected =:= Actual of
                    true ->
                        NewBase = case NextOracleSt of {_, H, _} when H > 0 -> H; _ -> BaseSeq end,
                        {ok, NextOracleSt, NewBase, Checked + 1};
                    false ->
                        {error, unicode:characters_to_binary(
                            io_lib:format("seq=~p expected=~p actual=~p", [CandidateSeq, Expected, Actual])
                        )}
                end
        end
    end, {ok, {false, 0, #{}}, 50, 0}, lists:seq(1, Trials)),
    case Res of
        {ok, _, _, Count} -> {ok, Count};
        {error, Msg} -> {error, Msg}
    end.

%% Modality 8 (Adversarial Fuzzing): Hostile binaries, NULs, deep JSON, a2a prefix -> 0 crashes, excl == 1
run_adversarial_fuzzing(Trials) ->
    {ok, #{os_pid := PrePid}} = uos_zlp_router:shard_health(2),
    _ = uos_zlp_router:reset_shard(2),
    lists:foreach(fun(K) ->
        Len = rand:uniform(320),
        Raw = case K rem 5 of
            0 -> crypto:strong_rand_bytes(Len);
            1 -> <<"{", (crypto:strong_rand_bytes(Len))/binary, 0, "}">>;
            2 -> <<"c3i/a2a/", (crypto:strong_rand_bytes(Len))/binary>>;
            3 -> list_to_binary(lists:duplicate(34 + (K rem 8), ${));
            4 -> <<>>
        end,
        case uos_zlp_router:verify_frame_on_shard(2, 0, true, Raw) of
            {ok, #{excl := 1}} -> ok;
            {error, {zlp_refused, Code, 1, _}} when Code >= 1, Code =< 6 -> ok
        end
    end, lists:seq(1, Trials)),
    {ok, #{os_pid := PostPid, excl := 1}} = uos_zlp_router:shard_health(2),
    case PrePid =:= PostPid of
        true -> {ok, PostPid};
        false -> {error, <<"worker_crashed_during_fuzzing">>}
    end.

%% Modality 9 (Chaos Engineering): 6 staggered SIGKILL strikes across all 4 shards under live load
run_multi_shard_chaos(CallsPerActor) ->
    Parent = self(),
    Workers = [
        spawn_link(fun() ->
            OkCount = lists:foldl(fun(_, Acc) ->
                case uos_zlp_router:verify_frame(0, true, <<"{\"chaos\":true}">>) of
                    {ok, #{excl := 1}} -> Acc + 1;
                    {error, _} -> timer:sleep(2), Acc
                end
            end, 0, lists:seq(1, CallsPerActor)),
            Parent ! {zlp_chaos_done, self(), OkCount}
        end) || _ <- lists:seq(1, 8)
    ],
    lists:foreach(fun(Strike) ->
        TargetShard = Strike rem 4,
        case uos_zlp_router:shard_health(TargetShard) of
            {ok, #{os_pid := VictimPid}} when VictimPid > 0 ->
                uos_zlp_router:gleam_kill9_os_pid(VictimPid);
            _ ->
                ok
        end,
        timer:sleep(18)
    end, lists:seq(0, 5)),
    Counts = [receive {zlp_chaos_done, W, C} -> C after 15000 -> error(chaos_hang) end || W <- Workers],
    timer:sleep(80),
    HealthyPids = [
        begin
            {ok, #{os_pid := P, excl := 1}} = uos_zlp_router:shard_health(S),
            P
        end || S <- [0, 1, 2, 3]
    ],
    case length(HealthyPids) =:= 4 of
        true -> {ok, lists:sum(Counts)};
        false -> {error, <<"shards_not_healed">>}
    end.

%% Verify upgraded indrajaal_native_zenoh.erl bridge (open_session, subscribe, put, get)
test_indrajaal_native_zenoh_bridge() ->
    {ok, Session} = indrajaal_native_zenoh:open_session(#{mode => zlp_v3}),
    SubKey = <<"uos/sandbox/zlp_v3_gleam_test/ffi/**">>,
    PubKey = <<"uos/sandbox/zlp_v3_gleam_test/ffi/node1">>,
    {ok, {zlp_subscription, ShardId, _}} = indrajaal_native_zenoh:subscribe(Session, SubKey, self()),
    timer:sleep(60),
    uos_zlp_router:gleam_flush_zenoh_pushes(),
    ok = indrajaal_native_zenoh:put(Session, PubKey, <<"{\"bridge\":\"indrajaal_native_zenoh_ok\"}">>),
    receive
        {zlp_zenoh_push, ShardId, 1, Dig, JsonBin} when Dig > 0 ->
            case binary:match(JsonBin, <<"indrajaal_native_zenoh_ok">>) of
                {_, _} -> {ok, ShardId};
                nomatch -> {error, <<"bridge_payload_mismatch">>}
            end
    after 3000 ->
        {error, <<"bridge_sse_timeout">>}
    end.
