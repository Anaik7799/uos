let () =
  let args = Sys.argv |> Array.to_list |> List.tl in
  let phase = 
    let rec find_phase = function
      | "--phase" :: p :: _ -> p
      | _ :: rest -> find_phase rest
      | [] -> "1"
    in find_phase args
  in
  let state_root = 
    let rec find_root = function
      | "--state-root" :: r :: _ -> r
      | _ :: rest -> find_root rest
      | [] -> "state/system_engg/receipts"
    in find_root args
  in
  match Exact_head_gate.run_gate ~repo_path:"." ~state_root with
  | Ok sha -> Printf.printf "Successfully minted receipt for phase %s at head SHA %s\n" phase sha
  | Error e -> Printf.eprintf "Gate failed: %s\n" e; exit 1