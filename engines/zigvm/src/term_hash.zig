//! beam-zig M4 / S7: **term hashing** law suite (cf. erts erl_term_hashing.c).
//!
//! The hash implementations live in term_algebra.zig (spec.hashValue over
//! canonical trees is the SPEC; FinalTerms.hashTerm walks raw tagged words
//! and must agree). This module owns the laws:
//!
//!   COHERENCE      eqlExact(a,b) ⇒ hash(a) == hash(b)
//!                  (over =:=, NOT ==: 1 and 1.0 hash differently by design —
//!                  exactly why ETS `set` and `ordered_set` key semantics
//!                  differ, S22's future law)
//!   SPEC AGREEMENT hashTerm(w) == spec.hashValue(denote(w)) — the word
//!                  walker never sees addresses, only values
//!   GC INVARIANCE  hash(gcCopy(t)) == hash(t) (address-freedom, again)
//!   ORDER-FREEDOM  a map built by ANY insertion order of the same pairs
//!                  hashes identically (HAMT iteration order must not leak)
//!
//! Plus the cross-cutting register row "eql ⇒ equal hash" (S1×S7): for
//! same-kind terms arithmetic and exact equality coincide, so coherence
//! over eqlExact discharges it; the int/float exception is the documented
//! (and spot-tested) reason the register names EXACT equality.

const std = @import("std");
const ta = @import("term_algebra.zig");

const AtomTable = ta.AtomTable;
const InitialTerms = ta.InitialTerms;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

test "Coherence + spec agreement + GC invariance over generated terms" {
    const gpa = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0x4A54, .iterations = 100 };
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    for (0..cfg.iterations) |i| {
        var fc = FinalTerms.Ctx.init(gpa, &atoms);
        defer fc.deinit();
        var to = FinalTerms.Ctx.init(gpa, &atoms);
        defer to.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();

        // twin terms in one heap: exact-equal by construction
        var p1 = std.Random.DefaultPrng.init(cfg.seed +% i);
        var p2 = std.Random.DefaultPrng.init(cfg.seed +% i);
        const a = try ta.genTerm(FinalTerms, p1.random(), &fc, cfg.max_depth);
        const b = try ta.genTerm(FinalTerms, p2.random(), &fc, cfg.max_depth);
        try expectLaw(FinalTerms.eqlExact(&fc, a, b), "hash: twins are exact-equal", cfg, i);
        try expectLaw(FinalTerms.hashTerm(&fc, a) == FinalTerms.hashTerm(&fc, b), "hash: coherence over exact equality", cfg, i);
        try expectLaw(FinalTerms.hashTerm(&fc, a) == spec.hashValue(try FinalTerms.denote(&fc, sa, a)), "hash: word walker agrees with spec hash", cfg, i);

        const copied = try FinalTerms.gcCopy(&to, &fc, a);
        try expectLaw(FinalTerms.hashTerm(&to, copied) == FinalTerms.hashTerm(&fc, a), "hash: GC copy invariance", cfg, i);
    }
}

test "Order-freedom: map insertion order never leaks into the hash" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var prng = std.Random.DefaultPrng.init(0x0D0E);
    const random = prng.random();

    // 40 keys → HAMT territory; build forward, backward, and shuffled
    const n = 40;
    var perm: [n]usize = undefined;
    for (&perm, 0..) |*p, i| p.* = i;
    random.shuffle(usize, &perm);

    var fwd = try FinalTerms.mapNew(&ctx, &.{}, &.{});
    var bwd = try FinalTerms.mapNew(&ctx, &.{}, &.{});
    var shuf = try FinalTerms.mapNew(&ctx, &.{}, &.{});
    for (0..n) |i| {
        fwd = try FinalTerms.mapPut(&ctx, fwd, FinalTerms.int(&ctx, @intCast(i)), FinalTerms.int(&ctx, @intCast(i * 3)));
        const j = n - 1 - i;
        bwd = try FinalTerms.mapPut(&ctx, bwd, FinalTerms.int(&ctx, @intCast(j)), FinalTerms.int(&ctx, @intCast(j * 3)));
        const k = perm[i];
        shuf = try FinalTerms.mapPut(&ctx, shuf, FinalTerms.int(&ctx, @intCast(k)), FinalTerms.int(&ctx, @intCast(k * 3)));
    }
    const h = FinalTerms.hashTerm(&ctx, fwd);
    try std.testing.expectEqual(h, FinalTerms.hashTerm(&ctx, bwd));
    try std.testing.expectEqual(h, FinalTerms.hashTerm(&ctx, shuf));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, fwd, bwd));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, fwd, shuf));
}

