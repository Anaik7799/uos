//! # bifs/fun_info — fun / module introspection BIF family (E3.13)
//!
//! ## Signature
//! Same contract as every other family module: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term`. This family wires
//! the `erlang:` fun/module-introspection BIFs of DIVERGENCE entry 13(b) to the
//! algebras that already carry their answers — the M5 `fun_` term
//! (`term_algebra`), the E3.12 static export index (`Machine.exports`), and the
//! generated pin BIF table (`bif_table.entries`) — no new term semantics.
//!
//! ## Semantic domain (what each BIF observes)
//!   is_builtin(M,F,A)       membership of `{M,F,A}` in the pin's `bif.tab`
//!                           set — EXACTLY `bif_table.entries` (the same table
//!                           `dispatch.resolve` classifies over, and the same
//!                           set OTP's own `erlang:is_builtin/3` is generated
//!                           from). INDEPENDENT of this VM's implement/justify
//!                           status: a justified/stub row is still a builtin in
//!                           OTP, so `is_builtin` reflects pin membership, never
//!                           our classification. → a `bool`.
//!   function_exported(M,F,A) `{M,F,A}` is an EXPORT of a currently-linked
//!                           module — a linear scan of `Machine.exports` (the
//!                           borrowed `module:func/arity → pc` index the E3.12b
//!                           linker builds over ALL linked modules, entry +
//!                           every `--pa` dep). An unloaded module or an
//!                           unexported (local) function → `false`. → a `bool`.
//!   fun_info(F, Item)       BOTH fun kinds (gap-fun-info, DIVERGENCE 652).
//!                           A LOCAL closure (SUBTAG_FUN `{label,arity,env}`):
//!                           `arity`→`{arity,funArity}`, `type`→`{type,local}`,
//!                           `env`→`{env,[captured]}` — all byte-EQ. An EXTERNAL
//!                           `fun M:F/A` (SUBTAG_EXPORT_FUN): FULLY byte-EQ —
//!                           `type`→`{type,external}`, `module`/`name` from the
//!                           term's atoms, `arity`, `env`→`{env,[]}`. A LOCAL
//!                           closure's module/name (727) + index/uniq (741, the
//!                           FunT Index+OldUniq via `fun_meta`) are byte-EQ.
//!                           RESIDUAL (`deferred_funmeta`, badarg — never
//!                           fabricated): every fun's pid + new_uniq/new_index
//!                           (the md5-based fields, absent from the old FunT
//!                           chunk we load). It is RESOLVABLE from a compiled
//!                           beam via the dispatch-needed-deferred carve-out
//!                           (the processes/0 precedent) — the deterministic
//!                           items run instead of undef-ing.
//!
//! ## Reachability / ledger (the entry-22 lesson, applied)
//! `is_builtin/3` and `function_exported/3` compile to `call_ext` (verified:
//! not guard bifs) and DISPATCH through `call_ext_bif` since E3.12 (entry 25),
//! and both are PURE + corpus-proven — so they flip **EQ** in
//! `harness/bif_gen.ml`'s `implemented_map`. **DIVERGENCE 727 (funmeta):** a LOCAL
//! closure's module/name + `fun_info_mfa/1`'s `{M,F,A}` are now byte-EQ, served from
//! the per-`Machine` `fun_meta` (label→{module,name} atoms populated at `make_fun3`
//! from the FunT/Lambda chunk). `fun_info/2` + `fun_info_mfa/1` STAY `.justified`
//! (RE-BOUND, never false-EQ) for the honest residual — a synthetic/cross-process
//! closure → badarg, plus fun uniq/index/pid + `fun_to_list/1`'s `#Fun<>` text; see
//! `bif_gen.ml`'s `deferred_funmeta`/`deferred_modinfo`.
//!
//! ## Laws (see the suite below)
//!   - IS_BUILTIN MEMBERSHIP: `is_builtin(M,F,A)` == `{M,F,A} ∈ bif_table`.
//!     A known builtin → true; a same-name non-bif or bad arity → false.
//!   - FUNCTION_EXPORTED = the export table: true iff `{M,F,A} ∈ m.exports`;
//!     a loaded-but-UNEXPORTED `{M,F,A}` (a pc present but not in the export
//!     index) → false (the plan's mutant-2 target).
//!   - FUN_INFO CONTRACT: `fun_info(F, arity)` == `{arity, funArity(F)}` and
//!     `fun_info(F, env)` == `{env, <the captured env, in order>}` — arity is
//!     NEVER the env length (the plan's mutant-1 target).
//!   - REJECTION: non-atom M/F, non-int A → badarg; a non-fun first arg → badarg.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const bif_table = @import("bif_table.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

