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

let level_to_string = function
  | L0 -> "L0"
  | L1 -> "L1"
  | L2 -> "L2"
  | L3 -> "L3"
  | L4 -> "L4"
  | L5 -> "L5"
  | L6 -> "L6"
  | LX -> "LX"

let all_nodes =
  [ { coordinate =
        { level = L0;
          name = "nix-substrate-daemon";
          description = "Nix store filesystem, SQLite db, daemon socket, and sandbox drivers" };
      owner = Substrate_daemon_owner;
      invariants = [ Hermetic_store_isolation; Deterministic_closure_reproducibility ];
      hazards = [ Store_closure_corruption; Agent_direct_cli_bypass ];
      inputs = [ "Store_path_query"; "Build_drv_request" ];
      outputs = [ "Realized_store_path"; "Daemon_status" ] };

    { coordinate =
        { level = L1;
          name = "nix-evaluator-engine";
          description = "Lazy evaluator, parallel eval, lazy-trees, and derivation instantiation" };
      owner = Evaluator_engine_owner;
      invariants = [ Hermetic_store_isolation; Total_error_rca_preservation ];
      hazards = [ Impure_path_leakage; Unbounded_eval_resource_exhaustion ];
      inputs = [ "Nix_expression"; "Evaluation_budget" ];
      outputs = [ "Derivation_AST"; "Evaluated_value" ] };

    { coordinate =
        { level = L2;
          name = "flake-registry-hub";
          description = "Flakes, lockfile management, FlakeHub semver resolution, and binary caches" };
      owner = Flake_registry_owner;
      invariants = [ Flake_lock_immutability; Deterministic_closure_reproducibility ];
      hazards = [ Unpinned_dependency_drift ];
      inputs = [ "Flake_reference"; "Lockfile" ];
      outputs = [ "Pinned_flake_closure"; "Cache_receipt" ] };

    { coordinate =
        { level = L3;
          name = "supply-chain-security";
          description = "FlakeBOM software bill of materials, FlakeAudit advisory scanner, and provenance" };
      owner = Supply_chain_security_owner;
      invariants = [ Flake_bom_supply_chain_integrity; Total_error_rca_preservation ];
      hazards = [ Vulnerable_package_advisory ];
      inputs = [ "Flake_closure"; "Security_database" ];
      outputs = [ "BOM_document"; "Audit_verdict" ] };

    { coordinate =
        { level = L4;
          name = "devenv-declarative-layer";
          description = "Composable developer environments, devenv.nix modules, languages, and containers" };
      owner = Devenv_environment_owner;
      invariants = [ Devenv_declarative_composability; Hermetic_store_isolation ];
      hazards = [ Impure_path_leakage; Unpinned_dependency_drift ];
      inputs = [ "Devenv_nix_file"; "Devenv_yaml" ];
      outputs = [ "Activated_shell_environment"; "Container_spec" ] };

    { coordinate =
        { level = L5;
          name = "process-supervision";
          description = "Process-compose integration, background services, health checks, and lifecycle" };
      owner = Process_supervisor_owner;
      invariants = [ Process_supervision_safety; Total_error_rca_preservation ];
      hazards = [ Port_collision_or_unhealthy_service ];
      inputs = [ "Service_definitions"; "Supervisor_budget" ];
      outputs = [ "Process_tree_status"; "Service_health_log" ] };

    { coordinate =
        { level = L6;
          name = "typed-intent-controller";
          description = "Strongly typed OCaml intent plane, gate admission, and immutable receipts" };
      owner = Intent_controller_owner;
      invariants = [ Controlled_intent_gate_admission; Total_error_rca_preservation ];
      hazards = [ Agent_direct_cli_bypass ];
      inputs = [ "Typed_declarative_intent" ];
      outputs = [ "Execution_receipt"; "Gate_verdict" ] };

    { coordinate =
        { level = LX;
          name = "governance-telemetry";
          description = "R31 compliance auditing, formal proofs, execution invariants, and metrics" };
      owner = Governance_telemetry_owner;
      invariants = [ Controlled_intent_gate_admission; Hermetic_store_isolation ];
      hazards = [ Agent_direct_cli_bypass; Impure_path_leakage ];
      inputs = [ "Execution_telemetry"; "Audit_event" ];
      outputs = [ "Governance_report"; "Compliance_metrics" ] } ]

let find_node lvl name =
  List.find_opt (fun n -> n.coordinate.level = lvl && String.equal n.coordinate.name name) all_nodes

let validate_ontology_graph () =
  let names = List.map (fun n -> n.coordinate.name) all_nodes in
  if List.length names <> List.length (List.sort_uniq String.compare names) then
    Error "Duplicate node names in fractal ontology graph"
  else
    Ok ()

let to_yojson node =
  `Assoc
    [ ("level", `String (level_to_string node.coordinate.level));
      ("name", `String node.coordinate.name);
      ("description", `String node.coordinate.description);
      ("inputs", `List (List.map (fun s -> `String s) node.inputs));
      ("outputs", `List (List.map (fun s -> `String s) node.outputs)) ]
