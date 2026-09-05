//! beam-zig / S-shared: the **expression evaluator** — the pure kernel both
//! `-eval` (erl_cli_surface) and match-spec BODIES (live_tracing) bottom out on.
//!
//! ## Signature
//!   denote : Expr × Env → Term ⊎ {exception}
//!     Env    = a `pat.Bindings` (`'$1'..'$8'` → slots 0..7) + the whole object
//!     Expr   = a term-tree over literals / bound variables / the ETS
//!              match-spec body grammar (`{const,T}`, `{{...}}` construction,
//!              `{Op, Arg…}` value-function calls)
//!     result = a Term, or the {exception} bottom — a body BIF that RAISES
//!              (badarith / badarg / bounds) denotes ⊥; in `ets:match_spec_run`
//!              a ⊥ body DROPS the object, so `null` is the honest encoding.
//!
//! ## Oracle vs final (a SEMANTIC-PRECURSOR / interpreter slice)
//! This is a tree interpreter: the obviously-correct *oracle* is the recursive
//! `eval` fold below, and there is (yet) no distinct efficient *final* encoding
//! worth admitting by a homomorphism against it — a compiled match-program /
//! threaded body is a later slice. Per `ALGEBRAIC_FRACTAL_RULES.md`, a
//! semantic-precursor slice SAYS SO and still ships laws; the binding law here
//! is the **live differential**: `eval(compile(Body), θ)` must be byte-equal to
//! the pinned OTP-30 `ets:match_spec_run([Obj], compile([{Head,[],[Body]}]))`
//! (`test/law "differential"` mirrors the captured oracle table). That external
//! equality is the real homomorphism — not a self-check against our own oracle.
//!
//! ## Laws
//!   DENOTATION      eval of a hand-built Expr over an env equals the term the
//!                   match-spec semantics assign it (in-process oracle table)
//!   EXCEPTION-⊥     a raising body BIF (`'+'(int,atom)`, `element` OOB) denotes
//!                   `null`, never a panic and never a wrong term (TOTALITY)
//!   CONST-OPACITY   `{const,T}` returns T VERBATIM — no descent, so a `{const,
//!                   {'$1',b}}` does NOT substitute `'$1'` (the ETS `const` law)
//!   DIFFERENTIAL    byte-EQ vs LIVE `ets:match_spec_run` for the op battery
//!
//! ## Scope (increment 1 — documented remainder)
//! Covered ops: arithmetic `+ - *`, comparison `== =:= /= =/= > >= < =<`,
//! boolean `andalso orelse not xor and or`, structural `element tuple_size`,
//! plus `{const,_}` and `{{…}}` construction. Deferred (a follow-on, kept an
//! honest EQUIV remainder in the ledger): `div rem band bor abs` and the rest
//! of the guard-BIF set, `hd/tl/self/node/map_get`, `'$*'`/`'$$'` in a select
//! body, and the full `erl_eval` surface (`case`/`fun`/list-comp) that `-eval`
//! ultimately needs. This kernel is the SHARED spine those consumers extend.

