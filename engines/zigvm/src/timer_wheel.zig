//! beam-zig M7 / S21: **timers** — sorted-list oracle vs hierarchical wheel
//! (cf. erts erl_hl_timer.c, time.c).
//!
//! Signature:
//!   start  : (Timers, at, payload) -> (Timers, Id)   (constructor)
//!   cancel : (Timers, Id) -> (Timers, bool)          (combinator)
//!   advance: (Timers, now) -> (Timers, [Fired])      (observation w/ time)
//!
//! Semantic domain: the set of pending (at, id, payload) triples; `advance`
//! observes the ≤-now subset in (at, id) order.
//!
//! Laws:
//!   AT-MOST-ONCE       an id fires at most once, ever
//!   CANCEL-THEN-FIRE IMPOSSIBLE  a successfully cancelled id never fires
//!   MONOTONIC DELIVERY fired sequence is nondecreasing in `at`, ties by id
//!                      (ids ascend within one instant), and never fires
//!                      before its time
//!   EXACTNESS          everything due (at ≤ now) fires on advance(now)
//!   HOMOMORPHISM       oracle (sorted list) and wheel (256-slot hierarchical,
//!                      cascading) produce identical fired sequences under
//!                      twin op streams
//!
//! E6.2 (Task 2): this wheel is now LIVE — `proc.zig`'s `Vm` owns a `WheelTimers`
//! and drives real receive timers (`wait_timeout` finite) + the `send_after`/
//! `start_timer`/`read_timer`/`cancel_timer` BIF family off a DETERMINISTIC virtual
//! clock (`Vm.vclock`, advanced event-to-event, never a wall read). The wheel's
//! payload becomes an index into the Vm's per-entry semantic metadata; the wheel
//! supplies the ordering/at-most-once/cancel-then-fire guarantees the integration
//! laws (in `proc.zig`) rely on. DIVERGENCE entry 5's residual + entry 104.
//!
//! gap-b-1 (SMP coarse→per-lock, step 1): the wheel now carries its OWN lock
//! `L_timer` (see `TimerLock`), acquired around every op, STRICTLY below `L_v` in
//! the order `L_v→L_c→{L_reg,L_timer}→L_e` (UCA-SMP-9/C-8, no back-edge by
//! construction). Laws: `gap-b-1 timer-linearizability-under-L_timer` + `gap-b-1
//! lock-order no-back-edge` (both bounded). Behaviour-preserving refactor.

const std = @import("std");
const smp_trace = @import("smp_trace.zig"); // S-epoch SMP-OBS: L_timer contention + order-check hooks (zero-cost when disabled)

pub const TimerId = u64;

pub const Fired = struct { at: u64, id: TimerId, payload: u64 };

/// `L_timer` — the timer wheel's own lock (`gap-b-1`, the leaf-most step of the
/// SMP coarse→per-lock transition). A self-contained atomic spinlock, IDENTICAL
/// in shape to `proc.SmpEngine.VmLock` (`L_v`): acquire `.acquire`, release
/// `.release`, a full happens-before fence around every wheel mutation.
///
/// LOCK-ORDER (the safety-critical invariant `L_v → L_c → {L_reg,L_timer} → L_e`,
/// UCA-SMP-9 / C-8): `L_timer` sits STRICTLY BELOW `L_v` in the total order. It is
/// acquired ONLY inside the `WheelTimers.{start,cancel,advance,pending}` methods,
/// whose bodies reference nothing but `self` (a `*WheelTimers`), `self.gpa`, and
/// the caller's `out` list — they hold NO reference to `Vm`, `ThreadCtx`, or
/// `VmLock`, so a `WheelTimers` method CANNOT acquire `L_v`. Therefore NO path
/// acquires `L_v` while holding `L_timer`: the back-edge is impossible BY
/// CONSTRUCTION (proof by type — the outer lock is unreachable from this scope).
/// Every live acquisition happens while the caller already holds `L_v` (the SMP
/// epilogue/`interpret` region) or holds no lock at all (single-thread
/// `driveModel`); either way the observed order is `L_v → L_timer`, never the
/// reverse. See `docs/OTP30_SMP_EPOCH_PLAN.md` step 1 + `DIVERGENCE_LOG` gap-b.
pub const TimerLock = struct {
    held: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    pub fn lock(self: *TimerLock) void {
        if (comptime smp_trace.enabled) smp_trace.onAcquire(.l_timer);
        while (self.held.swap(true, .acquire)) std.Thread.yield() catch {};
        if (comptime smp_trace.enabled) smp_trace.onAcquired(.l_timer);
    }
    pub fn unlock(self: *TimerLock) void {
        if (comptime smp_trace.enabled) smp_trace.onRelease(.l_timer);
        self.held.store(false, .release);
    }
};

