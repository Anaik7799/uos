import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_gameday as gameday
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const dir = "build/telegram_action_gameday_test_tmp"

const names = [
  "packet-loss-moderate", "packet-loss-catastrophic", "heartbeat-jitter-minor",
  "heartbeat-jitter-severe", "worker-oom", "queue-latency-minor",
  "queue-latency-spike",
]

fn fresh_dir(name: String) -> String {
  let path = dir <> "_" <> name
  let _ = simplifile.delete(path)
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  path
}

fn req(name: String) {
  let assert Ok(r) = gameday.parse(name)
  r
}

fn has(text: String, part: String) -> Bool {
  string.contains(text, part)
}

pub fn literal_is_gameday_test() {
  gameday.literal() |> should.equal("/gameday")
}

pub fn parse_accepts_every_allowlisted_scenario_test() {
  list.each(names, fn(n) {
    case gameday.parse(" " <> n <> "\n") {
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
      "reboot-prod",
      "worker-oom now",
      "worker-oom;ls",
      "WORKER-OOM",
      "packet-loss-0.9",
      "../x",
      "worker-oom\u{0}",
      "é",
      string.repeat("a", 257),
    ],
    fn(input) {
      case gameday.parse(input) {
        Error(usage) -> {
          has(usage, "usage: /gameday") |> should.equal(True)
          list.each(names, fn(n) { has(usage, n) |> should.equal(True) })
        }
        Ok(_) -> should.fail()
      }
    },
  )
}

pub fn effect_id_is_stable_distinct_digest_test() {
  let a = gameday.effect_id(req("worker-oom"))
  a |> should.equal(gameday.effect_id(req("worker-oom")))
  { a != gameday.effect_id(req("queue-latency-spike")) } |> should.equal(True)
  a |> should.equal(files.digest("uos.telegram.action.v1|/gameday|worker-oom"))
}

pub fn preview_shape_and_simulated_label_test() {
  let out = gameday.preview(req("packet-loss-catastrophic"))
  has(out, "\"status\":\"preview\"") |> should.equal(True)
  has(out, "\"confidence\":\"simulated\"") |> should.equal(True)
  has(out, "\"scenario\":\"packet-loss-catastrophic\"") |> should.equal(True)
  has(out, "\"response\":\"andon_emergency_halt\"") |> should.equal(True)
  has(out, "\"andon_tripped\":true") |> should.equal(True)
  has(out, "\"metabolic_health_milli\":0") |> should.equal(True)
  has(out, "\"real_effects\":\"none\"") |> should.equal(True)
  { string.byte_size(out) <= 3500 } |> should.equal(True)
  case json.parse(out, decode.dynamic) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn simulation_matches_backend_behaviour_test() {
  let moderate = gameday.preview(req("packet-loss-moderate"))
  has(moderate, "\"response\":\"antibody_neutralized\"") |> should.equal(True)
  has(moderate, "\"andon_tripped\":false") |> should.equal(True)
  has(moderate, "\"containment_preserved\":true") |> should.equal(True)
  let jitter = gameday.preview(req("heartbeat-jitter-severe"))
  has(jitter, "\"response\":\"hot_reload_triggered\"") |> should.equal(True)
  let spike = gameday.preview(req("queue-latency-spike"))
  has(spike, "\"response\":\"throttling_engaged\"") |> should.equal(True)
}

pub fn every_scenario_preview_is_bounded_and_simulated_test() {
  list.each(names, fn(n) {
    let out = gameday.preview(req(n))
    { string.byte_size(out) <= 3500 } |> should.equal(True)
    has(out, "\"confidence\":\"simulated\"") |> should.equal(True)
  })
}

pub fn preview_does_not_write_anything_test() {
  let d = fresh_dir("preview")
  let _ = gameday.preview(req("worker-oom"))
  simplifile.read_directory(d) |> should.equal(Ok([]))
}

pub fn execute_writes_receipt_then_duplicate_test() {
  let d = fresh_dir("exec")
  let r = req("worker-oom")
  let assert Ok(first) = gameday.execute(r, d)
  has(first, "\"status\":\"executed\"") |> should.equal(True)
  has(first, "\"confidence\":\"simulated\"") |> should.equal(True)
  has(first, "\"response\":\"hot_reload_triggered\"") |> should.equal(True)
  let file = d <> "/" <> gameday.effect_id(r) <> ".json"
  simplifile.read(file) |> should.equal(Ok(first))
  let assert Ok(second) = gameday.execute(r, d)
  has(second, "\"status\":\"duplicate\"") |> should.equal(True)
  has(second, "\"confidence\":\"simulated\"") |> should.equal(True)
  has(second, "\"receipt_sha256\":\"" <> files.digest(first) <> "\"")
  |> should.equal(True)
  simplifile.read(file) |> should.equal(Ok(first))
  let assert Ok(entries) = simplifile.read_directory(d)
  entries |> should.equal([gameday.effect_id(r) <> ".json"])
}

pub fn execute_distinct_scenarios_distinct_receipts_test() {
  let d = fresh_dir("two")
  let assert Ok(_) = gameday.execute(req("worker-oom"), d)
  let assert Ok(b) = gameday.execute(req("queue-latency-spike"), d)
  has(b, "\"status\":\"executed\"") |> should.equal(True)
  let assert Ok(entries) = simplifile.read_directory(d)
  list.length(entries) |> should.equal(2)
}

pub fn execute_refuses_missing_or_non_directory_evidence_dir_test() {
  let missing = "build/telegram_action_gameday_test_tmp_absent"
  let _ = simplifile.delete(missing)
  gameday.execute(req("worker-oom"), missing)
  |> should.equal(Error("evidence_dir_required"))
  simplifile.is_directory(missing) |> should.equal(Ok(False))
  gameday.execute(req("worker-oom"), "")
  |> should.equal(Error("evidence_dir_required"))
  let d = fresh_dir("file")
  let assert Ok(Nil) = simplifile.write(d <> "/plain", "x")
  gameday.execute(req("worker-oom"), d <> "/plain")
  |> should.equal(Error("evidence_dir_required"))
}
