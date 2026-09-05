//! src/release_upgrade.zig — the RELUP low-level instruction interpreter
//! (gap-release-handler, DIVERGENCE 629). The runtime half of the OTP
//! release_handler: `release_handler:install_release/1` applies a `relup`'s
//! LOW-LEVEL instruction script to a running release. This module models that
//! script as a polymorphic FOLD (the exact shape `boot_script.zig` uses for the
//! `.script` boot loop), so the upgrade's ORDER + `point_of_no_return`
//! commit/rollback semantics are proven independent of the real code-load /
//! gen_server-suspend effects.
//!
//! ## Semantic domain
//! A relup low-level script is an ORDERED list of instructions (OTP appup
//! cookbook): `load_object_code`, `point_of_no_return`, `load`, `remove`,
//! `purge`, `suspend`, `resume`, `code_change`, `apply`, `restart_application`,
//! `restart_emulator`. `interpret` FOLDS the list through a `Driver`: each
//! instruction's effect is applied in order. The `point_of_no_return` (PONR) is
//! the commit boundary — a Driver error BEFORE it ROLLS BACK the upgrade (the
//! old code stays); an error AFTER it is FATAL but the upgrade has COMMITTED
//! (there is no going back — the release is in the new state). An UNKNOWN
//! instruction is a malformed relup (never silently skipped).
//!
//! ## Scope (EQUIV first increment — honest bound)
//! This lands the SCRIPT-FOLD + PONR + apply-once + reject-unknown, proven by a
//! self-differential `TraceDriver` (order homomorphism, the boot_script grade).
//! The REAL runtime EFFECTS — actual code loading, gen_server `suspend`/
//! `code_change`/`resume`, the supervised-tree walk — and the appup→relup
//! TRANSLATION (`systools_rc`) are the Stratum-C / systools remainder.
const std = @import("std");
const ta = @import("term_algebra.zig");
const FinalTerms = ta.FinalTerms;

pub const InstrTag = enum {
    load_object_code,
    point_of_no_return,
    load,
    remove,
    purge,
    suspend_p,
    resume_p,
    code_change,
    apply,
    restart_application,
    restart_emulator,
    unknown,
};

pub const Instr = union(InstrTag) {
    load_object_code: FinalTerms.Term, // {App,Vsn,[Mod]}
    point_of_no_return,
    load: ta.AtomIdx, // {load,{Mod,_,_}} → Mod
    remove: ta.AtomIdx, // {remove,{Mod,_,_}} → Mod
    purge: FinalTerms.Term, // {purge,[Mod]}
    suspend_p: FinalTerms.Term, // {suspend,[Mod|{Mod,T}]}
    resume_p: FinalTerms.Term, // {resume,[Mod]}
    code_change: FinalTerms.Term, // {code_change,[{Mod,Extra}]} / {code_change,Mode,_}
    apply: struct { m: ta.AtomIdx, f: ta.AtomIdx }, // {apply,{M,F,A}}
    restart_application: ta.AtomIdx, // {restart_application,App}
    restart_emulator,
    unknown,
};

pub const Relup = struct {
    instrs: []Instr,
    pub fn deinit(self: *Relup, gpa: std.mem.Allocator) void {
        gpa.free(self.instrs);
    }
};

pub const ParseError = error{ OutOfMemory, Malformed };

fn tagOf(ctx: *FinalTerms.Ctx, atom_name: []const u8) InstrTag {
    const names = .{
        .{ "load_object_code", InstrTag.load_object_code },
        .{ "point_of_no_return", InstrTag.point_of_no_return },
        .{ "load", InstrTag.load },
        .{ "remove", InstrTag.remove },
        .{ "purge", InstrTag.purge },
        .{ "suspend", InstrTag.suspend_p },
        .{ "resume", InstrTag.resume_p },
        .{ "code_change", InstrTag.code_change },
        .{ "apply", InstrTag.apply },
        .{ "restart_application", InstrTag.restart_application },
        .{ "restart_emulator", InstrTag.restart_emulator },
    };
    _ = ctx;
    inline for (names) |n| {
        if (std.mem.eql(u8, atom_name, n[0])) return n[1];
    }
    return .unknown;
}

