//! # bifs/trace_bifs — the tracing BIF family (E7.6 / S29)
//!
//! ## Signature
//! Same contract as every other family module: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over ALREADY-
//! RESOLVED term arguments, computed via EXISTING Machine state (NO new term
//! semantics live here). It NEVER panics on a well-formed call.
//!
//! ## Scope — flip the HONESTLY observable, re-bind the delivery surface
//! The pinned bif.tab carries 23 tracing rows (the `dt_*` dynamic-trace tags,
//! the `seq_trace*` sequential-trace family, and the `erlang:`/`erts_internal:`/
//! `erts_trace_cleaner:` `trace*` setters). This module implements the twelve
//! whose full BEAM value is a VERSION-STABLE, SCHEDULE-INDEPENDENT observation —
//! the ones a differential can prove EQ end-to-end (`trace_surface` corpus):
//!
//!   dt_get_tag/0, dt_get_tag_data/0    a NON-dtrace build has no tag: the
//!                                       constant `undefined` (both VMs build
//!                                       without `--with-dynamic-trace`).
//!   dt_put_tag/1                        returns the PREVIOUS tag (`undefined`,
//!                                       never stored on a non-dtrace build).
//!   dt_spread_tag/1, dt_restore_tag/1   the spread/restore token pair: the
//!                                       constant `true` on a non-dtrace build.
//!   dt_prepend_vm_tag_data/1,           the IDENTITY on their argument (no VM
//!   dt_append_vm_tag_data/1             tag data exists to prepend/append to).
//!   seq_trace/2                         the token SETTER: label (any term) +
//!                                       the six flag booleans + serial, plus the
//!                                       `sequential_trace_token`-`[]` CLEAR. Each
//!                                       component returns its PREVIOUS value.
//!   seq_trace_info/1                    the token READER: `{Comp, Value}` for a
//!                                       live token, `[]` when no token is set —
//!                                       the round-trip partner of the setter.
//!   seq_trace_print/1,2                 with NO system tracer set, the constant
//!                                       `false` (nothing is printed).
//!   trace_info/2                        the empty-trace DEFAULTS: `{flags,[]}`
//!                                       and `{tracer,[]}` (an untraced process).
//!
//! ## The re-bound eleven (`deferred-trace-delivery`)
//! `trace_delivered/1`, `erts_internal:trace/3,4`, `erts_internal:trace_info/3`,
//! `trace_pattern/3,4`, `trace_session_create/3`, `trace_session_destroy/1`,
//! `notify_breakpoint_hit/3`, and `erts_trace_cleaner:check/0`,
//! `send_trace_clean_signal/1` are NOT flipped: their only honest observation is
//! a TRACE MESSAGE delivered to a tracer process (a tuple carrying pids/refs —
//! representation-coupled) or a session/breakpoint reference, over per-process
//! trace-flag engine state + a match-spec breakpoint machinery this VM does not
//! model. They re-bind to the owner token `deferred-trace-delivery` in
//! `harness/bif_gen.ml` (a dedicated tracer-delivery/breakpoint-engine slice) —
//! never a false EQ. See `DIVERGENCE_LOG.md` entry 158.
//!
//! ## Semantic domain — the sequential-trace token
//! A process either HAS a token or not (`seq_active`). A token is the tuple
//!   (label : Term, serial : (prev,cur) : ℤ², send/receive/print/timestamp/
//!    monotonic_timestamp/strict_monotonic_timestamp : 𝔹)
//! Setting ANY component makes the token exist (`seq_active := true`), defaulting
//! the untouched components (label 0, flags false, serial {0,0}). The lone
//! CLEAR is `seq_trace(sequential_trace_token, [])` (`seq_active := false`); after
//! it, `seq_trace_info(C)` denotes `[]` for every component `C`. State lives on
//! the Machine (`instr_algebra.zig`: `seq_active`, `seq_label` — a GC root —, and
//! the scalar flag/serial fields). Oracle = these exact host observations;
//! final = the Machine fields; the round-trip law glues them.
//!
//! ## Laws (below)
//!   - SEQ TOKEN ROUND-TRIP: `seq_trace(C, V)` then `seq_trace_info(C)` reads V
//!     back for every component; the setter returns the PREVIOUS value.
//!   - CLEAR / EMPTY-TOKEN: after `seq_trace(sequential_trace_token, [])` every
//!     `seq_trace_info(C)` denotes `[]` (mutant m1: a clear that leaves the token
//!     active reddens this).
//!   - DT CONSTANT / IDENTITY: `dt_get_tag`/`dt_get_tag_data`/`dt_put_tag` are the
//!     constant `undefined`; `dt_spread_tag`/`dt_restore_tag` the constant `true`;
//!     `dt_prepend/append_vm_tag_data` the identity (mutant m2: a non-identity
//!     `dt_append` reddens this).
//!   - EMPTY-TRACE DIFFERENTIAL: an untraced Machine answers `trace_info(_,flags)`
//!     `{flags,[]}` and `trace_info(_,tracer)` `{tracer,[]}`.

