//! beam-zig E5.4 / S25: **the port BIF surface** — the `erts_internal:*` /
//! `erlang:*` spawn-port primitives, wired end-to-end to the LIVE os-port driver
//! (`src/os_port.zig`, Stratum C) via the E4.5 port ENDPOINT algebra.
//!
//! ## Scope / ledger honesty
//! Five rows flip EQ here — the ones a compiled `.beam` can drive AND observe
//! end-to-end against the OTP oracle (both VMs spawn the SAME OS program):
//!   `erts_internal:open_port/2`  → a live child (`{spawn,Cmd}`) → a Port term
//!   `erts_internal:port_command/3` → write bytes; `{Port,{data,Echo}}` to owner
//!   `erts_internal:port_close/1`  → reap the child; `true`
//!   `erlang:port_set_data/2`      → store an opaque term on the port; `true`
//!   `erlang:port_get_data/1`      → read it back
//! Each is REPRESENTATION-SAFE in a differential: the Port VALUE is never printed
//! (bound as `P`, matched structurally); the observable results are `true` / an
//! echoed binary / the stored term — byte-identical on both VMs.
//!
//! E6.7 (Task 7): the remaining SIX port rows FLIP EQ (deferred-E6-portrepr
//! EMPTIED — DIVERGENCE 124). The port table is Vm-SHARED, so representation-FREE
//! / rejection differentials flip them end-to-end (the `port_verbs`/`port_conn`
//! corpus; proc.zig `doPortsList`/`doPortInfo`/`doPortConnect`):
//!   `erlang:ports/0`          → SET-membership `lists:member(P, ports())`
//!   `erts_internal:port_info/1,2` → `{name,"cat"}` (a repr-free STRING) /
//!       `connected =:= self()` / `id` is_integer / `undefined` on a dead port
//!   `erts_internal:port_call/3` + `port_control/3` → the RAW primitives RETURN
//!       the atom `badarg` (a `{spawn,Cmd}` port has no control-verb driver — the
//!       rejection differential; no false driver invented). NB the `erlang:`
//!       wrappers RAISE `error:badarg`; the erts_internal primitives RETURN it.
//!   `erts_internal:port_connect/2` → reassign the connected pid, observed via
//!       `port_info(P,connected) =:= Pid`.
//!
//! ## The trap mechanism
//! Each BIF needs the Vm's port table (a bare Machine cannot reach it — exactly
//! like `spawn`/`registered`), so it sets `m.pending = <ia.Action>` and returns a
//! placeholder; `proc.zig`'s `interpret` performs the effect (spawn/write/reap/
//! store/load) and writes the result to x0 (the BEAM call-return convention).

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

/// `erts_internal:open_port/2` — open a port on a live external program.
/// `args[0]` is the PortName (`{spawn, Cmd}`), `args[1]` the option list. Traps
/// `open_port_spawn`; the Vm spawns the child and writes the Port term to x0.
pub fn open_port_2(m: *Machine, args: []const Term) BifError!Term {
    // gap-open-port-dispatch (DIVERGENCE 594): scan the OPTION LIST (args[1]) for
    // the data-mode atoms — `binary` selects binary delivery, `list` (the OTP
    // DEFAULT) selects charlist. Slice A threads ONLY the mode (the option that
    // changes {Port,{data,_}}'s shape); `exit_status`/`{line,N}`/`stderr_to_stdout`
    // are later slices. A total walk of the proper list; a non-atom/other option is
    // skipped (not rejected — matching the permissive erts settings parse for the
    // subset we model).
    const binary_atom = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("binary"));
    const list_atom = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("list"));
    // gap-open-port-exit-status (Slice B): the `exit_status` option arms delivery
    // of a `{Port,{exit_status,Code}}` message when the child exits on its OWN.
    const exit_status_atom = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("exit_status"));
    const line_atom = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("line"));
    // gap-open-port-stderr (Slice D): `stderr_to_stdout` merges the child's stderr
    // into the port's data stream (fd2→fd1 dup at spawn).
    const stderr_atom = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("stderr_to_stdout"));
    var binary_mode = false;
    var exit_status = false;
    var stderr_to_stdout = false;
    var line_width: usize = 0; // 0 == not line-mode; else the {line,N} cap
    var cur = args[1];
    var fuel: usize = 0;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons and fuel < 4096) : (fuel += 1) {
        const head = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.eqlExact(&m.ctx, head, binary_atom)) binary_mode = true;
        if (FinalTerms.eqlExact(&m.ctx, head, list_atom)) binary_mode = false;
        if (FinalTerms.eqlExact(&m.ctx, head, exit_status_atom)) exit_status = true;
        if (FinalTerms.eqlExact(&m.ctx, head, stderr_atom)) stderr_to_stdout = true;
        // gap-open-port-line (Slice C): `{line, N}` — a 2-tuple option {atom line, int N}.
        if (FinalTerms.kindOf(&m.ctx, head) == .tuple and FinalTerms.tupleArity(&m.ctx, head) == 2 and
            FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, head, 0), line_atom))
        {
            const nt = FinalTerms.tupleElem(&m.ctx, head, 1);
            if (FinalTerms.repIsSmall(nt)) {
                const nv = FinalTerms.smallValOf(nt);
                if (nv > 0) line_width = @intCast(nv);
            }
        }
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    m.pending = .{ .open_port_spawn = .{ .name = args[0], .binary_mode = binary_mode, .exit_status = exit_status, .line_width = line_width, .stderr_to_stdout = stderr_to_stdout } };
    return FinalTerms.nil(&m.ctx); // placeholder; the Vm writes the Port to x0
}

