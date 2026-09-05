(** Source-only mainline carrier classification. *)

type disposition = Track | Sanitize_and_track | Digest_only | Exclude

type artifact_class =
  | Source
  | Deterministic_evolution_projection
  | Evidence_digest
  | Credential
  | Authentication_header
  | Cache
  | Session
  | Trust_record
  | Machine_id
  | Raw_database
  | Sidecar
  | Build_tree
  | Browser_runtime_media
  | Private_agent_state

type observation = {
  artifact : artifact_class;
  requested : disposition;
  size_bytes : int;
  deterministic : bool;
  allowlisted_projection : bool;
  public_identity : string;
}

type refusal =
  | Class_excluded
  | Projection_not_allowlisted
  | Nondeterministic_projection
  | Disposition_escalation
  | Invalid_size
  | Artifact_too_large
  | Identity_too_long
  | Closure_too_large
  | Closure_bytes_exceeded
  | Duplicate_identity

type admission = Admitted of disposition | Refused of refusal

val max_artifact_bytes : int
val max_closure_entries : int
val default_disposition : artifact_class -> disposition
val admit : observation -> admission

(** Returns only [Track] and [Sanitize_and_track] observations. Digest-only
    evidence and excluded runtime state never become source carriers. *)
val source_only_closure : observation list -> (observation list, refusal) result

(** The private value is deliberately absent from the safe projection. *)
val redacted_identity : public_identity:string -> private_value:string -> string
val source_digest : string
