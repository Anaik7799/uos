//! # substrate/row — the E-substrate effect ROW: Alloc + IO + Clock composed (E36-T2)
//!
//! ## Stratum
//! The COMPOSITION step of the E-substrate program (`docs/STRATUM_C_DESIGN.md` §2
//! extensible effects / effect rows). The three landed domains — memory
//! (`effect.zig`/`alloc.zig`), I/O (`reactor.zig`), and the logical clock — were
//! each proven INDIVIDUALLY observed-identical to a pure oracle under `effect.zig`
//! L1. This module proves they COMPOSE: a single program that interleaves ops from
//! all three domains is interpreted by ONE handler that peels one effect at a time,
//! and the observation of the combined run, PROJECTED onto each domain, equals that
//! domain's run in isolation. Nothing in the VM depends on it; `vm_all` pulls it for
//! its law suite only.
//!
//! ## What it proves (the "domains compose, not just coexist" milestone)
//! The effect row is a COPRODUCT of the domain signatures; observation is a PRODUCT
//! of the per-domain observations; and the combined handler is the unique mediating
//! map — i.e. HANDLERS COMMUTE ON DISJOINT EFFECTS. Concretely, for a mixed program
//! `p` and each domain `d`:
//!   `project_d(runRow(p)) == runRow(restrict_d(p))`
//! where `restrict_d` drops every op NOT in domain `d`. Interleaving ops from other
//! domains changes NOTHING about a domain's own observed sub-trace — the disjoint
//! effects do not interfere. This is the precondition for a real Stratum-C VM boot
//! over the effect row (the scheduler runs programs that allocate, do I/O, and read
//! the clock, and each concern is verified in isolation yet runs composed).
//!
//! ## Signature (the row) and semantic domain
//! `RowOp` is the tagged UNION (coproduct) of three disjoint sub-signatures:
//!   mem  : `mem_alloc | mem_touch | mem_free`   (a cell store; `touch` = write+read
//!          the last live cell — self-contained, no cross-op handle threading)
//!   io   : `io_open | io_touch | io_close`       (a file store; `touch` = append+read)
//!   clock: `clock_tick`                          (advance the logical clock)
//! Each `touch`/`free`/`close` targets the LAST live resource in ITS OWN domain, so
//! `restrict_d(p)` is always well-formed (a domain's internal references survive the
//! removal of other domains' ops). The handler tracks per-domain state; `observe`
//! renames resources to their per-domain allocation ORDINAL (the same quotient the
//! individual domains use).
//!
//! ## Laws
//!   COMPOSITION   `project_d(runRow(p)) == runRow(restrict_d(p))` for every domain
//!                 d, over a seeded mixed-program family — handlers commute on
//!                 disjoint effects (the milestone).
//!   CAPABILITY    the row's capability set is the PRODUCT: a program touching a
//!                 domain whose capability is absent fails CLOSED; a domain whose
//!                 capability is present runs regardless of the others (the caps do
//!                 not entangle — the effect.zig L3 rule, lifted to the row).
//!   ORDER         the combined trace is the interleaving of the per-domain traces
//!                 in program order (a projection is order-preserving) — so the row
//!                 handler adds no reordering of its own.
//!
//! ## Scope limits (documented, honest)
//! THREE single-actor domains (mem/io/clock); `Sched` is the META-level handler that
//! RUNS such programs (multi-actor — not a single-program effect, so not a row
//! member; `Real[Sched]` in `sched.zig` is exactly that runner). The comptime
//! row-polymorphic generic (an open union parameterised by a type-level effect set)
//! and the real per-domain homomorphism to host kernels are the landed modules'
//! content — this module adds ONLY the composition theorem over them.

const std = @import("std");

// ── the row signature (coproduct of three disjoint sub-signatures) ──────────

pub const Domain = enum { mem, io, clock };

pub const RowOp = union(enum) {
    mem_alloc,
    mem_touch: struct { v: u64 }, // write v to the last live cell, then read it back
    mem_free,
    io_open,
    io_touch: struct { v: u64 }, // append v to the last open file, then read record 0
    io_close,
    clock_tick: struct { by: u32 },

    fn domainOf(self: RowOp) Domain {
        return switch (self) {
            .mem_alloc, .mem_touch, .mem_free => .mem,
            .io_open, .io_touch, .io_close => .io,
            .clock_tick => .clock,
        };
    }
};

