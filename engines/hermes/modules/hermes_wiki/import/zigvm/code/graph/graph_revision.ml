(** Immutable revision algebra over [Graph_intelligence].

    A revision denotes a referentially closed property graph plus the ordered
    semantic edits that produced it. Constructors normalize the initial graph;
    [apply] rejects edits whose meaning cannot be represented without dangling
    references or identity collisions. *)

module Graph = Graph_intelligence
module Domain = Workspace_domain
module String_set = Set.Make (String)

type edit =
  | Add_node of Graph.node
  | Add_edge of Graph.edge
  | Rename_node of { node_id : string; label : string }
  | Merge_nodes of { source_ids : string list; target_id : string; target_label : string }
  | Remove_nodes of string list
  | Remove_edges of string list

type comparison_mode = Merge | Overlap | Difference_left | Difference_right | Difference_nodes

type t = {
  project_id : string;
  revision : int;
  parent_revision : int option;
  graph : Graph.t;
  edits : edit list;
  statement_ids : string list;
}

type error =
  | Missing_node of string
  | Duplicate_node of string
  | Missing_edge_endpoint of string
  | Duplicate_edge of string
  | Blank_label
  | Empty_merge
  | Merge_target_collision of string

type frame = { revision : int; node_count : int; edge_count : int; statement_ids : string list }

let error_name = function
  | Missing_node id -> "missing_node:" ^ id
  | Duplicate_node id -> "duplicate_node:" ^ id
  | Missing_edge_endpoint id -> "missing_edge_endpoint:" ^ id
  | Duplicate_edge key -> "duplicate_edge:" ^ key
  | Blank_label -> "blank_label"
  | Empty_merge -> "empty_merge"
  | Merge_target_collision id -> "merge_target_collision:" ^ id

let of_graph ?(statement_ids = []) ~project_id ~revision graph =
  {
    project_id;
    revision = Int.max 0 revision;
    parent_revision = None;
    graph = Graph.normalize graph;
    edits = [];
    statement_ids = List.sort_uniq String.compare statement_ids;
  }

let node_ids value =
  value.graph.nodes |> List.map (fun (node : Graph.node) -> node.id)
  |> List.sort_uniq String.compare

let node_label value id =
  value.graph.nodes
  |> List.find_opt (fun (node : Graph.node) -> String.equal node.id id)
  |> Option.map (fun node -> node.Graph.label)

let edge_key (edge : Graph.edge) = edge.source ^ "\x1f" ^ edge.relation ^ "\x1f" ^ edge.target

let advance (value : t) edit graph =
  {
    value with
    revision = value.revision + 1;
    parent_revision = Some value.revision;
    graph = Graph.normalize graph;
    edits = value.edits @ [ edit ];
  }

let apply (value : t) edit =
  let ids = node_ids value |> String_set.of_list in
  let missing candidates =
    List.find_opt (fun id -> not (String_set.mem id ids)) candidates
  in
  match edit with
  | Add_node node ->
      if String.trim node.Graph.id = "" || String.trim node.label = "" then Error Blank_label
      else if String_set.mem node.id ids then Error (Duplicate_node node.id)
      else Ok (advance value edit Graph.{ value.graph with nodes = node :: value.graph.nodes })
  | Add_edge edge ->
      let endpoint =
        if not (String_set.mem edge.Graph.source ids) then Some edge.source
        else if not (String_set.mem edge.target ids) then Some edge.target
        else None
      in
      (match endpoint with
      | Some id -> Error (Missing_edge_endpoint id)
      | None ->
          let key = edge_key edge in
          if List.exists (fun existing -> String.equal (edge_key existing) key) value.graph.edges
          then Error (Duplicate_edge key)
          else Ok (advance value edit Graph.{ value.graph with edges = edge :: value.graph.edges }))
  | Rename_node { node_id; label } ->
      if String.trim label = "" then Error Blank_label
      else if not (String_set.mem node_id ids) then Error (Missing_node node_id)
      else
        let nodes =
          List.map
            (fun (node : Graph.node) ->
              if String.equal node.id node_id then { node with label = String.trim label } else node)
            value.graph.nodes
        in
        Ok (advance value edit Graph.{ value.graph with nodes })
  | Merge_nodes { source_ids; target_id; target_label } ->
      let source_ids = List.sort_uniq String.compare source_ids in
      if source_ids = [] then Error Empty_merge
      else if String.trim target_id = "" || String.trim target_label = "" then Error Blank_label
      else
        (match missing source_ids with
        | Some id -> Error (Missing_node id)
        | None when String_set.mem target_id ids && not (List.mem target_id source_ids) ->
            Error (Merge_target_collision target_id)
        | None ->
            let sources = String_set.of_list source_ids in
            let source_nodes =
              List.filter (fun (node : Graph.node) -> String_set.mem node.id sources) value.graph.nodes
            in
            let template = List.hd source_nodes in
            let target =
              Graph.
                {
                  template with
                  id = target_id;
                  label = String.trim target_label;
                  weight =
                    List.fold_left
                      (fun sum (node : Graph.node) -> sum +. node.weight)
                      0. source_nodes;
                }
            in
            let nodes =
              target
              :: List.filter
                   (fun (node : Graph.node) -> not (String_set.mem node.id sources))
                   value.graph.nodes
            in
            let redirect id = if String_set.mem id sources then target_id else id in
            let edges =
              value.graph.edges
              |> List.map (fun (edge : Graph.edge) ->
                     { edge with source = redirect edge.source; target = redirect edge.target })
            in
            Ok (advance value edit Graph.{ value.graph with nodes; edges }))
  | Remove_nodes removed ->
      let removed = String_set.of_list removed in
      let nodes =
        List.filter (fun (node : Graph.node) -> not (String_set.mem node.id removed)) value.graph.nodes
      in
      let edges =
        List.filter
          (fun (edge : Graph.edge) ->
            not (String_set.mem edge.source removed) && not (String_set.mem edge.target removed))
          value.graph.edges
      in
      Ok (advance value edit Graph.{ value.graph with nodes; edges })
  | Remove_edges removed ->
      let removed = String_set.of_list removed in
      let edges =
        List.filter (fun edge -> not (String_set.mem (edge_key edge) removed)) value.graph.edges
      in
      Ok (advance value edit Graph.{ value.graph with edges })

