//! # beam-zig S21 — the OS **clock** algebra + the OS **environment** seam
//! (E5.8/Task 8b; cf. erts `erl_time_sup.c`, `sys_time.c`, `erl_bif_os.c`).
//!
//! ## Signature (the clock)
//!   monotonic : (Clock, Unit)  -> Int        (observation, warp-invariant)
//!   systemTime: (Clock, Unit)  -> Int         (observation)
//!   timeOffset: (Clock, Unit)  -> Int         (observation)
//!   warp      : (Clock, Δ)     -> Clock        (combinator — a time-warp step)
//!   convert   : (Int, tps, tps)-> Int          (pure unit-conversion lattice)
//!
//! ## Semantic domain
//! A clock is a pair `(mono, offset)` in *native* ticks, where the OS supplies
//! the strictly-forward `mono` source and `offset` is the (no-time-warp) constant
//! such that **system time == monotonic time + time offset** at every instant.
//! `warp` models a `multi_time_warp` adjustment: it moves `offset` (so system
//! time may jump either way) but NEVER touches `mono` — hence *monotonic time is
//! invariant under warp*, the S21 "monotone under warp" law. The unit lattice is
//! the exact erts integer arithmetic of `erlang:convert_time_unit/3` (a floor
//! division toward −∞, replicated by homomorphism, never by intuition).
//!
//! zigvm's native resolution is the **nanosecond** (`NATIVE_UNIT = 1e9`), so
//! `native` and `nanosecond` coincide — the shape of a modern nanosecond-native
//! erts. The *value* of the native unit is never observed across the VM boundary
//! (only within-VM properties: type, monotonicity, offset-identity, exact ratios)
//! so this choice cannot leak into a differential result — see `bifs/os.zig` and
//! the time BIFs in `bifs/time.zig`.
//!
//! ## Laws (the tests below, over an INJECTED mock source)
//!   IDENTITY           convert(v, u, u) == v
//!   EXACT-RATIO        convert(v, second, milli) == v*1000, …, micro, nano
//!                      (the pure decimal units are exact multiples — homomorphism)
//!   FLOOR              convert(v, milli, second) == ⌊v/1000⌋ for ALL v incl. <0
//!                      (the erts negative-value adjustment — Mutant m1 target)
//!   MONOTONE-CONV      v1<=v2 ⟹ convert(v1,·)<=convert(v2,·)
//!   MONOTONE-UNDER-WARP  monotonic(t) is nondecreasing along a forward source
//!                      AND invariant under any warp sequence (Mutant m2 target)
//!   OFFSET-IDENTITY    systemTime(native) == monotonic(native) + timeOffset(native)
//!                      at a single read, and after any warp
//!   TIMESTAMP-RT       {mega,sec,micro} reassembles systemTime(microsecond),
//!                      with 0<=sec<1e6, 0<=micro<1e6
//!   REJECTION          an unknown unit atom / non-positive integer unit → null
//!
//! ## Scope / strata
//! The `Unit`/`convert`/`Clock` core is **Stratum A** (pure, law-governed, mock-
//! sourced). `RealSource` (the linux `clock_gettime` reads) and `EnvTable`'s
//! `/proc/self/environ` seed are **Stratum C** (OS glue, Linux-only, quarantined
//! behind the `Source`/`EnvTable` seams — no Stratum-A law depends on them). This
//! mirrors `os_port.zig`'s raw-syscall precedent.

const std = @import("std");
const linux = std.os.linux;

// ── the unit lattice ─────────────────────────────────────────────────────────

/// zigvm's native tick resolution: nanoseconds. (So `native` ≡ `nanosecond`.)
pub const NATIVE_UNIT: i128 = 1_000_000_000;
/// The perf-counter tick resolution zigvm advertises (also nanosecond-native).
pub const PERF_COUNTER_UNIT: i128 = 1_000_000_000;

/// The named time units erts accepts (`erlang:convert_time_unit/3` atoms).
pub const Unit = enum { second, millisecond, microsecond, nanosecond, native, perf_counter };

/// Ticks-per-second for a named unit (erts `integer_time_unit`).
pub fn integerTimeUnit(u: Unit) i128 {
    return switch (u) {
        .second => 1,
        .millisecond => 1_000,
        .microsecond => 1_000_000,
        .nanosecond => 1_000_000_000,
        .native => NATIVE_UNIT,
        .perf_counter => PERF_COUNTER_UNIT,
    };
}