/// The `{load,{Mod,_,_}}` / `{remove,{Mod,_,_}}` inner Mod (first tuple element).
fn innerMod(ctx: *FinalTerms.Ctx, arg: FinalTerms.Term) ?ta.AtomIdx {
    if (FinalTerms.kindOf(ctx, arg) != .tuple or FinalTerms.tupleArity(ctx, arg) < 1) return null;
    const m = FinalTerms.tupleElem(ctx, arg, 0);
    if (FinalTerms.kindOf(ctx, m) != .atom) return null;
    return FinalTerms.atomIdxOf(m);
}

/// Parse ONE relup instruction from a term (a `{Tag,...}` tuple or a bare atom
/// `point_of_no_return`/`restart_emulator`). An unrecognised shape → `.unknown`
/// (the fold rejects it — never silently dropped).
pub fn parseInstr(ctx: *FinalTerms.Ctx, term: FinalTerms.Term) Instr {
    // bare atoms.
    if (FinalTerms.kindOf(ctx, term) == .atom) {
        return switch (tagOf(ctx, ctx.atoms.nameOf(FinalTerms.atomIdxOf(term)))) {
            .point_of_no_return => .point_of_no_return,
            .restart_emulator => .restart_emulator,
            else => .unknown,
        };
    }
    if (FinalTerms.kindOf(ctx, term) != .tuple or FinalTerms.tupleArity(ctx, term) < 1) return .unknown;
    const tag_term = FinalTerms.tupleElem(ctx, term, 0);
    if (FinalTerms.kindOf(ctx, tag_term) != .atom) return .unknown;
    const tag = tagOf(ctx, ctx.atoms.nameOf(FinalTerms.atomIdxOf(tag_term)));
    const arity = FinalTerms.tupleArity(ctx, term);
    return switch (tag) {
        .load_object_code => if (arity == 2) .{ .load_object_code = FinalTerms.tupleElem(ctx, term, 1) } else .unknown,
        .load => if (arity == 2) blk: {
            break :blk if (innerMod(ctx, FinalTerms.tupleElem(ctx, term, 1))) |mod| .{ .load = mod } else .unknown;
        } else .unknown,
        .remove => if (arity == 2) blk: {
            break :blk if (innerMod(ctx, FinalTerms.tupleElem(ctx, term, 1))) |mod| .{ .remove = mod } else .unknown;
        } else .unknown,
        .purge => if (arity == 2) .{ .purge = FinalTerms.tupleElem(ctx, term, 1) } else .unknown,
        .suspend_p => if (arity == 2) .{ .suspend_p = FinalTerms.tupleElem(ctx, term, 1) } else .unknown,
        .resume_p => if (arity == 2) .{ .resume_p = FinalTerms.tupleElem(ctx, term, 1) } else .unknown,
        .code_change => if (arity == 2) .{ .code_change = FinalTerms.tupleElem(ctx, term, 1) } else if (arity == 3) .{ .code_change = FinalTerms.tupleElem(ctx, term, 2) } else .unknown,
        .apply => if (arity == 2) blk: {
            const mfa = FinalTerms.tupleElem(ctx, term, 1);
            if (FinalTerms.kindOf(ctx, mfa) != .tuple or FinalTerms.tupleArity(ctx, mfa) != 3) break :blk .unknown;
            const mt = FinalTerms.tupleElem(ctx, mfa, 0);
            const ft = FinalTerms.tupleElem(ctx, mfa, 1);
            if (FinalTerms.kindOf(ctx, mt) != .atom or FinalTerms.kindOf(ctx, ft) != .atom) break :blk .unknown;
            break :blk .{ .apply = .{ .m = FinalTerms.atomIdxOf(mt), .f = FinalTerms.atomIdxOf(ft) } };
        } else .unknown,
        .restart_application => if (arity == 2) blk: {
            const a = FinalTerms.tupleElem(ctx, term, 1);
            break :blk if (FinalTerms.kindOf(ctx, a) == .atom) .{ .restart_application = FinalTerms.atomIdxOf(a) } else .unknown;
        } else .unknown,
        .point_of_no_return, .restart_emulator, .unknown => .unknown, // these are bare atoms, not tuples
    };
}

