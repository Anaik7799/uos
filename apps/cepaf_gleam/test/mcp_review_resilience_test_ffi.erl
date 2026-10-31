%% Test-only trace-order and paired-kill observer. No production hooks.
-module(mcp_review_resilience_test_ffi).
-export([guardian_publication/0,classification_cache_budget/1,
         ungranted_private_while_suspended/0,chronological_replay/0,
         private_owner_fault/2,native_guardian_recovery/0,
         registration_publication/0,native_minimum_budget/0]).

registration_publication() ->
    %% A trusted child can finish startup before its enclosing tree loses
    %% registration. Recover from the old pre-registration publication too.
    Existing=whereis(uos_mcp_runtime_gateway_sup),
    Sup=case Existing of undefined->P=spawn(fun()->receive stop->ok end end),register(uos_mcp_runtime_gateway_sup,P),P;_->Existing end,
    Before=persistent_term:get(uos_mcp_runtime_gateway_subject,none),
    Box=mcp_stdio_ffi:gateway_handle_new(),
    WinnerSubject=case Existing of undefined->{some,{subject,self(),make_ref()}};_->Before end,
    mcp_stdio_ffi:gateway_handle_set(Box,WinnerSubject),
    OldHandle=ets:lookup(uos_mcp_gateway_handles_ets,Sup),
    mcp_stdio_ffi:gateway_handle_register(Sup,Box),
    Loser=spawn(fun()->receive stop->ok end end),
    persistent_term:put(uos_mcp_runtime_gateway_subject,{some,{subject,Loser,make_ref()}}),
    try
        false=mcp_stdio_ffi:register_or_stop_supervisor(Loser),
        false=is_process_alive(Loser),
        WinnerSubject=persistent_term:get(uos_mcp_runtime_gateway_subject),
        {ok,nil}
    catch C:E->{error,iolist_to_binary(io_lib:format("~p:~p",[C,E]))}
    after
        exit(Loser,kill),persistent_term:put(uos_mcp_runtime_gateway_subject,Before),
        ets:delete(uos_mcp_gateway_handles_ets,Box),
        case Existing of undefined->exit(Sup,kill);_->ets:insert(uos_mcp_gateway_handles_ets,OldHandle) end
    end.

native_minimum_budget() ->
    _=mcp_stdio_ffi:with_inflight_slot(1,fun()->ok end),
    G=whereis(uos_mcp_native_guardian),
    A=alias(),Tag=make_ref(),Deadline=erlang:monotonic_time(millisecond)+30,
    G!{native_acquire,self(),A,Tag,Deadline,50},
    try
        receive {Tag,timeout}->ok;{Tag,granted}->error(hopeless_native_request_granted)
        after 200->error(native_minimum_reply_missing) end,
        Control=make_ref(),
        G!{native_acquire,self(),A,Control,erlang:monotonic_time(millisecond)+200,1},
        receive {Control,granted}->G!{native_release,Control}
        after 200->error(viable_native_request_not_granted) end,
        {ok,nil}
    catch C:E->{error,iolist_to_binary(io_lib:format("~p:~p",[C,E]))}
    after unalias(A),G!{native_release,Tag} end.

native_guardian_recovery() ->
    _=mcp_stdio_ffi:with_inflight_slot(1,fun()->ok end),
    Old=whereis(uos_mcp_native_guardian),Mon=monitor(process,Old),exit(Old,kill),
    receive {'DOWN',Mon,process,Old,_}->ok end,
    try
        Result=mcp_stdio_ffi:run_workspace_bounded_cd(<<"/not/an/executable">>,[],<<"/home/an/NAS-setup/uos">>,100),
        case Result of {error,_}->ok;{ok,{127,_}}->ok;_->error({unexpected_missing_executable_result,Result}) end,
        P=whereis(uos_mcp_native_guardian),true=is_pid(P),true=is_process_alive(P),
        {ok,nil}
    catch C:E -> {error,iolist_to_binary(io_lib:format("~p:~p",[C,E]))}
    end.

