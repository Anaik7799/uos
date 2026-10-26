import cepaf_gleam/harness/telegram_action_sidecar as sidecar
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const base = "/tmp/claude-1000/-home-an-NAS-setup-uos/35600f5c-f8c9-4312-b1e0-07fde55d77cc/scratchpad/w3/sidecar-"

fn fresh(name: String) -> String {
  let dir = base <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

fn req(args: String) {
  let assert Ok(r) = sidecar.parse(args)
  r
}

pub fn literal_and_parse_positive_test() {
  sidecar.literal() |> should.equal("/sidecar")
  let names = [
    "ingress",
    "sandbox",
    "dns",
    "crypto",
    "ledger",
    "forward",
    "solver",
  ]
  let ids = list.map(names, fn(n) { sidecar.effect_id(req(n)) })
  list.length(list.unique(ids)) |> should.equal(7)
  list.each(ids, fn(id) { string.length(id) |> should.equal(64) })
  sidecar.effect_id(req("  dns "))
  |> should.equal(sidecar.effect_id(req("dns")))
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "listen",
      "INGRESS",
      "MIG-01-INGRESS",
      "ingress dns",
      "dns;rm",
      "../dns",
      string.repeat("a", 257),
    ],
    fn(input) {
      case sidecar.parse(input) {
        Error(message) ->
          string.starts_with(message, "usage: /sidecar <ingress|")
          |> should.equal(True)
        Ok(_) -> should.fail()
      }
    },
  )
}

pub fn preview_shape_and_confidence_test() {
  let text = sidecar.preview(req("sandbox"))
  string.contains(text, "\"status\":\"preview\"") |> should.equal(True)
  string.contains(text, "\"confidence\":\"simulated\"") |> should.equal(True)
  string.contains(text, "\"literal\":\"/sidecar\"") |> should.equal(True)
  string.contains(text, "\"candidate_id\":\"MIG-02-SANDBOX\"")
  |> should.equal(True)
  string.contains(text, "\"platform\":\"solo5-spt\"") |> should.equal(True)
  string.contains(text, "\"configured_memory_mb\":16") |> should.equal(True)
  string.contains(text, "\"runtime_mode\":\"simulation_only\"")
  |> should.equal(True)
  string.contains(text, "\"runtime_observation\":\"unknown\"")
  |> should.equal(True)
  string.contains(text, "\"admission\":\"unverified\"") |> should.equal(True)
  string.contains(text, "unavailable:mirage_unikernel_daemon")
  |> should.equal(True)
  string.contains(text, "\"authority\":\"NONE\"") |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn execute_is_unavailable_and_writes_nothing_test() {
  let dir = fresh("unavail")
  sidecar.execute(req("ingress"), dir)
  |> should.equal(Error("backend_unavailable:mirage_unikernel_daemon"))
  sidecar.execute(req("ingress"), dir)
  |> should.equal(Error("backend_unavailable:mirage_unikernel_daemon"))
  simplifile.read_directory(dir) |> should.equal(Ok([]))
  let reply = sidecar.unavailable_reply(req("ingress"))
  string.contains(reply, "\"status\":\"backend_unavailable\"")
  |> should.equal(True)
  string.contains(reply, "\"backend\":\"mirage_unikernel_daemon\"")
  |> should.equal(True)
}

pub fn execute_refuses_missing_evidence_dir_test() {
  let dir = base <> "does-not-exist"
  let _ = simplifile.delete(dir)
  sidecar.execute(req("dns"), dir)
  |> should.equal(Error("evidence_dir_unavailable"))
  simplifile.is_directory(dir) |> should.equal(Ok(False))
}
