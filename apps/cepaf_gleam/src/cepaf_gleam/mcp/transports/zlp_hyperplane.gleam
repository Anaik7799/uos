//// UOS-ZLP-v3 Typed Gleam Facade (`SC-HARNESS-MCP-001` Supervised OTP 29 Port Hyperplane)
//// Bridges Gleam/OTP supervision and MCP/Zenoh transports to OS-isolated
//// Lean 4.33.0 (20 zero-sorry theorems + 8 exported C-ABI kernels) + Zig 0.16.0
//// Zen 5 AVX-512 Two-Lane (`epoll` + `eventfd`) port shards.
////
//// Authority invariant (`SC-HARNESS-MCP-001`, Theorem `T10`):
//// Gleam/OTP owns all policy and effect authority. ZLP port workers provide
//// bounded verification, anti-replay, risk/scale scoring, and Zenoh SSE/PUT/GET
//// transport behind Gleam's authenticated `SignedZenohEnvelope` contract.

import gleam/bit_array
import gleam/erlang/process

pub const admitted_ev_ceiling = 93

pub const system_admitted = False

pub type ZlpReceipt {
  ZlpReceipt(excl: Int, lane_or_sub: Int, value: Int)
}

pub type ZlpRefusal {
  ZlpRefusal(status_code: Int, excl: Int, value: Int, detail: String)
}

pub type ZlpShardHealth {
  ZlpShardHealth(
    os_pid: Int,
    active_subs: Int,
    in_flight_heavy: Int,
    excl: Int,
  )
}

pub type ZlpPushEvent {
  ZlpPushEvent(shard_id: Int, excl: Int, digest: Int, json_payload: String)
}

@external(erlang, "uos_zlp_router", "gleam_ensure_started")
pub fn ensure_started(shards shards: Int) -> Result(Int, String)

@external(erlang, "uos_zlp_router", "gleam_stop")
pub fn stop() -> Nil

@external(erlang, "uos_zlp_router", "gleam_is_running")
pub fn is_running() -> Bool

@external(erlang, "uos_zlp_router", "gleam_is_binary_available")
pub fn is_binary_available() -> Bool

@external(erlang, "uos_zlp_router", "gleam_verify_frame")
pub fn verify_frame_bits(
  seq_id seq_id: Int,
  check_json_depth check_json_depth: Bool,
  payload payload: BitArray,
) -> Result(ZlpReceipt, ZlpRefusal)

pub fn verify_frame(
  seq_id seq_id: Int,
  check_json_depth check_json_depth: Bool,
  payload payload: String,
) -> Result(ZlpReceipt, ZlpRefusal) {
  verify_frame_bits(seq_id, check_json_depth, bit_array.from_string(payload))
}

@external(erlang, "uos_zlp_router", "gleam_verify_frame_on_shard")
pub fn verify_frame_on_shard(
  shard_id shard_id: Int,
  seq_id seq_id: Int,
  check_json_depth check_json_depth: Bool,
  payload payload: BitArray,
) -> Result(ZlpReceipt, ZlpRefusal)

@external(erlang, "uos_zlp_router", "gleam_eval_scale_and_risk")
pub fn eval_scale_and_risk(
  active_writers active_writers: Int,
  active_reviewers active_reviewers: Int,
  is_writer_req is_writer_req: Bool,
  daily_spent_micro_usd daily_spent_micro_usd: Int,
  now_us now_us: Int,
  lease_expires_us lease_expires_us: Int,
  safety_ready safety_ready: Bool,
  dep_ready dep_ready: Bool,
  criticality criticality: Int,
  stpa stpa: Int,
  fmea fmea: Int,
  dependency dependency: Int,
  impact impact: Int,
) -> Result(ZlpReceipt, ZlpRefusal)

@external(erlang, "uos_zlp_router", "gleam_heavy_graph_digest")
pub fn heavy_graph_digest(
  shard_id shard_id: Int,
  rounds rounds: Int,
  payload payload: BitArray,
) -> Result(ZlpReceipt, ZlpRefusal)

@external(erlang, "uos_zlp_router", "gleam_zenoh_subscribe")
pub fn zenoh_subscribe(
  topic topic: String,
  subscriber subscriber: process.Pid,
) -> Result(#(Int, ZlpReceipt), ZlpRefusal)

@external(erlang, "uos_zlp_router", "gleam_zenoh_publish")
pub fn zenoh_publish(
  topic topic: String,
  json_payload json_payload: String,
) -> Result(ZlpReceipt, ZlpRefusal)

@external(erlang, "uos_zlp_router", "gleam_zenoh_get")
pub fn zenoh_get(topic topic: String) -> Result(#(ZlpReceipt, String), ZlpRefusal)

@external(erlang, "uos_zlp_router", "gleam_shard_health")
pub fn shard_health(shard_id shard_id: Int) -> Result(ZlpShardHealth, ZlpRefusal)

@external(erlang, "uos_zlp_router", "gleam_reset_shard")
pub fn reset_shard(shard_id shard_id: Int) -> Result(ZlpReceipt, ZlpRefusal)

@external(erlang, "uos_zlp_router", "gleam_flush_zenoh_pushes")
pub fn flush_zenoh_pushes() -> Nil

@external(erlang, "uos_zlp_router", "gleam_await_zenoh_push")
pub fn await_zenoh_push(timeout_ms timeout_ms: Int) -> Result(ZlpPushEvent, Nil)

@external(erlang, "uos_zlp_router", "gleam_kill9_os_pid")
pub fn kill9_os_pid(os_pid os_pid: Int) -> Nil
