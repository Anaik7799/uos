//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/a2ui/wave1_catalog</module></identity>
////   <fractal-topology><layer>L2_COMPONENT</layer></fractal-topology>
////   <compliance><stamp-controls>SC-A2UI-002, SC-A2UI-004, SC-FILESIZE-001, SC-ULTRA-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Wave 1: 100 Homomorphic Tripartite UI components.
//// SC-ULTRA-001 #4 — Homomorphic Tripartite UI
//// विभागशः — Division into parts (Gita 18.41)
//// STAMP: SC-A2UI-002, SC-A2UI-004

import cepaf_gleam/a2ui/schema.{
  type ComponentSpec, BoolProp, ComponentSpec, EnumProp, FloatProp, IntProp,
  JsonProp, L0Constitutional, L1AtomicDebug, L2Component, L3Transaction,
  L4System, L5Cognitive, L6Ecosystem, L7Federation, PropSpec, StringProp,
}

/// Wave 1: 100 components across 7 groups.
pub fn components() -> List(#(String, ComponentSpec)) {
  list_layout()
  |> list_append(list_data())
  |> list_append(list_status())
  |> list_append(list_interactive())
  |> list_append(list_visualization())
  |> list_append(list_agent())
  |> list_append(list_safety())
}

fn list_append(a: List(t), b: List(t)) -> List(t) {
  case a {
    [] -> b
    [head, ..tail] -> [head, ..list_append(tail, b)]
  }
}

// --- LAYOUT (14) ---
fn list_layout() -> List(#(String, ComponentSpec)) {
  [
    #(
      "split_pane",
      ComponentSpec(
        "split_pane",
        L2Component,
        "Resizable two-panel layout",
        [PropSpec("ratio", FloatProp, "Split ratio 0.0-1.0")],
        [],
      ),
    ),
    #(
      "tab_strip",
      ComponentSpec(
        "tab_strip",
        L2Component,
        "Horizontal tab selector",
        [
          PropSpec("tabs", JsonProp, "Tab labels"),
          PropSpec("active", IntProp, "Active index"),
        ],
        [],
      ),
    ),
    #(
      "collapsible_panel",
      ComponentSpec(
        "collapsible_panel",
        L2Component,
        "Expandable/collapsible region",
        [
          PropSpec("title", StringProp, "Panel title"),
          PropSpec("expanded", BoolProp, "Initial state"),
        ],
        [],
      ),
    ),
    #(
      "fractal_breadcrumb",
      ComponentSpec(
        "fractal_breadcrumb",
        L1AtomicDebug,
        "L0-L7 fractal hierarchy breadcrumb",
        [PropSpec("layers", JsonProp, "Active layer path")],
        [],
      ),
    ),
    #(
      "grid_layout",
      ComponentSpec(
        "grid_layout",
        L2Component,
        "Configurable CSS grid layout",
        [
          PropSpec("columns", IntProp, "Column count"),
          PropSpec("gap", IntProp, "Gap pixels"),
        ],
        [],
      ),
    ),
    #(
      "scroll_viewport",
      ComponentSpec(
        "scroll_viewport",
        L2Component,
        "Virtualized scroll container",
        [PropSpec("max_height", IntProp, "Max height")],
        [],
      ),
    ),
    #(
      "sidebar_nav",
      ComponentSpec(
        "sidebar_nav",
        L2Component,
        "Vertical navigation sidebar grouped by layer",
        [],
        [],
      ),
    ),
    #(
      "modal_overlay",
      ComponentSpec(
        "modal_overlay",
        L0Constitutional,
        "Full-screen focus-trapping overlay",
        [PropSpec("visible", BoolProp, "Is visible")],
        [],
      ),
    ),
    #(
      "sticky_footer",
      ComponentSpec(
        "sticky_footer",
        L2Component,
        "Persistent bottom status bar",
        [PropSpec("content", StringProp, "Footer content")],
        [],
      ),
    ),
    #(
      "responsive_columns",
      ComponentSpec(
        "responsive_columns",
        L2Component,
        "Auto-reflowing column layout",
        [PropSpec("min_width", IntProp, "Min column width")],
        [],
      ),
    ),
    #(
      "layer_accordion",
      ComponentSpec(
        "layer_accordion",
        L2Component,
        "Accordion grouped by L0-L7 layers",
        [],
        [],
      ),
    ),
    #(
      "dashboard_tile",
      ComponentSpec(
        "dashboard_tile",
        L2Component,
        "Fixed-ratio dashboard tile",
        [PropSpec("title", StringProp, "Tile title")],
        [],
      ),
    ),
    #(
      "header_bar",
      ComponentSpec(
        "header_bar",
        L2Component,
        "Application header with holon identity",
        [PropSpec("holon_id", StringProp, "Holon identity")],
        [],
      ),
    ),
    #(
      "empty_state",
      ComponentSpec(
        "empty_state",
        L2Component,
        "Empty data placeholder with action",
        [
          PropSpec("message", StringProp, "Message"),
          PropSpec("icon", StringProp, "Icon"),
        ],
        [],
      ),
    ),
  ]
}

