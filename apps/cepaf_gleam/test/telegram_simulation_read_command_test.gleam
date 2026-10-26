import cepaf_gleam/harness/telegram_simulation_read_command as sim
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

fn keys(reply: String) -> List(String) {
  let assert Ok(ks) =
    json.parse(reply, decode.dict(decode.string, decode.dynamic))
  ks |> dict_keys |> list.sort(string.compare)
}

@external(erlang, "maps", "keys")
fn dict_keys(d: a) -> List(String)

fn status(reply: String) -> String {
  let assert Ok(s) =
    json.parse(reply, {
      use s <- decode.field("status", decode.string)
      decode.success(s)
    })
  s
}

fn has(reply: String, needle: String) -> Bool {
  string.contains(reply, needle)
}

pub fn literal_catalog_test() {
  sim.literals()
  |> should.equal(["/whatif", "/simulate", "/babel", "/canvas", "/whiteboard"])
}

// ---- /whatif

pub fn whatif_claim_positive_test() {
  let r = sim.handle("/whatif", "claim 15")
  status(r) |> should.equal("ok")
  has(r, "\"backend\":\"cepaf_gleam/planning/sa_plan_simulator\"")
  |> should.equal(True)
  has(r, "\"kind\":\"pure_simulation\"") |> should.equal(True)
  has(r, "\"granted\":1") |> should.equal(True)
  has(r, "\"rejected\":14") |> should.equal(True)
  has(r, "\"winner\":\"w1\"") |> should.equal(True)
}

pub fn whatif_claim_negative_test() {
  status(sim.handle("/whatif", "claim 16")) |> should.equal("denied")
  status(sim.handle("/whatif", "claim 0")) |> should.equal("denied")
  status(sim.handle("/whatif", "claim x")) |> should.equal("denied")
  status(sim.handle("/whatif", "")) |> should.equal("denied")
  status(sim.handle("/whatif", "drain nas-1; rm -rf")) |> should.equal("denied")
}

pub fn whatif_retry_positive_test() {
  let r = sim.handle("/whatif", "retry 3")
  status(r) |> should.equal("ok")
  has(r, "\"backoff_seconds\":2") |> should.equal(True)
  has(r, "\"backoff_seconds\":4") |> should.equal(True)
  has(r, "\"backoff_seconds\":8") |> should.equal(True)
  has(r, "\"state\":\"dead\"") |> should.equal(True)
  has(r, "\"attempt\":4") |> should.equal(True)
}

pub fn whatif_retry_negative_test() {
  status(sim.handle("/whatif", "retry 9")) |> should.equal("denied")
  status(sim.handle("/whatif", "retry")) |> should.equal("denied")
}

pub fn whatif_zombie_positive_and_negative_test() {
  let expired = sim.handle("/whatif", "zombie 100 200")
  status(expired) |> should.equal("ok")
  has(expired, "\"reaped\":true") |> should.equal(True)
  has(expired, "\"final_task_state\":\"available\"") |> should.equal(True)
  let live = sim.handle("/whatif", "zombie 300 200")
  has(live, "\"reaped\":false") |> should.equal(True)
  has(live, "\"final_task_state\":\"executing\"") |> should.equal(True)
  status(sim.handle("/whatif", "zombie -1 5")) |> should.equal("denied")
  status(sim.handle("/whatif", "zombie 1")) |> should.equal("denied")
}

// ---- /simulate

pub fn simulate_positive_test() {
  let r = sim.handle("/simulate", "a:nominal b:nominal c:nominal d:partitioned")
  status(r) |> should.equal("ok")
  has(r, "\"backend\":\"cepaf_gleam/zenoh/peer_simulator\"")
  |> should.equal(True)
  has(r, "\"healthy_nodes\":3") |> should.equal(True)
  has(r, "\"total_nodes\":4") |> should.equal(True)
  has(r, "\"quorum_met\":true") |> should.equal(True)
  has(r, "\"circuit_state\":\"open\"") |> should.equal(True)
}

pub fn simulate_two_of_three_misses_067_threshold_test() {
  // 2/3 = 0.666... is below the fixed 0.67 threshold.
  let r = sim.handle("/simulate", "a:nominal b:nominal c:partitioned")
  has(r, "\"quorum_met\":false") |> should.equal(True)
  has(r, "\"healthy_nodes\":2") |> should.equal(True)
}

pub fn simulate_quorum_failure_is_reported_test() {
  let r = sim.handle("/simulate", "a:partitioned b:degraded c:nominal")
  status(r) |> should.equal("ok")
  has(r, "\"quorum_met\":false") |> should.equal(True)
  has(r, "\"healthy_nodes\":1") |> should.equal(True)
}

