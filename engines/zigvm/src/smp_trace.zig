//! src/smp_trace.zig — S-epoch "observability enabler" (slice SMP-OBS).
//!
//! Self-contained, COMPILE-GATED SMP lock observability for the coordinator-Lv
//! elimination epoch (`docs/20260729-051217-s-epoch-smp-coordinator-lock-fractal.md`
//! §4; `skills/smp-concurrency-slice`). Provides:
//!   (①) per-lock CONTENTION records — acquisitions + wait_ns/hold_ns histograms,
//!   (②) a per-THREAD lock-ORDER checker over L_v→L_c→{L_reg,L_timer}→L_e→L_events
//!        that fails CLOSED at the acquire site (UCA-SMP-9 guard — a deadlock cycle
//!        becomes a caught error/panic at the acquisition, never a hung scheduler),
//!   (③) the interface for deterministic schedule-seed replay of `driveThreads`.
//!
//! ZERO-COST WHEN OFF. `enabled` is a COMPTIME master gate: every wiring site is
//! `if (comptime smp_trace.enabled) …`, so with `enabled == false` (the default)
//! the hooks are dead-code-eliminated and the spinlocks are byte-identical to
//! pre-instrumentation — the 991-law gate stays green unchanged. `active` is the
//! RUNTIME toggle (harness `--smp-contention`) consulted only once compiled in.
//!
//! LEAF MODULE: imports only `std` (no proc/timer/registry) ⇒ no import cycle, and
//! the tracer introduces NO ordered lock of its own (all state is threadlocal;
//! cross-thread merge is a lock-free shard registry).
//!
//! Scope limit: this slice lands the OBSERVABILITY MECHANISM + its proof. The
//! live-lock wiring is comptime-gated in place; the `--smp-contention` harness
//! attribution mode and the actual residual-`L_v` shard (grant-counter / events /
//! drainSignals) are the named follow-on slices — the enabler is proven first.
const std = @import("std");

// ── master gates ────────────────────────────────────────────────────────────
/// COMPTIME gate. `true` compiles the instrumentation in. `false` (default) ⇒
/// every `if (comptime smp_trace.enabled) …` wiring site is DCE'd.
pub const enabled: bool = false;
/// RUNTIME toggle (set by `--smp-contention`). Only consulted when `enabled`.
pub var active: bool = false;

// ── lock identity & the total order ──────────────────────────────────────────
/// Distinct identity per instrumented lock (indexes the contention record). Rank
/// (the ORDER position) is separate — `L_reg`/`L_timer` are distinct identities
/// but share rank 2.
pub const LockId = enum(u8) { l_v, l_c, l_q, l_reg, l_timer, l_e, l_events, l_sigq };
pub const N_LOCKS = @typeInfo(LockId).@"enum".fields.len;

/// The total order: L_v(0) < L_c(1) < {L_reg,L_timer}(2) < L_e(3) < L_events(4)
/// < L_sigq(5). A target with STRICTLY GREATER rank than every held lock is safe
/// to acquire. `L_sigq` (Option B, the per-Process signal-queue leaf) is the
/// LOWEST leaf: always acquired last, and NOTHING may be acquired while holding
/// it — its critical sections are pure `sigq` append/detach/sweep, no lock reach.
pub fn rank(id: LockId) u8 {
    return switch (id) {
        .l_v => 0,
        .l_c => 1,
        // N9-Q1: `L_q` — the per-worker run-queue locks (one identity, one
        // rank slot; never more than ONE QLock held at a time by design —
        // steal pops from the victim then owns with the pid in hand).
        .l_q => 2,
        .l_reg, .l_timer => 3,
        .l_e => 4,
        .l_events => 5,
        .l_sigq => 6,
    };
}

pub const OrderError = error{LockOrderViolation};

