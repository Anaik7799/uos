(* Exact native K.v1 + resource.v2 purpose signing PREPARATION only.
   Private provider provenance/key handles are never constructed from request
   bytes. Production has no binding. Test-only workers each own ONE deliberately
   public fixed vector and an independently compiled private manifest pin. *)
module K=Recovery_kernel
module R=Recovery_resource
let ( let* )=Result.bind
exception Refused of string
let require b e=if not b then raise(Refused e)
let ok=function Ok x->x|Error _->raise(Refused"BOUND_DATA_REFUSED")
let text j k=match Yojson.Basic.Util.member k j with `String s->s|_->raise(Refused"BOUND_DATA_REFUSED")
let hex s n=String.length s=n&&String.for_all(function '0'..'9'|'a'..'f'->true|_->false)s
let token s=String.length s>0&&String.length s<=200&&String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'-'|'_'|'.'|'/'->true|_->false)s
let decimal s=let n=Int64.of_string s in require(n>0L&&Int64.to_string n=s)"FIXED_SCOPE_REFUSED";n
let closed j keys=match j with `Assoc fs->require(List.map fst fs=keys)"CLOSED_SCHEMA"|_->raise(Refused"CLOSED_SCHEMA")
let parse cap bytes=
 require(String.length bytes>0&&String.length bytes<=cap&&String.for_all(fun c->Char.code c>=32&&Char.code c<=126)bytes)"INPUT_BOUND";
 let depth=ref 0 and quoted=ref false and escaped=ref false in
 String.iter(fun c->if !quoted then(if !escaped then escaped:=false else if c='\\'then escaped:=true else if c='"'then quoted:=false)
 else if c='"'then quoted:=true else if c='{'||c='['then(incr depth;require(!depth<=8)"INPUT_BOUND")else if c='}'||c=']'then(decr depth;require(!depth>=0)"INPUT_BOUND"))bytes;
 require(not !quoted&& !depth=0)"INPUT_BOUND";
 let j=Yojson.Basic.from_string bytes in require(Yojson.Basic.to_string j=bytes)"NONCANONICAL_DATA";j
type role=Reviewer|Issuer
type operation=ReviewKernel|IssueKernel|ReviewResource|IssueResource
type request={operation:operation;intent:string;kr:string;ki:string;rr:string}
type provider={role:role;key:Mirage_crypto_ec.Ed25519.priv;manifest_path:string;manifest_sha:string}
type signature_fact={operation:operation;intent:string;manifest_sha:string;request_sha:string;capability_sha:string;resource_sha:string option;signature:string}
let op_name=function ReviewKernel->"review_kernel"|IssueKernel->"issue_kernel"|ReviewResource->"review_resource"|IssueResource->"issue_resource"
let op_role=function ReviewKernel|ReviewResource->Reviewer|IssueKernel|IssueResource->Issuer
let request_of_json raw=try
 let j=parse 2048 raw in closed j["schema";"operation";"intent_id";"kernel_review";"kernel_issuer";"resource_review"];
 require(text j"schema"="uos.recovery.native-signing.v2")"PURPOSE_REFUSED";
 let operation=match text j"operation"with"review_kernel"->ReviewKernel|"issue_kernel"->IssueKernel|"review_resource"->ReviewResource|"issue_resource"->IssueResource|_->raise(Refused"PURPOSE_REFUSED")in
 let intent=text j"intent_id"and kr=text j"kernel_review"and ki=text j"kernel_issuer"and rr=text j"resource_review"in
 require(token intent)"INTENT_REFUSED";
 require(match operation with ReviewKernel->kr=""&&ki=""&&rr=""|IssueKernel->hex kr 128&&ki=""&&rr=""|ReviewResource->hex kr 128&&hex ki 128&&rr=""|IssueResource->hex kr 128&&hex ki 128&&hex rr 128)"PRIOR_SIGNATURE_SCOPE";
 Ok{operation;intent;kr;ki;rr}
 with Refused e->Error e|_->Error"REQUEST_REFUSED"
