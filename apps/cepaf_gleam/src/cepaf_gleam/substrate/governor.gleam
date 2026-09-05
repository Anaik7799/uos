pub type ResourceMetrics {
  ResourceMetrics(
    cpu_usage_pct: Float,
    memory_usage_mb: Int,
    container_count: Int,
  )
}

pub type GovernorAction {
  Expand
  Contract
  Maintain
  EmergencyHalt(reason: String)
}

pub fn evaluate_metabolic_state(metrics: ResourceMetrics) -> GovernorAction {
  let cpu_limit = 85.0
  let memory_limit = 32_768
  // 32GB

  case metrics.cpu_usage_pct >. cpu_limit {
    True -> Contract
    False -> {
      case metrics.memory_usage_mb > memory_limit {
        True -> EmergencyHalt("Memory exhaustion detected")
        False -> {
          case metrics.cpu_usage_pct <. 40.0 {
            True -> Expand
            False -> Maintain
          }
        }
      }
    }
  }
}
