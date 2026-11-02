-module(finite_native_launch_test).
%% LOCAL Codex relay; private fixtures only, no production defaults.
-include_lib("eunit/include/eunit.hrl").
base()->os:getenv("UOS_FINITE_NATIVE_FIXTURE").
artifact()->os:getenv("UOS_FINITE_NATIVE_ARTIFACT").
hash(P)->{ok,B}=file:read_file(P),binary:encode_hex(crypto:hash(sha256,B),lowercase).
d(C)-> <<"sha256:",(binary:copy(<<C>>,64))/binary>>.
facts(M)->?assertEqual(<<"NONE">>,maps:get(<<"authority">>,M)),
 lists:foreach(fun(K)->?assertEqual(false,maps:get(K,M))end,[<<"authorized">>,<<"admitted">>,<<"new_effect_permission">>]).
with_poison(F)->
 Pairs=[{"LD_LIBRARY_PATH",base()}, {"LD_PRELOAD",base()++"/poison.so"},
        {"LD_AUDIT",base()++"/no-audit.so"},{"GLIBC_TUNABLES","glibc.malloc.trim_threshold=1024"},
        {"LD_UOS_PUBLIC_UNKNOWN","public"}],
 Old=[{K,os:getenv(K)}||{K,_}<-Pairs],
 try lists:foreach(fun({K,V})->true=os:putenv(K,V)end,Pairs),F()
 after lists:foreach(fun({K,false})->true=os:unsetenv(K);({K,V})->true=os:putenv(K,V)end,Old)end.
call(Worker,Db,Request)->
 G=list_to_binary(artifact()++"/guardian.exe"),W=list_to_binary(artifact()++"/"++Worker),
 L=list_to_binary(artifact()++"/finite_launcher.exe"),
 {ok,Config}=cepaf_gleam@harness@native_launch:reviewed_configuration(linux_x8664,native_storage_v1,L,hash(L),G,hash(G),W,hash(W),list_to_binary(Db)),
 Raw=iolist_to_binary(json:encode(Request)),
 {{ok,Reply},{some,{0,When}}}=cepaf_gleam@harness@native_launch:exchange_with_cleanup(Config,Raw),
 ?assert(is_integer(When)andalso When>0),json:decode(Reply).
