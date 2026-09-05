//! # substrate/sched — Real[Sched]: the SECOND HOST-touching substrate handler (E34-T2)
//!
//! ## Stratum
//! The FINAL encoding of the `Sched` domain — the second `Real` handler of the
//! E-substrate program (`docs/STRATUM_C_DESIGN.md` §3.2/§11.2/§13.2/§14 T-2),
//! following `Real[Alloc]` (E33-T1). Where `alloc.zig` proved the observation
//! quotient for MEMORY, this proves it for CONCURRENCY: the `Sched` effect
//! (`spawn`/`send`/`recv`/`yield`/`exit`) interpreted by a REAL per-core run-queue
//! (a mutable ring-buffer deque + a reduction counter — the Chase–Lev local-end
//! stand-in) is OBSERVED-identical to a pure oracle whose run-queue is a
//! persistent Okasaki functional queue. Nothing in the VM depends on it; `vm_all`
//! pulls it for its law suite only.
//!
//! ## What it proves
//! The design's scheduler homomorphism Φ, discharged for a real host kernel:
//! `observe(Real.run(p)) == observe(Model.run(p))` for a seeded process family.
//! The RESIDUE — physical pid values, real-time queue storage (ring vs functional
//! list), the reduction counter — is erased by `observe` (pid → SPAWN ORDINAL,
//! exactly as `alloc` renamed handle → allocation ordinal). A mutable ring-buffer
//! runtime and a persistent-queue oracle denote the same message/exit trace.
//!
//! ## Signature (Σ_Sched) and semantic domain
//!   `SchedOp = spawn(seed) | send(to,msg) | recv | yield | exit`. A PROCESS is a
//!   defunctionalized-CPS step machine (T-5, as in `effect.zig`): one shared
//!   `schedStep` interprets a `ProcState` (role + progress), receiving the prior
//!   op's result and yielding the next op. The SCHEDULE is single-core round-robin
//!   COOPERATIVE: a process runs a contiguous burst until it blocks on an empty
//!   `recv`, `yield`s, or `exit`s. Both Model and Real use this IDENTICAL policy;
//!   they differ only in the run-queue's CARRIER (persistent Okasaki queue vs
//!   mutable ring) — the homomorphism's whole point.
//!
//! ## Laws
//!   HOMOMORPHISM   `observe(Real.run(p)) == observe(Model.run(p))` over a seeded
//!                  process family (discharges Φ for a real per-core run-queue).
//!   QUOTIENT       `observe` is invariant to the physical pid supply (root pid
//!                  base 0 vs 1000) — pid→ordinal α-renaming is a real quotient.
//!   PERSISTENCE    a mid-run snapshot of the Model's functional run-queue denotes
//!                  the same pid sequence after later enqueues/dequeues (structural
//!                  sharing, never aliasing) — the Okasaki queue is a VALUE.
//!   FIFO           a process's mailbox delivers messages in arrival order; the
//!                  fan-out reply accumulator is deterministic.
//!   FAIL-CLOSED    send to an unknown/dead pid fails CLOSED (BadPid); a step after
//!                  `exit` is unreachable (the process is terminal); an unsatisfiable
//!                  `recv` leaves the process BLOCKED and the run terminates (a
//!                  bounded deadlock, never a hang) — the affine/liveness discipline.
//!
//! ## Scope limits (documented, honest)
//! SINGLE-CORE, ONE deterministic schedule (round-robin cooperative). The
//! cross-quantum happens-before quotient (reduction-preemption at quantum R
//! changing interleaving but not the causal message order), the Chase–Lev
//! CROSS-core steal + the erts `check_balance` migration pass, the 4-priority
//! queues, and the dirty-scheduler pool are NAMED successor slices (§13.2), each a
//! gap with an owner, not a silent one. The point of THIS slice is the second host
//! kernel under the same observation law, not the full parallel runtime.

const std = @import("std");

// ── Σ_Sched: the effect signature ──────────────────────────────────────────

