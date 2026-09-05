(* Gemini tool-parameter schema sanitization: candidate (first cut) for
   model_routing.gemini_adapter, faithful to frozen agent/gemini_schema.py
   sanitize_gemini_tool_parameters. Keep allowed keys in input order, recurse
   into properties/items/anyOf, stringify+dedupe integer/number/boolean enums,
   filter required against the node's properties. *)

let allowed =
  [ "type"; "format"; "title"; "description"; "nullable"; "enum"; "maxItems"; "minItems";
    "properties"; "required"; "minProperties"; "maxProperties"; "minLength"; "maxLength";
    "pattern"; "example"; "anyOf"; "propertyOrdering"; "default"; "items"; "minimum"; "maximum" ]

let rec sanitize (schema : Yojson.Safe.t) : Yojson.Safe.t =
  match schema with
  | `Assoc kvs ->
      let cleaned =
        List.filter_map
          (fun (key, value) ->
            if not (List.mem key allowed) then None
            else if key = "properties" then
              match value with
              | `Assoc props ->
                  Some
                    ( key,
                      `Assoc
                        (List.map
                           (fun (pk, pv) ->
                             (pk, match pv with `Assoc _ -> sanitize pv | _ -> `Assoc []))
                           props) )
              | _ -> None (* "properties" only if a dict *)
            else if key = "items" then Some (key, sanitize value)
            else if key = "anyOf" then
              match value with
              | `List items ->
                  Some
                    ( key,
                      `List
                        (List.filter_map
                           (function `Assoc _ as d -> Some (sanitize d) | _ -> None)
                           items) )
              | _ -> None (* "anyOf" only if a list *)
            else Some (key, value))
          kvs
      in
      cleaned |> enum_pass |> required_pass |> fun c -> `Assoc c
  | _ -> `Assoc []

and enum_pass cleaned =
  match (List.assoc_opt "enum" cleaned, List.assoc_opt "type" cleaned) with
  | Some (`List entries), Some (`String t)
    when List.mem t [ "integer"; "number"; "boolean" ] ->
      let mapped =
        List.filter_map
          (function
            | `String s -> Some s
            | `Bool b -> Some (if b then "true" else "false")
            | `Int n -> Some (string_of_int n)
            (* finite float via Python str() is out of the first-cut corpus (integer
               enums); dropped conservatively rather than mis-rendered. *)
            | _ -> None)
          entries
      in
      let deduped =
        List.fold_left (fun acc x -> if List.mem x acc then acc else acc @ [ x ]) [] mapped
      in
      List.filter_map
        (fun (k, v) ->
          if k = "enum" then
            if deduped = [] then None else Some (k, `List (List.map (fun s -> `String s) deduped))
          else Some (k, v))
        cleaned
  | _ -> cleaned

and required_pass cleaned =
  match List.assoc_opt "required" cleaned with
  | Some (`List names) ->
      let props =
        match List.assoc_opt "properties" cleaned with Some (`Assoc p) -> List.map fst p | _ -> []
      in
      let kept =
        List.filter_map
          (function `String n when List.mem n props -> Some (`String n) | _ -> None)
          names
      in
      List.filter_map
        (fun (k, v) ->
          if k = "required" then if kept = [] then None else Some (k, `List kept)
          else Some (k, v))
        cleaned
  | _ -> cleaned

let sanitize_tool_parameters parameters =
  match sanitize parameters with
  | `Assoc [] -> `Assoc [ ("type", `String "object"); ("properties", `Assoc []) ]
  | other -> other
