(* LOCAL CODEX relay. No issuer/owner is provisioned by this specification.
   Schema bytes mirror reviewed UOS source; parity is tested, not inferred. *)
type target = Task_store | Owner_journal
type request = {migration_id:string;resource_id:string;database:string;device:int;
  inode:int;target:target;source_sha256:string;before_schema_sha256:string;
  expires_utc_ns:int64;expires_mono_ns:int64}
type error = Authority_unavailable | Refused of string | Commit_unknown
let schema = function
 | Task_store -> [
 "sa_plan_reclaim_receipt","CREATE TABLE sa_plan_reclaim_receipt (request_id TEXT PRIMARY KEY, request_sha256 TEXT NOT NULL, request_json TEXT NOT NULL, receipt_json TEXT NOT NULL)";
 "sa_plan_reclaim_no_update","CREATE TRIGGER sa_plan_reclaim_no_update BEFORE UPDATE ON sa_plan_reclaim_receipt BEGIN SELECT RAISE(ABORT,'reclaim receipts are append-only'); END";
 "sa_plan_reclaim_no_delete","CREATE TRIGGER sa_plan_reclaim_no_delete BEFORE DELETE ON sa_plan_reclaim_receipt BEGIN SELECT RAISE(ABORT,'reclaim receipts are append-only'); END";
 "sa_plan_recovery_cap_receipt","CREATE TABLE sa_plan_recovery_cap_receipt (request_id TEXT PRIMARY KEY, evidence_sha256 TEXT NOT NULL, capability_sha256 TEXT NOT NULL, receipt_json TEXT NOT NULL)";
 "sa_plan_recovery_cap_no_update","CREATE TRIGGER sa_plan_recovery_cap_no_update BEFORE UPDATE ON sa_plan_recovery_cap_receipt BEGIN SELECT RAISE(ABORT,'recovery capability receipts are append-only'); END";
 "sa_plan_recovery_cap_no_delete","CREATE TRIGGER sa_plan_recovery_cap_no_delete BEFORE DELETE ON sa_plan_recovery_cap_receipt BEGIN SELECT RAISE(ABORT,'recovery capability receipts are append-only'); END"]
 | Owner_journal -> [
 "recovery_owner_event","CREATE TABLE recovery_owner_event (sequence INTEGER PRIMARY KEY, request_sha256 TEXT NOT NULL, request_json TEXT NOT NULL, record_json TEXT NOT NULL)";
 "recovery_owner_no_update","CREATE TRIGGER recovery_owner_no_update BEFORE UPDATE ON recovery_owner_event BEGIN SELECT RAISE(ABORT,'recovery owner records are append-only'); END";
 "recovery_owner_no_delete","CREATE TRIGGER recovery_owner_no_delete BEFORE DELETE ON recovery_owner_event BEGIN SELECT RAISE(ABORT,'recovery owner records are append-only'); END"]
let receipt_schema target =
 let prefix=match target with Task_store->"sa_plan_recovery_migration"|Owner_journal->"recovery_migration"in
 [prefix^"_receipt","CREATE TABLE "^prefix^"_receipt (migration_id TEXT PRIMARY KEY, request_sha256 TEXT NOT NULL, request_json TEXT NOT NULL, receipt_json TEXT NOT NULL)";
  prefix^"_no_update","CREATE TRIGGER "^prefix^"_no_update BEFORE UPDATE ON "^prefix^"_receipt BEGIN SELECT RAISE(ABORT,'recovery migration receipts are append-only'); END";
  prefix^"_no_delete","CREATE TRIGGER "^prefix^"_no_delete BEFORE DELETE ON "^prefix^"_receipt BEGIN SELECT RAISE(ABORT,'recovery migration receipts are append-only'); END"]
let request_bytes r =
 let s x=`String x in Yojson.Basic.to_string(`Assoc[
 "domain",s"uos.recovery-schema-migration-data.v1";"migration_id",s r.migration_id;
 "resource_id",s r.resource_id;"database",s r.database;"device",`Int r.device;"inode",`Int r.inode;
 "target",s(match r.target with Task_store->"task_store_v7_extensions_v1"|Owner_journal->"owner_journal_v2");
 "source_sha256",s r.source_sha256;"before_schema_sha256",s r.before_schema_sha256;
 "expires_utc_ns",s(Int64.to_string r.expires_utc_ns);"expires_mono_ns",s(Int64.to_string r.expires_mono_ns)])
let validate r=
 let id s=String.length s>0&&String.length s<=160&&String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'.'|'/'->true|_->false)s in
 let digest s=String.length s=64&&String.for_all(function '0'..'9'|'a'..'f'->true|_->false)s in
 if id r.migration_id&&id r.resource_id&&Filename.is_relative r.database=false&&String.length r.database<=4096
 &&not(String.contains r.database '\000')&&r.device>=0&&r.inode>0&&digest r.source_sha256&&digest r.before_schema_sha256
 &&r.expires_utc_ns>0L&&r.expires_mono_ns>0L
 then Ok()else Error(Refused"INVALID_REQUEST_DATA")
let migrate _request=Error Authority_unavailable