pub const Pid = u32;

pub const Role = enum { root, echo };

/// A process's initial behavior seed (what `spawn` carries). Defunctionalized:
/// the child's continuation is DATA (`role` + parameters), not a closure.
pub const ProcSeed = struct {
    role: Role,
    parent: Pid = 0, // echo: whom to reply to
    n: u32 = 0, //      root: number of children to fan out
    base: u64 = 0, //   root: base reply value
};

pub const SchedOp = union(enum) {
    spawn: ProcSeed,
    send: struct { to: Pid, msg: u64 },
    recv,
    yield,
    exit,
};

pub const SchedResult = union(enum) {
    pid: Pid, // spawn result
    msg: u64, // recv result
    unit, //    send/yield result
};

// ── the process behavior (one shared defunctionalized interpreter) ─────────

/// Full mutable process state: the seed plus progress counters + the collected
/// child pids and reply accumulator. `phase`/`i` drive the small per-role state
/// machine; `my` is threaded in by the scheduler (a process knows its own pid).
pub const ProcState = struct {
    role: Role,
    parent: Pid = 0,
    n: u32 = 0,
    base: u64 = 0,
    phase: u8 = 0,
    i: u32 = 0,
    children: [8]Pid = undefined,
    n_children: u32 = 0,
    got: u32 = 0,
    acc: u64 = 0,

    fn fromSeed(seed: ProcSeed) ProcState {
        return .{ .role = seed.role, .parent = seed.parent, .n = seed.n, .base = seed.base };
    }
};

/// One op per call; consumes the prior op's result. Total over the role state
/// machines; `null` = the process is done (⇒ exit). `my` is the caller's pid.
///
///   echo:  recv v → send parent (v+1) → exit
///   root:  spawn n echo children → send child_i (base+i) → recv n replies → exit
fn schedStep(s: *ProcState, my: Pid, prev: ?SchedResult) ?SchedOp {
    switch (s.role) {
        .echo => {
            defer s.phase += 1;
            return switch (s.phase) {
                0 => .recv,
                1 => .{ .send = .{ .to = s.parent, .msg = (prev.?.msg) +% 1 } },
                2 => .exit,
                else => null,
            };
        },
        .root => switch (s.phase) {
            0 => { // fan-out spawn: record the just-spawned child, spawn the next
                if (prev) |p| switch (p) {
                    .pid => |cp| {
                        if (s.n_children < s.children.len) {
                            s.children[s.n_children] = cp;
                            s.n_children += 1;
                        }
                    },
                    else => {},
                };
                if (s.i < s.n) {
                    s.i += 1;
                    return .{ .spawn = .{ .role = .echo, .parent = my } };
                }
                s.phase = 1;
                s.i = 0;
                return schedStep(s, my, null);
            },
            1 => { // send each child its value
                if (s.i < s.n_children) {
                    const c = s.children[s.i];
                    const v = s.base +% s.i;
                    s.i += 1;
                    return .{ .send = .{ .to = c, .msg = v } };
                }
                s.phase = 2;
                s.i = 0;
                return schedStep(s, my, null);
            },
            2 => { // collect the replies (FIFO into the accumulator)
                if (prev) |p| switch (p) {
                    .msg => |m| {
                        s.acc +%= m;
                        s.got += 1;
                    },
                    else => {},
                };
                if (s.got < s.n_children) return .recv;
                s.phase = 3;
                return .exit;
            },
            else => return null,
        },
    }
}

// ── the observed trace (the quotient q) ────────────────────────────────────

pub const SchedTag = enum { spawn, send, recv, exit };

/// One observed event. `actor`/`peer` are SPAWN ORDINALS (α-renamed), never
/// physical pid values — the residue erased by `observe`. Real-time interleaving
/// is quotiented to the deterministic schedule order (the event sequence itself).
pub const SchedEvent = struct {
    tag: SchedTag,
    actor: u64, //  the acting process's ordinal
    peer: u64, //   spawn: child ordinal; send: target ordinal; else 0
    val: u64, //    send/recv: message value; else 0
};

