-module(core_fpp_candidate_ffi).
-on_load(init_candidate_lock/0).
-export([
    verified_candidate_sha256/0,
    register_live_fpp_actor/2,
    lookup_live_fpp_actor/1,
    ensure_live_fpp_mesh_supervisor/1,
    live_fpp_supervisor_status/0,
    live_fpp_supervisor_pid/0,
    kill_live_fpp_supervisor_for_test/0,
    verify_capsule_and_extract_mesh_sha/4,
    is_canonical_capsule_location/3,
    expected_payload_env_matches/1,
    set_expected_payload_env_for_test/1
]).

-define(LIVE_FPP_TABLE, uos_live_fpp_actor_registry).
-define(LIVE_FPP_OWNER, uos_live_fpp_actor_registry_owner).
-define(LIVE_FPP_GUARDIAN, uos_live_fpp_actor_sup_guardian).
-define(ACTOR_COUNT, 40).
-define(PINNED_MESH_GLEAM_SHA256, <<"e6456d869e06b804d88b5d98735e4ebaa902454f26bfe2e21a2413330ad8fab1">>).
-define(PINNED_CRYPTO_ERL_SHA256, <<"08470b66e8d505dbea20a4692c4d0a68b6049e8b1ab2844a456d9c069466688f">>).

init_candidate_lock() ->
    _ = code:stick_mod(?MODULE),
    MeshMod = 'cepaf_gleam@ecology@core_fpp_actor_twin_mesh',
    CryptoMod = core_bus_crypto_ffi,
    case code:is_loaded(MeshMod) of
        {file, _} -> _ = code:stick_mod(MeshMod);
        false ->
            _ = spawn(fun() ->
                _ = code:ensure_loaded(MeshMod),
                _ = code:stick_mod(MeshMod)
            end)
    end,
    case code:is_loaded(CryptoMod) of
        {file, _} -> _ = code:stick_mod(CryptoMod);
        false ->
            _ = spawn(fun() ->
                _ = code:ensure_loaded(CryptoMod),
                _ = code:stick_mod(CryptoMod)
            end)
    end,
    ok.

verified_candidate_sha256() ->
    try
        Mod = 'cepaf_gleam@ecology@core_fpp_actor_twin_mesh',
        SelfMod = ?MODULE,
        CryptoMod = core_bus_crypto_ffi,
        _ = code:ensure_loaded(Mod),
        _ = code:ensure_loaded(CryptoMod),
        _ = code:stick_mod(SelfMod),
        _ = code:stick_mod(Mod),
        _ = code:stick_mod(CryptoMod),
        case {in_memory_matches_disk(Mod), in_memory_matches_disk(SelfMod), in_memory_matches_disk(CryptoMod)} of
            {{ok, BeamBin, BeamSha}, {ok, SelfBin, SelfSha}, {ok, CrypBin, CrypSha}} ->
                MeshDir = filename:dirname(BeamBin),
                SameEbin =
                    MeshDir =:= filename:dirname(SelfBin) andalso
                        MeshDir =:= filename:dirname(CrypBin),
                case SameEbin of
                    true ->
                        resolve_from_loaded_beam(BeamBin, BeamSha, SelfSha, CrypSha);
                    false ->
                        <<>>
                end;
            _ ->
                <<>>
        end
    catch
        _:_ -> <<>>
    end.

in_memory_matches_disk(Mod) ->
    case code:which(Mod) of
        BeamPathList when is_list(BeamPathList), BeamPathList =/= "" ->
            AbsList = filename:absname(BeamPathList),
            case file:read_file(AbsList) of
                {ok, BeamBytes} ->
                    case beam_lib:md5(BeamBytes) of
                        {ok, {Mod, DiskMd5}} ->
                            LoadedMd5 = Mod:module_info(md5),
                            case LoadedMd5 =:= DiskMd5 of
                                true ->
                                    {ok, unicode:characters_to_binary(AbsList), lower_sha256(BeamBytes)};
                                false ->
                                    error
                            end;
                        _ ->
                            error
                    end;
                _ ->
                    error
            end;
        _ ->
            error
    end.

