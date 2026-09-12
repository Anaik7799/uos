//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/ui/lustre/mini_app</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-OPENCLAW-001, SC-HMI-010</stamp-controls></compliance>
//// </c3i-module>
////
//// Mobile-optimized Lustre views for Telegram Mini App.
//// Reuses existing page Model types but renders with TeleNative patterns.
//// Touch-optimized, 8pt grid, large targets (60px+), dark mode priority.
//// STAMP: SC-GLM-UI-001, SC-OPENCLAW-001, SC-HMI-010

import cepaf_gleam/ui/lustre/app
import cepaf_gleam/ui/lustre/cockpit_view
import cepaf_gleam/ui/lustre/config
import cepaf_gleam/ui/lustre/conversation
import cepaf_gleam/ui/lustre/federation
import cepaf_gleam/ui/lustre/fmea_report
import cepaf_gleam/ui/lustre/health_grid
import cepaf_gleam/ui/lustre/immune
import cepaf_gleam/ui/lustre/inference_tier
import cepaf_gleam/ui/lustre/planning
import cepaf_gleam/ui/lustre/podman
import cepaf_gleam/ui/lustre/telemetry
import cepaf_gleam/ui/lustre/verification
import cepaf_gleam/ui/lustre/zenoh_browser
import gleam/int
import gleam/list
import gleam/option
import gleam/string

// =============================================================================
// Dashboard — System overview with status hero + health cards
// =============================================================================

pub fn dashboard_view() -> String {
  let model = app.init()
  let health_label = case model.dark_cockpit {
    True -> "Dark Cockpit Active"
    False -> "Systems Online"
  }

  "<div class=\"tg-status-hero\">C3I Mesh</div>
<div class=\"tg-status-sub\">"
  <> health_label
  <> "</div>

<div class=\"tg-grid-2\">
  <div class=\"tg-card\">
    <div class=\"tg-metric-label\">Containers</div>
    <div class=\"tg-metric-value\">17</div>
  </div>
  <div class=\"tg-card\">
    <div class=\"tg-metric-label\">Health</div>
    <div class=\"tg-metric-value tg-badge-ok\">OK</div>
  </div>
  <div class=\"tg-card\">
    <div class=\"tg-metric-label\">Agents</div>
    <div class=\"tg-metric-value\">5</div>
  </div>
  <div class=\"tg-card\">
    <div class=\"tg-metric-label\">Zenoh</div>
    <div class=\"tg-metric-value tg-badge-ok\">UP</div>
  </div>
</div>

<div class=\"tg-section-title\">Quick Actions</div>
<div class=\"tg-card\">
  <a href=\"/mini-app/health\" class=\"tg-list-cell\" data-navigate=\"/mini-app/health\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Health Grid</div>
      <div class=\"tg-list-subtitle\">Device status overview</div>
    </div>
    <span class=\"tg-list-chevron\">&rsaquo;</span>
  </a>
  <a href=\"/mini-app/alerts\" class=\"tg-list-cell\" data-navigate=\"/mini-app/alerts\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Active Alerts</div>
      <div class=\"tg-list-subtitle\">Monitor and acknowledge</div>
    </div>
    <span class=\"tg-list-chevron\">&rsaquo;</span>
  </a>
  <a href=\"/mini-app/tasks\" class=\"tg-list-cell\" data-navigate=\"/mini-app/tasks\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Task Board</div>
      <div class=\"tg-list-subtitle\">Planning and tracking</div>
    </div>
    <span class=\"tg-list-chevron\">&rsaquo;</span>
  </a>
  <a href=\"/mini-app/containers\" class=\"tg-list-cell\" data-navigate=\"/mini-app/containers\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Containers</div>
      <div class=\"tg-list-subtitle\">Podman swarm management</div>
    </div>
    <span class=\"tg-list-chevron\">&rsaquo;</span>
  </a>
</div>"
}

