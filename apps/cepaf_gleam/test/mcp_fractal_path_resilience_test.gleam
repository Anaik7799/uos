//// L0..L9 operational paths and bounded fault containment. Missing observations
//// remain explicit refusals; fixtures never turn absent probes into health.

import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/dispatch
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import simplifile

const root = "/home/an/NAS-setup/uos"

const candidate = "sha256:5fb7a77609e9f41f8368fc5a761435dec6519736a00f4642d6e986ca3e8e1663"

fn frame(method: String, params: json.Json) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(79)),
    #("method", json.string(method)),
    #("params", params),
  ])
  |> json.to_string
}

fn standard(raw: String, actor: String) -> String {
  let assert Some(body) =
    gateway.handle_standard_mcp_line(
      actor,
      actor,
      root,
      "fractal-" <> actor,
      "public",
      raw,
      3_000_000,
    )
  json.parse(body, decode.at(["id"], decode.int)) |> should.equal(Ok(79))
  body
}

fn provenance() {
  let body =
    standard(
      frame(
        "resources/read",
        json.object([
          #("uri", json.string("uos://governance/ev-provenance-ceiling")),
        ]),
      ),
      "codex",
    )
  string.contains(body, "93") |> should.be_true
  string.contains(body, "false") |> should.be_true
}

