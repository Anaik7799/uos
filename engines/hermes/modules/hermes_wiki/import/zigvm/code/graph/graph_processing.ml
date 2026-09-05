(** Deterministic attributed-text processing.

    The carrier is an ordered statement list plus an explicit processing
    profile. Its denotation is a typed token multiset, a weighted finite graph,
    and a provenance relation from normalized nodes to source statements.
    [process] is deterministic, total for all profile values, and clamps the
    co-occurrence window to the public interval [1,12]. *)

module Graph = Graph_intelligence
module String_map = Map.Make (String)
module String_set = Set.Make (String)

type graph_mode = Words_and_entities | Entities_only

type profile = {
  language : string;
  lemmatize : bool;
  stop_words : string list;
  protected_words : string list;
  synonyms : (string * string) list;
  process_words : bool;
  process_wiki_links : bool;
  process_mentions : bool;
  process_categories : bool;
  window : int;
  graph_mode : graph_mode;
}

type statement = {
  id : string;
  source_id : string;
  ordinal : int;
  text : string;
  metadata : (string * string) list;
}

type typed_node = { id : string; label : string; kind : string; weight : float }
type metadata_tag = { statement_id : string; key : string; value : string }

type result = {
  statements : statement list;
  graph : Graph.t;
  typed_nodes : typed_node list;
  node_statements : (string * string list) list;
  aliases : (string * string) list;
  tags : metadata_tag list;
  effective_language : string;
  digest : string;
}

let default_profile =
  {
    language = "auto";
    lemmatize = true;
    stop_words = [ "a"; "an"; "and"; "of"; "or"; "the"; "to" ];
    protected_words = [];
    synonyms = [];
    process_words = true;
    process_wiki_links = true;
    process_mentions = true;
    process_categories = true;
    window = 4;
    graph_mode = Words_and_entities;
  }

let statement ~id ~source_id ?(ordinal = 0) ?(metadata = []) text =
  { id; source_id; ordinal; text; metadata }

let normalize_space value =
  let buffer = Buffer.create (String.length value) in
  let pending_space = ref false in
  String.iter
    (fun character ->
      match character with
      | ' ' | '\t' | '\r' | '\n' -> pending_space := Buffer.length buffer > 0
      | _ ->
          if !pending_space then Buffer.add_char buffer '-';
          pending_space := false;
          Buffer.add_char buffer character)
    value;
  Buffer.contents buffer

let trim_token value =
  let is_boundary = function
    | '.' | ',' | ';' | ':' | '!' | '?' | '(' | ')' | '{' | '}' | '"' | '\'' -> true
    | _ -> false
  in
  let first = ref 0 and last = ref (String.length value - 1) in
  while !first <= !last && is_boundary value.[!first] do incr first done;
  while !last >= !first && is_boundary value.[!last] do decr last done;
  if !first > !last then "" else String.sub value !first (!last - !first + 1)

let canonical value =
  value |> String.trim |> normalize_space |> String.lowercase_ascii |> trim_token

let simple_lemma value =
  let length = String.length value in
  if length > 4 && String.ends_with ~suffix:"ies" value then
    String.sub value 0 (length - 3) ^ "y"
  else if length > 3 && String.ends_with ~suffix:"s" value
          && not (String.ends_with ~suffix:"ss" value)
  then String.sub value 0 (length - 1)
  else value

type raw_token = { raw : string; kind : string }

let raw_tokens text =
  let length = String.length text in
  let rec find_close at =
    if at + 1 >= length then None
    else if text.[at] = ']' && text.[at + 1] = ']' then Some at
    else find_close (at + 1)
  in
  let rec skip_space at =
    if at < length then
      match text.[at] with ' ' | '\t' | '\r' | '\n' -> skip_space (at + 1) | _ -> at
    else at
  in
  let rec word_end at =
    if at >= length then at
    else
      match text.[at] with
      | ' ' | '\t' | '\r' | '\n' -> at
      | _ -> word_end (at + 1)
  in
  let rec loop at tokens =
    let at = skip_space at in
    if at >= length then List.rev tokens
    else if at + 1 < length && text.[at] = '[' && text.[at + 1] = '[' then
      (match find_close (at + 2) with
      | Some close ->
          let raw = String.sub text (at + 2) (close - at - 2) in
          loop (close + 2) ({ raw; kind = "wiki-link" } :: tokens)
      | None ->
          let finish = word_end at in
          loop finish ({ raw = String.sub text at (finish - at); kind = "word" } :: tokens))
    else
      let finish = word_end at in
      let raw = String.sub text at (finish - at) |> trim_token in
      let lower = String.lowercase_ascii raw in
      let raw, kind =
        if String.starts_with ~prefix:"@" raw && String.length raw > 1 then
          (String.sub raw 1 (String.length raw - 1), "mention")
        else if String.starts_with ~prefix:"#" raw && String.length raw > 1 then
          (String.sub raw 1 (String.length raw - 1), "tag")
        else if String.starts_with ~prefix:"entity:" lower && String.length raw > 7 then
          (String.sub raw 7 (String.length raw - 7), "entity")
        else (raw, "word")
      in
      loop finish ({ raw; kind } :: tokens)
  in
  loop 0 []

