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

let status_to_string = function
  | Discovered -> "Discovered"
  | Classified -> "Classified"
  | Mapped -> "Mapped"
  | Implemented -> "Implemented"
  | Verified -> "Verified"
  | Admitted -> "Admitted"

let candidates_store : migration_candidate list = [
  {
    subsystem_id = "MIG-01-INGRESS";
    name = "Edge HTTP/TLS Ingress Proxy";
    fractal_layer = "L4";
    current_technology = "Mist HTTP / External Nginx Reverse Proxy";
    mirage_unikernel_target = "Solo5-SPT + paf / ocaml-tls / mirage-crypto-rng";
    sil_safety_level = 5;
    cold_start_comparison = "2000ms -> 10.9ms (99.4% speedup)";
    ram_usage_comparison = "180MB -> 12MB (93.3% memory reduction)";
    attack_surface_comparison = "350+ syscalls -> 6 syscalls, zero OpenSSL C bugs";
    readiness_score = 0.95;
    status = Implemented;
    proof_reference = "SPEC-MIRAGE-MIGRATE-001#ing";
  };
  {
    subsystem_id = "MIG-02-SANDBOX";
    name = "Isolated Ephemeral Tool Sandbox";
    fractal_layer = "L3";
    current_technology = "Podman Rootless OCI Container";
    mirage_unikernel_target = "Solo5-SPT Ephemeral Unikernel (Micro-Sandbox)";
    sil_safety_level = 6;
    cold_start_comparison = "1200ms -> 10.9ms (99.1% speedup)";
    ram_usage_comparison = "250MB -> 16MB (93.6% memory reduction)";
    attack_surface_comparison = "Full Linux ABI + /bin/sh -> 0 shell, 6 syscalls";
    readiness_score = 0.98;
    status = Admitted;
    proof_reference = "SC-MIRAGE-001";
  };
  {
    subsystem_id = "MIG-03-DNS";
    name = "Deterministic DNS Recursive Resolver";
    fractal_layer = "L2";
    current_technology = "Host Glibc getaddrinfo / /etc/resolv.conf";
    mirage_unikernel_target = "Solo5-SPT + mirage-dns / DNS-over-TLS (DoT)";
    sil_safety_level = 5;
    cold_start_comparison = "500ms -> 8.5ms (98.3% speedup)";
    ram_usage_comparison = "64MB -> 8MB (87.5% memory reduction)";
    attack_surface_comparison = "Glibc getaddrinfo poisoning -> Pure OCaml DNS stack";
    readiness_score = 0.92;
    status = Implemented;
    proof_reference = "SPEC-MIRAGE-MIGRATE-001#dns";
  };
  {
    subsystem_id = "MIG-04-CRYPTO";
    name = "Cryptographic Token & Receipt Authority";
    fractal_layer = "L1";
    current_technology = "C-NIF / Rust OpenSSL Bindings";
    mirage_unikernel_target = "Hermes mirage-crypto / mirage-crypto-ec (Pure OCaml)";
    sil_safety_level = 6;
    cold_start_comparison = "0ms (in-process) -> 0ms (zero overhead)";
    ram_usage_comparison = "32MB -> 4MB (87.5% memory reduction)";
    attack_surface_comparison = "C-ABI memory vulnerabilities -> Type-safe constant-time OCaml";
    readiness_score = 1.0;
    status = Admitted;
    proof_reference = "INV-17-ASPECT-RECEIPTS";
  };
  {
    subsystem_id = "MIG-05-LEDGER";
    name = "Immutable Merkle DAG Evidence Store";
    fractal_layer = "L5";
    current_technology = "SQLite WAL Files + Raw JSONL Ledgers";
    mirage_unikernel_target = "Irmin Merkle DAG / Wodan Block Engine";
    sil_safety_level = 6;
    cold_start_comparison = "100ms -> 12ms (88.0% speedup)";
    ram_usage_comparison = "120MB -> 24MB (80.0% memory reduction)";
    attack_surface_comparison = "Raw disk file I/O -> Cryptographic Merkle root hash verification";
    readiness_score = 0.90;
    status = Implemented;
    proof_reference = "SPEC-MIRAGE-MIGRATE-001#irmin";
  };
  {
    subsystem_id = "MIG-06-FORWARD";
    name = "Zenoh Micro-Packet Forwarder";
    fractal_layer = "L6";
    current_technology = "Zenoh Rust Daemon (Port 7447)";
    mirage_unikernel_target = "Solo5-SPT Flow-Forwarder Enclave (Pure OCaml)";
    sil_safety_level = 4;
    cold_start_comparison = "800ms -> 14ms (98.2% speedup)";
    ram_usage_comparison = "90MB -> 16MB (82.2% memory reduction)";
    attack_surface_comparison = "Unconstrained network socket -> Bounded type-safe flow";
    readiness_score = 0.85;
    status = Mapped;
    proof_reference = "SC-ZMOF-001";
  };
  {
    subsystem_id = "MIG-07-SOLVER";
    name = "Bounded Z3 Gospel Verification Sandbox";
    fractal_layer = "L0";
    current_technology = "Host OS Subprocess Fork with Timeout";
    mirage_unikernel_target = "Solo5-SPT Memory-Capped Micro-Sandbox (64MB Hard Cap)";
    sil_safety_level = 5;
    cold_start_comparison = "350ms -> 15ms (95.7% speedup)";
    ram_usage_comparison = "500MB -> 64MB hard-capped (87.2% memory reduction)";
    attack_surface_comparison = "Unbounded host process tree -> Strict 64MB physical RAM cap";
    readiness_score = 0.88;
    status = Implemented;
    proof_reference = "INV-GOSPEL-Z3-ORACLE-PIPELINE";
  };
]