pub const RowEvent = struct {
    domain: Domain,
    tag: u8, //  a per-domain op discriminant (stable within a domain)
    ord: u64, // the acting resource's per-domain ordinal (0 for clock)
    val: u64, // the observed value (written/read record; clock delta; 0)
};

pub fn tracesEqual(a: []const RowEvent, b: []const RowEvent) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x.domain != y.domain or x.tag != y.tag or x.ord != y.ord or x.val != y.val) return false;
    }
    return true;
}

pub const Caps = struct { mem: bool = true, io: bool = true, clock: bool = true };

pub const RowError = error{ OutOfMemory, CapabilityAbsent, BadResource };

// ── the unified handler (peels one effect at a time) ────────────────────────

// per-domain minimal state (each domain's own homomorphism to a real kernel is
// proven in its own module; here we only need a faithful per-domain semantics to
// state the COMPOSITION theorem over).
const MemCell = struct { v: u64, live: bool };
const IoFile = struct { recs: std.ArrayList(u64), open: bool };

const RowState = struct {
    gpa: std.mem.Allocator,
    // mem
    cells: std.ArrayList(MemCell) = .empty,
    last_cell: ?usize = null,
    n_alloc: u64 = 0,
    // io
    files: std.ArrayList(IoFile) = .empty,
    last_file: ?usize = null,
    n_open: u64 = 0,
    // clock
    clock: u64 = 0,

    fn deinit(self: *RowState) void {
        for (self.files.items) |*f| f.recs.deinit(self.gpa);
        self.files.deinit(self.gpa);
        self.cells.deinit(self.gpa);
    }
};

pub const RowRunOut = struct {
    trace: std.ArrayList(RowEvent),
    fn deinit(self: *RowRunOut, gpa: std.mem.Allocator) void {
        self.trace.deinit(gpa);
    }
};

// ── per-domain handlers (each a self-contained effect interpreter) ──────────
//
// A DOMAIN is a `(tag, handle)` pair: the tag classifies its ops, `handle`
// interprets one of ITS ops (the dispatcher routes only that domain's ops to it,
// so the `else` arms are unreachable). Adding a fourth domain = write its handler +
// add it to a handler list — the generic dispatcher below is NEVER edited. This is
// the row-POLYMORPHISM the design's open-union (§2) calls for.

pub const HandleFn = *const fn (*RowState, RowOp, Caps, *std.ArrayList(RowEvent), std.mem.Allocator) RowError!void;

pub const DomainHandler = struct { tag: Domain, handle: HandleFn };

fn memHandle(st: *RowState, op: RowOp, caps: Caps, trace: *std.ArrayList(RowEvent), gpa: std.mem.Allocator) RowError!void {
    if (!caps.mem) return error.CapabilityAbsent;
    switch (op) {
        .mem_alloc => {
            const ord = st.n_alloc;
            st.n_alloc += 1;
            try st.cells.append(gpa, .{ .v = 0, .live = true });
            st.last_cell = st.cells.items.len - 1;
            try trace.append(gpa, .{ .domain = .mem, .tag = 0, .ord = ord, .val = 0 });
        },
        .mem_touch => |t| {
            const i = st.last_cell orelse return error.BadResource;
            if (!st.cells.items[i].live) return error.BadResource;
            st.cells.items[i].v = t.v; // write
            const rv = st.cells.items[i].v; // read back
            try trace.append(gpa, .{ .domain = .mem, .tag = 1, .ord = @intCast(i), .val = rv });
        },
        .mem_free => {
            const i = st.last_cell orelse return error.BadResource;
            if (!st.cells.items[i].live) return error.BadResource;
            st.cells.items[i].live = false;
            try trace.append(gpa, .{ .domain = .mem, .tag = 2, .ord = @intCast(i), .val = 0 });
            st.last_cell = null;
        },
        else => unreachable, // the dispatcher routes only mem ops here
    }
}

fn ioHandle(st: *RowState, op: RowOp, caps: Caps, trace: *std.ArrayList(RowEvent), gpa: std.mem.Allocator) RowError!void {
    if (!caps.io) return error.CapabilityAbsent;
    switch (op) {
        .io_open => {
            const ord = st.n_open;
            st.n_open += 1;
            try st.files.append(gpa, .{ .recs = .empty, .open = true });
            st.last_file = st.files.items.len - 1;
            try trace.append(gpa, .{ .domain = .io, .tag = 0, .ord = ord, .val = 0 });
        },
        .io_touch => |t| {
            const i = st.last_file orelse return error.BadResource;
            if (!st.files.items[i].open) return error.BadResource;
            try st.files.items[i].recs.append(gpa, t.v); // append
            const rv = st.files.items[i].recs.items[0]; // read record 0
            try trace.append(gpa, .{ .domain = .io, .tag = 1, .ord = @intCast(i), .val = rv });
        },
        .io_close => {
            const i = st.last_file orelse return error.BadResource;
            if (!st.files.items[i].open) return error.BadResource;
            st.files.items[i].open = false;
            try trace.append(gpa, .{ .domain = .io, .tag = 2, .ord = @intCast(i), .val = 0 });
            st.last_file = null;
        },
        else => unreachable,
    }
}

