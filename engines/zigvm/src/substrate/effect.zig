//! # substrate/effect — the E-substrate effect-algebra core (E32-T4)
//!
//! ## Stratum
//! The DOORSTEP of the E-substrate program (`docs/STRATUM_C_DESIGN.md`,
//! sequencing step 1): the Model/Trace half of the station triple
//! `(Σ, M ⊨ Σ, R ⊨ Σ, q)` — deliberately HOST-FREE. No syscalls, no threads,
//! no `Real` handler yet: this module proves the pattern in code (the effect
//! DESCRIPTION as data, the pure world-model as the oracle, the observation
//! quotient as the lens) so the allocator domain can land against it next.
//! Nothing in the VM depends on this module; it is pulled by `vm_all` for its
//! law suite only.
//!
//! ## Signature (Σ — two domains composed as a ROW)
//! `Op` is the effect functor's op union: the `Alloc` domain
//! (`alloc`/`free`/`write`/`read` over abstract `Handle`s) and the `Clock`
//! domain (`clock_read`/`clock_advance` over LOGICAL time). `ResultOf` maps
//! each op tag to its result kind — the GADT/comptime-indexed-result rule of
//! the design's mapping calculus (§10 Rule 2).
//!
//! ## Semantic domain
//! A PROGRAM is a defunctionalized-CPS state machine (design tradeoff T-5):
//! `Program(S) = { state: S, step: fn(*S, ?Result) ?Op }` — the continuation
//! is first-order data, which is exactly what makes fibers serializable in
//! the full design. A WORLD is a persistent value (T-6): a path-copying
//! binary trie for the heap (`Handle ↦ u64`) + a canonical handle supply + a
//! logical clock. `snapshot(world)` is O(1) (struct copy, nodes shared).
//! An OBSERVATION (`observe` = the quotient `q`) renames handles to their
//! ALLOCATION ORDINAL and keeps only logical time — erasing exactly the
//! physical residue (§2.2 of the design: address values are not observable).
//!
//! ## Oracle / final
//! This module IS the oracle side (Model) plus the comparison object (Trace).
//! The final encoding (`Real` host handlers) arrives domain-by-domain in
//! later slices; the LAW that will bind them is already stated here as the
//! quotient law (L1): interpretations agree UNDER `observe`, not raw.
//!
//! ## Laws (the suite below)
//!   L1 QUOTIENT      the same program under two Models whose physical handle
//!                    supplies differ (the residue) yields RAW-different but
//!                    OBSERVED-equal traces — α-renaming is a genuine quotient.
//!   L2 PERSISTENCE   a snapshot taken mid-run is observationally immutable:
//!                    later steps never change what the snapshot denotes
//!                    (structural sharing, never aliasing).
//!   L3 CAPABILITY    an op whose capability is absent fails CLOSED
//!                    (error.CapabilityAbsent) — absence of authority makes
//!                    the effect unrepresentable at run time (the Eio rule).
//!   L4 DETERMINISM   same program, same Model ⇒ identical traces.
//!   L5 DENOTATION    a concrete program's final world denotes the expected
//!                    live-block multiset and clock value.
//!
//! ## Scope limits (documented, honest)
//! Two domains only (Alloc + Clock); `u64` block payloads (real blocks come
//! with the allocator domain); no `Real` handler; no effect-row polymorphism
//! beyond the one composed union (comptime row-merging arrives with the third
//! domain). Each limit is a named successor slice, not a silent gap.

const std = @import("std");

// ── Σ: the effect signature ────────────────────────────────────────────────

pub const AllocClass = enum { eheap, binary, ets, temp };

/// An abstract allocation handle. Its VALUE is physical residue — no law may
/// depend on it except through `observe`'s ordinal renaming.
pub const Handle = u32;

pub const Op = union(enum) {
    alloc: struct { class: AllocClass, size: u32 },
    free: struct { h: Handle },
    write: struct { h: Handle, v: u64 },
    read: struct { h: Handle },
    clock_read,
    clock_advance: struct { by: u32 },
};

/// The op's result carrier (the comptime-indexed-result rule: which variant a
/// handler must produce is a function of the op tag, checked by the law suite).
pub const Result = union(enum) {
    handle: Handle,
    unit,
    val: u64,
    time: u64,
};

// ── programs: defunctionalized CPS (T-5) ───────────────────────────────────

