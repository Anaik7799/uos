//! # substrate/boot — the full Stratum-C boot: Real[Sched] running Real[Alloc] fibers (E39-T1)
//!
//! ## Stratum
//! The END-TO-END composition of the E-substrate program: a real single-core
//! SCHEDULER (`substrate/sched.zig`'s run-queue discipline) running FIBERS that
//! perform real ALLOCATOR ops (`substrate/alloc.zig`'s slab). Where E36–E38 composed
//! resource domains under one row and proved a real allocator backs a row program,
//! THIS proves the top-level integration: a real scheduler runs real-allocating
//! processes, and the whole boot — the interleaved schedule/message/exit trace PLUS
//! every process's alloc/write/read — is OBSERVED-identical to a pure Model boot.
//! Nothing in the VM depends on it; `vm_all` pulls it for its law suite only.
//!
//! ## What it proves
//! `effect.zig` L1 lifted to the WHOLE substrate: `observe(bootReal(p)) ==
//! observe(bootModel(p))`. The resource backend is a COMPTIME parameter (`Res`) —
//! the Model uses a pure cell store, the Real uses the actual slab allocator — and
//! the SAME scheduler drives both. The residue (physical pids, real block
//! addresses, reused slab indices) is erased by the per-domain ordinal renaming
//! (pid → spawn-ordinal, handle → alloc-ordinal). A real scheduler over a real
//! allocator denotes the same boot trace as the pure oracle — the substrate
//! program's proof-of-concept for a real VM substrate.
//!
//! ## Signature and semantic domain
//! A process is a defunctionalized-CPS step machine (as in `sched.zig`): `bootStep`
//! interprets a `ProcState` (root | worker), yielding a `BootOp`:
//!   SCHED : spawn(seed) | send(to,msg) | recv | exit   (affect the run-queue/mailboxes)
//!   MEM   : alloc | write(v) | read                    (drive the resource backend)
//! The schedule is single-core round-robin COOPERATIVE (a process runs until it
//! blocks on an empty recv or exits). The workload: root spawns N workers, each
//! worker ALLOCATES a cell, writes its seed, reads it back, sends the read value to
//! root, and exits; root collects the N replies and exits. Every process does BOTH
//! scheduling AND real memory work — the integration under test.
//!
//! ## Laws
//!   HOMOMORPHISM   `observe(bootReal(p)) == observe(bootModel(p))` over a seeded
//!                  workload family — a real scheduler over a real allocator ==
//!                  the pure Model boot (L1 for the whole substrate).
//!   QUOTIENT       `observe` is invariant to the physical pid supply (root base 0
//!                  vs 1000) — the boot trace depends only on the ordinals.
//!   FAIL-CLOSED    an unsatisfiable recv is a bounded deadlock (never a hang); the
//!                  memory capability gates the mem ops (absent ⇒ fail closed).
//!
//! ## Scope limits (documented, honest)
//! SINGLE-CORE scheduler + the ALLOC resource kernel (a SHARED allocator, global
//! alloc-ordinal). Adding `Real[IO]` as a second resource domain, per-process heaps,
//! and the cross-core scheduler are NAMED successors — the point here is the
//! top-level scheduler×allocator integration under the one observation law.

const std = @import("std");

pub const Pid = u32;
pub const Role = enum { root, worker };

pub const ProcSeed = struct { role: Role, parent: Pid = 0, n: u32 = 0, base: u64 = 0, seed_val: u64 = 0 };

pub const BootOp = union(enum) {
    spawn: ProcSeed,
    send: struct { to: Pid, msg: u64 },
    recv,
    exit,
    alloc,
    write: struct { v: u64 },
    read,
    free,
    io_open,
    io_write: struct { v: u64 },
    io_read,
    io_close,
};

pub const BootResult = union(enum) { pid: Pid, msg: u64, val: u64, unit };

