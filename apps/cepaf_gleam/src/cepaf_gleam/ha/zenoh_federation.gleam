//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/zenoh_federation</module>
////     <fsharp-lineage>None — novel multi-region federation layer (F26)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L7_FEDERATION</layer>
////     <mesh-domain>
////       Multi-region Zenoh mesh federation for the SIL-6 Biomorphic system.
////       Defines region topology, health tracking, mode determination, quorum
////       evaluation, and Zenoh topic namespace generation for cross-region
////       communication.  Pure types and functions — no I/O, no side-effects.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>
////       SC-FED-001, SC-FED-006, SC-HA-001, SC-SIL4-011,
////       SC-ZENOH-001, SC-ZMOF-001, SC-MUDA-001, SC-FUNC-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Rust ha_election.rs Primary/Backup/Standby states ↪ Gleam FederationMode ADT.
////       HA election maps to multi-region quorum; region set extends node set.
////     </morphism>
////     <morphism type="surjective" loss="network-topology">
////       Zenoh router endpoint reachability ↠ Bool healthy flag.
////       Mitigation: Latency and consistency fields carry additional signal beyond
////       the binary reachable flag.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// ZENOH MULTI-REGION FEDERATION — F26
//// विश्वव्यापी — World-pervading (Sanskrit)
////
//// Default 3-region topology (GDPR-aware):
////   europe-north1   Stockholm  — primary,  GDPR-compliant EU data residence
////   us-east1        Virginia   — backup,   AWS us-east-1 redundancy
////   asia-southeast1 Singapore  — expansion, APAC coverage
////
//// Quorum rule  : majority of regions must be healthy  (floor(N/2) + 1)
//// Mode ladder  : FullFederation → PartialFederation → IslandMode → Recovering
//// Zenoh topics : indrajaal/{region}/health/**
////                indrajaal/{region}/guard/**
////                indrajaal/{region}/ooda/**
////
//// STAMP: SC-FED-001, SC-FED-006, SC-HA-001, SC-SIL4-011, SC-ZENOH-001,
////        SC-ZMOF-001, SC-MUDA-001, SC-FUNC-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ===========================================================================
// FederationNode API — multi-region node-level mesh types (F26b)
// Extends the region-level API above with per-node types used by the
// federated OODA loop and leader-election subsystem.
// STAMP: SC-FED-001, SC-HA-001, SC-SIL4-011, SC-ZMOF-001
// ===========================================================================

/// Role of a node in the federated Zenoh mesh (mirrors Rust ha_election.rs).
pub type NodeRole {
  Primary
  Backup
  Standby
  Observer
}

/// A single node in the federated Zenoh mesh.
pub type FederationNode {
  FederationNode(
    /// Unique node identifier (e.g. "eu-node-1").
    node_id: String,
    /// GCP/AWS region code this node belongs to (e.g. "europe-north1").
    region: String,
    /// Zenoh TCP endpoint for this node (e.g. "tcp/10.0.1.5:7447").
    endpoint: String,
    /// Current role in the mesh.
    role: NodeRole,
    /// Normalised health score in [0.0, 1.0].
    health: Float,
    /// Unix epoch milliseconds of last observed heartbeat.
    last_seen_ms: Int,
    /// Lamport vector clock: list of #(node_id, counter) pairs.
    version_vector: List(#(String, Int)),
  )
}

/// Aggregate node-level federation state.
pub type NodeFederationState {
  NodeFederationState(
    /// This node's own identifier.
    local_node: String,
    /// Region this node belongs to.
    local_region: String,
    /// All known mesh nodes.
    nodes: List(FederationNode),
    /// Quorum threshold: floor(|nodes|/2) + 1.
    quorum_size: Int,
    /// True when a network partition has been detected.
    partition_detected: Bool,
  )
}

/// Events emitted by the federation state machine.
pub type FederationEvent {
  NodeJoined(node_id: String, region: String)
  NodeLeft(node_id: String, reason: String)
  PartitionDetected(groups: List(List(String)))
  PartitionHealed
  LeaderElected(node_id: String)
  QuorumLost(available: Int, required: Int)
  QuorumRestored
}

// ---------------------------------------------------------------------------
// NodeFederationState construction
// ---------------------------------------------------------------------------

/// Construct an empty federation state for the given local node + region.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Bootstrap ↪ pure NodeFederationState value</morphism>
///   <formal-proof>
///     <P> local_id and region are non-empty Strings </P>
///     <C> node_init(local_id, region) </C>
///     <Q> NodeFederationState with empty nodes list; quorum_size = 1;
///         partition_detected = False. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn node_init(local_id: String, region: String) -> NodeFederationState {
  NodeFederationState(
    local_node: local_id,
    local_region: region,
    nodes: [],
    quorum_size: 1,
    partition_detected: False,
  )
}

