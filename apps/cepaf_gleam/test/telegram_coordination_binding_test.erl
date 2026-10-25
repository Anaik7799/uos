-module(telegram_coordination_binding_test).
-include_lib("eunit/include/eunit.hrl").
invalid_request_test() ->
  ?assertMatch({error,_},telegram_coordination_binding:launch_eval(<<"relative">>,<<"peers">>)),
  ?assertMatch({error,_},telegram_coordination_binding:launch_eval(<<"/tmp/a",0>>,<<"peers">>)),
  ?assertMatch({error,_},telegram_coordination_binding:launch_eval(<<"/tmp/a">>,<<"send">>)).
expression_bound_test() ->
  {ok,E}=telegram_coordination_binding:launch_eval(<<"/tmp/absent-coordination-fixture">>,<<"board">>),
  ?assert(byte_size(E)=<4096),
  ?assertEqual(nomatch,binary:match(E,<<0>>)).
%% Run serially in an isolated development build. Restore exact bytes even on failure.
changed_build_bytes_refused_test() ->
  M='cepaf_gleam@harness@telegram_coordination_report',
  {module,M}=code:ensure_loaded(M),
  {M,Bytes,Path}=code:get_object_code(M),
  {ok,Eval}=telegram_coordination_binding:launch_eval(<<"/tmp/absent-coordination-fixture">>,<<"peers">>),
  <<First,Rest/binary>>=Bytes,
  try
    ok=file:write_file(Path,<<(First bxor 1),Rest/binary>>),
    ?assertMatch({error,_},telegram_coordination_binding:launch_eval(<<"/tmp/absent-coordination-fixture">>,<<"peers">>)),
    {ok,{Exit,_}}=ecology_capability_ffi:run_bounded(
      <<"/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl">>,
      [<<"+S">>,<<"2:2">>,<<"+A">>,<<"2">>,<<"-noshell">>,<<"-eval">>,Eval],3000),
    ?assertNotEqual(0,Exit)
  after ok=file:write_file(Path,Bytes) end,
  ?assertMatch({ok,_},telegram_coordination_binding:launch_eval(<<"/tmp/absent-coordination-fixture">>,<<"peers">>)).
