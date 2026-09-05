//! # bifs/conv — the term-conversion BIF family (E2.5)
//!
//! ## Signature
//! Same contract as `bifs/erlang.zig`: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over ALREADY-
//! RESOLVED term arguments, computed via an EXISTING algebra (`atom_table`,
//! `term_algebra`, `etf`, `unicode` — NO new term/ETF semantics live here),
//! returning the result term or a clean `error.Badarg`/`error.Badarith`. It
//! NEVER panics on a well-formed call (the `ubif`/`bif` contract).
//!
//! ## The dispatch mechanism (unchanged — see `bifs/erlang.zig` / `bifs/dispatch.zig`)
//! This task adds ONLY `pub fn`s here, `implOf` arms in `bifs/dispatch.zig`,
//! and `implemented_map` rows in `harness/bif_gen.ml`. The generated
//! `bif_table.zig`, the loader, and the `bif_call` executor are untouched.
//!
//! ## Semantic domain — reuse, not reinvention
//!   atom<->list/binary   atom_to_list/list_to_atom/list_to_existing_atom via
//!                        `unicode.utf8ToList`/`listToUtf8` over the atom
//!                        name bytes (`AtomTable.nameOf`/`intern`); the
//!                        `latin1` encoding of atom_to_binary/binary_to_atom
//!                        re-maps codepoints through `unicode.encodeCp`/
//!                        `decodeCp` (a byte IS the codepoint in latin1).
//!   integer<->list/binary integer_to_list/list_to_integer/integer_to_binary/
//!                        binary_to_integer via a shared base-N digit
//!                        codec (2..36) over `term_algebra.intFromI128`/
//!                        `smallValOf`; SMALL-INT-domain (an i128-magnitude
//!                        overflow or a bignum operand defers via a clean
//!                        `badarith`, consistent with E2.4's bignum-defer).
//!   list<->binary        binary_to_list/list_to_binary/iolist_to_binary via
//!                        `term_algebra.iolistToBinary` (already flattens
//!                        nested lists+binaries+byte-ints) and `binBytes`.
//!   list<->bitstring      (E3.2) bitstring_to_list/list_to_bitstring via
//!                        `bitstring_algebra.concat`/`FinalTerms.bitsOf` —
//!                        the BIT-LEVEL generalization of list<->binary
//!                        above; a sub-byte segment survives as the LAST
//!                        LIST ELEMENT (`bitstring_to_list`, e.g.
//!                        `[1,2,<<3:3>>]` — a list may hold a bitstring as
//!                        an ordinary element, NOT an improper tail) and
//!                        folds back in bit-exact (`list_to_bitstring`).
//!   tuple<->list          tuple_to_list/list_to_tuple via `tupleElem`/
//!                        `tupleArity`/`cons`/`tuple`.
//!   term<->binary         term_to_binary/binary_to_term ARE the Machine-aware
//!                        ETF observer over `etf.encodeWithLocalIdentity` /
//!                        `etf.decode` — M9 still proves the pure round-trip;
//!                        E8.2u adds only the VM-owned local pid/ref/port wire
//!                        identity rewrite after `setnode/2`. The `/2` forms
//!                        accept (and IGNORE) an options list — no option
//!                        changes the wire format we produce/consume.
//!   float<->list          float_to_list/list_to_float via `std.fmt`
//!                        decimal formatting/parsing (see scope note below).
//!   pid/ref/port<->list   (E3.6) pid_to_list/ref_to_list/port_to_list ARE
//!                        `diag.formatTerm` (the E3.5 print-shape formatter)
//!                        materialized as an Erlang char-list — ONE
//!                        formatter, no second source of the
//!                        `<0.N.S>`/`#Ref<0.W1.W2.W3>`/`#Port<0.N>` shape.
//!                        list_to_pid/list_to_ref/list_to_port PARSE that
//!                        exact grammar back via a small hand-rolled
//!                        recursive-descent `Parser` (below) — liveness-
//!                        agnostic (a never-created id still builds, no
//!                        process/port table to check against — matching
//!                        real BEAM, which also does not validate).
//!
//! ## Scope limits (documented, honest)
//!   - `list_to_integer`/`integer_to_binary`/etc. are SMALL-INT-domain: a
//!     `.big` operand, or a parsed magnitude exceeding i128, is a clean
//!     `badarith` (deferred to the bignum-arithmetic follow-up), NOT a panic
//!     — mirrors `bifs/erlang.zig`'s arith scope note.
//!   - `float_to_list/2` implements `{decimals, D}` (0..253), `{scientific, D}`
//!     (0..249), `compact` (with `{decimals,D}`), and `short` (DIVERGENCE 713 —
//!     the shorter of the shortest decimal/scientific rendering, byte-EQ to erts)
//!     — byte-EQ to erts (DIVERGENCE 708). The bare `[]`/`[compact]` corner and the
//!     `{decimals,_}`+`{scientific,_}` mix fall back in erts to its 20-digit
//!     scientific default (the out-of-scope `float_to_list/1` shape below), so
//!     those are a clean `badarg` (an unsupported arg-space corner, not a wrong
//!     answer).
//!   - `float_to_list/1`'s default formatting is Zig's shortest round-trip
//!     decimal (`std.fmt` `{d}`), NOT BEAM's verbose 20-fraction-digit
//!     scientific default — a DOCUMENTED DIVERGENCE (see `DIVERGENCE_LOG.md`
//!     "E2.5 float_to_list/1 default format"); both forms round-trip via
//!     `list_to_float`, which is the law this module holds.
//!   - E3.2: `bitstring_to_list`/`list_to_bitstring` ARE now implemented
//!     (below, "list <-> bitstring") — the E3.1 term-level bitstring kind
//!     landed the representation this pair needed; both are wired into
//!     `implOf`/`implemented_map`, flipped off the deferred-E3 ledger row.
//!   - atom names longer than 255 bytes (BEAM's atom-length cap) are a clean
//!     `badarg` on `list_to_atom`/`binary_to_atom`.
//!   - PIN LEDGER NOTE: the pinned `bif.tab` does NOT declare
//!     `erlang:list_to_integer/1,2`, `erlang:binary_to_integer/1,2`,
//!     `erlang:atom_to_binary/1`, or `erlang:binary_to_atom/1` — those are
//!     erlang.erl LIBRARY wrappers (default base 10 / default encoding utf8)
//!     around a lower-arity/different-module primitive, not BIFs on this
//!     pin. This module still defines `list_to_integer_1`/`binary_to_integer_1`/
//!     `atom_to_binary_1`/`binary_to_atom_1` as plain Zig helpers (law-tested
//!     directly below) — they are simply NOT wired into `bifs/dispatch.zig`
//!     because there is no ledger row for them (a wire-anyway would be dead
//!     code: `resolve` never reaches `implOf` for an absent bif_table key).
//!     `erts_internal:list_to_integer/2` / `binary_to_integer/2` ARE real
//!     bif.tab entries — the base-explicit primitives underneath the erlang.erl
//!     wrappers — and ARE wired (`bifs/dispatch.zig`'s `implOfErtsInternal`).
//!
//! ## Laws (see the test suite below)
//!   - ROUND-TRIP  list_to_integer(integer_to_list(N)) == N (any base 2..36)
//!   - ROUND-TRIP  binary_to_integer(integer_to_binary(N)) == N
//!   - ROUND-TRIP  list_to_atom(atom_to_list(A)) == A
//!   - ROUND-TRIP  binary_to_term(term_to_binary(T)) denotes T (delegates to
//!     the M9 `decode∘encode=id` law — this module adds no new ETF law)
//!   - ROUND-TRIP  list_to_tuple(tuple_to_list(Tup)) == Tup
//!   - ROUND-TRIP  list_to_float(float_to_list(F)) == F (finite, moderate F)
//!   - ROUND-TRIP  (E3.2) bitstring_to_list(list_to_bitstring(L)) == id where
//!     total; list_to_bitstring of a list of aligned binaries == their
//!     `binConcat`; a trailing unaligned segment survives both directions
//!   - ROUND-TRIP  (E3.6) list_to_pid(pid_to_list(P)) == P (same for
//!     ref/port); pid_to_list denotes diag's EXACT print string; a
//!     never-created id ("<0.9999.0>") still builds (liveness-agnostic)
//!   - DENOTATION  integer_to_list(255, 16) == "FF"; list_to_integer("FF",16)
//!     == 255; tuple_to_list({a,b}) == [a,b]; atom_to_list('ok') == "ok"
//!   - REJECTION   malformed digits / bad base / non-matching kind / absent
//!     existing atom → a clean `error.Badarg` (never a panic)

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const etf = @import("../etf.zig");
const unicode = @import("../unicode.zig");
const prim_file = @import("../prim_file.zig"); // gap-localtime-tz (DIVERGENCE 731): host TZ offset
const bsa = @import("../bitstring_algebra.zig");
const diag = @import("../diag.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

// ── shared helpers ─────────────────────────────────────────────────────────

const DIGIT_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

fn digitChar(v: u8) u8 {
    return DIGIT_CHARS[v];
}

fn digitVal(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'Z' => c - 'A' + 10,
        'a'...'z' => c - 'a' + 10,
        else => null,
    };
}

/// Extract an i128 from a SMALL integer term (the small-int scope of this
/// family). A non-integer term is `badarg` (real BEAM behaviour); a `.big`
/// operand IS an integer but outside our scope — the documented bignum-defer,
/// `badarith` (mirrors `bifs/erlang.zig`'s arith scope note).
fn needSmallI128(m: *Machine, w: Term) BifError!i128 {
    if (FinalTerms.repIsSmall(w)) return FinalTerms.smallValOf(w);
    if (FinalTerms.repIsBig(&m.ctx, w)) return error.Badarith;
    return error.Badarg;
}

/// A base in 2..36, decoded from a SMALL int term arg; anything else is
/// `badarg` (BEAM: `integer_to_list(N, Base)` badargs on an out-of-range or
/// non-integer base).
fn needBase(w: Term) BifError!u8 {
    if (!FinalTerms.repIsSmall(w)) return error.Badarg;
    const v = FinalTerms.smallValOf(w);
    if (v < 2 or v > 36) return error.Badarg;
    return @intCast(v);
}

/// digits(|value|, base) into `buf`, most-significant digit first. Returns
/// the used slice. MUTANT 1 (integer_to_list emits little-endian digits) is
/// the omission of the `std.mem.reverse` call below.
fn magDigits(buf: []u8, mag_in: u128, base: u8) []u8 {
    var mag = mag_in;
    var n: usize = 0;
    if (mag == 0) {
        buf[0] = '0';
        n = 1;
    } else {
        while (mag > 0) {
            const d: u8 = @intCast(mag % base);
            buf[n] = digitChar(d);
            n += 1;
            mag /= base;
        }
    }
    std.mem.reverse(u8, buf[0..n]); // <- MUTANT 1 target: delete to break big-endian order
    return buf[0..n];
}

/// integer -> ASCII digit bytes (sign-prefixed), owned by `out` (caller-sized
/// stack buffer of >= 130 bytes is plenty for base-2 i128).
fn intToDigits(out: *[136]u8, value: i128, base: u8) []u8 {
    const neg = value < 0;
    const mag: u128 = if (neg) @as(u128, @intCast(-(value + 1))) + 1 else @intCast(value);
    var dbuf: [136]u8 = undefined;
    const digits = magDigits(&dbuf, mag, base);
    var n: usize = 0;
    if (neg) {
        out[0] = '-';
        n = 1;
    }
    @memcpy(out[n .. n + digits.len], digits);
    return out[0 .. n + digits.len];
}

/// DIVERGENCE 687 (gap-int-to-base-bignum): format a BIGNUM (`repIsBig`) term in
/// `base` (2..36) → caller-owned digit bytes — UPPERCASE `A..Z` for base>10
/// (matching `DIGIT_CHARS` + OTP), a leading `-` for a negative. `integer_to_list`/
/// `integer_to_binary` (both arities) badarith'd on ANY runtime bignum because the
/// shared `needSmallI128` path rejects a bignum with `error.Badarith`; only erlc
/// CONSTANT-FOLDING a literal `integer_to_list(10^41)` masked it (a variable/runtime
/// bignum reproduces the crash — the FM-DISPATCH-DEAD-via-constant-fold class).
/// Uses `std.math.big` over the term's OWN limbs (no copy).
fn bigToBaseBytes(m: *Machine, w: Term, base: u8) BifError![]u8 {
    const parts = FinalTerms.bigPartsOf(&m.ctx, w);
    const c = std.math.big.int.Const{ .limbs = parts.limbs, .positive = parts.positive };
    return c.toStringAlloc(m.gpa, base, .upper) catch return error.OutOfMemory;
}

/// ASCII digit bytes (optional leading '-') -> i128, or `null` on malformed
/// digits / empty digit run.
fn digitsToInt(bytes: []const u8, base: u8) ?i128 {
    if (bytes.len == 0) return null;
    var i: usize = 0;
    var neg = false;
    if (bytes[0] == '-') {
        neg = true;
        i = 1;
    } else if (bytes[0] == '+') {
        i = 1;
    }
    if (i >= bytes.len) return null; // sign with no digits
    var acc: i128 = 0;
    while (i < bytes.len) : (i += 1) {
        const d = digitVal(bytes[i]) orelse return null;
        if (d >= base) return null;
        acc = acc * base + d;
        if (acc > (1 << 126)) return null; // guard against runaway magnitude
    }
    return if (neg) -acc else acc;
}

/// Bytes -> a cons list of byte-int elements (BEAM's "string" of small ints).
/// `bytes` MUST NOT alias live `ctx`-heap memory (e.g. a `binBytes` slice):
/// `FinalTerms.cons` can grow/reallocate the heap's backing array, which
/// would invalidate such a slice mid-loop. Callers passing heap-derived bytes
/// dupe first (see `binary_to_list_1`/`_3`); a caller-owned stack/gpa buffer
/// (e.g. `intToDigits`'s output) is always safe as-is.
fn bytesToCharList(m: *Machine, bytes: []const u8) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = bytes.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, bytes[i]), acc) catch return error.OutOfMemory;
    }
    return acc;
}

/// A proper list of byte-range (0..255) SMALL ints -> owned byte slice
/// (caller frees with `m.gpa`), or `badarg` on a non-list / out-of-range /
/// non-integer element / improper tail.
fn charListToBytes(m: *Machine, l: Term) BifError![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(m.gpa);
    var cur = l;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        if (!FinalTerms.repIsSmall(h)) return error.Badarg;
        const v = FinalTerms.smallValOf(h);
        if (v < 0 or v > 255) return error.Badarg;
        out.append(m.gpa, @intCast(v)) catch return error.OutOfMemory;
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg;
    return out.toOwnedSlice(m.gpa) catch error.OutOfMemory;
}

const AtomEncoding = enum { utf8, latin1 };

fn atomEncodingOf(m: *Machine, w: Term) BifError!AtomEncoding {
    if (!FinalTerms.repIsAtom(w)) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(w));
    if (std.mem.eql(u8, name, "utf8") or std.mem.eql(u8, name, "unicode")) return .utf8;
    if (std.mem.eql(u8, name, "latin1")) return .latin1;
    return error.Badarg;
}

/// latin1 bytes (each byte IS a codepoint 0..255) -> UTF-8 bytes, owned.
fn latin1ToUtf8(gpa: std.mem.Allocator, bytes: []const u8) BifError![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (bytes) |b| {
        var buf: [4]u8 = undefined;
        const n = unicode.encodeCp(b, &buf) catch return error.Badarg;
        out.appendSlice(gpa, buf[0..n]) catch return error.OutOfMemory;
    }
    return out.toOwnedSlice(gpa) catch error.OutOfMemory;
}

/// UTF-8 bytes -> latin1 bytes (every decoded codepoint must fit 0..255), owned.
fn utf8ToLatin1(gpa: std.mem.Allocator, bytes: []const u8) BifError![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var pos: usize = 0;
    while (pos < bytes.len) {
        const r = unicode.decodeCp(bytes[pos..]) catch return error.Badarg;
        if (r.cp > 255) return error.Badarg;
        out.append(gpa, @intCast(r.cp)) catch return error.OutOfMemory;
        pos += r.len;
    }
    return out.toOwnedSlice(gpa) catch error.OutOfMemory;
}

// ── atom <-> list/binary ────────────────────────────────────────────────────

pub fn atom_to_list(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    const bin = FinalTerms.binary(&m.ctx, name) catch return error.OutOfMemory;
    return unicode.utf8ToList(m.gpa, &m.ctx, bin) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.Badarg,
    };
}

fn listToAtomName(m: *Machine, args: []const Term) BifError![]u8 {
    if (FinalTerms.kindOf(&m.ctx, args[0]) != .cons and FinalTerms.kindOf(&m.ctx, args[0]) != .nil) return error.Badarg;
    const bin = unicode.listToUtf8(m.gpa, &m.ctx, args[0]) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Badarg,
    };
    const name = FinalTerms.binBytes(&m.ctx, bin);
    if (name.len > 255) return error.Badarg;
    return m.gpa.dupe(u8, name) catch error.OutOfMemory;
}

pub fn list_to_atom(m: *Machine, args: []const Term) BifError!Term {
    const name = try listToAtomName(m, args);
    defer m.gpa.free(name);
    const idx = m.ctx.atoms.intern(name) catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

pub fn list_to_existing_atom(m: *Machine, args: []const Term) BifError!Term {
    const name = try listToAtomName(m, args);
    defer m.gpa.free(name);
    const idx = m.ctx.atoms.lookup.get(name) orelse return error.Badarg;
    return FinalTerms.atom(&m.ctx, idx);
}

fn atomToBinaryEnc(m: *Machine, atom_term: Term, enc: AtomEncoding) BifError!Term {
    if (!FinalTerms.repIsAtom(atom_term)) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(atom_term));
    switch (enc) {
        .utf8 => return FinalTerms.binary(&m.ctx, name) catch error.OutOfMemory,
        .latin1 => {
            const bytes = try utf8ToLatin1(m.gpa, name);
            defer m.gpa.free(bytes);
            return FinalTerms.binary(&m.ctx, bytes) catch error.OutOfMemory;
        },
    }
}

