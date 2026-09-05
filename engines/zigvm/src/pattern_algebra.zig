//! beam-zig M5 / S23-seed: the **pattern algebra** (cf. erts beam matching
//! ops + erl_db_util.c match programs, which reuse this at M11).
//!
//! Signature:
//!   patterns   pvar(n) | plit(term) | pwild | pcons(p,p) | ptuple(ps)
//!              | pmap(entries: literal key → sub-pattern)   [linear or not]
//!   build      : (Pattern, θ) -> Term          (constructor of subjects)
//!   match      : (Pattern, Term, *Bindings) -> bool   (THE observation)
//!
//! Semantic domain: partial functions Term -> ?Bindings.
//!
//! Laws:
//!   ROUND-TRIP        match(p, build(p, θ)) == θ on p's variables (linear p)
//!   WILDCARD TOTALITY pwild matches every term, binds nothing
//!   VAR TOTALITY      pvar matches every term and binds it EXACTLY
//!   LITERAL           plit(t) matches s  ⇔  t =:= s (exact, never arith)
//!   FAILURE SOUNDNESS a failed match leaves the caller's bindings UNTOUCHED
//!                     (no partial bindings observable — erts semantics)
//!   NON-LINEARITY     a repeated variable requires =:= between occurrences
//!   MAP SUBSET        pmap matches any map CONTAINING its keys with matching
//!                     values (map patterns are subset patterns, as in Erlang)
//!   HOMOMORPHISM      the ONE generic matcher, instantiated at the tree
//!                     oracle and at tagged words, agrees on twin inputs
//!
//! The matcher is generic over any term encoding that provides the
//! structural-reflection observations (kindOf/listHead/…) — the initial
//! encoding's reflection is trivial tree access, which makes match(Initial)
//! the oracle by construction; match(Final) walks raw words and never
//! materializes trees.
//!
//! E3.5: pid/reference/port need NO new pattern-algebra case — they are
//! opaque to structural patterns exactly like funs (M5's `LITERAL`/`VAR`
//! rules already cover them: `plit`/`pvar` match by `eqlExact`, which the
//! E3.5 term-kind work makes total over these three kinds too). See "E3.5
//! pid/reference/port match by exact equality (plit/pvar), like funs"
//! below.

const std = @import("std");
const ta = @import("term_algebra.zig");

const AtomTable = ta.AtomTable;
const InitialTerms = ta.InitialTerms;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

pub const max_vars = 8;

pub fn Pattern(comptime Impl: type) type {
    return union(enum) {
        const Self = @This();
        pub const MapEntry = struct { key: Impl.Term, val: *const Self };

        pvar: u8, //                  variable slot, 0..max_vars-1
        plit: Impl.Term, //           literal, matched with =:=
        pwild,
        pcons: struct { h: *const Self, t: *const Self },
        ptuple: []const *const Self,
        pmap: []const MapEntry,
    };
}

pub fn Bindings(comptime Impl: type) type {
    return struct {
        slots: [max_vars]?Impl.Term = @splat(null),
    };
}

/// THE observation. On success writes the complete bindings to `out` and
/// returns true; on failure returns false and leaves `out` UNTOUCHED —
/// failure soundness is architectural, then verified by law anyway.
pub fn match(
    comptime Impl: type,
    ctx: *Impl.Ctx,
    p: *const Pattern(Impl),
    subj: Impl.Term,
    out: *Bindings(Impl),
) bool {
    var b = Bindings(Impl){};
    if (matchInner(Impl, ctx, p, subj, &b)) {
        out.* = b;
        return true;
    }
    return false;
}

