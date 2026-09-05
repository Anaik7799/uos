//! # bifs/atomics — the `atomics:`/`erts_internal:atomics_new` BIF family (E2.10)
//!
//! ## Signature
//! Same contract as the other family modules: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over
//! ALREADY-RESOLVED term arguments, driving `atomics_algebra.AtomicsRegistry`
//! — NO new atomics semantics live here (the array/registry algebra + its
//! wraparound/exchange/CAS laws live in `atomics_algebra.zig`; this module
//! only converts BEAM terms ↔ that algebra's `i128` cell values).
//!
//! ## WHERE STATE LIVES (the `ets`-Tid shape, restated)
//! `atomics:new/2` allocates a fixed-arity `AtomicsArray` and registers it in
//! `Machine.atomics` (an `atomics_algebra.AtomicsRegistry`), owned by the
//! Machine and freed in `Machine.deinit` — exactly the `m.ets`/`EtsRegistry`
//! precedent (`bifs/ets.zig`'s module doc). Every other `atomics:` BIF
//! resolves the Ref → `*AtomicsArray` and operates.
//!
//! ## Ref REPRESENTATION (a documented E-scope simplification, the ets Tid twin)
//! A real BEAM `atomics_ref()` is an opaque `reference()`. Here it is the
//! array's dense registry id, boxed as a small-integer TERM — the identical
//! simplification `bifs/ets.zig` documents for Tid (a genuine ref term / GC
//! finalization is deferred to a later term-representation epoch). Ids are
//! never reused within a Machine's lifetime.
//!
//! ## Bif.tab wiring (8 rows total: 1 under `erts_internal:`, 7 under `atomics:`)
//!   `erts_internal:atomics_new/2` — the REAL primitive underneath
//!   `atomics:new/2` (`atomics.erl`'s `new/2` is a library wrapper that
//!   validates+encodes `Opts` then calls `erts_internal:atomics_new/2` — see
//!   `erl_bif_atomics.c`'s `erts_internal_atomics_new_2`). This module wires
//!   the base-explicit primitive DIRECTLY. `atomics_new_2` reads the ENCODED
//!   INTEGER opts bitmask (`?OPT_SIGNED = 1 bsl 0`) that `atomics.erl`'s
//!   `encode_opts` produces — NOT an opts list — and REJECTS a list (DIVERGENCE
//!   726 / LAW E2.10c; the old list-parse badarg'd every compiled `atomics:new/2`
//!   and `counters:new/2`, the HANDLER-PROVEN-NOT-DIFFERENTIAL exemplar), the exact
//!   `erts_internal:list_to_integer/2` precedent already established for
//!   `erlang:list_to_integer/1,2` (`bifs/conv.zig`'s E2.5 scope note).
//!   `get/2`, `put/3`, `add/3`, `add_get/3`, `exchange/3`, `compare_exchange/4`,
//!   `info/1` — the `atomics:` module's own 7 bif.tab rows.
//!   `sub/3`/`sub_get/3` are NOT bif.tab rows (`atomics.erl`: `sub(Ref,Ix,Decr)
//!   -> add(Ref,Ix,-Decr)`, a pure Erlang-level wrapper around `add/3`/
//!   `add_get/3`) — the `maps:new/0` shape again; not wired.
//!
//! ## The `add/3` vs `add_get/3` CONTRACT (verified against `atomics.erl`, not assumed)
//! `add/3` returns the atom `ok` and DISCARDS the new value; `add_get/3`
//! returns the NEW (post-add) value. `atomics_algebra.AtomicsArray.add`
//! always returns the new value — `add_3` here discards it, `add_get_3`
//! returns it. Mutant 2 target: `add_3` returning the new value (like
//! `add_get_3`) instead of `ok`, or `add_get_3` returning the PRE-add value.
//!
//! ## Arg-type scope (SMALL-INTEGER only, the `bifs/erlang.zig` bitwise precedent)
//! `Ix`/`Value`/`Incr`/`Expected`/`Desired` must be small-integer terms
//! (`repIsSmall` — this term representation's small-int immediate is
//! ~60-bit signed, `term_algebra.smallVal`'s `w >> 4` shift, NOT the full
//! ±2^63-1 atomics range). A value near the i64 boundary that this term
//! system represents as a BIGNUM is therefore a documented, clean `badarg`
//! — the SAME scope limit `bifs/erlang.zig`'s `band`/`bor`/`bsl`/… family
//! already carries for its small-int-only arithmetic BIFs (not a new
//! divergence shape). The overwhelming common case (small counters/indices)
//! is exact; full ±2^63-1 coverage needs a bignum→u64-truncation conversion,
//! deferred alongside the same gap in the bitwise family.
//!
//! ## E6 SCOPE NOTE — sequential shadow, not concurrent atomicity
//! See `atomics_algebra.zig`'s module doc comment: zigvm is single-threaded
//! today, so every op here is the correct SEQUENTIAL contract but gives no
//! cross-thread ordering guarantee. Real SMP atomicity is the E6 epoch.
//!
//! ## Laws (see the suite below — reuses `atomics_algebra.zig`'s array laws,
//! adds the BIF-surface behavior: 1-based Ix, the Ref/Opts encoding, the
//! `add`-vs-`add_get` return-value split, `compare_exchange`'s `ok`/actual
//! contract)
//!   - ROUND-TRIP    `get(new(N,[]),1)` after `put(Ref,1,V)` == `V`.
//!   - CONTRACT       `add/3` == `ok`; `add_get/3` == the post-add value
//!     (mutant 2 target, see above).
//!   - COMPARE-EXCHANGE  matching CAS → `ok`; mismatched CAS → the actual
//!     current value (never mutates).
//!   - REJECTION      `Ix` out of `[1,Arity]`, a non-small-int arg, or a bad
//!     `Ref` → `badarg`, never a panic.
//!   - LEAK-FREE      `Machine.atomics` frees every live array on `deinit`.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const aa = @import("../atomics_algebra.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;
const AtomicsArray = aa.AtomicsArray;