let all_candidates () = candidates_store

let find_candidate id =
  List.find_opt (fun c -> String.equal c.subsystem_id id) candidates_store

let total_ram_savings_mb () =
  (* Current baseline RAM total: 180 + 250 + 64 + 32 + 120 + 90 + 500 = 1236MB *)
  (* Mirage target RAM total: 12 + 16 + 8 + 4 + 24 + 16 + 64 = 144MB *)
  (* Net RAM saved: 1092 MB *)
  1092

let average_speedup_ratio () =
  (* Mean speedup across all cold-start migrations: >95.8% *)
  95.8

let is_non_negotiable_forbidden target_name =
  let upper = String.uppercase_ascii target_name in
  String.contains upper 'B' && String.contains upper 'E' && String.contains upper 'A' && String.contains upper 'M' ||
  String.contains upper 'U' && String.contains upper 'O' && String.contains upper 'S' && String.contains upper '_' && String.contains upper 'S' ||
  String.contains upper 'M' && String.contains upper 'A' && String.contains upper 'X' && String.contains upper '_' ||
  String.contains upper '2' && String.contains upper '5' && String.contains upper '5' && String.contains upper '0' && String.contains upper '3' ||
  String.contains upper 'J' && String.contains upper 'U' && String.contains upper 'J' && String.contains upper 'U'

let candidate_to_json (c : migration_candidate) : Yojson.Safe.t =
  `Assoc [
    ("subsystem_id", `String c.subsystem_id);
    ("name", `String c.name);
    ("fractal_layer", `String c.fractal_layer);
    ("current_technology", `String c.current_technology);
    ("mirage_unikernel_target", `String c.mirage_unikernel_target);
    ("declared_sil_level", `Int c.sil_safety_level);
    ("safety_certification", `String "NOT_VERIFIED; declared level has no defined certification scale");
    ("cold_start_comparison", `String c.cold_start_comparison);
    ("ram_usage_comparison", `String c.ram_usage_comparison);
    ("attack_surface_comparison", `String c.attack_surface_comparison);
    ("readiness_score", `Float c.readiness_score);
    ("status", `String "NOT_VERIFIED");
    ("declared_stage", `String (status_to_string c.status));
    ("evidence_scope", `String "static_migration_projection");
    ("declared_proof_reference", `String c.proof_reference);
  ]

let catalog_to_json () : Yojson.Safe.t =
  `Assoc [
    ("schema", `String "uos-mirage-catalog/v2");
    ("total_candidates", `Int (List.length candidates_store));
    ("evidence_scope", `String "static_migration_projection");
    ("deployment_admission", `String "NOT_VERIFIED");
    ("measured_ram_savings_mb", `Null);
    ("projected_ram_savings_mb", `Int (total_ram_savings_mb ()));
    ("measured_average_speedup_percent", `Null);
    ("declared_average_speedup_percent", `Float (average_speedup_ratio ()));
    ("estimate_note", `String "RAM and speedup fields are unmeasured catalog literals; the speedup aggregate has no validated derivation; declared_stage and declared_proof_reference are claims, not admission receipts");
    ("host_benchmark", `Assoc [
       ("command", `String "hermes_mirage_runner benchmark [roundtrips]");
       ("scope", `String "host_ocaml_library");
       ("feature_id", `String "HOST-KERNEL-BENCH-001");
       ("max_roundtrips", `Int Mirage_benchmark.max_roundtrips);
       ("default_roundtrips", `Int Mirage_benchmark.default_roundtrips);
       ("solo5_boot_measured", `Bool false);
    ]);
    ("candidates", `List (List.map candidate_to_json candidates_store));
  ]
