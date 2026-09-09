#use "topfind";;
#require "unix,yojson,cryptokit";;
(* Two fresh private repositories only. MODE=red observes the old defect;
   MODE=green requires preservation. No canonical observer invocation. *)
open Yojson.Safe.Util
let root="/home/an/NAS-setup/uos"
let tc=root^"/toolchains/opam-ocaml/bin/"
let adapter=root^"/.uos-workspaces/codex-ev-admission-20260909-0210/tools/ev_native.ml"
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->really_input_string c(in_channel_length c))
let write p b=let c=open_out_bin p in output_string c b;close_out c
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let require b s=if not b then failwith s
let ()=require(Array.length Sys.argv=4)"WORKSPACE FULL_REVISION red|green"
let ws=Unix.realpath Sys.argv.(1) and revision=Sys.argv.(2) and mode=Sys.argv.(3)
let ()=require(String.length revision=40 && String.for_all(function '0'..'9'|'a'..'f'->true|_->false)revision)"full revision";require(List.mem mode["red";"green"])"mode"
let stage=Filename.temp_dir ~temp_dir:"/tmp" "ev01-cwd-regression-"""
let counter=ref 0 and observations=ref[]
let invoke ?(expected=0) cwd label tool args=
 incr counter;let receipt=Printf.sprintf "%s/%02d-%s.json"stage !counter label in
 let fd=Unix.openfile(receipt^".output")[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in
 let input=Unix.openfile "/dev/null"[Unix.O_RDONLY]0 in
 let argv=Array.of_list([tc^"ocamlrun";tc^"ocaml";adapter;"--cwd";cwd;"--seconds";"30";"--receipt";receipt;"--";tool]@args)in
 let pid=Unix.create_process_env(tc^"ocamlrun")argv(Unix.environment())input fd fd in Unix.close fd;Unix.close input;
 let _,status=Unix.waitpid[]pid in let data=Yojson.Safe.from_file receipt in
 require(status=Unix.WEXITED(data|>member "exit_code"|>to_int))"structured child exit";
 let output=data|>member "output"|>to_string in
 require(sha output=(data|>member "output_sha256"|>to_string))"child output digest";
 observations:=`Assoc["path",`String receipt;"sha256",`String(sha(read receipt))]::!observations;
 require(data|>member "exit_code"|>to_int=expected)(label^": "^output);output
let query args=invoke ws "source" "jj"(["--ignore-working-copy";"--at-operation";"@";"--no-pager";"-R";ws]@args)
let expr="commit_id(\""^revision^"\")"
let child={|#use "topfind";;
#require "unix,yojson,cryptokit,mtime.clock.os";;
#mod_use "bootstrap_model.ml";;
#mod_use "bootstrap_observer.ml";;
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->really_input_string c(in_channel_length c))
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let require b s=if not b then failwith s
let fingerprint root=
 let count=ref 0 in let rec visit path=
  incr count;require(!count<=256)"fixture fingerprint node budget";
  let s=Unix.lstat path in
  let item=`Assoc["path",`String path;"inode",`Int s.st_ino;"mode",`Int s.st_perm;"size",`Int s.st_size;"mtime",`Float s.st_mtime;"ctime",`Float s.st_ctime;"bytes_sha256",(if s.st_kind=Unix.S_REG then `String(sha(read path))else `Null)]in
  item::(if s.st_kind=Unix.S_DIR then Sys.readdir path|>Array.to_list|>List.sort String.compare|>List.concat_map(fun n->visit(path^"/"^n))else[])in
 `List(visit root)
let ()=
 let selected=Sys.argv.(1)and startup=Sys.argv.(2)and config=Sys.argv.(3)and mode=Sys.argv.(4)in
 require(Sys.getcwd()=startup)"actual private startup cwd";
 let original_cwd=Sys.getcwd()in
 let before_a=fingerprint selected and before_b=fingerprint startup and before_c=fingerprint config in
 let result=Bootstrap_observer.observe selected in
 let after_a=fingerprint selected and after_b=fingerprint startup and after_c=fingerprint config in
 let passed=match result with Ok observation->observation.root=selected|Error _->false in
 let parent_preserved=Sys.getcwd()=original_cwd in
 let expected=if mode="red"then passed && parent_preserved && before_a=after_a && before_b<>after_b && before_c<>after_c
  else passed && parent_preserved && before_a=after_a && before_b=after_b && before_c=after_c in
 let chdir_refused=if mode="red"then true else
  try ignore(Bootstrap_observer.command(Bootstrap_observer.mono()+.5.)(ref 65536)config(selected^"/missing") ["root"]);false
  with Bootstrap_observer.Refused _->Sys.getcwd()=original_cwd && fingerprint startup=after_b && fingerprint config=after_c in
 let report=`Assoc["mode",`String mode;"observer_passed",`Bool passed;"parent_cwd_preserved",`Bool parent_preserved;"expected_control",`Bool expected;"missing_child_cwd_refused",`Bool chdir_refused;"selected_before",before_a;"selected_after",after_a;"startup_before",before_b;"startup_after",after_b;"config_before",before_c;"config_after",after_c]in
 print_endline(Yojson.Safe.to_string report);
 require expected(if mode="red"then "designated old cwd side effect absent"else "child cwd binding preserves both private repositories and configs");
 require(before_a=after_a && before_b=after_b && before_c=after_c)"child cwd binding preserves both private repositories and configs";
 require chdir_refused "missing child cwd fails closed without effects"
|}
let ()=
 print_endline stage;
 require(query["log";"-r";expr;"--no-graph";"-T";"self.commit_id()"] = revision)"exact commit";
 let sources=List.map(fun name->let path="tools/bootstrap/"^name in let bytes=query["file";"show";"-r";expr;"--";"root:"^path]in write(stage^"/"^name)bytes;`Assoc["path",`String path;"sha256",`String(sha bytes)])["bootstrap_model.ml";"bootstrap_observer.ml"]in
 let selected=stage^"/selected"and startup=stage^"/startup"and config=stage^"/config"in
 List.iter(fun path->ignore(invoke stage "init-private" "jj"["git";"init";"--no-colocate";path]))[selected;startup];
 Unix.mkdir config 0o700;write(startup^"/.jj/repo/config-id")"11111111111111111111";
 let runner=stage^"/observe.ml"in write runner child;
 let output=invoke ~expected:(if mode="red"then 2 else 0) startup "two-private-cwd" "native"["/usr/bin/env";"XDG_CONFIG_HOME="^config;tc^"ocamlrun";tc^"ocaml";runner;selected;startup;config;mode]in
 let body=Yojson.Safe.from_string(List.hd(String.split_on_char '\n' output))in
 require(body|>member "expected_control"|>to_bool)"designated outcome";
 let report=`Assoc["schema",`String "uos.ev01.two-private-cwd-regression.v1";"source_revision",`String revision;"mode",`String mode;"status",`String(if mode="red"then "OLD_READONLY_CONTRACT_FALSIFIED"else "PRESERVATION_PASS");"sources",`List sources;"runner_sha256",`String(sha child);"driver_sha256",`String(sha(read Sys.argv.(0)));"observations",`List(List.rev !observations);"control",body;"canonical_observer_invocations",`Int 0;"authority",`String "NONE"]in
 write(stage^"/verification.json")(Yojson.Safe.pretty_to_string report);
 Printf.printf "PASS designated %s control: %s/verification.json\n"mode stage
