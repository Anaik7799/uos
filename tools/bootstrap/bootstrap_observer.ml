(* Read-only interpretation of the EV01 bootstrap observation predicate.
   Filesystem calls assume a responsive local filesystem. Subprocesses share
   a five-second monotonic deadline and 64 KiB aggregate output budget.
   This is a cooperative snapshot check, not an effect-time fencing service. *)
open Bootstrap_model
type marker = Absent of string | Empty_directory of string * int * float * float
type observation = { root : string; revision : string; facts : (fact * bool) list; markers : marker list }
exception Refused of string
let require condition message = if not condition then raise (Refused message)
let mono () = Mtime.Span.to_float_ns (Mtime_clock.elapsed ()) /. 1e9
let jj = "/nix/store/vzrnnii3369cn2a2bgdlkx9gh6m297fj-jujutsu-0.44.0/bin/jj"
let stat path = try Some (Unix.lstat path) with Unix.Unix_error (Unix.ENOENT,_,_) -> None
let directory path = match stat path with Some s -> s.Unix.st_kind = Unix.S_DIR | None -> false
let identity s = s.Unix.st_dev,s.st_ino,s.st_kind,s.st_size,s.st_mtime,s.st_ctime
let marker path = match stat path with
  | None -> Absent path
  | Some before when before.Unix.st_kind=Unix.S_DIR ->
      let directory=Unix.opendir path in
      Fun.protect ~finally:(fun()->Unix.closedir directory)(fun()->
        let rec empty fuel =
          require(fuel>0) "ambiguous Git marker directory";
          match Unix.readdir directory with
          | "." | ".." -> empty(fuel-1)
          | _ -> false
          | exception End_of_file -> true in
        require(empty 3) "nonempty Git metadata directory";
        require(identity before=identity(Unix.lstat path)) "Git marker changed";
        Empty_directory(path,before.st_perm,before.st_mtime,before.st_ctime))
  | Some _ -> raise(Refused "Git metadata file or symlink")
let read_small path =
  let before = Unix.lstat path in
  require (before.st_kind=Unix.S_REG && before.st_size<=4096) "nonregular or oversized metadata";
  let fd=Unix.openfile path [Unix.O_RDONLY;Unix.O_NONBLOCK;Unix.O_CLOEXEC] 0 in
  Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
    require(identity before=identity(Unix.fstat fd))"metadata identity changed";
    let bytes=Bytes.create before.st_size in
    let rec fill offset=if offset<Bytes.length bytes then (
      let n=Unix.read fd bytes offset(Bytes.length bytes-offset)in
      require(n>0)"metadata truncated";fill(offset+n))in
    fill 0;
    require(Unix.read fd(Bytes.create 1)0 1=0)"metadata grew";
    require(identity before=identity(Unix.lstat path))"metadata replaced";
    Bytes.to_string bytes)
let kill_group pid = try Unix.kill (-pid) Sys.sigkill with Unix.Unix_error(Unix.ESRCH,_,_)->()
let command deadline remaining config_dir root arguments =
  require(mono()<deadline)"JJ observation deadline";
  let reader,writer=Unix.pipe ~cloexec:true () in
  let error_reader,error_writer=Unix.pipe ~cloexec:true () in
  let argv=Array.of_list(jj::["--ignore-working-copy";"--at-operation";"@";
    "--no-pager";"--color";"never";"-R";root]@arguments)in
  let environment=Array.of_list(
    ["XDG_CONFIG_HOME="^config_dir;"XDG_DATA_HOME="^config_dir;
     "JJ_CONFIG=/dev/null";"LANG=C.UTF-8";"NO_COLOR=1"] @
    (match Sys.getenv_opt "HOME" with None->[]|Some value->["HOME="^value]))in
  let pid=Unix.fork()in
  if pid=0 then (
    try ignore(Unix.setsid());Unix.close reader;Unix.close error_reader;
      let input=Unix.openfile "/dev/null"[Unix.O_RDONLY]0 in
      Unix.dup2 input Unix.stdin;Unix.dup2 writer Unix.stdout;Unix.dup2 error_writer Unix.stderr;
      Unix.close input;Unix.close writer;Unix.close error_writer;Unix.execve jj argv environment
    with _->Unix._exit 127);
  Unix.close writer;Unix.close error_writer;
  Unix.set_nonblock reader;Unix.set_nonblock error_reader;
  let status=ref None and eof=ref false and error_eof=ref false and output=Buffer.create 128 in
  let reap()=match !status with Some _->()|None->
    let found,value=Unix.waitpid[Unix.WNOHANG]pid in if found<>0 then status:=Some value in
  Fun.protect ~finally:(fun()->
    Unix.close reader;Unix.close error_reader;
    kill_group pid;
    match !status with Some _->()|None->ignore(Unix.waitpid[]pid)) (fun()->
    let bytes=Bytes.create 4096 in
    while !status=None || not !eof || not !error_eof do
      require(mono()<deadline)"JJ observation deadline";
      let descriptors=(if !eof then [] else [reader])@(if !error_eof then [] else [error_reader])in
      let ready,_,_=Unix.select descriptors[][](min 0.02(max 0.(deadline-.mono())))in
      List.iter(fun descriptor->
        let n=try Unix.read descriptor bytes 0 4096 with Unix.Unix_error((Unix.EAGAIN|Unix.EWOULDBLOCK),_,_)-> -1 in
        if n=0 then (if descriptor=reader then eof:=true else error_eof:=true) else if n>0 then (
          remaining:= !remaining-n;require(!remaining>=0)"JJ observation output limit";
          if descriptor=reader then Buffer.add_subbytes output bytes 0 n))ready;
      reap()
    done;
    require(!status=Some(Unix.WEXITED 0))"JJ observation failed";
    Buffer.contents output)
