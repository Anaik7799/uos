open Core
module Crdt = Sa_plan_crdt

(** Implements C3I rich-bundle formatting (HTML + Markdown). *)

let generate_markdown state ~title =
  let date = Time_float.to_string_abs (Time_float.now ()) ~zone:Time_float.Zone.utc in
  let header = sprintf "# %s\n*Generated: %s*\n\n## Tasks\n\n" title date in
  let task_line task =
    sprintf "- **[%s]** %s (`%s`) - %s\n" 
      task.Crdt.Task.id 
      task.Crdt.Task.title 
      (Crdt.Task_status.to_string task.Crdt.Task.status) 
      task.Crdt.Task.description
  in
  let lines = Map.data state |> List.map ~f:task_line |> String.concat ~sep:"" in
  header ^ lines

(* Element content is MARKUP, not a code fence. The bundle's task descriptions
   are cycle NOTES — arbitrary operator text — and both they and the title were
   spliced raw, which made every recorded note an injection into the published
   page. It was not hypothetical: a cycle note documenting the
   `--log-ooda <layer> <phase> <content>` signature put three unclosed tags into
   docs/journal/journal.html, and the document lint caught them as three Errors
   on a GENERATED artifact (where there is no ratchet, correctly). A note
   containing `</pre><script>` would have done considerably more than unbalance
   the page. *)
let escape_html value =
  String.concat_map value ~f:(function
    | '&' -> "&amp;"
    | '<' -> "&lt;"
    | '>' -> "&gt;"
    | '"' -> "&quot;"
    | '\'' -> "&#39;"
    | c -> String.of_char c)

let generate_html state ~title =
  let md = generate_markdown state ~title in
  (* Still a <pre> stub rather than a markdown renderer — but an ESCAPED one, so
     the stub is honest about what it shows instead of executing it. *)
  sprintf
    "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><title>%s</title></head><body><main><pre>%s</pre></main></body></html>"
    (escape_html title) (escape_html md)
