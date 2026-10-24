-module(telegram_matrix_http).
-export([get/5]).

-define(ERR, {error, <<"matrix_http_unavailable">>}).
-define(MAX_HEADERS, 32).
-define(MAX_HDR_BYTES, 8192).

-spec get(binary(), integer(), binary(), integer(), integer()) ->
    {ok, binary()} | {error, binary()}.
get(Host, Port, Path, TimeoutMs, MaxBody) ->
    try
        case valid_args(Host, Port, Path, TimeoutMs, MaxBody) of
            true ->
                Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
                connect_and_fetch(Host, Port, Path, MaxBody, Deadline);
            false ->
                ?ERR
        end
    catch
        _:_ -> ?ERR
    end.

connect_and_fetch(Host, Port, Path, MaxBody, Deadline) ->
    case rem_ms(Deadline) of
        {ok, Rem0} ->
            Opts = [
                binary,
                {active, false},
                {packet, http_bin},
                {packet_size, ?MAX_HDR_BYTES},
                {send_timeout, Rem0},
                {send_timeout_close, true}
            ],
            case gen_tcp:connect(binary_to_list(Host), Port, Opts, Rem0) of
                {ok, Sock} ->
                    try
                        exchange(Sock, Host, Port, Path, MaxBody, Deadline)
                    after
                        _ = gen_tcp:close(Sock)
                    end;
                _ ->
                    ?ERR
            end;
        error ->
            ?ERR
    end.

exchange(Sock, Host, Port, Path, MaxBody, Deadline) ->
    Req = [
        <<"GET ">>, Path, <<" HTTP/1.0\r\n">>,
        <<"Host: ">>, Host, <<":">>, integer_to_binary(Port), <<"\r\n">>,
        <<"Accept: application/json\r\n">>,
        <<"Connection: close\r\n\r\n">>
    ],
    case rem_ms(Deadline) of
        {ok, RemSend} ->
            case inet:setopts(Sock, [{send_timeout, RemSend}]) of
                ok ->
                    case gen_tcp:send(Sock, Req) of
                        ok -> read_status(Sock, MaxBody, Deadline);
                        _ -> ?ERR
                    end;
                _ ->
                    ?ERR
            end;
        error ->
            ?ERR
    end.

read_status(Sock, MaxBody, Deadline) ->
    case recv_pkt(Sock, Deadline) of
        {ok, {http_response, Ver, 200, Reason}}
          when (Ver =:= {1, 0} orelse Ver =:= {1, 1}),
               is_binary(Reason),
               byte_size(Reason) =< 256 ->
            read_headers(Sock, MaxBody, Deadline, 0, 0, undefined, false, false);
        _ ->
            ?ERR
    end.

read_headers(Sock, MaxBody, Deadline, Count, Bytes, CL, HasCT, HasCE) ->
    case recv_pkt(Sock, Deadline) of
        {ok, http_eoh} ->
            case CL =/= undefined andalso HasCT of
                true -> read_body(Sock, CL, Deadline);
                false -> ?ERR
            end;
        {ok, {http_header, _, Field, _, Val}}
          when is_binary(Val), Count < ?MAX_HEADERS ->
            case norm_field(Field) of
                {ok, Name, NameLen} ->
                    NewBytes = Bytes + NameLen + byte_size(Val),
                    case NewBytes =< ?MAX_HDR_BYTES of
                        true ->
                            apply_header(
                                Name, Val, Sock, MaxBody, Deadline,
                                Count + 1, NewBytes, CL, HasCT, HasCE
                            );
                        false ->
                            ?ERR
                    end;
                error ->
                    ?ERR
            end;
        _ ->
            ?ERR
    end.

apply_header(<<"transfer-encoding">>, _, _, _, _, _, _, _, _, _) ->
    ?ERR;
apply_header(<<"content-length">>, Val, Sock, MaxBody, Deadline, Cnt, Bytes, undefined, HasCT, HasCE) ->
    case parse_cl(Val, MaxBody) of
        {ok, N} -> read_headers(Sock, MaxBody, Deadline, Cnt, Bytes, N, HasCT, HasCE);
        error -> ?ERR
    end;
apply_header(<<"content-length">>, _, _, _, _, _, _, _, _, _) ->
    ?ERR;
apply_header(<<"content-type">>, Val, Sock, MaxBody, Deadline, Cnt, Bytes, CL, false, HasCE) ->
    case valid_ct(Val) of
        true -> read_headers(Sock, MaxBody, Deadline, Cnt, Bytes, CL, true, HasCE);
        false -> ?ERR
    end;
apply_header(<<"content-type">>, _, _, _, _, _, _, _, true, _) ->
    ?ERR;
apply_header(<<"content-encoding">>, Val, Sock, MaxBody, Deadline, Cnt, Bytes, CL, HasCT, false) ->
    case lower_bin(trim_ows(Val)) of
        <<"identity">> -> read_headers(Sock, MaxBody, Deadline, Cnt, Bytes, CL, HasCT, true);
        _ -> ?ERR
    end;
apply_header(<<"content-encoding">>, _, _, _, _, _, _, _, _, true) ->
    ?ERR;
apply_header(_, _, Sock, MaxBody, Deadline, Cnt, Bytes, CL, HasCT, HasCE) ->
    read_headers(Sock, MaxBody, Deadline, Cnt, Bytes, CL, HasCT, HasCE).

