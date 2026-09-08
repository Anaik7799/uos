//// Release evidence lifecycle using the existing UOS FPP metamodel/interpreter.
//// Denotation: candidate × waiting stage × evidence -> next observation or error.
//// Action labels are observations. This module never performs a runtime effect.

import cepaf_gleam/fpp/domain as d
import cepaf_gleam/fpp/interp as i
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub const stages = [
  "intake", "design", "source", "build", "test", "package", "staging",
  "authorize", "deploy", "observe", "recover", "close",
]

pub opaque type Release {
  Release(candidate: String, state: i.MachineState)
}

pub type Receipt {
  Receipt(
    candidate: String,
    stage: String,
    passed: Bool,
    observed_ms: Int,
    expires_ms: Int,
    digest: String,
  )
}

/// Declarative intent is data. Interpreting it changes the evidence model only.
pub type Intent {
  SubmitEvidence(Receipt)
  ReportFault
  ReportRestoration(Receipt)
}

pub fn interpret(
  run: Release,
  intent: Intent,
  now_ms: Int,
) -> Result(Release, String) {
  case intent {
    SubmitEvidence(receipt) -> advance(run, receipt, now_ms)
    ReportFault -> fault(run)
    ReportRestoration(receipt) -> restored(run, receipt, now_ms)
  }
}

fn hex(value: String, size: Int) -> Bool {
  string.length(value) == size
  && list.all(string.to_graphemes(value), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}

pub fn new(candidate: String) -> Result(Release, String) {
  case hex(candidate, 40) {
    False -> Error("invalid candidate")
    True ->
      i.init_machine(machine()) |> result.map(fn(s) { Release(candidate, s) })
  }
}

pub fn phase(run: Release) -> String {
  run.state.current
}

pub fn machine() -> d.StateMachine {
  let waiting =
    list.index_map(stages, fn(stage, index) {
      let target =
        list.drop(stages, index + 1) |> list.first |> result.unwrap("completed")
      let fault = case stage == "deploy" || stage == "observe" {
        True -> "recovering"
        False -> "held"
      }
      d.State(stage, [], [], [
        d.Transition(
          "pass:" <> stage,
          Some("evidence_valid"),
          ["record_evidence"],
          d.ToState(target),
        ),
        d.Transition("fault", None, ["record_failure"], d.ToState(fault)),
      ])
    })
  d.InternalMachine(
    "ReleaseLifecycle",
    list.append(list.map(stages, fn(s) { d.SignalDef("pass:" <> s, None) }), [
      d.SignalDef("fault", None),
      d.SignalDef("restored", None),
    ]),
    ["evidence_valid"],
    ["record_evidence", "record_failure", "record_rollback"],
    list.append(waiting, [
      d.State("completed", [], [], []),
      d.State("held", [], [], []),
      d.State("recovering", [], [], [
        d.Transition(
          "restored",
          Some("evidence_valid"),
          ["record_rollback"],
          d.ToState("rolled_back"),
        ),
      ]),
      d.State("rolled_back", [], [], []),
    ]),
    [],
    #([], "intake"),
  )
}

pub fn advance(
  run: Release,
  receipt: Receipt,
  now_ms: Int,
) -> Result(Release, String) {
  let valid =
    receipt.candidate == run.candidate
    && receipt.stage == phase(run)
    && receipt.passed
    && hex(receipt.digest, 64)
    && receipt.observed_ms >= 0
    && receipt.observed_ms <= now_ms
    && now_ms <= receipt.expires_ms
    && receipt.expires_ms >= receipt.observed_ms
    && receipt.expires_ms - receipt.observed_ms <= 3_600_000
  case valid && list.contains(stages, receipt.stage) {
    False -> Error("invalid, stale, failed or out-of-order evidence")
    True ->
      i.dispatch_signal(
        machine(),
        [#("evidence_valid", True)],
        run.state,
        "pass:" <> receipt.stage,
      )
      |> result.map(fn(s) { Release(run.candidate, s) })
  }
}

pub fn fault(run: Release) -> Result(Release, String) {
  i.dispatch_signal(machine(), [], run.state, "fault")
  |> result.map(fn(s) { Release(run.candidate, s) })
}

/// Restoration evidence must name the interrupted candidate; the external
/// executor separately validates the target rollback artifact and observed PID.
pub fn restored(
  run: Release,
  receipt: Receipt,
  now_ms: Int,
) -> Result(Release, String) {
  case
    phase(run) == "recovering"
    && receipt.stage == "recover"
    && receipt.candidate == run.candidate
    && receipt.passed
    && hex(receipt.digest, 64)
    && receipt.observed_ms >= 0
    && receipt.observed_ms <= now_ms
    && now_ms <= receipt.expires_ms
    && receipt.expires_ms - receipt.observed_ms <= 3_600_000
  {
    False -> Error("rollback not verified")
    True ->
      i.dispatch_signal(
        machine(),
        [#("evidence_valid", True)],
        run.state,
        "restored",
      )
      |> result.map(fn(s) { Release(run.candidate, s) })
  }
}