/// Resolve a unit atom NAME to its ticks-per-second, or `null` for an unknown
/// atom (the caller maps that to `badarg`). A positive-integer unit is handled
/// separately at the BIF boundary (`ticksPerSecondOfInt`).
pub fn ticksPerSecondOfAtom(name: []const u8) ?i128 {
    if (std.mem.eql(u8, name, "second")) return 1;
    if (std.mem.eql(u8, name, "millisecond")) return 1_000;
    if (std.mem.eql(u8, name, "microsecond")) return 1_000_000;
    if (std.mem.eql(u8, name, "nanosecond")) return 1_000_000_000;
    if (std.mem.eql(u8, name, "native")) return NATIVE_UNIT;
    if (std.mem.eql(u8, name, "perf_counter")) return PERF_COUNTER_UNIT;
    return null;
}

/// A positive-integer unit (`erlang:monotonic_time(1000)` == milliseconds) — the
/// value itself is the ticks-per-second; a non-positive integer is `null`.
pub fn ticksPerSecondOfInt(v: i128) ?i128 {
    return if (v > 0) v else null;
}

/// `erlang:convert_time_unit(value, from, to)` — the EXACT erts integer
/// arithmetic (`erl_time_sup.c`): a floor division toward −∞, achieved by the
/// negative-value pre-adjustment. `from_tps`/`to_tps` are ticks-per-second
/// (> 0 by construction of the resolvers above).
pub fn convert(value: i128, from_tps: i128, to_tps: i128) i128 {
    // erts: case Value<0 of true -> TU*Value - (FU-1); false -> TU*Value end div FU
    // (Erlang `div` truncates toward zero; the −(FU−1) adjustment turns that into
    //  a floor toward −∞ for negatives.)
    const num = if (value < 0) to_tps * value - (from_tps - 1) else to_tps * value;
    return @divTrunc(num, from_tps);
}

// ── the injectable source (Stratum-C seam; mockable for laws) ─────────────────

/// The OS-clock seam. A `Source` supplies three strictly-forward native-tick
/// readings; the laws inject a deterministic mock, the VM injects `RealSource`.
pub const Source = struct {
    ctx: *anyopaque,
    monoFn: *const fn (*anyopaque) i128,
    wallFn: *const fn (*anyopaque) i128,
    perfFn: *const fn (*anyopaque) i128,
    // gap-real-metrics runtime (FM-OBS-1): a REAL per-process CPU-time source
    // (native ticks). Backs `statistics(runtime)` — the CPU time consumed, NOT a
    // wall-clock alias (which would be a WRONG value). Strictly forward like the
    // others; 0 on a failed syscall keeps the readers total.
    cpuFn: *const fn (*anyopaque) i128,

    pub fn mono(self: Source) i128 {
        return self.monoFn(self.ctx);
    }
    pub fn wall(self: Source) i128 {
        return self.wallFn(self.ctx);
    }
    pub fn perf(self: Source) i128 {
        return self.perfFn(self.ctx);
    }
    /// Real per-process CPU time (native ticks) — `CLOCK_PROCESS_CPUTIME_ID`.
    pub fn cpu(self: Source) i128 {
        return self.cpuFn(self.ctx);
    }
};

/// Stratum-C: a real linux monotonic/realtime source via raw `clock_gettime`
/// (the `os_port.zig` raw-syscall precedent — no libc). On a failed syscall it
/// returns 0, which keeps the BIFs total (a degenerate but well-typed reading).
pub const RealSource = struct {
    var anchor: u8 = 0; // a stable, unique `*anyopaque` for the ctx slot

    fn readClock(clk: linux.clockid_t) i128 {
        var ts: linux.timespec = undefined;
        if (@as(isize, @bitCast(linux.clock_gettime(clk, &ts))) < 0) return 0;
        return @as(i128, ts.sec) * NATIVE_UNIT + @as(i128, ts.nsec);
    }
    fn monoFn(_: *anyopaque) i128 {
        return readClock(.MONOTONIC);
    }
    fn wallFn(_: *anyopaque) i128 {
        return readClock(.REALTIME);
    }
    fn perfFn(_: *anyopaque) i128 {
        return readClock(.MONOTONIC);
    }
    fn cpuFn(_: *anyopaque) i128 {
        // Real per-process CPU time — the honest `statistics(runtime)` source.
        return readClock(.PROCESS_CPUTIME_ID);
    }
    pub fn source() Source {
        return .{ .ctx = &anchor, .monoFn = monoFn, .wallFn = wallFn, .perfFn = perfFn, .cpuFn = cpuFn };
    }
};

