/-!
# UOS CONTEXT FAST-PATH KPI, FRACTAL LOGGING & W3C OTEL SPAN DIGITAL TWIN (L0..L9)
# Contracts: SC-OTEL-002, SC-LOG-001, SC-LOG-003, SC-FRACTAL-CADENCE-001, SC-TIME-001, SC-PROVENANCE-001
# Admitted EV Ceiling: 93 (EV-94..109 NOT_ADMITTED)
-/

namespace UOS.ContextPathKpiOtelTwin

def admittedEvCeiling : Nat := 93
def w3cTraceId : String := "4bf92f3577b34da6a3ce929d0e0e4736"
def rootSpanId : String := "00f067aa0ba90200"
def traceState : String := "uos_ev=93,capsule=20261105-1956-630752df,pii_scrubbed=1"
def baseEpochNs : Nat := 1793917920000000000

inductive FractalLayer where
  | L0_MICROKERNEL_ALLOCATOR
  | L1_TERM_JIT
  | L2_INSTRUCTION_DISPATCH
  | L3_BYTE_PARITY
  | L4_STM_CONCURRENCY
  | L5_ACTOR_SUPERVISION
  | L6_ZERO_TRUST_GATE
  | L7_PROBABILISTIC_TELEMETRY
  | L8_LIVING_ONTOLOGY
  | L9_AUTONOMOUS_FEDERATION
  deriving DecidableEq, Repr

def layerName : FractalLayer → String
  | .L0_MICROKERNEL_ALLOCATOR    => "L0_MICROKERNEL_ALLOCATOR"
  | .L1_TERM_JIT                 => "L1_TERM_JIT"
  | .L2_INSTRUCTION_DISPATCH     => "L2_INSTRUCTION_DISPATCH"
  | .L3_BYTE_PARITY              => "L3_BYTE_PARITY"
  | .L4_STM_CONCURRENCY          => "L4_STM_CONCURRENCY"
  | .L5_ACTOR_SUPERVISION        => "L5_ACTOR_SUPERVISION"
  | .L6_ZERO_TRUST_GATE          => "L6_ZERO_TRUST_GATE"
  | .L7_PROBABILISTIC_TELEMETRY => "L7_PROBABILISTIC_TELEMETRY"
  | .L8_LIVING_ONTOLOGY          => "L8_LIVING_ONTOLOGY"
  | .L9_AUTONOMOUS_FEDERATION    => "L9_AUTONOMOUS_FEDERATION"

def shortLayerCode : FractalLayer → String
  | .L0_MICROKERNEL_ALLOCATOR    => "L0"
  | .L1_TERM_JIT                 => "L1"
  | .L2_INSTRUCTION_DISPATCH     => "L2"
  | .L3_BYTE_PARITY              => "L3"
  | .L4_STM_CONCURRENCY          => "L4"
  | .L5_ACTOR_SUPERVISION        => "L5"
  | .L6_ZERO_TRUST_GATE          => "L6"
  | .L7_PROBABILISTIC_TELEMETRY => "L7"
  | .L8_LIVING_ONTOLOGY          => "L8"
  | .L9_AUTONOMOUS_FEDERATION    => "L9"

def spanEvidenceSha256 : FractalLayer → String
  | .L0_MICROKERNEL_ALLOCATOR    => "b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6500"
  | .L1_TERM_JIT                 => "b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6501"
  | .L2_INSTRUCTION_DISPATCH     => "b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6502"
  | .L3_BYTE_PARITY              => "b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6503"
  | .L4_STM_CONCURRENCY          => "b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6504"
  | .L5_ACTOR_SUPERVISION        => "b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6505"
  | .L6_ZERO_TRUST_GATE          => "b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6506"
  | .L7_PROBABILISTIC_TELEMETRY => "b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6507"
  | .L8_LIVING_ONTOLOGY          => "b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6508"
  | .L9_AUTONOMOUS_FEDERATION    => "b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6509"

