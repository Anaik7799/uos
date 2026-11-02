(* TEST-ONLY PID witness wrapper. Fixed sibling executable, no arbitrary exec.
   No process fork occurs in the wrapped native SQLite worker. /proc absence
   after exit/reap is a scoped fixture witness, not a production cgroup proof. *)
let ()=
 if Array.length Sys.argv<>2 then exit 2;
 let c=open_in_bin Sys.argv.(1)in
 let locator=Fun.protect ~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in if n>8192 then exit 2;really_input_string c n)in
 let marker=match Yojson.Basic.from_string locator with `List[_;_;_;`String p]->p^".pid"|_->exit 2 in
 let fd=Unix.openfile marker[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_TRUNC]0o600 in
 let c=Unix.out_channel_of_descr fd in output_string c(string_of_int(Unix.getpid()));close_out c;
 let worker=Filename.concat(Filename.dirname(Sys.executable_name))"recovery_kernel_fixture_port.exe"in
 Unix.execv worker[|worker;locator|]