poison_absent()->?assertEqual(false,filelib:is_file(base()++"/preload.marker")).
packaged_grants_factual_lifecycle_test()->with_poison(fun()->
 poison_absent(),Db=base()++"/composition-grants.sqlite3",
 Expires=erlang:system_time(millisecond)+60000,
 Common=#{<<"schema_version">>=>1,<<"grant_id">>=><<"composition-grant">>},
 Issue=Common#{<<"operation">>=><<"issue">>,<<"request_id">>=><<"issue-1">>,
  <<"intent_digest">>=>d($a),<<"approval_digest">>=>d($b),<<"owner_binding_digest">>=>d($c),<<"expires_utc_ms">>=>Expires},
 M1=call("release_grants_worker.exe",Db,Issue),facts(M1),?assertEqual(<<"issued">>,maps:get(<<"status">>,M1)),
 Consume=Common#{<<"operation">>=><<"consume">>,<<"request_id">>=><<"consume-1">>,
  <<"step_digest">>=>d($d),<<"epoch">>=>1,<<"generation">>=>0,<<"command">>=><<"replace:0">>},
 M2=call("release_grants_worker.exe",Db,Consume),facts(M2),?assertEqual(<<"consumed">>,maps:get(<<"status">>,M2)),
 Historical=call("release_grants_worker.exe",Db,Consume#{<<"request_id">>=><<"consume-alias">>}),facts(Historical),
 ?assertEqual(<<"already_consumed">>,maps:get(<<"status">>,Historical)),
 ?assertEqual(<<"consume-1">>,maps:get(<<"request_id">>,Historical)),
 Revoke=Common#{<<"operation">>=><<"revoke">>,<<"request_id">>=><<"revoke-1">>,<<"reason">>=><<"operator_revoked">>},
 M3=call("release_grants_worker.exe",Db,Revoke),facts(M3),?assertEqual(<<"revoked">>,maps:get(<<"status">>,M3)),
 Held=call("release_grants_worker.exe",Db,Consume#{<<"request_id">>=><<"consume-2">>,<<"step_digest">>=>d($e),<<"generation">>=>1}),
 facts(Held),?assertEqual(<<"hold">>,maps:get(<<"status">>,Held)),?assertEqual(<<"revoked">>,maps:get(<<"reason">>,Held)),
 Read=call("release_grants_worker.exe",Db,Common#{<<"operation">>=><<"lookup">>,<<"step_digest">>=>d($d)}),facts(Read),
 ?assertEqual(<<"found">>,maps:get(<<"status">>,Read)),
 Grant=maps:get(<<"grant">>,Read),?assertEqual(true,maps:get(<<"revoked">>,Grant)),
 ?assertEqual(d($a),maps:get(<<"intent_digest">>,Grant)),?assertEqual(d($b),maps:get(<<"approval_digest">>,Grant)),
 ?assertEqual(d($c),maps:get(<<"owner_binding_digest">>,Grant)),
 ?assertEqual(d($d),maps:get(<<"step_digest">>,maps:get(<<"step">>,Read))),poison_absent()
 end).
packaged_cutover_private_files_test()->with_poison(fun()->
 poison_absent(),Root=base()++"/cutover",
 lists:foreach(fun(P)->ok=file:make_dir(P),ok=file:change_mode(P,8#700)end,[Root,Root++"/files",Root++"/control",Root++"/staging"]),
 ok=file:write_file(Root++"/files/target",<<"synthetic-old">>),ok=file:change_mode(Root++"/files/target",8#600),
 ok=file:write_file(Root++"/staging/new",<<"synthetic-new">>),ok=file:change_mode(Root++"/staging/new",8#600),
 Config=Root++"/launcher.json",
 C=#{<<"schema_version">>=>1,<<"root">>=>list_to_binary(Root++"/files"),<<"state_relative">>=><<".txn">>,
  <<"control_directory">>=>list_to_binary(Root++"/control"),<<"staging_directory">>=>list_to_binary(Root++"/staging"),
  <<"transaction_id">>=>d($a),<<"candidate">>=>d($b),<<"manifest">>=>d($c)},
 ok=file:write_file(Config,json:encode(C)),ok=file:change_mode(Config,8#600),
 Common=#{<<"schema_version">>=>1,<<"transaction_id">>=>d($a),<<"candidate">>=>d($b),<<"manifest">>=>d($c),<<"epoch">>=>1},
 lists:foreach(fun({Generation,Op,Payload})->M=call("worker.exe",Config,
  Common#{<<"generation">>=>Generation,<<"operation">>=>Op,<<"payload">>=>Payload}),
  ?assertEqual(<<"ok">>,maps:get(<<"status">>,M))end,
 [{0,<<"inspect">>,#{}},{0,<<"stage">>,#{<<"edits">>=>[#{<<"relative">>=><<"target">>,<<"replacement_relative">>=><<"new">>}]}},
  {1,<<"replace_one">>,#{<<"index">>=>0}},{2,<<"verify_new">>,#{}}]),
 ?assertEqual({ok,<<"synthetic-new">>},file:read_file(Root++"/files/target")),poison_absent()
 end).

config(Worker)->
 L=list_to_binary(artifact()++"/finite_launcher.exe"),G=list_to_binary(artifact()++"/guardian.exe"),
 W=list_to_binary(Worker),
 {ok,C}=cepaf_gleam@harness@native_launch:reviewed_configuration(linux_x8664,native_storage_v1,L,hash(L),G,hash(G),W,hash(W),list_to_binary(base()++"/public-config")),C.
probe()->config(base()++"/probe").
raw(Path,Args,Input)->
 P=open_port({spawn_executable,Path},[binary,stream,use_stdio,exit_status,{args,Args}]),
 case Input of <<>>->ok;_->true=port_command(P,Input)end,
 receive_raw(P,[]).
receive_raw(P,Chunks)->receive
 {P,{data,B}}->receive_raw(P,[B|Chunks]);
 {P,{exit_status,Code}}->{Code,iolist_to_binary(lists:reverse(Chunks))}
 after 6500->try port_close(P) catch _:_ -> ok end,erlang:error(raw_timeout)end.
frame(B)-> <<(byte_size(B)):32/big,B/binary>>.
finite_environment_and_legacy_separation_test()->with_poison(fun()->
 true=os:putenv("UOS_NONLOADER_PUBLIC_SENTINEL","PUBLIC"),
 try
 {{ok,B},{some,{0,_}}}=cepaf_gleam@harness@native_launch:exchange_with_cleanup(probe(),<<"{}">>),
 ?assertEqual(#{<<"exact_environment">>=>true,<<"fd99_closed">>=>true},json:decode(B)),poison_absent(),
 G=list_to_binary(artifact()++"/guardian.exe"),W=list_to_binary(base()++"/probe"),
 {{ok,Legacy},{some,{0,_}}}=telegram_store_transport_ffi:request_with_cleanup(G,hash(G),W,hash(W),list_to_binary(base()++"/public-config"),<<"{}">>),
 ?assertEqual(false,maps:get(<<"exact_environment">>,json:decode(Legacy))),poison_absent()
 after true=os:unsetenv("UOS_NONLOADER_PUBLIC_SENTINEL")end
 end).
unknown_arch_profile_and_missing_launcher_no_fallback_test()->
 {finite_configuration,A,P,L,LH,G,GH,W,WH,D}=probe(),
 lists:foreach(fun(C)->?assertEqual({{error,<<"transport_configuration_or_spawn">>},none},
   telegram_store_transport_ffi:finite_request_with_cleanup(C,<<"{}">>))end,
 [{finite_configuration,unsupported_architecture,P,L,LH,G,GH,W,WH,D},
  {finite_configuration,A,unrecognized_profile,L,LH,G,GH,W,WH,D},
  {finite_configuration,A,P,list_to_binary(base()++"/missing"),LH,G,GH,W,WH,D},
  {finite_configuration,A,P,L,binary:copy(<<$0>>,64),G,GH,W,WH,D}]).
kernel_bounds_and_no_fallback_test()->
 L=artifact()++"/finite_launcher.exe",Probe=base()++"/probe",Cfg=base()++"/public-config",
 Valid=["linux-x86_64","native-storage-v1",Probe,Probe,Cfg,"3000"],
 lists:foreach(fun(Args)->?assertEqual({127,<<>>},raw(L,Args,frame(<<"{}">>)))end,
 [[],["--version"],["aarch64","native-storage-v1",Probe,Probe,Cfg,"3000"],
 ["linux-x86_64","unknown",Probe,Probe,Cfg,"3000"],
 ["linux-x86_64","native-storage-v1","relative",Probe,Cfg,"3000"],
 ["linux-x86_64","native-storage-v1",Probe,Probe,Cfg++"/../bad","3000"]]++
 [lists:sublist(Valid,5)++[Ms]||Ms<-["0","-1","03000","5001","9999999999999999","1x"]]),
 ?assertEqual({127,<<>>},raw(L,["linux-x86_64","native-storage-v1",base()++"/absent",Probe,Cfg,"3000"],frame(<<"{}">>))).
extra_inherited_descriptor_closed_before_guardian_test()->
 {0,<<"FD_CLOSED">>}=raw(base()++"/fd_parent",[base()++"/fd-source",artifact()++"/finite_launcher.exe",
 "linux-x86_64","native-storage-v1",base()++"/fd_guard_probe",base()++"/probe",base()++"/public-config","3000"],<<>>).
parent_environment_changes_do_not_enter_worker_test()->
 Parent=self(),M=spawn(fun Loop()->receive stop->Parent!mutator_stopped after 0->
 true=os:putenv("LD_UNRECOGNIZED_RACING","PUBLIC"),true=os:putenv("UOS_PUBLIC_RACING","PUBLIC"),
 true=os:unsetenv("LD_UNRECOGNIZED_RACING"),Loop()end end),
 try lists:foreach(fun(_)->{{ok,B},{some,{0,_}}}=cepaf_gleam@harness@native_launch:exchange_with_cleanup(probe(),<<"{}">>),
 ?assertEqual(true,maps:get(<<"exact_environment">>,json:decode(B)))end,lists:seq(1,10))
 after M!stop,receive mutator_stopped->ok after 1000->exit(M,kill)end,
 os:unsetenv("LD_UNRECOGNIZED_RACING"),os:unsetenv("UOS_PUBLIC_RACING")end.
expired_preparation_never_starts_launcher_test_()->{timeout,10,fun()->
 ?assertEqual({{error,<<"transport_configuration_or_spawn">>},none},finite_transport_delayed:finite_request_with_cleanup(probe(),<<"{}">>)),
 ?assertEqual(false,filelib:is_file(base()++"/spawn-boundary.marker"))end}.
actual_timeout_has_confirmed_guardian_cleanup_test_()->{timeout,10,fun()->
 C=config(base()++"/sleep_probe"),
 {{error,uncertain},{some,{124,When}}}=cepaf_gleam@harness@native_launch:exchange_with_cleanup(C,<<"{}">>),
 ?assert(is_integer(When)andalso When>0)end}.
