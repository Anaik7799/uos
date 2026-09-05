//! # bifs/os — the `os:` module BIF family (E5.8b / Task 8b)
//!
//! ## Signature
//! Each BIF is a `pub fn (m: *Machine, args: []const Term) BifError!Term` over
//! already-resolved terms, computed via `Machine.clock` (the S21 clock seam) and
//! `Machine.env` (the process-environment model) — both in `time_algebra.zig`.
//!
//! ## The rows (pin `bif.tab`, `os` module)
//!   getenv/1     `EnvTable.get`  → the value charlist, or the atom `false`
//!   putenv/2     `EnvTable.put`  → `true`
//!   unsetenv/1   `EnvTable.unset`→ `true`
//!   getpid/0     the OS pid as a decimal charlist
//!   system_time/0,1  `Clock.osSystemTime` (the OS wall clock, not the erlang offset)
//!   timestamp/0  `Clock.osTimestampParts` → `{MegaSec, Sec, MicroSec}`
//!   perf_counter/0  `Clock.perfCounter`
//!
//! `os:set_signal/2` (gap-os-signals): the ACCEPT/REJECT GRAMMAR is landed here
//! (resolveLibrary → `set_signal_2`) — it IS a differential twin (probed vs the
//! pin: catchable signals × {default,handle,ignore} → ok; sigint/uncatchable/
//! unknown/bad-option → badarg). The disposition EFFECT (recording the handler +
//! real OS sigaction delivery → erl_signal_server / graceful init:stop) is the
//! Stratum-C remainder. Not landed: `os:env/0` (its list ORDER over the ambient
//! environment is not a stable observable — stays `deferred-E5`).
//!
//! ## Why EQ (property-based, never byte-based)
//! The env round-trip (`putenv` → `getenv` == value; `unsetenv` → `getenv` ==
//! false) is exactly what erts guarantees and is host-DETERMINISTIC; `getenv` of
//! an ambient var read-through is faithful because `Machine.env` is seeded from
//! the same `/proc/self/environ` erts' `environ` reads. The clock rows fold the
//! integer-type / monotonicity / timestamp-shape properties (host-nondeterministic
//! VALUES never leak). See DIVERGENCE entry 93.

const std = @import("std");
const linux = std.os.linux;
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const time_algebra = @import("../time_algebra.zig");
const time_bifs = @import("time.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

// ── charlist codec ───────────────────────────────────────────────────────────

/// Build a byte-list (Latin-1/ASCII charlist) term from raw bytes.
fn charlist(m: *Machine, s: []const u8) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = s.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, s[i]), acc) catch return error.OutOfMemory;
    }
    return acc;
}

/// Decode a charlist (proper list of byte-range small ints) or a binary into
/// `out`; `badarg` on a non-charlist / out-of-range codepoint. Env keys/values
/// are byte strings on erts, so codepoints > 255 are rejected here (a documented
/// Latin-1 bound — matching `os:putenv`'s byte-oriented environ).
fn decodeString(m: *Machine, t: Term, out: *std.ArrayList(u8)) BifError!void {
    switch (FinalTerms.kindOf(&m.ctx, t)) {
        .binary => {
            const bytes = FinalTerms.binBytes(&m.ctx, t);
            out.appendSlice(m.gpa, bytes) catch return error.OutOfMemory;
        },
        .nil => {},
        .cons => {
            var cur = t;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
                const h = FinalTerms.listHead(&m.ctx, cur);
                if (!FinalTerms.repIsSmall(h)) return error.Badarg;
                const v = FinalTerms.smallValOf(h);
                if (v < 0 or v > 255) return error.Badarg;
                out.append(m.gpa, @intCast(v)) catch return error.OutOfMemory;
                cur = FinalTerms.listTail(&m.ctx, cur);
            }
            if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg; // improper list
        },
        else => return error.Badarg,
    }
}

