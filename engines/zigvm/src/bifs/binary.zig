//! # bifs/binary — the `binary:` BIF family (E2.8)
//!
//! ## Signature
//! Same contract as `bifs/erlang.zig`/`bifs/conv.zig`/`bifs/lists.zig`/
//! `bifs/maps.zig`: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over ALREADY-
//! RESOLVED term arguments, computed via `term_algebra`'s EXISTING binary
//! accessors (`binBytes`, `binSize`, `binPart`, `iolistToBinary`,
//! `intFromLimbs`, `bigPartsOf`) — NO new BINARY REPRESENTATION lives here.
//! The multi-pattern byte search this family needs (`match`/`matches`/
//! `split`) has no `bin_algebra` combinator to reuse (that module owns
//! concat/part/iolist-flatten/bitstring, not search) — it is implemented
//! directly here as plain `[]const u8` substring scanning over ALREADY-
//! EXPOSED `binBytes` reads, never a new byte layout or tag. It NEVER panics
//! on a well-formed call.
//!
//! ## The dispatch mechanism (unchanged — see `bifs/dispatch.zig`)
//! This task adds ONLY `pub fn`s here, an `implOfBinary` arm in
//! `bifs/dispatch.zig`, and `implemented_map` rows in `harness/bif_gen.ml`.
//! The generated `bif_table.zig`, the loader, and the `bif_call` executor are
//! untouched.
//!
//! ## PIN LEDGER NOTE (the `binary:bin_to_list/1,2,3` scope, honest)
//! The pinned `bif.tab` declares 21 real `binary:` BIFs: `at/2`, `first/1`,
//! `last/1`, `part/2,3`, `copy/1,2`, `list_to_bin/1`,
//! `referenced_byte_size/1`, `compile_pattern/1`, `match/2,3`, `matches/2,3`,
//! `split/2,3`, `longest_common_prefix/1`, `longest_common_suffix/1`,
//! `encode_unsigned/1,2`, `decode_unsigned/1,2`. `bin_to_list/1,2,3` is a
//! `binary.erl` LIBRARY wrapper (built atop `part/2,3` + list conversion,
//! confirmed in `third_party/otp/lib/stdlib/src/binary.erl`) — NOT a bif.tab
//! entry, the SAME shape as `bifs/conv.zig`'s `list_to_integer/1` /
//! `bifs/maps.zig`'s `to_list/1` scope notes. This module still defines
//! `bin_to_list_1/2/3` below (law-tested directly) but does NOT wire them
//! into `bifs/dispatch.zig`/`harness/bif_gen.ml`'s `implemented_map` — there
//! is no ledger row for them, so a wire-anyway would be dead code.
//!
//! ## Scope: sub-byte / bitstring-dependent ops — DEFERRED to E3 (LA-3)
//! Every op below operates on BYTE-ALIGNED binaries only (`repIsBinary`
//! guards every entry point); `term_algebra` has no term-level bitstring tag
//! at all yet (see `bin_algebra.zig`'s own scope note: "Term-level bitstring
//! tags and ETF BIT_BINARY_EXT integration remain later representation
//! work"), so there is nothing sub-byte-shaped to even partially wire here.
//! Nothing in this module is wired, tested, or `EQUIV`-recorded as
//! sub-byte-capable; a non-byte-aligned bitstring simply cannot reach this
//! family (no such term exists yet), so it stays UNTESTED (not silently EQ),
//! consistent with the deferral discipline.
//!
//! ## Compiled-pattern representation (documented choice)
//! `binary:compile_pattern/1` is implemented, NOT deferred: a compiled
//! pattern is the tagged tuple `{'$binary_pattern', PatternBinaries}`, where
//! `PatternBinaries` is the NORMALIZED proper list of pattern binaries
//! (deduplicated shape only — a single binary compiles to a one-element
//! list). `match`/`matches`/`split` accept a raw binary, a proper list of
//! binaries, OR this tagged tuple interchangeably (`normalizePatterns`
//! unwraps the tag transparently) — so `compile_pattern/1`'s result is a
//! fully first-class Pattern arg everywhere a Pattern is accepted. This is a
//! genuine (if simple, non-precompiled/non-Aho-Corasick) implementation, not
//! a stub — chosen because the pin's bif.tab DOES declare `compile_pattern/1`
//! as a real BIF and there is no representation reason to defer it.
//!
//! ## Bignum scope (`encode_unsigned`/`decode_unsigned`, consistent with the
//! E2.4/E2.5 bignum-defer)
//! `term_algebra.intFromLimbs`/`bigPartsOf` DO let this module build/read a
//! genuine BEAM bignum term from/to raw bytes — `encode_unsigned` and
//! `decode_unsigned` are NOT small-int-only. The hard cap is
//! `FinalTerms.max_limbs` (8 u64 limbs = 512 bits = 64 bytes of magnitude,
//! the FinalTerms engineering bound documented on `max_limbs` itself): a
//! `decode_unsigned` source binary longer than 64 bytes, or an
//! `encode_unsigned` bignum operand whose magnitude would need more than 8
//! limbs (unreachable in practice — `intFromLimbs`'s own `max_limbs` bound
//! means no larger bignum term can exist), is a clean `error.Badarith` —
//! mirrors `bifs/conv.zig`'s `needSmallI128` bignum-defer shape exactly (a
//! documented capacity limit, not a silent truncation).
//! Negative operands are `badarg` on both directions: `encode_unsigned` is
//! defined only for non-negative integers (a negative small int, or a
//! negative bignum's `positive == false`, is `error.Badarg`); `decode_unsigned`
//! always produces a non-negative result by construction (`intFromLimbs`
//! called with `positive = true`).
//!
//! ## Lifetime safety — THE #1 RISK (E2.5's read-after-free was in this
//! exact class: `binary()`/`cons`/`tuple`/`intFromLimbs` all call `ctx.alloc`,
//! which can grow/reallocate `ctx.words`, dangling ANY `binBytes` slice held
//! across that call). Audited per fn:
//!   - `at_2`/`first_1`/`last_1`: the ONLY construction is `FinalTerms.int`,
//!     which is an IMMEDIATE (no `ctx.alloc` at all — see `term_algebra.int`)
//!     — safe regardless of ordering; the `binBytes` slice is never at risk.
//!   - `part_2`/`part_3`: delegate to `term_algebra.binPart`, which ITSELF
//!     reads `binBytesOf` then copies into a `ctx.gpa`-owned temp buffer
//!     BEFORE calling `binary()` (already-audited term_algebra internal
//!     pattern) — no additional dupe needed in the wrapper, which only reads
//!     `binSize`/small-int args (no raw slice held across construction).
//!   - `copy_1`: reads `binBytes`, `m.gpa.dupe`s it, THEN constructs — the
//!     canonical dupe-before-construct pattern (mirrors
//!     `bifs/conv.zig.binary_to_list_1`).
//!   - `copy_2`: reads `binBytes` once, repeat-appends it into an
//!     `m.gpa`-owned `ArrayList` (no `ctx.words` growth during the appends),
//!     THEN makes the SINGLE `binary()` call at the end — the source slice is
//!     never touched after that call, so finish-reads-before-construction
//!     applies even without an explicit standalone dupe var.
//!   - `list_to_bin_1`: delegates directly to `term_algebra.iolistToBinary`,
//!     which accumulates every leaf's `binBytesOf` into a `ctx.gpa`-owned
//!     `ArrayList` (no `ctx.words` growth during the walk — the walk itself
//!     builds no terms) and calls `binary()` exactly ONCE at the end — already
//!     audited term_algebra-internal safety (same pattern `bifs/conv.zig`'s
//!     `list_to_binary` reuses without an extra dupe).
//!   - `referenced_byte_size_1`: never holds a `binBytes` slice at all — only
//!     `binSize` (a `usize`, not a slice) feeds the single `int`/`intFromI128`
//!     construction. Trivially safe. (`referenced_byte_size` == `byte_size`
//!     in THIS representation — no reference-counted over-allocation is
//!     modeled, a documented simplification: every `part`/`copy` here
//!     allocates a tight new backing, so there is no larger "referenced"
//!     blob to report a bigger count for.)
//!   - `longest_common_prefix_1`/`longest_common_suffix_1`: collect
//!     `binBytes` slices from every list element (values ARE `ctx.words`
//!     slices, held throughout the byte-by-byte scan), but the scan performs
//!     NO term construction at all until the single final `intFromI128` call
//!     — finish-all-reads-before-construction; the slices are never read
//!     again afterward.
//!   - `compile_pattern_1`: `normalizePatterns` collects PATTERN TERM VALUES
//!     (tagged offsets, not raw slices — realloc-safe to hold, see
//!     `bifs/lists.zig`'s module-level lifetime note) via `kindOf`/
//!     `tupleElem`/`listHead`/`listTail` walks only — no `binBytes` read at
//!     all in the normalize step (only `repIsBinary`/`binSize` checks, both
//!     slice-free). The result `cons`-fold then builds the list from those
//!     Term values — safe by the same pattern as `lists.reverse_2`.
//!   - `match_2/3`, `matches_2/3`, `split_2/3`: normalize patterns to Term
//!     values (slice-free, as above), then explicitly `dupeBytes` BOTH the
//!     subject AND every pattern binary into `m.gpa`-owned buffers BEFORE any
//!     search or construction runs (`dupePatternBytes`/`dupeBytes`) — the
//!     search phase and (for `split`) the MULTIPLE subsequent `binary()`
//!     calls all read exclusively from these off-heap copies, never from
//!     `ctx.words` again. This is the primary dupe-before-construct
//!     application in the module: `split` in particular builds N+1 binaries
//!     from slices of the SAME subject buffer across N+1 separate `binary()`
//!     calls, each of which can grow `ctx.words` — without the upfront dupe,
//!     the SECOND `binary()` call would dangle the source slice the FIRST
//!     call's growth invalidated. Dupe-first removes the hazard entirely.
//!   - `encode_unsigned_1/2`: the small-int path never reads `binBytes` at
//!     all. The bignum path reads `FinalTerms.bigPartsOf(...).limbs` (a slice
//!     INTO `ctx.words`) and immediately transforms it into an `m.gpa`-owned
//!     byte buffer (`magnitudeBEBytesFromLimbs`, which itself only calls
//!     `m.gpa.alloc`/`m.gpa.dupe` — never `ctx.alloc`) BEFORE the single
//!     `binary()` construction — read-then-transform-to-owned-then-construct,
//!     the limbs slice is never touched again afterward.
//!   - `decode_unsigned_1/2`: `bytesToLimbsBE` copies every byte it needs
//!     into a LOCAL `[8]u64` stack array before `intFromLimbs` (the only
//!     construction) runs — the source `binBytes` slice is never touched
//!     again afterward (finish-all-reads-before-construction; no separate
//!     dupe var needed). The `little`-endianness path reverses into an
//!     `m.gpa`-owned buffer first (not a construction call), then feeds that
//!     into the same safe path.
//!   - `bin_to_list_1/2/3` (unwired, still lifetime-audited since they are
//!     law-tested): `m.gpa.dupe`s the (possibly ranged) bytes BEFORE the
//!     `cons`-fold loop — mirrors `bifs/conv.zig.binary_to_list_1`/`_3`
//!     exactly.
//!
//! ## Laws (see the test suite below)
//!   - DENOTATION  at(<<1,2,3>>,1) == 2 (0-based); part(<<1,2,3,4>>,1,2) ==
//!     <<2,3>>; bin_to_list(<<1,2>>) == [1,2]; list_to_bin([1,<<2,3>>,4]) ==
//!     <<1,2,3,4>>; match(<<"abcXabc">>,<<"abc">>) == {0,3};
//!     matches(<<"abcXabc">>,<<"abc">>) == [{0,3},{4,3}];
//!     split(<<"a,b,c">>,<<",">>) == [<<"a">>,<<"b,c">>];
//!     decode_unsigned(<<1,0>>) == 256; encode_unsigned(256) == <<1,0>>
//!   - ROUND-TRIP  decode_unsigned(encode_unsigned(N)) == N (small AND bignum
//!     N, both endiannesses)
//!   - REJECTION  OOB `at`/`part`, an empty `first`/`last`, a non-binary arg,
//!     an empty/absent Pattern, a negative `encode_unsigned` operand, an
//!     empty `decode_unsigned` binary → a clean `error.Badarg` (never a
//!     panic); an over-64-byte `decode_unsigned` source → `error.Badarith`
//!     (the documented bignum-cap scope limit).
//!   - MUTANT-A (`at` 1-based instead of 0-based) and MUTANT-B (`part`
//!     treats `Len` as an end-index instead of a length) are marked at their
//!     call sites below; see `MUTATION_LOG.md` for the RED-demo record.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