fn clockHandle(st: *RowState, op: RowOp, caps: Caps, trace: *std.ArrayList(RowEvent), gpa: std.mem.Allocator) RowError!void {
    if (!caps.clock) return error.CapabilityAbsent;
    switch (op) {
        .clock_tick => |c| {
            st.clock += c.by;
            try trace.append(gpa, .{ .domain = .clock, .tag = 0, .ord = 0, .val = st.clock });
        },
        else => unreachable,
    }
}

pub const mem_handler = DomainHandler{ .tag = .mem, .handle = memHandle };
pub const io_handler = DomainHandler{ .tag = .io, .handle = ioHandle };
pub const clock_handler = DomainHandler{ .tag = .clock, .handle = clockHandle };

/// The full row = all three domains.
pub const all_handlers = [_]DomainHandler{ mem_handler, io_handler, clock_handler };

/// The GENERIC row handler (row-polymorphism): parameterised by a comptime set of
/// `DomainHandler`s. Each op is routed to the handler whose `tag` matches its
/// domain; an op whose domain is NOT in `handlers` is SKIPPED (it is not in this
/// row's signature). The dispatcher is written ONCE and never mentions a specific
/// domain — a new domain composes by joining the list. `runRow` instantiates it at
/// the full set. `restrict_d(p)` is a trivial filter, which is what the COMPOSITION
/// law needs; the FUNCTOR law below adds that this holds for ANY domain subset.
pub fn runRowGeneric(comptime handlers: []const DomainHandler, gpa: std.mem.Allocator, caps: Caps, prog: []const RowOp) RowError!RowRunOut {
    var st = RowState{ .gpa = gpa };
    defer st.deinit();
    var trace: std.ArrayList(RowEvent) = .empty;
    errdefer trace.deinit(gpa);

    for (prog) |op| {
        const d = op.domainOf();
        inline for (handlers) |h| {
            if (h.tag == d) {
                try h.handle(&st, op, caps, &trace, gpa);
                break;
            }
        }
        // ops whose domain is not among `handlers` are outside this row's
        // signature and are skipped (the sub-row of a domain subset).
    }
    const owned = trace; // MOVE out (no clone → no leak of the original)
    return .{ .trace = owned };
}

/// Interpret a MATERIALISED row program at the FULL domain set (the E36-T2 handler,
/// now a thin instantiation of the generic dispatcher).
pub fn runRow(gpa: std.mem.Allocator, caps: Caps, prog: []const RowOp) RowError!RowRunOut {
    return runRowGeneric(&all_handlers, gpa, caps, prog);
}

// ── the REAL composition: Real[Alloc] backs the mem domain (E38-T2) ─────────
//
// `runRowReal` interprets the SAME row program, but the MEM domain is driven by
// the REAL slab allocator (`substrate/alloc.zig` — carriers, per-class free-lists,
// the strategy functor, real host-memory block payloads) and the IO domain by a
// real host file store; the CLOCK is a real counter. `observe` renames each
// resource to its per-domain ALLOCATION ORDINAL (handle → alloc-order via an ords
// map, exactly as `alloc.zig`'s `runReal` does — the slab REUSES freed block
// indices, so the raw handle ≠ ordinal, but the observation erases that residue).
// The HOMOMORPHISM law below proves `observe(runRowReal(p)) == observe(runRow(p))`
// — the pure Model row and the row backed by a REAL host allocator denote the same
// composed trace. This is where the composed abstraction meets a real host kernel.
const alloc = @import("alloc.zig");

