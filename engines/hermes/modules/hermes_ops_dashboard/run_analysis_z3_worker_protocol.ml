type sha256 = string

let digest_bytes bytes =
  bytes |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let sha256_to_hex digest = digest

let valid_digest value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let digest_fields tag fields =
  String.concat "\x1f" (tag :: fields) |> digest_bytes

type limits = {
  virtual_memory_bytes : int64;
  cpu_seconds : int;
  maximum_query_bytes : int;
  maximum_output_bytes : int;
  limits_digest : sha256;
}

let limits_digest ~virtual_memory_bytes ~cpu_seconds ~maximum_query_bytes
    ~maximum_output_bytes =
  digest_fields "hermes-linked-z3-limits-v1"
    [ Int64.to_string virtual_memory_bytes; string_of_int cpu_seconds;
      string_of_int maximum_query_bytes; string_of_int maximum_output_bytes ]

let make_limits ~virtual_memory_bytes ~cpu_seconds ~maximum_query_bytes
    ~maximum_output_bytes =
  let errors = ref [] in
  let reject condition message = if condition then errors := message :: !errors in
  reject (Int64.compare virtual_memory_bytes 0L <= 0)
    "virtual-memory limit must be positive";
  reject (cpu_seconds <= 0) "CPU limit must be positive";
  reject (maximum_query_bytes <= 0 || maximum_query_bytes > 16_777_216)
    "query bound must be within 1..16777216 bytes";
  reject (maximum_output_bytes < 4096 || maximum_output_bytes > 1_048_576)
    "output bound must be within 4096..1048576 bytes";
  match List.rev !errors with
  | _ :: _ as errors -> Error errors
  | [] ->
      let limits_digest =
        limits_digest ~virtual_memory_bytes ~cpu_seconds ~maximum_query_bytes
          ~maximum_output_bytes
      in
      Ok
        { virtual_memory_bytes; cpu_seconds; maximum_query_bytes;
          maximum_output_bytes; limits_digest }

type group_policy = Own_process_group

type request = {
  protocol_version : string;
  obligation_id : string;
  worker_executable_digest : sha256;
  query_digest : sha256;
  query_bytes : int;
  limits : limits;
  group_policy : group_policy;
  request_digest : sha256;
}

type prepared_request = { request : request; query : string }

let protocol_version = "hermes-linked-z3-worker-v1"

let valid_identifier value =
  let width = String.length value in
  width > 0 && width <= 128
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | '_' | '-' -> true
         | _ -> false)
       value

let request_digest ~obligation_id ~worker_executable_digest ~query_digest
    ~query_bytes ~limits =
  digest_fields "hermes-linked-z3-request-v1"
    [ protocol_version; obligation_id; worker_executable_digest; query_digest;
      string_of_int query_bytes; limits.limits_digest; "own-process-group" ]

let prepare ~obligation_id ~worker_executable_digest ~query ~limits =
  let errors = ref [] in
  let reject condition message = if condition then errors := message :: !errors in
  reject (not (valid_identifier obligation_id)) "invalid obligation identifier";
  reject (not (valid_digest worker_executable_digest))
    "invalid worker executable digest";
  let query_bytes = String.length query in
  reject (query_bytes = 0) "query must not be empty";
  reject (query_bytes > limits.maximum_query_bytes) "query exceeds declared bound";
  match List.rev !errors with
  | _ :: _ as errors -> Error errors
  | [] ->
      let query_digest = digest_bytes query in
      let request_digest =
        request_digest ~obligation_id ~worker_executable_digest ~query_digest
          ~query_bytes ~limits
      in
      let request =
        { protocol_version; obligation_id; worker_executable_digest;
          query_digest; query_bytes; limits; group_policy = Own_process_group;
          request_digest }
      in
      Ok { request; query }