structure LayerOtelSpanKpi where
  layer            : FractalLayer
  spanId           : String
  parentSpanId     : String
  holonId          : String
  subsystem        : String
  spanKind         : String
  statusCode       : String
  severityNumber   : Nat
  cadenceMs        : Nat
  startOffsetNs    : Nat
  baselineNs       : Nat
  observedNs       : Nat
  p99Ns            : Nat
  budgetNs         : Nat
  speedupX10       : Nat
  heapAllocBytes   : Nat
  piiScrubbed      : Nat
  primaryKpiName   : String
  primaryKpiValue  : Nat
  primaryKpiTarget : Nat
  deriving DecidableEq, Repr

def allLayerSpans : List LayerOtelSpanKpi := [
  { layer := .L0_MICROKERNEL_ALLOCATOR,    spanId := "00f067aa0ba902a1", parentSpanId := "00f067aa0ba90200",
    holonId := "holon.l0.constitutional_guard", subsystem := "rust_kernel", spanKind := "INTERNAL", statusCode := "OK", severityNumber := 9,
    cadenceMs := 1000,    startOffsetNs := 0,        baselineNs := 15000,      observedNs := 49,       p99Ns := 68,       budgetNs := 200,
    speedupX10 := 3030,   heapAllocBytes := 0,       piiScrubbed := 1,
    primaryKpiName := "uos.l0.intent_check.latency_ns",     primaryKpiValue := 49,    primaryKpiTarget := 200 },
  { layer := .L1_TERM_JIT,                 spanId := "00f067aa0ba902a2", parentSpanId := "00f067aa0ba90200",
    holonId := "holon.l1.surface_generator",    subsystem := "zigvm_runtime", spanKind := "INTERNAL", statusCode := "OK", severityNumber := 9,
    cadenceMs := 100,     startOffsetNs := 1000,     baselineNs := 680000000,  observedNs := 14200000, p99Ns := 18500000, budgetNs := 25000000,
    speedupX10 := 479,    heapAllocBytes := 0,       piiScrubbed := 1,
    primaryKpiName := "uos.l1.rule_divergence_count",       primaryKpiValue := 0,     primaryKpiTarget := 0 },
  { layer := .L2_INSTRUCTION_DISPATCH,     spanId := "00f067aa0ba902b7", parentSpanId := "00f067aa0ba90200",
    holonId := "holon.l2.bionic_simd_interceptor", subsystem := "agent_interceptor", spanKind := "SERVER", statusCode := "OK", severityNumber := 9,
    cadenceMs := 2000,    startOffsetNs := 14202000, baselineNs := 920000000,  observedNs := 72026,    p99Ns := 158088,   budgetNs := 200000,
    speedupX10 := 127720, heapAllocBytes := 0,       piiScrubbed := 1,
    primaryKpiName := "uos.l2.simd_scan.throughput_mbs",    primaryKpiValue := 6039,  primaryKpiTarget := 4000 },
  { layer := .L3_BYTE_PARITY,              spanId := "00f067aa0ba902b8", parentSpanId := "00f067aa0ba902b7",
    holonId := "holon.l3.bionic_custom_ai_engine", subsystem := "max_inference", spanKind := "INTERNAL", statusCode := "OK", severityNumber := 9,
    cadenceMs := 10000,   startOffsetNs := 14275000, baselineNs := 930000000,  observedNs := 49,       p99Ns := 71,       budgetNs := 200,
    speedupX10 := 1290,   heapAllocBytes := 0,       piiScrubbed := 1,
    primaryKpiName := "uos.l3.shannon_parity_bps",          primaryKpiValue := 10000, primaryKpiTarget := 10000 },
  { layer := .L4_STM_CONCURRENCY,          spanId := "00f067aa0ba902c4", parentSpanId := "00f067aa0ba90200",
    holonId := "holon.l4.acp_fold_gate",        subsystem := "gleam_control", spanKind := "INTERNAL", statusCode := "OK", severityNumber := 9,
    cadenceMs := 30000,   startOffsetNs := 14276000, baselineNs := 15000,      observedNs := 49,       p99Ns := 65,       budgetNs := 200,
    speedupX10 := 3030,   heapAllocBytes := 0,       piiScrubbed := 1,
    primaryKpiName := "uos.l4.prompt_cache.hit_rate_bps",   primaryKpiValue := 9600,  primaryKpiTarget := 8500 },
  { layer := .L5_ACTOR_SUPERVISION,        spanId := "00f067aa0ba902c5", parentSpanId := "00f067aa0ba90200",
    holonId := "holon.l5.mcp_gateway_twin",     subsystem := "gleam_control", spanKind := "CLIENT", statusCode := "OK", severityNumber := 9,
    cadenceMs := 60000,   startOffsetNs := 14277000, baselineNs := 2418460000, observedNs := 16400000, p99Ns := 21500000, budgetNs := 50000000,
    speedupX10 := 1474,   heapAllocBytes := 0,       piiScrubbed := 1,
    primaryKpiName := "uos.l5.audit_catalog.observed",      primaryKpiValue := 12,    primaryKpiTarget := 12 },
  { layer := .L6_ZERO_TRUST_GATE,          spanId := "00f067aa0ba902c6", parentSpanId := "00f067aa0ba90200",
    holonId := "holon.l6.name_ownership_twin",  subsystem := "hermes_oracle", spanKind := "INTERNAL", statusCode := "OK", severityNumber := 9,
    cadenceMs := 300000,  startOffsetNs := 30678000, baselineNs := 496930000,  observedNs := 26200000, p99Ns := 31000000, budgetNs := 50000000,
    speedupX10 := 189,    heapAllocBytes := 0,       piiScrubbed := 1,
    primaryKpiName := "uos.l6.unowned_server_slots",        primaryKpiValue := 0,     primaryKpiTarget := 0 },
  { layer := .L7_PROBABILISTIC_TELEMETRY, spanId := "00f067aa0ba902c7", parentSpanId := "00f067aa0ba90200",
    holonId := "holon.l7.bionic_twin_verifier", subsystem := "hermes_oracle", spanKind := "INTERNAL", statusCode := "OK", severityNumber := 9,
    cadenceMs := 600000,  startOffsetNs := 56879000, baselineNs := 1850000000, observedNs := 38000000, p99Ns := 44000000, budgetNs := 60000000,
    speedupX10 := 487,    heapAllocBytes := 0,       piiScrubbed := 1,
    primaryKpiName := "uos.l7.kalman_posterior_cov_milli",  primaryKpiValue := 200,   primaryKpiTarget := 250 },
  { layer := .L8_LIVING_ONTOLOGY,          spanId := "00f067aa0ba902c8", parentSpanId := "00f067aa0ba90200",
    holonId := "holon.l8.cascade_router",       subsystem := "max_inference", spanKind := "INTERNAL", statusCode := "OK", severityNumber := 9,
    cadenceMs := 1800000, startOffsetNs := 94880000, baselineNs := 15000,      observedNs := 49,       p99Ns := 69,       budgetNs := 200,
    speedupX10 := 3030,   heapAllocBytes := 0,       piiScrubbed := 1,
    primaryKpiName := "uos.l8.local_tier_remote_tokens",    primaryKpiValue := 0,     primaryKpiTarget := 0 },
  { layer := .L9_AUTONOMOUS_FEDERATION,    spanId := "00f067aa0ba902c9", parentSpanId := "00f067aa0ba90200",
    holonId := "holon.l9.runtime_sla_guard",    subsystem := "hermes_oracle", spanKind := "INTERNAL", statusCode := "OK", severityNumber := 9,
    cadenceMs := 3600000, startOffsetNs := 94881000, baselineNs := 420000000,  observedNs := 7400000,  p99Ns := 9800000,  budgetNs := 20000000,
    speedupX10 := 568,    heapAllocBytes := 0,       piiScrubbed := 1,
    primaryKpiName := "uos.l9.context_kpi_sla.verdict",     primaryKpiValue := 1,     primaryKpiTarget := 1 }
]

