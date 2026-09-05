//! beam-zig M4 / S5: the **binary algebra** law suite (cf. erts binary.c,
//! erl_bits.c, erl_iolist.c).
//!
//! Scope note: byte-aligned binaries are the M4 term core. This module also
//! owns the S5 bitstring semantic slice: a bitstring is bytes plus a bit
//! length, with the final byte's unused low bits masked. Term-level bitstring
//! tags and ETF BIT_BINARY_EXT integration remain later representation work.
//!
//! Signature (ops live in term_algebra next to their representations):
//!   binary   : bytes -> Term            (constructor)
//!   binConcat: (Term, Term) -> Term     (combinator — <<A/binary,B/binary>>)
//!   binPart  : (Term, pos, len) -> Term (combinator — binary:part/3)
//!   binSize  : Term -> usize            (observation)
//!   iolistToBinary : Term -> Term       (observation/normalization)
//!
//! Semantic domain: byte sequences ([]const u8, via denote().binary).
//! Laws:
//!   MONOID     concat associative; empty binary is left/right identity
//!   ROUND-TRIP denote(binary(bs)).binary == bs
//!   PART       part(concat(a,b),0,|a|) ≡ a;  part(concat(a,b),|a|,|b|) ≡ b;
//!              part(b,0,|b|) ≡ b;  out-of-range part is error.BadArg
//!   SIZE       |concat(a,b)| = |a|+|b| (byte conservation of concat)
//!   IOLIST     iolistToBinary conserves the leaf bytes in traversal order;
//!              it is IDEMPOTENT (a binary is iodata);
//!              non-iodata terms are rejected (error.BadArg)
//!   Binaries order bytewise lexicographically (prefix < longer) — covered
//!   by term_algebra's spec-agreement law; spot-checked here.
//!   BITSTRING  construction masks padding; concat is associative; empty is
//!              identity; part recovers bit ranges across byte boundaries.

const std = @import("std");
const ta = @import("term_algebra.zig");

const AtomTable = ta.AtomTable;
const InitialTerms = ta.InitialTerms;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

pub const BitString = struct {
    bytes: []const u8,
    bit_len: usize,
};

fn bitByteLen(bit_len: usize) usize {
    return (bit_len + 7) / 8;
}

fn tailMask(bit_len: usize) u8 {
    const rem = bit_len % 8;
    if (rem == 0) return 0xFF;
    return @as(u8, 0xFF) << @intCast(8 - rem);
}

fn bitAt(b: BitString, idx: usize) bool {
    std.debug.assert(idx < b.bit_len);
    const byte = b.bytes[idx / 8];
    const shift: u3 = @intCast(7 - (idx % 8));
    return ((byte >> shift) & 1) != 0;
}

fn setBit(bytes: []u8, idx: usize) void {
    const shift: u3 = @intCast(7 - (idx % 8));
    bytes[idx / 8] |= @as(u8, 1) << shift;
}

pub fn bitstring(gpa: std.mem.Allocator, raw: []const u8, bit_len: usize) !BitString {
    const n = bitByteLen(bit_len);
    if (raw.len < n) return error.BadArg;
    const out = try gpa.alloc(u8, n);
    @memcpy(out, raw[0..n]);
    if (n > 0) out[n - 1] &= tailMask(bit_len);
    return .{ .bytes = out, .bit_len = bit_len };
}

pub fn bitstringFree(gpa: std.mem.Allocator, b: BitString) void {
    gpa.free(b.bytes);
}

pub fn bitstringEql(a: BitString, b: BitString) bool {
    return a.bit_len == b.bit_len and std.mem.eql(u8, a.bytes, b.bytes);
}

pub fn bitstringConcat(gpa: std.mem.Allocator, a: BitString, b: BitString) !BitString {
    const out_len = a.bit_len + b.bit_len;
    const out_bytes = try gpa.alloc(u8, bitByteLen(out_len));
    @memset(out_bytes, 0);
    for (0..a.bit_len) |i| if (bitAt(a, i)) setBit(out_bytes, i);
    for (0..b.bit_len) |i| if (bitAt(b, i)) setBit(out_bytes, a.bit_len + i);
    return .{ .bytes = out_bytes, .bit_len = out_len };
}