// --- DATA (16) ---
fn list_data() -> List(#(String, ComponentSpec)) {
  [
    #(
      "kv_table",
      ComponentSpec(
        "kv_table",
        L3Transaction,
        "Multi-row key-value display",
        [PropSpec("rows", JsonProp, "Key-value pairs")],
        [],
      ),
    ),
    #(
      "log_stream",
      ComponentSpec(
        "log_stream",
        L1AtomicDebug,
        "Scrolling severity-colored log viewer",
        [PropSpec("lines", JsonProp, "Log lines")],
        [PropSpec("max_lines", IntProp, "Max visible")],
      ),
    ),
    #(
      "json_tree",
      ComponentSpec(
        "json_tree",
        L1AtomicDebug,
        "Collapsible JSON object viewer",
        [PropSpec("data", JsonProp, "JSON object")],
        [],
      ),
    ),
    #(
      "triple_row",
      ComponentSpec(
        "triple_row",
        L3Transaction,
        "Subject-predicate-object triple",
        [
          PropSpec("subject", StringProp, "S"),
          PropSpec("predicate", StringProp, "P"),
          PropSpec("object", StringProp, "O"),
        ],
        [],
      ),
    ),
    #(
      "diff_viewer",
      ComponentSpec(
        "diff_viewer",
        L3Transaction,
        "RFC 6902 JSON patch diff viewer",
        [PropSpec("patches", JsonProp, "JSON patches")],
        [],
      ),
    ),
    #(
      "metric_counter",
      ComponentSpec(
        "metric_counter",
        L1AtomicDebug,
        "Large numeric metric with delta arrow",
        [
          PropSpec("value", FloatProp, "Current value"),
          PropSpec("label", StringProp, "Label"),
          PropSpec("unit", StringProp, "Unit"),
        ],
        [PropSpec("delta", FloatProp, "Change")],
      ),
    ),
    #(
      "histogram_bar",
      ComponentSpec(
        "histogram_bar",
        L4System,
        "Horizontal histogram with segments",
        [PropSpec("segments", JsonProp, "Segment data")],
        [],
      ),
    ),
    #(
      "version_vector_row",
      ComponentSpec(
        "version_vector_row",
        L7Federation,
        "Peer version vector display",
        [
          PropSpec("peer_id", StringProp, "Peer"),
          PropSpec("clock", IntProp, "Clock value"),
        ],
        [],
      ),
    ),
    #(
      "hash_display",
      ComponentSpec(
        "hash_display",
        L0Constitutional,
        "Truncated hash with copy and validity",
        [
          PropSpec("hash", StringProp, "Hash value"),
          PropSpec("valid", BoolProp, "Is valid"),
        ],
        [],
      ),
    ),
    #(
      "container_log_tail",
      ComponentSpec(
        "container_log_tail",
        L4System,
        "Tail-follow container log viewer",
        [
          PropSpec("container", StringProp, "Container name"),
          PropSpec("lines", JsonProp, "Log lines"),
        ],
        [],
      ),
    ),
    #(
      "sparql_result_grid",
      ComponentSpec(
        "sparql_result_grid",
        L3Transaction,
        "SPARQL query result table",
        [
          PropSpec("variables", JsonProp, "Variable names"),
          PropSpec("bindings", JsonProp, "Row bindings"),
        ],
        [],
      ),
    ),
    #(
      "event_payload_card",
      ComponentSpec(
        "event_payload_card",
        L5Cognitive,
        "AG-UI event detail card",
        [
          PropSpec("event_type", StringProp, "Event type"),
          PropSpec("payload", JsonProp, "Event payload"),
        ],
        [],
      ),
    ),
    #(
      "latency_gauge",
      ComponentSpec(
        "latency_gauge",
        L5Cognitive,
        "Color-banded latency display",
        [
          PropSpec("value_ms", FloatProp, "Latency ms"),
          PropSpec("budget_ms", FloatProp, "Budget ms"),
        ],
        [],
      ),
    ),
    #(
      "resource_usage_row",
      ComponentSpec(
        "resource_usage_row",
        L4System,
        "CPU/memory/disk usage row",
        [
          PropSpec("cpu", FloatProp, "CPU %"),
          PropSpec("memory", FloatProp, "Memory %"),
        ],
        [PropSpec("disk", FloatProp, "Disk %")],
      ),
    ),
    #(
      "task_detail_pane",
      ComponentSpec(
        "task_detail_pane",
        L3Transaction,
        "Full task detail view",
        [PropSpec("task_id", StringProp, "Task ID")],
        [],
      ),
    ),
    #(
      "proof_token_card",
      ComponentSpec(
        "proof_token_card",
        L0Constitutional,
        "Verification proof token",
        [
          PropSpec("hash", StringProp, "Token hash"),
          PropSpec(
            "result",
            EnumProp(["Verified", "Rejected", "Inconclusive"]),
            "Result",
          ),
        ],
        [],
      ),
    ),
  ]
}

