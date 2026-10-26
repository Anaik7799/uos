//// Laws for the /verify packet loader: a trusted profile, the exact
//// reservation, verify-purpose receipts and a canonical record are all
//// required; the cancellation and verify loaders refuse each other's packets.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_action_packet as action_packet
import cepaf_gleam/harness/telegram_action_profile as profile
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_cancellation as cancel
import cepaf_gleam/harness/telegram_verify_action as verify_action
import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_packet as packet
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import simplifile
import telegram_action_service_test as svc
import telegram_verify_action_test as fx

const created = 1_020_000

const mapping = "mapping-1"

const guardian = "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe"

const guardian_sha = "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab"

const recovery = "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe"

const recovery_sha = "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e"

fn context() -> profile.Context {
  profile.Context(
    7,
    "uos/example",
    "TASK",
    "operator",
    6,
    9,
    1,
    string.repeat("a", 64),
    fx.host,
    fx.boot,
    string.repeat("0123456789abcdef", 4),
  )
}

type Fixture {
  Fixture(
    root: String,
    p: profile.Profile,
    binding: action.Binding,
    intent: action.Intent,
  )
}

fn fixture(tag: String) -> Fixture {
  let root =
    "/tmp/uos_tg_verify_packet_test_"
    <> tag
    <> "_"
    <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(root)
  let c = context()
  let raw =
    svc.profile_raw(
      c,
      mapping,
      1_200_000_000_000,
      guardian,
      guardian_sha,
      recovery,
      recovery_sha,
      root <> "/telegram.sqlite3",
      created,
    )
  let assert Ok(p) =
    profile.persist(root, "profile.json", raw, files.digest(raw), c)
  let binding =
    action.Binding(
      ..fx.binding(),
      execution: action.Execution(
        mapping,
        "control-lease",
        3,
        profile.digest(p),
      ),
    )
  let assert Ok(intent) =
    action.new_kind(
      action.VerifyProfile,
      binding,
      verify_action.target_for(
        "uos/example",
        fx.verify_binding(),
        fx.worker,
        fx.lease_until_ns,
      ),
      fx.window(),
      "Operator requested verification of telegram-core",
      string.repeat("b", 64),
    )
  Fixture(root, p, binding, intent)
}

fn envelope(
  schema: String,
  record_key: String,
  record_json: String,
  receipts: List(approval.Receipt),
) -> String {
  json.object([
    #("schema", json.string(schema)),
    #(record_key, json.string(record_json)),
    #(
      "receipts",
      json.array(receipts, fn(r) {
        json.array([approval.role_name(r.role), r.token], json.string)
      }),
    ),
  ])
  |> json.to_string
}

fn verify_packet(f: Fixture, purpose: String, deadline: Int) -> String {
  envelope(
    packet.expected_schema,
    "record_json",
    verify_action.encode_parts(f.intent, deadline, fx.verify_binding()),
    fx.receipts(f.intent, purpose, profile.roster(f.p)),
  )
}

fn write(f: Fixture, name: String, text: String) -> Nil {
  let assert Ok(_) = files.create(f.root, name, text)
  Nil
}

fn load(f: Fixture, name: String) {
  packet.load(f.p, f.root, name, fx.observed(), fx.verify_binding())
}

pub fn a_verify_packet_for_the_reservation_loads_test() {
  let f = fixture("ok")
  write(f, "packet.json", verify_packet(f, "verify_profile", 1_060_000))
  let assert Ok(prepared) = load(f, "packet.json")
  verify_action.deadline_ms(prepared) |> should.equal(1_060_000)
  verify_action.verify_binding(prepared) |> should.equal(fx.verify_binding())
  verify_action.effect_id(prepared) |> should.equal(action.effect_id(f.intent))
  verify_action.ready(
    prepared,
    profile.roster(f.p),
    f.binding,
    fx.verify_binding(),
    fx.observed(),
  )
  |> should.be_true
}

pub fn a_packet_for_another_reservation_is_refused_test() {
  let f = fixture("reservation")
  write(f, "packet.json", verify_packet(f, "verify_profile", 1_060_000))
  packet.load(
    f.p,
    f.root,
    "packet.json",
    fx.observed(),
    v.Binding(..fx.verify_binding(), attempt: 2),
  )
  |> should.equal(Error(packet.invalid_error))
}

