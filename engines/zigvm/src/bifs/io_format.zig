//! io_format — the `io_lib:format`/`io:format` control-sequence interpreter
//! (gap-io-format, first increment).
//!
//! ## Semantic domain
//! `format(fmt: []u8, args: Term) -> chars()` (an Erlang charlist), BYTE-EQ with
//! OTP `io_lib_format:fwrite/2` for the directive subset `~~ ~n ~s ~c ~b ~B ~w ~i`
//! (plus field-width / precision / pad / left-adjust), each verified against the
//! pinned OTP-30 oracle (`erl -eval 'io_lib:format(...)'`).
//!
//! ## Oracle-pinned facts (NOT the design's guesses)
//!   ~.16b of 255 = "ff"  (LOWERCASE — the oracle overruled the design)
//!   ~5..0b of 42 = "00042"   ~.2b of 5 = "101"   ~b of -42 = "-42"
//!   ~w of {a,1} = "{a,1}"   ~w of [97,98] = "[97,98]" (NO string heuristic)
//!   ~c of 65 = "A"   ~3c of 120 = "xxx"   ~s of ok = "ok" (atom→name)
//!
//! ## Oracle-pinned float facts (gap-io-format-float)
//!   ~e P = TOTAL sig digits (≥2), ~f P = decimals (≥1), ~g fixed only for
//!   0.1 ≤ |x| < 10^4 (0.0 → e-form); default P=6; two-stage rounding
//!   (exact→21 ties-to-even, then half-up on the STRING: ~.1f 0.25→"0.3" but
//!   ~.2f 2.675→"2.67"); field overflow = width×'*'; ~w floats = shortest
//!   round-trip with the 2^53 fixed/sci layout rule ("1.0e3", "2048.0").
//!
//! ## Oracle-pinned ~p/~P wrap facts (gap-io-format-pwrap)
//!   F = LINE LENGTH (default 80, 0 ⇒ flat), P = START COLUMN (default =
//!   current column + 1); ~-Fp badarg; only LEAVES pack per line (strings are
//!   leaves, composites are not); leaf strings never wrap; tagged tuples align
//!   after the tag or TInd=4 staircase (cind); ~P pops a SECOND depth arg
//!   (0 → "...", <0 → unlimited; string heuristic OFF at depth 1).
//!
//! ## Oracle-pinned prefixed-integer + map facts (gap-io-format-complete)
//!   ~.16x 255 "0x" = "0xff"   ~.16X 255 "0x" = "0xFF" (DIGITS uppercased, the
//!   prefix verbatim)   ~.10x -31 "0x" = "-0x31" (sign BEFORE the prefix)
//!   ~.16B 31 = "1F"   ~.16b 31 = "1f"   ~.16+ -31 = "-16#1f"   ~+ 255 = "10#255"
//!   ~w/~p of a map render `#{K => V,...}` with keys in CANONICAL exact-term
//!   order (`#{}` empty). NOTE: erts prints maps in an INTERNAL hash/atom-index
//!   order that our term representation cannot reproduce, so byte-EQ holds only
//!   where that order coincides with term order (empty / single-key / numeric-
//!   or type-distinguished keys); multi-atom-key order is a disclosed boundary.
//!   ~P of a map collapses at depth 1 to "#{...}".
//!
//! ## Named deferrals (badarg — disclosed; io_lib:format is a library wrapper, not
//! a bif-ledger row, so a partial impl is honest)
//!   ~#, ~ts/~tp full unicode width, MULTI-LINE map wrapping + per-pair depth
//!   `...` truncation + multi-atom-key hash order (irreproducible erts order),
//!   {chars_limit,N} (the More/expand machinery — needed only if a shell-style
//!   surface lands), and ~w of a bignum / binary / pid / ref / fun. These raise
//!   `error.Badarg` (or render in canonical order for the map subset above).
const std = @import("std");
const ia = @import("../instr_algebra.zig");
const unicode = @import("../unicode.zig");
const ta = @import("../term_algebra.zig");
const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

const Spec = struct {
    width: ?i64 = null,
    adjust: enum { left, right } = .right,
    precision: ?i64 = null,
    pad: u8 = ' ',
    ctrl: u8 = 0,
    // gap-io-format-unicode: the `t` modifier — `~ts`/`~tc` treat integer args
    // as UNICODE CODEPOINTS and emit UTF-8 (`~ts [955]` → <<206,187>>), where
    // the latin1 `~s` would badarg on a >255 codepoint. Oracle-pinned.
    unicode: bool = false,
};

fn popArg(m: *Machine, args: *Term) BifError!Term {
    if (FinalTerms.kindOf(&m.ctx, args.*) != .cons) return error.Badarg;
    const h = FinalTerms.listHead(&m.ctx, args.*);
    args.* = FinalTerms.listTail(&m.ctx, args.*);
    return h;
}

fn readInt(t: Term) BifError!i64 {
    if (!FinalTerms.repIsSmall(t)) return error.Badarg;
    return FinalTerms.smallValOf(t);
}

fn scanDigits(fmt: []const u8, i: *usize) ?i64 {
    var v: i64 = 0;
    var seen = false;
    while (i.* < fmt.len and fmt[i.*] >= '0' and fmt[i.*] <= '9') : (i.* += 1) {
        v = v * 10 + @as(i64, fmt[i.*] - '0');
        seen = true;
    }
    return if (seen) v else null;
}

/// Scan one field spec after '~': [-][F|*][.P|.*][.Pad|.*][mods]Ctrl — the
/// io_lib_format collect_cseq order.
fn scanSpec(m: *Machine, fmt: []const u8, i: *usize, args: *Term) BifError!Spec {
    var s = Spec{};
    if (i.* < fmt.len and fmt[i.*] == '-') {
        s.adjust = .left;
        i.* += 1;
    }
    if (i.* < fmt.len and fmt[i.*] == '*') {
        s.width = try readInt(try popArg(m, args));
        i.* += 1;
    } else s.width = scanDigits(fmt, i);
    if (s.width) |w| if (w < 0) {
        s.adjust = .left;
        s.width = -w;
    };
    if (i.* < fmt.len and fmt[i.*] == '.') {
        i.* += 1;
        if (i.* < fmt.len and fmt[i.*] == '*') {
            s.precision = try readInt(try popArg(m, args));
            i.* += 1;
        } else s.precision = scanDigits(fmt, i);
    }
    if (i.* < fmt.len and fmt[i.*] == '.') {
        i.* += 1;
        if (i.* < fmt.len and fmt[i.*] == '*') {
            s.pad = @intCast(try readInt(try popArg(m, args)));
        } else if (i.* < fmt.len) {
            s.pad = fmt[i.*];
        }
        i.* += 1;
    }
    // modifiers: t=UNICODE (gap-io-format-unicode, wired below), l=no-strings,
    // k/K=map key order (consumed; erts hash order is the disclosed EQ bound).
    while (i.* < fmt.len) : (i.* += 1) switch (fmt[i.*]) {
        't' => s.unicode = true,
        'l', 'k' => {},
        'K' => _ = try popArg(m, args),
        else => break,
    };
    if (i.* >= fmt.len) return error.Badarg;
    s.ctrl = fmt[i.*];
    i.* += 1;
    return s;
}

/// Write a term in `~w` form (raw, one line, NO string heuristic). First increment:
/// small-int / atom / nil / cons / tuple; other kinds are a named deferral (badarg).
/// DIVERGENCE 689 (gap-io-format-bignum): append a BIGNUM's base-10 decimal digits
/// to `out`. `io_lib:format` `~w`/`~p` (and any bignum NESTED in a formatted term,
/// e.g. `~w [{a, 1 bsl 100, c}]`) badarg'd because `writeTerm`'s `.number` arm
/// deferred bignums — a LITERAL was masked by erlc constant-folding; a RUNTIME
/// bignum (≥ 2^59, the fixnum boundary) crashed every `~w`/`~p`. `leafStr` routes
/// the pretty-printer (`~p`) leaves through `writeTerm`, so this one site fixes both.
/// `std.math.big` over the term's own limbs. (The based-int controls `~b/~B/~x/~+`
/// still take the `i64` path — a bignum there is a separate narrow follow-on.)
fn writeBigDecimal(m: *Machine, out: *std.ArrayList(u8), t: Term) BifError!void {
    const parts = FinalTerms.bigPartsOf(&m.ctx, t);
    const c = std.math.big.int.Const{ .limbs = parts.limbs, .positive = parts.positive };
    const s = c.toStringAlloc(m.ctx.gpa, 10, .lower) catch return error.OutOfMemory;
    defer m.ctx.gpa.free(s);
    try out.appendSlice(m.ctx.gpa, s);
}

// ── DIVERGENCE 714/717: atom quoting for ~w/~p (and io_lib:write_atom) ──
// erts prints an atom UNQUOTED iff it is non-empty, starts with a lowercase
// letter, and every char is a name char; otherwise it is `'…'`-quoted. "letter"
// is the Latin-1 lexer class on the DECODED CODEPOINT (atom names are stored as
// UTF-8 here — DIVERGENCE-716 — so the predicate decodes utf8 first, 717):
// lowercase = a–z ∪ ß–ÿ∖÷; uppercase = A–Z ∪ À–Þ∖×; name char = letter ∪ digit ∪
// `_` ∪ `@`. A codepoint > 255 (Greek/CJK/emoji) is NEVER a name char → forces
// quoting, and inside the quotes prints as `\x{HEX}` (uppercase, no leading
// zeros); Latin-1 codepoints print as their single byte (é → byte 233, matching
// erts' latin1 ~w device — NOT the utf8 bytes).

fn isAtomLowerCp(c: u21) bool {
    return (c >= 'a' and c <= 'z') or (c >= 0xDF and c <= 0xFF and c != 0xF7);
}
fn isAtomUpperCp(c: u21) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 0xC0 and c <= 0xDE and c != 0xD7);
}
fn isAtomNameCharCp(c: u21) bool {
    return isAtomLowerCp(c) or isAtomUpperCp(c) or (c >= '0' and c <= '9') or c == '_' or c == '@';
}
/// An atom needs quoting unless it is a non-empty lowercase-led all-name-char
/// codepoint sequence. Invalid utf8 (never a real atom) conservatively quotes.
fn atomNeedsQuote(name: []const u8) bool {
    if (name.len == 0) return true; // the empty atom prints as ''
    var pos: usize = 0;
    var first = true;
    while (pos < name.len) {
        const r = unicode.decodeCp(name[pos..]) catch return true;
        pos += r.len;
        if (first) {
            if (!isAtomLowerCp(r.cp)) return true;
            first = false;
        } else if (!isAtomNameCharCp(r.cp)) return true;
    }
    return false;
}
/// Append an atom's printed form (quoted+escaped iff `atomNeedsQuote`), codepoint
/// -aware: an unquoted name's codepoints are all ≤255 (emitted as bytes); a quoted
/// name escapes controls/`'`/`\`, emits Latin-1 codepoints literally, and non-
/// Latin-1 codepoints as `\x{HEX}`.
fn writeAtomName(m: *Machine, out: *std.ArrayList(u8), name: []const u8) BifError!void {
    const gpa = m.ctx.gpa;
    if (!atomNeedsQuote(name)) {
        // every codepoint is a Latin-1 name char (≤255) → emit as a single byte.
        var pos: usize = 0;
        while (pos < name.len) {
            const r = unicode.decodeCp(name[pos..]) catch break;
            pos += r.len;
            try out.append(gpa, @intCast(r.cp));
        }
        return;
    }
    try out.append(gpa, '\'');
    var pos: usize = 0;
    while (pos < name.len) {
        const r = unicode.decodeCp(name[pos..]) catch {
            try out.append(gpa, name[pos]); // invalid utf8 byte: pass through
            pos += 1;
            continue;
        };
        pos += r.len;
        const cp = r.cp;
        if (cp > 255) {
            var hb: [8]u8 = undefined;
            const hs = std.fmt.bufPrint(&hb, "{X}", .{cp}) catch return error.Badarg;
            try out.appendSlice(gpa, "\\x{");
            try out.appendSlice(gpa, hs);
            try out.append(gpa, '}');
        } else switch (@as(u8, @intCast(cp))) {
            8 => try out.appendSlice(gpa, "\\b"),
            9 => try out.appendSlice(gpa, "\\t"),
            10 => try out.appendSlice(gpa, "\\n"),
            11 => try out.appendSlice(gpa, "\\v"),
            12 => try out.appendSlice(gpa, "\\f"),
            13 => try out.appendSlice(gpa, "\\r"),
            27 => try out.appendSlice(gpa, "\\e"),
            '\'' => try out.appendSlice(gpa, "\\'"),
            '\\' => try out.appendSlice(gpa, "\\\\"),
            else => |b| try out.append(gpa, b),
        }
    }
    try out.append(gpa, '\'');
}

fn writeTerm(m: *Machine, out: *std.ArrayList(u8), t: Term) BifError!void {
    switch (FinalTerms.kindOf(&m.ctx, t)) {
        .number => {
            if (FinalTerms.repIsSmall(t)) {
                try out.print(m.ctx.gpa, "{d}", .{FinalTerms.smallValOf(t)});
            } else if (FinalTerms.repIsFloat(&m.ctx, t)) {
                // gap-io-format-float: shortest round-trip, Erlang literal layout.
                try writeFloatShortest(m, out, FinalTerms.floatValOf(&m.ctx, t));
            } else if (FinalTerms.repIsBig(&m.ctx, t)) {
                try writeBigDecimal(m, out, t); // DIVERGENCE 689
            } else return error.Badarg;
        },
        .atom => try writeAtomName(m, out, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(t))),
        .nil => try out.appendSlice(m.ctx.gpa, "[]"),
        .cons => {
            try out.append(m.ctx.gpa, '[');
            var cur = t;
            var first = true;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
                if (!first) try out.append(m.ctx.gpa, ',');
                first = false;
                try writeTerm(m, out, FinalTerms.listHead(&m.ctx, cur));
                cur = FinalTerms.listTail(&m.ctx, cur);
            }
            if (FinalTerms.kindOf(&m.ctx, cur) != .nil) { // improper tail → |Tail
                try out.append(m.ctx.gpa, '|');
                try writeTerm(m, out, cur);
            }
            try out.append(m.ctx.gpa, ']');
        },
        .tuple => {
            try out.append(m.ctx.gpa, '{');
            const n = FinalTerms.tupleArity(&m.ctx, t);
            var k: usize = 0;
            while (k < n) : (k += 1) {
                if (k > 0) try out.append(m.ctx.gpa, ',');
                try writeTerm(m, out, FinalTerms.tupleElem(&m.ctx, t, k));
            }
            try out.append(m.ctx.gpa, '}');
        },
        .map => try writeMap(m, out, t, writeTerm), // ~w: no string heuristic
        .binary => try writeBinaryW(m, out, t), // ~w: <<B1,B2,...>>
        // gap-term-print-totality (DIVERGENCE 728): pid/port/ref/fun render in OTP
        // surface shapes — was `badarg`, the crash-amplifier: `io_lib:format` of ANY
        // term carrying a pid/ref/fun killed the printing process. pid/ref/port
        // NUMBERS are VM-run-specific (EQUIV, disclosed — the SHAPE is byte-EQ, per
        // the diag.zig %T twin's E3.5 shapes); an external `fun M:F/A` is byte-EQ; a
        // LOCAL closure WITH fun_meta prints `#Fun<Module.Index.OldUniq>` byte-EQ
        // (DIVERGENCE 740 discharged the 728 funmeta follow-up); a no-meta synthetic
        // fun falls back to `#Fun<Label.Arity>`.
        .pid => try out.print(m.ctx.gpa, "<0.{d}.{d}>", .{ FinalTerms.pidNumber(&m.ctx, t), FinalTerms.pidSerial(&m.ctx, t) }),
        .reference => {
            const w = FinalTerms.refWords(&m.ctx, t);
            try out.print(m.ctx.gpa, "#Ref<0.{d}.{d}.{d}>", .{ w[0], w[1], w[2] });
        },
        .port => try out.print(m.ctx.gpa, "#Port<0.{d}>", .{FinalTerms.portNumber(&m.ctx, t)}),
        .fun_ => if (FinalTerms.repIsExportFun(&m.ctx, t))
            try out.print(m.ctx.gpa, "fun {s}:{s}/{d}", .{ FinalTerms.exportFunModuleName(&m.ctx, t), FinalTerms.exportFunFuncName(&m.ctx, t), FinalTerms.exportFunArity(&m.ctx, t) })
        else if (m.fun_meta.get(FinalTerms.funLabel(&m.ctx, t))) |meta|
            // gap-fun-print-shape (DIVERGENCE 740): a LOCAL closure prints
            // `#Fun<Module.Index.OldUniq>` (erts `erts_print_fun`) — the module NAME
            // + the FunT Index + OldUniq carried in `fun_meta` ([0]=module atom,
            // [2]=index, [3]=old_uniq). Byte-EQ: all three come from the SAME beam
            // FunT record both VMs load. This discharges the 728 `#Fun<Label.Arity>`
            // funmeta follow-up. A synthetic fun (no meta) keeps the fallback below.
            try out.print(m.ctx.gpa, "#Fun<{s}.{d}.{d}>", .{ m.ctx.atoms.nameOf(@intCast(meta[0])), meta[2], meta[3] })
        else
            try out.print(m.ctx.gpa, "#Fun<{d}.{d}>", .{ FinalTerms.funLabel(&m.ctx, t), FinalTerms.funArity(&m.ctx, t) }),
        else => return error.Badarg, // native_record (VM-internal) stays deferred
    }
}

/// Render a map as `#{K => V,...}` with keys in CANONICAL exact-term order
/// (empty → `#{}`). `elemFn` is the per-element writer: `writeTerm` for ~w
/// (no string heuristic) or `writeTermP` for ~p. Note: erts prints maps in an
/// INTERNAL hash/atom-index order that is NOT reproducible from our term
/// representation (a named boundary); this canonical sorted rendering is
/// byte-EQ with the oracle only when erts' order coincides with term order
/// (empty / single-key / numeric- or type-distinguished keys). Multi-atom-key
/// order and per-pair depth `...` truncation stay a disclosed deferral.
fn writeMap(m: *Machine, out: *std.ArrayList(u8), t: Term, comptime elemFn: fn (*Machine, *std.ArrayList(u8), Term) BifError!void) BifError!void {
    const gpa = m.ctx.gpa;
    const n = FinalTerms.mapSize(&m.ctx, t);
    try out.appendSlice(gpa, "#{");
    if (n == 0) {
        try out.append(gpa, '}');
        return;
    }
    const pk = gpa.alloc(Term, n) catch return error.OutOfMemory;
    defer gpa.free(pk);
    const pv = gpa.alloc(Term, n) catch return error.OutOfMemory;
    defer gpa.free(pv);
    _ = FinalTerms.mapPairs(&m.ctx, t, pk, pv);
    const idx = gpa.alloc(usize, n) catch return error.OutOfMemory;
    defer gpa.free(idx);
    for (idx, 0..) |*s, i| s.* = i;
    const SortCtx = struct {
        m: *Machine,
        keys: []const Term,
        fn less(s: @This(), x: usize, y: usize) bool {
            return FinalTerms.compareExact(&s.m.ctx, s.keys[x], s.keys[y]) == .lt;
        }
    };
    std.sort.insertion(usize, idx, SortCtx{ .m = m, .keys = pk }, SortCtx.less);
    for (idx, 0..) |i, j| {
        if (j > 0) try out.append(gpa, ',');
        try elemFn(m, out, pk[i]);
        try out.appendSlice(gpa, " => ");
        try elemFn(m, out, pv[i]);
    }
    try out.append(gpa, '}');
}

