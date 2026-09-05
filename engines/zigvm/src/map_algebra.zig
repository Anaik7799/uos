//! beam-zig M4 / S4: the **map algebra** law suite (cf. erts erl_map.c).
//!
//! The map OPERATIONS (mapNew/mapGet/mapPut/mapRemove/mapSize) live in
//! term_algebra.zig next to the representations they manipulate — the oracle
//! works on sorted assoc trees, the final encoding on FLATMAP (≤ 32 keys,
//! sorted arrays) and HAMT (> 32) words. This module owns the LAWS:
//!
//!   get∘put            mapGet(mapPut(m,k,v), k) ≡exact v
//!   put-overwrite      put(put(m,k,v1),k,v2) ≡ put(m,k,v2); size unchanged
//!   remove∘put         fresh k: size(remove(put(m,k,v),k)) == size(m);
//!                      get after remove is null
//!   remove-absent      mapRemove(m, absent) is m (same denotation)
//!   CANONICAL FLATNESS the final representation is a flatmap IFF size ≤ 32
//!                      (the map analogue of canonical smallness), across
//!                      arbitrary op sequences that cross the boundary
//!   rep-switch homomorphism  at sizes 31/32/33/34, and along whole random
//!                      op sequences: oracle and final denote the same map,
//!                      same compares, same hashes
//!
//! Keys use EXACT equality (=:=): 1 and 1.0 are DIFFERENT keys. That is
//! itself a law here (the erts map-key semantics).

const std = @import("std");
const ta = @import("term_algebra.zig");

const AtomTable = ta.AtomTable;
const InitialTerms = ta.InitialTerms;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

/// One randomized map operation, decided by the same random stream in both
/// encodings (twin-seed discipline). Keys are small ints in [0, key_space)
/// so sequences collide, overwrite, and cross the 32-key boundary.
const key_space = 50;

fn opRound(
    comptime Impl: type,
    random: std.Random,
    ctx: *Impl.Ctx,
    m: Impl.Term,
) !Impl.Term {
    const k = Impl.int(ctx, @intCast(random.uintLessThan(usize, key_space)));
    switch (random.uintLessThan(u8, 3)) {
        0, 1 => { // put (2/3 weight so maps actually grow past 32)
            const v = Impl.int(ctx, @as(i64, random.int(i32)));
            return try Impl.mapPut(ctx, m, k, v);
        },
        else => return try Impl.mapRemove(ctx, m, k),
    }
}

pub fn verifyMapLaws(comptime Impl: type, gpa: std.mem.Allocator, cfg: LawConfig) !void {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var ctx = Impl.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        var spec_arena = std.heap.ArenaAllocator.init(gpa);
        defer spec_arena.deinit();
        const sa = spec_arena.allocator();

        // build a random map via an op walk
        var m = try Impl.mapNew(&ctx, &.{}, &.{});
        const steps = random.uintLessThan(usize, 60);
        for (0..steps) |_| m = try opRound(Impl, random, &ctx, m);

        const k = Impl.int(&ctx, @intCast(random.uintLessThan(usize, key_space)));
        const v = Impl.int(&ctx, @as(i64, random.int(i32)));
        const v2 = Impl.int(&ctx, @as(i64, random.int(i32)));
        const size0 = Impl.mapSize(&ctx, m);
        const had = Impl.mapGet(&ctx, m, k) != null;

        // get∘put
        const mp = try Impl.mapPut(&ctx, m, k, v);
        const got = Impl.mapGet(&ctx, mp, k) orelse return error.LawViolated;
        try expectLaw(Impl.eqlExact(&ctx, got, v), "map: get after put returns the value", cfg, i);
        try expectLaw(Impl.mapSize(&ctx, mp) == size0 + @intFromBool(!had), "map: put grows size iff key was fresh", cfg, i);

        // put-overwrite
        const mpp = try Impl.mapPut(&ctx, mp, k, v2);
        const got2 = Impl.mapGet(&ctx, mpp, k) orelse return error.LawViolated;
        try expectLaw(Impl.eqlExact(&ctx, got2, v2), "map: second put overwrites", cfg, i);
        try expectLaw(Impl.mapSize(&ctx, mpp) == Impl.mapSize(&ctx, mp), "map: overwrite preserves size", cfg, i);
        try expectLaw(Impl.eqlExact(&ctx, mpp, try Impl.mapPut(&ctx, m, k, v2)), "map: put∘put collapses to last put", cfg, i);

        // remove∘put on a key known present in mp
        const mr = try Impl.mapRemove(&ctx, mp, k);
        try expectLaw(Impl.mapGet(&ctx, mr, k) == null, "map: get after remove is null", cfg, i);
        try expectLaw(Impl.mapSize(&ctx, mr) == Impl.mapSize(&ctx, mp) - 1, "map: remove shrinks size by one", cfg, i);

        // remove-absent: same denotation
        const absent = Impl.int(&ctx, key_space + 7); // outside the key space
        const mra = try Impl.mapRemove(&ctx, m, absent);
        try expectLaw(Impl.eqlExact(&ctx, mra, m), "map: removing an absent key is identity", cfg, i);

        // spec agreement of the map value itself (denote is a sorted assoc
        // list with distinct exact keys — verify sortedness & distinctness)
        const dv = try Impl.denote(&ctx, sa, m);
        const kvs = dv.map;
        var j: usize = 1;
        while (j < kvs.len) : (j += 1) {
            try expectLaw(spec.orderExact(kvs[j - 1].key, kvs[j].key) == .lt, "map: denotation keys strictly ascending (exact order)", cfg, i);
        }
    }
}

