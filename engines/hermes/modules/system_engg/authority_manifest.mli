type authority_class =
  | Normative | Implementation_authority | Release_support
  | Reference_oracle | Context

type semantic_scope =
  | Kerml_1_0 | Sysml_2_0 | Systems_modeling_api_1_0
  | Oml_2_13_0 | Oml_development | Sysml_release_overlay
  | Sysml_oml_202407 | Open_caesar_collateral
  | Incose_mbse_context | Arcadia_capella_method
  | Openmbee_collaboration | Opense_cookbook_models
  | Mbse_context

type disposition =
  | Exact of Source_artifact.expected
  | Unavailable_observed of { locator : Uri.t; observed_at : string; reason : string }
  | Rejected_by_policy of { locator : Uri.t; reason : string }

type entry
type denominator_lock = {
  id : string;
  expected_digest : string;
}
type t

type coverage = {
  admitted : int;
  unavailable : int;
  rejected : int;
}

type readiness_error =
  | Missing_core_scope of semantic_scope
  | Core_not_admitted of semantic_scope
  | Empty_manifest_error

val entry :
  id:Source_artifact.Id.t -> title:string -> class_:authority_class ->
  scope:semantic_scope -> authoritative_for:string list ->
  license:License_policy.t -> disposition:disposition ->
  (entry, License_policy.error list) result

val validate : entries:entry list -> denominators:denominator_lock list ->
  (t, string list) result

val classification_complete : t -> bool
val acquisition_coverage : t -> coverage
val authority_ready : t -> (unit, readiness_error list) result
val digest : t -> Source_artifact.Sha256.t
val entries : t -> entry list
val id : entry -> Source_artifact.Id.t
val disposition : entry -> disposition