fn boolTerm(m: *Machine, cond: bool) Term {
    return FinalTerms.atom(&m.ctx, if (cond) m.bool_true else m.bool_false);
}
fn internAtom(m: *Machine, name: []const u8) BifError!Term {
    const idx = m.ctx.atoms.intern(name) catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}
/// A `Ref` arg (a small-int registry id — see the module doc's Ref note).
fn resolveRef(m: *Machine, ref: Term) BifError!*AtomicsArray {
    if (!FinalTerms.repIsSmall(ref)) return error.Badarg;
    const v = FinalTerms.smallValOf(ref);
    if (v < 0) return error.Badarg;
    return m.atomics.byId(@intCast(v)) orelse error.Badarg;
}

/// A 1-based `Ix` arg, converted to the algebra's 0-based index; bounds are
/// checked by `AtomicsArray` itself (badarg on out-of-range).
fn ix0Of(ix_term: Term) BifError!usize {
    if (!FinalTerms.repIsSmall(ix_term)) return error.Badarg;
    const v = FinalTerms.smallValOf(ix_term);
    if (v < 1) return error.Badarg;
    return @intCast(v - 1);
}

/// `Value`/`Incr`/`Expected`/`Desired` — SMALL-INTEGER only (see the module
/// scope note).
fn smallI128(t: Term) BifError!i128 {
    if (!FinalTerms.repIsSmall(t)) return error.Badarg;
    return @as(i128, FinalTerms.smallValOf(t));
}

fn cellTerm(m: *Machine, v: i128) BifError!Term {
    return FinalTerms.intFromI128(&m.ctx, v) catch error.OutOfMemory;
}

// ── erts_internal:atomics_new/2 (the real primitive under atomics:new/2) ───

pub fn atomics_new_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsSmall(args[0])) return error.Badarg;
    const arity_i = FinalTerms.smallValOf(args[0]);
    if (arity_i < 1) return error.Badarg;
    const arity: usize = @intCast(arity_i);

    // erts_internal:atomics_new(Arity, EncodedOpts): the REAL contract passes an
    // INTEGER bitmask (atomics.erl `encode_opts`), NOT an opts list. ?OPT_SIGNED =
    // (1 bsl 0); ?OPT_DEFAULT = ?OPT_SIGNED (default signed). The compiled
    // `atomics:new/2` (and `counters:new/2` via the atomics backend) ALWAYS sends
    // this encoded int — the previous list-parse badarg'd every real compiled call
    // (HANDLER-PROVEN-NOT-DIFFERENTIAL, DIVERGENCE 726). A non-integer opts is what
    // the real primitive never receives -> badarg, matching erl_bif_atomics.c.
    if (!FinalTerms.repIsSmall(args[1])) return error.Badarg;
    const enc = FinalTerms.smallValOf(args[1]);
    const OPT_SIGNED: i64 = 1; // (1 bsl 0)
    const signed = (enc & OPT_SIGNED) != 0;

    const id = m.atomics.create(arity, signed) catch return error.OutOfMemory;
    return FinalTerms.int(&m.ctx, @intCast(id));
}

// ── atomics:get/2, put/3 ────────────────────────────────────────────────────

