%%%-------------------------------------------------------------------
%%% @doc
%%% [C3I-SIL6] UOS Distributed Execution Node (Instance 2 - Laptop Node)
%%% Pure Erlang/OTP 29 Runtime Engine (zero external dependencies)
%%% Mandate: SC-NIX-DEVENV-001, SC-ZMOF-001, SC-TIME
%%% @end
%%%-------------------------------------------------------------------
-module(uos_instance2).
-behaviour(gen_server).

%% API
-export([start/0, start/1, start_link/1, stop/0, health/0, status/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    port :: integer(),
    lsocket :: gen_tcp:socket(),
    start_time :: integer(),
    master_nodes :: [node()],
    timer_ref :: reference()
}).

-define(DEFAULT_PORT, 8088).
-define(PING_INTERVAL_MS, 5000).
-define(COOKIE, 'uos_vajravyuh_cookie').

%%====================================================================
%% API functions
%%====================================================================

-spec start() -> {ok, pid()} | {error, term()}.
start() ->
    start(?DEFAULT_PORT).

-spec start(integer()) -> {ok, pid()} | {error, term()}.
start(Port) ->
    case gen_server:start({local, ?MODULE}, ?MODULE, [Port], []) of
        {ok, Pid} ->
            log_info("Instance 2 OTP 29 runtime engine started on port ~p", [Port]),
            {ok, Pid};
        {error, {already_started, Pid}} ->
            log_info("Instance 2 already running with PID ~p", [Pid]),
            {ok, Pid};
        Error ->
            log_error("Failed to start Instance 2: ~p", [Error]),
            Error
    end.

-spec start_link(integer()) -> {ok, pid()} | {error, term()}.
start_link(Port) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Port], []).

-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

-spec health() -> map().
health() ->
    gen_server:call(?MODULE, get_health).

-spec status() -> map().
status() ->
    health().

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([Port]) ->
    process_flag(trap_exit, true),
    StartTime = erlang:system_time(second),

    %% 1. Set Erlang Distributed Cookie
    case is_alive() of true -> erlang:set_cookie(node(), ?COOKIE); false -> ok end,

    %% 2. Open TCP Listen Socket on 0.0.0.0:Port
    Opts = [binary, {packet, 0}, {active, false}, {reuseaddr, true}, {backlog, 128}],
    case gen_tcp:listen(Port, Opts) of
        {ok, LSocket} ->
            log_info("TCP HTTP server listening on 0.0.0.0:~p", [Port]),
            %% Spawn TCP accept loop
            spawn_link(fun() -> accept_loop(LSocket, StartTime) end),

            %% 3. Setup periodic mesh ping timer
            TimerRef = erlang:send_after(1000, self(), ping_masters),

            MasterCandidates = [
                'uos_primary@100.87.7.78',
                'uos_primary@192.168.1.220',
                'instance0@100.87.7.78',
                'instance0@192.168.1.220',
                'instance1@100.78.98.18'
            ],

            {ok, #state{
                port = Port,
                lsocket = LSocket,
                start_time = StartTime,
                master_nodes = MasterCandidates,
                timer_ref = TimerRef
            }};
        {error, Reason} ->
            log_error("Failed to bind port ~p: ~p", [Port, Reason]),
            {stop, Reason}
    end.