// --- STATUS (18) ---
fn list_status() -> List(#(String, ComponentSpec)) {
  [
    #(
      "health_indicator",
      ComponentSpec(
        "health_indicator",
        L4System,
        "Colored health dot",
        [
          PropSpec(
            "status",
            EnumProp(["healthy", "degraded", "critical", "unknown"]),
            "Status",
          ),
        ],
        [],
      ),
    ),
    #(
      "connection_status",
      ComponentSpec(
        "connection_status",
        L6Ecosystem,
        "Connection indicator with latency",
        [
          PropSpec("connected", BoolProp, "Connected"),
          PropSpec("latency_ms", IntProp, "Latency"),
        ],
        [],
      ),
    ),
    #(
      "cockpit_mode_badge",
      ComponentSpec(
        "cockpit_mode_badge",
        L5Cognitive,
        "Dark cockpit mode display",
        [
          PropSpec(
            "mode",
            EnumProp(["dark", "dim", "normal", "bright", "emergency"]),
            "Mode",
          ),
        ],
        [],
      ),
    ),
    #(
      "quorum_indicator",
      ComponentSpec(
        "quorum_indicator",
        L7Federation,
        "Quorum status display",
        [
          PropSpec("current", IntProp, "Current peers"),
          PropSpec("required", IntProp, "Required peers"),
        ],
        [],
      ),
    ),
    #(
      "boot_phase_tracker",
      ComponentSpec(
        "boot_phase_tracker",
        L4System,
        "7-phase boot progress",
        [
          PropSpec("current_phase", IntProp, "Phase 0-6"),
          PropSpec("phases", JsonProp, "Phase names"),
        ],
        [],
      ),
    ),
    #(
      "threat_level_bar",
      ComponentSpec(
        "threat_level_bar",
        L0Constitutional,
        "Immune threat level indicator",
        [
          PropSpec(
            "level",
            EnumProp(["nominal", "elevated", "critical"]),
            "Level",
          ),
        ],
        [],
      ),
    ),
    #(
      "container_status_dot",
      ComponentSpec(
        "container_status_dot",
        L4System,
        "Single container dot",
        [
          PropSpec("name", StringProp, "Name"),
          PropSpec(
            "status",
            EnumProp(["running", "stopped", "error"]),
            "Status",
          ),
        ],
        [],
      ),
    ),
    #(
      "psi_invariant_row",
      ComponentSpec(
        "psi_invariant_row",
        L0Constitutional,
        "Psi invariant check result",
        [
          PropSpec("name", StringProp, "Psi-N"),
          PropSpec("passed", BoolProp, "Passed"),
          PropSpec("detail", StringProp, "Detail"),
        ],
        [],
      ),
    ),
    #(
      "sil_compliance_badge",
      ComponentSpec(
        "sil_compliance_badge",
        L0Constitutional,
        "SIL-6 compliance badge",
        [
          PropSpec("level", StringProp, "SIL level"),
          PropSpec("verified", BoolProp, "Verified"),
        ],
        [],
      ),
    ),
    #(
      "circuit_breaker_status",
      ComponentSpec(
        "circuit_breaker_status",
        L6Ecosystem,
        "Circuit breaker state",
        [PropSpec("state", EnumProp(["closed", "open", "half_open"]), "State")],
        [],
      ),
    ),
    #(
      "mara_status",
      ComponentSpec(
        "mara_status",
        L0Constitutional,
        "Chaos engineering daemon status",
        [
          PropSpec("running", BoolProp, "Is running"),
          PropSpec("attack_count", IntProp, "Attacks run"),
        ],
        [],
      ),
    ),
    #(
      "agent_heartbeat",
      ComponentSpec(
        "agent_heartbeat",
        L5Cognitive,
        "Agent heartbeat indicator",
        [
          PropSpec("agent_id", StringProp, "Agent"),
          PropSpec("last_seen", StringProp, "Timestamp"),
        ],
        [],
      ),
    ),
    #(
      "sync_status_icon",
      ComponentSpec(
        "sync_status_icon",
        L7Federation,
        "Federation sync state per peer",
        [
          PropSpec(
            "state",
            EnumProp(["in_sync", "behind", "ahead", "conflict"]),
            "Sync state",
          ),
        ],
        [],
      ),
    ),
    #(
      "entropy_score",
      ComponentSpec(
        "entropy_score",
        L5Cognitive,
        "Shannon entropy H display",
        [
          PropSpec("value", FloatProp, "Entropy bits"),
          PropSpec("threshold", FloatProp, "Gate threshold"),
        ],
        [],
      ),
    ),
    #(
      "test_suite_status",
      ComponentSpec(
        "test_suite_status",
        L1AtomicDebug,
        "Test suite passed/failed/skipped",
        [
          PropSpec("passed", IntProp, "Passed"),
          PropSpec("failed", IntProp, "Failed"),
          PropSpec("skipped", IntProp, "Skipped"),
        ],
        [],
      ),
    ),
    #(
      "cognitive_load_meter",
      ComponentSpec(
        "cognitive_load_meter",
        L5Cognitive,
        "HMI cognitive load estimate",
        [
          PropSpec(
            "level",
            EnumProp(["low", "medium", "high", "overload"]),
            "Load level",
          ),
        ],
        [],
      ),
    ),
    #(
      "dag_integrity_badge",
      ComponentSpec(
        "dag_integrity_badge",
        L1AtomicDebug,
        "DAG validity check badge",
        [
          PropSpec("nodes", IntProp, "Nodes"),
          PropSpec("edges", IntProp, "Edges"),
          PropSpec("acyclic", BoolProp, "Is acyclic"),
        ],
        [],
      ),
    ),
    #(
      "mesh_mode_indicator",
      ComponentSpec(
        "mesh_mode_indicator",
        L6Ecosystem,
        "MeshMode display",
        [
          PropSpec(
            "mode",
            EnumProp(["standalone", "clustered", "federated"]),
            "Mode",
          ),
        ],
        [],
      ),
    ),
  ]
}

