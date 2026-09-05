//! beam-zig M6 / S11-full: the **real GC** law suite (cf. erts erl_gc.c,
//! erl_global_literals.c).
//!
//! The collector lives in term_algebra.zig (FinalTerms.Collector — it is
//! representation knowledge): evacuation with forwarding words, in-place
//! generational collection via the erts high-water discipline. This module
//! owns the LAWS:
//!
//!   DENOTATION PRESERVATION  (still the one true GC spec, now over full
//!       rootsets) — denote(root) unchanged by any collection, with the
//!       dead space poisoned/removed
//!   SHARING PRESERVATION     a DAG rootset copies each cell ONCE: collected
//!       size of {X,X} == collected size of {X} + one word — this law kills
//!       M1's documented duplication caveat; gcCopy (duplicating) remains
//!       the oracle for denotations, Collector must beat it on size
//!   OLD-SPACE STABILITY      minor collection never touches a word below
//!       the water line (byte-identical prefix)
//!   NO-OLD→YOUNG INVARIANT   after every collection, no old-space term slot
//!       points above the water line (terms are immutable — this is WHY
//!       BEAM needs no write barrier; the law pins it)
//!   MINOR IDEMPOTENCE        an immediately repeated minor with the same
//!       roots moves nothing (all survivors were just promoted)
//!   MAJOR COMPACTION         a repeated major is a fixed point, and heap
//!       size never grows across a major
//!   LITERAL IMMUNITY         words below the literal water line are
//!       byte-identical across minors AND majors
//!   GC TRANSPARENCY          a machine collected mid-run finishes with the
//!       same result, reductions, and mailbox as an uncollected twin
//!       (the cross-cutting "copy preserves denotation" row, exercised
//!       through the interpreter)
//!
//! E3.5: pid/reference/port are boxed with an ALL-RAW payload (no term
//! slots — see `term_algebra.zig`'s SUBTAG_REF/PORT/PID doc comment), so
//! `Collector.evac`/`checkNoOldToYoung` needed only a one-line addition
//! (bucket them with bignum/float/binary's "no term slots" case); this
//! module's law suite already exercises them for free through `genTerm`
//! (the E3.5 explicit test lives in `term_algebra.zig` — "E3.5 GC
//! survival").

