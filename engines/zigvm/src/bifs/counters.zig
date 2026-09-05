//! # bifs/counters — the `erts_internal:counters_*` BIF family (E36-T1)
//!
//! ## Signature
//! Same contract as the other family modules: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over
//! ALREADY-RESOLVED term arguments. These are the FIVE primitives underneath
//! the `counters` module's `write_concurrency` variant (`counters.erl`'s
//! `new(Size,[write_concurrency])` → `erts_internal:counters_new/1`, then
//! `get/2`/`add/3`/`put/3`/`info/1`; the `atomics` variant already routes
//! through `bifs/atomics.zig`). `counters:sub/3` is a pure Erlang wrapper
//! (`add(Ref,Ix,-Decr)`) and is NOT a primitive — the `atomics:sub` precedent.
//!
//! ## WHERE STATE LIVES — reuse the atomics registry (the exact sequential shadow)
//! A `counters` array is, underneath, a signed 64-bit atomic integer array —
//! the SAME algebra as `atomics` (`atomics_algebra.AtomicsArray`, always
//! `signed=true` for counters). zigvm is single-threaded (the E6 scope note),
//! so the `write_concurrency` variant — which in real erts shards writes across
//! per-scheduler sub-counters and SUMS them on `get` — collapses to the exact
//! ONE-array sequential contract: with a single scheduler there is one shard, so
//! the sum IS the value. Reusing `Machine.atomics` (rather than a parallel
//! `Machine.counters` registry) is therefore not a shortcut but the correct
//! denotation for the pin's single-thread model — no new VM state, and the array
//! laws (`atomics_algebra.zig`) already bound it. Ids are shared with atomics
//! (both draw dense, never-reused ids from the one registry); a well-formed
//! program never crosses a counters ref into an atomics op (the `counters`/
//! `atomics` module tags keep them apart at the Erlang level).
//!
//! ## Ref REPRESENTATION (the atomics/ets Tid twin)
//! A real erts counters ref is an opaque `reference()`; here it is the array's
//! dense registry id boxed as a small-integer TERM — the identical simplification
//! `bifs/atomics.zig`/`bifs/ets.zig` document. The differential `counters_SUITE`
//! treats the ref OPAQUELY (asserts counter VALUES, never the ref shape), so the
//! small-int-vs-real-ref residue is unobservable (each VM makes + consumes its
//! OWN native ref).
//!
//! ## The `counters` vs `atomics` info CONTRACT (verified against counters.erl)
//! `counters:info/1` reports `#{size => S, memory => M}` — only TWO keys (NO
//! `max`/`min`, unlike `atomics:info/1`). Counters are always signed, so the
//! range is implicit. `add/3` and `put/3` return the atom `ok` (they discard).
//!
//! ## Arg-type scope (SMALL-INTEGER only — the atomics precedent)
//! `Ix`/`Value`/`Incr` must be small-integer terms (`repIsSmall`, ~60-bit here);
//! a value this term system represents as a BIGNUM is a documented clean `badarg`,
//! the SAME bound `bifs/atomics.zig` and the bitwise family already carry.
//!
//! ## Laws (the suite below — reuses `atomics_algebra.zig`'s array laws, adds the
//! counters BIF surface: 1-based Ix, add-then-get accumulation, the info key set,
//! sub-via-negative-add, rejection)
//!   - ROUND-TRIP    `get(new(N),Ix)==0` initially; `put` then `get` round-trips.
//!   - ACCUMULATE    `add` accumulates; a NEGATIVE incr subtracts (the sub path).
//!   - INFO-KEYS      `info/1` == `#{size, memory}` — exactly two keys.
//!   - REJECTION      `Ix` out of `[1,Size]`, a non-small arg, or a bad `Ref` →
//!                    `badarg`, never a panic.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const aa = @import("../atomics_algebra.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;
const AtomicsArray = aa.AtomicsArray;

fn internAtom(m: *Machine, name: []const u8) BifError!Term {
    const idx = m.ctx.atoms.intern(name) catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

/// A `Ref` arg (a small-int registry id — shared with the atomics registry).
fn resolveRef(m: *Machine, ref: Term) BifError!*AtomicsArray {
    if (!FinalTerms.repIsSmall(ref)) return error.Badarg;
    const v = FinalTerms.smallValOf(ref);
    if (v < 0) return error.Badarg;
    return m.atomics.byId(@intCast(v)) orelse error.Badarg;
}

/// A 1-based `Ix` arg → the algebra's 0-based index (bounds checked by the array).
fn ix0Of(ix_term: Term) BifError!usize {
    if (!FinalTerms.repIsSmall(ix_term)) return error.Badarg;
    const v = FinalTerms.smallValOf(ix_term);
    if (v < 1) return error.Badarg;
    return @intCast(v - 1);
}

fn smallI128(t: Term) BifError!i128 {
    if (!FinalTerms.repIsSmall(t)) return error.Badarg;
    return @as(i128, FinalTerms.smallValOf(t));
}

fn cellTerm(m: *Machine, v: i128) BifError!Term {
    return FinalTerms.intFromI128(&m.ctx, v) catch error.OutOfMemory;
}

// ── erts_internal:counters_new/1 (the write_concurrency primitive) ──────────

pub fn counters_new_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsSmall(args[0])) return error.Badarg;
    const size_i = FinalTerms.smallValOf(args[0]);
    if (size_i < 1) return error.Badarg;
    const size: usize = @intCast(size_i);
    // counters are ALWAYS signed 64-bit (counters.erl has no {signed,_} opt).
    const id = m.atomics.create(size, true) catch return error.OutOfMemory;
    return FinalTerms.int(&m.ctx, @intCast(id));
}