// --- INTERACTIVE (16) ---
fn list_interactive() -> List(#(String, ComponentSpec)) {
  [
    #(
      "filter_bar",
      ComponentSpec(
        "filter_bar",
        L2Component,
        "Horizontal filter chip bar",
        [
          PropSpec("options", JsonProp, "Filter options"),
          PropSpec("selected", JsonProp, "Active filters"),
        ],
        [],
      ),
    ),
    #(
      "search_input",
      ComponentSpec(
        "search_input",
        L2Component,
        "Debounced text search input",
        [PropSpec("placeholder", StringProp, "Placeholder text")],
        [],
      ),
    ),
    #(
      "confirm_dialog",
      ComponentSpec(
        "confirm_dialog",
        L0Constitutional,
        "Two-button approve/reject dialog",
        [
          PropSpec("title", StringProp, "Title"),
          PropSpec("message", StringProp, "Message"),
        ],
        [],
      ),
    ),
    #(
      "toggle_switch",
      ComponentSpec(
        "toggle_switch",
        L2Component,
        "Boolean on/off toggle",
        [
          PropSpec("label", StringProp, "Label"),
          PropSpec("value", BoolProp, "Current state"),
        ],
        [],
      ),
    ),
    #(
      "dropdown_select",
      ComponentSpec(
        "dropdown_select",
        L2Component,
        "Single-value dropdown",
        [
          PropSpec("options", JsonProp, "Options"),
          PropSpec("selected", StringProp, "Current value"),
        ],
        [],
      ),
    ),
    #(
      "command_palette",
      ComponentSpec(
        "command_palette",
        L5Cognitive,
        "Keyboard command palette (Ctrl+K)",
        [],
        [],
      ),
    ),
    #(
      "threshold_slider",
      ComponentSpec(
        "threshold_slider",
        L2Component,
        "Numeric range slider",
        [
          PropSpec("min", FloatProp, "Min"),
          PropSpec("max", FloatProp, "Max"),
          PropSpec("value", FloatProp, "Current"),
        ],
        [],
      ),
    ),
    #(
      "bulk_action_bar",
      ComponentSpec(
        "bulk_action_bar",
        L4System,
        "Multi-select batch action bar",
        [PropSpec("actions", JsonProp, "Available actions")],
        [],
      ),
    ),
    #(
      "topic_subscribe_btn",
      ComponentSpec(
        "topic_subscribe_btn",
        L6Ecosystem,
        "Zenoh topic subscribe toggle",
        [
          PropSpec("topic", StringProp, "Topic key expression"),
          PropSpec("subscribed", BoolProp, "Is subscribed"),
        ],
        [],
      ),
    ),
    #(
      "refresh_button",
      ComponentSpec(
        "refresh_button",
        L2Component,
        "Manual refresh trigger",
        [PropSpec("loading", BoolProp, "Is loading")],
        [],
      ),
    ),
    #(
      "pagination_controls",
      ComponentSpec(
        "pagination_controls",
        L2Component,
        "Previous/next page controls",
        [
          PropSpec("page", IntProp, "Current page"),
          PropSpec("total", IntProp, "Total pages"),
        ],
        [],
      ),
    ),
    #(
      "sort_header",
      ComponentSpec(
        "sort_header",
        L3Transaction,
        "Sortable column header",
        [
          PropSpec("label", StringProp, "Column label"),
          PropSpec(
            "direction",
            EnumProp(["asc", "desc", "none"]),
            "Sort direction",
          ),
        ],
        [],
      ),
    ),
    #(
      "copy_button",
      ComponentSpec(
        "copy_button",
        L2Component,
        "Copy-to-clipboard button",
        [PropSpec("value", StringProp, "Value to copy")],
        [],
      ),
    ),
    #(
      "two_key_release",
      ComponentSpec(
        "two_key_release",
        L0Constitutional,
        "Bicameral two-key sign-off",
        [
          PropSpec("key1_signed", BoolProp, "Key 1"),
          PropSpec("key2_signed", BoolProp, "Key 2"),
        ],
        [],
      ),
    ),
    #(
      "chaos_inject_btn",
      ComponentSpec(
        "chaos_inject_btn",
        L0Constitutional,
        "Chaos attack injection button",
        [
          PropSpec(
            "attack_type",
            EnumProp(["kill", "partition", "cpu_spike", "memory_leak"]),
            "Attack type",
          ),
        ],
        [],
      ),
    ),
    #(
      "time_range_picker",
      ComponentSpec(
        "time_range_picker",
        L2Component,
        "Start/end time selector",
        [
          PropSpec("start", StringProp, "Start time"),
          PropSpec("end", StringProp, "End time"),
        ],
        [],
      ),
    ),
  ]
}

