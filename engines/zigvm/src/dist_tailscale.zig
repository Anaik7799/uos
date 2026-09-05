//! Semantic Domain: Zero-IP Distribution Mesh over Tailscale/Zenoh
//! Design Purpose: Mock of a Tailscale/WireGuard user-space endpoint bound to a Zenoh carrier for BEAM distribution.
//! Oracle/Final Encoding: Oracle is standard TCP distribution; Final Encoding is Tailscale machine keys and Zenoh pub/sub.
//! Operations: parseNodeIdentity, tailscaleTransferQueued, tailscaleShuttle
//! Observations: Handshake states, ETF payloads received.
//! Invariants: Node identities must have `ts-` prefix. Carrier buffer lengths correspond to payload sizes.
//! Algebraic Laws: 
//!   - Distribution Transparency: remote send equals local send by denotation.
//!   - Carrier Homomorphism: data written to `TailscaleCarrier` is read unmodified (byte conservation).
//!   - Identity Rejection: `parseNodeIdentity` rejects a name with no `@`
//!     (`InvalidNodeName`) or a non-`ts-` host (`NotTailscaleIdentity`).
//! Scope limits: Stratum B interpretation. Replaces default distribution carrier when `experimental_tailscale` is true.
//!   `TailscaleCarrier.writeBytes` is a deliberate no-op Zenoh-publish mock (DIVERGENCE 221).

const std = @import("std");
const dist = @import("dist.zig");
const etf = @import("etf.zig");
const ta = @import("term_algebra.zig");

pub var experimental_tailscale: bool = false;

/// Mock of a Tailscale/WireGuard user-space endpoint bound to a Zenoh carrier.
pub const TailscaleCarrier = struct {
    zenoh_topic: []const u8,
    machine_key: []const u8,
    gpa: std.mem.Allocator,
    inbox: std.ArrayList(u8),

    pub fn init(gpa: std.mem.Allocator, zenoh_topic: []const u8, machine_key: []const u8) !TailscaleCarrier {
        return .{
            .zenoh_topic = try gpa.dupe(u8, zenoh_topic),
            .machine_key = try gpa.dupe(u8, machine_key),
            .gpa = gpa,
            .inbox = .empty,
        };
    }

    pub fn deinit(self: *TailscaleCarrier) void {
        self.gpa.free(self.zenoh_topic);
        self.gpa.free(self.machine_key);
        self.inbox.deinit(self.gpa);
    }

    pub fn writeBytes(self: *TailscaleCarrier, bytes: []const u8) !void {
        _ = self;
        _ = bytes;
        // Mock Zenoh publish would happen here.
    }

    pub fn pushInbox(self: *TailscaleCarrier, bytes: []const u8) !void {
        try self.inbox.appendSlice(self.gpa, bytes);
    }

    pub fn readExactAlloc(self: *TailscaleCarrier, gpa: std.mem.Allocator, len: usize) ![]u8 {
        if (self.inbox.items.len < len) return error.NotEnoughData;
        const out = try gpa.alloc(u8, len);
        @memcpy(out, self.inbox.items[0..len]);
        self.inbox.replaceRangeAssumeCapacity(0, len, &.{});
        return out;
    }
};

/// Extract cryptographic ts-machine-key identity from a node name
pub fn parseNodeIdentity(node_name: []const u8) ![]const u8 {
    var it = std.mem.splitScalar(u8, node_name, '@');
    _ = it.next();
    const host = it.next() orelse return error.InvalidNodeName;
    if (std.mem.startsWith(u8, host, "ts-")) {
        return host;
    }
    return error.NotTailscaleIdentity;
}

pub fn tailscaleTransferQueued(gpa: std.mem.Allocator, from: *dist.Node, to: *dist.Node, out_carrier: *TailscaleCarrier, in_carrier: *TailscaleCarrier) !usize {
    if (!experimental_tailscale) return 0;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(gpa);
    try from.takeOutput(&bytes);
    if (bytes.items.len == 0) return 0;
    
    // Simulate crossing the Zenoh carrier
    try out_carrier.writeBytes(bytes.items);
    try in_carrier.pushInbox(bytes.items);

    const wire = try in_carrier.readExactAlloc(gpa, bytes.items.len);
    defer gpa.free(wire);
    try to.pump(wire);
    return bytes.items.len;
}

