//! beam-zig E3.1 / LA-3: the **bitstring** algebra — finite bit-vectors
//! (cf. erts erl_bits.c; the foundation for the E3 bit-syntax opcodes
//! (Task 3-4, still deferred) and ETF `BIT_BINARY_EXT`, which E3.2 landed
//! in `etf.zig` using `concat`/`canonicalize` from this module directly).
//!
//! SIGNATURE (over the carrier `Bits`):
//!   bitSize(b)                     -> usize
//!   bitAt(b, i)                    -> u1                 (MSB-first, i < bitSize(b))
//!   slice(alloc, b, start, len)    -> Bits                (sub-bit-vector)
//!   concat(alloc, a, b)            -> Bits
//!   fromBinary(bytes)              -> Bits                (injection: aligned)
//!   toBinary(b)                    -> ?[]const u8          (partial projection)
//!   eql(a, b)                      -> bool
//!   compare(a, b)                  -> Order                (total order)
//!
//! SEMANTIC DOMAIN: a bitstring denotes a finite sequence of bits
//! b_0 .. b_{n-1}, b_i in {0,1}, numbered MSB-first WITHIN each byte (erts
//! bit-syntax numbering: bit 0 is the most-significant bit of byte 0).
//!
//! ORACLE ENCODING (obviously correct): `OracleBits` — a boolean SLICE, one
//! `bool` per bit. Every op is the direct definition over that slice; there
//! is no packing, no invariant to maintain.
//!
//! FINAL ENCODING (efficient): `Bits { bytes: []const u8, bit_len: usize }`
//! — 8 bits per byte, MSB-first, with a CANONICAL-PADDING INVARIANT: when
//! `bit_len` is not a multiple of 8, the low `8 - bit_len % 8` bits of the
//! LAST byte are always zero. `canonicalize` is the ONE enforcement point
//! (every constructor routes through it); it is what makes plain byte-array
//! equality (and hence hashing) agree with bit-vector equality — two
//! equal-denotation bitstrings, however they were built, are byte-identical.
//!
//! LAWS (this file):
//!   PACKED<->ORACLE HOMOMORPHISM   `OracleBits.slice` and `Bits.slice` agree
//!       bit-for-bit for random (bytes, bit_len) and random (start, len)
//!       — the worked law; seed echoed on failure (`bitstring homomorphism`)
//!   BYTE-ALIGNMENT HOMOMORPHISM    `toBinary(fromBinary(bytes)) == bytes`;
//!       every `bin_algebra`-shaped observation on an aligned `Bits` agrees
//!       with plain byte slicing (byte-aligned bitstring IS a binary)
//!   CANONICAL-PADDING INVARIANT    every constructed `Bits` satisfies
//!       `isCanonical`; `eql` is agnostic to HOW two equal-denotation values
//!       were built (same content, different incoming padding ⇒ still eql)
//!   TOTAL ORDER                    `compare` is reflexive/antisymmetric/
//!       transitive; `eql(a,b) == (compare(a,b) == .eq)`
//!   CONCAT HOMOMORPHISM            `bitAt(concat(a,b), i)` reads `a` for
//!       `i < bitSize(a)` and `b` (offset) beyond — concat is a genuine
//!       sequence append, not a byte-level shortcut
//!
//! SCOPE: this module is the bit-vector algebra ONLY. Term-kind integration
//! (order-family position, hash coherence, GC, print shape) lives in
//! term_algebra.zig / term_hash.zig / diag.zig / gc.zig, per the E3
//! Term-Kind Recipe. E3.2 landed ETF `BIT_BINARY_EXT` (`etf.zig`) and the
//! conversion BIFs `bit_size/1`/`bitstring_to_list/1`/`list_to_bitstring/1`
//! (`bifs/erlang.zig` / `bifs/conv.zig`) on top of this module, unchanged.
//! Bit-syntax `<<...>>` CONSTRUCTION/MATCHING opcodes are still E3 Tasks
//! 3-4 — deferred.

const std = @import("std");

pub const Order = enum { lt, eq, gt };

/// The FINAL encoding: packed bytes + an explicit bit length. Canonical
/// (see module doc) at every point a `Bits` is handed to a caller.
pub const Bits = struct {
    bytes: []const u8,
    bit_len: usize,
};

pub fn byteLen(bit_len: usize) usize {
    return (bit_len + 7) / 8;
}

