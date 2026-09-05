//! # bifs/io — the `io:*` surface riding the group-leader message protocol (E4.6)
//!
//! ## Signature
//! Same family contract: each BIF is
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over already-resolved
//! term arguments. These BIFs introduce NO new io semantics — they are a thin
//! REQUEST-BUILDER over the io / group-leader protocol implemented in `proc.zig`
//! (`Vm.serviceGroupLeader` / `doIoRequest`). Each builds the io `Request` term
//! and TRAPS `Action.io_request`; the Vm routes the full `{io_request, From,
//! ReplyAs, Request}` message to the caller's group leader (a VM-provided fixture
//! process), which appends `put_chars` output to the captured stdout sink and
//! replies `{io_reply, ReplyAs, ok}`. The Vm writes that Reply to x0.
//!
//! ## Semantic domain
//!   io:put_chars(Chars)         -> route {put_chars, unicode, Chars}; x0 = ok
//!   io:put_chars(IoDev, Chars)  -> IoDev routes to the caller's group leader
//!                                  (the standard_io fixture); same request.
//!   io:nl() / io:nl(IoDev)      -> put_chars a single '\n'; x0 = ok
//!
//! ## Scope (E4.6)
//! Only the OUTPUT verbs are wired: `put_chars/1,2` and `nl/0,1`. The formatted
//! writer verbs (`io:format/1,2,3`, `io:write/1`, `io:fwrite/*`) need a format-
//! string interpreter and the `%T`/`~p` term writer's map-order/string heuristics,
//! which stay `deferred-E4-io` in `harness/bif_gen.ml` (the printed-output writer
//! differential is only bring-up grade against the host OTP-28 oracle — see
//! DIVERGENCE_LOG.md entry 41). `put_chars` echoes bytes verbatim, so its output
//! byte-matches the oracle with NO writer involved — an honest end-to-end row.
//!
//! ## Laws (proven in proc.zig's E4.6 suite — the protocol lives there)
//!   - group-leader protocol: one io_request ⇒ exactly one io_reply, matching
//!     ReplyAs; put_chars appends exactly the flattened chars; bounded.
//!   - io round-trip: put_chars(Chars) sink bytes == flattenChars(Chars).

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const diag = @import("../diag.zig");
const io_format = @import("io_format.zig"); // gap-io-format: io_lib:format interpreter

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

/// Build `{put_chars, unicode, Chars}` and trap the io protocol. Returns a
/// placeholder (`ok`); the Vm overwrites x0 with the io_reply's Reply.
fn trapPutChars(m: *Machine, chars: Term) BifError!Term {
    const a_put_chars = try m.ctx.atoms.intern("put_chars");
    const a_unicode = try m.ctx.atoms.intern("unicode");
    const request = try FinalTerms.tuple(&m.ctx, &.{
        FinalTerms.atom(&m.ctx, a_put_chars),
        FinalTerms.atom(&m.ctx, a_unicode),
        chars,
    });
    m.pending = .{ .io_request = .{ .request = request } };
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("ok"));
}

/// `io:put_chars/1` — `put_chars(standard_io, Chars)`. Routes to the caller's
/// group leader via the io_request/io_reply protocol.
pub fn put_chars_1(m: *Machine, args: []const Term) BifError!Term {
    return trapPutChars(m, args[0]);
}

/// `io:put_chars/2` — `put_chars(IoDevice, Chars)`. The IoDevice is honored only
/// insofar as it routes to the caller's group leader (the standard_io fixture);
/// the second argument is the character data.
pub fn put_chars_2(m: *Machine, args: []const Term) BifError!Term {
    return trapPutChars(m, args[1]);
}

/// `io:nl/0` — write a newline to standard_io.
pub fn nl_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const nl = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, '\n'), FinalTerms.nil(&m.ctx));
    return trapPutChars(m, nl);
}

