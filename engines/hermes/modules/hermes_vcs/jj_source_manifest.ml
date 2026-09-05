module Bounded_string (Limit : sig val maximum : int end) = struct
  type t = string
  type error = Empty | Too_long | Invalid_byte

  let invalid byte =
    let code = Char.code byte in
    code = 0 || code < 32 || code = 127

  let make value =
    if String.length value = 0 then Error Empty
    else if String.length value > Limit.maximum then Error Too_long
    else if String.exists invalid value then Error Invalid_byte
    else Ok value

  let to_string value = value
end

module Identity = Bounded_string (struct let maximum = 512 end)
module Symlink_target = Bounded_string (struct let maximum = 4096 end)
module Exclusion_reason = Bounded_string (struct let maximum = 512 end)

type error =
  | Invalid_size
  | Carrier_refused of Mainline_carrier_policy.refusal
  | Symlink_target_required
  | Symlink_target_forbidden
  | Symlink_size_mismatch
  | Symlink_digest_mismatch
  | Invalid_sanitization_identity
  | Exclusion_reason_required
  | Exclusion_reason_forbidden
  | Empty_manifest
  | Too_many_entries
  | Path_identity_conflict

type entry = {
  path : Jj_path.t;
  mode : Jj_split_manifest.file_mode;
  symlink_target : Symlink_target.t option;
  size_bytes : int;
  content_digest : Jj_split_manifest.Digest.t;
  artifact : Mainline_carrier_policy.artifact_class;
  disposition : Mainline_carrier_policy.disposition;
  sanitizer_identity : Identity.t option;
  projection_identity : Identity.t option;
  exclusion_reason : Exclusion_reason.t option;
  digest : string;
}

let schema_id = "hermes.jj-source-manifest.v1"
let max_entries = Mainline_carrier_policy.max_closure_entries

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let option key to_string = function
  | None -> Jj_id.length_frame [ key; "none" ]
  | Some value -> Jj_id.length_frame [ key; "some"; to_string value ]

let mode_key = function
  | Jj_split_manifest.Regular -> "regular"
  | Jj_split_manifest.Executable -> "executable"
  | Jj_split_manifest.Symlink -> "symlink"

let disposition_key = function
  | Mainline_carrier_policy.Track -> "track"
  | Mainline_carrier_policy.Sanitize_and_track -> "sanitize-and-track"
  | Mainline_carrier_policy.Digest_only -> "digest-only"
  | Mainline_carrier_policy.Exclude -> "exclude"

let artifact_key = function
  | Mainline_carrier_policy.Source -> "source"
  | Deterministic_evolution_projection -> "deterministic-evolution-projection"
  | Evidence_digest -> "evidence-digest"
  | Credential -> "credential"
  | Authentication_header -> "authentication-header"
  | Cache -> "cache"
  | Session -> "session"
  | Trust_record -> "trust-record"
  | Machine_id -> "machine-id"
  | Raw_database -> "raw-database"
  | Sidecar -> "sidecar"
  | Build_tree -> "build-tree"
  | Browser_runtime_media -> "browser-runtime-media"
  | Private_agent_state -> "private-agent-state"

let canonical_entry ~path ~mode ~symlink_target ~size_bytes ~content_digest
    ~artifact ~disposition ~sanitizer_identity ~projection_identity
    ~exclusion_reason =
  Jj_id.length_frame
    [ schema_id; Jj_path.to_string path; mode_key mode;
      option "symlink-target" Symlink_target.to_string symlink_target;
      string_of_int size_bytes;
      Jj_split_manifest.Digest.to_string content_digest;
      artifact_key artifact; disposition_key disposition;
      option "sanitizer" Identity.to_string sanitizer_identity;
      option "projection" Identity.to_string projection_identity;
      option "exclusion" Exclusion_reason.to_string exclusion_reason ]

