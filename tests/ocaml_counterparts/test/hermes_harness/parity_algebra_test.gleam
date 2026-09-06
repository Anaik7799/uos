import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import ocaml_counterparts/native
import simplifile

// Catches the vacuous-truth bug: required empty evidence must withhold credit.
pub fn bdd_empty_required_test() {
  let reply =
    native.request(
      "report",
      json.object([
        #("required", json.bool(True)),
        #("verdicts", json.array([], json.string)),
      ]),
    )
  let value = reply |> should.be_ok
  value
  |> decode.run(decode.field("rolled", decode.string, decode.success))
  |> should.equal(Ok("unmapped"))
}

fn call(op: String, args: json.Json) -> Dynamic {
  native.request(op, args) |> should.be_ok
}

fn field(value: Dynamic, key: String, decoder: decode.Decoder(a)) -> a {
  decode.run(value, decode.field(key, decoder, decode.success)) |> should.be_ok
}

const all = ["unmapped", "blocked", "verified", "divergent"]

fn report(required: Bool, verdicts: List(String)) -> Dynamic {
  call(
    "report",
    json.object([
      #("required", json.bool(required)),
      #("verdicts", json.array(verdicts, json.string)),
    ]),
  )
}

fn rolled(value: Dynamic) -> String {
  field(value, "rolled", decode.string)
}

fn number(value: Dynamic, key: String) -> Int {
  field(value, key, decode.int)
}

fn text(value: Dynamic, key: String) -> String {
  field(value, key, decode.string)
}

fn flag(value: Dynamic, key: String) -> Bool {
  field(value, key, decode.bool)
}

// Rejects swapped constructors, credit/defect conflation and wrong severity.
pub fn unit_and_structure_test() {
  let values =
    call("observe", json.object([]))
    |> field("verdicts", decode.list(decode.dynamic))
  list.length(values) |> should.equal(4)
  list.map(values, text(_, "name"))
  |> list.unique
  |> list.length
  |> should.equal(4)
  list.each(
    list.zip(values, [
      #("unmapped", 1, False, False),
      #("blocked", 2, False, False),
      #("verified", 0, True, False),
      #("divergent", 3, False, True),
    ]),
    fn(pair) {
      let #(v, #(name, rank, credit, defect)) = pair
      text(v, "name") |> should.equal(name)
      number(v, "rank") |> should.equal(rank)
      flag(v, "grants_credit") |> should.equal(credit)
      flag(v, "asserts_defect") |> should.equal(defect)
    },
  )
  list.count(values, flag(_, "grants_credit")) |> should.equal(1)
  list.count(values, flag(_, "asserts_defect")) |> should.equal(1)
  list.count(values, fn(v) {
    !flag(v, "grants_credit") && !flag(v, "asserts_defect")
  })
  |> should.equal(2)
}

fn combined(matrix: List(List(String)), a: String, b: String) -> String {
  let row = list.zip(all, matrix) |> list.key_find(a) |> should.be_ok
  list.zip(all, row) |> list.key_find(b) |> should.be_ok
}

// Exhaustive laws use actual native combine outputs, including nested results.
pub fn property_test() {
  let observed = call("observe", json.object([]))
  let matrix =
    field(observed, "combine", decode.list(decode.list(decode.string)))
  let identity = text(observed, "identity")
  list.each(all, fn(a) {
    combined(matrix, a, a) |> should.equal(a)
    combined(matrix, identity, a) |> should.equal(a)
    combined(matrix, "divergent", a) |> should.equal("divergent")
    list.each(all, fn(b) {
      combined(matrix, a, b) |> should.equal(combined(matrix, b, a))
      let before = report(True, [a])
      let after = report(True, [a, b])
      flag(after, "grants_credit")
      |> should.equal(flag(before, "grants_credit") && b == "verified")
      list.each(all, fn(c) {
        combined(matrix, combined(matrix, a, b), c)
        |> should.equal(combined(matrix, a, combined(matrix, b, c)))
      })
    })
  })
  rolled(report(True, ["verified", "blocked", "unmapped"]))
  |> should.equal(rolled(report(True, ["unmapped", "blocked", "verified"])))
}

