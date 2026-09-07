%% Bounded OTP file/JSON boundary for the pure Gleam report reader.
%% No shell, NIF, network mutation, credential lookup, atom construction or writes.
-module(board_reader_ffi).
-export([read_bounded/2, unwrap_samples/1]).

read_bounded(Path, Limit) when is_binary(Path), is_integer(Limit), Limit > 0, Limit =< 16777216 ->
    case file:open(Path, [read, binary, raw]) of
        {ok, Fd} ->
            try
                case file:read(Fd, Limit + 1) of
                    {ok, Bytes} when byte_size(Bytes) =< Limit -> {ok, Bytes};
                    {ok, _} -> {error, <<"file exceeds byte bound">>};
                    eof -> {ok, <<>>};
                    {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
                end
            after file:close(Fd) end;
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end;
read_bounded(_, _) -> {error, <<"invalid bounded read">>}.

unwrap_samples(Body) when byte_size(Body) =< 16777216 ->
    try json:decode(Body) of
        Rows when is_list(Rows), length(Rows) =< 10000 ->
            {ok, [case Row of
                #{<<"value">> := Value} when is_binary(Value) -> Value;
                #{<<"value">> := Value} -> iolist_to_binary(json:encode(Value));
                _ -> <<"null">>
            end || Row <- Rows]};
        _ -> {error, <<"expected a bounded Zenoh sample array">>}
    catch _:_ -> {error, <<"invalid Zenoh sample JSON">>} end;
unwrap_samples(_) -> {error, <<"Zenoh response exceeds byte bound">>}.