resolve_from_loaded_beam(BeamBin, BeamSha, SelfSha, CrypSha) ->
    CapSuffix = <<"/apps/cepaf_gleam/ebin/cepaf_gleam@ecology@core_fpp_actor_twin_mesh.beam">>,
    case os:getenv("UOS_COCKPIT_RELEASE") of
        false ->
            case strip_suffix(BeamBin, <<"/build/dev/erlang/cepaf_gleam/ebin/cepaf_gleam@ecology@core_fpp_actor_twin_mesh.beam">>) of
                {ok, AppDir} -> hash_workspace_mesh_source(AppDir);
                error ->
                    case strip_suffix(BeamBin, <<"/build/prod/erlang/cepaf_gleam/ebin/cepaf_gleam@ecology@core_fpp_actor_twin_mesh.beam">>) of
                        {ok, AppDir2} -> hash_workspace_mesh_source(AppDir2);
                        error ->
                            case strip_suffix(BeamBin, CapSuffix) of
                                {ok, CapDir2} ->
                                    verify_capsule_and_extract_mesh_sha(CapDir2, BeamSha, SelfSha, CrypSha);
                                error ->
                                    <<>>
                            end
                    end
            end;
        EnvVal when is_list(EnvVal) ->
            Trimmed = string:trim(unicode:characters_to_binary(EnvVal)),
            case Trimmed of
                <<>> ->
                    <<>>;
                _ ->
                    CapDir = trim_trailing_slash(Trimmed),
                    ExpectedBeam = <<CapDir/binary, CapSuffix/binary>>,
                    case CapDir =/= <<>> andalso BeamBin =:= ExpectedBeam of
                        true ->
                            verify_capsule_and_extract_mesh_sha(CapDir, BeamSha, SelfSha, CrypSha);
                        false ->
                            <<>>
                    end
            end
    end.

hash_workspace_mesh_source(AppDir) ->
    AppsParent = filename:dirname(AppDir),
    MeshSrc = <<AppsParent/binary, "/cepaf_gleam/src/cepaf_gleam/ecology/core_fpp_actor_twin_mesh.gleam">>,
    CandSrc = <<AppsParent/binary, "/cepaf_gleam/src/cepaf_gleam/ecology/core_fpp_candidate_ffi.erl">>,
    CrypSrc = <<AppsParent/binary, "/cepaf_gleam/src/core_bus_crypto_ffi.erl">>,
    case {file:read_file(MeshSrc), file:read_file(CandSrc), file:read_file(CrypSrc)} of
        {{ok, SrcBytes}, {ok, CandBytes}, {ok, CrypBytes}}
          when byte_size(SrcBytes) > 0, byte_size(CandBytes) > 0, byte_size(CrypBytes) > 0 ->
            lower_sha256(<<SrcBytes/binary, 0, CandBytes/binary, 0, CrypBytes/binary>>);
        _ ->
            <<>>
    end.

