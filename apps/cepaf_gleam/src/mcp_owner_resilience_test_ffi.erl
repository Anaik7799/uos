%% Development-only fault fixtures. Never used by gateway production code.
-module(mcp_owner_resilience_test_ffi).
-export([suspended_owner/0, guardian_kill_survival/2, mirrored_state/1,
         checkpoint_probe/2, with_distinct_files/1]).

-define(ROOT, "/home/an/NAS-setup/uos").
-define(GATEWAY, 'cepaf_gleam@mcp@runtime_gateway').

suspended_owner() ->
    true = ?GATEWAY:ensure_started(),
    Before = {some,Subject} = persistent_term:get(uos_mcp_runtime_gateway_subject),
    {ok,Owner} = 'gleam@erlang@process':subject_owner(Subject),
    Sup = whereis(uos_mcp_runtime_gateway_sup),
    Parent = self(), Tag = make_ref(),
    ok = sys:suspend(Owner),
    Boots = [spawn(fun() -> Parent ! {Tag,boot,?GATEWAY:ensure_started()} end)
             || _ <- lists:seq(1,32)],
    Calls = [spawn(fun() ->
        Raw = iolist_to_binary([<<"{\"jsonrpc\":\"2.0\",\"id\":" >>,
            integer_to_binary(N),<<",\"method\":\"ping\"}">>]),
        Reply = ?GATEWAY:handle_standard_mcp_line(<<"codex">>,<<"codex">>,
            <<?ROOT>>,<<"wave2-suspended-owner">>,<<"public">>,Raw,1),
        Parent ! {Tag,call,Reply}
    end) || N <- lists:seq(1,8)],
    try
        timer:sleep(2200),
        true = is_process_alive(Owner),
        Sup = whereis(uos_mcp_runtime_gateway_sup),
        Before = persistent_term:get(uos_mcp_runtime_gateway_subject),
        [receive {Tag,boot,true} -> ok after 1500 -> error(boot_racer_did_not_return) end
         || _ <- Boots],
        ok = sys:resume(Owner),
        [receive
             {Tag,call,{some,Response}} ->
                 Frame = json:decode(Response),
                 true = maps:is_key(<<"result">>,Frame),
                 false = maps:is_key(<<"error">>,Frame)
         after 1500 -> error(queued_request_failed_after_resume) end || _ <- Calls],
        true = ?GATEWAY:is_running(),
        {ok,nil}
    after
        try sys:resume(Owner) catch _:_ -> ok end,
        [exit(P,kill) || P <- Boots++Calls]
    end.

guardian_kill_survival(Key, Ledger) ->
    _ = mcp_stdio_ffi:with_inflight_slot(1,fun() -> ready end),
    Old = whereis(uos_mcp_durable_ledger_guardian),
    true = is_pid(Old),
    State = #{test_only => true, scope => guardian_fault_survival},
    nil = mcp_stdio_ffi:durable_checkpoint(Key,Ledger,State),
    Parent=self(),Tag=make_ref(),
    Worker=spawn(fun() ->
        mcp_stdio_ffi:with_inflight_slot(1,fun() ->
            Parent!{Tag,entered},receive release -> completed end
        end)
    end),
    try
        receive {Tag,entered}->ok after 1000->error(inflight_not_entered) end,
        A=persistent_term:get(uos_mcp_inflight),
        1=used_slots(A),
        {refused,{tool_error,<<"GATEWAY_OVERLOADED">>,_,_}}=
            mcp_stdio_ffi:with_inflight_slot(1,fun()->error(slot_overallocated) end),
        Mon=monitor(process,Old),exit(Old,kill),
        receive {'DOWN',Mon,process,Old,killed}->ok after 1000->error(guardian_did_not_die) end,
        ok=wait(fun()->
            P=whereis(uos_mcp_durable_ledger_guardian),is_pid(P) andalso P=/=Old
        end,500),
        [{_,Ledger}]=ets:lookup(uos_mcp_durable_ledger_ets,{ledger,Key}),
        [{_,State}]=ets:lookup(uos_mcp_durable_ledger_ets,{state,Key}),
        1=used_slots(A),
        Heir=ets:info(uos_mcp_durable_ledger_ets,heir),
        true=is_pid(Heir),true=is_process_alive(Heir),
        exit(Worker,kill),
        ok=wait(fun()->used_slots(A)=:=0 end,500),
        free=mcp_stdio_ffi:with_inflight_slot(1,fun()->free end),
        {ok,Ledger}
    after
        exit(Worker,kill),
        try ets:delete(uos_mcp_durable_ledger_ets,{ledger,Key}) catch _:_ -> ok end,
        try ets:delete(uos_mcp_durable_ledger_ets,{state,Key}) catch _:_ -> ok end
    end.

used_slots(A) ->
    length([I || I <- lists:seq(1,maps:get(size,atomics:info(A))),atomics:get(A,I)=/=0]).

wait(Predicate,Remaining) when Remaining > 0 ->
    case Predicate() of true->ok; false->timer:sleep(2),wait(Predicate,Remaining-2) end;
wait(_,_) -> error(bounded_observation_timeout).

mirrored_state(Key) ->
    case ets:lookup(uos_mcp_durable_ledger_ets,{state,Key}) of
        [{{state,Key},State}]->{some,State};
        []->none
    end.

checkpoint_probe(Key,N) ->
    [{{state,Key},State}]=ets:lookup(uos_mcp_durable_ledger_ets,{state,Key}),
    [{{ledger,Key},Ledger}]=ets:lookup(uos_mcp_durable_ledger_ets,{ledger,Key}),
    {Time,nil}=timer:tc(fun()->
        [mcp_stdio_ffi:durable_checkpoint(Key,Ledger,State)||_<-lists:seq(1,N)],nil
    end),
    {Time div N,erlang:external_size(State),
     ets:info(uos_mcp_durable_ledger_ets,memory)*erlang:system_info(wordsize)}.

with_distinct_files(Fun) ->
    Relative="var/harness/20261030-2325-mcp-resilience/wave2-r05-memory-"++
        integer_to_list(erlang:unique_integer([positive,monotonic])),
    Dir=filename:join(?ROOT,Relative),
    ok=file:make_dir(Dir),
    Paths=[filename:join(Relative,integer_to_list(I)++".md")||I<-lists:seq(1,50)],
    %% 50*128KiB exceeds4MiB, exposing permanent corpus/replay retention.
    Payload=binary:copy(<<"x">>,131072),
    try
        [ok=file:write_file(filename:join(?ROOT,P),Payload)||P<-Paths],
        Fun([unicode:characters_to_binary(P)||P<-Paths])
    after
        [file:delete(filename:join(?ROOT,P))||P<-Paths],
        file:del_dir(Dir)
    end.
