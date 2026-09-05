type effect_policy = Pure_diagnosis | Corrective_via_bridge of string
type fpp_mapping = { owner : string; component : string; channel : string }
type t = { stable_id : string; failure_family : string; objective : string; target_module_id : string; symptom_patterns : string list; assumptions : string list; constraints : string list; success_criteria : string list; path : Ops_capability.coordinate list; capability_ids : string list; configuration_ids : string list; surfaces : (Ops_capability.surface * Ops_capability.applicability) list; effect_policy : effect_policy; fpp : fpp_mapping; dependability : Debug_dependability.t; hypotheses : Debug_ontology.hypothesis list; next_measurement : Debug_ontology.discriminator }
let coordinate level phase = Ops_capability.{ level; phase }
let path =
  [ coordinate Ops_capability.L0 Ops_capability.Observe;
    coordinate Ops_capability.L1 Ops_capability.Orient;
    coordinate Ops_capability.L2 Ops_capability.Decide;
    coordinate Ops_capability.L3 Ops_capability.Act;
    coordinate Ops_capability.L0 Ops_capability.Observe ]

let surfaces =
  [ Ops_capability.Ocaml_api; Ops_capability.Cli;
    Ops_capability.Mcp; Ops_capability.Zenoh ]
  |> List.map (fun surface -> (surface, Ops_capability.Applicable))

let bounds = Debug_dependability.{
  timeout_ms = 120_000; maximum_memory_bytes = 536_870_912L;
  maximum_output_bytes = 262_144; maximum_attempts = 1 }

let dependability family = Debug_dependability.{
  reproduction = "ops completion debug debug." ^ family
    ^ " --scope control-plane --request-id RUN_ID";
  failure_signature = "debug.failure." ^ family;
  deterministic_seed = Some ("debug-seed-" ^ family);
  bounds;
  required_controls = [ "control.positive." ^ family; "control.negative." ^ family ];
  mutation_targets = [ "mutant.omit-evidence." ^ family; "mutant.substitute-origin." ^ family ];
  concurrency_checks = [ "check.teardown." ^ family; "check.replay." ^ family ];
  verify_original = true; verify_dependency_cone = true }

let hypothesis family suffix origin statement = Debug_ontology.{
  hypothesis_id = "hypothesis." ^ family ^ "." ^ suffix;
  statement; rca_origin = origin;
  predictions = [ "prediction." ^ family ^ "." ^ suffix ] }

let make ~family ~objective ~target_module_id ~component ~symptoms
    first_origin first_statement second_origin second_statement =
  let hypotheses =
    [ hypothesis family "primary" first_origin first_statement;
      hypothesis family "alternative" second_origin second_statement ]
  in
  let next_measurement = Debug_ontology.{
    discriminator_id = "measurement." ^ family;
    hypothesis_ids = List.map (fun item -> item.hypothesis_id) hypotheses;
    measurement = "Run the smallest bounded measurement that separates the two declared predictions";
    maximum_cost = 1 }
  in
  { stable_id = "debug." ^ family; failure_family = family; objective;
    target_module_id; symptom_patterns = symptoms;
    assumptions = [ "the captured failure body is complete" ];
    constraints = [ "do not correct before discrimination";
                    "timeout is an observation, not a cause" ];
    success_criteria = [ "one cause survives a discriminating measurement";
                         "the original symptom and dependency cone verify freshly" ];
    path; capability_ids = [ "capability.debug-observe" ];
    configuration_ids = []; surfaces;
    effect_policy = Corrective_via_bridge "activity.debug-correction";
    fpp = { owner = "Operations"; component;
            channel = "ops.debug." ^ String.map (function '-' -> '_' | c -> c) family };
    dependability = dependability family; hypotheses; next_measurement }