fn tool(
  name: String,
  args: List(#(String, json.Json)),
  actor: String,
) -> String {
  standard(
    frame(
      "tools/call",
      json.object([
        #("name", json.string(name)),
        #("arguments", json.object(args)),
      ]),
    ),
    actor,
  )
}

fn operational_or_honestly_unobserved(body: String) {
  let assert Ok(is_error) =
    json.parse(body, decode.at(["result", "isError"], decode.bool))
  case is_error {
    False ->
      json.parse(
        body,
        decode.at(["result", "_meta", "candidate"], decode.string),
      )
      |> should.equal(Ok(candidate))
    True -> {
      let assert Ok(content) =
        json.parse(
          body,
          decode.at(
            ["result", "content"],
            decode.list(decode.at(["text"], decode.string)),
          ),
        )
      let text = string.concat(content)
      // These bounded backend limits are assertions, never passing health.
      should.be_true(
        list.any(
          [
            "OBSERVATION_PROBE_MISSING",
            "CONTAINER_PROBE_MISSING",
            "MISSING_ARGUMENT",
            "INVALID_",
            "KNOWLEDGE_",
            "NOT_FOUND",
            "INFERENCE_",
            "MAX_",
            "NO_MATCH",
            "PATH_NOT_IN_CORPUS",
            "SA_PLAN_",
            "VERIFICATION_",
            "MODEL_",
          ],
          fn(code) { string.contains(text, code) },
        ),
      )
    }
  }
}

fn layer_path(layer: Int, names: List(String)) {
  list.each(names, fn(name) {
    let args = case name {
      "preflight_check" -> [#("benefit", json.int(95)), #("cost", json.int(5))]
      "lyapunov_trend_predict" -> [#("series", json.string("49,1,0"))]
      "stpa_fmea_hazard" -> [
        #("severity", json.int(4)),
        #("occurrence", json.int(2)),
        #("detection", json.int(2)),
      ]
      "rete_rule_conflict" -> [#("rules", json.string("a->b;a->c"))]
      "ruliad_branch_eval" -> [#("branches", json.string("1,2,3"))]
      "read_file" -> [#("path", json.string("AGENTS.md"))]
      "knowledge_search" -> [#("query", json.string("Unified"))]
      "zk_transclude" -> [#("key", json.string("AGENTS.md"))]
      "sa_plan_status" | "sa_plan_status_for" | "plan_status" -> [
        #(
          "plan_id",
          json.string("20261030-2325-mcp-resilience-perf-scale-bdd-fractal"),
        ),
      ]
      _ -> []
    }
    operational_or_honestly_unobserved(tool(name, args, "codex"))
  })
  // Inject at Lk; re-observe the lower constitutional boundary and mailbox.
  let rejected = tool("unavailable_at_L" <> int.to_string(layer), [], "codex")
  json.parse(rejected, decode.at(["result", "isError"], decode.bool))
  |> should.equal(Ok(True))
  provenance()
  standard(frame("ping", json.object([])), "codex")
  |> string.contains("\"result\"")
  |> should.be_true
  gateway.is_running() |> should.be_true
}

pub fn l0_constitutional_provenance_and_fault_containment_test() {
  provenance()
  layer_path(0, ["dark_cockpit_mode", "integrity_check"])
}

pub fn l1_worker_timeout_poison_and_cellular_containment_test() {
  let assert Ok(pool) = supervisor.start_worker_pool_for_candidate(1, candidate)
  let #(timeout, next) =
    dispatch.execute_on_pool(
      pool,
      "public",
      "fixture-timeout",
      "l1-timeout",
      dispatch.SimulateWorkerTimeout(1),
    )
  let assert types.Refused(error) = timeout
  error.code |> should.equal("WORKER_DEADLINE_EXCEEDED")
  next.active_generation |> should.equal(pool.active_generation + 1)
  let #(crash, _) =
    dispatch.execute_on_pool(
      next,
      "public",
      "fixture-crash",
      "l1-crash",
      dispatch.SimulateCrashBeforeEffect("fixture-before-effect"),
    )
  let assert types.Refused(error) = crash
  error.retryability |> should.equal(types.Retryable)
  layer_path(1, ["mcp_capability_inventory"])
}

pub fn l2_wire_schema_profile_and_delimiter_containment_test() {
  receipts.hash_payload("t", [#("a", "x&b=y")])
  |> should.not_equal(receipts.hash_payload("t", [#("a", "x"), #("b", "y")]))
  candidate_id.from_root(root) |> should.equal(candidate)
  layer_path(2, ["preflight_check"])
}

pub fn l3_four_agent_principal_isolation_and_holon_containment_test() {
  list.each(["agy", "claude", "codex", "pi"], fn(actor) {
    operational_or_honestly_unobserved(tool(
      "mcp_capability_inventory",
      [],
      actor,
    ))
  })
  layer_path(3, ["holon_status", "agent_hierarchy"])
}

pub fn l4_substrate_observation_and_path_injection_containment_test() {
  let traversal =
    tool("read_file", [#("path", json.string("../../etc/shadow"))], "codex")
  json.parse(traversal, decode.at(["result", "isError"], decode.bool))
  |> should.equal(Ok(True))
  layer_path(4, ["podman_containers", "system_health", "read_file"])
}

pub fn l5_metabolic_missing_probe_is_not_synthetic_health_test() {
  layer_path(5, [
    "metabolic_state",
    "prajna_health",
    "lyapunov_trend_predict",
    "system_verification",
  ])
}

pub fn l6_mesh_observation_failure_does_not_take_down_gateway_test() {
  layer_path(6, ["system_zenoh", "mesh_topology", "swarm_status"])
}

pub fn l7_canonical_planning_federation_fault_containment_test() {
  layer_path(7, ["plan_status", "sa_plan_status", "sa_plan_list"])
}

pub fn l8_knowledge_resources_and_advisory_prompt_containment_test() {
  let resources = standard(frame("resources/list", json.object([])), "codex")
  string.contains(resources, "uos://") |> should.be_true
  let prompt =
    standard(
      frame(
        "prompts/get",
        json.object([#("name", json.string("uos_poodavr_review"))]),
      ),
      "codex",
    )
  string.contains(prompt, "advisory_only") |> should.be_true
  layer_path(8, [
    "knowledge_search",
    "kms_catalog",
    "zk_transclude",
    "ggram_synthesize",
  ])
}

pub fn l9_poodavr_analysis_and_sovereign_ceiling_containment_test() {
  layer_path(9, [
    "ooda_phase",
    "ooda_decide",
    "stpa_fmea_hazard",
    "rete_rule_conflict",
    "ruliad_branch_eval",
    "preflight_check",
    "feature_tracker_status",
    "mcp_capability_inventory",
  ])
}

pub fn l4_symlink_hardlink_and_nul_refusals_preserve_gateway_test() {
  let base = "var/harness/20261030-2325-mcp-resilience/l4-link-fixture"
  let assert Ok(Nil) = simplifile.create_directory_all(root <> "/" <> base)
  let target = root <> "/" <> base <> "/target.txt"
  let symlink = root <> "/" <> base <> "/symbol.txt"
  let hardlink = root <> "/" <> base <> "/hard.txt"
  let _ = simplifile.delete(symlink)
  let _ = simplifile.delete(hardlink)
  let assert Ok(Nil) = simplifile.write(target, "fixture only")
  let assert Ok(Nil) = simplifile.create_symlink(target, symlink)
  let assert Ok(Nil) = simplifile.create_link(target, hardlink)
  list.each([base <> "/symbol.txt", base <> "/hard.txt"], fn(path) {
    let body = tool("read_file", [#("path", json.string(path))], "codex")
    json.parse(body, decode.at(["result", "isError"], decode.bool))
    |> should.equal(Ok(True))
    string.contains(body, "LINK_ESCAPE_REFUSED") |> should.be_true
  })
  let body =
    tool("read_file", [#("path", json.string("bad\u{0000}path"))], "codex")
  string.contains(body, "NUL_BYTE_FORBIDDEN") |> should.be_true
  let assert Ok(Nil) = simplifile.delete(symlink)
  let assert Ok(Nil) = simplifile.delete(hardlink)
  let assert Ok(Nil) = simplifile.delete(target)
  let assert Ok(Nil) = simplifile.delete(root <> "/" <> base)
  provenance()
  gateway.is_running() |> should.be_true
}