pub fn atom_to_binary_1(m: *Machine, args: []const Term) BifError!Term {
    return atomToBinaryEnc(m, args[0], .utf8);
}
pub fn atom_to_binary_2(m: *Machine, args: []const Term) BifError!Term {
    const enc = try atomEncodingOf(m, args[1]);
    return atomToBinaryEnc(m, args[0], enc);
}

fn binaryToAtomEnc(m: *Machine, bin_term: Term, enc: AtomEncoding) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, bin_term)) return error.Badarg;
    const bytes = FinalTerms.binBytes(&m.ctx, bin_term);
    const owned = switch (enc) {
        .utf8 => blk: {
            // Validate strict UTF-8 (round-trip through decodeCp), reuse bytes as-is.
            var pos: usize = 0;
            while (pos < bytes.len) {
                const r = unicode.decodeCp(bytes[pos..]) catch return error.Badarg;
                pos += r.len;
            }
            break :blk m.gpa.dupe(u8, bytes) catch return error.OutOfMemory;
        },
        .latin1 => try latin1ToUtf8(m.gpa, bytes),
    };
    defer m.gpa.free(owned);
    if (owned.len > 255) return error.Badarg;
    const idx = m.ctx.atoms.intern(owned) catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

pub fn binary_to_atom_1(m: *Machine, args: []const Term) BifError!Term {
    return binaryToAtomEnc(m, args[0], .utf8);
}
pub fn binary_to_atom_2(m: *Machine, args: []const Term) BifError!Term {
    const enc = try atomEncodingOf(m, args[1]);
    return binaryToAtomEnc(m, args[0], enc);
}

// ── integer <-> list/binary ─────────────────────────────────────────────────

pub fn integer_to_list_1(m: *Machine, args: []const Term) BifError!Term {
    return integerToListBase(m, args[0], 10);
}
pub fn integer_to_list_2(m: *Machine, args: []const Term) BifError!Term {
    const base = try needBase(args[1]);
    return integerToListBase(m, args[0], base);
}
fn integerToListBase(m: *Machine, w: Term, base: u8) BifError!Term {
    if (FinalTerms.repIsBig(&m.ctx, w)) { // DIVERGENCE 687: bignum path
        const digits = try bigToBaseBytes(m, w, base);
        defer m.gpa.free(digits);
        return bytesToCharList(m, digits);
    }
    const v = try needSmallI128(m, w);
    var buf: [136]u8 = undefined;
    const digits = intToDigits(&buf, v, base);
    return bytesToCharList(m, digits);
}

pub fn list_to_integer_1(m: *Machine, args: []const Term) BifError!Term {
    return listToIntegerBase(m, args[0], 10);
}
pub fn list_to_integer_2(m: *Machine, args: []const Term) BifError!Term {
    const base = try needBase(args[1]);
    return listToIntegerBase(m, args[0], base);
}
fn listToIntegerBase(m: *Machine, l: Term, base: u8) BifError!Term {
    const bytes = try charListToBytes(m, l);
    defer m.gpa.free(bytes);
    const v = digitsToInt(bytes, base) orelse return error.Badarg;
    return FinalTerms.intFromI128(&m.ctx, v) catch error.OutOfMemory;
}

/// `erts_internal:list_to_integer/2` — the LENIENT prefix-parser primitive that
/// sits UNDERNEATH the `string` module (NOT `erlang:list_to_integer/2`, which is
/// STRICT — whole-string, bare int, badarg on trailing — and keeps mapping to
/// `list_to_integer_2`). Contract (OTP-30 `bif.c` erts_internal_list_to_integer_2,
/// confirmed against the pinned oracle): parse an optional leading sign + the
/// LEADING run of digits valid FOR THE BASE and return `{Int, Rest}` (Rest = the
/// unparsed suffix, a char list); a first char that is not a digit-for-base (incl.
/// empty / sign-only) yields the ATOM `no_integer`; a magnitude beyond the fast
/// i128 path yields the ATOM `big` (`string.erl` then falls back to
/// binary_to_integer). Was WRONGLY aliased to the strict `list_to_integer_2` — a
/// bare int made `string:to_integer("42")`→`{error,42}` (string.erl matched the
/// bare int against its `Reason` clause). DIVERGENCE 675.
pub fn erts_internal_list_to_integer_2(m: *Machine, args: []const Term) BifError!Term {
    const base = try needBase(args[1]);
    const bytes = try charListToBytes(m, args[0]);
    defer m.gpa.free(bytes);
    var i: usize = 0;
    var neg = false;
    if (bytes.len > 0 and bytes[0] == '-') {
        neg = true;
        i = 1;
    } else if (bytes.len > 0 and bytes[0] == '+') {
        i = 1;
    }
    const digit_start = i;
    var acc: i128 = 0;
    var overflow = false;
    const limit: i128 = 1 << 126;
    while (i < bytes.len) : (i += 1) {
        const d = digitVal(bytes[i]) orelse break; // stop at a non-digit char
        if (d >= base) break; // valid char but OUT OF RANGE for the base → stop
        // Guard BEFORE the multiply so acc*base can never overflow i128 (a
        // magnitude past the fast path → the atom `big`, string.erl falls back).
        if (acc > @divTrunc(limit, base)) {
            overflow = true;
            break;
        }
        acc = acc * base + d;
    }
    // No leading digit consumed (empty / sign-only / first char a non-digit).
    if (i == digit_start) return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("no_integer") catch return error.OutOfMemory);
    if (overflow) return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("big") catch return error.OutOfMemory);
    const int_term = FinalTerms.intFromI128(&m.ctx, if (neg) -acc else acc) catch return error.OutOfMemory;
    const rest_term = try bytesToCharList(m, bytes[i..]); // the unparsed suffix
    return FinalTerms.tuple(&m.ctx, &.{ int_term, rest_term }) catch error.OutOfMemory;
}

pub fn integer_to_binary_1(m: *Machine, args: []const Term) BifError!Term {
    return integerToBinaryBase(m, args[0], 10);
}
pub fn integer_to_binary_2(m: *Machine, args: []const Term) BifError!Term {
    const base = try needBase(args[1]);
    return integerToBinaryBase(m, args[0], base);
}
fn integerToBinaryBase(m: *Machine, w: Term, base: u8) BifError!Term {
    if (FinalTerms.repIsBig(&m.ctx, w)) { // DIVERGENCE 687: bignum path
        const digits = try bigToBaseBytes(m, w, base);
        defer m.gpa.free(digits);
        return FinalTerms.binary(&m.ctx, digits) catch error.OutOfMemory;
    }
    const v = try needSmallI128(m, w);
    var buf: [136]u8 = undefined;
    const digits = intToDigits(&buf, v, base);
    return FinalTerms.binary(&m.ctx, digits) catch error.OutOfMemory;
}

pub fn binary_to_integer_1(m: *Machine, args: []const Term) BifError!Term {
    return binaryToIntegerBase(m, args[0], 10);
}
pub fn binary_to_integer_2(m: *Machine, args: []const Term) BifError!Term {
    const base = try needBase(args[1]);
    return binaryToIntegerBase(m, args[0], base);
}
fn binaryToIntegerBase(m: *Machine, w: Term, base: u8) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, w)) return error.Badarg;
    const bytes = FinalTerms.binBytes(&m.ctx, w);
    const v = digitsToInt(bytes, base) orelse return error.Badarg;
    return FinalTerms.intFromI128(&m.ctx, v) catch error.OutOfMemory;
}

// ── list <-> binary ──────────────────────────────────────────────────────────

pub fn binary_to_list_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    // Dupe off-heap first: `bytesToCharList`'s `cons` calls can grow/reallocate
    // `ctx`'s backing store, which would invalidate a `binBytes` slice mid-loop.
    const owned = m.gpa.dupe(u8, FinalTerms.binBytes(&m.ctx, args[0])) catch return error.OutOfMemory;
    defer m.gpa.free(owned);
    return bytesToCharList(m, owned);
}

/// `binary_to_list(Bin, Start, Stop)` — 1-based, INCLUSIVE range (BEAM's odd
/// convention: unlike 0-based `binary_part`, `Stop` is the last included byte).
pub fn binary_to_list_3(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    if (!FinalTerms.repIsSmall(args[1]) or !FinalTerms.repIsSmall(args[2])) return error.Badarg;
    const bytes = FinalTerms.binBytes(&m.ctx, args[0]);
    const start = FinalTerms.smallValOf(args[1]);
    const stop = FinalTerms.smallValOf(args[2]);
    if (start < 1 or stop < start or stop > @as(i64, @intCast(bytes.len))) return error.Badarg;
    // Dupe off-heap first (see `binary_to_list_1`'s note).
    const owned = m.gpa.dupe(u8, bytes[@intCast(start - 1)..@intCast(stop)]) catch return error.OutOfMemory;
    defer m.gpa.free(owned);
    return bytesToCharList(m, owned);
}

pub fn list_to_binary(m: *Machine, args: []const Term) BifError!Term {
    const k = FinalTerms.kindOf(&m.ctx, args[0]);
    if (k != .cons and k != .nil) return error.Badarg;
    return FinalTerms.iolistToBinary(&m.ctx, args[0]) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.Badarg,
    };
}

pub fn iolist_to_binary(m: *Machine, args: []const Term) BifError!Term {
    const k = FinalTerms.kindOf(&m.ctx, args[0]);
    if (k != .cons and k != .nil and k != .binary) return error.Badarg;
    return FinalTerms.iolistToBinary(&m.ctx, args[0]) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.Badarg,
    };
}

// ── list <-> bitstring (E3.2) ─────────────────────────────────────────────────
//
// `bitstring_to_list/1` / `list_to_bitstring/1` are `list_to_binary`/
// `binary_to_list`'s BIT-LEVEL generalization: reuse `bitstring_algebra`'s
// `concat`/`bitsOf` — no second bit-vector implementation.

/// `bitstring_to_list(Bitstring)` — BEAM: a PROPER list of full-byte
/// integers, with a trailing SUB-BYTE bitstring as the LAST LIST ELEMENT
/// (NOT an improper tail — a list can hold any term, including a bitstring,
/// as an ordinary element) when the input is unaligned:
/// `bitstring_to_list(<<1,2,3:3>>) == [1,2,<<3:3>>]` is the 3-ELEMENT proper
/// list `[1, 2, <<3:3>>]`, tail `[]`. An aligned bitstring/true binary
/// produces a plain proper list of bytes only, matching `binary_to_list/1`
/// exactly (no bitstring element at all).
pub fn bitstring_to_list(m: *Machine, args: []const Term) BifError!Term {
    if (FinalTerms.kindOf(&m.ctx, args[0]) != .binary) return error.Badarg;
    const bits = FinalTerms.bitsOf(&m.ctx, args[0]);
    const full_bytes = bits.bit_len / 8;
    const rem_bits = bits.bit_len % 8;
    // Dupe off-heap first: `cons`'s heap growth can invalidate a live
    // `ctx`-heap slice mid-loop (the `binary_to_list_1` landmine, same fix).
    const owned = m.gpa.dupe(u8, bits.bytes) catch return error.OutOfMemory;
    defer m.gpa.free(owned);

    var acc: Term = FinalTerms.nil(&m.ctx);
    if (rem_bits != 0) {
        const last = FinalTerms.bitstring(&m.ctx, owned[full_bytes .. full_bytes + 1], rem_bits) catch return error.OutOfMemory;
        acc = FinalTerms.cons(&m.ctx, last, acc) catch return error.OutOfMemory;
    }
    var i = full_bytes;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, owned[i]), acc) catch return error.OutOfMemory;
    }
    return acc;
}

/// Recursively concatenate one iolist-of-bytes-and-bitstrings ELEMENT into
/// `acc` (an arena-owned running `Bits`). A bitstring/binary element
/// contributes its FULL bit content — including a sub-byte segment — via
/// `bsa.concat`, which appends bit-for-bit regardless of alignment; a
/// nested list recurses (`accBitstringList`). This is the arm
/// `bitstring_to_list`'s corresponding-list ELEMENT round-trips through: the
/// trailing bitstring `bitstring_to_list` emits is an ordinary LIST ELEMENT
/// (see that fn's doc comment), so it arrives HERE, not at
/// `accBitstringList`'s separate improper-tail arm below.
///
/// MUTANT 2 (do NOT do this): deleting the `k == .binary` arm below (i.e.
/// only accepting `.cons`/byte-int elements, falling through to the
/// `error.Badarg` case for a bitstring/binary element) drops the trailing
/// unaligned segment `bitstring_to_list` produces as its LAST ELEMENT —
/// killed by the `bitstring_to_list ∘ list_to_bitstring == id` law (it
/// surfaces as a `Badarg` on any unaligned input, never a silent short
/// result, but the law fails either way: the round-trip must SUCCEED and
/// recover the exact original bits).
fn accBitstringElem(m: *Machine, arena: std.mem.Allocator, t: Term, acc: *bsa.Bits) BifError!void {
    if (FinalTerms.repIsSmall(t)) {
        const v = FinalTerms.smallValOf(t);
        if (v < 0 or v > 255) return error.Badarg;
        const byte = [1]u8{@intCast(v)};
        acc.* = bsa.concat(arena, acc.*, bsa.fromBinary(&byte)) catch return error.OutOfMemory;
        return;
    }
    const k = FinalTerms.kindOf(&m.ctx, t);
    if (k == .binary) { // true binary OR bitstring (aligned or sub-byte) — one path
        acc.* = bsa.concat(arena, acc.*, FinalTerms.bitsOf(&m.ctx, t)) catch return error.OutOfMemory;
        return;
    }
    if (k == .nil or k == .cons) return accBitstringList(m, arena, t, acc);
    return error.Badarg;
}

/// Walk a (possibly improper) list, folding every element AND a non-nil
/// improper tail into `acc`. BEAM's `BitstringList` type permits a
/// bitstring/binary TAIL as well as a bitstring/binary ELEMENT (the general
/// bit-syntax-construction shape `[Byte1, Byte2 | Bin]`) — `bitstring_to_list`
/// itself never emits an improper tail (its trailing segment is always the
/// last ELEMENT, see that fn's doc comment), but `list_to_bitstring` still
/// accepts one on the wider BEAM-legal input shape.
fn accBitstringList(m: *Machine, arena: std.mem.Allocator, t0: Term, acc: *bsa.Bits) BifError!void {
    var t = t0;
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, t)) {
            .nil => return,
            .cons => {
                try accBitstringElem(m, arena, FinalTerms.listHead(&m.ctx, t), acc);
                t = FinalTerms.listTail(&m.ctx, t);
            },
            .binary => { // improper tail: a bitstring/binary segment, folded in whole
                acc.* = bsa.concat(arena, acc.*, FinalTerms.bitsOf(&m.ctx, t)) catch return error.OutOfMemory;
                return;
            },
            else => return error.Badarg,
        }
    }
}

/// `list_to_bitstring(BitstringList)` — the inverse of `bitstring_to_list`:
/// flattens a nested iolist of bytes/bitstrings/binaries (bitstring
/// elements and the improper tail preserve their EXACT bit content, sub-
/// byte segments included) into ONE bitstring via `bitstring_algebra.concat`.
/// `list_to_bitstring([Bin1, Bin2, ...])` of all-aligned binaries equals
/// their `binConcat`/`iolistToBinary` — the aligned case is this op's
/// restriction.
pub fn list_to_bitstring(m: *Machine, args: []const Term) BifError!Term {
    const k = FinalTerms.kindOf(&m.ctx, args[0]);
    if (k != .cons and k != .nil) return error.Badarg;
    var arena = std.heap.ArenaAllocator.init(m.gpa);
    defer arena.deinit();
    var acc: bsa.Bits = .{ .bytes = &.{}, .bit_len = 0 };
    try accBitstringList(m, arena.allocator(), args[0], &acc);
    return FinalTerms.bitstring(&m.ctx, acc.bytes, acc.bit_len) catch error.OutOfMemory;
}

// ── tuple <-> list ───────────────────────────────────────────────────────────

pub fn tuple_to_list(m: *Machine, args: []const Term) BifError!Term {
    if (FinalTerms.kindOf(&m.ctx, args[0]) != .tuple) return error.Badarg;
    const arity = FinalTerms.tupleArity(&m.ctx, args[0]);
    var acc = FinalTerms.nil(&m.ctx);
    var i = arity;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.tupleElem(&m.ctx, args[0], i), acc) catch return error.OutOfMemory;
    }
    return acc;
}

pub fn list_to_tuple(m: *Machine, args: []const Term) BifError!Term {
    const k = FinalTerms.kindOf(&m.ctx, args[0]);
    if (k != .cons and k != .nil) return error.Badarg;
    var elems: std.ArrayList(Term) = .empty;
    defer elems.deinit(m.gpa);
    var cur = args[0];
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        elems.append(m.gpa, FinalTerms.listHead(&m.ctx, cur)) catch return error.OutOfMemory;
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg;
    return FinalTerms.tuple(&m.ctx, elems.items) catch error.OutOfMemory;
}

// ── term <-> binary (etf IS the wire format — already law-covered) ──────────

fn localIdentity(m: *Machine) ?etf.LocalIdentity {
    const node = m.dist_local_node orelse return null;
    return .{ .node = node, .creation = m.dist_local_creation };
}

fn termToBinaryImpl(m: *Machine, t: Term) BifError!Term {
    var out = etf.encodeWithLocalIdentity(m.gpa, &m.ctx, t, localIdentity(m)) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return error.Badarg,
    };
    defer out.deinit(m.gpa);
    return FinalTerms.binary(&m.ctx, out.items) catch error.OutOfMemory;
}