pub fn tracesEqual(a: []const SchedEvent, b: []const SchedEvent) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x.tag != y.tag or x.actor != y.actor or x.peer != y.peer or x.val != y.val) return false;
    }
    return true;
}

pub const Caps = struct { sched: bool = true };

pub const SchedError = error{ OutOfMemory, CapabilityAbsent, BadPid, Deadlock };

// ── the persistent Okasaki run-queue (the Model's carrier — a VALUE) ────────

const QNode = struct { pid: Pid, next: ?*const QNode };

/// A persistent functional queue (front list in order + back list reversed) —
/// amortized O(1) ends, O(1) snapshot (struct copy; nodes shared). Nodes are
/// arena-owned; a push/pop SHARES the untouched spine (PERSISTENCE law's subject).
pub const FQueue = struct {
    front: ?*const QNode = null,
    back: ?*const QNode = null,
    len: u32 = 0,

    fn push(a: std.mem.Allocator, q: FQueue, pid: Pid) error{OutOfMemory}!FQueue {
        const node = try a.create(QNode);
        node.* = .{ .pid = pid, .next = q.back };
        return .{ .front = q.front, .back = node, .len = q.len + 1 };
    }

    /// Pop the front pid; returns the pid + the residual queue (structurally
    /// shared). When `front` is empty, reverse `back` into a fresh `front`
    /// (persistent — allocates the reversed spine, leaving the old queue intact).
    fn pop(a: std.mem.Allocator, q: FQueue) error{OutOfMemory}!?struct { pid: Pid, rest: FQueue } {
        if (q.len == 0) return null;
        if (q.front) |f| {
            return .{ .pid = f.pid, .rest = .{ .front = f.next, .back = q.back, .len = q.len - 1 } };
        }
        // reverse back → front (fresh nodes; old queue untouched)
        var rev: ?*const QNode = null;
        var cur = q.back;
        while (cur) |c| : (cur = c.next) {
            const node = try a.create(QNode);
            node.* = .{ .pid = c.pid, .next = rev };
            rev = node;
        }
        const head = rev.?;
        return .{ .pid = head.pid, .rest = .{ .front = head.next, .back = null, .len = q.len - 1 } };
    }

    fn snapshot(self: FQueue) FQueue {
        return self; // O(1): spine shared
    }
};

/// Denote a queue as its pid sequence (test observation; front-to-back order).
fn qToList(gpa: std.mem.Allocator, q: FQueue) error{OutOfMemory}![]Pid {
    var out: std.ArrayList(Pid) = .empty;
    errdefer out.deinit(gpa);
    var cur = q.front;
    while (cur) |c| : (cur = c.next) try out.append(gpa, c.pid);
    // back list is reversed: append in reverse
    var stack: std.ArrayList(Pid) = .empty;
    defer stack.deinit(gpa);
    cur = q.back;
    while (cur) |c| : (cur = c.next) try stack.append(gpa, c.pid);
    var i = stack.items.len;
    while (i > 0) : (i -= 1) try out.append(gpa, stack.items[i - 1]);
    return out.toOwnedSlice(gpa);
}

// ── a process slot (shared by Model and Real; carriers differ, not the FSM) ─

const Proc = struct {
    state: ProcState,
    ord: u64, //          spawn ordinal — what observe() renames pids to
    mailbox: std.ArrayList(u64) = .empty,
    mcursor: usize = 0, // FIFO read cursor
    alive: bool = true,
    blocked: bool = false, // parked on an empty recv
    // the pending op emitted before blocking (null unless mid-recv)
};

const STEP_CAP: u32 = 100_000; // bounded driver: exceeding it is a failed law (a hang)

// ── shared scheduler mechanics over a pid→Proc table ────────────────────────

