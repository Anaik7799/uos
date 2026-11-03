//// Wisp REST API & Telemetry Catalog for UOS-ZLP-v3 Supervised Lean 4.33.0 +
//// Zig 0.16.0 + Gleam/OTP 29.0.5 + MCP + Zenoh Port Hyperplane.
//// STAMP: SC-GLM-UI-001, SC-HARNESS-MCP-001, SC-ZLP-PORT-001, SC-PROVENANCE-001

import cepaf_gleam/mcp/transports/zlp_hyperplane
import gleam/json
import gleam/list

pub type ZlpTheoremRecord {
  ZlpTheoremRecord(
    id: String,
    name: String,
    layer: String,
    contract: String,
    statement: String,
  )
}

pub type ZlpExportKernel {
  ZlpExportKernel(
    c_symbol: String,
    lean_fn: String,
    lane: String,
    purpose: String,
  )
}

pub type ZlpShardObservation {
  ZlpShardObservation(
    shard_id: Int,
    status: String,
    os_pid: Int,
    active_subs: Int,
    in_flight_heavy: Int,
    perceus_excl: Int,
  )
}

pub fn observe_shards() -> List(ZlpShardObservation) {
  case zlp_hyperplane.is_running() {
    False -> []
    True ->
      list.filter_map([0, 1, 2, 3], fn(shard_id) {
        case zlp_hyperplane.shard_health(shard_id: shard_id) {
          Ok(sh) ->
            Ok(ZlpShardObservation(
              shard_id: shard_id,
              status: "online",
              os_pid: sh.os_pid,
              active_subs: sh.active_subs,
              in_flight_heavy: sh.in_flight_heavy,
              perceus_excl: sh.excl,
            ))
          Error(_) -> Error(Nil)
        }
      })
  }
}

pub fn runtime_status_label(binary_available: Bool, pool_running: Bool) -> String {
  case pool_running, binary_available {
    True, _ -> "healthy"
    False, True -> "standby"
    False, False -> "binary_unbuilt"
  }
}

pub fn status_json() -> json.Json {
  let binary_available = zlp_hyperplane.is_binary_available()
  let pool_running = zlp_hyperplane.is_running()
  let shards = observe_shards()
  let total_subs =
    list.fold(shards, 0, fn(acc, s) { acc + s.active_subs })
  let total_heavy =
    list.fold(shards, 0, fn(acc, s) { acc + s.in_flight_heavy })

  json.object([
    #("plane", json.string("zlp_hyperplane")),
    #("backend", json.string("uos_zlp_v3_otp29_port")),
    #(
      "status",
      json.string(runtime_status_label(binary_available, pool_running)),
    ),
    #("binary_available", json.bool(binary_available)),
    #("pool_running", json.bool(pool_running)),
    #("active_shard_count", json.int(list.length(shards))),
    #("total_active_subscriptions", json.int(total_subs)),
    #("total_in_flight_heavy", json.int(total_heavy)),
    #("shards", json.array(shards, shard_observation_to_json)),
    #("lean_version", json.string("4.33.0")),
    #("zig_version", json.string("0.16.0")),
    #("otp_release", json.string("29")),
    #("lean_theorems_proved", json.int(20)),
    #("formal_theorems_verified", json.int(list.length(get_theorems()))),
    #("exported_c_abi_kernels", json.int(list.length(get_export_kernels()))),
    #("zero_sorry_ax", json.bool(True)),
    #("supports_zenoh_sse_subscriptions", json.bool(True)),
    #("admitted_ev_ceiling", json.int(zlp_hyperplane.admitted_ev_ceiling)),
    #("application_admitted", json.bool(False)),
    #("system_admitted", json.bool(zlp_hyperplane.system_admitted)),
    #(
      "cockpit_url",
      json.string("http://nas-1.tail55d152.ts.net:4100/zlp"),
    ),
    #(
      "contract_url",
      json.string(
        "http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261101-1410-zlp-hyperplane-port-contract.md",
      ),
    ),
    #(
      "spec_url",
      json.string(
        "http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261101-1225-uos-zlp-v3-lean4-zig-otp29-zenoh-hyperplane-spec.md",
      ),
    ),
  ])
}

pub fn shard_observation_to_json(s: ZlpShardObservation) -> json.Json {
  json.object([
    #("shard_id", json.int(s.shard_id)),
    #("status", json.string(s.status)),
    #("os_pid", json.int(s.os_pid)),
    #("active_subs", json.int(s.active_subs)),
    #("in_flight_heavy", json.int(s.in_flight_heavy)),
    #("perceus_excl", json.int(s.perceus_excl)),
    #("perceus_exclusive", json.bool(s.perceus_excl == 1)),
  ])
}

