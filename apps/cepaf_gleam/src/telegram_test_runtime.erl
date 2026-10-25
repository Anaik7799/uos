%% Test-only child build binding. No process launch or production admission.
-module(telegram_test_runtime).
-export([launch_eval/1]).

launch_eval(ConfigPath) ->
    try
        true = is_binary(ConfigPath),
        true = byte_size(ConfigPath) > 0 andalso byte_size(ConfigPath) =< 4096,
        nomatch = binary:match(ConfigPath, <<0>>),
        absolute = filename:pathtype(binary_to_list(ConfigPath)),
        RawPaths = code:get_path(),
        true = length(RawPaths) =< 256,
        Paths = [absolute_path(P) || P <- RawPaths],
        RunnerFile = code:which(telegram_service_worker_runner),
        true = is_list(RunnerFile),
        Dir = filename:dirname(filename:absname(RunnerFile)),
        Modules = [
            telegram_service_worker_runner, telegram_conversation_test_io, telegram_http_ffi,
            telegram_store_transport_ffi, telegram_lifecycle_ffi,
            sa_plan_observer_ffi,
            'cepaf_gleam@harness@telegram_service',
            'cepaf_gleam@harness@telegram_http_client',
            'cepaf_gleam@harness@telegram_poll_rpc',
            'cepaf_gleam@harness@telegram_loop',
            'cepaf_gleam@harness@telegram_runtime',
            'cepaf_gleam@harness@telegram_commands',
            'cepaf_gleam@harness@telegram_conversation',
            'cepaf_gleam@harness@telegram_conversation_model',
            'cepaf_gleam@harness@telegram_memory_command',
            'cepaf_gleam@harness@telegram_tool_command',
            'cepaf_gleam@harness@telegram_operational_status',
            'cepaf_gleam@harness@telegram_ha_report',
            'cepaf_gleam@harness@telegram_budget_report', telegram_budget_clock,
            'cepaf_gleam@ha@beam_metrics', beam_metrics_ffi, uos_openrouter_ffi,
            'cepaf_gleam@harness@telegram_host_observation',
            telegram_knowledge_files, telegram_risk_files,
            'cepaf_gleam@harness@telegram_fmea_report', 'cepaf_gleam@harness@telegram_fmea_reader',
            'cepaf_gleam@harness@telegram_knowledge_report',
      'cepaf_gleam@harness@telegram_search_report',
      'cepaf_gleam@harness@telegram_storage_report',
      'cepaf_gleam@harness@telegram_verification_report',
      'cepaf_gleam@harness@telegram_verification_reader',
      'cepaf_gleam@harness@telegram_evidence_status',
      'cepaf_gleam@harness@telegram_rete_report',
      telegram_ecology_clock, 'cepaf_gleam@harness@telegram_ecology_report', 'cepaf_gleam@harness@telegram_ecology_reader',
      telegram_matrix_http, 'cepaf_gleam@harness@telegram_matrix_report', 'cepaf_gleam@harness@telegram_matrix_reader',
            'cepaf_gleam@harness@telegram_knowledge_reader',
            telegram_status_probe, telegram_coordination_binding,
            'cepaf_gleam@harness@telegram_coordination_report',
            'cepaf_gleam@harness@telegram_coordination_reader',
            'cepaf_gleam@harness@telegram_task_command',
            'cepaf_gleam@harness@telegram_ingress_guard',
            'cepaf_gleam@harness@telegram_store_codec',
            'cepaf_gleam@harness@telegram_store',
            'cepaf_gleam@harness@telegram_lifecycle_adapter'
        ],
        Pins = [pin(M, Dir) || M <- Modules],
        Names = [atom_to_binary(M,utf8) || M <- Modules],
        Binding = crypto:hash(sha256,term_to_binary([{atom_to_binary(M,utf8),H} || {M,H} <- Pins])),
        Data = {Paths, Names, Binding, ConfigPath},
        true = byte_size(term_to_binary(Data)) =< 100000,
        Payload = base64:encode(term_to_binary(Data, [{compressed,9}])),
        Expr = io_lib:format(
            "{P,N,H,C}=binary_to_term(base64:decode(~0p),[safe]),"
            "true=code:set_path(P),true=byte_size(H)=:=32,"
            "B=[begin M=binary_to_atom(X,utf8),{M,D,F}=code:get_object_code(M),{M,D,F} end||X<-N],"
            "H=crypto:hash(sha256,term_to_binary([{atom_to_binary(M,utf8),crypto:hash(sha256,D)}||{M,D,_}<-B])),"
            "lists:foreach(fun({M,D,F})->{module,M}=code:load_binary(M,F,D) end,B),"
            "telegram_service_worker_runner:start([C]).",
            [Payload]),
        Binary = iolist_to_binary(Expr),
        true = byte_size(Binary) =< 4096,
        {ok, Binary}
    catch _:_ ->
        {error, <<"test_runtime_binding_failed">>}
    end.

absolute_path(P) ->
    true = is_list(P),
    true = length(P) > 0 andalso length(P) =< 4096,
    false = lists:member(0, P),
    Absolute = filename:absname(P),
    true = length(Absolute) =< 4096,
    Absolute.

pin(M, Dir) ->
    {M, Beam, File} = code:get_object_code(M),
    true = byte_size(Beam) =< 8388608,
    Dir = filename:dirname(filename:absname(File)),
    {M, crypto:hash(sha256, Beam)}.