handle_call(get_health, _From, State) ->
    HealthData = gather_health_data(State#state.start_time),
    {reply, HealthData, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(ping_masters, State) ->
    %% Attempt to connect to any uncontacted master nodes
    Connected = nodes(),
    lists:foreach(fun(Master) ->
        case lists:member(Master, Connected) of
            true -> ok;
            false ->
                case net_adm:ping(Master) of
                    pong ->
                        log_info("Connected to peer node: ~p", [Master]);
                    pang ->
                        ok
                end
        end
    end, State#state.master_nodes),
    NewTimer = erlang:send_after(?PING_INTERVAL_MS, self(), ping_masters),
    {noreply, State#state{timer_ref = NewTimer}};

handle_info({'EXIT', _Pid, normal}, State) ->
    {noreply, State};

handle_info({'EXIT', Pid, Reason}, State) ->
    log_warn("Worker ~p exited: ~p", [Pid, Reason]),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    log_info("Shutting down Instance 2 on port ~p...", [State#state.port]),
    try gen_tcp:close(State#state.lsocket) catch _:_ -> ok end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal HTTP Server
%%====================================================================

accept_loop(LSocket, StartTime) ->
    case gen_tcp:accept(LSocket) of
        {ok, Socket} ->
            spawn(fun() ->
                handle_http_connection(Socket, StartTime),
                gen_tcp:close(Socket)
            end),
            accept_loop(LSocket, StartTime);
        {error, closed} ->
            ok;
        {error, Reason} ->
            log_error("Accept error: ~p", [Reason]),
            timer:sleep(500),
            accept_loop(LSocket, StartTime)
    end.

handle_http_connection(Socket, StartTime) ->
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, RequestBin} ->
            RequestStr = binary_to_list(RequestBin),
            case parse_request(RequestStr) of
                {Method, Path} ->
                    dispatch_request(Socket, Method, Path, StartTime);
                error ->
                    send_response(Socket, 400, "text/plain", "Bad Request\r\n")
            end;
        {error, timeout} ->
            ok;
        {error, _} ->
            ok
    end.

parse_request(Str) ->
    case string:tokens(Str, "\r\n") of
        [FirstLine | _] ->
            case string:tokens(FirstLine, " ") of
                [Method, Path, _Version] -> {Method, Path};
                [Method, Path] -> {Method, Path};
                _ -> error
            end;
        _ -> error
    end.

dispatch_request(Socket, "GET", Path, StartTime) ->
    case Path of
        P when P =:= "/health"; P =:= "/api/health"; P =:= "/healthz"; P =:= "/status" ->
            Health = gather_health_data(StartTime),
            Json = encode_health_json(Health),
            send_response(Socket, 200, "application/json", Json);
        P when P =:= "/"; P =:= "/index.html" ->
            Health = gather_health_data(StartTime),
            Html = render_dashboard_html(Health),
            send_response(Socket, 200, "text/html", Html);
        "/metrics" ->
            Metrics = render_metrics(StartTime),
            send_response(Socket, 200, "text/plain; version=0.0.4", Metrics);
        _ ->
            send_response(Socket, 404, "application/json", "{\"error\":\"Not Found\"}\r\n")
    end;

dispatch_request(Socket, "OPTIONS", _Path, _StartTime) ->
    %% CORS preflight
    Headers = "HTTP/1.1 204 No Content\r\n"
              "Access-Control-Allow-Origin: *\r\n"
              "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
              "Access-Control-Allow-Headers: Content-Type\r\n"
              "Content-Length: 0\r\n\r\n",
    gen_tcp:send(Socket, list_to_binary(Headers));

dispatch_request(Socket, _Method, _Path, _StartTime) ->
    send_response(Socket, 405, "application/json", "{\"error\":\"Method Not Allowed\"}\r\n").

send_response(Socket, StatusCode, ContentType, Body) ->
    BodyBin = if is_binary(Body) -> Body; is_list(Body) -> list_to_binary(Body) end,
    StatusText = case StatusCode of
        200 -> "OK";
        204 -> "No Content";
        400 -> "Bad Request";
        404 -> "Not Found";
        405 -> "Method Not Allowed";
        500 -> "Internal Server Error"
    end,
    Response = io_lib:format(
        "HTTP/1.1 ~p ~s\r\n"
        "Content-Type: ~s\r\n"
        "Content-Length: ~p\r\n"
        "Access-Control-Allow-Origin: *\r\n"
        "Connection: close\r\n"
        "Server: UOS-OTP29/1.0.0\r\n\r\n",
        [StatusCode, StatusText, ContentType, byte_size(BodyBin)]
    ),
    gen_tcp:send(Socket, [list_to_binary(Response), BodyBin]).

%%====================================================================
%% Health & Metrics Helpers
%%====================================================================

gather_health_data(StartTime) ->
    Now = erlang:system_time(second),
    Uptime = Now - StartTime,
    OtpRelease = erlang:system_info(otp_release),
    ErtsVersion = erlang:system_info(version),
    NodeName = atom_to_list(node()),
    ConnectedNodes = [atom_to_list(N) || N <- nodes()],
    ProcessCount = erlang:system_info(process_count),
    ProcessLimit = erlang:system_info(process_limit),
    Memory = erlang:memory(total),

    %% Check GPU in WSL2
    HasGPU = filelib:is_regular("/dev/dxg") orelse filelib:is_dir("/dev/dxg"),

    #{
        status => <<"healthy">>,
        instance_id => <<"razr15-1-wsl2">>,
        instance_role => <<"Instance 2 (Laptop GPU / Worker Node)">>,
        runtime_engine => list_to_binary(io_lib:format("Erlang/OTP ~s (ERTS ~s)", [OtpRelease, ErtsVersion])),
        otp_release => list_to_binary(OtpRelease),
        erts_version => list_to_binary(ErtsVersion),
        beam_node => list_to_binary(NodeName),
        connected_nodes => [list_to_binary(N) || N <- ConnectedNodes],
        peer_count => length(ConnectedNodes),
        process_count => ProcessCount,
        process_limit => ProcessLimit,
        memory_bytes => Memory,
        memory_mb => Memory / (1024 * 1024),
        uptime_seconds => Uptime,
        has_gpu => HasGPU,
        gpu_device => if HasGPU -> <<"NVIDIA CUDA /dev/dxg (DirectX WSL2)">>; true -> <<"CPU SIMD Emulation">> end,
        mesh => <<"Samvid Vajravyuha">>,
        distributed_operations => [
            <<"OTP_DISTRIBUTED_MESSAGING">>,
            <<"BEAM_WORK_STEALING">>,
            <<"FRACTAL_SWARM_LEASES">>,
            <<"CEPAF_HEALTH_MONITOR">>
        ],
        timestamp_utc => list_to_binary(iso8601_now())
    }.

encode_health_json(Map) ->
    #{
        status := Status,
        instance_id := InstId,
        instance_role := InstRole,
        runtime_engine := Runtime,
        otp_release := OtpRel,
        erts_version := ErtsVsn,
        beam_node := NodeName,
        connected_nodes := Nodes,
        peer_count := PeerCount,
        process_count := ProcCount,
        process_limit := ProcLimit,
        memory_bytes := MemBytes,
        memory_mb := MemMb,
        uptime_seconds := Uptime,
        has_gpu := HasGPU,
        gpu_device := GpuDev,
        mesh := Mesh,
        distributed_operations := Ops,
        timestamp_utc := Ts
    } = Map,

    NodesJson = "[" ++ string:join(["\"" ++ binary_to_list(N) ++ "\"" || N <- Nodes], ", ") ++ "]",
    OpsJson = "[" ++ string:join(["\"" ++ binary_to_list(O) ++ "\"" || O <- Ops], ", ") ++ "]",
    GpuBool = if HasGPU -> "true"; true -> "false" end,

    io_lib:format(
        "{\n"
        "  \"status\": \"~s\",\n"
        "  \"instance_id\": \"~s\",\n"
        "  \"instance_role\": \"~s\",\n"
        "  \"runtime_engine\": \"~s\",\n"
        "  \"otp_release\": \"~s\",\n"
        "  \"erts_version\": \"~s\",\n"
        "  \"beam_node\": \"~s\",\n"
        "  \"connected_nodes\": ~s,\n"
        "  \"peer_count\": ~p,\n"
        "  \"process_count\": ~p,\n"
        "  \"process_limit\": ~p,\n"
        "  \"memory_bytes\": ~p,\n"
        "  \"memory_mb\": ~.2f,\n"
        "  \"uptime_seconds\": ~p,\n"
        "  \"has_gpu\": ~s,\n"
        "  \"gpu_device\": \"~s\",\n"
        "  \"mesh\": \"~s\",\n"
        "  \"distributed_operations\": ~s,\n"
        "  \"timestamp_utc\": \"~s\"\n"
        "}\n",
        [Status, InstId, InstRole, Runtime, OtpRel, ErtsVsn, NodeName,
         NodesJson, PeerCount, ProcCount, ProcLimit, MemBytes, MemMb,
         Uptime, GpuBool, GpuDev, Mesh, OpsJson, Ts]
    ).

render_dashboard_html(Map) ->
    #{
        status := Status,
        instance_id := InstId,
        instance_role := InstRole,
        runtime_engine := Runtime,
        beam_node := NodeName,
        peer_count := PeerCount,
        memory_mb := MemMb,
        uptime_seconds := Uptime,
        gpu_device := GpuDev,
        timestamp_utc := Ts
    } = Map,

    io_lib:format(
        "<!DOCTYPE html>\n"
        "<html lang=\"en\">\n"
        "<head>\n"
        "  <meta charset=\"UTF-8\">\n"
        "  <title>UOS Instance 2 (Pure OTP 29)</title>\n"
        "  <style>\n"
        "    body { background: #0d1117; color: #c9d1d9; font-family: monospace; padding: 2rem; }\n"
        "    .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 1.5rem; max-width: 800px; margin: 0 auto; }\n"
        "    h1 { color: #58a6ff; margin-top: 0; }\n"
        "    .badge { display: inline-block; padding: 0.25rem 0.5rem; border-radius: 4px; font-weight: bold; background: #238636; color: #fff; }\n"
        "    .item { margin: 0.8rem 0; border-bottom: 1px solid #21262d; padding-bottom: 0.4rem; }\n"
        "    .label { color: #8b949e; width: 200px; display: inline-block; }\n"
        "    .val { color: #f0f6fc; font-weight: bold; }\n"
        "  </style>\n"
        "</head>\n"
        "<body>\n"
        "  <div class=\"card\">\n"
        "    <h1>⚡ UOS Instance 2 Distributed Node</h1>\n"
        "    <div class=\"item\"><span class=\"label\">Status:</span><span class=\"badge\">~s</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Instance ID:</span><span class=\"val\">~s</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Role:</span><span class=\"val\">~s</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Runtime:</span><span class=\"val\">~s</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">BEAM Node:</span><span class=\"val\">~s</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Peers Connected:</span><span class=\"val\">~p</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">GPU Acceleration:</span><span class=\"val\">~s</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Memory Usage:</span><span class=\"val\">~.2f MB</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Uptime:</span><span class=\"val\">~p seconds</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Timestamp:</span><span class=\"val\">~s</span></div>\n"
        "    <p style=\"margin-top:1.5rem;\"><a href=\"/health\" style=\"color:#58a6ff;\">/health JSON API</a> | <a href=\"/metrics\" style=\"color:#58a6ff;\">/metrics Prometheus</a></p>\n"
        "  </div>\n"
        "</body>\n"
        "</html>\n",
        [Status, InstId, InstRole, Runtime, NodeName, PeerCount, GpuDev, MemMb, Uptime, Ts]
    ).

render_metrics(StartTime) ->
    Now = erlang:system_time(second),
    Uptime = Now - StartTime,
    Memory = erlang:memory(total),
    Procs = erlang:system_info(process_count),
    Peers = length(nodes()),
    io_lib:format(
        "# HELP uos_uptime_seconds Process uptime in seconds\n"
        "# TYPE uos_uptime_seconds counter\n"
        "uos_uptime_seconds ~p\n"
        "# HELP uos_memory_bytes Total BEAM memory allocated\n"
        "# TYPE uos_memory_bytes gauge\n"
        "uos_memory_bytes ~p\n"
        "# HELP uos_process_count Total BEAM processes\n"
        "# TYPE uos_process_count gauge\n"
        "uos_process_count ~p\n"
        "# HELP uos_connected_peers Count of connected Erlang cluster peers\n"
        "# TYPE uos_connected_peers gauge\n"
        "uos_connected_peers ~p\n",
        [Uptime, Memory, Procs, Peers]
    ).

iso8601_now() ->
    calendar:system_time_to_rfc3339(erlang:system_time(second), [{offset, "Z"}]).

log_info(Format, Args) ->
    io:format("[~s] [INFO] [uos_instance2] " ++ Format ++ "~n", [iso8601_now() | Args]).

log_warn(Format, Args) ->
    io:format("[~s] [WARN] [uos_instance2] " ++ Format ++ "~n", [iso8601_now() | Args]).

log_error(Format, Args) ->
    io:format("[~s] [ERROR] [uos_instance2] " ++ Format ++ "~n", [iso8601_now() | Args]).