fn boolTerm(m: *Machine, cond: bool) Term {
    return FinalTerms.atom(&m.ctx, if (cond) m.bool_true else m.bool_false);
}

/// Decode a `(Module, Function, Arity)` MFA triple from the first three args,
/// rejecting a non-atom M/F or a non-small/out-of-range A with `badarg`. The
/// arity domain is 0..255 (BEAM's real fun/BIF arity ceiling), matching `u8`.
const Mfa = struct { m_name: []const u8, f_name: []const u8, arity: u8 };
fn decodeMfa(m: *Machine, args: []const Term) BifError!Mfa {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    if (!FinalTerms.repIsAtom(args[1])) return error.Badarg;
    if (!FinalTerms.repIsSmall(args[2])) return error.Badarg;
    const a = FinalTerms.smallValOf(args[2]);
    if (a < 0 or a > 255) return error.Badarg;
    return .{
        .m_name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0])),
        .f_name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[1])),
        .arity = @intCast(a),
    };
}

/// `erlang:is_builtin(M, F, A)` — is `{M,F,A}` a BIF of the pinned OTP set?
/// Membership in `bif_table.entries` (the pin's `bif.tab`), independent of this
/// VM's implement/justify classification.
pub fn is_builtin_3(m: *Machine, args: []const Term) BifError!Term {
    const mfa = try decodeMfa(m, args);
    for (bif_table.entries) |e| {
        if (e.arity != mfa.arity) continue;
        if (!std.mem.eql(u8, e.module, mfa.m_name)) continue;
        if (!std.mem.eql(u8, e.name, mfa.f_name)) continue;
        return boolTerm(m, true);
    }
    return boolTerm(m, false);
}

/// `erlang:function_exported(M, F, A)` — is `{M,F,A}` an EXPORT of a currently
/// linked module? Linear scan of the borrowed `Machine.exports` index. Atoms
/// come from `m.ctx.atoms` (the SAME table the linker interned exports into), so
/// the module/func comparison is a direct `AtomIdx` equality, no re-intern.
pub fn function_exported_3(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    if (!FinalTerms.repIsAtom(args[1])) return error.Badarg;
    if (!FinalTerms.repIsSmall(args[2])) return error.Badarg;
    const a = FinalTerms.smallValOf(args[2]);
    if (a < 0 or a > 255) return error.Badarg;
    const mod = FinalTerms.atomIdxOf(args[0]);
    const func = FinalTerms.atomIdxOf(args[1]);
    const arity: u32 = @intCast(a);
    for (m.exports) |e| {
        if (e.module == mod and e.func == func and e.arity == arity)
            return boolTerm(m, true);
    }
    // gap-app-boot-engine: also honor RUNTIME-loaded (autoloaded via --code-path)
    // modules — a stock app's `code:ensure_loaded` loads a module into the runtime
    // code space, and its following `function_exported` must see it (ranch checks
    // its transport/protocol modules this way).
    if (m.resolveRuntime(mod, func, arity) != null) return boolTerm(m, true);
    return boolTerm(m, false);
}

