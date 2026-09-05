module Graph = Graph_intelligence
module Ingest = Graph_ingest
module Store = Graph_store

type outcome = No_work | Finished of Store.job

let field name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let string_field ?default name json =
  match field name json with
  | Some (`String value) when String.trim value <> "" -> Ok (String.trim value)
  | _ -> (
      match default with Some value -> Ok value | None -> Error (name ^ " is required"))

let int_field ~default name json =
  match field name json with Some (`Int value) -> value | _ -> default

let valid_context_id id =
  let valid = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | ':' -> true
    | _ -> false
  in
  String.length id > 0 && String.length id <= 128 && String.for_all valid id

let load_context db id =
  if String.equal id "system" then Some (Store.load_system_graph db)
  else Store.load_graph db id

let import_text db args =
  match
    ( string_field "context_id" args,
      string_field ~default:"Imported text" "title" args,
      string_field "text" args )
  with
  | Error message, _, _ | _, Error message, _ | _, _, Error message -> Error message
  | Ok id, Ok title, Ok text when valid_context_id id ->
      if String.length text > 1_048_576 then Error "text exceeds 1 MiB"
      else
        let window = Int.max 1 (Int.min 12 (int_field ~default:4 "window" args)) in
        let source_uri =
          match string_field ~default:("inline:" ^ id) "source_uri" args with
          | Ok value -> value
          | Error _ -> "inline:" ^ id
        in
        let graph = Ingest.from_text ~window ~id ~title text in
        let digest = Store.save_text_graph db ~source_uri ~text graph in
        Ok
          (`Assoc
            [
              ("context_id", `String id);
              ("digest", `String digest);
              ("node_count", `Int (List.length graph.nodes));
              ("edge_count", `Int (List.length graph.edges));
              ("sentiment", `Float (Ingest.sentiment text));
            ])
  | Ok _, _, _ -> Error "context_id must use 1-128 letters, digits, '-', '_', or ':'"

let analyze db args =
  match string_field ~default:"system" "context_id" args with
  | Error message -> Error message
  | Ok id -> (
      match load_context db id with
      | None -> Error "graph context not found"
      | Some graph ->
          let digest = Store.save_graph db ~source_kind:"analysis" graph in
          let analytics = Graph.analyze graph in
          Ok
            (`Assoc
              [
                ("context_id", `String id);
                ("digest", `String digest);
                ("analytics", Graph.to_yojson ~analytics (Graph.bounded ~max_nodes:1500 graph));
              ]))

let compare db args =
  match (string_field "left_id" args, string_field "right_id" args) with
  | Ok left_id, Ok right_id -> (
      match (load_context db left_id, load_context db right_id) with
      | Some left, Some right -> Ok (Graph.compare left right |> Graph.comparison_to_yojson)
      | _ -> Error "one or both graph contexts were not found")
  | Error message, _ | _, Error message -> Error message

let export db args =
  match
    (string_field ~default:"system" "context_id" args, string_field ~default:"json" "format" args)
  with
  | Ok id, Ok format -> (
      match load_context db id with
      | None -> Error "graph context not found"
      | Some graph -> (
          match format with
          | "json" -> Ok (`Assoc [ ("format", `String format); ("content", Graph.to_yojson ~analytics:(Graph.analyze graph) graph) ])
          | "graphml" -> Ok (`Assoc [ ("format", `String format); ("content", `String (Graph.to_graphml graph)) ])
          | "dot" -> Ok (`Assoc [ ("format", `String format); ("content", `String (Graph.to_dot graph)) ])
          | _ -> Error "unsupported export format"))
  | Error message, _ | _, Error message -> Error message

let execute db (work : Store.work_item) =
  match work.job.command with
  | "import" -> import_text db work.args
  | "refresh" | "analyze" -> analyze db work.args
  | "compare" -> compare db work.args
  | "export" -> export db work.args
  | "generate" -> Error "provider-backed generation is not configured"
  | _ -> Error "unsupported command reached worker"

let run_one db =
  match Store.claim_next db with
  | None -> No_work
  | Some work ->
      let result =
        try execute db work
        with exn -> Error ("worker exception: " ^ Printexc.to_string exn)
      in
      (match Store.finish_job db ~id:work.job.id result with
      | Some job -> Finished job
      | None -> failwith "claimed graph job disappeared before completion")

let drain ?(limit = 100) db =
  let rec loop completed =
    if completed >= limit then completed
    else
      match run_one db with
      | No_work -> completed
      | Finished _ -> loop (completed + 1)
  in
  loop 0
