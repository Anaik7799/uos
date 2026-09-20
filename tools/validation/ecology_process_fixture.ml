#load "unix.cma";;
(* Bounded child-process falsifiers for the ecology guardian. *)
let () = match Array.to_list Sys.argv with
| [_;"drip"] -> for _=1 to 100 do print_endline "tick";Unix.sleepf 0.02 done
| [_;"flood"] -> print_string(String.make 1048577 'x');flush stdout
| [_;"closed-output";delay;code] ->
  close_out stdout;close_out stderr;Unix.sleepf(float_of_string delay);exit(int_of_string code)
| [_;"open-output";delay;code] -> Unix.sleepf(float_of_string delay);exit(int_of_string code)
| [_;"closed-signal"] ->
  close_out stdout;close_out stderr;Unix.kill(Unix.getpid()) Sys.sigkill
| [_;"closed-tree";marker] ->
  let child=Unix.fork() in
  close_out stdout;close_out stderr;
  if child=0 then (Unix.sleepf 0.8;let channel=open_out marker in output_string channel "escaped";close_out channel)
  else (Unix.sleepf 0.05;exit 0)
| [_;"tree";marker] ->
  let pid=Unix.fork() in
  if pid=0 then (Unix.sleepf 1.;let out=open_out marker in output_string out "escaped";close_out out)
  else (print_endline(string_of_int pid);Unix.sleepf 2.)
| _ -> failwith "unknown fixture"
