%% Bounded socket IO only. Gleam owns backend/key/response policy.
%% Exact Tailnet endpoint, no redirects/proxy, no NIF and no implicit retry.
-module(zenoh_rest_ffi).
-export([request/3,encode_json/1]).

request(Method,Key,Body) when (Method=:= <<"GET">> orelse Method=:= <<"PUT">>),
                            is_binary(Key),byte_size(Key)>0,byte_size(Key)=<512,
                            is_binary(Body),byte_size(Body)=<65536 ->
    %% Defense at the external boundary: caller cannot inject a path/header.
    Board = Key=:= <<"c3i/a2a">> orelse
            binary:match(Key,<<"c3i/a2a/">>)=:= {0,8},
    case safe_key(Key) andalso not (Method=:= <<"PUT">> andalso Board) of
        false->{error,<<"invalid_zenoh_key">>};
        true->uos_openrouter_ffi:bounded_call(fun(D)->
            Remaining=fun()->max(1,D-erlang:monotonic_time(millisecond)) end,
            case gen_tcp:connect("nas-1.tail55d152.ts.net",8080,
                    [binary,{active,false},{packet,raw},{send_timeout,3000},
                     {send_timeout_close,true},{recbuf,16384},{buffer,16384}],Remaining()) of
                {ok,S}->try
                    Extra=case Method of
                        <<"PUT">>->[<<"Content-Type: text/plain\r\nContent-Length: ">>,
                                    integer_to_binary(byte_size(Body)),<<"\r\n">>];
                        _->[]
                    end,
                    Bytes=[Method,<<" /">>,Key,
                        <<" HTTP/1.1\r\nHost: nas-1.tail55d152.ts.net:8080\r\nAccept: application/json\r\nAccept-Encoding: identity\r\nConnection: close\r\n">>,
                        Extra,<<"\r\n">>,Body],
                    case gen_tcp:send(S,Bytes) of
                        ok->uos_openrouter_ffi:read_response(fun(T)->gen_tcp:recv(S,0,T) end,D);
                        _->{error,<<"zenoh_send_failed">>}
                    end
                after gen_tcp:close(S) end;
                _->{error,<<"zenoh_connect_failed">>}
            end
        end,3000)
    end;
request(_,_,_)->{error,<<"zenoh_request_bound">>}.

safe_key(K)->
    Parts=binary:split(K,<<"/">>,[global]),
    lists:all(fun(P)->P=/= <<>> andalso P=/= <<".">> andalso P=/= <<"..">> end,Parts)
    andalso lists:all(fun(C)->
        (C>=$a andalso C=<$z) orelse (C>=$A andalso C=<$Z) orelse
        (C>=$0 andalso C=<$9) orelse lists:member(C,"/_.-")
    end,binary_to_list(K)).

encode_json(Value)->iolist_to_binary(json:encode(Value)).
