//! # bifs/checksum — the self-contained checksum/digest BIF family (E3.18)
//!
//! ## Signature
//! Same contract as the other family modules: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over
//! ALREADY-RESOLVED term arguments. Every BIF here flattens its `iodata`
//! argument to a byte slice (`iodataBytes`, reusing `term_algebra.iolistToBinary`
//! — NO second iolist walker) and runs a SELF-CONTAINED algorithm from Zig's
//! std — `std.hash.Adler32`, `std.hash.Crc32` (the zlib/IEEE-802.3 CRC-32), and
//! `std.crypto.hash.Md5` (erts vendors its own `md5.c` — this is NOT
//! libcrypto/LA-7, exactly the DIVERGENCE_LOG entry 13(a) reclassification).
//!
//! ## Semantic domain — the erts `erl_bif_guard.c`/`erl_bif_binary.c` shapes
//!   adler32/1(D)          == zlib adler32(1, D)          (== `Adler32.permute(1,D)`)
//!   adler32/2(Old,D)      == zlib adler32(Old, D)        (== `permute(Old,D)`)
//!   adler32_combine/3(A1,A2,Sz2) == zlib adler32_combine (the RFC-1950 §9 merge)
//!   crc32/1(D)            == zlib crc32(0, D)            (== `Crc32.hash(D)`)
//!   crc32/2(Old,D)        == zlib crc32(Old, D)          (resume: `crc = Old ^ ~0`)
//!   crc32_combine/3(C1,C2,Sz2)   == zlib crc32_combine   (the GF(2) matrix merge)
//!   md5/1(D)              == MD5(D) as a 16-byte binary
//!   md5_init/0            == an OPAQUE context binary (zigvm-internal `Md5` state)
//!   md5_update/2(Ctx,D)   == the context after absorbing D
//!   md5_final/1(Ctx)      == the 16-byte digest
//!
//! ## Laws (see the E3.18 suite below)
//!   - DENOTATION: adler32("Wikipedia") == 0x11E60398; crc32("123456789") ==
//!     0xCBF43926; md5("") == d41d8cd98f00b204e9800998ecf8427e (the pinned
//!     RFC/spec vectors — a value the differential oracle also agrees on).
//!   - STREAMING == ONE-SHOT: `md5_final(md5_update(md5_update(md5_init,A),B))
//!     == md5(A++B)`; `crc32(crc32(0,A),B) == crc32(0,A++B)`; likewise adler32.
//!   - COMBINE == CONCAT: `crc32_combine(crc32(0,A),crc32(0,B),|B|) ==
//!     crc32(0,A++B)`; likewise adler32_combine.
//!   - REJECTION: a non-iodata argument (an atom, a naked integer) → badarg.
//!
//! ## Scope
//! The MD5 context is an OPAQUE zigvm-internal binary (the serialized `Md5`
//! struct) — its exact bytes are NOT the erts context bytes, but every zigvm
//! `md5_init/update/final` round-trips through it consistently and the FINAL
//! digest matches erts (the only observation that escapes). Do not compare the
//! intermediate context binary across VMs — the OTP docs call it opaque.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;
const Md5 = std.crypto.hash.Md5;
const Adler32 = std.hash.Adler32;
const Crc32 = std.hash.Crc32;

const ADLER_BASE: u32 = 65521;

/// Flatten an `iodata` (binary or iolist) argument to an OWNED byte slice the
/// caller must free. A non-iodata term (atom, naked integer, tuple, …) is a
/// clean `badarg`. Duped off the ctx heap so a later `ctx.words` grow (building
/// the result term) can never dangle it — the `binary_to_list_1` gotcha.
fn iodataBytes(m: *Machine, w: Term) BifError![]u8 {
    const k = FinalTerms.kindOf(&m.ctx, w);
    if (k != .cons and k != .nil and k != .binary) return error.Badarg;
    const flat = FinalTerms.iolistToBinary(&m.ctx, w) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Badarg,
    };
    return m.gpa.dupe(u8, FinalTerms.binBytes(&m.ctx, flat)) catch error.OutOfMemory;
}

/// A checksum integer term. `u32` always fits an `i64` small.
fn u32Term(m: *Machine, v: u32) Term {
    return FinalTerms.int(&m.ctx, @intCast(v));
}

/// A checksum argument that must be a `u32`-range non-negative small integer
/// (the previous checksum in the `/2`/combine forms).
fn needU32(w: Term) BifError!u32 {
    if (!FinalTerms.repIsSmall(w)) return error.Badarg;
    const v = FinalTerms.smallValOf(w);
    if (v < 0 or v > 0xFFFFFFFF) return error.Badarg;
    return @intCast(v);
}

fn needSize(w: Term) BifError!u64 {
    if (!FinalTerms.repIsSmall(w)) return error.Badarg;
    const v = FinalTerms.smallValOf(w);
    if (v < 0) return error.Badarg;
    return @intCast(v);
}

// ── adler32 ─────────────────────────────────────────────────────────────────

pub fn adler32_1(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try iodataBytes(m, args[0]);
    defer m.gpa.free(bytes);
    return u32Term(m, Adler32.permute(1, bytes));
}

pub fn adler32_2(m: *Machine, args: []const Term) BifError!Term {
    const old = try needU32(args[0]);
    const bytes = try iodataBytes(m, args[1]);
    defer m.gpa.free(bytes);
    return u32Term(m, Adler32.permute(old, bytes));
}

/// zlib `adler32_combine` (madler/zlib `adler32.c`, RFC-1950 §9): merge the
/// adler of A (`a1`) and of B (`a2`, of length `len2`) into the adler of A++B.
pub fn adler32_combine_3(m: *Machine, args: []const Term) BifError!Term {
    const a1 = try needU32(args[0]);
    const a2 = try needU32(args[1]);
    const len2 = try needSize(args[2]);
    const rem: u64 = len2 % ADLER_BASE;
    var sum1: u64 = a1 & 0xffff;
    var sum2: u64 = (rem * sum1) % ADLER_BASE;
    sum1 += (a2 & 0xffff) + ADLER_BASE - 1;
    sum2 += ((a1 >> 16) & 0xffff) + ((a2 >> 16) & 0xffff) + ADLER_BASE - rem;
    if (sum1 >= ADLER_BASE) sum1 -= ADLER_BASE;
    if (sum1 >= ADLER_BASE) sum1 -= ADLER_BASE;
    if (sum2 >= (@as(u64, ADLER_BASE) << 1)) sum2 -= (@as(u64, ADLER_BASE) << 1);
    if (sum2 >= ADLER_BASE) sum2 -= ADLER_BASE;
    return u32Term(m, @intCast(sum1 | (sum2 << 16)));
}

// ── crc32 (zlib / IEEE-802.3) ────────────────────────────────────────────────

pub fn crc32_1(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try iodataBytes(m, args[0]);
    defer m.gpa.free(bytes);
    return u32Term(m, Crc32.hash(bytes));
}