pub fn runRowReal(gpa: std.mem.Allocator, caps: Caps, prog: []const RowOp) RowError!RowRunOut {
    var alc = alloc.Allctr(alloc.FirstFit).init(gpa);
    defer alc.deinit();
    var ords: std.AutoHashMapUnmanaged(u32, u64) = .empty; // real handle → alloc ordinal
    defer ords.deinit(gpa);
    var n_alloc: u64 = 0;
    var last_handle: ?u32 = null;
    // io: a REAL host file store (record vectors), read-record-0 semantics as in the
    // Model; clock: a real counter.
    var files: std.ArrayList(std.ArrayList(u64)) = .empty;
    var open: std.ArrayList(bool) = .empty;
    defer {
        for (files.items) |*f| f.deinit(gpa);
        files.deinit(gpa);
        open.deinit(gpa);
    }
    var n_open: u64 = 0;
    var last_file: ?usize = null;
    var clock: u64 = 0;
    var trace: std.ArrayList(RowEvent) = .empty;
    errdefer trace.deinit(gpa);

    for (prog) |op| {
        switch (op) {
            .mem_alloc => {
                if (!caps.mem) return error.CapabilityAbsent;
                const h = alc.alloc(8) catch |e| return switch (e) {
                    error.OutOfMemory => error.OutOfMemory,
                    else => error.BadResource,
                };
                const ord = n_alloc;
                n_alloc += 1;
                try ords.put(gpa, h, ord); // reused handle → freshest alloc ordinal
                last_handle = h;
                try trace.append(gpa, .{ .domain = .mem, .tag = 0, .ord = ord, .val = 0 });
            },
            .mem_touch => |t| {
                if (!caps.mem) return error.CapabilityAbsent;
                const h = last_handle orelse return error.BadResource;
                alc.write(h, t.v) catch return error.BadResource; // REAL host store
                const rv = alc.read(h) catch return error.BadResource; // REAL host load
                try trace.append(gpa, .{ .domain = .mem, .tag = 1, .ord = ords.get(h).?, .val = rv });
            },
            .mem_free => {
                if (!caps.mem) return error.CapabilityAbsent;
                const h = last_handle orelse return error.BadResource;
                const ord = ords.get(h).?;
                alc.free_(h) catch return error.BadResource;
                try trace.append(gpa, .{ .domain = .mem, .tag = 2, .ord = ord, .val = 0 });
                last_handle = null;
            },
            .io_open => {
                if (!caps.io) return error.CapabilityAbsent;
                const ord = n_open;
                n_open += 1;
                try files.append(gpa, .empty);
                try open.append(gpa, true);
                last_file = files.items.len - 1;
                try trace.append(gpa, .{ .domain = .io, .tag = 0, .ord = ord, .val = 0 });
            },
            .io_touch => |t| {
                if (!caps.io) return error.CapabilityAbsent;
                const i = last_file orelse return error.BadResource;
                if (!open.items[i]) return error.BadResource;
                try files.items[i].append(gpa, t.v); // REAL append
                const rv = files.items[i].items[0]; // read record 0
                try trace.append(gpa, .{ .domain = .io, .tag = 1, .ord = @intCast(i), .val = rv });
            },
            .io_close => {
                if (!caps.io) return error.CapabilityAbsent;
                const i = last_file orelse return error.BadResource;
                if (!open.items[i]) return error.BadResource;
                open.items[i] = false;
                try trace.append(gpa, .{ .domain = .io, .tag = 2, .ord = @intCast(i), .val = 0 });
                last_file = null;
            },
            .clock_tick => |c| {
                if (!caps.clock) return error.CapabilityAbsent;
                clock += c.by;
                try trace.append(gpa, .{ .domain = .clock, .tag = 0, .ord = 0, .val = clock });
            },
        }
    }
    const owned = trace;
    return .{ .trace = owned };
}

/// The observation PROJECTION onto a domain: keep only that domain's events.
fn projectDomain(gpa: std.mem.Allocator, trace: []const RowEvent, d: Domain) ![]RowEvent {
    var out: std.ArrayList(RowEvent) = .empty;
    errdefer out.deinit(gpa);
    for (trace) |ev| if (ev.domain == d) try out.append(gpa, ev);
    return out.toOwnedSlice(gpa);
}

/// `restrict_d(p)`: the sub-program of ops in domain `d` (program-order preserved).
fn restrictDomain(gpa: std.mem.Allocator, prog: []const RowOp, d: Domain) ![]RowOp {
    var out: std.ArrayList(RowOp) = .empty;
    errdefer out.deinit(gpa);
    for (prog) |op| if (op.domainOf() == d) try out.append(gpa, op);
    return out.toOwnedSlice(gpa);
}

// ── the law suite ──────────────────────────────────────────────────────────

