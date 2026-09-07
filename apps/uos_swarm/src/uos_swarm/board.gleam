//// Shared message board for agent/system coordination (Zenoh a2a plane, ETS live table,
//// append-only JSONL ledger). Every message is a fully tracked envelope: identity, W3C trace
//// context, microsecond UTC time, Lamport clock, sender/receiver, kind, Zenoh key expression,
//// typed payload attributes, semantic references (ontology concepts, aspects, STPA control
//// actions, muda tags, fractal layer), causality, SHA-256 digest chained to the previous message,
//// and an honest delivery record per transport. Nothing is ever marked Delivered without a real
//// Zenoh put that returned 2xx.
//// Key expressions follow cepaf `agui/zenoh_bus`: `c3i/a2a/{source}/{target}` (+ `/{id}` so the
//// Zenoh storage keeps every message, not only the latest per pair).
//// STAMP: SC-TUI-BOARD-001, SC-FPP-INTENT-001, CHK-16-OTEL.

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/stpa
import uos_swarm/system_ontology
import uos_tui/aspects
import uos_tui/layout.{Cells, Fraction, Vertical}
import uos_tui/telemetry
import uos_tui/widget.{type Widget, Column}

pub type Table

@external(erlang, "uos_swarm_ffi", "ets_open")
fn ets_open(name: String) -> Result(Table, String)

@external(erlang, "uos_swarm_ffi", "ets_insert")
fn ets_insert(table: Table, key: String, value: String) -> Nil

@external(erlang, "uos_swarm_ffi", "ets_lookup")
fn ets_lookup(table: Table, key: String) -> Result(String, Nil)

