(* Native factual metadata, never trust or signer authority. The only locator
   lives in a private launcher anchor. No argv/environment/request locator. *)
type anchor={database:string;realm:string;device:int;inode:int}
type key={kid:string;algorithm:string;reference:string;state:string}
type metadata={realm_id:string;issuer:string;keys:key list;observed_ms:int64;sqlite_version:string}
type observation=Unknown of string|Observed of metadata
exception Refused of string
let require b code=if not b then raise(Refused code)
let ascii allowed s=String.length s>0&&String.for_all allowed s
let identifier s=String.length s<=128&&ascii(function 'a'..'z'|'A'..'Z'|'0'..'9'|'-'|'_'|'.'->true|_->false)s
let issuer s=
 let prefix="https://"in
 String.length s<=512&&String.length s>String.length prefix&&String.starts_with ~prefix s&&
 ascii(function 'a'..'z'|'A'..'Z'|'0'..'9'|'-'|'_'|'.'|'/'|':'->true|_->false)s
let checked_file a=
 let st=Unix.lstat a.database in
 require(st.Unix.st_kind=Unix.S_REG&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_nlink=1&&st.Unix.st_perm land 0o077=0&&st.Unix.st_size<=33_554_432)"LOCATOR_UNAVAILABLE";
 require(st.Unix.st_dev=a.device&&st.Unix.st_ino=a.inode)"LOCATOR_CHANGED";
 require(Unix.realpath a.database=a.database)"LOCATOR_UNAVAILABLE";
 let parent=Unix.lstat(Filename.dirname a.database)in
 require(parent.Unix.st_kind=Unix.S_DIR&&parent.Unix.st_uid=Unix.geteuid()&&parent.Unix.st_perm land 0o077=0)"LOCATOR_UNAVAILABLE"
let checked_exec db sql= require(Sqlite3.exec db sql=Sqlite3.Rc.OK)"STORE_UNAVAILABLE"
let with_stmt db sql f=
 let st=Sqlite3.prepare db sql in
 Fun.protect ~finally:(fun()->let rc=Sqlite3.finalize st in Core.Gc.keep_alive st;Core.Gc.keep_alive db;require(rc=Sqlite3.Rc.OK)"STORE_UNAVAILABLE")(fun()->f st)
(* typeof and BLOB-byte projection bound conversion BEFORE OCaml copies a cell.
   No public_jwk, seed, user, credential, gcp_binding or audit column is read. *)
let projection column cap=Printf.sprintf"typeof(%s),substr(CAST(%s AS BLOB),1,%d)"column column(cap+1)
let text st i cap=
 require(Sqlite3.column_text st i="text")"METADATA_INVALID";
 let s=Sqlite3.column_blob st(i+1)in require(String.length s<=cap)"METADATA_BOUND";s
let singleton db sql params f=with_stmt db sql(fun st->
 List.iteri(fun i s->require(Sqlite3.bind st(i+1)(Sqlite3.Data.TEXT s)=Sqlite3.Rc.OK)"STORE_UNAVAILABLE")params;
 require(Sqlite3.step st=Sqlite3.Rc.ROW)"METADATA_ABSENT";
 let value=f st in require(Sqlite3.step st=Sqlite3.Rc.DONE)"METADATA_INVALID";value)
