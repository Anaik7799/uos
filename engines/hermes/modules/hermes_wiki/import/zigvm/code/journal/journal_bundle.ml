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

type raw = {
  version : int;
  title : string;
  root : string;
  input : string;
  outputs : string list;
  report : string option;
  dashboard : string option;
  otel_log : string option;
  prompt_ledgers : string list;
  text_artifacts : string list;
  image_artifacts : image_artifact list;
  root_policy : root_policy;
  audience : audience;
  output_specs : output_spec list;
  media_artifacts : media_artifact list;
}

type t = raw

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

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let required name decoder json =
  match member name json with
  | None -> Error ("missing field: " ^ name)
  | Some value -> decoder name value

let as_string name = function
  | `String value -> Ok value
  | _ -> Error (name ^ " must be a string")

let as_int name = function
  | `Int value -> Ok value
  | _ -> Error (name ^ " must be an integer")

let as_list item_decoder name = function
  | `List values ->
      List.fold_left
        (fun accumulated value ->
          match accumulated, item_decoder name value with
          | Ok items, Ok item -> Ok (item :: items)
          | Error message, _ | _, Error message -> Error message)
        (Ok []) values
      |> Result.map List.rev
  | _ -> Error (name ^ " must be an array")

let as_image name = function
  | `Assoc _ as json ->
      let path = required "path" as_string json in
      let source =
        match member "source" json with
        | None | Some `Null -> Ok None
        | Some value -> as_string "source" value |> Result.map Option.some
      in
      (match path, source with
       | Ok path, Ok source -> Ok { path; source }
       | Error message, _ | _, Error message -> Error (name ^ ": " ^ message))
  | _ -> Error (name ^ " entries must be objects")

let root_policy_of_string = function
  | "invocation_root" -> Ok Invocation_root
  | "manifest_directory" -> Ok Manifest_directory
  | value -> Error ("unknown root_policy: " ^ value)

let audience_of_string = function
  | "private" -> Ok Private
  | "tailnet" -> Ok Tailnet
  | "public" -> Ok Public
  | value -> Error ("unknown audience: " ^ value)

let role_of_string = function
  | "archive" -> Ok Archive
  | "dashboard" -> Ok Dashboard
  | "evidence" -> Ok Evidence
  | value -> Error ("unknown output role: " ^ value)

let kind_of_string = function
  | "text" -> Ok Text | "image" -> Ok Image | "video" -> Ok Video
  | "trace" -> Ok Trace | "binary" -> Ok Binary
  | value -> Error ("unknown artifact kind: " ^ value)

let privacy_of_string = function
  | "public_data" -> Ok Public_data
  | "personal_identifier" -> Ok Personal_identifier
  | "secret" -> Ok Secret
  | value -> Error ("unknown privacy class: " ^ value)

let bind result next = match result with Ok value -> next value | Error _ as failure -> failure

let as_output name = function
  | `String path -> Ok { path; role = Archive }
  | `Assoc _ as json ->
      bind (required "path" as_string json) (fun path ->
        bind (required "role" as_string json) (fun role ->
          bind (role_of_string role) (fun role -> Ok { path; role })))
  | _ -> Error (name ^ " entries must be strings or objects")

let as_media name = function
  | `Assoc _ as json ->
      let source =
        match member "source" json with
        | None | Some `Null -> Ok None
        | Some value -> as_string "source" value |> Result.map Option.some
      in
      bind (required "path" as_string json) (fun path ->
        bind source (fun source ->
          bind (required "kind" as_string json) (fun kind ->
            bind (kind_of_string kind) (fun kind ->
              bind (required "mime_type" as_string json) (fun mime_type ->
                bind (required "label" as_string json) (fun label ->
                  bind (required "privacy" as_string json) (fun privacy ->
                    bind (privacy_of_string privacy) (fun privacy ->
                      Ok { path; source; kind; mime_type; label; privacy }))))))))
  | _ -> Error (name ^ " entries must be objects")

let optional_with_default name decoder default json =
  match member name json with None -> Ok default | Some value -> decoder name value

let optional_string name json =
  match member name json with
  | None | Some `Null -> Ok None
  | Some value -> as_string name value |> Result.map Option.some

