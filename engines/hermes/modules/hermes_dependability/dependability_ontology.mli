(** Executable dependability ontology.

    The ontology is descriptive authority only: its evidence posture cannot
    grant execution or parity credit. *)

type scale = Framework | Target | Capability
type kind = Controller | Controlled_process | Evidence | Formal_model | Surface

type component_kind =
  | Framework_component
  | Target_component of Dependability_intent.target
  | Statement_lifecycle_component
  | Database_close_component
  | Actor_cleanup_component
  | Process_reliability_component
  | Crash_window_component
  | Lifecycle_formal_component
  | Fpp_mbse_component
  | Surface_gateway_component
  | Evidence_path_component of Dependability_intent.target
  | Closure_path_component of Dependability_intent.target

type oracle_kind =
  | No_oracle
  | Finite_transition_oracle
  | Z3_oracle
  | Native_sqlite_oracle
  | Swarm_process_oracle
  | Kernel_journal_oracle
  | Projection_oracle

type metric_kind = Counter | Gauge | Histogram | State_metric
type path_role = Admission_path | Evidence_path | Closure_path
type applicability = Framework_wide | Targets of Dependability_intent.target list
type evidence_status =
  | Declared_only
  | Implemented_structural
  | Tested_structural
  | Execution_unavailable
  | Differentially_verified

type evidence_currentness =
  | Current_evidence of {
      authority_digest : string;
      receipt_digest : string;
    }
  | Stale_evidence of {
      authority_digest : string;
      observed_digest : string;
    }
  | Currentness_unavailable of {
      authority_digest : string;
      diagnostic_digest : string;
    }

type hazard = { hazard_id : string; description : string }
type metric = { metric_id : string; metric_kind : metric_kind }
type source = { source_id : string; path : string }

type node = {
  id : string;
  parent_id : string option;
  coordinate : string;
  scale : scale;
  kind : kind;
  component_kind : component_kind;
  oracle_kind : oracle_kind;
  applicability : applicability;
  path_role : path_role;
  evidence_status : evidence_status;
  evidence_currentness : evidence_currentness;
  rca_origin : string;
  controller : string;
  controlled_process : string;
  control_actions : string list;
  feedback : string list;
  losses : string list;
  hazards : string list;
  unsafe_control_actions : string list;
  fmea : string list;
  safety_constraints : string list;
  sources : string list;
  implementation_paths : string list;
  test_paths : string list;
  metric_ids : string list;
  evidence_posture : string;
  provenance : string;
  owner : string;
  evolution_version : int;
}

val nodes : node list
val hazards : hazard list
val metrics : metric list
val sources : source list
val find : string -> node option

val validate : unit -> string list
(*@ errors = validate ()
    pure *)