// ── the clock ────────────────────────────────────────────────────────────────

/// A clock: an injected `Source` plus the no-time-warp constant `offset` (native
/// ticks) fixing `system == monotonic + offset`. Constructed by reading the
/// source's wall/monotonic once at init so system-time tracks wall-time; `warp`
/// then models a `multi_time_warp` adjustment.
pub const Clock = struct {
    source: Source,
    offset: i128, // native ticks; system_native = mono_native + offset

    pub fn init(source: Source) Clock {
        // Pin the offset from a single paired reading: offset = wall - mono.
        return .{ .source = source, .offset = source.wall() - source.mono() };
    }

    /// A time-warp step: shift the system/wall relationship by `delta` native
    /// ticks. Monotonic time is untouched — the "monotone under warp" invariant.
    pub fn warp(self: *Clock, delta: i128) void {
        self.offset += delta;
    }

    /// `erlang:monotonic_time(Unit)` — warp-invariant, strictly forward.
    pub fn monotonic(self: Clock, to_tps: i128) i128 {
        return convert(self.source.mono(), NATIVE_UNIT, to_tps);
    }

    /// `erlang:system_time(Unit)` — `monotonic + offset`, may warp either way.
    pub fn systemTime(self: Clock, to_tps: i128) i128 {
        return convert(self.source.mono() + self.offset, NATIVE_UNIT, to_tps);
    }

    /// `erlang:time_offset(Unit)` — the (no-warp: constant) offset.
    pub fn timeOffset(self: Clock, to_tps: i128) i128 {
        return convert(self.offset, NATIVE_UNIT, to_tps);
    }

    /// `erlang:timestamp/0` — the erlang-system-time `{MegaSec, Sec, MicroSec}`.
    pub fn timestampParts(self: Clock) [3]i128 {
        return partsOfMicros(self.systemTime(1_000_000));
    }

    /// `os:timestamp/0` — the OS wall clock directly (not the erlang offset), the
    /// `{MegaSec, Sec, MicroSec}` decomposition.
    pub fn osTimestampParts(self: Clock) [3]i128 {
        return partsOfMicros(convert(self.source.wall(), NATIVE_UNIT, 1_000_000));
    }

    /// `os:system_time(Unit)` reads the OS directly.
    pub fn osSystemTime(self: Clock, to_tps: i128) i128 {
        return convert(self.source.wall(), NATIVE_UNIT, to_tps);
    }
    /// `os:perf_counter/0` — the OS performance counter (native perf ticks).
    pub fn perfCounter(self: Clock) i128 {
        return self.source.perf();
    }
    /// `erlang:statistics(runtime)` basis — the REAL per-process CPU time,
    /// converted to `to_tps` (e.g. 1000 → milliseconds). Warp-invariant (CPU
    /// time, like monotonic time, is never shifted by a time-warp).
    pub fn processCpuTime(self: Clock, to_tps: i128) i128 {
        return convert(self.source.cpu(), NATIVE_UNIT, to_tps);
    }
};

/// Split a microsecond count into erts' `{MegaSec, Sec, MicroSec}` (floor-based,
/// so negatives never produce an out-of-range `micro`).
pub fn partsOfMicros(total_micros: i128) [3]i128 {
    const total_secs = @divFloor(total_micros, 1_000_000);
    const micro = @mod(total_micros, 1_000_000);
    const mega = @divFloor(total_secs, 1_000_000);
    const sec = @mod(total_secs, 1_000_000);
    return .{ mega, sec, micro };
}

// ── the OS environment seam (Stratum C) ──────────────────────────────────────

