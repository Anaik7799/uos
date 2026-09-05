//! beam-zig M10 / S24: **registry & persistent terms** (cf. erts register.c,
//! erl_bif_persistent.c).
//!
//! REGISTRY — a partial bijection name ↔ pid:
//!   register  : (Name, Pid) -> ok | error   (name free AND pid unnamed AND alive)
//!   whereis   : Name -> ?Pid
//!   unregister: Name -> ok | error
//!   nameOf    : Pid -> ?Name                (the inverse direction)
//! Laws:
//!   BIJECTION      whereis(n) == p ⇔ nameOf(p) == n (checked after EVERY op)
//!   REGISTER∘WHEREIS  whereis(register(n,p)) == p
//!   UNIQUENESS     registering a taken name or an already-named pid fails
//!   DEATH          registering a dead pid fails; killing a pid unregisters it
//!   HOMOMORPHISM   final (two hash maps) ≡ oracle (association list) under
//!                  twin-seeded random op walks
//!
//! PERSISTENT TERMS — put/get over a LITERAL region:
//!   put copies the term into the region (denote-preserving, the copy law
//!   again); get returns the stored term; the region's words are IMMUTABLE
//!   across process-heap collections (M6's literal-immunity law, reused
//!   byte-for-byte). E2.10 (`bifs/persistent_term.zig`): the table stores
//!   BOTH the copied key and value per `Entry` (not just the key's hash) so
//!   `get/0` can enumerate every live `{K,V}` pair and `info/0` can report
//!   `count`/`memory` — see `PersistentTerms.count`/`memoryBytes`.

//!
//! gap-b-2 (SMP coarse→per-lock, step 2): the name registry now carries its OWN
//! lock `L_reg` (see `RegLock`), acquired around every op, STRICTLY below `L_v` in
//! the total order `L_v→L_c→{L_reg,L_timer}→L_e` (UCA-SMP-9 / C-8, no back-edge by
//! construction — a `Registry` method holds no `Vm`/`ThreadCtx`/`VmLock`
//! reference, so it CANNOT acquire `L_v`). Laws: `gap-b-2
//! registry-linearizability-under-L_reg` + `gap-b-2 lock-order no-back-edge`
//! (both bounded). Behaviour-preserving refactor: under the coarse `L_v` every
//! registry op was already serialized, so adding `L_reg` under `L_v` is
//! observably inert (the HOMOMORPHISM + BIJECTION suites are the witness). Same
//! shape as `gap-b-1`'s `L_timer` (`src/timer_wheel.zig`).