// ── ① contention record ──────────────────────────────────────────────────────
/// A self-contained 16-bucket histogram (mirrors proc.LatencyHistogram's fold;
/// embedded to keep smp_trace a leaf module).
pub const Histogram = struct {
    width: u64 = 256, // ns per bucket; bucket = min(v/width, 15)
    buckets: [16]u64 = [_]u64{0} ** 16,
    n: u64 = 0,

    pub fn record(self: *Histogram, v: u64) void {
        self.buckets[@intCast(@min(v / self.width, 15))] += 1;
        self.n += 1;
    }
    pub fn merge(self: *Histogram, other: *const Histogram) void {
        for (&self.buckets, other.buckets) |*d, s| d.* += s;
        self.n += other.n;
    }
    /// CONSERVATION: Σ buckets == n (no sample lost/duplicated).
    pub fn conserves(self: *const Histogram) bool {
        var s: u64 = 0;
        for (self.buckets) |c| s += c;
        return s == self.n;
    }
    pub fn percentile(self: *const Histogram, p: u8) u64 {
        if (self.n == 0) return 0;
        const target = (self.n * @min(p, 100) + 99) / 100;
        var cum: u64 = 0;
        for (self.buckets, 0..) |c, b| {
            cum += c;
            if (cum >= target) return @as(u64, @intCast(b)) * self.width;
        }
        return 15 * self.width;
    }
};

pub const Contention = struct {
    acquisitions: u64 = 0,
    wait: Histogram = .{}, // ns spun to acquire
    hold: Histogram = .{}, // ns held
};

// ── ② per-thread order-checker + contention shard ────────────────────────────
pub const MAX_DEPTH = 8; // max simultaneously-held locks (steady state ≤ ~4)

/// Per-thread trace state: ONLY the held-lock stack (order-check + hold timing).
/// The contention COUNTS live in the global static `g_contention` array (indexed
/// by an atomically-assigned per-thread slot), NOT here — because a threadlocal
/// dies with its thread, so a post-join `report()` over threadlocal pointers is a
/// use-after-free (the enabler's own first caught bug: FM-SMP-TRACE-UAF). The
/// held-stack is fine threadlocal — it is only ever read by its OWN thread while
/// that thread is alive.
pub const ThreadState = struct {
    held: [MAX_DEPTH]LockId = undefined,
    hold_start: [MAX_DEPTH]u64 = undefined,
    depth: usize = 0,
    pending_wait_start: u64 = 0,

    /// The LAW-carrying core (testable, panic-free): `target` must be strictly
    /// BELOW every currently-held lock. Returns `error.LockOrderViolation` on an
    /// out-of-order (or equal-rank sibling) acquire — the UCA-SMP-9 back-edge.
    pub fn checkOrder(self: *const ThreadState, target: LockId) OrderError!void {
        const rt = rank(target);
        var i = self.depth;
        while (i > 0) {
            i -= 1;
            if (rt <= rank(self.held[i])) return error.LockOrderViolation;
        }
    }

    pub fn push(self: *ThreadState, target: LockId, start_ns: u64) void {
        if (self.depth >= MAX_DEPTH) return; // overflow guard (unreachable in practice)
        self.held[self.depth] = target;
        self.hold_start[self.depth] = start_ns;
        self.depth += 1;
    }

    /// Remove `target` (searched top-down; tolerant of non-LIFO release), returning
    /// its hold-start stamp (0 if not held).
    pub fn pop(self: *ThreadState, target: LockId) u64 {
        var i = self.depth;
        while (i > 0) {
            i -= 1;
            if (self.held[i] == target) {
                const start = self.hold_start[i];
                var j = i;
                while (j + 1 < self.depth) : (j += 1) {
                    self.held[j] = self.held[j + 1];
                    self.hold_start[j] = self.hold_start[j + 1];
                }
                self.depth -= 1;
                return start;
            }
        }
        return 0;
    }
    pub fn reset(self: *ThreadState) void {
        self.depth = 0;
    }
};

// ── live threadlocal held-stack + GLOBAL-STATIC contention shards ─────────────
// The held-stack is threadlocal (per-thread by nature). The contention CELLS live
// in a global static array that OUTLIVES every worker thread, so a post-join
// `report()` reads valid memory (no UAF). Each thread owns row `my_slot` — a
// disjoint row per thread, so writes are contention-free without a lock.
threadlocal var tls: ThreadState = .{};
threadlocal var my_slot: usize = 0;
threadlocal var slot_assigned: bool = false;

