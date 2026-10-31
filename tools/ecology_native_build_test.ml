#!/usr/bin/env -S opam exec -- ocaml
#use "ecology_native_build.ml";;
(* LOCAL Codex: reviewed public sources, actual cached compiler and synthetic
   private file ABI only. Finite laws/tests, not arbitrary-language proof. *)
module N=Native_build
let checks=ref 0
let check why b=if not b then failwith("TEST FAILED: "^why);incr checks
let ok=function Ok x->x|Error e->failwith(N.error_label e)
let error=function Error _->true|Ok _->false
let read p=let ic=open_in_bin p in Fun.protect ~finally:(fun()->close_in ic)(fun()->really_input_string ic(in_channel_length ic))
let write p text=let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_TRUNC]0o600 in
 Fun.protect ~finally:(fun()->Unix.close fd)(fun()->let rec loop off=if off<String.length text then let n=Unix.write_substring fd text off(String.length text-off)in if n<=0 then failwith "write"else loop(off+n)in loop 0;Unix.fchmod fd 0o600;Unix.fsync fd)
let mkdir p=Unix.mkdir p 0o700
let ()=if Array.length Sys.argv<>3 then failwith "usage: ecology_native_build_test.ml SOURCE_ROOT TOOLCHAIN_ROOT"
let source=Unix.realpath Sys.argv.(1)and tc=Unix.realpath Sys.argv.(2)
let base=Filename.temp_file ~temp_dir:(Unix.realpath(Filename.get_temp_dir_name())) "uos-native-build-test-" ""
let ()=Unix.unlink base;mkdir base
let serial=ref 0
let fixture()=incr serial;let root=base^"/fixture-"^string_of_int !serial in mkdir root;mkdir(root^"/tools");
 List.iter(fun name->write(root^"/tools/"^name)(read(source^"/tools/"^name)))
 ["ecology_file_transaction.ml";"ecology_file_transaction_port.ml";"telegram_store_transport_guardian.ml";"ecology_process.ml";"ecology_native_build.ml"];root
let kp="#use \"topfind\";;\n#require \"bos.setup,yojson,cryptokit,mtime.clock\";;\n"
let pp="#use \"ecology_file_transaction.ml\";;\n"
let ()=
 List.iter(fun(kind,prefix)->
  List.iter(fun rest->check "exact prefix removed, suffix byte-identical"(N.transform kind(prefix^rest)=Ok rest))
  ["\nlet x=1\n";"(* #use not a directive *)\nlet c='#'\n";"let x=\"multi\n#load in a string\"\n";
   "let x={tag|\n#use quoted string\n|tag}\n";"(* nested (* inner *)\n#use in comment\n*)\nlet x=0\n"];
  List.iter(fun rest->check "actual unexpected directive refused"(N.transform kind(prefix^rest)=Error N.Unexpected_directive))
   ["\n  #load \"unix.cma\";;\n";"(* safe *) #use \"evil.ml\";;\n";"let x=\"safe\"\n#use \"evil.ml\";;"]
 )[N.Kernel,kp;N.Port,pp;N.Guardian,""];
 check "changed required directive prefix refused"(N.transform N.Kernel(" "^kp^"let x=0")=Error N.Invalid_source);
 check "oversize transform input refused"(N.transform N.Guardian(String.make 262145 'x')=Error N.Resource_bound);
 List.iter(fun seed->let rng=Random.State.make[|seed|]in for _=1 to 100 do
  let x=Random.State.int rng 100000 in let rest=Printf.sprintf "(* %d *)\nlet x=%d\n" seed x in
  check "seeded reference crop equals lexical transform"(ok(N.transform N.Kernel(kp^rest))=String.sub(kp^rest)(String.length kp)(String.length rest))
 done)[17;91]
let ()=
 let root=fixture()in let path=root^"/tools/ecology_file_transaction.ml"in write path(read path^"\nlet unreviewed=()\n");
 check "unreviewed source refused before var effects"(N.build ~source_root:root ~toolchain_root:tc=Error N.Source_mismatch);
 check "no artifact namespace on unreviewed source"(not(Sys.file_exists(root^"/var")));
 let root=fixture()in let path=root^"/tools/ecology_file_transaction.ml"in Unix.rename path(path^".old");Unix.symlink(path^".old")path;
 check "symlink source refused"(error(N.build ~source_root:root ~toolchain_root:tc));
 let root=fixture()in Unix.link(root^"/tools/ecology_file_transaction.ml")(root^"/tools/alias");
 check "hardlink source refused"(error(N.build ~source_root:root ~toolchain_root:tc));
 check "noncanonical root refused"(N.build ~source_root:(source^"/../uos") ~toolchain_root:tc=Error N.Invalid_root)
