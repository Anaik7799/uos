/// TUI view for Hook Subsystem KPI Tile (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/hook_subsystem.{
  type HookSubsystemModel, type StopLockState,
  StopLockFree, StopLockHeld, StopLockStale,
}
import gleam/float
import gleam/int
import gleam/string

pub fn render(model: HookSubsystemModel) -> String {
  let header = visuals.with_color("  HOOK SUBSYSTEM KPIs", "cyan")
  let fires = render_fires(model)
  let agents = render_agents(model)
  let entropy = render_entropy(model)
  let daemon = render_daemon(model)
  let lock = render_lock(model)
  string.join([header, fires, agents, entropy, daemon, lock], "\n")
}

fn render_fires(model: HookSubsystemModel) -> String {
  let total =
    visuals.with_color(int.to_string(model.total_hook_fires), "green")
  let rete = visuals.with_color(int.to_string(model.rete_rule_fires), "yellow")
  "  Hook fires: "
  <> total
  <> "  RETE-UL fires: "
  <> rete
  <> "  Snapshot age: "
  <> int.to_string(model.snapshot_age_ms)
  <> "ms"
}

fn render_agents(model: HookSubsystemModel) -> String {
  let c = visuals.with_color(int.to_string(model.agent_counts.claude), "blue")
  let p = visuals.with_color(int.to_string(model.agent_counts.pi), "blue")
  let g = visuals.with_color(int.to_string(model.agent_counts.gemini), "blue")
  "  Agents — Claude: " <> c <> "  Pi: " <> p <> "  Gemini: " <> g
}

fn render_entropy(model: HookSubsystemModel) -> String {
  let h =
    visuals.with_color(
      float.to_string(model.entropy_bits) <> " bits",
      entropy_color(model.entropy_bits),
    )
  let cache =
    visuals.with_color(
      float.to_string(model.cache_hit_rate),
      cache_color(model.cache_hit_rate),
    )
  "  Entropy H: " <> h <> "  Cache hit: " <> cache
}

fn render_daemon(model: HookSubsystemModel) -> String {
  let color = case model.daemon_health_posterior >=. 0.9 {
    True -> "green"
    False -> case model.daemon_health_posterior >=. 0.7 {
      True -> "yellow"
      False -> "red"
    }
  }
  let p =
    visuals.with_color(
      float.to_string(model.daemon_health_posterior),
      color,
    )
  "  Daemon health P(safe|Δ): " <> p
}

fn render_lock(model: HookSubsystemModel) -> String {
  let label = stop_lock_label(model.stop_lock)
  let color = stop_lock_color(model.stop_lock)
  "  Stop-lock: " <> visuals.with_color(label, color)
}

fn stop_lock_label(state: StopLockState) -> String {
  case state {
    StopLockFree -> "FREE"
    StopLockHeld -> "HELD"
    StopLockStale -> "STALE"
  }
}

fn stop_lock_color(state: StopLockState) -> String {
  case state {
    StopLockFree -> "green"
    StopLockHeld -> "yellow"
    StopLockStale -> "red"
  }
}

fn entropy_color(h: Float) -> String {
  case h >=. 2.5 {
    True -> "green"
    False -> case h >=. 1.5 {
      True -> "yellow"
      False -> "red"
    }
  }
}

fn cache_color(rate: Float) -> String {
  case rate >=. 0.9 {
    True -> "green"
    False -> case rate >=. 0.7 {
      True -> "yellow"
      False -> "cyan"
    }
  }
}