// A seeded generator over the row: emits a mixed op stream across all three
// domains, keeping each domain internally well-formed (touch/free/close target the
// last live resource in that domain; a domain with no live resource gets an alloc/
// open instead of a touch/free/close).
const Gen = struct {
    prng: std.Random.DefaultPrng,
    mem_live: bool = false,
    io_live: bool = false,
};

fn genProg(gpa: std.mem.Allocator, seed: u64, n: u32) ![]RowOp {
    var g = Gen{ .prng = std.Random.DefaultPrng.init(seed) };
    var out: std.ArrayList(RowOp) = .empty;
    errdefer out.deinit(gpa);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const r = g.prng.random();
        switch (r.uintLessThan(u8, 7)) {
            0 => {
                try out.append(gpa, .mem_alloc);
                g.mem_live = true;
            },
            1 => if (g.mem_live) {
                try out.append(gpa, .{ .mem_touch = .{ .v = r.int(u64) } });
            } else {
                try out.append(gpa, .mem_alloc);
                g.mem_live = true;
            },
            2 => if (g.mem_live) {
                try out.append(gpa, .mem_free);
                g.mem_live = false;
            } else try out.append(gpa, .{ .clock_tick = .{ .by = 1 } }),
            3 => {
                try out.append(gpa, .io_open);
                g.io_live = true;
            },
            4 => if (g.io_live) {
                try out.append(gpa, .{ .io_touch = .{ .v = r.int(u64) } });
            } else {
                try out.append(gpa, .io_open);
                g.io_live = true;
            },
            5 => if (g.io_live) {
                try out.append(gpa, .io_close);
                g.io_live = false;
            } else try out.append(gpa, .{ .clock_tick = .{ .by = 2 } }),
            else => try out.append(gpa, .{ .clock_tick = .{ .by = 1 + r.uintLessThan(u32, 5) } }),
        }
    }
    return out.toOwnedSlice(gpa);
}

test "LAW e36-t2 COMPOSITION: project_d(runRow(p)) == runRow(restrict_d(p)) for every domain — handlers commute on disjoint effects" {
    const gpa = std.testing.allocator;
    var seed: u64 = 0;
    while (seed < 64) : (seed += 1) {
        const prog = try genProg(gpa, seed, 120);
        defer gpa.free(prog);

        var full = try runRow(gpa, .{}, prog);
        defer full.deinit(gpa);

        for ([_]Domain{ .mem, .io, .clock }) |d| {
            const proj = try projectDomain(gpa, full.trace.items, d);
            defer gpa.free(proj);
            const restricted = try restrictDomain(gpa, prog, d);
            defer gpa.free(restricted);
            var iso = try runRow(gpa, .{}, restricted);
            defer iso.deinit(gpa);
            // the domain's observed sub-trace is IDENTICAL whether the other domains'
            // ops were interleaved or absent — disjoint effects do not interfere.
            try std.testing.expect(tracesEqual(proj, iso.trace.items));
        }
    }
}

/// Project a trace onto a SET of domains (keep events whose domain is in `doms`).
fn projectDomains(gpa: std.mem.Allocator, trace: []const RowEvent, doms: []const Domain) ![]RowEvent {
    var out: std.ArrayList(RowEvent) = .empty;
    errdefer out.deinit(gpa);
    for (trace) |ev| {
        for (doms) |d| if (ev.domain == d) {
            try out.append(gpa, ev);
            break;
        };
    }
    return out.toOwnedSlice(gpa);
}

test "LAW e37-t2 FUNCTOR: the row is a functor of its domain SET — project_S(runRow(all,p)) == runRowGeneric(S, p) for any subset S" {
    const gpa = std.testing.allocator;
    // three proper subsets exercised through the SAME generic dispatcher (no
    // per-subset handler code): {mem,clock} drops io, {io} is io-only, {mem,io}
    // drops clock. The generic handler is instantiated at each subset; a domain
    // that is not in the subset is simply absent from the handler list.
    const Sub = struct { handlers: []const DomainHandler, doms: []const Domain };
    const subs = [_]Sub{
        .{ .handlers = &.{ mem_handler, clock_handler }, .doms = &.{ .mem, .clock } },
        .{ .handlers = &.{io_handler}, .doms = &.{.io} },
        .{ .handlers = &.{ mem_handler, io_handler }, .doms = &.{ .mem, .io } },
    };
    var seed: u64 = 0;
    while (seed < 48) : (seed += 1) {
        const prog = try genProg(gpa, seed, 100);
        defer gpa.free(prog);
        var full = try runRow(gpa, .{}, prog);
        defer full.deinit(gpa);

        inline for (subs) |sub| {
            // the sub-row (only the subset's handlers) …
            var subrun = try runRowGeneric(sub.handlers, gpa, .{}, prog);
            defer subrun.deinit(gpa);
            // … equals the FULL row projected onto the subset's domains. Composing a
            // SUBSET of domains IS the projection of the full composition — the row
            // is a functor from domain-sets to handlers (the design's open union).
            const proj = try projectDomains(gpa, full.trace.items, sub.doms);
            defer gpa.free(proj);
            try std.testing.expect(tracesEqual(subrun.trace.items, proj));
        }
    }
}