verify_capsule_and_extract_mesh_sha(CapDir, LoadedBeamSha, LoadedSelfSha, LoadedCrypSha) ->
    MarkerPath = <<CapDir/binary, "/.uos-ecology-release">>,
    RelPath = <<CapDir/binary, "/release-manifest.json">>,
    SrcPath = <<CapDir/binary, "/source-manifest.json">>,
    case {file:read_file(MarkerPath), file:read_file(RelPath), file:read_file(SrcPath)} of
        {{ok, <<"uos.ecology-release.v1\n">>}, {ok, RelBytes}, {ok, SrcBytes}} ->
            RelMap = json:decode(RelBytes),
            SchemaOk = maps:get(<<"schema">>, RelMap, <<>>) =:= <<"uos.ecology-release-manifest.v1">>,
            NotAdmitted = maps:get(<<"application_admitted">>, RelMap, true) =:= false,
            CandSha = maps:get(<<"candidate_sha256">>, RelMap, <<>>),
            PayloadSha = maps:get(<<"payload_sha256">>, RelMap, <<>>),
            RelFiles = maps:get(<<"files">>, RelMap, []),
            RecomputedCandSha = lower_sha256(canonical_json_bytes(maps:remove(<<"candidate_sha256">>, RelMap))),
            RecomputedPayloadSha = lower_sha256(canonical_json_bytes(RelFiles)),
            CandCryptographicallyBound =
                is_lower_hex64(CandSha) andalso
                CandSha =:= RecomputedCandSha andalso
                capsule_dir_matches_candidate(CapDir, CandSha) andalso
                is_readonly_entry(CapDir) andalso
                is_readonly_entry(RelPath) andalso
                is_readonly_entry(SrcPath),
            PayloadCryptographicallyBound =
                is_lower_hex64(PayloadSha) andalso
                PayloadSha =:= RecomputedPayloadSha andalso
                expected_payload_env_matches(PayloadSha),
            SrcManifestSha = lower_sha256(SrcBytes),
            SrcBound =
                maps:get(<<"source_sha256">>, RelMap, <<>>) =:= SrcManifestSha andalso
                find_sha_and_bytes_by_path(RelFiles, <<"source-manifest.json">>) =:=
                    {ok, SrcManifestSha, byte_size(SrcBytes)},
            MeshBeamBound = find_sha_by_path(
                RelFiles,
                <<"apps/cepaf_gleam/ebin/cepaf_gleam@ecology@core_fpp_actor_twin_mesh.beam">>
            ) =:= {ok, LoadedBeamSha},
            SelfBeamBound = find_sha_by_path(
                RelFiles,
                <<"apps/cepaf_gleam/ebin/core_fpp_candidate_ffi.beam">>
            ) =:= {ok, LoadedSelfSha},
            CrypBeamBound = find_sha_by_path(
                RelFiles,
                <<"apps/cepaf_gleam/ebin/core_bus_crypto_ffi.beam">>
            ) =:= {ok, LoadedCrypSha},
            case SchemaOk andalso NotAdmitted andalso CandCryptographicallyBound andalso
                PayloadCryptographicallyBound andalso SrcBound andalso
                MeshBeamBound andalso SelfBeamBound andalso CrypBeamBound of
                true ->
                    SrcMap = json:decode(SrcBytes),
                    SrcSchemaOk = maps:get(<<"schema">>, SrcMap, <<>>) =:= <<"uos.ecology-source-manifest.v1">>,
                    SrcRoot = maps:get(<<"source_root">>, SrcMap, <<>>),
                    CanonicalRootOk = is_canonical_capsule_location(CapDir, SrcRoot, CandSha),
                    Inputs = maps:get(<<"inputs">>, SrcMap, []),
                    MeshSrcOk = find_sha_by_path(
                        Inputs,
                        <<"apps/cepaf_gleam/src/cepaf_gleam/ecology/core_fpp_actor_twin_mesh.gleam">>
                    ) =:= {ok, ?PINNED_MESH_GLEAM_SHA256},
                    CrypSrcOk = find_sha_by_path(
                        Inputs,
                        <<"apps/cepaf_gleam/src/core_bus_crypto_ffi.erl">>
                    ) =:= {ok, ?PINNED_CRYPTO_ERL_SHA256},
                    SelfSrcRes = find_sha_and_bytes_by_path(
                        Inputs,
                        <<"apps/cepaf_gleam/src/cepaf_gleam/ecology/core_fpp_candidate_ffi.erl">>
                    ),
                    SrcMeshBeamOk = find_sha_by_path(
                        Inputs,
                        <<"apps/indrajaal_gleam_web/build/dev/erlang/cepaf_gleam/ebin/cepaf_gleam@ecology@core_fpp_actor_twin_mesh.beam">>
                    ) =:= {ok, LoadedBeamSha},
                    SrcSelfBeamOk = find_sha_by_path(
                        Inputs,
                        <<"apps/indrajaal_gleam_web/build/dev/erlang/cepaf_gleam/ebin/core_fpp_candidate_ffi.beam">>
                    ) =:= {ok, LoadedSelfSha},
                    SrcCrypBeamOk = find_sha_by_path(
                        Inputs,
                        <<"apps/indrajaal_gleam_web/build/dev/erlang/cepaf_gleam/ebin/core_bus_crypto_ffi.beam">>
                    ) =:= {ok, LoadedCrypSha},
                    case {SrcSchemaOk andalso CanonicalRootOk andalso MeshSrcOk andalso CrypSrcOk andalso
                          SrcMeshBeamOk andalso SrcSelfBeamOk andalso SrcCrypBeamOk, SelfSrcRes} of
                        {true, {ok, SelfSrcSha, SelfBytes}} when SelfBytes > 0 ->
                            case is_lower_hex64(SelfSrcSha) of
                                true -> CandSha;
                                false -> <<>>
                            end;
                        _ ->
                            <<>>
                    end;
                false ->
                    <<>>
            end;
        _ ->
            <<>>
    end.