pub fn bitstringPart(gpa: std.mem.Allocator, b: BitString, pos: usize, len: usize) !BitString {
    if (pos > b.bit_len or len > b.bit_len - pos) return error.BadArg;
    const out_bytes = try gpa.alloc(u8, bitByteLen(len));
    @memset(out_bytes, 0);
    for (0..len) |i| if (bitAt(b, pos + i)) setBit(out_bytes, i);
    return .{ .bytes = out_bytes, .bit_len = len };
}

// ── decode_packet framing kernel (erlang:decode_packet/3) ───────────────────
//
// A faithful Zig port of erts `packet_get_length` + `packet_get_body`
// (third_party/otp/erts/emulator/beam/packet_parser.c / .h) for the PURE
// FRAMING packet types — the ones whose `packet_parse` returns code 0 (a plain
// binary body, no structured protocol term). The BIF wrapper in
// `bifs/erlang.zig` layers term construction (`{ok,Body,Rest}` /
// `{more,Len|undefined}` / `{error,invalid}`) atop this kernel.
//
// Semantic domain (matches OTP's `int packet_get_length` contract EXACTLY):
//   packetGetLength : (type, bytes, max_plen, trunc_len, delimiter) -> i32
//     < 0  invalid format            (OTP `return -1`)
//     = 0  need more data, unknown   (OTP `goto more`)
//     > 0  total packet length bytes (OTP `remain`/`done`)
// All arithmetic is done in the SAME widths as the C (u32 header/plen/tlen with
// wrap-around, an i32 result via bit-reinterpretation) so wrap-around packets
// frame byte-identically to OTP — including the `tlen < (int)hlen` overflow
// guard and the `plen > max_plen` cap.
//
// COVERED framing types (packet_parse code 0): raw|0, 1, 2, 4, line, sunrm,
// cdr, fcgi, tpkt, asn1. The STRUCTURED types http/httph/http_bin/httph_bin/
// ssl_tls (packet_parse code 1 — they build {http_request,…}/{ssl_tls,…}
// terms) are OUT OF SCOPE here and rejected by the BIF wrapper; see its scope
// note. This kernel never allocates and never reads out of `bytes`.

pub const PacketType = enum { raw, sz1, sz2, sz4, line, sunrm, cdr, fcgi, tpkt, asn1 };

fn getInt8(b: []const u8, i: usize) u32 {
    return b[i];
}
fn getInt16(b: []const u8, i: usize) u32 {
    return (@as(u32, b[i]) << 8) | @as(u32, b[i + 1]);
}
fn getInt24(b: []const u8, i: usize) u32 {
    return (@as(u32, b[i]) << 16) | (@as(u32, b[i + 1]) << 8) | @as(u32, b[i + 2]);
}
fn getInt32(b: []const u8, i: usize) u32 {
    return (@as(u32, b[i]) << 24) | (@as(u32, b[i + 1]) << 16) |
        (@as(u32, b[i + 2]) << 8) | @as(u32, b[i + 3]);
}
fn getLittleInt32(b: []const u8, i: usize) u32 {
    return (@as(u32, b[i + 3]) << 24) | (@as(u32, b[i + 2]) << 16) |
        (@as(u32, b[i + 1]) << 8) | @as(u32, b[i]);
}

/// OTP `remain:` epilogue — `tlen = hlen + plen`, with the packet-size cap and
/// the wrap-around (`tlen < (int)hlen`) guard, in exact C widths.
fn packetRemain(hlen: u32, plen: u32, max_plen: u32) i32 {
    const tlen: i32 = @bitCast(hlen +% plen);
    if ((max_plen != 0 and plen > max_plen) or tlen < @as(i32, @bitCast(hlen))) return -1;
    return tlen;
}