/// `erlang:fun_info(Fun, Item)` — the truthful subset (`arity`/`type`/`env`).
/// The module/name/uniq/index Items need a fun-term metadata extension this
/// slice does not add; the ROW is deferred (`deferred_funmeta`), so this fn is
/// LAW-PROVEN over the truthful items but NOT wired into dispatch. Kept here so
/// the fun-environment observability the E3 charter names is real code with a
/// contract law, ready for the metadata slice that discharges the row.
pub fn fun_info_2(m: *Machine, args: []const Term) BifError!Term {
    const T = FinalTerms;
    const f = args[0];
    // gap-fun-info (DIVERGENCE 652): handle BOTH fun kinds. A local closure is a
    // SUBTAG_FUN (repIsFun); an `fun M:F/A` is a SUBTAG_EXPORT_FUN (repIsExportFun)
    // — the old handler `repIsFun`-only badarg'd on external funs AND mislabeled
    // their type as `local`.
    const is_ext = T.repIsExportFun(&m.ctx, f);
    const is_local = T.repIsFun(&m.ctx, f);
    if (!is_ext and !is_local) return error.Badarg;
    if (!T.repIsAtom(args[1])) return error.Badarg;
    const item = m.ctx.atoms.nameOf(T.atomIdxOf(args[1]));
    const item_atom = args[1];
    if (std.mem.eql(u8, item, "arity")) {
        const ar: i64 = if (is_ext) T.exportFunArity(&m.ctx, f) else T.funArity(&m.ctx, f);
        return T.tuple(&m.ctx, &.{ item_atom, T.int(&m.ctx, ar) }) catch error.OutOfMemory;
    }
    if (std.mem.eql(u8, item, "type")) {
        const ty_name = if (is_ext) "external" else "local";
        const ty = T.atom(&m.ctx, m.ctx.atoms.intern(ty_name) catch return error.OutOfMemory);
        return T.tuple(&m.ctx, &.{ item_atom, ty }) catch error.OutOfMemory;
    }
    if (std.mem.eql(u8, item, "env")) {
        if (is_ext) return T.tuple(&m.ctx, &.{ item_atom, T.nil(&m.ctx) }) catch error.OutOfMemory; // an external fun has no closure env
        const parts = T.funParts(&m.ctx, f);
        var lst = T.nil(&m.ctx);
        var i = parts.env_len;
        while (i > 0) {
            i -= 1;
            lst = T.cons(&m.ctx, T.funEnvElem(&m.ctx, f, i), lst) catch return error.OutOfMemory;
        }
        return T.tuple(&m.ctx, &.{ item_atom, lst }) catch error.OutOfMemory;
    }
    // DIVERGENCE 727 (funmeta): a LOCAL closure's module/name now come from the
    // `make_fun3`-populated `Machine.fun_meta` (label → {module, name} FunT atoms).
    // Absent meta (a synthetic fun, or a cross-process transfer without the creating
    // make_fun3 in this process) stays the honest badarg residual — never fabricated.
    // A fun's pid/new_uniq/new_index remain the deferred_funmeta residual (new_uniq
    // + new_index are the md5-based fields, absent from the old FunT chunk we load).
    if (is_local and (std.mem.eql(u8, item, "module") or std.mem.eql(u8, item, "name"))) {
        if (m.fun_meta.get(T.funLabel(&m.ctx, f))) |mm| {
            const a: u32 = if (std.mem.eql(u8, item, "module")) mm[0] else mm[1];
            return T.tuple(&m.ctx, &.{ item_atom, T.atom(&m.ctx, @intCast(a)) }) catch error.OutOfMemory;
        }
    }
    // DIVERGENCE 741: a LOCAL closure's `index` (FunT Index) + `uniq` (FunT OldUniq)
    // come from the same `make_fun3`-populated fun_meta ([2]/[3]) — the integers erts
    // `fun_info(F, index|uniq)` returns (byte-EQ: the SAME FunT both VMs load).
    // Discharges part of the 727 deferred_funmeta residual (740 added the data).
    if (is_local and (std.mem.eql(u8, item, "index") or std.mem.eql(u8, item, "uniq"))) {
        if (m.fun_meta.get(T.funLabel(&m.ctx, f))) |mm| {
            const v: u32 = if (std.mem.eql(u8, item, "index")) mm[2] else mm[3];
            return T.tuple(&m.ctx, &.{ item_atom, T.int(&m.ctx, @intCast(v)) }) catch error.OutOfMemory;
        }
    }
    // module/name are BYTE-EQ for an EXTERNAL fun (the `fun M:F/A` term carries the
    // module + function atoms).
    if (is_ext and std.mem.eql(u8, item, "module")) {
        const mod = T.atom(&m.ctx, m.ctx.atoms.intern(T.exportFunModuleName(&m.ctx, f)) catch return error.OutOfMemory);
        return T.tuple(&m.ctx, &.{ item_atom, mod }) catch error.OutOfMemory;
    }
    if (is_ext and std.mem.eql(u8, item, "name")) {
        const nm = T.atom(&m.ctx, m.ctx.atoms.intern(T.exportFunFuncName(&m.ctx, f)) catch return error.OutOfMemory);
        return T.tuple(&m.ctx, &.{ item_atom, nm }) catch error.OutOfMemory;
    }
    return error.Badarg;
}

