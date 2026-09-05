//! # bifs/records — the native-record BIF family (E3.14/S6, `records:` module)
//!
//! ## Signature
//! Same contract as every family module: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over ALREADY-
//! RESOLVED term arguments, computed via EXISTING term-algebra observations
//! (the E3.14 `native_record` term kind — NO new term semantics here). It
//! never panics on a well-formed call.
//!
//! ## Semantic domain — reuse, not reinvention
//! A native record denotes the E3.14 `(module, name, is_exported, keys[],
//! values[])` product (`term_algebra`, a distinct boxed kind). These BIFs are
//! the reflection API over it: `create/4` BUILDS one from ordinary terms
//! (module/name atoms, a `[{Key,Value}]` field list, an `#{is_exported=>B}`
//! opts map — the pin's `records_create_4`, which is SELF-CONTAINED: the
//! global staged record table it consults at the end is only a def-SHARING
//! optimization, so a locally-built def is returned unchanged); `update/4`
//! overrides fields of an existing record; `get_module/1`, `get_name/1`,
//! `get/2`, `get_field_names/1`, `is_exported/1` OBSERVE one. `create/4` is
//! the corpus-reachable ENTRY POINT (all-ordinary-term args), which is why
//! this whole family is genuinely end-to-end reachable via `call_ext_bif`.
//!
//! ## Reachability / evidence level (call_ext honesty)
//! All seven flip EQ: they compile to `call_ext` and DISPATCH through
//! `call_ext_bif` since E3.12 (the entry-25 mechanism), are PURE (no
//! scheduler/pid/Vm topology), and are implemented + law-proven here. The
//! evidence level is LAW-DRIVEN, not differential: host OTP 28 has no
//! `records` module at all (native records are OTP-29+), and W-11 already
//! bounds the corpus oracle to bring-up — so there is no oracle to
//! byte-compare against. The flip rests on implemented-map membership +
//! call_ext_bif reachability + these Zig laws, exactly the evidence level the
//! 6 opcodes flip on (dump-caps ∩ genop.tab totality + Zig laws). See
//! DIVERGENCE_LOG.md entry 3 (amended).
//!
//! ## Deferred within the family
//! `records:get_definition/2` queries the GLOBAL record-definition table
//! (module,name)→def that the COMPILER / code server populates — zigvm has no
//! such table (records are self-describing here). E7.2 (DIVERGENCE 147) VERIFIED
//! empirically: on the OTP-28 host `records:get_definition/2` raises
//! `error:undef` (the whole `records` module is absent — native records are an
//! OTP-30 feature), a 28-vs-30 SKEW with NO differential to byte-compare. Unlike
//! the 7 flipped rows (self-contained over ordinary-term args), get_definition/2
//! has no self-contained entry point (it needs the compiler-populated table), so
//! a law-driven flip would be contrived — re-bound `deferred-oracle-skew`, owner
//! the pinned-OTP-30 oracle-toolchain build (the check_process_code precedent).
//!
//! ## Field storage & order (documented bound)
//! erts stores a record's keys SORTED and reconstructs insertion order via a
//! `field_order` tuple; zigvm stores keys in INSERTION order and looks up by
//! exact atom equality. `get_field_names/1` observes insertion order (== the
//! pin's insertion-order output); `get/2` is order-independent. The only
//! divergence is the internal def-sharing/hash the global table would give —
//! not observable through these BIFs. (DIVERGENCE entry 3 amendment.)

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

