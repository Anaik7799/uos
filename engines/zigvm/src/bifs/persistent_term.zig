//! # bifs/persistent_term — the `persistent_term:` BIF family (E2.10)
//!
//! ## Signature
//! Same contract as the other family modules: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over
//! ALREADY-RESOLVED term arguments, driving `registry.PersistentTerms` — NO
//! new persistent-term semantics live here (M10/S24 already specified and
//! law-tested `put`/`get`/`erase`/literal-immunity in `registry.zig`; E2.10
//! only ADDS `count`/`memoryBytes` observers there for `info/0`, see that
//! module's doc comment).
//!
//! ## WHERE STATE LIVES (the crux — process-EXTERNAL, unlike ETS's per-Tid tables)
//! `persistent_term` is ONE GLOBAL key→value store (no handle/Tid — every
//! process sees the SAME table), so the Machine owns exactly ONE
//! `registry.PersistentTerms` (`m.pterm`), not a registry-of-tables like
//! `m.ets`. Freed in `Machine.deinit`. `put` copies (Key,Value) OFF the
//! process heap into `pterm`'s own immutable literal region (M10's literal-
//! immunity law — collecting the process heap never moves/frees a stored
//! term); `registry.get` is a cheap hash probe returning a REGION-relative
//! term.
//!
//! ## COPY-BACK IS MANDATORY ON EVERY READ (the crux — differs from ETS)
//! Because the store uses a SEPARATE heap (`pterm.region`), a value handed
//! back by `registry.get` is an offset into `region.words`, NOT `m.ctx.words`.
//! The `bif_call` executor writes a BIF result straight into a process
//! register (`setDst`, no copy), so every read BIF here (`get/1`, `get/2`'s
//! present branch, `get/0`, and `put_new/2`'s exact-equality compare) MUST
//! first `gcCopy` the region term onto `m.ctx` (helper `copyBack`). An
//! IMMEDIATE value (small int / atom / nil) is its own "offset" and survives
//! uncopied — which is why an integer-only law suite masks the bug — but a
//! BOXED value (tuple/list/float/bignum/binary/map) read without copy-back is
//! a WRONG `m.ctx` term and, for a large stored term, an OUT-OF-BOUNDS read.
//! (ETS needs NO such copy — its tables store shared `m.ctx` offsets directly;
//! the separate-heap store is what makes the copy load-bearing here. BEAM's
//! "cheap get, expensive put" asymmetry still holds structurally: put does a
//! full deep copy into the region, get does a probe + a shallow term copy.)
//!
//! ## The dispatch mechanism (unchanged — see `bifs/dispatch.zig`)
//! This task adds ONLY `pub fn`s here, an `implOf`/`implOfPersistentTerm` arm
//! in `bifs/dispatch.zig`, and `implemented_map` rows in
//! `harness/bif_gen.ml`. The generated `bif_table.zig`, the loader, and the
//! `bif_call` executor are untouched.
//!
//! ## Wiring (7 bif.tab rows)
//!   `put/2`     — copy (Key,Value) into the region; ALWAYS succeeds
//!                 (`registry.PersistentTerms.put` overwrites on a repeat
//!                 key — "last wins", already law-tested in `registry.zig`).
//!   `put_new/2` — `put/2` iff the key is ABSENT or the stored value is
//!                 exact-equal to `Value` (a no-op then); a PRESENT key with
//!                 a DIFFERENT value → `badarg` (never overwrites silently —
//!                 the one place this family diverges from `put/2`'s
//!                 always-overwrite contract).
//!   `get/1`     — the stored value, or `badarg` if the key is absent.
//!   `get/2`     — the stored value, or `Default` if absent (NEVER badarg).
//!   `get/0`     — `[{K,V}, …]` over every live entry (order: registry
//!                 iteration order — a documented divergence from BEAM's
//!                 insertion/creation order, the SAME shape as `ets`
//!                 first/next's hash-bucket-order divergence already
//!                 recorded).
//!   `erase/1`   — `true` if a key was removed, `false` if absent.
//!   `info/0`    — `#{count => N, memory => Bytes}` (a documented
//!                 APPROXIMATION of `memory` — region words × 8, the
//!                 `ets:info/1,2` field-SUBSET precedent, not exact erts
//!                 per-term accounting).
//!
//! ## Lifetime safety
//! Every value flowing through here is a `Term` VALUE (a `ctx`/`region`
//! offset), never a raw slice — `get/0`'s collected `{K,V}` tuples are built
//! from `pterm.region`-resident terms COPIED (via `gcCopy`, reused, not
//! reinvented) onto the CALLING process's `m.ctx` heap before being consed
//! into the result list, so the returned list lives correctly on the
//! process heap (never aliases the immutable region) and stays valid across
//! a later process-heap GC.
//!
//! ## Laws (see the suite below — reuses `registry.zig`'s put/get/erase laws,
//! adds the BIF-surface behavior: default-arg, get/0 enumeration, info/0)
//!   - ROUND-TRIP     `get(K)` after `put(K,V)` == `V` (denotation-equal).
//!   - DEFAULT         `get(K,D)` on an absent key == `D` (never badarg) —
//!                     mutant 2 target: returning the default even when the
//!                     key IS present.
//!   - REJECTION       `get(K)` on an absent key (no /2 default) → `badarg`.
//!   - ENUMERATION     `get/0` contains every `put`'d key exactly once
//!                     (post-`erase` exclusion checked too).
//!   - INFO            `count` == the number of live entries; `memory` grows
//!                     monotonically as entries are added (never shrinks on
//!                     an `erase` — matches the "literal region never
//!                     compacts" M10 invariant, since `erase` only removes
//!                     the TABLE row, not the region words already written).

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const reg = @import("../registry.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

fn boolTerm(m: *Machine, cond: bool) Term {
    return FinalTerms.atom(&m.ctx, if (cond) m.bool_true else m.bool_false);
}
fn internAtom(m: *Machine, name: []const u8) BifError!Term {
    const idx = m.ctx.atoms.intern(name) catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

pub fn put_2(m: *Machine, args: []const Term) BifError!Term {
    m.pterm.put(&m.ctx, args[0], args[1]) catch return error.OutOfMemory;
    return internAtom(m, "ok");
}

/// Copy a stored (region-resident) value onto the CALLING process heap
/// (`m.ctx`). This copy-back is MANDATORY on EVERY read path, not just
/// `get/0`: `m.pterm.get` returns a term whose offset indexes
/// `m.pterm.region.words`, but the executor writes the BIF result straight
/// into a process register (`setDst`, no copy) where it is interpreted
/// against `m.ctx.words`. For an IMMEDIATE value (small int / atom / nil)
/// the "offset" is the value itself, so it happens to work uncopied — which
/// is exactly why the original integer-only laws masked the bug. For any
/// BOXED value (tuple/list/float/bignum/binary/map) the raw region offset is
/// a WRONG `m.ctx` term (garbage) and, for a large stored term, can exceed
/// `m.ctx.words.len` → an out-of-bounds read. `gcCopy` re-materializes the
/// term into `m.ctx`, returning a valid `m.ctx`-relative term. (ETS does NOT
/// need this — its tables store shared `m.ctx` offsets directly; persistent_
/// term uses a SEPARATE heap, so the copy is load-bearing.)
fn copyBack(m: *Machine, region_term: Term) BifError!Term {
    return FinalTerms.gcCopy(&m.ctx, &m.pterm.region, region_term) catch error.OutOfMemory;
}

/// `put_new/2` — absent key: store, `ok`. Present key with the SAME value
/// (exact equality): no-op, `ok`. Present key with a DIFFERENT value:
/// `badarg` (never silently overwrites).
pub fn put_new_2(m: *Machine, args: []const Term) BifError!Term {
    if (m.pterm.get(&m.ctx, args[0])) |existing| {
        // `existing` is a REGION term — copy it onto `m.ctx` before the
        // exact-equality compare, else `eqlExact(&m.ctx, existing, args[1])`
        // walks a region offset against `m.ctx.words` (garbage for a boxed
        // value, potentially OOB). Copied, both operands are `m.ctx` terms.
        const existing_here = try copyBack(m, existing);
        if (!FinalTerms.eqlExact(&m.ctx, existing_here, args[1])) return error.Badarg;
        return internAtom(m, "ok"); // same value already stored: quick no-op
    }
    m.pterm.put(&m.ctx, args[0], args[1]) catch return error.OutOfMemory;
    return internAtom(m, "ok");
}

pub fn get_1(m: *Machine, args: []const Term) BifError!Term {
    const v = m.pterm.get(&m.ctx, args[0]) orelse return error.Badarg;
    return copyBack(m, v);
}

/// `get/2` NEVER raises on an absent key — `Default` is returned instead
/// (mutant 2 target: badarg-ing here, or returning the default when the key
/// IS present). A PRESENT value is copied region→`m.ctx` (see `copyBack`);
/// the `Default` is already an `m.ctx` term, so it is returned as-is.
pub fn get_2(m: *Machine, args: []const Term) BifError!Term {
    if (m.pterm.get(&m.ctx, args[0])) |v| return copyBack(m, v);
    return args[1];
}

pub fn get_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    var items: std.ArrayList(Term) = .empty;
    defer items.deinit(m.gpa);
    var it = m.pterm.table.valueIterator();
    while (it.next()) |e| {
        // Copy the (region-resident) key/value onto the CALLING process heap
        // before consing — the returned list must never alias the immutable
        // literal region (lifetime safety + the boxed-offset hazard `copyBack`
        // documents).
        const kcopy = try copyBack(m, e.key);
        const vcopy = try copyBack(m, e.val);
        const tup = FinalTerms.tuple(&m.ctx, &.{ kcopy, vcopy }) catch return error.OutOfMemory;
        items.append(m.gpa, tup) catch return error.OutOfMemory;
    }
    var acc = FinalTerms.nil(&m.ctx);
    var i = items.items.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, items.items[i], acc) catch return error.OutOfMemory;
    }
    return acc;
}

