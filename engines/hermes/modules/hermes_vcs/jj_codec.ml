type error = Too_large | Malformed_json | Unknown_field of string
  | Missing_field of string | Duplicate_field of string | Hostile_value
  | Invalid_value of string | Intent_error of Jj_intent.error

let schema = "hermes.jj.intent.v1"
let maximum_json_bytes = 8192
let maximum_field_bytes = 256

let string_of_approval = function
  | Jj_operation.Approval_observation -> "observation"
  | Jj_operation.Approval_mutation -> "mutation"
  | Jj_operation.Approval_destructive -> "destructive"
  | Jj_operation.Approval_recovery -> "recovery"
  | Jj_operation.Approval_fetch -> "fetch"
  | Jj_operation.Approval_remote_publish -> "remote-publish"

let string_of_postcondition = function
  | Jj_operation.Postcondition_readback -> "readback"
  | Jj_operation.Postcondition_mutation_readback -> "mutation-readback"
  | Jj_operation.Postcondition_recovery_readback -> "recovery-readback"
  | Jj_operation.Postcondition_remote_readback -> "remote-readback"

let string_of_recovery = function
  | Jj_operation.Recovery_none -> "none"
  | Jj_operation.Recovery_before_state -> "before-state"
  | Jj_operation.Recovery_partition_anchor -> "partition-anchor"

let string_of_applicability = function
  | Jj_intent.Unavailable_until_bridge -> "unavailable-until-bridge"
  | Jj_intent.Implemented_unavailable -> "implemented-unavailable"

let fields intent =
  let value = Jj_intent.projection intent in
  let declaration = Jj_operation.declaration value.operation in
  [ ("schema", schema); ("operation", declaration.key);
    ("repository", Jj_id.Repository.to_string value.repository);
    ("workspace", Jj_id.Workspace.to_string value.workspace);
    ("expected_before", Jj_id.Operation.to_string value.expected_before);
    ("approval_reference", Jj_id.Approval.to_string value.approval_reference);
    ("approval_class", string_of_approval value.approval);
    ("max_attempts", string_of_int value.budget.max_attempts);
    ("timeout_ms", string_of_int value.budget.timeout_ms);
    ("max_output_bytes", string_of_int value.budget.max_output_bytes);
    ("postcondition", string_of_postcondition value.postcondition);
    ("recovery", string_of_recovery value.recovery);
    ("applicability", string_of_applicability value.applicability) ]

let canonical_bytes intent =
  fields intent
  |> List.concat_map (fun (key, value) -> [ key; value ])
  |> Jj_id.length_frame

let digest intent =
  canonical_bytes intent |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let to_json intent =
  fields intent
  |> List.map (fun (key, value) ->
         Printf.sprintf "\"%s\":\"%s\"" key value)
  |> String.concat "," |> Printf.sprintf "{%s}"

let is_space = function ' ' | '\n' | '\r' | '\t' -> true | _ -> false

let parse_fields input =
  let length = String.length input in
  let rec skip_spaces offset =
    if offset < length && is_space input.[offset] then skip_spaces (offset + 1)
    else offset
  in
  let parse_string offset =
    let offset = skip_spaces offset in
    if offset >= length || input.[offset] <> '"' then Error Malformed_json
    else
      let rec scan cursor =
        if cursor >= length then Error Malformed_json
        else
          match input.[cursor] with
          | '"' ->
              let value = String.sub input (offset + 1) (cursor - offset - 1) in
              if String.length value > maximum_field_bytes then Error Too_large
              else Ok (value, cursor + 1)
          | '\\' -> Error Hostile_value
          | character when Char.code character < 32 || Char.code character = 127 ->
              Error Hostile_value
          | _ -> scan (cursor + 1)
      in
      scan (offset + 1)
  in
  let rec members offset fields =
    let offset = skip_spaces offset in
    if offset >= length then Error Malformed_json
    else if input.[offset] = '}' then
      let tail = skip_spaces (offset + 1) in
      if tail = length then Ok (List.rev fields) else Error Malformed_json
    else
      match parse_string offset with
      | Error error -> Error error
      | Ok (key, after_key) ->
          let colon = skip_spaces after_key in
          if colon >= length || input.[colon] <> ':' then Error Malformed_json
          else
            match parse_string (colon + 1) with
            | Error error -> Error error
            | Ok (value, after_value) ->
                let separator = skip_spaces after_value in
                if separator >= length then Error Malformed_json
                else if input.[separator] = ',' then
                  members (separator + 1) ((key, value) :: fields)
                else if input.[separator] = '}' then
                  let tail = skip_spaces (separator + 1) in
                  if tail = length then Ok (List.rev ((key, value) :: fields))
                  else Error Malformed_json
                else Error Malformed_json
  in
  let start = skip_spaces 0 in
  if start >= length || input.[start] <> '{' then Error Malformed_json
  else members (start + 1) []

