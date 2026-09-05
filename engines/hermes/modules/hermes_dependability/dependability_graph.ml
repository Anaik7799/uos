type attempt_phase = Sequential_oracle | Bounded_parallel of { lane : int }

type attempt = { attempt_id : int; phase : attempt_phase }

type unit_kind =
  | Identity_admission
  | Formal_model
  | Formal_smt
  | Native_focused
  | Permit_capacity of int
  | Process_attempt of attempt
  | Process_reliability
  | Crash_window
  | Fpp_mbse
  | Full_gate

type cache_policy = Reusable | Always_run

type input_kind = Source_input | Configuration_input | Tool_input | Executable_input

type input_state = Present of string | Missing | Unreadable of string

type input_requirement = {
  key : string;
  kind : input_kind;
  expected_digest : string option;
}

type input_fact = { key : string; kind : input_kind; state : input_state }

type node = {
  id : string;
  kind : unit_kind;
  dependencies : string list;
  inputs : input_fact list;
  criticality : int;
  cache_policy : cache_policy;
}

type verdict =
  | Passed
  | Failed of string
  | Unavailable of string
  | Skipped
  | Corrupt of string

type authority_binding = {
  target_digest : string;
  policy_digest : string;
  criteria_digest : string;
  source_digest : string;
  configuration_digest : string;
  toolchain_digest : string;
  executable_digest : string;
  topology_digest : string;
  receipt_digest : string;
}

type cache_entry = {
  fingerprint : string;
  authority : authority_binding;
  verdict : verdict;
}

let sha256_string text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let is_hex_digit = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false

let valid_digest digest =
  String.length digest = 64 && String.for_all is_hex_digit digest

let duplicates values =
  let sorted = List.sort String.compare values in
  let rec collect acc = function
    | left :: (right :: _ as rest) when String.equal left right ->
        collect (left :: acc) rest
    | _ :: rest -> collect acc rest
    | [] -> List.rev (List.sort_uniq String.compare acc)
  in
  collect [] sorted

