//! beam-zig M9 / S9: **unicode** (cf. erts erl_unicode.c) — the
//! charlist ↔ UTF-8-binary algebra.
//!
//! Signature:
//!   encodeCp  : codepoint -> bytes         (1..4 bytes)
//!   decodeCp  : bytes -> (codepoint, len)  (strict)
//!   listToUtf8 / utf8ToList : the characters_to_binary/list pair over
//!   the term algebra (codepoint lists ↔ binaries)
//!   normalizeUtf8 : NormalForm × bytes -> bytes (strict UTF-8 in/out)
//!
//! Laws:
//!   ROUND-TRIP      decode∘encode = id over every valid codepoint
//!                   (0..0x10FFFF minus surrogates)
//!   ORACLE          our hand-rolled decoder agrees with std.unicode on
//!                   random valid strings (initial encoding = std, final =
//!                   ours; the usual two-encodings discipline)
//!   STRICTNESS      overlong forms, surrogates, truncated sequences, and
//!                   >0x10FFFF are rejected with named errors — never
//!                   silently accepted (erts is strict here too)
//!   TERM ROUND-TRIP utf8ToList(listToUtf8(cps)) ≡ cps as TERMS (through
//!                   the M4 term algebra: lists of small ints ↔ binaries)
//!   NORMALIZATION   NFC/NFD are idempotent; canonical equivalents normalize
//!                   to equal UTF-8; canonical combining classes are ordered;
//!                   invalid UTF-8 is rejected before normalization.
//!   CASE MAPPING    toUpper/toLower/toTitle are TOTAL (identity outside the
//!                   table); each is idempotent; and case conversion is NOT a
//!                   universal involution — the round-trippable subset is the
//!                   cased letters, with real exceptions (µ, İ, Kelvin/Angstrom
//!                   signs, …) enumerated FROM the table itself.
//!
//! Scope: normalization is a table-driven canonical slice (NFC/NFD) covering
//! common Latin-1 canonical pairs and the Angstrom compatibility spelling used
//! as a canonical-equivalence regression. The law shape is deliberately the
//! full Unicode shape: expand the tables, not the proof strategy.
//!
//! CASE TABLES (E3.17 — S9 "big Unicode tables"): the SIMPLE (1:1) upper/lower/
//! title mappings for every codepoint the pinned Unicode data assigns one live in
//! the GENERATED `unicode_tables.zig` (2989 rows, all planes), emitted by the
//! OCaml harness `--gen-unicode-table` from the pin's
//! `lib/stdlib/uc_spec/UnicodeData.txt` (fields 12/13/14) and byte-checked against
//! a regenerate by the harness freshness law — the `bif_table.zig` precedent
//! (semantics stay Zig; data derives from the pin). `toUpper`/`toLower`/`toTitle`
//! are total binary-search lookups extended by identity outside the table.
//! DELIBERATE RESIDUAL (documented, not hidden): the one-to-many FULL case
//! mappings (ß→SS, final-sigma context, the SpecialCasing.txt family) and the
//! general-category classification tables are OUT of this slice — `string:`
//! full-casing + `unicode_util` category predicates are library functions that
//! need E4 code loading before any runtime path reaches them, so the simple
//! mappings are the exact, tested surface here.

