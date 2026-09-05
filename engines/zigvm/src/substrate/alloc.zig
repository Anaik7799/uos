//! # substrate/alloc — Real[Alloc]: the first HOST-touching substrate handler (E33-T1)
//!
//! ## Stratum
//! The FINAL encoding of the `Alloc` domain — the first `Real` handler of the
//! E-substrate program (`docs/STRATUM_C_DESIGN.md` §11.1/§13.1/§14 T-1). Unlike
//! the `effect.zig` Model (a pure persistent trie), this handler touches REAL
//! host memory: a size-classed slab allocator over a backing `std.mem.Allocator`
//! (the `mmap`-superblock analog), with per-class free-lists (the MBC free-list),
//! block payloads stored in and loaded from actual memory. Nothing in the VM
//! depends on it; `vm_all` pulls it for its law suite.
//!
//! ## What it proves (the substrate program's proof-of-concept)
//! The homomorphism the whole design rests on: `observe(Real.run(p)) ==
//! observe(Model.run(p))` for every program `p` (`effect.zig` L1 QUOTIENT, now
//! discharged for a REAL host kernel). The Real handler's physical residue — real
//! addresses, carrier layout, free-list order — is erased by the SAME observation
//! (handle → allocation ordinal); a real allocator and a pure trie are OBSERVED
//! -identical. This is where a syscall-shaped kernel meets a law for the first time.
//!
//! ## Structure (T-1, carrier-exact + strategy-monomorphized)
//!   - `size_classes`: power-of-two buckets (the erts `+M` size-class analog).
//!   - `Carrier`: a real backing region for one class, carved into fixed blocks
//!     (the multi-block carrier); grown from the backing allocator on demand.
//!   - `Block`: {class, offset} — a handle names a block INDEX (the residue).
//!   - `Strategy`: a comptime functor parameter picking a reuse slot from the
//!     free-list. `FirstFit`/`BestFit` here differ ONLY in reuse ORDER — which is
//!     invisible under `observe` (the STRATEGY-INVARIANCE law below), the exact
//!     correctness justification for monomorphizing the strategy (design T-1).
//!
//! ## Laws
//!   HOMOMORPHISM   `observe(Real.run(p)) == observe(Model.run(p))` — the Real
//!                  host kernel is observed-identical to the pure oracle, over a
//!                  seeded program family (discharges effect.zig L1 for Real).
//!   STRATEGY-INV   `observe(Real[FirstFit].run(p)) == observe(Real[BestFit]
//!                  .run(p))` — reuse strategy is quotiented away; the T-1
//!                  monomorphization changes performance, never observation.
//!   ROUND-TRIP     a real read after a real write returns the stored value
//!                  (genuine host memory, not the Model's value) — and a freed
//!                  block's slot is REUSED (the free-list works; carriers do not
//!                  grow unboundedly under alloc/free churn).
//!   AFFINE         double-free / use-after-free / read-of-dead fail CLOSED
//!                  (BadHandle) — the same affine discipline as the Model.
//!
//! ## Scope limits (documented, honest)
//! One allocator instance, one `class → carrier` policy, LIFO/FIFO strategy
//! stand-ins (real goodfit/bestfit/aoff arrive with per-block coalescing); no
//! abandoned-carrier pool, no NUMA placement, no per-scheduler instances — each a
//! NAMED successor slice (§13.1). The point of THIS slice is the homomorphism,
//! not the allocator's peak throughput.

const std = @import("std");
const eff = @import("effect.zig");

pub const Handle = eff.Handle;
pub const Op = eff.Op;
pub const Result = eff.Result;
pub const Event = eff.Event;
pub const Caps = eff.Caps;
pub const Program = eff.Program;

const size_classes = [_]u32{ 16, 32, 64, 128, 256, 512, 1024, 2048 };

fn classOf(size: u32) usize {
    for (size_classes, 0..) |sc, i| {
        if (size <= sc) return i;
    }
    return size_classes.len - 1; // clamp: oversized requests take the top class
}

// ── strategies (the comptime functor parameter, T-1) ───────────────────────

/// LIFO reuse: pop the most-recently-freed slot (the erts goodfit hot-path
/// analog — best cache locality).
pub const FirstFit = struct {
    pub fn pick(free: *std.ArrayList(u32)) ?u32 {
        return free.pop();
    }
};