let decode text =
  try
    let json = Yojson.Safe.from_string text in
    let version = required "version" as_int json in
    let title = required "title" as_string json in
    let root = optional_with_default "root" as_string "." json in
    let input = required "input" as_string json in
    let output_specs = required "outputs" (as_list as_output) json in
    let report = optional_string "report" json in
    let dashboard = optional_string "dashboard" json in
    let otel_log = optional_string "otel_log" json in
    let root_policy =
      match member "root_policy" json with
      | None -> Ok Invocation_root
      | Some value -> bind (as_string "root_policy" value) root_policy_of_string
    in
    let audience =
      match member "audience" json with
      | None -> Ok Private
      | Some value -> bind (as_string "audience" value) audience_of_string
    in
    let prompt_ledgers =
      required "prompt_ledgers" (as_list as_string) json
    in
    let text_artifacts =
      required "text_artifacts" (as_list as_string) json
    in
    let image_artifacts =
      required "image_artifacts" (as_list as_image) json
    in
    let media_artifacts =
      optional_with_default "artifacts" (as_list as_media) [] json
    in
    match
      version, title, root, input, output_specs, report, dashboard, otel_log,
      root_policy, audience, prompt_ledgers, text_artifacts, image_artifacts,
      media_artifacts
    with
    | Ok version, Ok title, Ok root, Ok input, Ok output_specs, Ok report,
      Ok dashboard, Ok otel_log, Ok root_policy, Ok audience,
      Ok prompt_ledgers, Ok text_artifacts, Ok image_artifacts,
      Ok media_artifacts ->
        let outputs = List.map (fun (output : output_spec) -> output.path) output_specs in
        Ok
          { version; title; root; input; outputs; report; dashboard; otel_log;
            prompt_ledgers;
            text_artifacts; image_artifacts; root_policy; audience;
            output_specs; media_artifacts }
    | values ->
        let errors =
          let add result acc = match result with Error message -> message :: acc | Ok _ -> acc in
          [] |> add version |> add title |> add root |> add input |> add output_specs
          |> add report |> add dashboard |> add otel_log |> add root_policy
          |> add audience |> add prompt_ledgers |> add text_artifacts
          |> add image_artifacts |> add media_artifacts
        in
        ignore values;
        Error (match List.rev errors with message :: _ -> message | [] -> "invalid manifest")
  with Yojson.Json_error message -> Error ("invalid JSON: " ^ message)

let resolve root path =
  if Filename.is_relative path then Filename.concat root path else path

let starts_with ~prefix value =
  String.length value >= String.length prefix &&
  String.sub value 0 (String.length prefix) = prefix

let duplicates values =
  let sorted = List.sort String.compare values in
  let rec loop accumulated = function
    | first :: (second :: _ as rest) when String.equal first second ->
        loop (first :: accumulated) rest
    | _ :: rest -> loop accumulated rest
    | [] -> List.sort_uniq String.compare accumulated
  in
  loop [] sorted

let nonempty_lines text =
  String.split_on_char '\n' text
  |> List.filter (fun line -> String.trim line <> "")

