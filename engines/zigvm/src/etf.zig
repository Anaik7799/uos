//! beam-zig M9 / S8: the **external term format** (cf. erts external.c,
//! erl_zlib.c) — the serialization homomorphism.
//!
//! Signature:  encode : Term -> bytes        decode : bytes -> Term
//! Semantic domain: the term's denotation (spec.Value).
//!
//! Laws:
//!   ROUND-TRIP        denote(decode(encode(t))) == denote(t) for every
//!                     generated wire term, plain AND (decode-side)
//!                     compressed
//!   NODE DECODE       every golden vector produced by a REAL node's
//!                     term_to_binary (vendored etf_vectors.bin, plain and
//!                     compressed forms; etf_bigmap.bin for the HAMT case)
//!                     decodes to the expected denotation
//!   NODE ENCODE       our encoder reproduces the node's bytes EXACTLY for
//!                     the deterministic subset (everything but large maps,
//!                     whose iteration order the wire does not fix) —
//!                     including the STRING_EXT optimization for byte lists
//!   DETERMINISM       twin-seeded terms encode to identical bytes
//!   TAG TOLERANCE     legacy ATOM_EXT(100)/small-atom forms decode
//!   BIT_BINARY ROUND-TRIP (E3.2)  decode(encode(bs)) == bs for seeded
//!                     sub-byte bitstrings (tag 77, BIT_BINARY_EXT: `{len:
//!                     u32, bits_in_last_byte: u8, data}`); a byte-aligned
//!                     bitstring encodes as plain BINARY_EXT (byte-alignment
//!                     homomorphism, matches BEAM); a malformed
//!                     `bits_in_last_byte` (0 or >8) or `len==0` decode is a
//!                     clean `error.BadBitBinary`, never a panic/OOB
//!
//! Scope (documented): LOCAL funs are not wire terms until M14's fun-export
//! codec lands; encoder emits error.Unsupported for them. E7.1: EXTERNAL funs
//! `fun M:F/A` DO round-trip through EXPORT_EXT (tag 113): Module atom,
//! Function atom, Arity small-int — byte-identical to the host
//! term_to_binary(fun m:f/a). Bignums are bounded by
//! the M2 cap (8 limbs = 64 bytes) — larger SMALL_BIG payloads are rejected
//! with a named error, never truncated.
//!
//! E3.5 (LA-4/S27): pid/reference/port NOW have wire codecs —
//! NEW_PID_EXT(88), NEWER_REFERENCE_EXT(90), NEW_PORT_EXT(89, decode-only)/
//! V4_PORT_EXT(120, our canonical encode form). The Node field in every one
//! of these frames MUST be the fixed LOCAL node atom (`nonode@nohost`, see
//! `term_algebra`'s E3.5 doc comment); a FOREIGN node atom is a clean
//! `error.ForeignNode` decode reject (never a panic) — external/remote
//! pids and dist frames stay E5 (LA-4/S27), so this is the honest boundary,
//! not a silent gap. `Creation` is accepted but not modeled further (we
//! have exactly one node identity); `NEWER_REFERENCE_EXT`'s `Len` must be 3
//! (our local refs are always 3 wire words) — any other length is
//! `error.UnsupportedRefLen`, another clean reject at the same E5 boundary.
//!
//! E8.2f: the debug distribution-external decoder used by
//! `erts_debug:dist_ext_to_term/2` reuses this same term decoder with one extra
//! wire tag: `ATOM_CACHE_REF` (`'R'`). The caller supplies the atom translation
//! tuple; ordinary versioned ETF terms and nested cache refs then decode through
//! one recursive path. This is not a live carrier handle.
//!
//! E8.2u: `erlang:term_to_binary/1,2` and `external_size/1,2` can pass a
//! VM-owned `LocalIdentity` while distribution is active. Only locally encoded
//! pid/ref/port terms (`nonode@nohost`, creation 0) rewrite their WIRE node and
//! creation; the term payload and the pure `encode` observer remain unchanged,
//! and foreign identities keep their encoded owner.

const std = @import("std");
const ta = @import("term_algebra.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

pub const VERSION_MAGIC: u8 = 131;

const T_COMPRESSED = 80;
const T_NEW_FLOAT = 70;
const T_BIT_BINARY = 77; // E3.2: BIT_BINARY_EXT — {len: u32, bits_in_last_byte: u8, data}
const T_RECORD_EXT = 67; // E3.14: RECORD_EXT ('C') — {size: u32, exported: u8, module atom, name atom, keys[size], values[size]}
const T_SMALL_INTEGER = 97;
const T_INTEGER = 98;
const T_ATOM = 100; // latin-1, legacy (decode only)
const T_ATOM_CACHE_REF = 82; // E8.2f: dist external atom-cache reference (decode only)
const T_NEW_PID_EXT = 88; // E3.5: {Node, ID: u32, Serial: u32, Creation: u32}
const T_NEW_PORT_EXT = 89; // E3.5: {Node, ID: u32, Creation: u32} (decode only)
const T_NEWER_REFERENCE_EXT = 90; // E3.5: {Len: u16, Node, Creation: u32, ID[Len]: u32}
const T_SMALL_TUPLE = 104;
const T_LARGE_TUPLE = 105;
const T_NIL = 106;
const T_STRING = 107;
const T_LIST = 108;
const T_BINARY = 109;
const T_SMALL_BIG = 110;
const T_LARGE_BIG = 111;
const T_EXPORT = 113; // E7.1: EXPORT_EXT — {Module: atom, Function: atom, Arity: small int}
const T_SMALL_ATOM = 115; // latin-1, legacy (decode only)
const T_MAP = 116;
const T_ATOM_UTF8 = 118;
const T_SMALL_ATOM_UTF8 = 119;
const T_V4_PORT_EXT = 120; // E3.5: {Node, ID: u64, Creation: u32} — our canonical port encode

/// E3.5: the fixed local node identity every pid/reference/port frame wire-
/// encodes with (and MUST decode against — see the module doc comment's E5
/// boundary). Not an atom table lookup: it is written/compared as raw bytes,
/// exactly like `T_SMALL_ATOM_UTF8`'s payload shape.
const local_node_name = "nonode@nohost";
const LOCAL_CREATION: u32 = 0;

pub const EncodeError = error{ OutOfMemory, Unsupported };
pub const DecodeError = error{ OutOfMemory, Truncated, UnknownTag, BignumTooLarge, BadCompressed, AtomTableFull, BadBitBinary, ForeignNode, UnsupportedRefLen, BadRecord, BadAtomCache };

pub const LocalIdentity = struct {
    node: ta.AtomIdx,
    creation: u32,
};

// ============================================================================
// encode
// ============================================================================

pub fn encode(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, t: FinalTerms.Term) EncodeError!std.ArrayList(u8) {
    return encodeWithLocalIdentity(gpa, ctx, t, null);
}

pub fn encodeWithLocalIdentity(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, t: FinalTerms.Term, local_identity: ?LocalIdentity) EncodeError!std.ArrayList(u8) {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, VERSION_MAGIC);
    try encodeTerm(gpa, ctx, t, &out, local_identity);
    return out;
}

fn u16be(out: *std.ArrayList(u8), gpa: std.mem.Allocator, v: u16) !void {
    try out.append(gpa, @truncate(v >> 8));
    try out.append(gpa, @truncate(v));
}
fn u32be(out: *std.ArrayList(u8), gpa: std.mem.Allocator, v: u32) !void {
    try out.append(gpa, @truncate(v >> 24));
    try out.append(gpa, @truncate(v >> 16));
    try out.append(gpa, @truncate(v >> 8));
    try out.append(gpa, @truncate(v));
}
fn u64be(out: *std.ArrayList(u8), gpa: std.mem.Allocator, v: u64) !void {
    var k: u6 = 56;
    while (true) : (k -= 8) {
        try out.append(gpa, @truncate(v >> k));
        if (k == 0) break;
    }
}

/// E3.5: the local node atom, written the SAME way `.atom` writes any other
/// atom (T_SMALL_ATOM_UTF8, len byte, raw name bytes) — every pid/reference/
/// port frame's Node field.
/// E5.7: write a node atom (a pid/port/ref Node field) in the encoder's
/// CANONICAL form — SMALL_ATOM_UTF8 for names ≤255 bytes (the form real OTP
/// `term_to_binary` emits for these short node names, per the empirical
/// oracle round-trip), ATOM_UTF8_EXT otherwise. Local and foreign nodes take
/// the same path, so `encode∘decode` is byte-stable over canonical frames.
fn encodeNodeAtom(gpa: std.mem.Allocator, name: []const u8, out: *std.ArrayList(u8)) !void {
    if (name.len <= std.math.maxInt(u8)) {
        try out.append(gpa, T_SMALL_ATOM_UTF8);
        try out.append(gpa, @intCast(name.len));
        try out.appendSlice(gpa, name);
    } else {
        try out.append(gpa, T_ATOM_UTF8);
        try u16be(out, gpa, @intCast(name.len));
        try out.appendSlice(gpa, name);
    }
}

const IdentityWire = struct {
    name: []const u8,
    creation: u32,
};

fn localPidWire(ctx: *FinalTerms.Ctx, t: FinalTerms.Term, local_identity: ?LocalIdentity) IdentityWire {
    if (local_identity) |id| {
        if (FinalTerms.pidCreation(ctx, t) == LOCAL_CREATION and
            std.mem.eql(u8, FinalTerms.pidNodeName(ctx, t), local_node_name))
            return .{ .name = ctx.atoms.nameOf(id.node), .creation = id.creation };
    }
    return .{ .name = FinalTerms.pidNodeName(ctx, t), .creation = FinalTerms.pidCreation(ctx, t) };
}