let module_sources =
  [ "modules/hermes_dependability/dependability_abandonment_protocol.ml";
    "modules/hermes_dependability/dependability_abandonment_protocol.mli";
    "modules/hermes_dependability/dependability_algebra.ml";
    "modules/hermes_dependability/dependability_algebra.mli";
    "modules/hermes_dependability/dependability_approval.ml";
    "modules/hermes_dependability/dependability_approval.mli";
    "modules/hermes_dependability/dependability_approval_crypto.ml";
    "modules/hermes_dependability/dependability_approval_crypto.mli";
    "modules/hermes_dependability/dependability_atlas.ml";
    "modules/hermes_dependability/dependability_atlas.mli";
    "modules/hermes_dependability/dependability_authority_store.ml";
    "modules/hermes_dependability/dependability_authority_store.mli";
    "modules/hermes_dependability/dependability_clock.ml";
    "modules/hermes_dependability/dependability_clock.mli";
    "modules/hermes_dependability/dependability_completion_store.ml";
    "modules/hermes_dependability/dependability_completion_store.mli";
    "modules/hermes_dependability/dependability_credential.ml";
    "modules/hermes_dependability/dependability_credential.mli";
    "modules/hermes_dependability/dependability_dispatch_store.ml";
    "modules/hermes_dependability/dependability_dispatch_store.mli";
    "modules/hermes_dependability/dependability_filesystem.ml";
    "modules/hermes_dependability/dependability_filesystem.mli";
    "modules/hermes_dependability/dependability_graph.ml";
    "modules/hermes_dependability/dependability_graph.mli";
    "modules/hermes_dependability/dependability_intent.ml";
    "modules/hermes_dependability/dependability_intent.mli";
    "modules/hermes_dependability/dependability_network.ml";
    "modules/hermes_dependability/dependability_network.mli";
    "modules/hermes_dependability/dependability_ontology.ml";
    "modules/hermes_dependability/dependability_ontology.mli";
    "modules/hermes_dependability/dependability_owner_inventory.ml";
    "modules/hermes_dependability/dependability_owner_inventory.mli";
    "modules/hermes_dependability/dependability_process.ml";
    "modules/hermes_dependability/dependability_process.mli";
    "modules/hermes_dependability/dependability_process_fixture.ml";
    "modules/hermes_dependability/dependability_process_protocol.ml";
    "modules/hermes_dependability/dependability_process_protocol.mli";
    "modules/hermes_dependability/dependability_process_test_protocol.ml";
    "modules/hermes_dependability/dependability_process_test_protocol.mli";
    "modules/hermes_dependability/dependability_recovery_vault.ml";
    "modules/hermes_dependability/dependability_recovery_vault.mli";
    "modules/hermes_dependability/dependability_sqlite.ml";
    "modules/hermes_dependability/dependability_sqlite.mli";
    "modules/hermes_dependability/dependability_sqlite_location.ml";
    "modules/hermes_dependability/dependability_sqlite_location.mli";
    "modules/hermes_dependability/dependability_sqlite_test_protocol.ml";
    "modules/hermes_dependability/dependability_sqlite_test_protocol.mli";
    "modules/hermes_dependability/dependability_surface.ml";
    "modules/hermes_dependability/dependability_surface.mli";
    "modules/hermes_dependability/dune";
    "modules/hermes_dependability/sqlite_lifecycle_model.ml";
    "modules/hermes_dependability/sqlite_lifecycle_model.mli";
    "modules/hermes_dependability/sqlite_lifecycle_solver.ml";
    "modules/hermes_dependability/sqlite_lifecycle_solver.mli";
    "modules/hermes_dependability/test_dependability_abandonment_protocol.ml";
    "modules/hermes_dependability/test_dependability_approval.ml";
    "modules/hermes_dependability/test_dependability_approval_crypto.ml";
    "modules/hermes_dependability/test_dependability_authority_store.ml";
    "modules/hermes_dependability/test_dependability_clock.ml";
    "modules/hermes_dependability/test_dependability_completion_store.ml";
    "modules/hermes_dependability/test_dependability_core.ml";
    "modules/hermes_dependability/test_dependability_credential.ml";
    "modules/hermes_dependability/test_dependability_dispatch_store.ml";
    "modules/hermes_dependability/test_dependability_filesystem.ml";
    "modules/hermes_dependability/test_dependability_graph.ml";
    "modules/hermes_dependability/test_dependability_meta.ml";
    "modules/hermes_dependability/test_dependability_network.ml";
    "modules/hermes_dependability/test_dependability_owner_inventory.ml";
    "modules/hermes_dependability/test_dependability_process.ml";
    "modules/hermes_dependability/test_dependability_process_protocol.ml";
    "modules/hermes_dependability/test_dependability_recovery_vault.ml";
    "modules/hermes_dependability/test_dependability_sqlite_location.ml";
    "modules/hermes_dependability/test_dependability_surface.ml";
    "modules/hermes_dependability/test_dependability_topology.ml";
    "modules/hermes_dependability/test_sqlite_lifecycle_model.ml";
    "modules/hermes_dependability/test_sqlite_lifecycle_smt.ml";
    "modules/hermes_dependability/dependability_topology.ml";
    "modules/hermes_dependability/dependability_topology.mli";
    "modules/hermes_dependability/dependability_writer_lease.ml";
    "modules/hermes_dependability/dependability_writer_lease.mli";
    "modules/hermes_dependability/test_dependability_writer_lease.ml";
    "modules/hermes_ops_dashboard/run_root_bootstrap.ml";
    "modules/hermes_ops_dashboard/run_root_bootstrap.mli";
    "modules/hermes_ops_dashboard/test_run_root_bootstrap.ml" ]

let source_requirement path : input_requirement =
  { key = "source:" ^ path; kind = Source_input; expected_digest = None }

let config_requirement key digest : input_requirement =
  { key = "config:" ^ key; kind = Configuration_input;
    expected_digest = Some digest }

let open_requirement kind key : input_requirement =
  { key; kind; expected_digest = None }

let required_inputs intent : input_requirement list =
  let source = Dependability_intent.source intent in
  let schedule =
    Dependability_intent.policy_of_intent intent
    |> Dependability_intent.reliability_schedule
  in
  let source_paths =
    module_sources
    @ Dependability_intent.target_sources (Dependability_intent.target intent)
    |> List.sort_uniq String.compare
  in
  let configurations =
    [ config_requirement "source-revision" (sha256_string source.source_revision);
      config_requirement "configuration" source.configuration_digest;
      config_requirement "authority" source.authority_digest;
      config_requirement "build" source.build_digest;
      config_requirement "provenance" source.provenance_digest;
      config_requirement "target" (Dependability_intent.target_digest intent);
      config_requirement "policy" (Dependability_intent.policy_digest intent);
      config_requirement "criteria" (Dependability_intent.criteria_digest intent);
      config_requirement "source-authority" (Dependability_intent.source_digest intent);
      config_requirement "intent" (Dependability_intent.digest intent);
      config_requirement "permit-topology"
        (Dependability_intent.permit_topology_digest schedule) ]
  in
  let tools =
    [ "tool:ocaml"; "tool:z3"; "tool:sqlite3-ocaml"; "tool:swarm";
      "tool:kernel-journal"; "tool:fpp"; "tool:mbse"; "tool:ops-verify" ]
    |> List.map (open_requirement Tool_input)
  in
  let executables =
    [ "executable:sqlite-lifecycle-model"; "executable:sqlite-lifecycle-smt";
      "executable:native-focused"; "executable:process-attempt";
      "executable:full-gate" ]
    |> List.map (open_requirement Executable_input)
  in
  List.map source_requirement source_paths @ configurations @ tools @ executables
  |> List.sort
       (fun (left : input_requirement) (right : input_requirement) ->
         String.compare left.key right.key)

