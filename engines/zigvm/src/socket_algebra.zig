//! # socket_algebra — real gen_tcp / gen_udp socket transport (Stratum C)
//!
//! ## What this is
//! The missing REAL socket floor for the `gen_tcp_udp_sockets` capability. The VM
//! already has the pure `{packet,N}` framing algebra (`port_algebra`, Stratum A,
//! proven FRAME∘DEFRAME=id + stream reassembly) and an in-memory completion
//! reactor (`substrate/reactor.zig`, Real[IO]); what it lacked was a transport that
//! moves bytes over an actual OS socket. This module is that transport — thin,
//! host-touching wrappers over `std.os.linux.{socket,bind,listen,accept,connect,
//! read,write,sendto,recvfrom,close}` (the same syscall idiom `dist.zig` already
//! uses for the distribution carrier), plus the COMPOSITION with `port_algebra`
//! that proves the end-to-end gen_tcp semantics.
//!
//! ## Stratum
//! Stratum C (substrate): real syscalls, quarantined. No Stratum-A law depends on
//! it. Its correctness is stated as an OBSERVATIONAL round-trip — bytes in ==
//! bytes out — not as anything about the physical fd. `vm_all` pulls it for its
//! law suite; the tests use the loopback interface only (deterministic, bounded,
//! zero-leak — every fd is `defer`-closed).
//!
//! ## Semantic domain
//!   A TCP socket is a bidirectional BYTE STREAM between two endpoints; a UDP
//!   socket is a DATAGRAM endpoint. The observable content is the byte sequence
//!   delivered, not the fd, port, or buffering. A gen_tcp connection in `{packet,N}`
//!   mode is this stream QUOTIENTED by the framing: message boundaries are carried
//!   by an N-byte big-endian length prefix (`port_algebra.Mode`).
//!
//! ## Encodings
//!   Oracle    = the identity: what you send is what the peer receives (a real
//!               loopback socket is its own oracle for a round-trip).
//!   Final     = the length-framed stream: `sendFramed`/`recvOnePacket` compose the
//!               proven `port_algebra` frame/Deframer with the transport.
//!
//! ## Laws (the RUNTIME-CAPABILITY-EQUIVALENCE evidence — a socket echo round-trips)
//!   TCP-ECHO         bytes written to one end of a connected loopback pair are
//!                    read verbatim at the other end (and echo back identically).
//!   FRAMED-ROUNDTRIP a message sent with `{packet,1|2|4}` over the real socket is
//!                    recovered EXACTLY by a Deframer on the peer — the message
//!                    boundary survives the byte stream (gen_tcp packet mode).
//!   REASSEMBLY       a payload larger than the read buffer is reassembled from the
//!                    stream's arbitrary chunk boundaries (partial-read handling).
//!   UDP-DATAGRAM     a datagram sent to a bound UDP socket is received with the
//!                    same payload (gen_udp send/recv).
//!   EPHEMERAL        binding port 0 yields a valid non-zero ephemeral port.
//!   FAIL-CLOSED      an op on a closed fd fails CLOSED (BadFd), never crashes.
//!   LIFECYCLE        (gap-socket-real-tcp) the DECOMPOSED gen_tcp lifecycle —
//!                    listen → connectPort → acceptTimeout → send → recvTimeout —
//!                    round-trips bytes both ways over the real loopback handles.
//!   CONNREFUSED      connect to a port nobody listens on fails ECONNREFUSED
//!                    (the OTP `{error,econnrefused}` shape).
//!   ACCEPT-BOUNDED   acceptTimeout/recvTimeout on an idle socket fail CLOSED with
//!                    Timeout within their bound — a blocking call NEVER hangs.
//!
//! ## Scope limits (documented, honest)
//! Loopback + blocking sockets, single-threaded pair setup (connect on loopback
//! completes without a peer thread; accept then succeeds). gap-socket-real-tcp
//! wires the HANDLE-based lifecycle up to the Vm socket TABLE + handler surface
//! (`proc.zig`: doGenTcpListen/Connect/Accept/Send/Recv/Close + gen_udp), proven
//! by a whole-VM `{ok,Socket}`/`{error,Posix}` round-trip. RESIDUAL (honest, as
//! the file-io slice): the erlang-level `gen_tcp:*`/`inet:*` NAME dispatch (a BIF
//! that emits the pending trap) is not yet plumbed, and active-mode `{tcp,S,Data}`
//! mailbox delivery + a live OTP-30 differential remain — the EQUIV→EQ follow-ons.