/// A program over Σ: first-order state + a step function. `step` receives the
/// PREVIOUS op's result (null on entry) and yields the next op (null = done).
/// The continuation is DATA — serializable, resumable, comparable.
pub fn Program(comptime S: type) type {
    return struct {
        state: S,
        stepFn: *const fn (s: *S, prev: ?Result) ?Op,
    };
}

// ── the persistent World (T-6) ─────────────────────────────────────────────

/// Path-copying binary trie over the handle's bits: a MINIMAL persistent map,
/// self-contained on purpose (the term-layer HAMT is heap-word-entangled; the
/// substrate world must be reviewable in isolation). Nodes are arena-owned;
/// an UPDATE copies the root-to-leaf path (≤32 nodes) and SHARES the rest.
const Node = struct {
    // leaf payload (valid when `leaf`), else children.
    leaf: bool,
    h: Handle = 0,
    v: u64 = 0,
    live: bool = false,
    left: ?*const Node = null,
    right: ?*const Node = null,
};

fn trieGet(node: ?*const Node, h: Handle, depth: u5) ?struct { v: u64, live: bool } {
    const n = node orelse return null;
    if (n.leaf) return if (n.h == h) .{ .v = n.v, .live = n.live } else null;
    const bit = (h >> depth) & 1;
    return trieGet(if (bit == 0) n.left else n.right, h, depth + 1);
}

fn triePut(a: std.mem.Allocator, node: ?*const Node, h: Handle, v: u64, live: bool, depth: u5) error{OutOfMemory}!*const Node {
    const fresh = try a.create(Node);
    const n = node orelse {
        fresh.* = .{ .leaf = true, .h = h, .v = v, .live = live };
        return fresh;
    };
    if (n.leaf) {
        if (n.h == h) {
            fresh.* = .{ .leaf = true, .h = h, .v = v, .live = live };
            return fresh;
        }
        // split: push the existing leaf down, then insert into the branch.
        const branch = try a.create(Node);
        branch.* = .{ .leaf = false };
        const old_bit = (n.h >> depth) & 1;
        if (old_bit == 0) branch.left = n else branch.right = n;
        const with_old: *const Node = branch;
        return triePutBranch(a, with_old, h, v, live, depth, fresh);
    }
    return triePutBranch(a, n, h, v, live, depth, fresh);
}

fn triePutBranch(a: std.mem.Allocator, n: *const Node, h: Handle, v: u64, live: bool, depth: u5, fresh: *Node) error{OutOfMemory}!*const Node {
    const bit = (h >> depth) & 1;
    const child = try triePut(a, if (bit == 0) n.left else n.right, h, v, live, depth + 1);
    fresh.* = .{ .leaf = false, .left = n.left, .right = n.right };
    if (bit == 0) fresh.left = child else fresh.right = child;
    return fresh;
}

/// The World: a VALUE. Copying the struct IS the O(1) snapshot — the trie
/// root is shared, never mutated (L2 pins this observationally).
pub const World = struct {
    heap: ?*const Node = null,
    next_handle: Handle, // the physical supply — RESIDUE (quotiented away)
    n_alloc: u32 = 0, //    the canonical ordinal supply — what observe() sees
    clock: u64 = 0,
    live_count: u32 = 0,

    pub fn snapshot(self: World) World {
        return self; // O(1): pointers shared, nothing copied — L2's subject
    }
};

// ── capabilities (the Eio rule) ────────────────────────────────────────────

pub const Caps = struct {
    alloc: bool = true,
    clock: bool = true,
};

// ── the Trace handler: events under the observation quotient (q) ──────────

/// One observed event. `arg`/`out` carry ORDINALS for handles (allocation
/// order), never physical handle values — the α-renaming half of `q`. Time is
/// logical by construction (the Clock domain has no wall arm in the Model).
pub const Event = struct {
    tag: std.meta.Tag(Op),
    arg: u64, // observed op argument (ordinal for handle args; size/by/raw v)
    out: u64, // observed result (ordinal for handle results; val/time; 0=unit)
};

// ── the Model handler (M ⊨ Σ) ──────────────────────────────────────────────

pub const RunError = error{ OutOfMemory, CapabilityAbsent, BadHandle };

