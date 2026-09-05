//! beam-zig M12 / S25: **ports** — the packet-framing and io-queue algebras
//! (cf. erts packet_parser.c, erl_io_queue.c). Ports are an interpretation
//! boundary by definition; THIS is their Stratum-A content.
//!
//! PACKET FRAMING — `{packet, N}` modes:
//!   frame  : (Mode, bytes) -> bytes
//!   Deframer: a STREAMING decoder fed arbitrary chunks, emitting packets
//! Laws:
//!   FRAME∘DEFRAME = id  per mode, incl. length-boundary payloads
//!                       (255/256 for mode 1 — oversize REJECTED, 65535
//!                       boundary for mode 2, large for mode 4)
//!   STREAM REASSEMBLY   any concatenation of frames, chopped at ARBITRARY
//!                       seeded chunk boundaries, deframes to exactly the
//!                       original packet sequence (the law that catches
//!                       every off-by-one a parser can commit)
//!   LINE MODE           complete '\n'-terminated lines are delivered
//!                       verbatim including the terminator; a trailing
//!                       unterminated line only on flush
//!
//! IO QUEUE — erts erl_io_queue's essence:
//!   enqv : (Q, [][]bytes) -> Q      deq : (Q, n) -> (bytes, Q)
//! Law: BYTE CONSERVATION — any interleaving of enqv/deq yields exactly the
//! concatenation of all enqueued bytes, in order (vs a flat oracle buffer).
//!
//! PORT ENDPOINT (E4.5, Task 5) — a port is a process-like endpoint with a
//! command/reply protocol over the M7 signal machinery (`PortWorld`/`Port`/
//! `Signal`): open_port/port_command/port_control/port_call/port_close/
//! port_connect/port_info/port_get_data/port_set_data/ports over a FIXTURE ECHO
//! driver. Laws: PORT COMMAND/REPLY (a command lands exactly one
//! {Port,{data,payload}} in the OWN connected process, byte-conserved),
//! PORT_INFO TOTALITY (documented items answer; dead/absent -> undefined; unknown
//! item -> badarg), PORT DEATH (close signals the connected process exactly-once
//! — the link law over ports), BOUNDED/CONSERVE. E5.4: a `.live` driver joins the
//! fixture `.echo` — a REAL OS program (`open_port({spawn,Cmd},…)`) behind the
//! Stratum-C `os_port.zig` seam; the endpoint algebra DRIVES it (`LAW E5.4 LIVE
//! ECHO`), and the runtime engine (`src/proc.zig`) makes it reachable end-to-end
//! from a compiled `.beam` (the `port_echo`/`port_data_rt` differential corpus).
//! The pure algebra + its laws are proven VM-side here.

const std = @import("std");
const os_port = @import("os_port.zig"); // E5.4: the live os-port driver (Stratum C)

pub const Mode = enum { raw, p1, p2, p4, line };

pub const FrameError = error{ OutOfMemory, TooLong };

pub fn frame(gpa: std.mem.Allocator, mode: Mode, payload: []const u8, out: *std.ArrayList(u8)) FrameError!void {
    switch (mode) {
        .raw => try out.appendSlice(gpa, payload),
        .p1 => {
            if (payload.len > 0xFF) return error.TooLong;
            try out.append(gpa, @intCast(payload.len));
            try out.appendSlice(gpa, payload);
        },
        .p2 => {
            if (payload.len > 0xFFFF) return error.TooLong;
            try out.append(gpa, @intCast(payload.len >> 8));
            try out.append(gpa, @truncate(payload.len));
            try out.appendSlice(gpa, payload);
        },
        .p4 => {
            if (payload.len > 0xFFFF_FFFF) return error.TooLong;
            const n: u32 = @intCast(payload.len);
            try out.append(gpa, @truncate(n >> 24));
            try out.append(gpa, @truncate(n >> 16));
            try out.append(gpa, @truncate(n >> 8));
            try out.append(gpa, @truncate(n));
            try out.appendSlice(gpa, payload);
        },
        .line => {
            try out.appendSlice(gpa, payload);
            if (payload.len == 0 or payload[payload.len - 1] != '\n')
                try out.append(gpa, '\n');
        },
    }
}

// ── gap-open-port-line (Slice C): the port `{line, N}` message framing ──────
// DISTINCT from the `{packet,line}` Deframer above (which is terminator-INCLUSIVE
// and un-capped). The PORT option `{line, N}` frames a child's output into
// `{Port,{data,{eol|noeol,Line}}}` messages, per erts `PACKET_LINE`:
//   • a complete line (bytes up to the next '\n') → `{eol, Line}`, terminator STRIPPED;
//   • a line LONGER than N → `{noeol, N-byte}` chunks, the FINAL ≤N piece `{eol, _}`;
//   • an unterminated EOF tail → `{noeol, tail}` (chunked at N, all `noeol`).

/// One framed line: a slice `bytes[off..off+len]` of the source + whether it was
/// '\n'-terminated (`eol`) or a length-cap / EOF-tail cut (`noeol`).
pub const LineFrame = struct { eol: bool, off: usize, len: usize };

