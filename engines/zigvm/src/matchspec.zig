//! beam-zig M11 / S23: **match specifications** (cf. erts erl_db_util.c
//! match programs) — reusing the M5 pattern algebra, exactly as the map
//! promised.
//!
//! A match spec denotes a partial function `Term -> ?Term`:
//!   head    — an M5 pattern (binds '$1'..'$8' → slots 0..7)
//!   guards  — a conjunction: the six FAST forms (comparisons + type tests) plus
//!             ANY richer guard (`andalso`/`orelse`/`not`, `element`/`tuple_size`,
//!             var-vs-var, arithmetic) COMPUTED over the shared eval kernel
//!             (gap-matchspec-guard-compute, DIVERGENCE 657)
//!   body    — '$_' (the whole object), '$N', or a tuple of '$N's
//!
//! Laws:
//!   DENOTATION      run(ms, t) ≡ (match head → θ) ∧ guards(θ) → body(θ),
//!                   composed from ALREADY-VERIFIED pieces (M5 match laws,
//!                   M4 order laws) — tested against a hand-rolled oracle
//!   GUARD PURITY    a failing guard yields null and leaves no observable
//!                   bindings (inherits M5 failure soundness)
//!   WHOLE BODY      body '$_' returns a term exact-equal to the subject
//!   GUARD SEMANTICS '>' / '<' are the ARITHMETIC order (==-family),
//!                   is_integer/is_atom/etc. are kind tests — both pinned
//!                   to the M4 observations
//!
//! E3.5: pid/reference/port need no new Guard variant here (mirrors E3.1's
//! bitstring, which also added no dedicated guard) — `eq_exact` already
//! covers exact-equality matching over the new kinds via `pat.match`'s
//! `plit`/`pvar` rules (see `pattern_algebra.zig`'s E3.5 note); a dedicated
//! `is_pid`/`is_reference`/`is_port` guard is Task 6-8 territory (the
//! entry-11 BIF ledger), not this term-kind slice.

const std = @import("std");
const ta = @import("term_algebra.zig");
const pat = @import("pattern_algebra.zig");
const eval = @import("eval.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

pub const Guard = union(enum) {
    is_integer: u8, //                    is_integer('$v')
    is_atom: u8,
    is_list: u8, //                       nil or cons
    gt: struct { v: u8, lit: FinalTerms.Term }, // '$v' > lit   (arithmetic)
    lt: struct { v: u8, lit: FinalTerms.Term },
    eq_exact: struct { v: u8, lit: FinalTerms.Term }, // '=:='
    // gap-matchspec-guard-compute (DIVERGENCE 657): any guard BEYOND the six fast
    // forms (`andalso`/`orelse`/`not`, `element`/`tuple_size` in a guard, var-vs-var
    // comparison, arithmetic) compiles to a COMPUTED expression over the SHARED
    // eval kernel (`src/eval.zig`, the same one bodies use since DIVERGENCE 632),
    // and PASSES iff it evaluates to the atom `true` (a raised guard exception →
    // fails the clause, exactly ETS). The six arms above stay fast projection paths.
    computed: *const eval.Expr,
};

pub const Body = union(enum) {
    whole, //                             '$_'
    variable: u8, //                      '$v'
    tuple_of: []const u8, //              {'$a', '$b', ...}
    // E-shared: a COMPUTED body — `{const,T}`, `{Op, Arg…}` value-function
    // calls, and construction over non-slot elements — delegated to the shared
    // expression evaluator (`src/eval.zig`). The three arms above stay as fast
    // projection paths (no evaluator, no true/false interning) for the pure
    // cases; anything that COMPUTES compiles to `.expr`.
    expr: *const eval.Expr,
};

pub const MatchSpec = struct {
    head: *const pat.Pattern(FinalTerms),
    guards: []const Guard,
    body: Body,
};

fn evalGuard(ctx: *FinalTerms.Ctx, g: Guard, b: *const pat.Bindings(FinalTerms), subject: FinalTerms.Term) error{OutOfMemory}!bool {
    switch (g) {
        // gap-matchspec-guard-compute (DIVERGENCE 657): evaluate the guard
        // expression over the shared eval kernel; PASS iff it yields the atom
        // `true`. A guard exception (`error.Exception`) fails the clause (→ false),
        // exactly ETS's guard-failure semantics.
        .computed => |e| {
            var ev = eval.Evaluator.init(ctx) catch return error.OutOfMemory;
            const r = ev.eval(e.*, b, subject) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Exception => return false,
            };
            return FinalTerms.kindOf(ctx, r) == .atom and std.mem.eql(u8, atomName(ctx, r) orelse "", "true");
        },
        .is_integer => |v| {
            const t = b.slots[v] orelse return false;
            return FinalTerms.kindOf(ctx, t) == .number and !FinalTerms.repIsFloat(ctx, t);
        },
        .is_atom => |v| {
            const t = b.slots[v] orelse return false;
            return FinalTerms.kindOf(ctx, t) == .atom;
        },
        .is_list => |v| {
            const t = b.slots[v] orelse return false;
            const k = FinalTerms.kindOf(ctx, t);
            return k == .nil or k == .cons;
        },
        .gt => |c| {
            const t = b.slots[c.v] orelse return false;
            return FinalTerms.compare(ctx, t, c.lit) == .gt; // arithmetic order
        },
        .lt => |c| {
            const t = b.slots[c.v] orelse return false;
            return FinalTerms.compare(ctx, t, c.lit) == .lt;
        },
        .eq_exact => |c| {
            const t = b.slots[c.v] orelse return false;
            return FinalTerms.eqlExact(ctx, t, c.lit);
        },
    }
}

/// THE observation: run a match spec on a subject.
pub fn run(ctx: *FinalTerms.Ctx, ms: *const MatchSpec, subject: FinalTerms.Term) !?FinalTerms.Term {
    var b = pat.Bindings(FinalTerms){};
    if (!pat.match(FinalTerms, ctx, ms.head, subject, &b)) return null;
    for (ms.guards) |g| {
        if (!try evalGuard(ctx, g, &b, subject)) return null;
    }
    return switch (ms.body) {
        .whole => subject,
        .variable => |v| b.slots[v].?,
        .tuple_of => |vs| blk: {
            var buf: [8]FinalTerms.Term = undefined;
            for (vs, 0..) |v, k| buf[k] = b.slots[v].?;
            break :blk try FinalTerms.tuple(ctx, buf[0..vs.len]);
        },
        // A computed body evaluates against the bindings + the whole subject
        // ('$_'). A body BIF that RAISES (`error.Exception`) DROPS the object —
        // exactly `ets:match_spec_run`'s body-exception semantics → `null`.
        .expr => |e| blk: {
            var ev = eval.Evaluator.init(ctx) catch return error.OutOfMemory;
            break :blk ev.eval(e.*, &b, subject) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Exception => return null,
            };
        },
    };
}

