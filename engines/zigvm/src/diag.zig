//! beam-zig M12 / S30: **diagnostics** — the crash-dump serializer (cf. erts
//! erl_crash_dump.c, erl_process_dump.c). Stratum C by the map: a
//! serializer of already-specified state, tested by golden files. The term
//! FORMATTER inside it is the rolling S10 observation (erl_printf_term)
//! finally landing.
//!
//! Two term writers share the S10 representation-free denotation domain but
//! observe DIFFERENT erts writers: `formatValue` is the compact crash-dump/`~w`
//! shape (bare atoms, numeric lists, `.0` floats — the corpus differential);
//! `formatValueT` (E5.3) is the `%.*T` shape `erts_internal:term_to_string/2`,
//! `~p`, and `display/1` ride (single-QUOTED atoms, the printable-STRING
//! heuristic, `%e`-6 floats), a faithful port of `erl_printf_term.c` byte-
//! verified against the pinned host — see the E5.3 spot-pin law and its scope
//! note (atom-keyed small-map order is the deferred residual, DIVERGENCE 41/90).
//!
//! Laws:
//!   DETERMINISM   twin machines dump byte-identically
//!   GOLDEN        the function_clause crash from the M8 gate dumps to the
//!                 exact vendored text
//!   FORMAT        the formatter is total over every term kind and prints
//!                 Erlang-ish syntax; the S10 reader parses the stable
//!                 non-lossy subset and proves parse(format(v)) by denotation.
//!   %T-WRITER     formatValueT byte-matches erts `%.*T` on the verified subset
//!                 (atom quoting, string heuristic, `%e` floats, int-keyed maps).

const std = @import("std");
const ta = @import("term_algebra.zig");
const ia = @import("instr_algebra.zig");
const mba = @import("mailbox_algebra.zig");
const loader = @import("beam_loader.zig");
const unicode = @import("unicode.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;

// ---------------------------------------------------------------------------
// S10: the term formatter (over denotations — representation-free)
// ---------------------------------------------------------------------------

pub fn formatValue(gpa: std.mem.Allocator, v: *const spec.Value, out: *std.ArrayList(u8)) !void {
    switch (v.*) {
        .int => |b| {
            // magnitude via repeated division is overkill; use std.math.big
            var m = try b.toManaged(gpa);
            defer m.deinit();
            const s = try m.toString(gpa, 10, .lower);
            defer gpa.free(s);
            try out.appendSlice(gpa, s);
        },
        .float => |f| {
            var buf: [64]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "{d}", .{f});
            try out.appendSlice(gpa, s);
            if (std.mem.indexOfScalar(u8, s, '.') == null and
                std.mem.indexOfScalar(u8, s, 'e') == null)
                try out.appendSlice(gpa, ".0"); // floats always show a point
        },
        .atom => |name| try out.appendSlice(gpa, name),
        .nil => try out.appendSlice(gpa, "[]"),
        .cons => {
            try out.append(gpa, '[');
            var cur = v;
            var first = true;
            while (cur.* == .cons) {
                if (!first) try out.append(gpa, ',');
                try formatValue(gpa, cur.cons.head, out);
                first = false;
                cur = cur.cons.tail;
            }
            if (cur.* != .nil) { // improper tail
                try out.append(gpa, '|');
                try formatValue(gpa, cur, out);
            }
            try out.append(gpa, ']');
        },
        .tuple => |xs| {
            try out.append(gpa, '{');
            for (xs, 0..) |x, i| {
                if (i > 0) try out.append(gpa, ',');
                try formatValue(gpa, x, out);
            }
            try out.append(gpa, '}');
        },
        .map => |kvs| {
            try out.appendSlice(gpa, "#{");
            for (kvs, 0..) |kv, i| {
                if (i > 0) try out.append(gpa, ',');
                try formatValue(gpa, kv.key, out);
                try out.appendSlice(gpa, " => ");
                try formatValue(gpa, kv.val, out);
            }
            try out.append(gpa, '}');
        },
        .binary => |bs| {
            try out.appendSlice(gpa, "<<");
            for (bs, 0..) |b, i| {
                if (i > 0) try out.append(gpa, ',');
                var buf: [8]u8 = undefined;
                try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "{d}", .{b}));
            }
            try out.appendSlice(gpa, ">>");
        },
        .fun_ => |f| {
            var buf: [48]u8 = undefined;
            try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "#Fun<{d}.{d}>", .{ f.label, f.arity }));
        },
        // E7.1: external funs print `fun M:F/A` (erl_printf_term EXPORT_DEF /
        // `erlang:fun_to_list(fun m:f/a)`), NOT the `#Fun<...>` local shape.
        .export_fun => |e| {
            try out.appendSlice(gpa, "fun ");
            try out.appendSlice(gpa, e.module);
            try out.append(gpa, ':');
            try out.appendSlice(gpa, e.function);
            try out.append(gpa, '/');
            var buf: [16]u8 = undefined;
            try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "{d}", .{e.arity}));
        },
        // E3.1: full bytes print exactly like `.binary`; a non-byte-aligned
        // tail prints as `<<...,V:N>>` — V is the trailing `N` bits (N < 8)
        // right-justified into an N-bit value, mirroring erl_printf_term's
        // bit-syntax literal shape for a sub-byte tail segment.
        .bitstring => |b| {
            try out.appendSlice(gpa, "<<");
            const full_bytes = b.bit_len / 8;
            for (0..full_bytes) |i| {
                if (i > 0) try out.append(gpa, ',');
                var buf: [8]u8 = undefined;
                try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "{d}", .{b.bytes[i]}));
            }
            const rem = b.bit_len % 8;
            if (rem != 0) {
                if (full_bytes > 0) try out.append(gpa, ',');
                const last_val: u8 = b.bytes[full_bytes] >> @intCast(8 - rem);
                var buf: [16]u8 = undefined;
                try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "{d}:{d}", .{ last_val, rem }));
            }
            try out.appendSlice(gpa, ">>");
        },
        // E3.5 print-shape laws (pin-exact — see term_algebra.zig's module
        // doc comment): pid `<0.Number.Serial>`, reference
        // `#Ref<0.W1.W2.W3>`, port `#Port<0.Number>`.
        // E5.7: the leading `0` is the LOCAL node-table index (erts' writer
        // shape for `nonode@nohost`). A foreign identity's true node-table
        // index is a per-node, non-deterministic slot we do NOT model — its
        // node identity is observable via `node/1` (the parity surface) and
        // the ETF bytes, never this printed index (documented scope limit).
        .pid => |p| {
            var buf: [48]u8 = undefined;
            try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "<0.{d}.{d}>", .{ p.number, p.serial }));
        },
        .reference => |r| {
            var buf: [64]u8 = undefined;
            try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "#Ref<0.{d}.{d}.{d}>", .{ r.words[0], r.words[1], r.words[2] }));
        },
        .port => |p| {
            var buf: [48]u8 = undefined;
            try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "#Port<0.{d}>", .{p.number}));
        },
        // E3.14: native record `#Module:Name{k1=v1,k2=v2}` (erl_printf_term.c
        // RECORD_DEF arm). Keys/values in stored (insertion) order.
        .native_record => |r| {
            try out.append(gpa, '#');
            try formatValue(gpa, r.module, out);
            try out.append(gpa, ':');
            try formatValue(gpa, r.name, out);
            try out.append(gpa, '{');
            for (r.keys, r.values, 0..) |k, val, i| {
                if (i > 0) try out.append(gpa, ',');
                try formatValue(gpa, k, out);
                try out.append(gpa, '=');
                try formatValue(gpa, val, out);
            }
            try out.append(gpa, '}');
        },
    }
}