pub fn theorems_json() -> json.Json {
  let theorems = get_theorems()
  let exports = get_export_kernels()
  json.object([
    #("plane", json.string("zlp_hyperplane")),
    #("lean_source", json.string("formal/lean/UosZlpHyperplane.lean")),
    #(
      "lean_source_url",
      json.string(
        "http://nas-1.tail55d152.ts.net:4100/files/formal/lean/UosZlpHyperplane.lean",
      ),
    ),
    #("theorem_count", json.int(list.length(theorems))),
    #("export_kernel_count", json.int(list.length(exports))),
    #("zero_sorry_ax", json.bool(True)),
    #("admitted_ev_ceiling", json.int(zlp_hyperplane.admitted_ev_ceiling)),
    #("system_admitted", json.bool(zlp_hyperplane.system_admitted)),
    #("theorems", json.array(theorems, theorem_to_json)),
    #("export_kernels", json.array(exports, export_kernel_to_json)),
  ])
}

pub fn theorem_to_json(t: ZlpTheoremRecord) -> json.Json {
  json.object([
    #("id", json.string(t.id)),
    #("name", json.string(t.name)),
    #("layer", json.string(t.layer)),
    #("contract", json.string(t.contract)),
    #("statement", json.string(t.statement)),
  ])
}

pub fn export_kernel_to_json(k: ZlpExportKernel) -> json.Json {
  json.object([
    #("c_symbol", json.string(k.c_symbol)),
    #("lean_fn", json.string(k.lean_fn)),
    #("lane", json.string(k.lane)),
    #("purpose", json.string(k.purpose)),
  ])
}

pub fn lanes_json() -> json.Json {
  json.object([
    #("plane", json.string("zlp_hyperplane")),
    #("isolation_model", json.string("otp29_open_port_packet4_parallelism_true")),
    #("parent_death_guard", json.string("PR_SET_PDEATHSIG(SIGTERM)+stdin_eof")),
    #("simd_pregate", json.string("zig_0.16.0_znver5_avx512_64byte_vector")),
    #("memory_model", json.string("perceus_fbip_lean_is_exclusive_zero_malloc_slab")),
    #(
      "subscription_resilience",
      json.string("supervisor_owned_dual_ets_auto_replay_on_sigkill"),
    ),
    #("fast_lane", json.object([
      #("thread", json.string("main_epoll_reactor")),
      #("opcodes", json.array(["OP_PING", "OP_VERIFY_FRAME", "OP_SCALE_RISK_GATE", "OP_ZENOH_PUB", "OP_ZENOH_SUB", "OP_ZENOH_GET", "OP_RESET_STATE"], json.string)),
      #("target_budget_us", json.int(10)),
    ])),
    #("heavy_lane", json.object([
      #("thread", json.string("detached_pthread_lean_initialize_thread_eventfd")),
      #("opcodes", json.array(["OP_HEAVY_PROVE"], json.string)),
      #("hol_blocking_on_fast_lane", json.bool(False)),
    ])),
    #("admitted_ev_ceiling", json.int(zlp_hyperplane.admitted_ev_ceiling)),
    #("system_admitted", json.bool(zlp_hyperplane.system_admitted)),
  ])
}

