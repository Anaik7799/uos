-module(core_fpp_candidate_ffi).
-on_load(init_candidate_lock/0).
-export([
    verified_candidate_sha256/0,
    register_live_fpp_actor/2,
    lookup_live_fpp_actor/1,
    ensure_live_fpp_mesh_supervisor/1,
    live_fpp_supervisor_status/0
]).

-define(LIVE_FPP_TABLE, uos_live_fpp_actor_registry).
-define(LIVE_FPP_OWNER, uos_live_fpp_actor_registry_owner).
-define(LIVE_FPP_GUARDIAN, uos_live_fpp_actor_sup_guardian).
-define(ACTOR_COUNT, 40).

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
          when byte_size(CandBytes) > 0, byte_size(CrypBytes) > 0 ->
            lower_sha256(SrcBytes);
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
            SrcManifestSha = lower_sha256(SrcBytes),
            SrcBound = maps:get(<<"source_sha256">>, RelMap, <<>>) =:= SrcManifestSha,
            RelFiles = maps:get(<<"files">>, RelMap, []),
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
            case SchemaOk andalso NotAdmitted andalso SrcBound andalso
                MeshBeamBound andalso SelfBeamBound andalso CrypBeamBound of
                true ->
                    SrcMap = json:decode(SrcBytes),
                    Inputs = maps:get(<<"inputs">>, SrcMap, []),
                    MeshSrcRes = find_sha_by_path(
                        Inputs,
                        <<"apps/cepaf_gleam/src/cepaf_gleam/ecology/core_fpp_actor_twin_mesh.gleam">>
                    ),
                    SelfSrcRes = find_sha_by_path(
                        Inputs,
                        <<"apps/cepaf_gleam/src/cepaf_gleam/ecology/core_fpp_candidate_ffi.erl">>
                    ),
                    CrypSrcRes = find_sha_by_path(
                        Inputs,
                        <<"apps/cepaf_gleam/src/core_bus_crypto_ffi.erl">>
                    ),
                    case {MeshSrcRes, SelfSrcRes, CrypSrcRes} of
                        {{ok, MeshSha}, {ok, SelfSrcSha}, {ok, CrypSrcSha}} ->
                            case is_lower_hex64(MeshSha) andalso
                                is_lower_hex64(SelfSrcSha) andalso
                                is_lower_hex64(CrypSrcSha) of
                                true -> MeshSha;
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

live_fpp_supervisor_status() ->
    SupAlive =
        case whereis(?LIVE_FPP_GUARDIAN) of
            Pid when is_pid(Pid) -> is_process_alive(Pid);
            _ -> false
        end,
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
                                case wait_all_40_alive(25) of
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

start_guardian_supervisor(NowMs) ->
    Parent = self(),
    Ref = make_ref(),
    _Guardian = spawn(fun() ->
        process_flag(trap_exit, true),
        try register(?LIVE_FPP_GUARDIAN, self()) catch _:_ -> ok end,
        MeshMod = 'cepaf_gleam@ecology@core_fpp_actor_twin_mesh',
        case MeshMod:start_supervised_all_40_fpp_actors(NowMs) of
            {ok, _StartedSup} ->
                Parent ! {Ref, ok},
                guardian_loop();
            Err ->
                catch unregister(?LIVE_FPP_GUARDIAN),
                Parent ! {Ref, {error, Err}}
        end
    end),
    receive
        {Ref, ok} ->
            case wait_all_40_alive(25) of
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

guardian_loop() ->
    receive
        {'EXIT', _From, _Reason} ->
            guardian_loop();
        _ ->
            guardian_loop()
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