fn localPortWire(ctx: *FinalTerms.Ctx, t: FinalTerms.Term, local_identity: ?LocalIdentity) IdentityWire {
    if (local_identity) |id| {
        if (FinalTerms.portCreation(ctx, t) == LOCAL_CREATION and
            std.mem.eql(u8, FinalTerms.portNodeName(ctx, t), local_node_name))
            return .{ .name = ctx.atoms.nameOf(id.node), .creation = id.creation };
    }
    return .{ .name = FinalTerms.portNodeName(ctx, t), .creation = FinalTerms.portCreation(ctx, t) };
}

fn localRefWire(ctx: *FinalTerms.Ctx, t: FinalTerms.Term, local_identity: ?LocalIdentity) IdentityWire {
    if (local_identity) |id| {
        if (FinalTerms.refCreation(ctx, t) == LOCAL_CREATION and
            std.mem.eql(u8, FinalTerms.refNodeName(ctx, t), local_node_name))
            return .{ .name = ctx.atoms.nameOf(id.node), .creation = id.creation };
    }
    return .{ .name = FinalTerms.refNodeName(ctx, t), .creation = FinalTerms.refCreation(ctx, t) };
}

/// Proper list of small ints 0..255, length 1..65535? → STRING_EXT payload.
fn stringable(ctx: *FinalTerms.Ctx, t0: FinalTerms.Term, len_out: *usize) bool {
    var t = t0;
    var n: usize = 0;
    while (FinalTerms.kindOf(ctx, t) == .cons) {
        const h = FinalTerms.listHead(ctx, t);
        if (!FinalTerms.repIsSmall(h)) return false;
        const v = FinalTerms.smallValOf(h);
        if (v < 0 or v > 255) return false;
        n += 1;
        if (n > 65535) return false;
        t = FinalTerms.listTail(ctx, t);
    }
    if (FinalTerms.kindOf(ctx, t) != .nil) return false;
    if (n == 0) return false;
    len_out.* = n;
    return true;
}

fn encodeTerm(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, t: FinalTerms.Term, out: *std.ArrayList(u8), local_identity: ?LocalIdentity) EncodeError!void {
    switch (FinalTerms.kindOf(ctx, t)) {
        .number => {
            if (FinalTerms.repIsSmall(t)) {
                const v = FinalTerms.smallValOf(t);
                if (v >= 0 and v <= 255) {
                    try out.append(gpa, T_SMALL_INTEGER);
                    try out.append(gpa, @intCast(v));
                    return;
                }
                if (v >= std.math.minInt(i32) and v <= std.math.maxInt(i32)) {
                    try out.append(gpa, T_INTEGER);
                    try u32be(out, gpa, @bitCast(@as(i32, @intCast(v))));
                    return;
                }
                // |v| ≥ 2^31: SMALL_BIG little-endian magnitude
                const mag: u64 = @abs(v);
                try encodeSmallBig(gpa, out, v < 0, &.{mag});
                return;
            }
            if (FinalTerms.repIsFloat(ctx, t)) {
                try out.append(gpa, T_NEW_FLOAT);
                const bits: u64 = @bitCast(FinalTerms.floatValOf(ctx, t));
                var k: u6 = 56;
                while (true) : (k -= 8) {
                    try out.append(gpa, @truncate(bits >> k));
                    if (k == 0) break;
                }
                return;
            }
            const p = FinalTerms.bigPartsOf(ctx, t);
            try encodeSmallBig(gpa, out, !p.positive, p.limbs);
        },
        .atom => {
            const name = ctx.atoms.nameOf(FinalTerms.atomIdxOf(t));
            std.debug.assert(name.len < 256);
            try out.append(gpa, T_SMALL_ATOM_UTF8);
            try out.append(gpa, @intCast(name.len));
            try out.appendSlice(gpa, name);
        },
        .nil => try out.append(gpa, T_NIL),
        .cons => {
            var slen: usize = 0;
            if (stringable(ctx, t, &slen)) {
                try out.append(gpa, T_STRING);
                try u16be(out, gpa, @intCast(slen));
                var cur = t;
                while (FinalTerms.kindOf(ctx, cur) == .cons) {
                    try out.append(gpa, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(ctx, cur))));
                    cur = FinalTerms.listTail(ctx, cur);
                }
                return;
            }
            // count proper elements; remember the tail
            var n: u32 = 0;
            var cur = t;
            while (FinalTerms.kindOf(ctx, cur) == .cons) {
                n += 1;
                cur = FinalTerms.listTail(ctx, cur);
            }
            try out.append(gpa, T_LIST);
            try u32be(out, gpa, n);
            cur = t;
            while (FinalTerms.kindOf(ctx, cur) == .cons) {
                try encodeTerm(gpa, ctx, FinalTerms.listHead(ctx, cur), out, local_identity);
                cur = FinalTerms.listTail(ctx, cur);
            }
            try encodeTerm(gpa, ctx, cur, out, local_identity); // tail (NIL when proper)
        },
        .tuple => {
            const n = FinalTerms.tupleArity(ctx, t);
            if (n < 256) {
                try out.append(gpa, T_SMALL_TUPLE);
                try out.append(gpa, @intCast(n));
            } else {
                try out.append(gpa, T_LARGE_TUPLE);
                try u32be(out, gpa, @intCast(n));
            }
            for (0..n) |k| try encodeTerm(gpa, ctx, FinalTerms.tupleElem(ctx, t, k), out, local_identity);
        },
        .map => {
            const n = FinalTerms.mapSize(ctx, t);
            try out.append(gpa, T_MAP);
            try u32be(out, gpa, @intCast(n));
            const pk = try gpa.alloc(FinalTerms.Term, n);
            defer gpa.free(pk);
            const pv = try gpa.alloc(FinalTerms.Term, n);
            defer gpa.free(pv);
            _ = FinalTerms.mapPairs(ctx, t, pk, pv);
            for (0..n) |k| {
                try encodeTerm(gpa, ctx, pk[k], out, local_identity);
                try encodeTerm(gpa, ctx, pv[k], out, local_identity);
            }
        },
        .binary => {
            // E3.1-fix / E3.2: `.binary` buckets BOTH true binaries and
            // bitstrings (term_algebra's E3.1 `kindOf`). `binBytes` reads
            // the SUBTAG_BINARY payload directly and is wrong for a
            // SUBTAG_BITSTRING term (its header word is `bit_len`, a BIT
            // count, not a byte count) — reading it as bytes under-reports
            // or panics OOB for a sub-byte bitstring, so the bitstring
            // branch below is mandatory, not an optimization.
            //
            // BEAM: a byte-ALIGNED bitstring (`bit_len % 8 == 0`) IS a
            // binary denotationally (byte-alignment homomorphism) and wire-
            // encodes as plain BINARY_EXT — matches `term_to_binary(<<1,2,3>>)`.
            // A sub-byte bitstring (sole reason it needs its OWN tag: the
            // wire has no other way to carry a non-byte-multiple length) wire-
            // encodes as BIT_BINARY_EXT (tag 77): `{len: u32, bits_in_last_byte:
            // u8, data}`, where `len` is the BYTE count `ceil(bit_len/8)` and
            // `bits_in_last_byte` is the count of SIGNIFICANT bits in the
            // final data byte (1..7 for anything this encoder emits — always
            // sub-byte here, since aligned took the BINARY_EXT branch above).
            //
            // MUTANT 1 (do NOT write this): `bits_in_last_byte = 8 - (bit_len
            // % 8)` is the INVERTED formula (e.g. bit_len=11 → wrong value 5
            // instead of correct 3) — killed by the round-trip law below,
            // which recovers a `bit_len` that disagrees with the original on
            // every unaligned case except the fixed point bit_len%8==4.
            if (FinalTerms.repIsBitstring(ctx, t)) {
                const bits = FinalTerms.bitstringBits(ctx, t);
                if (bits.bit_len % 8 == 0) {
                    try out.append(gpa, T_BINARY);
                    try u32be(out, gpa, @intCast(bits.bit_len / 8));
                    try out.appendSlice(gpa, bits.bytes[0 .. bits.bit_len / 8]);
                    return;
                }
                const byte_count = (bits.bit_len + 7) / 8;
                const bits_in_last_byte = bits.bit_len % 8; // CORRECT: 1..7 (never 0 here)
                try out.append(gpa, T_BIT_BINARY);
                try u32be(out, gpa, @intCast(byte_count));
                try out.append(gpa, @intCast(bits_in_last_byte));
                try out.appendSlice(gpa, bits.bytes[0..byte_count]);
                return;
            }
            const bs = FinalTerms.binBytes(ctx, t);
            try out.append(gpa, T_BINARY);
            try u32be(out, gpa, @intCast(bs.len));
            try out.appendSlice(gpa, bs);
        },
        // E7.1: local funs (repIsFun) are still M14 (Unsupported here); an
        // EXTERNAL fun `fun M:F/A` encodes as EXPORT_EXT (tag 113): module
        // atom, function atom, arity small-int — byte-identical to the host
        // `term_to_binary(fun m:f/a)`.
        .fun_ => {
            if (!FinalTerms.repIsExportFun(ctx, t)) return error.Unsupported;
            try out.append(gpa, T_EXPORT);
            try encodeTerm(gpa, ctx, FinalTerms.exportFunModule(ctx, t), out, local_identity);
            try encodeTerm(gpa, ctx, FinalTerms.exportFunFunction(ctx, t), out, local_identity);
            try out.append(gpa, T_SMALL_INTEGER);
            try out.append(gpa, FinalTerms.exportFunArity(ctx, t));
        },
        // E3.5: NEW_PID_EXT — Node, ID: u32be, Serial: u32be, Creation: u32be.
        .pid => {
            // NEW_PID_EXT's ID/Serial wire fields are u32 (a real wire-format
            // bound, not this codec's invention). `FinalTerms.pid` stores full
            // u64 fields (so the TERM ALGEBRA itself is not artificially
            // bounded — GC/hash/order all work on any u64), but a pid whose
            // number/serial does not fit u32 is a documented wire-encoding
            // capacity limit: reject cleanly (never silently truncate — same
            // discipline as the M2 bignum cap, `error.Unsupported`, not a
            // panic or a wrong byte).
            const number = FinalTerms.pidNumber(ctx, t);
            const serial = FinalTerms.pidSerial(ctx, t);
            if (number > std.math.maxInt(u32) or serial > std.math.maxInt(u32))
                return error.Unsupported;
            try out.append(gpa, T_NEW_PID_EXT);
            // E5.7: the term's OWN node atom + creation (local = nonode@nohost/0
            // ⇒ byte-identical to the pre-E5.7 encode; foreign = the external
            // node, so `term_to_binary` of a foreign pid round-trips).
            const wire = localPidWire(ctx, t, local_identity);
            try encodeNodeAtom(gpa, wire.name, out);
            try u32be(out, gpa, @truncate(number));
            try u32be(out, gpa, @truncate(serial));
            try u32be(out, gpa, wire.creation);
        },
        // E3.5: V4_PORT_EXT (our canonical encode form) — Node, ID: u64be,
        // Creation: u32be. NEW_PORT_EXT is decode-only (legacy u32 ID).
        .port => {
            try out.append(gpa, T_V4_PORT_EXT);
            const wire = localPortWire(ctx, t, local_identity);
            try encodeNodeAtom(gpa, wire.name, out);
            try u64be(out, gpa, FinalTerms.portNumber(ctx, t));
            try u32be(out, gpa, wire.creation);
        },
        // E3.5: NEWER_REFERENCE_EXT — Len: u16be (always 3, our local refs),
        // Node, Creation: u32be, ID[3]: u32be each.
        .reference => {
            try out.append(gpa, T_NEWER_REFERENCE_EXT);
            try u16be(out, gpa, 3);
            const wire = localRefWire(ctx, t, local_identity);
            try encodeNodeAtom(gpa, wire.name, out);
            try u32be(out, gpa, wire.creation);
            const words = FinalTerms.refWords(ctx, t);
            for (words) |w| try u32be(out, gpa, w);
        },
        // E3.14: RECORD_EXT — size:u32be, exported:u8, module atom, name atom,
        // size key atoms, size value terms (external.c enc_term RECORD_DEF).
        // Keys/values in stored (insertion) order.
        .native_record => {
            const n = FinalTerms.nrFieldCount(ctx, t);
            try out.append(gpa, T_RECORD_EXT);
            try u32be(out, gpa, @intCast(n));
            try out.append(gpa, if (FinalTerms.nrIsExported(ctx, t)) 1 else 0);
            try encodeTerm(gpa, ctx, FinalTerms.nrModule(ctx, t), out, local_identity);
            try encodeTerm(gpa, ctx, FinalTerms.nrName(ctx, t), out, local_identity);
            for (0..n) |i| try encodeTerm(gpa, ctx, FinalTerms.nrKeyAt(ctx, t, i), out, local_identity);
            for (0..n) |i| try encodeTerm(gpa, ctx, FinalTerms.nrValAt(ctx, t, i), out, local_identity);
        },
    }
}

