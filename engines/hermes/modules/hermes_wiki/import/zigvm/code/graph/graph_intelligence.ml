module String_set = Set.Make (String)
module String_map = Map.Make (String)

type node = {
  id : string;
  label : string;
  kind : string;
  layer : string;
  group : string;
  detail : string;
  weight : float;
}

type edge = {
  source : string;
  target : string;
  relation : string;
  weight : float;
}

type t = {
  id : string;
  title : string;
  kind : string;
  nodes : node list;
  edges : edge list;
}

type gap = {
  left_community : string;
  right_community : string;
  left_node : string;
  right_node : string;
  score : float;
}

type analytics = {
  node_count : int;
  edge_count : int;
  density : float;
  components : int;
  pagerank : (string * float) list;
  betweenness : (string * float) list;
  communities : (string * string) list;
  gaps : gap list;
}

type comparison = {
  left_id : string;
  right_id : string;
  common_nodes : string list;
  only_left_nodes : string list;
  only_right_nodes : string list;
  common_edges : string list;
  only_left_edges : string list;
  only_right_edges : string list;
}

let finite_nonnegative value =
  match classify_float value with
  | FP_normal | FP_subnormal | FP_zero -> Float.max 0. value
  | FP_infinite | FP_nan -> 0.

let edge_key edge =
  edge.source ^ "\x1f" ^ edge.relation ^ "\x1f" ^ edge.target

let normalize graph =
  let nodes_by_id =
    List.fold_left
      (fun nodes (node : node) ->
        if node.id = "" || String_map.mem node.id nodes then nodes
        else
          String_map.add node.id
            { node with weight = finite_nonnegative node.weight }
            nodes)
      String_map.empty graph.nodes
  in
  let _, edges =
    List.fold_left
      (fun (seen, edges) (edge : edge) ->
        let key = edge_key edge in
        if
          edge.source = edge.target
          || not (String_map.mem edge.source nodes_by_id)
          || not (String_map.mem edge.target nodes_by_id)
          || String_set.mem key seen
        then (seen, edges)
        else
          ( String_set.add key seen,
            { edge with weight = finite_nonnegative edge.weight } :: edges ))
      (String_set.empty, []) graph.edges
  in
  {
    graph with
    nodes = List.map snd (String_map.bindings nodes_by_id);
    edges = List.sort (fun left right -> String.compare (edge_key left) (edge_key right)) edges;
  }

let index graph =
  let graph = normalize graph in
  let nodes = Array.of_list graph.nodes in
  let ids = Hashtbl.create (Array.length nodes * 2 + 1) in
  Array.iteri
    (fun position (node : node) -> Hashtbl.replace ids node.id position)
    nodes;
  let outgoing = Array.make (Array.length nodes) [] in
  let undirected = Array.make (Array.length nodes) [] in
  List.iter
    (fun edge ->
      match (Hashtbl.find_opt ids edge.source, Hashtbl.find_opt ids edge.target) with
      | Some source, Some target ->
          outgoing.(source) <- target :: outgoing.(source);
          undirected.(source) <- target :: undirected.(source);
          undirected.(target) <- source :: undirected.(target)
      | _ -> ())
    graph.edges;
  Array.iteri
    (fun i adjacent -> undirected.(i) <- List.sort_uniq Int.compare adjacent)
    undirected;
  (graph, nodes, ids, outgoing, undirected)

let degrees graph =
  let _, nodes, _, _, adjacent = index graph in
  Array.to_list
    (Array.mapi
       (fun i (node : node) -> (node.id, List.length adjacent.(i)))
       nodes)
  |> List.sort (fun (a, da) (b, db) ->
         let by_degree = Int.compare db da in
         if by_degree = 0 then String.compare a b else by_degree)

let bounded ~max_nodes graph =
  let graph = normalize graph in
  if max_nodes <= 0 then { graph with nodes = []; edges = [] }
  else if List.length graph.nodes <= max_nodes then graph
  else
    let keep =
      degrees graph
      |> List.filteri (fun index _ -> index < max_nodes)
      |> List.fold_left
           (fun ids (id, _) -> String_set.add id ids)
           String_set.empty
    in
    {
      graph with
      nodes =
        List.filter (fun (node : node) -> String_set.mem node.id keep) graph.nodes;
      edges =
        List.filter
          (fun (edge : edge) ->
            String_set.mem edge.source keep && String_set.mem edge.target keep)
          graph.edges;
    }

