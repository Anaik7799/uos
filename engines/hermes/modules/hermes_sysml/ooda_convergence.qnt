module ooda_convergence {
  var state: str
  var anomaly: bool

  action init = all {
    state' = "IDLE",
    anomaly' = false,
  }

  action step_normal = all {
    not(anomaly),
    any {
      all { state == "IDLE", state' = "OBSERVE" },
      all { state == "OBSERVE", state' = "ORIENT" },
      all { state == "ORIENT", state' = "DECIDE" },
      all { state == "DECIDE", state' = "ACT" },
      all { state == "ACT", state' = "IDLE" }
    },
    // Anomaly can occur non-deterministically
    any { anomaly' = true, anomaly' = false }
  }

  action step_anomaly = all {
    anomaly,
    state' = "OBSERVE",
    anomaly' = false
  }

  action step = any { step_normal, step_anomaly }

  val valid_state = Set("IDLE", "OBSERVE", "ORIENT", "DECIDE", "ACT").contains(state)
}
