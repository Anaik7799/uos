%% Exact official endpoints; no redirects. Bounds cover HTTP plaintext bytes,
%% including headers and framing, not TLS overhead or a proof of OTP heap size.
%% A monitored socket owner enforces one deadline across DNS/TLS/send/receive.
-module(uos_openrouter_ffi).
-include_lib("kernel/include/file.hrl").
-export([has_api_key/0,api_key/0,https_get/2,https_post_json/4]).
-export([read_response/2,bounded_call/2,validate_request/5]).
-define(HEADER_LIMIT,16384).
-define(HTTP_LIMIT,4194304).
-define(BODY_LIMIT,4194304).
-record(reader,{recv,deadline,wire=0,buffer = <<>>}).

has_api_key()->case api_key() of {ok,_}->true;_->false end.
api_key()->case os:getenv("OPENROUTER_API_KEY") of
    false->credential_file();
    V->K=unicode:characters_to_binary(string:trim(V)),
       case valid_key(K) of true->{ok,K};false->{error,nil} end
end.
%% systemd decrypts its encrypted credential outside the repository and exposes
%% a service-private read-only mount. Never copy/hash/log credential contents.
credential_file()->case os:getenv("CREDENTIALS_DIRECTORY") of
    false->{error,nil};
    Dir->case filename:pathtype(Dir) of
        absolute->Path=filename:join(Dir,"openrouter_api_key"),
            case file:read_file_info(Path) of
                {ok,#file_info{type=regular,size=N}} when N>0,N=<8192->
                    case file:open(Path,[read,raw,binary]) of
                        {ok,F}->try case file:read(F,8193) of
                            {ok,K}->case valid_key(K) of true->{ok,K};false->{error,nil} end;
                            _->{error,nil}
                        end after file:close(F) end;
                        _->{error,nil}
                    end;
                _->{error,nil}
            end;
        _->{error,nil}
    end
end.
https_get(U,T)->request(get,U,<<>>,<<>>,T).
https_post_json(U,K,B,T)->request(post,U,K,B,T).

validate_request(M,U,K,B,T)->
    case is_integer(T) andalso T>0 andalso T=<30000 of
        false->{error,<<"invalid_timeout">>};
        true->case {M,U} of
            {get,<<"https://openrouter.ai/api/v1/models">>}->{ok,<<"/api/v1/models">>};
            {post,<<"https://openrouter.ai/api/v1/chat/completions">>}->
                case valid_key(K) andalso is_binary(B) andalso byte_size(B)=<65536 of
                    true->{ok,<<"/api/v1/chat/completions">>};
                    false->{error,<<"invalid_credential_or_request_bound">>}
                end;
            _->{error,<<"endpoint_not_allowlisted">>}
        end
    end.
valid_key(K) when is_binary(K),byte_size(K)>0,byte_size(K)=<8192->
    lists:all(fun(C)->C>=33 andalso C=<126 end,binary_to_list(K));
valid_key(_)->false.

request(M,U,K,B,T)->case validate_request(M,U,K,B,T) of
    {error,_}=E->E;
    {ok,Path}->bounded_call(fun(Deadline)->
        case application:ensure_all_started(ssl) of {ok,_}->ok;_->fail(tls_unavailable) end,
        Opts=[binary,{active,false},{packet,raw},{verify,verify_peer},
              {cacertfile,"/etc/ssl/certs/ca-certificates.crt"},{depth,3},
              {server_name_indication,"openrouter.ai"},
              {customize_hostname_check,[{match_fun,public_key:pkix_verify_hostname_match_fun(https)}]},
              {recbuf,16384},{buffer,16384}],
        case ssl:connect("openrouter.ai",443,Opts,remaining(Deadline)) of
            {ok,S}->try
                case ssl:send(S,request_bytes(M,Path,K,B)) of ok->ok;_->fail(send_failed) end,
                read_response(fun(R)->ssl:recv(S,0,R) end,Deadline)
            after ssl:close(S) end;
            {error,timeout}->fail(timeout);
            _->fail(tls_connect_failed)
        end
    end,T)
end.
request_bytes(M,Path,K,B)->
    {Verb,Extra}=case M of
        get->{<<"GET">>,[]};
        post->{<<"POST">>,[<<"Authorization: Bearer ">>,K,
            <<"\r\nContent-Type: application/json\r\nContent-Length: ">>,
            integer_to_binary(byte_size(B)),<<"\r\n">>]}
    end,
    [Verb,<<" ">>,Path,<<" HTTP/1.1\r\nHost: openrouter.ai\r\nAccept: application/json\r\nAccept-Encoding: identity\r\nConnection: close\r\n">>,Extra,<<"\r\n">>,B].

%% Killing the controlling worker closes its owned SSL connection. Results are
%% sent only after the request function has closed its socket. No implicit retry.
bounded_call(F,T) when is_integer(T),T>0,T=<30000->
    Parent=self(), Ref=make_ref(), D=erlang:monotonic_time(millisecond)+T,
    {Pid,Mon}=spawn_monitor(fun()->
        Owner=self(),
        %% This guardian remains responsive while SSL/DNS/send is blocked. It
        %% also stops the socket owner if its supervised caller is cancelled.
        Guardian=spawn(fun()->watch_owner(Parent,Owner,D) end),
        R=try F(D) catch throw:{bounded_http,Why}->{error,atom_to_binary(Why,utf8)};
                        _:_->{error,<<"transport_failed">>} end,
        exit(Guardian,kill),
        Parent!{Ref,R}
    end),
    receive
        {Ref,R}->erlang:demonitor(Mon,[flush]),R;
        {'DOWN',Mon,process,Pid,_}->
            case erlang:monotonic_time(millisecond)>=D of
                true->{error,<<"timeout">>};false->{error,<<"transport_worker_failed">>}
            end
    after T->
        exit(Pid,kill),receive {'DOWN',Mon,process,Pid,_}->ok end,
        receive {Ref,_}->ok after 0->ok end,
        {error,<<"timeout">>}
    end;
bounded_call(_,_) -> {error,<<"invalid_timeout">>}.
watch_owner(Parent,Owner,D)->
    PMon=erlang:monitor(process,Parent),OMon=erlang:monitor(process,Owner),
    receive
        {'DOWN',PMon,process,Parent,_}->exit(Owner,kill);
        {'DOWN',OMon,process,Owner,_}->ok
    after max(0,D-erlang:monotonic_time(millisecond))->exit(Owner,kill)
    end.
remaining(D)->case D-erlang:monotonic_time(millisecond) of N when N>0->N;_->fail(timeout) end.
fail(R)->throw({bounded_http,R}).

%% Counter checked before concatenation, for ALL status codes and framing modes.
more(R=#reader{recv=F,deadline=D,wire=W,buffer=B})->case F(remaining(D)) of
    {ok,C} when is_binary(C),byte_size(C)>0->
        N=W+byte_size(C),
        case N=< ?HTTP_LIMIT of
            true->{ok,R#reader{wire=N,buffer = <<B/binary,C/binary>>}};
            false->fail(http_byte_limit)
        end;
    {error,closed}->{closed,R};
    {error,timeout}->fail(timeout);
    _->fail(receive_failed)
end.
line(R=#reader{buffer=B},Limit)->case binary:match(B,<<"\r\n">>) of
    {At,2} when At=<Limit-> <<L:At/binary,"\r\n",Rest/binary>>=B,{L,R#reader{buffer=Rest}};
    {_,_}->fail(header_or_chunk_line_limit);
    nomatch when byte_size(B)>Limit+1->fail(header_or_chunk_line_limit);
    nomatch->case more(R) of {ok,N}->line(N,Limit);{closed,_}->fail(truncated_response) end
end.
read_response(F,D)->
    {Status,R1}=line(#reader{recv=F,deadline=D},?HEADER_LIMIT),
    Code=status_code(Status),
    {H,R2,HSize}=headers(R1,#{},byte_size(Status)+2,0),
    Mode=body_mode(H,HSize),
    case Code=:=204 orelse Code=:=304 of
        true->case {Mode,R2#reader.buffer} of
            {{length,0},<<>>}->{ok,{Code,<<>>}};
            {close,<<>>}->{ok,{Code,<<>>}};
            _->fail(unexpected_body)
        end;
        false->Body=case Mode of
            {length,N}->fixed_body(R2,N,[]);
            chunked->chunked_body(R2,[],0);
            close->closed_body(R2,[],0)
        end,{ok,{Code,Body}}
    end.
status_code(<<V:8/binary," ",C:3/binary,Reason/binary>>)
  when V=:= <<"HTTP/1.1">>;V=:= <<"HTTP/1.0">>->
    case {decimal(C),Reason} of
        {N,<<>>} when N>=200,N=<599->N;
        {N,<<" ",_/binary>>} when N>=200,N=<599->N;
        _->fail(unsupported_http_status)
    end;
status_code(_)->fail(invalid_http_status).
headers(R,H,Size,Count)->
    case Size=< ?HEADER_LIMIT andalso Count=<128 of true->ok;false->fail(header_limit) end,
    {L,N}=line(R,?HEADER_LIMIT-Size), NewSize=Size+byte_size(L)+2,
    case NewSize=< ?HEADER_LIMIT of true->ok;false->fail(header_limit) end,
    case L of
        <<>>->{H,N,NewSize};
        _->{K,V}=header_pair(L),H1=maps:update_with(K,fun(Old)->[V|Old] end,[V],H),
           headers(N,H1,NewSize,Count+1)
    end.
header_pair(L)->case binary:match(L,<<":">>) of
    {At,1} when At>0->
        <<K:At/binary,":",Raw/binary>>=L,
        case valid_name(K) andalso valid_value(Raw) of
            true->{string:lowercase(K),string:trim(Raw,both," \t")};
            false->fail(invalid_http_header)
        end;
    _->fail(invalid_http_header)
end.
valid_name(K)->lists:all(fun(C)->(C>=$a andalso C=<$z) orelse (C>=$A andalso C=<$Z)
    orelse (C>=$0 andalso C=<$9) orelse lists:member(C,"!#$%&'*+-.^_`|~") end,binary_to_list(K)).
valid_value(V)->lists:all(fun(C)->C=:=9 orelse (C>=32 andalso C=/=127) end,binary_to_list(V)).
single(K,H)->case maps:get(K,H,[]) of []->none;[V]->V;_->fail(ambiguous_http_header) end.
body_mode(H,HSize)->
    case single(<<"content-encoding">>,H) of
        none->ok;E->case string:lowercase(E) of <<"identity">>->ok;_->fail(unsupported_content_encoding) end
    end,
    case {single(<<"transfer-encoding">>,H),single(<<"content-length">>,H)} of
        {none,none}->close;
        {none,L}->N=decimal(L),case N=< ?BODY_LIMIT andalso N+HSize=< ?HTTP_LIMIT of
            true->{length,N};false->fail(http_byte_limit) end;
        {TE,none}->case string:lowercase(TE) of <<"chunked">>->chunked;_->fail(unsupported_transfer_encoding) end;
        _->fail(ambiguous_body_framing)
    end.
decimal(B) when byte_size(B)>0,byte_size(B)=<10->
    case lists:all(fun(C)->C>=$0 andalso C=<$9 end,binary_to_list(B)) of
        true->binary_to_integer(B);false->fail(invalid_decimal) end;
decimal(_)->fail(invalid_decimal).
fixed_body(R=#reader{buffer=B},N,Chunks)->case byte_size(B) of
    N->iolist_to_binary(lists:reverse([B|Chunks]));
    Size when Size>N->fail(trailing_response_bytes);
    Size->case more(R#reader{buffer = <<>>}) of
        {ok,Next}->fixed_body(Next,N-Size,[B|Chunks]);{closed,_}->fail(truncated_response) end
end.
closed_body(R=#reader{buffer=B},Chunks,Total)->
    Size=Total+byte_size(B),case Size=< ?BODY_LIMIT of true->ok;false->fail(body_byte_limit) end,
    case more(R#reader{buffer = <<>>}) of
        {ok,Next}->closed_body(Next,[B|Chunks],Size);
        {closed,_}->iolist_to_binary(lists:reverse([B|Chunks]))
    end.
take_bytes(R=#reader{buffer=B},N) when byte_size(B)>=N->
    <<Taken:N/binary,Rest/binary>>=B,{Taken,R#reader{buffer=Rest}};
take_bytes(R,N)->case more(R) of {ok,Next}->take_bytes(Next,N);{closed,_}->fail(truncated_response) end.
chunked_body(R,Chunks,Size)->
    {L,R1}=line(R,128),N=hex_size(L),
    case Size+N=< ?BODY_LIMIT of true->ok;false->fail(body_byte_limit) end,
    case N of
        0->{End,R2}=line(R1,?HEADER_LIMIT),
           %% Unsupported trailers and extensions fail closed, never ignored.
           case {End,R2#reader.buffer} of
               {<<>>,<<>>}->iolist_to_binary(lists:reverse(Chunks));
               {<<>>,_}->fail(trailing_response_bytes);_->fail(unsupported_trailer) end;
        _->{Framed,R2}=take_bytes(R1,N+2),
           case Framed of <<B:N/binary,"\r\n">>->chunked_body(R2,[B|Chunks],Size+N);
               _->fail(invalid_chunk_terminator) end
    end.
hex_size(B) when byte_size(B)>0,byte_size(B)=<8->
    case lists:all(fun(C)->(C>=$0 andalso C=<$9) orelse (C>=$a andalso C=<$f)
        orelse (C>=$A andalso C=<$F) end,binary_to_list(B)) of
        true->binary_to_integer(B,16);false->fail(invalid_chunk_size) end;
hex_size(_)->fail(invalid_chunk_size).