let capture path limit=
 let same a b=a.Unix.st_dev=b.Unix.st_dev&&a.Unix.st_ino=b.Unix.st_ino&&a.Unix.st_kind=b.Unix.st_kind&&a.Unix.st_perm=b.Unix.st_perm&&a.Unix.st_nlink=b.Unix.st_nlink&&a.Unix.st_uid=b.Unix.st_uid&&a.Unix.st_gid=b.Unix.st_gid&&a.Unix.st_size=b.Unix.st_size&&a.Unix.st_mtime=b.Unix.st_mtime&&a.Unix.st_ctime=b.Unix.st_ctime in
 let before=Unix.lstat path in
 require(before.Unix.st_kind=Unix.S_REG&&before.Unix.st_uid=Unix.geteuid()&&before.Unix.st_nlink=1&&before.Unix.st_perm land 0o077=0&&before.Unix.st_size<=limit&&Unix.realpath path=path)"MANIFEST_UNAVAILABLE";
 let c=open_in_bin path in Fun.protect ~finally:(fun()->close_in c)(fun()->
  let fd=Unix.descr_of_in_channel c in let opened=Unix.fstat fd in
  require(opened.Unix.st_dev=before.Unix.st_dev&&opened.Unix.st_ino=before.Unix.st_ino)"MANIFEST_CHANGED";
  let b=Bytes.create(limit+1)in let rec loop n=if n=limit+1 then n else let k=input c b n(limit+1-n)in if k=0 then n else loop(n+k)in
  let n=loop 0 in require(n<=limit)"MANIFEST_BOUND";
  let after=Unix.fstat fd and named=Unix.lstat path in
  require(same before opened&&same opened after&&same after named)"MANIFEST_CHANGED";Bytes.sub_string b 0 n)
let unhex s=let d c=if c<='9'then Char.code c-48 else Char.code c-87 in String.init(String.length s/2)(fun i->Char.chr((d s.[i*2]lsl 4)lor d s.[i*2+1]))
let as_hex s=String.concat""(List.init(String.length s)(fun i->Printf.sprintf"%02x"(Char.code s.[i])))
let verify public signature message=
 require(hex public 64&&hex signature 128)"PRIOR_SIGNATURE_SCOPE";
 let key=ok(Mirage_crypto_ec.Ed25519.pub_of_octets(unhex public))in
 require(Mirage_crypto_ec.Ed25519.verify ~key(unhex signature)~msg:message)"PRIOR_SIGNATURE_REFUSED"
let now_valid config cap=
 let positive j k=let s=text j k in let n=Int64.of_string s in require(n>0L&&Int64.to_string n=s)"NATIVE_WINDOW_REFUSED";n in
 let issued=positive cap"issued_utc_ns"and expires=positive cap"expires_utc_ns"and mono=positive cap"issued_mono_ns"and until=positive cap"expires_mono_ns"in
 let now=ok(K.native_clock())in
 let suffix=".tail55d152.ts.net"in let host=text config"host"in
 require(Filename.check_suffix host suffix&&String.length host>String.length suffix)"NATIVE_WINDOW_REFUSED";
 require(now.host=String.sub host 0(String.length host-String.length suffix)&&now.boot=text config"boot"&&now.domain=text cap"clock_domain"
  &&now.utc_ns>=issued&&now.utc_ns<expires&&now.mono_ns>=mono&&now.mono_ns<until&&issued<expires&&mono<until
  &&Int64.sub expires issued<=600000000000L&&Int64.sub until mono<=Int64.sub expires issued)"NATIVE_WINDOW_REFUSED"
let hash_file path=
 let before=Unix.lstat path in require(before.Unix.st_kind=Unix.S_REG&&before.Unix.st_size<=67108864)"PIN_UNAVAILABLE";
 let c=open_in_bin path in Fun.protect ~finally:(fun()->close_in c)(fun()->
  let buffer=Bytes.create 65536 and ctx=ref Digestif.SHA256.empty and total=ref 0 in
  let rec loop()=let n=input c buffer 0 65536 in if n>0 then(total:= !total+n;require(!total<=67108864)"PIN_BOUND";ctx:=Digestif.SHA256.feed_bytes !ctx ~off:0 ~len:n buffer;loop())in loop();
  let same a b=a.Unix.st_dev=b.Unix.st_dev&&a.Unix.st_ino=b.Unix.st_ino&&a.Unix.st_size=b.Unix.st_size&&a.Unix.st_mtime=b.Unix.st_mtime&&a.Unix.st_ctime=b.Unix.st_ctime&&a.Unix.st_kind=b.Unix.st_kind&&a.Unix.st_perm=b.Unix.st_perm&&a.Unix.st_uid=b.Unix.st_uid&&a.Unix.st_gid=b.Unix.st_gid&&a.Unix.st_nlink=b.Unix.st_nlink in
  require(same(Unix.fstat(Unix.descr_of_in_channel c))before&&same(Unix.lstat path)before)"PIN_CHANGED";Digestif.SHA256.(to_hex(get !ctx)))