private_owner_fault(Phase,Check) ->
    G='cepaf_gleam@mcp@runtime_gateway',true=G:ensure_started(),
    {some,Real}=persistent_term:get(uos_mcp_runtime_gateway_subject),
    {ok,RealPid}='gleam@erlang@process':subject_owner(Real),
    Key = <<"/home/an/NAS-setup/uos:",('cepaf_gleam@mcp@candidate_id':current())/binary>>,
    Table=uos_mcp_durable_ledger_ets,
    Before=[{K,V} || {K,V}<-ets:tab2list(Table),K=:={ledger,Key} orelse K=:={state,Key}],
    Tag=make_ref(),
    Fake=spawn(fun Loop() -> receive
        {Tag,Msg} when element(1,Msg)=:=snapshot -> 'gleam@erlang@process':send(Real,Msg),Loop();
        {Tag,Msg} when element(1,Msg)=:=reserve_private ->
            case Phase of <<"reserve">>->exit(fixture_owner_death);_->'gleam@erlang@process':send(Real,Msg),Loop() end;
        {Tag,Msg} when element(1,Msg)=:=commit_private ->case Phase of
            <<"late">>->timer:sleep(60),'gleam@erlang@process':send(element(3,Msg),{refused,{tool_error,<<"LATE_REPLY_FIXTURE">>,<<"late">>,retryable}});
            _->exit(fixture_owner_death)
        end
    end end),
    try
        true=is_process_alive(RealPid),
        {Elapsed,Outcome}=timer:tc(fun()->Check({subject,Fake,Tag}) end),
        case {Phase,Outcome} of
            {<<"reserve">>,{refused,{tool_error,<<"GATEWAY_RESTARTING">>,_,_}}}->ok;
            {<<"commit">>,{uncertain,_}}->ok;
            {<<"late">>,{uncertain,_}}->timer:sleep(100),
                {messages,Messages}=process_info(self(),messages),
                false=lists:any(fun({_,{refused,{tool_error,<<"LATE_REPLY_FIXTURE">>,_,_}}})->true;(_)->false end,Messages);
            _->error({wrong_owner_death_outcome,Phase,Outcome})
        end,
        case Elapsed<500000 of true->{ok,nil};false->error({owner_death_black_hole_us,Elapsed}) end
    catch C:E -> {error,iolist_to_binary(io_lib:format("~p:~p",[C,E]))}
    after exit(Fake,kill),ets:insert(Table,Before),restart_review_owner() end.