// ============================================================================
// E3.15 (S23): the runtime matchspec-TERM -> MatchSpec compiler
// ============================================================================
//
// ## Signature
//   compile        : (Ctx, arena, ms_term) -> []MatchSpec        (value bodies)
//   compilePredicate: (Ctx, arena, ms_term) -> []MatchSpec       (`[true]` body)
//   compileHead    : (Ctx, arena, head_term) -> HeadSpec         (match/2 form)
//   runMulti       : (Ctx, []MatchSpec, subject) -> ?Term        (first clause)
//
// The compiler is a TOTAL, REJECTING map from the ETS/`erl_db_util.c`
// match-spec TERM grammar (`[{Head, [Guard], [Body]}]` with `'$N'` variables,
// `'_'` wildcard, comparison/type-test guards, and `'$_'`/`'$N'`/tuple-of-vars
// bodies) INTO the ALREADY-LAW-COVERED M11 `MatchSpec` engine above — it adds
// NO matching semantics of its own (it emits `pat.Pattern` + `Guard` + `Body`,
// all run by the verified `run`). Malformed OR beyond-`MatchSpec`-expressiveness
// input is a clean `error.BadSpec` (the REJECTION law), never a panic.
//
// ## Bounded subset (documented DIVERGENCE, DIVERGENCE_LOG entry 13(b) amend)
// Because it compiles INTO the fixed `MatchSpec` (head pattern + the six guard
// forms + whole/variable/tuple-of-vars body), the compiler accepts exactly that
// subset of the full BEAM grammar:
//   - variables `'$1'..'$8'` -> slots 0..7 (`'$0'`/`'$9'+` -> BadSpec);
//   - guards: `{is_integer|is_atom|is_list, '$V'}` and
//     `{'>'|'<'|'=:=', '$V', Literal}` (arithmetic `>`/`<`, exact `=:=`);
//   - bodies: a ONE-element list `[E]` with `E` a match-spec BODY EXPRESSION —
//     `'$_'` (whole) | `'$N'` | a self-evaluating literal | `{const,T}` (opaque)
//     | `{{E1,…,En}}` tuple construction over sub-expressions | `{Op, Arg…}` a
//     value-function CALL. The COMPUTED forms (const / construction over
//     expressions / calls) delegate to the shared `eval.zig` kernel via the
//     `Body.expr` arm (E-shared wiring, DIVERGENCE 632); the pure projections
//     (`'$_'`, `'$N'`, `{{'$a',…}}` over bare slots) keep their fast paths.
//     `Op` is exactly `eval.opOfName` (`+ - *`, `== =:= /= =/= > >= < =<`,
//     `andalso orelse not xor and or`, `element tuple_size`).
// GUARDS now COMPUTE too (gap-matchspec-guard-compute, DIVERGENCE 657): any guard
// beyond the six fast `Guard` forms compiles to `.computed` over the SAME shared
// eval kernel as bodies (`andalso`/`orelse`/`not`, `element`/`tuple_size`,
// var-vs-var, arithmetic) and passes iff it yields `true`. STILL outside the
// subset (a documented `error.BadSpec`): a GENUINELY-unknown guard op, LIST/MAP
// construction in a body, `'$$'` in a select
// body, map heads, and an out-of-representable-range `'$N'` (a real ETS variable
// beyond zigvm's 8 slots). A `{NonOp, …}` single-brace body tuple is a call to a
// non-function → `BadSpec`, exactly ETS's compile-time badarg. `match/2`'s `'$$'`
// all-bindings body is served by `compileHead` at the BIF layer.

pub const CompileError = error{ BadSpec, OutOfMemory };

pub const HeadSpec = struct {
    head: *const pat.Pattern(FinalTerms),
    used: []const u8, // the variable slots that occur in `head`, ascending
};

const P = pat.Pattern(FinalTerms);

/// The used-variable bitset over the 8 representable slots.
const UsedSet = struct {
    bits: u8 = 0,
    fn add(self: *UsedSet, slot: u8) void {
        self.bits |= (@as(u8, 1) << @intCast(slot));
    }
    fn sorted(self: UsedSet, buf: *[pat.max_vars]u8) []u8 {
        var n: usize = 0;
        var i: u8 = 0;
        while (i < pat.max_vars) : (i += 1) {
            if (self.bits & (@as(u8, 1) << @intCast(i)) != 0) {
                buf[n] = i;
                n += 1;
            }
        }
        return buf[0..n];
    }
};

const AtomClass = union(enum) { slot: u8, whole, all, literal };

fn atomName(ctx: *FinalTerms.Ctx, t: FinalTerms.Term) ?[]const u8 {
    if (!FinalTerms.repIsAtom(t)) return null;
    return ctx.atoms.nameOf(FinalTerms.atomIdxOf(t));
}

/// Classify a match-spec atom: `'$N'` (slot N-1), `'$_'` (whole), `'$$'` (all
/// bindings), or an ordinary literal atom. `'_'` is handled by the caller
/// (it is a wildcard only in a HEAD, a literal atom elsewhere).
fn classifyAtom(name: []const u8) AtomClass {
    if (name.len >= 2 and name[0] == '$') {
        if (name.len == 2 and name[1] == '_') return .whole;
        if (name.len == 2 and name[1] == '$') return .all;
        var n: u32 = 0;
        for (name[1..]) |c| {
            if (c < '0' or c > '9') return .literal;
            n = n * 10 + (c - '0');
            if (n > 1000) return .literal; // way out of range; stop overflow
        }
        if (n >= 1 and n <= pat.max_vars) return .{ .slot = @intCast(n - 1) };
        return .literal; // '$0' or '$9'+ are out of the representable range
    }
    return .literal;
}

/// If `t` is a variable atom `'$N'`, its slot; else null.
fn argSlot(ctx: *FinalTerms.Ctx, t: FinalTerms.Term) ?u8 {
    const nm = atomName(ctx, t) orelse return null;
    return switch (classifyAtom(nm)) {
        .slot => |s| s,
        else => null,
    };
}

/// Is `t` one of the reserved match-spec atoms (`'$N'`/`'$_'`/`'$$'`)? Such a
/// term is never a plain guard/body literal.
fn isReservedAtom(ctx: *FinalTerms.Ctx, t: FinalTerms.Term) bool {
    const nm = atomName(ctx, t) orelse return false;
    return switch (classifyAtom(nm)) {
        .literal => false,
        else => true,
    };
}

fn compileHeadRec(
    ctx: *FinalTerms.Ctx,
    arena: std.mem.Allocator,
    term: FinalTerms.Term,
    used: *UsedSet,
) CompileError!*const P {
    const node = arena.create(P) catch return error.OutOfMemory;
    switch (FinalTerms.kindOf(ctx, term)) {
        .atom => {
            const nm = atomName(ctx, term).?;
            if (std.mem.eql(u8, nm, "_")) {
                node.* = .pwild;
                return node;
            }
            switch (classifyAtom(nm)) {
                .slot => |s| {
                    used.add(s);
                    node.* = .{ .pvar = s };
                },
                .whole, .all => return error.BadSpec, // body-only in a head
                .literal => node.* = .{ .plit = term },
            }
            return node;
        },
        .tuple => {
            const n = FinalTerms.tupleArity(ctx, term);
            const subs = arena.alloc(*const P, n) catch return error.OutOfMemory;
            var i: usize = 0;
            while (i < n) : (i += 1) {
                subs[i] = try compileHeadRec(ctx, arena, FinalTerms.tupleElem(ctx, term, i), used);
            }
            node.* = .{ .ptuple = subs };
            return node;
        },
        .cons => {
            const h = try compileHeadRec(ctx, arena, FinalTerms.listHead(ctx, term), used);
            const t = try compileHeadRec(ctx, arena, FinalTerms.listTail(ctx, term), used);
            node.* = .{ .pcons = .{ .h = h, .t = t } };
            return node;
        },
        .map => return error.BadSpec, // bounded: map heads are out of the subset
        // number/nil/binary/pid/ref/port/fun: exact-equality literals
        else => {
            node.* = .{ .plit = term };
            return node;
        },
    }
}

