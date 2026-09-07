//// svapna (स्वप्न) — the hive's idle-time consolidation. A dream never asserts a
//// fact: it reads the board timeline and a memory-slot snapshot and emits
//// hypotheses (vikalpa, see `agent_runtime.Vikalpa`), bounded and deterministic.
//// Citation: Yoga Sūtra 1.38, "svapna-nidrā-jñānālambanaṃ vā" — or [the mind is
//// steadied by] resting on the knowledge born of dream and sleep.
////
//// Rule (enforced by `idle`, which every caller MUST check before calling
//// `svapna`): a dream runs only when the line is idle — no live leases and no
//// new board messages have arrived since the caller's last cycle. `svapna`
//// itself never reads a clock, a lease table, or any live process state; it is
//// a pure function of its four arguments, so the idle gate is entirely the
//// caller's responsibility (see `uos_hive_cli`'s `dream` command, which is an
//// operator-invoked tool and deliberately does not call `idle` itself).
////
//// Deterministic and bounded: hypothesis ids and stable tie-break ordering come
//// from a fixed-recurrence LCG seeded by `seed` (never the host clock or a live
//// PRNG — the same recurrence `agent_runtime`'s Thompson sampler uses), and at
//// most `max` hypotheses are ever returned.
////
//// A dream never writes `belief/` or any fact namespace itself; its output is
//// only ever posted (via `to_utterance_text` + `board post-acl`) as a
//// `HYPOTHESIZE` utterance, which `agent_runtime.classify_slot` routes to
//// `Vikalpa` whether it lands under `hypothesis/` or `dream/`.
//// STAMP: SC-TUI-DREAM-001, #rocha-semiotics.

import gleam/dict
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import uos_swarm/agent_runtime
import uos_swarm/board

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub type Hypothesis {
  Hypothesis(
    id: String,
    text: String,
    basis: List(String),
    confidence: Float,
    proposed_action: String,
    aspects: List(Int),
  )
}

pub type Dream {
  Dream(
    seed: Int,
    consolidated: Int,
    hypotheses: List(Hypothesis),
    citation: String,
  )
}

pub const citation = "YS 1.38 svapna-nidrā-jñānālambanaṃ vā ; en: or [the mind is steadied by] resting on knowledge from dream and sleep"

/// The line is idle only when there are no live leases and no board messages
/// have arrived since the caller's last cycle. Pure counters in, pure bool
/// out — `svapna` trusts its caller to have checked this first.
pub fn idle(live_leases: Int, new_messages: Int) -> Bool {
  live_leases <= 0 && new_messages <= 0
}

// ---------------------------------------------------------------------------
// Fixed proposed-action vocabulary — a dream may never invent an action word.
// ---------------------------------------------------------------------------

const act_audit = "audit"

const act_verify = "verify"

const act_retire = "retire"

const act_escalate = "escalate"

const act_document = "document"

const act_no_op = "no-op"

/// Minimum distinct failing subjects before an aspect is worth dreaming about.
const aspect_fail_threshold = 2

/// Minimum Progress posts from one sender, with no Verdict mentioning them,
/// before "propose a verifier" is worth raising.
const progress_threshold = 3

/// Minimum messages from a sender with zero Heartbeat among them before
/// "propose retire-or-beat" is worth raising.
const heartbeat_min_activity = 2

/// Minimum dead-lettered deliveries to one recipient before it is worth
/// raising (every dead-letter is already a terminal failure, so 1 suffices).
const deadletter_threshold = 1

/// Minimum unanswered Question posts from one sender before it is worth
/// raising.
const question_threshold = 2

// ---------------------------------------------------------------------------
// Deterministic LCG (never the host clock): same recurrence as
// `agent_runtime`'s Thompson-sampling uniform draw.
// ---------------------------------------------------------------------------

fn lcg(seed: Int) -> Int {
  int.absolute_value({ seed * 1_103_515_245 + 12_345 } % 2_147_483_647)
}

