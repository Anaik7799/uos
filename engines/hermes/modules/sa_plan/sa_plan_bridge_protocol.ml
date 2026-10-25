open! Core
open Result.Let_syntax
module Store = Sa_plan_store

let request_schema = "uos.sa-plan.bridge-bind-request.v1"
let response_schema = "uos.sa-plan.bridge-bind-response.v1"
let rejected_error = "bridge_request_rejected"
let max_request_bytes = 4096
let max_token_length = 240
let max_task_attempt = 2_147_483_647L
let max_lease_duration_ns = 300_000_000_000L

type operation =
  | Bind
  | Lookup

type request =
  { mapping_id : string
  ; plan_id : string
  ; task_id : string
  ; owner : string
  ; task_attempt : int
  ; lease_id : string
  ; expires_at_ns : int64
  }

type t =
  { operation : operation
  ; request : request
  }

let is_token_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '.' | '/' | ':' | '-' -> true
  | _ -> false

let is_known_key = function
  | "schema"
  | "mapping_id"
  | "plan_id"
  | "task_id"
  | "owner"
  | "task_attempt"
  | "lease_id"
  | "expires_at_ns" -> true
  | _ -> false

let validate_raw_json_tokens (raw : string) : (unit, string) result =
  let len = String.length raw in
  if len = 0 || len > max_request_bytes || not (Stdlib.String.is_valid_utf_8 raw)
  then Error rejected_error
  else (
    let rec scan_digits idx =
      if idx < len && Char.is_digit (String.get raw idx)
      then scan_digits (idx + 1)
      else idx
    in
    let rec loop idx in_string =
      if idx >= len
      then if in_string then Error rejected_error else Ok ()
      else (
        let ch = String.get raw idx in
        if in_string
        then (
          match ch with
          | '\\' ->
            if idx + 1 >= len then Error rejected_error else loop (idx + 2) true
          | '"' -> loop (idx + 1) false
          | _ -> loop (idx + 1) true)
        else (
          match ch with
          | '{' | '}' | ':' | ',' | ' ' | '\t' | '\n' | '\r' -> loop (idx + 1) false
          | '"' -> loop (idx + 1) true
          | '1' .. '9' ->
            let next_idx = scan_digits (idx + 1) in
            if next_idx < len
            then (
              match String.get raw next_idx with
              | '}' | ',' | ' ' | '\t' | '\n' | '\r' -> loop next_idx false
              | _ -> Error rejected_error)
            else Ok ()
          | _ -> Error rejected_error))
    in
    loop 0 false)

let parse_token_string (json : Yojson.Safe.t) : (string, string) result =
  match json with
  | `String s ->
    let len = String.length s in
    if len >= 1
       && len <= max_token_length
       && (not (String.is_substring s ~substring:".."))
       && String.for_all s ~f:is_token_char
    then Ok s
    else Error rejected_error
  | _ -> Error rejected_error

let parse_positive_int64 (json : Yojson.Safe.t) : (int64, string) result =
  match json with
  | `Int n -> if n > 0 then Ok (Int64.of_int n) else Error rejected_error
  | `Intlit s ->
    let len = String.length s in
    if len >= 1
       && Char.( >= ) (String.get s 0) '1'
       && Char.( <= ) (String.get s 0) '9'
       && String.for_all s ~f:Char.is_digit
    then (
      try
        let v = Int64.of_string s in
        if Int64.(v > 0L) && String.equal (Int64.to_string v) s
        then Ok v
        else Error rejected_error
      with
      | _ -> Error rejected_error)
    else Error rejected_error
  | _ -> Error rejected_error

let parse_task_attempt (json : Yojson.Safe.t) : (int, string) result =
  let%bind v = parse_positive_int64 json in
  if Int64.(v >= 1L && v <= max_task_attempt)
  then (
    match Int64.to_int v with
    | Some n -> Ok n
    | None -> Error rejected_error)
  else Error rejected_error

let decode (operation : operation) (raw : string) : (t, string) result =
  try
    let%bind () = validate_raw_json_tokens raw in
    let json = Yojson.Safe.from_string raw in
    match json with
    | `Assoc fields ->
      let%bind field_map =
        List.fold_result fields ~init:String.Map.empty ~f:(fun acc (key, value) ->
          if (not (is_known_key key)) || Map.mem acc key
          then Error rejected_error
          else Ok (Map.set acc ~key ~data:value))
      in
      let%bind () =
        if Int.equal (Map.length field_map) 8 then Ok () else Error rejected_error
      in
      let find_field key =
        match Map.find field_map key with
        | Some v -> Ok v
        | None -> Error rejected_error
      in
      let%bind schema_json = find_field "schema" in
      let%bind () =
        match schema_json with
        | `String s when String.equal s request_schema -> Ok ()
        | _ -> Error rejected_error
      in
      let%bind mapping_id = Result.bind (find_field "mapping_id") ~f:parse_token_string in
      let%bind plan_id = Result.bind (find_field "plan_id") ~f:parse_token_string in
      let%bind task_id = Result.bind (find_field "task_id") ~f:parse_token_string in
      let%bind owner = Result.bind (find_field "owner") ~f:parse_token_string in
      let%bind task_attempt = Result.bind (find_field "task_attempt") ~f:parse_task_attempt in
      let%bind lease_id = Result.bind (find_field "lease_id") ~f:parse_token_string in
      let%bind expires_at_ns = Result.bind (find_field "expires_at_ns") ~f:parse_positive_int64 in
      Ok
        { operation
        ; request =
            { mapping_id
            ; plan_id
            ; task_id
            ; owner
            ; task_attempt
            ; lease_id
            ; expires_at_ns
            }
        }
    | _ -> Error rejected_error
  with
  | _ -> Error rejected_error

let yojson_of_int64 (v : int64) : Yojson.Safe.t =
  match Int64.to_int v with
  | Some n -> `Int n
  | None -> `Intlit (Int64.to_string v)

let validate_mapping (req : request) (mapping : Store.bridge_mapping)
  : (unit, string) result
  =
  match mapping.domain, mapping.sa_plan_id, mapping.sa_task_id with
  | Sa_plan, Some plan_id, Some task_id
    when String.equal plan_id req.plan_id && String.equal task_id req.task_id -> Ok ()
  | (Sa_plan | Otp_parity | Infranodus | Documentation | Fdc), _, _ ->
    Error rejected_error

let validate_lease (req : request) (lease : Store.bridge_lease) : (unit, string) result =
  if String.equal lease.mapping_id req.mapping_id
     && String.equal lease.owner req.owner
     && String.equal lease.lease_id req.lease_id
     && Option.equal Int.equal lease.task_attempt (Some req.task_attempt)
     && Int64.equal lease.expires_at_ns req.expires_at_ns
     && Int64.(lease.fencing_token > 0L)
  then Ok ()
  else Error rejected_error

let lease_to_yojson (req : request) (lease : Store.bridge_lease) : Yojson.Safe.t =
  `Assoc
    [ "mapping_id", `String lease.mapping_id
    ; "plan_id", `String req.plan_id
    ; "task_id", `String req.task_id
    ; "owner", `String lease.owner
    ; "task_attempt", `Int req.task_attempt
    ; "lease_id", `String lease.lease_id
    ; "fencing_token", yojson_of_int64 lease.fencing_token
    ; "expires_at_ns", yojson_of_int64 lease.expires_at_ns
    ]

