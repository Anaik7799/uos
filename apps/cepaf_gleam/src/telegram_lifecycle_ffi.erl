%% =============================================================================
%% [C3I-SIL6] telegram_lifecycle_ffi — Poka-Yoke Systemd & Cgroup Lifecycle FFI
%% =============================================================================
-module(telegram_lifecycle_ffi).
-export([
    validate_test_unit_name/1,
    validate_test_slice_name/1,
    read_cgroup_events_populated/1,
    now_us/0,
    storage_config_db_path/1,
    storage_config_worker_sha/1,
    storage_config_guardian_sha/1,
    compute_store_incarnation/1,
    atomic_write_file/2,
    mark_receipt_consumed/3,
    sleep_ms/1,
    read_self_cgroup/0,
    is_current_pid_in_cgroup/1
]).

-define(TEST_UNIT_REGEX, "^uos-tg-store-test-[a-zA-Z0-9_-]+(\\.[a-zA-Z0-9_-]+)?$").
-define(TEST_SLICE_REGEX, "^app-uos_tg_test_[a-zA-Z0-9_-]+(\\.[a-zA-Z0-9_-]+)?$").
-define(CONSUMED_RECEIPTS_TABLE, telegram_lifecycle_consumed_receipts).

%% @doc Strictly validate unit name: must match ^uos-tg-store-test-[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)?$
%% Permanently forbids wildcards, semicolons, shell metacharacters, spaces, or production units.
validate_test_unit_name(UnitName) when is_binary(UnitName) ->
    case byte_size(UnitName) > 80 orelse byte_size(UnitName) < 18 of
        true ->
            {error, <<"refused_unit_name_length_out_of_bounds">>};
        false ->
            case re:run(UnitName, ?TEST_UNIT_REGEX, [{capture, none}]) of
                match -> {ok, UnitName};
                nomatch ->
                    {error, <<"refused_invalid_test_unit_name: must match ^uos-tg-store-test-[a-zA-Z0-9_-]+$">>}
            end
    end;
validate_test_unit_name(_) ->
    {error, <<"invalid_unit_name_type">>}.

%% @doc Strictly validate slice name: must match ^app-uos_tg_test_[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)?$
%% Permanently forbids wildcards, semicolons, shell metacharacters, spaces, or production/Herdr slices.
validate_test_slice_name(SliceName) when is_binary(SliceName) ->
    case byte_size(SliceName) > 80 orelse byte_size(SliceName) < 18 of
        true ->
            {error, <<"refused_slice_name_length_out_of_bounds">>};
        false ->
            case re:run(SliceName, ?TEST_SLICE_REGEX, [{capture, none}]) of
                match -> {ok, SliceName};
                nomatch ->
                    {error, <<"refused_invalid_test_slice_name: must match ^app-uos_tg_test_[a-zA-Z0-9_-]+$">>}
            end
    end;
validate_test_slice_name(_) ->
    {error, <<"invalid_slice_name_type">>}.

sleep_ms(Ms) when is_integer(Ms), Ms >= 0 ->
    timer:sleep(Ms),
    ok;
sleep_ms(_) ->
    ok.

read_cgroup_events_populated(CgroupPath) when is_binary(CgroupPath) ->
    read_actual_cgroup_events_populated(CgroupPath);
read_cgroup_events_populated(_) ->
    {error, <<"invalid_cgroup_path">>}.

read_actual_cgroup_events_populated(CgroupPath) ->
    case binary:match(CgroupPath, <<"/sys/fs/cgroup">>) of
        {0, _} ->
            EventsFile = filename:join([binary_to_list(CgroupPath), "cgroup.events"]),
            case file:read_file(EventsFile) of
                {ok, Content} ->
                    Lines = binary:split(Content, [<<"\n">>], [global]),
                    parse_populated(Lines);
                {error, enoent} ->
                    {error, <<"cgroup_events_not_found">>};
                {error, Reason} ->
                    {error, list_to_binary(atom_to_list(Reason))}
            end;
        _ ->
            {error, <<"refused_non_canonical_cgroup_path: must reside in /sys/fs/cgroup">>}
    end.

parse_populated([]) ->
    {error, <<"populated_field_missing">>};
