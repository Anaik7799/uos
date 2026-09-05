//! beam-zig E2.10 / S28: **atomics** — a fixed-arity array of 64-bit integer
//! cells with sequential (single-Machine) atomic-contract operations (cf.
//! `erl_bif_atomics.c`, `erts/preloaded/src/atomics.erl`).
//!
//! ## Carrier
//! `AtomicsArray{ signed: bool, cells: []u64 }` — a gpa-owned slice of RAW
//! 64-bit words (the two's-complement bit pattern), plus a `signed` flag that
//! is purely a VIEW on those bits (never a representation change): reading a
//! cell reinterprets its 64 bits as `i64` (signed) or as `u64` (unsigned);
//! writing a cell truncates the caller's `i128` value to its low 64 bits
//! (two's-complement wraparound — `atomics` documents "Atomics wrap around at
//! overflow and underflow operations"). `AtomicsRegistry{ arrays: []?AtomicsArray }`
//! is the Machine-owned `Ref → array` table (`bifs/atomics.zig`'s Ref is a
//! small-int id into it — the exact `ets:Tid`-as-small-int simplification
//! `bifs/ets.zig` already documents; real BEAM atomics refs are `reference()`s).
//!
//! ## Denotation
//! `denote(arr)[i] = signed ? asI64(cells[i]) : asU64(cells[i])` — one 64-bit
//! two's-complement value per cell, 1-based in the public BIF surface
//! (`bifs/atomics.zig` converts to the 0-based `ix0` this module uses).
//!
//! ## Operations (all total over an in-range `ix0`; out-of-range → `error.Badarg`)
//!   `get(ix0)          : Cell`
//!   `put(ix0, v)       : ()`            — `cells[ix0] := bits(v)`
//!   `add(ix0, incr)    : Cell`          — `cells[ix0] := cells[ix0] +% bits(incr)`, returns the NEW value
//!   `exchange(ix0, d)  : Cell`          — `cells[ix0] := bits(d)`, returns the OLD value
//!   `compareExchange(ix0, expected, desired) : ?Cell` — if `get(ix0)==expected`,
//!     sets `desired` and returns `null` (swap happened); else returns the
//!     ACTUAL current value (swap did not happen) — the BEAM `ok | integer()`
//!     contract, translated to Zig's optional (caller maps `null`→`ok` atom).
//!
//! ## Laws
//!   MONOID (add is `+%` over `Z/2^64Z`): `add(add(v,a),b) == add(v,a+%b)`
//!     (associativity) and `add(v,a) == add(v',a)` whenever `v==v'` regardless
//!     of prior op history (well-definedness) — checked as a twin-walk below
//!     against an oracle that computes everything in `i128` then reduces mod
//!     `2^64` ONCE at the end (never wrapping mid-computation), proving the
//!     per-op wraparound and the single-reduction oracle agree.
//!   WRAPAROUND  `maxInt(i64) + 1` wraps to `minInt(i64)` (signed view);
//!     `maxInt(u64) + 1` wraps to `0` (unsigned view) — the documented
//!     over/underflow contract, exact per cell, no silent saturation.
//!   EXCHANGE  `exchange(ix0,d)` returns the value `get(ix0)` would have
//!     returned just before the call, and `get(ix0)` after equals `d`.
//!   COMPARE-EXCHANGE  swap iff `get(ix0)==expected`; a failed CAS is a
//!     PURE READ (never mutates the cell) — mutant target.
//!   REJECTION  `ix0 >= cells.len` → `error.Badarg` on every op, never a panic
//!     (no other op mutates on a rejected call).
//!   LEAK-FREE  `AtomicsRegistry.deinit` frees every live array's `cells`
//!     slice then the registry's own list — `std.testing.allocator` proves it.
//!
//! ## Scope (E6 note — the crux)
//! zigvm has no SMP scheduler yet (single-Machine, single-thread execution),
//! so these ops are SEQUENTIALLY consistent by construction (there is no
//! concurrent writer to race) — the real hardware-atomic / cross-thread-
//! ordering guarantee `atomics.erl`'s moduledoc describes ("implementation
//! utilizes only atomic hardware instructions… mutually ordered") is a
//! DEFERRED, documented gap: this module gives the correct SEQUENTIAL
//! shadow of every op's single-threaded contract, not concurrent atomicity.
//! Re-backing this with `std.atomic.Value(u64)` cells is the E6 SMP-epoch
//! follow-up; the op CONTRACTS (wraparound, add/exchange/CAS semantics)
//! do not change, only the memory model gains real cross-thread ordering.