/// A process-environment model: seeded once from the real `/proc/self/environ`
/// (so `getenv` of an ambient host var is faithful to erts, which reads the same
/// `environ`), then mutated by `putenv`/`unsetenv`. Owned strings; freed in
/// `deinit`. On a non-Linux host / unreadable proc the seed is empty (graceful:
/// the round-trip still holds, only ambient reads are unavailable) — a documented
/// Stratum-C bound.
pub const EnvTable = struct {
    gpa: std.mem.Allocator,
    map: std.StringHashMapUnmanaged([]u8) = .empty,
    seeded: bool = false,

    pub fn init(gpa: std.mem.Allocator) EnvTable {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *EnvTable) void {
        var it = self.map.iterator();
        while (it.next()) |e| {
            self.gpa.free(e.key_ptr.*);
            self.gpa.free(e.value_ptr.*);
        }
        self.map.deinit(self.gpa);
    }

    fn ensureSeeded(self: *EnvTable) void {
        if (self.seeded) return;
        self.seeded = true; // set first: a failed read seeds empty, never retries
        seedFromProc(self) catch {};
    }

    /// Stratum-C: read `/proc/self/environ` (NUL-separated `KEY=VALUE` records)
    /// via raw linux syscalls and populate the map.
    fn seedFromProc(self: *EnvTable) !void {
        const path = "/proc/self/environ";
        const fd_rc = linux.openat(linux.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0);
        if (@as(isize, @bitCast(fd_rc)) < 0) return error.OpenFailed;
        const fd: linux.fd_t = @intCast(fd_rc);
        defer _ = linux.close(fd);

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.gpa);
        var chunk: [4096]u8 = undefined;
        while (true) {
            const n = linux.read(fd, &chunk, chunk.len);
            const ni: isize = @bitCast(n);
            if (ni < 0) return error.ReadFailed;
            if (ni == 0) break;
            try buf.appendSlice(self.gpa, chunk[0..@intCast(ni)]);
        }
        var it = std.mem.splitScalar(u8, buf.items, 0);
        while (it.next()) |rec| {
            if (rec.len == 0) continue;
            const eq = std.mem.indexOfScalar(u8, rec, '=') orelse continue;
            try self.putOwned(rec[0..eq], rec[eq + 1 ..]);
        }
    }

    fn putOwned(self: *EnvTable, key: []const u8, value: []const u8) !void {
        const gop = try self.map.getOrPut(self.gpa, key);
        if (gop.found_existing) {
            self.gpa.free(gop.value_ptr.*);
            gop.value_ptr.* = try self.gpa.dupe(u8, value);
            return;
        }
        // New key: own both key and value; roll back on a value-alloc failure.
        gop.key_ptr.* = self.gpa.dupe(u8, key) catch |e| {
            self.map.removeByPtr(gop.key_ptr);
            return e;
        };
        gop.value_ptr.* = self.gpa.dupe(u8, value) catch |e| {
            self.gpa.free(gop.key_ptr.*);
            self.map.removeByPtr(gop.key_ptr);
            return e;
        };
    }

    /// `os:getenv(Key)` — the value, or `null` (→ the atom `false`).
    pub fn get(self: *EnvTable, key: []const u8) ?[]const u8 {
        self.ensureSeeded();
        return self.map.get(key);
    }

    /// `os:putenv(Key, Value)` — set (overwriting).
    pub fn put(self: *EnvTable, key: []const u8, value: []const u8) !void {
        self.ensureSeeded();
        try self.putOwned(key, value);
    }

    /// `os:unsetenv(Key)` — remove; a subsequent `get` yields `null`.
    pub fn unset(self: *EnvTable, key: []const u8) void {
        self.ensureSeeded();
        if (self.map.fetchRemove(key)) |kv| {
            self.gpa.free(kv.key);
            self.gpa.free(kv.value);
        }
    }
};

// ============================================================================
// Laws
// ============================================================================

// A deterministic mock source: a monotonic counter that advances by a fixed step
// on every `mono` read, a wall clock offset from it, and a perf clock.
const MockSource = struct {
    mono_ticks: i128 = 1_000_000_000, // start away from 0
    wall_ticks: i128 = 1_700_000_000_000_000_000, // ~2023 in ns
    perf_ticks: i128 = 5_000,
    cpu_ticks: i128 = 3_000_000, // native ticks of CPU time consumed
    step: i128 = 7, // ns advanced per mono read
    cpu_step: i128 = 4, // ns of CPU advanced per cpu read (≤ step: CPU ≤ wall)

    fn monoFn(ctx: *anyopaque) i128 {
        const self: *MockSource = @ptrCast(@alignCast(ctx));
        self.mono_ticks += self.step;
        return self.mono_ticks;
    }
    fn wallFn(ctx: *anyopaque) i128 {
        const self: *MockSource = @ptrCast(@alignCast(ctx));
        self.wall_ticks += self.step;
        return self.wall_ticks;
    }
    fn perfFn(ctx: *anyopaque) i128 {
        const self: *MockSource = @ptrCast(@alignCast(ctx));
        self.perf_ticks += 1;
        return self.perf_ticks;
    }
    fn cpuFn(ctx: *anyopaque) i128 {
        const self: *MockSource = @ptrCast(@alignCast(ctx));
        self.cpu_ticks += self.cpu_step;
        return self.cpu_ticks;
    }
    fn source(self: *MockSource) Source {
        return .{ .ctx = self, .monoFn = monoFn, .wallFn = wallFn, .perfFn = perfFn, .cpuFn = cpuFn };
    }
};

