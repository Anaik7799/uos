let usage =
  "usage: render_evidence_import_plan SOURCE.sqlite3 TARGET.sqlite3"

let () =
  match Array.to_list Sys.argv with
  | [ _; source_path; target_path ] ->
      (match Evidence_import.analyze ~source_path ~target_path with
      | Error diagnostic ->
          prerr_endline ("evidence import planning refused: " ^ diagnostic);
          exit 1
      | Ok plan ->
          print_string (Evidence_import.render plan);
          exit (if Evidence_import.admissible plan then 0 else 2))
  | _ ->
      prerr_endline usage;
      exit 64
