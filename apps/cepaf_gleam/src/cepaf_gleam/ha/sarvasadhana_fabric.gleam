//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/sarvasadhana_fabric</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L1_ATOMIC</layer>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Saṁvid Sarvasādhana-Vyūha (संविद् सर्वसाधन-व्यूह) Unified Resource Fabric
////       and Deterministic Workload Placement Engine. Measures CPU, NPU, GPU,
////       RAM, Storage, and Tailnet RTT across nas-1, vm-1, and razr15-1.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>
////       SC-RESOURCE-FABRIC-001, SC-DEFENSE-CONSTITUTION-001, SC-INF-MOJO-001,
////       SC-ZERO-MUDA-001, SC-MATH-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/json
import gleam/list

/// The Triadic Nodes of UOS.
pub type TriadicInstance {
  Instance0Nas1
  Instance1Vm1
  Instance2Razr15
}

/// Convert TriadicInstance to string identifier.
pub fn instance_to_string(inst: TriadicInstance) -> String {
  case inst {
    Instance0Nas1 -> "instance-0 (nas-1)"
    Instance1Vm1 -> "instance-1 (vm-1)"
    Instance2Razr15 -> "instance-2 (razr15-1)"
  }
}

/// Operational Workload Categories across the Triadic Defense Fabric.
pub type WorkloadDomain {
  RootSupervision
  PersistentStorage
  ConstitutionalConsensus
  CockpitWebUi
  FastOodaLoop
  ZeroTrustInterceptor
  LightweightEmbedding
  FormalZ3Solver
  ZenohMeshRouter
  DistributedSwarmWorker
  LogCompactor
  DeepGemma4Inference
  AttentionMatrixGQA
  SwigluBatchScoring
  VisionCyberAnalytics
}

/// Convert WorkloadDomain to string name.
pub fn workload_to_string(w: WorkloadDomain) -> String {
  case w {
    RootSupervision -> "ROOT_SUPERVISION_OTP29"
    PersistentStorage -> "PERSISTENT_STORAGE_NVME_WAL"
    ConstitutionalConsensus -> "CONSTITUTIONAL_2OO3_CONSENSUS"
    CockpitWebUi -> "COCKPIT_WEB_API_TUI"
    FastOodaLoop -> "FAST_OODA_RING_PRAJNA"
    ZeroTrustInterceptor -> "ZEROTRUST_PAYLOAD_INTERCEPTOR"
    LightweightEmbedding -> "LIGHTWEIGHT_SIMD_EMBEDDINGS"
    FormalZ3Solver -> "HERMES_FORMAL_Z3_SOLVER"
    ZenohMeshRouter -> "ZENOH_MESH_ROUTER_7447"
    DistributedSwarmWorker -> "DISTRIBUTED_SWARM_WORKER"
    LogCompactor -> "ANALYTIC_LOG_COMPACTOR"
    DeepGemma4Inference -> "DEEP_GEMMA4_GPU_INFERENCE"
    AttentionMatrixGQA -> "ATTENTION_MATRIX_GQA_SLIDING"
    SwigluBatchScoring -> "SWIGLU_GPU_BATCH_SCORING"
    VisionCyberAnalytics -> "VISION_CYBER_ANALYTICS"
  }
}

/// Deterministic Workload Placement Specification.
pub type WorkloadPlacement {
  WorkloadPlacement(
    workload: WorkloadDomain,
    name: String,
    primary_instance: TriadicInstance,
    fallback_instance: TriadicInstance,
    hardware_affinity: String,
    rationale: String,
  )
}

/// Dynamic Resource Measurement for an individual node.
pub type ResourceState {
  ResourceState(
    instance: TriadicInstance,
    hostname: String,
    vcpus: Int,
    ram_total_mb: Int,
    ram_available_mb: Int,
    storage_total_gb: Int,
    storage_available_gb: Int,
    has_npu: Bool,
    has_gpu: Bool,
    gpu_model: String,
    gpu_vram_mb: Int,
    ping_rtt_ms: Float,
    is_online: Bool,
  )
}

/// Fabric Overall Health Status.
pub type FabricHealth {
  FabricNominal
  FabricDegraded(reason: String)
  FabricEmergency(reason: String)
}