const Table = struct {
    gpa: std.mem.Allocator,
    procs: std.ArrayList(Proc) = .empty, // indexed by (pid - base)
    base: Pid,
    next_pid: Pid,
    n_spawn: u64 = 0, // ordinal supply (root = 0)
    trace: std.ArrayList(SchedEvent) = .empty,
    reds: u64 = 0, // the Real reduction counter (residue; Model leaves it 0)

    fn slot(self: *Table, pid: Pid) ?*Proc {
        if (pid < self.base) return null;
        const idx = pid - self.base;
        if (idx >= self.procs.items.len) return null;
        return &self.procs.items[idx];
    }

    fn ordOf(self: *Table, pid: Pid) SchedError!u64 {
        const p = self.slot(pid) orelse return error.BadPid;
        return p.ord;
    }

    fn spawn(self: *Table, seed: ProcSeed) SchedError!Pid {
        const pid = self.next_pid;
        self.next_pid += 1;
        const ord = self.n_spawn;
        self.n_spawn += 1;
        try self.procs.append(self.gpa, .{ .state = ProcState.fromSeed(seed), .ord = ord });
        return pid;
    }

    fn deinit(self: *Table) void {
        for (self.procs.items) |*p| p.mailbox.deinit(self.gpa);
        self.procs.deinit(self.gpa);
        self.trace.deinit(self.gpa);
    }
};

/// Run one process's contiguous burst: keep stepping until it blocks on an empty
/// recv (→ returns .blocked, do not requeue), yields/exits/finishes (→ .done_or_
/// yield, requeue only on yield). `woken` newly-runnable pids are appended to
/// `wake`. Emits observed events into `t.trace`. Shared by both interpreters.
const BurstOutcome = enum { blocked, exited, yielded };

fn runBurst(t: *Table, pid: Pid, wake: *std.ArrayList(Pid)) SchedError!BurstOutcome {
    var prev: ?SchedResult = null;
    while (true) {
        // Re-fetch `p` EACH iteration: a `spawn` appends to `t.procs`, which can
        // REALLOCATE the backing slice and dangle any held `*Proc` (the crash a
        // naive hoist causes). `my_ord` is captured before any in-iteration append.
        const p = t.slot(pid).?;
        const my_ord = p.ord;
        t.reds += 1;
        const op = schedStep(&p.state, pid, prev) orelse {
            // step returned null ⇒ the process is done: treat as exit.
            p.alive = false;
            try t.trace.append(t.gpa, .{ .tag = .exit, .actor = my_ord, .peer = 0, .val = 0 });
            return .exited;
        };
        switch (op) {
            .spawn => |seed| {
                const cp = try t.spawn(seed); // may realloc t.procs — `p` now dangling
                const cord = (t.slot(cp).?).ord;
                try t.trace.append(t.gpa, .{ .tag = .spawn, .actor = my_ord, .peer = cord, .val = 0 });
                try wake.append(t.gpa, cp); // the child is runnable
                prev = .{ .pid = cp };
            },
            .send => |sd| {
                const target = t.slot(sd.to) orelse return error.BadPid;
                if (!target.alive) return error.BadPid; // send to a dead pid fails closed
                try target.mailbox.append(t.gpa, sd.msg);
                try t.trace.append(t.gpa, .{ .tag = .send, .actor = p.ord, .peer = target.ord, .val = sd.msg });
                if (target.blocked) {
                    target.blocked = false;
                    try wake.append(t.gpa, sd.to); // delivery wakes the blocked receiver
                }
                prev = .unit;
            },
            .recv => {
                if (p.mcursor < p.mailbox.items.len) {
                    const m = p.mailbox.items[p.mcursor];
                    p.mcursor += 1;
                    try t.trace.append(t.gpa, .{ .tag = .recv, .actor = p.ord, .peer = 0, .val = m });
                    prev = .{ .msg = m }; // satisfied in-burst; keep running
                } else {
                    p.blocked = true; // park; a future send wakes us
                    return .blocked;
                }
            },
            .yield => {
                prev = .unit;
                return .yielded;
            },
            .exit => {
                p.alive = false;
                try t.trace.append(t.gpa, .{ .tag = .exit, .actor = p.ord, .peer = 0, .val = 0 });
                return .exited;
            },
        }
    }
}

