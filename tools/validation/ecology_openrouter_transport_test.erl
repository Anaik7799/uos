-module(ecology_openrouter_transport_test).
-include_lib("eunit/include/eunit.hrl").

%% The exact production reader runs against deterministic byte fragments.
%% No credentials, DNS, TLS or external request occurs in these fixtures.
read(Chunks)->
    Key=make_ref(),put(Key,Chunks),
    Recv=fun(_)->case get(Key) of
        []->{error,closed};
        [C|Rest]->put(Key,Rest),{ok,C}
    end end,
    try uos_openrouter_ffi:read_response(Recv,erlang:monotonic_time(millisecond)+1000)
    catch throw:{bounded_http,R}->{error,R}
    after erase(Key) end.

wire(Status,Headers,Body)->iolist_to_binary([
    "HTTP/1.1 ",integer_to_list(Status)," Status\r\n",Headers,"\r\n",Body]).
fragments(<<>>,_) -> [];
fragments(B,N) when byte_size(B)=<N -> [B];
fragments(B,N) -> <<A:N/binary,Rest/binary>>=B,[A|fragments(Rest,N)].

fixed_body_all_statuses_and_fragment_sizes_test()->
    [begin
        W=wire(Code,"Content-Length: 5\r\n",<<"hello">>),
        [?assertEqual({ok,{Code,<<"hello">>}},read(fragments(W,N)))||N<-lists:seq(1,17)]
    end || Code<-[200,206,401,429,500]].

chunked_fragmentation_test()->
    W=wire(200,"Transfer-Encoding: chunked\r\n",<<"4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n">>),
    [?assertEqual({ok,{200,<<"Wikipedia">>}},read(fragments(W,N)))||N<-lists:seq(1,31)].

close_delimited_error_body_is_supported_test()->
    ?assertEqual({ok,{503,<<"temporarily unavailable">>}},read(fragments(wire(503,[],<<"temporarily unavailable">>),3))).

redirect_is_returned_without_following_location_test()->
    ?assertEqual({ok,{302,<<>>}},read([wire(302,"Location: https://attacker.invalid/\r\nContent-Length: 0\r\n",<<>>)])).

exact_endpoint_and_header_injection_test()->
    ?assertMatch({ok,_},uos_openrouter_ffi:validate_request(get,<<"https://openrouter.ai/api/v1/models">>,<<>>,<<>>,100)),
    [?assertEqual({error,<<"endpoint_not_allowlisted">>},uos_openrouter_ffi:validate_request(get,U,<<>>,<<>>,100))
      || U<-[<<"http://openrouter.ai/api/v1/models">>,<<"https://openrouter.ai.evil/api/v1/models">>,
              <<"https://openrouter.ai/api/v1/models?redirect=1">>,<<"https://127.0.0.1/api/v1/models">>]],
    ?assertEqual({error,<<"invalid_credential_or_request_bound">>},uos_openrouter_ffi:validate_request(
        post,<<"https://openrouter.ai/api/v1/chat/completions">>,<<"key\r\nInjected: value">>,<<"{}">>,100)),
    ?assertEqual({error,<<"invalid_timeout">>},uos_openrouter_ffi:validate_request(get,<<>>,<<>>,<<>>,0)).

oversize_content_length_rejected_before_body_test()->
    ?assertEqual({error,http_byte_limit},read([wire(500,"Content-Length: 4194304\r\n",<<>>)])),
    ?assertEqual({error,http_byte_limit},read([wire(200,"Content-Length: 9999999999\r\n",<<>>)])).

wire_limit_applies_to_unframed_errors_test()->
    Header=wire(429,[],<<>>),
    ?assertEqual({error,http_byte_limit},read([Header,binary:copy(<<"x">>,4194304)])),
    ?assertEqual({error,http_byte_limit},read([wire(500,[],binary:copy(<<"x">>,4194304))])).

header_and_field_count_bounds_test()->
    ?assertMatch({error,_},read([wire(200,["X-Large: ",binary:copy(<<"x">>,16384),"\r\n"],<<>>)])),
    ?assertEqual({error,header_limit},read([wire(200,lists:duplicate(129,"X-A: a\r\n"),<<>>)])).