const std = @import("std");
const linux = std.os.linux;
const port_algebra = @import("port_algebra.zig");

pub const SockError = error{
    Socket, Bind, Listen, Connect, Accept, Send, Recv, SockName, SockOpt, BadFd, Closed,
    // gap-socket-real-tcp: the HANDLE-based gen_tcp lifecycle adds two shapes that
    // the OTP inet posix-error surface distinguishes: a connect to a port nobody
    // listens on (ECONNREFUSED) and a bounded accept/recv that fired its timeout
    // (a hang is a failed law — every blocking call is poll-bounded).
    ConnRefused, Timeout,
};

// ── loopback address ───────────────────────────────────────────────────────
fn loopbackAddr(port: u16) linux.sockaddr.in {
    return .{
        .port = std.mem.nativeToBig(u16, port),
        .addr = std.mem.nativeToBig(u32, 0x7F00_0001), // 127.0.0.1
    };
}

// ── TCP syscall wrappers (mirrors dist.zig; errno-checked, EINTR-retrying) ──
pub fn tcpSocket() SockError!i32 {
    while (true) {
        const rc = linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            else => return error.Socket,
        }
    }
}

fn tcpBind(fd: i32, addr: *const linux.sockaddr.in) SockError!void {
    const rc = linux.bind(fd, @ptrCast(addr), @sizeOf(linux.sockaddr.in));
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        else => return error.Bind,
    }
}

fn tcpListen(fd: i32) SockError!void {
    const rc = linux.listen(fd, 1);
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        else => return error.Listen,
    }
}

fn tcpSockName(fd: i32, addr: *linux.sockaddr.in) SockError!void {
    var len: linux.socklen_t = @sizeOf(linux.sockaddr.in);
    const rc = linux.getsockname(fd, @ptrCast(addr), &len);
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        else => return error.SockName,
    }
}

fn tcpConnect(fd: i32, addr: *const linux.sockaddr.in) SockError!void {
    while (true) {
        const rc = linux.connect(fd, @ptrCast(addr), @sizeOf(linux.sockaddr.in));
        switch (std.posix.errno(rc)) {
            .SUCCESS => return,
            .INTR => continue,
            else => return error.Connect,
        }
    }
}

fn tcpAccept(fd: i32) SockError!i32 {
    while (true) {
        const rc = linux.accept4(fd, null, null, linux.SOCK.CLOEXEC);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            else => return error.Accept,
        }
    }
}

pub fn close(fd: i32) void {
    _ = linux.close(fd);
}

/// gap-socket-gen-tcp-bifs: the `shutdown(2)` direction selectors, re-exported so
/// callers (proc.zig) name the half-close direction without reaching into `linux`.
pub const SHUT_RD: i32 = linux.SHUT.RD;
pub const SHUT_WR: i32 = linux.SHUT.WR;
pub const SHUT_RDWR: i32 = linux.SHUT.RDWR;

/// gap-socket-gen-tcp-bifs: half-close a connected socket (`shutdown(2)`). `how`
/// is one of `SHUT_{RD,WR,RDWR}`. `SHUT_WR` sends the peer an orderly EOF
/// once its buffered data drains — the graceful gen_tcp teardown. Fail-closed: a
/// dead/unconnected fd maps to a `SockError` the caller renders as `{error,_}`.
pub fn shutdown(fd: i32, how: i32) SockError!void {
    const rc = linux.shutdown(fd, how);
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        .NOTCONN, .BADF => return SockError.Closed, // unconnected/dead fd → {error,closed}
        else => return SockError.SockOpt, // → {error,einval}
    }
}

/// Ephemeral port bound to this listener (after bind). Public for the port law.
pub fn boundPort(fd: i32) SockError!u16 {
    var actual: linux.sockaddr.in = undefined;
    try tcpSockName(fd, &actual);
    return std.mem.bigToNative(u16, actual.port);
}

/// A connected loopback pair, set up single-threaded (connect completes on the
/// loopback without a peer thread; accept then returns the server side).
pub const Pair = struct { server: i32, client: i32 };

