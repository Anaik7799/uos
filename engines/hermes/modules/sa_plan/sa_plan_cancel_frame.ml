type t =
  | Cancellation of Sa_plan_cancel_protocol.t
  | Bridge of Sa_plan_bridge_protocol.t
  | Target of Sa_plan_target_protocol.t

let max_frame_bytes = 16384
let envelope_schema = "uos.telegram.cancel-transport.v1"
let response_schema = "uos.telegram.cancel-transport-response.v1"
let invalid_transport = "invalid_cancel_transport"
let rejected_error = "cancel_request_rejected"
let transport_io_error = "cancel_transport_io"

let read_frame (ic : in_channel) : (string, string) result =
  try
    set_binary_mode_in ic true;
    let hdr = Bytes.create 4 in
    really_input ic hdr 0 4;
    let b0 = Int64.of_int (Bytes.get_uint8 hdr 0) in
    let b1 = Int64.of_int (Bytes.get_uint8 hdr 1) in
    let b2 = Int64.of_int (Bytes.get_uint8 hdr 2) in
    let b3 = Int64.of_int (Bytes.get_uint8 hdr 3) in
    let len64 =
      Int64.(
        logor (shift_left b0 24)
          (logor (shift_left b1 16) (logor (shift_left b2 8) b3)))
    in
    if len64 < 1L || len64 > Int64.of_int max_frame_bytes then
      Error invalid_transport
    else
      let payload = really_input_string ic (Int64.to_int len64) in
      match input_char ic with
      | _ -> Error invalid_transport
      | exception End_of_file -> Ok payload
  with _ -> Error invalid_transport

let decode_request op raw =
  match op with
  | "cancel-once" -> Result.map (fun value -> Cancellation value)
      (Sa_plan_cancel_protocol.decode Cancel raw)
  | "cancellation-result" -> Result.map (fun value -> Cancellation value)
      (Sa_plan_cancel_protocol.decode Lookup raw)
  | "bind-controller-bridge" -> Result.map (fun value -> Bridge value)
      (Sa_plan_bridge_protocol.decode Bind raw)
  | "controller-bridge-result" -> Result.map (fun value -> Bridge value)
      (Sa_plan_bridge_protocol.decode Lookup raw)
  | "inspect-cancellation-target" -> Result.map (fun value -> Target value)
      (Sa_plan_target_protocol.decode raw)
  | _ -> Error invalid_transport

let extract_envelope_fields fields =
  let rec loop schema op req = function
    | [] -> (
        match (schema, op, req) with
        | Some s, Some o, Some r -> Some (s, o, r)
        | _ -> None)
    | ("schema", v) :: rest ->
        if Option.is_some schema then None else loop (Some v) op req rest
    | ("operation", v) :: rest ->
        if Option.is_some op then None else loop schema (Some v) req rest
    | ("request", v) :: rest ->
        if Option.is_some req then None else loop schema op (Some v) rest
    | _ :: _ -> None
  in
  loop None None None fields

let decode (raw : string) : (t, string) result =
  let len = String.length raw in
  if len < 1 || len > max_frame_bytes || not (Stdlib.String.is_valid_utf_8 raw)
  then Error invalid_transport
  else
    match Yojson.Safe.from_string raw with
    | exception _ -> Error invalid_transport
    | `Assoc fields -> (
        match extract_envelope_fields fields with
        | Some (`String s, `String op_str, (`Assoc _ as req_json))
          when String.equal s envelope_schema -> (
            let nested_raw = Yojson.Safe.to_string req_json in
            match decode_request op_str nested_raw with
            | Ok cmd -> Ok cmd
            | Error _ -> Error invalid_transport)
        | _ -> Error invalid_transport)
    | _ -> Error invalid_transport

let response (outcome : (Yojson.Safe.t, string) result) : Yojson.Safe.t =
  match outcome with
  | Ok res ->
      `Assoc
        [
          ("schema", `String response_schema);
          ("status", `String "ok");
          ("result", res);
          ("error", `Null);
        ]
  | Error _ ->
      `Assoc
        [
          ("schema", `String response_schema);
          ("status", `String "rejected");
          ("result", `Null);
          ("error", `String rejected_error);
        ]

let write_frame (oc : out_channel) (json : Yojson.Safe.t) : (unit, string) result
    =
  try
    let payload = Yojson.Safe.to_string json in
    let len = String.length payload in
    if
      len < 1 || len > max_frame_bytes
      || not (Stdlib.String.is_valid_utf_8 payload)
    then Error transport_io_error
    else (
      set_binary_mode_out oc true;
      let hdr = Bytes.create 4 in
      Bytes.set_uint8 hdr 0 ((len lsr 24) land 0xff);
      Bytes.set_uint8 hdr 1 ((len lsr 16) land 0xff);
      Bytes.set_uint8 hdr 2 ((len lsr 8) land 0xff);
      Bytes.set_uint8 hdr 3 (len land 0xff);
      output_bytes oc hdr;
      output_string oc payload;
      flush oc;
      Ok ())
  with _ -> Error transport_io_error

let execute_observed store command ~observe_now =
  match command with
  | Cancellation value -> Sa_plan_cancel_protocol.execute_observed store value ~observe_now
  | Bridge value -> Sa_plan_bridge_protocol.execute_observed store value ~observe_now
  | Target value -> Sa_plan_target_protocol.execute_observed store value ~observe_now

