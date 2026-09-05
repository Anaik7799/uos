//! # substrate/reactor — Real[IO]: the THIRD HOST-touching substrate handler (E35-T1)
//!
//! ## Stratum
//! The FINAL encoding of the `IO` domain — the third `Real` handler of the
//! E-substrate program (`docs/STRATUM_C_DESIGN.md` §3.3/§11.3/§14 T-3), following
//! `Real[Alloc]` (memory, E33-T1) and `Real[Sched]` (concurrency, E34-T2). This is
//! the first REACTIVE/streaming domain: the `IO` effect (`open`/`write`/`read`/
//! `close`) is COMPLETION-BASED — submissions go on a submission queue, results
//! return as a COMPLETION STREAM (the coalgebraic `Nu` side of the design). The
//! `Real` handler is an io_uring-shaped ring (a submission/completion queue pair,
//! single-threaded, in-memory backend); the `Model` is a pure fs whose files are
//! PERSISTENT append-only record vectors. Nothing in the VM depends on it; `vm_all`
//! pulls it for its law suite only.
//!
//! ## What it proves
//! `effect.zig` L1 extended to I/O: `observe(Real.run(p)) == observe(Model.run(p))`
//! for a seeded program family. The RESIDUE — physical fd values, the ring's
//! submission/completion storage + batching, real vs modeled backend — is erased by
//! the SAME observation (fd → OPEN ORDINAL, exactly as `alloc` renamed handle →
//! allocation ordinal and `sched` renamed pid → spawn ordinal). A real reactor over
//! a ring and a pure persistent fs denote the same completion trace.
//!
//! ## Signature (Σ_IO) and semantic domain
//!   `SubOp = open(name) | write(fd,v) | read(fd) | close(fd)` submitted to the ring;
//!   `IOResult = fd | val | unit` returned by the matching completion. A FILE is an
//!   append-only sequence of u64 records with a per-fd read cursor (streaming read,
//!   not addressed memory — the distinction from `Real[Alloc]`). A read past EOF is
//!   a defined SHORT READ (value 0), not a fault (mirrors `read(2)` returning 0).
//!   The COMPLETION STREAM is a pull-based iterator: `pullCompletion` yields the
//!   next ready completion or `null` (backpressure by construction — never
//!   fabricates a completion that was not submitted).
//!
//! ## Laws
//!   HOMOMORPHISM   `observe(Real[ring]) == observe(Model[persistent-fs])` over a
//!                  seeded program family (discharges L1 for the I/O reactor).
//!   QUOTIENT       `observe` is invariant to the physical fd supply (fd base 0 vs
//!                  1000) — fd→ordinal α-renaming is a real quotient.
//!   STREAM         the Real completion queue is a pull-based FIFO iterator:
//!                  submitting K ops and pulling yields EXACTLY K completions in
//!                  submission order, and the (K+1)th pull is `null` (backpressure —
//!                  no fabrication). The reactor's Nu-side discipline.
//!   PERSISTENCE    a mid-run snapshot of a Model file denotes the same records
//!                  after later appends (to it OR another fd) — the persistent
//!                  record vector is a VALUE (structural sharing, never aliasing).
//!   FAIL-CLOSED    op on an unknown/closed fd fails CLOSED (BadFd); capability
//!                  absent fails closed; a read past EOF is a defined short-read.
//!
//! ## Scope limits (documented, honest)
//! IN-MEMORY backend, SINGLE-THREADED reactor, synchronous submit→drain facade over
//! a real ring. The genuine `io_uring`/`epoll`/`kqueue` SYSCALL floor, registered
//! zero-copy buffers, cross-fd async reordering, and the socket-FSM half (this slice
//! is the file half) are NAMED successor slices (§13.3). The point is the third host
//! kernel under the one law + the first reactive domain, not a production reactor.

const std = @import("std");

// ── Σ_IO: the effect signature ─────────────────────────────────────────────

pub const Fd = u32;

pub const SubOp = union(enum) {
    open: struct { name: u32 },
    write: struct { fd: Fd, v: u64 },
    read: struct { fd: Fd },
    close: struct { fd: Fd },
};

pub const IOResult = union(enum) {
    fd: Fd, //   open completion
    val: u64, // read completion (the record, or 0 on EOF short-read)
    unit, //     write/close completion
};

