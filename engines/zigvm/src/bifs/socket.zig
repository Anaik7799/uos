//! # bifs/socket — gen_tcp / inet name-dispatch (gap-socket-real-tcp)
//!
//! The erlang-level `gen_tcp:*` / `inet:*` NAME-DISPATCH — the EQ remainder the
//! `gen_tcp_udp_sockets` capability named. The real transport + fd + socket table +
//! `{ok,Socket}`/`{error,Posix}` term shapes already live in `proc.zig`
//! (`doGenTcpListen`/`doInetPort`/`doGenTcpClose` over `socket_algebra`, Stratum C).
//! What was missing is the bridge from COMPILED erlang: a Cowboy/Ranch beam calling
//! `gen_tcp:listen(Port, Opts)` must REACH those handlers.
//!
//! Each BifFn here mirrors the `io:put_chars` precedent (`bifs/io.zig`): it sets a
//! `socket_op` pending carrying the op tag + its argument and returns a placeholder;
//! the Vm interpret loop (`proc.zig`) routes the pending to the matching handler and
//! overwrites x0 with the real `{ok,_}`/`{error,_}` result. These are resolved by
//! `dispatch.resolveLibrary` (ledger-invisible, the `spawn_monitor`/`io:put_chars`
//! precedent — a library wrapper, not a `bif.tab` row).
//!
//! This first wave carries the single-arg lifecycle verbs (listen/inet:port/close);
//! the two-arg verbs (accept/connect/send/recv) + active-mode `{tcp,S,Data}`
//! delivery are the M0-completion wave.

const std = @import("std");
const ta = @import("../term_algebra.zig");
const ia = @import("../instr_algebra.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

/// Trap a two-arg socket op into the Vm. Returns a placeholder (`undefined` atom);
/// the Vm overwrites x0 with the handler's real result term.
fn trap2(m: *Machine, op: ia.SocketOp, arg: Term, arg2: Term) BifError!Term {
    return trap3(m, op, arg, arg2, FinalTerms.nil(&m.ctx));
}

/// Trap a three-arg op. Only `gen_udp:send(Socket,_Addr,Port,Data)` uses `arg3`
/// (the Data payload); every other verb leaves it `nil`.
fn trap3(m: *Machine, op: ia.SocketOp, arg: Term, arg2: Term, arg3: Term) BifError!Term {
    m.pending = .{ .socket_op = .{ .op = op, .arg = arg, .arg2 = arg2, .arg3 = arg3 } };
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("undefined"));
}

/// Trap a single-arg op (the second/third slots are `nil`, ignored by the handler).
fn trap1(m: *Machine, op: ia.SocketOp, arg: Term) BifError!Term {
    return trap2(m, op, arg, FinalTerms.nil(&m.ctx));
}

/// `gen_tcp:listen(Port, Opts)` → `{ok, ListenSocket}` | `{error, Posix}`. Port
/// (arg 0) selects the bound port (0 → ephemeral); Opts render only the OTP shape.
pub fn gen_tcp_listen_2(m: *Machine, args: []const Term) BifError!Term {
    return trap2(m, .listen, args[0], args[1]); // arg2 = Opts (ranch carries the port in {port,N})
}

/// `inet:port(Socket)` → `{ok, Port}` | `{error, Posix}`.
pub fn inet_port_1(m: *Machine, args: []const Term) BifError!Term {
    return trap1(m, .inet_port, args[0]);
}

/// `gen_tcp:close(Socket)` → `ok` (idempotent).
pub fn gen_tcp_close_1(m: *Machine, args: []const Term) BifError!Term {
    return trap1(m, .close, args[0]);
}

/// `gen_tcp:accept(ListenSocket)` → `{ok, Socket}` | `{error, Posix}` (bounded).
pub fn gen_tcp_accept_1(m: *Machine, args: []const Term) BifError!Term {
    // gap-cowboy-trap-accept: arity-1 accept defaults to `infinity` — the handler
    // SUSPENDS (reactor) rather than blocking the drive.
    const inf = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("infinity"));
    return trap2(m, .accept, args[0], inf);
}

/// `gen_tcp:connect(Address, Port, Opts)` → `{ok, Socket}` | `{error, econnrefused}`.
/// Loopback transport: Address (arg 0) is ignored, Port is arg 1.
pub fn gen_tcp_connect_3(m: *Machine, args: []const Term) BifError!Term {
    return trap1(m, .connect, args[1]);
}

/// `gen_tcp:send(Socket, Data)` → `ok` | `{error, closed}`. Data is iodata (arg 1).
pub fn gen_tcp_send_2(m: *Machine, args: []const Term) BifError!Term {
    return trap2(m, .send, args[0], args[1]);
}

/// `gen_tcp:recv(Socket, Length)` → `{ok, Binary}` | `{error, closed|timeout}`.
pub fn gen_tcp_recv_2(m: *Machine, args: []const Term) BifError!Term {
    return trap2(m, .recv, args[0], args[1]);
}

/// `inet:sockname(Socket)` → `{ok, {Address, Port}}` — the bound local endpoint
/// (ranch reads it after listening).
pub fn inet_sockname_1(m: *Machine, args: []const Term) BifError!Term {
    return trap1(m, .sockname, args[0]);
}

