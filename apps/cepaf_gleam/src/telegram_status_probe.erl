-module(telegram_status_probe).
-export([probe/2, read_headers/2]).

-define(MAX_REASON_BYTES, 1024).
-define(MAX_HEADERS, 32).
-define(MAX_HEADER_BYTES, 16384).

-spec probe(binary(), integer()) -> {ok, integer()} | {error, binary()}.
probe(Name, T) when is_binary(Name), is_integer(T), T >= 100, T =< 1500 ->
    case endpoint(Name) of
        {ok, Host, Port, Req} ->
            uos_openrouter_ffi:bounded_call(
                fun(Deadline) -> connect_and_read(Host, Port, Req, T, Deadline) end,
                T
            );
        error ->
            {error, <<"unknown_target">>}
    end;
probe(Name, _T) when not is_binary(Name) ->
    {error, <<"unknown_target">>};
probe(_Name, _T) ->
    {error, <<"invalid_timeout">>}.

-spec read_headers(fun((integer()) -> term()), integer()) -> {ok, integer()} | {error, binary()}.
read_headers(RecvFun, Deadline) when is_function(RecvFun, 1), is_integer(Deadline) ->
    case recv_pkt(RecvFun, Deadline) of
        {ok, {http_response, Ver, Status, Reason}}
          when (Ver =:= {1, 0} orelse Ver =:= {1, 1}),
               is_integer(Status), Status >= 200, Status =< 599 ->
            case norm_bounded(Reason, ?MAX_REASON_BYTES) of
                {ok, _} -> read_hdr_loop(RecvFun, Deadline, Status, 0, 0);
                limit -> {error, <<"status_reason_too_long">>};
                error -> {error, <<"malformed_response">>}
            end;
        {ok, {http_response, _, _, _}} ->
            {error, <<"invalid_status">>};
        {ok, _} ->
            {error, <<"malformed_response">>};
        {error, _} = Err ->
            Err
    end;
read_headers(_RecvFun, _Deadline) ->
    {error, <<"invalid_arguments">>}.

connect_and_read(Host, Port, Req, T, Deadline) ->
    case rem_ms(Deadline) of
        Rem1 when Rem1 =< 0 ->
            {error, <<"timeout">>};
        Rem1 ->
            Opts = [binary, {active, false}, {packet, http_bin},
                    {packet_size, ?MAX_HEADER_BYTES}, {send_timeout, T},
                    {send_timeout_close, true}],
            case gen_tcp:connect(Host, Port, Opts, Rem1) of
                {ok, Sock} ->
                    try
                        case rem_ms(Deadline) of
                            Rem2 when Rem2 =< 0 -> {error, <<"timeout">>};
                            _ ->
                                case gen_tcp:send(Sock, Req) of
                                    ok -> read_headers(fun(R) -> gen_tcp:recv(Sock, 0, R) end, Deadline);
                                    {error, timeout} -> {error, <<"timeout">>};
                                    {error, _} -> {error, <<"send_failed">>}
                                end
                        end
                    after
                        gen_tcp:close(Sock)
                    end;
                {error, timeout} -> {error, <<"timeout">>};
                {error, _} -> {error, <<"connect_failed">>}
            end
    end.

read_hdr_loop(RecvFun, Deadline, Status, Count, Bytes) ->
    case recv_pkt(RecvFun, Deadline) of
        {ok, http_eoh} ->
            {ok, Status};
        {ok, {http_header, _, Name, _, Val}} when Count < ?MAX_HEADERS ->
            Budget = ?MAX_HEADER_BYTES - Bytes,
            case norm_bounded(Name, Budget) of
                {ok, NBin} ->
                    NSz = byte_size(NBin),
                    case norm_bounded(Val, Budget - NSz) of
                        {ok, VBin} ->
                            read_hdr_loop(RecvFun, Deadline, Status, Count + 1, Bytes + NSz + byte_size(VBin));
                        limit -> {error, <<"header_limit_exceeded">>};
                        error -> {error, <<"malformed_header">>}
                    end;
                limit -> {error, <<"header_limit_exceeded">>};
                error -> {error, <<"malformed_header">>}
            end;
        {ok, {http_header, _, _, _, _}} ->
            {error, <<"header_limit_exceeded">>};
        {ok, _} ->
            {error, <<"malformed_header">>};
        {error, _} = Err ->
            Err
    end.

recv_pkt(RecvFun, Deadline) ->
    case rem_ms(Deadline) of
        Rem when Rem =< 0 -> {error, <<"timeout">>};
        Rem ->
            case RecvFun(Rem) of
                {ok, _} = Ok -> Ok;
                {error, timeout} -> {error, <<"timeout">>};
                {error, _} -> {error, <<"recv_failed">>};
                _ -> {error, <<"malformed_response">>}
            end
    end.

norm_bounded(Bin, Max) when is_binary(Bin), Max >= 0 ->
    case byte_size(Bin) =< Max of true -> {ok, Bin}; false -> limit end;
norm_bounded(Atom, Max) when is_atom(Atom), Max >= 0 ->
    norm_bounded(erlang:atom_to_binary(Atom, utf8), Max);
norm_bounded(List, Max) when is_list(List), Max >= 0 ->
    norm_list(List, Max, []);
norm_bounded(_, _) ->
    error.

norm_list([], _Rem, Acc) -> {ok, erlang:list_to_binary(lists:reverse(Acc))};
norm_list(_, 0, _Acc) -> limit;
norm_list([B | T], Rem, Acc) when is_integer(B), B >= 0, B =< 255 -> norm_list(T, Rem - 1, [B | Acc]);
norm_list(_, _, _) -> error.

rem_ms(Deadline) -> Deadline - erlang:monotonic_time(millisecond).

endpoint(<<"matrix">>) ->
    {ok, "nas-1.tail55d152.ts.net", 6167,
     <<"GET /_matrix/client/versions HTTP/1.1\r\nHost: nas-1.tail55d152.ts.net:6167\r\nConnection: close\r\n\r\n">>};
endpoint(<<"cockpit">>) ->
    {ok, "nas-1.tail55d152.ts.net", 4100,
     <<"GET / HTTP/1.1\r\nHost: nas-1.tail55d152.ts.net:4100\r\nConnection: close\r\n\r\n">>};
endpoint(<<"zenoh">>) ->
    {ok, "nas-1.tail55d152.ts.net", 8080,
     <<"GET /api/zenoh/health HTTP/1.1\r\nHost: nas-1.tail55d152.ts.net:8080\r\nConnection: close\r\n\r\n">>};
endpoint(<<"peer_runtime">>) ->
    {ok, "vm-1.tail55d152.ts.net", 8088,
     <<"GET /health HTTP/1.1\r\nHost: vm-1.tail55d152.ts.net:8088\r\nConnection: close\r\n\r\n">>};
endpoint(_) -> error.