// ── shared helpers ─────────────────────────────────────────────────────────

fn needBinary(m: *Machine, w: Term) BifError![]const u8 {
    if (!FinalTerms.repIsBinary(&m.ctx, w)) return error.Badarg;
    return FinalTerms.binBytes(&m.ctx, w);
}

fn needSmallI64(w: Term) BifError!i64 {
    if (!FinalTerms.repIsSmall(w)) return error.Badarg;
    return FinalTerms.smallValOf(w);
}

fn dupeBytes(m: *Machine, bytes: []const u8) BifError![]u8 {
    return m.gpa.dupe(u8, bytes) catch error.OutOfMemory;
}

fn atomNameIs(m: *Machine, w: Term, name: []const u8) bool {
    if (!FinalTerms.repIsAtom(w)) return false;
    return std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(w)), name);
}

// ── binary:at/2, first/1, last/1 ─────────────────────────────────────────

pub fn at_2(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try needBinary(m, args[0]);
    const pos_i = try needSmallI64(args[1]);
    // MUTANT-A (`at` is 1-based instead of 0-based): using `pos_i - 1` here
    // instead of `pos_i` directly would silently shift every valid call by
    // one and wrongly accept `Pos == bytes.len` as in-range.
    if (pos_i < 0 or pos_i >= @as(i64, @intCast(bytes.len))) return error.Badarg;
    return FinalTerms.int(&m.ctx, bytes[@intCast(pos_i)]);
}

pub fn first_1(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try needBinary(m, args[0]);
    if (bytes.len == 0) return error.Badarg;
    return FinalTerms.int(&m.ctx, bytes[0]);
}

pub fn last_1(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try needBinary(m, args[0]);
    if (bytes.len == 0) return error.Badarg;
    return FinalTerms.int(&m.ctx, bytes[bytes.len - 1]);
}

// ── binary:part/2,3 ──────────────────────────────────────────────────────

const Range = struct { start: usize, len: usize };