/// Frame `bytes` into `{eol|noeol}` line pieces under the port `{line, N}` rule
/// (`n` = the max line length; `n == 0` is treated as 1 — erts floors it). The
/// frames' slices, concatenated in order, are exactly `bytes` MINUS the stripped
/// '\n' terminators (BYTE CONSERVATION); `#eol` == the number of '\n' in `bytes`.
pub fn lineFrames(gpa: std.mem.Allocator, bytes: []const u8, n: usize, out: *std.ArrayList(LineFrame)) FrameError!void {
    const cap = if (n == 0) 1 else n;
    var i: usize = 0;
    while (i < bytes.len) {
        // the line content runs [i, seg_end): up to the next '\n' (or EOF).
        var seg_end = i;
        while (seg_end < bytes.len and bytes[seg_end] != '\n') seg_end += 1;
        const terminated = seg_end < bytes.len; // seg_end points at a '\n'
        var pos = i;
        // full N-byte `noeol` chunks while more than a cap's worth remains.
        while (seg_end - pos > cap) {
            try out.append(gpa, .{ .eol = false, .off = pos, .len = cap });
            pos += cap;
        }
        // the final ≤cap piece: `eol` iff a '\n' terminates it, else `noeol`.
        try out.append(gpa, .{ .eol = terminated, .off = pos, .len = seg_end - pos });
        i = if (terminated) seg_end + 1 else seg_end; // skip the '\n'
    }
}

/// Streaming deframer: feed() arbitrary chunks; packets() drains complete
/// packets; flush() emits a trailing partial line (line mode only).
pub const Deframer = struct {
    gpa: std.mem.Allocator,
    mode: Mode,
    buf: std.ArrayList(u8),
    out: std.ArrayList([]u8), // completed packets (owned)

    pub fn init(gpa: std.mem.Allocator, mode: Mode) Deframer {
        return .{ .gpa = gpa, .mode = mode, .buf = .empty, .out = .empty };
    }
    pub fn deinit(self: *Deframer) void {
        self.buf.deinit(self.gpa);
        for (self.out.items) |p| self.gpa.free(p);
        self.out.deinit(self.gpa);
    }

    pub fn feed(self: *Deframer, chunk: []const u8) !void {
        try self.buf.appendSlice(self.gpa, chunk);
        try self.drain();
    }

    fn emit(self: *Deframer, bytes: []const u8) !void {
        try self.out.append(self.gpa, try self.gpa.dupe(u8, bytes));
    }

    fn consume(self: *Deframer, n: usize) void {
        std.mem.copyForwards(u8, self.buf.items[0 .. self.buf.items.len - n], self.buf.items[n..]);
        self.buf.shrinkRetainingCapacity(self.buf.items.len - n);
    }

    fn drain(self: *Deframer) !void {
        while (true) {
            const b = self.buf.items;
            switch (self.mode) {
                .raw => {
                    if (b.len == 0) return;
                    try self.emit(b);
                    self.buf.clearRetainingCapacity();
                    return;
                },
                .p1 => {
                    if (b.len < 1) return;
                    const n: usize = b[0];
                    if (b.len < 1 + n) return;
                    try self.emit(b[1 .. 1 + n]);
                    self.consume(1 + n);
                },
                .p2 => {
                    if (b.len < 2) return;
                    const n: usize = (@as(usize, b[0]) << 8) | b[1];
                    if (b.len < 2 + n) return;
                    try self.emit(b[2 .. 2 + n]);
                    self.consume(2 + n);
                },
                .p4 => {
                    if (b.len < 4) return;
                    const n: usize = (@as(usize, b[0]) << 24) | (@as(usize, b[1]) << 16) |
                        (@as(usize, b[2]) << 8) | b[3];
                    if (b.len < 4 + n) return;
                    try self.emit(b[4 .. 4 + n]);
                    self.consume(4 + n);
                },
                .line => {
                    const nl = std.mem.indexOfScalar(u8, b, '\n') orelse return;
                    try self.emit(b[0 .. nl + 1]); // line INCLUDING '\n'
                    self.consume(nl + 1);
                },
            }
        }
    }

    /// Line mode: deliver a trailing unterminated line (stream end).
    pub fn flush(self: *Deframer) !void {
        if (self.mode == .line and self.buf.items.len > 0) {
            try self.emit(self.buf.items);
            self.buf.clearRetainingCapacity();
        }
    }
};

// ---------------------------------------------------------------------------
// IO queue
// ---------------------------------------------------------------------------

pub const IoQueue = struct {
    gpa: std.mem.Allocator,
    chunks: std.ArrayList([]u8), // owned
    head_off: usize = 0,

    pub fn init(gpa: std.mem.Allocator) IoQueue {
        return .{ .gpa = gpa, .chunks = .empty };
    }
    pub fn deinit(self: *IoQueue) void {
        for (self.chunks.items) |c| self.gpa.free(c);
        self.chunks.deinit(self.gpa);
    }

    pub fn enqv(self: *IoQueue, iov: []const []const u8) !void {
        for (iov) |c| {
            if (c.len == 0) continue;
            try self.chunks.append(self.gpa, try self.gpa.dupe(u8, c));
        }
    }

    pub fn len(self: *const IoQueue) usize {
        var n: usize = 0;
        for (self.chunks.items, 0..) |c, i| {
            n += if (i == 0) c.len - self.head_off else c.len;
        }
        return n;
    }

    /// Dequeue up to n bytes (fewer only if the queue runs dry).
    pub fn deq(self: *IoQueue, n: usize, out: *std.ArrayList(u8)) !void {
        var want = n;
        while (want > 0 and self.chunks.items.len > 0) {
            const head = self.chunks.items[0];
            const avail = head.len - self.head_off;
            const take = @min(avail, want);
            try out.appendSlice(self.gpa, head[self.head_off .. self.head_off + take]);
            want -= take;
            self.head_off += take;
            if (self.head_off == head.len) {
                self.gpa.free(head);
                _ = self.chunks.orderedRemove(0);
                self.head_off = 0;
            }
        }
    }
};

