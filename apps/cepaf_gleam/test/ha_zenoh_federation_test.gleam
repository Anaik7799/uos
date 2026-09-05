//// Zenoh Multi-Region Federation Tests — F26
//// विश्वव्यापी — World-pervading
////
//// 24 tests covering init, add/remove region, health updates, mode transitions,
//// quorum evaluation, leader election, topic generation, JSON serialisation,
//// and the human-readable summary.
////
//// STAMP: SC-FED-001, SC-FED-006, SC-HA-001, SC-SIL4-011,
////        SC-ZENOH-001, SC-ZMOF-001, SC-MUDA-001
//// Layer: L7_FEDERATION

import cepaf_gleam/ha/zenoh_federation.{
  FullFederation, IslandMode, PartialFederation, Recovering, Region,
  RegionHealth, add_region, determine_mode, init, is_quorum_met, local_is_leader,
  remove_region, summary, to_json, update_health, zenoh_topics_for_region,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// 1. init — default 3-region topology
// ---------------------------------------------------------------------------

pub fn init_creates_three_regions_test() {
  let state = init("europe-north1")
  list.length(state.regions) |> should.equal(3)
}

pub fn init_sets_local_region_test() {
  let state = init("europe-north1")
  state.local_region |> should.equal("europe-north1")
}

pub fn init_total_nodes_is_sum_test() {
  // EU=3 + US=3 + APAC=2 = 8
  let state = init("europe-north1")
  state.total_nodes |> should.equal(8)
}

pub fn init_starts_with_zero_healthy_regions_test() {
  let state = init("europe-north1")
  state.healthy_regions |> should.equal(0)
}

pub fn init_starts_in_island_mode_test() {
  let state = init("europe-north1")
  state.federation_mode |> should.equal(IslandMode)
}

pub fn init_consensus_protocol_set_test() {
  let state = init("europe-north1")
  state.consensus_protocol |> should.equal("2oo3-quorum")
}

pub fn init_eu_region_present_test() {
  let state = init("europe-north1")
  state.regions
  |> list.any(fn(r) { r.id == "europe-north1" })
  |> should.be_true()
}

pub fn init_us_region_present_test() {
  let state = init("europe-north1")
  state.regions
  |> list.any(fn(r) { r.id == "us-east1" })
  |> should.be_true()
}

pub fn init_apac_region_present_test() {
  let state = init("europe-north1")
  state.regions
  |> list.any(fn(r) { r.id == "asia-southeast1" })
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// 2. add_region / remove_region
// ---------------------------------------------------------------------------

pub fn add_region_increases_count_test() {
  let extra =
    Region(
      id: "eu-west1",
      name: "Dublin",
      zenoh_endpoint: "tcp/zenoh-ie.example.com:7447",
      healthy: False,
      node_count: 2,
      leader_node: "ie-node-1",
      last_heartbeat: 0,
    )
  let state = init("europe-north1") |> add_region(extra)
  list.length(state.regions) |> should.equal(4)
}

pub fn add_region_updates_total_nodes_test() {
  let extra =
    Region(
      id: "eu-west1",
      name: "Dublin",
      zenoh_endpoint: "tcp/zenoh-ie.example.com:7447",
      healthy: False,
      node_count: 2,
      leader_node: "ie-node-1",
      last_heartbeat: 0,
    )
  let state = init("europe-north1") |> add_region(extra)
  // 8 base + 2 new = 10
  state.total_nodes |> should.equal(10)
}

pub fn remove_region_decreases_count_test() {
  let state = init("europe-north1") |> remove_region("us-east1")
  list.length(state.regions) |> should.equal(2)
}

pub fn remove_region_updates_total_nodes_test() {
  // Remove us-east1 (3 nodes) from 8 → 5
  let state = init("europe-north1") |> remove_region("us-east1")
  state.total_nodes |> should.equal(5)
}

pub fn remove_nonexistent_region_is_idempotent_test() {
  let state = init("europe-north1") |> remove_region("nonexistent-region")
  list.length(state.regions) |> should.equal(3)
}

// ---------------------------------------------------------------------------
// 3. update_health and determine_mode transitions
// ---------------------------------------------------------------------------

pub fn update_health_true_increments_healthy_test() {
  let state = init("europe-north1") |> update_health("europe-north1", True)
  state.healthy_regions |> should.equal(1)
}

pub fn all_healthy_gives_full_federation_test() {
  let state =
    init("europe-north1")
    |> update_health("europe-north1", True)
    |> update_health("us-east1", True)
    |> update_health("asia-southeast1", True)
  state.federation_mode |> should.equal(FullFederation)
}

pub fn majority_healthy_gives_partial_federation_test() {
  // 2 out of 3 = majority, but not all
  let state =
    init("europe-north1")
    |> update_health("europe-north1", True)
    |> update_health("us-east1", True)
  state.federation_mode |> should.equal(PartialFederation)
}

pub fn none_healthy_gives_island_mode_test() {
  let state = init("europe-north1")
  state.federation_mode |> should.equal(IslandMode)
}

pub fn minority_healthy_gives_recovering_test() {
  // Only 1 out of 3 healthy and 1 < floor(3/2)+1=2
  let state = init("europe-north1") |> update_health("us-east1", True)
  state.federation_mode |> should.equal(Recovering)
}

pub fn determine_mode_matches_state_mode_test() {
  let state =
    init("europe-north1")
    |> update_health("europe-north1", True)
    |> update_health("us-east1", True)
    |> update_health("asia-southeast1", True)
  determine_mode(state) |> should.equal(state.federation_mode)
}

// ---------------------------------------------------------------------------
// 4. Quorum
// ---------------------------------------------------------------------------

pub fn quorum_met_when_majority_healthy_test() {
  let state =
    init("europe-north1")
    |> update_health("europe-north1", True)
    |> update_health("us-east1", True)
  is_quorum_met(state) |> should.be_true()
}

pub fn quorum_not_met_with_zero_healthy_test() {
  is_quorum_met(init("europe-north1")) |> should.be_false()
}

pub fn quorum_met_all_healthy_test() {
  let state =
    init("europe-north1")
    |> update_health("europe-north1", True)
    |> update_health("us-east1", True)
    |> update_health("asia-southeast1", True)
  is_quorum_met(state) |> should.be_true()
}

pub fn quorum_not_met_with_minority_test() {
  // 1 out of 3 is not a majority
  let state = init("europe-north1") |> update_health("us-east1", True)
  is_quorum_met(state) |> should.be_false()
}

// ---------------------------------------------------------------------------
// 5. Leader election
// ---------------------------------------------------------------------------

pub fn local_is_leader_when_lex_first_healthy_test() {
  // "asia-southeast1" < "europe-north1" < "us-east1" lexicographically
  // So if all healthy, asia-southeast1 is leader — europe-north1 is NOT
  let state =
    init("europe-north1")
    |> update_health("europe-north1", True)
    |> update_health("us-east1", True)
    |> update_health("asia-southeast1", True)
  local_is_leader(state) |> should.be_false()
}

pub fn local_is_leader_sole_healthy_region_test() {
  // Only local region is healthy — it must be leader
  let state = init("europe-north1") |> update_health("europe-north1", True)
  local_is_leader(state) |> should.be_true()
}

pub fn local_not_leader_when_no_healthy_regions_test() {
  local_is_leader(init("europe-north1")) |> should.be_false()
}

// ---------------------------------------------------------------------------
// 6. Zenoh topics
// ---------------------------------------------------------------------------

pub fn zenoh_topics_returns_three_topics_test() {
  zenoh_topics_for_region("europe-north1") |> list.length() |> should.equal(3)
}

pub fn zenoh_topics_contain_health_test() {
  let topics = zenoh_topics_for_region("us-east1")
  topics
  |> list.any(fn(t) { string.contains(t, "/health/") })
  |> should.be_true()
}

pub fn zenoh_topics_contain_guard_test() {
  let topics = zenoh_topics_for_region("us-east1")
  topics
  |> list.any(fn(t) { string.contains(t, "/guard/") })
  |> should.be_true()
}

pub fn zenoh_topics_contain_ooda_test() {
  let topics = zenoh_topics_for_region("us-east1")
  topics
  |> list.any(fn(t) { string.contains(t, "/ooda/") })
  |> should.be_true()
}

pub fn zenoh_topics_prefix_indrajaal_test() {
  zenoh_topics_for_region("asia-southeast1")
  |> list.all(fn(t) { string.starts_with(t, "indrajaal/") })
  |> should.be_true()
}

pub fn zenoh_topics_embed_region_id_test() {
  let region = "europe-north1"
  zenoh_topics_for_region(region)
  |> list.all(fn(t) { string.contains(t, region) })
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// 7. JSON serialisation
// ---------------------------------------------------------------------------

pub fn to_json_contains_local_region_test() {
  let json = init("europe-north1") |> to_json()
  string.contains(json, "europe-north1") |> should.be_true()
}

pub fn to_json_contains_federation_mode_test() {
  let json = init("europe-north1") |> to_json()
  string.contains(json, "IslandMode") |> should.be_true()
}

pub fn to_json_contains_regions_array_test() {
  let json = init("europe-north1") |> to_json()
  string.contains(json, "\"regions\":[") |> should.be_true()
}

pub fn to_json_is_non_empty_test() {
  let json = init("europe-north1") |> to_json()
  { string.length(json) > 0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// 8. Summary
// ---------------------------------------------------------------------------

pub fn summary_contains_mode_test() {
  let s = init("europe-north1") |> summary()
  string.contains(s, "IslandMode") |> should.be_true()
}

pub fn summary_contains_local_region_test() {
  let s = init("europe-north1") |> summary()
  string.contains(s, "europe-north1") |> should.be_true()
}

pub fn summary_contains_quorum_status_test() {
  let s = init("europe-north1") |> summary()
  string.contains(s, "quorum=") |> should.be_true()
}

pub fn summary_contains_leader_status_test() {
  let s = init("europe-north1") |> summary()
  string.contains(s, "leader=") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 9. RegionHealth type smoke test
// ---------------------------------------------------------------------------

pub fn region_health_fields_accessible_test() {
  let rh =
    RegionHealth(
      region_id: "europe-north1",
      latency_ms: 42,
      reachable: True,
      data_consistent: True,
      version_match: True,
    )
  rh.region_id |> should.equal("europe-north1")
  rh.latency_ms |> should.equal(42)
  rh.reachable |> should.be_true()
}
