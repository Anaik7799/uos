%% Read-only fixed authenticated GETs. No retries, redirects, or inference.
%% Reuses existing monitored owner and 4MiB total-wire parser; delivered JSON
%% body is additionally capped at 256KiB. No heap-size guarantee is implied.
-module(uos_openrouter_usage_ffi).
-export([get/2,valid_path/1]).
valid_path(<<"/api/v1/key">>)->true;
valid_path(<<"/api/v1/credits">>)->true;
valid_path(<<"/api/v1/generation?id=gen-",Tail/binary>>) when byte_size(Tail)>=1,byte_size(Tail)=<120 ->
    lists:all(fun(C)->(C>=$a andalso C=<$z) orelse (C>=$A andalso C=<$Z) orelse (C>=$0 andalso C=<$9) orelse C==$- end,binary_to_list(Tail));
valid_path(<<"/api/v1/activity?date=",Y:4/binary,"-",M:2/binary,"-",D:2/binary>>)->
    try binary_to_integer(Y)>0 andalso calendar:valid_date({binary_to_integer(Y),binary_to_integer(M),binary_to_integer(D)}) andalso
        lists:all(fun(C)->C>=$0 andalso C=<$9 end,binary_to_list(<<Y/binary,M/binary,D/binary>>)) catch _:_ -> false end;
valid_path(_)->false.
get(Path,T) when is_binary(Path),is_integer(T),T>0,T=<30000 ->
    case valid_path(Path) of false->{error,<<"invalid_endpoint">>};true->
      uos_openrouter_ffi:bounded_call(fun(Deadline)->
        case uos_openrouter_ffi:api_key() of
          {error,_}->{error,<<"credential_unavailable">>};
          {ok,Key}->
            application:ensure_all_started(ssl),
            Opts=[binary,{active,false},{packet,raw},{verify,verify_peer},
              {cacertfile,"/etc/ssl/certs/ca-certificates.crt"},{depth,3},
              {server_name_indication,"openrouter.ai"},
              {customize_hostname_check,[{match_fun,public_key:pkix_verify_hostname_match_fun(https)}]},
              {recbuf,16384},{buffer,16384}],
            case ssl:connect("openrouter.ai",443,Opts,remaining(Deadline)) of
              {ok,S}->try
                case ssl:send(S,["GET ",Path," HTTP/1.1\r\nHost: openrouter.ai\r\nAccept: application/json\r\nAccept-Encoding: identity\r\nConnection: close\r\nAuthorization: Bearer ",Key,"\r\n\r\n"]) of
                  ok->case uos_openrouter_ffi:read_response(fun(R)->ssl:recv(S,0,R) end,Deadline) of
                    {ok,{Code,Body}} when byte_size(Body)=<262144 ->
                      case Code of 200->{ok,{Code,Body}};_->{ok,{Code,<<>>}} end;
                    {ok,_}->{error,<<"body_bound">>};
                    {error,_}->{error,<<"response_unavailable">>}
                  end;
                  _->{error,<<"send_failed">>}
                end
              after ssl:close(S) end;
              _->{error,<<"connection_failed">>}
            end
        end
      end,T)
    end;
get(_,_) -> {error,<<"invalid_request">>}.
remaining(D)->case D-erlang:monotonic_time(millisecond) of N when N>0->N;_->throw({bounded_http,timeout}) end.
