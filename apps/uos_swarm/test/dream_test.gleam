import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import uos_swarm/acl
import uos_swarm/board.{Agent, Causality, Draft, Semantics}
import uos_swarm/dream

fn span(i: Int) -> String {
  string.pad_start(int.to_string(i), 16, "0")
}

fn msg(
  from: String,
  layer: String,
  to: String,
  kind: board.Kind,
  payload: List(#(String, String)),
  aspects: List(Int),
  i: Int,
) -> board.Message {
  let draft =
    Draft(
      Agent(from, layer, "sonnet"),
      to,
      kind,
      payload,
      Semantics(["Worker"], aspects, ["CA-emit_intent"], [], 2),
      Causality(None, []),
      None,
      None,
    )
  board.seal(
    draft,
    "test-hive",
    1_700_000_000_000_000 + i,
    i,
    span(i),
    board.genesis_digest,
  )
}

/// A small synthetic ledger exercising every `svapna` signal generator
/// exactly once: one aspect-15 audit failure on two subjects (V1), three
/// W03 Progress posts with no Verdict anywhere naming W03 (W03 also posts a
/// Heartbeat, so it does NOT also trip the missing-heartbeat generator),
/// two W04 posts with no Heartbeat among them (the one sender left to trip
/// missing-heartbeat), one dead-lettered delivery to W05, one refused
/// authorization Andon from W06, and two unanswered Questions from W07 (W07
/// also posts a Heartbeat, for the same reason as W03).
fn ledger() -> List(board.Message) {
  [
    msg(
      "V1",
      "L3",
      "uos-coord",
      board.Verdict,
      [#("sliceA", "FAIL"), #("sliceB", "FAIL")],
      [15],
      1,
    ),
    msg("W03", "L2", "uos-coord", board.Progress, [#("note", "1")], [3], 2),
    msg("W03", "L2", "uos-coord", board.Progress, [#("note", "2")], [3], 3),
    msg("W03", "L2", "uos-coord", board.Progress, [#("note", "3")], [3], 4),
    msg("W03", "L2", "uos-coord", board.Heartbeat, [], [], 5),
    msg("W04", "L2", "uos-coord", board.Progress, [#("note", "1")], [3], 6),
    msg("W04", "L2", "uos-coord", board.Claim, [#("note", "2")], [3], 7),
    msg(
      "uos-coord",
      "L1",
      "W05",
      board.DeadLetter,
      [#("dead", "some-id"), #("attempts", "5")],
      [10],
      8,
    ),
    msg(
      "W06",
      "L2",
      "uos-coord",
      board.Andon,
      [#("reason", "refused: unknown target")],
      [1],
      9,
    ),
    msg("W07", "L2", "uos-coord", board.Question, [#("q", "why?")], [13], 10),
    msg("W07", "L2", "uos-coord", board.Question, [#("q", "why2?")], [13], 11),
    msg("W07", "L2", "uos-coord", board.Heartbeat, [], [], 12),
  ]
}

/// One contradicted belief (Viparyaya, see `agent_runtime.classify_slot`)
/// and one confirmed belief (Pramana, so it must NOT yield a hypothesis).
fn slots() -> List(#(String, String)) {
  [
    #("belief/palette-tests", "contradicted by V1 audit"),
    #("belief/other", "verified pass"),
  ]
}

pub fn idle_gate_test() {
  dream.idle(0, 0) |> should.be_true
  dream.idle(1, 0) |> should.be_false
  dream.idle(0, 1) |> should.be_false
  dream.idle(2, 3) |> should.be_false
}

pub fn svapna_deterministic_for_a_seed_test() {
  let d1 = dream.svapna(ledger(), slots(), 42, 10)
  let d2 = dream.svapna(ledger(), slots(), 42, 10)
  d1 |> should.equal(d2)
  // Every generator above is engineered to fire exactly once: aspect,
  // verifier, heartbeat, dead-letter, refused-auth, unanswered-question,
  // contradicted-belief.
  list.length(d1.hypotheses) |> should.equal(7)
  d1.consolidated
  |> should.equal(list.length(ledger()) + list.length(slots()))
}

pub fn svapna_bounded_by_max_test() {
  let d = dream.svapna(ledger(), slots(), 42, 3)
  list.length(d.hypotheses) |> should.equal(3)
}

pub fn svapna_different_seed_can_change_order_but_not_signal_count_test() {
  let a = dream.svapna(ledger(), slots(), 1, 10)
  let b = dream.svapna(ledger(), slots(), 2, 10)
  list.length(a.hypotheses) |> should.equal(list.length(b.hypotheses))
}

pub fn hypotheses_reference_real_message_ids_test() {
  let real_ids = ledger() |> list.map(fn(m) { m.id })
  let d = dream.svapna(ledger(), slots(), 7, 10)
  list.each(d.hypotheses, fn(h) {
    list.each(h.basis, fn(b) {
      { list.contains(real_ids, b) || b == "belief/palette-tests" }
      |> should.be_true
    })
  })
  // The aspect-15 hypothesis is grounded in the one Verdict message that
  // reported it.
  let verdict_id =
    ledger()
    |> list.find(fn(m) { m.kind == board.Verdict })
    |> fn(r) {
      case r {
        Ok(m) -> m.id
        Error(_) -> ""
      }
    }
  let aspect_h =
    d.hypotheses
    |> list.find(fn(h) { h.aspects == [15] })
  case aspect_h {
    Ok(h) -> h.basis |> should.equal([verdict_id])
    Error(_) -> should.fail()
  }
}

pub fn confidence_is_strictly_open_interval_test() {
  let d = dream.svapna(ledger(), slots(), 3, 10)
  list.each(d.hypotheses, fn(h) {
    { h.confidence >. 0.0 && h.confidence <. 1.0 } |> should.be_true
  })
}

pub fn proposed_action_is_from_fixed_vocabulary_test() {
  let allowed = [
    "audit", "verify", "retire", "escalate", "route-cheaper", "document",
    "no-op",
  ]
  let d = dream.svapna(ledger(), slots(), 9, 10)
  list.each(d.hypotheses, fn(h) {
    list.contains(allowed, h.proposed_action) |> should.be_true
  })
}

pub fn utterance_parses_and_validates_with_hypotheses_test() {
  let d = dream.svapna(ledger(), slots(), 5, 10)
  let text = dream.to_utterance_text(d, "hive-l1")
  let u = acl.parse(text) |> should.be_ok
  u.perf |> should.equal(acl.Hypothesize)
  acl.validate(u) |> should.equal(Ok(Nil))
}

pub fn utterance_parses_and_validates_with_no_hypotheses_test() {
  let d = dream.svapna([], [], 1, 10)
  d.hypotheses |> should.equal([])
  let text = dream.to_utterance_text(d, "hive-l1")
  let u = acl.parse(text) |> should.be_ok
  acl.validate(u) |> should.equal(Ok(Nil))
}

pub fn to_json_from_json_round_trip_test() {
  let d = dream.svapna(ledger(), slots(), 11, 4)
  let round = dream.from_json(json.to_string(dream.to_json(d)))
  round |> should.equal(Ok(d))
}