fn encodeSmallBig(gpa: std.mem.Allocator, out: *std.ArrayList(u8), negative: bool, limbs: []const u64) !void {
    // magnitude bytes, little-endian, minimal
    var bytes: [64]u8 = undefined;
    var n: usize = 0;
    for (limbs, 0..) |l, li| {
        var v = l;
        for (0..8) |bi| {
            bytes[li * 8 + bi] = @truncate(v);
            v >>= 8;
        }
        n = li * 8 + 8;
    }
    while (n > 1 and bytes[n - 1] == 0) n -= 1;
    try out.append(gpa, T_SMALL_BIG);
    try out.append(gpa, @intCast(n));
    try out.append(gpa, if (negative) 1 else 0);
    try out.appendSlice(gpa, bytes[0..n]);
}

// ============================================================================
// decode
// ============================================================================

const Rd = struct {
    buf: []const u8,
    pos: usize = 0,
    fn u8_(self: *Rd) DecodeError!u8 {
        if (self.pos >= self.buf.len) return error.Truncated;
        const b = self.buf[self.pos];
        self.pos += 1;
        return b;
    }
    fn u16_(self: *Rd) DecodeError!u16 {
        return (@as(u16, try self.u8_()) << 8) | try self.u8_();
    }
    fn u32_(self: *Rd) DecodeError!u32 {
        return (@as(u32, try self.u16_()) << 16) | try self.u16_();
    }
    fn u64_(self: *Rd) DecodeError!u64 {
        return (@as(u64, try self.u32_()) << 32) | try self.u32_();
    }
    fn bytes(self: *Rd, n: usize) DecodeError![]const u8 {
        if (self.pos + n > self.buf.len) return error.Truncated;
        const s = self.buf[self.pos .. self.pos + n];
        self.pos += n;
        return s;
    }
};

pub fn decode(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, buf: []const u8) DecodeError!FinalTerms.Term {
    var r = Rd{ .buf = buf };
    const magic = try r.u8_();
    if (magic != VERSION_MAGIC) return error.UnknownTag;
    const tag = try r.u8_();
    if (tag == T_COMPRESSED) {
        const usize_ = try r.u32_();
        const inflated = try inflate(gpa, r.buf[r.pos..], usize_);
        defer gpa.free(inflated);
        var r2 = Rd{ .buf = inflated };
        return decodeTermWithAttab(gpa, ctx, &r2, null);
    }
    r.pos -= 1;
    return decodeTermWithAttab(gpa, ctx, &r, null);
}

/// E18 Task 3 (distributed signals): decode ONE versioned external term and
/// report how many bytes it consumed. A DOP `PASS_THROUGH` distribution frame
/// concatenates a control term and (for SEND/REG_SEND) a message term with no
/// length delimiter, so the inbound decoder must learn where the control term
/// ends to find the message. `consumed` is the reader position AFTER the term
/// (== the length of `encode(t)` for a well-formed single-term buffer), so
/// `buf[consumed..]` is exactly the trailing bytes. No compressed handling: DOP
/// control/message terms are never zlib-wrapped on the wire.
pub const Consumed = struct { term: FinalTerms.Term, consumed: usize };
pub fn decodeConsumed(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, buf: []const u8) DecodeError!Consumed {
    var r = Rd{ .buf = buf };
    const magic = try r.u8_();
    if (magic != VERSION_MAGIC) return error.UnknownTag;
    const t = try decodeTermWithAttab(gpa, ctx, &r, null);
    return .{ .term = t, .consumed = r.pos };
}

/// E8.2f: decode one distribution-external term using an explicit atom
/// translation table. OTP's debug BIF still expects the leading ETF version
/// byte and accepts ordinary ETF terms; `ATOM_CACHE_REF` entries are resolved
/// against `attab`.
pub fn decodeDist(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, attab: []const FinalTerms.Term, buf: []const u8) DecodeError!FinalTerms.Term {
    if (attab.len > 255) return error.BadAtomCache;
    for (attab) |atom| {
        if (FinalTerms.kindOf(ctx, atom) != .atom) return error.BadAtomCache;
    }
    var r = Rd{ .buf = buf };
    const magic = try r.u8_();
    if (magic != VERSION_MAGIC) return error.UnknownTag;
    return decodeTermWithAttab(gpa, ctx, &r, attab);
}

/// W-17 (LitT literals): decode ONE external-format term WITHOUT the leading
/// version byte (131). The LitT chunk stores each literal as a version-less ETF
/// term (the tag byte comes first), so the loader enters at exactly the point
/// `decode` reaches AFTER stripping the version byte. Exposed so the loader
/// reuses the term semantics verbatim — NO duplicated ETF decoding.
pub fn decodeNoVersion(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, buf: []const u8) DecodeError!FinalTerms.Term {
    var r = Rd{ .buf = buf };
    return decodeTermWithAttab(gpa, ctx, &r, null);
}

/// W-17: inflate a raw zlib stream to `expect_len` bytes with the SAME
/// decompressor the compressed-ETF path uses (erl_zlib.c). The LitT chunk
/// payload is `u32be uncompressed-size` followed by this zlib blob.
pub fn inflateZlib(gpa: std.mem.Allocator, compressed: []const u8, expect_len: u32) DecodeError![]u8 {
    return inflate(gpa, compressed, expect_len);
}

fn inflate(gpa: std.mem.Allocator, compressed: []const u8, expect_len: u32) DecodeError![]u8 {
    var rd: std.Io.Reader = .fixed(compressed);
    const window = gpa.alloc(u8, std.compress.flate.max_window_len) catch return error.OutOfMemory;
    defer gpa.free(window);
    var d = std.compress.flate.Decompress.init(&rd, .zlib, window);
    const out = gpa.alloc(u8, expect_len) catch return error.OutOfMemory;
    errdefer gpa.free(out);
    var total: usize = 0;
    while (total < out.len) {
        const n = d.reader.readSliceShort(out[total..]) catch return error.BadCompressed;
        if (n == 0) break;
        total += n;
    }
    if (total != expect_len) return error.BadCompressed; // size must be exact
    return out;
}

fn decodeTerm(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, r: *Rd) DecodeError!FinalTerms.Term {
    return decodeTermWithAttab(gpa, ctx, r, null);
}