// ---------------------------------------------------------------------------
// Node management
// ---------------------------------------------------------------------------

/// Add a node to the state, recomputing the quorum size.
pub fn add_node(
  state: NodeFederationState,
  node: FederationNode,
) -> NodeFederationState {
  let nodes = list.append(state.nodes, [node])
  let qs = list.length(nodes) / 2 + 1
  NodeFederationState(..state, nodes: nodes, quorum_size: qs)
}

/// Remove a node by ID, recomputing the quorum size.
pub fn remove_node(
  state: NodeFederationState,
  node_id: String,
) -> NodeFederationState {
  let nodes = list.filter(state.nodes, fn(n) { n.node_id != node_id })
  let qs = list.length(nodes) / 2 + 1
  NodeFederationState(..state, nodes: nodes, quorum_size: qs)
}

/// Update the health score for a node identified by `node_id`.
pub fn update_node_health(
  state: NodeFederationState,
  node_id: String,
  health: Float,
) -> NodeFederationState {
  let nodes =
    list.map(state.nodes, fn(n) {
      case n.node_id == node_id {
        True -> FederationNode(..n, health: health)
        False -> n
      }
    })
  NodeFederationState(..state, nodes: nodes)
}

// ---------------------------------------------------------------------------
// Quorum
// ---------------------------------------------------------------------------

/// Returns True when the count of healthy nodes (health > 0.5) meets quorum.
/// Quorum rule: healthy >= floor(|nodes|/2) + 1  (SC-SIL4-011).
pub fn check_quorum(state: NodeFederationState) -> Bool {
  let healthy_count =
    list.filter(state.nodes, fn(n) { n.health >. 0.5 }) |> list.length()
  healthy_count >= state.quorum_size
}

// ---------------------------------------------------------------------------
// Healthy-node filter
// ---------------------------------------------------------------------------

/// Return only the nodes whose health score exceeds 0.5.
pub fn healthy_nodes(state: NodeFederationState) -> List(FederationNode) {
  list.filter(state.nodes, fn(n) { n.health >. 0.5 })
}

// ---------------------------------------------------------------------------
// Partition detection
// ---------------------------------------------------------------------------

/// Classify nodes as reachable/unreachable based on `last_seen_ms` vs
/// `now_ms - timeout_ms`.  Returns a `PartitionDetected` event when two
/// non-empty groups are found, or an empty list otherwise.
pub fn detect_partition(
  state: NodeFederationState,
  timeout_ms: Int,
  now_ms: Int,
) -> List(FederationEvent) {
  let cutoff = now_ms - timeout_ms
  let reachable =
    state.nodes
    |> list.filter(fn(n) { n.last_seen_ms >= cutoff })
    |> list.map(fn(n) { n.node_id })
  let unreachable =
    state.nodes
    |> list.filter(fn(n) { n.last_seen_ms < cutoff })
    |> list.map(fn(n) { n.node_id })
  case reachable, unreachable {
    [], _ -> []
    _, [] -> []
    r, u -> [PartitionDetected(groups: [r, u])]
  }
}

// ---------------------------------------------------------------------------
// Leader election
// ---------------------------------------------------------------------------