read_body(Sock, CL, Deadline) ->
    case inet:setopts(Sock, [{packet, raw}]) of
        ok ->
            case recv_raw(Sock, CL, Deadline) of
                {ok, Body} when byte_size(Body) =:= CL ->
                    case unicode:characters_to_binary(Body, utf8, utf8) of
                        Body -> {ok, Body};
                        _ -> ?ERR
                    end;
                _ ->
                    ?ERR
            end;
        _ ->
            ?ERR
    end.

recv_pkt(Sock, Deadline) ->
    case rem_ms(Deadline) of
        {ok, Rem} -> gen_tcp:recv(Sock, 0, Rem);
        error -> error
    end.

recv_raw(Sock, Len, Deadline) ->
    case rem_ms(Deadline) of
        {ok, Rem} -> gen_tcp:recv(Sock, Len, Rem);
        error -> error
    end.

rem_ms(Deadline) ->
    case Deadline - erlang:monotonic_time(millisecond) of
        Rem when Rem > 0 -> {ok, Rem};
        _ -> error
    end.

valid_args(Host, Port, Path, TimeoutMs, MaxBody) ->
    is_binary(Host) andalso byte_size(Host) >= 1 andalso byte_size(Host) =< 253 andalso
    is_integer(Port) andalso Port >= 1 andalso Port =< 65535 andalso
    is_binary(Path) andalso byte_size(Path) >= 1 andalso byte_size(Path) =< 256 andalso
    is_integer(TimeoutMs) andalso TimeoutMs >= 100 andalso TimeoutMs =< 2000 andalso
    is_integer(MaxBody) andalso MaxBody >= 1 andalso MaxBody =< 16384 andalso
    valid_host(Host) andalso valid_path(Path).

valid_host(<<C, _/binary>>) when C =:= $. orelse C =:= $- -> false;
valid_host(Host) -> valid_host_bytes(Host, $.).

valid_host_bytes(<<>>, Last) -> Last =/= $. andalso Last =/= $-;
valid_host_bytes(<<C, Rest/binary>>, _) when
    (C >= $a andalso C =< $z) orelse (C >= $A andalso C =< $Z) orelse
    (C >= $0 andalso C =< $9) orelse C =:= $. orelse C =:= $- ->
    valid_host_bytes(Rest, C);
valid_host_bytes(_, _) -> false.

valid_path(<<$/, Rest/binary>>) -> valid_path_bytes(Rest);
valid_path(_) -> false.

valid_path_bytes(<<>>) -> true;
valid_path_bytes(<<C, Rest/binary>>) when C >= 33, C =< 126 -> valid_path_bytes(Rest);
valid_path_bytes(_) -> false.

norm_field('Content-Length') -> {ok, <<"content-length">>, 14};
norm_field('Content-Type') -> {ok, <<"content-type">>, 12};
norm_field('Transfer-Encoding') -> {ok, <<"transfer-encoding">>, 17};
norm_field('Content-Encoding') -> {ok, <<"content-encoding">>, 16};
norm_field(F) when is_atom(F) ->
    B = atom_to_binary(F, latin1),
    case byte_size(B) =< 64 of
        true -> {ok, lower_bin(B), byte_size(B)};
        false -> error
    end;
norm_field(F) when is_binary(F), byte_size(F) >= 1, byte_size(F) =< 128 ->
    {ok, lower_bin(F), byte_size(F)};
norm_field(_) -> error.

parse_cl(<<D, Rest/binary>> = Bin, MaxBody) when byte_size(Bin) =< 5, D >= $1, D =< $9 ->
    case all_digits(Rest) of
        true ->
            N = binary_to_integer(Bin),
            case N >= 1 andalso N =< MaxBody of
                true -> {ok, N};
                false -> error
            end;
        false -> error
    end;
parse_cl(_, _) -> error.

all_digits(<<>>) -> true;
all_digits(<<D, Rest/binary>>) when D >= $0, D =< $9 -> all_digits(Rest);
all_digits(_) -> false.

valid_ct(Val) ->
    case binary:split(lower_bin(trim_ows(Val)), <<";">>) of
        [<<"application/json">>] -> true;
        [Base, Param] ->
            trim_ows(Base) =:= <<"application/json">> andalso valid_charset(trim_ows(Param));
        _ -> false
    end.

valid_charset(<<"charset=utf-8">>) -> true;
valid_charset(<<"charset=\"utf-8\"">>) -> true;
valid_charset(_) -> false.

trim_ows(<<C, Rest/binary>>) when C =:= $\s orelse C =:= $\t -> trim_ows(Rest);
trim_ows(Bin) -> trim_ows_end(Bin, byte_size(Bin)).

trim_ows_end(_, 0) -> <<>>;
trim_ows_end(Bin, Len) ->
    case binary:at(Bin, Len - 1) of
        C when C =:= $\s orelse C =:= $\t -> trim_ows_end(Bin, Len - 1);
        _ -> binary:part(Bin, 0, Len)
    end.

lower_bin(Bin) ->
    << <<(case C >= $A andalso C =< $Z of true -> C + 32; false -> C end)>> || <<C>> <= Bin >>.
