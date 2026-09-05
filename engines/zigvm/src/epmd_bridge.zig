//! S27 companion: **epmd ALIVE2 registration codec** (cf. erts `erl_epmd.erl`,
//! `epmd_srv.c`). E21 Task 5 (DIVERGENCE 440 discharge — the INBOUND
//! distribution acceptor) needs zigvm to ADVERTISE a distribution port with the
//! local Erlang Port Mapper Daemon so a real OTP-30 peer can look zigvm up and
//! DIAL IN. Every E18/E20 dist slice had zigvm dial OUT (`epmdPortPlease`); this
//! module is the mirror registration direction.
//!
//! Signature / semantic domain: the ALIVE2 protocol is a pair of total maps over
//! the request/response byte shapes. `encodeAlive2Req` renders the request BODY
//! (the bytes AFTER the 2-byte packet length prefix — the socket layer frames it
//! with the same packet-2 framing OTP uses); `decodeAlive2Req` is its exact
//! inverse; `decodeAlive2Resp` parses BOTH epmd reply shapes (the legacy
//! `ALIVE2_RESP` 'y' with a 16-bit creation and the modern `ALIVE2_X_RESP` 'v'
//! with a 32-bit creation). This module owns NO socket I/O — the live
//! registration (connect epmd, write the framed request, KEEP the connection
//! open so the registration persists) lives in `dist.zig`'s acceptor, which
//! reuses this codec. epmd holds a node's registration only while the TCP
//! connection stays open, so the acceptor keeps the epmd fd for its lifetime.
//!
//! Wire layout (erl_epmd.erl `alive2_req`/`alive2_resp`):
//!   ALIVE2_REQ (body): 120 | Port:16 | NodeType:8 | Protocol:8 | Highest:16 |
//!                      Lowest:16 | Nlen:16 | Name | Elen:16 | Extra
//!   ALIVE2_RESP:       121 | Result:8 | Creation:16      (legacy 'y')
//!   ALIVE2_X_RESP:     118 | Result:8 | Creation:32      (modern 'v')
//! Result == 0 means the node is registered; the node name is the ALIVE PREFIX
//! (the part before '@'), never the full `name@host`.
//!
//! Laws:
//!   ALIVE2-REGISTER ROUND-TRIP  decodeAlive2Req ∘ encodeAlive2Req == identity
//!                               over seeded (port, node_type, versions, name,
//!                               extra) — the request the peer's epmd will parse
//!                               is exactly the one we intend.
//!   ALIVE2-RESP PARSE           decodeAlive2Resp recovers (result, creation)
//!                               from BOTH the 'y' (16-bit) and 'v' (32-bit)
//!                               reply shapes; a wrong tag / short frame is a
//!                               NAMED rejection, never a silent misparse.

const std = @import("std");

pub const config = struct {
    pub const experimental_epmd_bridge: bool = true;
};

pub const EpmdError = error{
    InvalidLength,
    InvalidOpcode,
    ShortFrame,
    BadTag,
};

// erl_epmd.hrl constants.
pub const ALIVE2_REQ: u8 = 120; // 'x'
pub const ALIVE2_RESP: u8 = 121; // 'y' — legacy, 16-bit creation
pub const ALIVE2_X_RESP: u8 = 118; // 'v' — modern, 32-bit creation
pub const NODE_TYPE_NORMAL: u8 = 77; // 'M' — normal (visible) node
pub const NODE_TYPE_HIDDEN: u8 = 72; // 'H' — hidden node
pub const PROTOCOL_TCP: u8 = 0; // tcp/ip-v4
pub const EPMD_DIST_HIGH: u16 = 6; // OTP-23+ distribution version
pub const EPMD_DIST_LOW: u16 = 5;

pub const Alive2Req = struct {
    port: u16,
    node_type: u8 = NODE_TYPE_NORMAL,
    protocol: u8 = PROTOCOL_TCP,
    highest: u16 = EPMD_DIST_HIGH,
    lowest: u16 = EPMD_DIST_LOW,
    name: []const u8, // ALIVE prefix, no @host
    extra: []const u8 = &.{},
};

pub const Alive2Resp = struct {
    result: u8, // 0 == registered ok
    creation: u32, // epmd-assigned node incarnation (advisory)
    extended: bool, // true iff parsed from the 'v' (32-bit) reply
};

fn putU16(gpa: std.mem.Allocator, out: *std.ArrayList(u8), v: u16) !void {
    try out.append(gpa, @truncate(v >> 8));
    try out.append(gpa, @truncate(v));
}

fn getU16(b: []const u8) u16 {
    return (@as(u16, b[0]) << 8) | b[1];
}

/// Render the ALIVE2_REQ BODY (bytes after the packet-2 length prefix). The
/// caller frames it (`port.frame(.p2, ...)`) and writes it to the epmd socket.
/// Caller owns the returned slice.
pub fn encodeAlive2Req(gpa: std.mem.Allocator, req: Alive2Req) ![]u8 {
    var b: std.ArrayList(u8) = .empty;
    errdefer b.deinit(gpa);
    try b.append(gpa, ALIVE2_REQ);
    try putU16(gpa, &b, req.port);
    try b.append(gpa, req.node_type);
    try b.append(gpa, req.protocol);
    try putU16(gpa, &b, req.highest);
    try putU16(gpa, &b, req.lowest);
    try putU16(gpa, &b, @intCast(req.name.len));
    try b.appendSlice(gpa, req.name);
    try putU16(gpa, &b, @intCast(req.extra.len));
    try b.appendSlice(gpa, req.extra);
    return b.toOwnedSlice(gpa);
}

