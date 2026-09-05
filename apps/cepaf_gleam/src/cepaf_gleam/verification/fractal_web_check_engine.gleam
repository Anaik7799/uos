import gleam/list

pub type CheckSurface {
  LustreWeb
  WispApi
  AnsiTui
  AgUiSse
  MozZenoh
}

pub type CheckSeverity {
  Info
  Warning
  Critical
  Blocker
}

pub type CheckStatus {
  CheckPass
  CheckFail
}

pub type WebCheckSpec {
  WebCheckSpec(
    id: String,
    name: String,
    surface: CheckSurface,
    layer: Int,
    severity: CheckSeverity,
    predicate: fn() -> Bool,
  )
}

pub type CheckEvaluation {
  CheckEvaluation(
    check_id: String,
    name: String,
    status: CheckStatus,
    surface: CheckSurface,
    layer: Int,
    severity: CheckSeverity,
  )
}

pub fn evaluate_single_check(spec: WebCheckSpec) -> CheckEvaluation {
  let passed = spec.predicate()
  let status = case passed {
    True -> CheckPass
    False -> CheckFail
  }
  CheckEvaluation(
    check_id: spec.id,
    name: spec.name,
    status: status,
    surface: spec.surface,
    layer: spec.layer,
    severity: spec.severity,
  )
}

pub fn evaluate_check_suite(specs: List(WebCheckSpec)) -> List(CheckEvaluation) {
  list.map(specs, evaluate_single_check)
}

pub fn check_suite_passed(evaluations: List(CheckEvaluation)) -> Bool {
  list.all(evaluations, fn(eval) { eval.status == CheckPass })
}
