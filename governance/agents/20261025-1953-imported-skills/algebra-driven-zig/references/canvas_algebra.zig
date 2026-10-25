//! Algebra-Driven Design reference module (Zig 0.16) — Spatial Canvas domain.
//!
//! Structure:
//!   PART 1  Signature      — comptime-enforced interface contract
//!   PART 2  Semantics      — the shared denotation (Raster) all encodings map into
//!   PART 3  Interpretations— Initial (AST) and Final (direct) encodings
//!   PART 4  Axioms & Laws  — property-based tests over random expressions,
//!                            plus an encoding-homomorphism test
//!
//! Key doctrine correction vs. naive ADD ports:
//!   Algebraic laws such as `overlay(empty, x) == x` hold DENOTATIONALLY,
//!   not structurally. In an initial encoding, `overlay(empty, x)` is an
//!   `.overlay` AST node and is never structurally equal to `x`. Equality in
//!   the signature is therefore *observational*: both sides are interpreted
//!   into the semantic domain (a Raster) and compared there.

const std = @import("std");

// ============================================================================
// PART 1: THE SIGNATURE
// ============================================================================

pub const Pixel = struct { r: u8, g: u8, b: u8 };

/// Logical grid of the semantic domain. Small on purpose: laws quantify over
/// all cells, so an 8x8 raster is a total (not sampled) observation.
pub const grid_w: usize = 8;
pub const grid_h: usize = 8;

/// Compile-time structural contract. Emits a *diagnosable* error per missing
/// or malformed primitive instead of a boolean, so violations name themselves.
pub fn requireCanvasAlgebra(comptime T: type) void {
    comptime {
        const required = .{ "Canvas", "empty", "fill", "overlay", "rasterize", "eql" };
        for (required) |name| {
            if (!@hasDecl(T, name)) {
                @compileError(@typeName(T) ++ " violates the Canvas signature: missing decl `" ++ name ++ "`");
            }
        }
        // Shape checks beyond mere presence.
        if (@TypeOf(T.fill) != fn (Pixel) T.Canvas)
            @compileError(@typeName(T) ++ ": `fill` must be `fn (Pixel) Canvas`");
        if (@TypeOf(T.empty) != fn () T.Canvas)
            @compileError(@typeName(T) ++ ": `empty` must be `fn () Canvas`");
        if (@TypeOf(T.rasterize) != fn (T.Canvas) Raster)
            @compileError(@typeName(T) ++ ": `rasterize` must be `fn (Canvas) Raster`");
    }
}

// ============================================================================
// PART 2: THE SEMANTIC DOMAIN (shared denotation)
// ============================================================================

/// Denotation of a Canvas: a total function grid -> ?Pixel, tabulated.
/// `null` means "transparent / unpainted"; `overlay` is top-wins-if-painted.
pub const Raster = struct {
    cells: [grid_w * grid_h]?Pixel,

    pub const blank = Raster{ .cells = @splat(null) };

    pub fn uniform(px: Pixel) Raster {
        return .{ .cells = @splat(px) };
    }

    /// Semantic overlay: per-cell, top if painted, else bottom.
    pub fn over(top: Raster, bottom: Raster) Raster {
        var out: Raster = undefined;
        for (&out.cells, top.cells, bottom.cells) |*o, t, b| {
            o.* = t orelse b;
        }
        return out;
    }

    pub fn eql(a: Raster, b: Raster) bool {
        return std.meta.eql(a.cells, b.cells);
    }
};

// ============================================================================
// PART 3a: INITIAL ENCODING (AST via tagged union) — deep embedding
// ============================================================================

pub const CanvasInitial = struct {
    pub const Canvas = union(enum) {
        empty,
        fill: Pixel,
        overlay: struct { top: *const Canvas, bottom: *const Canvas },
    };

    pub fn empty() Canvas {
        return .empty;
    }

    pub fn fill(px: Pixel) Canvas {
        return .{ .fill = px };
    }

    /// Nodes are intended for arena allocation: expressions are built, observed,
    /// and dropped as a unit. Callers own the arena; no per-node deinit exists.
    pub fn overlay(arena: std.mem.Allocator, top: Canvas, bottom: Canvas) !Canvas {
        const t = try arena.create(Canvas);
        const b = try arena.create(Canvas);
        t.* = top;
        b.* = bottom;
        return .{ .overlay = .{ .top = t, .bottom = b } };
    }

    /// The interpreter: folds the AST into the semantic domain.
    /// Exhaustive over every variant — no wildcard arms.
    pub fn rasterize(self: Canvas) Raster {
        return switch (self) {
            .empty => Raster.blank,
            .fill => |px| Raster.uniform(px),
            .overlay => |pair| Raster.over(rasterize(pair.top.*), rasterize(pair.bottom.*)),
        };
    }

    /// Observational equality: laws are judged in the denotation, never on
    /// AST shape. (Structural equality would falsify every monoid law.)
    pub fn eql(a: Canvas, b: Canvas) bool {
        return rasterize(a).eql(rasterize(b));
    }
};

// ============================================================================
// PART 3b: FINAL ENCODING (direct execution) — shallow embedding
// ============================================================================