let cap_keys=["domain";"profile";"configuration_sha256";"request_sha256";"evidence_sha256";"context_sha256";"proposal_sha256";"portfolio_sha256";"selection_sha256";"factual_review_sha256";"source_sha256";"worker_sha256";"guardian_sha256";"reviewer";"reviewer_session";"issuer";"issuer_session";"host";"boot";"clock_domain";"epoch";"issued_utc_ns";"expires_utc_ns";"issued_mono_ns";"expires_mono_ns"]
let sign_bound (provider:provider) (request:request)=try
 require(op_role request.operation=provider.role)"ROLE_REFUSED";
 let bytes=capture provider.manifest_path 262144 in require(hex provider.manifest_sha 64&&K.sha256 bytes=provider.manifest_sha)"MANIFEST_PIN_REFUSED";
 let manifest=parse 262144 bytes in closed manifest["domain";"intent_id";"kernel_configuration";"resource_anchor";"request";"capability";"database";"journal";"pins"];
 require(text manifest"domain"="uos.recovery.native-signing.launcher-fixture.v2"&&text manifest"intent_id"=request.intent)"INTENT_REFUSED";
 let config_bytes=text manifest"kernel_configuration"and anchor_bytes=text manifest"resource_anchor"and native_request=text manifest"request"and capability=text manifest"capability"in
 let config=ok(K.configuration_data config_bytes)and anchor=ok(R.anchor_data anchor_bytes)in
 let cfg=parse 32768 config_bytes and aj=parse 32768 anchor_bytes and cap=parse 32768 capability and req=parse 32768 native_request in
 closed cap cap_keys;closed req["domain";"request_id";"plan";"snapshot";"old";"duration";"deadline"];
 require(text req"domain"="uos.sa-plan.reclaim-three.v1"&&text req"request_id"=request.intent&&text req"plan"=K.fixed_plan&&hex(text req"snapshot")64&&text aj"kernel_configuration"=config_bytes)"FIXED_SCOPE_REFUSED";
 let members=match Yojson.Basic.Util.member"old"req with`List xs when List.length xs=3->List.map(fun x->closed x["task";"worker";"attempt";"lease"];let attempt=Yojson.Basic.Util.to_int(Yojson.Basic.Util.member"attempt"x)in require(attempt>0&&attempt<1000000)"FIXED_SCOPE_REFUSED";ignore(decimal(text x"lease"));text x"task",text x"worker")xs|_->raise(Refused"FIXED_SCOPE_REFUSED")in
 require(members=K.fixed_members&&decimal(text req"duration")<=3600000000000L&&decimal(text cap"expires_utc_ns")<=decimal(text req"deadline"))"FIXED_SCOPE_REFUSED";
 let get_signer role=Yojson.Basic.Util.member role cfg in let reviewer=get_signer"reviewer"and issuer=get_signer"issuer"in
 List.iter(fun(k,v)->require(text cap k=v)"CAPABILITY_BINDING_REFUSED")([
  "domain","uos.sa-plan.reclaim-three.effect-capability.v1";"profile",K.profile;"configuration_sha256",K.configuration_sha256 config;"request_sha256",K.sha256 native_request;
  "reviewer",text reviewer"subject";"reviewer_session",text reviewer"session";"issuer",text issuer"subject";"issuer_session",text issuer"session"]@
  List.map(fun k->k,text cfg k)["source_sha256";"worker_sha256";"guardian_sha256";"host";"boot";"epoch"]);
 List.iter(fun k->require(hex(text cap k)64)"CAPABILITY_BINDING_REFUSED")["evidence_sha256";"context_sha256";"proposal_sha256";"portfolio_sha256";"selection_sha256";"factual_review_sha256"];
 let pins=Yojson.Basic.Util.member"pins"manifest in closed pins["source";"worker";"guardian";"launcher";"owner_source";"journal_worker"];
 List.iter(fun(role,expected)->let p=Yojson.Basic.Util.member role pins in closed p["path";"sha256"];require(text p"sha256"=expected&&hash_file(text p"path")=expected)"ARTIFACT_PIN_REFUSED")
  (List.map(fun k->k,text cfg(k^"_sha256"))["source";"worker";"guardian"]@List.map(fun k->k,text aj(k^"_sha256"))["launcher";"owner_source";"journal_worker"]);
 let database=ok(R.open_owned(text manifest"database"))in
 let result=Fun.protect ~finally:(fun()->R.close database)(fun()->let journal=ok(R.open_owned(text manifest"journal"))in
 Fun.protect ~finally:(fun()->R.close journal)(fun()->
 require(R.identity_json database=Yojson.Basic.Util.member"database_identity"aj&&R.identity_json journal=Yojson.Basic.Util.member"journal_identity"aj)"RESOURCE_BINDING_REFUSED";
 let public=as_hex(Mirage_crypto_ec.Ed25519.pub_to_octets(Mirage_crypto_ec.Ed25519.pub_of_priv provider.key))in
 require(public=text(if provider.role=Reviewer then reviewer else issuer)"public_key_hex")"KEY_BINDING_REFUSED";
 let resource=match request.operation with ReviewKernel|IssueKernel->None|ReviewResource|IssueResource->
  ignore(ok(K.verify config ~request_bytes:native_request ~capability_bytes:capability ~reviewer_signature:request.kr ~issuer_signature:request.ki));
  Some(ok(R.resource_bytes anchor ~request_bytes:native_request ~capability_bytes:capability ~reviewer_signature:request.kr ~issuer_signature:request.ki))in
 let message=match request.operation,resource with
 |ReviewKernel,_->K.review_message capability
 |IssueKernel,_->verify(text reviewer"public_key_hex")request.kr(K.review_message capability);K.issuer_message capability ~reviewer_signature:request.kr
 |ReviewResource,Some r->R.review_message r
 |IssueResource,Some r->verify(text reviewer"public_key_hex")request.rr(R.review_message r);R.issuer_message r ~reviewer_signature:request.rr
 |_->raise(Refused"PURPOSE_REFUSED")in
 ignore(ok(R.check_opened database));ignore(ok(R.check_opened journal));now_valid cfg cap;
 let signature=as_hex(Mirage_crypto_ec.Ed25519.sign ~key:provider.key message)in
 (match request.operation,resource with
 |IssueKernel,_->ignore(ok(K.verify config ~request_bytes:native_request ~capability_bytes:capability ~reviewer_signature:request.kr ~issuer_signature:signature))
 |IssueResource,Some resource_bytes->ignore(ok(R.verify anchor ~request_bytes:native_request ~capability_bytes:capability ~reviewer_signature:request.kr ~issuer_signature:request.ki ~resource_bytes ~resource_reviewer_signature:request.rr ~resource_issuer_signature:signature))
 |_->());
 Ok{operation=request.operation;intent=request.intent;manifest_sha=provider.manifest_sha;request_sha=K.sha256 native_request;capability_sha=K.sha256 capability;resource_sha=Option.map K.sha256 resource;signature}))in result
 with Refused e->Error e|_->Error"PROVIDER_UNAVAILABLE"
let launcher_provider : provider option = None
let sign request=match launcher_provider with None->Error"Unavailable"|Some p->sign_bound p request
let encode outcome=Yojson.Basic.to_string(match outcome with
 |Error reason->`Assoc["status",`String"Unavailable";"reason",`String reason;"authority",`String"NONE";"admitted",`Bool false]
 |Ok f->`Assoc["status",`String"SIGNATURE_FACT_ONLY";"operation",`String(op_name f.operation);"intent_id",`String f.intent;"manifest_sha256",`String f.manifest_sha;"request_sha256",`String f.request_sha;"capability_sha256",`String f.capability_sha;"resource_sha256",(match f.resource_sha with None->`Null|Some s->`String s);"signature_hex",`String f.signature;"authority",`String"NONE";"admitted",`Bool false])
let serve_with sign_request=
 let outcome=try require(Array.length Sys.argv=2&&Sys.argv.(1)="/NATIVE_SIGNING_NO_CALLER_LOCATOR")"REQUEST_REFUSED";
  let h=really_input_string stdin 4 in let n=ref 0 in String.iter(fun c->n:=(!n lsl 8)lor Char.code c)h;
  require(!n>0&& !n<=2048)"INPUT_BOUND";let raw=really_input_string stdin !n in
  (try ignore(input_char stdin);raise(Refused"INPUT_BOUND")with End_of_file->());
  let* request=request_of_json raw in sign_request request
  with _->Error"Unavailable"in
 let body=encode outcome in let n=String.length body in require(n<=4096)"OUTPUT_BOUND";
 for i=3 downto 0 do output_char stdout(Char.chr((n lsr(i*8))land 255))done;output_string stdout body;flush stdout
let serve()=serve_with sign