let argv prepared =
  let request = prepared.request in
  [| "--protocol"; request.protocol_version;
     "--obligation"; request.obligation_id;
     "--worker-executable-digest";
     sha256_to_hex request.worker_executable_digest;
     "--query-digest"; sha256_to_hex request.query_digest;
     "--query-bytes"; string_of_int request.query_bytes;
     "--virtual-memory-bytes"; Int64.to_string request.limits.virtual_memory_bytes;
     "--cpu-seconds"; string_of_int request.limits.cpu_seconds;
     "--maximum-query-bytes"; string_of_int request.limits.maximum_query_bytes;
     "--maximum-output-bytes"; string_of_int request.limits.maximum_output_bytes;
     "--limits-digest"; sha256_to_hex request.limits.limits_digest;
     "--group-policy"; "own-process-group";
     "--request-digest"; sha256_to_hex request.request_digest |]

let stdin_bytes prepared = prepared.query

type error =
  | Invalid_argv of string
  | Invalid_field of string
  | Invalid_digest of string
  | Query_too_large
  | Query_length_mismatch
  | Query_digest_mismatch
  | Frame_malformed of string
  | Frame_too_large
  | Protocol_unavailable

let render_error = function
  | Invalid_argv detail -> "invalid argv: " ^ detail
  | Invalid_field detail -> "invalid field: " ^ detail
  | Invalid_digest detail -> "invalid digest: " ^ detail
  | Query_too_large -> "query too large"
  | Query_length_mismatch -> "query length mismatch"
  | Query_digest_mismatch -> "query digest mismatch"
  | Frame_malformed detail -> "malformed frame: " ^ detail
  | Frame_too_large -> "frame too large"
  | Protocol_unavailable -> "protocol unavailable"

let sha256_of_hex value =
  if valid_digest value then Ok value else Error (Invalid_digest "sha256")

let decode_argv values =
  let expected_labels =
    [| "--protocol"; "--obligation"; "--worker-executable-digest";
       "--query-digest"; "--query-bytes"; "--virtual-memory-bytes";
       "--cpu-seconds"; "--maximum-query-bytes"; "--maximum-output-bytes";
       "--limits-digest"; "--group-policy"; "--request-digest" |]
  in
  if Array.length values <> Array.length expected_labels * 2 then
    Error (Invalid_argv "wrong argument count")
  else
    let rec labels index =
      if index = Array.length expected_labels then Ok ()
      else if String.equal values.(index * 2) expected_labels.(index) then
        labels (index + 1)
      else Error (Invalid_argv ("unexpected option " ^ values.(index * 2)))
    in
    match labels 0 with
    | Error _ as error -> error
    | Ok () ->
        let value index = values.((index * 2) + 1) in
        let parse_int label text =
          match int_of_string_opt text with
          | Some value -> Ok value
          | None -> Error (Invalid_field label)
        in
        let parse_int64 label text =
          match Int64.of_string_opt text with
          | Some value -> Ok value
          | None -> Error (Invalid_field label)
        in
        begin match
          parse_int "query-bytes" (value 4),
          parse_int64 "virtual-memory-bytes" (value 5),
          parse_int "cpu-seconds" (value 6),
          parse_int "maximum-query-bytes" (value 7),
          parse_int "maximum-output-bytes" (value 8)
        with
        | Ok query_bytes, Ok virtual_memory_bytes, Ok cpu_seconds,
          Ok maximum_query_bytes, Ok maximum_output_bytes ->
            let worker_executable_digest = value 2 in
            let query_digest = value 3 in
            let declared_limits_digest = value 9 in
            let declared_request_digest = value 11 in
            if not (String.equal (value 0) protocol_version) then
              Error (Invalid_field "protocol-version")
            else if not (valid_identifier (value 1)) then
              Error (Invalid_field "obligation-id")
            else if not (valid_digest worker_executable_digest) then
              Error (Invalid_digest "worker-executable")
            else if not (valid_digest query_digest) then
              Error (Invalid_digest "query")
            else if not (valid_digest declared_limits_digest) then
              Error (Invalid_digest "limits")
            else if not (valid_digest declared_request_digest) then
              Error (Invalid_digest "request")
            else if not (String.equal (value 10) "own-process-group") then
              Error (Invalid_field "group-policy")
            else begin
              match
                make_limits ~virtual_memory_bytes ~cpu_seconds
                  ~maximum_query_bytes ~maximum_output_bytes
              with
              | Error errors -> Error (Invalid_field (String.concat "; " errors))
              | Ok limits ->
                  if not (String.equal limits.limits_digest declared_limits_digest)
                  then Error (Invalid_digest "limits identity mismatch")
                  else if query_bytes <= 0 || query_bytes > maximum_query_bytes then
                    Error (Invalid_field "query-bytes")
                  else
                    let obligation_id = value 1 in
                    let expected =
                      request_digest ~obligation_id ~worker_executable_digest
                        ~query_digest ~query_bytes ~limits
                    in
                    if not (String.equal expected declared_request_digest) then
                      Error (Invalid_digest "request identity mismatch")
                    else
                      Ok
                        { protocol_version; obligation_id;
                          worker_executable_digest; query_digest; query_bytes;
                          limits; group_policy = Own_process_group;
                          request_digest = declared_request_digest }
            end
        | Error error, _, _, _, _ | _, Error error, _, _, _
        | _, _, Error error, _, _ | _, _, _, Error error, _
        | _, _, _, _, Error error -> Error error
        end