/// A program over Σ_IO: first-order state + a step function (defunctionalized CPS,
/// as in `alloc.zig`). `step` receives the PREVIOUS op's completion result (null on
/// entry) and yields the next submission (null = done).
pub fn Program(comptime S: type) type {
    return struct {
        state: S,
        stepFn: *const fn (s: *S, prev: ?IOResult) ?SubOp,
    };
}

// ── the observed trace (the quotient q) ────────────────────────────────────

pub const IOTag = enum { open, write, read, close };

/// One observed completion. `fd` is the OPEN ORDINAL (α-renamed), never a physical
/// fd. `val` is the record value (write/read) or the open name; 0 for close.
pub const IOEvent = struct {
    tag: IOTag,
    fd: u64,
    val: u64,
};

pub fn tracesEqual(a: []const IOEvent, b: []const IOEvent) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x.tag != y.tag or x.fd != y.fd or x.val != y.val) return false;
    }
    return true;
}

pub const Caps = struct { io: bool = true };

pub const IOError = error{ OutOfMemory, CapabilityAbsent, BadFd };

// ── the persistent file (the Model's carrier — a VALUE) ─────────────────────

const RecNode = struct { v: u64, next: ?*const RecNode };

/// An append-only record sequence as a persistent cons-list (head = MOST RECENT),
/// with a length so `get(idx)` reads in WRITE order. Append is O(1) sharing the old
/// spine; a snapshot is a struct copy (PERSISTENCE law's subject). Arena-owned.
pub const File = struct {
    head: ?*const RecNode = null,
    len: u32 = 0,

    fn append(a: std.mem.Allocator, f: File, v: u64) error{OutOfMemory}!File {
        const node = try a.create(RecNode);
        node.* = .{ .v = v, .next = f.head };
        return .{ .head = node, .len = f.len + 1 };
    }

    /// Record at write-index `idx` (0 = first written). Walk `len-1-idx` from head.
    fn get(f: File, idx: u32) ?u64 {
        if (idx >= f.len) return null;
        var steps = f.len - 1 - idx;
        var cur = f.head;
        while (steps > 0) : (steps -= 1) cur = cur.?.next;
        return cur.?.v;
    }

    fn snapshot(self: File) File {
        return self; // O(1): spine shared
    }
};

// ── a shared fd table (Model and Real differ in the FILE carrier, not the FSM) ─

fn Table(comptime FileRep: type) type {
    return struct {
        const Self = @This();
        const Slot = struct { file: FileRep, open: bool, rcursor: u32, ord: u64 };
        gpa: std.mem.Allocator,
        slots: std.ArrayList(Slot) = .empty,
        base: Fd,
        next_fd: Fd,
        n_open: u64 = 0, // ordinal supply
        trace: std.ArrayList(IOEvent) = .empty,

        fn slot(self: *Self, fd: Fd) ?*Slot {
            if (fd < self.base) return null;
            const idx = fd - self.base;
            if (idx >= self.slots.items.len) return null;
            return &self.slots.items[idx];
        }
        fn ordOf(self: *Self, fd: Fd) IOError!u64 {
            const s = self.slot(fd) orelse return error.BadFd;
            if (!s.open) return error.BadFd;
            return s.ord;
        }
        fn deinit(self: *Self, comptime freeFile: fn (std.mem.Allocator, *FileRep) void) void {
            for (self.slots.items) |*s| freeFile(self.gpa, &s.file);
            self.slots.deinit(self.gpa);
            self.trace.deinit(self.gpa);
        }
    };
}

// ── the Model: files = persistent cons-lists; ops applied directly ──────────

pub const RunOut = struct {
    trace: std.ArrayList(IOEvent),
    fn deinit(self: *RunOut, gpa: std.mem.Allocator) void {
        self.trace.deinit(gpa);
    }
};

fn noFreeFile(_: std.mem.Allocator, _: *File) void {}