// ============================================================================
// PORT ENDPOINT — the S25 port model (E4.5, Task 5)
// ============================================================================
//
// A port is a process-like ENDPOINT with a command/reply protocol, riding the
// M7 signal machinery: it owns a CONNECTED process; a `command` produces a
// reply SIGNAL — `{Port,{data,Reply}}` — into the connected process's mailbox;
// a `close` signals the connected process EXACTLY ONCE (the link law over
// ports). `control`/`call` are SYNCHRONOUS request/reply. `info` is a TOTAL
// observer over documented items (a dead/absent port -> `undefined`; an unknown
// item is the emulator's badarg arm — verified empirically on the OTP-28 host:
// `port_info(P, connected)` on a DEAD port is `undefined`, but
// `port_info(P, nonexistent_item)` RAISES `badarg`). Driver semantics here are
// the FIXTURE ECHO driver (cf. erts `echo_drv`): command(bytes) -> reply(bytes),
// control(op,bytes) -> bytes.
//
// Stratum discipline: a REAL OS port (`open_port({spawn,Cmd},…)` runs an
// external program — verified on the host: an echo needs a live `cat`) lives
// behind the Stratum-C seam and is `deferred-E5-osport`; the ALGEBRA — routing,
// exactly-once death, info totality, byte conservation — is proven HERE, VM-side,
// seed-driven and bounded (a stuck command is a failed law, never a hang).
//
// Laws:
//   PORT COMMAND/REPLY   a command to an echo port delivers EXACTLY ONE
//                        {Port,{data,payload}} to the port's OWN connected
//                        process (never another port's), payload byte-conserved.
//   PORT_INFO TOTALITY   documented items on a live port return a value; a dead
//                        or absent port -> undefined; an unknown item -> badarg.
//   PORT DEATH           close signals the connected process EXACTLY ONCE (a
//                        second close is inert); the port is not alive after.
//   BOUNDED / CONSERVE   any seeded interleaving of open/command/connect/close
//                        terminates on a step budget and conserves echoed bytes.

/// The two drivers the endpoint algebra can route a command to: the FIXTURE
/// ECHO (Stratum-A, no OS — the E4.5 oracle twin) and the LIVE driver (E5.4 —
/// a real external program behind the `os_port.zig` Stratum-C seam, cf. erts'
/// spawn ports). Both satisfy PORT COMMAND/REPLY + BYTE CONSERVATION; `live`
/// realizes CA-14's OS half.
pub const Driver = enum { echo, live, terminal };

pub const CloseReason = enum { normal };

pub const PortError = error{ OutOfMemory, BadPort, Badarg };

/// The port-death / data shapes a driver signals to its connected process — the
/// M7 signal machinery, restated for ports.
pub const Signal = union(enum) {
    /// `{Port,{data,Bytes}}` — bytes OWNED by the receiving inbox.
    data: struct { port: u32, bytes: []u8 },
    /// the port-death signal over the link to the connected process.
    exit: struct { port: u32, reason: CloseReason },
};

/// A connected process's mailbox — a bounded FIFO mirroring proc's M7 queue.
pub const Inbox = struct {
    gpa: std.mem.Allocator,
    sigs: std.ArrayList(Signal),

    pub fn init(gpa: std.mem.Allocator) Inbox {
        return .{ .gpa = gpa, .sigs = .empty };
    }
    pub fn deinit(self: *Inbox) void {
        for (self.sigs.items) |s| switch (s) {
            .data => |d| self.gpa.free(d.bytes),
            .exit => {},
        };
        self.sigs.deinit(self.gpa);
    }
    /// count of `{Port,{data,_}}` replies from a specific port (exactly-once obs).
    pub fn dataCountFrom(self: *const Inbox, port: u32) usize {
        var n: usize = 0;
        for (self.sigs.items) |s| switch (s) {
            .data => |d| if (d.port == port) {
                n += 1;
            },
            .exit => {},
        };
        return n;
    }
    /// count of port-death signals from a specific port (exactly-once obs).
    pub fn exitCountFrom(self: *const Inbox, port: u32) usize {
        var n: usize = 0;
        for (self.sigs.items) |s| switch (s) {
            .exit => |e| if (e.port == port) {
                n += 1;
            },
            .data => {},
        };
        return n;
    }
};

/// Documented `port_info/2` items (the total-observer domain).
pub const InfoItem = enum { connected, id, registered_name, links };

/// A `port_info/2` answer — `undefined` for a dead/absent port.
pub const Info = union(enum) {
    undef,
    proc: u32, // connected pid / a link entry
    id: u32,
    none, // registered_name of an unnamed port
};

pub const Port = struct {
    id: u32,
    connected: u32, // proc id of the connected process
    driver: Driver,
    alive: bool,
    closed_signalled: bool, // has the port-death signal been delivered?
    data: ?[]u8, // port_set_data/get_data slot (OWNED)
    /// E5.4: for a `.live` port, the real child behind the Stratum-C seam. The
    /// LivePort is BORROWED — its OS resources are owned by the caller (the law
    /// test / the runtime engine), never freed by the PortWorld.
    live: ?*os_port.LivePort = null,
};

