type staging_root
type verified_batch
type promotion

type error =
  | Verifier_not_implemented
  | Invalid_staging_root of string
  | Missing_member of string
  | Verification_failure of string
  | Destination_conflict of string

val staging_root : project_root:string -> string -> (staging_root, error) result
val verify_one :
  manifest:Authority_manifest.t ->
  staged_root:staging_root ->
  authority_id:Source_artifact.Id.t ->
  (Source_artifact.receipt, error list) result
val verify_batch :
  manifest:Authority_manifest.t ->
  lock:Authority_lock.t ->
  staged_root:staging_root ->
  (verified_batch, error list) result
val receipts : verified_batch -> Source_artifact.receipt list
val promotion_plan : verified_batch -> promotion list