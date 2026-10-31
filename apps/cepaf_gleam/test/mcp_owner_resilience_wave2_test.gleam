//// Development fault-survival tests for F1, F2/F3, F4 and F5.

import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/route_convergence
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/wire
import cepaf_gleam/mcp/worker
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import simplifile

const root = "/home/an/NAS-setup/uos"

@external(erlang, "mcp_owner_resilience_test_ffi", "suspended_owner")
fn suspended_owner() -> Result(Nil, String)

@external(erlang, "mcp_owner_resilience_test_ffi", "guardian_kill_survival")
fn guardian_kill_survival(
  key: String,
  ledger: receipts.ReceiptLedger,
) -> Result(receipts.ReceiptLedger, String)

@external(erlang, "mcp_owner_resilience_test_ffi", "mirrored_state")
fn mirrored_state(key: String) -> Option(gateway.GatewayState)

@external(erlang, "mcp_owner_resilience_test_ffi", "checkpoint_probe")
fn checkpoint_probe(key: String, repeats: Int) -> #(Int, Int, Int)

@external(erlang, "mcp_owner_resilience_test_ffi", "with_distinct_files")
fn with_distinct_files(check: fn(List(String)) -> Nil) -> Nil

@external(erlang, "persistent_term", "get")
fn current_owner(
  key: atom.Atom,
  fallback: Option(process.Subject(gateway.Message)),
) -> Option(process.Subject(gateway.Message))

@external(erlang, "erlang", "exit")
fn terminate(pid: process.Pid, reason: atom.Atom) -> Bool

@external(erlang, "timer", "sleep")
fn sleep(ms: Int) -> Nil

fn key() -> String {
  root <> ":" <> candidate_id.from_root(root)
}

fn state() -> gateway.GatewayState {
  let assert Some(state) = mirrored_state(key())
  state
}

fn restart_owner() {
  let assert Some(subject) =
    current_owner(atom.create("uos_mcp_runtime_gateway_subject"), None)
  let assert Ok(pid) = process.subject_owner(subject)
  let _ = terminate(pid, atom.create("kill"))
  sleep(20)
  gateway.ensure_started() |> should.be_true
  gateway.is_running() |> should.be_true
}

fn call(tool: String, fields: List(#(String, json.Json))) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(71)),
    #("method", json.string("tools/call")),
    #(
      "params",
      json.object([
        #("name", json.string(tool)),
        #("arguments", json.object(fields)),
      ]),
    ),
  ])
  |> json.to_string
}

fn standard(raw: String) -> String {
  let assert Some(reply) =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      root,
      "wave2-owner-resilience",
      "public",
      raw,
      1,
    )
  reply
}

pub fn f1_suspended_owner_for_2200ms_survives_32_boot_racers_and_8_requests_test() {
  suspended_owner() |> should.equal(Ok(Nil))
}

pub fn f5_guardian_sigkill_preserves_three_uncertain_latches_and_inflight_reaping_test() {
  gateway.ensure_started() |> should.be_true
  let candidate = candidate_id.from_root(root)
  let ledger =
    list.fold(
      ["latch-a", "latch-b", "latch-c"],
      receipts.new_ledger(candidate),
      fn(ledger, id) {
        let assert Ok(recorded) =
          receipts.record_intent(ledger, id, "public", "ping", "fixture")
        receipts.mark_uncertain(recorded, id, "observed interrupted effect").1
      },
    )
  let assert Ok(ledger) =
    receipts.record_intent(ledger, "committed", "public", "ping", "fixture")
  let committed =
    types.Refused(types.ToolError(
      "PRE_EFFECT_REFUSAL",
      "fixture",
      types.NonRetryable,
    ))
  let ledger = receipts.mark_complete(ledger, "committed", committed)
  let assert Ok(restored) =
    guardian_kill_survival("wave2-r05-guardian-fixture", ledger)
  restored |> should.equal(ledger)
  list.each(["latch-a", "latch-b", "latch-c"], fn(id) {
    let #(outcome, _) =
      worker.run_isolated_with_receipts(
        restored,
        id,
        "public",
        "ping",
        "fixture",
        fn() {
          panic as "Uncertain effects must never replay after guardian kill"
        },
      )
    let assert types.Refused(error) = outcome
    error.code |> should.equal("UNCERTAIN_RECEIPT_RECONCILE_REQUIRED")
  })
  gateway.is_running() |> should.be_true
}