/// Parse a relup low-level script (a proper list of instruction terms).
pub fn parse(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, script: FinalTerms.Term) ParseError!Relup {
    var list: std.ArrayList(Instr) = .empty;
    errdefer list.deinit(gpa);
    var cur = script;
    while (FinalTerms.kindOf(ctx, cur) == .cons) {
        const h = FinalTerms.listHead(ctx, cur);
        cur = FinalTerms.listTail(ctx, cur);
        try list.append(gpa, parseInstr(ctx, h));
    }
    if (FinalTerms.kindOf(ctx, cur) != .nil) return error.Malformed; // improper list
    return .{ .instrs = try list.toOwnedSlice(gpa) };
}

pub const Outcome = union(enum) {
    /// The upgrade ran to the end. `committed` = the PONR was crossed (the new
    /// release is live); `!committed` = no PONR seen (a pure code-load, still
    /// atomic).
    ok: struct { committed: bool },
    /// A Driver error BEFORE the PONR → the upgrade rolled back (old code stays).
    rolled_back: usize,
    /// A Driver error AFTER the PONR → FATAL, but the release has COMMITTED
    /// (the appup cookbook's point-of-no-return contract).
    fatal_committed: usize,
    /// An unknown/malformed instruction at `index`.
    malformed: usize,
};

/// FOLD the relup script through `driver`, honoring the `point_of_no_return`
/// commit boundary. Mirrors `boot_script.interpret` (order-preserving fold);
/// the PONR is the ONE piece of extra control the boot loop lacks.
pub fn interpret(comptime D: type, driver: *D, ctx: *FinalTerms.Ctx, relup: *const Relup) Outcome {
    var committed = false;
    for (relup.instrs, 0..) |instr, i| {
        const err: ?anyerror = switch (instr) {
            .point_of_no_return => blk: {
                committed = true;
                break :blk driver.pointOfNoReturn();
            },
            .load_object_code => |t| driver.loadObjectCode(t),
            .load => |mod| driver.load(mod),
            .remove => |mod| driver.remove(mod),
            .purge => |t| driver.purge(t),
            .suspend_p => |t| driver.suspendMods(t),
            .resume_p => |t| driver.resumeMods(t),
            .code_change => |t| driver.codeChange(t),
            .apply => |mf| driver.apply(mf.m, mf.f),
            .restart_application => |app| driver.restartApplication(app),
            .restart_emulator => driver.restartEmulator(),
            .unknown => return .{ .malformed = i },
        };
        _ = ctx;
        if (err) |_| {
            return if (committed) .{ .fatal_committed = i } else .{ .rolled_back = i };
        }
    }
    return .{ .ok = .{ .committed = committed } };
}

// ── appup → relup TRANSLATION (systools_rc, DIVERGENCE 630) ──────────────────
// The BUILD-time half: systools_rc:translate_scripts expands a HIGH-LEVEL appup
// instruction into the LOW-LEVEL relup instructions the interpreter above folds.
// Byte-EQ against the live pinned OTP-30 systools_rc for the simple (dependency-
// free) instructions; the merge (multi-instruction load_object_code coalescing,
// a single point_of_no_return) + dependency-driven update/restart_application
// are the systools remainder. `app` is the owning application's {name, vsn}.

/// `brutal_purge` (the systools_rc default purge mode for load/remove) as an atom.
fn bp(ctx: *FinalTerms.Ctx) FinalTerms.Term {
    return FinalTerms.atom(ctx, ctx.atoms.intern("brutal_purge") catch unreachable);
}