// ── ~p: the printable-string heuristic (recursive) + escaping ──
// Oracle-pinned printable set: {8,9,10,11,12,13,27} (→ \b\t\n\v\f\r\e), 32..126,
// 160..255. `"`→\" and `\`→\\. A NON-EMPTY proper list of all-printable chars
// renders as a quoted string; else as [...] with ~p on each element.
fn isPrintableChar(c: i64) bool {
    return switch (c) {
        8, 9, 10, 11, 12, 13, 27 => true,
        32...126 => true,
        160...255 => true,
        else => false,
    };
}

fn isPrintableList(m: *Machine, t: Term) bool {
    if (FinalTerms.kindOf(&m.ctx, t) != .cons) return false; // empty [] is NOT a string
    var cur = t;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        if (!FinalTerms.repIsSmall(h) or !isPrintableChar(FinalTerms.smallValOf(h))) return false;
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    return FinalTerms.kindOf(&m.ctx, cur) == .nil; // proper list
}

fn writeString(m: *Machine, out: *std.ArrayList(u8), t: Term) BifError!void {
    try out.append(m.ctx.gpa, '"');
    var cur = t;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const c = FinalTerms.smallValOf(FinalTerms.listHead(&m.ctx, cur));
        switch (c) {
            8 => try out.appendSlice(m.ctx.gpa, "\\b"),
            9 => try out.appendSlice(m.ctx.gpa, "\\t"),
            10 => try out.appendSlice(m.ctx.gpa, "\\n"),
            11 => try out.appendSlice(m.ctx.gpa, "\\v"),
            12 => try out.appendSlice(m.ctx.gpa, "\\f"),
            13 => try out.appendSlice(m.ctx.gpa, "\\r"),
            27 => try out.appendSlice(m.ctx.gpa, "\\e"),
            '"' => try out.appendSlice(m.ctx.gpa, "\\\""),
            '\\' => try out.appendSlice(m.ctx.gpa, "\\\\"),
            else => try out.append(m.ctx.gpa, @truncate(@as(u64, @bitCast(c)))),
        }
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    try out.append(m.ctx.gpa, '"');
}

// ── gap-io-format-binary: ~w/~p/~s of a binary, byte-EQ vs the pinned oracle ──
// Oracle-pinned (OTP-30 679f9dbb): ~w of <<"ping">> = "<<112,105,110,103>>";
// <<>> = "<<>>". ~p renders <<"...">> iff NON-empty and every byte is printable
// (the isPrintableChar set) with the writeString escaping, else the ~w byte form
// (<<97,98,1>> for <<"ab",1>>). ~s emits the raw latin1 bytes.

/// Render a binary as `<<B1,B2,...>>` (~w form; empty → `<<>>`).
fn writeBinaryW(m: *Machine, out: *std.ArrayList(u8), t: Term) BifError!void {
    const bytes = FinalTerms.binBytes(&m.ctx, t);
    try out.appendSlice(m.ctx.gpa, "<<");
    for (bytes, 0..) |b, i| {
        if (i > 0) try out.append(m.ctx.gpa, ',');
        try out.print(m.ctx.gpa, "{d}", .{b});
    }
    try out.appendSlice(m.ctx.gpa, ">>");
}

/// Write one byte with the oracle's ~p string escaping (the writeString table).
fn writeEscapedByte(m: *Machine, out: *std.ArrayList(u8), c: u8) BifError!void {
    switch (c) {
        8 => try out.appendSlice(m.ctx.gpa, "\\b"),
        9 => try out.appendSlice(m.ctx.gpa, "\\t"),
        10 => try out.appendSlice(m.ctx.gpa, "\\n"),
        11 => try out.appendSlice(m.ctx.gpa, "\\v"),
        12 => try out.appendSlice(m.ctx.gpa, "\\f"),
        13 => try out.appendSlice(m.ctx.gpa, "\\r"),
        27 => try out.appendSlice(m.ctx.gpa, "\\e"),
        '"' => try out.appendSlice(m.ctx.gpa, "\\\""),
        '\\' => try out.appendSlice(m.ctx.gpa, "\\\\"),
        else => try out.append(m.ctx.gpa, c),
    }
}

/// Render a binary in `~p` form: `<<"...">>` iff NON-empty and every byte is
/// printable (oracle heuristic + escaping); else the `<<B1,...>>` byte form.
fn writeBinaryP(m: *Machine, out: *std.ArrayList(u8), t: Term) BifError!void {
    const bytes = FinalTerms.binBytes(&m.ctx, t);
    var printable = bytes.len > 0;
    for (bytes) |b| {
        if (!isPrintableChar(b)) {
            printable = false;
            break;
        }
    }
    if (!printable) return writeBinaryW(m, out, t);
    try out.appendSlice(m.ctx.gpa, "<<\"");
    for (bytes) |b| try writeEscapedByte(m, out, b);
    try out.appendSlice(m.ctx.gpa, "\">>");
}

/// `~p` = `~w` structure + the recursive printable-string heuristic. Single-line
/// (line-wrapping past column 80 is a NAMED deferral — byte-EQ for terms that fit).
fn writeTermP(m: *Machine, out: *std.ArrayList(u8), t: Term) BifError!void {
    switch (FinalTerms.kindOf(&m.ctx, t)) {
        .cons => {
            if (isPrintableList(m, t)) return writeString(m, out, t);
            try out.append(m.ctx.gpa, '[');
            var cur = t;
            var first = true;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
                if (!first) try out.append(m.ctx.gpa, ',');
                first = false;
                try writeTermP(m, out, FinalTerms.listHead(&m.ctx, cur));
                cur = FinalTerms.listTail(&m.ctx, cur);
            }
            if (FinalTerms.kindOf(&m.ctx, cur) != .nil) {
                try out.append(m.ctx.gpa, '|');
                try writeTermP(m, out, cur);
            }
            try out.append(m.ctx.gpa, ']');
        },
        .tuple => {
            try out.append(m.ctx.gpa, '{');
            const n = FinalTerms.tupleArity(&m.ctx, t);
            var k: usize = 0;
            while (k < n) : (k += 1) {
                if (k > 0) try out.append(m.ctx.gpa, ',');
                try writeTermP(m, out, FinalTerms.tupleElem(&m.ctx, t, k));
            }
            try out.append(m.ctx.gpa, '}');
        },
        .map => try writeMap(m, out, t, writeTermP), // ~p: recurse with heuristic
        .binary => try writeBinaryP(m, out, t), // ~p: <<"...">> if printable else <<B,...>>
        else => try writeTerm(m, out, t), // number/atom/nil: identical to ~w
    }
}

// ── gap-io-format-pwrap: ~p/~P MULTI-LINE pretty-printing (io_lib_pretty.erl
// transliterated, byte-EQ vs the pinned oracle) ──
//
// OTP's algorithm is two-phase: (1) `print_length` builds a SIZED intermediate
// tree (flat width per node, depth threading), (2) `pp` emits with per-element
// fits tests; `cind` dry-runs to pick the tagged-tuple fallback indent TInd ∈
// {-1, 4, 1}. `chars_limit` is ALWAYS -1 for io_lib:format, which kills the
// whole More/expand/find_upper machinery — deliberately NOT implemented (the
// boundary: a future {chars_limit,N} surface needs it back). Key oracle-pinned
// facts: F = LINE LENGTH (default 80, 0 ⇒ flat), P = START COLUMN (default =
// current output column + 1, so preceding text shifts wrapping), `~-Fp` is
// badarg (no left clause), only LEAVES pack multi-per-line (composites get own
// lines; strings ARE leaves), leaf strings never wrap (may overflow), tagged
// tuples align after the tag or fall back to a TInd=4 staircase, ~P pops a
// SECOND depth arg (0 ⇒ "...", <0 ⇒ unlimited; the string heuristic is OFF at
// depth 1). Inequalities are transliterated subtraction-free with their
// io_lib_pretty.erl anchors (pp=236, pp_tag_tuple=259, pp_tail=383,
// pp_element=408, cind_tag_tuple=1434, last_depth=1585) — do NOT "simplify"
// the strict-< / <= asymmetries; the boundary laws pin them.

/// Sized intermediate node (io_lib_pretty intermediate_format, chars_limit
/// machinery removed). All nodes/strings live in a per-call arena.
const PNode = struct {
    shape: Shape,
    len: usize, // flat printed width

    const Shape = union(enum) {
        str: []const u8,
        list: Seq,
        tuple: struct { tagged: bool, seq: Seq },
    };
    const Tail = union(enum) { nil, dots, improper: *PNode };
    const Seq = struct { elems: []*PNode, tail: Tail };
    fn isLeaf(n: *const PNode) bool {
        return n.shape == .str;
    }
    fn seqOf(n: *const PNode) Seq {
        return switch (n.shape) {
            .list => |s| s,
            .tuple => |tu| tu.seq,
            .str => unreachable,
        };
    }
};

/// Render a LEAF term (int/float/atom/nil) through the landed byte-exact `~w`
/// writer into the arena.
fn leafStr(m: *Machine, a: std.mem.Allocator, t: Term) BifError![]const u8 {
    var tmp: std.ArrayList(u8) = .empty;
    defer tmp.deinit(m.ctx.gpa);
    try writeTerm(m, &tmp, t);
    return a.dupe(u8, tmp.items) catch return error.OutOfMemory;
}

/// Phase 1 — `print_length` with chars_limit=-1. depth<0 = unlimited; a
/// container VISITED at depth 1 collapses ("[...]"/"{...}"); element i of a
/// container is measured at depth-i (the countdown that yields `|...`/`,...`
/// tails); the printable-string heuristic is disabled at depth 1 (P37).
fn measure(m: *Machine, a: std.mem.Allocator, t: Term, depth: i64) BifError!*PNode {
    const node = a.create(PNode) catch return error.OutOfMemory;
    switch (FinalTerms.kindOf(&m.ctx, t)) {
        .cons => {
            if (depth == 1) {
                node.* = .{ .shape = .{ .str = "[...]" }, .len = 5 };
                return node;
            }
            if (isPrintableList(m, t)) {
                var tmp: std.ArrayList(u8) = .empty;
                defer tmp.deinit(m.ctx.gpa);
                try writeString(m, &tmp, t);
                const s = a.dupe(u8, tmp.items) catch return error.OutOfMemory;
                node.* = .{ .shape = .{ .str = s }, .len = s.len };
                return node;
            }
            var elems: std.ArrayList(*PNode) = .empty;
            var tail: PNode.Tail = .nil;
            var lensum: usize = 0;
            var ed = depth;
            var cur = t;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
                ed -= 1;
                if (ed == 0) {
                    tail = .dots;
                    break;
                }
                const e = try measure(m, a, FinalTerms.listHead(&m.ctx, cur), ed);
                elems.append(a, e) catch return error.OutOfMemory;
                lensum += e.len;
                cur = FinalTerms.listTail(&m.ctx, cur);
            }
            if (tail != .dots and FinalTerms.kindOf(&m.ctx, cur) != .nil) {
                ed -= 1;
                if (ed == 0) tail = .dots else {
                    const tn = try measure(m, a, cur, ed);
                    tail = .{ .improper = tn };
                }
            }
            var len: usize = 2 + lensum;
            if (elems.items.len > 1) len += elems.items.len - 1; // commas
            switch (tail) {
                .nil => {},
                .dots => len += 4, // "|..."
                .improper => |tn| len += 1 + tn.len,
            }
            node.* = .{ .shape = .{ .list = .{ .elems = elems.items, .tail = tail } }, .len = len };
        },
        .tuple => {
            if (depth == 1) {
                node.* = .{ .shape = .{ .str = "{...}" }, .len = 5 };
                return node;
            }
            const arity = FinalTerms.tupleArity(&m.ctx, t);
            var elems: std.ArrayList(*PNode) = .empty;
            var tail: PNode.Tail = .nil;
            var lensum: usize = 0;
            var ed = depth;
            var k: usize = 0;
            while (k < arity) : (k += 1) {
                ed -= 1;
                if (ed == 0) {
                    tail = .dots;
                    break;
                }
                const e = try measure(m, a, FinalTerms.tupleElem(&m.ctx, t, k), ed);
                elems.append(a, e) catch return error.OutOfMemory;
                lensum += e.len;
            }
            var len: usize = 2 + lensum;
            if (elems.items.len > 1) len += elems.items.len - 1;
            if (tail == .dots) len += 4; // ",..."
            const tagged = arity >= 2 and FinalTerms.repIsAtom(FinalTerms.tupleElem(&m.ctx, t, 0));
            node.* = .{ .shape = .{ .tuple = .{ .tagged = tagged, .seq = .{ .elems = elems.items, .tail = tail } } }, .len = len };
        },
        .map => {
            // ~p/~P of a map: depth 1 collapses to "#{...}"; otherwise render
            // FLAT (as a str leaf — multi-line map wrapping is a disclosed
            // deferral) with keys in canonical exact-term order and each pair's
            // key/value measured at depth-1 (so a nested map collapses at the
            // depth-1 boundary: `#{a => #{...}}`). The per-pair `...` truncation
            // of an over-wide small-depth map is NOT modelled (irreproducible
            // erts order); byte-EQ holds for the reproducible subset.
            if (depth == 1) {
                node.* = .{ .shape = .{ .str = "#{...}" }, .len = 6 };
                return node;
            }
            const cnt = FinalTerms.mapSize(&m.ctx, t);
            var tmp: std.ArrayList(u8) = .empty;
            defer tmp.deinit(m.ctx.gpa);
            try tmp.appendSlice(m.ctx.gpa, "#{");
            if (cnt > 0) {
                const pk = m.ctx.gpa.alloc(Term, cnt) catch return error.OutOfMemory;
                defer m.ctx.gpa.free(pk);
                const pv = m.ctx.gpa.alloc(Term, cnt) catch return error.OutOfMemory;
                defer m.ctx.gpa.free(pv);
                _ = FinalTerms.mapPairs(&m.ctx, t, pk, pv);
                const idx = m.ctx.gpa.alloc(usize, cnt) catch return error.OutOfMemory;
                defer m.ctx.gpa.free(idx);
                for (idx, 0..) |*s, i| s.* = i;
                const SortCtx = struct {
                    m: *Machine,
                    keys: []const Term,
                    fn less(s: @This(), x: usize, y: usize) bool {
                        return FinalTerms.compareExact(&s.m.ctx, s.keys[x], s.keys[y]) == .lt;
                    }
                };
                std.sort.insertion(usize, idx, SortCtx{ .m = m, .keys = pk }, SortCtx.less);
                const ed = depth - 1; // nested containers collapse one level in
                // DIVERGENCE 699: PER-PAIR depth truncation — like `.cons`/`.tuple`,
                // a `~P`/`~p` map at depth D shows only D-1 pairs then `,...` (erts
                // io_lib_pretty:print_length_map). `depth<0` = unlimited.
                const shown: usize = if (depth < 0) cnt else @min(cnt, @as(usize, @intCast(depth - 1)));
                for (idx[0..shown], 0..) |i, j| {
                    if (j > 0) try tmp.append(m.ctx.gpa, ',');
                    try writeFlat(m, &tmp, try measure(m, a, pk[i], ed));
                    try tmp.appendSlice(m.ctx.gpa, " => ");
                    try writeFlat(m, &tmp, try measure(m, a, pv[i], ed));
                }
                if (shown < cnt) {
                    if (shown > 0) try tmp.append(m.ctx.gpa, ',');
                    try tmp.appendSlice(m.ctx.gpa, "...");
                }
            }
            try tmp.append(m.ctx.gpa, '}');
            const s = a.dupe(u8, tmp.items) catch return error.OutOfMemory;
            node.* = .{ .shape = .{ .str = s }, .len = s.len };
        },
        .binary => {
            // ~p/~P of a binary: depth 1 collapses to "<<...>>" (like [...]/{...});
            // otherwise the printable heuristic (<<"...">> or <<B,...>>).
            if (depth == 1) {
                node.* = .{ .shape = .{ .str = "<<...>>" }, .len = 7 };
                return node;
            }
            var tmp: std.ArrayList(u8) = .empty;
            defer tmp.deinit(m.ctx.gpa);
            try writeBinaryP(m, &tmp, t);
            const s = a.dupe(u8, tmp.items) catch return error.OutOfMemory;
            node.* = .{ .shape = .{ .str = s }, .len = s.len };
        },
        else => {
            const s = try leafStr(m, a, t);
            node.* = .{ .shape = .{ .str = s }, .len = s.len };
        },
    }
    return node;
}

/// Flat writer over the sized tree (== io_lib_pretty:write intermediate form);
/// for unlimited depth this equals `writeTermP(t)` byte-for-byte (the
/// homomorphism the seeded law pins).
fn writeFlat(m: *Machine, out: *std.ArrayList(u8), n: *const PNode) BifError!void {
    const gpa = m.ctx.gpa;
    switch (n.shape) {
        .str => |s| try out.appendSlice(gpa, s),
        .list => |seq| {
            try out.append(gpa, '[');
            for (seq.elems, 0..) |e, i| {
                if (i > 0) try out.append(gpa, ',');
                try writeFlat(m, out, e);
            }
            switch (seq.tail) {
                .nil => {},
                .dots => try out.appendSlice(gpa, "|..."),
                .improper => |tn| {
                    try out.append(gpa, '|');
                    try writeFlat(m, out, tn);
                },
            }
            try out.append(gpa, ']');
        },
        .tuple => |tu| {
            try out.append(gpa, '{');
            for (tu.seq.elems, 0..) |e, i| {
                if (i > 0) try out.append(gpa, ',');
                try writeFlat(m, out, e);
            }
            if (tu.seq.tail == .dots) try out.appendSlice(gpa, ",...");
            try out.append(gpa, '}');
        },
    }
}

/// Phase 2 emission state. `ind` is the indent prefix written after every
/// break (invariant: len(ind) == the enclosing container's Col0 - 1).
const Pp = struct {
    m: *Machine,
    out: *std.ArrayList(u8),
    ll: usize, // line length (F)
    cmax: usize, // M = top-level flat length (the CHAR_MAX conjuncts)
    tind: i64, // tagged-tuple fallback indent: -1 | 4 | 1
    ind: std.ArrayList(u8),
};

fn setInd(p: *Pp, target: usize) BifError!void {
    if (p.ind.items.len > target) {
        p.ind.shrinkRetainingCapacity(target);
    } else while (p.ind.items.len < target) {
        p.ind.append(p.m.ctx.gpa, ' ') catch return error.OutOfMemory;
    }
}

fn newlineInd(p: *Pp) BifError!void {
    try p.out.append(p.m.ctx.gpa, '\n');
    try p.out.appendSlice(p.m.ctx.gpa, p.ind.items);
}

/// last_depth (io_lib_pretty:1585): closers pending after this element — 0
/// while more elements (or any tail) follow; LD+1 on the true last.
fn lastDepth(more: bool, tail: PNode.Tail, ld: usize) usize {
    if (more) return 0;
    return switch (tail) {
        .nil => ld + 1,
        else => 0,
    };
}

