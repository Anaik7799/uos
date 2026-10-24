open! Core
module Store = Sa_plan_store

type operation =
  | Cancel
  | Lookup
[@@deriving sexp_of, compare, equal]

type t =
  { operation : operation
  ; request : Store.job_cancellation
  }

let max_request_bytes = 8192
let max_token_bytes = 240
let max_reason_bytes = 256
let hex_digest_bytes = 64
let max_target_attempt_int64 = 2_147_483_647L

let request_schema = "uos.sa-plan.cancel-job-request.v1"
let response_schema = "uos.sa-plan.cancel-job-response.v1"
let expected_result_operation = "cancel_job_lease"

let expected_request_keys =
  String.Set.of_list
    [ "schema"
    ; "mapping_id"
    ; "effect_id"
    ; "intent_sha256"
    ; "owner"
    ; "lease_id"
    ; "fencing_token"
    ; "target_job_id"
    ; "target_worker"
    ; "target_attempt"
    ; "target_lease_until_ns"
    ; "reason"
    ; "expires_at_ns"
    ]
;;

let required_result_keys =
  String.Set.of_list
    [ "schema"
    ; "operation"
    ; "status"
    ; "job_lease_cleared"
    ; "task_cancelled"
    ; "process_quiesced"
    ; "effect_id"
    ; "intent_sha256"
    ; "job_id"
    ; "matched_attempt"
    ]
;;

let is_valid_utf8 = Stdlib.String.is_valid_utf_8

let is_token_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' | '/' | ':' -> true
  | _ -> false
;;

let is_valid_token_id (s : string) : bool =
  let len = String.length s in
  len >= 1
  && len <= max_token_bytes
  && (not (String.is_substring s ~substring:".."))
  && String.for_all s ~f:is_token_char
;;

let is_lower_hex_char = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false
;;

let is_valid_hex64 (s : string) : bool =
  String.length s = hex_digest_bytes && String.for_all s ~f:is_lower_hex_char
;;

let has_no_ascii_control_or_del (s : string) : bool =
  String.for_all s ~f:(fun c ->
    let code = Char.to_int c in
    code >= 0x20 && code <> 0x7F)
;;

let is_valid_reason (s : string) : bool =
  let len = String.length s in
  len >= 1
  && len <= max_reason_bytes
  && is_valid_utf8 s
  && has_no_ascii_control_or_del s
  && not (String.is_empty (String.strip s))
;;

let is_canonical_base10_int (s : string) : bool =
  let len = String.length s in
  if len = 0
  then false
  else (
    let start = if Char.equal (String.get s 0) '-' then 1 else 0 in
    let digits = len - start in
    if digits <= 0
    then false
    else if digits > 1 && Char.equal (String.get s start) '0'
    then false
    else if start = 1 && Char.equal (String.get s 1) '0'
    then false
    else (
      let rec check i =
        if i >= len
        then true
        else if Char.is_digit (String.get s i)
        then check (i + 1)
        else false
      in
      check start))
;;

let parse_int64_strict (json : Yojson.Safe.t) : (int64, string) Result.t =
  let of_literal s =
    if not (is_canonical_base10_int s)
    then Error "invalid_integer"
    else (
      try
        let v = Int64.of_string s in
        if String.equal (Int64.to_string v) s
        then Ok v
        else Error "integer_overflow"
      with
      | _ -> Error "integer_overflow")
  in
  match json with
  | `Int n -> of_literal (Int.to_string n)
  | `Intlit s -> of_literal s
  | _ -> Error "invalid_integer"
;;

let parse_target_attempt (json : Yojson.Safe.t) : (int, string) Result.t =
  match parse_int64_strict json with
  | Error _ as err -> err
  | Ok v ->
    if Int64.(v <= 0L || v > max_target_attempt_int64)
    then Error "invalid_target_attempt"
    else (
      match Int64.to_int v with
      | Some attempt when attempt > 0 -> Ok attempt
      | _ -> Error "invalid_target_attempt")
;;