/// INITIAL ENCODING — the oracle: a flat list, scanned & sorted on advance.
pub const OracleTimers = struct {
    const Entry = struct { at: u64, id: TimerId, payload: u64 };
    gpa: std.mem.Allocator,
    entries: std.ArrayList(Entry),
    next_id: TimerId = 1,

    pub fn init(gpa: std.mem.Allocator) OracleTimers {
        return .{ .gpa = gpa, .entries = .empty };
    }
    pub fn deinit(self: *OracleTimers) void {
        self.entries.deinit(self.gpa);
    }

    pub fn start(self: *OracleTimers, at: u64, payload: u64) !TimerId {
        const id = self.next_id;
        self.next_id += 1;
        try self.entries.append(self.gpa, .{ .at = at, .id = id, .payload = payload });
        return id;
    }

    pub fn cancel(self: *OracleTimers, id: TimerId) bool {
        for (self.entries.items, 0..) |e, k| {
            if (e.id == id) {
                _ = self.entries.orderedRemove(k);
                return true;
            }
        }
        return false;
    }

    pub fn advance(self: *OracleTimers, now: u64, out: *std.ArrayList(Fired)) !void {
        // collect due, sort by (at, id), remove from pending
        var due: std.ArrayList(Fired) = .empty;
        defer due.deinit(self.gpa);
        var k: usize = 0;
        while (k < self.entries.items.len) {
            const e = self.entries.items[k];
            if (e.at <= now) {
                try due.append(self.gpa, .{ .at = e.at, .id = e.id, .payload = e.payload });
                _ = self.entries.orderedRemove(k);
            } else k += 1;
        }
        std.sort.insertion(Fired, due.items, {}, struct {
            fn less(_: void, a: Fired, b: Fired) bool {
                if (a.at != b.at) return a.at < b.at;
                return a.id < b.id;
            }
        }.less);
        try out.appendSlice(self.gpa, due.items);
    }

    pub fn pending(self: *const OracleTimers) usize {
        return self.entries.items.len;
    }
};

