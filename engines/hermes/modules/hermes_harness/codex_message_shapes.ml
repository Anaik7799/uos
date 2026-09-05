(* Codex Responses-API message shaping: candidate for model_routing.codex_runtime,
   faithful to frozen agent/codex_responses_adapter.py. Pure JSON transforms;
   list order only, no dict iteration. *)

let text_types = [ "text"; "input_text"; "output_text" ]
let image_types = [ "image_url"; "input_image" ]

(* Python str(x or "").strip().lower() over the corpus (ASCII-scoped). *)
let coerce_type = function
  | `String "" | `Null | `Bool false | `Int 0 -> ""
  | `Float f when f = 0.0 -> ""
  | `List [] | `Assoc [] -> ""
  | `String s -> String.lowercase_ascii (String.trim s)
  | `Bool true -> "true"
  | `Int n -> string_of_int n
  | _ -> ""

let ptype = function
  | `Assoc kv -> coerce_type (match List.assoc_opt "type" kv with Some v -> v | None -> `Null)
  | _ -> ""

let chat_content_to_responses_parts ~content ~role =
  let text_type = if role = "assistant" then "output_text" else "input_text" in
  match content with
  | `List parts ->
      let convert part =
        match part with
        | `String "" -> None
        | `String s -> Some (`Assoc [ ("type", `String text_type); ("text", `String s) ])
        | `Assoc kv ->
            let pt = ptype part in
            if List.mem pt text_types then
              match List.assoc_opt "text" kv with
              | Some (`String t) when t <> "" ->
                  Some (`Assoc [ ("type", `String text_type); ("text", `String t) ])
              | _ -> None
            else if List.mem pt image_types then begin
              let field k = match List.assoc_opt k kv with Some v -> v | None -> `Null in
              let image_ref = field "image_url" and part_detail = field "detail" in
              let url, detail =
                match image_ref with
                | `Assoc iref ->
                    let u = match List.assoc_opt "url" iref with Some v -> v | None -> `Null in
                    let d = match List.assoc_opt "detail" iref with Some v -> v | None -> part_detail in
                    (u, d)
                | _ -> (image_ref, part_detail)
              in
              match url with
              | `String us when us <> "" ->
                  let base = [ ("type", `String "input_image"); ("image_url", `String us) ] in
                  let detail_field =
                    match detail with
                    | `String ds when String.trim ds <> "" -> [ ("detail", `String (String.trim ds)) ]
                    | _ -> []
                  in
                  Some (`Assoc (base @ detail_field))
              | _ -> None
            end
            else None
        | _ -> None
      in
      `List (List.filter_map convert parts)
  | _ -> `List []

let normalize_responses_message_status value ~default =
  match value with
  | `String v ->
      let s = String.lowercase_ascii (String.trim v) in
      let s = String.map (fun c -> if c = '-' then '_' else c) s in
      let s = String.map (fun c -> if c = ' ' then '_' else c) s in
      if List.mem s [ "completed"; "incomplete"; "in_progress" ] then s else default
  | _ -> default

let summarize_user_message_for_log ~content ~sep =
  match content with
  | `Null -> ""
  | `String s -> s
  | `List parts ->
      let text_bits = ref [] and image_count = ref 0 in
      List.iter
        (fun part ->
          match part with
          | `String "" -> ()
          | `String s -> text_bits := s :: !text_bits
          | `Assoc kv ->
              let pt = ptype part in
              if List.mem pt text_types then (
                match List.assoc_opt "text" kv with
                | Some (`String t) when t <> "" -> text_bits := t :: !text_bits
                | _ -> ())
              else if List.mem pt image_types then incr image_count
          | _ -> ())
        parts;
      let summary = String.trim (String.concat sep (List.rev !text_bits)) in
      if !image_count > 0 then
        let note =
          Printf.sprintf "[%d image%s]" !image_count (if !image_count = 1 then "" else "s")
        in
        if summary = "" then note else note ^ " " ^ summary
      else summary
  | `Int n -> string_of_int n
  | `Bool b -> if b then "True" else "False"
  | _ -> ""
