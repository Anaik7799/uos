import cepaf_gleam/harness/telegram_action_migrate as action
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

fn keys(text: String) -> List(String) {
  let assert Ok(object) =
    json.parse(text, decode.dict(decode.string, decode.dynamic))
  dict.keys(object) |> list.sort(string.compare)
}

fn status_of(text: String) -> String {
  let decoder = {
    use status <- decode.field("status", decode.string)
    decode.success(status)
  }
  let assert Ok(status) = json.parse(text, decoder)
  status
}

fn is_error(r: Result(a, String)) -> Bool {
  case r {
    Ok(_) -> False
    Error(_) -> True
  }
}

fn req() {
  let assert Ok(r) = action.parse("MIG-01-INGRESS discovered")
  r
}

pub fn literal_test() {
  action.literal() |> should.equal("/migrate")
}

pub fn parse_positive_test() {
  let assert Ok(a) = action.parse("MIG-01-INGRESS")
  let assert Ok(a2) = action.parse("  MIG-01-INGRESS  ")
  let assert Ok(b) = action.parse("MIG-01-INGRESS classified")
  let assert Ok(c) = action.parse("MIG-02-SANDBOX")
  action.effect_id(a) |> should.equal(action.effect_id(a2))
  action.effect_id(a) |> should.not_equal(action.effect_id(b))
  action.effect_id(a) |> should.not_equal(action.effect_id(c))
  string.starts_with(action.effect_id(a), "migrate-") |> should.equal(True)
  string.byte_size(action.effect_id(a)) |> should.equal(72)
  list.each(
    [
      "MIG-01-INGRESS", "MIG-02-SANDBOX", "MIG-03-DNS", "MIG-04-CRYPTO",
      "MIG-05-LEDGER", "MIG-06-FORWARD", "MIG-07-SOLVER",
    ],
    fn(id) {
      let assert Ok(r) = action.parse(id)
      status_of(action.preview(r)) |> should.equal("preview")
    },
  )
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "MIG-99-NOPE",
      "mig-01-ingress",
      "MIG-01-INGRESS verified",
      "MIG-01-INGRESS mapped extra",
      "MIG-01-INGRESS Mapped",
      "MIG 01",
      "MIG-01-INGRESS\u{0}",
      string.repeat("A", 257),
    ],
    fn(input) { action.parse(input) |> is_error |> should.equal(True) },
  )
  let assert Error(message) = action.parse(string.repeat("A", 257))
  string.starts_with(message, "args_bound") |> should.equal(True)
}

