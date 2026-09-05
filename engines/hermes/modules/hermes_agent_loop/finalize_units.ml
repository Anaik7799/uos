(* Turn-finalization units, reproduced faithfully from the frozen
   agent/turn_finalizer.py, agent/turn_summary.py and
   agent/message_content.py (each read completely before writing; parity is
   measured by the finalize.* scenarios, never assumed). *)

let field name = function `Assoc fields -> List.assoc_opt name fields | _ -> None

let truthy = function
  | `Null | `Bool false | `String "" | `List [] | `Assoc [] | `Int 0 | `Intlit "0" -> false
  | `Float f -> f <> 0.0
  | _ -> true

(* message_content._text_from_part / flatten_message_text, for the JSON-shaped
   domain the scenarios exercise (string, part list, null). *)
let non_text_part_types = [ "image"; "image_url"; "input_image"; "audio"; "input_audio" ]
let text_keys = [ "text"; "content"; "input_text"; "output_text"; "summary_text" ]

let text_from_part part =
  match part with
  | `Null -> ""
  | `String text -> text
  | `Assoc _ ->
      let part_type =
        match field "type" part with
        | Some (`String t) -> String.lowercase_ascii (String.trim t)
        | _ -> ""
      in
      if List.mem part_type non_text_part_types then ""
      else
        let rec first = function
          | [] -> ""
          | key :: rest -> (
              match field key part with Some (`String text) -> text | _ -> first rest)
        in
        first text_keys
  | _ -> ""

let flatten_message_text content =
  match content with
  | `Null -> ""
  | `String text -> text
  | `List parts ->
      String.concat "\n"
        (List.filter (fun chunk -> chunk <> "") (List.map text_from_part parts))
  | other -> text_from_part other

(* turn_finalizer._is_pure_tool_call_tail: an assistant row with tool_calls
   but no visible text of its own. *)
let is_pure_tool_call_tail message =
  match field "tool_calls" message with
  | Some value when truthy value ->
      String.trim
        (flatten_message_text
           (match field "content" message with Some content -> content | None -> `Null))
      = ""
  | _ -> false

(* turn_finalizer._drop_verification_continuation_scaffolding: strip the
   synthetic verification nudges, keep everything else (including non-dict
   rows). *)
let verification_continuation_flags =
  [ "_verification_stop_synthetic"; "_pre_verify_synthetic" ]

let drop_verification_continuation_scaffolding messages =
  List.filter
    (fun message ->
      match message with
      | `Assoc _ ->
          not
            (List.exists
               (fun flag ->
                 match field flag message with Some value -> truthy value | None -> false)
               verification_continuation_flags)
      | _ -> true)
    messages

(* turn_summary._count_diff_lines: unified-diff adds/removes, headers
   excluded. The frozen splitlines is applied to \n-separated text in this
   domain. *)
let count_diff_lines diff =
  let starts_with prefix line =
    String.length line >= String.length prefix
    && String.sub line 0 (String.length prefix) = prefix
  in
  List.fold_left
    (fun (added, removed) line ->
      if starts_with "+++" line || starts_with "---" line then (added, removed)
      else if starts_with "+" line then (added + 1, removed)
      else if starts_with "-" line then (added, removed + 1)
      else (added, removed))
    (0, 0)
    (String.split_on_char '\n' diff)

(* turn_summary.format_elapsed: "12.4s" under a minute, "2m05s" above.
   Python's round() is banker's rounding; reproduced exactly. *)
let round_half_even value =
  let floor_value = Float.of_int (int_of_float (Float.floor value)) in
  let fraction = value -. floor_value in
  if fraction > 0.5 then floor_value +. 1.0
  else if fraction < 0.5 then floor_value
  else if Float.rem floor_value 2.0 = 0.0 then floor_value
  else floor_value +. 1.0

let format_elapsed seconds =
  let seconds = if seconds < 0.0 then 0.0 else seconds in
  if seconds < 60.0 then Printf.sprintf "%.1fs" seconds
  else
    let total = int_of_float (round_half_even seconds) in
    Printf.sprintf "%dm%02ds" (total / 60) (total mod 60)

(* turn_summary._pluralize: "1 file" / "3 files" from the plural form. *)
let pluralize count plural_noun =
  if count = 1 then
    let n = String.length plural_noun in
    let ends_with suffix =
      let s = String.length suffix in
      n >= s && String.sub plural_noun (n - s) s = suffix
    in
    let singular =
      if ends_with "ies" then String.sub plural_noun 0 (n - 3) ^ "y"
      else if ends_with "ses" then String.sub plural_noun 0 (n - 2)
      else if ends_with "s" then String.sub plural_noun 0 (n - 1)
      else plural_noun
    in
    "1 " ^ singular
  else Printf.sprintf "%d %s" count plural_noun