/// pp (io_lib_pretty:236): flat if it fits, else break the container open.
fn pp(p: *Pp, n: *const PNode, col: usize, ld: usize, w: usize) BifError!void {
    const gpa = p.m.ctx.gpa;
    if (n.len + col + ld < p.ll and n.len + w + ld <= p.cmax) return writeFlat(p.m, p.out, n);
    switch (n.shape) {
        .str => |s| try p.out.appendSlice(gpa, s), // leaf overflow allowed (P15/P17)
        .list => |seq| {
            try p.out.append(gpa, '[');
            try ppSeq(p, seq, col + 1, ld, '|', w + 1);
            try p.out.append(gpa, ']');
        },
        .tuple => |tu| {
            try p.out.append(gpa, '{');
            if (tu.tagged and tu.seq.elems.len >= 2) {
                // pp_tag_tuple receives the '{' COLUMN itself — its TagInd =
                // Tlen + 2 accounts for both the brace and the comma (Tcol =
                // Col + Tlen + 2 = the first aligned element's column).
                try ppTagTuple(p, tu.seq, col, ld, w + 1);
            } else {
                try ppSeq(p, tu.seq, col + 1, ld, ',', w + 1);
            }
            try p.out.append(gpa, '}');
        },
    }
}

/// pp_element (io_lib_pretty:408): a fitting LEAF writes flat and advances Col
/// by its width; anything else recurses and returns Ll (poisoning Col so the
/// NEXT element breaks — the P35 "7000 alone on a line" behavior).
fn ppElement(p: *Pp, e: *const PNode, col: usize, ld: usize, w: usize) BifError!usize {
    if (e.isLeaf() and e.len + col + ld < p.ll and e.len + w + ld <= p.cmax) {
        try writeFlat(p.m, p.out, e);
        return e.len;
    }
    try pp(p, e, col, ld, w);
    return p.ll;
}

/// pp_list (io_lib_pretty:pp_list): first element then the tail loop.
fn ppSeq(p: *Pp, seq: PNode.Seq, col0: usize, ld: usize, sep: u8, w: usize) BifError!void {
    const save = p.ind.items.len;
    try setInd(p, col0 - 1);
    defer p.ind.shrinkRetainingCapacity(save);
    if (seq.elems.len == 0) {
        if (seq.tail == .dots) try p.out.appendSlice(p.m.ctx.gpa, "...");
        return;
    }
    const ld0 = lastDepth(seq.elems.len > 1, seq.tail, ld);
    const we = try ppElement(p, seq.elems[0], col0, ld0, w);
    try ppTail(p, seq.elems[1..], seq.tail, col0, col0 + we, ld, sep, w + we);
}

/// pp_tail (io_lib_pretty:383): the comma/inline-vs-break loop + tail closers.
fn ppTail(p: *Pp, rest: []*PNode, tail: PNode.Tail, col0: usize, col_in: usize, ld: usize, sep: u8, w_in: usize) BifError!void {
    const gpa = p.m.ctx.gpa;
    var col = col_in;
    var w = w_in;
    var idx: usize = 0;
    while (idx < rest.len) : (idx += 1) {
        const e = rest[idx];
        const ld1 = lastDepth(idx + 1 < rest.len, tail, ld);
        const elen = 1 + e.len; // the comma + the element
        const fits = if (ld1 == 0)
            (e.isLeaf() and elen + 1 + col < p.ll and w + elen + 1 <= p.cmax)
        else
            (e.isLeaf() and elen + col + ld1 < p.ll and w + elen + ld1 <= p.cmax);
        if (fits) {
            try p.out.append(gpa, ',');
            try writeFlat(p.m, p.out, e);
            col += elen;
            w += elen;
        } else {
            try p.out.append(gpa, ',');
            try newlineInd(p);
            const we = try ppElement(p, e, col0, ld1, 0);
            col = col0 + we;
            w = we;
        }
    }
    switch (tail) {
        .nil => {},
        .dots => {
            try p.out.append(gpa, sep);
            try p.out.appendSlice(gpa, "...");
        },
        .improper => |tn| {
            if (tn.isLeaf() and tn.len + 1 + col + ld + 1 < p.ll and tn.len + 1 + w + ld + 1 <= p.cmax) {
                try p.out.append(gpa, '|');
                try writeFlat(p.m, p.out, tn);
            } else {
                try p.out.append(gpa, '|');
                try newlineInd(p);
                try pp(p, tn, col0, ld + 1, 0);
            }
        },
    }
}

/// pp_tag_tuple (io_lib_pretty:259): align the remaining elements after the
/// tag ("{error,<here>") unless the chosen TInd forces the staircase (P11).
fn ppTagTuple(p: *Pp, seq: PNode.Seq, col: usize, ld: usize, w: usize) BifError!void {
    const gpa = p.m.ctx.gpa;
    const tag = seq.elems[0];
    const tlen = tag.len;
    const tagind = tlen + 2;
    const tcol = col + tagind;
    if (p.tind > 0 and tagind > @as(usize, @intCast(p.tind))) {
        // staircase: tag alone; pp_tail supplies each element's comma/break.
        try writeFlat(p.m, p.out, tag);
        const col0b = col + @as(usize, @intCast(p.tind));
        const save = p.ind.items.len;
        try setInd(p, col0b - 1);
        defer p.ind.shrinkRetainingCapacity(save);
        try ppTail(p, seq.elems[1..], seq.tail, col0b, tcol, ld, ',', w + tlen);
    } else {
        try writeFlat(p.m, p.out, tag);
        try p.out.append(gpa, ',');
        try ppSeq(p, .{ .elems = seq.elems[1..], .tail = seq.tail }, tcol, ld, ',', w + tlen + 1);
    }
}

// ── cind: the TInd dry run (io_lib_pretty:cind/cind_tag_tuple:1434) — the SAME
// recursion/fits shape as pp with no output; throws NoGood only where a tagged
// tuple's alignment column violates the trial's bound. ──
const CindErr = error{ NoGood, OutOfMemory };

fn cind(p: *const Pp, tind: i64, n: *const PNode, col: usize, ld: usize, w: usize) CindErr!void {
    if (n.len + col + ld < p.ll and n.len + w + ld <= p.cmax) return;
    switch (n.shape) {
        .str => {},
        .list => |seq| try cindSeq(p, tind, seq, col + 1, ld, w + 1),
        .tuple => |tu| {
            if (tu.tagged and tu.seq.elems.len >= 2) {
                try cindTagTuple(p, tind, tu.seq, col, ld, w + 1); // '{'-column convention
            } else try cindSeq(p, tind, tu.seq, col + 1, ld, w + 1);
        },
    }
}

fn cindElement(p: *const Pp, tind: i64, e: *const PNode, col: usize, ld: usize, w: usize) CindErr!usize {
    if (e.isLeaf() and e.len + col + ld < p.ll and e.len + w + ld <= p.cmax) return e.len;
    try cind(p, tind, e, col, ld, w);
    return p.ll;
}

fn cindSeq(p: *const Pp, tind: i64, seq: PNode.Seq, col0: usize, ld: usize, w: usize) CindErr!void {
    if (seq.elems.len == 0) return;
    const ld0 = lastDepth(seq.elems.len > 1, seq.tail, ld);
    const we = try cindElement(p, tind, seq.elems[0], col0, ld0, w);
    try cindTail(p, tind, seq.elems[1..], seq.tail, col0, col0 + we, ld, w + we);
}

fn cindTail(p: *const Pp, tind: i64, rest: []*PNode, tail: PNode.Tail, col0: usize, col_in: usize, ld: usize, w_in: usize) CindErr!void {
    var col = col_in;
    var w = w_in;
    var idx: usize = 0;
    while (idx < rest.len) : (idx += 1) {
        const e = rest[idx];
        const ld1 = lastDepth(idx + 1 < rest.len, tail, ld);
        const elen = 1 + e.len;
        const fits = if (ld1 == 0)
            (e.isLeaf() and elen + 1 + col < p.ll and w + elen + 1 <= p.cmax)
        else
            (e.isLeaf() and elen + col + ld1 < p.ll and w + elen + ld1 <= p.cmax);
        if (fits) {
            col += elen;
            w += elen;
        } else {
            const we = try cindElement(p, tind, e, col0, ld1, 0);
            col = col0 + we;
            w = we;
        }
    }
    if (tail == .improper) {
        const tn = tail.improper;
        if (!(tn.isLeaf() and tn.len + 1 + col + ld + 1 < p.ll and tn.len + 1 + w + ld + 1 <= p.cmax))
            try cind(p, tind, tn, col0, ld + 1, 0);
    }
}

fn cindTagTuple(p: *const Pp, tind: i64, seq: PNode.Seq, col: usize, ld: usize, w: usize) CindErr!void {
    const tag = seq.elems[0];
    const tagind = tag.len + 2;
    const tcol = col + tagind;
    if (tind > 0 and tagind > @as(usize, @intCast(tind))) {
        // TInd=4 trial: `M + Col1 <= Ll or Col1 <= Ll div 2` (note <=, laxer).
        const col1 = col + @as(usize, @intCast(tind));
        if (!(p.cmax + col1 <= p.ll or col1 <= p.ll / 2)) return error.NoGood;
        try cindTail(p, tind, seq.elems[1..], seq.tail, col1, tcol, ld, w + tag.len);
    } else {
        // TInd=-1 trial: `M + Tcol < Ll or Tcol < Ll div 2` (strict).
        if (!(p.cmax + tcol < p.ll or tcol < p.ll / 2)) return error.NoGood;
        try cindSeq(p, tind, .{ .elems = seq.elems[1..], .tail = seq.tail }, tcol, ld, w + tag.len + 1);
    }
}

/// while_fail([-1,4], cind, 1): the first trial whose dry run does not throw.
fn computeTInd(p: *const Pp, n: *const PNode, col: usize) i64 {
    for ([_]i64{ -1, 4 }) |trial| {
        cind(p, trial, n, col, 0, 0) catch continue;
        return trial;
    }
    return 1;
}

/// Column of the next output char (io_lib:indentation): chars since the last
/// '\n', a tab advancing to the next multiple of 8.
fn currentColumn(out: *const std.ArrayList(u8)) usize {
    var start: usize = 0;
    if (std.mem.lastIndexOfScalar(u8, out.items, '\n')) |k| start = k + 1;
    var c: usize = 0;
    for (out.items[start..]) |ch| {
        if (ch == '\t') c = (c / 8 + 1) * 8 else c += 1;
    }
    return c;
}

/// The ~p/~P entry (io_lib_pretty:print/10 top logic). `col` is 1-based;
/// ll==0 ⇒ unconditional flat; leaves never wrap (clause order). Measure-then-
/// emit: an unsupported kind badargs BEFORE any bytes are written.
fn writeTermPretty(m: *Machine, out: *std.ArrayList(u8), t: Term, depth: i64, ll: usize, col_in: usize) BifError!void {
    if (depth == 0) return out.appendSlice(m.ctx.gpa, "...");
    var arena = std.heap.ArenaAllocator.init(m.ctx.gpa);
    defer arena.deinit();
    const n = try measure(m, arena.allocator(), t, depth);
    const col: usize = @max(col_in, 1);
    if (n.isLeaf() or ll == 0 or n.len + col < ll) return writeFlat(m, out, n);
    var p = Pp{ .m = m, .out = out, .ll = ll, .cmax = n.len, .tind = 1, .ind = .empty };
    defer p.ind.deinit(m.ctx.gpa);
    p.tind = computeTInd(&p, n, col);
    try setInd(&p, col - 1);
    try pp(&p, n, col, 0, 0);
}

/// Flatten a `~s`/`~ts` string arg (atom→name, or charlist/iolist). When
/// `uni` (the `t` modifier), an integer element is a UNICODE CODEPOINT emitted
/// as UTF-8 (0..0x10FFFF, excl. surrogates — else badarg); a binary is treated
/// as already-encoded chardata and passed through. When latin1 (`~s`), an
/// integer >255 is badarg and a binary is raw bytes — the pinned-OTP contract.
fn appendStringArg(m: *Machine, out: *std.ArrayList(u8), t: Term, uni: bool) BifError!void {
    switch (FinalTerms.kindOf(&m.ctx, t)) {
        .atom => try writeAtomName(m, out, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(t))),
        .nil => {},
        .cons => {
            var cur = t;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
                const h = FinalTerms.listHead(&m.ctx, cur);
                if (FinalTerms.repIsSmall(h)) {
                    const c = FinalTerms.smallValOf(h);
                    if (uni) {
                        // ~ts: a unicode codepoint → UTF-8 (ascii stays one byte).
                        if (c < 0 or c > 0x10FFFF) return error.Badarg;
                        var b4: [4]u8 = undefined;
                        const n = unicode.encodeCp(@intCast(c), &b4) catch return error.Badarg;
                        try out.appendSlice(m.ctx.gpa, b4[0..n]);
                    } else {
                        if (c < 0 or c > 255) return error.Badarg; // latin1
                        try out.append(m.ctx.gpa, @intCast(c));
                    }
                } else try appendStringArg(m, out, h, uni); // nested iolist
                cur = FinalTerms.listTail(&m.ctx, cur);
            }
            if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg;
        },
        // ~s: raw latin1 bytes; ~ts: the binary is already chardata (UTF-8) → pass through.
        .binary => try out.appendSlice(m.ctx.gpa, FinalTerms.binBytes(&m.ctx, t)),
        else => return error.Badarg, // pid/ref/fun deferred
    }
}

/// `~b`/`~B`/`~x`/`~X`/`~+`: integer in base `base` (precision, default 10).
/// `upper` selects UPPERCASE digits (~B/~X → "1F"; ~b/~x/~+ → "1f"). `prefix`
/// is inserted AFTER a leading '-' but BEFORE the digits (~x → "-0x31";
/// ~+ → "-16#1f"). Oracle-pinned casing: ~.16b/x/+ = lowercase, ~.16B/X =
/// uppercase; `-` always precedes the prefix. base ∈ [2,36] else badarg.
fn writeBaseFull(m: *Machine, out: *std.ArrayList(u8), v: i64, base: i64, prefix: []const u8, upper: bool) BifError!void {
    if (base < 2 or base > 36) return error.Badarg;
    var buf: [72]u8 = undefined;
    var n: usize = 0;
    const neg = v < 0;
    var u: u64 = if (neg) @intCast(-v) else @intCast(v);
    const digits = if (upper) "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" else "0123456789abcdefghijklmnopqrstuvwxyz";
    const b: u64 = @intCast(base);
    if (u == 0) {
        buf[0] = '0';
        n = 1;
    }
    while (u > 0) {
        buf[n] = digits[@intCast(u % b)];
        n += 1;
        u /= b;
    }
    if (neg) try out.append(m.ctx.gpa, '-');
    try out.appendSlice(m.ctx.gpa, prefix);
    var k = n;
    while (k > 0) {
        k -= 1;
        try out.append(m.ctx.gpa, buf[k]);
    }
}

/// DIVERGENCE 703: the BIGNUM sibling of `writeBaseFull` — `~b`/`~B`/`~x`/`~X`/`~+`
/// of a bignum (>= 2^59) raised `badarg` because the `readInt` → `i64` path
/// rejected it (the DIVERGENCE-689 `~w`/`~p` fix did not cover the based-int
/// controls). Formats `|value|` in `base` via `std.math.big` over the term's own
/// limbs, preserving the sign-then-prefix-then-digits order (the `-` precedes the
/// prefix, exactly like the i64 path).
fn writeBaseFullBig(m: *Machine, out: *std.ArrayList(u8), t: Term, base: i64, prefix: []const u8, upper: bool) BifError!void {
    if (base < 2 or base > 36) return error.Badarg;
    const parts = FinalTerms.bigPartsOf(&m.ctx, t);
    const c = std.math.big.int.Const{ .limbs = parts.limbs, .positive = parts.positive };
    const s = c.toStringAlloc(m.ctx.gpa, @intCast(base), if (upper) .upper else .lower) catch return error.OutOfMemory;
    defer m.ctx.gpa.free(s);
    if (s.len > 0 and s[0] == '-') {
        try out.append(m.ctx.gpa, '-'); // sign FIRST, then prefix, then digits
        try out.appendSlice(m.ctx.gpa, prefix);
        try out.appendSlice(m.ctx.gpa, s[1..]);
    } else {
        try out.appendSlice(m.ctx.gpa, prefix);
        try out.appendSlice(m.ctx.gpa, s);
    }
}

// ── gap-io-format-float: ~e/~f/~g + float ~w — byte-EQ vs the pinned oracle ──
//
// OTP's float pipeline is STRING arithmetic over ONE base representation
// (io_lib_format: float_data → float_man → fwrite_e/f/g), and replicating that
// pipeline — not "format a double" — is what makes byte-EQ achievable. Two-stage
// rounding is SEMANTIC: exact→21 significant digits (nearest, ties-to-even, the
// erts %.20e), then 21→P HALF-UP on the digit STRING (oracle pair: ~.1f 0.25 →
// "0.3" but ~.2f 2.675 → "2.67" — only the staged scheme yields both).
// CRITICAL: Zig std.fmt {e:.20} zero-pads the SHORTEST digits (3.14 →
// …000000e0, not the true …012434) — it CANNOT supply the base digits, so
// `floatData` generates them exactly (m×2^e2 → decimal via bounded ×2/×5 digit
// loops, stack-only). Sign is ALWAYS `signbit`, never `f < 0.0` (-0.0 keeps its
// sign; ~.1f -0.04 → "-0.0" is a NEGATIVE zero from a nonzero input).

const FloatData = struct { neg: bool, ds: [21]u8, e: i32 };

/// ×2 / ×5 over a little-endian decimal digit buffer (values 0..9). Max length
/// 5^1074 of a 16-digit m ≈ 767 digits — the [800]u8 bound holds structurally.
fn mulSmall(d: *[800]u8, len: *usize, k: u8) void {
    var carry: u32 = 0;
    var i: usize = 0;
    while (i < len.*) : (i += 1) {
        const v = @as(u32, d[i]) * k + carry;
        d[i] = @intCast(v % 10);
        carry = v / 10;
    }
    while (carry > 0) {
        d[len.*] = @intCast(carry % 10);
        carry /= 10;
        len.* += 1;
    }
}

/// The exact 21-significant-digit decimal of |f| — OTP `float_data/1` over the
/// erts `%.20e` base (nearest, ties-to-even at digit 21). `e` = decimal-point
/// position (3.14 → e=1; 100.0 → 3; 0.001 → -2; ±0.0 → all-zero ds, e=1).
fn floatData(f: f64) FloatData {
    const bits: u64 = @bitCast(f);
    var fd = FloatData{ .neg = (bits >> 63) != 0, .ds = [_]u8{'0'} ** 21, .e = 1 };
    const expf: u64 = (bits >> 52) & 0x7ff;
    const frac: u64 = bits & ((@as(u64, 1) << 52) - 1);
    if (expf == 0 and frac == 0) return fd; // ±0.0
    var mant: u64 = undefined;
    var e2: i32 = undefined;
    if (expf == 0) { // subnormal: no implicit bit
        mant = frac;
        e2 = -1074;
    } else {
        mant = frac | (@as(u64, 1) << 52);
        e2 = @as(i32, @intCast(expf)) - 1075;
    }
    var d: [800]u8 = undefined;
    var len: usize = 0;
    var mm = mant;
    while (mm > 0) : (mm /= 10) {
        d[len] = @intCast(mm % 10);
        len += 1;
    }
    var point: i32 = undefined;
    if (e2 >= 0) {
        var k: i32 = 0;
        while (k < e2) : (k += 1) mulSmall(&d, &len, 2);
        point = @intCast(len);
    } else {
        var k: i32 = e2;
        while (k < 0) : (k += 1) mulSmall(&d, &len, 5);
        point = @as(i32, @intCast(len)) + e2;
    }
    if (len <= 21) {
        var i: usize = 0;
        while (i < len) : (i += 1) fd.ds[i] = '0' + d[len - 1 - i];
    } else {
        var i: usize = 0;
        while (i < 21) : (i += 1) fd.ds[i] = '0' + d[len - 1 - i];
        const r = d[len - 22]; // first dropped digit
        var sticky = false;
        var j: usize = 0;
        while (j < len - 22) : (j += 1) {
            if (d[j] != 0) {
                sticky = true;
                break;
            }
        }
        if (r > 5 or (r == 5 and (sticky or ((fd.ds[20] - '0') & 1) == 1))) {
            var ci: usize = 21;
            var carry = true;
            while (carry and ci > 0) {
                ci -= 1;
                if (fd.ds[ci] == '9') fd.ds[ci] = '0' else {
                    fd.ds[ci] += 1;
                    carry = false;
                }
            }
            if (carry) { // 999… rolled to 100…
                fd.ds[0] = '1';
                point += 1;
            }
        }
    }
    fd.e = point;
    return fd;
}

