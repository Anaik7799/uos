%% =============================================================================
%% [C3I-SIL6] telegram_service_worker_runner — Transient Unit BEAM Worker Runner
%% =============================================================================
-module(telegram_service_worker_runner).
-export([start/1, main/1]).

start([ConfigPath]) ->
    main([ConfigPath]);
start(ConfigPath) when is_list(ConfigPath) ->
    main([ConfigPath]).

main([ConfigPath]) ->
    ConfigBin = case file:read_file(ConfigPath) of
        {ok, B} -> B;
        {error, E} ->
            io:format("Failed to read config ~p: ~p~n", [ConfigPath, E]),
            erlang:halt(1)
    end,
    Config = json:decode(ConfigBin),
    IpcDir = binary_to_list(maps:get(<<"ipc_dir">>, Config)),
    ok = filelib:ensure_dir(filename:join([IpcDir, "dummy"])),

    _ = application:ensure_all_started(crypto),
    _ = application:ensure_all_started(ssl),
    _ = application:ensure_all_started(inets),
    _ = application:ensure_all_started(hackney),

    write_json_file(filename:join([IpcDir, "worker.ready"]), #{
        <<"status">> => <<"ready">>,
        <<"pid">> => list_to_binary(os:getpid())
    }),

    Mode = maps:get(<<"mode">>, Config, <<"standby">>),
    case Mode of
        <<"run_actor">> ->
            start_and_run_actor(Config, IpcDir);
        _ ->
            standby_loop(IpcDir, Config)
    end.

standby_loop(IpcDir, Config) ->
    CmdPath = filename:join([IpcDir, "cmd.json"]),
    case file:read_file(CmdPath) of
        {ok, CmdBin} ->
            _ = file:delete(CmdPath),
            Cmd = json:decode(CmdBin),
            handle_standby_command(Cmd, IpcDir, Config);
        {error, _} ->
            timer:sleep(20),
            standby_loop(IpcDir, Config)
    end.

handle_standby_command(#{<<"action">> := <<"probe_ownership">>} = Cmd, IpcDir, Config) ->
    CtrlPath = binary_to_list(maps:get(<<"control_registration_path">>, Cmd)),
    case file:read_file(CtrlPath) of
        {ok, RegBin} ->
            case cepaf_gleam@harness@telegram_lifecycle_adapter:decode_control_registration(RegBin) of
                {ok, Reg} ->
                    case cepaf_gleam@harness@telegram_lifecycle_adapter:verify_live_lifecycle_ownership(Reg) of
                        {ok, nil} ->
                            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                                <<"status">> => <<"ok">>,
                                <<"verdict">> => <<"verified">>
                            });
                        {error, Err} ->
                            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                                <<"status">> => <<"error">>,
                                <<"reason">> => Err
                            })
                    end;
                {error, DecErr} ->
                    write_json_file(filename:join([IpcDir, "resp.json"]), #{
                        <<"status">> => <<"error">>,
                        <<"reason">> => DecErr
                    })
            end;
        {error, ReadErr} ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                <<"status">> => <<"error">>,
                <<"reason">> => list_to_binary(io_lib:format("~p", [ReadErr]))
            })
    end,
    standby_loop(IpcDir, Config);

handle_standby_command(#{<<"action">> := <<"init_only">>} = Cmd, IpcDir, Config) ->
    MergedConfig = maps:merge(Config, Cmd),
    SvcConfig = build_service_configuration(MergedConfig),
    ReceiptOpt = build_receipt_opt(MergedConfig),
    case cepaf_gleam@harness@telegram_service:init_service(SvcConfig, ReceiptOpt) of
        {ok, {State, StepResult}} ->
            WriterStateStr = encode_writer_state(element(5, State)),
            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                <<"status">> => <<"ok">>,
                <<"writer_state">> => WriterStateStr,
                <<"summary">> => encode_step_result(StepResult)
            });
        {error, Reason} ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                <<"status">> => <<"error">>,
                <<"reason">> => Reason
            })
    end,
    standby_loop(IpcDir, Config);

