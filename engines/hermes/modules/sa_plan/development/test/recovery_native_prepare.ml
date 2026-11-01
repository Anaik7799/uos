(* PRIVATE ordinary unsigned preparation/finalization. No inline signing
   function/call, JWT, real key or production provider. Native role workers
   outside the development bundle supply all four detached signatures. *)
(* PRIVATE fixture interpreter and test trust. Never linked into production.
   Fixed NONSECRET R/I vectors; no live DB/config/keys. Complete FOUR-row
   synthetic portfolio retains every source reference from the supplied old
   matrix, re-observed from actual candidate bytes. It is NOT a canonical
   main-plan preflight, independent human/model review or production grant. *)
module K=Recovery_kernel
module R=Recovery_resource
module S=Sa_plan.Store
external fixture_persist : unit -> bool = "caml_uos_control_fixture_persist"
external retained_identity : Unix.file_descr -> (int64*int64)option = "caml_uos_main_mapping_retained_identity"
let need b s=if not b then failwith s
let ok=function Ok x->x|Error _->failwith"fixture validation refused"
let s x=`String x
let read p=Bounded.read ~limit:1048576 p
let write p b=let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in
 let c=Unix.out_channel_of_descr fd in Fun.protect ~finally:(fun()->close_out c)(fun()->output_string c b;flush c;Unix.fsync fd)
let json p=Bounded.json_text(read p)
let field j k=Yojson.Basic.Util.member k j
let text j k=Yojson.Basic.Util.to_string(field j k)
let set j k v=match j with `Assoc fs->`Assoc(List.map(fun(a,b)->a,if a=k then v else b)fs)|_->failwith"object"
let hash p=K.sha256(Bounded.read ~limit:100663296 p)
let capture p=
 let st=Unix.lstat p in need(st.Unix.st_kind=Unix.S_REG&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_nlink=1&&st.Unix.st_perm land 0o077=0)"private locator required";
 read p
let physical database=
 `Assoc(List.map(fun(role,suffix)->
   let fd=Unix.openfile(database^suffix)[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
   let device,inode=Fun.protect ~finally:(fun()->Unix.close fd)(fun()->ok(match retained_identity fd with Some x->Ok x|_->Error"identity"))in
   role,`Assoc["device",s(Int64.to_string device);"inode",s(Int64.to_string inode)])
  ["main","";"wal","-wal";"shm","-shm"])
let hex str=String.concat""(List.init(String.length str)(fun i->Printf.sprintf"%02x"(Char.code str.[i])))
let key c=ok(Mirage_crypto_ec.Ed25519.priv_of_octets(String.make 32 c))
let public c=hex(Mirage_crypto_ec.Ed25519.pub_to_octets(Mirage_crypto_ec.Ed25519.pub_of_priv(key c)))
let signer subject session kid seed=`Assoc["subject",s subject;"session",s session;"kid",s kid;"public_key_hex",s(public seed)]
let schema=[
 "control_resource_receipt","CREATE TABLE control_resource_receipt(request_id TEXT PRIMARY KEY,binding_json TEXT NOT NULL)";
 "control_no_update","CREATE TRIGGER control_no_update BEFORE UPDATE ON control_resource_receipt BEGIN SELECT RAISE(ABORT,'control receipts are append-only'); END";
 "control_no_delete","CREATE TRIGGER control_no_delete BEFORE DELETE ON control_resource_receipt BEGIN SELECT RAISE(ABORT,'control receipts are append-only'); END"]
let sql db q=need(Sqlite3.exec db q=Sqlite3.Rc.OK)("private SQL refused: "^Sqlite3.errmsg db)
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let with_db p f=let db=Sqlite3.db_open p in Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db);Core.Gc.keep_alive db)(fun()->f db)
let stamp t=let t=Unix.gmtime t in Printf.sprintf"%04d-%02d-%02dT%02d:%02d:%02dZ"(t.Unix.tm_year+1900)(t.Unix.tm_mon+1)t.Unix.tm_mday t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec
let check_schema db=
 let st=Sqlite3.prepare db"SELECT name,sql FROM sqlite_schema WHERE name GLOB 'control_*' ORDER BY name LIMIT 4"in
 Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st))(fun()->
 let rec rows xs=match Sqlite3.step st with Sqlite3.Rc.DONE->List.sort compare xs
 |Sqlite3.Rc.ROW when List.length xs<3->rows((Sqlite3.column_text st 0,Sqlite3.column_text st 1)::xs)
 |_->failwith"control schema bound"in need(rows[]=List.sort compare schema)"control schema changed")