const std = @import("std");
const ta = @import("term_algebra.zig");
const pat = @import("pattern_algebra.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const AtomIdx = ta.AtomIdx;

/// The value-function operators of the match-spec body grammar (increment 1).
pub const Op = enum {
    plus,
    minus,
    times,
    eq, //        '=='   (number-coercing term equality)
    eq_exact, //  '=:='
    ne, //        '/='
    ne_exact, //  '=/='
    gt, //        '>'
    ge, //        '>='
    lt, //        '<'
    le, //        '=<'
    andalso_, //  short-circuit
    orelse_, //   short-circuit
    not_,
    xor_,
    and_,
    or_,
    element, //   element(N, Tuple)
    tuple_size, // tuple_size(Tuple)
};

/// Map a match-spec value-function atom name to its `Op`, or null if it is not
/// a recognized operator (so a `{Foo, …}` body tuple with an unknown `Foo` is a
/// clean rejection at the compile boundary, mirroring ETS's compile-time badarg
/// on a non-function first element). This keeps the op grammar OWNED by eval —
/// the match-spec body compiler consults it rather than duplicating the table.
pub fn opOfName(nm: []const u8) ?Op {
    const eql = std.mem.eql;
    if (eql(u8, nm, "+")) return .plus;
    if (eql(u8, nm, "-")) return .minus;
    if (eql(u8, nm, "*")) return .times;
    if (eql(u8, nm, "==")) return .eq;
    if (eql(u8, nm, "=:=")) return .eq_exact;
    if (eql(u8, nm, "/=")) return .ne;
    if (eql(u8, nm, "=/=")) return .ne_exact;
    if (eql(u8, nm, ">")) return .gt;
    if (eql(u8, nm, ">=")) return .ge;
    if (eql(u8, nm, "<")) return .lt;
    if (eql(u8, nm, "=<")) return .le;
    if (eql(u8, nm, "andalso")) return .andalso_;
    if (eql(u8, nm, "orelse")) return .orelse_;
    if (eql(u8, nm, "not")) return .not_;
    if (eql(u8, nm, "xor")) return .xor_;
    if (eql(u8, nm, "and")) return .and_;
    if (eql(u8, nm, "or")) return .or_;
    if (eql(u8, nm, "element")) return .element;
    if (eql(u8, nm, "tuple_size")) return .tuple_size;
    return null;
}

/// A match-spec / erl_eval expression over an 8-slot binding environment.
pub const Expr = union(enum) {
    lit: FinalTerms.Term, //          a self-evaluating literal
    bound: u8, //                     '$N' → env.slots[N]
    whole, //                         '$_' → the matched object
    const_: FinalTerms.Term, //       {const,T} → T verbatim (opaque, no descent)
    tuple: []const Expr, //           {{E1,…,En}} → a tuple of the evaluated Es
    call: Call,

    pub const Call = struct { op: Op, args: []const Expr };
};

pub const EvalError = error{ Exception, OutOfMemory };

/// The evaluator: a `Ctx` plus the two boolean-atom indices it returns.
pub const Evaluator = struct {
    ctx: *FinalTerms.Ctx,
    t_true: AtomIdx,
    t_false: AtomIdx,

    pub fn init(ctx: *FinalTerms.Ctx) !Evaluator {
        return .{
            .ctx = ctx,
            .t_true = try ctx.atoms.intern("true"),
            .t_false = try ctx.atoms.intern("false"),
        };
    }

    fn boolT(self: *const Evaluator, b: bool) FinalTerms.Term {
        return FinalTerms.atom(self.ctx, if (b) self.t_true else self.t_false);
    }

    /// The Zig bool a `true`/`false` atom denotes, else `error.Exception`
    /// (a boolean op applied to a non-boolean raises in the match-spec engine).
    fn asBool(self: *const Evaluator, t: FinalTerms.Term) EvalError!bool {
        if (!FinalTerms.repIsAtom(t)) return error.Exception;
        const idx = FinalTerms.atomIdxOf(t);
        if (idx == self.t_true) return true;
        if (idx == self.t_false) return false;
        return error.Exception;
    }

    /// THE observation — `denote(e, env)`; `error.Exception` is the ⊥ bottom.
    pub fn eval(
        self: *const Evaluator,
        e: Expr,
        env: *const pat.Bindings(FinalTerms),
        whole: ?FinalTerms.Term,
    ) EvalError!FinalTerms.Term {
        const ctx = self.ctx;
        switch (e) {
            .lit => |t| return t,
            .const_ => |t| return t, // opaque: NO descent (the ETS `const` law)
            .whole => return whole orelse error.Exception,
            .bound => |n| {
                if (n >= pat.max_vars) return error.Exception;
                return env.slots[n] orelse error.Exception;
            },
            .tuple => |es| {
                if (es.len > 8) return error.Exception; // representable arity bound
                var buf: [8]FinalTerms.Term = undefined;
                for (es, 0..) |sub, k| buf[k] = try self.eval(sub, env, whole);
                return FinalTerms.tuple(ctx, buf[0..es.len]) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                };
            },
            .call => |c| return self.evalCall(c, env, whole),
        }
    }

    fn evalCall(
        self: *const Evaluator,
        c: Expr.Call,
        env: *const pat.Bindings(FinalTerms),
        whole: ?FinalTerms.Term,
    ) EvalError!FinalTerms.Term {
        const ctx = self.ctx;
        // Short-circuit boolean ops evaluate their SECOND arg lazily.
        switch (c.op) {
            .andalso_ => {
                if (c.args.len != 2) return error.Exception;
                const a = try self.asBool(try self.eval(c.args[0], env, whole));
                if (!a) return self.boolT(false);
                return self.boolT(try self.asBool(try self.eval(c.args[1], env, whole)));
            },
            .orelse_ => {
                if (c.args.len != 2) return error.Exception;
                const a = try self.asBool(try self.eval(c.args[0], env, whole));
                if (a) return self.boolT(true);
                return self.boolT(try self.asBool(try self.eval(c.args[1], env, whole)));
            },
            else => {},
        }
        // Strict ops: evaluate all args first (left→right).
        var argbuf: [3]FinalTerms.Term = undefined;
        if (c.args.len > argbuf.len) return error.Exception;
        for (c.args, 0..) |sub, k| argbuf[k] = try self.eval(sub, env, whole);
        const a = argbuf;
        switch (c.op) {
            .plus, .minus, .times => {
                if (c.args.len != 2) return error.Exception;
                // arithmetic BIFs RAISE on a non-number operand — the match-spec
                // engine type-checks first, and FinalTerms.add/mul assert numeric
                // (they panic otherwise), so reject to ⊥ here (TOTALITY).
                if (FinalTerms.kindOf(ctx, a[0]) != .number or
                    FinalTerms.kindOf(ctx, a[1]) != .number) return error.Exception;
                return switch (c.op) {
                    .plus => FinalTerms.add(ctx, a[0], a[1]),
                    .minus => FinalTerms.add(ctx, a[0], try negate(ctx, a[1])),
                    .times => FinalTerms.mul(ctx, a[0], a[1]),
                    else => unreachable,
                } catch |err| switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.Badarith => error.Exception,
                };
            },
            .eq, .ne, .gt, .ge, .lt, .le => {
                if (c.args.len != 2) return error.Exception;
                const ord = FinalTerms.compare(ctx, a[0], a[1]);
                return self.boolT(switch (c.op) {
                    .eq => ord == .eq,
                    .ne => ord != .eq,
                    .gt => ord == .gt,
                    .ge => ord != .lt,
                    .lt => ord == .lt,
                    .le => ord != .gt,
                    else => unreachable,
                });
            },
            .eq_exact, .ne_exact => {
                if (c.args.len != 2) return error.Exception;
                const ex = FinalTerms.eqlExact(ctx, a[0], a[1]);
                return self.boolT(if (c.op == .eq_exact) ex else !ex);
            },
            .not_ => {
                if (c.args.len != 1) return error.Exception;
                return self.boolT(!(try self.asBool(a[0])));
            },
            .xor_, .and_, .or_ => {
                if (c.args.len != 2) return error.Exception;
                const x = try self.asBool(a[0]);
                const y = try self.asBool(a[1]);
                return self.boolT(switch (c.op) {
                    .xor_ => x != y,
                    .and_ => x and y,
                    .or_ => x or y,
                    else => unreachable,
                });
            },
            .element => {
                // element(N, Tuple) — 1-based; OOB / non-tuple / non-int → ⊥
                if (c.args.len != 2) return error.Exception;
                if (FinalTerms.kindOf(ctx, a[1]) != .tuple) return error.Exception;
                const n = intVal(a[0]) orelse return error.Exception;
                if (n < 1) return error.Exception;
                const idx: usize = @intCast(n);
                if (idx > FinalTerms.tupleArity(ctx, a[1])) return error.Exception;
                return FinalTerms.tupleElem(ctx, a[1], idx - 1);
            },
            .tuple_size => {
                if (c.args.len != 1) return error.Exception;
                if (FinalTerms.kindOf(ctx, a[0]) != .tuple) return error.Exception;
                return FinalTerms.int(ctx, @intCast(FinalTerms.tupleArity(ctx, a[0])));
            },
            .andalso_, .orelse_ => unreachable, // handled above
        }
    }
};