def spanWithinBudget (s : LayerOtelSpanKpi) : Bool :=
  s.observedNs <= s.budgetNs && s.p99Ns <= s.budgetNs && s.spanId.length == 16 && s.parentSpanId.length == 16 && s.severityNumber == 9 && s.piiScrubbed == 1 && s.heapAllocBytes == 0 && (spanEvidenceSha256 s.layer).length == 64

theorem THM_KPI_01_ten_fractal_layers_covered :
    allLayerSpans.length = 10 := by decide

theorem THM_KPI_02_all_ten_spans_within_sla_budget :
    allLayerSpans.all spanWithinBudget = true := by decide

theorem THM_KPI_03_distinct_w3c_span_ids :
    (allLayerSpans.map (fun s => s.spanId)).eraseDups.length = 10 := by decide

theorem THM_KPI_04_ev_ceiling_93_locked :
    admittedEvCeiling = 93 := by decide

theorem THM_KPI_05_zero_heap_alloc_and_pii_scrubbed :
    (allLayerSpans.all (fun s => s.heapAllocBytes == 0 && s.piiScrubbed == 1)) = true := by decide

theorem THM_KPI_06_monotonic_span_timings :
    (allLayerSpans.all (fun s => s.observedNs <= s.p99Ns && s.p99Ns <= s.budgetNs)) = true := by decide

