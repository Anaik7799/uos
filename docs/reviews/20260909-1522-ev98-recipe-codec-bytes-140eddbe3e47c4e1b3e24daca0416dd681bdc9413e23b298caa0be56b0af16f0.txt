import cepaf_gleam/crdt/delta_state.{
  Dot, LWWRegister, MeshDeltaState, ORSet, PNCounter, new_mesh_delta_state,
  orset_add,
}
import cepaf_gleam/crdt/health_bridge.{NodeHealthTelemetry}
import cepaf_gleam/crdt/mesh_sync.{
  SyncAck, SyncDelta, SyncDigest, decode_sync_message, encode_sync_message,
  reconcile_remote_delta, reconcile_remote_wire, sync_message_to_json,
}
import cepaf_gleam/crdt/mesh_wire.{
  Array, ByteLimit, CollectionLimit, DepthLimit, DuplicateDot, DuplicateKey,
  IntegerLimit, InvalidIdentity, NodeMismatch, StringLimit, Text,
}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

pub fn diagnostic_delta_retains_payload_test() {
  let initial = new_mesh_delta_state("nas-1", 123)
  let state =
    MeshDeltaState(
      ..initial,
      active_workers: orset_add(
        initial.active_workers,
        "worker-payload-witness",
        Dot("nas-1", 2),
      ),
    )
  sync_message_to_json(SyncDelta("nas-1", state, [], 124))
  |> string.contains("worker-payload-witness")
  |> should.be_true
}

