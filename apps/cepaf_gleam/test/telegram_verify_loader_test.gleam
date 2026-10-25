import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_loader as loader
import cepaf_gleam/harness/telegram_verify_reservation as reservation
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/string
import gleeunit/should
import simplifile

fn fresh_root(tag: String) -> String {
  let root =
    "/tmp/uos_tg_verify_loader_test_"
    <> tag
    <> "_"
    <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(root <> "/gates")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/reservations")
  root
}

fn put(root: String, relative: String, content: String) -> Nil {
  let assert Ok(_) = simplifile.write(root <> "/" <> relative, content)
  Nil
}

fn locators() {
  [
    loader.Locator("build", "gates/build.exe", "gates/build.input"),
    loader.Locator("unit", "gates/unit.exe", "gates/unit.input"),
  ]
}

/// Writes gate artifacts and their canonical profile; returns the pin.
fn setup(root: String) -> String {
  put(root, "gates/build.exe", "#!build\n")
  put(root, "gates/build.input", "build-input")
  put(root, "gates/unit.exe", "#!unit\n")
  put(root, "gates/unit.input", "unit-input")
  let assert Ok(p) =
    v.profile(
      "telegram-core",
      string.repeat("a", 40),
      string.repeat("b", 64),
      [
        v.Gate(
          "build",
          files.digest("#!build\n"),
          files.digest("build-input"),
          1000,
        ),
        v.Gate(
          "unit",
          files.digest("#!unit\n"),
          files.digest("unit-input"),
          2000,
        ),
      ],
      3000,
    )
  put(root, "profile.json", v.canonical_json(p))
  v.profile_digest(p)
}

fn load(root: String, pin: String) {
  loader.load(root, "profile.json", pin, locators())
}

pub fn loads_pinned_canonical_profile_test() {
  let root = fresh_root("ok")
  let pin = setup(root)
  let assert Ok(l) = load(root, pin)
  v.profile_digest(loader.profile(l)) |> should.equal(pin)
  loader.locator(l, "unit")
  |> should.equal(
    Ok(loader.Locator("unit", "gates/unit.exe", "gates/unit.input")),
  )
  loader.recheck(l) |> should.equal(Ok(Nil))
}

pub fn raw_digest_matches_independent_sha256_test() {
  // The pin is the SHA-256 of the exact profile bytes, computed here with
  // crypto directly rather than through files.digest.
  let root = fresh_root("sha")
  let pin = setup(root)
  let assert Ok(raw) = simplifile.read(root <> "/profile.json")
  crypto.hash(crypto.Sha256, bit_array.from_string(raw))
  |> bit_array.base16_encode
  |> string.lowercase
  |> should.equal(pin)
}

pub fn wrong_pin_refused_test() {
  let root = fresh_root("pin")
  let _ = setup(root)
  load(root, string.repeat("0", 64))
  |> should.equal(Error("profile_pin_mismatch"))
  load(root, "not-a-pin") |> should.equal(Error("profile_pin_invalid"))
}

pub fn non_canonical_bytes_refused_even_when_pinned_test() {
  // The attacker controls the pin's preimage here: bytes with an extra field
  // hash to their own digest, yet must not load.
  let root = fresh_root("canon")
  let pin = setup(root)
  let assert Ok(raw) = simplifile.read(root <> "/profile.json")
  let padded = string.replace(raw, "{\"schema\"", "{\"extra\":1,\"schema\"")
  put(root, "profile.json", padded)
  load(root, files.digest(padded))
  |> should.equal(Error("profile_not_canonical"))
  load(root, pin) |> should.equal(Error("profile_pin_mismatch"))
}

pub fn tampered_executable_refused_test() {
  let root = fresh_root("exe")
  let pin = setup(root)
  put(root, "gates/build.exe", "#!evil\n")
  load(root, pin) |> should.equal(Error("executable_pin_mismatch:build"))
}

pub fn tampered_input_refused_test() {
  let root = fresh_root("input")
  let pin = setup(root)
  put(root, "gates/unit.input", "other")
  load(root, pin) |> should.equal(Error("input_pin_mismatch:unit"))
}