/// Elect the leader from healthy nodes: lexicographically smallest node_id
/// among nodes with `role == Primary` OR (if none) among all healthy nodes.
/// Returns `Error("no_quorum")` when fewer than `quorum_size` nodes are healthy.
pub fn elect_leader(state: NodeFederationState) -> Result(String, String) {
  case check_quorum(state) {
    False -> Error("no_quorum")
    True -> {
      let h = healthy_nodes(state)
      // Prefer Primary-role nodes first.
      let primaries =
        list.filter(h, fn(n) { n.role == Primary })
        |> list.map(fn(n) { n.node_id })
      let candidates = case primaries {
        [] -> list.map(h, fn(n) { n.node_id })
        ps -> ps
      }
      case list.sort(candidates, string.compare) {
        [first, ..] -> Ok(first)
        [] -> Error("no_candidates")
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

/// One-line summary of the node-level federation state for logs and TUI.
pub fn node_summary(state: NodeFederationState) -> String {
  let hc = list.filter(state.nodes, fn(n) { n.health >. 0.5 }) |> list.length()
  "NodeFederation local="
  <> state.local_node
  <> "@"
  <> state.local_region
  <> " nodes="
  <> int.to_string(list.length(state.nodes))
  <> " healthy="
  <> int.to_string(hc)
  <> " quorum_size="
  <> int.to_string(state.quorum_size)
  <> " partition="
  <> case state.partition_detected {
    True -> "yes"
    False -> "no"
  }
  <> " quorum="
  <> case check_quorum(state) {
    True -> "met"
    False -> "lost"
  }
}

// ---------------------------------------------------------------------------
// NodeRole helpers & JSON serialisation
// ---------------------------------------------------------------------------

fn node_role_to_string(role: NodeRole) -> String {
  case role {
    Primary -> "Primary"
    Backup -> "Backup"
    Standby -> "Standby"
    Observer -> "Observer"
  }
}

/// Serialise a FederationNode to compact JSON.
pub fn node_to_json(n: FederationNode) -> String {
  "{"
  <> "\"node_id\":\""
  <> n.node_id
  <> "\","
  <> "\"region\":\""
  <> n.region
  <> "\","
  <> "\"endpoint\":\""
  <> n.endpoint
  <> "\","
  <> "\"role\":\""
  <> node_role_to_string(n.role)
  <> "\","
  <> "\"health\":"
  <> float.to_string(n.health)
  <> ","
  <> "\"last_seen_ms\":"
  <> int.to_string(n.last_seen_ms)
  <> "}"
}

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A single region in the multi-region federation mesh.
pub type Region {
  Region(
    /// Canonical region ID matching GCP/AWS/Azure region codes.
    /// e.g. "europe-north1", "us-east1", "asia-southeast1"
    id: String,
    /// Human-readable location, e.g. "Stockholm", "Virginia"
    name: String,
    /// Zenoh TCP endpoint for this region's router.
    /// e.g. "tcp/zenoh-eu.example.com:7447"
    zenoh_endpoint: String,
    /// Whether the region is currently passing health checks.
    healthy: Bool,
    /// Number of Zenoh nodes in this region's mesh.
    node_count: Int,
    /// ZID or hostname of the current leader node in this region.
    leader_node: String,
    /// Unix epoch milliseconds of the last received heartbeat.
    last_heartbeat: Int,
  )
}

/// Aggregate federation state — the full multi-region picture.
pub type FederationState {
  FederationState(
    /// All registered regions, including unhealthy ones.
    regions: List(Region),
    /// ID of the region this node is running in.
    local_region: String,
    /// Sum of node_count across all regions.
    total_nodes: Int,
    /// Number of regions that are currently healthy.
    healthy_regions: Int,
    /// Current operating mode of the federation.
    federation_mode: FederationMode,
    /// Name of the consensus protocol in use, e.g. "raft", "2oo3-quorum".
    consensus_protocol: String,
  )
}

/// Operating mode of the federation — degrades gracefully on partition.
pub type FederationMode {
  /// All regions connected, full cross-region replication active.
  FullFederation
  /// Some regions unreachable; local quorum still met, degraded globally.
  PartialFederation
  /// No connectivity to other regions; local-only operation.
  IslandMode
  /// Re-establishing connections after a partition has healed.
  Recovering
}

/// Result of a cross-region health probe for a single region.
pub type RegionHealth {
  RegionHealth(
    /// The region being probed.
    region_id: String,
    /// Round-trip latency in milliseconds for the last probe.
    latency_ms: Int,
    /// Whether the region's Zenoh router is reachable.
    reachable: Bool,
    /// Whether the region's state is consistent with the local view.
    data_consistent: Bool,
    /// Whether the region is running the same software version.
    version_match: Bool,
  )
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Build the default 3-region federation state for a given local region.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">F26 bootstrap ↪ pure FederationState value</morphism>
///   <formal-proof>
///     <P> local_region is a non-empty String </P>
///     <C> init(local_region) </C>
///     <Q> Returns FederationState with 3 canonical regions; healthy=False until
///         probed; total_nodes is the sum of initial node_count values. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init(local_region: String) -> FederationState {
  let eu =
    Region(
      id: "europe-north1",
      name: "Stockholm",
      zenoh_endpoint: "tcp/zenoh-eu.example.com:7447",
      healthy: False,
      node_count: 3,
      leader_node: "eu-node-1",
      last_heartbeat: 0,
    )
  let us =
    Region(
      id: "us-east1",
      name: "Virginia",
      zenoh_endpoint: "tcp/zenoh-us.example.com:7447",
      healthy: False,
      node_count: 3,
      leader_node: "us-node-1",
      last_heartbeat: 0,
    )
  let apac =
    Region(
      id: "asia-southeast1",
      name: "Singapore",
      zenoh_endpoint: "tcp/zenoh-ap.example.com:7447",
      healthy: False,
      node_count: 2,
      leader_node: "ap-node-1",
      last_heartbeat: 0,
    )
  let regions = [eu, us, apac]
  let total = list.fold(regions, 0, fn(acc, r) { acc + r.node_count })
  FederationState(
    regions: regions,
    local_region: local_region,
    total_nodes: total,
    healthy_regions: 0,
    federation_mode: IslandMode,
    consensus_protocol: "2oo3-quorum",
  )
}

/// Construct the canonical 2-node Tailnet mesh federation state (nas-1 and vm-1).
pub fn init_tailnet_mesh() -> FederationState {
  let nas1 =
    Region(
      id: "nas-1",
      name: "NAS-1 Primary Host",
      zenoh_endpoint: "tcp/100.87.7.78:7447",
      healthy: True,
      node_count: 1,
      leader_node: "nas-1",
      last_heartbeat: 0,
    )
  let vm1 =
    Region(
      id: "vm-1",
      name: "VM-1 Peer Runtime Host",
      zenoh_endpoint: "tcp/100.78.98.18:7447",
      healthy: True,
      node_count: 1,
      leader_node: "vm-1",
      last_heartbeat: 0,
    )
  let regions = [nas1, vm1]
  let total = list.fold(regions, 0, fn(acc, r) { acc + r.node_count })
  FederationState(
    regions: regions,
    local_region: "nas-1",
    total_nodes: total,
    healthy_regions: 2,
    federation_mode: FullFederation,
    consensus_protocol: "2oo2-tailnet",
  )
}

/// Construct the canonical Tailnet node-level mesh federation state with nas-1 and vm-1.
pub fn init_tailnet_node_mesh(local_id: String) -> NodeFederationState {
  let nas1 =
    FederationNode(
      node_id: "nas-1",
      region: "tailnet-home",
      endpoint: "tcp/100.87.7.78:7447",
      role: Primary,
      health: 1.0,
      last_seen_ms: 0,
      version_vector: [#("nas-1", 1)],
    )
  let vm1 =
    FederationNode(
      node_id: "vm-1",
      region: "tailnet-home",
      endpoint: "tcp/100.78.98.18:7447",
      role: Backup,
      health: 1.0,
      last_seen_ms: 0,
      version_vector: [#("vm-1", 1)],
    )
  NodeFederationState(
    local_node: local_id,
    local_region: "tailnet-home",
    nodes: [nas1, vm1],
    quorum_size: 2,
    partition_detected: False,
  )
}

// ---------------------------------------------------------------------------
// Region management
// ---------------------------------------------------------------------------

/// Add a new region to the federation, recomputing totals.
pub fn add_region(state: FederationState, region: Region) -> FederationState {
  let regions = list.append(state.regions, [region])
  let total = list.fold(regions, 0, fn(acc, r) { acc + r.node_count })
  let healthy = list.filter(regions, fn(r) { r.healthy }) |> list.length()
  let mode = determine_mode_for(regions, healthy)
  FederationState(
    ..state,
    regions: regions,
    total_nodes: total,
    healthy_regions: healthy,
    federation_mode: mode,
  )
}

/// Remove a region by ID, recomputing totals.
pub fn remove_region(
  state: FederationState,
  region_id: String,
) -> FederationState {
  let regions = list.filter(state.regions, fn(r) { r.id != region_id })
  let total = list.fold(regions, 0, fn(acc, r) { acc + r.node_count })
  let healthy = list.filter(regions, fn(r) { r.healthy }) |> list.length()
  let mode = determine_mode_for(regions, healthy)
  FederationState(
    ..state,
    regions: regions,
    total_nodes: total,
    healthy_regions: healthy,
    federation_mode: mode,
  )
}

/// Update health status for a specific region, recomputing mode.
pub fn update_health(
  state: FederationState,
  region_id: String,
  healthy: Bool,
) -> FederationState {
  let regions =
    list.map(state.regions, fn(r) {
      case r.id == region_id {
        True -> Region(..r, healthy: healthy)
        False -> r
      }
    })
  let healthy_count = list.filter(regions, fn(r) { r.healthy }) |> list.length()
  let mode = determine_mode_for(regions, healthy_count)
  FederationState(
    ..state,
    regions: regions,
    healthy_regions: healthy_count,
    federation_mode: mode,
  )
}

// ---------------------------------------------------------------------------
// Mode determination
// ---------------------------------------------------------------------------

/// Compute the FederationMode from the current state.
/// Delegates to the internal helper which accepts raw region list + count.
pub fn determine_mode(state: FederationState) -> FederationMode {
  determine_mode_for(state.regions, state.healthy_regions)
}

// ---------------------------------------------------------------------------
// Quorum & leader
// ---------------------------------------------------------------------------

/// Returns True when a strict majority of regions are healthy.
/// Quorum rule: healthy_regions >= floor(total / 2) + 1.
///
/// Mirrors SC-SIL4-011: quorum floor(N/2)+1 maintained throughout upgrades.
pub fn is_quorum_met(state: FederationState) -> Bool {
  let total = list.length(state.regions)
  case total {
    0 -> False
    _ -> state.healthy_regions >= total / 2 + 1
  }
}

/// Returns True when the local region is the federation leader.
/// Leadership rule: local region is healthy AND is the lexicographically
/// first healthy region (deterministic tie-breaking, no network round-trip).
pub fn local_is_leader(state: FederationState) -> Bool {
  let healthy_ids =
    state.regions
    |> list.filter(fn(r) { r.healthy })
    |> list.map(fn(r) { r.id })
    |> list.sort(string.compare)
  case healthy_ids {
    [first, ..] -> first == state.local_region
    [] -> False
  }
}

// ---------------------------------------------------------------------------
// Zenoh topics
// ---------------------------------------------------------------------------

/// Return the canonical Zenoh key expressions for a region.
/// Pattern: indrajaal/{region_id}/{domain}/**
///
/// Aligned with SC-ZMOF-001 fractal namespace and SC-ZENOH-006.
pub fn zenoh_topics_for_region(region_id: String) -> List(String) {
  [
    "indrajaal/" <> region_id <> "/health/**",
    "indrajaal/" <> region_id <> "/guard/**",
    "indrajaal/" <> region_id <> "/ooda/**",
  ]
}

// ---------------------------------------------------------------------------
// Serialisation
// ---------------------------------------------------------------------------

/// Serialise the full FederationState to a compact JSON string.
pub fn to_json(state: FederationState) -> String {
  let regions_json =
    state.regions
    |> list.map(region_to_json)
    |> string.join(",")
  "{"
  <> "\"local_region\":\""
  <> state.local_region
  <> "\","
  <> "\"total_nodes\":"
  <> int.to_string(state.total_nodes)
  <> ","
  <> "\"healthy_regions\":"
  <> int.to_string(state.healthy_regions)
  <> ","
  <> "\"federation_mode\":\""
  <> mode_to_string(state.federation_mode)
  <> "\","
  <> "\"consensus_protocol\":\""
  <> state.consensus_protocol
  <> "\","
  <> "\"regions\":["
  <> regions_json
  <> "]"
  <> "}"
}

/// Human-readable one-liner summary for logs and TUI display.
pub fn summary(state: FederationState) -> String {
  "Federation["
  <> mode_to_string(state.federation_mode)
  <> "] local="
  <> state.local_region
  <> " healthy="
  <> int.to_string(state.healthy_regions)
  <> "/"
  <> int.to_string(list.length(state.regions))
  <> " nodes="
  <> int.to_string(state.total_nodes)
  <> " quorum="
  <> case is_quorum_met(state) {
    True -> "yes"
    False -> "no"
  }
  <> " leader="
  <> case local_is_leader(state) {
    True -> "yes"
    False -> "no"
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Core mode-determination logic, operating on raw region list + healthy count
/// rather than FederationState to avoid circular references in add/remove.
fn determine_mode_for(
  regions: List(Region),
  healthy_count: Int,
) -> FederationMode {
  let total = list.length(regions)
  case total, healthy_count {
    0, _ -> IslandMode
    t, h if h == t -> FullFederation
    _, 0 -> IslandMode
    t, h if h >= t / 2 + 1 -> PartialFederation
    _, _ -> Recovering
  }
}

fn region_to_json(r: Region) -> String {
  "{"
  <> "\"id\":\""
  <> r.id
  <> "\","
  <> "\"name\":\""
  <> r.name
  <> "\","
  <> "\"zenoh_endpoint\":\""
  <> r.zenoh_endpoint
  <> "\","
  <> "\"healthy\":"
  <> case r.healthy {
    True -> "true"
    False -> "false"
  }
  <> ","
  <> "\"node_count\":"
  <> int.to_string(r.node_count)
  <> ","
  <> "\"leader_node\":\""
  <> r.leader_node
  <> "\","
  <> "\"last_heartbeat\":"
  <> int.to_string(r.last_heartbeat)
  <> "}"
}

fn mode_to_string(mode: FederationMode) -> String {
  case mode {
    FullFederation -> "FullFederation"
    PartialFederation -> "PartialFederation"
    IslandMode -> "IslandMode"
    Recovering -> "Recovering"
  }
}