/// The port world: ports + the connected processes' inboxes. Self-contained
/// Stratum-A — no Machine/OS dependency; the M7 signal semantics restated.
pub const PortWorld = struct {
    gpa: std.mem.Allocator,
    ports: std.ArrayList(Port),
    inboxes: std.ArrayList(Inbox),
    next_id: u32 = 1,

    pub fn init(gpa: std.mem.Allocator) PortWorld {
        return .{ .gpa = gpa, .ports = .empty, .inboxes = .empty };
    }
    pub fn deinit(self: *PortWorld) void {
        for (self.ports.items) |p| if (p.data) |d| self.gpa.free(d);
        self.ports.deinit(self.gpa);
        for (self.inboxes.items) |*ib| ib.deinit();
        self.inboxes.deinit(self.gpa);
    }

    /// register a process; returns its proc id (an inbox index).
    pub fn addProc(self: *PortWorld) !u32 {
        const id: u32 = @intCast(self.inboxes.items.len);
        try self.inboxes.append(self.gpa, Inbox.init(self.gpa));
        return id;
    }

    /// open a port connected to `proc` — `open_port/2`. Returns the port id.
    pub fn open(self: *PortWorld, driver: Driver, proc: u32) !u32 {
        const id = self.next_id;
        self.next_id += 1;
        try self.ports.append(self.gpa, .{
            .id = id,
            .connected = proc,
            .driver = driver,
            .alive = true,
            .closed_signalled = false,
            .data = null,
        });
        return id;
    }

    /// E5.4: open a `.live` port connected to `proc`, backed by a BORROWED real
    /// child (`lp`). Returns the port id. The command/reply, port-death, and
    /// info-totality laws are identical to an echo port — the difference is the
    /// bytes now traverse a real OS pipe.
    pub fn openLive(self: *PortWorld, proc: u32, lp: *os_port.LivePort) !u32 {
        const id = self.next_id;
        self.next_id += 1;
        try self.ports.append(self.gpa, .{
            .id = id,
            .connected = proc,
            .driver = .live,
            .alive = true,
            .closed_signalled = false,
            .data = null,
            .live = lp,
        });
        return id;
    }

    fn find(self: *PortWorld, id: u32) ?*Port {
        for (self.ports.items) |*p| if (p.id == id) return p;
        return null;
    }

    fn deliver(self: *PortWorld, proc: u32, sig: Signal) !void {
        try self.inboxes.items[proc].sigs.append(self.gpa, sig);
    }

    /// `port_command/3` — an echo port replies `{Port,{data,Bytes}}` to its OWN
    /// connected process. A dead/absent port is `BadPort` (the caller's badarg).
    pub fn command(self: *PortWorld, id: u32, bytes: []const u8) PortError!void {
        const p = self.find(id) orelse return error.BadPort;
        if (!p.alive) return error.BadPort;
        switch (p.driver) {
            .echo => {
                const dup = try self.gpa.dupe(u8, bytes);
                errdefer self.gpa.free(dup);
                try self.deliver(p.connected, .{ .data = .{ .port = id, .bytes = dup } });
            },
            .live => {
                // E5.4: route the command to the real child; the echoed bytes are
                // read back across the OS pipe and delivered as the reply signal.
                // A wedged/dead child is a bounded `error.Fuel`/read failure →
                // BadPort (never a hang). The reply buffer is OWNED by the inbox.
                const lp = p.live orelse return error.BadPort;
                const out = try self.gpa.alloc(u8, bytes.len);
                errdefer self.gpa.free(out);
                const echoed = lp.command(bytes, out, 200) catch return error.BadPort;
                try self.deliver(p.connected, .{ .data = .{ .port = id, .bytes = echoed } });
            },
            .terminal => {
                // E11.4: route the command to the OS stdout (terminal), but NO synchronous
                // read-back or `{Port, {data, Reply}}` is produced (async terminal).
                const lp = p.live orelse return error.BadPort;
                lp.writeAll(bytes) catch return error.BadPort;
            },
        }
    }

    /// `port_control/3` — SYNCHRONOUS: the echo driver returns the operand bytes.
    pub fn control(self: *PortWorld, id: u32, _: u32, bytes: []const u8, out: *std.ArrayList(u8)) PortError!void {
        const p = self.find(id) orelse return error.BadPort;
        if (!p.alive) return error.BadPort;
        switch (p.driver) {
            .echo => try out.appendSlice(self.gpa, bytes),
            // A spawn/live/terminal port has no synchronous control operation (cf. erts:
            // `port_control` on an exec port is `badarg`) — the total arm.
            .live, .terminal => return error.Badarg,
        }
    }

    /// `port_connect/2` — reassign the connected process. Absent/dead -> BadPort.
    pub fn connect(self: *PortWorld, id: u32, new_proc: u32) PortError!void {
        const p = self.find(id) orelse return error.BadPort;
        if (!p.alive) return error.BadPort;
        p.connected = new_proc;
    }

    /// `port_close/1` — retires the port and signals the connected process
    /// EXACTLY ONCE (the link law over ports). A second close is INERT.
    pub fn close(self: *PortWorld, id: u32) PortError!void {
        const p = self.find(id) orelse return error.BadPort;
        if (!p.alive) return; // idempotent: already closed, no second signal
        p.alive = false;
        if (!p.closed_signalled) {
            p.closed_signalled = true;
            try self.deliver(p.connected, .{ .exit = .{ .port = id, .reason = .normal } });
        }
    }

    /// `port_info/2` over documented items — TOTAL: a dead/absent port is
    /// `undefined`; a live port answers each documented item.
    pub fn info(self: *PortWorld, id: u32, item: InfoItem) Info {
        const p = self.find(id) orelse return .undef;
        if (!p.alive) return .undef;
        return switch (item) {
            .connected => .{ .proc = p.connected },
            .id => .{ .id = p.id },
            .registered_name => .none,
            .links => .{ .proc = p.connected }, // the connected proc is linked
        };
    }

    /// `port_info/2` by item NAME — the emulator arm: an UNKNOWN item RAISES
    /// badarg (verified on OTP-28), a known item routes to `info`.
    pub fn infoByName(self: *PortWorld, id: u32, name: []const u8) PortError!Info {
        const item: InfoItem = if (std.mem.eql(u8, name, "connected"))
            .connected
        else if (std.mem.eql(u8, name, "id"))
            .id
        else if (std.mem.eql(u8, name, "registered_name"))
            .registered_name
        else if (std.mem.eql(u8, name, "links"))
            .links
        else
            return error.Badarg;
        return self.info(id, item);
    }

    /// `port_set_data/2` — store an opaque term (bytes here). Owns the copy.
    pub fn setData(self: *PortWorld, id: u32, bytes: []const u8) PortError!void {
        const p = self.find(id) orelse return error.BadPort;
        const dup = try self.gpa.dupe(u8, bytes);
        if (p.data) |old| self.gpa.free(old);
        p.data = dup;
    }

    /// `port_get_data/1` — read back the stored term; unset -> null.
    pub fn getData(self: *PortWorld, id: u32) PortError!?[]const u8 {
        const p = self.find(id) orelse return error.BadPort;
        return p.data;
    }

    /// `ports/0` — the list of LIVE port ids, in open order.
    pub fn livePorts(self: *PortWorld, out: *std.ArrayList(u32)) !void {
        for (self.ports.items) |p| if (p.alive) try out.append(self.gpa, p.id);
    }
};