/// The (virtually zero-extended) significant-digit stream, shifted right by
/// `lead_zeros` (the fwrite_f E≤0 prepend): '0' before and past the 21 digits.
fn streamDigit(fd: *const FloatData, lead_zeros: usize, i: usize) u8 {
    if (i < lead_zeros) return '0';
    const j = i - lead_zeros;
    return if (j < 21) fd.ds[j] else '0';
}

/// OTP `float_man`: write `int_digits` digits + '.' + `dec_digits` digits off the
/// stream, HALF-UP rounded at the cut (first dropped digit ≥ '5' carries right-
/// to-left). Returns the carry-out (a rounded 9.99… overflow — the caller's
/// directive decides how "1" enters: replace-leading-zero for ~e, prepend for ~f).
fn floatMan(gpa: std.mem.Allocator, out: *std.ArrayList(u8), fd: *const FloatData, lead_zeros: usize, int_digits: usize, dec_digits: usize) BifError!bool {
    const t = int_digits + dec_digits;
    const dig = gpa.alloc(u8, t) catch return error.OutOfMemory;
    defer gpa.free(dig);
    var i: usize = 0;
    while (i < t) : (i += 1) dig[i] = streamDigit(fd, lead_zeros, i);
    var carry = false;
    if (streamDigit(fd, lead_zeros, t) >= '5') {
        carry = true;
        var k = t;
        while (carry and k > 0) {
            k -= 1;
            if (dig[k] == '9') dig[k] = '0' else {
                dig[k] += 1;
                carry = false;
            }
        }
    }
    try out.appendSlice(gpa, dig[0..int_digits]);
    try out.append(gpa, '.');
    try out.appendSlice(gpa, dig[int_digits..]);
    return carry;
}

/// The bounded-precision cap (OTP accepts absurd P; a multi-GB piece is a
/// hang-class hazard — bounded-driver rule, NAMED deferral past 2^20).
const float_prec_max: i64 = 1 << 20;

/// `~e` — fwrite_e: P = TOTAL significant digits (default 6), badarg below 2.
/// Exponent text is `e±d` with NO zero padding ("e+0", "e-300").
fn writeFloatE(m: *Machine, out: *std.ArrayList(u8), f: f64, p: i64) BifError!void {
    if (p < 2 or p > float_prec_max) return error.Badarg;
    const gpa = m.ctx.gpa;
    const fd = floatData(f);
    if (fd.neg) try out.append(gpa, '-');
    const start = out.items.len;
    const carry = try floatMan(gpa, out, &fd, 0, 1, @intCast(p - 1));
    var exp: i32 = fd.e - 1;
    if (carry) { // "9.999999" → "1.00000e+1": mantissa buffer is all zeros
        out.items[start] = '1';
        exp = fd.e;
    }
    const sign_ch: u8 = if (exp < 0) '-' else '+';
    try out.print(gpa, "e{c}{d}", .{ sign_ch, @abs(exp) });
}

/// `~f` — fwrite_f: P = DECIMAL places (default 6), badarg below 1. E ≤ 0
/// virtually prepends (1−E) zeros; the integer side past digit 21 is zeros
/// (~f 1.0e300 = the 21 real digits then 286 zeros then ".000000").
fn writeFloatF(m: *Machine, out: *std.ArrayList(u8), f: f64, p: i64) BifError!void {
    if (p < 1 or p > float_prec_max) return error.Badarg;
    const gpa = m.ctx.gpa;
    const fd = floatData(f);
    if (fd.neg) try out.append(gpa, '-');
    const start = out.items.len;
    var lead: usize = 0;
    var int_digits: usize = 1;
    if (fd.e <= 0) {
        lead = @intCast(1 - fd.e);
    } else int_digits = @intCast(fd.e);
    const carry = try floatMan(gpa, out, &fd, lead, int_digits, @intCast(p));
    if (carry) try out.insert(gpa, start, '1'); // "9.99" ~.1f → "10.0"
}

/// `~g` — fwrite_g: P = significant digits (default 6). Fixed form only for
/// 0.1 ≤ |f| < 10^4 (FLOAT comparisons, exactly these constants — 0.0 is
/// e-form); otherwise ~e. Verified against every oracle ~g probe row.
fn writeFloatG(m: *Machine, out: *std.ArrayList(u8), f: f64, p: i64) BifError!void {
    if (p < 1 or p > float_prec_max) return error.Badarg;
    const a = @abs(f);
    var cat: i64 = undefined;
    if (a < 1.0e-1) {
        cat = -2;
    } else if (a < 1.0e0) {
        cat = -1;
    } else if (a < 1.0e1) {
        cat = 0;
    } else if (a < 1.0e2) {
        cat = 1;
    } else if (a < 1.0e3) {
        cat = 2;
    } else if (a < 1.0e4) {
        cat = 3;
    } else return writeFloatE(m, out, f, p);
    if ((p <= 1 and cat == -1) or (p - 1 > cat and cat >= -1))
        return writeFloatF(m, out, f, p - 1 - cat);
    if (p <= 1) return writeFloatE(m, out, f, 2);
    return writeFloatE(m, out, f, p);
}

/// `~w`/`~p` of a float (and the float_to_list/1 [short] semantics): Zig {e}
/// shortest digits (probed == Ryū/OTP on the adversarial set) laid out as an
/// Erlang literal. FIXED iff |f| < 2^53 (strict — 9007199254740991.0 fixed,
/// …992.0 sci) AND fixed_len ≤ sci_len (ties fixed). Sci exponent `eN`/`e-N`,
/// no '+'.
fn writeFloatShortest(m: *Machine, out: *std.ArrayList(u8), f: f64) BifError!void {
    const gpa = m.ctx.gpa;
    if (std.math.signbit(f)) try out.append(gpa, '-');
    var buf: [40]u8 = undefined;
    const txt = std.fmt.bufPrint(&buf, "{e}", .{@abs(f)}) catch return error.Badarg;
    const epos = std.mem.indexOfScalar(u8, txt, 'e') orelse return error.Badarg;
    const k = std.fmt.parseInt(i32, txt[epos + 1 ..], 10) catch return error.Badarg;
    var digits_buf: [24]u8 = undefined;
    var n: usize = 0;
    for (txt[0..epos]) |c| {
        if (c != '.') {
            digits_buf[n] = c;
            n += 1;
        }
    }
    const digits = digits_buf[0..n];
    const point: i32 = k + 1;
    const ni: i32 = @intCast(n);
    const use_fixed = blk: {
        if (!(@abs(f) < 9007199254740992.0)) break :blk false; // 2^53, strict
        const fixed_len: usize = if (point <= 0)
            2 + @as(usize, @intCast(-point)) + n
        else if (point >= ni)
            @as(usize, @intCast(point)) + 2
        else
            n + 1;
        var ebuf: [8]u8 = undefined;
        const etxt = std.fmt.bufPrint(&ebuf, "{d}", .{point - 1}) catch unreachable;
        const sci_len = 2 + @max(@as(usize, 1), n - 1) + 1 + etxt.len;
        break :blk fixed_len <= sci_len;
    };
    if (use_fixed) {
        if (point <= 0) {
            try out.appendSlice(gpa, "0.");
            var z: i32 = point;
            while (z < 0) : (z += 1) try out.append(gpa, '0');
            try out.appendSlice(gpa, digits);
        } else if (point >= ni) {
            try out.appendSlice(gpa, digits);
            var z: i32 = ni;
            while (z < point) : (z += 1) try out.append(gpa, '0');
            try out.appendSlice(gpa, ".0");
        } else {
            try out.appendSlice(gpa, digits[0..@intCast(point)]);
            try out.append(gpa, '.');
            try out.appendSlice(gpa, digits[@intCast(point)..]);
        }
    } else {
        try out.append(gpa, digits[0]);
        try out.append(gpa, '.');
        if (n > 1) try out.appendSlice(gpa, digits[1..]) else try out.append(gpa, '0');
        try out.print(gpa, "e{d}", .{point - 1});
    }
}

/// io_lib_format `term/string`: pad a piece to the field width with `pad` on the
/// adjust side. `overflow == .stars` (the float directives): a piece LONGER than
/// the field renders as width×'*' (probed `~5f 3.14 → *****`); `.keep` preserves
/// the landed behavior of every other directive (their star semantics need their
/// own probes — a separate slice).
const Overflow = enum { keep, stars };

/// Truncate a `~s`/`~ts` buffer to at most `n` characters (DIVERGENCE 709). For
/// `~s` (latin1) a character is a byte; for `~ts` a character is a UTF-8
/// codepoint (truncation stops on a codepoint boundary — consistent with the
/// existing byte-emit ~ts scope for non-ASCII, exact for ASCII). Shorter-than-n
/// buffers are left untouched (precision is a max, not a min).
fn truncateStrPrecision(buf: *std.ArrayList(u8), n: usize, uni: bool) void {
    if (!uni) {
        if (buf.items.len > n) buf.shrinkRetainingCapacity(n);
        return;
    }
    var cps: usize = 0;
    var off: usize = 0;
    while (off < buf.items.len and cps < n) {
        const b = buf.items[off];
        const w: usize = if (b < 0x80) 1 else if (b >> 5 == 0x6) 2 else if (b >> 4 == 0xE) 3 else if (b >> 3 == 0x1e) 4 else 1;
        off += w;
        cps += 1;
    }
    if (off < buf.items.len) buf.shrinkRetainingCapacity(off);
}

fn applyField(m: *Machine, out: *std.ArrayList(u8), piece: []const u8, s: Spec, overflow: Overflow) BifError!void {
    const w: usize = if (s.width) |ww| @intCast(@max(ww, 0)) else 0;
    if (w > 0 and piece.len > w and overflow == .stars) {
        var k: usize = 0;
        while (k < w) : (k += 1) try out.append(m.ctx.gpa, '*');
        return;
    }
    if (piece.len >= w) {
        try out.appendSlice(m.ctx.gpa, piece);
        return;
    }
    const padn = w - piece.len;
    if (s.adjust == .right) {
        var k: usize = 0;
        while (k < padn) : (k += 1) try out.append(m.ctx.gpa, s.pad);
        try out.appendSlice(m.ctx.gpa, piece);
    } else {
        try out.appendSlice(m.ctx.gpa, piece);
        var k: usize = 0;
        while (k < padn) : (k += 1) try out.append(m.ctx.gpa, s.pad);
    }
}

fn emit(m: *Machine, out: *std.ArrayList(u8), s: Spec, args: *Term) BifError!void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(m.ctx.gpa);
    switch (s.ctrl) {
        '~' => try buf.append(m.ctx.gpa, '~'),
        'n' => try buf.append(m.ctx.gpa, '\n'),
        'i' => {
            _ = try popArg(m, args);
            return; // consume+ignore, no field
        },
        'c' => {
            // io_lib: ~c repeats the char `precision` times; precision DEFAULTS TO
            // THE FIELD WIDTH (so ~3c → "xxx"), else 1.
            const cp = try readInt(try popArg(m, args));
            const rep: usize = if (s.precision) |p|
                @intCast(@max(p, 0))
            else if (s.width) |w|
                @intCast(@max(w, 0))
            else
                1;
            var k: usize = 0;
            if (s.unicode) {
                // ~tc: repeat the codepoint (as UTF-8) `rep` times.
                if (cp < 0 or cp > 0x10FFFF) return error.Badarg;
                var b4: [4]u8 = undefined;
                const n = unicode.encodeCp(@intCast(cp), &b4) catch return error.Badarg;
                while (k < rep) : (k += 1) try buf.appendSlice(m.ctx.gpa, b4[0..n]);
            } else {
                const ch: u8 = @truncate(@as(u64, @bitCast(cp)));
                while (k < rep) : (k += 1) try buf.append(m.ctx.gpa, ch);
            }
        },
        's' => {
            // DIVERGENCE 709: ~s/~ts precision is a MAX character count — the
            // string is TRUNCATED to `precision` chars (then applyField pads to
            // width). DIVERGENCE 712: the field WIDTH is ALSO a max for ~s (unlike
            // numeric controls, which star on overflow) — a string wider than the
            // field is truncated to the field, so the field is EXACTLY `width`
            // chars (truncate if longer, pad if shorter; `~0s` → empty). erts
            // rejects `precision > width` (both given) as badarg.
            try appendStringArg(m, &buf, try popArg(m, args), s.unicode);
            if (s.precision) |p| {
                if (s.width) |w| if (p > w) return error.Badarg; // erts: P>W is badarg
                truncateStrPrecision(&buf, @intCast(@max(p, 0)), s.unicode);
            }
            if (s.width) |w| truncateStrPrecision(&buf, @intCast(@max(w, 0)), s.unicode);
        },
        'b', 'B' => {
            // DIVERGENCE 703: a BIGNUM arg takes the std.math.big path, not readInt(i64).
            const arg = try popArg(m, args);
            const base: i64 = if (s.precision) |p| p else 10;
            if (FinalTerms.repIsBig(&m.ctx, arg))
                try writeBaseFullBig(m, &buf, arg, base, "", s.ctrl == 'B')
            else
                try writeBaseFull(m, &buf, try readInt(arg), base, "", s.ctrl == 'B');
        },
        'x', 'X' => {
            // ~x/~X: like ~b/~B but a SECOND arg (a deep charlist or atom) is a
            // prefix inserted after the sign, before the digits. ~X uppercases
            // the DIGITS only (the prefix is verbatim). Oracle: ~.16x 255 "0x"
            // → "0xff"; ~.16X 255 "0x" → "0xFF"; ~.10x -31 "0x" → "-0x31".
            const arg = try popArg(m, args);
            var pbuf: std.ArrayList(u8) = .empty;
            defer pbuf.deinit(m.ctx.gpa);
            try appendStringArg(m, &pbuf, try popArg(m, args), false); // ~x prefix: latin1
            const base: i64 = if (s.precision) |p| p else 10;
            if (FinalTerms.repIsBig(&m.ctx, arg)) // DIVERGENCE 703
                try writeBaseFullBig(m, &buf, arg, base, pbuf.items, s.ctrl == 'X')
            else
                try writeBaseFull(m, &buf, try readInt(arg), base, pbuf.items, s.ctrl == 'X');
        },
        '+' => {
            // ~+: like ~b but the prefix is the base in `<base>#` notation
            // (lowercase digits). Oracle: ~.16+ -31 → "-16#1f"; ~+ 255 → "10#255".
            const arg = try popArg(m, args);
            const base: i64 = if (s.precision) |p| p else 10;
            var pbuf: std.ArrayList(u8) = .empty;
            defer pbuf.deinit(m.ctx.gpa);
            try pbuf.print(m.ctx.gpa, "{d}#", .{base});
            if (FinalTerms.repIsBig(&m.ctx, arg)) // DIVERGENCE 703
                try writeBaseFullBig(m, &buf, arg, base, pbuf.items, false)
            else
                try writeBaseFull(m, &buf, try readInt(arg), base, pbuf.items, false);
        },
        '#' => {
            // DIVERGENCE 710: ~# is ~+ (the `<base>#` prefix) with UPPERCASE
            // digits. Oracle: ~.16# -31 → "-16#1F" (vs ~+'s "-16#1f"); ~# 255 →
            // "10#255"; ~.8# 64 → "8#100". Was a clean badarg (no emit arm).
            const arg = try popArg(m, args);
            const base: i64 = if (s.precision) |p| p else 10;
            var pbuf: std.ArrayList(u8) = .empty;
            defer pbuf.deinit(m.ctx.gpa);
            try pbuf.print(m.ctx.gpa, "{d}#", .{base});
            if (FinalTerms.repIsBig(&m.ctx, arg))
                try writeBaseFullBig(m, &buf, arg, base, pbuf.items, true)
            else
                try writeBaseFull(m, &buf, try readInt(arg), base, pbuf.items, true);
        },
        'w' => try writeTerm(m, &buf, try popArg(m, args)),
        'W' => {
            // DIVERGENCE 696: ~W is ~w with a DEPTH limit — a FLAT (never-wrapped)
            // write truncated at the popped second depth arg (like ~P is to ~p).
            // `measure(t, depth)` builds the depth-truncated node (depth<0 =
            // unlimited, a container at depth 1 collapses to "[...]"/"{...}"), then
            // `writeFlat` renders it flat; goes through `buf` so a field width/pad
            // still applies (unlike ~p/~P which bypass buf). Missing/non-int depth
            // → badarg (mirrors ~P).
            const t = try popArg(m, args);
            const depth = try readInt(try popArg(m, args));
            if (depth == 0) {
                try buf.appendSlice(m.ctx.gpa, "..."); // depth 0 = the whole term is elided (mirrors ~P/writeTermPretty)
            } else {
                var arena = std.heap.ArenaAllocator.init(m.ctx.gpa);
                defer arena.deinit();
                const node = try measure(m, arena.allocator(), t, depth);
                try writeFlat(m, &buf, node);
            }
        },
        'p', 'P' => {
            // gap-io-format-pwrap: ~p/~P bypass buf+applyField ENTIRELY — F is
            // the LINE LENGTH (not a pad width), P is the START COLUMN (default
            // = current output column + 1), and the wrap depends on what is
            // already on the line. `~-Fp` has no io_lib clause → badarg. `~P`
            // pops a SECOND depth argument (0 → "...", <0 → unlimited) — the
            // old alias that skipped it was a live arg-misalignment divergence.
            const t = try popArg(m, args);
            const depth: i64 = if (s.ctrl == 'P') try readInt(try popArg(m, args)) else -1;
            if (s.adjust == .left) return error.Badarg;
            const ll: usize = if (s.width) |wd| @intCast(@max(wd, 0)) else 80;
            const col: usize = if (s.precision) |pr| @intCast(@max(pr, 1)) else currentColumn(out) + 1;
            return writeTermPretty(m, out, t, depth, ll, col);
        },
        'e', 'f', 'g' => {
            // gap-io-format-float: floats ONLY (an integer/bignum/atom is badarg
            // — probed); default precision 6 for all three; floors differ per
            // directive (validated in the writers: ~e ≥2, ~f/~g ≥1).
            const t = try popArg(m, args);
            if (!FinalTerms.repIsFloat(&m.ctx, t)) return error.Badarg;
            const fv = FinalTerms.floatValOf(&m.ctx, t);
            const p: i64 = s.precision orelse 6;
            switch (s.ctrl) {
                'e' => try writeFloatE(m, &buf, fv, p),
                'f' => try writeFloatF(m, &buf, fv, p),
                else => try writeFloatG(m, &buf, fv, p),
            }
        },
        else => return error.Badarg, // unknown control seq → badarg
    }
    // DIVERGENCE 705: ~w with a precision P — if the term prints WIDER than P
    // chars, the value is REPLACED by P asterisks (OTP io_lib control_small
    // overflow), then the field width is applied normally. (~p's precision is the
    // start COLUMN, not a char cap, so it is unaffected; ~s precision TRUNCATES,
    // handled in its own arm; exactly-P fits — the guard is strict `>`.)
    if (s.ctrl == 'w') {
        if (s.precision) |p| {
            const plim: usize = @intCast(@max(p, 0));
            if (buf.items.len > plim) {
                buf.clearRetainingCapacity();
                var k: usize = 0;
                while (k < plim) : (k += 1) try buf.append(m.ctx.gpa, '*');
            }
        }
    }
    // DIVERGENCE 711: a NUMERIC control whose rendering is WIDER than the field
    // width overflows to a field of `*` (erts io_lib control_small/control_int
    // overflow) — the based-int (`b/B/x/X/+/#`) and raw-term (`w/W`) controls,
    // alongside the already-starred floats (`e/f/g`). `~p`/`~P` KEEP (pretty-print
    // ignores width overflow); `~s`/`~ts` TRUNCATE to the field (handled in their
    // own path), so neither joins the stars set.
    const ov: Overflow = switch (s.ctrl) {
        'e', 'f', 'g', 'b', 'B', 'w', 'W', 'x', 'X', '+', '#' => .stars,
        else => .keep,
    };
    try applyField(m, out, buf.items, s, ov);
}

