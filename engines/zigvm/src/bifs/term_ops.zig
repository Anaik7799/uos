//! # bifs/term_ops — the term-inspection/hash/unique BIF family (E2.12)
//!
//! ## Signature
//! Same contract as every other family module: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over ALREADY-
//! RESOLVED term arguments, computed via EXISTING algebras (`term_hash`'s
//! `FinalTerms.hashTerm`, `term_algebra`'s tuple builder/`setTupleElem`). No
//! new term semantics live here; it never panics on a well-formed call.
//!
//! ## The BIFs, and the algebra each reuses
//!   phash2/1,2       `FinalTerms.hashTerm` (M4/S7 — the SAME word-walking
//!                    hash `term_hash.zig`'s coherence law covers) reduced
//!                    into `[0, Range)` by `%`. Default Range for `/1` is
//!                    `1 bsl 27` (BEAM's own `phash2/1` default). NOT bit-
//!                    for-bit identical to erts' internal hash constants —
//!                    functional equivalence only requires: deterministic,
//!                    in-range, and COHERENT with `=:=` (the M4 law: `T =:=
//!                    T'` implies `hashTerm(T) == hashTerm(T')`, hence
//!                    `phash2(T) == phash2(T')`). See the law suite below.
//!   setelement/3     builds a FRESH tuple (`FinalTerms.tuple` copies its
//!                    `elems` slice into new heap words), then calls the
//!                    E1.5 `setTupleElem` on the COPY — never the source. The
//!                    source tuple is UNCHANGED (the aliasing law; mutant 2
//!                    below is "call `setTupleElem` on the source instead").
//!   append_element/2 tuple + one trailing elem, via the same copy-then-
//!                    build shape as `setelement`.
//!   make_tuple/2,3   `Arity` copies of `InitVal`, with `/3`'s `InitList`
//!                    (a list of `{Index,Value}` pairs, 1-based, LAST
//!                    occurrence of a repeated index wins — BEAM's own
//!                    contract) applied over the default fill.
//!   unique_integer/0,1  a Machine-owned monotonic `i64` counter, NOT a ref
//!                    (erlang:unique_integer/0,1 is genuinely an INTEGER
//!                    BIF). Single-Machine scope: uniqueness holds only
//!                    within one `Machine` (no cross-process/cross-node
//!                    coordination is modeled — matches this repo's
//!                    single-Machine BIF-testing shape everywhere else, e.g.
//!                    `bifs/atomics.zig`'s registry). The counter starts at 1
//!                    and only increases, so it is UNCONDITIONALLY both
//!                    "monotonic" (call order == value order) and "positive"
//!                    (always ≥ 1) — a safe superset of what `[monotonic]`/
//!                    `[positive]` individually require; unknown option atoms
//!                    are rejected with `badarg`.
//!   make_ref/0        (E3.6) `FinalTerms.freshRef` — the E3.5 `Ctx`-owned
//!                    monotone `ref_counter`; freshness (N calls pairwise
//!                    `=/=`) is guaranteed by that SAME counter's law, not a
//!                    second mechanism here.
//!   term_to_iovec/1,2  reuses `bifs/conv.zig`'s `term_to_binary_1/2` (the
//!                    already-law-covered ETF encoder) and wraps the result
//!                    in a singleton list `[Bin]` — a valid iovec by
//!                    definition (a proper list of binaries whose
//!                    concatenation equals the full encoding); this VM does
//!                    not fragment the encoding into multiple chunks.
//!
//! `tuple_size/1`, `size/1`, `map_get/2`, `is_map_key/2` were ALREADY
//! implemented in `bifs/erlang.zig` (E2.4) — no new wiring needed for those;
//! this module does not redeclare them.
//!
//!   phash/2          (E31-T2) the LEGACY (deprecated) hash — a DISTINCT
//!                    algorithm from `phash2`: erts' `make_hash`
//!                    (`erl_term_hashing.c`), its own constant table
//!                    (`FUNNY_NUMBER1..15`) and term walk. Implemented as a
//!                    FAITHFUL port in `term_algebra.zig`'s
//!                    `FinalTerms.phashLegacy` (NOT `hashTerm`), then reduced
//!                    to `[1, Range]` here by `1 + (hash % Range)` (with erts'
//!                    `Range == 2^32` special case → `hash + 1`). BYTE-EQ vs
//!                    pinned OTP-30 is PROVEN for the DATA-TERM fragment (small
//!                    ints, bignums, ASCII atoms, nil, lists, tuples, floats,
//!                    byte-aligned binaries — see LAW E31-T2, oracle values
//!                    cited). Non-data subtags (pid/port/ref/fun/map/…) take a
//!                    COHERENT TOTAL extension (erts' own map-arm shape) so the
//!                    BIF is total + `=:=`-coherent; that fragment is NOT
//!                    byte-EQ and is never claimed to be.
//!
//! ## Laws (see the suite below)
//!   - PHASH2 RANGE: `phash2(T, N)` ∈ `[0, N)` for every `N > 0`; `phash2(T)`
//!     ∈ `[0, 2^27)`.
//!   - PHASH2 COHERENCE (the M4 equal-hash law, reused): `T =:= T'` ⇒
//!     `phash2(T) == phash2(T')`.
//!   - SETELEMENT HOMOMORPHISM: `setelement(I,T,V)` denotes `T` with element
//!     `I` replaced by `V`, all others unchanged.
//!   - SETELEMENT ALIASING: the SOURCE tuple is unchanged after `setelement`
//!     (mutant 2 — mutate the source in place — must fail this law).
//!   - APPEND_ELEMENT: `append_element(T, V)` has arity `tuple_size(T)+1` and
//!     its last element is `V`; all prior elements unchanged.
//!   - MAKE_TUPLE: `make_tuple(N, X) == a tuple of N copies of X`;
//!     `make_tuple(N, X, [{I,V}])` overrides position `I` with `V`.
//!   - UNIQUE_INTEGER: every call returns a value STRICTLY GREATER than the
//!     previous call on the same Machine (uniqueness + monotonicity).
//!   - TERM_TO_IOVEC: `iolist_to_binary(term_to_iovec(T)) ==
//!     term_to_binary(T)` (concatenation round-trip).
//!   - MAKE_REF FRESHNESS (E3.6): N `make_ref/0` calls on one `Machine` are
//!     pairwise `=/=`; each `=:=` itself.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const conv = @import("conv.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

/// BEAM's real max tuple arity (2^24 - 1) — a sanity cap for `make_tuple`'s
/// `Arity` so a hostile/typo'd huge N is a clean `badarg`, never an
/// unbounded allocation attempt.
const max_tuple_arity: i64 = 16_777_215;

// ── phash2 ──────────────────────────────────────────────────────────────────

// gap-phash2-int (DIVERGENCE 737): the erts `make_hash2` INTEGER path, ported
// byte-EQ from erl_term_hashing.c. `phash2/1,2` of a SMALL integer must match erts
// exactly (it's a portable, node-independent hash used for consistent hashing /
// ETS). zigvm's internal `hashTerm` is a DIFFERENT algorithm, so every phash2 value
// diverged. This ports the small-int + ATOM (gap-phash2-atom 744, a top-level atom →
// its erts atom-table hvalue) + NIL (gap-phash2-nil 745, `[]` is a constant leaf) +
// FLOAT (gap-phash2-float 746, a bit-pattern leaf) + BIGNUM (gap-phash2-bignum 747, a 64-bit
// digit walk) + BINARY (gap-phash2-binary 748, byte-aligned erts block_hash) + TUPLES
// (gap-phash2-compound 750, the recursive make_hash2 walk threading UINT32_HASH(arity,HCONST_9)
// + each element IN-COMPOUND) + LISTS (gap-phash2-list 751, the byte-run string-optimization
// packing 4 small bytes -> HCONST_4 + head/tail recursion, the trailing [] hashed as nil) sub-
// algorithms + MAPS (gap-phash2-map 752, `UINT32_HASH(size,HCONST_16)` + order-INDEPENDENT
// hash_xor_pairs + `UINT32_HASH(xor,HCONST_19)`) + BITSTRINGS (gap-phash2-bitstring 753, the
// partial-tail-byte `HCONST_15` path). The full erts `make_hash2` term walk (small/atom/nil/
// float/bignum/binary/tuple/list/map/bitstring) is ported BYTE-FOR-BYTE — every common term is
// byte-EQ vs pinned OTP-30. `phash2Walk` returns false only on fun/ref/pid/port (a rare niche,
// falling back to `hashTerm`, never a wrong hash).
const H2_HCONST: u32 = 0x9e3779b9; // golden ratio (erts HCONST)
const H2_HCONST_10: u32 = 0x2e2ac13a;
const H2_HCONST_11: u32 = 0xcc623af3;

// erts MIX(a,b,c): the 9-step Jenkins mixer (wrapping u32 arithmetic).
inline fn h2mix(a: *u32, b: *u32, c: *u32) void {
    a.* -%= b.*; a.* -%= c.*; a.* ^= (c.* >> 13);
    b.* -%= c.*; b.* -%= a.*; b.* ^= (a.* << 8);
    c.* -%= a.*; c.* -%= b.*; c.* ^= (b.* >> 13);
    a.* -%= b.*; a.* -%= c.*; a.* ^= (c.* >> 12);
    b.* -%= c.*; b.* -%= a.*; b.* ^= (a.* << 16);
    c.* -%= a.*; c.* -%= b.*; c.* ^= (b.* >> 5);
    a.* -%= b.*; a.* -%= c.*; a.* ^= (c.* >> 3);
    b.* -%= c.*; b.* -%= a.*; b.* ^= (a.* << 10);
    c.* -%= a.*; c.* -%= b.*; c.* ^= (b.* >> 15);
}

// erts UINT32_HASH_2(e1, e2, aconst): a = aconst + e1; b = aconst + e2; MIX(a,b,hash).
inline fn h2u32(hash: *u32, e1: u32, e2: u32, aconst: u32) void {
    var a: u32 = aconst +% e1;
    var b: u32 = aconst +% e2;
    h2mix(&a, &b, hash);
}

