module Graph = Zigvm_harness_support.Graph_intelligence
module P = Zigvm_harness_support.Graph_processing
module R = Zigvm_harness_support.Graph_revision
module A = Zigvm_harness_support.Graph_analytics

let require condition message = if not condition then failwith message
let close left right = Float.abs (left -. right) < 1e-9

let node id group =
  Graph.{ id; label = id; kind = "concept"; layer = "text"; group; detail = id; weight = 1. }

let edge source target = Graph.{ source; target; relation = "coOccurs"; weight = 1. }

let graph =
  Graph.
    {
      id = "analytics-fixture";
      title = "Analytics fixture";
      kind = "text";
      nodes =
        [ node "left-a" "left"; node "left-b" "left"; node "bridge" "gateway";
          node "right-a" "right"; node "right-b" "right" ];
      edges =
        [ edge "left-a" "left-b"; edge "left-b" "bridge"; edge "bridge" "right-a";
          edge "right-a" "right-b" ];
    }

let statements =
  [
    P.statement ~id:"s-left" ~source_id:"src" ~ordinal:0
      ~metadata:[ ("sentiment", "positive") ] "left-a left-b robust success";
    P.statement ~id:"s-bridge" ~source_id:"src" ~ordinal:1
      ~metadata:[ ("sentiment", "neutral") ] "left-b bridge right-a evidence";
    P.statement ~id:"s-right" ~source_id:"src" ~ordinal:2
      ~metadata:[ ("sentiment", "negative") ] "right-a right-b unsafe failure";
  ]

let () =
  let revision =
    R.of_graph ~statement_ids:[ "s-left"; "s-bridge"; "s-right" ]
      ~project_id:"p" ~revision:7 graph
  in
  let report = A.analyze ~filter_digest:"all" revision statements in
  require (report.revision = 7 && report.filter_digest = "all")
    "analytics disclose revision and filter authority";
  require (List.length report.excerpts = 3) "source excerpts retain every statement";
  require
    (List.exists
       (fun (excerpt : A.excerpt) ->
         excerpt.statement_id = "s-bridge" && List.mem "bridge" excerpt.node_ids)
       report.excerpts)
    "source excerpts link concepts to statements";
  require (List.length report.topics >= 2) "topic observations retain declared groups";
  require
    (close
       (List.fold_left (fun sum (topic : A.topic) -> sum +. topic.influence) 0. report.topics)
       1.)
    "topic influence is normalized";
  require
    ((List.hd report.influential_concepts).node_id = "bridge")
    "the path bridge is the leading influential concept";
  require
    (List.exists (fun (gateway : A.gateway) -> gateway.node_id = "bridge") report.gateways)
    "conceptual gateways expose the path bridge";
  require (List.length report.relations = 4) "relations preserve weighted graph edges";
  require
    (report.sentiment.positive = 1 && report.sentiment.negative = 1
     && report.sentiment.neutral = 1 && report.sentiment.total = 3)
    "sentiment partitions every statement";
  require
    (report.stats.nodes = 5 && report.stats.edges = 4 && report.stats.words > 0)
    "text and network statistics share one report";
  require (report.structure.components = 1) "structure reports graph connectivity";
  require (List.length report.trends = 3) "trends retain ordinal progression";
  require
    (List.length report.propagation.values = 3)
    "propagation aligns one value to each ordered statement";
  require
    (List.fold_left (fun sum (bucket : A.bucket) -> sum + bucket.count) 0 report.degree_distribution = 5)
    "degree distribution partitions every node";
  require
    (List.for_all (fun (topic : A.topic) -> String.starts_with ~prefix:"lda:" topic.id) report.lda_comparison)
    "probabilistic comparison is separately labeled";
  require (A.analyze ~filter_digest:"all" revision statements = report)
    "analytics are deterministic";
  require
    (A.to_yojson report = A.to_yojson (A.analyze ~filter_digest:"all" revision statements))
    "serialized analytics are byte-stable values";
  print_endline "graph analytics laws: pass (seed=5514, deterministic)"