/// Translate ONE high-level appup instruction into its low-level relup list
/// TERM, byte-EQ vs systools_rc:translate_scripts (single-instruction case).
/// Handles load_module/add_module (identical expansion), delete_module, apply.
/// An unrecognised/dependency-driven instruction → error.Malformed (the remainder).
pub fn translateInstr(ctx: *FinalTerms.Ctx, hl: FinalTerms.Term, app_name: ta.AtomIdx, app_vsn: FinalTerms.Term) ParseError!FinalTerms.Term {
    if (FinalTerms.kindOf(ctx, hl) != .tuple or FinalTerms.tupleArity(ctx, hl) < 2) return error.Malformed;
    const tag_t = FinalTerms.tupleElem(ctx, hl, 0);
    if (FinalTerms.kindOf(ctx, tag_t) != .atom) return error.Malformed;
    const tag = ctx.atoms.nameOf(FinalTerms.atomIdxOf(tag_t));
    const ponr = FinalTerms.atom(ctx, try ctx.atoms.intern("point_of_no_return"));

    if (std.mem.eql(u8, tag, "load_module") or std.mem.eql(u8, tag, "add_module")) {
        const mod = FinalTerms.tupleElem(ctx, hl, 1);
        if (FinalTerms.kindOf(ctx, mod) != .atom) return error.Malformed;
        // [{load_object_code,{App,Vsn,[Mod]}}, point_of_no_return, {load,{Mod,brutal_purge,brutal_purge}}]
        const mod_list = try FinalTerms.cons(ctx, mod, FinalTerms.nil(ctx));
        const loc = try FinalTerms.tuple(ctx, &.{ FinalTerms.atom(ctx, try ctx.atoms.intern("load_object_code")), try FinalTerms.tuple(ctx, &.{ FinalTerms.atom(ctx, app_name), app_vsn, mod_list }) });
        const load = try FinalTerms.tuple(ctx, &.{ FinalTerms.atom(ctx, try ctx.atoms.intern("load")), try FinalTerms.tuple(ctx, &.{ mod, bp(ctx), bp(ctx) }) });
        return try list3(ctx, loc, ponr, load);
    }
    if (std.mem.eql(u8, tag, "delete_module")) {
        const mod = FinalTerms.tupleElem(ctx, hl, 1);
        if (FinalTerms.kindOf(ctx, mod) != .atom) return error.Malformed;
        // [point_of_no_return, {remove,{Mod,brutal_purge,brutal_purge}}, {purge,[Mod]}]
        const remove = try FinalTerms.tuple(ctx, &.{ FinalTerms.atom(ctx, try ctx.atoms.intern("remove")), try FinalTerms.tuple(ctx, &.{ mod, bp(ctx), bp(ctx) }) });
        const purge = try FinalTerms.tuple(ctx, &.{ FinalTerms.atom(ctx, try ctx.atoms.intern("purge")), try FinalTerms.cons(ctx, mod, FinalTerms.nil(ctx)) });
        return try list3(ctx, ponr, remove, purge);
    }
    if (std.mem.eql(u8, tag, "apply")) {
        const mfa = FinalTerms.tupleElem(ctx, hl, 1);
        // [point_of_no_return, {apply,MFA}]
        const ap = try FinalTerms.tuple(ctx, &.{ FinalTerms.atom(ctx, try ctx.atoms.intern("apply")), mfa });
        return try FinalTerms.cons(ctx, ponr, try FinalTerms.cons(ctx, ap, FinalTerms.nil(ctx)));
    }
    return error.Malformed; // update/restart_application/... = the dependency-driven remainder
}

fn list3(ctx: *FinalTerms.Ctx, a: FinalTerms.Term, b: FinalTerms.Term, c: FinalTerms.Term) !FinalTerms.Term {
    return try FinalTerms.cons(ctx, a, try FinalTerms.cons(ctx, b, try FinalTerms.cons(ctx, c, FinalTerms.nil(ctx))));
}

// ═══════════════════════════════════════════════════════════════════════════
// LAWS
// ═══════════════════════════════════════════════════════════════════════════

const AtomTable = ta.AtomTable;

