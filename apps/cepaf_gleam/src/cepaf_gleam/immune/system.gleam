import cepaf_gleam/immune/domain.{type Antibody, Antibody}
import cepaf_gleam/immune/patterns.{type FailurePattern}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/otp/actor
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

pub type Message {
  ReportViolation(reason: String, target: String)
  ProcessLogLine(line: String)
  PruneAntibodies
}

pub fn start() -> Result(Subject(Message), actor.StartError) {
  actor.new(SystemState([], 0, patterns.default_patterns()))
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
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
