import cepaf_gleam/verification/peer_health
import gleam/bit_array
import gleam/bytes_tree
import gleam/string
import gleeunit/should
import indrajaal_gleam_web as web
import mist

pub fn unavailable_report_stays_visible_in_real_api_and_page_test() {
  let report = peer_health.from_observation(
    peer_health.CurrentPeer,
    Ok(#(7, 0, "", 1_788_757_200_000)),
  )
  let response = web.peer_health_response(report)
  response.status |> should.equal(503)
  let assert mist.Bytes(body) = response.body
  let assert Ok(text) = body |> bytes_tree.to_bit_array() |> bit_array.to_string()
  text
  |> string.contains("\"status\":\"UNAVAILABLE\"")
  |> should.be_true()
  let html = web.render_peer_document(report)
  html |> string.contains("UNAVAILABLE") |> should.be_true()
  html |> string.contains("data-peer-state=\"UNAVAILABLE\"") |> should.be_true()
  html
  |> string.contains("href='http://vm-1.tail55d152.ts.net:4100'")
  |> should.be_true()
  html
  |> string.contains("href='http://vm-1.tail55d152.ts.net:8088'")
  |> should.be_false()
}

pub fn reported_metadata_cannot_turn_peer_api_green_test() {
  let report = peer_health.from_observation(
    peer_health.CurrentPeer,
    Ok(#(
      0,
      200,
      "{\"interface\":\"wisp\",\"port\":4100,\"version\":\"1.0.0\"}",
      1_788_757_200_000,
    )),
  )
  let response = web.peer_health_response(report)
  response.status |> should.equal(503)
  let assert mist.Bytes(body) = response.body
  let assert Ok(text) = body |> bytes_tree.to_bit_array() |> bit_array.to_string()
  text |> string.contains("REACHABLE_UNVERIFIED") |> should.be_true()
  text |> string.contains("\"system_green\":false") |> should.be_true()
  web.render_peer_document(report)
  |> string.contains("REACHABLE_UNVERIFIED")
  |> should.be_true()
}