let prompt_violations ~path text =
  let rec loop mode expected line_number violations = function
    | [] -> List.rev violations
    | line :: rest ->
        let next mode violations expected =
          loop mode expected (line_number + 1) violations rest
        in
        (try
           let json = Yojson.Safe.from_string line in
           let entry =
             match member "ordinal" json with
             | None -> `Legacy
             | Some (`Int ordinal) -> `Ordinal ordinal
             | Some _ -> `Invalid
           in
           let violations =
             match member "text" json, member "base_ordinal" json with
             | Some (`String _), None -> violations
             | Some (`String _), Some _ ->
                 Prompt_derivation_error
                   { path; line = line_number;
                     message = "entry cannot carry both text and base_ordinal" }
                 :: violations
             | None, Some (`Int base) ->
                 (match entry, member "suffix" json with
                  | `Ordinal actual, Some (`String suffix)
                    when base >= 1 && base < actual && suffix <> "" ->
                      violations
                  | `Ordinal actual, _ ->
                      Prompt_derivation_error
                        { path; line = line_number;
                          message =
                            Printf.sprintf
                              "derived prompt requires nonempty suffix and 1<=base(%d)<ordinal(%d)"
                              base actual }
                        :: violations
                  | _ ->
                      Prompt_derivation_error
                        { path; line = line_number;
                          message = "derived prompt requires explicit ordinal" }
                        :: violations)
             | None, Some _ ->
                 Prompt_derivation_error
                   { path; line = line_number;
                     message = "base_ordinal must be an integer" }
                 :: violations
             | None, None ->
                 Prompt_derivation_error
                   { path; line = line_number;
                     message = "prompt requires text or lossless derivation" }
                 :: violations
             | Some _, _ ->
                 Prompt_derivation_error
                   { path; line = line_number;
                     message = "text must be a string" }
                 :: violations
           in
           match mode, entry with
           | None, `Legacy -> next (Some `Legacy) violations expected
           | Some `Legacy, `Legacy -> next mode violations expected
           | None, `Ordinal actual when actual = expected ->
               next (Some `Ordinal) violations (expected + 1)
           | Some `Ordinal, `Ordinal actual when actual = expected ->
               next mode violations (expected + 1)
           | (None | Some `Ordinal), `Ordinal actual ->
               next (Some `Ordinal)
                 (Prompt_ordinal_gap
                    { path; line = line_number; expected; actual }
                  :: violations)
                 (actual + 1)
           | (Some `Legacy, `Ordinal _) | (Some `Ordinal, `Legacy) ->
               next mode
                 (Prompt_schema_mismatch { path; line = line_number }
                  :: violations)
                 expected
           | _, `Invalid ->
               next mode
                 (Prompt_parse_error
                    { path; line = line_number;
                      message = "ordinal must be an integer" }
                  :: violations)
                 expected
         with Yojson.Json_error message ->
           next mode
             (Prompt_parse_error { path; line = line_number; message }
              :: violations)
             expected)
  in
  loop None 1 1 [] (nonempty_lines text)

let validate_at ~invocation_root ~manifest_directory ~exists ~read raw =
  let policy_root =
    match raw.root_policy with
    | Invocation_root -> invocation_root
    | Manifest_directory -> manifest_directory
  in
  let root =
    if Filename.is_relative raw.root then
      Filename.concat policy_root raw.root
    else raw.root
  in
  let input = resolve root raw.input in
  let outputs = List.map (resolve root) raw.outputs in
  let report = Option.map (resolve root) raw.report in
  let dashboard = Option.map (resolve root) raw.dashboard in
  let otel_log = Option.map (resolve root) raw.otel_log in
  let prompt_ledgers = List.map (resolve root) raw.prompt_ledgers in
  let text_artifacts = List.map (resolve root) raw.text_artifacts in
  let image_artifacts =
    List.map
      (fun (image : image_artifact) ->
        { path = resolve root image.path;
          source = Option.map (resolve root) image.source })
      raw.image_artifacts
  in
  let output_specs =
    List.map (fun (output : output_spec) -> { output with path = resolve root output.path })
      raw.output_specs
  in
  let media_artifacts =
    List.map
      (fun artifact ->
        { artifact with path = resolve root artifact.path;
          source = Option.map (resolve root) artifact.source })
      raw.media_artifacts
  in
  let violations = ref [] in
  let add violation = violations := violation :: !violations in
  if raw.version <> 1 && raw.version <> 2 then add (Unsupported_version raw.version);
  if String.trim raw.title = "" then add Empty_title;
  if outputs = [] then add No_outputs;
  List.iter (fun path -> add (Duplicate_output path)) (duplicates outputs);
  let artifact_paths =
    prompt_ledgers @ text_artifacts @ List.map (fun (image : image_artifact) -> image.path) image_artifacts
    @ List.map (fun artifact -> artifact.path) media_artifacts
  in
  List.iter (fun path -> add (Duplicate_artifact path))
    (duplicates artifact_paths);
  if not (exists input) then add (Missing_artifact input);
  List.iter
    (fun path ->
      if not (exists path) then add (Missing_artifact path)
      else
        match read path with
        | Error _ -> add (Missing_artifact path)
        | Ok text ->
            List.iter add (prompt_violations ~path text);
            if raw.audience = Public && String.contains text '@' then
              add (Personal_identifier_requires_private_audience path))
    prompt_ledgers;
  List.iter
    (fun path -> if not (exists path) then add (Missing_artifact path))
    text_artifacts;
  List.iter
    (fun (image : image_artifact) ->
      if starts_with ~prefix:"/tmp/" image.path then
        add (Ephemeral_durable_path image.path);
      let source_exists =
        match image.source with Some path -> exists path | None -> false
      in
      if not (exists image.path) && not source_exists then
        add (Missing_artifact image.path))
    image_artifacts;
  List.iter
    (fun artifact ->
      if starts_with ~prefix:"/tmp/" artifact.path then
        add (Ephemeral_durable_path artifact.path);
      (match artifact.privacy, raw.audience with
       | Secret, _ -> add (Secret_artifact_rejected artifact.path)
       | Personal_identifier, Public ->
           add (Personal_identifier_requires_private_audience artifact.path)
       | Public_data, _ | Personal_identifier, (Private | Tailnet) -> ());
      let source_exists =
        match artifact.source with Some path -> exists path | None -> false
      in
      if not (exists artifact.path) && not source_exists then
        add (Missing_artifact artifact.path))
    media_artifacts;
  let validated =
    { raw with root; input; outputs; report; dashboard; otel_log;
      prompt_ledgers; text_artifacts;
      image_artifacts; output_specs; media_artifacts }
  in
  match List.rev !violations with
  | [] -> Ok validated
  | violations -> Error violations

let validate ~exists ~read raw =
  let cwd = Sys.getcwd () in
  validate_at ~invocation_root:cwd ~manifest_directory:cwd ~exists ~read raw

let title bundle = bundle.title
let root bundle = bundle.root
let input bundle = bundle.input
let outputs bundle = bundle.outputs
let report bundle = bundle.report
let dashboard bundle = bundle.dashboard
let otel_log bundle = bundle.otel_log
let prompt_ledgers bundle = bundle.prompt_ledgers
let text_artifacts bundle = bundle.text_artifacts
let image_artifacts bundle = bundle.image_artifacts
let root_policy bundle = bundle.root_policy
let audience bundle = bundle.audience
let output_specs bundle = bundle.output_specs
let media_artifacts bundle = bundle.media_artifacts
let fingerprint content = Journal_bundle_digest.sha256_string content

let report_input_fingerprint content =
  try
    let json = Yojson.Safe.from_string content in
    match member "input_fingerprint_sha256" json with
    | Some (`String value) -> Some value
    | _ ->
        (match member "input_fingerprint_md5" json with
         | Some (`String value) -> Some value
         | _ -> None)
  with Yojson.Json_error _ -> None