const std = @import("std");
const ta = @import("../term_algebra.zig");
const ia = @import("../instr_algebra.zig");
const msc = @import("../matchspec.zig");

const FinalTerms = ta.FinalTerms;
const AtomTable = ta.AtomTable;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

// ── small helpers (family-local, the pdict/procsys idiom) ────────────────────

fn atomOf(m: *Machine, name: []const u8) BifError!Term {
    const idx = m.ctx.atoms.intern(name) catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

fn undefinedAtom(m: *Machine) BifError!Term {
    return atomOf(m, "undefined");
}

fn boolTerm(m: *Machine, cond: bool) Term {
    return FinalTerms.atom(&m.ctx, if (cond) m.bool_true else m.bool_false);
}

fn asBool(m: *Machine, w: Term) ?bool {
    if (!FinalTerms.repIsAtom(w)) return null;
    const idx = FinalTerms.atomIdxOf(w);
    if (idx == m.bool_true) return true;
    if (idx == m.bool_false) return false;
    return null;
}

fn isNil(m: *Machine, w: Term) bool {
    return FinalTerms.kindOf(&m.ctx, w) == .nil;
}

fn pair(m: *Machine, tag_name: []const u8, val: Term) BifError!Term {
    const tag = try atomOf(m, tag_name);
    return FinalTerms.tuple(&m.ctx, &.{ tag, val }) catch return error.OutOfMemory;
}

fn serialTuple(m: *Machine) BifError!Term {
    const p = FinalTerms.int(&m.ctx, m.seq_serial_prev);
    const c = FinalTerms.int(&m.ctx, m.seq_serial_cur);
    return FinalTerms.tuple(&m.ctx, &.{ p, c }) catch return error.OutOfMemory;
}

// ============================================================================
// dt_* — the dynamic-trace (DTrace/SystemTap) VM tag family.
// A build WITHOUT `--with-dynamic-trace` (both VMs) has no per-process tag: the
// getters are the constant `undefined`, the spread/restore token pair the
// constant `true`, and prepend/append are the identity on their argument.
// ============================================================================

pub fn dt_get_tag_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return undefinedAtom(m);
}

pub fn dt_get_tag_data_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return undefinedAtom(m);
}

/// Returns the PREVIOUS tag — `undefined`; a non-dtrace build never stores one
/// (so a following `dt_get_tag/0` is still `undefined`).
pub fn dt_put_tag_1(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return undefinedAtom(m);
}

pub fn dt_spread_tag_1(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return boolTerm(m, true);
}

pub fn dt_restore_tag_1(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return boolTerm(m, true);
}

/// The IDENTITY on its argument (mutant m2: returning a constant reddens the
/// dt-identity law + the `trace_surface` corpus).
pub fn dt_prepend_vm_tag_data_1(m: *Machine, args: []const Term) BifError!Term {
    _ = m;
    return args[0];
}

pub fn dt_append_vm_tag_data_1(m: *Machine, args: []const Term) BifError!Term {
    _ = m;
    return args[0];
}

// ============================================================================
// seq_trace/2 — the sequential-trace token setter.
// ============================================================================