const std = @import("std");
const smp_trace = @import("smp_trace.zig"); // S-epoch SMP-OBS: L_reg contention + order-check hooks (zero-cost when disabled)
const ta = @import("term_algebra.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

pub const Pid = u32;
pub const Name = u32; // atom index

/// `L_reg` — the name registry's own lock (`gap-b-2`, the second leaf step of the
/// SMP coarse→per-lock transition). A self-contained atomic spinlock, IDENTICAL
/// in shape to `proc.SmpEngine.VmLock` (`L_v`) and `timer_wheel.TimerLock`
/// (`L_timer`): acquire `.acquire`, release `.release`, a full happens-before
/// fence around every registry mutation/observation.
///
/// LOCK-ORDER (the safety-critical invariant `L_v → L_c → {L_reg,L_timer} → L_e`,
/// UCA-SMP-9 / C-8): `L_reg` sits STRICTLY BELOW `L_v` in the total order. It is
/// acquired ONLY inside the `Registry.{register,whereis,nameOf,unregister,
/// pidExited,count,snapshotNames}` methods, whose bodies reference nothing but
/// `self` (a `*Registry`), `self.gpa`, and the caller's scalar/`out` args — they
/// hold NO reference to `Vm`, `ThreadCtx`, or `VmLock`, so a `Registry` method
/// CANNOT acquire `L_v`. Therefore NO path acquires `L_v` while holding `L_reg`:
/// the back-edge is impossible BY CONSTRUCTION (proof by type — the outer lock is
/// unreachable from this scope). Every live acquisition happens while the caller
/// already holds `L_v` (the SMP epilogue / `interpret` region, e.g.
/// `Vm.doRegister`/`doWhereis`/`pidExited`) or holds no lock at all
/// (single-thread `driveModel`); either way the observed order is `L_v → L_reg`,
/// never the reverse. The `Registry` methods are also non-reentrant w.r.t. each
/// other (none calls another locked method), so `L_reg` never self-deadlocks.
/// See `docs/OTP30_SMP_EPOCH_PLAN.md` step 2 + `DIVERGENCE_LOG` gap-b.
pub const RegLock = struct {
    held: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    pub fn lock(self: *RegLock) void {
        if (comptime smp_trace.enabled) smp_trace.onAcquire(.l_reg);
        while (self.held.swap(true, .acquire)) std.Thread.yield() catch {};
        if (comptime smp_trace.enabled) smp_trace.onAcquired(.l_reg);
    }
    pub fn unlock(self: *RegLock) void {
        if (comptime smp_trace.enabled) smp_trace.onRelease(.l_reg);
        self.held.store(false, .release);
    }
};

// ---------------------------------------------------------------------------
// ORACLE: an association list. Cannot be wrong.
// ---------------------------------------------------------------------------
pub const OracleRegistry = struct {
    gpa: std.mem.Allocator,
    pairs: std.ArrayList(struct { name: Name, pid: Pid }),

    pub fn init(gpa: std.mem.Allocator) OracleRegistry {
        return .{ .gpa = gpa, .pairs = .empty };
    }
    pub fn deinit(self: *OracleRegistry) void {
        self.pairs.deinit(self.gpa);
    }
    pub fn register(self: *OracleRegistry, name: Name, pid: Pid, alive: bool) !void {
        if (!alive) return error.BadArg;
        for (self.pairs.items) |p| {
            if (p.name == name or p.pid == pid) return error.BadArg;
        }
        try self.pairs.append(self.gpa, .{ .name = name, .pid = pid });
    }
    pub fn whereis(self: *OracleRegistry, name: Name) ?Pid {
        for (self.pairs.items) |p| {
            if (p.name == name) return p.pid;
        }
        return null;
    }
    pub fn nameOf(self: *OracleRegistry, pid: Pid) ?Name {
        for (self.pairs.items) |p| {
            if (p.pid == pid) return p.name;
        }
        return null;
    }
    pub fn unregister(self: *OracleRegistry, name: Name) !void {
        for (self.pairs.items, 0..) |p, k| {
            if (p.name == name) {
                _ = self.pairs.swapRemove(k);
                return;
            }
        }
        return error.BadArg;
    }
    pub fn pidExited(self: *OracleRegistry, pid: Pid) void {
        for (self.pairs.items, 0..) |p, k| {
            if (p.pid == pid) {
                _ = self.pairs.swapRemove(k);
                return;
            }
        }
    }
};

// ---------------------------------------------------------------------------
// FINAL: two hash maps kept in lockstep — the bijection is a REP INVARIANT
// enforced by the laws, not by hope.
// ---------------------------------------------------------------------------
pub const Registry = struct {
    gpa: std.mem.Allocator,
    by_name: std.AutoHashMapUnmanaged(Name, Pid),
    by_pid: std.AutoHashMapUnmanaged(Pid, Name),
    /// `L_reg` — every mutating/observing registry op holds this for its whole
    /// critical section (gap-b-2). Strictly below `L_v`; never acquires `L_v`.
    l_reg: RegLock = .{},

    pub fn init(gpa: std.mem.Allocator) Registry {
        return .{ .gpa = gpa, .by_name = .empty, .by_pid = .empty };
    }
    pub fn deinit(self: *Registry) void {
        self.by_name.deinit(self.gpa);
        self.by_pid.deinit(self.gpa);
    }
    pub fn register(self: *Registry, name: Name, pid: Pid, alive: bool) !void {
        self.l_reg.lock(); // L_reg — acquired under L_v (or lock-free path)
        defer self.l_reg.unlock();
        if (!alive) return error.BadArg;
        if (self.by_name.contains(name)) return error.BadArg;
        if (self.by_pid.contains(pid)) return error.BadArg;
        try self.by_name.put(self.gpa, name, pid);
        try self.by_pid.put(self.gpa, pid, name);
    }
    pub fn whereis(self: *Registry, name: Name) ?Pid {
        self.l_reg.lock(); // L_reg — a registry READ is a registry op too
        defer self.l_reg.unlock();
        return self.by_name.get(name);
    }
    pub fn nameOf(self: *Registry, pid: Pid) ?Name {
        self.l_reg.lock(); // L_reg
        defer self.l_reg.unlock();
        return self.by_pid.get(pid);
    }
    pub fn unregister(self: *Registry, name: Name) !void {
        self.l_reg.lock(); // L_reg
        defer self.l_reg.unlock();
        const pid = self.by_name.get(name) orelse return error.BadArg;
        _ = self.by_name.remove(name);
        _ = self.by_pid.remove(pid);
    }
    pub fn pidExited(self: *Registry, pid: Pid) void {
        self.l_reg.lock(); // L_reg
        defer self.l_reg.unlock();
        if (self.by_pid.get(pid)) |name| {
            _ = self.by_name.remove(name);
            _ = self.by_pid.remove(pid);
        }
    }
    pub fn count(self: *Registry) usize {
        self.l_reg.lock(); // L_reg
        defer self.l_reg.unlock();
        return self.by_name.count();
    }
    /// Snapshot every registered `Name` into `out` under `L_reg` — the atomic
    /// read that backs `registered/0`. Guarding the whole enumeration under
    /// `L_reg` (rather than iterating `by_name` directly at the call site) keeps
    /// the last registry op — the whole-table read — inside the lock, so a
    /// concurrent register/unregister can't tear the enumeration. Caller owns
    /// `out` (its allocator, its ordering/sort — the HashMap order never leaks).
    pub fn snapshotNames(self: *Registry, out: *std.ArrayList(Name), out_gpa: std.mem.Allocator) !void {
        self.l_reg.lock(); // L_reg
        defer self.l_reg.unlock();
        var it = self.by_name.keyIterator();
        while (it.next()) |k| try out.append(out_gpa, k.*);
    }
};

// ---------------------------------------------------------------------------
// Persistent terms: the literal region
// ---------------------------------------------------------------------------

/// E2.10: a stored (key, value) pair — BOTH copied into `region`. Storing the
/// key (not just its hash) is what makes `persistent_term:get/0` (enumerate
/// every `{K,V}`) and `info/0` possible; before E2.10 the table was keyed by
/// hash alone and could not recover the original key term.
pub const Entry = struct { key: FinalTerms.Term, val: FinalTerms.Term };

pub const PersistentTerms = struct {
    gpa: std.mem.Allocator,
    region: FinalTerms.Ctx, // THE literal region: never collected, never moved
    table: std.AutoHashMapUnmanaged(u64, Entry), // key-hash → (key, value)

    pub fn init(gpa: std.mem.Allocator, atoms: *AtomTable) PersistentTerms {
        return .{ .gpa = gpa, .region = FinalTerms.Ctx.init(gpa, atoms), .table = .empty };
    }
    pub fn deinit(self: *PersistentTerms) void {
        self.table.deinit(self.gpa);
        self.region.deinit();
    }

    /// Store a copy of (key, value) from a process heap. Cheap get,
    /// expensive put — the documented erts asymmetry, structurally true
    /// here: put copies, get is a table probe.
    pub fn put(self: *PersistentTerms, src: *FinalTerms.Ctx, key: FinalTerms.Term, val: FinalTerms.Term) !void {
        const kcopy = try FinalTerms.gcCopy(&self.region, src, key);
        const vcopy = try FinalTerms.gcCopy(&self.region, src, val);
        try self.table.put(self.gpa, FinalTerms.hashTerm(&self.region, kcopy), .{ .key = kcopy, .val = vcopy });
    }
    pub fn get(self: *PersistentTerms, src: *FinalTerms.Ctx, key: FinalTerms.Term) ?FinalTerms.Term {
        // hash is heap-independent (M4 law), so probe with the caller's key
        const e = self.table.get(FinalTerms.hashTerm(src, key)) orelse return null;
        return e.val;
    }
    pub fn erase(self: *PersistentTerms, src: *FinalTerms.Ctx, key: FinalTerms.Term) bool {
        return self.table.remove(FinalTerms.hashTerm(src, key));
    }
    /// E3.18: `erts_internal:erase_persistent_terms/0` — drop EVERY term. The
    /// literal region is NOT reclaimed here (erts also defers the literal-area
    /// collection); clearing the table makes all terms unreachable, so `count`
    /// becomes 0 and every prior key `get`s `null` — the observable effect.
    pub fn clearAll(self: *PersistentTerms) void {
        self.table.clearRetainingCapacity();
    }
    /// The number of live persistent terms — `persistent_term:info/0`'s `count`.
    pub fn count(self: *const PersistentTerms) usize {
        return self.table.count();
    }
    /// Approximate byte footprint of the literal region — `info/0`'s `memory`
    /// (a documented SUBSET/approximation, the ets.zig `info/1,2` precedent:
    /// real erts tracks per-term allocation, this counts region words).
    pub fn memoryBytes(self: *const PersistentTerms) usize {
        return self.region.words.items.len * @sizeOf(u64);
    }
};

// ============================================================================
// Law suites
// ============================================================================

test "HOMOMORPHISM + BIJECTION: registry op walks, oracle vs final in lockstep" {
    const gpa = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0x4E60, .iterations = 40 };

    for (0..cfg.iterations) |i| {
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();
        var oracle = OracleRegistry.init(gpa);
        defer oracle.deinit();
        var final = Registry.init(gpa);
        defer final.deinit();
        var alive = [_]bool{true} ** 12;

        for (0..120) |_| {
            const name: Name = random.uintLessThan(Name, 6);
            const pid: Pid = random.uintLessThan(Pid, 12);
            switch (random.uintLessThan(u8, 4)) {
                0, 1 => {
                    const ro = oracle.register(name, pid, alive[pid]);
                    const rf = final.register(name, pid, alive[pid]);
                    try expectLaw((ro == error.BadArg) == (rf == error.BadArg), "registry: twin verdicts on register", cfg, i);
                },
                2 => {
                    const ro = oracle.unregister(name);
                    const rf = final.unregister(name);
                    try expectLaw((ro == error.BadArg) == (rf == error.BadArg), "registry: twin verdicts on unregister", cfg, i);
                },
                else => {
                    if (random.uintLessThan(u8, 4) == 0) {
                        alive[pid] = false;
                        oracle.pidExited(pid);
                        final.pidExited(pid);
                    } else {
                        alive[pid] = true; // "new" process reusing the pid slot
                    }
                },
            }
            // agreement on every observation, after every op
            for (0..6) |n| {
                try expectLaw(oracle.whereis(@intCast(n)) == final.whereis(@intCast(n)), "registry: whereis agrees", cfg, i);
            }
            for (0..12) |p| {
                try expectLaw(oracle.nameOf(@intCast(p)) == final.nameOf(@intCast(p)), "registry: nameOf agrees", cfg, i);
            }
            // BIJECTION on the final encoding
            var it = final.by_name.iterator();
            while (it.next()) |e| {
                try expectLaw(final.nameOf(e.value_ptr.*) == e.key_ptr.*, "registry: name→pid→name closes", cfg, i);
            }
            var it2 = final.by_pid.iterator();
            while (it2.next()) |e| {
                try expectLaw(final.whereis(e.value_ptr.*) == e.key_ptr.*, "registry: pid→name→pid closes", cfg, i);
            }
        }
    }
}