pub fn erase_1(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, m.pterm.erase(&m.ctx, args[0]));
}

/// E3.18: `erts_internal:erase_persistent_terms/0` — drop every persistent term
/// and return `true` (erts `erl_bif_persistent.c` returns `am_true`).
pub fn erase_persistent_terms_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pterm.clearAll();
    return boolTerm(m, true);
}

pub fn info_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const count_k = try internAtom(m, "count");
    const memory_k = try internAtom(m, "memory");
    const count_v = FinalTerms.int(&m.ctx, @intCast(m.pterm.count()));
    const memory_v = FinalTerms.int(&m.ctx, @intCast(m.pterm.memoryBytes()));
    return FinalTerms.mapNew(&m.ctx, &.{ count_k, memory_k }, &.{ count_v, memory_v }) catch error.OutOfMemory;
}

// ============================================================================
// Laws
// ============================================================================

const AtomTable = ta.AtomTable;

test "LAW E2.10 persistent_term: get after put denotes the stored value; absent -> badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const key = FinalTerms.atom(&m.ctx, try atoms.intern("cfg"));
    const val = FinalTerms.int(&m.ctx, 42);
    _ = try put_2(&m, &.{ key, val });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try get_1(&m, &.{key}), val));

    const absent = FinalTerms.atom(&m.ctx, try atoms.intern("nope"));
    try std.testing.expectError(error.Badarg, get_1(&m, &.{absent}));
}