/// `erlang:fun_info_mfa/1` (DIVERGENCE 727) — the `{Module, Name, Arity}` of a fun.
/// An EXTERNAL `fun M:F/A` reads its atoms from the term; a LOCAL closure reads the
/// `make_fun3`-populated `Machine.fun_meta` (byte-EQ with the compiler-generated name,
/// e.g. `{mod, '-t/1-fun-0-', 1}`). Absent meta or a non-fun → badarg (never fabricated).
pub fn fun_info_mfa_1(m: *Machine, args: []const Term) BifError!Term {
    const T = FinalTerms;
    const f = args[0];
    if (T.repIsExportFun(&m.ctx, f)) {
        const mod = T.atom(&m.ctx, m.ctx.atoms.intern(T.exportFunModuleName(&m.ctx, f)) catch return error.OutOfMemory);
        const nm = T.atom(&m.ctx, m.ctx.atoms.intern(T.exportFunFuncName(&m.ctx, f)) catch return error.OutOfMemory);
        const ar = T.int(&m.ctx, T.exportFunArity(&m.ctx, f));
        return T.tuple(&m.ctx, &.{ mod, nm, ar }) catch error.OutOfMemory;
    }
    if (T.repIsFun(&m.ctx, f)) {
        if (m.fun_meta.get(T.funLabel(&m.ctx, f))) |mm| {
            const mod = T.atom(&m.ctx, @intCast(mm[0]));
            const nm = T.atom(&m.ctx, @intCast(mm[1]));
            const ar = T.int(&m.ctx, T.funArity(&m.ctx, f));
            return T.tuple(&m.ctx, &.{ mod, nm, ar }) catch error.OutOfMemory;
        }
    }
    return error.Badarg;
}

// ============================================================================
// Laws
// ============================================================================

const AtomTable = ta.AtomTable;
const Export = ia.Export;

test "LAW E3.13 is_builtin membership: a known bif -> true, a non-bif / bad arity -> false" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const erlang_a = FinalTerms.atom(&m.ctx, try atoms.intern("erlang"));
    const lists_a = FinalTerms.atom(&m.ctx, try atoms.intern("lists"));
    const abs_a = FinalTerms.atom(&m.ctx, try atoms.intern("abs"));
    const foldl_a = FinalTerms.atom(&m.ctx, try atoms.intern("foldl"));
    const one = FinalTerms.int(&m.ctx, 1);
    const three = FinalTerms.int(&m.ctx, 3);

    // erlang:abs/1 IS a builtin (bif.tab ubif).
    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try is_builtin_3(&m, &.{ erlang_a, abs_a, one })));
    // lists:foldl/3 is NOT a builtin (a library function).
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try is_builtin_3(&m, &.{ lists_a, foldl_a, three })));
    // right name, WRONG arity -> false (the triple is keyed on arity).
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try is_builtin_3(&m, &.{ erlang_a, abs_a, three })));
    // rejection: non-atom module.
    try std.testing.expectError(error.Badarg, is_builtin_3(&m, &.{ one, abs_a, one }));
}

test "LAW E3.13 function_exported == the export table (loaded-but-unexported -> false)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const modx = try atoms.intern("modx");
    const foo = try atoms.intern("foo");
    const bar = try atoms.intern("bar");
    // modx exports foo/1 only; bar/1 has code (pc 20) but is NOT in the export
    // index (a local function) — function_exported must say false for it.
    const exports = [_]Export{.{ .module = modx, .func = foo, .arity = 1, .pc = 10 }};
    m.exports = &exports;

    const modx_a = FinalTerms.atom(&m.ctx, modx);
    const foo_a = FinalTerms.atom(&m.ctx, foo);
    const bar_a = FinalTerms.atom(&m.ctx, bar);
    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);

    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try function_exported_3(&m, &.{ modx_a, foo_a, one })));
    // unexported local (bar/1): false.
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try function_exported_3(&m, &.{ modx_a, bar_a, one })));
    // exported name, wrong arity: false.
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try function_exported_3(&m, &.{ modx_a, foo_a, two })));
    // unknown module: false.
    const nomod = FinalTerms.atom(&m.ctx, try atoms.intern("nomod"));
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try function_exported_3(&m, &.{ nomod, foo_a, one })));
}

