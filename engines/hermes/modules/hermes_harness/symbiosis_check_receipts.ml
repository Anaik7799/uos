type error = Invalid_json | Invalid_receipt | Invalid_request | Invalid_path
  | Schema_mismatch | Nested_transaction | Store_unavailable | Resource_bound
  | Conflict | Stale_epoch | Out_of_order | Commit_unknown | Rollback_failed | Closed
let error_code = function
  | Invalid_json -> "invalid_json" | Invalid_receipt -> "invalid_receipt"
  | Invalid_request -> "invalid_request" | Invalid_path -> "invalid_local_path"
  | Schema_mismatch -> "schema_mismatch" | Nested_transaction -> "nested_transaction"
  | Store_unavailable -> "store_unavailable" | Resource_bound -> "resource_bound"
  | Conflict -> "conflicting_replay" | Stale_epoch -> "stale_epoch"
  | Out_of_order -> "out_of_order" | Commit_unknown -> "commit_unknown"
  | Rollback_failed -> "rollback_failed" | Closed -> "closed"
let ( let* ) x f = match x with Ok v -> f v | Error e -> Error e
let require b e = if b then Ok () else Error e
type limits = { max_rows:int; max_db_bytes:int; max_payload_bytes:int }
let default_limits = {max_rows=100_000;max_db_bytes=33_554_432;max_payload_bytes=262_144}
let max_request_bytes = 262_144
let max_response_bytes = 524_288
let sha s = Digestif.SHA256.(to_hex (digest_string s))
exception Bad_json
exception Bad_receipt

let utf8 s =
  let n=String.length s in
  let byte i=Char.code s.[i] in
  let cont i=i<n && byte i>=0x80 && byte i<=0xbf in
  let rec loop i = i=n ||
    let c=byte i in
    if c<0x80 then loop(i+1)
    else if c>=0xc2 && c<=0xdf then cont(i+1) && loop(i+2)
    else if c>=0xe0 && c<=0xef then
      cont(i+1) && cont(i+2) && (c<>0xe0 || byte(i+1)>=0xa0)
      && (c<>0xed || byte(i+1)<0xa0) && loop(i+3)
    else if c>=0xf0 && c<=0xf4 then
      cont(i+1) && cont(i+2) && cont(i+3)
      && (c<>0xf0 || byte(i+1)>=0x90) && (c<>0xf4 || byte(i+1)<0x90)
      && loop(i+4)
    else false in
  loop 0

(* Closed strict JSON grammar: protocol numbers are integers. No comments,
   tuples, trailing commas, NaN, duplicate members or lone Unicode surrogates. *)