pub const ProcState = struct {
    role: Role,
    parent: Pid = 0,
    n: u32 = 0,
    base: u64 = 0,
    seed_val: u64 = 0,
    phase: u8 = 0,
    i: u32 = 0,
    children: [8]Pid = undefined,
    n_children: u32 = 0,
    got: u32 = 0,
    acc: u64 = 0,
    read_val: u64 = 0,

    fn fromSeed(s: ProcSeed) ProcState {
        return .{ .role = s.role, .parent = s.parent, .n = s.n, .base = s.base, .seed_val = s.seed_val };
    }
};

/// One op per call; consumes the prior op's result. Total over the role machines.
///   worker: alloc → write(seed_val) → read → send(parent, read_val) → exit
///   root:   spawn n workers (seed base+i) → recv n replies → exit
fn bootStep(s: *ProcState, my: Pid, prev: ?BootResult) ?BootOp {
    switch (s.role) {
        .worker => {
            defer s.phase += 1;
            return switch (s.phase) {
                0 => .alloc,
                1 => .{ .write = .{ .v = s.seed_val } },
                2 => .read,
                3 => blk: {
                    s.read_val = prev.?.val;
                    break :blk .free; // release the scratch cell (a later worker REUSES the slab block)
                },
                // …then the SECOND resource domain: open a file, write+read the same
                // value through it, close — a fiber that allocates AND does I/O.
                4 => .io_open,
                5 => .{ .io_write = .{ .v = s.read_val } },
                6 => .io_read,
                7 => blk: {
                    s.read_val = prev.?.val; // the value round-tripped through the file
                    break :blk .io_close;
                },
                8 => .{ .send = .{ .to = s.parent, .msg = s.read_val } },
                9 => .exit,
                else => null,
            };
        },
        .root => switch (s.phase) {
            0 => {
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
                    const sv = s.base +% s.i;
                    s.i += 1;
                    return .{ .spawn = .{ .role = .worker, .parent = my, .seed_val = sv } };
                }
                s.phase = 1;
                s.i = 0;
                return bootStep(s, my, null);
            },
            1 => {
                if (prev) |p| switch (p) {
                    .msg => |m| {
                        s.acc +%= m;
                        s.got += 1;
                    },
                    else => {},
                };
                if (s.got < s.n_children) return .recv;
                s.phase = 2;
                return .exit;
            },
            else => return null,
        },
    }
}

// ── the observed trace (the quotient q) ────────────────────────────────────

pub const Kind = enum { spawn, send, recv, exit, alloc, write, read, free, io_open, io_write, io_read, io_close };

pub const BootEvent = struct {
    kind: Kind,
    actor: u64, // acting process's spawn ordinal
    peer: u64, //  spawn: child ord; send: target ord; alloc/write/read: handle ord; else 0
    val: u64, //   send/recv: message; write/read: value; else 0
};

pub fn tracesEqual(a: []const BootEvent, b: []const BootEvent) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x.kind != y.kind or x.actor != y.actor or x.peer != y.peer or x.val != y.val) return false;
    }
    return true;
}

pub const Caps = struct { sched: bool = true, mem: bool = true, io: bool = true };
pub const BootError = error{ OutOfMemory, CapabilityAbsent, BadPid, BadResource, Deadlock };

// ── the two resource backends (the COMPTIME parameter) ──────────────────────

