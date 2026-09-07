(** MirageOS Zero-Trust Tool Interceptor Unikernel (EV-87) *)

type intercept_verdict =
  | Admitted of string
  | Trapped_null_byte
  | Trapped_sql_injection of string
  | Trapped_unauthorized

val inspect_payload : string -> intercept_verdict
val sign_admission_receipt : secret_seed:string -> string -> (string, string) result
val verify_admission_receipt : public_key_octets:string -> string -> signature:string -> bool