chronological_replay() ->
    G='cepaf_gleam@mcp@runtime_gateway',
    true=G:ensure_started(),
    Key = <<"/home/an/NAS-setup/uos:",('cepaf_gleam@mcp@candidate_id':current())/binary>>,
    Table=uos_mcp_durable_ledger_ets,
    [{{ledger,Key},Original}]=ets:lookup(Table,{ledger,Key}),
    [{{state,Key},OriginalState}]=ets:lookup(Table,{state,Key}),
    Call=fun(Id) ->
        Raw=iolist_to_binary(json:encode(#{jsonrpc=><<"2.0">>,id=>71,
            method=><<"tools/call">>,params=>#{name=><<"mcp_capability_inventory">>,
            arguments=>#{intent_id=>Id}}})),
        {some,Reply}=G:handle_standard_mcp_line(<<"codex">>,<<"codex">>,
            <<"/home/an/NAS-setup/uos">>,<<"wave25-fifo">>,<<"public">>,Raw,1),
        #{<<"result">>:=Result}=json:decode(Reply),
        #{<<"isError">>:=false}=Result,
        Result
    end,
    try
        _=Call(<<"fifo-probe">>),
        [{{ledger,Key},{receipt_ledger,Candidate,ProbeEntries}}]=ets:lookup(Table,{ledger,Key}),
        [{Full,Template}]=[{Id,E} || {Id,E}<-maps:to_list(ProbeEntries),
            binary:match(Id,<<":fifo-probe">>)=/=nomatch],
        Prefix=binary:part(Full,0,byte_size(Full)-byte_size(<<"fifo-probe">>)),
        Seeds=maps:from_list([begin Id=iolist_to_binary(io_lib:format("seed-~4..0B",[N])),
            {Id,setelement(2,Template,Id)} end || N<-lists:seq(0,4095)]),
        %% Select adversarial high/diverse map-order keys independently of
        %% the retention implementation. Receipt arrival order is the oracle.
        Candidates=maps:from_list([{<<Prefix/binary,"wave25-high-",(integer_to_binary(N))/binary>>,N}
            || N<-lists:seq(1,8192)]),
        Ordered=lists:reverse(maps:keys(maps:merge(Seeds,Candidates))),
        Ids=lists:sublist([Id || Id<-Ordered,maps:is_key(Id,Candidates)],20),
        true=ets:insert(Table,{{ledger,Key},{receipt_ledger,Candidate,Seeds}}),
        restart_review_owner(),
        CommittedResults=maps:from_list([{Id,Call(binary:part(Id,byte_size(Prefix),byte_size(Id)-byte_size(Prefix)))} || Id<-Ids]),
        [{{state,Key},BeforeRestart}]=ets:lookup(Table,{state,Key}),
        Seq=element(tuple_size(BeforeRestart)-1,BeforeRestart),
        CommitOrder=element(tuple_size(BeforeRestart),BeforeRestart),
        4096=map_size(CommitOrder),
        restart_review_owner(),
        [{{state,Key},AfterRestart}]=ets:lookup(Table,{state,Key}),
        Seq=element(tuple_size(AfterRestart)-1,AfterRestart),
        CommitOrder=element(tuple_size(AfterRestart),AfterRestart),
        [{{ledger,Key},Restored={receipt_ledger,_,Entries}}]=ets:lookup(Table,{ledger,Key}),
        4096=map_size(Entries),
        Retained=length([Id || Id<-Ids,maps:is_key(Id,Entries)]),
        case Retained of 20->ok;_->error({new_commits_retained,Retained,expected,20}) end,
        false=lists:any(fun(N)->maps:is_key(iolist_to_binary(io_lib:format("seed-~4..0B",[N])),Entries) end,lists:seq(0,19)),
        Parent=self(),Tag=make_ref(),
        [begin
            Entry=maps:get(Id,Entries),
            {Outcome,Restored}='cepaf_gleam@mcp@worker':run_isolated_with_receipts(
                Restored,Id,element(3,Entry),element(4,Entry),element(5,Entry),
                fun()->Parent!{Tag,reexecuted},{worker_success,<<"duplicate">>} end),
            outcome_committed=element(1,element(7,Entry)),
            Outcome=element(2,element(7,Entry))
        end || Id<-Ids],
        receive {Tag,reexecuted}->error(readonly_reexecuted) after 0->ok end,
        %% Trace the actual backend boundary during the twenty wire replays.
        {some,ReplaySubject}=persistent_term:get(uos_mcp_runtime_gateway_subject),
        {ok,ReplayOwner}='gleam@erlang@process':subject_owner(ReplaySubject),
        Session=trace:session_create(wave25_replay_execution,self(),[]),
        try
            1=trace:function(Session,{'cepaf_gleam@mcp@server',execute_route_authenticated,8},true,[local]),
            1=trace:process(Session,ReplayOwner,true,[call]),
            [begin
                Expected=maps:get(Id,CommittedResults),
                Expected=Call(binary:part(Id,byte_size(Prefix),byte_size(Id)-byte_size(Prefix)))
            end || Id<-Ids],
            Fence=trace:delivered(Session,ReplayOwner),
            receive
                {trace,ReplayOwner,call,{'cepaf_gleam@mcp@server',execute_route_authenticated,_}} -> error(wire_replay_reexecuted);
                {trace_delivered,ReplayOwner,Fence}->ok
            after 1000->error(replay_trace_timeout) end
        after trace:session_destroy(Session) end,
        [{{state,Key},AfterReplay}]=ets:lookup(Table,{state,Key}),
        Seq=element(tuple_size(AfterReplay)-1,AfterReplay),
        CommitOrder=element(tuple_size(AfterReplay),AfterReplay),
        {ok,nil}
    catch C:E:S -> {error,iolist_to_binary(io_lib:format("~p:~p ~p",[C,E,lists:sublist(S,2)]))}
    after
        ets:insert(Table,[{{ledger,Key},Original},{{state,Key},OriginalState}]),
        restart_review_owner()
    end.

restart_review_owner() ->
    {some,Subject}=persistent_term:get(uos_mcp_runtime_gateway_subject),
    {ok,Owner}='gleam@erlang@process':subject_owner(Subject),
    Mon=monitor(process,Owner),exit(Owner,kill),
    receive {'DOWN',Mon,process,Owner,_}->ok after 1000->error(owner_not_killed) end,
    wait_review_owner(Owner,1000).
wait_review_owner(_,0) -> error(owner_not_restarted);
wait_review_owner(Old,N) ->
    case persistent_term:get(uos_mcp_runtime_gateway_subject,none) of
        {some,S}->case 'gleam@erlang@process':subject_owner(S) of
            {ok,P} when P=/=Old -> case is_process_alive(P) of true->ok;false->timer:sleep(2),wait_review_owner(Old,N-2) end;
            _->timer:sleep(2),wait_review_owner(Old,N-2) end;
        _->timer:sleep(2),wait_review_owner(Old,N-2)
    end.

%% A missing capability is a caller-side refusal, not an actor query. Exercise
%% both live routes while the real owner cannot answer any mailbox message.
ungranted_private_while_suspended() ->
    Gateway='cepaf_gleam@mcp@runtime_gateway',
    Keys=["UOS_HARNESS_GRANT_PATH","UOS_HARNESS_GRANT_SHA256",
          "UOS_HARNESS_ROLE","UOS_HARNESS_PLAN","UOS_HARNESS_TASK",
          "UOS_HARNESS_WORKER","UOS_HARNESS_ATTEMPT","UOS_HARNESS_SESSION",
          "UOS_HARNESS_EPOCH"],
    Old=[{K,os:getenv(K)} || K <- Keys],
    [os:unsetenv(K) || K <- Keys],
    true=Gateway:ensure_started(),
    Published={some,Subject}=persistent_term:get(uos_mcp_runtime_gateway_subject),
    {ok,Owner}='gleam@erlang@process':subject_owner(Subject),
    ok=sys:suspend(Owner),
    {message_queue_len,Before}=process_info(Owner,message_queue_len),
    try
        [begin
             Raw=json:encode(#{jsonrpc=><<"2.0">>,id=>71,
                 method=><<"tools/call">>,params=>#{name=><<"harness_write_file">>,
                 arguments=>#{path=><<"never-written.txt">>,content=><<"no authority">>}}}),
             {Elapsed,{some,Response}}=timer:tc(fun() ->
                 Gateway:handle_standard_mcp_line(<<"codex">>,<<"codex">>,
                    <<"/home/an/NAS-setup/uos">>,<<"wave2-no-grant-suspended">>,
                    Route,iolist_to_binary(Raw),erlang:system_time(millisecond))
             end),
             case binary:match(Response,<<"ROUTE_GRANT_REQUIRED">>) of
                 nomatch -> error({expected_prequeue_grant_refusal,Route,Response});
                 _ -> ok
             end,
             true=Elapsed<500000
         end || Route <- [<<"successor">>,<<"development">>]],
        Published=persistent_term:get(uos_mcp_runtime_gateway_subject),
        {message_queue_len,Before}=process_info(Owner,message_queue_len),
        {ok,nil}
    catch Class:Reason -> {error,iolist_to_binary(io_lib:format("~p:~p",[Class,Reason]))}
    after
        ok=sys:resume(Owner),
        [case V of false->os:unsetenv(K);_->os:putenv(K,V) end || {K,V} <- Old]
    end.

%% The cache can already be warm from other tests. Four serial checkpoints
%% may build the immutable classification zero or one times, never per call.
%% Concurrent cold callers may duplicate the bounded pure construction.
classification_cache_budget(Ledger) ->
    Parent=self(),Tag=make_ref(),
    {Pid,Mon}=spawn_monitor(fun() ->
        receive {run,Tag} ->
            lists:foreach(fun(_) ->
                Ledger='cepaf_gleam@mcp@runtime_gateway':bound_receipt_ledger(Ledger)
            end,lists:seq(1,4)),
            Parent!{checkpoint_done,Tag,self()},
            receive {finish,Tag} -> ok end
        end
    end),
    Session=trace:session_create(mcp_review_classification_trace,self(),[]),
    try
        {module,'cepaf_gleam@mcp@registry'}=code:ensure_loaded('cepaf_gleam@mcp@registry'),
        1=trace:function(Session,{'cepaf_gleam@mcp@registry',all_specs,0},true,[local]),
        1=trace:process(Session,Pid,true,[call]),
        Pid!{run,Tag},
        receive
            {checkpoint_done,Tag,Pid} -> ok;
            {'DOWN',Mon,process,Pid,Why} -> error({checkpoint_worker_died,Why})
        after 3000 -> error(checkpoint_worker_timeout) end,
        Fence=trace:delivered(Session,Pid),
        Count=collect_classifications(Pid,Fence,0),
        case Count=<1 of
            true -> {ok,nil};
            false -> {error,iolist_to_binary(io_lib:format("registry_classifications=~p; budget=1; checkpoints=4",[Count]))}
        end
    catch C:E -> {error,iolist_to_binary(io_lib:format("~p",[{C,E}]))}
    after
        trace:session_destroy(Session),
        Pid!{finish,Tag},
        demonitor(Mon,[flush])
    end.

collect_classifications(Pid,Fence,Count) ->
    receive
        {trace,Pid,call,{'cepaf_gleam@mcp@registry',all_specs,[]}} ->
            collect_classifications(Pid,Fence,Count+1);
        {trace_delivered,Pid,Fence} -> Count
    after 1000 -> error(classification_trace_timeout) end.

guardian_publication() ->
    Key={review_guardian_canary,make_ref()},
    mcp_stdio_ffi:durable_initial(<<"review-tables-ready">>,fun()->nil end),
    LedgerTid=ets:whereis(uos_mcp_durable_ledger_ets),
    HandlesTid=ets:whereis(uos_mcp_gateway_handles_ets),
    Owner=whereis(uos_mcp_durable_ledger_guardian),
    Heir=ets:info(LedgerTid,heir),
    Session=trace:session_create(mcp_review_publication_trace,self(),[]),
    try
        true=is_pid(Heir),
        true=ets:insert(LedgerTid,{Key,preserved}),
        1=trace:function(Session,{erlang,register,2},true,[local]),
        1=trace:function(Session,{ets,setopts,2},true,[local]),
        1=trace:process(Session,Heir,true,[call]),
        exit(Owner,kill),
        Heir=await_guardian(Heir,erlang:monotonic_time(millisecond)+1000),
        Fence=trace:delivered(Session,Heir),
        ok=collect_order(Heir,Fence,#{},false),
        [{Key,preserved}]=ets:lookup(LedgerTid,Key),
        LedgerTid=ets:whereis(uos_mcp_durable_ledger_ets),
        HandlesTid=ets:whereis(uos_mcp_gateway_handles_ets),
        %% Publication is now the externally observed readiness boundary. A
        %% second kill at that boundary must preserve exact table identities.
        Heir2=ets:info(LedgerTid,heir),true=is_pid(Heir2),
        exit(Heir,kill),
        Heir2=await_guardian(Heir2,erlang:monotonic_time(millisecond)+1000),
        [{Key,preserved}]=ets:lookup(LedgerTid,Key),
        LedgerTid=ets:whereis(uos_mcp_durable_ledger_ets),
        HandlesTid=ets:whereis(uos_mcp_gateway_handles_ets),
        {ok,nil}
    catch C:E -> {error,iolist_to_binary(io_lib:format("~p",[{C,E}]))}
    after
        trace:session_destroy(Session),
        try ets:delete(uos_mcp_durable_ledger_ets,Key) catch _:_ -> ok end
    end.

await_guardian(Expected,Deadline) ->
    case whereis(uos_mcp_durable_ledger_guardian) of
        Expected -> Expected;
        _ -> case erlang:monotonic_time(millisecond)<Deadline of
            true -> receive after 1 -> await_guardian(Expected,Deadline) end;
            false -> error(guardian_publication_timeout)
        end
    end.

collect_order(Pid,Fence,Armed,Published) ->
    receive
        {trace,Pid,call,{ets,setopts,[Table,{heir,Backup,_Tag}]}} ->
            true=is_pid(Backup),
            collect_order(Pid,Fence,Armed#{Table=>Backup},Published);
        {trace,Pid,call,{erlang,register,[uos_mcp_durable_ledger_guardian,Pid]}} ->
            case maps:is_key(uos_mcp_durable_ledger_ets,Armed) andalso
                 maps:is_key(uos_mcp_gateway_handles_ets,Armed) of
                true -> collect_order(Pid,Fence,Armed,true);
                false -> error(guardian_published_before_heirs_armed)
            end;
        {trace_delivered,Pid,Fence} ->
            case Published of true->ok;false->error(guardian_register_trace_missing) end;
        {trace,Pid,call,_} -> collect_order(Pid,Fence,Armed,Published)
    after 1000 -> error(guardian_trace_timeout) end.