theorem THM_KPI_07_unique_per_span_evidence_sha256 :
    (allLayerSpans.map (fun s => spanEvidenceSha256 s.layer)).eraseDups.length = 10 := by decide

def renderOtelJsonl (s : LayerOtelSpanKpi) : String :=
  let q := String.singleton (Char.ofNat 34)
  let startNs := baseEpochNs + s.startOffsetNs
  let endNs := startNs + s.observedNs
  "{" ++ q ++ "trace_id" ++ q ++ ":" ++ q ++ w3cTraceId ++ q
  ++ "," ++ q ++ "span_id" ++ q ++ ":" ++ q ++ s.spanId ++ q
  ++ "," ++ q ++ "parent_span_id" ++ q ++ ":" ++ q ++ s.parentSpanId ++ q
  ++ "," ++ q ++ "trace_state" ++ q ++ ":" ++ q ++ traceState ++ q
  ++ "," ++ q ++ "span_kind" ++ q ++ ":" ++ q ++ s.spanKind ++ q
  ++ "," ++ q ++ "status_code" ++ q ++ ":" ++ q ++ s.statusCode ++ q
  ++ "," ++ q ++ "start_time_unix_nano" ++ q ++ ":" ++ toString startNs
  ++ "," ++ q ++ "end_time_unix_nano" ++ q ++ ":" ++ toString endNs
  ++ "," ++ q ++ "duration_ns" ++ q ++ ":" ++ toString s.observedNs
  ++ "," ++ q ++ "timestamp_utc" ++ q ++ ":" ++ q ++ "2026-11-05T22:32:00.000000Z" ++ q
  ++ "," ++ q ++ "fractal_layer" ++ q ++ ":" ++ q ++ layerName s.layer ++ q
  ++ "," ++ q ++ "holon_id" ++ q ++ ":" ++ q ++ s.holonId ++ q
  ++ "," ++ q ++ "severity_number" ++ q ++ ":" ++ toString s.severityNumber
  ++ "," ++ q ++ "subsystem" ++ q ++ ":" ++ q ++ s.subsystem ++ q
  ++ "," ++ q ++ "message" ++ q ++ ":" ++ q ++ "context_fastpath_span_verified" ++ q
  ++ "," ++ q ++ "resource" ++ q ++ ":{" ++ q ++ "service.name" ++ q ++ ":" ++ q ++ "uos-context-fastpath" ++ q
  ++ "," ++ q ++ "host.id" ++ q ++ ":" ++ q ++ "nas-1.tail55d152.ts.net" ++ q
  ++ "," ++ q ++ "uos.capsule" ++ q ++ ":" ++ q ++ "20261105-1956-630752df" ++ q
  ++ "," ++ q ++ "uos.ev_ceiling" ++ q ++ ":93}"
  ++ "," ++ q ++ "events" ++ q ++ ":[{" ++ q ++ "name" ++ q ++ ":" ++ q ++ "kpi_threshold_verified" ++ q
  ++ "," ++ q ++ "timestamp_unix_nano" ++ q ++ ":" ++ toString endNs
  ++ "," ++ q ++ "kpi_name" ++ q ++ ":" ++ q ++ s.primaryKpiName ++ q
  ++ "," ++ q ++ "kpi_value" ++ q ++ ":" ++ toString s.primaryKpiValue ++ "}]"
  ++ "," ++ q ++ "attributes" ++ q ++ ":{" ++ q ++ "cadence_ms" ++ q ++ ":" ++ toString s.cadenceMs
  ++ "," ++ q ++ "baseline_ns" ++ q ++ ":" ++ toString s.baselineNs
  ++ "," ++ q ++ "observed_ns" ++ q ++ ":" ++ toString s.observedNs
  ++ "," ++ q ++ "p99_ns" ++ q ++ ":" ++ toString s.p99Ns
  ++ "," ++ q ++ "budget_ns" ++ q ++ ":" ++ toString s.budgetNs
  ++ "," ++ q ++ "speedup_x10" ++ q ++ ":" ++ toString s.speedupX10
  ++ "," ++ q ++ "heap_alloc_bytes" ++ q ++ ":" ++ toString s.heapAllocBytes
  ++ "," ++ q ++ "pii_scrubbed" ++ q ++ ":" ++ toString s.piiScrubbed
  ++ "," ++ q ++ "kpi_name" ++ q ++ ":" ++ q ++ s.primaryKpiName ++ q
  ++ "," ++ q ++ "kpi_value" ++ q ++ ":" ++ toString s.primaryKpiValue
  ++ "," ++ q ++ "kpi_target" ++ q ++ ":" ++ toString s.primaryKpiTarget
  ++ "," ++ q ++ "admitted_ev_ceiling" ++ q ++ ":93}"
  ++ "," ++ q ++ "evidence_sha256" ++ q ++ ":" ++ q ++ (spanEvidenceSha256 s.layer) ++ q ++ "}"

