//! beam-zig Milestone 2 / S3: the **atom table** (cf. erts atom.c).
//!
//! Atoms are VM-global (node-wide), not per-process-heap: process heaps hold
//! only indices; the table owns the names. Algebraically, the table is an
//! interning bijection between a growing set of names and 0..n indices.
//!
//! Signature:   intern : bytes -> AtomIdx      (constructor, effectful-once)
//!              nameOf : AtomIdx -> bytes      (observation)
//! Laws:        round-trip     nameOf(intern(s)) == s
//!              idempotence    intern(s) == intern(s)
//!              injectivity    s1 != s2  =>  intern(s1) != intern(s2)
//!
//! The law this table imposes on the TERM algebra (the M1 retrofit): atom
//! comparison is LEXICAL on names, never numeric on indices — enforced by
//! term_algebra.zig's spec-agreement property, since an atom now *denotes*
//! its name.

const std = @import("std");

pub const AtomIdx = u32;

pub const AtomTable = struct {
    // e48-smp-s3 (THREAD SAFETY): the table is the ONE store every machine
    // reads inline during execution, so it must survive concurrent grants.
    // Design: a FIXED SEGMENT DIRECTORY — names live in fixed-size blocks that
    // are NEVER moved (the directory itself is an inline fixed array, so no
    // reallocation exists anywhere on the read path), `intern` is mutex-
    // guarded (writers rare), and `nameOf` is LOCK-FREE: a slot is written
    // BEFORE the count is published with .release, and readers .acquire the
    // count — an index obtained from intern (yours or another thread's,
    // observed via any happens-before) always reads a fully-written stable
    // slot. Capacity: 1024×1024 = 1,048,576 atoms (the erts default limit).
    const SEG_BITS = 10;
    const SEG_SIZE = 1 << SEG_BITS; // 1024 names per segment
    const MAX_SEGS = 1024;
    const Segment = [SEG_SIZE][]const u8;

    const SpinLock = struct {
        held: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        fn lock(self: *SpinLock) void {
            while (self.held.swap(true, .acquire)) std.Thread.yield() catch {};
        }
        fn unlock(self: *SpinLock) void {
            self.held.store(false, .release);
        }
    };

    gpa: std.mem.Allocator,
    segments: [MAX_SEGS]?*Segment,
    n_atoms: std.atomic.Value(u32),
    lookup: std.StringHashMapUnmanaged(AtomIdx),
    // the repo lock idiom (std.Thread.Mutex is absent on this pinned Zig):
    // an atomic spinlock — writers are rare (intern of a NEW name only).
    mu: SpinLock,

    pub fn init(gpa: std.mem.Allocator) AtomTable {
        return .{
            .gpa = gpa,
            .segments = @splat(null),
            .n_atoms = std.atomic.Value(u32).init(0),
            .lookup = .empty,
            .mu = .{},
        };
    }

    pub fn deinit(self: *AtomTable) void {
        const n = self.n_atoms.load(.acquire);
        var i: u32 = 0;
        while (i < n) : (i += 1) self.gpa.free(self.segments[i >> SEG_BITS].?[i & (SEG_SIZE - 1)]);
        for (self.segments) |maybe| {
            if (maybe) |seg| self.gpa.destroy(seg);
        }
        self.lookup.deinit(self.gpa);
    }

    /// Intern a name, returning its stable index. Idempotent. Thread-safe
    /// (mutex-guarded — the write path; concurrent `nameOf` readers never
    /// block and never observe a partial slot).
    pub fn intern(self: *AtomTable, name: []const u8) !AtomIdx {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.lookup.get(name)) |idx| return idx;
        const idx: u32 = self.n_atoms.load(.monotonic);
        // The capacity cap (the erts atom-limit analogue) reports as resource
        // exhaustion — the ONE failure `intern` could already produce, so every
        // caller's error contract is unchanged (1M atoms = pathological input).
        if (idx >= MAX_SEGS * SEG_SIZE) return error.OutOfMemory;
        const owned = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(owned);
        const si = idx >> SEG_BITS;
        if (self.segments[si] == null) {
            self.segments[si] = try self.gpa.create(Segment);
        }
        self.segments[si].?[idx & (SEG_SIZE - 1)] = owned;
        try self.lookup.put(self.gpa, owned, @intCast(idx));
        self.n_atoms.store(idx + 1, .release); // publish AFTER the slot write
        return @intCast(idx);
    }

    /// Observation: the name an index denotes — LOCK-FREE (see the struct doc:
    /// slot-before-count publication; the name bytes themselves are immutable
    /// once interned). Index validity is a table invariant (indices only come
    /// from intern), so out-of-range is a bug.
    pub fn nameOf(self: *const AtomTable, idx: AtomIdx) []const u8 {
        std.debug.assert(idx < self.n_atoms.load(.acquire));
        return self.segments[idx >> SEG_BITS].?[idx & (SEG_SIZE - 1)];
    }

    pub fn count(self: *const AtomTable) usize {
        return self.n_atoms.load(.acquire);
    }
};

// ---------------------------------------------------------------------------
// Law suite
// ---------------------------------------------------------------------------

fn randomName(random: std.Random, buf: []u8) []const u8 {
    const len = 1 + random.uintLessThan(usize, buf.len);
    for (buf[0..len]) |*b| b.* = 'a' + random.uintLessThan(u8, 26);
    return buf[0..len];
}

test "Laws: intern round-trip and idempotence over random names" {
    var tab = AtomTable.init(std.testing.allocator);
    defer tab.deinit();
    var prng = std.Random.DefaultPrng.init(0xA70);
    const random = prng.random();

    for (0..300) |_| {
        var buf: [8]u8 = undefined;
        const name = randomName(random, &buf);
        const idx_a = try tab.intern(name);
        const idx_b = try tab.intern(name);
        try std.testing.expectEqual(idx_a, idx_b); // idempotence
        try std.testing.expect(std.mem.eql(u8, tab.nameOf(idx_a), name)); // round-trip
    }
}

test "Laws: injectivity — distinct names get distinct indices" {
    var tab = AtomTable.init(std.testing.allocator);
    defer tab.deinit();
    var prng = std.Random.DefaultPrng.init(0xA71);
    const random = prng.random();

    for (0..300) |_| {
        var b1: [8]u8 = undefined;
        var b2: [8]u8 = undefined;
        const n1 = randomName(random, &b1);
        const n2 = randomName(random, &b2);
        const idx_a = try tab.intern(n1);
        const idx_b = try tab.intern(n2);
        try std.testing.expectEqual(std.mem.eql(u8, n1, n2), idx_a == idx_b);
    }
}