/// erts `make_hash2` SMALL_DEF path (byte-EQ). `v` is an erts small (|v| < 2^59).
fn ertsHash2Small(v: i64) u32 {
    var hash: u32 = 0;
    // IS_SSMALL28(v): ((Uint)((v >> 27) + 1)) < 2 — fits SIGNED 28 bits.
    const s28: u64 = @bitCast((v >> 27) +% 1);
    if (s28 < 2) {
        // SINT32_HASH(v, HCONST): y = (Sint32)v; if y<0 UINT32_HASH(-y); UINT32_HASH(y).
        const y: i32 = @intCast(v); // v fits 28 bits
        if (y < 0) h2u32(&hash, @bitCast(-y), 0, H2_HCONST);
        h2u32(&hash, @bitCast(y), 0, H2_HCONST);
    } else {
        // NOT_SSMALL28_HASH: con = neg?HCONST_10:HCONST_11; t=|v|; UINT32_HASH_2(lo32,hi32,con).
        const con: u32 = if (v < 0) H2_HCONST_10 else H2_HCONST_11;
        const t: u64 = if (v < 0) @intCast(-v) else @intCast(v);
        h2u32(&hash, @truncate(t), @truncate(t >> 32), con);
    }
    return hash;
}

/// erts `atom_hash` — the value `make_hash2_helper` returns DIRECTLY for a top-level
/// atom (erl_term_hashing.c: "Fast, but the poor hash value should be mixed" →
/// `return atom_tab(atom_val(term))->slot.bucket.hvalue`). It is `hashpjw` (the ELF
/// hash) over the UTF-8 name bytes, with the r16 "latin1 clutch": a 2-byte
/// latin1-range UTF-8 sequence (lead `(b & 0xFE)==0xC2`, cont `(b2 & 0xC0)==0x80`)
/// folds to `(b << 6) | (b2 & 0x3F)` and consumes the continuation before hashing.
/// Byte-EQ vs erts (gap-phash2-atom); phash2 then masks/mods this u32.
fn ertsAtomHash(name: []const u8) u32 {
    var h: u32 = 0;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        var v: u32 = name[i];
        if (i + 1 < name.len and (name[i] & 0xFE) == 0xC2 and (name[i + 1] & 0xC0) == 0x80) {
            v = (@as(u32, name[i]) << 6) | (@as(u32, name[i + 1]) & 0x3F);
            i += 1;
        }
        h = (h << 4) +% v;
        const g: u32 = h & 0xf0000000;
        if (g != 0) {
            h ^= (g >> 24);
            h ^= g;
        }
    }
    return h;
}

const H2_HCONST_2: u32 = 0x3c6ef372; // erts HCONST_2 (2·golden ratio) — the make_hash2 leaf const

/// erts `make_hash2` NIL path: `UINT32_HASH(NIL_DEF, HCONST_2)` from hash=0
/// (erl_term_hashing.c:1524; `NIL_DEF` = 0x02, erl_term.h:1443). `[]` is a CONSTANT
/// term, so — like the atom/small fast-paths — it takes a direct fast-path, byte-EQ
/// (gap-phash2-nil). Raw value 3468870702; `& (2^27-1)` = 113427502.
fn ertsHash2Nil() u32 {
    var hash: u32 = 0;
    h2u32(&hash, 0x02, 0, H2_HCONST_2); // UINT32_HASH(NIL_DEF=0x02, HCONST_2)
    return hash;
}

const H2_HCONST_12: u32 = 0x6a99b4ac; // erts HCONST_12 (12·golden ratio) — the make_hash2 FLOAT const

/// erts `make_hash2` FLOAT_SUBTAG path (byte-EQ, erl_term_hashing.c:1476). A float is a
/// LEAF term (no recursive walk), so it takes a direct fast-path like the small/atom/nil
/// cases. erts normalizes -0.0 → +0.0 ("ensure positive 0.0") then, on a LITTLE-ENDIAN
/// host, `UINT32_HASH_2(fw[1], fw[0], HCONST_12)` where `fw` is the double's two 32-bit
/// words (fw[0]=low, fw[1]=high). Byte-EQ vs erts (gap-phash2-float, the compound-walk
/// residual's first leaf); phash2 then masks/mods this u32.
fn ertsHash2Float(f: f64) u32 {
    // -0.0 and 0.0 must hash identically → positive-zero bit pattern (0).
    const bits: u64 = if (f == 0.0) 0 else @bitCast(f);
    const fw0: u32 = @truncate(bits); // low word
    const fw1: u32 = @truncate(bits >> 32); // high word
    var hash: u32 = 0;
    h2u32(&hash, fw1, fw0, H2_HCONST_12); // little-endian: UINT32_HASH_2(fw[1], fw[0], HCONST_12)
    return hash;
}

/// erts `make_hash2` BIG (bignum) path (byte-EQ, erl_term_hashing.c:1410, the D_EXP==64 arm).
/// A big walks its 64-bit digits least-significant-first: `con` = HCONST_10 (NEGATIVE) or
/// HCONST_11 (POSITIVE), then each digit `t` → `UINT32_HASH_2(t & 0xffffffff, t >> 32, con)`.
/// zigvm stores the magnitude as little-endian u64 limbs (`std.math.big`, `Limb`=u64 on this
/// target) — a direct match for erts' `ErtsDigit` array on a 64-bit build; `BIG_SIZE` is the
/// NORMALIZED digit count (the most-significant digit is non-zero). A big is never 0 (that's a
/// small), so n≥1 and the `while` equals erts' `do…while`. Byte-EQ vs erts (gap-phash2-bignum).
fn ertsHash2Big(limbs: []const u64, positive: bool) u32 {
    const con: u32 = if (positive) H2_HCONST_11 else H2_HCONST_10;
    var n = limbs.len; // strip any trailing (most-significant) zero limbs → erts BIG_SIZE
    while (n > 0 and limbs[n - 1] == 0) n -= 1;
    var hash: u32 = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const t = limbs[i];
        h2u32(&hash, @truncate(t), @truncate(t >> 32), con); // UINT32_HASH_2(low32, high32, con)
    }
    return hash;
}

const H2_HCONST_13: u32 = 0x08d12e65; // erts HCONST_13 (13·golden ratio) — the make_hash2 BINARY const
const H2_HCONST_15: u32 = 0x454021d7; // erts HCONST_15 (15·golden ratio) — the BITSTRING tail-bits

/// erts `block_hash` (erl_term_hashing.c:505) — the Bob-Jenkins block hash over `bytes` seeded
/// with `initval`. Processes 12-byte blocks (a,b,c each += one little-endian u32, then MIX), then
/// a fall-through finalizer over the ≤11 trailing bytes with the byte length folded into `c`.
/// Reuses the make_hash2 MIX (`h2mix`) + HCONST (`H2_HCONST`).
fn ertsBlockHash(bytes: []const u8, initval: u32) u32 {
    var a: u32 = H2_HCONST;
    var b: u32 = H2_HCONST;
    var c: u32 = initval;
    var k: usize = 0;
    while (bytes.len - k >= 12) : (k += 12) {
        a +%= std.mem.readInt(u32, bytes[k..][0..4], .little);
        b +%= std.mem.readInt(u32, bytes[k + 4 ..][0..4], .little);
        c +%= std.mem.readInt(u32, bytes[k + 8 ..][0..4], .little);
        h2mix(&a, &b, &c);
    }
    const rem = bytes.len - k;
    c +%= @as(u32, @truncate(bytes.len)); // full_length, truncated to 32 bits (erts compat)
    // erts switch(len) fall-through: statement N executes iff rem >= N.
    if (rem >= 11) c +%= @as(u32, bytes[k + 10]) << 24;
    if (rem >= 10) c +%= @as(u32, bytes[k + 9]) << 16;
    if (rem >= 9) c +%= @as(u32, bytes[k + 8]) << 8;
    if (rem >= 8) b +%= @as(u32, bytes[k + 7]) << 24;
    if (rem >= 7) b +%= @as(u32, bytes[k + 6]) << 16;
    if (rem >= 6) b +%= @as(u32, bytes[k + 5]) << 8;
    if (rem >= 5) b +%= @as(u32, bytes[k + 4]);
    if (rem >= 4) a +%= @as(u32, bytes[k + 3]) << 24;
    if (rem >= 3) a +%= @as(u32, bytes[k + 2]) << 16;
    if (rem >= 2) a +%= @as(u32, bytes[k + 1]) << 8;
    if (rem >= 1) a +%= @as(u32, bytes[k + 0]);
    h2mix(&a, &b, &c);
    return c;
}

/// erts `make_hash2` HEAP_BITS/SUB_BITS byte-aligned path (byte-EQ, erl_term_hashing.c:1263):
/// `con = HCONST_13 + hash`; an EMPTY binary hashes to `con`, a non-empty one to
/// `block_hash(bytes, con)`. Byte-aligned FULL binaries only — non-byte-aligned or trailing-
/// partial-byte bitstrings stay on `hashTerm` (disclosed residual; `repIsBinary` gates here).
fn ertsHash2Binary(bytes: []const u8, hash_in: u32) u32 {
    const con = H2_HCONST_13 +% hash_in;
    if (bytes.len == 0) return con; // empty binary (bitsize == 0)
    return ertsBlockHash(bytes, con);
}

/// erts `make_hash2` bitstring path for a NON-byte-aligned bitstring (a trailing partial byte,
/// erl_term_hashing.c:1291): `con = HCONST_13 + hash`; `block_hash` over the FULL bytes, then the
/// partial tail adds `UINT32_HASH_2(bitsize, tail_byte >> (8 - bitsize), HCONST_15)`. `bytes` is
/// the bitstring storage (ceil(bit_len/8) bytes; the last holds the partial bits), `bit_len` the
/// total bit count. Completes the make_hash2 walk — no term type falls back to `hashTerm` now.
fn ertsHash2Bitstring(bytes: []const u8, bit_len: usize, hash_in: u32) u32 {
    const con = H2_HCONST_13 +% hash_in;
    const sz = bit_len / 8; // full byte count
    const bitsize = bit_len % 8; // trailing partial bits (0..7)
    if (sz == 0 and bitsize == 0) return con; // empty
    var hash = ertsBlockHash(bytes[0..sz], con);
    if (bitsize > 0) {
        const shift: u5 = @intCast(8 - bitsize);
        h2u32(&hash, @intCast(bitsize), @as(u32, bytes[sz]) >> shift, H2_HCONST_15); // UINT32_HASH_2(bitsize, tail, HCONST_15)
    }
    return hash;
}

