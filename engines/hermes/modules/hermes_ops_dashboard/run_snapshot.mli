type phase_state = Phase_not_started | Phase_active | Phase_complete
type suite_state = Suite_pending | Suite_active | Suite_terminal of Run_model.lifecycle
type attempt_state =
  | Attempt_ready
  | Attempt_running
  | Attempt_terminal of Run_model.lifecycle

type counts = {
  events : int;
  phases_started : int;
  phases_finished : int;
  suites_discovered : int;
  suites_started : int;
  suites_succeeded : int;
  suites_failed : int;
  diagnostics : int;
  receipts : int;
  residuals : int;
  attempts_ready : int;
  attempts_running : int;
  attempts_terminal : int;
}

type t

type summary = {
  run_id : string;
  lifecycle : Run_model.lifecycle;
  last_sequence : int64;
  last_digest : string option;
  source_revision : string;
  source_clean : bool;
  configuration_digest : string;
  authority_digest : string;
  executable_digest : string;
  terminal : bool;
  counts : counts;
}

type apply_result =
  | Applied of t
  | Duplicate of t
  | Gap of { expected : int64; observed : int64 }

val first_sequence : int64
val empty : run_id:string -> provenance:Run_model.provenance -> (t, string) result
val apply : t -> Run_model.event -> (apply_result, string) result
val fold : Run_model.event list -> (t, string) result
val summary : t -> summary
val run_id : t -> string
val lifecycle : t -> Run_model.lifecycle
val last_sequence : t -> int64
val last_digest : t -> string option
val provenance : t -> Run_model.provenance
val counts : t -> counts
val is_terminal : t -> bool
val phase_state : t -> Run_model.phase -> phase_state
val suite_state : t -> string -> suite_state option
val attempt_state : t -> step:string -> attempt:int -> attempt_state option