test "LAW E2.10 persistent_term: get/2 DEFAULT on absent key, real value when present (mutant 2)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const key = FinalTerms.atom(&m.ctx, try atoms.intern("k"));
    const val = FinalTerms.int(&m.ctx, 7);
    const default = FinalTerms.int(&m.ctx, -1);

    // absent -> default
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try get_2(&m, &.{ key, default }), default));
    // present -> the REAL value, not the default
    _ = try put_2(&m, &.{ key, val });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try get_2(&m, &.{ key, default }), val));
}

test "LAW E2.10 persistent_term: get/1,get/2 copy a BOXED stored value region->m.ctx (denotes original, not a raw offset)" {
    // REGRESSION (reviewer-found Critical): a boxed stored value lives at an
    // offset into `m.pterm.region.words`; returning it uncopied makes the
    // executor interpret that offset against `m.ctx.words` -> a WRONG value
    // (garbage) or, for a large term, an OUT-OF-BOUNDS read. Every current
    // integer-only law passes because an immediate is its own offset. This law
    // stores BOXED values (tuple/list/float) and pre-GROWS `m.ctx` first so a
    // naive region offset lands on unrelated (or out-of-range) `m.ctx` words,
    // then asserts get/1 and get/2 DENOTE the original.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // Pre-pad the process heap so the region's small offsets are already
    // occupied by unrelated `m.ctx` data (makes a raw-offset read visibly wrong).
    var pad: usize = 0;
    while (pad < 64) : (pad += 1) {
        _ = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 999), FinalTerms.int(&m.ctx, 999) });
    }

    const kt = FinalTerms.atom(&m.ctx, try atoms.intern("tup"));
    const kl = FinalTerms.atom(&m.ctx, try atoms.intern("lst"));
    const kf = FinalTerms.atom(&m.ctx, try atoms.intern("flt"));

    // Store BOXED values: a tuple {111,222}, a list [1,2,3], a float 3.5.
    const tup = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 111), FinalTerms.int(&m.ctx, 222) });
    const lst = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 2), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 3), FinalTerms.nil(&m.ctx))));
    const flt = FinalTerms.float(&m.ctx, 3.5);
    _ = try put_2(&m, &.{ kt, tup });
    _ = try put_2(&m, &.{ kl, lst });
    _ = try put_2(&m, &.{ kf, flt });

    // get/1 must denote the original boxed value (structure-exact on m.ctx).
    const got_t = try get_1(&m, &.{kt});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, got_t) == .tuple);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&m.ctx, got_t));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got_t, try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 111), FinalTerms.int(&m.ctx, 222) })));

    const got_l = try get_1(&m, &.{kl});
    const want_l = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 2), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 3), FinalTerms.nil(&m.ctx))));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got_l, want_l));

    // get/2 present branch takes the SAME copy-back path.
    const got_f = try get_2(&m, &.{ kf, FinalTerms.nil(&m.ctx) });
    try std.testing.expect(FinalTerms.repIsFloat(&m.ctx, got_f));
    try std.testing.expectEqual(@as(f64, 3.5), FinalTerms.floatValOf(&m.ctx, got_f));
}

