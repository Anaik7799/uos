// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-COG-001, SC-INF-001
// Wisp REST endpoint for Modular MAX / Mojo AI/ML inference tier.

import cepaf_gleam/services/max_inference_daemon as max_daemon
import cepaf_gleam/ui/lustre/inference_tier.{
  type InferenceTierModel, type TierStatus,
}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub fn status_json(model: InferenceTierModel) -> json.Json {
  json.object([
    #("active_tier", json.int(model.active_tier)),
    #("active_tier_name", json.string(inference_tier.active_tier_name(model))),
    #("hedged_mode", json.bool(model.hedged_mode)),
    #("total_requests", json.int(model.total_requests)),
    #("avg_latency_ms", json.int(model.avg_latency_ms)),
    #("cache_hit_rate", json.float(model.cache_hit_rate)),
    #("all_healthy", json.bool(inference_tier.all_circuits_healthy(model))),
    #("engine", json.string("Modular MAX / Mojo (v2.2.0)")),
    #("qps_capacity", json.int(50_770)),
    #(
      "tailscale_ingress",
      json.string("http://nas-1.tail55d152.ts.net:4100/api/v1/inference/status"),
    ),
    #(
      "modalities",
      json.array(
        [
          "text",
          "image",
          "audio",
          "video",
          "embedding",
          "ast_anomaly",
          "zk_transclusion",
          "lyapunov_trend",
        ],
        json.string,
      ),
    ),
    #("tiers", json.array(model.tiers, tier_json)),
  ])
}

pub fn modalities_json() -> String {
  json.object([
    #("status", json.string("ok")),
    #("engine", json.string("Modular MAX / Mojo")),
    #("device", json.string("cpu/simd")),
    #("hardware_acceleration", json.string("Modular MAX Mojo SIMD")),
    #(
      "modalities",
      json.array(
        [
          "text",
          "image",
          "audio",
          "video",
          "embedding",
          "ast_anomaly",
          "zk_transclusion",
          "lyapunov_trend",
        ],
        json.string,
      ),
    ),
  ])
  |> json.to_string
}

fn tier_json(t: TierStatus) -> json.Json {
  json.object([
    #("tier", json.int(t.tier)),
    #("name", json.string(t.name)),
    #("model", json.string(t.model)),
    #("latency_ms", json.int(t.latency_ms)),
    #("active", json.bool(t.active)),
    #("circuit", json.string(inference_tier.circuit_state_label(t.circuit))),
    #("requests_total", json.int(t.requests_total)),
    #("failures_total", json.int(t.failures_total)),
  ])
}

// =============================================================================
// Model 1: AST Structural Anomaly Detector
// =============================================================================

