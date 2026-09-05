//// Zenoh Federation — FederationNode API tests (F26b)
//// विश्वव्यापी — World-pervading
////
//// 20 tests covering node_init, add_node, remove_node, update_node_health,
//// check_quorum, healthy_nodes, detect_partition, elect_leader, node_summary,
//// node_to_json, and FederationEvent construction.
////
//// STAMP: SC-FED-001, SC-FED-006, SC-HA-001, SC-SIL4-011,
////        SC-ZENOH-001, SC-ZMOF-001, SC-MUDA-001
//// Layer: L7_FEDERATION

import cepaf_gleam/ha/zenoh_federation.{
  Backup, FederationNode, NodeJoined, NodeLeft, Observer, PartitionDetected,
  PartitionHealed, Primary, QuorumLost, QuorumRestored, Standby, add_node,
  check_quorum, detect_partition, elect_leader, healthy_nodes, node_init,
  node_summary, node_to_json, remove_node, update_node_health,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// 1. node_init — empty bootstrap
// ---------------------------------------------------------------------------

pub fn node_init_local_node_test() {
  let s = node_init("eu-node-1", "europe-north1")
  s.local_node |> should.equal("eu-node-1")
}

pub fn node_init_local_region_test() {
  let s = node_init("eu-node-1", "europe-north1")
  s.local_region |> should.equal("europe-north1")
}

pub fn node_init_empty_nodes_test() {
  let s = node_init("eu-node-1", "europe-north1")
  s.nodes |> list.length() |> should.equal(0)
}

pub fn node_init_quorum_size_one_test() {
  // floor(0/2) + 1 = 1
  let s = node_init("eu-node-1", "europe-north1")
  s.quorum_size |> should.equal(1)
}

pub fn node_init_no_partition_test() {
  let s = node_init("eu-node-1", "europe-north1")
  s.partition_detected |> should.be_false()
}

// ---------------------------------------------------------------------------
// 2. add_node / remove_node
// ---------------------------------------------------------------------------

pub fn add_node_increases_count_test() {
  let node =
    FederationNode(
      node_id: "us-node-1",
      region: "us-east1",
      endpoint: "tcp/10.0.1.5:7447",
      role: Backup,
      health: 0.9,
      last_seen_ms: 1_000_000,
      version_vector: [],
    )
  let s = node_init("eu-node-1", "europe-north1") |> add_node(node)
  s.nodes |> list.length() |> should.equal(1)
}

pub fn add_node_updates_quorum_size_test() {
  // With 1 node: quorum = floor(1/2)+1 = 1
  let node =
    FederationNode(
      node_id: "us-node-1",
      region: "us-east1",
      endpoint: "tcp/10.0.1.5:7447",
      role: Primary,
      health: 1.0,
      last_seen_ms: 1_000_000,
      version_vector: [],
    )
  let s = node_init("eu-node-1", "europe-north1") |> add_node(node)
  s.quorum_size |> should.equal(1)
}

pub fn add_two_nodes_quorum_size_two_test() {
  // With 2 nodes: quorum = floor(2/2)+1 = 2
  let node_a =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Primary,
      health: 1.0,
      last_seen_ms: 1_000_000,
      version_vector: [],
    )
  let node_b =
    FederationNode(
      node_id: "us-node-1",
      region: "us-east1",
      endpoint: "tcp/10.0.1.1:7447",
      role: Backup,
      health: 1.0,
      last_seen_ms: 1_000_000,
      version_vector: [],
    )
  let s =
    node_init("eu-node-1", "europe-north1")
    |> add_node(node_a)
    |> add_node(node_b)
  s.quorum_size |> should.equal(2)
}

pub fn remove_node_decreases_count_test() {
  let node =
    FederationNode(
      node_id: "us-node-1",
      region: "us-east1",
      endpoint: "tcp/10.0.1.5:7447",
      role: Backup,
      health: 0.9,
      last_seen_ms: 1_000_000,
      version_vector: [],
    )
  let s =
    node_init("eu-node-1", "europe-north1")
    |> add_node(node)
    |> remove_node("us-node-1")
  s.nodes |> list.length() |> should.equal(0)
}

pub fn remove_nonexistent_node_is_idempotent_test() {
  let s = node_init("eu-node-1", "europe-north1") |> remove_node("ghost-node")
  s.nodes |> list.length() |> should.equal(0)
}