fn boolAtom(m: *Machine, b: bool) Term {
    return FinalTerms.atom(&m.ctx, if (b) m.bool_true else m.bool_false);
}

// ── env family ───────────────────────────────────────────────────────────────

pub fn getenv_1(m: *Machine, args: []const Term) BifError!Term {
    var key: std.ArrayList(u8) = .empty;
    defer key.deinit(m.gpa);
    try decodeString(m, args[0], &key);
    if (m.env.get(key.items)) |val| {
        return charlist(m, val);
    }
    return boolAtom(m, false); // the atom `false` — a missing var
}

pub fn putenv_2(m: *Machine, args: []const Term) BifError!Term {
    var key: std.ArrayList(u8) = .empty;
    defer key.deinit(m.gpa);
    var val: std.ArrayList(u8) = .empty;
    defer val.deinit(m.gpa);
    try decodeString(m, args[0], &key);
    try decodeString(m, args[1], &val);
    m.env.put(key.items, val.items) catch return error.OutOfMemory;
    return boolAtom(m, true);
}

pub fn unsetenv_1(m: *Machine, args: []const Term) BifError!Term {
    var key: std.ArrayList(u8) = .empty;
    defer key.deinit(m.gpa);
    try decodeString(m, args[0], &key);
    m.env.unset(key.items);
    return boolAtom(m, true);
}

pub fn getpid_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    var buf: [16]u8 = undefined;
    const pid: i64 = @intCast(linux.getpid());
    const s = std.fmt.bufPrint(&buf, "{d}", .{pid}) catch return error.Badarg;
    return charlist(m, s);
}

// ── clock family (OS wall clock directly) ────────────────────────────────────

fn intOf(m: *Machine, v: i128) BifError!Term {
    return FinalTerms.intFromI128(&m.ctx, v) catch error.OutOfMemory;
}

fn tpsOfArg(m: *Machine, arg: Term) BifError!i128 {
    if (FinalTerms.repIsAtom(arg)) {
        const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(arg));
        return time_algebra.ticksPerSecondOfAtom(name) orelse error.Badarg;
    }
    if (FinalTerms.repIsSmall(arg)) {
        return time_algebra.ticksPerSecondOfInt(FinalTerms.smallValOf(arg)) orelse error.Badarg;
    }
    return error.Badarg;
}

pub fn system_time_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return intOf(m, m.clock.osSystemTime(time_algebra.NATIVE_UNIT));
}
pub fn system_time_1(m: *Machine, args: []const Term) BifError!Term {
    return intOf(m, m.clock.osSystemTime(try tpsOfArg(m, args[0])));
}

pub fn timestamp_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return time_bifs.partsTuple(m, m.clock.osTimestampParts());
}

pub fn perf_counter_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return intOf(m, m.clock.perfCounter());
}

// ============================================================================
// Laws — end-to-end over a real Machine (env + clock seams).
// ============================================================================

const AtomTable = ta.AtomTable;

fn strEq(m: *Machine, t: Term, expect: []const u8) bool {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(m.gpa);
    decodeString(m, t, &buf) catch return false;
    return std.mem.eql(u8, buf.items, expect);
}

test "LAW E5.8b os env round-trip: putenv/getenv/unsetenv (Mutant m: unsetenv no-op reddens)" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();

    const key = try charlist(&m, "ZIGVM_OS_BIF_LAW");
    // absent → false
    const r0 = try getenv_1(&m, &.{key});
    try std.testing.expect(FinalTerms.repIsAtom(r0) and FinalTerms.atomIdxOf(r0) == m.bool_false);
    // putenv → true; getenv → value
    const val = try charlist(&m, "42");
    const pr = try putenv_2(&m, &.{ key, val });
    try std.testing.expect(FinalTerms.atomIdxOf(pr) == m.bool_true);
    const r1 = try getenv_1(&m, &.{key});
    try std.testing.expect(strEq(&m, r1, "42"));
    // unsetenv → true; getenv → false
    const ur = try unsetenv_1(&m, &.{key});
    try std.testing.expect(FinalTerms.atomIdxOf(ur) == m.bool_true);
    const r2 = try getenv_1(&m, &.{key});
    try std.testing.expect(FinalTerms.repIsAtom(r2) and FinalTerms.atomIdxOf(r2) == m.bool_false);
}

