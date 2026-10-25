# Zig mechanics for algebraic code

The Haskell→Zig translation table, then the load-bearing patterns with exact
code. All snippets compile on Zig 0.14–0.16 unless flagged; §7 covers version
drift.

## Contents
1. Translation table
2. Comptime signature contracts
3. Tagged-union initial encodings & arena ownership
4. Property-based testing (generators, seeds, shrinking)
5. The twin-seed homomorphism pattern
6. Generic algebra modules (`fn (comptime T: type) type`)
7. Version-drift pitfalls & running tests anywhere
8. Performance notes

## 1. Translation table

| Book concept (Haskell) | Zig idiom | Why |
|---|---|---|
| Typeclass / signature | `requireXAlgebra(comptime T: type)` comptime assertion | Zero runtime cost, checked at instantiation of the law suite |
| Typeclass instance | Plain namespace struct with `pub fn`s | Duck-typed; contract enforces shape |
| GADT / initial encoding | `union(enum)` with `*const Self` recursion | Explicit layout, exhaustive `switch` |
| Final/tagless encoding | Struct holding the denotation directly | Operations compute eagerly |
| `Monoid a` dictionary | Comptime-known namespace passed as `comptime Impl: type` | Monomorphized per algebra |
| QuickCheck `Arbitrary` | `genX(Impl, random, arena, depth)` using the algebra's own constructors | Terms are well-typed by construction |
| QuickCheck property | Loop in a `test` block asserting the equation on generated terms | `std.testing.expect` + seed echo |
| `===` up to observation | `Impl.eql(a, b)` = compare denotations | Doctrine rule 1 |
| GC'd AST nodes | `std.heap.ArenaAllocator`, build-observe-drop | Leak-free under `std.testing.allocator` |

Runtime polymorphism (vtables) is almost never needed: law suites and
homomorphism tests select the implementation at comptime. Reach for a vtable
only if implementations must be swapped at *runtime* behind one pointer type.

## 2. Comptime signature contracts

Diagnose, don't gatekeep — named `@compileError` per violation, checking
presence **and** shape:

```zig
pub fn requireCanvasAlgebra(comptime T: type) void {
    comptime {
        const required = .{ "Canvas", "empty", "fill", "overlay", "rasterize", "eql" };
        for (required) |name| {
            if (!@hasDecl(T, name))
                @compileError(@typeName(T) ++ " violates the Canvas signature: missing decl `" ++ name ++ "`");
        }
        if (@TypeOf(T.fill) != fn (Pixel) T.Canvas)
            @compileError(@typeName(T) ++ ": `fill` must be `fn (Pixel) Canvas`");
        if (@TypeOf(T.rasterize) != fn (T.Canvas) Raster)
            @compileError(@typeName(T) ++ ": `rasterize` must be `fn (Canvas) Raster`");
        // Allocating ops have error unions with inferred sets; check param/return
        // pieces via @typeInfo(@TypeOf(T.overlay)).@"fn" when exact fn-type
        // comparison is too strict.
    }
}
```

Call it at the top of every generic law function
(`comptime requireCanvasAlgebra(Impl);`) so misuse fails at the *use site*
with a message naming the offending type. Verify the negative case once per
project: a deliberately broken impl must produce the readable error.

For heavy comptime loops (large signatures, generated law grids) raise the
budget: `@setEvalBranchQuota(10_000);` inside the `comptime` block.

## 3. Tagged-union initial encodings & arena ownership