/// `seq_trace(Component, Value)`. Sets one token component (creating the token if
/// absent) and returns its PREVIOUS value. The lone special case is
/// `seq_trace(sequential_trace_token, [])` — the whole-token CLEAR.
/// `badarg` on an unknown component, a non-boolean flag value, or a malformed
/// serial (the process_flag/2 scope discipline: reject, never silently no-op).
pub fn seq_trace_2(m: *Machine, args: []const Term) BifError!Term {
    const comp = args[0];
    const val = args[1];
    if (!FinalTerms.repIsAtom(comp)) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(comp));

    // The whole-token CLEAR: `sequential_trace_token` set to `[]` resets it.
    if (std.mem.eql(u8, name, "sequential_trace_token")) {
        if (!isNil(m, val)) return error.Badarg; // installing a raw token is the delivery slice
        const was_active = m.seq_active;
        clearToken(m);
        // The previous token value: `[]` when there was none (the value the
        // corpus discards anyway — never a repr-coupled 5-tuple leaked here).
        _ = was_active;
        return FinalTerms.nil(&m.ctx);
    }

    if (std.mem.eql(u8, name, "label")) {
        const old = if (m.seq_active) m.seq_label else FinalTerms.int(&m.ctx, 0);
        m.seq_label = val;
        m.seq_active = true;
        return old;
    }

    if (std.mem.eql(u8, name, "serial")) {
        // `{Prev, Cur}` of two smalls.
        if (FinalTerms.kindOf(&m.ctx, val) != .tuple or FinalTerms.tupleArity(&m.ctx, val) != 2)
            return error.Badarg;
        const pv = FinalTerms.tupleElem(&m.ctx, val, 0);
        const cv = FinalTerms.tupleElem(&m.ctx, val, 1);
        if (!FinalTerms.repIsSmall(pv) or !FinalTerms.repIsSmall(cv)) return error.Badarg;
        const old = try serialTuple(m);
        m.seq_serial_prev = FinalTerms.smallValOf(pv);
        m.seq_serial_cur = FinalTerms.smallValOf(cv);
        m.seq_active = true;
        return old;
    }

    // The six boolean flags.
    if (flagPtr(m, name)) |ptr| {
        const b = asBool(m, val) orelse return error.Badarg;
        const old = ptr.*;
        ptr.* = b;
        m.seq_active = true;
        return boolTerm(m, old);
    }

    return error.Badarg;
}

/// `seq_trace_info(Component)`. `[]` when no token is set (the empty-token law);
/// else `{Component, Value}`.
pub fn seq_trace_info_1(m: *Machine, args: []const Term) BifError!Term {
    const comp = args[0];
    if (!FinalTerms.repIsAtom(comp)) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(comp));

    // Validity is checked BEFORE the active gate: an unknown component is badarg
    // even on a fresh process (host-faithful).
    const known = std.mem.eql(u8, name, "label") or
        std.mem.eql(u8, name, "serial") or
        flagPtr(m, name) != null;
    if (!known) return error.Badarg;

    if (!m.seq_active) return FinalTerms.nil(&m.ctx);

    if (std.mem.eql(u8, name, "label")) return pair(m, "label", m.seq_label);
    if (std.mem.eql(u8, name, "serial")) return pair(m, "serial", try serialTuple(m));
    const ptr = flagPtr(m, name).?;
    return pair(m, name, boolTerm(m, ptr.*));
}

/// `seq_trace_print/1,2` — with NO system tracer set (this VM sets none), the
/// constant `false`: there is nothing to print to. `/2` ignores its label arg
/// under the same no-tracer condition.
pub fn seq_trace_print_1(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return boolTerm(m, false);
}

pub fn seq_trace_print_2(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return boolTerm(m, false);
}

// ============================================================================
// trace_info/2 — the empty-trace DEFAULTS.
// An untraced process has no trace flags and no tracer: `{flags,[]}` /
// `{tracer,[]}`. Scope: the two items the differential observes; other items are
// the tracer-delivery slice's (badarg here, the process_flag/2 discipline).
// ============================================================================

