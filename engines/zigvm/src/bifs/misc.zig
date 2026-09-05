//! # bifs/misc — small standalone BIF wrappers/constants (E3.18)
//!
//! ## Signature
//! Same contract as the other family modules
//! (`pub fn (m, args) BifError!Term`). This module hosts the E2 fast-follow
//! "misc" siblings (DIVERGENCE_LOG entry 13(a)) that do not belong to a larger
//! family module:
//!   error_logger:warning_map/0  — the constant `warning` (the pin's HARDCODED
//!                                 default `erts_error_logger_warnings =
//!                                 am_warning`, `erl_init.c`; the `+W` flag that
//!                                 overrides it is not modeled — a documented
//!                                 caveat, matching the pin's default behaviour).
//!   io:printable_range/0        — the constant `latin1` (the pin's HARDCODED
//!                                 default `printable_character_set =
//!                                 ERL_PRINTABLE_CHARACTERS_LATIN1`,
//!                                 `erl_sys_common_misc.c`; the `+pc` flag that
//!                                 overrides it is not modeled).
//!   string:list_to_float/1      — the erts `string_list_to_float_1` grammar
//!                                 (`bif.c`): parse a LEADING float prefix and
//!                                 return `{Float, RestChars}`, or
//!                                 `{error, no_float}` / `{error, not_a_list}`.
//!   erts_debug:dist_ext_to_term/2 — E8.2f debug distribution-external decoder:
//!                                 validate the atom-cache tuple and decode the
//!                                 binary via `etf.decodeDist`; this is a term
//!                                 decoder, not a live dist-channel handle.
//!
//! ## Laws (see the E3.18 suite below)
//!   - CONSTANTS: warning_map/0 == `warning`; printable_range/0 == `latin1`.
//!   - GRAMMAR: `string:list_to_float("2.3ok")` == `{2.3, "ok"}`; a leading
//!     `"3"` (no `.`) or a non-list → the error shapes; the exponent is consumed
//!     only when it is well-formed (`"1.0e2x"` -> `{100.0,"x"}`,
//!     `"1.0ex"` -> `{1.0,"ex"}`).

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const etf = @import("../etf.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

// ── constants ────────────────────────────────────────────────────────────────

pub fn warning_map_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const idx = m.ctx.atoms.intern("warning") catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

pub fn printable_range_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const idx = m.ctx.atoms.intern("latin1") catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

// ── E7.7: the debugger-capability query (the ONE honest tooling-stratum flip) ──
//
// `erl_debugger:supported/0` is a STATIC capability flag — whether the emulator
// was built with debugger instrumentation (`+D`). It takes no arguments and its
// value is a build property, not a per-term computation. zigvm has NO debugger
// subsystem (no breakpoint/stack-frame/xreg-peek engine), so its TRUTHFUL answer
// is `false` — matching a non-debug OTP build. Host-verified on the OTP-28 oracle
// (a default, non-`+D` build): `erl_debugger:supported() =:= false`. This is the
// authorized shape for the E7 tooling stratum — "implement the QUERY surface with
// zigvm's truthful capabilities" — never a fabricated `true` (that would be the
// coverage_support/0 false-EQ trap the plan's entry-88 guard names). The REST of
// the erl_debugger surface (register/breakpoints/stack_frames/xregs) needs the
// real debugger engine and stays justified (deferred-erl-debugger, bif_gen.ml).
pub fn erl_debugger_supported_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args; // a static capability query — argument-free
    return FinalTerms.atom(&m.ctx, m.bool_false);
}

// ── E8.2f: erts_debug:dist_ext_to_term/2 ───────────────────────────────────

/// `erts_debug:dist_ext_to_term(AtomCacheTuple, Binary)` decodes a versioned
/// distribution external term. The atom-cache tuple maps `ATOM_CACHE_REF`
/// indices; ordinary ETF terms are accepted by the same decoder. Malformed atom
/// tables, non-binaries, sub-byte bitstrings, and decode errors are `badarg`.
pub fn dist_ext_to_term_2(m: *Machine, args: []const Term) BifError!Term {
    const table = args[0];
    const bin = args[1];
    if (FinalTerms.kindOf(&m.ctx, table) != .tuple) return error.Badarg;
    if (!FinalTerms.repIsBinary(&m.ctx, bin)) return error.Badarg;

    const arity = FinalTerms.tupleArity(&m.ctx, table);
    if (arity > 255) return error.Badarg;
    var atoms: [255]Term = undefined;
    for (0..arity) |i| {
        const atom = FinalTerms.tupleElem(&m.ctx, table, i);
        if (FinalTerms.kindOf(&m.ctx, atom) != .atom) return error.Badarg;
        atoms[i] = atom;
    }
    return etf.decodeDist(m.gpa, &m.ctx, atoms[0..arity], FinalTerms.binBytes(&m.ctx, bin)) catch return error.Badarg;
}

