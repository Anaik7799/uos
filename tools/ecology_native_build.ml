#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos,yojson,cryptokit,mtime.clock.os";;

(* LOCAL Codex relay. @agent_intent: Build the reviewed public Kernel, Port,
   unchanged guardian, factual grant worker and bounded static finite-env facade
   with cached pinned tools; never release authority. Linux x86_64 only.
   @laws: transformation preserves every byte except the three exact directives;
   captured inputs are rechecked before publication; pinned artifact ID covers the
   complete manifest and outputs; unknown/conflicting/partial output is HOLD.
   Owner permissions/index lookup are cooperative, not cryptographic authority.
   A caller must retain artifact_id independently. Existing process guardian
   bounds compiler time/output/group; local regular-FS and frozen same-UID inputs
   are premises. Hash-before-exec does not defeat concurrent same-UID path
   replacement; verified runtime ownership/freeze remains an activation HOLD.
   Escaped descendants require a service cgroup. No DB/config,
   package installer, network, arbitrary command, library or source arguments.
   CLI: build SOURCE_ROOT TOOLCHAIN_ROOT | verify SOURCE_ROOT TOOLCHAIN_ROOT ID *)
module Native_build : sig
  type kind = Kernel | Port | Guardian
  type error = Invalid_root | Unsafe_file | Resource_bound | Source_mismatch
    | Unexpected_directive | Invalid_source | Toolchain_mismatch | Build_failed
    | Partial_exists | Artifact_conflict | Invalid_artifact | Runtime_unavailable | Io_failure
  val error_label : error -> string
  val transform : kind -> string -> (string,error) result
  type artifact
  val artifact_id : artifact -> string
  val directory : artifact -> string
  val worker : artifact -> string
  val guardian : artifact -> string
  val manifest : artifact -> string
  val worker_sha256 : artifact -> string
  val guardian_sha256 : artifact -> string
  val release_worker : artifact -> string
  val release_worker_sha256 : artifact -> string
  val launcher : artifact -> string
  val launcher_sha256 : artifact -> string
  val payload_files : artifact -> string list
  val test_retarget_versions : worker:bool -> string -> (string,error) result
  val test_verify_versions : string -> (unit,error) result
  val build : source_root:string -> toolchain_root:string -> (artifact,error) result
  val verify : source_root:string -> toolchain_root:string -> artifact_id:string -> (artifact,error) result
  (* Library-only fault observer, never a CLI field, command or production hook. *)
  val test_build_before_publication : (unit -> unit) -> source_root:string -> toolchain_root:string -> (artifact,error) result
  val to_json : artifact -> Yojson.Safe.t
