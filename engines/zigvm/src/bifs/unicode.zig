//! # bifs/unicode — the `unicode:` chardata BIF family (E2.12)
//!
//! ## Signature
//! Same contract as every other family module: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term`. Wired to
//! `unicode.zig` (M9 — `encodeCp`/`decodeCp`, the strict UTF-8 codec).
//!
//! ## Scope — the pin's ACTUAL `unicode:` bif.tab rows
//! Grepping the pinned `bif.tab` shows only THREE `unicode:` rows:
//! `characters_to_binary/2`, `characters_to_list/2`, `bin_is_7bit/1`. The
//! `/1`/`/3` arities and the `characters_to_nfc_list`/etc. normalization
//! family named in the task brief are `unicode.erl` LIBRARY wrappers around
//! these (confirmed by reading `third_party/otp/lib/stdlib/src/unicode.erl`:
//! `characters_to_binary/1` calls `characters_to_binary/2` with
//! `Encoding=unicode`; the normalization functions are pure Erlang over
//! `characters_to_list/1` + table lookups) — NOT bif.tab entries themselves,
//! so wiring them here would claim a table row that does not exist (the
//! same "library wrapper" shape as `maps:new/0`/`binary:bin_to_list/1` in
//! earlier E2 tasks). This module implements exactly the three real rows.
//!
//! ## Chardata walk — a deliberately SCOPED reuse of `unicode.zig`
//! `InEncoding` ∈ `{unicode, utf8, latin1}` (`unicode`/`utf8` both mean "the
//! bytes/binary elements are UTF-8"; `latin1` means "every int/byte IS a
//! codepoint 0..255", needing no `unicode.zig` codec at all). `Data` is
//! chardata: a proper (or binary-tailed) list of codepoint ints, binaries
//! (each decoded whole, via `unicode.decodeCp`), and nested sublists — or a
//! bare binary. Byte slices read via `FinalTerms.binBytes` are DUPED
//! (`m.gpa.dupe`) before any `ctx`-heap-growing call, the E2.5+ lifetime
//! lesson (see `bifs/conv.zig`'s `binary_to_list_1` note) — a `cons`/
//! `tuple`/`binary` call inside the walk can grow `ctx.words` and dangle an
//! un-duped slice.
//!
//! DELIBERATE SIMPLIFICATION (documented, not hidden): a UTF-8 sequence
//! truncated at the tail of one binary element that could in principle
//! continue into a LATER chardata element (cross-binary-boundary streaming)
//! is reported as `{error,...}`, not stitched across the boundary — the
//! `{incomplete,...}` classification is exact only for the single most
//! common shape: `Data` is (or reduces to) one binary and the truncation is
//! the LAST thing in the whole `Data` term (the `top` flag below). This
//! covers `characters_to_binary(<<truncated bytes>>, unicode)` exactly, and
//! errs toward `{error,...}` (a real, valid BEAM outcome shape) rather than
//! silently accepting invalid input.
//!
//! ## Laws (see the suite below)
//!   - ROUND-TRIP: `characters_to_binary("abc", unicode) == <<"abc">>`.
//!   - LATIN1: `characters_to_binary([16#E9], latin1) == <<16#C3,16#A9>>`
//!     (é in UTF-8) — latin1 byte 0xE9 IS codepoint U+00E9.
//!   - ERROR SHAPE: an invalid element yields `{error, Good, Rest}`, never a
//!     bare `badarg`, with `Good` = the successfully converted prefix.
//!   - INCOMPLETE SHAPE: a truncated UTF-8 tail (with nothing following)
//!     yields `{incomplete, Good, RestBytes}`.
//!   - BIN_IS_7BIT: `true` iff every byte is `< 0x80`; non-binary → badarg.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const uni = @import("../unicode.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

fn boolTerm(m: *Machine, cond: bool) Term {
    return FinalTerms.atom(&m.ctx, if (cond) m.bool_true else m.bool_false);
}

const Enc = enum { latin1, utf8 };

fn parseEncoding(m: *Machine, w: Term) ?Enc {
    if (!FinalTerms.repIsAtom(w)) return null;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(w));
    if (std.mem.eql(u8, name, "latin1")) return .latin1;
    if (std.mem.eql(u8, name, "utf8")) return .utf8;
    if (std.mem.eql(u8, name, "unicode")) return .utf8;
    return null;
}