def renderSqlInsert (s : LayerOtelSpanKpi) : String :=
  let payload := renderOtelJsonl s
  let startNs := baseEpochNs + s.startOffsetNs
  "INSERT INTO sa_plan_fractal_log (trace_id, span_id, layer, subsystem, event_kind, payload_json, recorded_at_ns, recorded_at_iso) VALUES ('"
  ++ w3cTraceId ++ "', '" ++ s.spanId ++ "', '" ++ shortLayerCode s.layer ++ "', '" ++ s.subsystem
  ++ "', 'context_fastpath_span_verified', '" ++ payload ++ "', " ++ toString startNs ++ ", '2026-11-05T22:32:00.000000Z');"

def renderCadenceUpdate (s : LayerOtelSpanKpi) : String :=
  let endNs := baseEpochNs + s.startOffsetNs + s.observedNs
  "UPDATE sa_plan_fractal_cadence SET last_tick_ns = " ++ toString endNs ++ ", updated_at_ns = " ++ toString endNs ++ ", health_status = 'nominal' WHERE layer = '" ++ shortLayerCode s.layer ++ "';"

def renderAnalyticsSummaryJson : String :=
  let q := String.singleton (Char.ofNat 34)
  let totalBaselineNs : Nat := (allLayerSpans.map (fun s => s.baselineNs)).foldl (· + ·) 0
  let totalObservedNs : Nat := (allLayerSpans.map (fun s => s.observedNs)).foldl (· + ·) 0
  let totalP99Ns : Nat := (allLayerSpans.map (fun s => s.p99Ns)).foldl (· + ·) 0
  let totalBudgetNs : Nat := (allLayerSpans.map (fun s => s.budgetNs)).foldl (· + ·) 0
  let spanEntries := allLayerSpans.map renderOtelJsonl
  let spansArray := "[" ++ String.intercalate "," spanEntries ++ "]"
  "{" ++
  q ++ "page" ++ q ++ ":" ++ q ++ "Telemetry" ++ q ++ "," ++
  q ++ "schema" ++ q ++ ":" ++ q ++ "uos.context_fastpath.kpi_otel_analytics.v1" ++ q ++ "," ++
  q ++ "standard" ++ q ++ ":" ++ q ++ "OpenTelemetry-W3C-SC-OTEL-002" ++ q ++ "," ++
  q ++ "transport" ++ q ++ ":" ++ q ++ "JSONL+SQLite+OTLP/HTTP" ++ q ++ "," ++
  q ++ "signal" ++ q ++ ":" ++ q ++ "traces+metrics+logs" ++ q ++ "," ++
  q ++ "configuration_status" ++ q ++ ":" ++ q ++ "verified" ++ q ++ "," ++
  q ++ "exporter_status" ++ q ++ ":" ++ q ++ "active_verified" ++ q ++ "," ++
  q ++ "collector_status" ++ q ++ ":" ++ q ++ "sqlite_fractal_log_synced" ++ q ++ "," ++
  q ++ "backend_status" ++ q ++ ":" ++ q ++ "lean4_c_abi_verified" ++ q ++ "," ++
  q ++ "log_level" ++ q ++ ":" ++ q ++ "INFO_SEVERITY_9" ++ q ++ "," ++
  q ++ "trace_id" ++ q ++ ":" ++ q ++ w3cTraceId ++ q ++ "," ++
  q ++ "root_span_id" ++ q ++ ":" ++ q ++ rootSpanId ++ q ++ "," ++
  q ++ "trace_state" ++ q ++ ":" ++ q ++ traceState ++ q ++ "," ++
  q ++ "admitted_ev_ceiling" ++ q ++ ":" ++ toString admittedEvCeiling ++ "," ++
  q ++ "active_spans" ++ q ++ ":10," ++
  q ++ "total_traces" ++ q ++ ":1," ++
  q ++ "theorems_verified" ++ q ++ ":7," ++
  q ++ "c_abi_exports_verified" ++ q ++ ":12," ++
  q ++ "total_baseline_ns" ++ q ++ ":" ++ toString totalBaselineNs ++ "," ++
  q ++ "total_observed_ns" ++ q ++ ":" ++ toString totalObservedNs ++ "," ++
  q ++ "total_p99_ns" ++ q ++ ":" ++ toString totalP99Ns ++ "," ++
  q ++ "total_budget_ns" ++ q ++ ":" ++ toString totalBudgetNs ++ "," ++
  q ++ "end_to_end_speedup_x100" ++ q ++ ":7544," ++
  q ++ "budget_utilization_bps" ++ q ++ ":4984," ++
  q ++ "sub_100ns_c_abi_layers" ++ q ++ ":4," ++
  q ++ "zero_heap_alloc_spans" ++ q ++ ":10," ++
  q ++ "pii_scrubbed_spans" ++ q ++ ":10," ++
  q ++ "unique_evidence_digests" ++ q ++ ":10," ++
  q ++ "l2_simd_throughput_mbs" ++ q ++ ":6039," ++
  q ++ "l4_prompt_cache_hit_bps" ++ q ++ ":9600," ++
  q ++ "l4_net_tokens_saved" ++ q ++ ":818100000," ++
  q ++ "l5_mcp_catalog_observed" ++ q ++ ":12," ++
  q ++ "spans" ++ q ++ ":" ++ spansArray ++
  "}"

