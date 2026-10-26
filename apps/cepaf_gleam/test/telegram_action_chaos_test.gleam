import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_chaos as chaos
import cepaf_gleam/testing/chaos_injector
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const dir = "build/telegram_action_chaos_test_tmp"

fn fresh_dir(name: String) -> String {
  let path = dir <> "_" <> name
  let _ = simplifile.delete(path)
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  path
}

fn req(name: String) {
  let assert Ok(r) = chaos.parse(name)
  r
}

fn has(text: String, part: String) -> Bool {
  string.contains(text, part)
}

pub fn literal_is_chaos_test() {
  chaos.literal() |> should.equal("/chaos")
}

pub fn parse_accepts_every_catalogue_scenario_test() {
  let names = list.map(chaos_injector.all_scenarios(), fn(s) { s.name })
  { list.length(names) >= 20 } |> should.equal(True)
  list.each(names, fn(n) {
    case chaos.parse("  " <> n <> "\n") {
      Ok(_) -> Nil
      Error(_) -> should.fail()
    }
  })
}

pub fn parse_denies_non_allowlisted_with_usage_test() {
  list.each(
    [
      "",
      " ",
      "rm-rf",
      "db-prod-kill extra",
      "db-prod-kill;ls",
      "DB-PROD-KILL",
      "../etc",
      "ollama-kill\u{0}",
      "é",
      string.repeat("a", 257),
      string.repeat(" ", 300) <> "ollama-kill",
    ],
    fn(input) {
      case chaos.parse(input) {
        Error(usage) -> {
          has(usage, "usage: /chaos") |> should.equal(True)
          has(usage, "ollama-kill") |> should.equal(True)
          has(usage, "zenoh-router-kill") |> should.equal(True)
        }
        Ok(_) -> should.fail()
      }
    },
  )
}

pub fn effect_id_is_stable_distinct_digest_test() {
  let a = chaos.effect_id(req("db-prod-kill"))
  a |> should.equal(chaos.effect_id(req("db-prod-kill")))
  { a != chaos.effect_id(req("ollama-kill")) } |> should.equal(True)
  string.length(a) |> should.equal(64)
  a |> should.equal(files.digest("uos.telegram.action.v1|/chaos|db-prod-kill"))
}

pub fn preview_shape_and_confidence_label_test() {
  let out = chaos.preview(req("db-prod-kill"))
  has(out, "\"status\":\"preview\"") |> should.equal(True)
  has(out, "\"confidence\":\"declared\"") |> should.equal(True)
  has(out, "\"scenario\":\"db-prod-kill\"") |> should.equal(True)
  has(out, "\"severity\":\"HIGH\"") |> should.equal(True)
  has(out, "\"guardian_required_for_live\":true") |> should.equal(True)
  has(out, "\"target\":\"synthetic:db-prod-kill\"") |> should.equal(True)
  has(out, "\"real_effects\":\"none\"") |> should.equal(True)
  has(out, "\"effect_id\":\"" <> chaos.effect_id(req("db-prod-kill")) <> "\"")
  |> should.equal(True)
  has(
    chaos.preview(req("otel-collector-kill")),
    "\"guardian_required_for_live\":false",
  )
  |> should.equal(True)
  { string.byte_size(out) <= 3500 } |> should.equal(True)
  case json.parse(out, decode.dynamic) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn preview_does_not_write_anything_test() {
  let d = fresh_dir("preview")
  let _ = chaos.preview(req("ollama-kill"))
  simplifile.read_directory(d) |> should.equal(Ok([]))
}

pub fn execute_writes_receipt_then_duplicate_test() {
  let d = fresh_dir("exec")
  let r = req("ollama-kill")
  let assert Ok(first) = chaos.execute(r, d)
  has(first, "\"status\":\"executed\"") |> should.equal(True)
  has(first, "\"confidence\":\"simulated\"") |> should.equal(True)
  has(first, "\"synthetic_deaths\":1") |> should.equal(True)
  has(first, "\"synthetic_resurrections\":1") |> should.equal(True)
  has(first, "\"real_effects\":\"none\"") |> should.equal(True)
  let file = d <> "/" <> chaos.effect_id(r) <> ".json"
  simplifile.read(file) |> should.equal(Ok(first))
  let assert Ok(second) = chaos.execute(r, d)
  has(second, "\"status\":\"duplicate\"") |> should.equal(True)
  has(second, "\"receipt_sha256\":\"" <> files.digest(first) <> "\"")
  |> should.equal(True)
  has(second, "executed") |> should.equal(True)
  simplifile.read(file) |> should.equal(Ok(first))
  let assert Ok(entries) = simplifile.read_directory(d)
  entries |> should.equal([chaos.effect_id(r) <> ".json"])
}

pub fn execute_non_kill_scenario_has_no_synthetic_deaths_test() {
  let d = fresh_dir("nonkill")
  let assert Ok(out) = chaos.execute(req("sqlite-wal-disk-full"), d)
  has(out, "\"synthetic_deaths\":0") |> should.equal(True)
  has(out, "\"injection_type\":\"disk_full\"") |> should.equal(True)
}

pub fn execute_is_idempotent_per_scenario_only_test() {
  let d = fresh_dir("two")
  let assert Ok(_) = chaos.execute(req("ollama-kill"), d)
  let assert Ok(b) = chaos.execute(req("db-prod-kill"), d)
  has(b, "\"status\":\"executed\"") |> should.equal(True)
  let assert Ok(entries) = simplifile.read_directory(d)
  list.length(entries) |> should.equal(2)
}

pub fn execute_refuses_missing_or_non_directory_evidence_dir_test() {
  let missing = "build/telegram_action_chaos_test_tmp_absent"
  let _ = simplifile.delete(missing)
  chaos.execute(req("ollama-kill"), missing)
  |> should.equal(Error("evidence_dir_required"))
  simplifile.is_directory(missing) |> should.equal(Ok(False))
  chaos.execute(req("ollama-kill"), "")
  |> should.equal(Error("evidence_dir_required"))
  let d = fresh_dir("file")
  let assert Ok(Nil) = simplifile.write(d <> "/plain", "x")
  chaos.execute(req("ollama-kill"), d <> "/plain")
  |> should.equal(Error("evidence_dir_required"))
}

pub fn every_scenario_preview_is_bounded_test() {
  list.each(chaos_injector.all_scenarios(), fn(s) {
    { string.byte_size(chaos.preview(req(s.name))) <= 3500 }
    |> should.equal(True)
  })
}