pub fn crc32_2(m: *Machine, args: []const Term) BifError!Term {
    const old = try needU32(args[0]);
    const bytes = try iodataBytes(m, args[1]);
    defer m.gpa.free(bytes);
    // Resume: the user-visible crc is the FINALIZED value (post-xor 0xFFFFFFFF).
    // Seed the internal running state with `old ^ ~0`, absorb, re-finalize. With
    // old==0 this reduces to `Crc32.init` (0xFFFFFFFF), so crc32(0,D)==hash(D).
    var c = Crc32.init();
    c.crc = old ^ 0xFFFFFFFF;
    c.update(bytes);
    return u32Term(m, c.final());
}

/// zlib `crc32_combine` (madler/zlib `crc32.c`): GF(2) polynomial-matrix merge
/// of crc(A) (`c1`) and crc(B) (`c2`, length `len2`) into crc(A++B).
pub fn crc32_combine_3(m: *Machine, args: []const Term) BifError!Term {
    const c1 = try needU32(args[0]);
    const c2 = try needU32(args[1]);
    const len2 = try needSize(args[2]);
    return u32Term(m, crc32Combine(c1, c2, len2));
}

fn gf2MatrixTimes(mat: *const [32]u32, vecin: u32) u32 {
    var sum: u32 = 0;
    var vec = vecin;
    var i: usize = 0;
    while (vec != 0) : (i += 1) {
        if (vec & 1 != 0) sum ^= mat[i];
        vec >>= 1;
    }
    return sum;
}

fn gf2MatrixSquare(square: *[32]u32, mat: *const [32]u32) void {
    var n: usize = 0;
    while (n < 32) : (n += 1) square[n] = gf2MatrixTimes(mat, mat[n]);
}

fn crc32Combine(crc1: u32, crc2: u32, len2_in: u64) u32 {
    if (len2_in == 0) return crc1;
    var even: [32]u32 = undefined; // even-power-of-two zeros operator
    var odd: [32]u32 = undefined; // odd-power-of-two zeros operator
    // Put operator for one zero bit in odd.
    odd[0] = 0xedb88320; // CRC-32 polynomial, reflected
    var row: u32 = 1;
    var n: usize = 1;
    while (n < 32) : (n += 1) {
        odd[n] = row;
        row <<= 1;
    }
    gf2MatrixSquare(&even, &odd); // even = odd^2 (2 zero bits)
    gf2MatrixSquare(&odd, &even); // odd  = even^2 (4 zero bits)

    var crc1v = crc1;
    var len2 = len2_in;
    while (true) {
        // Apply zeros operator for this bit of len2.
        gf2MatrixSquare(&even, &odd);
        if (len2 & 1 != 0) crc1v = gf2MatrixTimes(&even, crc1v);
        len2 >>= 1;
        if (len2 == 0) break;
        gf2MatrixSquare(&odd, &even);
        if (len2 & 1 != 0) crc1v = gf2MatrixTimes(&odd, crc1v);
        len2 >>= 1;
        if (len2 == 0) break;
    }
    return crc1v ^ crc2;
}

// ── md5 (erts vendors its own md5.c; std.crypto.hash.Md5 here) ────────────────

pub fn md5_1(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try iodataBytes(m, args[0]);
    defer m.gpa.free(bytes);
    var digest: [Md5.digest_length]u8 = undefined;
    Md5.hash(bytes, &digest, .{});
    return FinalTerms.binary(&m.ctx, &digest) catch error.OutOfMemory;
}

/// The opaque MD5 context — the serialized `Md5` struct as a binary. Its exact
/// bytes are zigvm-internal (NOT the erts context bytes); only the FINAL digest
/// is observed cross-VM.
pub fn md5_init_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    var st = Md5.init(.{});
    return FinalTerms.binary(&m.ctx, std.mem.asBytes(&st)) catch error.OutOfMemory;
}

fn ctxOf(m: *Machine, w: Term) BifError!Md5 {
    if (!FinalTerms.repIsBinary(&m.ctx, w)) return error.Badarg;
    const bytes = FinalTerms.binBytes(&m.ctx, w);
    if (bytes.len != @sizeOf(Md5)) return error.Badarg;
    var st: Md5 = undefined;
    @memcpy(std.mem.asBytes(&st), bytes);
    return st;
}

pub fn md5_update_2(m: *Machine, args: []const Term) BifError!Term {
    var st = try ctxOf(m, args[0]);
    const bytes = try iodataBytes(m, args[1]);
    defer m.gpa.free(bytes);
    st.update(bytes);
    return FinalTerms.binary(&m.ctx, std.mem.asBytes(&st)) catch error.OutOfMemory;
}

pub fn md5_final_1(m: *Machine, args: []const Term) BifError!Term {
    var st = try ctxOf(m, args[0]);
    var digest: [Md5.digest_length]u8 = undefined;
    st.final(&digest);
    return FinalTerms.binary(&m.ctx, &digest) catch error.OutOfMemory;
}

// ============================================================================
// Laws
// ============================================================================

const AtomTable = ta.AtomTable;

fn bin(m: *Machine, s: []const u8) !Term {
    return FinalTerms.binary(&m.ctx, s);
}
fn expectU32(m: *Machine, got: BifError!Term, want: u32) !void {
    const t = try got;
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, t, FinalTerms.int(&m.ctx, @intCast(want))));
}

test "LAW E3.18 checksum denotation: adler32/crc32/md5 hit the pinned spec vectors" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // adler32("Wikipedia") == 0x11E60398 (RFC-1950 worked example).
    try expectU32(&m, adler32_1(&m, &.{try bin(&m, "Wikipedia")}), 0x11E60398);
    // crc32("123456789") == 0xCBF43926 (the CRC-32 check value).
    try expectU32(&m, crc32_1(&m, &.{try bin(&m, "123456789")}), 0xCBF43926);
    // md5("") == d41d8cd98f00b204e9800998ecf8427e.
    {
        const d = try md5_1(&m, &.{try bin(&m, "")});
        const db = FinalTerms.binBytes(&m.ctx, d);
        try std.testing.expectEqual(@as(usize, 16), db.len);
        const hex = std.fmt.bytesToHex(db[0..16].*, .lower);
        try std.testing.expectEqualStrings("d41d8cd98f00b204e9800998ecf8427e", &hex);
    }
    // crc32/1 == crc32(0, D) (the resume form with a zero seed).
    try std.testing.expect(FinalTerms.eqlExact(
        &m.ctx,
        try crc32_1(&m, &.{try bin(&m, "123456789")}),
        try crc32_2(&m, &.{ FinalTerms.int(&m.ctx, 0), try bin(&m, "123456789") }),
    ));

    // Rejection: a non-iodata arg is badarg, never a panic.
    try std.testing.expectError(error.Badarg, adler32_1(&m, &.{FinalTerms.int(&m.ctx, 7)}));
    try std.testing.expectError(error.Badarg, crc32_1(&m, &.{FinalTerms.atom(&m.ctx, m.bool_true)}));
}

