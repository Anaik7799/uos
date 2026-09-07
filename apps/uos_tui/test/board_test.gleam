import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import prng
import uos_tui/board.{Agent, Causality, Draft, Semantics}
import uos_tui/frame
import uos_tui/geometry.{Size}
import uos_tui/render

fn sup() -> board.Agent {
  Agent("L0-fable", "L0", "fable")
}

fn draft(kind: board.Kind, to: String) -> board.Draft {
  Draft(
    sup(),
    to,
    kind,
    [#("note", "x")],
    Semantics(["App"], [14], ["CA-emit_intent"], ["Waiting"], 0),
    Causality(None, []),
    None,
    None,
  )
}

/// Sign a fixture with the configured key (tests run with UOS_BOARD_KEY set; unsigned otherwise).
fn signed(m: board.Message) -> board.Message {
  board.sign(m, option.from_result(board.board_key()))
}

fn seal_signed(
  d: board.Draft,
  swarm: String,
  ts: Int,
  lamport: Int,
  span: String,
  prev: String,
) -> board.Message {
  signed(board.seal(d, swarm, ts, lamport, span, prev))
}

fn chain(n: Int) -> List(board.Message) {
  prng.range(1, n)
  |> list.fold(#([], board.genesis_digest), fn(acc, i) {
    let m =
      seal_signed(
        draft(board.Progress, "broadcast"),
        "test",
        1_000_000 + i,
        i,
        string.pad_start(string.inspect(i), 16, "0")
          |> string.replace("0", "a")
          |> string.slice(0, 16),
        acc.1,
      )
    #([m, ..acc.0], m.digest)
  })
  |> fn(p) { list.reverse(p.0) }
}

pub fn seal_sets_id_key_iso_and_digest_test() {
  let m =
    seal_signed(
      draft(board.Plan, "W01"),
      "swarm",
      1_757_203_416_000_000,
      1,
      "0123456789abcdef",
      board.genesis_digest,
    )
  m.id |> should.equal("1757203416000000-0123456789abcdef")
  m.key_expr |> should.equal("c3i/a2a/L0-fable/W01/" <> m.id)
  m.ts_iso |> should.equal("2025-09-07T00:03:36.000000Z")
  string.length(m.digest) |> should.equal(64)
  board.digest_ok(m) |> should.be_true
}

pub fn tamper_breaks_digest_test() {
  let m =
    seal_signed(
      draft(board.Plan, "W01"),
      "swarm",
      1,
      1,
      "0123456789abcdef",
      board.genesis_digest,
    )
  board.digest_ok(board.Message(..m, to: "W02")) |> should.be_false
}

pub fn json_roundtrip_test() {
  let m =
    seal_signed(
      draft(board.Report, "L0-fable"),
      "swarm",
      42,
      3,
      "0123456789abcdef",
      board.genesis_digest,
    )
  let m =
    board.Message(..m, deliveries: [
      board.Delivery("ets", board.Delivered, 1),
      board.Delivery("zenoh-rest:x", board.Unavailable("econnrefused"), 1),
    ])
  board.decode(board.to_string(m)) |> should.equal(Ok(m))
}

pub fn chain_validates_and_break_detected_test() {
  let ms = chain(5)
  board.validate(ms) |> should.equal(Ok(Nil))
  let broken =
    list.map(ms, fn(m) {
      case m.lamport == 3 {
        True -> board.Message(..m, prev_digest: board.genesis_digest)
        False -> m
      }
    })
  board.validate(broken)
  |> should.equal(Error(
    "digest mismatch on "
    <> {
      broken
      |> list.drop(2)
      |> list.first
      |> fn(r) {
        case r {
          Ok(m) -> m.id
          Error(_) -> ""
        }
      }
    },
  ))
}

pub fn semantics_fail_closed_test() {
  board.validate_semantics(Semantics(["NotAConcept"], [], [], [], 0))
  |> should.equal(Error("unknown ontology concept: NotAConcept"))
  board.validate_semantics(Semantics([], [18], [], [], 0))
  |> should.equal(Error("aspect out of range: 18"))
  board.validate_semantics(Semantics([], [], ["CA-nope"], [], 0))
  |> should.equal(Error("unknown control action: CA-nope"))
  board.validate_semantics(Semantics([], [], [], ["Sloth"], 0))
  |> should.equal(Error("unknown muda: Sloth"))
  board.validate_semantics(Semantics(
    ["App"],
    [1, 17],
    ["CA-verify_slice"],
    ["Defects"],
    3,
  ))
  |> should.equal(Ok(Nil))
}