fn boolAtom(m: *Machine, b: bool) BifError!Term {
    const idx = m.ctx.atoms.intern(if (b) "true" else "false") catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

/// `error:{badrecord, Value}` (erl_record.c EXC_BADRECORD). Structured, via
/// the shared raise machinery (guard/body split handled by the caller path).
fn raiseBadrecord(m: *Machine, value: Term) BifError {
    const idx = m.ctx.atoms.intern("badrecord") catch return error.OutOfMemory;
    const tup = FinalTerms.tuple(&m.ctx, &.{ FinalTerms.atom(&m.ctx, idx), value }) catch return error.OutOfMemory;
    return m.bifRaise(.error_, tup);
}

/// `error:{badfield, Field}` (erl_record.c EXC_BADFIELD).
fn raiseBadfield(m: *Machine, field: Term) BifError {
    const idx = m.ctx.atoms.intern("badfield") catch return error.OutOfMemory;
    const tup = FinalTerms.tuple(&m.ctx, &.{ FinalTerms.atom(&m.ctx, idx), field }) catch return error.OutOfMemory;
    return m.bifRaise(.error_, tup);
}

// ── records:get_module/1, records:get_name/1 ────────────────────────────────

pub fn get_module_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsNativeRecord(&m.ctx, args[0])) return error.Badarg;
    return FinalTerms.nrModule(&m.ctx, args[0]);
}

pub fn get_name_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsNativeRecord(&m.ctx, args[0])) return error.Badarg;
    return FinalTerms.nrName(&m.ctx, args[0]);
}

// ── records:get/2 (Key, Record) ─────────────────────────────────────────────

pub fn get_2(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const rec = args[1];
    if (!FinalTerms.repIsNativeRecord(&m.ctx, rec) or FinalTerms.kindOf(&m.ctx, key) != .atom)
        return error.Badarg;
    return FinalTerms.nrLookup(&m.ctx, rec, key) orelse return error.Badarg;
}

// ── records:get_field_names/1 ───────────────────────────────────────────────

pub fn get_field_names_1(m: *Machine, args: []const Term) BifError!Term {
    const rec = args[0];
    if (!FinalTerms.repIsNativeRecord(&m.ctx, rec)) return raiseBadrecord(m, rec);
    const n = FinalTerms.nrFieldCount(&m.ctx, rec);
    var acc = FinalTerms.nil(&m.ctx);
    var i = n;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.nrKeyAt(&m.ctx, rec, i), acc) catch return error.OutOfMemory;
    }
    return acc;
}

// ── records:is_exported/1 ───────────────────────────────────────────────────

pub fn get_definition_2(_: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0]) or !FinalTerms.repIsAtom(args[1])) return error.Badarg;
    return error.Badarg;
}

pub fn is_exported_1(m: *Machine, args: []const Term) BifError!Term {
    const rec = args[0];
    if (!FinalTerms.repIsNativeRecord(&m.ctx, rec)) return raiseBadrecord(m, rec);
    return boolAtom(m, FinalTerms.nrIsExported(&m.ctx, rec));
}

// ── records:create/4 (Module, Name, Fields, Opts) ───────────────────────────

pub fn create_4(m: *Machine, args: []const Term) BifError!Term {
    const module = args[0];
    const name = args[1];
    const fields = args[2];
    const opts = args[3];
    if (FinalTerms.kindOf(&m.ctx, module) != .atom or FinalTerms.kindOf(&m.ctx, name) != .atom)
        return error.Badarg;
    // Opts must be a map with exactly the is_exported key (a boolean atom).
    if (!FinalTerms.repIsMap(&m.ctx, opts) or FinalTerms.mapSize(&m.ctx, opts) != 1)
        return error.Badarg;
    const exp_key = FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("is_exported") catch return error.OutOfMemory);
    const exp_v = FinalTerms.mapGet(&m.ctx, opts, exp_key) orelse return error.Badarg;
    const t_atom = FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("true") catch return error.OutOfMemory);
    const f_atom = FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("false") catch return error.OutOfMemory);
    const is_exported = if (FinalTerms.eqlExact(&m.ctx, exp_v, t_atom))
        true
    else if (FinalTerms.eqlExact(&m.ctx, exp_v, f_atom))
        false
    else
        return error.Badarg;

    // Fields is a proper list of {Key, Value} with distinct atom keys.
    var keys: [ta.max_nr_fields]Term = undefined;
    var vals: [ta.max_nr_fields]Term = undefined;
    var n: usize = 0;
    var cur = fields;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        if (n >= ta.max_nr_fields) return error.Badarg; // capacity bound
        const pair = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.kindOf(&m.ctx, pair) != .tuple or FinalTerms.tupleArity(&m.ctx, pair) != 2)
            return error.Badarg;
        const key = FinalTerms.tupleElem(&m.ctx, pair, 0);
        if (FinalTerms.kindOf(&m.ctx, key) != .atom) return error.Badarg;
        // reject duplicate keys (erts qsort dedup check)
        for (0..n) |j| if (FinalTerms.eqlExact(&m.ctx, keys[j], key)) return error.Badarg;
        keys[n] = key;
        vals[n] = FinalTerms.tupleElem(&m.ctx, pair, 1);
        n += 1;
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg; // improper list
    return FinalTerms.nativeRecord(&m.ctx, module, name, is_exported, keys[0..n], vals[0..n]) catch return error.OutOfMemory;
}