@external(erlang, "uos_swarm_ffi", "ets_all")
fn ets_all(table: Table) -> List(#(String, String))

@external(erlang, "uos_swarm_ffi", "ets_count")
fn ets_count(table: Table) -> Int

@external(erlang, "uos_swarm_ffi", "http_put")
fn http_put(url: String, body: String) -> Result(Int, String)

@external(erlang, "uos_swarm_ffi", "http_get")
pub fn http_get(url: String) -> Result(String, String)

@external(erlang, "uos_swarm_ffi", "file_append")
fn file_append(path: String, line: String) -> Result(Nil, String)

@external(erlang, "uos_swarm_ffi", "file_read")
pub fn file_read(path: String) -> Result(String, String)

@external(erlang, "uos_swarm_ffi", "file_write")
pub fn file_write(path: String, content: String) -> Result(Nil, String)

@external(erlang, "uos_swarm_ffi", "sha256_hex")
pub fn sha256_hex(data: String) -> String

@external(erlang, "uos_swarm_ffi", "hmac_hex")
pub fn hmac_hex(key: String, data: String) -> String

@external(erlang, "uos_swarm_ffi", "board_key")
pub fn board_key() -> Result(String, Nil)

@external(erlang, "uos_swarm_ffi", "system_time_us")
pub fn system_time_us() -> Int

// ---------------------------------------------------------------------------
// Envelope
// ---------------------------------------------------------------------------

pub type Kind {
  Plan
  Dispatch
  Claim
  Progress
  Question
  Answer
  Report
  Verdict
  Andon
  Jidoka
  Integrate
  Heartbeat
  Intent
  LeaseGrant
  LeaseRelease
  Ack
  DeadLetter
}

pub const kinds = [
  Plan,
  Dispatch,
  Claim,
  Progress,
  Question,
  Answer,
  Report,
  Verdict,
  Andon,
  Jidoka,
  Integrate,
  Heartbeat,
  Intent,
  LeaseGrant,
  LeaseRelease,
  Ack,
  DeadLetter,
]

pub fn kind_label(k: Kind) -> String {
  case k {
    Plan -> "Plan"
    Dispatch -> "Dispatch"
    Claim -> "Claim"
    Progress -> "Progress"
    Question -> "Question"
    Answer -> "Answer"
    Report -> "Report"
    Verdict -> "Verdict"
    Andon -> "Andon"
    Jidoka -> "Jidoka"
    Integrate -> "Integrate"
    Heartbeat -> "Heartbeat"
    Intent -> "Intent"
    LeaseGrant -> "LeaseGrant"
    LeaseRelease -> "LeaseRelease"
    Ack -> "Ack"
    DeadLetter -> "DeadLetter"
  }
}

pub fn kind_from_label(s: String) -> Result(Kind, String) {
  kinds
  |> list.find(fn(k) { kind_label(k) == s })
  |> result.replace_error("unknown kind " <> s)
}

pub type Agent {
  Agent(id: String, layer: String, model: String)
}

pub type Semantics {
  Semantics(
    ontology_concepts: List(String),
    aspects: List(Int),
    control_actions: List(String),
    muda: List(String),
    fractal_layer: Int,
  )
}

pub const no_semantics = Semantics([], [], [], [], 0)

pub type Causality {
  Causality(in_reply_to: Option(String), caused_by: List(String))
}

pub type DeliveryStatus {
  Delivered
  Queued
  Unavailable(String)
}

pub type Delivery {
  Delivery(transport: String, status: DeliveryStatus, attempts: Int)
}

/// What a sender supplies; the board seals it into a Message.
pub type Draft {
  Draft(
    from: Agent,
    to: String,
    kind: Kind,
    payload: List(#(String, String)),
    semantics: Semantics,
    causality: Causality,
    trace_id: Option(String),
    parent_span_id: Option(String),
  )
}

pub type Message {
  Message(
    id: String,
    trace_id: String,
    span_id: String,
    parent_span_id: Option(String),
    ts_us: Int,
    ts_iso: String,
    lamport: Int,
    swarm: String,
    from: Agent,
    to: String,
    kind: Kind,
    key_expr: String,
    payload: List(#(String, String)),
    semantics: Semantics,
    causality: Causality,
    prev_digest: String,
    digest: String,
    signature: String,
    deliveries: List(Delivery),
  )
}

pub const unsigned = "unsigned"

/// Derive a per-sender signing key from the shared swarm master key and a domain
/// tag. `hmac_hex` is a one-way keyed function, so knowledge of
/// `agent_key(master, "W03")` alone reveals nothing about
/// `agent_key(master, "L0-fable")`: a principal that is handed only its own
/// derived key (never the master) can sign solely as that sender, and cannot
/// forge another sender's signature. This closes the "one shared key signs
/// everyone" hole: previously `sign(m, key)` computed `hmac_hex(key, m.digest)`
/// directly with the shared key, so any holder of that key could sign as any
/// sender.
pub fn agent_key(master: String, agent_id: String) -> String {
  hmac_hex(master, "uos-board-agent-key/1:" <> agent_id)
}

/// Sign with an already-derived per-agent key. Use this when a principal holds
/// only its own derived key (never the master) — e.g. a worker agent signing its
/// own posts.
pub fn sign_with_agent_key(m: Message, agent_key: String) -> Message {
  Message(..m, signature: hmac_hex(agent_key, m.digest))
}

/// HMAC-SHA256 over the digest with the key derived for `m.from.id`; "unsigned"
/// when no swarm master key is configured.
pub fn sign(m: Message, key: Option(String)) -> Message {
  case key {
    Some(k) -> sign_with_agent_key(m, agent_key(k, m.from.id))
    None -> Message(..m, signature: unsigned)
  }
}

/// A message is authentic when its signature is the HMAC of its digest under the
/// key derived for its claimed sender (`m.from.id`).
pub fn signature_ok(m: Message, key: Option(String)) -> Bool {
  case key {
    Some(k) -> m.signature == hmac_hex(agent_key(k, m.from.id), m.digest)
    None -> False
  }
}

pub const genesis_digest = "0000000000000000000000000000000000000000000000000000000000000000"

/// `c3i/a2a/{source}/{target}/{id}` (cepaf a2a plane, one key per message).
pub fn key_expr(from_id: String, to: String, id: String) -> String {
  "c3i/a2a/" <> from_id <> "/" <> to <> "/" <> id
}

fn pad16(n: Int) -> String {
  string.pad_start(int.to_string(int.max(n, 0)), 16, "0")
}

/// Sortable message id: zero-padded µs timestamp + span id. ETS ordered_set == timeline.
pub fn make_id(ts_us: Int, span_id: String) -> String {
  pad16(ts_us) <> "-" <> span_id
}

/// Netstring-style length-prefixed encoding of one string: `"<byte_len>:<bytes>,"`.
/// Self-delimiting: a reader always knows exactly how many bytes belong to this
/// token without needing a reserved separator, so the raw bytes of `s` — including
/// any `\n`, `;`, `=`, or `,` it happens to contain — can never be misread as a
/// field boundary by whatever comes after it.
fn enc_str(s: String) -> String {
  int.to_string(string.byte_size(s)) <> ":" <> s <> ","
}

/// A discriminated `Option(String)`: `"0,"` for `None`, `"1"` followed by
/// `enc_str(v)` for `Some(v)`. The leading digit is read before any length, so
/// absence can never be confused with a present-but-encoded value.
fn enc_opt(o: Option(String)) -> String {
  case o {
    None -> "0,"
    Some(v) -> "1" <> enc_str(v)
  }
}

/// An `Int`, encoded via its (injective) decimal representation and then
/// length-prefixed like any other scalar.
fn enc_int(n: Int) -> String {
  enc_str(int.to_string(n))
}

/// A list is its element count (itself length-prefixed) followed by each encoded
/// element in order. Because every element is self-delimiting and the count fixes
/// how many elements follow, the extent of the list is fixed before any element is
/// read, so it cannot be confused with what comes after it.
fn enc_list(items: List(a), enc: fn(a) -> String) -> String {
  enc_int(list.length(items)) <> string.concat(list.map(items, enc))
}

/// The payload: pairs sorted by key (`list.sort` is a stable sort) so re-ordering
/// payload fields never changes the digest, then the pair count followed by each
/// key and value, both length-prefixed.
fn enc_payload(pairs: List(#(String, String))) -> String {
  let sorted = list.sort(pairs, fn(a, b) { string.compare(a.0, b.0) })
  enc_int(list.length(sorted))
  <> string.concat(list.map(sorted, fn(p) { enc_str(p.0) <> enc_str(p.1) }))
}

/// Canonical, injective byte encoding of a message, used for both the SHA-256
/// digest and the HMAC signature base. Domain-tagged and versioned
/// (`uos-board-canon/2`) so a future format change can never collide with this
/// one; `deliveries` is deliberately excluded (it evolves through retries and
/// acknowledgements after the message is sealed, and must not perturb identity).
///
/// Every scalar is `enc_str`: a netstring-style `<byte_length>:<bytes>,` token.
/// Every `Option(String)` is a 1-byte discriminator ("0" absent, "1" + value)
/// before any length is read. Every list is its element count followed by each
/// encoded element. The payload is its pair count followed by (key, value) pairs
/// sorted by key.
///
/// This is injective: the whole encoding is a concatenation of self-delimiting,
/// explicitly-counted tokens (a prefix-free code), so there is exactly one way to
/// split any output of this function back into the sequence of tokens that
/// produced it — distinct field tuples can therefore never encode to the same
/// bytes. Contrast the old "\n"/";"/"=" separator scheme it replaces, where a
/// payload value containing the separator itself could be re-split as extra
/// fields and collide with an unrelated message — e.g. payload
/// `[#("a", "b;c=d")]` and `[#("a", "b"), #("c", "d")]` used to yield the same
/// canonical bytes (see `canonical_injective_*_test`).
fn canonical(m: Message) -> String {
  "uos-board-canon/2"
  <> enc_str(m.id)
  <> enc_str(m.trace_id)
  <> enc_str(m.span_id)
  <> enc_opt(m.parent_span_id)
  <> enc_int(m.ts_us)
  <> enc_int(m.lamport)
  <> enc_str(m.swarm)
  <> enc_str(m.from.id)
  <> enc_str(m.from.layer)
  <> enc_str(m.from.model)
  <> enc_str(m.to)
  <> enc_str(kind_label(m.kind))
  <> enc_str(m.key_expr)
  <> enc_payload(m.payload)
  <> enc_list(m.semantics.ontology_concepts, enc_str)
  <> enc_list(m.semantics.aspects, enc_int)
  <> enc_list(m.semantics.control_actions, enc_str)
  <> enc_list(m.semantics.muda, enc_str)
  <> enc_int(m.semantics.fractal_layer)
  <> enc_opt(m.causality.in_reply_to)
  <> enc_list(m.causality.caused_by, enc_str)
  <> enc_str(m.prev_digest)
}

/// Pure sealing: given clock/ids and the previous digest, build the immutable message.
pub fn seal(
  draft: Draft,
  swarm: String,
  ts_us: Int,
  lamport: Int,
  span_id: String,
  prev_digest: String,
) -> Message {
  let id = make_id(ts_us, span_id)
  let trace_id = case draft.trace_id {
    Some(t) -> t
    None -> telemetry.new_trace_id()
  }
  let m =
    Message(
      id: id,
      trace_id: trace_id,
      span_id: span_id,
      parent_span_id: draft.parent_span_id,
      ts_us: ts_us,
      ts_iso: telemetry.iso8601_us(ts_us),
      lamport: lamport,
      swarm: swarm,
      from: draft.from,
      to: draft.to,
      kind: draft.kind,
      key_expr: key_expr(draft.from.id, draft.to, id),
      payload: draft.payload,
      semantics: draft.semantics,
      causality: draft.causality,
      prev_digest: prev_digest,
      digest: "",
      signature: unsigned,
      deliveries: [],
    )
  Message(..m, digest: sha256_hex(canonical(m)))
}

/// Recompute the digest and compare.
pub fn digest_ok(m: Message) -> Bool {
  sha256_hex(canonical(m)) == m.digest
}

// ---------------------------------------------------------------------------
// JSON
// ---------------------------------------------------------------------------

fn semantics_json(s: Semantics) -> Json {
  json.object([
    #("ontology_concepts", json.array(s.ontology_concepts, json.string)),
    #("aspects", json.array(s.aspects, json.int)),
    #("control_actions", json.array(s.control_actions, json.string)),
    #("muda", json.array(s.muda, json.string)),
    #("fractal_layer", json.int(s.fractal_layer)),
  ])
}

fn delivery_json(d: Delivery) -> Json {
  let #(status, reason) = case d.status {
    Delivered -> #("delivered", "")
    Queued -> #("queued", "")
    Unavailable(r) -> #("unavailable", r)
  }
  json.object([
    #("transport", json.string(d.transport)),
    #("status", json.string(status)),
    #("reason", json.string(reason)),
    #("attempts", json.int(d.attempts)),
  ])
}

fn opt_json(o: Option(String)) -> Json {
  case o {
    Some(s) -> json.string(s)
    None -> json.null()
  }
}

pub fn to_json(m: Message) -> Json {
  json.object([
    #("id", json.string(m.id)),
    #("trace_id", json.string(m.trace_id)),
    #("span_id", json.string(m.span_id)),
    #("parent_span_id", opt_json(m.parent_span_id)),
    #("ts_us", json.int(m.ts_us)),
    #("ts_iso", json.string(m.ts_iso)),
    #("lamport", json.int(m.lamport)),
    #("swarm", json.string(m.swarm)),
    #(
      "from",
      json.object([
        #("id", json.string(m.from.id)),
        #("layer", json.string(m.from.layer)),
        #("model", json.string(m.from.model)),
      ]),
    ),
    #("to", json.string(m.to)),
    #("kind", json.string(kind_label(m.kind))),
    #("key_expr", json.string(m.key_expr)),
    #(
      "payload",
      json.object(list.map(m.payload, fn(p) { #(p.0, json.string(p.1)) })),
    ),
    #("semantics", semantics_json(m.semantics)),
    #(
      "causality",
      json.object([
        #("in_reply_to", opt_json(m.causality.in_reply_to)),
        #("caused_by", json.array(m.causality.caused_by, json.string)),
      ]),
    ),
    #("prev_digest", json.string(m.prev_digest)),
    #("digest", json.string(m.digest)),
    #("signature", json.string(m.signature)),
    #("deliveries", json.array(m.deliveries, delivery_json)),
  ])
}

pub fn to_string(m: Message) -> String {
  json.to_string(to_json(m))
}

fn agent_decoder() -> decode.Decoder(Agent) {
  use id <- decode.field("id", decode.string)
  use layer <- decode.field("layer", decode.string)
  use model <- decode.field("model", decode.string)
  decode.success(Agent(id, layer, model))
}

fn semantics_decoder() -> decode.Decoder(Semantics) {
  use concepts <- decode.field("ontology_concepts", decode.list(decode.string))
  use asp <- decode.field("aspects", decode.list(decode.int))
  use cas <- decode.field("control_actions", decode.list(decode.string))
  use muda <- decode.field("muda", decode.list(decode.string))
  use layer <- decode.field("fractal_layer", decode.int)
  decode.success(Semantics(concepts, asp, cas, muda, layer))
}

fn delivery_decoder() -> decode.Decoder(Delivery) {
  use transport <- decode.field("transport", decode.string)
  use status <- decode.field("status", decode.string)
  use reason <- decode.field("reason", decode.string)
  use attempts <- decode.field("attempts", decode.int)
  let st = case status {
    "delivered" -> Delivered
    "queued" -> Queued
    _ -> Unavailable(reason)
  }
  decode.success(Delivery(transport, st, attempts))
}

fn message_decoder() -> decode.Decoder(Message) {
  use id <- decode.field("id", decode.string)
  use trace_id <- decode.field("trace_id", decode.string)
  use span_id <- decode.field("span_id", decode.string)
  use parent <- decode.field("parent_span_id", decode.optional(decode.string))
  use ts_us <- decode.field("ts_us", decode.int)
  use ts_iso <- decode.field("ts_iso", decode.string)
  use lamport <- decode.field("lamport", decode.int)
  use swarm <- decode.field("swarm", decode.string)
  use from <- decode.field("from", agent_decoder())
  use to <- decode.field("to", decode.string)
  use kind_s <- decode.field("kind", decode.string)
  use key <- decode.field("key_expr", decode.string)
  use payload <- decode.field(
    "payload",
    decode.dict(decode.string, decode.string),
  )
  use semantics <- decode.field("semantics", semantics_decoder())
  use reply <- decode.subfield(
    ["causality", "in_reply_to"],
    decode.optional(decode.string),
  )
  use caused <- decode.subfield(
    ["causality", "caused_by"],
    decode.list(decode.string),
  )
  use prev <- decode.field("prev_digest", decode.string)
  use digest <- decode.field("digest", decode.string)
  use signature <- decode.optional_field("signature", unsigned, decode.string)
  use deliveries <- decode.optional_field(
    "deliveries",
    [],
    decode.list(delivery_decoder()),
  )
  let kind = case kind_from_label(kind_s) {
    Ok(k) -> k
    Error(_) -> Progress
  }
  decode.success(Message(
    id,
    trace_id,
    span_id,
    parent,
    ts_us,
    ts_iso,
    lamport,
    swarm,
    from,
    to,
    kind,
    key,
    payload |> dict.to_list |> list.sort(fn(a, b) { string.compare(a.0, b.0) }),
    semantics,
    Causality(reply, caused),
    prev,
    digest,
    signature,
    deliveries,
  ))
}

pub fn decode(text: String) -> Result(Message, String) {
  json.parse(from: text, using: message_decoder())
  |> result.map_error(fn(e) { "message decode: " <> string.inspect(e) })
}

/// Rebuild messages from a JSONL ledger; malformed lines are reported, not dropped
/// silently — the second element of the result is the raw text of every line that
/// failed to decode, verbatim, so a caller can quarantine it for inspection (see
/// `open`, which writes each one to `<ledger_path>.quarantine.jsonl`).
/// The ledger is append-only: a later line with the same id supersedes the earlier one
/// (delivery records evolve through retries and acknowledgements), order is first appearance.
pub fn from_jsonl(text: String) -> #(List(Message), List(String)) {
  let #(order, latest, bad_lines) =
    text
    |> string.split("\n")
    |> list.filter(fn(l) { string.trim(l) != "" })
    |> list.fold(#([], dict.new(), []), fn(acc, line) {
      let #(order, latest, bad_lines) = acc
      case decode(line) {
        Ok(m) ->
          case dict.has_key(latest, m.id) {
            True -> #(order, dict.insert(latest, m.id, m), bad_lines)
            False -> #([m.id, ..order], dict.insert(latest, m.id, m), bad_lines)
          }
        Error(_) -> #(order, latest, [line, ..bad_lines])
      }
    })
  #(
    order |> list.reverse |> list.filter_map(fn(id) { dict.get(latest, id) }),
    list.reverse(bad_lines),
  )
}

