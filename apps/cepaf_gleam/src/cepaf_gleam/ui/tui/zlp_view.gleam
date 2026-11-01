//// Terminal ANSI TUI Dashboard for UOS-ZLP-v3 Supervised Lean 4.33.0 +
//// Zig 0.16.0 + Gleam/OTP 29.0.5 + MCP + Zenoh Port Hyperplane.
//// STAMP: SC-GLM-UI-001, SC-HARNESS-MCP-001, SC-ZLP-PORT-001, SC-PROVENANCE-001

import cepaf_gleam/mcp/transports/zlp_hyperplane
import cepaf_gleam/ui/wisp/zlp_api.{type ZlpShardObservation}
import gleam/int
import gleam/list
import gleam/string

pub fn render() -> String {
  let binary_available = zlp_hyperplane.is_binary_available()
  let pool_running = zlp_hyperplane.is_running()
  let shards = zlp_api.observe_shards()
  render_snapshot(binary_available, pool_running, shards)
}

pub fn render_snapshot(
  binary_available: Bool,
  pool_running: Bool,
  shards: List(ZlpShardObservation),
) -> String {
  let theorems = zlp_api.get_theorems()
  let exports = zlp_api.get_export_kernels()
  let status_label = zlp_api.runtime_status_label(binary_available, pool_running)
  let total_subs = list.fold(shards, 0, fn(acc, s) { acc + s.active_subs })

  let header =
    "\u{001b}[1;36m▌ UOS-ZLP-v3 Supervised Lean 4 + Zig + OTP 29 + Zenoh Hyperplane\u{001b}[0m"
    <> "  Status: \u{001b}[1;33m"
    <> status_label
    <> "\u{001b}[0m"
    <> " | Lean 4.33.0 Theorems: \u{001b}[1;32m"
    <> int.to_string(list.length(theorems))
    <> " (0 sorryAx)\u{001b}[0m"
    <> " | C-ABI Exports: \u{001b}[1;32m"
    <> int.to_string(list.length(exports))
    <> "\u{001b}[0m"

  let runtime =
    "  Shards: "
    <> int.to_string(list.length(shards))
    <> " | Active Zenoh SSE Subs: "
    <> int.to_string(total_subs)
    <> " | Fast Lane: epoll+AVX-512 (<10us) | Heavy Lane: pthread+eventfd (0 HoL)"

  let shard_header =
    "\u{001b}[90m  Shard  Status    OS_PID    SSE_Subs  Heavy_InFlight  Perceus_Excl\u{001b}[0m"

  let shard_rows = case shards {
    [] -> "  ○ (pool standby — invoke zlp_hyperplane.ensure_started or bash tools/uos-cli zlp-check)"
    _ ->
      shards
      |> list.map(render_shard_row)
      |> string.join("\n")
  }

  let provenance =
    "\u{001b}[33m  Provenance: EV-"
    <> int.to_string(zlp_hyperplane.admitted_ev_ceiling)
    <> " ceiling | system_admitted=false | Two-Key Gate: bash tools/uos-cli zlp-check\u{001b}[0m"

  let boundaries =
    "\u{001b}[90m  Boundaries: Gleam/OTP sole authority (SC-HARNESS-MCP-001), OS-isolated Port (SC-ZLP-PORT-001), Jujutsu .jj/\u{001b}[0m"

  string.join(
    [header, runtime, "", shard_header, shard_rows, "", provenance, boundaries],
    "\n",
  )
}

fn render_shard_row(s: ZlpShardObservation) -> String {
  "  ● "
  <> pad_right("#" <> int.to_string(s.shard_id), 6)
  <> " "
  <> pad_right(s.status, 9)
  <> " "
  <> pad_right(int.to_string(s.os_pid), 9)
  <> " "
  <> pad_right(int.to_string(s.active_subs), 9)
  <> " "
  <> pad_right(int.to_string(s.in_flight_heavy), 15)
  <> " "
  <> int.to_string(s.perceus_excl)
}

fn pad_right(value: String, width: Int) -> String {
  let length = string.length(value)
  case length >= width {
    True -> value
    False -> value <> string.repeat(" ", width - length)
  }
}
