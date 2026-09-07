open Mirage_benchmark
let require message condition = if not condition then failwith message
let unwrap = function Ok value -> value | Error message -> failwith message
let make n = unwrap (config ~roundtrips:n)
let workloads = [Block_roundtrip; Kv_roundtrip]

module Make_laws (Execution : EXECUTION) = struct
  let run () =
    let rng = Random.State.make [|87; 89; 20260907|] in
    let cases = [1; 16; 17; 251; 252; default_roundtrips; max_roundtrips]
      @ List.init 32 (fun _ -> 1 + Random.State.int rng 1024) in
    List.iter (fun n -> List.iter (fun workload ->
      let cfg = make n in
      let first = unwrap (Execution.run cfg workload) in
      let second = unwrap (Execution.run cfg workload) in
      require "MB-02 count law" (first.roundtrips = n && first.library_calls = 2*n);
      require "MB-03 verified payload count" (first.verified_roundtrips = n);
      require "MB-05 repeat semantics" (summaries_agree first second)
    ) workloads) cases
end
module Reference_laws = Make_laws (Reference)
module Native_laws = Make_laws (Native)

let check_clock samples check =
  let samples = ref samples in
  let module Clock = struct
    let now () = match !samples with
      | value :: rest -> samples := rest; value
      | [] -> failwith "clock read unexpectedly"
  end in
  let module Measurement = Timed (Clock) (Reference) in
  check (Measurement.run (make 3) Block_roundtrip)

let run_cli runner arguments =
  let path = Filename.temp_file "mirage-benchmark-test-" ".json" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
    let pid = Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
      Unix.create_process runner (Array.of_list (runner :: arguments)) Unix.stdin fd fd) in
    let _, status = Unix.waitpid [] pid in
    let channel = open_in_bin path in
    let output = Fun.protect ~finally:(fun () -> close_in channel)
      (fun () -> really_input_string channel (in_channel_length channel)) in
    status, output)

let () =
  List.iter (fun n -> require "MB-01 invalid config rejected"
    (Result.is_error (config ~roundtrips:n))) [min_int; -1; 0; 10001; max_int];
  require "MB-01 valid config observed" (roundtrips (make 10000) = 10000);
  (* Independent small closed-form examples also constrain the oracle. *)
  let expected = unwrap (Reference.run (make 3) Block_roundtrip) in
  require "MB-04 known checksum" (Int64.equal expected.checksum 1536L);
  Reference_laws.run ();
  Native_laws.run ();
  List.iter (fun seed ->
    let first = Random.State.make [|seed; 89|] in
    let twin = Random.State.make [|seed; 89|] in
    for _ = 1 to 32 do
      let reference_config = make (1 + Random.State.int first 1024) in
      let native_config = make (1 + Random.State.int twin 1024) in
      List.iter (fun workload ->
        let reference = unwrap (Reference.run reference_config workload) in
        let native = unwrap (Native.run native_config workload) in
        require "MB-04/06 oracle/native checksum and all observations"
          (summaries_agree reference native)) workloads
    done) [87; 20260907];
  List.iter (fun samples -> check_clock samples (fun result ->
    require "MB-07 invalid clock rejected" (Result.is_error result)))
    [[nan]; [infinity]; [-1.]; [1.; nan]; [1.; infinity]; [1.; -1.]; [2.; 1.];
     [0.; Float.next_after 0. 1.]];
  check_clock [1.; 1.] (fun result ->
    let value = unwrap result in
    require "MB-08 zero duration has no throughput"
      (value.process_cpu_seconds = 0. && value.library_calls_per_cpu_second = None));
  check_clock [1.; 3.] (fun result ->
    let value = unwrap result in
    require "MB-07 process CPU interval and rate"
      (value.process_cpu_seconds = 2. && value.library_calls_per_cpu_second = Some 3.));
  let runner = if Array.length Sys.argv = 2 then Sys.argv.(1)
    else failwith "supply path to hermes_mirage_runner.exe for CLI checks" in
  let runner = if Filename.is_relative runner then Filename.concat (Sys.getcwd ()) runner
    else runner in
  List.iter (fun args ->
    let status, _ = run_cli runner ("benchmark" :: args) in
    require "MB-09 actual CLI rejects invalid/surplus arguments"
      (status = Unix.WEXITED 2))
    [["0"]; ["10001"]; ["-1"]; ["1.5"]; ["abc"]; ["0x10"]; ["1"; "2"];
     [String.make 100 '9']];
  let module Json = Yojson.Safe.Util in
  List.iter (fun args ->
    let status, output = run_cli runner ("benchmark" :: args) in
    require "MB-09 valid CLI succeeds" (status = Unix.WEXITED 0);
    let json = Yojson.Safe.from_string output in
    require "MB-10 benchmark scope"
      (Json.(json |> member "scope" |> to_string) = "host_ocaml_library");
    require "MB-10 no boot claim" (Json.(json |> member "solo5_boot_measured" |> to_bool) = false);
    let results = Json.(json |> member "results" |> to_list) in
    require "MB-10 two workloads" (List.length results = 2);
    let cfg = unwrap (parse_config_args args) in
    List.iter2 (fun workload actual ->
      let expected = unwrap (Reference.run cfg workload) in
      require "MB-10 actual JSON summary agrees with independent oracle"
        (Json.(actual |> member "workload" |> to_string) = workload_name workload
         && Json.(actual |> member "roundtrips" |> to_int) = expected.roundtrips
         && Json.(actual |> member "library_calls" |> to_int) = expected.library_calls
         && Json.(actual |> member "verified_roundtrips" |> to_int) = expected.verified_roundtrips
         && Int64.of_int Json.(actual |> member "payload_checksum" |> to_int) = expected.checksum);
      let cpu = Json.(actual |> member "process_cpu_seconds" |> to_float) in
      require "MB-07 actual JSON CPU duration is valid" (Float.is_finite cpu && cpu >= 0.);
      let rate = Json.(actual |> member "library_calls_per_cpu_second") in
      if cpu = 0. then require "MB-08 actual JSON zero duration has null rate" (rate = `Null)
      else let rate = Json.to_float rate in
        require "MB-07 actual JSON rate matches observed interval"
          (Float.is_finite rate && rate = float_of_int expected.library_calls /. cpu)
    ) workloads results
  ) [[]; ["1"]; ["10000"]];
  let status, output = run_cli runner ["catalog"] in
  require "MB-10 actual catalog CLI succeeds" (status = Unix.WEXITED 0);
  let json = Yojson.Safe.from_string output in
  require "MB-10 candidate count unchanged" (Json.(json |> member "total_candidates" |> to_int) = 7);
  require "MB-10 catalog benchmark bounds"
    (Json.(json |> member "host_benchmark" |> member "max_roundtrips" |> to_int) = 10000);
  require "MB-10 declared RAM is only a projection"
    (Json.(json |> member "projected_ram_savings_mb" |> to_int) = 1092
     && Json.(json |> member "measured_ram_savings_mb") = `Null);
  List.iter (fun candidate -> require "MB-10 catalog cannot grant admission"
    (Json.(candidate |> member "status" |> to_string) = "NOT_VERIFIED"))
    Json.(json |> member "candidates" |> to_list);
  print_endline "Mirage benchmark MB-01..10 PASS: oracle/native laws, twin seeds 87+20260907/89, max 10000, clock negatives, 12 CLI probes"