const std = @import("std");
const ta = @import("term_algebra.zig");
const tables = @import("unicode_tables.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;

pub const Utf8Error = error{ Overlong, Surrogate, OutOfRange, Truncated, BadByte };

pub const NormalForm = enum { nfd, nfc };

const Decomp = struct {
    cp: u21,
    xs: []const u21,
};

const Compose = struct {
    starter: u21,
    mark: u21,
    cp: u21,
};

const decomp_table = [_]Decomp{
    .{ .cp = 0x00C0, .xs = &.{ 0x0041, 0x0300 } }, // A grave
    .{ .cp = 0x00C1, .xs = &.{ 0x0041, 0x0301 } }, // A acute
    .{ .cp = 0x00C5, .xs = &.{ 0x0041, 0x030A } }, // A ring
    .{ .cp = 0x00C7, .xs = &.{ 0x0043, 0x0327 } }, // C cedilla
    .{ .cp = 0x00C8, .xs = &.{ 0x0045, 0x0300 } }, // E grave
    .{ .cp = 0x00C9, .xs = &.{ 0x0045, 0x0301 } }, // E acute
    .{ .cp = 0x00D1, .xs = &.{ 0x004E, 0x0303 } }, // N tilde
    .{ .cp = 0x00D6, .xs = &.{ 0x004F, 0x0308 } }, // O diaeresis
    .{ .cp = 0x00DC, .xs = &.{ 0x0055, 0x0308 } }, // U diaeresis
    .{ .cp = 0x00E0, .xs = &.{ 0x0061, 0x0300 } }, // a grave
    .{ .cp = 0x00E1, .xs = &.{ 0x0061, 0x0301 } }, // a acute
    .{ .cp = 0x00E5, .xs = &.{ 0x0061, 0x030A } }, // a ring
    .{ .cp = 0x00E7, .xs = &.{ 0x0063, 0x0327 } }, // c cedilla
    .{ .cp = 0x00E8, .xs = &.{ 0x0065, 0x0300 } }, // e grave
    .{ .cp = 0x00E9, .xs = &.{ 0x0065, 0x0301 } }, // e acute
    .{ .cp = 0x00F1, .xs = &.{ 0x006E, 0x0303 } }, // n tilde
    .{ .cp = 0x00F6, .xs = &.{ 0x006F, 0x0308 } }, // o diaeresis
    .{ .cp = 0x00FC, .xs = &.{ 0x0075, 0x0308 } }, // u diaeresis
    .{ .cp = 0x212B, .xs = &.{ 0x0041, 0x030A } }, // Angstrom sign
};

const compose_table = [_]Compose{
    .{ .starter = 0x0041, .mark = 0x0300, .cp = 0x00C0 },
    .{ .starter = 0x0041, .mark = 0x0301, .cp = 0x00C1 },
    .{ .starter = 0x0041, .mark = 0x030A, .cp = 0x00C5 },
    .{ .starter = 0x0043, .mark = 0x0327, .cp = 0x00C7 },
    .{ .starter = 0x0045, .mark = 0x0300, .cp = 0x00C8 },
    .{ .starter = 0x0045, .mark = 0x0301, .cp = 0x00C9 },
    .{ .starter = 0x004E, .mark = 0x0303, .cp = 0x00D1 },
    .{ .starter = 0x004F, .mark = 0x0308, .cp = 0x00D6 },
    .{ .starter = 0x0055, .mark = 0x0308, .cp = 0x00DC },
    .{ .starter = 0x0061, .mark = 0x0300, .cp = 0x00E0 },
    .{ .starter = 0x0061, .mark = 0x0301, .cp = 0x00E1 },
    .{ .starter = 0x0061, .mark = 0x030A, .cp = 0x00E5 },
    .{ .starter = 0x0063, .mark = 0x0327, .cp = 0x00E7 },
    .{ .starter = 0x0065, .mark = 0x0300, .cp = 0x00E8 },
    .{ .starter = 0x0065, .mark = 0x0301, .cp = 0x00E9 },
    .{ .starter = 0x006E, .mark = 0x0303, .cp = 0x00F1 },
    .{ .starter = 0x006F, .mark = 0x0308, .cp = 0x00F6 },
    .{ .starter = 0x0075, .mark = 0x0308, .cp = 0x00FC },
};

fn combiningClass(cp: u21) u8 {
    return switch (cp) {
        0x0327 => 202, // cedilla
        0x0300, 0x0301, 0x0303, 0x0308, 0x030A => 230,
        else => 0,
    };
}

fn decompFor(cp: u21) ?[]const u21 {
    for (decomp_table) |d| if (d.cp == cp) return d.xs;
    return null;
}

fn composePair(starter: u21, mark: u21) ?u21 {
    for (compose_table) |c| {
        if (c.starter == starter and c.mark == mark) return c.cp;
    }
    return null;
}

fn appendDecomposed(gpa: std.mem.Allocator, out: *std.ArrayList(u21), cp: u21) !void {
    if (decompFor(cp)) |xs| {
        for (xs) |x| try appendDecomposed(gpa, out, x);
        return;
    }
    try out.append(gpa, cp);
    const cc = combiningClass(cp);
    if (cc == 0) return;
    var i = out.items.len - 1;
    while (i > 0) : (i -= 1) {
        const prev_cc = combiningClass(out.items[i - 1]);
        if (prev_cc == 0 or prev_cc <= cc) break;
        std.mem.swap(u21, &out.items[i], &out.items[i - 1]);
    }
}

fn decodeAll(gpa: std.mem.Allocator, bs: []const u8) !std.ArrayList(u21) {
    var out: std.ArrayList(u21) = .empty;
    errdefer out.deinit(gpa);
    var pos: usize = 0;
    while (pos < bs.len) {
        const r = try decodeCp(bs[pos..]);
        try appendDecomposed(gpa, &out, r.cp);
        pos += r.len;
    }
    return out;
}

fn composeCanonical(gpa: std.mem.Allocator, decomposed: []const u21) !std.ArrayList(u21) {
    var out: std.ArrayList(u21) = .empty;
    errdefer out.deinit(gpa);
    var starter_idx: ?usize = null;
    var last_cc: u8 = 0;
    for (decomposed) |cp| {
        const cc = combiningClass(cp);
        if (starter_idx) |si| {
            const blocked = last_cc != 0 and last_cc >= cc;
            if (cc != 0 and !blocked) {
                if (composePair(out.items[si], cp)) |composed| {
                    out.items[si] = composed;
                    last_cc = cc;
                    continue;
                }
            }
        }
        try out.append(gpa, cp);
        if (cc == 0) {
            starter_idx = out.items.len - 1;
            last_cc = 0;
        } else {
            last_cc = cc;
        }
    }
    return out;
}

fn encodeAll(gpa: std.mem.Allocator, cps: []const u21) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (cps) |cp| {
        var buf: [4]u8 = undefined;
        const n = try encodeCp(cp, &buf);
        try out.appendSlice(gpa, buf[0..n]);
    }
    return out.toOwnedSlice(gpa);
}