test "LAW gap-os-signals os:set_signal/2 ACCEPT/REJECT grammar: catchable signals × {default,handle,ignore} → ok; sigint / uncatchable / unknown atom / non-atom / bad option → badarg (byte-EQ vs the pinned oracle)" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();
    const A = struct {
        fn at(mm: *Machine, name: []const u8) !Term {
            return FinalTerms.atom(&mm.ctx, try mm.ctx.atoms.intern(name));
        }
    };
    const ok_atom = try A.at(&m, "ok");

    // (1) every catchable signal × every valid option → ok (the accept grammar,
    //     exactly as the pinned OTP-30 oracle answers — sigint DELIBERATELY absent).
    const good_sigs = [_][]const u8{ "sighup", "sigterm", "sigusr1", "sigusr2", "sigquit", "sigabrt", "sigalrm", "sigchld", "sigstop", "sigtstp" };
    const good_opts = [_][]const u8{ "default", "handle", "ignore" };
    for (good_sigs) |s| {
        for (good_opts) |o| {
            const r = try set_signal_2(&m, &.{ try A.at(&m, s), try A.at(&m, o) });
            try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r, ok_atom));
        }
    }
    // (2) sigint is ALWAYS badarg (the reserved break handler — the mutant target:
    //     admitting sigint would wrongly return ok).
    try std.testing.expectError(error.Badarg, set_signal_2(&m, &.{ try A.at(&m, "sigint"), try A.at(&m, "handle") }));
    // (3) uncatchable / unknown signals → badarg.
    for ([_][]const u8{ "sigkill", "sigsegv", "sigfoo", "sigbus" }) |s| {
        try std.testing.expectError(error.Badarg, set_signal_2(&m, &.{ try A.at(&m, s), try A.at(&m, "default") }));
    }
    // (4) an unknown OPTION on a valid signal → badarg (never a wrong ok).
    try std.testing.expectError(error.Badarg, set_signal_2(&m, &.{ try A.at(&m, "sigterm"), try A.at(&m, "bogus") }));
    // (5) a non-atom signal or option → badarg (totality: never a panic).
    try std.testing.expectError(error.Badarg, set_signal_2(&m, &.{ FinalTerms.int(&m.ctx, 42), try A.at(&m, "default") }));
    try std.testing.expectError(error.Badarg, set_signal_2(&m, &.{ try A.at(&m, "sigterm"), FinalTerms.int(&m.ctx, 7) }));
}