fn decodeTermWithAttab(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, r: *Rd, attab: ?[]const FinalTerms.Term) DecodeError!FinalTerms.Term {
    const tag = try r.u8_();
    switch (tag) {
        T_ATOM_CACHE_REF => {
            const idx: usize = try r.u8_();
            const table = attab orelse return error.BadAtomCache;
            if (idx >= table.len) return error.BadAtomCache;
            return table[idx];
        },
        T_SMALL_INTEGER => return FinalTerms.int(ctx, try r.u8_()),
        T_INTEGER => {
            const v: i32 = @bitCast(try r.u32_());
            return FinalTerms.int(ctx, v);
        },
        T_NEW_FLOAT => {
            var bits: u64 = 0;
            for (0..8) |_| bits = (bits << 8) | try r.u8_();
            return FinalTerms.float(ctx, @bitCast(bits));
        },
        T_SMALL_BIG, T_LARGE_BIG => {
            const n: usize = if (tag == T_SMALL_BIG) try r.u8_() else try r.u32_();
            const sign = try r.u8_();
            if (n > FinalTerms.max_limbs * 8) return error.BignumTooLarge;
            const mag = try r.bytes(n);
            var limbs: [FinalTerms.max_limbs]u64 = @splat(0);
            for (mag, 0..) |b, k| limbs[k / 8] |= @as(u64, b) << @intCast(8 * (k % 8));
            var nl: usize = (n + 7) / 8;
            while (nl > 1 and limbs[nl - 1] == 0) nl -= 1;
            // canonical smallness: small-fitting values must encode small
            if (nl == 1) {
                const l = limbs[0];
                if (sign == 0 and l < (1 << 59)) return FinalTerms.int(ctx, @intCast(l));
                if (sign == 1 and l <= (1 << 59)) return FinalTerms.int(ctx, -@as(i64, @intCast(l)));
            }
            return FinalTerms.intFromLimbs(ctx, sign == 0, limbs[0..nl]) catch return error.OutOfMemory;
        },
        // E7.1: EXPORT_EXT — Module(atom), Function(atom), Arity(small int
        // term). A non-atom Module/Function or a non-small-int / out-of-range
        // Arity is `error.BadRecord` (rejection is total, never a wrong term).
        T_EXPORT => {
            const module = try decodeTermWithAttab(gpa, ctx, r, attab);
            const function = try decodeTermWithAttab(gpa, ctx, r, attab);
            const arity_t = try decodeTermWithAttab(gpa, ctx, r, attab);
            if (FinalTerms.kindOf(ctx, module) != .atom or FinalTerms.kindOf(ctx, function) != .atom)
                return error.BadRecord;
            if (!FinalTerms.repIsSmall(arity_t)) return error.BadRecord;
            const av = FinalTerms.smallValOf(arity_t);
            if (av < 0 or av > std.math.maxInt(u8)) return error.BadRecord;
            return FinalTerms.makeExportFun(ctx, module, function, @intCast(av)) catch return error.OutOfMemory;
        },
        T_ATOM, T_ATOM_UTF8 => {
            const n = try r.u16_();
            const name = try r.bytes(n);
            const idx = ctx.atoms.intern(name) catch return error.AtomTableFull;
            return FinalTerms.atom(ctx, idx);
        },
        T_SMALL_ATOM, T_SMALL_ATOM_UTF8 => {
            const n = try r.u8_();
            const name = try r.bytes(n);
            const idx = ctx.atoms.intern(name) catch return error.AtomTableFull;
            return FinalTerms.atom(ctx, idx);
        },
        T_NIL => return FinalTerms.nil(ctx),
        T_STRING => {
            const n = try r.u16_();
            const bs = try r.bytes(n);
            var acc = FinalTerms.nil(ctx);
            var k = bs.len;
            while (k > 0) {
                k -= 1;
                acc = FinalTerms.cons(ctx, FinalTerms.int(ctx, bs[k]), acc) catch return error.OutOfMemory;
            }
            return acc;
        },
        T_LIST => {
            const n = try r.u32_();
            const elems = gpa.alloc(FinalTerms.Term, n) catch return error.OutOfMemory;
            defer gpa.free(elems);
            for (elems) |*e| e.* = try decodeTermWithAttab(gpa, ctx, r, attab);
            const tail = try decodeTermWithAttab(gpa, ctx, r, attab);
            var acc = tail;
            var k = elems.len;
            while (k > 0) {
                k -= 1;
                acc = FinalTerms.cons(ctx, elems[k], acc) catch return error.OutOfMemory;
            }
            return acc;
        },
        T_SMALL_TUPLE, T_LARGE_TUPLE => {
            const n: usize = if (tag == T_SMALL_TUPLE) try r.u8_() else try r.u32_();
            const elems = gpa.alloc(FinalTerms.Term, n) catch return error.OutOfMemory;
            defer gpa.free(elems);
            for (elems) |*e| e.* = try decodeTermWithAttab(gpa, ctx, r, attab);
            return FinalTerms.tuple(ctx, elems) catch return error.OutOfMemory;
        },
        T_MAP => {
            const n = try r.u32_();
            const ks = gpa.alloc(FinalTerms.Term, n) catch return error.OutOfMemory;
            defer gpa.free(ks);
            const vs = gpa.alloc(FinalTerms.Term, n) catch return error.OutOfMemory;
            defer gpa.free(vs);
            for (0..n) |k| {
                ks[k] = try decodeTermWithAttab(gpa, ctx, r, attab);
                vs[k] = try decodeTermWithAttab(gpa, ctx, r, attab);
            }
            return FinalTerms.mapNew(ctx, ks, vs) catch return error.OutOfMemory;
        },
        T_BINARY => {
            const n = try r.u32_();
            return FinalTerms.binary(ctx, try r.bytes(n)) catch return error.OutOfMemory;
        },
        T_BIT_BINARY => {
            // {len: u32, bits_in_last_byte: u8, data} — Term-Kind Recipe
            // step-4 rejection discipline: a malformed `bits_in_last_byte`
            // (0 or >8) is a CLEAN decode error, never a panic/OOB read.
            // `len == 0` is likewise malformed here: BEAM only ever pairs
            // `len == 0` with `bits_in_last_byte == 0` (the degenerate
            // empty case), which the `== 0` check already rejects, so this
            // guard also prevents the `(len - 1)` underflow below.
            const len = try r.u32_();
            const bits_in_last_byte = try r.u8_();
            if (len == 0 or bits_in_last_byte == 0 or bits_in_last_byte > 8) return error.BadBitBinary;
            const data = try r.bytes(len);
            const bit_len: usize = (@as(usize, len) - 1) * 8 + bits_in_last_byte;
            return FinalTerms.bitstring(ctx, data, bit_len) catch return error.OutOfMemory;
        },
        // E5.7: a NEW_PID_EXT from ANY node decodes to a first-class pid term.
        // The Node atom is interned (local → nonode@nohost; foreign → the
        // external node atom, observable via `node/1`); Creation is carried
        // so `term_to_binary` re-encodes the identity byte-exactly. Verified
        // empirically against the OTP oracle (foreign `<N.x.y>` accept + byte-
        // stable round-trip) — DIVERGENCE 54 external-pid clause discharged.
        T_NEW_PID_EXT => {
            const node = try decodeTermWithAttab(gpa, ctx, r, attab);
            if (FinalTerms.kindOf(ctx, node) != .atom) return error.ForeignNode;
            const node_idx = FinalTerms.atomIdxOf(node);
            const number = try r.u32_();
            const serial = try r.u32_();
            const creation = try r.u32_();
            return FinalTerms.pidExt(ctx, number, serial, node_idx, creation) catch return error.OutOfMemory;
        },
        T_NEW_PORT_EXT, T_V4_PORT_EXT => {
            const node = try decodeTermWithAttab(gpa, ctx, r, attab);
            if (FinalTerms.kindOf(ctx, node) != .atom) return error.ForeignNode;
            const node_idx = FinalTerms.atomIdxOf(node);
            const number: u64 = if (tag == T_NEW_PORT_EXT) try r.u32_() else try r.u64_();
            const creation = try r.u32_();
            return FinalTerms.portExt(ctx, number, node_idx, creation) catch return error.OutOfMemory;
        },
        T_NEWER_REFERENCE_EXT => {
            const len = try r.u16_();
            const node = try decodeTermWithAttab(gpa, ctx, r, attab);
            if (FinalTerms.kindOf(ctx, node) != .atom) return error.ForeignNode;
            const node_idx = FinalTerms.atomIdxOf(node);
            // MUTANT 2 site (see MUTATION_LOG.md E3.5 mutant 2): dropping
            // this Creation read misaligns every ID word that follows —
            // killed by the ETF round-trip law (`w[0]` would decode as the
            // wire's Creation value instead of the true first ID word).
            const creation = try r.u32_();
            if (len != 3) return error.UnsupportedRefLen; // E5 boundary: refs are always 3 words
            var words: [3]u32 = undefined;
            for (&words) |*w| w.* = try r.u32_();
            return FinalTerms.refExt(ctx, words, node_idx, creation) catch return error.OutOfMemory;
        },
        // E3.14: RECORD_EXT — size:u32, exported:u8 (0/1 only), module atom,
        // name atom, size key atoms, size value terms. Rejection law: a
        // non-atom module/name/key, a size beyond the field cap, or an
        // exported byte outside {0,1} is a clean `error.BadRecord`.
        T_RECORD_EXT => {
            const size = try r.u32_();
            if (size > ta.max_nr_fields) return error.BadRecord;
            const n: usize = @intCast(size);
            const exported_byte = try r.u8_();
            if (exported_byte > 1) return error.BadRecord;
            const module = try decodeTermWithAttab(gpa, ctx, r, attab);
            const name = try decodeTermWithAttab(gpa, ctx, r, attab);
            if (FinalTerms.kindOf(ctx, module) != .atom or FinalTerms.kindOf(ctx, name) != .atom)
                return error.BadRecord;
            var keys: [ta.max_nr_fields]FinalTerms.Term = undefined;
            var vals: [ta.max_nr_fields]FinalTerms.Term = undefined;
            for (0..n) |i| {
                keys[i] = try decodeTermWithAttab(gpa, ctx, r, attab);
                if (FinalTerms.kindOf(ctx, keys[i]) != .atom) return error.BadRecord;
            }
            for (0..n) |i| vals[i] = try decodeTermWithAttab(gpa, ctx, r, attab);
            return FinalTerms.nativeRecord(ctx, module, name, exported_byte == 1, keys[0..n], vals[0..n]) catch return error.OutOfMemory;
        },
        else => return error.UnknownTag,
    }
}