let control_lookup db id binding=
 check_schema db;
 let st=Sqlite3.prepare db"SELECT CASE WHEN typeof(binding_json)='text' THEN CAST(substr(CAST(binding_json AS BLOB),1,16385) AS TEXT) ELSE NULL END FROM control_resource_receipt WHERE request_id=? LIMIT 2"in
 Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st;Core.Gc.keep_alive db)(fun()->
 ignore(Sqlite3.bind st 1(Sqlite3.Data.TEXT id));match Sqlite3.step st with
 |Sqlite3.Rc.DONE->false
 |Sqlite3.Rc.ROW->let b=Sqlite3.column_text st 0 in need(b=binding&&String.length b<=16384&&Sqlite3.step st=Sqlite3.Rc.DONE)"control receipt conflict";true
 |_->failwith"control receipt lookup")
(* Initial actual NTP sample, not resampled synchronization. This complete
   checker executes BEFORE bound VFS open; every descriptor is closed first.
   Same-handle Store revalidates the full snapshot under BEGIN IMMEDIATE. *)
let checker root database portfolio bindings clock_tracking vfs_manifest =
 let raw=read portfolio in
 let records=Yojson.Basic.Util.to_list(Bounded.json_text raw)in
 let old=Sys.getcwd()in
 Fun.protect ~finally:(fun()->Unix.chdir old)(fun()->
 Unix.chdir root;
 let records=List.map(Record.check_record(Record.schema()))records in
 let native=ok(K.native_clock())in
 ignore(Host_clock.parse ~now:(Unix.gettimeofday())clock_tracking);
 let now=stamp(Int64.to_float native.utc_ns/.1e9)in
 let live=Live_plan.read ~path:database ~plan:K.fixed_plan in
 let projected=Checker.reclaim_set_projection ~now_ns:native.utc_ns bindings records live in
 let report=Checker.audit ~root ~now projected in
 let findings=report.Checker.findings@Checker.coherence ~reclaim_set:bindings ~now_ns:native.utc_ns records live@Checker.final_time_findings ~now records in
 if findings<>[]then failwith(Yojson.Basic.to_string(Checker.findings_json findings));
 Checker.verify_again ~root report.evidence;
 (* Stable decision-bearing report; observation time is a distinct field in
    the stored report file, never a synthetic refresh of an old review. *)
 `Assoc["domain",s"uos.private-recovery-control-checker.v1";"status",s"PASS";
 "scope",s"COMPLETE_SYNTHETIC_FOUR_TASK_PLAN_NOT_CANONICAL_PREFLIGHT";
 "portfolio_sha256",s(K.sha256 raw);"snapshot_sha256",s(Live_plan.digest live);
 "clock_tracking_sha256",s(K.sha256 clock_tracking);
 "physical_sqlite",physical database;"vfs_source_manifest_sha256",s vfs_manifest;
 "ranked",Checker.order_json report.ranked;
 "evidence",`List(List.map(fun(p,h)->`Assoc["path",s p;"sha256",s h])report.evidence)])
let bindings request=
 let j=Yojson.Basic.from_string request in
 Yojson.Basic.Util.(to_list(member"old"j))|>List.map(fun j->text j"task",text j"worker",Yojson.Basic.Util.to_int(field j"attempt"),Int64.of_string(text j"lease"))
let check_saved locator request=
 let root=text locator"evidence_root"and database=text locator"database"in
 let report=checker root database(text locator"portfolio")(bindings request)(text locator"clock_tracking")(text locator"vfs_manifest")in
 need(K.sha256(Yojson.Basic.to_string report)=text locator"checker_sha256")"checker decision changed";
 report
let source_boundary locator=
 let raw=read(text locator"portfolio")in
 let records=Yojson.Basic.Util.to_list(Bounded.json_text raw)in
 let now=Record.now_utc()in
 let report=Checker.audit ~root:(text locator"evidence_root")~now
  (List.map(fun j->if text j"task_state"="executing"then set j"task_state"(s"available")else j)records)in
 need(report.Checker.findings=[]&&Checker.final_time_findings ~now records=[])"source/assessment expiry";
 Checker.verify_again ~root:(text locator"evidence_root")report.evidence;
 ignore(Host_clock.parse ~now:(Unix.gettimeofday())(text locator"clock_tracking"))

let draft driver ttl=
 need(ttl>=300&&ttl<=30000)"ttl bound";
 need(fixture_persist())"private persistent-WAL initializer";
 let root=text driver"source_root"in
 let source_evidence_root=text driver"evidence_root"in
 let binary=text driver"worker"and guardian=text driver"guardian"and launcher=text driver"launcher"and journal_worker=text driver"journal_worker"in
 let directory=Filename.temp_file"uos-control-private-"""in Unix.unlink directory;Unix.mkdir directory 0o700;
 let database=directory^"/tasks.sqlite3"and journal=directory^"/owner.sqlite3"in
 let clock=ok(K.native_clock())in
 let db=ok(S.open_db database)in Unix.chmod database 0o600;
 (* No schema initializer on the empty Store. Populate and close first. *)
 ignore(ok(S.create_plan db ~id:K.fixed_plan ~name:"private/control"~title:"PRIVATE synthetic recovery control"~now_ns:clock.utc_ns));
 let lease=Int64.mul(Int64.sub(Int64.div clock.utc_ns 1000000L)2000L)1000000L in
 List.iter(fun(id,worker)->ignore(ok(S.create_task db ~plan_id:K.fixed_plan ~id ~name:("private/"^id)~title:id ~parent_id:None ~dependencies:[]~priority:0~now_ns:clock.utc_ns));
 ignore(ok(S.claim_task db ~plan_id:K.fixed_plan ~task_id:id ~worker ~now_ns:(Int64.sub lease 1000000000L)~lease_ns:1000000000L)))K.fixed_members;
 ignore(ok(S.create_task db ~plan_id:K.fixed_plan ~id:"CONTROL_SENTINEL"~name:"private/sentinel"~title:"Fourth-row conservation sentinel"~parent_id:None ~dependencies:[]~priority:0~now_ns:clock.utc_ns));
 let _,snapshot=ok(S.recovery_snapshot_bounded db ~plan_id:K.fixed_plan)in S.close db;
 let prepared=ok(Recovery_adapter.prepare_private_existing_v7~database)in
 write(directory^"/schema-preparation.json")prepared;
 let pj=Bounded.json_text prepared in need(text pj"before_task_snapshot_sha256"=snapshot&&text pj"after_task_snapshot_sha256"=snapshot)"populated schema preparation snapshot conservation";
 need(text pj"snapshot_scope"="FIXED_PLAN_BOUNDED_PROJECTION")"preparation scope";
 List.iter(fun suffix->Unix.chmod(database^suffix)0o600)["-wal";"-shm"];
 with_db journal(fun db->Unix.chmod journal 0o600;List.iter(sql db)(["PRAGMA journal_mode=WAL";"PRAGMA synchronous=FULL"]@Recovery_owner_journal.schema_statements));
 let observed=stamp(Unix.gettimeofday()-.1.)and until=stamp(Unix.gettimeofday()+.120.)in
 let oldportfolio=Yojson.Basic.Util.to_list(json(text driver"seed_portfolio"))in
 let paths=List.concat_map(fun j->Yojson.Basic.Util.(to_list(member"evidence"(member"snapshot"j)))|>List.map(fun x->text x"path"))oldportfolio
  |>fun xs->"governance/planning/20260907-1559-risk-priority-record.schema.json"::xs
  |>List.sort_uniq String.compare in
 need(List.length paths>0&&List.length paths<=256)"complete source matrix bound";
 (* Only public captured source bytes move to private workspace storage. The
    synthetic task DB/sidecars retain their reviewed /tmp-only namespace. *)
 let evidence_directory=text driver"evidence_directory"in
 let metadata=Unix.lstat evidence_directory in
 need(String.starts_with~prefix:(root^"/var/harness/")evidence_directory&&Unix.realpath evidence_directory=evidence_directory
  &&metadata.Unix.st_kind=Unix.S_DIR&&metadata.Unix.st_uid=Unix.geteuid()&&metadata.Unix.st_perm land 0o077=0)"private evidence directory";
 let evidence_root=evidence_directory^"/source-evidence-"^Filename.basename directory in mkdir evidence_root;
 let total=ref 0 in
 let evs=`List(List.map(fun path->
  let bytes=Bounded.evidence ~root:source_evidence_root path in total:= !total+String.length bytes;need(!total<=16777216)"complete source byte bound";
  let target=evidence_root^"/"^path in mkdir(Filename.dirname target);write target bytes;
  need(Bounded.evidence ~root:evidence_root path=bytes)"private source mirror parity";
  `Assoc["path",s path;"sha256",s(K.sha256 bytes);"observed_at",s observed])paths)in
 let cwd=Sys.getcwd()in let sample=Fun.protect ~finally:(fun()->Unix.chdir cwd)(fun()->Unix.chdir root;Record.sample())in
 let rows=List.mapi(fun i(id,worker)->
 sample|>fun j->set j"assessment_id"(s("private-control-"^string_of_int i))|>fun j->set j"plan_id"(s K.fixed_plan)
 |>fun j->set j"task_id"(s id)|>fun j->set j"actor"(s worker)|>fun j->set j"scope"(s"PRIVATE fixture assessment; no independent review or real task authority")
 |>fun j->set j"task_state"(s(if i=3 then"available"else"executing"))|>fun j->set j"class"(s("P"^string_of_int i))
 |>fun j->set j"observed_at"(s observed)|>fun j->set j"valid_until"(s until)|>fun j->set j"ready_since"(s observed)
 |>fun j->set j"snapshot"(`Assoc["kind",s"working_tree";"reference",s"Every source reference from old matrix re-observed; full FOUR-row synthetic plan only";"evidence",evs]))
 (K.fixed_members@["CONTROL_SENTINEL","private-control-assessor"])in
 let portfolio=directory^"/portfolio.json"in write portfolio(Yojson.Basic.to_string(`List rows));
 let request_deadline=Int64.mul(Int64.add(Int64.div clock.utc_ns 1000000L)120000L)1000000L in
 let request=S.{reclaim_request_id="private-control-request";reclaim_plan_id=K.fixed_plan;expected_snapshot_sha256=snapshot;
 expired_tasks=List.map(fun(id,worker)->S.{reclaim_task_id=id;old_worker=worker;old_attempt=1;old_lease_until_ns=lease})K.fixed_members;
 reclaim_lease_ns=30000000000L;request_deadline_ns=request_deadline}in
 let factual_request_bytes=Yojson.Basic.to_string(`Assoc[
 "request_id",s request.reclaim_request_id;"plan",s K.fixed_plan;"snapshot_sha256",s("sha256:"^snapshot);
 "members",`List(List.map(fun t->`Assoc["task_id",s t.S.reclaim_task_id;"worker",s t.S.old_worker;"old_attempt",`Int t.S.old_attempt;"old_lease_ns",s(Int64.to_string t.S.old_lease_until_ns);"lease_ms",`Int 30000])request.expired_tasks);
 "deadline_utc_ms",`Int(Int64.to_int(Int64.div request_deadline 1000000L))])in
 let request_bytes=Sa_plan__Sa_plan_recovery_wire.canonical_bytes(ok(Sa_plan__Sa_plan_recovery_wire.decode factual_request_bytes))in
 let report=checker evidence_root database portfolio(bindings request_bytes)(text driver"clock_tracking")(text driver"vfs_manifest")in
 need(text report"snapshot_sha256"=snapshot)"Store/checker projection mismatch";
 let report_bytes=Yojson.Basic.to_string report in write(directory^"/checker.json")report_bytes;
 let cfg=Yojson.Basic.to_string(`Assoc["domain",s"uos.sa-plan.recovery-launcher-data.v1";"profile",s K.profile;
 "host",s(clock.host^".tail55d152.ts.net");"boot",s clock.boot;"epoch",s"1";
 "source_sha256",s(hash(root^"/engines/hermes/modules/sa_plan/sa_plan_store.ml"));"worker_sha256",s(hash binary);"guardian_sha256",s(hash guardian);
 "reviewer",signer"fixture-reviewer""fixture-review-session""fixture-review-key"'R';"issuer",signer"fixture-issuer""fixture-issuer-session""fixture-issuer-key"'I'])in
 let cfgpath=directory^"/kernel.json"in write cfgpath cfg;
 let opened=ok(R.open_owned database)and jo=ok(R.open_owned journal)in
 let anchor_bytes=Yojson.Basic.to_string(`Assoc["domain",s"uos.sa-plan.recovery-resource-anchor-data.v2";"kernel_configuration",s cfg;
 "database_resource",s"uos/canonical-sa-plan";"database_identity",R.identity_json opened;"journal_resource",s"uos/recovery-owner-journal";"journal_identity",R.identity_json jo;
 "owner",s"control-fixture-owner";"generation",s"1";"epoch",s"1";"launcher_sha256",s(hash launcher);
 "owner_source_sha256",s(hash(root^"/apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_owner.gleam"));"journal_worker_sha256",s(hash journal_worker)])in
 R.close opened;R.close jo;
 let _anchor=ok(R.anchor_data anchor_bytes)in let anchor_path=directory^"/anchor.json"in write anchor_path anchor_bytes;
 let config=Yojson.Basic.from_string cfg in
 let selection=Yojson.Basic.to_string(`Assoc["scope",s"FIXTURE_DISTINCT_CLASSES_NO_TIE";"ranked",field report"ranked"])in
 let factual=Yojson.Basic.to_string(`Assoc["scope",s"FIXTURE_TEST_TRUST_NOT_REAL_INDEPENDENT_APPROVAL";"checker_sha256",s(K.sha256 report_bytes)])in
 let expires=Int64.add clock.utc_ns(Int64.mul(Int64.of_int ttl)1000000L)in
 let cap=Yojson.Basic.to_string(`Assoc[
 "domain",s"uos.sa-plan.reclaim-three.effect-capability.v1";"profile",s K.profile;"configuration_sha256",s(K.sha256 cfg);"request_sha256",s(K.sha256 request_bytes);
 "evidence_sha256",s(K.sha256 report_bytes);"context_sha256",s(K.sha256 report_bytes);"proposal_sha256",s(K.sha256 request_bytes);
 "portfolio_sha256",s(hash portfolio);"selection_sha256",s(K.sha256 selection);"factual_review_sha256",s(K.sha256 factual);
 "source_sha256",field config"source_sha256";"worker_sha256",field config"worker_sha256";"guardian_sha256",field config"guardian_sha256";
 "reviewer",s"fixture-reviewer";"reviewer_session",s"fixture-review-session";"issuer",s"fixture-issuer";"issuer_session",s"fixture-issuer-session";
 "host",field config"host";"boot",s clock.boot;"clock_domain",s clock.domain;"epoch",s"1";
 "issued_utc_ns",s(Int64.to_string(Int64.sub clock.utc_ns 1000000000L));"expires_utc_ns",s(Int64.to_string expires);
 "issued_mono_ns",s(Int64.to_string(Int64.sub clock.mono_ns 1000000000L));"expires_mono_ns",s(Int64.to_string(Int64.add clock.mono_ns(Int64.mul(Int64.of_int ttl)1000000L)))])in

 let pin path hash=`Assoc["path",s path;"sha256",s hash]in
 let aj=Bounded.json_text anchor_bytes in
 let manifest=Yojson.Basic.to_string(`Assoc[
  "domain",s"uos.recovery.native-signing.launcher-fixture.v2";"intent_id",s request.reclaim_request_id;
  "kernel_configuration",s cfg;"resource_anchor",s anchor_bytes;"request",s request_bytes;"capability",s cap;
  "database",s database;"journal",s journal;
  "pins",`Assoc[
   "source",pin(root^"/engines/hermes/modules/sa_plan/sa_plan_store.ml")(text config"source_sha256");
   "worker",pin binary(text config"worker_sha256");"guardian",pin guardian(text config"guardian_sha256");
   "launcher",pin launcher(text aj"launcher_sha256");
   "owner_source",pin(root^"/apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_owner.gleam")(text aj"owner_source_sha256");
   "journal_worker",pin journal_worker(text aj"journal_worker_sha256")]])in
 let manifest_path=directory^"/native-signing-manifest.json"in write manifest_path manifest;
 let draft_path=directory^"/unsigned-draft.json"in
 let data=`Assoc["domain",s"PRIVATE_UNSIGNED_NATIVE_SIGNATURE_DRAFT";"driver",driver;
  "directory",s directory;"evidence_root",s evidence_root;"kernel_configuration",s cfg;"resource_anchor",s anchor_bytes;
  "request",s request_bytes;"factual_request",s factual_request_bytes;"capability",s cap;
  "manifest_path",s manifest_path;"manifest_sha256",s(K.sha256 manifest);
  "checker_sha256",s(K.sha256 report_bytes);"source_evidence_count",`Int(List.length paths)]in
 write draft_path(Yojson.Basic.to_string data);
 `Assoc["draft",s draft_path;"manifest_path",s manifest_path;"manifest_sha256",s(K.sha256 manifest);
  "intent_id",s request.reclaim_request_id;"request_sha256",s(K.sha256 request_bytes);"capability_sha256",s(K.sha256 cap)]

let finalize draft_path facts=
 let d=json draft_path in need(text d"domain"="PRIVATE_UNSIGNED_NATIVE_SIGNATURE_DRAFT")"draft domain";
 let driver=field d"driver"in
 let directory=text d"directory"in
 need(String.starts_with~prefix:"/tmp/uos-control-private-"directory&&Filename.dirname directory="/tmp"&&Unix.realpath directory=directory)"private draft directory";
 let cfg=text d"kernel_configuration"and anchor_bytes=text d"resource_anchor"and request_bytes=text d"request"and cap=text d"capability"in
 need(read(directory^"/kernel.json")=cfg&&read(directory^"/anchor.json")=anchor_bytes)"draft bytes changed";
 let report_bytes=read(directory^"/checker.json")in
 need(K.sha256 report_bytes=text d"checker_sha256")"checker changed";
 let manifest_bytes=capture(text d"manifest_path")in
 need(K.sha256 manifest_bytes=text d"manifest_sha256")"native signing manifest changed";
 let config_json=Bounded.json_text cfg and aj=Bounded.json_text anchor_bytes and report=Bounded.json_text report_bytes in
 let config=ok(K.configuration_data cfg)and anchor=ok(R.anchor_data anchor_bytes)in
 let request=Bounded.json_text request_bytes in
 let intent=text request"request_id"in
 let facts=match facts with `List xs when List.length xs=4->xs|_->failwith"exact four native facts required"in
 List.iteri(fun i f->
  let fs=match f with `Assoc fs->fs|_->failwith"signature object"in
  need(List.sort String.compare(List.map fst fs)=List.sort String.compare["status";"operation";"intent_id";"manifest_sha256";"request_sha256";"capability_sha256";"resource_sha256";"signature_hex";"authority";"admitted"])"signature fact schema";
  need(text f"status"="SIGNATURE_FACT_ONLY"&&text f"authority"="NONE"&&field f"admitted"=`Bool false
   &&text f"operation"=List.nth["review_kernel";"issue_kernel";"review_resource";"issue_resource"]i
   &&text f"intent_id"=intent&&text f"manifest_sha256"=text d"manifest_sha256"
   &&text f"request_sha256"=K.sha256 request_bytes&&text f"capability_sha256"=K.sha256 cap)"detached fact binding")facts;
 let signature i=text(List.nth facts i)"signature_hex"in
 let reviewer=signature 0 and issuer=signature 1 and rr=signature 2 and ri=signature 3 in
 ignore(ok(K.verify config~request_bytes~capability_bytes:cap~reviewer_signature:reviewer~issuer_signature:issuer));
 let resource=ok(R.resource_bytes anchor~request_bytes~capability_bytes:cap~reviewer_signature:reviewer~issuer_signature:issuer)in
 List.iteri(fun i f->need(field f"resource_sha256"=(if i<2 then`Null else s(K.sha256 resource)))"exact native resource digest")facts;
 let evidence=ok(R.verify anchor~request_bytes~capability_bytes:cap~reviewer_signature:reviewer~issuer_signature:issuer
  ~resource_bytes:resource~resource_reviewer_signature:rr~resource_issuer_signature:ri)in
 let database=directory^"/tasks.sqlite3"and journal=directory^"/owner.sqlite3"in
 need(physical database=field report"physical_sqlite")"signed main/WAL/SHM identities changed";
 let db=ok(R.open_owned database)in Fun.protect~finally:(fun()->R.close db)(fun()->
 let jo=ok(R.open_owned journal)in Fun.protect~finally:(fun()->R.close jo)(fun()->ignore(ok(R.check_effect_boundary evidence~database:db~journal:jo))));
 let binding=Yojson.Basic.to_string(`Assoc[
  "domain",s"uos.private-recovery-control-resource-receipt.v2";"request_sha256",s(K.sha256 request_bytes);"capability_sha256",s(K.sha256 cap);
  "resource_sha256",s(K.sha256 resource);"anchor_sha256",s(K.sha256 anchor_bytes);"checker_sha256",s(K.sha256 report_bytes);
  "configuration_sha256",s(K.sha256 cfg);"portfolio_sha256",field(Bounded.json_text cap)"portfolio_sha256";
  "source_sha256",field config_json"source_sha256";"worker_sha256",field config_json"worker_sha256";"guardian_sha256",field config_json"guardian_sha256";
  "launcher_sha256",field aj"launcher_sha256";"owner_source_sha256",field aj"owner_source_sha256";"journal_worker_sha256",field aj"journal_worker_sha256";
  "vfs_source_manifest_sha256",field report"vfs_source_manifest_sha256"])in
 let locator=`Assoc["domain",s"PRIVATE_RECOVERY_CONTROL_FIXTURE";"source_root",field driver"source_root";"evidence_root",field d"evidence_root";
  "database",s database;"journal",s journal;"kernel",s(directory^"/kernel.json");"kernel_sha256",s(K.sha256 cfg);
  "anchor",s(directory^"/anchor.json");"anchor_sha256",s(K.sha256 anchor_bytes);
  "resource",s resource;"resource_review",s rr;"resource_issuer",s ri;"portfolio",s(directory^"/portfolio.json");
  "checker_sha256",s(K.sha256 report_bytes);"clock_tracking",field driver"clock_tracking";"binding",s binding;
  "worker",field driver"worker";"guardian",field driver"guardian";"launcher",field driver"launcher";"journal_worker",field driver"journal_worker";"vfs_manifest",field driver"vfs_manifest"]in
 ignore(check_saved locator request_bytes);
 let locator_path=directory^"/locator.json"in write locator_path(Yojson.Basic.to_string locator);
 let body operation=Yojson.Basic.to_string(`Assoc["operation",s operation;"request",s request_bytes;"capability",s cap;"reviewer_signature",s reviewer;"issuer_signature",s issuer])in
 let result=`Assoc["directory",s directory;"locator",s locator_path;"journal",s journal;"factual_request",field d"factual_request";
  "context_sha256",s(K.sha256 report_bytes);"checker_status",s"PASS";"source_evidence_count",field d"source_evidence_count";
  "checker_sha256",s(K.sha256 report_bytes);"commit_body",s(body"commit");"inspect_body",s(body"inspect");
  "expires_utc_ns",field(Bounded.json_text cap)"expires_utc_ns";"signature_source",s"FOUR_GUARDED_NATIVE_V2_DETACHED_FACTS"]in
 write(directory^"/native-signature-facts.json")(Yojson.Basic.to_string(`List facts));
 write(directory^"/native-signed-ready.json")(Yojson.Basic.to_string result);
 write(text driver"evidence_directory"^"/"^Filename.basename directory^".json")(Yojson.Basic.to_string result);
 result