let all =
  [ make ~family:"build-package-resolution"
      ~objective:"Separate package-manager scope drift from a missing dependency"
      ~target_module_id:"module.hermes-harness" ~component:"assuranceGate"
      ~symptoms:[ "Library not found"; "nested dune invocation exits 2" ]
      Ops_capability.Environment "installed library is hidden by package-management mode"
      Ops_capability.Specification "the Dune stanza omits the required library";
    make ~family:"formal-coverage-gap"
      ~objective:"Establish why an ontology component lacks formal coverage"
      ~target_module_id:"module.hermes-harness" ~component:"z3FormalGate"
      ~symptoms:[ "component uncovered"; "formal coverage alignment fails" ]
      Ops_capability.Implementation "the coverage registry lacks the component artifact"
      Ops_capability.Specification "the ontology contains a component outside the intended denominator";
    make ~family:"live-oracle-timeout"
      ~objective:"Separate unavailable or slow live oracles from local deadlock"
      ~target_module_id:"module.swarm" ~component:"resourceSampler"
      ~symptoms:[ "exit 124"; "live request does not finish within containment" ]
      Ops_capability.Environment "the external oracle exceeds its response envelope"
      Ops_capability.Implementation "local supervision or teardown prevents termination";
    make ~family:"sqlite-sidecar-race"
      ~objective:"Discriminate a disappearing SQLite sidecar from an invalid tracked-language artifact"
      ~target_module_id:"module.hermes-ops" ~component:"runEventStore"
      ~symptoms:[ "No such file or directory"; "database journal path disappears during scan" ]
      Ops_capability.Implementation "the scanner races SQLite sidecar creation and deletion"
      Ops_capability.Environment "another live process owns and removes the sidecar";
    make ~family:"r30-telemetry-ratchet"
      ~objective:"Locate the suite that increased the non-emitting telemetry denominator"
      ~target_module_id:"module.hermes-harness" ~component:"completionGate"
      ~symptoms:[ "RATCHET BREACHED"; "non-emitting suite count increased" ]
      Ops_capability.Implementation "a newly admitted suite omits Suite_telemetry emission"
      Ops_capability.Control "the ratchet baseline is stale relative to an accepted denominator change";
    make ~family:"operator-solver-invocation"
      ~objective:"Separate absent solver arguments from solver evidence failure"
      ~target_module_id:"module.hermes-ops-dashboard" ~component:"z3FormalGate"
      ~symptoms:[ "requires --z3 <solver>"; "operator authority blocks at admission" ]
      Ops_capability.Control "the governed suite invocation omits the required solver argument"
      Ops_capability.Environment "the declared solver is unavailable or unsupported";
    make ~family:"surface-divergence"
      ~objective:"Find command-receipt drift across OCaml CLI MCP and Zenoh"
      ~target_module_id:"module.hermes-ops" ~component:"assuranceGate"
      ~symptoms:[ "surface receipt differs"; "adapter normalization fails" ]
      Ops_capability.Implementation "one adapter reimplements or mutates command semantics"
      Ops_capability.Evidence "receipts were compared across different authority digests";
    make ~family:"fpp-projection-drift"
      ~objective:"Find divergence between typed authority and generated FPP or MBSE projections"
      ~target_module_id:"module.hermes-ops-dashboard" ~component:"z3FormalGate"
      ~symptoms:[ "projection stale"; "FPP component mapping unresolved" ]
      Ops_capability.Implementation "a projection was not regenerated from current authority"
      Ops_capability.Specification "the typed mapping names an invalid model component";
    make ~family:"bridge-admission"
      ~objective:"Establish which authority or action constraint prevents bridge admission"
      ~target_module_id:"module.hermes-ops-dashboard" ~component:"swarmExecutionBridge"
      ~symptoms:[ "bridge admission refused"; "authority digest differs" ]
      Ops_capability.Control "the admitted intent is stale or outside the action allowlist"
      Ops_capability.Implementation "the bridge dropped or substituted a typed intent field" ]
let find id = List.find_opt (fun item -> item.stable_id = id) all
let nonempty value = String.trim value <> ""
let unique values = List.length values = List.length (List.sort_uniq String.compare values)
let all_surface_names = [ Ops_capability.Ocaml_api; Cli; Mcp; Zenoh ]