/// Port of erts `packet_get_length`. `bytes` are the bytes read so far (the C
/// `n`); `delimiter` only matters for `.line`.
pub fn packetGetLength(
    htype: PacketType,
    bytes: []const u8,
    max_plen: u32,
    trunc_len: u32,
    delimiter: u8,
) i32 {
    const n: u32 = @truncate(bytes.len); // C: (unsigned)bin_sz
    switch (htype) {
        .raw => {
            if (n == 0) return 0; // more
            return @bitCast(n);
        },
        .sz1 => {
            if (n < 1) return 0;
            return packetRemain(1, getInt8(bytes, 0), max_plen);
        },
        .sz2 => {
            if (n < 2) return 0;
            return packetRemain(2, getInt16(bytes, 0), max_plen);
        },
        .sz4 => {
            if (n < 4) return 0;
            return packetRemain(4, getInt32(bytes, 0), max_plen);
        },
        .sunrm => {
            if (n < 4) return 0;
            return packetRemain(4, getInt32(bytes, 0) & 0x7fffffff, max_plen);
        },
        .line => {
            const idx = std.mem.indexOfScalar(u8, bytes, delimiter);
            if (idx == null) {
                if (n > max_plen and max_plen != 0) return -1; // packet full, no NL
                if (n >= trunc_len and trunc_len != 0) return @bitCast(trunc_len);
                return 0; // more
            }
            const len: u32 = @intCast(idx.? + 1); // include delimiter
            if (len > max_plen and max_plen != 0) return -1;
            if (len > trunc_len and trunc_len != 0) return @bitCast(trunc_len);
            return @bitCast(len);
        },
        .asn1 => {
            if (n < 2) return 0;
            var i: usize = 0;
            var nn: i64 = n;
            nn -= 1;
            const first = bytes[i];
            i += 1;
            if ((first & 0x1f) == 0x1f) { // long tag format
                while (nn != 0 and (bytes[i] & 0x80) == 0x80) {
                    i += 1;
                    nn -= 1;
                }
                if (nn < 2) return 0; // more
                i += 1;
                nn -= 1;
            }
            // bytes[i] is the length field
            const length: u32 = bytes[i] & 0x7f;
            var plen: u32 = undefined;
            if ((bytes[i] & 0x80) == 0x80) { // long length format
                i += 1;
                nn -= 1;
                if (nn < @as(i64, length)) return 0; // more
                switch (length) {
                    0 => plen = 0,
                    1 => {
                        plen = getInt8(bytes, i);
                        i += 1;
                    },
                    2 => {
                        plen = getInt16(bytes, i);
                        i += 2;
                    },
                    3 => {
                        plen = getInt24(bytes, i);
                        i += 3;
                    },
                    4 => {
                        plen = getInt32(bytes, i);
                        i += 4;
                    },
                    else => return -1,
                }
            } else {
                i += 1;
                plen = length;
            }
            return packetRemain(@intCast(i), plen, max_plen);
        },
        .cdr => {
            const hlen: u32 = 12; // sizeof(struct cdr_head)
            if (n < hlen) return 0;
            if (!std.mem.eql(u8, bytes[0..4], "GIOP")) return -1;
            const flags = bytes[6];
            const plen: u32 = if (flags & 0x01 != 0)
                getLittleInt32(bytes, 8)
            else
                getInt32(bytes, 8);
            return packetRemain(hlen, plen, max_plen);
        },
        .fcgi => {
            const hlen: u32 = 8; // sizeof(struct fcgi_head)
            if (n < hlen) return 0;
            if (bytes[0] != 1) return -1; // version != FCGI_VERSION_1
            const plen: u32 = ((@as(u32, bytes[4]) << 8) | @as(u32, bytes[5])) +% @as(u32, bytes[6]);
            return packetRemain(hlen, plen, max_plen);
        },
        .tpkt => {
            const hlen: u32 = 4; // sizeof(struct tpkt_head)
            if (n < hlen) return 0;
            if (bytes[0] != 3) return -1; // vrsn != TPKT_VRSN
            const plen: u32 = getInt16(bytes, 2) -% hlen;
            return packetRemain(hlen, plen, max_plen);
        },
    }
}

