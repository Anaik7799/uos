type t =
  | Ping_daemon
  | Eval_flake_attr
  | Eval_raw_expr
  | Build_flake_attr
  | Build_derivation
  | Flake_lock
  | Flake_audit
  | Flake_bom
  | Store_verify
  | Store_gc
  | Devenv_shell
  | Devenv_up
  | Devenv_test
  | Devenv_build
  | Devenv_gc
  | Devenv_info

type declaration = {
  key : string;
  description : string;
  read_only : bool;
  ontology_level : Nix_ontology.level;
}

let all =
  [ Ping_daemon;
    Eval_flake_attr;
    Eval_raw_expr;
    Build_flake_attr;
    Build_derivation;
    Flake_lock;
    Flake_audit;
    Flake_bom;
    Store_verify;
    Store_gc;
    Devenv_shell;
    Devenv_up;
    Devenv_test;
    Devenv_build;
    Devenv_gc;
    Devenv_info ]

let declaration = function
  | Ping_daemon ->
      { key = "ping-daemon"; description = "Check Nix daemon connectivity"; read_only = true; ontology_level = Nix_ontology.L0 }
  | Eval_flake_attr ->
      { key = "eval-flake-attr"; description = "Evaluate attribute in flake"; read_only = true; ontology_level = Nix_ontology.L1 }
  | Eval_raw_expr ->
      { key = "eval-raw-expr"; description = "Evaluate raw Nix expression string"; read_only = true; ontology_level = Nix_ontology.L1 }
  | Build_flake_attr ->
      { key = "build-flake-attr"; description = "Build attribute in flake"; read_only = false; ontology_level = Nix_ontology.L1 }
  | Build_derivation ->
      { key = "build-derivation"; description = "Realize store derivation .drv"; read_only = false; ontology_level = Nix_ontology.L1 }
  | Flake_lock ->
      { key = "flake-lock"; description = "Resolve and update flake.lock"; read_only = false; ontology_level = Nix_ontology.L2 }
  | Flake_audit ->
      { key = "flake-audit"; description = "Run security advisory audit via Determinate database"; read_only = true; ontology_level = Nix_ontology.L3 }
  | Flake_bom ->
      { key = "flake-bom"; description = "Generate Software Bill of Materials (SBOM)"; read_only = true; ontology_level = Nix_ontology.L3 }
  | Store_verify ->
      { key = "store-verify"; description = "Cryptographically verify store paths"; read_only = true; ontology_level = Nix_ontology.L0 }
  | Store_gc ->
      { key = "store-gc"; description = "Garbage collect unreferenced store paths"; read_only = false; ontology_level = Nix_ontology.L0 }
  | Devenv_shell ->
      { key = "devenv-shell"; description = "Instantiate developer shell environment"; read_only = true; ontology_level = Nix_ontology.L4 }
  | Devenv_up ->
      { key = "devenv-up"; description = "Supervise background services via process-compose"; read_only = false; ontology_level = Nix_ontology.L5 }
  | Devenv_test ->
      { key = "devenv-test"; description = "Execute devenv test suite and validation scripts"; read_only = true; ontology_level = Nix_ontology.L4 }
  | Devenv_build ->
      { key = "devenv-build"; description = "Build devenv environment container / package"; read_only = false; ontology_level = Nix_ontology.L4 }
  | Devenv_gc ->
      { key = "devenv-gc"; description = "Garbage collect old devenv profiles"; read_only = false; ontology_level = Nix_ontology.L4 }
  | Devenv_info ->
      { key = "devenv-info"; description = "Inspect active devenv configuration and variables"; read_only = true; ontology_level = Nix_ontology.L4 }

let find key =
  List.find_opt (fun op -> String.equal (declaration op).key key) all

let declaration_is_safe op =
  let d = declaration op in
  String.length d.key > 0 && String.length d.description > 0