pub fn openLoopbackPair() SockError!Pair {
    const listener = try tcpSocket();
    defer close(listener); // the listener is not needed once accepted
    var ba = loopbackAddr(0);
    try tcpBind(listener, &ba);
    try tcpListen(listener);
    var actual: linux.sockaddr.in = undefined;
    try tcpSockName(listener, &actual);

    const client = try tcpSocket();
    errdefer close(client);
    try tcpConnect(client, &actual);

    const server = try tcpAccept(listener);
    return .{ .server = server, .client = client };
}

// ── gap-socket-real-tcp: the DECOMPOSED gen_tcp lifecycle ───────────────────
// `openLoopbackPair` fuses listen+connect+accept into one call; the gen_tcp BIF
// surface needs them as SEPARATE, handle-returning steps (a listener persists,
// clients connect to it, the server accepts each). These primitives expose that
// shape; the ordering invariant (connect BEFORE accept) keeps accept bounded on
// loopback — and `acceptTimeout`/`recvTimeout` poll-bound every blocking call so
// a misordered accept or a starved recv fails CLOSED (Timeout) instead of hanging.

pub const Listener = struct { fd: i32, port: u16 };

/// gen_tcp:listen(Port,_): open a listening socket. Port 0 → an ephemeral port
/// (returned so a client can connect); a non-zero port binds that exact port.
pub fn listen(port: u16) SockError!Listener {
    const fd = try tcpSocket();
    errdefer close(fd);
    var ba = loopbackAddr(port);
    try tcpBind(fd, &ba);
    try tcpListen(fd);
    return .{ .fd = fd, .port = try boundPort(fd) };
}

/// gen_tcp:connect(loopback, Port, _): a client stream socket connected to the
/// loopback listener on `port`. ECONNREFUSED (nobody listening) maps to a
/// distinct error so the BIF layer can render `{error,econnrefused}`.
pub fn connectPort(port: u16) SockError!i32 {
    const fd = try tcpSocket();
    errdefer close(fd);
    const addr = loopbackAddr(port);
    while (true) {
        const rc = linux.connect(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.in));
        switch (std.posix.errno(rc)) {
            .SUCCESS => return fd,
            .INTR => continue,
            .CONNREFUSED => return error.ConnRefused, // OTP {error,econnrefused}
            else => return error.Connect,
        }
    }
}

/// Bounded `accept`: wait up to `ms` for a pending connection, then accept it.
/// On loopback the kernel completes the handshake at connect() time, so when the
/// client connected first this returns immediately; with no pending client it
/// fails CLOSED with Timeout (never blocks forever — the accept-hang law).
pub fn acceptTimeout(listener_fd: i32, ms: i32) SockError!i32 {
    var pfd = [_]linux.pollfd{.{ .fd = listener_fd, .events = linux.POLL.IN, .revents = 0 }};
    while (true) {
        const pr = linux.poll(&pfd, 1, ms);
        switch (std.posix.errno(pr)) {
            .SUCCESS => {},
            .INTR => continue,
            else => return error.Accept,
        }
        if (pr == 0) return error.Timeout; // no pending connection within the bound
        return tcpAccept(listener_fd);
    }
}

/// gap-cowboy-trap-accept: block up to `ms` until ANY of `fds` is readable (a
/// pending connection on a listen fd / data on an active stream fd), or the timeout.
/// The resident scheduler's reactor poll-wait — efficient kernel `poll`, never a
/// busy-spin. An empty `fds` degrades to a pure `ms` sleep. Ignores the result
/// (the caller re-polls each socket to service it).
pub fn pollWait(fds: []const i32, ms: i32) void {
    if (fds.len == 0) {
        var none: [1]linux.pollfd = .{.{ .fd = -1, .events = 0, .revents = 0 }};
        _ = linux.poll(&none, 0, ms);
        return;
    }
    var pfds: [64]linux.pollfd = undefined;
    const n = @min(fds.len, pfds.len);
    for (fds[0..n], 0..) |fd, i| pfds[i] = .{ .fd = fd, .events = linux.POLL.IN, .revents = 0 };
    _ = linux.poll(&pfds, @intCast(n), ms);
}

/// Bounded `recv`: poll up to `ms` for readable data, then read up to buf.len.
/// Returns 0 on peer-close (EOF). A starved recv fails CLOSED with Timeout rather
/// than blocking forever (the recv-hang law).
pub fn recvTimeout(fd: i32, buf: []u8, ms: i32) SockError!usize {
    var pfd = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    while (true) {
        const pr = linux.poll(&pfd, 1, ms);
        switch (std.posix.errno(pr)) {
            .SUCCESS => {},
            .INTR => continue,
            .BADF => return error.BadFd,
            else => return error.Recv,
        }
        if (pr == 0) return error.Timeout;
        return recv(fd, buf);
    }
}