// =============================================================================
// Health Grid — Device list cells with status badges
// =============================================================================

pub fn health_grid_view() -> String {
  let model = health_grid.init()
  "<div class=\"tg-status-hero\">Health Grid</div>
<div class=\"tg-status-sub\">Device monitoring — "
  <> int.to_string(list.length(model.devices))
  <> " devices</div>
<div class=\"tg-card\">
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-icon tg-badge-ok\">&#9679;</div>
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">All Devices</div>
      <div class=\"tg-list-subtitle\">No devices reporting issues</div>
    </div>
  </div>
</div>
<div class=\"tg-hint\" style=\"padding: 16px 0;\">Connect to Zenoh mesh for live device data.</div>"
}

// =============================================================================
// Cockpit — Alert management with large action buttons
// =============================================================================

pub fn cockpit_view() -> String {
  let model = cockpit_view.init()
  let alarm_count = list.length(model.alarms)

  "<div class=\"tg-status-hero\">"
  <> case alarm_count > 0 {
    True -> int.to_string(alarm_count) <> " Active Alerts"
    False -> "All Clear"
  }
  <> "</div>
<div class=\"tg-status-sub\">Cockpit alert management</div>

<div class=\"tg-card\">"
  <> case alarm_count {
    0 ->
      "<div class=\"tg-hint\" style=\"padding: 16px; text-align: center;\">No active alarms. System nominal.</div>"
    _ ->
      "<div class=\"tg-list-cell\">
      <div class=\"tg-list-icon tg-badge-warn\">&#9888;</div>
      <div class=\"tg-list-body\">
        <div class=\"tg-list-title\">"
      <> int.to_string(alarm_count)
      <> " alarms pending</div>
        <div class=\"tg-list-subtitle\">Tap to review and acknowledge</div>
      </div>
    </div>"
  }
  <> "</div>

<div style=\"padding: 16px 0;\">
  <button class=\"tg-btn tg-action-btn\">Acknowledge All</button>
</div>"
}

// =============================================================================
// Immune — Threat list with Mara toggle
// =============================================================================

pub fn immune_view() -> String {
  let model = immune.init()
  "<div class=\"tg-status-hero\">Immune System</div>
<div class=\"tg-status-sub\">"
  <> int.to_string(list.length(model.active_attacks))
  <> " active threats | Mara: "
  <> case model.mara_running {
    True -> "Running"
    False -> "Idle"
  }
  <> "</div>

<div class=\"tg-card\">
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-icon tg-badge-ok\">&#128737;</div>
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Antibodies: "
  <> int.to_string(list.length(model.antibodies))
  <> "</div>
      <div class=\"tg-list-subtitle\">Active defense agents</div>
    </div>
  </div>
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-icon tg-badge-warn\">&#128270;</div>
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Recent Events: "
  <> int.to_string(list.length(model.recent_events))
  <> "</div>
      <div class=\"tg-list-subtitle\">Threat detection log</div>
    </div>
  </div>
</div>

<div style=\"padding: 16px 0;\">
  <button class=\"tg-btn tg-btn-tonal\">Toggle Mara Chaos Engine</button>
</div>"
}

// =============================================================================
// Planning — Task list cells
// =============================================================================

pub fn planning_view() -> String {
  let model = planning.init()
  "<div class=\"tg-status-hero\">Tasks</div>
<div class=\"tg-status-sub\">"
  <> int.to_string(list.length(model.tasks))
  <> " tasks</div>

<div class=\"tg-card\">
  <div class=\"tg-hint\" style=\"padding: 8px 0;\">No tasks loaded. Connect to Smriti DB for live data.</div>
</div>"
}

// =============================================================================
// Inference Tier — AI pipeline status
// =============================================================================