// --- VISUALIZATION (20) ---
fn list_visualization() -> List(#(String, ComponentSpec)) {
  [
    #(
      "container_grid_16",
      ComponentSpec(
        "container_grid_16",
        L4System,
        "4x4 grid of 16 container dots",
        [PropSpec("containers", JsonProp, "Container statuses")],
        [],
      ),
    ),
    #(
      "ooda_waterfall",
      ComponentSpec(
        "ooda_waterfall",
        L5Cognitive,
        "OODA cycle waterfall chart",
        [PropSpec("cycles", JsonProp, "Cycle durations")],
        [],
      ),
    ),
    #(
      "trace_flamegraph",
      ComponentSpec(
        "trace_flamegraph",
        L1AtomicDebug,
        "OTel span flamegraph",
        [
          PropSpec("trace_id", StringProp, "Trace ID"),
          PropSpec("spans", JsonProp, "Span data"),
        ],
        [],
      ),
    ),
    #(
      "span_gantt_chart",
      ComponentSpec(
        "span_gantt_chart",
        L1AtomicDebug,
        "Concurrent span Gantt chart",
        [
          PropSpec("spans", JsonProp, "Span data"),
          PropSpec("time_range_ms", IntProp, "Window ms"),
        ],
        [],
      ),
    ),
    #(
      "peer_ring",
      ComponentSpec(
        "peer_ring",
        L7Federation,
        "Circular federation peer ring",
        [
          PropSpec("peers", JsonProp, "Peer data"),
          PropSpec("attestations", JsonProp, "Attestation edges"),
        ],
        [],
      ),
    ),
    #(
      "antibody_list",
      ComponentSpec(
        "antibody_list",
        L0Constitutional,
        "Immune antibody list",
        [PropSpec("antibodies", JsonProp, "Antibody list")],
        [],
      ),
    ),
    #(
      "attack_timeline",
      ComponentSpec(
        "attack_timeline",
        L0Constitutional,
        "Chaos attack timeline",
        [PropSpec("attacks", JsonProp, "Attack events")],
        [],
      ),
    ),
    #(
      "knowledge_graph_mini",
      ComponentSpec(
        "knowledge_graph_mini",
        L3Transaction,
        "Mini knowledge graph viz",
        [PropSpec("triples", JsonProp, "SPO triples")],
        [],
      ),
    ),
    #(
      "pid_control_plot",
      ComponentSpec(
        "pid_control_plot",
        L2Component,
        "PID controller time series",
        [
          PropSpec("setpoint", FloatProp, "Set point"),
          PropSpec("actual", FloatProp, "Actual"),
          PropSpec("error", FloatProp, "Error"),
        ],
        [],
      ),
    ),
    #(
      "version_clock_ring",
      ComponentSpec(
        "version_clock_ring",
        L7Federation,
        "Version vector clock ring",
        [PropSpec("peers", JsonProp, "Peer clocks")],
        [],
      ),
    ),
    #(
      "event_frequency_heatmap",
      ComponentSpec(
        "event_frequency_heatmap",
        L5Cognitive,
        "AG-UI event frequency grid",
        [PropSpec("data", JsonProp, "Frequency matrix")],
        [],
      ),
    ),
    #(
      "task_kanban_board",
      ComponentSpec(
        "task_kanban_board",
        L3Transaction,
        "4-column task kanban",
        [PropSpec("tasks", JsonProp, "Task list")],
        [],
      ),
    ),
    #(
      "dependency_dag",
      ComponentSpec(
        "dependency_dag",
        L3Transaction,
        "Task dependency graph",
        [
          PropSpec("nodes", JsonProp, "Nodes"),
          PropSpec("edges", JsonProp, "Edges"),
        ],
        [],
      ),
    ),
    #(
      "reconciliation_diff",
      ComponentSpec(
        "reconciliation_diff",
        L7Federation,
        "Federation reconciliation diff",
        [PropSpec("entries", JsonProp, "Diff entries")],
        [],
      ),
    ),
    #(
      "router_topology_mini",
      ComponentSpec(
        "router_topology_mini",
        L6Ecosystem,
        "3-node router triangle",
        [PropSpec("routers", JsonProp, "Router statuses")],
        [],
      ),
    ),
    #(
      "metric_time_series",
      ComponentSpec(
        "metric_time_series",
        L1AtomicDebug,
        "Multi-line time series chart",
        [
          PropSpec("series", JsonProp, "Series data"),
          PropSpec("labels", JsonProp, "Series labels"),
        ],
        [],
      ),
    ),
    #(
      "hash_chain_strip",
      ComponentSpec(
        "hash_chain_strip",
        L0Constitutional,
        "Horizontal hash chain visualization",
        [PropSpec("blocks", JsonProp, "Hash blocks")],
        [],
      ),
    ),
    #(
      "layer_sunburst",
      ComponentSpec(
        "layer_sunburst",
        L2Component,
        "L0-L7 concentric ring chart",
        [PropSpec("layers", JsonProp, "Layer data")],
        [],
      ),
    ),
    #(
      "evolution_radar",
      ComponentSpec(
        "evolution_radar",
        L5Cognitive,
        "4-axis evolution radar chart",
        [PropSpec("vectors", JsonProp, "V1-V4 values")],
        [],
      ),
    ),
    #(
      "coverage_gauge_ring",
      ComponentSpec(
        "coverage_gauge_ring",
        L1AtomicDebug,
        "Donut gauge for coverage metric",
        [
          PropSpec("value", FloatProp, "Coverage 0.0-1.0"),
          PropSpec("label", StringProp, "Metric name"),
        ],
        [],
      ),
    ),
  ]
}