let input_state_error key = function
  | Present digest when not (valid_digest digest) ->
      Some ("invalid present SHA-256: " ^ key)
  | Unreadable diagnostic_digest when not (valid_digest diagnostic_digest) ->
      Some ("invalid unreadable diagnostic SHA-256: " ^ key)
  | Present _ | Missing | Unreadable _ -> None

let validate_materialized_inputs
    (requirements : input_requirement list) (facts : input_fact list) =
  let requirement_keys =
    List.map (fun (requirement : input_requirement) -> requirement.key) requirements
  in
  let fact_keys = List.map (fun (fact : input_fact) -> fact.key) facts in
  let errors =
    duplicates fact_keys
    |> List.map (fun key -> "duplicate materialized input: " ^ key)
  in
  let errors =
    List.fold_left
      (fun errors key ->
        if List.mem key fact_keys then errors else ("missing materialized input: " ^ key) :: errors)
      errors requirement_keys
  in
  let errors =
    List.fold_left
      (fun errors key ->
        if List.mem key requirement_keys then errors
        else ("unknown materialized input: " ^ key) :: errors)
      errors fact_keys
  in
  let errors =
    List.fold_left
      (fun errors (fact : input_fact) ->
        let errors =
          match input_state_error fact.key fact.state with
          | None -> errors
          | Some error -> error :: errors
        in
        match
          List.find_opt
            (fun (requirement : input_requirement) -> requirement.key = fact.key)
            requirements
        with
        | None -> errors
        | Some requirement when requirement.kind <> fact.kind ->
            ("materialized input kind mismatch: " ^ fact.key) :: errors
        | Some { expected_digest = Some expected; _ }
          when fact.state <> Present expected ->
            ("materialized configuration identity mismatch: " ^ fact.key) :: errors
        | Some _ -> errors)
      errors facts
  in
  List.sort_uniq String.compare errors

let node ~id ~kind ~dependencies ~inputs ~criticality ~cache_policy : node =
  { id; kind; dependencies; inputs; criticality; cache_policy }

let attempt_node_id attempt_id = Printf.sprintf "process-attempt-%03d" attempt_id
let permit_node_id lane = Printf.sprintf "permit-lane-%d" lane

let frozen_permit_topology_digest =
  match
    Dependability_intent.make_reliability_schedule
      ~sequential_oracle_attempts:32 ~bounded_parallel_attempts:268
      ~lane_count:5
  with
  | Ok schedule -> Dependability_intent.permit_topology_digest schedule
  | Error diagnostic ->
      invalid_arg ("invalid frozen dependability campaign: " ^ diagnostic)