pub fn formatTerm(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, t: FinalTerms.Term, out: *std.ArrayList(u8)) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const v = try FinalTerms.denote(ctx, arena.allocator(), t);
    try formatValue(gpa, v, out);
}

// ---------------------------------------------------------------------------
// E5.3 (Task 3): the `%T` writer — the emulator's `erl_printf_term.c` term
// formatter, distinct from the crash-dump `formatValue` above. Two families
// share the S10 representation-free denotation domain but observe DIFFERENT
// erts writers: `formatValue` is the compact crash-dump/`~w` shape (bare atoms,
// numeric lists, `.0` floats — the corpus/`~w` differential); `formatValueT`
// is the `%.*T` shape `erts_internal:term_to_string/2` and `~p`/`display/1`
// ride (SINGLE-QUOTED atoms when needed, the printable-STRING heuristic, and
// `%e`-6 floats). Byte-verified against the pinned OTP host — see the spot-pin
// law below. SCOPE (the honest residuals, DIVERGENCE entry 41 amended): a
// SMALL-map's key ITERATION ORDER is erts' internal atom-table index order for
// atom keys (a per-VM interning slot, non-matchable across two independent atom
// tables — the `fpid` node-table-index precedent), so atom-keyed maps are NOT
// pinned here; integer-keyed maps in stored order ARE. This is why
// `term_to_string/2` stays `justified` in the ledger (no false-EQ) — the writer
// LANDS its atom-quote/string-heuristic/float parity, the map-order residual
// keeps the row deferred.

/// `%T` atom-quote predicate (erts `print_atom_name`): a bare atom needs no
/// quotes iff it is non-empty, its first CODEPOINT is a lowercase letter, and
/// every other codepoint is a name char. DIVERGENCE 718: the predicate is
/// codepoint-based over the UTF-8-stored name (atom names are utf8 — DIVERGENCE
/// 716), using the SAME Latin-1 lexer class as io_format (717): lowercase =
/// a–z ∪ ß–ÿ∖÷; uppercase = A–Z ∪ À–Þ∖×; name char = letter ∪ digit ∪ `_`
/// (NOT `@` — %T quotes `foo_bar@x`, unlike io_lib ~w which does not).
/// A codepoint > 255 (Greek/emoji) is never a name char → quotes. (The %T writer
/// emits the RAW utf8 bytes; only the quoting DECISION is codepoint-aware.)
fn tLowerCp(c: u21) bool {
    return (c >= 'a' and c <= 'z') or (c >= 0xDF and c <= 0xFF and c != 0xF7);
}
fn tUpperCp(c: u21) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 0xC0 and c <= 0xDE and c != 0xD7);
}
fn tNameCharCp(c: u21) bool {
    // NOTE: `%T` (erts print_atom_name) does NOT admit `@` as a bare name char —
    // `erlang:display(foo_bar@x)` quotes, unlike io_lib `~w` which does not (717).
    return tLowerCp(c) or tUpperCp(c) or (c >= '0' and c <= '9') or c == '_';
}
fn atomNeedsQuoteT(name: []const u8) bool {
    if (name.len == 0) return true;
    var pos: usize = 0;
    var first = true;
    while (pos < name.len) {
        const r = unicode.decodeCp(name[pos..]) catch return true;
        pos += r.len;
        if (first) {
            if (!tLowerCp(r.cp)) return true;
            first = false;
        } else if (!tNameCharCp(r.cp)) return true;
    }
    return false;
}

