import cepaf_gleam/crdt/delta_state.{
  Dot, MeshDeltaState, new_mesh_delta_state, orset_add, pncounter_increment,
}
import cepaf_gleam/crdt/health_bridge.{empty_health_map, record_health}
import cepaf_gleam/crdt/mesh_sync.{
  SyncAck, SyncDelta, SyncDigest, default_cluster_topology,
  generate_sync_digest, reconcile_remote_delta, requires_delta_sync,
  sync_message_to_json,
}
import gleeunit/should

pub fn mesh_sync_digest_and_drift_test() {
  let state1 = new_mesh_delta_state("nas-1", 1000)
  let state1 =
    MeshDeltaState(
      ..state1,
      active_workers: orset_add(
        state1.active_workers,
        "worker-alpha",
        Dot("nas-1", 1),
      ),
      task_counters: pncounter_increment(state1.task_counters, "nas-1", 5),
    )

  let digest = generate_sync_digest("nas-1", state1, 2000)
  case digest {
    SyncDigest(from_node, vector_clock, active_count, _) -> {
      from_node |> should.equal("nas-1")
      active_count |> should.equal(1)
      vector_clock |> should.equal([#("nas-1", 1)])
    }
    _ -> panic as "expected SyncDigest"
  }

  let remote_clock = [#("nas-1", 0)]
  requires_delta_sync(state1, remote_clock) |> should.equal(True)

  let dominator_clock = [#("nas-1", 2)]
  requires_delta_sync(state1, dominator_clock) |> should.equal(False)
}

pub fn mesh_sync_reconciliation_and_ack_test() {
  let state_local = new_mesh_delta_state("nas-1", 1000)
  let health_local = empty_health_map()

  let state_remote = new_mesh_delta_state("vm-1", 1500)
  let health_remote =
    record_health(empty_health_map(), "vm-1", 0.95, -1.2, True, "closed", 1500)

  let delta_msg = SyncDelta("vm-1", state_remote, health_remote, 1600)
  let #(_updated_state, _updated_health, ack) =
    reconcile_remote_delta("nas-1", state_local, health_local, delta_msg, 1700)

  case ack {
    SyncAck(from_node, applied_clock, status, _) -> {
      from_node |> should.equal("nas-1")
      status |> should.equal("reconciled_ok")
      applied_clock |> should.not_equal([])
    }
    _ -> panic as "expected SyncAck"
  }

  // Check JSON serialization
  let json_str = sync_message_to_json(ack)
  json_str |> should.not_equal("")

  let topo = default_cluster_topology(1700)
  topo |> should.not_equal([])
}
