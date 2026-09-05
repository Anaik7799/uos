//! Semantic Domain: mesh substrate reconciliation — peer discovery + eventual
//! message delivery under partition. Two law-governed cores plus one quarantined
//! network interpretation.
//!
//! Oracle/Final Encoding:
//!   - `PeerView` is a state-based CvRDT: the ORACLE is a partial map
//!     node -> last-seen timestamp; the JOIN is pointwise `max`. It forms a
//!     bounded join-semilattice, so anti-entropy (repeated `mergeInto`) is a
//!     monotone convergence process — the algebraic content of gossip.
//!   - `MeshState` is the executable mirror of `specs/mesh_spec.qnt`: the four
//!     state variables (network/delivered/buffered/partitioned + next_msg_id)
//!     and the five actions (send/deliver/partition_node/heal_node/flush). Its
//!     laws ARE the Quint invariants, checked under a bounded twin-seeded driver
//!     over the same action set the model `step` ranges over.
//!   - `GossipEngine` is the anti-entropy discovery interpreter: it encodes
//!     `PRESENCE <node>` frames and decodes them into `PeerView.observe` under
//!     an explicit receive clock. The raw UDP-broadcast TRANSPORT that would
//!     ferry those frames between hosts is quarantined Stratum-C and is NOT
//!     independently law-bound here (DIVERGENCE 220 — live socket delivery is
//!     owned by the E18 live-carrier tasks). The engine's *state transition*
//!     (observe) is the pure core and is what the laws pin.
//!
//! Operations: PeerView(observe, mergeInto, clone, get, equalTo);
//!             MeshState(send, deliver, partition, heal, flush, drain);
//!             GossipEngine(init, deinit, encodePresence, ingestPresence).
//! Observations: peer timestamps; message-location membership; delivered count.
//! Invariants (MeshState, = mesh_spec.qnt): no message lost
//!   (|network|+|delivered|+Σ|buffered| == next_msg_id); delivered ∩ network = ∅;
//!   buffered ∩ network = ∅.
//! Algebraic Laws:
//!   - PeerView JOIN idempotence:     a ⊔ a  == a
//!   - PeerView JOIN commutativity:   a ⊔ b  == b ⊔ a
//!   - PeerView JOIN associativity:  (a⊔b)⊔c == a⊔(b⊔c)
//!   - PeerView LWW monotonicity:     observe keeps the max timestamp
//!   - PeerView anti-entropy round-trip: joining a dominated delta is a no-op
//!   - MeshState no-message-lost / delivered-disjoint / buffered-disjoint
//!   - MeshState bounded eventual delivery: heal-all then drain empties the
//!     network and every buffer; delivered count == next_msg_id.
//! Scope limits: the UDP path is Stratum-C substrate (mock, unbounded network);
//!   the laws never touch a socket. No wire-format conformance is claimed here.
//! e19-t5: MeshState is the executable mirror model-checked by the harness
//!   `--run-mesh-verify` mode against `specs/mesh_spec.qnt` (extended with the
//!   idempotent `redeliver` action) and `proofs/Mesh_Delivery.v` (the Rocq
//!   delivery proof: NO-MESSAGE-LOST as an inductive invariant of the action
//!   set, BOUNDED EVENTUAL DELIVERY via `drain`, IDEMPOTENT RE-DELIVERY). See
//!   DIVERGENCE 380 (delivery triad) / 220 (UDP transport) / 221 (Zenoh mock).

const std = @import("std");
const ta = @import("term_algebra.zig");
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

pub var experimental_gossip: bool = false;

// ---------------------------------------------------------------------------
// PeerView — a state-based CvRDT (node -> last-seen timestamp, join = max).
// ---------------------------------------------------------------------------

