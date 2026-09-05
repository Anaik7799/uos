type edge_kind = Admission_flow | Evidence_flow | Projection_flow | Observation_flow
  | Planned_flow
type edge = { source : string; target : string; kind : edge_kind }

let edge kind source target = { source; target; kind }

let edges =
  [ edge Admission_flow "prompt" "command";
    edge Admission_flow "command" "rete_naive";
    edge Planned_flow "command" "rete_ul";
    edge Planned_flow "rete_ul" "raven_matrix";
    edge Planned_flow "raven_matrix" "stpa";
    edge Planned_flow "stpa" "fmea";
    edge Planned_flow "fmea" "ruliad";
    edge Planned_flow "ruliad" "stan";
    edge Planned_flow "stan" "z3";
    edge Planned_flow "z3" "assurance";
    edge Admission_flow "assurance" "swarm_bridge";
    edge Admission_flow "swarm_bridge" "swarm";
    edge Evidence_flow "swarm_bridge" "event";
    edge Planned_flow "swarm" "run";
    edge Evidence_flow "run" "event";
    edge Evidence_flow "event" "store";
    edge Evidence_flow "store" "metrics";
    edge Evidence_flow "store" "diagnostics";
    edge Observation_flow "resource_sampler" "metrics";
    edge Observation_flow "metrics" "fast_path";
    edge Observation_flow "fast_path" "diagnostics";
    edge Observation_flow "trace" "diagnostics";
    edge Observation_flow "rete_naive" "projection_criterion";
    edge Evidence_flow "metrics" "completion_criterion";
    edge Evidence_flow "diagnostics" "completion_criterion";
    edge Planned_flow "completion_criterion" "completion_receipt";
    edge Planned_flow "store" "zenoh";
    edge Planned_flow "zenoh" "dream";
    edge Planned_flow "dream" "bonsai";
    edge Planned_flow "bonsai" "webgl";
    edge Planned_flow "bonsai" "table";
    edge Planned_flow "webgl" "projection_receipt";
    edge Planned_flow "table" "projection_receipt";
    edge Planned_flow "projection_receipt" "projection_criterion";
    edge Observation_flow "run_ontology" "diagnostics";
    edge Observation_flow "run_atlas" "diagnostics";
    edge Observation_flow "run_algebra" "diagnostics" ]

module String_set = Set.Make (String)

let has_edge source target =
  List.exists (fun edge -> String.equal edge.source source && String.equal edge.target target) edges

let available node = match Run_ontology.find node with
  | Some { availability = Run_ontology.Available; _ } -> true
  | Some { availability = (Planned _ | Unavailable_observed _); _ } | None -> false

let has_active_edge source target =
  List.exists
    (fun edge -> edge.kind <> Planned_flow && String.equal edge.source source
      && String.equal edge.target target && available source && available target)
    edges

let successors node =
  edges |> List.filter (fun edge -> String.equal edge.source node)
  |> List.map (fun edge -> edge.target)

let can_reach source target =
  let rec visit seen = function
    | [] -> false
    | node :: _ when String.equal node target -> true
    | node :: rest when String_set.mem node seen -> visit seen rest
    | node :: rest -> visit (String_set.add node seen) (successors node @ rest)
  in
  visit String_set.empty [ source ]

let active_successors node =
  edges
  |> List.filter (fun edge -> edge.kind <> Planned_flow
       && String.equal edge.source node && available edge.source && available edge.target)
  |> List.map (fun edge -> edge.target)

let can_reach_available source target =
  let rec visit seen = function
    | [] -> false
    | node :: _ when String.equal node target -> true
    | node :: rest when String_set.mem node seen -> visit seen rest
    | node :: rest -> visit (String_set.add node seen) (active_successors node @ rest)
  in
  available source && available target && visit String_set.empty [ source ]

let criterion_nodes =
  [ "completion_criterion"; "completion_receipt";
    "projection_criterion" ]

let paths_to_criterion source =
  let bound = List.length Run_ontology.components + 1 in
  let rec walk seen path depth node =
    if depth > bound || String_set.mem node seen then []
    else
      let path = node :: path in
      if List.mem node criterion_nodes then [ List.rev path ]
      else
        successors node
        |> List.concat_map (walk (String_set.add node seen) path (depth + 1))
  in
  if Option.is_none (Run_ontology.find source) then []
  else walk String_set.empty [] 0 source

