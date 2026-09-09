import cepaf_gleam/ecology/living_swarm
import cepaf_gleam/ecology/living_swarm_actor
import cepaf_gleam/ui/wisp/router
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/otp/static_supervisor
import gleam/string
import gleeunit/should

pub fn missing_runtime_returns_503_instead_of_reinitializing_test() {
  let assert Ok(req) =
    request.to("http://nas-1.tail55d152.ts.net:4100/api/v1/ecology/swarm")
  let result = router.handle_request(request.set_body(req, ""))
  result.status |> should.equal(503)
  string.contains(result.body, "unavailable") |> should.be_true
  string.contains(result.body, "\"cycle_counter\":1") |> should.be_false
}

pub fn ecology_html_uses_observed_state_and_existing_shell_test() {
  let state = living_swarm.init_living_swarm() |> living_swarm.step_swarm_cycle
  let result = router.ecology_snapshot_response("/ecology", Ok(state))
  result.status |> should.equal(200)
  string.contains(result.body, "Living ecology") |> should.be_true
  string.contains(result.body, "ucon") |> should.be_true
  string.contains(result.body, "indrajaal") |> should.be_true
  string.contains(result.body, "external system bindings are absent")
  |> should.be_true
  string.contains(result.body, "CHK-18-JJ") |> should.be_true
  string.contains(result.body, "18/18 PASS") |> should.be_false
  string.contains(result.body, "aria-label=\"Primary\"") |> should.be_true
  string.contains(result.body, "id=\"ecology-refresh-status\"")
  |> should.be_true
  string.contains(result.body, "fetch('/api/v1/ecology/swarm'")
  |> should.be_true
  string.contains(result.body, "openrouter_free: stopped") |> should.be_true
  response.get_header(result, "content-type")
  |> should.equal(Ok("text/html; charset=utf-8"))
}

pub fn http_reads_preserve_persistent_autonomous_progress_test() {
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(living_swarm_actor.runtime_supervised(20))
    |> static_supervisor.start
  let assert Ok(req) =
    request.to("http://nas-1.tail55d152.ts.net:4100/api/v1/ecology/swarm")
  let first = router.handle_request(request.set_body(req, ""))
  process.sleep(75)
  let second = router.handle_request(request.set_body(req, ""))
  first.status |> should.equal(200)
  second.status |> should.equal(200)
  first.body |> should.not_equal(second.body)
  let assert Ok(state) =
    living_swarm_actor.get_swarm(living_swarm_actor.runtime_subject(), 100)
  should.be_true(state.cycle_counter >= 2)
  string.contains(second.body, "observed_heartbeat") |> should.be_true
  string.contains(second.body, "\"external_system_binding\":false")
  |> should.be_true
  process.unlink(started.pid)
  let assert Ok(pid) =
    process.subject_owner(living_swarm_actor.runtime_subject())
  let monitor = process.monitor(pid)
  process.kill(started.pid)
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(d) { d })
  |> process.selector_receive(500)
  |> should.be_ok
}

pub fn nominal_and_stressed_observations_drive_distinct_input_test() {
  let assert [holon, ..] = living_swarm.init_living_swarm().holons
  living_swarm_actor.local_input(holon, "bayesian") |> should.equal("ok")
  let stressed =
    living_swarm.step_swarm_cycle_observed(
      living_swarm.init_living_swarm(),
      living_swarm.observed_epoch_us(),
      1000.0,
      20.0,
    )
  let assert [holon, ..] = stressed.holons
  living_swarm_actor.local_input(holon, "bayesian") |> should.equal("fail")
  living_swarm_actor.local_input(holon, "ets")
  |> string.contains("homeostatic_error")
  |> should.be_true
  let encoded = living_swarm.swarm_to_json(stressed) |> json.to_string
  string.contains(encoded, "latency energy") |> should.be_true
}
