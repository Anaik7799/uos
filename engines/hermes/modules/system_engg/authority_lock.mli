type locked_status = Admitted | Unavailable_observed | Rejected_by_policy

type locked_entry = {
  manifest_digest : Source_artifact.Sha256.t;
  authority_id : Source_artifact.Id.t;
  resolved_revision : string option;
  content_digest : Source_artifact.Sha256.t option;
  license_policy_digest : Source_artifact.Sha256.t;
  status : locked_status;
  reason : string option;
}

type t = locked_entry list

val decode_strict : Yojson.Safe.t -> (t, string list) result
val encode_canonical : t -> Yojson.Safe.t
val validate_against : manifest:Authority_manifest.t -> t ->
  (unit, string list) result