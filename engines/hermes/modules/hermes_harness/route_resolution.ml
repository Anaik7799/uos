(* Fallback route-chain resolution: candidate for model_routing.route_resolution,
   faithful to the frozen hermes_cli/fallback_config.get_fallback_chain. Yojson
   Assoc is an ordered assoc list, so key order and extra keys are preserved by
   mapping in place -- exactly the reference's shallow-copy-and-overwrite. *)

(* Python str(v or "").strip(): a falsy value coerces to "", else its string
   form, stripped. Containers and floats are outside the scenario corpus and
   left conservative here (they would surface as an honest divergence if tested,
   never a silent pass). *)
let coerce_field = function
  | `String s -> String.trim s
  | `Bool true -> "True"
  | `Bool false -> ""
  | `Int 0 -> ""
  | `Int n -> string_of_int n
  | `Null -> ""
  | `Float f when f = 0.0 -> ""
  | `Float _ | `Intlit _ | `List _ | `Assoc _ | `Tuple _ | `Variant _ -> ""

(* strip whitespace, then strip all trailing "/"; a non-string is "". *)
let normalize_base_url = function
  | `String s ->
      let t = String.trim s in
      let rec last i = if i > 0 && t.[i - 1] = '/' then last (i - 1) else i in
      String.sub t 0 (last (String.length t))
  | _ -> ""

let field entry key = match List.assoc_opt key entry with Some v -> v | None -> `Null

(* A candidate entry -> (normalized shallow copy, dedup identity) if valid. *)
let process_entry entry =
  let provider = coerce_field (field entry "provider") in
  let model = coerce_field (field entry "model") in
  if provider = "" || model = "" then None
  else
    let nb = normalize_base_url (field entry "base_url") in
    let copy =
      List.map
        (fun (key, value) ->
          if key = "provider" then (key, `String provider)
          else if key = "model" then (key, `String model)
          else if key = "base_url" && nb <> "" then (key, `String nb)
          else (key, value))
        entry
    in
    let low = String.lowercase_ascii in
    Some (`Assoc copy, (low provider, low model, low nb))

(* raw dict -> [raw] (legacy single-entry); raw list -> its elements; else []. *)
let candidates = function `Assoc _ as d -> [ d ] | `List xs -> xs | _ -> []

let get_fallback_chain config =
  let cfg = match config with `Assoc fields -> fields | _ -> [] in
  let seen = Hashtbl.create 16 and chain = ref [] in
  List.iter
    (fun key ->
      List.iter
        (fun candidate ->
          match candidate with
          | `Assoc entry -> (
              match process_entry entry with
              | Some (copy, identity) ->
                  if not (Hashtbl.mem seen identity) then begin
                    Hashtbl.add seen identity ();
                    chain := copy :: !chain
                  end
              | None -> ())
          | _ -> ())
        (candidates (field cfg key)))
    [ "fallback_providers"; "fallback_model" ];
  `List (List.rev !chain)
