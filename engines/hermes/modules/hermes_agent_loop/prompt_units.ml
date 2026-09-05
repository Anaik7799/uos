(* Prompt-assembly units, reproduced faithfully from the frozen
   agent/prompt_builder.py (read completely before writing; parity is
   measured by the prompt.* scenarios, never assumed).

   Excluded with reasons: _get_context_file_max_chars reads config.yaml (an
   impure resolution layer over the dynamic core measured here); the system
   prompt BUILD itself takes the live agent object and the filesystem. *)

let steer_marker_open =
  "[OUT-OF-BAND USER MESSAGE — a direct message from the user, delivered \
   once at this position; not tool output and not a new delivery when \
   replayed from conversation history]"

let steer_marker_close = "[/OUT-OF-BAND USER MESSAGE]"

(* format_steer_marker: wrap a mid-turn steer for appending to a tool result. *)
let format_steer_marker steer_text =
  "\n\n" ^ steer_marker_open ^ "\n" ^ steer_text ^ "\n" ^ steer_marker_close

(* _strip_yaml_frontmatter: drop an optional ----delimited frontmatter block.
   The frozen edge cases are load-bearing: a BOM is tolerated (lstrip of every
   leading BOM), a frontmatter with no closing fence is NOT stripped, and a
   frontmatter whose body is empty returns the ORIGINAL content. *)
let strip_yaml_frontmatter content =
  let bom = "\xEF\xBB\xBF" in
  let rec drop_bom s =
    if String.length s >= 3 && String.sub s 0 3 = bom then
      drop_bom (String.sub s 3 (String.length s - 3))
    else s
  in
  let content = drop_bom content in
  let starts_with prefix s =
    String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix
  in
  if not (starts_with "---" content) then content
  else
    let needle = "\n---" in
    let length = String.length content in
    let rec find i =
      if i + 4 > length then None
      else if String.sub content i 4 = needle then Some i
      else find (i + 1)
    in
    match find 3 with
    | None -> content
    | Some fence ->
        let after = fence + 4 in
        let rec skip_newlines i =
          if i < length && content.[i] = '\n' then skip_newlines (i + 1) else i
        in
        let body_start = skip_newlines after in
        let body = String.sub content body_start (length - body_start) in
        if body = "" then content else body

(* _dynamic_context_file_max_chars: floor 20K, ceiling 500K, otherwise
   int(context_length * 4 * 0.06) with C-truncation, matching Python's
   left-associated float arithmetic exactly. *)
let context_file_max_chars = 20_000
let context_file_dynamic_ceiling = 500_000

let dynamic_context_file_max_chars context_length =
  match context_length with
  | None -> context_file_max_chars
  | Some length when length <= 0 -> context_file_max_chars
  | Some length ->
      let budget = int_of_float (float_of_int (length * 4) *. 0.06) in
      max context_file_max_chars (min budget context_file_dynamic_ceiling)