// ── records:update/4 (Record, Module, Name, UpdatesMap) ─────────────────────

pub fn update_4(m: *Machine, args: []const Term) BifError!Term {
    const rec = args[0];
    const id_module = args[1];
    const id_name = args[2];
    const updates = args[3];
    if (!FinalTerms.repIsNativeRecord(&m.ctx, rec)) return raiseBadrecord(m, rec);
    // Module/Name may be the atom `_` (no check) or must match the record.
    const under = FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("_") catch return error.OutOfMemory);
    const skip = FinalTerms.eqlExact(&m.ctx, id_module, under) and FinalTerms.eqlExact(&m.ctx, id_name, under);
    if (!skip) {
        if (FinalTerms.kindOf(&m.ctx, id_module) != .atom or FinalTerms.kindOf(&m.ctx, id_name) != .atom)
            return raiseBadrecord(m, id_name);
        if (!FinalTerms.eqlExact(&m.ctx, FinalTerms.nrModule(&m.ctx, rec), id_module) or
            !FinalTerms.eqlExact(&m.ctx, FinalTerms.nrName(&m.ctx, rec), id_name))
            return raiseBadrecord(m, id_name);
    }
    if (!FinalTerms.repIsMap(&m.ctx, updates)) return error.Badarg;
    if (FinalTerms.mapSize(&m.ctx, updates) == 0) return rec; // empty map: unchanged

    const nf = FinalTerms.nrFieldCount(&m.ctx, rec);
    var keys: [ta.max_nr_fields]Term = undefined;
    var vals: [ta.max_nr_fields]Term = undefined;
    for (0..nf) |i| {
        keys[i] = FinalTerms.nrKeyAt(&m.ctx, rec, i);
        vals[i] = FinalTerms.nrValAt(&m.ctx, rec, i);
    }
    // Walk the updates map; each key must be a field (else badfield).
    const nu = FinalTerms.mapSize(&m.ctx, updates);
    const uk = m.gpa.alloc(Term, nu) catch return error.OutOfMemory;
    defer m.gpa.free(uk);
    const uv = m.gpa.alloc(Term, nu) catch return error.OutOfMemory;
    defer m.gpa.free(uv);
    _ = FinalTerms.mapPairs(&m.ctx, updates, uk, uv);
    for (uk, uv) |k, v| {
        var found = false;
        for (0..nf) |i| {
            if (FinalTerms.eqlExact(&m.ctx, keys[i], k)) {
                vals[i] = v;
                found = true;
                break;
            }
        }
        if (!found) return raiseBadfield(m, k);
    }
    return FinalTerms.nativeRecord(&m.ctx, FinalTerms.nrModule(&m.ctx, rec), FinalTerms.nrName(&m.ctx, rec), FinalTerms.nrIsExported(&m.ctx, rec), keys[0..nf], vals[0..nf]) catch return error.OutOfMemory;
}

// ============================================================================
// Laws
// ============================================================================

const testing = std.testing;

fn mkAtom(m: *Machine, name: []const u8) !Term {
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern(name));
}

