module J = Yojson.Safe
let receipt = "/tmp/ev98-health-direct-projection-native-20260909-1125.json"
let beam = "/tmp/ev98-health-direct-projection-1124/ebin/ev98_health_projection_runner.beam"
let digest = "5b420b5e4fea8fd106fcce3403efc8173ec0a9a90818e0c0e27d8b64906025dc"
let exe = Filename.dirname (Unix.realpath Sys.argv.(0)) ^ "/ev98_health_projection_verify.exe"
let replace key value = function
  | `Assoc fields -> `Assoc ((key, value) :: List.remove_assoc key fields)
  | _ -> failwith "fixture object"
let write path json =
  let out = open_out_bin path in output_string out (J.to_string json); close_out out
let rejects name json =
  let path = Filename.temp_file ("ev98-" ^ name) ".json" in
  write path json;
  let pid = Unix.create_process exe [|exe; path; beam; digest|] Unix.stdin Unix.stdout Unix.stderr in
  let _, status = Unix.waitpid [] pid in
  match status with Unix.WEXITED 0 -> failwith ("accepted " ^ name) | _ -> Printf.printf "PASS %s\n%!" name
let () =
  let base = J.from_file receipt in
  rejects "nonzero_exit" (replace "exit_code" (`Int 1) base);
  rejects "failure_reason" (replace "failure" (`String "timeout") base);
  rejects "wrong_termination" (replace "child_termination" (`Assoc ["kind", `String "SIGNALED"]) base);
  rejects "wrong_digest" (replace "output_sha256" (`String "00") base);
  let duplicate = Filename.temp_file "ev98-duplicate" ".json" in
  let rendered = J.to_string base in
  let out = open_out_bin duplicate in
  output_string out (String.sub rendered 0 (String.length rendered - 1) ^ ",\"exit_code\":1}"); close_out out;
  let pid = Unix.create_process exe [|exe; duplicate; beam; digest|] Unix.stdin Unix.stdout Unix.stderr in
  (match snd (Unix.waitpid [] pid) with Unix.WEXITED 0 -> failwith "accepted duplicate exit_code" | _ -> print_endline "PASS duplicate_exit_code");
  rejects "wrong_runner" (replace "argv" (`List [`String "not-runner"]) base);
  rejects "nonstring_argv" (replace "argv" (`List [`Int 1]) base);
  let argv = match Yojson.Safe.Util.member "argv" base with `List values -> values | _ -> failwith "argv" in
  let injected options =
    match argv with launcher :: noshell :: noinput :: rest -> `List (launcher :: noshell :: noinput :: options @ rest) | _ -> failwith "short argv" in
  rejects "prefix_run" (replace "argv" (injected [`String "-run"; `String "foreign_runner"; `String "main"]) base);
  rejects "prefix_args_file" (replace "argv" (injected [`String "-args_file"; `String "/tmp/foreign-runtime.args"]) base);
  rejects "prefix_boot" (replace "argv" (injected [`String "-boot"; `String "/tmp/foreign.boot"]) base);
  let path = Filename.temp_file "ev98-oversize" ".json" in
  let out = open_out_bin path in output_string out (String.make (4 * 1024 * 1024 + 1) 'x'); close_out out;
  let pid = Unix.create_process exe [|exe; path; beam; digest|] Unix.stdin Unix.stdout Unix.stderr in
  (match snd (Unix.waitpid [] pid) with Unix.WEXITED 0 -> failwith "accepted oversize" | _ -> print_endline "PASS oversize_before_parse");
  let link = Filename.temp_file "ev98-link" ".json" in Unix.unlink link; Unix.symlink receipt link;
  let pid = Unix.create_process exe [|exe; link; beam; digest|] Unix.stdin Unix.stdout Unix.stderr in
  (match snd (Unix.waitpid [] pid) with Unix.WEXITED 0 -> failwith "accepted receipt symlink" | _ -> print_endline "PASS receipt_symlink");
  match Ev98_health_smt.rows () with
  | first :: rest ->
    let altered = { first with independently_validated = false } :: rest in
    if Ev98_health_smt.emitted_rows_hold altered then failwith "accepted altered solver rows"
    else print_endline "PASS altered_emitted_rows_prevent_success"
  | [] -> failwith "missing solver rows"