// LAW gap-os-signals-sigaction (DIVERGENCE 628): the REAL Stratum-C sigaction
// effect for default/ignore — proven on the BENIGN SIGUSR1 (nothing in zigvm
// uses it) with SAVE/RESTORE so the test process's signal state is net-zero.
// `applySignalDisposition` is the SAME production helper set_signal_2 calls
// (guarded out of test builds); this law exercises it directly. Mutants:
// MUT-SIG-1 (sigaction call dropped → disposition unchanged), MUT-SIG-2
// (ignore↔default handler swap → wrong disposition).
test "LAW gap-os-signals-sigaction: os:set_signal disposition performs a REAL sigaction (SIG_IGN/SIG_DFL) — proven on SIGUSR1, save/restore, uncatchable is a no-op" {
    const P = std.posix;
    // SAVE the current SIGUSR1 disposition (restored at the end — net-zero).
    var saved: P.Sigaction = undefined;
    P.sigaction(P.SIG.USR1, null, &saved);
    defer P.sigaction(P.SIG.USR1, &saved, null);

    // ignore → SIG_IGN, verified by querying the disposition back.
    try applySignalDisposition("sigusr1", "ignore");
    var cur: P.Sigaction = undefined;
    P.sigaction(P.SIG.USR1, null, &cur);
    try std.testing.expect(cur.handler.handler == P.SIG.IGN); // MUT-SIG-1/2 red here
    // and the effect is REAL: raising SIGUSR1 is now a no-op (we survive).
    try P.raise(P.SIG.USR1);

    // default → SIG_DFL.
    try applySignalDisposition("sigusr1", "default");
    P.sigaction(P.SIG.USR1, null, &cur);
    try std.testing.expect(cur.handler.handler == P.SIG.DFL);

    // an UNCATCHABLE signal (sigstop) is a no-op — signalNumber returns null,
    // so no sigaction is attempted (the OS would EINVAL). No error.
    try std.testing.expect(signalNumber("sigstop") == null);
    try applySignalDisposition("sigstop", "ignore"); // no-op, no crash
    // gap-os-signals-delivery: `handle` now installs a REAL handler — neither
    // SIG_DFL nor SIG_IGN. This assertion used to read "unchanged by `handle`",
    // which was the honest statement of a disclosed remainder; closing the
    // remainder makes the OPPOSITE the law.
    try applySignalDisposition("sigusr1", "handle");
    P.sigaction(P.SIG.USR1, null, &cur);
    try std.testing.expect(cur.handler.handler != P.SIG.DFL);
    try std.testing.expect(cur.handler.handler != P.SIG.IGN);
}

test "LAW E5.8b os clock: system_time/timestamp/perf_counter are integers/shaped; getpid is a charlist" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();

    const st = try system_time_0(&m, &.{});
    try std.testing.expect(FinalTerms.repIsSmall(st) or FinalTerms.kindOf(&m.ctx, st) == .number);
    const ms = FinalTerms.atom(&m.ctx, try atoms.intern("millisecond"));
    _ = try system_time_1(&m, &.{ms});
    const pc = try perf_counter_0(&m, &.{});
    try std.testing.expect(FinalTerms.repIsSmall(pc) or FinalTerms.kindOf(&m.ctx, pc) == .number);

    const ts = try timestamp_0(&m, &.{});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, ts) == .tuple and FinalTerms.tupleArity(&m.ctx, ts) == 3);
    const sec = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, ts, 1));
    const micro = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, ts, 2));
    try std.testing.expect(sec >= 0 and sec < 1_000_000 and micro >= 0 and micro < 1_000_000);

    const pid = try getpid_0(&m, &.{});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, pid) == .cons); // a nonempty charlist

    // REJECTION: a non-string key / bad unit → badarg.
    try std.testing.expectError(error.Badarg, getenv_1(&m, &.{FinalTerms.int(&m.ctx, 7)}));
    const bad = FinalTerms.atom(&m.ctx, try atoms.intern("fortnight"));
    try std.testing.expectError(error.Badarg, system_time_1(&m, &.{bad}));
}

/// e49-real-ports-io: `os:cmd/1` — an os.erl LIBRARY wrapper (it wraps
/// open_port in OTP), expanded here over the SAME proven live-port seam the
/// port BIFs use (fork+exec /bin/sh -c). Traps to the Vm (the port table +
/// reaping live there); the result is the command's stdout-to-EOF as a
/// charlist — the os:cmd contract (exit status ignored; stderr not captured).
pub fn cmd_1(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .os_cmd = .{ .cmd = args[0] } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the charlist to x0
}