let response_to_yojson
  ~(found : bool)
  ~(historical : bool)
  ~(observed_at_ns : int64)
  ~(lease : Yojson.Safe.t)
  : Yojson.Safe.t
  =
  `Assoc
    [ "schema", `String response_schema
    ; "found", `Bool found
    ; "historical", `Bool historical
    ; "observed_at_ns", yojson_of_int64 observed_at_ns
    ; "lease", lease
    ]

let execute_in_tx (store : Store.t) (t : t) ~(observe_now : unit -> int64)
  : (Yojson.Safe.t, string) result
  =
  let now_ns = observe_now () in
  let%bind () = if Int64.(now_ns >= 0L) then Ok () else Error rejected_error in
  let req = t.request in
  let%bind mapping_opt =
    Result.map_error (Store.find_bridge_mapping store ~id:req.mapping_id) ~f:(fun _ ->
      rejected_error)
  in
  let%bind (mapping : Store.bridge_mapping) =
    match mapping_opt with
    | Some mapping -> Ok mapping
    | None -> Error rejected_error
  in
  let%bind () = validate_mapping req mapping in
  match t.operation with
  | Bind ->
    let%bind lease_ns =
      if Int64.(req.expires_at_ns > now_ns)
      then (
        let duration_ns = Int64.(req.expires_at_ns - now_ns) in
        if Int64.(duration_ns > 0L && duration_ns <= max_lease_duration_ns)
        then Ok duration_ns
        else Error rejected_error)
      else Error rejected_error
    in
    let%bind (lease : Store.bridge_lease) =
      Result.map_error
        (Store.bind_bridge_to_claimed_task
           store
           ~mapping_id:req.mapping_id
           ~owner:req.owner
           ~expected_attempt:req.task_attempt
           ~lease_id:req.lease_id
           ~now_ns
           ~lease_ns)
        ~f:(fun _ -> rejected_error)
    in
    let%bind () = validate_lease req lease in
    Ok
      (response_to_yojson
         ~found:true
         ~historical:false
         ~observed_at_ns:now_ns
         ~lease:(lease_to_yojson req lease))
  | Lookup ->
    let%bind lease_opt =
      Result.map_error
        (Store.find_bridge_lease store ~mapping_id:req.mapping_id)
        ~f:(fun _ -> rejected_error)
    in
    (match lease_opt with
     | None ->
       Ok
         (response_to_yojson
            ~found:false
            ~historical:true
            ~observed_at_ns:now_ns
            ~lease:`Null)
     | Some (lease : Store.bridge_lease) ->
       let%bind () = validate_lease req lease in
       Ok
         (response_to_yojson
            ~found:true
            ~historical:true
            ~observed_at_ns:now_ns
            ~lease:(lease_to_yojson req lease)))

let execute_observed (store : Store.t) (t : t) ~(observe_now : unit -> int64)
  : (Yojson.Safe.t, string) result
  =
  try
    match
      Store.with_transaction store (fun () ->
        try execute_in_tx store t ~observe_now with
        | _ -> Error rejected_error)
    with
    | Ok response -> Ok response
    | Error _ -> Error rejected_error
  with
  | _ -> Error rejected_error

let execute (store : Store.t) (t : t) ~(now_ns : int64) : (Yojson.Safe.t, string) result =
  execute_observed store t ~observe_now:(fun () -> now_ns)