let entry ~path ~mode ~symlink_target ~size_bytes ~content_digest ~artifact
    ~disposition ~sanitizer_identity ~projection_identity ~exclusion_reason =
  let is_sanitized = disposition = Mainline_carrier_policy.Sanitize_and_track in
  let is_excluded =
    disposition = Mainline_carrier_policy.Digest_only
    || disposition = Mainline_carrier_policy.Exclude
  in
  if size_bytes < 0 then Error Invalid_size
  else if mode = Jj_split_manifest.Symlink && symlink_target = None then
    Error Symlink_target_required
  else if mode <> Jj_split_manifest.Symlink && symlink_target <> None then
    Error Symlink_target_forbidden
  else if
    (is_sanitized
     && not (sanitizer_identity <> None && projection_identity <> None))
    || ((not is_sanitized)
        && (sanitizer_identity <> None || projection_identity <> None))
  then Error Invalid_sanitization_identity
  else if is_excluded && exclusion_reason = None then Error Exclusion_reason_required
  else if not is_excluded && exclusion_reason <> None then Error Exclusion_reason_forbidden
  else
    match symlink_target with
    | Some target when String.length (Symlink_target.to_string target) <> size_bytes ->
        Error Symlink_size_mismatch
    | Some target ->
        let observed =
          Symlink_target.to_string target |> Bytes.of_string
          |> Jj_split_manifest.Digest.of_bytes
          |> Jj_split_manifest.Digest.to_string
        in
        if
          not
            (String.equal observed
               (Jj_split_manifest.Digest.to_string content_digest))
        then Error Symlink_digest_mismatch
        else
          let observation : Mainline_carrier_policy.observation =
            { artifact; requested = disposition; size_bytes; deterministic = true;
              allowlisted_projection = projection_identity <> None;
              public_identity = Jj_path.to_string path }
          in
          (match Mainline_carrier_policy.admit observation with
           | Refused refusal -> Error (Carrier_refused refusal)
           | Admitted _ ->
               let canonical =
                 canonical_entry ~path ~mode ~symlink_target ~size_bytes
                   ~content_digest ~artifact ~disposition ~sanitizer_identity
                   ~projection_identity ~exclusion_reason
               in
               Ok { path; mode; symlink_target; size_bytes; content_digest;
                    artifact; disposition; sanitizer_identity;
                    projection_identity; exclusion_reason;
                    digest = sha256 canonical })
    | None ->
        let observation : Mainline_carrier_policy.observation =
          { artifact; requested = disposition; size_bytes; deterministic = true;
            allowlisted_projection = projection_identity <> None;
            public_identity = Jj_path.to_string path }
        in
        (match Mainline_carrier_policy.admit observation with
         | Refused refusal -> Error (Carrier_refused refusal)
         | Admitted _ ->
             let canonical =
               canonical_entry ~path ~mode ~symlink_target ~size_bytes
                 ~content_digest ~artifact ~disposition ~sanitizer_identity
                 ~projection_identity ~exclusion_reason
             in
             Ok { path; mode; symlink_target; size_bytes; content_digest;
                  artifact; disposition; sanitizer_identity; projection_identity;
                  exclusion_reason; digest = sha256 canonical })

let entry_digest entry = entry.digest

type t = { entries : entry list; digest : string }

let compare_entry left right = Jj_path.compare left.path right.path

let carrier_observation entry : Mainline_carrier_policy.observation =
  { artifact = entry.artifact; requested = entry.disposition;
    size_bytes = entry.size_bytes; deterministic = true;
    allowlisted_projection = entry.projection_identity <> None;
    public_identity = Jj_path.to_string entry.path }

let make entries =
  if entries = [] then Error Empty_manifest
  else if List.length entries > max_entries then Error Too_many_entries
  else
    let sorted = List.sort compare_entry entries in
    let rec deduplicate accumulated = function
      | [] -> Ok (List.rev accumulated)
      | entry :: rest ->
          (match accumulated with
           | previous :: _ when Jj_path.equal previous.path entry.path ->
               if String.equal previous.digest entry.digest then
                 deduplicate accumulated rest
               else Error Path_identity_conflict
           | _ -> deduplicate (entry :: accumulated) rest)
    in
    match deduplicate [] sorted with
    | Error _ as error -> error
    | Ok unique ->
        (match
           Mainline_carrier_policy.source_only_closure
             (List.map carrier_observation unique)
         with
         | Error refusal -> Error (Carrier_refused refusal)
         | Ok _ ->
             let digest =
               Jj_id.length_frame
                 (schema_id :: List.map (fun (entry : entry) -> entry.digest) unique)
               |> sha256
             in
             Ok { entries = unique; digest })

let entry_count manifest = List.length manifest.entries
let entries manifest = manifest.entries
let digest manifest = manifest.digest

let source_digest =
  Jj_id.length_frame
    [ schema_id; string_of_int max_entries;
      "entry:path,mode,symlink-target,size,content-digest,artifact,disposition,sanitizer,projection,exclusion";
      "modes:regular,executable,symlink";
      "errors:invalid-size,carrier,symlink-required,symlink-forbidden,symlink-size,symlink-digest,sanitizer,exclusion-required,exclusion-forbidden,empty,too-many,path-conflict";
      Mainline_carrier_policy.source_digest ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