let pagerank ?(iterations = 60) ?(damping = 0.85) graph =
  let _, nodes, _, outgoing, _ = index graph in
  let count = Array.length nodes in
  if count = 0 then []
  else
    let count_f = float_of_int count in
    let damping = Float.max 0. (Float.min 1. damping) in
    let rank = Array.make count (1. /. count_f) in
    for _ = 1 to Int.max 0 iterations do
      let next = Array.make count ((1. -. damping) /. count_f) in
      let dangling = ref 0. in
      Array.iteri
        (fun source targets ->
          match targets with
          | [] -> dangling := !dangling +. rank.(source)
          | _ ->
              let share =
                damping *. rank.(source) /. float_of_int (List.length targets)
              in
              List.iter (fun target -> next.(target) <- next.(target) +. share) targets)
        outgoing;
      let dangling_share = damping *. !dangling /. count_f in
      Array.iteri (fun i value -> next.(i) <- value +. dangling_share) next;
      Array.blit next 0 rank 0 count
    done;
    Array.to_list
      (Array.mapi (fun i (node : node) -> (node.id, rank.(i))) nodes)
    |> List.sort (fun (a, ra) (b, rb) ->
           let by_rank = Float.compare rb ra in
           if by_rank = 0 then String.compare a b else by_rank)

let betweenness graph =
  let _, nodes, _, _, adjacent = index graph in
  let count = Array.length nodes in
  let scores = Array.make count 0. in
  for source = 0 to count - 1 do
    let stack = Stack.create () in
    let predecessors = Array.make count [] in
    let paths = Array.make count 0. in
    let distance = Array.make count (-1) in
    paths.(source) <- 1.;
    distance.(source) <- 0;
    let queue = Queue.create () in
    Queue.add source queue;
    while not (Queue.is_empty queue) do
      let vertex = Queue.take queue in
      Stack.push vertex stack;
      List.iter
        (fun next ->
          if distance.(next) < 0 then (
            distance.(next) <- distance.(vertex) + 1;
            Queue.add next queue);
          if distance.(next) = distance.(vertex) + 1 then (
            paths.(next) <- paths.(next) +. paths.(vertex);
            predecessors.(next) <- vertex :: predecessors.(next)))
        adjacent.(vertex)
    done;
    let dependency = Array.make count 0. in
    while not (Stack.is_empty stack) do
      let vertex = Stack.pop stack in
      if paths.(vertex) > 0. then
        List.iter
          (fun predecessor ->
            dependency.(predecessor) <-
              dependency.(predecessor)
              +. (paths.(predecessor) /. paths.(vertex))
                 *. (1. +. dependency.(vertex)))
          predecessors.(vertex);
      if vertex <> source then scores.(vertex) <- scores.(vertex) +. dependency.(vertex)
    done
  done;
  Array.to_list
    (Array.mapi (fun i (node : node) -> (node.id, scores.(i) /. 2.)) nodes)
  |> List.sort (fun (a, sa) (b, sb) ->
         let by_score = Float.compare sb sa in
         if by_score = 0 then String.compare a b else by_score)

let communities ?(iterations = 24) graph =
  let _, nodes, _, _, adjacent = index graph in
  let count = Array.length nodes in
  let labels = Array.init count (fun i -> nodes.(i).id) in
  let iteration = ref 0 and changed = ref true in
  while !iteration < iterations && !changed do
    incr iteration;
    changed := false;
    for vertex = 0 to count - 1 do
      let frequencies = Hashtbl.create 8 in
      List.iter
        (fun next ->
          let label = labels.(next) in
          let previous = Option.value ~default:0 (Hashtbl.find_opt frequencies label) in
          Hashtbl.replace frequencies label (previous + 1))
        adjacent.(vertex);
      let best =
        Hashtbl.fold
          (fun label frequency current ->
            match current with
            | None -> Some (label, frequency)
            | Some (best_label, best_frequency) ->
                if
                  frequency > best_frequency
                  || (frequency = best_frequency && String.compare label best_label < 0)
                then Some (label, frequency)
                else current)
          frequencies None
      in
      match best with
      | Some (label, _) when not (String.equal label labels.(vertex)) ->
          labels.(vertex) <- label;
          changed := true
      | _ -> ()
    done
  done;
  let representatives = Hashtbl.create count in
  Array.iteri
    (fun i label ->
      let id = nodes.(i).id in
      match Hashtbl.find_opt representatives label with
      | Some previous when String.compare previous id <= 0 -> ()
      | _ -> Hashtbl.replace representatives label id)
    labels;
  Array.to_list
    (Array.mapi
       (fun i (node : node) ->
         (node.id, Option.value ~default:node.id (Hashtbl.find_opt representatives labels.(i))))
       nodes)

let component_count graph =
  let _, nodes, _, _, adjacent = index graph in
  let seen = Array.make (Array.length nodes) false in
  let count = ref 0 in
  Array.iteri
    (fun start _ ->
      if not seen.(start) then (
        incr count;
        let queue = Queue.create () in
        Queue.add start queue;
        seen.(start) <- true;
        while not (Queue.is_empty queue) do
          let vertex = Queue.take queue in
          List.iter
            (fun next ->
              if not seen.(next) then (
                seen.(next) <- true;
                Queue.add next queue))
            adjacent.(vertex)
        done))
    nodes;
  !count

