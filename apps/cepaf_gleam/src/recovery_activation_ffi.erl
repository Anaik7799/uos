%% =============================================================================
%% UOS Recovery Activation FFI
%% -----------------------------------------------------------------------------
%% Bounded native filesystem, lock, generation, quiescence, and SQLite
%% integrity facade for typed recovery activation.
%%
%% Governing contracts:
%% - contracts/rules/20260907-0653-tri-agent-coordination.md (SYNC-04)
%% - contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md (SC-HARNESS-MCP-001)
%% - contracts/rules/20260908-0912-provenance-integrity-contract.md (SC-PROVENANCE-001)
%%
%% Invariants:
%% 1. All command selection, policy, state machines, and authority checks live
%%    in Gleam (recovery_activation.gleam). This Erlang module is strictly a
%%    bounded IO interpreter.
%% 2. Exclusive per-target lock at TARGET.recovery-lock (O_CREAT | O_EXCL).
%%    If lock exists, check PID liveness on host/boot. Refuse active or unknown
%%    owners; never blindly delete locks.
%% 3. Persistent generation tracking at TARGET.recovery-generation. Advanced
%%    atomically under lock BEFORE preservation/swap. Never removed, even on
%%    rollback, retiring stale open handles.
%% 4. Quiescence verification via bounded fuser/lsof probe, rechecked under
%%    lock after generation advance.
%% 5. Full path safety checking inspecting all ancestor directories from /
%%    for ownership, permissions, and symlink absence.
%% 6. Atomic staged swap: candidate -> TARGET.swap-tmp -> fsync -> rename.
%%    Preserve originals (DB, WAL, SHM) into immutable backup directory.
%% 7. Reopened SQLite PRAGMA integrity_check and cryptographic chain verification.
%% 8. Real host/boot clock required (fail closed on missing /etc/machine-id).
%% 9. No unhandled exception escapes to Gleam: {ok, Val} | {error, Binary}.
%% =============================================================================
-module(recovery_activation_ffi).

-export([
    get_pid/0,
    clock/0,
    utc_now_iso8601/0,
    sha256_file/1,
    path_safety_check/1,
    check_private_file/1,
    acquire_target_lock/2,
    release_target_lock/2,
    hold_target_lock/3,
    is_target_locked/1,
    read_target_lock/1,
    read_generation/1,
    advance_generation/2,
    check_quiescence/1,
    preserve_target_files/2,
    preserve_target_state/7,
    retire_target_sidecars/1,
    persist_phase_receipt/6,
    staged_swap_database/2,
    staged_swap_database/3,
    rollback_database/4,
    rollback_from_manifest/2,
    copy_file_exclusive/2,
    sqlite_verify_integrity/1,
    sqlite_checkpoint/1,
    verify_cycle_chain/1,
    verify_coordinator_chain/1,
    file_exists/1,
    read_file_binary/1,
    write_file_binary/2,
    change_file_mode/2,
    delete_file/1,
    list_dir/1,
    get_argv/0,
    create_test_db/2,
    create_test_coordinator_db/1,
    create_test_cycle_db/1
]).

-include_lib("kernel/include/file.hrl").

-define(CHUNK_SIZE, 65536).
-define(MAX_FILE_BYTES, 1073741824). % 1 GiB ceiling for single recovery candidate
-define(MAX_QUIESCENCE_TIMEOUT_MS, 3000).

%% ---------------------------------------------------------------------
%% Process & Clock (Strict Host & Boot Authority)
%% ---------------------------------------------------------------------

-spec get_pid() -> integer().
get_pid() ->
    list_to_integer(os:getpid()).

-spec clock() -> {ok, {binary(), binary(), integer(), integer()}} | {error, binary()}.
clock() ->
    guarded(fun() ->
        Host = case file:read_file("/etc/machine-id") of
            {ok, Bin} ->
                Trimmed = string:trim(Bin),
                case byte_size(Trimmed) of
                    0 -> fail(<<"empty_machine_id">>);
                    _ -> binary:encode_hex(crypto:hash(sha256, Trimmed), lowercase)
                end;
            {error, Reason} ->
                fail(iolist_to_binary(io_lib:format("cannot_read_machine_id:~p", [Reason])))
        end,
        Boot = case file:read_file("/proc/sys/kernel/random/boot_id") of
            {ok, BootBin} ->
                TrimmedBoot = string:trim(BootBin),
                case byte_size(TrimmedBoot) of
                    0 -> fail(<<"empty_boot_id">>);
                    _ -> TrimmedBoot
                end;
            {error, BReason} ->
                fail(iolist_to_binary(io_lib:format("cannot_read_boot_id:~p", [BReason])))
        end,
        Tick = case file:read_file("/proc/uptime") of
            {ok, UpBin} ->
                [First | _] = binary:split(string:trim(UpBin), <<" ">>, [global]),
                [Seconds, Fraction] = binary:split(First, <<".">>),
                Scale = trunc(math:pow(10, byte_size(Fraction))),
                binary_to_integer(Seconds) * 1000000 + binary_to_integer(Fraction) * 1000000 div Scale;
            {error, UReason} ->
                fail(iolist_to_binary(io_lib:format("cannot_read_uptime:~p", [UReason])))
        end,
        {ok, {Host, Boot, Tick, erlang:system_time(microsecond)}}
    end).

-spec utc_now_iso8601() -> binary().
utc_now_iso8601() ->
    list_to_binary(calendar:system_time_to_rfc3339(erlang:system_time(second), [{offset, "Z"}, {unit, second}])).

%% ---------------------------------------------------------------------
%% File Hashing & Full Ancestor Path Safety Verification
%% ---------------------------------------------------------------------

