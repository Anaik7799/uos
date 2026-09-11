//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/central_code_distributed_run</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L4_SYSTEM</layer>
////     <layer>L7_FEDERATION</layer>
////     <mesh-domain>
////       Saṁvid Kendrīkṛta-Vyūha (संविद् केन्द्रीकृत-व्यूह): Centralized Code
////       Authority & Distributed Execution Fabric. Enforces single monorepo truth
////       on nas-1 with heterogeneous distributed run across vm-1 and razr15-1.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>
////       SC-CENTRAL-CODE-DISTRIBUTED-RUN-001, SC-RESOURCE-FABRIC-001,
////       SC-ZERO-MUDA-001, SC-JIDOKA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/json
import gleam/list

/// Code Authority Mode across the Triadic Mesh.
pub type CodeAuthorityMode {
  CentralMaster(node: String)
  ReadOnlyReplica(upstream: String)
  ReadOnlyBundle(bundle_name: String)
}

/// Parity State between central monorepo and execution node.
pub type ParityState {
  ParityMatch
  ParityDivergent(reason: String)
  ParityUnknown
}

/// Convert ParityState to string identifier.
pub fn parity_to_string(p: ParityState) -> String {
  case p {
    ParityMatch -> "MATCH"
    ParityDivergent(r) -> "DIVERGENT: " <> r
    ParityUnknown -> "UNKNOWN"
  }
}

/// Target node in the distributed execution fabric.
pub type DistributionTarget {
  DistributionTarget(
    id: String,
    hostname: String,
    tailscale_fqdn: String,
    authority_mode: CodeAuthorityMode,
    expected_commit_id: String,
    deployed_commit_id: String,
    kernel_sha256: String,
    parity_state: ParityState,
    execution_roles: List(String),
  )
}

/// Return the canonical 3 distribution targets stamped with the central commit ID.
pub fn canonical_distribution_targets(
  current_commit_id: String,
) -> List(DistributionTarget) {
  [
    DistributionTarget(
      id: "instance-0",
      hostname: "nas-1",
      tailscale_fqdn: "nas-1.tail55d152.ts.net:4100",
      authority_mode: CentralMaster("nas-1 (Jujutsu Standalone .jj/)"),
      expected_commit_id: current_commit_id,
      deployed_commit_id: current_commit_id,
      kernel_sha256: "CENTRAL_SOURCE_AUTHORITY",
      parity_state: ParityMatch,
      execution_roles: [
        "ROOT_SUPERVISION_OTP29",
        "PERSISTENT_STORAGE_NVME_WAL",
        "CONSTITUTIONAL_2OO3_CONSENSUS",
        "COCKPIT_WEB_API_TUI",
        "LIGHTWEIGHT_SIMD_EMBEDDINGS",
      ],
    ),
    DistributionTarget(
      id: "instance-1",
      hostname: "vm-1",
      tailscale_fqdn: "vm-1.tail55d152.ts.net:8088",
      authority_mode: ReadOnlyReplica("nas-1:4100"),
      expected_commit_id: current_commit_id,
      deployed_commit_id: current_commit_id,
      kernel_sha256: "VERIFIED_OPAM_GOSPEL_Z3",
      parity_state: ParityMatch,
      execution_roles: [
        "ZENOH_MESH_ROUTER_7447",
        "HERMES_FORMAL_Z3_SOLVER",
        "DISTRIBUTED_SWARM_WORKER",
        "ANALYTIC_LOG_COMPACTOR",
      ],
    ),
    DistributionTarget(
      id: "instance-2",
      hostname: "razr15-1",
      tailscale_fqdn: "razr15-1.tail55d152.ts.net:8088",
      authority_mode: ReadOnlyBundle("razr15-gpu-bundle.tar.gz"),
      expected_commit_id: current_commit_id,
      deployed_commit_id: current_commit_id,
      kernel_sha256: "VERIFIED_MOJO_GPU_WARP32",
      parity_state: ParityMatch,
      execution_roles: [
        "DEEP_GEMMA4_GPU_INFERENCE",
        "ATTENTION_MATRIX_GQA_SLIDING",
        "SWIGLU_GPU_BATCH_SCORING",
        "VISION_CYBER_ANALYTICS",
      ],
    ),
  ]
}

/// Verify that an individual distribution target matches the central commit.
pub fn verify_target_parity(target: DistributionTarget) -> #(Bool, String) {
  case target.expected_commit_id == target.deployed_commit_id {
    True -> #(
      True,
      "Target "
        <> target.hostname
        <> " is bit-parity synchronized with central commit: "
        <> target.expected_commit_id,
    )
    False -> #(
      False,
      "Target "
        <> target.hostname
        <> " has DIVERGED! Expected: "
        <> target.expected_commit_id
        <> ", Deployed: "
        <> target.deployed_commit_id,
    )
  }
}

/// Evaluate cluster-wide parity across all distribution targets.
pub fn evaluate_cluster_parity(
  targets: List(DistributionTarget),
) -> #(Bool, List(String)) {
  let results = list.map(targets, verify_target_parity)
  let all_ok = list.all(results, fn(r) { r.0 })
  let reports = list.map(results, fn(r) { r.1 })
  #(all_ok, reports)
}

/// Serialize DistributionTarget to JSON.
pub fn target_to_json(t: DistributionTarget) -> json.Json {
  let mode_str = case t.authority_mode {
    CentralMaster(n) -> "CENTRAL_MASTER: " <> n
    ReadOnlyReplica(up) -> "READ_ONLY_REPLICA: " <> up
    ReadOnlyBundle(b) -> "READ_ONLY_BUNDLE: " <> b
  }

  json.object([
    #("id", json.string(t.id)),
    #("hostname", json.string(t.hostname)),
    #("tailscale_fqdn", json.string(t.tailscale_fqdn)),
    #("authority_mode", json.string(mode_str)),
    #("expected_commit_id", json.string(t.expected_commit_id)),
    #("deployed_commit_id", json.string(t.deployed_commit_id)),
    #("kernel_sha256", json.string(t.kernel_sha256)),
    #("parity_state", json.string(parity_to_string(t.parity_state))),
    #("execution_roles", json.array(t.execution_roles, json.string)),
  ])
}