const std = @import("std");
const ta = @import("term_algebra.zig");
const ia = @import("instr_algebra.zig");
const mba = @import("mailbox_algebra.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;
const bsa = ta.bsa;

/// Collect a set of roots into a fresh heap; returns nothing extra — slots
/// are updated in place.
fn fullCollect(dst: *FinalTerms.Ctx, src: *FinalTerms.Ctx, roots: []FinalTerms.Term) !void {
    var c = FinalTerms.collectInto(dst, src);
    for (roots) |*r| try c.root(r);
    FinalTerms.finishInto(dst, &c);
}

/// E3.9: the ONE TOTAL root enumeration for a full in-place collection of a
/// Machine's own heap — registers, result, EVERY mailbox payload (in-transit
/// + inner), and `pdict` (S24 — see `Machine.pdict`'s doc comment, THE crux:
/// a missed root here is exactly mutant 2, a corrupted/dangling pdict read
/// after a collection). This is the single reusable point that keeps the
/// root set from drifting out of sync across call sites — the same shape as
/// the "GC transparency" test below, factored out so `bifs/pdict.zig`'s
/// GC-root law calls the identical enumeration a future real GC trigger
/// would use.
pub fn collectMachineRoots(m: *ia.Machine) !void {
    // e48-gc-literal-area (CAST-20): collect ABOVE the literal-area water line
    // — the materialized literal pool [0, heap_lit_end) stays byte-stable in
    // place (the erts literal-area exemption), so `m.literals` terms remain
    // positionally valid without being (unrootably-shared) roots.
    var c = FinalTerms.collectInPlace(&m.ctx, m.heap_lit_end);
    for (&m.regs) |*r| try c.root(r);
    // e48-gc-literal-area: the Y REGISTERS — compiled code keeps its locals
    // here across calls; the pre-fix rootset omitted them (the suspend_fam
    // corpus DIVERGENT of CAST-20: a mid-run collect dangled a y-held pid).
    for (m.ystack.items) |*y| try c.root(y);
    // e48-gc-literal-area: runtime-loaded literals live ABOVE the water line
    // (appended at load time mid-life) — root each table entry (mutable).
    for (m.dyn_literals.items) |*dl| try c.root(dl);
    // e48-gc-literal-area: staged/last exception terms (a collect between a
    // BIF raise and its consumption must not dangle the reason/stacktrace).
    if (m.bif_raise) |*ex| {
        try c.root(&ex.reason);
        try c.root(&ex.stacktrace);
    }
    try c.root(&m.result);
    try c.root(&m.pdict);
    try c.root(&m.seq_label); // E7.6: the seq-trace token LABEL is a ctx-heap term (see Machine.seq_label)
    for (m.mbox.inner.items) |*msg| try c.root(&msg.payload);
    for (&m.mbox.in_transit) |*lane| {
        for (lane.items) |*msg| try c.root(&msg.payload);
    }
    // cp-gc-rootset (SAFETY W-14): root EVERY FinalTerms.Term inside a pending
    // scheduler Action (`Machine.pending`, M7). This enumeration previously omitted
    // it, so a GC-during-execution while a BIF-trap Action holds a ctx-heap term
    // (pid/msg/reason/name/…) would use-after-GC that term. Comptime reflection over
    // the Action union (the `beam_loader.relocLits` idiom) roots each Term field of
    // the ACTIVE variant — COMPLETE and future-proof: a newly-added term-bearing
    // variant is rooted automatically, closing the regression class (a hand-listed
    // switch would silently miss it — the exact shape of the original W-14 gap).
    if (m.pending) |*act| {
        switch (act.*) {
            inline else => |*payload| {
                const P = @TypeOf(payload.*);
                if (@typeInfo(P) == .@"struct") {
                    inline for (@typeInfo(P).@"struct".fields) |f| {
                        if (f.type == FinalTerms.Term) try c.root(&@field(payload.*, f.name));
                    }
                }
            },
        }
    }
    _ = try FinalTerms.finishInPlace(&m.ctx, &c);
}

test "LAW cp-gc-rootset: a pending Action's terms are rooted — survive a full collection (SAFETY W-14)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();

    // Garbage on the heap so the collector actually compacts/relocates live terms
    // (an unrooted stale pointer into the reclaimed from-space is the W-14 hazard).
    _ = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 7), FinalTerms.int(&m.ctx, 8) });
    _ = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 9), FinalTerms.nil(&m.ctx));

    // A compound (boxed, heap-relocated) term carried ONLY by m.pending — the exact
    // root the transparency set used to omit.
    const pid = try FinalTerms.pid(&m.ctx, 3, 0);
    const msg = try FinalTerms.tuple(&m.ctx, &.{
        FinalTerms.atomTerm(try atoms.intern("hello")),
        try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 42), FinalTerms.nil(&m.ctx)),
    });
    m.pending = .{ .send_to = .{ .pid = pid, .msg = msg } };

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();
    const before_msg = try FinalTerms.denote(&m.ctx, sa, msg);

    // Full in-place collection. Without the W-14 fix, m.pending's msg is UNROOTED,
    // so its heap word is not forwarded — a use-after-GC on resume.
    try collectMachineRoots(&m);

    // The pending term survived + relocated: read the ROOTED handle back from
    // m.pending (the local `msg` is stale post-compaction) and denote — preserved.
    const after_msg = try FinalTerms.denote(&m.ctx, sa, m.pending.?.send_to.msg);
    try std.testing.expect(spec.eqlExact(before_msg, after_msg));
    try std.testing.expect(FinalTerms.repIsPid(&m.ctx, m.pending.?.send_to.pid));
}

test "E3.1 bitstring: full collection preserves denotation and canonical padding, garbage dropped" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var src = FinalTerms.Ctx.init(gpa, &atoms);
    defer src.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    // a non-byte-aligned bitstring, plus garbage the collector must drop
    const root0 = try FinalTerms.bitstring(&src, &.{ 0x11, 0x22, 0b1010_0000 }, 19);
    for (0..8) |_| _ = try FinalTerms.binary(&src, &.{ 9, 9 }); // garbage
    var roots = [_]FinalTerms.Term{root0};
    const before = try FinalTerms.denote(&src, sa, roots[0]);
    const dirty_size = src.words.items.len;

    var dst = FinalTerms.Ctx.init(gpa, &atoms);
    defer dst.deinit();
    try fullCollect(&dst, &src, &roots);

    const after = try FinalTerms.denote(&dst, sa, roots[0]);
    try std.testing.expect(spec.eqlExact(before, after));
    try std.testing.expect(FinalTerms.repIsBitstring(&dst, roots[0]));
    try std.testing.expect(bsa.isCanonical(FinalTerms.bitstringBits(&dst, roots[0])));
    try std.testing.expect(dst.words.items.len < dirty_size); // garbage reclaimed
}

