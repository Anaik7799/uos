import cepaf_gleam/harness/telegram_lifecycle_adapter as lifecycle
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
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

fn with_store(test_fn: fn(transport.LocalConfiguration, String) -> a) -> a {
  let dir = "/tmp/uos_writer_registration_test_" <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let db_path = dir <> "/telegram.sqlite3"
  let config = transport.reviewed_local_configuration(
    "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe",
    "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab",
    "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe",
    "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e",
    db_path)
  let value = test_fn(config, db_path)
  let _ = simplifile.delete(dir)
  value
}

fn registration_for(proof: store.FreshWriterStore) -> codec.WriterRegistration {
  codec.WriterRegistration(..registration(),
    store_incarnation_id: store.fresh_writer_store_incarnation(proof))
}

pub fn fresh_proof_requires_actual_creation_and_identity_test() {
  use config, db_path <- with_store
  lifecycle.compute_store_incarnation(db_path) |> should.equal(Error("store_file_not_found"))
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  let assert Ok(actual) = lifecycle.compute_store_incarnation(db_path)
  store.fresh_writer_store_incarnation(proof) |> should.equal(actual)
  let assert Ok(#(generation, rows)) = store.read_keys(config, [
    codec.bot_identity_key(), codec.watermark_key(), codec.writer_registration_key()])
  generation |> should.equal(1)
  list.each(rows, fn(row) { row.exists |> should.be_false })
}

pub fn new_writer_bootstrap_commits_all_metadata_together_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  let r = registration_for(proof)
  store.finish_new_writer_store(proof, r) |> should.equal(Ok(2))
  let assert Ok(#(generation, rows)) = store.read_keys(config, [
    codec.bot_identity_key(), codec.watermark_key(), codec.writer_registration_key()])
  generation |> should.equal(2)
  list.each(rows, fn(row) { row.exists |> should.be_true row.version |> should.equal(1) })
  let assert Ok(row) = list.find(rows, fn(row) {row.key == codec.writer_registration_key()})
  let assert Ok(raw) = codec.decode_canonical_base64(row.canonical_value_base64)
  codec.decode_writer_registration(raw) |> should.equal(Ok(r))
  let assert Ok(bot) = list.find(rows, fn(row) {row.key == codec.bot_identity_key()})
  let assert Ok(bot_raw) = codec.decode_canonical_base64(bot.canonical_value_base64)
  codec.decode_bot_identity_value(bot_raw) |> should.equal(Ok(123))
  let assert Ok(watermark) = store.read_watermark(config)
  watermark.0 |> should.equal(ledger.Watermark(0))
}

pub fn duplicate_new_writer_refused_without_store_mutation_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  store.finish_new_writer_store(proof, registration_for(proof)) |> should.equal(Ok(2))
  let before = store.read_keys(config, [codec.writer_registration_key()])
  store.begin_new_writer_store(config, 123)
  |> should.equal(Error(store.StoreBackendError("db_already_exists")))
  store.read_keys(config, [codec.writer_registration_key()]) |> should.equal(before)
}

pub fn legacy_store_cannot_be_claimed_as_fresh_writer_test() {
  use config, _ <- with_store
  store.initialize_store(config, 123) |> should.equal(Ok(2))
  let before = store.read_keys(config, [codec.writer_registration_key()])
  store.begin_new_writer_store(config, 123)
  |> should.equal(Error(store.StoreBackendError("db_already_exists")))
  store.read_keys(config, [codec.writer_registration_key()]) |> should.equal(before)
  let assert Ok(#(_, [row])) = before
  row.exists |> should.be_false
}

pub fn invalid_bot_does_not_create_store_test() {
  use config, db_path <- with_store
  store.begin_new_writer_store(config, 0) |> should.be_error
  simplifile.file_info(db_path) |> should.equal(Error(simplifile.Enoent))
  store.begin_new_writer_store(config, 123) |> should.be_ok
}

pub fn invalid_registration_keeps_incomplete_store_and_same_proof_can_finish_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  let r = registration_for(proof)
  list.each([
    codec.WriterRegistration(..r, service_epoch: 2),
    codec.WriterRegistration(..r, bot_id: 124),
    codec.WriterRegistration(..r, store_incarnation_id: string.repeat("c", 64)),
    codec.WriterRegistration(..r, control_digest: "bad"),
  ], fn(bad) { store.finish_new_writer_store(proof, bad) |> should.be_error })
  let assert Ok(#(1, [row])) = store.read_keys(config, [codec.writer_registration_key()])
  row.exists |> should.be_false
  store.finish_new_writer_store(proof, r) |> should.equal(Ok(2))
}

pub fn partially_initialized_store_is_not_fresh_writer_proof_test() {
  use config, _ <- with_store
  let assert Ok(response) = transport.exchange(config,
    codec.encode_initialize_new_command(123, None))
  codec.decode_initialize_new_response(response) |> should.equal(Ok(1))
  store.begin_new_writer_store(config, 123)
  |> should.equal(Error(store.StoreBackendError("db_already_exists")))
  let assert Ok(#(generation, rows)) = store.read_keys(config, [
    codec.bot_identity_key(), codec.watermark_key(), codec.writer_registration_key()])
  generation |> should.equal(1)
  list.each(rows, fn(row) { row.exists |> should.be_false })
}