// --- AGENT (10) ---
fn list_agent() -> List(#(String, ComponentSpec)) {
  [
    #(
      "agent_run_card",
      ComponentSpec(
        "agent_run_card",
        L5Cognitive,
        "Active agent run card",
        [
          PropSpec("run_id", StringProp, "Run ID"),
          PropSpec("step_count", IntProp, "Steps"),
          PropSpec("elapsed_ms", IntProp, "Elapsed"),
        ],
        [],
      ),
    ),
    #(
      "tool_call_panel",
      ComponentSpec(
        "tool_call_panel",
        L5Cognitive,
        "In-flight tool call panel",
        [
          PropSpec("tool_name", StringProp, "Tool"),
          PropSpec(
            "status",
            EnumProp(["pending", "running", "completed", "failed"]),
            "Status",
          ),
        ],
        [],
      ),
    ),
    #(
      "reasoning_stream",
      ComponentSpec(
        "reasoning_stream",
        L5Cognitive,
        "Real-time reasoning text",
        [
          PropSpec("content", StringProp, "Text"),
          PropSpec("encrypted", BoolProp, "Encrypted CoT"),
        ],
        [],
      ),
    ),
    #(
      "sse_connection_indicator",
      ComponentSpec(
        "sse_connection_indicator",
        L6Ecosystem,
        "SSE connection badge",
        [
          PropSpec("connected", BoolProp, "Connected"),
          PropSpec("reconnect_count", IntProp, "Reconnects"),
        ],
        [],
      ),
    ),
    #(
      "agent_hierarchy_tree",
      ComponentSpec(
        "agent_hierarchy_tree",
        L5Cognitive,
        "5-tier agent hierarchy",
        [
          PropSpec("cortex", IntProp, "Cortex count"),
          PropSpec("intelligence", IntProp, "Intelligence"),
          PropSpec("workers", IntProp, "Workers"),
        ],
        [],
      ),
    ),
    #(
      "hitl_pending_queue",
      ComponentSpec(
        "hitl_pending_queue",
        L0Constitutional,
        "HITL approval request queue",
        [PropSpec("requests", JsonProp, "Pending requests")],
        [],
      ),
    ),
    #(
      "activity_feed",
      ComponentSpec(
        "activity_feed",
        L5Cognitive,
        "AG-UI activity event feed",
        [PropSpec("events", JsonProp, "Activity events")],
        [],
      ),
    ),
    #(
      "state_inspector",
      ComponentSpec(
        "state_inspector",
        L5Cognitive,
        "AG-UI SharedState viewer",
        [PropSpec("state", JsonProp, "Current state")],
        [],
      ),
    ),
    #(
      "message_thread",
      ComponentSpec(
        "message_thread",
        L5Cognitive,
        "AG-UI text message thread",
        [PropSpec("messages", JsonProp, "Message list")],
        [],
      ),
    ),
    #(
      "agent_capability_badges",
      ComponentSpec(
        "agent_capability_badges",
        L5Cognitive,
        "Agent capability badge row",
        [PropSpec("capabilities", JsonProp, "Capability list")],
        [],
      ),
    ),
  ]
}