test "Sharing preservation: a diamond copies once (kills the M1 caveat)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(0x6C6C);
    const random = prng.random();

    for (0..40) |_| {
        var src = FinalTerms.Ctx.init(gpa, &atoms);
        defer src.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();

        // one shared subterm z, two roots: {z} and the diamond {z, z}
        const z = try ta.genTerm(FinalTerms, random, &src, 3);
        var rs = [_]FinalTerms.Term{try FinalTerms.tuple(&src, &.{z})};
        var rd = [_]FinalTerms.Term{try FinalTerms.tuple(&src, &.{ z, z })};
        const rs_before = try FinalTerms.denote(&src, sa, rs[0]);
        const rd_before = try FinalTerms.denote(&src, sa, rd[0]);

        var dst = FinalTerms.Ctx.init(gpa, &atoms);
        defer dst.deinit();
        var c = FinalTerms.collectInto(&dst, &src);
        try c.root(&rs[0]);
        const size_single = c.out.items.len;
        try c.root(&rd[0]); // z already forwarded → fully SHARED
        FinalTerms.finishInto(&dst, &c);
        const size_both = dst.words.items.len;

        // the diamond adds exactly its own 3-word tuple box (header + 2
        // slots): z itself — however large — is not copied again.
        try std.testing.expectEqual(size_single + 3, size_both);
        try std.testing.expect(spec.eqlExact(rs_before, try FinalTerms.denote(&dst, sa, rs[0])));
        try std.testing.expect(spec.eqlExact(rd_before, try FinalTerms.denote(&dst, sa, rd[0])));
    }
}

test "Full collect: denotation preserved, poisoned source, never bigger than the duplicating oracle" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x66C0, .iterations = 60 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var src = FinalTerms.Ctx.init(gpa, &atoms);
        defer src.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();

        // a rootset with genuine sharing: three roots over two subterms
        const a = try ta.genTerm(FinalTerms, random, &src, 3);
        const b = try ta.genTerm(FinalTerms, random, &src, 3);
        var roots = [_]FinalTerms.Term{
            try FinalTerms.cons(&src, a, b),
            try FinalTerms.tuple(&src, &.{ b, a }),
            a,
        };
        var before: [3]*const spec.Value = undefined;
        for (roots, 0..) |r, k| before[k] = try FinalTerms.denote(&src, sa, r);

        // duplicating-oracle size
        var dup = FinalTerms.Ctx.init(gpa, &atoms);
        defer dup.deinit();
        for (roots) |r| _ = try FinalTerms.gcCopy(&dup, &src, r);
        const oracle_size = dup.words.items.len;

        var dst = FinalTerms.Ctx.init(gpa, &atoms);
        defer dst.deinit();
        try fullCollect(&dst, &src, &roots);
        @memset(src.words.items, 0xAAAA_AAAA_AAAA_AAAA); // poison from-space

        for (roots, 0..) |r, k| {
            try expectLaw(spec.eqlExact(before[k], try FinalTerms.denote(&dst, sa, r)), "gc: rootset denotations preserved across poisoned from-space", cfg, i);
        }
        try expectLaw(dst.words.items.len <= oracle_size, "gc: sharing collector never exceeds the duplicating oracle", cfg, i);
    }
}