const MAX_THREADS = 128;
var g_contention: [MAX_THREADS][N_LOCKS]Contention = [_][N_LOCKS]Contention{[_]Contention{.{}} ** N_LOCKS} ** MAX_THREADS;
var g_count = std.atomic.Value(usize).init(0);

fn register() void {
    if (slot_assigned) return;
    slot_assigned = true;
    const slot = g_count.fetchAdd(1, .acq_rel); // lock-free; no ordered lock
    my_slot = if (slot < MAX_THREADS) slot else MAX_THREADS - 1;
}

/// Reset ALL global contention shards + the thread counter (a fresh measurement).
pub fn resetContention() void {
    g_count.store(0, .release);
    for (&g_contention) |*row| row.* = [_]Contention{.{}} ** N_LOCKS;
}

/// Monotonic ns (bounded-measurement clock only; identical to timer_wheel.monoNs).
fn nowNs() u64 {
    var ts: std.os.linux.timespec = undefined;
    if (@as(isize, @bitCast(std.os.linux.clock_gettime(.MONOTONIC, &ts))) < 0) return 0;
    return @as(u64, @intCast(ts.sec)) *% 1_000_000_000 +% @as(u64, @intCast(ts.nsec));
}

fn orderPanic(target: LockId) noreturn {
    const rt = rank(target);
    var offender: LockId = target;
    var i = tls.depth;
    while (i > 0) {
        i -= 1;
        if (rt <= rank(tls.held[i])) {
            offender = tls.held[i];
            break;
        }
    }
    std.debug.panic("SMP lock-order violation (UCA-SMP-9): acquiring {s} (rank {d}) while holding {s} (rank {d})", .{ @tagName(target), rt, @tagName(offender), rank(offender) });
}

// ── the wiring hooks (thin threadlocal wrappers; called under `if comptime enabled`) ──
/// Top of `lock()`, before the spin: order-check (fail-closed) + stamp wait-start.
pub fn onAcquire(id: LockId) void {
    if (!active) return;
    register();
    tls.checkOrder(id) catch orderPanic(id);
    tls.pending_wait_start = nowNs();
}
/// After the spin succeeds: fold wait_ns into this thread's GLOBAL-STATIC row,
/// record hold-start on the threadlocal held-stack, push held.
pub fn onAcquired(id: LockId) void {
    if (!active) return;
    const now = nowNs();
    g_contention[my_slot][@intFromEnum(id)].wait.record(now -| tls.pending_wait_start);
    tls.push(id, now);
}
/// Top of `unlock()`: fold hold_ns + bump acquisitions in the global row, pop held.
pub fn onRelease(id: LockId) void {
    if (!active) return;
    const start = tls.pop(id);
    const c = &g_contention[my_slot][@intFromEnum(id)];
    c.hold.record(nowNs() -| start);
    c.acquisitions += 1;
}

/// Read-side merge across all thread rows in the GLOBAL-STATIC array (valid
/// POST-JOIN — the rows outlive the threads, so no UAF). Lock-free walk.
pub fn report(id: LockId) Contention {
    var out = Contention{};
    const idx = @intFromEnum(id);
    const n = @min(g_count.load(.acquire), MAX_THREADS);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out.acquisitions += g_contention[i][idx].acquisitions;
        out.wait.merge(&g_contention[i][idx].wait);
        out.hold.merge(&g_contention[i][idx].hold);
    }
    return out;
}

// ── ③ deterministic schedule-seed replay (interface only) ────────────────────
/// A cooperative schedule seed: a deterministic decision stream a future
/// `driveThreads` consults at each grant/steal choice point so `same seed → same
/// interleaving → a race/deadlock is reproducible`.
pub const Schedule = struct {
    state: u64,
    pub fn init(seed: u64) Schedule {
        return .{ .state = seed | 1 };
    }
    /// xorshift64 — the next deterministic decision value.
    pub fn next(self: *Schedule) u64 {
        var x = self.state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.state = x;
        return x;
    }
};
/// Set by `--smp-replay <seed>`; null ⇒ production policy (no replay).
pub var schedule: ?Schedule = null;