pub fn simulate_negative_test() {
  status(sim.handle("/simulate", "")) |> should.equal("denied")
  status(sim.handle("/simulate", "a:exploding")) |> should.equal("denied")
  status(sim.handle("/simulate", "a:nominal a:degraded"))
  |> should.equal("denied")
  status(sim.handle("/simulate", "Bad_ID:nominal")) |> should.equal("denied")
  status(sim.handle(
    "/simulate",
    "a:nominal b:nominal c:nominal d:nominal e:nominal f:nominal g:nominal h:nominal",
  ))
  |> should.equal("denied")
}

// ---- /canvas

pub fn canvas_positive_test() {
  let r = sim.handle("/canvas", "a:0,0,0 b:3,4,0 c:-2,10,5")
  status(r) |> should.equal("ok")
  has(r, "\"backend\":\"cepaf_gleam/crdt/spatial\"") |> should.equal(True)
  has(r, "\"element_count\":3") |> should.equal(True)
  has(r, "\"version\":3") |> should.equal(True)
  has(r, "\"split_replicas_merge_converged\":true") |> should.equal(True)
  has(r, "\"bounding_box_min\":{\"x\":-2.0,\"y\":0.0,\"z\":0.0}")
  |> should.equal(True)
  has(r, "\"bounding_box_max\":{\"x\":3.0,\"y\":10.0,\"z\":5.0}")
  |> should.equal(True)
}

pub fn canvas_negative_test() {
  status(sim.handle("/canvas", "")) |> should.equal("denied")
  status(sim.handle("/canvas", "a:1,2")) |> should.equal("denied")
  status(sim.handle("/canvas", "a:1,2,x")) |> should.equal("denied")
  status(sim.handle("/canvas", "a:1,2,3 a:4,5,6")) |> should.equal("denied")
  status(sim.handle("/canvas", "a:1000001,0,0")) |> should.equal("denied")
}

// ---- /babel and /whiteboard

pub fn babel_is_unavailable_test() {
  let r = sim.handle("/babel", "start ja en")
  status(r) |> should.equal("backend_unavailable")
  has(r, "telegram_collab.handle_babel") |> should.equal(True)
  has(r, "\"status\":\"ok\"") |> should.equal(False)
}

pub fn babel_oversize_args_denied_test() {
  status(sim.handle("/babel", string.repeat("a", 257)))
  |> should.equal("denied")
}

pub fn whiteboard_is_unavailable_test() {
  let r = sim.handle("/whiteboard", "")
  status(r) |> should.equal("backend_unavailable")
  has(r, "telegram_collab.handle_whiteboard") |> should.equal(True)
}

pub fn whiteboard_oversize_args_denied_test() {
  status(sim.handle("/whiteboard", string.repeat("a", 257)))
  |> should.equal("denied")
}

// ---- cross-cutting

pub fn unknown_literal_denied_test() {
  let r = sim.handle("/nope", "x")
  r
  |> should.equal(
    "{\"status\":\"denied\",\"command\":\"/nope\",\"reason\":\"not handled by telegram_simulation_read_command\"}",
  )
}

pub fn all_replies_have_closed_key_sets_test() {
  let ok_keys = ["backend", "command", "observation", "status"]
  let denied_keys = ["command", "reason", "status"]
  let unavailable_keys = ["backend", "command", "reason", "status"]
  keys(sim.handle("/whatif", "claim 2")) |> should.equal(ok_keys)
  keys(sim.handle("/simulate", "a:nominal")) |> should.equal(ok_keys)
  keys(sim.handle("/canvas", "a:1,2,3")) |> should.equal(ok_keys)
  keys(sim.handle("/whatif", "bogus")) |> should.equal(denied_keys)
  keys(sim.handle("/nope", "")) |> should.equal(denied_keys)
  keys(sim.handle("/babel", "")) |> should.equal(unavailable_keys)
  keys(sim.handle("/whiteboard", "")) |> should.equal(unavailable_keys)
}

pub fn replies_are_bounded_test() {
  let r =
    sim.handle(
      "/canvas",
      "a:1000000,1000000,1000000 b:-1000000,-1000000,-1000000 c:1,1,1 d:2,2,2 e:3,3,3 f:4,4,4 g:5,5,5 h:6,6,6",
    )
  { string.byte_size(r) <= 3500 } |> should.equal(True)
  status(r) |> should.equal("ok")
}