let normalized_pairs pairs =
  pairs
  |> List.filter_map (fun (source, target) ->
         let source = canonical source and target = canonical target in
         if source = "" || target = "" then None else Some (source, target))
  |> List.sort_uniq compare

let process profile statements =
  let effective_language =
    match canonical profile.language with "" -> "auto" | value -> value
  in
  let protected =
    profile.protected_words
    |> List.fold_left (fun set value -> String_set.add (canonical value) set) String_set.empty
  in
  let stop_words =
    profile.stop_words
    |> List.fold_left (fun set value -> String_set.add (canonical value) set) String_set.empty
  in
  let aliases = normalized_pairs profile.synonyms in
  let alias_map =
    List.fold_left (fun map (source, target) -> String_map.add source target map)
      String_map.empty aliases
  in
  let normalize raw kind =
    let value = canonical raw in
    let value =
      if kind = "word" && profile.lemmatize && not (String_set.mem value protected)
      then simple_lemma value
      else value
    in
    Option.value ~default:value (String_map.find_opt value alias_map)
  in
  let enabled kind =
    match kind with
    | "word" -> profile.process_words && profile.graph_mode = Words_and_entities
    | "wiki-link" -> profile.process_wiki_links
    | "mention" -> profile.process_mentions
    | "tag" -> profile.process_categories
    | "entity" -> true
    | _ -> false
  in
  let statement_tokens =
    List.map
      (fun statement ->
        let tokens =
          raw_tokens statement.text
          |> List.filter_map (fun token ->
                 let id = normalize token.raw token.kind in
                 if id = "" || not (enabled token.kind)
                    || (token.kind = "word" && String_set.mem id stop_words
                        && not (String_set.mem id protected))
                 then None
                 else Some (id, token.kind))
        in
        (statement, tokens))
      statements
  in
  let nodes, provenance =
    List.fold_left
      (fun (nodes, provenance) ((statement : statement), tokens) ->
        List.fold_left
          (fun (nodes, provenance) (id, kind) ->
            let count, existing_kind =
              Option.value ~default:(0, kind) (String_map.find_opt id nodes)
            in
            let statement_ids =
              Option.value ~default:String_set.empty (String_map.find_opt id provenance)
              |> String_set.add statement.id
            in
            ( String_map.add id (count + 1, existing_kind) nodes,
              String_map.add id statement_ids provenance ))
          (nodes, provenance) tokens)
      (String_map.empty, String_map.empty) statement_tokens
  in
  let window = Int.max 1 (Int.min 12 profile.window) in
  let edges =
    let add_edge edges left right =
      if String.equal left right then edges
      else
        let source, target = if String.compare left right <= 0 then (left, right) else (right, left) in
        let key = source ^ "\x1f" ^ target in
        let weight = Option.value ~default:0 (String_map.find_opt key edges) in
        String_map.add key (weight + 1) edges
    in
    List.fold_left
      (fun edges (_, tokens) ->
        let ids = Array.of_list (List.map fst tokens) in
        let result = ref edges in
        for left = 0 to Array.length ids - 1 do
          let upper = Int.min (Array.length ids - 1) (left + window) in
          for right = left + 1 to upper do
            result := add_edge !result ids.(left) ids.(right)
          done
        done;
        !result)
      String_map.empty statement_tokens
  in
  let typed_nodes =
    String_map.bindings nodes
    |> List.map (fun (id, (count, kind)) ->
           { id; label = id; kind; weight = float_of_int count })
  in
  let graph_nodes =
    List.map
      (fun (node : typed_node) ->
        Graph.
          {
            id = node.id;
            label = node.label;
            kind = node.kind;
            layer = "text";
            group = node.kind;
            detail = node.kind;
            weight = node.weight;
          })
      typed_nodes
  in
  let graph_edges =
    String_map.bindings edges
    |> List.map (fun (key, weight) ->
           match String.split_on_char '\x1f' key with
           | [ source; target ] ->
               Graph.{ source; target; relation = "coOccurs"; weight = float_of_int weight }
           | _ -> assert false)
  in
  let graph =
    Graph.normalize
      Graph.
        {
          id = "processed";
          title = "Processed statements";
          kind = "attributed-text";
          nodes = graph_nodes;
          edges = graph_edges;
        }
  in
  let node_statements =
    String_map.bindings provenance
    |> List.map (fun (id, ids) -> (id, String_set.elements ids))
  in
  let tags =
    statements
    |> List.concat_map (fun (statement : statement) ->
           statement.metadata
           |> List.map (fun (key, value) ->
                  { statement_id = statement.id; key = canonical key; value = canonical value }))
  in
  let digest_source =
    String.concat "\x1e"
      (effective_language
       :: List.map (fun node -> node.id ^ ":" ^ node.kind ^ ":" ^ string_of_float node.weight) typed_nodes
       @ List.map
           (fun edge -> edge.Graph.source ^ ">" ^ edge.target ^ ":" ^ string_of_float edge.weight)
           graph.edges)
  in
  {
    statements;
    graph;
    typed_nodes;
    node_statements;
    aliases;
    tags;
    effective_language;
    digest = Digest.to_hex (Digest.string digest_source);
  }

let has_node result id = List.exists (fun node -> String.equal node.id id) result.typed_nodes

let statement_ids_for_node result id =
  Option.value ~default:[] (List.assoc_opt id result.node_statements)
