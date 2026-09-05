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

let max_artifact_bytes = 16 * 1024 * 1024
let max_closure_entries = 256
let max_closure_bytes = 64 * 1024 * 1024
let max_identity_bytes = 512

let default_disposition = function
  | Source -> Track
  | Deterministic_evolution_projection -> Sanitize_and_track
  | Evidence_digest -> Digest_only
  | Credential | Authentication_header | Cache | Session | Trust_record
  | Machine_id | Raw_database | Sidecar | Build_tree | Browser_runtime_media
  | Private_agent_state -> Exclude

let rank = function Track -> 3 | Sanitize_and_track -> 2 | Digest_only -> 1
  | Exclude -> 0

let is_private artifact = default_disposition artifact = Exclude

let admit observation =
  if observation.size_bytes < 0 then Refused Invalid_size
  else if observation.size_bytes > max_artifact_bytes then
    Refused Artifact_too_large
  else if String.length observation.public_identity > max_identity_bytes then
    Refused Identity_too_long
  else if is_private observation.artifact then
    if observation.requested = Exclude then Admitted Exclude
    else Refused Class_excluded
  else if
    observation.artifact = Deterministic_evolution_projection
    && not observation.allowlisted_projection
  then Refused Projection_not_allowlisted
  else if
    observation.artifact = Deterministic_evolution_projection
    && not observation.deterministic
  then Refused Nondeterministic_projection
  else if
    rank observation.requested > rank (default_disposition observation.artifact)
  then Refused Disposition_escalation
  else Admitted observation.requested

let source_only_closure observations =
  if List.length observations > max_closure_entries then Error Closure_too_large
  else
    let rec loop seen total admitted = function
      | [] -> Ok (List.rev admitted)
      | observation :: rest ->
          if List.mem observation.public_identity seen then Error Duplicate_identity
          else if observation.size_bytes > max_closure_bytes - total then
            Error Closure_bytes_exceeded
          else
            match admit observation with
            | Refused refusal -> Error refusal
            | Admitted (Track | Sanitize_and_track) ->
                loop (observation.public_identity :: seen)
                  (total + observation.size_bytes) (observation :: admitted) rest
            | Admitted (Digest_only | Exclude) ->
                loop (observation.public_identity :: seen)
                  (total + observation.size_bytes) admitted rest
    in
    loop [] 0 [] observations

let redacted_identity ~public_identity ~private_value:_ =
  "redacted:" ^ public_identity

let disposition_key = function
  | Track -> "track" | Sanitize_and_track -> "sanitize-and-track"
  | Digest_only -> "digest-only" | Exclude -> "exclude"

let artifact_key = function
  | Source -> "source"
  | Deterministic_evolution_projection -> "deterministic-evolution-projection"
  | Evidence_digest -> "evidence-digest"
  | Credential -> "credential" | Authentication_header -> "authentication-header"
  | Cache -> "cache" | Session -> "session" | Trust_record -> "trust-record"
  | Machine_id -> "machine-id" | Raw_database -> "raw-database"
  | Sidecar -> "sidecar" | Build_tree -> "build-tree"
  | Browser_runtime_media -> "browser-runtime-media"
  | Private_agent_state -> "private-agent-state"

let source_digest =
  let artifacts =
    [ Source; Deterministic_evolution_projection; Evidence_digest; Credential;
      Authentication_header; Cache; Session; Trust_record; Machine_id;
      Raw_database; Sidecar; Build_tree; Browser_runtime_media;
      Private_agent_state ]
  in
  Jj_id.length_frame
    [ "mainline-carrier-policy.v1";
      string_of_int max_artifact_bytes; string_of_int max_closure_entries;
      string_of_int max_closure_bytes; string_of_int max_identity_bytes;
      artifacts
      |> List.map (fun artifact ->
             Jj_id.length_frame
               [ artifact_key artifact;
                 disposition_key (default_disposition artifact) ])
      |> Jj_id.length_frame;
      "deny-overrides;source-only;deterministic-allowlist;redaction-noninterference" ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