parse_populated([Line | Rest]) ->
    case string:trim(Line) of
        <<"populated 0">> -> {ok, 0};
        <<"populated 1">> -> {ok, 1};
        _ -> parse_populated(Rest)
    end.

now_us() ->
    os:system_time(microsecond).

storage_config_db_path({local_configuration, _, _, _, _, DbPath}) when is_binary(DbPath) ->
    DbPath;
storage_config_db_path(_) ->
    <<>>.

storage_config_worker_sha({local_configuration, _, _, _, WorkerSha, _}) when is_binary(WorkerSha) ->
    WorkerSha;
storage_config_worker_sha(_) ->
    <<>>.

storage_config_guardian_sha({local_configuration, _, GuardianSha, _, _, _}) when is_binary(GuardianSha) ->
    GuardianSha;
storage_config_guardian_sha(_) ->
    <<>>.

%% @doc Deterministically compute the store incarnation string without modifying frozen store files.
%% Uses stable OS file identity (st_dev + st_ino) plus durable persistent cookie file (<DbPath>.incarnation).
%% Fails closed on nonexistent file or error. Stable across SQLite transactions and WAL checkpoints.
compute_store_incarnation(DbPath) when is_binary(DbPath) ->
    DbPathList = binary_to_list(DbPath),
    case file:read_file_info(DbPathList, [{time, posix}]) of
        {ok, FI} ->
            case element(3, FI) of
                regular ->
                    MajorDev = element(10, FI),
                    MinorDev = element(11, FI),
                    Inode = element(12, FI),
                    case Inode of
                        0 ->
                            {error, <<"invalid_zero_inode">>};
                        _ ->
                            case read_or_create_store_cookie(DbPathList) of
                                {ok, Cookie} ->
                                    Payload = io_lib:format("store_identity:v2:dev=~p:~p:ino=~p:cookie=~s", [MajorDev, MinorDev, Inode, Cookie]),
                                    Hex = string:lowercase(binary:encode_hex(crypto:hash(sha256, list_to_binary(Payload)))),
                                    {ok, Hex};
                                {error, CookieErr} ->
                                    {error, CookieErr}
                            end
                    end;
                directory ->
                    {error, <<"store_path_is_directory">>};
                _ ->
                    {error, <<"store_file_not_regular">>}
            end;
        {error, enoent} ->
            {error, <<"store_file_not_found">>};
        {error, Reason} ->
            {error, list_to_binary(atom_to_list(Reason))}
    end;
compute_store_incarnation(_) ->
    {error, <<"invalid_db_path">>}.

read_or_create_store_cookie(DbPathList) ->
    CookiePath = DbPathList ++ ".incarnation",
    case file:read_file_info(CookiePath, [{time, posix}]) of
        {ok, FI} ->
            case element(3, FI) of
                directory ->
                    {error, <<"cookie_path_is_directory">>};
                regular ->
                    Size = element(2, FI),
                    case Size >= 32 andalso Size =< 128 of
                        true ->
                            case file:read_file(CookiePath) of
                                {ok, Bin} ->
                                    Trimmed = string:trim(Bin),
                                    case is_valid_hex_cookie(Trimmed) of
                                        true ->
                                            {ok, string:lowercase(Trimmed)};
                                        false ->
                                            {error, <<"corrupt_cookie_file">>}
                                    end;
                                {error, ReadErr} ->
                                    {error, list_to_binary(io_lib:format("cookie_read_failed:~p", [ReadErr]))}
                            end;
                        false ->
                            {error, <<"invalid_cookie_file_size">>}
                    end;
                _ ->
                    {error, <<"cookie_file_not_regular">>}
            end;
        {error, enoent} ->
            Cookie = string:lowercase(binary:encode_hex(crypto:strong_rand_bytes(16))),
            case atomic_write_file(list_to_binary(CookiePath), Cookie) of
                {ok, true} ->
                    {ok, Cookie};
                {error, WriteErr} when is_binary(WriteErr) ->
                    {error, WriteErr};
                {error, WriteErr} ->
                    {error, list_to_binary(io_lib:format("cookie_create_failed:~p", [WriteErr]))}
            end;
        {error, StatErr} ->
            {error, list_to_binary(io_lib:format("cookie_stat_failed:~p", [StatErr]))}
    end.