fn bytesToCharlist(m: *Machine, bytes: []const u8) BifError!Term {
    var lst = FinalTerms.nil(&m.ctx);
    var i = bytes.len;
    while (i > 0) {
        i -= 1;
        lst = FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, bytes[i]), lst) catch return error.OutOfMemory;
    }
    return lst;
}

// ── DIVERGENCE 715: io_lib:write_atom/1, write_string/1, write_char/1 ──
// The three char-list-returning writers erts exposes for building quoted term
// text. They reuse the ~w escaping already proven here: write_atom = the quoted
// atom form (`writeAtomName`); write_string = the quoted+escaped string
// (`writeString`); write_char = `$` + the erts char escaping.

/// `io_lib:write_atom(A)` → the atom's printed form (quoted iff needed) as a
/// char-list. Non-atom → badarg.
pub fn io_lib_write_atom_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(m.ctx.gpa);
    try writeAtomName(m, &out, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0])));
    return bytesToCharlist(m, out.items);
}

/// `io_lib:write_string(S)` → the quoted, escaped string form (`"…"`) as a
/// char-list. `S` must be a proper list of chars (else badarg).
pub fn io_lib_write_string_1(m: *Machine, args: []const Term) BifError!Term {
    // validate a proper char list first (writeString assumes small-int elems).
    var cur = args[0];
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        if (!FinalTerms.repIsSmall(h)) return error.Badarg;
        const c = FinalTerms.smallValOf(h);
        if (c < 0 or c > 0x10FFFF) return error.Badarg;
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg; // improper / non-list
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(m.ctx.gpa);
    try writeString(m, &out, args[0]);
    return bytesToCharlist(m, out.items);
}

/// erts' `$`-char escaping for `write_char`: named escapes for the control set
/// (`\b\t\n\v\f\r\e`), `\s` for space, `\\`, `\d` for DEL, octal `\OOO` for the
/// other C0/C1 control bytes, literal otherwise.
fn writeCharEsc(out: *std.ArrayList(u8), gpa: std.mem.Allocator, c: u8) BifError!void {
    switch (c) {
        8 => try out.appendSlice(gpa, "\\b"),
        9 => try out.appendSlice(gpa, "\\t"),
        10 => try out.appendSlice(gpa, "\\n"),
        11 => try out.appendSlice(gpa, "\\v"),
        12 => try out.appendSlice(gpa, "\\f"),
        13 => try out.appendSlice(gpa, "\\r"),
        27 => try out.appendSlice(gpa, "\\e"),
        32 => try out.appendSlice(gpa, "\\s"),
        92 => try out.appendSlice(gpa, "\\\\"),
        127 => try out.appendSlice(gpa, "\\d"),
        else => {
            if (c < 32 or (c >= 128 and c <= 159)) {
                try out.append(gpa, '\\'); // octal \OOO (3 digits)
                try out.append(gpa, '0' + (c >> 6));
                try out.append(gpa, '0' + ((c >> 3) & 0x7));
                try out.append(gpa, '0' + (c & 0x7));
            } else try out.append(gpa, c);
        },
    }
}

/// `io_lib:write_char(C)` → `$` + the escaped char, as a char-list. `C` must be
/// a valid char code (0..0x10FFFF); a codepoint > 255 is emitted literally as a
/// single list element (past the Latin-1 escape range).
pub fn io_lib_write_char_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsSmall(args[0])) return error.Badarg;
    const c = FinalTerms.smallValOf(args[0]);
    if (c < 0 or c > 0x10FFFF) return error.Badarg;
    if (c > 255) // a non-Latin-1 codepoint: `[$, C]` literal (no escaping)
        return FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, '$'), FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, c), FinalTerms.nil(&m.ctx)) catch return error.OutOfMemory) catch error.OutOfMemory;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(m.ctx.gpa);
    try out.append(m.ctx.gpa, '$');
    try writeCharEsc(&out, m.ctx.gpa, @intCast(c));
    return bytesToCharlist(m, out.items);
}

/// The pure `io_lib:format/2` path: format `fmt` with `args_in`, return a charlist.
pub fn format(m: *Machine, fmt: []const u8, args_in: Term) BifError!Term {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(m.ctx.gpa);
    var args = args_in;
    var i: usize = 0;
    while (i < fmt.len) {
        const c = fmt[i];
        if (c != '~') {
            try out.append(m.ctx.gpa, c);
            i += 1;
            continue;
        }
        i += 1;
        const s = try scanSpec(m, fmt, &i, &args);
        try emit(m, &out, s, &args);
    }
    return bytesToCharlist(m, out.items);
}

/// Flatten the format-STRING argument (a charlist/atom) then interpret it — the
/// entry the io/io_lib wrappers call. A binary format string is a named deferral.
pub fn formatTerm(m: *Machine, fmt_term: Term, args: Term) BifError!Term {
    var fbuf: std.ArrayList(u8) = .empty;
    defer fbuf.deinit(m.ctx.gpa);
    try appendStringArg(m, &fbuf, fmt_term, false); // format string: latin1
    return format(m, fbuf.items, args);
}

const AtomTable = ta.AtomTable;

test "LAW gap-io-format: byte-EQ per directive vs the pinned OTP-30 io_lib:format oracle" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // build helpers over the machine heap.
    const H = struct {
        m: *Machine,
        fn int(self: @This(), v: i64) Term {
            return FinalTerms.int(&self.m.ctx, v);
        }
        fn atom(self: @This(), name: []const u8) !Term {
            return FinalTerms.atom(&self.m.ctx, try self.m.ctx.atoms.intern(name));
        }
        fn list(self: @This(), items: []const Term) Term {
            var l = FinalTerms.nil(&self.m.ctx);
            var i = items.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(&self.m.ctx, items[i], l) catch unreachable;
            }
            return l;
        }
        fn ints(self: @This(), vs: []const i64) Term {
            var l = FinalTerms.nil(&self.m.ctx);
            var i = vs.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(&self.m.ctx, FinalTerms.int(&self.m.ctx, vs[i]), l) catch unreachable;
            }
            return l;
        }
        fn tup(self: @This(), items: []const Term) Term {
            return FinalTerms.tuple(&self.m.ctx, items) catch unreachable;
        }
        fn map(self: @This(), keys: []const Term, vals: []const Term) Term {
            return FinalTerms.mapNew(&self.m.ctx, keys, vals) catch unreachable;
        }
    };
    const h = H{ .m = &m };

    const check = struct {
        fn go(mm: *Machine, fmt: []const u8, args: Term, want: []const u8) !void {
            const r = try format(mm, fmt, args);
            // flatten the returned charlist to bytes.
            var got: std.ArrayList(u8) = .empty;
            defer got.deinit(std.testing.allocator);
            var cur = r;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                try got.append(std.testing.allocator, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&mm.ctx, cur))));
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            try std.testing.expectEqualStrings(want, got.items);
        }
    }.go;

    // every `want` is the EXACT byte string the pinned OTP-30 oracle returned.
    try check(&m, "~~", h.list(&.{}), "~");
    try check(&m, "~n", h.list(&.{}), "\n");
    try check(&m, "hi ~s!", h.list(&.{h.list(&.{ h.int('b'), h.int('o'), h.int('b') })}), "hi bob!");
    try check(&m, "~s", h.list(&.{try h.atom("ok")}), "ok");
    try check(&m, "~c", h.list(&.{h.int(65)}), "A");
    try check(&m, "~3c", h.list(&.{h.int(120)}), "xxx");
    try check(&m, "~b", h.list(&.{h.int(255)}), "255");
    try check(&m, "~.16b", h.list(&.{h.int(255)}), "ff");
    try check(&m, "~.2b", h.list(&.{h.int(5)}), "101");
    try check(&m, "~b", h.list(&.{h.int(-42)}), "-42");
    try check(&m, "~5..0b", h.list(&.{h.int(42)}), "00042");
    try check(&m, "~w", h.list(&.{h.tup(&.{ try h.atom("a"), h.int(1) })}), "{a,1}");
    try check(&m, "~w", h.list(&.{h.ints(&.{ 97, 98 })}), "[97,98]");
    try check(&m, "~w", h.list(&.{try h.atom("foo")}), "foo");
    try check(&m, "~w", h.list(&.{h.ints(&.{ 1, 2, 3 })}), "[1,2,3]");
    // too-few-args → badarg (OTP raises on argument exhaustion).
    try std.testing.expectError(error.Badarg, format(&m, "~s", h.list(&.{})));

    // ~p: the printable-string heuristic (recursive) + escaping — every `want` is
    // the EXACT pinned OTP-30 oracle byte string.
    try check(&m, "~p", h.list(&.{h.tup(&.{ try h.atom("a"), h.int(1) })}), "{a,1}");
    try check(&m, "~p", h.list(&.{try h.atom("foo")}), "foo");
    try check(&m, "~p", h.list(&.{h.ints(&.{ 97, 98, 99 })}), "\"abc\""); // printable → string
    try check(&m, "~p", h.list(&.{h.ints(&.{ 1, 2, 3 })}), "[1,2,3]"); // control chars → [...]
    try check(&m, "~p", h.list(&.{h.ints(&.{ 104, 105, 0 })}), "[104,105,0]"); // NUL → [...]
    try check(&m, "~p", h.list(&.{FinalTerms.nil(&m.ctx)}), "[]"); // empty is NOT a string
    try check(&m, "~p", h.list(&.{h.tup(&.{ try h.atom("ok"), h.ints(&.{ 104, 105 }) })}), "{ok,\"hi\"}"); // recursive
    try check(&m, "~p", h.list(&.{h.list(&.{ try h.atom("a"), try h.atom("b") })}), "[a,b]"); // atoms → [...]
    try check(&m, "~p", h.list(&.{h.ints(&.{9})}), "\"\\t\""); // tab escaped
    try check(&m, "~p", h.list(&.{h.ints(&.{ 97, 34, 98 })}), "\"a\\\"b\""); // quote escaped
    try check(&m, "~p", h.list(&.{h.ints(&.{ 97, 92, 98 })}), "\"a\\\\b\""); // backslash escaped
    try check(&m, "~p", h.list(&.{h.ints(&.{255})}), "\"\xff\""); // latin1 high → verbatim byte

    // ── gap-io-format-complete: ~x/~X/~+ prefixed integers + ~B uppercase —
    // every `want` is the EXACT pinned OTP-30 io_lib:format oracle byte string. ──
    try check(&m, "~.16x", h.list(&.{ h.int(255), h.list(&.{ h.int('0'), h.int('x') }) }), "0xff");
    try check(&m, "~.16X", h.list(&.{ h.int(255), h.list(&.{ h.int('0'), h.int('x') }) }), "0xFF");
    try check(&m, "~.10x", h.list(&.{ h.int(-31), h.list(&.{ h.int('0'), h.int('x') }) }), "-0x31");
    try check(&m, "~.16x", h.list(&.{ h.int(255), h.list(&.{ h.int('0'), h.int('x') }) }), "0xff");
    try check(&m, "~.16x", h.list(&.{ h.int(-255), h.list(&.{ h.int('0'), h.int('x') }) }), "-0xff");
    try check(&m, "~x", h.list(&.{ h.int(255), h.list(&.{h.int('#')}) }), "#255"); // default base 10
    try check(&m, "~x", h.list(&.{ h.int(-31), try h.atom("foo") }), "-foo31"); // atom prefix
    try check(&m, "~.16B", h.list(&.{h.int(31)}), "1F"); // ~B uppercases (was a lowercase bug)
    try check(&m, "~.16b", h.list(&.{h.int(31)}), "1f");
    try check(&m, "~B", h.list(&.{h.int(255)}), "255");
    try check(&m, "~.10+", h.list(&.{h.int(31)}), "10#31");
    try check(&m, "~.16+", h.list(&.{h.int(-31)}), "-16#1f"); // sign, then base#, then lowercase
    try check(&m, "~.2+", h.list(&.{h.int(5)}), "2#101");
    try check(&m, "~+", h.list(&.{h.int(255)}), "10#255");
    try check(&m, "~.2+", h.list(&.{h.int(-5)}), "-2#101");
    // DIVERGENCE 703: ~b/~B/~x/~+ of a BIGNUM (2^80, limbs {0, 1<<16}) — was badarg.
    const big80 = try FinalTerms.intFromLimbs(&m.ctx, true, &.{ 0, @as(u64, 1) << 16 });
    const px = h.list(&.{ h.int('0'), h.int('x') }); // "0x" prefix
    try check(&m, "~b", h.list(&.{big80}), "1208925819614629174706176"); // base 10 decimal
    try check(&m, "~.16B", h.list(&.{big80}), "100000000000000000000"); // uppercase hex
    try check(&m, "~.16x", h.list(&.{ big80, px }), "0x100000000000000000000"); // prefix after (no) sign
    try check(&m, "~.16+", h.list(&.{big80}), "16#100000000000000000000"); // base# prefix
    const nbig80 = try FinalTerms.intFromLimbs(&m.ctx, false, &.{ 0, @as(u64, 1) << 16 });
    try check(&m, "~.16x", h.list(&.{ nbig80, px }), "-0x100000000000000000000"); // '-' BEFORE the prefix
    // DIVERGENCE 705: ~w precision-overflow → the value becomes P asterisks, then field-padded.
    try check(&m, "~6.3w", h.list(&.{h.int(123456)}), "   ***"); // 6 chars > P=3 → "***" in field 6
    try check(&m, "~.3w", h.list(&.{h.int(123456)}), "***"); // no field width → just "***"
    try check(&m, "~6.3w", h.list(&.{h.int(123)}), "   123"); // exactly P=3 → fits (strict >), no stars
    try check(&m, "~6.3w", h.list(&.{h.int(12)}), "    12"); // < P → fits
    try check(&m, "~.4w", h.list(&.{h.tup(&.{ try h.atom("a"), try h.atom("b"), try h.atom("c") })}), "****"); // "{a,b,c}"=7 > 4
    try check(&m, "~6.3p", h.list(&.{h.int(123456)}), "123456"); // ~p precision is the COLUMN — NOT starred
    // an unknown control seq → badarg; ~x with too few args → badarg.
    try std.testing.expectError(error.Badarg, format(&m, "~q", h.list(&.{h.int(1)})));
    try std.testing.expectError(error.Badarg, format(&m, "~x", h.list(&.{h.int(255)})));

    // ── gap-io-format-complete: maps in ~w/~p (canonical exact-term order;
    // byte-EQ on the reproducible subset). Every `want` is the EXACT pinned
    // OTP-30 oracle byte string (order coincides with term order here). ──
    try check(&m, "~w", h.list(&.{h.map(&.{}, &.{})}), "#{}");
    try check(&m, "~w", h.list(&.{h.map(&.{try h.atom("a")}, &.{h.int(1)})}), "#{a => 1}");
    try check(&m, "~w", h.list(&.{h.map(&.{ h.int(1), h.int(2), h.int(3) }, &.{ try h.atom("one"), try h.atom("two"), try h.atom("three") })}), "#{1 => one,2 => two,3 => three}");
    try check(&m, "~w", h.list(&.{h.map(&.{h.int(1)}, &.{try h.atom("a")})}), "#{1 => a}");
    try check(&m, "~w", h.list(&.{h.map(&.{try h.atom("k")}, &.{try h.atom("v")})}), "#{k => v}");
    // nested map value (single atom key each level)
    try check(&m, "~w", h.list(&.{h.map(&.{try h.atom("a")}, &.{h.map(&.{try h.atom("b")}, &.{h.int(2)})})}), "#{a => #{b => 2}}");
    // type-distinguished keys: integer < float < list (all sort universally)
    try check(&m, "~w", h.list(&.{h.map(&.{ h.int(1), FinalTerms.float(&m.ctx, 3.0), h.ints(&.{115}) }, &.{ try h.atom("x"), try h.atom("f"), h.int(2) })}), "#{1 => x,3.0 => f,[115] => 2}");
    try check(&m, "~w", h.list(&.{h.map(&.{ h.int(1), FinalTerms.float(&m.ctx, 2.0) }, &.{ try h.atom("a"), try h.atom("b") })}), "#{1 => a,2.0 => b}");
    try check(&m, "~w", h.list(&.{h.map(&.{h.ints(&.{ 1, 2 })}, &.{try h.atom("x")})}), "#{[1,2] => x}");
    // ~p applies the string heuristic to values; empty/single are byte-EQ
    try check(&m, "~p", h.list(&.{h.map(&.{try h.atom("a")}, &.{h.int(1)})}), "#{a => 1}");
    try check(&m, "~p", h.list(&.{h.map(&.{h.int(1)}, &.{h.ints(&.{ 104, 105 })})}), "#{1 => \"hi\"}");
    try check(&m, "~p", h.list(&.{h.map(&.{try h.atom("sym")}, &.{h.ints(&.{ 104, 105, 0 })})}), "#{sym => [104,105,0]}");
    // ~P depth: a map collapses at depth 1; a nested map collapses one in
    try check(&m, "~P", h.list(&.{ h.map(&.{try h.atom("a")}, &.{h.int(1)}), h.int(1) }), "#{...}");
    try check(&m, "~P", h.list(&.{ h.map(&.{try h.atom("a")}, &.{h.map(&.{try h.atom("b")}, &.{h.int(2)})}), h.int(2) }), "#{a => #{...}}");
    // ~s of a map is badarg (probed: io_lib crashes with badarg)
    try std.testing.expectError(error.Badarg, format(&m, "~s", h.list(&.{h.map(&.{try h.atom("a")}, &.{h.int(1)})})));

    // ── gap-io-format-float: ~e/~f/~g/~w of floats — every `want` is the EXACT
    // pinned OTP-30 oracle byte string (design probe table, captured live). ──
    const F = struct {
        m: *Machine,
        fn f(self: @This(), v: f64) Term {
            return FinalTerms.float(&self.m.ctx, v);
        }
    };
    const hf = F{ .m = &m };

    // ~e (P = total significant digits, default 6; exponent e±d unpadded)
    try check(&m, "~e", h.list(&.{hf.f(3.14)}), "3.14000e+0");
    try check(&m, "~e", h.list(&.{hf.f(-0.0)}), "-0.00000e+0");
    try check(&m, "~e", h.list(&.{hf.f(100.0)}), "1.00000e+2");
    try check(&m, "~e", h.list(&.{hf.f(1.0e-300)}), "1.00000e-300");
    try check(&m, "~e", h.list(&.{hf.f(9.999999)}), "1.00000e+1"); // carry bumps exponent
    try check(&m, "~.3e", h.list(&.{hf.f(3.14159)}), "3.14e+0");
    try check(&m, "~.2e", h.list(&.{hf.f(9.99)}), "1.0e+1");
    try check(&m, "~.21e", h.list(&.{hf.f(3.14)}), "3.14000000000000012434e+0"); // the exact 21 base digits
    try check(&m, "~.30e", h.list(&.{hf.f(3.14)}), "3.14000000000000012434000000000e+0"); // zero-padded past 21
    try check(&m, "~15..0e", h.list(&.{hf.f(3.14)}), "000003.14000e+0");
    try check(&m, "~5e", h.list(&.{hf.f(3.14)}), "*****"); // field overflow = width×'*'

    // ~f (P = decimal places, default 6; two-stage rounding is load-bearing)
    try check(&m, "~f", h.list(&.{hf.f(3.14)}), "3.140000");
    try check(&m, "~f", h.list(&.{hf.f(-0.0)}), "-0.000000");
    try check(&m, "~.1f", h.list(&.{hf.f(0.25)}), "0.3"); // HALF-UP on the 21-digit string
    try check(&m, "~.1f", h.list(&.{hf.f(0.35)}), "0.3"); // base 0.34999… rounds down
    try check(&m, "~.2f", h.list(&.{hf.f(2.675)}), "2.67"); // base 2.674999… — NOT float half-up
    try check(&m, "~.1f", h.list(&.{hf.f(9.99)}), "10.0"); // carry into a new integer digit
    try check(&m, "~.1f", h.list(&.{hf.f(-0.04)}), "-0.0"); // negative zero RESULT survives
    try check(&m, "~.2f", h.list(&.{hf.f(0.001)}), "0.00");
    try check(&m, "~.17f", h.list(&.{hf.f(0.1)}), "0.10000000000000001");
    try check(&m, "~.25f", h.list(&.{hf.f(3.14)}), "3.1400000000000001243400000");
    try check(&m, "~f", h.list(&.{hf.f(1.0e10)}), "10000000000.000000");
    try check(&m, "~10.2.0f", h.list(&.{hf.f(3.14159)}), "0000003.14");
    try check(&m, "~-10.2f", h.list(&.{hf.f(3.14159)}), "3.14      ");

    // ~g (fixed only for 0.1 ≤ |x| < 10^4; 0.0 is e-form)
    try check(&m, "~g", h.list(&.{hf.f(3.14)}), "3.14000");
    try check(&m, "~g", h.list(&.{hf.f(0.0)}), "0.00000e+0");
    try check(&m, "~g", h.list(&.{hf.f(0.1)}), "0.100000");
    try check(&m, "~g", h.list(&.{hf.f(0.0999)}), "9.99000e-2");
    try check(&m, "~g", h.list(&.{hf.f(9999.99)}), "9999.99");
    try check(&m, "~g", h.list(&.{hf.f(10000.0)}), "1.00000e+4"); // the boundary is e-form
    try check(&m, "~g", h.list(&.{hf.f(99999.99)}), "1.00000e+5"); // rounding crosses up inside e-form
    try check(&m, "~.1g", h.list(&.{hf.f(0.5)}), "0.5"); // P=1, E=-1 stays fixed
    try check(&m, "~.1g", h.list(&.{hf.f(3.14)}), "3.1e+0"); // P=1 e-form forced to 2 sig digits
    try check(&m, "~.2g", h.list(&.{hf.f(99.0)}), "9.9e+1"); // NOT "99": P-1 > E fails ⇒ e-form
    try check(&m, "~.2g", h.list(&.{hf.f(0.1)}), "0.10");

    // ~w/~p of floats (shortest round-trip, Erlang literal layout)
    try check(&m, "~w", h.list(&.{hf.f(3.14)}), "3.14");
    try check(&m, "~w", h.list(&.{hf.f(1.0)}), "1.0");
    try check(&m, "~w", h.list(&.{hf.f(-0.0)}), "-0.0");
    try check(&m, "~w", h.list(&.{hf.f(1000.0)}), "1.0e3"); // sci beats "1000.0"
    try check(&m, "~w", h.list(&.{hf.f(2048.0)}), "2048.0");
    try check(&m, "~w", h.list(&.{hf.f(1250.0)}), "1250.0"); // tie → fixed
    try check(&m, "~w", h.list(&.{hf.f(0.0001)}), "0.0001");
    try check(&m, "~w", h.list(&.{hf.f(1.0e-5)}), "1.0e-5");
    try check(&m, "~w", h.list(&.{hf.f(0.00012345)}), "1.2345e-4");
    try check(&m, "~w", h.list(&.{hf.f(9007199254740991.0)}), "9007199254740991.0"); // 2^53−1 fixed
    try check(&m, "~w", h.list(&.{hf.f(9007199254740992.0)}), "9.007199254740992e15"); // 2^53 sci
    try check(&m, "~w", h.list(&.{hf.f(9999999999999998.0)}), "9.999999999999998e15"); // sci though fixed shorter
    try check(&m, "~w", h.list(&.{hf.f(0.30000000000000004)}), "0.30000000000000004");
    try check(&m, "~w", h.list(&.{hf.f(5.0e-324)}), "5.0e-324"); // subnormal min
    try check(&m, "~w", h.list(&.{hf.f(1.0e300)}), "1.0e300");
    try check(&m, "~p", h.list(&.{hf.f(3.14)}), "3.14");
    try check(&m, "~p", h.list(&.{h.tup(&.{ try h.atom("a"), hf.f(3.14) })}), "{a,3.14}");

    // badarg rejection: precision floors + non-float args (all probed).
    try std.testing.expectError(error.Badarg, format(&m, "~.1e", h.list(&.{hf.f(3.14159)}))); // ~e needs P≥2
    try std.testing.expectError(error.Badarg, format(&m, "~.0f", h.list(&.{hf.f(0.5)}))); // ~f needs P≥1
    try std.testing.expectError(error.Badarg, format(&m, "~f", h.list(&.{h.int(3)}))); // integer is badarg
    try std.testing.expectError(error.Badarg, format(&m, "~e", h.list(&.{h.int(3)})));
    try std.testing.expectError(error.Badarg, format(&m, "~g", h.list(&.{h.int(3)})));
    try std.testing.expectError(error.Badarg, format(&m, "~f", h.list(&.{try h.atom("x")})));
}