/// erts `is_printable_string`: a byte is "printable" for the string heuristic
/// iff it is a byte (0..255) AND not a control char that is not whitespace.
fn isPrintableByteT(c: i128) bool {
    if (c < 0 or c > 255) return false;
    const b: u8 = @intCast(c);
    const is_cntrl = b < 32 or b == 127;
    const is_space = b == ' ' or b == '\t' or b == '\n' or b == '\r' or (b == 11) or (b == 12);
    return !is_cntrl or is_space;
}

/// True iff `v` is a proper list of printable bytes (the erts string heuristic).
fn isPrintableStringT(v: *const spec.Value) bool {
    var cur = v;
    var len: usize = 0;
    while (cur.* == .cons) {
        const h = cur.cons.head;
        if (h.* != .int) return false;
        const as_i128 = h.int.toInt(i128) catch return false;
        if (!isPrintableByteT(as_i128)) return false;
        len += 1;
        cur = cur.cons.tail;
    }
    return cur.* == .nil and len > 0;
}

/// Append a `%e`-6 float exactly as C `printf("%e", f)` / erts `PRINT_DOUBLE
/// 'e' 6`: `[-]d.dddddde[+-]NN` (one leading digit, six fractional, a signed
/// two-or-more-digit exponent). Byte-verified: 1.5 → `1.500000e+00`.
fn appendFloatET(gpa: std.mem.Allocator, out: *std.ArrayList(u8), f: f64) !void {
    if (std.math.signbit(f)) try out.append(gpa, '-');
    var x = @abs(f);
    var exp: i32 = 0;
    if (x != 0) {
        while (x >= 10.0) : (exp += 1) x /= 10.0;
        while (x < 1.0) : (exp -= 1) x *= 10.0;
    }
    // Round the 7 significant digits (d.dddddd) into an integer mantissa; a
    // carry past 9.999999 re-normalizes (e.g. 9.9999996 -> 1.000000e+01).
    var m: u64 = @intFromFloat(@round(x * 1_000_000.0));
    if (m >= 10_000_000) {
        m = 1_000_000;
        exp += 1;
    }
    const lead = m / 1_000_000;
    const frac = m % 1_000_000;
    var buf: [32]u8 = undefined;
    try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "{d}.{d:0>6}e", .{ lead, frac }));
    try out.append(gpa, if (exp < 0) '-' else '+');
    const eabs: u32 = @intCast(if (exp < 0) -exp else exp);
    try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "{d:0>2}", .{eabs}));
}

/// The `%T` writer over the representation-free denotation. Total over every
/// term kind; the byte shape matches erts `%.*T` for the pinned subset (see the
/// scope note above).
pub fn formatValueT(gpa: std.mem.Allocator, v: *const spec.Value, out: *std.ArrayList(u8)) !void {
    switch (v.*) {
        .float => |f| try appendFloatET(gpa, out, f),
        .atom => |name| {
            if (!atomNeedsQuoteT(name)) {
                try out.appendSlice(gpa, name);
            } else {
                try out.append(gpa, '\'');
                for (name) |c| switch (c) {
                    '\'' => try out.appendSlice(gpa, "\\'"),
                    '\\' => try out.appendSlice(gpa, "\\\\"),
                    '\n' => try out.appendSlice(gpa, "\\n"),
                    '\t' => try out.appendSlice(gpa, "\\t"),
                    '\r' => try out.appendSlice(gpa, "\\r"),
                    12 => try out.appendSlice(gpa, "\\f"),
                    8 => try out.appendSlice(gpa, "\\b"),
                    11 => try out.appendSlice(gpa, "\\v"),
                    else => {
                        // DIVERGENCE 718: octal-escape only ASCII control bytes;
                        // a byte ≥128 is part of a UTF-8 codepoint (the name is
                        // utf8) and is emitted RAW — the old `128..159` clause
                        // wrongly escaped utf8 continuation bytes (e.g. ß=[195,159]).
                        if (c < 32) {
                            var b: [8]u8 = undefined;
                            try out.appendSlice(gpa, try std.fmt.bufPrint(&b, "\\{o:0>3}", .{c}));
                        } else try out.append(gpa, c);
                    },
                };
                try out.append(gpa, '\'');
            }
        },
        .cons => {
            if (isPrintableStringT(v)) {
                try out.append(gpa, '"');
                var cur = v;
                while (cur.* == .cons) {
                    const c: u8 = @intCast(try cur.cons.head.int.toInt(i128));
                    if (c == '\n') {
                        try out.appendSlice(gpa, "\\n");
                    } else {
                        if (c == '"') try out.append(gpa, '\\');
                        try out.append(gpa, c);
                    }
                    cur = cur.cons.tail;
                }
                try out.append(gpa, '"');
            } else {
                try out.append(gpa, '[');
                var cur = v;
                var first = true;
                while (cur.* == .cons) {
                    if (!first) try out.append(gpa, ',');
                    try formatValueT(gpa, cur.cons.head, out);
                    first = false;
                    cur = cur.cons.tail;
                }
                if (cur.* != .nil) {
                    try out.append(gpa, '|');
                    try formatValueT(gpa, cur, out);
                }
                try out.append(gpa, ']');
            }
        },
        .tuple => |xs| {
            try out.append(gpa, '{');
            for (xs, 0..) |x, i| {
                if (i > 0) try out.append(gpa, ',');
                try formatValueT(gpa, x, out);
            }
            try out.append(gpa, '}');
        },
        .map => |kvs| {
            // `%T` maps: no spaces around `=>` (unlike the crash-dump writer),
            // keys in stored order (integer-keyed pinned; atom-keyed a residual).
            try out.appendSlice(gpa, "#{");
            for (kvs, 0..) |kv, i| {
                if (i > 0) try out.append(gpa, ',');
                try formatValueT(gpa, kv.key, out);
                try out.appendSlice(gpa, "=>");
                try formatValueT(gpa, kv.val, out);
            }
            try out.append(gpa, '}');
        },
        .binary => |bs| {
            var printable = bs.len > 0;
            for (bs) |b| {
                if (b < ' ' or b >= 127) {
                    printable = false;
                    break;
                }
            }
            if (printable) {
                try out.appendSlice(gpa, "<<\"");
                try out.appendSlice(gpa, bs);
                try out.appendSlice(gpa, "\">>");
            } else {
                try out.appendSlice(gpa, "<<");
                for (bs, 0..) |b, i| {
                    if (i > 0) try out.append(gpa, ',');
                    var buf: [8]u8 = undefined;
                    try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "{d}", .{b}));
                }
                try out.appendSlice(gpa, ">>");
            }
        },
        // Every other kind shares the crash-dump shape byte-for-byte (int,
        // nil, pid/ref/port, bitstring, fun, native_record) — delegate.
        else => try formatValue(gpa, v, out),
    }
}

