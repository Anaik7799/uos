(* G-DIAGRAM: the corpus-wide SC-DIAGRAM-001 report.

   Exit status is deliberate. Only genuine FAILURES (mermaid with no ASCII
   diagram, a table standing in for one, or arrow-list edge sets that
   disagree) set a nonzero exit. `Unverifiable_box_art` is counted and
   printed but does NOT fail the gate, because 58 of the 59 documents
   carrying a mermaid block use box art: failing them would break every
   concurrent session's build to report a mandate/corpus mismatch that is
   a sovereign decision, not a defect in any one document. The count is
   the honest measure of how much of INV-JRN-06 is unverified, and it is
   printed on every run so it cannot be forgotten. *)

let read path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let rec walk acc dir =
  match Sys.readdir dir with
  | entries ->
    Array.fold_left
      (fun acc e ->
         let p = Filename.concat dir e in
         if e = "" || e.[0] = '.' then acc
         else if Sys.is_directory p then walk acc p
         else if Filename.check_suffix e ".md" then p :: acc
         else acc)
      acc entries
  | exception _ -> acc

let () =
  let roots =
    match Array.to_list Sys.argv with
    | _ :: [] -> [ "docs"; "contracts" ]
    | _ :: rest -> rest
    | [] -> [ "docs" ]
  in
  let files =
    List.concat_map
      (fun r ->
         if not (Sys.file_exists r) then []
         else if Sys.is_directory r then walk [] r
         else [ r ])
      roots
  in
  let files = List.sort String.compare files in
  let fails = ref 0 and unver = ref 0 and pass = ref 0 and none = ref 0 in
  List.iter
    (fun f ->
       match Diagram_parity.check (read f) with
       | Diagram_parity.No_mermaid -> incr none
       | v ->
         if Diagram_parity.is_failure v then begin
           incr fails;
           Printf.printf "FAIL      %s\n            %s\n" f (Diagram_parity.describe v)
         end
         else if Diagram_parity.is_passing v then begin
           incr pass; Printf.printf "PASS      %s\n" f
         end
         else begin
           incr unver;
           Printf.printf "UNVERIFIED %s\n" f
         end)
    files;
  Printf.printf
    "\nG-DIAGRAM over %d markdown files:\n  \
     %d verified (edge sets compared)\n  \
     %d UNVERIFIED (box-art ASCII; INV-JRN-06 topology not mechanically checkable)\n  \
     %d FAILED\n  %d carry no mermaid diagram\n"
    (List.length files) !pass !unver !fails !none;
  if !fails > 0 then begin
    Printf.printf
      "\nG-DIAGRAM: HOLD -- %d document(s) fail SC-DIAGRAM-001.\n" !fails;
    exit 1
  end
  else
    Printf.printf
      "\nG-DIAGRAM: PASS on the checkable subset. This is NOT a claim that \
       INV-JRN-06 holds: %d document(s) remain unverified.\n" !unver