test "LAW gap-io-format-sprec (DIVERGENCE 709): ~s/~ts precision truncates the string to N chars (then width pads); byte-EQ OTP-30" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const H = struct {
        m: *Machine,
        fn str(self: @This(), bytes: []const u8) Term {
            var l = FinalTerms.nil(&self.m.ctx);
            var i = bytes.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(&self.m.ctx, FinalTerms.int(&self.m.ctx, bytes[i]), l) catch unreachable;
            }
            return l;
        }
        fn arg1(self: @This(), t: Term) Term {
            return FinalTerms.cons(&self.m.ctx, t, FinalTerms.nil(&self.m.ctx)) catch unreachable;
        }
    };
    const h = H{ .m = &m };

    const check = struct {
        fn go(mm: *Machine, fmt: []const u8, arg: Term, want: []const u8) !void {
            const r = try format(mm, fmt, arg);
            var got: std.ArrayList(u8) = .empty;
            defer got.deinit(std.testing.allocator);
            var cur = r;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                try got.append(std.testing.allocator, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&mm.ctx, cur))));
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            try std.testing.expectEqualStrings(want, got.items);
        }
    };

    // precision truncates to N chars (byte-EQ OTP-30, all latin1).
    try check.go(&m, "~.3s", h.arg1(h.str("abcdef")), "abc");
    try check.go(&m, "~.2s", h.arg1(h.str("abcdef")), "ab");
    // precision is a MAX, not a min — a shorter string is untouched (no pad).
    try check.go(&m, "~.3s", h.arg1(h.str("ab")), "ab");
    // width + precision: truncate to precision FIRST, then pad to width (right).
    try check.go(&m, "~5.3s", h.arg1(h.str("abcdef")), "  abc");
    // left-justify (~-W): truncate then left-pad-right.
    try check.go(&m, "~-5.3s", h.arg1(h.str("abcdef")), "abc  ");
    // width alone still pads (unchanged regression).
    try check.go(&m, "~5s", h.arg1(h.str("ab")), "   ab");
    // ~ts precision counts codepoints — ASCII is byte-EQ to ~s.
    try check.go(&m, "~.3ts", h.arg1(h.str("abcdef")), "abc");
}

test "LAW gap-term-print-totality (DIVERGENCE 728): ~w/~p total over pid/ref/port/fun; byte-EQ shape (was the badarg crash-amplifier)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const T = FinalTerms;

    const fmt1 = struct {
        fn go(mm: *Machine, ctrl: []const u8, term: Term, want: []const u8) !void {
            const args = T.cons(&mm.ctx, term, T.nil(&mm.ctx)) catch unreachable;
            const r = try format(mm, ctrl, args);
            var got: std.ArrayList(u8) = .empty;
            defer got.deinit(std.testing.allocator);
            var cur = r;
            while (T.kindOf(&mm.ctx, cur) == .cons) {
                got.append(std.testing.allocator, @intCast(T.smallValOf(T.listHead(&mm.ctx, cur)))) catch unreachable;
                cur = T.listTail(&mm.ctx, cur);
            }
            try std.testing.expectEqualStrings(want, got.items);
        }
    }.go;

    // SHAPE byte-EQ over constructed terms (the numbers are ours in-process) — ~w:
    try fmt1(&m, "~w", try T.pid(&m.ctx, 5, 6), "<0.5.6>");
    try fmt1(&m, "~w", try T.ref(&m.ctx, .{ 1, 2, 3 }), "#Ref<0.1.2.3>");
    try fmt1(&m, "~w", try T.port(&m.ctx, 9), "#Port<0.9>");
    try fmt1(&m, "~w", try T.makeExportFun(&m.ctx, T.atom(&m.ctx, try atoms.intern("m")), T.atom(&m.ctx, try atoms.intern("f")), 2), "fun m:f/2");
    try fmt1(&m, "~w", try T.makeFun(&m.ctx, 42, 1, &.{}), "#Fun<42.1>"); // local closure, NO fun_meta → the label.arity fallback (the WITH-meta #Fun<M.I.U> shape is LAW gap-fun-print-shape / 740)
    // ~p delegates to writeTerm for these kinds → identical shapes:
    try fmt1(&m, "~p", try T.pid(&m.ctx, 7, 8), "<0.7.8>");
    // TOTALITY (the crash-amplifier fix): a TUPLE containing a pid + ref FORMATS
    // instead of `error.Badarg` killing the printing process.
    const pr = try T.tuple(&m.ctx, &.{ try T.pid(&m.ctx, 1, 0), try T.ref(&m.ctx, .{ 4, 5, 6 }) });
    try fmt1(&m, "~w", pr, "{<0.1.0>,#Ref<0.4.5.6>}");
}

test "LAW gap-fun-print-shape (DIVERGENCE 740): a LOCAL closure WITH fun_meta prints #Fun<Module.Index.OldUniq> byte-EQ (erts erts_print_fun); no meta → the #Fun<Label.Arity> fallback" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const T = FinalTerms;
    const fmt1 = struct {
        fn go(mm: *Machine, ctrl: []const u8, term: Term, want: []const u8) !void {
            const args = T.cons(&mm.ctx, term, T.nil(&mm.ctx)) catch unreachable;
            const r = try format(mm, ctrl, args);
            var got: std.ArrayList(u8) = .empty;
            defer got.deinit(std.testing.allocator);
            var cur = r;
            while (T.kindOf(&mm.ctx, cur) == .cons) {
                got.append(std.testing.allocator, @intCast(T.smallValOf(T.listHead(&mm.ctx, cur)))) catch unreachable;
                cur = T.listTail(&mm.ctx, cur);
            }
            try std.testing.expectEqualStrings(want, got.items);
        }
    }.go;

    // Simulate make_fun3's fun_meta population for label 7: {module, name, index=3,
    // old_uniq=99887766} — exactly what the loader threads from the FunT record.
    const mod = try atoms.intern("zmod");
    const nm = try atoms.intern("-t/1-fun-0-");
    try m.fun_meta.put(gpa, 7, .{ @intCast(mod), @intCast(nm), 3, 99887766 });
    const f = try T.makeFun(&m.ctx, 7, 1, &.{});
    // ~w and ~p both render the OTP #Fun<Module.Index.OldUniq> shape (module NAME, not idx).
    try fmt1(&m, "~w", f, "#Fun<zmod.3.99887766>");
    try fmt1(&m, "~p", f, "#Fun<zmod.3.99887766>");
    // a fun WITHOUT meta (synthetic/fuzzer) keeps the #Fun<Label.Arity> fallback.
    try fmt1(&m, "~w", try T.makeFun(&m.ctx, 55, 2, &.{}), "#Fun<55.2>");
}

test "LAW gap-io-format-atomquote (DIVERGENCE 714): ~w/~p quote+escape an atom that isn't a bare lowercase name; byte-EQ OTP-30" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const check = struct {
        fn go(mm: *Machine, ctrl: []const u8, name: []const u8, want: []const u8) !void {
            const a = FinalTerms.atom(&mm.ctx, try mm.ctx.atoms.intern(name));
            const args = FinalTerms.cons(&mm.ctx, a, FinalTerms.nil(&mm.ctx)) catch unreachable;
            const r = try format(mm, ctrl, args);
            var got: std.ArrayList(u8) = .empty;
            defer got.deinit(std.testing.allocator);
            var cur = r;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                try got.append(std.testing.allocator, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&mm.ctx, cur))));
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            try std.testing.expectEqualStrings(want, got.items);
        }
    };

    // bare lowercase names stay UNQUOTED (~w and ~p).
    try check.go(&m, "~w", "foo", "foo");
    try check.go(&m, "~w", "foo_bar@x", "foo_bar@x");
    try check.go(&m, "~p", "foo", "foo");
    // needs-quote: uppercase/underscore/digit start, embedded space/dot.
    try check.go(&m, "~w", "Foo", "'Foo'");
    try check.go(&m, "~w", "_x", "'_x'");
    try check.go(&m, "~w", "hello world", "'hello world'");
    try check.go(&m, "~w", "with.dot", "'with.dot'");
    try check.go(&m, "~p", "hello world", "'hello world'");
    // escaping inside the quotes: ' \ tab nl.
    try check.go(&m, "~w", "has'q", "'has\\'q'");
    try check.go(&m, "~w", "a\\b", "'a\\\\b'");
    try check.go(&m, "~w", "a\tb", "'a\\tb'");
    // the empty atom quotes.
    try check.go(&m, "~w", "", "''");
    // DIVERGENCE 717: codepoint-based quoting over the UTF-8-stored name.
    // A Latin-1 lowercase-letter atom stays UNQUOTED, and its codepoint prints
    // as a single byte (café: utf8 name "caf\xc3\xa9" → output "caf\xe9", é=233).
    try check.go(&m, "~w", "caf\xc3\xa9", "caf\xe9");
    try check.go(&m, "~w", "na\xc3\xafve", "na\xefve"); // naïve, ï=239 unquoted
    try check.go(&m, "~w", "\xc3\x9feta", "\xdfeta"); // ßeta, ß=223 lowercase → unquoted
    // Latin-1 UPPERCASE-led → quoted, byte literal inside (Ärger: Ä=196).
    try check.go(&m, "~w", "\xc3\x84rger", "'\xc4rger'");
    // non-Latin-1 codepoints → quoted with \x{HEX} (uppercase, no leading zeros).
    try check.go(&m, "~w", "\xce\x94elta", "'\\x{394}elta'"); // Δelta, Δ=U+0394
    try check.go(&m, "~w", "\xce\xb1\xce\xb2", "'\\x{3B1}\\x{3B2}'"); // αβ (Greek lowercase but >255 → quoted+escaped)
    try check.go(&m, "~w", "snow\xe2\x98\x83", "'snow\\x{2603}'"); // snow☃, ☃=U+2603
    // atom nested in a tuple/list still quotes.
    {
        const a = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("a b"));
        const tup = try FinalTerms.tuple(&m.ctx, &.{ a, FinalTerms.int(&m.ctx, 1) });
        const args = try FinalTerms.cons(&m.ctx, tup, FinalTerms.nil(&m.ctx));
        const r = try format(&m, "~w", args);
        var got: std.ArrayList(u8) = .empty;
        defer got.deinit(gpa);
        var cur = r;
        while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
            try got.append(gpa, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&m.ctx, cur))));
            cur = FinalTerms.listTail(&m.ctx, cur);
        }
        try std.testing.expectEqualStrings("{'a b',1}", got.items);
    }
}

test "LAW gap-io-lib-write (DIVERGENCE 715): io_lib:write_atom/1 + write_string/1 + write_char/1 byte-EQ OTP-30" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const flat = struct {
        fn go(mm: *Machine, t: Term) ![]u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(std.testing.allocator);
            var cur = t;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                try out.append(std.testing.allocator, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&mm.ctx, cur))));
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            return out.toOwnedSlice(std.testing.allocator);
        }
        fn str(mm: *Machine, bytes: []const u8) Term {
            var l = FinalTerms.nil(&mm.ctx);
            var i = bytes.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(&mm.ctx, FinalTerms.int(&mm.ctx, bytes[i]), l) catch unreachable;
            }
            return l;
        }
    };

    // write_atom: quoted iff needed.
    {
        const r = try io_lib_write_atom_1(&m, &.{FinalTerms.atom(&m.ctx, try atoms.intern("hello world"))});
        const s = try flat.go(&m, r);
        defer gpa.free(s);
        try std.testing.expectEqualStrings("'hello world'", s);
    }
    {
        const r = try io_lib_write_atom_1(&m, &.{FinalTerms.atom(&m.ctx, try atoms.intern("foo"))});
        const s = try flat.go(&m, r);
        defer gpa.free(s);
        try std.testing.expectEqualStrings("foo", s);
    }
    try std.testing.expectError(error.Badarg, io_lib_write_atom_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));

    // write_string: quoted + escaped.
    {
        const r = try io_lib_write_string_1(&m, &.{flat.str(&m, "a\tb\"c")});
        const s = try flat.go(&m, r);
        defer gpa.free(s);
        try std.testing.expectEqualStrings("\"a\\tb\\\"c\"", s);
    }
    try std.testing.expectError(error.Badarg, io_lib_write_string_1(&m, &.{FinalTerms.atom(&m.ctx, try atoms.intern("x"))}));

    // write_char: `$` + escape (named / \s / octal / \d / literal).
    const chars = [_]struct { c: i64, want: []const u8 }{
        .{ .c = 'A', .want = "$A" },
        .{ .c = '$', .want = "$$" },
        .{ .c = 10, .want = "$\\n" },
        .{ .c = 9, .want = "$\\t" },
        .{ .c = 32, .want = "$\\s" },
        .{ .c = 92, .want = "$\\\\" },
        .{ .c = 0, .want = "$\\000" },
        .{ .c = 7, .want = "$\\007" },
        .{ .c = 31, .want = "$\\037" },
        .{ .c = 127, .want = "$\\d" },
        .{ .c = 233, .want = "$\xe9" }, // é literal (Latin-1)
        .{ .c = 128, .want = "$\\200" }, // C1 control → octal
    };
    for (chars) |cc| {
        const r = try io_lib_write_char_1(&m, &.{FinalTerms.int(&m.ctx, cc.c)});
        const s = try flat.go(&m, r);
        defer gpa.free(s);
        try std.testing.expectEqualStrings(cc.want, s);
    }
    try std.testing.expectError(error.Badarg, io_lib_write_char_1(&m, &.{FinalTerms.int(&m.ctx, -1)}));
    try std.testing.expectError(error.Badarg, io_lib_write_char_1(&m, &.{FinalTerms.atom(&m.ctx, try atoms.intern("x"))}));
}