let rec build ~inputs intent =
  let requirements = required_inputs intent in
  match validate_materialized_inputs requirements inputs with
  | _ :: _ as errors -> Error errors
  | [] ->
      let fact key : input_fact =
        List.find (fun (value : input_fact) -> value.key = key) inputs
      in
      let source path = fact ("source:" ^ path) in
      let select keys : input_fact list =
        List.map fact keys
        |> List.sort
             (fun (a : input_fact) (b : input_fact) ->
               String.compare a.key b.key)
      in
      let select_sources paths = List.map source paths in
      let target_sources =
        Dependability_intent.target_sources (Dependability_intent.target intent)
      in
      let identity_sources =
        [ "dependability_intent.ml"; "dependability_intent.mli";
          "dependability_graph.ml"; "dependability_graph.mli";
          "test_dependability_core.ml"; "test_dependability_graph.ml"; "dune" ]
        |> List.map (fun name -> "modules/hermes_dependability/" ^ name)
      in
      let identity_inputs =
        select_sources identity_sources
        @ select
            [ "config:source-revision"; "config:configuration";
              "config:authority"; "config:build"; "config:provenance";
              "config:target"; "config:policy"; "config:criteria";
              "config:source-authority"; "config:intent"; "tool:ocaml" ]
      in
      let model_inputs =
        select_sources
          [ "modules/hermes_dependability/sqlite_lifecycle_model.ml";
            "modules/hermes_dependability/sqlite_lifecycle_model.mli";
            "modules/hermes_dependability/test_sqlite_lifecycle_model.ml" ]
        @ select [ "tool:ocaml"; "executable:sqlite-lifecycle-model" ]
      in
      let solver_inputs =
        select_sources
          [ "modules/hermes_dependability/sqlite_lifecycle_solver.ml";
            "modules/hermes_dependability/sqlite_lifecycle_solver.mli";
            "modules/hermes_dependability/test_sqlite_lifecycle_smt.ml" ]
        @ select [ "tool:z3"; "executable:sqlite-lifecycle-smt" ]
      in
      let native_inputs =
        select_sources
          ([ "modules/hermes_dependability/dependability_sqlite.ml";
             "modules/hermes_dependability/dependability_sqlite.mli";
             "modules/hermes_dependability/test_sqlite_lifecycle_model.ml" ]
           @ target_sources)
        @ select [ "tool:sqlite3-ocaml"; "executable:native-focused" ]
      in
      let topology_sources =
        select_sources
          [ "modules/hermes_dependability/dependability_topology.ml";
            "modules/hermes_dependability/dependability_topology.mli" ]
      in
      let topology_inputs =
        topology_sources
        @ select [ "config:permit-topology"; "tool:swarm";
                   "executable:process-attempt" ]
      in
      let attempt_inputs =
        select_sources
          (target_sources
           @ [ "modules/hermes_dependability/dependability_process.ml";
               "modules/hermes_dependability/dependability_process.mli";
               "modules/hermes_dependability/dependability_process_fixture.ml";
               "modules/hermes_dependability/test_dependability_process.ml";
               "modules/hermes_dependability/test_dependability_topology.ml" ])
        @ topology_inputs
      in
      let fpp_inputs =
        select_sources
          [ "modules/hermes_dependability/dependability_algebra.ml";
            "modules/hermes_dependability/dependability_algebra.mli";
            "modules/hermes_dependability/dependability_atlas.ml";
            "modules/hermes_dependability/dependability_atlas.mli";
            "modules/hermes_dependability/dependability_ontology.ml";
            "modules/hermes_dependability/dependability_ontology.mli";
            "modules/hermes_dependability/dependability_surface.ml";
            "modules/hermes_dependability/dependability_surface.mli";
            "modules/hermes_dependability/test_dependability_surface.ml";
            "modules/hermes_dependability/test_dependability_meta.ml" ]
        @ topology_sources @ select [ "tool:fpp"; "tool:mbse" ]
      in
      let full_inputs =
        select_sources
          (List.sort_uniq String.compare
             (module_sources @ target_sources
              @ [ "modules/hermes_dependability/dependability_surface.ml";
                  "modules/hermes_dependability/dependability_surface.mli";
                  "modules/hermes_dependability/test_dependability_surface.ml" ]))
        @ select [ "tool:ops-verify"; "executable:full-gate" ]
      in
      let schedule =
        Dependability_intent.policy_of_intent intent
        |> Dependability_intent.reliability_schedule
      in
      let sequential = Dependability_intent.sequential_attempt_ids schedule in
      let partitions = Dependability_intent.parallel_lane_partitions schedule in
      let parallel_predecessors =
        partitions
        |> List.mapi (fun lane ids ->
               let rec rows previous = function
                 | [] -> []
                 | id :: rest -> (id, lane, previous) :: rows (attempt_node_id id) rest
               in
               rows (permit_node_id lane) ids)
        |> List.concat
      in
      let attempt_node attempt_id =
        match List.find_opt (fun id -> id = attempt_id) sequential with
        | Some _ ->
            let dependency =
              if attempt_id = 0 then "native-focused"
              else attempt_node_id (attempt_id - 1)
            in
            node ~id:(attempt_node_id attempt_id)
              ~kind:(Process_attempt { attempt_id; phase = Sequential_oracle })
              ~dependencies:[ dependency ] ~inputs:attempt_inputs ~criticality:90
              ~cache_policy:Reusable
        | None ->
            let _, lane, predecessor =
              List.find (fun (id, _, _) -> id = attempt_id) parallel_predecessors
            in
            node ~id:(attempt_node_id attempt_id)
              ~kind:(Process_attempt
                       { attempt_id; phase = Bounded_parallel { lane } })
              ~dependencies:[ predecessor ] ~inputs:attempt_inputs ~criticality:90
              ~cache_policy:Reusable
      in
      let permit_nodes =
        List.init (Dependability_intent.lane_count schedule) (fun lane ->
            node ~id:(permit_node_id lane) ~kind:(Permit_capacity lane)
              ~dependencies:[ "native-focused" ] ~inputs:topology_inputs
              ~criticality:91 ~cache_policy:Reusable)
      in
      let attempt_nodes =
        Dependability_intent.all_attempt_ids schedule |> List.map attempt_node
      in
      let all_attempt_node_ids =
        List.map (fun (value : node) -> value.id) attempt_nodes
      in
      let graph =
        [ node ~id:"identity-admission" ~kind:Identity_admission ~dependencies:[]
            ~inputs:identity_inputs ~criticality:100 ~cache_policy:Reusable;
          node ~id:"lifecycle-model" ~kind:Formal_model
            ~dependencies:[ "identity-admission" ] ~inputs:model_inputs
            ~criticality:95 ~cache_policy:Reusable;
          node ~id:"lifecycle-smt" ~kind:Formal_smt
            ~dependencies:[ "lifecycle-model" ] ~inputs:solver_inputs
            ~criticality:94 ~cache_policy:Reusable;
          node ~id:"native-focused" ~kind:Native_focused
            ~dependencies:[ "lifecycle-smt" ] ~inputs:native_inputs
            ~criticality:92 ~cache_policy:Reusable ]
        @ permit_nodes @ attempt_nodes
        @ [ node ~id:"process-reliability" ~kind:Process_reliability
              ~dependencies:all_attempt_node_ids ~inputs:topology_inputs
              ~criticality:90 ~cache_policy:Reusable;
            node ~id:"crash-window" ~kind:Crash_window
              ~dependencies:[ "process-reliability" ]
              ~inputs:(select [ "tool:kernel-journal" ]) ~criticality:99
              ~cache_policy:Always_run;
            node ~id:"fpp-mbse" ~kind:Fpp_mbse
              ~dependencies:[ "identity-admission" ] ~inputs:fpp_inputs
              ~criticality:80 ~cache_policy:Reusable;
            node ~id:"full-gate" ~kind:Full_gate
              ~dependencies:
                [ "lifecycle-smt"; "native-focused"; "process-reliability";
                  "crash-window"; "fpp-mbse" ]
              ~inputs:full_inputs
              ~criticality:100 ~cache_policy:Always_run ]
      in
      let used_input_keys =
        graph |> List.concat_map (fun (node : node) -> node.inputs)
        |> List.map (fun (input : input_fact) -> input.key)
        |> List.sort_uniq String.compare
      in
      let supplied_input_keys =
        inputs |> List.map (fun (input : input_fact) -> input.key)
        |> List.sort_uniq String.compare
      in
      if used_input_keys <> supplied_input_keys then
        Error [ "materialized input manifest is not fully bound into graph nodes" ]
      else
        match validate graph with [] -> Ok graph | errors -> Error errors