// ---------------------------------------------------------------------------
// 3. update_node_health
// ---------------------------------------------------------------------------

pub fn update_node_health_changes_score_test() {
  let node =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Primary,
      health: 0.0,
      last_seen_ms: 0,
      version_vector: [],
    )
  let s =
    node_init("eu-node-1", "europe-north1")
    |> add_node(node)
    |> update_node_health("eu-node-1", 0.9)
  let updated = s.nodes |> list.first()
  case updated {
    Ok(n) -> n.health |> should.equal(0.9)
    Error(_) -> should.fail()
  }
}

pub fn update_unknown_node_health_is_noop_test() {
  let node =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Primary,
      health: 0.5,
      last_seen_ms: 0,
      version_vector: [],
    )
  let s =
    node_init("eu-node-1", "europe-north1")
    |> add_node(node)
    |> update_node_health("ghost", 1.0)
  let unchanged = s.nodes |> list.first()
  case unchanged {
    Ok(n) -> n.health |> should.equal(0.5)
    Error(_) -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// 4. check_quorum & healthy_nodes
// ---------------------------------------------------------------------------

pub fn check_quorum_no_nodes_requires_one_test() {
  // quorum_size=1, 0 healthy nodes → quorum NOT met
  let s = node_init("eu-node-1", "europe-north1")
  check_quorum(s) |> should.be_false()
}

pub fn check_quorum_met_with_single_healthy_test() {
  let node =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Primary,
      health: 1.0,
      last_seen_ms: 1_000_000,
      version_vector: [],
    )
  let s = node_init("eu-node-1", "europe-north1") |> add_node(node)
  check_quorum(s) |> should.be_true()
}

pub fn check_quorum_not_met_when_all_unhealthy_test() {
  let node =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Primary,
      health: 0.1,
      last_seen_ms: 0,
      version_vector: [],
    )
  let s = node_init("eu-node-1", "europe-north1") |> add_node(node)
  // health=0.1 ≤ 0.5, so not counted as healthy
  check_quorum(s) |> should.be_false()
}

pub fn healthy_nodes_filters_by_threshold_test() {
  let healthy =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Primary,
      health: 0.9,
      last_seen_ms: 1_000_000,
      version_vector: [],
    )
  let degraded =
    FederationNode(
      node_id: "us-node-1",
      region: "us-east1",
      endpoint: "tcp/10.0.1.1:7447",
      role: Backup,
      health: 0.3,
      last_seen_ms: 0,
      version_vector: [],
    )
  let s =
    node_init("eu-node-1", "europe-north1")
    |> add_node(healthy)
    |> add_node(degraded)
  healthy_nodes(s) |> list.length() |> should.equal(1)
}

// ---------------------------------------------------------------------------
// 5. detect_partition
// ---------------------------------------------------------------------------

pub fn detect_partition_no_nodes_returns_empty_test() {
  let s = node_init("eu-node-1", "europe-north1")
  detect_partition(s, 5000, 10_000) |> should.equal([])
}

pub fn detect_partition_all_reachable_returns_empty_test() {
  let node =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Primary,
      health: 1.0,
      last_seen_ms: 9000,
      // seen 1000ms ago, timeout=5000ms, now=10000
      version_vector: [],
    )
  let s = node_init("eu-node-1", "europe-north1") |> add_node(node)
  detect_partition(s, 5000, 10_000) |> should.equal([])
}

pub fn detect_partition_returns_event_when_split_test() {
  let reachable =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Primary,
      health: 1.0,
      last_seen_ms: 9000,
      // 9000 >= 5000 (10000-5000) → reachable
      version_vector: [],
    )
  let unreachable =
    FederationNode(
      node_id: "us-node-1",
      region: "us-east1",
      endpoint: "tcp/10.0.1.1:7447",
      role: Backup,
      health: 0.0,
      last_seen_ms: 1000,
      // 1000 < 5000 → unreachable
      version_vector: [],
    )
  let s =
    node_init("eu-node-1", "europe-north1")
    |> add_node(reachable)
    |> add_node(unreachable)
  let events = detect_partition(s, 5000, 10_000)
  list.length(events) |> should.equal(1)
  case events {
    [PartitionDetected(groups: gs)] -> list.length(gs) |> should.equal(2)
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// 6. elect_leader
// ---------------------------------------------------------------------------

pub fn elect_leader_no_quorum_returns_error_test() {
  // No nodes → quorum not met
  let s = node_init("eu-node-1", "europe-north1")
  elect_leader(s) |> should.equal(Error("no_quorum"))
}

pub fn elect_leader_single_primary_wins_test() {
  let node =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Primary,
      health: 1.0,
      last_seen_ms: 1_000_000,
      version_vector: [],
    )
  let s = node_init("eu-node-1", "europe-north1") |> add_node(node)
  elect_leader(s) |> should.equal(Ok("eu-node-1"))
}