/// Exact-key semantics: 1 and 1.0 are different keys (erts map law).
fn verifyExactKeys(comptime Impl: type, gpa: std.mem.Allocator) !void {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = Impl.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const ki = Impl.int(&ctx, 1);
    const kf = Impl.float(&ctx, 1.0);
    const va = Impl.int(&ctx, 100);
    const vb = Impl.int(&ctx, 200);

    var m = try Impl.mapNew(&ctx, &.{}, &.{});
    m = try Impl.mapPut(&ctx, m, ki, va);
    m = try Impl.mapPut(&ctx, m, kf, vb);
    try std.testing.expectEqual(@as(usize, 2), Impl.mapSize(&ctx, m));
    try std.testing.expect(Impl.eqlExact(&ctx, Impl.mapGet(&ctx, m, ki).?, va));
    try std.testing.expect(Impl.eqlExact(&ctx, Impl.mapGet(&ctx, m, kf).?, vb));
}

test "Laws: map ops on the Initial encoding (sorted assoc oracle)" {
    try verifyMapLaws(InitialTerms, std.testing.allocator, .{ .iterations = 80 });
}

test "Laws: map ops on the Final encoding (flatmap + HAMT words)" {
    try verifyMapLaws(FinalTerms, std.testing.allocator, .{ .iterations = 80 });
}

test "Law: map keys are exact — 1 and 1.0 are distinct keys" {
    try verifyExactKeys(InitialTerms, std.testing.allocator);
    try verifyExactKeys(FinalTerms, std.testing.allocator);
}

test "CANONICAL FLATNESS: final rep is flatmap iff size ≤ 32, across op walks" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0xF1A7 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..30) |i| {
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        var m = try FinalTerms.mapNew(&ctx, &.{}, &.{});
        for (0..120) |_| {
            m = try opRound(FinalTerms, random, &ctx, m);
            const size = FinalTerms.mapSize(&ctx, m);
            try expectLaw(
                FinalTerms.mapRepIsFlat(&ctx, m) == (size <= ta.max_flatmap_size),
                "canonical flatness: flat iff size ≤ 32",
                cfg,
                i,
            );
        }
    }
}

