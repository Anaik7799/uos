(** Pure, non-authorizing fractal ontology for controlled Nix, Determinate Systems, and Devenv.
    Structural authority only: records invariants, inputs, outputs, hazards, and mitigation obligations. *)

type level = L0 | L1 | L2 | L3 | L4 | L5 | L6 | LX

type coordinate = { level : level; name : string; description : string }

type invariant =
  | Hermetic_store_isolation
  | Deterministic_closure_reproducibility
  | Flake_lock_immutability
  | Flake_bom_supply_chain_integrity
  | Devenv_declarative_composability
  | Process_supervision_safety
  | Controlled_intent_gate_admission
  | Total_error_rca_preservation

type owner =
  | Substrate_daemon_owner
  | Evaluator_engine_owner
  | Flake_registry_owner
  | Supply_chain_security_owner
  | Devenv_environment_owner
  | Process_supervisor_owner
  | Intent_controller_owner
  | Governance_telemetry_owner

type hazard =
  | Impure_path_leakage
  | Unpinned_dependency_drift
  | Store_closure_corruption
  | Vulnerable_package_advisory
  | Port_collision_or_unhealthy_service
  | Unbounded_eval_resource_exhaustion
  | Agent_direct_cli_bypass

type node = {
  coordinate : coordinate;
  owner : owner;
  invariants : invariant list;
  hazards : hazard list;
  inputs : string list;
  outputs : string list;
}

val level_to_string : level -> string
val all_nodes : node list
val find_node : level -> string -> node option
val validate_ontology_graph : unit -> (unit, string) result
val to_yojson : node -> Yojson.Safe.t