/// The ORACLE. Files are persistent `File` values; the ring is IMPLICIT (ops apply
/// directly, in submission order — the obviously-correct semantics the real reactor
/// must match). `arena` owns record nodes. `fd_base` varies the physical fd supply
/// (QUOTIENT). One completion per submitted op (synchronous facade).
pub fn runModel(
    comptime S: type,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    caps: Caps,
    fd_base: Fd,
    prog: Program(S),
) IOError!RunOut {
    if (!caps.io) return error.CapabilityAbsent;
    var t = Table(File){ .gpa = gpa, .base = fd_base, .next_fd = fd_base };
    defer t.deinit(noFreeFile);
    var st = prog.state;
    var prev: ?IOResult = null;

    while (prog.stepFn(&st, prev)) |op| {
        switch (op) {
            .open => |o| {
                const fd = t.next_fd;
                t.next_fd += 1;
                const ord = t.n_open;
                t.n_open += 1;
                try t.slots.append(gpa, .{ .file = .{}, .open = true, .rcursor = 0, .ord = ord });
                try t.trace.append(gpa, .{ .tag = .open, .fd = ord, .val = o.name });
                prev = .{ .fd = fd };
            },
            .write => |w| {
                const s = t.slot(w.fd) orelse return error.BadFd;
                if (!s.open) return error.BadFd;
                s.file = try File.append(arena, s.file, w.v);
                try t.trace.append(gpa, .{ .tag = .write, .fd = s.ord, .val = w.v });
                prev = .unit;
            },
            .read => |r| {
                const s = t.slot(r.fd) orelse return error.BadFd;
                if (!s.open) return error.BadFd;
                const v: u64 = s.file.get(s.rcursor) orelse 0; // EOF short-read = 0
                if (s.rcursor < s.file.len) s.rcursor += 1;
                try t.trace.append(gpa, .{ .tag = .read, .fd = s.ord, .val = v });
                prev = .{ .val = v };
            },
            .close => |c| {
                const s = t.slot(c.fd) orelse return error.BadFd;
                if (!s.open) return error.BadFd;
                s.open = false;
                try t.trace.append(gpa, .{ .tag = .close, .fd = s.ord, .val = 0 });
                prev = .unit;
            },
        }
    }
    return .{ .trace = try t.trace.clone(gpa) };
}

// ── Real[IO]: an io_uring-shaped ring + a mutable in-memory fs ───────────────

/// A submission-queue entry (what the program pushes) tagged with the fd ordinal
/// resolved at submit time (so the completion can carry the observed ordinal).
const Sqe = struct { op: SubOp, ord: u64 };

/// A completion-queue entry — the reactor's output, pulled as a stream.
const Cqe = struct { ev: IOEvent, res: IOResult };

/// The real ring: FIFO submission + completion queues (ArrayList-backed, head
/// cursors — the io_uring SQ/CQ shape). The physical residue the homomorphism erases.
pub const Ring = struct {
    sq: std.ArrayList(Sqe) = .empty,
    sq_head: usize = 0,
    cq: std.ArrayList(Cqe) = .empty,
    cq_head: usize = 0,

    fn deinit(self: *Ring, gpa: std.mem.Allocator) void {
        self.sq.deinit(gpa);
        self.cq.deinit(gpa);
    }
    fn submit(self: *Ring, gpa: std.mem.Allocator, sqe: Sqe) !void {
        try self.sq.append(gpa, sqe);
    }
    /// Pull the next ready completion, or null (backpressure — the STREAM law).
    fn pullCompletion(self: *Ring) ?Cqe {
        if (self.cq_head >= self.cq.items.len) return null;
        const c = self.cq.items[self.cq_head];
        self.cq_head += 1;
        return c;
    }
};

const RealFile = std.ArrayList(u64);
fn freeRealFile(gpa: std.mem.Allocator, f: *RealFile) void {
    f.deinit(gpa);
}

/// Process every pending submission in FIFO order, applying it to the real fs and
/// producing a completion. The reactor tick (the `io_uring_enter` analog).
fn reactorTick(t: *Table(RealFile), ring: *Ring) IOError!void {
    while (ring.sq_head < ring.sq.items.len) {
        const sqe = ring.sq.items[ring.sq_head];
        ring.sq_head += 1;
        switch (sqe.op) {
            .write => |w| {
                const s = t.slot(w.fd) orelse return error.BadFd;
                if (!s.open) return error.BadFd;
                try s.file.append(t.gpa, w.v); // REAL host store
                try ring.cq.append(t.gpa, .{ .ev = .{ .tag = .write, .fd = s.ord, .val = w.v }, .res = .unit });
            },
            .read => |r| {
                const s = t.slot(r.fd) orelse return error.BadFd;
                if (!s.open) return error.BadFd;
                const v: u64 = if (s.rcursor < s.file.items.len) s.file.items[s.rcursor] else 0;
                if (s.rcursor < s.file.items.len) s.rcursor += 1;
                try ring.cq.append(t.gpa, .{ .ev = .{ .tag = .read, .fd = s.ord, .val = v }, .res = .{ .val = v } });
            },
            .close => |c| {
                const s = t.slot(c.fd) orelse return error.BadFd;
                if (!s.open) return error.BadFd;
                s.open = false;
                try ring.cq.append(t.gpa, .{ .ev = .{ .tag = .close, .fd = s.ord, .val = 0 }, .res = .unit });
            },
            .open => {}, // opens are handled at submit time (they allocate the fd)
        }
    }
}

