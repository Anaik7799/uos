import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/erlang/process
import gleam/option.{None}
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

fn registration() -> codec.WriterRegistration {
  codec.WriterRegistration(123, 1, string.repeat("a", 64), string.repeat("b", 64),
    string.repeat("c", 64), string.repeat("d", 32), 1_792_838_000_000_000)
}

pub fn registration_golden_wire_test() {
  let r = registration()
  let assert Ok(raw) = codec.encode_writer_registration(r)
  let expected = "{\"schema\":\"uos.telegram-writer-registration.v1\",\"bot_id\":123,\"service_epoch\":1,\"instance_token\":\""
    <> string.repeat("a", 64) <> "\",\"control_digest\":\""
    <> string.repeat("b", 64) <> "\",\"store_incarnation_id\":\""
    <> string.repeat("c", 64) <> "\",\"unit_invocation_id\":\""
    <> string.repeat("d", 32) <> "\",\"registered_at_us\":1792838000000000}"
  raw |> should.equal(expected)
  codec.decode_writer_registration(expected) |> should.equal(Ok(r))
}

pub fn registration_rejects_duplicate_unknown_whitespace_and_reordered_fields_test() {
  let assert Ok(raw) = codec.encode_writer_registration(registration())
  list.each([
    " " <> raw,
    raw <> "\n",
    string.replace(raw, "{", "{\"extra\":true,"),
    string.replace(raw, "{", "{\"bot_id\":123,"),
    string.replace(raw, "\"bot_id\":123,\"service_epoch\":1", "\"service_epoch\":1,\"bot_id\":123"),
  ], fn(value) { codec.decode_writer_registration(value) |> should.be_error })
}

pub fn registration_rejects_invalid_identity_bounds_test() {
  let r = registration()
  list.each([
    codec.WriterRegistration(..r, bot_id: 0),
    codec.WriterRegistration(..r, bot_id: -1),
    codec.WriterRegistration(..r, bot_id: 4_503_599_627_370_496),
    codec.WriterRegistration(..r, service_epoch: 0),
    codec.WriterRegistration(..r, service_epoch: 2_147_483_648),
    codec.WriterRegistration(..r, registered_at_us: 0),
    codec.WriterRegistration(..r, registered_at_us: 9_007_199_254_740_992),
    codec.WriterRegistration(..r, instance_token: string.repeat("A", 64)),
    codec.WriterRegistration(..r, instance_token: string.repeat("a", 63)),
    codec.WriterRegistration(..r, control_digest: string.repeat("z", 64)),
    codec.WriterRegistration(..r, store_incarnation_id: string.repeat("C", 64)),
    codec.WriterRegistration(..r, unit_invocation_id: string.repeat("D", 32)),
    codec.WriterRegistration(..r, unit_invocation_id: string.repeat("d", 31)),
  ], fn(value) { codec.encode_writer_registration(value) |> should.be_error })
}

pub fn registration_rejects_schema_types_and_payload_bounds_test() {
  let assert Ok(raw) = codec.encode_writer_registration(registration())
  list.each([
    "", "null", "[]", "{",
    string.repeat(" ", 98_305),
    string.replace(raw, ".v1", ".v2"),
    string.replace(raw, "\"bot_id\":123", "\"bot_id\":\"123\""),
    string.replace(raw, "\"bot_id\":123", "\"bot_id\":123.0"),
    string.replace(raw, "\"service_epoch\":1", "\"service_epoch\":0"),
    string.replace(raw, "\"registered_at_us\":1792838000000000", "\"registered_at_us\":null"),
  ], fn(value) { codec.decode_writer_registration(value) |> should.be_error })
}

pub fn registration_accepts_numeric_upper_bounds_test() {
  let r = codec.WriterRegistration(..registration(),
    bot_id: 4_503_599_627_370_495, service_epoch: 2_147_483_647,
    registered_at_us: 9_007_199_254_740_991)
  let assert Ok(raw) = codec.encode_writer_registration(r)
  codec.decode_writer_registration(raw) |> should.equal(Ok(r))
}

fn with_store(test_fn: fn(transport.LocalConfiguration) -> a) -> a {
  let dir = "/tmp/uos_writer_registration_test_" <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let config = transport.reviewed_local_configuration(
    "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe",
    "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab",
    "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe",
    "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e",
    dir <> "/telegram.sqlite3")
  let value = test_fn(config)
  let _ = simplifile.delete(dir)
  value
}

pub fn new_writer_bootstrap_commits_all_metadata_together_test() {
  use config <- with_store
  store.initialize_new_registered_store(config, registration()) |> should.equal(Ok(2))
  let assert Ok(#(generation, rows)) = store.read_keys(config, [
    codec.bot_identity_key(), codec.watermark_key(), codec.writer_registration_key()])
  generation |> should.equal(2)
  list.length(rows) |> should.equal(3)
  list.each(rows, fn(row) { row.exists |> should.be_true row.version |> should.equal(1) })
  let assert Ok(row) = list.find(rows, fn(row) {row.key == codec.writer_registration_key()})
  let assert Ok(raw) = codec.decode_canonical_base64(row.canonical_value_base64)
  codec.decode_writer_registration(raw) |> should.equal(Ok(registration()))
}