// ── the Model: run-queue = persistent Okasaki functional queue ──────────────

pub const RunOut = struct {
    trace: std.ArrayList(SchedEvent),
    reds: u64,
    fn deinit(self: *RunOut, gpa: std.mem.Allocator) void {
        self.trace.deinit(gpa);
    }
};

/// The ORACLE. Scheduling state is a persistent `FQueue` value threaded through
/// the loop; each dequeue produces a fresh queue sharing the old spine. `arena`
/// owns the queue nodes. `root_base` is the physical pid supply origin (QUOTIENT
/// varies it). Obviously-correct: round-robin cooperative, one burst per turn.
pub fn runModel(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    caps: Caps,
    root_base: Pid,
    root_seed: ProcSeed,
) SchedError!RunOut {
    if (!caps.sched) return error.CapabilityAbsent;
    var t = Table{ .gpa = gpa, .base = root_base, .next_pid = root_base };
    defer t.deinit();
    _ = try t.spawn(root_seed); // root: ordinal 0, pid root_base

    var q = FQueue{};
    q = try FQueue.push(arena, q, root_base);
    var steps: u32 = 0;
    while (try FQueue.pop(arena, q)) |d| {
        q = d.rest;
        steps += 1;
        if (steps > STEP_CAP) return error.Deadlock;
        const p = t.slot(d.pid) orelse continue;
        if (!p.alive or p.blocked) continue;
        var wake: std.ArrayList(Pid) = .empty;
        defer wake.deinit(gpa);
        const outcome = try runBurst(&t, d.pid, &wake);
        // enqueue newly-woken pids (FIFO), then requeue self on yield.
        for (wake.items) |w| q = try FQueue.push(arena, q, w);
        if (outcome == .yielded) q = try FQueue.push(arena, q, d.pid);
    }
    return .{ .trace = try t.trace.clone(gpa), .reds = t.reds };
}

// ── Real[Sched]: run-queue = a mutable ring-buffer deque + reduction counter ─

/// A genuine mutable ring-buffer deque — the Chase–Lev LOCAL-end stand-in
/// (push/pop at the tail, single-core so no cross-core steal). Real memory,
/// in-place head/tail advance with wrap — the physical residue the homomorphism
/// erases. Backed by a growable slice; wraps rather than shifting.
const RingDeque = struct {
    buf: std.ArrayList(Pid) = .empty,
    head: usize = 0,
    count: usize = 0,

    fn pushTail(self: *RingDeque, gpa: std.mem.Allocator, pid: Pid) !void {
        if (self.count == self.buf.items.len) try self.grow(gpa);
        const cap = self.buf.items.len;
        const tail = (self.head + self.count) % cap;
        self.buf.items[tail] = pid;
        self.count += 1;
    }
    fn popHead(self: *RingDeque) ?Pid {
        if (self.count == 0) return null;
        const pid = self.buf.items[self.head];
        self.head = (self.head + 1) % self.buf.items.len;
        self.count -= 1;
        return pid;
    }
    fn grow(self: *RingDeque, gpa: std.mem.Allocator) !void {
        const old_cap = self.buf.items.len;
        const new_cap = if (old_cap == 0) 8 else old_cap * 2;
        var fresh: std.ArrayList(Pid) = .empty;
        try fresh.resize(gpa, new_cap);
        var i: usize = 0;
        while (i < self.count) : (i += 1) fresh.items[i] = self.buf.items[(self.head + i) % old_cap];
        self.buf.deinit(gpa);
        self.buf = fresh;
        self.head = 0;
    }
    fn deinit(self: *RingDeque, gpa: std.mem.Allocator) void {
        self.buf.deinit(gpa);
    }
};