/// `{Pos,Len}` -> `{start,len}` bounds over a binary of `size` bytes.
/// Negative `Len` counts BACKWARD from `Pos` (BEAM's documented convention):
/// `part(<<1,2,3,4,5>>, 5, -2) == <<4,5>>`. `badarg` on any out-of-range
/// combination.
fn partRange(size: usize, pos_i: i64, len_i: i64) BifError!Range {
    if (pos_i < 0 or pos_i > @as(i64, @intCast(size))) return error.Badarg;
    const pos: usize = @intCast(pos_i);
    if (len_i < 0) {
        const neg: i64 = -len_i;
        if (neg > pos_i) return error.Badarg;
        const start = pos - @as(usize, @intCast(neg));
        return .{ .start = start, .len = @intCast(neg) };
    }
    // MUTANT-B (`part` treats `Len` as an end-index): computing
    // `@as(usize,@intCast(len_i)) - pos` here (deriving a length by
    // subtracting `Pos` from `Len`, as if `Len` were an absolute end offset)
    // instead of using `len_i` directly AS the length would silently
    // reinterpret the third argument's meaning.
    const length: usize = @intCast(len_i);
    if (pos + length > size) return error.Badarg;
    return .{ .start = pos, .len = length };
}

fn partImpl(m: *Machine, bin: Term, pos_i: i64, len_i: i64) BifError!Term {
    const size = FinalTerms.binSize(&m.ctx, bin);
    const r = try partRange(size, pos_i, len_i);
    return FinalTerms.binPart(&m.ctx, bin, r.start, r.len) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.Badarg,
    };
}

pub fn part_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    const pl = args[1];
    if (FinalTerms.kindOf(&m.ctx, pl) != .tuple or FinalTerms.tupleArity(&m.ctx, pl) != 2) return error.Badarg;
    const pos_i = try needSmallI64(FinalTerms.tupleElem(&m.ctx, pl, 0));
    const len_i = try needSmallI64(FinalTerms.tupleElem(&m.ctx, pl, 1));
    return partImpl(m, args[0], pos_i, len_i);
}

pub fn part_3(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    const pos_i = try needSmallI64(args[1]);
    const len_i = try needSmallI64(args[2]);
    return partImpl(m, args[0], pos_i, len_i);
}

// ── binary:copy/1,2 ───────────────────────────────────────────────────────

pub fn copy_1(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try needBinary(m, args[0]);
    const owned = try dupeBytes(m, bytes);
    defer m.gpa.free(owned);
    return FinalTerms.binary(&m.ctx, owned) catch error.OutOfMemory;
}

pub fn copy_2(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try needBinary(m, args[0]);
    const n_i = try needSmallI64(args[1]);
    if (n_i < 0) return error.Badarg;
    const n: usize = @intCast(n_i);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(m.gpa);
    var i: usize = 0;
    while (i < n) : (i += 1) out.appendSlice(m.gpa, bytes) catch return error.OutOfMemory;
    return FinalTerms.binary(&m.ctx, out.items) catch error.OutOfMemory;
}

// ── binary:list_to_bin/1 ─────────────────────────────────────────────────

pub fn list_to_bin_1(m: *Machine, args: []const Term) BifError!Term {
    const k = FinalTerms.kindOf(&m.ctx, args[0]);
    if (k != .cons and k != .nil) return error.Badarg;
    return FinalTerms.iolistToBinary(&m.ctx, args[0]) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.Badarg,
    };
}

// ── binary:referenced_byte_size/1 ────────────────────────────────────────

pub fn referenced_byte_size_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    return FinalTerms.intFromI128(&m.ctx, @intCast(FinalTerms.binSize(&m.ctx, args[0]))) catch error.OutOfMemory;
}

// ── binary:longest_common_prefix/1, longest_common_suffix/1 ─────────────

fn collectBinBytesList(m: *Machine, list: Term) BifError![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(m.gpa);
    var cur = list;
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => break,
            .cons => {
                const h = FinalTerms.listHead(&m.ctx, cur);
                if (!FinalTerms.repIsBinary(&m.ctx, h)) return error.Badarg;
                out.append(m.gpa, FinalTerms.binBytes(&m.ctx, h)) catch return error.OutOfMemory;
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg,
        }
    }
    if (out.items.len == 0) return error.Badarg;
    return out.toOwnedSlice(m.gpa) catch error.OutOfMemory;
}

pub fn longest_common_prefix_1(m: *Machine, args: []const Term) BifError!Term {
    const bins = try collectBinBytesList(m, args[0]);
    defer m.gpa.free(bins);
    var n: usize = bins[0].len;
    for (bins[1..]) |b| n = @min(n, b.len);
    var plen: usize = 0;
    outer: while (plen < n) : (plen += 1) {
        const c = bins[0][plen];
        for (bins[1..]) |b| if (b[plen] != c) break :outer;
    }
    return FinalTerms.intFromI128(&m.ctx, @intCast(plen)) catch error.OutOfMemory;
}

pub fn longest_common_suffix_1(m: *Machine, args: []const Term) BifError!Term {
    const bins = try collectBinBytesList(m, args[0]);
    defer m.gpa.free(bins);
    var n: usize = bins[0].len;
    for (bins[1..]) |b| n = @min(n, b.len);
    var slen: usize = 0;
    outer: while (slen < n) : (slen += 1) {
        const c = bins[0][bins[0].len - 1 - slen];
        for (bins[1..]) |b| if (b[b.len - 1 - slen] != c) break :outer;
    }
    return FinalTerms.intFromI128(&m.ctx, @intCast(slen)) catch error.OutOfMemory;
}

// ── binary:compile_pattern/1 + Pattern normalization ─────────────────────

/// Normalize a `Pattern` arg (a binary | a proper list of binaries | a
/// `{'$binary_pattern', PatList}` compiled pattern) into an owned `m.gpa`
/// array of PATTERN TERM VALUES (each guaranteed `repIsBinary` and
/// non-empty). Term VALUES are realloc-safe to hold (see module lifetime
/// note); `badarg` on an empty pattern set, an empty pattern binary, a
/// non-binary list element, or any other shape.
fn normalizePatterns(m: *Machine, pattern0: Term) BifError![]Term {
    var pattern = pattern0;
    if (FinalTerms.kindOf(&m.ctx, pattern) == .tuple and
        FinalTerms.tupleArity(&m.ctx, pattern) == 2 and
        atomNameIs(m, FinalTerms.tupleElem(&m.ctx, pattern, 0), "$binary_pattern"))
    {
        pattern = FinalTerms.tupleElem(&m.ctx, pattern, 1); // unwrap to the inner list
    }
    if (FinalTerms.repIsBinary(&m.ctx, pattern)) {
        if (FinalTerms.binSize(&m.ctx, pattern) == 0) return error.Badarg;
        const out = m.gpa.alloc(Term, 1) catch return error.OutOfMemory;
        out[0] = pattern;
        return out;
    }
    var out: std.ArrayList(Term) = .empty;
    errdefer out.deinit(m.gpa);
    var cur = pattern;
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => break,
            .cons => {
                const h = FinalTerms.listHead(&m.ctx, cur);
                if (!FinalTerms.repIsBinary(&m.ctx, h) or FinalTerms.binSize(&m.ctx, h) == 0) return error.Badarg;
                out.append(m.gpa, h) catch return error.OutOfMemory;
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg,
        }
    }
    if (out.items.len == 0) return error.Badarg;
    return out.toOwnedSlice(m.gpa) catch error.OutOfMemory;
}