let parse_json text =
  let n=String.length text in
  if n=0 || n>max_request_bytes || not(utf8 text) then Error Invalid_json else
  let i=ref 0 and nodes=ref 0 in
  let bad()=raise Bad_json in
  let rec ws()=if !i<n && List.mem text.[!i] [' ';'\t';'\r';'\n'] then(incr i;ws()) in
  let take c=ws(); if !i>=n || text.[!i]<>c then bad() else incr i in
  let hex c=match c with '0'..'9'->Char.code c-48|'a'..'f'->Char.code c-87|'A'..'F'->Char.code c-55|_->bad() in
  let four()=if !i+4>n then bad(); let x=ref 0 in for k=0 to 3 do x:=(!x lsl 4) lor hex text.[!i+k] done;i:= !i+4;!x in
  let string_token()=
    ws();let start= !i in take '"';
    let rec scan()=
      if !i>=n then bad();
      match text.[!i] with
      | '"' -> incr i
      | '\\' -> incr i;if !i>=n then bad();let c=text.[!i] in incr i;
          (match c with
          | '"'|'\\'|'/'|'b'|'f'|'n'|'r'|'t'->()
          | 'u'->let h=four() in
              if h>=0xd800 && h<=0xdbff then(
                if !i+2>n || text.[!i]<>'\\' || text.[!i+1]<>'u' then bad();
                i:= !i+2;let l=four() in if l<0xdc00 || l>0xdfff then bad())
              else if h>=0xdc00 && h<=0xdfff then bad()
          | _->bad());scan()
      | c when Char.code c<32 -> bad()
      | _ -> incr i;scan() in
    scan(); match Yojson.Safe.from_string(String.sub text start (!i-start)) with
    | `String s->s|_->bad() in
  let rec value depth =
    incr nodes;if depth>16 || !nodes>20_000 then bad();ws();if !i>=n then bad();
    match text.[!i] with
    | '"' -> `String(string_token())
    | '{' -> incr i;ws();let seen=Hashtbl.create 16 in
        let rec members acc =
          let key=string_token() in if Hashtbl.mem seen key then bad();Hashtbl.add seen key ();
          take ':';let v=value(depth+1) in ws();
          if !i<n && text.[!i]=',' then(incr i;members((key,v)::acc))
          else(take '}';`Assoc(List.rev((key,v)::acc))) in
        if !i<n && text.[!i]='}' then(incr i;`Assoc[])else members []
    | '[' -> incr i;ws();
        let rec items acc count =
          if count>=1024 then bad();let v=value(depth+1) in ws();
          if !i<n && text.[!i]=',' then(incr i;items(v::acc)(count+1))
          else(take ']';`List(List.rev(v::acc))) in
        if !i<n && text.[!i]=']' then(incr i;`List[])else items [] 0
    | 't' -> literal "true" (`Bool true)
    | 'f' -> literal "false" (`Bool false)
    | 'n' -> literal "null" `Null
    | '-'|'0'..'9' ->
        let start= !i in if text.[!i]='-' then incr i;
        if !i>=n then bad();
        (match text.[!i] with
        | '0' -> incr i
        | '1'..'9' -> incr i;while !i<n && text.[!i]>='0' && text.[!i]<='9' do incr i done
        | _ -> bad());
        if !i-start>20 then bad();
        let number=Int64.of_string(String.sub text start (!i-start)) in
        `Intlit(Int64.to_string number)
    | _ -> bad()
  and literal s v =
    let size=String.length s in if !i+size>n || String.sub text !i size<>s then bad();
    i:= !i+size;v in
  try let j=value 0 in ws();if !i<>n then bad();Ok j
  with Bad_json|Failure _|Yojson.Json_error _ -> Error Invalid_json

let rec canonical = function
  | `Assoc fields -> `Assoc(List.sort (fun(a,_)(b,_)->String.compare a b)
      (List.map(fun(k,v)->k,canonical v)fields))
  | `List xs -> `List(List.map canonical xs)
  | `Int n -> `Intlit(string_of_int n)
  | `Intlit n -> `Intlit(Int64.to_string(Int64.of_string n))
  | x -> x