pub fn formatTermT(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, t: FinalTerms.Term, out: *std.ArrayList(u8)) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const v = try FinalTerms.denote(ctx, arena.allocator(), t);
    try formatValueT(gpa, v, out);
}

const Parser = struct {
    arena: std.mem.Allocator,
    text: []const u8,
    pos: usize = 0,

    fn eof(self: *const Parser) bool {
        return self.pos >= self.text.len;
    }

    fn peek(self: *const Parser) ?u8 {
        return if (self.eof()) null else self.text[self.pos];
    }

    fn skipWs(self: *Parser) void {
        while (self.peek()) |c| {
            if (c != ' ' and c != '\n' and c != '\r' and c != '\t') return;
            self.pos += 1;
        }
    }

    fn startsWith(self: *const Parser, lit: []const u8) bool {
        return self.pos + lit.len <= self.text.len and
            std.mem.eql(u8, self.text[self.pos .. self.pos + lit.len], lit);
    }

    fn consume(self: *Parser, lit: []const u8) bool {
        if (!self.startsWith(lit)) return false;
        self.pos += lit.len;
        return true;
    }

    fn expect(self: *Parser, lit: []const u8) !void {
        if (!self.consume(lit)) return error.ExpectedToken;
    }

    fn value(self: *Parser) anyerror!*const spec.Value {
        self.skipWs();
        if (self.eof()) return error.ExpectedValue;
        if (self.startsWith("#{")) return self.map();
        if (self.startsWith("<<")) return self.binary();
        if (self.startsWith("#Fun<")) return self.funPlaceholder();
        return switch (self.peek().?) {
            '[' => self.list(),
            '{' => self.tuple(),
            '-', '0'...'9' => self.number(),
            'A'...'Z', 'a'...'z', '_' => self.atom(),
            else => error.ExpectedValue,
        };
    }

    fn finishValue(self: *Parser) anyerror!*const spec.Value {
        const v = try self.value();
        self.skipWs();
        if (!self.eof()) return error.TrailingInput;
        return v;
    }

    fn mk(self: *Parser, v: spec.Value) anyerror!*const spec.Value {
        const out = try self.arena.create(spec.Value);
        out.* = v;
        return out;
    }

    fn nil(self: *Parser) anyerror!*const spec.Value {
        return self.mk(.nil);
    }

    fn cons(self: *Parser, head: *const spec.Value, tail: *const spec.Value) anyerror!*const spec.Value {
        return self.mk(.{ .cons = .{ .head = head, .tail = tail } });
    }

    fn number(self: *Parser) anyerror!*const spec.Value {
        const start = self.pos;
        _ = self.consume("-");
        const digits_start = self.pos;
        while (self.peek()) |c| switch (c) {
            '0'...'9' => self.pos += 1,
            else => break,
        };
        if (self.pos == digits_start) return error.BadNumber;

        var is_float = false;
        if (self.consume(".")) {
            is_float = true;
            const frac_start = self.pos;
            while (self.peek()) |c| switch (c) {
                '0'...'9' => self.pos += 1,
                else => break,
            };
            if (self.pos == frac_start) return error.BadNumber;
        }
        if (self.peek()) |c| {
            if (c == 'e' or c == 'E') {
                is_float = true;
                self.pos += 1;
                if (self.peek()) |s| {
                    if (s == '+' or s == '-') self.pos += 1;
                }
                const exp_start = self.pos;
                while (self.peek()) |d| switch (d) {
                    '0'...'9' => self.pos += 1,
                    else => break,
                };
                if (self.pos == exp_start) return error.BadNumber;
            }
        }

        const slice = self.text[start..self.pos];
        if (is_float) {
            const f = std.fmt.parseFloat(f64, slice) catch return error.BadNumber;
            if (!std.math.isFinite(f)) return error.BadNumber;
            return self.mk(.{ .float = f });
        }

        var m = try std.math.big.int.Managed.init(self.arena);
        try m.setString(10, slice);
        return self.mk(.{ .int = m.toConst() });
    }

    fn atom(self: *Parser) anyerror!*const spec.Value {
        const start = self.pos;
        while (self.peek()) |c| switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9', '_', '@' => self.pos += 1,
            else => break,
        };
        if (self.pos == start) return error.ExpectedAtom;
        const name = try self.arena.dupe(u8, self.text[start..self.pos]);
        return self.mk(.{ .atom = name });
    }

    fn list(self: *Parser) anyerror!*const spec.Value {
        try self.expect("[");
        self.skipWs();
        if (self.consume("]")) return self.nil();

        var elems: std.ArrayList(*const spec.Value) = .empty;
        defer elems.deinit(self.arena);
        var improper_tail: ?*const spec.Value = null;

        while (true) {
            try elems.append(self.arena, try self.value());
            self.skipWs();
            if (self.consume("|")) {
                improper_tail = try self.value();
                self.skipWs();
                try self.expect("]");
                break;
            }
            if (self.consume(",")) continue;
            try self.expect("]");
            break;
        }

        var tail = if (improper_tail) |t| t else try self.nil();
        var i = elems.items.len;
        while (i > 0) {
            i -= 1;
            tail = try self.cons(elems.items[i], tail);
        }
        return tail;
    }

    fn tuple(self: *Parser) anyerror!*const spec.Value {
        try self.expect("{");
        self.skipWs();
        var xs: std.ArrayList(*const spec.Value) = .empty;
        defer xs.deinit(self.arena);
        if (!self.consume("}")) {
            while (true) {
                try xs.append(self.arena, try self.value());
                self.skipWs();
                if (self.consume(",")) continue;
                try self.expect("}");
                break;
            }
        }
        const out = try self.arena.alloc(*const spec.Value, xs.items.len);
        @memcpy(out, xs.items);
        return self.mk(.{ .tuple = out });
    }

    fn map(self: *Parser) anyerror!*const spec.Value {
        try self.expect("#{");
        self.skipWs();
        var kvs: std.ArrayList(spec.KV) = .empty;
        defer kvs.deinit(self.arena);
        if (!self.consume("}")) {
            while (true) {
                const key = try self.value();
                self.skipWs();
                try self.expect("=>");
                const val = try self.value();
                try kvs.append(self.arena, .{ .key = key, .val = val });
                self.skipWs();
                if (self.consume(",")) continue;
                try self.expect("}");
                break;
            }
        }
        const out = try self.arena.alloc(spec.KV, kvs.items.len);
        @memcpy(out, kvs.items);
        return self.mk(.{ .map = out });
    }

    fn binary(self: *Parser) anyerror!*const spec.Value {
        try self.expect("<<");
        self.skipWs();
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(self.arena);
        if (!self.consume(">>")) {
            while (true) {
                const start = self.pos;
                while (self.peek()) |c| switch (c) {
                    '0'...'9' => self.pos += 1,
                    else => break,
                };
                if (self.pos == start) return error.BadByte;
                const raw = std.fmt.parseInt(u16, self.text[start..self.pos], 10) catch return error.BadByte;
                if (raw > 255) return error.BadByte;
                try bytes.append(self.arena, @intCast(raw));
                self.skipWs();
                if (self.consume(",")) continue;
                try self.expect(">>");
                break;
            }
        }
        const out = try self.arena.dupe(u8, bytes.items);
        return self.mk(.{ .binary = out });
    }

    fn uintUntil(self: *Parser, stop: u8) anyerror!u64 {
        const start = self.pos;
        while (self.peek()) |c| switch (c) {
            '0'...'9' => self.pos += 1,
            else => break,
        };
        if (self.pos == start or self.peek() != stop) return error.BadFun;
        return std.fmt.parseInt(u64, self.text[start..self.pos], 10) catch return error.BadFun;
    }

    fn funPlaceholder(self: *Parser) anyerror!*const spec.Value {
        try self.expect("#Fun<");
        const label = try self.uintUntil('.');
        try self.expect(".");
        const arity = try self.uintUntil('>');
        try self.expect(">");
        const env = try self.arena.alloc(*const spec.Value, 0);
        return self.mk(.{ .fun_ = .{ .label = label, .arity = arity, .env = env } });
    }
};