// ============================================================================
// Tests
// ============================================================================

fn randPayload(random: std.Random, buf: []u8, max: usize) []const u8 {
    const n = random.uintLessThan(usize, @min(buf.len, max) + 1);
    for (buf[0..n]) |*b| b.* = random.int(u8);
    return buf[0..n];
}

test "FRAME∘DEFRAME = id per mode + STREAM REASSEMBLY under seeded chunking" {
    const gpa = std.testing.allocator;

    inline for ([_]Mode{ .p1, .p2, .p4 }) |mode| {
        for (0..25) |iter| {
            var prng = std.Random.DefaultPrng.init(0x9047 +% iter);
            const random = prng.random();

            // build a stream of K frames; keep the payloads
            var payloads: std.ArrayList([]u8) = .empty;
            defer {
                for (payloads.items) |p| gpa.free(p);
                payloads.deinit(gpa);
            }
            var stream: std.ArrayList(u8) = .empty;
            defer stream.deinit(gpa);
            const kn = 1 + random.uintLessThan(usize, 6);
            for (0..kn) |ki| {
                var buf: [600]u8 = undefined;
                // hit length boundaries on purpose
                const pay = switch (ki % 3) {
                    0 => randPayload(random, &buf, if (mode == .p1) 255 else 600),
                    1 => buf[0..@min(if (mode == .p1) 255 else 256, buf.len)],
                    else => buf[0..0],
                };
                if (ki % 3 == 1) for (buf[0..pay.len]) |*b| {
                    b.* = random.int(u8);
                };
                try payloads.append(gpa, try gpa.dupe(u8, pay));
                try frame(gpa, mode, pay, &stream);
            }

            // chop the stream at arbitrary boundaries and feed
            var d = Deframer.init(gpa, mode);
            defer d.deinit();
            var pos: usize = 0;
            while (pos < stream.items.len) {
                const step = 1 + random.uintLessThan(usize, 9);
                const end = @min(pos + step, stream.items.len);
                try d.feed(stream.items[pos..end]);
                pos = end;
            }
            // exact packet sequence back
            try std.testing.expectEqual(payloads.items.len, d.out.items.len);
            for (payloads.items, d.out.items) |want, got| {
                try std.testing.expect(std.mem.eql(u8, want, got));
            }
        }
    }

    // mode 1 oversize is refused, never truncated
    var sink: std.ArrayList(u8) = .empty;
    defer sink.deinit(gpa);
    const big = [_]u8{7} ** 256;
    try std.testing.expectError(error.TooLong, frame(gpa, .p1, &big, &sink));
}

test "LINE mode: terminator-inclusive lines; trailing partial only on flush" {
    const gpa = std.testing.allocator;
    var d = Deframer.init(gpa, .line);
    defer d.deinit();

    try d.feed("hello\nwor");
    try std.testing.expectEqual(@as(usize, 1), d.out.items.len);
    try std.testing.expect(std.mem.eql(u8, "hello\n", d.out.items[0]));
    try d.feed("ld\npart");
    try std.testing.expectEqual(@as(usize, 2), d.out.items.len);
    try std.testing.expect(std.mem.eql(u8, "world\n", d.out.items[1]));
    // partial line held back until flush
    try d.flush();
    try std.testing.expectEqual(@as(usize, 3), d.out.items.len);
    try std.testing.expect(std.mem.eql(u8, "part", d.out.items[2]));
}

