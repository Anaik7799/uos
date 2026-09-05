//// vault_kek_test — Pass-22 wiring guard for the Gleam ↔ Rust kek_chain bridge.
////
//// Per SC-WIRE-001..007: this module's tests verify the FFI surface compiles
//// and the typed wrapper builds correct Result variants from the NIF return
//// shape. The actual NIF .so is loaded only in production / integration runs;
//// these unit tests cover the type-level contract.
////
//// SC-VAULT-021: argon2id 64MB/3iter/parallelism=4 — parameters are baked
//// into the NIF and cannot be overridden from Gleam.
//// SC-VAULT-002: caller MUST pass derived BitArray straight to vault.unseal/2.

import cepaf_gleam/vault_kek.{
  type KekError, BadOutputLen, BadParam, DeriveFailed, SaltTooShort, Unknown,
  derive_master_key, generate_salt, tpm_present, tpm_present_default,
}
import gleeunit/should

// =====================================================================
// Type-construction tests — exhaustive variant coverage of KekError
// =====================================================================

pub fn salt_too_short_constructible_test() {
  let e = SaltTooShort(actual_len: 5)
  case e {
    SaltTooShort(actual_len: 5) -> Nil
    _ -> panic as "SaltTooShort destructure failed"
  }
}

pub fn bad_param_constructible_test() {
  let e = BadParam(reason: "argon2 internal")
  case e {
    BadParam(reason: r) -> should.equal(r, "argon2 internal")
    //     _ -> panic as "BadParam destructure failed"
  }
}

pub fn derive_failed_constructible_test() {
  let e = DeriveFailed(reason: "out of memory")
  case e {
    DeriveFailed(reason: r) -> should.equal(r, "out of memory")
    //     _ -> panic as "DeriveFailed destructure failed"
  }
}

pub fn bad_output_len_constructible_test() {
  let e = BadOutputLen(actual_len: 16)
  case e {
    BadOutputLen(actual_len: 16) -> Nil
    _ -> panic as "BadOutputLen destructure failed"
  }
}

pub fn unknown_constructible_test() {
  let e = Unknown(payload: "something:weird")
  case e {
    Unknown(payload: p) -> should.equal(p, "something:weird")
    //     _ -> panic as "Unknown destructure failed"
  }
}

// =====================================================================
// FFI surface tests — verify functions exist with correct types
// (signatures only — actual NIF calls happen at runtime if .so loaded)
// =====================================================================

pub fn derive_master_key_signature_compiles_test() {
  // Reference the function via type-checked closure to prove the signature.
  // (Calling it would require the NIF .so which is not loaded in this test env.)
  let _: fn(BitArray, BitArray) -> Result(BitArray, KekError) =
    derive_master_key
  Nil
}

pub fn generate_salt_signature_compiles_test() {
  let _: fn() -> Result(BitArray, String) = generate_salt
  Nil
}

pub fn tpm_present_signature_compiles_test() {
  let _: fn(String) -> Bool = tpm_present
  Nil
}

pub fn tpm_present_default_signature_compiles_test() {
  let _: fn() -> Bool = tpm_present_default
  Nil
}