```zig
pub const CanvasInitial = struct {
    pub const Canvas = union(enum) {
        empty,                       // void payload: construct with `.empty`
        fill: Pixel,
        overlay: struct { top: *const Canvas, bottom: *const Canvas },
    };

    pub fn empty() Canvas { return .empty; }
    pub fn fill(px: Pixel) Canvas { return .{ .fill = px }; }

    /// Nodes are arena-owned: expressions are built, observed, dropped as a
    /// unit. No per-node deinit exists — the caller owns the arena.
    pub fn overlay(arena: std.mem.Allocator, top: Canvas, bottom: Canvas) !Canvas {
        const t = try arena.create(Canvas);
        const b = try arena.create(Canvas);
        t.* = top; b.* = bottom;
        return .{ .overlay = .{ .top = t, .bottom = b } };
    }

    pub fn rasterize(self: Canvas) Raster {   // exhaustive: no else arm
        return switch (self) {
            .empty => Raster.blank,
            .fill => |px| Raster.uniform(px),
            .overlay => |p| Raster.over(rasterize(p.top.*), rasterize(p.bottom.*)),
        };
    }

    pub fn eql(a: Canvas, b: Canvas) bool {   // observational — doctrine rule 1
        return rasterize(a).eql(rasterize(b));
    }
};
```

Notes:
- Recursive union fields must be pointers (`*const Canvas`); a union cannot
  contain itself by value.
- Keep the non-allocating signature uniform across encodings: a final
  encoding's `overlay` takes and ignores the allocator
  (`pub fn overlay(_: std.mem.Allocator, ...) !Canvas`) so one generic law
  suite covers both.
- Depth-bounded generators (§4) keep interpreter recursion shallow; for
  user-supplied deep terms, convert the interpreter to an explicit work-list
  if stack depth becomes a concern.
- Propagate `error.OutOfMemory`; never `catch unreachable` in library code.

Test-side ownership — arena per iteration, leak-checked for free:

```zig
for (0..cfg.iterations) |_| {
    var arena_state = std.heap.ArenaAllocator.init(gpa); // gpa = std.testing.allocator
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // ... generate terms, assert laws ...
}
```

## 4. Property-based testing

**Generator** — always through the algebra's own constructors (terms are
well-typed by construction), depth-bounded, deterministic given PRNG state:

```zig
pub fn genCanvas(comptime Impl: type, random: std.Random,
                 arena: std.mem.Allocator, depth: usize) !Impl.Canvas {
    const Variant = enum { empty, fill, overlay };
    const pick: Variant = if (depth == 0)
        (if (random.boolean()) .empty else .fill)   // leaves only at the bound
    else
        random.enumValue(Variant);
    return switch (pick) {
        .empty => Impl.empty(),
        .fill => Impl.fill(randomPixel(random)),
        .overlay => try Impl.overlay(arena,
            try genCanvas(Impl, random, arena, depth - 1),
            try genCanvas(Impl, random, arena, depth - 1)),
    };
}
```

