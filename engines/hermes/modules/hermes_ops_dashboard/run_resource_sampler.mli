(** Sole live resource-sampling boundary. Pure parsers and [of_readings] make
    every fail-closed sensor outcome deterministic in tests. *)

type context = {
  run_id : string;
  subject_id : string;
  subject_digest : string;
  provenance : Run_model.provenance;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
}

type readings = {
  process_times : (Unix.process_times, string) result;
  gc : (Gc.stat, string) result;
  proc_status : (string, string) result;
  load_average : (string, string) result;
}

type sensors = {
  process_times : unit -> (Unix.process_times, string) result;
  gc : unit -> (Gc.stat, string) result;
  read_file : string -> (string, string) result;
}

val parse_proc_status : string -> (int64, string) result
val parse_load_average : string -> ((float * float * float), string) result
val of_readings : context -> now_ns:int64 -> readings -> Run_metrics.observation list
val observe_with : sensors -> context -> now_ns:int64 -> Run_metrics.observation list
val observe : context -> now_ns:int64 -> Run_metrics.observation list