-spec sha256_file(binary()) -> {ok, binary()} | {error, binary()}.
sha256_file(PathBinary) ->
    guarded(fun() ->
        Path = unicode:characters_to_list(PathBinary),
        case file:read_file_info(Path) of
            {ok, #file_info{type = regular, size = Size}} when Size =< ?MAX_FILE_BYTES ->
                case file:open(Path, [read, binary, raw]) of
                    {ok, Fd} ->
                        try
                            HashCtx = crypto:hash_init(sha256),
                            Hex = stream_hash(Fd, HashCtx, Size),
                            {ok, Hex}
                        after
                            file:close(Fd)
                        end;
                    {error, OpenReason} ->
                        fail(fmt(OpenReason))
                end;
            {ok, #file_info{type = regular, size = _}} ->
                fail(<<"file_size_exceeds_ceiling">>);
            {ok, #file_info{type = Type}} ->
                fail(iolist_to_binary(io_lib:format("not_regular_file:~p", [Type])));
            {error, Reason} ->
                fail(fmt(Reason))
        end
    end).

stream_hash(_Fd, HashCtx, 0) ->
    binary:encode_hex(crypto:hash_final(HashCtx), lowercase);
stream_hash(Fd, HashCtx, Remaining) when Remaining > 0 ->
    ToRead = min(?CHUNK_SIZE, Remaining),
    case file:read(Fd, ToRead) of
        {ok, Chunk} when byte_size(Chunk) =< Remaining, byte_size(Chunk) > 0 ->
            NextCtx = crypto:hash_update(HashCtx, Chunk),
            stream_hash(Fd, NextCtx, Remaining - byte_size(Chunk));
        {error, Reason} ->
            fail(fmt(Reason));
        _ ->
            fail(<<"unexpected_hash_stream_state">>)
    end.

-spec path_safety_check(binary()) -> {ok, nil} | {error, binary()}.
path_safety_check(PathBinary) ->
    guarded(fun() ->
        case binary:match(PathBinary, [<<0>>, <<"\r">>, <<"\n">>]) of
            nomatch -> ok;
            _ -> fail(<<"path_contains_illegal_control_characters">>)
        end,
        Path = unicode:characters_to_list(PathBinary),
        case Path of
            [$/ | _] -> ok;
            _ -> fail(<<"path_must_be_absolute">>)
        end,
        Components = string:split(Path, "/", all),
        case Components of
            ["", "" | _] -> fail(<<"path_cannot_have_double_slashes">>);
            ["" | Parts] ->
                case Parts of
                    [] -> fail(<<"path_cannot_be_root">>);
                    _ ->
                        lists:foreach(fun(Part) ->
                            case Part of
                                "" -> fail(<<"empty_path_component">>);
                                "." -> fail(<<"dot_component_rejected">>);
                                ".." -> fail(<<"dotdot_component_rejected">>);
                                _ -> ok
                            end
                        end, Parts)
                end;
            _ -> fail(<<"path_must_be_absolute">>)
        end,
        CurrentUid = case file:read_file_info("/proc/self") of
            {ok, #file_info{uid = Uid}} -> Uid;
            _ -> os:getuid()
        end,
        %% Full ancestor traversal: inspect every directory from / to target parent
        Ancestors = get_ancestors(Path),
        lists:foreach(fun(Dir) ->
            case file:read_link_info(Dir) of
                {ok, #file_info{type = symlink}} ->
                    fail(iolist_to_binary(io_lib:format("ancestor_is_symlink:~s", [Dir])));
                {ok, #file_info{type = directory, uid = OwnerUid, mode = Mode}} ->
                    OwnerOk = (OwnerUid =:= 0) orelse (OwnerUid =:= CurrentUid),
                    case OwnerOk of
                        true -> ok;
                        false -> fail(iolist_to_binary(io_lib:format("ancestor_untrusted_owner:~s", [Dir])))
                    end,
                    PermOk = ((Mode band 8#002) =:= 0) orelse ((Mode band 8#1000) =/= 0),
                    case PermOk of
                        true -> ok;
                        false -> fail(iolist_to_binary(io_lib:format("ancestor_insecure_permissions:~s", [Dir])))
                    end;
                {ok, #file_info{type = OtherType}} ->
                    fail(iolist_to_binary(io_lib:format("ancestor_not_directory:~s:~p", [Dir, OtherType])));
                {error, Reason} ->
                    fail(iolist_to_binary(io_lib:format("ancestor_unreadable:~s:~p", [Dir, Reason])))
            end
        end, Ancestors),
        %% Target file itself (if present)
        case file:read_link_info(Path) of
            {ok, #file_info{type = symlink}} ->
                fail(<<"symlink_path_rejected">>);
            {ok, #file_info{type = regular}} ->
                ok;
            {ok, #file_info{type = directory}} ->
                ok; % valid for directories like backup_dir
            {ok, #file_info{type = OtherT}} ->
                fail(iolist_to_binary(io_lib:format("target_not_regular_or_dir:~p", [OtherT])));
            {error, enoent} ->
                ok;
            {error, Reason} ->
                fail(fmt(Reason))
        end,
        {ok, nil}
    end).

get_ancestors(Path) ->
    Dir = filename:dirname(Path),
    get_ancestors_acc(Dir, []).

get_ancestors_acc("/", Acc) ->
    ["/" | Acc];
get_ancestors_acc(Dir, Acc) ->
    Parent = filename:dirname(Dir),
    get_ancestors_acc(Parent, [Dir | Acc]).

-spec check_private_file(binary()) -> {ok, nil} | {error, binary()}.
check_private_file(PathBinary) ->
    guarded(fun() ->
        case path_safety_check(PathBinary) of
            {ok, nil} -> ok;
            {error, Err} -> fail(Err)
        end,
        Path = unicode:characters_to_list(PathBinary),
        case file:read_link_info(Path) of
            {ok, #file_info{type = regular, uid = OwnerUid, mode = Mode}} ->
                CurrentUid = case file:read_file_info("/proc/self") of
                    {ok, #file_info{uid = Uid}} -> Uid;
                    _ -> os:getuid()
                end,
                case (OwnerUid =:= 0) orelse (OwnerUid =:= CurrentUid) of
                    true -> ok;
                    false -> fail(iolist_to_binary(io_lib:format("private_file_untrusted_owner:~s", [Path])))
                end,
                case (Mode band 8#022) =:= 0 of
                    true -> ok;
                    false -> fail(iolist_to_binary(io_lib:format("private_file_insecure_permissions:~s", [Path])))
                end,
                {ok, nil};
            {ok, #file_info{type = symlink}} ->
                fail(<<"private_file_is_symlink">>);
            {ok, #file_info{type = Other}} ->
                fail(iolist_to_binary(io_lib:format("private_file_not_regular:~p", [Other])));
            {error, Reason} ->
                fail(fmt(Reason))
        end
    end).

%% ---------------------------------------------------------------------
%% Target Lock Operations (TARGET.recovery-lock)
%% ---------------------------------------------------------------------

-spec acquire_target_lock(binary(), binary()) -> {ok, nil} | {error, binary()}.
acquire_target_lock(LockPathBinary, PayloadBinary) ->
    guarded(fun() ->
        LockPath = unicode:characters_to_list(LockPathBinary),
        case file:open(LockPath, [write, exclusive, raw, binary]) of
            {ok, Fd} ->
                try
                    ok = file:write(Fd, PayloadBinary),
                    ok = file:change_mode(LockPath, 8#600),
                    ok = file:sync(Fd),
                    {ok, nil}
                after
                    file:close(Fd)
                end;
            {error, eexist} ->
                case file:read_file(LockPath) of
                    {ok, ExistingContent} ->
                        inspect_existing_lock(ExistingContent);
                    {error, ReadReason} ->
                        fail(iolist_to_binary(io_lib:format("existing_lock_unreadable:~p", [ReadReason])))
                end;
            {error, Reason} ->
                fail(fmt(Reason))
        end
    end).

inspect_existing_lock(Content) ->
    try
        Decoded = json:decode(Content),
        case maps:get(<<"status">>, Decoded, <<"ACTIVE">>) of
            <<"HOLD">> ->
                fail(<<"target_locked_in_hold_state">>);
            _ ->
                Pid = maps:get(<<"pid">>, Decoded),
                HostId = maps:get(<<"host_id">>, Decoded),
                BootId = maps:get(<<"boot_id">>, Decoded),
                {ok, {CurrentHost, CurrentBoot, _, _}} = clock(),
                case {HostId =:= CurrentHost, BootId =:= CurrentBoot} of
                    {true, true} ->
                        PidStr = integer_to_list(Pid),
                        case file:read_file_info("/proc/" ++ PidStr) of
                            {ok, #file_info{type = directory}} ->
                                fail(<<"target_locked_by_active_owner">>);
                            _ ->
                                fail(<<"target_locked_by_stale_owner">>)
                        end;
                    _ ->
                        fail(<<"target_locked_by_foreign_owner">>)
                end
        end
    catch
        throw:{storage, Err} -> fail(Err);
        _:_ -> fail(<<"target_locked_with_invalid_payload">>)
    end.

-spec release_target_lock(binary(), integer()) -> {ok, nil} | {error, binary()}.
release_target_lock(LockPathBinary, ExpectedPid) ->
    guarded(fun() ->
        LockPath = unicode:characters_to_list(LockPathBinary),
        case file:read_file(LockPath) of
            {ok, Content} ->
                try
                    Decoded = json:decode(Content),
                    case maps:get(<<"pid">>, Decoded, undefined) of
                        ExpectedPid ->
                            ok = file:delete(LockPath),
                            {ok, nil};
                        OtherPid ->
                            fail(iolist_to_binary(io_lib:format("lock_owned_by_different_pid:~p", [OtherPid])))
                    end
                catch
                    throw:{storage, Err} -> fail(Err);
                    _:_ -> fail(<<"corrupt_lock_payload_on_release">>)
                end;
            {error, enoent} ->
                {ok, nil};
            {error, Reason} ->
                fail(fmt(Reason))
        end
    end).

-spec hold_target_lock(binary(), binary(), binary()) -> {ok, nil} | {error, binary()}.
hold_target_lock(LockPathBinary, ReasonBinary, UtcStringBinary) ->
    guarded(fun() ->
        LockPath = unicode:characters_to_list(LockPathBinary),
        Pid = get_pid(),
        {ok, {Host, Boot, _, _}} = clock(),
        PayloadMap = #{
            <<"schema">> => <<"uos.recovery-lock.v1">>,
            <<"status">> => <<"HOLD">>,
            <<"reason">> => ReasonBinary,
            <<"pid">> => Pid,
            <<"host_id">> => Host,
            <<"boot_id">> => Boot,
            <<"timestamp_utc">> => UtcStringBinary
        },
        Payload = json:encode(PayloadMap),
        TmpLock = LockPath ++ ".hold-tmp",
        case file:open(TmpLock, [write, binary, raw]) of
            {ok, Fd} ->
                try
                    ok = file:write(Fd, Payload),
                    ok = file:change_mode(TmpLock, 8#600),
                    ok = file:sync(Fd)
                after
                    file:close(Fd)
                end,
                case file:rename(TmpLock, LockPath) of
                    ok ->
                        ok = sync_directory(filename:dirname(LockPath)),
                        {ok, nil};
                    {error, RenameErr} ->
                        _ = file:delete(TmpLock),
                        fail(fmt(RenameErr))
                end;
            {error, OpenErr} ->
                fail(fmt(OpenErr))
        end
    end).

-spec is_target_locked(binary()) -> {ok, boolean()} | {error, binary()}.
is_target_locked(LockPathBinary) ->
    guarded(fun() ->
        LockPath = unicode:characters_to_list(LockPathBinary),
        Exists = filelib:is_regular(LockPath),
        {ok, Exists}
    end).

-spec read_target_lock(binary()) -> {ok, binary()} | {error, binary()}.
read_target_lock(LockPathBinary) ->
    guarded(fun() ->
        LockPath = unicode:characters_to_list(LockPathBinary),
        case file:read_file(LockPath) of
            {ok, Content} -> {ok, Content};
            {error, Reason} -> fail(fmt(Reason))
        end
    end).

%% ---------------------------------------------------------------------
%% Persistent Generation Token Tracking (TARGET.recovery-generation)
%% ---------------------------------------------------------------------

-spec read_generation(binary()) -> {ok, binary()} | {error, binary()}.
read_generation(GenPathBinary) ->
    guarded(fun() ->
        GenPath = unicode:characters_to_list(GenPathBinary),
        case file:read_file(GenPath) of
            {ok, Content} -> {ok, string:trim(Content)};
            {error, enoent} -> {ok, <<"genesis">>};
            {error, Reason} -> fail(fmt(Reason))
        end
    end).

-spec advance_generation(binary(), binary()) -> {ok, nil} | {error, binary()}.
advance_generation(GenPathBinary, TokenBinary) ->
    guarded(fun() ->
        GenPath = unicode:characters_to_list(GenPathBinary),
        TmpPath = GenPath ++ ".tmp",
        case file:open(TmpPath, [write, binary, raw]) of
            {ok, Fd} ->
                try
                    ok = file:write(Fd, TokenBinary),
                    ok = file:change_mode(TmpPath, 8#600),
                    ok = file:sync(Fd)
                after
                    file:close(Fd)
                end;
            {error, OpenErr} ->
                fail(fmt(OpenErr))
        end,
        case file:rename(TmpPath, GenPath) of
            ok ->
                _ = sync_directory(filename:dirname(GenPath)),
                {ok, nil};
            {error, RenameErr} ->
                _ = file:delete(TmpPath),
                fail(fmt(RenameErr))
        end
    end).

%% ---------------------------------------------------------------------
%% Quiescence Verification (fuser / lsof)
%% ---------------------------------------------------------------------

-spec check_quiescence(binary()) -> {ok, nil} | {error, binary()}.
check_quiescence(TargetPathBinary) ->
    guarded(fun() ->
        TargetPath = unicode:characters_to_list(TargetPathBinary),
        FilesToCheck = [
            TargetPath,
            TargetPath ++ "-wal",
            TargetPath ++ "-shm"
        ],
        ExistingFiles = lists:filter(fun(F) -> filelib:is_regular(F) end, FilesToCheck),
        case ExistingFiles of
            [] ->
                {ok, nil};
            _ ->
                lists:foreach(fun(File) ->
                    case probe_single_file_quiescence(File) of
                        quiescent -> ok;
                        in_use -> fail(iolist_to_binary(io_lib:format("target_or_sidecar_has_active_file_descriptors:~s", [filename:basename(File)])));
                        {error, Reason} -> fail(Reason)
                    end
                end, ExistingFiles),
                {ok, nil}
        end
    end).

probe_single_file_quiescence(FilePath) ->
    FuserBin = "/usr/bin/fuser",
    case filelib:is_regular(FuserBin) of
        true ->
            Port = erlang:open_port(
                {spawn_executable, FuserBin},
                [
                    {args, [FilePath]},
                    exit_status,
                    stderr_to_stdout,
                    binary
                ]
            ),
            collect_quiescence(Port, fuser);
        false ->
            LsofBin = "/usr/bin/lsof",
            case filelib:is_regular(LsofBin) of
                true ->
                    Port = erlang:open_port(
                        {spawn_executable, LsofBin},
                        [
                            {args, [FilePath]},
                            exit_status,
                            stderr_to_stdout,
                            binary
                        ]
                    ),
                    collect_quiescence(Port, lsof);
                false ->
                    {error, <<"quiescence_probe_tool_missing">>}
            end
    end.

collect_quiescence(Port, Tool) ->
    receive
        {Port, {exit_status, Code}} ->
            case {Tool, Code} of
                {fuser, 1} -> quiescent;
                {fuser, 0} -> in_use;
                {lsof, 1} -> quiescent;
                {lsof, 0} -> in_use;
                {_, Other} -> {error, iolist_to_binary(io_lib:format("quiescence_probe_failed:~p", [Other]))}
            end
    after ?MAX_QUIESCENCE_TIMEOUT_MS ->
        _ = (try erlang:port_close(Port) catch _:_ -> ok end),
        {error, <<"quiescence_probe_timeout">>}
    end.

%% ---------------------------------------------------------------------
%% Target Preservation & Atomic Swap
%% ---------------------------------------------------------------------

-spec copy_file_exclusive(string(), string()) -> {ok, binary()} | no_return().
copy_file_exclusive(Src, Dst) ->
    case file:read_file(Src) of
        {ok, Content} ->
            case file:open(Dst, [write, exclusive, binary, raw]) of
                {ok, Fd} ->
                    try
                        ok = file:write(Fd, Content),
                        ok = file:change_mode(Dst, 8#400),
                        ok = file:sync(Fd)
                    after
                        file:close(Fd)
                    end,
                    Sha256 = binary:encode_hex(crypto:hash(sha256, Content), lowercase),
                    {ok, Sha256};
                {error, eexist} ->
                    fail(iolist_to_binary(io_lib:format("backup_destination_already_exists_no_truncate:~s", [Dst])));
                {error, OpenErr} ->
                    fail(fmt(OpenErr))
            end;
        {error, ReadErr} ->
            fail(fmt(ReadErr))
    end.

copy_file_exact(Src, Dst) ->
    case file:read_file(Src) of
        {ok, Content} ->
            case file:open(Dst, [write, binary, raw]) of
                {ok, Fd} ->
                    try
                        ok = file:write(Fd, Content),
                        ok = file:change_mode(Dst, 8#600),
                        ok = file:sync(Fd)
                    after
                        file:close(Fd)
                    end;
                {error, WReason} ->
                    fail(fmt(WReason))
            end;
        {error, RReason} ->
            fail(fmt(RReason))
    end.

-spec sync_directory(string()) -> ok | no_return().
sync_directory(Dir) ->
    case file:open(Dir, [read, raw, directory]) of
        {ok, Fd} ->
            try
                case file:sync(Fd) of
                    ok -> ok;
                    {error, SyncErr} -> fail(iolist_to_binary(io_lib:format("dir_sync_failed:~s:~p", [Dir, SyncErr])))
                end
            after
                file:close(Fd)
            end;
        {error, OpenErr} ->
            fail(iolist_to_binary(io_lib:format("dir_open_for_sync_failed:~s:~p", [Dir, OpenErr])))
    end.

-spec preserve_target_files(binary(), binary()) ->
    {ok, {binary(), binary(), binary()}} | {error, binary()}.
preserve_target_files(TargetPathBinary, BackupDirBinary) ->
    guarded(fun() ->
        TargetPath = unicode:characters_to_list(TargetPathBinary),
        BackupDir = unicode:characters_to_list(BackupDirBinary),
        ok = filelib:ensure_path(BackupDir),
        ok = file:change_mode(BackupDir, 8#700),

        BaseName = filename:basename(TargetPath),
        TargetBackup = filename:join(BackupDir, BaseName),
        WalBackup = filename:join(BackupDir, BaseName ++ "-wal"),
        ShmBackup = filename:join(BackupDir, BaseName ++ "-shm"),

        TargetOut = case filelib:is_regular(TargetPath) of
            true ->
                ok = copy_file_exact(TargetPath, TargetBackup),
                unicode:characters_to_binary(TargetBackup);
            false ->
                <<>>
        end,

        WalPath = TargetPath ++ "-wal",
        WalOut = case filelib:is_regular(WalPath) of
            true ->
                ok = copy_file_exact(WalPath, WalBackup),
                unicode:characters_to_binary(WalBackup);
            false ->
                <<>>
        end,

        ShmPath = TargetPath ++ "-shm",
        ShmOut = case filelib:is_regular(ShmPath) of
            true ->
                ok = copy_file_exact(ShmPath, ShmBackup),
                unicode:characters_to_binary(ShmBackup);
            false ->
                <<>>
        end,

        ok = sync_directory(BackupDir),
        {ok, {TargetOut, WalOut, ShmOut}}
    end).

-spec preserve_target_state(binary(), binary(), binary(), integer(), binary(), integer(), binary()) ->
    {ok, {binary(), binary(), binary(), binary(), binary()}} | {error, binary()}.
preserve_target_state(TargetPathBinary, BackupDirBinary, IntentIdBinary, AttemptInt, GenTokenBinary, UtcUsInt, UtcStringBinary) ->
    guarded(fun() ->
        TargetPath = unicode:characters_to_list(TargetPathBinary),
        BaseBackupDir = unicode:characters_to_list(BackupDirBinary),
        ok = filelib:ensure_path(BaseBackupDir),
        
        IntentStr = unicode:characters_to_list(IntentIdBinary),
        AttemptStr = integer_to_list(AttemptInt),
        UniqueDirName = "bk-" ++ IntentStr ++ "-att" ++ AttemptStr,
        UniqueBackupDir = filename:join(BaseBackupDir, UniqueDirName),

        case file:make_dir(UniqueBackupDir) of
            ok -> ok;
            {error, eexist} -> fail(iolist_to_binary(io_lib:format("unique_backup_dir_already_exists:~s", [UniqueBackupDir])));
            {error, MkErr} -> fail(fmt(MkErr))
        end,
        ok = file:change_mode(UniqueBackupDir, 8#700),

        BaseName = filename:basename(TargetPath),
        TargetBackup = filename:join(UniqueBackupDir, BaseName),
        WalBackup = filename:join(UniqueBackupDir, BaseName ++ "-wal"),
        ShmBackup = filename:join(UniqueBackupDir, BaseName ++ "-shm"),

        {TargetOut, TargetHash} = case filelib:is_regular(TargetPath) of
            true ->
                {ok, THash} = copy_file_exclusive(TargetPath, TargetBackup),
                {unicode:characters_to_binary(TargetBackup), THash};
            false ->
                {<<>>, <<>>}
        end,

        WalPath = TargetPath ++ "-wal",
        {WalOut, WalHash} = case filelib:is_regular(WalPath) of
            true ->
                {ok, WHash} = copy_file_exclusive(WalPath, WalBackup),
                {unicode:characters_to_binary(WalBackup), WHash};
            false ->
                {<<>>, <<>>}
        end,

        ShmPath = TargetPath ++ "-shm",
        {ShmOut, ShmHash} = case filelib:is_regular(ShmPath) of
            true ->
                {ok, SHash} = copy_file_exclusive(ShmPath, ShmBackup),
                {unicode:characters_to_binary(ShmBackup), SHash};
            false ->
                {<<>>, <<>>}
        end,

        ManifestMap = #{
            <<"schema">> => <<"uos.recovery-backup-manifest.v1">>,
            <<"intent_id">> => IntentIdBinary,
            <<"attempt">> => AttemptInt,
            <<"target_path">> => TargetPathBinary,
            <<"backup_target_path">> => TargetOut,
            <<"backup_wal_path">> => WalOut,
            <<"backup_shm_path">> => ShmOut,
            <<"target_sha256">> => TargetHash,
            <<"wal_sha256">> => WalHash,
            <<"shm_sha256">> => ShmHash,
            <<"generation_token">> => GenTokenBinary,
            <<"utc_us">> => UtcUsInt,
            <<"timestamp_utc">> => UtcStringBinary
        },
        ManifestPayload = json:encode(ManifestMap),
        ManifestPath = filename:join(UniqueBackupDir, "manifest.json"),
        case file:open(ManifestPath, [write, exclusive, binary, raw]) of
            {ok, MFd} ->
                try
                    ok = file:write(MFd, ManifestPayload),
                    ok = file:change_mode(ManifestPath, 8#400),
                    ok = file:sync(MFd)
                after
                    file:close(MFd)
                end;
            {error, MErr} ->
                fail(fmt(MErr))
        end,

        ok = sync_directory(UniqueBackupDir),
        ok = sync_directory(BaseBackupDir),

        {ok, {
            unicode:characters_to_binary(UniqueBackupDir),
            TargetOut,
            WalOut,
            ShmOut,
            TargetHash
        }}
    end).

-spec retire_target_sidecars(binary()) -> {ok, nil} | {error, binary()}.
retire_target_sidecars(TargetPathBinary) ->
    guarded(fun() ->
        TargetPath = unicode:characters_to_list(TargetPathBinary),
        WalPath = TargetPath ++ "-wal",
        ShmPath = TargetPath ++ "-shm",
        case filelib:is_regular(WalPath) of
            true ->
                case file:delete(WalPath) of
                    ok -> ok;
                    {error, WalErr} -> fail(iolist_to_binary(io_lib:format("cannot_delete_wal_sidecar:~s:~p", [WalPath, WalErr])))
                end;
            false ->
                ok
        end,
        case filelib:is_regular(ShmPath) of
            true ->
                case file:delete(ShmPath) of
                    ok -> ok;
                    {error, ShmErr} -> fail(iolist_to_binary(io_lib:format("cannot_delete_shm_sidecar:~s:~p", [ShmPath, ShmErr])))
                end;
            false ->
                ok
        end,
        ok = sync_directory(filename:dirname(TargetPath)),
        {ok, nil}
    end).

-spec staged_swap_database(binary(), binary(), binary()) -> {ok, nil} | {error, binary()}.
staged_swap_database(CandidatePathBinary, TargetPathBinary, ExpectedCandidateSha256) ->
    guarded(fun() ->
        CandidatePath = unicode:characters_to_list(CandidatePathBinary),
        TargetPath = unicode:characters_to_list(TargetPathBinary),
        SwapTmp = TargetPath ++ ".swap-tmp",

        case file:read_file(CandidatePath) of
            {ok, Content} ->
                case file:open(SwapTmp, [write, exclusive, binary, raw]) of
                    {ok, Fd} ->
                        try
                            ok = file:write(Fd, Content),
                            ok = file:change_mode(SwapTmp, 8#600),
                            ok = file:sync(Fd)
                        after
                            file:close(Fd)
                        end;
                    {error, eexist} ->
                        fail(iolist_to_binary(io_lib:format("swap_tmp_already_exists_no_truncate:~s", [SwapTmp])));
                    {error, OpenErr} ->
                        fail(fmt(OpenErr))
                end;
            {error, ReadErr} ->
                fail(fmt(ReadErr))
        end,

        %% Verify written temp file hash matches expected candidate hash before file:rename
        case sha256_file(unicode:characters_to_binary(SwapTmp)) of
            {ok, ExpectedCandidateSha256} ->
                ok;
            {ok, SwapTmpHash} ->
                _ = file:delete(SwapTmp),
                fail(iolist_to_binary(io_lib:format("swap_tmp_hash_mismatch:expected ~s found ~s", [ExpectedCandidateSha256, SwapTmpHash])));
            {error, HashErr} ->
                _ = file:delete(SwapTmp),
                fail(iolist_to_binary(io_lib:format("cannot_hash_swap_tmp:~p", [HashErr])))
        end,

        case file:rename(SwapTmp, TargetPath) of
            ok ->
                ParentDir = filename:dirname(TargetPath),
                ok = sync_directory(ParentDir),
                {ok, nil};
            {error, RenameErr} ->
                _ = file:delete(SwapTmp),
                fail(fmt(RenameErr))
        end
    end).

-spec staged_swap_database(binary(), binary()) -> {ok, nil} | {error, binary()}.
staged_swap_database(CandidatePathBinary, TargetPathBinary) ->
    case sha256_file(CandidatePathBinary) of
        {ok, ExpectedHash} ->
            staged_swap_database(CandidatePathBinary, TargetPathBinary, ExpectedHash);
        {error, Err} ->
            {error, Err}
    end.

-spec persist_phase_receipt(binary(), binary(), binary(), integer(), binary(), binary()) -> {ok, nil} | {error, binary()}.
persist_phase_receipt(BackupDirBinary, IntentIdBinary, PhaseBinary, UtcUsInt, UtcStringBinary, ExtraJsonBinary) ->
    guarded(fun() ->
        BackupDir = unicode:characters_to_list(BackupDirBinary),
        ok = filelib:ensure_path(BackupDir),
        PhaseReceiptFile = filename:join(BackupDir, "phase_receipt.json"),
        TmpFile = PhaseReceiptFile ++ ".tmp",
        
        ReceiptMap = #{
            <<"schema">> => <<"uos.recovery-phase-receipt.v1">>,
            <<"intent_id">> => IntentIdBinary,
            <<"phase">> => PhaseBinary,
            <<"utc_us">> => UtcUsInt,
            <<"timestamp_utc">> => UtcStringBinary,
            <<"details">> => ExtraJsonBinary
        },
        Payload = json:encode(ReceiptMap),
        case file:open(TmpFile, [write, binary, raw]) of
            {ok, Fd} ->
                try
                    ok = file:write(Fd, Payload),
                    ok = file:change_mode(TmpFile, 8#600),
                    ok = file:sync(Fd)
                after
                    file:close(Fd)
                end,
                case file:rename(TmpFile, PhaseReceiptFile) of
                    ok ->
                        ok = sync_directory(BackupDir),
                        {ok, nil};
                    {error, RenameErr} ->
                        _ = file:delete(TmpFile),
                        fail(fmt(RenameErr))
                end;
            {error, OpenErr} ->
                fail(fmt(OpenErr))
        end
    end).

-spec rollback_database(binary(), binary(), binary(), binary()) -> {ok, nil} | {error, binary()}.
rollback_database(TargetPathBinary, BackupTargetBinary, BackupWalBinary, BackupShmBinary) ->
    guarded(fun() ->
        TargetPath = unicode:characters_to_list(TargetPathBinary),
        BackupTarget = unicode:characters_to_list(BackupTargetBinary),
        BackupWal = unicode:characters_to_list(BackupWalBinary),
        BackupShm = unicode:characters_to_list(BackupShmBinary),

        _ = file:delete(TargetPath ++ ".swap-tmp"),

        case BackupTarget =/= "" andalso filelib:is_regular(BackupTarget) of
            true ->
                RollbackTmp = TargetPath ++ ".rollback-tmp",
                ok = copy_file_exact(BackupTarget, RollbackTmp),
                ok = file:rename(RollbackTmp, TargetPath),
                ok = sync_directory(filename:dirname(TargetPath));
            false ->
                _ = file:delete(TargetPath),
                ok = sync_directory(filename:dirname(TargetPath))
        end,

        WalPath = TargetPath ++ "-wal",
        case BackupWal =/= "" andalso filelib:is_regular(BackupWal) of
            true ->
                ok = copy_file_exact(BackupWal, WalPath);
            false ->
                _ = file:delete(WalPath)
        end,

        ShmPath = TargetPath ++ "-shm",
        case BackupShm =/= "" andalso filelib:is_regular(BackupShm) of
            true ->
                ok = copy_file_exact(BackupShm, ShmPath);
            false ->
                _ = file:delete(ShmPath)
        end,

        ok = sync_directory(filename:dirname(TargetPath)),
        {ok, nil}
    end).

-spec rollback_from_manifest(binary(), binary()) -> {ok, nil} | {error, binary()}.
rollback_from_manifest(TargetPathBinary, BackupDirBinary) ->
    guarded(fun() ->
        TargetPath = unicode:characters_to_list(TargetPathBinary),
        BackupDir = unicode:characters_to_list(BackupDirBinary),
        ManifestPath = filename:join(BackupDir, "manifest.json"),
        
        ManifestContent = case file:read_file(ManifestPath) of
            {ok, MBytes} -> MBytes;
            {error, MErr} -> fail(iolist_to_binary(io_lib:format("backup_manifest_unreadable:~s:~p", [ManifestPath, MErr])))
        end,
        
        Manifest = json:decode(ManifestContent),
        MTarget = maps:get(<<"target_path">>, Manifest),
        case unicode:characters_to_binary(TargetPath) =:= MTarget of
            true -> ok;
            false -> fail(<<"manifest_target_path_mismatch">>)
        end,
        
        BackupTarget = maps:get(<<"backup_target_path">>, Manifest, undefined),
        BackupWal = maps:get(<<"backup_wal_path">>, Manifest, undefined),
        BackupShm = maps:get(<<"backup_shm_path">>, Manifest, undefined),
        ExpectedTargetHash = maps:get(<<"target_sha256">>, Manifest, undefined),

        SwapTmp = TargetPath ++ ".swap-tmp",
        _ = file:delete(SwapTmp),

        case retire_target_sidecars(TargetPathBinary) of
            {ok, nil} -> ok;
            {error, RetErr} -> fail(RetErr)
        end,

        case BackupTarget =/= undefined andalso is_binary(BackupTarget) andalso byte_size(BackupTarget) > 0 of
            true ->
                BkTargetList = unicode:characters_to_list(BackupTarget),
                case filelib:is_regular(BkTargetList) of
                    true ->
                        {ok, ActualBkHash} = sha256_file(BackupTarget),
                        case ExpectedTargetHash =:= undefined orelse ExpectedTargetHash =:= null orelse ActualBkHash =:= ExpectedTargetHash of
                            true -> ok;
                            false -> fail(<<"backup_target_hash_corrupted_against_manifest">>)
                        end,
                        RollbackTmp = TargetPath ++ ".rollback-tmp",
                        _ = file:delete(RollbackTmp),
                        case file:read_file(BkTargetList) of
                            {ok, Content} ->
                                case file:open(RollbackTmp, [write, exclusive, binary, raw]) of
                                    {ok, Fd} ->
                                        try
                                            ok = file:write(Fd, Content),
                                            ok = file:change_mode(RollbackTmp, 8#600),
                                            ok = file:sync(Fd)
                                        after
                                            file:close(Fd)
                                        end,
                                        ok = file:rename(RollbackTmp, TargetPath),
                                        ok = sync_directory(filename:dirname(TargetPath));
                                    {error, OpenErr} ->
                                        fail(fmt(OpenErr))
                                end;
                            {error, ReadErr} ->
                                fail(fmt(ReadErr))
                        end;
                    false ->
                        fail(<<"backup_target_file_missing_from_disk">>)
                end;
            false ->
                _ = file:delete(TargetPath),
                ok = sync_directory(filename:dirname(TargetPath))
        end,

        case BackupWal =/= undefined andalso is_binary(BackupWal) andalso byte_size(BackupWal) > 0 of
            true ->
                BkWalList = unicode:characters_to_list(BackupWal),
                case filelib:is_regular(BkWalList) of
                    true ->
                        WalDest = TargetPath ++ "-wal",
                        {ok, WalContent} = file:read_file(BkWalList),
                        ok = file:write_file(WalDest, WalContent),
                        ok = file:change_mode(WalDest, 8#600);
                    false ->
                        fail(<<"backup_wal_missing">>)
                end;
            false ->
                ok
        end,

        case BackupShm =/= undefined andalso is_binary(BackupShm) andalso byte_size(BackupShm) > 0 of
            true ->
                BkShmList = unicode:characters_to_list(BackupShm),
                case filelib:is_regular(BkShmList) of
                    true ->
                        ShmDest = TargetPath ++ "-shm",
                        {ok, ShmContent} = file:read_file(BkShmList),
                        ok = file:write_file(ShmDest, ShmContent),
                        ok = file:change_mode(ShmDest, 8#600);
                    false ->
                        fail(<<"backup_shm_missing">>)
                end;
            false ->
                ok
        end,

        ok = sync_directory(filename:dirname(TargetPath)),

        {ok, nil}
    end).

%% ---------------------------------------------------------------------
%% SQLite Integrity & Cryptographic Chain Verification
%% ---------------------------------------------------------------------

-spec sqlite_verify_integrity(binary()) -> {ok, integer()} | {error, binary()}.
sqlite_verify_integrity(DbPathBinary) ->
    guarded(fun() ->
        DbPath = unicode:characters_to_list(DbPathBinary),
        case esqlite3:open(DbPath) of
            {ok, Conn} ->
                try
                    case esqlite3:q(Conn, "PRAGMA integrity_check;", []) of
                        [[<<"ok">>]] -> ok;
                        [["ok"]] -> ok;
                        [{<<"ok">>}] -> ok;
                        [{"ok"}] -> ok;
                        OtherCheck -> fail(iolist_to_binary(io_lib:format("integrity_check_failed:~p", [OtherCheck])))
                    end,
                    case esqlite3:q(Conn, "PRAGMA quick_check;", []) of
                        [[<<"ok">>]] -> ok;
                        [["ok"]] -> ok;
                        [{<<"ok">>}] -> ok;
                        [{"ok"}] -> ok;
                        OtherQuick -> fail(iolist_to_binary(io_lib:format("quick_check_failed:~p", [OtherQuick])))
                    end,
                    TableRows = esqlite3:q(Conn, "SELECT count(*) FROM sqlite_master WHERE type='table';", []),
                    CountInt = case TableRows of
                        [[N]] when is_integer(N) -> N;
                        [[B]] when is_binary(B) -> binary_to_integer(B);
                        [{N}] when is_integer(N) -> N;
                        [{B}] when is_binary(B) -> binary_to_integer(B)
                    end,
                    {ok, CountInt}
                after
                    esqlite3:close(Conn)
                end;
            {error, Reason} ->
                fail(fmt(Reason))
        end
    end).

-spec sqlite_checkpoint(binary()) -> {ok, nil} | {error, binary()}.
sqlite_checkpoint(DbPathBinary) ->
    guarded(fun() ->
        DbPath = unicode:characters_to_list(DbPathBinary),
        case esqlite3:open(DbPath) of
            {ok, Conn} ->
                try
                    case esqlite3:exec(Conn, "PRAGMA wal_checkpoint(TRUNCATE);") of
                        ok -> {ok, nil};
                        {ok, _} -> {ok, nil};
                        {error, Reason} -> fail(fmt(Reason))
                    end
                after
                    esqlite3:close(Conn)
                end;
            {error, Reason} ->
                fail(fmt(Reason))
        end
    end).

-spec verify_cycle_chain(binary()) -> {ok, {integer(), integer()}} | {error, binary()}.
verify_cycle_chain(DbPathBinary) ->
    guarded(fun() ->
        DbPath = unicode:characters_to_list(DbPathBinary),
        case esqlite3:open(DbPath) of
            {ok, Conn} ->
                try
                    case esqlite3:q(Conn, "PRAGMA integrity_check;", []) of
                        [[<<"ok">>]] -> ok;
                        [["ok"]] -> ok;
                        [{<<"ok">>}] -> ok;
                        [{"ok"}] -> ok;
                        Err -> fail(iolist_to_binary(io_lib:format("cycle_integrity_failed:~p", [Err])))
                    end,
                    TriggerRows = esqlite3:q(Conn, "SELECT name FROM sqlite_master WHERE type='trigger' AND name IN ('cycle_no_update', 'cycle_no_delete', 'cycle_no_replace', 'cycle_chain');", []),
                    case length(TriggerRows) =:= 4 of
                        true -> ok;
                        false -> fail(<<"cycle_triggers_incomplete">>)
                    end,
                    Rows = esqlite3:q(Conn, "SELECT sequence, previous_digest, digest FROM cycle ORDER BY sequence ASC;", []),
                    {RowCount, _} = check_cycle_rows(Rows, 0, <<>>),
                    HoldRows = esqlite3:q(Conn, "SELECT count(*) FROM cycle_hold WHERE released_utc IS NULL;", []),
                    HoldCount = case HoldRows of
                        [[HN]] when is_integer(HN) -> HN;
                        [[HB]] when is_binary(HB) -> binary_to_integer(HB);
                        [{HN}] when is_integer(HN) -> HN;
                        [{HB}] when is_binary(HB) -> binary_to_integer(HB);
                        _ -> 0
                    end,
                    {ok, {RowCount, HoldCount}}
                after
                    esqlite3:close(Conn)
                end;
            {error, Reason} ->
                fail(fmt(Reason))
        end
    end).

check_cycle_rows([], ExpectedSeq, LastDigest) ->
    {ExpectedSeq, LastDigest};
check_cycle_rows([Row | Rest], ExpectedSeq, LastDigest) ->
    {Seq, PrevDigest, Digest} = parse_cycle_row(Row),
    case Seq =:= ExpectedSeq + 1 of
        false ->
            fail(iolist_to_binary(io_lib:format("cycle_seq_broken:expected ~p found ~p", [ExpectedSeq + 1, Seq])));
        true ->
            case ExpectedSeq of
                0 -> ok;
                _ ->
                    case PrevDigest =:= LastDigest of
                        false -> fail(<<"cycle_chain_mismatch">>);
                        true -> ok
                    end
            end,
            check_cycle_rows(Rest, Seq, Digest)
    end.

parse_cycle_row([Seq, Prev, Dig]) -> {as_int(Seq), as_bin(Prev), as_bin(Dig)};
parse_cycle_row({Seq, Prev, Dig}) -> {as_int(Seq), as_bin(Prev), as_bin(Dig)}.

as_int(I) when is_integer(I) -> I;
as_int(B) when is_binary(B) -> binary_to_integer(B).

as_bin(B) when is_binary(B) -> B;
as_bin(L) when is_list(L) -> unicode:characters_to_binary(L).

-spec verify_coordinator_chain(binary()) -> {ok, integer()} | {error, binary()}.
verify_coordinator_chain(DbPathBinary) ->
    guarded(fun() ->
        DbPath = unicode:characters_to_list(DbPathBinary),
        case esqlite3:open(DbPath) of
            {ok, Conn} ->
                try
                    case esqlite3:q(Conn, "PRAGMA integrity_check;", []) of
                        [[<<"ok">>]] -> ok;
                        [["ok"]] -> ok;
                        [{<<"ok">>}] -> ok;
                        [{"ok"}] -> ok;
                        Err -> fail(iolist_to_binary(io_lib:format("coordinator_integrity_failed:~p", [Err])))
                    end,
                    case esqlite3:q(Conn, "SELECT value FROM meta WHERE key='schema';", []) of
                        [[<<"uos-session-sync/v1">>]] -> ok;
                        [["uos-session-sync/v1"]] -> ok;
                        [{<<"uos-session-sync/v1">>}] -> ok;
                        [{"uos-session-sync/v1"}] -> ok;
                        BadSchema -> fail(iolist_to_binary(io_lib:format("coordinator_bad_schema:~p", [BadSchema])))
                    end,
                    TriggerRows = esqlite3:q(Conn, "SELECT name FROM sqlite_master WHERE type='trigger' AND name IN ('events_no_update', 'events_no_delete', 'events_chain', 'events_no_replace');", []),
                    case length(TriggerRows) =:= 4 of
                        true -> ok;
                        false -> fail(<<"coordinator_triggers_incomplete">>)
                    end,
                    Rows = esqlite3:q(Conn, "SELECT sequence, operation_id, previous_digest, digest, body_json FROM events ORDER BY sequence ASC;", []),
                    {CheckedCount, _} = check_coordinator_rows(Rows, 0, <<"uos-session-sync/v1">>, sets:new()),
                    {ok, CheckedCount}
                after
                    esqlite3:close(Conn)
                end;
            {error, Reason} ->
                fail(fmt(Reason))
        end
    end).

check_coordinator_rows([], ExpectedSeq, LastDigest, _SeenOps) ->
    {ExpectedSeq, LastDigest};
check_coordinator_rows([Row | Rest], ExpectedSeq, LastDigest, SeenOps) ->
    {Seq, OpId, PrevDigest, Digest, BodyJson} = parse_coordinator_row(Row),
    case Seq =:= ExpectedSeq + 1 of
        false ->
            fail(iolist_to_binary(io_lib:format("coordinator_seq_broken:expected ~p found ~p", [ExpectedSeq + 1, Seq])));
        true ->
            case PrevDigest =:= LastDigest of
                false ->
                    fail(iolist_to_binary(io_lib:format("coordinator_chain_mismatch:seq ~p expected ~s found ~s", [Seq, LastDigest, PrevDigest])));
                true ->
                    ComputedDigest = binary:encode_hex(crypto:hash(sha256, BodyJson), lowercase),
                    case ComputedDigest =:= Digest of
                        false ->
                            fail(iolist_to_binary(io_lib:format("coordinator_digest_mismatch:seq ~p expected ~s computed ~s", [Seq, Digest, ComputedDigest])));
                        true ->
                            case sets:is_element(OpId, SeenOps) of
                                true ->
                                    fail(iolist_to_binary(io_lib:format("coordinator_duplicate_operation_id:~s", [OpId])));
                                false ->
                                    check_coordinator_rows(Rest, Seq, Digest, sets:add_element(OpId, SeenOps))
                            end
                    end
            end
    end.

parse_coordinator_row([Seq, OpId, Prev, Dig, Body]) ->
    {as_int(Seq), as_bin(OpId), as_bin(Prev), as_bin(Dig), as_bin(Body)};
parse_coordinator_row({Seq, OpId, Prev, Dig, Body}) ->
    {as_int(Seq), as_bin(OpId), as_bin(Prev), as_bin(Dig), as_bin(Body)}.


%% ---------------------------------------------------------------------
%% General File Helpers for Tests & CLI
%% ---------------------------------------------------------------------

-spec file_exists(binary()) -> boolean().
file_exists(PathBinary) ->
    filelib:is_regular(unicode:characters_to_list(PathBinary)).

-spec read_file_binary(binary()) -> {ok, binary()} | {error, binary()}.
read_file_binary(PathBinary) ->
    case file:read_file(unicode:characters_to_list(PathBinary)) of
        {ok, Bin} -> {ok, Bin};
        {error, Reason} -> {error, fmt(Reason)}
    end.

-spec write_file_binary(binary(), binary()) -> {ok, nil} | {error, binary()}.
write_file_binary(PathBinary, ContentBinary) ->
    Path = unicode:characters_to_list(PathBinary),
    ok = filelib:ensure_path(filename:dirname(Path)),
    case file:write_file(Path, ContentBinary) of
        ok ->
            _ = file:change_mode(Path, 8#600),
            {ok, nil};
        {error, Reason} -> {error, fmt(Reason)}
    end.

-spec change_file_mode(binary(), integer()) -> {ok, nil} | {error, binary()}.
change_file_mode(PathBinary, Mode) ->
    case file:change_mode(unicode:characters_to_list(PathBinary), Mode) of
        ok -> {ok, nil};
        {error, Reason} -> {error, fmt(Reason)}
    end.

-spec delete_file(binary()) -> {ok, nil} | {error, binary()}.
delete_file(PathBinary) ->
    case file:delete(unicode:characters_to_list(PathBinary)) of
        ok -> {ok, nil};
        {error, enoent} -> {ok, nil};
        {error, Reason} -> {error, fmt(Reason)}
    end.

-spec list_dir(binary()) -> {ok, [binary()]} | {error, binary()}.
list_dir(PathBinary) ->
    case file:list_dir(unicode:characters_to_list(PathBinary)) of
        {ok, Filenames} ->
            {ok, [unicode:characters_to_binary(F) || F <- Filenames]};
        {error, Reason} ->
            {error, fmt(Reason)}
    end.

-spec get_argv() -> [binary()].
get_argv() ->
    [unicode:characters_to_binary(A) || A <- init:get_plain_arguments()].

-spec create_test_db(binary(), binary()) -> {ok, nil} | {error, binary()}.
create_test_db(PathBinary, TableNameBinary) ->
    guarded(fun() ->
        Path = unicode:characters_to_list(PathBinary),
        Table = unicode:characters_to_list(TableNameBinary),
        ok = filelib:ensure_path(filename:dirname(Path)),
        case esqlite3:open(Path) of
            {ok, Conn} ->
                try
                    ok = esqlite3:exec(Conn, "CREATE TABLE " ++ Table ++ " (id INTEGER PRIMARY KEY, val TEXT);"),
                    ok = esqlite3:exec(Conn, "INSERT INTO " ++ Table ++ " (id, val) VALUES (1, 'uos_test_row');"),
                    {ok, nil}
                after
                    esqlite3:close(Conn)
                end;
            {error, Err} ->
                fail(fmt(Err))
        end
    end).

-spec create_test_coordinator_db(binary()) -> {ok, nil} | {error, binary()}.
create_test_coordinator_db(PathBinary) ->
    guarded(fun() ->
        Path = unicode:characters_to_list(PathBinary),
        ok = filelib:ensure_path(filename:dirname(Path)),
        case esqlite3:open(Path) of
            {ok, Conn} ->
                try
                    ok = esqlite3:exec(Conn, "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);"),
                    ok = esqlite3:exec(Conn, "INSERT INTO meta (key, value) VALUES ('schema', 'uos-session-sync/v1');"),
                    ok = esqlite3:exec(Conn, "CREATE TABLE events (sequence INTEGER PRIMARY KEY, operation_id TEXT UNIQUE, host_id TEXT, boot_id TEXT, tick_us INTEGER, utc_us INTEGER, operation TEXT, actor TEXT, command_json TEXT, body_json TEXT, previous_digest TEXT, digest TEXT UNIQUE, inserted_utc_us INTEGER);"),
                    ok = esqlite3:exec(Conn, "CREATE TRIGGER events_no_update BEFORE UPDATE ON events BEGIN SELECT RAISE(ABORT, 'events are append-only'); END;"),
                    ok = esqlite3:exec(Conn, "CREATE TRIGGER events_no_delete BEFORE DELETE ON events BEGIN SELECT RAISE(ABORT, 'events are append-only'); END;"),
                    ok = esqlite3:exec(Conn, "CREATE TRIGGER events_chain BEFORE INSERT ON events WHEN NOT (NEW.sequence = (SELECT COALESCE(MAX(sequence), 0) + 1 FROM events) AND NEW.previous_digest = COALESCE((SELECT digest FROM events WHERE sequence = NEW.sequence - 1), 'uos-session-sync/v1')) BEGIN SELECT RAISE(ABORT, 'events chain violated'); END;"),
                    ok = esqlite3:exec(Conn, "CREATE TRIGGER events_no_replace BEFORE INSERT ON events WHEN EXISTS (SELECT 1 FROM events WHERE sequence = NEW.sequence OR operation_id = NEW.operation_id OR digest = NEW.digest) BEGIN SELECT RAISE(ABORT, 'events are append-only'); END;"),
                    ok = esqlite3:exec(Conn, "CREATE TABLE quarantine (id INTEGER PRIMARY KEY, raw TEXT, reason TEXT, recorded_utc_us INTEGER);"),
                    
                    Body = <<"{\"command\":{\"a\":\"agy\",\"b\":\"/work\",\"c\":\"test\",\"epoch\":1,\"refs\":[],\"ttl_us\":1000}}">>,
                    Digest = binary:encode_hex(crypto:hash(sha256, Body), lowercase),
                    InsertSql = "INSERT INTO events (sequence, operation_id, host_id, boot_id, tick_us, utc_us, operation, actor, command_json, body_json, previous_digest, digest, inserted_utc_us) VALUES (1, 'op-001', 'h1', 'b1', 100, 100, 'register', 'agy', '{\"a\":\"agy\",\"b\":\"/work\",\"c\":\"test\",\"epoch\":1,\"refs\":[],\"ttl_us\":1000}', '" ++ binary_to_list(Body) ++ "', 'uos-session-sync/v1', '" ++ binary_to_list(Digest) ++ "', 100);",
                    ok = esqlite3:exec(Conn, InsertSql),
                    {ok, nil}
                after
                    esqlite3:close(Conn)
                end;
            {error, Reason} ->
                fail(fmt(Reason))
        end
    end).

-spec create_test_cycle_db(binary()) -> {ok, nil} | {error, binary()}.
create_test_cycle_db(PathBinary) ->
    guarded(fun() ->
        Path = unicode:characters_to_list(PathBinary),
        ok = filelib:ensure_path(filename:dirname(Path)),
        case esqlite3:open(Path) of
            {ok, Conn} ->
                try
                    ok = esqlite3:exec(Conn, "CREATE TABLE cycle (sequence INTEGER PRIMARY KEY, cycle_id TEXT, plan_id TEXT, task_id TEXT, kind TEXT, title TEXT, body TEXT, observed_utc TEXT, evidence_json TEXT, previous_digest TEXT, digest TEXT UNIQUE);"),
                    ok = esqlite3:exec(Conn, "CREATE TRIGGER cycle_no_update BEFORE UPDATE ON cycle BEGIN SELECT RAISE(ABORT, 'no update'); END;"),
                    ok = esqlite3:exec(Conn, "CREATE TRIGGER cycle_no_delete BEFORE DELETE ON cycle BEGIN SELECT RAISE(ABORT, 'no delete'); END;"),
                    ok = esqlite3:exec(Conn, "CREATE TRIGGER cycle_no_replace BEFORE INSERT ON cycle WHEN EXISTS (SELECT 1 FROM cycle WHERE sequence=NEW.sequence) BEGIN SELECT RAISE(ABORT, 'no replace'); END;"),
                    ok = esqlite3:exec(Conn, "CREATE TRIGGER cycle_chain BEFORE INSERT ON cycle WHEN NOT (NEW.sequence = (SELECT COALESCE(MAX(sequence),0)+1 FROM cycle)) BEGIN SELECT RAISE(ABORT, 'broken'); END;"),
                    ok = esqlite3:exec(Conn, "CREATE TABLE cycle_hold (id INTEGER PRIMARY KEY, hold_id TEXT, released_utc TEXT);"),
                    ok = esqlite3:exec(Conn, "INSERT INTO cycle_hold (id, hold_id, released_utc) VALUES (1, 'hold_1', NULL);"),
                    ok = esqlite3:exec(Conn, "INSERT INTO cycle (sequence, cycle_id, plan_id, task_id, kind, title, body, observed_utc, evidence_json, previous_digest, digest) VALUES (1, 'c1', 'p', 't', 'k', 't', 'b', 'o', '{}', '', 'dig_1');"),
                    ok = esqlite3:exec(Conn, "INSERT INTO cycle (sequence, cycle_id, plan_id, task_id, kind, title, body, observed_utc, evidence_json, previous_digest, digest) VALUES (2, 'c2', 'p', 't', 'k', 't', 'b', 'o', '{}', 'dig_1', 'dig_2');"),
                    {ok, nil}
                after
                    esqlite3:close(Conn)
                end;
            {error, Reason} ->
                fail(fmt(Reason))
        end
    end).

%% ---------------------------------------------------------------------
%% Internal Error Handling
%% ---------------------------------------------------------------------

guarded(Fun) ->
    try Fun()
    catch
        throw:{storage, Reason} -> {error, Reason};
        error:{badmatch, {error, Reason}} -> {error, fmt(Reason)};
        Class:Reason -> {error, iolist_to_binary(io_lib:format("~p:~p", [Class, Reason]))}
    end.

fail(Reason) -> throw({storage, Reason}).

fmt(Reason) when is_binary(Reason) -> Reason;
fmt(Reason) -> iolist_to_binary(io_lib:format("~p", [Reason])).