/// Canonical-padding invariant, checked (used by the law suite and by
/// callers who want to assert a `Bits` they did not build themselves).
pub fn isCanonical(b: Bits) bool {
    if (b.bytes.len != byteLen(b.bit_len)) return false;
    const rem = b.bit_len % 8;
    if (rem == 0) return true;
    const last = b.bytes[b.bytes.len - 1];
    const pad_mask: u8 = (@as(u8, 1) << @intCast(8 - rem)) - 1;
    return (last & pad_mask) == 0;
}

/// Construct a canonical `Bits`, copying `bit_len` bits out of `bytes` into
/// `allocator`-owned storage and masking the last byte's padding to zero —
/// the ONE enforcement point for the canonical-padding invariant.
///
/// MUTANT 2 (canonical-padding invariant dropped): deleting the `if (rem !=
/// 0)` masking block below leaves junk bits in the last byte. Two `Bits`
/// built from the same logical content but different incoming padding would
/// then differ byte-for-byte — killed by the eql/hash coherence law (see
/// term_algebra.zig's bitstring tests): two equal-denotation values with
/// different incoming padding must still be `eql`/equal-hash.
pub fn canonicalize(allocator: std.mem.Allocator, bytes: []const u8, bit_len: usize) !Bits {
    const n = byteLen(bit_len);
    std.debug.assert(bytes.len >= n);
    const out = try allocator.dupe(u8, bytes[0..n]);
    const rem = bit_len % 8;
    if (rem != 0) {
        const keep_mask: u8 = @as(u8, 0xFF) << @intCast(8 - rem); // keep the HIGH `rem` bits
        out[n - 1] &= keep_mask;
    }
    return .{ .bytes = out, .bit_len = bit_len };
}

pub fn bitSize(b: Bits) usize {
    return b.bit_len;
}

pub fn bitAt(b: Bits, i: usize) u1 {
    std.debug.assert(i < b.bit_len);
    const byte = b.bytes[i / 8];
    const shift: u3 = @intCast(7 - (i % 8));
    return @truncate((byte >> shift) & 1);
}
const packedBitAt = bitAt; // unambiguous alias for use inside OracleBits below

fn setBit(bytes: []u8, i: usize, v: u1) void {
    if (v == 1) bytes[i / 8] |= @as(u8, 1) << @intCast(7 - (i % 8));
}

/// `slice(b, start, len)` — the sub-bit-vector `b[start..start+len)`.
///
/// MUTANT 1 (slice rounds `start_bit` down to a byte boundary): replacing
/// `start` below with `(start / 8) * 8` still type-checks and only differs
/// on an UNALIGNED start — killed by the packed<->oracle homomorphism law
/// (the worked law), which generates random unaligned `start`.
pub fn slice(allocator: std.mem.Allocator, b: Bits, start: usize, len: usize) !Bits {
    std.debug.assert(start + len <= b.bit_len);
    const out = try allocator.alloc(u8, byteLen(len));
    @memset(out, 0);
    for (0..len) |i| setBit(out, i, bitAt(b, start + i));
    return .{ .bytes = out, .bit_len = len };
}

pub fn concat(allocator: std.mem.Allocator, a: Bits, b: Bits) !Bits {
    const total = a.bit_len + b.bit_len;
    const out = try allocator.alloc(u8, byteLen(total));
    @memset(out, 0);
    for (0..a.bit_len) |i| setBit(out, i, bitAt(a, i));
    for (0..b.bit_len) |i| setBit(out, a.bit_len + i, bitAt(b, i));
    return .{ .bytes = out, .bit_len = total };
}

/// The injection binary -> bitstring: zero-copy, always aligned, always
/// canonical (a full byte array has no partial last byte to pad).
pub fn fromBinary(bytes: []const u8) Bits {
    return .{ .bytes = bytes, .bit_len = bytes.len * 8 };
}

/// The partial projection bitstring -> binary: defined only when aligned.
pub fn toBinary(b: Bits) ?[]const u8 {
    if (b.bit_len % 8 != 0) return null;
    return b.bytes[0 .. b.bit_len / 8];
}

/// Observational equality: same length, same bit content. Canonical padding
/// (invariant, above) makes this a plain byte-array compare in practice.
pub fn eql(a: Bits, b: Bits) bool {
    if (a.bit_len != b.bit_len) return false;
    return std.mem.eql(u8, a.bytes[0..byteLen(a.bit_len)], b.bytes[0..byteLen(b.bit_len)]);
}