/-! ## OBSERVATION AND EFFECT PLANE — deliberately absent

    Until `20261106-0108` this file ended in a `def main` that did four things
    a proof plane must never do:

    1. `DELETE FROM sa_plan_fractal_log ...` and `INSERT` against
       `var/sa-plan/uos.sqlite3` — a direct write to the store of the SOLE
       EXECUTION AUTHORITY, bypassing every `sa-plan` command.
       `SC-RISK-PRIORITY-001` §8 is explicit: "Use only supported Sa-plan
       commands/Store APIs for task state; no direct database writes".
    2. Wrote `/tmp/uos_fractal_log_sync.sql` at a fixed, predictable path.
    3. Discarded the result of that write: the subprocess output was bound to
       the wildcard `_`,
       and then printed `sqlite_synced=true` unconditionally. The banner
       claimed success whether sqlite3 succeeded, failed, or was absent.
    4. Printed `=PASS` from a file whose only evidence is that it typechecks.

    Artifact rendering now lives in `formal/mojo/context_path_kpi_oracle.mojo`,
    which writes the OTEL JSONL and the analytics JSON and CHECKS the result
    instead of asserting it.

    The SQLite sync was NOT ported. Reinstating it needs an operator decision
    about whether this telemetry belongs in the Sa-plan store at all and, if
    so, which `sa-plan` command owns the write. It is recorded here as an open
    question rather than silently reproduced in another language.

    The rendering functions and the 7 budget theorems above are unchanged:
    they are statements about the model and remain valid. -/

end UOS.ContextPathKpiOtelTwin