// ---------------------------------------------------------------------------
// Board (ETS live table + JSONL ledger + Zenoh REST)
// ---------------------------------------------------------------------------

pub type Board {
  Board(
    swarm: String,
    table: Table,
    ledger_path: Option(String),
    zenoh_base: Option(String),
    last_digest: String,
    heads: dict.Dict(String, String),
    lamport: Int,
    count: Int,
    key: Option(String),
    quarantined: Int,
  )
}

/// Count of ledger lines that failed to parse on the most recent `open` (0 when
/// there was no ledger, or every line parsed).
pub fn quarantined(board: Board) -> Int {
  board.quarantined
}

/// Chain head (last digest) for a sender; genesis when the sender has not posted yet.
pub fn head_of(board: Board, sender: String) -> String {
  dict.get(board.heads, sender) |> result.unwrap(genesis_digest)
}

fn heads_from(messages: List(Message)) -> dict.Dict(String, String) {
  list.fold(messages, dict.new(), fn(d, m) {
    dict.insert(d, m.from.id, m.digest)
  })
}

/// Open (or reopen) the named ETS table; rebuild chain state from the ledger if
/// present. Every ledger line that fails to parse is quarantined, not dropped: it
/// is appended verbatim to `<ledger_path>.quarantine.jsonl` for an operator to
/// inspect and repair, and counted in `Board.quarantined` (`quarantined/1`) so a
/// corrupt ledger never silently loses evidence on restore.
pub fn open(
  swarm: String,
  table_name: String,
  ledger_path: Option(String),
  zenoh_base: Option(String),
) -> Result(Board, String) {
  use table <- result.try(ets_open(table_name))
  let #(restored, bad_lines) = case ledger_path {
    Some(p) ->
      case file_read(p) {
        Ok(text) -> from_jsonl(text)
        Error(_) -> #([], [])
      }
    None -> #([], [])
  }
  let quarantine_path =
    option.map(ledger_path, fn(p) { p <> ".quarantine.jsonl" })
  case quarantine_path {
    Some(qp) -> list.each(bad_lines, fn(line) { file_append(qp, line <> "\n") })
    None -> Nil
  }
  list.each(restored, fn(m) { ets_insert(table, m.id, to_string(m)) })
  let last =
    restored
    |> list.last
    |> result.map(fn(m) { m.digest })
    |> result.unwrap(genesis_digest)
  let lamport = restored |> list.fold(0, fn(acc, m) { int.max(acc, m.lamport) })
  Ok(Board(
    swarm,
    table,
    ledger_path,
    zenoh_base,
    last,
    heads_from(restored),
    lamport,
    ets_count(table),
    option.from_result(board_key()),
    list.length(bad_lines),
  ))
}

