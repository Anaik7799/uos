module J=Recovery_owner_journal
let count=ref 0
let check label b=incr count;if not b then failwith label
let field j k=Yojson.Basic.Util.member k j
let text j k=Yojson.Basic.Util.to_string(field j k)
let raw p sql=let db=Sqlite3.db_open p in Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db);Core.Gc.keep_alive db)(fun()->if Sqlite3.exec db sql<>Sqlite3.Rc.OK then failwith(Sqlite3.errmsg db))
let binding=`Assoc["owner_id",`String"fixture-owner";"operation_id",`String(String.make 64 'a');"request_sha256",`String(String.make 64 'b');"context_sha256",`String(String.make 64 'c')]
let request ?(b=binding) previous event=Yojson.Basic.to_string(`Assoc["schema_version",`Int 1;"operation",`String(if event=`Null then"latest"else"append");"binding",b;"expected_previous",previous;"event",event])
let event n phase receipt=`Assoc["sequence",`Int n;"phase",`String phase;"receipt_sha256",receipt]
let call p bytes=Yojson.Basic.from_string(J.handle ~database:p bytes)
let create()=let p=Filename.temp_file"uos-owner-journal-"".sqlite3"in Unix.chmod p 0o600;
 List.iter(raw p)["PRAGMA journal_mode=WAL";"PRAGMA synchronous=FULL"];
 List.iter(raw p)J.schema_statements;p
let fixture f=let p=create()in Fun.protect ~finally:(fun()->List.iter(fun s->let f=p^s in if Sys.file_exists f then Unix.unlink f)["";"-wal";"-shm"])(fun()->f p)
let ()=
 fixture(fun p->let get=request `Null `Null in
  check"empty indexed snapshot"(field(call p get)"record"=`Null);
  let pending=request `Null(event 1"pending"`Null)in let ack=call p pending in
  check"first pending durable ACK"(text ack"status"="ok"&&text ack"code"="APPENDED");
  check"exact replay factual only"(text(call p pending)"code"="REPLAY");
  let previous=field(field ack"record")"sha256"in
  check"changed same sequence refuses"(text(call p(request `Null(event 1"unknown"`Null)))"status"="hold");
  check"wrong CAS refuses"(text(call p(request(`String(String.make 64 '0'))(event 2"unknown"`Null)))"status"="hold");
  check"rearm pending forbidden"(text(call p(request previous(event 2"pending"`Null)))"status"="hold");
  let committed=call p(request previous(event 2"committed_fact"(`String(String.make 64 'd'))))in
  check"terminal metadata append"(text committed"status"="ok");
  check"latest after reopen exact"(field(call p get)"record"=field committed"record");
  check"old pending exact replay never new append"(text(call p pending)"code"="REPLAY");
  let foreign=match binding with `Assoc fs->`Assoc(List.map(fun(k,v)->k,if k="owner_id"then`String"different"else v)fs)|_->assert false in
  check"other identity read refused"(text(call p(request ~b:foreign `Null `Null))"status"="hold");
  List.iter(fun bad->check"strict closed noncanonical wire refuses"(text(call p bad)"status"="hold"))
   [" "^pending;"/*x*/"^pending;String.sub pending 0(String.length pending-1)^",\"x\":1}";pending^"\000";String.make 16385 'x'];
  let db=Sqlite3.db_open p in Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db);Core.Gc.keep_alive db)(fun()->
   check"actual UPDATE refused"(Sqlite3.exec db"UPDATE recovery_owner_event SET record_json='{}'"=Sqlite3.Rc.CONSTRAINT);
   check"actual DELETE refused"(Sqlite3.exec db"DELETE FROM recovery_owner_event"=Sqlite3.Rc.CONSTRAINT)));
 fixture(fun p->raw p"DROP TRIGGER recovery_owner_no_update";check"schema tamper failclosed"(text(call p(request `Null `Null))"status"="hold"));
 fixture(fun p->raw p"INSERT INTO recovery_owner_event VALUES(3,'bad','{}','{}')";check"gap malformed journal fails"(text(call p(request `Null `Null))"status"="hold"));
 fixture(fun p->
  let first=call p(request `Null(event 1"pending"`Null))in
  let second=call p(request(field(field first"record")"sha256")(event 2"unknown"`Null))in
  let third=call p(request(field(field second"record")"sha256")(event 3"unknown"`Null))in
  check"three valid records positive ancestry control"(text third"status"="ok");
  raw p"DROP TRIGGER recovery_owner_no_update";
  raw p"UPDATE recovery_owner_event SET record_json='{}' WHERE sequence=1";
  raw p(List.nth J.schema_statements 1);
  check"valid head cannot conceal malformed earlier row"(text(call p(request `Null `Null))"status"="hold"));
 fixture(fun p->fixture(fun oracle->
  let first=call p(request `Null(event 1"pending"`Null))in
  let previous=field(field first"record")"sha256"in
  let old_second=call p(request previous(event 2"unknown"`Null))in
  ignore(call p(request(field(field old_second"record")"sha256")(event 3"unknown"`Null)));
  ignore(call oracle(request `Null(event 1"pending"`Null)));
  let new_request=request previous(event 2"refused"`Null)in
  let coherent=call oracle new_request in
  check"individually valid alternate prefix positive control"(text coherent"status"="ok");
  raw p"DROP TRIGGER recovery_owner_no_update";
  let db=Sqlite3.db_open p in Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db);Core.Gc.keep_alive db)(fun()->
   let st=Sqlite3.prepare db"UPDATE recovery_owner_event SET request_sha256=?,request_json=?,record_json=? WHERE sequence=2"in
   Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st)(fun()->
    let digest=Digestif.SHA256.(to_hex(digest_string new_request))in
    if Sqlite3.bind_values st[Sqlite3.Data.TEXT digest;TEXT new_request;TEXT(Yojson.Basic.to_string(field coherent"record"))]<>Sqlite3.Rc.OK||Sqlite3.step st<>Sqlite3.Rc.DONE then failwith"fixture coherent prefix mutation"));
  raw p(List.nth J.schema_statements 1);
  check"valid alternate prefix cannot reuse old successor digest"(text(call p(request `Null `Null))"status"="hold")));
 fixture(fun p->let link=p^".link"in Unix.symlink p link;check"symlink fails"(text(call link(request `Null `Null))"status"="hold");Unix.unlink link);
 fixture(fun p->raw p"PRAGMA journal_mode=DELETE";check"nonWAL append refuses"(text(call p(request `Null(event 1"pending"`Null)))"status"="hold"));
 fixture(fun p->
  let first=call p(request `Null(event 1"pending"`Null))in
  let previous=ref(field(field first"record")"sha256")and accepted=ref true in
  for sequence=2 to 256 do
   let ack=call p(request !previous(event sequence"unknown"`Null))in
   if text ack"status"<>"ok"then accepted:=false;
   previous:=field(field ack"record")"sha256"
  done;
  check"all256 bounded append records accepted"!accepted;
  check"record257 refuses without implicit rotation"(text(call p(request !previous(event 257"unknown"`Null)))"status"="hold");
  check"capacity refusal retainslastrecord256"(field(field(call p(request `Null `Null))"record")"sequence"=`Int 256));
 fixture(fun p->
  let fd=Unix.openfile p[Unix.O_WRONLY]0 in Unix.LargeFile.ftruncate fd 33554433L;Unix.close fd;
  check"oversize sparseDB refusedbeforeSQLite"(text(call p(request `Null `Null))"status"="hold"));
 fixture(fun p->
  let canary=Filename.temp_file"owner-foreign-canary-"""in
  let c=open_out_bin canary in output_string c"SYNTHETIC_FOREIGN_CANARY";close_out c;
  Unix.symlink canary(p^"-wal");
  check"WALsymlink refusesbeforeforeignpayload"(text(call p(request `Null(event 1"pending"`Null)))"status"="hold");
  Unix.unlink(p^"-wal");Unix.unlink canary);
 let missing=Filename.temp_file"uos-owner-missing-"""in Sys.remove missing;
 check"missing DB no create"(text(call missing(request `Null(event 1"pending"`Null)))"status"="hold"&&not(Sys.file_exists missing));
 Printf.printf"PASS %d factual journal checks authority=NONE\n"!count