const Outcome = enum { ok, err, incomplete };
const WalkOut = struct { outcome: Outcome, rest: Term };

/// Walk chardata `data`, appending decoded codepoints to `cps`. `top` marks
/// "nothing else follows this piece" — see the module doc comment's
/// incomplete-vs-error scope note.
fn walk(m: *Machine, enc: Enc, data: Term, cps: *std.ArrayList(u21), top: bool) BifError!WalkOut {
    switch (FinalTerms.kindOf(&m.ctx, data)) {
        .nil => return .{ .outcome = .ok, .rest = data },
        .binary => {
            // Dupe off-heap first — the walk's `cons`/`binary` allocations
            // below can grow `ctx.words` and dangle a `binBytes` slice.
            const owned = m.gpa.dupe(u8, FinalTerms.binBytes(&m.ctx, data)) catch return error.OutOfMemory;
            defer m.gpa.free(owned);
            var pos: usize = 0;
            while (pos < owned.len) {
                switch (enc) {
                    .latin1 => {
                        cps.append(m.gpa, owned[pos]) catch return error.OutOfMemory;
                        pos += 1;
                    },
                    .utf8 => {
                        const r = uni.decodeCp(owned[pos..]) catch |e| {
                            const rest_bin = FinalTerms.binary(&m.ctx, owned[pos..]) catch return error.OutOfMemory;
                            return .{ .outcome = if (e == error.Truncated and top) .incomplete else .err, .rest = rest_bin };
                        };
                        cps.append(m.gpa, r.cp) catch return error.OutOfMemory;
                        pos += r.len;
                    },
                }
            }
            return .{ .outcome = .ok, .rest = data };
        },
        .cons => {
            var cur = data;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
                const h = FinalTerms.listHead(&m.ctx, cur);
                const tail = FinalTerms.listTail(&m.ctx, cur);
                const tail_is_nil = FinalTerms.kindOf(&m.ctx, tail) == .nil;
                switch (FinalTerms.kindOf(&m.ctx, h)) {
                    .cons, .nil, .binary => {
                        const r = try walk(m, enc, h, cps, top and tail_is_nil);
                        if (r.outcome != .ok) return r;
                    },
                    else => {
                        if (!FinalTerms.repIsSmall(h)) return .{ .outcome = .err, .rest = cur };
                        const v = FinalTerms.smallValOf(h);
                        const bad = switch (enc) {
                            .latin1 => v < 0 or v > 255,
                            .utf8 => v < 0 or v > 0x10FFFF or (v >= 0xD800 and v <= 0xDFFF),
                        };
                        if (bad) return .{ .outcome = .err, .rest = cur };
                        cps.append(m.gpa, @intCast(v)) catch return error.OutOfMemory;
                    },
                }
                cur = tail;
            }
            return switch (FinalTerms.kindOf(&m.ctx, cur)) {
                .nil => .{ .outcome = .ok, .rest = cur },
                .binary => try walk(m, enc, cur, cps, top),
                else => .{ .outcome = .err, .rest = cur },
            };
        },
        else => return .{ .outcome = .err, .rest = data },
    }
}

fn encodeCps(m: *Machine, cps: []const u21) BifError![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(m.gpa);
    for (cps) |cp| {
        var buf: [4]u8 = undefined;
        // cps only ever holds values this walk already validated as legal
        // codepoints (0..255 for latin1, strict-UTF-8-legal for utf8), so
        // `encodeCp` cannot fail here.
        const n = uni.encodeCp(cp, &buf) catch unreachable;
        out.appendSlice(m.gpa, buf[0..n]) catch return error.OutOfMemory;
    }
    return out.toOwnedSlice(m.gpa) catch error.OutOfMemory;
}

fn errTuple(m: *Machine, tag: []const u8, good: Term, rest: Term) BifError!Term {
    const idx = m.ctx.atoms.intern(tag) catch return error.OutOfMemory;
    const tag_atom = FinalTerms.atom(&m.ctx, idx);
    return FinalTerms.tuple(&m.ctx, &.{ tag_atom, good, rest }) catch error.OutOfMemory;
}