pub fn trace_info_2(m: *Machine, args: []const Term) BifError!Term {
    const item = args[1];
    if (!FinalTerms.repIsAtom(item)) return error.Badarg;
    // gap-tracing-trace-info (DIVERGENCE 601): the FUNCTION-trace form —
    // `trace_info({M,F,A}, Item)` queries the global call-trace pattern table (Vm
    // state), so it TRAPS. `{M,F,A}` is a 3-tuple; `on_load`/`send`/`receive` (the
    // event-trace forms) are 1-tuple/atom keys handled by the process form below.
    if (FinalTerms.kindOf(&m.ctx, args[0]) == .tuple and FinalTerms.tupleArity(&m.ctx, args[0]) == 3) {
        m.pending = .{ .trace_info_mfa = .{
            .module = FinalTerms.tupleElem(&m.ctx, args[0], 0),
            .func = FinalTerms.tupleElem(&m.ctx, args[0], 1),
            .arity = FinalTerms.tupleElem(&m.ctx, args[0], 2),
            .item = item,
        } };
        return FinalTerms.nil(&m.ctx); // placeholder; the Vm writes {Item,Value} to x0
    }
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(item));
    if (std.mem.eql(u8, name, "flags")) return pair(m, "flags", FinalTerms.nil(&m.ctx));
    if (std.mem.eql(u8, name, "tracer")) return pair(m, "tracer", FinalTerms.nil(&m.ctx));
    return error.Badarg;
}

/// gap-tracing-trace-info (DIVERGENCE 601): `erlang:trace_delivered/1` — a trace
/// FLUSH barrier. Returns a fresh reference immediately and (eventually) sends
/// `{trace_delivered, Tracee, Ref}` to the caller once all trace messages up to the
/// call have been delivered. In this single-scheduler model delivery is synchronous,
/// so the handler mints the ref, delivers the message NOW, and returns the ref. The
/// arg is a pid or the atom `all` (`new`/`new_processes`/`new_ports` also accepted).
pub fn trace_delivered_1(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .trace_delivered = .{ .tracee = args[0] } };
    return FinalTerms.nil(&m.ctx); // placeholder; the Vm writes the Ref to x0
}

// ── token internals ──────────────────────────────────────────────────────────

fn clearToken(m: *Machine) void {
    m.seq_active = false;
    m.seq_label = FinalTerms.int(&m.ctx, 0);
    m.seq_serial_prev = 0;
    m.seq_serial_cur = 0;
    m.seq_send = false;
    m.seq_receive = false;
    m.seq_print = false;
    m.seq_timestamp = false;
    m.seq_monotonic = false;
    m.seq_strict_monotonic = false;
}

fn flagPtr(m: *Machine, name: []const u8) ?*bool {
    if (std.mem.eql(u8, name, "send")) return &m.seq_send;
    if (std.mem.eql(u8, name, "receive")) return &m.seq_receive;
    if (std.mem.eql(u8, name, "print")) return &m.seq_print;
    if (std.mem.eql(u8, name, "timestamp")) return &m.seq_timestamp;
    if (std.mem.eql(u8, name, "monotonic_timestamp")) return &m.seq_monotonic;
    if (std.mem.eql(u8, name, "strict_monotonic_timestamp")) return &m.seq_strict_monotonic;
    return null;
}

// ============================================================================
// Laws
// ============================================================================

const testing = std.testing;

fn tupleTag(m: *Machine, t: Term) []const u8 {
    return m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&m.ctx, t, 0)));
}

test "LAW E7.6 seq-token ROUND-TRIP: every component reads back; setter returns the previous value" {
    const gpa = testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // A fresh process has NO token: seq_trace_info denotes [].
    const before = try seq_trace_info_1(&m, &.{try atomOf(&m, "label")});
    try testing.expect(isNil(&m, before));

    // label: any term rounds through; the first set returns the default 0.
    const lbl = try atomOf(&m, "label");
    const old_lbl = try seq_trace_2(&m, &.{ lbl, FinalTerms.int(&m.ctx, 42) });
    try testing.expect(FinalTerms.repIsSmall(old_lbl) and FinalTerms.smallValOf(old_lbl) == 0);
    const got_lbl = try seq_trace_info_1(&m, &.{lbl});
    try testing.expectEqualStrings("label", tupleTag(&m, got_lbl));
    try testing.expect(FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, got_lbl, 1)) == 42);

    // send flag: false → true → false, each set returning the previous.
    const send = try atomOf(&m, "send");
    const t = try atomOf(&m, "true");
    const f = try atomOf(&m, "false");
    const o1 = try seq_trace_2(&m, &.{ send, t });
    try testing.expect(asBool(&m, o1).? == false);
    const gi = try seq_trace_info_1(&m, &.{send});
    try testing.expect(asBool(&m, FinalTerms.tupleElem(&m.ctx, gi, 1)).? == true);
    const o2 = try seq_trace_2(&m, &.{ send, f });
    try testing.expect(asBool(&m, o2).? == true);

    // a non-boolean flag value and an unknown component are BOTH badarg.
    try testing.expectError(error.Badarg, seq_trace_2(&m, &.{ send, FinalTerms.int(&m.ctx, 7) }));
    try testing.expectError(error.Badarg, seq_trace_2(&m, &.{ try atomOf(&m, "bogus"), t }));
    try testing.expectError(error.Badarg, seq_trace_info_1(&m, &.{try atomOf(&m, "bogus")}));
}