test "Generational: old-space stability, no-old→young, minor idempotence" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x9E9E, .iterations = 40 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();

        // phase 1: build the "old" generation
        var old_root = try ta.genTerm(FinalTerms, random, &ctx, 3);
        var roots0 = [_]FinalTerms.Term{old_root};
        var c0 = FinalTerms.collectInPlace(&ctx, 0);
        try c0.root(&roots0[0]);
        const hw = try FinalTerms.finishInPlace(&ctx, &c0);
        old_root = roots0[0];
        try expectLaw(FinalTerms.checkNoOldToYoung(&ctx, hw), "gc: compacted old space is self-contained", cfg, i);

        // phase 2: young allocations referencing old (young→old is fine)
        const young1 = try FinalTerms.cons(&ctx, old_root, try ta.genTerm(FinalTerms, random, &ctx, 2));
        const young2 = try FinalTerms.tuple(&ctx, &.{ young1, old_root });
        var roots = [_]FinalTerms.Term{ old_root, young1, young2 };
        var before: [3]*const spec.Value = undefined;
        for (roots, 0..) |r, k| before[k] = try FinalTerms.denote(&ctx, sa, r);
        const old_snapshot = try gpa.dupe(u64, ctx.words.items[0..hw]);
        defer gpa.free(old_snapshot);

        // minor collection
        var c1 = FinalTerms.collectInPlace(&ctx, hw);
        for (&roots) |*r| try c1.root(r);
        const hw2 = try FinalTerms.finishInPlace(&ctx, &c1);

        try expectLaw(std.mem.eql(u64, old_snapshot, ctx.words.items[0..hw]), "gc: minor never touches old space (byte-identical)", cfg, i);
        for (roots, 0..) |r, k| {
            try expectLaw(spec.eqlExact(before[k], try FinalTerms.denote(&ctx, sa, r)), "gc: minor preserves root denotations", cfg, i);
        }
        try expectLaw(FinalTerms.checkNoOldToYoung(&ctx, hw2), "gc: promotion maintains the no-old→young invariant", cfg, i);

        // minor idempotence: an immediate second minor moves nothing
        const words_after = try gpa.dupe(u64, ctx.words.items);
        defer gpa.free(words_after);
        var roots_copy = roots;
        var c2 = FinalTerms.collectInPlace(&ctx, hw2);
        for (&roots_copy) |*r| try c2.root(r);
        const hw3 = try FinalTerms.finishInPlace(&ctx, &c2);
        try expectLaw(hw3 == hw2, "gc: repeated minor is identity on the water line", cfg, i);
        try expectLaw(std.mem.eql(u64, words_after, ctx.words.items), "gc: repeated minor moves nothing", cfg, i);
        for (roots, roots_copy) |r0, r1| {
            try expectLaw(r0 == r1, "gc: repeated minor leaves handles identical", cfg, i);
        }
    }
}

test "Major: literal immunity + compaction fixed point + garbage reclaimed" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x3A30, .iterations = 30 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();

        // literal region: compacted terms at the bottom
        var lit = try ta.genTerm(FinalTerms, random, &ctx, 2);
        var lit_roots = [_]FinalTerms.Term{lit};
        var lc = FinalTerms.collectInPlace(&ctx, 0);
        try lc.root(&lit_roots[0]);
        const lw = try FinalTerms.finishInPlace(&ctx, &lc);
        lit = lit_roots[0];

        // live data + garbage
        var live = try FinalTerms.tuple(&ctx, &.{ lit, try ta.genTerm(FinalTerms, random, &ctx, 3) });
        for (0..10) |_| _ = try ta.genTerm(FinalTerms, random, &ctx, 3); // garbage
        const size_dirty = ctx.words.items.len;
        const live_before = try FinalTerms.denote(&ctx, sa, live);
        const lit_before = try FinalTerms.denote(&ctx, sa, lit);
        const lit_snapshot = try gpa.dupe(u64, ctx.words.items[0..lw]);
        defer gpa.free(lit_snapshot);

        // major collection (keep only literals in place)
        const roots = [_]*FinalTerms.Term{ &live, &lit };
        var mc = FinalTerms.collectInPlace(&ctx, lw);
        for (roots) |r| try mc.root(r);
        const hw = try FinalTerms.finishInPlace(&ctx, &mc);

        try expectLaw(ctx.words.items.len <= size_dirty, "gc: major never grows the heap", cfg, i);
        try expectLaw(std.mem.eql(u64, lit_snapshot, ctx.words.items[0..lw]), "gc: literals byte-identical across major", cfg, i);
        try expectLaw(lit_roots[0] == lit, "gc: literal handles never move", cfg, i);
        try expectLaw(spec.eqlExact(live_before, try FinalTerms.denote(&ctx, sa, live)), "gc: major preserves live denotations", cfg, i);
        try expectLaw(spec.eqlExact(lit_before, try FinalTerms.denote(&ctx, sa, lit)), "gc: major preserves literal denotations", cfg, i);

        // fixed point: a second major reclaims nothing further
        const size_clean = ctx.words.items.len;
        var mc2 = FinalTerms.collectInPlace(&ctx, lw);
        try mc2.root(&live);
        try mc2.root(&lit);
        _ = try FinalTerms.finishInPlace(&ctx, &mc2);
        try expectLaw(ctx.words.items.len == size_clean, "gc: major is a compaction fixed point", cfg, i);
        _ = hw;
    }
}