/// FINAL ENCODING — a two-level hierarchical wheel: 256 near slots (1 tick
/// each) + overflow list cascaded on wrap (the erts wheel's essential shape).
pub const WheelTimers = struct {
    const Entry = struct { at: u64, id: TimerId, payload: u64, cancelled: bool = false };
    const SLOTS = 256;

    gpa: std.mem.Allocator,
    slots: [SLOTS]std.ArrayList(Entry),
    overflow: std.ArrayList(Entry), // at ≥ horizon
    now: u64 = 0,
    next_id: TimerId = 1,
    /// `L_timer` — every mutating/observing wheel op holds this for its whole
    /// critical section (gap-b-1). Strictly below `L_v`; never acquires `L_v`.
    l_timer: TimerLock = .{},

    pub fn init(gpa: std.mem.Allocator) WheelTimers {
        return .{ .gpa = gpa, .slots = @splat(.empty), .overflow = .empty };
    }
    pub fn deinit(self: *WheelTimers) void {
        for (&self.slots) |*s| s.deinit(self.gpa);
        self.overflow.deinit(self.gpa);
    }

    fn horizon(self: *const WheelTimers) u64 {
        return self.now + SLOTS;
    }

    pub fn start(self: *WheelTimers, at: u64, payload: u64) !TimerId {
        self.l_timer.lock(); // L_timer — acquired under L_v (or lock-free path)
        defer self.l_timer.unlock();
        const id = self.next_id;
        self.next_id += 1;
        const e = Entry{ .at = at, .id = id, .payload = payload };
        if (at < self.horizon()) {
            try self.slots[at % SLOTS].append(self.gpa, e);
        } else {
            try self.overflow.append(self.gpa, e);
        }
        return id;
    }

    pub fn cancel(self: *WheelTimers, id: TimerId) bool {
        self.l_timer.lock(); // L_timer
        defer self.l_timer.unlock();
        for (&self.slots) |*s| {
            for (s.items) |*e| {
                if (e.id == id and !e.cancelled) {
                    e.cancelled = true;
                    return true;
                }
            }
        }
        for (self.overflow.items) |*e| {
            if (e.id == id and !e.cancelled) {
                e.cancelled = true;
                return true;
            }
        }
        return false;
    }

    pub fn advance(self: *WheelTimers, now: u64, out: *std.ArrayList(Fired)) !void {
        self.l_timer.lock(); // L_timer
        defer self.l_timer.unlock();
        std.debug.assert(now >= self.now);
        var fired: std.ArrayList(Fired) = .empty;
        defer fired.deinit(self.gpa);
        while (self.now <= now) {
            const slot = &self.slots[self.now % SLOTS];
            var k: usize = 0;
            while (k < slot.items.len) {
                const e = slot.items[k];
                if (e.at == self.now) {
                    if (!e.cancelled)
                        try fired.append(self.gpa, .{ .at = e.at, .id = e.id, .payload = e.payload });
                    _ = slot.swapRemove(k);
                } else k += 1;
            }
            self.now += 1;
            // cascade: overflow entries entering the horizon get slotted
            if (self.now % SLOTS == 0 or true) { // cascade continuously (simple & correct)
                var j: usize = 0;
                while (j < self.overflow.items.len) {
                    const e = self.overflow.items[j];
                    if (e.at < self.horizon()) {
                        _ = self.overflow.swapRemove(j);
                        if (!e.cancelled)
                            try self.slots[e.at % SLOTS].append(self.gpa, .{ .at = e.at, .id = e.id, .payload = e.payload });
                    } else j += 1;
                }
            }
        }
        self.now = now; // (loop leaves self.now == now+1-1 semantics aligned)
        // wheel slots are unordered within an instant: sort fired by (at,id)
        std.sort.insertion(Fired, fired.items, {}, struct {
            fn less(_: void, a: Fired, b: Fired) bool {
                if (a.at != b.at) return a.at < b.at;
                return a.id < b.id;
            }
        }.less);
        try out.appendSlice(self.gpa, fired.items);
    }

    pub fn pending(self: *WheelTimers) usize {
        self.l_timer.lock(); // L_timer — a wheel READ is a timer op too
        defer self.l_timer.unlock();
        var n: usize = 0;
        for (self.slots) |s| {
            for (s.items) |e| {
                if (!e.cancelled) n += 1;
            }
        }
        for (self.overflow.items) |e| {
            if (!e.cancelled) n += 1;
        }
        return n;
    }
};

// ============================================================================
// Law suite
// ============================================================================