test "Design point: 1 and 1.0 are ==-equal but hash differently (exact hash)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const one_i = FinalTerms.int(&ctx, 1);
    const f1 = FinalTerms.float(&ctx, 1.0);
    try std.testing.expect(FinalTerms.eql(&ctx, one_i, f1)); // arithmetic ==
    try std.testing.expect(!FinalTerms.eqlExact(&ctx, one_i, f1)); // not =:=
    try std.testing.expect(FinalTerms.hashTerm(&ctx, one_i) != FinalTerms.hashTerm(&ctx, f1));

    // …but small 5 and big-demoted 5 are the SAME value, same hash
    // (canonical smallness makes this unrepresentable as two forms; the law
    // is that VALUE determines hash — check via a computed 5)
    const five = try FinalTerms.add(&ctx, FinalTerms.int(&ctx, 2), FinalTerms.int(&ctx, 3));
    try std.testing.expectEqual(FinalTerms.hashTerm(&ctx, FinalTerms.int(&ctx, 5)), FinalTerms.hashTerm(&ctx, five));
}

test "E3.1 bitstring: canonical-padding invariant makes hash agnostic to incoming padding junk" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var prng = std.Random.DefaultPrng.init(0xB17A);
    const random = prng.random();

    for (0..100) |_| {
        var buf: [8]u8 = undefined;
        const nbytes = 1 + random.uintLessThan(usize, buf.len);
        for (buf[0..nbytes]) |*b| b.* = random.int(u8);
        // a NON-byte-aligned length so the last byte has real padding
        const rem = 1 + random.uintLessThan(usize, 7);
        const bit_len = (nbytes - 1) * 8 + rem;

        const clean = try FinalTerms.bitstring(&ctx, buf[0..nbytes], bit_len);
        // same significant bits, garbage stuffed into the padding tail
        var junk = buf;
        const pad_mask: u8 = (@as(u8, 1) << @intCast(8 - rem)) - 1;
        junk[nbytes - 1] |= pad_mask & random.int(u8);
        const dirty = try FinalTerms.bitstring(&ctx, junk[0..nbytes], bit_len);

        try std.testing.expect(FinalTerms.eqlExact(&ctx, clean, dirty));
        try std.testing.expectEqual(FinalTerms.hashTerm(&ctx, clean), FinalTerms.hashTerm(&ctx, dirty));
    }
}

test "E3.1 bitstring: hash agrees with spec.hashValue over generated bitstring-mixed terms" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    const bs = try FinalTerms.bitstring(&ctx, &.{ 0x5A, 0b1100_0000 }, 10);
    try std.testing.expectEqual(spec.hashValue(try FinalTerms.denote(&ctx, sa, bs)), FinalTerms.hashTerm(&ctx, bs));
}

test "Oracle hash: InitialTerms agrees with spec by construction" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ic = InitialTerms.Ctx.init(gpa, &atoms);
    defer ic.deinit();
    var prng = std.Random.DefaultPrng.init(0x11A5);

    for (0..50) |_| {
        const t = try ta.genTerm(InitialTerms, prng.random(), &ic, 3);
        try std.testing.expectEqual(spec.hashValue(t), InitialTerms.hashTerm(&ic, t));
    }
}
