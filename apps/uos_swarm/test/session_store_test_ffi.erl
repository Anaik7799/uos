%% Test-only helpers for session_store: raw (unwrapped) SQL against a
%% database file, independent of session_store_ffi's own connection and
%% pragmas, used to build negative controls (raw UPDATE/DELETE against the
%% append-only triggers, a hand-tampered row for `verify` to catch).
-module(session_store_test_ffi).
-export([raw_exec/2, copy_file/2]).

raw_exec(PathBinary, SqlBinary) ->
    Path = unicode:characters_to_list(PathBinary),
    Sql = unicode:characters_to_list(SqlBinary),
    Statements = [string:trim(S) || S <- string:lexemes(Sql, ";"), string:trim(S) =/= ""],
    case esqlite3:open(Path) of
        {ok, Conn} ->
            ExecAll = fun Loop([]) -> ok;
                          Loop([Stmt | Rest]) ->
                              case esqlite3:exec(Conn, Stmt) of
                                  ok -> Loop(Rest);
                                  {ok, _} -> Loop(Rest);
                                  {error, Reason} -> {error, {Stmt, Reason}}
                              end
                      end,
            Result = ExecAll(Statements),
            _ = esqlite3:close(Conn),
            case Result of
                ok -> {ok, nil};
                {error, Reason} -> {error, fmt(Reason)}
            end;
        {error, Reason} -> {error, fmt(Reason)}
    end.

%% Copies the main database file plus any WAL/SHM sidecar files that exist
%% alongside it (journal_mode=WAL means recent commits can still live only
%% in "<path>-wal" until a checkpoint; copying the main file alone can
%% silently produce a copy missing the tail of the chain).
copy_file(FromBinary, ToBinary) ->
    From = unicode:characters_to_list(FromBinary),
    To = unicode:characters_to_list(ToBinary),
    case file:copy(From, To) of
        {ok, _Bytes} ->
            case copy_sidecar(From ++ "-wal", To ++ "-wal") of
                ok ->
                    case copy_sidecar(From ++ "-shm", To ++ "-shm") of
                        ok -> {ok, nil};
                        {error, Reason} -> {error, fmt(Reason)}
                    end;
                {error, Reason} -> {error, fmt(Reason)}
            end;
        {error, Reason} -> {error, fmt(Reason)}
    end.

copy_sidecar(From, To) ->
    case file:copy(From, To) of
        {ok, _Bytes} -> ok;
        {error, enoent} -> ok;
        {error, Reason} -> {error, Reason}
    end.

fmt(Reason) when is_binary(Reason) -> Reason;
fmt(Reason) -> unicode:characters_to_binary(io_lib:format("~p", [Reason])).