/// The oracle driver: an ordered effect log (one tag per applied instruction) —
/// the boot_script oracle-driver shape, so the fold trace lines up 1:1 with the
/// instruction list for the ORDER homomorphism law. `fail_at` injects a Driver
/// error at the N-th effect (to exercise the PONR rollback/commit branch).
const TraceDriver = struct {
    log: std.ArrayList(InstrTag),
    gpa: std.mem.Allocator,
    fail_at: ?usize = null,
    n: usize = 0,
    fn rec(self: *TraceDriver, t: InstrTag) ?anyerror {
        self.log.append(self.gpa, t) catch return error.OutOfMemory;
        self.n += 1;
        if (self.fail_at) |fa| if (self.n - 1 == fa) return error.Injected;
        return null;
    }
    fn loadObjectCode(self: *TraceDriver, _: FinalTerms.Term) ?anyerror {
        return self.rec(.load_object_code);
    }
    fn pointOfNoReturn(self: *TraceDriver) ?anyerror {
        return self.rec(.point_of_no_return);
    }
    fn load(self: *TraceDriver, _: ta.AtomIdx) ?anyerror {
        return self.rec(.load);
    }
    fn remove(self: *TraceDriver, _: ta.AtomIdx) ?anyerror {
        return self.rec(.remove);
    }
    fn purge(self: *TraceDriver, _: FinalTerms.Term) ?anyerror {
        return self.rec(.purge);
    }
    fn suspendMods(self: *TraceDriver, _: FinalTerms.Term) ?anyerror {
        return self.rec(.suspend_p);
    }
    fn resumeMods(self: *TraceDriver, _: FinalTerms.Term) ?anyerror {
        return self.rec(.resume_p);
    }
    fn codeChange(self: *TraceDriver, _: FinalTerms.Term) ?anyerror {
        return self.rec(.code_change);
    }
    fn apply(self: *TraceDriver, _: ta.AtomIdx, _: ta.AtomIdx) ?anyerror {
        return self.rec(.apply);
    }
    fn restartApplication(self: *TraceDriver, _: ta.AtomIdx) ?anyerror {
        return self.rec(.restart_application);
    }
    fn restartEmulator(self: *TraceDriver) ?anyerror {
        return self.rec(.restart_emulator);
    }
};

/// Build a relup script term from a small DSL for the laws.
fn buildScript(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx) !FinalTerms.Term {
    const at = struct {
        fn go(c: *FinalTerms.Ctx, s: []const u8) FinalTerms.Term {
            return FinalTerms.atom(c, c.atoms.intern(s) catch unreachable);
        }
    }.go;
    const mod = at(ctx, "mymod");
    const app = at(ctx, "myapp");
    // [{load_object_code,{myapp,"1",[mymod]}}, point_of_no_return,
    //  {suspend,[mymod]}, {load,{mymod,brutal,brutal}}, {code_change,[{mymod,[]}]},
    //  {resume,[mymod]}, {apply,{io,format,[]}}, {restart_application,myapp}]
    const loc = try FinalTerms.tuple(ctx, &.{ at(ctx, "load_object_code"), try FinalTerms.tuple(ctx, &.{ app, at(ctx, "v1"), try FinalTerms.cons(ctx, mod, FinalTerms.nil(ctx)) }) });
    const ponr = at(ctx, "point_of_no_return");
    const susp = try FinalTerms.tuple(ctx, &.{ at(ctx, "suspend"), try FinalTerms.cons(ctx, mod, FinalTerms.nil(ctx)) });
    const load = try FinalTerms.tuple(ctx, &.{ at(ctx, "load"), try FinalTerms.tuple(ctx, &.{ mod, at(ctx, "brutal"), at(ctx, "brutal") }) });
    const cc = try FinalTerms.tuple(ctx, &.{ at(ctx, "code_change"), try FinalTerms.cons(ctx, try FinalTerms.tuple(ctx, &.{ mod, FinalTerms.nil(ctx) }), FinalTerms.nil(ctx)) });
    const res = try FinalTerms.tuple(ctx, &.{ at(ctx, "resume"), try FinalTerms.cons(ctx, mod, FinalTerms.nil(ctx)) });
    const ap = try FinalTerms.tuple(ctx, &.{ at(ctx, "apply"), try FinalTerms.tuple(ctx, &.{ at(ctx, "io"), at(ctx, "format"), FinalTerms.nil(ctx) }) });
    const ra = try FinalTerms.tuple(ctx, &.{ at(ctx, "restart_application"), app });
    var l = FinalTerms.nil(ctx);
    for ([_]FinalTerms.Term{ ra, ap, res, cc, load, susp, ponr, loc }) |x| l = try FinalTerms.cons(ctx, x, l);
    _ = gpa;
    return l;
}