/// Encode one codepoint (validated) into 1..4 bytes; returns the length.
pub fn encodeCp(cp: u21, out: *[4]u8) Utf8Error!usize {
    if (cp >= 0xD800 and cp <= 0xDFFF) return error.Surrogate;
    if (cp > 0x10FFFF) return error.OutOfRange;
    if (cp < 0x80) {
        out[0] = @intCast(cp);
        return 1;
    }
    if (cp < 0x800) {
        out[0] = @intCast(0xC0 | (cp >> 6));
        out[1] = @intCast(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = @intCast(0xE0 | (cp >> 12));
        out[1] = @intCast(0x80 | ((cp >> 6) & 0x3F));
        out[2] = @intCast(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = @intCast(0xF0 | (cp >> 18));
    out[1] = @intCast(0x80 | ((cp >> 12) & 0x3F));
    out[2] = @intCast(0x80 | ((cp >> 6) & 0x3F));
    out[3] = @intCast(0x80 | (cp & 0x3F));
    return 4;
}

/// Strict decoder: exactly one codepoint from the front of `bs`.
pub fn decodeCp(bs: []const u8) Utf8Error!struct { cp: u21, len: usize } {
    if (bs.len == 0) return error.Truncated;
    const b0 = bs[0];
    if (b0 < 0x80) return .{ .cp = b0, .len = 1 };
    if (b0 < 0xC0) return error.BadByte; // stray continuation
    var need: usize = undefined;
    var cp: u21 = undefined;
    if (b0 < 0xE0) {
        need = 1;
        cp = b0 & 0x1F;
    } else if (b0 < 0xF0) {
        need = 2;
        cp = b0 & 0x0F;
    } else if (b0 < 0xF8) {
        need = 3;
        cp = b0 & 0x07;
    } else return error.BadByte;
    if (bs.len < 1 + need) return error.Truncated;
    for (bs[1 .. 1 + need]) |b| {
        if (b & 0xC0 != 0x80) return error.BadByte;
        cp = (cp << 6) | @as(u21, b & 0x3F);
    }
    // strictness
    const min: u21 = switch (need) {
        1 => 0x80,
        2 => 0x800,
        3 => 0x10000,
        else => unreachable,
    };
    if (cp < min) return error.Overlong;
    if (cp >= 0xD800 and cp <= 0xDFFF) return error.Surrogate;
    if (cp > 0x10FFFF) return error.OutOfRange;
    return .{ .cp = cp, .len = 1 + need };
}

/// characters_to_binary: a proper list of codepoints → UTF-8 binary term.
pub fn listToUtf8(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, l: FinalTerms.Term) !FinalTerms.Term {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    var cur = l;
    while (FinalTerms.kindOf(ctx, cur) == .cons) {
        const h = FinalTerms.listHead(ctx, cur);
        if (!FinalTerms.repIsSmall(h)) return error.BadArg;
        const v = FinalTerms.smallValOf(h);
        if (v < 0 or v > 0x10FFFF) return error.BadArg;
        var buf: [4]u8 = undefined;
        const n = encodeCp(@intCast(v), &buf) catch return error.BadArg;
        try out.appendSlice(gpa, buf[0..n]);
        cur = FinalTerms.listTail(ctx, cur);
    }
    if (FinalTerms.kindOf(ctx, cur) != .nil) return error.BadArg;
    return FinalTerms.binary(ctx, out.items);
}

/// characters_to_list: a UTF-8 binary term → proper list of codepoints.
pub fn utf8ToList(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, b: FinalTerms.Term) !FinalTerms.Term {
    const bs = FinalTerms.binBytes(ctx, b);
    var cps: std.ArrayList(u21) = .empty;
    defer cps.deinit(gpa);
    var pos: usize = 0;
    while (pos < bs.len) {
        const r = decodeCp(bs[pos..]) catch return error.BadArg;
        try cps.append(gpa, r.cp);
        pos += r.len;
    }
    var acc = FinalTerms.nil(ctx);
    var k = cps.items.len;
    while (k > 0) {
        k -= 1;
        acc = try FinalTerms.cons(ctx, FinalTerms.int(ctx, cps.items[k]), acc);
    }
    return acc;
}

/// Normalize strict UTF-8 bytes into the requested canonical form.
/// Caller owns the returned slice.
pub fn normalizeUtf8(gpa: std.mem.Allocator, bs: []const u8, form: NormalForm) ![]u8 {
    var decomposed = try decodeAll(gpa, bs);
    defer decomposed.deinit(gpa);
    switch (form) {
        .nfd => return encodeAll(gpa, decomposed.items),
        .nfc => {
            var composed = try composeCanonical(gpa, decomposed.items);
            defer composed.deinit(gpa);
            return encodeAll(gpa, composed.items);
        },
    }
}

/// Normalize a UTF-8 binary term, returning a binary term.
pub fn normalizeBinary(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, b: FinalTerms.Term, form: NormalForm) !FinalTerms.Term {
    const normalized = normalizeUtf8(gpa, FinalTerms.binBytes(ctx, b), form) catch return error.BadArg;
    defer gpa.free(normalized);
    return FinalTerms.binary(ctx, normalized);
}

// ============================================================================
// Case mapping (E3.17) — total simple upper/lower/title over `unicode_tables.zig`
// ============================================================================

/// Binary-search the codepoint-sorted case table for `cp`. The table's strict
/// monotonicity (asserted by the SORTED law below, and by the generator's own
/// sort) is this search's precondition.
fn caseEntryFor(cp: u21) ?tables.CaseEntry {
    var lo: usize = 0;
    var hi: usize = tables.entries.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const e = tables.entries[mid];
        if (e.cp == cp) return e;
        if (e.cp < cp) lo = mid + 1 else hi = mid;
    }
    return null;
}

/// Simple uppercase mapping — total: identity for any codepoint the table does
/// not list (the vast majority: caseless letters, digits, CJK, symbols).
pub fn toUpper(cp: u21) u21 {
    return if (caseEntryFor(cp)) |e| e.upper else cp;
}

/// Simple lowercase mapping — total (identity outside the table).
pub fn toLower(cp: u21) u21 {
    return if (caseEntryFor(cp)) |e| e.lower else cp;
}

/// Simple titlecase mapping — total (identity outside the table).
pub fn toTitle(cp: u21) u21 {
    return if (caseEntryFor(cp)) |e| e.title else cp;
}

// ============================================================================
// Tests
// ============================================================================

fn randomCp(random: std.Random) u21 {
    while (true) {
        const cp = random.uintLessThan(u21, 0x110000);
        if (cp >= 0xD800 and cp <= 0xDFFF) continue;
        return cp;
    }
}

test "LAW round-trip + std.unicode oracle over random codepoints" {
    var prng = std.Random.DefaultPrng.init(0x0C0DE);
    const random = prng.random();

    for (0..2000) |_| {
        const cp = randomCp(random);
        var buf: [4]u8 = undefined;
        const n = try encodeCp(cp, &buf);
        // round-trip
        const back = try decodeCp(buf[0..n]);
        try std.testing.expectEqual(cp, back.cp);
        try std.testing.expectEqual(n, back.len);
        // oracle: std.unicode agrees in both directions
        var std_buf: [4]u8 = undefined;
        const std_n = try std.unicode.utf8Encode(cp, &std_buf);
        try std.testing.expectEqual(@as(usize, std_n), n);
        try std.testing.expect(std.mem.eql(u8, std_buf[0..std_n], buf[0..n]));
        const std_cp = try std.unicode.utf8Decode(buf[0..n]);
        try std.testing.expectEqual(std_cp, @as(u21, @intCast(back.cp)));
    }
}

test "STRICTNESS: overlong, surrogate, out-of-range, truncated all rejected" {
    // overlong 'A' as 2 bytes: C1 81
    try std.testing.expectError(error.Overlong, decodeCp(&.{ 0xC1, 0x81 }));
    // overlong NUL as 2 bytes: C0 80 (the classic)
    try std.testing.expectError(error.Overlong, decodeCp(&.{ 0xC0, 0x80 }));
    // surrogate D800: ED A0 80
    try std.testing.expectError(error.Surrogate, decodeCp(&.{ 0xED, 0xA0, 0x80 }));
    // 0x110000: F4 90 80 80
    try std.testing.expectError(error.OutOfRange, decodeCp(&.{ 0xF4, 0x90, 0x80, 0x80 }));
    // truncated 3-byte form
    try std.testing.expectError(error.Truncated, decodeCp(&.{ 0xE2, 0x82 }));
    // stray continuation
    try std.testing.expectError(error.BadByte, decodeCp(&.{0x80}));
    // encode side
    var buf: [4]u8 = undefined;
    try std.testing.expectError(error.Surrogate, encodeCp(0xD800, &buf));
}

test "TERM round-trip: codepoint lists ↔ UTF-8 binaries through the algebra" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();
    var prng = std.Random.DefaultPrng.init(0x1157);
    const random = prng.random();

    for (0..60) |_| {
        // random codepoint list term
        const n = random.uintLessThan(usize, 12);
        var acc = FinalTerms.nil(&ctx);
        var k: usize = n;
        var cps: [12]u21 = undefined;
        for (0..n) |i| cps[i] = randomCp(random);
        while (k > 0) {
            k -= 1;
            acc = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, cps[k]), acc);
        }
        const before = try FinalTerms.denote(&ctx, sa, acc);
        const bin = try listToUtf8(gpa, &ctx, acc);
        const back = try utf8ToList(gpa, &ctx, bin);
        try std.testing.expect(spec.eqlExact(before, try FinalTerms.denote(&ctx, sa, back)));
        // and the binary really is valid UTF-8 by the std oracle
        try std.testing.expect(std.unicode.utf8ValidateSlice(FinalTerms.binBytes(&ctx, bin)));
    }

    // badarg: a surrogate in the list, a bad binary
    const bad_list = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 0xD800), FinalTerms.nil(&ctx));
    try std.testing.expectError(error.BadArg, listToUtf8(gpa, &ctx, bad_list));
    const bad_bin = try FinalTerms.binary(&ctx, &.{ 0xC0, 0x80 });
    try std.testing.expectError(error.BadArg, utf8ToList(gpa, &ctx, bad_bin));
}

