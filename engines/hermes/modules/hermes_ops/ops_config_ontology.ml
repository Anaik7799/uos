type node_kind = Registry | Supply | Element | Consumer | Source_observation
  | Validation | Configuration_digest | Execution_intent | Assurance
  | Execution_bridge | Scheduler | Receipt

type authority = Declaration | Observation | Derived_identity | Admission
  | Execution | Scheduling | Evidence

type node = {
  id : string;
  label : string;
  kind : node_kind;
  layer : Ops_config.layer option;
  authority : authority;
  purpose : string;
}

let registry_id = "ops-config-registry"
let observation_id = "source-observation"
let validation_id = "configuration-validation"
let configuration_digest_id = "configuration-digest"
let execution_intent_id = "typed-execution-intent"
let assurance_id = "exact-head-assurance"
let execution_bridge_id = "run-swarm-bridge"
let scheduler_id = "swarm-engine"
let receipt_id = "execution-receipt"

let schema_id = Ops_config.schema_id
let declaration_digest = Ops_config.declaration_digest

let element_id key = "config:" ^ key
let consumer_id path = "consumer:" ^ path

let supply_id = function
  | Ops_config.Environment -> "supply:environment"
  | Toolchain -> "supply:toolchain"
  | Derived -> "supply:derived"

let kind_name = function
  | Registry -> "registry"
  | Supply -> "supply"
  | Element -> "configuration element"
  | Consumer -> "consumer"
  | Source_observation -> "source observation"
  | Validation -> "validation"
  | Configuration_digest -> "configuration digest"
  | Execution_intent -> "execution intent"
  | Assurance -> "assurance"
  | Execution_bridge -> "execution bridge"
  | Scheduler -> "scheduler"
  | Receipt -> "receipt"

let authority_name = function
  | Declaration -> "declaration"
  | Observation -> "observation"
  | Derived_identity -> "derived identity"
  | Admission -> "admission"
  | Execution -> "execution"
  | Scheduling -> "scheduling"
  | Evidence -> "evidence"

let node ?layer id label kind authority purpose =
  { id; label; kind; layer; authority; purpose }

let supply_node supply =
  let label, purpose =
    match supply with
    | Ops_config.Environment ->
        ("Environment supply", "Operator or process environment supplies the declared element")
    | Toolchain ->
        ("Toolchain supply", "The verified OCaml toolchain supplies the declared element")
    | Derived ->
        ("Derived supply", "The system deterministically derives the declared element")
  in
  node (supply_id supply) label Supply Declaration purpose

let element_node (element : Ops_config.element) =
  node ~layer:element.layer (element_id element.key) element.key Element Declaration
    element.purpose

let consumer_node path =
  node (consumer_id path) path Consumer Declaration
    "Declared source boundary that consumes one or more configuration elements"

let core =
  [ node registry_id "Ops_config.elements" Registry Declaration
      "Single declarative configuration authority";
    node observation_id "Source observation" Source_observation Observation
      "Whole-module-tree observation of configuration reads";
    node validation_id "Configuration validation" Validation Admission
      "Fail-closed comparison of declarations, observed reads, and projections";
    node configuration_digest_id "Configuration digest" Configuration_digest
      Derived_identity "Deterministic value-free identity of the declaration set";
    node execution_intent_id "Typed execution intent" Execution_intent Admission
      "Closed operational intent bound to the exact configuration digest";
    node assurance_id "Exact-head assurance" Assurance Admission
      "Current-head safety and formal admission bundle";
    node execution_bridge_id "Run_swarm_bridge" Execution_bridge Execution
      "Sole admitted execution boundary";
    node scheduler_id "Swarm engine" Scheduler Scheduling
      "Non-creditable OCaml Domain-wave scheduler";
    node receipt_id "Execution receipt" Receipt Evidence
      "Typed durable result reconstructed from authoritative readback" ]

let all =
  let supplies =
    Ops_config.elements
    |> List.map (fun (element : Ops_config.element) -> element.supply)
    |> List.sort_uniq compare
    |> List.map supply_node
  in
  let elements = List.map element_node Ops_config.elements in
  let consumers =
    Ops_config.elements
    |> List.map (fun (element : Ops_config.element) -> element.consumer)
    |> List.sort_uniq String.compare
    |> List.map consumer_node
  in
  core @ supplies @ elements @ consumers

let find id = List.find_opt (fun node -> String.equal node.id id) all

let ( let* ) value continuation =
  match value with Ok result -> continuation result | Error _ as error -> error

let unique label values =
  if List.length values = List.length (List.sort_uniq String.compare values)
  then Ok ()
  else Error (label ^ " must be unique")

let validate_nodes nodes =
  let* () = if nodes = [] then Error "configuration ontology is empty" else Ok () in
  let* () = unique "configuration ontology node ids" (List.map (fun node -> node.id) nodes) in
  let* () =
    if List.for_all
        (fun node ->
          String.trim node.id <> "" && String.trim node.label <> ""
          && String.trim node.purpose <> "")
        nodes
    then Ok () else Error "configuration ontology contains a vacuous node"
  in
  let* () =
    if List.for_all
        (fun node ->
          match node.kind, node.layer with
          | Element, Some _ -> true
          | Element, None -> false
          | _, None -> true
          | _, Some _ -> false)
        nodes
    then Ok () else Error "only configuration elements may carry a fractal layer"
  in
  let element_nodes = List.filter (fun node -> node.kind = Element) nodes in
  let* () =
    if List.length element_nodes = List.length Ops_config.elements
       && List.for_all
            (fun (element : Ops_config.element) ->
              List.exists
                (fun node ->
                  String.equal node.id (element_id element.key)
                  && node.layer = Some element.layer
                  && node.authority = Declaration)
                element_nodes)
            Ops_config.elements
    then Ok () else Error "ontology is not a total projection of Ops_config.elements"
  in
  let required =
    [ registry_id; observation_id; validation_id; configuration_digest_id;
      execution_intent_id; assurance_id; execution_bridge_id; scheduler_id;
      receipt_id ]
  in
  let* () =
    if List.for_all (fun id -> List.exists (fun node -> String.equal node.id id) nodes) required
    then Ok () else Error "configuration ontology lacks a required control node"
  in
  match
    ( List.find_opt (fun node -> String.equal node.id execution_bridge_id) nodes,
      List.find_opt (fun node -> String.equal node.id scheduler_id) nodes,
      List.find_opt (fun node -> String.equal node.id receipt_id) nodes )
  with
  | Some bridge, Some scheduler, Some receipt
    when bridge.authority = Execution && scheduler.authority = Scheduling
         && receipt.authority = Evidence -> Ok ()
  | _ -> Error "execution, scheduling, and evidence authorities are conflated"

let validate () = validate_nodes all