/// `erts_internal:port_command/3` — send `args[1]` (a binary/iodata) to the port
/// `args[0]`; the echo driver replies `{Port,{data,Bytes}}` to the port's owner.
/// Returns `true`. Traps `port_cmd`.
pub fn port_command_3(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .port_cmd = .{ .port = args[0], .data = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// `erlang:port_command/2` — the auto-imported 2-arg form `port_command(Port,
/// Data)` (the common case; the /3 form adds `[force|nosuspend]` options that
/// do not change the byte effect of the send). Same `port_cmd` trap as /3.
/// gap-open-port-dispatch: the AUTO-IMPORTED `erlang:` name — before this, a
/// compiled `port_command(P, D)` (arity 2) missed both resolve tables (only
/// `erts_internal:port_command/3` was wired, under the DEAD `implOf` path) → undef.
pub fn port_command_2(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .port_cmd = .{ .port = args[0], .data = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// `erts_internal:port_close/1` — retire the port, reaping its child. Returns
/// `true`. Traps `port_close_sig`.
pub fn port_close_1(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .port_close_sig = .{ .port = args[0] } };
    return FinalTerms.nil(&m.ctx);
}

/// `erlang:port_set_data/2` — store an opaque term on the port. Returns `true`.
/// Traps `port_set_data`.
pub fn port_set_data_2(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .port_set_data = .{ .port = args[0], .data = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// `erlang:port_get_data/1` — read back the stored term (`undefined` if unset).
/// Traps `port_get_data`.
pub fn port_get_data_1(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .port_get_data = .{ .port = args[0] } };
    return FinalTerms.nil(&m.ctx);
}

// ── E6.7 (Task 7): the port-representation surface (deferred-E6-portrepr) ────

/// `erlang:ports/0` — the list of all live ports. Traps `ports_list`; the Vm
/// builds the port-term list (the E4.2 registered/0 SET-membership precedent —
/// a caller observes it by `lists:member(P, ports())`, never a raw list VALUE).
pub fn ports_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .{ .ports_list = .{} };
    return FinalTerms.nil(&m.ctx);
}

/// `erlang:port_info/1` — the port's info proplist (`[{name,_},{id,_},
/// {connected,_},…]`), or `undefined` for a dead/absent port. Traps `port_info`
/// with an `nil` item sentinel.
pub fn port_info_1(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .port_info = .{ .port = args[0], .item = FinalTerms.nil(&m.ctx) } };
    return FinalTerms.nil(&m.ctx);
}

/// `erlang:port_info/2` — a single info item `{Item,Value}` (e.g. `{name,"cat"}`,
/// `{connected,Pid}`, `{id,Int}`), or `undefined` for a dead/absent port. Traps
/// `port_info`.
pub fn port_info_2(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .port_info = .{ .port = args[0], .item = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// `erts_internal:port_call/3` — a driver control CALL. The RAW erts_internal
/// primitive RETURNS the atom `badarg` (a VALUE, not a raised exception — unlike
/// the `erlang:port_call/3` wrapper which raises `error:badarg`) when the port's
/// driver has no `call` entry. An external-program (`{spawn,Cmd}`) port carries
/// no such driver, so both erts and zigvm answer the atom `badarg` (the rejection
/// differential — no false driver invented). No trap needed.
pub fn port_call_3(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("badarg"));
}

/// `erts_internal:port_control/3` — a driver control operation. Same rejection
/// differential as `port_call/3`: `{spawn,Cmd}` ports have no control-verb
/// driver, so the raw primitive RETURNS the atom `badarg` on both VMs.
pub fn port_control_3(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("badarg"));
}

/// `erts_internal:port_connect/2` — reassign the port's connected (owner)
/// process to `args[1]`. Returns `true`; `badarg` on a bad/absent port or a
/// non-live-pid target. Traps `port_connect_sig` (needs the Vm's port table +
/// pid liveness). Observed representation-free via `port_info(P,connected) =:= Pid`.
pub fn port_connect_2(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .port_connect_sig = .{ .port = args[0], .pid = args[1] } };
    return FinalTerms.nil(&m.ctx);
}