let analyze graph =
  let graph = normalize graph in
  let node_count = List.length graph.nodes in
  let edge_count = List.length graph.edges in
  let pagerank = pagerank graph in
  let betweenness = betweenness graph in
  let communities = communities graph in
  let community_of id = Option.value ~default:id (List.assoc_opt id communities) in
  let centrality id = Option.value ~default:0. (List.assoc_opt id betweenness) in
  let linked =
    List.fold_left
      (fun set edge ->
        String_set.add (edge.source ^ "\x1f" ^ edge.target)
          (String_set.add (edge.target ^ "\x1f" ^ edge.source) set))
      String_set.empty graph.edges
  in
  let representatives =
    List.fold_left
      (fun representatives (node : node) ->
        let community = community_of node.id in
        match String_map.find_opt community representatives with
        | None -> String_map.add community node.id representatives
        | Some previous ->
            if centrality node.id > centrality previous then
              String_map.add community node.id representatives
            else representatives)
      String_map.empty graph.nodes
    |> String_map.bindings
  in
  let rec pairs accumulated = function
    | [] -> accumulated
    | (left_community, left_node) :: rest ->
        let accumulated =
          List.fold_left
            (fun gaps (right_community, right_node) ->
              if
                String_set.mem (left_node ^ "\x1f" ^ right_node) linked
                || String.equal left_community right_community
              then gaps
              else
                {
                  left_community;
                  right_community;
                  left_node;
                  right_node;
                  score = centrality left_node +. centrality right_node;
                }
                :: gaps)
            accumulated rest
        in
        pairs accumulated rest
  in
  let gaps =
    pairs [] representatives
    |> List.sort (fun left right -> Float.compare right.score left.score)
    |> List.filteri (fun index _ -> index < 12)
  in
  let possible = node_count * (node_count - 1) in
  {
    node_count;
    edge_count;
    density = if possible = 0 then 0. else float_of_int edge_count /. float_of_int possible;
    components = component_count graph;
    pagerank;
    betweenness;
    communities;
    gaps;
  }

let edge_keys graph =
  normalize graph |> fun normalized ->
  List.fold_left (fun set edge -> String_set.add (edge_key edge) set) String_set.empty normalized.edges

let node_ids graph =
  normalize graph |> fun normalized ->
  List.fold_left
    (fun set (node : node) -> String_set.add node.id set)
    String_set.empty normalized.nodes

let compare left right =
  let left_nodes = node_ids left and right_nodes = node_ids right in
  let left_edges = edge_keys left and right_edges = edge_keys right in
  {
    left_id = left.id;
    right_id = right.id;
    common_nodes = String_set.elements (String_set.inter left_nodes right_nodes);
    only_left_nodes = String_set.elements (String_set.diff left_nodes right_nodes);
    only_right_nodes = String_set.elements (String_set.diff right_nodes left_nodes);
    common_edges = String_set.elements (String_set.inter left_edges right_edges);
    only_left_edges = String_set.elements (String_set.diff left_edges right_edges);
    only_right_edges = String_set.elements (String_set.diff right_edges left_edges);
  }

let assoc_float pairs =
  `List
    (List.map
       (fun (id, value) -> `Assoc [ ("id", `String id); ("value", `Float value) ])
       pairs)

let analytics_json analytics =
  `Assoc
    [
      ("node_count", `Int analytics.node_count);
      ("edge_count", `Int analytics.edge_count);
      ("density", `Float analytics.density);
      ("components", `Int analytics.components);
      ("pagerank", assoc_float analytics.pagerank);
      ("betweenness", assoc_float analytics.betweenness);
      ( "communities",
        `List
          (List.map
             (fun (id, community) ->
               `Assoc [ ("id", `String id); ("community", `String community) ])
             analytics.communities) );
      ( "gaps",
        `List
          (List.map
             (fun gap ->
               `Assoc
                 [
                   ("left_community", `String gap.left_community);
                   ("right_community", `String gap.right_community);
                   ("left_node", `String gap.left_node);
                   ("right_node", `String gap.right_node);
                   ("score", `Float gap.score);
                 ])
             analytics.gaps) );
    ]

