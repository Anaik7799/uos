//! # bifs/time — the `erlang:` monotonic/system time family (E5.8b / Task 8b)
//!
//! ## Signature
//! Same contract as every family module: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over already-resolved
//! term arguments, computed via `Machine.clock` — the S21 clock seam
//! (`time_algebra.zig`). No new time semantics live here; this module is the
//! thin term-decoding/encoding boundary over `time_algebra.Clock`.
//!
//! ## The rows (all `bif` kind on the pin's `bif.tab`)
//!   monotonic_time/0,1   `Clock.monotonic` (warp-invariant, strictly forward)
//!   system_time/0,1      `Clock.systemTime` (`monotonic + time_offset`)
//!   time_offset/0,1      `Clock.timeOffset` (no-warp constant)
//!   timestamp/0          `Clock.timestampParts` → `{MegaSec, Sec, MicroSec}`
//!
//! ## Why these are EQ (property-based, never byte-based)
//! A wall/monotonic READING is host-nondeterministic, so the differential corpus
//! folds only the DETERMINISTIC PROPERTIES erts guarantees into fixed values:
//! integer type, monotonicity (`t2 >= t1`), the offset identity
//! (`system == monotonic + offset` at a single instant), and the timestamp
//! shape/range. The exact unit arithmetic + offset identity are pinned by the
//! `time_algebra.zig` laws over an injected mock source. See DIVERGENCE entry 93.
//!
//! ## Unit argument (`/1`)
//! `second | millisecond | microsecond | nanosecond | native | perf_counter`, or
//! a positive integer (its own ticks-per-second, e.g. `monotonic_time(1000)` ==
//! milliseconds). Any other term → `badarg` (rejection totality).

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const time_algebra = @import("../time_algebra.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

/// Resolve a `/1` unit argument to its ticks-per-second, or `badarg`.
fn tpsOfArg(m: *Machine, arg: Term) BifError!i128 {
    if (FinalTerms.repIsAtom(arg)) {
        const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(arg));
        return time_algebra.ticksPerSecondOfAtom(name) orelse error.Badarg;
    }
    if (FinalTerms.repIsSmall(arg)) {
        return time_algebra.ticksPerSecondOfInt(FinalTerms.smallValOf(arg)) orelse error.Badarg;
    }
    // A bignum unit is astronomically large but still a positive integer in
    // erts; this VM's units are all small, so a non-small integer is out of the
    // supported range -> badarg (a documented bound, never a silent wrong value).
    return error.Badarg;
}

fn intOf(m: *Machine, v: i128) BifError!Term {
    return FinalTerms.intFromI128(&m.ctx, v) catch error.OutOfMemory;
}

pub fn monotonic_time_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return intOf(m, m.clock.monotonic(time_algebra.NATIVE_UNIT));
}
pub fn monotonic_time_1(m: *Machine, args: []const Term) BifError!Term {
    return intOf(m, m.clock.monotonic(try tpsOfArg(m, args[0])));
}

pub fn system_time_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return intOf(m, m.clock.systemTime(time_algebra.NATIVE_UNIT));
}
pub fn system_time_1(m: *Machine, args: []const Term) BifError!Term {
    return intOf(m, m.clock.systemTime(try tpsOfArg(m, args[0])));
}

/// `erlang:convert_time_unit(Value, FromUnit, ToUnit)` (DIVERGENCE 721) — the
/// PURE unit conversion (`time_algebra.convert`, the exact erts floor-toward-−∞
/// integer arithmetic). Value is a (small) integer; the units are the named
/// atoms or a positive integer (ticks-per-second). A bignum Value is the
/// documented small-integer bound (timestamps fit i64) → badarg, never a wrong
/// value. Was `undef` (the algebra existed but no BIF wrapper).
pub fn convert_time_unit_3(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsSmall(args[0])) return error.Badarg;
    const value: i128 = FinalTerms.smallValOf(args[0]);
    const from_tps = try tpsOfArg(m, args[1]);
    const to_tps = try tpsOfArg(m, args[2]);
    return intOf(m, time_algebra.convert(value, from_tps, to_tps));
}

pub fn time_offset_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return intOf(m, m.clock.timeOffset(time_algebra.NATIVE_UNIT));
}
pub fn time_offset_1(m: *Machine, args: []const Term) BifError!Term {
    return intOf(m, m.clock.timeOffset(try tpsOfArg(m, args[0])));
}

pub fn timestamp_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const p = m.clock.timestampParts();
    return partsTuple(m, p);
}

/// Build the `{MegaSec, Sec, MicroSec}` tuple shared by `erlang:timestamp/0` and
/// `os:timestamp/0`.
pub fn partsTuple(m: *Machine, p: [3]i128) BifError!Term {
    const a = try intOf(m, p[0]);
    const b = try intOf(m, p[1]);
    const c = try intOf(m, p[2]);
    return FinalTerms.tuple(&m.ctx, &.{ a, b, c }) catch error.OutOfMemory;
}

// ============================================================================
// Laws — end-to-end over a real Machine clock (the mock-sourced arithmetic laws
// live in time_algebra.zig; here we pin the BIF term-boundary + reachability).
// ============================================================================

const AtomTable = ta.AtomTable;