handle_standby_command(#{<<"action">> := <<"start_actor">>} = Cmd, IpcDir, Config) ->
    MergedConfig = maps:merge(Config, Cmd),
    start_and_run_actor(MergedConfig, IpcDir);

handle_standby_command(#{<<"action">> := <<"claim_processing_and_hang">>} = Cmd, IpcDir, Config) ->
    MergedConfig = maps:merge(Config, Cmd),
    SvcConfig = build_service_configuration(MergedConfig),
    StorageConfig = element(2, SvcConfig),
    BotId = element(4, SvcConfig),
    Epoch = element(13, SvcConfig),
    WorkerId = element(10, SvcConfig),
    NowUs = maps:get(<<"now_us">>, Cmd, 1700000013000),
    case cepaf_gleam@harness@telegram_store:read_inbox_records(StorageConfig, 10, none) of
        {ok, {Gen, [{Rec, Ver, Sha} | _]}} ->
            {ok, _} = cepaf_gleam@harness@telegram_store:claim_task_processing(
                StorageConfig, BotId, <<"op-claim-hang">>, Gen, Rec, Ver, Sha, WorkerId, Epoch, NowUs
            ),
            write_json_file(filename:join([IpcDir, "resp.json"]), #{<<"status">> => <<"claimed">>}),
            % Intentionally sleep and wait for systemd SIGTERM/SIGKILL kill
            timer:sleep(infinity);
        _ ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{<<"status">> => <<"error">>, <<"reason">> => <<"claim_failed">>}),
            standby_loop(IpcDir, Config)
    end;

handle_standby_command(#{<<"action">> := <<"stop">>}, IpcDir, _Config) ->
    write_json_file(filename:join([IpcDir, "resp.json"]), #{<<"status">> => <<"stopped">>}),
    erlang:halt(0);

handle_standby_command(Unknown, IpcDir, Config) ->
    write_json_file(filename:join([IpcDir, "resp.json"]), #{
        <<"status">> => <<"error">>,
        <<"reason">> => <<"unknown_standby_command">>,
        <<"cmd">> => Unknown
    }),
    standby_loop(IpcDir, Config).

start_and_run_actor(Config, IpcDir) ->
    SvcConfig = build_service_configuration(Config),
    ReceiptOpt = build_receipt_opt(Config),
    StartRes = case maps:get(<<"managed_start">>, Config, false) of
        true ->
            put(managed_start_config, Config),
            case managed_start_result(Config) of
                {ok, SupSvc} -> put(managed_supervised_service, SupSvc), {ok, element(3, SupSvc)};
                {error, Err} -> {error, Err}
            end;
        false ->
            case maps:get(<<"supervised">>, Config, false) of
        true ->
            case cepaf_gleam@harness@telegram_service:start_supervised_service(SvcConfig, ReceiptOpt) of
                {ok, SupSvc} -> put(managed_supervised_service, SupSvc), {ok, element(3, SupSvc)};
                {error, Err} -> {error, Err}
            end;
        false ->
            case cepaf_gleam@harness@telegram_service:start_actor(SvcConfig, ReceiptOpt) of
                {ok, Started} -> {ok, element(3, Started)};
                {error, Err} -> {error, Err}
            end
            end
    end,
    case StartRes of
        {ok, Subj} ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                <<"status">> => <<"ok">>,
                <<"action">> => <<"started">>
            }),
            actor_loop(Subj, IpcDir, SvcConfig);
        {error, Reason} ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                <<"status">> => <<"error">>,
                <<"reason">> => Reason
            }),
            standby_loop(IpcDir, Config)
    end.

managed_start_result(Config) ->
    SvcConfig = build_service_configuration(Config),
    ReceiptOpt = build_receipt_opt(Config),
    CurrentPath = maps:get(<<"current_control_registration_path">>, Config, <<>>),
    WriterJson = maps:get(<<"writer_registration">>, Config, <<>>),
    case cepaf_gleam@harness@telegram_store_codec:decode_writer_registration(WriterJson) of
        {ok, Writer} ->
            cepaf_gleam@harness@telegram_service:start_managed_service(
                SvcConfig, CurrentPath, Writer, ReceiptOpt);
        {error, Reason} -> {error, Reason}
    end.