pub fn preview_shape_and_simulated_confidence_test() {
  let text = action.preview(req())
  status_of(text) |> should.equal("preview")
  keys(text)
  |> should.equal([
    "admission", "approval_required", "authority", "candidate", "confidence",
    "effect", "effect_id", "estimate_basis", "from_stage", "layer", "literal",
    "migrated", "name", "projected_ram_saving_mb", "projected_speedup_pct",
    "stage_changed", "state_source", "status", "to_stage",
  ])
  string.contains(text, "\"confidence\":\"simulated\"") |> should.equal(True)
  string.contains(text, "\"migrated\":false") |> should.equal(True)
  string.contains(text, "\"estimate_basis\":\"configured_projection\"")
  |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn stage_ladder_matches_the_backend_test() {
  let go = fn(args: String) {
    let assert Ok(r) = action.parse(args)
    action.preview(r)
  }
  let d = go("MIG-03-DNS discovered")
  string.contains(d, "\"from_stage\":\"Discovered\"") |> should.equal(True)
  string.contains(d, "\"to_stage\":\"Classified\"") |> should.equal(True)
  string.contains(d, "\"stage_changed\":true") |> should.equal(True)
  let c = go("MIG-03-DNS classified")
  string.contains(c, "\"to_stage\":\"Mapped\"") |> should.equal(True)
  let m = go("MIG-03-DNS mapped")
  string.contains(m, "\"from_stage\":\"Mapped\"") |> should.equal(True)
  string.contains(m, "\"to_stage\":\"Mapped\"") |> should.equal(True)
  string.contains(m, "\"stage_changed\":false") |> should.equal(True)
  let declared = go("MIG-03-DNS")
  string.contains(declared, "\"from_stage\":\"Mapped\"") |> should.equal(True)
}

pub fn receipt_records_transition_without_migrating_test() {
  let dir = fresh_dir("receipt")
  let assert Ok(reply) = action.execute(req(), dir)
  string.contains(reply, "\"candidate\":\"MIG-01-INGRESS\"")
  |> should.equal(True)
  string.contains(reply, "\"from_stage\":\"Discovered\"") |> should.equal(True)
  string.contains(reply, "\"to_stage\":\"Classified\"") |> should.equal(True)
  string.contains(reply, "\"migrated\":false") |> should.equal(True)
  string.contains(reply, "\"effect\":\"stage_transition_record_only\"")
  |> should.equal(True)
  string.contains(reply, "\"admission\":\"unverified\"") |> should.equal(True)
}

pub fn distinct_requests_get_distinct_receipts_test() {
  let dir = fresh_dir("distinct")
  let assert Ok(a) = action.parse("MIG-01-INGRESS")
  let assert Ok(b) = action.parse("MIG-02-SANDBOX")
  let assert Ok(ra) = action.execute(a, dir)
  let assert Ok(rb) = action.execute(b, dir)
  status_of(ra) |> should.equal("executed")
  status_of(rb) |> should.equal("executed")
  let assert Ok(files) = simplifile.read_directory(dir)
  list.length(files) |> should.equal(2)
}

fn fresh_dir(name: String) -> String {
  let dir = "/tmp/uos_w1_migrate_test_" <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

pub fn preview_creates_nothing_test() {
  let dir = fresh_dir("preview")
  let _ = action.preview(req())
  simplifile.read_directory(dir) |> should.equal(Ok([]))
}

pub fn execute_writes_receipt_exclusively_test() {
  let dir = fresh_dir("write")
  let r = req()
  let assert Ok(reply) = action.execute(r, dir)
  status_of(reply) |> should.equal("executed")
  string.contains(reply, "\"confidence\":\"simulated\"") |> should.equal(True)
  string.contains(reply, "\"clock\":\"not_sampled\"") |> should.equal(True)
  string.contains(reply, "\"authority\":\"NONE\"") |> should.equal(True)
  let path = dir <> "/" <> action.effect_id(r) <> ".json"
  simplifile.read(path) |> should.equal(Ok(reply))
  simplifile.read_directory(dir)
  |> should.equal(Ok([action.effect_id(r) <> ".json"]))
}

pub fn execute_repeat_is_duplicate_with_stored_receipt_test() {
  let dir = fresh_dir("dup")
  let r = req()
  let assert Ok(first) = action.execute(r, dir)
  let assert Ok(second) = action.execute(r, dir)
  let assert Ok(third) = action.execute(r, dir)
  status_of(second) |> should.equal("duplicate")
  status_of(third) |> should.equal("duplicate")
  string.contains(second, first) |> should.equal(True)
  { string.byte_size(second) <= 3500 } |> should.equal(True)
  simplifile.read(dir <> "/" <> action.effect_id(r) <> ".json")
  |> should.equal(Ok(first))
  let assert Ok(files) = simplifile.read_directory(dir)
  list.length(files) |> should.equal(1)
}

pub fn execute_refuses_missing_or_empty_evidence_dir_test() {
  let missing = "/tmp/uos_w1_migrate_test_absent_dir_xyz"
  let _ = simplifile.delete(missing)
  action.execute(req(), missing) |> should.equal(Error("evidence_dir_missing"))
  action.execute(req(), "") |> should.equal(Error("evidence_dir_missing"))
  action.execute(req(), "   ") |> should.equal(Error("evidence_dir_missing"))
  simplifile.is_directory(missing) |> should.equal(Ok(False))
}

pub fn execute_refuses_a_file_as_evidence_dir_test() {
  let dir = fresh_dir("filedir")
  let file = dir <> "/not_a_dir"
  let assert Ok(_) = simplifile.write(file, "x")
  action.execute(req(), file) |> should.equal(Error("evidence_dir_missing"))
}

pub fn tampered_stored_receipt_fails_closed_test() {
  let dir = fresh_dir("tamper")
  let r = req()
  let path = dir <> "/" <> action.effect_id(r) <> ".json"
  let assert Ok(_) =
    simplifile.write(
      path,
      "{\"status\":\"executed\",\"literal\":\"/migrate\",\"effect_id\":\"migrate-forged\"}",
    )
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
  let assert Ok(_) = simplifile.write(path, "not json")
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
  let assert Ok(_) =
    simplifile.write(
      path,
      "{\"status\":\"preview\",\"literal\":\"/migrate\",\"effect_id\":\""
        <> action.effect_id(r)
        <> "\"}",
    )
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
}
