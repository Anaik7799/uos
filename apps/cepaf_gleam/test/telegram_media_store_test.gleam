//// Media design T4: content-addressed store, retention horizon and ceiling.
//// Every law runs against a real directory (TMPDIR or /tmp), removed at the end
//// of the test. SHA-256 expectations use the published "abc" vector, so the
//// oracle is not the module under test.

import cepaf_gleam/harness/telegram_media_ref as ref
import cepaf_gleam/harness/telegram_media_store as store
import envoy
import gleam/bit_array
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

@external(erlang, "erlang", "system_time")
fn system_time() -> Int

const abc_sha = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

const retention = 60_000

const t0 = 1_000_000

fn tmp_base() -> String {
  case envoy.get("TMPDIR") {
    Ok(dir) if dir != "" -> dir
    _ -> "/tmp"
  }
}

fn fresh_root() -> String {
  let root =
    tmp_base()
    <> "/uos-media-store-test-"
    <> int.to_string(int.absolute_value(unique_integer()))
    <> "-"
    <> int.to_string(system_time())
  // never inherit files left by an earlier failed run
  let _ = simplifile.delete(root)
  let assert Ok(_) = simplifile.create_directory_all(root)
  root
}

fn policy(root: String) -> store.Policy {
  store.Policy(
    root: root,
    base: "media",
    retention_ms: retention,
    total_ceiling_bytes: 1000,
  )
}

fn with_store(body: fn(store.Policy, String) -> Nil) -> Nil {
  let root = fresh_root()
  body(policy(root), root)
  let _ = simplifile.delete(root)
  Nil
}

fn abc() -> BitArray {
  bit_array.from_string("abc")
}

fn put_abc(p: store.Policy, now: Int, usage: Int) -> store.Outcome {
  store.put(p, ref.Photo, "uniq-1", abc(), abc_sha, now, usage)
}

fn bin_path(root: String) -> String {
  root <> "/media/ba/" <> abc_sha <> ".bin"
}

fn index_path(root: String) -> String {
  root <> "/media/ba/" <> abc_sha <> ".json"
}

fn written(outcome: store.Outcome) -> store.Stored {
  case outcome {
    store.Written(s) -> s
    other -> panic as { "expected Written, got " <> describe(other) }
  }
}

fn describe(outcome: store.Outcome) -> String {
  case outcome {
    store.Written(_) -> "Written"
    store.AlreadyStored(_) -> "AlreadyStored"
    store.Refused(r) -> "Refused(" <> r <> ")"
  }
}

fn refused(outcome: store.Outcome) -> String {
  case outcome {
    store.Refused(r) -> r
    other -> "NOT REFUSED: " <> describe(other)
  }
}

// ------------------------------------------------------------- round trip