// ── erts_internal:counters_get/2 ────────────────────────────────────────────

pub fn counters_get_2(m: *Machine, args: []const Term) BifError!Term {
    const c = try resolveRef(m, args[0]);
    const ix0 = try ix0Of(args[1]);
    const v = c.get(ix0) catch return error.Badarg;
    return cellTerm(m, v);
}

// ── erts_internal:counters_add/3 (-> ok; discards) ──────────────────────────

pub fn counters_add_3(m: *Machine, args: []const Term) BifError!Term {
    const c = try resolveRef(m, args[0]);
    const ix0 = try ix0Of(args[1]);
    const incr = try smallI128(args[2]);
    _ = c.add(ix0, incr) catch return error.Badarg;
    return internAtom(m, "ok");
}

// ── erts_internal:counters_put/3 (-> ok) ────────────────────────────────────

pub fn counters_put_3(m: *Machine, args: []const Term) BifError!Term {
    const c = try resolveRef(m, args[0]);
    const ix0 = try ix0Of(args[1]);
    const v = try smallI128(args[2]);
    c.put(ix0, v) catch return error.Badarg;
    return internAtom(m, "ok");
}

// ── erts_internal:counters_info/1 (-> #{size, memory}) ──────────────────────

pub fn counters_info_1(m: *Machine, args: []const Term) BifError!Term {
    const c = try resolveRef(m, args[0]);
    // counters:info/1 reports EXACTLY size + memory (no max/min — the counters
    // contract, distinct from atomics:info/1).
    const keys = [_][]const u8{ "size", "memory" };
    const vals = [_]Term{
        FinalTerms.int(&m.ctx, @intCast(c.len())),
        // Approximate (the atomics:info/persistent_term:info precedent): 8 bytes/
        // counter plus a small fixed overhead.
        FinalTerms.int(&m.ctx, @intCast(c.len() * 8 + 64)),
    };
    var kts: [2]Term = undefined;
    for (keys, 0..) |k, i| kts[i] = try internAtom(m, k);
    return FinalTerms.mapNew(&m.ctx, &kts, &vals) catch error.OutOfMemory;
}

// ============================================================================
// Laws
// ============================================================================

const AtomTable = ta.AtomTable;

fn newCounters(m: *Machine, size: i64) BifError!Term {
    return counters_new_1(m, &.{FinalTerms.int(&m.ctx, size)});
}

test "LAW E36-T1 counters: new zeroes; put/get round-trip; 1-based Ix; bad Ix/Ref -> badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const ref = try newCounters(&m, 3);
    // fresh counters read 0.
    try std.testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(try counters_get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 1) })));
    _ = try counters_put_3(&m, &.{ ref, FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 42) });
    try std.testing.expectEqual(@as(i64, 42), FinalTerms.smallValOf(try counters_get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 2) })));

    // 1-based: index 0 and index 4 are out of range on a size-3 array.
    try std.testing.expectError(error.Badarg, counters_get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 0) }));
    try std.testing.expectError(error.Badarg, counters_get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 4) }));
    // bad ref.
    try std.testing.expectError(error.Badarg, counters_get_2(&m, &.{ FinalTerms.int(&m.ctx, 9999), FinalTerms.int(&m.ctx, 1) }));
    // non-small arg.
    try std.testing.expectError(error.Badarg, counters_add_3(&m, &.{ ref, FinalTerms.int(&m.ctx, 1), FinalTerms.atom(&m.ctx, try atoms.intern("x")) }));
}

test "LAW E36-T1 counters: add accumulates and returns ok; a NEGATIVE incr subtracts (the sub/3 path)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const ref = try newCounters(&m, 1);

    const ok = try counters_add_3(&m, &.{ ref, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 10) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ok, FinalTerms.atom(&m.ctx, try atoms.intern("ok"))));
    _ = try counters_add_3(&m, &.{ ref, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 7) });
    try std.testing.expectEqual(@as(i64, 17), FinalTerms.smallValOf(try counters_get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 1) })));
    // sub(Ref,Ix,5) == add(Ref,Ix,-5): 17 - 5 = 12.
    _ = try counters_add_3(&m, &.{ ref, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, -5) });
    try std.testing.expectEqual(@as(i64, 12), FinalTerms.smallValOf(try counters_get_2(&m, &.{ ref, FinalTerms.int(&m.ctx, 1) })));
}

test "LAW E36-T1 counters: info/1 reports EXACTLY size + memory (no max/min — distinct from atomics:info)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const ref = try newCounters(&m, 5);
    const info = try counters_info_1(&m, &.{ref});

    const size_k = FinalTerms.atom(&m.ctx, try atoms.intern("size"));
    const mem_k = FinalTerms.atom(&m.ctx, try atoms.intern("memory"));
    const max_k = FinalTerms.atom(&m.ctx, try atoms.intern("max"));
    try std.testing.expectEqual(@as(i64, 5), FinalTerms.smallValOf(FinalTerms.mapGet(&m.ctx, info, size_k).?));
    try std.testing.expect(FinalTerms.mapGet(&m.ctx, info, mem_k) != null);
    // the counters info map has NO `max` key (mutant target: adding atomics keys).
    try std.testing.expect(FinalTerms.mapGet(&m.ctx, info, max_k) == null);
}
