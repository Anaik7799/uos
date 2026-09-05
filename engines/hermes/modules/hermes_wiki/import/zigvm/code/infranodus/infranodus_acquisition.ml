type source_kind =
  | Document | Spreadsheet | Batch | Web | Search | Youtube | Social
  | Knowledge_notes | Graph_network | Api

type provider_state =
  | Configured
  | Unavailable of string
  | Rate_limited of { retry_after_seconds : int }

type request = {
  id : string;
  kind : source_kind;
  locator : string option;
  content_type : string;
  content : string;
  metadata : (string * string) list;
}

type provider_payload = { body : string; content_type : string; metadata : (string * string) list; usage : int }
type progress = { completed : int; total : int; truncated : bool; retry_after_seconds : int option; usage : int }
type provenance = { request_id : string; source_kind : source_kind; locator : string option; content_type : string; metadata : (string * string) list }
type result = { statements : Graph_processing.statement list; processed : Graph_processing.result; provenance : provenance list; progress : progress }
type provider = request -> (provider_payload, provider_state) Stdlib.result

let source_kind_name = function
  | Document -> "document" | Spreadsheet -> "spreadsheet" | Batch -> "batch"
  | Web -> "web" | Search -> "search" | Youtube -> "youtube"
  | Social -> "social" | Knowledge_notes -> "knowledge-notes"
  | Graph_network -> "graph-network" | Api -> "api"

let request ~id ~kind ?locator ?(metadata = []) ~content_type content =
  { id = String.trim id; kind; locator; content_type = String.lowercase_ascii (String.trim content_type); content; metadata }

let requires_provider = function Web | Search | Youtube | Social -> true | _ -> false

let split_lines value =
  value |> String.split_on_char '\n' |> List.map String.trim
  |> List.filter (fun value -> value <> "")

let json_texts body =
  let rec collect acc = function
    | `String value -> if String.trim value = "" then acc else value :: acc
    | `List values -> List.fold_left collect acc values
    | `Assoc fields -> List.fold_left (fun acc (_, value) -> collect acc value) acc fields
    | `Null | `Bool _ | `Int _ | `Intlit _ | `Float _ | `Tuple _ | `Variant _ -> acc
  in
  match Yojson.Safe.from_string body with
  | json -> List.rev (collect [] json)
  | exception Yojson.Json_error _ -> []

let csv_texts body =
  match split_lines body with
  | [] -> []
  | _header :: rows ->
      List.filter_map
        (fun row -> match String.split_on_char ',' row with value :: _ when String.trim value <> "" -> Some (String.trim value) | _ -> None)
        rows

let local_texts request =
  match request.kind, request.content_type with
  | Spreadsheet, ("text/csv" | "application/csv") -> csv_texts request.content
  | Document, "application/json" | Api, "application/json" -> json_texts request.content
  | Document, "application/pdf" -> []
  | Graph_network, _ -> split_lines request.content
  | Document, _ | Spreadsheet, _ | Batch, _ | Knowledge_notes, _ | Api, _ -> split_lines request.content
  | Web, _ | Search, _ | Youtube, _ | Social, _ -> []

let acquire ?provider ?(profile = Graph_processing.default_profile) requests =
  let total = List.length requests in
  let rec loop statements provenance usage = function
    | [] ->
        let statements = List.rev statements in
        Ok { statements; processed = Graph_processing.process profile statements;
             provenance = List.rev provenance;
             progress = { completed = total; total; truncated = false; retry_after_seconds = None; usage } }
    | request :: rest ->
        if request.id = "" then Error (Unavailable "blank_request_id")
        else
          let needs_provider = requires_provider request.kind || (request.kind = Document && request.content_type = "application/pdf") in
          let payload =
            if needs_provider then
              match provider with None -> Error (Unavailable (source_kind_name request.kind ^ "_provider_not_configured")) | Some run -> run request
            else Ok { body = request.content; content_type = request.content_type; metadata = request.metadata; usage = 0 }
          in
          match payload with
          | Error state -> Error state
          | Ok payload ->
              let effective = { request with content = payload.body; content_type = payload.content_type; metadata = request.metadata @ payload.metadata } in
              let texts =
                if needs_provider && request.kind <> Document then split_lines payload.body
                else local_texts effective
              in
              if texts = [] then Error (Unavailable (source_kind_name request.kind ^ "_empty_or_unsupported"))
              else
                let items =
                  List.mapi
                    (fun ordinal text ->
                      Graph_processing.statement ~id:(Printf.sprintf "%s-%d" request.id (ordinal + 1))
                        ~source_id:request.id ~ordinal ~metadata:effective.metadata text)
                    texts
                in
                let provenance = { request_id = request.id; source_kind = request.kind; locator = request.locator;
                                   content_type = payload.content_type; metadata = effective.metadata } :: provenance in
                loop (List.rev_append items statements) provenance (usage + payload.usage) rest
  in
  loop [] [] 0 requests

let to_yojson result =
  `Assoc
    [ ("statements", `Int (List.length result.statements));
      ("graph", Graph_intelligence.to_yojson result.processed.graph);
      ("processing_digest", `String result.processed.digest);
      ("progress", `Assoc [ ("completed", `Int result.progress.completed); ("total", `Int result.progress.total);
                              ("truncated", `Bool result.progress.truncated); ("usage", `Int result.progress.usage);
                              ("retry_after_seconds", match result.progress.retry_after_seconds with None -> `Null | Some value -> `Int value) ]);
      ("provenance", `List (List.map (fun item -> `Assoc [ ("request_id", `String item.request_id);
          ("source_kind", `String (source_kind_name item.source_kind));
          ("locator", match item.locator with None -> `Null | Some value -> `String value);
          ("content_type", `String item.content_type);
          ("metadata", `Assoc (List.map (fun (key, value) -> key, `String value) item.metadata)) ]) result.provenance)) ]