pub fn receipts_with_the_cancellation_purpose_are_refused_test() {
  let f = fixture("purpose")
  write(f, "packet.json", verify_packet(f, "cancel_job_lease", 1_060_000))
  load(f, "packet.json") |> should.equal(Error(packet.invalid_error))
}

pub fn a_record_deadline_that_disagrees_with_the_receipts_is_refused_test() {
  let f = fixture("deadline")
  write(f, "packet.json", verify_packet(f, "verify_profile", 1_050_000))
  load(f, "packet.json") |> should.equal(Error(packet.invalid_error))
}

pub fn the_two_loaders_refuse_each_others_packets_test() {
  let f = fixture("kinds")
  // A verify packet presented to the cancellation loader.
  write(f, "verify.json", verify_packet(f, "verify_profile", 1_060_000))
  action_packet.load(f.p, f.root, "verify.json", fx.observed())
  |> should.equal(Error("action_packet_invalid"))
  // A verify record wrapped in the cancellation envelope presented here.
  write(
    f,
    "wrapped.json",
    envelope(
      "uos.telegram.action-packet.v1",
      "recovery_json",
      verify_action.encode_parts(f.intent, 1_060_000, fx.verify_binding()),
      fx.receipts(f.intent, "verify_profile", profile.roster(f.p)),
    ),
  )
  load(f, "wrapped.json") |> should.equal(Error(packet.invalid_error))
  // The verify schema around a cancellation-kind intent.
  let assert Ok(cancel_intent) =
    action.new(
      f.binding,
      verify_action.target_for(
        "uos/example",
        fx.verify_binding(),
        fx.worker,
        fx.lease_until_ns,
      ),
      fx.window(),
      "Operator requested verification of telegram-core",
      string.repeat("b", 64),
    )
  write(
    f,
    "cancelkind.json",
    envelope(
      packet.expected_schema,
      "record_json",
      verify_action.encode_parts(cancel_intent, 1_060_000, fx.verify_binding()),
      fx.receipts(cancel_intent, "cancel_job_lease", profile.roster(f.p)),
    ),
  )
  load(f, "cancelkind.json") |> should.equal(Error(packet.invalid_error))
}

pub fn tampered_oversize_and_foreign_binding_packets_are_refused_test() {
  let f = fixture("tamper")
  let good = verify_packet(f, "verify_profile", 1_060_000)
  write(f, "tampered.json", string.replace(good, "1060000", "1060001"))
  load(f, "tampered.json") |> should.equal(Error(packet.invalid_error))
  write(f, "big.json", good <> string.repeat(" ", 70_000))
  load(f, "big.json") |> should.equal(Error(packet.invalid_error))
  // A binding whose worker is not the profile context's worker.
  let foreign = action.Binding(..f.binding, worker: "someone-else")
  let assert Ok(intent) =
    action.new_kind(
      action.VerifyProfile,
      foreign,
      verify_action.target_for(
        "uos/example",
        fx.verify_binding(),
        fx.worker,
        fx.lease_until_ns,
      ),
      fx.window(),
      "Operator requested verification of telegram-core",
      string.repeat("b", 64),
    )
  write(
    f,
    "foreign.json",
    envelope(
      packet.expected_schema,
      "record_json",
      verify_action.encode_parts(intent, 1_060_000, fx.verify_binding()),
      fx.receipts(intent, "verify_profile", profile.roster(f.p)),
    ),
  )
  load(f, "foreign.json") |> should.equal(Error(packet.invalid_error))
  // No receipts at all.
  write(
    f,
    "none.json",
    envelope(
      packet.expected_schema,
      "record_json",
      verify_action.encode_parts(f.intent, 1_060_000, fx.verify_binding()),
      [],
    ),
  )
  load(f, "none.json") |> should.equal(Error(packet.invalid_error))
  // Missing file.
  load(f, "absent.json") |> should.equal(Error(packet.invalid_error))
  let _ = list.length([cancel.Cancel])
  let _ = result.is_ok(Ok(Nil))
  Nil
}
