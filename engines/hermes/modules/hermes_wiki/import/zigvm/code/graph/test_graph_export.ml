module Graph = Zigvm_harness_support.Graph_intelligence
module P = Zigvm_harness_support.Graph_processing
module R = Zigvm_harness_support.Graph_revision
module A = Zigvm_harness_support.Graph_analytics
module E = Zigvm_harness_support.Graph_export
module Db = Zigvm_harness_support.Db
module Mcp = Zigvm_harness_support.Mcp_server

let require condition message = if not condition then failwith message

let node id =
  Graph.{ id; label = id; kind = "concept"; layer = "text"; group = "fixture"; detail = id; weight = 1. }

let graph =
  Graph.
    {
      id = "export";
      title = "Export fixture";
      kind = "text";
      nodes = [ node "alpha"; node "beta" ];
      edges = [ { source = "alpha"; target = "beta"; relation = "coOccurs"; weight = 2. } ];
    }

let statements =
  [
    P.statement ~id:"s1" ~source_id:"src" ~ordinal:0
      ~metadata:[ ("sentiment", "positive"); ("topic", "fixture") ]
      "alpha, beta";
  ]

let () =
  let revision = R.of_graph ~statement_ids:[ "s1" ] ~project_id:"p" ~revision:4 graph in
  let analytics = A.analyze ~filter_digest:"visible-4" revision statements in
  let packet = E.packet ~revision ~statements ~analytics in
  require (E.exported_node_ids packet = R.node_ids revision)
    "every graph export observes the visible revision";
  require (E.statement_ids packet = [ "s1" ]) "statement export preserves source identity";
  require (String.starts_with ~prefix:"statement_id,source_id" (E.statements_csv packet))
    "statement CSV has a typed header";
  require (String.contains (E.statements_markdown packet) '#')
    "statement Markdown is a readable document";
  require (String.contains (E.analytics_csv packet) ',')
    "analytics CSV exposes revision-labelled metrics";
  require (String.contains (E.analytics_text packet) ':')
    "analytics text is revision labelled";
  require (String.contains (E.gexf packet) '<') "GEXF is serialized";
  require (String.contains (E.graphml packet) '<') "GraphML is serialized";
  require (String.contains (E.dot packet) '{') "DOT is serialized";
  require
    (match E.decode_source_backup (E.source_json packet) with
    | Ok (decoded_revision, decoded_statements) ->
        decoded_revision.graph = revision.graph && decoded_statements = statements
    | Error _ -> false)
    "source backup round-trips graph and attributed statements";
  List.iter
    (fun format ->
      let mime, body = E.render format packet in
      require (mime <> "" && body <> "") (E.format_name format ^ " renders a non-empty typed body"))
    E.formats;
  let db_path = Filename.temp_file "graph-mcp" ".sqlite3" in
  let db = Db.open_ ~path:db_path in
  Fun.protect
    ~finally:(fun () ->
      Db.close db;
      List.iter (fun path -> if Sys.file_exists path then Sys.remove path)
        [ db_path; db_path ^ "-wal"; db_path ^ "-shm" ])
    (fun () ->
      let tools = Mcp.db_tools db ~observe:(fun () -> "{}") in
      let tool name = List.find (fun (tool : Mcp.tool) -> tool.name = name) tools in
      require
        (match (tool "graph_analyze_text").run (`Assoc [ ("text", `String "alpha beta graph evidence") ]) with
        | Ok body -> String.contains body 'r'
        | Error _ -> false)
        "MCP text analysis shares the deterministic graph authority";
      require
        (match
           (tool "graph_export_text").run
             (`Assoc [ ("text", `String "alpha beta graph evidence");
                       ("format", `String "source-json") ])
         with
        | Ok body -> String.length body > 100
        | Error _ -> false)
        "MCP export shares the local export authority";
      require
        (match
           (tool "graph_acquire_text").run
             (`Assoc [ ("kind", `String "spreadsheet");
                       ("content_type", `String "text/csv");
                       ("content", `String "text,kind\ngraph evidence,survey") ])
         with
        | Ok body -> String.length body > 100
        | Error _ -> false)
        "MCP acquisition shares the provenance authority";
      require
        (match
           (tool "graph_intelligence_text").run
             (`Assoc [ ("text", `String "alpha beta graph evidence");
                       ("query", `String "graph evidence") ])
         with
        | Ok body -> String.contains body 'c'
        | Error _ -> false)
        "MCP intelligence shares the cited retrieval authority");
  print_endline "graph export laws: pass (seed=5705, deterministic)"
