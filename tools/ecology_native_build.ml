#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos,yojson,cryptokit,mtime.clock.os";;

(* LOCAL Codex relay. @agent_intent: Build only the reviewed public Kernel,
   Port and unchanged guardian with cached pinned tools; never release authority.
   @laws: transformation preserves every byte except the three exact directives;
   all inputs are rechecked before publication; pinned artifact ID covers the
   complete manifest and outputs; unknown/conflicting/partial output is HOLD.
   Owner permissions/index lookup are cooperative, not cryptographic authority.
   A caller must retain artifact_id independently. Existing process guardian
   bounds compiler time/output/group; local regular-FS and frozen same-UID inputs
   are premises. Escaped descendants require a service cgroup. No DB/config,
   package installer, network, arbitrary command, library or source arguments.
   CLI: build SOURCE_ROOT TOOLCHAIN_ROOT | verify SOURCE_ROOT TOOLCHAIN_ROOT ID *)
module Native_build : sig
  type kind = Kernel | Port | Guardian
  type error = Invalid_root | Unsafe_file | Resource_bound | Source_mismatch
    | Unexpected_directive | Invalid_source | Toolchain_mismatch | Build_failed
    | Partial_exists | Artifact_conflict | Invalid_artifact | Io_failure
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
  val build : source_root:string -> toolchain_root:string -> (artifact,error) result
  val verify : source_root:string -> toolchain_root:string -> artifact_id:string -> (artifact,error) result
  (* Library-only fault observer, never a CLI field, command or production hook. *)
  val test_build_before_publication : (unit -> unit) -> source_root:string -> toolchain_root:string -> (artifact,error) result
  val to_json : artifact -> Yojson.Safe.t