type admitted_query = { bytes : string; digest : sha256; length : int }

let admit_stdin request bytes =
  let length = String.length bytes in
  if length > request.limits.maximum_query_bytes then Error Query_too_large
  else if length <> request.query_bytes then Error Query_length_mismatch
  else
    let digest = digest_bytes bytes in
    if not (String.equal digest request.query_digest) then
      Error Query_digest_mismatch
    else Ok { bytes; digest; length }

let resource_requirements ~worker_path ~expected =
  Resource_envelope.
    [ Exact_executable { path = worker_path; expected };
      Kernel_capability Proc_self_fd_executable;
      Kernel_capability Rlimit_as;
      Kernel_capability Process_group_signalling ]

type limit_value = Finite of int64 | Infinite
type limit_observation = { current : limit_value; maximum : limit_value }

type applied_limit = {
  requested : int64;
  before : limit_observation;
  after : limit_observation;
  applied : bool;
}

type worker_object = {
  identity : Resource_envelope.executable_identity;
  bytes : int;
  digest : sha256;
}

type handshake = {
  protocol_version : string;
  request_digest : sha256;
  declared_query_digest : sha256;
  declared_query_bytes : int;
  object_before : worker_object;
  object_after : worker_object;
  virtual_memory : applied_limit;
  cpu : applied_limit;
  process_id : int;
  process_group_id : int;
  group_policy : group_policy;
  handshake_digest : sha256;
}

let limit_value_string = function
  | Finite value -> Int64.to_string value
  | Infinite -> "infinite"

let identity_fields (identity : Resource_envelope.executable_identity) =
  [ string_of_int identity.device; string_of_int identity.inode ]

let object_fields object_ =
  identity_fields object_.identity
  @ [ string_of_int object_.bytes; object_.digest ]

let observation_fields observation =
  [ limit_value_string observation.current;
    limit_value_string observation.maximum ]

let applied_fields applied =
  Int64.to_string applied.requested
  :: string_of_bool applied.applied
  :: observation_fields applied.before @ observation_fields applied.after

let handshake_digest handshake =
  digest_fields "hermes-linked-z3-handshake-v1"
    ([ handshake.protocol_version; handshake.request_digest;
       handshake.declared_query_digest;
       string_of_int handshake.declared_query_bytes ]
     @ object_fields handshake.object_before
     @ object_fields handshake.object_after
     @ applied_fields handshake.virtual_memory @ applied_fields handshake.cpu
     @ [ string_of_int handshake.process_id;
         string_of_int handshake.process_group_id; "own-process-group" ])

let limit_applied requested applied =
  let finite_within = function
    | Finite value -> Int64.compare value 0L > 0 && Int64.compare value requested <= 0
    | Infinite -> false
  in
  applied.applied && Int64.equal applied.requested requested
  && finite_within applied.after.current

let worker_object_valid object_ =
  object_.identity.device >= 0 && object_.identity.inode > 0
  && object_.bytes > 0 && valid_digest object_.digest

