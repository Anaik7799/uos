(* Pure versioned specification. All request fields remain caller DATA. *)
module V1=Recovery_schema_migration
type predecessor=Legacy_six|V1_with_receipts
type request={base:V1.request;predecessor:predecessor}
type error=V1.error=Authority_unavailable|Refused of string|Commit_unknown
let resource_schema=[
 "control_resource_receipt","CREATE TABLE control_resource_receipt(request_id TEXT PRIMARY KEY,binding_json TEXT NOT NULL)";
 "control_no_update","CREATE TRIGGER control_no_update BEFORE UPDATE ON control_resource_receipt BEGIN SELECT RAISE(ABORT,'control receipts are append-only'); END";
 "control_no_delete","CREATE TRIGGER control_no_delete BEFORE DELETE ON control_resource_receipt BEGIN SELECT RAISE(ABORT,'control receipts are append-only'); END"]
let schema=V1.schema V1.Task_store@resource_schema
let receipt_schema=V1.receipt_schema V1.Task_store
let predecessor_schema=function
 |Legacy_six->V1.schema V1.Task_store
 |V1_with_receipts->V1.schema V1.Task_store@receipt_schema
let request_bytes r=Yojson.Basic.to_string(`Assoc[
 "domain",`String"uos.recovery-schema-migration-data.v2";
 "from_profile",`String(match r.predecessor with Legacy_six->"task_store_v7_extensions_v1_legacy_six"|V1_with_receipts->"task_store_v7_extensions_v1_with_receipts");
 "to_profile",`String"task_store_v7_extensions_v2_resource_receipt";
 "base_v1_data",Yojson.Basic.from_string(V1.request_bytes r.base)])
let validate r=match V1.validate r.base with
 |Error e->Error e
 |Ok()->if r.base.target=V1.Task_store then Ok()else Error(Refused"TASK_STORE_ONLY")
let migrate _=Error Authority_unavailable