pub fn term_to_binary_1(m: *Machine, args: []const Term) BifError!Term {
    return termToBinaryImpl(m, args[0]);
}
/// `/2` accepts (and ignores) an options list (e.g. `[compressed]`) — no
/// option changes the wire bytes we produce (see module scope note).
pub fn term_to_binary_2(m: *Machine, args: []const Term) BifError!Term {
    return termToBinaryImpl(m, args[0]);
}

fn binaryToTermImpl(m: *Machine, w: Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, w)) return error.Badarg;
    // Dupe off-heap first: `etf.decode`'s reader reads FROM `bytes` while
    // `decodeTerm` APPENDS the result terms into the SAME `ctx.words` backing
    // store — an amortized-doubling grow reallocates it, dangling a `binBytes`
    // slice mid-decode (a read-after-free that surfaces as a spurious
    // UnknownTag→badarg on a well-formed input). Same class as the
    // `bytesToCharList` gotcha and the `binary_to_list_1` fix.
    const owned = m.gpa.dupe(u8, FinalTerms.binBytes(&m.ctx, w)) catch return error.OutOfMemory;
    defer m.gpa.free(owned);
    return etf.decode(m.gpa, &m.ctx, owned) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.Badarg,
    };
}

pub fn binary_to_term_1(m: *Machine, args: []const Term) BifError!Term {
    return binaryToTermImpl(m, args[0]);
}
/// `/2` accepts (and ignores) an options list (e.g. `[safe]`) — decode is
/// already total over well-formed ETF bytes (see module scope note).
pub fn binary_to_term_2(m: *Machine, args: []const Term) BifError!Term {
    return binaryToTermImpl(m, args[0]);
}

// ── E3.18: derivations of the term-conversion family ─────────────────────────
//
// The E2 fast-follow siblings (DIVERGENCE_LOG entry 13(a)) that are pure
// derivations of already-implemented conversions — no new algebra:
//   external_size/1,2  == byte length of `term_to_binary/1`'s output (the ETF
//                         encoder's byte count; erts documents it as exactly
//                         that size), WITHOUT materializing the binary term.
//   binary_to_existing_atom/2 == binary_to_atom/2 but LOOKUP-only (never
//                         interns) — the binary twin of list_to_existing_atom.
//   iolist_size/1      == byte length of `iolist_to_binary/1`'s flattening.
//   split_binary/2     == {part(Bin,0,N), part(Bin,N,size-N)} over binPart.

/// `external_size(Term)` — the ETF byte count `term_to_binary(Term)` would
/// produce. Encodes once and returns the length; never builds a binary term.
pub fn external_size_1(m: *Machine, args: []const Term) BifError!Term {
    var out = etf.encodeWithLocalIdentity(m.gpa, &m.ctx, args[0], localIdentity(m)) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return error.Badarg,
    };
    defer out.deinit(m.gpa);
    return FinalTerms.int(&m.ctx, @intCast(out.items.len));
}
/// `/2` accepts (and ignores) an options list — no option changes our wire size.
pub fn external_size_2(m: *Machine, args: []const Term) BifError!Term {
    return external_size_1(m, args[0..1]);
}

fn binaryToExistingAtomEnc(m: *Machine, bin_term: Term, enc: AtomEncoding) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, bin_term)) return error.Badarg;
    const bytes = FinalTerms.binBytes(&m.ctx, bin_term);
    const owned = switch (enc) {
        .utf8 => blk: {
            var pos: usize = 0;
            while (pos < bytes.len) {
                const r = unicode.decodeCp(bytes[pos..]) catch return error.Badarg;
                pos += r.len;
            }
            break :blk m.gpa.dupe(u8, bytes) catch return error.OutOfMemory;
        },
        .latin1 => try latin1ToUtf8(m.gpa, bytes),
    };
    defer m.gpa.free(owned);
    if (owned.len > 255) return error.Badarg;
    // Existing-only: LOOKUP, never intern (the list_to_existing_atom discipline).
    const idx = m.ctx.atoms.lookup.get(owned) orelse return error.Badarg;
    return FinalTerms.atom(&m.ctx, idx);
}

pub fn binary_to_existing_atom_2(m: *Machine, args: []const Term) BifError!Term {
    const enc = try atomEncodingOf(m, args[1]);
    return binaryToExistingAtomEnc(m, args[0], enc);
}

/// `iolist_size(IoList)` — the flattened byte length. Reuses the SAME
/// `iolistToBinary` flattening `iolist_to_binary/1` uses, then observes its
/// size (no second iolist walker).
pub fn iolist_size_1(m: *Machine, args: []const Term) BifError!Term {
    const k = FinalTerms.kindOf(&m.ctx, args[0]);
    if (k != .cons and k != .nil and k != .binary) return error.Badarg;
    const bin = FinalTerms.iolistToBinary(&m.ctx, args[0]) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Badarg,
    };
    return FinalTerms.int(&m.ctx, @intCast(FinalTerms.binSize(&m.ctx, bin)));
}

/// `iolist_to_iovec(IoList)` — a list of binaries whose concatenation equals
/// the flattened iolist. erts documents the exact split as UNSPECIFIED, so a
/// single-chunk `[Bin]` (or `[]` for empty) is a conforming iovec. The
/// invariant law is `iolist_to_binary(iolist_to_iovec(X)) == iolist_to_binary(X)`.
pub fn iolist_to_iovec_1(m: *Machine, args: []const Term) BifError!Term {
    const k = FinalTerms.kindOf(&m.ctx, args[0]);
    if (k != .cons and k != .nil and k != .binary) return error.Badarg;
    const bin = FinalTerms.iolistToBinary(&m.ctx, args[0]) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Badarg,
    };
    if (FinalTerms.binSize(&m.ctx, bin) == 0) return FinalTerms.nil(&m.ctx); // [] for empty
    return FinalTerms.cons(&m.ctx, bin, FinalTerms.nil(&m.ctx)) catch error.OutOfMemory;
}

// ── E3.18: the pure Gregorian-calendar pair ──────────────────────────────────
//
// `posixtime_to_universaltime/1` / `universaltime_to_posixtime/1` — PURE integer
// calendar arithmetic (no OS clock read, no timezone lookup — unlike `localtime*`,
// which stay deferred-E5). Uses Howard Hinnant's `civil_from_days`/
// `days_from_civil` (public-domain, proleptic Gregorian), floored division so
// pre-1970 POSIX seconds work. `universaltime` is `{{Y,Mo,D},{H,Mi,S}}` UTC.

fn civilFromDays(z_in: i64) [3]i64 { // -> {year, month, day}
    const z = z_in + 719468;
    const era = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe = z - era * 146097; // [0, 146096]
    const yoe = @divTrunc(doe - @divTrunc(doe, 1460) + @divTrunc(doe, 36524) - @divTrunc(doe, 146096), 365); // [0,399]
    const y = yoe + era * 400;
    const doy = doe - (365 * yoe + @divTrunc(yoe, 4) - @divTrunc(yoe, 100)); // [0,365]
    const mp = @divTrunc(5 * doy + 2, 153); // [0,11]
    const d = doy - @divTrunc(153 * mp + 2, 5) + 1; // [1,31]
    const m = if (mp < 10) mp + 3 else mp - 9; // [1,12]
    return .{ y + @as(i64, if (m <= 2) 1 else 0), m, d };
}

fn daysFromCivil(y_in: i64, m: i64, d: i64) i64 {
    const y = y_in - @as(i64, if (m <= 2) 1 else 0);
    const era = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe = y - era * 400; // [0,399]
    const doy = @divTrunc(153 * (if (m > 2) m - 3 else m + 9) + 2, 5) + d - 1; // [0,365]
    const doe = yoe * 365 + @divTrunc(yoe, 4) - @divTrunc(yoe, 100) + doy; // [0,146096]
    return era * 146097 + doe - 719468;
}

pub fn posixtime_to_universaltime_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsSmall(args[0])) return error.Badarg;
    const secs = FinalTerms.smallValOf(args[0]);
    const days = @divFloor(secs, 86400);
    const rem = secs - days * 86400; // [0, 86399] (floored)
    const ymd = civilFromDays(days);
    const date = FinalTerms.tuple(&m.ctx, &.{
        FinalTerms.int(&m.ctx, ymd[0]), FinalTerms.int(&m.ctx, ymd[1]), FinalTerms.int(&m.ctx, ymd[2]),
    }) catch return error.OutOfMemory;
    const time = FinalTerms.tuple(&m.ctx, &.{
        FinalTerms.int(&m.ctx, @divTrunc(rem, 3600)),
        FinalTerms.int(&m.ctx, @divTrunc(@mod(rem, 3600), 60)),
        FinalTerms.int(&m.ctx, @mod(rem, 60)),
    }) catch return error.OutOfMemory;
    return FinalTerms.tuple(&m.ctx, &.{ date, time }) catch error.OutOfMemory;
}

fn smallElem(m: *Machine, tup: Term, i: usize) BifError!i64 {
    const e = FinalTerms.tupleElem(&m.ctx, tup, i);
    if (!FinalTerms.repIsSmall(e)) return error.Badarg;
    return FinalTerms.smallValOf(e);
}

/// `erlang:universaltime/0` → `{{Y,Mo,D},{H,Mi,S}}` UTC — the real system clock
/// (osSystemTime seconds) run through the pure Gregorian conversion. cowboy_clock:
/// rfc1123 needs it for the HTTP `Date` header (gap-app-boot-engine); without it a
/// cowboy handler crashed → 500. UTC only (no TZ), which is exactly what rfc1123 uses.
pub fn universaltime_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const secs: i64 = @intCast(m.clock.osSystemTime(1)); // real UTC seconds
    return posixtime_to_universaltime_1(m, &.{FinalTerms.int(&m.ctx, secs)});
}

// ── gap-localtime-tz (DIVERGENCE 731): the LOCAL-time calendar family ──────────
// `universaltime_0` is UTC-only. These add the host TIMEZONE seam: the pure
// Gregorian pair above + `prim_file.tzOffsetAt` (reads `/etc/localtime` TZif → the
// UTC↔local offset in seconds at a given instant). The conversions are DETERMINISTIC
// given the host zone, so two VMs on the SAME host are byte-EQ; the zone DATA itself
// is host-specific (EQUIV across hosts — the real OS-timezone value, never a
// fabricated constant, FM-OBS-1). This discharges the `deferred-calendar-tz` bucket
// (date/0, time/0, localtime/0, {universal,local}time_to_* conversions) the bif_table
// reason cited as "a self-contained calendar/TZ dedicated slice over the S21 seam".

/// `erlang:universaltime_to_localtime/1` — UTC `{{Y,Mo,D},{H,Mi,S}}` → LOCAL wall
/// clock. `off = tzOffsetAt(utc_secs)` (correct: tzOffsetAt is keyed by the UTC
/// instant), local wall-clock = utc + off.
pub fn universaltime_to_localtime_1(m: *Machine, args: []const Term) BifError!Term {
    const secs_t = try universaltime_to_posixtime_1(m, args); // UTC datetime → UTC secs
    const secs = FinalTerms.smallValOf(secs_t);
    const off = prim_file.tzOffsetAt(secs);
    return posixtime_to_universaltime_1(m, &.{FinalTerms.int(&m.ctx, secs + off)});
}

/// `erlang:localtime_to_universaltime/1` — LOCAL wall clock → UTC. Inverts the
/// offset: utc = local − off(utc). `tzOffsetAt` is keyed by UTC, so estimate off at
/// the local instant then REFINE once at the UTC estimate — exact except inside a
/// DST discontinuity (the ~1 h/yr ambiguous fold, where OTP's `/2` `IsDst` flag
/// disambiguates and `/1` takes the standard-time side; disclosed residual).
pub fn localtime_to_universaltime_1(m: *Machine, args: []const Term) BifError!Term {
    const local_t = try universaltime_to_posixtime_1(m, args); // local datetime → local secs
    const local = FinalTerms.smallValOf(local_t);
    var off = prim_file.tzOffsetAt(local); // 1st estimate (offset near the local instant)
    off = prim_file.tzOffsetAt(local - off); // refine at the UTC estimate
    return posixtime_to_universaltime_1(m, &.{FinalTerms.int(&m.ctx, local - off)});
}

// NOTE (honest scope): `erlang:localtime_to_universaltime/2` (with the `IsDst`
// `true|false` flag that FORCES the standard-vs-DST fold side) is DELIBERATELY not
// wired here — it stays deferred. A correct `/2` needs the zone's SEPARATE standard
// and DST offsets (this slice only has `tzOffsetAt(instant)`, the offset AT one
// instant), so delegating `/2` to `/1` returns a WRONG value for an explicit flag at
// a DST-affected local time (verified: OTP `localtime_to_universaltime(SummerDT,
// false)` differs from `/1`). Shipping that would be a false EQ (FM-OBS-1). `/1`
// (== `/2` with `IsDst=undefined`) is byte-EQ and is what discharges the concrete
// cascades (`sys:statistics`, `calendar:local_time`).

/// `erlang:localtime/0` — the current LOCAL wall-clock `{{Y,Mo,D},{H,Mi,S}}`.
pub fn localtime_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const secs: i64 = @intCast(m.clock.osSystemTime(1)); // real UTC seconds now
    const off = prim_file.tzOffsetAt(secs);
    return posixtime_to_universaltime_1(m, &.{FinalTerms.int(&m.ctx, secs + off)});
}

/// `erlang:date/0` — the DATE part of `localtime/0` (`{Y,Mo,D}`).
pub fn date_0(m: *Machine, args: []const Term) BifError!Term {
    const lt = try localtime_0(m, args);
    return FinalTerms.tupleElem(&m.ctx, lt, 0);
}

/// `erlang:time/0` — the TIME part of `localtime/0` (`{H,Mi,S}`).
pub fn time_0(m: *Machine, args: []const Term) BifError!Term {
    const lt = try localtime_0(m, args);
    return FinalTerms.tupleElem(&m.ctx, lt, 1);
}

/// gap-justified-bif-sweep (DIVERGENCE 653): `erlang:now/0` → `{MegaSecs, Secs,
/// MicroSecs}` from the REAL system clock (UTC microseconds since the epoch, split
/// erts-style). TRUTHFUL, host-nondeterministic (never fabricated, FM-OBS-1) — like
/// `universaltime/0`, so the ROW stays `.justified` (deferred-calendar-tz: the VALUE
/// is a host time, not byte-EQ to the oracle) but is RESOLVABLE from a compiled beam
/// (undef → a working truthful timestamp; legacy code still calls `now()`). NOT
/// TZ-coupled — the system-time value is UTC, so unlike date/time/localtime it needs
/// no timezone database. The strict-monotonic-uniqueness of the deprecated erts now/0
/// is NOT modelled (a documented bound — the VALUE is truthful, the tie-break is not).
pub fn now_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const total_us: i64 = @intCast(m.clock.osSystemTime(1_000_000)); // real UTC microseconds
    const total_s = @divFloor(total_us, 1_000_000);
    const micros = @mod(total_us, 1_000_000);
    const mega = @divFloor(total_s, 1_000_000);
    const secs = @mod(total_s, 1_000_000);
    return FinalTerms.tuple(&m.ctx, &.{
        FinalTerms.int(&m.ctx, mega),
        FinalTerms.int(&m.ctx, secs),
        FinalTerms.int(&m.ctx, micros),
    }) catch error.OutOfMemory;
}

pub fn universaltime_to_posixtime_1(m: *Machine, args: []const Term) BifError!Term {
    const dt = args[0];
    if (FinalTerms.kindOf(&m.ctx, dt) != .tuple or FinalTerms.tupleArity(&m.ctx, dt) != 2) return error.Badarg;
    const date = FinalTerms.tupleElem(&m.ctx, dt, 0);
    const time = FinalTerms.tupleElem(&m.ctx, dt, 1);
    if (FinalTerms.kindOf(&m.ctx, date) != .tuple or FinalTerms.tupleArity(&m.ctx, date) != 3) return error.Badarg;
    if (FinalTerms.kindOf(&m.ctx, time) != .tuple or FinalTerms.tupleArity(&m.ctx, time) != 3) return error.Badarg;
    const y = try smallElem(m, date, 0);
    const mo = try smallElem(m, date, 1);
    const d = try smallElem(m, date, 2);
    const h = try smallElem(m, time, 0);
    const mi = try smallElem(m, time, 1);
    const s = try smallElem(m, time, 2);
    const days = daysFromCivil(y, mo, d);
    return FinalTerms.int(&m.ctx, days * 86400 + h * 3600 + mi * 60 + s);
}

/// `split_binary(Bin, Pos)` — `{binary_part(Bin,0,Pos), binary_part(Bin,Pos,size-Pos)}`.
/// A non-binary, non-small `Pos`, or out-of-range `Pos` is `badarg`.
pub fn split_binary_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    if (!FinalTerms.repIsSmall(args[1])) return error.Badarg;
    const size = FinalTerms.binSize(&m.ctx, args[0]);
    const pos_i = FinalTerms.smallValOf(args[1]);
    if (pos_i < 0 or pos_i > @as(i64, @intCast(size))) return error.Badarg;
    const pos: usize = @intCast(pos_i);
    const left = FinalTerms.binPart(&m.ctx, args[0], 0, pos) catch return error.Badarg;
    const right = FinalTerms.binPart(&m.ctx, args[0], pos, size - pos) catch return error.Badarg;
    return FinalTerms.tuple(&m.ctx, &.{ left, right }) catch error.OutOfMemory;
}

// ── float <-> list ────────────────────────────────────────────────────────────