pub fn legacy_completion_cannot_be_promoted_using_retained_fresh_proof_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  store.initialize_store(config, 123) |> should.equal(Ok(2))
  store.finish_new_writer_store(proof, registration_for(proof)) |> should.be_error
  let assert Ok(#(2, [row])) = store.read_keys(config, [codec.writer_registration_key()])
  row.exists |> should.be_false
}

pub fn copied_proof_cannot_replace_committed_registration_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  let r = registration_for(proof)
  store.finish_new_writer_store(proof, r) |> should.equal(Ok(2))
  // Exact storage operation replay returns its receipt, never a new live permit.
  store.finish_new_writer_store(proof, r) |> should.equal(Ok(2))
  store.finish_new_writer_store(proof,
    codec.WriterRegistration(..r, instance_token: string.repeat("e", 64)))
  |> should.be_error
  let assert Ok(#(2, [row])) = store.read_keys(config, [codec.writer_registration_key()])
  let assert Ok(raw) = codec.decode_canonical_base64(row.canonical_value_base64)
  codec.decode_writer_registration(raw) |> should.equal(Ok(r))
}

pub fn replaced_file_refuses_old_creation_proof_test() {
  use config, db_path <- with_store
  let assert Ok(old_proof) = store.begin_new_writer_store(config, 123)
  let assert Ok(_) = simplifile.rename(db_path, db_path <> ".old")
  let assert Ok(new_proof) = store.begin_new_writer_store(config, 123)
  should.be_true(store.fresh_writer_store_incarnation(old_proof) != store.fresh_writer_store_incarnation(new_proof))
  store.finish_new_writer_store(old_proof, registration_for(old_proof))
  |> should.equal(Error(store.StoreInvariantError("fresh_writer_incarnation_mismatch")))
  store.finish_new_writer_store(new_proof, registration_for(new_proof)) |> should.equal(Ok(2))
}