pub fn parseValue(arena: std.mem.Allocator, text: []const u8) anyerror!*const spec.Value {
    var p = Parser{ .arena = arena, .text = text };
    return p.finishValue();
}

// ---------------------------------------------------------------------------
// The crash dump
// ---------------------------------------------------------------------------

pub fn dumpMachine(gpa: std.mem.Allocator, m: *ia.Machine, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(gpa, "=== beam-zig crash dump ===\n");
    try out.appendSlice(gpa, switch (m.status) {
        .running => "status: running\n",
        .halted => "status: halted\n",
        .crashed => "status: crashed\n",
        .suspended => "status: suspended\n", // E1.11: blocked in a receive (wait)
    });
    try out.appendSlice(gpa, "reason: ");
    try formatTerm(gpa, &m.ctx, m.result, out);
    try out.append(gpa, '\n');
    var buf: [32]u8 = undefined;
    try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "pc: {d}\n", .{m.pc}));
    try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "reductions: {d}\n", .{m.reductions}));
    for (m.regs, 0..) |r, i| {
        if (FinalTerms.repIsAtom(r) or !FinalTerms.repIsSmall(r) or FinalTerms.smallValOf(r) != 0) {
            // print only "interesting" registers? No — determinism first:
            _ = i;
        }
    }
    for (m.regs, 0..) |r, i| {
        try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "x{d}: ", .{i}));
        try formatTerm(gpa, &m.ctx, r, out);
        try out.append(gpa, '\n');
    }
    try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "ystack: {d}\n", .{m.ystack.items.len}));
    var qbuf: [64]mba.Msg(FinalTerms) = undefined;
    const q = m.mbox.toSeq(&qbuf);
    try out.appendSlice(gpa, try std.fmt.bufPrint(&buf, "mailbox: {d}\n", .{q.len}));
    for (q) |msg| {
        try out.appendSlice(gpa, "  msg: ");
        try formatTerm(gpa, &m.ctx, msg.payload, out);
        try out.append(gpa, '\n');
    }
    try out.appendSlice(gpa, "=== end ===\n");
}

