#use "topfind";;
#require "digestif.ocaml,yojson";;

(** Closed contracts shared by the acceptance registry and runner.
    Public entry points: [parse_json_strict], [decode_acceptance_case],
    [decode_runner_fixture], [assert_expected], and [receipt_to_yojson]. *)

type status = Pass | Fail | Error

let string_of_status = function Pass -> "PASS" | Fail -> "FAIL" | Error -> "ERROR"

let status_of_string = function
  | "PASS" -> Ok Pass
  | "FAIL" -> Ok Fail
  | "ERROR" -> Ok Error
  | value -> Error ("unknown status " ^ value)

let sha256_string value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

type contract_error = { path : string; message : string }

let contract_error path message = Error { path; message }

let string_of_contract_error error = error.path ^ ": " ^ error.message

let child_path path key = if path = "$" then "$." ^ key else path ^ "." ^ key

let index_path path index = Printf.sprintf "%s[%d]" path index

let rec first_duplicate_or_nested path = function
  | `Assoc fields ->
      let rec fields_loop seen = function
        | [] -> Ok ()
        | (key, value) :: rest ->
            if List.mem key seen then contract_error (child_path path key) "duplicate key"
            else
              (match first_duplicate_or_nested (child_path path key) value with
               | Error _ as error -> error
               | Ok () -> fields_loop (key :: seen) rest)
      in
      fields_loop [] fields
  | `List values ->
      let rec list_loop index = function
        | [] -> Ok ()
        | value :: rest ->
            (match first_duplicate_or_nested (index_path path index) value with
             | Error _ as error -> error
             | Ok () -> list_loop (index + 1) rest)
      in
      list_loop 0 values
  | `Null | `Bool _ | `Int _ | `Float _ | `String _ -> Ok ()

let parse_json_strict bytes =
  try
    let json = Yojson.Basic.from_string bytes in
    match first_duplicate_or_nested "$" json with
    | Ok () -> Ok json
    | Error _ as error -> error
  with Yojson.Json_error message -> contract_error "$" ("malformed JSON: " ^ message)

let assoc_at path = function
  | `Assoc fields -> Ok fields
  | _ -> contract_error path "expected object"

let list_at path = function
  | `List values -> Ok values
  | _ -> contract_error path "expected array"

let string_at path = function
  | `String value -> Ok value
  | _ -> contract_error path "expected string"

let bool_at path = function
  | `Bool value -> Ok value
  | _ -> contract_error path "expected boolean"

let int_at path = function
  | `Int value -> Ok value
  | _ -> contract_error path "expected integer"

let exact_fields path allowed fields =
  match List.find_opt (fun (key, _) -> not (List.mem key allowed)) fields with
  | Some (key, _) -> contract_error (child_path path key) "unexpected field"
  | None ->
      match List.find_opt (fun key -> not (List.mem_assoc key fields)) allowed with
      | Some key -> contract_error (child_path path key) "missing field"
      | None -> Ok ()

let required_field path name fields decode =
  match List.assoc_opt name fields with
  | None -> contract_error (child_path path name) "missing field"
  | Some value -> decode (child_path path name) value

let valid_component value =
  let length = String.length value in
  let char_ok = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' -> true
    | _ -> false
  in
  length > 0 && length <= 96 && String.for_all char_ok value

let valid_namespaced_name value =
  let parts = String.split_on_char '.' value in
  List.length parts >= 2 && List.for_all valid_component parts

let namespaced_string_at path json =
  match string_at path json with
  | Error _ as error -> error
  | Ok value when valid_namespaced_name value -> Ok value
  | Ok _ -> contract_error path "expected a namespaced identifier"

type action = { op : string }

let decode_action path json =
  match assoc_at path json with
  | Error _ as error -> error
  | Ok fields ->
      (match exact_fields path [ "op" ] fields with
       | Error _ as error -> error
       | Ok () ->
           match required_field path "op" fields namespaced_string_at with
           | Error _ as error -> error
           | Ok op -> Ok { op })