/// `inet:peername(Socket)` → `{ok, {Address, Port}}` — the remote endpoint (ranch
/// reads it per accepted connection; loopback-modelled).
pub fn inet_peername_1(m: *Machine, args: []const Term) BifError!Term {
    return trap1(m, .peername, args[0]);
}

/// `gen_tcp:accept(ListenSocket, Timeout)` → `{ok, Socket}` | `{error, _}`. The
/// timeout is honored by the handler's own poll bound.
pub fn gen_tcp_accept_2(m: *Machine, args: []const Term) BifError!Term {
    // gap-cowboy-trap-accept: thread the caller's Timeout through — `infinity`
    // SUSPENDS (reactor); a finite Timeout is a bounded fail-closed sync accept.
    return trap2(m, .accept, args[0], args[1]);
}

/// `gen_tcp:recv(Socket, Length, Timeout)` → `{ok, Binary}` | `{error, _}`.
pub fn gen_tcp_recv_3(m: *Machine, args: []const Term) BifError!Term {
    return trap2(m, .recv, args[0], args[1]);
}

fn okAtom(m: *Machine) BifError!Term {
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("ok"));
}

/// `inet:setopts(Socket, Opts)` → `ok`. Most tuning options are fixed in zigvm's
/// socket model (accepted+ignored), BUT `{active, once|true}` arms the SCHEDULER to
/// deliver `{tcp,Socket,Data}` to the caller — cowboy_http drives its request loop
/// this way. Traps so the Vm can set the socket's active mode + owner (non-blocking;
/// the actual poll+deliver is scheduler-driven, never synchronous here).
pub fn inet_setopts_2(m: *Machine, args: []const Term) BifError!Term {
    return trap2(m, .setopts, args[0], args[1]);
}

/// gap-socket-gen-tcp-bifs: `inet:getopts(Socket, OptNames)` → `{ok, [{Opt,Val}]}`.
/// The read-back complement of setopts/2. zigvm answers the `active` option from
/// the socket's recorded state (truthful); options it does not model are OMITTED
/// (never a fabricated value — FM-OBS-1). Traps so the Vm reads the socket table.
pub fn inet_getopts_2(m: *Machine, args: []const Term) BifError!Term {
    return trap2(m, .getopts, args[0], args[1]);
}

/// `gen_tcp:controlling_process(Socket, Pid)` → `ok`. Sockets live in the Vm table
/// (not per-process owned), so transferring control is a no-op (ok).
pub fn gen_tcp_controlling_process_2(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return okAtom(m);
}

/// gap-socket-gen-tcp-bifs: `gen_tcp:shutdown(Socket, How)` → `ok` | `{error, _}`.
/// How ∈ {read, write, read_write}; `write` sends the peer an orderly EOF once its
/// buffered data drains (the graceful half-close). Traps so the Vm resolves the
/// socket table + drives the real `shutdown(2)` syscall.
pub fn gen_tcp_shutdown_2(m: *Machine, args: []const Term) BifError!Term {
    return trap2(m, .shutdown, args[0], args[1]);
}

// ── gen_udp:* name-dispatch (gap-socket-udp-dispatch) ────────────────────────
// The datagram transport the `gen_tcp_udp_sockets` capability names. The real
// handlers (`doGenUdpOpen`/`doGenUdpSend`/`doGenUdpRecv` over `socket_algebra`)
// already exist; this is the missing bridge from COMPILED erlang, mirroring the
// gen_tcp verbs above.

/// `gen_udp:open(Port)` → `{ok, Socket}`. Port (arg 0) selects the bind port
/// (0 → ephemeral, read back via `inet:port/1`); the handler binds loopback.
pub fn gen_udp_open_1(m: *Machine, args: []const Term) BifError!Term {
    return trap1(m, .udp_open, args[0]);
}

/// `gen_udp:open(Port, Opts)` → `{ok, Socket}`. Opts render only the OTP shape.
pub fn gen_udp_open_2(m: *Machine, args: []const Term) BifError!Term {
    return trap1(m, .udp_open, args[0]);
}

/// `gen_udp:send(Socket, Address, Port, Data)` → `ok` | `{error, Posix}`.
/// Loopback transport: Address (arg 1) is ignored; Socket=arg0, Port=arg2,
/// Data=arg3 (carried in the pending's third slot).
pub fn gen_udp_send_4(m: *Machine, args: []const Term) BifError!Term {
    return trap3(m, .udp_send, args[0], args[2], args[3]);
}

/// `gen_udp:recv(Socket, Length)` → `{ok, {Address, Port, Packet}}` (passive).
pub fn gen_udp_recv_2(m: *Machine, args: []const Term) BifError!Term {
    return trap1(m, .udp_recv, args[0]);
}

/// `gen_udp:recv(Socket, Length, Timeout)` → `{ok, {Address, Port, Packet}}`.
pub fn gen_udp_recv_3(m: *Machine, args: []const Term) BifError!Term {
    return trap1(m, .udp_recv, args[0]);
}