/// FIFO reuse: take the oldest-freed slot (a bestfit/aoff stand-in — different
/// physical choice, IDENTICAL observation, which STRATEGY-INV proves).
pub const BestFit = struct {
    pub fn pick(free: *std.ArrayList(u32)) ?u32 {
        if (free.items.len == 0) return null;
        return free.orderedRemove(0);
    }
};

// ── the allocator (Real[Alloc]) ────────────────────────────────────────────

const Block = struct { class: u8, offset: u32, live: bool };

pub const RealError = error{ OutOfMemory, CapabilityAbsent, BadHandle };

pub fn Allctr(comptime Strategy: type) type {
    return struct {
        const Self = @This();
        gpa: std.mem.Allocator,
        // per-class REAL backing carriers (the MBCs) — block payloads live here.
        carriers: [size_classes.len]std.ArrayList(u8) = @splat(.empty),
        // per-class free-lists of reusable block indices (the MBC free-list).
        free: [size_classes.len]std.ArrayList(u32) = @splat(.empty),
        // block descriptors — a handle is an index into this (the residue).
        blocks: std.ArrayList(Block) = .empty,
        live_count: u32 = 0,
        carrier_bytes: usize = 0, // total real memory carved (the ROUND-TRIP no-leak subject)

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{ .gpa = gpa };
        }
        pub fn deinit(self: *Self) void {
            for (&self.carriers) |*c| c.deinit(self.gpa);
            for (&self.free) |*f| f.deinit(self.gpa);
            self.blocks.deinit(self.gpa);
        }

        pub fn alloc(self: *Self, size: u32) RealError!Handle {
            const cls = classOf(size);
            if (Strategy.pick(&self.free[cls])) |reused| {
                const b = &self.blocks.items[reused];
                b.live = true;
                // Zero the reused block's payload: the Model's oracle denotes a
                // FRESH block as 0, so Real must too for the HOMOMORPHISM to hold
                // over read-before-write (erts leaves it undefined — reading it
                // is a program bug; pinning it to 0 matches the pure oracle and
                // is the honest reconciliation, not a divergence FROM real BEAM).
                @memset(self.carriers[b.class].items[b.offset..][0..8], 0);
                self.live_count += 1;
                return reused;
            }
            // carve a fresh block from the carrier (grow it — the mmap analog).
            const off: u32 = @intCast(self.carriers[cls].items.len);
            try self.carriers[cls].appendNTimes(self.gpa, 0, size_classes[cls]);
            self.carrier_bytes += size_classes[cls];
            const h: Handle = @intCast(self.blocks.items.len);
            try self.blocks.append(self.gpa, .{ .class = @intCast(cls), .offset = off, .live = true });
            self.live_count += 1;
            return h;
        }
        pub fn liveBlock(self: *Self, h: Handle) RealError!*Block {
            if (h >= self.blocks.items.len) return error.BadHandle;
            const b = &self.blocks.items[h];
            if (!b.live) return error.BadHandle; // use-after-free / double-free
            return b;
        }
        pub fn free_(self: *Self, h: Handle) RealError!void {
            const b = try self.liveBlock(h);
            b.live = false;
            self.live_count -= 1;
            try self.free[b.class].append(self.gpa, h);
        }
        pub fn write(self: *Self, h: Handle, v: u64) RealError!void {
            const b = try self.liveBlock(h);
            const bytes = self.carriers[b.class].items[b.offset..][0..8];
            std.mem.writeInt(u64, bytes, v, .little); // REAL host store
        }
        pub fn read(self: *Self, h: Handle) RealError!u64 {
            const b = try self.liveBlock(h);
            const bytes = self.carriers[b.class].items[b.offset..][0..8];
            return std.mem.readInt(u64, bytes, .little); // REAL host load
        }
    };
}

pub const RealRunOut = struct {
    trace: std.ArrayList(Event),
    live_count: u32,
    carrier_bytes: usize,
    pub fn deinit(self: *RealRunOut, gpa: std.mem.Allocator) void {
        self.trace.deinit(gpa);
    }
};