test "LAW E3.18 checksum streaming == one-shot, and combine == concat (crc32/adler32/md5)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = "the quick brown ";
    const b = "fox jumps over";
    const ab = a ++ b;

    // crc32 streaming: crc32(crc32(0,A),B) == crc32(0,A++B).
    {
        const c_a = try crc32_1(&m, &.{try bin(&m, a)});
        const c_stream = try crc32_2(&m, &.{ c_a, try bin(&m, b) });
        const c_oneshot = try crc32_1(&m, &.{try bin(&m, ab)});
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, c_stream, c_oneshot));
        // crc32_combine(crc32(A), crc32(B), |B|) == crc32(A++B).
        const c_b = try crc32_1(&m, &.{try bin(&m, b)});
        const c_comb = try crc32_combine_3(&m, &.{ c_a, c_b, FinalTerms.int(&m.ctx, @intCast(b.len)) });
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, c_comb, c_oneshot));
    }
    // adler32 streaming + combine.
    {
        const a_a = try adler32_1(&m, &.{try bin(&m, a)});
        const a_stream = try adler32_2(&m, &.{ a_a, try bin(&m, b) });
        const a_oneshot = try adler32_1(&m, &.{try bin(&m, ab)});
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, a_stream, a_oneshot));
        const a_b = try adler32_1(&m, &.{try bin(&m, b)});
        const a_comb = try adler32_combine_3(&m, &.{ a_a, a_b, FinalTerms.int(&m.ctx, @intCast(b.len)) });
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, a_comb, a_oneshot));
    }
    // md5 streaming: final(update(update(init,A),B)) == md5(A++B).
    {
        const c0 = try md5_init_0(&m, &.{});
        const c1 = try md5_update_2(&m, &.{ c0, try bin(&m, a) });
        const c2 = try md5_update_2(&m, &.{ c1, try bin(&m, b) });
        const via_stream = try md5_final_1(&m, &.{c2});
        const via_oneshot = try md5_1(&m, &.{try bin(&m, ab)});
        try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, via_stream), FinalTerms.binBytes(&m.ctx, via_oneshot)));
        // A malformed context (wrong-size binary) is badarg, not a panic.
        try std.testing.expectError(error.Badarg, md5_final_1(&m, &.{try bin(&m, "short")}));
    }

    // Iodata input: an iolist flattens identically to its binary form.
    {
        const iol = try FinalTerms.cons(&m.ctx, try bin(&m, a), try FinalTerms.cons(&m.ctx, try bin(&m, b), FinalTerms.nil(&m.ctx)));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try crc32_1(&m, &.{iol}), try crc32_1(&m, &.{try bin(&m, ab)})));
    }
}

// ── e49-crypto-pure-zig: crypto:hash/2 over std.crypto (NO NIF, NO libcrypto) ──
//
// The crypto app's `crypto:hash(Type, Data)` is a NIF in OTP; here it is a pure
// std.crypto computation — the sha family + md5, each returning the digest as a
// binary, DIFFERENTIAL byte-EQ vs the pinned oracle (crypto:hash). An unknown
// algorithm atom is `badarg` (never a wrong digest — the system_info "never a
// WRONG value" rule).
const Sha1 = std.crypto.hash.Sha1;
const Sha224 = std.crypto.hash.sha2.Sha224;
const Sha256 = std.crypto.hash.sha2.Sha256;
const Sha384 = std.crypto.hash.sha2.Sha384;
const Sha512 = std.crypto.hash.sha2.Sha512;

fn hashInto(comptime Hasher: type, m: *Machine, bytes: []const u8) BifError!Term {
    var digest: [Hasher.digest_length]u8 = undefined;
    Hasher.hash(bytes, &digest, .{});
    return FinalTerms.binary(&m.ctx, &digest) catch error.OutOfMemory;
}

/// `crypto:hash(Type, Data)` — Type ∈ {md5, sha, sha224, sha256, sha384,
/// sha512}; Data is iodata; result is the raw digest binary. Pure std.crypto.
pub fn hash_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const alg = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    const bytes = try iodataBytes(m, args[1]);
    defer m.gpa.free(bytes);
    if (std.mem.eql(u8, alg, "md5")) return hashInto(Md5, m, bytes);
    if (std.mem.eql(u8, alg, "sha")) return hashInto(Sha1, m, bytes);
    if (std.mem.eql(u8, alg, "sha224")) return hashInto(Sha224, m, bytes);
    if (std.mem.eql(u8, alg, "sha256")) return hashInto(Sha256, m, bytes);
    if (std.mem.eql(u8, alg, "sha384")) return hashInto(Sha384, m, bytes);
    if (std.mem.eql(u8, alg, "sha512")) return hashInto(Sha512, m, bytes);
    return error.Badarg; // an unknown algorithm is never a wrong digest
}

test "LAW e49-crypto-pure-zig crypto:hash/2 DIFFERENTIAL: sha/sha224/sha256/sha384/sha512/md5 digests byte-EQ the pinned OTP-30 crypto:hash oracle vectors; unknown algorithm is badarg (never a wrong digest)" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();

    const H = struct {
        fn hex(comptime s: []const u8) [s.len / 2]u8 {
            var out: [s.len / 2]u8 = undefined;
            _ = std.fmt.hexToBytes(&out, s) catch unreachable;
            return out;
        }
        fn run(mm: *ia.Machine, alg: []const u8, data: []const u8, want: []const u8) !void {
            const alg_t = FinalTerms.atom(&mm.ctx, try mm.ctx.atoms.intern(alg));
            const data_t = try FinalTerms.binary(&mm.ctx, data);
            const r = try hash_2(mm, &.{ alg_t, data_t });
            try std.testing.expect(FinalTerms.repIsBinary(&mm.ctx, r));
            try std.testing.expectEqualSlices(u8, want, FinalTerms.binBytes(&mm.ctx, r));
        }
    };

    // every `want` is the EXACT digest the pinned OTP-30 crypto:hash returned.
    try H.run(&m, "sha", "abc", &H.hex("a9993e364706816aba3e25717850c26c9cd0d89d"));
    try H.run(&m, "sha256", "abc", &H.hex("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
    try H.run(&m, "sha512", "", &H.hex("cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"));
    try H.run(&m, "sha224", "abc", &H.hex("23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7"));
    try H.run(&m, "md5", "", &H.hex("d41d8cd98f00b204e9800998ecf8427e")); // matches the module's own md5("") vector

    // an unknown algorithm is badarg — NEVER a wrong digest.
    const bad = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("sha3_256"));
    const d = try FinalTerms.binary(&m.ctx, "x");
    try std.testing.expectError(error.Badarg, hash_2(&m, &.{ bad, d }));
    // a non-atom algorithm is badarg.
    try std.testing.expectError(error.Badarg, hash_2(&m, &.{ d, d }));
}

