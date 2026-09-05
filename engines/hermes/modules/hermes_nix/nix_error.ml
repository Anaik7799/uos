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

let rca = function
  | Invalid_identifier _ -> Specification_origin
  | Flake_resolution_failed _ -> Flake_origin
  | Evaluation_error _ -> Evaluator_origin
  | Derivation_build_failed _ -> Builder_origin
  | Devenv_parse_error _ -> Devenv_config_origin
  | Devenv_service_failed _ -> Process_supervision_origin
  | Policy_violation _ -> Policy_rejection_origin
  | Impure_access_blocked _ -> Sandbox_origin
  | Network_sandbox_blocked _ -> Sandbox_origin
  | Flake_bom_mismatch _ -> Specification_origin
  | Flake_audit_finding _ -> Specification_origin
  | Store_path_corrupted _ -> Environment_origin
  | Daemon_unreachable _ -> Environment_origin

let to_string = function
  | Invalid_identifier { kind; raw; reason } ->
      Printf.sprintf "Invalid identifier [%s] '%s': %s" kind raw reason
  | Flake_resolution_failed { flake_ref; reason } ->
      Printf.sprintf "Flake resolution failed for '%s': %s" flake_ref reason
  | Evaluation_error { attribute; message } ->
      Printf.sprintf "Nix evaluation error on '%s': %s" attribute message
  | Derivation_build_failed { drv_path; exit_code; log_tail } ->
      Printf.sprintf "Derivation build failed '%s' (exit %d): %s" drv_path exit_code log_tail
  | Devenv_parse_error { file; line; message } ->
      let lstr = match line with Some l -> Printf.sprintf ":%d" l | None -> "" in
      Printf.sprintf "Devenv configuration error in %s%s: %s" file lstr message
  | Devenv_service_failed { service; reason } ->
      Printf.sprintf "Devenv service '%s' failed: %s" service reason
  | Policy_violation { rule; description } ->
      Printf.sprintf "Nix policy violation [%s]: %s" rule description
  | Impure_access_blocked { attempted_path } ->
      Printf.sprintf "Impure path access blocked: '%s'" attempted_path
  | Network_sandbox_blocked { target } ->
      Printf.sprintf "Network access outside sandbox blocked for '%s'" target
  | Flake_bom_mismatch { expected; actual } ->
      Printf.sprintf "FlakeBOM mismatch — expected %s, got %s" expected actual
  | Flake_audit_finding { advisory_id; severity; package } ->
      Printf.sprintf "FlakeAudit security finding [%s / %s] in package '%s'" advisory_id severity package
  | Store_path_corrupted { path; reason } ->
      Printf.sprintf "Store path '%s' verification failed: %s" path reason
  | Daemon_unreachable { socket; message } ->
      Printf.sprintf "Nix daemon unreachable on socket '%s': %s" socket message

let to_yojson e =
  `Assoc
    [ ("error", `String (to_string e));
      ("rca_origin",
       `String
         (match rca e with
          | Specification_origin -> "specification"
          | Environment_origin -> "environment"
          | Flake_origin -> "flake"
          | Evaluator_origin -> "evaluator"
          | Builder_origin -> "builder"
          | Sandbox_origin -> "sandbox"
          | Devenv_config_origin -> "devenv_config"
          | Process_supervision_origin -> "process_supervision"
          | Policy_rejection_origin -> "policy_rejection")) ]
