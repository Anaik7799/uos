(** Pure analytics over a visible immutable revision.

    Every report is authority-labelled by revision and filter digest. The
    observations do not mutate the graph and never read persistence. Network
    topics and the deterministic comparison projection are deliberately
    distinct carriers. *)

module Graph = Graph_intelligence
module Revision = Graph_revision
module Processing = Graph_processing
module String_map = Map.Make (String)
module String_set = Set.Make (String)

type excerpt = {
  statement_id : string;
  text : string;
  node_ids : string list;
  metadata : (string * string) list;
}

type topic = { id : string; label : string; node_ids : string list; influence : float }
type ranked = { node_id : string; score : float }
type gateway = { node_id : string; globality : float; locality : float }
type relation = { source : string; target : string; occurrences : int; weight : float }
type sentiment_summary = { positive : int; negative : int; neutral : int; total : int }

type structure = {
  modularity : float;
  influence_entropy : float;
  diversity : [ `Biased | `Focused | `Diverse | `Dispersed ];
  components : int;
  density : float;
}

type stats = {
  words : int;
  unique_lemmas : int;
  characters : int;
  nodes : int;
  edges : int;
  average_degree : float;
}

type trend = { bucket : int; topic_id : string; cumulative_occurrences : int }
type propagation = { values : float list; alpha : float option; classification : string }
type bucket = { degree : int; count : int }

type report = {
  revision : int;
  filter_digest : string;
  excerpts : excerpt list;
  topics : topic list;
  influential_concepts : ranked list;
  gaps : Graph.gap list;
  gateways : gateway list;
  relations : relation list;
  sentiment : sentiment_summary;
  stats : stats;
  trends : trend list;
  structure : structure;
  propagation : propagation;
  degree_distribution : bucket list;
  lda_comparison : topic list;
}

let contains ~needle haystack =
  let needle = String.lowercase_ascii needle and haystack = String.lowercase_ascii haystack in
  let needle_length = String.length needle and length = String.length haystack in
  let rec loop at =
    at + needle_length <= length
    && (String.sub haystack at needle_length = needle || loop (at + 1))
  in
  needle_length = 0 || loop 0

let tokens text =
  let buffer = Buffer.create (String.length text) in
  String.iter
    (fun character ->
      match character with
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' ->
          Buffer.add_char buffer (Char.lowercase_ascii character)
      | _ -> Buffer.add_char buffer ' ')
    text;
  Buffer.contents buffer |> String.split_on_char ' '
  |> List.filter (fun value -> String.length value > 0)

let topics graph =
  let groups =
    List.fold_left
      (fun groups (node : Graph.node) ->
        let group = match String.trim node.group with "" -> node.id | value -> value in
        let existing = Option.value ~default:[] (String_map.find_opt group groups) in
        String_map.add group (node :: existing) groups)
      String_map.empty graph.Graph.nodes
  in
  let total =
    List.fold_left (fun sum (node : Graph.node) -> sum +. Float.max 0. node.weight) 0. graph.nodes
  in
  String_map.bindings groups
  |> List.map (fun (group, nodes) ->
         let node_ids =
           nodes |> List.map (fun (node : Graph.node) -> node.id) |> List.sort String.compare
         in
         let weight =
           List.fold_left (fun sum (node : Graph.node) -> sum +. Float.max 0. node.weight) 0. nodes
         in
         {
           id = "network:" ^ group;
           label = group;
           node_ids;
           influence = if total = 0. then 0. else weight /. total;
         })
  |> List.sort (fun left right ->
         let by_influence = Float.compare right.influence left.influence in
         if by_influence = 0 then String.compare left.id right.id else by_influence)

let sentiment_of_statement (statement : Processing.statement) =
  match List.assoc_opt "sentiment" statement.metadata |> Option.map String.lowercase_ascii with
  | Some "positive" -> `Positive
  | Some "negative" -> `Negative
  | Some "neutral" -> `Neutral
  | Some _ | None ->
      let score = Graph_ingest.sentiment statement.text in
      if score > 0. then `Positive else if score < 0. then `Negative else `Neutral

let entropy topics =
  List.fold_left
    (fun sum topic ->
      if topic.influence <= 0. then sum else sum -. (topic.influence *. log topic.influence))
    0. topics

let diversity topic_count entropy =
  if topic_count <= 1 then `Biased
  else
    let maximum = log (float_of_int topic_count) in
    let normalized = if maximum = 0. then 0. else entropy /. maximum in
    if normalized < 0.35 then `Focused
    else if normalized < 0.75 then `Diverse
    else `Dispersed

