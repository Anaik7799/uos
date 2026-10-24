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
            telegram_service_worker_runner, telegram_http_ffi,
            telegram_store_transport_ffi, telegram_lifecycle_ffi,
            sa_plan_observer_ffi,
            'cepaf_gleam@harness@telegram_service',
            'cepaf_gleam@harness@telegram_http_client',
            'cepaf_gleam@harness@telegram_poll_rpc',
            'cepaf_gleam@harness@telegram_loop',
            'cepaf_gleam@harness@telegram_store',
            'cepaf_gleam@harness@telegram_lifecycle_adapter'
        ],
        Pins = [pin(M, Dir) || M <- Modules],
        Data = {Paths, [H || {_, H} <- Pins], ConfigPath},
        true = byte_size(term_to_binary(Data)) =< 100000,
        Payload = base64:encode(term_to_binary(Data, [compressed])),
        Expr = io_lib:format(
            "{P,H,C}=binary_to_term(base64:decode(~0p),[safe]),"
            "true=code:set_path(P),"
            "lists:foreach(fun({M,D})->"
            "{M,B,F}=code:get_object_code(M),"
            "D=crypto:hash(sha256,B),"
            "{module,M}=code:load_binary(M,F,B)"
            " end,lists:zip(~0p,H)),"
            "telegram_service_worker_runner:start([C]).",
            [Payload, Modules]),
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
