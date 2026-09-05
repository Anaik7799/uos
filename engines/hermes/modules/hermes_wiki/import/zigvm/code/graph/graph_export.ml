(** Deterministic export interpretations.

    A packet closes over one visible revision, its attributed statements, and
    an analytics report for the same revision/filter. All renderers observe
    that packet only; source backup is admitted by an explicit round trip. *)

module Graph = Graph_intelligence
module Revision = Graph_revision
module Processing = Graph_processing
module Analytics = Graph_analytics

type format =
  | Statements_csv
  | Statements_markdown
  | Analytics_text
  | Analytics_csv
  | Json
  | Graph_csv
  | Gexf
  | Dot
  | Graphml
  | Source_json

type packet = {
  revision : Revision.t;
  statements : Processing.statement list;
  analytics : Analytics.report;
}

let formats =
  [ Statements_csv; Statements_markdown; Analytics_text; Analytics_csv; Json;
    Graph_csv; Gexf; Dot; Graphml; Source_json ]

let format_name = function
  | Statements_csv -> "statements-csv"
  | Statements_markdown -> "statements-markdown"
  | Analytics_text -> "analytics-text"
  | Analytics_csv -> "analytics-csv"
  | Json -> "json"
  | Graph_csv -> "graph-csv"
  | Gexf -> "gexf"
  | Dot -> "dot"
  | Graphml -> "graphml"
  | Source_json -> "source-json"

let packet ~(revision : Revision.t) ~statements ~(analytics : Analytics.report) =
  if analytics.Analytics.revision <> revision.Revision.revision then
    invalid_arg "analytics revision does not match export revision"
  else { revision; statements; analytics }

let exported_node_ids packet = Revision.node_ids packet.revision

let statement_ids packet =
  packet.statements |> List.map (fun (statement : Processing.statement) -> statement.id)

let csv value =
  let escaped = String.concat "\"\"" (String.split_on_char '"' value) in
  if String.exists (function ',' | '"' | '\n' | '\r' -> true | _ -> false) value
  then "\"" ^ escaped ^ "\""
  else escaped

let metadata_text metadata =
  metadata |> List.map (fun (key, value) -> key ^ "=" ^ value) |> String.concat ";"

let statements_csv packet =
  "statement_id,source_id,ordinal,text,metadata\n"
  ^ String.concat ""
      (List.map
         (fun (statement : Processing.statement) ->
           Printf.sprintf "%s,%s,%d,%s,%s\n" (csv statement.id) (csv statement.source_id)
             statement.ordinal (csv statement.text) (csv (metadata_text statement.metadata)))
         packet.statements)

let statements_markdown packet =
  Printf.sprintf "# Statements — revision %d\n\n%s"
    packet.revision.revision
    (String.concat ""
       (List.map
          (fun (statement : Processing.statement) ->
            Printf.sprintf "## %s · ordinal %d\n\n%s\n\nMetadata: %s\n\n"
              statement.id statement.ordinal statement.text
              (match metadata_text statement.metadata with "" -> "none" | value -> value))
          packet.statements))

let analytics_rows packet =
  let report = packet.analytics in
  [
    ("revision", string_of_int report.revision);
    ("filter_digest", report.filter_digest);
    ("nodes", string_of_int report.stats.nodes);
    ("edges", string_of_int report.stats.edges);
    ("words", string_of_int report.stats.words);
    ("unique_lemmas", string_of_int report.stats.unique_lemmas);
    ("components", string_of_int report.structure.components);
    ("density", Printf.sprintf "%.12g" report.structure.density);
    ("modularity", Printf.sprintf "%.12g" report.structure.modularity);
    ("positive", string_of_int report.sentiment.positive);
    ("negative", string_of_int report.sentiment.negative);
    ("neutral", string_of_int report.sentiment.neutral);
  ]

let analytics_text packet =
  analytics_rows packet |> List.map (fun (key, value) -> key ^ ": " ^ value ^ "\n")
  |> String.concat ""

let analytics_csv packet =
  "metric,value\n"
  ^ (analytics_rows packet
    |> List.map (fun (key, value) -> csv key ^ "," ^ csv value ^ "\n")
    |> String.concat "")

let json packet =
  `Assoc
    [
      ("project_id", `String packet.revision.project_id);
      ("revision", `Int packet.revision.revision);
      ("filter_digest", `String packet.analytics.filter_digest);
      ("graph", Graph.to_yojson packet.revision.graph);
      ("analytics", Analytics.to_yojson packet.analytics);
    ]
  |> Yojson.Safe.pretty_to_string