const H2_HCONST_3: u32 = 0xdaa66d2b; // erts HCONST_3 (3·golden ratio) — ATOM inside a compound
const H2_HCONST_9: u32 = 0x8ff34781; // erts HCONST_9 (9·golden ratio) — TUPLE arity
const H2_HCONST_4: u32 = 0x78dde6e4; // erts HCONST_4 (4·golden ratio) — LIST byte-run
const H2_HCONST_16: u32 = 0xe3779b90; // erts HCONST_16 (16·golden ratio) — MAP size
const H2_HCONST_19: u32 = 0xbe1e08bb; // erts HCONST_19 (19·golden ratio) — MAP hash_xor_pairs combine

/// erts `make_hash2` recursive walk (gap-phash2-compound, PARTIAL: leaves + TUPLES). Threads
/// the running `hash` through the term exactly as erl_term_hashing.c's make_hash2_helper does
/// IN A COMPOUND — note the atom/nil `hash==0` (top-level) vs `!=0` (compound) distinction
/// (an atom is its bare hvalue at top level but `UINT32_HASH(hvalue, HCONST_3)` inside a
/// term). Returns FALSE on a not-yet-walked type (cons/map/bitstring/fun/ref/pid/port, or an
/// out-of-erts-small-range int) so the caller falls back to `hashTerm` for the WHOLE term —
/// every result stays honest (byte-EQ or hashTerm, never a wrong hybrid).
fn phash2Walk(m: *Machine, t: Term, hash: *u32) bool {
    const ctx = &m.ctx;
    if (FinalTerms.repIsSmall(t)) {
        const v = FinalTerms.smallValOf(t);
        const small_max: i64 = @as(i64, 1) << 59;
        if (v < -small_max or v >= small_max) return false; // erts would treat as a bignum
        const s28: u64 = @bitCast((v >> 27) +% 1);
        if (s28 < 2) {
            const y: i32 = @intCast(v);
            if (y < 0) h2u32(hash, @bitCast(-y), 0, H2_HCONST);
            h2u32(hash, @bitCast(y), 0, H2_HCONST);
        } else {
            const con: u32 = if (v < 0) H2_HCONST_10 else H2_HCONST_11;
            const tt: u64 = if (v < 0) @intCast(-v) else @intCast(v);
            h2u32(hash, @truncate(tt), @truncate(tt >> 32), con);
        }
        return true;
    }
    if (FinalTerms.repIsAtom(t)) {
        const hv = ertsAtomHash(ctx.atoms.nameOf(FinalTerms.atomIdxOf(t)));
        if (hash.* == 0) hash.* = hv else h2u32(hash, hv, 0, H2_HCONST_3);
        return true;
    }
    if (t == FinalTerms.nil_term) {
        h2u32(hash, 0x02, 0, H2_HCONST_2); // UINT32_HASH(NIL_DEF, HCONST_2)
        return true;
    }
    if (FinalTerms.repIsFloat(ctx, t)) {
        const f = FinalTerms.floatValOf(ctx, t);
        const bits: u64 = if (f == 0.0) 0 else @bitCast(f);
        h2u32(hash, @truncate(bits >> 32), @truncate(bits), H2_HCONST_12);
        return true;
    }
    if (FinalTerms.repIsBig(ctx, t)) {
        const bp = FinalTerms.bigParts(ctx, t);
        const con: u32 = if (bp.positive) H2_HCONST_11 else H2_HCONST_10;
        var n = bp.limbs.len;
        while (n > 0 and bp.limbs[n - 1] == 0) n -= 1;
        var i: usize = 0;
        while (i < n) : (i += 1) h2u32(hash, @truncate(bp.limbs[i]), @truncate(bp.limbs[i] >> 32), con);
        return true;
    }
    if (FinalTerms.repIsBinary(ctx, t)) {
        hash.* = ertsHash2Binary(FinalTerms.binBytesOf(ctx, t), hash.*);
        return true;
    }
    if (FinalTerms.repIsBitstring(ctx, t)) {
        // a NON-byte-aligned bitstring (partial tail byte) — block_hash + the HCONST_15 tail.
        const bits = FinalTerms.bitstringBits(ctx, t);
        hash.* = ertsHash2Bitstring(bits.bytes, bits.bit_len, hash.*);
        return true;
    }
    if (FinalTerms.kindOf(ctx, t) == .tuple) {
        const arity = FinalTerms.tupleArity(ctx, t);
        h2u32(hash, @intCast(arity), 0, H2_HCONST_9); // UINT32_HASH(arity, HCONST_9)
        var i: usize = 0;
        while (i < arity) : (i += 1) {
            if (!phash2Walk(m, FinalTerms.tupleElem(ctx, t, i), hash)) return false;
        }
        return true;
    }
    if (FinalTerms.kindOf(ctx, t) == .cons) {
        // gap-phash2-list: the erts make_hash2 LIST walk (erl_term_hashing.c TAG_PRIMARY_LIST).
        // A byte-run STRING-OPTIMIZATION packs leading small bytes (0..255) four-at-a-time into
        // `sh`, hashing UINT32_HASH(sh, HCONST_4); a non-byte head is walked then the spine
        // continues (re-entering the byte-run). SUBTLE: a `[]` reached BY the byte-run is
        // DROPPED (erts' `if (is_list(term))` is false, term abandoned), but a `[]` reached as a
        // cons TAIL is hashed as nil (HCONST_2); an improper (non-nil) tail is always hashed.
        var lt = t;
        while (true) {
            var sh: u32 = 0;
            var c: u32 = 0;
            while (FinalTerms.kindOf(ctx, lt) == .cons) {
                const head = FinalTerms.listHead(ctx, lt);
                if (FinalTerms.repIsSmall(head)) {
                    const hv = FinalTerms.smallValOf(head);
                    if (hv >= 0 and hv <= 255) {
                        sh = (sh << 8) +% @as(u32, @intCast(hv));
                        if (c == 3) {
                            h2u32(hash, sh, 0, H2_HCONST_4);
                            c = 0;
                            sh = 0;
                        } else c += 1;
                        lt = FinalTerms.listTail(ctx, lt);
                        continue;
                    }
                }
                break; // non-byte head
            }
            if (c > 0) h2u32(hash, sh, 0, H2_HCONST_4); // flush the partial byte-run
            if (FinalTerms.kindOf(ctx, lt) == .cons) {
                // non-byte head: walk it, advance, re-enter the byte-run on the tail
                if (!phash2Walk(m, FinalTerms.listHead(ctx, lt), hash)) return false;
                lt = FinalTerms.listTail(ctx, lt);
                continue;
            }
            // terminator: erts' for(;;) re-processes it — a `[]` hashes as nil (HCONST_2), an
            // improper (non-nil) tail as its leaf; NEVER dropped.
            return phash2Walk(m, lt, hash);
        }
    }
    if (FinalTerms.repIsMap(ctx, t)) {
        // gap-phash2-map: erts make_hash2 flatmap/hashmap. `UINT32_HASH(size, HCONST_16)`, then
        // each {k,v} pair is hashed INDEPENDENTLY (from 0 — HASH_MAP_PAIR resets hash) and the
        // pair-hashes XOR'd (deliberately ORDER-INDEPENDENT, so zigvm's iteration order is
        // irrelevant — the flatmap/hashmap distinction collapses), then `UINT32_HASH(xor,
        // HCONST_19)`. Byte-EQ vs erts.
        const size = FinalTerms.mapSize(ctx, t);
        h2u32(hash, @intCast(size), 0, H2_HCONST_16);
        if (size == 0) return true;
        const pk = m.gpa.alloc(Term, size) catch return false;
        defer m.gpa.free(pk);
        const pv = m.gpa.alloc(Term, size) catch return false;
        defer m.gpa.free(pv);
        _ = FinalTerms.mapPairs(ctx, t, pk, pv);
        var xor_acc: u32 = 0;
        var i: usize = 0;
        while (i < size) : (i += 1) {
            var ph: u32 = 0; // per-pair independent hash (erts HASH_MAP_PAIR resets hash to 0)
            if (!phash2Walk(m, pk[i], &ph)) return false;
            if (!phash2Walk(m, pv[i], &ph)) return false;
            xor_acc ^= ph;
        }
        h2u32(hash, xor_acc, 0, H2_HCONST_19);
        return true;
    }
    return false; // bitstring/fun/ref/pid/port — not yet walked
}

fn phash2Impl(m: *Machine, t: Term, range: i64) BifError!Term {
    if (range <= 0) return error.Badarg;
    // gap-phash2-int (DIVERGENCE 737): a SMALL integer within the erts SMALL range
    // (|v| < 2^59 = SMALL_BITS 60) hashes via the byte-EQ erts `make_hash2` small
    // path; every OTHER term (incl. an erts-bignum-ranged int) keeps the internal
    // `hashTerm` (EQUIV residual). phash2/1's default range 2^27 is a power of two,
    // so `h % range == h & (range-1)` (erts masks /1, mods /2) — one expression fits
    // both. The erts hash is a u32, so `% range` stays in [0, range).
    const small_max: i64 = @as(i64, 1) << 59;
    const h: u64 = if (FinalTerms.repIsSmall(t) and FinalTerms.smallValOf(t) >= -small_max and FinalTerms.smallValOf(t) < small_max)
        ertsHash2Small(FinalTerms.smallValOf(t))
    else if (FinalTerms.repIsAtom(t))
        // gap-phash2-atom (DIVERGENCE 744): a top-level atom hashes to its erts
        // atom-table hvalue directly (see ertsAtomHash).
        ertsAtomHash(m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(t)))
    else if (t == FinalTerms.nil_term)
        // gap-phash2-nil (DIVERGENCE 745): [] is a constant term → the erts make_hash2
        // NIL leaf hash.
        ertsHash2Nil()
    else if (FinalTerms.repIsFloat(&m.ctx, t))
        // gap-phash2-float: a float is a LEAF (no recursive walk) → the erts make_hash2
        // FLOAT_SUBTAG hash byte-EQ.
        ertsHash2Float(FinalTerms.floatValOf(&m.ctx, t))
    else if (FinalTerms.repIsBig(&m.ctx, t)) blk: {
        // gap-phash2-bignum: a big walks its own 64-bit digits (no term recursion) → the
        // erts make_hash2 BIG hash byte-EQ.
        const bp = FinalTerms.bigParts(&m.ctx, t);
        break :blk ertsHash2Big(bp.limbs, bp.positive);
    } else if (FinalTerms.repIsBinary(&m.ctx, t))
        // gap-phash2-binary: a byte-aligned binary is a LEAF whose bytes hash via erts
        // block_hash (no term recursion).
        ertsHash2Binary(FinalTerms.binBytesOf(&m.ctx, t), 0)
    else if (FinalTerms.repIsBitstring(&m.ctx, t)) bsblk: {
        // gap-phash2-bitstring: a NON-byte-aligned bitstring (partial tail byte).
        const bits = FinalTerms.bitstringBits(&m.ctx, t);
        break :bsblk ertsHash2Bitstring(bits.bytes, bits.bit_len, 0);
    } else if (FinalTerms.kindOf(&m.ctx, t) == .tuple or FinalTerms.kindOf(&m.ctx, t) == .cons or FinalTerms.kindOf(&m.ctx, t) == .map) blk: {
        // gap-phash2-compound (tuples + lists + maps): recursively walk the term via the erts
        // make_hash2 traversal. If the walk hits a not-yet-ported type (a partial-byte
        // bitstring) it returns false and we fall back to hashTerm for the WHOLE term — never
        // a wrong partial hash.
        var h: u32 = 0;
        break :blk if (phash2Walk(m, t, &h)) h else FinalTerms.hashTerm(&m.ctx, t);
    } else
        FinalTerms.hashTerm(&m.ctx, t);
    const r: u64 = @intCast(range);
    return FinalTerms.intFromI128(&m.ctx, @intCast(h % r)) catch error.OutOfMemory;
}