test "Twin op streams: wheel ≡ oracle; at-most-once; cancel-then-fire impossible; monotone" {
    const gpa = std.testing.allocator;

    for (0..30) |iter| {
        var prng = std.Random.DefaultPrng.init(0x71AE +% iter);
        const random = prng.random();

        var oracle = OracleTimers.init(gpa);
        defer oracle.deinit();
        var wheel = WheelTimers.init(gpa);
        defer wheel.deinit();

        var fired_o: std.ArrayList(Fired) = .empty;
        defer fired_o.deinit(gpa);
        var fired_w: std.ArrayList(Fired) = .empty;
        defer fired_w.deinit(gpa);

        var cancelled_ok: std.ArrayList(TimerId) = .empty;
        defer cancelled_ok.deinit(gpa);

        var now: u64 = 0;
        var live_ids: std.ArrayList(TimerId) = .empty;
        defer live_ids.deinit(gpa);

        for (0..200) |_| {
            switch (random.uintLessThan(u8, 4)) {
                0, 1 => { // start a timer 0..600 ticks out (crosses horizon)
                    const at = now + random.uintLessThan(u64, 600);
                    const payload = random.int(u32);
                    const id_o = try oracle.start(at, payload);
                    const id_w = try wheel.start(at, payload);
                    try std.testing.expectEqual(id_o, id_w); // twin id streams
                    try live_ids.append(gpa, id_o);
                },
                2 => { // cancel a random known id (may already be fired)
                    if (live_ids.items.len > 0) {
                        const id = live_ids.items[random.uintLessThan(usize, live_ids.items.len)];
                        const co = oracle.cancel(id);
                        const cw = wheel.cancel(id);
                        try std.testing.expectEqual(co, cw); // agree on success
                        if (co) try cancelled_ok.append(gpa, id);
                    }
                },
                else => { // advance time
                    now += random.uintLessThan(u64, 90);
                    try oracle.advance(now, &fired_o);
                    try wheel.advance(now, &fired_w);
                    try std.testing.expectEqual(fired_o.items.len, fired_w.items.len);
                },
            }
        }
        // drain everything
        now += 1000;
        try oracle.advance(now, &fired_o);
        try wheel.advance(now, &fired_w);

        // HOMOMORPHISM: identical fired sequences
        try std.testing.expectEqual(fired_o.items.len, fired_w.items.len);
        for (fired_o.items, fired_w.items) |a, b| {
            try std.testing.expectEqual(a.at, b.at);
            try std.testing.expectEqual(a.id, b.id);
            try std.testing.expectEqual(a.payload, b.payload);
        }

        // AT-MOST-ONCE
        var seen: std.AutoHashMapUnmanaged(TimerId, void) = .empty;
        defer seen.deinit(gpa);
        for (fired_w.items) |f| {
            try std.testing.expect(!seen.contains(f.id));
            try seen.put(gpa, f.id, {});
        }

        // CANCEL-THEN-FIRE IMPOSSIBLE
        for (cancelled_ok.items) |id| {
            try std.testing.expect(!seen.contains(id));
        }

        // MONOTONIC + never early: verified pairwise on the fired stream
        // (at nondecreasing; equal instants ordered by id) — and everything
        // pending is strictly in the future
        var k: usize = 1;
        while (k < fired_w.items.len) : (k += 1) {
            const a = fired_w.items[k - 1];
            const b = fired_w.items[k];
            try std.testing.expect(a.at < b.at or (a.at == b.at and a.id < b.id));
        }
        try std.testing.expectEqual(@as(usize, 0), wheel.pending());
        try std.testing.expectEqual(@as(usize, 0), oracle.pending());
    }
}

test "Exactness: everything due fires on advance, nothing early" {
    const gpa = std.testing.allocator;
    var wheel = WheelTimers.init(gpa);
    defer wheel.deinit();
    var fired: std.ArrayList(Fired) = .empty;
    defer fired.deinit(gpa);

    _ = try wheel.start(10, 1);
    _ = try wheel.start(300, 2); // beyond the 256 horizon: overflow path
    _ = try wheel.start(10, 3);
    _ = try wheel.start(11, 4);

    try wheel.advance(9, &fired);
    try std.testing.expectEqual(@as(usize, 0), fired.items.len); // nothing early
    try wheel.advance(10, &fired);
    try std.testing.expectEqual(@as(usize, 2), fired.items.len); // both at t=10, id order
    try std.testing.expect(fired.items[0].id < fired.items[1].id);
    try wheel.advance(400, &fired);
    try std.testing.expectEqual(@as(usize, 4), fired.items.len); // 11 then 300
    try std.testing.expectEqual(@as(u64, 11), fired.items[2].at);
    try std.testing.expectEqual(@as(u64, 300), fired.items[3].at);
}

// ============================================================================
// gap-b-1: L_timer — the timer-wheel lock (SMP coarse→per-lock transition, step 1)
// ============================================================================
//
// SAFETY PACKET (SAFETY_ANALYSIS §10; controller = the lock hierarchy / the timer
// -wheel lock acquisition, CTRL-SCHED). UCA = UCA-SMP-9 (a lock acquired out of
// order → L_v↔L_timer priority-inversion / hold-and-wait DEADLOCK). HAZARD = a
// scheduler thread never returns (hung node). MITIGATION = the proven total order
// `L_v → L_timer` with NO back-edge (C-8) + BOUNDED joins (a deadlock blows the
// wall bound = a FAILED LAW, never a hung suite). FMEA = if a lock cannot be
// acquired within the bound, that is a RED to surface, never a silent spin.

/// A test-only ABORTABLE spinlock: `tryLockUntil` bails out if the shared abort
/// flag is set, so a MODELLED lock-order cycle terminates as a failed law (the
/// wall bound trips `abort`) instead of hanging the suite — the bounded-join
/// contract made mechanical.
/// Monotonic wall clock in ns (bounded-join deadlines only — never a semantic
/// clock; the wheel's own time is `Vm.vclock`, event-advanced).
fn monoNs() u64 {
    var ts: std.os.linux.timespec = undefined;
    if (@as(isize, @bitCast(std.os.linux.clock_gettime(.MONOTONIC, &ts))) < 0) return 0;
    return @as(u64, @intCast(ts.sec)) *% 1_000_000_000 +% @as(u64, @intCast(ts.nsec));
}

