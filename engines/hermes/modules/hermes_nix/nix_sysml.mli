(** SysML v2 architectural blocks, ports, and formal obligations for Nix & Devenv. *)

type block_kind =
  | Substrate_store_block
  | Evaluator_block
  | Flake_lock_manager_block
  | Flake_security_auditor_block
  | Devenv_runtime_block
  | Process_compose_supervisor_block
  | Intent_admission_controller_block

type port_direction = In | Out | InOut

type port = {
  name : string;
  direction : port_direction;
  payload_type : string;
}

type constraint_rule = {
  id : string;
  name : string;
  expression : string;
  formal_solver : string; (* e.g., "Z3", "Why3", "Rocq" *)
}

type sysml_block = {
  kind : block_kind;
  name : string;
  ports : port list;
  constraints : constraint_rule list;
}

val all_blocks : sysml_block list
val find_block : block_kind -> sysml_block option
val to_sysml_v2_dsl : sysml_block -> string
val to_yojson : sysml_block -> Yojson.Safe.t