is_valid_hex_cookie(Bin) when is_binary(Bin), byte_size(Bin) =:= 32 ->
    lists:all(fun(C) ->
        (C >= $0 andalso C =< $9) orelse (C >= $a andalso C =< $f) orelse (C >= $A andalso C =< $F)
    end, binary_to_list(Bin));
is_valid_hex_cookie(_) ->
    false.

%% @doc Atomically and durably write file content via temporary file, fsync, atomic rename, and directory fsync.
atomic_write_file(Path, Content) when is_binary(Path), is_binary(Content) ->
    PathList = binary_to_list(Path),
    Dir = filename:dirname(PathList),
    Base = filename:basename(PathList),
    Uniq = integer_to_list(erlang:unique_integer([positive])),
    TmpPath = filename:join([Dir, "." ++ Base ++ ".tmp." ++ Uniq]),
    case file:open(TmpPath, [write, raw, binary, exclusive]) of
        {ok, Fd} ->
            case file:write(Fd, Content) of
                ok ->
                    case file:sync(Fd) of
                        ok ->
                            ok = file:close(Fd),
                            case file:rename(TmpPath, PathList) of
                                ok ->
                                    sync_directory(Dir);
                                {error, RenameErr} ->
                                    _ = file:delete(TmpPath),
                                    {error, list_to_binary(io_lib:format("atomic_rename_failed:~p", [RenameErr]))}
                            end;
                        {error, SyncErr} ->
                            _ = file:close(Fd),
                            _ = file:delete(TmpPath),
                            {error, list_to_binary(io_lib:format("atomic_sync_failed:~p", [SyncErr]))}
                    end;
                {error, WriteErr} ->
                    _ = file:close(Fd),
                    _ = file:delete(TmpPath),
                    {error, list_to_binary(io_lib:format("atomic_write_failed:~p", [WriteErr]))}
            end;
        {error, OpenErr} ->
            {error, list_to_binary(io_lib:format("atomic_open_failed:~p", [OpenErr]))}
    end;
atomic_write_file(_, _) ->
    {error, <<"invalid_atomic_write_arguments">>}.

sync_directory(Dir) ->
    case file:open(Dir, [read, raw, directory]) of
        {ok, DirFd} ->
            case file:sync(DirFd) of
                ok ->
                    _ = file:close(DirFd),
                    {ok, true};
                {error, SyncErr} ->
                    _ = file:close(DirFd),
                    {error, list_to_binary(io_lib:format("dir_sync_failed:~s:~p", [Dir, SyncErr]))}
            end;
        {error, OpenErr} ->
            {error, list_to_binary(io_lib:format("dir_open_failed:~s:~p", [Dir, OpenErr]))}
    end.

is_32_hex(Bin) when is_binary(Bin), byte_size(Bin) =:= 32 ->
    is_32_hex_bytes(binary_to_list(Bin));
is_32_hex(_) -> false.

is_32_hex_bytes([]) -> true;
is_32_hex_bytes([C | Rest]) when (C >= $0 andalso C =< $9) orelse (C >= $a andalso C =< $f) orelse (C >= $A andalso C =< $F) ->
    is_32_hex_bytes(Rest);
is_32_hex_bytes(_) -> false.