/// gap-open-port-dispatch: `os:cmd/2` — `os:cmd(Cmd, Options)`. `Options` is a
/// map (OTP-30: `#{max_size => N}` bounds the captured output). SCOPE (Slice A):
/// the map is VALIDATED (a non-map is `badarg`, matching the os.erl guard) then
/// the command runs over the SAME live-port seam as `cmd_1` — `max_size` bounding
/// is the documented remainder (the seam already caps at 1 MiB). A basic
/// `os:cmd(C, #{})` is byte-EQ to `os:cmd(C)`.
pub fn cmd_2(m: *Machine, args: []const Term) BifError!Term {
    if (FinalTerms.kindOf(&m.ctx, args[1]) != .map) return error.Badarg;
    m.pending = .{ .os_cmd = .{ .cmd = args[0] } };
    return FinalTerms.nil(&m.ctx);
}

// gap-os-signals: `os:set_signal/2` — the signal-disposition ACCEPT/REJECT
// grammar. The pinned OTP-30 oracle accepts a FIXED set of catchable signals ×
// {default,handle,ignore} with `ok`, and rejects everything else with `badarg`
// (probed vs the pin): `sigint` is ALWAYS badarg (reserved for the break
// handler), as are the uncatchable signals (sigkill/sigstop-family beyond this
// set), unknown signal atoms, non-atom args, and unknown options. THIS grammar
// is a real differential twin — contrary to the historical "no differential
// twin" note. SCOPE (EQUIV first increment): the grammar + validity is proven
// byte-EQ; the disposition EFFECT (recording the handler + real OS sigaction
// delivery → the erl_signal_server message / graceful init:stop) is the
// Stratum-C remainder. A valid call returns `ok` (the disposition would be
// recorded); an invalid one is `badarg` — never a wrong ok.
const catchable_signals = [_][]const u8{
    "sighup",  "sigterm", "sigusr1", "sigusr2", "sigquit",
    "sigabrt", "sigalrm", "sigchld", "sigstop", "sigtstp",
};
const signal_options = [_][]const u8{ "default", "handle", "ignore" };
pub fn set_signal_2(m: *Machine, args: []const Term) BifError!Term {
    // both args must be atoms (a non-atom signal or option is badarg).
    if (!FinalTerms.repIsAtom(args[0]) or !FinalTerms.repIsAtom(args[1])) return error.Badarg;
    const sig = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    const opt = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[1]));
    var sig_ok = false;
    for (catchable_signals) |vs| {
        if (std.mem.eql(u8, sig, vs)) sig_ok = true;
    }
    var opt_ok = false;
    for (signal_options) |vo| {
        if (std.mem.eql(u8, opt, vo)) opt_ok = true;
    }
    // sigint is excluded from catchable_signals ⇒ always badarg (the break
    // handler reservation), as is any unknown signal / unknown option.
    if (!sig_ok or !opt_ok) return error.Badarg;
    // gap-os-signals-sigaction (DIVERGENCE 628): apply the REAL OS disposition
    // for default/ignore (SIG_DFL/SIG_IGN). GUARDED out of TEST builds — the
    // grammar law drives EVERY catchable signal (sigchld/sigabrt/sigterm),
    // and mutating the TEST process's signal state would break os:cmd's waitpid
    // + the panic handler. Production `zigvm run` gets the real effect; the
    // dedicated LAW proves the helper on the benign SIGUSR1 with save/restore.
    // `handle` (→ erl_signal_server notify) stays the documented remainder.
    if (comptime !@import("builtin").is_test) applySignalDisposition(sig, opt) catch {};
    return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("ok") catch return error.OutOfMemory);
}