/// The body sub-range of a fully-received packet — port of `packet_get_body`.
/// `packet_sz` is the value packetGetLength returned (> 0, <= bytes.len).
/// Returns `{off, len}` into the ORIGINAL binary: for sz1/2/4 the length header
/// is skipped; for fcgi the trailing padding is trimmed; otherwise the whole
/// packet is returned "as is".
pub const BodyRange = struct { off: usize, len: usize };
pub fn packetGetBody(htype: PacketType, bytes: []const u8, packet_sz: usize) BodyRange {
    return switch (htype) {
        .sz1 => .{ .off = 1, .len = packet_sz - 1 },
        .sz2 => .{ .off = 2, .len = packet_sz - 2 },
        .sz4 => .{ .off = 4, .len = packet_sz - 4 },
        .fcgi => .{ .off = 0, .len = packet_sz - bytes[6] }, // trim paddingLength
        else => .{ .off = 0, .len = packet_sz },
    };
}

fn randBytes(random: std.Random, buf: []u8) []const u8 {
    const len = random.uintLessThan(usize, buf.len + 1);
    for (buf[0..len]) |*b| b.* = random.int(u8);
    return buf[0..len];
}

/// Generate a random iodata term AND the byte sequence it denotes (the
/// oracle bytes, computed independently of either encoding's walker).
fn genIolist(
    comptime Impl: type,
    random: std.Random,
    ctx: *Impl.Ctx,
    expected: *std.ArrayList(u8),
    gpa: std.mem.Allocator,
    depth: usize,
) !Impl.Term {
    if (depth == 0 or random.uintLessThan(u8, 3) == 0) {
        // leaf list of bytes/binaries, possibly with an improper binary tail
        var items: [5]Impl.Term = undefined;
        const n = random.uintLessThan(usize, 5);
        for (0..n) |k| {
            if (random.boolean()) {
                const byte = random.int(u8);
                items[k] = Impl.int(ctx, byte);
                try expected.append(gpa, byte);
            } else {
                var buf: [6]u8 = undefined;
                const bs = randBytes(random, &buf);
                items[k] = try Impl.binary(ctx, bs);
                try expected.appendSlice(gpa, bs);
            }
        }
        var tail: Impl.Term = undefined;
        if (random.uintLessThan(u8, 4) == 0) { // improper binary tail
            var buf: [6]u8 = undefined;
            const bs = randBytes(random, &buf);
            tail = try Impl.binary(ctx, bs);
            try expected.appendSlice(gpa, bs);
        } else {
            tail = Impl.nil(ctx);
        }
        var acc = tail;
        var k = n;
        while (k > 0) {
            k -= 1;
            acc = try Impl.cons(ctx, items[k], acc);
        }
        return acc;
    }
    // nested: a proper list of sub-iolists
    const n = 1 + random.uintLessThan(usize, 3);
    var subs: [3]Impl.Term = undefined;
    for (0..n) |k| subs[k] = try genIolist(Impl, random, ctx, expected, gpa, depth - 1);
    var acc = Impl.nil(ctx);
    var k = n;
    while (k > 0) {
        k -= 1;
        acc = try Impl.cons(ctx, subs[k], acc);
    }
    return acc;
}

