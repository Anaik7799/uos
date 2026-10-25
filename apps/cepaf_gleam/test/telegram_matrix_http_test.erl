-module(telegram_matrix_http_test).
-include_lib("eunit/include/eunit.hrl").
fixture(Reply,Delay,T) ->
  {ok,L}=gen_tcp:listen(0,[binary,{active,false},{reuseaddr,true},{ip,{127,0,0,1}}]),
  {ok,{_,Port}}=inet:sockname(L),
  Pid=spawn(fun()->case gen_tcp:accept(L,1000) of
    {ok,S}->try {ok,_}=gen_tcp:recv(S,0,1000),timer:sleep(Delay),gen_tcp:send(S,Reply)
      after gen_tcp:close(S) end;
    _->ok end end),
  try telegram_matrix_http:get(<<"127.0.0.1">>,Port,<<"/versions">>,T,16384)
  after gen_tcp:close(L),exit(Pid,kill) end.
response(Body) -> <<"HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nContent-Length: ",
  (integer_to_binary(byte_size(Body)))/binary,"\r\nConnection: close\r\n\r\n",Body/binary>>.
actual_socket_body_test() ->
  Body = <<"{\"versions\":[\"v1.18\"]}">>,
  ?assertEqual({ok,Body},fixture(response(Body),0,500)).
non200_redirect_and_framing_refused_test() ->
  lists:foreach(fun(R)->?assertMatch({error,_},fixture(R,0,500)) end,[
    <<"HTTP/1.0 302 Found\r\nLocation: http://outside/\r\nContent-Length: 2\r\n\r\n{}">>,
    <<"HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n">>,
    <<"HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n{}">>,
    <<"HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}">>,
    <<"HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nContent-Length: 02\r\n\r\n{}">>,
    <<"HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nContent-Length: 2\r\n\r\n{}">>,
    <<"HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nContent-Encoding: gzip\r\nContent-Length: 2\r\n\r\n{}">>
  ]).
byte_header_and_utf8_bounds_test() ->
  ?assertMatch({error,_},fixture(response(binary:copy(<<"x">>,16385)),0,500)),
  ?assertMatch({error,_},fixture(response(<<255>>),0,500)),
  ?assertMatch({error,_},fixture(<<"HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nContent-Length: 5\r\n\r\n{}">>,0,500)),
  Many=iolist_to_binary(lists:duplicate(33,<<"X-A: b\r\n">>)),
  ?assertMatch({error,_},fixture(<<"HTTP/1.0 200 OK\r\n",Many/binary,"Content-Type: application/json\r\nContent-Length: 2\r\n\r\n{}">>,0,500)).
deadline_and_input_refusal_test() ->
  Started=erlang:monotonic_time(millisecond),
  ?assertMatch({error,_},fixture(response(<<"{}">>),500,100)),
  ?assert(erlang:monotonic_time(millisecond)-Started<700),
  ?assertMatch({error,_},telegram_matrix_http:get(<<"host\r\nX:1">>,80,<<"/">>,500,100)),
  ?assertMatch({error,_},telegram_matrix_http:get(<<"host">>,80,<<"/\r\nX:1">>,500,100)),
  ?assertMatch({error,_},telegram_matrix_http:get(<<"host">>,80,<<"/">>,2001,100)),
  ?assertMatch({error,_},telegram_matrix_http:get(<<"host">>,80,<<"/">>,500,16385)).

snapshot_fixture(Reply,Delay,T,Max) ->
  {ok,L}=gen_tcp:listen(0,[binary,{active,false},{reuseaddr,true},{ip,{127,0,0,1}}]),
  {ok,{_,Port}}=inet:sockname(L),
  Pid=spawn(fun()->case gen_tcp:accept(L,1000) of
    {ok,S}->try {ok,_}=gen_tcp:recv(S,0,1000),timer:sleep(Delay),gen_tcp:send(S,Reply)
      after gen_tcp:close(S) end;
    _->ok end end),
  try telegram_matrix_http:get_snapshot(<<"127.0.0.1">>,Port,<<"/versions">>,T,Max)
  after gen_tcp:close(L),exit(Pid,kill) end.

snapshot_budget_and_original_bound_test() ->
  Body=binary:copy(<<"x">>,100000),
  ?assertEqual({ok,Body},snapshot_fixture(response(Body),0,500,131072)),
  ?assertMatch({error,_},fixture(response(Body),0,500)),
  ?assertMatch({error,_},snapshot_fixture(response(binary:copy(<<"x">>,131073)),0,500,131072)),
  ?assertMatch({error,_},telegram_matrix_http:get_snapshot(<<"host">>,80,<<"/">>,500,131073)).
snapshot_framing_utf8_and_deadline_test() ->
  ?assertMatch({error,_},snapshot_fixture(<<"HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n">>,0,500,131072)),
  ?assertMatch({error,_},snapshot_fixture(response(<<255>>),0,500,131072)),
  ?assertMatch({error,_},snapshot_fixture(response(<<"{}">>),500,100,131072)).