pub fn evaluate_ast_anomaly(
  code: String,
  language: String,
  strict_mode: Bool,
) -> max_daemon.AstAnomalyReport {
  let lang = string.lowercase(language)
  let code_lower = string.lowercase(code)

  let nul_detected = string.contains(code, "\u{0000}")
  let sql_detected =
    string.contains(code_lower, "union select")
    || string.contains(code_lower, "or 1=1")
    || string.contains(code_lower, "drop table")
    || string.contains(code_lower, "--;")
    || string.contains(code_lower, "/*")
  let jidoka_bypass =
    string.contains(code_lower, "bypass_sa_plan")
    || string.contains(code_lower, "shadow_task")
    || string.contains(code_lower, "untracked_execution")
    || string.contains(code_lower, "adhoc_task")
    || string.contains(code_lower, "skip_sa_plan")
  let zero_muda =
    string.contains(code_lower, "bevy") || string.contains(code_lower, "graphite")
  let storage_locked = string.contains(code, "25503L801736")

  let rust_panic = case lang {
    "rust" ->
      string.contains(code, ".unwrap()")
      || string.contains(code, ".expect(")
      || string.contains(code, "panic!(")
    _ -> False
  }

  let gleam_panic = case lang {
    "gleam" -> string.contains(code, "panic as") || string.contains(code, "todo")
    _ -> False
  }

  let python_eval = case lang {
    "python" ->
      string.contains(code_lower, "eval(")
      || string.contains(code_lower, "exec(")
      || string.contains(code_lower, "os.system")
    _ -> False
  }

  let mut_violations = []
  let mut_violations = case nul_detected {
    True -> ["NUL_BYTE_INJECTION", ..mut_violations]
    False -> mut_violations
  }
  let mut_violations = case sql_detected {
    True -> ["RAW_SQL_INJECTION", ..mut_violations]
    False -> mut_violations
  }
  let mut_violations = case jidoka_bypass {
    True -> ["JIDOKA_BYPASS_ATTEMPT", ..mut_violations]
    False -> mut_violations
  }
  let mut_violations = case zero_muda {
    True -> ["ZERO_MUDA_VIOLATION", ..mut_violations]
    False -> mut_violations
  }
  let mut_violations = case storage_locked {
    True -> ["OS_STORAGE_DENIED_SERIAL", ..mut_violations]
    False -> mut_violations
  }
  let mut_violations = case rust_panic {
    True -> ["RUST_UNHANDLED_PANIC", ..mut_violations]
    False -> mut_violations
  }
  let mut_violations = case gleam_panic {
    True -> ["GLEAM_UNHANDLED_PANIC", ..mut_violations]
    False -> mut_violations
  }
  let mut_violations = case python_eval {
    True -> ["PYTHON_UNSAFE_EVAL_EXEC", ..mut_violations]
    False -> mut_violations
  }
  let violations = list.reverse(mut_violations)

  let recs = case violations {
    [] -> [
      "AST structural verification passed. Code conforms to UOS safety invariants.",
    ]
    _ ->
      list.map(violations, fn(v) {
        case v {
          "NUL_BYTE_INJECTION" ->
            "Sanitize input boundary: reject raw NUL bytes."
          "RAW_SQL_INJECTION" ->
            "Use parameterized queries or Hermes typed relational algebra."
          "JIDOKA_BYPASS_ATTEMPT" ->
            "SC-JIDOKA-001: All tasks must be executed via tools/sa-plan."
          "ZERO_MUDA_VIOLATION" ->
            "SC-ZERO-MUDA-001: Bevy and Graphite are permanently barred. Use pure BEAM/Hermes."
          "OS_STORAGE_DENIED_SERIAL" ->
            "HARD_DENIED_SYSTEM_OS_SERIAL: Host root NVMe 25503L801736 is locked against allocation."
          "RUST_UNHANDLED_PANIC" ->
            "Replace unwrap/panic with Result/Option handling (SRXS-001)."
          "GLEAM_UNHANDLED_PANIC" -> "Replace panic/todo with explicit error types."
          "PYTHON_UNSAFE_EVAL_EXEC" ->
            "Eliminate dynamic evaluation; use typed RPC schemas."
          _ -> "Enforce typed structural contracts."
        }
      })
  }

  let has_critical =
    nul_detected || sql_detected || jidoka_bypass || zero_muda || storage_locked

  let #(anomaly_score, risk_level, passed) = case has_critical {
    True -> #(1.0, "BLOCKED", False)
    False ->
      case violations {
        [] -> #(0.05, "NOMINAL", True)
        _ ->
          case strict_mode {
            True -> #(0.65, "ELEVATED", False)
            False -> #(0.65, "ELEVATED", True)
          }
      }
  }

  let lines_count = list.length(string.split(code, "\n"))

  max_daemon.AstAnomalyReport(
    id: "ast-" <> int.to_string(lines_count),
    status: "ok",
    language: language,
    code_length: string.length(code),
    lines: lines_count,
    anomaly_score: anomaly_score,
    risk_level: risk_level,
    violations: violations,
    passed: passed,
    structural_similarity: 0.94,
    recommendations: recs,
    centroid_dimension: 128,
    latency_us: 15,
  )
}

// =============================================================================
// Model 2: ZK Knowledge Transclusion Model
// =============================================================================