pub fn verifyBinaryLaws(comptime Impl: type, gpa: std.mem.Allocator, cfg: LawConfig) !void {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var ctx = Impl.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        var spec_arena = std.heap.ArenaAllocator.init(gpa);
        defer spec_arena.deinit();
        const sa = spec_arena.allocator();

        var b1: [24]u8 = undefined;
        var b2: [24]u8 = undefined;
        var b3: [24]u8 = undefined;
        const s1 = randBytes(random, &b1);
        const s2 = randBytes(random, &b2);
        const s3 = randBytes(random, &b3);
        const a = try Impl.binary(&ctx, s1);
        const b = try Impl.binary(&ctx, s2);
        const c = try Impl.binary(&ctx, s3);
        const empty = try Impl.binary(&ctx, &.{});

        // round-trip
        try expectLaw(std.mem.eql(u8, (try Impl.denote(&ctx, sa, a)).binary, s1), "binary: construct/denote round-trip", cfg, i);

        // monoid
        try expectLaw(Impl.eqlExact(&ctx, try Impl.binConcat(&ctx, empty, a), a), "binary: concat left identity", cfg, i);
        try expectLaw(Impl.eqlExact(&ctx, try Impl.binConcat(&ctx, a, empty), a), "binary: concat right identity", cfg, i);
        try expectLaw(Impl.eqlExact(
            &ctx,
            try Impl.binConcat(&ctx, try Impl.binConcat(&ctx, a, b), c),
            try Impl.binConcat(&ctx, a, try Impl.binConcat(&ctx, b, c)),
        ), "binary: concat associativity", cfg, i);

        // size conservation
        const ab = try Impl.binConcat(&ctx, a, b);
        try expectLaw(Impl.binSize(&ctx, ab) == s1.len + s2.len, "binary: concat conserves byte count", cfg, i);

        // part laws
        try expectLaw(Impl.eqlExact(&ctx, try Impl.binPart(&ctx, ab, 0, s1.len), a), "binary: part recovers left of concat", cfg, i);
        try expectLaw(Impl.eqlExact(&ctx, try Impl.binPart(&ctx, ab, s1.len, s2.len), b), "binary: part recovers right of concat", cfg, i);
        try expectLaw(Impl.eqlExact(&ctx, try Impl.binPart(&ctx, a, 0, s1.len), a), "binary: whole part is identity", cfg, i);
        try expectLaw(Impl.binPart(&ctx, a, 0, s1.len + 1) == error.BadArg, "binary: out-of-range part is badarg", cfg, i);

        // iolist: conservation against independently-accumulated oracle bytes
        var expected: std.ArrayList(u8) = .empty;
        defer expected.deinit(gpa);
        const iol = try genIolist(Impl, random, &ctx, &expected, gpa, 3);
        const flat = try Impl.iolistToBinary(&ctx, iol);
        try expectLaw(std.mem.eql(u8, (try Impl.denote(&ctx, sa, flat)).binary, expected.items), "iolist: flatten conserves leaf bytes in order", cfg, i);
        // idempotence: a binary is iodata
        const flat2 = try Impl.iolistToBinary(&ctx, flat);
        try expectLaw(Impl.eqlExact(&ctx, flat2, flat), "iolist: flatten is idempotent", cfg, i);
        // rejection: an atom is not iodata
        const bad = try Impl.cons(&ctx, Impl.atom(&ctx, try ctx.atoms.intern("nope")), Impl.nil(&ctx));
        try expectLaw(Impl.iolistToBinary(&ctx, bad) == error.BadArg, "iolist: non-iodata is badarg", cfg, i);
        // rejection: 256 is not a byte
        const bad2 = try Impl.cons(&ctx, Impl.int(&ctx, 256), Impl.nil(&ctx));
        try expectLaw(Impl.iolistToBinary(&ctx, bad2) == error.BadArg, "iolist: out-of-range byte is badarg", cfg, i);
    }
}

test "Laws: binaries on the Initial encoding (tree oracle)" {
    try verifyBinaryLaws(InitialTerms, std.testing.allocator, .{ .iterations = 100 });
}

test "Laws: binaries on the Final encoding (packed heap words)" {
    try verifyBinaryLaws(FinalTerms, std.testing.allocator, .{ .iterations = 100 });
}

test "Homomorphism: twin iolists flatten identically across encodings" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0xB1AB };

    for (0..40) |i| {
        var ic = InitialTerms.Ctx.init(gpa, &atoms);
        defer ic.deinit();
        var fc = FinalTerms.Ctx.init(gpa, &atoms);
        defer fc.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng_a = std.Random.DefaultPrng.init(cfg.seed +% i);
        var prng_b = std.Random.DefaultPrng.init(cfg.seed +% i);

        var e1: std.ArrayList(u8) = .empty;
        defer e1.deinit(gpa);
        var e2: std.ArrayList(u8) = .empty;
        defer e2.deinit(gpa);
        const ti = try genIolist(InitialTerms, prng_a.random(), &ic, &e1, gpa, 3);
        const tf = try genIolist(FinalTerms, prng_b.random(), &fc, &e2, gpa, 3);
        try std.testing.expect(std.mem.eql(u8, e1.items, e2.items)); // twins in lockstep

        const fi = try InitialTerms.iolistToBinary(&ic, ti);
        const ff = try FinalTerms.iolistToBinary(&fc, tf);
        try expectLaw(spec.eqlExact(
            try InitialTerms.denote(&ic, sa, fi),
            try FinalTerms.denote(&fc, sa, ff),
        ), "iolist homomorphism: flattenings agree", cfg, i);
    }
}

