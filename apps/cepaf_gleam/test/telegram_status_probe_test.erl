-module(telegram_status_probe_test).
-include_lib("eunit/include/eunit.hrl").
run(Packets)->
  put(status_packets,Packets),
  F=fun(_)->case get(status_packets) of [P|Ps]->put(status_packets,Ps),P;[]->{error,closed} end end,
  telegram_status_probe:read_headers(F,erlang:monotonic_time(millisecond)+1000).
response(N)->{ok,{http_response,{1,1},N,<<"OK">>}}.
header(N,V)->{ok,{http_header,0,N,undefined,V}}.
complete_headers_test()->
  ?assertEqual({ok,200},run([response(200),header('Content-Type',<<"application/json">>),{ok,http_eoh}])),
  ?assertEqual({ok,503},run([response(503),{ok,http_eoh}])).
headers_do_not_consume_body_test()->
  ?assertEqual({ok,200},run([response(200),{ok,http_eoh},{ok,<<"CANARY_BODY">>}])),
  ?assertEqual([{ok,<<"CANARY_BODY">>}],get(status_packets)).
reject_malformed_or_incomplete_test()->
  ?assertMatch({error,_},run([{ok,<<"HTTP garbage">>}])),
  ?assertMatch({error,_},run([response(200)])),
  ?assertMatch({error,_},run([response(200),{ok,{http_error,<<"private">>}}])).
status_and_reason_bounds_test()->
  ?assertMatch({error,_},run([response(199),{ok,http_eoh}])),
  ?assertMatch({error,_},run([response(600),{ok,http_eoh}])),
  ?assertMatch({error,_},run([{ok,{http_response,{2,0},200,<<"OK">>}},{ok,http_eoh}])),
  ?assertMatch({error,_},run([{ok,{http_response,{1,1},200,binary:copy(<<"a">>,1025)}},{ok,http_eoh}])).
header_count_and_bytes_test()->
  H=header(<<"x">>,<<"y">>),
  ?assertEqual({ok,200},run([response(200)]++lists:duplicate(32,H)++[{ok,http_eoh}])),
  ?assertMatch({error,_},run([response(200)]++lists:duplicate(33,H)++[{ok,http_eoh}])),
  ?assertEqual({ok,200},run([response(200),header(<<"x">>,binary:copy(<<"v">>,16383)),{ok,http_eoh}])),
  ?assertMatch({error,_},run([response(200),header(<<"x">>,binary:copy(<<"v">>,16384)),{ok,http_eoh}])).
header_types_and_private_errors_test()->
  ?assertEqual({ok,200},run([response(200),header("X-Test","value"),{ok,http_eoh}])),
  ?assertMatch({error,_},run([response(200),header(42,<<"x">>),{ok,http_eoh}])),
  ?assertEqual({error,<<"recv_failed">>},run([{error,{secret,<<"CANARY">>}}])).
expired_deadline_does_not_receive_test()->
  ?assertEqual({error,<<"timeout">>},telegram_status_probe:read_headers(
    fun(_)->error(should_not_receive) end,erlang:monotonic_time(millisecond)-1)).
target_and_timeout_allowlist_test()->
  ?assertEqual({error,<<"unknown_target">>},telegram_status_probe:probe(<<"http://evil/">>,100)),
  ?assertEqual({error,<<"invalid_timeout">>},telegram_status_probe:probe(<<"cockpit">>,99)),
  ?assertEqual({error,<<"invalid_timeout">>},telegram_status_probe:probe(<<"cockpit">>,1501)).
bounded_stalled_reader_is_reaped_test()->
  Parent=self(),
  Start=erlang:monotonic_time(millisecond),
  ?assertMatch({error,_},uos_openrouter_ffi:bounded_call(
    fun(D)->Parent!{timed_owner,self()},telegram_status_probe:read_headers(fun(_)->receive never->never end end,D) end,100)),
  ?assert(erlang:monotonic_time(millisecond)-Start<1000),
  receive {timed_owner,P}->?assertNot(erlang:is_process_alive(P)) after 1000->error(no_owner) end.

caller_death_reaps_reader_test()->
  Parent=self(),
  Caller=spawn(fun()->
    uos_openrouter_ffi:bounded_call(fun(D)->
      Parent!{status_owner,self()},
      telegram_status_probe:read_headers(fun(_)->receive never->never end end,D)
    end,5000)
  end),
  Owner=receive {status_owner,P}->P after 1000->exit(Caller,kill),error(no_owner) end,
  Mon=erlang:monitor(process,Owner),
  exit(Caller,kill),
  receive {'DOWN',Mon,process,Owner,_}->ok after 1000->exit(Owner,kill),error(owner_not_reaped) end.
