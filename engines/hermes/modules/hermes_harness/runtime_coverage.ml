(* Runtime anchor coverage: which capability source anchors are executed when the
   frozen reference runs a scenario. An honest coverage meter (the zigvm framing):
   covered/total/percentage, no fabrication, no vacuous 100% on an empty set. An
   anchor is covered iff its file is in the executed set the tracer recorded. *)

type anchor_status = { anchor : string; covered : bool }
type summary = { covered : int; total : int; statuses : anchor_status list }

let coverage ~executed ~anchors =
  let executed_set = List.sort_uniq compare executed in
  let statuses =
    anchors
    |> List.sort_uniq compare
    |> List.map (fun anchor -> { anchor; covered = List.mem anchor executed_set })
  in
  { covered = List.length (List.filter (fun (s : anchor_status) -> s.covered) statuses);
    total = List.length statuses;
    statuses }

let percent summary =
  if summary.total = 0 then 0 else summary.covered * 100 / summary.total

let describe summary =
  Printf.sprintf "%d/%d anchors executed (%d%%)" summary.covered summary.total (percent summary)