test "LAW E3.13 fun_info contract: arity is the arity (never the env length), env is the captured env" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // a fun of arity 1 capturing TWO env terms (7, 8): arity=1 != env_len=2.
    const e0 = FinalTerms.int(&m.ctx, 7);
    const e1 = FinalTerms.int(&m.ctx, 8);
    const f = try FinalTerms.makeFun(&m.ctx, 3, 1, &.{ e0, e1 });

    const arity_i = FinalTerms.atom(&m.ctx, try atoms.intern("arity"));
    const env_i = FinalTerms.atom(&m.ctx, try atoms.intern("env"));
    const type_i = FinalTerms.atom(&m.ctx, try atoms.intern("type"));

    // {arity, 1} — the arity, NOT the env length (2).
    const want_arity = try FinalTerms.tuple(&m.ctx, &.{ arity_i, FinalTerms.int(&m.ctx, 1) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try fun_info_2(&m, &.{ f, arity_i }), want_arity));

    // {env, [7,8]} — the captured env, in order.
    const env_list = try FinalTerms.cons(&m.ctx, e0, try FinalTerms.cons(&m.ctx, e1, FinalTerms.nil(&m.ctx)));
    const want_env = try FinalTerms.tuple(&m.ctx, &.{ env_i, env_list });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try fun_info_2(&m, &.{ f, env_i }), want_env));

    // {type, local}.
    const local = FinalTerms.atom(&m.ctx, try atoms.intern("local"));
    const want_type = try FinalTerms.tuple(&m.ctx, &.{ type_i, local });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try fun_info_2(&m, &.{ f, type_i }), want_type));

    // rejection: a non-fun first arg.
    try std.testing.expectError(error.Badarg, fun_info_2(&m, &.{ FinalTerms.int(&m.ctx, 1), arity_i }));
}

/// e47-a2 (the STOCK-BEAM keystone): `erlang:make_fun(Module, Function, Arity)`
/// → the EXTERNAL fun `fun M:F/A` (the E7.1 export_fun term — late-bound: the
/// target need not exist until application, exactly erts). gen_server's
/// callback cache (OTP-26+) calls this on every successful init, so it gates
/// every stock gen_server child. Application/ordering/hashing/ETF of the
/// resulting term are the ALREADY-LANDED E7.1 laws; this BIF is the missing
/// constructor. badarg: non-atom M/F, non-small/negative/>255 arity (erts
/// bounds fun arity at 255).
pub fn make_fun_3(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0]) or !FinalTerms.repIsAtom(args[1])) return error.Badarg;
    if (!FinalTerms.repIsSmall(args[2])) return error.Badarg;
    const a = FinalTerms.smallValOf(args[2]);
    if (a < 0 or a > 255) return error.Badarg;
    return FinalTerms.makeExportFun(&m.ctx, args[0], args[1], @intCast(a)) catch return error.OutOfMemory;
}

test "LAW e47-a2 make_fun/3: constructs the E7.1 external fun (module/function/arity observed EXACTLY); badarg totality on non-atom M/F and out-of-range arity" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const mod = FinalTerms.atom(&m.ctx, try atoms.intern("lists"));
    const f = FinalTerms.atom(&m.ctx, try atoms.intern("reverse"));
    const fv = try make_fun_3(&m, &.{ mod, f, FinalTerms.int(&m.ctx, 1) });
    // the constructed term IS an export fun carrying exactly M/F/A
    try std.testing.expect(FinalTerms.repIsExportFun(&m.ctx, fv));
    try std.testing.expectEqual(try atoms.intern("lists"), FinalTerms.exportFunModuleIdx(&m.ctx, fv));
    try std.testing.expectEqual(try atoms.intern("reverse"), FinalTerms.exportFunFuncIdx(&m.ctx, fv));
    try std.testing.expectEqual(@as(u8, 1), FinalTerms.exportFunArity(&m.ctx, fv));
    // is_function/1-class observation holds (kindOf routes to the fun band)
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, fv) == .fun_);
    // badarg totality: non-atom M / non-atom F / non-int / negative / >255
    try std.testing.expectError(error.Badarg, make_fun_3(&m, &.{ FinalTerms.int(&m.ctx, 1), f, FinalTerms.int(&m.ctx, 1) }));
    try std.testing.expectError(error.Badarg, make_fun_3(&m, &.{ mod, FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 1) }));
    try std.testing.expectError(error.Badarg, make_fun_3(&m, &.{ mod, f, mod }));
    try std.testing.expectError(error.Badarg, make_fun_3(&m, &.{ mod, f, FinalTerms.int(&m.ctx, -1) }));
    try std.testing.expectError(error.Badarg, make_fun_3(&m, &.{ mod, f, FinalTerms.int(&m.ctx, 256) }));
    // a fun made for arity 0 differs from arity 1 (arity is load-bearing in the term)
    const fv0 = try make_fun_3(&m, &.{ mod, f, FinalTerms.int(&m.ctx, 0) });
    try std.testing.expect(!FinalTerms.eqlExact(&m.ctx, fv, fv0));
}