pub fn symlinked_and_hardlinked_artifacts_refused_test() {
  let root = fresh_root("link")
  let pin = setup(root)
  put(root, "gates/real.exe", "#!build\n")
  let assert Ok(_) = simplifile.delete(root <> "/gates/build.exe")
  let assert Ok(_) =
    simplifile.create_symlink(
      root <> "/gates/real.exe",
      root <> "/gates/build.exe",
    )
  load(root, pin)
  |> should.equal(Error("executable:build:artifact_not_regular_single_link"))
  let assert Ok(_) = simplifile.delete(root <> "/gates/build.exe")
  let assert Ok(_) =
    simplifile.create_link(
      root <> "/gates/real.exe",
      root <> "/gates/build.exe",
    )
  load(root, pin)
  |> should.equal(Error("executable:build:artifact_not_regular_single_link"))
}

pub fn missing_artifact_and_escaping_path_refused_test() {
  let root = fresh_root("missing")
  let pin = setup(root)
  let assert Ok(_) = simplifile.delete(root <> "/gates/unit.exe")
  load(root, pin) |> should.equal(Error("executable:unit:artifact_unavailable"))
  loader.load(root, "profile.json", pin, [
    loader.Locator("build", "../build.exe", "gates/build.input"),
    loader.Locator("unit", "gates/unit.exe", "gates/unit.input"),
  ])
  |> should.equal(Error("executable_path:build:relative_path_required"))
}

pub fn locator_set_must_equal_gate_set_test() {
  let root = fresh_root("loc")
  let pin = setup(root)
  loader.load(root, "profile.json", pin, [
    loader.Locator("build", "gates/build.exe", "gates/build.input"),
  ])
  |> should.equal(Error("locator_set_mismatch"))
  loader.load(root, "profile.json", pin, [
    loader.Locator("extra", "gates/build.exe", "gates/build.input"),
    ..locators()
  ])
  |> should.equal(Error("locator_set_mismatch"))
}

pub fn recheck_detects_change_after_load_test() {
  let root = fresh_root("recheck")
  let pin = setup(root)
  let assert Ok(l) = load(root, pin)
  put(root, "gates/unit.exe", "#!swapped\n")
  loader.recheck(l) |> should.equal(Error("executable_pin_mismatch:unit"))
}

fn binding(root: String, request: String, attempt: Int) -> v.Binding {
  let assert Ok(l) = load(root, setup(root))
  let assert Ok(b) = v.binding(loader.profile(l), request, attempt)
  b
}

pub fn reservation_is_unique_per_inbox_request_test() {
  let root = fresh_root("reserve")
  let b = binding(root, "bot999/inbox8001", 1)
  reservation.reserve(root, "reservations", b)
  |> should.equal(Ok(reservation.Created(b)))
  reservation.reserve(root, "reservations", b)
  |> should.equal(Ok(reservation.Existing(b)))
  // A retry that would mint a different job for the same inbox message.
  let retry = v.Binding(..b, attempt: 2)
  reservation.reserve(root, "reservations", retry)
  |> should.equal(Error("reservation_conflict"))
  reservation.load(root, "reservations", "bot999/inbox8001")
  |> should.equal(Ok(b))
  let other = binding(root, "bot999/inbox8002", 1)
  reservation.reserve(root, "reservations", other)
  |> should.equal(Ok(reservation.Created(other)))
}

pub fn reservation_load_refuses_missing_and_altered_test() {
  let root = fresh_root("reserve_load")
  let b = binding(root, "bot999/inbox9001", 1)
  reservation.load(root, "reservations", b.request_id)
  |> should.equal(Error("reservation_unavailable:file_unavailable"))
  let assert Ok(_) = reservation.reserve(root, "reservations", b)
  let stored = "reservations/" <> files.digest(b.request_id) <> ".json"
  put(
    root,
    stored,
    string.replace(reservation.encode(b), "\"attempt\":1", "\"attempt\":1 "),
  )
  reservation.load(root, "reservations", b.request_id)
  |> should.equal(Error("reservation_not_canonical"))
  // An altered file is a conflict for reserve too, never silently replaced.
  reservation.reserve(root, "reservations", b)
  |> should.equal(Error("reservation_conflict"))
}

pub fn reservation_refuses_request_stored_under_another_key_test() {
  let root = fresh_root("reserve_key")
  let a = binding(root, "bot999/inbox7001", 1)
  let b = binding(root, "bot999/inbox7002", 1)
  put(
    root,
    "reservations/" <> files.digest(b.request_id) <> ".json",
    reservation.encode(a),
  )
  reservation.load(root, "reservations", b.request_id)
  |> should.equal(Error("reservation_not_canonical"))
}