/// Return the canonical 15 Workload Placements across the Triadic Mesh.
pub fn canonical_placements() -> List(WorkloadPlacement) {
  [
    // Instance 0 (nas-1) Primary Workloads
    WorkloadPlacement(
      workload: RootSupervision,
      name: "Root Supervision & State Plane",
      primary_instance: Instance0Nas1,
      fallback_instance: Instance1Vm1,
      hardware_affinity: "Intel/AMD Bare-Metal CPU + Erlang OTP 29",
      rationale: "Requires deterministic supervisor hierarchy and low-jitter BEAM scheduler.",
    ),
    WorkloadPlacement(
      workload: PersistentStorage,
      name: "Hermes SQLite WAL & Safe Storage",
      primary_instance: Instance0Nas1,
      fallback_instance: Instance1Vm1,
      hardware_affinity: "NVMe Drive Lock: 25503L801736",
      rationale: "Protected by hardware serial interlock to prevent accidental wiping.",
    ),
    WorkloadPlacement(
      workload: ConstitutionalConsensus,
      name: "2oo3 Constitutional Consensus & Andon",
      primary_instance: Instance0Nas1,
      fallback_instance: Instance1Vm1,
      hardware_affinity: "Pure Gleam / BEAM OTP 29",
      rationale: "Final decision authority must run on root controller.",
    ),
    WorkloadPlacement(
      workload: CockpitWebUi,
      name: "Lustre 5.6 WebUI & Wisp REST API",
      primary_instance: Instance0Nas1,
      fallback_instance: Instance1Vm1,
      hardware_affinity: "Port 4100 on Tailnet FQDN",
      rationale: "Primary operator dashboard served server-side with zero client JS.",
    ),
    WorkloadPlacement(
      workload: FastOodaLoop,
      name: "Fast OODA Ring & Prajna Breakers",
      primary_instance: Instance0Nas1,
      fallback_instance: Instance1Vm1,
      hardware_affinity: "Sub-1.5ms BEAM Loop",
      rationale: "Continuous health surveillance and Lyapunov trend analysis.",
    ),
    WorkloadPlacement(
      workload: ZeroTrustInterceptor,
      name: "Zero-Trust MCP Interceptor",
      primary_instance: Instance0Nas1,
      fallback_instance: Instance1Vm1,
      hardware_affinity: "Hermes Cryptokit SHA-256",
      rationale: "All external agent toolcalls intercepted before admission.",
    ),
    WorkloadPlacement(
      workload: LightweightEmbedding,
      name: "Lightweight SIMD Embeddings",
      primary_instance: Instance0Nas1,
      fallback_instance: Instance2Razr15,
      hardware_affinity: "CPU AVX2 SIMD / AMD NPU",
      rationale: "Sub-microsecond dot products executed immediately on CPU metal.",
    ),
    // Instance 1 (vm-1) Primary Workloads
    WorkloadPlacement(
      workload: ZenohMeshRouter,
      name: "Zenoh Mesh Router Node (7447/8080)",
      primary_instance: Instance1Vm1,
      fallback_instance: Instance0Nas1,
      hardware_affinity: "Virtualized Network Hub",
      rationale: "Dedicated high-bandwidth broker forwarding OTel spans across mesh.",
    ),
    WorkloadPlacement(
      workload: FormalZ3Solver,
      name: "Hermes Gospel & Bounded Z3 Solvers",
      primary_instance: Instance1Vm1,
      fallback_instance: Instance0Nas1,
      hardware_affinity: "46GB RAM Isolated Hypervisor",
      rationale: "Heavy solver memory allocations isolated from root supervisor.",
    ),
    WorkloadPlacement(
      workload: DistributedSwarmWorker,
      name: "Decentralized Swarm Work-Stealing",
      primary_instance: Instance1Vm1,
      fallback_instance: Instance0Nas1,
      hardware_affinity: "10 vCPUs Parallel Compute",
      rationale: "Pulls background tasks from leveled Heijunka pull queue.",
    ),
    WorkloadPlacement(
      workload: LogCompactor,
      name: "Historical Ledger & OTel Compactor",
      primary_instance: Instance1Vm1,
      fallback_instance: Instance0Nas1,
      hardware_affinity: "1.2TB Storage Volume",
      rationale: "Asynchronous log rotation without consuming root NVMe bandwidth.",
    ),
    // Instance 2 (razr15-1 WSL2 GPU) Primary Workloads
    WorkloadPlacement(
      workload: DeepGemma4Inference,
      name: "Bare-Metal Gemma 4 GPU Inference",
      primary_instance: Instance2Razr15,
      fallback_instance: Instance0Nas1,
      hardware_affinity: "NVIDIA GeForce RTX GPU (CUDA /dev/dxg)",
      rationale: "Hardware warp 32 parallelism and dedicated GDDR6 VRAM.",
    ),
    WorkloadPlacement(
      workload: AttentionMatrixGQA,
      name: "Grouped Query Attention (16:8 GQA)",
      primary_instance: Instance2Razr15,
      fallback_instance: Instance0Nas1,
      hardware_affinity: "GPU Warp Parallelism & Tensor Cores",
      rationale: "4096-token sliding-window attention accelerated on metal.",
    ),
    WorkloadPlacement(
      workload: SwigluBatchScoring,
      name: "SwiGLU FFN Batch Feed-Forward",
      primary_instance: Instance2Razr15,
      fallback_instance: Instance0Nas1,
      hardware_affinity: "Fused GPU Math & High Bandwidth",
      rationale: "Matrix multiplications exceed CPU throughput by an order of magnitude.",
    ),
    WorkloadPlacement(
      workload: VisionCyberAnalytics,
      name: "Tactical Vision & Threat Embedding",
      primary_instance: Instance2Razr15,
      fallback_instance: Instance0Nas1,
      hardware_affinity: "8GB Dedicated VRAM",
      rationale: "Heavy multi-modal tensor analysis for real-time cyber defense.",
    ),
  ]
}