const std = @import("std");

pub const AtomicsError = error{ Badarg, OutOfMemory };

pub const AtomicsArray = struct {
    gpa: std.mem.Allocator,
    signed: bool,
    cells: []u64,

    pub fn init(gpa: std.mem.Allocator, arity: usize, signed: bool) !AtomicsArray {
        const cells = try gpa.alloc(u64, arity);
        @memset(cells, 0);
        return .{ .gpa = gpa, .signed = signed, .cells = cells };
    }
    pub fn deinit(self: *AtomicsArray) void {
        self.gpa.free(self.cells);
    }
    pub fn len(self: *const AtomicsArray) usize {
        return self.cells.len;
    }

    /// The signed/unsigned VIEW of a raw 64-bit cell (never a repr change).
    fn view(self: *const AtomicsArray, bits: u64) i128 {
        return if (self.signed) @as(i128, @as(i64, @bitCast(bits))) else @as(i128, bits);
    }
    /// Truncate an i128 value to its low 64 bits — the documented
    /// two's-complement WRAPAROUND (mutant target: dropping the truncation
    /// and instead saturating would silently break the monoid law).
    fn bitsOf(v: i128) u64 {
        return @truncate(@as(u128, @bitCast(v)));
    }

    pub fn get(self: *const AtomicsArray, ix0: usize) error{Badarg}!i128 {
        if (ix0 >= self.cells.len) return error.Badarg;
        return self.view(self.cells[ix0]);
    }
    pub fn put(self: *AtomicsArray, ix0: usize, v: i128) error{Badarg}!void {
        if (ix0 >= self.cells.len) return error.Badarg;
        self.cells[ix0] = bitsOf(v);
    }
    /// Returns the NEW value (the BEAM `add_get/3` contract — `add/3` itself
    /// discards it and returns `ok`, done by the BIF wrapper, not here).
    pub fn add(self: *AtomicsArray, ix0: usize, incr: i128) error{Badarg}!i128 {
        if (ix0 >= self.cells.len) return error.Badarg;
        const nb = self.cells[ix0] +% bitsOf(incr);
        self.cells[ix0] = nb;
        return self.view(nb);
    }
    /// Returns the OLD value.
    pub fn exchange(self: *AtomicsArray, ix0: usize, desired: i128) error{Badarg}!i128 {
        if (ix0 >= self.cells.len) return error.Badarg;
        const old = self.view(self.cells[ix0]);
        self.cells[ix0] = bitsOf(desired);
        return old;
    }
    /// `null` == swap happened (matches `expected`); else the ACTUAL value
    /// (swap did NOT happen — a failed CAS never mutates the cell).
    pub fn compareExchange(self: *AtomicsArray, ix0: usize, expected: i128, desired: i128) error{Badarg}!?i128 {
        if (ix0 >= self.cells.len) return error.Badarg;
        const cur = self.view(self.cells[ix0]);
        if (cur != expected) return cur;
        self.cells[ix0] = bitsOf(desired);
        return null;
    }
    pub fn maxVal(self: *const AtomicsArray) i128 {
        return if (self.signed) @as(i128, std.math.maxInt(i64)) else @as(i128, std.math.maxInt(u64));
    }
    pub fn minVal(self: *const AtomicsArray) i128 {
        return if (self.signed) @as(i128, std.math.minInt(i64)) else 0;
    }
};

/// Machine-owned `Ref → array` table, the `bifs/ets.zig` `EtsRegistry` shape:
/// dense ids, never reused, a `delete`-free array (BEAM never frees an
/// atomics ref explicitly — it is GC'd when unreferenced; here it simply
/// lives for the Machine's lifetime, freed in `deinit`).
pub const AtomicsRegistry = struct {
    gpa: std.mem.Allocator,
    arrays: std.ArrayList(?AtomicsArray),

    pub fn init(gpa: std.mem.Allocator) AtomicsRegistry {
        return .{ .gpa = gpa, .arrays = .empty };
    }
    pub fn deinit(self: *AtomicsRegistry) void {
        for (self.arrays.items) |*slot| {
            if (slot.*) |*a| a.deinit();
        }
        self.arrays.deinit(self.gpa);
    }
    pub fn create(self: *AtomicsRegistry, arity: usize, signed: bool) !usize {
        const a = try AtomicsArray.init(self.gpa, arity, signed);
        try self.arrays.append(self.gpa, a);
        return self.arrays.items.len - 1;
    }
    pub fn byId(self: *AtomicsRegistry, id: usize) ?*AtomicsArray {
        if (id >= self.arrays.items.len) return null;
        if (self.arrays.items[id]) |*a| return a;
        return null;
    }
};