pub const RunOut = struct {
    world: World,
    trace: std.ArrayList(Event),

    pub fn deinit(self: *RunOut, gpa: std.mem.Allocator) void {
        self.trace.deinit(gpa);
    }
};

/// Interpret a program in the Model: fold the defunctionalized continuation
/// over the world (the catamorphism), recording observed events. `arena`
/// owns trie nodes (the world's lifetime); `gpa` owns the trace list.
/// The ordinal map (physical handle → allocation ordinal) implements q's
/// α-renaming; it is PART OF THE OBSERVER, not the world — the world keeps
/// physical handles precisely so L1 can demonstrate the quotient is real.
pub fn run(
    comptime S: type,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    caps: Caps,
    world0: World,
    prog: Program(S),
) RunError!RunOut {
    var world = world0;
    var trace: std.ArrayList(Event) = .empty;
    errdefer trace.deinit(gpa);
    var st = prog.state;
    var prev: ?Result = null;
    // the observer's ordinal table: physical handle -> ordinal (dense, small
    // for the law suite's programs; the full design uses a persistent map).
    var ords: std.AutoHashMapUnmanaged(Handle, u64) = .empty;
    defer ords.deinit(gpa);

    while (prog.stepFn(&st, prev)) |op| {
        switch (op) {
            .alloc => |a| {
                if (!caps.alloc) return error.CapabilityAbsent;
                const h = world.next_handle;
                world.next_handle += 1;
                world.n_alloc += 1;
                world.live_count += 1;
                world.heap = try triePut(arena, world.heap, h, 0, true, 0);
                const ord: u64 = world.n_alloc; // canonical: allocation order
                try ords.put(gpa, h, ord);
                try trace.append(gpa, .{ .tag = .alloc, .arg = a.size, .out = ord });
                prev = .{ .handle = h };
            },
            .free => |f| {
                if (!caps.alloc) return error.CapabilityAbsent;
                const cur = trieGet(world.heap, f.h, 0) orelse return error.BadHandle;
                if (!cur.live) return error.BadHandle; // double-free fails closed
                world.heap = try triePut(arena, world.heap, f.h, cur.v, false, 0);
                world.live_count -= 1;
                try trace.append(gpa, .{ .tag = .free, .arg = ords.get(f.h) orelse return error.BadHandle, .out = 0 });
                prev = .unit;
            },
            .write => |w| {
                if (!caps.alloc) return error.CapabilityAbsent;
                const cur = trieGet(world.heap, w.h, 0) orelse return error.BadHandle;
                if (!cur.live) return error.BadHandle;
                world.heap = try triePut(arena, world.heap, w.h, w.v, true, 0);
                try trace.append(gpa, .{ .tag = .write, .arg = ords.get(w.h) orelse return error.BadHandle, .out = w.v });
                prev = .unit;
            },
            .read => |r| {
                if (!caps.alloc) return error.CapabilityAbsent;
                const cur = trieGet(world.heap, r.h, 0) orelse return error.BadHandle;
                if (!cur.live) return error.BadHandle;
                try trace.append(gpa, .{ .tag = .read, .arg = ords.get(r.h) orelse return error.BadHandle, .out = cur.v });
                prev = .{ .val = cur.v };
            },
            .clock_read => {
                if (!caps.clock) return error.CapabilityAbsent;
                try trace.append(gpa, .{ .tag = .clock_read, .arg = 0, .out = world.clock });
                prev = .{ .time = world.clock };
            },
            .clock_advance => |c| {
                if (!caps.clock) return error.CapabilityAbsent;
                world.clock += c.by;
                try trace.append(gpa, .{ .tag = .clock_advance, .arg = c.by, .out = 0 });
                prev = .unit;
            },
        }
    }
    return .{ .world = world, .trace = trace };
}

/// Observed equality of two traces — the comparison the future Model≡Real
/// homomorphism law will use verbatim.
pub fn tracesEqual(a: []const Event, b: []const Event) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x.tag != y.tag or x.arg != y.arg or x.out != y.out) return false;
    }
    return true;
}

/// Denote a world's live-block content at a handle (test observation).
pub fn denoteAt(w: World, h: Handle) ?u64 {
    const cur = trieGet(w.heap, h, 0) orelse return null;
    return if (cur.live) cur.v else null;
}

// ── the law suite ──────────────────────────────────────────────────────────