test "LAW E7.6 CLEAR / empty-token: sequential_trace_token=[] resets to no-token" {
    const gpa = testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    _ = try seq_trace_2(&m, &.{ try atomOf(&m, "label"), FinalTerms.int(&m.ctx, 9) });
    _ = try seq_trace_2(&m, &.{ try atomOf(&m, "print"), try atomOf(&m, "true") });
    try testing.expect(m.seq_active);

    // The CLEAR.
    const stt = try atomOf(&m, "sequential_trace_token");
    _ = try seq_trace_2(&m, &.{ stt, FinalTerms.nil(&m.ctx) });
    try testing.expect(!m.seq_active); // MUTANT m1 target: a clear that leaves this true reddens below.

    // After the clear EVERY component reads back []. (This is exactly what
    // mutant m1 breaks — the token would still answer {label,9}/{print,true}.)
    for ([_][]const u8{ "label", "print", "send", "serial" }) |c| {
        const got = try seq_trace_info_1(&m, &.{try atomOf(&m, c)});
        try testing.expect(isNil(&m, got));
    }

    // Only the []-form clears; a non-[] token install is the delivery slice.
    try testing.expectError(error.Badarg, seq_trace_2(&m, &.{ stt, FinalTerms.int(&m.ctx, 1) }));
}

test "LAW E7.6 dt_* CONSTANT / IDENTITY: non-dtrace tags are undefined/true/identity" {
    const gpa = testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const undef = FinalTerms.atomIdxOf(try undefinedAtom(&m));
    try testing.expect(FinalTerms.atomIdxOf(try dt_get_tag_0(&m, &.{})) == undef);
    try testing.expect(FinalTerms.atomIdxOf(try dt_get_tag_data_0(&m, &.{})) == undef);
    // dt_put_tag returns the previous tag (undefined) and stores nothing.
    try testing.expect(FinalTerms.atomIdxOf(try dt_put_tag_1(&m, &.{try atomOf(&m, "x")})) == undef);
    try testing.expect(FinalTerms.atomIdxOf(try dt_get_tag_0(&m, &.{})) == undef);
    // spread/restore token pair: constant true.
    try testing.expect(asBool(&m, try dt_spread_tag_1(&m, &.{try atomOf(&m, "true")})).? == true);
    try testing.expect(asBool(&m, try dt_restore_tag_1(&m, &.{try atomOf(&m, "true")})).? == true);
    // prepend/append are the IDENTITY (MUTANT m2 target).
    const arg = FinalTerms.int(&m.ctx, 77);
    try testing.expect(FinalTerms.eqlExact(&m.ctx, try dt_prepend_vm_tag_data_1(&m, &.{arg}), arg));
    try testing.expect(FinalTerms.eqlExact(&m.ctx, try dt_append_vm_tag_data_1(&m, &.{arg}), arg));
}

test "LAW E7.6 EMPTY-TRACE differential: an untraced process answers {flags,[]} / {tracer,[]}" {
    const gpa = testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const self = FinalTerms.int(&m.ctx, 0); // the item arg only depends on the ITEM name here
    const flags = try trace_info_2(&m, &.{ self, try atomOf(&m, "flags") });
    try testing.expectEqualStrings("flags", tupleTag(&m, flags));
    try testing.expect(isNil(&m, FinalTerms.tupleElem(&m.ctx, flags, 1)));
    const tracer = try trace_info_2(&m, &.{ self, try atomOf(&m, "tracer") });
    try testing.expectEqualStrings("tracer", tupleTag(&m, tracer));
    try testing.expect(isNil(&m, FinalTerms.tupleElem(&m.ctx, tracer, 1)));
    // seq_trace_print with no tracer is the constant false.
    try testing.expect(asBool(&m, try seq_trace_print_1(&m, &.{FinalTerms.nil(&m.ctx)})).? == false);
    try testing.expect(asBool(&m, try seq_trace_print_2(&m, &.{ FinalTerms.int(&m.ctx, 0), FinalTerms.nil(&m.ctx) })).? == false);
}