fn matchInner(
    comptime Impl: type,
    ctx: *Impl.Ctx,
    p: *const Pattern(Impl),
    subj: Impl.Term,
    b: *Bindings(Impl),
) bool {
    switch (p.*) {
        .pwild => return true,
        .pvar => |n| {
            if (b.slots[n]) |prev| // non-linear occurrence: must be =:=
                return Impl.eqlExact(ctx, prev, subj);
            b.slots[n] = subj;
            return true;
        },
        .plit => |lit| return Impl.eqlExact(ctx, lit, subj),
        .pcons => |pc| {
            if (Impl.kindOf(ctx, subj) != .cons) return false;
            if (!matchInner(Impl, ctx, pc.h, Impl.listHead(ctx, subj), b)) return false;
            return matchInner(Impl, ctx, pc.t, Impl.listTail(ctx, subj), b);
        },
        .ptuple => |ps| {
            if (Impl.kindOf(ctx, subj) != .tuple) return false;
            if (Impl.tupleArity(ctx, subj) != ps.len) return false;
            for (ps, 0..) |sub, i| {
                if (!matchInner(Impl, ctx, sub, Impl.tupleElem(ctx, subj, i), b)) return false;
            }
            return true;
        },
        .pmap => |entries| {
            if (Impl.kindOf(ctx, subj) != .map) return false;
            for (entries) |e| {
                const v = Impl.mapGet(ctx, subj, e.key) orelse return false;
                if (!matchInner(Impl, ctx, e.val, v, b)) return false;
            }
            return true;
        },
    }
}

/// Build the least subject a pattern matches, under θ. Wildcards get nil
/// (any filler works: match ignores what wilds saw). Vars must be bound.
pub fn build(
    comptime Impl: type,
    ctx: *Impl.Ctx,
    p: *const Pattern(Impl),
    theta: *const Bindings(Impl),
) error{ OutOfMemory, BadArg }!Impl.Term {
    switch (p.*) {
        .pwild => return Impl.nil(ctx),
        .pvar => |n| return theta.slots[n] orelse error.BadArg,
        .plit => |lit| return lit,
        .pcons => |pc| return try Impl.cons(
            ctx,
            try build(Impl, ctx, pc.h, theta),
            try build(Impl, ctx, pc.t, theta),
        ),
        .ptuple => |ps| {
            var buf: [8]Impl.Term = undefined;
            std.debug.assert(ps.len <= 8);
            for (ps, 0..) |sub, i| buf[i] = try build(Impl, ctx, sub, theta);
            return try Impl.tuple(ctx, buf[0..ps.len]);
        },
        .pmap => |entries| {
            var ks: [8]Impl.Term = undefined;
            var vs: [8]Impl.Term = undefined;
            std.debug.assert(entries.len <= 8);
            for (entries, 0..) |e, i| {
                ks[i] = e.key;
                vs[i] = try build(Impl, ctx, e.val, theta);
            }
            return try Impl.mapNew(ctx, ks[0..entries.len], vs[0..entries.len]);
        },
    }
}

// ============================================================================
// Generators
// ============================================================================

const GenState = struct { next_var: u8 = 0, map_key: i64 = 1000 };

/// Linear pattern generator: every pvar gets a FRESH slot (round-trip laws
/// need linearity); map keys are distinct int literals from a counter.
pub fn genPattern(
    comptime Impl: type,
    random: std.Random,
    ctx: *Impl.Ctx,
    arena: std.mem.Allocator,
    st: *GenState,
    depth: usize,
) !*const Pattern(Impl) {
    const P = Pattern(Impl);
    const node = try arena.create(P);
    const Variant = enum { pvar, plit, pwild, pcons, ptuple, pmap };
    const pick: Variant = if (depth == 0) switch (random.uintLessThan(u8, 3)) {
        0 => .pvar,
        1 => .plit,
        else => .pwild,
    } else random.enumValue(Variant);

    switch (pick) {
        .pvar => {
            if (st.next_var < max_vars) {
                node.* = .{ .pvar = st.next_var };
                st.next_var += 1;
            } else node.* = .pwild;
        },
        .pwild => node.* = .pwild,
        .plit => node.* = .{ .plit = try ta.genTerm(Impl, random, ctx, 1) },
        .pcons => node.* = .{ .pcons = .{
            .h = try genPattern(Impl, random, ctx, arena, st, depth - 1),
            .t = try genPattern(Impl, random, ctx, arena, st, depth - 1),
        } },
        .ptuple => {
            const n = random.uintLessThan(usize, 4);
            const ps = try arena.alloc(*const P, n);
            for (ps) |*slot| slot.* = try genPattern(Impl, random, ctx, arena, st, depth - 1);
            node.* = .{ .ptuple = ps };
        },
        .pmap => {
            const n = 1 + random.uintLessThan(usize, 2);
            const es = try arena.alloc(P.MapEntry, n);
            for (es) |*e| {
                e.* = .{
                    .key = Impl.int(ctx, st.map_key),
                    .val = try genPattern(Impl, random, ctx, arena, st, depth - 1),
                };
                st.map_key += 1;
            }
            node.* = .{ .pmap = es };
        },
    }
    return node;
}