pub fn get_2(m: *Machine, args: []const Term) BifError!Term {
    const a = try resolveRef(m, args[0]);
    const ix0 = try ix0Of(args[1]);
    const v = a.get(ix0) catch return error.Badarg;
    return cellTerm(m, v);
}

pub fn put_3(m: *Machine, args: []const Term) BifError!Term {
    const a = try resolveRef(m, args[0]);
    const ix0 = try ix0Of(args[1]);
    const v = try smallI128(args[2]);
    a.put(ix0, v) catch return error.Badarg;
    return internAtom(m, "ok");
}

// ── atomics:add/3 (-> ok), add_get/3 (-> new value) ─────────────────────────

pub fn add_3(m: *Machine, args: []const Term) BifError!Term {
    const a = try resolveRef(m, args[0]);
    const ix0 = try ix0Of(args[1]);
    const incr = try smallI128(args[2]);
    _ = a.add(ix0, incr) catch return error.Badarg;
    return internAtom(m, "ok"); // add/3 discards the new value (the contract)
}

pub fn add_get_3(m: *Machine, args: []const Term) BifError!Term {
    const a = try resolveRef(m, args[0]);
    const ix0 = try ix0Of(args[1]);
    const incr = try smallI128(args[2]);
    const nv = a.add(ix0, incr) catch return error.Badarg;
    return cellTerm(m, nv);
}

// ── atomics:exchange/3, compare_exchange/4 ──────────────────────────────────

pub fn exchange_3(m: *Machine, args: []const Term) BifError!Term {
    const a = try resolveRef(m, args[0]);
    const ix0 = try ix0Of(args[1]);
    const desired = try smallI128(args[2]);
    const old = a.exchange(ix0, desired) catch return error.Badarg;
    return cellTerm(m, old);
}

/// `ok` if `Desired` was written; the ACTUAL current value if not.
pub fn compare_exchange_4(m: *Machine, args: []const Term) BifError!Term {
    const a = try resolveRef(m, args[0]);
    const ix0 = try ix0Of(args[1]);
    const expected = try smallI128(args[2]);
    const desired = try smallI128(args[3]);
    const r = a.compareExchange(ix0, expected, desired) catch return error.Badarg;
    return if (r) |actual| cellTerm(m, actual) else internAtom(m, "ok");
}

// ── atomics:info/1 ───────────────────────────────────────────────────────────

pub fn info_1(m: *Machine, args: []const Term) BifError!Term {
    const a = try resolveRef(m, args[0]);
    const keys = [_][]const u8{ "size", "max", "min", "memory" };
    const max_v = try cellTerm(m, a.maxVal());
    const min_v = try cellTerm(m, a.minVal());
    const vals = [_]Term{
        FinalTerms.int(&m.ctx, @intCast(a.len())),
        max_v,
        min_v,
        // Approximate (the `ets:info/1,2`/`persistent_term:info/0` precedent):
        // 8 bytes/cell plus a small fixed overhead.
        FinalTerms.int(&m.ctx, @intCast(a.len() * 8 + 64)),
    };
    var kts: [4]Term = undefined;
    for (keys, 0..) |k, i| kts[i] = try internAtom(m, k);
    return FinalTerms.mapNew(&m.ctx, &kts, &vals) catch error.OutOfMemory;
}

// ============================================================================
// Laws
// ============================================================================

const AtomTable = ta.AtomTable;

fn newArray(m: *Machine, arity: i64, signed: bool) BifError!Term {
    // Pass the encoded-int opts, matching the real erts_internal:atomics_new/2
    // contract (atomics.erl `encode_opts`): ?OPT_SIGNED = (1 bsl 0).
    const enc: i64 = if (signed) 1 else 0;
    return atomics_new_2(m, &.{ FinalTerms.int(&m.ctx, arity), FinalTerms.int(&m.ctx, enc) });
}

test "LAW E2.10 atomics: new/get/put round-trip; 1-based Ix; bad Ix -> badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const ref = try newArray(&m, 3, true);
    _ = try put_3(&m, &.{ ref, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 100) });
    try std.testing.expectEqual(@as(i64, 100), FinalTerms.smallValOf(try get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 1) })));
    try std.testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(try get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 3) })));

    try std.testing.expectError(error.Badarg, get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 0) })); // 0 is out-of-range (1-based)
    try std.testing.expectError(error.Badarg, get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 4) }));
    try std.testing.expectError(error.Badarg, get_2(&m, &.{ FinalTerms.int(&m.ctx, 999), FinalTerms.int(&m.ctx, 1) })); // bad ref
}

