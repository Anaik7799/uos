(* Native verification-only prerequisite. No public Store mutator, signing key,
   activation flag or production trust constructor. Fixture effects are compiled
   separately under test/, not selected by request/config/environment values. *)
type clock = { utc_ns:int64; mono_ns:int64; host:string; boot:string; domain:string }
type signer = { subject:string; session:string; kid:string; key:Mirage_crypto_ec.Ed25519.pub; octets:string }
type configuration_data = { bytes:string; digest:string; reviewer:signer; issuer:signer;
 host:string; boot:string; epoch:int64; source:string; worker:string; guardian:string }
type authenticated_bytes = { request:string; capability:string; digest:string; config:configuration_data;
 issued_utc:int64; until_utc:int64; issued_mono:int64; until_mono:int64; verified:clock }
type verified_evidence = Fresh of authenticated_bytes
type historical_evidence = Historical of authenticated_bytes
let profile="NATIVE_RECOVERY_CAPABILITY_PREPARATION_NOT_ADMITTED"
let fixed_plan="uos/codex-handover-open-items-fractal-plan/20261031-1240"
let fixed_members=[
 "OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT","codex-symbiosis-preflight-20261031";
 "OI02E_RELEASE_AUTHORITY_PREPARATION","codex-release-authority-20261031";
 "OI02_ATOMIC_11_TARGET_CAPSULE_CUTOVER","codex-hive-cutover-20261031"]
let sha256 s=Digestif.SHA256.(to_hex(digest_string s))
let ( let* )=Result.bind
let ensure b e=if b then Ok()else Error e
let error()=Error "INVALID_CANONICAL_DATA"
let token s=String.length s>0&&String.length s<=200&&String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'/'|'_'|'-'|'.'->true|_->false)s
let hex s n=String.length s=n&&String.for_all(function '0'..'9'|'a'..'f'->true|_->false)s
let unhex s=let byte c=if c<='9'then Char.code c-48 else Char.code c-87 in
 String.init(String.length s/2)(fun i->Char.chr((byte s.[2*i] lsl 4)lor byte s.[2*i+1]))
let parse s =
 if String.length s=0||String.length s>32768||not(String.for_all(fun c->Char.code c>=32&&Char.code c<=126)s)then error()else
 let depth=ref 0 and quoted=ref false and escaped=ref false and bad=ref false in
 String.iter(fun c->if !quoted then(if !escaped then escaped:=false else if c='\\'then escaped:=true else if c='"'then quoted:=false)
  else if c='"'then quoted:=true else if c='{'||c='['then(incr depth;if !depth>6 then bad:=true)
  else if c='}'||c=']'then(decr depth;if !depth<0 then bad:=true))s;
 if !bad|| !quoted|| !depth<>0 then error()else
 try let j=Yojson.Basic.from_string s in if Yojson.Basic.to_string j=s then Ok j else error()with Yojson.Json_error _->error()