test "LAW gap-fun-info (DIVERGENCE 652): fun_info/2 deterministic items are byte-EQ vs OTP-30 — an EXTERNAL `fun M:F/A` is FULLY covered (type=external, module, name, arity, env=[]); a LOCAL closure covers arity/type=local/env; a local closure's module/name (+ every fun's uniq/index) are the honest deferred-funmeta RESIDUAL (clean badarg, never fabricated); a non-fun arg → badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const T = FinalTerms;
    const A = struct {
        fn a(mm: *Machine, s: []const u8) FinalTerms.Term {
            return T.atom(&mm.ctx, mm.ctx.atoms.intern(s) catch unreachable);
        }
    };
    const pair = struct {
        fn p(mm: *Machine, k: []const u8, v: FinalTerms.Term) !FinalTerms.Term {
            return T.tuple(&mm.ctx, &.{ A.a(mm, k), v });
        }
    };

    // ---- EXTERNAL fun `fun mod:func/2` — every deterministic item byte-EQ ----
    const ext = try T.makeExportFun(&m.ctx, A.a(&m, "mod"), A.a(&m, "func"), 2);
    try std.testing.expect(T.eqlExact(&m.ctx, try fun_info_2(&m, &.{ ext, A.a(&m, "arity") }), try pair.p(&m, "arity", T.int(&m.ctx, 2))));
    try std.testing.expect(T.eqlExact(&m.ctx, try fun_info_2(&m, &.{ ext, A.a(&m, "type") }), try pair.p(&m, "type", A.a(&m, "external"))));
    try std.testing.expect(T.eqlExact(&m.ctx, try fun_info_2(&m, &.{ ext, A.a(&m, "module") }), try pair.p(&m, "module", A.a(&m, "mod"))));
    try std.testing.expect(T.eqlExact(&m.ctx, try fun_info_2(&m, &.{ ext, A.a(&m, "name") }), try pair.p(&m, "name", A.a(&m, "func"))));
    try std.testing.expect(T.eqlExact(&m.ctx, try fun_info_2(&m, &.{ ext, A.a(&m, "env") }), try pair.p(&m, "env", T.nil(&m.ctx))));

    // ---- LOCAL closure (label=10, arity=1, env=[7]) — arity/type/env byte-EQ ----
    const loc = try T.makeFun(&m.ctx, 10, 1, &.{T.int(&m.ctx, 7)});
    try std.testing.expect(T.eqlExact(&m.ctx, try fun_info_2(&m, &.{ loc, A.a(&m, "arity") }), try pair.p(&m, "arity", T.int(&m.ctx, 1))));
    try std.testing.expect(T.eqlExact(&m.ctx, try fun_info_2(&m, &.{ loc, A.a(&m, "type") }), try pair.p(&m, "type", A.a(&m, "local"))));
    try std.testing.expect(T.eqlExact(&m.ctx, try fun_info_2(&m, &.{ loc, A.a(&m, "env") }), try pair.p(&m, "env", try T.cons(&m.ctx, T.int(&m.ctx, 7), T.nil(&m.ctx)))));

    // ---- RESIDUAL: a local closure's module/name + any fun's uniq/index → badarg
    //      (deferred-funmeta; a clean rejection, never a fabricated value, FM-OBS-1).
    try std.testing.expectError(error.Badarg, fun_info_2(&m, &.{ loc, A.a(&m, "module") }));
    try std.testing.expectError(error.Badarg, fun_info_2(&m, &.{ loc, A.a(&m, "name") }));
    try std.testing.expectError(error.Badarg, fun_info_2(&m, &.{ ext, A.a(&m, "uniq") }));
    // ---- totality: a non-fun / non-atom item → badarg.
    try std.testing.expectError(error.Badarg, fun_info_2(&m, &.{ T.int(&m.ctx, 5), A.a(&m, "arity") }));
    try std.testing.expectError(error.Badarg, fun_info_2(&m, &.{ ext, T.int(&m.ctx, 9) }));
}

