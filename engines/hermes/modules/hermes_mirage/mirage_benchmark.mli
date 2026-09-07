(** Bounded host-library benchmark. This is not a Solo5 boot or RAM measurement.
    Laws MB-01..10: docs/design/20260907-1037-mirage-benchmark-contract.md. *)
type config
val max_roundtrips : int
val default_roundtrips : int
val payload_bytes : int
val retained_slots : int
val config : roundtrips:int -> (config, string) result
val roundtrips : config -> int

type workload = Block_roundtrip | Kv_roundtrip
val workload_name : workload -> string
type summary = private {
  workload : workload;
  roundtrips : int;
  library_calls : int;
  verified_roundtrips : int;
  checksum : int64;
}
val summaries_agree : summary -> summary -> bool
module type EXECUTION = sig
  val run : config -> workload -> (summary, string) result
end
module Reference : EXECUTION
module Native : EXECUTION

type measurement = private {
  summary : summary;
  process_cpu_seconds : float;
  library_calls_per_cpu_second : float option;
}
module type CLOCK = sig val now : unit -> float end
module Timed (Clock : CLOCK) (Execution : EXECUTION) : sig
  val run : config -> workload -> (measurement, string) result
end
val parse_config_args : string list -> (config, string) result
val run_suite : config -> (Yojson.Safe.t, string) result