let object_fields keys=function
 |`Assoc fields when List.map fst fields=keys->Ok fields|_->error()
let text fs name=match List.assoc_opt name fs with Some(`String s)->Ok s|_->error()
let decimal ?(zero=false) s=try let n=Int64.of_string s in if Int64.to_string n=s&&(if zero then n>=0L else n>0L)then Ok n else error()with Failure _->error()
let num fs name=let* s=text fs name in decimal s
let integer fs name=match List.assoc_opt name fs with Some(`Int n)when n>0&&n<1000000->Ok n|_->error()
let signer j=
 let* fs=object_fields["subject";"session";"kid";"public_key_hex"]j in
 let* subject=text fs "subject"in let* session=text fs "session"in let* kid=text fs "kid"in let* pk=text fs "public_key_hex"in
 let* ()=ensure(token subject&&token session&&token kid&&hex pk 64)"INVALID_SIGNER"in
 let octets=unhex pk in
 (* Canonical compressed Edwards y<p, no all-zero/identity key. No proof of
    independent organizational custody follows from distinct decoded keys. *)
 let rec canonical i=if i<0 then false else
  let observed=Char.code octets.[i]land(if i=31 then 127 else 255)in let bound=if i=0 then 237 else if i=31 then 127 else 255 in
  observed<bound||(observed=bound&&canonical(i-1))in
 let* ()=ensure(canonical 31&&not(String.for_all((=)'\000')octets)&&not(octets="\001"^String.make 31 '\000'))"INVALID_PUBLIC_KEY"in
 match Mirage_crypto_ec.Ed25519.pub_of_octets octets with
 |Error _->error()|Ok key->Ok{subject;session;kid;key;octets}
let configuration_data bytes=
 let* j=parse bytes in
 let* fs=object_fields["domain";"profile";"host";"boot";"epoch";"source_sha256";"worker_sha256";"guardian_sha256";"reviewer";"issuer"]j in
 let* domain=text fs "domain"in let* p=text fs "profile"in let* host=text fs "host"in let* boot=text fs "boot"in
 let* epoch=num fs "epoch"in let* source=text fs "source_sha256"in let* worker=text fs "worker_sha256"in let* guardian=text fs "guardian_sha256"in
 let* reviewer=signer(List.assoc "reviewer"fs)in let* issuer=signer(List.assoc "issuer"fs)in
 let suffix=".tail55d152.ts.net"in
 let* ()=ensure(domain="uos.sa-plan.recovery-launcher-data.v1"&&p=profile&&token host&&Filename.check_suffix host suffix&&token boot
  &&hex source 64&&hex worker 64&&hex guardian 64&&reviewer.subject<>issuer.subject&&reviewer.session<>issuer.session
  &&reviewer.kid<>issuer.kid&&reviewer.octets<>issuer.octets)"CONFIGURATION_DATA_REFUSED"in
 Ok{bytes;digest=sha256 bytes;reviewer;issuer;host;boot;epoch;source;worker;guardian}
let configuration_sha256 (c:configuration_data)=c.digest
let capture path =
 try
  let before=Unix.lstat path in
  if before.Unix.st_kind<>Unix.S_REG||before.Unix.st_nlink<>1||before.Unix.st_uid<>Unix.geteuid()||before.Unix.st_perm land 0o077<>0||before.Unix.st_size>32768 then Error "CONFIGURATION_FILE_BOUND"else
  let fd=Unix.openfile path[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
  Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
   let opened=Unix.fstat fd in
   if opened.Unix.st_dev<>before.Unix.st_dev||opened.Unix.st_ino<>before.Unix.st_ino then Error "CONFIGURATION_IDENTITY_CHANGED"else
   let b=Bytes.create 32769 in let rec loop n=if n=32769 then n else let k=Unix.read fd b n(32769-n)in if k=0 then n else loop(n+k)in
   let n=loop 0 and after=Unix.fstat fd in let named=Unix.lstat path in
   let stable a b=a.Unix.st_dev=b.Unix.st_dev&&a.Unix.st_ino=b.Unix.st_ino&&a.Unix.st_kind=b.Unix.st_kind
    &&a.Unix.st_nlink=b.Unix.st_nlink&&a.Unix.st_uid=b.Unix.st_uid&&a.Unix.st_gid=b.Unix.st_gid
    &&a.Unix.st_perm=b.Unix.st_perm&&a.Unix.st_size=b.Unix.st_size&&a.Unix.st_mtime=b.Unix.st_mtime&&a.Unix.st_ctime=b.Unix.st_ctime in
   if n>32768||not(stable before opened&&stable opened after&&stable after named)then Error "CONFIGURATION_CAPTURE_CHANGED"else Ok(Bytes.sub_string b 0 n))
 with Unix.Unix_error _|Sys_error _->Error "CONFIGURATION_FILE_UNAVAILABLE"
let read_pinned_data ~path ~sha256:expected=
 let* ()=ensure(hex expected 64&&not(Filename.is_relative path))"INVALID_CONFIGURATION_LOCATOR"in
 let* bytes=capture path in let* ()=ensure(sha256 bytes=expected)"CONFIGURATION_PIN_MISMATCH"in configuration_data bytes
let native_clock()=
 try
  let m1=Mtime_clock.now_ns()in
  let days,ps=Ptime.Span.to_d_ps(Ptime.to_span(Ptime_clock.now()))in
  if days<0||days>106751 then Error "NATIVE_UTC_RANGE"else
  let utc_ns=Int64.add(Int64.mul(Int64.of_int days)86400000000000L)(Int64.div ps 1000L)in
  let c=open_in_bin "/proc/sys/kernel/random/boot_id"in
  let boot=Fun.protect ~finally:(fun()->close_in c)(fun()->let b=Bytes.create 65 in let n=input c b 0 65 in String.trim(Bytes.sub_string b 0 n))in
  let host=Unix.gethostname()and mono_ns=Mtime_clock.now_ns()in
  if utc_ns<=0L||m1<0L||mono_ns<m1||Int64.sub mono_ns m1>100000000L||not(token boot&&token host)then Error "NATIVE_CLOCK_UNAVAILABLE"else
  Ok{utc_ns;mono_ns;host;boot;domain="linux-clock-monotonic:"^boot}
 with Unix.Unix_error _|Sys_error _|Invalid_argument _->Error "NATIVE_CLOCK_UNAVAILABLE"
let frame fields=String.concat "|"(List.map(fun s->string_of_int(String.length s)^":"^s)fields)
let review_message bytes=frame["uos.sa-plan.reclaim-review-capability.v1";bytes]
let issuer_message bytes ~reviewer_signature=frame["uos.sa-plan.reclaim-issuer-capability.v1";bytes;reviewer_signature]
let request_shape bytes =
 let* j=parse bytes in
 let* fs=object_fields["domain";"request_id";"plan";"snapshot";"old";"duration";"deadline"]j in
 let* domain=text fs "domain"in let* id=text fs "request_id"in let* plan=text fs "plan"in let* snapshot=text fs "snapshot"in
 let* duration=num fs "duration"in let* deadline=num fs "deadline"in
 let* old=match List.assoc "old"fs with `List [a;b;c]->Ok[a;b;c]|_->error()in
 let rec members acc=function []->Ok(List.rev acc)|j::rest->
  let* f=object_fields["task";"worker";"attempt";"lease"]j in
  let* task=text f "task"in let* worker=text f "worker"in let* _=integer f "attempt"in let* _=num f "lease"in members((task,worker)::acc)rest in
 let* actual=members[]old in
 let* ()=ensure(domain="uos.sa-plan.reclaim-three.v1"&&token id&&plan=fixed_plan&&hex snapshot 64&&duration<=3600000000000L&&actual=fixed_members)"FIXED_RECOVERY_SCOPE_REFUSED"in Ok deadline
let verify_signature signer signature message=
 if not(hex signature 128)then Error "SIGNATURE_ENCODING"else
 if Mirage_crypto_ec.Ed25519.verify ~key:signer.key (unhex signature) ~msg:message then Ok()else Error "SIGNATURE_INVALID"
let cap_keys=["domain";"profile";"configuration_sha256";"request_sha256";"evidence_sha256";"context_sha256";"proposal_sha256";"portfolio_sha256";"selection_sha256";"factual_review_sha256";"source_sha256";"worker_sha256";"guardian_sha256";"reviewer";"reviewer_session";"issuer";"issuer_session";"host";"boot";"clock_domain";"epoch";"issued_utc_ns";"expires_utc_ns";"issued_mono_ns";"expires_mono_ns"]
let check_clock (c:configuration_data) ~issued_utc ~until_utc ~issued_mono ~until_mono ~(previous:clock) (now:clock)=
 let short=String.sub c.host 0(String.length c.host-String.length ".tail55d152.ts.net")in
 ensure(now.host=short&&now.boot=c.boot&&now.domain="linux-clock-monotonic:"^c.boot
  &&now.utc_ns>=issued_utc&&now.utc_ns<until_utc&&now.mono_ns>=issued_mono&&now.mono_ns<until_mono
  &&now.utc_ns>=previous.utc_ns&&now.mono_ns>=previous.mono_ns)"NATIVE_CLOCK_SCOPE_EXPIRED_OR_REGRESSED"
let authenticate (config:configuration_data) ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature=
 let* deadline=request_shape request_bytes in let* j=parse capability_bytes in let* fs=object_fields cap_keys j in
 let get=text fs in let* domain=get"domain"in let* p=get"profile"in
 let expected=["configuration_sha256",config.digest;"request_sha256",sha256 request_bytes;"source_sha256",config.source;"worker_sha256",config.worker;"guardian_sha256",config.guardian;
 "reviewer",config.reviewer.subject;"reviewer_session",config.reviewer.session;"issuer",config.issuer.subject;"issuer_session",config.issuer.session;
 "host",config.host;"boot",config.boot;"clock_domain","linux-clock-monotonic:"^config.boot;"epoch",Int64.to_string config.epoch]in
 let rec same=function []->Ok()|(k,v)::rest->let* actual=get k in let* ()=ensure(actual=v)"CAPABILITY_BINDING_MISMATCH"in same rest in
 let* ()=same expected in
 let rec digests=function []->Ok()|k::rest->let* v=get k in let* ()=ensure(hex v 64)"INVALID_EVIDENCE_DIGEST"in digests rest in
 let* ()=digests["evidence_sha256";"context_sha256";"proposal_sha256";"portfolio_sha256";"selection_sha256";"factual_review_sha256"]in
 let* issued_utc=num fs "issued_utc_ns"in let* until_utc=num fs "expires_utc_ns"in
 let* issued_mono=num fs "issued_mono_ns"in let* until_mono=num fs "expires_mono_ns"in
 let* ()=ensure(domain="uos.sa-plan.reclaim-three.effect-capability.v1"&&p=profile
  &&issued_utc<until_utc&&until_utc<=deadline&&Int64.sub until_utc issued_utc<=600000000000L
  &&issued_mono<until_mono&&Int64.sub until_mono issued_mono<=Int64.sub until_utc issued_utc)"CAPABILITY_WINDOW_OR_PURPOSE"in
 let* ()=verify_signature config.reviewer reviewer_signature(review_message capability_bytes)in
 let* ()=verify_signature config.issuer issuer_signature(issuer_message capability_bytes ~reviewer_signature)in
 let* now=native_clock()in
 Ok{request=request_bytes;capability=capability_bytes;digest=sha256(frame[profile;config.digest;request_bytes;capability_bytes;reviewer_signature;issuer_signature]);config;issued_utc;until_utc;issued_mono;until_mono;verified=now}
let verify config ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature=
 let* e=authenticate config ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature in
 let* ()=check_clock config ~issued_utc:e.issued_utc ~until_utc:e.until_utc ~issued_mono:e.issued_mono ~until_mono:e.until_mono ~previous:e.verified e.verified in Ok(Fresh e)
let verify_history config ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature=
 let* e=authenticate config ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature in Ok(Historical e)
let historical_request_bytes(Historical e)=e.request
let historical_capability_sha256(Historical e)=sha256 e.capability
let historical_evidence_sha256(Historical e)=e.digest
let still_valid(Fresh e)=let* now=native_clock()in
 let* ()=check_clock e.config ~issued_utc:e.issued_utc ~until_utc:e.until_utc ~issued_mono:e.issued_mono ~until_mono:e.until_mono ~previous:e.verified now in Ok now
let request_bytes(Fresh e)=e.request
let capability_sha256(Fresh e)=sha256 e.capability
let evidence_sha256(Fresh e)=e.digest
let expires_utc_ns(Fresh e)=e.until_utc
let authority _="NONE_UNTIL_INDEPENDENT_LAUNCHER_AND_INGRESS_ADMISSION"
let production_owner_status()="ADMITTED_RECOVERY_OWNER_UNAVAILABLE"