let encoded j=Yojson.Safe.to_string(canonical j)
let obj names = function
  | `Assoc xs when List.length xs=List.length names
      && List.for_all(fun name->List.length(List.filter(fun(k,_)->k=name)xs)=1)names -> xs
  | _->raise Bad_receipt
let field xs name=List.assoc name xs
let str=function `String s->s|_->raise Bad_receipt
let integer=function `Int n->Int64.of_int n|`Intlit s->(try Int64.of_string s with Failure _->raise Bad_receipt)|_->raise Bad_receipt
let bool=function `Bool b->b|_->raise Bad_receipt
let ascii s cap = String.length s>0 && String.length s<=cap
  && String.for_all(fun c->match c with 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'.'|':'|'/'->true|_->false)s
let digest n s=String.length s=n && String.for_all(fun c->match c with '0'..'9'|'a'..'f'->true|_->false)s
let check b=if not b then raise Bad_receipt
let agent j=let a=str j in check(List.mem a ["claude";"pi";"agy";"codex"]);a
let time j=let t=integer j in check(t>= -9_000_000_000_000L && t<=9_000_000_000_000L);t
let nonnegative j=let n=integer j in check(n>=0L);n
let positive j=let n=integer j in check(n>0L);n
let identifier j=let s=str j in check(ascii s 256);s
let probe j=let p=str j in check(List.mem p ["heartbeat";"functional";"coverage"]);p
let option_bool=function `Null->None|`Bool b->Some b|_->raise Bad_receipt
let binding j =
  let o=obj ["candidate";"config_digest";"session"] j in
  let c=str(field o "candidate") and d=str(field o "config_digest") and s=identifier(field o "session") in
  check(digest 40 c && digest 64 d);(c,d,s)
type receipt={id:string;operation:string;owner:string;epoch:int64;agent:string;
  candidate:string;config:string;session:string;sequence:int64;clock:string;
  probe:string;service:string;canonical:string;hash:string}
let receipt_keys=["receipt_id";"operation_id";"owner_id";"owner_epoch";"agent";
  "candidate";"config_digest";"session";"sequence";"clock_domain";"probe";"service_id";
  "started_mono_ms";"observed_mono_ms";"expires_mono_ms";"observed_utc_us";
  "status";"reason";"results";"coverage"]
let receipt_of_json json = try
  let o=obj receipt_keys json in
  let get=field o in
  let id=identifier(get "receipt_id") and operation=identifier(get "operation_id")
    and owner=identifier(get "owner_id") and epoch=nonnegative(get "owner_epoch")
    and a=agent(get "agent") and candidate=str(get "candidate")
    and config=str(get "config_digest") and session=identifier(get "session")
    and sequence=positive(get "sequence") and clock=identifier(get "clock_domain")
    and p=probe(get "probe") and service=identifier(get "service_id") in
  check(digest 40 candidate && digest 64 config);
  let started=time(get "started_mono_ms") and observed=time(get "observed_mono_ms")
    and expires=time(get "expires_mono_ms") in
  ignore(positive(get "observed_utc_us"));check(observed>=started && expires>=started);
  let status=str(get "status") and reason=str(get "reason") in
  check(List.mem status ["unknown";"stop";"ready_scoped"]);
  check(List.mem reason ["none";"probe_failed";"unavailable";"timed_out";"missing_dimension";"stale";"policy_refused"]);
  let results=obj ["function";"performance";"operation"] (get "results") in
  let f=option_bool(field results "function") and perf=option_bool(field results "performance")
    and op=option_bool(field results "operation") in
  if status="ready_scoped" then check(reason="none" && observed<=expires && op=Some true
    && (p="heartbeat" || (f=Some true && perf=Some true)));
  let coverage=match get "coverage" with
    | `Null -> check(p<>"coverage" || status<>"ready_scoped");`Null
    | j ->
      check(p="coverage");let c=obj ["agent";"binding";"services"] j in
      check(agent(field c "agent")=a && binding(field c "binding")=(candidate,config,session));
      let services=match field c "services" with `List xs when List.length(List.take 257 xs)<=256->xs|_->raise Bad_receipt in
      check(services<>[]);let seen=Hashtbl.create 32 in
      let services=List.map(fun s->
        let v=obj ["agent";"service_id";"binding";"function";"performance";"operation"] s in
        let name=identifier(field v "service_id") in
        check(String.length name<=128 && not(Hashtbl.mem seen name));Hashtbl.add seen name ();
        check(agent(field v "agent")=a && binding(field v "binding")=(candidate,config,session));
        List.iter(fun key->let d=obj ["passed";"observed_mono_ms"](field v key) in
          let passed=bool(field d "passed") and at=time(field d "observed_mono_ms") in
          check(at<=observed);if status="ready_scoped" then check passed)
          ["function";"performance";"operation"];name,s)services in
      let services=List.sort(fun(a,_)(b,_)->String.compare a b)services |> List.map snd in
      `Assoc["agent",`String a;"binding",field c "binding";"services",`List services] in
  let json=`Assoc(List.map(fun(k,v)->k,if k="coverage" then coverage else v)o) in
  let canonical=encoded json in check(String.length canonical<=max_request_bytes);
  Ok{id;operation;owner;epoch;agent=a;candidate;config;session;sequence;clock;
    probe=p;service;canonical;hash=sha canonical}
  with Bad_receipt|Failure _->Error Invalid_receipt
let receipt_json r=Yojson.Safe.from_string r.canonical
let receipt_id r=r.id
let payload_sha256 r=r.hash
type latest_key={owner:string;epoch:int64;agent:string;candidate:string;config:string;
  session:string;clock:string;probe:string;service:string}
let latest_keys=["owner_id";"owner_epoch";"agent";"candidate";"config_digest";"session";"clock_domain";"probe";"service_id"]
let latest_key_of_json j=try
  let o=obj latest_keys j in let get=field o in
  let candidate=str(get "candidate") and config=str(get "config_digest") in
  check(digest 40 candidate && digest 64 config);
  Ok{owner=identifier(get "owner_id");epoch=nonnegative(get "owner_epoch");agent=agent(get "agent");candidate;config;
    session=identifier(get "session");clock=identifier(get "clock_domain");probe=probe(get "probe");service=identifier(get "service_id")}
  with Bad_receipt|Failure _->Error Invalid_request