let root=fixture()
let a=ok(N.build ~source_root:root ~toolchain_root:tc)
let verify()=N.verify ~source_root:root ~toolchain_root:tc ~artifact_id:(N.artifact_id a)
let mutate p text mode=Unix.chmod p 0o600;write p text;Unix.chmod p mode
let sha text=Cryptokit.hash_string(Cryptokit.Hash.sha256())text |> Cryptokit.transform_string(Cryptokit.Hexa.encode())
let ()=
 check "actual cached build returned both executables"(Sys.file_exists(N.worker a)&&Sys.file_exists(N.guardian a));
 check "exact published permissions"((Unix.stat(N.worker a)).Unix.st_perm=0o555 && (Unix.stat(N.guardian a)).Unix.st_perm=0o555 && (Unix.stat(N.manifest a)).Unix.st_perm=0o444);
 check "independently pinned full artifact ID verifies"(not(error(verify())));
 check "existing verified index reuses artifact"(N.artifact_id(ok(N.build ~source_root:root ~toolchain_root:tc))=N.artifact_id a);
 let binary=read(N.worker a)and manifest=read(N.manifest a)in
 Unix.chmod(N.worker a)0o755;check "mutable binary refused"(error(verify()));Unix.chmod(N.worker a)0o555;
 Unix.chmod(N.manifest a)0o644;check "mutable manifest refused"(error(verify()));Unix.chmod(N.manifest a)0o444;
 Unix.chmod(N.directory a)0o755;check "mutable directory refused"(error(verify()));
 write(N.directory a^"/unexpected")"public-test";Unix.chmod(N.directory a)0o555;check "unexpected artifact file refused"(error(verify()));
 Unix.chmod(N.directory a)0o755;Unix.unlink(N.directory a^"/unexpected");Unix.chmod(N.directory a)0o555;
 List.iter(fun text->mutate(N.manifest a)text 0o444;check "malformed/noncanonical/oversize manifest refused"(error(verify())))
 ["{}";"{\"schema\":1,\"schema\":1}";manifest^" ";String.make(1024*1024+1)'x'];
 mutate(N.manifest a)manifest 0o444;
 let changed=Bytes.of_string binary in Bytes.set changed 0(if Bytes.get changed 0='x'then 'y'else 'x');let changed=Bytes.to_string changed in
 mutate(N.worker a)changed 0o555;check "changed binary refused"(error(verify()));
 let j=Yojson.Safe.from_string manifest in
 let j=match j with `Assoc xs->`Assoc(List.map(fun(k,v)->if k<>"outputs"then k,v else k,
  (match v with `List xs->`List(List.map(function `Assoc fs as entry->if List.assoc "path"fs=`String"worker.exe"then
   `Assoc(List.map(fun(k,v)->k,if k="sha256"then `String(sha changed)else v)fs)else entry|v->v)xs)|v->v))xs)|v->v in
 let rec sort=function `Assoc xs->`Assoc(List.sort compare(List.map(fun(k,v)->k,sort v)xs))|`List xs->`List(List.map sort xs)|v->v in
 mutate(N.manifest a)(Yojson.Safe.to_string(sort j))0o444;
 check "coherent binary plus manifest rewrite fails old pinned ID"(error(verify()));
 mutate(N.worker a)binary 0o555;mutate(N.manifest a)manifest 0o444;check "restored exact artifact verifies"(not(error(verify())));
 let inputs=root^"/var/ecology/native-builds/inputs"in let names=Sys.readdir inputs in check "one cooperative index"(Array.length names=1);
 let path=inputs^"/"^names.(0)in let saved=read path in mutate path(String.make 64 '0'^"\n")0o444;
 check "tampered index refuses no blind rebuild"(error(N.build ~source_root:root ~toolchain_root:tc));mutate path saved 0o444