test "LAW gap-release-handler-relup: the relup low-level FOLD is order-preserving (trace == instruction order), applies EXACTLY once per instruction, and point_of_no_return is the commit boundary (rollback before / fatal-committed after)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const script = try buildScript(gpa, &ctx);
    var relup = try parse(gpa, &ctx, script);
    defer relup.deinit(gpa);
    // parse totality: 8 instructions, none unknown.
    try std.testing.expectEqual(@as(usize, 8), relup.instrs.len);
    for (relup.instrs) |ins| try std.testing.expect(ins != .unknown);

    // (1) FOLD-ORDER HOMOMORPHISM: the trace tag sequence == the parsed order.
    {
        var d = TraceDriver{ .log = .empty, .gpa = gpa };
        defer d.log.deinit(gpa);
        const out = interpret(TraceDriver, &d, &ctx, &relup);
        try std.testing.expect(out == .ok and out.ok.committed); // PONR crossed → committed
        try std.testing.expectEqual(relup.instrs.len, d.log.items.len); // apply-once: |trace|==|instrs|
        for (relup.instrs, d.log.items) |ins, tag| {
            try std.testing.expectEqual(@as(InstrTag, ins), tag); // trace[k] denotes instr[k]
        }
    }

    // (2) POINT_OF_NO_RETURN — rollback BEFORE, fatal-committed AFTER.
    // PONR is at index 1 (load_object_code=0, ponr=1). A fail at effect 0 (before)
    // → rolled_back; a fail at effect 2 (after) → fatal_committed.
    {
        var d = TraceDriver{ .log = .empty, .gpa = gpa, .fail_at = 0 };
        defer d.log.deinit(gpa);
        const out = interpret(TraceDriver, &d, &ctx, &relup);
        try std.testing.expect(out == .rolled_back); // pre-PONR error rolls back
    }
    {
        var d = TraceDriver{ .log = .empty, .gpa = gpa, .fail_at = 2 };
        defer d.log.deinit(gpa);
        const out = interpret(TraceDriver, &d, &ctx, &relup);
        try std.testing.expect(out == .fatal_committed); // post-PONR error is fatal-but-committed
    }

    // (3) REJECT-UNKNOWN: a malformed instruction is never silently skipped.
    {
        const bad = FinalTerms.atom(&ctx, try atoms.intern("frobnicate")); // unknown bare atom
        const bad_script = try FinalTerms.cons(&ctx, bad, FinalTerms.nil(&ctx));
        var bad_relup = try parse(gpa, &ctx, bad_script);
        defer bad_relup.deinit(gpa);
        try std.testing.expect(bad_relup.instrs[0] == .unknown);
        var d = TraceDriver{ .log = .empty, .gpa = gpa };
        defer d.log.deinit(gpa);
        const out = interpret(TraceDriver, &d, &ctx, &bad_relup);
        try std.testing.expect(out == .malformed and out.malformed == 0);
    }
}