/// e50-tracing: `erlang:trace(Pid, How, FlagList)` — the flag-setter subset
/// (send + 'receive' message events). An erlang.erl wrapper over the broader
/// erts_internal:trace surface (sessions/breakpoints stay deferred); traps
/// `.trace_set`, the Vm installs the tracer+flags and delivers {trace,...}
/// messages at the signal points. Returns the matched count (1|0).
pub fn trace_3(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsPid(&m.ctx, args[0])) return error.Badarg;
    if (!FinalTerms.repIsAtom(args[1])) return error.Badarg;
    const how_name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[1]));
    const how = if (std.mem.eql(u8, how_name, "true")) true
        else if (std.mem.eql(u8, how_name, "false")) false
        else return error.Badarg;
    m.pending = .{ .trace_set = .{ .pid = args[0], .how = how, .flags = args[2] } };
    return FinalTerms.int(&m.ctx, 0); // placeholder; the VM writes the count to x0
}

// ============================================================================
// gap-tracing-e7: erlang:trace_pattern/2,3 — the call-trace BREAKPOINT setter.
// `trace_pattern(MFA, MatchSpec, FlagList)` installs (or clears) a `call`-trace
// breakpoint on a matched function set and returns the matched-function COUNT.
// When a process traced with the `call` flag (erlang:trace/3) dispatches an MFA
// covered by an enabled breakpoint, the VM delivers `{trace,Pid,call,{M,F,Args}}`
// to the tracer (the delivery + global pattern table live in proc.zig; this BIF
// validates the shape, computes the count over the caller's export table, and
// traps `.trace_pattern`).
//
// SCOPE / honest defers: MatchSpec `true`/`[]`/a compiled list all just ENABLE
// the breakpoint (`false` clears) — compiled match-spec BODIES are NOT executed,
// and `{return_trace}`/`return_to`/`meta`-tracer/session semantics stay deferred
// (never a fabricated event). The `on_load` pseudo-MFA returns 0 (nothing loaded
// to break on here); `send`/`receive` message-trace patterns are out of scope
// (badarg). erts_internal:trace_pattern/3,4 remains `justified`.
// ============================================================================

/// `MatchSpec` → enable(`true`) / disable(`false`), or `null` = badarg. `true`,
/// `[]`, and any non-empty list (a compiled match spec, body unexecuted) ENABLE;
/// `false` disables.
fn parseMatchSpec(m: *Machine, spec: Term) ?bool {
    if (FinalTerms.repIsAtom(spec)) {
        const idx = FinalTerms.atomIdxOf(spec);
        if (idx == m.bool_true) return true;
        if (idx == m.bool_false) return false;
        return null;
    }
    switch (FinalTerms.kindOf(&m.ctx, spec)) {
        .nil => return true, // `[]` = empty match spec: enable, no filter
        .cons => return true, // compiled match spec: enable (body not executed)
        else => return null,
    }
}

/// The `FlagList` must be a proper list of the recognised trace-pattern flags
/// (`local`/`global`/`meta`/`call_count`/`call_time`/`call_memory`); any other
/// element or an improper tail is badarg. `null` = the arity-2 default (`global`).
fn flagsValid(m: *Machine, flags: ?Term) bool {
    const fl = flags orelse return true;
    var cur = fl;
    var guard: usize = 0;
    while (guard < 64) : (guard += 1) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => return true,
            .cons => {
                const h = FinalTerms.listHead(&m.ctx, cur);
                if (!FinalTerms.repIsAtom(h)) return false;
                const n = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(h));
                const ok = std.mem.eql(u8, n, "local") or std.mem.eql(u8, n, "global") or
                    std.mem.eql(u8, n, "meta") or std.mem.eql(u8, n, "call_count") or
                    std.mem.eql(u8, n, "call_time") or std.mem.eql(u8, n, "call_memory");
                if (!ok) return false;
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return false,
        }
    }
    return false;
}