/// `phash2(Term)` — default range `1 bsl 27` (BEAM's own default).
pub fn phash2_1(m: *Machine, args: []const Term) BifError!Term {
    return phash2Impl(m, args[0], 1 << 27);
}

/// `phash2(Term, Range)` — `Range` must be a positive small integer.
pub fn phash2_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsSmall(args[1])) return error.Badarg;
    return phash2Impl(m, args[0], FinalTerms.smallValOf(args[1]));
}

// ── phash (legacy) ───────────────────────────────────────────────────────────

/// `erlang:phash(Term, Range)` — the LEGACY, deprecated hash (erts `make_hash`,
/// NOT `phash2`/`make_hash2`). Returns an integer in `[1, Range]`.
///
/// erts range contract (bif.c `phash_2`): `Range` special-cases the value
/// `2^32` (→ wrap: `hash + 1`, which yields the integer `2^32` only when the
/// raw hash is `2^32 - 1`); otherwise `Range` must be an integer in
/// `[1, 2^32 - 1]` (`term_to_Uint` succeeds, `((u>>16)>>16) == 0`, `u != 0`) —
/// everything else (0, negative, `>= 2^32` but not the `2^32` special, or a
/// non-integer) is `badarg`. The raw 32-bit hash is `FinalTerms.phashLegacy`.
pub fn phash_2(m: *Machine, args: []const Term) BifError!Term {
    const rt = args[1];
    if (!FinalTerms.repIsSmall(rt)) return error.Badarg; // bignum range → term_to_Uint/>>16>>16 badarg; non-int → badarg
    const rv = FinalTerms.smallValOf(rt);
    const two_p32: i64 = 4294967296;

    const hash: u32 = FinalTerms.phashLegacy(&m.ctx, args[0]);
    if (rv == two_p32) {
        // Range == 2^32 → range=0 branch: final = hash + 1 (an integer; equals
        // 2^32 when hash == 2^32 - 1).
        const final: u64 = @as(u64, hash) + 1;
        return FinalTerms.intFromI128(&m.ctx, @intCast(final)) catch error.OutOfMemory;
    }
    if (rv < 1 or rv > two_p32 - 1) return error.Badarg;
    const range: u32 = @intCast(rv);
    const final: u32 = 1 + (hash % range); // [1, Range]
    return FinalTerms.intFromI128(&m.ctx, final) catch error.OutOfMemory;
}

/// E3.18: `erts_internal:cmp_term(A, B)` — the standard term order as a
/// three-valued small `-1 | 0 | 1` (erts `bif.c` `erts_internal_cmp_term_2`
/// normalizes `CMP_TERM` to exactly that). Reuses `FinalTerms.compare` (arith
/// order) — the SAME comparator every ordered observation already uses.
pub fn cmp_term_2(m: *Machine, args: []const Term) BifError!Term {
    return FinalTerms.int(&m.ctx, switch (FinalTerms.compare(&m.ctx, args[0], args[1])) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    });
}

// ── setelement / append_element / make_tuple ───────────────────────────────

/// `setelement(Index, Tuple, Value)` — COPY, never mutate the source (see
/// module doc comment's aliasing law).
pub fn setelement_3(m: *Machine, args: []const Term) BifError!Term {
    const idx_t = args[0];
    const tup = args[1];
    const val = args[2];
    if (!FinalTerms.repIsSmall(idx_t)) return error.Badarg;
    if (FinalTerms.kindOf(&m.ctx, tup) != .tuple) return error.Badarg;
    const arity = FinalTerms.tupleArity(&m.ctx, tup);
    const i = FinalTerms.smallValOf(idx_t);
    if (i < 1 or i > @as(i64, @intCast(arity))) return error.Badarg;

    const elems = m.gpa.alloc(Term, arity) catch return error.OutOfMemory;
    defer m.gpa.free(elems);
    for (0..arity) |k| elems[k] = FinalTerms.tupleElem(&m.ctx, tup, k);
    const copy = FinalTerms.tuple(&m.ctx, elems) catch return error.OutOfMemory;
    // MUTANT 2 target: calling setTupleElem on `tup` (the source) instead of
    // `copy` would break the aliasing law below.
    FinalTerms.setTupleElem(&m.ctx, copy, @intCast(i - 1), val);
    return copy;
}

/// `append_element(Tuple, Value)` — a new tuple, arity+1, `Value` last.
pub fn append_element_2(m: *Machine, args: []const Term) BifError!Term {
    const tup = args[0];
    const val = args[1];
    if (FinalTerms.kindOf(&m.ctx, tup) != .tuple) return error.Badarg;
    const arity = FinalTerms.tupleArity(&m.ctx, tup);
    const elems = m.gpa.alloc(Term, arity + 1) catch return error.OutOfMemory;
    defer m.gpa.free(elems);
    for (0..arity) |k| elems[k] = FinalTerms.tupleElem(&m.ctx, tup, k);
    elems[arity] = val;
    return FinalTerms.tuple(&m.ctx, elems) catch error.OutOfMemory;
}

/// `make_tuple(Arity, InitValue)` — `Arity` copies of `InitValue`.
pub fn make_tuple_2(m: *Machine, args: []const Term) BifError!Term {
    const n = try tupleArityArg(args[0]);
    const elems = m.gpa.alloc(Term, @intCast(n)) catch return error.OutOfMemory;
    defer m.gpa.free(elems);
    for (elems) |*e| e.* = args[1];
    return FinalTerms.tuple(&m.ctx, elems) catch error.OutOfMemory;
}

fn tupleArityArg(w: Term) BifError!i64 {
    if (!FinalTerms.repIsSmall(w)) return error.Badarg;
    const n = FinalTerms.smallValOf(w);
    if (n < 0 or n > max_tuple_arity) return error.Badarg;
    return n;
}

/// `make_tuple(Arity, InitValue, InitList)` — `InitList` is a proper list of
/// `{Index, Value}` pairs (1-based) overriding the default fill; the LAST
/// occurrence of a repeated `Index` wins (applied in list order).
pub fn make_tuple_3(m: *Machine, args: []const Term) BifError!Term {
    const n = try tupleArityArg(args[0]);
    const elems = m.gpa.alloc(Term, @intCast(n)) catch return error.OutOfMemory;
    defer m.gpa.free(elems);
    for (elems) |*e| e.* = args[1];

    var cur = args[2];
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => break,
            .cons => {
                const pair = FinalTerms.listHead(&m.ctx, cur);
                if (FinalTerms.kindOf(&m.ctx, pair) != .tuple or FinalTerms.tupleArity(&m.ctx, pair) != 2) {
                    return error.Badarg;
                }
                const idx_t = FinalTerms.tupleElem(&m.ctx, pair, 0);
                if (!FinalTerms.repIsSmall(idx_t)) return error.Badarg;
                const i = FinalTerms.smallValOf(idx_t);
                if (i < 1 or i > n) return error.Badarg;
                elems[@intCast(i - 1)] = FinalTerms.tupleElem(&m.ctx, pair, 1);
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg,
        }
    }
    return FinalTerms.tuple(&m.ctx, elems) catch error.OutOfMemory;
}

// ── insert_element / delete_element (E6.6 — dirty-TAGGED pure rows) ──────────
//
// Both are dirty-cpu-test-tagged in erl_dirty_bif.tab (a SCHEDULING hint: on a
// real node they may run on a dirty CPU scheduler under the test build), but
// their SEMANTICS are pure total tuple functions — copy-then-build, exactly the
// `setelement`/`append_element` shape. They flip EQ on reachability with an
// ordinary differential; the dirty tag is orthogonal to `denote` (the
// dirty-migration homomorphism proven in proc.zig). Host-verified index ranges:
// `insert_element` accepts 1..arity+1 (insert BEFORE Index; arity+1 appends),
// `delete_element` accepts 1..arity; anything else is `badarg`.

/// `insert_element(Index, Tuple, Term)` — a NEW tuple of arity+1 with `Term`
/// spliced in BEFORE 1-based `Index` (so `Index == arity+1` appends). COPY,
/// never mutate the source (the `setelement` aliasing discipline).
pub fn insert_element_3(m: *Machine, args: []const Term) BifError!Term {
    const idx_t = args[0];
    const tup = args[1];
    const val = args[2];
    if (!FinalTerms.repIsSmall(idx_t)) return error.Badarg;
    if (FinalTerms.kindOf(&m.ctx, tup) != .tuple) return error.Badarg;
    const arity = FinalTerms.tupleArity(&m.ctx, tup);
    const i = FinalTerms.smallValOf(idx_t);
    if (i < 1 or i > @as(i64, @intCast(arity)) + 1) return error.Badarg;
    const at: usize = @intCast(i - 1);
    const elems = m.gpa.alloc(Term, arity + 1) catch return error.OutOfMemory;
    defer m.gpa.free(elems);
    for (0..at) |k| elems[k] = FinalTerms.tupleElem(&m.ctx, tup, k);
    elems[at] = val;
    for (at..arity) |k| elems[k + 1] = FinalTerms.tupleElem(&m.ctx, tup, k);
    return FinalTerms.tuple(&m.ctx, elems) catch error.OutOfMemory;
}

