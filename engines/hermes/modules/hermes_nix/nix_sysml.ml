type block_kind =
  | Substrate_store_block
  | Evaluator_block
  | Flake_lock_manager_block
  | Flake_security_auditor_block
  | Devenv_runtime_block
  | Process_compose_supervisor_block
  | Intent_admission_controller_block

type port_direction = In | Out | InOut

type port = {
  name : string;
  direction : port_direction;
  payload_type : string;
}

type constraint_rule = {
  id : string;
  name : string;
  expression : string;
  formal_solver : string;
}

type sysml_block = {
  kind : block_kind;
  name : string;
  ports : port list;
  constraints : constraint_rule list;
}

let all_blocks =
  [ { kind = Substrate_store_block;
      name = "NixSubstrateStore";
      ports =
        [ { name = "storePathQueryIn"; direction = In; payload_type = "StorePath" };
          { name = "realizedPathOut"; direction = Out; payload_type = "StorePath" };
          { name = "daemonControlPort"; direction = InOut; payload_type = "DaemonProtocol" } ];
      constraints =
        [ { id = "C-NIX-01";
            name = "StorePathImmutability";
            expression = "forall p in StorePath: modified(p) == false";
            formal_solver = "Z3" };
          { id = "C-NIX-02";
            name = "ClosureCompleteness";
            expression = "forall d in Derivation: closure(d) subset /nix/store";
            formal_solver = "Why3" } ] };

    { kind = Evaluator_block;
      name = "NixEvaluatorEngine";
      ports =
        [ { name = "exprIn"; direction = In; payload_type = "NixExpression" };
          { name = "drvOut"; direction = Out; payload_type = "DerivationAST" } ];
      constraints =
        [ { id = "C-NIX-03";
            name = "PureEvaluationDeterminism";
            expression = "pure(e) => eval(e, env1) == eval(e, env2)";
            formal_solver = "Rocq" } ] };

    { kind = Flake_lock_manager_block;
      name = "FlakeLockManager";
      ports =
        [ { name = "flakeRefIn"; direction = In; payload_type = "FlakeRef" };
          { name = "lockfileOut"; direction = Out; payload_type = "FlakeLock" } ];
      constraints =
        [ { id = "C-NIX-04";
            name = "LockfileIdempotence";
            expression = "lock(lock(f)) == lock(f)";
            formal_solver = "Z3" } ] };

    { kind = Flake_security_auditor_block;
      name = "FlakeSecurityAuditor";
      ports =
        [ { name = "closureIn"; direction = In; payload_type = "FlakeClosure" };
          { name = "advisoryReportOut"; direction = Out; payload_type = "AuditReport" };
          { name = "bomOut"; direction = Out; payload_type = "FlakeBOM" } ];
      constraints =
        [ { id = "C-NIX-05";
            name = "SupplyChainTraceability";
            expression = "forall pkg in closure: has_provenance(pkg)";
            formal_solver = "Why3" } ] };

    { kind = Devenv_runtime_block;
      name = "DevenvRuntimeEngine";
      ports =
        [ { name = "devenvConfigIn"; direction = In; payload_type = "DevenvNix" };
          { name = "shellEnvOut"; direction = Out; payload_type = "EnvironmentMap" } ];
      constraints =
        [ { id = "C-DEV-01";
            name = "LayerCompositionAssociativity";
            expression = "(L1 + L2) + L3 == L1 + (L2 + L3)";
            formal_solver = "Rocq" } ] };

    { kind = Process_compose_supervisor_block;
      name = "ProcessComposeSupervisor";
      ports =
        [ { name = "servicesIn"; direction = In; payload_type = "ServiceDefinitions" };
          { name = "processTreeOut"; direction = Out; payload_type = "ProcessTreeStatus" } ];
      constraints =
        [ { id = "C-DEV-02";
            name = "PortDisjointness";
            expression = "forall s1, s2: s1 != s2 => ports(s1) intersect ports(s2) == empty";
            formal_solver = "Z3" } ] };

    { kind = Intent_admission_controller_block;
      name = "IntentAdmissionController";
      ports =
        [ { name = "intentIn"; direction = In; payload_type = "DeclarativeIntent" };
          { name = "receiptOut"; direction = Out; payload_type = "ExecutionReceipt" } ];
      constraints =
        [ { id = "C-INTENT-01";
            name = "R31PolicyCompliance";
            expression = "admitted(intent) => verified_bounds(intent) && no_direct_shell_bypass(intent)";
            formal_solver = "Z3" } ] } ]

let find_block kind =
  List.find_opt (fun b -> b.kind = kind) all_blocks

let to_sysml_v2_dsl b =
  let port_lines =
    List.map
      (fun (p : port) ->
         let dir_str = match p.direction with In -> "in" | Out -> "out" | InOut -> "inout" in
         Printf.sprintf "    port %s : %s [direction: %s];" p.name p.payload_type dir_str)
      b.ports
  in
  let constraint_lines =
    List.map
      (fun (c : constraint_rule) ->
         Printf.sprintf "    constraint %s /* %s (solver: %s) */ {\n      %s\n    }"
           c.id c.name c.formal_solver c.expression)
      b.constraints
  in
  Printf.sprintf "part def %s {\n%s\n%s\n}"
    b.name
    (String.concat "\n" port_lines)
    (String.concat "\n" constraint_lines)

let to_yojson b =
  `Assoc
    [ ("name", `String b.name);
      ("ports", `List (List.map (fun (p : port) -> `Assoc [ ("name", `String p.name); ("type", `String p.payload_type) ]) b.ports));
      ("constraints", `List (List.map (fun (c : constraint_rule) -> `Assoc [ ("id", `String c.id); ("expr", `String c.expression); ("solver", `String c.formal_solver) ]) b.constraints)) ]