/// Interpret a program through the REAL allocator, recording the SAME observed
/// trace shape the Model produces (`effect.Event`, handle → allocation ordinal).
/// The Clock domain is modeled locally (a logical counter) — this handler owns
/// the Alloc domain; the row composes.
pub fn runReal(
    comptime S: type,
    comptime Strategy: type,
    gpa: std.mem.Allocator,
    caps: Caps,
    prog: Program(S),
) RealError!RealRunOut {
    var alc = Allctr(Strategy).init(gpa);
    defer alc.deinit();
    var trace: std.ArrayList(Event) = .empty;
    errdefer trace.deinit(gpa);
    var ords: std.AutoHashMapUnmanaged(Handle, u64) = .empty;
    defer ords.deinit(gpa);
    var n_alloc: u64 = 0;
    var clock: u64 = 0;
    var st = prog.state;
    var prev: ?Result = null;

    while (prog.stepFn(&st, prev)) |op| {
        switch (op) {
            .alloc => |a| {
                if (!caps.alloc) return error.CapabilityAbsent;
                const h = try alc.alloc(a.size);
                n_alloc += 1;
                try ords.put(gpa, h, n_alloc);
                try trace.append(gpa, .{ .tag = .alloc, .arg = a.size, .out = n_alloc });
                prev = .{ .handle = h };
            },
            .free => |f| {
                if (!caps.alloc) return error.CapabilityAbsent;
                const ord = ords.get(f.h) orelse return error.BadHandle;
                try alc.free_(f.h);
                try trace.append(gpa, .{ .tag = .free, .arg = ord, .out = 0 });
                prev = .unit;
            },
            .write => |w| {
                if (!caps.alloc) return error.CapabilityAbsent;
                try alc.write(w.h, w.v);
                try trace.append(gpa, .{ .tag = .write, .arg = ords.get(w.h) orelse return error.BadHandle, .out = w.v });
                prev = .unit;
            },
            .read => |r| {
                if (!caps.alloc) return error.CapabilityAbsent;
                const v = try alc.read(r.h);
                try trace.append(gpa, .{ .tag = .read, .arg = ords.get(r.h) orelse return error.BadHandle, .out = v });
                prev = .{ .val = v };
            },
            .clock_read => {
                if (!caps.clock) return error.CapabilityAbsent;
                try trace.append(gpa, .{ .tag = .clock_read, .arg = 0, .out = clock });
                prev = .{ .time = clock };
            },
            .clock_advance => |c| {
                if (!caps.clock) return error.CapabilityAbsent;
                clock += c.by;
                try trace.append(gpa, .{ .tag = .clock_advance, .arg = c.by, .out = 0 });
                prev = .unit;
            },
        }
    }
    return .{ .trace = trace, .live_count = alc.live_count, .carrier_bytes = alc.carrier_bytes };
}

// ── the law suite ──────────────────────────────────────────────────────────

// A seeded program generator over the Σ ops: alloc/write/read/free churn with a
// small live set + clock ticks. State carries the live handles so free/read/
// write target REAL live blocks (never a dangling handle — those are the AFFINE
// law's job, exercised separately).
const GenState = struct {
    prng: std.Random.DefaultPrng,
    live: [8]Handle = undefined,
    n_live: usize = 0,
    steps_left: u32,
    pending: ?enum { free, read } = null, // set after an alloc records its handle
    pending_idx: usize = 0,
};

fn genStep(s: *GenState, prev: ?Result) ?Op {
    // capture a just-allocated handle into the live set.
    if (prev) |p| switch (p) {
        .handle => |h| {
            if (s.n_live < s.live.len) {
                s.live[s.n_live] = h;
                s.n_live += 1;
            }
        },
        else => {},
    };
    if (s.steps_left == 0) return null;
    s.steps_left -= 1;
    const r = s.prng.random();
    // bias toward alloc when small so a live set exists to act on.
    const choice = if (s.n_live == 0) @as(u8, 0) else r.uintLessThan(u8, 5);
    switch (choice) {
        0 => return .{ .alloc = .{ .class = .eheap, .size = 1 + r.uintLessThan(u32, 2048) } },
        1 => {
            const i = r.uintLessThan(usize, s.n_live);
            return .{ .write = .{ .h = s.live[i], .v = r.int(u64) } };
        },
        2 => {
            const i = r.uintLessThan(usize, s.n_live);
            return .{ .read = .{ .h = s.live[i] } };
        },
        3 => {
            // free a live handle and remove it from the set (swap-remove).
            const i = r.uintLessThan(usize, s.n_live);
            const h = s.live[i];
            s.live[i] = s.live[s.n_live - 1];
            s.n_live -= 1;
            return .{ .free = .{ .h = h } };
        },
        else => return .{ .clock_advance = .{ .by = 1 + r.uintLessThan(u32, 7) } },
    }
}

