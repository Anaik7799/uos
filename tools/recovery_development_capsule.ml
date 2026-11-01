#use "topfind";;
#require "bos,yojson,cryptokit";;

(* DEVELOPMENT bundle, deliberately NOT an ecology release/native artifact.
   Fixed data-port/owner roles; no DB/WAL/SHM, locator/config, fixture seed or
   preparation/helper executable is copied. Baseline Store library functions
   may remain inert in the ELF, but the port exposes no initializer/signer.
   This helper performs bounded local assembly/verification ONLY, never launch,
   install, grant, task or configuration changes. Captured source bytes and
   output hashes do not prove full build/runtime closure. Trusted same-UID
   ownership/freeze, regular local filesystem and independent expected digest
   retention are premises. Nix interpreter/DSOs and BEAM dependencies external. *)
module Development_capsule : sig
 type t
 val identifier : t -> string
 val directory : t -> string
 val assemble_data : source_root:string -> build_root:string -> beam_root:string ->
   launcher:string -> (t,string)result
 val verify_data : directory:string -> expected_identifier:string -> (t,string)result
 val source_catalog : string -> string list
end = struct
 type t={id:string;dir:string}
 let identifier t=t.id
 let directory t=t.dir
 let need b s=if not b then failwith s
 let maximum_file=67108864
 let maximum_total=134217728
 let max_manifest=4194304
 let sha s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
 let safe p=String.length p>0&&String.length p<=4096&&p.[0]<>'/'&&not(String.contains p '\000')&&
  List.for_all(fun s->s<>""&&s<>"."&&s<>"..")(String.split_on_char '/'p)
 let hex s=String.length s=64&&String.for_all(function '0'..'9'|'a'..'f'->true|_->false)s
 let abs p=String.length p>1&&p.[0]='/'&&not(String.contains p '\000')&&Unix.realpath p=p
 let inside root path=String.starts_with~prefix:(root^"/")path
 let canon j=
  let rec f=function `Assoc xs->`Assoc(List.sort compare(List.map(fun(k,v)->k,f v)xs))|`List xs->`List(List.map f xs)|v->v in
  Yojson.Safe.to_string(f j)
 let fields expected=function `Assoc fs as j->
  need(List.sort String.compare(List.map fst fs)=List.sort String.compare expected)"closed manifest";j
  |_->failwith"object required"
 let text j k=Yojson.Safe.Util.(to_string(member k j))
 let stat p=let s=Unix.lstat p in
  need(s.Unix.st_kind=Unix.S_REG&&s.Unix.st_uid=Unix.geteuid()&&s.Unix.st_nlink=1&&s.Unix.st_size>=0&&s.Unix.st_size<=maximum_file)"file metadata";s
 let read ?(cap=maximum_file) p=
  need(cap>=0&&cap<=maximum_file)"read cap";
  let before=stat p in need(before.Unix.st_size<=cap)"preopen size cap";
  let c=open_in_bin p in
  Fun.protect~finally:(fun()->close_in c)(fun()->
   let opened=Unix.fstat(Unix.descr_of_in_channel c)in
   (* Recheck the OPEN descriptor before allocating. A same-inode growth from
      lstat to open cannot bypass cap; later growth allocates only this bounded
      length and is rejected by the one-byte EOF/readback checks below. This
      bounds payload read length, not total OCaml heap/RSS or physical I/O. *)
   need(before.Unix.st_dev=opened.Unix.st_dev&&before.Unix.st_ino=opened.Unix.st_ino
    &&opened.Unix.st_kind=Unix.S_REG&&opened.Unix.st_uid=Unix.geteuid()&&opened.Unix.st_nlink=1
    &&opened.Unix.st_size>=0&&opened.Unix.st_size<=cap&&opened.Unix.st_size=before.Unix.st_size)"source swapped/size changed";
   let s=really_input_string c opened.Unix.st_size in
   (try ignore(input_char c);failwith"grew"with End_of_file->());
   let after=Unix.fstat(Unix.descr_of_in_channel c)in
   need(opened.Unix.st_size=after.Unix.st_size&&opened.Unix.st_mtime=after.Unix.st_mtime&&opened.Unix.st_ctime=after.Unix.st_ctime)"source changed";s)
 let mkdir p=match Bos.OS.Dir.create~path:true~mode:0o700(Fpath.v p)with Ok _->()|_->failwith"mkdir"
 let write p s mode=
  let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
  let c=Unix.out_channel_of_descr fd in
  Fun.protect~finally:(fun()->close_out c)(fun()->output_string c s;flush c;Unix.fchmod fd mode;Unix.fsync fd)
 let syncdir p=let fd=Unix.openfile p[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
  Fun.protect~finally:(fun()->Unix.close fd)(fun()->Unix.fsync fd)
 let rec walk root rel depth=
  need(depth<=16)"tree depth";
  let p=if rel=""then root else root^"/"^rel in
  match(Unix.lstat p).Unix.st_kind with
  |Unix.S_REG->need(safe rel)"relative file";[rel]
  |Unix.S_DIR->Sys.readdir p|>Array.to_list|>List.sort String.compare|>List.concat_map(fun n->walk root(if rel=""then n else rel^"/"^n)(depth+1))
  |_->failwith"unsupported source entry"
 let source_catalog root=
  let base="engines/hermes/modules/sa_plan"in
  let native=walk(root^"/"^base)""0|>List.filter(fun p->
   List.mem(Filename.extension p)[".ml";".mli";".inc";".c";".h";".gospel"]||
   List.mem(Filename.basename p)["dune";"dune-project";"reviewed-dependencies.sha256"])
   |>List.map(fun p->base^"/"^p)in
  native@[
   "apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_owner.gleam";
   "apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_owner_store.gleam";
   "apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_factual_reply.gleam";
   "apps/cepaf_gleam/test/fixtures/recovery_owner_fixture_extension.gleam.inc";
   "apps/cepaf_gleam/src/cepaf_gleam/harness/native_launch.gleam";
   "apps/cepaf_gleam/src/telegram_store_transport_ffi.erl";
   "native/c/finite_environment_launch.c";
   "tools/telegram_store_transport_guardian.ml";"tools/ecology_release.ml";
   "tools/recovery_development_capsule.ml";"tools/validation/recovery_capsule_fixture.ml"]
  |>List.sort_uniq String.compare
 let source_entries root=
  let names=source_catalog root in need(List.length names<=1024)"source count";
  let total=ref 0 in
  List.map(fun p->need(safe p&&inside root(Unix.realpath(root^"/"^p)))"source escape";
   let b=read(root^"/"^p)in total:= !total+String.length b;need(!total<=maximum_total)"source total";
   `Assoc["path",`String p;"sha256",`String(sha b);"bytes",`Int(String.length b)])names
 let inventory=[
  "DATA_ONLY_RECOVERY_PORT","native/recovery_data.exe",0o555;
  "UNCHANGED_PRODUCTION_HOLD_PORT","native/production_hold.exe",0o555;
  "FACTUAL_JOURNAL_PORT","native/journal.exe",0o555;
  "BOUNDED_GUARDIAN","native/guardian.exe",0o555;
  "FINITE_ENVIRONMENT_LAUNCHER","native/finite_launcher.exe",0o555;
  "DEVELOPMENT_OWNER_BEAM","beam/cepaf_gleam@harness@recovery_owner.beam",0o444;
  "FACTUAL_JOURNAL_CLIENT_BEAM","beam/cepaf_gleam@harness@recovery_owner_store.beam",0o444;
  "FACTUAL_REPLY_DECODER_BEAM","beam/cepaf_gleam@harness@recovery_factual_reply.beam",0o444]
 let marker="THIS_IS_NOT_A_RELEASE"
 let marker_bytes="UOS DEVELOPMENT RECOVERY BUNDLE ONLY\nNO RELEASE AUTHORITY OR PRODUCTION ADMISSION\n"
 let roles=List.map(fun(r,p,m)->r,p,m)inventory
 let verify_data~directory~expected_identifier=
  try need(hex expected_identifier&&abs directory)"expected identity/root";
  let st=Unix.lstat directory in need(st.Unix.st_kind=Unix.S_DIR&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_perm=0o555)"bundle mode";
  let bytes=read~cap:max_manifest(directory^"/development-manifest.json")in need(sha bytes=expected_identifier)"independent expected identity mismatch";
  let j=Yojson.Safe.from_string bytes|>fields["schema";"kind";"authority";"application_admitted";"system_admitted";"files";"source_inputs";"external_runtime"]in
  need(canon j=bytes&&text j"schema"="uos.recovery-development-bundle.v1"&&text j"kind"="DEVELOPMENT_ONLY_NOT_RELEASE"
   &&text j"authority"="NONE"&&Yojson.Safe.Util.member"application_admitted"j=`Bool false&&Yojson.Safe.Util.member"system_admitted"j=`Bool false)"development classification";
  need(text j"external_runtime"="NIX_INTERPRETER_DSOS_AND_BEAM_DEPENDENCIES_EXTERNAL_NOT_PACKAGED")"runtime scope";
  let inputs=Yojson.Safe.Util.(to_list(member"source_inputs"j))in
  need(List.length inputs>0&&List.length inputs<=1024)"source inventory bound";
  let paths=List.map(fun v->let v=fields["path";"sha256";"bytes"]v in
   let path=text v"path"and count=Yojson.Safe.Util.(to_int(member"bytes"v))in
   need(safe path&&hex(text v"sha256")&&count>=0&&count<=maximum_file)"source entry";path)inputs in
  need(List.length paths=List.length(List.sort_uniq String.compare paths))"duplicate source path";
  let fs=Yojson.Safe.Util.(to_list(member"files"j))in
  need(List.length fs=List.length inventory)"inventory count";
  let total=ref 0 in List.iter(fun(role,path,mode)->
   let v=List.find(fun v->text v"path"=path)fs|>fields["role";"path";"sha256";"bytes";"mode"]in
   need(text v"role"=role&&Yojson.Safe.Util.(to_int(member"mode"v))=mode)"role/mode mismatch";
   let p=directory^"/"^path in let st=stat p in need(st.Unix.st_perm=mode)"mutable artifact";
   let b=read p in total:= !total+String.length b;need(!total<=maximum_total&&sha b=text v"sha256"&&String.length b=Yojson.Safe.Util.(to_int(member"bytes"v)))"artifact binding")roles;
  need(read(directory^"/"^marker)=marker_bytes&&(stat(directory^"/"^marker)).Unix.st_perm=0o444)"development marker";
  need((stat(directory^"/development-manifest.json")).Unix.st_perm=0o444)"manifest mode";
  List.iter(fun d->let s=Unix.lstat(directory^"/"^d)in need(s.Unix.st_kind=Unix.S_DIR&&s.Unix.st_uid=Unix.geteuid()&&s.Unix.st_perm=0o555)"subdirectory mode")["native";"beam"];
  let names=walk directory""0|>List.sort String.compare in
  need(names=List.sort String.compare(marker::"development-manifest.json"::List.map(fun(_,p,_)->p)roles))"unexpected bundle file";
  Ok{id=expected_identifier;dir=directory}
  with _->Error"DEVELOPMENT_BUNDLE_HOLD"
 let assemble_data~source_root~build_root~beam_root~launcher=
  try need(abs source_root&&abs build_root&&abs beam_root&&abs launcher)"canonical roots";
  let before=source_entries source_root in
  let root=source_root^"/var/development-capsules/recovery"in mkdir root;
  let temporary=root^"/.pending-"^string_of_int(Unix.getpid())^"-"^string_of_int(int_of_float(Unix.gettimeofday()*.1000000.))in
  Unix.mkdir temporary 0o700;mkdir(temporary^"/native");mkdir(temporary^"/beam");
  let source path=match path with
  |"native/recovery_data.exe"->build_root^"/default/store/development/recovery_adapter_data_port.exe"
  |"native/production_hold.exe"->build_root^"/default/fixture/recovery_port.exe"
  |"native/journal.exe"->build_root^"/default/fixture/recovery_owner_journal_port.exe"
  |"native/guardian.exe"->build_root^"/default/fixture/recovery_fixture_guardian.exe"
  |"native/finite_launcher.exe"->launcher
  |p when String.starts_with~prefix:"beam/"p->beam_root^"/"^Filename.basename p
  |_->failwith"fixed role only"in
  let total=ref 0 in
  let fs=List.map(fun(role,path,mode)->let bytes=read(source path)in total:= !total+String.length bytes;need(!total<=maximum_total)"bundle total";
   write(temporary^"/"^path)bytes mode;
   `Assoc["role",`String role;"path",`String path;"sha256",`String(sha bytes);"bytes",`Int(String.length bytes);"mode",`Int mode])roles in
  write(temporary^"/"^marker)marker_bytes 0o444;
  let manifest=`Assoc["schema",`String"uos.recovery-development-bundle.v1";"kind",`String"DEVELOPMENT_ONLY_NOT_RELEASE";
   "authority",`String"NONE";"application_admitted",`Bool false;"system_admitted",`Bool false;
   "files",`List fs;"source_inputs",`List before;
   "external_runtime",`String"NIX_INTERPRETER_DSOS_AND_BEAM_DEPENDENCIES_EXTERNAL_NOT_PACKAGED"]in
  let bytes=canon manifest in need(String.length bytes<=max_manifest)"manifest cap";
  write(temporary^"/development-manifest.json")bytes 0o444;
  need(before=source_entries source_root)"source changed during assembly";
  List.iter(fun d->syncdir(temporary^"/"^d);Unix.chmod(temporary^"/"^d)0o555)["native";"beam"];
  syncdir temporary;Unix.chmod temporary 0o555;
  let id=sha bytes and dir=root^"/"^sha bytes in
  if Sys.file_exists dir then verify_data~directory:dir~expected_identifier:id
  else(Unix.rename temporary dir;syncdir root;verify_data~directory:dir~expected_identifier:id)
  with _->Error"DEVELOPMENT_BUNDLE_ASSEMBLY_HOLD_PARTIAL_RETAINED"
end

(* No implicit CLI/main when imported by the bounded development driver. *)