let edge_key edge =
  let kind = match edge.kind with Admission_flow -> "A" | Evidence_flow -> "E"
    | Projection_flow -> "P" | Observation_flow -> "O" | Planned_flow -> "X" in
  kind ^ ":" ^ edge.source ^ ":" ^ edge.target

let ( let* ) value f = match value with Ok result -> f result | Error _ as error -> error

let unique label values =
  if List.length values = List.length (List.sort_uniq String.compare values) then Ok ()
  else Error (label ^ " must be unique")

let validate_edges declarations =
  let* () = if declarations = [] then Error "atlas must contain edges" else Ok () in
  let* () = unique "atlas edges" (List.map edge_key declarations) in
  let* () =
    if List.for_all
        (fun edge -> not (String.equal edge.source edge.target)
          && Option.is_some (Run_ontology.find edge.source)
          && Option.is_some (Run_ontology.find edge.target))
        declarations
    then Ok () else Error "atlas contains a dangling or self edge"
  in
  if List.for_all
      (fun edge -> edge.kind = Planned_flow || (available edge.source && available edge.target))
      declarations
  then Ok ()
  else Error "atlas promotes an unavailable endpoint into an active flow"

let acyclic () =
  let rec visit visiting visited node =
    if String_set.mem node visiting then Error ("atlas cycle reaches " ^ node)
    else if String_set.mem node visited then Ok visited
    else
      let visiting = String_set.add node visiting in
      let rec children visited = function
        | [] -> Ok (String_set.add node visited)
        | child :: rest ->
            let* visited = visit visiting visited child in
            children visited rest
      in
      children visited (successors node)
  in
  let rec nodes visited = function
    | [] -> Ok ()
    | node :: rest -> let* visited = visit String_set.empty visited node in nodes visited rest
  in
  nodes String_set.empty Run_ontology.components

let validate () =
  let* () = Run_ontology.validate () in
  let* () = validate_edges edges in
  let* () = if edges = [] then Error "atlas must contain edges" else Ok () in
  let* () = unique "atlas edges" (List.map edge_key edges) in
  let* () =
    if List.for_all
        (fun edge -> not (String.equal edge.source edge.target)
          && Option.is_some (Run_ontology.find edge.source)
          && Option.is_some (Run_ontology.find edge.target)) edges
    then Ok () else Error "atlas contains a dangling or self edge" in
  let* () = acyclic () in
  let required_chain =
    [ ("prompt", "command"); ("command", "rete_ul");
      ("rete_ul", "raven_matrix"); ("raven_matrix", "stpa");
      ("stpa", "fmea"); ("fmea", "ruliad"); ("ruliad", "stan");
      ("stan", "z3"); ("z3", "assurance");
      ("assurance", "swarm_bridge"); ("swarm_bridge", "swarm");
      ("swarm", "run"); ("run", "event"); ("event", "store") ] in
  let* () = if List.for_all (fun (source, target) -> has_edge source target) required_chain
    then Ok () else Error "atlas admission chain is incomplete" in
  let swarm_predecessors =
    edges |> List.filter (fun edge -> String.equal edge.target "swarm")
    |> List.map (fun edge -> edge.source) in
  let* () = if swarm_predecessors = [ "swarm_bridge" ] then Ok ()
    else Error "Swarm has a gate-bypass predecessor" in
  let bridge_predecessors =
    edges |> List.filter (fun edge -> String.equal edge.target "swarm_bridge")
    |> List.map (fun edge -> edge.source) in
  let* () = if bridge_predecessors = [ "assurance" ] then Ok ()
    else Error "Run_swarm_bridge has an assurance-bypass predecessor" in
  let* () =
    if not (can_reach "webgl" "completion_criterion")
       && not (can_reach "table" "completion_criterion")
       && not (can_reach "projection_receipt" "completion_receipt") then Ok ()
    else Error "visualization or projection can reach completion admission" in
  let* () =
    if List.for_all (fun component -> paths_to_criterion component <> [])
        Run_ontology.components then Ok ()
    else Error "an ontology component has no bounded path to a criterion" in
  let* () = Run_metrics.validate_declarations Run_metrics.all in
  let channels = List.map (fun declaration -> declaration.Run_metrics.fpp_channel)
      Run_metrics.all in
  unique "metric-to-FPP channels" channels