type request=Append of receipt|Get of string|Latest of latest_key
let decode_request text =
  let* j=parse_json text in try
  let operation=match j with `Assoc xs->str(field xs "operation")|_->raise Bad_receipt in
  let names=match operation with "append"->["schema_version";"operation";"receipt"]
    |"get"->["schema_version";"operation";"receipt_id"]
    |"latest"->"schema_version"::"operation"::latest_keys|_->raise Bad_receipt in
  let o=obj names j in check(integer(field o "schema_version")=1L);
  match operation with
  |"append"->let* r=receipt_of_json(field o "receipt") in Ok(Append r)
  |"get"->Ok(Get(identifier(field o "receipt_id")))
  |_ -> let* key=latest_key_of_json(`Assoc(List.filter(fun(k,_)->List.mem k latest_keys)o)) in Ok(Latest key)
  with Bad_receipt|Not_found|Failure _->Error Invalid_request

let table="symbiosis_check_receipt_v1"
let definitions=[
  "table",table,"CREATE TABLE symbiosis_check_receipt_v1 (record_index INTEGER PRIMARY KEY CHECK(record_index>0), receipt_id TEXT NOT NULL, operation_id TEXT NOT NULL, owner_id TEXT NOT NULL, owner_epoch INTEGER NOT NULL CHECK(typeof(owner_epoch)='integer' AND owner_epoch>=0), agent TEXT NOT NULL CHECK(agent IN ('claude','pi','agy','codex')), sequence INTEGER NOT NULL CHECK(typeof(sequence)='integer' AND sequence>0), candidate TEXT NOT NULL, config_digest TEXT NOT NULL, session TEXT NOT NULL, clock_domain TEXT NOT NULL, probe TEXT NOT NULL, service_id TEXT NOT NULL, payload TEXT NOT NULL, payload_sha256 TEXT NOT NULL, payload_bytes_total INTEGER NOT NULL CHECK(typeof(payload_bytes_total)='integer' AND payload_bytes_total>0))";
  "index","symbiosis_receipt_id_v1","CREATE UNIQUE INDEX symbiosis_receipt_id_v1 ON symbiosis_check_receipt_v1(receipt_id)";
  "index","symbiosis_operation_id_v1","CREATE UNIQUE INDEX symbiosis_operation_id_v1 ON symbiosis_check_receipt_v1(operation_id)";
  "index","symbiosis_identity_v1","CREATE UNIQUE INDEX symbiosis_identity_v1 ON symbiosis_check_receipt_v1(owner_id,owner_epoch,agent,sequence)";
  "index","symbiosis_owner_head_v1","CREATE INDEX symbiosis_owner_head_v1 ON symbiosis_check_receipt_v1(owner_id,owner_epoch DESC,sequence DESC)";
  "index","symbiosis_latest_v1","CREATE INDEX symbiosis_latest_v1 ON symbiosis_check_receipt_v1(owner_id,owner_epoch,agent,candidate,config_digest,session,clock_domain,probe,service_id,sequence DESC)";
  "trigger","symbiosis_no_update_v1","CREATE TRIGGER symbiosis_no_update_v1 BEFORE UPDATE ON symbiosis_check_receipt_v1 BEGIN SELECT RAISE(ABORT,'symbiosis receipts are append-only'); END";
  "trigger","symbiosis_no_delete_v1","CREATE TRIGGER symbiosis_no_delete_v1 BEFORE DELETE ON symbiosis_check_receipt_v1 BEGIN SELECT RAISE(ABORT,'symbiosis receipts are append-only'); END"]
type stage=After_insert|Before_commit|Commit_error|After_commit
type t={evidence:Evidence_store.t;limits:limits;path:string option;identity:(int*int)option;
  owns:bool;mutable active:bool;mutable closed:bool;mutable poisoned:bool;mutable hook:stage->unit}
type stored={index:int64;total:int64;receipt:receipt}
type append_outcome=Stored of stored|Replayed of stored
let sql_exception=function Sqlite3.Error _|Sqlite3.SqliteError _|Sqlite3.InternalError _
  |Sqlite3.RangeError _|Sqlite3.DataTypeError _->true|_->false
(* Pinned sqlite3-ocaml5.4.1 does not root these custom-block arguments across
   its blocking sections. Keep them live after the C call, as Sa_plan_store does.
   Adaptation: installed pinned core/gc.ml:295-302 Core.Gc.keep_alive (Jane Street),
   the opaque runtime-zero recursion, without its template/mode extensions.
   Source: /home/an/NAS-setup/uos/toolchains/opam-ocaml/lib/core/gc.ml,
   SHA256 810d5359aaa2388eb5efb0927550298e2e7d4192d05b54eac6a4c2ee0d51133b.
   Linking Core itself conflicts with Hermes' existing unwrapped Core module.
   Exact installed source digest and native call-site evidence accompany tests. *)