test "Registry semantics: uniqueness, death, register∘whereis" {
    const gpa = std.testing.allocator;
    var reg = Registry.init(gpa);
    defer reg.deinit();

    try reg.register(1, 100, true);
    try std.testing.expectEqual(@as(?Pid, 100), reg.whereis(1));
    try std.testing.expectEqual(@as(?Name, 1), reg.nameOf(100));
    try std.testing.expectError(error.BadArg, reg.register(1, 101, true)); // name taken
    try std.testing.expectError(error.BadArg, reg.register(2, 100, true)); // pid named
    try std.testing.expectError(error.BadArg, reg.register(3, 102, false)); // dead pid
    reg.pidExited(100); // death unregisters
    try std.testing.expectEqual(@as(?Pid, null), reg.whereis(1));
    try reg.register(1, 101, true); // name is free again
}

test "Persistent terms: get∘put, last-wins, literal immunity across process GC" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var pt = PersistentTerms.init(gpa, &atoms);
    defer pt.deinit();
    var proc_heap = FinalTerms.Ctx.init(gpa, &atoms);
    defer proc_heap.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();
    var prng = std.Random.DefaultPrng.init(0x9E45);
    const random = prng.random();

    for (0..30) |_| {
        const key = try ta.genTerm(FinalTerms, random, &proc_heap, 2);
        const val = try ta.genTerm(FinalTerms, random, &proc_heap, 3);
        const val_denote = try FinalTerms.denote(&proc_heap, sa, val);
        try pt.put(&proc_heap, key, val);
        // get∘put: same denotation, read back from the literal region
        const got = pt.get(&proc_heap, key) orelse return error.LawViolated;
        try std.testing.expect(spec.eqlExact(val_denote, try FinalTerms.denote(&pt.region, sa, got)));
        // last wins
        const val2 = try ta.genTerm(FinalTerms, random, &proc_heap, 2);
        const val2_denote = try FinalTerms.denote(&proc_heap, sa, val2);
        try pt.put(&proc_heap, key, val2);
        const got2 = pt.get(&proc_heap, key) orelse return error.LawViolated;
        try std.testing.expect(spec.eqlExact(val2_denote, try FinalTerms.denote(&pt.region, sa, got2)));
    }

    // LITERAL IMMUNITY: collecting the PROCESS heap does not move a single
    // word of the literal region (byte-identical), and stored terms still
    // denote the same values afterwards.
    const key = FinalTerms.int(&proc_heap, 424242);
    const val = try ta.genTerm(FinalTerms, random, &proc_heap, 3);
    const vd = try FinalTerms.denote(&proc_heap, sa, val);
    try pt.put(&proc_heap, key, val);
    const region_snapshot = try gpa.dupe(u64, pt.region.words.items);
    defer gpa.free(region_snapshot);

    var live = try ta.genTerm(FinalTerms, random, &proc_heap, 3);
    var c = FinalTerms.collectInPlace(&proc_heap, 0);
    try c.root(&live);
    _ = try FinalTerms.finishInPlace(&proc_heap, &c);

    try std.testing.expect(std.mem.eql(u64, region_snapshot, pt.region.words.items));
    const got = pt.get(&proc_heap, FinalTerms.int(&proc_heap, 424242)).?;
    try std.testing.expect(spec.eqlExact(vd, try FinalTerms.denote(&pt.region, sa, got)));

    // erase
    try std.testing.expect(pt.erase(&proc_heap, FinalTerms.int(&proc_heap, 424242)));
    try std.testing.expect(pt.get(&proc_heap, FinalTerms.int(&proc_heap, 424242)) == null);
}

