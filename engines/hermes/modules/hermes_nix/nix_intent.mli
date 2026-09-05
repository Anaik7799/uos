(** Strongly typed declarative intent for controlled Nix and Devenv execution.
    No effect is performed until validated and admitted by governance. *)

type eval_target =
  | Flake_attribute of { flake_ref : Nix_id.Flake_ref.t; attr : Nix_id.Attribute_path.t }
  | Raw_expression of { expr : string }
  | File_expression of { path : string }

type build_target =
  | Build_flake_attr of { flake_ref : Nix_id.Flake_ref.t; attr : Nix_id.Attribute_path.t }
  | Build_drv of { drv_path : Nix_id.Store_path.t }
  | Build_store_path of { path : Nix_id.Store_path.t }

type devenv_action =
  | Shell of { print_bash : bool }
  | Up of { detach : bool; services : Nix_id.Service_name.t list }
  | Test
  | Build
  | Gc of { max_freed_mb : int option }
  | Info

type flake_security_action =
  | Audit
  | Generate_bom
  | Verify_provenance of { expected_commit : string }

type t =
  | Evaluate of { target : eval_target; budget : Nix_budget.t; pure : bool }
  | Build of { target : build_target; budget : Nix_budget.t; keep_going : bool }
  | Shell_environment of { flake_ref : Nix_id.Flake_ref.t; budget : Nix_budget.t }
  | Flake_lock of { flake_ref : Nix_id.Flake_ref.t; update_all : bool }
  | Flake_security of { flake_ref : Nix_id.Flake_ref.t; action : flake_security_action }
  | Store_verify of { paths : Nix_id.Store_path.t list; repair : bool }
  | Store_gc of { max_freed_bytes : int64 option }
  | Devenv_execute of { root : Nix_id.Devenv_root.t; action : devenv_action; budget : Nix_budget.t }

val intent_id : t -> Nix_id.Intent_id.t
val is_read_only : t -> bool
val target_summary : t -> string
val to_yojson : t -> Yojson.Safe.t