let single_line bytes =
  require(String.length bytes>1 && bytes.[String.length bytes-1]='\n')"missing JJ line";
  let value=String.sub bytes 0(String.length bytes-1)in
  require(not(String.contains value '\n') && not(String.contains value '\000'))"ambiguous JJ output";
  value
let fingerprint paths=List.map(fun path->path,Option.map identity(stat path))paths
let remove_private_config path =
  let fuel=ref 64 in
  let rec remove depth path =
    require(depth<8 && !fuel>0)"private config cleanup bound";decr fuel;
    match Unix.lstat path with
    |s when s.Unix.st_kind=Unix.S_DIR ->
      Sys.readdir path |> Array.iter(fun name->remove(depth+1)(path^"/"^name));Unix.rmdir path
    |_->Unix.unlink path in
  remove 0 path
let observe selected =
  let config_dir=ref None in
  Fun.protect ~finally:(fun()->Option.iter remove_private_config !config_dir)(fun()->
  try
    let deadline=mono()+.5. and remaining=ref 65536 in
    let root=Unix.realpath selected in
    require(directory root)"selected root is not a directory";
    let jj_marker=root^"/.jj" in
    require(directory jj_marker && directory(jj_marker^"/working_copy"))"invalid workspace marker";
    ignore(marker(root^"/.git"));
    let locator=jj_marker^"/repo" in
    let repo=match stat locator with
      |Some info when info.st_kind=Unix.S_DIR->Unix.realpath locator
      |Some info when info.st_kind=Unix.S_REG->
        let target=read_small locator in
        require(target<>"" && not(String.contains target '\000') && not(String.contains target '\n'))"invalid repository pointer";
        Unix.realpath(if Filename.is_relative target then jj_marker^"/"^target else target)
      |Some _|None->raise(Refused "invalid repository metadata")in
    require(directory repo && Filename.basename repo="repo" && Filename.basename(Filename.dirname repo)=".jj")"unsupported repository topology";
    let repository_root=Filename.dirname(Filename.dirname repo)in
    let marker_paths=List.sort_uniq String.compare[root^"/.git";repository_root^"/.git"]in
    let markers=List.map marker marker_paths in
    let git=repo^"/store/git" in
    require(directory(repo^"/store") && Unix.realpath(repo^"/store")=repo^"/store" &&
      directory git && Unix.realpath git=git && read_small(repo^"/store/type")="git" &&
      read_small(repo^"/store/git_target")="git")"Git store is not internal";
    let tracked=[root;repository_root;jj_marker;locator;jj_marker^"/working_copy/checkout";jj_marker^"/working_copy/tree_state";
      repo^"/config.toml";repo^"/store/type";repo^"/store/git_target";git;repo^"/op_heads"]@marker_paths in
    let before=fingerprint tracked in
    let private_config=Filename.temp_dir ~temp_dir:"/tmp" "uos-bootstrap-jj-config-"""in
    config_dir:=Some private_config;
    let observed_root=single_line(command deadline remaining private_config root["root"])in
    require(Unix.realpath observed_root=root)"JJ selected root mismatch";
    let observed_git=single_line(command deadline remaining private_config root["git";"root"])in
    require(Unix.realpath observed_git=Unix.realpath git)"JJ internal store mismatch";
    let revision_args=["log";"-r";"@";"--no-graph";"-T";"self.commit_id() ++ \"\\n\""]in
    let revision=single_line(command deadline remaining private_config root revision_args)in
    require((String.length revision=40 || String.length revision=64) &&
      String.for_all(function '0'..'9'|'a'..'f'->true|_->false)revision)"invalid current revision";
    let repeated=single_line(command deadline remaining private_config root revision_args)in
    require(repeated=revision && before=fingerprint tracked && markers=List.map marker marker_paths && mono()<deadline)"repository changed during observation";
    Ok {root;revision;facts=List.map(fun fact->fact,true)facts;markers}
  with
  |Refused reason->Error reason
  |Unix.Unix_error _|Sys_error _->Error "filesystem or process observation unavailable")