/// Post a draft: seal + sign, then run the message through the transactional
/// outbox (`deliver`) — durable ledger acceptance happens before any Zenoh
/// publish is attempted, so a message is never announced on the wire before it
/// is safely recorded on disk.
pub fn post(board: Board, draft: Draft) -> #(Board, Message) {
  let ts = system_time_us()
  let lamport = board.lamport + 1
  let m =
    seal(
      draft,
      board.swarm,
      ts,
      lamport,
      telemetry.new_span_id(),
      head_of(board, draft.from.id),
    )
  let m = sign(m, board.key)
  let m = deliver(board, m)
  #(
    Board(
      ..board,
      last_digest: m.digest,
      heads: dict.insert(board.heads, draft.from.id, m.digest),
      lamport: lamport,
      count: board.count + 1,
    ),
    m,
  )
}

/// Merge a message that originated elsewhere (Lamport merge). The remote sender's chain head
/// advances only when the message extends our current head for that sender.
pub fn absorb(board: Board, m: Message) -> Board {
  let authentic = case board.key {
    Some(_) -> signature_ok(m, board.key)
    None -> True
  }
  case ets_lookup(board.table, m.id), authentic {
    Ok(_), _ -> board
    Error(_), False -> board
    Error(_), True -> {
      ets_insert(board.table, m.id, to_string(m))
      let _ = case board.ledger_path {
        Some(p) -> file_append(p, to_string(m) <> "\n")
        None -> Ok(Nil)
      }
      let heads = case head_of(board, m.from.id) == m.prev_digest {
        True -> dict.insert(board.heads, m.from.id, m.digest)
        False -> board.heads
      }
      Board(
        ..board,
        heads: heads,
        lamport: int.max(board.lamport, m.lamport),
        count: board.count + 1,
      )
    }
  }
}