let to_yojson ?analytics graph =
  let graph = normalize graph in
  let fields =
    [
      ("id", `String graph.id);
      ("title", `String graph.title);
      ("kind", `String graph.kind);
      ( "nodes",
        `List
          (List.map
             (fun (node : node) ->
               `Assoc
                 [
                   ("id", `String node.id);
                   ("label", `String node.label);
                   ("kind", `String node.kind);
                   ("layer", `String node.layer);
                   ("group", `String node.group);
                   ("detail", `String node.detail);
                   ("weight", `Float node.weight);
                 ])
             graph.nodes) );
      ( "edges",
        `List
          (List.map
             (fun edge ->
               `Assoc
                 [
                   ("source", `String edge.source);
                   ("target", `String edge.target);
                   ("relation", `String edge.relation);
                   ("weight", `Float edge.weight);
                 ])
             graph.edges) );
    ]
  in
  `Assoc
    (match analytics with None -> fields | Some value -> fields @ [ ("analytics", analytics_json value) ])

let of_yojson json =
  let open Yojson.Safe.Util in
  let node json =
    try
      Some
        {
          id = json |> member "id" |> to_string;
          label = json |> member "label" |> to_string;
          kind = json |> member "kind" |> to_string;
          layer = json |> member "layer" |> to_string;
          group = json |> member "group" |> to_string;
          detail = json |> member "detail" |> to_string;
          weight = json |> member "weight" |> to_float;
        }
    with _ -> None
  in
  let edge json =
    try
      Some
        {
          source = json |> member "source" |> to_string;
          target = json |> member "target" |> to_string;
          relation = json |> member "relation" |> to_string;
          weight = json |> member "weight" |> to_float;
        }
    with _ -> None
  in
  try
    Ok
      (normalize
         {
           id = json |> member "id" |> to_string;
           title = json |> member "title" |> to_string;
           kind = json |> member "kind" |> to_string;
           nodes = json |> member "nodes" |> to_list |> List.filter_map node;
           edges = json |> member "edges" |> to_list |> List.filter_map edge;
         })
  with _ -> Error "invalid property graph JSON"

let comparison_to_yojson comparison =
  let strings values = `List (List.map (fun value -> `String value) values) in
  `Assoc
    [
      ("left_id", `String comparison.left_id);
      ("right_id", `String comparison.right_id);
      ("common_nodes", strings comparison.common_nodes);
      ("only_left_nodes", strings comparison.only_left_nodes);
      ("only_right_nodes", strings comparison.only_right_nodes);
      ("common_edges", strings comparison.common_edges);
      ("only_left_edges", strings comparison.only_left_edges);
      ("only_right_edges", strings comparison.only_right_edges);
    ]

let xml_escape value =
  let buffer = Buffer.create (String.length value) in
  String.iter
    (function
      | '&' -> Buffer.add_string buffer "&amp;"
      | '<' -> Buffer.add_string buffer "&lt;"
      | '>' -> Buffer.add_string buffer "&gt;"
      | '"' -> Buffer.add_string buffer "&quot;"
      | '\'' -> Buffer.add_string buffer "&apos;"
      | character -> Buffer.add_char buffer character)
    value;
  Buffer.contents buffer

let to_graphml graph =
  let graph = normalize graph in
  let buffer = Buffer.create 4096 in
  Buffer.add_string buffer "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  Buffer.add_string buffer "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><graph edgedefault=\"directed\">\n";
  List.iter
    (fun (node : node) ->
      Buffer.add_string buffer
        (Printf.sprintf "<node id=\"%s\"><data key=\"label\">%s</data><data key=\"kind\">%s</data></node>\n"
           (xml_escape node.id) (xml_escape node.label) (xml_escape node.kind)))
    graph.nodes;
  List.iteri
    (fun index edge ->
      Buffer.add_string buffer
        (Printf.sprintf "<edge id=\"e%d\" source=\"%s\" target=\"%s\"><data key=\"relation\">%s</data></edge>\n"
           index (xml_escape edge.source) (xml_escape edge.target)
           (xml_escape edge.relation)))
    graph.edges;
  Buffer.add_string buffer "</graph></graphml>\n";
  Buffer.contents buffer

let dot_escape value =
  String.concat "\\\"" (String.split_on_char '"' value)

let to_dot graph =
  let graph = normalize graph in
  let buffer = Buffer.create 4096 in
  Buffer.add_string buffer "digraph zigvm {\n";
  List.iter
    (fun (node : node) ->
      Buffer.add_string buffer
        (Printf.sprintf "  \"%s\" [label=\"%s\", group=\"%s\"];\n"
           (dot_escape node.id) (dot_escape node.label) (dot_escape node.kind)))
    graph.nodes;
  List.iter
    (fun edge ->
      Buffer.add_string buffer
        (Printf.sprintf "  \"%s\" -> \"%s\" [label=\"%s\"];\n"
           (dot_escape edge.source) (dot_escape edge.target)
           (dot_escape edge.relation)))
    graph.edges;
  Buffer.add_string buffer "}\n";
  Buffer.contents buffer