/// The FINAL encoding. Identical op SEMANTICS to `runModel`; the fs is real mutable
/// memory and every op round-trips through a genuine SQ/CQ ring. `observe` (fd→
/// ordinal, baked into the emitted events) makes the ring storage invisible.
pub fn runReal(
    comptime S: type,
    gpa: std.mem.Allocator,
    caps: Caps,
    fd_base: Fd,
    prog: Program(S),
) IOError!RunOut {
    if (!caps.io) return error.CapabilityAbsent;
    var t = Table(RealFile){ .gpa = gpa, .base = fd_base, .next_fd = fd_base };
    defer t.deinit(freeRealFile);
    var ring = Ring{};
    defer ring.deinit(gpa);
    var st = prog.state;
    var prev: ?IOResult = null;

    while (prog.stepFn(&st, prev)) |op| {
        switch (op) {
            .open => |o| {
                // opens allocate the fd synchronously (they may realloc t.slots —
                // NO held slot pointer survives this, the sched-T2 lesson).
                const fd = t.next_fd;
                t.next_fd += 1;
                const ord = t.n_open;
                t.n_open += 1;
                try t.slots.append(gpa, .{ .file = .empty, .open = true, .rcursor = 0, .ord = ord });
                try t.trace.append(gpa, .{ .tag = .open, .fd = ord, .val = o.name });
                prev = .{ .fd = fd };
            },
            else => {
                // submit the op to the ring (resolving the fd ordinal now), tick the
                // reactor to process it, and pull its single completion.
                const target_fd: Fd = switch (op) {
                    .write => |w| w.fd,
                    .read => |r| r.fd,
                    .close => |c| c.fd,
                    .open => unreachable,
                };
                const ord = try t.ordOf(target_fd);
                try ring.submit(gpa, .{ .op = op, .ord = ord });
                try reactorTick(&t, &ring);
                const cqe = ring.pullCompletion() orelse return error.BadFd;
                try t.trace.append(gpa, cqe.ev);
                prev = cqe.res;
            },
        }
    }
    return .{ .trace = try t.trace.clone(gpa) };
}

// ── the law suite ──────────────────────────────────────────────────────────

// A seeded program generator over Σ_IO: open/write/read/close churn with a small
// live-fd set. State carries the open fds so write/read/close target REAL open
// files (dangling/closed fds are the FAIL-CLOSED law's job, exercised separately).
const GenState = struct {
    prng: std.Random.DefaultPrng,
    live: [8]Fd = undefined,
    n_live: usize = 0,
    steps_left: u32,
};

fn genStep(s: *GenState, prev: ?IOResult) ?SubOp {
    if (prev) |p| switch (p) {
        .fd => |fd| {
            if (s.n_live < s.live.len) {
                s.live[s.n_live] = fd;
                s.n_live += 1;
            }
        },
        else => {},
    };
    if (s.steps_left == 0) return null;
    s.steps_left -= 1;
    const r = s.prng.random();
    const choice = if (s.n_live == 0) @as(u8, 0) else r.uintLessThan(u8, 5);
    switch (choice) {
        0 => return .{ .open = .{ .name = r.uintLessThan(u32, 4) } },
        1 => {
            const i = r.uintLessThan(usize, s.n_live);
            return .{ .write = .{ .fd = s.live[i], .v = r.int(u64) } };
        },
        2 => {
            const i = r.uintLessThan(usize, s.n_live);
            return .{ .read = .{ .fd = s.live[i] } };
        },
        3 => {
            const i = r.uintLessThan(usize, s.n_live);
            const fd = s.live[i];
            s.live[i] = s.live[s.n_live - 1];
            s.n_live -= 1;
            return .{ .close = .{ .fd = fd } };
        },
        else => {
            const i = r.uintLessThan(usize, s.n_live);
            return .{ .read = .{ .fd = s.live[i] } }; // bias reads (exercise cursors/EOF)
        },
    }
}