/// Transactional outbox (fixes "publication precedes durable acceptance"): the
/// ledger line is appended, and the message inserted into ETS, *before* any
/// Zenoh publish is attempted; a Zenoh put only happens once the ledger append
/// has actually succeeded (or there is no ledger configured at all, i.e.
/// nothing to wait on). If the ledger append fails, the message still ends up
/// in ETS — so the process never silently loses it — but is recorded
/// `Unavailable` and is never published; `retry_undelivered` is the path back
/// to durability (it re-attempts a failed ledger append the same way it
/// re-attempts a failed Zenoh put).
fn deliver(board: Board, m: Message) -> Message {
  // (a)/(b): durable acceptance first. Stage the record a reader will see if the
  // ledger accepts the line: ledger delivered, Zenoh still queued.
  let #(ledger_delivery, ledger_ok) = case board.ledger_path {
    None -> #(Delivery("ledger", Queued, 0), True)
    Some(p) -> {
      let staged =
        Message(..m, deliveries: [
          Delivery("ledger", Delivered, 1),
          Delivery("zenoh", Queued, 0),
        ])
      case file_append(p, to_string(staged) <> "\n") {
        Ok(_) -> #(Delivery("ledger", Delivered, 1), True)
        Error(e) -> #(Delivery("ledger", Unavailable(e), 1), False)
      }
    }
  }
  let staged_record =
    Message(..m, deliveries: [ledger_delivery, Delivery("zenoh", Queued, 0)])
  // The process must retain visibility of a posted message whether or not the
  // ledger accepted it: ETS is the live table, not itself a durability
  // guarantee.
  ets_insert(board.table, staged_record.id, to_string(staged_record))
  case ledger_ok {
    False -> staged_record
    True -> {
      // (c): only now attempt the Zenoh publish.
      let zenoh = case board.zenoh_base {
        Some(base) ->
          case http_put(base <> "/" <> m.key_expr, to_string(staged_record)) {
            Ok(code) if code >= 200 && code < 300 ->
              Delivery("zenoh", Delivered, 1)
            Ok(code) ->
              Delivery("zenoh", Unavailable("http " <> int.to_string(code)), 1)
            Error(e) -> Delivery("zenoh", Unavailable(e), 1)
          }
        None -> Delivery("zenoh", Queued, 0)
      }
      let final = Message(..m, deliveries: [ledger_delivery, zenoh])
      // (d): a second ledger line with the final delivery records — the ledger
      // already uses latest-line-per-id semantics, so this supersedes the
      // staged line above.
      let _ = case board.ledger_path {
        Some(p) -> file_append(p, to_string(final) <> "\n")
        None -> Ok(Nil)
      }
      ets_insert(board.table, final.id, to_string(final))
      final
    }
  }
}

/// Timeline in id order (ETS ordered_set).
pub fn timeline(board: Board) -> List(Message) {
  ets_all(board.table)
  |> list.filter_map(fn(kv) { decode(kv.1) })
}

pub fn by_agent(messages: List(Message), agent_id: String) -> List(Message) {
  list.filter(messages, fn(m) { m.from.id == agent_id || m.to == agent_id })
}

pub fn by_kind(messages: List(Message), kind: Kind) -> List(Message) {
  list.filter(messages, fn(m) { m.kind == kind })
}

pub fn replies_to(messages: List(Message), id: String) -> List(Message) {
  list.filter(messages, fn(m) { m.causality.in_reply_to == Some(id) })
}

/// Put a raw JSON document on any key (used for shared state and re-publishing during sync).
pub fn zenoh_put(
  base: String,
  key: String,
  body: String,
) -> Result(Nil, String) {
  case http_put(base <> "/" <> key, body) {
    Ok(code) if code >= 200 && code < 300 -> Ok(Nil)
    Ok(code) -> Error("http " <> int.to_string(code))
    Error(e) -> Error(e)
  }
}

/// Fetch everything on the a2a plane from a Zenoh storage over REST. Samples that are not
/// full envelopes (foreign publishers on the same plane) are skipped, never fatal.
pub fn zenoh_fetch(base: String) -> Result(List(Message), String) {
  use body <- result.try(http_get(base <> "/c3i/a2a/**"))
  let envelope = {
    use value <- decode.field("value", message_decoder())
    decode.success(Some(value))
  }
  let sample = decode.one_of(envelope, [decode.success(None)])
  json.parse(from: body, using: decode.list(sample))
  |> result.map(fn(xs) {
    xs
    |> list.filter_map(fn(x) { option.to_result(x, Nil) })
    // A sample read back from the Zenoh storage is, by construction, delivered to Zenoh:
    // the wire copy was written before the put result was known, so settle it here.
    |> list.map(fn(m) {
      Message(
        ..m,
        deliveries: list.map(m.deliveries, fn(d) {
          case string.starts_with(d.transport, "zenoh"), d.status {
            True, Queued ->
              Delivery("zenoh-rest:" <> base, Delivered, int.max(d.attempts, 1))
            _, _ -> d
          }
        }),
      )
    })
  })
  |> result.map_error(fn(e) { "zenoh samples decode: " <> string.inspect(e) })
}

// ---------------------------------------------------------------------------
// Inbox, acknowledgement, retry, dead-letter, replay (at-least-once discipline)
// ---------------------------------------------------------------------------

/// Messages addressed to `agent` (directly or broadcast) that `agent` has not acknowledged.
pub fn inbox(messages: List(Message), agent: String) -> List(Message) {
  let acked =
    messages
    |> list.filter(fn(m) { m.kind == Ack && m.from.id == agent })
    |> list.filter_map(fn(m) { option.to_result(m.causality.in_reply_to, Nil) })
  messages
  |> list.filter(fn(m) {
    m.kind != Ack
    && { m.to == agent || m.to == "broadcast" }
    && m.from.id != agent
  })
  |> list.filter(fn(m) { !list.contains(acked, m.id) })
}

/// True when `agent` has acknowledged message `id`.
pub fn acked_by(messages: List(Message), id: String, agent: String) -> Bool {
  list.any(messages, fn(m) {
    m.kind == Ack && m.from.id == agent && m.causality.in_reply_to == Some(id)
  })
}

/// Post an acknowledgement for `id` from `agent` (tracked like any message).
/// The acknowledgement draft for message `id` (broadcast, in reply to `id`), so callers
/// that must pass the authorization boundary can authorize it before posting.
pub fn ack_draft(agent: Agent, id: String) -> Draft {
  Draft(
    agent,
    "broadcast",
    Ack,
    [#("ack", id)],
    Semantics(
      ["Message / Event"],
      [10, 13],
      ["CA-emit_intent"],
      [],
      layer_num(agent.layer),
    ),
    Causality(Some(id), [id]),
    None,
    None,
  )
}

pub fn ack(board: Board, agent: Agent, id: String) -> #(Board, Message) {
  post(board, ack_draft(agent, id))
}