type acceptance_case = {
  case_id : string;
  given : Yojson.Basic.t;
  actions : action list;
  expect : Yojson.Basic.t;
}

let decode_acceptance_case ?(path = "$.acceptance_case") json =
  match first_duplicate_or_nested path json with
  | Error _ as error -> error
  | Ok () ->
      match assoc_at path json with
      | Error _ as error -> error
      | Ok fields ->
          match exact_fields path [ "id"; "given"; "when"; "expect" ] fields with
          | Error _ as error -> error
          | Ok () ->
              match required_field path "id" fields string_at with
              | Error _ as error -> error
              | Ok case_id when not (valid_component case_id) ->
                  contract_error (child_path path "id") "invalid case identifier"
              | Ok case_id ->
                  match required_field path "given" fields assoc_at with
                  | Error _ as error -> error
                  | Ok _ ->
                      let given = List.assoc "given" fields in
                      match required_field path "when" fields list_at with
                      | Error _ as error -> error
                      | Ok [] -> contract_error (child_path path "when") "actions must be nonempty"
                      | Ok action_jsons ->
                          let rec decode_actions index acc = function
                            | [] -> Ok (List.rev acc)
                            | action_json :: rest ->
                                match decode_action (index_path (child_path path "when") index) action_json with
                                | Error _ as error -> error
                                | Ok action -> decode_actions (index + 1) (action :: acc) rest
                          in
                          match decode_actions 0 [] action_jsons with
                          | Error _ as error -> error
                          | Ok actions ->
                              match required_field path "expect" fields assoc_at with
                              | Error _ as error -> error
                              | Ok _ -> Ok { case_id; given; actions; expect = List.assoc "expect" fields }

type runner_fixture = {
  adapter : string;
  required : bool;
  expected_exit : int;
  fixture : string;
}

let decode_runner_fixture ?(path = "$.given") json =
  match first_duplicate_or_nested path json with
  | Error _ as error -> error
  | Ok () ->
      match assoc_at path json with
      | Error _ as error -> error
      | Ok fields ->
          match exact_fields path [ "adapter"; "required"; "expected_exit"; "fixture" ] fields with
          | Error _ as error -> error
          | Ok () ->
              match required_field path "adapter" fields string_at with
              | Error _ as error -> error
              | Ok adapter when not (valid_component adapter || valid_namespaced_name adapter) ->
                  contract_error (child_path path "adapter") "invalid adapter identifier"
              | Ok adapter ->
                  match required_field path "required" fields bool_at with
                  | Error _ as error -> error
                  | Ok required ->
                      match required_field path "expected_exit" fields int_at with
                      | Error _ as error -> error
                      | Ok expected_exit ->
                          match required_field path "fixture" fields string_at with
                          | Error _ as error -> error
                          | Ok fixture when not (valid_component fixture) ->
                              contract_error (child_path path "fixture") "invalid fixture identifier"
                          | Ok fixture -> Ok { adapter; required; expected_exit; fixture }