test "LAW E2.10 persistent_term: put_new/2 compares a BOXED existing value across heaps (region->m.ctx before eqlExact)" {
    // REGRESSION: `put_new/2` exact-compares the STORED value (a region term)
    // against the caller's arg; without copy-back the compare walks a region
    // offset against m.ctx -> garbage for a boxed value. This law stores a
    // boxed tuple, then put_new/2 with the SAME structure (must no-op ok) and
    // a DIFFERENT structure (must badarg).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    var pad: usize = 0;
    while (pad < 32) : (pad += 1) {
        _ = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 7), FinalTerms.int(&m.ctx, 8) });
    }

    const key = FinalTerms.atom(&m.ctx, try atoms.intern("bk"));
    const ok_atom = FinalTerms.atom(&m.ctx, try atoms.intern("ok"));
    const v_stored = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 111), FinalTerms.int(&m.ctx, 222) });
    _ = try put_2(&m, &.{ key, v_stored });

    // same boxed structure -> quick no-op ok (the cross-heap compare must
    // succeed, which it cannot do on a raw region offset).
    const v_same = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 111), FinalTerms.int(&m.ctx, 222) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try put_new_2(&m, &.{ key, v_same }), ok_atom));
    // stored value unchanged, still denotes {111,222}.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try get_1(&m, &.{key}), v_same));

    // different boxed structure -> badarg (never overwrites).
    const v_diff = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 111), FinalTerms.int(&m.ctx, 333) });
    try std.testing.expectError(error.Badarg, put_new_2(&m, &.{ key, v_diff }));
}