let lifetime_zero = Sys.opaque_identity (int_of_string "0")
let[@inline never] rec keep_alive value =
  if lifetime_zero<>0 then keep_alive(Sys.opaque_identity value)
let close_db db=Fun.protect ~finally:(fun()->keep_alive db)(fun()->Sqlite3.db_close db)
let finalize s=Fun.protect ~finally:(fun()->keep_alive s)(fun()->Sqlite3.finalize s)
let exec db sql=Fun.protect ~finally:(fun()->keep_alive db)(fun()->try match Sqlite3.exec db sql with
  |rc when Sqlite3.Rc.is_success rc->Ok()|_->Error Store_unavailable
  with ex when sql_exception ex ->Error Store_unavailable)
let stmt db sql values f=Fun.protect ~finally:(fun()->keep_alive db)(fun()->try
  let s=Sqlite3.prepare db sql in
  let answer=try `Result(match Sqlite3.bind_values s values with
    |rc when Sqlite3.Rc.is_success rc->f s|_->Error Store_unavailable)
    with ex ->`Exception ex in
  let rc=finalize s in
  match answer with
  |`Exception ex->raise ex
  |`Result answer->if Sqlite3.Rc.is_success rc then answer else Error Store_unavailable
  with ex when sql_exception ex ->Error Store_unavailable)
let text s=Sqlite3.Data.TEXT s
let num n=Sqlite3.Data.INT n
let query_one db sql values decode=stmt db sql values(fun s->match Sqlite3.step s with
  |Sqlite3.Rc.DONE->Ok None|Sqlite3.Rc.ROW->let* v=decode s in Ok(Some v)|_->Error Store_unavailable)
let schema_state db =
  let names=List.map(fun(_,name,_)->name)definitions in
  stmt db "SELECT type,name,sql FROM sqlite_master WHERE tbl_name='symbiosis_check_receipt_v1' OR name IN ('symbiosis_receipt_id_v1','symbiosis_operation_id_v1','symbiosis_identity_v1','symbiosis_owner_head_v1','symbiosis_latest_v1','symbiosis_no_update_v1','symbiosis_no_delete_v1') ORDER BY name LIMIT 9" [] (fun s->
    let rec loop acc=match Sqlite3.step s with
      |Sqlite3.Rc.DONE->Ok acc
      |Sqlite3.Rc.ROW->let row=Sqlite3.column_text s 0,Sqlite3.column_text s 1,Sqlite3.column_text s 2 in loop(row::acc)
      |_->Error Store_unavailable in
    let* rows=loop [] in if rows=[] then Ok false else
    if List.length rows=List.length definitions
       && List.for_all(fun row->List.mem row definitions)rows
       && List.for_all(fun(_,name,_)->List.mem name names)rows then Ok true
    else Error Schema_mismatch)
let pragma db name =
  let* n=query_one db ("PRAGMA "^name) [] (fun s->match Sqlite3.column s 0 with
    |Sqlite3.Data.INT n->Ok n|_->Error Store_unavailable) in
  match n with Some n->Ok n|None->Error Store_unavailable
let valid_limits l=l.max_rows>0 && l.max_rows<=100_000 && l.max_db_bytes>=131_072
  && l.max_db_bytes<=33_554_432 && l.max_payload_bytes>0 && l.max_payload_bytes<=max_request_bytes
let physical_files path identity maximum = try
      let s=Unix.lstat path in
      let* ()=require(s.Unix.st_kind=Unix.S_REG && s.st_nlink=1 && (s.st_dev,s.st_ino)=identity)Invalid_path in
      let total=List.fold_left(fun total path->
        try let s=Unix.lstat path in
          if s.Unix.st_kind<>Unix.S_REG || s.st_nlink<>1 || s.st_uid<>Unix.geteuid()
             || s.st_perm land 0o077<>0 then raise Bad_receipt;
          Int64.add total (Int64.of_int s.st_size)
        with Unix.Unix_error(Unix.ENOENT,_,_)->total)0L [path;path^"-wal";path^"-shm"] in
      require(total<=Int64.of_int maximum)Resource_bound
    with Unix.Unix_error _|Bad_receipt->Error Invalid_path
let physical_check t=match t.path,t.identity with
  |Some path,Some identity->physical_files path identity t.limits.max_db_bytes
  |_->Ok()
