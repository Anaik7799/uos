type context = { run_id : string; subject_id : string; subject_digest : string;
  provenance : Run_model.provenance; coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin }
type readings = { process_times : (Unix.process_times, string) result;
  gc : (Gc.stat, string) result; proc_status : (string, string) result;
  load_average : (string, string) result }
type sensors = { process_times : unit -> (Unix.process_times, string) result;
  gc : unit -> (Gc.stat, string) result;
  read_file : string -> (string, string) result }

let finite value = match classify_float value with
  | FP_nan | FP_infinite -> false
  | FP_normal | FP_subnormal | FP_zero -> true

let words line =
  line |> String.map (function '\t' -> ' ' | character -> character)
  |> String.split_on_char ' ' |> List.map String.trim
  |> List.filter (fun word -> word <> "")

let parse_rss_line line =
  match words (String.trim line) with
  | [ "VmRSS:"; number; "kB" ] ->
      begin match Int64.of_string_opt number with
      | Some value when value >= 0L && value <= Int64.div Int64.max_int 1_024L ->
          Ok (Int64.mul value 1_024L)
      | _ -> Error "VmRSS is outside the nonnegative int64 byte range"
      end
  | _ -> Error "VmRSS must have the strict '<integer> kB' shape"

let parse_proc_status text =
  let rss_lines =
    text |> String.split_on_char '\n'
    |> List.filter (fun line -> String.starts_with ~prefix:"VmRSS:" (String.trim line))
  in
  match rss_lines with
  | [ line ] -> parse_rss_line line
  | [] -> Error "VmRSS is absent from /proc/self/status"
  | _ -> Error "VmRSS occurs more than once in /proc/self/status"

let parse_load_average text =
  match words (String.trim text) with
  | one :: five :: fifteen :: _ ->
      begin match float_of_string_opt one, float_of_string_opt five, float_of_string_opt fifteen with
      | Some one, Some five, Some fifteen
        when finite one && finite five && finite fifteen
             && one >= 0. && five >= 0. && fifteen >= 0. ->
          Ok (one, five, fifteen)
      | _ -> Error "load averages must be finite nonnegative floats"
      end
  | _ -> Error "load average requires three numeric horizons"

let observation (context : context) ~now_ns ~metric_id ~source value =
  let sample = match value with
    | Ok value -> Run_metrics.Measured { value; sampled_at_ns = now_ns }
    | Error reason -> Run_metrics.Unavailable_observed { reason; sampled_at_ns = now_ns }
  in
  let modeled_digest = match Run_metrics.find metric_id with
    | Some declaration -> Run_metrics.declaration_digest declaration
    | None -> String.make 64 '0'
  in
  Run_metrics.
    { metric_id; declaration_digest = modeled_digest; run_id = context.run_id;
      subject_id = context.subject_id; subject_digest = context.subject_digest;
      provenance = context.provenance; coordinate = context.coordinate;
      rca_origin = context.rca_origin; source; labels = []; sample }

let same_error reason ids context ~now_ns ~source =
  List.map (fun (id, _) -> observation context ~now_ns ~metric_id:id ~source (Error reason)) ids

let cpu_fields =
  [ ("process.cpu.user_seconds", fun times -> times.Unix.tms_utime);
    ("process.cpu.system_seconds", fun times -> times.tms_stime);
    ("process.cpu.child_user_seconds", fun times -> times.tms_cutime);
    ("process.cpu.child_system_seconds", fun times -> times.tms_cstime) ]

let gc_float_fields =
  [ ("ocaml.gc.minor_words", fun stat -> stat.Gc.minor_words);
    ("ocaml.gc.promoted_words", fun stat -> stat.promoted_words);
    ("ocaml.gc.major_words", fun stat -> stat.major_words) ]

let gc_int_fields =
  [ ("ocaml.gc.heap_words", fun stat -> stat.Gc.heap_words);
    ("ocaml.gc.live_words", fun stat -> stat.live_words);
    ("ocaml.gc.free_words", fun stat -> stat.free_words);
    ("ocaml.gc.minor_collections", fun stat -> stat.minor_collections);
    ("ocaml.gc.major_collections", fun stat -> stat.major_collections);
    ("ocaml.gc.compactions", fun stat -> stat.compactions) ]

