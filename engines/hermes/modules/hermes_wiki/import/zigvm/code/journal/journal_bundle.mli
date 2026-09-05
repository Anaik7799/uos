type image_artifact = {
  path : string;
  source : string option;
}

type root_policy = Invocation_root | Manifest_directory
type output_role = Archive | Dashboard | Evidence
type artifact_kind = Text | Image | Video | Trace | Binary
type audience = Private | Tailnet | Public
type privacy = Public_data | Personal_identifier | Secret

type output_spec = { path : string; role : output_role }
type media_artifact = {
  path : string;
  source : string option;
  kind : artifact_kind;
  mime_type : string;
  label : string;
  privacy : privacy;
}

type raw
type t

type violation =
  | Unsupported_version of int
  | Empty_title
  | No_outputs
  | Duplicate_output of string
  | Duplicate_artifact of string
  | Missing_artifact of string
  | Ephemeral_durable_path of string
  | Prompt_parse_error of { path : string; line : int; message : string }
  | Prompt_schema_mismatch of { path : string; line : int }
  | Prompt_derivation_error of { path : string; line : int; message : string }
  | Prompt_ordinal_gap of {
      path : string;
      line : int;
      expected : int;
      actual : int;
    }
  | Personal_identifier_requires_private_audience of string
  | Secret_artifact_rejected of string

val decode : string -> (raw, string) result

val validate :
  exists:(string -> bool) ->
  read:(string -> (string, string) result) ->
  raw ->
  (t, violation list) result

val validate_at :
  invocation_root:string ->
  manifest_directory:string ->
  exists:(string -> bool) ->
  read:(string -> (string, string) result) ->
  raw ->
  (t, violation list) result

val title : t -> string
val root : t -> string
val input : t -> string
val outputs : t -> string list
val report : t -> string option
val dashboard : t -> string option
val otel_log : t -> string option
val prompt_ledgers : t -> string list
val text_artifacts : t -> string list
val image_artifacts : t -> image_artifact list
val root_policy : t -> root_policy
val audience : t -> audience
val output_specs : t -> output_spec list
val media_artifacts : t -> media_artifact list
val fingerprint : string -> string
val report_input_fingerprint : string -> string option
val valid_human_timestamp : string -> bool
val format_human_timestamp : float -> string
val violation_name : violation -> string
val report_to_yojson : t -> Yojson.Safe.t