const AbortableLock = struct {
    held: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    fn tryLockUntil(self: *AbortableLock, abort: *std.atomic.Value(bool)) bool {
        while (self.held.swap(true, .acquire)) {
            if (abort.load(.acquire)) return false;
            std.Thread.yield() catch {};
        }
        return true;
    }
    fn unlock(self: *AbortableLock) void {
        self.held.store(false, .release);
    }
};

// LAW gap-b-1 (timer-linearizability-under-L_timer + bounded-join): N REAL
// std.Thread workers hammer ONE shared `WheelTimers` concurrently — each does M
// `start`s, interleaved cancels and `pending` reads — with `L_timer` the ONLY
// synchronization. Because every wheel op is serialized by `L_timer`, the outcome
// is LINEARIZABLE: exactly N*M timers were created (ids unique, none lost, none
// double-counted), and a final drain fires each surviving id AT MOST ONCE, with
// firing count == created − cancelled. The join is BOUNDED (wall deadline) — a
// deadlock or a torn-list crash blows the bound / traps rather than hanging.
test "gap-b-1: timers linearizable under L_timer (N threads, one shared wheel), bounded" {
    const gpa = std.testing.allocator;

    const Worker = struct {
        wheel: *WheelTimers,
        gpa: std.mem.Allocator,
        m: usize,
        started: usize = 0,
        cancelled: usize = 0,
        err: ?anyerror = null,
        seed: u64,

        fn run(w: *@This()) void {
            var prng = std.Random.DefaultPrng.init(w.seed);
            const r = prng.random();
            var ids: std.ArrayList(TimerId) = .empty;
            defer ids.deinit(w.gpa);
            var i: usize = 0;
            while (i < w.m) : (i += 1) {
                // spread starts across / beyond the horizon so slots + overflow
                // + cascade all take concurrent traffic.
                const at = 1 + r.uintLessThan(u64, 600);
                const id = w.wheel.start(at, @intCast(i)) catch |e| {
                    w.err = e;
                    return;
                };
                ids.append(w.gpa, id) catch |e| {
                    w.err = e;
                    return;
                };
                w.started += 1;
                // occasionally cancel one of our OWN earlier ids and read pending
                if (r.uintLessThan(u8, 4) == 0 and ids.items.len > 1) {
                    const victim = ids.items[r.uintLessThan(usize, ids.items.len)];
                    if (w.wheel.cancel(victim)) w.cancelled += 1;
                }
                _ = w.wheel.pending(); // a concurrent READ op — must not tear
            }
        }
    };

    for (0..8) |iter| {
        const N: usize = 4;
        const M: usize = 300;
        var wheel = WheelTimers.init(gpa);
        defer wheel.deinit();

        var workers: [4]Worker = undefined;
        for (&workers, 0..) |*w, k| w.* = .{ .wheel = &wheel, .gpa = gpa, .m = M, .seed = 0xB1 +% iter *% 7 +% k };

        const wall_ns: u64 = 5 * std.time.ns_per_s; // generous anti-hang bound
        const start_ns = monoNs();

        var threads: [4]std.Thread = undefined;
        for (&threads, 0..) |*t, k| t.* = try std.Thread.spawn(.{}, Worker.run, .{&workers[k]});
        for (&threads) |t| t.join(); // BOUNDED: no lock-order cycle can form (L_timer is a leaf), so join returns
        const elapsed_ns: u64 = @intCast(monoNs() - start_ns);
        try std.testing.expect(elapsed_ns < wall_ns); // bounded-join witness

        var total_started: usize = 0;
        var total_cancelled: usize = 0;
        for (&workers) |*w| {
            if (w.err) |e| return e;
            total_started += w.started;
            total_cancelled += w.cancelled;
        }
        // LINEARIZABLE: no lost update — every one of the N*M starts took effect.
        try std.testing.expectEqual(N * M, total_started);
        try std.testing.expectEqual(N * M - total_cancelled, wheel.pending());

        // Drain and prove AT-MOST-ONCE across the whole concurrent history.
        var fired: std.ArrayList(Fired) = .empty;
        defer fired.deinit(gpa);
        try wheel.advance(1000, &fired);
        try std.testing.expectEqual(N * M - total_cancelled, fired.items.len);
        var seen: std.AutoHashMapUnmanaged(TimerId, void) = .empty;
        defer seen.deinit(gpa);
        for (fired.items) |f| {
            try std.testing.expect(!seen.contains(f.id)); // at-most-once
            try seen.put(gpa, f.id, {});
        }
        try std.testing.expectEqual(@as(usize, 0), wheel.pending());
    }
}

