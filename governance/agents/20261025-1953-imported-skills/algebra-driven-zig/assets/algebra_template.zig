//! TEMPLATE: minimal complete Algebra-Driven Design module (Zig 0.14+).
//! Domain shown: alert **Severity** — the smallest real algebra: a
//! bounded semilattice (assoc + comm + idem + identity) under "worst wins".
//!
//! To adapt: replace Severity/Level with your domain, rewrite the ⟦·⟧ lines,
//! keep the file's shape and the law suite intact. Semantic domain:
//!   ⟦Severity⟧ ≙ Level   (ordered; combine = max)
//!   ⟦none⟧            = .ok
//!   ⟦at(l)⟧           = l
//!   ⟦worst(a, b)⟧     = max(⟦a⟧, ⟦b⟧)

const std = @import("std");

// ============================================================================
// PART 1: SIGNATURE
// ============================================================================

pub const Level = enum(u8) { ok = 0, warn = 1, err = 2, fatal = 3 };

pub fn requireSeverityAlgebra(comptime T: type) void {
    comptime {
        const required = .{ "Severity", "none", "at", "worst", "level", "eql" };
        for (required) |name| {
            if (!@hasDecl(T, name))
                @compileError(@typeName(T) ++ " violates the Severity signature: missing decl `" ++ name ++ "`");
        }
        if (@TypeOf(T.at) != fn (Level) T.Severity)
            @compileError(@typeName(T) ++ ": `at` must be `fn (Level) Severity`");
        if (@TypeOf(T.level) != fn (T.Severity) Level)
            @compileError(@typeName(T) ++ ": `level` (the observation) must be `fn (Severity) Level`");
    }
}

// ============================================================================
// PART 2: SEMANTIC DOMAIN — here so small it IS a Level; eql is ==.
// ============================================================================

// ============================================================================
// PART 3a: INITIAL ENCODING (the oracle)
// ============================================================================

pub const SeverityInitial = struct {
    pub const Severity = union(enum) {
        none,
        at: Level,
        worst: struct { a: *const Severity, b: *const Severity },
    };

    pub fn none() Severity {
        return .none;
    }
    pub fn at(l: Level) Severity {
        return .{ .at = l };
    }

    /// Arena-owned nodes: build, observe, drop as a unit. Caller owns the arena.
    pub fn worst(arena: std.mem.Allocator, a: Severity, b: Severity) !Severity {
        const pa = try arena.create(Severity);
        const pb = try arena.create(Severity);
        pa.* = a;
        pb.* = b;
        return .{ .worst = .{ .a = pa, .b = pb } };
    }

    /// The observation ⟦·⟧ — exhaustive switch, no else arm.
    pub fn level(self: Severity) Level {
        return switch (self) {
            .none => .ok,
            .at => |l| l,
            .worst => |p| maxLevel(level(p.a.*), level(p.b.*)),
        };
    }

    /// Observational equality (doctrine rule 1).
    pub fn eql(a: Severity, b: Severity) bool {
        return level(a) == level(b);
    }
};

// ============================================================================
// PART 3b: FINAL ENCODING (efficient; derived from the denotation)
// ============================================================================

pub const SeverityFinal = struct {
    pub const Severity = Level; // the denotation itself

    pub fn none() Severity {
        return .ok;
    }
    pub fn at(l: Level) Severity {
        return l;
    }
    /// Takes and ignores the allocator so one law suite covers both encodings.
    pub fn worst(_: std.mem.Allocator, a: Severity, b: Severity) !Severity {
        return maxLevel(a, b);
    }
    pub fn level(self: Severity) Level {
        return self;
    }
    pub fn eql(a: Severity, b: Severity) bool {
        return a == b;
    }
};

fn maxLevel(a: Level, b: Level) Level {
    return if (@intFromEnum(a) >= @intFromEnum(b)) a else b;
}

// ============================================================================
// PART 4: LAWS — bounded semilattice (see references/algebra-catalog.md)
// ============================================================================