test "LAW E2.10 atomics: add/3 -> ok (discards); add_get/3 -> the NEW value (mutant 2)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const ref = try newArray(&m, 1, true);

    const r1 = try add_3(&m, &.{ ref, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 5) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r1, FinalTerms.atom(&m.ctx, try atoms.intern("ok"))));
    try std.testing.expectEqual(@as(i64, 5), FinalTerms.smallValOf(try get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 1) })));

    const r2 = try add_get_3(&m, &.{ ref, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 5) });
    try std.testing.expectEqual(@as(i64, 10), FinalTerms.smallValOf(r2)); // 5+5, the NEW value
}

test "LAW E2.10 atomics: exchange returns OLD value; compare_exchange ok-vs-actual contract" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const ref = try newArray(&m, 1, true);
    _ = try put_3(&m, &.{ ref, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 10) });

    const old = try exchange_3(&m, &.{ ref, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 20) });
    try std.testing.expectEqual(@as(i64, 10), FinalTerms.smallValOf(old));

    // matching CAS -> ok
    const ok = try compare_exchange_4(&m, &.{ ref, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 20), FinalTerms.int(&m.ctx, 30) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ok, FinalTerms.atom(&m.ctx, try atoms.intern("ok"))));
    // mismatched CAS -> the ACTUAL value (30), unchanged
    const mismatch = try compare_exchange_4(&m, &.{ ref, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 999), FinalTerms.int(&m.ctx, 40) });
    try std.testing.expectEqual(@as(i64, 30), FinalTerms.smallValOf(mismatch));
    try std.testing.expectEqual(@as(i64, 30), FinalTerms.smallValOf(try get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 1) })));
}

test "LAW E2.10 atomics: info/1 reports size/max/min/memory; unsigned array min is 0" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const ref = try newArray(&m, 4, false); // unsigned
    const info = try info_1(&m, &.{ref});
    const size_k = FinalTerms.atom(&m.ctx, try atoms.intern("size"));
    const min_k = FinalTerms.atom(&m.ctx, try atoms.intern("min"));
    try std.testing.expectEqual(@as(i64, 4), FinalTerms.smallValOf(FinalTerms.mapGet(&m.ctx, info, size_k).?));
    try std.testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(FinalTerms.mapGet(&m.ctx, info, min_k).?));
}

test "LAW E2.10c atomics_new/2 encoded-INT opts contract (DIVERGENCE 726 compiled-diff fix)" {
    // The REAL erts_internal:atomics_new/2 receives an INTEGER bitmask from
    // atomics.erl `encode_opts` (?OPT_SIGNED = 1 bsl 0), NEVER an opts list. Until
    // the primitive accepted the encoded int, every compiled `atomics:new/2` (and
    // `counters:new/2` via the atomics backend) badarg'd — a HANDLER-PROVEN-NOT-
    // DIFFERENTIAL divergence (the handler law fed a list the real path never sends).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // enc=1 (?OPT_SIGNED set) -> a signed array is CREATED from the encoded int and
    // supports the basic op set (proves the int is accepted, not badarg'd).
    const sref = try atomics_new_2(&m, &.{ FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 1) });
    _ = try put_3(&m, &.{ sref, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 42) });
    try std.testing.expectEqual(@as(i64, 42), FinalTerms.smallValOf(try get_2(&m, &.{ sref, FinalTerms.int(&m.ctx, 1) })));

    // enc=0 (?OPT_SIGNED clear) -> an UNSIGNED array: info min is 0 (a signed array's
    // min is the negative i64 floor, never 0) — so the ?OPT_SIGNED bit is truly read.
    const uref = try atomics_new_2(&m, &.{ FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 0) });
    const uinfo = try info_1(&m, &.{uref});
    const min_k = FinalTerms.atom(&m.ctx, try atoms.intern("min"));
    // eqlExact (not smallValOf) so a mutant that mis-signs the array — making min the
    // negative i64 floor (a bignum) — reds CLEANLY here rather than aborting in smallValOf.
    const umin = FinalTerms.mapGet(&m.ctx, uinfo, min_k).?;
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, umin, FinalTerms.int(&m.ctx, 0)));

    // REJECTION: an opts LIST (the shape the OLD list-parse accepted) is what the
    // real primitive NEVER receives -> badarg. Guards against regressing to the
    // list-parse that made every compiled atomics:new/2 badarg.
    const listopts = FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, try atoms.intern("signed")), FinalTerms.nil(&m.ctx)) catch unreachable;
    try std.testing.expectError(error.Badarg, atomics_new_2(&m, &.{ FinalTerms.int(&m.ctx, 2), listopts }));
    // arity < 1 stays badarg (unchanged contract).
    try std.testing.expectError(error.Badarg, atomics_new_2(&m, &.{ FinalTerms.int(&m.ctx, 0), FinalTerms.int(&m.ctx, 1) }));
}
