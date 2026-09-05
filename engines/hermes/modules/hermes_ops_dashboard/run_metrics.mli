(** Closed metric declarations and exact-head observations for one operations run. *)

type value = Int of int64 | Float of float | State of string

type sample =
  | Measured of { value : value; sampled_at_ns : int64 }
  | Unavailable_observed of { reason : string; sampled_at_ns : int64 }

type source =
  | Run_event
  | Process_times
  | Ocaml_gc
  | Proc_status
  | Load_average
  | Sqlite_store
  | Zenoh_transport
  | Websocket_transport
  | Snapshot_reconciler
  | Webgl_runtime
  | Admission_gate
  | Rete_ul_engine
  | Deterministic_mcda_v1
  | Safety_analysis
  | Formal_analysis
  | Assurance_runner

type unit_ = Count | Nanoseconds | Bytes | Words | Seconds | Ratio | State_unit
type aggregation = Last | Sum | Maximum | Mean | Quantile of int

type objective =
  | Informational
  | Lower_is_better of { warning : float; critical : float }
  | Higher_is_better of { warning : float; critical : float }
  | Exact_int of int64
  | Allowed_states of string list

type freshness = { max_age_ns : int64; future_tolerance_ns : int64 }

type cardinality = {
  max_series : int;
  max_labels : int;
  max_label_length : int;
}

type unavailable_semantics =
  | Preserve_unavailable
  | Block_completion
  | Degrade_observability

type declaration = {
  id : string;
  description : string;
  unit_ : unit_;
  aggregation : aggregation;
  objective : objective;
  freshness : freshness;
  cardinality : cardinality;
  unavailable_semantics : unavailable_semantics;
  sources : source list;
  fpp_channel : string;
}

type observation = {
  metric_id : string;
  declaration_digest : string;
  run_id : string;
  subject_id : string;
  subject_digest : string;
  provenance : Run_model.provenance;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  source : source;
  labels : (string * string) list;
  sample : sample;
}

val all : declaration list
val find : string -> declaration option
val declaration_digest : declaration -> string
val observation_digest : observation -> string
val sampled_at_ns : observation -> int64

val validate_declarations : declaration list -> (unit, string) result
(*@ ensures match result with Ok () -> declarations <> [] | Error _ -> true *)

val validate_observation : now_ns:int64 -> observation -> (unit, string) result
val to_otel_json : observation -> Yojson.Safe.t

val string_of_source : source -> string
val string_of_unit : unit_ -> string