// ── string:list_to_float/1 ───────────────────────────────────────────────────

/// Scan the LONGEST valid float prefix of `s` (erts grammar: `[sign] DIGITS '.'
/// DIGITS [ (e|E) [sign] DIGITS ]`). Returns the consumed byte length, or null
/// if there is no valid `INT.FRAC` prefix. The exponent is consumed only when
/// fully well-formed (the erts SAVE_E/LOAD_E backtrack).
fn scanFloatPrefix(s: []const u8) ?usize {
    var i: usize = 0;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
    const int_start = i;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') i += 1;
    if (i == int_start) return null; // need at least one integer digit
    if (i >= s.len or s[i] != '.') return null; // need the decimal point
    i += 1;
    const frac_start = i;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') i += 1;
    if (i == frac_start) return null; // need at least one fraction digit
    const end_of_frac = i; // a valid float ends here even without an exponent
    // Optional exponent — consumed only if well-formed, else backtrack.
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        var j = i + 1;
        if (j < s.len and (s[j] == '+' or s[j] == '-')) j += 1;
        const exp_start = j;
        while (j < s.len and s[j] >= '0' and s[j] <= '9') j += 1;
        if (j != exp_start) return j; // well-formed exponent: consume it
    }
    return end_of_frac;
}

fn tuple2(m: *Machine, a: Term, b: Term) BifError!Term {
    return FinalTerms.tuple(&m.ctx, &.{ a, b }) catch error.OutOfMemory;
}
fn errAtom(m: *Machine, name: []const u8) BifError!Term {
    const err = FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("error") catch return error.OutOfMemory);
    const res = FinalTerms.atom(&m.ctx, m.ctx.atoms.intern(name) catch return error.OutOfMemory);
    return tuple2(m, err, res);
}

pub fn string_list_to_float_1(m: *Machine, args: []const Term) BifError!Term {
    const w = args[0];
    const k0 = FinalTerms.kindOf(&m.ctx, w);
    if (k0 == .nil) return errAtom(m, "no_float");
    if (k0 != .cons) return errAtom(m, "not_a_list");

    // Collect the leading run of small-int char codes into a byte buffer, while
    // remembering the list TAIL after each consumed char (so `Rest` is the exact
    // suffix). A non-small/out-of-byte element terminates the run (erts
    // `is_not_small` -> end-of-float).
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(m.gpa);
    var tails: std.ArrayList(Term) = .empty;
    defer tails.deinit(m.gpa);
    var cur = w;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        if (!FinalTerms.repIsSmall(h)) break;
        const v = FinalTerms.smallValOf(h);
        if (v < 0 or v > 255) break;
        bytes.append(m.gpa, @intCast(v)) catch return error.OutOfMemory;
        cur = FinalTerms.listTail(&m.ctx, cur);
        tails.append(m.gpa, cur) catch return error.OutOfMemory;
    }

    const k = scanFloatPrefix(bytes.items) orelse return errAtom(m, "no_float");
    const f = std.fmt.parseFloat(f64, bytes.items[0..k]) catch return errAtom(m, "no_float");
    // Rest is the list tail AFTER the k-th consumed char (tails[k-1]); if k
    // consumed the whole collected run, Rest is that same tail (possibly a
    // non-parsed suffix or []).
    const rest = tails.items[k - 1];
    return tuple2(m, FinalTerms.float(&m.ctx, f), rest);
}

// ============================================================================
// Laws
// ============================================================================

const AtomTable = ta.AtomTable;

fn charList(m: *Machine, s: []const u8) !Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i: usize = s.len;
    while (i > 0) {
        i -= 1;
        acc = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, s[i]), acc);
    }
    return acc;
}