actor_loop(Subj, IpcDir, SvcConfig) ->
    CmdPath = filename:join([IpcDir, "cmd.json"]),
    case file:read_file(CmdPath) of
        {ok, CmdBin} ->
            _ = file:delete(CmdPath),
            Cmd = json:decode(CmdBin),
            handle_actor_command(Cmd, Subj, IpcDir, SvcConfig);
        {error, _} ->
            timer:sleep(20),
            actor_loop(Subj, IpcDir, SvcConfig)
    end.

handle_actor_command(#{<<"action">> := <<"repeat_managed_start">>}, Subj, IpcDir, SvcConfig) ->
    Result = case get(managed_start_config) of
        undefined -> #{<<"status">> => <<"error">>, <<"reason">> => <<"managed_start_context_missing">>};
        Config ->
            case managed_start_result(Config) of
                {error, Reason} -> #{<<"status">> => <<"refused">>, <<"reason">> => Reason};
                {ok, Duplicate} ->
                    Cleanup = cepaf_gleam@harness@telegram_service:stop_supervised_service(Duplicate),
                    #{<<"status">> => <<"duplicate_admitted">>,
                      <<"cleanup">> => list_to_binary(io_lib:format("~p", [Cleanup]))}
            end
    end,
    write_json_file(filename:join([IpcDir, "resp.json"]), Result),
    actor_loop(Subj, IpcDir, SvcConfig);

handle_actor_command(#{<<"action">> := <<"set_authority">>} = Cmd, Subj, IpcDir, SvcConfig) ->
    LeaseId = maps:get(<<"lease_id">>, Cmd),
    Attempt = maps:get(<<"attempt">>, Cmd, 1),
    Epoch = maps:get(<<"epoch">>, Cmd, 1),
    ValidUntilUs = maps:get(<<"valid_until_us">>, Cmd),
    Lease = {authority_lease, LeaseId, Attempt, Epoch, ValidUntilUs},
    gleam@erlang@process:send(Subj, {set_authority, Lease}),
    write_json_file(filename:join([IpcDir, "resp.json"]), #{<<"status">> => <<"ok">>}),
    actor_loop(Subj, IpcDir, SvcConfig);

handle_actor_command(#{<<"action">> := <<"poll_cycle">>} = Cmd, Subj, IpcDir, SvcConfig) ->
    NowUs = maps:get(<<"now_us">>, Cmd),
    PollRes = gleam@erlang@process:call(Subj, 15000, fun(Reply) -> {poll_cycle, NowUs, Reply} end),
    case PollRes of
        {ok, StepResult} ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                <<"status">> => <<"ok">>,
                <<"result">> => encode_step_result(StepResult)
            });
        {error, Err} ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                <<"status">> => <<"error">>,
                <<"reason">> => Err
            })
    end,
    actor_loop(Subj, IpcDir, SvcConfig);

handle_actor_command(#{<<"action">> := <<"automatic_dispatch_tick">>} = Cmd, Subj, IpcDir, SvcConfig) ->
    NowUs = maps:get(<<"now_us">>, Cmd),
    TickRes = gleam@erlang@process:call(Subj, 3000, fun(Reply) -> {automatic_dispatch_tick, NowUs, Reply} end),
    case TickRes of
        {ok, StepResult} ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                <<"status">> => <<"ok">>,
                <<"result">> => encode_step_result(StepResult)
            });
        {error, Err} ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                <<"status">> => <<"error">>,
                <<"reason">> => Err
            })
    end,
    actor_loop(Subj, IpcDir, SvcConfig);