fn seededProg(seed: u64, steps: u32) Program(GenState) {
    return .{ .state = .{ .prng = std.Random.DefaultPrng.init(seed), .steps_left = steps }, .stepFn = genStep };
}

test "LAW e35-t1 HOMOMORPHISM: observe(Real[ring]) == observe(Model[persistent-fs]) over a seeded program family (L1 for the I/O reactor)" {
    const gpa = std.testing.allocator;
    var seed: u64 = 0;
    while (seed < 64) : (seed += 1) {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        var mr = try runModel(GenState, gpa, arena.allocator(), .{}, 0, seededProg(seed, 200));
        defer mr.deinit(gpa);
        var rr = try runReal(GenState, gpa, .{}, 0, seededProg(seed, 200));
        defer rr.deinit(gpa);
        // the pure persistent-fs oracle and the real ring reactor produce IDENTICAL
        // observed completion traces — the residue (fd values, ring storage) erased.
        try std.testing.expect(tracesEqual(mr.trace.items, rr.trace.items));
    }
}

test "LAW e35-t1 QUOTIENT: observe is invariant to the physical fd supply (fd base 0 vs 1000) — fd->ordinal alpha-renaming is a real quotient" {
    const gpa = std.testing.allocator;
    var r0 = try runReal(GenState, gpa, .{}, 0, seededProg(7, 120));
    defer r0.deinit(gpa);
    var r1 = try runReal(GenState, gpa, .{}, 1000, seededProg(7, 120));
    defer r1.deinit(gpa);
    // physical fds differ (base 0 vs 1000) but every event carries ORDINALS, so
    // the observed traces are identical — q erased exactly the fd residue.
    try std.testing.expect(tracesEqual(r0.trace.items, r1.trace.items));
    try std.testing.expect(r0.trace.items.len > 0);
}

test "LAW e35-t1 STREAM: the completion queue is a pull-based FIFO iterator — K submissions yield EXACTLY K completions, then null (backpressure)" {
    const gpa = std.testing.allocator;
    var t = Table(RealFile){ .gpa = gpa, .base = 0, .next_fd = 0 };
    defer t.deinit(freeRealFile);
    var ring = Ring{};
    defer ring.deinit(gpa);

    // open a file directly (opens allocate the fd), then batch-submit 3 writes and
    // 1 read WITHOUT draining between submissions.
    try t.slots.append(gpa, .{ .file = .empty, .open = true, .rcursor = 0, .ord = 0 });
    try ring.submit(gpa, .{ .op = .{ .write = .{ .fd = 0, .v = 10 } }, .ord = 0 });
    try ring.submit(gpa, .{ .op = .{ .write = .{ .fd = 0, .v = 20 } }, .ord = 0 });
    try ring.submit(gpa, .{ .op = .{ .write = .{ .fd = 0, .v = 30 } }, .ord = 0 });
    try ring.submit(gpa, .{ .op = .{ .read = .{ .fd = 0 } }, .ord = 0 });
    try reactorTick(&t, &ring);

    // pull EXACTLY 4 completions in submission order; the read observes the FIRST
    // written record (10) — FIFO both in the ring and in the file cursor.
    const c0 = ring.pullCompletion().?;
    const c1 = ring.pullCompletion().?;
    const c2 = ring.pullCompletion().?;
    const c3 = ring.pullCompletion().?;
    try std.testing.expectEqual(IOTag.write, c0.ev.tag);
    try std.testing.expectEqual(@as(u64, 10), c0.ev.val);
    try std.testing.expectEqual(@as(u64, 20), c1.ev.val);
    try std.testing.expectEqual(@as(u64, 30), c2.ev.val);
    try std.testing.expectEqual(IOTag.read, c3.ev.tag);
    try std.testing.expectEqual(@as(u64, 10), c3.ev.val);
    // BACKPRESSURE: the 5th pull fabricates nothing — the stream is exhausted.
    try std.testing.expectEqual(@as(?Cqe, null), ring.pullCompletion());
}

