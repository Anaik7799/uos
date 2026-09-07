(* Bounded local process fixtures. Not Solo5 artifacts and never admitted. *)
let () =
  match Sys.argv.(Array.length Sys.argv - 1) with
  | "silent-timeout" -> Unix.sleep 30
  | "late-abort" ->
      print_endline "SUCCESS: solo5_exit(0)";
      for _ = 1 to 25 do print_endline (String.make 2048 'x') done;
      print_endline "ABORT: intentional independent negative control"
  | "large-line" -> print_string (String.make (4 * 1024 * 1024) 'x'); flush stdout
  | _ -> exit 2