fn negate(ctx: *FinalTerms.Ctx, w: FinalTerms.Term) EvalError!FinalTerms.Term {
    return FinalTerms.negate(ctx, w) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
    };
}

/// A small-integer term's i64 value, or null if it is not a representable
/// small integer (a bignum index / non-integer is out of `element`'s honest
/// range for this increment → ⊥).
fn intVal(w: FinalTerms.Term) ?i64 {
    if (!FinalTerms.repIsSmall(w)) return null;
    return FinalTerms.smallValOf(w);
}

// ============================================================================
// Laws
// ============================================================================

const TestCtx = struct {
    atoms: AtomTable,
    ctx: FinalTerms.Ctx,
    fn deinit(self: *TestCtx) void {
        self.ctx.deinit();
        self.atoms.deinit();
    }
};

fn call(op: Op, args: []const Expr) Expr {
    return .{ .call = .{ .op = op, .args = args } };
}

test "LAW eval-denotation: hand-built exprs over an env equal the oracle terms" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var ev = try Evaluator.init(&ctx);

    // env: $1=10, $2=3   (the oracle probe subject {10,3})
    var env = pat.Bindings(FinalTerms){};
    env.slots[0] = FinalTerms.int(&ctx, 10);
    env.slots[1] = FinalTerms.int(&ctx, 3);
    const whole = try FinalTerms.tuple(&ctx, &.{ env.slots[0].?, env.slots[1].? });

    const v1 = Expr{ .bound = 0 };
    const v2 = Expr{ .bound = 1 };

    // {'+','$1','$2'} = 13
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(call(.plus, &.{ v1, v2 }), &env, whole), FinalTerms.int(&ctx, 13)));
    // {'-','$1','$2'} = 7
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(call(.minus, &.{ v1, v2 }), &env, whole), FinalTerms.int(&ctx, 7)));
    // {'*','$1','$2'} = 30
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(call(.times, &.{ v1, v2 }), &env, whole), FinalTerms.int(&ctx, 30)));
    // {{'$2','$1'}} = {3,10}
    const swap = Expr{ .tuple = &.{ v2, v1 } };
    const expect_swap = try FinalTerms.tuple(&ctx, &.{ env.slots[1].?, env.slots[0].? });
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(swap, &env, whole), expect_swap));
    // {'>','$1','$2'} = true ; {'=:=','$1','$1'} = true ; {'<','$1','$2'} = false
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(call(.gt, &.{ v1, v2 }), &env, whole), ev.boolT(true)));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(call(.eq_exact, &.{ v1, v1 }), &env, whole), ev.boolT(true)));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(call(.lt, &.{ v1, v2 }), &env, whole), ev.boolT(false)));
    // {andalso,{'>','$1','$2'},{'<','$2',100}} = true (short-circuit)
    const g1 = call(.gt, &.{ v1, v2 });
    const g2 = call(.lt, &.{ v2, .{ .lit = FinalTerms.int(&ctx, 100) } });
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(call(.andalso_, &.{ g1, g2 }), &env, whole), ev.boolT(true)));
    // {element,1,{{'$1','$2'}}} = 10
    const built = Expr{ .tuple = &.{ v1, v2 } };
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(call(.element, &.{ .{ .lit = FinalTerms.int(&ctx, 1) }, built }), &env, whole), FinalTerms.int(&ctx, 10)));
    // {tuple_size, {{'$1','$2'}}} = 2
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(call(.tuple_size, &.{built}), &env, whole), FinalTerms.int(&ctx, 2)));
    // '$_' = {10,3}
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(.whole, &env, whole), whole));
}