/// Default float formatting: Zig's shortest round-trip decimal, always with a
/// decimal point (BEAM's default is a verbose 20-fraction-digit scientific
/// form — a DOCUMENTED DIVERGENCE, see `DIVERGENCE_LOG.md`; both round-trip
/// via `list_to_float`, the law this module actually holds).
fn floatToDecimalBytes(gpa: std.mem.Allocator, f: f64) BifError![]u8 {
    var stack: [512]u8 = undefined;
    const s = std.fmt.bufPrint(&stack, "{d}", .{f}) catch return error.Badarg;
    if (std.mem.indexOfScalar(u8, s, '.') == null and std.mem.indexOfAny(u8, s, "eE") == null) {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(gpa);
        buf.appendSlice(gpa, s) catch return error.OutOfMemory;
        buf.appendSlice(gpa, ".0") catch return error.OutOfMemory;
        return buf.toOwnedSlice(gpa) catch error.OutOfMemory;
    }
    return gpa.dupe(u8, s) catch error.OutOfMemory;
}

fn floatToFixedBytes(gpa: std.mem.Allocator, f: f64, decimals: u8) BifError![]u8 {
    var stack: [700]u8 = undefined;
    const s = std.fmt.bufPrint(&stack, "{d:.[1]}", .{ f, decimals }) catch return error.Badarg;
    return gpa.dupe(u8, s) catch error.OutOfMemory;
}

fn needFloat(m: *Machine, w: Term) BifError!f64 {
    if (!FinalTerms.repIsFloat(&m.ctx, w)) return error.Badarg;
    return FinalTerms.floatValOf(&m.ctx, w);
}

pub fn float_to_list_1(m: *Machine, args: []const Term) BifError!Term {
    const f = try needFloat(m, args[0]);
    const bytes = try floatToDecimalBytes(m.gpa, f);
    defer m.gpa.free(bytes);
    return bytesToCharList(m, bytes);
}

/// `/2` supports `[{decimals, D}]` (0..253), `[{scientific, D}]` (0..249), and
/// the `compact` flag (with `{decimals, D}` — trims trailing fraction zeros,
/// keeping ≥1 digit after the point). The BARE `[]` / `[compact]` corners and
/// the `{decimals,_}`+`{scientific,_}` mix fall back in erts to its verbose
/// 20-fraction-digit scientific default, which this module deliberately does
/// NOT reproduce (the documented `float_to_list/1` shortest-round-trip scope) —
/// so those corners are a clean `badarg` (an unsupported arg-space corner, not
/// a wrong answer). See DIVERGENCE 708.
pub fn float_to_list_2(m: *Machine, args: []const Term) BifError!Term {
    const f = try needFloat(m, args[0]);
    const bytes = try floatWithOptsBytes(m, f, args[1]);
    defer m.gpa.free(bytes);
    return bytesToCharList(m, bytes);
}

const FloatMode = enum { decimals, scientific, short };
const FloatFmtOpts = struct { mode: FloatMode, count: u8, compact: bool };

/// Parse a `float_to_list/2`/`float_to_binary/2` option list into the supported
/// subset. `{decimals,D}`/`{scientific,D}` (their mix is the erts-20-digit-default
/// scope limit → `badarg`) OR the `short` flag; `compact` is valid only with
/// `{decimals,D}`. A `{decimals,_}`/`{scientific,_}` present OVERRIDES `short`
/// (erts precedence); the bare `[]`/`[compact]`-only corner is `badarg`.
fn parseFloatFmtOpts(m: *Machine, opts: Term) BifError!FloatFmtOpts {
    var mode: ?FloatMode = null;
    var count: u8 = 0;
    var compact = false;
    var has_short = false;
    var cur = opts;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const el = FinalTerms.listHead(&m.ctx, cur);
        cur = FinalTerms.listTail(&m.ctx, cur);
        if (FinalTerms.repIsAtom(el)) {
            const an = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(el));
            if (std.mem.eql(u8, an, "compact")) {
                compact = true;
                continue;
            }
            if (std.mem.eql(u8, an, "short")) {
                has_short = true;
                continue;
            }
            return error.Badarg;
        }
        if (FinalTerms.kindOf(&m.ctx, el) != .tuple or FinalTerms.tupleArity(&m.ctx, el) != 2) return error.Badarg;
        const tag = FinalTerms.tupleElem(&m.ctx, el, 0);
        if (!FinalTerms.repIsAtom(tag)) return error.Badarg;
        const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(tag));
        const d = FinalTerms.tupleElem(&m.ctx, el, 1);
        if (!FinalTerms.repIsSmall(d)) return error.Badarg;
        const v = FinalTerms.smallValOf(d);
        if (std.mem.eql(u8, name, "decimals")) {
            if (mode != null) return error.Badarg; // duplicate / mix unsupported
            if (v < 0 or v > 253) return error.Badarg;
            mode = .decimals;
            count = @intCast(v);
        } else if (std.mem.eql(u8, name, "scientific")) {
            if (mode != null) return error.Badarg;
            if (v < 0 or v > 249) return error.Badarg;
            mode = .scientific;
            count = @intCast(v);
        } else return error.Badarg;
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg; // improper list
    if (mode == null) {
        if (has_short) return .{ .mode = .short, .count = 0, .compact = false }; // short alone
        return error.Badarg; // bare / compact-only -> erts default (out of scope)
    }
    const md = mode.?; // decimals/scientific present -> overrides short (erts precedence)
    if (compact and md == .scientific) return error.Badarg; // compact only pairs with decimals here
    return .{ .mode = md, .count = count, .compact = compact };
}

/// The shared `float_to_list/2` + `float_to_binary/2` byte formatter (a single
/// source of truth). Caller owns the returned slice.
fn floatWithOptsBytes(m: *Machine, f: f64, opts: Term) BifError![]u8 {
    const o = try parseFloatFmtOpts(m, opts);
    switch (o.mode) {
        .decimals => {
            const bytes = try floatToFixedBytes(m.gpa, f, o.count);
            if (!o.compact) return bytes;
            defer m.gpa.free(bytes);
            return compactDecimalsBytes(m.gpa, bytes);
        },
        .scientific => return floatToScientificBytes(m.gpa, f, o.count),
        .short => return floatToShortestBytes(m.gpa, f),
    }
}

/// `float_to_list(F, [short])` — erts' SHORTEST round-trip text: the shorter of
/// the shortest decimal and the shortest scientific rendering (tie → decimal).
/// erts picks whichever printed form is fewer characters — `100000.0`→`1.0e5`,
/// `1.23e-4`→`1.23e-4`, `3.14`→`3.14`, `0.0001`→`0.0001` (tie, decimal wins).
/// The scientific exponent is erts-short (`e5`/`e-4`/`e120` — sign only when
/// negative, no padding — distinct from `{scientific,D}`'s `e+00` form). The
/// mantissa always carries a `.0` when integral (`1e5`→`1.0e5`).
fn floatToShortestBytes(gpa: std.mem.Allocator, f: f64) BifError![]u8 {
    const dec = try floatToDecimalBytes(gpa, f); // shortest decimal, `.0`-normalized
    errdefer gpa.free(dec);
    var stack: [512]u8 = undefined;
    const raw = std.fmt.bufPrint(&stack, "{e}", .{f}) catch return error.Badarg; // shortest scientific
    const epos = std.mem.indexOfScalar(u8, raw, 'e') orelse return dec; // no exponent → decimal only
    const mant = raw[0..epos];
    const exp = raw[epos..]; // includes the 'e' and sign/digits (erts-short shape)
    var sci: std.ArrayList(u8) = .empty;
    defer sci.deinit(gpa);
    sci.appendSlice(gpa, mant) catch return error.OutOfMemory;
    if (std.mem.indexOfScalar(u8, mant, '.') == null) sci.appendSlice(gpa, ".0") catch return error.OutOfMemory;
    sci.appendSlice(gpa, exp) catch return error.OutOfMemory;
    if (sci.items.len < dec.len) { // scientific strictly shorter → use it (tie keeps decimal)
        gpa.free(dec);
        return sci.toOwnedSlice(gpa) catch error.OutOfMemory;
    }
    return dec;
}

/// Trim trailing fraction zeros from a fixed-decimals rendering, keeping at
/// least one digit after the point (`"1.0000"`→`"1.0"`, `"100.000000"`→`"100.0"`);
/// a point-less rendering (`{decimals,0}`→`"4"`) is returned as-is.
fn compactDecimalsBytes(gpa: std.mem.Allocator, s: []const u8) BifError![]u8 {
    const dot = std.mem.indexOfScalar(u8, s, '.') orelse return gpa.dupe(u8, s) catch error.OutOfMemory;
    var end = s.len;
    while (end > dot + 2 and s[end - 1] == '0') end -= 1;
    return gpa.dupe(u8, s[0..end]) catch error.OutOfMemory;
}

/// `float_to_list(F, [{scientific, D}])` — erts scientific text: a D-decimal
/// mantissa and a sign-always, ≥2-digit exponent (`3.142e+00`, `1e+03`,
/// `-1.00e-03`, `1.0000e+120`). Zig's `{e:.D}` gives the erts mantissa digits
/// (same round-to-nearest); only the exponent field is reshaped (Zig emits an
/// unpadded, sign-only-on-negative `e<exp>`).
fn floatToScientificBytes(gpa: std.mem.Allocator, f: f64, decimals: u8) BifError![]u8 {
    var stack: [700]u8 = undefined;
    const s = std.fmt.bufPrint(&stack, "{e:.[1]}", .{ f, @as(usize, decimals) }) catch return error.Badarg;
    const epos = std.mem.indexOfScalar(u8, s, 'e') orelse return error.Badarg;
    const mant = s[0..epos];
    const exp = std.fmt.parseInt(i32, s[epos + 1 ..], 10) catch return error.Badarg;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    out.appendSlice(gpa, mant) catch return error.OutOfMemory;
    out.append(gpa, 'e') catch return error.OutOfMemory;
    out.append(gpa, if (exp < 0) '-' else '+') catch return error.OutOfMemory;
    const aexp: u32 = @intCast(if (exp < 0) -exp else exp);
    var eb: [16]u8 = undefined;
    const es = std.fmt.bufPrint(&eb, "{d}", .{aexp}) catch return error.Badarg;
    if (es.len < 2) out.append(gpa, '0') catch return error.OutOfMemory; // erts pads the exponent to ≥2 digits
    out.appendSlice(gpa, es) catch return error.OutOfMemory;
    return out.toOwnedSlice(gpa) catch error.OutOfMemory;
}

pub fn list_to_float(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try charListToBytes(m, args[0]);
    defer m.gpa.free(bytes);
    if (std.mem.indexOfScalar(u8, bytes, '.') == null) return error.Badarg; // BEAM requires a decimal point
    const f = std.fmt.parseFloat(f64, bytes) catch return error.Badarg;
    if (!std.math.isFinite(f)) return error.Badarg;
    return FinalTerms.float(&m.ctx, f);
}

// ── float <-> binary (E6.6 — dirty-TAGGED pure rows) ─────────────────────────
//
// `float_to_binary`/`binary_to_float` are the `float_to_list`/`list_to_float`
// pair with a BINARY carrier instead of a char-list — the SAME formatter/parser,
// no second source of truth (exactly the `integer_to_binary`/`binary_to_integer`
// relationship to `integer_to_list`/`list_to_integer`). Both are dirty-cpu-test-
// tagged (a scheduling hint), semantically pure. `float_to_binary/1`'s default
// text is Zig's shortest round-trip (NOT erts' fixed 20-digit form — the
// documented `float_to_list/1` discipline: the LAW this module holds is the
// ROUND-TRIP `binary_to_float(float_to_binary(F)) == F`, not the intermediate
// bytes). `float_to_binary/2` supports only `{decimals, D}` (matching
// `float_to_list/2`'s scope) — a FIXED-width form that IS byte-stable, so it
// differentials byte-for-byte. `binary_to_float/1` parses the erts grammar (a
// decimal point required) via the SAME `std.fmt.parseFloat` `list_to_float` uses.

/// `float_to_binary(Float)` — the shortest round-trip decimal, as a binary.
pub fn float_to_binary_1(m: *Machine, args: []const Term) BifError!Term {
    const f = try needFloat(m, args[0]);
    const bytes = try floatToDecimalBytes(m.gpa, f);
    defer m.gpa.free(bytes);
    return FinalTerms.binary(&m.ctx, bytes) catch error.OutOfMemory;
}

/// `float_to_binary(Float, [{decimals, D}])` — the fixed-decimals form, as a
/// binary. Only `{decimals, D}` (0..253) is supported (the `float_to_list/2`
/// scope limit); any other option list is `badarg`.
pub fn float_to_binary_2(m: *Machine, args: []const Term) BifError!Term {
    const f = try needFloat(m, args[0]);
    const bytes = try floatWithOptsBytes(m, f, args[1]);
    defer m.gpa.free(bytes);
    return FinalTerms.binary(&m.ctx, bytes) catch error.OutOfMemory;
}

/// `binary_to_float(Binary)` — parse a float binary (a decimal point required,
/// like `list_to_float`; non-finite is `badarg`).
pub fn binary_to_float_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    const bytes = FinalTerms.binBytes(&m.ctx, args[0]);
    if (std.mem.indexOfScalar(u8, bytes, '.') == null) return error.Badarg; // BEAM requires a decimal point
    const f = std.fmt.parseFloat(f64, bytes) catch return error.Badarg;
    if (!std.math.isFinite(f)) return error.Badarg;
    return FinalTerms.float(&m.ctx, f);
}

// ── pid/reference/port <-> list (E3.6) ───────────────────────────────────────
//
// `pid_to_list/1`, `ref_to_list/1`, `port_to_list/1` are `diag.formatValue`'s
// pid/reference/port print arms MATERIALIZED AS A LIST — ONE formatter, no
// second source of the `<0.N.S>`/`#Ref<0.W1.W2.W3>`/`#Port<0.N>` shape (see
// `src/diag.zig`'s E3.5 print-shape arms, which this reuses via
// `diag.formatTerm`). The `list_to_*` inverses PARSE that exact grammar back
// (see `parseListPrefix`/`Parser` below) — a small, honest hand-rolled
// recursive-descent parser over the SAME literal shape, not a second
// generator. Both directions are liveness-agnostic: BEAM does not validate
// that a decoded id was ever actually allocated — `list_to_pid("<0.9999.0>")`
// builds the term for a never-created pid exactly like real BEAM does (a
// documented, pinned behaviour, not a gap) — this module has no process
// table to check against in the first place, so "liveness-agnostic" is
// simply the honest description of what building a pid/ref/port term FROM
// its printed digits can mean here.

/// A term of the matching kind -> its `diag`-formatted string, as an Erlang
/// char-list. Reuses `diag.formatTerm` — the SAME formatter `pid_to_list`/
/// `ref_to_list`/`port_to_list` and the crash-dump serializer both run
/// through; there is no second string-building path to drift from it.
fn termToCharList(m: *Machine, t: Term) BifError!Term {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(m.gpa);
    diag.formatTerm(m.gpa, &m.ctx, t, &out) catch return error.OutOfMemory;
    return bytesToCharList(m, out.items);
}

pub fn pid_to_list(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsPid(&m.ctx, args[0])) return error.Badarg;
    return termToCharList(m, args[0]);
}

pub fn ref_to_list(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsRef(&m.ctx, args[0])) return error.Badarg;
    return termToCharList(m, args[0]);
}

pub fn port_to_list(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsPort(&m.ctx, args[0])) return error.Badarg;
    return termToCharList(m, args[0]);
}

/// A tiny cursor-based literal/decimal recognizer over the pinned print
/// grammar. `expectLit` consumes an exact literal or fails without
/// consuming; `decimal` consumes a run of ASCII digits (>=1) into a checked
/// `u64` (overflow -> null, never a wraparound) or fails without consuming.
/// Every `list_to_*` parser below is `expectLit`s and `decimal`s chained
/// end-to-end, checked to consume the WHOLE string (a trailing byte is
/// malformed, not silently ignored) — this is the entire parse grammar,
/// deliberately not generalized beyond these three fixed shapes.
const Parser = struct {
    s: []const u8,
    pos: usize = 0,

    fn expectLit(p: *Parser, lit: []const u8) bool {
        if (p.pos + lit.len > p.s.len) return false;
        if (!std.mem.eql(u8, p.s[p.pos .. p.pos + lit.len], lit)) return false;
        p.pos += lit.len;
        return true;
    }

    fn decimal(p: *Parser) ?u64 {
        const start = p.pos;
        var v: u64 = 0;
        while (p.pos < p.s.len and p.s[p.pos] >= '0' and p.s[p.pos] <= '9') {
            const d: u64 = p.s[p.pos] - '0';
            v = std.math.mul(u64, v, 10) catch return null;
            v = std.math.add(u64, v, d) catch return null;
            p.pos += 1;
        }
        if (p.pos == start) return null; // no digits consumed
        return v;
    }

    /// The fixed "0" node-id segment every print shape emits (this VM models
    /// exactly one local node) — a nonzero value is a malformed/foreign-node
    /// string, badarg (mirrors the E3.5 ETF `isLocalNode` reject).
    fn localNode(p: *Parser) ?void {
        const n = p.decimal() orelse return null;
        if (n != 0) return null;
        return {};
    }

    fn atEnd(p: *const Parser) bool {
        return p.pos == p.s.len;
    }
};

/// `list_to_pid("<0.N.S>")` — parses the `<0.Number.Serial>` shape
/// (`diag`'s pid print shape) back to a pid term. Liveness-agnostic (see the
/// section doc comment): a never-allocated `(N,S)` pair still builds.
pub fn list_to_pid(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try charListToBytes(m, args[0]);
    defer m.gpa.free(bytes);
    var p = Parser{ .s = bytes };
    if (!p.expectLit("<")) return error.Badarg;
    _ = p.localNode() orelse return error.Badarg;
    if (!p.expectLit(".")) return error.Badarg;
    const number = p.decimal() orelse return error.Badarg;
    if (!p.expectLit(".")) return error.Badarg;
    const serial = p.decimal() orelse return error.Badarg;
    if (!p.expectLit(">")) return error.Badarg;
    if (!p.atEnd()) return error.Badarg;
    return FinalTerms.pid(&m.ctx, number, serial) catch error.OutOfMemory;
}