test "NORMALIZATION: NFC/NFD vectors, idempotence, and canonical equivalence" {
    const gpa = std.testing.allocator;
    const Vector = struct {
        input: []const u8,
        nfd: []const u8,
        nfc: []const u8,
    };
    const vectors = [_]Vector{
        .{
            .input = &.{ 0xC3, 0xA9 }, // e acute precomposed
            .nfd = &.{ 0x65, 0xCC, 0x81 },
            .nfc = &.{ 0xC3, 0xA9 },
        },
        .{
            .input = &.{ 0x65, 0xCC, 0x81 }, // e + acute
            .nfd = &.{ 0x65, 0xCC, 0x81 },
            .nfc = &.{ 0xC3, 0xA9 },
        },
        .{
            .input = &.{ 0xE2, 0x84, 0xAB }, // Angstrom sign
            .nfd = &.{ 0x41, 0xCC, 0x8A },
            .nfc = &.{ 0xC3, 0x85 },
        },
        .{
            .input = &.{ 0x63, 0xCC, 0xA7 }, // c + cedilla
            .nfd = &.{ 0x63, 0xCC, 0xA7 },
            .nfc = &.{ 0xC3, 0xA7 },
        },
        .{
            .input = &.{ 0x6E, 0xCC, 0x83 }, // n + tilde
            .nfd = &.{ 0x6E, 0xCC, 0x83 },
            .nfc = &.{ 0xC3, 0xB1 },
        },
        .{
            .input = &.{ 0x6F, 0xCC, 0x88 }, // o + diaeresis
            .nfd = &.{ 0x6F, 0xCC, 0x88 },
            .nfc = &.{ 0xC3, 0xB6 },
        },
    };

    for (vectors) |v| {
        const nfd = try normalizeUtf8(gpa, v.input, .nfd);
        defer gpa.free(nfd);
        try std.testing.expect(std.mem.eql(u8, v.nfd, nfd));
        try std.testing.expect(std.unicode.utf8ValidateSlice(nfd));

        const nfc = try normalizeUtf8(gpa, v.input, .nfc);
        defer gpa.free(nfc);
        try std.testing.expect(std.mem.eql(u8, v.nfc, nfc));
        try std.testing.expect(std.unicode.utf8ValidateSlice(nfc));

        const nfd2 = try normalizeUtf8(gpa, nfd, .nfd);
        defer gpa.free(nfd2);
        try std.testing.expect(std.mem.eql(u8, nfd, nfd2));

        const nfc2 = try normalizeUtf8(gpa, nfc, .nfc);
        defer gpa.free(nfc2);
        try std.testing.expect(std.mem.eql(u8, nfc, nfc2));
    }

    // Same abstract text, two spellings; both normal forms converge.
    const pre = [_]u8{ 0xC3, 0xA1 }; // a acute
    const dec = [_]u8{ 0x61, 0xCC, 0x81 };
    const pre_nfd = try normalizeUtf8(gpa, &pre, .nfd);
    defer gpa.free(pre_nfd);
    const dec_nfd = try normalizeUtf8(gpa, &dec, .nfd);
    defer gpa.free(dec_nfd);
    try std.testing.expect(std.mem.eql(u8, pre_nfd, dec_nfd));

    const pre_nfc = try normalizeUtf8(gpa, &pre, .nfc);
    defer gpa.free(pre_nfc);
    const dec_nfc = try normalizeUtf8(gpa, &dec, .nfc);
    defer gpa.free(dec_nfc);
    try std.testing.expect(std.mem.eql(u8, pre_nfc, dec_nfc));
}

