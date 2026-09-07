//// FerrisKey NIF load-evidence test (SC-FERRISKEY-NIF-001, SC-WIRE-001).
////
//// Runtime-truth pattern (mirrors test/mcp_runtime_truth_test.gleam and
//// cepaf_gleam/mcp/tools.nif_runtime_available/c3i_nif:runtime_loaded):
//// determines, on the host actually running this suite, whether
//// priv/ferriskey_nif.so is present, then exercises the branch that is
//// true and prints which branch it took. It must pass on every host.
////
//// `test/ferriskey_nif_wiring_test.gleam` and
//// `test/ferriskey_rbac_wiring_test.gleam` only check that the typed
//// wrapper's function references compile (they never invoke a NIF at
//// runtime), so neither one is evidence that the artifact actually loads
//// or that `ping`/`db_init` actually work. This file is that evidence.
////
//// Load-semantics finding (documented, not assumed — see
//// src/ferriskey_load_evidence_ffi.erl's header for the full write-up and
//// the empirical verification method): src/ferriskey_nif.erl's `init/0`
//// (lines 76-85) returns `erlang:load_nif/2`'s raw result straight from
//// `-on_load`, unlike src/c3i_nif.erl's `init/0` (lines 27-39), which
//// always returns `ok` and separately records success/failure in a
//// `persistent_term` (`c3i_nif:runtime_loaded/0`). Per Erlang `on_load`
//// semantics, when an `-on_load` function does not return `ok`, the
//// WHOLE MODULE fails to load — so on a host where
//// `priv/ferriskey_nif.so` is absent, calling
//// `ferriskey_nif:ferriskey_ping/0` directly raises `error:undef`, not a
//// clean `{error, "nif_not_loaded"}` stub return (that stub body is only
//// reachable if the module loaded, which it did not). The "absent" branch
//// below therefore goes through `ferriskey_load_evidence_ffi:safe_ping/0`,
//// a tiny exception-catching FFI boundary, instead of calling the typed
//// `ferriskey_nif.ping()` wrapper unconditionally — so this test is
//// honest about what actually happens on an artifact-absent host rather
//// than about what the stub bodies alone would suggest.

import cepaf_gleam/auth/ferriskey_nif as fk
import envoy
import gleam/io
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

/// Mirrors ferriskey_nif:init/0's own PrivDir/Lib path resolution
/// (src/ferriskey_nif.erl:76-85) so this test agrees with the loader about
/// exactly which file must exist. See src/ferriskey_load_evidence_ffi.erl.
@external(erlang, "ferriskey_load_evidence_ffi", "resolved_so_path")
fn resolved_so_path() -> String

/// Crash-safe probe of ferriskey_nif:ferriskey_ping/0 — see module header
/// and src/ferriskey_load_evidence_ffi.erl for why this exists instead of
/// calling fk.ping() unconditionally.
@external(erlang, "ferriskey_load_evidence_ffi", "safe_ping")
fn safe_ping() -> Result(String, String)

/// Scratch root for the db_init round trip: env UOS_FK_TEST_ROOT if set and
/// non-empty, else build/fk-test/ — never priv/ or data/.
fn scratch_root() -> String {
  case envoy.get("UOS_FK_TEST_ROOT") {
    Ok(root) if root != "" -> root
    _ -> "build/fk-test"
  }
}

pub fn ferriskey_nif_load_evidence_test() {
  let so_path = resolved_so_path()
  let artifact_present = simplifile.is_file(so_path) == Ok(True)

  case artifact_present {
    True -> assert_present_branch(so_path)
    False -> assert_absent_branch(so_path)
  }
}

/// priv/ferriskey_nif.so is present: the typed binding MUST succeed. A
/// failure here is real evidence and must not be papered over — this
/// function panics loudly (with the exact error) rather than weakening the
/// assertion, per the task's fail-closed reporting contract.
fn assert_present_branch(so_path: String) -> Nil {
  case fk.ping() {
    Ok(fk.PingResponse(runtime_ok: runtime_ok, ..)) ->
      runtime_ok |> should.be_true
    Error(e) ->
      panic as {
        "priv/ferriskey_nif.so is present at "
        <> so_path
        <> " but ferriskey_nif.ping() failed — real evidence, not weakened: "
        <> string.inspect(e)
      }
  }

  let root = scratch_root()
  let assert Ok(_) = simplifile.create_directory_all(root)
  let db_path = root <> "/ferriskey-load-evidence.db"

  case fk.db_init(db_path) {
    Ok(fk.DbInitResponse(..)) -> Nil
    Error(e) ->
      panic as {
        "ferriskey_nif.db_init(\""
        <> db_path
        <> "\") failed: "
        <> string.inspect(e)
      }
  }

  // Cheap round trip: create one realm and read it back (SC-IAM-003
  // exhaustive mapping). Skipped no further than this — user/group/role
  // creation needs more than the realm create/get functions to assert
  // cleanly, per the task's "skip if it needs more than realm create/get".
  let realm_name = "fk-load-evidence-realm"
  case
    fk.realm_create(db_path, realm_name, "https://evidence.local/realm", "{}")
  {
    Ok(fk.Realm(id: realm_id, name: got_name, ..)) -> {
      got_name |> should.equal(realm_name)
      case fk.realm_get(db_path, realm_id) {
        Ok(fk.RealmFound(realm: fk.Realm(id: found_id, ..))) ->
          found_id |> should.equal(realm_id)
        Ok(fk.RealmNotFound) ->
          panic as "ferriskey_nif.realm_get returned RealmNotFound immediately after realm_create"
        Error(e) ->
          panic as {
            "ferriskey_nif.realm_get after realm_create failed: "
            <> string.inspect(e)
          }
      }
    }
    Error(e) ->
      panic as { "ferriskey_nif.realm_create failed: " <> string.inspect(e) }
  }

  io.println("ferriskey load evidence: artifact present, ping ok, db_init ok")
}

/// priv/ferriskey_nif.so is absent: the module fails -on_load in its
/// entirety (see module header), so this asserts the fail-closed outcome
/// through the crash-safe FFI boundary rather than crashing the suite.
fn assert_absent_branch(so_path: String) -> Nil {
  case safe_ping() {
    Error(_reason) -> Nil
    Ok(json) ->
      panic as {
        "priv/ferriskey_nif.so is absent at "
        <> so_path
        <> " but the ferriskey_nif module unexpectedly answered ping "
        <> "successfully: "
        <> json
      }
  }

  io.println("ferriskey load evidence: artifact absent, fail-closed verified")
}

/// Pure, read-only check that the pin file exists and its first
/// whitespace-delimited field is a 64-hex-character digest. Does not
/// compute the artifact's digest — that is the provenance record's job
/// (governance/sources/20260907-1330-ferriskey-nif-source-ingestion.json).
pub fn ferriskey_nif_pin_file_present_and_well_formed_test() {
  let assert Ok(contents) = simplifile.read("priv/ferriskey_nif.sha256")
  let assert Ok(first_field) =
    contents
    |> string.split(on: " ")
    |> list.first

  string.length(first_field) |> should.equal(64)
  first_field
  |> string.to_graphemes
  |> list.all(is_hex_digit)
  |> should.be_true
}

fn is_hex_digit(grapheme: String) -> Bool {
  case grapheme {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "a" | "b" | "c" | "d" | "e" | "f" -> True
    "A" | "B" | "C" | "D" | "E" | "F" -> True
    _ -> False
  }
}
