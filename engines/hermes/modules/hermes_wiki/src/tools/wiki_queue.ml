(* The work queue: what is ACTIONABLE now, in the register's own priority
   order. R18 says recall before starting; this is the recall for "what
   should I do next", and it exists because `next ()` shows only the head
   and the head is sometimes a recorded NO-GO you must skip past.

   Read-only. Priority is 3*criticality + 2*utility + gates, and
   `actionable` means every gate this row waits on is already Built —
   which is NOT the same as the row's raw `Blocked` label. Priority is
   not permission: a NO-GO row can still sort first. *)

let usage () =
  prerr_endline "usage: wiki_queue [N]   (default 15)";
  exit 2

let () =
  let n =
    match List.tl (Array.to_list Sys.argv) with
    | [] -> 15
    | [ a ] -> ( match int_of_string_opt a with Some v when v > 0 -> v | _ -> usage ())
    | _ -> usage ()
  in
  let rows = Feature_register.prioritized () in
  if rows = [] then begin
    prerr_endline
      "[LX/control-plane control] REFUSED: no actionable rows derived — the register\n\
      \  would have to be empty for that to be true, so this is a defect, not a finish";
    exit 1
  end;
  Printf.printf "%d actionable row(s); top %d by priority:\n" (List.length rows)
    (min n (List.length rows));
  rows
  |> List.filteri (fun i _ -> i < n)
  |> List.iter (fun (f : Feature_register.feature) ->
         Printf.printf "  %-10s p%-3d %-14s %s\n" f.Feature_register.id
           (Feature_register.priority f)
           (Feature_register.area_name f.Feature_register.area)
           f.Feature_register.name)