// ============================================================================
// Tests
// ============================================================================

fn s10Atom(random: std.Random, atoms: *AtomTable) !ta.AtomIdx {
    var buf: [6]u8 = undefined;
    const len = 1 + random.uintLessThan(usize, buf.len);
    for (buf[0..len]) |*b| b.* = 'a' + random.uintLessThan(u8, 26);
    return atoms.intern(buf[0..len]);
}

fn s10Float(random: std.Random) f64 {
    if (random.boolean()) return @floatFromInt(@as(i32, random.int(i16)));
    return @as(f64, @floatFromInt(@as(i32, random.int(i24)))) * 0x1p-8;
}

fn s10Term(random: std.Random, ctx: *FinalTerms.Ctx, depth: usize) !FinalTerms.Term {
    const Variant = enum { int, bigint, float, atom, nil, binary, cons, tuple, map };
    const pick: Variant = if (depth == 0) switch (random.uintLessThan(u8, 6)) {
        0 => .int,
        1 => .bigint,
        2 => .float,
        3 => .atom,
        4 => .binary,
        else => .nil,
    } else random.enumValue(Variant);

    return switch (pick) {
        .int => FinalTerms.int(ctx, @as(i64, random.int(i32))),
        .bigint => blk: {
            const mag = (@as(i128, 1) << 70) + @as(i128, random.int(u32));
            break :blk try FinalTerms.intFromI128(ctx, if (random.boolean()) mag else -mag);
        },
        .float => FinalTerms.float(ctx, s10Float(random)),
        .atom => FinalTerms.atom(ctx, try s10Atom(random, ctx.atoms)),
        .nil => FinalTerms.nil(ctx),
        .binary => blk: {
            var buf: [8]u8 = undefined;
            const len = random.uintLessThan(usize, buf.len + 1);
            for (buf[0..len]) |*b| b.* = random.int(u8);
            break :blk try FinalTerms.binary(ctx, buf[0..len]);
        },
        .cons => try FinalTerms.cons(
            ctx,
            try s10Term(random, ctx, depth - 1),
            try s10Term(random, ctx, depth - 1),
        ),
        .tuple => blk: {
            const n = random.uintLessThan(u8, ta.max_tuple_arity + 1);
            var buf: [ta.max_tuple_arity]FinalTerms.Term = undefined;
            for (0..n) |k| buf[k] = try s10Term(random, ctx, depth - 1);
            break :blk try FinalTerms.tuple(ctx, buf[0..n]);
        },
        .map => blk: {
            const n = random.uintLessThan(u8, ta.max_tuple_arity + 1);
            var ks: [ta.max_tuple_arity]FinalTerms.Term = undefined;
            var vs: [ta.max_tuple_arity]FinalTerms.Term = undefined;
            for (0..n) |k| {
                ks[k] = FinalTerms.int(ctx, @intCast(k));
                vs[k] = try s10Term(random, ctx, depth - 1);
            }
            break :blk try FinalTerms.mapNew(ctx, ks[0..n], vs[0..n]);
        },
    };
}

test "Formatter is total and Erlang-shaped (spot pins)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var prng = std.Random.DefaultPrng.init(0xF0A7);

    // totality over every kind the generator produces
    for (0..80) |_| {
        const t = try ta.genTerm(FinalTerms, prng.random(), &ctx, 3);
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try formatTerm(gpa, &ctx, t, &out);
        try std.testing.expect(out.items.len > 0);
    }

    // spot pins
    const cases = [_]struct { t: FinalTerms.Term, want: []const u8 }{
        .{ .t = FinalTerms.int(&ctx, -42), .want = "-42" },
        .{ .t = FinalTerms.float(&ctx, 1.5), .want = "1.5" },
        .{ .t = FinalTerms.float(&ctx, 2.0), .want = "2.0" },
        .{ .t = FinalTerms.atom(&ctx, try atoms.intern("ok")), .want = "ok" },
        .{ .t = FinalTerms.nil(&ctx), .want = "[]" },
        .{ .t = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 1), FinalTerms.int(&ctx, 2)), .want = "[1|2]" },
        .{ .t = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 1), FinalTerms.nil(&ctx) }), .want = "{1,[]}" },
        .{ .t = try FinalTerms.binary(&ctx, &.{ 1, 2 }), .want = "<<1,2>>" },
        // E3.1: aligned bitstring prints exactly like a binary...
        .{ .t = try FinalTerms.bitstring(&ctx, &.{ 1, 2 }, 16), .want = "<<1,2>>" },
        // ...a non-byte-aligned tail gets the `<<...,V:N>>` shape (5 bits:
        // 1,0,1,1,0 -> value 0b10110 = 22, tagged with its bit width)
        .{ .t = try FinalTerms.bitstring(&ctx, &.{ 1, 0b1011_0000 }, 13), .want = "<<1,22:5>>" },
        .{ .t = try FinalTerms.bitstring(&ctx, &.{0b1011_0000}, 5), .want = "<<22:5>>" },
        .{ .t = try FinalTerms.bitstring(&ctx, &.{}, 0), .want = "<<>>" },
        // E3.5 print-shape laws (pin-exact — see term_algebra.zig's module
        // doc comment).
        .{ .t = try FinalTerms.pid(&ctx, 3, 1), .want = "<0.3.1>" },
        .{ .t = try FinalTerms.ref(&ctx, .{ 5, 6, 7 }), .want = "#Ref<0.5.6.7>" },
        .{ .t = try FinalTerms.port(&ctx, 9), .want = "#Port<0.9>" },
        // E3.14 native-record format law: `#Module:Name{k=v,...}`.
        .{ .t = try FinalTerms.nativeRecord(
            &ctx,
            FinalTerms.atomTerm(try atoms.intern("mod")),
            FinalTerms.atomTerm(try atoms.intern("point")),
            true,
            &.{ FinalTerms.atomTerm(try atoms.intern("x")), FinalTerms.atomTerm(try atoms.intern("y")) },
            &.{ FinalTerms.int(&ctx, 1), FinalTerms.int(&ctx, 2) },
        ), .want = "#mod:point{x=1,y=2}" },
        // E7.1 external-fun format law: `fun M:F/A` (host ~p/~w/fun_to_list).
        .{ .t = try FinalTerms.makeExportFun(
            &ctx,
            FinalTerms.atomTerm(try atoms.intern("lists")),
            FinalTerms.atomTerm(try atoms.intern("map")),
            2,
        ), .want = "fun lists:map/2" },
    };
    for (cases) |c| {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try formatTerm(gpa, &ctx, c.t, &out);
        try std.testing.expect(std.mem.eql(u8, c.want, out.items));
    }
    // big int via the arena path
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try formatTerm(gpa, &ctx, try FinalTerms.intFromI128(&ctx, 1 << 64), &out);
    try std.testing.expect(std.mem.eql(u8, "18446744073709551616", out.items));
}