fn genTheta(comptime Impl: type, random: std.Random, ctx: *Impl.Ctx, used: u8) !Bindings(Impl) {
    var th = Bindings(Impl){};
    for (0..used) |i| th.slots[i] = try ta.genTerm(Impl, random, ctx, 2);
    return th;
}

// ============================================================================
// Law suite
// ============================================================================

pub fn verifyPatternLaws(comptime Impl: type, gpa: std.mem.Allocator, cfg: LawConfig) !void {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var ctx = Impl.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        var parena = std.heap.ArenaAllocator.init(gpa);
        defer parena.deinit();
        const pa = parena.allocator();

        var st = GenState{};
        const p = try genPattern(Impl, random, &ctx, pa, &st, 3);
        const theta = try genTheta(Impl, random, &ctx, st.next_var);

        // ROUND-TRIP on linear patterns
        const subj = try build(Impl, &ctx, p, &theta);
        var out = Bindings(Impl){};
        try expectLaw(match(Impl, &ctx, p, subj, &out), "pattern: match(p, build(p,θ)) succeeds", cfg, i);
        for (0..st.next_var) |n| {
            const got = out.slots[n] orelse {
                // a var may be unreached only if it sits under a pwild? No —
                // linear generation embeds every var in the pattern itself.
                return expectLaw(false, "pattern: round-trip bound every variable", cfg, i);
            };
            try expectLaw(Impl.eqlExact(&ctx, got, theta.slots[n].?), "pattern: round-trip bindings agree (exact)", cfg, i);
        }

        // WILDCARD & VAR TOTALITY over an arbitrary term
        const any = try ta.genTerm(Impl, random, &ctx, cfg.max_depth);
        var b1 = Bindings(Impl){};
        const wildp = Pattern(Impl){ .pwild = {} };
        try expectLaw(match(Impl, &ctx, &wildp, any, &b1), "pattern: wildcard totality", cfg, i);
        const varp = Pattern(Impl){ .pvar = 0 };
        var b2 = Bindings(Impl){};
        try expectLaw(match(Impl, &ctx, &varp, any, &b2), "pattern: variable totality", cfg, i);
        try expectLaw(Impl.eqlExact(&ctx, b2.slots[0].?, any), "pattern: variable binds the subject exactly", cfg, i);

        // LITERAL ⇔ exact equality
        const lit = try ta.genTerm(Impl, random, &ctx, 2);
        const cand = try ta.genTerm(Impl, random, &ctx, 2);
        const litp = Pattern(Impl){ .plit = lit };
        var b3 = Bindings(Impl){};
        try expectLaw(match(Impl, &ctx, &litp, cand, &b3) == Impl.eqlExact(&ctx, lit, cand), "pattern: literal matches iff =:=", cfg, i);

        // FAILURE SOUNDNESS: a sentinel-filled out survives a failed match
        const sentinel = Impl.int(&ctx, 424242);
        var b4 = Bindings(Impl){};
        b4.slots[0] = sentinel;
        b4.slots[3] = sentinel;
        // pattern {x0, x1} cannot match a non-tuple (nil)
        const v0 = Pattern(Impl){ .pvar = 0 };
        const v1 = Pattern(Impl){ .pvar = 1 };
        const tp = Pattern(Impl){ .ptuple = &.{ &v0, &v1 } };
        try expectLaw(!match(Impl, &ctx, &tp, Impl.nil(&ctx), &b4), "pattern: tuple pattern rejects nil", cfg, i);
        try expectLaw(b4.slots[0] != null and Impl.eqlExact(&ctx, b4.slots[0].?, sentinel), "pattern: failure leaves bindings untouched (slot 0)", cfg, i);
        try expectLaw(b4.slots[1] == null, "pattern: failure leaves bindings untouched (slot 1)", cfg, i);
        try expectLaw(b4.slots[3] != null and Impl.eqlExact(&ctx, b4.slots[3].?, sentinel), "pattern: failure leaves bindings untouched (slot 3)", cfg, i);

        // FAILURE SOUNDNESS (deep): a pattern that BINDS slot 0 and THEN
        // fails on a later position must not leak the partial binding.
        // (This is the case that kills the write-through mutant.)
        const lit_no = Pattern(Impl){ .plit = Impl.int(&ctx, -111222333) };
        const deep = Pattern(Impl){ .ptuple = &.{ &v0, &lit_no } };
        const subj_bad = try Impl.tuple(&ctx, &.{ any, Impl.int(&ctx, 77) });
        var b9 = Bindings(Impl){};
        try expectLaw(!match(Impl, &ctx, &deep, subj_bad, &b9), "pattern: bind-then-fail rejects", cfg, i);
        try expectLaw(b9.slots[0] == null, "pattern: deep failure leaks no partial binding", cfg, i);

        // NON-LINEARITY: [X|X] needs head =:= tail
        const nl = Pattern(Impl){ .pcons = .{ .h = &v0, .t = &v0 } };
        const t1 = try ta.genTerm(Impl, random, &ctx, 2);
        var tw1 = std.Random.DefaultPrng.init(cfg.seed +% i +% 7);
        var tw2 = std.Random.DefaultPrng.init(cfg.seed +% i +% 7);
        const same_a = try ta.genTerm(Impl, tw1.random(), &ctx, 2);
        const same_b = try ta.genTerm(Impl, tw2.random(), &ctx, 2);
        var b5 = Bindings(Impl){};
        try expectLaw(match(Impl, &ctx, &nl, try Impl.cons(&ctx, same_a, same_b), &b5), "pattern: non-linear var accepts exact-equal pair", cfg, i);
        const other = try Impl.cons(&ctx, t1, Impl.int(&ctx, -987654321));
        var b6 = Bindings(Impl){};
        const both_eq = Impl.eqlExact(&ctx, t1, Impl.int(&ctx, -987654321));
        try expectLaw(match(Impl, &ctx, &nl, other, &b6) == both_eq, "pattern: non-linear var rejects unequal pair", cfg, i);

        // MAP SUBSET: adding an extra key must not break the match;
        // removing a required key must.
        var st2 = GenState{};
        var pm = Pattern(Impl){ .pmap = &.{} };
        const entry_val = Pattern(Impl){ .pvar = 7 };
        const key = Impl.int(&ctx, 555);
        const entries = [_]Pattern(Impl).MapEntry{.{ .key = key, .val = &entry_val }};
        pm = .{ .pmap = &entries };
        _ = &st2;
        const payload = try ta.genTerm(Impl, random, &ctx, 2);
        var m = try Impl.mapNew(&ctx, &.{key}, &.{payload});
        m = try Impl.mapPut(&ctx, m, Impl.int(&ctx, 556), Impl.int(&ctx, 1)); // extra key
        var b7 = Bindings(Impl){};
        try expectLaw(match(Impl, &ctx, &pm, m, &b7), "pattern: map pattern is a subset pattern", cfg, i);
        try expectLaw(Impl.eqlExact(&ctx, b7.slots[7].?, payload), "pattern: map pattern binds the value", cfg, i);
        const m2 = try Impl.mapRemove(&ctx, m, key);
        var b8 = Bindings(Impl){};
        try expectLaw(!match(Impl, &ctx, &pm, m2, &b8), "pattern: missing key fails the map pattern", cfg, i);
    }
}

