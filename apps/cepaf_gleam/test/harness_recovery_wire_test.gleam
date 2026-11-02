import cepaf_gleam/harness/recovery_wire as wire
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/json_guard
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn getenv(name: String) -> Result(String, Nil)

@external(erlang, "file", "read_file")
fn read_file(path: String) -> Result(BitArray, Nil)

fn field(v: value.Value, k: String) -> value.Value {
  let assert Ok(x) = value.get(v, k)
  x
}

fn text(v: value.Value) -> String {
  let assert value.Text(s) = v
  s
}

fn vectors() -> List(value.Value) {
  let assert Ok(path) = getenv("UOS_RECOVERY_WIRE_FIXTURE")
  let assert Ok(bytes) = read_file(path)
  let assert Ok(raw) = bit_array.to_string(bytes)
  let assert Ok(v) = json_guard.native_inspect(raw, 12)
  let assert value.Array(xs) = field(v, "vectors")
  xs
}

fn input() -> value.Value {
  let assert [first, ..] = vectors()
  field(first, "input")
}

fn encode(v: value.Value) -> String {
  v |> value.encode |> json.to_string
}

fn change_member(
  v: value.Value,
  key: String,
  replacement: value.Value,
) -> value.Value {
  let assert value.Array([first, ..rest]) = field(v, "members")
  value.set(
    v,
    "members",
    value.Array([value.set(first, key, replacement), ..rest]),
  )
}

pub fn independent_literal_golden_vectors_test() {
  list.each(vectors(), fn(v) {
    let assert Ok(request) = wire.decode(encode(field(v, "input")))
    wire.canonical_bytes(request) |> should.equal(text(field(v, "canonical")))
    wire.request_sha256(request) |> should.equal(text(field(v, "sha256")))
    wire.tagged_request_sha256(request)
    |> should.equal("sha256:" <> text(field(v, "sha256")))
  })
}

pub fn ordering_and_decimal_precision_test() {
  let v = input()
  let assert value.Array(ms) = field(v, "members")
  let assert Ok(a) = wire.decode(encode(v))
  let assert Ok(b) =
    wire.decode(encode(value.set(v, "members", value.Array(list.reverse(ms)))))
  wire.canonical_bytes(a) |> should.equal(wire.canonical_bytes(b))
  string.contains(wire.canonical_bytes(a), "9007199254740993") |> should.be_true
  string.contains(wire.canonical_bytes(a), "9223372036854775807")
  |> should.be_true
}

pub fn meaningful_fields_change_digest_test() {
  let v = input()
  let assert Ok(original) = wire.decode(encode(v))
  let assert value.Array(members) = field(v, "members")
  let edits = [
    value.set(v, "request_id", value.Text("other-request")),
    value.set(v, "plan", value.Text("uos/other")),
    value.set(
      v,
      "snapshot_sha256",
      value.Text("sha256:" <> string.repeat("1", 64)),
    ),
    value.set(v, "deadline_utc_ms", value.Integer(1_793_487_751_776)),
    change_member(v, "task_id", value.Text("different-task")),
    change_member(v, "worker", value.Text("different-worker")),
    change_member(v, "old_attempt", value.Integer(99)),
    change_member(v, "old_lease_ns", value.Text("9223372036854775806")),
    value.set(
      v,
      "members",
      value.Array(
        list.map(members, fn(m) { value.set(m, "lease_ms", value.Integer(2)) }),
      ),
    ),
  ]
  list.each(edits, fn(edit) {
    let assert Ok(changed) = wire.decode(encode(edit))
    { wire.request_sha256(changed) != wire.request_sha256(original) }
    |> should.be_true
  })
}

pub fn rejected_inputs_and_integer_boundaries_test() {
  let v = input()
  let assert value.Array(ms) = field(v, "members")
  let assert [first, ..] = ms
  let edits = [
    value.set(v, "request_id", value.Text("bad:colon")),
    value.set(v, "plan", value.Text("")),
    value.set(v, "authorized", value.Boolean(True)),
    value.set(v, "snapshot_sha256", value.Text(string.repeat("a", 64))),
    value.set(
      v,
      "snapshot_sha256",
      value.Text("sha256:" <> string.repeat("A", 64)),
    ),
    value.set(v, "deadline_utc_ms", value.Integer(9_223_372_036_855)),
    value.set(v, "deadline_utc_ms", value.Integer(0)),
    value.set(v, "deadline_utc_ms", value.Number(1.0)),
    value.set(v, "members", value.Array(list.append(ms, ms))),
    value.set(v, "members", value.Array([])),
    value.set(v, "members", value.Array([first, first, first])),
    change_member(v, "lease_ms", value.Integer(2)),
    change_member(v, "lease_ms", value.Integer(0)),
    change_member(v, "lease_ms", value.Integer(3_600_001)),
    change_member(v, "old_attempt", value.Integer(0)),
    change_member(v, "old_attempt", value.Integer(1_000_000)),
    change_member(v, "old_lease_ns", value.Text("0")),
    change_member(v, "old_lease_ns", value.Text("01")),
    change_member(v, "old_lease_ns", value.Text("+1")),
    change_member(v, "old_lease_ns", value.Text("1e3")),
    change_member(v, "old_lease_ns", value.Text("9223372036854775808")),
    change_member(v, "old_lease_ns", value.Integer(1)),
    change_member(v, "worker", value.Text("nul\u{0000}worker")),
  ]
  list.each(edits, fn(edit) { wire.decode(encode(edit)) |> should.be_error })
}

pub fn strict_raw_json_refusals_test() {
  list.each(
    [
      "{\"request_id\":\"a\",\"request_id\":\"b\"}",
      "{} trailing",
      "[]",
      "null",
      "{",
      string.repeat(" ", 32_769),
      "[[[[[[[[[[[[[0]]]]]]]]]]]]]",
    ],
    fn(raw) { wire.decode(raw) |> should.be_error },
  )
}

pub fn nonstandard_syntax_in_otherwise_valid_objects_is_refused_test() {
  let raw = encode(input())
  list.each(
    [
      "/* before */" <> raw,
      "// before\n" <> raw,
      "{" <> "/* inside */" <> string.drop_start(raw, 1),
      "{" <> "// inside\n" <> string.drop_start(raw, 1),
      raw <> "/* after */",
      raw <> "// after\n",
      string.replace(raw, "\"request_id\"", "request_id"),
      string.drop_end(raw, 1) <> ",}",
    ],
    fn(commented) { wire.decode(commented) |> should.be_error },
  )
  let assert Ok(clean) = wire.decode(raw)
  let assert Ok(spaced) = wire.decode(" \t\r\n" <> raw <> " \t\r\n")
  wire.canonical_bytes(spaced) |> should.equal(wire.canonical_bytes(clean))
  let assert Ok(slashes) =
    wire.decode(encode(value.set(input(), "request_id", value.Text("r//x"))))
  string.contains(wire.canonical_bytes(slashes), "r//x") |> should.be_true
}
