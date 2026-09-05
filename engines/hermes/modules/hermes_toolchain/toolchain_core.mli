(** Pure derivation and fail-closed supply-chain validation for the workspace
    toolchain gate.  This module performs no filesystem, process, network, or
    package-manager operation; callers pass observations in explicitly. *)

val strip_comments : string -> string
val tokens_of : string -> string list
val stanza_bodies : key:string -> deep:bool -> string -> string list
val libraries_of_dune : string -> string list
val pps_of_dune : string -> string list
val defined_in_dune : string -> string list
val external_libraries : used:string list -> defined:string list -> string list

(** Closed refusal set for the approval-verification provider.  Manifest drift
    is deliberately one state: the manifest is an exact frozen release record,
    not a permissive configuration language. *)
type approval_crypto_refusal =
  | Approval_crypto_dependency_not_derived
  | Approval_crypto_version_unavailable
  | Approval_crypto_version_mismatch of {
      expected : string;
      observed : string;
    }
  | Approval_crypto_manifest_missing
  | Approval_crypto_manifest_mismatch
  | Approval_crypto_self_test_unavailable
  | Approval_crypto_self_test_failed

(** Admit only the exact [mirage-crypto-ec] 2.2.0 dependency derived from the
    live Dune denominator, the byte-exact checked release-provenance manifest,
    and a present successful verification-only provider self-test.

    The installed version, manifest bytes, and self-test result are
    observations supplied by the effectful shell.  Unknown evidence is a
    refusal and multiple independent refusals are accumulated in deterministic
    dependency/version/manifest/self-test order. *)
val validate_approval_crypto_supply_chain :
  derived_packages:string list ->
  installed_version:string option ->
  provenance_manifest:string option ->
  provider_self_test:bool option ->
  (unit, approval_crypto_refusal list) result

val string_of_approval_crypto_refusal : approval_crypto_refusal -> string