test "NORMALIZATION: canonical ordering, invalid rejection, and term binary wrapper" {
    const gpa = std.testing.allocator;

    // a + acute(230) + cedilla(202) must reorder to a + cedilla + acute.
    const unordered = [_]u8{ 0x61, 0xCC, 0x81, 0xCC, 0xA7 };
    const ordered = try normalizeUtf8(gpa, &unordered, .nfd);
    defer gpa.free(ordered);
    try std.testing.expect(std.mem.eql(u8, &.{ 0x61, 0xCC, 0xA7, 0xCC, 0x81 }, ordered));

    try std.testing.expectError(error.Overlong, normalizeUtf8(gpa, &.{ 0xC0, 0x80 }, .nfc));
    try std.testing.expectError(error.Truncated, normalizeUtf8(gpa, &.{ 0xE2, 0x82 }, .nfd));

    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const decomposed = try FinalTerms.binary(&ctx, &.{ 0x65, 0xCC, 0x81 });
    const normalized = try normalizeBinary(gpa, &ctx, decomposed, .nfc);
    try std.testing.expect(std.mem.eql(u8, &.{ 0xC3, 0xA9 }, FinalTerms.binBytes(&ctx, normalized)));

    const bad_bin = try FinalTerms.binary(&ctx, &.{ 0xED, 0xA0, 0x80 });
    try std.testing.expectError(error.BadArg, normalizeBinary(gpa, &ctx, bad_bin, .nfc));
}