%% ============================================================================
%% Persistent Supervised Live 40-Actor OTP Registry & Immortal Guardian
%% ============================================================================

ensure_live_fpp_table() ->
    case ets:whereis(?LIVE_FPP_TABLE) of
        undefined ->
            global:trans({?LIVE_FPP_TABLE, self()}, fun() ->
                case ets:whereis(?LIVE_FPP_TABLE) of
                    undefined ->
                        Parent = self(),
                        Ref = make_ref(),
                        Owner = spawn(fun() ->
                            process_flag(trap_exit, true),
                            HeirOpts =
                                case whereis(init) of
                                    undefined -> [];
                                    InitPid -> [{heir, InitPid, none}]
                                end,
                            _ = ets:new(?LIVE_FPP_TABLE, [
                                named_table,
                                public,
                                set,
                                {read_concurrency, true},
                                {write_concurrency, true}
                                | HeirOpts
                            ]),
                            try register(?LIVE_FPP_OWNER, self()) catch _:_ -> ok end,
                            Parent ! {Ref, ready},
                            live_owner_loop()
                        end),
                        true = is_pid(Owner),
                        receive
                            {Ref, ready} -> ?LIVE_FPP_TABLE
                        after 5000 ->
                            erlang:error(live_fpp_table_init_timeout)
                        end;
                    _Tid ->
                        ?LIVE_FPP_TABLE
                end
            end);
        _Tid ->
            ?LIVE_FPP_TABLE
    end.

live_owner_loop() ->
    receive
        _ -> live_owner_loop()
    end.

subject_pid(Subject) when is_tuple(Subject), tuple_size(Subject) >= 2 ->
    case element(2, Subject) of
        Pid when is_pid(Pid) -> Pid;
        _ -> undefined
    end;
subject_pid(_) ->
    undefined.

register_live_fpp_actor(ActorIdx, Subject) when is_integer(ActorIdx) ->
    Table = ensure_live_fpp_table(),
    Pid = subject_pid(Subject),
    true = ets:insert(Table, {ActorIdx, Subject, Pid}),
    nil.

lookup_live_fpp_actor(ActorIdx) when is_integer(ActorIdx) ->
    Table = ensure_live_fpp_table(),
    case ets:lookup(Table, ActorIdx) of
        [{ActorIdx, Subject, Pid}] when is_pid(Pid) ->
            case is_process_alive(Pid) of
                true -> {ok, Subject};
                false -> {error, nil}
            end;
        _ ->
            {error, nil}
    end.

live_fpp_supervisor_pid() ->
    Table = ensure_live_fpp_table(),
    case ets:lookup(Table, supervisor_pid) of
        [{supervisor_pid, SupPid}] when is_pid(SupPid) ->
            case is_process_alive(SupPid) of
                true -> {ok, SupPid};
                false -> {error, nil}
            end;
        _ ->
            {error, nil}
    end.

kill_live_fpp_supervisor_for_test() ->
    case live_fpp_supervisor_pid() of
        {ok, SupPid} ->
            exit(SupPid, kill),
            true;
        _ ->
            false
    end.

