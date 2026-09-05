import cepaf_gleam/a2ui/schema.{type ComponentProposal}
import cepaf_gleam/ui/lustre/shell
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// Render an A2UI ComponentProposal directly into a Lustre Element tree.
/// Covers all 233 catalog components across 22 domains.
/// STAMP: SC-A2UI-002, SC-GLM-UI-001
pub fn render(proposal: ComponentProposal) -> Element(msg) {
  let ch = list.map(proposal.children, render)
  let aid = attribute.attribute("data-a2ui-id", proposal.id)
  let atype = attribute.attribute("data-a2ui-type", proposal.component_type)

  case proposal.component_type {
    // ═══════════════════════════════════════════════════════════
    // L0 CONSTITUTIONAL — Safety, Guardian, Emergency
    // ═══════════════════════════════════════════════════════════
    "alert" ->
      html.div(
        [attribute.attribute("role", "alert"), aid, cls("a2ui-alert")],
        ch,
      )
    "modal" -> html.dialog([aid, cls("a2ui-modal")], ch)
    "emergency_stop" ->
      html.button(
        [
          aid,
          cls("a2ui-emergency-stop"),
          attribute.attribute("aria-label", "Emergency Stop"),
        ],
        [element.text("EMERGENCY STOP")],
      )
    "emergency_banner" ->
      html.div(
        [
          aid,
          cls("a2ui-emergency-banner"),
          attribute.attribute("role", "alert"),
        ],
        ch,
      )
    "guardian_approval_panel" -> html.div([aid, cls("a2ui-guardian-panel")], ch)
    "psi_invariant_dashboard" -> html.div([aid, cls("a2ui-psi-dashboard")], ch)
    "psi_invariant_row" -> html.div([aid, cls("a2ui-psi-row")], ch)
    "constitutional_hash_chain" -> html.div([aid, cls("a2ui-hash-chain")], ch)
    "two_key_release" -> html.div([aid, cls("a2ui-two-key")], ch)
    "confirm_dialog" -> html.dialog([aid, cls("a2ui-confirm")], ch)
    "hitl_pending_queue" -> html.div([aid, cls("a2ui-hitl-queue")], ch)
    "access_control_row" -> html.div([aid, cls("a2ui-access-row")], ch)

    // ═══════════════════════════════════════════════════════════
    // L1 ATOMIC/DEBUG — Telemetry, Metrics, Traces
    // ═══════════════════════════════════════════════════════════
    "sparkline" -> html.span([aid, cls("a2ui-sparkline")], ch)
    "metric_counter" -> html.span([aid, cls("a2ui-metric")], ch)
    "metric_time_series" -> html.div([aid, cls("a2ui-timeseries")], ch)
    "metric_label_filter" -> html.div([aid, cls("a2ui-label-filter")], ch)
    "log_stream" -> html.pre([aid, cls("a2ui-log-stream")], ch)
    "log_level_filter" -> html.div([aid, cls("a2ui-log-filter")], ch)
    "span_gantt_chart" -> html.div([aid, cls("a2ui-gantt")], ch)
    "span_detail_drawer" -> html.div([aid, cls("a2ui-span-drawer")], ch)
    "trace_flamegraph" -> html.div([aid, cls("a2ui-flamegraph")], ch)
    "trace_id_link" -> html.a([aid, cls("a2ui-trace-link")], ch)
    "histogram_bar" -> html.div([aid, cls("a2ui-histogram")], ch)
    "latency_gauge" -> html.div([aid, cls("a2ui-latency-gauge")], ch)
    "event_frequency_heatmap" -> html.div([aid, cls("a2ui-heatmap")], ch)
    "event_payload_card" -> html.div([aid, cls("a2ui-event-card")], ch)
    "otel_export_status" -> html.div([aid, cls("a2ui-otel-status")], ch)
    "exemplar_link" -> html.a([aid, cls("a2ui-exemplar")], ch)
    "nif_latency_histogram" -> html.div([aid, cls("a2ui-nif-hist")], ch)
    "beam_scheduler_load" -> html.div([aid, cls("a2ui-beam-sched")], ch)
    "dirty_scheduler_load" -> html.div([aid, cls("a2ui-dirty-sched")], ch)
    "gc_pressure_indicator" -> html.div([aid, cls("a2ui-gc")], ch)
    "process_count_gauge" -> html.div([aid, cls("a2ui-proc-count")], ch)
    "ets_table_monitor" -> html.div([aid, cls("a2ui-ets")], ch)
    "memory_pressure_bar" -> html.div([aid, cls("a2ui-mem-pressure")], ch)
    "disk_io_sparkline" -> html.span([aid, cls("a2ui-disk-io")], ch)
    "network_throughput" -> html.div([aid, cls("a2ui-net-throughput")], ch)

    // ═══════════════════════════════════════════════════════════
    // L2 COMPONENT — Forms, Inputs, Layout
    // ═══════════════════════════════════════════════════════════
    "badge" -> html.span([aid, cls("a2ui-badge")], ch)
    "button" -> html.button([aid, cls("a2ui-button")], ch)
    "action_button" -> shell.action_button("Action", "/api/v1/noop", "{}")
    "toggle_switch" -> html.label([aid, cls("a2ui-toggle")], ch)
    "search_input" ->
      html.input([aid, cls("a2ui-search"), attribute.type_("search")])
    "dropdown_select" -> html.select([aid, cls("a2ui-dropdown")], ch)
    "threshold_slider" ->
      html.input([aid, cls("a2ui-slider"), attribute.type_("range")])
    "copy_button" ->
      html.button([aid, cls("a2ui-copy")], [element.text("Copy")])
    "refresh_button" ->
      html.button([aid, cls("a2ui-refresh")], [element.text("Refresh")])
    "rollback_button" ->
      html.button([aid, cls("a2ui-rollback")], [element.text("Rollback")])
    "filter_bar" -> html.div([aid, cls("a2ui-filter-bar")], ch)
    "sort_header" -> html.th([aid, cls("a2ui-sortable")], ch)
    "pagination_controls" -> html.nav([aid, cls("a2ui-pagination")], ch)
    "bulk_action_bar" -> html.div([aid, cls("a2ui-bulk-actions")], ch)
    "grid_layout" -> html.div([aid, cls("a2ui-grid")], ch)
    "responsive_columns" -> html.div([aid, cls("a2ui-columns")], ch)
    "split_pane" -> html.div([aid, cls("a2ui-split-pane")], ch)
    "tab_strip" ->
      html.div(
        [aid, cls("a2ui-tabs"), attribute.attribute("role", "tablist")],
        ch,
      )
    "collapsible_panel" -> html.details([aid, cls("a2ui-collapsible")], ch)
    "scroll_viewport" -> html.div([aid, cls("a2ui-scroll")], ch)
    "sidebar_nav" -> html.nav([aid, cls("a2ui-sidebar")], ch)
    "header_bar" -> html.header([aid, cls("a2ui-header")], ch)
    "sticky_footer" -> html.footer([aid, cls("a2ui-footer")], ch)
    "empty_state" -> html.div([aid, cls("a2ui-empty")], ch)
    "modal_overlay" -> html.div([aid, cls("a2ui-overlay")], ch)
    "section" -> shell.section("Section", ch)
    "card_grid" -> html.div([aid, cls("a2ui-card-grid")], ch)
    "dashboard_tile" -> html.div([aid, cls("a2ui-tile")], ch)
    "time_range_picker" -> html.div([aid, cls("a2ui-time-range")], ch)
    "domain_selector" -> html.select([aid, cls("a2ui-domain-select")], ch)
    "command_palette" -> html.div([aid, cls("a2ui-command-palette")], ch)
    "toast_notification" ->
      html.div(
        [aid, cls("a2ui-toast"), attribute.attribute("role", "status")],
        ch,
      )
    "notification_badge_counter" ->
      html.span([aid, cls("a2ui-notif-badge")], ch)
    "layer_accordion" -> html.div([aid, cls("a2ui-layer-accordion")], ch)

    // ═══════════════════════════════════════════════════════════
    // L3 TRANSACTION — Data, Tables, State
    // ═══════════════════════════════════════════════════════════
    "data_table" -> shell.data_table([], [])
    "kv_table" -> html.table([aid, cls("a2ui-kv-table")], ch)
    "json_tree" -> html.pre([aid, cls("a2ui-json-tree")], ch)
    "diff_viewer" -> html.div([aid, cls("a2ui-diff")], ch)
    "state_inspector" -> html.div([aid, cls("a2ui-state-inspector")], ch)
    "audit_trail_log" -> html.div([aid, cls("a2ui-audit-log")], ch)
    "checkpoint_status" -> html.div([aid, cls("a2ui-checkpoint")], ch)
    "sqlite_wal_status" -> html.div([aid, cls("a2ui-wal")], ch)
    "crdt_merge_log" -> html.div([aid, cls("a2ui-crdt-log")], ch)
    "hash_display" -> html.code([aid, cls("a2ui-hash")], ch)
    "hash_chain_strip" -> html.div([aid, cls("a2ui-hash-strip")], ch)
    "triple_row" -> html.tr([aid, cls("a2ui-triple-row")], ch)
    "triple_store_stats" -> html.div([aid, cls("a2ui-triple-stats")], ch)
    "fact_table" -> html.table([aid, cls("a2ui-fact-table")], ch)
    "raw_lines_preview" -> html.pre([aid, cls("a2ui-raw-lines")], ch)
    "message_inspector" -> html.div([aid, cls("a2ui-msg-inspector")], ch)

    // ═══════════════════════════════════════════════════════════
    // L4 SYSTEM — Containers, Resources, Infrastructure
    // ═══════════════════════════════════════════════════════════
    "progress" -> html.div([aid, cls("a2ui-progress")], ch)
    "container_card" -> html.div([aid, cls("a2ui-container-card")], ch)
    "container_grid_16" -> html.div([aid, cls("a2ui-container-grid")], ch)
    "container_status_dot" -> html.span([aid, cls("a2ui-status-dot")], ch)
    "container_log_tail" -> html.pre([aid, cls("a2ui-log-tail")], ch)
    "container_restart_btn" ->
      html.button([aid, cls("a2ui-restart")], [element.text("Restart")])
    "cpu_governor_gauge" -> html.div([aid, cls("a2ui-cpu-gov")], ch)
    "resource_usage_row" -> html.div([aid, cls("a2ui-resource-row")], ch)
    "resource_limit_bar" -> html.div([aid, cls("a2ui-resource-limit")], ch)
    "port_mapping_row" -> html.div([aid, cls("a2ui-port-row")], ch)
    "volume_mount_list" -> html.ul([aid, cls("a2ui-volumes")], ch)
    "network_namespace_badge" -> html.span([aid, cls("a2ui-netns")], ch)
    "image_staleness_badge" -> html.span([aid, cls("a2ui-staleness")], ch)
    "boot_phase_tracker" -> html.div([aid, cls("a2ui-boot-phase")], ch)
    "tier_boot_progress" -> html.div([aid, cls("a2ui-tier-boot")], ch)
    "dependency_dag" -> html.div([aid, cls("a2ui-dep-dag")], ch)
    "critical_path_highlight" -> html.div([aid, cls("a2ui-critical-path")], ch)
    "dag_integrity_badge" -> html.span([aid, cls("a2ui-dag-badge")], ch)
    "health_indicator" -> html.div([aid, cls("a2ui-health")], ch)
    "health_check_log" -> html.div([aid, cls("a2ui-health-log")], ch)
    "heartbeat_monitor" -> html.div([aid, cls("a2ui-heartbeat")], ch)
    "connection_status" -> html.div([aid, cls("a2ui-conn-status")], ch)
    "congestion_indicator" -> html.div([aid, cls("a2ui-congestion")], ch)

    // ═══════════════════════════════════════════════════════════
    // L5 COGNITIVE — OODA, Reasoning, AI, Rules
    // ═══════════════════════════════════════════════════════════
    "ooda_ring" -> html.div([aid, cls("a2ui-ooda-ring")], ch)
    "ooda_waterfall" -> html.div([aid, cls("a2ui-ooda-waterfall")], ch)
    "reasoning" -> html.div([aid, cls("a2ui-reasoning")], ch)
    "reasoning_stream" -> html.div([aid, cls("a2ui-reasoning-stream")], ch)
    "tool_call_panel" -> html.div([aid, cls("a2ui-tool-call")], ch)
    "decision_tree_node" -> html.div([aid, cls("a2ui-decision-node")], ch)
    "inference_chain" -> html.div([aid, cls("a2ui-inference-chain")], ch)
    "chat_message_bubble" -> html.div([aid, cls("a2ui-chat-bubble")], ch)
    "message_thread" -> html.div([aid, cls("a2ui-thread")], ch)
    "agent_run_card" -> html.div([aid, cls("a2ui-run-card")], ch)
    "agent_hierarchy_tree" -> html.div([aid, cls("a2ui-hierarchy")], ch)
    "agent_capability_badges" -> html.div([aid, cls("a2ui-capabilities")], ch)
    "agent_heartbeat" -> html.div([aid, cls("a2ui-agent-hb")], ch)
    "cognitive_load_meter" -> html.div([aid, cls("a2ui-cog-load")], ch)
    "circuit_breaker_status" -> html.div([aid, cls("a2ui-circuit")], ch)
    "rate_limit_gauge" -> html.div([aid, cls("a2ui-ratelimit")], ch)
    "grl_rule_card" -> html.div([aid, cls("a2ui-grl-rule")], ch)
    "rule_fire_log" -> html.div([aid, cls("a2ui-rule-log")], ch)
    "rete_network_viz" -> html.div([aid, cls("a2ui-rete")], ch)
    "allium_entity_card" -> html.div([aid, cls("a2ui-allium-entity")], ch)
    "allium_rule_display" -> html.div([aid, cls("a2ui-allium-rule")], ch)
    "allium_invariant_badge" -> html.span([aid, cls("a2ui-allium-inv")], ch)
    "entropy_score" -> html.span([aid, cls("a2ui-entropy")], ch)
    "coverage_gauge_ring" -> html.div([aid, cls("a2ui-coverage")], ch)
    "semantic_search_result" -> html.div([aid, cls("a2ui-semantic-result")], ch)
    "knowledge_graph_mini" -> html.div([aid, cls("a2ui-kg-mini")], ch)
    "ontology_class_tree" -> html.div([aid, cls("a2ui-ontology")], ch)
    "sparql_query_editor" -> html.textarea([aid, cls("a2ui-sparql-editor")], "")
    "sparql_result_grid" -> html.div([aid, cls("a2ui-sparql-results")], ch)
    "activity_feed" -> html.div([aid, cls("a2ui-activity")], ch)
    "adaptation_rate_meter" -> html.div([aid, cls("a2ui-adaptation")], ch)
    "evolution_radar" -> html.div([aid, cls("a2ui-evolution-radar")], ch)
    "sprint_velocity" -> html.div([aid, cls("a2ui-sprint-velocity")], ch)
    "spec_drift_indicator" -> html.div([aid, cls("a2ui-spec-drift")], ch)

    // ═══════════════════════════════════════════════════════════
    // L6 ECOSYSTEM — Mesh, Zenoh, Federation
    // ═══════════════════════════════════════════════════════════
    "topology" -> html.div([aid, cls("a2ui-topology")], ch)
    "mesh_partition_map" -> html.div([aid, cls("a2ui-partition-map")], ch)
    "mesh_mode_indicator" -> html.span([aid, cls("a2ui-mesh-mode")], ch)
    "peer_ring" -> html.div([aid, cls("a2ui-peer-ring")], ch)
    "quorum_indicator" -> html.div([aid, cls("a2ui-quorum")], ch)
    "consensus_vote_panel" -> html.div([aid, cls("a2ui-consensus")], ch)
    "router_topology_mini" -> html.div([aid, cls("a2ui-router-topo")], ch)
    "router_health_strip" -> html.div([aid, cls("a2ui-router-health")], ch)
    "zenoh_session_card" -> html.div([aid, cls("a2ui-zenoh-session")], ch)
    "zenoh_topic_rate" -> html.div([aid, cls("a2ui-topic-rate")], ch)
    "key_expression_viewer" -> html.div([aid, cls("a2ui-key-expr")], ch)
    "topic_tree" -> html.div([aid, cls("a2ui-topic-tree")], ch)
    "topic_subscribe_btn" ->
      html.button([aid, cls("a2ui-subscribe")], [element.text("Subscribe")])
    "pub_sub_flow" -> html.div([aid, cls("a2ui-pubsub-flow")], ch)
    "message_queue_depth" -> html.div([aid, cls("a2ui-queue-depth")], ch)
    "namespace_prefix_table" -> html.table([aid, cls("a2ui-ns-table")], ch)
    "service_map_node" -> html.div([aid, cls("a2ui-service-node")], ch)
    "gateway_status" -> html.div([aid, cls("a2ui-gateway")], ch)
    "sse_connection_indicator" -> html.div([aid, cls("a2ui-sse")], ch)
    "sync_status_icon" -> html.span([aid, cls("a2ui-sync")], ch)
    "energy_flow_sankey" -> html.div([aid, cls("a2ui-sankey")], ch)
    "contract_boundary_viz" -> html.div([aid, cls("a2ui-contract")], ch)

    // ═══════════════════════════════════════════════════════════
    // L7 FEDERATION — Attestation, Version Vectors, Compliance
    // ═══════════════════════════════════════════════════════════
    "federation_member_card" -> html.div([aid, cls("a2ui-fed-member")], ch)
    "attestation_chain" -> html.div([aid, cls("a2ui-attestation")], ch)
    "version_vector_row" -> html.div([aid, cls("a2ui-version-vector")], ch)
    "version_clock_ring" -> html.div([aid, cls("a2ui-clock-ring")], ch)
    "certificate_status" -> html.div([aid, cls("a2ui-cert")], ch)
    "sovereignty_badge" -> html.span([aid, cls("a2ui-sovereignty")], ch)
    "sil_compliance_badge" -> html.span([aid, cls("a2ui-sil-badge")], ch)
    "sil6_compliance_matrix" -> html.div([aid, cls("a2ui-sil6-matrix")], ch)
    "proof_token_card" -> html.div([aid, cls("a2ui-proof-token")], ch)
    "proof_token_verifier" -> html.div([aid, cls("a2ui-proof-verify")], ch)
    "graph_statistics_card" -> html.div([aid, cls("a2ui-graph-stats")], ch)
    "encryption_indicator" -> html.span([aid, cls("a2ui-encryption")], ch)
    "hmac_verification_badge" -> html.span([aid, cls("a2ui-hmac")], ch)
    "key_rotation_timeline" -> html.div([aid, cls("a2ui-key-rotation")], ch)

    // ═══════════════════════════════════════════════════════════
    // CROSS-LAYER — Immune, Chaos, Apoptosis, Recovery
    // ═══════════════════════════════════════════════════════════
    "antibody_list" -> html.div([aid, cls("a2ui-antibodies")], ch)
    "attack_timeline" -> html.div([aid, cls("a2ui-attacks")], ch)
    "immune_antibody_forge" -> html.div([aid, cls("a2ui-forge")], ch)
    "threat_level_bar" -> html.div([aid, cls("a2ui-threat")], ch)
    "mara_status" -> html.div([aid, cls("a2ui-mara")], ch)
    "chaos_inject_btn" ->
      html.button([aid, cls("a2ui-chaos")], [element.text("Inject Chaos")])
    "apoptosis_countdown" -> html.div([aid, cls("a2ui-apoptosis")], ch)
    "dying_gasp_log" -> html.pre([aid, cls("a2ui-dying-gasp")], ch)
    "cascade_containment" -> html.div([aid, cls("a2ui-cascade")], ch)
    "self_heal_timeline" -> html.div([aid, cls("a2ui-self-heal")], ch)
    "recovery_playbook_card" -> html.div([aid, cls("a2ui-recovery")], ch)
    "graceful_degradation_bar" -> html.div([aid, cls("a2ui-degradation")], ch)
    "partition_fence_status" -> html.div([aid, cls("a2ui-partition-fence")], ch)
    "hysteresis_band" -> html.div([aid, cls("a2ui-hysteresis")], ch)
    "liveliness_token" -> html.span([aid, cls("a2ui-liveliness")], ch)
    "causal_order_timeline" -> html.div([aid, cls("a2ui-causal-order")], ch)

    // ═══════════════════════════════════════════════════════════
    // PLANNING & TASKS
    // ═══════════════════════════════════════════════════════════
    "task_kanban_board" -> html.div([aid, cls("a2ui-kanban")], ch)
    "task_burndown_chart" -> html.div([aid, cls("a2ui-burndown")], ch)
    "task_priority_pill" -> html.span([aid, cls("a2ui-priority")], ch)
    "task_status_flow" -> html.div([aid, cls("a2ui-status-flow")], ch)
    "task_age_indicator" -> html.span([aid, cls("a2ui-task-age")], ch)
    "task_detail_pane" -> html.div([aid, cls("a2ui-task-detail")], ch)
    "task_dependency_edge" -> html.div([aid, cls("a2ui-dep-edge")], ch)
    "parent_child_tree" -> html.div([aid, cls("a2ui-parent-child")], ch)
    "escalation_path" -> html.div([aid, cls("a2ui-escalation")], ch)

    // ═══════════════════════════════════════════════════════════
    // BUILDS, TESTS, COMPLIANCE
    // ═══════════════════════════════════════════════════════════
    "build_history_chart" -> html.div([aid, cls("a2ui-build-history")], ch)
    "test_suite_status" -> html.div([aid, cls("a2ui-test-suite")], ch)
    "alert_rule_card" -> html.div([aid, cls("a2ui-alert-rule")], ch)
    "scout_result" -> html.div([aid, cls("a2ui-scout")], ch)

    // ═══════════════════════════════════════════════════════════
    // BIOMORPHIC — Bio, Neuro, Metabolic, Homeostasis
    // ═══════════════════════════════════════════════════════════
    "bio_subsystem_radar" -> html.div([aid, cls("a2ui-bio-radar")], ch)
    "neuro_signal_trace" -> html.div([aid, cls("a2ui-neuro-trace")], ch)
    "metabolic_rate_gauge" -> html.div([aid, cls("a2ui-metabolic")], ch)
    "homeostasis_error_integral" -> html.div([aid, cls("a2ui-homeostasis")], ch)
    "pid_control_plot" -> html.div([aid, cls("a2ui-pid-plot")], ch)
    "pid_tuning_panel" -> html.div([aid, cls("a2ui-pid-tuning")], ch)
    "cockpit_mode_badge" -> html.span([aid, cls("a2ui-cockpit-mode")], ch)
    "operator_presence" -> html.div([aid, cls("a2ui-operator")], ch)
    "owner_avatar" -> html.div([aid, cls("a2ui-avatar")], ch)
    "entity_detail_card" -> html.div([aid, cls("a2ui-entity-detail")], ch)

    // ═══════════════════════════════════════════════════════════
    // ACCESSIBILITY (SC-HMI)
    // ═══════════════════════════════════════════════════════════
    "aria_landmark_indicator" ->
      html.div(
        [aid, cls("a2ui-aria-landmark"), attribute.attribute("role", "region")],
        ch,
      )
    "focus_trap_boundary" -> html.div([aid, cls("a2ui-focus-trap")], ch)
    "screen_reader_status" ->
      html.div(
        [aid, cls("a2ui-sr-status"), attribute.attribute("aria-live", "polite")],
        ch,
      )
    "keyboard_shortcut_hint" -> html.kbd([aid, cls("a2ui-shortcut")], ch)
    "high_contrast_mode" -> html.div([aid, cls("a2ui-high-contrast")], ch)
    "color_contrast_badge" -> html.span([aid, cls("a2ui-contrast")], ch)
    "reduced_motion_toggle" -> html.label([aid, cls("a2ui-reduced-motion")], ch)
    "text_scaling_control" -> html.div([aid, cls("a2ui-text-scale")], ch)
    "system_announcement" ->
      html.div(
        [
          aid,
          cls("a2ui-announce"),
          attribute.attribute("aria-live", "assertive"),
        ],
        ch,
      )
    "fractal_breadcrumb" ->
      html.nav(
        [
          aid,
          cls("a2ui-breadcrumb"),
          attribute.attribute("aria-label", "Fractal Layer"),
        ],
        ch,
      )
    "layer_sunburst" -> html.div([aid, cls("a2ui-sunburst")], ch)

    // ═══════════════════════════════════════════════════════════
    // MISC — Remaining specialized components
    // ═══════════════════════════════════════════════════════════
    "slo_budget_gauge" -> html.div([aid, cls("a2ui-slo-budget")], ch)
    "reconciliation_diff" -> html.div([aid, cls("a2ui-reconciliation")], ch)

    // Fallback for any unrecognized component type
    _ -> html.div([atype, aid, cls("a2ui-unknown")], ch)
  }
}

fn cls(name: String) -> attribute.Attribute(msg) {
  attribute.class(name)
}