// ============================================================================
// Wire-term generator (all kinds the codec speaks — E7.1: incl. external funs)
// ============================================================================

pub fn genWireTerm(random: std.Random, ctx: *FinalTerms.Ctx, depth: usize) !FinalTerms.Term {
    const Variant = enum { small, byte, big, float, atom, nil, binary, reference, port, pid, cons, tuple, map, native_record, export_fun };
    const pick: Variant = if (depth == 0) switch (random.uintLessThan(u8, 10)) {
        0 => .small,
        1 => .byte,
        2 => .big,
        3 => .float,
        4 => .atom,
        5 => .binary,
        6 => .reference,
        7 => .port,
        8 => .pid,
        else => .nil,
    } else random.enumValue(Variant);
    switch (pick) {
        .small => return FinalTerms.int(ctx, @as(i64, random.int(i48))),
        .byte => return FinalTerms.int(ctx, random.uintLessThan(u16, 256)), // exercises STRING
        .big => {
            const mag: u128 = (@as(u128, 1) << 61) | random.int(u64);
            return FinalTerms.intFromI128(ctx, if (random.boolean()) @intCast(mag) else -@as(i128, @intCast(mag)));
        },
        .float => return FinalTerms.float(ctx, @as(f64, @floatFromInt(@as(i64, random.int(i32)))) * 0x1p-8),
        .atom => {
            var buf: [6]u8 = undefined;
            const len = 1 + random.uintLessThan(usize, buf.len);
            for (buf[0..len]) |*b| b.* = 'a' + random.uintLessThan(u8, 26);
            const idx = try ctx.atoms.intern(buf[0..len]);
            return FinalTerms.atom(ctx, idx);
        },
        .nil => return FinalTerms.nil(ctx),
        .binary => {
            var buf: [12]u8 = undefined;
            const len = random.uintLessThan(usize, buf.len + 1);
            for (buf[0..len]) |*b| b.* = random.int(u8);
            return FinalTerms.binary(ctx, buf[0..len]);
        },
        // E3.5: pid/reference/port are now wire terms (see the module doc
        // comment) — mixed into the wire-term generator so the round-trip
        // law above exercises them alongside everything else.
        .reference => {
            const words: [3]u32 = .{ random.int(u32), random.int(u32), random.int(u32) };
            return FinalTerms.ref(ctx, words);
        },
        .port => return FinalTerms.port(ctx, random.int(u32)),
        .pid => return FinalTerms.pid(ctx, random.int(u32), random.int(u32)),
        .cons => return FinalTerms.cons(
            ctx,
            try genWireTerm(random, ctx, depth - 1),
            try genWireTerm(random, ctx, depth - 1),
        ),
        .tuple => {
            const n = random.uintLessThan(u8, 4);
            var buf: [4]FinalTerms.Term = undefined;
            for (0..n) |k| buf[k] = try genWireTerm(random, ctx, depth - 1);
            return FinalTerms.tuple(ctx, buf[0..n]);
        },
        .map => {
            const n = random.uintLessThan(u8, 4);
            var ks: [4]FinalTerms.Term = undefined;
            var vs: [4]FinalTerms.Term = undefined;
            for (0..n) |k| {
                ks[k] = try genWireTerm(random, ctx, depth - 1);
                vs[k] = try genWireTerm(random, ctx, depth - 1);
            }
            return FinalTerms.mapNew(ctx, ks[0..n], vs[0..n]);
        },
        // E3.14: native records round-trip through RECORD_EXT. Distinct atom
        // keys (a1,a2,… — never colliding), arbitrary value terms.
        .native_record => {
            const module = try genAtom(random, ctx);
            const name = try genAtom(random, ctx);
            const n = random.uintLessThan(u8, 4);
            var ks: [4]FinalTerms.Term = undefined;
            var vs: [4]FinalTerms.Term = undefined;
            for (0..n) |k| {
                var buf: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "f{d}", .{k}) catch unreachable;
                ks[k] = FinalTerms.atom(ctx, try ctx.atoms.intern(s));
                vs[k] = try genWireTerm(random, ctx, depth - 1);
            }
            return FinalTerms.nativeRecord(ctx, module, name, random.boolean(), ks[0..n], vs[0..n]);
        },
        // E7.1: external funs round-trip through EXPORT_EXT (tag 113).
        .export_fun => {
            const module = try genAtom(random, ctx);
            const function = try genAtom(random, ctx);
            return FinalTerms.makeExportFun(ctx, module, function, random.uintLessThan(u8, 5));
        },
    }
}

fn genAtom(random: std.Random, ctx: *FinalTerms.Ctx) !FinalTerms.Term {
    var buf: [6]u8 = undefined;
    const len = 1 + random.uintLessThan(usize, buf.len);
    for (buf[0..len]) |*b| b.* = 'a' + random.uintLessThan(u8, 26);
    return FinalTerms.atom(ctx, try ctx.atoms.intern(buf[0..len]));
}

// ============================================================================
// Tests
// ============================================================================

test "LAW round-trip: denote∘decode∘encode = denote over generated wire terms" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0xE7F0, .iterations = 150 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();

        const t = try genWireTerm(random, &ctx, 4);
        const before = try FinalTerms.denote(&ctx, sa, t);
        var bytes = try encode(gpa, &ctx, t);
        defer bytes.deinit(gpa);
        const back = try decode(gpa, &ctx, bytes.items);
        try expectLaw(spec.eqlExact(before, try FinalTerms.denote(&ctx, sa, back)), "etf: round-trip preserves denotation", cfg, i);

        // determinism: twin term encodes to identical bytes
        var twin_prng = std.Random.DefaultPrng.init(cfg.seed +% i +% 1000);
        var twin_prng2 = std.Random.DefaultPrng.init(cfg.seed +% i +% 1000);
        const t1 = try genWireTerm(twin_prng.random(), &ctx, 3);
        const t2 = try genWireTerm(twin_prng2.random(), &ctx, 3);
        var b1 = try encode(gpa, &ctx, t1);
        defer b1.deinit(gpa);
        var b2 = try encode(gpa, &ctx, t2);
        defer b2.deinit(gpa);
        try expectLaw(std.mem.eql(u8, b1.items, b2.items), "etf: encoding is deterministic on twins", cfg, i);
    }
}

/// The golden-vector terms, constructed EXACTLY as the erl script did.
fn goldenTerms(ctx: *FinalTerms.Ctx, atoms: *AtomTable, out: *[27]FinalTerms.Term) !void {
    const F = FinalTerms;
    const a_hello = try atoms.intern("hello");
    const a_ok = try atoms.intern("ok");
    const a_a = try atoms.intern("a");
    const a_x = try atoms.intern("x");
    const a_head = try atoms.intern("head");
    const a_mixed = try atoms.intern("mixed");
    const a_k = try atoms.intern("k");
    var i: usize = 0;
    out[i] = F.int(ctx, 0);
    i += 1;
    out[i] = F.int(ctx, 255);
    i += 1;
    out[i] = F.int(ctx, 256);
    i += 1;
    out[i] = F.int(ctx, -1);
    i += 1;
    out[i] = F.int(ctx, 123456789);
    i += 1;
    out[i] = F.int(ctx, -123456789);
    i += 1;
    out[i] = try F.intFromI128(ctx, 1 << 59);
    i += 1;
    out[i] = try F.intFromI128(ctx, 1 << 100);
    i += 1;
    out[i] = try F.intFromI128(ctx, -(1 << 100));
    i += 1;
    out[i] = F.float(ctx, 1.5);
    i += 1;
    out[i] = F.float(ctx, 0.0);
    i += 1;
    out[i] = F.atom(ctx, a_hello);
    i += 1;
    out[i] = F.atom(ctx, a_ok);
    i += 1;
    out[i] = F.nil(ctx);
    i += 1;
    out[i] = try list(ctx, &.{ F.int(ctx, 1), F.int(ctx, 2), F.int(ctx, 3) });
    i += 1;
    out[i] = try list(ctx, &.{ F.int(ctx, 300), F.int(ctx, 400) });
    i += 1;
    out[i] = try F.cons(ctx, F.int(ctx, 1), F.int(ctx, 2)); // [1|2]
    i += 1;
    out[i] = try F.tuple(ctx, &.{});
    i += 1;
    out[i] = try F.tuple(ctx, &.{ F.int(ctx, 1), F.atom(ctx, a_ok) });
    i += 1;
    out[i] = try F.tuple(ctx, &.{
        try F.tuple(ctx, &.{ F.int(ctx, 1), F.int(ctx, 2) }),
        try list(ctx, &.{F.int(ctx, 3)}),
    });
    i += 1;
    out[i] = try F.mapNew(ctx, &.{}, &.{});
    i += 1;
    out[i] = try F.mapNew(ctx, &.{F.int(ctx, 1)}, &.{F.int(ctx, 2)});
    i += 1;
    out[i] = try F.binary(ctx, &.{});
    i += 1;
    out[i] = try F.binary(ctx, &.{ 1, 2, 3 });
    i += 1;
    out[i] = try F.binary(ctx, "hello");
    i += 1;
    out[i] = try F.mapNew(ctx, &.{ F.atom(ctx, a_a), F.int(ctx, 1) }, &.{ F.int(ctx, 1), F.atom(ctx, a_x) });
    i += 1;
    out[i] = try list(ctx, &.{
        F.atom(ctx, a_head),
        try F.tuple(ctx, &.{ F.atom(ctx, a_mixed), try F.binary(ctx, "bin") }),
        try F.mapNew(ctx, &.{F.atom(ctx, a_k)}, &.{try list(ctx, &.{ F.int(ctx, 1), F.int(ctx, 2) })}),
    });
    i += 1;
    std.debug.assert(i == 27);
}

fn list(ctx: *FinalTerms.Ctx, xs: []const FinalTerms.Term) !FinalTerms.Term {
    var acc = FinalTerms.nil(ctx);
    var k = xs.len;
    while (k > 0) {
        k -= 1;
        acc = try FinalTerms.cons(ctx, xs[k], acc);
    }
    return acc;
}