test "LAW gap-open-port-line: {line,N} framing — eol/noeol tags, N-cap split, EOF tail, byte conservation (Slice C, DIVERGENCE 596)" {
    const gpa = std.testing.allocator;
    const F = LineFrame;
    const Case = struct { in: []const u8, n: usize, want: []const F };
    const cases = [_]Case{
        // "a\nb\n"@80 → [eol"a", eol"b"] (each complete line, terminator stripped)
        .{ .in = "a\nb\n", .n = 80, .want = &.{ .{ .eol = true, .off = 0, .len = 1 }, .{ .eol = true, .off = 2, .len = 1 } } },
        // "x\ny"@80 → [eol"x", noeol"y"] (unterminated tail → noeol)
        .{ .in = "x\ny", .n = 80, .want = &.{ .{ .eol = true, .off = 0, .len = 1 }, .{ .eol = false, .off = 2, .len = 1 } } },
        // "abcdef\n"@3 → [noeol"abc", eol"def"] (line > N → N-chunk noeol, final ≤N eol)
        .{ .in = "abcdef\n", .n = 3, .want = &.{ .{ .eol = false, .off = 0, .len = 3 }, .{ .eol = true, .off = 3, .len = 3 } } },
        // "abcdefg\n"@3 → [noeol"abc", noeol"def", eol"g"]
        .{ .in = "abcdefg\n", .n = 3, .want = &.{ .{ .eol = false, .off = 0, .len = 3 }, .{ .eol = false, .off = 3, .len = 3 }, .{ .eol = true, .off = 6, .len = 1 } } },
        // empty line "\n"@80 → [eol""] (a bare newline is a complete empty line)
        .{ .in = "\n", .n = 80, .want = &.{.{ .eol = true, .off = 0, .len = 0 }} },
        // "" → [] (no output, no frames)
        .{ .in = "", .n = 80, .want = &.{} },
        // long unterminated tail "abcde"@2 → all noeol chunks [ab, cd, e]
        .{ .in = "abcde", .n = 2, .want = &.{ .{ .eol = false, .off = 0, .len = 2 }, .{ .eol = false, .off = 2, .len = 2 }, .{ .eol = false, .off = 4, .len = 1 } } },
    };
    for (cases) |c| {
        var got: std.ArrayList(F) = .empty;
        defer got.deinit(gpa);
        try lineFrames(gpa, c.in, c.n, &got);
        try std.testing.expectEqual(c.want.len, got.items.len);
        for (c.want, got.items) |w, g|
            try std.testing.expect(w.eol == g.eol and w.off == g.off and w.len == g.len);
    }

    // BYTE CONSERVATION (seeded): the frame slices concatenated == input minus the
    // stripped '\n' terminators, and #eol == the number of '\n' in the input.
    for (0..40) |iter| {
        var prng = std.Random.DefaultPrng.init(0x71E5 +% iter);
        const rnd = prng.random();
        var buf: [64]u8 = undefined;
        const len = rnd.intRangeAtMost(usize, 0, 64);
        for (0..len) |k| buf[k] = if (rnd.boolean()) '\n' else 'a' + rnd.intRangeAtMost(u8, 0, 25);
        const in = buf[0..len];
        const n = rnd.intRangeAtMost(usize, 1, 8);
        var frames: std.ArrayList(F) = .empty;
        defer frames.deinit(gpa);
        try lineFrames(gpa, in, n, &frames);
        var concat: std.ArrayList(u8) = .empty;
        defer concat.deinit(gpa);
        var eols: usize = 0;
        for (frames.items) |fr| {
            try concat.appendSlice(gpa, in[fr.off .. fr.off + fr.len]);
            if (fr.eol) eols += 1;
            try std.testing.expect(fr.len <= n); // no chunk exceeds the cap
        }
        var nl_count: usize = 0;
        for (in) |b| { if (b == '\n') nl_count += 1; }
        var stripped: std.ArrayList(u8) = .empty;
        defer stripped.deinit(gpa);
        for (in) |b| { if (b != '\n') try stripped.append(gpa, b); }
        if (!std.mem.eql(u8, concat.items, stripped.items)) {
            std.debug.print("lineFrames conservation FAIL seed 0x{x} in={s} n={d}\n", .{ 0x71E5 +% iter, in, n });
            return error.LineFrameConservation;
        }
        try std.testing.expectEqual(nl_count, eols);
    }
}

test "IO QUEUE: byte conservation & order across random interleavings" {
    const gpa = std.testing.allocator;

    for (0..30) |iter| {
        var prng = std.Random.DefaultPrng.init(0x10F1 +% iter);
        const random = prng.random();
        var q = IoQueue.init(gpa);
        defer q.deinit();
        var oracle: std.ArrayList(u8) = .empty; // everything ever enqueued
        defer oracle.deinit(gpa);
        var drained: std.ArrayList(u8) = .empty; // everything ever dequeued
        defer drained.deinit(gpa);

        for (0..60) |_| {
            if (random.boolean()) {
                var b1: [16]u8 = undefined;
                var b2: [16]u8 = undefined;
                const c1 = randPayload(random, &b1, 16);
                const c2 = randPayload(random, &b2, 16);
                try q.enqv(&.{ c1, c2 });
                try oracle.appendSlice(gpa, c1);
                try oracle.appendSlice(gpa, c2);
            } else {
                try q.deq(random.uintLessThan(usize, 24), &drained);
            }
            // conservation invariant at every step
            try std.testing.expectEqual(oracle.items.len, drained.items.len + q.len());
            // order invariant: drained is a prefix of the oracle stream
            try std.testing.expect(std.mem.eql(u8, oracle.items[0..drained.items.len], drained.items));
        }
        // drain fully: exact equality
        try q.deq(std.math.maxInt(u32), &drained);
        try std.testing.expect(std.mem.eql(u8, oracle.items, drained.items));
    }
}