let is_digit character = character >= '0' && character <= '9'

let parse_decimal value offset length =
  let rec loop index accumulated =
    if index = offset + length then Some accumulated
    else
      let character = value.[index] in
      if is_digit character then
        loop (index + 1)
          ((accumulated * 10) + (Char.code character - Char.code '0'))
      else None
  in
  loop offset 0

let leap_year year =
  year mod 400 = 0 || (year mod 4 = 0 && year mod 100 <> 0)

let days_in_month year = function
  | 1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
  | 4 | 6 | 9 | 11 -> 30
  | 2 -> if leap_year year then 29 else 28
  | _ -> 0

let valid_human_timestamp value =
  String.length value = 15 &&
  value.[4] = '-' && value.[7] = '-' && value.[10] = '-' &&
  match
    parse_decimal value 0 4,
    parse_decimal value 5 2,
    parse_decimal value 8 2,
    parse_decimal value 11 2,
    parse_decimal value 13 2
  with
  | Some year, Some month, Some day, Some hour, Some second ->
      year >= 1 && month >= 1 && month <= 12 && day >= 1 &&
      day <= days_in_month year month && hour >= 0 && hour <= 23 &&
      second >= 0 && second <= 60
  | _ -> false

let format_human_timestamp epoch_seconds =
  let time = Unix.localtime epoch_seconds in
  Printf.sprintf "%04d-%02d-%02d-%02d%02d"
    (time.tm_year + 1900) (time.tm_mon + 1) time.tm_mday time.tm_hour
    time.tm_sec