test "LAW gap-io-format-radixhash (DIVERGENCE 710): ~# is ~+ with UPPERCASE base#value digits; byte-EQ OTP-30" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const check = struct {
        fn go(mm: *Machine, fmt: []const u8, v: i64, want: []const u8) !void {
            const arg = FinalTerms.cons(&mm.ctx, FinalTerms.int(&mm.ctx, v), FinalTerms.nil(&mm.ctx)) catch unreachable;
            const r = try format(mm, fmt, arg);
            var got: std.ArrayList(u8) = .empty;
            defer got.deinit(std.testing.allocator);
            var cur = r;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                try got.append(std.testing.allocator, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&mm.ctx, cur))));
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            try std.testing.expectEqualStrings(want, got.items);
        }
    };

    // ~# : base#value with UPPERCASE digits (default base 10).
    try check.go(&m, "~#", 255, "10#255");
    try check.go(&m, "~#", 0, "10#0");
    try check.go(&m, "~.16#", 255, "16#FF"); // uppercase (vs ~+'s lowercase "ff")
    try check.go(&m, "~.16#", -31, "-16#1F"); // sign before the prefix
    try check.go(&m, "~.8#", 64, "8#100");
    try check.go(&m, "~.2#", 5, "2#101");
    // ~+ stays LOWERCASE — the discriminator this LAW pins vs ~#.
    try check.go(&m, "~.16+", -31, "-16#1f");
}

test "LAW gap-io-format-fieldstars (DIVERGENCE 711): a NUMERIC control wider than the field overflows to '*'; ~p/~P keep, byte-EQ OTP-30" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const H = struct {
        m: *Machine,
        fn str(self: @This(), bytes: []const u8) Term {
            var l = FinalTerms.nil(&self.m.ctx);
            var i = bytes.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(&self.m.ctx, FinalTerms.int(&self.m.ctx, bytes[i]), l) catch unreachable;
            }
            return l;
        }
    };
    const h = H{ .m = &m };

    const check = struct {
        fn go(mm: *Machine, fmt: []const u8, args: Term, want: []const u8) !void {
            const r = try format(mm, fmt, args);
            var got: std.ArrayList(u8) = .empty;
            defer got.deinit(std.testing.allocator);
            var cur = r;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                try got.append(std.testing.allocator, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&mm.ctx, cur))));
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            try std.testing.expectEqualStrings(want, got.items);
        }
        fn one(mm: *Machine, v: i64) Term {
            return FinalTerms.cons(&mm.ctx, FinalTerms.int(&mm.ctx, v), FinalTerms.nil(&mm.ctx)) catch unreachable;
        }
        fn two(mm: *Machine, a: i64, b: Term) Term {
            return FinalTerms.cons(&mm.ctx, FinalTerms.int(&mm.ctx, a), FinalTerms.cons(&mm.ctx, b, FinalTerms.nil(&mm.ctx)) catch unreachable) catch unreachable;
        }
    };

    // numeric controls overflow to a field of '*' (byte-EQ OTP-30).
    try check.go(&m, "~2b", check.one(&m, 555), "**"); // "555" > width 2
    try check.go(&m, "~2B", check.one(&m, 255), "**");
    try check.go(&m, "~3.16#", check.one(&m, 255), "***"); // "16#FF" (5) > width 3
    try check.go(&m, "~3.16+", check.one(&m, 255), "***");
    try check.go(&m, "~2w", check.one(&m, 12345), "**");
    try check.go(&m, "~3.16X", check.two(&m, 255, h.str("0x")), "***"); // "0xFF" (4) > width 3

    // ~W (depth) also stars on overflow; ~P (depth) KEEPS.
    try check.go(&m, "~3W", check.two(&m, 123456, FinalTerms.int(&m.ctx, 3)), "***");
    try check.go(&m, "~3P", check.two(&m, 123456, FinalTerms.int(&m.ctx, 3)), "123456");

    // ~p KEEPS (pretty-print ignores width overflow) — the discriminator.
    try check.go(&m, "~2p", check.one(&m, 12345), "12345");
    // a value that FITS the field is untouched (no spurious stars).
    try check.go(&m, "~4b", check.one(&m, 55), "  55");
}

test "LAW gap-io-format-swidth (DIVERGENCE 712): ~s/~ts field WIDTH is a max — truncates to exactly the field (not stars); precision>width is badarg; byte-EQ OTP-30" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const H = struct {
        m: *Machine,
        fn str(self: @This(), bytes: []const u8) Term {
            var l = FinalTerms.nil(&self.m.ctx);
            var i = bytes.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(&self.m.ctx, FinalTerms.int(&self.m.ctx, bytes[i]), l) catch unreachable;
            }
            return FinalTerms.cons(&self.m.ctx, l, FinalTerms.nil(&self.m.ctx)) catch unreachable; // one arg: [String]
        }
    };
    const h = H{ .m = &m };

    const check = struct {
        fn go(mm: *Machine, fmt: []const u8, args: Term, want: []const u8) !void {
            const r = try format(mm, fmt, args);
            var got: std.ArrayList(u8) = .empty;
            defer got.deinit(std.testing.allocator);
            var cur = r;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                try got.append(std.testing.allocator, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&mm.ctx, cur))));
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            try std.testing.expectEqualStrings(want, got.items);
        }
    };

    // width truncates a longer string to EXACTLY the field (no stars).
    try check.go(&m, "~2s", h.str("abcdef"), "ab");
    try check.go(&m, "~2s", h.str("ab"), "ab"); // exact
    try check.go(&m, "~3s", h.str("ab"), " ab"); // shorter → pad
    try check.go(&m, "~0s", h.str("abc"), ""); // width 0 → empty
    // width + precision compose: precision truncates first, then width pads.
    try check.go(&m, "~4.2s", h.str("abcdef"), "  ab");
    try check.go(&m, "~5.3s", h.str("abcdef"), "  abc");
    try check.go(&m, "~6.4s", h.str("abcdefgh"), "  abcd");
    try check.go(&m, "~-4.2s", h.str("abcdef"), "ab  "); // left-justify
    // ~ts width (ASCII byte-EQ to ~s).
    try check.go(&m, "~2ts", h.str("abcdef"), "ab");
    // erts rejects precision > width.
    try std.testing.expectError(error.Badarg, format(&m, "~2.3s", h.str("abcdef")));
    // no width → the whole string (regression: 709 precision-only still holds).
    try check.go(&m, "~.3s", h.str("abcdef"), "abc");
    try check.go(&m, "~s", h.str("abcdef"), "abcdef");
}

test "LAW gap-io-format-bignum (DIVERGENCE 689): ~w/~p of a RUNTIME bignum (and a bignum NESTED in a term) formats its base-10 decimal — was badarg (the writeTerm .number arm deferred bignums; leafStr routes ~p through writeTerm so one fix covers both)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const flat = struct {
        fn go(mm: *Machine, fmt: []const u8, args: Term) ![]u8 {
            const r = try format(mm, fmt, args);
            var got: std.ArrayList(u8) = .empty;
            var cur = r;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                try got.append(mm.ctx.gpa, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&mm.ctx, cur))));
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            return got.toOwnedSlice(mm.ctx.gpa);
        }
    }.go;

    // 2^100 (limbs {0, 1<<36}, little-endian u64) — a runtime bignum beyond the fixnum boundary.
    const big = try FinalTerms.intFromLimbs(&m.ctx, true, &.{ 0, @as(u64, 1) << 36 });
    try std.testing.expect(FinalTerms.repIsBig(&m.ctx, big));
    const dec = "1267650600228229401496703205376"; // 2^100

    const argw = FinalTerms.cons(&m.ctx, big, FinalTerms.nil(&m.ctx)) catch unreachable;
    // ~w and ~p both format the bignum's decimal (leafStr → writeTerm).
    const rw = try flat(&m, "~w", argw);
    defer gpa.free(rw);
    try std.testing.expectEqualStrings(dec, rw);
    const rp = try flat(&m, "~p", argw);
    defer gpa.free(rp);
    try std.testing.expectEqualStrings(dec, rp);
    // a bignum NESTED in a tuple: {a, 2^100, c}
    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const c = FinalTerms.atom(&m.ctx, try atoms.intern("c"));
    const tup = try FinalTerms.tuple(&m.ctx, &.{ a, big, c });
    const rt = try flat(&m, "~w", FinalTerms.cons(&m.ctx, tup, FinalTerms.nil(&m.ctx)) catch unreachable);
    defer gpa.free(rt);
    try std.testing.expectEqualStrings("{a," ++ dec ++ ",c}", rt);
    // a NEGATIVE bignum keeps the '-'
    const nbig = try FinalTerms.intFromLimbs(&m.ctx, false, &.{ 0, @as(u64, 1) << 36 });
    const rn = try flat(&m, "~w", FinalTerms.cons(&m.ctx, nbig, FinalTerms.nil(&m.ctx)) catch unreachable);
    defer gpa.free(rn);
    try std.testing.expectEqualStrings("-" ++ dec, rn);
}

test "LAW gap-io-format-complete MAP CANONICAL-ORDER (seeded): ~w of an integer-keyed map is insertion-order-invariant and strictly ascending (seed echoed)" {
    // The canonical `#{K => V,...}` rendering is a function of the map VALUE, not
    // of key insertion order: two builds of the same key set (shuffled) print
    // byte-identically, and integer keys always appear strictly ascending — the
    // reproducible invariant that byte-EQ with the oracle rests on for numeric
    // keys. Seeded, echoed on failure; bounded map size (bounded-driver rule).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const seed: u64 = 0x33ac71;
    var prng = std.Random.DefaultPrng.init(seed);
    const rnd = prng.random();

    var it: usize = 0;
    while (it < 200) : (it += 1) {
        const n = rnd.intRangeAtMost(usize, 0, 12);
        var ks: [12]i64 = undefined;
        // distinct keys
        var built: usize = 0;
        while (built < n) {
            const cand = rnd.intRangeAtMost(i64, -50, 50);
            var dup = false;
            for (ks[0..built]) |k| if (k == cand) {
                dup = true;
            };
            if (!dup) {
                ks[built] = cand;
                built += 1;
            }
        }
        // build map from the keys in given order
        var kt1: [12]Term = undefined;
        var vt1: [12]Term = undefined;
        for (0..n) |i| {
            kt1[i] = FinalTerms.int(&m.ctx, ks[i]);
            vt1[i] = FinalTerms.int(&m.ctx, ks[i] * 2);
        }
        const map1 = try FinalTerms.mapNew(&m.ctx, kt1[0..n], vt1[0..n]);
        // shuffle a copy and rebuild
        var perm = ks;
        rnd.shuffle(i64, perm[0..n]);
        var kt2: [12]Term = undefined;
        var vt2: [12]Term = undefined;
        for (0..n) |i| {
            kt2[i] = FinalTerms.int(&m.ctx, perm[i]);
            vt2[i] = FinalTerms.int(&m.ctx, perm[i] * 2);
        }
        const map2 = try FinalTerms.mapNew(&m.ctx, kt2[0..n], vt2[0..n]);

        var o1: std.ArrayList(u8) = .empty;
        defer o1.deinit(gpa);
        var o2: std.ArrayList(u8) = .empty;
        defer o2.deinit(gpa);
        try writeMap(&m, &o1, map1, writeTerm);
        try writeMap(&m, &o2, map2, writeTerm);
        std.testing.expectEqualStrings(o1.items, o2.items) catch |e| {
            std.debug.print("SEED 0x{x} it={d} n={d} (insertion-order variance)\n", .{ seed, it, n });
            return e;
        };
        // strictly ascending integer keys: sort ks and check the rendered order.
        std.sort.insertion(i64, ks[0..n], {}, std.sort.asc(i64));
        var want: std.ArrayList(u8) = .empty;
        defer want.deinit(gpa);
        try want.appendSlice(gpa, "#{");
        for (0..n) |i| {
            if (i > 0) try want.append(gpa, ',');
            try want.print(gpa, "{d} => {d}", .{ ks[i], ks[i] * 2 });
        }
        try want.append(gpa, '}');
        std.testing.expectEqualStrings(want.items, o1.items) catch |e| {
            std.debug.print("SEED 0x{x} it={d} n={d} (not strictly ascending)\n", .{ seed, it, n });
            return e;
        };
    }
}

test "LAW gap-io-format-float TOTALITY/BOUNDEDNESS: floatData terminates and round-trips its own digits over seeded random finite f64 bit patterns (seed echoed)" {
    // Guards the exact big-decimal loop independently of the oracle rows: for a
    // seeded sweep of finite doubles, floatData yields 21 ASCII digits with a
    // sane point, and re-parsing "0.<ds>e<point>" recovers f within 1 ulp
    // (21 significant digits over-determine a double).
    var prng = std.Random.DefaultPrng.init(0xf10a7);
    const rnd = prng.random();
    var i: usize = 0;
    while (i < 500) : (i += 1) {
        const bits = rnd.int(u64);
        const f: f64 = @bitCast(bits);
        if (!std.math.isFinite(f)) continue;
        // subnormals: the pow-based REBUILD (not floatData) loses precision
        // below the normal range — their exactness is pinned by the ~w oracle
        // row for 5.0e-324 instead.
        if (f != 0.0 and @abs(f) < 2.2250738585072014e-308) continue;
        const fd = floatData(f);
        for (fd.ds) |c| std.debug.assert(c >= '0' and c <= '9');
        // reconstruct: 0.d1..d21 × 10^e
        var acc: f64 = 0.0;
        var j: usize = 21;
        while (j > 0) {
            j -= 1;
            acc = (acc + @as(f64, @floatFromInt(fd.ds[j] - '0'))) / 10.0;
        }
        const rebuilt = std.math.copysign(acc * std.math.pow(f64, 10.0, @floatFromInt(fd.e)), if (fd.neg) @as(f64, -1.0) else 1.0);
        const want = f;
        if (want == 0.0) {
            std.testing.expect(rebuilt == 0.0) catch |e| {
                std.debug.print("seed 0xf10a7 i={d} bits={x}\n", .{ i, bits });
                return e;
            };
            continue;
        }
        const rel = @abs(rebuilt - want) / @abs(want);
        // 1e-12: the REBUILD path (pow+divide chain) is the loose side; byte
        // exactness is the oracle rows' job, this law guards termination+shape.
        std.testing.expect(rel < 1.0e-12) catch |e| {
            std.debug.print("seed 0xf10a7 i={d} bits={x} f={e} rebuilt={e}\n", .{ i, bits, want, rebuilt });
            return e;
        };
    }
}