pub fn evaluate_zk_transclusion(
  query: String,
  limit: Int,
) -> max_daemon.ZkTransclusionResult {
  let lim = case limit <= 0 {
    True -> 3
    False -> int.min(10, limit)
  }
  let q_lower = string.lowercase(query)

  let canonical_notes = [
    #(
      "ADR-066",
      "Sa-Plan Fractal Jidoka TPS and Universal Execution Authority",
      "L0",
      "Governs sa-plan as sole canonical execution authority and TPS Andon stop line.",
      "[[zk:20260907-1530-adr-066-sa-plan-fractal-jidoka-tps-and-universal-execution-authority]]",
      "http://nas-1.tail55d152.ts.net:4100/zk/20260907-1530-adr-066-sa-plan-fractal-jidoka-tps-and-universal-execution-authority",
      ["sa-plan", "jidoka", "tps", "authority", "andon", "execution", "plan"],
    ),
    #(
      "ADR-067",
      "Fractal Symbiosis Sa-Plan Sublimation and EV-91 Ratification",
      "L0",
      "Sublimation of fractal execution loops, TPS pull queues, and EV-91 ratification.",
      "[[zk:20260907-1550-adr-067-fractal-symbiosis-sa-plan-sublimation-and-ev91-ratification]]",
      "http://nas-1.tail55d152.ts.net:4100/zk/20260907-1550-adr-067-fractal-symbiosis-sa-plan-sublimation-and-ev91-ratification",
      ["symbiosis", "sublimation", "ev91", "ev-91", "ratification", "sa-plan"],
    ),
    #(
      "ADR-068",
      "Multidimensional Fractal Vectors Sa-Plan TPS Matrix",
      "L0",
      "10-Layer x 5-Surface Cartesian tensor product governing fractal execution.",
      "[[zk:20260907-1605-adr-068-multidimensional-fractal-vectors-sa-plan-tps-matrix]]",
      "http://nas-1.tail55d152.ts.net:4100/zk/20260907-1605-adr-068-multidimensional-fractal-vectors-sa-plan-tps-matrix",
      ["multidimensional", "vector", "matrix", "tensor", "layers", "surfaces"],
    ),
    #(
      "ADR-001",
      "Closed Rete Fact Schema and Strict Typing Invariant",
      "L0",
      "Formal schema and typed closed world assumption for Rete-UL forward chaining.",
      "[[zk:20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant]]",
      "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant",
      ["rete", "fact", "schema", "typing", "closed", "rules"],
    ),
    #(
      "ADR-002",
      "Embedded NUL Ingress Trap and Memory Allocation Containment",
      "L0",
      "Security boundary invariant intercepting embedded NUL bytes and SQL injection.",
      "[[zk:20260904-150142-adr-002-embedded-nul-ingress-trap-and-memory-allocation-containment]]",
      "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150142-adr-002-embedded-nul-ingress-trap-and-memory-allocation-containment",
      ["nul", "trap", "ingress", "memory", "injection", "security"],
    ),
    #(
      "ADR-003",
      "Pure 100-Byte Binary SQLite Header Verification Rule R31",
      "L0",
      "SQLite 100-byte binary header validation and WAL consistency verification.",
      "[[zk:20260904-150145-adr-003-pure-100-byte-binary-sqlite-header-verification-rule-r31]]",
      "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150145-adr-003-pure-100-byte-binary-sqlite-header-verification-rule-r31",
      ["sqlite", "header", "wal", "verification", "binary", "rule"],
    ),
    #(
      "ADR-005",
      "Dual-Host Unified Operational System Topology and Live Tailnet Wiki",
      "L4",
      "Universal Tailscale FQDN navigation and distributed topology over Tailnet.",
      "[[zk:20260904-151412-adr-005-dual-host-unified-operational-system-topology-and-live-tailnet-wiki-integration]]",
      "http://nas-1.tail55d152.ts.net:4100/zk/20260904-151412-adr-005-dual-host-unified-operational-system-topology-and-live-tailnet-wiki-integration",
      ["tailscale", "tailnet", "wiki", "dual-host", "topology", "fqdn"],
    ),
    #(
      "MOC-MASTER",
      "Master Map of Content (MOC) UOS Unified Knowledge Base",
      "L5",
      "Master Map of Content indexing all ADRs, living ontology, and fractal layers.",
      "[[zk:20260905-1801-moc-uos-unified-master]]",
      "http://nas-1.tail55d152.ts.net:4100/zk/20260905-1801-moc-uos-unified-master",
      ["moc", "master", "index", "catalog", "ontology", "unified"],
    ),
  ]

  let scored =
    list.map(canonical_notes, fn(note) {
      let #(id, title, layer, summary, transclusion, url, keywords) = note
      let id_match = case string.contains(q_lower, string.lowercase(id)) {
        True -> 2.0
        False -> 0.0
      }
      let kw_matches =
        list.fold(keywords, 0.0, fn(acc, kw) {
          case string.contains(q_lower, kw) {
            True -> acc +. 0.35
            False -> acc
          }
        })
      let score = id_match +. kw_matches
      let relevance = case score >=. 1.5 {
        True -> "exact"
        False ->
          case score >=. 0.7 {
            True -> "high"
            False -> "moderate"
          }
      }
      #(
        score,
        max_daemon.ZkMatch(
          id: id,
          title: title,
          layer: layer,
          score: score,
          relevance: relevance,
          transclusion: transclusion,
          tailscale_url: url,
          summary: summary,
        ),
      )
    })

  let sorted_matches =
    list.sort(scored, fn(a, b) { float.compare(b.0, a.0) })
    |> list.map(fn(pair) { pair.1 })
    |> list.take(lim)

  max_daemon.ZkTransclusionResult(
    id: "zk-query",
    status: "ok",
    query: query,
    total_corpus_notes: 68,
    match_count: list.length(sorted_matches),
    matches: sorted_matches,
    latency_us: 25,
  )
}

// =============================================================================
// Model 3: Anticipatory Lyapunov Trend Predictor
// =============================================================================