/// Compile a HEAD pattern in isolation (the `match/2`/`match_object/2` form),
/// returning the pattern plus its variables in ascending order (`'$$'`).
pub fn compileHead(ctx: *FinalTerms.Ctx, arena: std.mem.Allocator, term: FinalTerms.Term) CompileError!HeadSpec {
    var used = UsedSet{};
    const h = try compileHeadRec(ctx, arena, term, &used);
    var buf: [pat.max_vars]u8 = undefined;
    const owned = arena.dupe(u8, used.sorted(&buf)) catch return error.OutOfMemory;
    return .{ .head = h, .used = owned };
}

fn compileGuard(ctx: *FinalTerms.Ctx, arena: std.mem.Allocator, term: FinalTerms.Term) CompileError!Guard {
    // The six FAST guard forms: `{is_integer|is_atom|is_list, '$V'}` and
    // `{>|<|=:=, '$V', Literal}` — kept as no-eval projection paths.
    fast: {
        if (FinalTerms.kindOf(ctx, term) != .tuple) break :fast;
        const ar = FinalTerms.tupleArity(ctx, term);
        if (ar != 2 and ar != 3) break :fast;
        const op = atomName(ctx, FinalTerms.tupleElem(ctx, term, 0)) orelse break :fast;
        const vslot = argSlot(ctx, FinalTerms.tupleElem(ctx, term, 1)) orelse break :fast;
        if (ar == 2) {
            if (std.mem.eql(u8, op, "is_integer")) return .{ .is_integer = vslot };
            if (std.mem.eql(u8, op, "is_atom")) return .{ .is_atom = vslot };
            if (std.mem.eql(u8, op, "is_list")) return .{ .is_list = vslot };
            break :fast;
        }
        // ar == 3: comparison of a variable against a LITERAL (never another var).
        const lit = FinalTerms.tupleElem(ctx, term, 2);
        if (isReservedAtom(ctx, lit)) break :fast; // var/whole/all as literal
        if (std.mem.eql(u8, op, ">")) return .{ .gt = .{ .v = vslot, .lit = lit } };
        if (std.mem.eql(u8, op, "<")) return .{ .lt = .{ .v = vslot, .lit = lit } };
        if (std.mem.eql(u8, op, "=:=")) return .{ .eq_exact = .{ .v = vslot, .lit = lit } };
    }
    // gap-matchspec-guard-compute (DIVERGENCE 657): every richer guard —
    // `andalso`/`orelse`/`not`, `element`/`tuple_size` in a guard, var-vs-var
    // comparison, arithmetic — compiles to a COMPUTED expression over the shared
    // eval kernel (the same `compileExprE` bodies use). A genuinely malformed
    // guard is still `error.BadSpec` (compileExprE rejects it), never a panic.
    const node = arena.create(eval.Expr) catch return error.OutOfMemory;
    node.* = try compileExprE(ctx, arena, term);
    return .{ .computed = node };
}

fn compileGuards(
    ctx: *FinalTerms.Ctx,
    arena: std.mem.Allocator,
    guards_t: FinalTerms.Term,
) CompileError![]const Guard {
    var gs: std.ArrayList(Guard) = .empty;
    var cur = guards_t;
    while (FinalTerms.kindOf(ctx, cur) == .cons) {
        const g = try compileGuard(ctx, arena, FinalTerms.listHead(ctx, cur));
        gs.append(arena, g) catch return error.OutOfMemory;
        cur = FinalTerms.listTail(ctx, cur);
    }
    if (FinalTerms.kindOf(ctx, cur) != .nil) return error.BadSpec; // improper list
    return gs.toOwnedSlice(arena) catch return error.OutOfMemory;
}

/// Every element of the tuple `inner` is a bare `'$N'` variable (the pure-slot
/// projection fast path for `{{'$a','$b',…}}`).
fn allSlots(ctx: *FinalTerms.Ctx, inner: FinalTerms.Term) bool {
    const n = FinalTerms.tupleArity(ctx, inner);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (argSlot(ctx, FinalTerms.tupleElem(ctx, inner, i)) == null) return false;
    }
    return true;
}

/// A body ATOM as an `eval.Expr`: `'$_'` → whole, `'$1'..'$8'` → bound; `'$$'`
/// and an out-of-representable-range `'$N'` (a real ETS variable zigvm's 8 slots
/// can't hold) → an honest `BadSpec`; every other atom is a self-evaluating
/// LITERAL (`foo` → `[foo]`, matching the live engine).
fn bodyAtomExpr(nm: []const u8, term: FinalTerms.Term) CompileError!eval.Expr {
    if (nm.len >= 2 and nm[0] == '$') {
        if (nm.len == 2 and nm[1] == '_') return .whole;
        if (nm.len == 2 and nm[1] == '$') return error.BadSpec; // '$$' all-bindings body
        var all_digits = true;
        for (nm[1..]) |c| {
            if (c < '0' or c > '9') {
                all_digits = false;
                break;
            }
        }
        if (all_digits) {
            var n: u32 = 0;
            for (nm[1..]) |c| {
                n = n * 10 + (c - '0');
                if (n > 1000) break; // overflow guard (way out of range)
            }
            if (n >= 1 and n <= pat.max_vars) return .{ .bound = @intCast(n - 1) };
            return error.BadSpec; // an ETS variable beyond the 8 representable slots
        }
        // '$foo' etc. — not variable syntax → a literal atom.
    }
    return .{ .lit = term };
}

/// Compile a match-spec BODY expression TERM into a shared `eval.Expr`. Mirrors
/// the ETS `erl_db_util.c` MatchBody grammar for the value-function subset:
/// `'$N'`/`'$_'`/literal, `{const,T}` (opaque), `{{T}}` tuple construction, and
/// `{Op, Arg…}` calls (`Op` gated by `eval.opOfName`). List/map CONSTRUCTION and
/// `'$$'` are the documented deferred remainder (a clean `BadSpec`).
fn compileExprE(
    ctx: *FinalTerms.Ctx,
    arena: std.mem.Allocator,
    term: FinalTerms.Term,
) CompileError!eval.Expr {
    switch (FinalTerms.kindOf(ctx, term)) {
        .atom => return bodyAtomExpr(atomName(ctx, term).?, term),
        .tuple => {
            const ar = FinalTerms.tupleArity(ctx, term);
            // {const, X} → X verbatim (opaque — no descent into X).
            if (ar == 2) {
                if (atomName(ctx, FinalTerms.tupleElem(ctx, term, 0))) |op0| {
                    if (std.mem.eql(u8, op0, "const"))
                        return .{ .const_ = FinalTerms.tupleElem(ctx, term, 1) };
                }
            }
            // {{T}} → construct a tuple from the compiled elements of T.
            if (ar == 1) {
                const inner = FinalTerms.tupleElem(ctx, term, 0);
                if (FinalTerms.kindOf(ctx, inner) != .tuple) return error.BadSpec;
                const n = FinalTerms.tupleArity(ctx, inner);
                if (n > 8) return error.BadSpec; // representable arity bound
                const es = arena.alloc(eval.Expr, n) catch return error.OutOfMemory;
                var i: usize = 0;
                while (i < n) : (i += 1) es[i] = try compileExprE(ctx, arena, FinalTerms.tupleElem(ctx, inner, i));
                return .{ .tuple = es };
            }
            // {Op, Arg…} → a value-function call ('$N' or unknown-atom first
            // element is a call to a non-function in ETS → compile-time badarg).
            const op0 = atomName(ctx, FinalTerms.tupleElem(ctx, term, 0)) orelse return error.BadSpec;
            const op = eval.opOfName(op0) orelse return error.BadSpec;
            const na = ar - 1;
            const args = arena.alloc(eval.Expr, na) catch return error.OutOfMemory;
            var i: usize = 0;
            while (i < na) : (i += 1) args[i] = try compileExprE(ctx, arena, FinalTerms.tupleElem(ctx, term, i + 1));
            return .{ .call = .{ .op = op, .args = args } };
        },
        .cons, .nil => return error.BadSpec, // list construction — deferred remainder
        .map => return error.BadSpec, //        map construction — deferred remainder
        // number / binary / pid / ref / port / fun: a self-evaluating literal.
        else => return .{ .lit = term },
    }
}