pub fn inference_view() -> String {
  let model = inference_tier.init()
  "<div class=\"tg-status-hero\">Inference</div>
<div class=\"tg-status-sub\">6-tier hedged cascade | "
  <> case model.hedged_mode {
    True -> "Hedged mode ON"
    False -> "Sequential mode"
  }
  <> "</div>

<div class=\"tg-grid-2\">
  <div class=\"tg-card\">
    <div class=\"tg-metric-label\">Requests</div>
    <div class=\"tg-metric-value\">"
  <> int.to_string(model.total_requests)
  <> "</div>
  </div>
  <div class=\"tg-card\">
    <div class=\"tg-metric-label\">Avg Latency</div>
    <div class=\"tg-metric-value\">"
  <> int.to_string(model.avg_latency_ms)
  <> "ms</div>
  </div>
</div>

<div class=\"tg-section-title\">Tiers</div>
<div class=\"tg-card\">"
  <> string.join(
    list.index_map(model.tiers, fn(tier, idx) {
      "<div class=\"tg-list-cell\">
      <div class=\"tg-list-body\">
        <div class=\"tg-list-title\">Tier "
      <> int.to_string(idx + 1)
      <> ": "
      <> tier.name
      <> "</div>
        <div class=\"tg-list-subtitle\">"
      <> tier.model
      <> " | "
      <> int.to_string(tier.latency_ms)
      <> "ms</div>
      </div>
      <span class=\"tg-badge "
      <> case tier.circuit {
        inference_tier.CircuitClosed -> "tg-badge-ok"
        inference_tier.CircuitOpen(_) -> "tg-badge-crit"
        inference_tier.CircuitHalfOpen -> "tg-badge-warn"
      }
      <> "\">"
      <> inference_tier.circuit_state_label(tier.circuit)
      <> "</span>
    </div>"
    }),
    "",
  )
  <> "</div>"
}

// =============================================================================
// Conversation — Chat history
// =============================================================================

pub fn conversation_view() -> String {
  let model = conversation.init()
  "<div class=\"tg-status-hero\">Chat History</div>
<div class=\"tg-status-sub\">Chat "
  <> model.chat_id
  <> " | Max "
  <> int.to_string(model.max_messages)
  <> " messages</div>
<div class=\"tg-card\">
  <div class=\"tg-hint\" style=\"padding: 8px 0;\">No messages loaded. Connect for live conversation data.</div>
</div>"
}

// =============================================================================
// Config — Mesh configuration
// =============================================================================

pub fn config_view() -> String {
  let model = config.init()
  "<div class=\"tg-status-hero\">Configuration</div>
<div class=\"tg-status-sub\">Quorum: "
  <> int.to_string(model.quorum_size)
  <> " | Valid: "
  <> case model.is_valid {
    True -> "Yes"
    False -> "No"
  }
  <> "</div>

<div class=\"tg-card\">
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Containers</div>
      <div class=\"tg-list-subtitle\">"
  <> int.to_string(list.length(model.containers))
  <> " configured</div>
    </div>
  </div>
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Networks</div>
      <div class=\"tg-list-subtitle\">"
  <> int.to_string(list.length(model.networks))
  <> " configured</div>
    </div>
  </div>
</div>"
}

// =============================================================================
// Podman — Container list with start/stop
// =============================================================================

pub fn podman_view() -> String {
  let model = podman.init()
  "<div class=\"tg-status-hero\">Containers</div>
<div class=\"tg-status-sub\">"
  <> int.to_string(list.length(model.containers))
  <> " containers | "
  <> int.to_string(list.length(model.images))
  <> " images</div>

<div class=\"tg-card\">
  <div class=\"tg-hint\" style=\"padding: 8px 0;\">Connect to Podman for live container data.</div>
</div>"
}

// =============================================================================
// Federation — HA status + peer count
// =============================================================================