pub fn elect_leader_prefers_primary_over_backup_test() {
  let primary =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Primary,
      health: 0.9,
      last_seen_ms: 1_000_000,
      version_vector: [],
    )
  let backup =
    FederationNode(
      node_id: "ap-node-1",
      region: "asia-southeast1",
      endpoint: "tcp/10.0.2.1:7447",
      role: Backup,
      health: 0.9,
      last_seen_ms: 1_000_000,
      version_vector: [],
    )
  // "ap-node-1" < "eu-node-1" lexicographically but ap is Backup
  let s =
    node_init("eu-node-1", "europe-north1")
    |> add_node(primary)
    |> add_node(backup)
  // Primary wins over Backup even if its ID is lexicographically larger
  elect_leader(s) |> should.equal(Ok("eu-node-1"))
}

// ---------------------------------------------------------------------------
// 7. node_summary
// ---------------------------------------------------------------------------

pub fn node_summary_contains_local_node_test() {
  let s = node_init("eu-node-1", "europe-north1")
  node_summary(s) |> string.contains("eu-node-1") |> should.be_true()
}

pub fn node_summary_contains_quorum_status_test() {
  let s = node_init("eu-node-1", "europe-north1")
  node_summary(s) |> string.contains("quorum=") |> should.be_true()
}

pub fn node_summary_is_non_empty_test() {
  let s = node_init("eu-node-1", "europe-north1")
  { string.length(node_summary(s)) > 0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// 8. node_to_json
// ---------------------------------------------------------------------------

pub fn node_to_json_contains_node_id_test() {
  let node =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Primary,
      health: 0.95,
      last_seen_ms: 1_234_567,
      version_vector: [],
    )
  node_to_json(node) |> string.contains("eu-node-1") |> should.be_true()
}

pub fn node_to_json_contains_role_test() {
  let node =
    FederationNode(
      node_id: "eu-node-1",
      region: "europe-north1",
      endpoint: "tcp/10.0.0.1:7447",
      role: Standby,
      health: 0.5,
      last_seen_ms: 0,
      version_vector: [],
    )
  node_to_json(node) |> string.contains("Standby") |> should.be_true()
}

pub fn node_to_json_is_non_empty_test() {
  let node =
    FederationNode(
      node_id: "ap-node-1",
      region: "asia-southeast1",
      endpoint: "tcp/10.0.2.1:7447",
      role: Observer,
      health: 0.7,
      last_seen_ms: 9999,
      version_vector: [#("ap-node-1", 3)],
    )
  { string.length(node_to_json(node)) > 0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// 9. FederationEvent constructors — smoke tests
// ---------------------------------------------------------------------------

pub fn federation_event_node_joined_fields_test() {
  let NodeJoined(node_id: id, region: r) =
    NodeJoined(node_id: "new-node", region: "eu-west1")
  id |> should.equal("new-node")
  r |> should.equal("eu-west1")
}

pub fn federation_event_node_left_fields_test() {
  let NodeLeft(node_id: id, reason: r) =
    NodeLeft(node_id: "old-node", reason: "timeout")
  id |> should.equal("old-node")
  r |> should.equal("timeout")
}

pub fn federation_event_partition_healed_test() {
  PartitionHealed |> should.equal(PartitionHealed)
}

pub fn federation_event_quorum_lost_fields_test() {
  let QuorumLost(available: a, required: r) =
    QuorumLost(available: 1, required: 2)
  a |> should.equal(1)
  r |> should.equal(2)
}

pub fn federation_event_quorum_restored_test() {
  QuorumRestored |> should.equal(QuorumRestored)
}
