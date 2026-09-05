let node_kind_name = function
  | Ops_governance_model.Declaration -> "Declaration"
  | Command -> "Command"
  | Surface -> "Surface"
  | Activity -> "Activity"
  | Receipt -> "Receipt"
  | Criterion -> "Criterion"
  | Metric -> "Metric"
  | Model -> "Model"

let relation_name = function
  | Ops_governance_model.Declares -> "declares"
  | Projects -> "projects"
  | Executes -> "executes"
  | Produces -> "produces"
  | Satisfies -> "satisfies"
  | Measures -> "measures"
  | Models -> "models"

let sanitize value =
  let mapped =
    String.map
      (fun character ->
        match character with
        | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> character
        | _ -> '_')
      value
  in
  "OGM_" ^ mapped

let escape value =
  let buffer = Buffer.create (String.length value + 8) in
  String.iter
    (function
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> ()
      | character -> Buffer.add_char buffer character)
    value;
  Buffer.contents buffer

let sysml_v2 () =
  let buffer = Buffer.create 65536 in
  let add fmt = Printf.ksprintf (Buffer.add_string buffer) fmt in
  add "// GENERATED from Ops_governance_model; do not edit.\n";
  add "package HermesExecutableGovernance {\n";
  add "  requirement def GovernanceCriterion { attribute sourceId : String; }\n";
  List.iter
    (fun (node : Ops_governance_model.node) ->
      let identifier = sanitize node.node_id in
      add "  part def %s {\n" identifier;
      add "    attribute sourceId : String = \"%s\";\n" (escape node.node_id);
      add "    attribute obligationId : String = \"%s\";\n" (escape node.obligation_id);
      add "    attribute ontologyKind : String = \"%s\";\n" (node_kind_name node.kind);
      if node.kind = Ops_governance_model.Criterion then
        add "    requirement criterion : GovernanceCriterion { attribute sourceId = \"%s\"; }\n"
          (escape node.node_id);
      add "  }\n")
    Ops_governance_model.nodes;
  List.iteri
    (fun index (edge : Ops_governance_model.edge) ->
      add "  dependency edge_%04d_%s from %s to %s; // %s -> %s\n"
        index (relation_name edge.relation) (sanitize edge.source)
        (sanitize edge.target) (escape edge.source) (escape edge.target))
    Ops_governance_model.edges;
  add "}\n";
  Buffer.contents buffer

let oml_owl () =
  let buffer = Buffer.create 65536 in
  let add fmt = Printf.ksprintf (Buffer.add_string buffer) fmt in
  add "# GENERATED from Ops_governance_model; do not edit.\n";
  add "@prefix hermes: <https://hermes.local/governance#> .\n";
  add "@prefix owl: <http://www.w3.org/2002/07/owl#> .\n";
  add "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .\n";
  add "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .\n\n";
  add "hermes:ExecutableGovernance a owl:Ontology .\n";
  List.iter
    (fun kind -> add "hermes:%s a owl:Class ; rdfs:subClassOf hermes:GovernanceNode .\n" kind)
    [ "Declaration"; "Command"; "Surface"; "Activity"; "Receipt";
      "Criterion"; "Metric"; "Model" ];
  List.iter
    (fun relation -> add "hermes:%s a owl:ObjectProperty .\n" relation)
    [ "declares"; "projects"; "executes"; "produces"; "satisfies";
      "measures"; "models" ];
  List.iter
    (fun (node : Ops_governance_model.node) ->
      add "hermes:%s a hermes:%s ; rdfs:label \"%s\" ; hermes:obligationId \"%s\" .\n"
        (sanitize node.node_id) (node_kind_name node.kind) (escape node.node_id)
        (escape node.obligation_id))
    Ops_governance_model.nodes;
  List.iter
    (fun (edge : Ops_governance_model.edge) ->
      add "hermes:%s hermes:%s hermes:%s . # %s -> %s\n"
        (sanitize edge.source) (relation_name edge.relation) (sanitize edge.target)
        (escape edge.source) (escape edge.target))
    Ops_governance_model.edges;
  Buffer.contents buffer

let openmbee_mms () =
  let elements =
    List.map
      (fun (node : Ops_governance_model.node) ->
        `Assoc
          [ ("id", `String (sanitize node.node_id));
            ("sourceId", `String node.node_id);
            ("name", `String node.node_id);
            ("type", `String (node_kind_name node.kind));
            ("ownerId", `String node.obligation_id);
            ("authority", `String "Ops_governance_model.nodes") ])
      Ops_governance_model.nodes
  in
  let relationships =
    List.mapi
      (fun index (edge : Ops_governance_model.edge) ->
        `Assoc
          [ ("id", `String (Printf.sprintf "OGM_EDGE_%04d" index));
            ("type", `String (relation_name edge.relation));
            ("sourceId", `String (sanitize edge.source));
            ("targetId", `String (sanitize edge.target));
            ("sourceAuthorityId", `String edge.source);
            ("targetAuthorityId", `String edge.target) ])
      Ops_governance_model.edges
  in
  `Assoc
    [ ("schema", `String "openmbee-mms-element-projection/v1");
      ("authority", `String "Ops_governance_model");
      ("publication", `String "local-projection-only");
      ("elements", `List elements);
      ("relationships", `List relationships) ]
  |> Yojson.Safe.pretty_to_string

let contains text needle =
  let length = String.length text and width = String.length needle in
  let rec loop index =
    index + width <= length
    && (String.sub text index width = needle || loop (index + 1))
  in
  width > 0 && loop 0

let validate () =
  let errors = ref (Ops_governance_model.validate ()) in
  let add message = errors := message :: !errors in
  let sysml = sysml_v2 () and oml = oml_owl () and mms = openmbee_mms () in
  let ids = List.map (fun (node : Ops_governance_model.node) -> node.node_id)
      Ops_governance_model.nodes in
  let projected_ids = List.map sanitize ids in
  if List.length projected_ids <> List.length (List.sort_uniq compare projected_ids) then
    add "sanitized MBSE identifiers collide";
  List.iter
    (fun id ->
      if not (contains sysml id) then add ("SysML misses " ^ id);
      if not (contains oml id) then add ("OML/OWL misses " ^ id);
      if not (contains mms id) then add ("OpenMBEE MMS misses " ^ id))
    ids;
  begin match Yojson.Safe.from_string mms with
  | exception Yojson.Json_error message -> add ("OpenMBEE MMS JSON invalid: " ^ message)
  | json ->
      begin match Yojson.Safe.Util.member "elements" json,
                  Yojson.Safe.Util.member "relationships" json with
      | `List elements, `List relationships ->
          if List.length elements <> List.length Ops_governance_model.nodes then
            add "OpenMBEE element denominator differs";
          if List.length relationships <> List.length Ops_governance_model.edges then
            add "OpenMBEE relationship denominator differs"
      | _ -> add "OpenMBEE projection lacks element or relationship arrays"
      end
  end;
  List.rev !errors
