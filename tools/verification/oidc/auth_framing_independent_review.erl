%% Independent fixed-framing checks against the actual connection adapter.
%% Only owned ephemeral loopback sockets are used. No live service is contacted.
-module(auth_framing_independent_review).
-export([run/0]).
-define(APP, indrajaal_gleam_web).

run() ->
  Framing = framing_checks(),
  SocketResults = [fixed_socket_exact_remainder(), closed_socket(), stalled_socket(), trickle_deadline()],
  Results = Framing ++ SocketResults ++ auth_ingress_test_ffi:with_oidc_env(fun chain_checks/0),
  Passed = length([ok || #{passed := true} <- Results]),
  io:put_chars(json:encode(#{schema => <<"uos-auth-framing-independent/v1">>,
    otp_release => list_to_binary(erlang:system_info(otp_release)),
    total => length(Results), passed => Passed, failed => length(Results)-Passed,
    network_scope => <<"owned 127.0.0.1 ephemeral sockets only">>, results => Results})),
  io:nl(),
  case Passed =:= length(Results) of true -> 0; false -> 1 end.

framing_checks() ->
  ChunkPayload = binary:copy(<<"x">>,65537),
  ChunkWire = <<"10001\r\n",ChunkPayload/binary,"\r\n0\r\n\r\n">>,
  BadCases = [
    {"expect_continue_rejected_before_read",[{<<"expect">>,<<"100-continue">>},{<<"content-length">>,<<"1">>}],<<>>,417},
    {"expect_case_insensitive",[{<<"ExPeCt">>,<<"100-continue">>},{<<"content-length">>,<<"1">>}],<<>>,417},
    {"expect_empty_rejected",[{<<"expect">>,<<>>}],<<>>,417},
    {"expect_unknown_rejected",[{<<"expect">>,<<"unknown">>}],<<>>,417},
    {"expect_duplicate_rejected",[{<<"expect">>,<<"100-continue">>},{<<"expect">>,<<"100-continue">>}],<<>>,417},
    {"exact_prior_chunked_counterexample",[{<<"transfer-encoding">>,<<"chunked">>}],ChunkWire,400},
    {"transfer_encoding_case_insensitive",[{<<"Transfer-Encoding">>,<<"CHUNKED">>}],<<>>,400},
    {"transfer_encoding_empty_rejected",[{<<"transfer-encoding">>,<<>>}],<<>>,400},
    {"transfer_encoding_identity_rejected",[{<<"transfer-encoding">>,<<"identity">>}],<<>>,400},
    {"transfer_encoding_and_length_rejected",[{<<"transfer-encoding">>,<<"chunked">>},{<<"content-length">>,<<"1">>}],ChunkWire,400},
    {"duplicate_same_length",[{<<"content-length">>,<<"1">>},{<<"content-length">>,<<"1">>}],<<"x">>,400},
    {"duplicate_case_length",[{<<"Content-Length">>,<<"1">>},{<<"content-length">>,<<"2">>}],<<"x">>,400},
    {"comma_length",[{<<"content-length">>,<<"1,1">>}],<<"x">>,400},
    {"length_plus_sign",[{<<"content-length">>,<<"+1">>}],<<"x">>,400},
    {"length_minus_sign",[{<<"content-length">>,<<"-1">>}],<<>>,400},
    {"length_whitespace",[{<<"content-length">>,<<" 1">>}],<<"x">>,400},
    {"length_empty",[{<<"content-length">>,<<>>}],<<>>,400},
    {"length_nondigit",[{<<"content-length">>,<<"1x">>}],<<"x">>,400},
    {"length_unicode_digits",[{<<"content-length">>,<<217,161>>}],<<"x">>,400},
    {"length_exceeds_cap",[{<<"content-length">>,<<"65537">>}],ChunkPayload,413},
    {"length_huge_integer",[{<<"content-length">>,<<"9999999999999999999999999999">>}],<<>>,413},
    {"initial_exceeds_declared",[{<<"content-length">>,<<"1">>}],<<"xx">>,400},
    {"explicit_zero_rejects_initial",[{<<"content-length">>,<<"0">>}],<<"x">>,400},
    {"initial_over_cap_rejected",[{<<"content-length">>,<<"65536">>}],ChunkPayload,400}
  ],
  Bad = [assert_rejection(Name,conn(Headers,Initial,unused_socket,tcp),Status)
    || {Name,Headers,Initial,Status} <- BadCases],
  GoodCases = [
    {"absent_framing_drops_initial",[],<<"unframed">>,<<>>},
    {"absent_framing_drops_prior_chunk_wire",[],ChunkWire,<<>>},
    {"explicit_zero_empty",[{<<"content-length">>,<<"0">>}],<<>>,<<>>},
    {"valid_fixed_body",[{<<"content-length">>,<<"5">>}],<<"hello">>,<<"hello">>},
    {"leading_zero_decimal_fixed_body",[{<<"content-length">>,<<"0005">>}],<<"hello">>,<<"hello">>},
    {"case_insensitive_length",[{<<"CONTENT-LENGTH">>,<<"5">>}],<<"hello">>,<<"hello">>},
    {"exact_byte_limit",[{<<"content-length">>,<<"65536">>}],binary:copy(<<"x">>,65536),binary:copy(<<"x">>,65536)},
    {"non_utf8_ingestion_preserves_bytes",[{<<"content-length">>,<<"1">>}],<<255>>,<<255>>}
  ],
  Good = [assert_admission(Name,conn(Headers,Initial,unused_socket,tcp),Expected)
    || {Name,Headers,Initial,Expected} <- GoodCases],
  StreamReq=setelement(4,conn([{<<"content-length">>,<<"1">>}],<<>>,unused_socket,tcp),
    {connection,{stream,unused_selector,<<>>,1,0},unused_socket,tcp,unused_factory}),
  UnsupportedReq=conn([{<<"content-length">>,<<"1">>}],<<>>,unused_socket,unsupported),
  Bad ++ Good ++ [
    assert_rejection("stream_body_rejected",StreamReq,400),
    assert_rejection("unsupported_transport_rejected_before_handler",UnsupportedReq,400)
  ].

assert_rejection(Name,Req,ExpectedStatus) ->
  erase(next_calls),
  R=?APP:handle_bounded_connection_request(Req,fun next/1),
  result(Name,element(2,R)=:=ExpectedStatus andalso get(next_calls)=:=undefined,
    #{status=>element(2,R),handler_called=>(get(next_calls)=/=undefined)}).
assert_admission(Name,Req,ExpectedBody) ->
  erase(next_calls),
  R=?APP:handle_bounded_connection_request(Req,fun next/1),
  result(Name,element(2,R)=:=299 andalso get(next_calls)=:=1 andalso response_body(R)=:=ExpectedBody,
    #{status=>element(2,R),body_bytes=>byte_size(response_body(R)),handler_calls=>get(next_calls)}).
next(Req) ->
  put(next_calls,case get(next_calls) of undefined->1; N->N+1 end),
  {response,299,[{<<"x-repeat">>,<<"first">>},{<<"x-repeat">>,<<"second">>}],
    {bytes,'gleam@bytes_tree':from_bit_array(element(4,Req))}}.

fixed_socket_exact_remainder() ->
  with_socket(fun(Client,Server) ->
    ok=gen_tcp:send(Client,<<"lloTAIL">>),
    Headers=[{<<"content-length">>,<<"5">>},{<<"authorization">>,<<"Bearer public-fixture">>}],
    Req=conn(Headers,<<"he">>,Server,tcp),
    erase(next_calls),
    R=?APP:handle_bounded_connection_request(Req,fun(Bounded) ->
      true=setelement(4,Bounded,element(4,Req))=:=Req,
      next(Bounded)
    end),
    Tail=gen_tcp:recv(Server,4,250),
    result("socket_reads_only_declared_remainder",element(2,R)=:=299 andalso
      response_body(R)=:= <<"hello">> andalso Tail=:={ok,<<"TAIL">>} andalso
      element(3,R)=:=[{<<"x-repeat">>,<<"first">>},{<<"x-repeat">>,<<"second">>}],
      #{status=>element(2,R),body_bytes=>byte_size(response_body(R)),leftover_bytes=>case Tail of {ok,B}->byte_size(B);_->0 end})
  end).

closed_socket() ->
  with_socket(fun(Client,Server) ->
    ok=gen_tcp:send(Client,<<"x">>),
    ok=gen_tcp:close(Client),
    assert_rejection("closed_incomplete_socket_rejected",conn([{<<"content-length">>,<<"2">>}],<<>>,Server,tcp),400)
  end).

stalled_socket() ->
  with_socket(fun(_Client,Server) ->
    Start=erlang:monotonic_time(millisecond),
    R=assert_rejection("actual_wrapper_stalled_socket_408",
      conn([{<<"content-length">>,<<"1">>}],<<>>,Server,tcp),408),
    Elapsed=erlang:monotonic_time(millisecond)-Start,
    R#{passed := maps:get(passed,R) andalso Elapsed>=4900 andalso Elapsed<6500,
       elapsed_ms=>Elapsed,configured_deadline_ms=>5000}
  end).

trickle_deadline() ->
  with_socket(fun(Client,Server) ->
    {Sender,Monitor}=spawn_monitor(fun() ->
      receive stop -> ok after 100 -> gen_tcp:send(Client,<<"a">>) end,
      receive stop -> ok after 150 -> gen_tcp:send(Client,<<"b">>) end,
      receive stop -> ok after 150 -> gen_tcp:send(Client,<<"c">>) end
    end),
    Start=erlang:monotonic_time(millisecond),
    Read=indrajaal_web_ffi:read_fixed_request_body(
      conn([{<<"content-length">>,<<"4">>}],<<>>,Server,tcp),4,65536,450),
    Elapsed=erlang:monotonic_time(millisecond)-Start,
    Sender!stop,
    receive {'DOWN',Monitor,process,Sender,_}->ok after 1000->erlang:error(sender_not_reaped) end,
    result("partial_progress_does_not_extend_deadline",
      Read=:={error,fixed_body_read_timeout} andalso Elapsed>=400 andalso Elapsed<1200,
      #{elapsed_ms=>Elapsed,configured_deadline_ms=>450,received_outcome=>element(2,Read)})
  end).

chain_checks() ->
  %% Public, committed interoperability fixture; no operator token or key.
  Token = <<"eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6MjAwMDAwMDMwMCwiaXNzIjoiaHR0cHM6Ly9pc3N1ZXIuZXhhbXBsZS9yZWFsbXMvYzNpIiwiYXVkIjoiYzNpLXdpc3AtYXBpIn0.mfaSQdB3lV47YleIzp9Kr3dFpBgZ87aiQBr3F_BMWdOUjAGJwoiRifw8ZtZcazFPL1gxFfgSQSz04xDhCVtuAg">>,
  Cases = [
    {"connection_to_auth_rejects_static_downgrade",<<"/api/review/nonexistent">>,<<>>,<<"must-not-authorize-in-oidc-mode">>,401},
    {"connection_to_auth_accepts_signed_unknown_route",<<"/api/review/nonexistent">>,<<>>,Token,404},
    {"connection_to_auth_preserves_body_validation",<<"/api/v1/plan/update">>,<<"{\"id\":\"fixture-only\",\"status\":\"deliberately_invalid\"}">>,Token,400},
    {"connection_to_http_rejects_non_utf8",<<"/api/review/nonexistent">>,<<255>>,Token,400}
  ],
  [begin
    Headers=[{<<"content-length">>,integer_to_binary(byte_size(Body))},
             {<<"authorization">>,<<"Bearer ",Credential/binary>>}],
    Request=setelement(9,setelement(8,conn(Headers,Body,unused_socket,tcp),Path),none),
    R=?APP:handle_bounded_connection_request(Request,fun ?APP:handle_c3i_http_request/1),
    BodyCheck=case Name of
      "connection_to_auth_preserves_body_validation" ->
        binary:match(response_body(R),<<"invalid status: deliberately_invalid">>) =/= nomatch;
      _ -> true
    end,
    result(Name,element(2,R)=:=Expected andalso BodyCheck,#{status=>element(2,R)})
  end || {Name,Path,Body,Credential,Expected} <- Cases].

with_socket(Fun) ->
  {ok,L}=gen_tcp:listen(0,[binary,{active,false},{ip,{127,0,0,1}}]),
  try
    {ok,{{127,0,0,1},Port}}=inet:sockname(L),
    {ok,C}=gen_tcp:connect({127,0,0,1},Port,[binary,{active,false}],1000),
    try
      {ok,S}=gen_tcp:accept(L,1000),
      try Fun(C,S) after gen_tcp:close(S) end
    after gen_tcp:close(C) end
  after gen_tcp:close(L) end.
conn(Headers,Initial,Socket,Transport) ->
  {request,post,Headers,{connection,{initial,Initial},Socket,Transport,unused_factory},
   http,<<"review.invalid">>,none,<<"/api/review/nonexistent">>,{some,<<"preserved=1">>}}.
response_body(R) -> {bytes,T}=element(4,R),'gleam@bytes_tree':to_bit_array(T).
result(Name,Passed,Data) -> Data#{name=>list_to_binary(Name),passed=>Passed}.