pub fn compile_pattern_1(m: *Machine, args: []const Term) BifError!Term {
    const pats = try normalizePatterns(m, args[0]);
    defer m.gpa.free(pats);
    var acc = FinalTerms.nil(&m.ctx);
    var i = pats.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, pats[i], acc) catch return error.OutOfMemory;
    }
    const tag_idx = m.ctx.atoms.intern("$binary_pattern") catch return error.OutOfMemory;
    const tag = FinalTerms.atom(&m.ctx, tag_idx);
    return FinalTerms.tuple(&m.ctx, &.{ tag, acc }) catch error.OutOfMemory;
}

// ── the shared byte-level search engine (match/matches/split) ────────────

const MatchRange = struct { start: usize, len: usize };

/// Earliest, then-longest match among `patterns` inside `subject[from..until]`
/// (both bounds absolute offsets into `subject`). `subject`/`patterns` MUST
/// be off-heap (gpa-owned) — this fn performs no term construction, but every
/// caller holds these across LATER construction, so they must not alias
/// `ctx.words`.
fn scanFirst(subject: []const u8, from: usize, until: usize, patterns: []const []const u8) ?MatchRange {
    var i = from;
    while (i <= until) : (i += 1) {
        var best: usize = 0;
        for (patterns) |p| {
            if (p.len == 0) continue; // normalizePatterns already rejects these; defensive only
            if (i + p.len <= until and std.mem.eql(u8, subject[i .. i + p.len], p)) {
                if (p.len > best) best = p.len;
            }
        }
        if (best > 0) return .{ .start = i, .len = best };
    }
    return null;
}

fn dupePatternBytes(m: *Machine, pats: []const Term) BifError![][]u8 {
    const out = m.gpa.alloc([]u8, pats.len) catch return error.OutOfMemory;
    var filled: usize = 0;
    errdefer {
        for (out[0..filled]) |b| m.gpa.free(b);
        m.gpa.free(out);
    }
    for (pats, 0..) |p, i| {
        out[i] = m.gpa.dupe(u8, FinalTerms.binBytes(&m.ctx, p)) catch return error.OutOfMemory;
        filled += 1;
    }
    return out;
}

fn freePatternBytes(m: *Machine, bufs: [][]u8) void {
    for (bufs) |b| m.gpa.free(b);
    m.gpa.free(bufs);
}

const Opts = struct { scope_start: usize, scope_end: usize, global: bool, trim: bool = false, trim_all: bool = false };

/// Parse an options list: `{scope, {Start,Len}}` (restricts the search
/// window; absolute positions in RESULTS are still relative to the WHOLE
/// subject, matching BEAM) and, when `allow_global` (split only), the bare
/// atom `global`. Any other option shape is a clean `badarg` — a documented,
/// honest scope limit (mirrors `bifs/conv.zig`'s `float_to_list/2`
/// single-supported-option pattern), not a silent no-op.
fn parseOpts(m: *Machine, subject_len: usize, opts: Term, allow_global: bool) BifError!Opts {
    var result = Opts{ .scope_start = 0, .scope_end = subject_len, .global = false };
    var cur = opts;
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => break,
            .cons => {
                const h = FinalTerms.listHead(&m.ctx, cur);
                if (allow_global and atomNameIs(m, h, "global")) {
                    result.global = true;
                } else if (allow_global and atomNameIs(m, h, "trim")) {
                    result.trim = true; // DIVERGENCE 693: drop TRAILING empty parts
                } else if (allow_global and atomNameIs(m, h, "trim_all")) {
                    result.trim_all = true; // DIVERGENCE 693: drop ALL empty parts
                } else if (FinalTerms.kindOf(&m.ctx, h) == .tuple and FinalTerms.tupleArity(&m.ctx, h) == 2 and
                    atomNameIs(m, FinalTerms.tupleElem(&m.ctx, h, 0), "scope"))
                {
                    const sl = FinalTerms.tupleElem(&m.ctx, h, 1);
                    if (FinalTerms.kindOf(&m.ctx, sl) != .tuple or FinalTerms.tupleArity(&m.ctx, sl) != 2) return error.Badarg;
                    const s_i = try needSmallI64(FinalTerms.tupleElem(&m.ctx, sl, 0));
                    const l_i = try needSmallI64(FinalTerms.tupleElem(&m.ctx, sl, 1));
                    const r = try partRange(subject_len, s_i, l_i);
                    result.scope_start = r.start;
                    result.scope_end = r.start + r.len;
                } else return error.Badarg;
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg,
        }
    }
    return result;
}

// ── binary:match/2,3 ──────────────────────────────────────────────────────

fn matchImpl(m: *Machine, subject: Term, pattern: Term, opts: Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, subject)) return error.Badarg;
    const pats = try normalizePatterns(m, pattern);
    defer m.gpa.free(pats);
    const subject_len = FinalTerms.binSize(&m.ctx, subject);
    const o = try parseOpts(m, subject_len, opts, false);
    // Dupe EVERY source byte slice off-heap BEFORE any term construction —
    // the subject and every pattern binary live in `ctx.words`, and the
    // result construction below (`tuple`/`atom`) can reallocate it.
    const subj = try dupeBytes(m, FinalTerms.binBytes(&m.ctx, subject));
    defer m.gpa.free(subj);
    const pat_bufs = try dupePatternBytes(m, pats);
    defer freePatternBytes(m, pat_bufs);

    if (scanFirst(subj, o.scope_start, o.scope_end, pat_bufs)) |f| {
        return FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, @intCast(f.start)), FinalTerms.int(&m.ctx, @intCast(f.len)) }) catch error.OutOfMemory;
    }
    const idx = m.ctx.atoms.intern("nomatch") catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

pub fn match_2(m: *Machine, args: []const Term) BifError!Term {
    return matchImpl(m, args[0], args[1], FinalTerms.nil(&m.ctx));
}
pub fn match_3(m: *Machine, args: []const Term) BifError!Term {
    return matchImpl(m, args[0], args[1], args[2]);
}

// ── binary:matches/2,3 ────────────────────────────────────────────────────

fn matchesImpl(m: *Machine, subject: Term, pattern: Term, opts: Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, subject)) return error.Badarg;
    const pats = try normalizePatterns(m, pattern);
    defer m.gpa.free(pats);
    const subject_len = FinalTerms.binSize(&m.ctx, subject);
    const o = try parseOpts(m, subject_len, opts, false);
    const subj = try dupeBytes(m, FinalTerms.binBytes(&m.ctx, subject));
    defer m.gpa.free(subj);
    const pat_bufs = try dupePatternBytes(m, pats);
    defer freePatternBytes(m, pat_bufs);

    // Collect ALL matches as plain structs (no terms) BEFORE any term
    // construction — the fold-cons below builds the result list only after
    // every subject/pattern byte read is finished.
    var found: std.ArrayList(MatchRange) = .empty;
    defer found.deinit(m.gpa);
    var pos = o.scope_start;
    while (true) {
        const f = scanFirst(subj, pos, o.scope_end, pat_bufs) orelse break;
        found.append(m.gpa, f) catch return error.OutOfMemory;
        pos = f.start + f.len;
    }

    var acc = FinalTerms.nil(&m.ctx);
    var i = found.items.len;
    while (i > 0) {
        i -= 1;
        const t = FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, @intCast(found.items[i].start)), FinalTerms.int(&m.ctx, @intCast(found.items[i].len)) }) catch return error.OutOfMemory;
        acc = FinalTerms.cons(&m.ctx, t, acc) catch return error.OutOfMemory;
    }
    return acc;
}

