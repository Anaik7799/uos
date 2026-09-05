type domain =
  | Substrate_domain
  | Evaluation_domain
  | Flake_domain
  | Security_domain
  | Devenv_domain
  | Supervision_domain
  | Intent_bridge_domain

type capability = {
  name : string;
  domain : domain;
  ontology_level : Nix_ontology.level;
  read_only : bool;
  preconditions : string list;
  postconditions : string list;
  failure_modes : string list;
}

let domain_to_string = function
  | Substrate_domain -> "Substrate"
  | Evaluation_domain -> "Evaluation"
  | Flake_domain -> "Flake"
  | Security_domain -> "Security"
  | Devenv_domain -> "Devenv"
  | Supervision_domain -> "Supervision"
  | Intent_bridge_domain -> "Intent_bridge"

let all_capabilities =
  [ { name = "nix-daemon-ping";
      domain = Substrate_domain;
      ontology_level = Nix_ontology.L0;
      read_only = true;
      preconditions = [ "Socket /nix/var/nix/daemon-socket/socket exists or daemon running" ];
      postconditions = [ "Daemon availability confirmed" ];
      failure_modes = [ "Daemon_unreachable" ] };

    { name = "store-path-verify";
      domain = Substrate_domain;
      ontology_level = Nix_ontology.L0;
      read_only = true;
      preconditions = [ "Store paths exist in /nix/store" ];
      postconditions = [ "Cryptographic hash verified against SQLite DB" ];
      failure_modes = [ "Store_path_corrupted" ] };

    { name = "store-garbage-collect";
      domain = Substrate_domain;
      ontology_level = Nix_ontology.L0;
      read_only = false;
      preconditions = [ "No active build lock held" ];
      postconditions = [ "Unreferenced store paths reaped" ];
      failure_modes = [ "GC_lock_conflict" ] };

    { name = "eval-pure-expression";
      domain = Evaluation_domain;
      ontology_level = Nix_ontology.L1;
      read_only = true;
      preconditions = [ "Syntactically valid Nix expression"; "Bounded memory budget" ];
      postconditions = [ "Evaluated normal form returned without side effects" ];
      failure_modes = [ "Evaluation_error"; "Impure_access_blocked" ] };

    { name = "build-derivation";
      domain = Evaluation_domain;
      ontology_level = Nix_ontology.L1;
      read_only = false;
      preconditions = [ "Valid .drv store path"; "Sandboxed build environment" ];
      postconditions = [ "Realized store path created in /nix/store" ];
      failure_modes = [ "Derivation_build_failed" ] };

    { name = "flake-resolve-and-lock";
      domain = Flake_domain;
      ontology_level = Nix_ontology.L2;
      read_only = false;
      preconditions = [ "Valid flake.nix in workspace or URL" ];
      postconditions = [ "flake.lock generated or verified immutable" ];
      failure_modes = [ "Flake_resolution_failed" ] };

    { name = "flake-security-audit";
      domain = Security_domain;
      ontology_level = Nix_ontology.L3;
      read_only = true;
      preconditions = [ "Locked flake closure available" ];
      postconditions = [ "Vulnerability scan completed against Determinate advisory database" ];
      failure_modes = [ "Flake_audit_finding" ] };

    { name = "flake-bom-generate";
      domain = Security_domain;
      ontology_level = Nix_ontology.L3;
      read_only = true;
      preconditions = [ "Locked flake closure available" ];
      postconditions = [ "Software Bill of Materials generated in SPDX/CycloneDX format" ];
      failure_modes = [ "Flake_bom_mismatch" ] };

    { name = "devenv-shell-instantiate";
      domain = Devenv_domain;
      ontology_level = Nix_ontology.L4;
      read_only = true;
      preconditions = [ "devenv.nix present in target root" ];
      postconditions = [ "Hermetic shell environment and PATH derived" ];
      failure_modes = [ "Devenv_parse_error" ] };

    { name = "devenv-up-supervision";
      domain = Supervision_domain;
      ontology_level = Nix_ontology.L5;
      read_only = false;
      preconditions = [ "Declared services non-conflicting on local ports" ];
      postconditions = [ "Process-compose supervisor managing service lifecycle" ];
      failure_modes = [ "Devenv_service_failed" ] };

    { name = "typed-intent-admission";
      domain = Intent_bridge_domain;
      ontology_level = Nix_ontology.L6;
      read_only = true;
      preconditions = [ "Valid Nix_intent.t submitted" ];
      postconditions = [ "Intent validated against R31 policy and admitted" ];
      failure_modes = [ "Policy_violation" ] } ]

let find_capability name =
  List.find_opt (fun c -> String.equal c.name name) all_capabilities

let capabilities_by_domain d =
  List.filter (fun c -> c.domain = d) all_capabilities

let to_yojson c =
  `Assoc
    [ ("name", `String c.name);
      ("domain", `String (domain_to_string c.domain));
      ("level", `String (Nix_ontology.level_to_string c.ontology_level));
      ("read_only", `Bool c.read_only);
      ("preconditions", `List (List.map (fun s -> `String s) c.preconditions));
      ("postconditions", `List (List.map (fun s -> `String s) c.postconditions));
      ("failure_modes", `List (List.map (fun s -> `String s) c.failure_modes)) ]