fn seededProg(seed: u64, steps: u32) Program(GenState) {
    return .{ .state = .{ .prng = std.Random.DefaultPrng.init(seed), .steps_left = steps }, .stepFn = genStep };
}

test "LAW e33-t1 HOMOMORPHISM: observe(Real[FirstFit]) == observe(Model) over a seeded program family (L1 for a REAL host kernel)" {
    const gpa = std.testing.allocator;
    var seed: u64 = 0;
    while (seed < 64) : (seed += 1) {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        var mr = try eff.run(GenState, gpa, arena.allocator(), .{}, .{ .next_handle = 0 }, seededProg(seed, 200));
        defer mr.deinit(gpa);
        var rr = try runReal(GenState, FirstFit, gpa, .{}, seededProg(seed, 200));
        defer rr.deinit(gpa);
        // the pure oracle and the real host allocator produce IDENTICAL observed
        // traces — the residue (addresses, carrier layout) erased by observe.
        try std.testing.expect(eff.tracesEqual(mr.trace.items, rr.trace.items));
        try std.testing.expectEqual(mr.world.live_count, rr.live_count);
    }
}

test "LAW e33-t1 STRATEGY-INV: observe(Real[FirstFit]) == observe(Real[BestFit]) — reuse strategy is quotiented away" {
    const gpa = std.testing.allocator;
    var seed: u64 = 100;
    while (seed < 148) : (seed += 1) {
        var r1 = try runReal(GenState, FirstFit, gpa, .{}, seededProg(seed, 200));
        defer r1.deinit(gpa);
        var r2 = try runReal(GenState, BestFit, gpa, .{}, seededProg(seed, 200));
        defer r2.deinit(gpa);
        // two DIFFERENT physical reuse policies — observed identically. This is
        // the correctness justification for monomorphizing the strategy (T-1).
        try std.testing.expect(eff.tracesEqual(r1.trace.items, r2.trace.items));
    }
}

test "LAW e33-t1 ROUND-TRIP: real read-after-write returns the stored value; freed slots are REUSED (no carrier leak under churn)" {
    const gpa = std.testing.allocator;
    var alc = Allctr(FirstFit).init(gpa);
    defer alc.deinit();

    // real host round-trip through actual memory.
    const h = try alc.alloc(64);
    try alc.write(h, 0xDEADBEEFCAFEF00D);
    try std.testing.expectEqual(@as(u64, 0xDEADBEEFCAFEF00D), try alc.read(h));

    // free/re-alloc churn in one class must REUSE the slot — carriers bounded.
    try alc.free_(h);
    const bytes_after_one = alc.carrier_bytes;
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const g = try alc.alloc(64); // same class → the free-list serves it
        try alc.free_(g);
    }
    // 1000 alloc/free of the same class grew the carrier by ZERO (all reused).
    try std.testing.expectEqual(bytes_after_one, alc.carrier_bytes);
    try std.testing.expectEqual(@as(u32, 0), alc.live_count);
}

test "LAW e33-t1 AFFINE: double-free / use-after-free / read-of-dead fail CLOSED (BadHandle)" {
    const gpa = std.testing.allocator;
    var alc = Allctr(FirstFit).init(gpa);
    defer alc.deinit();
    const h = try alc.alloc(16);
    try alc.free_(h);
    try std.testing.expectError(error.BadHandle, alc.free_(h)); // double free
    try std.testing.expectError(error.BadHandle, alc.write(h, 1)); // use-after-free
    try std.testing.expectError(error.BadHandle, alc.read(h)); // read-of-dead
    try std.testing.expectError(error.BadHandle, alc.liveBlock(9999)); // out of range

    // capability fail-closed carries over from the Model (row-composed).
    const OneState = struct { done: bool = false };
    const oneStep = struct {
        fn f(s: *OneState, _: ?Result) ?Op {
            if (s.done) return null;
            s.done = true;
            return .{ .alloc = .{ .class = .eheap, .size = 8 } };
        }
    }.f;
    try std.testing.expectError(error.CapabilityAbsent, runReal(OneState, FirstFit, gpa, .{ .alloc = false }, .{ .state = .{}, .stepFn = oneStep }));
}