pub fn bdd_test() {
  let empty = report(True, [])
  rolled(empty) |> should.equal("unmapped")
  flag(empty, "grants_credit") |> should.be_false
  rolled(report(True, ["verified", "verified", "blocked"]))
  |> should.equal("blocked")
  rolled(report(True, ["blocked", "divergent"])) |> should.equal("divergent")
  rolled(report(True, ["verified", "verified"])) |> should.equal("verified")
  let impacts =
    call("observe", json.object([]))
    |> field("impacts", decode.list(decode.string))
  impacts |> should.equal(["blocked", "divergent", "unmapped"])
}

pub fn feature_test() {
  let r = report(True, ["verified", "verified", "blocked", "unmapped"])
  list.map(
    ["total", "verified", "blocked", "unmapped", "divergent", "percent"],
    number(r, _),
  )
  |> should.equal([4, 2, 1, 1, 0, 50])
  rolled(r) |> should.equal("blocked")
  text(r, "verdict") |> should.equal("blocked")
  text(r, "rendered")
  |> should.equal(
    "blocked (2/4 verified, 1 blocked, 0 divergent, 1 unmapped, 50%)",
  )
  let nearly = report(True, ["blocked", ..list.repeat("verified", 94)])
  number(nearly, "percent") |> should.equal(98)
  should.be_false(text(nearly, "verdict") == "verified")
  should.be_true(string.length(text(nearly, "rendered")) > 0)
}

// OCaml exports original Random.init/int/List.init/bool order with observations.
pub fn fuzz_test() {
  let vectors =
    call("vectors", json.object([]))
    |> field("vectors", decode.list(decode.dynamic))
  list.length(vectors) |> should.equal(2000)
  let inputs_decoder = {
    use inputs <- decode.field("inputs", decode.list(decode.string))
    use required <- decode.field("required", decode.bool)
    decode.success(#(inputs, required))
  }
  let fixture =
    simplifile.read("fixtures/20260905-2209-parity-random-vectors.json")
    |> should.be_ok
    |> json.parse(decode.list(inputs_decoder))
    |> should.be_ok
  list.map(vectors, fn(v) { decode.run(v, inputs_decoder) |> should.be_ok })
  |> should.equal(fixture)
  list.each(vectors, fn(v) {
    let inputs = field(v, "inputs", decode.list(decode.string))
    let r = field(v, "report", decode.dynamic)
    text(r, "verdict") |> should.equal(rolled(r))
    should.equal(
      number(r, "verified")
        + number(r, "blocked")
        + number(r, "divergent")
        + number(r, "unmapped"),
      number(r, "total"),
    )
    number(r, "total") |> should.equal(list.length(inputs))
    let percent = number(r, "percent")
    should.be_true(percent >= 0 && percent <= 100)
    should.be_true(
      !flag(r, "grants_credit") || list.all(inputs, fn(v) { v == "verified" }),
    )
    should.be_true(
      !list.contains(inputs, "divergent") || rolled(r) == "divergent",
    )
  })
}

pub fn chaos_test() {
  chaos_with_report(report)
}

// Test-only injection keeps the mutation probe on these exact assertions.
pub fn chaos_with_report(report: fn(Bool, List(String)) -> Dynamic) {
  let r = report(True, ["blocked", ..list.repeat("verified", 99_999)])
  number(r, "total") |> should.equal(100_000)
  text(r, "verdict") |> should.equal("blocked")
  rolled(r) |> should.equal("blocked")
  number(r, "percent") |> should.equal(99)
  let bad = report(True, list.repeat("divergent", 10_000))
  text(bad, "verdict") |> should.equal("divergent")
  rolled(bad) |> should.equal("divergent")
  number(bad, "percent") |> should.equal(0)
  rolled(report(False, [])) |> should.equal("verified")
  rolled(report(True, [])) |> should.equal("unmapped")
}