let resource_check t=
  let* ()=physical_check t in
  let* pages=pragma t.evidence.db "page_count" in
  let* size=pragma t.evidence.db "page_size" in
  require(size>0L && pages<=Int64.div(Int64.of_int t.limits.max_db_bytes)size)Resource_bound
let available t=if t.closed then Error Closed else if t.poisoned then Error Rollback_failed else Ok()
let transaction t body =
  let* ()=available t in
  if t.active then Error Nested_transaction else
  match exec t.evidence.db "BEGIN IMMEDIATE" with
  |Error _->if Sqlite3.errmsg t.evidence.db="cannot start a transaction within a transaction"
      && Sqlite3.errcode t.evidence.db=Sqlite3.Rc.ERROR
      then Error Nested_transaction else Error Store_unavailable
  |Ok()->
    t.active<-true;
    let rollback original=let rolled=exec t.evidence.db "ROLLBACK" in t.active<-false;
      match rolled with Ok()->Error original|Error _->t.poisoned<-true;Error Rollback_failed in
    let unexpected ex =
      let rolled=exec t.evidence.db "ROLLBACK" in t.active<-false;
      (match rolled with Ok()->()|Error _->t.poisoned<-true);raise ex in
    let attempt=try body() with ex ->
      (* Roll back even an unexpected implementation exception. Do not swallow
         it as successful storage or leave a caller-owned transaction open. *)
      unexpected ex in
    match attempt with
    |Error e->rollback e
    |Ok value->
      let precommit=try t.hook Before_commit;resource_check t
        with Failure _->Error Store_unavailable|ex->unexpected ex in
      (match precommit with Error e->rollback e|Ok()->
       let commit=try t.hook Commit_error;exec t.evidence.db "COMMIT"
         with Failure _->Error Commit_unknown|ex->unexpected ex in
       match commit with
       |Error _->(match rollback Commit_unknown with Error Rollback_failed->Error Rollback_failed|_->Error Commit_unknown)
       |Ok()->t.active<-false;t.hook After_commit;
         match physical_check t with Ok()->Ok value|Error _->Error Commit_unknown)
let initialize t=
  let* ()=require(valid_limits t.limits)Resource_bound in
  Sqlite3.busy_timeout t.evidence.db 100;
  let* ()=exec t.evidence.db "PRAGMA synchronous=FULL" in
  let* full=pragma t.evidence.db "synchronous" in
  let* ()=require(full=2L)Store_unavailable in
  let* size=pragma t.evidence.db "page_size" in
  let* ()=exec t.evidence.db ("PRAGMA max_page_count="^Int64.to_string(Int64.div(Int64.of_int t.limits.max_db_bytes)size)) in
  let* ()=exec t.evidence.db "PRAGMA wal_autocheckpoint=1" in
  let* ()=exec t.evidence.db "PRAGMA journal_size_limit=1048576" in
  transaction t(fun()->let* present=schema_state t.evidence.db in
    if present then Ok() else
    let* ()=List.fold_left(fun acc(_,_,sql)->let* ()=acc in exec t.evidence.db sql)(Ok())definitions in
    let* present=schema_state t.evidence.db in require present Schema_mismatch)
let make ~owns ~path ~identity ~limits evidence=
  let t={evidence;limits;path;identity;owns;active=false;closed=false;poisoned=false;hook=(fun _->())} in
  let* ()=initialize t in Ok t
let safe_path path =
  String.length path>1 && String.length path<=4096 && path.[0]='/'
  && not(String.contains path '\000')
  && List.for_all(fun s->s<>""&&s<>"."&&s<>"..") (List.tl(String.split_on_char '/' path))
let prepare_path path =try
  let* ()=require(safe_path path)Invalid_path in
  let parts=String.split_on_char '/' (Filename.dirname path) |> List.filter((<>)"") in
  let _=List.fold_left(fun current name->let p=Filename.concat current name in
    if (Unix.lstat p).Unix.st_kind<>Unix.S_DIR then raise Bad_receipt;p)"/"parts in
  (try let s=Unix.lstat path in
    if s.Unix.st_kind<>Unix.S_REG || s.st_nlink<>1 || s.st_uid<>Unix.geteuid()
       || s.st_perm land 0o077<>0 then raise Bad_receipt
   with Unix.Unix_error(Unix.ENOENT,_,_)->
     let fd=Unix.openfile path [Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY;Unix.O_CLOEXEC]0o600 in Unix.close fd);
  let s=Unix.lstat path in Ok(s.st_dev,s.st_ino)
  with Unix.Unix_error _|Bad_receipt->Error Invalid_path
