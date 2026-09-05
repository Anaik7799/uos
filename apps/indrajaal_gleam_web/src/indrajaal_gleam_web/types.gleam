import gleam/option.{type Option}
import cepaf_gleam/cockpit/domain as cockpit

pub type Page {
  Dashboard
  Alarms
  Guardian
  Sentinel
  TestEvolution
  Video
  AccessControl
  Analytics
  Compliance
  Copilot
  Register
  Devices
  Settings
  Singularity
}

pub type WebConnectionState {
  Connecting
  Connected
  Reconnecting
  Disconnected
  Error(String)
}

pub type SystemHealthSummary {
  SystemHealthSummary(
    overall_health: Float,
    health_trend: cockpit.Trend,
    active_alarms: Int,
    critical_alarms: Int,
    connected_nodes: Int,
    total_nodes: Int,
    pending_proposals: Int,
    threat_level: cockpit.AlarmLevel,
    last_update: Int,
    connection_state: WebConnectionState,
  )
}

pub type GuardianProposal {
  GuardianProposal(
    id: String,
    title: String,
    description: String,
    category: String,
    severity: cockpit.AlarmLevel,
    proposed_by: String,
    proposed_at: Int,
    requires_approval: Bool,
    votes: Int,
    required_votes: Int,
  )
}

pub type SentinelThreat {
  SentinelThreat(
    id: String,
    category: String,
    severity: cockpit.AlarmLevel,
    description: String,
    source: String,
    detected_at: Int,
    mitigated: Bool,
    mitigated_at: Option(Int),
  )
}

pub type SingularityModel {
  SingularityModel(
    coverage: Float,
    active_vectors: Int,
    last_update: Int,
  )
}