let validate_handshake ~(request : request) (handshake : handshake) =
  let errors = ref [] in
  let reject condition message = if condition then errors := message :: !errors in
  reject (not (String.equal handshake.protocol_version request.protocol_version))
    "handshake protocol mismatch";
  reject (not (String.equal handshake.request_digest request.request_digest))
    "handshake request mismatch";
  reject
    (not (String.equal handshake.declared_query_digest request.query_digest))
    "handshake query digest mismatch";
  reject (handshake.declared_query_bytes <> request.query_bytes)
    "handshake query length mismatch";
  reject (not (worker_object_valid handshake.object_before))
    "invalid worker object before";
  reject (not (worker_object_valid handshake.object_after))
    "invalid worker object after";
  reject (handshake.object_before <> handshake.object_after)
    "worker executable object changed";
  reject
    (not
       (String.equal handshake.object_before.digest
          request.worker_executable_digest))
    "worker executable digest mismatch";
  reject
    (not
       (limit_applied request.limits.virtual_memory_bytes
          handshake.virtual_memory))
    "RLIMIT_AS was not applied";
  reject
    (not (limit_applied (Int64.of_int request.limits.cpu_seconds) handshake.cpu))
    "RLIMIT_CPU was not applied";
  reject
    (handshake.process_id <= 0
     || handshake.process_group_id <> handshake.process_id)
    "worker does not own its process group";
  reject (handshake.group_policy <> Own_process_group)
    "worker group policy mismatch";
  reject
    (not (String.equal handshake.handshake_digest (handshake_digest handshake)))
    "handshake digest mismatch";
  List.rev !errors

type capture_receipt = {
  directory_object_before : Resource_envelope.executable_identity;
  directory_mode_before : int;
  file_object_before : Resource_envelope.executable_identity;
  file_object_after : Resource_envelope.executable_identity;
  file_mode_before : int;
  readback_digest : sha256;
  readback_bytes : int;
  file_removed : bool;
  directory_removed : bool;
}

type answer = Sat | Unsat | Unknown

type result = {
  request_digest : sha256;
  executed_query_digest : sha256;
  executed_query_bytes : int;
  handshake_digest : sha256;
  capture : capture_receipt;
  answer : answer;
  solver_id : string;
  solver_version : string;
  solver_call_delta : int;
  assertion_count : int;
  peak_rss_bytes : int64;
  result_digest : sha256;
}

let answer_string = function Sat -> "sat" | Unsat -> "unsat" | Unknown -> "unknown"

let capture_fields capture =
  identity_fields capture.directory_object_before
  @ [ string_of_int capture.directory_mode_before ]
  @ identity_fields capture.file_object_before
  @ identity_fields capture.file_object_after
  @ [ string_of_int capture.file_mode_before; capture.readback_digest;
      string_of_int capture.readback_bytes; string_of_bool capture.file_removed;
      string_of_bool capture.directory_removed ]

let result_digest result =
  digest_fields "hermes-linked-z3-result-v1"
    ([ result.request_digest; result.executed_query_digest;
       string_of_int result.executed_query_bytes; result.handshake_digest ]
     @ capture_fields result.capture
     @ [ answer_string result.answer; result.solver_id; result.solver_version;
         string_of_int result.solver_call_delta;
         string_of_int result.assertion_count;
         Int64.to_string result.peak_rss_bytes ])

let validate_result ~(request : request) ~(query : admitted_query)
    ~(handshake : handshake) (result : result) =
  let errors = ref [] in
  let reject condition message = if condition then errors := message :: !errors in
  reject (validate_handshake ~request handshake <> []) "invalid result handshake";
  reject (not (String.equal result.request_digest request.request_digest))
    "result request mismatch";
  reject (not (String.equal result.executed_query_digest query.digest))
    "executed query digest mismatch";
  reject (result.executed_query_bytes <> query.length)
    "executed query length mismatch";
  reject (not (String.equal result.handshake_digest handshake.handshake_digest))
    "result handshake mismatch";
  let capture = result.capture in
  reject (capture.directory_mode_before <> 0o700)
    "capture directory mode is not 0700";
  reject (capture.file_mode_before <> 0o600) "capture file mode is not 0600";
  reject (capture.file_object_before <> capture.file_object_after)
    "capture file object changed";
  reject (not (String.equal capture.readback_digest query.digest))
    "capture readback digest mismatch";
  reject (capture.readback_bytes <> query.length)
    "capture readback length mismatch";
  reject (not capture.file_removed || not capture.directory_removed)
    "capture was not removed";
  reject (not (String.equal result.solver_id "z3"))
    "solver id is not the linked Z3 authority";
  reject (String.trim result.solver_version = "") "missing solver version";
  reject (result.solver_call_delta <> 1) "solver call denominator is not one";
  reject (result.assertion_count <= 0) "assertion denominator is not positive";
  reject (Int64.compare result.peak_rss_bytes 0L <= 0)
    "peak RSS evidence is not positive";
  reject (not (String.equal result.result_digest (result_digest result)))
    "result digest mismatch";
  List.rev !errors