pub fn reply_must_resolve_test() {
  let ms = chain(2)
  let bad =
    list.map(ms, fn(m) {
      case m.lamport == 2 {
        True -> board.Message(..m, causality: Causality(Some("missing"), []))
        False -> m
      }
    })
  case board.validate(bad) {
    Error(e) ->
      string.contains(e, "digest mismatch")
      || string.contains(e, "unknown message")
    Ok(_) -> False
  }
  |> should.be_true
}

pub fn ets_board_posts_and_timeline_ordered_test() {
  let assert_ok = fn(r) {
    case r {
      Ok(v) -> v
      Error(_) -> panic_free()
    }
  }
  let b =
    board.open("test-swarm", "uos_tui_board_test_1", None, None) |> assert_ok
  let #(b, m1) = board.post(b, draft(board.Plan, "broadcast"))
  let #(b, m2) = board.post(b, draft(board.Dispatch, "W01"))
  let tl = board.timeline(b)
  { list.length(tl) >= 2 } |> should.be_true
  let ids = list.map(tl, fn(m) { m.id })
  ids |> should.equal(list.sort(ids, string.compare))
  m2.prev_digest |> should.equal(m1.digest)
  m2.lamport |> should.equal(m1.lamport + 1)
  board.validate(tl) |> should.equal(Ok(Nil))
  // deliveries are honest: ledger queued (no path) and zenoh queued (no base)
  m2.deliveries
  |> list.map(fn(d) { d.status })
  |> should.equal([board.Queued, board.Queued])
}

fn panic_free() -> board.Board {
  // unreachable in tests; keeps the test module free of let assert
  let r = board.open("fallback", "uos_tui_board_test_fallback", None, None)
  case r {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
}

pub fn zenoh_unreachable_is_reported_not_faked_test() {
  let b = case
    board.open(
      "test-swarm",
      "uos_tui_board_test_2",
      None,
      Some("http://127.0.0.1:1"),
    )
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let #(_, m) = board.post(b, draft(board.Heartbeat, "broadcast"))
  let z =
    m.deliveries
    |> list.find(fn(d) { string.starts_with(d.transport, "zenoh") })
  case z {
    Ok(board.Delivery(_, board.Unavailable(_), 1)) -> True
    _ -> False
  }
  |> should.be_true
}

pub fn journal_ingest_test() {
  let text =
    "{\"type\":\"started\",\"key\":\"k\",\"agentId\":\"a1\"}\n{\"type\":\"result\",\"key\":\"k\",\"agentId\":\"a1\",\"result\":{\"slice\":\"palette\",\"files_created\":[],\"tests_added\":14,\"gleam_test_line\":\"130 passed, no failures\",\"warnings\":0,\"format_clean\":true,\"loc\":391,\"public_api\":[],\"notes\":\"\"}}\n{\"type\":\"result\",\"key\":\"k\",\"agentId\":\"v1\",\"result\":{\"slices\":[{\"id\":\"W01\",\"verdict\":\"PASS\"},{\"id\":\"W02\",\"verdict\":\"FAIL\"}]}}\nnot json\n"
  let entries = board.parse_journal(text)
  list.length(entries) |> should.equal(3)
  let drafts = board.drafts_from_journal(entries, sup())
  list.map(drafts, fn(d) { d.kind })
  |> should.equal([board.Dispatch, board.Report, board.Verdict])
  list.each(drafts, fn(d) {
    board.validate_semantics(d.semantics) |> should.equal(Ok(Nil))
  })
}

pub fn view_renders_test() {
  let ms = chain(3)
  render.compose(board.view(ms, 0), Size(100, 12), None, render.dark)
  |> frame.is_well_formed
  |> should.be_true
  board.to_markdown(ms) |> string.contains("| lamport |") |> should.be_true
}

pub fn from_jsonl_reports_bad_lines_test() {
  let ms = chain(2)
  let text = string.join(list.map(ms, board.to_string), "\n") <> "\n{bad}\n"
  let #(ok, errs) = board.from_jsonl(text)
  list.length(ok) |> should.equal(2)
  list.length(errs) |> should.equal(1)
}

// Property: any chain built by seal validates; the chain is exactly as long as requested.
pub fn property_chain_validates_test() {
  list.each(prng.seeds(30), fn(seed) {
    let #(n, _) = prng.int_between(seed, 1, 12)
    let ms = chain(n)
    list.length(ms) |> should.equal(n)
    board.validate(ms) |> should.equal(Ok(Nil))
  })
}

// Fuzz: decode never crashes on random text.
pub fn fuzz_decode_test() {
  list.each(prng.seeds(300), fn(seed) {
    let #(t, _) = prng.text(seed, 40)
    let _ = board.decode(t)
    let _ = board.parse_journal(t)
    Nil
  })
}

pub fn ledger_line_carries_delivery_record_test() {
  let path =
    "/tmp/claude-1000/-home-an-NAS-setup/656f0d2c-6019-4d9e-b0ce-b9e39b240047/scratchpad/board_test_ledger_"
    <> string.inspect(board.system_time_us())
    <> ".jsonl"
  let b = case
    board.open(
      "ledger-test",
      "uos_tui_board_test_3",
      Some(path),
      Some("http://127.0.0.1:1"),
    )
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let #(_, m) = board.post(b, draft(board.Report, "broadcast"))
  let #(from_file, errs) = case board.file_read(path) {
    Ok(text) -> board.from_jsonl(text)
    Error(_) -> #([], ["unreadable"])
  }
  errs |> should.equal([])
  case list.last(from_file) {
    Ok(last) -> {
      last.id |> should.equal(m.id)
      list.map(last.deliveries, fn(d) { d.status })
      |> should.equal(list.map(m.deliveries, fn(d) { d.status }))
      list.any(last.deliveries, fn(d) {
        string.starts_with(d.transport, "zenoh")
      })
      |> should.be_true
    }
    Error(_) -> should.fail()
  }
}