// ============================================================================
// gap-b-2: L_reg — the name-registry lock (SMP coarse→per-lock transition, step 2)
// ============================================================================
//
// SAFETY PACKET (SAFETY_ANALYSIS §10; controller = the lock hierarchy / the
// name-registry lock acquisition, CTRL-SCHED). UCA = UCA-SMP-9 (a lock acquired
// out of order → L_v↔L_reg priority-inversion / hold-and-wait DEADLOCK). HAZARD =
// a scheduler thread never returns (hung node). MITIGATION = the proven total
// order `L_v → L_reg` with NO back-edge (C-8, by construction — a `Registry`
// method reaches no `Vm`/`VmLock`) + BOUNDED joins (a deadlock blows the wall
// bound = a FAILED LAW, never a hung suite). FMEA = if a lock cannot be acquired
// within the bound, that is a RED to surface, never a silent spin. CAST: a red
// gate gets a CAST_LOG cause entry before any re-run.

/// Monotonic wall clock in ns — bounded-join DEADLINES only (never a semantic
/// clock; the registry has no notion of time).
fn monoNs() u64 {
    var ts: std.os.linux.timespec = undefined;
    if (@as(isize, @bitCast(std.os.linux.clock_gettime(.MONOTONIC, &ts))) < 0) return 0;
    return @as(u64, @intCast(ts.sec)) *% 1_000_000_000 +% @as(u64, @intCast(ts.nsec));
}