test "LAW gap-fun-info-mfa (DIVERGENCE 727): fun_info_mfa/1 + fun_info(F,module|name) from make_fun3 fun_meta" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const T = FinalTerms;

    const mod_idx = try atoms.intern("mymod");
    const name_idx = try atoms.intern("-f/1-fun-0-");
    const label: u32 = 4242;
    // Simulate make_fun3's population for a LOCAL closure at `label` (the compiled
    // path does exactly this from the FunT-derived instruction fields — proven
    // end-to-end byte-EQ by fixtures/erl/zigvm_fun_info_mfa_diff.erl).
    try m.fun_meta.put(gpa, label, .{ mod_idx, name_idx, 2, 123456789 }); // {module,name,index,old_uniq} (DIVERGENCE 740/741)
    const loc = try T.makeFun(&m.ctx, label, 1, &.{});

    // fun_info_mfa/1 -> {mymod, '-f/1-fun-0-', 1} (was undef).
    const mfa = try fun_info_mfa_1(&m, &.{loc});
    try std.testing.expect(T.tupleArity(&m.ctx, mfa) == 3);
    try std.testing.expect(T.eqlExact(&m.ctx, T.tupleElem(&m.ctx, mfa, 0), T.atom(&m.ctx, mod_idx)));
    try std.testing.expect(T.eqlExact(&m.ctx, T.tupleElem(&m.ctx, mfa, 1), T.atom(&m.ctx, name_idx)));
    try std.testing.expectEqual(@as(i64, 1), T.smallValOf(T.tupleElem(&m.ctx, mfa, 2)));

    // fun_info(F, module) -> {module, mymod}; fun_info(F, name) -> {name, '-f/1-fun-0-'} (were badarg).
    const infomod = try fun_info_2(&m, &.{ loc, T.atom(&m.ctx, try atoms.intern("module")) });
    try std.testing.expect(T.eqlExact(&m.ctx, T.tupleElem(&m.ctx, infomod, 1), T.atom(&m.ctx, mod_idx)));
    const infoname = try fun_info_2(&m, &.{ loc, T.atom(&m.ctx, try atoms.intern("name")) });
    try std.testing.expect(T.eqlExact(&m.ctx, T.tupleElem(&m.ctx, infoname, 1), T.atom(&m.ctx, name_idx)));

    // DIVERGENCE 741: fun_info(F, index) -> {index, 2}; fun_info(F, uniq) -> {uniq,
    // 123456789} — the FunT Index + OldUniq integers from fun_meta[2]/[3] (were badarg).
    const infoidx = try fun_info_2(&m, &.{ loc, T.atom(&m.ctx, try atoms.intern("index")) });
    try std.testing.expectEqual(@as(i64, 2), T.smallValOf(T.tupleElem(&m.ctx, infoidx, 1)));
    const infouniq = try fun_info_2(&m, &.{ loc, T.atom(&m.ctx, try atoms.intern("uniq")) });
    try std.testing.expectEqual(@as(i64, 123456789), T.smallValOf(T.tupleElem(&m.ctx, infouniq, 1)));
    // new_uniq / new_index stay the honest deferred residual (md5-based, absent from the
    // old FunT chunk) → badarg, never a fabricated value.
    try std.testing.expectError(error.Badarg, fun_info_2(&m, &.{ loc, T.atom(&m.ctx, try atoms.intern("new_uniq")) }));
    try std.testing.expectError(error.Badarg, fun_info_2(&m, &.{ loc, T.atom(&m.ctx, try atoms.intern("new_index")) }));

    // RESIDUAL honesty (FM-OBS-1): a closure whose label is ABSENT from fun_meta (a
    // synthetic fun / cross-process transfer without the creating make_fun3) stays a
    // clean badarg — never a fabricated value.
    const orphan = try T.makeFun(&m.ctx, 9999, 1, &.{});
    try std.testing.expectError(error.Badarg, fun_info_mfa_1(&m, &.{orphan}));
    try std.testing.expectError(error.Badarg, fun_info_2(&m, &.{ orphan, T.atom(&m.ctx, try atoms.intern("module")) }));
}