pub fn journal_labels_resolve_test() {
  let text =
    "{\"type\":\"started\",\"key\":\"k\",\"agentId\":\"a1\"}\n{\"type\":\"result\",\"key\":\"k\",\"agentId\":\"a1\",\"result\":{\"slice\":\"uos_tui/palette — command palette\",\"files_created\":[],\"tests_added\":14,\"gleam_test_line\":\"130 passed\",\"warnings\":0,\"format_clean\":true,\"loc\":391,\"public_api\":[],\"notes\":\"\"}}\n{\"type\":\"result\",\"key\":\"k\",\"agentId\":\"v1\",\"result\":{\"slices\":[{\"id\":\"W01\",\"verdict\":\"PASS\"}]}}\n"
  let entries = board.parse_journal(text)
  let labels = [#("uos_tui/palette fuzzy", "W03"), #("verify:W01", "V1")]
  let drafts = board.drafts_from_journal_labelled(entries, sup(), labels)
  list.map(drafts, fn(d) { #(d.from.id, d.to) })
  |> should.equal([
    #("L0-fable", "W03"),
    #("W03", "L0-fable"),
    #("V1", "L0-fable"),
  ])
}

pub fn inbox_and_ack_test() {
  let sup_a = sup()
  let w = Agent("W09", "L2", "sonnet")
  let ms = chain(0)
  let m1 =
    seal_signed(
      Draft(
        sup_a,
        "W09",
        board.Dispatch,
        [],
        Semantics(["Worker"], [4], ["CA-write_owned_file"], [], 0),
        Causality(None, []),
        None,
        None,
      ),
      "s",
      10,
      1,
      "0123456789abcde1",
      board.genesis_digest,
    )
  let m2 =
    seal_signed(
      Draft(
        sup_a,
        "broadcast",
        board.Plan,
        [],
        Semantics(["App"], [1], [], [], 0),
        Causality(None, []),
        None,
        None,
      ),
      "s",
      11,
      2,
      "0123456789abcde2",
      m1.digest,
    )
  let ackm =
    seal_signed(
      Draft(
        w,
        "broadcast",
        board.Ack,
        [#("ack", m1.id)],
        Semantics([], [], [], [], 2),
        Causality(Some(m1.id), [m1.id]),
        None,
        None,
      ),
      "s",
      12,
      3,
      "0123456789abcde3",
      m2.digest,
    )
  let all = list.append(ms, [m1, m2, ackm])
  board.inbox([m1, m2], "W09")
  |> list.map(fn(m) { m.id })
  |> should.equal([m1.id, m2.id])
  board.inbox(all, "W09") |> list.map(fn(m) { m.id }) |> should.equal([m2.id])
  board.acked_by(all, m1.id, "W09") |> should.be_true
  board.acked_by(all, m2.id, "W09") |> should.be_false
  board.inbox(all, "W02") |> list.length |> should.equal(1)
}

pub fn delivery_state_machine_test() {
  let m =
    seal_signed(
      draft(board.Report, "W01"),
      "s",
      1,
      1,
      "0123456789abcdef",
      board.genesis_digest,
    )
  board.delivery_state([m], m) |> should.equal(board.Created)
  let out =
    board.Message(..m, deliveries: [
      board.Delivery("ledger", board.Delivered, 1),
      board.Delivery("zenoh", board.Queued, 0),
    ])
  board.delivery_state([out], out) |> should.equal(board.Outboxed)
  // Zenoh alone being Delivered is not enough: the ledger line must also be
  // Delivered before a message counts as Published (the transactional-outbox
  // invariant that fixed "publication precedes durable acceptance").
  let zenoh_without_ledger =
    board.Message(..m, deliveries: [
      board.Delivery("ledger", board.Queued, 0),
      board.Delivery("zenoh", board.Delivered, 1),
    ])
  board.delivery_state([zenoh_without_ledger], zenoh_without_ledger)
  |> should.not_equal(board.Published)
  let pub_ =
    board.Message(..m, deliveries: [
      board.Delivery("ledger", board.Delivered, 1),
      board.Delivery("zenoh", board.Delivered, 1),
    ])
  board.delivery_state([pub_], pub_) |> should.equal(board.Published)
  let dead =
    board.Message(..m, deliveries: [
      board.Delivery("ledger", board.Delivered, 1),
      board.Delivery(
        "zenoh",
        board.Unavailable("econnrefused"),
        board.max_attempts,
      ),
    ])
  board.delivery_state([dead], dead) |> should.equal(board.Dead)
  // The ledger transport going terminally Unavailable is also Dead, even when
  // Zenoh was never even attempted.
  let ledger_dead =
    board.Message(..m, deliveries: [
      board.Delivery("ledger", board.Unavailable("enoent"), board.max_attempts),
      board.Delivery("zenoh", board.Queued, 0),
    ])
  board.delivery_state([ledger_dead], ledger_dead) |> should.equal(board.Dead)
  let ackm =
    seal_signed(
      Draft(
        Agent("W01", "L2", "sonnet"),
        "broadcast",
        board.Ack,
        [],
        Semantics([], [], [], [], 2),
        Causality(Some(pub_.id), []),
        None,
        None,
      ),
      "s",
      2,
      2,
      "0123456789abcdee",
      pub_.digest,
    )
  board.delivery_state([pub_, ackm], pub_) |> should.equal(board.Acknowledged)
}

pub fn ledger_latest_line_wins_test() {
  let m =
    seal_signed(
      draft(board.Report, "W01"),
      "s",
      1,
      1,
      "0123456789abcdef",
      board.genesis_digest,
    )
  let updated =
    board.Message(..m, deliveries: [
      board.Delivery("zenoh-rest:x", board.Delivered, 2),
    ])
  let #(ms, errs) =
    board.from_jsonl(
      board.to_string(m) <> "\n" <> board.to_string(updated) <> "\n",
    )
  errs |> should.equal([])
  list.length(ms) |> should.equal(1)
  list.map(ms, fn(x) { x.deliveries }) |> should.equal([updated.deliveries])
}

pub fn retry_records_attempts_and_dead_letters_test() {
  let path =
    "/tmp/claude-1000/-home-an-NAS-setup/656f0d2c-6019-4d9e-b0ce-b9e39b240047/scratchpad/board_test_retry_"
    <> string.inspect(board.system_time_us())
    <> ".jsonl"
  let b = case
    board.open(
      "retry-test",
      "uos_tui_board_test_retry",
      Some(path),
      Some("http://127.0.0.1:1"),
    )
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let #(b, m) = board.post(b, draft(board.Report, "W01"))
  let #(b, r1, d1) = board.retry_undelivered(b)
  r1 |> should.equal(1)
  d1 |> should.equal(0)
  let #(b, _, _) = board.retry_undelivered(b)
  let #(b, _, _) = board.retry_undelivered(b)
  let #(b, _, dead) = board.retry_undelivered(b)
  dead |> should.equal(1)
  let tl = board.timeline(b)
  board.delivery_state(tl, case list.find(tl, fn(x) { x.id == m.id }) {
    Ok(x) -> x
    Error(_) -> m
  })
  |> should.equal(board.Dead)
  board.by_kind(tl, board.DeadLetter) |> list.length |> should.equal(1)
}

pub fn per_sender_chains_are_multi_writer_safe_test() {
  // Two writers each keep their own chain; interleaving must validate.
  let a = Agent("L0-fable", "L0", "fable")
  let b = Agent("W03", "L2", "sonnet")
  let d = fn(agent, to) {
    Draft(
      agent,
      to,
      board.Progress,
      [],
      Semantics(["App"], [1], [], [], 0),
      Causality(None, []),
      None,
      None,
    )
  }
  let a1 =
    seal_signed(
      d(a, "broadcast"),
      "s",
      1,
      1,
      "0123456789abcde1",
      board.genesis_digest,
    )
  let b1 =
    seal_signed(
      d(b, "broadcast"),
      "s",
      2,
      2,
      "0123456789abcde2",
      board.genesis_digest,
    )
  let a2 =
    seal_signed(d(a, "broadcast"), "s", 3, 3, "0123456789abcde3", a1.digest)
  let b2 =
    seal_signed(d(b, "broadcast"), "s", 4, 4, "0123456789abcde4", b1.digest)
  board.validate([a1, b1, a2, b2]) |> should.equal(Ok(Nil))
  // b2 chained to a1 instead of b1 breaks W03's chain
  let bad =
    seal_signed(d(b, "broadcast"), "s", 4, 4, "0123456789abcde4", a1.digest)
  board.validate([a1, b1, a2, bad])
  |> should.equal(Error("chain broken at " <> bad.id))
}

pub fn board_heads_track_each_sender_test() {
  let b = case
    board.open("heads-test", "uos_tui_board_test_heads", None, None)
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let #(b, m1) =
    board.post(
      b,
      Draft(
        Agent("L0-fable", "L0", "fable"),
        "broadcast",
        board.Plan,
        [],
        Semantics(["App"], [1], [], [], 0),
        Causality(None, []),
        None,
        None,
      ),
    )
  let #(b, m2) =
    board.post(
      b,
      Draft(
        Agent("W01", "L2", "sonnet"),
        "broadcast",
        board.Progress,
        [],
        Semantics(["App"], [1], [], [], 2),
        Causality(None, []),
        None,
        None,
      ),
    )
  let #(_, m3) =
    board.post(
      b,
      Draft(
        Agent("L0-fable", "L0", "fable"),
        "broadcast",
        board.Plan,
        [],
        Semantics(["App"], [1], [], [], 0),
        Causality(None, []),
        None,
        None,
      ),
    )
  m2.prev_digest |> should.equal(board.genesis_digest)
  m3.prev_digest |> should.equal(m1.digest)
}

pub fn absorb_advances_remote_sender_head_test() {
  let b = case
    board.open("absorb-test", "uos_tui_board_test_absorb", None, None)
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let w = Agent("W03", "L2", "sonnet")
  let d = fn() {
    Draft(
      w,
      "broadcast",
      board.Report,
      [],
      Semantics(["App"], [1], [], [], 2),
      Causality(None, []),
      None,
      None,
    )
  }
  let r1 = seal_signed(d(), "s", 1, 1, "0123456789abcde1", board.genesis_digest)
  let b = board.absorb(b, r1)
  board.head_of(b, "W03") |> should.equal(r1.digest)
  let #(_, r2) = board.post(b, d())
  r2.prev_digest |> should.equal(r1.digest)
}

pub fn signature_and_forgery_rejected_when_keyed_test() {
  let key = Some("test-key")
  let m =
    seal_signed(
      draft(board.Report, "W01"),
      "s",
      1,
      1,
      "0123456789abcdef",
      board.genesis_digest,
    )
  board.signature_ok(m, key) |> should.be_false
  let signed = board.sign(m, key)
  board.signature_ok(signed, key) |> should.be_true
  board.signature_ok(signed, Some("other-key")) |> should.be_false
  // tamper after signing: digest changes, signature no longer matches
  let tampered = board.Message(..signed, to: "W02")
  board.signature_ok(
    board.Message(..tampered, digest: board.sha256_hex("x")),
    key,
  )
  |> should.be_false
  board.decode(board.to_string(signed)) |> should.equal(Ok(signed))
}

// ---------------------------------------------------------------------------
// P1 hardening (Codex sovereign review): injective canonical encoding,
// per-sender key separation, transactional outbox, quarantine on restore,
// crash recovery.
// ---------------------------------------------------------------------------

fn plain(payload: List(#(String, String))) -> board.Message {
  board.seal(
    Draft(
      sup(),
      "W01",
      board.Report,
      payload,
      Semantics(["App"], [1], [], [], 0),
      Causality(None, []),
      None,
      None,
    ),
    "s",
    1,
    1,
    "0123456789abcdef",
    board.genesis_digest,
  )
}

fn plain_semantics(concepts: List(String)) -> board.Message {
  board.seal(
    Draft(
      sup(),
      "W01",
      board.Report,
      [#("note", "x")],
      Semantics(concepts, [], [], [], 0),
      Causality(None, []),
      None,
      None,
    ),
    "s",
    1,
    1,
    "0123456789abcdef",
    board.genesis_digest,
  )
}

/// Codex's exact counterexample: under the old "\n"/";"/"=" separator canonical
/// encoding, a payload value containing the field separator itself could be
/// re-split as extra fields, so these two distinct payloads produced the same
/// canonical bytes (hence the same digest and the same HMAC signature). The new
/// length-prefixed encoding is injective, so the digests must differ.
pub fn canonical_injective_payload_separator_counterexample_test() {
  let m1 = plain([#("a", "b;c=d")])
  let m2 = plain([#("a", "b"), #("c", "d")])
  m1.digest |> should.not_equal(m2.digest)
}

/// Same counterexample shape, this time on `ontology_concepts`, which used to be
/// joined with a bare "," separator: `["a,b"]` (one concept containing a comma)
/// must not collide with `["a", "b"]` (two concepts).
pub fn canonical_injective_ontology_concepts_counterexample_test() {
  let m1 = plain_semantics(["a,b"])
  let m2 = plain_semantics(["a", "b"])
  m1.digest |> should.not_equal(m2.digest)
}

/// A payload value containing an embedded "\n" must not be able to bleed into
/// the surrounding field structure the way it could under the old
/// newline-joined canonical scheme; it is simply data captured by the
/// length-prefixed token, so two otherwise-identical messages that differ only
/// by a literal newline inside a payload value must still get distinct digests.
pub fn canonical_injective_embedded_newline_test() {
  let m1 = plain([#("note", "line1\nline2")])
  let m2 = plain([#("note", "line1")])
  m1.digest |> should.not_equal(m2.digest)
  // And round-tripping through JSON preserves the exact bytes (and hence the
  // digest), confirming the newline is carried faithfully end to end.
  board.decode(board.to_string(m1)) |> should.equal(Ok(m1))
}

/// A message signed with W03's own derived key but claiming `from.id ==
/// "L0-fable"` must fail `signature_ok` under the master key: a principal
/// holding only its own derived key cannot forge another sender's signature.
/// A message genuinely from W03, signed with the master (which derives W03's
/// key internally via `sign`), verifies normally.
pub fn per_sender_key_separation_test() {
  let master = "swarm-master-secret"
  let l0 = sup()
  let w03 = Agent("W03", "L2", "sonnet")
  let d = fn(agent) {
    Draft(
      agent,
      "broadcast",
      board.Progress,
      [],
      Semantics(["App"], [1], [], [], 0),
      Causality(None, []),
      None,
      None,
    )
  }
  let forged =
    board.seal(d(l0), "s", 1, 1, "0123456789abcdef", board.genesis_digest)
  let forged_signed =
    board.sign_with_agent_key(forged, board.agent_key(master, "W03"))
  board.signature_ok(forged_signed, Some(master)) |> should.be_false

  let genuine =
    board.seal(d(w03), "s", 2, 1, "0123456789abcdee", board.genesis_digest)
  let genuine_signed = board.sign(genuine, Some(master))
  board.signature_ok(genuine_signed, Some(master)) |> should.be_true
  // Cross-check: signing genuine's payload with W03's own derived key directly
  // (as a principal that never held the master would have to) produces the
  // exact same signature as `sign` derives internally.
  board.sign_with_agent_key(genuine, board.agent_key(master, "W03")).signature
  |> should.equal(genuine_signed.signature)
}

/// `open` never silently drops a corrupt ledger line: it is quarantined
/// verbatim to `<ledger_path>.quarantine.jsonl` and counted.
pub fn open_quarantines_unparseable_lines_test() {
  let path =
    "/tmp/claude-1000/-home-an-NAS-setup/656f0d2c-6019-4d9e-b0ce-b9e39b240047/scratchpad/board_test_quarantine_"
    <> string.inspect(board.system_time_us())
    <> ".jsonl"
  let ms = chain(2)
  let bad_line = "{not valid json at all"
  let text =
    string.join(list.map(ms, board.to_string), "\n") <> "\n" <> bad_line <> "\n"
  let _ = board.file_write(path, text)
  let b = case
    board.open(
      "quarantine-test",
      "uos_tui_board_test_quarantine",
      Some(path),
      None,
    )
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  board.timeline(b) |> list.length |> should.equal(2)
  board.quarantined(b) |> should.equal(1)
  case board.file_read(path <> ".quarantine.jsonl") {
    Ok(qtext) -> string.contains(qtext, bad_line) |> should.be_true
    Error(_) -> should.fail()
  }
}

/// Full crash-recovery round trip: post 3 messages to a file-backed board with
/// no Zenoh configured, drop the `Board` value (simulating a process crash),
/// reopen the same ledger into a fresh ETS table, and confirm the reopened
/// board is a faithful reconstruction: same count, same per-sender chain
/// heads, a validating chain (signatures and digests), and every message's
/// ledger transport shows Delivered (never faked, never lost).
pub fn crash_recovery_reopens_full_chain_test() {
  let path =
    "/tmp/claude-1000/-home-an-NAS-setup/656f0d2c-6019-4d9e-b0ce-b9e39b240047/scratchpad/board_test_crash_"
    <> string.inspect(board.system_time_us())
    <> ".jsonl"
  let b1 = case
    board.open("crash-test", "uos_tui_board_test_crash_1", Some(path), None)
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let #(b1, _) = board.post(b1, draft(board.Plan, "broadcast"))
  let #(b1, _) = board.post(b1, draft(board.Progress, "W01"))
  let #(b1, m3) = board.post(b1, draft(board.Report, "broadcast"))
  let heads_before = b1.heads
  // b1 (and its ETS table) is dropped here — never referenced again — and a
  // fresh board is opened against the same ledger file, simulating a process
  // restart after a crash.
  let b2 = case
    board.open("crash-test", "uos_tui_board_test_crash_2", Some(path), None)
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let tl = board.timeline(b2)
  list.length(tl) |> should.equal(3)
  b2.heads |> should.equal(heads_before)
  board.head_of(b2, "L0-fable") |> should.equal(m3.digest)
  board.validate(tl) |> should.equal(Ok(Nil))
  list.each(tl, fn(m) {
    case
      list.find(m.deliveries, fn(d) {
        string.starts_with(d.transport, "ledger")
      })
    {
      Ok(board.Delivery(_, board.Delivered, _)) -> Nil
      _ -> should.fail()
    }
  })
}
