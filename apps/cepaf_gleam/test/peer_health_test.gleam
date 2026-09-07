import cepaf_gleam/ui/lustre/peer_health_view
import cepaf_gleam/verification/peer_health
import gleam/string
import gleeunit/should
import lustre/element

pub fn refused_observation_remains_unavailable_test() {
  let report =
    peer_health.from_observation(peer_health.ObsoletePeer, Ok(#(7, 0, "", 123)))
  peer_health.state_name(report) |> should.equal("UNAVAILABLE")
  peer_health.system_green(report) |> should.be_false()
  peer_health.exit_code(report) |> should.equal(1)
}

pub fn http_success_cannot_create_system_health_test() {
  let report =
    peer_health.from_observation(
      peer_health.CurrentPeer,
      Ok(#(
        0,
        200,
        "{\"interface\":\"wisp\",\"port\":4100,\"version\":\"1.0.0\",\"system_green\":true}",
        123,
      )),
    )
  peer_health.state_name(report) |> should.equal("REACHABLE_UNVERIFIED")
  peer_health.system_green(report) |> should.be_false()
  peer_health.exit_code(report) |> should.equal(1)
}

pub fn malformed_and_foreign_identity_fail_closed_test() {
  let bodies = [
    "not json",
    "{}",
    "{\"interface\":\"other\",\"port\":8080,\"version\":\"1\"}",
  ]
  check_invalid(bodies)
}

fn check_invalid(bodies: List(String)) {
  case bodies {
    [] -> Nil
    [body, ..rest] -> {
      let report =
        peer_health.from_observation(
          peer_health.CurrentPeer,
          Ok(#(0, 200, body, 123)),
        )
      peer_health.state_name(report) |> should.equal("IDENTITY_MISMATCH")
      peer_health.system_green(report) |> should.be_false()
      check_invalid(rest)
    }
  }
}

pub fn failing_http_and_probe_quota_are_nonpassing_test() {
  let http =
    peer_health.from_observation(
      peer_health.CurrentPeer,
      Ok(#(0, 503, "{}", 123)),
    )
  let quota =
    peer_health.from_observation(peer_health.CurrentPeer, Error("quota"))
  peer_health.state_name(http) |> should.equal("HTTP_FAILURE")
  peer_health.state_name(quota) |> should.equal("UNAVAILABLE")
  peer_health.system_green(http) |> should.be_false()
  peer_health.system_green(quota) |> should.be_false()
}

pub fn unavailable_ui_and_json_share_the_actual_state_test() {
  let report =
    peer_health.from_observation(peer_health.ObsoletePeer, Ok(#(7, 0, "", 123)))
  let html = peer_health_view.view(report) |> element.to_string()
  string.contains(html, "data-peer-state=\"UNAVAILABLE\"") |> should.be_true()
  string.contains(html, peer_health.current_url) |> should.be_true()
  string.contains(peer_health.to_json(report), "\"status\":\"UNAVAILABLE\"")
  |> should.be_true()
}

pub fn duplicate_identity_and_trailing_documents_are_rejected_test() {
  check_invalid([
    "{\"interface\":\"wisp\",\"port\":8080,\"port\":4100,\"version\":\"1\"}",
    "{\"interface\":\"wisp\",\"port\":4100,\"version\":\"1\",\"metadata\":{\"x\":1,\"x\":2}}",
    "{\"interface\":\"wisp\",\"port\":4100,\"version\":\"1\"} {}",
    "{\"interface\":\"wisp\",\"port\":4100,\"version\":\"1\",\"metadata\":"
      <> string.repeat("[", 33)
      <> "0"
      <> string.repeat("]", 33)
      <> "}",
  ])
}