/// gap-os-signals-sigaction: map a catchable-signal NAME → its signal number,
/// or null for an uncatchable one (sigstop/sigkill can't be sigaction'd → the
/// grammar accepts them but the OS won't honor a disposition — a no-op here).
pub fn signalNumber(name: []const u8) ?std.posix.SIG {
    const S = std.posix.SIG;
    const map = [_]struct { n: []const u8, v: std.posix.SIG }{
        .{ .n = "sighup", .v = S.HUP },   .{ .n = "sigterm", .v = S.TERM },
        .{ .n = "sigusr1", .v = S.USR1 }, .{ .n = "sigusr2", .v = S.USR2 },
        .{ .n = "sigquit", .v = S.QUIT }, .{ .n = "sigabrt", .v = S.ABRT },
        .{ .n = "sigalrm", .v = S.ALRM }, .{ .n = "sigchld", .v = S.CHLD },
        .{ .n = "sigtstp", .v = S.TSTP },
        // sigstop is UNCATCHABLE (SIGSTOP can't be caught/ignored) → null.
    };
    for (map) |e| if (std.mem.eql(u8, name, e.n)) return e.v;
    return null;
}

/// gap-os-signals-sigaction (DIVERGENCE 628): the REAL Stratum-C effect — a
/// genuine `sigaction(2)` for `default` (SIG_DFL) / `ignore` (SIG_IGN). `handle`
/// is a no-op here (the erl_signal_server notify pipeline is the remainder);
/// an uncatchable signal (sigstop) is a no-op (the OS rejects it). The disposition
/// is verifiable by querying it back (the LAW does exactly that).
pub fn applySignalDisposition(sig_name: []const u8, opt: []const u8) !void {
    const num = signalNumber(sig_name) orelse return; // uncatchable → no-op
    const P = std.posix;
    // gap-os-signals-delivery: `handle` installs a REAL handler that records the
    // signal for the scheduler to deliver. See `pending_signals`.
    if (std.mem.eql(u8, opt, "handle")) {
        // SA.RESTART so a signal arriving during a blocking syscall does not
        // turn into a spurious EINTR the rest of the VM would have to handle.
        var act = P.Sigaction{
            .handler = .{ .handler = onCatchableSignal },
            .mask = P.sigemptyset(),
            .flags = P.SA.RESTART,
        };
        P.sigaction(num, &act, null);
        return;
    }
    const handler = if (std.mem.eql(u8, opt, "ignore"))
        P.SIG.IGN
    else if (std.mem.eql(u8, opt, "default"))
        P.SIG.DFL
    else
        return; // an unknown option is rejected by set_signal_2 before reaching here
    var act = P.Sigaction{ .handler = .{ .handler = handler }, .mask = P.sigemptyset(), .flags = 0 };
    P.sigaction(num, &act, null);
}

/// gap-os-signals-delivery: signals raised since the scheduler last drained,
/// one bit per entry of `catchable_signals`.
///
/// A BITMASK, not a queue, and not a pipe. A signal handler may call only
/// async-signal-safe operations — no allocation, no lock, no formatting — and a
/// single relaxed atomic OR is the smallest thing that satisfies that while
/// still being observable from the scheduler. The cost is honest and disclosed:
/// N occurrences of the SAME signal between two drains coalesce into one
/// delivery. That is also what the OS itself does to non-realtime signals, so
/// the coalescing is inherited rather than introduced.
pub var pending_signals: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

/// The installed handler. Async-signal-safe by construction: one atomic
/// read-modify-write and nothing else. It must never allocate, take a lock, or
/// touch the VM — the scheduler does all of that later, on its own thread.
fn onCatchableSignal(sig: std.posix.SIG) callconv(.c) void {
    inline for (catchable_signals, 0..) |name, i| {
        if (signalNumber(name)) |n| {
            if (n == sig) {
                _ = pending_signals.fetchOr(@as(u32, 1) << @intCast(i), .monotonic);
                return;
            }
        }
    }
}

/// Drain the pending set, returning the bits that were set. Called by the
/// scheduler tick; the swap makes the drain atomic against a concurrent handler.
pub fn drainPendingSignals() u32 {
    return pending_signals.swap(0, .monotonic);
}

/// The name of bit `i` of the pending mask.
pub fn pendingSignalName(i: usize) []const u8 {
    return catchable_signals[i];
}

pub const pending_signal_count = catchable_signals.len;
