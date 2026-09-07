import cepaf_gleam/verification/peer_health
import gleam/io

@external(erlang, "cepaf_gleam_ffi", "get_arguments")
fn arguments() -> List(String)

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn main() {
  case arguments() {
    ["current"] ->
      peer_health.observe(peer_health.CurrentPeer)
      |> peer_health.to_json()
      |> io.println()
    ["obsolete"] ->
      peer_health.observe(peer_health.ObsoletePeer)
      |> peer_health.to_json()
      |> io.println()
    _ -> {
      io.println("Expected current or obsolete")
      halt(2)
    }
  }
}
