import cepaf_gleam/ecology/cutover_protocol as p
import cepaf_gleam/ecology/cutover_transport as wire
import cepaf_gleam/harness/value as v
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

const digest = "sha256:1111111111111111111111111111111111111111111111111111111111111111"

const other = "sha256:2222222222222222222222222222222222222222222222222222222222222222"

fn binding() {
  wire.Binding(digest, digest, digest, 7, 0)
}

fn raw_value() {
  v.Object([
    #("schema_version", v.Integer(1)),
    #("status", v.Text("ok")),
    #("code", v.Text("ok")),
    #("transaction_id", v.Text(digest)),
    #("candidate", v.Text(digest)),
    #("manifest", v.Text(digest)),
    #("epoch", v.Integer(7)),
    #("generation", v.Integer(0)),
    #("operation", v.Text("stage")),
    #("prepared", v.Boolean(True)),
    #("count", v.Integer(14)),
    #("images", v.Array(list.repeat(v.Text("old"), 14))),
    #("records", v.Array([])),
  ])
}

fn encode(value) {
  value |> v.encode |> json.to_string
}

fn parse(value) {
  wire.decode_reply(encode(value), binding(), "stage")
}

pub fn initial_generation_zero_and_prefixed_bindings_encode_test() {
  let assert Ok(raw) =
    wire.request_body(binding(), "inspect", wire.empty_payload())
  string.contains(raw, "\"generation\":0") |> should.be_true
  string.contains(raw, digest) |> should.be_true
  let assert Error(_) =
    wire.request_body(
      wire.Binding(..binding(), epoch: 0),
      "inspect",
      wire.empty_payload(),
    )
  let assert Error(_) =
    wire.request_body(
      wire.Binding(..binding(), generation: -1),
      "inspect",
      wire.empty_payload(),
    )
  let assert Error(_) =
    wire.request_body(
      wire.Binding(..binding(), candidate: "unbound"),
      "inspect",
      wire.empty_payload(),
    )
  let assert Error(_) =
    wire.request_body(binding(), "execute_arbitrary", wire.empty_payload())
}

pub fn exact_reply_binding_and_shape_test() {
  let assert Ok(reply) = parse(raw_value())
  reply.prepared |> should.be_true
  reply.count |> should.equal(14)
  reply.cleanup |> should.equal(wire.Unconfirmed)
  list.each(
    [
      #("transaction_id", v.Text(other)),
      #("candidate", v.Text(other)),
      #("manifest", v.Text(other)),
      #("epoch", v.Integer(8)),
      #("generation", v.Integer(1)),
      #("operation", v.Text("restore_one")),
      #("schema_version", v.Integer(2)),
      #("status", v.Text("accepted")),
      #("count", v.Integer(15)),
      #("prepared", v.Boolean(False)),
      #("images", v.Array(list.repeat(v.Text("ok"), 14))),
    ],
    fn(change) {
      let assert Error(_) = parse(v.set(raw_value(), change.0, change.1))
    },
  )
}

pub fn refusal_cannot_become_a_success_ack_test() {
  wire.decode_reply(
    "{\"schema_version\":1,\"status\":\"hold\",\"code\":\"missing_pin\"}",
    binding(),
    "inspect",
  )
  |> should.equal(Error("NATIVE_REFUSAL:hold:missing_pin"))
  wire.decode_reply(
    "{\"schema_version\":1,\"status\":\"unknown\",\"code\":\"pending\"}",
    binding(),
    "inspect",
  )
  |> should.equal(Error("NATIVE_REFUSAL:unknown:pending"))
  let assert Error(_) =
    wire.decode_reply(
      "{\"schema_version\":1,\"status\":\"ok\",\"code\":\"ok\"}",
      binding(),
      "inspect",
    )
}

pub fn duplicate_keys_extra_fields_prefix_and_size_refuse_test() {
  let raw = encode(raw_value())
  let assert Error(_) =
    wire.decode_reply(
      string.replace(
        raw,
        "\"schema_version\":1",
        "\"schema_version\":1,\"schema_version\":1",
      ),
      binding(),
      "stage",
    )
  let assert Error(_) = parse(v.set(raw_value(), "unexpected", v.Boolean(True)))
  let assert Error(_) =
    wire.decode_reply("warning\n" <> raw, binding(), "stage")
  let assert Error(_) =
    wire.decode_reply(string.repeat(" ", 524_289), binding(), "stage")
}

pub fn all_protocol_command_and_observation_roundtrips_test() {
  list.each(
    [
      p.StageFiles,
      p.FenceReaders,
      p.ReplaceFile(0),
      p.ReplaceFile(14),
      p.RestoreFile(0),
      p.RestoreFile(14),
      p.VerifyCandidate,
      p.VerifyPrevious,
      p.ResumeReaders,
    ],
    fn(command) {
      command
      |> wire.command_value
      |> wire.decode_command
      |> should.equal(Ok(command))
    },
  )
  list.each(
    [
      p.Succeeded,
      p.Failed,
      p.Prepared(digest, 14),
      p.Prepared(other, 15),
      p.Verified(other),
    ],
    fn(observation) {
      observation
      |> wire.observation_value
      |> wire.decode_observation
      |> should.equal(Ok(observation))
    },
  )
  let assert Error(_) =
    wire.decode_command(
      v.Object([#("kind", v.Text("replace_file")), #("index", v.Integer(15))]),
    )
  let assert Error(_) =
    wire.decode_command(
      v.Object([#("kind", v.Text("stage_files")), #("index", v.Integer(0))]),
    )
  let assert Error(_) =
    wire.decode_observation(
      v.Object([
        #("kind", v.Text("verified")),
        #("candidate", v.Text("unbound")),
        #("manifest", v.Null),
        #("physical_count", v.Null),
      ]),
    )
}

pub fn native_file_result_is_not_a_protocol_verification_ack_test() {
  let native =
    wire.LogRecord(
      "verify_new",
      7,
      16,
      v.Object([
        #("index", v.Null),
        #("files_verified", v.Boolean(True)),
        #("prepared", v.Boolean(True)),
        #("count", v.Integer(14)),
      ]),
      "result",
    )
  wire.record_ack(binding(), native)
  |> should.equal(Error("NOT_PROTOCOL_ACK_RECORD"))
  let checkpoint =
    wire.LogRecord(
      "checkpoint_result",
      7,
      16,
      wire.result_payload(p.VerifyCandidate, p.Verified(digest)),
      "result",
    )
  let assert Ok(ack) = wire.record_ack(binding(), checkpoint)
  ack.command |> should.equal(p.VerifyCandidate)
  ack.generation |> should.equal(16)
  ack.observation |> should.equal(p.Verified(digest))
}

pub fn log_cardinality_and_unknown_operation_refuse_test() {
  let native =
    v.Object([
      #("operation", v.Text("invented")),
      #("epoch", v.Integer(7)),
      #("generation", v.Integer(0)),
      #("payload", v.Object([])),
      #("status", v.Text("result")),
    ])
  let assert Error(_) = parse(v.set(raw_value(), "records", v.Array([native])))
  let assert Error(_) =
    parse(v.set(raw_value(), "records", v.Array(list.repeat(native, 257))))
}