fn isChardataShaped(m: *Machine, data: Term) bool {
    const k = FinalTerms.kindOf(&m.ctx, data);
    return k == .cons or k == .nil or k == .binary;
}

/// `unicode:characters_to_binary(Data, InEncoding)` — output is always UTF-8.
pub fn characters_to_binary_2(m: *Machine, args: []const Term) BifError!Term {
    const data = args[0];
    const enc = parseEncoding(m, args[1]) orelse return error.Badarg;
    if (!isChardataShaped(m, data)) return error.Badarg;

    var cps: std.ArrayList(u21) = .empty;
    defer cps.deinit(m.gpa);
    const r = try walk(m, enc, data, &cps, true);

    const bytes = try encodeCps(m, cps.items);
    defer m.gpa.free(bytes);
    const good_bin = FinalTerms.binary(&m.ctx, bytes) catch return error.OutOfMemory;

    return switch (r.outcome) {
        .ok => good_bin,
        .err => errTuple(m, "error", good_bin, r.rest),
        .incomplete => errTuple(m, "incomplete", good_bin, r.rest),
    };
}

/// `unicode:characters_to_list(Data, InEncoding)` — a list of codepoint ints.
pub fn characters_to_list_2(m: *Machine, args: []const Term) BifError!Term {
    const data = args[0];
    const enc = parseEncoding(m, args[1]) orelse return error.Badarg;
    if (!isChardataShaped(m, data)) return error.Badarg;

    var cps: std.ArrayList(u21) = .empty;
    defer cps.deinit(m.gpa);
    const r = try walk(m, enc, data, &cps, true);

    var acc = FinalTerms.nil(&m.ctx);
    var k = cps.items.len;
    while (k > 0) {
        k -= 1;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, cps.items[k]), acc) catch return error.OutOfMemory;
    }

    return switch (r.outcome) {
        .ok => acc,
        .err => errTuple(m, "error", acc, r.rest),
        .incomplete => errTuple(m, "incomplete", acc, r.rest),
    };
}

/// `unicode:bin_is_7bit/1` — `true` iff `args[0]` is a binary whose every byte is
/// `< 0x80`. A NON-BINARY argument is `false`, NOT badarg (DIVERGENCE 686): OTP's
/// `unicode.erl` `no_conversion_needed(ML, latin1, utf8)` is `true andalso
/// unicode:bin_is_7bit(ML)` where `ML` is often a LIST (the input to
/// `characters_to_binary(List, latin1, utf8)`) — a badarg there aborts the
/// bread-and-butter latin1→utf8 conversion; `false` lets the andalso fall through
/// to the real conversion (host-verified: `bin_is_7bit([233])`==`bin_is_7bit(<<200>>)`==`false`).
pub fn bin_is_7bit_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsBinary(&m.ctx, args[0])) return boolTerm(m, false);
    const bytes = FinalTerms.binBytes(&m.ctx, args[0]);
    for (bytes) |b| {
        if (b >= 0x80) return boolTerm(m, false);
    }
    return boolTerm(m, true);
}

// ============================================================================
// Laws
// ============================================================================

const AtomTable = ta.AtomTable;

fn expectAtomName(m: *Machine, w: Term, want: []const u8) !void {
    try std.testing.expect(FinalTerms.repIsAtom(w));
    try std.testing.expectEqualStrings(want, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(w)));
}

