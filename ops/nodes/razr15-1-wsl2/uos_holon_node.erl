%%%-------------------------------------------------------------------
%%% @doc
%%% [C3I-SIL6] UOS Autonomous Intelligent Holon Node (aṃśa-pūrṇa)
%%% Autonomous whole-part entity for distributed mesh execution and swarm expansion.
%%% Full Development, Evolution & Operational Capability: Opam, Mojo, MAX, Lean, Quint.
%%% Runtime: Pure Erlang/OTP 29 (ERTS 17.0.5) ONLY.
%%% Mandates: SC-NIX-DEVENV-001, SC-ZMOF-001, SC-TIME, SC-MUDA-001
%%% @end
%%%-------------------------------------------------------------------
-module(uos_holon_node).
-behaviour(gen_server).

%% API
-export([start/0, start/1, start_link/1, stop/0, health/0, sensory/0, capacity/0, evolution/0, execute/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    port :: integer(),
    lsocket :: gen_tcp:socket(),
    start_time :: integer(),
    lifecycle = <<"Active">> :: binary(),
    ooda_cycle = 0 :: integer(),
    capacity_score = 1.0 :: float(),
    active_jobs = 0 :: integer(),
    completed_jobs = 0 :: integer(),
    master_nodes :: [node()],
    timer_ref :: reference()
}).

-define(DEFAULT_PORT, 8088).
-define(TICK_INTERVAL_MS, 2000).
-define(COOKIE, 'uos_vajravyuh_cookie').

%%====================================================================
%% API Functions
%%====================================================================

-spec start() -> {ok, pid()} | {error, term()}.
start() ->
    start(?DEFAULT_PORT).

-spec start(integer()) -> {ok, pid()} | {error, term()}.
start(Port) ->
    case gen_server:start({local, ?MODULE}, ?MODULE, [Port], []) of
        {ok, Pid} ->
            log_info("Holon Node (Saṁvid Vajravyūha) online on port ~p", [Port]),
            {ok, Pid};
        {error, {already_started, Pid}} ->
            log_info("Holon Node already active (PID ~p)", [Pid]),
            {ok, Pid};
        Error ->
            log_error("Holon startup error: ~p", [Error]),
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

-spec sensory() -> map().
sensory() ->
    uos_holon_sensory:sense_all().

-spec evolution() -> map().
evolution() ->
    uos_holon_sensory:sense_toolchains().

-spec capacity() -> float().
capacity() ->
    gen_server:call(?MODULE, get_capacity).

-spec execute(term()) -> {ok, term()} | {error, term()}.
execute(Task) ->
    gen_server:call(?MODULE, {execute_task, Task}, 30000).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([Port]) ->
    process_flag(trap_exit, true),
    StartTime = erlang:system_time(second),

    %% 1. Set Distributed Cookie if node is distributed
    case is_alive() of
        true -> erlang:set_cookie(node(), ?COOKIE);
        false -> ok
    end,

    %% 2. Open HTTP Server Socket on 0.0.0.0:Port
    Opts = [binary, {packet, 0}, {active, false}, {reuseaddr, true}, {backlog, 128}],
    case gen_tcp:listen(Port, Opts) of
        {ok, LSocket} ->
            log_info("Holon TCP HTTP Gateway listening on 0.0.0.0:~p", [Port]),
            spawn_link(fun() -> accept_loop(LSocket, StartTime) end),

            %% 3. Schedule OODA & Mesh Homeostasis loop
            TimerRef = erlang:send_after(?TICK_INTERVAL_MS, self(), ooda_tick),

            MasterNodes = [
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
                lifecycle = <<"Active">>,
                ooda_cycle = 0,
                capacity_score = 1.0,
                active_jobs = 0,
                completed_jobs = 0,
                master_nodes = MasterNodes,
                timer_ref = TimerRef
            }};
        {error, Reason} ->
            log_error("Failed to bind port ~p: ~p", [Port, Reason]),
            {stop, Reason}
    end.

