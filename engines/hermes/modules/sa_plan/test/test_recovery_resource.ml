(* Actual private SQLite + Ed25519 vectors. No canonical DB/keys/authority.
   The fixture owns its anchor bytes and expected digest independently of
   envelopes; production has no trusted anchor constructor or Store mutator. *)
module R=Recovery_resource
module K=Recovery_kernel
let count=ref 0
let check name b=incr count;if not b then failwith name
let ok=function Ok x->x|Error e->failwith e
let s x=`String x
let hash=K.sha256
let hex b=String.concat ""(List.init(String.length b)(fun i->Printf.sprintf"%02x"(Char.code b.[i])))
let key c=match Mirage_crypto_ec.Ed25519.priv_of_octets(String.make 32 c)with Ok x->x|Error _->failwith"key"
let public c=hex(Mirage_crypto_ec.Ed25519.pub_to_octets(Mirage_crypto_ec.Ed25519.pub_of_priv(key c)))
let sign c msg=hex(Mirage_crypto_ec.Ed25519.sign ~key:(key c)msg)
let signer subject session kid seed=`Assoc["subject",s subject;"session",s session;"kid",s kid;"public_key_hex",s(public seed)]
let write path bytes=let c=open_out_bin path in Fun.protect ~finally:(fun()->close_out c)(fun()->output_string c bytes);Unix.chmod path 0o600
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let sql p query=let db=Sqlite3.db_open p in Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db))(fun()->if Sqlite3.exec db query<>Sqlite3.Rc.OK then failwith"private SQL")
let probe_value db=let st=Sqlite3.prepare db"SELECT n FROM probe"in
 Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);ignore(Sys.opaque_identity db))(fun()->
  if Sqlite3.step st=Sqlite3.Rc.ROW then Sqlite3.column_int st 0 else failwith"probe row")