/// Compile a body EXPRESSION into a `Body`. Pure projections (`'$_'`, `'$N'`,
/// `{{'$a',…}}` over bare slots) take the fast paths; anything that COMPUTES
/// ({const,_}, arithmetic, comparison, element, construction over expressions)
/// compiles to `.expr` and rides the shared `eval` kernel.
fn compileBodyExpr(
    ctx: *FinalTerms.Ctx,
    arena: std.mem.Allocator,
    expr: FinalTerms.Term,
) CompileError!Body {
    switch (FinalTerms.kindOf(ctx, expr)) {
        .atom => {
            const nm = atomName(ctx, expr).?;
            switch (classifyAtom(nm)) {
                .whole => return .whole, //          fast path
                .slot => |s| return .{ .variable = s }, // fast path
                .all => return error.BadSpec, //     '$$' select body -> compileHead
                .literal => {}, //                   a literal/variable atom → expr compiler
            }
        },
        .tuple => {
            // Fast path: `{{'$a','$b',…}}` pure-slot tuple construction.
            if (FinalTerms.tupleArity(ctx, expr) == 1) {
                const inner = FinalTerms.tupleElem(ctx, expr, 0);
                if (FinalTerms.kindOf(ctx, inner) == .tuple and allSlots(ctx, inner)) {
                    const n = FinalTerms.tupleArity(ctx, inner);
                    if (n <= pat.max_vars) {
                        const slots = arena.alloc(u8, n) catch return error.OutOfMemory;
                        var i: usize = 0;
                        while (i < n) : (i += 1) slots[i] = argSlot(ctx, FinalTerms.tupleElem(ctx, inner, i)).?;
                        return .{ .tuple_of = slots };
                    }
                }
            }
        },
        else => {}, // numbers/etc → the expr compiler (was BadSpec)
    }
    // COMPUTED body → the shared evaluator.
    const node = arena.create(eval.Expr) catch return error.OutOfMemory;
    node.* = try compileExprE(ctx, arena, expr);
    return .{ .expr = node };
}

/// A body list must contain EXACTLY one expression (`select`'s contract).
fn compileBody(ctx: *FinalTerms.Ctx, arena: std.mem.Allocator, body_t: FinalTerms.Term) CompileError!Body {
    if (FinalTerms.kindOf(ctx, body_t) != .cons) return error.BadSpec;
    const head = FinalTerms.listHead(ctx, body_t);
    if (FinalTerms.kindOf(ctx, FinalTerms.listTail(ctx, body_t)) != .nil) return error.BadSpec;
    return compileBodyExpr(ctx, arena, head);
}

/// Is the body list exactly `[true]` (the `select_count`/`select_delete`
/// predicate form)?
fn isTrueBody(ctx: *FinalTerms.Ctx, body_t: FinalTerms.Term) bool {
    if (FinalTerms.kindOf(ctx, body_t) != .cons) return false;
    const h = FinalTerms.listHead(ctx, body_t);
    if (FinalTerms.kindOf(ctx, FinalTerms.listTail(ctx, body_t)) != .nil) return false;
    const nm = atomName(ctx, h) orelse return false;
    return std.mem.eql(u8, nm, "true");
}

const BodyMode = enum { value, predicate };

fn compileClauseMode(
    ctx: *FinalTerms.Ctx,
    arena: std.mem.Allocator,
    clause_t: FinalTerms.Term,
    mode: BodyMode,
) CompileError!MatchSpec {
    if (FinalTerms.kindOf(ctx, clause_t) != .tuple or FinalTerms.tupleArity(ctx, clause_t) != 3)
        return error.BadSpec;
    var used = UsedSet{};
    const head = try compileHeadRec(ctx, arena, FinalTerms.tupleElem(ctx, clause_t, 0), &used);
    const guards = try compileGuards(ctx, arena, FinalTerms.tupleElem(ctx, clause_t, 1));
    const body_t = FinalTerms.tupleElem(ctx, clause_t, 2);
    const body: Body = switch (mode) {
        .value => try compileBody(ctx, arena, body_t),
        // A predicate clause KEEPS every matched object; its `[true]` body is
        // required (a non-`[true]` body would need a boolean body evaluator).
        .predicate => if (isTrueBody(ctx, body_t)) Body{ .whole = {} } else return error.BadSpec,
    };
    return .{ .head = head, .guards = guards, .body = body };
}

fn compileClauses(
    ctx: *FinalTerms.Ctx,
    arena: std.mem.Allocator,
    ms_term: FinalTerms.Term,
    mode: BodyMode,
) CompileError![]const MatchSpec {
    if (FinalTerms.kindOf(ctx, ms_term) != .cons) return error.BadSpec; // [] is not a spec
    var clauses: std.ArrayList(MatchSpec) = .empty;
    var cur = ms_term;
    while (FinalTerms.kindOf(ctx, cur) == .cons) {
        const ms = try compileClauseMode(ctx, arena, FinalTerms.listHead(ctx, cur), mode);
        clauses.append(arena, ms) catch return error.OutOfMemory;
        cur = FinalTerms.listTail(ctx, cur);
    }
    if (FinalTerms.kindOf(ctx, cur) != .nil) return error.BadSpec; // improper spec list
    return clauses.toOwnedSlice(arena) catch return error.OutOfMemory;
}

/// Compile a value-body match spec (`select`/`match_object`/`select_replace`).
pub fn compile(ctx: *FinalTerms.Ctx, arena: std.mem.Allocator, ms_term: FinalTerms.Term) CompileError![]const MatchSpec {
    return compileClauses(ctx, arena, ms_term, .value);
}

/// Compile a predicate match spec (`select_count`/`select_delete`; `[true]` body).
pub fn compilePredicate(ctx: *FinalTerms.Ctx, arena: std.mem.Allocator, ms_term: FinalTerms.Term) CompileError![]const MatchSpec {
    return compileClauses(ctx, arena, ms_term, .predicate);
}

/// Run a multi-clause spec on a subject: the FIRST clause that matches produces
/// (the `erl_db_util.c` clause-order semantics). `null` if none match.
pub fn runMulti(ctx: *FinalTerms.Ctx, clauses: []const MatchSpec, subject: FinalTerms.Term) !?FinalTerms.Term {
    for (clauses) |*ms| {
        if (try run(ctx, ms, subject)) |r| return r;
    }
    return null;
}

// ============================================================================
// E-shared: TRACE match specs — the trace-body ACTION functions (live_tracing)
// ============================================================================
//
// A trace match spec (`erlang:trace_pattern` / `erlang:match_spec_test(_,_,trace)`)
// runs against a call's ARGUMENT LIST. Its body is a sequence of ACTIONS folded
// left→right maintaining a running RESULT (default `true`) + a set of trace
// FLAGS, exactly `erl_db_util.c`'s trace program:
//   {message, E}        → RESULT := eval(E)                (the delivered message)
//   {return_trace}      → FLAG return_trace                (RESULT unchanged)
//   {exception_trace}   → FLAG exception_trace
//   anything else       → a NO-OP (RESULT unchanged)
// CRITICAL trace-vs-table distinction (a Rule-9 differential caught it): in a
// TRACE body only `{message,E}` sets the result — a bare value CALL like
// `{'+','$1','$2'}` is a NO-OP and the result stays the default `true` (whereas
// in a TABLE/select body that call's value IS the result). The `{message,E}`
// value evaluation delegates to the shared `eval` kernel; a raising body leaves
// the running result (match_spec_test tolerates it). Head-no-match OR a failing
// guard → `null` (the tester reports `{ok,false,[],[]}`).