test "Laws: patterns over the Initial encoding (tree oracle)" {
    try verifyPatternLaws(InitialTerms, std.testing.allocator, .{ .iterations = 80 });
}

test "Laws: patterns over the Final encoding (raw tagged words)" {
    try verifyPatternLaws(FinalTerms, std.testing.allocator, .{ .iterations = 80 });
}

test "Homomorphism: twin patterns + twin subjects match identically" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x9A77 };

    for (0..60) |i| {
        var ic = InitialTerms.Ctx.init(gpa, &atoms);
        defer ic.deinit();
        var fc = FinalTerms.Ctx.init(gpa, &atoms);
        defer fc.deinit();
        var pa = std.heap.ArenaAllocator.init(gpa);
        defer pa.deinit();
        var sa = std.heap.ArenaAllocator.init(gpa);
        defer sa.deinit();

        var prng_a = std.Random.DefaultPrng.init(cfg.seed +% i);
        var prng_b = std.Random.DefaultPrng.init(cfg.seed +% i);
        const ra = prng_a.random();
        const rb = prng_b.random();

        var st_a = GenState{};
        var st_b = GenState{};
        const pi = try genPattern(InitialTerms, ra, &ic, pa.allocator(), &st_a, 3);
        const pf = try genPattern(FinalTerms, rb, &fc, pa.allocator(), &st_b, 3);
        const si = try ta.genTerm(InitialTerms, ra, &ic, 3);
        const sf = try ta.genTerm(FinalTerms, rb, &fc, 3);

        var bi = Bindings(InitialTerms){};
        var bf = Bindings(FinalTerms){};
        const ri = match(InitialTerms, &ic, pi, si, &bi);
        const rf = match(FinalTerms, &fc, pf, sf, &bf);
        try expectLaw(ri == rf, "pattern homomorphism: same verdict", cfg, i);
        if (ri) {
            for (0..max_vars) |n| {
                const has_i = bi.slots[n] != null;
                const has_f = bf.slots[n] != null;
                try expectLaw(has_i == has_f, "pattern homomorphism: same slots bound", cfg, i);
                if (has_i) {
                    try expectLaw(spec.eqlExact(
                        try InitialTerms.denote(&ic, sa.allocator(), bi.slots[n].?),
                        try FinalTerms.denote(&fc, sa.allocator(), bf.slots[n].?),
                    ), "pattern homomorphism: bindings denote equal", cfg, i);
                }
            }
        }
    }
}