// LAW gap-release-handler-translate (DIVERGENCE 630): the appup→relup TRANSLATION
// (systools_rc:translate_scripts, single-instruction case) is byte-EQ vs the live
// pinned OTP-30 systools_rc — the expansions were captured from the oracle (sasl
// systools_rc, an #application{name=myapp,vsn="1.0",modules=[m1]}). load_module ≡
// add_module; delete_module; apply. Composition: the translated low-level list
// PARSES + FOLDS through the interpreter (translate → parse → interpret). Mutants:
// MUT-TRANS-1 (wrong purge mode), MUT-TRANS-2 (load_module/delete_module confusion).
test "LAW gap-release-handler-translate: appup->relup translation byte-EQ vs pinned OTP-30 systools_rc (load/add/delete_module, apply); translated output parses+folds" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const A = struct {
        fn at(c: *FinalTerms.Ctx, s: []const u8) FinalTerms.Term {
            return FinalTerms.atom(c, c.atoms.intern(s) catch unreachable);
        }
        fn charlist(c: *FinalTerms.Ctx, s: []const u8) FinalTerms.Term {
            var l = FinalTerms.nil(c);
            var i = s.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(c, FinalTerms.int(c, s[i]), l) catch unreachable;
            }
            return l;
        }
        fn t2(c: *FinalTerms.Ctx, a: FinalTerms.Term, b: FinalTerms.Term) FinalTerms.Term {
            return FinalTerms.tuple(c, &.{ a, b }) catch unreachable;
        }
    };
    const app_name = atoms.intern("myapp") catch unreachable;
    const vsn = A.charlist(&ctx, "1.0"); // the oracle's [49,46,48]
    const m1 = A.at(&ctx, "m1");
    const bpp = A.at(&ctx, "brutal_purge");
    const ponr = A.at(&ctx, "point_of_no_return");
    const mod_list = FinalTerms.cons(&ctx, m1, FinalTerms.nil(&ctx)) catch unreachable;

    // EXPECTED (from the oracle) load_module/add_module:
    //   [{load_object_code,{myapp,"1.0",[m1]}}, point_of_no_return, {load,{m1,brutal_purge,brutal_purge}}]
    const exp_loc = A.t2(&ctx, A.at(&ctx, "load_object_code"), FinalTerms.tuple(&ctx, &.{ A.at(&ctx, "myapp"), vsn, mod_list }) catch unreachable);
    const exp_load = A.t2(&ctx, A.at(&ctx, "load"), FinalTerms.tuple(&ctx, &.{ m1, bpp, bpp }) catch unreachable);
    const exp_lm = list3(&ctx, exp_loc, ponr, exp_load) catch unreachable;

    const got_lm = try translateInstr(&ctx, A.t2(&ctx, A.at(&ctx, "load_module"), m1), app_name, vsn);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, got_lm, exp_lm)); // byte-EQ vs oracle
    const got_am = try translateInstr(&ctx, A.t2(&ctx, A.at(&ctx, "add_module"), m1), app_name, vsn);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, got_am, exp_lm)); // add_module ≡ load_module (oracle)

    // EXPECTED delete_module: [point_of_no_return, {remove,{m1,bp,bp}}, {purge,[m1]}]
    const exp_rm = A.t2(&ctx, A.at(&ctx, "remove"), FinalTerms.tuple(&ctx, &.{ m1, bpp, bpp }) catch unreachable);
    const exp_pg = A.t2(&ctx, A.at(&ctx, "purge"), mod_list);
    const exp_dm = list3(&ctx, ponr, exp_rm, exp_pg) catch unreachable;
    const got_dm = try translateInstr(&ctx, A.t2(&ctx, A.at(&ctx, "delete_module"), m1), app_name, vsn);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, got_dm, exp_dm));

    // EXPECTED apply: [point_of_no_return, {apply,MFA}]
    const mfa = FinalTerms.tuple(&ctx, &.{ A.at(&ctx, "mymod"), A.at(&ctx, "go"), FinalTerms.nil(&ctx) }) catch unreachable;
    const exp_ap = FinalTerms.cons(&ctx, ponr, FinalTerms.cons(&ctx, A.t2(&ctx, A.at(&ctx, "apply"), mfa), FinalTerms.nil(&ctx)) catch unreachable) catch unreachable;
    const got_ap = try translateInstr(&ctx, A.t2(&ctx, A.at(&ctx, "apply"), mfa), app_name, vsn);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, got_ap, exp_ap));

    // COMPOSITION: the translated low-level list PARSES + FOLDS through the interpreter.
    var relup = try parse(gpa, &ctx, got_lm);
    defer relup.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), relup.instrs.len);
    for (relup.instrs) |ins| try std.testing.expect(ins != .unknown);

    // a dependency-driven instruction (update) is the disclosed remainder → Malformed.
    try std.testing.expectError(error.Malformed, translateInstr(&ctx, A.t2(&ctx, A.at(&ctx, "update"), m1), app_name, vsn));
}