// ── gap-crypto-pure-zig: HMAC / strong_rand_bytes / AES-CTR over std.crypto ───
//
// Pushes `crypto:` past `hash/2` toward EQ, still 100% pure Zig `std.crypto`
// (NO NIF, NO libcrypto). Three surfaces, each with the "never a WRONG value"
// discipline — an unsupported algorithm is `badarg`, never a fabricated mac /
// keystream:
//
//   crypto:mac(hmac, Sub, Key, Data)      == HMAC-Sub(Key, Data) as a binary
//   crypto:hmac(Sub, Key, Data)           == the same (deprecated OTP spelling)
//   crypto:hmac(Sub, Key, Data, MacLen)   == the mac truncated to MacLen bytes
//   crypto:strong_rand_bytes(N)           == N CSPRNG bytes (nondeterministic)
//   crypto:crypto_one_time(Cipher,K,IV,D,_)== AES-CTR of D (Cipher∈{aes_128_ctr,
//                                             aes_256_ctr}); enc==dec for CTR
//
// Semantic domain / laws:
//   * HMAC is a pure function → DIFFERENTIAL byte-EQ vs fixed RFC 2202 (HMAC-MD5,
//     HMAC-SHA1) and RFC 4231 (HMAC-SHA224/256/384/512) test vectors. An unknown
//     Sub, or a MAC type other than `hmac`, or MacLen > digest, is `badarg`.
//   * AES-CTR is a pure function → DIFFERENTIAL byte-EQ vs NIST SP800-38A F.5.1
//     (CTR-AES128) and F.5.5 (CTR-AES256). Wrong key/IV length is `badarg`; enc
//     and dec are the identical transform (CTR is XOR of a keystream), so
//     round-trip decrypt(encrypt(D))==D is a corollary of the differential.
//   * strong_rand_bytes is the one NON-differential surface (nondeterministic):
//     its laws are (a) exact length N, (b) N=0 → empty binary, (c) it is NEVER a
//     fixed/fabricated buffer (two calls differ w.o.p.; never all-zero for N≥16).
//
const auth_hmac = std.crypto.auth.hmac;
const HmacMd5 = auth_hmac.HmacMd5;
const HmacSha1 = auth_hmac.HmacSha1;
const HmacSha224 = auth_hmac.sha2.HmacSha224;
const HmacSha256 = auth_hmac.sha2.HmacSha256;
const HmacSha384 = auth_hmac.sha2.HmacSha384;
const HmacSha512 = auth_hmac.sha2.HmacSha512;
const Aes128 = std.crypto.core.aes.Aes128;
const Aes256 = std.crypto.core.aes.Aes256;
const aes_modes = std.crypto.core.modes;

/// Compute HMAC-`Hasher`(key, data), optionally truncated to `want_len` bytes,
/// and return it as a binary. `want_len > mac_length` is `badarg` (never a
/// silently-extended/zero-padded mac).
fn hmacInto(comptime Hasher: type, m: *Machine, key: []const u8, data: []const u8, want_len: ?u64) BifError!Term {
    var out: [Hasher.mac_length]u8 = undefined;
    Hasher.create(&out, data, key);
    const n: usize = if (want_len) |wl| blk: {
        if (wl > Hasher.mac_length) return error.Badarg;
        break :blk @intCast(wl);
    } else Hasher.mac_length;
    return FinalTerms.binary(&m.ctx, out[0..n]) catch error.OutOfMemory;
}

/// Dispatch an HMAC sub-type atom name → the concrete hasher. Exhaustive over
/// the supported union; anything else is `badarg` (never a wrong digest).
fn hmacDispatch(m: *Machine, sub: []const u8, key: []const u8, data: []const u8, want_len: ?u64) BifError!Term {
    if (std.mem.eql(u8, sub, "md5")) return hmacInto(HmacMd5, m, key, data, want_len);
    if (std.mem.eql(u8, sub, "sha")) return hmacInto(HmacSha1, m, key, data, want_len);
    if (std.mem.eql(u8, sub, "sha224")) return hmacInto(HmacSha224, m, key, data, want_len);
    if (std.mem.eql(u8, sub, "sha256")) return hmacInto(HmacSha256, m, key, data, want_len);
    if (std.mem.eql(u8, sub, "sha384")) return hmacInto(HmacSha384, m, key, data, want_len);
    if (std.mem.eql(u8, sub, "sha512")) return hmacInto(HmacSha512, m, key, data, want_len);
    return error.Badarg; // an unsupported hash sub-type is never a wrong mac
}

/// Read the sub-type atom name from an argument (must be an atom).
fn atomName(m: *Machine, w: Term) BifError![]const u8 {
    if (!FinalTerms.repIsAtom(w)) return error.Badarg;
    return m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(w));
}

/// `crypto:mac(Type, SubType, Key, Data)` — only `Type == hmac` is supported
/// (cmac/poly1305 stay `badarg`, never a fabricated tag). SubType ∈ the HMAC
/// hash union; Key and Data are iodata; result is the raw mac binary.
pub fn mac_4(m: *Machine, args: []const Term) BifError!Term {
    const mtype = try atomName(m, args[0]);
    if (!std.mem.eql(u8, mtype, "hmac")) return error.Badarg; // only HMAC (no wrong tag)
    const sub = try atomName(m, args[1]);
    const key = try iodataBytes(m, args[2]);
    defer m.gpa.free(key);
    const data = try iodataBytes(m, args[3]);
    defer m.gpa.free(data);
    return hmacDispatch(m, sub, key, data, null);
}

/// `crypto:hmac(SubType, Key, Data)` — the deprecated direct HMAC spelling.
pub fn hmac_3(m: *Machine, args: []const Term) BifError!Term {
    const sub = try atomName(m, args[0]);
    const key = try iodataBytes(m, args[1]);
    defer m.gpa.free(key);
    const data = try iodataBytes(m, args[2]);
    defer m.gpa.free(data);
    return hmacDispatch(m, sub, key, data, null);
}

/// `crypto:hmac(SubType, Key, Data, MacLength)` — mac truncated to MacLength
/// bytes; MacLength > the digest size is `badarg`.
pub fn hmac_4(m: *Machine, args: []const Term) BifError!Term {
    const sub = try atomName(m, args[0]);
    const key = try iodataBytes(m, args[1]);
    defer m.gpa.free(key);
    const data = try iodataBytes(m, args[2]);
    defer m.gpa.free(data);
    const want_len = try needSize(args[3]);
    return hmacDispatch(m, sub, key, data, want_len);
}

/// Fill `buf` with cryptographically-strong random bytes from the OS CSPRNG
/// (Linux `getrandom(2)`). Loops until the whole buffer is filled.
fn osRandomBytes(buf: []u8) void {
    var off: usize = 0;
    while (off < buf.len) {
        const n = std.os.linux.getrandom(buf.ptr + off, buf.len - off, 0);
        // getrandom without GRND_NONBLOCK on a seeded pool never short-returns
        // except on EINTR (n as a syscall error is a huge usize); guard both.
        if (n == 0 or n > buf.len - off) continue;
        off += n;
    }
}