pub const CanvasFinal = struct {
    pub const Canvas = Raster;

    pub fn empty() Canvas {
        return Raster.blank;
    }

    pub fn fill(px: Pixel) Canvas {
        return Raster.uniform(px);
    }

    /// Accepts (and ignores) an allocator so both encodings share one
    /// call shape; the final encoding is allocation-free by construction.
    pub fn overlay(_: std.mem.Allocator, top: Canvas, bottom: Canvas) !Canvas {
        return Raster.over(top, bottom);
    }

    pub fn rasterize(self: Canvas) Raster {
        return self;
    }

    pub fn eql(a: Canvas, b: Canvas) bool {
        return a.eql(b);
    }
};

// ============================================================================
// PART 4: AXIOMS & PROPERTY-BASED LAWS
// ============================================================================

fn randomPixel(random: std.Random) Pixel {
    return .{ .r = random.int(u8), .g = random.int(u8), .b = random.int(u8) };
}

/// Generator: random well-typed expression of bounded depth, built through the
/// implementation's own constructors. Deterministic given the PRNG state, so
/// two encodings driven by identically-seeded PRNGs build the *same* term.
pub fn genCanvas(
    comptime Impl: type,
    random: std.Random,
    arena: std.mem.Allocator,
    depth: usize,
) !Impl.Canvas {
    const Variant = enum { empty, fill, overlay };
    const pick: Variant = if (depth == 0)
        // Leaves only at the depth bound.
        if (random.boolean()) .empty else .fill
    else
        random.enumValue(Variant);

    return switch (pick) {
        .empty => Impl.empty(),
        .fill => Impl.fill(randomPixel(random)),
        .overlay => try Impl.overlay(
            arena,
            try genCanvas(Impl, random, arena, depth - 1),
            try genCanvas(Impl, random, arena, depth - 1),
        ),
    };
}

pub const LawConfig = struct {
    iterations: usize = 200,
    max_depth: usize = 5,
    seed: u64 = 0xADD_0_CAFE,
};

/// Monoid laws for (Canvas, overlay, empty), plus idempotence — a law this
/// particular semantics also satisfies. Every assertion is observational.
pub fn verifyMonoidLaws(comptime Impl: type, gpa: std.mem.Allocator, cfg: LawConfig) !void {
    comptime requireCanvasAlgebra(Impl);

    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |_| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const x = try genCanvas(Impl, random, arena, cfg.max_depth);
        const y = try genCanvas(Impl, random, arena, cfg.max_depth);
        const z = try genCanvas(Impl, random, arena, cfg.max_depth);
        const e = Impl.empty();

        // Law 1: left identity   — overlay(empty, x) == x
        try std.testing.expect(Impl.eql(try Impl.overlay(arena, e, x), x));
        // Law 2: right identity  — overlay(x, empty) == x
        try std.testing.expect(Impl.eql(try Impl.overlay(arena, x, e), x));
        // Law 3: associativity   — overlay(overlay(x, y), z) == overlay(x, overlay(y, z))
        const lhs = try Impl.overlay(arena, try Impl.overlay(arena, x, y), z);
        const rhs = try Impl.overlay(arena, x, try Impl.overlay(arena, y, z));
        try std.testing.expect(Impl.eql(lhs, rhs));
        // Law 4: idempotence     — overlay(x, x) == x
        try std.testing.expect(Impl.eql(try Impl.overlay(arena, x, x), x));
    }
}

/// The ADD keystone: both interpretations denote the same algebra.
/// Identically-seeded generators build the same term in each encoding; their
/// rasters must agree cell-for-cell on every iteration.
pub fn verifyEncodingHomomorphism(gpa: std.mem.Allocator, cfg: LawConfig) !void {
    comptime requireCanvasAlgebra(CanvasInitial);
    comptime requireCanvasAlgebra(CanvasFinal);

    var prng_a = std.Random.DefaultPrng.init(cfg.seed);
    var prng_b = std.Random.DefaultPrng.init(cfg.seed);

    for (0..cfg.iterations) |_| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const deep = try genCanvas(CanvasInitial, prng_a.random(), arena, cfg.max_depth);
        const shallow = try genCanvas(CanvasFinal, prng_b.random(), arena, cfg.max_depth);

        try std.testing.expect(CanvasInitial.rasterize(deep).eql(CanvasFinal.rasterize(shallow)));
    }
}

// ----------------------------------------------------------------------------
// Verification suite
// ----------------------------------------------------------------------------

test "Laws: Initial encoding satisfies monoid + idempotence (observationally)" {
    try verifyMonoidLaws(CanvasInitial, std.testing.allocator, .{});
}

test "Laws: Final encoding satisfies monoid + idempotence" {
    try verifyMonoidLaws(CanvasFinal, std.testing.allocator, .{});
}

test "Homomorphism: Initial and Final encodings denote the same algebra" {
    try verifyEncodingHomomorphism(std.testing.allocator, .{});
}

test "Doctrine guard: structural equality must NOT be used to judge laws" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const x = CanvasInitial.fill(.{ .r = 1, .g = 2, .b = 3 });
    const wrapped = try CanvasInitial.overlay(arena, CanvasInitial.empty(), x);

    // Structurally different trees...
    try std.testing.expect(std.meta.activeTag(wrapped) != std.meta.activeTag(x));
    // ...yet observationally equal — exactly what the identity law asserts.
    try std.testing.expect(CanvasInitial.eql(wrapped, x));
}
