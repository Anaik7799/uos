#use "topfind";;
#require "bos,yojson,unix";;
(* Fixed adapter to the EXISTING canonical aggregate liability ledger. Gleam
   authorizes the task and binds this exact request first. No init/refund/clock
   override/model call/alternate ledger option is exposed here. *)
let root="/home/an/NAS-setup/uos"
let ()=
 try
  if Array.length Sys.argv<>2||String.length Sys.argv.(1)>2048 then failwith"input";
  let request=Sys.argv.(1)in
  let command=Bos.Cmd.of_list[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";
   root^"/tools/ecology_process.ml";"4000";"8192";"framed";
   root^"/toolchains/opam-ocaml/bin/ocaml";root^"/tools/ecology_budget.ml";"reserve";
   root^"/var/ecology/openrouter_budget.sqlite3"]in
  match Bos.OS.Cmd.run_io command(Bos.OS.Cmd.in_string request)|>Bos.OS.Cmd.out_string~trim:false with
  |Ok(body,(_,`Exited 0))when String.length body<=8192->print_string body
  |_->print_string"{\"status\":\"RESERVATION_UNKNOWN\",\"dispatch_authorized\":false}";exit 1
 with _->print_string"{\"status\":\"RESERVATION_UNKNOWN\",\"dispatch_authorized\":false}";exit 1