/// The FINAL encoding. Identical SCHEDULE policy to `runModel` (round-robin
/// cooperative, one burst per turn); the run-queue is a real mutable ring deque
/// with a live reduction counter. `observe` (pid→ordinal, already baked into the
/// emitted events) makes the ring's physical storage + the reds counter invisible.
pub fn runReal(
    gpa: std.mem.Allocator,
    caps: Caps,
    root_base: Pid,
    root_seed: ProcSeed,
) SchedError!RunOut {
    if (!caps.sched) return error.CapabilityAbsent;
    var t = Table{ .gpa = gpa, .base = root_base, .next_pid = root_base };
    defer t.deinit();
    _ = try t.spawn(root_seed);

    var rq = RingDeque{};
    defer rq.deinit(gpa);
    try rq.pushTail(gpa, root_base);
    var steps: u32 = 0;
    while (rq.popHead()) |pid| {
        steps += 1;
        if (steps > STEP_CAP) return error.Deadlock;
        const p = t.slot(pid) orelse continue;
        if (!p.alive or p.blocked) continue;
        var wake: std.ArrayList(Pid) = .empty;
        defer wake.deinit(gpa);
        const outcome = try runBurst(&t, pid, &wake);
        for (wake.items) |w| try rq.pushTail(gpa, w);
        if (outcome == .yielded) try rq.pushTail(gpa, pid);
    }
    return .{ .trace = try t.trace.clone(gpa), .reds = t.reds };
}

// ── the law suite ──────────────────────────────────────────────────────────

fn fanoutSeed(n: u32, base: u64) ProcSeed {
    return .{ .role = .root, .n = n, .base = base };
}

test "LAW e34-t2 HOMOMORPHISM: observe(Real[ring]) == observe(Model[okasaki]) over a seeded process family (Φ for a real per-core run-queue)" {
    const gpa = std.testing.allocator;
    var seed: u64 = 0;
    while (seed < 64) : (seed += 1) {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        // vary the fan-out width (0..7) and base value by seed.
        const n: u32 = @intCast(seed % 8);
        const base: u64 = seed *% 1000 + 1;
        var mr = try runModel(gpa, arena.allocator(), .{}, 0, fanoutSeed(n, base));
        defer mr.deinit(gpa);
        var rr = try runReal(gpa, .{}, 0, fanoutSeed(n, base));
        defer rr.deinit(gpa);
        // the persistent-queue oracle and the real ring-buffer runtime produce
        // IDENTICAL observed traces — the residue (queue storage, reds) erased.
        try std.testing.expect(tracesEqual(mr.trace.items, rr.trace.items));
        // and the reduction counter is genuinely live in BOTH (not observed).
        try std.testing.expect(rr.reds > 0 and mr.reds == rr.reds);
    }
}

test "LAW e34-t2 QUOTIENT: observe is invariant to the physical pid supply (root base 0 vs 1000) — pid->ordinal alpha-renaming is a real quotient" {
    const gpa = std.testing.allocator;
    var arena0 = std.heap.ArenaAllocator.init(gpa);
    defer arena0.deinit();
    var arena1 = std.heap.ArenaAllocator.init(gpa);
    defer arena1.deinit();

    var r0 = try runModel(gpa, arena0.allocator(), .{}, 0, fanoutSeed(4, 10));
    defer r0.deinit(gpa);
    var r1 = try runModel(gpa, arena1.allocator(), .{}, 1000, fanoutSeed(4, 10));
    defer r1.deinit(gpa);
    // physical pids differ (base 0 vs 1000) but every event carries ORDINALS, so
    // the observed traces are identical — q erased exactly the pid residue.
    try std.testing.expect(tracesEqual(r0.trace.items, r1.trace.items));
    // the trace is non-trivial: a 4-fan-out has spawn+send+recv+exit events.
    try std.testing.expect(r0.trace.items.len >= 4 * 3);
}

