(** Solo5 Tender Sandboxing & Unikernel Manifest Generation (EV-87) *)

type tender_config = {
  manifest : Mirage_signatures.unikernel_manifest;
  memory_limit_mb : int;
  seccomp_enabled : bool;
  read_only_root : bool;
  network_tap : string option;
}

val default_tender_config : string -> tender_config
val generate_manifest_json : tender_config -> string
val verify_sandbox_safety : tender_config -> (unit, string) result
val cold_start_estimate_ms : tender_config -> float
