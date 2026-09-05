//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module><identity><module>cepaf_gleam/rules/dispatcher</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-OODA-003, SC-ALLIUM-001</stamp-controls></compliance>
//// </c3i-module>
////
//// RETE-UL Decision Dispatcher — bridges rule evaluation to system actions.
//// When rules evaluate to decisions like "EmergencyStop" or "Restart",
//// this module routes them to the appropriate handler.
//// STAMP: SC-OODA-003 (decide→act coupling)

import cepaf_gleam/rules/engine.{type Fact, type RuleResult}
import cepaf_gleam/ui/domain.{Agents, Cockpit, Dashboard, Podman}
import cepaf_gleam/ui/zenoh_otel
import cepaf_gleam/zenoh/client

/// Action to take based on a rule decision.
pub type Action {
  EmergencyStop(reason: String)
  RestartContainer(name: String, reason: String)
  ScaleDown(reason: String)
  Escalate(level: String, reason: String)
  LogAndContinue(reason: String)
  NoAction
}

/// Parse a RuleResult decision string into a typed Action.
pub fn decision_to_action(result: RuleResult) -> Action {
  case result.decision {
    "EmergencyStop" -> EmergencyStop(result.reason)
    "Restart" -> RestartContainer("unknown", result.reason)
    "RestartContainer" -> RestartContainer("unknown", result.reason)
    "HeavyThrottle" -> ScaleDown(result.reason)
    "Wait" -> ScaleDown(result.reason)
    "EscalateToLLM" -> Escalate("L7", result.reason)
    "EscalateToHuman" -> Escalate("L0", result.reason)
    "Compliant" -> NoAction
    "NoAction" -> NoAction
    "Pass" -> NoAction
    "Skip" -> NoAction
    _ -> LogAndContinue(result.reason)
  }
}

/// Dispatch an action — execute the side effect.
/// Returns a description of what was done.
pub fn dispatch(action: Action) -> String {
  case action {
    EmergencyStop(reason) -> {
      zenoh_otel.emit(Cockpit, "emergency_stop", zenoh_otel.Act)
      let _ =
        client.put_nif(
          "indrajaal/l0/const/emergency",
          "{\"action\":\"stop\",\"reason\":\"" <> reason <> "\"}",
        )
      "EMERGENCY STOP: " <> reason
    }
    RestartContainer(name, reason) -> {
      zenoh_otel.emit(Podman, "restart", zenoh_otel.Act)
      let _ =
        client.put_nif(
          "indrajaal/l4/system/restart",
          "{\"container\":\"" <> name <> "\",\"reason\":\"" <> reason <> "\"}",
        )
      "RESTART " <> name <> ": " <> reason
    }
    ScaleDown(reason) -> {
      zenoh_otel.emit(Dashboard, "scale_down", zenoh_otel.Decide)
      "SCALE DOWN: " <> reason
    }
    Escalate(level, reason) -> {
      zenoh_otel.emit(Agents, "escalate", zenoh_otel.Decide)
      let _ =
        client.put_nif(
          "indrajaal/l5/cog/escalate",
          "{\"level\":\"" <> level <> "\",\"reason\":\"" <> reason <> "\"}",
        )
      "ESCALATE to " <> level <> ": " <> reason
    }
    LogAndContinue(reason) -> {
      "LOG: " <> reason
    }
    NoAction -> "NO_ACTION"
  }
}

/// Evaluate rules and dispatch the resulting action in one call.
/// This is the primary entry point for OODA Decide→Act coupling.
pub fn evaluate_and_dispatch(
  domain_name: String,
  rules_grl: String,
  facts: List(Fact),
) -> String {
  let result = engine.evaluate(domain_name, rules_grl, facts)
  let action = decision_to_action(result)
  dispatch(action)
}
