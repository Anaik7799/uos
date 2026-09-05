type receipt = {
  wall_ns : int64;
  monotonic_started_ns : int64;
  monotonic_finished_ns : int64;
  expires_monotonic_ns : int64;
  max_pair_span_ns : int64;
  lifetime_ns : int64;
  timezone_offset_s : int;
  journal_timestamp : string;
  digest : string;
}

type error =
  | Invalid_pair_bound
  | Invalid_lifetime_bound
  | Wall_clock_unavailable
  | Monotonic_clock_unavailable
  | Timezone_unavailable
  | Wall_time_out_of_range
  | Pair_window_exceeded
  | Arithmetic_overflow
  | Invalid_receipt
  | Wall_clock_rollback
  | Monotonic_clock_rollback
  | Expired

let maximum_pair_span_ns = 1_000_000_000L
let maximum_lifetime_ns = 604_800_000_000_000L

let length_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat "|"

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let error_keys =
  [ "invalid-pair-bound"; "invalid-lifetime-bound";
    "wall-clock-unavailable"; "monotonic-clock-unavailable";
    "timezone-unavailable"; "wall-time-out-of-range";
    "pair-window-exceeded"; "arithmetic-overflow"; "invalid-receipt";
    "wall-clock-rollback"; "monotonic-clock-rollback"; "expired" ]

let authority_digest ?(drop_wall = false) ?(drop_monotonic = false)
    ?(pair_bound = maximum_pair_span_ns)
    ?(lifetime_bound = maximum_lifetime_ns)
    ?(wall_rollback = true) ?(monotonic_rollback = true) ?(expiry = true) () =
  let fields =
    [ "timezone-offset-s"; "journal-timestamp"; "receipt-digest";
      "max-pair-span-ns"; "lifetime-ns" ]
    @ (if drop_wall then [] else [ "wall-ns" ])
    @ (if drop_monotonic then []
       else
         [ "monotonic-started-ns"; "monotonic-finished-ns";
           "expires-monotonic-ns" ])
  in
  length_frame
    [ "dependability-clock-authority-v1";
      "sources"; length_frame [ "Ptime_clock.now"; "Mtime_clock.elapsed_ns" ];
      "bounds"; Int64.to_string pair_bound; Int64.to_string lifetime_bound;
      "receipt-fields"; length_frame fields;
      "errors"; length_frame error_keys;
      "pair-law"; "monotonic-before<=monotonic-after<=before+bound";
      "wall-rollback"; string_of_bool wall_rollback;
      "monotonic-rollback"; string_of_bool monotonic_rollback;
      "expiry"; string_of_bool expiry;
      "timestamp-format"; "YYYYMMDD-HHSS" ]
  |> sha256

let source_digest = authority_digest ()

let valid_pair_bound value =
  Int64.compare value 0L > 0
  && Int64.compare value maximum_pair_span_ns <= 0

let valid_lifetime value =
  Int64.compare value 0L > 0
  && Int64.compare value maximum_lifetime_ns <= 0

let safe_add_positive left right =
  if Int64.compare left 0L < 0 || Int64.compare right 0L < 0
     || Int64.compare left (Int64.sub Int64.max_int right) > 0
  then None
  else Some (Int64.add left right)

let day_ns = 86_400_000_000_000L

let wall_ns_of_ptime wall =
  let days, picoseconds = Ptime.Span.to_d_ps (Ptime.to_span wall) in
  if days < 0 || Int64.compare picoseconds 0L < 0 then Error Wall_time_out_of_range
  else
    let days = Int64.of_int days in
    if Int64.compare days (Int64.div Int64.max_int day_ns) > 0 then
      Error Wall_time_out_of_range
    else
      let day_part = Int64.mul days day_ns in
      let within_day = Int64.div picoseconds 1_000L in
      match safe_add_positive day_part within_day with
      | None -> Error Wall_time_out_of_range
      | Some value when Int64.compare value 0L <= 0 -> Error Wall_time_out_of_range
      | Some value -> Ok value

let timestamp_of_ptime ~timezone_offset_s wall =
  let (year, month, day), ((hour, _minute, second), actual_offset) =
    Ptime.to_date_time ~tz_offset_s:timezone_offset_s wall
  in
  if actual_offset <> timezone_offset_s then Error Timezone_unavailable
  else
    Ok
      (Printf.sprintf "%04d%02d%02d-%02d%02d"
         year month day hour second)

let canonical value =
  length_frame
    [ source_digest; Int64.to_string value.wall_ns;
      Int64.to_string value.monotonic_started_ns;
      Int64.to_string value.monotonic_finished_ns;
      Int64.to_string value.expires_monotonic_ns;
      Int64.to_string value.max_pair_span_ns;
      Int64.to_string value.lifetime_ns;
      string_of_int value.timezone_offset_s; value.journal_timestamp ]

let receipt_digest value = sha256 (canonical value)