test "LAW E5.3 %T writer matches erts erl_printf_term (byte-verified spot pins)" {
    // Every `want` was captured from the pinned OTP host via
    // `erts_internal:term_to_string(T, undefined)` (see DIVERGENCE entry 41).
    // This pins the atom-quote rule, the printable-string heuristic, and the
    // `%e`-6 float shape — the three writer blockers entry 41 named. Small-map
    // key order for ATOM keys is deliberately NOT pinned (erts internal
    // atom-index order, non-matchable across atom tables — the residual that
    // keeps term_to_string/2 justified).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    // a printable string "hello" as a char list
    const hello = blk: {
        var l = FinalTerms.nil(&ctx);
        const bytes = "hello";
        var i = bytes.len;
        while (i > 0) {
            i -= 1;
            l = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, bytes[i]), l);
        }
        break :blk l;
    };
    const nl_str = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 'a'), try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, '\n'), try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 'b'), FinalTerms.nil(&ctx))));

    const cases = [_]struct { t: FinalTerms.Term, want: []const u8 }{
        .{ .t = FinalTerms.int(&ctx, -42), .want = "-42" },
        .{ .t = FinalTerms.atom(&ctx, try atoms.intern("foo")), .want = "foo" },
        .{ .t = FinalTerms.atom(&ctx, try atoms.intern("Foo")), .want = "'Foo'" },
        .{ .t = FinalTerms.atom(&ctx, try atoms.intern("foo_bar@x")), .want = "'foo_bar@x'" },
        .{ .t = FinalTerms.atom(&ctx, try atoms.intern("hi there")), .want = "'hi there'" },
        // DIVERGENCE 718: codepoint-based %T atom quoting over the utf8 name.
        // Latin-1 lowercase-led atoms are UNQUOTED, emitted as RAW utf8 bytes.
        .{ .t = FinalTerms.atom(&ctx, try atoms.intern("caf\xc3\xa9")), .want = "caf\xc3\xa9" }, // café
        .{ .t = FinalTerms.atom(&ctx, try atoms.intern("\xc3\x9feta")), .want = "\xc3\x9feta" }, // ßeta (ß=223 lower)
        // Latin-1 uppercase-led / non-Latin-1 → quoted, RAW utf8 inside (no \x{}).
        .{ .t = FinalTerms.atom(&ctx, try atoms.intern("\xc3\x84rger")), .want = "'\xc3\x84rger'" }, // Ärger
        .{ .t = FinalTerms.atom(&ctx, try atoms.intern("\xce\x94elta")), .want = "'\xce\x94elta'" }, // Δelta
        .{ .t = FinalTerms.atom(&ctx, try atoms.intern("\xce\xb1\xce\xb2")), .want = "'\xce\xb1\xce\xb2'" }, // αβ (>255 → quote)
        .{ .t = FinalTerms.atom(&ctx, try atoms.intern("snow\xe2\x98\x83")), .want = "'snow\xe2\x98\x83'" }, // snow☃
        .{ .t = hello, .want = "\"hello\"" },
        .{ .t = nl_str, .want = "\"a\\nb\"" },
        .{ .t = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 1), try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 2), try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 3), FinalTerms.nil(&ctx)))), .want = "[1,2,3]" },
        .{ .t = try FinalTerms.tuple(&ctx, &.{ FinalTerms.atom(&ctx, try atoms.intern("ok")), FinalTerms.int(&ctx, 1) }), .want = "{ok,1}" },
        .{ .t = try FinalTerms.binary(&ctx, &.{ 1, 2 }), .want = "<<1,2>>" },
        .{ .t = try FinalTerms.binary(&ctx, "ab"), .want = "<<\"ab\">>" },
        // gap-display-bitstring-binary (DIVERGENCE 649): a BYTE-ALIGNED bitstring
        // (a `<< _, Rest/binary >>` tail) denotes as a BINARY, so it rides the SAME
        // printable-string heuristic as a flat binary — a printable one prints
        // `<<"hi">>` (NOT `<<104,105>>`), byte-EQ vs OTP erlang:display; a
        // non-printable one is `<<1,2>>`; a genuinely SUB-BYTE bitstring keeps the
        // `<<V:N>>` tail shape.
        .{ .t = try FinalTerms.bitstring(&ctx, "hi", 16), .want = "<<\"hi\">>" },
        .{ .t = try FinalTerms.bitstring(&ctx, &.{ 1, 2 }, 16), .want = "<<1,2>>" },
        .{ .t = try FinalTerms.bitstring(&ctx, &.{0b1011_0000}, 5), .want = "<<22:5>>" },
        .{ .t = FinalTerms.float(&ctx, 1.5), .want = "1.500000e+00" },
        .{ .t = FinalTerms.float(&ctx, 2.0), .want = "2.000000e+00" },
        .{ .t = FinalTerms.float(&ctx, -0.5), .want = "-5.000000e-01" },
        .{ .t = FinalTerms.float(&ctx, 1234.5), .want = "1.234500e+03" },
        .{ .t = FinalTerms.nil(&ctx), .want = "[]" },
        // integer-keyed small map in stored (sorted-on-insertion) order — the
        // matchable map subset; note `=>` carries NO surrounding spaces (unlike
        // the crash-dump `formatValue`).
        .{ .t = try FinalTerms.mapNew(&ctx, &.{ FinalTerms.int(&ctx, 1), FinalTerms.int(&ctx, 2) }, &.{ FinalTerms.int(&ctx, 10), FinalTerms.int(&ctx, 20) }), .want = "#{1=>10,2=>20}" },
    };
    for (cases) |c| {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try formatTermT(gpa, &ctx, c.t, &out);
        try std.testing.expectEqualStrings(c.want, out.items);
    }

    // TOTALITY: never crashes over the generator's full kind space.
    var prng = std.Random.DefaultPrng.init(0x5E3D0);
    for (0..80) |_| {
        const t = try ta.genTerm(FinalTerms, prng.random(), &ctx, 3);
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try formatTermT(gpa, &ctx, t, &out);
        try std.testing.expect(out.items.len > 0);
    }
}