pub const TraceFlag = enum { return_trace, exception_trace };

pub const TraceAction = union(enum) {
    set_result: *const eval.Expr, // {message,E} or a value expression
    flag: TraceFlag,
};

pub const TraceClause = struct {
    head: *const pat.Pattern(FinalTerms),
    guards: []const Guard,
    actions: []const TraceAction,
};

pub const TraceResult = struct {
    result: FinalTerms.Term,
    return_trace: bool = false,
    exception_trace: bool = false,
};

/// Compile a trace body list `[Action…]` into `[]TraceAction`.
fn compileTraceBody(ctx: *FinalTerms.Ctx, arena: std.mem.Allocator, body_t: FinalTerms.Term) CompileError![]const TraceAction {
    var acts: std.ArrayList(TraceAction) = .empty;
    var cur = body_t;
    while (FinalTerms.kindOf(ctx, cur) == .cons) {
        const e = FinalTerms.listHead(ctx, cur);
        cur = FinalTerms.listTail(ctx, cur);
        // {return_trace} / {exception_trace}: a 1-tuple whose element is the
        // action atom (distinct from {{…}} whose element is a TUPLE).
        if (FinalTerms.kindOf(ctx, e) == .tuple and FinalTerms.tupleArity(ctx, e) == 1) {
            if (atomName(ctx, FinalTerms.tupleElem(ctx, e, 0))) |nm| {
                if (std.mem.eql(u8, nm, "return_trace")) {
                    acts.append(arena, .{ .flag = .return_trace }) catch return error.OutOfMemory;
                    continue;
                }
                if (std.mem.eql(u8, nm, "exception_trace")) {
                    acts.append(arena, .{ .flag = .exception_trace }) catch return error.OutOfMemory;
                    continue;
                }
            }
        }
        // {message, E}: RESULT := eval(E).
        if (FinalTerms.kindOf(ctx, e) == .tuple and FinalTerms.tupleArity(ctx, e) == 2) {
            if (atomName(ctx, FinalTerms.tupleElem(ctx, e, 0))) |nm| {
                if (std.mem.eql(u8, nm, "message")) {
                    const node = arena.create(eval.Expr) catch return error.OutOfMemory;
                    node.* = try compileExprE(ctx, arena, FinalTerms.tupleElem(ctx, e, 1));
                    acts.append(arena, .{ .set_result = node }) catch return error.OutOfMemory;
                    continue;
                }
            }
        }
        // Anything else (a bare value call, literal, variable, {const}, {{…}})
        // is a NO-OP in a trace body — only {message,E} sets the result.
    }
    if (FinalTerms.kindOf(ctx, cur) != .nil) return error.BadSpec; // improper body list
    return acts.toOwnedSlice(arena) catch return error.OutOfMemory;
}

fn compileTraceClause(ctx: *FinalTerms.Ctx, arena: std.mem.Allocator, clause_t: FinalTerms.Term) CompileError!TraceClause {
    if (FinalTerms.kindOf(ctx, clause_t) != .tuple or FinalTerms.tupleArity(ctx, clause_t) != 3)
        return error.BadSpec;
    var used = UsedSet{};
    const head = try compileHeadRec(ctx, arena, FinalTerms.tupleElem(ctx, clause_t, 0), &used);
    const guards = try compileGuards(ctx, arena, FinalTerms.tupleElem(ctx, clause_t, 1));
    const actions = try compileTraceBody(ctx, arena, FinalTerms.tupleElem(ctx, clause_t, 2));
    return .{ .head = head, .guards = guards, .actions = actions };
}

/// Compile a TRACE match spec `[{Head,[Guard],[Action]}…]`.
pub fn compileTrace(ctx: *FinalTerms.Ctx, arena: std.mem.Allocator, ms_term: FinalTerms.Term) CompileError![]const TraceClause {
    if (FinalTerms.kindOf(ctx, ms_term) != .cons) return error.BadSpec;
    var clauses: std.ArrayList(TraceClause) = .empty;
    var cur = ms_term;
    while (FinalTerms.kindOf(ctx, cur) == .cons) {
        const c = try compileTraceClause(ctx, arena, FinalTerms.listHead(ctx, cur));
        clauses.append(arena, c) catch return error.OutOfMemory;
        cur = FinalTerms.listTail(ctx, cur);
    }
    if (FinalTerms.kindOf(ctx, cur) != .nil) return error.BadSpec;
    return clauses.toOwnedSlice(arena) catch return error.OutOfMemory;
}

/// Run a trace spec against `obj` (a call's argument list): the FIRST clause
/// whose head matches and whose guards hold produces a `TraceResult`; `null` if
/// none match (the tester reports `{ok,false,[],[]}`).
pub fn runTrace(ctx: *FinalTerms.Ctx, clauses: []const TraceClause, obj: FinalTerms.Term) !?TraceResult {
    var ev = eval.Evaluator.init(ctx) catch return error.OutOfMemory;
    for (clauses) |*c| {
        var b = pat.Bindings(FinalTerms){};
        if (!pat.match(FinalTerms, ctx, c.head, obj, &b)) continue;
        var guard_ok = true;
        for (c.guards) |g| {
            if (!(evalGuard(ctx, g, &b, obj) catch return error.OutOfMemory)) {
                guard_ok = false;
                break;
            }
        }
        if (!guard_ok) continue;
        var tr = TraceResult{ .result = FinalTerms.atom(ctx, ev.t_true) }; // default `true`
        for (c.actions) |act| switch (act) {
            .flag => |f| switch (f) {
                .return_trace => tr.return_trace = true,
                .exception_trace => tr.exception_trace = true,
            },
            .set_result => |e| {
                // A body BIF that raises leaves the running result untouched
                // (match_spec_test's tolerance), never a wrong term or a panic.
                tr.result = ev.eval(e.*, &b, obj) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Exception => tr.result,
                };
            },
        };
        return tr;
    }
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "Denotation: head+guard+body composes the verified pieces (oracle check)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();
    const cfg = LawConfig{ .seed = 0x3A7C };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    // ms: match {'$1', '$2'} when '$1' > 10 → {'$2', '$1'}
    const v0 = pat.Pattern(FinalTerms){ .pvar = 0 };
    const v1 = pat.Pattern(FinalTerms){ .pvar = 1 };
    const head = pat.Pattern(FinalTerms){ .ptuple = &.{ &v0, &v1 } };
    const ten = FinalTerms.int(&ctx, 10);
    const ms = MatchSpec{
        .head = &head,
        .guards = &.{.{ .gt = .{ .v = 0, .lit = ten } }},
        .body = .{ .tuple_of = &.{ 1, 0 } },
    };

    for (0..150) |i| {
        // random subjects: half are well-shaped pairs, half arbitrary
        const subject = if (random.boolean()) blk: {
            const a = FinalTerms.int(&ctx, @as(i64, random.int(i8)));
            const b_ = try ta.genTerm(FinalTerms, random, &ctx, 2);
            break :blk try FinalTerms.tuple(&ctx, &.{ a, b_ });
        } else try ta.genTerm(FinalTerms, random, &ctx, 3);

        const got = try run(&ctx, &ms, subject);

        // ORACLE: decide by hand from verified observations
        var expect: ?FinalTerms.Term = null;
        if (FinalTerms.kindOf(&ctx, subject) == .tuple and FinalTerms.tupleArity(&ctx, subject) == 2) {
            const e0 = FinalTerms.tupleElem(&ctx, subject, 0);
            const e1 = FinalTerms.tupleElem(&ctx, subject, 1);
            if (FinalTerms.compare(&ctx, e0, ten) == .gt)
                expect = try FinalTerms.tuple(&ctx, &.{ e1, e0 });
        }
        try expectLaw((got == null) == (expect == null), "matchspec: verdict equals the oracle", cfg, i);
        if (got != null) {
            try expectLaw(spec.eqlExact(
                try FinalTerms.denote(&ctx, sa, got.?),
                try FinalTerms.denote(&ctx, sa, expect.?),
            ), "matchspec: result equals the oracle", cfg, i);
        }
    }
}

