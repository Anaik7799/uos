type flow = Contains | Observes | Admits | Prepares | Produces | Retains | Reports
type verification = Structural_check

type part = {
  id : string;
  kind : Jj_ontology.kind;
  coordinate : Jj_ontology.coordinate;
  owner : Jj_ontology.owner;
  identity : Jj_ontology.identity;
  lifecycle : Jj_ontology.lifecycle;
}

type connection = { source : string; target : string; flow : flow }

type requirement = {
  id : string;
  subject : string;
  invariant : Jj_ontology.invariant;
  verification : verification;
}

type operation_allocation = {
  operation : Jj_operation.t;
  operation_key : string;
  operation_digest : string;
  intent_part : string;
  effect_part : string;
  lifecycle : Jj_ontology.lifecycle;
}

type model = {
  schema_id : string;
  ontology_digest : string;
  operation_authority_digest : string;
  parts : part list;
  connections : connection list;
  requirements : requirement list;
  operation_allocations : operation_allocation list;
}

let schema_id = "hermes.jj-sysml-projection.v1"

let flow_key = function
  | Contains -> "contains" | Observes -> "observes" | Admits -> "admits"
  | Prepares -> "prepares" | Produces -> "produces" | Retains -> "retains"
  | Reports -> "reports"

let part_of_node (node : Jj_ontology.node) =
  { id = node.coordinate.node; kind = node.kind; coordinate = node.coordinate;
    owner = node.owner; identity = node.identity; lifecycle = node.lifecycle }

let connection source flow target = { source; target; flow }

let connections =
  [ connection "jj.portfolio" Contains "jj.repository-workspace";
    connection "jj.repository-workspace" Observes "jj.policy-coordinator";
    connection "jj.policy-coordinator" Admits "jj.intent-operation";
    connection "jj.intent-operation" Prepares "jj.effect-attempt";
    connection "jj.effect-attempt" Produces "jj.readback-evidence";
    connection "jj.readback-evidence" Retains "jj.durable-receipt";
    connection "jj.durable-receipt" Reports "jj.telemetry" ]

let requirements =
  List.concat_map
    (fun (node : Jj_ontology.node) ->
       List.map
         (fun invariant ->
            { id = node.coordinate.node ^ ".requirement."
                   ^ Jj_ontology.invariant_key invariant;
              subject = node.coordinate.node; invariant;
              verification = Structural_check })
         node.invariants)
    Jj_ontology.all

let allocation operation =
  let declaration = Jj_operation.declaration operation in
  { operation; operation_key = declaration.key;
    operation_digest = Jj_operation.digest_of [ operation ];
    intent_part = "jj.intent-operation"; effect_part = "jj.effect-attempt";
    lifecycle = Jj_ontology.Implemented_unavailable }

let model =
  { schema_id; ontology_digest = Jj_ontology.source_digest;
    operation_authority_digest = Jj_operation.source_digest;
    parts = List.map part_of_node Jj_ontology.all; connections; requirements;
    operation_allocations = List.map allocation Jj_operation.all }

let requirement_count model = List.length model.requirements
let operation_count model = List.length model.operation_allocations

let connection_endpoints_exist model =
  let ids = List.map (fun (part : part) -> part.id) model.parts in
  List.for_all
    (fun (edge : connection) ->
       List.mem edge.source ids && List.mem edge.target ids)
    model.connections

let operation_denominator_is_exact model =
  List.map
    (fun (allocation : operation_allocation) -> allocation.operation)
    model.operation_allocations
  = Jj_operation.all
  && List.for_all
       (fun (allocation : operation_allocation) ->
          allocation.operation_key
          = (Jj_operation.declaration allocation.operation).key
          && allocation.operation_digest
             = Jj_operation.digest_of [ allocation.operation ])
       model.operation_allocations

let canonical_part (part : part) =
  Jj_id.length_frame
    [ part.id; Jj_ontology.kind_key part.kind;
      Jj_ontology.level_key part.coordinate.level; part.coordinate.node;
      Jj_ontology.owner_key part.owner; part.identity.schema_id;
      part.identity.authority_digest;
      Jj_ontology.lifecycle_key part.lifecycle ]

let canonical_connection (edge : connection) =
  Jj_id.length_frame [ edge.source; flow_key edge.flow; edge.target ]

let canonical_requirement (requirement : requirement) =
  Jj_id.length_frame
    [ requirement.id; requirement.subject;
      Jj_ontology.invariant_key requirement.invariant; "structural-check" ]

let canonical_allocation (allocation : operation_allocation) =
  Jj_id.length_frame
    [ allocation.operation_key; allocation.operation_digest;
      allocation.intent_part; allocation.effect_part;
      Jj_ontology.lifecycle_key allocation.lifecycle ]

let digest model extra =
  (schema_id :: model.ontology_digest :: model.operation_authority_digest
   :: extra
   @ List.map canonical_part model.parts
   @ List.map canonical_connection model.connections
   @ List.map canonical_requirement model.requirements
   @ List.map canonical_allocation model.operation_allocations)
  |> Jj_id.length_frame |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let source_digest = digest model []

module For_test = struct
  type mutation = Drop_part | Reverse_connection | Drop_requirement | Change_operation

  let source_digest_with_mutation = function
    | Drop_part -> digest { model with parts = List.tl model.parts } []
    | Reverse_connection ->
        let first = List.hd model.connections in
        let reversed = { first with source = first.target; target = first.source } in
        digest { model with connections = reversed :: List.tl model.connections } []
    | Drop_requirement ->
        digest { model with requirements = List.tl model.requirements } []
    | Change_operation ->
        let first = List.hd model.operation_allocations in
        let second = List.hd (List.tl model.operation_allocations) in
        let changed =
          { first with operation_key = second.operation_key;
            operation_digest = second.operation_digest } in
        digest
          { model with
            operation_allocations =
              changed :: List.tl model.operation_allocations }
          []
end
