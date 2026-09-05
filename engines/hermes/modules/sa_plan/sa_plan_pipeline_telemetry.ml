open Core

type stage = { name : string; duration_ns : int64 }

let stage ~name ~duration_ns =
  if String.is_empty name then
    invalid_arg "Sa-plan pipeline stage name must be non-empty";
  if Int64.(duration_ns < 0L) then
    invalid_arg "Sa-plan pipeline duration must be non-negative";
  { name; duration_ns }

let now_ns () =
  Time_ns.now () |> Time_ns.to_int_ns_since_epoch |> Int64.of_int

let measure ~name operation =
  let started_ns = now_ns () in
  let value = operation () in
  let duration_ns = Int64.max 0L Int64.(now_ns () - started_ns) in
  value, stage ~name ~duration_ns

let milliseconds duration_ns = Int64.to_float duration_ns /. 1_000_000.

let timing_item stage =
  Printf.sprintf "%s;dur=%.3f" stage.name (milliseconds stage.duration_ns)

let server_timing ~total_ns stages =
  String.concat ~sep:", "
    (List.map stages ~f:timing_item
     @ [ timing_item { name = "total"; duration_ns = total_ns } ])

let stage_json stage =
  `Assoc
    [ "name", `String stage.name;
      "duration_ns", `Intlit (Int64.to_string stage.duration_ns);
      "duration_ms", `Float (milliseconds stage.duration_ns) ]

let to_yojson ~request_id ~command ~total_ns stages =
  `Assoc
    [ "request_id", `String request_id;
      "command", `String command;
      "authority", `String "report_only";
      "total_ns", `Intlit (Int64.to_string total_ns);
      "server_timing", `String (server_timing ~total_ns stages);
      "stages", `List (List.map stages ~f:stage_json) ]

let log_line ~request_id ~command ~total_ns stages =
  to_yojson ~request_id ~command ~total_ns stages |> Yojson.Safe.to_string