// --- SAFETY (6) ---
fn list_safety() -> List(#(String, ComponentSpec)) {
  [
    #(
      "guardian_approval_panel",
      ComponentSpec(
        "guardian_approval_panel",
        L0Constitutional,
        "Full Guardian approval workflow",
        [
          PropSpec("request_id", StringProp, "Request ID"),
          PropSpec("action", StringProp, "Requested action"),
        ],
        [],
      ),
    ),
    #(
      "psi_invariant_dashboard",
      ComponentSpec(
        "psi_invariant_dashboard",
        L0Constitutional,
        "All Psi invariants grid",
        [PropSpec("results", JsonProp, "Check results")],
        [],
      ),
    ),
    #(
      "emergency_banner",
      ComponentSpec(
        "emergency_banner",
        L0Constitutional,
        "Full-width emergency banner",
        [PropSpec("message", StringProp, "Emergency message")],
        [],
      ),
    ),
    #(
      "constitutional_hash_chain",
      ComponentSpec(
        "constitutional_hash_chain",
        L0Constitutional,
        "Constitution hash chain display",
        [PropSpec("chain", JsonProp, "Chain blocks")],
        [],
      ),
    ),
    #(
      "audit_trail_log",
      ComponentSpec(
        "audit_trail_log",
        L0Constitutional,
        "Immutable audit log viewer",
        [PropSpec("entries", JsonProp, "Audit entries")],
        [],
      ),
    ),
    #(
      "sil6_compliance_matrix",
      ComponentSpec(
        "sil6_compliance_matrix",
        L0Constitutional,
        "STAMP control verification matrix",
        [PropSpec("controls", JsonProp, "Control statuses")],
        [],
      ),
    ),
  ]
}