/// `list_to_ref("#Ref<0.W1.W2.W3>")` — parses `diag`'s reference print
/// shape back to a reference term. Each word must fit `u32` (the E3.5
/// `refWords` domain) or the string is malformed -> badarg.
pub fn list_to_ref(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try charListToBytes(m, args[0]);
    defer m.gpa.free(bytes);
    var p = Parser{ .s = bytes };
    if (!p.expectLit("#Ref<")) return error.Badarg;
    _ = p.localNode() orelse return error.Badarg;
    var words: [3]u32 = undefined;
    for (0..3) |i| {
        if (!p.expectLit(".")) return error.Badarg;
        const w = p.decimal() orelse return error.Badarg;
        if (w > std.math.maxInt(u32)) return error.Badarg;
        words[i] = @intCast(w);
    }
    if (!p.expectLit(">")) return error.Badarg;
    if (!p.atEnd()) return error.Badarg;
    return FinalTerms.ref(&m.ctx, words) catch error.OutOfMemory;
}

/// `list_to_port("#Port<0.N>")` — parses `diag`'s port print shape back to
/// a port term.
pub fn list_to_port(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try charListToBytes(m, args[0]);
    defer m.gpa.free(bytes);
    var p = Parser{ .s = bytes };
    if (!p.expectLit("#Port<")) return error.Badarg;
    _ = p.localNode() orelse return error.Badarg;
    if (!p.expectLit(".")) return error.Badarg;
    const number = p.decimal() orelse return error.Badarg;
    if (!p.expectLit(">")) return error.Badarg;
    if (!p.atEnd()) return error.Badarg;
    return FinalTerms.port(&m.ctx, number) catch error.OutOfMemory;
}

// ============================================================================
// E2.5 LAWS
// ============================================================================

const AtomTable = ta.AtomTable;

fn expectEqlExact(m: *Machine, got: BifError!Term, want: Term) !void {
    const t = try got;
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, t, want));
}

fn strTerm(m: *Machine, s: []const u8) !Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = s.len;
    while (i > 0) {
        i -= 1;
        acc = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, s[i]), acc);
    }
    return acc;
}

fn termToUtf8Str(m: *Machine, gpa: std.mem.Allocator, l: Term) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var cur = l;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        try out.append(gpa, @intCast(FinalTerms.smallValOf(h)));
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    return out.toOwnedSlice(gpa);
}

test "LAW E2.5 atom<->list/binary round-trip and denote the atom name" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const ok = FinalTerms.atom(&m.ctx, try atoms.intern("ok"));
    const want = try strTerm(&m, "ok");
    try expectEqlExact(&m, atom_to_list(&m, &.{ok}), want);

    const roundtrip = try list_to_atom(&m, &.{try atom_to_list(&m, &.{ok})});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, roundtrip, ok));

    // list_to_existing_atom: found vs. absent.
    const found = try list_to_existing_atom(&m, &.{try strTerm(&m, "ok")});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, found, ok));
    try std.testing.expectError(error.Badarg, list_to_existing_atom(&m, &.{try strTerm(&m, "definitely_not_interned_yet")}));

    // atom_to_binary/1 (utf8 default) denotes the raw name bytes.
    const bin = try atom_to_binary_1(&m, &.{ok});
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, bin), "ok"));
    const back = try binary_to_atom_1(&m, &.{bin});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, back, ok));

    // DIVERGENCE 716: atom_to_binary/1 + binary_to_atom/1 default to utf8 (NOT
    // latin1) — a MULTIBYTE atom pins the encoding. Atom names are stored as
    // utf8 here, so `café` is the 5-byte name <<…,195,169>>; atom_to_binary/1
    // returns those bytes verbatim and binary_to_atom/1 round-trips them
    // (byte-EQ vs OTP-30; a latin1 mutant would collapse é to the 1-byte 233).
    {
        const cafe = FinalTerms.atom(&m.ctx, try atoms.intern("caf\xc3\xa9")); // utf8 name bytes
        const ub = try atom_to_binary_1(&m, &.{cafe});
        try std.testing.expectEqualStrings("caf\xc3\xa9", FinalTerms.binBytes(&m.ctx, ub)); // utf8, 5 bytes
        const rt = try binary_to_atom_1(&m, &.{ub});
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, rt, cafe)); // decodes back to café
    }

    // Rejections.
    try std.testing.expectError(error.Badarg, atom_to_list(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    try std.testing.expectError(error.Badarg, list_to_atom(&m, &.{FinalTerms.int(&m.ctx, 1)}));
}

test "LAW E2.5 integer<->list/binary round-trip across bases; denotation at base 16" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // Worked denotation: integer_to_list(255,16) == "FF"; list_to_integer("FF",16) == 255.
    const ff_list = try integer_to_list_2(&m, &.{ FinalTerms.int(&m.ctx, 255), FinalTerms.int(&m.ctx, 16) });
    try expectEqlExact(&m, ff_list, try strTerm(&m, "FF"));
    try expectEqlExact(&m, list_to_integer_2(&m, &.{ try strTerm(&m, "FF"), FinalTerms.int(&m.ctx, 16) }), FinalTerms.int(&m.ctx, 255));

    var prng = std.Random.DefaultPrng.init(0xC04F);
    const random = prng.random();
    for (0..200) |_| {
        const n: i64 = random.int(i32);
        const base: u8 = 2 + random.uintLessThan(u8, 35);
        const lst = try integer_to_list_2(&m, &.{ FinalTerms.int(&m.ctx, n), FinalTerms.int(&m.ctx, base) });
        const back = try list_to_integer_2(&m, &.{ lst, FinalTerms.int(&m.ctx, base) });
        try expectEqlExact(&m, back, FinalTerms.int(&m.ctx, n));

        const bin = try integer_to_binary_2(&m, &.{ FinalTerms.int(&m.ctx, n), FinalTerms.int(&m.ctx, base) });
        const back_b = try binary_to_integer_2(&m, &.{ bin, FinalTerms.int(&m.ctx, base) });
        try expectEqlExact(&m, back_b, FinalTerms.int(&m.ctx, n));
    }

    // base-10 default forms agree with base-10 explicit forms.
    const l10 = try integer_to_list_1(&m, &.{FinalTerms.int(&m.ctx, -42)});
    try expectEqlExact(&m, l10, try strTerm(&m, "-42"));

    // Rejections: bad base, malformed digits, non-integer.
    try std.testing.expectError(error.Badarg, integer_to_list_2(&m, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 1) }));
    try std.testing.expectError(error.Badarg, list_to_integer_1(&m, &.{try strTerm(&m, "12x")}));
    try std.testing.expectError(error.Badarg, list_to_integer_1(&m, &.{try strTerm(&m, "")}));
}

test "LAW gap-int-to-base-bignum (DIVERGENCE 687): integer_to_list/binary of a RUNTIME BIGNUM in any base — was badarith (the shared needSmallI128 path rejects bignums; only erlc constant-folding a LITERAL masked it)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // 2^128 (limbs {0,0,1}, little-endian u64) — beyond i128, a genuine bignum.
    const big = try FinalTerms.intFromLimbs(&m.ctx, true, &.{ 0, 0, 1 });
    try std.testing.expect(FinalTerms.repIsBig(&m.ctx, big));
    const dec = "340282366920938463463374607431768211456"; // 2^128 base 10
    const hex = "1" ++ ("0" ** 32); // 2^128 base 16 = 1 followed by 32 zeros (UPPERCASE alphabet)

    // base 10 (both the /2 explicit and the /1 default form)
    try expectEqlExact(&m, try integer_to_list_2(&m, &.{ big, FinalTerms.int(&m.ctx, 10) }), try strTerm(&m, dec));
    try expectEqlExact(&m, try integer_to_list_1(&m, &.{big}), try strTerm(&m, dec));
    // base 16, list AND binary
    try expectEqlExact(&m, try integer_to_list_2(&m, &.{ big, FinalTerms.int(&m.ctx, 16) }), try strTerm(&m, hex));
    try expectEqlExact(&m, try integer_to_binary_2(&m, &.{ big, FinalTerms.int(&m.ctx, 16) }), try FinalTerms.binary(&m.ctx, hex));
    try expectEqlExact(&m, try integer_to_binary_1(&m, &.{big}), try FinalTerms.binary(&m.ctx, dec));
    // a NEGATIVE bignum keeps the leading '-' (the sign flows from the term)
    const nbig = try FinalTerms.intFromLimbs(&m.ctx, false, &.{ 0, 0, 1 });
    try expectEqlExact(&m, try integer_to_list_2(&m, &.{ nbig, FinalTerms.int(&m.ctx, 16) }), try strTerm(&m, "-" ++ hex));
}

test "LAW gap-cowboy-serve binary_to_integer on a byte-aligned BITSTRING binary (the `<< _, Rest/bits >>` tail-bind idiom cowboy's parse_host uses on a Host `:port`): the digits are read from the CORRECT ceil(bit_len/8)-byte window, not an over-read — so `binary_to_integer(<<\"8099\">>-as-bitstring) == 8099`, byte-EQ with the flat-binary form (DIVERGENCE 646)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // A byte-aligned bitstring "8099" — the exact term shape a `Rest/bits` tail
    // binds (SUBTAG_BITSTRING, bit_len 32), distinct from a flat SUBTAG_BINARY.
    const bs = try FinalTerms.bitstring(&m.ctx, "8099", 32);
    try expectEqlExact(&m, try binary_to_integer_1(&m, &.{bs}), FinalTerms.int(&m.ctx, 8099));
    // /2 (explicit base) over the same bitstring carrier.
    const hexbs = try FinalTerms.bitstring(&m.ctx, "1F", 16);
    try expectEqlExact(&m, try binary_to_integer_2(&m, &.{ hexbs, FinalTerms.int(&m.ctx, 16) }), FinalTerms.int(&m.ctx, 31));
    // EQ to the flat-binary twin (the read is representation-independent).
    const flat = try FinalTerms.binary(&m.ctx, "8099");
    try expectEqlExact(&m, try binary_to_integer_1(&m, &.{flat}), try binary_to_integer_1(&m, &.{bs}));
    // a non-digit bitstring still rejects cleanly (badarg, never a heap over-read).
    const bad = try FinalTerms.bitstring(&m.ctx, "8x", 16);
    try std.testing.expectError(error.Badarg, binary_to_integer_1(&m, &.{bad}));
}

// LAW E24-T9 — the DARK base-conversion edge/rejection branches of `digitsToInt`
// + `needBase`, correlated to OTP-30 `erts_internal:list_to_integer/2`
// (`big.c:c2int_is_valid_char` @3967 / `bif.c` `erts_internal_list_to_integer_2`
// @4160). The E2.5 round-trip law above covers the HAPPY digit-agreement path;
// this law covers the branches a round-trip can never reach: a valid character
// that is out of range FOR THE BASE (distinct from an invalid character), the
// case-insensitive letter-digit arm, the leading `+`/`-` sign arms, a sign with
// no digits, and the `needBase` out-of-range/non-integer base rejection — driven
// by the exact vectors in OTP's `list_to_integer/2` doc-comment.
//
// OTP CORRELATION. `c2int_is_valid_char(ch, base)`: for base ≤ 10 only
// `'0'..'0'+base`; for base > 10 also `'A'..'A'+base-10` / `'a'..'a'+base-10`
// (case-insensitive). The VM SPLITS this into `digitVal(c) orelse reject`
// (is-a-digit) + `if (d >= base) reject` (in-range-for-base) — provably the same
// predicate. `needBase` mirrors the `2..36` `Base` spec (out-of-range/non-integer
// → badarg). The whole string must be consumed (OTP's `/2` wrapper accepts only
// `{Int,[]}`), so any trailing/interior invalid char is badarg.
//
// Mutants MUTATION_LOG e24-t9 m1 (`d >= base` → `d > base`, admitting the digit
// == base) / m2 (`needBase` upper bound `36` → `37`, admitting base 37).
test "LAW DIVERGENCE-675 erts_internal:list_to_integer/2 is LENIENT: {Int,Rest} prefix parse | no_integer | big; strict erlang:list_to_integer stays bare-int" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const li = struct {
        fn f(mm: *Machine, s: []const u8, base: i64) BifError!Term {
            return erts_internal_list_to_integer_2(mm, &.{ try strTerm(mm, s), FinalTerms.int(&mm.ctx, base) });
        }
    }.f;
    const int_ = struct {
        fn f(mm: *Machine, v: i64) Term {
            return FinalTerms.int(&mm.ctx, v);
        }
    }.f;
    // {Int, Rest}: whole-digit → {N, []}; trailing → {N, Rest}; out-of-range-for-base stops.
    try expectEqlExact(&m, li(&m, "42", 10), try FinalTerms.tuple(&m.ctx, &.{ int_(&m, 42), FinalTerms.nil(&m.ctx) }));
    try expectEqlExact(&m, li(&m, "12x", 10), try FinalTerms.tuple(&m.ctx, &.{ int_(&m, 12), try strTerm(&m, "x") }));
    try expectEqlExact(&m, li(&m, "-3FF", 16), try FinalTerms.tuple(&m.ctx, &.{ int_(&m, -1023), FinalTerms.nil(&m.ctx) }));
    try expectEqlExact(&m, li(&m, "+7", 10), try FinalTerms.tuple(&m.ctx, &.{ int_(&m, 7), FinalTerms.nil(&m.ctx) }));
    try expectEqlExact(&m, li(&m, "102", 2), try FinalTerms.tuple(&m.ctx, &.{ int_(&m, 2), try strTerm(&m, "2") })); // '2' out of range for base 2 → parses "10"=2
    // a NON-alphanumeric terminator (digitVal→null, the `orelse break` path — distinct
    // from the d>=base out-of-range break): "42 abc" → {42," abc"}, "7$x" → {7,"$x"}.
    try expectEqlExact(&m, li(&m, "42 abc", 10), try FinalTerms.tuple(&m.ctx, &.{ int_(&m, 42), try strTerm(&m, " abc") }));
    try expectEqlExact(&m, li(&m, "7$x", 10), try FinalTerms.tuple(&m.ctx, &.{ int_(&m, 7), try strTerm(&m, "$x") }));
    // no leading digit (empty / sign-only / non-digit) → the ATOM no_integer.
    const no_integer = FinalTerms.atom(&m.ctx, try atoms.intern("no_integer"));
    try expectEqlExact(&m, li(&m, "abc", 10), no_integer);
    try expectEqlExact(&m, li(&m, "", 10), no_integer);
    try expectEqlExact(&m, li(&m, "-", 10), no_integer);
    // overflow beyond the fast i128 path → the ATOM big.
    const big = FinalTerms.atom(&m.ctx, try atoms.intern("big"));
    var many: [400]u8 = undefined;
    @memset(&many, '9');
    try expectEqlExact(&m, li(&m, &many, 10), big);
    // CONTRAST: strict erlang:list_to_integer/2 (list_to_integer_2) stays BARE INT
    // and badargs on a trailing non-digit — the two must NOT be conflated.
    try expectEqlExact(&m, try list_to_integer_2(&m, &.{ try strTerm(&m, "42"), int_(&m, 10) }), int_(&m, 42));
    try std.testing.expectError(error.Badarg, list_to_integer_2(&m, &.{ try strTerm(&m, "12x"), int_(&m, 10) }));
}

test "LAW E24-T9 base-conversion edge/rejection branches match OTP-30 list_to_integer/2 (digit>=base, case, sign, base range)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const i = struct {
        fn f(mm: *Machine, v: i64) Term {
            return FinalTerms.int(&mm.ctx, v);
        }
    }.f;
    // list_to_integer_2 over a string + base.
    const l2i = struct {
        fn f(mm: *Machine, s: []const u8, base: i64) BifError!Term {
            return list_to_integer_2(mm, &.{ try strTerm(mm, s), FinalTerms.int(&mm.ctx, base) });
        }
    }.f;

    // (1) OTP doc vectors — the exact examples from erlang.erl list_to_integer/2.
    try expectEqlExact(&m, l2i(&m, "3FF", 16), i(&m, 1023)); // example 1
    try expectEqlExact(&m, l2i(&m, "+3FF", 16), i(&m, 1023)); // example 2: leading '+'
    try expectEqlExact(&m, l2i(&m, "3ff", 16), i(&m, 1023)); // example 3: lowercase == uppercase
    try expectEqlExact(&m, l2i(&m, "-3FF", 16), i(&m, -1023)); // example 4: leading '-'
    try expectEqlExact(&m, l2i(&m, "Base36IsFun", 36), i(&m, 41313437507787071)); // example 5: base 36
    // example 6: "102" in base 2 — a VALID char '2' that is OUT OF RANGE for base 2.
    try std.testing.expectError(error.Badarg, l2i(&m, "102", 2));

    // (2) digit == base and digit > base rejections across bases (the `d >= base`
    //     branch — a valid char that the base does not admit; NOT an invalid char).
    try std.testing.expectError(error.Badarg, l2i(&m, "8", 8)); // '8' not a base-8 digit
    try std.testing.expectError(error.Badarg, l2i(&m, "G", 16)); // 'G'==16 not a base-16 digit
    try std.testing.expectError(error.Badarg, l2i(&m, "a", 10)); // letter in a ≤10 base
    // boundary: the largest admitted digit of each base IS accepted.
    try expectEqlExact(&m, l2i(&m, "7", 8), i(&m, 7));
    try expectEqlExact(&m, l2i(&m, "F", 16), i(&m, 15));
    try expectEqlExact(&m, l2i(&m, "Z", 36), i(&m, 35));

    // (3) sign-with-no-digits → badarg (the `i >= bytes.len` branch).
    try std.testing.expectError(error.Badarg, l2i(&m, "+", 10));
    try std.testing.expectError(error.Badarg, l2i(&m, "-", 16));

    // (4) needBase out-of-range / non-integer base rejection (2..36), across the
    //     whole conversion family that routes through `needBase`.
    try std.testing.expectError(error.Badarg, l2i(&m, "5", 1)); // base < 2
    try std.testing.expectError(error.Badarg, l2i(&m, "5", 37)); // base > 36
    try std.testing.expectError(error.Badarg, list_to_integer_2(&m, &.{ try strTerm(&m, "5"), try strTerm(&m, "10") })); // non-integer base
    try std.testing.expectError(error.Badarg, integer_to_list_2(&m, &.{ i(&m, 5), i(&m, 37) }));
    try std.testing.expectError(error.Badarg, integer_to_binary_2(&m, &.{ i(&m, 5), i(&m, 1) }));

    // (5) the base guard also gates the binary form (shared `needBase`): a VALID
    //     binary numeral with an out-of-range base is badarg, never a wrong value.
    const bin16 = try integer_to_binary_2(&m, &.{ i(&m, 255), i(&m, 16) }); // <<"FF">>
    try std.testing.expectError(error.Badarg, binary_to_integer_2(&m, &.{ bin16, i(&m, 37) }));
}