test "Whole-body '$_' returns the subject; guards are kind- and order-true" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var prng = std.Random.DefaultPrng.init(0x3A7D);
    const random = prng.random();

    const v0 = pat.Pattern(FinalTerms){ .pvar = 0 };
    const ms_int = MatchSpec{ .head = &v0, .guards = &.{.{ .is_integer = 0 }}, .body = .whole };
    const ms_atom = MatchSpec{ .head = &v0, .guards = &.{.{ .is_atom = 0 }}, .body = .whole };

    for (0..120) |_| {
        const t = try ta.genTerm(FinalTerms, random, &ctx, 3);
        const is_int = FinalTerms.kindOf(&ctx, t) == .number and !FinalTerms.repIsFloat(&ctx, t);
        const is_atom = FinalTerms.kindOf(&ctx, t) == .atom;
        const r1 = try run(&ctx, &ms_int, t);
        const r2 = try run(&ctx, &ms_atom, t);
        try std.testing.expectEqual(is_int, r1 != null);
        try std.testing.expectEqual(is_atom, r2 != null);
        if (r1) |r| try std.testing.expect(FinalTerms.eqlExact(&ctx, r, t)); // '$_'
    }

    // 1 vs 1.0 at the guard boundary: is_integer('$1') distinguishes what
    // '>' (arithmetic) cannot
    const one_i = FinalTerms.int(&ctx, 1);
    const one_f = FinalTerms.float(&ctx, 1.0);
    try std.testing.expect((try run(&ctx, &ms_int, one_i)) != null);
    try std.testing.expect((try run(&ctx, &ms_int, one_f)) == null);
}

// ── E3.15 compiler laws ─────────────────────────────────────────────────────

/// Build a match-spec atom term by name.
fn tAtom(ctx: *FinalTerms.Ctx, name: []const u8) !FinalTerms.Term {
    return FinalTerms.atom(ctx, try ctx.atoms.intern(name));
}
fn tList(ctx: *FinalTerms.Ctx, items: []const FinalTerms.Term) !FinalTerms.Term {
    var acc = FinalTerms.nil(ctx);
    var i = items.len;
    while (i > 0) {
        i -= 1;
        acc = try FinalTerms.cons(ctx, items[i], acc);
    }
    return acc;
}

test "E3.15 COMPILER HOMOMORPHISM: run(compile(term), x) == the engine's denotation of the same spec built directly (two-var head kills mutant 1)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();
    const cfg = LawConfig{ .seed = 0x15C0 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    // DIRECT (oracle) spec: match {'$1','$2'} when '$1' > 10 -> {'$2','$1'}.
    const v0 = pat.Pattern(FinalTerms){ .pvar = 0 };
    const v1 = pat.Pattern(FinalTerms){ .pvar = 1 };
    const head_p = pat.Pattern(FinalTerms){ .ptuple = &.{ &v0, &v1 } };
    const ten = FinalTerms.int(&ctx, 10);
    const direct = MatchSpec{
        .head = &head_p,
        .guards = &.{.{ .gt = .{ .v = 0, .lit = ten } }},
        .body = .{ .tuple_of = &.{ 1, 0 } },
    };

    // TERM form of the SAME spec: [{{'$1','$2'}, [{'>','$1',10}], [{{'$2','$1'}}]}].
    const d1 = try tAtom(&ctx, "$1");
    const d2 = try tAtom(&ctx, "$2");
    const term_head = try FinalTerms.tuple(&ctx, &.{ d1, d2 });
    const guard = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, ">"), d1, ten });
    const body_tuple = try FinalTerms.tuple(&ctx, &.{try FinalTerms.tuple(&ctx, &.{ d2, d1 })}); // {{'$2','$1'}}
    const clause = try FinalTerms.tuple(&ctx, &.{ term_head, try tList(&ctx, &.{guard}), try tList(&ctx, &.{body_tuple}) });
    const ms_term = try tList(&ctx, &.{clause});

    var carena = std.heap.ArenaAllocator.init(gpa);
    defer carena.deinit();
    const compiled = try compile(&ctx, carena.allocator(), ms_term);
    try std.testing.expectEqual(@as(usize, 1), compiled.len);

    for (0..150) |i| {
        const subject = if (random.boolean()) blk: {
            const a = FinalTerms.int(&ctx, @as(i64, random.int(i8)));
            const b_ = FinalTerms.int(&ctx, @as(i64, random.int(i8)));
            break :blk try FinalTerms.tuple(&ctx, &.{ a, b_ });
        } else try ta.genTerm(FinalTerms, random, &ctx, 3);

        const got = try runMulti(&ctx, compiled, subject);
        const want = try run(&ctx, &direct, subject);
        try expectLaw((got == null) == (want == null), "compiler homomorphism: verdict agrees with the direct engine", cfg, i);
        if (got != null) {
            try expectLaw(spec.eqlExact(
                try FinalTerms.denote(&ctx, sa, got.?),
                try FinalTerms.denote(&ctx, sa, want.?),
            ), "compiler homomorphism: result agrees with the direct engine", cfg, i);
        }
    }
}