fn layer_num(layer: String) -> Int {
  layer |> string.drop_start(1) |> int.parse |> result.unwrap(3)
}

/// Delivery state of a message across the transactional outbox's two
/// transports (ledger, Zenoh).
pub type DeliveryState {
  Created
  Outboxed
  Published
  Acknowledged
  Dead
}

fn dead_at_max(d: Result(Delivery, Nil)) -> Bool {
  case d {
    Ok(Delivery(_, Unavailable(_), attempts)) -> attempts >= max_attempts
    _ -> False
  }
}

/// A message is never `Published` unless its ledger line is `Delivered` — Zenoh
/// visibility alone is not enough, since the whole point of the transactional
/// outbox is that durable ledger acceptance gates publication. `Dead` fires
/// when either transport is `Unavailable` after `max_attempts`.
pub fn delivery_state(messages: List(Message), m: Message) -> DeliveryState {
  let ledger =
    m.deliveries
    |> list.find(fn(d) { string.starts_with(d.transport, "ledger") })
  let zenoh =
    m.deliveries
    |> list.find(fn(d) { string.starts_with(d.transport, "zenoh") })
  case dead_at_max(ledger) || dead_at_max(zenoh) {
    True -> Dead
    False ->
      case ledger {
        Ok(Delivery(_, Delivered, _)) ->
          case zenoh {
            Ok(Delivery(_, Delivered, _)) ->
              case m.to != "broadcast" && acked_by(messages, m.id, m.to) {
                True -> Acknowledged
                False -> Published
              }
            _ -> Outboxed
          }
        _ -> Created
      }
  }
}

pub const max_attempts = 5

pub fn state_label(s: DeliveryState) -> String {
  case s {
    Created -> "created"
    Outboxed -> "outboxed"
    Published -> "published"
    Acknowledged -> "acknowledged"
    Dead -> "dead-letter"
  }
}

fn find_delivery(m: Message, prefix: String) -> Delivery {
  m.deliveries
  |> list.find(fn(d) { string.starts_with(d.transport, prefix) })
  |> result.unwrap(Delivery(prefix, Queued, 0))
}

/// Retry the ledger append for `m` when its ledger delivery is `Unavailable`
/// and has not yet exhausted `max_attempts`; `None` when there is nothing to
/// retry.
fn retry_ledger(board: Board, m: Message) -> Option(Delivery) {
  case find_delivery(m, "ledger"), board.ledger_path {
    Delivery(t, Unavailable(_), attempts), Some(p) if attempts < max_attempts -> {
      let status = case file_append(p, to_string(m) <> "\n") {
        Ok(_) -> Delivered
        Error(e) -> Unavailable(e)
      }
      Some(Delivery(t, status, attempts + 1))
    }
    _, _ -> None
  }
}

/// Retry the Zenoh put for `m` when its Zenoh delivery is `Unavailable` and has
/// not yet exhausted `max_attempts`; `None` when there is nothing to retry.
fn retry_zenoh(board: Board, m: Message) -> Option(Delivery) {
  case find_delivery(m, "zenoh"), board.zenoh_base {
    Delivery(t, Unavailable(_), attempts), Some(base)
      if attempts < max_attempts
    -> {
      let status = case http_put(base <> "/" <> m.key_expr, to_string(m)) {
        Ok(code) if code >= 200 && code < 300 -> Delivered
        Ok(code) -> Unavailable("http " <> int.to_string(code))
        Error(e) -> Unavailable(e)
      }
      Some(Delivery(t, status, attempts + 1))
    }
    _, _ -> None
  }
}

fn just_went_dead(retry: Option(Delivery)) -> Bool {
  case retry {
    Some(Delivery(_, Unavailable(_), attempts)) -> attempts >= max_attempts
    _ -> False
  }
}

/// Retry ledger and Zenoh delivery independently for every message whose
/// respective transport is still `Unavailable` (each capped at
/// `max_attempts`). Every retried message gets its combined, updated delivery
/// record persisted (`record`: ETS overwrite + ledger append), so a ledger
/// retry that succeeds is itself durably recorded, not just held in memory. A
/// message whose ledger or Zenoh transport exhausts its attempts while still
/// `Unavailable` gets a `DeadLetter` notice posted by the system, once, at the
/// retry that crosses the threshold, so nothing fails silently.
pub fn retry_undelivered(board: Board) -> #(Board, Int, Int) {
  timeline(board)
  |> list.fold(#(board, 0, 0), fn(acc, m) {
    let #(b, retried, dead) = acc
    let ledger_retry = retry_ledger(b, m)
    let zenoh_retry = retry_zenoh(b, m)
    case ledger_retry, zenoh_retry {
      None, None -> acc
      _, _ -> {
        let updated =
          Message(..m, deliveries: [
            option.unwrap(ledger_retry, find_delivery(m, "ledger")),
            option.unwrap(zenoh_retry, find_delivery(m, "zenoh")),
          ])
        let b = record(b, updated)
        case just_went_dead(ledger_retry) || just_went_dead(zenoh_retry) {
          False -> #(b, retried + 1, dead)
          True -> {
            let #(b, _) =
              post(
                b,
                Draft(
                  Agent("uos-coord", "L1", "system"),
                  m.from.id,
                  DeadLetter,
                  [#("dead", m.id), #("attempts", int.to_string(max_attempts))],
                  Semantics(
                    ["Message / Event"],
                    [10],
                    ["CA-emit_intent"],
                    ["Defects"],
                    1,
                  ),
                  Causality(Some(m.id), []),
                  None,
                  None,
                ),
              )
            #(b, retried + 1, dead + 1)
          }
        }
      }
    }
  })
}

/// Persist an updated record for an existing message (ETS overwrite + ledger append).
pub fn record(board: Board, m: Message) -> Board {
  ets_insert(board.table, m.id, to_string(m))
  let _ = case board.ledger_path {
    Some(p) -> file_append(p, to_string(m) <> "\n")
    None -> Ok(Nil)
  }
  board
}