/// `delete_element(Index, Tuple)` — a NEW tuple of arity-1 with the 1-based
/// `Index` element dropped. `Index` must be 1..arity (a 1-tuple deletes to `{}`).
pub fn delete_element_2(m: *Machine, args: []const Term) BifError!Term {
    const idx_t = args[0];
    const tup = args[1];
    if (!FinalTerms.repIsSmall(idx_t)) return error.Badarg;
    if (FinalTerms.kindOf(&m.ctx, tup) != .tuple) return error.Badarg;
    const arity = FinalTerms.tupleArity(&m.ctx, tup);
    const i = FinalTerms.smallValOf(idx_t);
    if (i < 1 or i > @as(i64, @intCast(arity))) return error.Badarg;
    const drop: usize = @intCast(i - 1);
    const elems = m.gpa.alloc(Term, arity - 1) catch return error.OutOfMemory;
    defer m.gpa.free(elems);
    var w: usize = 0;
    for (0..arity) |k| {
        if (k == drop) continue;
        elems[w] = FinalTerms.tupleElem(&m.ctx, tup, k);
        w += 1;
    }
    return FinalTerms.tuple(&m.ctx, elems) catch error.OutOfMemory;
}

// ── unique_integer ──────────────────────────────────────────────────────────

fn uniqueIntegerImpl(m: *Machine) BifError!Term {
    // The counter is ALWAYS strictly increasing and starts at 1 — see the
    // module doc comment: this already satisfies both `monotonic` and
    // `positive` unconditionally, so the parsed options only gate which
    // ATOMS are accepted, never change the arithmetic (mutant target:
    // hard-coding a constant return breaks the UNIQUE_INTEGER law below).
    m.unique_counter += 1;
    return FinalTerms.intFromI128(&m.ctx, m.unique_counter) catch error.OutOfMemory;
}

pub fn unique_integer_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return uniqueIntegerImpl(m);
}

// ── make_ref (E3.6) ──────────────────────────────────────────────────────────

/// `erlang:make_ref/0` — a FRESH reference via the E3.5 `Ctx`-owned monotone
/// `ref_counter` (`FinalTerms.freshRef`, the SAME freshness generator the
/// term-algebra module's own "E3.5 REF FRESHNESS" law covers — no second
/// counter/generator here). MUTANT 2 (do NOT do this): returning a constant
/// ref (e.g. always `freshRef`'s FIRST call, memoized) breaks the freshness
/// law below the instant a second `make_ref()` is compared.
pub fn make_ref_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.freshRef(&m.ctx) catch error.OutOfMemory;
}

pub fn unique_integer_1(m: *Machine, args: []const Term) BifError!Term {
    var cur = args[0];
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => break,
            .cons => {
                const h = FinalTerms.listHead(&m.ctx, cur);
                if (!FinalTerms.repIsAtom(h)) return error.Badarg;
                const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(h));
                if (!std.mem.eql(u8, name, "monotonic") and !std.mem.eql(u8, name, "positive")) {
                    return error.Badarg;
                }
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg,
        }
    }
    return uniqueIntegerImpl(m);
}

// ── term_to_iovec ────────────────────────────────────────────────────────────

/// `term_to_iovec(Term)` — `[term_to_binary(Term)]`: a valid (if minimal)
/// iovec, since a singleton binary list trivially concatenates to the full
/// encoding.
pub fn term_to_iovec_1(m: *Machine, args: []const Term) BifError!Term {
    const bin = try conv.term_to_binary_1(m, args);
    return FinalTerms.cons(&m.ctx, bin, FinalTerms.nil(&m.ctx)) catch error.OutOfMemory;
}

/// `/2` accepts (and ignores) an options list, matching `term_to_binary/2`.
pub fn term_to_iovec_2(m: *Machine, args: []const Term) BifError!Term {
    const bin = try conv.term_to_binary_2(m, args);
    return FinalTerms.cons(&m.ctx, bin, FinalTerms.nil(&m.ctx)) catch error.OutOfMemory;
}

// ============================================================================
// Laws
// ============================================================================

const AtomTable = ta.AtomTable;

test "LAW gap-phash2-int (DIVERGENCE 737): the erts make_hash2 SMALL path is byte-EQ vs pinned OTP-30 — phash2(V) = ertsHash2Small(V) & (2^27-1) matches OTP golden values across the SINT32 (≤28-bit) + NOT_SSMALL28 (28..60-bit) ranges, and negatives are mixed twice" {
    const mask: u32 = (1 << 27) - 1; // phash2/1 masks to 2^27 (a power of two → == % 2^27)
    // (V, phash2(V)) golden pairs captured from pinned OTP-30 `erlang:phash2/1`:
    try std.testing.expectEqual(@as(u32, 846366), ertsHash2Small(7) & mask); // SINT32 path
    try std.testing.expectEqual(@as(u32, 88723725), ertsHash2Small(0) & mask);
    try std.testing.expectEqual(@as(u32, 2614250), ertsHash2Small(1) & mask);
    try std.testing.expectEqual(@as(u32, 115015680), ertsHash2Small(-5) & mask); // negative → mixed twice
    try std.testing.expectEqual(@as(u32, 112602999), ertsHash2Small(134217727) & mask); // 2^27-1 (last SINT32)
    try std.testing.expectEqual(@as(u32, 12354923), ertsHash2Small(134217728) & mask); // 2^27 (first NOT_SSMALL28)
    try std.testing.expectEqual(@as(u32, 101464513), ertsHash2Small(1000000000) & mask);
    try std.testing.expectEqual(@as(u32, 13893919), ertsHash2Small(1099511627776) & mask); // 2^40
    try std.testing.expectEqual(@as(u32, 67006816), ertsHash2Small(288230376151711743) & mask); // 2^58-1
    try std.testing.expectEqual(@as(u32, 27520264), ertsHash2Small(576460752303423487) & mask); // 2^59-1 (max small)
}

test "LAW gap-phash2-float: the erts make_hash2 FLOAT path is byte-EQ vs pinned OTP-30 — phash2(F) = ertsHash2Float(F) & (2^27-1) is UINT32_HASH_2(fw[1],fw[0],HCONST_12) over the double's little-endian words, and -0.0 normalizes to +0.0 (identical hash)" {
    const mask: u32 = (1 << 27) - 1; // phash2/1 masks to 2^27
    // (F, phash2(F)) golden pairs captured from pinned OTP-30 `erlang:phash2/1`:
    try std.testing.expectEqual(@as(u32, 123862623), ertsHash2Float(2.0) & mask);
    try std.testing.expectEqual(@as(u32, 10380315), ertsHash2Float(1.5) & mask);
    try std.testing.expectEqual(@as(u32, 49234703), ertsHash2Float(-3.5) & mask); // negative float
    try std.testing.expectEqual(@as(u32, 20875736), ertsHash2Float(0.0) & mask);
    try std.testing.expectEqual(@as(u32, 119088650), ertsHash2Float(1.0e300) & mask); // large magnitude
    // -0.0 normalizes to +0.0 (erts "ensure positive 0.0") → identical hash, distinct bits notwithstanding.
    try std.testing.expectEqual(ertsHash2Float(0.0), ertsHash2Float(-0.0));
    try std.testing.expectEqual(@as(u32, 20875736), ertsHash2Float(-0.0) & mask);
}

test "LAW gap-phash2-bignum: the erts make_hash2 BIG path is byte-EQ vs pinned OTP-30 — phash2(V) = ertsHash2Big(limbs, positive) & (2^27-1) walks the little-endian 64-bit digits (UINT32_HASH_2(low32, high32, con)), the SIGN selecting con = HCONST_11 (+) / HCONST_10 (-)" {
    const mask: u32 = (1 << 27) - 1; // phash2/1 masks to 2^27
    const p36: u64 = 1 << 36; // 2^100 = 2^36 << 64 → limbs [0, 2^36]
    // (V, phash2(V)) golden pairs captured from pinned OTP-30 `erlang:phash2/1`:
    try std.testing.expectEqual(@as(u32, 103122609), ertsHash2Big(&[_]u64{ 0, 1 }, true) & mask); // 2^64
    try std.testing.expectEqual(@as(u32, 126219984), ertsHash2Big(&[_]u64{ 0, p36 }, true) & mask); // 2^100
    try std.testing.expectEqual(@as(u32, 124857544), ertsHash2Big(&[_]u64{ 0, p36 }, false) & mask); // -(2^100): SIGN arm
    try std.testing.expectEqual(@as(u32, 89637930), ertsHash2Big(&[_]u64{ 12345, 1 }, true) & mask); // 2^64+12345 (low limb)
    try std.testing.expectEqual(@as(u32, 8264834), ertsHash2Big(&[_]u64{ 0, 0, 1 }, true) & mask); // 2^128 (3 limbs)
    // same magnitude, opposite sign → distinct hash (con = HCONST_11 vs HCONST_10):
    try std.testing.expect((ertsHash2Big(&[_]u64{ 0, p36 }, true) & mask) != (ertsHash2Big(&[_]u64{ 0, p36 }, false) & mask));
}

test "LAW gap-phash2-binary: the erts make_hash2 byte-aligned BINARY path is byte-EQ vs pinned OTP-30 — phash2(B) = ertsHash2Binary(bytes,0) & (2^27-1) is block_hash(bytes, HCONST_13); the EMPTY binary hashes to HCONST_13 masked, and a 100-byte binary exercises the 12-byte MIX block loop" {
    const mask: u32 = (1 << 27) - 1; // phash2/1 masks to 2^27
    // (bytes, phash2) golden pairs captured from pinned OTP-30 `erlang:phash2/1`:
    try std.testing.expectEqual(@as(u32, 13708901), ertsHash2Binary("", 0) & mask); // <<>> empty → HCONST_13 masked
    try std.testing.expectEqual(@as(u32, 98228475), ertsHash2Binary("abc", 0) & mask); // 3 bytes (finalizer only)
    try std.testing.expectEqual(@as(u32, 33550279), ertsHash2Binary("hello world", 0) & mask); // 11 bytes (max finalizer)
    try std.testing.expectEqual(@as(u32, 133103521), ertsHash2Binary(&[_]u8{ 0, 1, 2, 255 }, 0) & mask); // 0x00/0xff bytes
    // 100 bytes = 8 full 12-byte MIX blocks + a 4-byte finalizer (exercises the block loop):
    try std.testing.expectEqual(@as(u32, 131552894), ertsHash2Binary(&([_]u8{'x'} ** 100), 0) & mask);
    // the empty binary is exactly HCONST_13 (13·golden-ratio) masked:
    try std.testing.expectEqual(@as(u32, 0x08d12e65 & ((1 << 27) - 1)), ertsHash2Binary("", 0) & mask);
}