/// Bitwise lexicographic order, shorter-is-smaller-when-a-prefix — the
/// bit-level generalization of erts' byte-lexicographic binary order (so an
/// aligned `Bits` orders identically to plain byte comparison).
pub fn compare(a: Bits, b: Bits) Order {
    const n = @min(a.bit_len, b.bit_len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const ba = bitAt(a, i);
        const bb = bitAt(b, i);
        if (ba != bb) return if (ba < bb) .lt else .gt;
    }
    if (a.bit_len == b.bit_len) return .eq;
    return if (a.bit_len < b.bit_len) .lt else .gt;
}

// ============================================================================
// ORACLE ENCODING — a boolean slice, obviously correct
// ============================================================================

pub const OracleBits = struct {
    vals: []const bool,

    pub fn bitSize(b: OracleBits) usize {
        return b.vals.len;
    }
    pub fn bitAt(b: OracleBits, i: usize) u1 {
        return if (b.vals[i]) 1 else 0;
    }
    pub fn slice(allocator: std.mem.Allocator, b: OracleBits, start: usize, len: usize) !OracleBits {
        return .{ .vals = try allocator.dupe(bool, b.vals[start .. start + len]) };
    }
    pub fn concat(allocator: std.mem.Allocator, a: OracleBits, b: OracleBits) !OracleBits {
        const out = try allocator.alloc(bool, a.vals.len + b.vals.len);
        @memcpy(out[0..a.vals.len], a.vals);
        @memcpy(out[a.vals.len..], b.vals);
        return .{ .vals = out };
    }
    pub fn eql(a: OracleBits, b: OracleBits) bool {
        return std.mem.eql(bool, a.vals, b.vals);
    }

    /// packed -> oracle (the homomorphism's LHS/RHS bridge).
    pub fn fromPacked(allocator: std.mem.Allocator, b: Bits) !OracleBits {
        const out = try allocator.alloc(bool, b.bit_len);
        for (out, 0..) |*v, i| v.* = packedBitAt(b, i) == 1;
        return .{ .vals = out };
    }
    /// oracle -> packed, canonical by construction (routes through
    /// `canonicalize`, but a boolean slice has no padding to begin with).
    pub fn toPacked(allocator: std.mem.Allocator, b: OracleBits) !Bits {
        const bytes = try allocator.alloc(u8, byteLen(b.vals.len));
        @memset(bytes, 0);
        for (b.vals, 0..) |v, i| if (v) setBit(bytes, i, 1);
        return .{ .bytes = bytes, .bit_len = b.vals.len };
    }
};

// ============================================================================
// LAWS
// ============================================================================

const LawCfg = struct { seed: u64, iterations: usize = 200 };

fn randomBits(random: std.Random, buf: []u8) Bits {
    const nbytes = random.uintLessThan(usize, buf.len + 1);
    for (buf[0..nbytes]) |*b| b.* = random.int(u8);
    const bit_len = if (nbytes == 0) 0 else random.uintLessThan(usize, nbytes * 8 + 1);
    // buf holds >= byteLen(bit_len) live bytes; canonicalize on demand below.
    return .{ .bytes = buf[0..nbytes], .bit_len = bit_len };
}