/// Send all bytes (the write loop — gen_tcp:send has no short write).
pub fn send(fd: i32, bytes: []const u8) SockError!void {
    var off: usize = 0;
    while (off < bytes.len) {
        const rc = linux.write(fd, bytes.ptr + off, bytes.len - off);
        switch (std.posix.errno(rc)) {
            .SUCCESS => off += rc,
            .INTR => continue,
            .BADF => return error.BadFd,
            else => return error.Send,
        }
    }
}

/// Receive up to buf.len bytes; returns the count (0 = peer closed / EOF).
pub fn recv(fd: i32, buf: []u8) SockError!usize {
    while (true) {
        const rc = linux.read(fd, buf.ptr, buf.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return rc,
            .INTR => continue,
            .BADF => return error.BadFd,
            else => return error.Recv,
        }
    }
}

// ── gen_tcp {packet,N} composition with the proven framing algebra ─────────
/// Frame `payload` in `mode` (via port_algebra) and send it over the socket.
pub fn sendFramed(gpa: std.mem.Allocator, fd: i32, mode: port_algebra.Mode, payload: []const u8) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try port_algebra.frame(gpa, mode, payload, &out);
    try send(fd, out.items);
}

/// Read the stream until the Deframer yields exactly one packet; return it
/// (caller owns). Composes the proven Deframer with the real transport.
pub fn recvOnePacket(gpa: std.mem.Allocator, fd: i32, mode: port_algebra.Mode) ![]u8 {
    var df = port_algebra.Deframer.init(gpa, mode);
    defer df.deinit();
    var buf: [64]u8 = undefined; // small on purpose: forces multi-read reassembly
    while (df.out.items.len == 0) {
        const n = try recv(fd, &buf);
        if (n == 0) return error.Closed;
        try df.feed(buf[0..n]);
    }
    return try gpa.dupe(u8, df.out.items[0]);
}

// ── UDP (gen_udp) ──────────────────────────────────────────────────────────
pub fn udpSocket() SockError!i32 {
    while (true) {
        const rc = linux.socket(linux.AF.INET, linux.SOCK.DGRAM | linux.SOCK.CLOEXEC, 0);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            else => return error.Socket,
        }
    }
}

/// Bind a UDP socket to loopback:0 and return the chosen ephemeral port.
pub fn udpBindEphemeral(fd: i32) SockError!u16 {
    var ba = loopbackAddr(0);
    try tcpBind(fd, &ba);
    return boundPort(fd);
}

pub fn udpSendTo(fd: i32, bytes: []const u8, port: u16) SockError!void {
    const dest = loopbackAddr(port);
    while (true) {
        const rc = linux.sendto(fd, bytes.ptr, bytes.len, 0, @ptrCast(&dest), @sizeOf(linux.sockaddr.in));
        switch (std.posix.errno(rc)) {
            .SUCCESS => return,
            .INTR => continue,
            .BADF => return error.BadFd,
            else => return error.Send,
        }
    }
}