live_fpp_supervisor_status() ->
    GuardianAlive =
        case whereis(?LIVE_FPP_GUARDIAN) of
            Pid when is_pid(Pid) -> is_process_alive(Pid);
            _ -> false
        end,
    SupPidAlive =
        case live_fpp_supervisor_pid() of
            {ok, _} -> true;
            _ -> false
        end,
    SupAlive = GuardianAlive andalso SupPidAlive,
    AliveCount = length([
        ok
     || Idx <- lists:seq(0, ?ACTOR_COUNT - 1),
        case lookup_live_fpp_actor(Idx) of
            {ok, _} -> true;
            _ -> false
        end
    ]),
    {SupAlive, AliveCount}.

wait_all_40_alive(0) ->
    live_fpp_supervisor_status();
wait_all_40_alive(Retries) ->
    case live_fpp_supervisor_status() of
        {true, ?ACTOR_COUNT} = Ready ->
            Ready;
        _ ->
            timer:sleep(15),
            wait_all_40_alive(Retries - 1)
    end.

ensure_live_fpp_mesh_supervisor(NowMs) when is_integer(NowMs) ->
    _ = ensure_live_fpp_table(),
    case live_fpp_supervisor_status() of
        {true, ?ACTOR_COUNT} ->
            {ok, ?ACTOR_COUNT};
        _ ->
            global:trans({?LIVE_FPP_GUARDIAN, self()}, fun() ->
                case whereis(?LIVE_FPP_GUARDIAN) of
                    Pid when is_pid(Pid) ->
                        case is_process_alive(Pid) of
                            true ->
                                case wait_all_40_alive(240) of
                                    {true, ?ACTOR_COUNT} ->
                                        {ok, ?ACTOR_COUNT};
                                    {_, Count} ->
                                        {error, iolist_to_binary(
                                            io_lib:format("live_fpp_actors_incomplete:~p", [Count])
                                        )}
                                end;
                            false ->
                                start_guardian_supervisor(NowMs)
                        end;
                    undefined ->
                        start_guardian_supervisor(NowMs)
                end
            end)
    end.

extract_started_pid(StartedSup) when is_tuple(StartedSup), tuple_size(StartedSup) >= 2 ->
    case element(2, StartedSup) of
        Pid when is_pid(Pid) -> {ok, Pid};
        _ -> error
    end;
extract_started_pid(_) ->
    error.

start_and_record_supervisor(NowMs) ->
    Table = ensure_live_fpp_table(),
    MeshMod = 'cepaf_gleam@ecology@core_fpp_actor_twin_mesh',
    case MeshMod:start_supervised_all_40_fpp_actors(NowMs) of
        {ok, StartedSup} ->
            case extract_started_pid(StartedSup) of
                {ok, SupPid} ->
                    true = ets:insert(Table, {supervisor_pid, SupPid}),
                    {ok, SupPid};
                error ->
                    {error, invalid_started_supervisor_tuple}
            end;
        Err ->
            {error, Err}
    end.

start_guardian_supervisor(NowMs) ->
    Parent = self(),
    Ref = make_ref(),
    _Guardian = spawn(fun() ->
        process_flag(trap_exit, true),
        try register(?LIVE_FPP_GUARDIAN, self()) catch _:_ -> ok end,
        case start_and_record_supervisor(NowMs) of
            {ok, SupPid} ->
                Parent ! {Ref, ok},
                guardian_loop(SupPid);
            {error, Err} ->
                try unregister(?LIVE_FPP_GUARDIAN) catch _:_ -> ok end,
                Parent ! {Ref, {error, Err}}
        end
    end),
    receive
        {Ref, ok} ->
            case wait_all_40_alive(240) of
                {true, ?ACTOR_COUNT} ->
                    {ok, ?ACTOR_COUNT};
                {_, Count} ->
                    {error, iolist_to_binary(
                        io_lib:format("live_fpp_actors_post_boot_incomplete:~p", [Count])
                    )}
            end;
        {Ref, {error, _Reason}} ->
            {error, <<"failed_to_start_40_fpp_static_supervisor">>}
    after 15000 ->
        {error, <<"live_fpp_static_supervisor_start_timeout">>}
    end.

