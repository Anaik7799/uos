//! Semantic Domain: Conflict-free Replicated Data Types (CRDTs)
//! Design Purpose: LWW-Register and PN-Counter implementations for distributed Zenoh payloads.
//! Oracle/Final Encoding: Oracle is a logical set/counter; Final encoding is a node-tagged time/value vector.
//! Operations: LWWRegister(init, merge), PNCounter(init, append, increment, decrement, merge, value)
//! Observations: Register value, PNCounter value.
//! Invariants: PNCounter node_id uniqueness in entries. LWW uses timestamp and node_id for total order.
//! Algebraic Laws: 
//!   - Idempotence: a merge a == a
//!   - Commutativity: a merge b == b merge a
//!   - Associativity: (a merge b) merge c == a merge (b merge c)
//! Scope limits: Stratum A algebraic core. Does not handle transport.

const std = @import("std");

/// Last-Write-Wins (LWW) Register
pub fn LWWRegister(comptime T: type) type {
    return struct {
        value: T,
        timestamp: i64,
        node_id: u32,

        const Self = @This();

        pub fn init(value: T, timestamp: i64, node_id: u32) Self {
            return .{
                .value = value,
                .timestamp = timestamp,
                .node_id = node_id,
            };
        }

        pub fn merge(self: Self, other: Self) Self {
            if (other.timestamp > self.timestamp) {
                return other;
            } else if (other.timestamp == self.timestamp) {
                if (other.node_id > self.node_id) {
                    return other;
                }
            }
            return self;
        }
    };
}

/// Positive-Negative (PN) Counter
pub const PNCounter = struct {
    pub const Entry = struct {
        node_id: u32,
        inc: u64 = 0,
        dec: u64 = 0,
    };

    const MAX_NODES = 32;
    
    entries: [MAX_NODES]Entry = undefined,
    len: usize = 0,

    pub fn init() PNCounter {
        return .{};
    }

    pub fn slice(self: *PNCounter) []Entry {
        return self.entries[0..self.len];
    }

    pub fn constSlice(self: *const PNCounter) []const Entry {
        return self.entries[0..self.len];
    }

    pub fn append(self: *PNCounter, entry: Entry) !void {
        if (self.len >= MAX_NODES) return error.OutOfMemory;
        self.entries[self.len] = entry;
        self.len += 1;
    }

    pub fn increment(self: *PNCounter, node_id: u32, amount: u64) !void {
        for (self.slice()) |*entry| {
            if (entry.node_id == node_id) {
                entry.inc += amount;
                return;
            }
        }
        try self.append(.{ .node_id = node_id, .inc = amount, .dec = 0 });
    }

    pub fn decrement(self: *PNCounter, node_id: u32, amount: u64) !void {
        for (self.slice()) |*entry| {
            if (entry.node_id == node_id) {
                entry.dec += amount;
                return;
            }
        }
        try self.append(.{ .node_id = node_id, .inc = 0, .dec = amount });
    }

    pub fn value(self: *const PNCounter) i64 {
        var val: i64 = 0;
        for (self.constSlice()) |entry| {
            val += @as(i64, @intCast(entry.inc));
            val -= @as(i64, @intCast(entry.dec));
        }
        return val;
    }

    pub fn merge(self: *const PNCounter, other: *const PNCounter) PNCounter {
        var merged = PNCounter.init();
        
        // Add all from self
        for (self.constSlice()) |self_entry| {
            merged.append(self_entry) catch unreachable;
        }

        // Merge other
        for (other.constSlice()) |other_entry| {
            var found = false;
            for (merged.slice()) |*merged_entry| {
                if (merged_entry.node_id == other_entry.node_id) {
                    merged_entry.inc = @max(merged_entry.inc, other_entry.inc);
                    merged_entry.dec = @max(merged_entry.dec, other_entry.dec);
                    found = true;
                    break;
                }
            }
            if (!found) {
                merged.append(other_entry) catch unreachable;
            }
        }
        
        // Manual insertion sort by node_id to guarantee commutativity 
        // yields a bitwise identical struct regardless of merge order.
        const merged_slice = merged.slice();
        var i: usize = 1;
        while (i < merged_slice.len) : (i += 1) {
            var j = i;
            while (j > 0 and merged_slice[j].node_id < merged_slice[j - 1].node_id) : (j -= 1) {
                const temp = merged_slice[j];
                merged_slice[j] = merged_slice[j - 1];
                merged_slice[j - 1] = temp;
            }
        }

        return merged;
    }
};

/// Mock Zenoh carrier payload definitions
pub const ZenohPayload = union(enum) {
    lww_register: LWWRegister(i64),
    pn_counter: PNCounter,
};

test "LWWRegister merge laws" {
    const testing = std.testing;
    const Reg = LWWRegister(i64);
    
    const a = Reg.init(10, 100, 1);
    const b = Reg.init(20, 200, 2);
    const c = Reg.init(30, 200, 3);
    
    // Idempotence: a merge a == a
    try testing.expectEqual(a, a.merge(a));
    
    // Commutativity: a merge b == b merge a
    try testing.expectEqual(b, a.merge(b));
    try testing.expectEqual(b, b.merge(a));
    
    // Associativity: (a merge b) merge c == a merge (b merge c)
    try testing.expectEqual(a.merge(b).merge(c), a.merge(b.merge(c)));
    
    // Tie breaker check
    try testing.expectEqual(c, b.merge(c));
}

test "PNCounter merge laws" {
    const testing = std.testing;
    
    var a = PNCounter.init();
    try a.increment(1, 10);
    try a.decrement(1, 2);
    
    var b = PNCounter.init();
    try b.increment(2, 5);
    try b.decrement(2, 1);
    
    var c = PNCounter.init();
    try c.increment(1, 20); // higher inc for node 1
    
    // Idempotence: a merge a == a
    const a_a = a.merge(&a);
    try testing.expectEqual(a.value(), a_a.value());
    
    // Commutativity: a merge b == b merge a
    const a_b = a.merge(&b);
    const b_a = b.merge(&a);
    
    try testing.expectEqual(a_b.value(), b_a.value());
    // Also structural equality check
    try testing.expectEqualSlices(PNCounter.Entry, a_b.constSlice(), b_a.constSlice());
    
    // Associativity: (a merge b) merge c == a merge (b merge c)
    const ab_c = a_b.merge(&c);
    const b_c = b.merge(&c);
    const a_bc = a.merge(&b_c);
    try testing.expectEqual(ab_c.value(), a_bc.value());
    try testing.expectEqualSlices(PNCounter.Entry, ab_c.constSlice(), a_bc.constSlice());
}