pub fn matches_2(m: *Machine, args: []const Term) BifError!Term {
    return matchesImpl(m, args[0], args[1], FinalTerms.nil(&m.ctx));
}
pub fn matches_3(m: *Machine, args: []const Term) BifError!Term {
    return matchesImpl(m, args[0], args[1], args[2]);
}

// ── binary:split/2,3 ───────────────────────────────────────────────────────

fn splitImpl(m: *Machine, subject: Term, pattern: Term, opts: Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, subject)) return error.Badarg;
    const pats = try normalizePatterns(m, pattern);
    defer m.gpa.free(pats);
    const subject_len = FinalTerms.binSize(&m.ctx, subject);
    const o = try parseOpts(m, subject_len, opts, true); // split accepts `global`
    const subj = try dupeBytes(m, FinalTerms.binBytes(&m.ctx, subject));
    defer m.gpa.free(subj);
    const pat_bufs = try dupePatternBytes(m, pats);
    defer freePatternBytes(m, pat_bufs);

    // Compute ALL split boundaries first (plain usize pairs, no terms). The
    // subject copy `subj` is gpa-owned, so the MULTIPLE `binary()` calls
    // below (each of which can grow `ctx.words`) never dangle each other's
    // source slices — every one reads from `subj`, not `ctx.words`.
    var bounds: std.ArrayList(usize) = .empty; // (match_start, match_end) pairs, ascending
    defer bounds.deinit(m.gpa);
    var pos: usize = o.scope_start;
    while (true) {
        const f = scanFirst(subj, pos, o.scope_end, pat_bufs) orelse break;
        bounds.append(m.gpa, f.start) catch return error.OutOfMemory;
        bounds.append(m.gpa, f.start + f.len) catch return error.OutOfMemory;
        pos = f.start + f.len;
        if (!o.global) break; // default: split at the FIRST match only
    }

    var parts: std.ArrayList(Term) = .empty;
    defer parts.deinit(m.gpa);
    if (bounds.items.len == 0) {
        // No match: the single part is the whole Subject (a Term VALUE).
        parts.append(m.gpa, subject) catch return error.OutOfMemory;
    } else {
        var start: usize = 0;
        var k: usize = 0;
        while (k < bounds.items.len) : (k += 2) {
            const b = FinalTerms.binary(&m.ctx, subj[start..bounds.items[k]]) catch return error.OutOfMemory;
            parts.append(m.gpa, b) catch return error.OutOfMemory;
            start = bounds.items[k + 1];
        }
        const last = FinalTerms.binary(&m.ctx, subj[start..]) catch return error.OutOfMemory;
        parts.append(m.gpa, last) catch return error.OutOfMemory;
    }

    // DIVERGENCE 693: `trim_all` drops EVERY empty (`<<>>`) part; `trim` drops only
    // TRAILING empty parts (OTP `binary:split/3`). Applied to the finished parts.
    if (o.trim_all) {
        var w: usize = 0;
        for (parts.items) |p| {
            if (FinalTerms.binSize(&m.ctx, p) != 0) {
                parts.items[w] = p;
                w += 1;
            }
        }
        parts.shrinkRetainingCapacity(w);
    } else if (o.trim) {
        while (parts.items.len > 0 and FinalTerms.binSize(&m.ctx, parts.items[parts.items.len - 1]) == 0) {
            _ = parts.pop();
        }
    }

    var acc = FinalTerms.nil(&m.ctx);
    var i = parts.items.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, parts.items[i], acc) catch return error.OutOfMemory;
    }
    return acc;
}

pub fn split_2(m: *Machine, args: []const Term) BifError!Term {
    return splitImpl(m, args[0], args[1], FinalTerms.nil(&m.ctx));
}
pub fn split_3(m: *Machine, args: []const Term) BifError!Term {
    return splitImpl(m, args[0], args[1], args[2]);
}

// ── binary:encode_unsigned/1,2, decode_unsigned/1,2 ──────────────────────

const Endianness = enum { big, little };

fn needEndianness(m: *Machine, w: Term) BifError!Endianness {
    if (atomNameIs(m, w, "big")) return .big;
    if (atomNameIs(m, w, "little")) return .little;
    return error.Badarg;
}

/// Big-endian MINIMAL byte encoding of a magnitude given as little-endian
/// u64 limbs (limbs[0] = least-significant 64 bits, the SAME convention
/// `term_algebra` uses internally). Strips leading zero bytes but always
/// keeps at least one byte. Reads `limbs` (which may alias `ctx.words` via
/// `bigPartsOf`) into a fresh `gpa`-owned buffer and returns that — the
/// caller may safely construct terms afterward.
fn magnitudeBEBytesFromLimbs(gpa: std.mem.Allocator, limbs: []const u64) BifError![]u8 {
    const buf = gpa.alloc(u8, limbs.len * 8) catch return error.OutOfMemory;
    defer gpa.free(buf);
    var i: usize = 0;
    var li = limbs.len;
    while (li > 0) {
        li -= 1;
        std.mem.writeInt(u64, buf[i..][0..8], limbs[li], .big);
        i += 8;
    }
    var start: usize = 0;
    while (start < buf.len - 1 and buf[start] == 0) start += 1;
    return gpa.dupe(u8, buf[start..]) catch error.OutOfMemory;
}

/// Non-negative operand -> owned big-endian minimal bytes; `badarg` on a
/// negative operand or a non-integer. See the module bignum-scope note for
/// the `error.Badarith` capacity limit (unreachable via a valid `Term`, since
/// `intFromLimbs`'s own `max_limbs` bound means no larger bignum can exist —
/// kept as a defensive documented boundary, not dead code removal).
fn encodeUnsignedBytes(m: *Machine, w: Term) BifError![]u8 {
    if (FinalTerms.repIsSmall(w)) {
        const v = FinalTerms.smallValOf(w);
        if (v < 0) return error.Badarg;
        if (v == 0) return dupeBytes(m, &[_]u8{0});
        const limb: u64 = @intCast(v);
        return magnitudeBEBytesFromLimbs(m.gpa, &.{limb});
    }
    if (FinalTerms.repIsBig(&m.ctx, w)) {
        const parts = FinalTerms.bigPartsOf(&m.ctx, w);
        if (!parts.positive) return error.Badarg;
        return magnitudeBEBytesFromLimbs(m.gpa, parts.limbs);
    }
    return error.Badarg;
}

pub fn encode_unsigned_1(m: *Machine, args: []const Term) BifError!Term {
    const be = try encodeUnsignedBytes(m, args[0]);
    defer m.gpa.free(be);
    return FinalTerms.binary(&m.ctx, be) catch error.OutOfMemory;
}

pub fn encode_unsigned_2(m: *Machine, args: []const Term) BifError!Term {
    const endian = try needEndianness(m, args[1]);
    const be = try encodeUnsignedBytes(m, args[0]);
    defer m.gpa.free(be);
    if (endian == .little) {
        const rev = m.gpa.alloc(u8, be.len) catch return error.OutOfMemory;
        defer m.gpa.free(rev);
        for (be, 0..) |b, i| rev[be.len - 1 - i] = b;
        return FinalTerms.binary(&m.ctx, rev) catch error.OutOfMemory;
    }
    return FinalTerms.binary(&m.ctx, be) catch error.OutOfMemory;
}

