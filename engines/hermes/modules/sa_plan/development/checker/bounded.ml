(* Bounded local I/O. These checks assume a trusted host/filesystem; not a sandbox. *)
open Priority
let same a b =
  a.Unix.st_dev=b.Unix.st_dev && a.st_ino=b.st_ino && a.st_size=b.st_size &&
  a.st_mtime=b.st_mtime && a.st_ctime=b.st_ctime && a.st_kind=b.st_kind
let read ?(limit=1048576) path =
  let before=Unix.stat path in
  require (before.Unix.st_kind=Unix.S_REG) "input is not a regular file";
  require (before.st_size<=limit) "input exceeds byte bound";
  let fd=Unix.openfile path [Unix.O_RDONLY;Unix.O_NONBLOCK;Unix.O_CLOEXEC] 0 in
  Fun.protect ~finally:(fun ()->Unix.close fd) (fun ()->
    require (same before (Unix.fstat fd)) "input changed while opening";
    let bytes=Bytes.create (before.st_size+1) in
    let rec loop offset =
      if offset=Bytes.length bytes then offset
      else let n=Unix.read fd bytes offset (Bytes.length bytes-offset) in
        if n=0 then offset else loop (offset+n) in
    let n=loop 0 in
    require (n=before.st_size && same before (Unix.fstat fd) && same before (Unix.stat path))
      "input changed while reading";
    Bytes.sub_string bytes 0 n)
let json_text s =
  require (String.length s<=1048576) "JSON exceeds 1 MiB";
  let depth=ref 0 and nodes=ref 0 and quoted=ref false and escaped=ref false in
  String.iter (fun c ->
    if !quoted then (
      if !escaped then escaped:=false
      else if c='\\' then escaped:=true else if c='"' then quoted:=false)
    else match c with
      | '"' -> quoted:=true
      | '{'|'[' -> incr depth; incr nodes; require (!depth<=64) "JSON nesting exceeds 64"
      | '}'|']' -> decr depth; require (!depth>=0) "unbalanced JSON"
      | ','|':' -> incr nodes
      | _ -> ();
    require (!nodes<=100000) "JSON token budget exceeded") s;
  require (not !quoted && !depth=0) "unterminated JSON";
  Yojson.Basic.from_string s
let sha256 s =
  Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let safe_relative path =
  require (String.length path>0 && String.length path<=1024 && Filename.is_relative path)
    "evidence path must be bounded and repository-relative";
  let segments=String.split_on_char '/' path in
  List.iter (fun p->
    require (p<>"" && p<>"." && p<>"..") "noncanonical evidence path";
    require (String.for_all (fun c->Char.code c>=32 && Char.code c<127 && c<>'\\' && c<>':') p)
      "invalid evidence path characters";
    let lower=String.lowercase_ascii p in
    require (not (List.mem lower ["var";"state";".jj";".git";".ssh";".aws";"_build";"_opam";
        "secrets";"credentials";"private";"node_modules";"model_weights"]) &&
      not (String.starts_with ~prefix:".env" lower) &&
      not (String.ends_with ~suffix:".sqlite3" lower || String.ends_with ~suffix:".db" lower ||
        String.ends_with ~suffix:".pem" lower || String.ends_with ~suffix:".key" lower ||
        String.ends_with ~suffix:".p12" lower || String.ends_with ~suffix:"-wal" lower ||
        String.ends_with ~suffix:"-shm" lower || String.starts_with ~prefix:"id_rsa" lower ||
        String.starts_with ~prefix:"id_ed25519" lower)) "sensitive/runtime evidence path rejected")
    segments;
  segments
let evidence ~root path =
  let segments=safe_relative path in
  let root=Unix.realpath root in
  let target=List.fold_left (fun base segment ->
    let p=Filename.concat base segment in
    require ((Unix.lstat p).Unix.st_kind<>Unix.S_LNK) "symlink evidence rejected"; p)
    root segments in
  require (Unix.realpath target=target) "noncanonical evidence target";
  let bytes=read target in
  require (Unix.realpath target=target) "evidence path changed";
  bytes