let open_store ?(limits=default_limits) ~path () =
  let* ()=require(valid_limits limits)Resource_bound in
  let* identity=prepare_path path in
  let* ()=physical_files path identity limits.max_db_bytes in
  (* Reuse the exact existing evidence connection carrier and schema, while
     keeping every owned initialization/error-close C call rooted. The legacy
     Evidence_store.open_db failure cleanup predates the pinned binding fix. *)
  let opened=try Ok(Sqlite3.db_open ~mode:`NO_CREATE ~uri:false ~mutex:`FULL ~cache:`PRIVATE path)
    with ex when sql_exception ex->Error Store_unavailable in
  let* db=opened in
  let cleanup error=try if close_db db then Error error else Error Rollback_failed
    with ex when sql_exception ex->Error Rollback_failed in
  let initialized=try `Result(
    Sqlite3.busy_timeout db 100;
    let* ()=physical_files path identity limits.max_db_bytes in
    (* Refuse an existing malformed receipt namespace before even the reused
       legacy initializer can create missing unrelated evidence tables. *)
    let* _=schema_state db in
    let* ()=exec db Evidence_store.schema in
    make ~owns:true ~path:(Some path) ~identity:(Some identity) ~limits {Evidence_store.db=db})
    with ex->`Raised ex in
  match initialized with
  |`Result(Ok t)->Ok t
  |`Result(Error error)->cleanup error
  |`Raised ex->
      (* A failed initialization never leaves a handle hidden in an exception.
         Known SQLite faults are redacted; unexpected faults are re-raised only
         after confirmed cleanup, otherwise cleanup uncertainty takes priority. *)
      match cleanup Store_unavailable with
      |Error Rollback_failed->Error Rollback_failed
      |_->if sql_exception ex then Error Store_unavailable else raise ex
let close t =
  if t.closed then Ok() else if t.active then Error Nested_transaction else
  if not t.owns || close_db t.evidence.db then(t.closed<-true;Ok())else Error Store_unavailable

let columns="record_index,payload_bytes_total,payload,payload_sha256,receipt_id,operation_id,owner_id,owner_epoch,agent,sequence,candidate,config_digest,session,clock_domain,probe,service_id,length(CAST(payload AS BLOB))"
let stored_row s =
  let* ()=require(Sqlite3.column_int64 s 16<=Int64.of_int max_request_bytes)Resource_bound in
  let index=Sqlite3.column_int64 s 0 and total=Sqlite3.column_int64 s 1 in
  let payload=Sqlite3.column_text s 2 and hash=Sqlite3.column_text s 3 in
  let* j=parse_json payload in let* r=receipt_of_json j in
  let string_columns=[4,r.id;5,r.operation;6,r.owner;8,r.agent;10,r.candidate;11,r.config;12,r.session;13,r.clock;14,r.probe;15,r.service] in
  let* ()=require(index>0L && total>=Int64.of_int(String.length payload)
    && payload=r.canonical && hash=r.hash && Sqlite3.column_int64 s 7=r.epoch
    && Sqlite3.column_int64 s 9=r.sequence
    && List.for_all(fun(i,v)->Sqlite3.column_text s i=v)string_columns)Schema_mismatch in
  Ok{index;total;receipt=r}
let stored_json s=`Assoc["record_index",`Intlit(Int64.to_string s.index);
  "receipt_id",`String s.receipt.id;"payload_sha256",`String s.receipt.hash;
  "receipt",receipt_json s.receipt]
let ensure_schema t=let* ()=available t in let* present=schema_state t.evidence.db in require present Schema_mismatch
let lookup t id=query_one t.evidence.db ("SELECT "^columns^" FROM "^table^" WHERE receipt_id=? LIMIT 1")[text id]stored_row
let get t ~receipt_id:id =
  let* ()=available t in
  let* ()=require(ascii id 256)Invalid_request in
  let* ()=resource_check t in let* ()=ensure_schema t in lookup t id
let latest t k =
  let* ()=available t in
  let* ()=resource_check t in let* ()=ensure_schema t in
  query_one t.evidence.db ("SELECT "^columns^" FROM "^table^" WHERE owner_id=? AND owner_epoch=? AND agent=? AND candidate=? AND config_digest=? AND session=? AND clock_domain=? AND probe=? AND service_id=? ORDER BY sequence DESC LIMIT 1")
    [text k.owner;num k.epoch;text k.agent;text k.candidate;text k.config;text k.session;text k.clock;text k.probe;text k.service]stored_row