test "LAW e35-t1 PERSISTENCE: a mid-run snapshot of a Model file is observationally immutable (persistent record vector; sharing, not aliasing)" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // append 10,20,30, snapshot, then append 40 — the snapshot must not move.
    var f = File{};
    f = try File.append(a, f, 10);
    f = try File.append(a, f, 20);
    f = try File.append(a, f, 30);
    const snap = f.snapshot();
    try std.testing.expectEqual(@as(?u64, 10), snap.get(0));
    try std.testing.expectEqual(@as(?u64, 30), snap.get(2));
    try std.testing.expectEqual(@as(u32, 3), snap.len);

    f = try File.append(a, f, 40); // the live file grows

    // the snapshot STILL denotes [10,20,30] (structural sharing, not aliasing)…
    try std.testing.expectEqual(@as(?u64, 10), snap.get(0));
    try std.testing.expectEqual(@as(?u64, 30), snap.get(2));
    try std.testing.expectEqual(@as(?u64, null), snap.get(3));
    try std.testing.expectEqual(@as(u32, 3), snap.len);
    // …while the live file denotes [10,20,30,40].
    try std.testing.expectEqual(@as(?u64, 40), f.get(3));
    try std.testing.expectEqual(@as(u32, 4), f.len);
}

test "LAW e35-t1 FAIL-CLOSED: op on an unknown/closed fd fails CLOSED; capability absent fails closed; read past EOF is a defined short-read" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    // capability fail-closed (row-composed, as in effect.zig L3).
    const OneState = struct { op: SubOp, done: bool = false };
    const oneStep = struct {
        fn f(s: *OneState, _: ?IOResult) ?SubOp {
            if (s.done) return null;
            s.done = true;
            return s.op;
        }
    }.f;
    try std.testing.expectError(error.CapabilityAbsent, runReal(OneState, gpa, .{ .io = false }, 0, .{ .state = .{ .op = .{ .open = .{ .name = 0 } } }, .stepFn = oneStep }));

    // write/read/close on an UNKNOWN fd fail closed.
    for ([_]SubOp{
        .{ .write = .{ .fd = 99, .v = 1 } },
        .{ .read = .{ .fd = 99 } },
        .{ .close = .{ .fd = 99 } },
    }) |op| {
        try std.testing.expectError(error.BadFd, runReal(OneState, gpa, .{}, 0, .{ .state = .{ .op = op }, .stepFn = oneStep }));
    }

    // open → close → write-after-close fails closed (both handlers agree).
    const AfterCloseState = struct { step: u8 = 0, fd: Fd = 0 };
    const acStep = struct {
        fn f(s: *AfterCloseState, prev: ?IOResult) ?SubOp {
            defer s.step += 1;
            return switch (s.step) {
                0 => .{ .open = .{ .name = 0 } },
                1 => blk: {
                    s.fd = prev.?.fd;
                    break :blk .{ .close = .{ .fd = s.fd } };
                },
                2 => .{ .write = .{ .fd = s.fd, .v = 7 } }, // use-after-close
                else => null,
            };
        }
    }.f;
    try std.testing.expectError(error.BadFd, runReal(AfterCloseState, gpa, .{}, 0, .{ .state = .{}, .stepFn = acStep }));
    try std.testing.expectError(error.BadFd, runModel(AfterCloseState, gpa, arena.allocator(), .{}, 0, .{ .state = .{}, .stepFn = acStep }));

    // read past EOF is a defined SHORT READ (0), not a fault — Real and Model agree.
    const EofState = struct { step: u8 = 0, fd: Fd = 0 };
    const eofStep = struct {
        fn f(s: *EofState, prev: ?IOResult) ?SubOp {
            defer s.step += 1;
            return switch (s.step) {
                0 => .{ .open = .{ .name = 0 } },
                1 => blk: {
                    s.fd = prev.?.fd;
                    break :blk .{ .read = .{ .fd = s.fd } }; // read an empty file
                },
                else => null,
            };
        }
    }.f;
    var er = try runReal(EofState, gpa, .{}, 0, .{ .state = .{}, .stepFn = eofStep });
    defer er.deinit(gpa);
    // the read event exists and observed 0 (EOF short-read), no fault.
    var saw_read = false;
    for (er.trace.items) |ev| if (ev.tag == .read) {
        saw_read = true;
        try std.testing.expectEqual(@as(u64, 0), ev.val);
    };
    try std.testing.expect(saw_read);
}