pub fn udpRecv(fd: i32, buf: []u8) SockError!usize {
    while (true) {
        const rc = linux.recvfrom(fd, buf.ptr, buf.len, 0, null, null);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return rc,
            .INTR => continue,
            .BADF => return error.BadFd,
            else => return error.Recv,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Laws — the RUNTIME-CAPABILITY-EQUIVALENCE evidence (a socket echo round-trips)
// ═══════════════════════════════════════════════════════════════════════════

test "socket_algebra: TCP loopback echo round-trips (send == recv, both ways)" {
    const p = try openLoopbackPair();
    defer close(p.server);
    defer close(p.client);
    const msg = "hello, beam sockets — a real loopback round-trip";
    try send(p.client, msg);
    var buf: [128]u8 = undefined;
    const n = try recv(p.server, buf[0..]);
    try std.testing.expectEqual(msg.len, n);
    try std.testing.expectEqualStrings(msg, buf[0..n]);
    // echo back
    try send(p.server, buf[0..n]);
    var buf2: [128]u8 = undefined;
    const n2 = try recv(p.client, buf2[0..]);
    try std.testing.expectEqualStrings(msg, buf2[0..n2]);
}

test "socket_algebra: {packet,N} framed message round-trips over a real socket" {
    const modes = [_]port_algebra.Mode{ .p1, .p2, .p4 };
    for (modes) |mode| {
        const p = try openLoopbackPair();
        defer close(p.server);
        defer close(p.client);
        const payload = "gen_tcp {packet,N} boundary must survive the byte stream";
        try sendFramed(std.testing.allocator, p.client, mode, payload);
        const got = try recvOnePacket(std.testing.allocator, p.server, mode);
        defer std.testing.allocator.free(got);
        try std.testing.expectEqualStrings(payload, got);
    }
}

test "socket_algebra: a payload larger than the read buffer reassembles" {
    const p = try openLoopbackPair();
    defer close(p.server);
    defer close(p.client);
    var payload: [4096]u8 = undefined;
    for (&payload, 0..) |*b, i| b.* = @intCast(i & 0xff);
    try send(p.client, &payload); // 4 KiB fits the socket buffer → no send block
    var got: [4096]u8 = undefined;
    var off: usize = 0;
    while (off < got.len) {
        const n = try recv(p.server, got[off..]);
        if (n == 0) break;
        off += n;
    }
    try std.testing.expectEqual(payload.len, off);
    try std.testing.expectEqualSlices(u8, &payload, got[0..off]);
}

test "socket_algebra: UDP datagram round-trips over loopback (gen_udp)" {
    const rx = try udpSocket();
    defer close(rx);
    const port = try udpBindEphemeral(rx);
    try std.testing.expect(port != 0);
    const tx = try udpSocket();
    defer close(tx);
    const dg = "a udp datagram payload";
    try udpSendTo(tx, dg, port);
    var buf: [64]u8 = undefined;
    const n = try udpRecv(rx, buf[0..]);
    try std.testing.expectEqualStrings(dg, buf[0..n]);
}

test "socket_algebra: bind port 0 yields a valid non-zero ephemeral port" {
    const fd = try tcpSocket();
    defer close(fd);
    var ba = loopbackAddr(0);
    try tcpBind(fd, &ba);
    const port = try boundPort(fd);
    try std.testing.expect(port != 0);
}

test "socket_algebra: DECOMPOSED gen_tcp lifecycle round-trips (listen→connect→accept→send→recv→echo)" {
    // The real gen_tcp shape: a persistent listener, a client that connects to
    // its port, a server side pulled out by accept — then a byte-exact echo in
    // BOTH directions over the real loopback sockets. Every blocking call is
    // poll-bounded (100ms) so the law can never hang.
    const l = try listen(0);
    defer close(l.fd);
    try std.testing.expect(l.port != 0);

    const client = try connectPort(l.port);
    defer close(client);
    const server = try acceptTimeout(l.fd, 100); // client connected first → immediate
    defer close(server);

    const req = "gen_tcp:send/recv over a REAL loopback handle pair";
    try send(client, req);
    var rbuf: [128]u8 = undefined;
    const n = try recvTimeout(server, rbuf[0..], 100);
    try std.testing.expectEqualStrings(req, rbuf[0..n]);

    // server echoes the exact bytes back; client recv's the echo
    try send(server, rbuf[0..n]);
    var ebuf: [128]u8 = undefined;
    const n2 = try recvTimeout(client, ebuf[0..], 100);
    try std.testing.expectEqualStrings(req, ebuf[0..n2]);
}

test "socket_algebra: connect to a port nobody listens on fails ECONNREFUSED" {
    // Bind+close a listener to obtain a definitely-unbound loopback port, then
    // connect → must fail CLOSED as ConnRefused (the {error,econnrefused} shape).
    const l = try listen(0);
    const port = l.port;
    close(l.fd); // now nothing listens on `port`
    try std.testing.expectError(error.ConnRefused, connectPort(port));
}

test "socket_algebra: acceptTimeout on an idle listener fails CLOSED (Timeout), never hangs" {
    const l = try listen(0);
    defer close(l.fd);
    // no client connected → accept must time out within the bound, not block.
    try std.testing.expectError(error.Timeout, acceptTimeout(l.fd, 20));
}

test "socket_algebra: recv on a closed fd fails closed (BadFd), never crashes" {
    const fd = try tcpSocket();
    close(fd); // close first, then use — must fail closed
    var buf: [8]u8 = undefined;
    try std.testing.expectError(error.BadFd, recv(fd, buf[0..]));
}