// LAW E24-T10 — `binary_to_list/3`'s 1-based INCLUSIVE range validation, matching
// OTP-30 `binary.c:binary_to_list_3` (@354, range guard @377). The E3.2 test drove
// ONE happy `(2,3)` slice; the boundary + every rejection arm stayed dark. This law
// pins BEAM's odd convention (`Stop` is the LAST INCLUDED byte, 1-based — unlike
// 0-based `binary_part`) and the full guard.
//
// OTP CORRELATION. OTP rejects iff
//   `start < 1 || start > size || stop < 1 || stop > size || stop < start`.
// The VM factors it as `start < 1 || stop < start || stop > len`; the two dropped
// OTP terms are covered TRANSITIVELY (`start > size` ⟹ `stop ≥ start > len` or
// `stop < start`; `stop < 1` ⟹ `stop < start` since `start ≥ 1`) — provably the
// same predicate. An empty binary always badargs on /3 (no `start ≥ 1` fits size
// 0), matching OTP where `start > size` fires before its `size==0 → NIL`. An
// unaligned bitstring is badarg (VM `repIsBinary` byte-aligned gate ≡ OTP
// `TAIL_BITS(size) != 0 → BADARG`).
//
// Mutants MUTATION_LOG e24-t10 m1 (`start < 1` → `start < 0`, admitting start 0 —
// a 0-based off-by-one) / m2 (`stop > len` → `stop >= len`, rejecting the last
// byte — an inclusive/exclusive off-by-one).
test "LAW E24-T10 binary_to_list/3 1-based inclusive range validation matches OTP-30 binary.c binary_to_list_3" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const i = struct {
        fn f(mm: *Machine, v: i64) Term {
            return FinalTerms.int(&mm.ctx, v);
        }
    }.f;
    const bin = try FinalTerms.binary(&m.ctx, &.{ 10, 20, 30, 40, 50 }); // len 5
    const b2l = struct {
        fn f(mm: *Machine, bb: Term, s: i64, e: i64) BifError!Term {
            return binary_to_list_3(mm, &.{ bb, FinalTerms.int(&mm.ctx, s), FinalTerms.int(&mm.ctx, e) });
        }
    }.f;

    // (1) Happy boundaries — 1-based, INCLUSIVE stop.
    try expectEqlExact(&m, b2l(&m, bin, 1, 5), try strTerm(&m, &.{ 10, 20, 30, 40, 50 })); // whole
    try expectEqlExact(&m, b2l(&m, bin, 1, 1), try strTerm(&m, &.{10})); // first byte only
    try expectEqlExact(&m, b2l(&m, bin, 5, 5), try strTerm(&m, &.{50})); // LAST byte (inclusive)
    try expectEqlExact(&m, b2l(&m, bin, 3, 3), try strTerm(&m, &.{30})); // single mid byte
    try expectEqlExact(&m, b2l(&m, bin, 2, 4), try strTerm(&m, &.{ 20, 30, 40 })); // mid run

    // (2) Rejections — the guard arms (each an off-by-one trap).
    try std.testing.expectError(error.Badarg, b2l(&m, bin, 0, 3)); // start < 1 (0-based mistake)
    try std.testing.expectError(error.Badarg, b2l(&m, bin, -1, 3)); // start < 1 (negative)
    try std.testing.expectError(error.Badarg, b2l(&m, bin, 1, 6)); // stop > len
    try std.testing.expectError(error.Badarg, b2l(&m, bin, 6, 6)); // start > len (transitive)
    try std.testing.expectError(error.Badarg, b2l(&m, bin, 3, 2)); // stop < start
    try std.testing.expectError(error.Badarg, b2l(&m, bin, 1, 0)); // stop < 1 (via stop < start)

    // (3) Empty binary: no valid /3 range exists → always badarg.
    const empty = try FinalTerms.binary(&m.ctx, &.{});
    try std.testing.expectError(error.Badarg, b2l(&m, empty, 1, 1));
    try std.testing.expectError(error.Badarg, b2l(&m, empty, 1, 0));

    // (4) Non-binary / non-integer index → badarg (argument-shape guards).
    try std.testing.expectError(error.Badarg, b2l(&m, i(&m, 7), 1, 1)); // non-binary subject
    try std.testing.expectError(error.Badarg, binary_to_list_3(&m, &.{ bin, try strTerm(&m, "x"), i(&m, 3) })); // non-int start
}

// LAW E24-T11 — the DARK iodata-flattening branches of `iolistToBinary` /
// `ioAccList` / `ioAccElem`, correlated to OTP-30 `iolist_to_binary/1` +
// `list_to_binary/1` (the `iodata()`/`iolist()` grammar). The E2.5 test drove ONE
// happy nested flatten; the IMPROPER-tail arms, the byte-range / non-byte / bignum /
// atom / unaligned-bitstring element rejections, and the `iolist_to_binary`-accepts-
// a-bare-binary vs `list_to_binary`-rejects-it distinction all stayed dark.
//
// OTP CORRELATION. `iodata() = iolist() | binary()`; `iolist()` is a maybe-improper
// list whose elements are `byte() (0..255) | binary() | iolist()` with an OPTIONAL
// trailing `binary()` (so `[65,66|<<"CD">>]` is legal, `[65|66]` is not). A
// bitstring that is not byte-aligned, a non-byte integer, a bignum, or an atom in an
// element position is `badarg`. `list_to_binary/1` requires a LIST at top level (a
// bare binary is `badarg`), whereas `iolist_to_binary/1` also accepts a bare binary
// — the exact `k != cons && k != nil` gate in the conv wrapper vs the `repIsBinary`
// top arm in `iolistToBinary`.
//
// Mutants MUTATION_LOG e24-t11 m1 (`ioAccElem` byte guard `v > 255` → `v > 256`,
// admitting the non-byte 256) / m2 (`ioAccList` improper-binary-tail arm dropped —
// a legal `[..|<<..>>]` tail becomes badarg).
test "LAW E24-T11 iolist/list_to_binary iodata grammar — improper tail, byte range, bad element, bare-binary distinction (OTP-30)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const i = struct {
        fn f(mm: *Machine, v: i64) Term {
            return FinalTerms.int(&mm.ctx, v);
        }
    }.f;
    const cons = FinalTerms.cons;
    const nil = FinalTerms.nil(&m.ctx);
    const l2b = struct {
        fn f(mm: *Machine, t: Term) BifError!Term {
            return list_to_binary(mm, &.{t});
        }
    }.f;
    const io2b = struct {
        fn f(mm: *Machine, t: Term) BifError!Term {
            return iolist_to_binary(mm, &.{t});
        }
    }.f;
    const eqBytes = struct {
        fn f(mm: *Machine, got: BifError!Term, want: []const u8) !void {
            const t = try got;
            try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&mm.ctx, t), want));
        }
    }.f;

    // (1) Empty list → empty binary; deep nesting flattens in order.
    try eqBytes(&m, l2b(&m, nil), "");
    // [[[65]], [66, [67]]] → "ABC"
    const deep = try cons(&m.ctx, try cons(&m.ctx, try cons(&m.ctx, i(&m, 65), nil), nil), try cons(&m.ctx, try cons(&m.ctx, i(&m, 66), try cons(&m.ctx, try cons(&m.ctx, i(&m, 67), nil), nil)), nil));
    try eqBytes(&m, l2b(&m, deep), "ABC");

    // (2) IMPROPER BINARY TAIL is legal iodata: [65, 66 | <<"CD">>] → "ABCD".
    const cd = try FinalTerms.binary(&m.ctx, "CD");
    const improper_ok = try cons(&m.ctx, i(&m, 65), try cons(&m.ctx, i(&m, 66), cd));
    try eqBytes(&m, l2b(&m, improper_ok), "ABCD");
    try eqBytes(&m, io2b(&m, improper_ok), "ABCD");

    // (3) IMPROPER NON-BINARY TAIL is badarg: [65 | 66].
    try std.testing.expectError(error.Badarg, l2b(&m, try cons(&m.ctx, i(&m, 65), i(&m, 66))));

    // (4) Byte range: 0 and 255 ok; 256 and -1 badarg.
    try eqBytes(&m, l2b(&m, try cons(&m.ctx, i(&m, 0), try cons(&m.ctx, i(&m, 255), nil))), &.{ 0, 255 });
    try std.testing.expectError(error.Badarg, l2b(&m, try cons(&m.ctx, i(&m, 256), nil)));
    try std.testing.expectError(error.Badarg, l2b(&m, try cons(&m.ctx, i(&m, -1), nil)));

    // (5) Non-byte element kinds are badarg: a bignum, an atom, an UNALIGNED bitstring.
    const big = try FinalTerms.intFromI128(&m.ctx, @as(i128, 1) << 70); // a bignum, not a byte
    try std.testing.expectError(error.Badarg, l2b(&m, try cons(&m.ctx, big, nil)));
    const an_atom = FinalTerms.atom(&m.ctx, try atoms.intern("x"));
    try std.testing.expectError(error.Badarg, l2b(&m, try cons(&m.ctx, an_atom, nil)));
    const bits3 = try FinalTerms.bitstring(&m.ctx, &.{0b011_00000}, 3); // <<3:3>>, not byte-aligned
    try std.testing.expectError(error.Badarg, l2b(&m, try cons(&m.ctx, bits3, nil)));

    // (6) The bare-binary DISTINCTION: iolist_to_binary accepts a top-level binary;
    //     list_to_binary requires a LIST (a bare binary is badarg).
    const x = try FinalTerms.binary(&m.ctx, "x");
    try eqBytes(&m, io2b(&m, x), "x"); // iolist_to_binary(<<"x">>) == <<"x">>
    try std.testing.expectError(error.Badarg, l2b(&m, x)); // list_to_binary(<<"x">>) badarg
    // a byte-aligned binary IS a valid element (not just tail): [<<"ab">>, 67] → "abC".
    const ab = try FinalTerms.binary(&m.ctx, "ab");
    try eqBytes(&m, l2b(&m, try cons(&m.ctx, ab, try cons(&m.ctx, i(&m, 67), nil))), "abC");
}

test "LAW E6.6 float<->binary: round-trip + fixed-decimals byte form + rejection" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // ROUND-TRIP: binary_to_float(float_to_binary(F)) == F (finite F) — the LAW
    // this module holds (the default text is shortest round-trip, not asserted).
    var prng = std.Random.DefaultPrng.init(0xF10A7);
    const random = prng.random();
    for (0..200) |_| {
        const f = @as(f64, @floatFromInt(random.int(i32))) / 1024.0;
        const bin = try float_to_binary_1(&m, &.{FinalTerms.float(&m.ctx, f)});
        const back = try binary_to_float_1(&m, &.{bin});
        try std.testing.expectEqual(f, FinalTerms.floatValOf(&m.ctx, back));
    }

    // FIXED DECIMALS: float_to_binary(2.5, [{decimals,2}]) == <<"2.50">> — a
    // byte-stable form (the mutant-2 target: dropping the option -> wrong bytes).
    const opt = try FinalTerms.cons(&m.ctx, try FinalTerms.tuple(&m.ctx, &.{
        FinalTerms.atom(&m.ctx, try atoms.intern("decimals")),
        FinalTerms.int(&m.ctx, 2),
    }), FinalTerms.nil(&m.ctx));
    const fixed = try float_to_binary_2(&m, &.{ FinalTerms.float(&m.ctx, 2.5), opt });
    try std.testing.expectEqualStrings("2.50", FinalTerms.binBytes(&m.ctx, fixed));

    // binary_to_float parses the erts default 20-digit scientific form too.
    const erts_form = try FinalTerms.binary(&m.ctx, "2.50000000000000000000e+00");
    try std.testing.expectEqual(@as(f64, 2.5), FinalTerms.floatValOf(&m.ctx, try binary_to_float_1(&m, &.{erts_form})));

    // rejection: a point-less binary and a non-binary are badarg.
    try std.testing.expectError(error.Badarg, binary_to_float_1(&m, &.{try FinalTerms.binary(&m.ctx, "42")}));
    try std.testing.expectError(error.Badarg, binary_to_float_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    try std.testing.expectError(error.Badarg, float_to_binary_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
}

test "LAW gap-float-to-list-opts (DIVERGENCE 708): float_to_list/2 {scientific,D}+compact byte-EQ OTP-30" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // little builders for option lists over the machine heap.
    const H = struct {
        fn tagOpt(mm: *Machine, name: []const u8, d: i64) !Term {
            return FinalTerms.tuple(&mm.ctx, &.{
                FinalTerms.atom(&mm.ctx, try mm.ctx.atoms.intern(name)),
                FinalTerms.int(&mm.ctx, d),
            });
        }
        // format float_to_list(F, Opts) to a Zig string (asserts no error).
        fn fmt(mm: *Machine, f: f64, opts: Term) ![]u8 {
            const lst = try float_to_list_2(mm, &.{ FinalTerms.float(&mm.ctx, f), opts });
            return charListToBytes(mm, lst);
        }
    };

    // {scientific, D}: sign-always, ≥2-digit exponent (byte-EQ OTP-30).
    {
        const o = try FinalTerms.cons(&m.ctx, try H.tagOpt(&m, "scientific", 3), FinalTerms.nil(&m.ctx));
        const s = try H.fmt(&m, 3.14159, o);
        defer gpa.free(s);
        try std.testing.expectEqualStrings("3.142e+00", s);
    }
    {
        const o = try FinalTerms.cons(&m.ctx, try H.tagOpt(&m, "scientific", 0), FinalTerms.nil(&m.ctx));
        const s = try H.fmt(&m, 1234.5, o);
        defer gpa.free(s);
        try std.testing.expectEqualStrings("1e+03", s);
    }
    {
        const o = try FinalTerms.cons(&m.ctx, try H.tagOpt(&m, "scientific", 2), FinalTerms.nil(&m.ctx));
        const s = try H.fmt(&m, -0.001, o);
        defer gpa.free(s);
        try std.testing.expectEqualStrings("-1.00e-03", s);
    }
    {
        const o = try FinalTerms.cons(&m.ctx, try H.tagOpt(&m, "scientific", 4), FinalTerms.nil(&m.ctx));
        const s = try H.fmt(&m, 1.0e120, o);
        defer gpa.free(s);
        try std.testing.expectEqualStrings("1.0000e+120", s); // 3-digit exponent kept
    }

    // {decimals, D} + compact: trims trailing fraction zeros, keeps ≥1 (byte-EQ).
    {
        const o = try FinalTerms.cons(&m.ctx, try H.tagOpt(&m, "decimals", 4), try FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, try atoms.intern("compact")), FinalTerms.nil(&m.ctx)));
        const s = try H.fmt(&m, 1.0, o);
        defer gpa.free(s);
        try std.testing.expectEqualStrings("1.0", s);
    }
    {
        const o = try FinalTerms.cons(&m.ctx, try H.tagOpt(&m, "decimals", 6), try FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, try atoms.intern("compact")), FinalTerms.nil(&m.ctx)));
        const s = try H.fmt(&m, 100.0, o);
        defer gpa.free(s);
        try std.testing.expectEqualStrings("100.0", s);
    }

    // plain {decimals, D} still exact (regression guard on the shared path).
    {
        const o = try FinalTerms.cons(&m.ctx, try H.tagOpt(&m, "decimals", 4), FinalTerms.nil(&m.ctx));
        const s = try H.fmt(&m, 1.0, o);
        defer gpa.free(s);
        try std.testing.expectEqualStrings("1.0000", s);
    }

    // out-of-scope corners → badarg (erts falls to its 20-digit default here,
    // which this module deliberately does not reproduce).
    const compact_only = try FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, try atoms.intern("compact")), FinalTerms.nil(&m.ctx));
    try std.testing.expectError(error.Badarg, float_to_list_2(&m, &.{ FinalTerms.float(&m.ctx, 1.5), compact_only }));
    try std.testing.expectError(error.Badarg, float_to_list_2(&m, &.{ FinalTerms.float(&m.ctx, 1.5), FinalTerms.nil(&m.ctx) }));
    // {decimals,_}+{scientific,_} mix and out-of-range counts → badarg.
    const mix = try FinalTerms.cons(&m.ctx, try H.tagOpt(&m, "decimals", 2), try FinalTerms.cons(&m.ctx, try H.tagOpt(&m, "scientific", 2), FinalTerms.nil(&m.ctx)));
    try std.testing.expectError(error.Badarg, float_to_list_2(&m, &.{ FinalTerms.float(&m.ctx, 1.5), mix }));
    const neg = try FinalTerms.cons(&m.ctx, try H.tagOpt(&m, "decimals", -1), FinalTerms.nil(&m.ctx));
    try std.testing.expectError(error.Badarg, float_to_list_2(&m, &.{ FinalTerms.float(&m.ctx, 1.5), neg }));

    // float_to_binary/2 shares the formatter — {scientific,D} as a binary.
    {
        const o = try FinalTerms.cons(&m.ctx, try H.tagOpt(&m, "scientific", 3), FinalTerms.nil(&m.ctx));
        const b = try float_to_binary_2(&m, &.{ FinalTerms.float(&m.ctx, 3.14159), o });
        try std.testing.expectEqualStrings("3.142e+00", FinalTerms.binBytes(&m.ctx, b));
    }
}