// ============================================================================
// Laws
// ============================================================================

test "LAW E2.10 get/put round-trip; WRAPAROUND at the signed/unsigned boundary" {
    const gpa = std.testing.allocator;
    var arr = try AtomicsArray.init(gpa, 3, true);
    defer arr.deinit();

    try arr.put(0, 42);
    try std.testing.expectEqual(@as(i128, 42), try arr.get(0));

    // signed WRAPAROUND: maxInt(i64) + 1 -> minInt(i64).
    try arr.put(1, std.math.maxInt(i64));
    _ = try arr.add(1, 1);
    try std.testing.expectEqual(@as(i128, std.math.minInt(i64)), try arr.get(1));

    // unsigned view of the SAME bit pattern reads the raw u64.
    var uarr = try AtomicsArray.init(gpa, 1, false);
    defer uarr.deinit();
    try uarr.put(0, -1); // bit pattern 0xFFFF_FFFF_FFFF_FFFF
    try std.testing.expectEqual(@as(i128, std.math.maxInt(u64)), try uarr.get(0));
    _ = try uarr.add(0, 1); // maxInt(u64)+1 -> 0
    try std.testing.expectEqual(@as(i128, 0), try uarr.get(0));

    // REJECTION: out-of-range index never panics.
    try std.testing.expectError(error.Badarg, arr.get(3));
    try std.testing.expectError(error.Badarg, arr.put(99, 1));
}

test "LAW E2.10 exchange returns the OLD value; a failed compareExchange is a pure read" {
    const gpa = std.testing.allocator;
    var arr = try AtomicsArray.init(gpa, 1, true);
    defer arr.deinit();

    try arr.put(0, 10);
    try std.testing.expectEqual(@as(i128, 10), try arr.exchange(0, 20));
    try std.testing.expectEqual(@as(i128, 20), try arr.get(0));

    // Matching CAS swaps and reports success (null).
    try std.testing.expectEqual(@as(?i128, null), try arr.compareExchange(0, 20, 30));
    try std.testing.expectEqual(@as(i128, 30), try arr.get(0));

    // Mismatched CAS reports the ACTUAL value and does NOT mutate.
    try std.testing.expectEqual(@as(?i128, 30), try arr.compareExchange(0, 999, 40));
    try std.testing.expectEqual(@as(i128, 30), try arr.get(0)); // unchanged
}

test "LAW E2.10 add is a commutative monoid over Z/2^64Z (twin-walk vs an i128-then-reduce oracle)" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xA70A_1C5);
    const random = prng.random();

    for (0..40) |seed_i| {
        var seeded = std.Random.DefaultPrng.init(0xA70A_1C5 +% seed_i);
        const r2 = seeded.random();
        var arr = try AtomicsArray.init(gpa, 1, false); // unsigned: full u64 range
        defer arr.deinit();
        var oracle: i128 = 0; // accumulate in i128, reduce mod 2^64 only at the end

        for (0..60) |_| {
            const incr: i128 = r2.int(i64); // any i64-range increment
            const new_val = try arr.add(0, incr);
            oracle += incr;
            const masked: u128 = @as(u128, @bitCast(oracle)) & 0xFFFF_FFFF_FFFF_FFFF; // mod 2^64
            const reduced: i128 = @intCast(masked);
            try std.testing.expectEqual(reduced, new_val);
            try std.testing.expectEqual(reduced, try arr.get(0));
        }
        _ = random;
    }
}

test "LAW E2.10 AtomicsRegistry: create/byId round-trip, absent id -> null, zero-leak" {
    const gpa = std.testing.allocator;
    var reg = AtomicsRegistry.init(gpa);
    defer reg.deinit();

    const r0 = try reg.create(4, true);
    const r1 = try reg.create(2, false);
    try std.testing.expect(reg.byId(r0) != null);
    try std.testing.expectEqual(@as(usize, 4), reg.byId(r0).?.len());
    try std.testing.expectEqual(@as(usize, 2), reg.byId(r1).?.len());
    try std.testing.expectEqual(@as(?*AtomicsArray, null), reg.byId(999));

    try reg.byId(r0).?.put(0, 123);
    try std.testing.expectEqual(@as(i128, 123), try reg.byId(r0).?.get(0));
    // r1 is untouched by an op on r0 (distinct arrays).
    try std.testing.expectEqual(@as(i128, 0), try reg.byId(r1).?.get(0));
}