and validate nodes =
  let ids = List.map (fun (node : node) -> node.id) nodes in
  let errors =
    duplicates ids |> List.map (fun id -> "duplicate node id: " ^ id)
  in
  let errors =
    List.fold_left
      (fun errors (node : node) ->
        let errors = if String.trim node.id = "" then "empty node id" :: errors else errors in
        let errors =
          if node.criticality < 0 || node.criticality > 100 then
            ("criticality outside 0..100: " ^ node.id) :: errors
          else errors
        in
        let errors =
          List.fold_left
            (fun errors dependency ->
              if dependency = node.id then ("self dependency: " ^ node.id) :: errors
              else if not (List.mem dependency ids) then
                (Printf.sprintf "unknown dependency: %s -> %s" node.id dependency) :: errors
              else errors)
            errors node.dependencies
        in
        let errors =
          List.fold_left
            (fun errors dependency ->
              (Printf.sprintf "duplicate dependency: %s -> %s" node.id dependency) :: errors)
            errors (duplicates node.dependencies)
        in
        let errors =
          List.fold_left
            (fun errors key ->
              (Printf.sprintf "duplicate input identity: %s -> %s" node.id key) :: errors)
            errors
            (duplicates
               (List.map (fun (input : input_fact) -> input.key) node.inputs))
        in
        let errors =
          List.fold_left
            (fun errors (input : input_fact) ->
              if String.trim input.key = "" then ("empty input identity: " ^ node.id) :: errors
              else
                match input_state_error input.key input.state with
                | None -> errors
                | Some error -> error :: errors)
            errors node.inputs
        in
        match node.kind with
        | Permit_capacity lane when lane < 0 || lane >= 5 ->
            ("permit lane outside exact range 0..4: " ^ node.id) :: errors
        | Permit_capacity lane when node.id <> permit_node_id lane ->
            ("permit node identity mismatch: " ^ node.id) :: errors
        | Process_attempt attempt when attempt.attempt_id < 0 ->
            ("negative attempt id: " ^ node.id) :: errors
        | Process_attempt { phase = Bounded_parallel { lane }; _ }
          when lane < 0 || lane >= 5 ->
            ("attempt lane outside exact range 0..4: " ^ node.id) :: errors
        | Process_attempt attempt
          when node.id <> attempt_node_id attempt.attempt_id ->
            ("attempt node identity mismatch: " ^ node.id) :: errors
        | Identity_admission | Formal_model | Formal_smt | Native_focused
        | Permit_capacity _ | Process_attempt _ | Process_reliability
        | Crash_window | Fpp_mbse | Full_gate -> errors)
      errors nodes
  in
  let fixed_nodes =
    [ ("identity-admission", Identity_admission, []);
      ("lifecycle-model", Formal_model, [ "identity-admission" ]);
      ("lifecycle-smt", Formal_smt, [ "lifecycle-model" ]);
      ("native-focused", Native_focused, [ "lifecycle-smt" ]);
      ("crash-window", Crash_window, [ "process-reliability" ]);
      ("fpp-mbse", Fpp_mbse, [ "identity-admission" ]);
      ( "full-gate", Full_gate,
        [ "lifecycle-smt"; "native-focused"; "process-reliability";
          "crash-window"; "fpp-mbse" ] ) ]
  in
  let errors =
    List.fold_left
      (fun errors (id, expected_kind, expected_dependencies) ->
        match List.find_opt (fun (node : node) -> node.id = id) nodes with
        | None -> errors
        | Some node
          when node.kind = expected_kind
               && node.dependencies = expected_dependencies -> errors
        | Some _ -> ("fixed graph node shape drift: " ^ id) :: errors)
      errors fixed_nodes
  in
  let campaign_errors =
    let attempts =
      List.filter_map
        (fun (node : node) ->
          match node.kind with Process_attempt attempt -> Some (node, attempt)
          | _ -> None)
        nodes
    in
    if attempts = [] then []
    else
      let attempt_ids = List.map (fun (_, attempt) -> attempt.attempt_id) attempts in
      let sequential =
        List.filter_map
          (fun (node, attempt) ->
            match attempt.phase with Sequential_oracle -> Some (node, attempt) | _ -> None)
          attempts
        |> List.sort (fun (_, a) (_, b) -> Int.compare a.attempt_id b.attempt_id)
      in
      let parallel =
        List.filter_map
          (fun (node, attempt) ->
            match attempt.phase with
            | Bounded_parallel { lane } -> Some (node, attempt, lane)
            | Sequential_oracle -> None)
          attempts
      in
      let permits =
        List.filter_map
          (fun (node : node) ->
            match node.kind with Permit_capacity lane -> Some (node, lane)
            | _ -> None)
          nodes
      in
      let errors =
        if List.sort_uniq Int.compare attempt_ids = List.init 300 Fun.id then []
        else [ "campaign attempt ids are not the exact global range 0..299" ]
      in
      let errors =
        if List.map (fun (_, attempt) -> attempt.attempt_id) sequential = List.init 32 Fun.id
        then errors else "sequential oracle is not the exact 0..31 chain" :: errors
      in
      let errors =
        if
          (List.map (fun (_, attempt, _) -> attempt.attempt_id) parallel
           |> List.sort Int.compare) = List.init 268 (fun index -> index + 32)
        then errors else "parallel attempt ids are not the exact 32..299 range" :: errors
      in
      let errors =
        if List.length permits = 5
           && (List.map snd permits |> List.sort Int.compare) = List.init 5 Fun.id
        then errors else "permit lanes are not the exact range 0..4" :: errors
      in
      let errors =
        List.fold_left
          (fun errors (node, lane) ->
            if node.id = permit_node_id lane
               && node.dependencies = [ "native-focused" ]
            then errors
            else ("invalid permit identity or dependency: " ^ node.id) :: errors)
          errors permits
      in
      let errors =
        List.fold_left
          (fun errors (node, attempt) ->
            let expected =
              if attempt.attempt_id = 0 then "native-focused"
              else attempt_node_id (attempt.attempt_id - 1)
            in
            if node.dependencies = [ expected ] then errors
            else ("broken sequential dependency: " ^ node.id) :: errors)
          errors sequential
      in
      let errors =
        List.fold_left
          (fun errors (node, attempt, lane) ->
            let expected_lane = (attempt.attempt_id - 32) mod 5 in
            if lane = expected_lane then errors
            else
              (Printf.sprintf "parallel attempt uses wrong permit lane: %s -> %d"
                 node.id lane) :: errors)
          errors parallel
      in
      let errors =
        List.init 5 Fun.id
        |> List.fold_left
             (fun errors lane ->
               let lane_attempts =
                 parallel |> List.filter (fun (_, _, actual) -> actual = lane)
                 |> List.sort (fun (_, a, _) (_, b, _) ->
                        Int.compare a.attempt_id b.attempt_id)
               in
               let rec check errors previous = function
                 | [] -> errors
                 | (node, _, _) :: rest ->
                     let errors =
                       if node.dependencies = [ previous ] then errors
                       else ("broken permit-lane dependency: " ^ node.id) :: errors
                     in
                     check errors node.id rest
               in
               check errors (permit_node_id lane) lane_attempts)
             errors
      in
      let topology_digests =
        permits
        |> List.filter_map (fun (node, _) ->
               match
                 List.find_opt
                   (fun (input : input_fact) ->
                     input.key = "config:permit-topology")
                   node.inputs
               with
               | Some { state = Present digest; _ } -> Some digest
               | Some _ | None -> None)
        |> List.sort_uniq String.compare
      in
      let errors =
        if topology_digests = [ frozen_permit_topology_digest ]
        then errors else "permit topology digest is missing or inconsistent" :: errors
      in
      let expected_dependencies = List.map (fun (node, _) -> node.id) attempts |> List.sort String.compare in
      match
        List.find_opt
          (fun (node : node) -> node.id = "process-reliability") nodes
      with
      | Some aggregate
        when List.sort String.compare aggregate.dependencies = expected_dependencies -> errors
      | Some _ -> "process aggregate does not depend on every attempt" :: errors
      | None -> "process aggregate is missing" :: errors
  in
  let errors = List.sort_uniq String.compare (campaign_errors @ errors) in
  if errors <> [] || nodes = [] then
    List.sort_uniq String.compare
      (if nodes = [] then "graph is empty" :: errors else errors)
  else
    let indegree = Hashtbl.create (List.length nodes) in
    List.iter
      (fun (node : node) ->
        Hashtbl.add indegree node.id (List.length node.dependencies))
      nodes;
    let rec consume count =
      match
        List.find_opt
          (fun (node : node) -> Hashtbl.find indegree node.id = 0) nodes
      with
      | None -> count
      | Some node ->
          Hashtbl.replace indegree node.id (-1);
          List.iter
            (fun candidate ->
              if List.mem node.id candidate.dependencies then
                Hashtbl.replace indegree candidate.id
                  (Hashtbl.find indegree candidate.id - 1))
            nodes;
          consume (count + 1)
    in
    if consume 0 = List.length nodes then [] else [ "dependency cycle" ]