let validate intents =
  let gaps = ref [] in
  let add message = gaps := message :: !gaps in
  if List.length intents <> 9 then add "debug intent denominator differs from nine";
  let ids = List.map (fun item -> item.stable_id) intents in
  if not (unique ids) then add "debug intent stable ids are not unique";
  List.iter (fun item ->
    if not (nonempty item.stable_id && nonempty item.failure_family
            && nonempty item.objective && nonempty item.target_module_id) then
      add (item.stable_id ^ " has empty identity or purpose");
    if item.symptom_patterns = [] || List.exists (Fun.negate nonempty) item.symptom_patterns then
      add (item.stable_id ^ " has no concrete symptom pattern");
    if item.constraints = [] || item.success_criteria = [] then
      add (item.stable_id ^ " has a vacuous debugging envelope");
    if item.path = [] then add (item.stable_id ^ " has no semantic path");
    if List.map fst item.surfaces |> List.sort_uniq compare
       <> List.sort_uniq compare all_surface_names then
      add (item.stable_id ^ " does not declare exactly four surfaces");
    begin match item.effect_policy with
    | Pure_diagnosis -> add (item.stable_id ^ " does not declare correction mediation")
    | Corrective_via_bridge activity when not (nonempty activity) ->
        add (item.stable_id ^ " has an empty bridge activity")
    | Corrective_via_bridge _ -> ()
    end;
    if not (nonempty item.fpp.owner && nonempty item.fpp.component && nonempty item.fpp.channel) then
      add (item.stable_id ^ " has an incomplete FPP mapping");
    if List.length item.hypotheses < 2 then
      add (item.stable_id ^ " collapses competing hypotheses");
    let hypothesis_ids = List.map (fun item -> item.Debug_ontology.hypothesis_id) item.hypotheses in
    if not (unique hypothesis_ids) then add (item.stable_id ^ " has duplicate hypotheses");
    if item.next_measurement.hypothesis_ids <> hypothesis_ids
       || item.next_measurement.maximum_cost <= 0
       || not (nonempty item.next_measurement.measurement) then
      add (item.stable_id ^ " lacks a discriminating measurement");
    List.iter (fun gap -> add (item.stable_id ^ ": " ^ gap))
      (Debug_dependability.validate item.dependability);
    let expected_reproduction =
      "ops completion debug " ^ item.stable_id
      ^ " --scope control-plane --request-id RUN_ID"
    in
    if not (String.equal item.dependability.reproduction expected_reproduction) then
      add (item.stable_id ^ " has a noncanonical reproduction command")) intents;
  List.rev !gaps

let canonical item =
  String.concat "|"
    [ item.stable_id; item.failure_family; item.objective; item.target_module_id;
      String.concat "," item.symptom_patterns;
      String.concat "," item.constraints; String.concat "," item.success_criteria;
      String.concat "," (List.map (fun coordinate ->
        Ops_capability.string_of_level coordinate.Ops_capability.level ^ "/"
        ^ Ops_capability.string_of_phase coordinate.phase) item.path);
      String.concat "," item.capability_ids; String.concat "," item.configuration_ids;
      item.fpp.owner; item.fpp.component; item.fpp.channel;
      Debug_dependability.canonical item.dependability;
      String.concat "," (List.map (fun item -> item.Debug_ontology.hypothesis_id) item.hypotheses);
      item.next_measurement.discriminator_id ]

let source_digest =
  all |> List.map canonical |> String.concat "\n"
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
module For_test = struct
  type mutation = Drop_first | Duplicate_first | Empty_symptoms | Direct_effect | Unbounded_test | Collapse_hypotheses
  let replace_first update = function [] -> [] | first :: rest -> update first :: rest
  let mutate = function
    | Drop_first -> (match all with [] -> [] | _ :: rest -> rest)
    | Duplicate_first -> (match all with [] -> [] | first :: _ -> first :: all)
    | Empty_symptoms -> replace_first (fun item -> { item with symptom_patterns = [] }) all
    | Direct_effect -> replace_first (fun item -> { item with effect_policy = Pure_diagnosis }) all
    | Unbounded_test -> replace_first (fun item ->
        { item with dependability = { item.dependability with bounds =
            { item.dependability.bounds with timeout_ms = max_int } } }) all
    | Collapse_hypotheses -> replace_first (fun item ->
        { item with hypotheses = List.take 1 item.hypotheses }) all
end
