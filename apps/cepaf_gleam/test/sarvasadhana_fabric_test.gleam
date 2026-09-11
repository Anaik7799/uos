import cepaf_gleam/ha/sarvasadhana_fabric.{
  DeepGemma4Inference, FabricDegraded, FabricEmergency, FabricNominal,
  FormalZ3Solver, Instance0Nas1, Instance1Vm1, Instance2Razr15, ResourceState,
  RootSupervision, canonical_placements, dispatch_workload,
  evaluate_fabric_health, placement_to_json,
}
import gleam/json
import gleam/list
import gleeunit/should

pub fn canonical_placements_count_test() {
  let placements = canonical_placements()
  list.length(placements)
  |> should.equal(15)
}

pub fn dispatch_workload_primary_online_test() {
  let all_online = [Instance0Nas1, Instance1Vm1, Instance2Razr15]

  // Deep AI routes to GPU (Instance 2)
  let #(target_gpu, _reason1) =
    dispatch_workload(DeepGemma4Inference, all_online)
  target_gpu
  |> should.equal(Instance2Razr15)

  // Root supervision routes to Instance 0
  let #(target_root, _reason2) = dispatch_workload(RootSupervision, all_online)
  target_root
  |> should.equal(Instance0Nas1)

  // Formal solver routes to Instance 1
  let #(target_solver, _reason3) = dispatch_workload(FormalZ3Solver, all_online)
  target_solver
  |> should.equal(Instance1Vm1)
}

pub fn dispatch_workload_gpu_offline_fallback_test() {
  // Instance 2 offline -> Fallback to Instance 0 CPU SIMD
  let peers_no_gpu = [Instance0Nas1, Instance1Vm1]

  let #(target, reason) =
    dispatch_workload(DeepGemma4Inference, peers_no_gpu)
  target
  |> should.equal(Instance0Nas1)

  // Verify degraded fallback reason is present
  reason
  |> should.equal(
    "Primary target offline (instance-2 (razr15-1)) -> Fallback to: instance-0 (nas-1) [DEGRADED_MODE]",
  )
}

pub fn evaluate_fabric_health_test() {
  let s0 =
    ResourceState(
      instance: Instance0Nas1,
      hostname: "nas-1",
      vcpus: 24,
      ram_total_mb: 44738,
      ram_available_mb: 30000,
      storage_total_gb: 1800,
      storage_available_gb: 789,
      has_npu: True,
      has_gpu: True,
      gpu_model: "Radeon 890M",
      gpu_vram_mb: 4096,
      ping_rtt_ms: 0.0,
      is_online: True,
    )

  let s1 =
    ResourceState(
      instance: Instance1Vm1,
      hostname: "vm-1",
      vcpus: 10,
      ram_total_mb: 47145,
      ram_available_mb: 41000,
      storage_total_gb: 1228,
      storage_available_gb: 305,
      has_npu: False,
      has_gpu: False,
      gpu_model: "None",
      gpu_vram_mb: 0,
      ping_rtt_ms: 1.2,
      is_online: True,
    )

  let s2 =
    ResourceState(
      instance: Instance2Razr15,
      hostname: "razr15-1",
      vcpus: 12,
      ram_total_mb: 16384,
      ram_available_mb: 12000,
      storage_total_gb: 512,
      storage_available_gb: 256,
      has_npu: False,
      has_gpu: True,
      gpu_model: "NVIDIA GeForce RTX",
      gpu_vram_mb: 8192,
      ping_rtt_ms: 3.5,
      is_online: True,
    )

  // 1. All online -> Nominal
  evaluate_fabric_health([s0, s1, s2])
  |> should.equal(FabricNominal)

  // 2. GPU offline -> Degraded
  let s2_offline = ResourceState(..s2, is_online: False)
  case evaluate_fabric_health([s0, s1, s2_offline]) {
    FabricDegraded(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }

  // 3. Root offline -> Emergency
  let s0_offline = ResourceState(..s0, is_online: False)
  case evaluate_fabric_health([s0_offline, s1, s2]) {
    FabricEmergency(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn json_serialization_test() {
  let placements = canonical_placements()
  let first = case placements {
    [p, ..] -> p
    [] -> panic as "Empty placements"
  }

  let json_str = json.to_string(placement_to_json(first))
  should.be_true(json_str != "")
}