test "E3.15 COMPILER REJECTION: malformed / beyond-subset match-spec terms are a clean BadSpec, never a panic" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var carena = std.heap.ArenaAllocator.init(gpa);
    defer carena.deinit();
    const a = carena.allocator();

    const v1 = try tAtom(&ctx, "$1");
    const nilv = FinalTerms.nil(&ctx);
    const five = FinalTerms.int(&ctx, 5);

    // not a list -> BadSpec.
    try std.testing.expectError(error.BadSpec, compile(&ctx, a, five));
    // empty spec [] -> BadSpec (a spec must have >=1 clause).
    try std.testing.expectError(error.BadSpec, compile(&ctx, a, nilv));
    // clause not a 3-tuple.
    const bad_clause = try tList(&ctx, &.{try FinalTerms.tuple(&ctx, &.{ v1, nilv })});
    try std.testing.expectError(error.BadSpec, compile(&ctx, a, bad_clause));
    // gap-matchspec-guard-compute (DIVERGENCE 657): `>=` and var-vs-var `=:=` are
    // NOW SUPPORTED (they compile to a COMPUTED guard over the shared eval kernel),
    // no longer BadSpec — see the guard-compute law below. A guard with a
    // GENUINELY-UNKNOWN op is still rejected (compileExprE → BadSpec, never a panic).
    const g_bogus = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "no_such_guard_op"), v1, five });
    const c_bogus = try tList(&ctx, &.{try FinalTerms.tuple(&ctx, &.{ v1, try tList(&ctx, &.{g_bogus}), try tList(&ctx, &.{v1}) })});
    try std.testing.expectError(error.BadSpec, compile(&ctx, a, c_bogus));
    // body list must be a single element.
    const c_body2 = try tList(&ctx, &.{try FinalTerms.tuple(&ctx, &.{ v1, nilv, try tList(&ctx, &.{ v1, v1 }) })});
    try std.testing.expectError(error.BadSpec, compile(&ctx, a, c_body2));
    // '$_' (whole) is body-only; using it in a HEAD -> BadSpec.
    const whole = try tAtom(&ctx, "$_");
    const c_wholehead = try tList(&ctx, &.{try FinalTerms.tuple(&ctx, &.{ whole, nilv, try tList(&ctx, &.{v1}) })});
    try std.testing.expectError(error.BadSpec, compile(&ctx, a, c_wholehead));
    // out-of-range variable '$99' -> literal atom in head (never a slot); as a
    // BODY it is neither whole/slot/tuple -> BadSpec.
    const v99 = try tAtom(&ctx, "$99");
    const c_v99body = try tList(&ctx, &.{try FinalTerms.tuple(&ctx, &.{ v1, nilv, try tList(&ctx, &.{v99}) })});
    try std.testing.expectError(error.BadSpec, compile(&ctx, a, c_v99body));
    // improper spec list -> BadSpec.
    const good_clause = try FinalTerms.tuple(&ctx, &.{ v1, nilv, try tList(&ctx, &.{v1}) });
    const improper = try FinalTerms.cons(&ctx, good_clause, five);
    try std.testing.expectError(error.BadSpec, compile(&ctx, a, improper));

    // A WELL-FORMED spec compiles (positive control).
    _ = try compile(&ctx, a, try tList(&ctx, &.{good_clause}));
    // A `[true]` body compiles under BOTH modes now: predicate keeps the object,
    // and a VALUE body `[true]` is a self-evaluating literal atom (matching the
    // live `ets:match_spec_run`, which returns `[true]` — the E-shared wiring
    // corrected the old over-rejection of a bare-atom value body).
    const truebody = try tList(&ctx, &.{try FinalTerms.tuple(&ctx, &.{ v1, nilv, try tList(&ctx, &.{try tAtom(&ctx, "true")}) })});
    _ = try compilePredicate(&ctx, a, truebody);
    const true_val = try compile(&ctx, a, truebody);
    const one = FinalTerms.int(&ctx, 1);
    const r_true = try runMulti(&ctx, true_val, one); // head '$1' binds anything
    try std.testing.expect(r_true != null and FinalTerms.eqlExact(&ctx, r_true.?, try tAtom(&ctx, "true")));

    // A single-brace tuple whose first element is not a value-function atom is a
    // CALL to a non-function → ETS raises at compile time → BadSpec here too.
    const call_nonfn = try tList(&ctx, &.{try FinalTerms.tuple(&ctx, &.{ v1, nilv, try tList(&ctx, &.{try FinalTerms.tuple(&ctx, &.{ v1, v1 })}) })});
    try std.testing.expectError(error.BadSpec, compile(&ctx, a, call_nonfn));
    // '$99' as a body is a real ETS variable beyond zigvm's 8 slots → BadSpec
    // (NOT silently a literal atom — the honest unrepresentable-variable reject).
    // (already asserted above via c_v99body; re-stated here as the wiring's contract.)
}

test "LAW gap-matchspec-guard-compute (DIVERGENCE 657): a guard BEYOND the six fast forms — andalso/orelse, element-in-guard, arithmetic, var-vs-var — compiles to a COMPUTED guard over the shared eval kernel and filters correctly (was error.BadSpec); a genuinely-unknown guard op is still BadSpec" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const v1 = try tAtom(&ctx, "$1");
    const v2 = try tAtom(&ctx, "$2");
    const i = struct {
        fn f(c: *FinalTerms.Ctx, n: i64) FinalTerms.Term {
            return FinalTerms.int(c, n);
        }
    }.f;
    // build a one-clause spec [{Head, [Guard], [Body]}] and run one subject.
    const oneClause = struct {
        fn f(c: *FinalTerms.Ctx, ar: std.mem.Allocator, head: FinalTerms.Term, guard: FinalTerms.Term, body: FinalTerms.Term, subj: FinalTerms.Term) !?FinalTerms.Term {
            const clause = try FinalTerms.tuple(c, &.{ head, try tList(c, &.{guard}), try tList(c, &.{body}) });
            const ms = try compile(c, ar, try tList(c, &.{clause}));
            return runMulti(c, ms, subj);
        }
    }.f;

    // (1) andalso: keep {$1,$2} where 1 < $2 < 4 → body $1.
    const head_kv = try FinalTerms.tuple(&ctx, &.{ v1, v2 });
    const g_and = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "andalso"), try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, ">"), v2, i(&ctx, 1) }), try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "<"), v2, i(&ctx, 4) }) });
    const subj_b = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "b"), i(&ctx, 2) }); // passes
    const subj_d = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "d"), i(&ctx, 5) }); // fails (>=4)
    try std.testing.expect((try oneClause(&ctx, a, head_kv, g_and, v1, subj_b)) != null);
    try std.testing.expect((try oneClause(&ctx, a, head_kv, g_and, v1, subj_d)) == null);

    // (2) element-in-guard: {element,2,'$1'} > 1 over a whole-tuple head '$1'.
    const g_elem = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, ">"), try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "element"), i(&ctx, 2), v1 }), i(&ctx, 1) });
    const subj_c = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "c"), i(&ctx, 3) }); // elem 2 = 3 > 1 → pass
    const subj_a = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "a"), i(&ctx, 1) }); // elem 2 = 1, not > 1 → fail
    try std.testing.expect((try oneClause(&ctx, a, v1, g_elem, v1, subj_c)) != null);
    try std.testing.expect((try oneClause(&ctx, a, v1, g_elem, v1, subj_a)) == null);

    // (3) var-vs-var '=:=' '$1' '$1' is always true (a var equals itself).
    const g_vv = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "=:="), v1, v1 });
    try std.testing.expect((try oneClause(&ctx, a, v1, g_vv, v1, subj_a)) != null);

    // (4) a GENUINELY-unknown guard op is still a clean BadSpec, never a panic.
    const g_bogus = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "no_such_guard_op"), v1, i(&ctx, 1) });
    const clause_bogus = try FinalTerms.tuple(&ctx, &.{ v1, try tList(&ctx, &.{g_bogus}), try tList(&ctx, &.{v1}) });
    try std.testing.expectError(error.BadSpec, compile(&ctx, a, try tList(&ctx, &.{clause_bogus})));
}