fn expectFloatRest(m: *Machine, got: BifError!Term, want_f: f64, want_rest: []const u8) !void {
    const t = try got;
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, t) == .tuple and FinalTerms.tupleArity(&m.ctx, t) == 2);
    const f = FinalTerms.tupleElem(&m.ctx, t, 0);
    try std.testing.expect(FinalTerms.repIsFloat(&m.ctx, f));
    try std.testing.expectEqual(want_f, FinalTerms.floatValOf(&m.ctx, f));
    // Rebuild the rest char list into bytes and compare.
    var rest = FinalTerms.tupleElem(&m.ctx, t, 1);
    var buf: [64]u8 = undefined;
    var n: usize = 0;
    while (FinalTerms.kindOf(&m.ctx, rest) == .cons) {
        buf[n] = @intCast(FinalTerms.smallValOf(FinalTerms.listHead(&m.ctx, rest)));
        n += 1;
        rest = FinalTerms.listTail(&m.ctx, rest);
    }
    try std.testing.expectEqualStrings(want_rest, buf[0..n]);
}

test "LAW E3.18 misc: warning_map/printable_range constants; string:list_to_float grammar" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // Constants match the pin's HARDCODED emulator defaults.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try warning_map_0(&m, &.{}), FinalTerms.atom(&m.ctx, try atoms.intern("warning"))));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try printable_range_0(&m, &.{}), FinalTerms.atom(&m.ctx, try atoms.intern("latin1"))));

    // string:list_to_float — leading float + remaining chars.
    try expectFloatRest(&m, string_list_to_float_1(&m, &.{try charList(&m, "2.3ok")}), 2.3, "ok");
    try expectFloatRest(&m, string_list_to_float_1(&m, &.{try charList(&m, "-0.5")}), -0.5, "");
    // Exponent consumed only when well-formed (SAVE_E/LOAD_E backtrack).
    try expectFloatRest(&m, string_list_to_float_1(&m, &.{try charList(&m, "1.0e2x")}), 100.0, "x");
    try expectFloatRest(&m, string_list_to_float_1(&m, &.{try charList(&m, "1.0ex")}), 1.0, "ex");
    // Error shapes: no decimal point -> no_float; [] -> no_float; non-list -> not_a_list.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try string_list_to_float_1(&m, &.{try charList(&m, "3abc")}), try errAtom(&m, "no_float")));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try string_list_to_float_1(&m, &.{FinalTerms.nil(&m.ctx)}), try errAtom(&m, "no_float")));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try string_list_to_float_1(&m, &.{FinalTerms.int(&m.ctx, 7)}), try errAtom(&m, "not_a_list")));
}

test "LAW E7.7 erl_debugger:supported/0 — the truthful debugger-capability query is false" {
    // The debugger-capability CONSTANT: zigvm has no debugger subsystem, so
    // supported/0 truthfully answers `false` (byte-EQ to a non-debug OTP build,
    // host-verified). Argument-free and total.
    //   MUTANT 1 (fabricated `true`): returning m.bool_true — the coverage_support
    //            false-EQ trap — reddens the `== false` assert below.
    //   MUTANT 2 (wrong shape): returning a non-atom (e.g. int 0) reddens the
    //            `repIsAtom` assert — the value must be the bool atom `false`,
    //            not a truthy/int stand-in.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const got = try erl_debugger_supported_0(&m, &.{});
    try std.testing.expect(FinalTerms.repIsAtom(got)); // an atom, not an int/tuple
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(got)); // exactly `false`
    // Argument-free: extra args are ignored (a static capability query).
    const got2 = try erl_debugger_supported_0(&m, &.{FinalTerms.int(&m.ctx, 1)});
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(got2));
}

test "LAW E8.2f erts_debug:dist_ext_to_term/2 decodes canonical terms and atom-cache refs" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const empty = try FinalTerms.tuple(&m.ctx, &.{});
    const one_bin = try FinalTerms.binary(&m.ctx, &.{ 131, 97, 1 });
    const one = try dist_ext_to_term_2(&m, &.{ empty, one_bin });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, one, FinalTerms.int(&m.ctx, 1)));

    const foo = FinalTerms.atom(&m.ctx, try atoms.intern("foo"));
    const table = try FinalTerms.tuple(&m.ctx, &.{foo});
    const cached_tuple = try FinalTerms.binary(&m.ctx, &.{ 131, 104, 2, 97, 1, 82, 0 });
    const got = try dist_ext_to_term_2(&m, &.{ table, cached_tuple });
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&m.ctx, got));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, got, 0), FinalTerms.int(&m.ctx, 1)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, got, 1), foo));

    const cached_list = try FinalTerms.binary(&m.ctx, &.{ 131, 108, 0, 0, 0, 2, 82, 0, 97, 2, 106 });
    const got_list = try dist_ext_to_term_2(&m, &.{ table, cached_list });
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, got_list) == .cons);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, got_list), foo));

    try std.testing.expectError(error.Badarg, dist_ext_to_term_2(&m, &.{ FinalTerms.nil(&m.ctx), one_bin }));
    const bad_table = try FinalTerms.tuple(&m.ctx, &.{FinalTerms.int(&m.ctx, 0)});
    try std.testing.expectError(error.Badarg, dist_ext_to_term_2(&m, &.{ bad_table, one_bin }));
    try std.testing.expectError(error.Badarg, dist_ext_to_term_2(&m, &.{ empty, try FinalTerms.binary(&m.ctx, &.{ 131, 82, 0 }) }));
    try std.testing.expectError(error.Badarg, dist_ext_to_term_2(&m, &.{ table, FinalTerms.int(&m.ctx, 0) }));
}

