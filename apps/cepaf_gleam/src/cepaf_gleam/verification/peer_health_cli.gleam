import cepaf_gleam/verification/peer_health
import gleam/io

@external(erlang, "cepaf_gleam_ffi", "get_arguments")
fn arguments() -> List(String)

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn main() {
  case arguments() {
    ["current"] -> print_report(peer_health.observe(peer_health.CurrentPeer))
    ["obsolete"] -> print_report(peer_health.observe(peer_health.ObsoletePeer))
    _ -> {
      io.println("Expected current or obsolete")
      halt(2)
    }
  }
}

fn print_report(report: peer_health.Report) {
  report |> peer_health.to_json() |> io.println()
  halt(peer_health.exit_code(report))
}
