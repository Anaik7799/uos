(* Signed resource/owner binding PREPARATION, not an admitted launcher.
   Adapted canonical data/signature conventions from Recovery_kernel; no
   signer, mutator, initializer, migration, native process or authority here.
   Opened fds identify real objects, but SQLite's OCaml binding reopens paths.
   Same-UID/cooperative frozen directory topology is NOT race-free confinement. *)
module K=Recovery_kernel
let ( let* )=Result.bind
let ensure b e=if b then Ok()else Error e
let sha=K.sha256
let s x=`String x
type identity={device:int;inode:int;uid:int}
type opened={fd:Unix.file_descr;parent_fd:Unix.file_descr;path:string;
 identity:identity;parent_identity:identity;mutable closed:bool}
type anchor_data={bytes:string;digest:string;kernel:K.configuration_data;
 reviewer:Mirage_crypto_ec.Ed25519.pub;issuer:Mirage_crypto_ec.Ed25519.pub;
 database:identity;journal:identity;fields:(string*Yojson.Basic.t)list}
type evidence={anchor:anchor_data;fresh:K.verified_evidence}
type historical={anchor:anchor_data;history:K.historical_evidence}
let hex str n=String.length str=n&&String.for_all(function '0'..'9'|'a'..'f'->true|_->false)str
let unhex str=let digit c=if c<='9'then Char.code c-48 else Char.code c-87 in
 String.init(String.length str/2)(fun i->Char.chr((digit str.[2*i]lsl 4)lor digit str.[2*i+1]))
let token str=String.length str>0&&String.length str<=200&&String.for_all(function
 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'.'|'/'->true|_->false)str
let identity st={device=st.Unix.st_dev;inode=st.Unix.st_ino;uid=st.Unix.st_uid}
let same a b=a.device=b.device&&a.inode=b.inode&&a.uid=b.uid
let identity_value id=`Assoc["device",s(string_of_int id.device);"inode",s(string_of_int id.inode);"uid",`Int id.uid]
let identity_json o=identity_value o.identity
let regular st=st.Unix.st_kind=Unix.S_REG&&st.Unix.st_uid=Unix.geteuid()
 &&st.Unix.st_nlink=1&&st.Unix.st_perm land 0o077=0&&st.Unix.st_size<=33554432
let directory st=st.Unix.st_kind=Unix.S_DIR&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_perm land 0o077=0
let safe_path path=String.length path>1&&String.length path<=4096&&path.[0]='/'
 &&not(String.contains path '\000')&&List.for_all(fun p->p<>""&&p<>"."&&p<>"..")
 (List.tl(String.split_on_char '/' path))
let close o=if not o.closed then(o.closed<-true;(try Unix.close o.fd with Unix.Unix_error _->());try Unix.close o.parent_fd with Unix.Unix_error _->())
let check_opened o=
 if o.closed then Error"OPENED_RESOURCE_CLOSED"else
 try let current=Unix.fstat o.fd and named=Unix.lstat o.path
 and parent=Unix.fstat o.parent_fd and parent_named=Unix.lstat(Filename.dirname o.path)in
 ensure(regular current&&regular named&&directory parent&&directory parent_named
  &&same(identity current)o.identity&&same(identity named)o.identity
  &&same(identity parent)o.parent_identity&&same(identity parent_named)o.parent_identity)
 "OPENED_RESOURCE_IDENTITY_CHANGED"
 with Unix.Unix_error _->Error"OPENED_RESOURCE_UNAVAILABLE"
let open_owned path=
 let* ()=ensure(safe_path path)"RESOURCE_PATH_BOUND"in
 try
  let parent_path=Filename.dirname path in
  let parent_before=Unix.lstat parent_path and before=Unix.lstat path in
  let* ()=ensure(directory parent_before&&regular before)"PRIVATE_REGULAR_RESOURCE_REQUIRED"in
  let parent_fd=Unix.openfile parent_path[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
  try
   let fd=Unix.openfile path[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
   let o={fd;parent_fd;path;identity=identity before;parent_identity=identity parent_before;closed=false}in
   (match check_opened o with Ok()->Ok o|Error _ as e->close o;e)
  with e->Unix.close parent_fd;raise e
 with Unix.Unix_error _->Error"OPENED_RESOURCE_UNAVAILABLE"
let parse bytes=
 if String.length bytes=0||String.length bytes>32768||not(String.for_all(fun c->Char.code c>=32&&Char.code c<=126)bytes)
 then Error"RESOURCE_DATA_BOUND"else
 (* This fixed shallow schema has at most two object levels plus a quoted
    bounded kernel configuration. Reject structural depth before Yojson. *)
 let depth=ref 0 and quoted=ref false and escaped=ref false and bad=ref false in
 String.iter(fun c->if !quoted then(if !escaped then escaped:=false else if c='\\'then escaped:=true else if c='"'then quoted:=false)
  else if c='"'then quoted:=true else if c='{'||c='['then(incr depth;if !depth>4 then bad:=true)
  else if c='}'||c=']'then(decr depth;if !depth<0 then bad:=true))bytes;
 if !bad|| !quoted|| !depth<>0 then Error"RESOURCE_DATA_DEPTH"else
 try let j=Yojson.Basic.from_string bytes in if Yojson.Basic.to_string j=bytes then Ok j else Error"NONCANONICAL_RESOURCE_DATA"
 with Yojson.Json_error _->Error"INVALID_RESOURCE_DATA"
let fields names=function `Assoc fs when List.map fst fs=names->Ok fs|_->Error"RESOURCE_CLOSED_SCHEMA"
let text fs k=match List.assoc_opt k fs with Some(`String v)->Ok v|_->Error"RESOURCE_STRING_REQUIRED"
let positive str=try let n=Int64.of_string str in ensure(n>0L&&Int64.to_string n=str)"RESOURCE_POSITIVE_INTEGER"with Failure _->Error"RESOURCE_POSITIVE_INTEGER"
let parse_identity j=
 let* fs=fields["device";"inode";"uid"]j in
 let* dev=text fs"device"in let* ino=text fs"inode"in
 let* ()=positive ino in
 try let device=int_of_string dev and inode=int_of_string ino in
  let* uid=match List.assoc"uid"fs with `Int uid when uid>=0&&uid<=2147483647->Ok uid|_->Error"RESOURCE_UID"in
  let* ()=ensure(device>=0&&string_of_int device=dev&&string_of_int inode=ino)"RESOURCE_IDENTITY_INTEGER"in
  Ok{device;inode;uid}
 with Failure _->Error"RESOURCE_IDENTITY_INTEGER"
let anchor_keys=["domain";"kernel_configuration";"database_resource";"database_identity";
 "journal_resource";"journal_identity";"owner";"generation";"epoch";"launcher_sha256";
 "owner_source_sha256";"journal_worker_sha256"]
let anchor_data bytes=
 let* j=parse bytes in let* fs=fields anchor_keys j in
 let* domain=text fs"domain"in let* config=text fs"kernel_configuration"in
 let* kernel=K.configuration_data config in
 let* config_j=parse config in
 let config_fs=match config_j with `Assoc fs->fs|_->assert false in
 let* database_resource=text fs"database_resource"in let* journal_resource=text fs"journal_resource"in
 let* owner=text fs"owner"in let* generation=text fs"generation"in let* epoch=text fs"epoch"in
 let* ()=positive generation in let* ()=positive epoch in
 let* database=parse_identity(List.assoc"database_identity"fs)in
 let* journal=parse_identity(List.assoc"journal_identity"fs)in
 let* ()=ensure(domain="uos.sa-plan.recovery-resource-anchor-data.v2"
  &&database_resource="uos/canonical-sa-plan"&&journal_resource="uos/recovery-owner-journal"
  &&token owner&&not(same database journal)&&List.assoc"epoch"config_fs=s epoch)"RESOURCE_ANCHOR_SCOPE"in
 let rec digests=function []->Ok()|k::rest->let* d=text fs k in let* ()=ensure(hex d 64)"RESOURCE_DIGEST"in digests rest in
 let* ()=digests["launcher_sha256";"owner_source_sha256";"journal_worker_sha256"]in
 let key name=match List.assoc name config_fs with
  |`Assoc signer->let* public=text signer"public_key_hex"in
   (* Exact kernel configuration parser already checked canonical independent
      key encodings and distinct role/session/subject/kid/key values. *)
   (match Mirage_crypto_ec.Ed25519.pub_of_octets(unhex public)with Ok key->Ok key|Error _->Error"RESOURCE_PUBLIC_KEY")
  |_->Error"RESOURCE_SIGNER"in
 let* reviewer=key"reviewer"in let* issuer=key"issuer"in
 Ok{bytes;digest=sha bytes;kernel;reviewer;issuer;database;journal;fields=fs}
let anchor_sha256 a=a.digest
let resource_bytes a ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature=
 let* ()=ensure(String.length request_bytes>0&&String.length request_bytes<=32768
  &&String.length capability_bytes>0&&String.length capability_bytes<=32768
  &&hex reviewer_signature 128&&hex issuer_signature 128)"RESOURCE_INPUT_BOUND"in
 let bytes=Yojson.Basic.to_string(`Assoc([
  "domain",s"uos.sa-plan.reclaim-three.resource-capability.v2";
  "profile",s"RESOURCE_BOUND_PREPARATION_NOT_ADMITTED";"anchor_sha256",s a.digest;
  "request_sha256",s(sha request_bytes);"capability_sha256",s(sha capability_bytes);
  "kernel_reviewer_signature_sha256",s(sha reviewer_signature);"kernel_issuer_signature_sha256",s(sha issuer_signature)]
  @List.filter(fun(k,_)->k<>"domain"&&k<>"kernel_configuration")a.fields))in
 let* ()=ensure(String.length bytes<=32768)"RESOURCE_OUTPUT_BOUND"in Ok bytes
let frame fields=String.concat"|"(List.map(fun s->string_of_int(String.length s)^":"^s)fields)
let review_message bytes=frame["uos.sa-plan.reclaim-resource-review.v2";bytes]
let issuer_message bytes ~reviewer_signature=frame["uos.sa-plan.reclaim-resource-issuer.v2";bytes;reviewer_signature]
let signature key signature message=
 let* ()=ensure(hex signature 128)"RESOURCE_SIGNATURE_ENCODING"in
 ensure(Mirage_crypto_ec.Ed25519.verify ~key (unhex signature)~msg:message)"RESOURCE_SIGNATURE_INVALID"
let authenticate a ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature
 ~resource_bytes:bytes ~resource_reviewer_signature ~resource_issuer_signature=
 let* expected=resource_bytes a ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature in
 let* ()=ensure(String.length bytes<=32768&&bytes=expected)"SIGNED_RESOURCE_BINDING_MISMATCH"in
 let* ()=signature a.reviewer resource_reviewer_signature(review_message bytes)in
 signature a.issuer resource_issuer_signature(issuer_message bytes ~reviewer_signature:resource_reviewer_signature)
let verify a ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature
 ~resource_bytes ~resource_reviewer_signature ~resource_issuer_signature=
 let* ()=authenticate a ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature
  ~resource_bytes ~resource_reviewer_signature ~resource_issuer_signature in
 let* fresh=K.verify a.kernel ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature in
 Ok{anchor=a;fresh}
let verify_history a ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature
 ~resource_bytes ~resource_reviewer_signature ~resource_issuer_signature=
 let* ()=authenticate a ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature
  ~resource_bytes ~resource_reviewer_signature ~resource_issuer_signature in
 let* history=K.verify_history a.kernel ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature in
 Ok{anchor=a;history}
let check a database journal=
 let* ()=check_opened database in let* ()=check_opened journal in
 ensure(same database.identity a.database&&same journal.identity a.journal
  &&not(same database.identity journal.identity))"SIGNED_OPENED_RESOURCE_MISMATCH"
let check_effect_boundary e ~database ~journal=
 let* _=K.still_valid e.fresh in check e.anchor database journal
let check_history_boundary (h:historical) ~database ~journal=
 (* Historical data has no conversion to a fresh-capability type. It can check
    objects only; it neither calls a Store mutator nor reconstructs a permit. *)
 let _=K.historical_capability_sha256 h.history in check h.anchor database journal
let evidence_anchor_sha256 (e:evidence)=e.anchor.digest
let sqlite_descriptor_binding="SQLITE_REOPENS_PATH_NOT_DESCRIPTOR_BOUND"
let production_status()="ADMITTED_RESOURCE_AUTHORITY_UNAVAILABLE"