pub fn concurrent_fresh_start_has_exactly_one_winner_test() {
  use config, _ <- with_store
  let ready = process.new_subject()
  let results = process.new_subject()
  list.each([1, 2], fn(_) {
    let _ = process.spawn_unlinked(fn() {
      let go = process.new_subject()
      process.send(ready, go)
      case process.receive(go, 2000) {
        Error(_) -> Nil
        Ok(Nil) -> process.send(results, store.begin_new_writer_store(config, 123))
      }
    })
  })
  let assert Ok(first) = process.receive(ready, 2000)
  let assert Ok(second) = process.receive(ready, 2000)
  process.send(first, Nil)
  process.send(second, Nil)
  let assert Ok(a) = process.receive(results, 5000)
  let assert Ok(b) = process.receive(results, 5000)
  let wins = list.filter_map([a, b], fn(x) { x })
  let losses = list.filter([a, b], fn(x) {
    x == Error(store.StoreBackendError("db_already_exists"))
  })
  list.length(wins) |> should.equal(1)
  list.length(losses) |> should.equal(1)
  let assert [proof] = wins
  let winner = registration_for(proof)
  store.finish_new_writer_store(proof, winner) |> should.equal(Ok(2))
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

pub fn writer_start_is_consumed_once_and_duplicate_does_not_mutate_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  let r = registration_for(proof)
  store.finish_new_writer_store(proof, r) |> should.equal(Ok(2))
  store.consume_writer_start(config, r) |> should.equal(Ok(3))
  let before = store.read_keys(config, ["meta/writer_start"])
  store.consume_writer_start(config, r)
  |> should.equal(Error(store.StoreInvariantError("writer_start_already_consumed")))
  store.read_keys(config, ["meta/writer_start"]) |> should.equal(before)
  let assert Ok(#(3, [row])) = before
  let assert Ok(raw) = codec.decode_canonical_base64(row.canonical_value_base64)
  codec.decode_writer_registration(raw) |> should.equal(Ok(r))
}

pub fn writer_start_rejects_changed_registration_and_wrong_incarnation_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  let r = registration_for(proof)
  store.finish_new_writer_store(proof, r) |> should.equal(Ok(2))
  list.each([
    codec.WriterRegistration(..r, bot_id: 124),
    codec.WriterRegistration(..r, service_epoch: 2),
    codec.WriterRegistration(..r, instance_token: string.repeat("e", 64)),
    codec.WriterRegistration(..r, unit_invocation_id: string.repeat("e", 32)),
    codec.WriterRegistration(..r, control_digest: string.repeat("e", 64)),
  ], fn(changed) {
    store.consume_writer_start(config, changed)
    |> should.equal(Error(store.StoreInvariantError("writer_start_registration_mismatch")))
  })
  store.consume_writer_start(config,
    codec.WriterRegistration(..r, store_incarnation_id: string.repeat("e", 64)))
  |> should.equal(Error(store.StoreInvariantError("writer_start_incarnation_mismatch")))
  let assert Ok(#(2, [row])) = store.read_keys(config, ["meta/writer_start"])
  row.exists |> should.be_false
  store.consume_writer_start(config, r) |> should.equal(Ok(3))
}

pub fn legacy_store_without_writer_cannot_consume_start_test() {
  use config, db_path <- with_store
  store.initialize_store(config, 123) |> should.equal(Ok(2))
  let assert Ok(incarnation) = lifecycle.compute_store_incarnation(db_path)
  store.consume_writer_start(config,
    codec.WriterRegistration(..registration(), store_incarnation_id: incarnation))
  |> should.equal(Error(store.StoreInvariantError("writer_start_missing_writer_row")))
  let assert Ok(#(2, [row])) = store.read_keys(config, ["meta/writer_start"])
  row.exists |> should.be_false
}

pub fn concurrent_writer_start_has_one_success_and_one_explicit_refusal_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  let r = registration_for(proof)
  store.finish_new_writer_store(proof, r) |> should.equal(Ok(2))
  let ready = process.new_subject()
  let results = process.new_subject()
  list.each([1, 2], fn(_) {
    let _ = process.spawn_unlinked(fn() {
      let go = process.new_subject()
      process.send(ready, go)
      case process.receive(go, 2000) {
        Error(_) -> Nil
        Ok(Nil) -> process.send(results, store.consume_writer_start(config, r))
      }
    })
  })
  let assert Ok(first) = process.receive(ready, 2000)
  let assert Ok(second) = process.receive(ready, 2000)
  process.send(first, Nil)
  process.send(second, Nil)
  let assert Ok(a) = process.receive(results, 5000)
  let assert Ok(b) = process.receive(results, 5000)
  list.length(list.filter([a, b], fn(x) { x == Ok(3) })) |> should.equal(1)
  let allowed = [
    Error(store.StoreInvariantError("writer_start_already_consumed")),
    Error(store.StoreInvariantError("writer_start_replay_not_admission")),
    Error(store.StoreBackendError("stale_generation")),
    Error(store.StoreBackendError("db_locked")),
  ]
  list.length(list.filter([a, b], fn(x) { list.contains(allowed, x) })) |> should.equal(1)
  let assert Ok(#(3, [row])) = store.read_keys(config, ["meta/writer_start"])
  row.version |> should.equal(1)
}

fn replace_writer_fixture(
  config: transport.LocalConfiguration,
  next: codec.WriterRegistration,
) -> Int {
  let assert Ok(#(generation, [row])) = store.read_keys(config, [codec.writer_registration_key()])
  let assert Ok(raw) = codec.encode_writer_registration(next)
  let operation = "test-writer-transition-" <> int.to_string(next.service_epoch)
  let reads = [codec.ReadSetAssertion(row.key, row.version, row.sha256)]
  let changes = [codec.Change(row.key, row.version, row.sha256, codec.encode_canonical_base64(raw))]
  let delta = codec.ReservationDelta(0, 0)
  let summary = "{\"test_only\":true}"
  let digest = codec.compute_apply_digest(next.bot_id, operation, generation, reads, changes, delta, summary)
  let request = codec.encode_apply_command(next.bot_id, operation, digest, generation,
    reads, changes, delta, summary, None)
  let assert Ok(response) = transport.exchange(config, request)
  let assert codec.DecodedApplySuccess(result) = codec.decode_apply_response_discriminated(response)
  result.receipt.generation
}

pub fn writer_start_accepts_only_next_registered_epoch_once_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  let previous = registration_for(proof)
  store.finish_new_writer_store(proof, previous) |> should.equal(Ok(2))
  store.consume_writer_start(config, previous) |> should.equal(Ok(3))
  // Test-only persisted transition; this does not prove live cleanup/admission.
  let next = codec.WriterRegistration(..previous, service_epoch: 2,
    instance_token: string.repeat("e", 64), unit_invocation_id: string.repeat("e", 32),
    control_digest: string.repeat("f", 64))
  replace_writer_fixture(config, next) |> should.equal(4)
  store.consume_writer_start(config, previous)
  |> should.equal(Error(store.StoreInvariantError("writer_start_registration_mismatch")))
  store.consume_writer_start(config, next) |> should.equal(Ok(5))
  store.consume_writer_start(config, next)
  |> should.equal(Error(store.StoreInvariantError("writer_start_already_consumed")))
}

pub fn writer_start_rejects_skipped_epoch_and_reused_instance_or_unit_test() {
  list.each([0, 1, 2, 3], fn(case_id) {
    use config, _ <- with_store
    let assert Ok(proof) = store.begin_new_writer_store(config, 123)
    let previous = registration_for(proof)
    store.finish_new_writer_store(proof, previous) |> should.equal(Ok(2))
    store.consume_writer_start(config, previous) |> should.equal(Ok(3))
    let valid = codec.WriterRegistration(..previous, service_epoch: 2,
      instance_token: string.repeat("e", 64), unit_invocation_id: string.repeat("e", 32))
    let invalid = case case_id {
      0 -> codec.WriterRegistration(..valid, service_epoch: 3)
      1 -> codec.WriterRegistration(..valid, instance_token: previous.instance_token)
      2 -> codec.WriterRegistration(..valid, unit_invocation_id: previous.unit_invocation_id)
      _ -> codec.WriterRegistration(..valid, service_epoch: 1)
    }
    replace_writer_fixture(config, invalid) |> should.equal(4)
    store.consume_writer_start(config, invalid)
    |> should.equal(Error(store.StoreInvariantError("writer_start_invalid_successor")))
    let assert Ok(#(4, [row])) = store.read_keys(config, ["meta/writer_start"])
    let assert Ok(raw) = codec.decode_row_value(row)
    codec.decode_writer_registration(raw) |> should.equal(Ok(previous))
  })
}

pub fn writer_start_requires_persisted_predecessor_for_later_epoch_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  let previous = registration_for(proof)
  store.finish_new_writer_store(proof, previous) |> should.equal(Ok(2))
  let next = codec.WriterRegistration(..previous, service_epoch: 2,
    instance_token: string.repeat("e", 64), unit_invocation_id: string.repeat("e", 32))
  replace_writer_fixture(config, next) |> should.equal(3)
  store.consume_writer_start(config, next)
  |> should.equal(Error(store.StoreInvariantError("writer_start_predecessor_missing")))
}

pub fn incomplete_store_cannot_consume_writer_start_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  store.consume_writer_start(config, registration_for(proof))
  |> should.equal(Error(store.StoreInvariantError("writer_start_missing_bot_row")))
  let assert Ok(#(1, [row])) = store.read_keys(config, ["meta/writer_start"])
  row.exists |> should.be_false
}

pub fn writer_start_classifies_epoch_regression_as_invalid_successor_test() {
  use config, _ <- with_store
  let assert Ok(proof) = store.begin_new_writer_store(config, 123)
  let first = registration_for(proof)
  store.finish_new_writer_store(proof, first) |> should.equal(Ok(2))
  store.consume_writer_start(config, first) |> should.equal(Ok(3))
  let second = codec.WriterRegistration(..first, service_epoch: 2,
    instance_token: string.repeat("e", 64), unit_invocation_id: string.repeat("e", 32))
  replace_writer_fixture(config, second) |> should.equal(4)
  store.consume_writer_start(config, second) |> should.equal(Ok(5))
  let assert Ok(#(5, [row])) = store.read_keys(config, ["meta/writer_start"])
  row.version |> should.equal(2)
  replace_writer_fixture(config, first) |> should.equal(6)
  store.consume_writer_start(config, first)
  |> should.equal(Error(store.StoreInvariantError("writer_start_invalid_successor")))
  let assert Ok(#(6, [after])) = store.read_keys(config, ["meta/writer_start"])
  after |> should.equal(row)
}