/// Exact inverse of `encodeAlive2Req` over the request body. Fields alias into
/// `buf` (no allocation); a truncated frame is a NAMED rejection.
pub fn decodeAlive2Req(buf: []const u8) EpmdError!Alive2Req {
    if (buf.len < 11) return error.ShortFrame;
    if (buf[0] != ALIVE2_REQ) return error.BadTag;
    const port = getU16(buf[1..3]);
    const node_type = buf[3];
    const protocol = buf[4];
    const highest = getU16(buf[5..7]);
    const lowest = getU16(buf[7..9]);
    const nlen: usize = getU16(buf[9..11]);
    if (buf.len < 11 + nlen + 2) return error.ShortFrame;
    const name = buf[11 .. 11 + nlen];
    const elen: usize = getU16(buf[11 + nlen .. 11 + nlen + 2]);
    const eoff = 11 + nlen + 2;
    if (buf.len < eoff + elen) return error.ShortFrame;
    return .{
        .port = port,
        .node_type = node_type,
        .protocol = protocol,
        .highest = highest,
        .lowest = lowest,
        .name = name,
        .extra = buf[eoff .. eoff + elen],
    };
}

/// Parse an epmd ALIVE2 reply, accepting BOTH the legacy 'y' (16-bit creation)
/// and the modern 'v' (32-bit creation) shapes. `result == 0` means registered.
pub fn decodeAlive2Resp(buf: []const u8) EpmdError!Alive2Resp {
    if (buf.len < 1) return error.ShortFrame;
    switch (buf[0]) {
        ALIVE2_RESP => {
            if (buf.len < 4) return error.ShortFrame;
            return .{ .result = buf[1], .creation = getU16(buf[2..4]), .extended = false };
        },
        ALIVE2_X_RESP => {
            if (buf.len < 6) return error.ShortFrame;
            const c = (@as(u32, buf[2]) << 24) | (@as(u32, buf[3]) << 16) |
                (@as(u32, buf[4]) << 8) | buf[5];
            return .{ .result = buf[1], .creation = c, .extended = true };
        },
        else => return error.BadTag,
    }
}

test "LAW E21.5 ALIVE2-REGISTER ROUND-TRIP: decode∘encode == id over seeded requests" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0x21E5_A11E_2AED_0001);
    const r = prng.random();
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const nlen = r.intRangeAtMost(usize, 1, 40);
        var nbuf: [40]u8 = undefined;
        for (0..nlen) |k| nbuf[k] = r.intRangeAtMost(u8, 'a', 'z');
        const elen = r.intRangeAtMost(usize, 0, 8);
        var ebuf: [8]u8 = undefined;
        for (0..elen) |k| ebuf[k] = r.int(u8);
        const req = Alive2Req{
            .port = r.int(u16),
            .node_type = if (r.boolean()) NODE_TYPE_NORMAL else NODE_TYPE_HIDDEN,
            .protocol = PROTOCOL_TCP,
            .highest = r.int(u16),
            .lowest = r.int(u16),
            .name = nbuf[0..nlen],
            .extra = ebuf[0..elen],
        };
        const enc = try encodeAlive2Req(gpa, req);
        defer gpa.free(enc);
        const dec = try decodeAlive2Req(enc);
        try std.testing.expectEqual(req.port, dec.port);
        try std.testing.expectEqual(req.node_type, dec.node_type);
        try std.testing.expectEqual(req.protocol, dec.protocol);
        try std.testing.expectEqual(req.highest, dec.highest);
        try std.testing.expectEqual(req.lowest, dec.lowest);
        try std.testing.expectEqualStrings(req.name, dec.name);
        try std.testing.expectEqualSlices(u8, req.extra, dec.extra);
    }
}

test "LAW E21.5 ALIVE2-RESP PARSE: both 'y'/'v' shapes recovered; bad tag/short rejected" {
    // Legacy 'y' — 16-bit creation.
    const y = decodeAlive2Resp(&[_]u8{ ALIVE2_RESP, 0, 0x12, 0x34 }) catch unreachable;
    try std.testing.expectEqual(@as(u8, 0), y.result);
    try std.testing.expectEqual(@as(u32, 0x1234), y.creation);
    try std.testing.expect(!y.extended);
    // Modern 'v' — 32-bit creation.
    const v = decodeAlive2Resp(&[_]u8{ ALIVE2_X_RESP, 0, 0xDE, 0xAD, 0xBE, 0xEF }) catch unreachable;
    try std.testing.expectEqual(@as(u8, 0), v.result);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), v.creation);
    try std.testing.expect(v.extended);
    // A non-zero result (name already registered) parses cleanly, still a reply.
    const busy = decodeAlive2Resp(&[_]u8{ ALIVE2_X_RESP, 1, 0, 0, 0, 0 }) catch unreachable;
    try std.testing.expectEqual(@as(u8, 1), busy.result);
    // Rejections are NAMED, never a silent misparse.
    try std.testing.expectError(error.BadTag, decodeAlive2Resp(&[_]u8{ 0x77, 0, 0, 0 }));
    try std.testing.expectError(error.ShortFrame, decodeAlive2Resp(&[_]u8{}));
    try std.testing.expectError(error.ShortFrame, decodeAlive2Resp(&[_]u8{ ALIVE2_RESP, 0 }));
    try std.testing.expectError(error.ShortFrame, decodeAlive2Resp(&[_]u8{ ALIVE2_X_RESP, 0, 0, 0 }));
    // Request decode rejections.
    try std.testing.expectError(error.BadTag, decodeAlive2Req(&[_]u8{0x01} ++ [_]u8{0} ** 12));
    try std.testing.expectError(error.ShortFrame, decodeAlive2Req(&[_]u8{ ALIVE2_REQ, 0, 0 }));
}