fn nonempty_state() {
  MeshDeltaState(
    "origin",
    91,
    [#("z", 3), #("a", 2)],
    ORSet([#("worker-α", Dot("z", 3)), #("worker-α", Dot("a", 2))], [
      Dot("retired", 9),
    ]),
    PNCounter([#("z", 7)], [#("a", 4)]),
    LWWRegister("leader-β", 98, "lease-writer"),
  )
}

fn nonempty_health() {
  [
    #(
      "node-health",
      LWWRegister(
        NodeHealthTelemetry("node-health", 0.95, -1.25, True, "closed", 80),
        82,
        "observer",
      ),
    ),
    #(
      "node-other",
      LWWRegister(
        NodeHealthTelemetry("node-other", 0.0, 1.0, False, "open", 79),
        900,
        "older-sample-larger-logical",
      ),
    ),
  ]
}

fn roundtrip(message) {
  let assert Ok(bytes) = encode_sync_message(message)
  decode_sync_message(bytes) |> should.equal(Ok(message))
}

pub fn all_fields_and_forwarding_origin_roundtrip_test() {
  roundtrip(SyncDelta("forwarder", nonempty_state(), nonempty_health(), 100))
}

pub fn digest_and_ack_roundtrip_test() {
  roundtrip(SyncDigest("node", [#("b", 2), #("a", 0)], 13, 27))
  roundtrip(SyncAck(
    "node",
    [#("b", 2), #("a", 0)],
    "escaped \" [] {} \\ \n α",
    27,
  ))
}

pub fn empty_delta_and_zero_boundaries_roundtrip_test() {
  roundtrip(SyncDelta("node", new_mesh_delta_state("node", 0), [], 0))
  roundtrip(SyncDigest("node", [], 0, 0))
}

pub fn independent_exact_wire_layout_test() {
  decode_sync_message(
    "[1,\"sync_delta\",\"forwarder\",[\"origin\",10,[[\"n\",2]],[[[\"w\",[\"n\",2]]],[[\"retired\",1]]],[[[\"n\",7]],[[\"n\",3]]],[\"leader\",12,\"writer\"]],[[\"n\",[[\"n\",0.75,-0.25,true,\"closed\",8],11,\"observer\"]]],20]",
  )
  |> should.equal(
    Ok(SyncDelta(
      "forwarder",
      MeshDeltaState(
        "origin",
        10,
        [#("n", 2)],
        ORSet([#("w", Dot("n", 2))], [Dot("retired", 1)]),
        PNCounter([#("n", 7)], [#("n", 3)]),
        LWWRegister("leader", 12, "writer"),
      ),
      [
        #(
          "n",
          LWWRegister(
            NodeHealthTelemetry("n", 0.75, -0.25, True, "closed", 8),
            11,
            "observer",
          ),
        ),
      ],
      20,
    )),
  )
}

pub fn wire_reconciliation_matches_typed_oracle_test() {
  let local = new_mesh_delta_state("local", 92)
  let health = nonempty_health()
  let remote = SyncDelta("forwarder", nonempty_state(), [], 100)
  let assert Ok(bytes) = encode_sync_message(remote)
  reconcile_remote_wire("local", local, health, bytes, 101)
  |> should.equal(
    Ok(reconcile_remote_delta("local", local, health, remote, 101)),
  )
}

pub fn malformed_wire_refuses_before_reconciliation_test() {
  let local = nonempty_state()
  let health = nonempty_health()
  reconcile_remote_wire("local", local, health, "[1,\"sync_delta\"]", 101)
  |> result.is_error
  |> should.be_true
  local |> should.equal(nonempty_state())
  health |> should.equal(nonempty_health())
}

pub fn exact_byte_decode_boundary_test() {
  let json = "[1,\"sync_ack\",\"n\",[],\"ok\",0]"
  let exact =
    json <> string.repeat(" ", mesh_wire.max_bytes - string.byte_size(json))
  decode_sync_message(exact) |> should.equal(Ok(SyncAck("n", [], "ok", 0)))
  decode_sync_message(exact <> " ") |> should.equal(Error(ByteLimit))
}

pub fn exact_byte_encode_boundary_test() {
  let prefix = list.repeat(Text(string.repeat("x", 1024)), 127)
  let value = Array(list.append(prefix, [Text(string.repeat("y", 639))]))
  let assert Ok(encoded) = mesh_wire.encode(value)
  string.byte_size(encoded) |> should.equal(mesh_wire.max_bytes)
  mesh_wire.encode(Array(list.append(prefix, [Text(string.repeat("y", 640))])))
  |> should.equal(Error(ByteLimit))
}

pub fn depth_checked_before_recursive_parse_test() {
  let exact = string.repeat("[", 12) <> "0" <> string.repeat("]", 12)
  mesh_wire.parse(exact) |> result.is_ok |> should.be_true
  mesh_wire.parse("[" <> exact <> "]") |> should.equal(Error(DepthLimit))
  mesh_wire.parse("[\"[\\\"{]\"]") |> result.is_ok |> should.be_true
}

fn clock_entries(n) {
  list.index_map(list.repeat(Nil, n), fn(_, i) {
    #("node-" <> int.to_string(i), i)
  })
}

pub fn collection_boundary_and_order_test() {
  roundtrip(SyncDigest("n", clock_entries(256), 256, 0))
  encode_sync_message(SyncDigest("n", clock_entries(257), 257, 0))
  |> should.equal(Error(CollectionLimit))
  let assert Ok(value) = mesh_wire.parse("[1,\"sync_ack\",\"n\",[],\"ok\",0]")
  mesh_wire.encode(value) |> result.is_ok |> should.be_true
  mesh_wire.parse("[" <> string.join(list.repeat("0", 257), ",") <> "]")
  |> should.equal(Error(CollectionLimit))
}

pub fn utf8_string_byte_boundaries_test() {
  let exact = string.repeat("α", 512)
  roundtrip(SyncAck("n", [], exact, 0))
  encode_sync_message(SyncAck("n", [], exact <> "x", 0))
  |> should.equal(Error(StringLimit))
  decode_sync_message("[1,\"sync_ack\",\"n\",[],\"" <> exact <> "x\",0]")
  |> should.equal(Error(StringLimit))
}

pub fn safe_integer_and_negative_boundaries_test() {
  roundtrip(SyncDigest(
    "n",
    [#("n", mesh_wire.max_integer)],
    mesh_wire.max_integer,
    mesh_wire.max_integer,
  ))
  encode_sync_message(SyncAck("n", [], "ok", mesh_wire.max_integer + 1))
  |> should.equal(Error(IntegerLimit))
  encode_sync_message(SyncDigest("n", [#("n", -1)], 0, 0))
  |> should.equal(Error(IntegerLimit))
  decode_sync_message("[1,\"sync_ack\",\"n\",[],\"ok\",9007199254740992]")
  |> should.equal(Error(IntegerLimit))
  decode_sync_message("[1,\"sync_ack\",\"n\",[],\"ok\",-1]")
  |> should.equal(Error(IntegerLimit))
}

pub fn closed_grammar_rejects_ambiguous_and_malformed_inputs_test() {
  list.each(
    [
      "{\"version\":1,\"version\":1}", "null", "true", "[]",
      "[2,\"sync_ack\",\"n\",[],\"ok\",0]", "[1,\"unknown\",\"n\",[],\"ok\",0]",
      "[1,\"sync_ack\",\"n\",[],\"ok\",0,0]", "[1,\"sync_ack\",\"n\",[],\"ok\"]",
      "[1,\"sync_ack\",\"n\",{},\"ok\",0]",
      "[1,\"sync_ack\",\"n\",[],\"ok\",0] []",
      "[1,\"sync_ack\",\"n\",[],\"\\q\",0]",
      "[1,\"sync_ack\",\"n\",[],\"ok\",1.0]",
      "[1,\"sync_digest\",\"n\",[[\"x\",1,2]],0,0]",
      "[1,\"sync_ack\",\"n\",[],\"ok\",01]",
    ],
    fn(input) {
      decode_sync_message(input) |> result.is_error |> should.be_true
    },
  )
}

pub fn duplicate_clock_and_counter_keys_refused_test() {
  encode_sync_message(SyncDigest("n", [#("x", 1), #("x", 2)], 0, 0))
  |> should.equal(Error(DuplicateKey))
  decode_sync_message("[1,\"sync_ack\",\"n\",[[\"x\",1],[\"x\",2]],\"ok\",0]")
  |> should.equal(Error(DuplicateKey))
  let state = nonempty_state()
  let bad =
    MeshDeltaState(
      ..state,
      task_counters: PNCounter([#("n", 1), #("n", 2)], []),
    )
  encode_sync_message(SyncDelta("n", bad, [], 0))
  |> should.equal(Error(DuplicateKey))
}

pub fn duplicate_health_keys_and_mismatched_nodes_refused_test() {
  let assert [entry, ..] = nonempty_health()
  encode_sync_message(SyncDelta("n", nonempty_state(), [entry, entry], 0))
  |> should.equal(Error(DuplicateKey))
  encode_sync_message(SyncDelta(
    "n",
    nonempty_state(),
    [#("wrong-key", entry.1)],
    0,
  ))
  |> should.equal(Error(NodeMismatch))
}

pub fn duplicate_live_tombstone_and_cross_set_dots_refused_test() {
  let state = nonempty_state()
  let dot = Dot("n", 1)
  list.each(
    [
      ORSet([#("w", dot), #("other", dot)], []),
      ORSet([], [dot, dot]),
      ORSet([#("w", dot)], [dot]),
    ],
    fn(workers) {
      encode_sync_message(SyncDelta(
        "n",
        MeshDeltaState(..state, active_workers: workers),
        [],
        0,
      ))
      |> should.equal(Error(DuplicateDot))
    },
  )
}

pub fn empty_node_identities_refused_test() {
  encode_sync_message(SyncAck(" ", [], "ok", 0))
  |> should.equal(Error(InvalidIdentity))
  encode_sync_message(SyncAck("n", [#("", 1)], "ok", 0))
  |> should.equal(Error(InvalidIdentity))
  let state = nonempty_state()
  encode_sync_message(SyncDelta(
    "n",
    MeshDeltaState(..state, leader_lease: LWWRegister("leader", 0, "")),
    [],
    0,
  ))
  |> should.equal(Error(InvalidIdentity))
}

pub fn physical_and_logical_health_times_survive_independently_test() {
  let message =
    SyncDelta("n", nonempty_state(), nonempty_health(), mesh_wire.max_integer)
  roundtrip(message)
  let assert [#(key, reg), ..rest] = nonempty_health()
  let negative_sample =
    LWWRegister(
      ..reg,
      value: NodeHealthTelemetry(..reg.value, sample_epoch_us: -1),
    )
  encode_sync_message(SyncDelta(
    "n",
    nonempty_state(),
    [#(key, negative_sample), ..rest],
    0,
  ))
  |> should.equal(Error(IntegerLimit))
  encode_sync_message(SyncDelta(
    "n",
    nonempty_state(),
    [#(key, LWWRegister(..reg, timestamp_us: -1))],
    0,
  ))
  |> should.equal(Error(IntegerLimit))
}

pub fn nonfinite_numeric_literals_are_refused_test() {
  list.each(["1e999", "-1e999", "NaN", "Infinity"], fn(literal) {
    mesh_wire.parse("[" <> literal <> "]") |> result.is_error |> should.be_true
  })
}

pub fn exact_float_extremes_and_escaped_strings_roundtrip_test() {
  let health = [
    #(
      "n",
      LWWRegister(
        NodeHealthTelemetry(
          "n",
          1.7976931348623157e308,
          -1.7976931348623157e308,
          False,
          "\u{0000}\"\\[]{}",
          0,
        ),
        0,
        "observer",
      ),
    ),
  ]
  roundtrip(SyncDelta("n", new_mesh_delta_state("n", 0), health, 0))
}

pub fn every_composite_collection_has_an_encoder_bound_test() {
  let s = nonempty_state()
  let entries = clock_entries(257)
  let elements = list.map(entries, fn(p) { #(p.0, Dot(p.0, p.1)) })
  let dots = list.map(elements, fn(p) { p.1 })
  let states = [
    MeshDeltaState(..s, vector_clock: entries),
    MeshDeltaState(..s, active_workers: ORSet(elements, [])),
    MeshDeltaState(..s, active_workers: ORSet([], dots)),
    MeshDeltaState(..s, task_counters: PNCounter(entries, [])),
    MeshDeltaState(..s, task_counters: PNCounter([], entries)),
  ]
  list.each(states, fn(state) {
    encode_sync_message(SyncDelta("n", state, [], 0))
    |> should.equal(Error(CollectionLimit))
  })
  let assert [entry, ..] = nonempty_health()
  encode_sync_message(SyncDelta("n", s, list.repeat(entry, 257), 0))
  |> should.equal(Error(CollectionLimit))
}

pub fn malformed_nested_wire_records_refused_test() {
  let assert Ok(bytes) =
    encode_sync_message(SyncDelta(
      "forwarder",
      nonempty_state(),
      nonempty_health(),
      100,
    ))
  list.each(
    [
      string.replace(
        bytes,
        "\"node-health\",[[\"node-health\"",
        "\"wrong\",[[\"node-health\"",
      ),
      string.replace(bytes, "[\"z\",3]", "[\"z\",-3]"),
      string.replace(bytes, "\"lease-writer\"", "null"),
      string.replace(bytes, "0.95", "\"0.95\""),
      string.replace(bytes, "true", "1"),
      string.replace(bytes, "\"observer\"", "\"\""),
    ],
    fn(bad) {
      bad |> should.not_equal(bytes)
      decode_sync_message(bad) |> result.is_error |> should.be_true
    },
  )
}

pub fn aggregate_budget_stops_before_invalid_shared_tail_test() {
  let leaf = Array(list.repeat(Text(string.repeat("x", 1024)), 256))
  let wide = Array([Array(list.repeat(leaf, 256)), mesh_wire.Integer(-1)])
  mesh_wire.validate(wide) |> should.equal(Error(ByteLimit))
  mesh_wire.encode(wide) |> should.equal(Error(ByteLimit))
}

pub fn deeply_shared_tree_and_escaping_have_aggregate_bounds_test() {
  let tree =
    list.fold(list.repeat(Nil, 12), Text(""), fn(child, _) {
      Array(list.repeat(child, 256))
    })
  mesh_wire.validate(tree) |> should.equal(Error(ByteLimit))
  mesh_wire.encode(tree) |> should.equal(Error(ByteLimit))
  mesh_wire.encode(
    Array(list.repeat(Text(string.repeat("\u{0000}", 1024)), 256)),
  )
  |> should.equal(Error(ByteLimit))
}