pub fn tailscaleShuttle(gpa: std.mem.Allocator, a: *dist.Node, b: *dist.Node, ab: *TailscaleCarrier, ba: *TailscaleCarrier) !void {
    var quiet: usize = 0;
    while (quiet < 2) {
        const moved_ab = try tailscaleTransferQueued(gpa, a, b, ab, ba);
        const moved_ba = try tailscaleTransferQueued(gpa, b, a, ba, ab);
        if (moved_ab == 0 and moved_ba == 0) quiet += 1 else quiet = 0;
    }
}

test "parseNodeIdentity rejection law: non-ts hosts and malformed names reject" {
    // REJECTION law (audit e18-t5): every exported decl law-reached — the error
    // arms of parseNodeIdentity are pinned so a mutant that accepts a non-`ts-`
    // host or a name without `@` goes RED.
    try std.testing.expectError(error.NotTailscaleIdentity, parseNodeIdentity("node@plainhost"));
    try std.testing.expectError(error.NotTailscaleIdentity, parseNodeIdentity("node@localhost"));
    // No '@' segment: splitScalar yields one field, second next() is null.
    try std.testing.expectError(error.InvalidNodeName, parseNodeIdentity("bare-node-name"));
    // Empty host after '@' is not ts-prefixed.
    try std.testing.expectError(error.NotTailscaleIdentity, parseNodeIdentity("node@"));
    // Accept arm: a well-formed ts- identity round-trips to the host segment.
    try std.testing.expectEqualStrings("ts-abc", try parseNodeIdentity("n@ts-abc"));
}

test "Zero-IP Identity over Tailscale/Zenoh" {
    experimental_tailscale = true;
    defer experimental_tailscale = false;

    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // 1 & 2: Parse ts-machine-key identities
    const node_a_name = "node_a@ts-machine-key-12345";
    const node_b_name = "node_b@ts-machine-key-67890";
    const key_a = try parseNodeIdentity(node_a_name);
    const key_b = try parseNodeIdentity(node_b_name);
    try std.testing.expectEqualStrings("ts-machine-key-12345", key_a);
    try std.testing.expectEqualStrings("ts-machine-key-67890", key_b);

    // Initialize Mock Endpoints
    var carrier_a = try TailscaleCarrier.init(gpa, "zenoh/dist", key_a);
    defer carrier_a.deinit();
    var carrier_b = try TailscaleCarrier.init(gpa, "zenoh/dist", key_b);
    defer carrier_b.deinit();

    // Initialize Distribution Nodes
    var node_a = try dist.Node.init(gpa, &atoms, node_a_name, 1);
    defer node_a.deinit();
    var node_b = try dist.Node.init(gpa, &atoms, node_b_name, 2);
    defer node_b.deinit();

    // Perform handshake over Tailscale
    try node_a.startHandshake();
    try node_b.startHandshake();
    try tailscaleShuttle(gpa, &node_a, &node_b, &carrier_a, &carrier_b);

    try std.testing.expectEqual(dist.HsState.connected, node_a.hs);
    try std.testing.expectEqual(dist.HsState.connected, node_b.hs);

    // 3. Validate M9 ETF routing over the tunnel
    const target_pid = try node_b.vm.spawn(&.{}, 0, null);
    const source_pid = try node_a.vm.spawn(&.{}, 0, null);

    const term_to_send = ta.FinalTerms.atom(&node_a.vm.procs.items[source_pid].machine.ctx, try atoms.intern("hello_etf"));
    
    try node_a.sendRemote(source_pid, target_pid, 2, term_to_send, &node_a.vm.procs.items[source_pid].machine.ctx);

    try tailscaleShuttle(gpa, &node_a, &node_b, &carrier_a, &carrier_b);
    
    // Validate target received the ETF payload
    const receiver = node_b.vm.procs.items[target_pid];
    try std.testing.expect(receiver.sigq.items.len == 1);
    const sig = receiver.sigq.items[0].sig;
    
    // Should be a message signal
    switch (sig) {
        .message => |m| {
            // Check it is indeed the 'hello_etf' atom
            const expected = ta.FinalTerms.atom(&node_b.vm.procs.items[target_pid].machine.ctx, try atoms.intern("hello_etf"));
            try std.testing.expect(ta.FinalTerms.eqlExact(&node_b.vm.procs.items[target_pid].machine.ctx, m, expected));
        },
        else => unreachable,
    }
}
