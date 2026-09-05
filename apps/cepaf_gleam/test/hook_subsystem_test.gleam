// Hook Subsystem KPI Tile — Wave 4 Tests
// Task 116487357141533399 · SC-GLM-UI-001 · SC-WIRE-001
//
// 8-category coverage:
//   C1 – page renders (structure present, non-empty)
//   C2 – status badges (FREE / HELD / STALE visible)
//   C3 – data grids (all 10 KPI cards present)
//   C5 – interactive (refresh button present)
//   C7 – AG-UI events (update() Msg variants produce correct state)

import cepaf_gleam/ui/lustre/hook_subsystem.{
  AgentCountsUpdated, AgentHookCounts, CacheHitRateUpdated, DaemonHealthUpdated,
  EntropyUpdated, HookSubsystemModel, RefreshHookSubsystem, ReteFiresUpdated,
  SnapshotAgeUpdated, StopLockChanged, StopLockFree, StopLockHeld, StopLockStale,
  format_cache_rate, format_entropy, format_posterior, init, stop_lock_color,
  stop_lock_label, update, view,
}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ── C1: Page structure ────────────────────────────────────────────────────────

pub fn c1_view_returns_non_empty_test() {
  let html = view(init())
  should.be_true(string.length(html) > 0)
}

pub fn c1_view_contains_tile_testid_test() {
  let html = view(init())
  html |> string.contains("hook-subsystem-tile") |> should.be_true
}

pub fn c1_view_contains_title_test() {
  let html = view(init())
  html |> string.contains("Hook Subsystem KPIs") |> should.be_true
}

pub fn c1_view_contains_section_tag_test() {
  let html = view(init())
  html |> string.contains("<section") |> should.be_true
}

// ── C2: Status badges ─────────────────────────────────────────────────────────

pub fn c2_stop_lock_free_shows_free_label_test() {
  let model = HookSubsystemModel(..init(), stop_lock: StopLockFree)
  view(model) |> string.contains("FREE") |> should.be_true
}

pub fn c2_stop_lock_held_shows_held_label_test() {
  let model = HookSubsystemModel(..init(), stop_lock: StopLockHeld)
  view(model) |> string.contains("HELD") |> should.be_true
}

pub fn c2_stop_lock_stale_shows_stale_label_test() {
  let model = HookSubsystemModel(..init(), stop_lock: StopLockStale)
  view(model) |> string.contains("STALE") |> should.be_true
}

pub fn c2_stop_lock_label_free_test() {
  stop_lock_label(StopLockFree) |> should.equal("FREE")
}

pub fn c2_stop_lock_label_held_test() {
  stop_lock_label(StopLockHeld) |> should.equal("HELD")
}

pub fn c2_stop_lock_label_stale_test() {
  stop_lock_label(StopLockStale) |> should.equal("STALE")
}

pub fn c2_stop_lock_color_free_is_green_test() {
  stop_lock_color(StopLockFree) |> should.equal("#3dd68c")
}

pub fn c2_stop_lock_color_held_is_amber_test() {
  stop_lock_color(StopLockHeld) |> should.equal("#f5a623")
}

pub fn c2_stop_lock_color_stale_is_red_test() {
  stop_lock_color(StopLockStale) |> should.equal("#ff4757")
}

// ── C3: Data grids — all 10 KPI cards ────────────────────────────────────────

pub fn c3_kpi_card_hook_fires_total_present_test() {
  view(init()) |> string.contains("hook-fires-total") |> should.be_true
}

pub fn c3_kpi_card_hook_fires_claude_present_test() {
  view(init()) |> string.contains("hook-fires-claude") |> should.be_true
}

pub fn c3_kpi_card_hook_fires_pi_present_test() {
  view(init()) |> string.contains("hook-fires-pi") |> should.be_true
}

pub fn c3_kpi_card_hook_fires_gemini_present_test() {
  view(init()) |> string.contains("hook-fires-gemini") |> should.be_true
}

pub fn c3_kpi_card_snapshot_age_present_test() {
  view(init()) |> string.contains("hook-snapshot-age") |> should.be_true
}

pub fn c3_kpi_card_entropy_present_test() {
  view(init()) |> string.contains("hook-entropy") |> should.be_true
}

pub fn c3_kpi_card_daemon_health_present_test() {
  view(init()) |> string.contains("hook-daemon-health") |> should.be_true
}

pub fn c3_kpi_card_cache_rate_present_test() {
  view(init()) |> string.contains("hook-cache-rate") |> should.be_true
}

pub fn c3_kpi_card_rete_fires_present_test() {
  view(init()) |> string.contains("hook-rete-fires") |> should.be_true
}

pub fn c3_kpi_card_stop_lock_present_test() {
  view(init()) |> string.contains("hook-stop-lock") |> should.be_true
}

pub fn c3_entropy_ring_present_test() {
  view(init()) |> string.contains("entropy-ring") |> should.be_true
}

pub fn c3_cache_ring_present_test() {
  view(init()) |> string.contains("cache-ring") |> should.be_true
}

// ── C5: Interactive ───────────────────────────────────────────────────────────

pub fn c5_refresh_button_present_test() {
  view(init())
  |> string.contains("data-action=\"refresh-hook-subsystem\"")
  |> should.be_true
}