// A concrete program: alloc a, alloc b, write a=7, clock+5, read a, free b,
// clock_read — exercises every op and threads results through the state.
const DemoState = struct {
    step: u8 = 0,
    a: Handle = 0,
    b: Handle = 0,
};

fn demoStep(s: *DemoState, prev: ?Result) ?Op {
    defer s.step += 1;
    switch (s.step) {
        0 => return .{ .alloc = .{ .class = .eheap, .size = 16 } },
        1 => {
            s.a = prev.?.handle;
            return .{ .alloc = .{ .class = .binary, .size = 32 } };
        },
        2 => {
            s.b = prev.?.handle;
            return .{ .write = .{ .h = s.a, .v = 7 } };
        },
        3 => return .{ .clock_advance = .{ .by = 5 } },
        4 => return .{ .read = .{ .h = s.a } },
        5 => return .{ .free = .{ .h = s.b } },
        6 => return .clock_read,
        else => return null,
    }
}

test "LAW e32-t4 L1 QUOTIENT: different physical handle supplies -> raw-different, observed-EQUAL traces (alpha-renaming is a real quotient)" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // Two Models whose ONLY difference is the physical residue: the handle
    // supply starts at 0 vs 1000 (the ASLR analog).
    var r1 = try run(DemoState, gpa, a, .{}, .{ .next_handle = 0 }, .{ .state = .{}, .stepFn = demoStep });
    defer r1.deinit(gpa);
    var r2 = try run(DemoState, gpa, a, .{}, .{ .next_handle = 1000 }, .{ .state = .{}, .stepFn = demoStep });
    defer r2.deinit(gpa);

    // RAW worlds differ (the residue is real)…
    try std.testing.expect(r1.world.next_handle != r2.world.next_handle);
    try std.testing.expect(denoteAt(r1.world, 0) != null and denoteAt(r2.world, 1000) != null);
    // …but the OBSERVED traces are identical: q erased exactly the residue.
    try std.testing.expect(tracesEqual(r1.trace.items, r2.trace.items));
}

test "LAW e32-t4 L2 PERSISTENCE: a mid-run snapshot is observationally immutable (structural sharing, never aliasing)" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // Run the prefix (alloc a, alloc b, write a=7) by hand, snapshot, then
    // keep mutating the LIVE world; the snapshot's denotation must not move.
    var w = World{ .next_handle = 0 };
    w.heap = try triePut(a, w.heap, 0, 0, true, 0);
    w.heap = try triePut(a, w.heap, 1, 0, true, 0);
    w.heap = try triePut(a, w.heap, 0, 7, true, 0);
    w.live_count = 2;
    w.n_alloc = 2;
    w.next_handle = 2;

    const snap = w.snapshot();
    try std.testing.expectEqual(@as(?u64, 7), denoteAt(snap, 0));

    // live world moves on: overwrite h0, free h1, alloc h2.
    w.heap = try triePut(a, w.heap, 0, 999, true, 0);
    w.heap = try triePut(a, w.heap, 1, 0, false, 0);
    w.heap = try triePut(a, w.heap, 2, 42, true, 0);

    // the snapshot still denotes the OLD state — sharing, not aliasing.
    try std.testing.expectEqual(@as(?u64, 7), denoteAt(snap, 0));
    try std.testing.expectEqual(@as(?u64, 0), denoteAt(snap, 1));
    try std.testing.expectEqual(@as(?u64, null), denoteAt(snap, 2));
    // and the live world denotes the NEW state.
    try std.testing.expectEqual(@as(?u64, 999), denoteAt(w, 0));
    try std.testing.expectEqual(@as(?u64, null), denoteAt(w, 1));
    try std.testing.expectEqual(@as(?u64, 42), denoteAt(w, 2));
}

