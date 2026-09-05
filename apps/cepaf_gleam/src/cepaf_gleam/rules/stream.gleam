//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/rules/stream</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ULTRA-001, SC-OODA-001</stamp-controls></compliance>
//// </c3i-module>
////
//// FRP OODA Wavefront — continuous stream-processing actor per RETE-UL domain.
//// Each domain evaluates independently; decision fusion combines outputs.

import cepaf_gleam/rules/engine.{type Fact, type RuleResult, RuleResult}
import gleam/dict.{type Dict}
import gleam/list

/// State of a single domain stream actor
pub type DomainStream {
  DomainStream(
    domain: String,
    last_result: RuleResult,
    evaluation_count: Int,
    last_latency_us: Int,
  )
}

/// Combined wavefront — all 13 domains evaluated in parallel
pub type OodaWavefront {
  OodaWavefront(
    domains: Dict(String, DomainStream),
    cycle_count: Int,
    fused_decision: String,
    fused_reason: String,
  )
}

/// Initialize wavefront with all 13 domains
pub fn init_wavefront() -> OodaWavefront {
  let domains = [
    "ooda", "preflight", "recovery", "health", "cascade", "partition", "launch",
    "governor", "verify", "build", "apoptosis", "rca", "hysteresis",
  ]
  let streams =
    list.fold(domains, dict.new(), fn(acc, d) {
      dict.insert(
        acc,
        d,
        DomainStream(
          domain: d,
          last_result: RuleResult(decision: "NoAction", reason: "Initial"),
          evaluation_count: 0,
          last_latency_us: 0,
        ),
      )
    })
  OodaWavefront(
    domains: streams,
    cycle_count: 0,
    fused_decision: "NoAction",
    fused_reason: "Initial",
  )
}

/// Evaluate a single domain with new facts
pub fn evaluate_domain(
  wavefront: OodaWavefront,
  domain: String,
  facts: List(Fact),
) -> OodaWavefront {
  let result = case domain {
    "ooda" -> engine.evaluate("System", engine.ooda_rules(), facts)
    "preflight" -> engine.evaluate("Preflight", engine.preflight_rules(), facts)
    "cascade" -> engine.evaluate("Cascade", engine.cascade_rules(), facts)
    "recovery" -> engine.evaluate("Recovery", engine.recovery_rules(), facts)
    "health" -> engine.evaluate("Health", engine.health_rules(), facts)
    "governor" -> engine.evaluate("Governor", engine.governor_rules(), facts)
    "verify" -> engine.evaluate("Verify", engine.verify_rules(), facts)
    "launch" -> engine.evaluate("Launch", engine.launch_rules(), facts)
    "rca" -> engine.evaluate("RCA", engine.rca_rules(), facts)
    "build" -> engine.evaluate("Build", engine.build_rules(), facts)
    "apoptosis" -> engine.evaluate("Apoptosis", engine.apoptosis_rules(), facts)
    "hysteresis" ->
      engine.evaluate("Hysteresis", engine.hysteresis_rules(), facts)
    "partition" -> engine.evaluate("Partition", engine.partition_rules(), facts)
    _ -> RuleResult(decision: "Unknown", reason: "Unknown domain")
  }

  let updated_stream =
    DomainStream(
      domain: domain,
      last_result: result,
      evaluation_count: case dict.get(wavefront.domains, domain) {
        Ok(s) -> s.evaluation_count + 1
        Error(_) -> 1
      },
      last_latency_us: 0,
    )

  OodaWavefront(
    ..wavefront,
    domains: dict.insert(wavefront.domains, domain, updated_stream),
  )
}

/// Fuse all domain decisions into a single OODA decision
/// Priority: EmergencyStop > BootMesh > RestartContainer > HealthCheck > NoAction
pub fn fuse_decisions(wavefront: OodaWavefront) -> OodaWavefront {
  let all_decisions =
    dict.values(wavefront.domains)
    |> list.map(fn(s) { s.last_result.decision })

  let fused = case list.contains(all_decisions, "EmergencyStop") {
    True -> #("EmergencyStop", "Emergency detected by domain rule")
    False ->
      case list.contains(all_decisions, "BootMesh") {
        True -> #("BootMesh", "Boot required by domain rule")
        False ->
          case list.contains(all_decisions, "RestartContainer") {
            True -> #("RestartContainer", "Restart required by domain rule")
            False ->
              case list.contains(all_decisions, "HealthCheck") {
                True -> #(
                  "HealthCheck",
                  "Health check triggered by domain rule",
                )
                False -> #("NoAction", "All domains nominal")
              }
          }
      }
  }

  OodaWavefront(
    ..wavefront,
    fused_decision: fused.0,
    fused_reason: fused.1,
    cycle_count: wavefront.cycle_count + 1,
  )
}

/// Get the current fused decision
pub fn current_decision(wavefront: OodaWavefront) -> RuleResult {
  RuleResult(decision: wavefront.fused_decision, reason: wavefront.fused_reason)
}