test "LAW E2.12 characters_to_binary/2: round-trip, latin1, and error/incomplete tuples" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const unicode_atom = FinalTerms.atom(&m.ctx, try atoms.intern("unicode"));
    const latin1_atom = FinalTerms.atom(&m.ctx, try atoms.intern("latin1"));

    // "abc" as a codepoint list, unicode encoding.
    const abc = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 'a'), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 'b'), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 'c'), FinalTerms.nil(&m.ctx))));
    const bin1 = try characters_to_binary_2(&m, &.{ abc, unicode_atom });
    try std.testing.expect(std.mem.eql(u8, "abc", FinalTerms.binBytes(&m.ctx, bin1)));

    // a bare binary passes through unchanged (already UTF-8).
    const raw = try FinalTerms.binary(&m.ctx, "héllo");
    const bin2 = try characters_to_binary_2(&m, &.{ raw, unicode_atom });
    try std.testing.expect(std.mem.eql(u8, "héllo", FinalTerms.binBytes(&m.ctx, bin2)));

    // latin1: byte 0xE9 (é in Latin-1) becomes the 2-byte UTF-8 encoding.
    const latin1_list = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 0xE9), FinalTerms.nil(&m.ctx));
    const bin3 = try characters_to_binary_2(&m, &.{ latin1_list, latin1_atom });
    try std.testing.expect(std.mem.eql(u8, &.{ 0xC3, 0xA9 }, FinalTerms.binBytes(&m.ctx, bin3)));

    // error tuple: a surrogate codepoint mid-list.
    const bad_list = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 'a'), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 0xD800), FinalTerms.nil(&m.ctx)));
    const err_result = try characters_to_binary_2(&m, &.{ bad_list, unicode_atom });
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, err_result) == .tuple);
    try std.testing.expectEqual(@as(usize, 3), FinalTerms.tupleArity(&m.ctx, err_result));
    try expectAtomName(&m, FinalTerms.tupleElem(&m.ctx, err_result, 0), "error");
    try std.testing.expect(std.mem.eql(u8, "a", FinalTerms.binBytes(&m.ctx, FinalTerms.tupleElem(&m.ctx, err_result, 1))));

    // incomplete tuple: a truncated 2-byte UTF-8 sequence at the very tail.
    const truncated = try FinalTerms.binary(&m.ctx, &.{0xC3});
    const inc_result = try characters_to_binary_2(&m, &.{ truncated, unicode_atom });
    try expectAtomName(&m, FinalTerms.tupleElem(&m.ctx, inc_result, 0), "incomplete");

    // badarg: unrecognized encoding atom; non-chardata top-level Data.
    try std.testing.expectError(error.Badarg, characters_to_binary_2(&m, &.{ abc, FinalTerms.atom(&m.ctx, try atoms.intern("bogus")) }));
    try std.testing.expectError(error.Badarg, characters_to_binary_2(&m, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("x")), unicode_atom }));
}

test "LAW E2.12 characters_to_list/2: TERM round-trip against unicode.zig's utf8ToList" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const unicode_atom = FinalTerms.atom(&m.ctx, try atoms.intern("unicode"));
    const bin = try FinalTerms.binary(&m.ctx, "abc");
    const got = try characters_to_list_2(&m, &.{ bin, unicode_atom });
    const want = try uni.utf8ToList(gpa, &m.ctx, bin);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got, want));

    // error tuple over a non-chardata element (an atom in the list).
    const bad = try FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, try atoms.intern("nope")), FinalTerms.nil(&m.ctx));
    const err_result = try characters_to_list_2(&m, &.{ bad, unicode_atom });
    try expectAtomName(&m, FinalTerms.tupleElem(&m.ctx, err_result, 0), "error");
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, err_result, 1), FinalTerms.nil(&m.ctx)));
}

test "LAW E2.12 bin_is_7bit/1: true iff every byte < 0x80" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const ascii = try FinalTerms.binary(&m.ctx, "hello");
    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(try bin_is_7bit_1(&m, &.{ascii})));
    const hi = try FinalTerms.binary(&m.ctx, &.{ 'h', 0xC3, 0xA9 });
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try bin_is_7bit_1(&m, &.{hi})));
    // DIVERGENCE 686: a NON-BINARY argument is `false`, NOT badarg (host-verified
    // vs OTP) — so OTP's `no_conversion_needed(List, latin1, utf8)` andalso-chain
    // falls through to the real latin1→utf8 conversion instead of aborting.
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try bin_is_7bit_1(&m, &.{FinalTerms.int(&m.ctx, 1)}))); // an integer
    const list233 = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 233), FinalTerms.nil(&m.ctx));
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try bin_is_7bit_1(&m, &.{list233}))); // the [233] latin1 list
    const anatom = FinalTerms.atom(&m.ctx, try atoms.intern("nope"));
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(try bin_is_7bit_1(&m, &.{anatom}))); // an atom
}