// A naive reference floor-division (independent of the erts adjustment trick), so
// the FLOOR law checks the arithmetic by homomorphism, not by restating it.
fn refConvert(value: i128, from_tps: i128, to_tps: i128) i128 {
    return @divFloor(value * to_tps, from_tps);
}

test "LAW E5.8b IDENTITY + EXACT-RATIO + FLOOR: convert matches the reference floor-division (Mutant m1)" {
    const units = [_]i128{ 1, 1_000, 1_000_000, 1_000_000_000 };
    var prng = std.Random.DefaultPrng.init(0x71EC0DE);
    const r = prng.random();
    for (0..2000) |_| {
        const v: i128 = r.intRangeAtMost(i64, -5_000_000, 5_000_000);
        const from = units[r.uintLessThan(usize, units.len)];
        const to = units[r.uintLessThan(usize, units.len)];
        // IDENTITY
        try std.testing.expectEqual(v, convert(v, from, from));
        // FLOOR — agrees with an independent floor-division for ALL v incl. <0.
        // (Mutant m1: dropping the negative pre-adjustment truncates toward zero
        //  and reddens here on a negative down-conversion.)
        try std.testing.expectEqual(refConvert(v, from, to), convert(v, from, to));
    }
    // EXACT-RATIO — the pure decimal units are exact multiples (homomorphism).
    try std.testing.expectEqual(@as(i128, 1_000), convert(1, 1, 1_000)); // s→ms
    try std.testing.expectEqual(@as(i128, 1_000_000), convert(1, 1, 1_000_000)); // s→us
    try std.testing.expectEqual(@as(i128, 1_000_000_000), convert(1, 1, 1_000_000_000)); // s→ns
    // native ≡ nanosecond (zigvm resolution)
    try std.testing.expectEqual(convert(123456, NATIVE_UNIT, 1_000_000_000), @as(i128, 123456));
}

test "LAW E5.8b MONOTONE-CONV: convert preserves order" {
    const cases = [_][2]i128{ .{ 1, 1_000 }, .{ 1_000, 1 }, .{ 1_000_000, 1_000 } };
    var prng = std.Random.DefaultPrng.init(0xC10CC);
    const r = prng.random();
    for (0..1000) |_| {
        const a: i128 = r.intRangeAtMost(i64, -1_000_000, 1_000_000);
        const b: i128 = r.intRangeAtMost(i64, -1_000_000, 1_000_000);
        const c = cases[r.uintLessThan(usize, cases.len)];
        const lo = @min(a, b);
        const hi = @max(a, b);
        try std.testing.expect(convert(lo, c[0], c[1]) <= convert(hi, c[0], c[1]));
    }
}

test "LAW E5.8b MONOTONE-UNDER-WARP + OFFSET-IDENTITY (Mutant m2)" {
    var mock = MockSource{};
    var clock = Clock.init(mock.source());
    var prng = std.Random.DefaultPrng.init(0x5AFEC10C);
    const r = prng.random();

    var last_mono: i128 = clock.monotonic(NATIVE_UNIT);
    for (0..1500) |_| {
        // Interleave warps (multi_time_warp adjustments, either direction) with
        // reads. Monotonic time must be nondecreasing and INVARIANT to the warp;
        // system time may jump either way.
        if (r.boolean()) {
            const delta: i128 = r.intRangeAtMost(i64, -1_000_000_000, 1_000_000_000);
            clock.warp(delta);
        }
        const m = clock.monotonic(NATIVE_UNIT);
        try std.testing.expect(m >= last_mono); // MONOTONE-UNDER-WARP (Mutant m2)
        last_mono = m;

        const off = clock.timeOffset(NATIVE_UNIT);
        try std.testing.expectEqual(off, clock.offset); // native ≡ nanosecond
    }

    // OFFSET-IDENTITY, exact single-instant form via a FROZEN source (step 0).
    var frozen = MockSource{ .step = 0 };
    var fclock = Clock.init(frozen.source());
    for (0..50) |k| {
        fclock.warp(@as(i128, @intCast(k)) * 13 - 300);
        const s = fclock.systemTime(NATIVE_UNIT);
        const mo = fclock.monotonic(NATIVE_UNIT);
        const of = fclock.timeOffset(NATIVE_UNIT);
        try std.testing.expectEqual(s, mo + of); // system == monotonic + offset
    }
}