let frame text=let b=Bytes.create 4 in for i=0 to 3 do Bytes.set b i(Char.chr((String.length text lsr((3-i)*8))land 255))done;Bytes.to_string b^text
let call config text=
 let ir,iw=Unix.pipe ~cloexec:true()and or_,ow=Unix.pipe ~cloexec:true()in let err=Unix.openfile "/dev/null"[Unix.O_WRONLY]0 in
 let guardian=N.guardian a and worker=N.worker a in let pid=Unix.create_process guardian[|guardian;worker;config;"3000"|]ir ow err in
 Unix.close ir;Unix.close ow;Unix.close err;let reaped=ref false in
 Fun.protect ~finally:(fun()->Unix.close iw;Unix.close or_;if not !reaped then(Unix.kill pid Sys.sigkill;ignore(Unix.waitpid[]pid)))(fun()->
  let wire=frame text in let rec send off=if off<String.length wire then let n=Unix.write_substring iw wire off(String.length wire-off)in if n<=0 then failwith "pipe"else send(off+n)in send 0;
  let out=Buffer.create 4096 and b=Bytes.create 4096 and until=Unix.gettimeofday()+.4. in
  let rec collect()=if Unix.gettimeofday()>until then failwith "test child timeout";
   let ready,_,_=Unix.select[or_][][]0.05 in if ready=[]then collect()else let n=Unix.read or_ b 0 4096 in
   if n>0 then(Buffer.add_subbytes out b 0 n;check "actual transport output bound"(Buffer.length out<=262148);collect())in
  collect();let _,status=Unix.waitpid[]pid in reaped:=true;check "actual guardian child reaped exit0"(status=Unix.WEXITED 0);
  let body=Buffer.contents out in check "actual frame header present"(String.length body>=4);let n=ref 0 in for i=0 to 3 do n:=(!n lsl 8)lor Char.code body.[i]done;
  check "actual exact frame length"(!n=String.length body-4);Yojson.Safe.from_string(String.sub body 4 !n))
let ()=
 let abi=base^"/abi"in mkdir abi;List.iter(fun n->mkdir(abi^"/"^n))["files";"control";"staging"];
 write(abi^"/files/target")"synthetic-old";write(abi^"/staging/new")"synthetic-new";
 let d c=`String("sha256:"^String.make 64 c)in let config=abi^"/launcher.json"in
 write config(Yojson.Safe.to_string(`Assoc["schema_version",`Int 1;"root",`String(abi^"/files");"state_relative",`String".txn";"control_directory",`String(abi^"/control");"staging_directory",`String(abi^"/staging");"transaction_id",d 'a';"candidate",d 'b';"manifest",d 'c']));
 List.iter(fun(g,op,payload)->let json=call config(Yojson.Safe.to_string(`Assoc["schema_version",`Int 1;"transaction_id",d 'a';"candidate",d 'b';"manifest",d 'c';"epoch",`Int 1;"generation",`Int g;"operation",`String op;"payload",payload]))in
  check("actual built ABI "^op)(Yojson.Safe.Util.member "status"json=`String"ok"))[
  0,"inspect",`Assoc[];0,"stage",`Assoc["edits",`List[`Assoc["relative",`String"target";"replacement_relative",`String"new"]]];
  1,"replace_one",`Assoc["index",`Int 0];2,"verify_new",`Assoc[]];
 check "only private synthetic target changed via built ABI"(read(abi^"/files/target")="synthetic-new")
let ()=
 let root=fixture()in let path=root^"/tools/ecology_file_transaction.ml"in let saved=read path in
 check "source drift before publication HOLD"(N.test_build_before_publication(fun()->write path(saved^"\n(* changed *)\n"))~source_root:root ~toolchain_root:tc=Error N.Source_mismatch);
 let output=root^"/var/ecology/native-builds"in check "failed partial retained"(Array.length(Sys.readdir(output^"/work"))=1);
 check "drift published no CAS or index"(Array.length(Sys.readdir(output^"/cas"))=0 && Array.length(Sys.readdir(output^"/inputs"))=0);
 write path saved;check "incomplete prior work blocks automatic retry"(N.build ~source_root:root ~toolchain_root:tc=Error N.Partial_exists);
 Printf.printf "%d checks PASS actual_cached_build=true actual_private_guardian_abi=true artifact=%s fixtures=%s\n%!" !checks(N.artifact_id a)base