test "GC transparency: a machine collected mid-run equals its uncollected twin" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x6C7A, .iterations = 25 };

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();

        // a random program (same generator the control laws use)
        var buf: [16]ia.CInstr = undefined;
        const prog = ia.randProgram(random, &buf);

        var m1 = try ia.Machine.init(gpa, &atoms); // collected mid-run
        defer m1.deinit();
        var m2 = try ia.Machine.init(gpa, &atoms); // untouched twin
        defer m2.deinit();
        var seed_prng1 = std.Random.DefaultPrng.init(cfg.seed +% i +% 99);
        var seed_prng2 = std.Random.DefaultPrng.init(cfg.seed +% i +% 99);
        const r1 = seed_prng1.random();
        const r2 = seed_prng2.random();
        for (&m1.regs) |*r| r.* = FinalTerms.int(&m1.ctx, @as(i64, r1.int(i32)));
        for (&m2.regs) |*r| r.* = FinalTerms.int(&m2.ctx, @as(i64, r2.int(i32)));

        try ia.run(&m1, prog, 30);
        try ia.run(&m2, prog, 30);

        // full in-place compaction of m1's heap, rooting EVERYTHING live:
        // registers, result, every mailbox payload (in-transit + inner), and
        // (E3.9) the process dictionary — `collectMachineRoots` is the ONE
        // TOTAL enumeration point (see its doc comment).
        try collectMachineRoots(&m1);

        // the collected machine must be observationally identical...
        try expectLaw(try ia.eqMachines(&m1, &m2, sa), "gc: transparency at the collection point", cfg, i);
        // ...and must FINISH identically
        try ia.run(&m1, prog, 200);
        try ia.run(&m2, prog, 200);
        try expectLaw(try ia.eqMachines(&m1, &m2, sa), "gc: transparency through completion", cfg, i);
    }
}

test "LAW e48-gc-literal-area (CAST-20 discharged): a mid-run collect keeps the literal area BYTE-STABLE IN PLACE, y-register locals SURVIVE with exact denotations, dyn literals are rooted, and the garbage above the line is reclaimed" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();

    // The LITERAL AREA: a compound literal materialized as the heap prefix,
    // the water line set exactly as the loaders set it.
    const lit = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 7), FinalTerms.int(&m.ctx, 8) });
    var lits = [_]FinalTerms.Term{lit};
    m.literals = &lits;
    m.heap_lit_end = m.ctx.words.items.len;
    const lit_word_before = lit; // the positional identity shared readers rely on

    // A Y-REGISTER local (the CAST-20 dangle: pre-fix these were unrooted).
    const ylocal = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 41), FinalTerms.int(&m.ctx, 42) });
    try m.ystack.append(m.gpa, ylocal);
    // A DYN literal (above the line — rooted, not exempted).
    const dl = try FinalTerms.tuple(&m.ctx, &.{FinalTerms.int(&m.ctx, 99)});
    try m.dyn_literals.append(m.gpa, dl);
    // Garbage above the line.
    var k: usize = 0;
    while (k < 2000) : (k += 1) _ = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, @intCast(k)), FinalTerms.int(&m.ctx, 5) });
    const before = m.ctx.words.items.len;

    try collectMachineRoots(&m);

    // the garbage is gone; the heap never shrinks below the water line
    try std.testing.expect(m.ctx.words.items.len < before);
    try std.testing.expect(m.ctx.words.items.len >= m.heap_lit_end);
    // LITERAL-AREA EXEMPTION: the literal term is POSITIONALLY IDENTICAL (not
    // merely denotation-equal — shared table readers hold the old word) and
    // denotes exactly.
    try std.testing.expectEqual(lit_word_before, m.literals[0]);
    try std.testing.expectEqual(@as(i64, 8), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, m.literals[0], 1)));
    // Y-LOCAL SURVIVAL: the y term was relocated live with its denotation.
    try std.testing.expectEqual(@as(i64, 42), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, m.ystack.items[0], 1)));
    // DYN-LITERAL ROOTING: the table entry survived the collect.
    try std.testing.expectEqual(@as(i64, 99), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, m.dyn_literals.items[0], 0)));
    m.literals = &.{}; // detach the stack-owned table before deinit
}
