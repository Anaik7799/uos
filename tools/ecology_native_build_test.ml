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
 ["ecology_file_transaction.ml";"ecology_file_transaction_port.ml";"telegram_store_transport_guardian.ml";"ecology_process.ml";"ecology_native_build.ml"];
 mkdir(root^"/native");mkdir(root^"/native/c");
 write(root^"/native/c/finite_environment_launch.c")(read(source^"/native/c/finite_environment_launch.c"));
 List.iter(fun d->mkdir(root^"/"^d))["engines";"engines/hermes";"engines/hermes/modules";"engines/hermes/modules/hermes_harness"];
 List.iter(fun name->let p="engines/hermes/modules/hermes_harness/"^name in write(root^"/"^p)(read(source^"/"^p)))
 ["core.ml";"inventory.ml";"evidence_store.ml";"symbiosis_check_receipts.ml";"symbiosis_check_receipts.mli";"ecology_release_grants.ml";"ecology_release_grants.mli";"ecology_release_grants_port.ml"];root
let kp="#use \"topfind\";;\n#require \"bos.setup,yojson,cryptokit,mtime.clock\";;\n"
let pp="#use \"ecology_file_transaction.ml\";;\n"
let ()=
 let elf=Bytes.make 464 '\000'in
 let put16 p n=for k=0 to 1 do Bytes.set elf(p+k)(Char.chr((n lsr(8*k))land 255))done in
 let put32 p n=for k=0 to 3 do Bytes.set elf(p+k)(Char.chr((n lsr(8*k))land 255))done in
 let put64 p n=put32 p n;put32(p+4)0 in
 Bytes.blit_string "\127ELF\002\001" 0 elf 0 6;put16 18 62;put64 40 64;put16 58 64;put16 60 4;
 put32(128+4)3;put64(128+24)320;put64(128+32)96;
 put32(192+4)6;put64(192+24)416;put64(192+32)32;put32(192+40)1;
 put32(256+4)0x6ffffffe;put64(256+24)448;put64(256+32)16;put32(256+40)1;
 Bytes.blit_string "libc.so.6" 0 elf 321 9;
 Bytes.blit_string "$ORIGIN/runtime/libc.so.6" 0 elf 336 25;
 put64 416 1;put64 424 1;put16 448 1;put32 452 16;
 let original=Bytes.to_string elf in
 check "RED literal ORIGIN Verneed label cannot identify target SONAME"(error(N.test_verify_versions original));
 let fixed=ok(N.test_retarget_versions ~worker:true original)in
 check "GREEN exact existing dynstr Verneed retarget"(N.test_verify_versions fixed=Ok());
 check "only vn_file four bytes may change"(String.mapi(fun k c->if k>=452 && k<456 then original.[k]else c)fixed=original);
 check "new vn_file reuses existing SONAME index"(Char.code fixed.[452]=1);
 List.iter(fun(p,c)->let b=Bytes.of_string original in Bytes.set b p c;
   check "unsupported/truncated/unknown ELF shape HOLD"(error(N.test_retarget_versions ~worker:true(Bytes.to_string b))))
 [4,'\001';18,'\183';60,'\000';216,'\255';321,'e';432,'\001';440,'\001'];
 let after_null=Bytes.of_string original in Bytes.fill after_null 416 32 '\000';
 Bytes.set after_null 432 '\001';Bytes.set after_null 440 '\001';
 check "DT_NEEDED hidden after FIRST DT_NULL is refused, not interpreted"
   (error(N.test_retarget_versions ~worker:true(Bytes.to_string after_null)));
 check "truncated ELF HOLD"(error(N.test_retarget_versions ~worker:true(String.sub original 0 450)));
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
let ()=Printf.printf "%d focused/source/transform checks observed before mandatory actual composite build\n%!" !checks
let a=ok(N.build ~source_root:root ~toolchain_root:tc)
let ()=
 let j=Yojson.Safe.from_string(read(N.manifest a))in
 check "finite source-bound artifact schema"(Yojson.Safe.Util.member "schema"j=`String"uos.native-build.v3");
 check "finite launcher captured as distinct pinned output"(List.mem "finite_launcher.exe"(N.payload_files a));
 check "closed Linux x86_64/profile recipe"(Yojson.Safe.Util.(member "architecture"(member "recipe"j))=`String"linux-x86_64" && Yojson.Safe.Util.(member "launch_profile"(member "recipe"j))=`String"native-storage-v1")
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
(* Actual ELF substrate interpretation, not just metadata equality. Relocation
   means a different private directory on this host; the Nix interpreter stays
   external. A finite replacement environment excludes ALL inherited LD_*,
   GLIBC_TUNABLES and other dynamic-loader knobs. Production FFI is unchanged
   and inherits its environment: activation remains HOLD for that boundary. *)
let clean_native_env=Astring.String.Map.of_list[
 "PATH",tc^"/toolchains/opam-ocaml/bin:"^tc^"/toolchains/nix-profile/bin:/usr/bin:/bin";
 "OCAMLPATH",tc^"/toolchains/opam-ocaml/lib";"LANG","C.UTF-8"]
let loader="/nix/store/n51dhmdbik1kfrsm62j5knavmigwrl1a-glibc-2.42-84/lib/ld-linux-x86-64.so.2"
let bounded_tool exe args=
 let argv=[tc^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";source^"/tools/ecology_process.ml";
  "2000";"8192";"merged";exe]@args in
 match Bos.OS.Cmd.run_out ~env:clean_native_env(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string ~trim:false with
 |Ok(raw,(_,`Exited code))->raw,code
 |_->failwith"bounded private ELF initialization failed"