/// gap-halt-argcheck: the erts `erlang:halt/1,2` Status CONTRACT, oracle-pinned
/// (OTP-30 679f9dbb differential). A Status is VALID iff it is a NON-NEGATIVE
/// integer (→ exit code, capped 0..255 by `doNodeHalt`), the atom `abort` (→ 134),
/// or a proper STRING — a (possibly empty) list of valid Unicode codepoints
/// 0..0x10FFFF (→ crashdump slogan, exit 1). EVERYTHING else raises `badarg`:
/// a NEGATIVE integer, any atom other than `abort`, a BINARY (NOT a slogan —
/// only a charlist is), a float / tuple / bignum, or an improper / bad-codepoint
/// list (`[-1]`, `[16#110000|_]`). Validating HERE (in the BifFn, before the
/// `node_halt` trap) makes the rejection a CATCHABLE `badarg` that leaves the
/// node alive — exactly like erts, where a bad Status never terminates the node.
fn haltStatusValid(m: *Machine, status: Term) bool {
    if (FinalTerms.repIsSmall(status)) return FinalTerms.smallValOf(status) >= 0;
    if (FinalTerms.repIsAtom(status))
        return std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(status)), "abort");
    // A proper STRING: `[]` or a cons-list of small ints in [0, 0x10FFFF]. A binary,
    // float, tuple, improper tail, or an out-of-range/non-int element → badarg.
    switch (FinalTerms.kindOf(&m.ctx, status)) {
        .nil => return true, // the empty string "" is a valid (empty) slogan
        .cons => {
            var cur = status;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
                const h = FinalTerms.listHead(&m.ctx, cur);
                if (!FinalTerms.repIsSmall(h)) return false;
                const c = FinalTerms.smallValOf(h);
                if (c < 0 or c > 0x10FFFF) return false; // valid Unicode codepoint
                cur = FinalTerms.listTail(&m.ctx, cur);
            }
            return FinalTerms.kindOf(&m.ctx, cur) == .nil; // must be a PROPER list
        },
        else => return false, // binary / float / tuple / bignum / port / ref / fun / pid
    }
}

/// e50-halt: `erlang:halt/0,1,2` — terminate the node. halt/0 == halt(0).
/// Traps `.node_halt`; the Vm sets the exit code and halts every process, and
/// the driver (cli.runMulti) returns the code. A subprocess-level differential
/// (the oracle node dies with it, so the observable is the EXIT CODE).
pub fn halt_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .{ .node_halt = .{ .status = FinalTerms.int(&m.ctx, 0) } };
    return FinalTerms.int(&m.ctx, 0);
}
pub fn halt_1(m: *Machine, args: []const Term) BifError!Term {
    // gap-halt-argcheck: reject an invalid Status with a CATCHABLE badarg (the node
    // stays alive) BEFORE arming the trap — the erts contract.
    if (!haltStatusValid(m, args[0])) return error.Badarg;
    m.pending = .{ .node_halt = .{ .status = args[0] } };
    return FinalTerms.int(&m.ctx, 0); // placeholder; the run ends
}
pub fn halt_2(m: *Machine, args: []const Term) BifError!Term {
    // Status is validated identically to halt/1. halt/2 opts (flush/…) are a
    // parsed-then-ignored proper list — the exit CODE is the observable; the flush
    // behavior is not differentially observable in-VM.
    if (!haltStatusValid(m, args[0])) return error.Badarg;
    m.pending = .{ .node_halt = .{ .status = args[0] } };
    return FinalTerms.int(&m.ctx, 0);
}