let analyze ~filter_digest (revision : Revision.t) statements =
  let graph = revision.graph and network = Graph.analyze revision.graph in
  let topics = topics graph in
  let excerpts =
    statements
    |> List.sort (fun (left : Processing.statement) right -> Int.compare left.ordinal right.ordinal)
    |> List.map (fun (statement : Processing.statement) ->
           let node_ids =
             graph.nodes
             |> List.filter (fun (node : Graph.node) ->
                    contains ~needle:node.id statement.text || contains ~needle:node.label statement.text)
             |> List.map (fun (node : Graph.node) -> node.id)
           in
           { statement_id = statement.id; text = statement.text; node_ids; metadata = statement.metadata })
  in
  let degrees = Graph.degrees graph in
  let max_betweenness =
    List.fold_left (fun maximum (_, score) -> Float.max maximum score) 0. network.betweenness
  in
  let influential_concepts =
    network.betweenness
    |> List.map (fun (node_id, score) -> { node_id; score })
  in
  let gateways =
    network.betweenness
    |> List.map (fun (node_id, score) ->
           let degree = Option.value ~default:0 (List.assoc_opt node_id degrees) |> float_of_int in
           let normalized = if max_betweenness = 0. then 0. else score /. max_betweenness in
           { node_id; globality = normalized /. (1. +. degree); locality = degree /. (1. +. normalized) })
    |> List.sort (fun left right ->
           let by_globality = Float.compare right.globality left.globality in
           if by_globality = 0 then String.compare left.node_id right.node_id else by_globality)
  in
  let relations =
    graph.edges
    |> List.map (fun (edge : Graph.edge) ->
           {
             source = edge.source;
             target = edge.target;
             occurrences = int_of_float (Float.ceil edge.weight);
             weight = edge.weight;
           })
  in
  let positive, negative, neutral =
    List.fold_left
      (fun (positive, negative, neutral) statement ->
        match sentiment_of_statement statement with
        | `Positive -> (positive + 1, negative, neutral)
        | `Negative -> (positive, negative + 1, neutral)
        | `Neutral -> (positive, negative, neutral + 1))
      (0, 0, 0) statements
  in
  let sentiment = { positive; negative; neutral; total = List.length statements } in
  let all_tokens = List.concat_map (fun (statement : Processing.statement) -> tokens statement.text) statements in
  let unique_lemmas = List.sort_uniq String.compare all_tokens |> List.length in
  let nodes = List.length graph.nodes and edges = List.length graph.edges in
  let stats =
    {
      words = List.length all_tokens;
      unique_lemmas;
      characters = List.fold_left (fun count statement -> count + String.length statement.Processing.text) 0 statements;
      nodes;
      edges;
      average_degree = if nodes = 0 then 0. else (2. *. float_of_int edges) /. float_of_int nodes;
    }
  in
  let topic_for_statement (statement : Processing.statement) =
    topics
    |> List.map (fun topic ->
           ( topic,
             List.fold_left
               (fun count id -> if contains ~needle:id statement.text then count + 1 else count)
               0 topic.node_ids ))
    |> List.sort (fun (left, lc) (right, rc) ->
           let by_count = Int.compare rc lc in
           if by_count = 0 then String.compare left.id right.id else by_count)
    |> function (topic, count) :: _ when count > 0 -> topic.id | _ -> "network:unclassified"
  in
  let _, trends =
    statements
    |> List.sort (fun (left : Processing.statement) right -> Int.compare left.ordinal right.ordinal)
    |> List.fold_left
         (fun (counts, trends) statement ->
           let topic_id = topic_for_statement statement in
           let count = Option.value ~default:0 (String_map.find_opt topic_id counts) + 1 in
           ( String_map.add topic_id count counts,
             { bucket = statement.Processing.ordinal; topic_id; cumulative_occurrences = count } :: trends ))
         (String_map.empty, [])
  in
  let trends = List.rev trends in
  let intra =
    let group_of id =
      graph.nodes
      |> List.find_opt (fun (node : Graph.node) -> node.id = id)
      |> Option.map (fun node -> node.Graph.group)
    in
    List.fold_left
      (fun count (edge : Graph.edge) ->
        match (group_of edge.source, group_of edge.target) with
        | Some left, Some right when left = right -> count + 1
        | _ -> count)
      0 graph.edges
  in
  let influence_entropy = entropy topics in
  let structure =
    {
      modularity = if edges = 0 then 0. else float_of_int intra /. float_of_int edges;
      influence_entropy;
      diversity = diversity (List.length topics) influence_entropy;
      components = network.components;
      density = network.density;
    }
  in
  let statement_count = List.length statements in
  let values =
    List.mapi
      (fun index _ -> if statement_count = 0 then 0. else float_of_int (index + 1) /. float_of_int statement_count)
      statements
  in
  let propagation =
    {
      values;
      alpha = if statement_count < 2 then None else Some 1.;
      classification = if statement_count < 2 then "insufficient" else "bounded-cumulative";
    }
  in
  let degree_distribution =
    degrees
    |> List.fold_left
         (fun counts (_, degree) ->
           let count = Option.value ~default:0 (List.assoc_opt degree counts) in
           (degree, count + 1) :: List.remove_assoc degree counts)
         []
    |> List.sort compare
    |> List.map (fun (degree, count) -> { degree; count })
  in
  let lda_comparison =
    topics
    |> List.mapi (fun index topic ->
           { topic with id = "lda:" ^ string_of_int (index + 1); label = "comparison " ^ topic.label })
  in
  {
    revision = revision.revision;
    filter_digest;
    excerpts;
    topics;
    influential_concepts;
    gaps = network.gaps;
    gateways;
    relations;
    sentiment;
    stats;
    trends;
    structure;
    propagation;
    degree_distribution;
    lda_comparison;
  }

let float value = `Float value

let topic_json (topic : topic) =
  `Assoc
    [
      ("id", `String topic.id);
      ("label", `String topic.label);
      ("node_ids", `List (List.map (fun value -> `String value) topic.node_ids));
      ("influence", float topic.influence);
    ]

let to_yojson report =
  `Assoc
    [
      ("revision", `Int report.revision);
      ("filter_digest", `String report.filter_digest);
      ( "excerpts",
        `List
          (List.map
             (fun (excerpt : excerpt) ->
               `Assoc
                 [
                   ("statement_id", `String excerpt.statement_id);
                   ("text", `String excerpt.text);
                   ("node_ids", `List (List.map (fun value -> `String value) excerpt.node_ids));
                 ])
             report.excerpts) );
      ("topics", `List (List.map topic_json report.topics));
      ( "influential_concepts",
        `List
          (List.map
             (fun (ranked : ranked) ->
               `Assoc [ ("node_id", `String ranked.node_id); ("score", float ranked.score) ])
             report.influential_concepts) );
      ( "gateways",
        `List
          (List.map
             (fun (gateway : gateway) ->
               `Assoc
                 [ ("node_id", `String gateway.node_id); ("globality", float gateway.globality);
                   ("locality", float gateway.locality) ])
             report.gateways) );
      ( "gaps",
        `List
          (List.map
             (fun (gap : Graph.gap) ->
               `Assoc
                 [ ("left_community", `String gap.left_community);
                   ("right_community", `String gap.right_community);
                   ("left_node", `String gap.left_node);
                   ("right_node", `String gap.right_node);
                   ("score", float gap.score) ])
             report.gaps) );
      ( "relations",
        `List
          (List.map
             (fun (relation : relation) ->
               `Assoc
                 [ ("source", `String relation.source); ("target", `String relation.target);
                   ("occurrences", `Int relation.occurrences); ("weight", float relation.weight) ])
             report.relations) );
      ( "sentiment",
        `Assoc
          [ ("positive", `Int report.sentiment.positive); ("negative", `Int report.sentiment.negative);
            ("neutral", `Int report.sentiment.neutral); ("total", `Int report.sentiment.total) ] );
      ( "stats",
        `Assoc
          [ ("words", `Int report.stats.words); ("unique_lemmas", `Int report.stats.unique_lemmas);
            ("characters", `Int report.stats.characters); ("nodes", `Int report.stats.nodes);
            ("edges", `Int report.stats.edges); ("average_degree", float report.stats.average_degree) ] );
      ( "structure",
        `Assoc
          [ ("modularity", float report.structure.modularity);
            ("influence_entropy", float report.structure.influence_entropy);
            ( "diversity",
              `String
                (match report.structure.diversity with
                | `Biased -> "biased" | `Focused -> "focused"
                | `Diverse -> "diverse" | `Dispersed -> "dispersed") );
            ("components", `Int report.structure.components); ("density", float report.structure.density) ] );
      ( "trends",
        `List
          (List.map
             (fun (trend : trend) ->
               `Assoc [ ("bucket", `Int trend.bucket); ("topic_id", `String trend.topic_id);
                        ("cumulative_occurrences", `Int trend.cumulative_occurrences) ])
             report.trends) );
      ( "propagation",
        `Assoc
          [ ("values", `List (List.map float report.propagation.values));
            ("alpha", match report.propagation.alpha with Some value -> float value | None -> `Null);
            ("classification", `String report.propagation.classification) ] );
      ( "degree_distribution",
        `List
          (List.map
             (fun (bucket : bucket) ->
               `Assoc [ ("degree", `Int bucket.degree); ("count", `Int bucket.count) ])
             report.degree_distribution) );
      ("lda_comparison", `List (List.map topic_json report.lda_comparison));
    ]