test "LAW gap-float-to-list-short (DIVERGENCE 713): float_to_list/2 [short] = the shorter of shortest-decimal/shortest-scientific (tie→decimal); byte-EQ OTP-30" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const shortOpt = try FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, try atoms.intern("short")), FinalTerms.nil(&m.ctx));
    const S = struct {
        fn go(mm: *Machine, opt: Term, f: f64) ![]u8 {
            const lst = try float_to_list_2(mm, &.{ FinalTerms.float(&mm.ctx, f), opt });
            return charListToBytes(mm, lst);
        }
    };

    // byte-EQ OTP-30 [short] across the decimal/scientific boundary.
    const cases = [_]struct { f: f64, want: []const u8 }{
        .{ .f = 3.14, .want = "3.14" }, // decimal shorter
        .{ .f = 1.0, .want = "1.0" },
        .{ .f = 0.1, .want = "0.1" },
        .{ .f = -2.5, .want = "-2.5" },
        .{ .f = 0.0, .want = "0.0" },
        .{ .f = 0.0001, .want = "0.0001" }, // tie → decimal
        .{ .f = 100000.0, .want = "1.0e5" }, // scientific shorter (+ .0 mantissa)
        .{ .f = 1.5e10, .want = "1.5e10" },
        .{ .f = 1.23e-4, .want = "1.23e-4" },
        .{ .f = 1.5e-5, .want = "1.5e-5" },
        .{ .f = 1.0e120, .want = "1.0e120" }, // huge → scientific, not the 121-digit expansion
    };
    for (cases) |c| {
        const s = try S.go(&m, shortOpt, c.f);
        defer gpa.free(s);
        try std.testing.expectEqualStrings(c.want, s);
    }

    // decimals/scientific OVERRIDE short (erts precedence): [short,{decimals,4}] → fixed.
    {
        const o = try FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, try atoms.intern("short")), try FinalTerms.cons(&m.ctx, try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("decimals")), FinalTerms.int(&m.ctx, 4) }), FinalTerms.nil(&m.ctx)));
        const s = try S.go(&m, o, 1.0);
        defer gpa.free(s);
        try std.testing.expectEqualStrings("1.0000", s);
    }
    // float_to_binary/2 shares the [short] formatter.
    {
        const b = try float_to_binary_2(&m, &.{ FinalTerms.float(&m.ctx, 100000.0), shortOpt });
        try std.testing.expectEqualStrings("1.0e5", FinalTerms.binBytes(&m.ctx, b));
    }
}

test "LAW E2.5 list<->binary flattens iodata; tuple<->list denotes tuple elements" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // list_to_binary over a nested iolist (list+binary+byte-int mix).
    const inner_bin = try FinalTerms.binary(&m.ctx, "cd");
    const nested = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 'a'), try FinalTerms.cons(&m.ctx, try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 'b'), FinalTerms.nil(&m.ctx)), try FinalTerms.cons(&m.ctx, inner_bin, FinalTerms.nil(&m.ctx))));
    const flat = try list_to_binary(&m, &.{nested});
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, flat), "abcd"));
    const flat2 = try iolist_to_binary(&m, &.{nested});
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, flat2), "abcd"));

    // binary_to_list round-trips through list_to_binary.
    const back = try binary_to_list_1(&m, &.{flat});
    try expectEqlExact(&m, back, try strTerm(&m, "abcd"));
    // binary_to_list/3: 1-based INCLUSIVE range [2,3] of "abcd" -> "bc".
    const mid = try binary_to_list_3(&m, &.{ flat, FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 3) });
    try expectEqlExact(&m, mid, try strTerm(&m, "bc"));

    // tuple_to_list / list_to_tuple round-trip and denote element order.
    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const tup = try FinalTerms.tuple(&m.ctx, &.{ a, b });
    const lst = try tuple_to_list(&m, &.{tup});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, lst), a));
    const tup2 = try list_to_tuple(&m, &.{lst});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, tup2, tup) or FinalTerms.eql(&m.ctx, tup2, tup));

    try std.testing.expectError(error.Badarg, list_to_binary(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    try std.testing.expectError(error.Badarg, tuple_to_list(&m, &.{a}));
}

test "LAW E3.2: bitstring_to_list denotes BEAM's last-ELEMENT shape, list_to_bitstring is its inverse" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // DENOTATION: bitstring_to_list(<<1,2,3:3>>) == [1,2,<<3:3>>] — a proper
    // 3-ELEMENT list; the sub-byte trailing segment is the LAST ELEMENT
    // (lists may hold any term, including a bitstring), NOT an improper tail.
    const three_3bits = try FinalTerms.bitstring(&m.ctx, &.{0b011_00000}, 3);
    const bs123 = try FinalTerms.bitstring(&m.ctx, &.{ 1, 2, 0b011_00000 }, 8 + 8 + 3);
    const got = try bitstring_to_list(&m, &.{bs123});
    // got == [1, 2, <<3:3>>]  (proper list, tail [])
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, got) == .cons);
    try expectEqlExact(&m, FinalTerms.listHead(&m.ctx, got), FinalTerms.int(&m.ctx, 1));
    const t1 = FinalTerms.listTail(&m.ctx, got);
    try expectEqlExact(&m, FinalTerms.listHead(&m.ctx, t1), FinalTerms.int(&m.ctx, 2));
    const t2 = FinalTerms.listTail(&m.ctx, t1);
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, t2) == .cons); // still a PROPER list here
    try expectEqlExact(&m, FinalTerms.listHead(&m.ctx, t2), three_3bits);
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, FinalTerms.listTail(&m.ctx, t2)) == .nil); // proper: tail is []

    // An ALIGNED bitstring/true binary produces a plain proper list (tail
    // nil), matching binary_to_list/1 exactly.
    const aligned = try FinalTerms.bitstring(&m.ctx, "ab", 16);
    const aligned_list = try bitstring_to_list(&m, &.{aligned});
    try expectEqlExact(&m, aligned_list, try strTerm(&m, "ab"));

    // ROUND-TRIP: bitstring_to_list ∘ list_to_bitstring == id (unaligned).
    const rebuilt = try list_to_bitstring(&m, &.{got});
    try std.testing.expect(FinalTerms.eql(&m.ctx, rebuilt, bs123));

    // list_to_bitstring of a list of ALIGNED binaries == their binConcat.
    const bin_ab = try FinalTerms.binary(&m.ctx, "ab");
    const bin_cd = try FinalTerms.binary(&m.ctx, "cd");
    const iolist_bins = try FinalTerms.cons(&m.ctx, bin_ab, try FinalTerms.cons(&m.ctx, bin_cd, FinalTerms.nil(&m.ctx)));
    const concatenated = try list_to_bitstring(&m, &.{iolist_bins});
    const want_concat = try FinalTerms.binary(&m.ctx, "abcd");
    try std.testing.expect(FinalTerms.eql(&m.ctx, concatenated, want_concat));

    // NESTED lists flatten; a NESTED bitstring ELEMENT folds in bit-exact
    // (MUTANT 2's target — see accBitstringElem's doc comment).
    const nested_with_bits = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), try FinalTerms.cons(&m.ctx, try FinalTerms.cons(&m.ctx, three_3bits, FinalTerms.nil(&m.ctx)), FinalTerms.nil(&m.ctx)));
    const nested_built = try list_to_bitstring(&m, &.{nested_with_bits});
    const want_nested = try FinalTerms.bitstring(&m.ctx, &.{ 1, 0b011_00000 }, 8 + 3);
    try std.testing.expect(FinalTerms.eql(&m.ctx, nested_built, want_nested));

    // Rejections: non-byte-range element / non-list argument → badarg.
    try std.testing.expectError(error.Badarg, bitstring_to_list(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    try std.testing.expectError(error.Badarg, list_to_bitstring(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    const bad_elem = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 256), FinalTerms.nil(&m.ctx));
    try std.testing.expectError(error.Badarg, list_to_bitstring(&m, &.{bad_elem}));
}

test "LAW E3.2 seeded: bitstring_to_list ∘ list_to_bitstring == id over random unaligned bitstrings" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xB512E5);
    const random = prng.random();

    for (0..150) |iter| {
        var atoms = AtomTable.init(gpa);
        defer atoms.deinit();
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();

        var buf: [12]u8 = undefined;
        random.bytes(&buf);
        const bit_len = random.uintLessThan(usize, buf.len * 8 + 1);
        const bs = try FinalTerms.bitstring(&m.ctx, &buf, bit_len);

        const as_list = bitstring_to_list(&m, &.{bs}) catch |err| {
            std.debug.print("LAW FAILED: bitstring_to_list errored (seed=0xB512E5, iter={d}, bit_len={d}): {any}\n", .{ iter, bit_len, err });
            return err;
        };
        const rebuilt = list_to_bitstring(&m, &.{as_list}) catch |err| {
            std.debug.print("LAW FAILED: list_to_bitstring errored (seed=0xB512E5, iter={d}, bit_len={d}): {any}\n", .{ iter, bit_len, err });
            return err;
        };
        if (!FinalTerms.eql(&m.ctx, rebuilt, bs)) {
            std.debug.print("LAW FAILED: bitstring_to_list∘list_to_bitstring==id (seed=0xB512E5, iter={d}, bit_len={d})\n", .{ iter, bit_len });
            return error.LawViolated;
        }
    }
}

test "MUTANT 2 RED-demo (documented, not executed): dropping the trailing unaligned segment breaks the conversion round-trip" {
    // See MUTATION_LOG.md E3.2 mutant 2. Manually verified: if
    // `accBitstringElem`'s `k == .binary` arm (conv.zig) is deleted — i.e.
    // only `.cons`/byte-int elements are accepted, and a bitstring/binary
    // ELEMENT falls through to `error.Badarg` — then
    // `list_to_bitstring(bitstring_to_list(<<1,2,3:3>>))` (== `list_to_bitstring([1,
    // 2, <<3:3>>])`) fails with `Badarg` on the trailing `<<3:3>>` element
    // instead of recovering the original 19-bit value. The seeded
    // round-trip law above fails on the very first iteration whose
    // `bit_len % 8 != 0` (any unaligned draw).
}

test "LAW E3.2 re-verify: is_bitstring (type_test .bitstr) stays truthful over etf-decoded and list_to_bitstring-constructed bitstrings" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // etf-decoded: BIT_BINARY_EXT round-trip produces a bitstring whose
    // kind must still read as `.bitstr`-truthful (repIsBinary OR
    // repIsBitstring, per E1.3's `type_test` predicate — see
    // instr_algebra.zig's `.bitstr` arm).
    const original = try FinalTerms.bitstring(&m.ctx, &.{0b101_00000}, 3);
    var bytes = try etf.encode(gpa, &m.ctx, original);
    defer bytes.deinit(gpa);
    const decoded = try etf.decode(gpa, &m.ctx, bytes.items);
    try std.testing.expect(FinalTerms.repIsBitstring(&m.ctx, decoded) or FinalTerms.repIsBinary(&m.ctx, decoded));
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, decoded) == .binary); // the .bitstr type_test's own bucket

    // list_to_bitstring-constructed: same truthfulness.
    const one_elem = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), FinalTerms.nil(&m.ctx));
    const built = try list_to_bitstring(&m, &.{one_elem});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, built) == .binary);
    // built is ALIGNED (bit_len==8): repIsBinary is truthful too, matching
    // the byte-alignment homomorphism `is_binary`/`is_bitstring` share.
    try std.testing.expect(FinalTerms.repIsBinary(&m.ctx, built));
}

test "LAW E2.5 term_to_binary/binary_to_term denote etf.encode/decode (M9 round-trip reused)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("hello"));
    const tup = try FinalTerms.tuple(&m.ctx, &.{ a, FinalTerms.int(&m.ctx, 42) });

    // WORKED LAW: term_to_binary(t) == etf.encode(t) (byte-identical).
    var direct = try etf.encode(gpa, &m.ctx, tup);
    defer direct.deinit(gpa);
    const via_bif = try term_to_binary_1(&m, &.{tup});
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, via_bif), direct.items));

    // ROUND-TRIP: binary_to_term(term_to_binary(T)) denotes T.
    const back = try binary_to_term_1(&m, &.{via_bif});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, back, tup) or FinalTerms.eql(&m.ctx, back, tup));

    // /2 forms (options ignored) agree with /1.
    const via2 = try term_to_binary_2(&m, &.{ tup, FinalTerms.nil(&m.ctx) });
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, via2), direct.items));

    // Rejection: malformed binary -> badarg, never a panic.
    const bad = try FinalTerms.binary(&m.ctx, "\x83not-etf");
    try std.testing.expectError(error.Badarg, binary_to_term_1(&m, &.{bad}));
}

test "LAW E3.18: derivations agree with their base BIF (external_size, iolist_size, iolist_to_iovec, split_binary, binary_to_existing_atom)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("hello"));
    const tup = try FinalTerms.tuple(&m.ctx, &.{ a, FinalTerms.int(&m.ctx, 42) });

    // external_size(T) == byte_size(term_to_binary(T)) (the encoder's byte count).
    const ttb = try term_to_binary_1(&m, &.{tup});
    const want_sz: i64 = @intCast(FinalTerms.binSize(&m.ctx, ttb));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try external_size_1(&m, &.{tup}), FinalTerms.int(&m.ctx, want_sz)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try external_size_2(&m, &.{ tup, FinalTerms.nil(&m.ctx) }), FinalTerms.int(&m.ctx, want_sz)));

    // iolist_size(IoList) == byte_size(iolist_to_binary(IoList)).
    // IoList = [<<"ab">>, [67, <<"d">>], 69] flattens to "abCdE" (5 bytes).
    const ab = try FinalTerms.binary(&m.ctx, "ab");
    const d = try FinalTerms.binary(&m.ctx, "d");
    const inner = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 67), try FinalTerms.cons(&m.ctx, d, FinalTerms.nil(&m.ctx)));
    const iol = try FinalTerms.cons(&m.ctx, ab, try FinalTerms.cons(&m.ctx, inner, try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 69), FinalTerms.nil(&m.ctx))));
    const flat = try iolist_to_binary(&m, &.{iol});
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, flat), "abCdE"));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try iolist_size_1(&m, &.{iol}), FinalTerms.int(&m.ctx, 5)));

    // iolist_to_iovec INVARIANT: iolist_to_binary(iolist_to_iovec(X)) == iolist_to_binary(X).
    const iov = try iolist_to_iovec_1(&m, &.{iol});
    const iov_flat = try iolist_to_binary(&m, &.{iov});
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, iov_flat), "abCdE"));
    // Empty iolist -> [] (nil), never a spurious [<<>>].
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, try iolist_to_iovec_1(&m, &.{FinalTerms.nil(&m.ctx)})) == .nil);

    // split_binary(<<"abCdE">>, 2) == {<<"ab">>, <<"CdE">>}; concatenation identity.
    const sp = try split_binary_2(&m, &.{ flat, FinalTerms.int(&m.ctx, 2) });
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, sp) == .tuple and FinalTerms.tupleArity(&m.ctx, sp) == 2);
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, FinalTerms.tupleElem(&m.ctx, sp, 0)), "ab"));
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, FinalTerms.tupleElem(&m.ctx, sp, 1)), "CdE"));
    // Boundary + rejection.
    try std.testing.expect(std.mem.eql(u8, FinalTerms.binBytes(&m.ctx, FinalTerms.tupleElem(&m.ctx, try split_binary_2(&m, &.{ flat, FinalTerms.int(&m.ctx, 0) }), 1)), "abCdE"));
    try std.testing.expectError(error.Badarg, split_binary_2(&m, &.{ flat, FinalTerms.int(&m.ctx, 6) })); // out of range
    try std.testing.expectError(error.Badarg, split_binary_2(&m, &.{ a, FinalTerms.int(&m.ctx, 0) })); // non-binary

    // binary_to_existing_atom: an ALREADY-interned name resolves; an unseen name badargs.
    const hb = try FinalTerms.binary(&m.ctx, "hello"); // "hello" was interned above
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try binary_to_existing_atom_2(&m, &.{ hb, FinalTerms.atom(&m.ctx, try atoms.intern("utf8")) }), a));
    const nb = try FinalTerms.binary(&m.ctx, "never_interned_zzz");
    try std.testing.expectError(error.Badarg, binary_to_existing_atom_2(&m, &.{ nb, FinalTerms.atom(&m.ctx, try atoms.intern("utf8")) }));
}