test "LAW E2.10 persistent_term: get/0 enumerates every live entry; erase excludes it; info/0 count" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const k1 = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const k2 = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const v1 = FinalTerms.int(&m.ctx, 1);
    const v2 = FinalTerms.int(&m.ctx, 2);
    _ = try put_2(&m, &.{ k1, v1 });
    _ = try put_2(&m, &.{ k2, v2 });

    const all1 = try get_0(&m, &.{});
    try std.testing.expectEqual(@as(i64, 2), FinalTerms.smallValOf(try (struct {
        fn len(mm: *Machine, l: Term) BifError!Term {
            var n: i64 = 0;
            var cur = l;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) : (n += 1) cur = FinalTerms.listTail(&mm.ctx, cur);
            return FinalTerms.int(&mm.ctx, n);
        }
    }.len)(&m, all1)));

    try std.testing.expectEqual(@as(usize, 2), m.pterm.count());
    const info = try info_0(&m, &.{});
    const count_k = FinalTerms.atom(&m.ctx, try atoms.intern("count"));
    try std.testing.expectEqual(@as(i64, 2), FinalTerms.smallValOf(FinalTerms.mapGet(&m.ctx, info, count_k).?));

    // erase k1 -> true; k1 no longer resolves; get/0 now has exactly 1 entry.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try erase_1(&m, &.{k1}), FinalTerms.atom(&m.ctx, m.bool_true)));
    try std.testing.expectError(error.Badarg, get_1(&m, &.{k1}));
    try std.testing.expectEqual(@as(usize, 1), m.pterm.count());
    // erase of an absent key -> false.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try erase_1(&m, &.{k1}), FinalTerms.atom(&m.ctx, m.bool_false)));

    // E3.18: erase_persistent_terms/0 drops EVERY term -> true, count 0, every
    // prior key now badargs on get/1.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try erase_persistent_terms_0(&m, &.{}), FinalTerms.atom(&m.ctx, m.bool_true)));
    try std.testing.expectEqual(@as(usize, 0), m.pterm.count());
    try std.testing.expectError(error.Badarg, get_1(&m, &.{k2}));
    // Idempotent on an already-empty store.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try erase_persistent_terms_0(&m, &.{}), FinalTerms.atom(&m.ctx, m.bool_true)));
}

test "LAW E2.10 persistent_term: put_new/2 stores-if-absent, no-ops on the SAME value, badargs on a DIFFERENT one" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const key = FinalTerms.atom(&m.ctx, try atoms.intern("k"));
    const v1 = FinalTerms.int(&m.ctx, 1);
    const v2 = FinalTerms.int(&m.ctx, 2);

    // absent key -> stores.
    const ok_atom = FinalTerms.atom(&m.ctx, try atoms.intern("ok"));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try put_new_2(&m, &.{ key, v1 }), ok_atom));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try get_1(&m, &.{key}), v1));

    // same value again -> quick no-op, still ok, value unchanged.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try put_new_2(&m, &.{ key, v1 }), ok_atom));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try get_1(&m, &.{key}), v1));

    // different value -> badarg, stored value untouched.
    try std.testing.expectError(error.Badarg, put_new_2(&m, &.{ key, v2 }));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try get_1(&m, &.{key}), v1));
}