test "LAW gap-io-format-pwrap: multi-line ~p/~P byte-EQ vs the pinned OTP-30 io_lib_pretty oracle (wrap, tag-align, staircase, depth, column)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const H = struct {
        m: *Machine,
        fn int(self: @This(), v: i64) Term {
            return FinalTerms.int(&self.m.ctx, v);
        }
        fn atom(self: @This(), name: []const u8) !Term {
            return FinalTerms.atom(&self.m.ctx, try self.m.ctx.atoms.intern(name));
        }
        /// an atom of `n` repeats of `ch` (the oracle probes' a20/b40 shapes)
        fn atomN(self: @This(), ch: u8, n: usize) !Term {
            var buf: [48]u8 = undefined;
            @memset(buf[0..n], ch);
            return self.atom(buf[0..n]);
        }
        /// lists:seq(lo,hi) with an arbitrary tail (nil or improper atom)
        fn seqT(self: @This(), lo: i64, hi: i64, tail: Term) Term {
            var l = tail;
            var v = hi;
            while (v >= lo) : (v -= 1) {
                l = FinalTerms.cons(&self.m.ctx, self.int(v), l) catch unreachable;
            }
            return l;
        }
        fn seq(self: @This(), lo: i64, hi: i64) Term {
            return self.seqT(lo, hi, FinalTerms.nil(&self.m.ctx));
        }
        fn list(self: @This(), items: []const Term) Term {
            var l = FinalTerms.nil(&self.m.ctx);
            var i = items.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(&self.m.ctx, items[i], l) catch unreachable;
            }
            return l;
        }
        fn tup(self: @This(), items: []const Term) Term {
            return FinalTerms.tuple(&self.m.ctx, items) catch unreachable;
        }
        /// a latin1 charlist from bytes (the string-element probes)
        fn chars(self: @This(), s: []const u8) Term {
            var l = FinalTerms.nil(&self.m.ctx);
            var i = s.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(&self.m.ctx, self.int(s[i]), l) catch unreachable;
            }
            return l;
        }
    };
    const h = H{ .m = &m };

    const check = struct {
        fn go(mm: *Machine, fmt: []const u8, args: Term, want: []const u8) !void {
            const r = try format(mm, fmt, args);
            var got: std.ArrayList(u8) = .empty;
            defer got.deinit(std.testing.allocator);
            var cur = r;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                try got.append(std.testing.allocator, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&mm.ctx, cur))));
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            try std.testing.expectEqualStrings(want, got.items);
        }
    }.go;

    // every `exp` is the EXACT byte string the pinned OTP-30 oracle returned
    // (probe run recorded in the pwrap design doc; newlines/indent literal).
    const exp1 = "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,\n 29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50]";
    const exp2 = "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,\n 29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,\n 54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,\n 79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100]";
    const exp3 = "{1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,\n 29,30}";
    const exp4 = "{aaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbb,cccccccccccccccccccc,\n                      dddddddddddddddddddd,eeeeeeeeeeeeeeeeeeee}";
    const exp5 = "{error,aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,\n       bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,cccccccccc}";
    const exp7 = "[{key1,value1},\n {key2,value2},\n {key3,value3},\n {key4,value4},\n {key5,value5},\n {key6,value6}]";
    const exp8 = "[\"a fairly long string element here\",\"a fairly long string element here\",\n \"a fairly long string element here\"]";
    const exp9 = "{deep,\n    {nesting,\n        {goes,\n            {here,\n                {with,\n                    {many,\n                        {levels,\n                            {ofx,\n                                {tuples,\n                                    [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,\n                                     17,18,19,20,21,22,23,24,25,26,27,28,29,\n                                     30]}}}}}}}}}";
    const exp10 = "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,\n 16,17,18,19,20,21,22,23,24,25,26,27,\n 28,29,30]";
    const exp11 = "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,\n          26,27,28,29,30]";
    const exp12 = "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50]";
    const exp14 = "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,\n 29|...]";
    const exp19 = "pre: [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,\n      28,29,30]";
    const exp21 = "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,\n 29,30,31,32,33,34,35,36,37,38,39,40|last_tail_atom]";
    const exp22 = "[[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,\n  29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,\n  54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,\n  79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100]]";
    const exp23 = "[1,\n 2,\n 3,\n 4,\n 5]";
    const exp25 = "[1,2,3,\n 4,5,6,\n 7,8]";
    const exp26 = "[1,2,3,4,\n 5,6,7,8]";
    const exp27 = "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20] [1,2,3,4,5,6,7,8,9,10,11,\n                                                      12,13,14,15,16,17,18,19,\n                                                      20]";

    // wrap + packing (the strict-< fits inequalities; 76-char lines at Ll=80)
    try check(&m, "~p", h.list(&.{h.seq(1, 50)}), exp1);
    try check(&m, "~p", h.list(&.{h.seq(1, 100)}), exp2);
    // untagged tuple: indent 1
    var t30: [30]Term = undefined;
    for (&t30, 0..) |*e, i| e.* = h.int(@intCast(i + 1));
    try check(&m, "~p", h.list(&.{h.tup(&t30)}), exp3);
    // tagged tuple: align after the tag (22 / 7)
    try check(&m, "~p", h.list(&.{h.tup(&.{ try h.atomN('a', 20), try h.atomN('b', 20), try h.atomN('c', 20), try h.atomN('d', 20), try h.atomN('e', 20) })}), exp4);
    try check(&m, "~p", h.list(&.{h.tup(&.{ try h.atom("error"), try h.atomN('a', 40), try h.atomN('b', 40), try h.atomN('c', 10) })}), exp5);
    // composites never pack (one tuple per line despite room)
    try check(&m, "~p", h.list(&.{h.list(&.{
        h.tup(&.{ try h.atom("key1"), try h.atom("value1") }),
        h.tup(&.{ try h.atom("key2"), try h.atom("value2") }),
        h.tup(&.{ try h.atom("key3"), try h.atom("value3") }),
        h.tup(&.{ try h.atom("key4"), try h.atom("value4") }),
        h.tup(&.{ try h.atom("key5"), try h.atom("value5") }),
        h.tup(&.{ try h.atom("key6"), try h.atom("value6") }),
    })}), exp7);
    // strings ARE packable leaves (two per line)
    const lstr = h.chars("a fairly long string element here");
    try check(&m, "~p", h.list(&.{h.list(&.{ lstr, lstr, lstr })}), exp8);
    // the TInd=4 staircase (cind fallback engaged)
    try check(&m, "~p", h.list(&.{h.tup(&.{ try h.atom("deep"), h.tup(&.{ try h.atom("nesting"), h.tup(&.{ try h.atom("goes"), h.tup(&.{ try h.atom("here"), h.tup(&.{ try h.atom("with"), h.tup(&.{ try h.atom("many"), h.tup(&.{ try h.atom("levels"), h.tup(&.{ try h.atom("ofx"), h.tup(&.{ try h.atom("tuples"), h.seq(1, 30) }) }) }) }) }) }) }) }) })}), exp9);
    // F = line length; P = start column; F=0 = flat
    try check(&m, "~40p", h.list(&.{h.seq(1, 30)}), exp10);
    try check(&m, "~80.10p", h.list(&.{h.seq(1, 30)}), exp11);
    try check(&m, "~0p", h.list(&.{h.seq(1, 50)}), exp12);
    // ~P: the SECOND depth argument (flat + wrapped + containers + heuristic-off)
    try check(&m, "~P", h.list(&.{ h.seq(1, 100), h.int(5) }), "[1,2,3,4|...]");
    try check(&m, "~P", h.list(&.{ h.seq(1, 100), h.int(30) }), exp14);
    try check(&m, "~P", h.list(&.{ h.tup(&.{ h.int(1), h.int(2), h.int(3), h.int(4), h.int(5) }), h.int(3) }), "{1,2,...}");
    try check(&m, "~P", h.list(&.{ h.tup(&.{ try h.atom("a"), h.tup(&.{ try h.atom("b"), h.tup(&.{ try h.atom("c"), h.tup(&.{ try h.atom("d"), h.tup(&.{ try h.atom("e"), try h.atom("f") }) }) }) }) }), h.int(3) }), "{a,{...}}");
    try check(&m, "~P", h.list(&.{ h.tup(&.{h.chars("hi")}), h.int(2) }), "{[...]}"); // string heuristic OFF at depth 1
    try check(&m, "~P", h.list(&.{ h.seq(1, 10), h.int(0) }), "...");
    try check(&m, "~P", h.list(&.{ h.seq(1, 10), h.int(-1) }), "[1,2,3,4,5,6,7,8,9,10]");
    // DIVERGENCE 696: ~W — FLAT (~w) write with the SECOND depth argument (was badarg).
    try check(&m, "~W", h.list(&.{ h.seq(1, 5), h.int(3) }), "[1,2|...]"); // depth 3: 2 elems + |...
    try check(&m, "~W", h.list(&.{ h.tup(&.{ try h.atom("a"), h.tup(&.{ try h.atom("b"), h.tup(&.{ try h.atom("c"), try h.atom("d") }) }) }), h.int(2) }), "{a,...}");
    try check(&m, "~W", h.list(&.{ h.tup(&.{ try h.atom("x"), try h.atom("y"), try h.atom("z") }), h.int(5) }), "{x,y,z}"); // depth 5: full
    try check(&m, "~W", h.list(&.{ h.seq(1, 3), h.int(0) }), "..."); // depth 0: whole term elided
    try check(&m, "~W", h.list(&.{ h.seq(1, 3), h.int(-1) }), "[1,2,3]"); // depth <0: unlimited
    try check(&m, "~10W", h.list(&.{ try h.atom("ok"), h.int(3) }), "        ok"); // field width applies (unlike ~P)
    // ~W depth arg missing / non-int → badarg (mirrors ~P)
    try std.testing.expectError(error.Badarg, format(&m, "~W", h.list(&.{try h.atom("foo")})));
    try std.testing.expectError(error.Badarg, format(&m, "~W", h.list(&.{ try h.atom("foo"), try h.atom("bar") })));
    // DIVERGENCE 699: ~P/~p PER-PAIR map depth truncation (D shows D-1 pairs then ",...").
    // Integer keys → canonical (sorted) order matches erts small-map order (byte-EQ subset).
    {
        const m5 = try FinalTerms.mapNew(&m.ctx, &.{ h.int(1), h.int(2), h.int(3), h.int(4), h.int(5) }, &.{ try h.atom("a"), try h.atom("b"), try h.atom("c"), try h.atom("d"), try h.atom("e") });
        try check(&m, "~P", h.list(&.{ m5, h.int(3) }), "#{1 => a,2 => b,...}"); // depth 3 → 2 pairs + ,...
        const m3 = try FinalTerms.mapNew(&m.ctx, &.{ h.int(1), h.int(2), h.int(3) }, &.{ try h.atom("a"), try h.atom("b"), try h.atom("c") });
        try check(&m, "~P", h.list(&.{ m3, h.int(2) }), "#{1 => a,...}"); // depth 2 → 1 pair + ,...
        const m2 = try FinalTerms.mapNew(&m.ctx, &.{ h.int(1), h.int(2) }, &.{ try h.atom("a"), try h.atom("b") });
        try check(&m, "~P", h.list(&.{ m2, h.int(5) }), "#{1 => a,2 => b}"); // depth 5 ≥ 2 pairs → full, no dots
    }
    // default column = current output column + 1 (preceding text shifts wrap)
    try check(&m, "pre: ~p", h.list(&.{h.seq(1, 30)}), exp19);
    try check(&m, "~p ~p", h.list(&.{ h.seq(1, 20), h.seq(1, 20) }), exp27);
    // improper tail wraps with the container
    try check(&m, "~p", h.list(&.{h.seqT(1, 40, try h.atom("last_tail_atom"))}), exp21);
    // singleton nesting: the pending-closer (LD) reservation
    try check(&m, "~p", h.list(&.{h.list(&.{h.seq(1, 100)})}), exp22);
    // tiny Ll: one leaf per line; boundary widths pin the strict-< inequalities
    try check(&m, "~1p", h.list(&.{h.seq(1, 5)}), exp23);
    try check(&m, "~10p", h.list(&.{h.seq(1, 8)}), exp25);
    try check(&m, "~11p", h.list(&.{h.seq(1, 8)}), exp26);
    // rejection: no left-adjust clause for p; ~P depth arg missing / non-int
    try std.testing.expectError(error.Badarg, format(&m, "~-40p", h.list(&.{h.seq(1, 30)})));
    try std.testing.expectError(error.Badarg, format(&m, "~P", h.list(&.{try h.atom("foo")})));
    try std.testing.expectError(error.Badarg, format(&m, "~P", h.list(&.{ try h.atom("foo"), try h.atom("bar") })));
}

test "LAW gap-io-format-pwrap HOMOMORPHISM (seeded): a term that FITS the line pretty-prints exactly as its flat single-line ~p form" {
    // pretty(t) == flat(t) whenever flat width < Ll - the wrap machinery is a
    // pure representation change for fitting terms. Seeded generator, echoed on
    // failure; bounded depth/size (bounded-driver rule).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const seed: u64 = 0x9f0a2c;
    var prng = std.Random.DefaultPrng.init(seed);
    const rnd = prng.random();

    const Gen = struct {
        fn term(mm: *Machine, r: std.Random, depth: usize) Term {
            const pick = if (depth == 0) r.intRangeAtMost(u8, 0, 1) else r.intRangeAtMost(u8, 0, 3);
            switch (pick) {
                0 => return FinalTerms.int(&mm.ctx, r.intRangeAtMost(i64, -999, 999)),
                1 => {
                    const names = [_][]const u8{ "a", "ok", "foo", "bar_baz", "x" };
                    const nm = names[r.intRangeAtMost(usize, 0, names.len - 1)];
                    return FinalTerms.atom(&mm.ctx, mm.ctx.atoms.intern(nm) catch unreachable);
                },
                2 => {
                    var l = FinalTerms.nil(&mm.ctx);
                    var i: usize = r.intRangeAtMost(usize, 0, 4);
                    while (i > 0) : (i -= 1) {
                        l = FinalTerms.cons(&mm.ctx, term(mm, r, depth - 1), l) catch unreachable;
                    }
                    return l;
                },
                else => {
                    var items: [4]Term = undefined;
                    const n = r.intRangeAtMost(usize, 0, 4);
                    for (items[0..n]) |*e| e.* = term(mm, r, depth - 1);
                    return FinalTerms.tuple(&mm.ctx, items[0..n]) catch unreachable;
                },
            }
        }
    };

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const t = Gen.term(&m, rnd, 3);
        var flat: std.ArrayList(u8) = .empty;
        defer flat.deinit(gpa);
        try writeTermP(&m, &flat, t);
        if (flat.items.len >= 79) continue; // only fitting terms are in-law
        var pretty: std.ArrayList(u8) = .empty;
        defer pretty.deinit(gpa);
        try writeTermPretty(&m, &pretty, t, -1, 80, 1);
        std.testing.expectEqualStrings(flat.items, pretty.items) catch |e| {
            std.debug.print("SEED 0x{x} case {d}\n", .{ seed, i });
            return e;
        };
    }
}

test "LAW gap-io-format-binary: ~w/~p/~s of a binary byte-EQ vs the pinned OTP-30 oracle (byte-list, printable-string heuristic, escaping, empty, nesting, ~P depth)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const H = struct {
        m: *Machine,
        fn bin(self: @This(), bytes: []const u8) Term {
            return FinalTerms.binary(&self.m.ctx, bytes) catch unreachable;
        }
        fn int(self: @This(), v: i64) Term {
            return FinalTerms.int(&self.m.ctx, v);
        }
        fn atom(self: @This(), name: []const u8) !Term {
            return FinalTerms.atom(&self.m.ctx, try self.m.ctx.atoms.intern(name));
        }
        fn list(self: @This(), items: []const Term) Term {
            var l = FinalTerms.nil(&self.m.ctx);
            var i = items.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(&self.m.ctx, items[i], l) catch unreachable;
            }
            return l;
        }
        fn tup(self: @This(), items: []const Term) Term {
            return FinalTerms.tuple(&self.m.ctx, items) catch unreachable;
        }
        fn map(self: @This(), keys: []const Term, vals: []const Term) Term {
            return FinalTerms.mapNew(&self.m.ctx, keys, vals) catch unreachable;
        }
    };
    const h = H{ .m = &m };
    const check = struct {
        fn go(mm: *Machine, fmt: []const u8, args: Term, want: []const u8) !void {
            const r = try format(mm, fmt, args);
            var got: std.ArrayList(u8) = .empty;
            defer got.deinit(std.testing.allocator);
            var cur = r;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                try got.append(std.testing.allocator, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&mm.ctx, cur))));
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            try std.testing.expectEqualStrings(want, got.items);
        }
    }.go;

    // Every `want` below is the EXACT byte string the pinned OTP-30 679f9dbb oracle
    // returned (fixtures/erl/*orc*.erl differential). ── ~w: byte-list form ──
    try check(&m, "~w", h.list(&.{h.bin("ping")}), "<<112,105,110,103>>");
    try check(&m, "~w", h.list(&.{h.bin("")}), "<<>>");
    try check(&m, "~w", h.list(&.{h.bin(&.{ 1, 2, 3 })}), "<<1,2,3>>");
    try check(&m, "~w", h.list(&.{h.bin(&.{ 255, 0, 127 })}), "<<255,0,127>>");
    // ── ~p: printable → <<"...">> (with escaping); non-printable/empty → byte form ──
    try check(&m, "~p", h.list(&.{h.bin("ping")}), "<<\"ping\">>");
    try check(&m, "~p", h.list(&.{h.bin("")}), "<<>>");
    try check(&m, "~p", h.list(&.{h.bin(&.{ 1, 2, 3 })}), "<<1,2,3>>");
    try check(&m, "~p", h.list(&.{h.bin(&.{ 'a', 'b', 1 })}), "<<97,98,1>>"); // one non-printable → all byte form
    try check(&m, "~p", h.list(&.{h.bin("has \"quote\" and \\bs")}), "<<\"has \\\"quote\\\" and \\\\bs\">>");
    try check(&m, "~p", h.list(&.{h.bin(&.{ 8, 9, 10, 11, 12, 13, 27 })}), "<<\"\\b\\t\\n\\v\\f\\r\\e\">>");
    try check(&m, "~p", h.list(&.{h.bin(&.{ 160, 200, 255 })}), "<<\"\xA0\xC8\xFF\">>"); // high latin1 printable
    try check(&m, "~p", h.list(&.{h.bin(&.{159})}), "<<159>>"); // 159 not printable
    // ── ~s: raw latin1 bytes (incl. binaries nested in an iolist) ──
    try check(&m, "~s", h.list(&.{h.bin("hi")}), "hi");
    try check(&m, "~s", h.list(&.{h.bin("")}), "");
    try check(&m, "~s", h.list(&.{h.list(&.{ h.bin("io"), h.bin("list") })}), "iolist");
    // ── nesting: ~w byte-form vs ~p heuristic inside a tuple/list/map ──
    try check(&m, "~w", h.list(&.{h.tup(&.{ try h.atom("y"), h.bin("x") })}), "{y,<<120>>}");
    try check(&m, "~p", h.list(&.{h.tup(&.{ try h.atom("y"), h.bin("x") })}), "{y,<<\"x\">>}");
    try check(&m, "~p", h.list(&.{h.map(&.{try h.atom("k")}, &.{h.bin("v")})}), "#{k => <<\"v\">>}");
    // ── ~P depth: a binary collapses to <<...>> at depth 1, full at depth ≥ 2 ──
    try check(&m, "~P", h.list(&.{ h.bin("ping"), h.int(1) }), "<<...>>");
    try check(&m, "~P", h.list(&.{ h.bin("ping"), h.int(2) }), "<<\"ping\">>");
    try check(&m, "~P", h.list(&.{ h.tup(&.{ try h.atom("a"), h.bin("ping") }), h.int(2) }), "{a,...}");
}

// LAW gap-io-format-unicode (DIVERGENCE 626): the `t` modifier — `~ts`/`~tc`
// treat integer args as UNICODE CODEPOINTS and emit UTF-8, where latin1
// `~s`/`~c` handle only 0..255. Every case byte-EQ vs the pinned OTP-30
// io_lib:format oracle (probed via unicode:characters_to_binary/2), NARROWING
// the io_format EQUIV remainder (the `~ts/~tp unicode` sub-gap closed). Mutants:
// MUT-UNI-1 (t modifier ignored → ~ts == ~s → badarg on 955), MUT-UNI-2
// (encodeCp dropped → codepoint truncated to a byte → wrong bytes).
test "LAW gap-io-format-unicode: ~ts/~tc emit UTF-8 for codepoints; ~s rejects >255; boundaries — byte-EQ vs pinned OTP-30" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const H = struct {
        m: *Machine,
        fn ints(self: @This(), vs: []const i64) Term {
            var l = FinalTerms.nil(&self.m.ctx);
            var i = vs.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(&self.m.ctx, FinalTerms.int(&self.m.ctx, vs[i]), l) catch unreachable;
            }
            return l;
        }
        fn list(self: @This(), items: []const Term) Term {
            var l = FinalTerms.nil(&self.m.ctx);
            var i = items.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(&self.m.ctx, items[i], l) catch unreachable;
            }
            return l;
        }
        fn int(self: @This(), v: i64) Term {
            return FinalTerms.int(&self.m.ctx, v);
        }
        fn bin(self: @This(), b: []const u8) Term {
            return FinalTerms.binary(&self.m.ctx, b) catch unreachable;
        }
    };
    const h = H{ .m = &m };
    const check = struct {
        fn go(mm: *Machine, fmt: []const u8, args: Term, want: []const u8) !void {
            const r = try format(mm, fmt, args);
            var got: std.ArrayList(u8) = .empty;
            defer got.deinit(std.testing.allocator);
            var cur = r;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                try got.append(std.testing.allocator, @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&mm.ctx, cur))));
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            try std.testing.expectEqualStrings(want, got.items);
        }
    }.go;

    // ~ts: codepoints → UTF-8 (oracle: ~ts [955] = <<206,187>>).
    try check(&m, "~ts", h.list(&.{h.ints(&.{955})}), "\xCE\xBB"); // λ  (MUT-UNI-2 reds)
    try check(&m, "~ts", h.list(&.{h.ints(&.{ 104, 105 })}), "hi"); // ascii unchanged
    try check(&m, "~ts", h.list(&.{h.ints(&.{ 104, 955, 105 })}), "h\xCE\xBBi"); // mixed
    try check(&m, "~tc", h.list(&.{h.int(955)}), "\xCE\xBB"); // single char
    try check(&m, "~2tc", h.list(&.{h.int(955)}), "\xCE\xBB\xCE\xBB"); // repeat
    // ~ts on a UTF-8 binary = pass-through chardata.
    try check(&m, "~ts", h.list(&.{h.bin("h\xC3\xA9")}), "h\xC3\xA9"); // <<"hé"/utf8>>
    // 4-byte codepoint (U+1F600 😀 = F0 9F 98 80).
    try check(&m, "~ts", h.list(&.{h.ints(&.{0x1F600})}), "\xF0\x9F\x98\x80");

    // BOUNDARIES: latin1 ~s rejects a >255 codepoint (oracle: badarg). (MUT-UNI-1 reds)
    try std.testing.expectError(error.Badarg, format(&m, "~s", h.list(&.{h.ints(&.{955})})));
    // ~ts rejects an out-of-range codepoint.
    try std.testing.expectError(error.Badarg, format(&m, "~ts", h.list(&.{h.ints(&.{0x110000})})));
}
