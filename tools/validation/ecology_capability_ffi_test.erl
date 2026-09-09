-module(ecology_capability_ffi_test).
-include_lib("eunit/include/eunit.hrl").

root() -> ecology_capability_ffi:uos_root().
fixture(Mode, Extra, Ms) ->
    Root=root(),
    ecology_capability_ffi:run_bounded(
      <<Root/binary,"/toolchains/opam-ocaml/bin/ocaml">>,
      [<<"-I">>,<<"+unix">>,<<Root/binary,"/tools/validation/ecology_process_fixture.ml">>,Mode]++Extra,Ms).

absolute_deadline_test() ->
    Start=erlang:monotonic_time(millisecond),
    ?assertEqual({error,<<"timeout">>},fixture(<<"drip">>,[],150)),
    ?assert(erlang:monotonic_time(millisecond)-Start<1000).

output_bound_test() ->
    ?assertMatch({error,_},fixture(<<"flood">>,[],1000)).

process_tree_reaped_test() ->
    Marker= <<"/tmp/uos-ecology-descendant-",(integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    ?assertEqual({error,<<"timeout">>},fixture(<<"tree">>,[Marker],150)),
    timer:sleep(1100),
    ?assertEqual(false,filelib:is_file(Marker)).

invalid_deadline_and_executable_test() ->
    ?assertEqual({error,<<"invalid_resource_bound">>},ecology_capability_ffi:run_bounded(<<"/bin/true">>,[],0)),
    ?assertEqual(false,ecology_capability_ffi:probe_executable(<<"/tmp">>)).

ets_cas_and_aba_test() ->
    ecology_capability_ffi:ets_init(),
    Req=#{<<"namespace">>=><<"test">>,<<"key">>=><<"cas">>,<<"value">>=>42},
    Put=fun(R)->{ok,J}=ecology_capability_ffi:ets_request(iolist_to_binary(json:encode(R))),json:decode(J) end,
    #{<<"version">>:=Version}=Put(Req#{<<"operation">>=><<"put">>}),
    Self=self(),
    [spawn(fun()->Self!{cas,ecology_capability_ffi:ets_request(iolist_to_binary(json:encode(
      Req#{<<"operation">>=><<"compare_exchange">>,<<"expected_version">>=>Version}))) } end)||_<-lists:seq(1,20)],
    Results=[receive {cas,R}->R after 1000->error(timeout) end||_<-lists:seq(1,20)],
    ?assertEqual(1,length([ok||{ok,_}<-Results])),
    Put(Req#{<<"operation">>=><<"delete">>}),
    #{<<"version">>:=New}=Put(Req#{<<"operation">>=><<"put">>}),
    ?assert(New>Version),
    ?assertEqual({error,<<"version_conflict">>},ecology_capability_ffi:ets_request(iolist_to_binary(json:encode(
      Req#{<<"operation">>=><<"compare_exchange">>,<<"expected_version">>=>Version})))),
    Put(Req#{<<"operation">>=><<"delete">>}).

max_real_graph_test_() -> {timeout,40,fun()->
    Input= <<"{\"operation\":\"linear_softmax\",\"features\":[2.0,-1.0],\"weights\":[[1.0,0.0],[0.0,1.0]],\"bias\":[0.5,-0.5]}">>,
    {ok,Body}=ecology_capability_ffi:max_request(Input),
    #{<<"backend">>:= <<"modular_max_graph">>,<<"probabilities">>:=[P,_]}=json:decode(Body),
    ?assert(abs(P-1/(1+math:exp(-4)))<0.000001)
end}.
