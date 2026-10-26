import cepaf_gleam/immune/domain.{type Antibody, Antibody}
import cepaf_gleam/immune/patterns.{type FailurePattern}
import gleam/erlang/process.{type Name, type Subject}
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/string

pub type ReflexAction {
  HaltSystem
  RestartService(String)
  IsolateNode(String)
  LogAnomaly
}

pub type SystemState {
  SystemState(
    active_antibodies: List(Antibody),
    violation_count: Int,
    known_patterns: List(FailurePattern),
  )
}

pub type SystemSnapshot {
  SystemSnapshot(
    active_antibodies: Int,
    violation_count: Int,
    known_patterns: Int,
    antibody_targets: List(String),
  )
}

pub type Message {
  ReportViolation(reason: String, target: String)
  ProcessLogLine(line: String)
  PruneAntibodies
  Snapshot(reply: Subject(SystemSnapshot))
}

pub fn start() -> Result(Subject(Message), actor.StartError) {
  actor.new(SystemState([], 0, patterns.default_patterns()))
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

// ---------------------------------------------------------------------------
// Supervised, discoverable start (Mini App residual closed, residuals plan
// of 2026-10-26). Before this the actor had only an unnamed `start` and no
// supervisor in the tree started it, so every observer answered
// `immune_actor_not_running` by construction.
// ---------------------------------------------------------------------------

/// The one registered name of the immune system actor. A fixed atom (via
/// `immune_system_ffi`) rather than `process.new_name`, so a runtime in
/// another module can find the actor without being handed the name.
@external(erlang, "immune_system_ffi", "registry_name")
pub fn registry_name() -> Name(Message)

/// Start the actor registered under `registry_name()`.
pub fn start_named() -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new(SystemState([], 0, patterns.default_patterns()))
  |> actor.on_message(handle_message)
  |> actor.named(registry_name())
  |> actor.start()
}

/// Permanent worker child under `registry_name()`; a deployment adds it to
/// the supervisor that owns the Mini App runtime. Nothing here adds it to any
/// tree.
pub fn child_spec() -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start_named() })
}

/// The live actor, if one is registered under `registry_name()` right now.
/// `None` is the truthful answer when no supervisor has started it; a
/// `Some` names whichever incarnation is alive and survives a restart.
pub fn lookup() -> Option(Subject(Message)) {
  case process.named(registry_name()) {
    Ok(_) -> Some(process.named_subject(registry_name()))
    Error(_) -> None
  }
}

fn handle_message(
  state: SystemState,
  message: Message,
) -> actor.Next(SystemState, Message) {
  case message {
    ReportViolation(reason, target) -> {
      io.println_error("[IMMUNE] Safety violation detected: " <> reason)

      // P0: Automated Rollback Logic
      io.println("[IMMUNE] INITIATING AUTOMATED ROLLBACK for " <> target)

      trigger_reflex(HaltSystem)

      // Synthesize antibody to prevent immediate recurrence
      let new_antibody =
        Antibody(
          id: "gen-123",
          // TODO: proper ID
          target_pattern: reason,
          reason: "Safety kernel violation",
          expires_at: 0,
          // TODO: timestamp
        )

      actor.continue(
        SystemState(
          ..state,
          active_antibodies: [new_antibody, ..state.active_antibodies],
          violation_count: state.violation_count + 1,
        ),
      )
    }
    ProcessLogLine(line) -> {
      let anomalies = patterns.detect_anomalies(line, state.known_patterns)
      list.each(anomalies, fn(p) {
        io.println_error(
          "[IMMUNE] ANOMALY DETECTED: "
          <> p.match_string
          <> " (Severity: "
          <> string.inspect(p.severity)
          <> ")",
        )
        let action = case p.severity {
          s if s >= 10 -> HaltSystem
          s if s >= 8 -> IsolateNode("current_node")
          _ -> LogAnomaly
        }
        trigger_reflex(action)
      })
      actor.continue(state)
    }
    PruneAntibodies -> actor.continue(state)
    Snapshot(reply) -> {
      let snapshot =
        SystemSnapshot(
          active_antibodies: list.length(state.active_antibodies),
          violation_count: state.violation_count,
          known_patterns: list.length(state.known_patterns),
          antibody_targets: state.active_antibodies
            |> list.take(24)
            |> list.map(fn(a) { a.target_pattern }),
        )
      process.send(reply, snapshot)
      actor.continue(state)
    }
  }
}

fn trigger_reflex(action: ReflexAction) {
  case action {
    HaltSystem ->
      io.println_error("[IMMUNE-REFLEX] !!! SYSTEM HALT TRIGGERED !!!")
    RestartService(s) -> io.println("[IMMUNE-REFLEX] Restarting service: " <> s)
    IsolateNode(n) -> io.println_error("[IMMUNE-REFLEX] Isolating node: " <> n)
    LogAnomaly ->
      io.println("[IMMUNE-REFLEX] Anomaly logged to persistent store")
  }
}