guardian_loop(SupPid) ->
    receive
        {'EXIT', SupPid, _Reason} ->
            case start_and_record_supervisor(erlang:system_time(millisecond)) of
                {ok, NewSupPid} ->
                    guardian_loop(NewSupPid);
                {error, _} ->
                    timer:sleep(50),
                    self() ! {'EXIT', SupPid, retry_supervisor_boot},
                    guardian_loop(SupPid)
            end;
        {'EXIT', _OtherPid, _Reason} ->
            guardian_loop(SupPid);
        _ ->
            guardian_loop(SupPid)
    end.

%% ============================================================================
%% Helpers
%% ============================================================================

find_sha_by_path([], _TargetPath) ->
    error;
find_sha_by_path([Entry | Rest], TargetPath) when is_map(Entry) ->
    case maps:get(<<"path">>, Entry, <<>>) =:= TargetPath of
        true ->
            case maps:find(<<"sha256">>, Entry) of
                {ok, Sha} when is_binary(Sha) -> {ok, Sha};
                _ -> error
            end;
        false ->
            find_sha_by_path(Rest, TargetPath)
    end;
find_sha_by_path([_ | Rest], TargetPath) ->
    find_sha_by_path(Rest, TargetPath).

find_sha_and_bytes_by_path([], _TargetPath) ->
    error;
find_sha_and_bytes_by_path([Entry | Rest], TargetPath) when is_map(Entry) ->
    case maps:get(<<"path">>, Entry, <<>>) =:= TargetPath of
        true ->
            case {maps:find(<<"sha256">>, Entry), maps:find(<<"bytes">>, Entry)} of
                {{ok, Sha}, {ok, Bytes}} when is_binary(Sha), is_integer(Bytes), Bytes >= 0 ->
                    {ok, Sha, Bytes};
                _ ->
                    error
            end;
        false ->
            find_sha_and_bytes_by_path(Rest, TargetPath)
    end;
find_sha_and_bytes_by_path([_ | Rest], TargetPath) ->
    find_sha_and_bytes_by_path(Rest, TargetPath).

canonical_json_bytes(Term) ->
    iolist_to_binary(canonical_json_iolist(Term)).

canonical_json_iolist(M) when is_map(M) ->
    KVs = lists:sort(maps:to_list(M)),
    [
        <<"{">>,
        lists:join(<<",">>, [
            [json:encode_binary(K), <<":">>, canonical_json_iolist(V)]
         || {K, V} <- KVs
        ]),
        <<"}">>
    ];
canonical_json_iolist(L) when is_list(L) ->
    [<<"[">>, lists:join(<<",">>, [canonical_json_iolist(E) || E <- L]), <<"]">>];
canonical_json_iolist(B) when is_binary(B) ->
    json:encode_binary(B);
canonical_json_iolist(I) when is_integer(I) ->
    integer_to_binary(I);
canonical_json_iolist(F) when is_float(F) ->
    json:encode_float(F);
canonical_json_iolist(true) ->
    <<"true">>;
canonical_json_iolist(false) ->
    <<"false">>;
canonical_json_iolist(null) ->
    <<"null">>.

capsule_dir_matches_candidate(CapDir, CandSha) ->
    Base = filename:basename(CapDir),
    Suffix = <<"-", CandSha/binary>>,
    case strip_suffix(Base, Suffix) of
        {ok, Stamp} -> byte_size(Stamp) =:= 13;
        error -> false
    end.

is_canonical_capsule_location(CapDir, SrcRoot, CandSha) ->
    AllowedRoot =
        SrcRoot =:= <<"/home/an/NAS-setup/uos">> orelse
        is_single_sibling_workspace_root(SrcRoot),
    ExpectedParent = <<SrcRoot/binary, "/var/releases/ecology">>,
    AllowedRoot andalso
        filename:dirname(CapDir) =:= ExpectedParent andalso
        capsule_dir_matches_candidate(CapDir, CandSha) andalso
        no_dot_or_symlink_components(CapDir) andalso
        no_dot_or_symlink_components(SrcRoot) andalso
        filelib:is_dir(binary_to_list(<<SrcRoot/binary, "/.jj">>)).