fn isWildcardAtom(m: *Machine, t: Term) bool {
    if (!FinalTerms.repIsAtom(t)) return false;
    return std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(t)), "_");
}

pub fn trace_pattern_3(m: *Machine, args: []const Term) BifError!Term {
    return tracePatternImpl(m, args[0], args[1], args[2]);
}

/// `trace_pattern/2` — the flags default to `[global]`; identical count/enable
/// semantics (the breakpoint set is flag-independent in this model).
pub fn trace_pattern_2(m: *Machine, args: []const Term) BifError!Term {
    return tracePatternImpl(m, args[0], args[1], null);
}

fn tracePatternImpl(m: *Machine, mfa: Term, spec: Term, flags: ?Term) BifError!Term {
    const enable = parseMatchSpec(m, spec) orelse return error.Badarg;
    if (!flagsValid(m, flags)) return error.Badarg;

    // The MFA. An atom is only the `on_load` pseudo-target (→ 0, nothing loaded);
    // any other atom is badarg. Else a `{M,F,A}` triple with `'_'` wildcards.
    if (FinalTerms.repIsAtom(mfa)) {
        if (std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(mfa)), "on_load"))
            return FinalTerms.int(&m.ctx, 0);
        return error.Badarg;
    }
    if (FinalTerms.kindOf(&m.ctx, mfa) != .tuple or FinalTerms.tupleArity(&m.ctx, mfa) != 3)
        return error.Badarg;
    const m_t = FinalTerms.tupleElem(&m.ctx, mfa, 0);
    const f_t = FinalTerms.tupleElem(&m.ctx, mfa, 1);
    const a_t = FinalTerms.tupleElem(&m.ctx, mfa, 2);

    var mod: ?ta.AtomIdx = null;
    if (!isWildcardAtom(m, m_t)) {
        if (!FinalTerms.repIsAtom(m_t)) return error.Badarg;
        mod = FinalTerms.atomIdxOf(m_t);
    }
    var fun: ?ta.AtomIdx = null;
    if (!isWildcardAtom(m, f_t)) {
        if (!FinalTerms.repIsAtom(f_t)) return error.Badarg;
        fun = FinalTerms.atomIdxOf(f_t);
    }
    var ar: ?u32 = null;
    if (!isWildcardAtom(m, a_t)) {
        if (!FinalTerms.repIsSmall(a_t)) return error.Badarg;
        const av = FinalTerms.smallValOf(a_t);
        // A negative arity matches nothing (erts: count 0, NOT badarg) and has no
        // breakpoint effect — short-circuit.
        if (av < 0) return FinalTerms.int(&m.ctx, 0);
        ar = @intCast(av);
    }

    const count = m.countMatchingExports(mod, fun, ar);
    // gap-tracing-firepath (DIVERGENCE 636): when the MatchSpec is a real clause
    // LIST that COMPILES within the trace-body subset (matchspec.compileTrace),
    // carry the spec TERM so the Vm can store it stably (gcCopy) and RUN it at
    // fire time (head/guard filter + {message,_} shaping). `true`/`[]`/false and
    // any beyond-subset spec → null (the prior enable-only, bare-delivery path).
    var spec_term: ?Term = null;
    if (enable and FinalTerms.kindOf(&m.ctx, spec) == .cons) {
        var scratch = std.heap.ArenaAllocator.init(m.ctx.gpa);
        defer scratch.deinit();
        if (msc.compileTrace(&m.ctx, scratch.allocator(), spec)) |_| {
            spec_term = spec;
        } else |_| {}
    }
    m.pending = .{ .trace_pattern = .{ .module = mod, .func = fun, .arity = ar, .enable = enable, .count = count, .spec = spec_term } };
    return FinalTerms.int(&m.ctx, count); // placeholder; the VM writes count to x0
}