test "GOLDEN: node vectors decode correctly, plain AND compressed; encode is byte-exact" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    var expected: [27]FinalTerms.Term = undefined;
    try goldenTerms(&ctx, &atoms, &expected);

    const blob = @embedFile("etf_vectors.bin");
    var r = Rd{ .buf = blob };
    const count = try r.u32_();
    try std.testing.expectEqual(@as(u32, 27), count);

    for (0..count) |k| {
        const plen = try r.u32_();
        const pbytes = try r.bytes(plen);
        const clen = try r.u32_();
        const cbytes = try r.bytes(clen);

        // NODE DECODE (plain)
        const got_p = try decode(gpa, &ctx, pbytes);
        try std.testing.expect(spec.eqlExact(
            try FinalTerms.denote(&ctx, sa, expected[k]),
            try FinalTerms.denote(&ctx, sa, got_p),
        ));
        // NODE DECODE (compressed — decode must transparently inflate)
        const got_c = try decode(gpa, &ctx, cbytes);
        try std.testing.expect(spec.eqlExact(
            try FinalTerms.denote(&ctx, sa, expected[k]),
            try FinalTerms.denote(&ctx, sa, got_c),
        ));
        // NODE ENCODE: byte-exact against term_to_binary
        var ours = try encode(gpa, &ctx, expected[k]);
        defer ours.deinit(gpa);
        try std.testing.expect(std.mem.eql(u8, pbytes, ours.items));
    }
}

test "GOLDEN: 40-key map (HAMT on our side) decodes to the right denotation" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    const got = try decode(gpa, &ctx, @embedFile("etf_bigmap.bin"));
    try std.testing.expectEqual(@as(usize, 40), FinalTerms.mapSize(&ctx, got));
    try std.testing.expect(!FinalTerms.mapRepIsFlat(&ctx, got)); // really a HAMT
    var expect = try FinalTerms.mapNew(&ctx, &.{}, &.{});
    for (1..41) |k| {
        expect = try FinalTerms.mapPut(&ctx, expect, FinalTerms.int(&ctx, @intCast(k)), FinalTerms.int(&ctx, @intCast(k * 3)));
    }
    try std.testing.expect(spec.eqlExact(
        try FinalTerms.denote(&ctx, sa, expect),
        try FinalTerms.denote(&ctx, sa, got),
    ));
    // round-trip the HAMT through OUR encoder too
    var bytes = try encode(gpa, &ctx, got);
    defer bytes.deinit(gpa);
    const back = try decode(gpa, &ctx, bytes.items);
    try std.testing.expect(spec.eqlExact(
        try FinalTerms.denote(&ctx, sa, expect),
        try FinalTerms.denote(&ctx, sa, back),
    ));
}

test "Tag tolerance: legacy ATOM_EXT(100) and SMALL_ATOM(115) decode" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const legacy100 = [_]u8{ 131, 100, 0, 2, 'o', 'k' };
    const legacy115 = [_]u8{ 131, 115, 2, 'o', 'k' };
    const a1 = try decode(gpa, &ctx, &legacy100);
    const a2 = try decode(gpa, &ctx, &legacy115);
    const ok_atom = FinalTerms.atom(&ctx, try atoms.intern("ok"));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, a1, ok_atom));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, a2, ok_atom));
}

test "Named rejection: compressed frame whose size field lies is REFUSED" {
    // (added after a mutant survived: without the exact-size check, a short
    // zlib stream whose prefix happens to decode would be accepted SILENTLY)
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const lying = [_]u8{ 131, 80, 0, 0, 0, 5, 120, 156, 75, 100, 7, 0, 0, 203, 0, 105 }; // declares 5 bytes, inflates to 2
    try std.testing.expectError(error.BadCompressed, decode(gpa, &ctx, &lying));
}

test "Named rejections: truncation, unknown tag, oversized bignum" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    try std.testing.expectError(error.Truncated, decode(gpa, &ctx, &[_]u8{ 131, 98, 0, 0 }));
    try std.testing.expectError(error.UnknownTag, decode(gpa, &ctx, &[_]u8{ 131, 42 }));
    var big: [7]u8 = undefined;
    big[0] = 131;
    big[1] = T_LARGE_BIG;
    const n: u32 = FinalTerms.max_limbs * 8 + 1; // > cap
    big[2] = @intCast((n >> 24) & 0xFF);
    big[3] = @intCast((n >> 16) & 0xFF);
    big[4] = @intCast((n >> 8) & 0xFF);
    big[5] = @intCast(n & 0xFF);
    big[6] = 0; // sign
    try std.testing.expectError(error.BignumTooLarge, decode(gpa, &ctx, &big));
}

test "LAW E3.2: aligned bitstring round-trips as BINARY_EXT (byte-alignment homomorphism); <<>> too" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    // <<>> — bit_len 0 IS aligned: round-trips as an empty binary.
    const empty_bits = try FinalTerms.bitstring(&ctx, &.{}, 0);
    var enc_empty = try encode(gpa, &ctx, empty_bits);
    defer enc_empty.deinit(gpa);
    try std.testing.expectEqual(@as(u8, T_BINARY), enc_empty.items[1]); // tag byte, right after VERSION_MAGIC
    var ctx2 = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx2.deinit();
    const decoded_empty = try decode(gpa, &ctx2, enc_empty.items);
    try std.testing.expect(FinalTerms.kindOf(&ctx2, decoded_empty) == .binary);
    try std.testing.expectEqual(@as(usize, 0), FinalTerms.binBytes(&ctx2, decoded_empty).len);

    // aligned bitstring (bit_len % 8 == 0): encodes as a plain binary and
    // round-trips byte-exact — an aligned bitstring IS a binary
    // denotationally (byte-alignment homomorphism); BEAM:
    // `term_to_binary(<<1,2,3>>)` uses BINARY_EXT, never BIT_BINARY_EXT.
    const aligned = try FinalTerms.bitstring(&ctx, "hello", 40);
    var enc = try encode(gpa, &ctx, aligned);
    defer enc.deinit(gpa);
    try std.testing.expectEqual(@as(u8, T_BINARY), enc.items[1]);
    var ctx3 = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx3.deinit();
    const decoded = try decode(gpa, &ctx3, enc.items);
    try std.testing.expect(FinalTerms.kindOf(&ctx3, decoded) == .binary);
    try std.testing.expectEqualSlices(u8, "hello", FinalTerms.binBytes(&ctx3, decoded));
}

test "LAW E3.2 WORKED: BIT_BINARY_EXT round-trip for a sub-byte bitstring — decode(encode(<<1:3>>)) == <<1:3>>, byte-exact golden" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    // <<1:3>> — 3 significant bits, value 0b001 in the top 3 bits of one byte:
    // 0b001_00000 = 0x20. BEAM's term_to_binary(<<1:3>>) golden byte sequence
    // (pinned; no differential-printer path available in this harness — see
    // report): 131, 77 (BIT_BINARY_EXT), 0,0,0,1 (len=1 u32be), 3
    // (bits_in_last_byte), 0x20 (data).
    const bs = try FinalTerms.bitstring(&ctx, &.{0b001_00000}, 3);
    var enc = try encode(gpa, &ctx, bs);
    defer enc.deinit(gpa);
    try std.testing.expectEqualSlices(u8, &.{ 131, T_BIT_BINARY, 0, 0, 0, 1, 3, 0b001_00000 }, enc.items);

    const back = try decode(gpa, &ctx, enc.items);
    try std.testing.expect(FinalTerms.repIsBitstring(&ctx, back));
    const bits = FinalTerms.bitstringBits(&ctx, back);
    try std.testing.expectEqual(@as(usize, 3), bits.bit_len);
    try std.testing.expectEqualSlices(u8, &.{0b001_00000}, bits.bytes);
}

test "LAW E3.2: decode∘encode = id over seeded unaligned bitstrings (bit_len 1..127)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(0xB177B17);
    const random = prng.random();

    for (0..200) |iter| {
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();

        var buf: [16]u8 = undefined;
        random.bytes(&buf);
        // bit_len drawn from the SUB-BYTE range (never a multiple of 8),
        // so every iteration exercises BIT_BINARY_EXT, not BINARY_EXT.
        var bit_len: usize = 1 + random.uintLessThan(usize, buf.len * 8 - 1);
        if (bit_len % 8 == 0) bit_len += 1;
        const bs = try FinalTerms.bitstring(&ctx, &buf, bit_len);

        var enc = try encode(gpa, &ctx, bs);
        defer enc.deinit(gpa);
        try std.testing.expectEqual(@as(u8, T_BIT_BINARY), enc.items[1]);

        const back = decode(gpa, &ctx, enc.items) catch |err| {
            std.debug.print("LAW FAILED: BIT_BINARY_EXT decode errored (seed=0xB177B17, iter={d}, bit_len={d}): {any}\n", .{ iter, bit_len, err });
            return err;
        };
        if (!FinalTerms.repIsBitstring(&ctx, back)) {
            std.debug.print("LAW FAILED: BIT_BINARY_EXT round-trip lost the bitstring kind (seed=0xB177B17, iter={d}, bit_len={d})\n", .{ iter, bit_len });
            return error.LawViolated;
        }
        const before_bits = FinalTerms.bitstringBits(&ctx, bs);
        const after_bits = FinalTerms.bitstringBits(&ctx, back);
        if (after_bits.bit_len != before_bits.bit_len or
            !std.mem.eql(u8, before_bits.bytes, after_bits.bytes))
        {
            std.debug.print("LAW FAILED: BIT_BINARY_EXT round-trip (seed=0xB177B17, iter={d}, bit_len={d})\n", .{ iter, bit_len });
            return error.LawViolated;
        }
    }
}