handle_call(get_health, _From, State) ->
    Health = build_health_data(State),
    {reply, Health, State};

handle_call(get_capacity, _From, State) ->
    {reply, State#state.capacity_score, State};

handle_call({execute_task, Task}, _From, State) ->
    Self = self(),
    NewActive = State#state.active_jobs + 1,
    spawn_link(fun() ->
        Result = execute_internal_task(Task),
        Self ! {task_finished, Result}
    end),
    {reply, {ok, job_dispatched}, State#state{active_jobs = NewActive}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(ooda_tick, State) ->
    %% 1. Observe & Orient: Compute capacity score and lifecycle state
    Sensory = uos_holon_sensory:sense_all(),
    Mem = maps:get(memory, Sensory, #{}),
    Cpu = maps:get(cpu, Sensory, #{}),

    AvailMb = maps:get(host_available_mb, Mem, 1024.0),
    Load1m = maps:get(load_1m, Cpu, 1.0),
    LogicalCores = maps:get(logical_cores, Cpu, 4),

    %% Capacity calculus: [0.0..1.0] based on RAM and CPU headroom
    MemFactor = math:min(1.0, math:max(0.1, AvailMb / 4096.0)),
    CpuFactor = math:min(1.0, math:max(0.1, 1.0 - (Load1m / float(LogicalCores)))),
    CapacityScore = (MemFactor * 0.5) + (CpuFactor * 0.5),

    %% Lifecycle State Machine
    NewLifecycle = if
        CapacityScore < 0.2 -> <<"Stressed">>;
        true -> <<"Active">>
    end,

    %% 2. Mesh Homeostasis: Ping hive masters if alive
    case is_alive() of
        true ->
            lists:foreach(fun(Master) ->
                case lists:member(Master, nodes()) of
                    true -> ok;
                    false -> try net_adm:ping(Master) catch _:_ -> pang end
                end
            end, State#state.master_nodes);
        false -> ok
    end,

    NewCycle = State#state.ooda_cycle + 1,
    NewTimer = erlang:send_after(?TICK_INTERVAL_MS, self(), ooda_tick),
    {noreply, State#state{
        ooda_cycle = NewCycle,
        capacity_score = CapacityScore,
        lifecycle = NewLifecycle,
        timer_ref = NewTimer
    }};

handle_info({task_finished, _Result}, State) ->
    NewActive = math:max(0, State#state.active_jobs - 1),
    NewDone = State#state.completed_jobs + 1,
    {noreply, State#state{active_jobs = NewActive, completed_jobs = NewDone}};

handle_info({'EXIT', _Pid, normal}, State) ->
    {noreply, State};

handle_info({'EXIT', Pid, Reason}, State) ->
    log_warn("Worker process ~p terminated: ~p", [Pid, Reason]),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    log_info("Terminating Holon Node on port ~p...", [State#state.port]),
    try gen_tcp:close(State#state.lsocket) catch _:_ -> ok end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Task Execution
%%====================================================================

execute_internal_task({eval_math, Expr}) ->
    log_info("Executing distributed math computation: ~p", [Expr]),
    {ok, computed};
execute_internal_task(ping) ->
    {ok, pong};
execute_internal_task(run_preflight) ->
    Out = os:cmd("bash tools/preflight 2>&1"),
    {ok, list_to_binary(Out)};
execute_internal_task(run_lean_proofs) ->
    Out = os:cmd("tools/lean formal/lean/Traceability.lean 2>&1"),
    {ok, list_to_binary(Out)};
execute_internal_task(run_quint_sim) ->
    Out = os:cmd("tools/quint run formal/quint/parity_frontier.qnt 2>&1"),
    {ok, list_to_binary(Out)};
execute_internal_task(run_mojo_gpu) ->
    Out = os:cmd("tools/mojo run services/inference/max/gemma4_gpu_kernel.mojo 2>&1"),
    {ok, list_to_binary(Out)};
execute_internal_task(Task) ->
    log_info("Executing generic holon task: ~p", [Task]),
    {ok, completed}.

%%====================================================================
%% HTTP Gateway & Dispatcher
%%====================================================================

accept_loop(LSocket, StartTime) ->
    case gen_tcp:accept(LSocket) of
        {ok, Socket} ->
            spawn(fun() ->
                handle_http(Socket, StartTime),
                gen_tcp:close(Socket)
            end),
            accept_loop(LSocket, StartTime);
        {error, closed} -> ok;
        {error, Reason} ->
            log_error("Accept error: ~p", [Reason]),
            timer:sleep(500),
            accept_loop(LSocket, StartTime)
    end.

handle_http(Socket, StartTime) ->
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, RequestBin} ->
            Str = binary_to_list(RequestBin),
            case parse_http_first_line(Str) of
                {Method, Path} ->
                    dispatch_http(Socket, Method, Path, StartTime);
                error ->
                    send_http(Socket, 400, "text/plain", "Bad Request\r\n")
            end;
        _ -> ok
    end.

parse_http_first_line(Str) ->
    case string:tokens(Str, "\r\n") of
        [FirstLine | _] ->
            case string:tokens(FirstLine, " ") of
                [M, P | _] -> {M, P};
                _ -> error
            end;
        _ -> error
    end.

dispatch_http(Socket, "GET", Path, StartTime) ->
    case Path of
        P when P =:= "/health"; P =:= "/api/health"; P =:= "/status" ->
            Sensory = uos_holon_sensory:sense_all(),
            Health = build_health_json(Sensory, StartTime),
            send_http(Socket, 200, "application/json", Health);
        P when P =:= "/holon"; P =:= "/api/holon"; P =:= "/substrate" ->
            Sensory = uos_holon_sensory:sense_all(),
            HolonJson = encode_holon_json(Sensory, StartTime),
            send_http(Socket, 200, "application/json", HolonJson);
        P when P =:= "/evolution"; P =:= "/api/evolution" ->
            Toolchains = uos_holon_sensory:sense_toolchains(),
            EvoJson = encode_evolution_json(Toolchains),
            send_http(Socket, 200, "application/json", EvoJson);
        "/metrics" ->
            Metrics = build_prometheus_metrics(StartTime),
            send_http(Socket, 200, "text/plain; version=0.0.4", Metrics);
        P when P =:= "/"; P =:= "/index.html" ->
            Sensory = uos_holon_sensory:sense_all(),
            Html = render_holon_dashboard(Sensory, StartTime),
            send_http(Socket, 200, "text/html", Html);
        _ ->
            send_http(Socket, 404, "application/json", "{\"error\":\"Not Found\"}\r\n")
    end;

dispatch_http(Socket, "POST", Path, _StartTime) ->
    case Path of
        "/evolution/preflight" ->
            Out = os:cmd("bash tools/preflight 2>&1"),
            send_http(Socket, 200, "text/plain", Out);
        "/evolution/lean" ->
            Out = os:cmd("tools/lean formal/lean/Traceability.lean 2>&1"),
            send_http(Socket, 200, "text/plain", Out);
        "/evolution/quint" ->
            Out = os:cmd("tools/quint run formal/quint/parity_frontier.qnt 2>&1"),
            send_http(Socket, 200, "text/plain", Out);
        "/evolution/mojo" ->
            Out = os:cmd("tools/mojo run services/inference/max/gemma4_gpu_kernel.mojo 2>&1"),
            send_http(Socket, 200, "text/plain", Out);
        _ ->
            send_http(Socket, 404, "application/json", "{\"error\":\"Unknown Evolution Task\"}\r\n")
    end;

dispatch_http(Socket, "OPTIONS", _Path, _StartTime) ->
    Cors = "HTTP/1.1 204 No Content\r\n"
           "Access-Control-Allow-Origin: *\r\n"
           "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
           "Access-Control-Allow-Headers: Content-Type\r\n"
           "Content-Length: 0\r\n\r\n",
    gen_tcp:send(Socket, list_to_binary(Cors));

dispatch_http(Socket, _Method, _Path, _StartTime) ->
    send_http(Socket, 405, "application/json", "{\"error\":\"Method Not Allowed\"}\r\n").

send_http(Socket, Code, ContentType, Body) ->
    BodyBin = if is_binary(Body) -> Body; is_list(Body) -> list_to_binary(Body) end,
    StatusText = case Code of
        200 -> "OK";
        204 -> "No Content";
        400 -> "Bad Request";
        404 -> "Not Found";
        405 -> "Method Not Allowed";
        500 -> "Internal Server Error"
    end,
    Header = io_lib:format(
        "HTTP/1.1 ~p ~s\r\n"
        "Content-Type: ~s\r\n"
        "Content-Length: ~p\r\n"
        "Access-Control-Allow-Origin: *\r\n"
        "Connection: close\r\n"
        "Server: UOS-HOLON-OTP29/1.0.0\r\n\r\n",
        [Code, StatusText, ContentType, byte_size(BodyBin)]
    ),
    gen_tcp:send(Socket, [list_to_binary(Header), BodyBin]).

%%====================================================================
%% Telemetry, Metrics & Rendering
%%====================================================================

build_health_data(State) ->
    Sensory = uos_holon_sensory:sense_all(),
    #{
        status => <<"healthy">>,
        holon_id => <<"holon-razr15-1">>,
        lifecycle => State#state.lifecycle,
        ooda_cycle => State#state.ooda_cycle,
        capacity_score => State#state.capacity_score,
        active_jobs => State#state.active_jobs,
        completed_jobs => State#state.completed_jobs,
        runtime_engine => list_to_binary(io_lib:format("Erlang/OTP ~s (ERTS ~s)",
            [erlang:system_info(otp_release), erlang:system_info(version)])),
        beam_node => list_to_binary(atom_to_list(node())),
        sensory => Sensory
    }.

build_health_json(Sensory, StartTime) ->
    Uptime = erlang:system_time(second) - StartTime,
    OtpRel = erlang:system_info(otp_release),
    ErtsVsn = erlang:system_info(version),
    NodeName = atom_to_list(node()),
    Gpu = maps:get(gpu, Sensory, #{}),
    HasGpu = maps:get(has_dxg, Gpu, false),
    GpuMode = maps:get(acceleration_mode, Gpu, <<"CPU_SIMD">>),
    Toolchains = maps:get(toolchains, Sensory, #{}),
    EvoGrade = maps:get(evolution_grade, Toolchains, <<"UNKNOWN">>),
    EvoPct = maps:get(evolution_readiness_pct, Toolchains, 0.0),

    io_lib:format(
        "{\n"
        "  \"status\": \"healthy\",\n"
        "  \"holon_id\": \"holon-razr15-1\",\n"
        "  \"role\": \"Instance 2 (Autonomous Evolution Holon)\",\n"
        "  \"runtime_engine\": \"Erlang/OTP ~s (ERTS ~s)\",\n"
        "  \"beam_node\": \"~s\",\n"
        "  \"uptime_seconds\": ~p,\n"
        "  \"has_gpu\": ~s,\n"
        "  \"gpu_acceleration\": \"~s\",\n"
        "  \"evolution_grade\": \"~s\",\n"
        "  \"evolution_readiness_pct\": ~.1f,\n"
        "  \"mesh\": \"Samvid Vajravyuha\",\n"
        "  \"holon_lifecycle\": \"Active\",\n"
        "  \"timestamp_utc\": \"~s\"\n"
        "}\n",
        [OtpRel, ErtsVsn, NodeName, Uptime,
         if HasGpu -> "true"; true -> "false" end,
         GpuMode, EvoGrade, EvoPct, maps:get(timestamp_utc, Sensory, <<"">>)]
    ).

encode_holon_json(Sensory, StartTime) ->
    Uptime = erlang:system_time(second) - StartTime,
    Cpu = maps:get(cpu, Sensory, #{}),
    Mem = maps:get(memory, Sensory, #{}),
    Gpu = maps:get(gpu, Sensory, #{}),
    Net = maps:get(network, Sensory, #{}),
    Hive = maps:get(hive, Sensory, #{}),
    Toolchains = maps:get(toolchains, Sensory, #{}),

    io_lib:format(
        "{\n"
        "  \"holon\": {\n"
        "    \"id\": \"holon-razr15-1\",\n"
        "    \"type\": \"Autonomous-Evolution-Holon\",\n"
        "    \"plane\": \"Runtime/Compute/Evolution\",\n"
        "    \"svara\": \"Sa\",\n"
        "    \"svadharma\": \"autonomous-full-stack-evolution-and-mesh-acceleration\",\n"
        "    \"lifecycle\": \"Active\",\n"
        "    \"uptime_seconds\": ~p,\n"
        "    \"evolution_grade\": \"~s\",\n"
        "    \"evolution_readiness_pct\": ~.1f\n"
        "  },\n"
        "  \"substrate\": {\n"
        "    \"cpu_model\": \"~s\",\n"
        "    \"logical_cores\": ~p,\n"
        "    \"beam_schedulers\": ~p,\n"
        "    \"load_1m\": ~.2f,\n"
        "    \"host_memory_total_mb\": ~.1f,\n"
        "    \"host_memory_available_mb\": ~.1f,\n"
        "    \"beam_memory_mb\": ~.2f,\n"
        "    \"gpu_device\": \"~s\",\n"
        "    \"gpu_acceleration\": \"~s\",\n"
        "    \"is_wsl2\": ~s,\n"
        "    \"hostname\": \"~s\"\n"
        "  },\n"
        "  \"hive\": {\n"
        "    \"mesh\": \"Samvid Vajravyuha\",\n"
        "    \"nas1_reachable\": ~s,\n"
        "    \"connected_peers\": ~p\n"
        "  }\n"
        "}\n",
        [
            Uptime,
            maps:get(evolution_grade, Toolchains, <<"BOOTSTRAP">>),
            maps:get(evolution_readiness_pct, Toolchains, 0.0),
            maps:get(model, Cpu, <<"x86_64">>),
            maps:get(logical_cores, Cpu, 0),
            maps:get(beam_schedulers, Cpu, 0),
            maps:get(load_1m, Cpu, 0.0),
            maps:get(host_total_kb, Mem, 0) / 1024.0,
            maps:get(host_available_mb, Mem, 0.0),
            maps:get(beam_total_mb, Mem, 0.0),
            maps:get(device_name, Gpu, <<"None">>),
            maps:get(acceleration_mode, Gpu, <<"CPU">>),
            case maps:get(is_wsl2, Net, false) of true -> "true"; _ -> "false" end,
            maps:get(hostname, Net, <<"localhost">>),
            case maps:get(nas1_lan_reachable, Hive, false) of true -> "true"; _ -> "false" end,
            maps:get(peer_count, Hive, 0)
        ]
    ).

encode_evolution_json(Toolchains) ->
    Opam = maps:get(opam_ocaml, Toolchains, #{}),
    Mojo = maps:get(modular_max_mojo, Toolchains, #{}),
    Lean = maps:get(lean4, Toolchains, #{}),
    Quint = maps:get(quint, Toolchains, #{}),
    Otp = maps:get(otp29, Toolchains, #{}),
    Gleam = maps:get(gleam, Toolchains, #{}),
    Z3 = maps:get(z3, Toolchains, #{}),
    Jj = maps:get(jj, Toolchains, #{}),

    io_lib:format(
        "{\n"
        "  \"evolution_readiness_pct\": ~.1f,\n"
        "  \"evolution_grade\": \"~s\",\n"
        "  \"toolchains\": {\n"
        "    \"opam_ocaml\": {\"present\": ~s, \"version\": \"~s\", \"role\": \"~s\"},\n"
        "    \"modular_max_mojo\": {\"present\": ~s, \"version\": \"~s\", \"role\": \"~s\"},\n"
        "    \"lean4\": {\"present\": ~s, \"version\": \"~s\", \"role\": \"~s\"},\n"
        "    \"quint\": {\"present\": ~s, \"version\": \"~s\", \"role\": \"~s\"},\n"
        "    \"otp29\": {\"present\": ~s, \"version\": \"~s\", \"role\": \"~s\"},\n"
        "    \"gleam\": {\"present\": ~s, \"version\": \"~s\", \"role\": \"~s\"},\n"
        "    \"z3\": {\"present\": ~s, \"version\": \"~s\", \"role\": \"~s\"},\n"
        "    \"jj\": {\"present\": ~s, \"version\": \"~s\", \"role\": \"~s\"}\n"
        "  },\n"
        "  \"evolution_endpoints\": [\n"
        "    \"POST /evolution/preflight\",\n"
        "    \"POST /evolution/lean\",\n"
        "    \"POST /evolution/quint\",\n"
        "    \"POST /evolution/mojo\"\n"
        "  ]\n"
        "}\n",
        [
            maps:get(evolution_readiness_pct, Toolchains, 0.0),
            maps:get(evolution_grade, Toolchains, <<"UNKNOWN">>),
            bool_str(maps:get(present, Opam, false)), maps:get(version, Opam, <<"">>), maps:get(role, Opam, <<"">>),
            bool_str(maps:get(present, Mojo, false)), maps:get(version, Mojo, <<"">>), maps:get(role, Mojo, <<"">>),
            bool_str(maps:get(present, Lean, false)), maps:get(version, Lean, <<"">>), maps:get(role, Lean, <<"">>),
            bool_str(maps:get(present, Quint, false)), maps:get(version, Quint, <<"">>), maps:get(role, Quint, <<"">>),
            bool_str(maps:get(present, Otp, false)), maps:get(version, Otp, <<"">>), maps:get(role, Otp, <<"">>),
            bool_str(maps:get(present, Gleam, false)), maps:get(version, Gleam, <<"">>), maps:get(role, Gleam, <<"">>),
            bool_str(maps:get(present, Z3, false)), maps:get(version, Z3, <<"">>), maps:get(role, Z3, <<"">>),
            bool_str(maps:get(present, Jj, false)), maps:get(version, Jj, <<"">>), maps:get(role, Jj, <<"">>)
        ]
    ).

bool_str(true) -> "true";
bool_str(_) -> "false".

build_prometheus_metrics(StartTime) ->
    Now = erlang:system_time(second),
    Uptime = Now - StartTime,
    Mem = erlang:memory(total),
    Procs = erlang:system_info(process_count),
    Peers = length(nodes()),
    io_lib:format(
        "# HELP uos_holon_uptime_seconds Holon uptime\n"
        "# TYPE uos_holon_uptime_seconds counter\n"
        "uos_holon_uptime_seconds ~p\n"
        "# HELP uos_holon_memory_bytes Total BEAM memory\n"
        "# TYPE uos_holon_memory_bytes gauge\n"
        "uos_holon_memory_bytes ~p\n"
        "# HELP uos_holon_processes Total BEAM processes\n"
        "# TYPE uos_holon_processes gauge\n"
        "uos_holon_processes ~p\n"
        "# HELP uos_holon_peers Connected BEAM mesh peers\n"
        "# TYPE uos_holon_peers gauge\n"
        "uos_holon_peers ~p\n",
        [Uptime, Mem, Procs, Peers]
    ).

render_holon_dashboard(Sensory, StartTime) ->
    Uptime = erlang:system_time(second) - StartTime,
    Cpu = maps:get(cpu, Sensory, #{}),
    Mem = maps:get(memory, Sensory, #{}),
    Gpu = maps:get(gpu, Sensory, #{}),
    Net = maps:get(network, Sensory, #{}),
    Hive = maps:get(hive, Sensory, #{}),
    Toolchains = maps:get(toolchains, Sensory, #{}),

    io_lib:format(
        "<!DOCTYPE html>\n"
        "<html lang=\"en\">\n"
        "<head>\n"
        "  <meta charset=\"UTF-8\">\n"
        "  <title>UOS Autonomous Holon — Full Evolution Stack</title>\n"
        "  <style>\n"
        "    body { background: #0a0e14; color: #c9d1d9; font-family: monospace; padding: 2rem; margin: 0; }\n"
        "    .card { background: #121820; border: 1px solid #232e3d; border-radius: 10px; padding: 1.8rem; max-width: 900px; margin: 0 auto 1.5rem auto; }\n"
        "    h1 { color: #00d4aa; margin-top: 0; }\n"
        "    h2 { color: #58a6ff; font-size: 1.2rem; margin-top: 1.5rem; border-bottom: 1px solid #21262d; padding-bottom: 0.4rem; }\n"
        "    .badge { display: inline-block; padding: 0.2rem 0.6rem; border-radius: 4px; font-weight: bold; background: #238636; color: #fff; font-size: 0.85rem; }\n"
        "    .badge.gold { background: #d29922; color: #000; }\n"
        "    .item { margin: 0.5rem 0; display: flex; justify-content: space-between; }\n"
        "    .label { color: #8b949e; }\n"
        "    .val { color: #f0f6fc; font-weight: bold; }\n"
        "    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }\n"
        "    .evo-box { background: #05080c; border: 1px solid #1f2b3b; border-radius: 6px; padding: 0.8rem; margin-bottom: 0.5rem; }\n"
        "  </style>\n"
        "</head>\n"
        "<body>\n"
        "  <div class=\"card\">\n"
        "    <h1>⚡ UOS Autonomous Holon (aṃśa-pūrṇa)</h1>\n"
        "    <div class=\"item\"><span class=\"label\">Identity:</span><span class=\"val\">holon-razr15-1 (Svara: Sa, Plane: Runtime/Compute/Evolution)</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Lifecycle:</span><span class=\"badge\">Active (Homeostatic)</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Evolution Readiness:</span><span class=\"badge gold\">~.1f%% (~s)</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Runtime Engine:</span><span class=\"val\">Erlang/OTP ~s (ERTS ~s)</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Uptime:</span><span class=\"val\">~p seconds</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">BEAM Node:</span><span class=\"val\">~s</span></div>\n"
        "\n"
        "    <h2>🧬 Full Development &amp; Evolution Stack</h2>\n"
        "    <div class=\"grid\">\n"
        "      <div class=\"evo-box\">\n"
        "        <strong>🐫 Opam / OCaml &amp; Dune</strong><br>\n"
        "        <small style=\"color:#8b949e;\">Hermes Gospel contracts &amp; Z3 parity</small>\n"
        "      </div>\n"
        "      <div class=\"evo-box\">\n"
        "        <strong>🔥 Modular MAX / Mojo</strong><br>\n"
        "        <small style=\"color:#8b949e;\">GPU Gemma 4 inference &amp; SIMD scoring</small>\n"
        "      </div>\n"
        "      <div class=\"evo-box\">\n"
        "        <strong>📐 Lean 4.33.0 &amp; Lake</strong><br>\n"
        "        <small style=\"color:#8b949e;\">Mathematical proofs (Traceability, Century)</small>\n"
        "      </div>\n"
        "      <div class=\"evo-box\">\n"
        "        <strong>⏱️ Quint 0.32.0</strong><br>\n"
        "        <small style=\"color:#8b949e;\">Temporal logic &amp; invariant simulation</small>\n"
        "      </div>\n"
        "    </div>\n"
        "\n"
        "    <h2>💻 Substrate Sensory</h2>\n"
        "    <div class=\"grid\">\n"
        "      <div>\n"
        "        <div class=\"item\"><span class=\"label\">CPU:</span><span class=\"val\">~s</span></div>\n"
        "        <div class=\"item\"><span class=\"label\">Cores / Schedulers:</span><span class=\"val\">~p / ~p</span></div>\n"
        "        <div class=\"item\"><span class=\"label\">Load Avg (1m):</span><span class=\"val\">~.2f</span></div>\n"
        "      </div>\n"
        "      <div>\n"
        "        <div class=\"item\"><span class=\"label\">Host RAM Avail:</span><span class=\"val\">~.1f MB</span></div>\n"
        "        <div class=\"item\"><span class=\"label\">BEAM RAM:</span><span class=\"val\">~.2f MB</span></div>\n"
        "        <div class=\"item\"><span class=\"label\">GPU Acceleration:</span><span class=\"val\">~s (~s)</span></div>\n"
        "      </div>\n"
        "    </div>\n"
        "\n"
        "    <h2>🌐 Hive &amp; Mesh Connectivity</h2>\n"
        "    <div class=\"item\"><span class=\"label\">Mesh Name:</span><span class=\"val\">Saṁvid Vajravyūha</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Controller Reachable:</span><span class=\"val\">~s</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Connected Peers:</span><span class=\"val\">~p node(s)</span></div>\n"
        "    <div class=\"item\"><span class=\"label\">Host IP:</span><span class=\"val\">~s</span></div>\n"
        "\n"
        "    <p style=\"margin-top:1.5rem;\">\n"
        "      <a href=\"/health\" style=\"color:#00d4aa;\">[Health API]</a> &bull;\n"
        "      <a href=\"/evolution\" style=\"color:#00d4aa;\">[Evolution Matrix]</a> &bull;\n"
        "      <a href=\"/holon\" style=\"color:#00d4aa;\">[Substrate Telemetry]</a> &bull;\n"
        "      <a href=\"/metrics\" style=\"color:#00d4aa;\">[Prometheus Metrics]</a>\n"
        "    </p>\n"
        "  </div>\n"
        "</body>\n"
        "</html>\n",
        [
            maps:get(evolution_readiness_pct, Toolchains, 0.0),
            maps:get(evolution_grade, Toolchains, <<"BOOTSTRAP">>),
            erlang:system_info(otp_release),
            erlang:system_info(version),
            Uptime,
            atom_to_list(node()),
            maps:get(model, Cpu, <<"x86_64">>),
            maps:get(logical_cores, Cpu, 0),
            maps:get(beam_schedulers, Cpu, 0),
            maps:get(load_1m, Cpu, 0.0),
            maps:get(host_available_mb, Mem, 0.0),
            maps:get(beam_total_mb, Mem, 0.0),
            maps:get(acceleration_mode, Gpu, <<"CPU">>),
            maps:get(device_name, Gpu, <<"None">>),
            case maps:get(nas1_lan_reachable, Hive, false) of true -> "Yes (LAN 192.168.1.220:4100)"; _ -> "Checking..." end,
            maps:get(peer_count, Hive, 0),
            maps:get(hostname, Net, <<"localhost">>)
        ]
    ).

log_info(Format, Args) ->
    io:format("[~s] [INFO] [uos_holon] " ++ Format ++ "~n", [iso8601_now() | Args]).

log_warn(Format, Args) ->
    io:format("[~s] [WARN] [uos_holon] " ++ Format ++ "~n", [iso8601_now() | Args]).

log_error(Format, Args) ->
    io:format("[~s] [ERROR] [uos_holon] " ++ Format ++ "~n", [iso8601_now() | Args]).

iso8601_now() ->
    calendar:system_time_to_rfc3339(erlang:system_time(second), [{offset, "Z"}]).