test "LAW gap-tracing-e7 trace_pattern REJECTION + count: bad MFA/spec/flags are badarg; on_load & negative arity are 0; the matched count is exact (pinned to the live erl vectors)" {
    const gpa = testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const modA = try atoms.intern("tp_mod");
    const f = try atoms.intern("target");
    const g = try atoms.intern("other");
    const exports = [_]ia.Export{
        .{ .module = modA, .func = f, .arity = 1, .pc = 0 },
        .{ .module = modA, .func = g, .arity = 0, .pc = 1 },
    };
    m.exports = &exports;

    const tt = try atomOf(&m, "true");
    const ff = try atomOf(&m, "false");
    const wild = try atomOf(&m, "_");
    const local = try FinalTerms.cons(&m.ctx, try atomOf(&m, "local"), FinalTerms.nil(&m.ctx));
    const H = struct {
        fn mfa(mm: *Machine, mo: Term, fu: Term, ar: Term) !Term {
            return FinalTerms.tuple(&mm.ctx, &.{ mo, fu, ar });
        }
    };
    const mod_t = FinalTerms.atom(&m.ctx, modA);
    const f_t = FinalTerms.atom(&m.ctx, f);

    // matched COUNT (oracle: {tp_mod,target,1}=1, {tp_mod,'_','_'}=2, {tp_mod,target,'_'}=1).
    const c1 = try trace_pattern_3(&m, &.{ try H.mfa(&m, mod_t, f_t, FinalTerms.int(&m.ctx, 1)), tt, local });
    try testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(c1)); // MUTANT m2: off-by-one reddens here
    const c2 = try trace_pattern_3(&m, &.{ try H.mfa(&m, mod_t, wild, wild), tt, local });
    try testing.expectEqual(@as(i64, 2), FinalTerms.smallValOf(c2));
    const c3 = try trace_pattern_3(&m, &.{ try H.mfa(&m, mod_t, f_t, wild), tt, local });
    try testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(c3));

    // `[]` and a compiled match spec are ACCEPTED (enable), NOT badarg.
    _ = try trace_pattern_3(&m, &.{ try H.mfa(&m, mod_t, f_t, FinalTerms.int(&m.ctx, 1)), FinalTerms.nil(&m.ctx), local });
    const ms = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 0), FinalTerms.nil(&m.ctx)); // a non-empty list stands in for a compiled ms
    _ = try trace_pattern_3(&m, &.{ try H.mfa(&m, mod_t, f_t, FinalTerms.int(&m.ctx, 1)), ms, local });

    // on_load → 0; negative arity → 0 (both NON-badarg per the oracle).
    try testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(try trace_pattern_3(&m, &.{ try atomOf(&m, "on_load"), tt, local })));
    try testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(try trace_pattern_3(&m, &.{ try H.mfa(&m, mod_t, f_t, FinalTerms.int(&m.ctx, -1)), tt, local })));

    // REJECTIONS: a bare atom MFA (≠on_load), a non-atom module, a non-bool/non-list
    // spec, a non-atom flag, an unknown flag atom, and a non-list flags term.
    try testing.expectError(error.Badarg, trace_pattern_3(&m, &.{ try atomOf(&m, "foo"), tt, local }));
    try testing.expectError(error.Badarg, trace_pattern_3(&m, &.{ try H.mfa(&m, FinalTerms.int(&m.ctx, 3), f_t, FinalTerms.int(&m.ctx, 1)), tt, local }));
    try testing.expectError(error.Badarg, trace_pattern_3(&m, &.{ try H.mfa(&m, mod_t, f_t, FinalTerms.int(&m.ctx, 1)), FinalTerms.int(&m.ctx, 5), local }));
    const bogus = try FinalTerms.cons(&m.ctx, try atomOf(&m, "bogus"), FinalTerms.nil(&m.ctx));
    try testing.expectError(error.Badarg, trace_pattern_3(&m, &.{ try H.mfa(&m, mod_t, f_t, FinalTerms.int(&m.ctx, 1)), tt, bogus }));
    try testing.expectError(error.Badarg, trace_pattern_3(&m, &.{ try H.mfa(&m, mod_t, f_t, FinalTerms.int(&m.ctx, 1)), tt, ff })); // flags = a bare atom, not a list

    // arity-2 (no flags) defaults valid; same count.
    const c2a = try trace_pattern_2(&m, &.{ try H.mfa(&m, mod_t, f_t, FinalTerms.int(&m.ctx, 1)), tt });
    try testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(c2a));
}