/// Big-endian bytes -> little-endian-limb `u64` array (out[0] = LSB limb),
/// matching `term_algebra`'s own limb convention. Reads only from `bytes`
/// (already off-heap by the time callers use this — see per-fn audit) into
/// the caller's LOCAL `out` array; performs no allocation.
fn bytesToLimbsBE(bytes: []const u8, out: *[FinalTerms.max_limbs]u64) usize {
    var idx: usize = 0;
    var pos: usize = bytes.len;
    while (pos > 0) : (idx += 1) {
        const start = if (pos >= 8) pos - 8 else 0;
        var buf8: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
        const chunk = bytes[start..pos];
        @memcpy(buf8[8 - chunk.len ..], chunk);
        out[idx] = std.mem.readInt(u64, &buf8, .big);
        pos = start;
    }
    return idx;
}

fn decodeUnsignedImpl(m: *Machine, bytes_be: []const u8) BifError!Term {
    if (bytes_be.len == 0) return error.Badarg;
    if (bytes_be.len > FinalTerms.max_limbs * 8) return error.Badarith; // documented bignum-cap scope limit
    var limbs: [FinalTerms.max_limbs]u64 = undefined;
    const n = bytesToLimbsBE(bytes_be, &limbs);
    return FinalTerms.intFromLimbs(&m.ctx, true, limbs[0..n]) catch error.OutOfMemory;
}

pub fn decode_unsigned_1(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try needBinary(m, args[0]);
    // Read-then-transform-then-construct: `bytesToLimbsBE` copies every byte
    // it needs into the LOCAL `limbs` array (inside `decodeUnsignedImpl`)
    // before `intFromLimbs` (the only construction) runs — `bytes` (a
    // `ctx.words` slice) is never touched again afterward, so this is safe
    // without an explicit dupe (finish-all-reads-before-construction).
    return decodeUnsignedImpl(m, bytes);
}

pub fn decode_unsigned_2(m: *Machine, args: []const Term) BifError!Term {
    const endian = try needEndianness(m, args[1]);
    const bytes = try needBinary(m, args[0]);
    if (endian == .big) return decodeUnsignedImpl(m, bytes);
    if (bytes.len == 0) return error.Badarg;
    // Reverse into an off-heap buffer first (a `m.gpa` allocation, not a
    // term construction) — still all-reads-before-construction overall.
    const rev = m.gpa.alloc(u8, bytes.len) catch return error.OutOfMemory;
    defer m.gpa.free(rev);
    for (bytes, 0..) |b, i| rev[bytes.len - 1 - i] = b;
    return decodeUnsignedImpl(m, rev);
}

// ── binary:bin_to_list/1,2,3 (NOT wired — a binary.erl library wrapper, see
// the module scope note; law-tested directly below) ───────────────────────

fn bytesToCharList(m: *Machine, bytes: []const u8) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = bytes.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, bytes[i]), acc) catch return error.OutOfMemory;
    }
    return acc;
}

fn binToListRange(m: *Machine, bin: Term, pos_i: i64, len_i: i64) BifError!Term {
    const size = FinalTerms.binSize(&m.ctx, bin);
    const r = try partRange(size, pos_i, len_i);
    const bytes = FinalTerms.binBytes(&m.ctx, bin);
    const owned = try dupeBytes(m, bytes[r.start .. r.start + r.len]);
    defer m.gpa.free(owned);
    return bytesToCharList(m, owned);
}

pub fn bin_to_list_1(m: *Machine, args: []const Term) BifError!Term {
    const bytes = try needBinary(m, args[0]);
    const owned = try dupeBytes(m, bytes); // dupe before the `cons` fold-loop
    defer m.gpa.free(owned);
    return bytesToCharList(m, owned);
}

pub fn bin_to_list_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    if (FinalTerms.kindOf(&m.ctx, args[1]) != .tuple or FinalTerms.tupleArity(&m.ctx, args[1]) != 2) return error.Badarg;
    const pos_i = try needSmallI64(FinalTerms.tupleElem(&m.ctx, args[1], 0));
    const len_i = try needSmallI64(FinalTerms.tupleElem(&m.ctx, args[1], 1));
    return binToListRange(m, args[0], pos_i, len_i);
}

pub fn bin_to_list_3(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return error.Badarg;
    const pos_i = try needSmallI64(args[1]);
    const len_i = try needSmallI64(args[2]);
    return binToListRange(m, args[0], pos_i, len_i);
}

// ============================================================================
// E2.8 LAWS
// ============================================================================

const AtomTable = ta.AtomTable;

fn expectEqlExact(m: *Machine, got: BifError!Term, want: Term) !void {
    const t = try got;
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, t, want));
}

fn listTerm(m: *Machine, elems: []const i64) !Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = elems.len;
    while (i > 0) {
        i -= 1;
        acc = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, elems[i]), acc);
    }
    return acc;
}

fn binList(m: *Machine, bins: []const []const u8) !Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = bins.len;
    while (i > 0) {
        i -= 1;
        const b = try FinalTerms.binary(&m.ctx, bins[i]);
        acc = try FinalTerms.cons(&m.ctx, b, acc);
    }
    return acc;
}

test "LAW E2.8 at/2, first/1, last/1 denote 0-based byte access; OOB/empty -> badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 3 });
    // WORKED LAW: at(<<1,2,3>>, 1) == 2.
    try expectEqlExact(&m, at_2(&m, &.{ bin, FinalTerms.int(&m.ctx, 1) }), FinalTerms.int(&m.ctx, 2));
    try expectEqlExact(&m, at_2(&m, &.{ bin, FinalTerms.int(&m.ctx, 0) }), FinalTerms.int(&m.ctx, 1));
    try std.testing.expectError(error.Badarg, at_2(&m, &.{ bin, FinalTerms.int(&m.ctx, 3) })); // OOB
    try std.testing.expectError(error.Badarg, at_2(&m, &.{ bin, FinalTerms.int(&m.ctx, -1) }));

    try expectEqlExact(&m, first_1(&m, &.{bin}), FinalTerms.int(&m.ctx, 1));
    try expectEqlExact(&m, last_1(&m, &.{bin}), FinalTerms.int(&m.ctx, 3));
    const empty = try FinalTerms.binary(&m.ctx, &.{});
    try std.testing.expectError(error.Badarg, first_1(&m, &.{empty}));
    try std.testing.expectError(error.Badarg, last_1(&m, &.{empty}));
    try std.testing.expectError(error.Badarg, at_2(&m, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 0) })); // non-binary
}

test "LAW E2.8 part/2,3 denotes a slice; negative Len counts backward; OOB -> badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 3, 4 });
    // WORKED LAW: part(<<1,2,3,4>>,1,2) == <<2,3>>.
    const want = try FinalTerms.binary(&m.ctx, &.{ 2, 3 });
    try expectEqlExact(&m, part_3(&m, &.{ bin, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) }), want);
    const pl = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) });
    try expectEqlExact(&m, part_2(&m, &.{ bin, pl }), want);

    // negative Len counts backward: part(<<1,2,3,4,5>>, 5, -2) == <<4,5>>.
    const bin5 = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 3, 4, 5 });
    const want5 = try FinalTerms.binary(&m.ctx, &.{ 4, 5 });
    try expectEqlExact(&m, part_3(&m, &.{ bin5, FinalTerms.int(&m.ctx, 5), FinalTerms.int(&m.ctx, -2) }), want5);

    // whole-binary identity.
    try expectEqlExact(&m, part_3(&m, &.{ bin, FinalTerms.int(&m.ctx, 0), FinalTerms.int(&m.ctx, 4) }), bin);

    // OOB -> badarg.
    try std.testing.expectError(error.Badarg, part_3(&m, &.{ bin, FinalTerms.int(&m.ctx, 3), FinalTerms.int(&m.ctx, 2) }));
    try std.testing.expectError(error.Badarg, part_3(&m, &.{ bin, FinalTerms.int(&m.ctx, 0), FinalTerms.int(&m.ctx, -1) }));
}