let initialized directory ?(no_cache=false) program=
 let exe,args=if no_cache then loader,["--inhibit-cache";directory^"/"^program]
   else directory^"/"^program,[]in bounded_tool exe args
let exact_hold raw=
 if String.length raw<4 then false else
 let n=ref 0 in for k=0 to 3 do n:=(!n lsl 8)lor Char.code raw.[k]done;
 !n=String.length raw-4 &&
 Yojson.Safe.Util.member "status"(Yojson.Safe.from_string(String.sub raw 4 !n))=`String"hold"
let ()=
 let relocated=base^"/relocated"in mkdir relocated;mkdir(relocated^"/runtime");
 List.iter(fun p->if p<>"manifest.json"then(
   let bytes=read(N.directory a^"/"^p)in write(relocated^"/"^p)bytes;
   Unix.chmod(relocated^"/"^p)(if Filename.dirname p="runtime"then 0o444 else 0o555);
   check "relocation preserves exact observed output bytes"(read(relocated^"/"^p)=bytes))) (N.payload_files a);
 let programs=["worker.exe";"guardian.exe";"release_grants_worker.exe"]in
 List.iter(fun p->List.iter(fun no_cache->let raw,code=initialized relocated ~no_cache p in
   check "relocated initialization has expected exit"(code=(if p="guardian.exe"then 125 else 0));
   if p<>"guardian.exe"then check "relocated exact binary frame is HOLD"(exact_hold raw)) [false;true])programs;
 let required program lib=List.mem lib(match program with
   |"worker.exe"->["libc.so.6";"libm.so.6";"libgmp.so.10";"libz.so.1"]
   |"guardian.exe"->["libc.so.6";"libm.so.6";"libpthread.so.0";"librt.so.1"]
   |"release_grants_worker.exe"->["libc.so.6";"libm.so.6";"libsqlite3.so.0";"libz.so.1"]
   |_->failwith"closed test program inventory")in
 List.iter(fun lib->let p=relocated^"/runtime/"^lib in Unix.rename p(p^".held");
   Fun.protect ~finally:(fun()->Unix.rename(p^".held")p)(fun()->
     List.iter(fun program->List.iter(fun no_cache->let raw,code=initialized relocated ~no_cache program in
       if required program lib then(
         check "required-library absence refuses before worker startup"(code=127);
         check "missing dependency is loader refusal, not framed worker HOLD"
           (Astring.String.is_infix ~affix:"error while loading shared libraries" raw))
       else check "unreferenced library absence leaves initialization unchanged"
         (code=(if program="guardian.exe"then 125 else 0))) [false;true])programs))
 ["libc.so.6";"libm.so.6";"libgmp.so.10";"libz.so.1";"libpthread.so.0";"librt.so.1";"libsqlite3.so.0"];
 check "all original runtime files retained after private omission controls"
   (List.for_all(fun p->if Filename.dirname p="runtime"then read(N.directory a^"/"^p)=read(relocated^"/"^p)else true)(N.payload_files a))
let ()=
 (* A syntactically valid, metadata-conforming ELF constructor is the control:
    a shebang/invalid ELF would be stopped by inspection even with the OLD bug.
    Its only effect is one known marker in this private synthetic fixture. *)
 let marker=base^"/private-marker"and c=base^"/marker.c"and so=base^"/marker.so"in
 write c(Printf.sprintf "#include <fcntl.h>\n#include <unistd.h>\n__attribute__((constructor)) static void marker(void){int f=open(%S,O_CREAT|O_WRONLY|O_EXCL,0600);if(f>=0){(void)write(f,\"PRIVATE\",7);close(f);}}\n" marker);
 let gcc="/nix/store/w88q44gqd1qg5wmkk7v0h97rpiqvam0l-gcc-wrapper-15.3.0/bin/gcc"in
 let _,code=bounded_tool gcc["-shared";"-fPIC";"-Wl,-soname,libz.so.1";"-o";so;c]in
 check "private benign constructor ELF compiled with pinned cached GCC"(code=0);
 let patchelf="/nix/store/fpig164lz7fcipbndn61sfd2y2yq363n-patchelf-0.15.2/bin/patchelf"in
 List.iter(fun args->let _,code=bounded_tool patchelf args in check "private control ELF normalized"(code=0))
 [["--set-rpath";"$ORIGIN";so];["--no-default-lib";so]];
 let path=N.directory a^"/runtime/libz.so.1"in let saved=read path in
 mutate path(read so)0o444;
 Fun.protect ~finally:(fun()->mutate path saved 0o444)(fun()->
   (* Positive control intentionally executes only this locally authored benign
      marker through the known worker; no DB/configuration/credential input. *)
   let raw,code=initialized(N.directory a)"worker.exe"in
   check "valid ELF constructor positive control reaches only private marker"
     (code=0 && exact_hold raw && Sys.file_exists marker && read marker="PRIVATE");
   Unix.unlink marker;
   check "tampered metadata-valid runtime refused against independent artifact ID"(error(verify()));
   check "authentication failure executes NO constructor"(not(Sys.file_exists marker)));
 check "restored exact artifact verifies after execution-order control"(not(error(verify())))
let call config text=
 let ir,iw=Unix.pipe ~cloexec:true()and or_,ow=Unix.pipe ~cloexec:true()in let err=Unix.openfile "/dev/null"[Unix.O_WRONLY]0 in
 let guardian=N.guardian a and worker=N.worker a in
 let env=Astring.String.Map.bindings clean_native_env|>List.map(fun(k,v)->k^"="^v)|>Array.of_list in
 let pid=Unix.create_process_env guardian[|guardian;worker;config;"3000"|]env ir ow err in
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