/// `io:nl/1` — `nl(IoDevice)`; routes to the caller's group leader as `nl/0`.
pub fn nl_1(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const nl = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, '\n'), FinalTerms.nil(&m.ctx));
    return trapPutChars(m, nl);
}

// ── gap-io-format: io:format/1,2,3 (sink) + io_lib:format/2 (pure) ────────────
// io:format renders the format string (io_format, byte-EQ with io_lib:format)
// then routes the chars through put_chars (the group-leader protocol). io_lib:
// format is the pure path — it RETURNS the charlist (no output).

/// gap-io-format-unicode (DIVERGENCE 626): `io_format.formatTerm` already emits
/// the FINAL display bytes (UTF-8 for `~ts`), so `io:format` must write them
/// VERBATIM — wrapping the flat byte-charlist into a BINARY, which the group-
/// leader flattener (`flattenChars`) appends raw. Passing the raw charlist under
/// the `unicode` tag would DOUBLE-ENCODE every >=0x80 byte (206→CE8E …). This is
/// distinct from `io:put_chars(unicode, Codepoints)`, which correctly encodes.
fn formatBin(m: *Machine, chars: Term) BifError!Term {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(m.ctx.gpa);
    var cur = chars;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.repIsSmall(h)) {
            try buf.append(m.ctx.gpa, @intCast(FinalTerms.smallValOf(h) & 0xFF));
        } else if (FinalTerms.kindOf(&m.ctx, h) == .binary) {
            try buf.appendSlice(m.ctx.gpa, FinalTerms.binBytes(&m.ctx, h));
        }
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) == .binary) try buf.appendSlice(m.ctx.gpa, FinalTerms.binBytes(&m.ctx, cur));
    return FinalTerms.binary(&m.ctx, buf.items) catch return error.OutOfMemory;
}

/// `io:format/1` — `format(Format)` == `format(Format, [])`.
pub fn format_1(m: *Machine, args: []const Term) BifError!Term {
    const chars = try io_format.formatTerm(m, args[0], FinalTerms.nil(&m.ctx));
    return trapPutChars(m, try formatBin(m, chars));
}

/// `io:format/2` — `format(Format, Args)` → put_chars.
pub fn format_2(m: *Machine, args: []const Term) BifError!Term {
    const chars = try io_format.formatTerm(m, args[0], args[1]);
    return trapPutChars(m, try formatBin(m, chars));
}

/// `io:format/3` — `format(IoDevice, Format, Args)`; IoDevice routes to the
/// caller's group leader (the standard_io fixture), as put_chars/2 does.
pub fn format_3(m: *Machine, args: []const Term) BifError!Term {
    const chars = try io_format.formatTerm(m, args[1], args[2]);
    return trapPutChars(m, try formatBin(m, chars));
}

/// `io_lib:format/2` — the PURE path: returns the rendered charlist, no output.
pub fn io_lib_format_2(m: *Machine, args: []const Term) BifError!Term {
    return io_format.formatTerm(m, args[0], args[1]);
}

/// `io_lib:write_atom/1`, `write_string/1`, `write_char/1` (DIVERGENCE 715) —
/// the pure quoted-term-text writers, delegating to `io_format` (which owns the
/// ~w escaping used everywhere else).
pub fn io_lib_write_atom_1(m: *Machine, args: []const Term) BifError!Term {
    return io_format.io_lib_write_atom_1(m, args);
}
pub fn io_lib_write_string_1(m: *Machine, args: []const Term) BifError!Term {
    return io_format.io_lib_write_string_1(m, args);
}
pub fn io_lib_write_char_1(m: *Machine, args: []const Term) BifError!Term {
    return io_format.io_lib_write_char_1(m, args);
}