/// `crypto:strong_rand_bytes(N)` — N CSPRNG bytes as a binary. N=0 → empty
/// binary. NONDETERMINISTIC: never differentialled, never a fabricated buffer.
pub fn strong_rand_bytes_1(m: *Machine, args: []const Term) BifError!Term {
    const n = try needSize(args[0]);
    if (n == 0) return FinalTerms.binary(&m.ctx, "") catch error.OutOfMemory;
    const buf = m.gpa.alloc(u8, @intCast(n)) catch return error.OutOfMemory;
    defer m.gpa.free(buf);
    osRandomBytes(buf);
    return FinalTerms.binary(&m.ctx, buf) catch error.OutOfMemory;
}

/// AES-CTR one-shot for a concrete key type. `key` must be exactly the key
/// length, `iv` exactly 16 bytes; otherwise `badarg`. CTR: enc == dec.
fn aesCtr(comptime Aes: type, m: *Machine, key: []const u8, iv: []const u8, data: []const u8) BifError!Term {
    const key_len = Aes.key_bits / 8;
    if (key.len != key_len or iv.len != 16) return error.Badarg;
    const out = m.gpa.alloc(u8, data.len) catch return error.OutOfMemory;
    defer m.gpa.free(out);
    var key_arr: [key_len]u8 = undefined;
    @memcpy(&key_arr, key[0..key_len]);
    var iv_arr: [16]u8 = undefined;
    @memcpy(&iv_arr, iv[0..16]);
    const ctx = Aes.initEnc(key_arr);
    aes_modes.ctr(@TypeOf(ctx), ctx, out, data, iv_arr, .big);
    return FinalTerms.binary(&m.ctx, out) catch error.OutOfMemory;
}

/// `crypto:crypto_one_time(Cipher, Key, IV, Data, FlagOrOpts)` — one-shot
/// symmetric cipher. Only the CTR modes {aes_128_ctr, aes_256_ctr} are byte-
/// total over std.crypto; every other cipher atom is `badarg` (never a wrong
/// ciphertext). For CTR encrypt and decrypt are the identical transform, so the
/// 5th flag argument does not change the output.
pub fn crypto_one_time_5(m: *Machine, args: []const Term) BifError!Term {
    const cipher = try atomName(m, args[0]);
    const key = try iodataBytes(m, args[1]);
    defer m.gpa.free(key);
    const iv = try iodataBytes(m, args[2]);
    defer m.gpa.free(iv);
    const data = try iodataBytes(m, args[3]);
    defer m.gpa.free(data);
    if (std.mem.eql(u8, cipher, "aes_128_ctr")) return aesCtr(Aes128, m, key, iv, data);
    if (std.mem.eql(u8, cipher, "aes_256_ctr")) return aesCtr(Aes256, m, key, iv, data);
    // gap-crypto-aes-gcm-cbc: AES-CBC (block-chained). args[4] = EncFlag (true|false).
    const enc = try boolArg(m, args[4]);
    if (std.mem.eql(u8, cipher, "aes_128_cbc")) return aesCbc(Aes128, m, key, iv, data, enc);
    if (std.mem.eql(u8, cipher, "aes_256_cbc")) return aesCbc(Aes256, m, key, iv, data, enc);
    return error.Badarg; // unsupported cipher is never a wrong ciphertext
}

/// Parse a `true`/`false` atom flag. Any other term → `Badarg`.
fn boolArg(m: *Machine, t: Term) BifError!bool {
    if (!FinalTerms.repIsAtom(t)) return error.Badarg;
    const nm = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(t));
    if (std.mem.eql(u8, nm, "true")) return true;
    if (std.mem.eql(u8, nm, "false")) return false;
    return error.Badarg;
}

/// AES-CBC (NIST SP800-38A §6.2). Block-chained: enc XORs each plaintext block
/// with the prior ciphertext (IV for the first) then AES-encrypts; dec reverses.
/// Data MUST be a non-empty 16-byte multiple (crypto_one_time does no padding) —
/// else `Badarg` (never a wrong/truncated ciphertext).
fn aesCbc(comptime Aes: type, m: *Machine, key: []const u8, iv: []const u8, data: []const u8, encrypt: bool) BifError!Term {
    const key_len = Aes.key_bits / 8;
    if (key.len != key_len or iv.len != 16) return error.Badarg;
    if (data.len == 0 or data.len % 16 != 0) return error.Badarg;
    const out = m.gpa.alloc(u8, data.len) catch return error.OutOfMemory;
    defer m.gpa.free(out);
    var key_arr: [key_len]u8 = undefined;
    @memcpy(&key_arr, key[0..key_len]);
    var prev: [16]u8 = undefined;
    @memcpy(&prev, iv[0..16]);
    var i: usize = 0;
    if (encrypt) {
        const ctx = Aes.initEnc(key_arr);
        while (i < data.len) : (i += 16) {
            var blk: [16]u8 = undefined;
            for (0..16) |j| blk[j] = data[i + j] ^ prev[j];
            ctx.encrypt(out[i..][0..16], &blk);
            @memcpy(&prev, out[i..][0..16]);
        }
    } else {
        const ctx = Aes.initDec(key_arr);
        while (i < data.len) : (i += 16) {
            var src: [16]u8 = undefined;
            @memcpy(&src, data[i..][0..16]);
            var dec: [16]u8 = undefined;
            ctx.decrypt(&dec, &src);
            for (0..16) |j| out[i + j] = dec[j] ^ prev[j];
            @memcpy(&prev, &src);
        }
    }
    return FinalTerms.binary(&m.ctx, out) catch error.OutOfMemory;
}

const Aes128Gcm = std.crypto.aead.aes_gcm.Aes128Gcm;
const Aes256Gcm = std.crypto.aead.aes_gcm.Aes256Gcm;

/// AES-GCM encrypt (crypto_one_time_aead EncFlag=true) → `{Cipher, Tag}`. IV is a
/// 12-byte nonce (the GCM standard); a wrong key/IV length → `Badarg`.
fn aesGcmEnc(comptime Gcm: type, m: *Machine, key: []const u8, iv: []const u8, data: []const u8, aad: []const u8) BifError!Term {
    if (key.len != Gcm.key_length or iv.len != Gcm.nonce_length) return error.Badarg;
    const c = m.gpa.alloc(u8, data.len) catch return error.OutOfMemory;
    defer m.gpa.free(c);
    var tag: [Gcm.tag_length]u8 = undefined;
    var key_arr: [Gcm.key_length]u8 = undefined;
    @memcpy(&key_arr, key[0..Gcm.key_length]);
    var npub: [Gcm.nonce_length]u8 = undefined;
    @memcpy(&npub, iv[0..Gcm.nonce_length]);
    Gcm.encrypt(c, &tag, data, aad, npub, key_arr);
    const cbin = FinalTerms.binary(&m.ctx, c) catch return error.OutOfMemory;
    const tbin = FinalTerms.binary(&m.ctx, &tag) catch return error.OutOfMemory;
    return FinalTerms.tuple(&m.ctx, &.{ cbin, tbin }) catch error.OutOfMemory;
}