fn randomLevel(random: std.Random) Level {
    return random.enumValue(Level);
}

pub fn genSeverity(
    comptime Impl: type,
    random: std.Random,
    arena: std.mem.Allocator,
    depth: usize,
) !Impl.Severity {
    const Variant = enum { none, at, worst };
    const pick: Variant = if (depth == 0)
        (if (random.boolean()) .none else .at)
    else
        random.enumValue(Variant);
    return switch (pick) {
        .none => Impl.none(),
        .at => Impl.at(randomLevel(random)),
        .worst => try Impl.worst(
            arena,
            try genSeverity(Impl, random, arena, depth - 1),
            try genSeverity(Impl, random, arena, depth - 1),
        ),
    };
}

pub const LawConfig = struct {
    iterations: usize = 200,
    max_depth: usize = 5,
    seed: u64 = 0xADD_0_CAFE,
};

fn expectLaw(ok: bool, name: []const u8, cfg: LawConfig, iter: usize) !void {
    if (!ok) {
        std.debug.print("LAW FAILED: {s} (seed=0x{x}, iteration={d}, depth={d})\n", .{ name, cfg.seed, iter, cfg.max_depth });
        return error.LawViolated;
    }
}

pub fn verifySemilatticeLaws(comptime Impl: type, gpa: std.mem.Allocator, cfg: LawConfig) !void {
    comptime requireSeverityAlgebra(Impl);
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const x = try genSeverity(Impl, random, arena, cfg.max_depth);
        const y = try genSeverity(Impl, random, arena, cfg.max_depth);
        const z = try genSeverity(Impl, random, arena, cfg.max_depth);
        const e = Impl.none();

        try expectLaw(Impl.eql(try Impl.worst(arena, e, x), x), "left identity", cfg, i);
        try expectLaw(Impl.eql(try Impl.worst(arena, x, e), x), "right identity", cfg, i);
        const lhs = try Impl.worst(arena, try Impl.worst(arena, x, y), z);
        const rhs = try Impl.worst(arena, x, try Impl.worst(arena, y, z));
        try expectLaw(Impl.eql(lhs, rhs), "associativity", cfg, i);
        try expectLaw(Impl.eql(try Impl.worst(arena, x, y), try Impl.worst(arena, y, x)), "commutativity", cfg, i);
        try expectLaw(Impl.eql(try Impl.worst(arena, x, x), x), "idempotence", cfg, i);
    }
}

pub fn verifyHomomorphism(gpa: std.mem.Allocator, cfg: LawConfig) !void {
    var prng_a = std.Random.DefaultPrng.init(cfg.seed);
    var prng_b = std.Random.DefaultPrng.init(cfg.seed);
    for (0..cfg.iterations) |_| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const deep = try genSeverity(SeverityInitial, prng_a.random(), arena, cfg.max_depth);
        const shallow = try genSeverity(SeverityFinal, prng_b.random(), arena, cfg.max_depth);
        try std.testing.expect(SeverityInitial.level(deep) == SeverityFinal.level(shallow));
    }
}

test "Laws: Initial encoding is a bounded semilattice" {
    try verifySemilatticeLaws(SeverityInitial, std.testing.allocator, .{});
}

test "Laws: Final encoding is a bounded semilattice" {
    try verifySemilatticeLaws(SeverityFinal, std.testing.allocator, .{});
}

test "Homomorphism: encodings denote the same algebra" {
    try verifyHomomorphism(std.testing.allocator, .{});
}

test "Doctrine guard: laws are observational, not structural" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const x = SeverityInitial.at(.warn);
    const wrapped = try SeverityInitial.worst(arena, SeverityInitial.none(), x);
    // Structurally different trees...
    try std.testing.expect(std.meta.activeTag(wrapped) != std.meta.activeTag(x));
    // ...observationally equal — exactly what left identity asserts.
    try std.testing.expect(SeverityInitial.eql(wrapped, x));
}