let of_readings (context : context) ~now_ns (readings : readings) =
  let cpu = match readings.process_times with
    | Error reason -> same_error reason cpu_fields context ~now_ns ~source:Run_metrics.Process_times
    | Ok times ->
        List.map
          (fun (metric_id, project) ->
            let value = project times in
            let result = if finite value && value >= 0. then Ok (Run_metrics.Float value)
              else Error "process time is not finite and nonnegative" in
            observation context ~now_ns ~metric_id ~source:Run_metrics.Process_times result)
          cpu_fields
  in
  let gc = match readings.gc with
    | Error reason ->
        same_error reason (gc_float_fields @ List.map (fun (id, _) -> (id, fun _ -> 0.)) gc_int_fields)
          context ~now_ns ~source:Run_metrics.Ocaml_gc
    | Ok stat ->
        List.map
          (fun (metric_id, project) ->
            let value = project stat in
            let result = if finite value && value >= 0. then Ok (Run_metrics.Float value)
              else Error "GC word count is not finite and nonnegative" in
            observation context ~now_ns ~metric_id ~source:Run_metrics.Ocaml_gc result)
          gc_float_fields
        @ List.map
            (fun (metric_id, project) ->
              let value = project stat in
              let result = if value >= 0 then Ok (Run_metrics.Int (Int64.of_int value))
                else Error "GC counter is negative" in
              observation context ~now_ns ~metric_id ~source:Run_metrics.Ocaml_gc result)
            gc_int_fields
  in
  let rss =
    let value = match readings.proc_status with
      | Error reason -> Error reason
      | Ok text -> Result.map (fun bytes -> Run_metrics.Int bytes) (parse_proc_status text)
    in
    [ observation context ~now_ns ~metric_id:"process.rss.bytes"
        ~source:Run_metrics.Proc_status value ]
  in
  let load = match readings.load_average with
    | Error reason ->
        List.map
          (fun metric_id -> observation context ~now_ns ~metric_id
              ~source:Run_metrics.Load_average (Error reason))
          [ "system.load.1m"; "system.load.5m"; "system.load.15m" ]
    | Ok text ->
        begin match parse_load_average text with
        | Error reason ->
            List.map
              (fun metric_id -> observation context ~now_ns ~metric_id
                  ~source:Run_metrics.Load_average (Error reason))
              [ "system.load.1m"; "system.load.5m"; "system.load.15m" ]
        | Ok (one, five, fifteen) ->
            List.map
              (fun (metric_id, value) -> observation context ~now_ns ~metric_id
                  ~source:Run_metrics.Load_average (Ok (Run_metrics.Float value)))
              [ ("system.load.1m", one); ("system.load.5m", five);
                ("system.load.15m", fifteen) ]
        end
  in
  cpu @ gc @ rss @ load

let protect label action =
  try action () with exn -> Error (label ^ ": " ^ Printexc.to_string exn)

let observe_with (sensors : sensors) (context : context) ~now_ns =
  let process_times = protect "Unix.times sensor raised" sensors.process_times in
  let gc = protect "Gc.quick_stat sensor raised" sensors.gc in
  let proc_status = protect "/proc/self/status sensor raised"
      (fun () -> sensors.read_file "/proc/self/status") in
  let load_average = protect "/proc/loadavg sensor raised"
      (fun () -> sensors.read_file "/proc/loadavg") in
  of_readings context ~now_ns { process_times; gc; proc_status; load_average }

let read_file path =
  try
    let channel = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr channel)
      (fun () ->
        let buffer = Buffer.create 4_096 in
        let chunk = Bytes.create 4_096 in
        let rec consume total =
          let read = input channel chunk 0 (Bytes.length chunk) in
          if read = 0 then Ok (Buffer.contents buffer)
          else if total + read > 1_048_576 then Error (path ^ ": sensor input exceeds 1 MiB")
          else begin Buffer.add_subbytes buffer chunk 0 read; consume (total + read) end
        in
        consume 0)
  with exn -> Error (path ^ ": " ^ Printexc.to_string exn)

let live_sensors =
  { process_times = (fun () -> Ok (Unix.times ()));
    gc = (fun () -> Ok (Gc.quick_stat ()));
    read_file }

let observe context ~now_ns = observe_with live_sensors context ~now_ns