module Worker_evidence = struct
  let worker_object ~identity ~bytes ~digest =
    let value = { identity; bytes; digest } in
    if worker_object_valid value then Ok value
    else Error [ "invalid worker executable evidence" ]

  let limit_observation ~current ~maximum = { current; maximum }
  let applied_limit ~requested ~before ~after ~applied =
    { requested; before; after; applied }

  let handshake (request : request) ~object_before ~object_after ~virtual_memory ~cpu
      ~process_id ~process_group_id =
    let provisional =
      { protocol_version = request.protocol_version;
        request_digest = request.request_digest;
        declared_query_digest = request.query_digest;
        declared_query_bytes = request.query_bytes; object_before; object_after;
        virtual_memory; cpu; process_id; process_group_id;
        group_policy = Own_process_group; handshake_digest = "" }
    in
    let value =
      { provisional with handshake_digest = handshake_digest provisional }
    in
    match validate_handshake ~request value with
    | [] -> Ok value
    | errors -> Error errors

  let capture ~directory_object_before ~directory_mode_before
      ~file_object_before ~file_object_after ~file_mode_before ~readback_digest
      ~readback_bytes ~file_removed ~directory_removed =
    let value =
      { directory_object_before; directory_mode_before; file_object_before;
        file_object_after; file_mode_before; readback_digest; readback_bytes;
        file_removed; directory_removed }
    in
    let errors = ref [] in
    let reject condition message = if condition then errors := message :: !errors in
    reject (directory_mode_before <> 0o700) "capture directory mode is not 0700";
    reject (file_mode_before <> 0o600) "capture file mode is not 0600";
    reject (file_object_before <> file_object_after) "capture object changed";
    reject (not (valid_digest readback_digest)) "invalid capture digest";
    reject (readback_bytes <= 0) "invalid capture length";
    reject (not file_removed || not directory_removed) "capture remains present";
    match List.rev !errors with [] -> Ok value | errors -> Error errors

  let result ~(request : request) ~(query : admitted_query)
      ~(handshake : handshake) ~capture ~answer ~solver_id
      ~solver_version ~solver_call_delta ~assertion_count ~peak_rss_bytes =
    let provisional =
      { request_digest = request.request_digest;
        executed_query_digest = query.digest; executed_query_bytes = query.length;
        handshake_digest = handshake.handshake_digest; capture; answer; solver_id;
        solver_version; solver_call_delta; assertion_count; peak_rss_bytes;
        result_digest = "" }
    in
    let value = { provisional with result_digest = result_digest provisional } in
    match validate_result ~request ~query ~handshake value with
    | [] -> Ok value
    | errors -> Error errors
end

type refusal_reason =
  | Unsupported_capability of Resource_envelope.kernel_capability
  | Invalid_request
  | Query_rejected
  | Limit_application_failed
  | Group_setup_failed
  | Worker_identity_failed
  | Capture_failed
  | Solver_unavailable
  | Solver_failed
  | Output_limit_exceeded

type refusal = {
  request_digest : sha256 option;
  reason : refusal_reason;
  detail : string;
  refusal_digest : sha256;
}

let capability_name = function
  | Resource_envelope.Proc_self_fd_executable -> "proc-self-fd-executable"
  | Resource_envelope.Rlimit_as -> "rlimit-as"
  | Resource_envelope.Process_group_signalling -> "process-group-signalling"

