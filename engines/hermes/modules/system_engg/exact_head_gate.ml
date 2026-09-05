let run_command cmd =
  let l = Unix.open_process_in cmd in
  let res = ref [] in
  try
    while true do
      res := input_line l :: !res
    done;
    assert false
  with End_of_file ->
    let status = Unix.close_process_in l in
    (status, List.rev !res)

let is_git_clean repo_path =
  let cmd = Printf.sprintf "git -C %s status --porcelain" repo_path in
  match run_command cmd with
  | Unix.WEXITED 0, lines -> Ok (lines = [])
  | Unix.WEXITED code, _ -> Error (Printf.sprintf "git status exited with code %d" code)
  | _ -> Error "git status process failed"

let get_head_sha repo_path =
  let cmd = Printf.sprintf "git -C %s rev-parse HEAD" repo_path in
  match run_command cmd with
  | Unix.WEXITED 0, [sha] -> Ok (String.trim sha)
  | Unix.WEXITED code, _ -> Error (Printf.sprintf "git rev-parse exited with code %d" code)
  | _ -> Error "git rev-parse process failed"

let write_receipt state_root sha =
  let dir = Filename.concat state_root sha in
  (try if not (Sys.file_exists dir) then Unix.mkdir dir 0o755 with _ -> ());
  let path = Filename.concat dir "phase-1.json" in
  let content = Printf.sprintf "{\n  \"sha\": \"%s\",\n  \"status\": \"passed\",\n  \"timestamp_ns\": %Ld\n}\n" sha (Unix.gettimeofday () *. 1e9 |> Int64.of_float) in
  try
    let ch = open_out path in
    output_string ch content;
    close_out ch;
    Ok ()
  with exn -> Error (Printexc.to_string exn)

let run_gate ~repo_path ~state_root =
  match is_git_clean repo_path with
  | Error e -> Error e
  | Ok false -> Error "Git worktree is dirty"
  | Ok true ->
      match get_head_sha repo_path with
      | Error e -> Error e
      | Ok sha ->
          match write_receipt state_root sha with
          | Error e -> Error e
          | Ok () -> Ok sha