let compare_ready left right =
  match Int.compare right.criticality left.criticality with
  | 0 -> String.compare left.id right.id
  | order -> order

let topo_order nodes =
  match validate nodes with
  | error :: rest ->
      invalid_arg ("Dependability_graph.topo_order: " ^ String.concat "; " (error :: rest))
  | [] ->
      let indegree = Hashtbl.create (List.length nodes) in
      List.iter
        (fun (node : node) ->
          Hashtbl.add indegree node.id (List.length node.dependencies))
        nodes;
      let rec loop ordered remaining =
        if remaining = 0 then List.rev ordered
        else
          let ready =
            nodes
            |> List.filter
                 (fun (node : node) -> Hashtbl.find indegree node.id = 0)
            |> List.sort compare_ready
          in
          match ready with
          | [] -> invalid_arg "Dependability_graph.topo_order: dependency cycle"
          | next :: _ ->
              Hashtbl.replace indegree next.id (-1);
              List.iter
                (fun candidate ->
                  if List.mem next.id candidate.dependencies then
                    Hashtbl.replace indegree candidate.id
                      (Hashtbl.find indegree candidate.id - 1))
                nodes;
              loop (next :: ordered) (remaining - 1)
      in
      loop [] (List.length nodes)

let input_kind_name = function
  | Source_input -> "source"
  | Configuration_input -> "configuration"
  | Tool_input -> "tool"
  | Executable_input -> "executable"