pub fn duplicate_new_writer_refused_without_store_mutation_test() {
  use config <- with_store
  store.initialize_new_registered_store(config, registration()) |> should.equal(Ok(2))
  let before = store.read_keys(config, [codec.writer_registration_key()])
  store.initialize_new_registered_store(config, registration())
  |> should.equal(Error(store.StoreBackendError("db_already_exists")))
  store.initialize_new_registered_store(config,
    codec.WriterRegistration(..registration(), instance_token: string.repeat("e", 64)))
  |> should.equal(Error(store.StoreBackendError("db_already_exists")))
  store.read_keys(config, [codec.writer_registration_key()]) |> should.equal(before)
}

pub fn legacy_store_cannot_be_claimed_as_fresh_writer_test() {
  use config <- with_store
  store.initialize_store(config, 123) |> should.equal(Ok(2))
  let before = store.read_keys(config, [codec.writer_registration_key()])
  store.initialize_new_registered_store(config, registration())
  |> should.equal(Error(store.StoreBackendError("db_already_exists")))
  store.read_keys(config, [codec.writer_registration_key()]) |> should.equal(before)
  let assert Ok(#(_, [row])) = before
  row.exists |> should.be_false
}

pub fn invalid_registration_does_not_create_store_test() {
  use config <- with_store
  store.initialize_new_registered_store(config,
    codec.WriterRegistration(..registration(), service_epoch: 2))
  |> should.equal(Error(store.StoreInvariantError("first_writer_requires_epoch_one")))
  store.initialize_new_registered_store(config,
    codec.WriterRegistration(..registration(), control_digest: "bad"))
  |> should.be_error
  store.initialize_new_registered_store(config, registration()) |> should.equal(Ok(2))
}

pub fn partially_initialized_store_is_not_fresh_writer_proof_test() {
  use config <- with_store
  let assert Ok(response) = transport.exchange(config,
    codec.encode_initialize_new_command(123, None))
  codec.decode_initialize_new_response(response) |> should.equal(Ok(1))
  store.initialize_new_registered_store(config, registration())
  |> should.equal(Error(store.StoreBackendError("db_already_exists")))
  let assert Ok(#(generation, rows)) = store.read_keys(config, [
    codec.bot_identity_key(), codec.watermark_key(), codec.writer_registration_key()])
  generation |> should.equal(1)
  list.each(rows, fn(row) { row.exists |> should.be_false })
}

pub fn concurrent_fresh_start_has_exactly_one_winner_test() {
  use config <- with_store
  let ready = process.new_subject()
  let results = process.new_subject()
  list.each(["a", "e"], fn(token) {
    let _ = process.spawn_unlinked(fn() {
      let go = process.new_subject()
      process.send(ready, go)
      case process.receive(go, 2000) {
        Error(_) -> Nil
        Ok(Nil) -> {
          let r = codec.WriterRegistration(..registration(), instance_token: string.repeat(token, 64))
          process.send(results, #(r, store.initialize_new_registered_store(config, r)))
        }
      }
    })
  })
  let assert Ok(first) = process.receive(ready, 2000)
  let assert Ok(second) = process.receive(ready, 2000)
  process.send(first, Nil)
  process.send(second, Nil)
  let assert Ok(a) = process.receive(results, 5000)
  let assert Ok(b) = process.receive(results, 5000)
  let outcomes = [a, b]
  let wins = list.filter(outcomes, fn(x) { x.1 == Ok(2) })
  let losses = list.filter(outcomes, fn(x) {
    x.1 == Error(store.StoreBackendError("db_already_exists"))
  })
  list.length(wins) |> should.equal(1)
  list.length(losses) |> should.equal(1)
  let assert [#(winner, _)] = wins
  let assert Ok(#(2, [row])) = store.read_keys(config, [codec.writer_registration_key()])
  let assert Ok(raw) = codec.decode_canonical_base64(row.canonical_value_base64)
  codec.decode_writer_registration(raw) |> should.equal(Ok(winner))
}

pub fn registration_decode_rejects_hostile_canonical_fields_test() {
  let assert Ok(raw) = codec.encode_writer_registration(registration())
  list.each([
    #("\"bot_id\":123", "\"bot_id\":0"),
    #("\"bot_id\":123", "\"bot_id\":4503599627370496"),
    #("\"service_epoch\":1", "\"service_epoch\":2147483648"),
    #("\"registered_at_us\":1792838000000000", "\"registered_at_us\":0"),
    #("\"registered_at_us\":1792838000000000", "\"registered_at_us\":9007199254740992"),
    #(string.repeat("a", 64), string.repeat("A", 64)),
    #(string.repeat("a", 64), string.repeat("a", 65)),
    #(string.repeat("b", 64), string.repeat("z", 64)),
    #(string.repeat("c", 64), string.repeat("c", 63)),
    #(string.repeat("d", 32), string.repeat("d", 33)),
    #(string.repeat("d", 32), string.repeat("d", 31)),
    #(string.repeat("a", 64), "\\u0061" <> string.repeat("a", 63)),
    #("\"service_epoch\":1,", ""),
    #("}", ",\"bot_id\":123}"),
  ], fn(replacement) {
    codec.decode_writer_registration(string.replace(raw, replacement.0, replacement.1))
    |> should.be_error
  })
  codec.decode_writer_registration(string.repeat(" ", 98_304)) |> should.be_error
}

pub fn registration_accepts_lower_bounds_test() {
  let r = codec.WriterRegistration(..registration(), bot_id: 1, registered_at_us: 1)
  let assert Ok(raw) = codec.encode_writer_registration(r)
  codec.decode_writer_registration(raw) |> should.equal(Ok(r))
}
