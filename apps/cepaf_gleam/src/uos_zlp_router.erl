-module(uos_zlp_router).
-export([
    is_binary_available/0,
    verify_frame/3, verify_frame_on_shard/4,
    eval_scale_and_risk/13,
    heavy_graph_digest/3,
    zenoh_subscribe/2, zenoh_publish/2, zenoh_get/1,
    shard_health/1, reset_shard/1,
    %% Strongly-typed Gleam FFI tuple wrappers
    gleam_ensure_started/1, gleam_stop/0, gleam_is_running/0, gleam_is_binary_available/0,
    gleam_verify_frame/3, gleam_verify_frame_on_shard/4,
    gleam_eval_scale_and_risk/13,
    gleam_heavy_graph_digest/3,
    gleam_zenoh_subscribe/2, gleam_zenoh_publish/2, gleam_zenoh_get/1,
    gleam_shard_health/1, gleam_reset_shard/1,
    gleam_await_zenoh_push/1, gleam_flush_zenoh_pushes/0, gleam_kill9_os_pid/1
]).

is_binary_available() ->
    case uos_zlp_shard:resolve_port_executable() of
        {ok, _} -> true;
        {error, _} -> false
    end.

shard_count() ->
    persistent_term:get(uos_zlp_shard_count, 4).

pick_stateless_shard() ->
    N = shard_count(),
    erlang:system_info(scheduler_id) rem N.

pick_topic_shard(TopicBin) ->
    N = shard_count(),
    erlang:phash2(TopicBin, N).

call_shard(ShardId, Msg, Timeout) ->
    Name = uos_zlp_shard:shard_name(ShardId),
    try
        gen_server:call(Name, Msg, Timeout)
    catch
        exit:{noproc, _} -> {error, zlp_shard_not_running};
        exit:{{port_crashed, Code}, _} -> {error, {port_crashed, Code}};
        exit:{Reason, _} -> {error, {zlp_call_exit, Reason}}
    end.

verify_frame(SeqId, CheckJsonDepthBool, PayloadBin) ->
    verify_frame_on_shard(pick_stateless_shard(), SeqId, CheckJsonDepthBool, PayloadBin).