let kind_json = function
  | Identity_admission -> `Assoc [ ("kind", `String "identity-admission") ]
  | Formal_model -> `Assoc [ ("kind", `String "formal-model") ]
  | Formal_smt -> `Assoc [ ("kind", `String "formal-smt") ]
  | Native_focused -> `Assoc [ ("kind", `String "native-focused") ]
  | Permit_capacity lane ->
      `Assoc [ ("kind", `String "permit-capacity"); ("lane", `Int lane) ]
  | Process_attempt { attempt_id; phase = Sequential_oracle } ->
      `Assoc [ ("attempt_id", `Int attempt_id);
               ("kind", `String "process-attempt");
               ("phase", `String "sequential-oracle") ]
  | Process_attempt { attempt_id; phase = Bounded_parallel { lane } } ->
      `Assoc [ ("attempt_id", `Int attempt_id);
               ("kind", `String "process-attempt"); ("lane", `Int lane);
               ("phase", `String "bounded-parallel") ]
  | Process_reliability -> `Assoc [ ("kind", `String "process-reliability") ]
  | Crash_window -> `Assoc [ ("kind", `String "crash-window") ]
  | Fpp_mbse -> `Assoc [ ("kind", `String "fpp-mbse") ]
  | Full_gate -> `Assoc [ ("kind", `String "full-gate") ]

let cache_policy_name = function Reusable -> "reusable" | Always_run -> "always-run"

