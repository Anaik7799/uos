pub type ChaosAttack {
  ContainerAssault(name: String, mode: String)
  ZenohFlood(topic: String, count: Int)
  HeartbeatSabotage(target: String)
  ResourceDrain(cpu_percent: Int, duration_ms: Int)
}

pub type Antibody {
  Antibody(id: String, target_pattern: String, reason: String, expires_at: Int)
}

pub type ImmuneEvent {
  AntibodySynthesized(id: String, pattern: String)
  AttackBlocked(id: String, reason: String)
  SafetyViolationDetected(reason: String)
  AutomatedRollbackInitiated(target: String)
}