/// A small deterministic (0, 0.01) jitter used only to give the sort a stable,
/// seed-dependent tie-break; it never changes which hypotheses qualify.
fn jitter(seed: Int, i: Int) -> Float {
  let n = lcg(seed + i * 7919 + 1)
  int.to_float(n % 1000) /. 100_000.0
}

fn clamp01(f: Float) -> Float {
  float.clamp(f, 0.02, 0.98)
}

/// Confidence rises monotonically with the supporting count and is always
/// strictly within (0, 1) — the open interval `acl.validate` requires for a
/// HYPOTHESIZE `@conf`.
fn confidence_from_count(n: Int) -> Float {
  clamp01(1.0 -. 1.0 /. int.to_float(n + 1))
}

// ---------------------------------------------------------------------------
// Signal extraction (a)/(b): pure readers over the message timeline and slots.
// ---------------------------------------------------------------------------

fn senders(messages: List(board.Message)) -> List(String) {
  messages |> list.map(fn(m) { m.from.id }) |> list.unique
}

/// True when `m` names `id` as its sender, its recipient, or a payload key or
/// value — the general-purpose "this message concerns `id`" test used to
/// decide whether a Verdict exists for a given Progress-poster.
fn mentions(m: board.Message, id: String) -> Bool {
  m.from.id == id
  || m.to == id
  || list.any(m.payload, fn(p) { p.0 == id || p.1 == id })
}

/// Aspect numbers whose Verdict messages recorded >= `aspect_fail_threshold`
/// distinct failing payload subjects (a payload pair whose value is "FAIL"),
/// paired with the failing subject keys and the contributing message ids.
fn aspect_failures(
  messages: List(board.Message),
) -> List(#(Int, List(String), List(String))) {
  let verdicts = list.filter(messages, fn(m) { m.kind == board.Verdict })
  let per_aspect =
    list.fold(verdicts, dict.new(), fn(d, m) {
      let fails =
        m.payload
        |> list.filter(fn(p) { p.0 != "agent_id" && p.1 == "FAIL" })
        |> list.map(fn(p) { p.0 })
      case fails {
        [] -> d
        _ ->
          list.fold(m.semantics.aspects, d, fn(d2, a) {
            dict.upsert(d2, a, fn(x) {
              let #(subs, ids) = option.unwrap(x, #([], []))
              #(
                list.append(subs, fails) |> list.unique,
                list.append(ids, [m.id]) |> list.unique,
              )
            })
          })
      }
    })
  per_aspect
  |> dict.to_list
  |> list.filter_map(fn(p) {
    let #(a, #(subs, ids)) = p
    case list.length(subs) >= aspect_fail_threshold {
      True -> Ok(#(a, subs, ids))
      False -> Error(Nil)
    }
  })
  |> list.sort(fn(x, y) { int.compare(x.0, y.0) })
}

