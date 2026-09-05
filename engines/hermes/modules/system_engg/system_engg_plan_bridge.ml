open Phase0_programme

let () =
  let args = Sys.argv |> Array.to_list |> List.tl in
  let apply = List.mem "--apply" args in
  let dry_run = List.mem "--dry-run" args || not apply in
  
  if dry_run then begin
    Printf.printf "Plan ID: system-engg/phase-0/v1\n";
    Printf.printf "Nodes: %d\n" (List.length tasks);
    exit 0
  end else begin
    let path = 
      let rec find_path = function
        | "--path" :: p :: _ -> p
        | _ :: rest -> find_path rest
        | [] -> failwith "Missing --path"
      in find_path args
    in
    if not (ready_to_apply ()) then begin
      Printf.eprintf "Error: Phase 0 decisions are not all approved.\n";
      exit 1
    end;
    let nodes = List.map to_plan_node tasks in
    match Sa_plan.Store.open_db path with
    | Error e -> Printf.eprintf "Failed to open DB: %s\n" e; exit 1
    | Ok db ->
      match Sa_plan.Store.register_plan db ~id:"system-engg/phase-0/v1" ~title:"Phase 0 Programme" ~nodes with
      | Ok () -> 
        Sa_plan.Store.close db;
        Printf.printf "Successfully applied plan to %s\n" path
      | Error e -> 
        Sa_plan.Store.close db;
        Printf.eprintf "Failed to apply plan: %s\n" e; exit 1
  end