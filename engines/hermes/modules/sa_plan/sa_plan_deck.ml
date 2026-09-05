open Core
module Crdt = Sa_plan_crdt

(** Generates Marp-compatible Markdown for Slide Decks. *)

let header ~title ~date =
  sprintf "---\nmarp: true\ntheme: default\nclass: lead\npaginate: true\n---\n\n# %s\n### Generated: %s\n\n---\n\n" title date

let task_slide (task: Crdt.Task.t) =
  sprintf "## Task: %s\n**Status**: %s\n**ID**: `%s`\n\n%s\n\n---\n\n"
    task.title (Crdt.Task_status.to_string task.status) task.id task.description

let generate_deck state ~title =
  let date = Time_float.to_string_abs (Time_float.now ()) ~zone:Time_float.Zone.utc in
  let tasks = Map.data state in
  let slides = List.map tasks ~f:task_slide |> String.concat ~sep:"" in
  header ~title ~date ^ slides