let expected_keys =
  [ "schema"; "operation"; "repository"; "workspace"; "expected_before";
    "approval_reference"; "approval_class"; "max_attempts"; "timeout_ms";
    "max_output_bytes"; "postcondition"; "recovery"; "applicability" ]

let codec_error_denominator =
  [ "too-large"; "malformed-json"; "unknown-field"; "missing-field";
    "duplicate-field"; "hostile-value"; "invalid-value"; "intent-error" ]

let source_digest_of ~json_bound ~keys =
  Jj_id.length_frame
    [ "intent-codec-authority-v1"; Jj_intent.source_digest; schema;
      "maximum-json-bytes:" ^ string_of_int json_bound;
      "maximum-field-bytes:" ^ string_of_int maximum_field_bytes;
      Jj_id.length_frame keys; Jj_id.length_frame codec_error_denominator;
      "json-values:string-only"; "unknown-fields:refused";
      "duplicate-fields:refused"; "escapes:refused" ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let source_digest =
  source_digest_of ~json_bound:maximum_json_bytes ~keys:expected_keys

module For_test = struct
  type source_mutation = Change_json_bound | Drop_expected_field
  let source_digest_with_mutation = function
    | Change_json_bound ->
        source_digest_of ~json_bound:(maximum_json_bytes + 1)
          ~keys:expected_keys
    | Drop_expected_field ->
        source_digest_of ~json_bound:maximum_json_bytes
          ~keys:(List.tl expected_keys)
end

let validate_shape values =
  let rec loop seen = function
    | [] ->
        (match List.find_opt (fun key -> not (List.mem key seen)) expected_keys with
         | Some key -> Error (Missing_field key)
         | None -> Ok ())
    | (key, _) :: tail ->
        if not (List.mem key expected_keys) then Error (Unknown_field key)
        else if List.mem key seen then Error (Duplicate_field key)
        else loop (key :: seen) tail
  in
  loop [] values

let lookup key values =
  match List.assoc_opt key values with
  | Some value -> Ok value
  | None -> Error (Missing_field key)

let bind result function_ = match result with Ok value -> function_ value | Error error -> Error error
let ( let* ) = bind

let typed_id field make value =
  match make value with
  | Ok typed -> Ok typed
  | Error _ -> Error (Invalid_value field)

let verify_field values key expected =
  bind (lookup key values) (fun actual ->
      if String.equal actual expected then Ok () else Error (Invalid_value key))

let of_json input =
  if String.length input > maximum_json_bytes then Error Too_large
  else
    let* values = parse_fields input in
    let* () = validate_shape values in
    let* operation_key = lookup "operation" values in
    match Jj_operation.find operation_key with
    | None -> Error (Invalid_value "operation")
    | Some operation ->
        let* repository_text = lookup "repository" values in
        let* repository =
          typed_id "repository" Jj_id.Repository.make repository_text
        in
        let* workspace_text = lookup "workspace" values in
        let* workspace =
          typed_id "workspace" Jj_id.Workspace.make workspace_text
        in
        let* before_text = lookup "expected_before" values in
        let* expected_before =
          typed_id "expected_before" Jj_id.Operation.make before_text
        in
        let* approval_text = lookup "approval_reference" values in
        let* approval_reference =
          typed_id "approval_reference" Jj_id.Approval.make approval_text
        in
        let* intent =
          match
            Jj_intent.make ~operation ~repository ~workspace ~expected_before
              ~approval_reference
          with
          | Ok value -> Ok value
          | Error error -> Error (Intent_error error)
        in
        let rec verify = function
          | [] -> Ok intent
          | (key, expected) :: tail ->
              let* () = verify_field values key expected in
              verify tail
        in
        verify (fields intent)