fn isValidCp(cp: u21) bool {
    return cp <= 0x10FFFF and !(cp >= 0xD800 and cp <= 0xDFFF);
}

test "CASE SORTED: table strictly increasing; all fields valid codepoints" {
    try std.testing.expect(tables.entries.len > 2000); // full-plane, not a stub
    var prev: i64 = -1;
    for (tables.entries) |e| {
        // strict monotonicity is the binary-search precondition
        try std.testing.expect(@as(i64, e.cp) > prev);
        prev = e.cp;
        // every mapping target is a legal (non-surrogate, in-range) codepoint
        try std.testing.expect(isValidCp(e.cp));
        try std.testing.expect(isValidCp(e.upper));
        try std.testing.expect(isValidCp(e.lower));
        try std.testing.expect(isValidCp(e.title));
        // every row is a NON-identity mapping (the generator's emission rule)
        try std.testing.expect(e.upper != e.cp or e.lower != e.cp or e.title != e.cp);
    }
}

test "CASE TOTALITY: toUpper/toLower/toTitle total over a full-range sample" {
    // Never crashes, always yields a valid codepoint, and is identity off-table.
    var prng = std.Random.DefaultPrng.init(0xCA5E);
    const random = prng.random();
    for (0..20000) |_| {
        const cp = random.uintLessThan(u21, 0x110000);
        if (!isValidCp(cp)) continue;
        try std.testing.expect(isValidCp(toUpper(cp)));
        try std.testing.expect(isValidCp(toLower(cp)));
        try std.testing.expect(isValidCp(toTitle(cp)));
        if (caseEntryFor(cp) == null) {
            try std.testing.expectEqual(cp, toUpper(cp));
            try std.testing.expectEqual(cp, toLower(cp));
            try std.testing.expectEqual(cp, toTitle(cp));
        }
    }
    // ASCII anchors
    try std.testing.expectEqual(@as(u21, 'A'), toUpper('a'));
    try std.testing.expectEqual(@as(u21, 'z'), toLower('Z'));
}