test "LAW E3.2 rejection: malformed BIT_BINARY_EXT (bits_in_last_byte 0 or >8, or len 0) is a clean decode error, never a panic" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    // bits_in_last_byte == 0 (a well-formed-looking frame otherwise).
    try std.testing.expectError(error.BadBitBinary, decode(gpa, &ctx, &[_]u8{ 131, T_BIT_BINARY, 0, 0, 0, 1, 0, 0xFF }));
    // bits_in_last_byte == 9 (> 8, out of range).
    try std.testing.expectError(error.BadBitBinary, decode(gpa, &ctx, &[_]u8{ 131, T_BIT_BINARY, 0, 0, 0, 1, 9, 0xFF }));
    // bits_in_last_byte == 255 (way > 8).
    try std.testing.expectError(error.BadBitBinary, decode(gpa, &ctx, &[_]u8{ 131, T_BIT_BINARY, 0, 0, 0, 1, 255, 0xFF }));
    // len == 0 — would underflow `(len-1)*8` if not guarded explicitly.
    try std.testing.expectError(error.BadBitBinary, decode(gpa, &ctx, &[_]u8{ 131, T_BIT_BINARY, 0, 0, 0, 0, 3 }));
    // a WELL-FORMED frame (bits_in_last_byte == 8, a "full last byte"
    // BIT_BINARY_EXT — legal per the wire contract even though this
    // encoder never emits it) decodes cleanly, boundary-exercising the
    // accept side of the same `> 8` check.
    const ok = try decode(gpa, &ctx, &[_]u8{ 131, T_BIT_BINARY, 0, 0, 0, 1, 8, 0xFF });
    try std.testing.expect(FinalTerms.repIsBitstring(&ctx, ok));
    try std.testing.expectEqual(@as(usize, 8), FinalTerms.bitstringBits(&ctx, ok).bit_len);
}

test "MUTANT 1 RED-demo (documented, not executed): bits_in_last_byte = 8 - (bit_len % 8) breaks the round-trip law" {
    // See MUTATION_LOG.md E3.2 mutant 1. Manually verified: with bit_len=11
    // (byte_count=2), the correct `bits_in_last_byte` is 11%8==3; the
    // inverted mutant formula computes 8-3==5, so decode recovers
    // bit_len=(2-1)*8+5==13, not 11 — the seeded round-trip law above
    // (`decode∘encode = id over seeded unaligned bitstrings`) fails on the
    // very first non-fixed-point bit_len it draws (bit_len%8==4 is the lone
    // fixed point of `r -> 8-r` mod 8, since 8-4=4).
}

// ============================================================================
// E3.5: pid / reference / port wire codec
// ============================================================================

test "LAW E18.3sig INBOUND-CONTROL-DECODE ROUND-TRIP: decodeConsumed of enc(A)++enc(B) recovers A with consumed==len(enc(A)), leaving enc(B)" {
    // The DOP PASS_THROUGH inbound decoder relies on decodeConsumed to split a
    // concatenated control+message frame at the exact term boundary. This law
    // proves the split point: for any two terms, decoding the first from the
    // concatenation consumes EXACTLY enc(first).len bytes, so the remainder is
    // byte-identical to enc(second) and decodes to it.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();
    var prng = std.Random.DefaultPrng.init(0x18E3_51_60_DEC0_DE01);
    const r = prng.random();
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const a = try genWireTerm(r, &ctx, 3);
        const b = try genWireTerm(r, &ctx, 3);
        const before_b = try FinalTerms.denote(&ctx, sa, b);
        var ea = try encode(gpa, &ctx, a);
        defer ea.deinit(gpa);
        var eb = try encode(gpa, &ctx, b);
        defer eb.deinit(gpa);
        var cat: std.ArrayList(u8) = .empty;
        defer cat.deinit(gpa);
        try cat.appendSlice(gpa, ea.items);
        try cat.appendSlice(gpa, eb.items);
        const dc = try decodeConsumed(gpa, &ctx, cat.items);
        // consumed == len(enc(first)) — the exact boundary (seed 0x18E3..DE01).
        try std.testing.expectEqual(ea.items.len, dc.consumed);
        // the remainder is byte-identical to enc(second) and decodes to it.
        try std.testing.expectEqualSlices(u8, eb.items, cat.items[dc.consumed..]);
        const back_b = try decode(gpa, &ctx, cat.items[dc.consumed..]);
        try std.testing.expect(spec.eqlExact(before_b, try FinalTerms.denote(&ctx, sa, back_b)));
    }
}

test "LAW E3.5: pid/reference/port round-trip through the wire codec (worked + seeded)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    // worked example, byte-shape pinned: NEW_PID_EXT tag(88), local node
    // atom (T_SMALL_ATOM_UTF8, len 13, "nonode@nohost"), ID=1 u32be,
    // Serial=2 u32be, Creation=0 u32be.
    const p = try FinalTerms.pid(&ctx, 1, 2);
    var enc = try encode(gpa, &ctx, p);
    defer enc.deinit(gpa);
    try std.testing.expectEqual(@as(u8, T_NEW_PID_EXT), enc.items[1]);
    try std.testing.expectEqual(@as(u8, T_SMALL_ATOM_UTF8), enc.items[2]);
    try std.testing.expectEqual(@as(u8, local_node_name.len), enc.items[3]);
    const back_p = try decode(gpa, &ctx, enc.items);
    try std.testing.expect(FinalTerms.repIsPid(&ctx, back_p));
    try std.testing.expectEqual(@as(u64, 1), FinalTerms.pidNumber(&ctx, back_p));
    try std.testing.expectEqual(@as(u64, 2), FinalTerms.pidSerial(&ctx, back_p));

    // port: our canonical encode form is V4_PORT_EXT.
    const pt = try FinalTerms.port(&ctx, 0x1_0000_0002); // > u32 range: exercises the u64 ID path
    var enc_p = try encode(gpa, &ctx, pt);
    defer enc_p.deinit(gpa);
    try std.testing.expectEqual(@as(u8, T_V4_PORT_EXT), enc_p.items[1]);
    const back_pt = try decode(gpa, &ctx, enc_p.items);
    try std.testing.expect(FinalTerms.repIsPort(&ctx, back_pt));
    try std.testing.expectEqual(@as(u64, 0x1_0000_0002), FinalTerms.portNumber(&ctx, back_pt));

    // reference: NEWER_REFERENCE_EXT, Len=3.
    const r = try FinalTerms.ref(&ctx, .{ 0xAABBCCDD, 0x11223344, 0x55667788 });
    var enc_r = try encode(gpa, &ctx, r);
    defer enc_r.deinit(gpa);
    try std.testing.expectEqual(@as(u8, T_NEWER_REFERENCE_EXT), enc_r.items[1]);
    const back_r = try decode(gpa, &ctx, enc_r.items);
    try std.testing.expect(FinalTerms.repIsRef(&ctx, back_r));
    try std.testing.expectEqual([3]u32{ 0xAABBCCDD, 0x11223344, 0x55667788 }, FinalTerms.refWords(&ctx, back_r));

    // seeded round-trip over all three kinds
    const cfg = LawConfig{ .seed = 0xE3E5, .iterations = 100 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();
    for (0..cfg.iterations) |i| {
        var c2 = FinalTerms.Ctx.init(gpa, &atoms);
        defer c2.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();

        const t = switch (random.uintLessThan(u8, 3)) {
            0 => try FinalTerms.pid(&c2, random.int(u32), random.int(u32)),
            1 => try FinalTerms.port(&c2, random.int(u64)),
            else => try FinalTerms.ref(&c2, .{ random.int(u32), random.int(u32), random.int(u32) }),
        };
        const before = try FinalTerms.denote(&c2, sa, t);
        var bytes = try encode(gpa, &c2, t);
        defer bytes.deinit(gpa);
        const back = try decode(gpa, &c2, bytes.items);
        try expectLaw(spec.eqlExact(before, try FinalTerms.denote(&c2, sa, back)), "etf: pid/ref/port round-trip preserves denotation", cfg, i);
    }
}

test "E3.5 REJECTION: a pid number/serial exceeding the NEW_PID_EXT u32 wire field is a clean error.Unsupported, never a silent truncation" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const over_number = try FinalTerms.pid(&ctx, @as(u64, std.math.maxInt(u32)) + 1, 0);
    try std.testing.expectError(error.Unsupported, encode(gpa, &ctx, over_number));
    const over_serial = try FinalTerms.pid(&ctx, 0, @as(u64, std.math.maxInt(u32)) + 1);
    try std.testing.expectError(error.Unsupported, encode(gpa, &ctx, over_serial));
    // boundary: exactly u32 max is accepted (never rejected on the fence-post).
    const at_boundary = try FinalTerms.pid(&ctx, std.math.maxInt(u32), std.math.maxInt(u32));
    var enc = try encode(gpa, &ctx, at_boundary);
    defer enc.deinit(gpa);
    const back = try decode(gpa, &ctx, enc.items);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u32)), FinalTerms.pidNumber(&ctx, back));
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u32)), FinalTerms.pidSerial(&ctx, back));
}