// ── display / display_string (E6.6 — dirty-TAGGED direct-write verbs) ─────────
//
// erts `display/1` = `erts_printf("%.*T\n", INT_MAX, Term); return am_true` —
// the `%T` term writer (`diag.formatTermT`, a byte-verified port of
// `erl_printf_term.c`) plus a trailing newline, written DIRECTLY to fd 1.
// `display_string/2` writes the raw bytes of a string (list|bitstring) to the
// `stdout`|`stderr`|`stdin` device named by arg1, returning `true`. Both bypass
// the io/group-leader protocol (a scheduling-hint dirty tag over pure output),
// so they trap `display_out` (proc.zig appends to the captured stdout sink for
// the stdout device, then writes `true`). The stderr/stdin devices do NOT touch
// the compared stdout channel — exactly as erts writes them to fd 2 / the tty.

/// `erlang:display/1` — the `%T` term rendering + newline to stdout; returns true.
pub fn display_1(m: *Machine, args: []const Term) BifError!Term {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(m.gpa);
    diag.formatTermT(m.gpa, &m.ctx, args[0], &out) catch return error.OutOfMemory;
    out.append(m.gpa, '\n') catch return error.OutOfMemory;
    const chars = FinalTerms.binary(&m.ctx, out.items) catch return error.OutOfMemory;
    m.pending = .{ .display_out = .{ .chars = chars, .to_stdout = true } };
    return FinalTerms.atom(&m.ctx, m.bool_true);
}

/// `erlang:display_string(Device, String)` — raw string bytes to `stdout`|
/// `stderr`|`stdin`; returns true. Bad device or non-string(list|bitstring)
/// arg is badarg.
pub fn display_string_2(m: *Machine, args: []const Term) BifError!Term {
    const dev = args[0];
    if (!FinalTerms.repIsAtom(dev)) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(dev));
    const to_stdout = std.mem.eql(u8, name, "stdout");
    if (!to_stdout and !std.mem.eql(u8, name, "stderr") and !std.mem.eql(u8, name, "stdin")) return error.Badarg;
    switch (FinalTerms.kindOf(&m.ctx, args[1])) {
        .cons, .nil, .binary => {},
        else => return error.Badarg,
    }
    m.pending = .{ .display_out = .{ .chars = args[1], .to_stdout = to_stdout } };
    return FinalTerms.atom(&m.ctx, m.bool_true);
}

const AtomTable = ta.AtomTable;

test "LAW E6.6 display/1 + display_string/2: %T bytes to stdout, device routing, return true, rejection" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // display/1: returns true, traps display_out to_stdout, and the chars are
    // EXACTLY the %T rendering (diag.formatTermT) + '\n' — the byte-faithful erts
    // `erts_printf("%.*T\n", ...)` form (formatTermT is byte-verified vs the host).
    const t = try FinalTerms.tuple(&m.ctx, &.{
        FinalTerms.atom(&m.ctx, try atoms.intern("tag")),
        FinalTerms.int(&m.ctx, 7),
    });
    const r = try display_1(&m, &.{t});
    try std.testing.expect(FinalTerms.repIsAtom(r) and FinalTerms.atomIdxOf(r) == m.bool_true);
    const act = m.pending orelse return error.TestUnexpectedResult;
    try std.testing.expect(act == .display_out and act.display_out.to_stdout);
    var want: std.ArrayList(u8) = .empty;
    defer want.deinit(gpa);
    try diag.formatTermT(gpa, &m.ctx, t, &want);
    try want.append(gpa, '\n');
    try std.testing.expectEqualStrings(want.items, FinalTerms.binBytes(&m.ctx, act.display_out.chars));
    m.pending = null;

    // display_string/2: stdout device routes to the captured sink; stderr/stdin
    // do NOT (to_stdout false); returns true. Bad device / non-string is badarg.
    const hi = try FinalTerms.binary(&m.ctx, "hi");
    _ = try display_string_2(&m, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("stdout")), hi });
    try std.testing.expect(m.pending.?.display_out.to_stdout);
    m.pending = null;
    _ = try display_string_2(&m, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("stderr")), hi });
    try std.testing.expect(!m.pending.?.display_out.to_stdout);
    m.pending = null;
    try std.testing.expectError(error.Badarg, display_string_2(&m, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("bogus")), hi }));
    try std.testing.expectError(error.Badarg, display_string_2(&m, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("stdout")), FinalTerms.int(&m.ctx, 42) }));
}

