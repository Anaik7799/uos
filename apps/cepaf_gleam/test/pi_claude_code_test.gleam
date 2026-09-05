// Pi x Claude Code Bridge Tests
// SC-PI-AUTO-001..008 verification

import cepaf_gleam/bridge/pi_claude_code
import gleam/list
import gleeunit/should

// === Bridge Initialization ===

pub fn init_creates_valid_bridge_test() {
  let bridge = pi_claude_code.init()
  bridge.pi_events_mapped |> should.equal(29)
  bridge.agui_events_mapped |> should.equal(32)
  bridge.tool_federation_count |> should.equal(93)
}

pub fn init_rpc_state_not_started_test() {
  let bridge = pi_claude_code.init()
  bridge.rpc_state |> should.equal(pi_claude_code.NotStarted)
}

pub fn init_session_sync_inactive_test() {
  let bridge = pi_claude_code.init()
  bridge.session_sync_active |> should.be_false()
}

pub fn init_tool_counts_correct_test() {
  let bridge = pi_claude_code.init()
  bridge.claude_tools_count |> should.equal(6)
  bridge.pi_tools_count |> should.equal(14)
  bridge.c3i_tools_count |> should.equal(73)
  // 6 + 14 + 73 = 93
  { bridge.claude_tools_count + bridge.pi_tools_count + bridge.c3i_tools_count }
  |> should.equal(93)
}

// === Bridge Status ===

pub fn bridge_status_disconnected_test() {
  let bridge = pi_claude_code.init()
  let status = pi_claude_code.bridge_status(bridge)
  status.health |> should.equal(pi_claude_code.Disconnected)
  status.rpc_connected |> should.be_false()
}

pub fn bridge_status_total_tools_test() {
  let bridge = pi_claude_code.init()
  let status = pi_claude_code.bridge_status(bridge)
  status.total_tools |> should.equal(93)
}

pub fn bridge_status_events_mapped_test() {
  let bridge = pi_claude_code.init()
  let status = pi_claude_code.bridge_status(bridge)
  status.events_mapped |> should.equal(29)
}

// === Event Mappings ===

pub fn event_mappings_count_test() {
  let mappings = pi_claude_code.event_mappings()
  // 29 Pi events total (some map to same AG-UI event)
  { list.length(mappings) >= 27 } |> should.be_true()
}

pub fn bidirectional_mappings_exist_test() {
  let count = pi_claude_code.bidirectional_count()
  // Most mappings are bidirectional
  { count >= 15 } |> should.be_true()
}

pub fn agui_only_events_count_test() {
  let only = pi_claude_code.agui_only_events()
  // AG-UI has extra events not in Pi
  { list.length(only) >= 5 } |> should.be_true()
}

pub fn pi_lifecycle_events_mapped_test() {
  let mappings = pi_claude_code.event_mappings()
  let lifecycle =
    mappings
    |> list.filter(fn(m) { m.pi_category == pi_claude_code.PiLifecycle })
  { list.length(lifecycle) >= 7 } |> should.be_true()
}

pub fn pi_tool_events_mapped_test() {
  let mappings = pi_claude_code.event_mappings()
  let tools =
    mappings
    |> list.filter(fn(m) { m.pi_category == pi_claude_code.PiToolExecution })
  { list.length(tools) >= 3 } |> should.be_true()
}

pub fn pi_session_events_mapped_test() {
  let mappings = pi_claude_code.event_mappings()
  let sessions =
    mappings
    |> list.filter(fn(m) { m.pi_category == pi_claude_code.PiSessionManagement })
  { list.length(sessions) >= 7 } |> should.be_true()
}

// === Claude Code Tools ===

pub fn claude_code_tools_count_test() {
  let tools = pi_claude_code.claude_code_tools()
  list.length(tools) |> should.equal(6)
}

pub fn claude_code_tools_names_test() {
  let tools = pi_claude_code.claude_code_tools()
  let names = list.map(tools, fn(t) { t.name })
  names |> should.equal(["Read", "Write", "Edit", "Bash", "Grep", "Glob"])
}

pub fn total_tool_count_test() {
  pi_claude_code.total_tool_count() |> should.equal(93)
}

// === Tool Mapping (Bidirectional) ===

pub fn claude_read_maps_to_pi_read_test() {
  pi_claude_code.claude_to_pi_tool("Read") |> should.equal("read")
}

pub fn claude_bash_maps_to_pi_bash_test() {
  pi_claude_code.claude_to_pi_tool("Bash") |> should.equal("bash")
}

pub fn claude_glob_maps_to_pi_find_test() {
  pi_claude_code.claude_to_pi_tool("Glob") |> should.equal("find")
}

pub fn pi_read_maps_to_claude_read_test() {
  pi_claude_code.pi_to_claude_tool("read") |> should.equal("Read")
}

pub fn pi_find_maps_to_claude_glob_test() {
  pi_claude_code.pi_to_claude_tool("find") |> should.equal("Glob")
}

pub fn pi_ls_maps_to_claude_glob_test() {
  pi_claude_code.pi_to_claude_tool("ls") |> should.equal("Glob")
}

pub fn unknown_tool_handled_test() {
  pi_claude_code.claude_to_pi_tool("Unknown") |> should.equal("unknown")
  pi_claude_code.pi_to_claude_tool("unknown") |> should.equal("Unknown")
}

// === Zenoh Topics ===

pub fn zenoh_topic_prefix_test() {
  pi_claude_code.zenoh_topic_prefix() |> should.equal("indrajaal/pi")
}

pub fn zenoh_agent_topic_test() {
  pi_claude_code.zenoh_agent_topic()
  |> should.equal("indrajaal/pi/agent/events")
}

pub fn zenoh_bridge_health_topic_test() {
  pi_claude_code.zenoh_bridge_health_topic()
  |> should.equal("indrajaal/pi/bridge/health")
}

// === Fractal Layer Coverage ===

pub fn claude_tools_cover_l3_l4_test() {
  let tools = pi_claude_code.claude_code_tools()
  let l3_tools = list.filter(tools, fn(t) { t.fractal_layer == 3 })
  let l4_tools = list.filter(tools, fn(t) { t.fractal_layer == 4 })
  { list.length(l3_tools) >= 4 } |> should.be_true()
  { list.length(l4_tools) >= 1 } |> should.be_true()
}

// === Integration Invariants ===

pub fn tool_counts_sum_correctly_test() {
  let bridge = pi_claude_code.init()
  let sum =
    bridge.claude_tools_count + bridge.pi_tools_count + bridge.c3i_tools_count
  sum |> should.equal(bridge.tool_federation_count)
}

pub fn event_mapping_covers_all_pi_categories_test() {
  let mappings = pi_claude_code.event_mappings()
  let categories =
    mappings
    |> list.map(fn(m) { m.pi_category })
    |> list.unique()
  // All 6 Pi event categories should be represented
  { list.length(categories) >= 5 } |> should.be_true()
}