test "LAW gap-phash2-compound (tuples): the erts make_hash2 TUPLE walk is byte-EQ vs pinned OTP-30 — phash2({..}) threads UINT32_HASH(arity, HCONST_9) then each element hashed IN-COMPOUND (atoms via HCONST_3, recursion for nested tuples); a tuple with a not-yet-walked element falls back to hashTerm" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const p2 = struct {
        fn f(mm: *Machine, t: Term) !i64 {
            const r = try phash2Impl(mm, t, 1 << 27); // phash2/1 default range
            return FinalTerms.smallValOf(r);
        }
    }.f;
    // (tuple, phash2) golden pairs captured from pinned OTP-30 `erlang:phash2/1`:
    try std.testing.expectEqual(@as(i64, 87486268), try p2(&m, try FinalTerms.tuple(&m.ctx, &.{}))); // {} empty
    const t123 = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 3) });
    try std.testing.expectEqual(@as(i64, 28734975), try p2(&m, t123)); // {1,2,3}
    const t12 = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) });
    const tnest = try FinalTerms.tuple(&m.ctx, &.{ t12, FinalTerms.int(&m.ctx, 3) });
    try std.testing.expectEqual(@as(i64, 2475619), try p2(&m, tnest)); // {{1,2},3} nested → recursion
    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const tab = try FinalTerms.tuple(&m.ctx, &.{ a, b });
    try std.testing.expectEqual(@as(i64, 101277806), try p2(&m, tab)); // {a,b} → atoms IN-COMPOUND use HCONST_3
}

test "LAW gap-phash2-list: the erts make_hash2 LIST walk is byte-EQ vs pinned OTP-30 — the byte-run string-opt (4 small bytes -> UINT32_HASH(sh, HCONST_4)), head/tail recursion, the trailing [] ALWAYS hashed as nil, and improper tails" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const H = struct {
        fn p2(mm: *Machine, t: Term) !i64 {
            return FinalTerms.smallValOf(try phash2Impl(mm, t, 1 << 27));
        }
        fn listOf(mm: *Machine, vals: []const i64) !Term {
            var acc = FinalTerms.nil(&mm.ctx);
            var i = vals.len;
            while (i > 0) {
                i -= 1;
                acc = try FinalTerms.cons(&mm.ctx, FinalTerms.int(&mm.ctx, vals[i]), acc);
            }
            return acc;
        }
    };
    // (list, phash2) golden pairs from pinned OTP-30 `erlang:phash2/1`:
    try std.testing.expectEqual(@as(i64, 25788620), try H.p2(&m, try H.listOf(&m, &.{ 1, 2, 3 }))); // byte-run of 3
    try std.testing.expectEqual(@as(i64, 66056394), try H.p2(&m, try H.listOf(&m, &.{ 1, 2, 3, 4, 5 }))); // flush + partial
    try std.testing.expectEqual(@as(i64, 23539029), try H.p2(&m, try H.listOf(&m, &.{ 1, 2, 3, 4, 5, 6, 7, 8 }))); // two flushes
    try std.testing.expectEqual(@as(i64, 81920127), try H.p2(&m, try H.listOf(&m, &.{ 104, 101, 108, 108, 111 }))); // "hello"
    // improper list [1|2] → the tail 2 is hashed as a leaf, not nil:
    try std.testing.expectEqual(@as(i64, 86124794), try H.p2(&m, try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2))));
    // nested [[1,2],3] → recursion into the sublist:
    const l12 = try H.listOf(&m, &.{ 1, 2 });
    const nest = try FinalTerms.cons(&m.ctx, l12, try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 3), FinalTerms.nil(&m.ctx)));
    try std.testing.expectEqual(@as(i64, 67352312), try H.p2(&m, nest));
    // [a,b] non-byte list → head/tail recursion + trailing nil (HCONST_2):
    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const ab = try FinalTerms.cons(&m.ctx, a, try FinalTerms.cons(&m.ctx, b, FinalTerms.nil(&m.ctx)));
    try std.testing.expectEqual(@as(i64, 9075654), try H.p2(&m, ab));
}

test "LAW gap-phash2-map: the erts make_hash2 MAP walk is byte-EQ vs pinned OTP-30 — UINT32_HASH(size, HCONST_16), each {k,v} pair hashed INDEPENDENTLY (from 0) and XOR'd (ORDER-INDEPENDENT), then UINT32_HASH(xor, HCONST_19)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const p2 = struct {
        fn f(mm: *Machine, t: Term) !i64 {
            return FinalTerms.smallValOf(try phash2Impl(mm, t, 1 << 27));
        }
    }.f;
    const I = FinalTerms.int;
    // (map, phash2) golden pairs from pinned OTP-30 `erlang:phash2/1`:
    try std.testing.expectEqual(@as(i64, 39679005), try p2(&m, try FinalTerms.mapNew(&m.ctx, &.{}, &.{}))); // #{} empty
    try std.testing.expectEqual(@as(i64, 40530709), try p2(&m, try FinalTerms.mapNew(&m.ctx, &.{I(&m.ctx, 1)}, &.{I(&m.ctx, 2)}))); // #{1=>2}
    const m12_34 = try FinalTerms.mapNew(&m.ctx, &.{ I(&m.ctx, 1), I(&m.ctx, 3) }, &.{ I(&m.ctx, 2), I(&m.ctx, 4) });
    try std.testing.expectEqual(@as(i64, 101230890), try p2(&m, m12_34)); // #{1=>2, 3=>4}
    // ORDER-INDEPENDENCE: the reversed-insertion map must hash IDENTICALLY (the xor_pairs point):
    const m34_12 = try FinalTerms.mapNew(&m.ctx, &.{ I(&m.ctx, 3), I(&m.ctx, 1) }, &.{ I(&m.ctx, 4), I(&m.ctx, 2) });
    try std.testing.expectEqual(@as(i64, 101230890), try p2(&m, m34_12));
    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    try std.testing.expectEqual(@as(i64, 15730249), try p2(&m, try FinalTerms.mapNew(&m.ctx, &.{a}, &.{I(&m.ctx, 99)}))); // #{a=>99}
}

test "LAW gap-phash2-bitstring: the erts make_hash2 NON-byte-aligned bitstring path is byte-EQ vs pinned OTP-30 — block_hash(full bytes) then UINT32_HASH_2(bitsize, tail_byte >> (8-bitsize), HCONST_15); the partial byte is MSB-first" {
    const mask: u32 = (1 << 27) - 1; // phash2/1 masks to 2^27
    // (bitstring, phash2) golden pairs from pinned OTP-30; the partial byte holds its bits at the TOP:
    try std.testing.expectEqual(@as(u32, 102233125), ertsHash2Bitstring(&[_]u8{0x80}, 1, 0) & mask); // <<1:1>>
    try std.testing.expectEqual(@as(u32, 77228721), ertsHash2Bitstring(&[_]u8{0xC0}, 2, 0) & mask); // <<3:2>>
    try std.testing.expectEqual(@as(u32, 29192568), ertsHash2Bitstring(&[_]u8{ 255, 0xC0 }, 10, 0) & mask); // <<255,3:2>> (1 byte + 2 bits)
    try std.testing.expectEqual(@as(u32, 82827821), ertsHash2Bitstring(&[_]u8{ 97, 98, 0xA0 }, 19, 0) & mask); // <<"ab",5:3>> (2 bytes + 3 bits)
}

test "LAW gap-phash2-atom (DIVERGENCE): the erts make_hash2 ATOM path is byte-EQ vs pinned OTP-30 — phash2(A) = ertsAtomHash(name) & (2^27-1) is hashpjw/ELF over the name bytes, incl. the g-branch high-bit fold, and the empty atom hashes to 0" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const mask: u32 = (1 << 27) - 1; // phash2/1 masks to 2^27

    // (1) the pure helper is byte-EQ vs pinned OTP-30 `erlang:phash2/1` golden values.
    // "world"/"undefined"/"error"/"false"/"Bar" exercise the g-branch (h & 0xf0000000 != 0).
    try std.testing.expectEqual(@as(u32, 7258927), ertsAtomHash("hello") & mask);
    try std.testing.expectEqual(@as(u32, 8284452), ertsAtomHash("world") & mask);
    try std.testing.expectEqual(@as(u32, 1883), ertsAtomHash("ok") & mask);
    try std.testing.expectEqual(@as(u32, 7117154), ertsAtomHash("error") & mask);
    try std.testing.expectEqual(@as(u32, 45914356), ertsAtomHash("undefined") & mask);
    try std.testing.expectEqual(@as(u32, 7111573), ertsAtomHash("false") & mask);
    try std.testing.expectEqual(@as(u32, 506293), ertsAtomHash("true") & mask);
    try std.testing.expectEqual(@as(u32, 27999), ertsAtomHash("foo") & mask);
    try std.testing.expectEqual(@as(u32, 18562), ertsAtomHash("Bar") & mask);
    try std.testing.expectEqual(@as(u32, 0), ertsAtomHash("") & mask); // empty atom -> 0

    // (2) end-to-end: the phash2/1 BIF on real interned atom terms matches the same values.
    const Case = struct { name: []const u8, h: i64 };
    for ([_]Case{
        .{ .name = "hello", .h = 7258927 },
        .{ .name = "world", .h = 8284452 },
        .{ .name = "ok", .h = 1883 },
        .{ .name = "undefined", .h = 45914356 },
        .{ .name = "Bar", .h = 18562 },
        .{ .name = "", .h = 0 },
    }) |c| {
        const a = FinalTerms.atom(&m.ctx, try atoms.intern(c.name));
        const r = try phash2_1(&m, &.{a});
        try std.testing.expect(FinalTerms.repIsSmall(r));
        try std.testing.expectEqual(c.h, FinalTerms.smallValOf(r));
    }
}

