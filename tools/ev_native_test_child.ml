(* Private test fixture; all writes are to a path supplied by the test driver. *)
let () = match Array.to_list Sys.argv with
  | [_; "signal"] -> Unix.kill (Unix.getpid ()) Sys.sigterm
  | [_; "mark"; path] ->
      let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL] 0o600 in
      Unix.close fd; print_endline "effect observed"
  | [_; "wait"] -> Unix.sleepf 5.
  | [_; "overflow"] ->
      let chunk = String.make 65536 'x' in
      for _ = 1 to 80 do print_string chunk done
  | _ -> exit 2