let visible (value : t) (filter : Domain.filter) =
  if filter = Domain.empty_filter then value
  else
    let query = String.trim filter.query |> String.lowercase_ascii in
    let degrees = Graph.degrees value.graph in
    let keep =
      value.graph.nodes
      |> List.filter (fun (node : Graph.node) ->
             let degree = Option.value ~default:0 (List.assoc_opt node.id degrees) in
             let query_match =
               query = ""
               || String.lowercase_ascii node.label |> fun label ->
                  let qlen = String.length query and llen = String.length label in
                  let rec contains at =
                    at + qlen <= llen
                    && (String.sub label at qlen = query || contains (at + 1))
                  in
                  qlen = 0 || contains 0
             in
             degree >= filter.minimum_degree && query_match)
      |> List.map (fun (node : Graph.node) -> node.id)
      |> String_set.of_list
    in
    let graph =
      Graph.
        {
          value.graph with
          nodes = List.filter (fun (node : node) -> String_set.mem node.id keep) value.graph.nodes;
          edges =
            List.filter
              (fun (edge : edge) -> String_set.mem edge.source keep && String_set.mem edge.target keep)
              value.graph.edges;
        }
    in
    { value with graph = Graph.normalize graph }

let graph_of_nodes_edges template nodes edges =
  Graph.normalize Graph.{ template with nodes; edges }

let compare mode (left : t) (right : t) =
  let left_ids = String_set.of_list (node_ids left) and right_ids = String_set.of_list (node_ids right) in
  let selected =
    match mode with
    | Merge -> String_set.union left_ids right_ids
    | Overlap -> String_set.inter left_ids right_ids
    | Difference_left -> String_set.diff left_ids right_ids
    | Difference_right -> String_set.diff right_ids left_ids
    | Difference_nodes ->
        String_set.union (String_set.diff left_ids right_ids) (String_set.diff right_ids left_ids)
  in
  let choose_nodes source =
    source.graph.nodes |> List.filter (fun (node : Graph.node) -> String_set.mem node.id selected)
  in
  let nodes =
    choose_nodes left @ choose_nodes right
    |> List.sort_uniq (fun (a : Graph.node) b -> String.compare a.id b.id)
  in
  let edges =
    left.graph.edges @ right.graph.edges
    |> List.filter (fun (edge : Graph.edge) ->
           String_set.mem edge.source selected && String_set.mem edge.target selected)
    |> List.sort_uniq (fun left right -> String.compare (edge_key left) (edge_key right))
  in
  let graph =
    graph_of_nodes_edges
      Graph.{ left.graph with id = left.graph.id ^ "-comparison"; title = "Comparison" }
      nodes edges
  in
  {
    project_id = left.project_id;
    revision = Int.max left.revision right.revision;
    parent_revision = None;
    graph;
    edits = [];
    statement_ids = List.sort_uniq String.compare (left.statement_ids @ right.statement_ids);
  }

let timeline revisions =
  revisions
  |> List.sort (fun (left : t) right -> Int.compare left.revision right.revision)
  |> List.map (fun (value : t) ->
         {
           revision = value.revision;
           node_count = List.length value.graph.nodes;
           edge_count = List.length value.graph.edges;
           statement_ids = value.statement_ids;
         })