test "CASE IDEMPOTENCE: toUpper∘toUpper = toUpper (and lower/title) over the table" {
    for (tables.entries) |e| {
        try std.testing.expectEqual(toUpper(e.cp), toUpper(toUpper(e.cp)));
        try std.testing.expectEqual(toLower(e.cp), toLower(toLower(e.cp)));
        try std.testing.expectEqual(toTitle(e.cp), toTitle(toTitle(e.cp)));
    }
}

test "CASE INVOLUTION where defined — NOT universal; exceptions enumerated from the table" {
    // Round-trip counts over the cased letters. `lower_rt` = toLower(toUpper(cp))
    // returns cp (the round-trippable-DOWN subset ~ lowercase letters); `upper_rt`
    // = toUpper(toLower(cp)) returns cp (~ uppercase letters). Neither is universal.
    var lower_rt: usize = 0;
    var lower_break: usize = 0;
    var upper_rt: usize = 0;
    var upper_break: usize = 0;
    for (tables.entries) |e| {
        if (toUpper(e.cp) != e.cp) {
            if (toLower(toUpper(e.cp)) == e.cp) upper_rt += 1 else upper_break += 1;
        }
        if (toLower(e.cp) != e.cp) {
            if (toUpper(toLower(e.cp)) == e.cp) lower_rt += 1 else lower_break += 1;
        }
    }
    // The round-trippable subset is LARGE (most cased letters).
    try std.testing.expect(lower_rt > 900);
    try std.testing.expect(upper_rt > 900);
    // ...but case conversion is NOT a universal involution: real exceptions exist.
    try std.testing.expect(lower_break > 0);
    try std.testing.expect(upper_break > 0);

    // Known ROUND-TRIPPERS (letters, incl. a supplementary-plane pair).
    try std.testing.expectEqual(@as(u21, 0x0041), toUpper(0x0061)); // a->A
    try std.testing.expectEqual(@as(u21, 0x0061), toLower(toUpper(0x0061))); // a->A->a
    try std.testing.expectEqual(@as(u21, 0x0391), toUpper(0x03B1)); // α->Α
    try std.testing.expectEqual(@as(u21, 0x03B1), toLower(toUpper(0x03B1))); // α->Α->α
    // Deseret (plane 1): U+10428 small <-> U+10400 capital.
    try std.testing.expectEqual(@as(u21, 0x10400), toUpper(0x10428));
    try std.testing.expectEqual(@as(u21, 0x10428), toLower(toUpper(0x10428)));

    // Known EXCEPTIONS (round-trip DOES NOT hold) — the honest non-involution.
    // MICRO SIGN µ (U+00B5): toUpper=Μ(039C), toLower(Μ)=μ(03BC) ≠ µ.
    try std.testing.expect(toLower(toUpper(0x00B5)) != 0x00B5);
    // LATIN CAPITAL I WITH DOT ABOVE İ (U+0130): toLower=i(0069), toUpper(i)=I(0049) ≠ İ.
    try std.testing.expect(toUpper(toLower(0x0130)) != 0x0130);
    // KELVIN SIGN (U+212A) and ANGSTROM SIGN (U+212B): compat capitals.
    try std.testing.expect(toUpper(toLower(0x212A)) != 0x212A);
    try std.testing.expect(toUpper(toLower(0x212B)) != 0x212B);
}

