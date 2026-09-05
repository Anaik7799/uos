(** Pure normalization of injected secret-detector findings.

    This module never reads a file or runs a detector. Locations are structured
    redacted coordinates; no API accepts a path, matched text, or secret bytes.
    Errors are closed constructors and therefore cannot echo sensitive input. *)

type digest
type digest_error = Invalid_digest

val digest : string -> (digest, digest_error) result
val digest_to_hex : digest -> string

type detector_authority

(** The identity and ruleset digest jointly identify the detector authority. *)
val detector_authority :
  identity:Jj_id.Executable.t -> ruleset:digest -> detector_authority

type category =
  | Credential
  | Authentication_header
  | Private_key
  | Access_token
  | Session_material
  | Credential_bearing_remote
  | Other_sensitive

type confidence = Possible | Probable | Certain

type location_scope =
  | Source_object
  | Patch_payload
  | Description_payload
  | Operation_log_payload
  | Remote_payload

type redacted_location
type location_error = Negative_ordinal | Ordinal_limit_exceeded

(** [ordinal] is a bounded occurrence number, not a byte/line offset or path. *)
val redacted_location :
  scope:location_scope -> ordinal:int ->
  (redacted_location, location_error) result

type finding

val finding :
  detector:detector_authority ->
  category:category ->
  location:redacted_location ->
  confidence:confidence ->
  evidence:digest ->
  finding

type scan
type scan_error = Too_many_findings | Duplicate_finding

(** Findings are sorted by their complete safe projection. Input order cannot
    alter the scan identity. An exact duplicate is refused, not collapsed. *)
val scan : findings:finding list -> (scan, scan_error) result
val finding_count : scan -> int
val canonical_digest : scan -> digest
val safe_summary : scan -> string
val source_digest : string

module For_test : sig
  type mutation =
    | Detector_identity
    | Detector_ruleset
    | Category
    | Location_scope
    | Location_ordinal
    | Confidence
    | Evidence_digest

  val finding_digest : finding -> string
  val finding_digest_with_mutation : finding -> mutation -> string
end
