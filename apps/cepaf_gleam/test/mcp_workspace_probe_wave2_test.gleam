//// Actual filesystem/probe regressions for bounded transient knowledge.

import cepaf_gleam/mcp/adapters/knowledge
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/workspace_knowledge
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/order
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "erlang", "unique_integer")
fn unique_integer(options: List(atom.Atom)) -> Int

fn fixture(run_case: fn(String) -> Nil) -> Nil {
  let root =
    "/tmp/uos-wave2-knowledge-"
    <> int.to_string(now_ns())
    <> "-"
    <> int.to_string(
      unique_integer([atom.create("positive"), atom.create("monotonic")]),
    )
  let assert Ok(_) = simplifile.create_directory(root)
  let assert Ok(_) = simplifile.create_directory_all(root <> "/docs/zk")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/docs/wiki")
  put(root, "AGENTS.md", "seed governance")
  put(root, "CLAUDE.md", "seed claude")
  put(root, "GEMINI.md", "seed gemini")
  run_case(root)
  let assert Ok(_) = simplifile.delete(root)
  Nil
}

fn put(root: String, rel: String, body: String) -> Nil {
  let assert Ok(_) = simplifile.write(root <> "/" <> rel, body)
  Nil
}

fn names(entries: List(knowledge.CorpusEntry)) -> List(String) {
  list.map(entries, fn(entry) { entry.rel_path })
}

fn seed_names() -> List(String) {
  ["AGENTS.md", "CLAUDE.md", "GEMINI.md"]
}

pub fn workspace_exact_and_keyword_prefetch_preserve_seeds_and_discover_only_markdown_test() {
  fixture(fn(root) {
    put(root, "docs/zk/one.md", "supervisor resilience")
    put(root, "docs/wiki/two.md", "formal supervisor")
    put(root, "docs/zk/data.json", "supervisor private JSON")
    put(root, "docs/unscoped.md", "supervisor outside declared corpus")
    let exact = workspace_knowledge.prefetch(root, "docs/zk/one.md")
    names(exact)
    |> should.equal(["AGENTS.md", "CLAUDE.md", "GEMINI.md", "docs/zk/one.md"])
    let matched = workspace_knowledge.prefetch(root, "supervisor")
    names(matched)
    |> list.sort(string.compare)
    |> should.equal([
      "AGENTS.md",
      "CLAUDE.md",
      "GEMINI.md",
      "docs/wiki/two.md",
      "docs/zk/one.md",
    ])
    matched |> should.equal(workspace_knowledge.prefetch(root, "supervisor"))
    list.each(matched, fn(entry) {
      entry.link_kind |> should.equal(knowledge.RegularFile)
    })
  })
}

pub fn workspace_prefetch_refuses_links_nuls_and_path_escapes_test() {
  fixture(fn(root) {
    put(root, "outside.md", "needle external")
    let assert Ok(_) =
      simplifile.create_symlink(
        "../../outside.md",
        root <> "/docs/zk/symlink.md",
      )
    let assert Ok(_) =
      simplifile.create_link(
        root <> "/outside.md",
        root <> "/docs/zk/hardlink.md",
      )
    let assert Ok(_) =
      simplifile.create_symlink("../..", root <> "/docs/zk/dirlink")
    put(root, "docs/zk/nul.md", "needle before\u{0000}after")
    workspace_knowledge.prefetch(root, "needle")
    |> names
    |> should.equal(seed_names())
    list.each(
      [
        "../outside.md",
        "/etc/passwd",
        "docs/zk/../../outside.md",
        "needle\u{0000}query",
      ],
      fn(query) {
        workspace_knowledge.prefetch(root, query) |> should.equal([])
      },
    )
    workspace_knowledge.prefetch(root <> "/docs/zk/dirlink", "needle")
    |> should.equal([])
  })
}

pub fn workspace_entry_and_aggregate_byte_quotas_keep_all_three_seeds_test() {
  fixture(fn(root) {
    let one_mib = string.repeat("x", 1_048_576)
    put(root, "AGENTS.md", one_mib)
    put(root, "CLAUDE.md", one_mib)
    put(root, "GEMINI.md", one_mib)
    put(root, "docs/zk/a.md", one_mib)
    put(root, "docs/zk/b.md", "x")
    put(root, "docs/zk/too-large.md", one_mib <> "x")
    let entries = workspace_knowledge.prefetch(root, "x")
    names(entries)
    |> should.equal(["AGENTS.md", "CLAUDE.md", "GEMINI.md", "docs/zk/a.md"])
    list.fold(entries, 0, fn(acc, entry) {
      acc + string.byte_size(entry.content)
    })
    |> should.equal(4_194_304)
  })
}