let violation_name = function
  | Unsupported_version version -> Printf.sprintf "unsupported-version(%d)" version
  | Empty_title -> "empty-title"
  | No_outputs -> "no-outputs"
  | Duplicate_output path -> "duplicate-output(" ^ path ^ ")"
  | Duplicate_artifact path -> "duplicate-artifact(" ^ path ^ ")"
  | Missing_artifact path -> "missing-artifact(" ^ path ^ ")"
  | Ephemeral_durable_path path -> "ephemeral-durable-path(" ^ path ^ ")"
  | Prompt_parse_error { path; line; message } ->
      Printf.sprintf "prompt-parse-error(%s:%d:%s)" path line message
  | Prompt_schema_mismatch { path; line } ->
      Printf.sprintf "prompt-schema-mismatch(%s:%d)" path line
  | Prompt_derivation_error { path; line; message } ->
      Printf.sprintf "prompt-derivation-error(%s:%d:%s)" path line message
  | Prompt_ordinal_gap { path; line; expected; actual } ->
      Printf.sprintf "prompt-ordinal-gap(%s:%d:%d!=%d)"
        path line expected actual
  | Personal_identifier_requires_private_audience path ->
      "personal-identifier-requires-private-audience(" ^ path ^ ")"
  | Secret_artifact_rejected path -> "secret-artifact-rejected(" ^ path ^ ")"

let root_policy_name = function
  | Invocation_root -> "invocation_root"
  | Manifest_directory -> "manifest_directory"
let audience_name = function Private -> "private" | Tailnet -> "tailnet" | Public -> "public"
let role_name = function Archive -> "archive" | Dashboard -> "dashboard" | Evidence -> "evidence"
let kind_name = function Text -> "text" | Image -> "image" | Video -> "video" | Trace -> "trace" | Binary -> "binary"
let privacy_name = function Public_data -> "public_data" | Personal_identifier -> "personal_identifier" | Secret -> "secret"

let report_to_yojson bundle =
  `Assoc
    [ ("version", `Int 2);
      ("title", `String bundle.title);
      ("root", `String bundle.root);
      ("root_policy", `String (root_policy_name bundle.root_policy));
      ("audience", `String (audience_name bundle.audience));
      ("input", `String bundle.input);
      ("outputs",
       `List
         (List.map (fun (output : output_spec) ->
            `Assoc [ "path", `String output.path; "role", `String (role_name output.role) ])
            bundle.output_specs));
      ("report", match bundle.report with None -> `Null | Some path -> `String path);
      ("dashboard", match bundle.dashboard with None -> `Null | Some path -> `String path);
      ("otel_log", match bundle.otel_log with None -> `Null | Some path -> `String path);
      ("prompt_ledgers",
       `List (List.map (fun path -> `String path) bundle.prompt_ledgers));
      ("text_artifacts",
       `List (List.map (fun path -> `String path) bundle.text_artifacts));
      ("image_artifacts",
       `List
         (List.map
            (fun (image : image_artifact) ->
              `Assoc
                ([ ("path", `String image.path) ] @
                 match image.source with
                 | None -> []
                 | Some source -> [ ("source", `String source) ]))
            bundle.image_artifacts));
      ("artifacts",
       `List
         (List.map
            (fun artifact ->
              `Assoc
                ([ "path", `String artifact.path;
                   "kind", `String (kind_name artifact.kind);
                   "mime_type", `String artifact.mime_type;
                   "label", `String artifact.label;
                   "privacy", `String (privacy_name artifact.privacy) ] @
                 match artifact.source with None -> [] | Some path -> [ "source", `String path ]))
            bundle.media_artifacts)) ]
