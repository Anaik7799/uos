-module(c3i_nif).
-export([
    %% Planning (7)
    plan_status/0, plan_list_pending/0, plan_list_by_status/1,
    plan_get_task/1, plan_add_task/2, plan_update_task/2, plan_search/1,
    %% System (5)
    system_health/0, system_dashboard/0, system_immune/0,
    system_zenoh/0, system_verification/0,
    %% Knowledge (1)
    knowledge_search/1,
    %% Verification (1)
    verification_run/0,
    %% Cortex & Operations (11)
    inference_status/0, trace_recent/1, conversation_history/1,
    cache_stats/0, fmea_report/0, ha_status/0, voice_status/0,
    ruliology_automaton/1, ruliology_multiway/0, ruliology_causal/0,
    ooda_phase/0,
    %% Zenoh Native (5) — SC-ZENOH-001
    zenoh_open/1, zenoh_put/2, zenoh_get/1, zenoh_status/0, zenoh_close/0
]).
-on_load(init/0).

init() ->
    SoPath = case code:priv_dir(cepaf_gleam) of
        {error, _} -> "priv/c3i_nif";
        PrivDir -> filename:join(PrivDir, "c3i_nif")
    end,
    case erlang:load_nif(SoPath, 0) of
        ok -> ok;
        {error, {reload, _}} -> ok;
        {error, Reason} ->
            io:format("[c3i_nif] NIF load failed: ~p (path: ~s)~n", [Reason, SoPath]),
            ok
    end.

%% NIF stubs — replaced by Rust at load time.
%% Planning
plan_status() -> <<"{\"active\":0,\"pending\":0,\"completed\":0,\"blocked\":0,\"total\":0}">>.
plan_list_pending() -> <<"[]">>.
plan_list_by_status(_Status) -> <<"[]">>.
plan_get_task(_Id) -> <<"{\"error\":\"NIF not loaded\"}">>.
plan_add_task(_Title, _Priority) -> <<"{\"ok\":false,\"error\":\"NIF not loaded\"}">>.
plan_update_task(_Id, _Status) -> <<"{\"ok\":false,\"error\":\"NIF not loaded\"}">>.
plan_search(_Query) -> <<"[]">>.
%% System
system_health() -> <<"{\"container_count\":0,\"healthy_count\":0,\"threat_level\":\"unknown\",\"zenoh_connected\":false}">>.
system_dashboard() -> <<"{\"page\":\"Dashboard\",\"status\":\"offline\",\"container_count\":0,\"healthy_count\":0,\"health_pct\":0.0}">>.
system_immune() -> <<"{\"page\":\"Immune System\",\"status\":\"offline\",\"threat_level\":\"unknown\"}">>.
system_zenoh() -> <<"{\"page\":\"Zenoh Mesh\",\"status\":\"offline\",\"connected\":false,\"routers\":0}">>.
system_verification() -> <<"{\"page\":\"Verification\",\"status\":\"offline\",\"tests_total\":0}">>.
%% Knowledge
knowledge_search(_Query) -> <<"{\"query\":\"\",\"results\":[],\"total\":0}">>.
%% Verification
verification_run() -> <<"{\"ok\":false,\"output\":\"NIF not loaded\",\"warnings\":0,\"errors\":1}">>.
%% Cortex & Operations
inference_status() -> <<"{\"tiers\":[],\"total_recent\":0}">>.
trace_recent(_N) -> <<"{\"traces\":[],\"count\":0}">>.
conversation_history(_N) -> <<"{\"messages\":[],\"count\":0}">>.
cache_stats() -> <<"{\"entries\":0,\"total\":0,\"expired\":0,\"hit_rate\":0.0}">>.
fmea_report() -> <<"{\"failure_modes\":[],\"total_failures\":0,\"failure_rate\":0.0}">>.
ha_status() -> <<"{\"role\":\"standby\",\"missed_heartbeats\":0,\"lease_ttl_ms\":0}">>.
voice_status() -> <<"{\"ws_connected\":false,\"active_tier\":\"none\",\"transcription_active\":false}">>.
ruliology_automaton(_Name) -> <<"{\"name\":\"unknown\",\"current\":\"unknown\",\"states\":[],\"step_count\":0}">>.
ruliology_multiway() -> <<"{\"nodes\":[],\"node_count\":0}">>.
ruliology_causal() -> <<"{\"nodes\":[],\"edges\":[],\"node_count\":0,\"edge_count\":0}">>.
ooda_phase() -> <<"{\"phase\":\"idle\",\"cycle_count\":0,\"target_ms\":100}">>.
%% Zenoh Native
zenoh_open(_ConfigJson) -> <<"{\"status\":\"error\",\"error\":\"zenoh_nif_not_loaded\"}">>.
zenoh_put(_Key, _Payload) -> <<"{\"status\":\"error\",\"error\":\"zenoh_nif_not_loaded\"}">>.
zenoh_get(_Key) -> <<"[]">>.
zenoh_status() -> <<"{\"connected\":false,\"endpoint\":\"none\"}">>.
zenoh_close() -> <<"{\"status\":\"closed\"}">>.
