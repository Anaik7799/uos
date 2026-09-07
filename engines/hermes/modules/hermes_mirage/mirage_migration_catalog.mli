(* Unified Operational System (UOS) - MirageOS Subsystem Migration Catalog *)
(* Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001 *)

type migration_status =
  | Discovered
  | Classified
  | Mapped
  | Implemented
  | Verified
  | Admitted

type migration_candidate = {
  subsystem_id : string;
  name : string;
  fractal_layer : string;
  current_technology : string;
  mirage_unikernel_target : string;
  sil_safety_level : int;
  cold_start_comparison : string;
  ram_usage_comparison : string;
  attack_surface_comparison : string;
  readiness_score : float;
  status : migration_status;
  proof_reference : string;
}

val status_to_string : migration_status -> string
val all_candidates : unit -> migration_candidate list
val find_candidate : string -> migration_candidate option
val total_ram_savings_mb : unit -> int
val average_speedup_ratio : unit -> float
val is_non_negotiable_forbidden : string -> bool
val candidate_to_json : migration_candidate -> Yojson.Safe.t
val catalog_to_json : unit -> Yojson.Safe.t
