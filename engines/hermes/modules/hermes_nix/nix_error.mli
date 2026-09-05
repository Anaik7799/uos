(** Strongly typed error hierarchy for Nix and Devenv ecosystem.
    Errors are total, bounded, and preserve RCA classification without panics. *)

type rca_origin =
  | Specification_origin
  | Environment_origin
  | Flake_origin
  | Evaluator_origin
  | Builder_origin
  | Sandbox_origin
  | Devenv_config_origin
  | Process_supervision_origin
  | Policy_rejection_origin

type t =
  | Invalid_identifier of { kind : string; raw : string; reason : string }
  | Flake_resolution_failed of { flake_ref : string; reason : string }
  | Evaluation_error of { attribute : string; message : string }
  | Derivation_build_failed of { drv_path : string; exit_code : int; log_tail : string }
  | Devenv_parse_error of { file : string; line : int option; message : string }
  | Devenv_service_failed of { service : string; reason : string }
  | Policy_violation of { rule : string; description : string }
  | Impure_access_blocked of { attempted_path : string }
  | Network_sandbox_blocked of { target : string }
  | Flake_bom_mismatch of { expected : string; actual : string }
  | Flake_audit_finding of { advisory_id : string; severity : string; package : string }
  | Store_path_corrupted of { path : string; reason : string }
  | Daemon_unreachable of { socket : string; message : string }

val rca : t -> rca_origin
val to_string : t -> string
val to_yojson : t -> Yojson.Safe.t