test "LAW eval-exception-bottom: a raising body BIF denotes ⊥ (null), never a panic" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var ev = try Evaluator.init(&ctx);

    var env = pat.Bindings(FinalTerms){};
    env.slots[0] = FinalTerms.int(&ctx, 10);
    const foo = FinalTerms.atom(&ctx, try ctx.atoms.intern("foo"));
    env.slots[1] = foo;
    const v1 = Expr{ .bound = 0 };
    const v2 = Expr{ .bound = 1 };

    // {'+','$1',foo} raises badarith → ⊥
    try std.testing.expectError(error.Exception, ev.eval(call(.plus, &.{ v1, v2 }), &env, null));
    // element(5, {10,foo}) out of bounds → ⊥
    const pair = Expr{ .tuple = &.{ v1, v2 } };
    try std.testing.expectError(error.Exception, ev.eval(call(.element, &.{ .{ .lit = FinalTerms.int(&ctx, 5) }, pair }), &env, null));
    // andalso with a non-boolean first arg → ⊥
    try std.testing.expectError(error.Exception, ev.eval(call(.andalso_, &.{ v1, v1 }), &env, null));
    // '$_' with no whole object → ⊥
    try std.testing.expectError(error.Exception, ev.eval(.whole, &env, null));
    // an unbound slot → ⊥
    try std.testing.expectError(error.Exception, ev.eval(Expr{ .bound = 5 }, &env, null));
}