test "LAW E2.8 copy/1,2 duplicates bytes; list_to_bin/1 flattens iodata" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2 });
    try expectEqlExact(&m, copy_1(&m, &.{bin}), bin);
    const want3 = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 1, 2, 1, 2 });
    try expectEqlExact(&m, copy_2(&m, &.{ bin, FinalTerms.int(&m.ctx, 3) }), want3);
    const empty = try FinalTerms.binary(&m.ctx, &.{});
    try expectEqlExact(&m, copy_2(&m, &.{ bin, FinalTerms.int(&m.ctx, 0) }), empty);
    try std.testing.expectError(error.Badarg, copy_2(&m, &.{ bin, FinalTerms.int(&m.ctx, -1) }));

    // WORKED LAW: list_to_bin([1,<<2,3>>,4]) == <<1,2,3,4>>.
    const inner = try FinalTerms.binary(&m.ctx, &.{ 2, 3 });
    const nested = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), try FinalTerms.cons(&m.ctx, inner, try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 4), FinalTerms.nil(&m.ctx))));
    const want_flat = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 3, 4 });
    try expectEqlExact(&m, list_to_bin_1(&m, &.{nested}), want_flat);
    try std.testing.expectError(error.Badarg, list_to_bin_1(&m, &.{bin})); // non-list
}

test "LAW E2.8 referenced_byte_size/1 denotes byte_size (no over-allocation modeled)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2, 3 });
    try expectEqlExact(&m, referenced_byte_size_1(&m, &.{bin}), FinalTerms.int(&m.ctx, 3));
    try std.testing.expectError(error.Badarg, referenced_byte_size_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
}

test "LAW E2.8 longest_common_prefix/1, longest_common_suffix/1 denote the shared byte run" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const l1 = try binList(&m, &.{ "erlang", "ergonomic", "erase" });
    try expectEqlExact(&m, longest_common_prefix_1(&m, &.{l1}), FinalTerms.int(&m.ctx, 2)); // "er"
    const l2 = try binList(&m, &.{ "erlang", "fang", "clang" });
    try expectEqlExact(&m, longest_common_suffix_1(&m, &.{l2}), FinalTerms.int(&m.ctx, 3)); // "ang"

    try std.testing.expectError(error.Badarg, longest_common_prefix_1(&m, &.{FinalTerms.nil(&m.ctx)})); // empty list
    const bad = try binList(&m, &.{"x"});
    const bad_list = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), bad);
    try std.testing.expectError(error.Badarg, longest_common_prefix_1(&m, &.{bad_list})); // non-binary elem
}

test "LAW E2.8 compile_pattern/1 normalizes to a first-class Pattern arg for match/matches/split" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const abc = try FinalTerms.binary(&m.ctx, "abc");
    const compiled = try compile_pattern_1(&m, &.{abc});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, compiled) == .tuple);
    try std.testing.expect(FinalTerms.tupleArity(&m.ctx, compiled) == 2);
    try std.testing.expect(atomNameIs(&m, FinalTerms.tupleElem(&m.ctx, compiled, 0), "$binary_pattern"));

    const subj = try FinalTerms.binary(&m.ctx, "abcXabc");
    const want = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 0), FinalTerms.int(&m.ctx, 3) });
    try expectEqlExact(&m, match_2(&m, &.{ subj, compiled }), want);

    try std.testing.expectError(error.Badarg, compile_pattern_1(&m, &.{FinalTerms.nil(&m.ctx)})); // empty pattern list
}

test "LAW E2.8 match/2,3 denotes the earliest-then-longest occurrence; nomatch on absence" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const subj = try FinalTerms.binary(&m.ctx, "abcXabc");
    const pat = try FinalTerms.binary(&m.ctx, "abc");
    // WORKED LAW: match(<<"abcXabc">>, <<"abc">>) == {0,3}.
    const want = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 0), FinalTerms.int(&m.ctx, 3) });
    try expectEqlExact(&m, match_2(&m, &.{ subj, pat }), want);

    // list-of-binaries pattern: "abc" matches starting at position 0 (subj ==
    // "abcXabc"); "bc" does NOT start at 0 (subj[0..2] == "ab"), so "abc" is
    // the only match at the earliest position and wins outright.
    const patlist = try binList(&m, &.{ "bc", "abc" });
    try expectEqlExact(&m, match_2(&m, &.{ subj, patlist }), want);

    // tie-break: at the SAME start position, the LONGEST matching pattern wins.
    const subj_ab = try FinalTerms.binary(&m.ctx, "abcd");
    const patlist_tie = try binList(&m, &.{ "ab", "abcd" });
    const want_tie = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 0), FinalTerms.int(&m.ctx, 4) });
    try expectEqlExact(&m, match_2(&m, &.{ subj_ab, patlist_tie }), want_tie);

    // nomatch.
    const idx_nomatch = try atoms.intern("nomatch");
    const absent = try FinalTerms.binary(&m.ctx, "zzz");
    try expectEqlExact(&m, match_2(&m, &.{ subj, absent }), FinalTerms.atom(&m.ctx, idx_nomatch));

    // scope option restricts the search window; positions stay absolute.
    const scope_opt = try FinalTerms.cons(&m.ctx, try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("scope")), try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 4), FinalTerms.int(&m.ctx, 3) }) }), FinalTerms.nil(&m.ctx));
    const want_scoped = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 4), FinalTerms.int(&m.ctx, 3) });
    try expectEqlExact(&m, match_3(&m, &.{ subj, pat, scope_opt }), want_scoped);

    // empty Pattern -> badarg.
    try std.testing.expectError(error.Badarg, match_2(&m, &.{ subj, FinalTerms.nil(&m.ctx) }));
}

test "LAW E2.8 matches/2,3 denotes ALL non-overlapping occurrences, left to right" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const subj = try FinalTerms.binary(&m.ctx, "abcXabc");
    const pat = try FinalTerms.binary(&m.ctx, "abc");
    // WORKED LAW: matches(<<"abcXabc">>, <<"abc">>) == [{0,3},{4,3}].
    const t1 = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 0), FinalTerms.int(&m.ctx, 3) });
    const t2 = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 4), FinalTerms.int(&m.ctx, 3) });
    const want = try FinalTerms.cons(&m.ctx, t1, try FinalTerms.cons(&m.ctx, t2, FinalTerms.nil(&m.ctx)));
    try expectEqlExact(&m, matches_2(&m, &.{ subj, pat }), want);

    const absent = try FinalTerms.binary(&m.ctx, "zzz");
    try expectEqlExact(&m, matches_2(&m, &.{ subj, absent }), FinalTerms.nil(&m.ctx));
}

