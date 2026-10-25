%% Private service-test fixtures only; production sources never import this module.
-module(telegram_budget_test_io).
-export([fixture/2]).
fixture(Db,Variant) ->
 true=is_binary(Db),
 <<"/tmp/uos_tg_service_e2e_test_",_/binary>>=Db,
 nomatch=binary:match(Db,<<"..">>),
 Exe=list_to_binary(filename:join(filename:dirname(filename:dirname(filename:dirname(code:which(?MODULE)))),"ecology_budget.exe")),
 {ok,Bytes}=file:read_file(Exe),
 Sha=binary:encode_hex(crypto:hash(sha256,Bytes),lowercase),
 Ledger= <<Db/binary,".budget.sqlite3">>,
 {ok,{observation,<<"child_exited">>,<<"confirmed">>,0,_}}=
 sa_plan_observer_ffi:observe_checked(
 <<"/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe">>,
 <<"b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be">>,
 [<<"--exe">>,Exe,<<"--sha256">>,Sha,<<"--deadline-ms">>,<<"3000">>,<<"--max-bytes">>,<<"8192">>,<<"--">>,<<"init">>,Ledger],3000,8192),
 case Variant of <<"budget_missing">> -> ok=file:delete(Ledger); _->ok end,
 Pin=case Variant of <<"budget_badsha">>->binary:copy(<<"0">>,64); _->Sha end,
 iolist_to_binary(json:encode([Exe,Pin,Ledger])).