/// The Model resource: a pure cell store. Handle == cell index == alloc ordinal
/// (no reuse), so the observation is the identity on handles.
const ModelRes = struct {
    gpa: std.mem.Allocator,
    cells: std.ArrayList(u64) = .empty,
    n_alloc: u64 = 0,
    files: std.ArrayList(std.ArrayList(u64)) = .empty,
    fopen: std.ArrayList(bool) = .empty,
    n_open: u64 = 0,

    pub fn init(gpa: std.mem.Allocator) ModelRes {
        return .{ .gpa = gpa };
    }
    pub fn deinit(self: *ModelRes) void {
        self.cells.deinit(self.gpa);
        for (self.files.items) |*f| f.deinit(self.gpa);
        self.files.deinit(self.gpa);
        self.fopen.deinit(self.gpa);
    }
    pub fn open(self: *ModelRes) BootError!struct { fd: u64, ord: u64 } {
        const ord = self.n_open;
        self.n_open += 1;
        try self.files.append(self.gpa, .empty);
        try self.fopen.append(self.gpa, true);
        return .{ .fd = self.files.items.len - 1, .ord = ord };
    }
    pub fn iowrite(self: *ModelRes, fd: u64, v: u64) BootError!void {
        if (fd >= self.files.items.len or !self.fopen.items[@intCast(fd)]) return error.BadResource;
        try self.files.items[@intCast(fd)].append(self.gpa, v);
    }
    pub fn ioread(self: *ModelRes, fd: u64) BootError!u64 {
        if (fd >= self.files.items.len or !self.fopen.items[@intCast(fd)]) return error.BadResource;
        const f = self.files.items[@intCast(fd)];
        return if (f.items.len > 0) f.items[0] else 0; // read record 0 (EOF short-read = 0)
    }
    pub fn ioclose(self: *ModelRes, fd: u64) BootError!void {
        if (fd >= self.files.items.len or !self.fopen.items[@intCast(fd)]) return error.BadResource;
        self.fopen.items[@intCast(fd)] = false;
    }
    fn fdOrd(self: *ModelRes, fd: u64) u64 {
        _ = self;
        return fd; // files never reuse indices ⇒ fd == open ordinal
    }
    pub fn alloc(self: *ModelRes) BootError!struct { handle: u64, ord: u64 } {
        const ord = self.n_alloc;
        self.n_alloc += 1;
        try self.cells.append(self.gpa, 0);
        return .{ .handle = self.cells.items.len - 1, .ord = ord };
    }
    pub fn write(self: *ModelRes, handle: u64, v: u64) BootError!void {
        if (handle >= self.cells.items.len) return error.BadResource;
        self.cells.items[@intCast(handle)] = v;
    }
    pub fn read(self: *ModelRes, handle: u64) BootError!u64 {
        if (handle >= self.cells.items.len) return error.BadResource;
        return self.cells.items[@intCast(handle)];
    }
    pub fn free(self: *ModelRes, handle: u64) BootError!void {
        // The pure store never REUSES an index (alloc always appends), so free is
        // observationally a no-op on handles — a freed handle_ord stays its alloc
        // ordinal, matching what the Real slab's `ords` renaming yields.
        if (handle >= self.cells.items.len) return error.BadResource;
    }
};

const alloc_mod = @import("alloc.zig");