pub const PeerView = struct {
    map: std.StringHashMap(i64),

    pub fn init(allocator: std.mem.Allocator) PeerView {
        return .{ .map = std.StringHashMap(i64).init(allocator) };
    }

    pub fn deinit(self: *PeerView) void {
        var it = self.map.iterator();
        while (it.next()) |entry| self.map.allocator.free(entry.key_ptr.*);
        self.map.deinit();
    }

    /// LWW observation: record `name` last seen at `ts`, keeping the MAX of any
    /// prior timestamp (the pointwise join). Returns true iff `name` was newly
    /// discovered (drives the discovery callback). Owns a private copy of `name`.
    pub fn observe(self: *PeerView, name: []const u8, ts: i64) !bool {
        if (self.map.getEntry(name)) |entry| {
            if (ts > entry.value_ptr.*) entry.value_ptr.* = ts;
            return false;
        }
        const owned = try self.map.allocator.dupe(u8, name);
        errdefer self.map.allocator.free(owned);
        try self.map.put(owned, ts);
        return true;
    }

    pub fn get(self: *const PeerView, name: []const u8) ?i64 {
        return self.map.get(name);
    }

    /// Join `other` into `self` in place: for every node, take the max timestamp.
    pub fn mergeInto(self: *PeerView, other: *const PeerView) !void {
        var it = other.map.iterator();
        while (it.next()) |entry| {
            _ = try self.observe(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    pub fn clone(self: *const PeerView, allocator: std.mem.Allocator) !PeerView {
        var out = PeerView.init(allocator);
        errdefer out.deinit();
        var it = self.map.iterator();
        while (it.next()) |entry| {
            _ = try out.observe(entry.key_ptr.*, entry.value_ptr.*);
        }
        return out;
    }

    /// Observational equality: same node set with identical timestamps.
    pub fn equalTo(self: *const PeerView, other: *const PeerView) bool {
        if (self.map.count() != other.map.count()) return false;
        var it = self.map.iterator();
        while (it.next()) |entry| {
            const ov = other.map.get(entry.key_ptr.*) orelse return false;
            if (ov != entry.value_ptr.*) return false;
        }
        return true;
    }
};

// ---------------------------------------------------------------------------
// GossipEngine — anti-entropy discovery interpreter over the PeerView core.
//
// The `PRESENCE <node>` frame encode/decode and the discovery state transition
// are pure and law-covered. The raw UDP-broadcast TRANSPORT that would ferry
// those frames between hosts is quarantined Stratum-C: it is NOT independently
// law-bound here (see DIVERGENCE 220). Live socket delivery is owned by the
// E18 live-carrier tasks (Task 1/3), not by gossip.
// ---------------------------------------------------------------------------

pub const PRESENCE_PREFIX = "PRESENCE ";

pub const GossipEngine = struct {
    allocator: std.mem.Allocator,
    peers: PeerView,
    node_name: []const u8,
    on_peer_discovered: ?*const fn (name: []const u8) void,

    pub fn init(allocator: std.mem.Allocator, node_name: []const u8, on_peer_discovered: ?*const fn (name: []const u8) void) !GossipEngine {
        return GossipEngine{
            .allocator = allocator,
            .peers = PeerView.init(allocator),
            .node_name = node_name,
            .on_peer_discovered = on_peer_discovered,
        };
    }

    pub fn deinit(self: *GossipEngine) void {
        self.peers.deinit();
    }

    /// Encode this node's presence announcement. Owned by the caller. The
    /// transport that would broadcast it is DIVERGENCE-220-bounded.
    pub fn encodePresence(self: *const GossipEngine, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, PRESENCE_PREFIX ++ "{s}", .{self.node_name});
    }

    /// Decode a single `PRESENCE <node>` frame into the PeerView core, stamping
    /// it with the receive clock `now` (the clock read is the caller's Stratum-C
    /// responsibility, keeping this transition pure). The state transition is
    /// `PeerView.observe`; non-PRESENCE frames are ignored. This is the
    /// anti-entropy receive step, drivable without any socket.
    pub fn ingestPresence(self: *GossipEngine, msg: []const u8, now: i64) !void {
        if (std.mem.startsWith(u8, msg, PRESENCE_PREFIX)) {
            const name = msg[PRESENCE_PREFIX.len..];
            const is_new = try self.peers.observe(name, now);
            if (is_new) {
                if (self.on_peer_discovered) |cb| cb(name);
            }
        }
    }
};

// ---------------------------------------------------------------------------
// MeshState — executable mirror of specs/mesh_spec.qnt (eventual delivery).
// ---------------------------------------------------------------------------

const MsgId = u32;

pub const Msg = struct { id: MsgId, src: u8, dst: u8 };

/// Faithful port of the Quint model: msg locations are three disjoint sets
/// (network / delivered / buffered-per-node), gated by a per-node partition
/// flag. A mutation that drops or double-counts a message breaks one of the
/// three invariants — so these laws can go RED.
pub const MeshState = struct {
    allocator: std.mem.Allocator,
    n_nodes: u8,
    table: std.ArrayList(Msg), // msg id -> {src,dst}; index == id
    network: std.ArrayList(MsgId),
    delivered: std.ArrayList(MsgId),
    buffered: []std.ArrayList(MsgId), // per source node
    partitioned: []bool,
    next_msg_id: MsgId,

    pub fn init(allocator: std.mem.Allocator, n_nodes: u8) !MeshState {
        const buffered = try allocator.alloc(std.ArrayList(MsgId), n_nodes);
        for (buffered) |*b| b.* = .empty;
        const partitioned = try allocator.alloc(bool, n_nodes);
        @memset(partitioned, false);
        return .{
            .allocator = allocator,
            .n_nodes = n_nodes,
            .table = .empty,
            .network = .empty,
            .delivered = .empty,
            .buffered = buffered,
            .partitioned = partitioned,
            .next_msg_id = 0,
        };
    }

    pub fn deinit(self: *MeshState) void {
        self.table.deinit(self.allocator);
        self.network.deinit(self.allocator);
        self.delivered.deinit(self.allocator);
        for (self.buffered) |*b| b.deinit(self.allocator);
        self.allocator.free(self.buffered);
        self.allocator.free(self.partitioned);
    }

    fn removeValue(list: *std.ArrayList(MsgId), id: MsgId) bool {
        for (list.items, 0..) |v, i| {
            if (v == id) {
                _ = list.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    fn contains(list: *const std.ArrayList(MsgId), id: MsgId) bool {
        for (list.items) |v| if (v == id) return true;
        return false;
    }

    /// action send(src,dst): partitioned endpoint -> buffer at src; else network.
    pub fn send(self: *MeshState, src: u8, dst: u8) !void {
        const id = self.next_msg_id;
        try self.table.append(self.allocator, .{ .id = id, .src = src, .dst = dst });
        self.next_msg_id += 1;
        if (self.partitioned[src] or self.partitioned[dst]) {
            try self.buffered[src].append(self.allocator, id);
        } else {
            try self.network.append(self.allocator, id);
        }
    }

    /// action deliver(msg): in network AND dst not partitioned -> delivered.
    pub fn deliver(self: *MeshState, id: MsgId) !bool {
        if (!contains(&self.network, id)) return false;
        if (self.partitioned[self.table.items[id].dst]) return false;
        _ = removeValue(&self.network, id);
        try self.delivered.append(self.allocator, id);
        return true;
    }

    pub fn partition(self: *MeshState, n: u8) void {
        self.partitioned[n] = true;
    }

    pub fn heal(self: *MeshState, n: u8) void {
        self.partitioned[n] = false;
    }

    /// action flush(src,dst): both unpartitioned -> buffered msgs to dst re-enter
    /// the network.
    pub fn flush(self: *MeshState, src: u8, dst: u8) !void {
        if (self.partitioned[src] or self.partitioned[dst]) return;
        var i: usize = 0;
        while (i < self.buffered[src].items.len) {
            const id = self.buffered[src].items[i];
            if (self.table.items[id].dst == dst) {
                _ = self.buffered[src].swapRemove(i);
                try self.network.append(self.allocator, id);
            } else i += 1;
        }
    }

    /// Drive to quiescence: heal everyone, flush every buffer, deliver everything.
    /// Bounded — each message can leave a buffer / the network at most once.
    pub fn drain(self: *MeshState) !void {
        for (0..self.n_nodes) |n| self.heal(@intCast(n));
        var s: u8 = 0;
        while (s < self.n_nodes) : (s += 1) {
            var d: u8 = 0;
            while (d < self.n_nodes) : (d += 1) try self.flush(s, d);
        }
        // network is finite and deliver only shrinks it; snapshot then drain.
        var pending = try self.network.clone(self.allocator);
        defer pending.deinit(self.allocator);
        for (pending.items) |id| _ = try self.deliver(id);
    }

    // ---- observations feeding the invariants ----
    fn bufferedTotal(self: *const MeshState) usize {
        var t: usize = 0;
        for (self.buffered) |b| t += b.items.len;
        return t;
    }

    /// inv_no_message_lost: every created id lives in exactly the union.
    pub fn invNoMessageLost(self: *const MeshState) bool {
        return self.network.items.len + self.delivered.items.len + self.bufferedTotal() == self.next_msg_id;
    }

    /// inv_delivered_never_in_network.
    pub fn invDeliveredDisjoint(self: *const MeshState) bool {
        for (self.delivered.items) |id| if (contains(&self.network, id)) return false;
        return true;
    }

    /// inv_buffered_not_in_network.
    pub fn invBufferedDisjoint(self: *const MeshState) bool {
        for (self.buffered) |b| {
            for (b.items) |id| if (contains(&self.network, id)) return false;
        }
        return true;
    }

    pub fn invariantsHold(self: *const MeshState) bool {
        return self.invNoMessageLost() and self.invDeliveredDisjoint() and self.invBufferedDisjoint();
    }
};

// ---------------------------------------------------------------------------
// Law suite
// ---------------------------------------------------------------------------

const NODE_NAMES = [_][]const u8{ "n1", "n2", "n3", "n4", "n5" };

fn buildView(alloc: std.mem.Allocator, random: std.Random, steps: usize) !PeerView {
    var v = PeerView.init(alloc);
    errdefer v.deinit();
    for (0..steps) |_| {
        const name = NODE_NAMES[random.uintLessThan(usize, NODE_NAMES.len)];
        const ts: i64 = @intCast(random.uintLessThan(u64, 1000));
        _ = try v.observe(name, ts);
    }
    return v;
}

test "PeerView CvRDT join laws (idempotence/commutativity/associativity/anti-entropy)" {
    const alloc = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0x6055_1901, .iterations = 200 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var a = try buildView(alloc, random, random.uintLessThan(usize, 12));
        defer a.deinit();
        var b = try buildView(alloc, random, random.uintLessThan(usize, 12));
        defer b.deinit();
        var c = try buildView(alloc, random, random.uintLessThan(usize, 12));
        defer c.deinit();

        // idempotence: a ⊔ a == a
        {
            var aa = try a.clone(alloc);
            defer aa.deinit();
            try aa.mergeInto(&a);
            try expectLaw(aa.equalTo(&a), "gossip: PeerView join idempotence", cfg, i);
        }
        // commutativity: a ⊔ b == b ⊔ a
        {
            var ab = try a.clone(alloc);
            defer ab.deinit();
            try ab.mergeInto(&b);
            var ba = try b.clone(alloc);
            defer ba.deinit();
            try ba.mergeInto(&a);
            try expectLaw(ab.equalTo(&ba), "gossip: PeerView join commutativity", cfg, i);
        }
        // associativity: (a ⊔ b) ⊔ c == a ⊔ (b ⊔ c)
        {
            var lhs = try a.clone(alloc);
            defer lhs.deinit();
            try lhs.mergeInto(&b);
            try lhs.mergeInto(&c);
            var bc = try b.clone(alloc);
            defer bc.deinit();
            try bc.mergeInto(&c);
            var rhs = try a.clone(alloc);
            defer rhs.deinit();
            try rhs.mergeInto(&bc);
            try expectLaw(lhs.equalTo(&rhs), "gossip: PeerView join associativity", cfg, i);
        }
        // anti-entropy round-trip: joining a dominated delta (a itself, or a⊔b
        // back into a⊔b) changes nothing.
        {
            var full = try a.clone(alloc);
            defer full.deinit();
            try full.mergeInto(&b);
            var again = try full.clone(alloc);
            defer again.deinit();
            try again.mergeInto(&a); // a is dominated by full
            try again.mergeInto(&b); // b is dominated by full
            try expectLaw(again.equalTo(&full), "gossip: PeerView anti-entropy round-trip is a no-op", cfg, i);
        }
    }
}

test "PeerView LWW monotonicity: observe keeps the max timestamp" {
    const alloc = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0x6055_1902, .iterations = 200 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var v = PeerView.init(alloc);
        defer v.deinit();
        const name = NODE_NAMES[random.uintLessThan(usize, NODE_NAMES.len)];
        var running_max: i64 = std.math.minInt(i64);
        const steps = 1 + random.uintLessThan(usize, 10);
        for (0..steps) |_| {
            const ts: i64 = @intCast(random.uintLessThan(u64, 1000));
            running_max = @max(running_max, ts);
            _ = try v.observe(name, ts);
            try expectLaw(v.get(name).? == running_max, "gossip: PeerView observe is a running max (LWW)", cfg, i);
        }
    }
}

fn checkInvariants(m: *const MeshState, cfg: LawConfig, i: usize) !void {
    try expectLaw(m.invNoMessageLost(), "gossip: MeshState no message lost", cfg, i);
    try expectLaw(m.invDeliveredDisjoint(), "gossip: MeshState delivered disjoint from network", cfg, i);
    try expectLaw(m.invBufferedDisjoint(), "gossip: MeshState buffered disjoint from network", cfg, i);
}

test "MeshState invariants + bounded eventual delivery (mesh_spec.qnt driver)" {
    const alloc = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0x6055_1903, .iterations = 120 };
    const n_nodes: u8 = 3; // matches mesh_spec_test: Set("n1","n2","n3")

    for (0..cfg.iterations) |i| {
        // twin-seeded: fresh stream per iteration, echoes seed+iter on failure.
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();

        var m = try MeshState.init(alloc, n_nodes);
        defer m.deinit();

        try checkInvariants(&m, cfg, i);

        const steps = 1 + random.uintLessThan(usize, 40);
        for (0..steps) |_| {
            switch (random.uintLessThan(u8, 5)) {
                0 => try m.send(random.uintLessThan(u8, n_nodes), random.uintLessThan(u8, n_nodes)),
                1 => {
                    if (m.network.items.len != 0) {
                        const id = m.network.items[random.uintLessThan(usize, m.network.items.len)];
                        _ = try m.deliver(id);
                    }
                },
                2 => m.partition(random.uintLessThan(u8, n_nodes)),
                3 => m.heal(random.uintLessThan(u8, n_nodes)),
                else => try m.flush(random.uintLessThan(u8, n_nodes), random.uintLessThan(u8, n_nodes)),
            }
            try checkInvariants(&m, cfg, i);
        }

        // bounded eventual delivery: heal + drain empties network & buffers,
        // and everything ever sent is now delivered exactly once.
        try m.drain();
        try checkInvariants(&m, cfg, i);
        try expectLaw(m.network.items.len == 0, "gossip: eventual delivery empties the network", cfg, i);
        try expectLaw(m.bufferedTotal() == 0, "gossip: eventual delivery empties every buffer", cfg, i);
        try expectLaw(m.delivered.items.len == m.next_msg_id, "gossip: eventual delivery delivers every message once", cfg, i);
    }
}

test "GossipEngine presence encode/ingest round-trip discovers peers via PeerView" {
    experimental_gossip = false; // transport is DIVERGENCE-220-bounded; drive the core
    const alloc = std.testing.allocator;

    const Seen = struct {
        var count: usize = 0;
        fn cb(_: []const u8) void {
            count += 1;
        }
    };
    Seen.count = 0;

    var self_engine = try GossipEngine.init(alloc, "peer_a", null);
    defer self_engine.deinit();
    var engine = try GossipEngine.init(alloc, "self@node", &Seen.cb);
    defer engine.deinit();

    // encode∘ingest round-trip: a peer's own announcement is discovered.
    const frame = try self_engine.encodePresence(alloc);
    defer alloc.free(frame);
    try std.testing.expectEqualStrings("PRESENCE peer_a", frame);
    try engine.ingestPresence(frame, 100);

    try engine.ingestPresence("PRESENCE peer_b", 101);
    try engine.ingestPresence("PRESENCE peer_a", 102); // duplicate: no re-discovery
    try engine.ingestPresence("garbage frame", 103); // non-PRESENCE: ignored

    try std.testing.expectEqual(@as(usize, 2), Seen.count);
    try std.testing.expect(engine.peers.get("peer_a") != null);
    try std.testing.expect(engine.peers.get("peer_b") != null);
    try std.testing.expect(engine.peers.get("garbage") == null);
}
