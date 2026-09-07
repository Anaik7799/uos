%% Pure-Erlang shim for uos_swarm (no NIFs, no ports to foreign binaries).
%% Copied verbatim from uos_tui_ffi.erl's board/coordination shim (ets, inets/httpc, file, crypto).
%% Every function is total: failures come back as {error, Reason}.
-module(uos_swarm_ffi).
-export([ets_open/1, ets_insert/3, ets_lookup/2, ets_all/1, ets_count/1, ets_clear/1,
         http_put/2, http_get/1, file_append/2, file_read/1, file_write/2, sha256_hex/1, hmac_hex/2, board_key/0, system_time_us/0, host_boot/0,
         list_dir/1, getenv/2, ensure_dir/1]).

%% ---- board / coordination shim (pure OTP: ets, inets/httpc, file, crypto) ----
ets_open(Name) ->
    Atom = binary_to_atom(Name, utf8),
    case ets:whereis(Atom) of
        undefined ->
            try ets:new(Atom, [ordered_set, protected, named_table]) of
                T -> {ok, T}
            catch
                _:R -> {error, iolist_to_binary(io_lib:format("~p", [R]))}
            end;
        Tid -> {ok, Tid}
    end.

ets_insert(T, Key, Value) -> true = ets:insert(T, {Key, Value}), nil.

ets_lookup(T, Key) ->
    case ets:lookup(T, Key) of
        [{_, V}] -> {ok, V};
        _ -> {error, nil}
    end.

ets_all(T) -> ets:tab2list(T).

ets_count(T) -> ets:info(T, size).

ets_clear(T) -> true = ets:delete_all_objects(T), nil.

http_put(Url, Body) ->
    _ = application:ensure_all_started(inets),
    case httpc:request(put, {binary_to_list(Url), [], "application/json", Body},
                       [{timeout, 3000}, {connect_timeout, 2000}], [{body_format, binary}]) of
        {ok, {{_, Code, _}, _, _}} -> {ok, Code};
        {error, R} -> {error, iolist_to_binary(io_lib:format("~p", [R]))}
    end.

http_get(Url) ->
    _ = application:ensure_all_started(inets),
    case httpc:request(get, {binary_to_list(Url), []},
                       [{timeout, 3000}, {connect_timeout, 2000}], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, Body}} -> {ok, Body};
        {ok, {{_, Code, _}, _, _}} -> {error, <<"http ", (integer_to_binary(Code))/binary>>};
        {error, R} -> {error, iolist_to_binary(io_lib:format("~p", [R]))}
    end.

file_append(Path, Line) ->
    case file:write_file(Path, Line, [append]) of
        ok -> {ok, nil};
        {error, R} -> {error, atom_to_binary(R, utf8)}
    end.

file_write(Path, Content) ->
    case file:write_file(Path, Content) of
        ok -> {ok, nil};
        {error, R} -> {error, atom_to_binary(R, utf8)}
    end.

file_read(Path) ->
    case file:read_file(Path) of
        {ok, B} -> {ok, B};
        {error, R} -> {error, atom_to_binary(R, utf8)}
    end.

%% HMAC-SHA256 (keyed) so envelopes cannot be forged by anyone who can reach the transport.
hmac_hex(Key, Bin) -> string:lowercase(binary:encode_hex(crypto:mac(hmac, sha256, Key, Bin))).

%% Signing key: UOS_BOARD_KEY env, else ~/.config/uos/board.key; {error, nil} when absent (board runs unsigned and says so).
board_key() ->
    case os:getenv("UOS_BOARD_KEY") of
        false ->
            case file:read_file(filename:join(os:getenv("HOME", "/root"), ".config/uos/board.key")) of
                {ok, B} -> {ok, string:trim(B)};
                _ -> {error, nil}
            end;
        K -> {ok, list_to_binary(K)}
    end.

sha256_hex(Bin) -> string:lowercase(binary:encode_hex(crypto:hash(sha256, Bin))).

system_time_us() -> erlang:system_time(microsecond).

%% Total: the named env var as a binary, or Default (also a binary) when unset.
getenv(Name, Default) ->
    case os:getenv(binary_to_list(Name)) of
        false -> Default;
        V -> unicode:characters_to_binary(V)
    end.

%% Idempotent single-level directory creation (parent must already exist), used
%% by tests to stand up a scratch output directory. Not a recursive mkdir -p.
ensure_dir(Path) ->
    case file:make_dir(Path) of
        ok -> {ok, nil};
        {error, eexist} -> {ok, nil};
        {error, R} -> {error, atom_to_binary(R, utf8)}
    end.

%% List a directory's entries as binaries; used to probe hardware interlocks under sysfs
%% without ever shelling out or touching a NIF (Zero-Muda: pure Erlang/OTP file:list_dir/1).
list_dir(Path) ->
    case file:list_dir(binary_to_list(Path)) of
        {ok, Names} -> {ok, [unicode:characters_to_binary(N) || N <- Names]};
        {error, R} -> {error, atom_to_binary(R, utf8)}
    end.

%% Actual host and boot provenance: hostname, kernel boot id, and boot-relative
%% monotonic microseconds from /proc/uptime. Never a wall-clock value.
host_boot() ->
    Host = case inet:gethostname() of {ok, H} -> list_to_binary(H); _ -> <<"unknown-host">> end,
    Boot = case file:read_file("/proc/sys/kernel/random/boot_id") of
        {ok, B} -> string:trim(B); _ -> <<"unknown-boot">> end,
    Up = case file:read_file("/proc/uptime") of
        {ok, U} -> case string:split(U, " ") of
                       [S | _] -> case string:to_float(binary_to_list(S)) of
                                      {F, _} when is_float(F) -> trunc(F * 1000000);
                                      _ -> 0
                                  end;
                       _ -> 0
                   end;
        _ -> 0 end,
    {Host, Boot, Up}.
