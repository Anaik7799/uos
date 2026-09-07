%% Pure-Erlang terminal shim for uos_tui (no NIFs, no ports to foreign binaries).
%% Every function is total: failures come back as {error, Reason}.
-module(uos_tui_ffi).
-export([enter_raw/0, size/0, read_chars/1, write/1, monotonic_micros/0, utc_iso8601/0,
         file_read/1, list_dir/1]).

enter_raw() ->
    try
        shell:start_interactive({noshell, raw}),
        {ok, nil}
    catch
        _:Reason -> {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
    end.

size() ->
    case {io:columns(), io:rows()} of
        {{ok, W}, {ok, H}} -> {ok, {W, H}};
        _ -> {error, nil}
    end.

read_chars(N) ->
    case io:get_chars("", N) of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Data when is_list(Data) -> {ok, unicode:characters_to_binary(Data)};
        Data when is_binary(Data) -> {ok, Data}
    end.

write(Bin) ->
    io:put_chars(Bin),
    nil.

monotonic_micros() ->
    erlang:monotonic_time(microsecond).

utc_iso8601() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:universal_time(),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, Mo, D, H, Mi, S])).

file_read(Path) ->
    case file:read_file(Path) of
        {ok, B} -> {ok, B};
        {error, R} -> {error, atom_to_binary(R, utf8)}
    end.

%% List a directory's entries as binaries; used to probe hardware interlocks under sysfs
%% without ever shelling out or touching a NIF (Zero-Muda: pure Erlang/OTP file:list_dir/1).
list_dir(Path) ->
    case file:list_dir(binary_to_list(Path)) of
        {ok, Names} -> {ok, [unicode:characters_to_binary(N) || N <- Names]};
        {error, R} -> {error, atom_to_binary(R, utf8)}
    end.