test "S10 FORMAT/PARSE: stable formatter syntax round-trips by denotation" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var prng = std.Random.DefaultPrng.init(0x510F0A7);
    const random = prng.random();

    for (0..80) |_| {
        const t = try s10Term(random, &ctx, 3);

        var spec_arena = std.heap.ArenaAllocator.init(gpa);
        defer spec_arena.deinit();
        const original = try FinalTerms.denote(&ctx, spec_arena.allocator(), t);

        var formatted: std.ArrayList(u8) = .empty;
        defer formatted.deinit(gpa);
        try formatValue(gpa, original, &formatted);

        var parse_arena = std.heap.ArenaAllocator.init(gpa);
        defer parse_arena.deinit();
        const parsed = try parseValue(parse_arena.allocator(), formatted.items);
        try std.testing.expect(spec.eqlExact(original, parsed));

        var formatted_again: std.ArrayList(u8) = .empty;
        defer formatted_again.deinit(gpa);
        try formatValue(gpa, parsed, &formatted_again);
        try std.testing.expect(std.mem.eql(u8, formatted.items, formatted_again.items));
    }

    var parse_arena = std.heap.ArenaAllocator.init(gpa);
    defer parse_arena.deinit();
    const parsed_fun = try parseValue(parse_arena.allocator(), "#Fun<7.2>");
    try std.testing.expectEqual(@as(u64, 7), parsed_fun.fun_.label);
    try std.testing.expectEqual(@as(u64, 2), parsed_fun.fun_.arity);
    try std.testing.expectEqual(@as(usize, 0), parsed_fun.fun_.env.len);
}

test "S10 parser rejects malformed syntax with named errors" {
    const gpa = std.testing.allocator;
    const bad = [_][]const u8{
        "",
        "[1,]",
        "{1",
        "<<256>>",
        "#{1 =>}",
        "1abc",
        "#Fun<1>",
    };
    for (bad) |text| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        if (parseValue(arena.allocator(), text)) |_| {
            return error.ExpectedParserFailure;
        } else |_| {}
    }
}

test "GOLDEN + DETERMINISM: the M8 function_clause crash dumps byte-exactly, twice" {
    const gpa = std.testing.allocator;
    var mod = try loader.parse(gpa, @embedFile("mylists.beam"));
    defer mod.deinit();
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const t = try loader.translate(gpa, &mod, &atoms, null);
    defer {
        gpa.free(t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs); // E3.11: pc->source-location table
    }

    var dumps: [2]std.ArrayList(u8) = .{ .empty, .empty };
    defer for (&dumps) |*d| d.deinit(gpa);

    for (&dumps) |*d| {
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        m.pc = loader.entryOf(&t, "sum", 1).?;
        m.regs[0] = FinalTerms.atom(&m.ctx, try atoms.intern("oops"));
        var guard: usize = 0;
        while (m.status == .running) : (guard += 1) {
            if (guard > 1000) return error.DidNotHalt;
            try ia.run(&m, t.prog, 10);
        }
        try std.testing.expectEqual(ia.Status.crashed, m.status);
        try dumpMachine(gpa, &m, d);
    }
    // DETERMINISM: twin dumps byte-identical
    try std.testing.expect(std.mem.eql(u8, dumps[0].items, dumps[1].items));
    // GOLDEN: the load-bearing lines are pinned exactly
    try std.testing.expect(std.mem.indexOf(u8, dumps[0].items, "status: crashed\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, dumps[0].items, "reason: function_clause\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, dumps[0].items, "x0: oops\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, dumps[0].items, "mailbox: 0\n") != null);
}
