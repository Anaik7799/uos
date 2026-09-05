module Graph = Zigvm_harness_support.Graph_intelligence
module R = Zigvm_harness_support.Graph_revision
module Domain = Zigvm_harness_support.Workspace_domain

let require condition message = if not condition then failwith message
let ok = function Ok value -> value | Error error -> failwith (R.error_name error)

let node id =
  Graph.{ id; label = id; kind = "concept"; layer = "text"; group = "fixture"; detail = id; weight = 1. }

let edge source target = Graph.{ source; target; relation = "coOccurs"; weight = 1. }

let base_graph =
  Graph.
    {
      id = "fixture";
      title = "Two communities";
      kind = "text";
      nodes = List.map node [ "left-a"; "left-b"; "bridge"; "right-a"; "right-b" ];
      edges =
        [ edge "left-a" "left-b"; edge "left-b" "bridge"; edge "bridge" "right-a";
          edge "right-a" "right-b" ];
    }

let () =
  let base = R.of_graph ~project_id:"p" ~revision:0 base_graph in
  let renamed =
    R.apply base (R.Rename_node { node_id = "bridge"; label = "Conceptual gateway" }) |> ok
  in
  require (renamed.revision = 1) "each semantic edit advances exactly one revision";
  require (R.node_label renamed "bridge" = Some "Conceptual gateway") "rename is observable";
  let merged =
    R.apply renamed
      (R.Merge_nodes
         { source_ids = [ "left-a"; "left-b" ]; target_id = "left"; target_label = "Left topic" })
    |> ok
  in
  require (List.mem "left" (R.node_ids merged)) "merge creates its target";
  require
    (List.for_all (fun edge -> List.mem edge.Graph.source (R.node_ids merged) && List.mem edge.target (R.node_ids merged)) merged.graph.edges)
    "merge preserves referential closure";
  let removed = R.apply merged (R.Remove_nodes [ "bridge" ]) |> ok in
  require
    (List.for_all (fun edge -> edge.Graph.source <> "bridge" && edge.target <> "bridge") removed.graph.edges)
    "node removal cannot leave dangling edges";
  require
    (R.apply base (R.Rename_node { node_id = "missing"; label = "No" }) = Error (R.Missing_node "missing"))
    "edits reject absent targets";
  require
    (R.apply base (R.Rename_node { node_id = "bridge"; label = "  " }) = Error R.Blank_label)
    "edits reject blank labels";
  let visible =
    R.visible base Domain.{ empty_filter with minimum_degree = 2 }
  in
  require (R.visible visible Domain.empty_filter = visible) "visibility is a stable projection";
  require
    (R.compare R.Overlap base base |> R.node_ids = R.node_ids base)
    "self-overlap is identity";
  require
    (R.compare R.Difference_left base base |> R.node_ids = [])
    "self-difference is empty";
  let right = R.apply base (R.Remove_nodes [ "left-a" ]) |> ok in
  require
    (R.compare R.Overlap base right |> R.node_ids = R.node_ids right)
    "overlap excludes nodes absent from either operand";
  let frames = R.timeline [ base; renamed; merged; removed ] in
  require (List.map (fun frame -> frame.R.revision) frames = [ 0; 1; 2; 3 ])
    "timeline preserves revision order";
  print_endline "graph revision laws: pass (seed=5038, deterministic)"
