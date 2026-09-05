type edge_kind = Declares | Supplies | Consumes | Observes | Validates | Derives
  | Binds | Admits | Executes | Emits

type edge = { source : string; target : string; kind : edge_kind }

let schema_id = Ops_config.schema_id
let declaration_digest = Ops_config.declaration_digest

let kind_name = function
  | Declares -> "declares"
  | Supplies -> "supplies"
  | Consumes -> "consumes"
  | Observes -> "observes"
  | Validates -> "validates"
  | Derives -> "derives"
  | Binds -> "binds"
  | Admits -> "admits"
  | Executes -> "executes"
  | Emits -> "emits"

let edge kind source target = { source; target; kind }

let declaration_edges =
  Ops_config.elements
  |> List.concat_map (fun (element : Ops_config.element) ->
         [ edge Declares Ops_config_ontology.registry_id
             (Ops_config_ontology.element_id element.key);
           edge Supplies (Ops_config_ontology.supply_id element.supply)
             (Ops_config_ontology.element_id element.key);
           edge Consumes (Ops_config_ontology.element_id element.key)
             (Ops_config_ontology.consumer_id element.consumer);
           edge Observes (Ops_config_ontology.consumer_id element.consumer)
             Ops_config_ontology.observation_id ])
  |> List.sort_uniq compare

let control_edges =
  [ edge Validates Ops_config_ontology.registry_id Ops_config_ontology.validation_id;
    edge Validates Ops_config_ontology.observation_id Ops_config_ontology.validation_id;
    edge Derives Ops_config_ontology.validation_id
      Ops_config_ontology.configuration_digest_id;
    edge Binds Ops_config_ontology.configuration_digest_id
      Ops_config_ontology.execution_intent_id;
    edge Admits Ops_config_ontology.execution_intent_id Ops_config_ontology.assurance_id;
    edge Admits Ops_config_ontology.assurance_id
      Ops_config_ontology.execution_bridge_id;
    edge Executes Ops_config_ontology.execution_bridge_id Ops_config_ontology.scheduler_id;
    edge Emits Ops_config_ontology.scheduler_id Ops_config_ontology.receipt_id ]

let edges = declaration_edges @ control_edges

let successors_from declarations node =
  declarations
  |> List.filter (fun item -> String.equal item.source node)
  |> List.map (fun item -> item.target)
  |> List.sort_uniq String.compare

let predecessors node =
  edges
  |> List.filter (fun item -> String.equal item.target node)
  |> List.map (fun item -> item.source)
  |> List.sort_uniq String.compare

module String_set = Set.Make (String)

let can_reach source target =
  let rec visit seen = function
    | [] -> false
    | node :: _ when String.equal node target -> true
    | node :: rest when String_set.mem node seen -> visit seen rest
    | node :: rest ->
        visit (String_set.add node seen) (successors_from edges node @ rest)
  in
  visit String_set.empty [ source ]

let paths_to_receipt source =
  let bound = List.length Ops_config_ontology.all + 1 in
  let rec walk seen reversed depth node =
    if depth > bound || String_set.mem node seen then []
    else
      let reversed = node :: reversed in
      if String.equal node Ops_config_ontology.receipt_id then [ List.rev reversed ]
      else
        successors_from edges node
        |> List.concat_map
             (walk (String_set.add node seen) reversed (depth + 1))
  in
  match Ops_config_ontology.find source with
  | None -> []
  | Some _ -> walk String_set.empty [] 0 source

let ( let* ) value continuation =
  match value with Ok result -> continuation result | Error _ as error -> error

let validate_edges declarations =
  let* () = if declarations = [] then Error "configuration atlas is empty" else Ok () in
  let* () =
    if List.length declarations = List.length (List.sort_uniq compare declarations)
    then Ok () else Error "configuration atlas edges must be unique"
  in
  if List.for_all
      (fun item ->
        not (String.equal item.source item.target)
        && Option.is_some (Ops_config_ontology.find item.source)
        && Option.is_some (Ops_config_ontology.find item.target))
      declarations
  then Ok () else Error "configuration atlas contains a dangling or self edge"

let acyclic declarations =
  let rec visit visiting visited node =
    if String_set.mem node visiting then Error ("configuration atlas cycle reaches " ^ node)
    else if String_set.mem node visited then Ok visited
    else
      let visiting = String_set.add node visiting in
      let rec visit_children visited = function
        | [] -> Ok (String_set.add node visited)
        | child :: rest ->
            let* visited = visit visiting visited child in
            visit_children visited rest
      in
      visit_children visited (successors_from declarations node)
  in
  let rec visit_nodes visited = function
    | [] -> Ok ()
    | node :: rest ->
        let* visited = visit String_set.empty visited node.Ops_config_ontology.id in
        visit_nodes visited rest
  in
  visit_nodes String_set.empty Ops_config_ontology.all

let path_crosses_required_chain path =
  let index value =
    let rec loop offset = function
      | [] -> None
      | item :: _ when String.equal item value -> Some offset
      | _ :: rest -> loop (offset + 1) rest
    in
    loop 0 path
  in
  match
    ( index Ops_config_ontology.configuration_digest_id,
      index Ops_config_ontology.execution_intent_id,
      index Ops_config_ontology.assurance_id,
      index Ops_config_ontology.execution_bridge_id,
      index Ops_config_ontology.scheduler_id,
      index Ops_config_ontology.receipt_id )
  with
  | Some digest, Some intent, Some assurance, Some bridge, Some scheduler, Some receipt ->
      digest < intent && intent < assurance && assurance < bridge
      && bridge < scheduler && scheduler < receipt
  | _ -> false

let validate () =
  let* () = Ops_config_ontology.validate () in
  let* () = validate_edges edges in
  let* () = acyclic edges in
  let* () =
    if predecessors Ops_config_ontology.execution_bridge_id
       = [ Ops_config_ontology.assurance_id ]
    then Ok () else Error "Run_swarm_bridge has an assurance-bypass predecessor"
  in
  let* () =
    if predecessors Ops_config_ontology.scheduler_id
       = [ Ops_config_ontology.execution_bridge_id ]
    then Ok () else Error "the Swarm scheduler has a Run_swarm_bridge bypass"
  in
  if List.for_all
      (fun (element : Ops_config.element) ->
        let paths = paths_to_receipt (Ops_config_ontology.element_id element.key) in
        paths <> [] && List.for_all path_crosses_required_chain paths)
      Ops_config.elements
  then Ok ()
  else Error "a configuration declaration lacks the complete receipt path"