test "bitstring homomorphism: packed slice == oracle bit-vector slice (seeded)" {
    const gpa = std.testing.allocator;
    const cfg = LawCfg{ .seed = 0xB175 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |iter| {
        var buf: [16]u8 = undefined;
        const raw = randomBits(random, &buf);
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const a = arena.allocator();

        const packed_full = try canonicalize(a, raw.bytes, raw.bit_len);
        try std.testing.expect(isCanonical(packed_full));
        const oracle_full = try OracleBits.fromPacked(a, packed_full);

        const start = if (raw.bit_len == 0) 0 else random.uintLessThan(usize, raw.bit_len + 1);
        const len = if (start > raw.bit_len) 0 else random.uintLessThan(usize, raw.bit_len - start + 1);

        const packed_slice = try slice(a, packed_full, start, len);
        const oracle_slice = try OracleBits.slice(a, oracle_full, start, len);

        if (packed_slice.bit_len != oracle_slice.bitSize()) {
            std.debug.print("LAW FAILED: bitstring homomorphism length (seed=0x{x}, iter={d})\n", .{ cfg.seed, iter });
            return error.LawViolated;
        }
        for (0..len) |i| {
            if (bitAt(packed_slice, i) != oracle_slice.bitAt(i)) {
                std.debug.print("LAW FAILED: bitstring homomorphism bit {d} (seed=0x{x}, iter={d})\n", .{ i, cfg.seed, iter });
                return error.LawViolated;
            }
        }

        // toBinary . fromBinary == id, on aligned inputs
        if (raw.bit_len % 8 == 0) {
            const bin = raw.bytes[0 .. raw.bit_len / 8];
            const injected = fromBinary(bin);
            const projected = toBinary(injected) orelse {
                std.debug.print("LAW FAILED: byte-alignment homomorphism (seed=0x{x}, iter={d})\n", .{ cfg.seed, iter });
                return error.LawViolated;
            };
            try std.testing.expectEqualSlices(u8, bin, projected);
        }
    }
}

test "canonical-padding invariant: every constructed Bits is canonical" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xCA40);
    const random = prng.random();

    for (0..200) |_| {
        var buf: [16]u8 = undefined;
        const raw = randomBits(random, &buf);
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const b = try canonicalize(a, raw.bytes, raw.bit_len);
        try std.testing.expect(isCanonical(b));

        // slice/concat outputs are canonical too (built via setBit, never
        // touching padding bits beyond bit_len)
        if (raw.bit_len > 0) {
            const half = raw.bit_len / 2;
            const s = try slice(a, b, half, raw.bit_len - half);
            try std.testing.expect(isCanonical(s));
        }
        const cc = try concat(a, b, b);
        try std.testing.expect(isCanonical(cc));
    }
}

test "eql/order coherence: canonical padding makes eql agnostic to how a value was built" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // same logical content (5 bits: 1,0,1,1,0), different junk in the padding
    const clean = try canonicalize(a, &.{0b1011_0000}, 5);
    const junky = try canonicalize(a, &.{0b1011_0101}, 5); // padding bits set before canonicalize
    try std.testing.expect(eql(clean, junky));
    try std.testing.expect(std.mem.eql(u8, clean.bytes, junky.bytes)); // byte-identical: THE point

    try std.testing.expectEqual(Order.eq, compare(clean, junky));
}

test "total order: reflexive, antisymmetric, transitive over a random mix" {
    var prng = std.Random.DefaultPrng.init(0x07D0);
    const random = prng.random();
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    var vals: [24]Bits = undefined;
    for (&vals) |*v| {
        var buf: [10]u8 = undefined;
        const raw = randomBits(random, &buf);
        v.* = try canonicalize(a, raw.bytes, raw.bit_len);
    }
    for (vals) |x| try std.testing.expectEqual(Order.eq, compare(x, x));
    for (vals) |x| for (vals) |y| {
        const oxy = compare(x, y);
        const oyx = compare(y, x);
        const inv: Order = switch (oxy) {
            .lt => .gt,
            .eq => .eq,
            .gt => .lt,
        };
        try std.testing.expectEqual(inv, oyx);
        try std.testing.expectEqual(eql(x, y), oxy == .eq);
    };
    for (vals) |x| for (vals) |y| for (vals) |z| {
        const le = struct {
            fn f(o: Order) bool {
                return o != .gt;
            }
        }.f;
        if (le(compare(x, y)) and le(compare(y, z)))
            try std.testing.expect(le(compare(x, z)));
    };
}

test "concat homomorphism: bitAt(concat(a,b), i) reads a then b" {
    var prng = std.Random.DefaultPrng.init(0xC047);
    const random = prng.random();
    const gpa = std.testing.allocator;

    for (0..100) |_| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const al = arena.allocator();
        var bufa: [10]u8 = undefined;
        var bufb: [10]u8 = undefined;
        const ra = randomBits(random, &bufa);
        const rb = randomBits(random, &bufb);
        const a = try canonicalize(al, ra.bytes, ra.bit_len);
        const b = try canonicalize(al, rb.bytes, rb.bit_len);
        const c = try concat(al, a, b);
        try std.testing.expectEqual(a.bit_len + b.bit_len, c.bit_len);
        for (0..a.bit_len) |i| try std.testing.expectEqual(bitAt(a, i), bitAt(c, i));
        for (0..b.bit_len) |i| try std.testing.expectEqual(bitAt(b, i), bitAt(c, a.bit_len + i));
    }
}