test "LAW eval-const-opacity: {const,T} returns T verbatim, no substitution" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var ev = try Evaluator.init(&ctx);

    var env = pat.Bindings(FinalTerms){};
    env.slots[0] = FinalTerms.int(&ctx, 10);

    // {const, {a,b}} → {a,b} verbatim
    const a = FinalTerms.atom(&ctx, try ctx.atoms.intern("a"));
    const b = FinalTerms.atom(&ctx, try ctx.atoms.intern("b"));
    const ab = try FinalTerms.tuple(&ctx, &.{ a, b });
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try ev.eval(Expr{ .const_ = ab }, &env, null), ab));

    // {const, {'$1',b}} → the tuple with the ATOM '$1', NOT 10 (opacity).
    const dollar1 = FinalTerms.atom(&ctx, try ctx.atoms.intern("$1"));
    const opaque_pair = try FinalTerms.tuple(&ctx, &.{ dollar1, b });
    const got = try ev.eval(Expr{ .const_ = opaque_pair }, &env, null);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, got, opaque_pair));
    // and it is NOT the substituted {10,b}
    const substituted = try FinalTerms.tuple(&ctx, &.{ env.slots[0].?, b });
    try std.testing.expect(!FinalTerms.eqlExact(&ctx, got, substituted));
}

// The DIFFERENTIAL law is realized as an oracle TABLE captured from the pinned
// OTP-30 `ets:match_spec_run` (harness `zigvm_matchspec_body_diff.erl`); each
// row's expected term is reproduced here so the kernel is byte-checked against
// the live engine's answers without a boot dependency in the unit suite.
test "LAW eval-differential: op battery equals the captured OTP-30 match_spec_run table" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var ev = try Evaluator.init(&ctx);

    // subject {10,3}: $1=10 $2=3   (exactly the values the oracle probe used)
    var env = pat.Bindings(FinalTerms){};
    env.slots[0] = FinalTerms.int(&ctx, 10);
    env.slots[1] = FinalTerms.int(&ctx, 3);
    const v1 = Expr{ .bound = 0 };
    const v2 = Expr{ .bound = 1 };

    // Captured (see probe): +→13 -→7 *→30 >→true =:=→true element(1,{10,3})→10 const({a,b})→{a,b}
    const rows = .{
        .{ call(.plus, &.{ v1, v2 }), FinalTerms.int(&ctx, 13) },
        .{ call(.minus, &.{ v1, v2 }), FinalTerms.int(&ctx, 7) },
        .{ call(.times, &.{ v1, v2 }), FinalTerms.int(&ctx, 30) },
        .{ call(.gt, &.{ v1, v2 }), ev.boolT(true) },
        .{ call(.eq_exact, &.{ v1, v1 }), ev.boolT(true) },
        .{ call(.element, &.{ .{ .lit = FinalTerms.int(&ctx, 1) }, .{ .tuple = &.{ v1, v2 } } }), FinalTerms.int(&ctx, 10) },
    };
    inline for (rows) |row| {
        const got = try ev.eval(row[0], &env, null);
        try std.testing.expect(FinalTerms.eqlExact(&ctx, got, row[1]));
    }
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