let parse_string_strict (json : Yojson.Safe.t) : (string, string) Result.t =
  match json with
  | `String s -> Ok s
  | _ -> Error "invalid_string_field"
;;

let parse_token_field (map : Yojson.Safe.t String.Map.t) (key : string)
  : (string, string) Result.t
  =
  match Map.find map key with
  | None -> Error "missing_request_field"
  | Some json ->
    (match parse_string_strict json with
     | Error _ as err -> err
     | Ok s -> if is_valid_token_id s then Ok s else Error "invalid_token_id")
;;

let parse_hex64_field (map : Yojson.Safe.t String.Map.t) (key : string)
  : (string, string) Result.t
  =
  match Map.find map key with
  | None -> Error "missing_request_field"
  | Some json ->
    (match parse_string_strict json with
     | Error _ as err -> err
     | Ok s -> if is_valid_hex64 s then Ok s else Error "invalid_hex_digest")
;;

let parse_positive_int64_field (map : Yojson.Safe.t String.Map.t) (key : string)
  : (int64, string) Result.t
  =
  match Map.find map key with
  | None -> Error "missing_request_field"
  | Some json ->
    (match parse_int64_strict json with
     | Error _ as err -> err
     | Ok v -> if Int64.(v > 0L) then Ok v else Error "non_positive_integer")
;;

let closed_assoc_map (fields : (string * Yojson.Safe.t) list)
  : (Yojson.Safe.t String.Map.t, string) Result.t
  =
  match String.Map.of_alist fields with
  | `Duplicate_key _ -> Error "duplicate_json_key"
  | `Ok map -> Ok map
;;

let decode (operation : operation) (raw : string) : (t, string) Result.t =
  let len = String.length raw in
  if len = 0 || len > max_request_bytes || not (is_valid_utf8 raw)
  then Error "invalid_request_frame"
  else (
    match
      try Ok (Yojson.Safe.from_string raw) with
      | _ -> Error "malformed_json"
    with
    | Error _ as err -> err
    | Ok (`Assoc fields) ->
      let open Result.Let_syntax in
      let%bind map = closed_assoc_map fields in
      if not (Set.equal (Map.key_set map) expected_request_keys)
      then Error "invalid_request_keys"
      else (
        let%bind schema =
          match Map.find map "schema" with
          | Some (`String s) -> Ok s
          | _ -> Error "invalid_schema"
        in
        if not (String.equal schema request_schema)
        then Error "unsupported_schema"
        else (
          let%bind mapping_id = parse_token_field map "mapping_id" in
          let%bind effect_id = parse_hex64_field map "effect_id" in
          let%bind intent_sha256 = parse_hex64_field map "intent_sha256" in
          let%bind owner = parse_token_field map "owner" in
          let%bind lease_id = parse_token_field map "lease_id" in
          let%bind fencing_token = parse_positive_int64_field map "fencing_token" in
          let%bind target_job_id = parse_token_field map "target_job_id" in
          let%bind target_worker = parse_token_field map "target_worker" in
          let%bind target_attempt =
            match Map.find map "target_attempt" with
            | None -> Error "missing_request_field"
            | Some json -> parse_target_attempt json
          in
          let%bind target_lease_until_ns =
            parse_positive_int64_field map "target_lease_until_ns"
          in
          let%bind expires_at_ns = parse_positive_int64_field map "expires_at_ns" in
          if Int64.(target_lease_until_ns <= expires_at_ns)
          then Error "invalid_lease_window"
          else (
            let%bind reason =
              match Map.find map "reason" with
              | Some (`String s) when is_valid_reason s -> Ok s
              | _ -> Error "invalid_reason"
            in
            let request =
              { Store.mapping_id
              ; effect_id
              ; intent_sha256
              ; owner
              ; lease_id
              ; fencing_token
              ; target_job_id
              ; target_worker
              ; target_attempt
              ; target_lease_until_ns
              ; reason
              ; expires_at_ns
              }
            in
            Ok { operation; request })))
    | Ok _ -> Error "invalid_json_root")
;;