let append t r =
  let* ()=require(String.length r.canonical<=t.limits.max_payload_bytes)Resource_bound in
  let* outcome=transaction t(fun()->
    let* ()=ensure_schema t in let* ()=resource_check t in
    let* existing=stmt t.evidence.db ("SELECT "^columns^" FROM "^table^" WHERE receipt_id=? OR operation_id=? OR (owner_id=? AND owner_epoch=? AND agent=? AND sequence=?) LIMIT 4")
      [text r.id;text r.operation;text r.owner;num r.epoch;text r.agent;num r.sequence](fun s->
        let rec loop acc=match Sqlite3.step s with
          |Sqlite3.Rc.DONE->Ok(List.rev acc)|Sqlite3.Rc.ROW->let* row=stored_row s in loop(row::acc)|_->Error Store_unavailable in loop[]) in
    match existing with
    |[s] when s.receipt.canonical=r.canonical->Ok(Replayed s)
    |_::_->Error Conflict
    |[] ->
      let* head=query_one t.evidence.db ("SELECT owner_epoch,sequence FROM "^table^" WHERE owner_id=? ORDER BY owner_epoch DESC,sequence DESC LIMIT 1")
        [text r.owner](fun s->Ok(Sqlite3.column_int64 s 0,Sqlite3.column_int64 s 1)) in
      let* ()=match head with Some(e,_)when r.epoch<e->Error Stale_epoch
        |Some(e,q)when r.epoch=e && r.sequence<=q->Error Out_of_order|_->Ok() in
      let* last=query_one t.evidence.db ("SELECT record_index,payload_bytes_total FROM "^table^" ORDER BY record_index DESC LIMIT 1")[]
        (fun s->Ok(Sqlite3.column_int64 s 0,Sqlite3.column_int64 s 1)) in
      let index,total=match last with None->1L,Int64.of_int(String.length r.canonical)
        |Some(i,bytes)->Int64.succ i,Int64.add bytes(Int64.of_int(String.length r.canonical)) in
      let* ()=require(index<=Int64.of_int t.limits.max_rows && index>0L
        && total>0L && total<=Int64.of_int t.limits.max_db_bytes)Resource_bound in
      let* ()=stmt t.evidence.db ("INSERT INTO "^table^" VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
        [num index;text r.id;text r.operation;text r.owner;num r.epoch;text r.agent;num r.sequence;
         text r.candidate;text r.config;text r.session;text r.clock;text r.probe;text r.service;
         text r.canonical;text r.hash;num total](fun s->match Sqlite3.step s with Sqlite3.Rc.DONE->Ok()|_->Error Store_unavailable) in
      t.hook After_insert;
      let* readback=lookup t r.id in
      match readback with Some stored when stored.receipt.canonical=r.canonical && stored.index=index->Ok(Stored stored)
      |_->Error Schema_mismatch) in
  let stored=match outcome with Stored s|Replayed s->s in
  match get t ~receipt_id:r.id with
  |Ok(Some d) when d.receipt.canonical=r.canonical && d.index=stored.index->Ok outcome
  |_->Error Commit_unknown

let base status fields=`Assoc(["schema_version",`Int 1;"authority",`String "NONE";
  "status",`String status;"admitted",`Bool false]@fields)
let hold_json error=base "hold"["reason",`String(error_code error)]
let execute t=function
  |Append r->let* out=append t r in
      let status,s=match out with Stored s->"stored",s|Replayed s->"replayed",s in
      (* append already completed its bounded post-COMMIT exact readback. *)
      Ok(base status["record_index",`Intlit(Int64.to_string s.index);"receipt_id",`String r.id;"payload_sha256",`String r.hash])
  |Get id->let* s=get t ~receipt_id:id in
      Ok(match s with None->base "absent"[]|Some s->base "found"["stored",stored_json s])
  |Latest key->let* s=latest t key in
      Ok(match s with None->base "absent"[]|Some s->base "found"["stored",stored_json s])
module For_test = struct
  type nonrec stage=stage=After_insert|Before_commit|Commit_error|After_commit
  let attach ~limits evidence=make ~owns:false ~path:None ~identity:None ~limits evidence
  let on_stage t hook=t.hook<-hook
end