let observe ~max_pair_span_ns ~lifetime_ns =
  if not (valid_pair_bound max_pair_span_ns) then Error Invalid_pair_bound
  else if not (valid_lifetime lifetime_ns) then Error Invalid_lifetime_bound
  else
    match (try Ok (Mtime_clock.elapsed_ns ())
           with Sys_error _ -> Error Monotonic_clock_unavailable) with
    | Error _ as error -> error
    | Ok monotonic_started_ns when Int64.compare monotonic_started_ns 0L < 0 ->
        Error Monotonic_clock_unavailable
    | Ok monotonic_started_ns ->
        begin
          match (try Ok (Ptime_clock.now ())
                 with Sys_error _ -> Error Wall_clock_unavailable) with
          | Error _ as error -> error
          | Ok wall ->
              begin
                match Ptime_clock.current_tz_offset_s () with
                | None -> Error Timezone_unavailable
                | Some timezone_offset_s
                  when timezone_offset_s < -86_400
                       || timezone_offset_s > 86_400 ->
                    Error Timezone_unavailable
                | Some timezone_offset_s ->
                    match (try Ok (Mtime_clock.elapsed_ns ())
                           with Sys_error _ -> Error Monotonic_clock_unavailable) with
                    | Error _ as error -> error
                    | Ok monotonic_finished_ns
                      when Int64.compare monotonic_finished_ns 0L < 0
                           || Int64.compare monotonic_finished_ns
                             monotonic_started_ns < 0 ->
                        Error Monotonic_clock_rollback
                    | Ok monotonic_finished_ns ->
                        let pair_span =
                          Int64.sub monotonic_finished_ns monotonic_started_ns
                        in
                        if Int64.compare pair_span max_pair_span_ns > 0 then
                          Error Pair_window_exceeded
                        else
                          match wall_ns_of_ptime wall,
                                timestamp_of_ptime ~timezone_offset_s wall,
                                safe_add_positive monotonic_finished_ns lifetime_ns
                          with
                          | Error error, _, _ | _, Error error, _ -> Error error
                          | _, _, None -> Error Arithmetic_overflow
                          | Ok wall_ns, Ok journal_timestamp,
                            Some expires_monotonic_ns ->
                              let unsigned =
                                { wall_ns; monotonic_started_ns;
                                  monotonic_finished_ns; expires_monotonic_ns;
                                  max_pair_span_ns; lifetime_ns;
                                  timezone_offset_s; journal_timestamp;
                                  digest = "" }
                              in
                              Ok
                                { unsigned with
                                  digest = receipt_digest unsigned }
              end
        end

let valid_timestamp value =
  let length = String.length value in
  let rec loop index =
    if index = length then true
    else if index = 8 then value.[index] = '-' && loop (index + 1)
    else
      match value.[index] with
      | '0' .. '9' -> loop (index + 1)
      | _ -> false
  in
  length = 13 && loop 0

let validate value =
  if not (valid_pair_bound value.max_pair_span_ns)
     || not (valid_lifetime value.lifetime_ns)
     || Int64.compare value.wall_ns 0L <= 0
     || Int64.compare value.monotonic_started_ns 0L < 0
     || Int64.compare value.monotonic_finished_ns
          value.monotonic_started_ns < 0
     || Int64.compare
          (Int64.sub value.monotonic_finished_ns value.monotonic_started_ns)
          value.max_pair_span_ns > 0
     || value.timezone_offset_s < -86_400
     || value.timezone_offset_s > 86_400
     || not (valid_timestamp value.journal_timestamp)
  then Error Invalid_receipt
  else
    match safe_add_positive value.monotonic_finished_ns value.lifetime_ns with
    | None -> Error Invalid_receipt
    | Some expected_expiry
      when not (Int64.equal expected_expiry value.expires_monotonic_ns) ->
        Error Invalid_receipt
    | Some _ when not (String.equal value.digest (receipt_digest value)) ->
        Error Invalid_receipt
    | Some _ -> Ok ()

let validate_order ~previous ~next =
  match validate previous, validate next with
  | Error error, _ | _, Error error -> Error error
  | Ok (), Ok () when Int64.compare next.wall_ns previous.wall_ns < 0 ->
      Error Wall_clock_rollback
  | Ok (), Ok ()
    when Int64.compare next.monotonic_finished_ns
           previous.monotonic_finished_ns < 0 ->
      Error Monotonic_clock_rollback
  | Ok (), Ok () -> Ok ()

let validate_current ~now receipt =
  match validate_order ~previous:receipt ~next:now with
  | Error _ as error -> error
  | Ok () when Int64.compare now.monotonic_finished_ns
                  receipt.expires_monotonic_ns >= 0 ->
      Error Expired
  | Ok () -> Ok ()

let wall_ns value = value.wall_ns
let monotonic_started_ns value = value.monotonic_started_ns
let monotonic_finished_ns value = value.monotonic_finished_ns
let expires_monotonic_ns value = value.expires_monotonic_ns
let journal_timestamp value = value.journal_timestamp
let digest value = value.digest

module For_test = struct
  type mutation =
    | Drop_wall
    | Drop_monotonic
    | Widen_pair_bound
    | Widen_lifetime_bound
    | Remove_wall_rollback
    | Remove_monotonic_rollback
    | Remove_expiry

  let source_digest_with_mutation = function
    | Drop_wall -> authority_digest ~drop_wall:true ()
    | Drop_monotonic -> authority_digest ~drop_monotonic:true ()
    | Widen_pair_bound ->
        authority_digest ~pair_bound:(Int64.succ maximum_pair_span_ns) ()
    | Widen_lifetime_bound ->
        authority_digest ~lifetime_bound:(Int64.succ maximum_lifetime_ns) ()
    | Remove_wall_rollback -> authority_digest ~wall_rollback:false ()
    | Remove_monotonic_rollback -> authority_digest ~monotonic_rollback:false ()
    | Remove_expiry -> authority_digest ~expiry:false ()
end
