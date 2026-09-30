(* All process fixtures have a 30s finite lifetime as a second safety bound.
   Parent control adds GNU timeout; long waits intentionally test product limits. *)
let () =
  match Sys.argv.(Array.length Sys.argv - 1) with
  | "forged-success" -> print_endline "SUCCESS"
  | "first-byte-hang" -> print_string "S"; flush stdout; Unix.sleep 30
  | "stdout-closed-hang" -> close_out stdout; close_out stderr; Unix.sleep 30
  | "late-abort" ->
      print_endline "SUCCESS";
      for _ = 1 to 21 do print_endline "unused line" done;
      print_endline "ABORT: independent negative control"
  | "large-line" ->
      print_string "SUCCESS";
      print_string (String.make (4 * 1024 * 1024) 'x');
      print_newline ()
  | "silent-timeout" -> Unix.sleep 30
  | "descendant" ->
      let child = Unix.fork () in
      if child = 0 then (Unix.sleep 30; exit 0)
      else (
        let oc = open_out (Sys.argv.(1) ^ ".descendant-pid") in
        output_string oc (string_of_int child); close_out oc;
        Unix.sleep 30)
  | _ -> exit 2
