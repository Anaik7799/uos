(* DEVELOPMENT-ONLY DATA port: no signer, fixture seed, initializer, task route,
   installed public name or production admission. The adapter's synthetic-path
   restriction is not authentication. Generic transport/configuration is DATA;
   public production owner/port remain unavailable. One ordinary frame only. *)
let marker_lock : Unix.file_descr option ref=ref None
let need b=if not b then failwith"private data port refused"
let marker directory=
 need(String.starts_with~prefix:"/tmp/uos-control-private-"directory&&Filename.dirname directory="/tmp"&&Unix.realpath directory=directory);
 let path=directory^"/worker.pid"in
 let fd=Unix.openfile path[Unix.O_RDWR;Unix.O_CREAT;Unix.O_CLOEXEC]0o600 in
 try let st=Unix.fstat fd and p=Unix.lstat path in
  need(st.Unix.st_kind=Unix.S_REG&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_nlink=1&&st.Unix.st_perm land 0o077=0
   &&st.Unix.st_dev=p.Unix.st_dev&&st.Unix.st_ino=p.Unix.st_ino);
  Unix.lockf fd Unix.F_TLOCK 0;Unix.ftruncate fd 0;
  let bytes=string_of_int(Unix.getpid())in
  let rec put n=if n<String.length bytes then let k=Unix.write_substring fd bytes n(String.length bytes-n)in need(k>0);put(n+k)in
  put 0;Unix.fsync fd;marker_lock:=Some fd
 with e->Unix.close fd;raise e
let response status code=Yojson.Safe.to_string(`Assoc[
 "schema",`String"uos.recovery-adapter.factual.v1";"status",`String status;"code",`String code;
 "authority",`String"NONE";"application_admitted",`Bool false;"system_admitted",`Bool false;"receipt",`Null])
let write_observation directory diagnostics=
 let path=directory^"/bound-observation.json"in
 if not(Sys.file_exists path)then(
 let fd=Unix.openfile path[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
 let oc=Unix.out_channel_of_descr fd in
 Fun.protect~finally:(fun()->close_out oc)(fun()->
  output_string oc(Yojson.Safe.to_string(`Assoc["sqlite_version",`String(Sqlite3.sqlite_version_info());"diagnostics",diagnostics]));
  flush oc;Unix.fsync fd))
let ()=
 let begun=ref false in
 let body=try
  need(Array.length Sys.argv=2);
  let h=really_input_string stdin 4 in let count=ref 0 in String.iter(fun c->count:=(!count lsl 8)lor Char.code c)h;
  need(!count>0&& !count<=65536);let request=really_input_string stdin !count in
  (try ignore(input_char stdin);failwith"trailing"with End_of_file->());
  let locator=Sys.argv.(1)in let directory=Filename.dirname locator in marker directory;
  begun:=true;
  match Recovery_adapter.handle_private_data~locator~request with
  |Error _->response"UNKNOWN""OUTCOME_OR_OBSERVATION_UNKNOWN"
  |Ok observed->write_observation directory observed.diagnostics;observed.reply
 with _->if !begun then response"UNKNOWN""OUTCOME_OR_OBSERVATION_UNKNOWN"else response"HOLD""FRAME_OR_PRIVATE_NAMESPACE_REFUSED"in
 let n=String.length body in for i=3 downto 0 do output_char stdout(Char.chr((n lsr(8*i))land 255))done;
 output_string stdout body;flush stdout
