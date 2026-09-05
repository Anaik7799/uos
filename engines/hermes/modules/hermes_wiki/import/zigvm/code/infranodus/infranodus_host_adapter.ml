type host = Browser | Obsidian | Ide | N8n
type payload = { host : host; external_id : string; title : string; body : string; locator : string option; tags : string list }

let host_name = function Browser -> "browser" | Obsidian -> "obsidian" | Ide -> "ide" | N8n -> "n8n"

let kind = function
  | Browser -> Infranodus_acquisition.Web
  | Obsidian -> Infranodus_acquisition.Knowledge_notes
  | Ide -> Infranodus_acquisition.Document
  | N8n -> Infranodus_acquisition.Api

let content_type = function
  | Browser -> "text/html" | Obsidian -> "text/markdown"
  | Ide -> "text/plain" | N8n -> "application/json"

let to_request payload =
  let id = String.trim payload.external_id and body = String.trim payload.body in
  if id = "" then Error "external_id_required"
  else if body = "" && payload.host <> Browser then Error "body_required"
  else
    Ok (Infranodus_acquisition.request ~id ~kind:(kind payload.host) ?locator:payload.locator
          ~metadata:([ ("host", host_name payload.host); ("title", String.trim payload.title) ]
                     @ List.map (fun tag -> "tag", tag) payload.tags)
          ~content_type:(content_type payload.host) payload.body)

let to_yojson payload =
  `Assoc [ ("host", `String (host_name payload.host)); ("external_id", `String payload.external_id);
           ("title", `String payload.title); ("body", `String payload.body);
           ("locator", match payload.locator with None -> `Null | Some value -> `String value);
           ("tags", `List (List.map (fun value -> `String value) payload.tags)) ]

let of_yojson = function
  | `Assoc fields ->
      let string name = match List.assoc_opt name fields with Some (`String value) -> Some value | _ -> None in
      let host = match string "host" with Some "browser" -> Some Browser | Some "obsidian" -> Some Obsidian | Some "ide" -> Some Ide | Some "n8n" -> Some N8n | _ -> None in
      (match host, string "external_id", string "title", string "body" with
      | Some host, Some external_id, Some title, Some body ->
          let locator = string "locator" in
          let tags = match List.assoc_opt "tags" fields with Some (`List values) -> List.filter_map (function `String value -> Some value | _ -> None) values | _ -> [] in
          Ok { host; external_id; title; body; locator; tags }
      | _ -> Error "invalid_host_payload")
  | _ -> Error "host_payload_object_required"