test "LAW E2.8 split/2,3 splits at the FIRST match by default; [global] splits at every match" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const subj = try FinalTerms.binary(&m.ctx, "a,b,c");
    const comma = try FinalTerms.binary(&m.ctx, ",");
    // WORKED LAW: split(<<"a,b,c">>, <<",">>) == [<<"a">>,<<"b,c">>].
    const want = try binList(&m, &.{ "a", "b,c" });
    try expectEqlExact(&m, split_2(&m, &.{ subj, comma }), want);

    // [global]: splits at every match.
    const global_opt = try FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, try atoms.intern("global")), FinalTerms.nil(&m.ctx));
    const want_global = try binList(&m, &.{ "a", "b", "c" });
    try expectEqlExact(&m, split_3(&m, &.{ subj, comma, global_opt }), want_global);

    // no match: [Subject] unchanged.
    const semi = try FinalTerms.binary(&m.ctx, ";");
    const want_unsplit = try FinalTerms.cons(&m.ctx, subj, FinalTerms.nil(&m.ctx));
    try expectEqlExact(&m, split_2(&m, &.{ subj, semi }), want_unsplit);
}

test "LAW gap-binary-split-trim (DIVERGENCE 693): binary:split/3 [trim] drops only TRAILING empty parts (keeps interior); [trim_all] drops EVERY empty part — byte-EQ vs OTP-30" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const comma = try FinalTerms.binary(&m.ctx, ",");
    const globalA = FinalTerms.atom(&m.ctx, try atoms.intern("global"));
    const trimA = FinalTerms.atom(&m.ctx, try atoms.intern("trim"));
    const trimAllA = FinalTerms.atom(&m.ctx, try atoms.intern("trim_all"));
    const optsTrim = try FinalTerms.cons(&m.ctx, globalA, try FinalTerms.cons(&m.ctx, trimA, FinalTerms.nil(&m.ctx)));
    const optsTrimAll = try FinalTerms.cons(&m.ctx, globalA, try FinalTerms.cons(&m.ctx, trimAllA, FinalTerms.nil(&m.ctx)));

    // "a,,b,," → [trim] keeps the INTERIOR empty, drops the two TRAILING empties.
    const subj1 = try FinalTerms.binary(&m.ctx, "a,,b,,");
    try expectEqlExact(&m, split_3(&m, &.{ subj1, comma, optsTrim }), try binList(&m, &.{ "a", "", "b" }));
    // [trim_all] drops EVERY empty (interior + trailing).
    try expectEqlExact(&m, split_3(&m, &.{ subj1, comma, optsTrimAll }), try binList(&m, &.{ "a", "b" }));
    // ",a," [trim_all] → the LEADING and trailing empties are both gone.
    const subj2 = try FinalTerms.binary(&m.ctx, ",a,");
    try expectEqlExact(&m, split_3(&m, &.{ subj2, comma, optsTrimAll }), try binList(&m, &.{"a"}));
    // an EMPTY subject + [trim] → [] (the lone trailing empty part removed).
    const empty = try FinalTerms.binary(&m.ctx, "");
    const optsTrimOnly = try FinalTerms.cons(&m.ctx, trimA, FinalTerms.nil(&m.ctx));
    try expectEqlExact(&m, split_3(&m, &.{ empty, comma, optsTrimOnly }), FinalTerms.nil(&m.ctx));
}

test "LAW E2.8 encode_unsigned/decode_unsigned: big-endian denotation and round-trip (small + bignum, both endiannesses)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // WORKED LAW: decode_unsigned(<<1,0>>) == 256; encode_unsigned(256) == <<1,0>>.
    const two56 = try FinalTerms.binary(&m.ctx, &.{ 1, 0 });
    try expectEqlExact(&m, encode_unsigned_1(&m, &.{FinalTerms.int(&m.ctx, 256)}), two56);
    try expectEqlExact(&m, decode_unsigned_1(&m, &.{two56}), FinalTerms.int(&m.ctx, 256));

    // zero.
    const zero_bin = try FinalTerms.binary(&m.ctx, &.{0});
    try expectEqlExact(&m, encode_unsigned_1(&m, &.{FinalTerms.int(&m.ctx, 0)}), zero_bin);
    try expectEqlExact(&m, decode_unsigned_1(&m, &.{zero_bin}), FinalTerms.int(&m.ctx, 0));

    // little-endian.
    const little_bin = try FinalTerms.binary(&m.ctx, &.{ 0, 1 });
    const little_atom = FinalTerms.atom(&m.ctx, try atoms.intern("little"));
    try expectEqlExact(&m, encode_unsigned_2(&m, &.{ FinalTerms.int(&m.ctx, 256), little_atom }), little_bin);
    try expectEqlExact(&m, decode_unsigned_2(&m, &.{ little_bin, little_atom }), FinalTerms.int(&m.ctx, 256));

    // ROUND-TRIP over small ints (fuzzed) and a genuine bignum operand.
    var prng = std.Random.DefaultPrng.init(0xB146);
    const random = prng.random();
    for (0..100) |_| {
        // Bounded to the SMALL-int range (`fitsSmall`, `[-2^59, 2^59)`, see
        // `term_algebra.int`'s assertion) — non-negative only (encode_unsigned
        // is unsigned-only).
        const v = random.uintLessThan(u64, 1 << 59);
        const n = FinalTerms.int(&m.ctx, @intCast(v));
        const enc = try encode_unsigned_1(&m, &.{n});
        const back = try decode_unsigned_1(&m, &.{enc});
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, back, n));
        const enc_l = try encode_unsigned_2(&m, &.{ n, little_atom });
        const back_l = try decode_unsigned_2(&m, &.{ enc_l, little_atom });
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, back_l, n));
    }
    // a genuine bignum (beyond i64/small range).
    const big = try FinalTerms.intFromI128(&m.ctx, 1 << 100);
    const enc_big = try encode_unsigned_1(&m, &.{big});
    const back_big = try decode_unsigned_1(&m, &.{enc_big});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, back_big, big));

    // Rejections: negative operand, empty decode source.
    try std.testing.expectError(error.Badarg, encode_unsigned_1(&m, &.{FinalTerms.int(&m.ctx, -1)}));
    const empty = try FinalTerms.binary(&m.ctx, &.{});
    try std.testing.expectError(error.Badarg, decode_unsigned_1(&m, &.{empty}));

    // bignum-cap scope limit: a source binary longer than 8192 bytes -> badarith.
    var huge_buf: [8193]u8 = @splat(1);
    const huge = try FinalTerms.binary(&m.ctx, &huge_buf);
    try std.testing.expectError(error.Badarith, decode_unsigned_1(&m, &.{huge}));
}

test "LAW E2.8 bin_to_list/1,2,3 (unwired library wrapper) denotes byte lists over a range" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bin = try FinalTerms.binary(&m.ctx, &.{ 1, 2 });
    // WORKED LAW: bin_to_list(<<1,2>>) == [1,2].
    const want = try listTerm(&m, &.{ 1, 2 });
    try expectEqlExact(&m, bin_to_list_1(&m, &.{bin}), want);

    const bin4 = try FinalTerms.binary(&m.ctx, &.{ 10, 20, 30, 40 });
    const want_mid = try listTerm(&m, &.{ 20, 30 });
    try expectEqlExact(&m, bin_to_list_3(&m, &.{ bin4, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) }), want_mid);
    const pl = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) });
    try expectEqlExact(&m, bin_to_list_2(&m, &.{ bin4, pl }), want_mid);
}