test "LAW gap-phash2-nil (DIVERGENCE): the erts make_hash2 NIL path is byte-EQ vs pinned OTP-30 — phash2([]) = UINT32_HASH(NIL_DEF=0x02, HCONST_2), a constant leaf; raw 3468870702, masked 113427502" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const mask: u32 = (1 << 27) - 1;

    // (1) the pure helper is byte-EQ vs pinned OTP-30 (raw = phash2([],2^32); masked = phash2/1).
    try std.testing.expectEqual(@as(u32, 3468870702), ertsHash2Nil());
    try std.testing.expectEqual(@as(u32, 113427502), ertsHash2Nil() & mask);

    // (2) end-to-end: phash2/1([]) masks to 113427502; phash2([], 2^32) yields the RAW u32
    // (2^32 range → h % 2^32 == h), proving the full value flows through, not just the mask.
    const r1 = try phash2_1(&m, &.{FinalTerms.nil(&m.ctx)});
    try std.testing.expect(FinalTerms.repIsSmall(r1));
    try std.testing.expectEqual(@as(i64, 113427502), FinalTerms.smallValOf(r1));
    const r2 = try phash2_2(&m, &.{ FinalTerms.nil(&m.ctx), FinalTerms.int(&m.ctx, 4294967296) });
    try std.testing.expectEqual(@as(i64, 3468870702), FinalTerms.smallValOf(r2));
}

test "LAW E2.12 phash2 range + coherence with =:= (the M4 equal-hash law, reused)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const t1 = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) });
    const t2 = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, t1, t2)); // =:=
    const h1 = try phash2_1(&m, &.{t1});
    const h2 = try phash2_1(&m, &.{t2});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, h1, h2)); // COHERENCE

    // range: phash2/2 stays in [0, Range).
    var prng = std.Random.DefaultPrng.init(0x9A54);
    const random = prng.random();
    for (0..50) |_| {
        const v = random.int(i32);
        const term = FinalTerms.int(&m.ctx, v);
        const range: i64 = 1 + @as(i64, random.uintLessThan(u32, 1000));
        const r = try phash2_2(&m, &.{ term, FinalTerms.int(&m.ctx, range) });
        try std.testing.expect(FinalTerms.repIsSmall(r));
        const rv = FinalTerms.smallValOf(r);
        try std.testing.expect(rv >= 0 and rv < range);
    }

    // default /1 range is [0, 2^27).
    const rd = try phash2_1(&m, &.{FinalTerms.int(&m.ctx, 123456)});
    try std.testing.expect(FinalTerms.smallValOf(rd) >= 0 and FinalTerms.smallValOf(rd) < (1 << 27));

    // badarg: non-positive / non-integer range.
    try std.testing.expectError(error.Badarg, phash2_2(&m, &.{ t1, FinalTerms.int(&m.ctx, 0) }));
    try std.testing.expectError(error.Badarg, phash2_2(&m, &.{ t1, FinalTerms.int(&m.ctx, -1) }));
}

test "LAW E31-T2 phash/2 byte-EQ vs pinned OTP-30 make_hash + range + =:=-coherence" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const H = struct {
        // phash(T, Range) as a plain integer (Range fits a small in every case
        // used here, incl. the 2^32 special whose result is <= 2^32 < 2^59).
        fn ph(mm: *Machine, term: Term, range: i64) !i64 {
            const r = try phash_2(mm, &.{ term, FinalTerms.int(&mm.ctx, range) });
            try std.testing.expect(FinalTerms.repIsSmall(r));
            return FinalTerms.smallValOf(r);
        }
        fn plist(mm: *Machine, elems: []const Term) !Term {
            var acc = FinalTerms.nil(&mm.ctx);
            var i = elems.len;
            while (i > 0) {
                i -= 1;
                acc = try FinalTerms.cons(&mm.ctx, elems[i], acc);
            }
            return acc;
        }
    };
    const R1: i64 = 1000000;
    const R2: i64 = 4294967296; // 2^32 special-case (wrap: hash + 1)

    const foo = FinalTerms.atom(&m.ctx, try atoms.intern("foo"));
    const bar = FinalTerms.atom(&m.ctx, try atoms.intern("bar"));
    const ok = FinalTerms.atom(&m.ctx, try atoms.intern("ok"));
    const empty_atom = FinalTerms.atom(&m.ctx, try atoms.intern(""));
    const i = struct {
        fn v(mm: *Machine, x: i64) Term {
            return FinalTerms.int(&mm.ctx, x);
        }
    }.v;

    // Fixed term vector, with OTP-30 (OTP-28 erl; make_hash is the FROZEN
    // deprecated hash → identical) oracle values for phash(T,1000000) and
    // phash(T,2^32). Generated via `erlang:phash(T, R)`.
    const Case = struct { t: Term, h1: i64, h2: i64 };
    const cases = [_]Case{
        .{ .t = i(&m, 0), .h1 = 1, .h2 = 1 },
        .{ .t = i(&m, 1), .h1 = 898428, .h2 = 2788898428 },
        .{ .t = i(&m, 255), .h1 = 495046, .h2 = 2499495046 },
        .{ .t = i(&m, 256), .h1 = 229268, .h2 = 1920229268 },
        .{ .t = i(&m, -1), .h1 = 185270, .h2 = 1680185270 },
        .{ .t = i(&m, -255), .h1 = 481292, .h2 = 3245481292 },
        .{ .t = i(&m, 12345), .h1 = 111988, .h2 = 2030111988 },
        .{ .t = i(&m, 4294967296), .h1 = 898428, .h2 = 2788898428 }, // 2^32 as a small
        .{ .t = i(&m, -4294967296), .h1 = 185270, .h2 = 1680185270 },
        .{ .t = i(&m, 1000000007), .h1 = 726059, .h2 = 193726059 },
        .{ .t = try FinalTerms.intFromI128(&m.ctx, 12345678901234567890), .h1 = 422983, .h2 = 3165422983 },
        .{ .t = try FinalTerms.intFromI128(&m.ctx, -99999999999999999999999999), .h1 = 262218, .h2 = 4292262218 },
        .{ .t = foo, .h1 = 28000, .h2 = 28000 },
        .{ .t = bar, .h1 = 26755, .h2 = 26755 },
        .{ .t = ok, .h1 = 1884, .h2 = 1884 },
        .{ .t = empty_atom, .h1 = 1, .h2 = 1 },
        .{ .t = FinalTerms.nil(&m.ctx), .h1 = 2, .h2 = 2 },
        .{ .t = FinalTerms.float(&m.ctx, 3.14), .h1 = 63656, .h2 = 300063656 },
        .{ .t = FinalTerms.float(&m.ctx, 0.0), .h1 = 1, .h2 = 1 },
        .{ .t = FinalTerms.float(&m.ctx, -0.0), .h1 = 1, .h2 = 1 }, // -0.0 canonicalizes to +0.0
        .{ .t = FinalTerms.float(&m.ctx, 1.0), .h1 = 693249, .h2 = 1072693249 },
        .{ .t = FinalTerms.float(&m.ctx, -2.5), .h1 = 487617, .h2 = 3221487617 },
        .{ .t = FinalTerms.float(&m.ctx, 1.0e10), .h1 = 339296, .h2 = 1644339296 },
        .{ .t = try FinalTerms.binary(&m.ctx, ""), .h1 = 1, .h2 = 1 },
        .{ .t = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 3 }), .h1 = 692590, .h2 = 687692590 },
        .{ .t = try FinalTerms.binary(&m.ctx, "hello"), .h1 = 327964, .h2 = 476327964 },
        .{ .t = try H.plist(&m, &.{ i(&m, 1), i(&m, 2), i(&m, 3) }), .h1 = 869158, .h2 = 3336869158 },
        .{ .t = try H.plist(&m, &.{ i(&m, 97), i(&m, 98), i(&m, 99) }), .h1 = 580166, .h2 = 3654580166 }, // "abc"
        .{ .t = try H.plist(&m, &.{ foo, bar }), .h1 = 313779, .h2 = 1446313779 },
        .{ .t = try FinalTerms.cons(&m.ctx, i(&m, 1), i(&m, 2)), .h1 = 949552, .h2 = 2402949552 }, // [1|2]
        .{ .t = try H.plist(&m, &.{
            try H.plist(&m, &.{i(&m, 1)}),
            try H.plist(&m, &.{i(&m, 2)}),
        }), .h1 = 464617, .h2 = 1718464617 }, // [[1],[2]]
        .{ .t = try H.plist(&m, &.{ foo, i(&m, 1), bar }), .h1 = 479882, .h2 = 669479882 },
        .{ .t = try FinalTerms.tuple(&m.ctx, &.{}), .h1 = 1, .h2 = 1 },
        .{ .t = try FinalTerms.tuple(&m.ctx, &.{i(&m, 1)}), .h1 = 724171, .h2 = 381724171 },
        .{ .t = try FinalTerms.tuple(&m.ctx, &.{ i(&m, 1), i(&m, 2), i(&m, 3) }), .h1 = 354534, .h2 = 4267354534 },
        .{ .t = try FinalTerms.tuple(&m.ctx, &.{ foo, bar }), .h1 = 1976, .h2 = 1131001976 },
        .{ .t = try FinalTerms.tuple(&m.ctx, &.{
            i(&m, 1),
            try FinalTerms.tuple(&m.ctx, &.{ i(&m, 2), i(&m, 3) }),
        }), .h1 = 20175, .h2 = 1865020175 }, // {1,{2,3}}
    };

    for (cases, 0..) |c, idx| {
        const got1 = try H.ph(&m, c.t, R1);
        const got2 = try H.ph(&m, c.t, R2);
        std.testing.expectEqual(c.h1, got1) catch |e| {
            std.debug.print("BYTE-EQ FAIL case #{d} R=1000000: want {d} got {d}\n", .{ idx, c.h1, got1 });
            return e;
        };
        std.testing.expectEqual(c.h2, got2) catch |e| {
            std.debug.print("BYTE-EQ FAIL case #{d} R=2^32: want {d} got {d}\n", .{ idx, c.h2, got2 });
            return e;
        };
        // RANGE law: phash(T,R) in [1, R].
        try std.testing.expect(got1 >= 1 and got1 <= R1);
        try std.testing.expect(got2 >= 1 and got2 <= R2);
    }

    // COHERENCE law: T =:= T' (independently built) ⇒ phash(T,R)==phash(T',R),
    // including the coherent-total extension arm (a map value, non byte-EQ).
    const l_a = try H.plist(&m, &.{ foo, i(&m, 1), try FinalTerms.tuple(&m.ctx, &.{ bar, i(&m, 2) }) });
    const l_b = try H.plist(&m, &.{ foo, i(&m, 1), try FinalTerms.tuple(&m.ctx, &.{ bar, i(&m, 2) }) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, l_a, l_b));
    try std.testing.expectEqual(try H.ph(&m, l_a, R1), try H.ph(&m, l_b, R1));

    // RANGE law over random ranges (never 0, never > 2^32-1 here).
    var prng = std.Random.DefaultPrng.init(0x31D2);
    const random = prng.random();
    for (0..64) |_| {
        const term = i(&m, random.int(i32));
        const range: i64 = 1 + @as(i64, random.uintLessThan(u32, 5_000_000));
        const hv = try H.ph(&m, term, range);
        try std.testing.expect(hv >= 1 and hv <= range);
    }

    // badarg: Range 0, negative, >= 2^32 (but not the 2^32 special), non-integer.
    try std.testing.expectError(error.Badarg, phash_2(&m, &.{ foo, i(&m, 0) }));
    try std.testing.expectError(error.Badarg, phash_2(&m, &.{ foo, i(&m, -1) }));
    try std.testing.expectError(error.Badarg, phash_2(&m, &.{ foo, i(&m, 4294967297) })); // 2^32 + 1
    try std.testing.expectError(error.Badarg, phash_2(&m, &.{ foo, foo })); // non-integer range
    try std.testing.expectError(error.Badarg, phash_2(&m, &.{ foo, try FinalTerms.intFromI128(&m.ctx, 1 << 70) })); // bignum range
}