/// Senders with >= `progress_threshold` Progress posts and no Verdict message
/// anywhere in the timeline that mentions them.
fn progress_without_verdict(
  messages: List(board.Message),
) -> List(#(String, Int, List(String))) {
  let verdicts = list.filter(messages, fn(m) { m.kind == board.Verdict })
  senders(messages)
  |> list.filter_map(fn(s) {
    let progress_msgs =
      list.filter(messages, fn(m) { m.kind == board.Progress && m.from.id == s })
    let has_verdict = list.any(verdicts, fn(v) { mentions(v, s) })
    case list.length(progress_msgs) >= progress_threshold && !has_verdict {
      True ->
        Ok(#(
          s,
          list.length(progress_msgs),
          list.map(progress_msgs, fn(m) { m.id }),
        ))
      False -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// Senders active (>= `heartbeat_min_activity` posts) but with zero
/// Heartbeat messages anywhere in the timeline.
fn missing_heartbeat(
  messages: List(board.Message),
) -> List(#(String, List(String))) {
  senders(messages)
  |> list.filter_map(fn(s) {
    let from_s = list.filter(messages, fn(m) { m.from.id == s })
    let hb = list.filter(from_s, fn(m) { m.kind == board.Heartbeat })
    case list.length(from_s) >= heartbeat_min_activity && hb == [] {
      True -> Ok(#(s, from_s |> list.map(fn(m) { m.id }) |> list.take(5)))
      False -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// Dead-letter counts per original recipient (`DeadLetter.to`).
fn deadletter_counts(
  messages: List(board.Message),
) -> List(#(String, Int, List(String))) {
  messages
  |> list.filter(fn(m) { m.kind == board.DeadLetter })
  |> list.fold(dict.new(), fn(d, m) {
    dict.upsert(d, m.to, fn(x) {
      let #(n, ids) = option.unwrap(x, #(0, []))
      #(n + 1, [m.id, ..ids])
    })
  })
  |> dict.to_list
  |> list.filter(fn(p) { p.1.0 >= deadletter_threshold })
  |> list.map(fn(p) { #(p.0, p.1.0, p.1.1) })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// Andon posts whose payload names a refusal ("refused" appears, case
/// insensitively, in some payload value), counted per sender.
fn refused_authorizations(
  messages: List(board.Message),
) -> List(#(String, Int, List(String))) {
  messages
  |> list.filter(fn(m) {
    m.kind == board.Andon
    && list.any(m.payload, fn(p) {
      string.contains(string.lowercase(p.1), "refus")
    })
  })
  |> list.fold(dict.new(), fn(d, m) {
    dict.upsert(d, m.from.id, fn(x) {
      let #(n, ids) = option.unwrap(x, #(0, []))
      #(n + 1, [m.id, ..ids])
    })
  })
  |> dict.to_list
  |> list.map(fn(p) { #(p.0, p.1.0, p.1.1) })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// Question posts with no Answer anywhere in the timeline whose
/// `causality.in_reply_to` names them, counted per sender.
fn unanswered_questions(
  messages: List(board.Message),
) -> List(#(String, Int, List(String))) {
  let answered_ids =
    messages
    |> list.filter(fn(m) { m.kind == board.Answer })
    |> list.filter_map(fn(m) { option.to_result(m.causality.in_reply_to, Nil) })
  messages
  |> list.filter(fn(m) {
    m.kind == board.Question && !list.contains(answered_ids, m.id)
  })
  |> list.fold(dict.new(), fn(d, m) {
    dict.upsert(d, m.from.id, fn(x) {
      let #(n, ids) = option.unwrap(x, #(0, []))
      #(n + 1, [m.id, ..ids])
    })
  })
  |> dict.to_list
  |> list.filter(fn(p) { p.1.0 >= question_threshold })
  |> list.map(fn(p) { #(p.0, p.1.0, p.1.1) })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// Memory slots whose vṛtti (per `agent_runtime.classify_slot`) is Viparyaya
/// (a contradicted belief) — an unresolved cognitive error worth dreaming on.
fn contradicted_beliefs(
  slots: List(#(String, String)),
) -> List(#(String, String)) {
  list.filter(slots, fn(kv) {
    agent_runtime.classify_slot(kv.0, kv.1) == agent_runtime.Viparyaya
  })
}

// ---------------------------------------------------------------------------
// Recombination (b)/(c): raw signals -> ranked, bounded hypotheses.
// ---------------------------------------------------------------------------

fn raw_candidates(
  messages: List(board.Message),
  slots: List(#(String, String)),
) -> List(#(String, List(String), Int, String, List(Int))) {
  let aspect_c =
    list.map(aspect_failures(messages), fn(f) {
      let #(aspect, subs, ids) = f
      #(
        "aspect "
          <> int.to_string(aspect)
          <> " failed on "
          <> int.to_string(list.length(subs))
          <> " subjects in the last audit -> propose evaluating the checklist items from evidence",
        ids,
        list.length(subs),
        act_audit,
        [aspect],
      )
    })
  let verifier_c =
    list.map(progress_without_verdict(messages), fn(f) {
      let #(sender, n, ids) = f
      #(
        "sender "
          <> sender
          <> " posted "
          <> int.to_string(n)
          <> " Progress with no Verdict -> propose a verifier",
        ids,
        n,
        act_verify,
        [],
      )
    })
  let heartbeat_c =
    list.map(missing_heartbeat(messages), fn(f) {
      let #(sender, ids) = f
      #(
        "no Heartbeat from "
          <> sender
          <> " for the window -> propose retire-or-beat",
        ids,
        list.length(ids),
        act_retire,
        [],
      )
    })
  let dead_c =
    list.map(deadletter_counts(messages), fn(f) {
      let #(agent, n, ids) = f
      #(
        int.to_string(n)
          <> " dead-lettered message(s) to "
          <> agent
          <> " -> propose escalate",
        ids,
        n,
        act_escalate,
        [],
      )
    })
  let refused_c =
    list.map(refused_authorizations(messages), fn(f) {
      let #(agent, n, ids) = f
      #(
        int.to_string(n)
          <> " refused authorization(s) posted by "
          <> agent
          <> " -> propose document",
        ids,
        n,
        act_document,
        [],
      )
    })
  let question_c =
    list.map(unanswered_questions(messages), fn(f) {
      let #(agent, n, ids) = f
      #(
        agent
          <> " posted "
          <> int.to_string(n)
          <> " unanswered Question(s) -> propose escalate",
        ids,
        n,
        act_escalate,
        [],
      )
    })
  let belief_c =
    list.map(contradicted_beliefs(slots), fn(kv) {
      #(
        "contradicted belief at " <> kv.0 <> " -> propose document",
        [kv.0],
        1,
        act_document,
        [],
      )
    })
  list.flatten([
    aspect_c,
    verifier_c,
    heartbeat_c,
    dead_c,
    refused_c,
    question_c,
    belief_c,
  ])
}

/// Deterministic, bounded consolidation: read `messages` and `slots`, derive
/// at most `max` `Hypothesis` values (never facts), ordered by descending
/// confidence (a per-seed deterministic jitter breaks ties, so the order
/// never depends on list-fold ordering alone). Same `messages`/`slots`/`seed`/
/// `max` always yields the same `Dream` — no clock, no live PRNG.
pub fn svapna(
  messages: List(board.Message),
  slots: List(#(String, String)),
  seed: Int,
  max: Int,
) -> Dream {
  let bound = int.max(max, 0)
  let ranked =
    raw_candidates(messages, slots)
    |> list.index_map(fn(c, idx) {
      let #(text, basis, count, action, aspects) = c
      let conf = confidence_from_count(count)
      let id = "dream-" <> int.to_string(seed) <> "-" <> int.to_string(idx)
      #(
        Hypothesis(id, text, basis, conf, action, aspects),
        conf +. jitter(seed, idx),
      )
    })
    |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
    |> list.take(bound)
    |> list.map(fn(pair) { pair.0 })
  Dream(seed, list.length(messages) + list.length(slots), ranked, citation)
}

// ---------------------------------------------------------------------------
// Rendering: ACL utterance (posted via `board post-acl`) and JSON.
// ---------------------------------------------------------------------------

fn round2_text(f: Float) -> String {
  float.to_string(int.to_float(float.round(f *. 100.0)) /. 100.0)
}

/// Render a dream as a `HYPOTHESIZE` utterance in the existing ACL grammar
/// (see `acl.gleam`): one `B(<from>): hypothesis(id=..., confidence=...)` +
/// `∴ propose(action=..., aspects="...")` clause pair per hypothesis (a
/// `no-op` pair when the dream produced none, so the utterance always
/// validates), aspects joined with `|` — never `,` — inside the quoted value,
/// because `acl.gleam`'s atom-argument splitter is a plain comma split with
/// no quote awareness, so an embedded `,` would be mis-parsed as a second
/// argument. The result parses with `acl.parse` and passes `acl.validate`.
pub fn to_utterance_text(d: Dream, from: String) -> String {
  let overall_conf =
    list.fold(d.hypotheses, 0.0, fn(acc, h) {
      case h.confidence >. acc {
        True -> h.confidence
        False -> acc
      }
    })
  let overall_conf = case overall_conf <=. 0.0 {
    True -> 0.5
    False -> overall_conf
  }
  let header = [
    "@perf HYPOTHESIZE",
    "@from " <> from <> "/L1 @to broadcast",
    "@ooda orient",
    "@conf " <> round2_text(overall_conf),
  ]
  let clause_lines = case d.hypotheses {
    [] -> [
      "B(" <> from <> "): no_signal(dream=" <> int.to_string(d.seed) <> ")",
      "∴ propose(action=" <> act_no_op <> ")",
    ]
    hs ->
      list.flat_map(hs, fn(h) {
        [
          "B("
            <> from
            <> "): hypothesis(id="
            <> h.id
            <> ", confidence="
            <> round2_text(h.confidence)
            <> ")",
          "∴ propose(action="
            <> h.proposed_action
            <> ", aspects=\""
            <> string.join(list.map(h.aspects, int.to_string), "|")
            <> "\")",
        ]
      })
  }
  let all_aspects = case
    list.unique(list.flatten(list.map(d.hypotheses, fn(h) { h.aspects })))
  {
    [] -> [13]
    a -> list.sort(a, int.compare)
  }
  let tags = [
    "#aspects " <> string.join(list.map(all_aspects, int.to_string), ","),
    "#ca CA-emit_intent",
    "#onto Worker|Message / Event",
  ]
  string.join(list.flatten([header, clause_lines, tags]), "\n")
}

fn hypothesis_json(h: Hypothesis) -> Json {
  json.object([
    #("id", json.string(h.id)),
    #("text", json.string(h.text)),
    #("basis", json.array(h.basis, json.string)),
    #("confidence", json.float(h.confidence)),
    #("proposed_action", json.string(h.proposed_action)),
    #("aspects", json.array(h.aspects, json.int)),
  ])
}

pub fn to_json(d: Dream) -> Json {
  json.object([
    #("seed", json.int(d.seed)),
    #("consolidated", json.int(d.consolidated)),
    #("hypotheses", json.array(d.hypotheses, hypothesis_json)),
    #("citation", json.string(d.citation)),
  ])
}

fn hypothesis_decoder() -> decode.Decoder(Hypothesis) {
  use id <- decode.field("id", decode.string)
  use text <- decode.field("text", decode.string)
  use basis <- decode.field("basis", decode.list(decode.string))
  use confidence <- decode.field("confidence", decode.float)
  use proposed_action <- decode.field("proposed_action", decode.string)
  use aspects <- decode.field("aspects", decode.list(decode.int))
  decode.success(Hypothesis(
    id,
    text,
    basis,
    confidence,
    proposed_action,
    aspects,
  ))
}

fn dream_decoder() -> decode.Decoder(Dream) {
  use seed <- decode.field("seed", decode.int)
  use consolidated <- decode.field("consolidated", decode.int)
  use hypotheses <- decode.field(
    "hypotheses",
    decode.list(hypothesis_decoder()),
  )
  use citation <- decode.field("citation", decode.string)
  decode.success(Dream(seed, consolidated, hypotheses, citation))
}

/// Round trip for `to_json` (used by `uos_hive_cli evolve init`, which reads
/// back a dream printed by `uos_hive_cli dream`).
pub fn from_json(text: String) -> Result(Dream, String) {
  json.parse(from: text, using: dream_decoder())
  |> result.map_error(fn(e) { "dream decode: " <> string.inspect(e) })
}