let observe_bound a=
 try
  checked_file a;require(identifier a.realm)"LAUNCHER_BINDING_INVALID";
  let db=Sqlite3.db_open ~mode:`READONLY ~uri:false ~mutex:`FULL ~cache:`PRIVATE a.database in
  let result=Fun.protect ~finally:(fun()->let closed=Sqlite3.db_close db in Core.Gc.keep_alive db;require closed "STORE_UNAVAILABLE")(fun()->
   Sqlite3.busy_timeout db 100;
   checked_exec db"PRAGMA query_only=ON;PRAGMA trusted_schema=OFF;BEGIN";
   ignore(singleton db"PRAGMA query_only"[](fun st->require(Sqlite3.column_int st 0=1)"STORE_UNAVAILABLE"));
   let observed=try
    List.iter(fun name->let typ=singleton db("SELECT "^projection"type"16^" FROM sqlite_schema WHERE name=? LIMIT 2")[name](fun st->text st 0 16)in require(typ="table")"SCHEMA_UNSUPPORTED")["schema_meta";"realms";"signing_keys"];
    let version=singleton db("SELECT "^projection"value"8^" FROM schema_meta WHERE key='version' LIMIT 2")[](fun st->text st 0 8)in
    require(version="1")"SCHEMA_UNSUPPORTED";
    let realm_id,iss=singleton db("SELECT "^projection"id"128^","^projection"issuer_url"512^" FROM realms WHERE id=? LIMIT 2")[a.realm](fun st->text st 0 128,text st 2 512)in
    require(realm_id=a.realm&&identifier realm_id&&issuer iss)"METADATA_INVALID";
    let keys=with_stmt db("SELECT "^projection"kid"128^","^projection"alg"8^","^projection"vault_secret_name"256^",rotated_at IS NULL FROM signing_keys WHERE realm_id=? AND retired_at IS NULL ORDER BY kid LIMIT 17")(fun st->
     require(Sqlite3.bind st 1(Sqlite3.Data.TEXT a.realm)=Sqlite3.Rc.OK)"STORE_UNAVAILABLE";
     let rec loop acc=match Sqlite3.step st with
      |Sqlite3.Rc.DONE->List.rev acc
      |Sqlite3.Rc.ROW->require(List.length acc<16)"METADATA_BOUND";
        let kid=text st 0 128 and alg=text st 2 8 and reference=text st 4 256 in
        require(identifier kid&&List.mem alg["EdDSA";"ES256";"RS256"])"METADATA_INVALID";
        require(reference="iam/signing/"^String.lowercase_ascii alg^"/"^kid)"CUSTODY_REFERENCE_UNKNOWN";
        let state=if Sqlite3.column_int st 6=1 then"current"else"rotating"in
        loop({kid;algorithm=alg;reference;state}::acc)
      |_->raise(Refused"STORE_UNAVAILABLE")in loop[])in
    checked_exec db"ROLLBACK";
    require(keys<>[])"METADATA_ABSENT";
    Observed{realm_id;issuer=iss;keys;observed_ms=Int64.of_float(Unix.gettimeofday()*.1000.);sqlite_version=Sqlite3.sqlite_version_info()}
   with e->ignore(Sqlite3.exec db"ROLLBACK");raise e in
   observed)in checked_file a;result
 with Refused code->Unknown code|_->Unknown"STORE_UNAVAILABLE"
(* Real production binding must come from a protected launcher, not caller
   configuration, argv, environment, metadata or a hash that authenticates itself.
   No such binding is established by this development slice. *)
let launcher_anchor : anchor option = None
let observe()=match launcher_anchor with None->Unknown "PROVIDER_UNCONFIGURED"|Some a->observe_bound a
let encode observation=
 let fields=match observation with
 |Unknown reason->["status",`String"UNKNOWN";"reason",`String reason;"realm_id",`Null;"issuer",`Null;"observed_at_ms",`Null;"sqlite_version",`Null;"keys",`List[]]
 |Observed m->["status",`String"OBSERVED_METADATA_ONLY";"reason",`Null;"realm_id",`String m.realm_id;"issuer",`String m.issuer;"observed_at_ms",`Int(Int64.to_int m.observed_ms);"sqlite_version",`String m.sqlite_version;
  "keys",`List(List.map(fun k->`Assoc["kid",`String k.kid;"algorithm",`String k.algorithm;"custody_reference",`String k.reference;"state",`String k.state])m.keys)]in
 Yojson.Basic.to_string(`Assoc(["schema_version",`Int 1;"source_schema",`String"ferriskey.sqlite.v1";"authority",`String"NONE";"trusted_roster",`Bool false;"purpose_binding",`String"UNKNOWN";"custody_verified",`Bool false]@fields))
let serve_with observed=
 let result=try
  require(Array.length Sys.argv=2&&Sys.argv.(1)="/METADATA_ONLY_NO_LOCATOR")"REQUEST_REFUSED";
  let h=really_input_string stdin 4 in let n=ref 0 in String.iter(fun c->n:=(!n lsl 8)lor Char.code c)h;
  require(!n=51)"REQUEST_REFUSED";
  let raw=really_input_string stdin !n in
  require(raw="{\"operation\":\"observe_metadata\",\"schema_version\":1}")"REQUEST_REFUSED";
  (try ignore(input_char stdin);raise(Refused"REQUEST_REFUSED")with End_of_file->());
  observed()
 with Refused code->Unknown code|_->Unknown"REQUEST_REFUSED"in
 let body=encode result in require(String.length body<=16384)"OUTPUT_BOUND";
 let n=String.length body in for i=3 downto 0 do output_char stdout(Char.chr((n lsr(i*8))land 255))done;
 output_string stdout body;flush stdout
let serve()=serve_with observe
