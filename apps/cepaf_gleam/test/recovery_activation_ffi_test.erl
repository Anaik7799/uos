%% =============================================================================
%% Recovery Activation FFI Test Suite
%% =============================================================================
-module(recovery_activation_ffi_test).
-include_lib("eunit/include/eunit.hrl").

-define(TEST_TMP, "/tmp/uos_recovery_ffi_test").

setup() ->
    _ = os:cmd("rm -rf " ++ ?TEST_TMP),
    ok = filelib:ensure_path(?TEST_TMP).

teardown(_) ->
    _ = os:cmd("rm -rf " ++ ?TEST_TMP),
    ok.

recovery_ffi_test_() ->
    {setup, fun setup/0, fun teardown/1, [
        fun test_clock_and_pid/0,
        fun test_sha256_file/0,
        fun test_path_safety/0,
        fun test_check_private_file/0,
        fun test_lock_lifecycle/0,
        fun test_hold_target_lock/0,
        fun test_generation_lifecycle/0,
        fun test_preservation_and_staged_swap/0,
        fun test_preserve_target_state_unique_dir/0,
        fun test_rollback/0,
        fun test_rollback_from_manifest/0,
        fun test_sqlite_integrity/0,
        fun test_cycle_chain_verification/0,
        fun test_coordinator_chain_verification/0,
        fun test_cycle_chain_tamper_rejection/0,
        fun test_staged_swap_database_3_temp_hash_mismatch/0,
        fun test_staged_swap_database_existing_swap_tmp_refusal/0
    ]}.

test_clock_and_pid() ->
    Pid = recovery_activation_ffi:get_pid(),
    ?assert(is_integer(Pid)),
    ?assert(Pid > 0),
    {ok, {Host, Boot, Tick, Utc}} = recovery_activation_ffi:clock(),
    ?assert(is_binary(Host)),
    ?assert(is_binary(Boot)),
    ?assert(is_integer(Tick)),
    ?assert(is_integer(Utc)),
    ?assert(Utc > 0),
    IsoUtc = recovery_activation_ffi:utc_now_iso8601(),
    ?assert(is_binary(IsoUtc)),
    ?assert(byte_size(IsoUtc) > 10).

test_sha256_file() ->
    FilePath = filename:join(?TEST_TMP, "hash_test.txt"),
    Content = <<"Hello UOS Recovery Verification">>,
    ok = file:write_file(FilePath, Content),
    Expected = binary:encode_hex(crypto:hash(sha256, Content), lowercase),
    ?assertEqual({ok, Expected}, recovery_activation_ffi:sha256_file(unicode:characters_to_binary(FilePath))),
    ?assertMatch({error, _}, recovery_activation_ffi:sha256_file(<<"/tmp/non_existent_file_xyz_123">>)).

test_path_safety() ->
    GoodPath = unicode:characters_to_binary(filename:join(?TEST_TMP, "good_file.txt")),
    ?assertEqual({ok, nil}, recovery_activation_ffi:path_safety_check(GoodPath)),
    ?assertEqual({error, <<"path_must_be_absolute">>}, recovery_activation_ffi:path_safety_check(<<"relative/path.txt">>)),
    ?assertEqual({error, <<"path_contains_illegal_control_characters">>}, recovery_activation_ffi:path_safety_check(<<GoodPath/binary, 0>>)),
    
    %% Symlink test
    SymlinkTarget = filename:join(?TEST_TMP, "real_file.txt"),
    ok = file:write_file(SymlinkTarget, <<"real content">>),
    SymlinkPath = filename:join(?TEST_TMP, "symlink_file.txt"),
    _ = file:delete(SymlinkPath),
    ok = file:make_symlink(SymlinkTarget, SymlinkPath),
    ?assertEqual({error, <<"symlink_path_rejected">>}, recovery_activation_ffi:path_safety_check(unicode:characters_to_binary(SymlinkPath))).