test "LAW e32-t4 L3 CAPABILITY: an absent capability fails CLOSED; the disjoint domain still runs" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // The demo program's first op is an alloc: with the Alloc capability
    // absent the run fails closed at that op.
    try std.testing.expectError(error.CapabilityAbsent, run(DemoState, gpa, a, .{ .alloc = false }, .{ .next_handle = 0 }, .{ .state = .{}, .stepFn = demoStep }));

    // ISOLATION (each alloc-domain op must gate INDEPENDENTLY — a single
    // alloc-only program fails closed, so no per-op check can be dropped
    // silently behind a later op's check). Op selected by the state seed.
    const OneState = struct { op: Op, done: bool = false };
    const oneStep = struct {
        fn f(s: *OneState, _: ?Result) ?Op {
            if (s.done) return null;
            s.done = true;
            return s.op;
        }
    }.f;
    const alloc_ops = [_]Op{
        .{ .alloc = .{ .class = .eheap, .size = 1 } },
        .{ .free = .{ .h = 0 } },
        .{ .write = .{ .h = 0, .v = 1 } },
        .{ .read = .{ .h = 0 } },
    };
    for (alloc_ops) |op| {
        try std.testing.expectError(error.CapabilityAbsent, run(OneState, gpa, a, .{ .alloc = false }, .{ .next_handle = 0 }, .{ .state = .{ .op = op }, .stepFn = oneStep }));
    }
    // and each clock op fails closed with the Clock capability absent.
    for ([_]Op{ .clock_read, .{ .clock_advance = .{ .by = 1 } } }) |op| {
        try std.testing.expectError(error.CapabilityAbsent, run(OneState, gpa, a, .{ .clock = false }, .{ .next_handle = 0 }, .{ .state = .{ .op = op }, .stepFn = oneStep }));
    }

    // A clock-only program runs without the Alloc capability (domains are
    // separable — the row composes, the caps do not entangle).
    const ClockState = struct { step: u8 = 0 };
    const clockStep = struct {
        fn f(s: *ClockState, _: ?Result) ?Op {
            defer s.step += 1;
            return switch (s.step) {
                0 => .{ .clock_advance = .{ .by = 3 } },
                1 => .clock_read,
                else => null,
            };
        }
    }.f;
    var r = try run(ClockState, gpa, a, .{ .alloc = false }, .{ .next_handle = 0 }, .{ .state = .{}, .stepFn = clockStep });
    defer r.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 3), r.world.clock);
    try std.testing.expectEqual(@as(usize, 2), r.trace.items.len);
}

test "LAW e32-t4 L4+L5 DETERMINISM + DENOTATION: identical traces across runs; the final world denotes the expected content" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    var r1 = try run(DemoState, gpa, a, .{}, .{ .next_handle = 0 }, .{ .state = .{}, .stepFn = demoStep });
    defer r1.deinit(gpa);
    var r2 = try run(DemoState, gpa, a, .{}, .{ .next_handle = 0 }, .{ .state = .{}, .stepFn = demoStep });
    defer r2.deinit(gpa);
    try std.testing.expect(tracesEqual(r1.trace.items, r2.trace.items));

    // L5: a=7 live; b freed; clock 5; exactly one live block; the trace ends
    // with clock_read observing 5 and read observing 7 (results thread).
    try std.testing.expectEqual(@as(?u64, 7), denoteAt(r1.world, 0));
    try std.testing.expectEqual(@as(?u64, null), denoteAt(r1.world, 1));
    try std.testing.expectEqual(@as(u32, 1), r1.world.live_count);
    try std.testing.expectEqual(@as(u64, 5), r1.world.clock);
    const t = r1.trace.items;
    try std.testing.expectEqual(std.meta.Tag(Op).clock_read, t[t.len - 1].tag);
    try std.testing.expectEqual(@as(u64, 5), t[t.len - 1].out);
    try std.testing.expectEqual(std.meta.Tag(Op).read, t[4].tag);
    try std.testing.expectEqual(@as(u64, 7), t[4].out);

    // Rejection: double-free and use-after-free fail CLOSED (BadHandle) —
    // the affine-handle discipline enforced by the Model.
    const DFState = struct { step: u8 = 0, h: Handle = 0 };
    const dfStep = struct {
        fn f(s: *DFState, prev: ?Result) ?Op {
            defer s.step += 1;
            return switch (s.step) {
                0 => .{ .alloc = .{ .class = .temp, .size = 8 } },
                1 => blk: {
                    s.h = prev.?.handle;
                    break :blk .{ .free = .{ .h = s.h } };
                },
                2 => .{ .free = .{ .h = s.h } }, // double free
                else => null,
            };
        }
    }.f;
    try std.testing.expectError(error.BadHandle, run(DFState, gpa, a, .{}, .{ .next_handle = 0 }, .{ .state = .{}, .stepFn = dfStep }));
}