pub fn workspace_cardinality_is_capped64_and_directory_depth4_test() {
  fixture(fn(root) {
    let assert Ok(_) =
      simplifile.create_directory_all(root <> "/docs/zk/a/b/c/d/e")
    put(root, "docs/zk/a/b/c/d/accepted.md", "depth marker")
    put(root, "docs/zk/a/b/c/d/e/rejected.md", "depth marker")
    let deep = workspace_knowledge.prefetch(root, "depth marker") |> names
    list.contains(deep, "docs/zk/a/b/c/d/accepted.md") |> should.be_true
    list.contains(deep, "docs/zk/a/b/c/d/e/rejected.md") |> should.be_false
    let _ =
      int.range(0, 75, Nil, fn(_, n) {
        put(
          root,
          "docs/wiki/doc-" <> int.to_string(n) <> ".md",
          "bounded corpus needle",
        )
      })
    let entries = workspace_knowledge.prefetch(root, "needle")
    list.length(entries) |> should.equal(64)
    list.each(seed_names(), fn(name) {
      list.contains(names(entries), name) |> should.be_true
    })
  })
}

pub fn workspace_discovery_inspects_at_most512_directory_entries_test() {
  fixture(fn(root) {
    let _ =
      int.range(0, 520, Nil, fn(_, n) {
        put(root, "docs/zk/a-" <> int.to_string(n) <> ".md", "irrelevant")
      })
    put(root, "docs/zk/z-after-budget.md", "needle")
    workspace_knowledge.prefetch(root, "needle")
    |> names
    |> should.equal(seed_names())
  })
}

fn live(tool: String) -> String {
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(1)),
      #("method", json.string("tools/call")),
      #(
        "params",
        json.object([
          #("name", json.string(tool)),
          #("arguments", json.object([])),
        ]),
      ),
    ])
    |> json.to_string
  let assert Some(frame) =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      "/home/an/NAS-setup/uos",
      "wave2-observed-probes",
      "public",
      raw,
      now_ms(),
    )
  frame
}

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn now_ns() -> Int

fn now_ms() -> Int {
  now_ns() / 1_000_000
}

fn payload(frame: String) -> String {
  json.parse(frame, decode.at(["result", "isError"], decode.bool))
  |> should.equal(Ok(False))
  json.parse(
    frame,
    decode.at(
      ["result", "content"],
      decode.list(decode.at(["text"], decode.string)),
    ),
  )
  |> should.be_ok
  |> list.first
  |> should.be_ok
}

pub fn live_health_dashboard_and_metabolic_probes_carry_actual_beam_fields_test() {
  list.each(["system_health", "system_dashboard", "metabolic_state"], fn(tool) {
    let body = payload(live(tool))
    json.parse(body, decode.at(["process_count"], decode.int))
    |> should.be_ok
    |> int.compare(0)
    |> should.equal(order.Gt)
    json.parse(body, decode.at(["probe_kind"], decode.string))
    |> should.be_ok
    |> string.is_empty
    |> should.be_false
    json.parse(body, decode.at(["observed_source"], decode.string))
    |> should.be_ok
    |> string.is_empty
    |> should.be_false
    json.parse(body, decode.at(["effect_authority"], decode.bool))
    |> should.equal(Ok(False))
  })
}

pub fn live_unwired_kms_stays_fail_closed_and_container_inventory_is_observed_test() {
  let missing = live("kms_catalog")
  json.parse(missing, decode.at(["result", "isError"], decode.bool))
  |> should.equal(Ok(True))
  string.contains(missing, "OBSERVATION_PROBE_MISSING") |> should.be_true
  let containers = live("podman_containers")
  case json.parse(containers, decode.at(["result", "isError"], decode.bool)) {
    Ok(True) ->
      string.contains(containers, "CONTAINER_PROBE_MISSING") |> should.be_true
    Ok(False) -> {
      let body = payload(containers)
      let count =
        json.parse(body, decode.at(["container_count"], decode.int))
        |> should.be_ok
      let names =
        json.parse(body, decode.at(["containers"], decode.list(decode.string)))
        |> should.be_ok
      list.length(names) |> should.equal(count)
      json.parse(body, decode.at(["probe_completed"], decode.bool))
      |> should.equal(Ok(True))
    }
    _ -> should.fail()
  }
}