test "LAW e34-t2 PERSISTENCE: a mid-run snapshot of the Okasaki run-queue is observationally immutable (sharing, not aliasing)" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // build [1,2,3], snapshot, then push 4 and pop the front — the snapshot's
    // denotation must not move.
    var q = FQueue{};
    q = try FQueue.push(a, q, 1);
    q = try FQueue.push(a, q, 2);
    q = try FQueue.push(a, q, 3);
    const snap = q.snapshot();

    const snap_seq = try qToList(gpa, snap);
    defer gpa.free(snap_seq);
    try std.testing.expectEqualSlices(Pid, &.{ 1, 2, 3 }, snap_seq);

    // live queue moves on: push 4, pop front (1).
    q = try FQueue.push(a, q, 4);
    const d = (try FQueue.pop(a, q)).?;
    try std.testing.expectEqual(@as(Pid, 1), d.pid);
    q = d.rest;

    // the snapshot STILL denotes [1,2,3] (structural sharing, not aliasing)…
    const snap_seq2 = try qToList(gpa, snap);
    defer gpa.free(snap_seq2);
    try std.testing.expectEqualSlices(Pid, &.{ 1, 2, 3 }, snap_seq2);
    // …while the live queue denotes [2,3,4].
    const live_seq = try qToList(gpa, q);
    defer gpa.free(live_seq);
    try std.testing.expectEqualSlices(Pid, &.{ 2, 3, 4 }, live_seq);
}

test "LAW e34-t2 FIFO: the fan-out reply accumulator is deterministic (mailbox delivers in arrival order)" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    // root fans out to 3 echoes with base=100: children reply 101,102,103; the
    // trace's recv events at the root observe them in the deterministic order the
    // children ran (spawn order). Assert the exact recv value sequence at root.
    var r = try runModel(gpa, arena.allocator(), .{}, 0, fanoutSeed(3, 100));
    defer r.deinit(gpa);
    var recvs: [3]u64 = undefined;
    var k: usize = 0;
    for (r.trace.items) |ev| {
        if (ev.tag == .recv and ev.actor == 0) { // root's ordinal is 0
            recvs[k] = ev.val;
            k += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), k);
    try std.testing.expectEqualSlices(u64, &.{ 101, 102, 103 }, &recvs);
}

test "LAW e34-t2 FAIL-CLOSED: send to an unknown/dead pid fails CLOSED; capability absent fails closed; an unsatisfiable recv is a bounded deadlock" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    // capability fail-closed (row-composed, as in effect.zig L3).
    try std.testing.expectError(error.CapabilityAbsent, runReal(gpa, .{ .sched = false }, 0, fanoutSeed(1, 1)));
    try std.testing.expectError(error.CapabilityAbsent, runModel(gpa, arena.allocator(), .{ .sched = false }, 0, fanoutSeed(1, 1)));

    // send to an unknown pid fails closed (BadPid). A bespoke one-shot process
    // that sends to a pid that was never spawned.
    var t = Table{ .gpa = gpa, .base = 0, .next_pid = 0 };
    defer t.deinit();
    _ = try t.spawn(.{ .role = .echo, .parent = 999 }); // echo replies to pid 999 (never spawned)
    // hand-drive: echo's first op is recv; feed it a message so it proceeds to
    // send-to-999, which must fail closed.
    t.procs.items[0].mailbox.append(gpa, 7) catch unreachable;
    var wake: std.ArrayList(Pid) = .empty;
    defer wake.deinit(gpa);
    try std.testing.expectError(error.BadPid, runBurst(&t, 0, &wake));

    // an unsatisfiable recv: a lone echo with NO sender parks blocked; the run
    // drains the queue and TERMINATES (bounded — never a hang) with no exit event.
    var arena2 = std.heap.ArenaAllocator.init(gpa);
    defer arena2.deinit();
    var r = try runModel(gpa, arena2.allocator(), .{}, 0, .{ .role = .echo, .parent = 0 });
    defer r.deinit(gpa);
    // the echo blocked on its first recv: no send/exit events, run still returned.
    for (r.trace.items) |ev| try std.testing.expect(ev.tag != .exit);
}