let verify_store_result_payload
      (request : Store.job_cancellation)
      (raw_result : string)
  : (Yojson.Safe.t, string) Result.t
  =
  let len = String.length raw_result in
  if len = 0 || len > max_request_bytes || not (is_valid_utf8 raw_result)
  then Error "invalid_cancellation_receipt"
  else (
    match
      try Ok (Yojson.Safe.from_string raw_result) with
      | _ -> Error "invalid_cancellation_receipt"
    with
    | Error _ as err -> err
    | Ok (`Assoc fields as parsed) ->
      (match closed_assoc_map fields with
       | Error _ -> Error "invalid_cancellation_receipt"
       | Ok map ->
         let keys = Map.key_set map in
         if not (Set.equal keys required_result_keys)         then Error "invalid_cancellation_receipt"
         else (
           let matched_attempt_ok =
             match Map.find map "matched_attempt" with
             | Some json ->
               (match parse_target_attempt json with
                | Ok n -> Int.equal n request.target_attempt
                | Error _ -> false)
             | None -> false
           in
           let fields_ok =
             (match Map.find map "operation" with
              | Some (`String s) -> String.equal s expected_result_operation
              | _ -> false)
             && (match Map.find map "schema" with
                 | Some (`String s) -> String.equal s "uos.sa-plan.cancel-job-once.receipt.v1"
                 | _ -> false)
             && (match Map.find map "status" with
                 | Some (`String s) -> String.equal s "job_lease_revoked"
                 | _ -> false)
             && (match Map.find map "job_lease_cleared" with
                 | Some (`Bool true) -> true
                 | _ -> false)
             && (match Map.find map "task_cancelled" with
                 | Some (`Bool false) -> true
                 | _ -> false)
             && (match Map.find map "process_quiesced" with
                 | Some (`Bool false) -> true
                 | _ -> false)
             && (match Map.find map "effect_id" with
                 | Some (`String s) -> String.equal s request.effect_id
                 | _ -> false)
             && (match Map.find map "intent_sha256" with
                 | Some (`String s) -> String.equal s request.intent_sha256
                 | _ -> false)
             && (match Map.find map "job_id" with
                 | Some (`String s) -> String.equal s request.target_job_id
                 | _ -> false)
             && matched_attempt_ok
           in
           if fields_ok then Ok parsed else Error "invalid_cancellation_receipt"))
    | Ok _ -> Error "invalid_cancellation_receipt")
;;

let encode_verified_receipt
      (request : Store.job_cancellation)
      (receipt : Store.bridge_command_receipt)
  : (Yojson.Safe.t, string) Result.t
  =
  let { Store.mapping_id
      ; command_id
      ; request_hash
      ; recorded_at_ns
      ; replayed
      ; result
      }
    =
    receipt
  in
  if (not (String.equal mapping_id request.mapping_id))
     || (not (is_valid_token_id mapping_id))
     || (not (String.equal command_id ("cancel-job:" ^ request.effect_id)))
     || (not (is_valid_hex64 request_hash))
     || Int64.(recorded_at_ns < 0L)
  then Error "invalid_cancellation_receipt"
  else (
    match verify_store_result_payload request result with
    | Error _ -> Error "invalid_cancellation_receipt"
    | Ok result_json ->
      Ok
        (`Assoc
          [ "mapping_id", `String mapping_id
          ; "command_id", `String command_id
          ; "request_hash", `String request_hash
          ; "recorded_at_ns", `Intlit (Int64.to_string recorded_at_ns)
          ; "replayed", `Bool replayed
          ; "result", result_json
          ]))
;;

let build_response ~(found : bool) ~(historical : bool) ~(receipt : Yojson.Safe.t)
  : Yojson.Safe.t
  =
  `Assoc
    [ "schema", `String response_schema
    ; "found", `Bool found
    ; "historical", `Bool historical
    ; "receipt", receipt
    ]
;;

let execute (store : Store.t) (t : t) ~(now_ns : int64)
  : (Yojson.Safe.t, string) Result.t
  =
  if Int64.(now_ns < 0L)
  then Error "invalid_clock"
  else (
    match t.operation with
    | Cancel ->
      (match
         try Store.cancel_job_once store t.request ~now_ns with
         | _ -> Error "cancellation_refused"
       with
       | Error _ -> Error "cancellation_refused"
       | Ok receipt ->
         (match encode_verified_receipt t.request receipt with
          | Error _ -> Error "invalid_cancellation_receipt"
          | Ok receipt_json ->
            Ok (build_response ~found:true ~historical:false ~receipt:receipt_json)))
    | Lookup ->
      (match
         try Store.lookup_job_cancellation store t.request ~now_ns with
         | _ -> Error "cancellation_refused"
       with
       | Error _ -> Error "cancellation_refused"
       | Ok None -> Ok (build_response ~found:false ~historical:true ~receipt:`Null)
       | Ok (Some receipt) ->
         (match encode_verified_receipt t.request receipt with
          | Error _ -> Error "invalid_cancellation_receipt"
          | Ok receipt_json ->
            Ok (build_response ~found:true ~historical:true ~receipt:receipt_json))))
;;

let execute_observed store command ~observe_now =
  match Store.with_transaction store (fun () ->
    let now_ns = observe_now () in
    execute store command ~now_ns) with
  | Ok response -> Ok response
  | Error _ -> Error "cancellation_refused"