handle_actor_command(#{<<"action">> := <<"finite_automatic_loop">>}, Subj, IpcDir, SvcConfig) ->
    Observer = gleam@erlang@process:new_subject(),
    Config = {config, 2, 6000, 10, 15000, 15000, 1},
    Result = case cepaf_gleam@harness@telegram_loop:start(Subj, Config, Observer) of
        {ok, {started, DriverPid, DriverSubject}} ->
            unlink(DriverPid),
            Mon = erlang:monitor(process, DriverPid),
            Received = gleam@erlang@process:'receive'(Observer, 7000),
            Down = receive {'DOWN', Mon, process, DriverPid, Why} -> {down, Why}
                after 1000 -> unknown end,
            case {Received, Down} of
                {{ok, {terminal, Reason, Cycles}}, {down, normal}} ->
                    #{<<"status">> => <<"ok">>, <<"reason">> => Reason,
                      <<"completed_cycles">> => Cycles};
                _ ->
                    gleam@erlang@process:send(DriverSubject, stop),
                    case Down of
                        {down, _} -> ok;
                        unknown ->
                            exit(DriverPid, kill),
                            receive {'DOWN', Mon, process, DriverPid, _} -> ok
                            after 500 -> erlang:error(loop_cleanup_unconfirmed) end
                    end,
                    erlang:demonitor(Mon, [flush]),
                    #{<<"status">> => <<"error">>, <<"reason">> => <<"loop_terminal_unconfirmed">>}
            end;
        {error, _} -> #{<<"status">> => <<"error">>, <<"reason">> => <<"loop_start_failed">>}
    end,
    write_json_file(filename:join([IpcDir, "resp.json"]), Result),
    actor_loop(Subj, IpcDir, SvcConfig);

handle_actor_command(#{<<"action">> := <<"get_state">>}, Subj, IpcDir, SvcConfig) ->
    State = gleam@erlang@process:call(Subj, 2000, fun(Reply) -> {get_state, Reply} end),
    Pending = gleam@erlang@process:call(Subj, 2000, fun(Reply) -> {get_pending_operation, Reply} end),
    Watermark = element(7, State),
    LastOffset = element(2, Watermark),
    Gen = element(10, State),
    WriterStateStr = encode_writer_state(element(5, State)),
    write_json_file(filename:join([IpcDir, "resp.json"]), #{
        <<"status">> => <<"ok">>,
        <<"last_committed_offset">> => LastOffset,
        <<"expected_generation">> => Gen,
        <<"pending_operation_present">> => Pending =/= none,
        <<"writer_state">> => WriterStateStr
    }),
    actor_loop(Subj, IpcDir, SvcConfig);

handle_actor_command(#{<<"action">> := <<"deliver_chunk_from_store">>} = Cmd, Subj, IpcDir, SvcConfig) ->
    ReqId = maps:get(<<"request_id">>, Cmd),
    NowUs = maps:get(<<"now_us">>, Cmd),
    StorageConfig = element(2, SvcConfig),
    case cepaf_gleam@harness@telegram_store:read_inbox_records(StorageConfig, 10, none) of
        {ok, {_Gen, Records}} ->
            Matching = [{R, V, S} || {R, V, S} <- Records, element(10, R) =:= ReqId orelse element(2, R) =:= ReqId],
            case Matching of
                [{ReadyRec, ReadyVer, ReadySha}] ->
                    ChunkKey = cepaf_gleam@harness@telegram_store_codec:chunk_key(element(10, ReadyRec), 0),
                    case cepaf_gleam@harness@telegram_store:read_keys(StorageConfig, [ChunkKey]) of
                        {ok, {_CGen, [CRow]}} ->
                            {ok, CRaw} = cepaf_gleam@harness@telegram_store_codec:decode_row_value(CRow),
                            {ok, Chunk} = cepaf_gleam@harness@telegram_store_codec:decode_chunk_value(CRaw),
                            ChunkVer = element(4, CRow),
                            ChunkSha = element(6, CRow),
                            DeliverRes = gleam@erlang@process:call(
                                Subj, 2000,
                                fun(Reply) ->
                                    {deliver_chunk, ReadyRec, ReadyVer, ReadySha, Chunk, ChunkVer, ChunkSha, NowUs, Reply}
                                end
                            ),
                            case DeliverRes of
                                {ok, StepRes} ->
                                    write_json_file(filename:join([IpcDir, "resp.json"]), #{
                                        <<"status">> => <<"ok">>,
                                        <<"result">> => encode_step_result(StepRes)
                                    });
                                {error, Err} ->
                                    write_json_file(filename:join([IpcDir, "resp.json"]), #{
                                        <<"status">> => <<"error">>,
                                        <<"reason">> => Err
                                    })
                            end;
                        {error, ErrK} ->
                            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                                <<"status">> => <<"error">>,
                                <<"reason">> => list_to_binary(io_lib:format("~p", [ErrK]))
                            })
                    end;
                _ ->
                    write_json_file(filename:join([IpcDir, "resp.json"]), #{
                        <<"status">> => <<"error">>,
                        <<"reason">> => <<"inbox_record_not_found">>
                    })
            end;
        {error, ErrInbox} ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{
                <<"status">> => <<"error">>,
                <<"reason">> => list_to_binary(io_lib:format("~p", [ErrInbox]))
            })
    end,
    actor_loop(Subj, IpcDir, SvcConfig);

