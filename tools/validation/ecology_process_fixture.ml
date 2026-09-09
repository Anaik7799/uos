#load "unix.cma";;
(* Bounded child-process falsifiers for the ecology guardian. *)
let () = match Array.to_list Sys.argv with
| [_;"drip"] -> for _=1 to 100 do print_endline "tick";Unix.sleepf 0.02 done
| [_;"flood"] -> print_string(String.make 1048577 'x');flush stdout
| [_;"tree";marker] ->
  let pid=Unix.fork() in
  if pid=0 then (Unix.sleepf 1.;let out=open_out marker in output_string out "escaped";close_out out)
  else (print_endline(string_of_int pid);Unix.sleepf 2.)
| _ -> failwith "unknown fixture"