test_check_private_file() ->
    GoodFile = filename:join(?TEST_TMP, "private_ok.json"),
    ok = file:write_file(GoodFile, <<"{\"safe\":true}">>),
    ok = file:change_mode(GoodFile, 8#600),
    GoodBin = unicode:characters_to_binary(GoodFile),
    ?assertEqual({ok, nil}, recovery_activation_ffi:check_private_file(GoodBin)),

    %% Insecure mode (group/world writable)
    InsecureFile = filename:join(?TEST_TMP, "insecure.json"),
    ok = file:write_file(InsecureFile, <<"{\"insecure\":true}">>),
    ok = file:change_mode(InsecureFile, 8#666),
    InsecureBin = unicode:characters_to_binary(InsecureFile),
    ?assertMatch({error, <<"private_file_insecure_permissions:", _/binary>>}, recovery_activation_ffi:check_private_file(InsecureBin)),

    %% Symlink
    SymlinkFile = filename:join(?TEST_TMP, "symlink_private.json"),
    _ = file:delete(SymlinkFile),
    ok = file:make_symlink(GoodFile, SymlinkFile),
    SymlinkBin = unicode:characters_to_binary(SymlinkFile),
    ?assertEqual({error, <<"symlink_path_rejected">>}, recovery_activation_ffi:check_private_file(SymlinkBin)).

test_lock_lifecycle() ->
    LockPath = unicode:characters_to_binary(filename:join(?TEST_TMP, "test.sqlite3.recovery-lock")),
    Pid = recovery_activation_ffi:get_pid(),
    {ok, {Host, Boot, _, _}} = recovery_activation_ffi:clock(),
    Payload = json:encode(#{
        <<"pid">> => Pid,
        <<"host_id">> => Host,
        <<"boot_id">> => Boot,
        <<"worker">> => <<"test_worker">>
    }),
    
    %% Acquire lock
    ?assertEqual({ok, nil}, recovery_activation_ffi:acquire_target_lock(LockPath, iolist_to_binary(Payload))),
    ?assertEqual({ok, true}, recovery_activation_ffi:is_target_locked(LockPath)),
    
    %% Conflicting acquisition: since PID is alive, must fail with target_locked_by_active_owner
    ?assertEqual({error, <<"target_locked_by_active_owner">>}, recovery_activation_ffi:acquire_target_lock(LockPath, <<"other">>)),
    
    %% Releasing by wrong PID fails
    ?assertMatch({error, <<"lock_owned_by_different_pid:", _/binary>>}, recovery_activation_ffi:release_target_lock(LockPath, Pid + 99999)),
    
    %% Releasing by correct PID succeeds
    ?assertEqual({ok, nil}, recovery_activation_ffi:release_target_lock(LockPath, Pid)),
    ?assertEqual({ok, false}, recovery_activation_ffi:is_target_locked(LockPath)).

test_hold_target_lock() ->
    LockFile = filename:join(?TEST_TMP, "hold_test.sqlite3.recovery-lock"),
    LockBin = unicode:characters_to_binary(LockFile),
    Reason = <<"swap_verification_failed_irrecoverably">>,
    UtcStr = <<"2026-09-30T05:24:00Z">>,

    ?assertEqual({ok, nil}, recovery_activation_ffi:hold_target_lock(LockBin, Reason, UtcStr)),
    ?assertEqual({ok, true}, recovery_activation_ffi:is_target_locked(LockBin)),

    %% Subsequent acquisition must be REFUSED with target_locked_in_hold_state
    ?assertEqual({error, <<"target_locked_in_hold_state">>}, recovery_activation_ffi:acquire_target_lock(LockBin, <<"{}">>)),

    %% Check content of HOLD lock
    {ok, Content} = recovery_activation_ffi:read_target_lock(LockBin),
    Decoded = json:decode(Content),
    ?assertEqual(<<"HOLD">>, maps:get(<<"status">>, Decoded)),
    ?assertEqual(Reason, maps:get(<<"reason">>, Decoded)).

test_generation_lifecycle() ->
    GenPath = unicode:characters_to_binary(filename:join(?TEST_TMP, "test.sqlite3.recovery-generation")),
    %% Absent initially: returns genesis
    ?assertEqual({ok, <<"genesis">>}, recovery_activation_ffi:read_generation(GenPath)),
    
    %% Advance generation
    Token = <<"gen-tok-001">>,
    ?assertEqual({ok, nil}, recovery_activation_ffi:advance_generation(GenPath, Token)),
    ?assertEqual({ok, Token}, recovery_activation_ffi:read_generation(GenPath)),
    
    %% Advance again
    Token2 = <<"gen-tok-002">>,
    ?assertEqual({ok, nil}, recovery_activation_ffi:advance_generation(GenPath, Token2)),
    ?assertEqual({ok, Token2}, recovery_activation_ffi:read_generation(GenPath)).

test_preservation_and_staged_swap() ->
    TargetFile = filename:join(?TEST_TMP, "target.sqlite3"),
    TargetWal = filename:join(?TEST_TMP, "target.sqlite3-wal"),
    TargetShm = filename:join(?TEST_TMP, "target.sqlite3-shm"),
    CandidateFile = filename:join(?TEST_TMP, "candidate.sqlite3"),
    BackupDir = filename:join(?TEST_TMP, "backups"),

    ok = file:write_file(TargetFile, <<"TARGET_V1">>),
    ok = file:write_file(TargetWal, <<"TARGET_WAL_V1">>),
    ok = file:write_file(TargetShm, <<"TARGET_SHM_V1">>),
    ok = file:write_file(CandidateFile, <<"CANDIDATE_V2">>),

    %% 1. Preserve
    {ok, {BkTarget, BkWal, BkShm}} = recovery_activation_ffi:preserve_target_files(
        unicode:characters_to_binary(TargetFile),
        unicode:characters_to_binary(BackupDir)
    ),
    ?assert(filelib:is_regular(binary_to_list(BkTarget))),
    ?assert(filelib:is_regular(binary_to_list(BkWal))),
    ?assert(filelib:is_regular(binary_to_list(BkShm))),
    ?assertEqual({ok, <<"TARGET_V1">>}, file:read_file(binary_to_list(BkTarget))),

    %% 2. Retire sidecars
    ?assertEqual({ok, nil}, recovery_activation_ffi:retire_target_sidecars(unicode:characters_to_binary(TargetFile))),
    ?assertEqual(false, filelib:is_regular(TargetWal)),
    ?assertEqual(false, filelib:is_regular(TargetShm)),

    %% 3. Staged swap
    ?assertEqual({ok, nil}, recovery_activation_ffi:staged_swap_database(
        unicode:characters_to_binary(CandidateFile),
        unicode:characters_to_binary(TargetFile)
    )),

    %% Target now has candidate bytes
    ?assertEqual({ok, <<"CANDIDATE_V2">>}, file:read_file(TargetFile)).

test_preserve_target_state_unique_dir() ->
    TargetFile = filename:join(?TEST_TMP, "target_pres.sqlite3"),
    TargetWal = filename:join(?TEST_TMP, "target_pres.sqlite3-wal"),
    TargetShm = filename:join(?TEST_TMP, "target_pres.sqlite3-shm"),
    BackupBase = filename:join(?TEST_TMP, "backups_state"),
    ok = filelib:ensure_path(BackupBase),

    ok = file:write_file(TargetFile, <<"DB_STATE_V1">>),
    ok = file:write_file(TargetWal, <<"WAL_STATE_V1">>),
    ok = file:write_file(TargetShm, <<"SHM_STATE_V1">>),

    IntentId = <<"int-pres-001">>,
    Attempt = 1,
    GenToken = <<"gen-tok-123">>,
    UtcUs = 1788800000000000,
    UtcStr = <<"2026-09-30T05:24:00Z">>,

    {ok, {UniqueDirBin, TargetOut, WalOut, ShmOut, TargetHash}} = recovery_activation_ffi:preserve_target_state(
        unicode:characters_to_binary(TargetFile),
        unicode:characters_to_binary(BackupBase),
        IntentId,
        Attempt,
        GenToken,
        UtcUs,
        UtcStr
    ),
    UniqueDir = binary_to_list(UniqueDirBin),
    ?assert(filelib:is_dir(UniqueDir)),
    ?assertEqual(TargetHash, binary:encode_hex(crypto:hash(sha256, <<"DB_STATE_V1">>), lowercase)),
    ?assert(filelib:is_regular(binary_to_list(TargetOut))),
    ?assert(filelib:is_regular(binary_to_list(WalOut))),
    ?assert(filelib:is_regular(binary_to_list(ShmOut))),

    ManifestPath = filename:join(UniqueDir, "manifest.json"),
    ?assert(filelib:is_regular(ManifestPath)),
    {ok, MBytes} = file:read_file(ManifestPath),
    Manifest = json:decode(MBytes),
    ?assertEqual(<<"uos.recovery-backup-manifest.v1">>, maps:get(<<"schema">>, Manifest)),
    ?assertEqual(IntentId, maps:get(<<"intent_id">>, Manifest)),
    ?assertEqual(Attempt, maps:get(<<"attempt">>, Manifest)),
    ?assertEqual(TargetHash, maps:get(<<"target_sha256">>, Manifest)),

    %% Re-attempting preservation with SAME intent and attempt MUST refuse to overwrite (no truncate!)
    ?assertMatch({error, <<"unique_backup_dir_already_exists:", _/binary>>}, recovery_activation_ffi:preserve_target_state(
        unicode:characters_to_binary(TargetFile),
        unicode:characters_to_binary(BackupBase),
        IntentId,
        Attempt,
        GenToken,
        UtcUs,
        UtcStr
    )).

test_rollback() ->
    TargetFile = filename:join(?TEST_TMP, "rb_target.sqlite3"),
    TargetWal = filename:join(?TEST_TMP, "rb_target.sqlite3-wal"),
    TargetShm = filename:join(?TEST_TMP, "rb_target.sqlite3-shm"),
    BackupTarget = filename:join(?TEST_TMP, "bk_target.sqlite3"),
    BackupWal = filename:join(?TEST_TMP, "bk_target.sqlite3-wal"),
    BackupShm = filename:join(?TEST_TMP, "bk_target.sqlite3-shm"),

    ok = file:write_file(TargetFile, <<"CORRUPT_OR_FAILED_NEW">>),
    ok = file:write_file(BackupTarget, <<"ORIGINAL_SAFE_DB">>),
    ok = file:write_file(BackupWal, <<"ORIGINAL_SAFE_WAL">>),
    ok = file:write_file(BackupShm, <<"ORIGINAL_SAFE_SHM">>),

    ?assertEqual({ok, nil}, recovery_activation_ffi:rollback_database(
        unicode:characters_to_binary(TargetFile),
        unicode:characters_to_binary(BackupTarget),
        unicode:characters_to_binary(BackupWal),
        unicode:characters_to_binary(BackupShm)
    )),

    ?assertEqual({ok, <<"ORIGINAL_SAFE_DB">>}, file:read_file(TargetFile)),
    ?assertEqual({ok, <<"ORIGINAL_SAFE_WAL">>}, file:read_file(TargetWal)),
    ?assertEqual({ok, <<"ORIGINAL_SAFE_SHM">>}, file:read_file(TargetShm)).

test_rollback_from_manifest() ->
    TargetFile = filename:join(?TEST_TMP, "rb_mf_target.sqlite3"),
    TargetWal = filename:join(?TEST_TMP, "rb_mf_target.sqlite3-wal"),
    TargetShm = filename:join(?TEST_TMP, "rb_mf_target.sqlite3-shm"),
    BackupBase = filename:join(?TEST_TMP, "backups_mf"),
    ok = filelib:ensure_path(BackupBase),

    {ok, nil} = recovery_activation_ffi:create_test_db(unicode:characters_to_binary(TargetFile), "original_db"),
    ok = file:write_file(TargetWal, <<"WAL_ORIG">>),
    ok = file:write_file(TargetShm, <<"SHM_ORIG">>),

    IntentId = <<"int-mf-001">>,
    Attempt = 1,
    GenToken = <<"gen-tok-mf">>,
    UtcUs = 1788800000000000,
    UtcStr = <<"2026-09-30T05:24:00Z">>,

    {ok, {UniqueDirBin, _TargetOut, _WalOut, _ShmOut, TargetHash}} = recovery_activation_ffi:preserve_target_state(
        unicode:characters_to_binary(TargetFile),
        unicode:characters_to_binary(BackupBase),
        IntentId,
        Attempt,
        GenToken,
        UtcUs,
        UtcStr
    ),

    %% Simulate corrupted target and deleted sidecars
    ok = file:write_file(TargetFile, <<"CORRUPTED_BYTES_AFTER_FAILED_SWAP">>),
    _ = file:delete(TargetWal),
    _ = file:delete(TargetShm),

    %% Rollback from manifest
    ?assertEqual({ok, nil}, recovery_activation_ffi:rollback_from_manifest(
        unicode:characters_to_binary(TargetFile),
        UniqueDirBin
    )),

    %% Target restored and matches original hash
    {ok, RestoredHash} = recovery_activation_ffi:sha256_file(unicode:characters_to_binary(TargetFile)),
    ?assertEqual(TargetHash, RestoredHash),
    ?assertEqual({ok, <<"WAL_ORIG">>}, file:read_file(TargetWal)),
    ?assertEqual({ok, <<"SHM_ORIG">>}, file:read_file(TargetShm)),

    %% Negative test: tamper with backup target inside unique backup dir
    UniqueDir = binary_to_list(UniqueDirBin),
    BkTarget = filename:join(UniqueDir, "rb_mf_target.sqlite3"),
    ok = file:change_mode(BkTarget, 8#600),
    ok = file:write_file(BkTarget, <<"TAMPERED_BACKUP_CONTENT">>),
    ?assertEqual({error, <<"backup_target_hash_corrupted_against_manifest">>}, recovery_activation_ffi:rollback_from_manifest(
        unicode:characters_to_binary(TargetFile),
        UniqueDirBin
    )).

test_sqlite_integrity() ->
    DbFile = filename:join(?TEST_TMP, "integrity_test.sqlite3"),
    {ok, Conn} = esqlite3:open(DbFile),
    ok = esqlite3:exec(Conn, "CREATE TABLE test (id INTEGER PRIMARY KEY, msg TEXT);"),
    ok = esqlite3:exec(Conn, "INSERT INTO test (id, msg) VALUES (1, 'uos_integrity_ok');"),
    ok = esqlite3:close(Conn),

    ?assertEqual({ok, 1}, recovery_activation_ffi:sqlite_verify_integrity(unicode:characters_to_binary(DbFile))),
    ?assertEqual({ok, nil}, recovery_activation_ffi:sqlite_checkpoint(unicode:characters_to_binary(DbFile))),

    %% Negative test: corrupt the database file
    {ok, Fd} = file:open(DbFile, [read, write, binary, raw]),
    ok = file:pwrite(Fd, 100, <<"CORRUPT_BYTES_TRASHING_SQLITE_HEADER_PAGES">>),
    ok = file:close(Fd),

    ?assertMatch({error, _}, recovery_activation_ffi:sqlite_verify_integrity(unicode:characters_to_binary(DbFile))).

test_cycle_chain_verification() ->
    DbFile = filename:join(?TEST_TMP, "cycle_test.sqlite3"),
    {ok, Conn} = esqlite3:open(DbFile),
    ok = esqlite3:exec(Conn, "CREATE TABLE cycle (sequence INTEGER PRIMARY KEY, cycle_id TEXT, plan_id TEXT, task_id TEXT, kind TEXT, title TEXT, body TEXT, observed_utc TEXT, evidence_json TEXT, previous_digest TEXT, digest TEXT UNIQUE);"),
    ok = esqlite3:exec(Conn, "CREATE TRIGGER cycle_no_update BEFORE UPDATE ON cycle BEGIN SELECT RAISE(ABORT, 'no update'); END;"),
    ok = esqlite3:exec(Conn, "CREATE TRIGGER cycle_no_delete BEFORE DELETE ON cycle BEGIN SELECT RAISE(ABORT, 'no delete'); END;"),
    ok = esqlite3:exec(Conn, "CREATE TRIGGER cycle_no_replace BEFORE INSERT ON cycle WHEN EXISTS (SELECT 1 FROM cycle WHERE sequence=NEW.sequence) BEGIN SELECT RAISE(ABORT, 'no replace'); END;"),
    ok = esqlite3:exec(Conn, "CREATE TRIGGER cycle_chain BEFORE INSERT ON cycle WHEN NOT (NEW.sequence = (SELECT COALESCE(MAX(sequence),0)+1 FROM cycle)) BEGIN SELECT RAISE(ABORT, 'broken'); END;"),
    ok = esqlite3:exec(Conn, "CREATE TABLE cycle_hold (id INTEGER PRIMARY KEY, hold_id TEXT, released_utc TEXT);"),
    ok = esqlite3:exec(Conn, "INSERT INTO cycle_hold (id, hold_id, released_utc) VALUES (1, 'hold_1', NULL);"),
    
    %% Insert contiguous rows
    ok = esqlite3:exec(Conn, "INSERT INTO cycle (sequence, cycle_id, plan_id, task_id, kind, title, body, observed_utc, evidence_json, previous_digest, digest) VALUES (1, 'c1', 'p', 't', 'k', 't', 'b', 'o', '{}', '', 'dig_1');"),
    ok = esqlite3:exec(Conn, "INSERT INTO cycle (sequence, cycle_id, plan_id, task_id, kind, title, body, observed_utc, evidence_json, previous_digest, digest) VALUES (2, 'c2', 'p', 't', 'k', 't', 'b', 'o', '{}', 'dig_1', 'dig_2');"),
    ok = esqlite3:close(Conn),

    ?assertEqual({ok, {2, 1}}, recovery_activation_ffi:verify_cycle_chain(unicode:characters_to_binary(DbFile))).

test_coordinator_chain_verification() ->
    DbFile = filename:join(?TEST_TMP, "coord_test.sqlite3"),
    ?assertEqual({ok, nil}, recovery_activation_ffi:create_test_coordinator_db(unicode:characters_to_binary(DbFile))),
    ?assertEqual({ok, 1}, recovery_activation_ffi:verify_coordinator_chain(unicode:characters_to_binary(DbFile))),

    %% Negative test 1: tampered digest in events table
    {ok, Conn} = esqlite3:open(DbFile),
    %% Disable trigger to tamper
    ok = esqlite3:exec(Conn, "DROP TRIGGER events_no_update;"),
    ok = esqlite3:exec(Conn, "UPDATE events SET digest = '0000000000000000000000000000000000000000000000000000000000000000' WHERE sequence = 1;"),
    ok = esqlite3:close(Conn),
    ?assertMatch({error, <<"coordinator_triggers_incomplete">>}, recovery_activation_ffi:verify_coordinator_chain(unicode:characters_to_binary(DbFile))),

    %% Negative test 2: bad schema in meta
    DbFile2 = filename:join(?TEST_TMP, "coord_bad_schema.sqlite3"),
    ?assertEqual({ok, nil}, recovery_activation_ffi:create_test_coordinator_db(unicode:characters_to_binary(DbFile2))),
    {ok, Conn2} = esqlite3:open(DbFile2),
    ok = esqlite3:exec(Conn2, "UPDATE meta SET value = 'foreign-schema/v99' WHERE key = 'schema';"),
    ok = esqlite3:close(Conn2),
    ?assertMatch({error, <<"coordinator_bad_schema:", _/binary>>}, recovery_activation_ffi:verify_coordinator_chain(unicode:characters_to_binary(DbFile2))).

test_cycle_chain_tamper_rejection() ->
    DbFile = filename:join(?TEST_TMP, "cycle_tampered.sqlite3"),
    ?assertEqual({ok, nil}, recovery_activation_ffi:create_test_cycle_db(unicode:characters_to_binary(DbFile))),
    ?assertEqual({ok, {2, 1}}, recovery_activation_ffi:verify_cycle_chain(unicode:characters_to_binary(DbFile))),

    %% Tamper sequence chain
    {ok, Conn} = esqlite3:open(DbFile),
    ok = esqlite3:exec(Conn, "DROP TRIGGER cycle_no_update;"),
    ok = esqlite3:exec(Conn, "UPDATE cycle SET previous_digest = 'broken_prev_hash' WHERE sequence = 2;"),
    ok = esqlite3:close(Conn),
    ?assertMatch({error, <<"cycle_triggers_incomplete">>}, recovery_activation_ffi:verify_cycle_chain(unicode:characters_to_binary(DbFile))).

test_staged_swap_database_3_temp_hash_mismatch() ->
    CandFile = filename:join(?TEST_TMP, "cand_swap_mismatch.sqlite3"),
    TargetFile = filename:join(?TEST_TMP, "target_swap_mismatch.sqlite3"),
    ok = file:write_file(CandFile, <<"CANDIDATE_DATA_FOR_HASH_TEST">>),
    ok = file:write_file(TargetFile, <<"TARGET_INITIAL_DATA">>),
    
    WrongHash = <<"0000000000000000000000000000000000000000000000000000000000000000">>,
    Res = recovery_activation_ffi:staged_swap_database(
        unicode:characters_to_binary(CandFile),
        unicode:characters_to_binary(TargetFile),
        WrongHash
    ),
    ?assertMatch({error, <<"swap_tmp_hash_mismatch:", _/binary>>}, Res),
    
    %% Target must remain untouched
    ?assertEqual({ok, <<"TARGET_INITIAL_DATA">>}, file:read_file(TargetFile)),
    %% Temp file must have been deleted
    SwapTmp = TargetFile ++ ".swap-tmp",
    ?assertEqual(false, filelib:is_regular(SwapTmp)).

test_staged_swap_database_existing_swap_tmp_refusal() ->
    CandFile = filename:join(?TEST_TMP, "cand_swap_ex.sqlite3"),
    TargetFile = filename:join(?TEST_TMP, "target_swap_ex.sqlite3"),
    SwapTmp = TargetFile ++ ".swap-tmp",
    
    ok = file:write_file(CandFile, <<"CAND_CONTENT">>),
    ok = file:write_file(TargetFile, <<"TARGET_CONTENT">>),
    %% Pre-create .swap-tmp -> staged swap must refuse to overwrite!
    ok = file:write_file(SwapTmp, <<"EXISTING_SWAP_TMP">>),
    
    {ok, CandHash} = recovery_activation_ffi:sha256_file(unicode:characters_to_binary(CandFile)),
    Res = recovery_activation_ffi:staged_swap_database(
        unicode:characters_to_binary(CandFile),
        unicode:characters_to_binary(TargetFile),
        CandHash
    ),
    ?assertMatch({error, <<"swap_tmp_already_exists_no_truncate:", _/binary>>}, Res),
    %% Existing .swap-tmp must NOT have been truncated or modified!
    ?assertEqual({ok, <<"EXISTING_SWAP_TMP">>}, file:read_file(SwapTmp)),
    _ = file:delete(SwapTmp).