pub fn federation_view() -> String {
  let model = federation.init()
  "<div class=\"tg-status-hero\">Federation</div>
<div class=\"tg-status-sub\">HA Role: "
  <> federation.ha_role_label(model.ha.role)
  <> " | Peers: "
  <> int.to_string(federation.total_peer_count(model))
  <> "</div>

<div class=\"tg-card\">
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Lease TTL</div>
      <div class=\"tg-list-subtitle\">"
  <> int.to_string(model.ha.lease_ttl_ms)
  <> "ms</div>
    </div>
  </div>
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Missed Heartbeats</div>
      <div class=\"tg-list-subtitle\">"
  <> int.to_string(model.ha.missed_heartbeats)
  <> "</div>
    </div>
  </div>
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">All Attested</div>
      <div class=\"tg-list-subtitle\">"
  <> case federation.all_attested_check(model) {
    True -> "Yes"
    False -> "No"
  }
  <> "</div>
    </div>
  </div>
</div>"
}

// =============================================================================
// Verification — Integrity check
// =============================================================================

pub fn verification_view() -> String {
  let model = verification.init()
  "<div class=\"tg-status-hero\">Verification</div>
<div class=\"tg-status-sub\">DAG: "
  <> int.to_string(model.dag_node_count)
  <> " nodes, "
  <> int.to_string(model.dag_edge_count)
  <> " edges</div>

<div class=\"tg-card\">
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Running</div>
      <div class=\"tg-list-subtitle\">"
  <> case model.running {
    True -> "Verification in progress"
    False -> "Idle"
  }
  <> "</div>
    </div>
  </div>
</div>

<div style=\"padding: 16px 0;\">
  <button class=\"tg-btn\">Run Verification</button>
</div>"
}

// =============================================================================
// FMEA Report — Risk analysis
// =============================================================================

pub fn fmea_view() -> String {
  let model = fmea_report.init()
  "<div class=\"tg-status-hero\">FMEA Report</div>
<div class=\"tg-status-sub\">Total RPN: "
  <> int.to_string(model.total_rpn)
  <> " | Critical: "
  <> int.to_string(model.critical_count)
  <> "</div>

<div class=\"tg-card\">
  <div class=\"tg-hint\" style=\"padding: 8px 0;\">Load FMEA data for failure mode analysis.</div>
</div>"
}

// =============================================================================
// Telemetry — Metrics overview
// =============================================================================

pub fn telemetry_view() -> String {
  let model = telemetry.init()
  "<div class=\"tg-status-hero\">Telemetry</div>
<div class=\"tg-status-sub\">"
  <> int.to_string(list.length(model.spans))
  <> " spans | "
  <> int.to_string(model.active_traces)
  <> " active traces</div>

<div class=\"tg-card\">
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Log Level</div>
      <div class=\"tg-list-subtitle\">"
  <> case model.log_level {
    telemetry.Debug -> "DEBUG"
    telemetry.Info -> "INFO"
    telemetry.Warning -> "WARNING"
    telemetry.Error -> "ERROR"
  }
  <> "</div>
    </div>
  </div>
</div>"
}

// =============================================================================
// Zenoh Browser — Topic inspection
// =============================================================================

pub fn zenoh_browser_view() -> String {
  let model = zenoh_browser.init()
  "<div class=\"tg-status-hero\">Zenoh Browser</div>
<div class=\"tg-status-sub\">Topic inspection and monitoring</div>

<div class=\"tg-card\">
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Topics</div>
      <div class=\"tg-list-subtitle\">"
  <> int.to_string(list.length(model.root))
  <> " root nodes</div>
    </div>
  </div>
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Subscriptions</div>
      <div class=\"tg-list-subtitle\">"
  <> int.to_string(list.length(model.subscribed))
  <> " active</div>
    </div>
  </div>
  <div class=\"tg-list-cell\">
    <div class=\"tg-list-body\">
      <div class=\"tg-list-title\">Selected</div>
      <div class=\"tg-list-subtitle\">"
  <> case model.selected_topic {
    option.Some(t) -> t
    option.None -> "None"
  }
  <> "</div>
    </div>
  </div>
</div>"
}