/// The consult point. `driveThreads` would call this where it picks a ready proc /
/// steal victim among `n` candidates; null ⇒ keep the default policy (zero-cost).
pub fn scheduleDecision(n: usize) ?usize {
    if (comptime !enabled) return null;
    if (schedule) |*s| return @intCast(s.next() % @max(n, 1));
    return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// LAWS — the observability MECHANISM proven correct (S-epoch SMP-OBS)
// ═══════════════════════════════════════════════════════════════════════════

test "LAW smp-trace-order: the lock-order checker REFUSES an out-of-order or equal-rank acquire fail-closed (UCA-SMP-9 caught at the acquire site) and ADMITS every sanctioned downward prefix — testable/no-panic" {
    var st = ThreadState{};
    // ADMITS the in-order descent L_v → L_c → L_timer.
    try st.checkOrder(.l_v);
    st.push(.l_v, 0);
    try st.checkOrder(.l_c);
    st.push(.l_c, 0);
    try st.checkOrder(.l_timer);
    st.push(.l_timer, 0);
    // REFUSES acquiring a strictly-higher lock while holding a lower one (the crux
    // L_c-then-L_v inversion). MUT-SMPLO-1 (ignore held set → admitted → red);
    // MUT-SMPLO-2 (rank L_c below L_v → the positive prefix reds).
    try std.testing.expectError(error.LockOrderViolation, st.checkOrder(.l_v));
    try std.testing.expectError(error.LockOrderViolation, st.checkOrder(.l_c));
    // REFUSES an equal-rank sibling (no sanctioned L_reg↔L_timer nesting).
    try std.testing.expectError(error.LockOrderViolation, st.checkOrder(.l_reg));
    // A fully in-order chain from empty is admitted (not over-refusing).
    var fresh = ThreadState{};
    try fresh.checkOrder(.l_v);
    fresh.push(.l_v, 0);
    try fresh.checkOrder(.l_events); // below everything except l_sigq
    // Option B: `l_sigq` is the NEW lowest leaf — admitted under any held lock,
    // and NOTHING is admissible while holding it (pure leaf sections only).
    try fresh.checkOrder(.l_sigq);
    fresh.push(.l_sigq, 0);
    try std.testing.expectError(error.LockOrderViolation, fresh.checkOrder(.l_events));
    try std.testing.expectError(error.LockOrderViolation, fresh.checkOrder(.l_sigq));
}

test "LAW smp-trace-contention: per-lock acquisitions counted EXACTLY and the wait/hold histograms CONSERVE their samples — the FM-SMP-CONTENTION-BLIND evidence" {
    // Test the Contention accumulation logic directly (the same fold the live hooks
    // apply to a global row). N acquire/release cycles → N acquisitions, N samples.
    var c = Contention{};
    const N: u64 = 500;
    var k: u64 = 0;
    while (k < N) : (k += 1) {
        c.wait.record(k); // wait sample
        c.hold.record(k * 2); // hold sample
        c.acquisitions += 1;
    }
    try std.testing.expectEqual(N, c.acquisitions); // MUT-SMPCA-1 miscount → red
    try std.testing.expectEqual(N, c.wait.n);
    try std.testing.expectEqual(N, c.hold.n);
    try std.testing.expect(c.wait.conserves()); // MUT-SMPCA-2 lost sample → n≠Σ → red
    try std.testing.expect(c.hold.conserves());
    // an untouched Contention stays zero (no cross-contamination).
    const empty = Contention{};
    try std.testing.expectEqual(@as(u64, 0), empty.acquisitions);
}

test "LAW smp-trace-replay: the same schedule seed reproduces an IDENTICAL decision stream (deterministic interleaving — a race becomes reproducible/bisectable)" {
    var a = Schedule.init(0xC0FFEE);
    var b = Schedule.init(0xC0FFEE);
    for (0..64) |_| try std.testing.expectEqual(a.next(), b.next());
    // a DIFFERENT seed diverges (non-degenerate).
    var d = Schedule.init(0xBEEF);
    var same: usize = 0;
    for (0..64) |_| {
        if (a.next() == d.next()) same += 1;
    }
    try std.testing.expect(same < 8); // effectively independent streams
}