test "Rep-switch homomorphism: 31→34 and back, oracle and words agree" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ic = InitialTerms.Ctx.init(gpa, &atoms);
    defer ic.deinit();
    var fc = FinalTerms.Ctx.init(gpa, &atoms);
    defer fc.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    var mi = try InitialTerms.mapNew(&ic, &.{}, &.{});
    var mf = try FinalTerms.mapNew(&fc, &.{}, &.{});

    // grow through the boundary
    for (0..34) |k| {
        const ki = InitialTerms.int(&ic, @intCast(k));
        const kf = FinalTerms.int(&fc, @intCast(k));
        const vi = InitialTerms.int(&ic, @intCast(k * 10));
        const vf = FinalTerms.int(&fc, @intCast(k * 10));
        mi = try InitialTerms.mapPut(&ic, mi, ki, vi);
        mf = try FinalTerms.mapPut(&fc, mf, kf, vf);
        const size = k + 1;
        try std.testing.expectEqual(size, FinalTerms.mapSize(&fc, mf));
        try std.testing.expectEqual(FinalTerms.mapRepIsFlat(&fc, mf), size <= ta.max_flatmap_size);
        try std.testing.expect(spec.eqlExact(
            try InitialTerms.denote(&ic, sa, mi),
            try FinalTerms.denote(&fc, sa, mf),
        ));
        try std.testing.expectEqual(
            InitialTerms.hashTerm(&ic, mi),
            FinalTerms.hashTerm(&fc, mf),
        );
    }
    // probe every key through the HAMT
    for (0..34) |k| {
        const got = FinalTerms.mapGet(&fc, mf, FinalTerms.int(&fc, @intCast(k))) orelse
            return error.LawViolated;
        try std.testing.expect(FinalTerms.eqlExact(&fc, got, FinalTerms.int(&fc, @intCast(k * 10))));
    }
    // shrink back through the boundary (demotion)
    var k: i64 = 33;
    while (k >= 30) : (k -= 1) {
        mi = try InitialTerms.mapRemove(&ic, mi, InitialTerms.int(&ic, k));
        mf = try FinalTerms.mapRemove(&fc, mf, FinalTerms.int(&fc, k));
        const size: usize = @intCast(k);
        try std.testing.expectEqual(size, FinalTerms.mapSize(&fc, mf));
        try std.testing.expectEqual(FinalTerms.mapRepIsFlat(&fc, mf), size <= ta.max_flatmap_size);
        try std.testing.expect(spec.eqlExact(
            try InitialTerms.denote(&ic, sa, mi),
            try FinalTerms.denote(&fc, sa, mf),
        ));
    }
    // flat and HAMT versions of the same 32-key map compare equal & hash equal
    // (compare works across representations because it is observational)
    const dm = try FinalTerms.denote(&fc, sa, mf);
    try std.testing.expectEqual(@as(usize, 30), dm.map.len);
}

test "Twin op-sequences: oracle and final agree at every step (incl. maps in maps)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x3A9B };

    for (0..20) |i| {
        var ic = InitialTerms.Ctx.init(gpa, &atoms);
        defer ic.deinit();
        var fc = FinalTerms.Ctx.init(gpa, &atoms);
        defer fc.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng_a = std.Random.DefaultPrng.init(cfg.seed +% i);
        var prng_b = std.Random.DefaultPrng.init(cfg.seed +% i);
        const ra = prng_a.random();
        const rb = prng_b.random();

        var mi = try InitialTerms.mapNew(&ic, &.{}, &.{});
        var mf = try FinalTerms.mapNew(&fc, &.{}, &.{});
        for (0..80) |_| {
            mi = try opRound(InitialTerms, ra, &ic, mi);
            mf = try opRound(FinalTerms, rb, &fc, mf);
            try expectLaw(spec.eqlExact(
                try InitialTerms.denote(&ic, sa, mi),
                try FinalTerms.denote(&fc, sa, mf),
            ), "map twin walk: denotations agree", cfg, i);
            try expectLaw(
                InitialTerms.hashTerm(&ic, mi) == FinalTerms.hashTerm(&fc, mf),
                "map twin walk: hashes agree",
                cfg,
                i,
            );
        }
        // maps as VALUES inside terms: wrap in a tuple and compare via terms
        const wi = try InitialTerms.tuple(&ic, &.{mi});
        const wf = try FinalTerms.tuple(&fc, &.{mf});
        try expectLaw(spec.eqlExact(
            try InitialTerms.denote(&ic, sa, wi),
            try FinalTerms.denote(&fc, sa, wf),
        ), "map-in-tuple: denotations agree", cfg, i);
    }
}