let replace j name value=match j with `Assoc fs->`Assoc(List.map(fun(k,v)->k,if k=name then value else v)fs)|_->failwith"object"
let ()=
 let dir=Filename.temp_file"uos-resource-v2-"""in Unix.unlink dir;Unix.mkdir dir 0o700;
 let a=dir^"/a.sqlite3"and b=dir^"/b.sqlite3"and j=dir^"/journal.sqlite3"in
 sql a"CREATE TABLE probe(n INTEGER); INSERT INTO probe VALUES(1)";Unix.chmod a 0o600;
 write b(read a);sql j"CREATE TABLE journal(n INTEGER)";Unix.chmod j 0o600;
 let da=ok(R.open_owned a)and db=ok(R.open_owned b)and journal=ok(R.open_owned j)in
 let clock=ok(K.native_clock())in
 let compiled=Filename.dirname Sys.executable_name in
 let source_file n=let local=compiled^"/"^n in if Sys.file_exists local then local else Filename.dirname compiled^"/"^n in
 let kernel_file=source_file"recovery_kernel.ml"and resource_file=source_file"recovery_resource.ml"in
 let source_pin=hash(read kernel_file)and worker_pin=hash(read Sys.executable_name)
 and owner_pin=hash(read resource_file)in
 let owned_source=dir^"/owner-source.ml"in write owned_source(read resource_file);
 let kernel_j=`Assoc["domain",s"uos.sa-plan.recovery-launcher-data.v1";"profile",s K.profile;
  "host",s(clock.host^".tail55d152.ts.net");"boot",s clock.boot;"epoch",s"3";
  "source_sha256",s source_pin;"worker_sha256",s worker_pin;"guardian_sha256",s worker_pin;
  "reviewer",signer"fixture-reviewer""review-session""review-key"'R';"issuer",signer"fixture-issuer""issue-session""issue-key"'I']in
 let kernel=Yojson.Basic.to_string kernel_j in
 let anchor_j=`Assoc["domain",s"uos.sa-plan.recovery-resource-anchor-data.v2";"kernel_configuration",s kernel;
  "database_resource",s"uos/canonical-sa-plan";"database_identity",R.identity_json da;
  "journal_resource",s"uos/recovery-owner-journal";"journal_identity",R.identity_json journal;
  "owner",s"fixture-owner";"generation",s"7";"epoch",s"3";
  (* This fixture's one compiled driver plays launcher/worker/journal roles.
     These pins are actual bytes, not production ownership/custody claims. *)
  "launcher_sha256",s worker_pin;"owner_source_sha256",s owner_pin;"journal_worker_sha256",s worker_pin]in
 let anchor_bytes=Yojson.Basic.to_string anchor_j in
 let anchor=ok(R.anchor_data anchor_bytes)in
 (* This local expected hash is a TEST-DRIVER anchor, not supplied by a request. *)
 let expected_anchor=hash anchor_bytes in
 check"driver anchor pinned independently"(R.anchor_sha256 anchor=expected_anchor);
 let request=Yojson.Basic.to_string(`Assoc["domain",s"uos.sa-plan.reclaim-three.v1";"request_id",s"resource-fixture";
  "plan",s K.fixed_plan;"snapshot",s(String.make 64 '1');
  "old",`List(List.map(fun(t,w)->`Assoc["task",s t;"worker",s w;"attempt",`Int 1;"lease",s"1"])K.fixed_members);
  "duration",s"10000000000";"deadline",s(Int64.to_string(Int64.add clock.utc_ns 60000000000L))])in
 let fields=match kernel_j with `Assoc fs->fs|_->assert false in
 let get k=List.assoc k fields in
 let cap=Yojson.Basic.to_string(`Assoc[
  "domain",s"uos.sa-plan.reclaim-three.effect-capability.v1";"profile",s K.profile;"configuration_sha256",s(hash kernel);"request_sha256",s(hash request);
  "evidence_sha256",s(String.make 64 'e');"context_sha256",s(String.make 64 'c');"proposal_sha256",s(String.make 64 'a');"portfolio_sha256",s(String.make 64 'b');"selection_sha256",s(String.make 64 'd');"factual_review_sha256",s(String.make 64 'f');
  "source_sha256",get"source_sha256";"worker_sha256",get"worker_sha256";"guardian_sha256",get"guardian_sha256";
  "reviewer",s"fixture-reviewer";"reviewer_session",s"review-session";"issuer",s"fixture-issuer";"issuer_session",s"issue-session";
  "host",get"host";"boot",get"boot";"clock_domain",s clock.domain;"epoch",s"3";
  "issued_utc_ns",s(Int64.to_string(Int64.sub clock.utc_ns 1000000000L));"expires_utc_ns",s(Int64.to_string(Int64.add clock.utc_ns 30000000000L));
  "issued_mono_ns",s(Int64.to_string(Int64.sub clock.mono_ns 1000000000L));"expires_mono_ns",s(Int64.to_string(Int64.add clock.mono_ns 30000000000L))])in
 let rs=sign 'R'(K.review_message cap)in let is=sign 'I'(K.issuer_message cap ~reviewer_signature:rs)in
 let body=ok(R.resource_bytes anchor ~request_bytes:request ~capability_bytes:cap ~reviewer_signature:rs ~issuer_signature:is)in
 let rr=sign 'R'(R.review_message body)in let ri=sign 'I'(R.issuer_message body ~reviewer_signature:rr)in
 let verify ?(anchor=anchor) ?(request=request) ?(cap=cap) ?(rs=rs) ?(is=is) ?(body=body) ?(rr=rr) ?(ri=ri)()=
  R.verify anchor ~request_bytes:request ~capability_bytes:cap ~reviewer_signature:rs ~issuer_signature:is ~resource_bytes:body ~resource_reviewer_signature:rr ~resource_issuer_signature:ri in
 let evidence=ok(verify())in
 let fixture_boundary evidence ~database ~journal=
  if R.evidence_anchor_sha256 evidence<>expected_anchor then Error"DRIVER_ANCHOR_MISMATCH"
  else if hash(read kernel_file)<>source_pin||hash(read owned_source)<>owner_pin||hash(read Sys.executable_name)<>worker_pin then Error"DRIVER_ACTUAL_SOURCE_ARTIFACT_DRIFT"
  else R.check_effect_boundary evidence ~database ~journal in
 check"valid doubly signed opened resource positive"(R.check_effect_boundary evidence ~database:da ~journal=Ok());
 check"actual SQLite clone has identical bytes"(read a=read b);
 check"actual cloned SQLite B cannot substitute A"(Result.is_error(R.check_effect_boundary evidence ~database:db ~journal));
 check"DB journal role alias refused"(Result.is_error(R.check_effect_boundary evidence ~database:da ~journal:da));
 let invalid_review=String.make 128 '0'in
 check"wrong resource reviewer signature with otherwise correctly linked issuer"(Result.is_error(verify ~rr:invalid_review ~ri:(sign 'I'(R.issuer_message body ~reviewer_signature:invalid_review))()));
 check"wrong resource issuer signature"(Result.is_error(verify ~ri:(String.make 128 '0')()));
 let wrong=Yojson.Basic.to_string(replace(Yojson.Basic.from_string body)"owner"(s"other-owner"))in
 check"changed unsigned owner refuses"(Result.is_error(verify ~body:wrong()));
 let signed_wrong_review=sign 'R'(R.review_message wrong)in
 check"valid signatures on wrong owner still refuse fixed anchor binding"
  (Result.is_error(verify ~body:wrong ~rr:signed_wrong_review ~ri:(sign 'I'(R.issuer_message wrong ~reviewer_signature:signed_wrong_review))()));
 check"cross-purpose signature refuses"(Result.is_error(verify ~rr:(sign 'R'(R.issuer_message body ~reviewer_signature:rr))()));
 let changed_generation=ok(R.anchor_data(Yojson.Basic.to_string(replace anchor_j "generation"(s"9"))))in
 check"signed generation cannot be rebound"(Result.is_error(verify ~anchor:changed_generation()));
 check"mismatched kernel and resource epoch refuses at parse"(Result.is_error(R.anchor_data(Yojson.Basic.to_string(replace anchor_j "epoch"(s"9")))));
 let changed_kernel=Yojson.Basic.to_string(replace kernel_j "epoch"(s"9"))in
 let changed_epoch=ok(R.anchor_data(Yojson.Basic.to_string(replace(replace anchor_j "epoch"(s"9"))"kernel_configuration"(s changed_kernel))))in
 check"coherent replacement epoch cannot reuse signed envelope"(Result.is_error(verify ~anchor:changed_epoch()));
 let foreign_anchor=ok(R.anchor_data(Yojson.Basic.to_string(replace anchor_j "database_identity"(R.identity_json db))))in
 check"caller-supplied matching clone metadata cannot reuse signed envelope"(Result.is_error(verify ~anchor:foreign_anchor()));
 List.iter(fun field->let changed=Yojson.Basic.to_string(replace anchor_j field(s(String.make 64 '0')))in
  let data=ok(R.anchor_data changed)in
  check("signed exact artifact pin "^field)(Result.is_error(verify ~anchor:data())))
  ["launcher_sha256";"owner_source_sha256";"journal_worker_sha256"];
 List.iter(fun bad->check"strict v2 anchor canonical parsing"(Result.is_error(R.anchor_data bad)))
  ["/*comment*/"^anchor_bytes;anchor_bytes^"/*comment*/";" "^anchor_bytes;anchor_bytes^"\000";String.make 32769 'x';
   "{domain:"^String.sub anchor_bytes 10(String.length anchor_bytes-10)];
 (* Public verification under supplied keys remains evidence-only. A fixture
    launcher uses its independent expected anchor, never request-supplied keys. *)
 let hostile_kernel=kernel_j|>fun k->replace(replace k "reviewer"(signer"other-reviewer""other-review-session""other-review-key"'X'))"issuer"(signer"other-issuer""other-issue-session""other-issue-key"'Y')in
 let hostile_config=Yojson.Basic.to_string hostile_kernel in
 let hostile_anchor=ok(R.anchor_data(Yojson.Basic.to_string(replace anchor_j "kernel_configuration"(s hostile_config))))in
 let hostile_cap=Yojson.Basic.from_string cap|>fun c->replace c "configuration_sha256"(s(hash hostile_config))
  |>fun c->replace(replace(replace(replace c "reviewer"(s"other-reviewer"))"reviewer_session"(s"other-review-session"))"issuer"(s"other-issuer"))"issuer_session"(s"other-issue-session")
  |>Yojson.Basic.to_string in
 let hostile_rs=sign 'X'(K.review_message hostile_cap)in
 let hostile_is=sign 'Y'(K.issuer_message hostile_cap ~reviewer_signature:hostile_rs)in
 let hostile_body=ok(R.resource_bytes hostile_anchor ~request_bytes:request ~capability_bytes:hostile_cap ~reviewer_signature:hostile_rs ~issuer_signature:hostile_is)in
 let hostile_rr=sign 'X'(R.review_message hostile_body)in
 let hostile_ri=sign 'Y'(R.issuer_message hostile_body ~reviewer_signature:hostile_rr)in
 let hostile=ok(verify ~anchor:hostile_anchor ~cap:hostile_cap ~rs:hostile_rs ~is:hostile_is ~body:hostile_body ~rr:hostile_rr ~ri:hostile_ri())in
 check"provided hostile keys can prove only their own evidence"(R.evidence_anchor_sha256 hostile=R.anchor_sha256 hostile_anchor);
 check"independent driver anchor refuses self-signed alternate keys"(Result.is_error(fixture_boundary hostile ~database:da ~journal));
 let current_history=ok(R.verify_history anchor ~request_bytes:request ~capability_bytes:cap ~reviewer_signature:rs ~issuer_signature:is ~resource_bytes:body ~resource_reviewer_signature:rr ~resource_issuer_signature:ri)in
 check"historical wrapper checks only resource identity"(R.check_history_boundary current_history ~database:da ~journal=Ok());
 let expired=Yojson.Basic.from_string cap|>fun c->
  replace(replace(replace(replace c "issued_utc_ns"(s(Int64.to_string(Int64.sub clock.utc_ns 2000000000L))))
   "expires_utc_ns"(s(Int64.to_string(Int64.sub clock.utc_ns 100000000L))))
   "issued_mono_ns"(s(Int64.to_string(Int64.sub clock.mono_ns 2000000000L))))
   "expires_mono_ns"(s(Int64.to_string(Int64.sub clock.mono_ns 100000000L)))|>Yojson.Basic.to_string in
 let ex_rs=sign 'R'(K.review_message expired)in let ex_is=sign 'I'(K.issuer_message expired ~reviewer_signature:ex_rs)in
 let ex_body=ok(R.resource_bytes anchor ~request_bytes:request ~capability_bytes:expired ~reviewer_signature:ex_rs ~issuer_signature:ex_is)in
 let ex_rr=sign 'R'(R.review_message ex_body)in let ex_ri=sign 'I'(R.issuer_message ex_body ~reviewer_signature:ex_rr)in
 check"fully signed expired v2 cannot yield fresh evidence"(Result.is_error(verify ~cap:expired ~rs:ex_rs ~is:ex_is ~body:ex_body ~rr:ex_rr ~ri:ex_ri()));
 let expired_history=ok(R.verify_history anchor ~request_bytes:request ~capability_bytes:expired ~reviewer_signature:ex_rs ~issuer_signature:ex_is ~resource_bytes:ex_body ~resource_reviewer_signature:ex_rr ~resource_issuer_signature:ex_ri)in
 check"expired signed history can check only exact opened objects"(R.check_history_boundary expired_history ~database:da ~journal=Ok());
 check"oversized factual request refused before hashing"(Result.is_error(R.resource_bytes anchor ~request_bytes:(String.make 32769 'x') ~capability_bytes:cap ~reviewer_signature:rs ~issuer_signature:is));
 check"oversized legacy capability refused before hashing"(Result.is_error(R.resource_bytes anchor ~request_bytes:request ~capability_bytes:(String.make 32769 'x') ~reviewer_signature:rs ~issuer_signature:is));
 check"oversized signature refused before hashing"(Result.is_error(R.resource_bytes anchor ~request_bytes:request ~capability_bytes:cap ~reviewer_signature:(String.make 129 '0') ~issuer_signature:is));
 check"empty request refused"(Result.is_error(R.resource_bytes anchor ~request_bytes:"" ~capability_bytes:cap ~reviewer_signature:rs ~issuer_signature:is));
 let link=dir^"/symbolic"in Unix.symlink a link;
 check"symbolic locator rejected"(Result.is_error(R.open_owned link));Unix.unlink link;
 check"relative locator rejects"(Result.is_error(R.open_owned"relative.sqlite3"));
 check"dotdot locator rejects"(Result.is_error(R.open_owned(dir^"/../a.sqlite3")));
 Unix.chmod a 0o644;check"publicly readable file refuses"(Result.is_error(R.check_opened da));Unix.chmod a 0o600;
 let hard=dir^"/hard"in Unix.link a hard;
 check"hardlink alias rejected"(Result.is_error(R.open_owned hard));
 check"held fd notices new hardlink"(Result.is_error(R.check_opened da));Unix.unlink hard;
 let saved=dir^"/saved.sqlite3"in Unix.rename a saved;write a(read b);
 check"held descriptor retains old inode but replacement locator refuses"(Result.is_error(R.check_effect_boundary evidence ~database:da ~journal));
 check"new opened replacement refuses signed old identity"(let replacement=ok(R.open_owned a)in Fun.protect ~finally:(fun()->R.close replacement)(fun()->Result.is_error(R.check_effect_boundary evidence ~database:replacement ~journal)));
 Unix.unlink a;Unix.rename saved a;
 check"restoring genuine original path identity positive"(R.check_effect_boundary evidence ~database:da ~journal=Ok());
 let old_j=j^".saved"in Unix.rename j old_j;write j(read b);
 check"actual journal identity swap refuses"(Result.is_error(fixture_boundary evidence ~database:da ~journal));
 Unix.unlink j;Unix.rename old_j j;
 let old_dir=dir^".saved"in Unix.rename dir old_dir;Unix.mkdir dir 0o700;
 List.iter(fun name->write(dir^"/"^name)(read(old_dir^"/"^name)))["a.sqlite3";"b.sqlite3";"journal.sqlite3";"owner-source.ml"];
 check"actual owned parent directory swap refuses"(Result.is_error(fixture_boundary evidence ~database:da ~journal));
 List.iter(fun name->Unix.unlink(dir^"/"^name))["a.sqlite3";"b.sqlite3";"journal.sqlite3";"owner-source.ml"];Unix.rmdir dir;Unix.rename old_dir dir;
 check"genuine directory restoration positive"(fixture_boundary evidence ~database:da ~journal=Ok());
 let original_source=read owned_source in write owned_source(original_source^"\n");
 check"actual private source drift refuses at fixture effect boundary"(Result.is_error(fixture_boundary evidence ~database:da ~journal));write owned_source original_source;
 (* Actual fixture effect at the checked boundary. SQLite opens a pathname;
    this proves only cooperative frozen-path fixture behavior, not FD-VFS. *)
 ignore(ok(fixture_boundary evidence ~database:da ~journal));
 let sqlite=Sqlite3.db_open ~mode:`NO_CREATE a in
 ignore(ok(fixture_boundary evidence ~database:da ~journal));
 check"private checked SQLite effect"(Sqlite3.exec sqlite"UPDATE probe SET n=2"=Sqlite3.Rc.OK);
 ignore(Sqlite3.db_close sqlite);
 (* Falsify the tempting claim that an owned fd pins SQLite's open: swap the
    pathname AFTER a valid check. SQLite opens B's inode; a second fd check
    refuses before any fixture UPDATE. This is a visible production blocker. *)
 ignore(ok(fixture_boundary evidence ~database:da ~journal));
 Unix.rename a saved;write a(read b);
 let reopened=Sqlite3.db_open ~mode:`NO_CREATE a in
 check"SQLite pathname reopen can select substituted clone"(not((Unix.stat a).Unix.st_ino=(Unix.stat saved).Unix.st_ino));
 check"actual SQLite connection read proves clone B was opened"(probe_value reopened=1);
 check"post-open actual descriptor check refuses before fixture mutation"(Result.is_error(fixture_boundary evidence ~database:da ~journal));
 ignore(Sqlite3.db_close reopened);Unix.unlink a;Unix.rename saved a;
 check"SQLite FD seam is explicitly unproved"(R.sqlite_descriptor_binding="SQLITE_REOPENS_PATH_NOT_DESCRIPTOR_BOUND");
 check"production always HOLD despite valid signatures"(R.production_status()="ADMITTED_RESOURCE_AUTHORITY_UNAVAILABLE");
 R.close da;check"closed held fd refuses"(Result.is_error(R.check_opened da));R.close da;R.close db;R.close journal;
 List.iter(fun p->if Sys.file_exists p then Unix.unlink p)[a;b;j;owned_source];Unix.rmdir dir;
 Printf.printf"PASS %d resource-v2 checks authority=NONE sqlite_descriptor_binding=UNPROVED\n"!count