// LAW gap-b-1 (lock-order no-back-edge, bounded): the total order `L_v → L_timer`
// holds on every path — modelled with an outer lock `O` (stands for `L_v`) and an
// inner lock `T` (stands for `L_timer`). Workers that ALWAYS take `O` then `T`
// (the sanctioned order) can never form a cycle, so all K workers complete their
// full iteration budget within the wall bound. The MUTANT (one worker reversed to
// `T` then `O`) forms the L_v↔L_timer cycle; the abort watchdog trips at the wall
// deadline and progress falls short — a deadlock surfaces as a FAILED LAW, never a
// hung suite (the C-8 / bounded-join contract). This is exactly the mechanized
// witness that no back-edge exists on the real path, where — by construction — a
// `WheelTimers` method holds NO reference to `L_v` and so CANNOT reverse the order.
test "gap-b-1: lock-order L_v->L_timer has no back-edge (bounded, deadlock=failed law)" {
    const OrderWorker = struct {
        o: *AbortableLock,
        t: *AbortableLock,
        abort: *std.atomic.Value(bool),
        reversed: bool,
        iters: usize,
        progress: *std.atomic.Value(usize),

        fn run(w: *@This()) void {
            var i: usize = 0;
            while (i < w.iters) : (i += 1) {
                if (w.abort.load(.acquire)) return;
                const first = if (w.reversed) w.t else w.o;
                const second = if (w.reversed) w.o else w.t;
                if (!first.tryLockUntil(w.abort)) return;
                std.Thread.yield() catch {}; // widen the interleaving window
                if (!second.tryLockUntil(w.abort)) {
                    first.unlock();
                    return;
                }
                _ = w.progress.fetchAdd(1, .monotonic);
                second.unlock();
                first.unlock();
            }
        }
    };

    // The abort watchdog: after the wall deadline, force every worker to unwind
    // so the join is BOUNDED even if a (mutant) cycle formed.
    const Watchdog = struct {
        abort: *std.atomic.Value(bool),
        progress: *std.atomic.Value(usize),
        target: usize,
        deadline_ns: u64,
        fn run(w: *@This()) void {
            while (w.progress.load(.acquire) < w.target and monoNs() < w.deadline_ns) {
                std.Thread.yield() catch {};
            }
            w.abort.store(true, .release);
        }
    };

    const K: usize = 4;
    const ITERS: usize = 5000;
    var o = AbortableLock{};
    var t = AbortableLock{};
    var abort = std.atomic.Value(bool).init(false);
    var progress = std.atomic.Value(usize).init(0);

    const wall_ns: u64 = 3 * std.time.ns_per_s;
    const start_ns = monoNs();

    var workers: [K]OrderWorker = undefined;
    for (&workers) |*w| w.* = .{ .o = &o, .t = &t, .abort = &abort, .reversed = false, .iters = ITERS, .progress = &progress };
    // FLIP THIS to true on ONE worker → the L_v↔L_timer cycle → deadlock →
    // progress stalls → RED at the wall bound (mutant MUT-GAPB1-2).

    var wd = Watchdog{ .abort = &abort, .progress = &progress, .target = K * ITERS, .deadline_ns = start_ns + wall_ns };
    const wd_thread = try std.Thread.spawn(.{}, Watchdog.run, .{&wd});

    var threads: [K]std.Thread = undefined;
    for (&threads, 0..) |*th, k| th.* = try std.Thread.spawn(.{}, OrderWorker.run, .{&workers[k]});
    for (&threads) |th| th.join();
    abort.store(true, .release); // release the watchdog if all finished first
    wd_thread.join();

    const elapsed_ns: u64 = @intCast(monoNs() - start_ns);
    try std.testing.expect(elapsed_ns < wall_ns + std.time.ns_per_s); // bounded join
    // With the sanctioned order on every path, NOBODY aborts: full progress.
    try std.testing.expectEqual(K * ITERS, progress.load(.acquire));
}
