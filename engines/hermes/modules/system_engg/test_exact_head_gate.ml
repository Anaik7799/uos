let check name f =
  match f () with
  | true -> Printf.printf "PASS %s\n" name; true
  | false -> Printf.printf "FAIL %s\n" name; false
  | exception exn -> Printf.printf "FAIL %s (%s)\n" name (Printexc.to_string exn); false

let temp_directory () =
  let path = Filename.temp_file "exact-head-git-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Array.iter (fun name -> remove_tree (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path
    end
    else Sys.remove path

let () =
  let p = ref 0 and f = ref 0 in
  let run name fn = if check name fn then incr p else incr f in

  let temp_dir = temp_directory () in
  
  let run_cmd cmd =
    Sys.command
      (Printf.sprintf "git -C %s %s > /dev/null 2>&1" (Filename.quote temp_dir) cmd)
  in
  let _ = run_cmd "init" in
  let _ = run_cmd "config user.name 'Test'" in
  let _ = run_cmd "config user.email 'test@test.com'" in

  run "is_git_clean on empty new repo is clean or fails" (fun () ->
    match Exact_head_gate.is_git_clean temp_dir with
    | Ok true | Error _ -> true
    | _ -> false
  );

  (* Commit a file to make it clean *)
  let ch = open_out (Filename.concat temp_dir "a.txt") in
  output_string ch "hello";
  close_out ch;
  let _ = run_cmd "add a.txt" in
  let _ = run_cmd "commit -m 'Initial'" in

  run "is_git_clean is true on clean committed repo" (fun () ->
    match Exact_head_gate.is_git_clean temp_dir with
    | Ok true -> true
    | _ -> false
  );

  run "get_head_sha returns valid sha" (fun () ->
    match Exact_head_gate.get_head_sha temp_dir with
    | Ok sha -> String.length sha = 40
    | _ -> false
  );

  (* Make it dirty *)
  let ch = open_out (Filename.concat temp_dir "b.txt") in
  output_string ch "dirty";
  close_out ch;

  run "is_git_clean is false on dirty repo" (fun () ->
    match Exact_head_gate.is_git_clean temp_dir with
    | Ok false -> true
    | _ -> false
  );

  remove_tree temp_dir;

  Printf.printf "test_exact_head_gate: %d passed, %d failed\n" !p !f;
  let self = Suite_telemetry.observe ~suite:"test_exact_head_gate" ~passed:!p ~failed:!f ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.agent_time_hook; Stanza.run_swarm_bridge_programme ]);
  exit (Suite_telemetry.exit_code self)