handle_actor_command(#{<<"action">> := <<"stop">>}, Subj, IpcDir, _SvcConfig) ->
    Cleanup = case erase(managed_supervised_service) of
        undefined -> gleam@erlang@process:send(Subj, stop), {ok, nil};
        SupSvc -> cepaf_gleam@harness@telegram_service:stop_supervised_service(SupSvc)
    end,
    case Cleanup of
        {ok, _} ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{<<"status">> => <<"stopped">>}),
            erlang:halt(0);
        {error, Reason} ->
            write_json_file(filename:join([IpcDir, "resp.json"]), #{<<"status">> => <<"cleanup_unconfirmed">>, <<"reason">> => Reason}),
            erlang:halt(1)
    end;

handle_actor_command(Unknown, _Subj, IpcDir, SvcConfig) ->
    write_json_file(filename:join([IpcDir, "resp.json"]), #{
        <<"status">> => <<"error">>,
        <<"reason">> => <<"unknown_actor_command">>,
        <<"cmd">> => Unknown
    }),
    actor_loop(_Subj, IpcDir, SvcConfig).

build_service_configuration(Config) ->
    DbPath = maps:get(<<"db_path">>, Config),
    GuardianPath = maps:get(<<"guardian_path">>, Config, <<"/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe">>),
    GuardianSha = maps:get(<<"guardian_sha">>, Config, <<"06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab">>),
    WorkerPath = maps:get(<<"worker_path">>, Config, <<"/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe">>),
    WorkerSha = maps:get(<<"worker_sha">>, Config, <<"f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e">>),
    StorageCfg = cepaf_gleam@harness@telegram_store_transport:reviewed_local_configuration(
        GuardianPath, GuardianSha, WorkerPath, WorkerSha, DbPath
    ),
    BaseUrl = maps:get(<<"base_url">>, Config, <<"http://127.0.0.1:9">>),
    Token = maps:get(<<"token">>, Config, <<"test-token">>),
    HttpCfg = cepaf_gleam@harness@telegram_http_client:default_configuration(BaseUrl, Token),
    BotId = maps:get(<<"bot_id">>, Config, 888111),
    AllowedPairsRaw = maps:get(<<"allowed_pairs">>, Config, [[100, 200]]),
    AllowedPairs = [list_to_tuple(P) || P <- AllowedPairsRaw],
    WorkerId = maps:get(<<"worker_id">>, Config, <<"worker-e2e-01">>),
    TaskId = maps:get(<<"task_id">>, Config, <<"lease-e2e-01">>),
    PlanId = maps:get(<<"plan_id">>, Config, <<"plan-e2e">>),
    ServiceEpoch = maps:get(<<"service_epoch">>, Config, 1),
    SaPlanDb = maps:get(<<"sa_plan_db">>, Config, <<"/tmp/sa_plan.sqlite3">>),
    CoordDb = maps:get(<<"coord_db">>, Config, <<"/tmp/coord.sqlite3">>),
    CtrlPath = maps:get(<<"control_registration_path">>, Config, null),
    CtrlPathOpt = case CtrlPath of
        null -> none;
        <<>> -> none;
        P when is_binary(P) -> {some, P}
    end,
    AuthPaths = {isolated_test_paths, SaPlanDb, CoordDb},
    ObsExe = <<"/home/an/NAS-setup/uos/tools/validation/sa_plan_observer.exe"/utf8>>,
    ObsSha = <<"5b9dab694c7486f39decb0f3db4238b74753941a659106d5e12fee3c0fe656e2"/utf8>>,
    GuardExe = <<"/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe"/utf8>>,
    GuardSha = <<"b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be"/utf8>>,
    {service_configuration,
        StorageCfg,
        HttpCfg,
        BotId,
        AllowedPairs,
        PlanId,
        TaskId,
        WorkerId,
        maps:get(<<"resource_id">>, Config, <<"task:", TaskId/binary>>),
        WorkerId,
        maps:get(<<"expected_task_attempt">>, Config, 1),
        maps:get(<<"coordinator_epoch">>, Config, 1),
        ServiceEpoch,
        10, % poll_limit
        1,  % poll_timeout_s
        ObsExe,
        ObsSha,
        GuardExe,
        GuardSha,
        AuthPaths,
        CtrlPathOpt}.