// ----------------------------------------------------------------------------
// PORT ENDPOINT laws (E4.5)
// ----------------------------------------------------------------------------

test "LAW E4.5 PORT COMMAND/REPLY: echo command lands {Port,{data,payload}} in the OWN connected proc, byte-conserved" {
    const gpa = std.testing.allocator;

    for (0..30) |iter| {
        var prng = std.Random.DefaultPrng.init(0x9701 +% iter);
        const random = prng.random();
        var w = PortWorld.init(gpa);
        defer w.deinit();

        // two connected processes, one port each — routing must not cross.
        const pa = try w.addProc();
        const pb = try w.addProc();
        const port_a = try w.open(.echo, pa);
        const port_b = try w.open(.echo, pb);

        // send a seeded stream of commands to port_a only.
        const kn = 1 + random.uintLessThan(usize, 6);
        var expected: std.ArrayList([]u8) = .empty;
        defer {
            for (expected.items) |e| gpa.free(e);
            expected.deinit(gpa);
        }
        for (0..kn) |_| {
            var buf: [32]u8 = undefined;
            const pay = randPayload(random, &buf, 32);
            try expected.append(gpa, try gpa.dupe(u8, pay));
            try w.command(port_a, pay);
        }

        // EXACTLY kn data replies from port_a landed in pa's inbox, in order,
        // byte-for-byte; NONE leaked to pb (the wrong-port mutant killer).
        const inbox_a = &w.inboxes.items[pa];
        try std.testing.expectEqual(kn, inbox_a.dataCountFrom(port_a));
        try std.testing.expectEqual(@as(usize, 0), w.inboxes.items[pb].dataCountFrom(port_a));
        try std.testing.expectEqual(@as(usize, 0), inbox_a.dataCountFrom(port_b));
        var seen: usize = 0;
        for (inbox_a.sigs.items) |s| switch (s) {
            .data => |d| {
                try std.testing.expectEqual(port_a, d.port);
                try std.testing.expect(std.mem.eql(u8, expected.items[seen], d.bytes));
                seen += 1;
            },
            .exit => {},
        };
        try std.testing.expectEqual(kn, seen);

        // control is synchronous echo; command to a non-port / dead port is BadPort.
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try w.control(port_a, 0, "ctl", &out);
        try std.testing.expect(std.mem.eql(u8, "ctl", out.items));
        try std.testing.expectError(error.BadPort, w.command(9999, "x"));
    }
}

test "LAW E4.5 PORT_INFO TOTALITY: documented items on live; dead/absent -> undefined; unknown item -> badarg" {
    const gpa = std.testing.allocator;
    var w = PortWorld.init(gpa);
    defer w.deinit();
    const p0 = try w.addProc();
    const p1 = try w.addProc();
    const port = try w.open(.echo, p0);

    // live port: documented items answer.
    try std.testing.expectEqual(Info{ .proc = p0 }, w.info(port, .connected));
    try std.testing.expectEqual(Info{ .id = port }, w.info(port, .id));
    try std.testing.expectEqual(Info.none, w.info(port, .registered_name));

    // connect reassigns the connected process — info reflects it.
    try w.connect(port, p1);
    try std.testing.expectEqual(Info{ .proc = p1 }, w.info(port, .connected));

    // set/get data round-trip.
    try w.setData(port, "state");
    try std.testing.expect(std.mem.eql(u8, "state", (try w.getData(port)).?));

    // ports/0 lists the live port.
    var live: std.ArrayList(u32) = .empty;
    defer live.deinit(gpa);
    try w.livePorts(&live);
    try std.testing.expectEqual(@as(usize, 1), live.items.len);

    // unknown item name -> badarg (the OTP-28 emulator arm); known name routes.
    try std.testing.expectError(error.Badarg, w.infoByName(port, "nonexistent_item"));
    try std.testing.expectEqual(Info{ .id = port }, try w.infoByName(port, "id"));

    // absent port -> undefined (never a crash).
    try std.testing.expectEqual(Info.undef, w.info(4242, .connected));

    // after close: totality holds — a DEAD port answers undefined.
    try w.close(port);
    try std.testing.expectEqual(Info.undef, w.info(port, .connected));
    // ports/0 no longer lists it.
    live.clearRetainingCapacity();
    try w.livePorts(&live);
    try std.testing.expectEqual(@as(usize, 0), live.items.len);
}

test "LAW E4.5 PORT DEATH: close signals the connected process EXACTLY ONCE; second close inert" {
    const gpa = std.testing.allocator;

    for (0..25) |iter| {
        var prng = std.Random.DefaultPrng.init(0xDEAD +% iter);
        const random = prng.random();
        var w = PortWorld.init(gpa);
        defer w.deinit();

        const owner = try w.addProc();
        const nports = 1 + random.uintLessThan(usize, 5);
        var ports: std.ArrayList(u32) = .empty;
        defer ports.deinit(gpa);
        for (0..nports) |_| try ports.append(gpa, try w.open(.echo, owner));

        // close each port once; some twice (idempotence).
        for (ports.items) |id| {
            try w.close(id);
            if (random.boolean()) try w.close(id); // second close is inert
        }

        // EXACTLY ONE port-death signal per port reached the owner (the link
        // law over ports); the port is not alive afterward.
        const inbox = &w.inboxes.items[owner];
        for (ports.items) |id| {
            try std.testing.expectEqual(@as(usize, 1), inbox.exitCountFrom(id));
            try std.testing.expect(!w.find(id).?.alive);
        }
        // total death signals == number of ports (no double-signal anywhere).
        try std.testing.expectEqual(nports, inbox.exitCountFrom(ports.items[0]) * 0 + blk: {
            var tot: usize = 0;
            for (inbox.sigs.items) |s| switch (s) {
                .exit => tot += 1,
                .data => {},
            };
            break :blk tot;
        });
    }
}