pub fn f2_f3_fifty_distinct_reads_keep_corpus_and_replay_checkpoint_bounded_test() {
  gateway.ensure_started() |> should.be_true
  with_distinct_files(fn(paths) {
    let baseline = checkpoint_probe(key(), 10)
    list.each(list.index_map(paths, fn(path, n) { #(path, n) }), fn(pair) {
      let response =
        standard(
          call("read_file", [
            #("path", json.string(pair.0)),
            #(
              "intent_id",
              json.string("wave2-memory-" <> int.to_string(pair.1)),
            ),
          ]),
        )
      json.parse(response, decode.at(["result", "isError"], decode.bool))
      |> should.equal(Ok(False))
    })
    let state = state()
    let corpus = state.backends.knowledge.entries
    let corpus_bytes =
      list.fold(dict.values(corpus), 0, fn(total, entry) {
        total + string.byte_size(entry.content)
      })
    let read_receipts =
      dict.values(state.pool.ledger.entries)
      |> list.filter(fn(entry) { entry.tool == "read_file" })
    let max_replay_payload =
      list.fold(read_receipts, 0, fn(largest, entry) {
        let size = case entry.state {
          receipts.OutcomeCommitted(types.Complete(text, _)) ->
            string.byte_size(text)
          _ -> 0
        }
        int.max(largest, size)
      })
    let after = checkpoint_probe(key(), 10)
    let metrics =
      json.object([
        #("files_read", json.int(50)),
        #("corpus_entries", json.int(dict.size(corpus))),
        #("corpus_bytes", json.int(corpus_bytes)),
        #("max_replay_payload_bytes", json.int(max_replay_payload)),
        #("checkpoint_before_us", json.int(baseline.0)),
        #("checkpoint_after_us", json.int(after.0)),
        #("serialized_state_before_bytes", json.int(baseline.1)),
        #("serialized_state_after_bytes", json.int(after.1)),
        #("ets_before_bytes", json.int(baseline.2)),
        #("ets_after_bytes", json.int(after.2)),
        #(
          "scope",
          json.string(
            "development bounded checkpoint regression; elapsed time is measured, not an asymptotic proof",
          ),
        ),
      ])
      |> json.to_string
    simplifile.write(
      root
        <> "/var/harness/20261030-2325-mcp-resilience/owner-memory-checkpoint-benchmark.json",
      metrics,
    )
    |> should.equal(Ok(Nil))
    should.be_true(dict.size(corpus) <= 64)
    should.be_true(corpus_bytes <= 4 * 1024 * 1024)
    list.each(["AGENTS.md", "CLAUDE.md", "GEMINI.md"], fn(seed) {
      should.be_true(dict.has_key(corpus, seed))
    })
    should.be_true(max_replay_payload <= 16 * 1024)
    should.be_true(after.0 <= int.max(50_000, baseline.0 * 5))
    should.be_true(after.1 <= baseline.1 + 5 * 1024 * 1024)
  })
}

fn no_unresolved(id: String, require_entry: Bool) {
  let entries =
    dict.values(state().pool.ledger.entries)
    |> list.filter(fn(entry) { string.ends_with(entry.intent_id, ":" <> id) })
  case require_entry {
    True -> list.length(entries) |> should.equal(1)
    False -> Nil
  }
  list.each(entries, fn(entry) {
    case entry.state {
      receipts.OutcomeCommitted(types.Refused(_)) -> Nil
      _ ->
        panic as "Known pre-effect refusal must be terminal and never uncertain"
    }
  })
}

pub fn f4_public_pre_effect_path_refusal_is_terminal_across_owner_restart_test() {
  let id = "wave2-public-preeffect"
  let response =
    standard(
      call("read_file", [
        #("path", json.string("/proc/self/environ")),
        #("intent_id", json.string(id)),
      ]),
    )
  json.parse(response, decode.at(["result", "isError"], decode.bool))
  |> should.equal(Ok(True))
  no_unresolved(id, False)
  restart_owner()
  no_unresolved(id, False)
}

pub fn f4_private_readonly_backend_refusal_is_terminal_across_owner_restart_test() {
  gateway.ensure_started() |> should.be_true
  let id = "wave2-private-preeffect"
  let raw = call("harness_status", [#("intent_id", json.string(id))])
  let msg =
    wire.NormalizedMessage(
      wire.IntId(71),
      "tools/call",
      [#("intent_id", id)],
      "",
    )
  let p =
    principal.from_launcher_env(
      "codex",
      types.ClientProfile("codex"),
      root,
      "wave2-private-preeffect",
    )
  let ticket =
    admission.GrantTicket(
      "wave2-fixture-no-effects",
      types.TaskScopedMutation,
      False,
      9_999_999_999_999,
      root,
    )
  let outcome =
    gateway.dispatch_private_live_with_resolver(
      p,
      "successor",
      raw,
      msg,
      fn(_, route, tool, _, _) {
        Ok(
          gateway.PrivateBinding(
            Some(route_convergence.RouteGrant(route, [tool], ticket)),
            Some(admission.TaskFence(
              "wave2-fixture-plan",
              "no-effect-read",
              "codex",
              1,
              admission.TaskExecuting,
              ticket.expires_at_ms,
              Some(ticket),
            )),
            fn() { #(Error("fixture refuses before any effect"), None) },
          ),
        )
      },
    )
  let assert types.Refused(error) = outcome
  error.code |> should.equal("WORKER_ISOLATED_FAILURE")
  no_unresolved(id, True)
  restart_owner()
  no_unresolved(id, True)
}