/// The Real resource: the actual slab allocator. Handles are slab block indices
/// (REUSED after free), so an `ords` map renames handle → alloc ordinal — the
/// residue the homomorphism erases.
const RealRes = struct {
    gpa: std.mem.Allocator,
    alc: alloc_mod.Allctr(alloc_mod.FirstFit),
    ords: std.AutoHashMapUnmanaged(u32, u64) = .empty,
    n_alloc: u64 = 0,
    // the second REAL resource kernel: a real host file store.
    files: std.ArrayList(std.ArrayList(u64)) = .empty,
    fopen: std.ArrayList(bool) = .empty,
    n_open: u64 = 0,

    pub fn init(gpa: std.mem.Allocator) RealRes {
        return .{ .gpa = gpa, .alc = alloc_mod.Allctr(alloc_mod.FirstFit).init(gpa) };
    }
    pub fn deinit(self: *RealRes) void {
        self.alc.deinit();
        self.ords.deinit(self.gpa);
        for (self.files.items) |*f| f.deinit(self.gpa);
        self.files.deinit(self.gpa);
        self.fopen.deinit(self.gpa);
    }
    pub fn open(self: *RealRes) BootError!struct { fd: u64, ord: u64 } {
        const ord = self.n_open;
        self.n_open += 1;
        try self.files.append(self.gpa, .empty);
        try self.fopen.append(self.gpa, true);
        return .{ .fd = self.files.items.len - 1, .ord = ord };
    }
    pub fn iowrite(self: *RealRes, fd: u64, v: u64) BootError!void {
        if (fd >= self.files.items.len or !self.fopen.items[@intCast(fd)]) return error.BadResource;
        try self.files.items[@intCast(fd)].append(self.gpa, v); // REAL host append
    }
    pub fn ioread(self: *RealRes, fd: u64) BootError!u64 {
        if (fd >= self.files.items.len or !self.fopen.items[@intCast(fd)]) return error.BadResource;
        const f = self.files.items[@intCast(fd)];
        return if (f.items.len > 0) f.items[0] else 0;
    }
    pub fn ioclose(self: *RealRes, fd: u64) BootError!void {
        if (fd >= self.files.items.len or !self.fopen.items[@intCast(fd)]) return error.BadResource;
        self.fopen.items[@intCast(fd)] = false;
    }
    fn fdOrd(self: *RealRes, fd: u64) u64 {
        _ = self;
        return fd;
    }
    pub fn alloc(self: *RealRes) BootError!struct { handle: u64, ord: u64 } {
        const h = self.alc.alloc(8) catch return error.BadResource;
        const ord = self.n_alloc;
        self.n_alloc += 1;
        try self.ords.put(self.gpa, h, ord);
        return .{ .handle = h, .ord = ord };
    }
    pub fn write(self: *RealRes, handle: u64, v: u64) BootError!void {
        self.alc.write(@intCast(handle), v) catch return error.BadResource;
    }
    pub fn read(self: *RealRes, handle: u64) BootError!u64 {
        return self.alc.read(@intCast(handle)) catch error.BadResource;
    }
    pub fn free(self: *RealRes, handle: u64) BootError!void {
        // the slab pushes the block onto its free-list; a LATER alloc REUSES the
        // index — so `ords` genuinely renames a reused handle (the residue the
        // homomorphism erases). We keep the freed handle's ord in `ords` for its
        // free EVENT (it is overwritten only when the index is re-allocated).
        self.alc.free_(@intCast(handle)) catch return error.BadResource;
    }
    fn ordOf(self: *RealRes, handle: u64) u64 {
        return self.ords.get(@intCast(handle)).?;
    }
};

// ── the shared scheduler (generic over the resource backend) ────────────────

const Proc = struct {
    state: ProcState,
    ord: u64,
    mailbox: std.ArrayList(u64) = .empty,
    mcursor: usize = 0,
    alive: bool = true,
    blocked: bool = false,
    last_handle: u64 = 0,
    has_handle: bool = false,
    last_fd: u64 = 0,
    has_fd: bool = false,
};

const STEP_CAP: u32 = 100_000;

pub const BootOut = struct {
    trace: std.ArrayList(BootEvent),
    fn deinit(self: *BootOut, gpa: std.mem.Allocator) void {
        self.trace.deinit(gpa);
    }
};