ambiguous_and_invalid_headers_test()->
    ?assertEqual({error,ambiguous_http_header},read([wire(200,"Content-Length: 0\r\nContent-Length: 0\r\n",<<>>)])),
    ?assertEqual({error,ambiguous_body_framing},read([wire(200,"Content-Length: 0\r\nTransfer-Encoding: chunked\r\n",<<>>)])),
    ?assertEqual({error,invalid_http_header},read([wire(200," Content-Length: 0\r\n",<<>>)])),
    ?assertEqual({error,invalid_http_header},read([wire(200,<<"X: a",0,"b\r\n">>,<<>>)])),
    ?assertEqual({error,invalid_decimal},read([wire(200,"Content-Length: -1\r\n",<<>>)])).

truncated_and_extra_fixed_body_test()->
    ?assertEqual({error,truncated_response},read([wire(200,"Content-Length: 4\r\n",<<"abc">>)])),
    ?assertEqual({error,trailing_response_bytes},read([wire(200,"Content-Length: 2\r\n",<<"abc">>)])),
    ?assertEqual({error,truncated_response},read([<<"HTTP/1.1 200 OK\r\nX: a">>])).

invalid_and_oversize_chunked_framing_test()->
    H="Transfer-Encoding: chunked\r\n",
    ?assertEqual({error,body_byte_limit},read([wire(200,H,<<"400001\r\n">>)])),
    ?assertEqual({error,invalid_chunk_size},read([wire(200,H,<<"-1\r\n">>)])),
    ?assertEqual({error,invalid_chunk_size},read([wire(200,H,<<"1;extension=value\r\nx\r\n0\r\n\r\n">>)])),
    ?assertEqual({error,invalid_chunk_terminator},read([wire(200,H,<<"1\r\nxZZ">>)])),
    ?assertEqual({error,unsupported_trailer},read([wire(200,H,<<"0\r\nX-Trailer: a\r\n\r\n">>)])),
    ?assertEqual({error,truncated_response},read([wire(200,H,<<"3\r\nab">>)])).

compressed_interim_and_no_body_responses_test()->
    ?assertEqual({error,unsupported_content_encoding},read([wire(200,"Content-Encoding: gzip\r\n",<<>>)])),
    ?assertEqual({error,unsupported_http_status},read([wire(100,[],<<>>)])),
    ?assertEqual({ok,{204,<<>>}},read([wire(204,[],<<>>)])),
    ?assertEqual({error,unexpected_body},read([wire(204,"Content-Length: 1\r\n",<<"x">>)])).

absolute_deadline_kills_even_an_uncooperative_receiver_test()->
    Parent=self(),Start=erlang:monotonic_time(millisecond),
    Result=uos_openrouter_ffi:bounded_call(fun(D)->
        Parent!{worker,self()},
        uos_openrouter_ffi:read_response(fun(_)->timer:sleep(1000),{ok,<<"a">>} end,D)
    end,50),
    ?assertEqual({error,<<"timeout">>},Result),
    ?assert(erlang:monotonic_time(millisecond)-Start<300),
    receive {worker,Pid}->?assertEqual(false,is_process_alive(Pid)) after 0->?assert(false) end.

continuous_output_never_resets_deadline_test()->
    Start=erlang:monotonic_time(millisecond),
    ?assertEqual({error,<<"timeout">>},uos_openrouter_ffi:bounded_call(fun(D)->
        uos_openrouter_ffi:read_response(fun(_)->timer:sleep(5),{ok,<<"a">>} end,D)
    end,60)),
    ?assert(erlang:monotonic_time(millisecond)-Start<300).

transport_error_does_not_echo_request_or_credentials_test()->
    ?assertEqual({error,<<"transport_failed">>},uos_openrouter_ffi:bounded_call(fun(_)->
        erlang:error({private_request,<<"secret-must-not-be-returned">>})
    end,100)).

caller_death_stops_socket_owner_test()->
    Parent=self(),
    Caller=spawn(fun()->uos_openrouter_ffi:bounded_call(fun(_)->
        Parent!{socket_owner,self()},receive never->ok end
    end,2000) end),
    Owner=receive {socket_owner,Pid}->Pid after 500->error(owner_not_started) end,
    Mon=erlang:monitor(process,Owner),
    exit(Caller,kill),
    receive {'DOWN',Mon,process,Owner,_}->ok after 500->?assert(false) end.