end = struct
  open Unix
  type kind=Kernel|Port|Guardian
  type error=Invalid_root|Unsafe_file|Resource_bound|Source_mismatch|Unexpected_directive|Invalid_source
    |Toolchain_mismatch|Build_failed|Partial_exists|Artifact_conflict|Invalid_artifact|Io_failure
  let error_label=function Invalid_root->"invalid_root"|Unsafe_file->"unsafe_file"|Resource_bound->"resource_bound"
    |Source_mismatch->"source_mismatch"|Unexpected_directive->"unexpected_directive"|Invalid_source->"invalid_source"
    |Toolchain_mismatch->"toolchain_mismatch"|Build_failed->"build_failed"|Partial_exists->"partial_exists"
    |Artifact_conflict->"artifact_conflict"|Invalid_artifact->"invalid_artifact"|Io_failure->"io_failure"
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
  let sources=[
    "tools/ecology_file_transaction.ml","64789f843adf44440b8190fd3c6eb8fadba4b5d7d052dd790a33e8375d240cd2";
    "tools/ecology_file_transaction_port.ml","463e6c48bbbee414d5be551ed5485f84ec49a478d2830d888a9f4ee7d20918b6";
    "tools/telegram_store_transport_guardian.ml","9ba03f57d2350c75ab95bfaa36553e637f432bd30e32dffd7db6ce738978d6d5";
    "tools/ecology_process.ml","b8ed1735909701376949b0ca00acd2f4cb8aac177fb771a5c59532319cea249b"]
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
  let hash_file ~deadline ~single ~cap path=
    need(now()<=deadline)Resource_bound;check_parents path;
    let before=lstat path in
    need(before.st_kind=S_REG && before.st_uid=geteuid() && (not single || before.st_nlink=1) && before.st_size>=0 && before.st_size<=cap)Unsafe_file;
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
  let dune_recipe="(library (name port_impl) (modules port_impl) (libraries yojson cryptokit unix))\n(executable (name worker) (modules worker) (libraries port_impl))\n(executable (name guardian) (modules guardian) (libraries unix mtime.clock.os))\n"
  let worker_entry="let ()=Port_impl.Port.main()\n"
  let recipe=`Assoc["dune_project",s dune_project;"dune_workspace",s dune_workspace;"dune",s dune_recipe;"worker",s worker_entry;
    "transform",s"exact_kernel_two_directives_and_port_one_directive_only.v1";"jobs",n 1;"compiler_timeout_ms",n 50000;"output_limit",n 1048576]
  let list_bounded path cap=
    let d=opendir path in Fun.protect ~finally:(fun()->closedir d)(fun()->
      let rec loop count acc=match readdir d with
        |"."|".."->loop count acc
        |name->need(count<cap)Resource_bound;loop(count+1)(name::acc)
        |exception End_of_file->List.sort String.compare acc in loop 0 [])
  let library_dirs=["lib/ocaml";"lib/ocaml/unix";"lib/yojson";"lib/cryptokit";"lib/zarith";"lib/mtime";"lib/mtime/clock"]
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
    let json=`Assoc["schema",s"uos.native-build-inputs.v1";"source_root",s source_root;"toolchain_root",s toolchain_root;
      "sources",`List(List.map(fun(b,_)->binding_json b)src);"toolchain",`List(List.map binding_json deps);
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
  type artifact={id:string;dir:string;worker_hash:string;guardian_hash:string}
  let artifact_id a=a.id and directory a=a.dir
  let worker a=a.dir^"/worker.exe" and guardian a=a.dir^"/guardian.exe" and manifest a=a.dir^"/manifest.json"
  let worker_sha256 a=a.worker_hash and guardian_sha256 a=a.guardian_hash
  let output_json i dir=
    List.map(fun name->let path=dir^"/"^name in let b=hash_file ~deadline:i.deadline ~single:true ~cap:max_binary path in
      need((lstat path).st_perm=0o555)Invalid_artifact;{b with path=name})["worker.exe";"guardian.exe"]
  let manifest_json i outputs=`Assoc["schema",s"uos.native-build.v1";"inputs",i.json;"recipe",recipe;
    "outputs",`List(List.map binding_json outputs);"authority",s"NONE";"admitted",`Bool false]
  let verify_loaded i id=
    need(hex id)Invalid_artifact;let dir=base i^"/cas/"^id in
    let st=lstat dir in need(st.st_kind=S_DIR && st.st_uid=geteuid() && st.st_perm=0o555 && realpath dir=dir)Invalid_artifact;
    need(list_bounded dir 4=["guardian.exe";"manifest.json";"worker.exe"])Invalid_artifact;
    let outputs=output_json i dir in
    let text=encoded(manifest_json i outputs)in
    let _,actual=read_source ~deadline:i.deadline(dir^"/manifest.json")max_manifest in
    need((lstat(dir^"/manifest.json")).st_perm=0o444 && actual=text && digest actual=id)Invalid_artifact;
    {id;dir;worker_hash=(List.hd outputs).sha;guardian_hash=(List.nth outputs 1).sha}
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
        let version,code=run i ~process ~timeout:3000 ~limit:4096(i.toolchain^"/bin/ocamlc.opt")["-version"]in
        need(code=0 && String.trim version="5.5.0")Toolchain_mismatch;
        let version,code=run i ~process ~timeout:3000 ~limit:4096(i.toolchain^"/bin/dune")["--version"]in
        need(code=0 && String.trim version="3.23.1")Toolchain_mismatch;
        let log,code=run i ~process ~timeout:50000 ~limit:1048576(i.toolchain^"/bin/dune")
          ["build";"--root";project;"--build-dir";project^"/_build";"--workspace";project^"/dune-workspace";
           "--no-config";"--disable-promotion";"-j1";"worker.exe";"guardian.exe"]in
        write_new(stage^"/build.log")log;need(code=0)Build_failed;
        List.iter(fun name->let path=project^"/_build/default/"^name in
          let _,body=read_source ~deadline:i.deadline path max_binary in
          write_new ~mode:0o555(publish^"/"^name)body)["worker.exe";"guardian.exe"];
        let outputs=output_json i publish in let text=encoded(manifest_json i outputs)in
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
    "worker_sha256",s a.worker_hash;"guardian_sha256",s a.guardian_hash;"authority",s"NONE";"admitted",`Bool false]
end
let ()=if Filename.basename Sys.argv.(0)="ecology_native_build.ml"then(
  let result=match Array.to_list Sys.argv with
    |[_;"build";source_root;toolchain_root]->Native_build.build ~source_root ~toolchain_root
    |[_;"verify";source_root;toolchain_root;artifact_id]->Native_build.verify ~source_root ~toolchain_root ~artifact_id
    |_->Error Native_build.Invalid_root in
  match result with Ok a->print_endline(Yojson.Safe.to_string(Native_build.to_json a))
  |Error e->print_endline(Yojson.Safe.to_string(`Assoc["status",`String"HOLD";"detail",`String(Native_build.error_label e);"authority",`String"NONE";"admitted",`Bool false]));exit 2)