test "CASE SUPPLEMENTARY PLANE: plane-1 case pairs present (BMP-only generator killed)" {
    // Deseret U+10400 <-> U+10428.
    const cap = caseEntryFor(0x10400) orelse return error.MissingSupplementaryRow;
    try std.testing.expectEqual(@as(u21, 0x10428), cap.lower);
    const small = caseEntryFor(0x10428) orelse return error.MissingSupplementaryRow;
    try std.testing.expectEqual(@as(u21, 0x10400), small.upper);
    // Adlam (U+1E900 block) and Warang Citi round the plane-1 coverage out.
    try std.testing.expect(toLower(0x1E900) != 0x1E900);
    // A genuinely case-mapping supplementary codepoint must exist ABOVE the BMP.
    var any_astral = false;
    for (tables.entries) |e| {
        if (e.cp > 0xFFFF) {
            any_astral = true;
            break;
        }
    }
    try std.testing.expect(any_astral);
}

test "CASE + CODEC: enlarged domain — codec round-trips every case-table target; surrogate boundary rejected" {
    // The E2.12/M9 codec laws re-asserted over the enlarged case domain: every
    // upper/lower/title target encodes and strictly decodes back (all planes).
    for (tables.entries) |e| {
        for ([_]u21{ e.cp, e.upper, e.lower, e.title }) |cp| {
            var buf: [4]u8 = undefined;
            const n = try encodeCp(cp, &buf);
            const back = try decodeCp(buf[0..n]);
            try std.testing.expectEqual(cp, back.cp);
        }
    }
    // Surrogate-adjacent boundary: U+D7FF and U+E000 encode; the surrogate block
    // itself is rejected on BOTH sides (kills a codec mutant that leaks surrogates).
    var buf: [4]u8 = undefined;
    _ = try encodeCp(0xD7FF, &buf);
    _ = try encodeCp(0xE000, &buf);
    try std.testing.expectError(error.Surrogate, encodeCp(0xD800, &buf));
    try std.testing.expectError(error.Surrogate, encodeCp(0xDFFF, &buf));
    try std.testing.expectError(error.Surrogate, decodeCp(&.{ 0xED, 0xBF, 0xBF })); // U+DFFF
}