let refusal_reason_name = function
  | Unsupported_capability capability ->
      "unsupported-capability:" ^ capability_name capability
  | Invalid_request -> "invalid-request"
  | Query_rejected -> "query-rejected"
  | Limit_application_failed -> "limit-application-failed"
  | Group_setup_failed -> "group-setup-failed"
  | Worker_identity_failed -> "worker-identity-failed"
  | Capture_failed -> "capture-failed"
  | Solver_unavailable -> "solver-unavailable"
  | Solver_failed -> "solver-failed"
  | Output_limit_exceeded -> "output-limit-exceeded"

let refusal_reason_of_string = function
  | "unsupported-capability:proc-self-fd-executable" ->
      Ok (Unsupported_capability Resource_envelope.Proc_self_fd_executable)
  | "unsupported-capability:rlimit-as" ->
      Ok (Unsupported_capability Resource_envelope.Rlimit_as)
  | "unsupported-capability:process-group-signalling" ->
      Ok (Unsupported_capability Resource_envelope.Process_group_signalling)
  | "invalid-request" -> Ok Invalid_request
  | "query-rejected" -> Ok Query_rejected
  | "limit-application-failed" -> Ok Limit_application_failed
  | "group-setup-failed" -> Ok Group_setup_failed
  | "worker-identity-failed" -> Ok Worker_identity_failed
  | "capture-failed" -> Ok Capture_failed
  | "solver-unavailable" -> Ok Solver_unavailable
  | "solver-failed" -> Ok Solver_failed
  | "output-limit-exceeded" -> Ok Output_limit_exceeded
  | value -> Error (Frame_malformed ("unknown refusal reason " ^ value))

let make_refusal ~request_digest reason ~detail =
  let detail = if String.length detail <= 512 then detail else String.sub detail 0 512 in
  let refusal_digest =
    digest_fields "hermes-linked-z3-refusal-v1"
      [ Option.value ~default:"none" request_digest;
        refusal_reason_name reason; detail ]
  in
  { request_digest; reason; detail; refusal_digest }

type frame = Handshake of handshake | Result of result | Refusal of refusal

let json_identity (identity : Resource_envelope.executable_identity) =
  `Assoc [ ("device", `Int identity.device); ("inode", `Int identity.inode) ]

let json_limit_value = function
  | Infinite -> `String "infinite"
  | Finite value -> `String (Int64.to_string value)

let json_observation observation =
  `Assoc [ ("current", json_limit_value observation.current);
           ("maximum", json_limit_value observation.maximum) ]

let json_applied applied =
  `Assoc
    [ ("requested", `String (Int64.to_string applied.requested));
      ("before", json_observation applied.before);
      ("after", json_observation applied.after);
      ("applied", `Bool applied.applied) ]

let json_object object_ =
  `Assoc
    [ ("identity", json_identity object_.identity); ("bytes", `Int object_.bytes);
      ("digest", `String object_.digest) ]

let json_capture capture =
  `Assoc
    [ ("directory_object_before", json_identity capture.directory_object_before);
      ("directory_mode_before", `Int capture.directory_mode_before);
      ("file_object_before", json_identity capture.file_object_before);
      ("file_object_after", json_identity capture.file_object_after);
      ("file_mode_before", `Int capture.file_mode_before);
      ("readback_digest", `String capture.readback_digest);
      ("readback_bytes", `Int capture.readback_bytes);
      ("file_removed", `Bool capture.file_removed);
      ("directory_removed", `Bool capture.directory_removed) ]

let encode_refusal (refusal : refusal) =
  `Assoc
    [ ("frame", `String "refusal");
      ("request_digest", Option.fold ~none:`Null ~some:(fun d -> `String d) refusal.request_digest);
      ("reason", `String (refusal_reason_name refusal.reason));
      ("detail", `String refusal.detail);
      ("refusal_digest", `String refusal.refusal_digest) ]
  |> Yojson.Safe.to_string

let encode_handshake (handshake : handshake) =
  `Assoc
    [ ("frame", `String "handshake");
      ("protocol_version", `String handshake.protocol_version);
      ("request_digest", `String handshake.request_digest);
      ("declared_query_digest", `String handshake.declared_query_digest);
      ("declared_query_bytes", `Int handshake.declared_query_bytes);
      ("object_before", json_object handshake.object_before);
      ("object_after", json_object handshake.object_after);
      ("virtual_memory", json_applied handshake.virtual_memory);
      ("cpu", json_applied handshake.cpu);
      ("process_id", `Int handshake.process_id);
      ("process_group_id", `Int handshake.process_group_id);
      ("group_policy", `String "own-process-group");
      ("handshake_digest", `String handshake.handshake_digest) ]
  |> Yojson.Safe.to_string