is_single_sibling_workspace_root(SrcRoot) when is_binary(SrcRoot) ->
    Prefix = <<"/home/an/NAS-setup/uos/.uos-workspaces/">>,
    case binary:match(SrcRoot, Prefix) =:= {0, 39} of
        false ->
            false;
        true ->
            Rest = binary:part(SrcRoot, 39, byte_size(SrcRoot) - 39),
            byte_size(Rest) > 0 andalso
                binary:match(Rest, <<"/">>) =:= nomatch andalso
                Rest =/= <<".">> andalso
                Rest =/= <<"..">>
    end;
is_single_sibling_workspace_root(_) ->
    false.

no_dot_or_symlink_components(AbsPathBin) ->
    Parts = [P || P <- binary:split(AbsPathBin, <<"/">>, [global]), P =/= <<>>],
    lists:all(
        fun(P) ->
            P =/= <<".">> andalso P =/= <<"..">> andalso is_valid_segment_chars(P)
        end,
        Parts
    ) andalso check_no_symlinks(<<>>, Parts).

is_valid_segment_chars(P) when is_binary(P), byte_size(P) > 0 ->
    lists:all(
        fun(C) ->
            (C >= $a andalso C =< $z) orelse
                (C >= $A andalso C =< $Z) orelse
                (C >= $0 andalso C =< $9) orelse
                C =:= $. orelse
                C =:= $- orelse
                C =:= $_
        end,
        binary_to_list(P)
    );
is_valid_segment_chars(_) ->
    false.

check_no_symlinks(_Prefix, []) ->
    true;
check_no_symlinks(Prefix, [Part | Rest]) ->
    Cur = <<Prefix/binary, "/", Part/binary>>,
    case file:read_link_info(binary_to_list(Cur)) of
        {ok, Info} ->
            case element(3, Info) of
                symlink -> false;
                _ -> check_no_symlinks(Cur, Rest)
            end;
        _ ->
            false
    end.

is_readonly_entry(PathBin) ->
    case file:read_link_info(binary_to_list(PathBin)) of
        {ok, Info} ->
            Type = element(3, Info),
            Mode = element(8, Info),
            (Type =:= regular orelse Type =:= directory) andalso
                is_integer(Mode) andalso
                (Mode band 8#222) =:= 0;
        _ ->
            false
    end.

expected_payload_env_matches(PayloadSha) ->
    case os:getenv("UOS_MCP_EXPECTED_PAYLOAD_SHA256") of
        false ->
            false;
        "" ->
            false;
        Raw ->
            string:trim(unicode:characters_to_binary(Raw)) =:= PayloadSha
    end.

strip_suffix(Bin, Suffix) ->
    BinLen = byte_size(Bin),
    SufLen = byte_size(Suffix),
    case BinLen > SufLen andalso binary:part(Bin, BinLen - SufLen, SufLen) =:= Suffix of
        true -> {ok, binary:part(Bin, 0, BinLen - SufLen)};
        false -> error
    end.

trim_trailing_slash(Bin) ->
    Len = byte_size(Bin),
    case Len > 1 andalso binary:at(Bin, Len - 1) =:= $/ of
        true -> binary:part(Bin, 0, Len - 1);
        false -> Bin
    end.

lower_sha256(Bytes) ->
    string:lowercase(binary:encode_hex(crypto:hash(sha256, Bytes))).

is_lower_hex64(Bin) when is_binary(Bin), byte_size(Bin) =:= 64 ->
    lists:all(
        fun(C) -> (C >= $0 andalso C =< $9) orelse (C >= $a andalso C =< $f) end,
        binary_to_list(Bin)
    );
is_lower_hex64(_) ->
    false.

set_expected_payload_env_for_test(<<>>) -> os:unsetenv("UOS_MCP_EXPECTED_PAYLOAD_SHA256"), nil;
set_expected_payload_env_for_test(ValBin) when is_binary(ValBin) -> os:putenv("UOS_MCP_EXPECTED_PAYLOAD_SHA256", binary_to_list(ValBin)), nil.