pub fn round_trip_test() {
  use p, root <- with_store
  let stored = written(put_abc(p, t0, 0))
  stored.sha256_hex |> should.equal(abc_sha)
  stored.bytes |> should.equal(3)
  stored.stored_at_ms |> should.equal(t0)
  stored.expires_at_ms |> should.equal(t0 + retention)
  stored.file_unique_id |> should.equal("uniq-1")
  stored.kind |> should.equal(ref.Photo)
  let assert Ok(#(got, bytes)) = store.get(p, abc_sha, t0 + 1)
  got |> should.equal(stored)
  bytes |> should.equal(abc())
  store.usage(p) |> should.equal(Ok(3))
  simplifile.read_bits(bin_path(root)) |> should.equal(Ok(abc()))
}

pub fn index_record_has_fixed_key_order_test() {
  use p, root <- with_store
  let _ = written(put_abc(p, t0, 0))
  let assert Ok(text) = simplifile.read(index_path(root))
  text
  |> should.equal(
    "{\"schema\":\"uos.telegram.media-object.v1\",\"sha256_hex\":\""
    <> abc_sha
    <> "\",\"bytes\":3,\"kind\":\"photo\",\"file_unique_id\":\"uniq-1\","
    <> "\"stored_at_ms\":1000000,\"expires_at_ms\":1060000}",
  )
}

pub fn uppercase_expected_digest_is_accepted_test() {
  use p, _ <- with_store
  store.put(p, ref.Document, "u", abc(), string.uppercase(abc_sha), t0, 0)
  |> written
  |> fn(s) { s.sha256_hex }
  |> should.equal(abc_sha)
}

// -------------------------------------------------------------- idempotence

pub fn second_put_is_already_stored_and_writes_nothing_test() {
  use p, root <- with_store
  let first = written(put_abc(p, t0, 0))
  let assert Ok(index_before) = simplifile.read(index_path(root))
  // A later clock and a different sender string must not rewrite anything.
  let second = store.put(p, ref.Photo, "other-id", abc(), abc_sha, t0 + 5000, 3)
  second |> should.equal(store.AlreadyStored(first))
  simplifile.read(index_path(root)) |> should.equal(Ok(index_before))
  simplifile.read_bits(bin_path(root)) |> should.equal(Ok(abc()))
  store.usage(p) |> should.equal(Ok(3))
}

pub fn already_stored_is_reported_even_at_the_ceiling_test() {
  use p, _ <- with_store
  let first = written(put_abc(p, t0, 0))
  // The caller's measured usage already includes the object: no false refusal.
  put_abc(p, t0 + 1, 1000) |> should.equal(store.AlreadyStored(first))
}

pub fn interrupted_put_orphan_bin_is_adopted_test() {
  use p, root <- with_store
  let _ = written(put_abc(p, t0, 0))
  let assert Ok(_) = simplifile.delete(index_path(root))
  // bin without index: a retry completes the index and leaves the bytes alone
  let again = written(put_abc(p, t0 + 10, 0))
  again.stored_at_ms |> should.equal(t0 + 10)
  simplifile.read_bits(bin_path(root)) |> should.equal(Ok(abc()))
  store.get(p, abc_sha, t0 + 11) |> result.is_ok |> should.be_true
}

pub fn wrong_bytes_at_the_digest_name_are_replaced_test() {
  use p, root <- with_store
  let _ = written(put_abc(p, t0, 0))
  let assert Ok(_) = simplifile.delete(index_path(root))
  let assert Ok(_) = simplifile.write_bits(bin_path(root), <<"zzz":utf8>>)
  let _ = written(put_abc(p, t0 + 10, 0))
  simplifile.read_bits(bin_path(root)) |> should.equal(Ok(abc()))
  store.get(p, abc_sha, t0 + 11) |> result.is_ok |> should.be_true
}

// --------------------------------------------------- review fixes (M-01..M-11)

fn seed_shard(root: String) -> Nil {
  let assert Ok(_) = simplifile.create_directory_all(root <> "/media/ba")
  Nil
}

pub fn truncated_bin_retry_succeeds_test() {
  use p, root <- with_store
  seed_shard(root)
  // the residue of a crash mid-write: a prefix of the bytes at the final name
  let assert Ok(_) = simplifile.write_bits(bin_path(root), <<"ab":utf8>>)
  let stored = written(put_abc(p, t0, 0))
  simplifile.read_bits(bin_path(root)) |> should.equal(Ok(abc()))
  let assert Ok(#(got, bytes)) = store.get(p, abc_sha, t0 + 1)
  got |> should.equal(stored)
  bytes |> should.equal(abc())
  // no temporary file survives a successful put
  let assert Ok(names) = simplifile.read_directory(root <> "/media/ba")
  list.sort(names, string.compare)
  |> should.equal([abc_sha <> ".bin", abc_sha <> ".json"])
}

pub fn empty_bin_retry_succeeds_test() {
  use p, root <- with_store
  seed_shard(root)
  let assert Ok(_) = simplifile.write_bits(bin_path(root), <<>>)
  let _ = written(put_abc(p, t0, 0))
  simplifile.read_bits(bin_path(root)) |> should.equal(Ok(abc()))
}

pub fn re_put_after_expiry_is_not_already_stored_test() {
  use p, _ <- with_store
  let first = written(put_abc(p, t0, 0))
  // before the horizon the same content is still AlreadyStored
  put_abc(p, first.expires_at_ms - 1, 3)
  |> should.equal(store.AlreadyStored(first))
  // at and after the horizon the caller must dispose of it first
  put_abc(p, first.expires_at_ms, 3)
  |> refused
  |> should.equal("expired_present")
  put_abc(p, first.expires_at_ms + 5_000_000, 3)
  |> refused
  |> should.equal("expired_present")
  // the refused re-put changed nothing
  store.expired(p, first.expires_at_ms) |> should.equal(Ok([first]))
}

pub fn index_present_bin_missing_put_refuses_test() {
  use p, root <- with_store
  let _ = written(put_abc(p, t0, 0))
  let assert Ok(_) = simplifile.delete(bin_path(root))
  put_abc(p, t0 + 1, 0)
  |> refused
  |> should.equal("stored_object_unverified:bin_missing")
}

pub fn index_present_bin_wrong_put_refuses_test() {
  use p, root <- with_store
  let _ = written(put_abc(p, t0, 0))
  let assert Ok(_) = simplifile.write_bits(bin_path(root), <<"abd":utf8>>)
  put_abc(p, t0 + 1, 0)
  |> refused
  |> should.equal("stored_object_unverified:bin_hash_mismatch")
  let assert Ok(_) = simplifile.write_bits(bin_path(root), <<"ab":utf8>>)
  put_abc(p, t0 + 1, 0)
  |> refused
  |> should.equal("stored_object_unverified:bin_size_mismatch")
}

pub fn orphan_bin_counted_in_usage_test() {
  use p, root <- with_store
  let orphan = string.repeat("ab", 32)
  let assert Ok(_) = simplifile.create_directory_all(root <> "/media/ab")
  let assert Ok(_) =
    simplifile.write_bits(root <> "/media/ab/" <> orphan <> ".bin", <<
      "0123456789":utf8,
    >>)
  store.usage(p) |> should.equal(Ok(10))
  // a leftover temporary file is disk the ceiling must also see
  let assert Ok(_) =
    simplifile.write_bits(root <> "/media/ab/.tmp-dead", <<"12345":utf8>>)
  store.usage(p) |> should.equal(Ok(15))
}

pub fn usage_takes_the_larger_of_index_and_bin_test() {
  use p, root <- with_store
  let _ = written(put_abc(p, t0, 0))
  store.usage(p) |> should.equal(Ok(3))
  // the index under-reports once the bytes grew
  let assert Ok(_) =
    simplifile.write_bits(bin_path(root), <<"0123456789":utf8>>)
  store.usage(p) |> should.equal(Ok(10))
}

pub fn oversized_unique_id_refused_no_files_test() {
  use p, root <- with_store
  let too_long = string.repeat("x", 129)
  store.put(p, ref.Photo, too_long, abc(), abc_sha, t0, 0)
  |> refused
  |> should.equal("file_unique_id_too_long")
  simplifile.is_directory(root <> "/media") |> should.equal(Ok(False))
  store.usage(p) |> should.equal(Ok(0))
  // exactly 128 bytes is accepted and recorded
  let exact = string.repeat("x", 128)
  let stored = store.put(p, ref.Photo, exact, abc(), abc_sha, t0, 0) |> written
  stored.file_unique_id |> should.equal(exact)
}

pub fn symlinked_base_is_refused_without_mkdir_test() {
  use p, root <- with_store
  let assert Ok(_) = simplifile.create_directory_all(root <> "/elsewhere")
  let assert Ok(_) = simplifile.create_symlink("elsewhere", root <> "/media")
  put_abc(p, t0, 0)
  |> refused
  |> should.equal("write_failed:parent_not_regular_directory")
  // nothing was created through the link
  simplifile.read_directory(root <> "/elsewhere") |> should.equal(Ok([]))
}

pub fn symlinked_shard_is_refused_without_writes_test() {
  use p, root <- with_store
  let assert Ok(_) = simplifile.create_directory_all(root <> "/media")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/elsewhere")
  let assert Ok(_) =
    simplifile.create_symlink("../elsewhere", root <> "/media/ba")
  put_abc(p, t0, 0)
  |> refused
  |> should.equal("write_failed:parent_not_regular_directory")
  simplifile.read_directory(root <> "/elsewhere") |> should.equal(Ok([]))
}

pub fn symlinked_bin_is_not_adopted_test() {
  use p, root <- with_store
  seed_shard(root)
  // a symlink whose target holds exactly the right bytes must still not count
  let assert Ok(_) = simplifile.write_bits(root <> "/outside.bin", abc())
  let assert Ok(_) =
    simplifile.create_symlink("../../outside.bin", bin_path(root))
  put_abc(p, t0, 0)
  |> refused
  |> should.equal("write_failed:bin_not_regular_single_link")
  simplifile.is_file(index_path(root)) |> should.equal(Ok(False))
  let assert Ok(info) = simplifile.link_info(bin_path(root))
  simplifile.file_info_type(info) |> should.equal(simplifile.Symlink)
}

pub fn concurrent_same_digest_put_test() {
  list.each(list.repeat(Nil, 15), fn(_) {
    use p, _ <- with_store
    let results = process.new_subject()
    list.each([1, 2], fn(n) {
      process.spawn(fn() {
        process.send(
          results,
          store.put(
            p,
            ref.Photo,
            "u" <> int.to_string(n),
            abc(),
            abc_sha,
            t0,
            0,
          ),
        )
      })
    })
    let assert Ok(a) = process.receive(results, 5000)
    let assert Ok(b) = process.receive(results, 5000)
    let outcomes = [a, b]
    let wins =
      list.count(outcomes, fn(o) {
        case o {
          store.Written(_) -> True
          _ -> False
        }
      })
    { wins >= 1 } |> should.be_true
    list.each(outcomes, fn(o) {
      case o {
        store.Written(_) | store.AlreadyStored(_) -> Nil
        store.Refused(r) ->
          string.starts_with(r, "write_failed:") |> should.be_true
      }
    })
    // never a poisoned state
    let assert store.AlreadyStored(_) = put_abc(p, t0 + 1, 3)
    store.get(p, abc_sha, t0 + 1) |> result.is_ok |> should.be_true
    store.usage(p) |> should.equal(Ok(3))
  })
}

pub fn expired_reports_errors_test() {
  use p, root <- with_store
  let _ = written(put_abc(p, t0, 0))
  let assert Ok(_) = simplifile.write(index_path(root), "{not json")
  store.expired(p, t0 + 10_000_000) |> should.equal(Error("index_invalid"))
  store.expired(store.Policy(..p, retention_ms: 1), t0)
  |> should.equal(Error("policy_invalid"))
}

pub fn expired_reports_unreadable_store_test() {
  use p, root <- with_store
  // `base` is a plain file: the store cannot be listed, and that is not "empty"
  let assert Ok(_) = simplifile.write(root <> "/media", "not a directory")
  store.expired(p, t0) |> should.equal(Error("store_unavailable"))
  store.usage(p) |> should.equal(Error("store_unavailable"))
}

// ----------------------------------------------------------------- refusals

pub fn digest_mismatch_is_refused_with_no_file_test() {
  use p, root <- with_store
  let wrong = string.repeat("0", 64)
  store.put(p, ref.Photo, "u", abc(), wrong, t0, 0)
  |> refused
  |> should.equal("content_digest_mismatch")
  simplifile.is_directory(root <> "/media") |> should.equal(Ok(False))
  store.usage(p) |> should.equal(Ok(0))
}

pub fn ceiling_is_refused_with_no_file_test() {
  use p, root <- with_store
  put_abc(p, t0, 998) |> refused |> should.equal("ceiling_reached")
  simplifile.is_directory(root <> "/media") |> should.equal(Ok(False))
  store.usage(p) |> should.equal(Ok(0))
}

pub fn ceiling_boundary_is_inclusive_test() {
  use p, _ <- with_store
  // 997 + 3 == 1000: exactly at the ceiling is allowed, one more byte is not.
  let boundary = store.put(p, ref.Photo, "u", abc(), abc_sha, t0, 997)
  boundary |> written |> fn(s) { s.bytes } |> should.equal(3)
  let other = bit_array.from_string("abcd")
  let digest_of_abcd =
    "88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589"
  store.put(p, ref.Photo, "u", other, digest_of_abcd, t0, 997)
  |> refused
  |> should.equal("ceiling_reached")
}

pub fn invalid_policy_is_refused_test() {
  let root = fresh_root()
  let ok = policy(root)
  let bad = [
    store.Policy(..ok, retention_ms: 59_999),
    store.Policy(..ok, total_ceiling_bytes: 0),
    store.Policy(..ok, base: "../escape"),
    store.Policy(..ok, base: "/abs"),
    store.Policy(..ok, base: "a/../b"),
    store.Policy(..ok, base: "a//b"),
    store.Policy(..ok, base: ""),
    store.Policy(..ok, base: "ok/"),
    store.Policy(..ok, root: ""),
  ]
  list.each(bad, fn(p) {
    put_abc(p, t0, 0) |> refused |> should.equal("policy_invalid")
    store.get(p, abc_sha, t0) |> should.equal(Error("policy_invalid"))
    store.usage(p) |> should.equal(Error("policy_invalid"))
    store.object_path(p, abc_sha) |> should.equal(Error("policy_invalid"))
    store.expired(p, t0) |> should.equal(Error("policy_invalid"))
  })
  // nothing was created for any invalid policy
  simplifile.read_directory(root) |> should.equal(Ok([]))
  let _ = simplifile.delete(root)
  Nil
}

pub fn exact_minimum_retention_is_valid_test() {
  use p, _ <- with_store
  store.put(
    store.Policy(..p, retention_ms: 60_000),
    ref.Photo,
    "u",
    abc(),
    abc_sha,
    t0,
    0,
  )
  |> written
  |> fn(s) { s.expires_at_ms }
  |> should.equal(t0 + 60_000)
}

pub fn unsupported_kind_and_negative_usage_are_refused_test() {
  use p, root <- with_store
  store.put(p, ref.Unsupported("poll"), "u", abc(), abc_sha, t0, 0)
  |> refused
  |> should.equal("kind_unsupported")
  put_abc(p, t0, -1) |> refused |> should.equal("usage_invalid")
  simplifile.is_directory(root <> "/media") |> should.equal(Ok(False))
}

pub fn missing_root_is_a_write_failure_not_a_created_root_test() {
  let missing = tmp_base() <> "/uos-media-store-absent-root-no-such-dir"
  let p = policy(missing)
  put_abc(p, t0, 0) |> refused |> should.equal("write_failed:root_unavailable")
  simplifile.is_directory(missing) |> should.equal(Ok(False))
}

// ------------------------------------------------------------------- expiry

pub fn expiry_is_reported_and_never_served_test() {
  use p, _ <- with_store
  let stored = written(put_abc(p, t0, 0))
  let horizon = stored.expires_at_ms
  store.get(p, abc_sha, horizon - 1) |> result.is_ok |> should.be_true
  store.get(p, abc_sha, horizon) |> should.equal(Error("expired"))
  store.get(p, abc_sha, horizon + 1_000_000) |> should.equal(Error("expired"))
  store.expired(p, horizon - 1) |> should.equal(Ok([]))
  store.expired(p, horizon) |> should.equal(Ok([stored]))
  // listing is read-only: the object is still on disk and still counted
  store.usage(p) |> should.equal(Ok(3))
}

// ----------------------------------------------------------------- tamper

pub fn same_length_tamper_is_detected_test() {
  use p, root <- with_store
  let _ = written(put_abc(p, t0, 0))
  let assert Ok(_) = simplifile.write_bits(bin_path(root), <<"abd":utf8>>)
  store.get(p, abc_sha, t0 + 1) |> should.equal(Error("content_tampered"))
}

pub fn different_length_tamper_is_detected_test() {
  use p, root <- with_store
  let _ = written(put_abc(p, t0, 0))
  let assert Ok(_) = simplifile.write_bits(bin_path(root), <<"abcdef":utf8>>)
  store.get(p, abc_sha, t0 + 1) |> should.equal(Error("content_tampered"))
}

pub fn missing_bytes_and_missing_record_are_distinct_test() {
  use p, root <- with_store
  let _ = written(put_abc(p, t0, 0))
  store.get(p, string.repeat("a", 64), t0) |> should.equal(Error("not_found"))
  let assert Ok(_) = simplifile.delete(bin_path(root))
  store.get(p, abc_sha, t0 + 1) |> should.equal(Error("content_missing"))
}

pub fn malformed_index_fails_closed_test() {
  use p, root <- with_store
  let _ = written(put_abc(p, t0, 0))
  let assert Ok(_) = simplifile.write(index_path(root), "{not json")
  store.get(p, abc_sha, t0 + 1) |> should.equal(Error("index_invalid"))
  // an unreadable record must not under-count usage
  store.usage(p) |> should.equal(Error("index_invalid"))
  // and a retry must not clobber it
  put_abc(p, t0 + 2, 0)
  |> refused
  |> should.equal("write_failed:index_invalid")
}

pub fn index_for_a_different_digest_is_rejected_test() {
  use p, root <- with_store
  let stored = written(put_abc(p, t0, 0))
  let forged = store.Stored(..stored, sha256_hex: string.repeat("f", 64))
  let assert Ok(_) =
    simplifile.write(index_path(root), store.encode_record(forged))
  store.get(p, abc_sha, t0 + 1) |> should.equal(Error("index_invalid"))
}

// ---------------------------------------------------- hostile sender strings

pub fn hostile_unique_id_never_names_a_path_test() {
  use p, root <- with_store
  let hostile = "../../etc/passwd\u{0}"
  let stored =
    store.put(p, ref.Document, hostile, abc(), abc_sha, t0, 0) |> written
  stored.file_unique_id |> should.equal(hostile)
  // exactly the digest paths exist; nothing else was created anywhere
  simplifile.read_directory(root) |> should.equal(Ok(["media"]))
  simplifile.read_directory(root <> "/media") |> should.equal(Ok(["ba"]))
  let assert Ok(names) = simplifile.read_directory(root <> "/media/ba")
  list.sort(names, string.compare)
  |> should.equal([abc_sha <> ".bin", abc_sha <> ".json"])
  // the hostile string is only a recorded value and survives the round trip
  let assert Ok(#(got, _)) = store.get(p, abc_sha, t0 + 1)
  got.file_unique_id |> should.equal(hostile)
}

// ----------------------------------------------------------------- paths

pub fn object_path_is_digest_named_and_bounded_test() {
  use p, root <- with_store
  // shard directory absent before the first put: checked_path refuses
  store.object_path(p, abc_sha) |> should.equal(Error("parent_unavailable"))
  let _ = written(put_abc(p, t0, 0))
  store.object_path(p, abc_sha) |> should.equal(Ok(bin_path(root)))
  store.object_path(p, "../../etc/passwd")
  |> should.equal(Error("sha256_invalid"))
  store.object_path(p, string.uppercase(abc_sha))
  |> should.equal(Error("sha256_invalid"))
  store.get(p, "../x", t0) |> should.equal(Error("sha256_invalid"))
}

pub fn usage_sums_index_recorded_bytes_test() {
  use p, _ <- with_store
  let _ = written(put_abc(p, t0, 0))
  let other = bit_array.from_string("abcd")
  let _ =
    store.put(
      p,
      ref.Audio,
      "u2",
      other,
      "88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589",
      t0,
      3,
    )
    |> written
  store.usage(p) |> should.equal(Ok(7))
}