test "LAW E5.8b TIMESTAMP-RT: {mega,sec,micro} reassembles system micros, in range" {
    var prng = std.Random.DefaultPrng.init(0x715A3);
    const r = prng.random();
    for (0..2000) |_| {
        // Any nonnegative microsecond count (a real wall clock is > 0).
        const micros: i128 = r.intRangeAtMost(i64, 0, 4_000_000_000_000_000);
        const p = partsOfMicros(micros);
        try std.testing.expect(p[1] >= 0 and p[1] < 1_000_000); // sec in range
        try std.testing.expect(p[2] >= 0 and p[2] < 1_000_000); // micro in range
        try std.testing.expectEqual(micros, p[0] * 1_000_000_000_000 + p[1] * 1_000_000 + p[2]);
    }
}

test "LAW E5.8b REJECTION: unknown unit atom / non-positive integer unit → null" {
    try std.testing.expect(ticksPerSecondOfAtom("second") != null);
    try std.testing.expect(ticksPerSecondOfAtom("native") != null);
    try std.testing.expect(ticksPerSecondOfAtom("perf_counter") != null);
    try std.testing.expect(ticksPerSecondOfAtom("fortnight") == null);
    try std.testing.expect(ticksPerSecondOfAtom("") == null);
    try std.testing.expect(ticksPerSecondOfInt(1000) != null);
    try std.testing.expect(ticksPerSecondOfInt(0) == null);
    try std.testing.expect(ticksPerSecondOfInt(-5) == null);
}

test "LAW E5.8b EnvTable round-trip: put/get/unset over an injected key (no leaks)" {
    var env = EnvTable.init(std.testing.allocator);
    defer env.deinit();
    // A key the host is overwhelmingly unlikely to carry.
    const k = "ZIGVM_TIME_ALGEBRA_LAW_KEY";
    try std.testing.expect(env.get(k) == null); // absent → null (→ false)
    try env.put(k, "hello");
    try std.testing.expectEqualStrings("hello", env.get(k).?);
    try env.put(k, "world"); // overwrite frees the old value (no leak)
    try std.testing.expectEqualStrings("world", env.get(k).?);
    env.unset(k);
    try std.testing.expect(env.get(k) == null); // unset → null
    env.unset(k); // idempotent, no double-free
}

test "LAW E5.8b RealSource monotonic: two reads never go backward" {
    var clock = Clock.init(RealSource.source());
    const a = clock.monotonic(NATIVE_UNIT);
    const b = clock.monotonic(NATIVE_UNIT);
    try std.testing.expect(b >= a);
    try std.testing.expect(clock.systemTime(1) >= 0); // seconds since epoch > 0
}

test "LAW gap-real-metrics CPU-MONOTONE + CONVERT: processCpuTime is strictly forward off the seam and converts native→ms by the same floor rule (statistics(runtime) basis)" {
    // gap-real-metrics runtime. SEMANTIC DOMAIN: statistics(runtime)'s Total is a
    // REAL per-process CPU-time reading, converted native→to_tps. The law fixes:
    // (1) MONOTONICITY — CPU time never runs backward; (2) CONVERT-HOMOMORPHISM —
    // processCpuTime(to_tps) == convert(raw_cpu, NATIVE, to_tps). Deterministic via
    // the MockSource (cpu_step > 0), so no host-nondeterminism in this law.
    var mock = MockSource{};
    var clock = Clock.init(mock.source());
    // MONOTONE: each read advances by cpu_step (> 0), never decreasing.
    const a = clock.processCpuTime(NATIVE_UNIT);
    const b = clock.processCpuTime(NATIVE_UNIT);
    try std.testing.expect(b > a); // strictly forward under load
    try std.testing.expectEqual(mock.cpu_step, b - a); // exactly cpu_step per read
    // CONVERT-HOMOMORPHISM: ms reading == convert(raw native ticks, NATIVE, 1000).
    const raw_before = mock.cpu_ticks;
    const ms = clock.processCpuTime(1000);
    try std.testing.expectEqual(convert(raw_before + mock.cpu_step, NATIVE_UNIT, 1000), ms);

    // RealSource: real CPU time is non-negative and monotone across two reads.
    var rclock = Clock.init(RealSource.source());
    const r1 = rclock.processCpuTime(1000);
    const r2 = rclock.processCpuTime(1000);
    try std.testing.expect(r1 >= 0); // HONESTY: a real reading, never negative
    try std.testing.expect(r2 >= r1); // MONOTONICITY on the real seam
}