end = struct
  open Unix
  type kind=Kernel|Port|Guardian
  type error=Invalid_root|Unsafe_file|Resource_bound|Source_mismatch|Unexpected_directive|Invalid_source
    |Toolchain_mismatch|Build_failed|Partial_exists|Artifact_conflict|Invalid_artifact|Runtime_unavailable|Io_failure
  let error_label=function Invalid_root->"invalid_root"|Unsafe_file->"unsafe_file"|Resource_bound->"resource_bound"
    |Source_mismatch->"source_mismatch"|Unexpected_directive->"unexpected_directive"|Invalid_source->"invalid_source"
    |Toolchain_mismatch->"toolchain_mismatch"|Build_failed->"build_failed"|Partial_exists->"partial_exists"
    |Artifact_conflict->"artifact_conflict"|Invalid_artifact->"invalid_artifact"|Runtime_unavailable->"runtime_unavailable"|Io_failure->"io_failure"
  exception Hold of error
  let need b e=if not b then raise(Hold e)
  let digest s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s |> Cryptokit.transform_string(Cryptokit.Hexa.encode())
  let rec canonical=function `Assoc xs->`Assoc(List.sort(fun(a,_)(b,_)->String.compare a b)(List.map(fun(k,v)->k,canonical v)xs))
    |`List xs->`List(List.map canonical xs)|v->v
  let encoded j=Yojson.Safe.to_string(canonical j)
  let s x=`String x and n x=`Int x
  let hex x=String.length x=64 && String.for_all(function '0'..'9'|'a'..'f'->true|_->false)x
  let protect f=try Ok(f())with Hold e->Error e|Unix_error _|Sys_error _|Yojson.Json_error _->Error Io_failure
  let now()=Mtime.Span.to_float_ns(Mtime_clock.elapsed())/.1e9
  let max_binary=64*1024*1024
  let max_manifest=1024*1024
  let hermes="engines/hermes/modules/hermes_harness/"
  let sources=[
    "native/c/finite_environment_launch.c","297cf7a9f15768c0be2f8335e53d6dd8dcc8cc01a20d0be6378fe77ed23b1371";
    "tools/ecology_file_transaction.ml","64789f843adf44440b8190fd3c6eb8fadba4b5d7d052dd790a33e8375d240cd2";
    "tools/ecology_file_transaction_port.ml","463e6c48bbbee414d5be551ed5485f84ec49a478d2830d888a9f4ee7d20918b6";
    "tools/telegram_store_transport_guardian.ml","9ba03f57d2350c75ab95bfaa36553e637f432bd30e32dffd7db6ce738978d6d5";
    "tools/ecology_process.ml","b8ed1735909701376949b0ca00acd2f4cb8aac177fb771a5c59532319cea249b"]@List.map(fun(p,h)->hermes^p,h)[
    "core.ml","300f3a5b07c2df8e449c9a09bea8683177298cf7090e1fb23d6896fcd8a08ff4";
    "inventory.ml","fa57639337a36a7d6b2d4f9437c8adc8e41d9c4eefe7e1b3cdac63a8c6301aa3";
    "evidence_store.ml","3df638c16000dbab0a4fe947edb0dd616063569e8a5159792f601cfff75fed64";
    "symbiosis_check_receipts.ml","146387176ca599ba3933620b8363a4d406a8088842e8a597dc4c4c6eb4f001e7";
    "symbiosis_check_receipts.mli","449662b7959dc805c131a821740353ddaa294492e85d2eff8d2d3857222ac7cb";
    "ecology_release_grants.ml","efbbcc5afa51d10c1b60a3522b152c96f298bdfe31795c74af75d934ec8100b0";
    "ecology_release_grants.mli","2ed305f4378da9e90beb14344ddd23b2192b544711876b17e631cb48377a62a4";
    "ecology_release_grants_port.ml","9d9172f0146cc01ed9f66fa72b0e1703b8c6819d2302138bc1df3f6eb279d80b"]
  let glibc="/nix/store/n51dhmdbik1kfrsm62j5knavmigwrl1a-glibc-2.42-84/lib/"
  let loader=glibc^"ld-linux-x86-64.so.2"
  let sqlite="/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib/"
  let nix_gcc="/nix/store/w88q44gqd1qg5wmkk7v0h97rpiqvam0l-gcc-wrapper-15.3.0/bin/gcc"
  let patchelf="/nix/store/fpig164lz7fcipbndn61sfd2y2yq363n-patchelf-0.15.2/bin/patchelf"
  let nix_readelf="/nix/store/5pa1282x1sasbwhmnah6bny1g9pc2lj1-binutils-2.46/bin/readelf"
  let runtime_sources=[
    "libpthread.so.0",glibc^"libpthread.so.0","74459e8919cf4d93b3c0c5ebf8a1b670d9cc8b3494a4d401c56aaa636bcbbf19";
    "librt.so.1",glibc^"librt.so.1","c3758f70ac6fc40f087649c3a209fcd2ee817119cbebe7d286862a25d9b7e715";
    "libgmp.so.10","/nix/store/jrzincyqwpwvl7xvbnfjryyczd3b8a78-gmp-6.3.0/lib/libgmp.so.10.5.0","c90f177b1b7469da1ca42ba5d0e3b9572d23432a66ea2489e23aa9339eb7b178";
    "libc.so.6",glibc^"libc.so.6","8334bf4b6c5ab4939cab40f9c9594d0756d10dc6df3e5603593d223f7c538b02";
    "libm.so.6",glibc^"libm.so.6","6b750bd68b01a4205569d14d2952c3ada4fdf0316a875d02a59d2f680dc5f205";
    "libsqlite3.so.0",sqlite^"libsqlite3.so.3.53.3","83be5e2629d718bf67b5bd0b545f56fd3438773791bfaf26f0bdbd78e9e5f16b";
    "libz.so.1","/nix/store/l3p6y554mkxi4vipnnp8809kxj0g1lyv-zlib-1.3.2/lib/libz.so.1.3.2","7e890587588b933bf5e9759f5882cf992ed4c6cbdc4cd3d3e829a7043a870c92"]
  let nix_inputs=[nix_gcc,"a6bae38b6f7ecfc085b9716ca4c238a8d20e3d45ae0db46d5a1e355c9ca37632";
    patchelf,"dddb7afe3bc9a35e9646042964956f49e62972c96ccee15cec7b3c48faab9acd";
    nix_readelf,"f5a29c8f253ab3b56b4bf7a643def9cf33430bec5d1f56399fccd9c97d292d05";
    loader,"0e470f96e41ddd98ac964b3b729df0becfa7562c8ba78ab3cab1822fa5498d23"]@
    List.map(fun(_,p,h)->p,h)runtime_sources
  let tools=[
    "ocaml","f63584aac3923ba0060b0795274846b6df425b17b7f2f45bc6368b81e3b2ad92";
    "ocamlc.opt","00f78789117b660082780c5a1b4a2d450a0b26723e548e881594bedc95e4c030";
    "ocamlopt.opt","46277032bdb87755ce4bd9f20de18a7217f320fbb9b6129e7edd15571f7ee1a2";
    "dune","9b0a4d43cecade7d25cf0d524834bc4063d4c23497872d3d47c983f76d52170a";
    "ocamlfind","dab744b5c3e30b25567ffc8871b9e0ed33f4a874e2f58d2d90ad1e045c17058d"]
  let kernel_prefix="#use \"topfind\";;\n#require \"bos.setup,yojson,cryptokit,mtime.clock\";;\n"
  let port_prefix="#use \"ecology_file_transaction.ml\";;\n"
  (* Lexical directive check, not a second OCaml parser. Comments nest and may
     contain strings; normal/quoted strings and character literals cannot hide
     an actual beginning-of-line directive. Pinned compiler checks full syntax. *)
  let no_directives text=
    let len=String.length text in
    let at i x=i+String.length x<=len && String.sub text i(String.length x)=x in
    let quoted i=if i<len && text.[i]='{'then
      let rec end_tag j=if j<len then match text.[j]with
        |'|'->Some(String.sub text(i+1)(j-i-1),j+1)
        |'a'..'z'|'_'->end_tag(j+1)|_->None else None in end_tag(i+1)else None in
    let char_end i=if i<len && text.[i]='\''then
      if i+2<len && text.[i+1]<>'\\' && text.[i+2]='\''then Some(i+3)
      else if i+1<len && text.[i+1]='\\'then
        let rec find j=if j>=len || j>i+7 || text.[j]='\n' then None
          else if text.[j]='\''then Some(j+1)else find(j+1)in find(i+3)
      else None else None in
    let rec code i bol=if i>=len then()else
      if text.[i]='\n' then code(i+1)true
      else if bol && List.mem text.[i][' ';'\t';'\r';'\012']then code(i+1)true
      else if bol && text.[i]='#'then raise(Hold Unexpected_directive)
      else if at i "(*"then comment(i+2)1 bol
      else if text.[i]='"'then literal(i+1)(fun j->code j false)
      else match char_end i with Some j->code j false|None->
        match quoted i with Some(tag,j)->quote j tag(fun k->code k false)|None->code(i+1)false
    and literal i resume=if i>=len then raise(Hold Invalid_source)else
      if text.[i]='\\'then(if i+1>=len then raise(Hold Invalid_source)else literal(i+2)resume)
      else if text.[i]='"'then resume(i+1)else literal(i+1)resume
    and quote i tag resume=let ending="|"^tag^"}"in
      if i>=len then raise(Hold Invalid_source)else if at i ending then resume(i+String.length ending)else quote(i+1)tag resume
    and comment i depth bol=if i>=len then raise(Hold Invalid_source)else
      if at i "(*"then comment(i+2)(depth+1)bol
      else if at i "*)"then(if depth=1 then code(i+2)bol else comment(i+2)(depth-1)bol)
      else if text.[i]='"'then literal(i+1)(fun j->comment j depth bol)
      else match quoted i with Some(tag,j)->quote j tag(fun k->comment k depth bol)|None->comment(i+1)depth (if text.[i]='\n' then true else bol)
    in code 0 true
  let transform kind text=protect(fun()->
    need(String.length text<=262144)Resource_bound;
    let prefix=match kind with Kernel->kernel_prefix|Port->port_prefix|Guardian->""in
    need(String.starts_with ~prefix text)Invalid_source;
    let rest=String.sub text(String.length prefix)(String.length text-String.length prefix)in
    no_directives rest;rest)
  let transformed kind text=match transform kind text with Ok x->x|Error e->raise(Hold e)
  let same a b=a.st_dev=b.st_dev && a.st_ino=b.st_ino && a.st_size=b.st_size && a.st_kind=b.st_kind &&
    a.st_mtime=b.st_mtime && a.st_ctime=b.st_ctime && a.st_perm=b.st_perm && a.st_uid=b.st_uid && a.st_gid=b.st_gid && a.st_nlink=b.st_nlink
  let abs p=String.length p>1 && String.length p<4096 && p.[0]='/' && not(String.contains p '\000') &&
    List.for_all(fun x->x<>""&&x<>"."&&x<>"..") (List.tl(String.split_on_char '/' p))
  let root p=need(abs p && realpath p=p && (lstat p).st_kind=S_DIR)Invalid_root;p
  let check_parents path=
    let rec loop p=need((lstat p).st_kind=S_DIR)Unsafe_file;if p<>"/"then loop(Filename.dirname p)in loop(Filename.dirname path)
  type binding={path:string;sha:string;bytes:int}
  let binding_json b=`Assoc["path",s b.path;"sha256",s b.sha;"bytes",n b.bytes]
  let hash_file ?(owner=geteuid()) ~deadline ~single ~cap path=
    need(now()<=deadline)Resource_bound;check_parents path;
    let before=lstat path in
    need(before.st_kind=S_REG && before.st_uid=owner && (not single || before.st_nlink=1) && before.st_size>=0 && before.st_size<=cap)Unsafe_file;
    let fd=openfile path[O_RDONLY;O_NONBLOCK;O_CLOEXEC]0 in
    Fun.protect ~finally:(fun()->close fd)(fun()->
      need(same before(fstat fd) && same before(lstat path))Unsafe_file;
      let hash=Cryptokit.Hash.sha256()and buffer=Bytes.create 65536 in
      let rec loop total=need(now()<=deadline)Resource_bound;
        let count=read fd buffer 0(Bytes.length buffer)in
        if count=0 then total else(need(total+count<=cap)Resource_bound;hash#add_substring buffer 0 count;loop(total+count))in
      let count=loop 0 in need(count=before.st_size && same before(fstat fd) && same before(lstat path))Unsafe_file;
      {path;sha=Cryptokit.transform_string(Cryptokit.Hexa.encode())hash#result;bytes=count})
  let read_source ~deadline path cap=
    need(now()<=deadline)Resource_bound;check_parents path;
    let before=lstat path in
    need(before.st_kind=S_REG && before.st_uid=geteuid() && before.st_nlink=1 && before.st_size>=0 && before.st_size<=cap)Unsafe_file;
    let fd=openfile path[O_RDONLY;O_NONBLOCK;O_CLOEXEC]0 in
    Fun.protect ~finally:(fun()->close fd)(fun()->
      need(same before(fstat fd) && same before(lstat path))Unsafe_file;
      let buffer=Bytes.create(before.st_size+1)in
      let rec loop off=need(now()<=deadline)Resource_bound;
        if off=Bytes.length buffer then off else let n=read fd buffer off(min 65536(Bytes.length buffer-off))in
        if n=0 then off else loop(off+n)in
      let count=loop 0 in
      need(count=before.st_size && same before(fstat fd) && same before(lstat path))Unsafe_file;
      let text=Bytes.sub_string buffer 0 count in {path;sha=digest text;bytes=count},text)
  let exists p=try ignore(lstat p);true with Unix_error(ENOENT,_,_)->false
  let fsync_dir p=let fd=openfile p[O_RDONLY;O_CLOEXEC]0 in Fun.protect ~finally:(fun()->close fd)(fun()->fsync fd)
  let mkdir ?(private_mode=true) p=
    if not(exists p)then(mkdir p 0o700;fsync_dir(Filename.dirname p));
    let st=lstat p in need(st.st_kind=S_DIR && realpath p=p && st.st_uid=geteuid() &&
      (if private_mode then st.st_perm=0o700 else st.st_perm land 0o022=0))Unsafe_file
  let write_new ?(mode=0o600) path text=
    let fd=openfile path[O_WRONLY;O_CREAT;O_EXCL;O_CLOEXEC]0o600 in
    Fun.protect ~finally:(fun()->close fd)(fun()->
      let rec loop off=if off<String.length text then let count=write_substring fd text off(String.length text-off)in need(count>0)Io_failure;loop(off+count)in
      loop 0;fchmod fd mode;need((fstat fd).st_perm=mode)Unsafe_file;fsync fd);
    fsync_dir(Filename.dirname path)
  let dune_project="(lang dune 3.23)\n"
  let dune_workspace="(lang dune 3.23)\n(context default)\n"
  let fixed_link=" (link_flags (:standard -cc "^nix_gcc^" -ccopt -L"^sqlite^
    " -ccopt -Wl,--dynamic-linker="^loader^" -ccopt -Wl,-rpath,"^sqlite^"))"
  let dune_recipe="(library (name port_impl) (modules port_impl) (libraries yojson cryptokit unix))\n"^
    "(library (name release_impl) (wrapped false) (modules core inventory evidence_store symbiosis_check_receipts ecology_release_grants) (libraries yojson sqlite3 digestif.c unix))\n"^
    "(executable (name worker) (modules worker) (libraries port_impl)"^fixed_link^")\n"^
    "(executable (name guardian) (modules guardian) (libraries unix mtime.clock.os)"^fixed_link^")\n"^
    "(executable (name release_grants_worker) (modules release_grants_worker) (libraries release_impl yojson sqlite3 unix)"^fixed_link^")\n"
  let worker_entry="let ()=Port_impl.Port.main()\n"
  let launcher_flags=["-nostdlib";"-static";"-no-pie";"-ffreestanding";"-fno-builtin";
    "-fno-stack-protector";"-fno-pie";"-mno-red-zone";"-O2";"-Wall";"-Wextra";"-Werror";
    "-Wl,--build-id=none";"-Wl,-e,_start";"-Wl,-z,noexecstack"]
  let recipe=`Assoc["dune_project",s dune_project;"dune_workspace",s dune_workspace;"dune",s dune_recipe;"worker",s worker_entry;
    "transform",s"composite_exact_hermes_and_finite_static_launch.v4";"jobs",n 1;"compiler_timeout_ms",n 50000;"output_limit",n 1048576;
    "architecture",s"linux-x86_64";"launch_profile",s"native-storage-v1";
    "launcher_flags",`List(List.map s launcher_flags);
    "finite_environment",`List(List.map(fun(k,v)->`List[s k;s v])["PATH","/nonexistent";"LANG","C";"LC_ALL","C";"TZ","UTC"]);
    "runtime_policy",s"Opt-in static finite launcher before guardian loader; legacy paths remain separate. Closed SONAME/Verneed, RUNPATH, NODEFLIB require trusted startup/immutable paths and independently retained loader lifetime; no universal no-fallback or same-UID defence. Compiler/transitive build closure unproved. No admission."]
  let list_bounded path cap=
    let d=opendir path in Fun.protect ~finally:(fun()->closedir d)(fun()->
      let rec loop count acc=match readdir d with
        |"."|".."->loop count acc
        |name->need(count<cap)Resource_bound;loop(count+1)(name::acc)
        |exception End_of_file->List.sort String.compare acc in loop 0 [])
  let library_dirs=["lib/ocaml";"lib/ocaml/unix";"lib/yojson";"lib/cryptokit";"lib/zarith";"lib/mtime";"lib/mtime/clock";"lib/sqlite3";"lib/digestif";"lib/digestif/c";"lib/eqaf"]
  let library_name x=List.mem x["META";"dune-package"] || List.exists(fun suffix->String.ends_with ~suffix x)[".a";".cmxa";".cmx";".cmi"]
  type inputs={source_root:string;toolchain_root:string;toolchain:string;src:(binding*string)list;deps:binding list;json:Yojson.Safe.t;input_id:string;deadline:float}
  let snapshot ?(deadline=now()+.60.) source_root toolchain_root=
    let source_root=root source_root and toolchain_root=root toolchain_root in
    let toolchain=root(toolchain_root^"/toolchains/opam-ocaml")in
    let src=List.map(fun(path,expected)->let b,text=read_source ~deadline(source_root^"/"^path)262144 in
      need(b.sha=expected)Source_mismatch;({b with path},text))sources in
    let self,text=read_source ~deadline(source_root^"/tools/ecology_native_build.ml")262144 in
    let src=src@[({self with path="tools/ecology_native_build.ml"},text)]in
    need(List.fold_left(fun n(b,_)->n+b.bytes)0 src<=524288)Resource_bound;
    let binaries=List.map(fun(name,expected)->let rel="bin/"^name in
      let b=hash_file ~deadline ~single:false ~cap:max_binary(toolchain^"/"^rel)in
      need(b.sha=expected && (lstat b.path).st_perm land 0o111<>0)Toolchain_mismatch;{b with path=rel})tools in
    (* Resolve only the two standard compiler aliases, never arbitrary PATH tools. *)
    List.iter(fun(alias,target)->need(realpath(toolchain^"/bin/"^alias)=toolchain^"/bin/"^target)Toolchain_mismatch)["ocamlc","ocamlc.opt";"ocamlopt","ocamlopt.opt"];
    let libraries=List.concat_map(fun rel->let directory=toolchain^"/"^rel in
      check_parents(directory^"/META");
      list_bounded directory 2048 |> List.filter library_name |> List.map(fun name->let path=rel^"/"^name in
        let b=hash_file ~deadline ~single:false ~cap:max_binary(toolchain^"/"^path)in {b with path}))library_dirs in
    need(List.length libraries<=1024)Resource_bound;
    let deps=binaries@libraries in need(List.fold_left(fun n b->n+b.bytes)0 deps<=512*1024*1024)Resource_bound;
    let nix=List.map(fun(path,expected)->
      need(realpath path=path && (lstat path).st_perm land 0o222=0)Toolchain_mismatch;
      let b=hash_file ~owner:0 ~deadline ~single:false ~cap:max_binary path in
      need(b.sha=expected)Toolchain_mismatch;b)nix_inputs in
    let json=`Assoc["schema",s"uos.native-build-inputs.v3";"source_root",s source_root;"toolchain_root",s toolchain_root;
      "sources",`List(List.map(fun(b,_)->binding_json b)src);"toolchain",`List(List.map binding_json deps);
      "nix_inputs",`List(List.map binding_json nix);
      "recipe_sha256",s(digest(encoded recipe));"ocaml_version",s"5.5.0";"dune_version",s"3.23.1"]in
    need(String.length(encoded json)<=max_manifest-4096)Resource_bound;
    {source_root;toolchain_root;toolchain;src;deps;json;input_id=digest(encoded json);deadline}
  let environment i=Astring.String.Map.of_list[
    "PATH",i.toolchain^"/bin:"^i.toolchain_root^"/toolchains/nix-profile/bin:/usr/bin:/bin";
    "OCAMLLIB",i.toolchain^"/lib/ocaml";"OCAMLPATH",i.toolchain^"/lib";
    "DUNE_CACHE","disabled";"LANG","C.UTF-8";"TZ","UTC";"SOURCE_DATE_EPOCH","0"]
  let run i ~process ~timeout ~limit exe args=
    need(now()<i.deadline)Resource_bound;
    let timeout=min timeout(int_of_float((i.deadline-.now())*.1000.))in
    need(timeout>0)Resource_bound;
    let argv=[i.toolchain^"/bin/ocaml";"-I";"+unix";process;
      string_of_int timeout;string_of_int limit;"merged";exe]@args in
    let out=Bos.OS.Cmd.run_out ~env:(environment i)(Bos.Cmd.of_list argv) |> Bos.OS.Cmd.out_string in
    match out with Error _->raise(Hold Build_failed)|Ok(text,(_,status))->
      need(String.length text<=limit)Resource_bound;text,(match status with `Exited n->n|_->125)
  let base i=i.source_root^"/var/ecology/native-builds"
  let ensure_base i=
    mkdir ~private_mode:false(i.source_root^"/var");mkdir ~private_mode:false(i.source_root^"/var/ecology");
    mkdir(base i);List.iter(fun name->mkdir(base i^"/"^name))["cas";"inputs";"work"]
  let with_lock i f=
    let path=base i^"/lock"in
    if not(exists path)then write_new path "";
    let st=lstat path in need(st.st_kind=S_REG && st.st_nlink=1 && st.st_uid=geteuid() && st.st_perm=0o600)Unsafe_file;
    let fd=openfile path[O_RDWR;O_NONBLOCK;O_CLOEXEC]0 in
    Fun.protect ~finally:(fun()->close fd)(fun()->need(same st(fstat fd) && same st(lstat path))Unsafe_file;lockf fd F_TLOCK 0;f())
  type artifact={id:string;dir:string;worker_hash:string;guardian_hash:string;release_hash:string;launcher_hash:string}
  let artifact_id a=a.id and directory a=a.dir
  let worker a=a.dir^"/worker.exe" and guardian a=a.dir^"/guardian.exe" and manifest a=a.dir^"/manifest.json"
  let worker_sha256 a=a.worker_hash and guardian_sha256 a=a.guardian_hash
  let release_worker a=a.dir^"/release_grants_worker.exe"
  let release_worker_sha256 a=a.release_hash
  let launcher a=a.dir^"/finite_launcher.exe"
  let launcher_sha256 a=a.launcher_hash
  let dynamic_executables=["worker.exe";"guardian.exe";"release_grants_worker.exe"]
  let executables=dynamic_executables@["finite_launcher.exe"]
  let runtime_files=List.map(fun(n,_,_)->"runtime/"^n)runtime_sources
  let payload_files _=executables@["manifest.json"]@runtime_files
  let output_json i dir=
    List.map(fun name->let path=dir^"/"^name in let b=hash_file ~deadline:i.deadline ~single:true ~cap:max_binary path in
      need((lstat path).st_perm=0o555)Invalid_artifact;{b with path=name})executables
  let runtime_json i dir=
    let files=List.map(fun path->let b=hash_file ~deadline:i.deadline ~single:true ~cap:max_binary(dir^"/"^path)in
      need((lstat b.path).st_perm=0o444)Invalid_artifact;binding_json{b with path})runtime_files in
    `Assoc["external_loader",binding_json(hash_file ~owner:0 ~deadline:i.deadline ~single:false ~cap:max_binary loader);
      "files",`List files;"activation",s"HOLD: opt-in finite launcher is not runtime adoption; immutable owner paths, trusted BEAM startup and independently managed Nix loader release lifetime unverified; no admission"]
  let manifest_json i dir outputs=`Assoc["schema",s"uos.native-build.v3";"inputs",i.json;"recipe",recipe;
    "runtime",runtime_json i dir;"outputs",`List(List.map binding_json outputs);"authority",s"NONE";"admitted",`Bool false]
  let elf_tool i args=
    let out,code=run i ~process:(i.source_root^"/tools/ecology_process.ml") ~timeout:2000 ~limit:8192 patchelf args in
    need(code=0)Invalid_artifact;String.trim out
  let needed i file=let text=elf_tool i["--print-needed";file]in
    if text=""then[]else let xs=String.split_on_char '\n' text in need(List.length xs<=8)Resource_bound;xs
  let runtime_target _worker name=
    if name="ld-linux-x86-64.so.2"||name=loader then loader else
    let name=if String.starts_with ~prefix:"$ORIGIN/" name then Filename.basename name else name in
    let name=if name="libsqlite3.so"||name=sqlite^"libsqlite3.so.3.53.3"then"libsqlite3.so.0"else name in
    need(List.exists(fun(n,_,_)->n=name)runtime_sources)Invalid_artifact;
    name
  (* Loader version-map lookup requires exact DT_NEEDED/Verneed identities.
     Literal ORIGIN DT_NEEDED is expanded before that lookup and failed an
     actual glibc assertion even when Verneed used the target SONAME. Use bare
     SONAME identities and an exact owned RUNPATH instead.
     Only that four-byte reference is adapted to an existing dynstr entry.
     Version hashes/names/indices and all other bytes remain.
     Closed ELF64LE/x86_64 structural parser; unsupported/extended headers are
     HOLD. Section-table versus loader PT_DYNAMIC/DT_STRTAB correspondence is
     NOT proved by this parser; actual bounded startup is separate evidence. *)
  let elf_versions text=
    let len=String.length text in
    let span p n=need(p>=0 && n>=0 && p<=len-n)Invalid_artifact in
    let byte p=span p 1;Char.code text.[p]in
    let u16 p=byte p lor(byte(p+1)lsl 8)in
    let u32 p=span p 4;let n=ref 0L in for k=0 to 3 do n:=Int64.logor !n(Int64.shift_left(Int64.of_int(byte(p+k)))(8*k))done;!n in
    let small n=need(n>=0L && n<=Int64.of_int max_binary)Invalid_artifact;Int64.to_int n in
    let u64 p=span p 8;let n=ref 0L in for k=0 to 7 do n:=Int64.logor !n(Int64.shift_left(Int64.of_int(byte(p+k)))(8*k))done;small !n in
    span 0 64;need(String.sub text 0 6="\127ELF\002\001" && u16 18=62)Invalid_artifact;
    let shoff=u64 40 and width=u16 58 and count=u16 60 in
    need(width=64 && count>0 && count<=512)Invalid_artifact;span shoff(count*64);
    let section n=need(n>=0 && n<count)Invalid_artifact;shoff+n*64 in
    let sections=List.init count section in
    let dynamics=List.filter(fun p->u32(p+4)=6L)sections in
    let dyn=match dynamics with [p]->p|_->raise(Hold Invalid_artifact)in
    let start=u64(dyn+24)and size=u64(dyn+32)in
    need(size mod 16=0 && size<=8192)Invalid_artifact;span start size;
    let strings=section(small(u32(dyn+40)))in
    let str_start=u64(strings+24)and str_size=u64(strings+32)in
    need(str_size<=1048576)Resource_bound;span str_start str_size;
    let string_at n=need(n>=0 && n<str_size)Invalid_artifact;
      let rec ending k=need(k<str_size && k-n<=1024)Invalid_artifact;
        if text.[str_start+k]='\000'then k else ending(k+1)in
      String.sub text(str_start+n)(ending n-n)in
    let rec dynamic k acc=
      need(k<size/16)Invalid_artifact;let p=start+k*16 in
      if u32 p=0L && u32(p+4)=0L then(
        (* The loader stops at FIRST DT_NULL. Refuse hidden trailing entries
           and noncanonical nonzero NULL values rather than inspect past it. *)
        need(String.for_all((=)'\000')(String.sub text p(start+size-p)))Invalid_artifact;
        List.rev acc)
      else let acc=if u32 p=1L && u32(p+4)=0L then
        let index=u64(p+8)in (string_at index,index)::acc else acc in dynamic(k+1)acc in
    let needed=dynamic 0 []in
    need(List.length needed<=8)Invalid_artifact;
    let versions=List.filter(fun p->u32(p+4)=0x6ffffffeL)sections in
    let references=match versions with []->[]|[p]->
      need(small(u32(p+40))=small(u32(dyn+40)))Invalid_artifact;
      let lo=u64(p+24)and bytes=u64(p+32)in span lo bytes;
      let rec walk at n acc=need(n<64 && at>=lo && at+16<=lo+bytes && u16 at=1)Invalid_artifact;
        let name=string_at(small(u32(at+4)))and next=small(u32(at+12))in
        let acc=(at+4,name)::acc in
        if next=0 then List.rev acc else(need(next>=16)Invalid_artifact;walk(at+next)(n+1)acc)in
      walk lo 0 []
      |_->raise(Hold Invalid_artifact)in
    let locate name=let width=String.length name in
      let rec loop k=need(k+width<str_size)Invalid_artifact;
        if (k=0||text.[str_start+k-1]='\000') && text.[str_start+k+width]='\000'
          && String.sub text(str_start+k)width=name then k else loop(k+1)in loop 0 in
    needed,references,locate
  let version_name name=if name=loader then loader else Filename.basename name
  let retarget_versions ~worker text=
    let ns,refs,locate=elf_versions text and bytes=Bytes.of_string text in
    List.iter(fun(pos,old)->let target=if List.mem_assoc old ns then old else runtime_target worker old in
      need(List.mem_assoc target ns)Invalid_artifact;
      let index=locate(version_name target)in
      for k=0 to 3 do Bytes.set bytes(pos+k)(Char.chr((index lsr(8*k))land 255))done)refs;
    Bytes.to_string bytes
  let verify_versions text=let ns,refs,_=elf_versions text in
    need(List.for_all(fun(_,name)->List.mem_assoc name ns)refs)Invalid_artifact
  let test_retarget_versions ~worker text=protect(fun()->retarget_versions ~worker text)
  let test_verify_versions text=protect(fun()->verify_versions text)
  let patch_elf i ~worker file=
    List.iter(fun name->ignore(elf_tool i["--replace-needed";name;runtime_target worker name;file]))(needed i file);
    ignore(elf_tool i["--set-rpath";(if worker then "$ORIGIN/runtime"else "$ORIGIN");file]);
    ignore(elf_tool i["--no-default-lib";file]);
    if not worker then ignore(elf_tool i["--set-soname";Filename.basename file;file]);
    if worker then ignore(elf_tool i["--set-interpreter";loader;file]);
    let _,old=read_source ~deadline:i.deadline file max_binary in
    let fixed=retarget_versions ~worker old in
    let fd=openfile file[O_WRONLY;O_CLOEXEC]0 in
    Fun.protect ~finally:(fun()->close fd)(fun()->let rec write_all n=if n<String.length fixed then
      let count=write_substring fd fixed n(String.length fixed-n)in need(count>0)Io_failure;write_all(n+count)in
      write_all 0;fsync fd);
    verify_versions fixed
  let verify_elf i dir=
    List.iter(fun rel->let file=dir^"/"^rel and worker=List.mem rel executables in
      need(elf_tool i["--print-rpath";file]=(if worker then "$ORIGIN/runtime"else "$ORIGIN"))Invalid_artifact;
      let dynamic,code=run i ~process:(i.source_root^"/tools/ecology_process.ml") ~timeout:2000 ~limit:16384 nix_readelf ["--dynamic";"--wide";file]in
      need(code=0 && Astring.String.is_infix ~affix:"NODEFLIB" dynamic &&
        Astring.String.is_infix ~affix:"(RUNPATH)" dynamic &&
        not(Astring.String.is_infix ~affix:"(RPATH)" dynamic))Invalid_artifact;
      if not worker then need(elf_tool i["--print-soname";file]=Filename.basename file)Invalid_artifact;
      if worker then need(elf_tool i["--print-interpreter";file]=loader)Invalid_artifact;
      let ns=needed i file in
      let _,text=read_source ~deadline:i.deadline file max_binary in verify_versions text;
      let allowed=loader::List.map(fun(n,_,_)->n)runtime_sources in
      need(ns<>[] && List.for_all(fun n->List.mem n allowed)ns)Invalid_artifact;
      if rel="release_grants_worker.exe"then need(List.mem "libsqlite3.so.0" ns)Invalid_artifact
    )(dynamic_executables@runtime_files)
  let verify_static i dir=
    let _,text=read_source ~deadline:i.deadline(dir^"/finite_launcher.exe")max_binary in
    let len=String.length text in
    let u off count=need(off>=0 && off<=len-count)Invalid_artifact;
      let x=ref 0 in for k=count-1 downto 0 do
        need(!x<=max_int lsr 8)Invalid_artifact;x:=(!x lsl 8)lor Char.code text.[off+k] done;!x in
    need(len>=64 && String.sub text 0 7="\127ELF\002\001\001" && u 16 2=2 && u 18 2=62)Invalid_artifact;
    let offset=u 32 8 and count=u 56 2 and entry=u 24 8 in
    need(u 54 2=56 && count>0 && count<=64 && offset<=len-count*56)Invalid_artifact;
    let executable_entry=ref false in
    for j=0 to count-1 do let p=offset+j*56 in let kind=u p 4 in
      need(kind<>2 && kind<>3)Invalid_artifact; (* PT_DYNAMIC / PT_INTERP *)
      if kind=1 then(let fileoff=u(p+8)8 and va=u(p+16)8 and bytes=u(p+32)8 in
        need(fileoff<=len-bytes)Invalid_artifact;
        if u(p+4)4 land 1<>0 && entry>=va && entry-va<bytes then executable_entry:=true)
    done;need !executable_entry Invalid_artifact
  let runtime_smoke i dir=
    List.iter(fun name->
      let out,code=run i ~process:(i.source_root^"/tools/ecology_process.ml") ~timeout:2000 ~limit:8192(dir^"/"^name)[]in
      need(code=(if name="guardian.exe"then 125 else 0))Runtime_unavailable;
      if name<>"guardian.exe"then(
        need(String.length out>=4)Runtime_unavailable;
        let count=ref 0 in for k=0 to 3 do count:=(!count lsl 8)lor Char.code out.[k]done;
        need(!count=String.length out-4)Runtime_unavailable;
        let body=Yojson.Safe.from_string(String.sub out 4 !count)in
        need(Yojson.Safe.Util.member "status"body=`String"hold")Runtime_unavailable)
    )dynamic_executables;
    let out,code=run i ~process:(i.source_root^"/tools/ecology_process.ml") ~timeout:2000 ~limit:8192(dir^"/finite_launcher.exe")[]in
    need(code=127 && out="")Runtime_unavailable
  let verify_loaded i id=
    need(hex id)Invalid_artifact;let dir=base i^"/cas/"^id in
    let st=lstat dir in need(st.st_kind=S_DIR && st.st_uid=geteuid() && st.st_perm=0o555 && realpath dir=dir)Invalid_artifact;
    need(list_bounded dir 7=["finite_launcher.exe";"guardian.exe";"manifest.json";"release_grants_worker.exe";"runtime";"worker.exe"])Invalid_artifact;
    need((lstat(dir^"/runtime")).st_kind=S_DIR && (lstat(dir^"/runtime")).st_perm=0o555 &&
      list_bounded(dir^"/runtime")(List.length runtime_sources+1)=List.sort String.compare(List.map(fun(n,_,_)->n)runtime_sources))Invalid_artifact;
    let outputs=output_json i dir in
    let text=encoded(manifest_json i dir outputs)in
    let _,actual=read_source ~deadline:i.deadline(dir^"/manifest.json")max_manifest in
    need((lstat(dir^"/manifest.json")).st_perm=0o444 && actual=text && digest actual=id)Invalid_artifact;
    (* Authenticate EVERY observed executable and runtime-library byte against
       the separately retained artifact ID BEFORE any artifact execution.
       This ordering is necessary, not a hostile same-UID TOCTOU defence. *)
    verify_elf i dir;verify_static i dir;
    runtime_smoke i dir;
    {id;dir;worker_hash=(List.hd outputs).sha;guardian_hash=(List.nth outputs 1).sha;release_hash=(List.nth outputs 2).sha;launcher_hash=(List.nth outputs 3).sha}
  let verify ~source_root ~toolchain_root ~artifact_id=protect(fun()->let i=snapshot source_root toolchain_root in verify_loaded i artifact_id)
  let input_current i=
    let next=snapshot ~deadline:i.deadline i.source_root i.toolchain_root in need(encoded next.json=encoded i.json)Source_mismatch
  let build_internal observer ~source_root ~toolchain_root=protect(fun()->
    let i=snapshot source_root toolchain_root in ensure_base i;
    with_lock i(fun()->
      let index=base i^"/inputs/"^i.input_id in
      if exists index then(
        let _,text=read_source ~deadline:i.deadline index 65 in
        need((lstat index).st_perm=0o444 && String.length text=65 && text.[64]='\n')Artifact_conflict;
        let id=String.sub text 0 64 in need(hex id)Artifact_conflict;
        verify_loaded i id
      )else(
        let stage=base i^"/work/"^i.input_id in need(not(exists stage))Partial_exists;
        mkdir stage;let project=stage^"/project"and publish=stage^"/publish"in mkdir project;mkdir publish;
        let source rel=try List.assoc rel(List.map(fun(b,text)->b.path,text)i.src)with Not_found->raise(Hold Source_mismatch)in
        let process=stage^"/ecology_process.ml"in
        write_new process(source "tools/ecology_process.ml");
        let transformed_kernel=transformed Kernel(source "tools/ecology_file_transaction.ml")
        and transformed_port=transformed Port(source "tools/ecology_file_transaction_port.ml")
        and transformed_guardian=transformed Guardian(source "tools/telegram_store_transport_guardian.ml")in
        List.iter(fun(name,text)->write_new(project^"/"^name)text)[
          "port_impl.ml",transformed_kernel^transformed_port;"worker.ml",worker_entry;"guardian.ml",transformed_guardian;
          "dune-project",dune_project;"dune-workspace",dune_workspace;"dune",dune_recipe];
        List.iter(fun(name,_)->let base=Filename.basename name in
          write_new(project^"/"^(if base="ecology_release_grants_port.ml"then"release_grants_worker.ml"else base))(source name))
          (List.filter(fun(p,_)->String.starts_with ~prefix:hermes p)sources);
        let version,code=run i ~process ~timeout:3000 ~limit:4096(i.toolchain^"/bin/ocamlc.opt")["-version"]in
        need(code=0 && String.trim version="5.5.0")Toolchain_mismatch;
        let version,code=run i ~process ~timeout:3000 ~limit:4096(i.toolchain^"/bin/dune")["--version"]in
        need(code=0 && String.trim version="3.23.1")Toolchain_mismatch;
        let log,code=run i ~process ~timeout:50000 ~limit:1048576(i.toolchain^"/bin/dune")
          ["build";"--root";project;"--build-dir";project^"/_build";"--workspace";project^"/dune-workspace";
           "--no-config";"--disable-promotion";"-j1";"worker.exe";"guardian.exe";"release_grants_worker.exe"]in
        write_new(stage^"/build.log")log;need(code=0)Build_failed;
        write_new(project^"/finite_environment_launch.c")(source "native/c/finite_environment_launch.c");
        let log,code=run i ~process ~timeout:5000 ~limit:16384 nix_gcc
          (launcher_flags@[project^"/finite_environment_launch.c";"-o";project^"/_build/default/finite_launcher.exe"])in
        write_new(stage^"/launcher-build.log")log;need(code=0)Build_failed;
        List.iter(fun name->let path=project^"/_build/default/"^name in
          let _,body=read_source ~deadline:i.deadline path max_binary in
          write_new(publish^"/"^name)body)executables;
        mkdir(publish^"/runtime");
        List.iter(fun(name,path,_)->
          let fd=openfile path[O_RDONLY;O_CLOEXEC]0 in let bytes=Bytes.create((fstat fd).st_size)in
          Fun.protect ~finally:(fun()->close fd)(fun()->let rec read_all n=if n<Bytes.length bytes then let got=read fd bytes n(Bytes.length bytes-n)in need(got>0)Io_failure;read_all(n+got)in read_all 0);
          write_new(publish^"/runtime/"^name)(Bytes.to_string bytes))runtime_sources;
        List.iter(fun name->patch_elf i ~worker:false(publish^"/"^name);chmod(publish^"/"^name)0o444)runtime_files;
        List.iter(fun name->patch_elf i ~worker:true(publish^"/"^name);chmod(publish^"/"^name)0o555)dynamic_executables;
        chmod(publish^"/finite_launcher.exe")0o555;
        chmod(publish^"/runtime")0o555;fsync_dir(publish^"/runtime");verify_elf i publish;verify_static i publish;runtime_smoke i publish;
        let outputs=output_json i publish in let text=encoded(manifest_json i publish outputs)in
        need(String.length text<=max_manifest)Resource_bound;
        let id=digest text in write_new ~mode:0o444(publish^"/manifest.json")text;
        observer();input_current i;
        let destination=base i^"/cas/"^id in need(not(exists destination))Artifact_conflict;
        (* Cross-parent directory rename needs owner write permission to update
           '..' on Linux. A crash before the following chmod leaves a private
           incomplete artifact which verify MUST refuse, never a ready marker. *)
        fsync_dir publish;rename publish destination;chmod destination 0o555;
        fsync_dir destination;fsync_dir(base i^"/cas");
        let artifact=verify_loaded i id in
        write_new ~mode:0o444(stage^"/input-index")(id^"\n");
        link(stage^"/input-index")index;unlink(stage^"/input-index");fsync_dir stage;fsync_dir(base i^"/inputs");
        artifact)))
  let build ~source_root ~toolchain_root=build_internal(fun()->())~source_root ~toolchain_root
  let test_build_before_publication observer ~source_root ~toolchain_root=build_internal observer ~source_root ~toolchain_root
  let to_json a=`Assoc["schema",s"uos.native-build-result.v1";"status",s"BUILT_OR_VERIFIED";"artifact_id",s a.id;
    "directory",s a.dir;"worker",s(worker a);"guardian",s(guardian a);"manifest",s(manifest a);
    "worker_sha256",s a.worker_hash;"guardian_sha256",s a.guardian_hash;
    "release_worker",s(release_worker a);"release_worker_sha256",s a.release_hash;
    "launcher",s(launcher a);"launcher_sha256",s a.launcher_hash;"architecture",s"linux-x86_64";"launch_profile",s"native-storage-v1";
    "payload_files",`List(List.map s(payload_files a));"authority",s"NONE";"admitted",`Bool false]
end
let ()=if Filename.basename Sys.argv.(0)="ecology_native_build.ml"then(
  let result=match Array.to_list Sys.argv with
    |[_;"build";source_root;toolchain_root]->Native_build.build ~source_root ~toolchain_root
    |[_;"verify";source_root;toolchain_root;artifact_id]->Native_build.verify ~source_root ~toolchain_root ~artifact_id
    |_->Error Native_build.Invalid_root in
  match result with Ok a->print_endline(Yojson.Safe.to_string(Native_build.to_json a))
  |Error e->print_endline(Yojson.Safe.to_string(`Assoc["status",`String"HOLD";"detail",`String(Native_build.error_label e);"authority",`String"NONE";"admitted",`Bool false]));exit 2)