Generator quality (the book's "Writing Good Generators"): every variant must
be reachable; recursive picks must shrink `depth` so termination is
structural; weight leaf variants up if interesting small terms are being
drowned out; generate *payloads* across the full range (`random.int(u8)`, not
three hand-picked constants).

**Law suite** — one generic function, laws transcribed 1:1 from the design
note, fixed default seed:

```zig
pub const LawConfig = struct {
    iterations: usize = 200,
    max_depth: usize = 5,
    seed: u64 = 0xADD_0_CAFE,
};

pub fn verifyMonoidLaws(comptime Impl: type, gpa: std.mem.Allocator, cfg: LawConfig) !void {
    comptime requireCanvasAlgebra(Impl);
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();
    for (0..cfg.iterations) |i| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const x = try genCanvas(Impl, random, arena, cfg.max_depth);
        const e = Impl.empty();
        expectLaw(Impl.eql(try Impl.overlay(arena, e, x), x),
                  "left identity", cfg.seed, i) catch |err| return err;
        // ... remaining laws ...
    }
}

fn expectLaw(ok: bool, name: []const u8, seed: u64, iter: usize) !void {
    if (!ok) {
        std.debug.print("LAW FAILED: {s} (seed=0x{x}, iteration={d})\n", .{ name, seed, iter });
        return error.LawViolated;
    }
}
```

**Shrinking** — Zig has no QuickCheck shrinker; approximate it cheaply and
honestly: on failure, rerun the failing law with the same seed at
`max_depth = 0, 1, 2, ...` and report the smallest depth that still fails.
Minimal-depth counterexamples are usually small enough to read. Print enough
(seed, iteration, depth, and the two denotations) that the human can
reconstruct the term.

**Failure semantics**: a red law against the initial encoding indicts the
*law or semantic domain*; against the final encoding only, it indicts the
final implementation; homomorphism red with both law suites green means the
encodings disagree on term *shape* handling — check the generator twins (§5).

## 5. The twin-seed homomorphism pattern

Two PRNGs with the same seed make identical choices, so the same term shape is
built through both encodings without any shared IR:

```zig
var prng_a = std.Random.DefaultPrng.init(cfg.seed);
var prng_b = std.Random.DefaultPrng.init(cfg.seed);
for (0..cfg.iterations) |_| {
    // arena per iteration as usual
    const deep    = try genCanvas(CanvasInitial, prng_a.random(), arena, cfg.max_depth);
    const shallow = try genCanvas(CanvasFinal,   prng_b.random(), arena, cfg.max_depth);
    try std.testing.expect(CanvasInitial.rasterize(deep).eql(CanvasFinal.rasterize(shallow)));
}
```

This only stays sound if the generator consumes randomness identically for
both `Impl`s — which it does automatically when there is exactly one generator
generic over `Impl` (never write per-encoding generators).

## 6. Generic algebra modules

When the generalization gate (methodology §5) fires, promote the module:

```zig
pub fn RegionAlgebra(comptime Payload: type, comptime domain_size: usize) type {
    return struct {
        pub const Denotation = struct { cells: [domain_size]?Payload, ... };
        // signature, encodings, laws — all closed over Payload
    };
}
```

Law suites stay generic over `Impl` exactly as before; instantiate the tests
for two different `Payload`s to catch accidental payload assumptions.

## 7. Version-drift pitfalls & running tests anywhere

Zig's std reorganizes between minor versions. **Always run `zig version`
first and compile with the user's actual toolchain.** Known drift relevant to
this skill:

| Area | Old (≤0.12/0.13) | Current (0.14–0.16) |
|---|---|---|
| PRNG | `std.rand.DefaultPrng` | `std.Random.DefaultPrng` |
| ArrayList | managed, `list.append(x)` | unmanaged default: `var l: std.ArrayList(T) = .empty; l.append(gpa, x); l.deinit(gpa)` |
| Array fill | `[_]T{v} ** n` still works | `@splat(v)` preferred, works for nested via `@splat(@splat(v))` |
| `usingnamespace` | available | **removed** — write explicit decls |
| I/O in examples | `std.io.getStdOut()` | `std.debug.print` for test/debug output; std.Io API in flux — avoid in library code |
| Void-payload union construction | `.{ .empty = {} }` | `.empty` (enum-literal coercion) |

Do not memorize further; when in doubt `grep` the installed std
(`<zig>/lib/std/`) or compile a 5-line probe.

Running tests:
- Local toolchain: `zig test file.zig`
- No toolchain (e.g. sandboxed container):
  `pip install ziglang --break-system-packages && python3 -m ziglang test file.zig`
  (official Zig distribution on PyPI). `scripts/run_zig_tests.sh` automates the
  fallback.
- `std.testing.allocator` doubles as the leak detector — a leaking suite
  *fails*, which is why arena-per-iteration is mandatory, not stylistic.

## 8. Performance notes

- The initial encoding is the oracle, not the product: production call paths
  use the final encoding; keep the AST compiled only under
  `@import("builtin").is_test` if binary size matters.
- Tabulated denotations are plain arrays → element-wise combinator loops
  auto-vectorize; for hot paths consider `@Vector` explicitly, but only after
  the law suite is green (optimizations are algebraic rewrites, cite the law).
- Comptime contracts and monomorphized law suites cost zero at runtime;
  `union(enum)` pattern matching compiles to a jump table.
- If terms must be built at scale in production (not just tests), size the
  arena with `ArenaAllocator` retention or a `FixedBufferAllocator` over a
  measured budget; term size is `O(nodes)` with no hidden allocations.