test "LAW gap-app-boot-engine universaltime/0: a well-formed UTC {{Y,Mo,D},{H,Mi,S}} from the real clock (cowboy_clock:rfc1123 Date header)" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const ut = try universaltime_0(&m, &.{});
    // {{Y,Mo,D},{H,Mi,S}} — a 2-tuple of two 3-tuples, all small ints in range.
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, ut) == .tuple and FinalTerms.tupleArity(&m.ctx, ut) == 2);
    const date = FinalTerms.tupleElem(&m.ctx, ut, 0);
    const time = FinalTerms.tupleElem(&m.ctx, ut, 1);
    try std.testing.expect(FinalTerms.tupleArity(&m.ctx, date) == 3 and FinalTerms.tupleArity(&m.ctx, time) == 3);
    const y = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, date, 0));
    const mo = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, date, 1));
    const d = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, date, 2));
    const h = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, time, 0));
    const mi = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, time, 1));
    const s = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, time, 2));
    // A real wall-clock read: a sane current year (NOT the epoch, NOT a ns-as-seconds
    // overflow) + valid calendar ranges. The year band is the mutant tripwire.
    try std.testing.expect(y >= 2024 and y <= 2100);
    try std.testing.expect(mo >= 1 and mo <= 12 and d >= 1 and d <= 31);
    try std.testing.expect(h >= 0 and h <= 23 and mi >= 0 and mi <= 59 and s >= 0 and s <= 59);
}

test "LAW gap-justified-bif-sweep now/0 (DIVERGENCE 653): {Mega,Sec,Micro} from the real UTC clock is a VALID erts-split timestamp — Sec/Micro in [0,1e6), Mega*1e6+Sec a RECENT epoch second (a real wall read, never epoch/overflow); truthful + host-nondeterministic (not TZ-coupled), never fabricated (FM-OBS-1)" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const nw = try now_0(&m, &.{});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, nw) == .tuple and FinalTerms.tupleArity(&m.ctx, nw) == 3);
    const mega = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, nw, 0));
    const secs = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, nw, 1));
    const micros = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, nw, 2));
    // erts split invariants — the /vs% split-math mutant tripwire.
    try std.testing.expect(secs >= 0 and secs < 1_000_000);
    try std.testing.expect(micros >= 0 and micros < 1_000_000);
    const epoch_s = mega * 1_000_000 + secs;
    try std.testing.expect(epoch_s > 1_700_000_000 and epoch_s < 5_000_000_000); // ~2023..2128, a real wall read
}

test "LAW E3.18: posixtime<->universaltime is an inverse pair over the Gregorian calendar" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const int = FinalTerms.int;

    // WORKED VECTOR: 1970-01-01 00:00:00 == posix 0 (the epoch).
    {
        const ut = try posixtime_to_universaltime_1(&m, &.{int(&m.ctx, 0)});
        const date = FinalTerms.tupleElem(&m.ctx, ut, 0);
        const time = FinalTerms.tupleElem(&m.ctx, ut, 1);
        try std.testing.expectEqual(@as(i64, 1970), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, date, 0)));
        try std.testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, date, 1)));
        try std.testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, date, 2)));
        try std.testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, time, 0)));
    }
    // WORKED VECTOR: 2001-09-09 01:46:40 UTC == posix 1_000_000_000.
    {
        const ut = try posixtime_to_universaltime_1(&m, &.{int(&m.ctx, 1_000_000_000)});
        const date = FinalTerms.tupleElem(&m.ctx, ut, 0);
        const time = FinalTerms.tupleElem(&m.ctx, ut, 1);
        try std.testing.expectEqual(@as(i64, 2001), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, date, 0)));
        try std.testing.expectEqual(@as(i64, 9), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, date, 1)));
        try std.testing.expectEqual(@as(i64, 9), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, date, 2)));
        try std.testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, time, 0)));
        try std.testing.expectEqual(@as(i64, 46), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, time, 1)));
        try std.testing.expectEqual(@as(i64, 40), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, time, 2)));
        // Inverse: universaltime_to_posixtime(posixtime_to_universaltime(S)) == S.
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try universaltime_to_posixtime_1(&m, &.{ut}), int(&m.ctx, 1_000_000_000)));
    }
    // ROUND-TRIP over a range, INCLUDING a pre-1970 (negative) POSIX time.
    for ([_]i64{ -86400 * 400, -1, 0, 1, 86399, 86400, 951782400, 1_700_000_000 }) |secs| {
        const ut = try posixtime_to_universaltime_1(&m, &.{int(&m.ctx, secs)});
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try universaltime_to_posixtime_1(&m, &.{ut}), int(&m.ctx, secs)));
    }

    // Rejection: a non-integer posix, and a malformed datetime, are badarg.
    try std.testing.expectError(error.Badarg, posixtime_to_universaltime_1(&m, &.{FinalTerms.atom(&m.ctx, m.bool_true)}));
    const bad_dt = try FinalTerms.tuple(&m.ctx, &.{ int(&m.ctx, 1), int(&m.ctx, 2) }); // date not a 3-tuple
    try std.testing.expectError(error.Badarg, universaltime_to_posixtime_1(&m, &.{bad_dt}));
}

/// A test allocator that DETERMINISTICALLY exposes a read-after-free of a
/// `ctx.words`-backed slice across a `ctx.words` grow, independent of the host
/// allocator's in-place-remap luck: `resize`/`remap` always DECLINE (forcing
/// ArrayList to alloc-new + copy + free-old — a guaranteed MOVE), and `free`
/// POISONS the released bytes with 0xAA before returning them. So after the
/// first `ctx.words` grow during decode, the OLD backing (where an un-duped
/// source slice would still point) is filled with 0xAA — the decoder then
/// reads 0xAA as its next ETF tag and fails `UnknownTag`→`badarg`. The
/// `binaryToTermImpl` dupe reads its own private copy instead, so it is
/// unaffected. This is a pure-Zig test harness (allowed under `src/`), not VM
/// semantics.
const ForceMovePoisonAllocator = struct {
    child: std.mem.Allocator,

    fn allocFn(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *ForceMovePoisonAllocator = @ptrCast(@alignCast(ctx));
        return self.child.rawAlloc(len, alignment, ra);
    }
    fn resizeFn(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false; // never resize in place → force a move
    }
    fn remapFn(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null; // never remap in place → force alloc+copy+free
    }
    fn freeFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *ForceMovePoisonAllocator = @ptrCast(@alignCast(ctx));
        @memset(memory, 0xAA); // poison the released region before handing it back
        self.child.rawFree(memory, alignment, ra);
    }
    const vtable: std.mem.Allocator.VTable = .{
        .alloc = allocFn,
        .resize = resizeFn,
        .remap = remapFn,
        .free = freeFn,
    };
    fn allocator(self: *ForceMovePoisonAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }
};

test "LAW E2.5 binary_to_term is realloc-safe: source binary lives on ctx.words but decode grows ctx.words mid-read" {
    // REGRESSION (read-after-free): `etf.decode` reads FROM the source bytes
    // WHILE appending the decoded result terms into the SAME `ctx.words`
    // backing store. If the source is a `binBytes` slice into `ctx.words`
    // (the common case — the binary arg is itself a heap term), a grow
    // reallocates the backing and dangles the source slice mid-decode. The
    // `binaryToTermImpl` dupe defends against exactly this. The
    // ForceMovePoisonAllocator makes the failure DETERMINISTIC (see its
    // doc-comment). Mutant: revert the dupe
    // (`etf.decode(m.gpa, &m.ctx, binBytes(w))`) → decode reads the poisoned
    // old backing → `error.UnknownTag`→`badarg`; the assertion below fails.
    var backing = ForceMovePoisonAllocator{ .child = std.testing.allocator };
    const gpa = backing.allocator();
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // A small multi-element float list — enough that decoding it appends more
    // than one term into ctx.words (so at least one grow-and-move happens
    // AFTER the source header byte has been read).
    var lst = FinalTerms.nil(&m.ctx);
    var k: usize = 6;
    while (k > 0) {
        k -= 1;
        lst = try FinalTerms.cons(&m.ctx, FinalTerms.float(&m.ctx, @as(f64, @floatFromInt(k)) + 0.5), lst);
    }
    const bin = try term_to_binary_1(&m, &.{lst});

    // Zero spare capacity so the first result-term append during decode grows
    // (and, under this allocator, moves+poisons) immediately.
    m.ctx.words.shrinkAndFree(gpa, m.ctx.words.items.len);

    // With the dupe fix: decode reads its own off-heap copy → round-trips to T.
    // With the mutant (in-place read): decode reads the poisoned old backing
    // after the first grow → error.UnknownTag → badarg → the `try` fails.
    const back = try binary_to_term_1(&m, &.{bin});
    try std.testing.expect(FinalTerms.eql(&m.ctx, back, lst));
}

test "LAW E2.5 float<->list round-trips (moderate finite floats); list_to_float requires a decimal point" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const fs = [_]f64{ 0.0, 1.0, -1.0, 3.14, -2.5, 100.125 };
    for (fs) |f| {
        const lst = try float_to_list_1(&m, &.{FinalTerms.float(&m.ctx, f)});
        const back = try list_to_float(&m, &.{lst});
        try std.testing.expect(FinalTerms.floatValOf(&m.ctx, back) == f);
    }

    // float_to_list/2 with {decimals, D}.
    const fixed = try float_to_list_2(&m, &.{ FinalTerms.float(&m.ctx, 3.14159), try FinalTerms.cons(&m.ctx, try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("decimals")), FinalTerms.int(&m.ctx, 2) }), FinalTerms.nil(&m.ctx)) });
    const bytes = try termToUtf8Str(&m, gpa, fixed);
    defer gpa.free(bytes);
    try std.testing.expect(std.mem.eql(u8, bytes, "3.14"));

    // Rejections.
    try std.testing.expectError(error.Badarg, list_to_float(&m, &.{try strTerm(&m, "123")})); // no '.'
    try std.testing.expectError(error.Badarg, list_to_float(&m, &.{try strTerm(&m, "abc")}));
    try std.testing.expectError(error.Badarg, float_to_list_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
}

test "LAW E3.6: pid_to_list denotes diag's EXACT print shape; list_to_pid is its inverse (round-trip)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // WORKED DENOTATION (pinned against diag.zig's own "<0.3.1>" spot-pin).
    const p = try FinalTerms.pid(&m.ctx, 3, 1);
    const lst = try pid_to_list(&m, &.{p});
    try expectEqlExact(&m, pid_to_list(&m, &.{p}), try strTerm(&m, "<0.3.1>"));

    // ROUND-TRIP: list_to_pid(pid_to_list(P)) == P.
    const back = try list_to_pid(&m, &.{lst});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, back, p));

    // Seeded round-trip over many (number, serial) pairs.
    var prng = std.Random.DefaultPrng.init(0x91D_9EF);
    const random = prng.random();
    for (0..100) |_| {
        const n = random.int(u32);
        const s = random.int(u32);
        const pid_t = try FinalTerms.pid(&m.ctx, n, s);
        const rt = try list_to_pid(&m, &.{try pid_to_list(&m, &.{pid_t})});
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, rt, pid_t));
    }

    // LIVENESS-AGNOSTIC BUILD: a never-created id still builds a pid term
    // (BEAM does not validate liveness — see the section doc comment).
    const never_created = try list_to_pid(&m, &.{try strTerm(&m, "<0.9999.0>")});
    try std.testing.expect(FinalTerms.repIsPid(&m.ctx, never_created));
    try std.testing.expect(FinalTerms.pidNumber(&m.ctx, never_created) == 9999);
    try std.testing.expect(FinalTerms.pidSerial(&m.ctx, never_created) == 0);

    // Rejections: malformed shape, non-list, wrong kind, foreign node.
    try std.testing.expectError(error.Badarg, list_to_pid(&m, &.{try strTerm(&m, "<0.3>")})); // missing serial
    try std.testing.expectError(error.Badarg, list_to_pid(&m, &.{try strTerm(&m, "0.3.1")})); // missing '<'/'>'
    try std.testing.expectError(error.Badarg, list_to_pid(&m, &.{try strTerm(&m, "<0.3.1>x")})); // trailing junk
    try std.testing.expectError(error.Badarg, list_to_pid(&m, &.{try strTerm(&m, "<1.3.1>")})); // foreign node
    try std.testing.expectError(error.Badarg, list_to_pid(&m, &.{FinalTerms.int(&m.ctx, 1)})); // non-list
    try std.testing.expectError(error.Badarg, pid_to_list(&m, &.{FinalTerms.int(&m.ctx, 1)})); // wrong kind
}

test "LAW E3.6: ref_to_list/list_to_ref round-trip over diag's #Ref<0.W1.W2.W3> shape" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const r = try FinalTerms.ref(&m.ctx, .{ 5, 6, 7 });
    try expectEqlExact(&m, ref_to_list(&m, &.{r}), try strTerm(&m, "#Ref<0.5.6.7>"));

    const back = try list_to_ref(&m, &.{try ref_to_list(&m, &.{r})});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, back, r));

    // ROUND-TRIP over freshly-generated (guaranteed-distinct) refs.
    for (0..50) |_| {
        const fr = try FinalTerms.freshRef(&m.ctx);
        const rt = try list_to_ref(&m, &.{try ref_to_list(&m, &.{fr})});
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, rt, fr));
    }

    try std.testing.expectError(error.Badarg, list_to_ref(&m, &.{try strTerm(&m, "#Ref<0.5.6>")})); // missing word
    try std.testing.expectError(error.Badarg, list_to_ref(&m, &.{try strTerm(&m, "Ref<0.5.6.7>")})); // missing '#'
    try std.testing.expectError(error.Badarg, list_to_ref(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    try std.testing.expectError(error.Badarg, ref_to_list(&m, &.{FinalTerms.int(&m.ctx, 1)}));
}

test "LAW E3.6: port_to_list/list_to_port round-trip over diag's #Port<0.N> shape" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const port = try FinalTerms.port(&m.ctx, 9);
    try expectEqlExact(&m, port_to_list(&m, &.{port}), try strTerm(&m, "#Port<0.9>"));

    const back = try list_to_port(&m, &.{try port_to_list(&m, &.{port})});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, back, port));

    var prng = std.Random.DefaultPrng.init(0x90F_7A2);
    const random = prng.random();
    for (0..100) |_| {
        const n = random.int(u32);
        const pt = try FinalTerms.port(&m.ctx, n);
        const rt = try list_to_port(&m, &.{try port_to_list(&m, &.{pt})});
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, rt, pt));
    }

    // LIVENESS-AGNOSTIC BUILD, mirroring the pid case.
    const never_created = try list_to_port(&m, &.{try strTerm(&m, "#Port<0.9999>")});
    try std.testing.expect(FinalTerms.repIsPort(&m.ctx, never_created));
    try std.testing.expect(FinalTerms.portNumber(&m.ctx, never_created) == 9999);

    try std.testing.expectError(error.Badarg, list_to_port(&m, &.{try strTerm(&m, "#Port<0.>")})); // no digits
    try std.testing.expectError(error.Badarg, list_to_port(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    try std.testing.expectError(error.Badarg, port_to_list(&m, &.{FinalTerms.int(&m.ctx, 1)}));
}

fn mkDatetime(mm: *Machine, y: i64, mo: i64, d: i64, h: i64, mi: i64, s: i64) !Term {
    const date = try FinalTerms.tuple(&mm.ctx, &.{ FinalTerms.int(&mm.ctx, y), FinalTerms.int(&mm.ctx, mo), FinalTerms.int(&mm.ctx, d) });
    const time = try FinalTerms.tuple(&mm.ctx, &.{ FinalTerms.int(&mm.ctx, h), FinalTerms.int(&mm.ctx, mi), FinalTerms.int(&mm.ctx, s) });
    return FinalTerms.tuple(&mm.ctx, &.{ date, time });
}

test "LAW gap-localtime-tz (DIVERGENCE 731): universaltime↔localtime apply the host TZ offset (prim_file.tzOffsetAt) and are exact INVERSES (round-trip); the shift equals the offset AT that instant" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // ROUND-TRIP (host-AGNOSTIC in correctness): l2u(u2l(U)) == U for a datetime
    // away from a DST fold. Holds for ANY host offset (the +off then −off cancels);
    // a mutant that breaks the +off/−off symmetry reds here on the non-UTC gate host.
    const u = try mkDatetime(&m, 2024, 6, 15, 12, 0, 0);
    const l = try universaltime_to_localtime_1(&m, &.{u});
    const u_back = try localtime_to_universaltime_1(&m, &.{l});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, u_back, u));

    // OFFSET DIRECTION: u2l shifts U FORWARD by EXACTLY tzOffsetAt(U-instant) — the
    // local wall clock is ahead of UTC by the zone offset. This PINS the sign; the
    // `secs − off` mutant reds here (on the non-UTC gate host; see MUTATION_LOG for
    // the host-TZ note). The pure Gregorian secs conversion is the shared oracle.
    const u_secs = FinalTerms.smallValOf(try universaltime_to_posixtime_1(&m, &.{u}));
    const l_secs = FinalTerms.smallValOf(try universaltime_to_posixtime_1(&m, &.{l}));
    try std.testing.expectEqual(prim_file.tzOffsetAt(u_secs), l_secs - u_secs);

    // a SECOND datetime (winter, standard time) round-trips too — exercises the
    // other side of the zone's DST rule when the gate host observes DST.
    const w = try mkDatetime(&m, 2023, 12, 25, 9, 30, 15);
    const wl = try universaltime_to_localtime_1(&m, &.{w});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try localtime_to_universaltime_1(&m, &.{wl}), w));
}

test "MUTANT 1 RED-demo (documented, not executed): pid_to_list dropping the serial breaks the round-trip law" {
    // See MUTATION_LOG.md E3.6 mutant 1. Manually verified: if `diag.zig`'s
    // `.pid` print arm is mutated to `"<0.{d}>"` (dropping `p.serial`) —
    // `pid_to_list`/`termToCharList` reuse that SAME formatter, so the
    // mutation surfaces here too, not just in diag's own spot-pin test —
    // then `list_to_pid(pid_to_list(pid(3,1)))` fails to parse (the
    // `list_to_pid` parser requires TWO dotted numbers before `>`, so a
    // 1-number string like "<0.3>" is a clean `Badarg`, never a silently
    // wrong pid) — the round-trip law above fails immediately on its very
    // first assertion.
}