test "LAW E3.14 records:create/4 + observers round-trip (module/name/get/field_names/is_exported)" {
    var atoms = AtomTable.init(testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(testing.allocator, &atoms);
    defer m.deinit();

    const module = try mkAtom(&m, "mymod");
    const name = try mkAtom(&m, "point");
    const kx = try mkAtom(&m, "x");
    const ky = try mkAtom(&m, "y");
    // #{is_exported => true}
    const opts = try FinalTerms.mapNew(&m.ctx, &.{try mkAtom(&m, "is_exported")}, &.{try mkAtom(&m, "true")});
    // Fields = [{x,1},{y,2}]
    const p1 = try FinalTerms.tuple(&m.ctx, &.{ kx, FinalTerms.int(&m.ctx, 1) });
    const p2 = try FinalTerms.tuple(&m.ctx, &.{ ky, FinalTerms.int(&m.ctx, 2) });
    const fields = try FinalTerms.cons(&m.ctx, p1, try FinalTerms.cons(&m.ctx, p2, FinalTerms.nil(&m.ctx)));

    const rec = try create_4(&m, &.{ module, name, fields, opts });
    try testing.expect(FinalTerms.repIsNativeRecord(&m.ctx, rec));
    try testing.expect(FinalTerms.eqlExact(&m.ctx, try get_module_1(&m, &.{rec}), module));
    try testing.expect(FinalTerms.eqlExact(&m.ctx, try get_name_1(&m, &.{rec}), name));
    try testing.expect(FinalTerms.eqlExact(&m.ctx, try get_2(&m, &.{ kx, rec }), FinalTerms.int(&m.ctx, 1)));
    try testing.expect(FinalTerms.eqlExact(&m.ctx, try get_2(&m, &.{ ky, rec }), FinalTerms.int(&m.ctx, 2)));
    try testing.expect(FinalTerms.eqlExact(&m.ctx, try is_exported_1(&m, &.{rec}), try mkAtom(&m, "true")));
    // get_field_names → [x,y] (insertion order)
    const names = try get_field_names_1(&m, &.{rec});
    try testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, names), kx));
    try testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, FinalTerms.listTail(&m.ctx, names)), ky));

    // get/2 of an absent key → badarg; get on a non-record → badarg
    try testing.expectError(error.Badarg, get_2(&m, &.{ try mkAtom(&m, "z"), rec }));
    try testing.expectError(error.Badarg, get_module_1(&m, &.{FinalTerms.int(&m.ctx, 7)}));
    // create with a duplicate key → badarg (mutant 2 target)
    const dupf = try FinalTerms.cons(&m.ctx, p1, try FinalTerms.cons(&m.ctx, p1, FinalTerms.nil(&m.ctx)));
    try testing.expectError(error.Badarg, create_4(&m, &.{ module, name, dupf, opts }));
}

test "LAW E3.14 records:update/4 overrides fields; unknown field raises badfield; source unchanged" {
    var atoms = AtomTable.init(testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(testing.allocator, &atoms);
    defer m.deinit();

    const module = try mkAtom(&m, "mymod");
    const name = try mkAtom(&m, "point");
    const kx = try mkAtom(&m, "x");
    const ky = try mkAtom(&m, "y");
    const rec = try FinalTerms.nativeRecord(&m.ctx, module, name, true, &.{ kx, ky }, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) });
    // update #{x => 9} with Module/Name = _ (no check)
    const under = try mkAtom(&m, "_");
    const upd = try FinalTerms.mapNew(&m.ctx, &.{kx}, &.{FinalTerms.int(&m.ctx, 9)});
    const out = try update_4(&m, &.{ rec, under, under, upd });
    try testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrLookup(&m.ctx, out, kx).?, FinalTerms.int(&m.ctx, 9)));
    try testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrLookup(&m.ctx, out, ky).?, FinalTerms.int(&m.ctx, 2)));
    // source unchanged (aliasing)
    try testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.nrLookup(&m.ctx, rec, kx).?, FinalTerms.int(&m.ctx, 1)));
    // unknown field → error.Raise (badfield)
    const bad = try FinalTerms.mapNew(&m.ctx, &.{try mkAtom(&m, "z")}, &.{FinalTerms.int(&m.ctx, 0)});
    try testing.expectError(error.Raise, update_4(&m, &.{ rec, under, under, bad }));
}
