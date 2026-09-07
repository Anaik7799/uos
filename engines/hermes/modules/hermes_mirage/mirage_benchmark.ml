type config = { iterations : int }
let max_roundtrips = 10_000
let default_roundtrips = 256
let payload_bytes = 512
let retained_slots = 16
let config ~roundtrips =
  if roundtrips < 1 || roundtrips > max_roundtrips then
    Error "roundtrips must be an integer in 1..10000"
  else Ok { iterations = roundtrips }
let roundtrips config = config.iterations

type workload = Block_roundtrip | Kv_roundtrip
let workload_name = function
  | Block_roundtrip -> "block_roundtrip"
  | Kv_roundtrip -> "kv_roundtrip"
type summary = {
  workload : workload;
  roundtrips : int;
  library_calls : int;
  verified_roundtrips : int;
  checksum : int64;
}
let summaries_agree a b =
  String.equal (workload_name a.workload) (workload_name b.workload)
  && a.roundtrips = b.roundtrips && a.library_calls = b.library_calls
  && a.verified_roundtrips = b.verified_roundtrips && Int64.equal a.checksum b.checksum
module type EXECUTION = sig
  val run : config -> workload -> (summary, string) result
end

let ( let* ) = Result.bind

module Native : EXECUTION = struct
  let run_loop config workload roundtrip =
    let rec loop index calls checksum =
      if index = config.iterations then
        Ok { workload; roundtrips = index; library_calls = calls;
             verified_roundtrips = index; checksum }
      else
        let expected = String.make payload_bytes (Char.chr (index mod 251)) in
        let* actual = roundtrip (index mod retained_slots) expected in
        if not (String.equal actual expected) then Error "payload verification failed"
        else
          let bytes = String.fold_left
            (fun sum byte -> Int64.add sum (Int64.of_int (Char.code byte))) 0L actual in
          loop (index + 1) (calls + 2) (Int64.add checksum bytes)
    in
    loop 0 0 0L

  let run config workload = match workload with
    | Block_roundtrip ->
        let* device = Mirage_memory_block.create ~sector_size:payload_bytes
          (Int64.of_int retained_slots) in
        Fun.protect ~finally:(fun () -> Mirage_memory_block.disconnect device)
          (fun () -> run_loop config workload (fun slot expected ->
            let* () = Mirage_memory_block.write device (Int64.of_int slot)
              [Bytes.of_string expected]
              |> Result.map_error (fun _ -> "block write failed") in
            let actual = Bytes.make payload_bytes '\000' in
            let* () = Mirage_memory_block.read device (Int64.of_int slot) [actual]
              |> Result.map_error (fun _ -> "block read failed") in
            Ok (Bytes.to_string actual)))
    | Kv_roundtrip ->
        let store = ref (Mirage_merkle_kv.create ()) in
        run_loop config workload (fun slot expected ->
          let key = ["benchmark"; string_of_int slot] in
          let* next = Mirage_merkle_kv.set !store key expected
            |> Result.map_error (fun _ -> "key/value set failed") in
          store := next;
          Mirage_merkle_kv.get !store key
          |> Result.map_error (fun _ -> "key/value get failed"))
end

type measurement = {
  summary : summary;
  process_cpu_seconds : float;
  library_calls_per_cpu_second : float option;
}
module type CLOCK = sig val now : unit -> float end
let finite_nonnegative value = match classify_float value with
  | FP_nan | FP_infinite -> false
  | FP_normal | FP_subnormal | FP_zero -> value >= 0.

module Timed (Clock : CLOCK) (Execution : EXECUTION) = struct
  let run config workload =
    let started = Clock.now () in
    if not (finite_nonnegative started) then Error "invalid process CPU start sample"
    else
      let* summary = Execution.run config workload in
      let stopped = Clock.now () in
      if not (finite_nonnegative stopped) || stopped < started then
        Error "invalid or backwards process CPU stop sample"
      else
        let process_cpu_seconds = stopped -. started in
        let rate = if process_cpu_seconds = 0. then None
          else Some (float_of_int summary.library_calls /. process_cpu_seconds) in
        match rate with
        | Some rate when not (finite_nonnegative rate) -> Error "CPU throughput overflow"
        | None | Some _ -> Ok { summary; process_cpu_seconds;
                               library_calls_per_cpu_second = rate }
end

let parse_config_args = function
  | [] -> config ~roundtrips:default_roundtrips
  | [count] when String.length count > 0 && String.length count <= 5
                && String.for_all (fun c -> c >= '0' && c <= '9') count ->
      (match int_of_string_opt count with
       | Some roundtrips -> config ~roundtrips
       | None -> Error "invalid benchmark count")
  | _ -> Error "benchmark accepts at most one decimal count in 1..10000"

module Process_cpu : CLOCK = struct let now = Sys.time end
module Host_benchmark = Timed (Process_cpu) (Native)

let measurement_to_json measurement =
  let summary = measurement.summary in
  `Assoc [
    "workload", `String (workload_name summary.workload);
    "roundtrips", `Int summary.roundtrips;
    "library_calls", `Int summary.library_calls;
    "verified_roundtrips", `Int summary.verified_roundtrips;
    "payload_checksum", `Intlit (Int64.to_string summary.checksum);
    "process_cpu_seconds", `Float measurement.process_cpu_seconds;
    "library_calls_per_cpu_second", (match measurement.library_calls_per_cpu_second with
      | None -> `Null | Some value -> `Float value)
  ]

let run_suite config =
  let* block = Host_benchmark.run config Block_roundtrip in
  let* kv = Host_benchmark.run config Kv_roundtrip in
  Ok (`Assoc [
    "schema", `String "uos-mirage-host-benchmark/v1";
    "scope", `String "host_ocaml_library";
    "ocaml_version", `String Sys.ocaml_version;
    "clock", `String "process_cpu_seconds:Sys.time";
    "timing_includes", `String "setup, library calls, payload verification, checksum and cleanup";
    "solo5_boot_measured", `Bool false;
    "ram_savings_measured", `Bool false;
    "deployment_admission", `String "NOT_VERIFIED";
    "payload_bytes", `Int payload_bytes;
    "retained_slots_per_workload", `Int retained_slots;
    "max_roundtrips", `Int max_roundtrips;
    "results", `List [measurement_to_json block; measurement_to_json kv]
  ])

module _ : EXECUTION = Native

module Reference : EXECUTION = struct
  (* Initial denotation: list of planned byte values. No storage API or native
     loop is used to compute the expected observations. *)
  let run config workload =
    let plan = List.init config.iterations (fun index -> index mod 251) in
    let rounds, calls, checksum = List.fold_left
      (fun (rounds, calls, checksum) byte ->
         rounds + 1, calls + 2,
         Int64.add checksum (Int64.mul (Int64.of_int byte) 512L))
      (0, 0, 0L) plan in
    Ok { workload; roundtrips = rounds; library_calls = calls;
         verified_roundtrips = rounds; checksum }
end

module _ : EXECUTION = Reference