/// AES-GCM decrypt (crypto_one_time_aead EncFlag=false) → the plaintext binary, or
/// the atom `error` on authentication FAILURE (the erts contract — never a wrong
/// plaintext on a bad tag).
fn aesGcmDec(comptime Gcm: type, m: *Machine, key: []const u8, iv: []const u8, data: []const u8, aad: []const u8, tag: []const u8) BifError!Term {
    if (key.len != Gcm.key_length or iv.len != Gcm.nonce_length or tag.len != Gcm.tag_length) return error.Badarg;
    const out = m.gpa.alloc(u8, data.len) catch return error.OutOfMemory;
    defer m.gpa.free(out);
    var key_arr: [Gcm.key_length]u8 = undefined;
    @memcpy(&key_arr, key[0..Gcm.key_length]);
    var npub: [Gcm.nonce_length]u8 = undefined;
    @memcpy(&npub, iv[0..Gcm.nonce_length]);
    var tag_arr: [Gcm.tag_length]u8 = undefined;
    @memcpy(&tag_arr, tag[0..Gcm.tag_length]);
    Gcm.decrypt(out, data, tag_arr, aad, npub, key_arr) catch
        return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("error") catch unreachable);
    return FinalTerms.binary(&m.ctx, out) catch error.OutOfMemory;
}

fn gcmDispatch(m: *Machine, cipher: []const u8, key: []const u8, iv: []const u8, data: []const u8, aad: []const u8, tag: ?[]const u8) BifError!Term {
    if (tag) |t| {
        if (std.mem.eql(u8, cipher, "aes_128_gcm")) return aesGcmDec(Aes128Gcm, m, key, iv, data, aad, t);
        if (std.mem.eql(u8, cipher, "aes_256_gcm")) return aesGcmDec(Aes256Gcm, m, key, iv, data, aad, t);
    } else {
        if (std.mem.eql(u8, cipher, "aes_128_gcm")) return aesGcmEnc(Aes128Gcm, m, key, iv, data, aad);
        if (std.mem.eql(u8, cipher, "aes_256_gcm")) return aesGcmEnc(Aes256Gcm, m, key, iv, data, aad);
    }
    return error.Badarg;
}

/// `crypto:crypto_one_time_aead(Cipher, Key, IV, InText, AAD, EncFlag=true)` →
/// `{CipherText, Tag}` (encrypt only; the decrypt form carries the tag, /7).
pub fn crypto_one_time_aead_6(m: *Machine, args: []const Term) BifError!Term {
    const cipher = try atomName(m, args[0]);
    const key = try iodataBytes(m, args[1]);
    defer m.gpa.free(key);
    const iv = try iodataBytes(m, args[2]);
    defer m.gpa.free(iv);
    const data = try iodataBytes(m, args[3]);
    defer m.gpa.free(data);
    const aad = try iodataBytes(m, args[4]);
    defer m.gpa.free(aad);
    if (!try boolArg(m, args[5])) return error.Badarg; // /6 is encrypt-only
    return gcmDispatch(m, cipher, key, iv, data, aad, null);
}

/// `crypto:crypto_one_time_aead(Cipher, Key, IV, InText, AAD, TagOrTagLength, EncFlag)`.
/// EncFlag=true → `{Cipher, Tag}`; EncFlag=false → the plaintext | atom `error`.
pub fn crypto_one_time_aead_7(m: *Machine, args: []const Term) BifError!Term {
    const cipher = try atomName(m, args[0]);
    const key = try iodataBytes(m, args[1]);
    defer m.gpa.free(key);
    const iv = try iodataBytes(m, args[2]);
    defer m.gpa.free(iv);
    const data = try iodataBytes(m, args[3]);
    defer m.gpa.free(data);
    const aad = try iodataBytes(m, args[4]);
    defer m.gpa.free(aad);
    const enc = try boolArg(m, args[6]);
    if (enc) return gcmDispatch(m, cipher, key, iv, data, aad, null); // args[5]=TagLength (16 produced)
    const tag = try iodataBytes(m, args[5]); // args[5] = the Tag to verify
    defer m.gpa.free(tag);
    return gcmDispatch(m, cipher, key, iv, data, aad, tag);
}

fn hexBuf(comptime s: []const u8) [s.len / 2]u8 {
    var out: [s.len / 2]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, s) catch unreachable;
    return out;
}