let decode_task_acceptance task_id manifest =
  match first_duplicate_or_nested "$" manifest with
  | Error _ as error -> error
  | Ok () ->
      match assoc_at "$" manifest with
      | Error _ as error -> error
      | Ok root ->
          match required_field "$" "tasks" root list_at with
          | Error _ as error -> error
          | Ok tasks ->
              let matching =
                List.filter_map
                  (function
                    | `Assoc fields as task ->
                        (match List.assoc_opt "id" fields with
                         | Some (`String id) when id = task_id -> Some task
                         | _ -> None)
                    | _ -> None)
                  tasks
              in
              match matching with
              | [] -> contract_error "$.tasks" ("task not found: " ^ task_id)
              | _ :: _ :: _ -> contract_error "$.tasks" ("duplicate task id: " ^ task_id)
              | [ `Assoc fields ] ->
                  (match List.assoc_opt "acceptance_case" fields with
                   | None -> contract_error "$.tasks[].acceptance_case" "missing field"
                   | Some json -> decode_acceptance_case ~path:"$.tasks[].acceptance_case" json)
              | _ -> assert false

type assertion_mismatch = {
  mismatch_path : string;
  reason : string;
  expected_json : Yojson.Basic.t option;
  actual_json : Yojson.Basic.t option;
}

let json_kind = function
  | `Assoc _ -> "object" | `List _ -> "array" | `String _ -> "string"
  | `Int _ -> "integer" | `Float _ -> "number" | `Bool _ -> "boolean" | `Null -> "null"

let mismatch path reason expected actual =
  { mismatch_path = path; reason; expected_json = expected; actual_json = actual }

let rec compare_expected ~exact path expected actual =
  match expected, actual with
  | `Assoc expected_fields, `Assoc actual_fields ->
      let missing_or_different =
        List.concat_map
          (fun (key, expected_value) ->
            match List.assoc_opt key actual_fields with
            | None -> [ mismatch (child_path path key) "missing expected field" (Some expected_value) None ]
            | Some actual_value -> compare_expected ~exact (child_path path key) expected_value actual_value)
          expected_fields
      in
      let extras =
        if exact then
          List.filter_map
            (fun (key, actual_value) ->
              if List.mem_assoc key expected_fields then None
              else Some (mismatch (child_path path key) "unexpected field" None (Some actual_value)))
            actual_fields
        else []
      in
      missing_or_different @ extras
  | `List expected_values, `List actual_values ->
      if List.length expected_values <> List.length actual_values then
        [ mismatch path "array length differs" (Some expected) (Some actual) ]
      else
        List.mapi
          (fun index expected_value ->
            compare_expected ~exact (index_path path index) expected_value (List.nth actual_values index))
          expected_values
        |> List.concat
  | `Int expected_value, `Int actual_value when expected_value = actual_value -> []
  | `Float expected_value, `Float actual_value when expected_value = actual_value -> []
  | `String expected_value, `String actual_value when expected_value = actual_value -> []
  | `Bool expected_value, `Bool actual_value when expected_value = actual_value -> []
  | `Null, `Null -> []
  | _ when json_kind expected <> json_kind actual ->
      [ mismatch path ("type differs: expected " ^ json_kind expected ^ ", got " ^ json_kind actual)
          (Some expected) (Some actual) ]
  | _ -> [ mismatch path "value differs" (Some expected) (Some actual) ]

let assert_expected ?(exact = false) expected actual =
  match first_duplicate_or_nested "$expected" expected with
  | Error error -> [ mismatch error.path error.message (Some expected) None ]
  | Ok () ->
      match first_duplicate_or_nested "$actual" actual with
      | Error error -> [ mismatch error.path error.message None (Some actual) ]
      | Ok () -> compare_expected ~exact "$" expected actual

type observation = {
  operation_supported : bool;
  adapter_registered : bool;
  built : bool;
  executed : bool;
  passed : bool;
  exit_code : int;
  status : status;
  passing_tests : int;
  children_reaped : bool;
  timed_out : bool;
  stdout_overflow : bool;
  stderr_overflow : bool;
  stdout : string;
  stderr : string;
  duration_ms : float;
  data : Yojson.Basic.t option;
}

let observation_projection observation =
  let base =
    [ ("operation_supported", `Bool observation.operation_supported);
      ("adapter_registered", `Bool observation.adapter_registered);
      ("built", `Bool observation.built); ("executed", `Bool observation.executed);
      ("passed", `Bool observation.passed); ("exit_code", `Int observation.exit_code);
      ("status", `String (string_of_status observation.status));
      ("passing_tests", `Int observation.passing_tests);
      ("children_reaped", `Bool observation.children_reaped);
      ("timed_out", `Bool observation.timed_out);
      ("stdout_overflow", `Bool observation.stdout_overflow);
      ("stderr_overflow", `Bool observation.stderr_overflow) ]
  in
  match observation.data with
  | Some (`Assoc fields) -> `Assoc (base @ fields)
  | Some value -> `Assoc (base @ [ ("data", value) ])
  | None -> `Assoc base

type identity = { change_id : string; commit_id : string; workspace : string }
type binding = { binding_path : string; binding_sha256 : string }
type receipt_limits = {
  receipt_timeout_ms : int;
  receipt_stdout_bytes : int;
  receipt_stderr_bytes : int;
  receipt_term_grace_ms : int;
}

type receipt = {
  receipt_id : string;
  task_id : string;
  case_id : string;
  operation : string;
  observed_at_utc : string;
  manifest : binding;
  candidate : identity;
  source : binding;
  limits : receipt_limits;
  observation : observation;
  assertion_passed : bool;
  assertion_mismatches : assertion_mismatch list;
  assertion_duration_ms : float;
  receipt_write_ms : float;
}

let mismatch_to_yojson item =
  `Assoc
    [ ("path", `String item.mismatch_path); ("reason", `String item.reason);
      ("expected", Option.value ~default:`Null item.expected_json);
      ("actual", Option.value ~default:`Null item.actual_json) ]

let observation_to_yojson observation =
  let raw_json = Option.map Yojson.Basic.to_string observation.data in
  `Assoc
    [ ("operation_supported", `Bool observation.operation_supported);
      ("adapter_registered", `Bool observation.adapter_registered);
      ("status", `String (string_of_status observation.status));
      ("exit_code", `Int observation.exit_code);
      ("passing_tests", `Int observation.passing_tests);
      ("children_reaped", `Bool observation.children_reaped);
      ("timed_out", `Bool observation.timed_out);
      ("stdout_overflow", `Bool observation.stdout_overflow);
      ("stderr_overflow", `Bool observation.stderr_overflow);
      ("stdout", `String observation.stdout);
      ("stderr", `String observation.stderr);
      ("stdout_sha256", `String (sha256_string observation.stdout));
      ("stderr_sha256", `String (sha256_string observation.stderr));
      ("raw_json", match raw_json with None -> `Null | Some value -> `String value);
      ("raw_json_sha256", match raw_json with None -> `Null | Some value -> `String (sha256_string value));
      ("duration_ms", `Float observation.duration_ms) ]

let receipt_to_yojson receipt =
  `Assoc
    [ ("schema", `String "uos.acceptance-receipt.v2");
      ("receipt_id", `String receipt.receipt_id);
      ("task_id", `String receipt.task_id); ("case_id", `String receipt.case_id);
      ("operation", `String receipt.operation);
      ("observed_at_utc", `String receipt.observed_at_utc);
      ("manifest", `Assoc [ ("path", `String receipt.manifest.binding_path);
                             ("sha256", `String receipt.manifest.binding_sha256) ]);
      ("candidate", `Assoc [ ("change_id", `String receipt.candidate.change_id);
                              ("commit_id", `String receipt.candidate.commit_id);
                              ("workspace", `String receipt.candidate.workspace) ]);
      ("source", `Assoc [ ("path", `String receipt.source.binding_path);
                           ("sha256", `String receipt.source.binding_sha256) ]);
      ("limits", `Assoc [ ("timeout_ms", `Int receipt.limits.receipt_timeout_ms);
                           ("stdout_bytes", `Int receipt.limits.receipt_stdout_bytes);
                           ("stderr_bytes", `Int receipt.limits.receipt_stderr_bytes);
                           ("term_grace_ms", `Int receipt.limits.receipt_term_grace_ms) ]);
      ("states", `Assoc [ ("built", `Bool receipt.observation.built);
                           ("executed", `Bool receipt.observation.executed);
                           ("passed", `Bool receipt.observation.passed) ]);
      ("observation", observation_to_yojson receipt.observation);
      ("assertion", `Assoc [ ("passed", `Bool receipt.assertion_passed);
                              ("mismatches", `List (List.map mismatch_to_yojson receipt.assertion_mismatches)) ]);
      ("timings", `Assoc [ ("operation_ms", `Float receipt.observation.duration_ms);
                            ("assertion_ms", `Float receipt.assertion_duration_ms);
                            ("receipt_write_ms", `Float receipt.receipt_write_ms) ]);
      ("system_admission_granted", `Bool false) ]