let state_json input =
  let state_fields =
    match input.state with
    | Present digest -> [ ("sha256", `String digest); ("state", `String "present") ]
    | Missing -> [ ("sha256", `Null); ("state", `String "missing") ]
    | Unreadable diagnostic_digest ->
        [ ("sha256", `String diagnostic_digest); ("state", `String "unreadable") ]
  in
  `Assoc
    ([ ("input_kind", `String (input_kind_name input.kind));
       ("key", `String input.key) ] @ state_fields)

let canonical_pairs label values =
  values |> List.sort (fun (left, _) (right, _) -> String.compare left right)
  |> List.map (fun (key, value) ->
         `Assoc [ ("category", `String label); ("key", `String key);
                  ("value", `String value) ])

let fingerprint node ~parents =
  List.iter
    (fun (input : input_fact) ->
      match input_state_error input.key input.state with
      | None -> ()
      | Some error -> invalid_arg ("Dependability_graph.fingerprint: " ^ error))
    node.inputs;
  `Assoc
    [ ("cache_policy", `String (cache_policy_name node.cache_policy));
      ("criticality", `Int node.criticality);
      ("dependencies",
       `List (node.dependencies |> List.sort String.compare
              |> List.map (fun dependency -> `String dependency)));
      ("id", `String node.id); ("inputs", `List (node.inputs |> List.sort (fun a b -> String.compare a.key b.key) |> List.map state_json));
      ("kind", kind_json node.kind); ("parents", `List (canonical_pairs "parent" parents)) ]
  |> Yojson.Safe.to_string |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let fingerprints nodes =
  let ordered = topo_order nodes in
  let known = Hashtbl.create (List.length nodes) in
  List.map
    (fun (node : node) ->
      let parents =
        List.map (fun dependency -> (dependency, Hashtbl.find known dependency)) node.dependencies
      in
      let value = fingerprint node ~parents in
      Hashtbl.add known node.id value;
      (node.id, value))
    ordered

let validate_identity_map ~label ~node_ids entries =
  let entry_ids = List.map fst entries in
  match duplicates entry_ids with
  | duplicate :: _ ->
      invalid_arg (Printf.sprintf "Dependability_graph.%s: duplicate id %s" label duplicate)
  | [] ->
      List.iter
        (fun (id, _) ->
          if not (List.mem id node_ids) then
            invalid_arg (Printf.sprintf "Dependability_graph.%s: unknown id %s" label id))
        entries

let binding_digests binding =
  [ binding.target_digest; binding.policy_digest; binding.criteria_digest;
    binding.source_digest; binding.configuration_digest; binding.toolchain_digest;
    binding.executable_digest; binding.topology_digest; binding.receipt_digest ]

let valid_binding binding = List.for_all valid_digest (binding_digests binding)

let dirty_frontier ~fingerprints:fingerprint_rows ~authorities ~cache nodes =
  let ordered = topo_order nodes in
  let node_ids = List.map (fun (node : node) -> node.id) ordered in
  validate_identity_map ~label:"dirty_frontier fingerprints" ~node_ids fingerprint_rows;
  validate_identity_map ~label:"dirty_frontier authorities" ~node_ids authorities;
  validate_identity_map ~label:"dirty_frontier cache" ~node_ids cache;
  if List.length fingerprint_rows <> List.length node_ids then
    invalid_arg "Dependability_graph.dirty_frontier: fingerprint map is not total";
  if List.length authorities <> List.length node_ids then
    invalid_arg "Dependability_graph.dirty_frontier: authority map is not total";
  List.iter
    (fun (id, value) ->
      if not (valid_digest value) then
        invalid_arg ("Dependability_graph.dirty_frontier: invalid fingerprint for " ^ id))
    fingerprint_rows;
  List.iter
    (fun (id, authority) ->
      if not (valid_binding authority) then
        invalid_arg ("Dependability_graph.dirty_frontier: invalid authority binding for " ^ id))
    authorities;
  let fingerprint_of id =
    match List.assoc_opt id fingerprint_rows with
    | Some value -> value
    | None -> invalid_arg ("Dependability_graph.dirty_frontier: missing fingerprint for " ^ id)
  in
  let tainted = Hashtbl.create (List.length nodes) in
  let rerun = Hashtbl.create (List.length nodes) in
  List.iter
    (fun (node : node) ->
      let expected = fingerprint_of node.id in
      let expected_authority =
        match List.assoc_opt node.id authorities with
        | Some authority -> authority
        | None -> invalid_arg ("Dependability_graph.dirty_frontier: missing authority for " ^ node.id)
      in
      let dependency_tainted =
        List.exists (fun dependency -> Hashtbl.mem tainted dependency) node.dependencies
      in
      let exact_pass =
        match List.assoc_opt node.id cache with
        | Some { fingerprint; authority; verdict = Passed } ->
            fingerprint = expected && valid_binding authority && authority = expected_authority
        | Some _ | None -> false
      in
      if dependency_tainted || not exact_pass then Hashtbl.add tainted node.id ();
      if dependency_tainted || not exact_pass || node.cache_policy = Always_run then
        Hashtbl.add rerun node.id ())
    ordered;
  List.filter_map
    (fun (node : node) ->
      if Hashtbl.mem rerun node.id then Some node.id else None)
    ordered