test "LAW E3.18 cmp_term/2 denotes the standard term order as -1|0|1 (agrees with compare)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));

    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try cmp_term_2(&m, &.{ one, two }), FinalTerms.int(&m.ctx, -1)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try cmp_term_2(&m, &.{ two, one }), FinalTerms.int(&m.ctx, 1)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try cmp_term_2(&m, &.{ two, two }), FinalTerms.int(&m.ctx, 0)));
    // TOTAL across kinds: number < atom, so cmp_term(1, a) == -1.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try cmp_term_2(&m, &.{ one, a }), FinalTerms.int(&m.ctx, -1)));
    // AGREES with FinalTerms.compare over random small pairs (the sign homomorphism).
    var prng = std.Random.DefaultPrng.init(0xC311);
    const random = prng.random();
    for (0..64) |_| {
        const x = FinalTerms.int(&m.ctx, random.intRangeAtMost(i64, -50, 50));
        const y = FinalTerms.int(&m.ctx, random.intRangeAtMost(i64, -50, 50));
        const want: i64 = switch (FinalTerms.compare(&m.ctx, x, y)) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try cmp_term_2(&m, &.{ x, y }), FinalTerms.int(&m.ctx, want)));
    }
}

test "LAW E2.12 setelement: denotation + the SOURCE is unchanged (aliasing law)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const c = FinalTerms.atom(&m.ctx, try atoms.intern("c"));
    const x = FinalTerms.atom(&m.ctx, try atoms.intern("x"));
    const src = try FinalTerms.tuple(&m.ctx, &.{ a, b, c });

    const out = try setelement_3(&m, &.{ FinalTerms.int(&m.ctx, 2), src, x });
    // denotation: {a,x,c}
    const want = try FinalTerms.tuple(&m.ctx, &.{ a, x, c });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, out, want));
    // ALIASING LAW: the source tuple is UNCHANGED (mutant 2: mutate `src`
    // in place instead of a copy — this assertion is exactly what catches
    // it).
    const src_unchanged = try FinalTerms.tuple(&m.ctx, &.{ a, b, c });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, src, src_unchanged));

    // rejections.
    try std.testing.expectError(error.Badarg, setelement_3(&m, &.{ FinalTerms.int(&m.ctx, 0), src, x }));
    try std.testing.expectError(error.Badarg, setelement_3(&m, &.{ FinalTerms.int(&m.ctx, 4), src, x }));
    try std.testing.expectError(error.Badarg, setelement_3(&m, &.{ FinalTerms.int(&m.ctx, 1), a, x }));
}

test "LAW E2.12 append_element: arity+1, last element is Value, prefix unchanged" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const tup = try FinalTerms.tuple(&m.ctx, &.{ a, b });
    const out = try append_element_2(&m, &.{ tup, FinalTerms.int(&m.ctx, 9) });
    const want = try FinalTerms.tuple(&m.ctx, &.{ a, b, FinalTerms.int(&m.ctx, 9) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, out, want));
    try std.testing.expectError(error.Badarg, append_element_2(&m, &.{ a, b }));
}

test "LAW E2.12 make_tuple/2,3: default fill + InitList overrides (last occurrence wins)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const zero = FinalTerms.int(&m.ctx, 0);
    const r2 = try make_tuple_2(&m, &.{ FinalTerms.int(&m.ctx, 3), zero });
    const want2 = try FinalTerms.tuple(&m.ctx, &.{ zero, zero, zero });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r2, want2));

    // {2, 9} then {2, 7}: index 2 (0-based 1) ends at 7 (last occurrence wins).
    const pair1 = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 9) });
    const pair2 = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 7) });
    const extra = try FinalTerms.cons(&m.ctx, pair1, try FinalTerms.cons(&m.ctx, pair2, FinalTerms.nil(&m.ctx)));
    const r3 = try make_tuple_3(&m, &.{ FinalTerms.int(&m.ctx, 3), zero, extra });
    const want3 = try FinalTerms.tuple(&m.ctx, &.{ zero, FinalTerms.int(&m.ctx, 7), zero });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r3, want3));

    try std.testing.expectError(error.Badarg, make_tuple_2(&m, &.{ FinalTerms.int(&m.ctx, -1), zero }));
}

test "LAW E6.6 insert_element/delete_element: splice/drop + inverse + range rejection" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const c = FinalTerms.atom(&m.ctx, try atoms.intern("c"));
    const x = FinalTerms.atom(&m.ctx, try atoms.intern("x"));
    const abc = try FinalTerms.tuple(&m.ctx, &.{ a, b, c });

    // splice BEFORE index 2 -> {a,x,b,c}; index 1 prepends; index arity+1 appends.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try insert_element_3(&m, &.{ FinalTerms.int(&m.ctx, 2), abc, x }), try FinalTerms.tuple(&m.ctx, &.{ a, x, b, c })));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try insert_element_3(&m, &.{ FinalTerms.int(&m.ctx, 1), abc, x }), try FinalTerms.tuple(&m.ctx, &.{ x, a, b, c })));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try insert_element_3(&m, &.{ FinalTerms.int(&m.ctx, 4), abc, x }), try FinalTerms.tuple(&m.ctx, &.{ a, b, c, x })));

    // drop index 2 -> {a,c}; the SOURCE tuple is unchanged (aliasing law).
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try delete_element_2(&m, &.{ FinalTerms.int(&m.ctx, 2), abc }), try FinalTerms.tuple(&m.ctx, &.{ a, c })));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, abc, try FinalTerms.tuple(&m.ctx, &.{ a, b, c })));

    // INVERSE: delete_element(I, insert_element(I, T, V)) == T (V spliced then dropped).
    const spliced = try insert_element_3(&m, &.{ FinalTerms.int(&m.ctx, 2), abc, x });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try delete_element_2(&m, &.{ FinalTerms.int(&m.ctx, 2), spliced }), abc));

    // range rejection: insert accepts 1..arity+1, delete 1..arity; a non-tuple/
    // non-small arg is badarg.
    try std.testing.expectError(error.Badarg, insert_element_3(&m, &.{ FinalTerms.int(&m.ctx, 5), abc, x }));
    try std.testing.expectError(error.Badarg, insert_element_3(&m, &.{ FinalTerms.int(&m.ctx, 0), abc, x }));
    try std.testing.expectError(error.Badarg, delete_element_2(&m, &.{ FinalTerms.int(&m.ctx, 4), abc }));
    try std.testing.expectError(error.Badarg, delete_element_2(&m, &.{ FinalTerms.int(&m.ctx, 1), a }));
}

test "LAW E2.12 unique_integer: strictly increasing across calls (uniqueness + monotonicity)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const monotonic_atom = FinalTerms.atom(&m.ctx, try atoms.intern("monotonic"));
    const positive_atom = FinalTerms.atom(&m.ctx, try atoms.intern("positive"));
    const opts = try FinalTerms.cons(&m.ctx, monotonic_atom, try FinalTerms.cons(&m.ctx, positive_atom, FinalTerms.nil(&m.ctx)));

    var prev = try unique_integer_0(&m, &.{});
    for (0..20) |_| {
        const next = try unique_integer_1(&m, &.{opts});
        try std.testing.expect(FinalTerms.compare(&m.ctx, prev, next) == .lt);
        try std.testing.expect(FinalTerms.smallValOf(next) > 0); // always positive
        prev = next;
    }

    // an unknown option atom is rejected.
    const bad_opt = try FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, try atoms.intern("bogus")), FinalTerms.nil(&m.ctx));
    try std.testing.expectError(error.Badarg, unique_integer_1(&m, &.{bad_opt}));
}

test "LAW E2.12 term_to_iovec: concatenation equals term_to_binary" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const t = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.atom(&m.ctx, try atoms.intern("ok")) });
    const bin = try conv.term_to_binary_1(&m, &.{t});
    const iov = try term_to_iovec_1(&m, &.{t});
    // [Bin] — a singleton list whose one element == term_to_binary(T).
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, iov) == .cons);
    const head = FinalTerms.listHead(&m.ctx, iov);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, head, bin));
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, FinalTerms.listTail(&m.ctx, iov)) == .nil);
}

test "LAW E3.6: make_ref/0 freshness — N calls pairwise =/=, each =:= itself (MUTANT 2's law)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    var refs: [64]Term = undefined;
    for (0..refs.len) |i| refs[i] = try make_ref_0(&m, &.{});

    for (0..refs.len) |i| {
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, refs[i], refs[i])); // =:= itself
        for (i + 1..refs.len) |j| {
            try std.testing.expect(!FinalTerms.eqlExact(&m.ctx, refs[i], refs[j])); // pairwise =/=
        }
        try std.testing.expect(FinalTerms.repIsRef(&m.ctx, refs[i]));
    }
}
