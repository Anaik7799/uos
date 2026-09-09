import cepaf_gleam/ecology/living_swarm
import gleam/http
import gleam/http/request
import gleeunit/should
import indrajaal/ecology_service
import indrajaal/runtime_identity

fn identity() {
  runtime_identity.from_observation(
    runtime_identity.Vm("29", "17.0.5", "123", "test-run", 1, 2, 1),
    runtime_identity.Configuration("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "test", "primary", True),
  )
}

pub fn live_identity_and_actor_are_required_for_health_test() {
  let assert Ok(req) = request.to("http://nas-1.tail55d152.ts.net:4110/health")
  ecology_service.handle_snapshot(req, Error("absent"), identity()).status |> should.equal(503)
  let initial = living_swarm.init_living_swarm()
  ecology_service.handle_snapshot(req, Ok(initial), identity()).status |> should.equal(503)
  ecology_service.handle_snapshot(req, Ok(living_swarm.SwarmEcology(..initial, cycle_counter: 1)), identity()).status |> should.equal(200)
}

pub fn file_and_mutation_routes_are_absent_test() {
  let assert Ok(req) = request.to("http://nas-1.tail55d152.ts.net:4110/files/.codex/config.toml")
  ecology_service.handle_snapshot(req, Error("absent"), identity()).status |> should.equal(404)
  let post = request.set_method(req, http.Post)
  ecology_service.handle_snapshot(post, Error("absent"), identity()).status |> should.equal(405)
}