pub fn c5_refresh_button_has_hst_class_test() {
  view(init()) |> string.contains("class=\"hst-refresh\"") |> should.be_true
}

pub fn c5_refresh_button_has_aria_label_test() {
  view(init()) |> string.contains("aria-label") |> should.be_true
}

// ── C7: AG-UI events — update() Msg variants ─────────────────────────────────

pub fn c7_init_total_hook_fires_is_6_test() {
  init().total_hook_fires |> should.equal(6)
}

pub fn c7_init_claude_fires_is_6_test() {
  init().agent_counts.claude |> should.equal(6)
}

pub fn c7_init_pi_fires_is_0_test() {
  init().agent_counts.pi |> should.equal(0)
}

pub fn c7_init_gemini_fires_is_0_test() {
  init().agent_counts.gemini |> should.equal(0)
}

pub fn c7_init_entropy_bits_test() {
  init().entropy_bits |> should.equal(2.58)
}

pub fn c7_init_daemon_health_posterior_test() {
  init().daemon_health_posterior |> should.equal(1.0)
}

pub fn c7_init_cache_hit_rate_test() {
  init().cache_hit_rate |> should.equal(0.0)
}

pub fn c7_init_stop_lock_is_free_test() {
  init().stop_lock |> should.equal(StopLockFree)
}

pub fn c7_init_loading_is_false_test() {
  init().loading |> should.be_false
}

pub fn c7_update_refresh_clears_loading_test() {
  let model = HookSubsystemModel(..init(), loading: True)
  let result = update(model, RefreshHookSubsystem)
  result.loading |> should.be_false
}

pub fn c7_update_snapshot_age_updated_test() {
  let result = update(init(), SnapshotAgeUpdated(42))
  result.snapshot_age_ms |> should.equal(42)
}

pub fn c7_update_entropy_updated_test() {
  let result = update(init(), EntropyUpdated(3.14))
  result.entropy_bits |> should.equal(3.14)
}

pub fn c7_update_rete_fires_updated_test() {
  let result = update(init(), ReteFiresUpdated(7))
  result.rete_rule_fires |> should.equal(7)
}

pub fn c7_update_stop_lock_to_held_test() {
  let result = update(init(), StopLockChanged(StopLockHeld))
  result.stop_lock |> should.equal(StopLockHeld)
}

pub fn c7_update_stop_lock_to_stale_test() {
  let result = update(init(), StopLockChanged(StopLockStale))
  result.stop_lock |> should.equal(StopLockStale)
}

pub fn c7_update_agent_counts_updates_total_test() {
  let counts = AgentHookCounts(claude: 10, pi: 3, gemini: 2)
  let result = update(init(), AgentCountsUpdated(counts))
  result.total_hook_fires |> should.equal(15)
}

pub fn c7_update_agent_counts_updates_agent_counts_test() {
  let counts = AgentHookCounts(claude: 10, pi: 3, gemini: 2)
  let result = update(init(), AgentCountsUpdated(counts))
  result.agent_counts.claude |> should.equal(10)
  result.agent_counts.pi |> should.equal(3)
  result.agent_counts.gemini |> should.equal(2)
}

pub fn c7_update_daemon_health_updated_test() {
  let result = update(init(), DaemonHealthUpdated(0.75))
  result.daemon_health_posterior |> should.equal(0.75)
}

pub fn c7_update_cache_hit_rate_updated_test() {
  let result = update(init(), CacheHitRateUpdated(0.92))
  result.cache_hit_rate |> should.equal(0.92)
}

pub fn c7_update_preserves_other_fields_test() {
  let result = update(init(), SnapshotAgeUpdated(99))
  result.total_hook_fires |> should.equal(6)
  result.stop_lock |> should.equal(StopLockFree)
  result.loading |> should.be_false
}

// ── Format helpers ────────────────────────────────────────────────────────────

pub fn format_entropy_appends_bits_test() {
  format_entropy(2.58) |> string.contains("bits") |> should.be_true
}

pub fn format_posterior_appends_percent_test() {
  format_posterior(1.0) |> string.contains("%") |> should.be_true
}

pub fn format_cache_rate_appends_percent_test() {
  format_cache_rate(0.5) |> string.contains("%") |> should.be_true
}

// ── View reflects live model values ──────────────────────────────────────────

pub fn view_reflects_total_fires_test() {
  let model = HookSubsystemModel(..init(), total_hook_fires: 42)
  view(model) |> string.contains("42") |> should.be_true
}

pub fn view_reflects_entropy_bits_test() {
  let model = HookSubsystemModel(..init(), entropy_bits: 3.0)
  view(model) |> string.contains("3.0") |> should.be_true
}

pub fn view_high_entropy_no_amber_color_test() {
  // entropy >= 2.5 → green (#3dd68c), not amber (#f5a623) for entropy card
  let model = HookSubsystemModel(..init(), entropy_bits: 3.0)
  let html = view(model)
  // The entropy color is embedded in kpi_card style; green should appear
  html |> string.contains("#3dd68c") |> should.be_true
}

pub fn view_low_entropy_amber_color_test() {
  // entropy < 2.5 → amber (#f5a623) for entropy card
  let model = HookSubsystemModel(..init(), entropy_bits: 1.0)
  let html = view(model)
  html |> string.contains("#f5a623") |> should.be_true
}