let graph_csv packet =
  let node_rows =
    packet.revision.graph.nodes
    |> List.map (fun (node : Graph.node) ->
           Printf.sprintf "node,%s,%s,%s,,,%s\n" (csv node.id) (csv node.label)
             (csv node.kind) (Printf.sprintf "%.12g" node.weight))
  in
  let edge_rows =
    packet.revision.graph.edges
    |> List.map (fun (edge : Graph.edge) ->
           Printf.sprintf "edge,,,,%s,%s,%s,%s\n" (csv edge.source) (csv edge.target)
             (csv edge.relation) (Printf.sprintf "%.12g" edge.weight))
  in
  "record,id,label,kind,source,target,relation,weight\n"
  ^ String.concat "" (node_rows @ edge_rows)

let xml value =
  value |> String.to_seq
  |> Seq.map (function
       | '&' -> "&amp;" | '<' -> "&lt;" | '>' -> "&gt;" | '"' -> "&quot;" | '\'' -> "&apos;"
       | character -> String.make 1 character)
  |> List.of_seq |> String.concat ""

let gexf packet =
  let nodes =
    packet.revision.graph.nodes
    |> List.map (fun (node : Graph.node) ->
           Printf.sprintf "<node id=\"%s\" label=\"%s\" />" (xml node.id) (xml node.label))
    |> String.concat ""
  in
  let edges =
    packet.revision.graph.edges
    |> List.mapi (fun index (edge : Graph.edge) ->
           Printf.sprintf
             "<edge id=\"e%d\" source=\"%s\" target=\"%s\" label=\"%s\" weight=\"%.12g\" />"
             index (xml edge.source) (xml edge.target) (xml edge.relation) edge.weight)
    |> String.concat ""
  in
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gexf version=\"1.3\"><graph mode=\"static\" defaultedgetype=\"undirected\"><nodes>"
  ^ nodes ^ "</nodes><edges>" ^ edges ^ "</edges></graph></gexf>"

let dot packet = Graph.to_dot packet.revision.graph
let graphml packet = Graph.to_graphml packet.revision.graph

let statement_json (statement : Processing.statement) =
  `Assoc
    [
      ("id", `String statement.id);
      ("source_id", `String statement.source_id);
      ("ordinal", `Int statement.ordinal);
      ("text", `String statement.text);
      ("metadata", `Assoc (List.map (fun (key, value) -> (key, `String value)) statement.metadata));
    ]

let source_json packet =
  `Assoc
    [
      ("schema", `String "zigvm.infranodus.source-backup.v1");
      ("project_id", `String packet.revision.project_id);
      ("revision", `Int packet.revision.revision);
      ("graph", Graph.to_yojson packet.revision.graph);
      ("statements", `List (List.map statement_json packet.statements));
    ]
  |> Yojson.Safe.pretty_to_string

let decode_source_backup value =
  let open Yojson.Safe.Util in
  try
    let document = Yojson.Safe.from_string value in
    if document |> member "schema" |> to_string <> "zigvm.infranodus.source-backup.v1" then
      Error "unknown source backup schema"
    else
      match Graph.of_yojson (document |> member "graph") with
      | Error message -> Error message
      | Ok graph ->
          let project_id = document |> member "project_id" |> to_string in
          let revision_number = document |> member "revision" |> to_int in
          let statements =
            document |> member "statements" |> to_list
            |> List.map (fun json ->
                   Processing.
                     {
                       id = json |> member "id" |> to_string;
                       source_id = json |> member "source_id" |> to_string;
                       ordinal = json |> member "ordinal" |> to_int;
                       text = json |> member "text" |> to_string;
                       metadata =
                         json |> member "metadata" |> to_assoc
                         |> List.map (fun (key, item) -> (key, to_string item));
                     })
          in
          Ok
            ( Revision.of_graph
                ~statement_ids:
                  (List.map (fun (statement : Processing.statement) -> statement.id) statements)
                ~project_id ~revision:revision_number graph,
              statements )
  with Yojson.Json_error message | Type_error (message, _) -> Error message

let render format packet =
  match format with
  | Statements_csv -> ("text/csv; charset=utf-8", statements_csv packet)
  | Statements_markdown -> ("text/markdown; charset=utf-8", statements_markdown packet)
  | Analytics_text -> ("text/plain; charset=utf-8", analytics_text packet)
  | Analytics_csv -> ("text/csv; charset=utf-8", analytics_csv packet)
  | Json -> ("application/json", json packet)
  | Graph_csv -> ("text/csv; charset=utf-8", graph_csv packet)
  | Gexf -> ("application/gexf+xml", gexf packet)
  | Dot -> ("text/vnd.graphviz; charset=utf-8", dot packet)
  | Graphml -> ("application/graphml+xml", graphml packet)
  | Source_json -> ("application/json", source_json packet)