/// Dispatch a workload to the optimal available node with fail-closed degradation.
pub fn dispatch_workload(
  workload: WorkloadDomain,
  active_instances: List(TriadicInstance),
) -> #(TriadicInstance, String) {
  let placements = canonical_placements()
  let maybe_placement =
    list.find(placements, fn(p) { p.workload == workload })

  case maybe_placement {
    Error(_) -> #(
      Instance0Nas1,
      "Unknown workload, defaulted to Instance 0 (Root Supervisor)",
    )
    Ok(p) -> {
      let is_primary_online =
        list.contains(active_instances, p.primary_instance)
      case is_primary_online {
        True -> #(
          p.primary_instance,
          "Dispatched to primary target: "
            <> instance_to_string(p.primary_instance)
            <> " ["
            <> p.hardware_affinity
            <> "]",
        )
        False -> {
          let is_fallback_online =
            list.contains(active_instances, p.fallback_instance)
          case is_fallback_online {
            True -> #(
              p.fallback_instance,
              "Primary target offline ("
                <> instance_to_string(p.primary_instance)
                <> ") -> Fallback to: "
                <> instance_to_string(p.fallback_instance)
                <> " [DEGRADED_MODE]",
            )
            False -> #(
              Instance0Nas1,
              "Both primary and fallback offline -> Emergency containment on Instance 0 [EMERGENCY_CONTAINMENT]",
            )
          }
        }
      }
    }
  }
}

/// Calculate the fabric health based on active instances and latencies.
pub fn evaluate_fabric_health(states: List(ResourceState)) -> FabricHealth {
  let has_nas =
    list.any(states, fn(s) { s.instance == Instance0Nas1 && s.is_online })
  let has_vm =
    list.any(states, fn(s) { s.instance == Instance1Vm1 && s.is_online })
  let has_gpu =
    list.any(states, fn(s) { s.instance == Instance2Razr15 && s.is_online })

  case has_nas, has_vm, has_gpu {
    False, _, _ ->
      FabricEmergency(
        "Instance 0 (nas-1 Root Supervisor) is offline! Fail-closed halt.",
      )
    True, True, True -> FabricNominal
    True, False, True ->
      FabricDegraded(
        "Instance 1 (vm-1) offline. Formal Z3 and Zenoh routing fail-over to nas-1.",
      )
    True, True, False ->
      FabricDegraded(
        "Instance 2 (razr15-1 GPU) offline. Gemma 4 deep AI fail-over to nas-1 CPU SIMD.",
      )
    True, False, False ->
      FabricDegraded(
        "Both peer nodes offline. Autonomous isolated operation active on nas-1 bare-metal.",
      )
  }
}

/// Serialize WorkloadPlacement to JSON.
pub fn placement_to_json(p: WorkloadPlacement) -> json.Json {
  json.object([
    #("workload", json.string(workload_to_string(p.workload))),
    #("name", json.string(p.name)),
    #("primary_instance", json.string(instance_to_string(p.primary_instance))),
    #(
      "fallback_instance",
      json.string(instance_to_string(p.fallback_instance)),
    ),
    #("hardware_affinity", json.string(p.hardware_affinity)),
    #("rationale", json.string(p.rationale)),
  ])
}

/// Serialize ResourceState to JSON.
pub fn resource_state_to_json(s: ResourceState) -> json.Json {
  json.object([
    #("instance", json.string(instance_to_string(s.instance))),
    #("hostname", json.string(s.hostname)),
    #("vcpus", json.int(s.vcpus)),
    #("ram_total_mb", json.int(s.ram_total_mb)),
    #("ram_available_mb", json.int(s.ram_available_mb)),
    #("storage_total_gb", json.int(s.storage_total_gb)),
    #("storage_available_gb", json.int(s.storage_available_gb)),
    #("has_npu", json.bool(s.has_npu)),
    #("has_gpu", json.bool(s.has_gpu)),
    #("gpu_model", json.string(s.gpu_model)),
    #("gpu_vram_mb", json.int(s.gpu_vram_mb)),
    #("ping_rtt_ms", json.float(s.ping_rtt_ms)),
    #("is_online", json.bool(s.is_online)),
  ])
}
