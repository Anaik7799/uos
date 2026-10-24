-module(telegram_store_transport_test).
-include_lib("eunit/include/eunit.hrl").
base()->case os:getenv("UOS_CANCEL_TRANSPORT_TEST_DIR") of false->"/home/an/NAS-setup/uos/var/recovery-runtime/20261001-1238-store-transport";Path->Path end.
hash(P)->{ok,B}=file:read_file(P),binary:encode_hex(crypto:hash(sha256,B),lowercase).
call(Mode,Body)->
 G=list_to_binary(base()++"/guardian"),W=list_to_binary(base()++"/fixture"),
 telegram_store_transport_ffi:request(G,hash(G),W,hash(W),
   list_to_binary(base()++"/"++Mode),Body).
eof_and_frame_test()->?assertEqual({ok,<<"{}">>},call("echo",<<"{}">>)).
maximum_frame_test()->B=binary:copy(<<"x">>,1048572),?assertEqual({ok,B},call("echo",B)).
oversize_before_spawn_test()->?assertEqual({error,<<"transport_input_bound">>},call("echo",binary:copy(<<"x">>,1048573))).
empty_test()->?assertEqual({error,<<"transport_input_bound">>},call("echo",<<>>)).
truncated_response_test()->?assertEqual({error,<<"transport_uncertain">>},call("truncated",<<"{}">>)).
trailing_response_test()->?assertEqual({error,<<"transport_uncertain">>},call("trailing",<<"{}">>)).
output_bound_test()->?assertMatch({error,_},call("flood",<<"{}">>)).
invalid_utf8_test()->?assertEqual({error,<<"transport_response_uncertain">>},call("invalid_utf8",<<"{}">>)).
nonzero_test()->?assertEqual({error,<<"transport_uncertain">>},call("nonzero",<<"{}">>)).
pin_refusal_test()->G=list_to_binary(base()++"/guardian"),W=list_to_binary(base()++"/fixture"),
 ?assertEqual({error,<<"transport_configuration_or_spawn">>},
  telegram_store_transport_ffi:request(G,binary:copy(<<"0">>,64),W,hash(W),<<"/tmp/pinned-only">>,<<"{}">>)).
fixed_deadline_test_()->{timeout,8,fun()->
 T=erlang:monotonic_time(millisecond),
 ?assertMatch({error,_},call("timeout",<<"{}">>)),
 D=erlang:monotonic_time(millisecond)-T,?assert(D>=4800),?assert(D<5700)
 end}.
group_cleanup_test_()->{timeout,3,fun()->
 Mode="tree-"++integer_to_list(erlang:system_time(nanosecond)),
 Marker=base()++"/"++Mode++".marker",?assertEqual(false,filelib:is_file(Marker)),
 ?assertEqual({ok,<<"{}">>},call(Mode,<<"{}">>)),
 timer:sleep(1100),?assertEqual(false,filelib:is_file(Marker))
 end}.
raw(Frame,Ms)->
 G=base()++"/guardian",W=base()++"/fixture",
 P=open_port({spawn_executable,G},[stream,use_stdio,exit_status,binary,
  {args,[W,base()++"/echo",integer_to_list(Ms)]}]),
 true=port_command(P,Frame),
 receive{P,{exit_status,N}}->N after 1000->try port_close(P) catch _:_ -> ok end,unknown end.
trailing_input_test()->?assertEqual(125,raw(<<2:32/big,"{}trailing-private">>,200)).
truncated_input_test()->?assertEqual(124,raw(<<4:32/big,"{}">>,100)).
oversize_header_test()->?assertEqual(125,raw(<<1048573:32/big>>,200)).
typed_entrypoint_test()->
 G=list_to_binary(base()++"/guardian"),W=list_to_binary(base()++"/fixture"),
 C='cepaf_gleam@harness@telegram_store_transport':reviewed_local_configuration(G,hash(G),W,hash(W),list_to_binary(base()++"/echo")),
 ?assertEqual({ok,<<"{}">>},'cepaf_gleam@harness@telegram_store_transport':exchange(C,<<"{}">>)),
 ?assertEqual({error,input_bound},'cepaf_gleam@harness@telegram_store_transport':exchange(C,<<>>)).
timeout_group_cleanup_test_()->{timeout,3,fun()->
 Mode="abandon-"++integer_to_list(erlang:system_time(nanosecond)),
 G=base()++"/guardian",W=base()++"/fixture",Db=base()++"/"++Mode,
 P=open_port({spawn_executable,G},[stream,use_stdio,exit_status,binary,{args,[W,Db,"150"]}]),
 true=port_command(P,<<2:32/big,"{}">>),
 receive{P,{exit_status,N}}->?assertEqual(124,N)after 1000->error(timeout)end,
 timer:sleep(1100),?assertEqual(false,filelib:is_file(Db++".marker"))
 end}.
caller_death_cleanup_test_()->{timeout,3,fun()->
 Mode="abandon-"++integer_to_list(erlang:system_time(nanosecond)),
 P=spawn(fun()->call(Mode,<<"{}">>)end),timer:sleep(100),exit(P,kill),
 timer:sleep(1100),?assertEqual(false,filelib:is_file(base()++"/"++Mode++".marker"))
 end}.


executable_upper_bound_test()->
 P=base()++"/oversize-worker-"++integer_to_list(erlang:unique_integer([positive])),
 {ok,F}=file:open(P,[write,binary,raw]),{ok,_}=file:position(F,{bof,67108864}),ok=file:write(F,<<0>>),ok=file:close(F),ok=file:change_mode(P,8#700),
 try G=list_to_binary(base()++"/guardian"),
  ?assertEqual({error,<<"transport_configuration_or_spawn">>},telegram_store_transport_ffi:request(G,hash(G),list_to_binary(P),hash(P),<<"/tmp/no-effect">>,<<"{}">>))
 after file:delete(P) end.
