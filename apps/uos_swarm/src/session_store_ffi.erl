%% Thin, typed Erlang wrappers over the esqlite hex package (esqlite3),
%% giving uos_swarm/session_store a bounded local SQLite storage interpreter.
%% Policy, schema text, and replay/verify logic all live in Gleam
%% (session_store.gleam); this module only opens connections, runs SQL,
%% marshals rows to/from the Gleam `Cell` type, and reads the same host
%% clock derivation as session_sync_ffi. No exception ever escapes to
%% Gleam: every exported function returns {ok, _} | {error, Reason::binary()}.
-module(session_store_ffi).
-export([open/1, exec/2, query/3, begin_immediate/1, commit/1, rollback/1,
         close/1, clock/0, halt/1]).

-spec halt(integer()) -> no_return().
halt(Code) -> erlang:halt(Code).

%% ---------------------------------------------------------------------
%% Connection lifecycle
%% ---------------------------------------------------------------------

-spec open(binary()) -> {ok, term()} | {error, binary()}.
open(PathBinary) -> guarded(fun() ->
    Path = unicode:characters_to_list(PathBinary),
    case esqlite3:open(Path) of
        {ok, Conn} ->
            ok = pragma(Conn, "PRAGMA journal_mode=WAL;"),
            ok = pragma(Conn, "PRAGMA synchronous=NORMAL;"),
            ok = pragma(Conn, "PRAGMA busy_timeout=30000;"),
            ok = pragma(Conn, "PRAGMA foreign_keys=ON;"),
            {ok, Conn};
        {error, Reason} -> fail(fmt(Reason))
    end
end).

pragma(Conn, Sql) ->
    case esqlite3:exec(Conn, Sql) of
        ok -> ok;
        {ok, _} -> ok;
        {error, Reason} -> fail(fmt(Reason))
    end.

-spec close(term()) -> {ok, nil} | {error, binary()}.
close(Conn) -> guarded(fun() ->
    case esqlite3:close(Conn) of
        ok -> {ok, nil};
        {error, Reason} -> fail(fmt(Reason))
    end
end).

%% ---------------------------------------------------------------------
%% Statement execution
%% ---------------------------------------------------------------------

%% Unparameterized script execution: schema DDL and transaction control
%% statements only. sqlite3_exec natively runs a ";"-separated script.
-spec exec(term(), binary()) -> {ok, integer()} | {error, binary()}.
exec(Conn, SqlBinary) -> guarded(fun() ->
    Sql = unicode:characters_to_list(SqlBinary),
    case esqlite3:exec(Conn, Sql) of
        ok -> {ok, 0};
        {ok, Rows} when is_list(Rows) -> {ok, length(Rows)};
        {error, Reason} -> fail(fmt(Reason))
    end
end).

-spec begin_immediate(term()) -> {ok, integer()} | {error, binary()}.
begin_immediate(Conn) -> exec(Conn, <<"BEGIN IMMEDIATE;">>).

-spec commit(term()) -> {ok, integer()} | {error, binary()}.
commit(Conn) -> exec(Conn, <<"COMMIT;">>).

-spec rollback(term()) -> {ok, integer()} | {error, binary()}.
rollback(Conn) -> exec(Conn, <<"ROLLBACK;">>).

%% Parameterized query: SELECT and data-carrying INSERT statements alike.
%% Params is a list of the Gleam `Cell` type: {cell_text, binary()} |
%% {cell_int, integer()} | cell_null. Rows come back as the same shape, so
%% one typed wire format covers both directions.
-spec query(term(), binary(), list()) -> {ok, list(list())} | {error, binary()}.
query(Conn, SqlBinary, Params) -> guarded(fun() ->
    Sql = unicode:characters_to_list(SqlBinary),
    Args = [to_bind_arg(P) || P <- Params],
    case esqlite3:q(Conn, Sql, Args) of
        Rows when is_list(Rows) ->
            {ok, [row_to_cells(Row) || Row <- Rows]};
        {error, Reason} -> fail(fmt(Reason))
    end
end).

to_bind_arg({cell_text, Bin}) when is_binary(Bin) -> Bin;
to_bind_arg({cell_int, N}) when is_integer(N) -> N;
to_bind_arg(cell_null) -> undefined.

row_to_cells(Row) when is_tuple(Row) -> [cell_of(V) || V <- tuple_to_list(Row)];
row_to_cells(Row) when is_list(Row) -> [cell_of(V) || V <- Row].

cell_of(undefined) -> cell_null;
cell_of(V) when is_binary(V) -> {cell_text, V};
cell_of(V) when is_integer(V) -> {cell_int, V};
%% events.sequence/tick_us/utc_us/inserted_utc_us are always bound as
%% integers; a float only appears if a caller mis-binds a REAL column, which
%% this schema never declares. Round rather than crash so a malformed row is
%% still observable to `verify` instead of throwing across the FFI boundary.
cell_of(V) when is_float(V) -> {cell_int, round(V)};
cell_of(_Other) -> cell_null.

%% ---------------------------------------------------------------------
%% Clock (identical derivation to session_sync_ffi:clock/0, duplicated here
%% so this module has no dependency on the file-journal FFI)
%% ---------------------------------------------------------------------

-spec clock() -> {ok, {binary(), binary(), integer(), integer()}} | {error, binary()}.
clock() -> guarded(fun() ->
    Host = binary:encode_hex(crypto:hash(sha256, trim_read(<<"/etc/machine-id">>)), lowercase),
    Boot = trim_read(<<"/proc/sys/kernel/random/boot_id">>),
    [First | _] = binary:split(trim_read(<<"/proc/uptime">>), <<" ">>, [global]),
    [Seconds, Fraction] = binary:split(First, <<".">>),
    Scale = trunc(math:pow(10, byte_size(Fraction))),
    Tick = binary_to_integer(Seconds) * 1000000 + binary_to_integer(Fraction) * 1000000 div Scale,
    {ok, {Host, Boot, Tick, erlang:system_time(microsecond)}}
end).

trim_read(Path) ->
    {ok, Bin} = file:read_file(Path),
    string:trim(Bin).

%% ---------------------------------------------------------------------
%% Error boundary
%% ---------------------------------------------------------------------

guarded(Fun) ->
    try Fun()
    catch
        throw:{storage, Reason} -> {error, Reason};
        error:{badmatch, {error, Reason}} -> {error, fmt(Reason)};
        Class:Reason -> {error, iolist_to_binary(io_lib:format("sqlite ~p: ~p", [Class, Reason]))}
    end.

fail(Reason) -> throw({storage, Reason}).
fmt(Reason) when is_binary(Reason) -> Reason;
fmt(Reason) -> iolist_to_binary(io_lib:format("~p", [Reason])).