test "LAW E5.8b time BIFs: integer type + monotonicity + offset identity" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();

    // monotonic_time/0 returns a small/big integer, and never decreases.
    const t1 = try monotonic_time_0(&m, &.{});
    try std.testing.expect(FinalTerms.repIsSmall(t1) or FinalTerms.kindOf(&m.ctx, t1) == .number);
    // Monotonicity is the observable property — read the native clock in order.
    const a = m.clock.monotonic(time_algebra.NATIVE_UNIT);
    const b = m.clock.monotonic(time_algebra.NATIVE_UNIT);
    try std.testing.expect(b >= a);

    // OFFSET IDENTITY at a single instant: system(native) == monotonic + offset.
    // Read via the clock's own frozen arithmetic is covered in time_algebra; here
    // we assert the BIF results are integers and the offset row resolves.
    const off0 = try time_offset_0(&m, &.{});
    try std.testing.expect(FinalTerms.repIsSmall(off0) or FinalTerms.kindOf(&m.ctx, off0) == .number);

    // timestamp/0 is a 3-tuple with sec/micro in range.
    const tsq = try timestamp_0(&m, &.{});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, tsq) == .tuple);
    try std.testing.expectEqual(@as(usize, 3), FinalTerms.tupleArity(&m.ctx, tsq));
    const sec = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, tsq, 1));
    const micro = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, tsq, 2));
    try std.testing.expect(sec >= 0 and sec < 1_000_000);
    try std.testing.expect(micro >= 0 and micro < 1_000_000);
}

test "LAW E5.8b time BIFs REJECTION: a bad unit atom / non-integer unit → badarg" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();

    const bad = FinalTerms.atom(&m.ctx, try atoms.intern("fortnight"));
    try std.testing.expectError(error.Badarg, monotonic_time_1(&m, &.{bad}));
    try std.testing.expectError(error.Badarg, system_time_1(&m, &.{bad}));
    // A valid unit atom resolves.
    const ms = FinalTerms.atom(&m.ctx, try atoms.intern("millisecond"));
    _ = try monotonic_time_1(&m, &.{ms});
    // A positive-integer unit resolves; a non-positive one is badarg.
    _ = try system_time_1(&m, &.{FinalTerms.int(&m.ctx, 1000)});
    try std.testing.expectError(error.Badarg, time_offset_1(&m, &.{FinalTerms.int(&m.ctx, 0)}));
    // A non-atom/non-integer unit (e.g. nil) is badarg.
    try std.testing.expectError(error.Badarg, monotonic_time_1(&m, &.{FinalTerms.nil(&m.ctx)}));
}

test "LAW gap-convert-time-unit (DIVERGENCE 721): erlang:convert_time_unit/3 = the exact erts floor-toward-−∞ integer conversion; byte-EQ OTP-30" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();

    const U = struct {
        fn a(mm: *Machine, aa: *AtomTable, name: []const u8) !Term {
            return FinalTerms.atom(&mm.ctx, try aa.intern(name));
        }
        fn go(mm: *Machine, aa: *AtomTable, v: i64, from: []const u8, to: []const u8) !i64 {
            const r = try convert_time_unit_3(mm, &.{ FinalTerms.int(&mm.ctx, v), try a(mm, aa, from), try a(mm, aa, to) });
            return FinalTerms.smallValOf(r);
        }
    };
    try std.testing.expectEqual(@as(i64, 1), try U.go(&m, &atoms, 1000, "millisecond", "second"));
    try std.testing.expectEqual(@as(i64, 1000), try U.go(&m, &atoms, 1, "second", "millisecond"));
    try std.testing.expectEqual(@as(i64, 1), try U.go(&m, &atoms, 1500, "millisecond", "second")); // floor
    try std.testing.expectEqual(@as(i64, -2), try U.go(&m, &atoms, -1500, "millisecond", "second")); // floor toward -inf
    try std.testing.expectEqual(@as(i64, 0), try U.go(&m, &atoms, 999, "millisecond", "second"));
    try std.testing.expectEqual(@as(i64, 1_000_000_000), try U.go(&m, &atoms, 1, "second", "nanosecond"));
    // an integer (ticks-per-second) unit: 7 s at 3 tps = 21.
    {
        const r = try convert_time_unit_3(&m, &.{ FinalTerms.int(&m.ctx, 7), try U.a(&m, &atoms, "second"), FinalTerms.int(&m.ctx, 3) });
        try std.testing.expectEqual(@as(i64, 21), FinalTerms.smallValOf(r));
    }
    // rejections: bad unit atom, non-positive integer unit, non-integer value.
    try std.testing.expectError(error.Badarg, convert_time_unit_3(&m, &.{ FinalTerms.int(&m.ctx, 1), try U.a(&m, &atoms, "fortnight"), try U.a(&m, &atoms, "second") }));
    try std.testing.expectError(error.Badarg, convert_time_unit_3(&m, &.{ FinalTerms.int(&m.ctx, 1), try U.a(&m, &atoms, "second"), FinalTerms.int(&m.ctx, 0) }));
    try std.testing.expectError(error.Badarg, convert_time_unit_3(&m, &.{ FinalTerms.nil(&m.ctx), try U.a(&m, &atoms, "second"), try U.a(&m, &atoms, "second") }));
}