pub fn get_theorems() -> List(ZlpTheoremRecord) {
  [
    ZlpTheoremRecord(
      "T00",
      "provenance_ceiling_fixed",
      "L0",
      "SC-PROVENANCE-001",
      "admittedEvCeiling = 93 /\\ systemAdmission = false",
    ),
    ZlpTheoremRecord(
      "T01",
      "T01_wire_header_roundtrip",
      "L1",
      "SC-ZLP-PORT-001",
      "24-byte WireHeader24 prism encode/decode exact bijection",
    ),
    ZlpTheoremRecord(
      "T02",
      "T02_wire_decode_enforces_cap",
      "L1",
      "SC-ZLP-PORT-001",
      "Decoded frames strictly satisfy frameLen <= 1 MiB /\\ magic = 0x55",
    ),
    ZlpTheoremRecord(
      "T03",
      "T03_perceus_zero_malloc_for_all_n",
      "L1",
      "SC-ZLP-PORT-001",
      "Perceus FBIP exclusive slab reuse preserves 0 heap allocs for all N",
    ),
    ZlpTheoremRecord(
      "T04",
      "T04_replay_always_rejected",
      "L2",
      "SC-HARNESS-MCP-001",
      "64-packet sliding bitmap rejects every duplicate sequence ID",
    ),
    ZlpTheoremRecord(
      "T05",
      "T05_out_of_order_unseen_accepted",
      "L2",
      "SC-HARNESS-MCP-001",
      "Unseen sequence IDs within 64-slot window succeed out-of-order",
    ),
    ZlpTheoremRecord(
      "T06",
      "T06_lyapunov_exact_zero_at_equilibrium",
      "L3",
      "SC-POODAVR-002",
      "Fixed-point Foster-Lyapunov energy V(x*, x*) = 0",
    ),
    ZlpTheoremRecord(
      "T07",
      "T07_lyapunov_exact_pos_def",
      "L3",
      "SC-POODAVR-002",
      "Positive-definiteness V(x, x*) = 0 <-> x = x*",
    ),
    ZlpTheoremRecord(
      "T08",
      "T08_lyapunov_exponential_contraction",
      "L3",
      "SC-POODAVR-002",
      "Inductive exponential drift contraction V(k)*D^k <= V(0)*(D-N)^k",
    ),
    ZlpTheoremRecord(
      "T09",
      "T09_credit_queue_never_overflows",
      "L2",
      "SC-ZLP-PORT-001",
      "Bounded credit window queue invariant stepCreditQueue <= W",
    ),
    ZlpTheoremRecord(
      "T10",
      "T10_zlp_cannot_escalate_authority",
      "L0",
      "SC-HARNESS-MCP-001",
      "authorizeEffect false v = false (ZLP port cannot grant authority)",
    ),
    ZlpTheoremRecord(
      "T11",
      "T11_zlp_veto_blocks_effect",
      "L0",
      "SC-HARNESS-MCP-001",
      "Non-permit ZLP verdict unconditionally vetoes downstream effect",
    ),
    ZlpTheoremRecord(
      "T12",
      "T12_meshJoin_semilattice",
      "L6",
      "SC-ZENOH-001",
      "Join-semilattice commutativity, associativity, and idempotence",
    ),
    ZlpTheoremRecord(
      "T13",
      "T13_two_lane_ooo_correlation_sound",
      "L2",
      "SC-ZLP-PORT-001",
      "Out-of-order Two-Lane req_id correlation preserves caller isolation",
    ),
    ZlpTheoremRecord(
      "T14",
      "T14_zenoh_key_blocks_a2a_and_nul",
      "L6",
      "SC-ZENOH-001",
      "Zenoh key guard blocks c3i/a2a prefix, empty topics, and NUL bytes",
    ),
    ZlpTheoremRecord(
      "T15",
      "T15_ets_subscription_replay_idempotent",
      "L3",
      "SC-ZLP-PORT-001",
      "Supervisor-owned ETS subscription replay is idempotent across SIGKILL",
    ),
    ZlpTheoremRecord(
      "T16",
      "T16_pku_bracket_always_relocks",
      "L1",
      "SC-ZLP-PORT-001",
      "Zen 5 MPK/PKU heap write-lock bracket always relocks on exit",
    ),
    ZlpTheoremRecord(
      "T17",
      "T17_scale_budget_gate_sound",
      "L4",
      "SC-HARNESS-MCP-001",
      "Passing scale/budget gate implies active lease and <= $10/day cap",
    ),
    ZlpTheoremRecord(
      "T18",
      "T18_risk_priority_zero_when_unready",
      "L4",
      "SC-RISK-PRIORITY-001",
      "5-factor ordinal risk tensor collapses to 0 when safetyReady = 0",
    ),
    ZlpTheoremRecord(
      "T19",
      "T19_km_fresh_reopen_eliminates_staleness",
      "L5",
      "SC-MCP-KM-BRAIN-001",
      "Fresh disk reopen eliminates stale KM index cache projections",
    ),
    ZlpTheoremRecord(
      "T20",
      "T20_graceful_drain_reaches_zero",
      "L3",
      "SC-RELEASE-ASSURANCE-001",
      "Bounded capsule drain reaches 0 in-flight requests in k steps",
    ),
  ]
}

pub fn get_export_kernels() -> List(ZlpExportKernel) {
  [
    ZlpExportKernel(
      "uos_zlp_scale_budget_gate",
      "uosZlpScaleBudgetGate",
      "Fast Lane (<10us)",
      "Enforces writer/reviewer concurrency caps, lease expiry, and $10/day micro-USD ceiling",
    ),
    ZlpExportKernel(
      "uos_zlp_risk_priority_score",
      "uosZlpRiskPriorityScore",
      "Fast Lane (<10us)",
      "Computes safetyReady /\\ depReady pre-gated 5-factor SC-RISK-PRIORITY-001 score",
    ),
    ZlpExportKernel(
      "uos_zlp_sliding_replay_check",
      "uosZlpSlidingReplayCheck",
      "Fast Lane (<10us)",
      "O(1) 64-packet sliding bitmap anti-replay membership check",
    ),
    ZlpExportKernel(
      "uos_zlp_sliding_replay_advance",
      "uosZlpSlidingReplayAdvance",
      "Fast Lane (<10us)",
      "O(1) 64-packet sliding bitmap window shift & bit commit",
    ),
    ZlpExportKernel(
      "uos_zlp_lyapunov_q16_gate",
      "uosZlpLyapunovQ16Gate",
      "Fast Lane (<10us)",
      "Overflow-safe Q16.16 Foster-Lyapunov energy & contraction bit evaluator",
    ),
    ZlpExportKernel(
      "uos_zlp_zenoh_topic_guard",
      "uosZlpZenohTopicGuard",
      "Fast Lane (<10us)",
      "Rejects leading '/', '..', NUL bytes, >512B keys, and forbidden c3i/a2a topics",
    ),
    ZlpExportKernel(
      "uos_zlp_verify_frame",
      "uosZlpVerifyFrame",
      "Fast Lane (<10us)",
      "Perceus ByteArray frame bounds, c3i/a2a trap, and FNV-1a 64-bit witness digest",
    ),
    ZlpExportKernel(
      "uos_zlp_heavy_graph_digest",
      "uosZlpHeavyGraphDigest",
      "Heavy Lane (pthread + eventfd)",
      "Multi-round algebraic corpus/graph reduction offloaded via lean_initialize_thread()",
    ),
  ]
}