build_receipt_opt(Config) ->
    case maps:get(<<"cleanup_receipt">>, Config, null) of
        null ->
            case maps:get(<<"cleanup_receipt_path">>, Config, null) of
                null -> none;
                Path when is_binary(Path) ->
                    case file:read_file(Path) of
                        {ok, Bin} ->
                            build_receipt_opt(#{<<"cleanup_receipt">> => json:decode(Bin)});
                        _ -> none
                    end
            end;
        R when is_map(R) ->
            UnitName = maps:get(<<"unit_name">>, R),
            SliceName = maps:get(<<"slice_name">>, R),
            InvId = maps:get(<<"invocation_id">>, R),
            SliceInvId = maps:get(<<"slice_invocation_id">>, R),
            StoreIncId = maps:get(<<"store_incarnation_id">>, R, <<>>),
            ServiceEpoch = maps:get(<<"service_epoch">>, R, 1),
            StoppedAt = maps:get(<<"stopped_at_us">>, R),
            ExitStatus = maps:get(<<"exit_status">>, R, 0),
            CgroupPath = maps:get(<<"cgroup_path">>, R),
            StoreDbPath = maps:get(<<"store_db_path">>, R),
            WorkerHash = maps:get(<<"worker_hash">>, R),
            GuardianHash = maps:get(<<"guardian_hash">>, R),
            {some, {unit_cleanup_receipt,
                UnitName,
                SliceName,
                InvId,
                SliceInvId,
                StoreIncId,
                ServiceEpoch,
                StoppedAt,
                ExitStatus,
                CgroupPath,
                StoreDbPath,
                WorkerHash,
                GuardianHash}}
    end.

encode_writer_state(service_writer_clean) ->
    <<"clean">>;
encode_writer_state({service_writer_hold, Reason}) ->
    <<"hold:", Reason/binary>>.

encode_step_result({poll_committed, Count, Wm}) ->
    #{<<"type">> => <<"poll_committed">>, <<"count">> => Count, <<"new_watermark">> => Wm};
encode_step_result(poll_empty) ->
    #{<<"type">> => <<"poll_empty">>};
encode_step_result({poll_skipped, Reason}) ->
    #{<<"type">> => <<"poll_skipped">>, <<"reason">> => Reason};
encode_step_result({delivery_step_success, ReqId, MsgId}) ->
    #{<<"type">> => <<"delivery_step_success">>, <<"request_id">> => ReqId, <<"message_id">> => MsgId};
encode_step_result({delivery_step_failed, ReqId, Reason}) ->
    #{<<"type">> => <<"delivery_step_failed">>, <<"request_id">> => ReqId, <<"reason">> => Reason};
encode_step_result({delivery_step_uncertain, ReqId, Reason}) ->
    #{<<"type">> => <<"delivery_step_uncertain">>, <<"request_id">> => ReqId, <<"reason">> => Reason};
encode_step_result({recovery_result, Active, Held, Total}) ->
    #{<<"type">> => <<"recovery_result">>, <<"active_count">> => Active, <<"held_count">> => Held, <<"total_records">> => Total};
encode_step_result({recovery_hold, Reason}) ->
    #{<<"type">> => <<"recovery_hold">>, <<"reason">> => Reason};
encode_step_result({dispatch_cycle_result, Proc, Deliv}) ->
    #{<<"type">> => <<"dispatch_cycle_result">>, <<"processed_count">> => Proc, <<"delivered_count">> => Deliv}.

write_json_file(Path, Data) ->
    Json = json:encode(Data),
    TmpPath = Path ++ ".tmp",
    ok = file:write_file(TmpPath, Json),
    ok = file:rename(TmpPath, Path),
    ok.