test "LAW E5.7 FOREIGN-NODE ACCEPT + BYTE-EXACT ROUND-TRIP: a foreign pid/port/ref decodes to a first-class term (node observable) and re-encodes byte-identically" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    // The EXACT bytes the OTP oracle produces for a foreign pid — empirically
    // pinned: `term_to_binary(binary_to_term(<<131,88,119,10,"other@host",
    // 100:32,7:32,3:32>>))` == the input (SAME=true), node/1 == other@host.
    var frame: std.ArrayList(u8) = .empty;
    defer frame.deinit(gpa);
    try frame.append(gpa, VERSION_MAGIC);
    try frame.append(gpa, T_NEW_PID_EXT);
    try frame.append(gpa, T_SMALL_ATOM_UTF8);
    try frame.append(gpa, 10);
    try frame.appendSlice(gpa, "other@host");
    try frame.appendSlice(gpa, &[_]u8{ 0, 0, 0, 100 }); // ID = 100
    try frame.appendSlice(gpa, &[_]u8{ 0, 0, 0, 7 }); //   Serial = 7
    try frame.appendSlice(gpa, &[_]u8{ 0, 0, 0, 3 }); //   Creation = 3
    const pid = try decode(gpa, &ctx, frame.items);
    try std.testing.expect(FinalTerms.repIsPid(&ctx, pid)); // is_pid == true
    try std.testing.expectEqualStrings("other@host", FinalTerms.pidNodeName(&ctx, pid)); // node/1
    try std.testing.expectEqual(@as(u64, 100), FinalTerms.pidNumber(&ctx, pid));
    try std.testing.expectEqual(@as(u64, 7), FinalTerms.pidSerial(&ctx, pid));
    try std.testing.expectEqual(@as(u32, 3), FinalTerms.pidCreation(&ctx, pid));
    var re = try encode(gpa, &ctx, pid); // BYTE-EXACT round-trip (== oracle)
    defer re.deinit(gpa);
    try std.testing.expectEqualSlices(u8, frame.items, re.items);

    // NEWER_REFERENCE_EXT + V4_PORT_EXT from the same foreign node, same law.
    var rframe: std.ArrayList(u8) = .empty;
    defer rframe.deinit(gpa);
    try rframe.append(gpa, VERSION_MAGIC);
    try rframe.append(gpa, T_NEWER_REFERENCE_EXT);
    try rframe.appendSlice(gpa, &[_]u8{ 0, 3 }); // Len = 3
    try rframe.append(gpa, T_SMALL_ATOM_UTF8);
    try rframe.append(gpa, 10);
    try rframe.appendSlice(gpa, "other@host");
    try rframe.appendSlice(gpa, &[_]u8{ 0, 0, 0, 9 }); // Creation = 9
    try rframe.appendSlice(gpa, &[_]u8{ 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3 }); // ID[3]
    const rf = try decode(gpa, &ctx, rframe.items);
    try std.testing.expect(FinalTerms.repIsRef(&ctx, rf));
    try std.testing.expectEqualStrings("other@host", FinalTerms.refNodeName(&ctx, rf));
    try std.testing.expectEqual(@as(u32, 9), FinalTerms.refCreation(&ctx, rf));
    var rre = try encode(gpa, &ctx, rf);
    defer rre.deinit(gpa);
    try std.testing.expectEqualSlices(u8, rframe.items, rre.items);

    // The remaining E5 boundary — a NEWER_REFERENCE_EXT with Len != 3 — stays
    // a clean, distinct reject (unchanged by the foreign-node widening).
    var lframe: std.ArrayList(u8) = .empty;
    defer lframe.deinit(gpa);
    try lframe.append(gpa, VERSION_MAGIC);
    try lframe.append(gpa, T_NEWER_REFERENCE_EXT);
    try lframe.appendSlice(gpa, &[_]u8{ 0, 5 }); // Len = 5 (unsupported)
    try lframe.append(gpa, T_SMALL_ATOM_UTF8);
    try lframe.append(gpa, @intCast(local_node_name.len));
    try lframe.appendSlice(gpa, local_node_name);
    try lframe.appendSlice(gpa, &[_]u8{ 0, 0, 0, 0 }); // Creation
    try lframe.appendSlice(gpa, &[_]u8{0} ** 20); // 5 ID words
    try std.testing.expectError(error.UnsupportedRefLen, decode(gpa, &ctx, lframe.items));

    // A non-atom Node field is still a clean reject (never a panic).
    var bframe: std.ArrayList(u8) = .empty;
    defer bframe.deinit(gpa);
    try bframe.append(gpa, VERSION_MAGIC);
    try bframe.append(gpa, T_NEW_PID_EXT);
    try bframe.append(gpa, T_SMALL_INTEGER); // Node = 42 (not an atom)
    try bframe.append(gpa, 42);
    try bframe.appendSlice(gpa, &[_]u8{ 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0 });
    try std.testing.expectError(error.ForeignNode, decode(gpa, &ctx, bframe.items));
}

test "MUTANT 2 RED-demo (documented, planted+run+reverted — see MUTATION_LOG.md E3.5 mutant 2)" {
    // Plant: delete the `_ = try r.u32_();` Creation read in the
    // T_NEWER_REFERENCE_EXT decode arm. RED, as run against "LAW E3.5:
    // pid/reference/port round-trip through the wire codec"'s worked
    // reference case (words {0xAABBCCDD, 0x11223344, 0x55667788}):
    // `expectEqualSlices` reports `[0]: 0` (the wire's Creation word, mis-
    // read as ID word 0) where `2864434397` (0xAABBCCDD) was expected, and
    // every subsequent word shifted one slot early. Reverted; the suite is
    // green again with the Creation read restored above.
}

test "LAW E7.1 EXPORT_EXT: byte-exact vs host term_to_binary(fun lists:map/2); round-trip; truncation rejects" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const m = FinalTerms.atom(&ctx, try atoms.intern("lists"));
    const f = FinalTerms.atom(&ctx, try atoms.intern("map"));
    const ef = try FinalTerms.makeExportFun(&ctx, m, f, 2);

    // Byte-exact against the OTP host: `term_to_binary(fun lists:map/2)` =
    // <<131, 113, 119,5,"lists", 119,3,"map", 97,2>> (empirically captured).
    const expected = [_]u8{
        131, 113,
        119, 5, 'l', 'i', 's', 't', 's',
        119, 3, 'm', 'a', 'p',
        97,  2,
    };
    var enc = try encode(gpa, &ctx, ef);
    defer enc.deinit(gpa);
    try std.testing.expectEqualSlices(u8, &expected, enc.items);

    // round-trip: decode∘encode preserves the denotation (module/function/arity).
    const back = try decode(gpa, &ctx, enc.items);
    try std.testing.expect(FinalTerms.repIsExportFun(&ctx, back));
    try std.testing.expectEqualStrings("lists", FinalTerms.exportFunModuleName(&ctx, back));
    try std.testing.expectEqualStrings("map", FinalTerms.exportFunFuncName(&ctx, back));
    try std.testing.expectEqual(@as(u8, 2), FinalTerms.exportFunArity(&ctx, back));

    // rejection is TOTAL on truncation: every proper prefix of a valid frame
    // is a clean error (Truncated), never a panic or a partial term.
    for (1..enc.items.len) |k| {
        try std.testing.expectError(error.Truncated, decode(gpa, &ctx, enc.items[0..k]));
    }
    // a malformed EXPORT_EXT whose Arity slot is not a small int is BadRecord.
    // <<131,113, atom "a", atom "b", NIL(106)>> — NIL is not a small int.
    const bad = [_]u8{ 131, 113, 119, 1, 'a', 119, 1, 'b', 106 };
    try std.testing.expectError(error.BadRecord, decode(gpa, &ctx, &bad));
}

// ── e21-t7: FUZZ target — malformed external-term surface ──────────────────
// SEMANTIC DOMAIN: `decode` is a partial function `bytes ⇀ Term` whose TOTAL
// obligation is *safety*: every byte string either decodes to a well-formed
// term or returns a named `DecodeError` — it must NEVER crash, over-read, or
// leak, no matter how adversarial the input. LAW (rejection/totality-of-safety):
// ∀ b ∈ bytes . decode(b) ∈ {Ok(t)} ∪ DecodeError, and the arena is balanced.
// This is the coverage-guided realization of that law (`zig build test --fuzz`);
// under the plain gate it replays the seed corpus + the empty smoke input.
// `Smith.slice` consumes a u32-LE length prefix from the fuzz stream, so each
// corpus seed is `fuzzLenPrefix`-wrapped to feed the decoder its EXACT bytes
// (a fixed over-sized buffer would mask length-delimited decoders behind
// spurious padding — the fuzz input length is itself part of the surface).
fn fuzzLenPrefix(comptime raw: []const u8) []const u8 {
    const n: u32 = @intCast(raw.len);
    const pre = [_]u8{
        @intCast(n & 0xFF),        @intCast((n >> 8) & 0xFF),
        @intCast((n >> 16) & 0xFF), @intCast((n >> 24) & 0xFF),
    };
    return pre ++ raw;
}
fn fuzzEtfDecode(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [512]u8 = undefined;
    const n = smith.sliceWithHash(&buf, 0xE1F0_DEC0);
    const input = buf[0..n];
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    // Safety obligation: any error is acceptable, a crash/leak is not.
    const t = decode(gpa, &ctx, input) catch return;
    std.mem.doNotOptimizeAway(t);
}

test "FUZZ e21-t7: ETF decode is safe/total on adversarial bytes (corpus replay under gate)" {
    try std.testing.fuzz({}, fuzzEtfDecode, .{ .corpus = &.{
        fuzzLenPrefix(&[_]u8{ 131, 97, 7 }), // SMALL_INTEGER_EXT
        fuzzLenPrefix(&[_]u8{ 131, 98, 0, 0, 1, 0 }), // INTEGER_EXT
        fuzzLenPrefix(&[_]u8{ 131, 100, 0, 3, 'f', 'o', 'o' }), // ATOM_EXT
        fuzzLenPrefix(&[_]u8{ 131, 104, 2, 97, 1, 97, 2 }), // SMALL_TUPLE
        fuzzLenPrefix(&[_]u8{ 131, 108, 0, 0, 0, 1, 97, 9, 106 }), // LIST
        fuzzLenPrefix(&[_]u8{ 131, 116, 0, 0, 0, 1, 97, 1, 97, 2 }), // MAP_EXT
        fuzzLenPrefix(&[_]u8{ 131, 80, 0, 0, 0, 5, 120, 1, 1, 0 }), // COMPRESSED (malformed)
        fuzzLenPrefix(&[_]u8{ 131, 42 }), // unknown tag
        fuzzLenPrefix(&[_]u8{ 131, 98, 0, 0 }), // truncated
        fuzzLenPrefix(&[_]u8{ 131, 110, 255, 0 }), // oversized bignum prefix
    } });
}