// ── e47-a1: the logger-less node's logging surface (STOCK-BEAM boot path) ──
//
// proc_lib/gen_server (OTP-30) consult `logger:allow/2` on every start/success
// path and `error_logger:get_format_depth/0` when formatting reports. Both are
// stdlib LIBRARY functions (logger.erl / error_logger.erl — not bif.tab rows),
// expanded here like io:put_chars so a stock beam resolves them instead of
// trapping undef. HONESTY: zigvm runs NO logger tree, so `allow/2` answers
// `false` — the observable behavior of a node whose primary log level filters
// everything (no handler consumes the event); it is a DISCLOSED scope bound
// (no fabricated logging pipeline), empirically the exact shim under which the
// stock supervisor closure boots end-to-end (E46 gap analysis). `get_format_
// depth/0` answers `unlimited` — the pinned oracle's default (probed).

/// `logger:allow(Level, Module)` → false (no logger tree — disclosed bound).
pub fn logger_allow_2(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.atom(&m.ctx, m.bool_false);
}

/// `error_logger:get_format_depth()` → unlimited (the pinned default).
pub fn error_logger_get_format_depth_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("unlimited") catch return error.OutOfMemory);
}

/// gap-error-logger-null-sink (DIVERGENCE 650): the `error_logger` REPORTING
/// surface — `error_msg`/`error_report`/`warning_msg`/`warning_report`/
/// `info_msg`/`info_report` (arities 1 and 2) — as a NULL SINK returning `ok`.
/// This is the logger-less node's disclosed bound (the `logger:allow → false`
/// precedent): the VM deliberately does not run the logger tree, so a report is
/// a no-op that returns `ok` EXACTLY as OTP's public API does — never `undef`.
/// The `undef` was load-bearing WRONG: a SUPERVISOR crash-report path
/// (`ranch_conns_sup:report_error` → `error_logger:error_report`) hit it while
/// HANDLING a child crash, so the trapping supervisor itself crashed →
/// cascade tore down the acceptor tree (M3 recovery failure). A null sink lets
/// the supervisor contain the crash and keep serving. No value is observed
/// (the return is always `ok`), so FM-OBS-1 does not apply.
pub fn error_logger_ok(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("ok") catch return error.OutOfMemory);
}

/// gap-logger-null-sink (DIVERGENCE 742): the `logger` API surface —
/// `logger:emergency/alert/critical/error/warning/notice/info/debug` (arities
/// 1/2/3) + `logger:log` (arities 2/3/4) — as a NULL SINK returning `ok`, the
/// SAME disclosed bound as the `error_logger` null sink (650) and `logger:allow →
/// false` (e47-a1): the VM runs NO logger tree, so a log call returns `ok` (the
/// public API's EXACT return) without emitting — never `undef`. A DIRECT
/// `logger:error(...)` in app code (a proc_lib crash report, a gen_server
/// `terminate`) previously undef-KILLED the caller — the highest-severity
/// FM-DISPATCH-DEAD instance for the logging spine; the null sink lets it
/// survive. The RETURN is byte-EQ (`ok`); the EMIT (`=ERROR REPORT==== <ts>
/// ===\n<msg>` to stdout, async, level-filtered at `notice`) is the disclosed
/// "no logger tree" bound — a real handler pipeline is a separate slice that
/// would flip `logger:allow → true`. No value is observed (always `ok`) → FM-OBS-1
/// does not apply, exactly as for `error_logger_ok`.
pub fn logger_ok(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("ok") catch return error.OutOfMemory);
}