test "Spot: binary term order is bytewise lexicographic, prefix first" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const ab = try FinalTerms.binary(&ctx, "ab");
    const abc = try FinalTerms.binary(&ctx, "abc");
    const b = try FinalTerms.binary(&ctx, "b");
    try std.testing.expectEqual(ta.Order.lt, FinalTerms.compare(&ctx, ab, abc)); // prefix
    try std.testing.expectEqual(ta.Order.lt, FinalTerms.compare(&ctx, ab, b)); // 'a' < 'b'
    try std.testing.expectEqual(ta.Order.lt, FinalTerms.compare(&ctx, abc, b));
}

fn randBitString(gpa: std.mem.Allocator, random: std.Random, buf: []u8) !BitString {
    const bit_len = random.uintLessThan(usize, buf.len * 8 + 1);
    for (buf) |*b| b.* = random.int(u8);
    return bitstring(gpa, buf, bit_len);
}

test "S5 bitstrings: construction masks padding and observes bits MSB-first" {
    const gpa = std.testing.allocator;
    const b = try bitstring(gpa, &.{0b1010_1111}, 5);
    defer bitstringFree(gpa, b);
    try std.testing.expectEqual(@as(usize, 5), b.bit_len);
    try std.testing.expectEqual(@as(u8, 0b1010_1000), b.bytes[0]);
    try std.testing.expect(bitAt(b, 0));
    try std.testing.expect(!bitAt(b, 1));
    try std.testing.expect(bitAt(b, 2));
    try std.testing.expect(!bitAt(b, 3));
    try std.testing.expect(bitAt(b, 4));

    const empty = try bitstring(gpa, &.{}, 0);
    defer bitstringFree(gpa, empty);
    try std.testing.expectEqual(@as(usize, 0), empty.bytes.len);
}

test "S5 bitstrings: concat, part, associativity, and bad ranges" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xB175);
    const random = prng.random();

    for (0..120) |_| {
        var ba: [5]u8 = undefined;
        var bb: [5]u8 = undefined;
        var bc: [5]u8 = undefined;
        const a = try randBitString(gpa, random, &ba);
        defer bitstringFree(gpa, a);
        const b = try randBitString(gpa, random, &bb);
        defer bitstringFree(gpa, b);
        const c = try randBitString(gpa, random, &bc);
        defer bitstringFree(gpa, c);
        const empty = try bitstring(gpa, &.{}, 0);
        defer bitstringFree(gpa, empty);

        const ea = try bitstringConcat(gpa, empty, a);
        defer bitstringFree(gpa, ea);
        try std.testing.expect(bitstringEql(ea, a));
        const ae = try bitstringConcat(gpa, a, empty);
        defer bitstringFree(gpa, ae);
        try std.testing.expect(bitstringEql(ae, a));

        const ab = try bitstringConcat(gpa, a, b);
        defer bitstringFree(gpa, ab);
        try std.testing.expectEqual(a.bit_len + b.bit_len, ab.bit_len);

        const left = try bitstringPart(gpa, ab, 0, a.bit_len);
        defer bitstringFree(gpa, left);
        try std.testing.expect(bitstringEql(left, a));
        const right = try bitstringPart(gpa, ab, a.bit_len, b.bit_len);
        defer bitstringFree(gpa, right);
        try std.testing.expect(bitstringEql(right, b));

        const ab_c = try bitstringConcat(gpa, ab, c);
        defer bitstringFree(gpa, ab_c);
        const bcatc = try bitstringConcat(gpa, b, c);
        defer bitstringFree(gpa, bcatc);
        const a_bc = try bitstringConcat(gpa, a, bcatc);
        defer bitstringFree(gpa, a_bc);
        try std.testing.expect(bitstringEql(ab_c, a_bc));

        if (ab.bytes.len > 0 and ab.bit_len % 8 != 0) {
            try std.testing.expectEqual(@as(u8, 0), ab.bytes[ab.bytes.len - 1] & ~tailMask(ab.bit_len));
        }
        try std.testing.expectError(error.BadArg, bitstringPart(gpa, ab, ab.bit_len, 1));
    }
}