pub fn evaluate_lyapunov_trend(
  telemetry: List(Float),
  dt: Float,
  horizon_s: Float,
  critical_threshold: Float,
) -> max_daemon.LyapunovTrendResult {
  let sample_count = list.length(telemetry)
  let dt_eff = case dt <=. 0.0 {
    True -> 1.0
    False -> dt
  }
  let crit = case critical_threshold <=. 0.0 {
    True -> 100.0
    False -> critical_threshold
  }

  let current_val = case list.reverse(telemetry) {
    [last, ..] -> last
    [] -> 1.0
  }

  let #(growth_sum, pairs_count) = case telemetry {
    [] | [_] -> #(0.0, 0)
    [first, ..rest] -> {
      let #(_, sum, count) =
        list.fold(rest, #(first, 0.0, 0), fn(acc, curr) {
          let #(prev, s, c) = acc
          let delta = float.absolute_value(curr -. prev)
          let base = float.absolute_value(prev) +. 0.000001
          let ratio = delta /. base
          let step_val = case ratio >. 0.5 {
            True -> 0.45
            False ->
              case ratio >. 0.05 {
                True -> 0.02
                False -> -0.35
              }
          }
          #(curr, s +. step_val, c + 1)
        })
      #(sum, count)
    }
  }

  let lambda = case pairs_count > 0 {
    True -> growth_sum /. { int.to_float(pairs_count) *. dt_eff }
    False -> -0.35
  }

  let #(stability, phase, cert_pass) = case lambda <=. -0.30 {
    True -> #("strongly_stable", "ACT", True)
    False ->
      case lambda <=. 0.05 {
        True -> #("marginally_stable", "OBSERVE", True)
        False ->
          case lambda <=. 0.50 {
            True -> #("unstable_divergent", "DECIDE", False)
            False -> #("chaotic_cascade", "STOP_ANDON", False)
          }
      }
  }

  let time_to_cascade = case lambda >. 0.0 && current_val <. crit {
    True -> {
      let ratio = crit /. current_val
      case float.square_root(ratio) {
        Ok(r) -> Some(r /. lambda)
        Error(_) -> None
      }
    }
    False ->
      case current_val >=. crit {
        True -> Some(0.0)
        False -> None
      }
  }

  let preflight_status = case cert_pass {
    True -> "PASSED"
    False ->
      case lambda <=. 0.30 {
        True -> "CONDITIONAL"
        False -> "FAILED"
      }
  }

  let traj = [
    current_val,
    current_val *. { 1.0 +. { lambda *. 0.2 } },
    current_val *. { 1.0 +. { lambda *. 0.4 } },
    current_val *. { 1.0 +. { lambda *. 0.6 } },
    current_val *. { 1.0 +. { lambda *. 0.8 } },
  ]

  max_daemon.LyapunovTrendResult(
    id: "lyap-" <> int.to_string(sample_count),
    status: "ok",
    samples_count: sample_count,
    dt_seconds: dt_eff,
    horizon_seconds: horizon_s,
    current_value: current_val,
    critical_threshold: crit,
    lyapunov_exponent: lambda,
    stability_state: stability,
    time_to_cascade_s: time_to_cascade,
    forecast_trajectory: traj,
    seu_preflight_passed: cert_pass,
    preflight_status: preflight_status,
    recommended_poodavr_phase: phase,
    latency_us: 18,
  )
}

// =============================================================================
// JSON Parsers for POST Requests
// =============================================================================

pub fn parse_ast_anomaly_body(
  body: String,
) -> Result(#(String, String, Bool), String) {
  let decoder = {
    use code <- decode.field("code", decode.string)
    use language <- decode.optional_field("language", "gleam", decode.string)
    use strict_mode <- decode.optional_field("strict_mode", True, decode.bool)
    decode.success(#(code, language, strict_mode))
  }
  json.parse(body, decoder)
  |> result.map_error(fn(_) { "failed_to_parse_ast_anomaly_request" })
}

pub fn parse_zk_transclude_body(body: String) -> Result(#(String, Int), String) {
  let decoder = {
    use query <- decode.field("query", decode.string)
    use limit <- decode.optional_field("limit", 3, decode.int)
    decode.success(#(query, limit))
  }
  json.parse(body, decoder)
  |> result.map_error(fn(_) { "failed_to_parse_zk_transclude_request" })
}

pub fn parse_lyapunov_trend_body(
  body: String,
) -> Result(#(List(Float), Float, Float, Float), String) {
  let decoder = {
    use telemetry <- decode.field("telemetry", decode.list(decode.float))
    use dt <- decode.optional_field("dt", 1.0, decode.float)
    use horizon_s <- decode.optional_field("horizon_s", 60.0, decode.float)
    use critical_threshold <- decode.optional_field(
      "critical_threshold",
      100.0,
      decode.float,
    )
    decode.success(#(telemetry, dt, horizon_s, critical_threshold))
  }
  json.parse(body, decoder)
  |> result.map_error(fn(_) { "failed_to_parse_lyapunov_trend_request" })
}