test "Funs are opaque to structural patterns but matchable as literals/vars" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const env = [_]FinalTerms.Term{FinalTerms.int(&ctx, 9)};
    const f = try FinalTerms.makeFun(&ctx, 12, 2, &env);
    const f_twin = try FinalTerms.makeFun(&ctx, 12, 2, &env);
    const g = try FinalTerms.makeFun(&ctx, 13, 2, &env);

    const litp = Pattern(FinalTerms){ .plit = f };
    var b = Bindings(FinalTerms){};
    try std.testing.expect(match(FinalTerms, &ctx, &litp, f_twin, &b)); // same fun value
    try std.testing.expect(!match(FinalTerms, &ctx, &litp, g, &b)); // different label

    const consp = Pattern(FinalTerms){ .pcons = .{
        .h = &Pattern(FinalTerms){ .pwild = {} },
        .t = &Pattern(FinalTerms){ .pwild = {} },
    } };
    try std.testing.expect(!match(FinalTerms, &ctx, &consp, f, &b)); // fun is not a cons
}

test "E3.5 pid/reference/port match by exact equality (plit/pvar), like funs" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const p1 = try FinalTerms.pid(&ctx, 3, 0);
    const p1_twin = try FinalTerms.pid(&ctx, 3, 0);
    const p2 = try FinalTerms.pid(&ctx, 3, 1);
    const litp = Pattern(FinalTerms){ .plit = p1 };
    var b = Bindings(FinalTerms){};
    try std.testing.expect(match(FinalTerms, &ctx, &litp, p1_twin, &b));
    try std.testing.expect(!match(FinalTerms, &ctx, &litp, p2, &b));

    const r1 = try FinalTerms.ref(&ctx, .{ 1, 2, 3 });
    const varp = Pattern(FinalTerms){ .pvar = 0 };
    var b2 = Bindings(FinalTerms){};
    try std.testing.expect(match(FinalTerms, &ctx, &varp, r1, &b2));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, b2.slots[0].?, r1));

    const consp = Pattern(FinalTerms){ .pcons = .{
        .h = &Pattern(FinalTerms){ .pwild = {} },
        .t = &Pattern(FinalTerms){ .pwild = {} },
    } };
    const port_t = try FinalTerms.port(&ctx, 5);
    try std.testing.expect(!match(FinalTerms, &ctx, &consp, port_t, &b)); // a port is not a cons
}