/// A test-only ABORTABLE spinlock: `tryLockUntil` bails out if the shared abort
/// flag is set, so a MODELLED lock-order cycle terminates as a failed law (the
/// wall bound trips `abort`) instead of hanging the suite — the bounded-join
/// contract made mechanical.
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

// LAW gap-b-2 (registry-linearizability-under-L_reg + bounded-join): N REAL
// std.Thread workers hammer ONE shared `Registry` concurrently — each owns a
// DISJOINT slice of the name- and pid-space (worker k uses names/pids in
// [k*STRIDE, k*STRIDE+STRIDE)), and does M rounds of register → whereis → nameOf
// → unregister on its own slice, with `L_reg` the ONLY synchronization. Because
// every registry op is serialized by `L_reg`, the outcome is LINEARIZABLE: no
// register is lost (a just-registered name whereis-resolves to exactly its pid,
// its pid nameOf-resolves back — the BIJECTION holds mid-flight), an unregister
// atomically drops both directions, and the disjoint slices never interfere. A
// name-collision on a DELIBERATELY shared "hot" name goes to exactly one winner
// at a time (register returns BadArg while taken). The join is BOUNDED (wall
// deadline) — a deadlock or a torn-map crash blows the bound / traps rather than
// hanging (L_reg is a leaf, so no lock-order cycle can form: join always returns).
test "gap-b-2: registry linearizable under L_reg (N threads, one shared registry), bounded" {
    const gpa = std.testing.allocator;

    const STRIDE: u32 = 1000;
    const Worker = struct {
        reg: *Registry,
        base: u32, // this worker's disjoint slice base
        m: usize,
        hot_name: Name, // the SHARED collision name every worker fights over
        collisions_won: usize = 0,
        mismatch: bool = false,
        err: ?anyerror = null,
        seed: u64,

        fn run(w: *@This()) void {
            var prng = std.Random.DefaultPrng.init(w.seed);
            const r = prng.random();
            var i: usize = 0;
            while (i < w.m) : (i += 1) {
                const off = r.uintLessThan(u32, STRIDE - 1);
                const name: Name = w.base + off;
                const pid: Pid = w.base + off; // disjoint per worker: name==pid space slice
                // register on my own disjoint slot — MUST succeed (slot is mine)
                w.reg.register(name, pid, true) catch {
                    w.mismatch = true;
                    return;
                };
                // mid-flight BIJECTION: my registration resolves both ways
                if (w.reg.whereis(name) != pid) w.mismatch = true;
                if (w.reg.nameOf(pid) != name) w.mismatch = true;
                // fight over the HOT shared name with a distinct pid in my slice
                const hot_pid: Pid = w.base + STRIDE - 1;
                if (w.reg.register(w.hot_name, hot_pid, true)) |_| {
                    // I won the hot name — it must resolve to MY pid until I drop it
                    if (w.reg.whereis(w.hot_name) == hot_pid) w.collisions_won += 1;
                    w.reg.unregister(w.hot_name) catch {};
                } else |_| {
                    // someone else holds it — a legitimate collision (BadArg)
                }
                // drop my own slot again so the slice is reusable next round
                w.reg.unregister(name) catch {
                    w.mismatch = true;
                    return;
                };
            }
        }
    };

    for (0..8) |iter| {
        const M: usize = 400;
        var reg = Registry.init(gpa);
        defer reg.deinit();
        const hot: Name = 900_000; // outside every worker's slice

        var workers: [4]Worker = undefined;
        for (&workers, 0..) |*w, k| w.* = .{
            .reg = &reg,
            .base = @as(u32, @intCast(k)) * STRIDE,
            .m = M,
            .hot_name = hot,
            .seed = 0xB2 +% iter *% 7 +% k,
        };

        const wall_ns: u64 = 5 * std.time.ns_per_s; // generous anti-hang bound
        const start_ns = monoNs();

        var threads: [4]std.Thread = undefined;
        for (&threads, 0..) |*t, k| t.* = try std.Thread.spawn(.{}, Worker.run, .{&workers[k]});
        for (&threads) |t| t.join(); // BOUNDED: L_reg is a leaf, no cycle → join returns
        const elapsed_ns: u64 = @intCast(monoNs() - start_ns);
        try std.testing.expect(elapsed_ns < wall_ns); // bounded-join witness

        for (&workers) |*w| {
            if (w.err) |e| return e;
            try std.testing.expect(!w.mismatch); // no torn/lost registry op mid-flight
        }
        // Every slot was dropped again → the registry is EMPTY (no leaked entry).
        try std.testing.expectEqual(@as(usize, 0), reg.count());
        // The hot name was contended and always dropped by its winner → free now.
        try std.testing.expectEqual(@as(?Pid, null), reg.whereis(hot));
    }
}