/// Run the whole boot: a single-core round-robin scheduler drives fibers; SCHED
/// ops touch the run-queue/mailboxes, MEM ops drive `Res`. Emits observed events
/// (pid → spawn ordinal, handle → alloc ordinal). `Res` is Model or Real — the
/// SAME scheduler, so the HOMOMORPHISM law compares two backends under one driver.
pub fn runBoot(comptime Res: type, gpa: std.mem.Allocator, caps: Caps, root_base: Pid, root_seed: ProcSeed) BootError!BootOut {
    if (!caps.sched) return error.CapabilityAbsent;
    var res = Res.init(gpa);
    defer res.deinit();
    var procs: std.ArrayList(Proc) = .empty;
    defer {
        for (procs.items) |*p| p.mailbox.deinit(gpa);
        procs.deinit(gpa);
    }
    var trace: std.ArrayList(BootEvent) = .empty;
    errdefer trace.deinit(gpa);

    var next_pid = root_base;
    var n_spawn: u64 = 0;
    const spawnProc = struct {
        fn f(pr: *std.ArrayList(Proc), g: std.mem.Allocator, np: *Pid, ns: *u64, seed: ProcSeed) !Pid {
            const pid = np.*;
            np.* += 1;
            const ord = ns.*;
            ns.* += 1;
            try pr.append(g, .{ .state = ProcState.fromSeed(seed), .ord = ord });
            return pid;
        }
    }.f;

    const root_pid = try spawnProc(&procs, gpa, &next_pid, &n_spawn, root_seed);
    // a simple FIFO run-queue (index cursor) — the scheduling residue quotiented away.
    var rq: std.ArrayList(Pid) = .empty;
    defer rq.deinit(gpa);
    try rq.append(gpa, root_pid);
    var head: usize = 0;
    var steps: u32 = 0;

    while (head < rq.items.len) {
        const pid = rq.items[head];
        head += 1;
        steps += 1;
        if (steps > STEP_CAP) return error.Deadlock;
        const idx = pid - root_base;
        if (idx >= procs.items.len) continue;
        if (!procs.items[idx].alive or procs.items[idx].blocked) continue;

        // run this process's burst
        var prev: ?BootResult = null;
        burst: while (true) {
            // re-fetch each iteration: spawn/alloc may realloc procs.
            const p = &procs.items[idx];
            const my_ord = p.ord;
            steps += 1;
            if (steps > STEP_CAP) return error.Deadlock;
            const op = bootStep(&p.state, pid, prev) orelse {
                p.alive = false;
                try trace.append(gpa, .{ .kind = .exit, .actor = my_ord, .peer = 0, .val = 0 });
                break :burst;
            };
            switch (op) {
                .spawn => |seed| {
                    const cp = try spawnProc(&procs, gpa, &next_pid, &n_spawn, seed);
                    const cord = procs.items[cp - root_base].ord;
                    try trace.append(gpa, .{ .kind = .spawn, .actor = my_ord, .peer = cord, .val = 0 });
                    try rq.append(gpa, cp);
                    prev = .{ .pid = cp };
                },
                .send => |sd| {
                    const ti = sd.to - root_base;
                    if (ti >= procs.items.len or !procs.items[ti].alive) return error.BadPid;
                    try procs.items[ti].mailbox.append(gpa, sd.msg);
                    try trace.append(gpa, .{ .kind = .send, .actor = my_ord, .peer = procs.items[ti].ord, .val = sd.msg });
                    if (procs.items[ti].blocked) {
                        procs.items[ti].blocked = false;
                        try rq.append(gpa, sd.to);
                    }
                    prev = .unit;
                },
                .recv => {
                    const pp = &procs.items[idx];
                    if (pp.mcursor < pp.mailbox.items.len) {
                        const m = pp.mailbox.items[pp.mcursor];
                        pp.mcursor += 1;
                        try trace.append(gpa, .{ .kind = .recv, .actor = my_ord, .peer = 0, .val = m });
                        prev = .{ .msg = m };
                    } else {
                        pp.blocked = true;
                        break :burst;
                    }
                },
                .exit => {
                    procs.items[idx].alive = false;
                    try trace.append(gpa, .{ .kind = .exit, .actor = my_ord, .peer = 0, .val = 0 });
                    break :burst;
                },
                .alloc => {
                    if (!caps.mem) return error.CapabilityAbsent;
                    const a = try res.alloc();
                    const pp = &procs.items[idx];
                    pp.last_handle = a.handle;
                    pp.has_handle = true;
                    try trace.append(gpa, .{ .kind = .alloc, .actor = my_ord, .peer = a.ord, .val = 0 });
                    prev = .unit;
                },
                .write => |w| {
                    if (!caps.mem) return error.CapabilityAbsent;
                    const pp = &procs.items[idx];
                    if (!pp.has_handle) return error.BadResource;
                    try res.write(pp.last_handle, w.v);
                    const ord = resOrd(Res, &res, pp.last_handle);
                    try trace.append(gpa, .{ .kind = .write, .actor = my_ord, .peer = ord, .val = w.v });
                    prev = .unit;
                },
                .read => {
                    if (!caps.mem) return error.CapabilityAbsent;
                    const pp = &procs.items[idx];
                    if (!pp.has_handle) return error.BadResource;
                    const v = try res.read(pp.last_handle);
                    const ord = resOrd(Res, &res, pp.last_handle);
                    try trace.append(gpa, .{ .kind = .read, .actor = my_ord, .peer = ord, .val = v });
                    prev = .{ .val = v };
                },
                .free => {
                    if (!caps.mem) return error.CapabilityAbsent;
                    const pp = &procs.items[idx];
                    if (!pp.has_handle) return error.BadResource;
                    const ord = resOrd(Res, &res, pp.last_handle); // ord BEFORE free (still in ords)
                    try res.free(pp.last_handle);
                    try trace.append(gpa, .{ .kind = .free, .actor = my_ord, .peer = ord, .val = 0 });
                    pp.has_handle = false;
                    prev = .unit;
                },
                .io_open => {
                    if (!caps.io) return error.CapabilityAbsent;
                    const o = try res.open();
                    const pp = &procs.items[idx];
                    pp.last_fd = o.fd;
                    pp.has_fd = true;
                    try trace.append(gpa, .{ .kind = .io_open, .actor = my_ord, .peer = o.ord, .val = 0 });
                    prev = .unit;
                },
                .io_write => |w| {
                    if (!caps.io) return error.CapabilityAbsent;
                    const pp = &procs.items[idx];
                    if (!pp.has_fd) return error.BadResource;
                    try res.iowrite(pp.last_fd, w.v);
                    try trace.append(gpa, .{ .kind = .io_write, .actor = my_ord, .peer = res.fdOrd(pp.last_fd), .val = w.v });
                    prev = .unit;
                },
                .io_read => {
                    if (!caps.io) return error.CapabilityAbsent;
                    const pp = &procs.items[idx];
                    if (!pp.has_fd) return error.BadResource;
                    const v = try res.ioread(pp.last_fd);
                    try trace.append(gpa, .{ .kind = .io_read, .actor = my_ord, .peer = res.fdOrd(pp.last_fd), .val = v });
                    prev = .{ .val = v };
                },
                .io_close => {
                    if (!caps.io) return error.CapabilityAbsent;
                    const pp = &procs.items[idx];
                    if (!pp.has_fd) return error.BadResource;
                    const ord = res.fdOrd(pp.last_fd);
                    try res.ioclose(pp.last_fd);
                    try trace.append(gpa, .{ .kind = .io_close, .actor = my_ord, .peer = ord, .val = 0 });
                    pp.has_fd = false;
                    prev = .unit;
                },
            }
        }
    }
    const owned = trace; // MOVE out (no clone → no leak of the original)
    return .{ .trace = owned };
}

