import gleam/option.{type Option}

// =============================================================================
// domain.gleam - Shared Cockpit Domain Types
// =============================================================================
// Ported from: Cepaf.Cockpit.Domain.fs
// Compliance: NASA-STD-3000, NUREG-0700, MIL-STD-1472H
// =============================================================================

pub type NodeId =
  String

pub type ZoneId =
  String

pub type AlarmId =
  String

pub type CommandId =
  String

pub type Trend {
  Rising
  RisingFast
  Falling
  FallingFast
  Stable
}

pub type ConnectionStatus {
  Connected
  Stale
  Degraded
  Disconnected
}

pub type AlarmLevel {
  Normal
  Advisory
  Caution
  Warning
  Critical
}

pub type CommandState {
  Idle
  Armed
  Executing
  Acknowledged
  Failed
}

pub type NodeRole {
  Supervisor
  Controller
  Worker
  Observer
  Gateway
}

pub type InsightType {
  Anomaly
  Prediction
  Recommendation
  Correlation
  RootCause
  Summary
}

pub type ViewMode {
  Overview
  Mesh
  Alarms
  Commands
  AI
  Dashboard
  NodeDetail
  AlarmCenter
  Topology
  Timeline
  AiAssistant
  Federation
  Economics
}

pub type MetricThresholds {
  MetricThresholds(
    advisory_low: Option(Float),
    advisory_high: Option(Float),
    caution_low: Option(Float),
    caution_high: Option(Float),
    warning_low: Option(Float),
    warning_high: Option(Float),
  )
}

pub type SmartMetric {
  SmartMetric(
    value: Float,
    previous_value: Option(Float),
    last_updated: Int,
    // Timestamp
    trend: Trend,
    level: AlarmLevel,
    thresholds: Option(MetricThresholds),
    unit: String,
    label: String,
    sparkline: List(Float),
  )
}

pub type MeshNode {
  MeshNode(
    id: NodeId,
    name: String,
    zone: ZoneId,
    role: NodeRole,
    status: ConnectionStatus,
    cpu: SmartMetric,
    memory: SmartMetric,
    battery: Option(SmartMetric),
    network_latency: SmartMetric,
    capabilities: List(String),
    health_score: SmartMetric,
    location: Option(#(Float, Float)),
    ai_insight: Option(String),
    ai_insight_updated_at: Option(Int),
  )
}

pub type Alarm {
  Alarm(
    id: AlarmId,
    node_id: NodeId,
    level: AlarmLevel,
    category: String,
    message: String,
    details: Option(String),
    occurred_at: Int,
    acknowledged_at: Option(Int),
    acknowledged_by: Option(String),
    auto_clearable: Bool,
  )
}

pub type MeshCommand {
  PowerOff
  PowerOn
  Restart
  Hibernate
  IsolateNetwork
  ResumeNetwork
  SetLoadBalancer(Int)
  ForceHealthCheck
  ClearAlarms
  Custom(String, BitArray)
}

pub type CommandRecord {
  CommandRecord(
    id: CommandId,
    target_node_id: NodeId,
    command: MeshCommand,
    state: CommandState,
    armed_at: Option(Int),
    executed_at: Option(Int),
    acknowledged_at: Option(Int),
    error_message: Option(String),
    requires_confirmation: Bool,
  )
}

pub type AiInsight {
  AiInsight(
    id: String,
    insight_type: InsightType,
    level: AlarmLevel,
    title: String,
    description: String,
    related_nodes: List(NodeId),
    related_alarms: List(AlarmId),
    confidence: Float,
    generated_at: Int,
    expires_at: Option(Int),
    action_items: List(String),
  )
}

pub type AutomationState {
  NormalOps
  AutoHealing
  AutoScaling
  ManualOverride
  DegradedMode
  EmergencyStop
  AutoExecuting
}

pub type GitCommit {
  GitCommit(hash: String, message: String, author: String, timestamp: Int)
}