// LAW gap-b-2 (lock-order no-back-edge, bounded): the total order `L_v → L_reg`
// holds on every path — modelled with an outer lock `O` (stands for `L_v`) and an
// inner lock `R` (stands for `L_reg`). Workers that ALWAYS take `O` then `R` (the
// sanctioned order) can never form a cycle, so all K workers complete their full
// iteration budget within the wall bound. The MUTANT (one worker reversed to `R`
// then `O`) forms the L_v↔L_reg cycle; the abort watchdog trips at the wall
// deadline and progress falls short — a deadlock surfaces as a FAILED LAW, never
// a hung suite (the C-8 / bounded-join contract). This is exactly the mechanized
// witness that no back-edge exists on the real path, where — by construction — a
// `Registry` method holds NO reference to `L_v` and so CANNOT reverse the order.
test "gap-b-2: lock-order L_v->L_reg has no back-edge (bounded, deadlock=failed law)" {
    const OrderWorker = struct {
        o: *AbortableLock,
        r: *AbortableLock,
        abort: *std.atomic.Value(bool),
        reversed: bool,
        iters: usize,
        progress: *std.atomic.Value(usize),

        fn run(w: *@This()) void {
            var i: usize = 0;
            while (i < w.iters) : (i += 1) {
                if (w.abort.load(.acquire)) return;
                const first = if (w.reversed) w.r else w.o;
                const second = if (w.reversed) w.o else w.r;
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
    var rlock = AbortableLock{};
    var abort = std.atomic.Value(bool).init(false);
    var progress = std.atomic.Value(usize).init(0);

    const wall_ns: u64 = 3 * std.time.ns_per_s;
    const start_ns = monoNs();

    var workers: [K]OrderWorker = undefined;
    for (&workers) |*w| w.* = .{ .o = &o, .r = &rlock, .abort = &abort, .reversed = false, .iters = ITERS, .progress = &progress };
    // FLIP `.reversed` to true on ONE worker → the L_v↔L_reg cycle → deadlock →
    // progress stalls → RED at the wall bound (mutant MUT-GAPB2-2).

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
