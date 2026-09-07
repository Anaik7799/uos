(** E04 versioned adapter.  Load after [contract.ml], [process_supervisor.ml],
    [registry.ml], and [tools/source_review/census.ml].  Expected values are not
    present in this interface. *)

let decode_string_list path = function
  | `List values ->
      let rec loop index items = function
        | [] -> Ok (List.rev items)
        | `String value :: tail -> loop (index + 1) (value :: items) tail
        | _ :: _ -> contract_error (index_path path index) "expected string"
      in
      loop 0 [] values
  | _ -> contract_error path "expected array"

let decode_e04_given json =
  let path = "$.given" in
  match first_duplicate_or_nested path json with
  | Error _ as error -> error
  | Ok () ->
      match assoc_at path json with
      | Error _ as error -> error
      | Ok fields ->
          match exact_fields path [ "files"; "registered_tests"; "ast_sites"; "unreadable" ] fields with
          | Error _ as error -> error
          | Ok () ->
              let strings name = required_field path name fields decode_string_list in
              match strings "files", strings "registered_tests",
                    required_field path "ast_sites" fields int_at,
                    strings "unreadable" with
              | Ok files, Ok registered_tests, Ok ast_sites, Ok unreadable ->
                  Ok { files; registered_tests; ast_sites; unreadable }
              | Error error, _, _, _ | _, Error error, _, _
              | _, _, Error error, _ | _, _, _, Error error -> Error error

let census_classify_operation given =
  match decode_e04_given given with
  | Error error ->
      error_observation ~adapter_registered:true ~executed:false
        (string_of_contract_error error)
  | Ok input ->
      match classify input with
      | Error error ->
          error_observation ~adapter_registered:true ~executed:false
            (string_of_error error)
      | Ok summary ->
          { operation_supported = true; adapter_registered = true; built = true;
            executed = true; passed = true; exit_code = 0; status = Status_pass;
            passing_tests = 1; children_reaped = true; timed_out = false;
            stdout_overflow = false; stderr_overflow = false; stdout = "";
            stderr = ""; duration_ms = 0.; data = Some (summary_to_yojson summary);
            applied_limits = no_process_limits }

let e04_supported_operation = ("census.classify", census_classify_operation)