verify_frame_on_shard(ShardId, SeqId, CheckJsonDepthBool, PayloadBin) ->
    Flags = case CheckJsonDepthBool of true -> 1; false -> 0 end,
    call_shard(ShardId, {rpc, 16#01, Flags, SeqId, PayloadBin}, 5000).

eval_scale_and_risk(Writers, Reviewers, IsWriter, SpentUusd, NowUs, LeaseUs,
                    SafeRdy, DepRdy, Crit, Stpa, Fmea, Dep, Impact) ->
    IW = case IsWriter of true -> 1; false -> 0 end,
    SR = case SafeRdy of true -> 1; false -> 0 end,
    DR = case DepRdy of true -> 1; false -> 0 end,
    Bin = <<Writers:32/big, Reviewers:32/big, IW:8, SpentUusd:64/big, NowUs:64/big, LeaseUs:64/big,
            SR:8, DR:8, Crit:32/big, Stpa:32/big, Fmea:32/big, Dep:32/big, Impact:32/big>>,
    call_shard(pick_stateless_shard(), {rpc, 16#02, 0, 0, Bin}, 5000).

heavy_graph_digest(ShardId, Rounds, PayloadBin) ->
    call_shard(ShardId, {rpc, 16#05, 0, Rounds, PayloadBin}, 10000).

zenoh_subscribe(TopicBin, SubscriberPid) ->
    ShardId = pick_topic_shard(TopicBin),
    Res = call_shard(ShardId, {subscribe_zenoh, TopicBin, SubscriberPid}, 5000),
    case Res of
        {error, _} ->
            case ets:whereis(uos_zlp_subscriptions) of
                undefined -> ok;
                _ -> ets:delete_object(uos_zlp_subscriptions, {ShardId, TopicBin, SubscriberPid})
            end;
        _ ->
            ok
    end,
    {ShardId, Res}.

zenoh_publish(TopicBin, JsonBodyBin) ->
    TLen = byte_size(TopicBin),
    Payload = <<TLen:16/big, TopicBin/binary, JsonBodyBin/binary>>,
    call_shard(pick_topic_shard(TopicBin), {rpc, 16#13, 0, 0, Payload}, 5000).

zenoh_get(TopicBin) ->
    call_shard(pick_topic_shard(TopicBin), {rpc, 16#14, 0, 0, TopicBin}, 5000).

shard_health(ShardId) ->
    case call_shard(ShardId, {rpc, 16#0C, 0, 0, <<>>}, 5000) of
        {ok, #{excl := Excl, value := Packed}} ->
            OsPid = Packed bsr 32,
            ActiveSubs = (Packed bsr 16) band 16#FFFF,
            InFlightHeavy = Packed band 16#FFFF,
            {ok, #{os_pid => OsPid, active_subs => ActiveSubs, in_flight_heavy => InFlightHeavy, excl => Excl}};
        Err ->
            Err
    end.

reset_shard(ShardId) ->
    call_shard(ShardId, {rpc, 16#FF, 0, 0, <<>>}, 5000).

%% ── Strongly-Typed Gleam FFI Tuple Wrappers ──

format_reason(Reason) ->
    unicode:characters_to_binary(io_lib:format("~p", [Reason])).

map_receipt_result({ok, #{excl := Excl, lane_or_sub := Sub, value := Val}}) ->
    {ok, {zlp_receipt, Excl, Sub, Val}};
map_receipt_result({error, {zlp_refused, Code, Excl, Val}}) ->
    {error, {zlp_refusal, Code, Excl, Val, <<"zlp_refused">>}};
map_receipt_result({error, {port_crashed, ExitCode}}) ->
    {error, {zlp_refusal, 254, 0, ExitCode, <<"port_crashed">>}};
map_receipt_result({error, Reason}) ->
    {error, {zlp_refusal, 255, 0, 0, format_reason(Reason)}}.

gleam_ensure_started(NumShards) ->
    case uos_zlp_sup:ensure_started(NumShards) of
        {ok, _Pid} -> {ok, NumShards};
        {error, Reason} -> {error, format_reason(Reason)}
    end.

gleam_stop() ->
    uos_zlp_sup:stop(),
    nil.

gleam_is_running() ->
    uos_zlp_sup:is_running().

gleam_is_binary_available() ->
    is_binary_available().

gleam_verify_frame(SeqId, CheckJsonDepthBool, PayloadBin) ->
    map_receipt_result(verify_frame(SeqId, CheckJsonDepthBool, PayloadBin)).

gleam_verify_frame_on_shard(ShardId, SeqId, CheckJsonDepthBool, PayloadBin) ->
    map_receipt_result(verify_frame_on_shard(ShardId, SeqId, CheckJsonDepthBool, PayloadBin)).

gleam_eval_scale_and_risk(Writers, Reviewers, IsWriter, SpentUusd, NowUs, LeaseUs,
                          SafeRdy, DepRdy, Crit, Stpa, Fmea, Dep, Impact) ->
    map_receipt_result(eval_scale_and_risk(
        Writers, Reviewers, IsWriter, SpentUusd, NowUs, LeaseUs,
        SafeRdy, DepRdy, Crit, Stpa, Fmea, Dep, Impact
    )).

gleam_heavy_graph_digest(ShardId, Rounds, PayloadBin) ->
    map_receipt_result(heavy_graph_digest(ShardId, Rounds, PayloadBin)).

gleam_zenoh_subscribe(TopicBin, SubscriberPid) ->
    {ShardId, Res} = zenoh_subscribe(TopicBin, SubscriberPid),
    case map_receipt_result(Res) of
        {ok, Receipt} -> {ok, {ShardId, Receipt}};
        {error, Refusal} -> {error, Refusal}
    end.

gleam_zenoh_publish(TopicBin, JsonBodyBin) ->
    map_receipt_result(zenoh_publish(TopicBin, JsonBodyBin)).

gleam_zenoh_get(TopicBin) ->
    case zenoh_get(TopicBin) of
        {ok, #{excl := Excl, lane_or_sub := Sub, value := Val, body := BodyBin}} ->
            {ok, {{zlp_receipt, Excl, Sub, Val}, BodyBin}};
        Other ->
            map_receipt_result(Other)
    end.

gleam_shard_health(ShardId) ->
    case shard_health(ShardId) of
        {ok, #{os_pid := OsPid, active_subs := Subs, in_flight_heavy := Heavy, excl := Excl}} ->
            {ok, {zlp_shard_health, OsPid, Subs, Heavy, Excl}};
        Other ->
            map_receipt_result(Other)
    end.

gleam_reset_shard(ShardId) ->
    map_receipt_result(reset_shard(ShardId)).

gleam_flush_zenoh_pushes() ->
    receive
        {zlp_zenoh_push, _, _, _, _} -> gleam_flush_zenoh_pushes()
    after 0 ->
        nil
    end.

gleam_await_zenoh_push(TimeoutMs) ->
    receive
        {zlp_zenoh_push, ShardId, Excl, Digest, JsonBin} ->
            {ok, {zlp_push_event, ShardId, Excl, Digest, JsonBin}}
    after TimeoutMs ->
        {error, nil}
    end.

gleam_kill9_os_pid(OsPid) when is_integer(OsPid), OsPid > 1 ->
    _ = os:cmd("kill -9 " ++ integer_to_list(OsPid)),
    nil.