test "LAW e38-t2 HOMOMORPHISM: observe(runRowReal(p)) == observe(runRow(p)) — the row backed by the REAL slab allocator == the pure Model row" {
    const gpa = std.testing.allocator;
    var seed: u64 = 0;
    while (seed < 64) : (seed += 1) {
        const prog = try genProg(gpa, seed, 120);
        defer gpa.free(prog);
        // the pure Model composition …
        var model = try runRow(gpa, .{}, prog);
        defer model.deinit(gpa);
        // … and the REAL composition — mem ops drive substrate/alloc.zig's slab
        // allocator (carriers, free-lists, real host block payloads), io ops a real
        // file store — produce the SAME observed trace under fd/handle→ordinal
        // renaming. The residue (real addresses, reused block indices, carrier
        // layout) is erased by observe; a real host kernel composed into a mixed
        // mem+io+clock row is observed-identical to the pure oracle.
        var real = try runRowReal(gpa, .{}, prog);
        defer real.deinit(gpa);
        try std.testing.expect(tracesEqual(model.trace.items, real.trace.items));
    }
}

test "LAW e36-t2 CAPABILITY: the row's cap set is the PRODUCT — a domain fails closed iff ITS cap is absent; the others still run" {
    const gpa = std.testing.allocator;
    // a program that only touches mem + clock runs WITHOUT the io capability
    // (the caps do not entangle — effect.zig L3 lifted to the row).
    const mem_clock = [_]RowOp{ .mem_alloc, .{ .mem_touch = .{ .v = 9 } }, .{ .clock_tick = .{ .by = 3 } } };
    var r = try runRow(gpa, .{ .io = false }, &mem_clock);
    defer r.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), r.trace.items.len);

    // but the SAME program with the mem cap absent fails closed at the first mem op.
    try std.testing.expectError(error.CapabilityAbsent, runRow(gpa, .{ .mem = false }, &mem_clock));
    // and an io op with the io cap absent fails closed (each domain gates independently).
    const io_only = [_]RowOp{.io_open};
    try std.testing.expectError(error.CapabilityAbsent, runRow(gpa, .{ .io = false }, &io_only));
    // a clock-only program runs with BOTH mem and io absent (full independence).
    const clock_only = [_]RowOp{ .{ .clock_tick = .{ .by = 1 } }, .{ .clock_tick = .{ .by = 1 } } };
    var rc = try runRow(gpa, .{ .mem = false, .io = false }, &clock_only);
    defer rc.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 2), rc.trace.items[1].val); // clock accumulated to 2
}

test "LAW e36-t2 ORDER: the combined trace is the program-order interleaving of the per-domain traces (no handler-introduced reordering)" {
    const gpa = std.testing.allocator;
    // a hand interleaving: mem, io, clock, mem, io — the trace domains must appear
    // in exactly this program order.
    const prog = [_]RowOp{
        .mem_alloc, //          mem
        .io_open, //            io
        .{ .clock_tick = .{ .by = 1 } }, // clock
        .{ .mem_touch = .{ .v = 7 } }, //   mem
        .{ .io_touch = .{ .v = 8 } }, //    io
    };
    var r = try runRow(gpa, .{}, &prog);
    defer r.deinit(gpa);
    const expect = [_]Domain{ .mem, .io, .clock, .mem, .io };
    try std.testing.expectEqual(expect.len, r.trace.items.len);
    for (expect, 0..) |d, i| try std.testing.expectEqual(d, r.trace.items[i].domain);
    // and the mem_touch read back 7, the io_touch read record-0 = 8 (per-domain
    // semantics intact under interleaving).
    try std.testing.expectEqual(@as(u64, 7), r.trace.items[3].val);
    try std.testing.expectEqual(@as(u64, 8), r.trace.items[4].val);
}