%% @doc Tracks single-use consumption of UnitCleanupReceipts to prevent reuse across crashes/restarts.
%% Persists consumption durably on disk at <DbPath>.consumed_receipts/<InvocationId>_<StoppedAtUs>
%% using atomic exclusive file creation, fsync, and directory fsync.
mark_receipt_consumed(DbPath, InvocationId, StoppedAtUs)
  when is_binary(DbPath), is_binary(InvocationId), is_integer(StoppedAtUs) ->
    case byte_size(DbPath) > 0 andalso binary:first(DbPath) =:= $/ andalso is_32_hex(InvocationId) andalso StoppedAtUs > 0 of
        false ->
            {error, <<"invalid_receipt_arguments">>};
        true ->
            DbPathList = binary_to_list(DbPath),
            ParentDir = filename:dirname(DbPathList),
            ConsumedDir = filename:join([ParentDir, filename:basename(DbPathList) ++ ".consumed_receipts"]),
            MkRes = case file:make_dir(ConsumedDir) of
                ok ->
                    sync_directory(ParentDir);
                {error, eexist} ->
                    {ok, true};
                {error, MkErr} ->
                    {error, list_to_binary(io_lib:format("consumed_receipts_mkdir_failed:~p", [MkErr]))}
            end,
            case MkRes of
                {error, ErrReason} ->
                    {error, ErrReason};
                {ok, true} ->
                    MarkerName = io_lib:format("~s_~p", [binary_to_list(InvocationId), StoppedAtUs]),
                    MarkerPath = filename:join([ConsumedDir, MarkerName]),
                    case file:open(MarkerPath, [write, raw, binary, exclusive]) of
                        {ok, Fd} ->
                            Payload = io_lib:format("consumed_at_us=~p pid=~s db_path=~s~n", [os:system_time(microsecond), os:getpid(), DbPathList]),
                            case file:write(Fd, list_to_binary(Payload)) of
                                ok ->
                                    case file:sync(Fd) of
                                        ok ->
                                            case file:close(Fd) of
                                                ok ->
                                                    sync_directory(ConsumedDir);
                                                {error, CloseErr} ->
                                                    {error, list_to_binary(io_lib:format("receipt_consumption_file_close_failed:~p", [CloseErr]))}
                                            end;
                                        {error, SyncErr} ->
                                            _ = file:close(Fd),
                                            {error, list_to_binary(io_lib:format("receipt_consumption_file_sync_failed:~p", [SyncErr]))}
                                    end;
                                {error, WriteErr} ->
                                    _ = file:close(Fd),
                                    {error, list_to_binary(io_lib:format("receipt_consumption_file_write_failed:~p", [WriteErr]))}
                            end;
                        {error, eexist} ->
                            {error, <<"cleanup_receipt_already_consumed">>};
                        {error, OpenErr} ->
                            {error, list_to_binary(io_lib:format("receipt_consumption_file_open_failed:~p", [OpenErr]))}
                    end
            end
    end;
mark_receipt_consumed(_, _, _) ->
    {error, <<"invalid_receipt_arguments">>}.

%% @doc Read current process's cgroup path from /proc/self/cgroup (cgroup v2).
read_self_cgroup() ->
    case file:read_file("/proc/self/cgroup") of
        {ok, Bin} ->
            Lines = binary:split(Bin, [<<"\n">>], [global]),
            parse_self_cgroup(Lines);
        {error, Reason} ->
            {error, list_to_binary(io_lib:format("read_self_cgroup_failed:~p", [Reason]))}
    end.

parse_self_cgroup([]) ->
    {error, <<"self_cgroup_not_found">>};
parse_self_cgroup([Line | Rest]) ->
    Trimmed = string:trim(Line),
    case binary:split(Trimmed, [<<"::">>]) of
        [<<"0">>, Path] when byte_size(Path) > 0 ->
            {ok, Path};
        _ ->
            parse_self_cgroup(Rest)
    end.

%% @doc Check if the current OS process PID is inside the specified cgroup's cgroup.procs.
is_current_pid_in_cgroup(CgroupPath) when is_binary(CgroupPath) ->
    case binary:match(CgroupPath, <<"/">>) of
        {0, _} ->
            CgroupDir = "/sys/fs/cgroup" ++ binary_to_list(CgroupPath),
            ProcsFile = filename:join([CgroupDir, "cgroup.procs"]),
            case file:read_file(ProcsFile) of
                {ok, Content} ->
                    MyPidStr = os:getpid(),
                    Lines = binary:split(Content, [<<"\n">>], [global]),
                    InProcs = lists:any(fun(Line) ->
                        string:trim(binary_to_list(Line)) =:= MyPidStr
                    end, Lines),
                    {ok, InProcs};
                {error, enoent} ->
                    {error, <<"cgroup_procs_not_found">>};
                {error, Reason} ->
                    {error, list_to_binary(io_lib:format("cgroup_procs_read_failed:~p", [Reason]))}
            end;
        _ ->
            {error, <<"refused_non_absolute_cgroup_path">>}
    end;
is_current_pid_in_cgroup(_) ->
    {error, <<"invalid_cgroup_path_argument">>}.