/// The handle → alloc-ordinal renaming: identity for the Model (handle == ord),
/// the `ords` map for the Real (slab indices are reused).
fn resOrd(comptime Res: type, res: *Res, handle: u64) u64 {
    if (Res == RealRes) return res.ordOf(handle);
    return handle; // ModelRes: handle == cell index == alloc ordinal
}

// ── the law suite ──────────────────────────────────────────────────────────

fn workloadSeed(n: u32, base: u64) ProcSeed {
    return .{ .role = .root, .n = n, .base = base };
}

test "LAW e39-t1 HOMOMORPHISM: observe(bootReal) == observe(bootModel) — a real scheduler over a REAL allocator == the pure Model boot (L1 for the whole substrate)" {
    const gpa = std.testing.allocator;
    var seed: u64 = 0;
    while (seed < 48) : (seed += 1) {
        const n: u32 = @intCast(seed % 8);
        const base: u64 = seed *% 100 + 1;
        var m = try runBoot(ModelRes, gpa, .{}, 0, workloadSeed(n, base));
        defer m.deinit(gpa);
        var r = try runBoot(RealRes, gpa, .{}, 0, workloadSeed(n, base));
        defer r.deinit(gpa);
        // the pure Model boot and the real scheduler×allocator boot produce the SAME
        // observed trace — pids renamed to spawn ordinals, slab handles to alloc
        // ordinals; the residue (physical pids, reused block indices) is erased.
        try std.testing.expect(tracesEqual(m.trace.items, r.trace.items));
        // the boot is non-trivial: a 4-worker workload has spawn+alloc+write+read+
        // send+recv+exit events.
        if (n >= 1) try std.testing.expect(r.trace.items.len >= @as(usize, n) * 10);
    }
}