test "LAW gap-crypto-pure-zig crypto HMAC DIFFERENTIAL: mac(hmac,Sub,K,D)/hmac/3,4 byte-EQ the RFC 2202 & RFC 4231 vectors; unknown sub / non-hmac type / over-long MacLength is badarg (never a wrong mac)" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();

    const H = struct {
        fn mka(mm: *ia.Machine, s: []const u8) Term {
            return FinalTerms.atom(&mm.ctx, mm.ctx.atoms.intern(s) catch unreachable);
        }
        fn mkbin(mm: *ia.Machine, b: []const u8) Term {
            return FinalTerms.binary(&mm.ctx, b) catch unreachable;
        }
        // mac(hmac, Sub, Key, Data) byte-EQ `want`.
        fn mac(mm: *ia.Machine, sub: []const u8, key: []const u8, data: []const u8, want: []const u8) !void {
            const r = try mac_4(mm, &.{ mka(mm, "hmac"), mka(mm, sub), mkbin(mm, key), mkbin(mm, data) });
            try std.testing.expect(FinalTerms.repIsBinary(&mm.ctx, r));
            try std.testing.expectEqualSlices(u8, want, FinalTerms.binBytes(&mm.ctx, r));
        }
    };

    // RFC 2202 §2 test case 1 (HMAC-MD5): key=0x0b×16, data="Hi There".
    try H.mac(&m, "md5", &hexBuf("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), "Hi There", &hexBuf("9294727a3638bb1c13f48ef8158bfc9d"));
    // RFC 2202 §3 test case 1 (HMAC-SHA1): key=0x0b×20, data="Hi There".
    try H.mac(&m, "sha", &hexBuf("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), "Hi There", &hexBuf("b617318655057264e28bc0b6fb378c8ef146be00"));
    // RFC 4231 test case 1 (HMAC-SHA224/256/384/512): key=0x0b×20, data="Hi There".
    const k20 = hexBuf("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b");
    try H.mac(&m, "sha224", &k20, "Hi There", &hexBuf("896fb1128abbdf196832107cd49df33f47b4b1169912ba4f53684b22"));
    try H.mac(&m, "sha256", &k20, "Hi There", &hexBuf("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"));
    try H.mac(&m, "sha384", &k20, "Hi There", &hexBuf("afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59cfaea9ea9076ede7f4af152e8b2fa9cb6"));
    try H.mac(&m, "sha512", &k20, "Hi There", &hexBuf("87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854"));

    // hmac/3 == mac(hmac, …); hmac/4 truncates to MacLength.
    {
        const r3 = try hmac_3(&m, &.{ H.mka(&m, "sha256"), H.mkbin(&m, &k20), H.mkbin(&m, "Hi There") });
        try std.testing.expectEqualSlices(u8, &hexBuf("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"), FinalTerms.binBytes(&m.ctx, r3));
        const r4 = try hmac_4(&m, &.{ H.mka(&m, "sha256"), H.mkbin(&m, &k20), H.mkbin(&m, "Hi There"), FinalTerms.int(&m.ctx, 16) });
        // first 16 bytes of the SHA-256 mac.
        try std.testing.expectEqualSlices(u8, &hexBuf("b0344c61d8db38535ca8afceaf0bf12b"), FinalTerms.binBytes(&m.ctx, r4));
    }

    // rejections — NEVER a wrong mac.
    const anyb = H.mkbin(&m, "x");
    try std.testing.expectError(error.Badarg, mac_4(&m, &.{ H.mka(&m, "cmac"), H.mka(&m, "sha256"), anyb, anyb })); // non-hmac type
    try std.testing.expectError(error.Badarg, mac_4(&m, &.{ H.mka(&m, "hmac"), H.mka(&m, "sha3_256"), anyb, anyb })); // unknown sub
    try std.testing.expectError(error.Badarg, hmac_3(&m, &.{ H.mka(&m, "md4"), anyb, anyb })); // unknown sub
    try std.testing.expectError(error.Badarg, hmac_4(&m, &.{ H.mka(&m, "sha256"), anyb, anyb, FinalTerms.int(&m.ctx, 33) })); // MacLength > digest
    try std.testing.expectError(error.Badarg, mac_4(&m, &.{ anyb, H.mka(&m, "sha256"), anyb, anyb })); // non-atom type
}

test "LAW gap-crypto-pure-zig crypto:crypto_one_time AES-CTR DIFFERENTIAL: aes_128_ctr / aes_256_ctr byte-EQ NIST SP800-38A F.5.1 & F.5.5; enc==dec round-trip; wrong key/IV length + unknown cipher is badarg" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();

    const H = struct {
        fn mka(mm: *ia.Machine, s: []const u8) Term {
            return FinalTerms.atom(&mm.ctx, mm.ctx.atoms.intern(s) catch unreachable);
        }
        fn mkbin(mm: *ia.Machine, b: []const u8) Term {
            return FinalTerms.binary(&mm.ctx, b) catch unreachable;
        }
    };

    // NIST SP800-38A F.5.1 CTR-AES128.Encrypt (4 blocks).
    const key128 = hexBuf("2b7e151628aed2a6abf7158809cf4f3c");
    const iv = hexBuf("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff");
    const plain = hexBuf("6bc1bee22e409f96e93d7e117393172a" ++
        "ae2d8a571e03ac9c9eb76fac45af8e51" ++
        "30c81c46a35ce411e5fbc1191a0a52ef" ++
        "f69f2445df4f9b17ad2b417be66c3710");
    const cipher128 = hexBuf("874d6191b620e3261bef6864990db6ce" ++
        "9806f66b7970fdff8617187bb9fffdff" ++
        "5ae4df3edbd5d35e5b4f09020db03eab" ++
        "1e031dda2fbe03d1792170a0f3009cee");
    {
        const enc = try crypto_one_time_5(&m, &.{ H.mka(&m, "aes_128_ctr"), H.mkbin(&m, &key128), H.mkbin(&m, &iv), H.mkbin(&m, &plain), FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("true")) });
        try std.testing.expectEqualSlices(u8, &cipher128, FinalTerms.binBytes(&m.ctx, enc));
        // CTR enc == dec: feeding the ciphertext back yields the plaintext.
        const dec = try crypto_one_time_5(&m, &.{ H.mka(&m, "aes_128_ctr"), H.mkbin(&m, &key128), H.mkbin(&m, &iv), H.mkbin(&m, &cipher128), FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("false")) });
        try std.testing.expectEqualSlices(u8, &plain, FinalTerms.binBytes(&m.ctx, dec));
    }

    // NIST SP800-38A F.5.5 CTR-AES256.Encrypt (4 blocks, same IV/plaintext).
    const key256 = hexBuf("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4");
    const cipher256 = hexBuf("601ec313775789a5b7a7f504bbf3d228" ++
        "f443e3ca4d62b59aca84e990cacaf5c5" ++
        "2b0930daa23de94ce87017ba2d84988d" ++
        "dfc9c58db67aada613c2dd08457941a6");
    {
        const enc = try crypto_one_time_5(&m, &.{ H.mka(&m, "aes_256_ctr"), H.mkbin(&m, &key256), H.mkbin(&m, &iv), H.mkbin(&m, &plain), H.mka(&m, "true") });
        try std.testing.expectEqualSlices(u8, &cipher256, FinalTerms.binBytes(&m.ctx, enc));
    }

    // rejections — NEVER a wrong ciphertext.
    const anyb = H.mkbin(&m, "0123456789abcdef");
    try std.testing.expectError(error.Badarg, crypto_one_time_5(&m, &.{ H.mka(&m, "aes_128_ctr"), H.mkbin(&m, "shortkey"), H.mkbin(&m, &iv), anyb, H.mka(&m, "true") })); // bad key len
    try std.testing.expectError(error.Badarg, crypto_one_time_5(&m, &.{ H.mka(&m, "aes_128_ctr"), H.mkbin(&m, &key128), H.mkbin(&m, "shortIV"), anyb, H.mka(&m, "true") })); // bad IV len
    try std.testing.expectError(error.Badarg, crypto_one_time_5(&m, &.{ H.mka(&m, "aes_192_gcm"), H.mkbin(&m, &key128), H.mkbin(&m, &iv), anyb, H.mka(&m, "true") })); // unsupported cipher
}