/// Replay every ledger message onto Zenoh (idempotent: one key per message id).
pub fn replay(board: Board) -> Result(#(Int, Int), String) {
  use base <- result.try(option.to_result(
    board.zenoh_base,
    "no zenoh base configured",
  ))
  let ms = timeline(board)
  let ok =
    list.count(ms, fn(m) {
      zenoh_put(base, m.key_expr, to_string(m)) == Ok(Nil)
    })
  Ok(#(ok, list.length(ms) - ok))
}

// ---------------------------------------------------------------------------
// Validation (fail-closed semantic tracking)
// ---------------------------------------------------------------------------

pub const muda_labels = [
  "Overproduction", "Waiting", "Transport", "Overprocessing", "Inventory",
  "Motion", "Defects",
]

pub fn validate_semantics(s: Semantics) -> Result(Nil, String) {
  let cas = list.map(stpa.model().control_actions, fn(c) { c.id })
  let bad_concept =
    list.find(s.ontology_concepts, fn(c) {
      case system_ontology.resolve(c) {
        Ok(_) -> False
        Error(_) -> True
      }
    })
  let bad_aspect = list.find(s.aspects, fn(a) { a < 1 || a > 17 })
  let bad_ca = list.find(s.control_actions, fn(c) { !list.contains(cas, c) })
  let bad_muda = list.find(s.muda, fn(m) { !list.contains(muda_labels, m) })
  case
    bad_concept,
    bad_aspect,
    bad_ca,
    bad_muda,
    s.fractal_layer >= 0 && s.fractal_layer <= 9
  {
    Ok(c), _, _, _, _ -> Error("unknown ontology concept: " <> c)
    _, Ok(a), _, _, _ -> Error("aspect out of range: " <> int.to_string(a))
    _, _, Ok(c), _, _ -> Error("unknown control action: " <> c)
    _, _, _, Ok(m), _ -> Error("unknown muda: " <> m)
    _, _, _, _, False -> Error("fractal layer out of range")
    _, _, _, _, True -> Ok(Nil)
  }
}

/// Validate a timeline: unique ids, intact per-sender digest chains (multi-writer safe),
/// resolvable replies, valid semantics, and valid W3C ids.
pub fn validate(messages: List(Message)) -> Result(Nil, String) {
  let ids = list.map(messages, fn(m) { m.id })
  use _ <- result.try(case list.length(list.unique(ids)) == list.length(ids) {
    True -> Ok(Nil)
    False -> Error("duplicate message id")
  })
  use _ <- result.try(
    list.try_each(messages, fn(m) {
      case digest_ok(m) {
        True -> Ok(Nil)
        False -> Error("digest mismatch on " <> m.id)
      }
    }),
  )
  // A reply may point at a message that is provably lost (for example wiped from a
  // shared store before it was absorbed). Such an id is never recreated or forged;
  // instead an explicit causal-gap record (payload key `causal_gap`) documents it,
  // and replies to a recorded gap validate.
  let gaps = causal_gaps(messages)
  use _ <- result.try(
    list.try_each(messages, fn(m) {
      case m.causality.in_reply_to {
        Some(target) ->
          case list.contains(ids, target) || list.contains(gaps, target) {
            True -> Ok(Nil)
            False -> Error("reply to unknown message " <> target)
          }
        None -> Ok(Nil)
      }
    }),
  )
  use _ <- result.try(
    list.try_each(messages, fn(m) { validate_semantics(m.semantics) }),
  )
  use _ <- result.try(
    list.try_each(messages, fn(m) {
      case
        telemetry.is_hex_id(m.trace_id, 32)
        && telemetry.is_hex_id(m.span_id, 16)
      {
        True -> Ok(Nil)
        False -> Error("invalid trace/span id on " <> m.id)
      }
    }),
  )
  use _ <- result.try(case option.from_result(board_key()) {
    Some(k) ->
      list.try_each(messages, fn(m) {
        case signature_ok(m, Some(k)) {
          True -> Ok(Nil)
          False -> Error("bad or missing signature on " <> m.id)
        }
      })
    None -> Ok(Nil)
  })
  // One hash chain per sender (per-author log), ordered by id (timestamp) within the sender.
  messages
  |> list.group(fn(m) { m.from.id })
  |> dict.values
  |> list.try_each(fn(ms) { chain_ok(list.reverse(ms), genesis_digest) })
}

/// Ids documented as lost by explicit causal-gap records (payload key `causal_gap`).
/// Recording a gap never recreates the message; it only makes the gap visible and
/// lets replies that reference it validate.
pub fn causal_gaps(messages: List(Message)) -> List(String) {
  messages
  |> list.flat_map(fn(m) {
    list.filter_map(m.payload, fn(p) {
      case p.0 == "causal_gap" {
        True -> Ok(p.1)
        False -> Error(Nil)
      }
    })
  })
  |> list.unique
}

/// Distributed note: `list.group` returns each group newest-first, hence the reverse.
fn chain_ok(messages: List(Message), prev: String) -> Result(Nil, String) {
  case messages {
    [] -> Ok(Nil)
    [m, ..rest] ->
      case m.prev_digest == prev {
        True -> chain_ok(rest, m.digest)
        False -> Error("chain broken at " <> m.id)
      }
  }
}

// ---------------------------------------------------------------------------
// Workflow journal ingestion (retroactive tracking of a swarm run)
// ---------------------------------------------------------------------------

pub type JournalEntry {
  Started(agent_id: String)
  WorkerResult(
    agent_id: String,
    slice: String,
    tests_added: Int,
    warnings: Int,
    test_line: String,
    loc: Int,
  )
  VerifierResult(agent_id: String, verdicts: List(#(String, String)))
}

fn entry_decoder() -> decode.Decoder(JournalEntry) {
  use typ <- decode.field("type", decode.string)
  use agent <- decode.field("agentId", decode.string)
  case typ {
    "result" -> {
      let worker = {
        use slice <- decode.subfield(["result", "slice"], decode.string)
        use tests <- decode.subfield(["result", "tests_added"], decode.int)
        use warnings <- decode.subfield(["result", "warnings"], decode.int)
        use line <- decode.subfield(
          ["result", "gleam_test_line"],
          decode.string,
        )
        use loc <- decode.subfield(["result", "loc"], decode.int)
        decode.success(WorkerResult(agent, slice, tests, warnings, line, loc))
      }
      let verifier = {
        let slice = {
          use id <- decode.field("id", decode.string)
          use verdict <- decode.field("verdict", decode.string)
          decode.success(#(id, verdict))
        }
        use slices <- decode.subfield(["result", "slices"], decode.list(slice))
        decode.success(VerifierResult(agent, slices))
      }
      decode.one_of(worker, [verifier])
    }
    _ -> decode.success(Started(agent))
  }
}

pub fn parse_journal(text: String) -> List(JournalEntry) {
  text
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case string.trim(line) {
      "" -> Error(Nil)
      l ->
        json.parse(from: l, using: entry_decoder()) |> result.replace_error(Nil)
    }
  })
}

/// Two-pass label resolution: results reveal which agent id did which slice; `labels`
/// maps a slice prefix (lowercase, 12 chars) or a verifier's first verdict id to a swarm label.
pub fn resolve_labels(
  entries: List(JournalEntry),
  labels: List(#(String, String)),
) -> List(#(String, String)) {
  list.filter_map(entries, fn(e) {
    case e {
      WorkerResult(agent, slice, ..) -> {
        let words = fn(t: String) {
          t
          |> string.lowercase
          |> string.replace("(", " ")
          |> string.replace(")", " ")
          |> string.replace("/", " ")
          |> string.replace("-", " ")
          |> string.split(" ")
          |> list.filter(fn(w) { string.length(w) >= 4 })
        }
        let sw = words(slice)
        labels
        |> list.filter(fn(l) { !string.starts_with(l.0, "verify:") })
        |> list.map(fn(l) {
          #(l, list.count(words(l.0), fn(w) { list.contains(sw, w) }))
        })
        |> list.sort(fn(a, b) { int.compare(b.1, a.1) })
        |> list.first
        |> result.try(fn(best) {
          case best.1 >= 1 {
            True -> Ok(#(agent, best.0.1))
            False -> Error(Nil)
          }
        })
      }
      VerifierResult(agent, verdicts) ->
        case verdicts {
          [#(first, _), ..] ->
            labels
            |> list.find(fn(l) { l.0 == "verify:" <> first })
            |> result.map(fn(l) { #(agent, l.1) })
            |> result.replace_error(Nil)
          [] -> Error(Nil)
        }
      Started(_) -> Error(Nil)
    }
  })
}

fn label_of(agent: String, resolved: List(#(String, String))) -> String {
  resolved
  |> list.find(fn(r) { r.0 == agent })
  |> result.map(fn(r) { r.1 })
  |> result.unwrap(agent)
}

/// Turn journal entries into drafts from/to the supervisor with full semantics.
pub fn drafts_from_journal(
  entries: List(JournalEntry),
  supervisor: Agent,
) -> List(Draft) {
  drafts_from_journal_labelled(entries, supervisor, [])
}

pub fn drafts_from_journal_labelled(
  entries: List(JournalEntry),
  supervisor: Agent,
  labels: List(#(String, String)),
) -> List(Draft) {
  let resolved = resolve_labels(entries, labels)
  list.map(entries, fn(e) {
    case e {
      Started(agent) ->
        Draft(
          supervisor,
          label_of(agent, resolved),
          Dispatch,
          [#("event", "agent started"), #("agent_id", agent)],
          Semantics(
            ["Worker"],
            [4, 13],
            ["CA-write_owned_file"],
            ["Waiting"],
            2,
          ),
          Causality(None, []),
          None,
          None,
        )
      WorkerResult(agent, slice, tests, warnings, line, loc) ->
        Draft(
          Agent(label_of(agent, resolved), "L2", "sonnet"),
          supervisor.id,
          Report,
          [
            #("agent_id", agent),
            #("slice", slice),
            #("tests_added", int.to_string(tests)),
            #("warnings", int.to_string(warnings)),
            #("gleam_test_line", line),
            #("loc", int.to_string(loc)),
          ],
          Semantics(
            ["Worker", "Pilot / run_test"],
            [3, 10, 13],
            ["CA-write_owned_file"],
            [],
            2,
          ),
          Causality(None, []),
          None,
          None,
        )
      VerifierResult(agent, verdicts) ->
        Draft(
          Agent(label_of(agent, resolved), "L3", "haiku"),
          supervisor.id,
          Verdict,
          [#("agent_id", agent), ..list.map(verdicts, fn(v) { #(v.0, v.1) })],
          Semantics(
            ["17 Aspect audit"],
            [3, 13, 15],
            ["CA-verify_slice"],
            ["Defects"],
            3,
          ),
          Causality(None, []),
          None,
          None,
        )
    }
  })
}

// ---------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------

pub fn to_markdown(messages: List(Message)) -> String {
  let header =
    "| ts (UTC) | lamport | from | kind | to | delivery | digest |\n|---|---|---|---|---|---|---|"
  let rows =
    list.map(messages, fn(m) {
      let delivered =
        m.deliveries
        |> list.filter(fn(d) { d.status == Delivered })
        |> list.map(fn(d) { d.transport })
        |> string.join(" ")
      "| "
      <> m.ts_iso
      <> " | "
      <> int.to_string(m.lamport)
      <> " | "
      <> m.from.id
      <> " | "
      <> kind_label(m.kind)
      <> " | "
      <> m.to
      <> " | "
      <> delivered
      <> " | "
      <> string.slice(m.digest, 0, 12)
      <> " |"
    })
  string.join([header, ..rows], "\n")
}

pub fn view(messages: List(Message), cursor: Int) -> Widget(msg) {
  let rows =
    list.map(messages, fn(m) {
      let z =
        m.deliveries
        |> list.any(fn(d) {
          string.starts_with(d.transport, "zenoh") && d.status == Delivered
        })
      [
        string.slice(m.ts_iso, 11, 15),
        m.from.id,
        kind_label(m.kind),
        m.to,
        case z {
          True -> "zenoh+ets+jsonl"
          False -> "ets+jsonl"
        },
      ]
    })
  widget.Container(
    "board",
    Vertical,
    [
      #(
        Cells(1),
        widget.Static(
          "board-title",
          "Message board · "
            <> aspects.tailnet_fqdn
            <> " · "
            <> int.to_string(list.length(messages))
            <> " tracked",
          widget.no_style(),
        ),
      ),
      #(
        Fraction(1),
        widget.DataTable(
          "board-messages",
          [
            Column("ts", Cells(16)),
            Column("from", Cells(18)),
            Column("kind", Cells(12)),
            Column("to", Cells(18)),
            Column("delivery", Fraction(1)),
          ],
          rows,
          cursor,
          None,
          None,
        ),
      ),
    ],
    True,
    "Board",
  )
}