let encode_result (result : result) =
  `Assoc
    [ ("frame", `String "result");
      ("request_digest", `String result.request_digest);
      ("executed_query_digest", `String result.executed_query_digest);
      ("executed_query_bytes", `Int result.executed_query_bytes);
      ("handshake_digest", `String result.handshake_digest);
      ("capture", json_capture result.capture);
      ("answer", `String (answer_string result.answer));
      ("solver_id", `String result.solver_id);
      ("solver_version", `String result.solver_version);
      ("solver_call_delta", `Int result.solver_call_delta);
      ("assertion_count", `Int result.assertion_count);
      ("peak_rss_bytes", `String (Int64.to_string result.peak_rss_bytes));
      ("result_digest", `String result.result_digest) ]
  |> Yojson.Safe.to_string

let member name fields =
  match List.assoc_opt name fields with
  | Some value -> value
  | None -> raise (Invalid_argument ("missing field " ^ name))

let string name fields = Yojson.Safe.Util.to_string (member name fields)
let int name fields = Yojson.Safe.Util.to_int (member name fields)
let bool name fields = Yojson.Safe.Util.to_bool (member name fields)

let int64_string name fields =
  match Int64.of_string_opt (string name fields) with
  | Some value -> value
  | None -> raise (Invalid_argument ("invalid int64 field " ^ name))

let assoc = function
  | `Assoc fields -> fields
  | _ -> raise (Invalid_argument "object expected")

let identity_of_json json =
  let fields = assoc json in
  Resource_envelope.{ device = int "device" fields; inode = int "inode" fields }

let limit_value_of_json = function
  | `String "infinite" -> Infinite
  | `String value ->
      begin match Int64.of_string_opt value with
      | Some value -> Finite value
      | None -> raise (Invalid_argument "invalid limit value")
      end
  | _ -> raise (Invalid_argument "invalid limit value")

let observation_of_json json =
  let fields = assoc json in
  { current = limit_value_of_json (member "current" fields);
    maximum = limit_value_of_json (member "maximum" fields) }

let applied_of_json json =
  let fields = assoc json in
  { requested = int64_string "requested" fields;
    before = observation_of_json (member "before" fields);
    after = observation_of_json (member "after" fields);
    applied = bool "applied" fields }

let object_of_json json =
  let fields = assoc json in
  { identity = identity_of_json (member "identity" fields);
    bytes = int "bytes" fields; digest = string "digest" fields }

let capture_of_json json =
  let fields = assoc json in
  { directory_object_before = identity_of_json (member "directory_object_before" fields);
    directory_mode_before = int "directory_mode_before" fields;
    file_object_before = identity_of_json (member "file_object_before" fields);
    file_object_after = identity_of_json (member "file_object_after" fields);
    file_mode_before = int "file_mode_before" fields;
    readback_digest = string "readback_digest" fields;
    readback_bytes = int "readback_bytes" fields;
    file_removed = bool "file_removed" fields;
    directory_removed = bool "directory_removed" fields }

let decode_frame ~maximum_bytes bytes =
  if maximum_bytes <= 0 || String.length bytes > maximum_bytes then
    Error Frame_too_large
  else
    match Yojson.Safe.from_string bytes with
    | exception exn -> Error (Frame_malformed (Printexc.to_string exn))
    | json ->
        begin
          try
            let fields = assoc json in
            match string "frame" fields with
            | "handshake" ->
                let handshake =
                  { protocol_version = string "protocol_version" fields;
                    request_digest = string "request_digest" fields;
                    declared_query_digest = string "declared_query_digest" fields;
                    declared_query_bytes = int "declared_query_bytes" fields;
                    object_before = object_of_json (member "object_before" fields);
                    object_after = object_of_json (member "object_after" fields);
                    virtual_memory = applied_of_json (member "virtual_memory" fields);
                    cpu = applied_of_json (member "cpu" fields);
                    process_id = int "process_id" fields;
                    process_group_id = int "process_group_id" fields;
                    group_policy =
                      (if String.equal (string "group_policy" fields) "own-process-group"
                       then Own_process_group
                       else raise (Invalid_argument "invalid group policy"));
                    handshake_digest = string "handshake_digest" fields }
                in
                if not (valid_digest handshake.handshake_digest) then
                  Error (Invalid_digest "handshake")
                else Ok (Handshake handshake)
            | "result" ->
                let answer =
                  match string "answer" fields with
                  | "sat" -> Sat | "unsat" -> Unsat | "unknown" -> Unknown
                  | _ -> raise (Invalid_argument "invalid solver answer")
                in
                let result =
                  { request_digest = string "request_digest" fields;
                    executed_query_digest = string "executed_query_digest" fields;
                    executed_query_bytes = int "executed_query_bytes" fields;
                    handshake_digest = string "handshake_digest" fields;
                    capture = capture_of_json (member "capture" fields); answer;
                    solver_id = string "solver_id" fields;
                    solver_version = string "solver_version" fields;
                    solver_call_delta = int "solver_call_delta" fields;
                    assertion_count = int "assertion_count" fields;
                    peak_rss_bytes = int64_string "peak_rss_bytes" fields;
                    result_digest = string "result_digest" fields }
                in
                if not (valid_digest result.result_digest) then
                  Error (Invalid_digest "result")
                else Ok (Result result)
            | "refusal" ->
                let request_digest =
                  match member "request_digest" fields with
                  | `Null -> None
                  | `String digest when valid_digest digest -> Some digest
                  | _ -> raise (Invalid_argument "invalid refusal request digest")
                in
                begin match refusal_reason_of_string (string "reason" fields) with
                | Error _ as error -> error
                | Ok reason ->
                    let detail = string "detail" fields in
                    let refusal_digest = string "refusal_digest" fields in
                    let refusal = { request_digest; reason; detail; refusal_digest } in
                    let expected = make_refusal ~request_digest reason ~detail in
                    if String.length detail > 512
                       || not (String.equal refusal_digest expected.refusal_digest)
                    then Error (Invalid_digest "refusal")
                    else Ok (Refusal refusal)
                end
            | value -> Error (Frame_malformed ("unknown frame " ^ value))
          with exn -> Error (Frame_malformed (Printexc.to_string exn))
        end

type transcript =
  | Completed of { handshake : handshake; result : result }
  | Refused of refusal

let decode_transcript ~maximum_bytes bytes =
  if maximum_bytes <= 0 || String.length bytes > maximum_bytes then
    Error Frame_too_large
  else
    let lines =
      String.split_on_char '\n' bytes
      |> List.filter (fun line -> not (String.equal line ""))
    in
    match lines with
    | [ line ] ->
        begin match decode_frame ~maximum_bytes line with
        | Ok (Refusal refusal) -> Ok (Refused refusal)
        | Ok (Handshake _ | Result _) ->
            Error (Frame_malformed "incomplete successful transcript")
        | Error _ as error -> error
        end
    | [ handshake_line; result_line ] ->
        begin match decode_frame ~maximum_bytes handshake_line,
          decode_frame ~maximum_bytes result_line with
        | Ok (Handshake handshake), Ok (Result result) ->
            Ok (Completed { handshake; result })
        | Ok (Handshake _), Ok (Refusal refusal) -> Ok (Refused refusal)
        | Error error, _ | _, Error error -> Error error
        | _ -> Error (Frame_malformed "invalid frame order")
        end
    | _ -> Error (Frame_malformed "transcript must contain one or two frames")

type worker_exit = Completed_exit | Unsupported_exit | Rejected_exit | Failed_exit

let exit_code = function
  | Completed_exit -> 0
  | Unsupported_exit -> 20
  | Rejected_exit -> 21
  | Failed_exit -> 22