test "LAW gap-crypto-aes-gcm-cbc: AES-CBC byte-EQ NIST SP800-38A F.2.1 (openssl-cross-checked) + AES-GCM byte-EQ the NIST-tested std vector; enc/dec round-trip; GCM bad-tag → error atom; bad key/IV length → badarg" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    const H = struct {
        fn mka(mm: *ia.Machine, s: []const u8) Term {
            return FinalTerms.atom(&mm.ctx, mm.ctx.atoms.intern(s) catch unreachable);
        }
        fn mkbin(mm: *ia.Machine, b: []const u8) Term {
            return FinalTerms.binary(&mm.ctx, b) catch unreachable;
        }
        fn bytes(mm: *ia.Machine, t: Term) []const u8 {
            return FinalTerms.binBytes(&mm.ctx, t);
        }
    };
    const a_true = H.mka(&m, "true");
    const a_false = H.mka(&m, "false");

    // ── AES-128-CBC: NIST SP800-38A F.2.1 (K/IV/PT → CT), cross-checked vs openssl. ──
    const k128 = hexBuf("2b7e151628aed2a6abf7158809cf4f3c");
    const iv16 = hexBuf("000102030405060708090a0b0c0d0e0f");
    // TWO blocks (F.2.1 blocks 1+2) — exercises the IV→ciphertext CHAINING (a 1-block
    // vector can't distinguish CBC from a broken chain).
    const pt = hexBuf("6bc1bee22e409f96e93d7e117393172a" ++ "ae2d8a571e03ac9c9eb76fac45af8e51");
    const ct = hexBuf("7649abac8119b246cee98e9b12e9197d" ++ "5086cb9b507219ee95db113a917678b2");
    const cbc = try crypto_one_time_5(&m, &.{ H.mka(&m, "aes_128_cbc"), H.mkbin(&m, &k128), H.mkbin(&m, &iv16), H.mkbin(&m, &pt), a_true });
    try std.testing.expectEqualSlices(u8, &ct, H.bytes(&m, cbc));
    // CBC decrypt round-trips.
    const cbc_d = try crypto_one_time_5(&m, &.{ H.mka(&m, "aes_128_cbc"), H.mkbin(&m, &k128), H.mkbin(&m, &iv16), H.mkbin(&m, &ct), a_false });
    try std.testing.expectEqualSlices(u8, &pt, H.bytes(&m, cbc_d));
    // non-block-aligned data → badarg (crypto_one_time does no padding).
    try std.testing.expectError(error.Badarg, crypto_one_time_5(&m, &.{ H.mka(&m, "aes_128_cbc"), H.mkbin(&m, &k128), H.mkbin(&m, &iv16), H.mkbin(&m, "not16"), a_true }));

    // ── AES-256-GCM: the NIST-tested std.crypto vector (key=0x69×32, nonce=0x42×12,
    // "Test with message only", no AAD) → {C, Tag}. ──
    const k256 = [_]u8{0x69} ** 32;
    const iv12 = [_]u8{0x42} ** 12;
    const msg = "Test with message only";
    const gc = hexBuf("5ca1642d90009fea33d01f78cf6eefaf01d539472f7c");
    const gt = hexBuf("07cd7fc9103e2f9e9bf2dfaa319caff4");
    const aead = try crypto_one_time_aead_6(&m, &.{ H.mka(&m, "aes_256_gcm"), H.mkbin(&m, &k256), H.mkbin(&m, &iv12), H.mkbin(&m, msg), H.mkbin(&m, ""), a_true });
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, aead) == .tuple and FinalTerms.tupleArity(&m.ctx, aead) == 2);
    try std.testing.expectEqualSlices(u8, &gc, H.bytes(&m, FinalTerms.tupleElem(&m.ctx, aead, 0))); // ciphertext
    try std.testing.expectEqualSlices(u8, &gt, H.bytes(&m, FinalTerms.tupleElem(&m.ctx, aead, 1))); // tag
    // GCM decrypt (/7) round-trips with the tag.
    const dec = try crypto_one_time_aead_7(&m, &.{ H.mka(&m, "aes_256_gcm"), H.mkbin(&m, &k256), H.mkbin(&m, &iv12), H.mkbin(&m, &gc), H.mkbin(&m, ""), H.mkbin(&m, &gt), a_false });
    try std.testing.expectEqualSlices(u8, msg, H.bytes(&m, dec));
    // a WRONG tag → the atom `error` (never a wrong plaintext).
    const badtag = [_]u8{0} ** 16;
    const bad = try crypto_one_time_aead_7(&m, &.{ H.mka(&m, "aes_256_gcm"), H.mkbin(&m, &k256), H.mkbin(&m, &iv12), H.mkbin(&m, &gc), H.mkbin(&m, ""), H.mkbin(&m, &badtag), a_false });
    try std.testing.expect(FinalTerms.repIsAtom(bad) and std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(bad)), "error"));

    // rejections — NEVER a wrong ciphertext/tag.
    try std.testing.expectError(error.Badarg, crypto_one_time_aead_6(&m, &.{ H.mka(&m, "aes_256_gcm"), H.mkbin(&m, "shortkey"), H.mkbin(&m, &iv12), H.mkbin(&m, msg), H.mkbin(&m, ""), a_true })); // bad key
    try std.testing.expectError(error.Badarg, crypto_one_time_aead_6(&m, &.{ H.mka(&m, "aes_256_gcm"), H.mkbin(&m, &k256), H.mkbin(&m, "shortIV"), H.mkbin(&m, msg), H.mkbin(&m, ""), a_true })); // bad IV
    try std.testing.expectError(error.Badarg, crypto_one_time_aead_6(&m, &.{ H.mka(&m, "aes_192_gcm"), H.mkbin(&m, &k256), H.mkbin(&m, &iv12), H.mkbin(&m, msg), H.mkbin(&m, ""), a_true })); // unsupported cipher
}

test "LAW gap-crypto-pure-zig crypto:strong_rand_bytes/1 length + N=0-empty + non-fabrication + distinctness (nondeterministic; never differentialled, never a fixed buffer)" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();

    // LAW (length): strong_rand_bytes(N) is a binary of exactly N bytes, over a
    // seeded spread of sizes.
    const seed_used: u64 = 0xC0FFEE_5EED; // seed echoed on failure
    var prng = std.Random.DefaultPrng.init(seed_used);
    var rng = prng.random();
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        const n: u32 = rng.uintLessThan(u32, 64);
        const r = try strong_rand_bytes_1(&m, &.{FinalTerms.int(&m.ctx, @intCast(n))});
        try std.testing.expect(FinalTerms.repIsBinary(&m.ctx, r));
        std.testing.expectEqual(@as(usize, n), FinalTerms.binBytes(&m.ctx, r).len) catch |e| {
            std.debug.print("strong_rand_bytes length law failed at seed=0x{x} i={d} n={d}\n", .{ seed_used, i, n });
            return e;
        };
    }

    // LAW (N=0 → empty binary).
    {
        const r0 = try strong_rand_bytes_1(&m, &.{FinalTerms.int(&m.ctx, 0)});
        try std.testing.expect(FinalTerms.repIsBinary(&m.ctx, r0));
        try std.testing.expectEqual(@as(usize, 0), FinalTerms.binBytes(&m.ctx, r0).len);
    }

    // LAW (non-fabrication + distinctness): two 32-byte draws are (w.o.p.)
    // different and NOT the all-zero constant — kills a "return a fixed buffer"
    // mutant. P(collision or all-zero) < 2^-200, so this is deterministically
    // safe for a bounded test.
    {
        const r1 = try strong_rand_bytes_1(&m, &.{FinalTerms.int(&m.ctx, 32)});
        const b1 = try gpa.dupe(u8, FinalTerms.binBytes(&m.ctx, r1));
        defer gpa.free(b1);
        const r2 = try strong_rand_bytes_1(&m, &.{FinalTerms.int(&m.ctx, 32)});
        const b2 = FinalTerms.binBytes(&m.ctx, r2);
        try std.testing.expect(!std.mem.eql(u8, b1, b2)); // distinctness
        const zeros = [_]u8{0} ** 32;
        try std.testing.expect(!std.mem.eql(u8, b1, &zeros)); // non-fabrication
        try std.testing.expect(!std.mem.eql(u8, b2, &zeros));
    }

    // rejection: a negative size is badarg.
    try std.testing.expectError(error.Badarg, strong_rand_bytes_1(&m, &.{FinalTerms.int(&m.ctx, -1)}));
}

