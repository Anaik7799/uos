(* Deliberately hostile protocol peer; never used as parity evidence. *)
let frame bytes =
  output_binary_int stdout (String.length bytes);
  output_string stdout bytes;
  flush stdout
let () =
  let length = input_binary_int stdin in
  if length < 0 || length > 8 * 1024 * 1024 then exit 2;
  let req = Yojson.Basic.from_string (really_input_string stdin length) in
  let get key = Yojson.Basic.Util.member key req in
  let mode = Sys.argv.(1) in
  match mode with
  | "malformed_frame" -> output_string stdout "bad"; flush stdout
  | "truncated" -> output_binary_int stdout 100; output_string stdout "{}"; flush stdout
  | "oversized" -> output_binary_int stdout (8 * 1024 * 1024 + 1); flush stdout
  | "malformed_json" -> frame "{"
  | "nonzero" -> exit 7
  | "timeout" ->
    if Array.length Sys.argv > 2 then (
      let channel = open_out Sys.argv.(2) in
      Printf.fprintf channel "%d\n" (Unix.getpid ());
      close_out channel);
    Unix.sleep 60
  | _ ->
    let id = if mode = "wrong_id" then `String "other" else get "id" in
    let version = if mode = "wrong_version" then `Int 2 else get "version" in
    let operation = if mode = "wrong_operation" then `String "other" else get "operation" in
    let payload = if mode = "native_error" then
      "error", `Assoc ["code", `String "fixture_failure"; "message", `String "injected native error"]
      else "result", `Null in
    frame (Yojson.Basic.to_string (`Assoc ["version", version; "id", id; "operation", operation; payload]))