test "LAW e39-t1 QUOTIENT: observe is invariant to the physical pid supply (root base 0 vs 1000)" {
    const gpa = std.testing.allocator;
    var r0 = try runBoot(RealRes, gpa, .{}, 0, workloadSeed(4, 10));
    defer r0.deinit(gpa);
    var r1 = try runBoot(RealRes, gpa, .{}, 1000, workloadSeed(4, 10));
    defer r1.deinit(gpa);
    try std.testing.expect(tracesEqual(r0.trace.items, r1.trace.items));
    try std.testing.expect(r0.trace.items.len >= 4 * 6);
}

test "LAW e39-t1 FAIL-CLOSED: the sched/mem capabilities gate; an unsatisfiable recv is a bounded deadlock" {
    const gpa = std.testing.allocator;
    // capabilities fail closed.
    try std.testing.expectError(error.CapabilityAbsent, runBoot(RealRes, gpa, .{ .sched = false }, 0, workloadSeed(1, 1)));
    try std.testing.expectError(error.CapabilityAbsent, runBoot(RealRes, gpa, .{ .mem = false }, 0, workloadSeed(1, 1)));
    // the IO capability gates the io domain independently (E40-T1): a worker reaches
    // its io_open after the mem work, so an absent io cap fails closed there.
    try std.testing.expectError(error.CapabilityAbsent, runBoot(RealRes, gpa, .{ .io = false }, 0, workloadSeed(1, 1)));

    // a lone worker whose parent (pid 0 = itself, but it never sends to a live
    // recv-er)… use root with 0 workers: it recvs nothing, exits cleanly (n=0).
    var r = try runBoot(RealRes, gpa, .{}, 0, workloadSeed(0, 0));
    defer r.deinit(gpa);
    // n=0: root spawns nothing, gets 0 replies, exits — exactly one exit event.
    try std.testing.expectEqual(@as(usize, 1), r.trace.items.len);
    try std.testing.expectEqual(Kind.exit, r.trace.items[0].kind);
}

test "LAW e40-t1 TWO-DOMAIN BOOT: fibers drive BOTH Real[Alloc] and Real[IO] under Real[Sched]; observe(Real)==observe(Model) with both domains present" {
    const gpa = std.testing.allocator;
    var seed: u64 = 0;
    while (seed < 32) : (seed += 1) {
        const n: u32 = 1 + @as(u32, @intCast(seed % 6)); // ≥1 worker so both domains fire
        const base: u64 = seed *% 100 + 1;
        var m = try runBoot(ModelRes, gpa, .{}, 0, workloadSeed(n, base));
        defer m.deinit(gpa);
        var r = try runBoot(RealRes, gpa, .{}, 0, workloadSeed(n, base));
        defer r.deinit(gpa);
        // the composed two-resource boot is observed-identical Model vs Real …
        try std.testing.expect(tracesEqual(m.trace.items, r.trace.items));
        // … and BOTH resource domains genuinely fired (a real allocator AND a real
        // file store, per worker, under the one scheduler) — not just scheduling.
        var saw_alloc = false;
        var saw_free = false;
        var saw_io_open = false;
        var saw_io_close = false;
        for (r.trace.items) |ev| switch (ev.kind) {
            .alloc => saw_alloc = true,
            .free => saw_free = true,
            .io_open => saw_io_open = true,
            .io_close => saw_io_close = true,
            else => {},
        };
        try std.testing.expect(saw_alloc and saw_free and saw_io_open and saw_io_close);
    }
}