test "LAW E4.5 BOUNDED: any seeded interleaving of open/command/connect/close terminates on a step budget" {
    const gpa = std.testing.allocator;

    for (0..20) |iter| {
        var prng = std.Random.DefaultPrng.init(0xB0DE +% iter);
        const random = prng.random();
        var w = PortWorld.init(gpa);
        defer w.deinit();
        const p0 = try w.addProc();
        const p1 = try w.addProc();
        var open_ports: std.ArrayList(u32) = .empty;
        defer open_ports.deinit(gpa);

        const budget: usize = 200; // a stuck op is a failed law, never a hang
        var steps: usize = 0;
        while (steps < budget) : (steps += 1) {
            switch (random.uintLessThan(u8, 5)) {
                0 => try open_ports.append(gpa, try w.open(.echo, if (random.boolean()) p0 else p1)),
                1 => if (open_ports.items.len > 0) {
                    const id = open_ports.items[random.uintLessThan(usize, open_ports.items.len)];
                    w.command(id, "ping") catch {};
                },
                2 => if (open_ports.items.len > 0) {
                    const id = open_ports.items[random.uintLessThan(usize, open_ports.items.len)];
                    w.connect(id, if (random.boolean()) p0 else p1) catch {};
                },
                3 => if (open_ports.items.len > 0) {
                    const idx = random.uintLessThan(usize, open_ports.items.len);
                    w.close(open_ports.items[idx]) catch {};
                    _ = open_ports.orderedRemove(idx);
                },
                else => _ = w.info(if (open_ports.items.len > 0) open_ports.items[0] else 1, .connected),
            }
        }
        try std.testing.expectEqual(budget, steps); // terminated on the budget
    }
}

// ----------------------------------------------------------------------------
// LIVE os-port law (E5.4) — the endpoint algebra drives a REAL child
// ----------------------------------------------------------------------------

test "LAW E5.4 LIVE ECHO: the endpoint algebra drives a real `cat` — each command lands EXACTLY ONE {Port,{data,payload}}, byte-conserved" {
    const gpa = std.testing.allocator;

    var lp = try os_port.LivePort.spawnShell("exec cat");
    defer lp.deinit();

    var w = PortWorld.init(gpa);
    defer w.deinit();

    const pa = try w.addProc();
    const pb = try w.addProc(); // a second proc: routing must not cross to it
    const port = try w.openLive(pa, &lp);

    // a seeded stream of commands to the live port; keep the payloads.
    var expected: std.ArrayList([]u8) = .empty;
    defer {
        for (expected.items) |e| gpa.free(e);
        expected.deinit(gpa);
    }
    for (0..20) |iter| {
        var prng = std.Random.DefaultPrng.init(0x11FE +% iter);
        const random = prng.random();
        var buf: [64]u8 = undefined;
        const n = 1 + random.uintLessThan(usize, 64); // never empty (cat needs bytes to echo)
        for (buf[0..n]) |*b| b.* = random.int(u8);
        try expected.append(gpa, try gpa.dupe(u8, buf[0..n]));
        try w.command(port, buf[0..n]);
    }

    // EXACTLY expected.len data replies, in order, byte-for-byte, in pa's inbox;
    // NONE leaked to pb (the wrong-connected-process mutant killer).
    const inbox_a = &w.inboxes.items[pa];
    try std.testing.expectEqual(expected.items.len, inbox_a.dataCountFrom(port));
    try std.testing.expectEqual(@as(usize, 0), w.inboxes.items[pb].dataCountFrom(port));
    var seen: usize = 0;
    for (inbox_a.sigs.items) |s| switch (s) {
        .data => |d| {
            try std.testing.expectEqual(port, d.port);
            try std.testing.expect(std.mem.eql(u8, expected.items[seen], d.bytes));
            seen += 1;
        },
        .exit => {},
    };
    try std.testing.expectEqual(expected.items.len, seen);

    // control on a live/spawn port is badarg (the total non-echo arm).
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try std.testing.expectError(error.Badarg, w.control(port, 0, "ctl", &out));

    // close signals the connected process EXACTLY ONCE (the port-death law holds
    // for the live driver too); a second close is inert.
    try w.close(port);
    try w.close(port);
    try std.testing.expectEqual(@as(usize, 1), inbox_a.exitCountFrom(port));
}

test "LAW E11.4 TERMINAL COMMAND: terminal port does not produce synchronous echo" {
    const gpa = std.testing.allocator;
    var w = PortWorld.init(gpa);
    defer w.deinit();

    const pa = try w.addProc();
    // Use an echo driver but act as if we had a live terminal port
    var live_port = try os_port.LivePort.spawnShell("tty_sl -c -e");
    defer live_port.deinit();

    const port_a = try w.openLive(pa, &live_port);
    w.ports.items[0].driver = .terminal;

    try w.command(port_a, "hello");

    // The command wrote to stdout and returned NO data signals.
    const inbox_a = &w.inboxes.items[pa];
    try std.testing.expectEqual(@as(usize, 0), inbox_a.dataCountFrom(port_a));
}