test "LAW matchspec-body-eval: COMPUTED bodies compile+run byte-EQ vs the live ets:match_spec_run table" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var carena = std.heap.ArenaAllocator.init(gpa);
    defer carena.deinit();
    const a = carena.allocator();

    const d1 = try tAtom(&ctx, "$1");
    const d2 = try tAtom(&ctx, "$2");
    const head = try FinalTerms.tuple(&ctx, &.{ d1, d2 }); // {'$1','$2'}
    const subject = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 10), FinalTerms.int(&ctx, 3) }); // {10,3}

    // Build [{ {'$1','$2'}, [], [Body] }], compile it, run on {10,3}.
    const runBody = struct {
        fn f(c: *FinalTerms.Ctx, ar: std.mem.Allocator, h: FinalTerms.Term, body: FinalTerms.Term, subj: FinalTerms.Term) !?FinalTerms.Term {
            const clause = try FinalTerms.tuple(c, &.{ h, FinalTerms.nil(c), try tList(c, &.{body}) });
            const ms = try tList(c, &.{clause});
            const compiled = try compile(c, ar, ms);
            return runMulti(c, compiled, subj);
        }
    }.f;

    // {'+','$1','$2'} → 13   (the live ets:match_spec_run answer, fixtures/erl)
    const b_plus = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "+"), d1, d2 });
    try expectBody(&ctx, try runBody(&ctx, a, head, b_plus, subject), FinalTerms.int(&ctx, 13));
    // {'-','$1','$2'} → 7 ; {'*','$1','$2'} → 30
    const b_minus = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "-"), d1, d2 });
    try expectBody(&ctx, try runBody(&ctx, a, head, b_minus, subject), FinalTerms.int(&ctx, 7));
    const b_times = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "*"), d1, d2 });
    try expectBody(&ctx, try runBody(&ctx, a, head, b_times, subject), FinalTerms.int(&ctx, 30));
    // {{'$2','$1'}} → {3,10}   (COMPUTED construction with swapped slots via .expr;
    //  note: pure-slot construction ALSO hits this — proven equal to the fast path)
    const b_swap = try FinalTerms.tuple(&ctx, &.{try FinalTerms.tuple(&ctx, &.{ d2, d1 })});
    try expectBody(&ctx, try runBody(&ctx, a, head, b_swap, subject), try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 3), FinalTerms.int(&ctx, 10) }));
    // {element,1,{{'$1','$2'}}} → 10
    const inner_pair = try FinalTerms.tuple(&ctx, &.{try FinalTerms.tuple(&ctx, &.{ d1, d2 })});
    const b_elem = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "element"), FinalTerms.int(&ctx, 1), inner_pair });
    try expectBody(&ctx, try runBody(&ctx, a, head, b_elem, subject), FinalTerms.int(&ctx, 10));
    // {const,{a,b}} → {a,b}   (opaque)
    const ab = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "a"), try tAtom(&ctx, "b") });
    const b_const = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "const"), ab });
    try expectBody(&ctx, try runBody(&ctx, a, head, b_const, subject), ab);
    // {'+','$1',foo} → the body RAISES → the object is DROPPED (null), exactly
    // match_spec_run's body-exception semantics.
    const b_bad = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "+"), d1, try tAtom(&ctx, "foo") });
    try std.testing.expect((try runBody(&ctx, a, head, b_bad, subject)) == null);
}

fn expectBody(ctx: *FinalTerms.Ctx, got: ?FinalTerms.Term, want: FinalTerms.Term) !void {
    try std.testing.expect(got != null);
    try std.testing.expect(FinalTerms.eqlExact(ctx, got.?, want));
}

test "LAW matchspec-trace-actions: trace-body actions match the live match_spec_test(_,_,trace) table" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var carena = std.heap.ArenaAllocator.init(gpa);
    defer carena.deinit();
    const a = carena.allocator();

    const d1 = try tAtom(&ctx, "$1");
    const d2 = try tAtom(&ctx, "$2");
    const headL = try tList(&ctx, &.{ d1, d2 }); // ['$1','$2']
    const obj = try tList(&ctx, &.{ FinalTerms.int(&ctx, 10), FinalTerms.int(&ctx, 3) }); // [10,3]
    const tru = try tAtom(&ctx, "true");

    // Build a one-clause trace spec [{['$1','$2'], Guards, Body}] and run it.
    const run1 = struct {
        fn f(c: *FinalTerms.Ctx, ar: std.mem.Allocator, h: FinalTerms.Term, gs: FinalTerms.Term, body: FinalTerms.Term, o: FinalTerms.Term) !?TraceResult {
            const clause = try FinalTerms.tuple(c, &.{ h, gs, try tList(c, &.{body}) });
            const cl = try compileTrace(c, ar, try tList(c, &.{clause}));
            return runTrace(c, cl, o);
        }
    }.f;
    const runBody2 = struct { // a body list with TWO actions
        fn f(c: *FinalTerms.Ctx, ar: std.mem.Allocator, h: FinalTerms.Term, b1: FinalTerms.Term, b2: FinalTerms.Term, o: FinalTerms.Term) !?TraceResult {
            const clause = try FinalTerms.tuple(c, &.{ h, FinalTerms.nil(c), try tList(c, &.{ b1, b2 }) });
            const cl = try compileTrace(c, ar, try tList(c, &.{clause}));
            return runTrace(c, cl, o);
        }
    }.f;
    const nil_ = FinalTerms.nil(&ctx);

    // plainbody [{'+','$1','$2'}] → {ok,TRUE,[],[]}: in a TRACE body a bare
    // value call is a NO-OP (result stays true), UNLIKE a table body where it
    // would be 13. (A Rule-9 differential vs live match_spec_test caught this.)
    const b_plus = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "+"), d1, d2 });
    {
        const tr = (try run1(&ctx, a, headL, nil_, b_plus, obj)).?;
        try std.testing.expect(FinalTerms.eqlExact(&ctx, tr.result, tru) and !tr.return_trace and !tr.exception_trace);
    }
    // {message,{'+','$1','$2'}} → 13, no flags
    const b_msg = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "message"), b_plus });
    {
        const tr = (try run1(&ctx, a, headL, nil_, b_msg, obj)).?;
        try std.testing.expect(FinalTerms.eqlExact(&ctx, tr.result, FinalTerms.int(&ctx, 13)));
    }
    // {message,false} → false
    const b_msgf = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, "message"), try tAtom(&ctx, "false") });
    {
        const tr = (try run1(&ctx, a, headL, nil_, b_msgf, obj)).?;
        try std.testing.expect(FinalTerms.eqlExact(&ctx, tr.result, try tAtom(&ctx, "false")));
    }
    // {return_trace} → result true, flag return_trace
    const b_ret = try FinalTerms.tuple(&ctx, &.{try tAtom(&ctx, "return_trace")});
    {
        const tr = (try run1(&ctx, a, headL, nil_, b_ret, obj)).?;
        try std.testing.expect(FinalTerms.eqlExact(&ctx, tr.result, tru) and tr.return_trace and !tr.exception_trace);
    }
    // [true] → true, no flags
    {
        const tr = (try run1(&ctx, a, headL, nil_, tru, obj)).?;
        try std.testing.expect(FinalTerms.eqlExact(&ctx, tr.result, tru) and !tr.return_trace);
    }
    // guard fail {'>','$1',100} → no match (null)
    const g_gt = try FinalTerms.tuple(&ctx, &.{ try tAtom(&ctx, ">"), d1, FinalTerms.int(&ctx, 100) });
    try std.testing.expect((try run1(&ctx, a, headL, try tList(&ctx, &.{g_gt}), tru, obj)) == null);
    // head no match ['a','b'] vs [10,3] → null
    const headAB = try tList(&ctx, &.{ try tAtom(&ctx, "a"), try tAtom(&ctx, "b") });
    try std.testing.expect((try run1(&ctx, a, headAB, nil_, tru, obj)) == null);
    // multi [{message,'$2'},{return_trace}] → result 3, flag return_trace
    {
        const tr = (try runBody2(&ctx, a, headL, b_msg2(&ctx, a, d2) catch unreachable, b_ret, obj)).?;
        try std.testing.expect(FinalTerms.eqlExact(&ctx, tr.result, FinalTerms.int(&ctx, 3)) and tr.return_trace);
    }
    // bothflags [{return_trace},{exception_trace}] → true, both flags
    {
        const b_exc = try FinalTerms.tuple(&ctx, &.{try tAtom(&ctx, "exception_trace")});
        const tr = (try runBody2(&ctx, a, headL, b_ret, b_exc, obj)).?;
        try std.testing.expect(FinalTerms.eqlExact(&ctx, tr.result, tru) and tr.return_trace and tr.exception_trace);
    }
}

fn b_msg2(c: *FinalTerms.Ctx, ar: std.mem.Allocator, v: FinalTerms.Term) !FinalTerms.Term {
    _ = ar;
    return FinalTerms.tuple(c, &.{ try tAtom(c, "message"), v });
}
