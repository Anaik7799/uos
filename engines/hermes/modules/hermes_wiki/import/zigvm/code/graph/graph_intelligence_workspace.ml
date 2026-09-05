type provider_state = Configured of string | Unavailable of string | Rate_limited of { provider : string; retry_after_seconds : int }
type evidence = { statement_id : string; text : string }
type retrieval_packet = { query : string; revision : int; filter_digest : string; node_ids : string list; evidence : evidence list }
type answer = { text : string; provider : string option; citations : string list }
type ontology = { entities : string list; relations : (string * string) list; categories : (string * string list) list; rules : string list }
type note_mode = Append | Replace
type note = { label : string; revision : int; body : string }
type provider = string -> (string, provider_state) Stdlib.result

let words value =
  value |> String.lowercase_ascii |> String.split_on_char ' '
  |> List.map String.trim |> List.filter (fun value -> value <> "")

let contains haystack needle =
  let haystack = String.lowercase_ascii haystack and needle = String.lowercase_ascii needle in
  let lh = String.length haystack and ln = String.length needle in
  let rec loop index = index + ln <= lh && (String.sub haystack index ln = needle || loop (index + 1)) in
  ln = 0 || loop 0

let topic_overview report =
  match report.Graph_analytics.topics with
  | [] -> "No topics are observable for this revision."
  | topics ->
      topics
      |> List.map (fun (topic : Graph_analytics.topic) -> Printf.sprintf "%s (%.1f%%): %s" topic.label (100. *. topic.influence)
             (String.concat ", " topic.node_ids))
      |> String.concat "\n"

let focused_summary ~node_ids report =
  let selected = List.sort_uniq String.compare node_ids in
  let excerpts =
    report.Graph_analytics.excerpts
    |> List.filter (fun (excerpt : Graph_analytics.excerpt) -> List.exists (fun id -> List.mem id excerpt.node_ids) selected)
  in
  match excerpts with
  | [] -> "No source excerpts match the selected concepts."
  | values -> values |> List.map (fun (excerpt : Graph_analytics.excerpt) -> "[" ^ excerpt.statement_id ^ "] " ^ excerpt.text) |> String.concat "\n"

let gap_ideation report =
  report.Graph_analytics.gaps
  |> List.map (fun (gap : Graph_intelligence.gap) -> Printf.sprintf "What evidence could connect %s and %s (gap %.3f)?" gap.left_node gap.right_node gap.score)

let retrieve ~query report =
  let terms = words query in
  let excerpts =
    report.Graph_analytics.excerpts
    |> List.filter (fun (excerpt : Graph_analytics.excerpt) ->
           terms = [] || List.exists (fun term -> contains excerpt.text term || List.exists (fun node -> contains node term) excerpt.node_ids) terms)
  in
  let excerpts = if excerpts = [] then List.filteri (fun index _ -> index < 3) report.excerpts else excerpts in
  { query; revision = report.revision; filter_digest = report.filter_digest;
    node_ids = excerpts |> List.concat_map (fun (excerpt : Graph_analytics.excerpt) -> excerpt.node_ids) |> List.sort_uniq String.compare;
    evidence = List.map (fun (excerpt : Graph_analytics.excerpt) -> { statement_id = excerpt.statement_id; text = excerpt.text }) excerpts }

let packet_to_yojson (packet : retrieval_packet) =
  `Assoc [ ("query", `String packet.query); ("revision", `Int packet.revision);
           ("filter_digest", `String packet.filter_digest);
           ("node_ids", `List (List.map (fun value -> `String value) packet.node_ids));
           ("evidence", `List (List.map (fun item -> `Assoc [ ("statement_id", `String item.statement_id); ("text", `String item.text) ]) packet.evidence)) ]

let augment_prompt ~prompt (packet : retrieval_packet) =
  prompt ^ "\n\nGraph evidence (revision " ^ string_of_int packet.revision ^ ", filter " ^ packet.filter_digest ^ "):\n"
  ^ (packet.evidence |> List.map (fun item -> "- [" ^ item.statement_id ^ "] " ^ item.text) |> String.concat "\n")

let local_answer (packet : retrieval_packet) =
  match packet.evidence with
  | [] -> "No source evidence matched the question."
  | values ->
      "The graph-grounded evidence contains " ^ string_of_int (List.length values)
      ^ " matching source excerpt(s): "
      ^ (values |> List.map (fun item -> "[" ^ item.statement_id ^ "] " ^ item.text) |> String.concat " ")

let chat ?provider (packet : retrieval_packet) =
  let citations = List.map (fun item -> item.statement_id) packet.evidence in
  match provider with
  | None -> Ok { text = local_answer packet; provider = None; citations }
  | Some run ->
      (match run (augment_prompt ~prompt:packet.query packet) with
      | Ok text -> Ok { text; provider = Some "configured"; citations }
      | Error state -> Error state)

let classify report =
  let entities =
    report.Graph_analytics.influential_concepts |> List.map (fun (ranked : Graph_analytics.ranked) -> ranked.node_id)
    |> List.sort_uniq String.compare
  in
  let relations = report.relations |> List.map (fun (relation : Graph_analytics.relation) -> relation.source, relation.target) in
  let categories = report.topics |> List.map (fun (topic : Graph_analytics.topic) -> topic.label, topic.node_ids) in
  { entities; relations; categories;
    rules = [ "every relation endpoint belongs to the entity carrier";
              "every category member is revision-scoped";
              "source excerpts remain the evidence authority" ] }

let ontology_to_yojson ontology =
  `Assoc [ ("entities", `List (List.map (fun value -> `String value) ontology.entities));
           ("relations", `List (List.map (fun (source, target) -> `List [ `String source; `String target ]) ontology.relations));
           ("categories", `List (List.map (fun (label, values) -> `Assoc [ ("label", `String label); ("members", `List (List.map (fun value -> `String value) values)) ]) ontology.categories));
           ("rules", `List (List.map (fun value -> `String value) ontology.rules)) ]

let generate_note ~mode ~existing ~label report =
  let generated = "# " ^ label ^ "\n" ^ topic_overview report in
  let body = match mode with Append when String.trim existing <> "" -> existing ^ "\n\n" ^ generated | Append | Replace -> generated in
  { label; revision = report.revision; body }

let select_provider states =
  match List.find_opt (function Configured _ -> true | _ -> false) states with
  | Some (Configured provider) -> Ok provider
  | Some _ | None ->
      (match List.find_opt (function Rate_limited _ -> true | _ -> false) states with
      | Some state -> Error state
      | None -> Error (Unavailable "no_provider_configured"))
