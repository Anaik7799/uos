//// Trusted loader for /verify profiles. Turns pinned bytes into a Profile only
//// after the raw profile digest equals the caller's pin, the bytes are the
//// contract's canonical encoding, and every gate executable and input on disk
//// hashes to the digest the profile names. No execution or authority here:
//// a Loaded value says the artifacts matched when observed, nothing more.
//// Artifacts can change after load; `recheck` must run again immediately
//// before any execution.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_verify_contract as v
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const max_artifact_bytes = 268_435_456

/// Where a gate's executable and input live, relative to the loader root.
pub type Locator {
  Locator(gate_id: String, executable: String, input: String)
}

pub opaque type Loaded {
  Loaded(profile: v.Profile, root: String, locators: List(Locator))
}

@external(erlang, "telegram_verify_loader_ffi", "file_sha256")
fn file_sha256(path: String, max_bytes: Int) -> Result(String, String)

fn hex64(value: String) -> Bool {
  string.byte_size(value) == 64
  && string.to_graphemes(value)
  |> list.all(fn(c) { string.contains("0123456789abcdef", c) })
}

fn gate_decoder() {
  use id <- decode.field("id", decode.string)
  use executable <- decode.field("executable_sha256", decode.string)
  use input <- decode.field("input_sha256", decode.string)
  use timeout <- decode.field("timeout_ms", decode.int)
  decode.success(v.Gate(id, executable, input, timeout))
}

fn profile_decoder() {
  use schema <- decode.field("schema", decode.string)
  use id <- decode.field("profile_id", decode.string)
  use candidate <- decode.field("candidate", decode.string)
  use closure <- decode.field("source_closure_sha256", decode.string)
  use gates <- decode.field("required_gates", decode.list(gate_decoder()))
  use timeout <- decode.field("total_timeout_ms", decode.int)
  decode.success(#(schema, id, candidate, closure, gates, timeout))
}

/// Decodes bytes already known to hash to the pin. Requiring the canonical
/// encoding rejects extra fields, reordering and duplicate keys without a
/// second parser: only one byte string encodes a given Profile.
pub fn decode_pinned(raw: String, pin: String) -> Result(v.Profile, String) {
  use _ <- result.try(case hex64(pin) {
    True -> Ok(Nil)
    False -> Error("profile_pin_invalid")
  })
  use _ <- result.try(case files.digest(raw) == pin {
    True -> Ok(Nil)
    False -> Error("profile_pin_mismatch")
  })
  use #(schema, id, candidate, closure, gates, timeout) <- result.try(
    json.parse(raw, profile_decoder())
    |> result.map_error(fn(_) { "profile_malformed" }),
  )
  use _ <- result.try(case schema == "uos.telegram.verify-profile.v1" {
    True -> Ok(Nil)
    False -> Error("profile_schema")
  })
  use p <- result.try(v.profile(id, candidate, closure, gates, timeout))
  case v.canonical_json(p) == raw && v.profile_digest(p) == pin {
    True -> Ok(p)
    False -> Error("profile_not_canonical")
  }
}

fn verify_artifact(
  root: String,
  relative: String,
  want: String,
  what: String,
  gate: String,
) -> Result(Nil, String) {
  use path <- result.try(
    files.checked_path(root, relative)
    |> result.map_error(fn(r) { what <> "_path:" <> gate <> ":" <> r }),
  )
  use got <- result.try(
    file_sha256(path, max_artifact_bytes)
    |> result.map_error(fn(r) { what <> ":" <> gate <> ":" <> r }),
  )
  case got == want {
    True -> Ok(Nil)
    False -> Error(what <> "_pin_mismatch:" <> gate)
  }
}

fn verify_all(
  p: v.Profile,
  root: String,
  locators: List(Locator),
) -> Result(Nil, String) {
  list.try_each(v.required_gates(p), fn(gate) {
    use loc <- result.try(
      list.find(locators, fn(l) { l.gate_id == gate.id })
      |> result.replace_error("locator_missing:" <> gate.id),
    )
    use _ <- result.try(verify_artifact(
      root,
      loc.executable,
      gate.executable_sha256,
      "executable",
      gate.id,
    ))
    verify_artifact(root, loc.input, gate.input_sha256, "input", gate.id)
  })
}

pub fn load(
  root: String,
  profile_path: String,
  pin: String,
  locators: List(Locator),
) -> Result(Loaded, String) {
  use raw <- result.try(
    files.read(root, profile_path)
    |> result.map_error(fn(r) { "profile_unavailable:" <> r }),
  )
  use p <- result.try(decode_pinned(raw, pin))
  let gate_ids =
    list.map(v.required_gates(p), fn(g) { g.id }) |> list.sort(string.compare)
  let locator_ids =
    list.map(locators, fn(l) { l.gate_id }) |> list.sort(string.compare)
  use _ <- result.try(case gate_ids == locator_ids {
    True -> Ok(Nil)
    False -> Error("locator_set_mismatch")
  })
  use _ <- result.try(verify_all(p, root, locators))
  Ok(Loaded(p, root, locators))
}

/// Re-hashes every artifact. Call immediately before executing a gate.
pub fn recheck(l: Loaded) -> Result(Nil, String) {
  verify_all(l.profile, l.root, l.locators)
}

pub fn profile(l: Loaded) -> v.Profile {
  l.profile
}

pub fn locator(l: Loaded, gate_id: String) -> Result(Locator, Nil) {
  list.find(l.locators, fn(x) { x.gate_id == gate_id })
}
