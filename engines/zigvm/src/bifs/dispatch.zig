//! # bifs/dispatch — the SINGLE BIF resolver over the generated table (E2.2/E2.4)
//!
//! ## Signature
//!   resolve : (module, name, arity) -> ?BifFn
//!
//! ## Semantic domain
//! One total function from an `M:F/A` key to "does the VM execute this BIF, and
//! if so, VIA WHICH family fn". Its codomain is `?ia.BifFn` (a function pointer
//! into `bifs/erlang.zig`, …):
//!   - `some(fn)` — the generated `bif_table` classifies this exact
//!     `module:name/arity` as `.implemented` AND `implOf` has an executable
//!     family fn for it;
//!   - `null` — every other key: a `.stub`/`.justified` table entry, or a key
//!     the table does not carry at all. The CALLER traps `undef` at RUNTIME for
//!     these (BEAM-faithful — a module LOADS and only errors when the BIF is
//!     actually called), never a loader reject.
//!
//! ## Why a function pointer (E2.4 — the scalable dispatch)
//! E2.2 resolved to a tiny `BifOp{add,sub}` enum the executor switched on. That
//! did NOT scale past two BIFs. E2.4 replaced it with `ia.BifFn` — a pointer to a
//! hand-written family fn `(m, args) BifError!Term`. `implOf` is the ONE place a
//! `.implemented` table key is mapped to its fn; the `bif_call` executor calls
//! the pointer through a single uniform arm. Every later family task (E2.5+) adds
//! `pub fn`s to a family module and arms to `implOf` — never an executor edit,
//! never a giant enum. The resolver stays arity- AND module-precise (keyed on the
//! full triple) and TOTAL (every key maps to `some`/`null`, never crashes).
//!
//! ## Relation to `ia.supported_bifs`
//! `ia.supported_bifs` is the ADVERTISED ledger (dump-caps / harness bif EQ
//! rows). `resolve` is the loader-time RESOLVER over the generated `bif_table`
//! (the pinned OTP BIF universe). The two agree BY CONSTRUCTION — the
//! `.implemented` table entries are exactly `supported_bifs`, and `implOf`
//! returns a fn for each — pinned by the "resolve agrees with supported_bifs"
//! law below. A future coverage slice extends BOTH plus `implOf`.
//!
//! e21-t2b (DIVERGENCE 490-amend) carves ONE precise exception: the
//! DISPATCH-NEEDED-DEFERRED set (`dispatch_needed_deferred` /
//! `resolveDispatchNeededDeferred`). These are `.justified`/ledger-DEFERRED rows
//! (`erlang:process_info/1,2`) that `resolve` STILL bakes executable so a compiled
//! OTP behaviour boot can dispatch their byte-total item subset instead of
//! trapping `undef`. They are DELIBERATELY absent from `supported_bifs` (the full
//! BIF is not byte-EQ). So the resolvable universe is exactly
//! `supported_bifs ∪ dispatch_needed_deferred`, and those two sets are DISJOINT —
//! the revised AGREES law states precisely this (not the old
//! resolvable ⟺ supported_bifs).
//!
//! ## Laws (see below + instr_algebra / beam_loader suites)
//!   - EXECUTABLE:  resolve("erlang","element",2) == &erlang.element, etc.
//!   - ARITY-PRECISE:  `-`/1 and `-`/2 map to distinct fns; an absent arity
//!     (`erlang:element/1`) → null.
//!   - MODULE-PRECISE: resolve("lists","+",2) == null
//!   - DISPATCH-NEEDED-DEFERRED: resolve("erlang","process_info",2) is non-null
//!     (executable) YET absent from supported_bifs (ledger-deferred).
//!   - TOTAL: never crashes; every key maps to `some`/`null`.
//!   - AGREES: every `supported_bifs` entry resolves to a non-null fn; every
//!     resolvable key is in `supported_bifs` XOR in `dispatch_needed_deferred`;
//!     the two sets are disjoint.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const erlang = @import("erlang.zig");
const conv = @import("conv.zig");
const lists = @import("lists.zig");
const maps = @import("maps.zig");
const binary = @import("binary.zig");
const ets = @import("ets.zig");
const math = @import("math.zig");
const persistent_term = @import("persistent_term.zig");
const atomics = @import("atomics.zig");
const counters = @import("counters.zig");
const procsys = @import("procsys.zig");
const trace_bifs = @import("trace_bifs.zig");
const pdict = @import("pdict.zig");
const term_ops = @import("term_ops.zig");
const code_bifs = @import("code.zig");
const fun_info = @import("fun_info.zig");
const unicode_bifs = @import("unicode.zig");
const checksum = @import("checksum.zig");
const socket = @import("socket.zig"); // gap-socket-real-tcp: gen_tcp/inet name-dispatch
const application = @import("application.zig"); // gap-app-boot-engine: application:get_env intercept
const file_bifs = @import("file.zig");
const misc = @import("misc.zig");
const dist_ctrl = @import("dist_ctrl.zig");
const io = @import("io.zig");
const records = @import("records.zig");
const re_bifs = @import("re.zig");
const ports = @import("ports.zig"); // E5.4: the live os-port surface
const time_bifs = @import("time.zig"); // E5.8b: erlang: monotonic/system time family
const os_bifs = @import("os.zig"); // E5.8b: the os: module family
const bif_table = @import("bif_table.zig");

/// The executable family fn a resolved (`.implemented`) BIF runs as.
pub const BifFn = ia.BifFn;

/// Resolve an `M:F/A` key to its family fn, or `null` if the VM does not execute
/// it. `null` is the caller's cue to trap `undef` at runtime. Keyed on the FULL
/// triple: a same-named BIF at a different arity or module never aliases.
pub fn resolve(module: []const u8, name: []const u8, arity: u8) ?BifFn {
    // e21-t2b (DIVERGENCE 490-amend): the DISPATCH-NEEDED-DEFERRED set. A tiny,
    // explicitly-enumerated group of BIFs whose bif.tab row is `.justified`
    // (ledger-DEFERRED — the FULL BIF is not observationally byte-EQ to erts, so
    // it must NOT advertise EQ in supported_bifs) yet whose IMPLEMENTED item
    // subset is genuinely needed for a COMPILED beam to dispatch — otherwise the
    // call resolves `undef` and a real OTP behaviour boot cannot proceed.
    // `erlang:process_info/1,2` is the first member: its documented, byte-total
    // items (`registered_name` → `[]` for an unregistered self, the item
    // `proc_lib:proc_info/2` reads on the `gen_server` boot path) ARE correct;
    // its FULL default list + pid-VALUE items stay the honest residual (ledger row
    // UNMOVED, `deferred-procinfo-full`). Resolving it here bakes a `call_ext_bif`
    // that runs the real impl instead of trapping `undef`. This is the SOLE way a
    // `.justified` row becomes resolvable — kept a closed, named list so the
    // "resolve AGREES with supported_bifs" law (§ below) can carve it out exactly:
    // resolvable = supported_bifs ∪ dispatch_needed_deferred, DISJOINT sets.
    if (resolveDispatchNeededDeferred(module, name, arity)) |f| return f;
    for (bif_table.entries) |e| {
        if (e.arity != arity) continue;
        if (!std.mem.eql(u8, e.module, module)) continue;
        if (!std.mem.eql(u8, e.name, name)) continue;
        // The table knows this key. Only `.implemented` entries are executable;
        // `.stub`/`.justified` fall through to `undef` at runtime.
        if (e.class != .implemented) return null;
        return implOf(module, name, arity);
    }
    return null;
}

/// gap-dynamic-native-dispatch (DIVERGENCE 650): resolve a NATIVE bif for a
/// RUNTIME `M:F/A` dispatch (`apply/2,3`, `Mod:Var(...)`, a code-miss retry) —
/// the union `resolve ∪ resolveLibrary` a STATIC `call_ext` already sees at load
/// time. Injected into the Machine as `native_bif_resolver` so `dispatchMFACore`
/// can serve a dynamic call to a wired wrapper (io/logger/gen_tcp/file/…) instead
/// of trapping `undef`. Consulted ONLY after a loaded beam misses AND autoload has
/// been tried, so real code always wins (new-code-wins) and this is a pure
/// fallback above `error_handler`/undef. Fixes the FM-DISPATCH-DEAD-via-apply
/// class: ranch's `error_logger:Function(Fmt,Args)` (a dynamic crash-report call)
/// was `undef`, crashing a trapping supervisor mid-recovery → the M3 cascade.
pub fn resolveDynamic(module: []const u8, name: []const u8, arity: u8) ?BifFn {
    return resolve(module, name, arity) orelse resolveLibrary(module, name, arity);
}

/// e21-t2b (DIVERGENCE 490-amend): the DISPATCH-NEEDED-DEFERRED allow-list — the
/// closed set of `.justified`/ledger-deferred bif.tab rows that `resolve`
/// nonetheless bakes as executable `call_ext_bif`s (see `resolve`'s doc). Keyed
/// on the FULL triple. Adding a member here is a deliberate act: the row's
/// IMPLEMENTED item subset must be genuinely EQ (the part a real caller exercises)
/// while the FULL BIF stays a named ledger residual. The "resolve AGREES" law
/// pins that this set is DISJOINT from `supported_bifs` (never double-counted) and
/// that every member resolves non-null.
pub fn resolveDispatchNeededDeferred(module: []const u8, name: []const u8, arity: u8) ?BifFn {
    if (!std.mem.eql(u8, module, "erlang")) return null;
    if (std.mem.eql(u8, name, "process_info")) return switch (arity) {
        1 => &procsys.process_info_1,
        2 => &procsys.process_info_2,
        else => null,
    };
    // gap-processes-0 (DIVERGENCE 651): `erlang:processes/0` is `.justified` in
    // bif.tab (its enumerated pid-VALUE list can never byte-match OTP's per-node
    // boot-set — 43 system procs with nondeterministic pid numbers + ports this
    // single-node interpreter does not model), so `resolve` misses → a compiled
    // `processes()` was `undef`, breaking any real app that introspects the process
    // table. The HANDLER is complete + TRUTHFUL (`.list_processes` → every ALIVE
    // proc as a `.pid` term). Resolve it via THIS carve-out (the process_info/1,2
    // precedent): the call RUNS + returns the honest live list; the ledger row
    // stays `.justified` (the byte-EQ enumeration is the disclosed residual).
    if (std.mem.eql(u8, name, "processes") and arity == 0) return &procsys.processes_0;
    // gap-fun-info (DIVERGENCE 652): `erlang:fun_info/2` is `.justified`
    // (deferred-funmeta: a local closure's module/name + every fun's
    // uniq/index/pid need compile metadata this fun term does not carry), so a
    // compiled `fun_info(F, arity)` was `undef`. The handler is byte-EQ for the
    // deterministic items — arity/type/env (both kinds) + module/name (external
    // funs). Resolve it via the carve-out (processes/0 precedent): the common
    // introspection items RUN byte-EQ; the residual items stay a clean badarg;
    // the ledger row stays `.justified`.
    if (std.mem.eql(u8, name, "fun_info") and arity == 2) return &fun_info.fun_info_2;
    // gap-fun-info-mfa (DIVERGENCE 727): `erlang:fun_info_mfa/1` stays `.justified`
    // (deferred-funmeta residual = cross-process/synthetic closures whose creating
    // make_fun3 did not run in THIS process) yet its common case — an external fun, or
    // a local closure created in this process — now returns byte-EQ {Module, Name,
    // Arity} from the make_fun3-populated `Machine.fun_meta`. Resolve via the same
    // carve-out so a compiled `fun_info_mfa/1` RUNS instead of undef-ing.
    if (std.mem.eql(u8, name, "fun_info_mfa") and arity == 1) return &fun_info.fun_info_mfa_1;
    // E42-T1: decode_packet/3 GRADUATED to a full `.implemented` capability (all
    // types byte-EQ) — it now resolves via the normal erlang implOf, not this
    // carve-out.
    return null;
}

/// The dispatch-needed-deferred keys, for the law suite (mirrors the function
/// above — the law asserts the function and this list agree, and that each key is
/// `.justified` in bif_table and ABSENT from supported_bifs).
pub const dispatch_needed_deferred = [_]struct { module: []const u8, name: []const u8, arity: u8 }{
    .{ .module = "erlang", .name = "process_info", .arity = 1 },
    .{ .module = "erlang", .name = "process_info", .arity = 2 },
    // gap-processes-0 (DIVERGENCE 651): `.justified` (pid-VALUE list ≠ OTP boot-set)
    // yet its IMPLEMENTED item (the truthful live pid list) is needed so a compiled
    // `erlang:processes()` runs instead of undef-ing.
    .{ .module = "erlang", .name = "processes", .arity = 0 },
    // gap-fun-info (DIVERGENCE 652): `.justified` (deferred-funmeta) yet its
    // deterministic items (arity/type/env + external module/name) are byte-EQ and
    // needed so a compiled `fun_info(F, Item)` runs instead of undef-ing.
    .{ .module = "erlang", .name = "fun_info", .arity = 2 },
    // gap-fun-info-mfa (DIVERGENCE 727): `.justified` (deferred-funmeta residual) yet
    // its common case is byte-EQ and needed so a compiled `fun_info_mfa/1` runs.
    .{ .module = "erlang", .name = "fun_info_mfa", .arity = 1 },
    // E42-T1: decode_packet/3 graduated to `.implemented` (all types byte-EQ) — no
    // longer a carve-out member.
};

/// E5.8 (Task 8): resolve an erlang.erl LIBRARY WRAPPER the loader expands inline
/// — a function defined in Erlang (in `erlang.erl`), NOT a bif.tab BIF, so it is
/// DELIBERATELY absent from `bif_table`/`supported_bifs`/the harness ledger (the
/// `erlang:apply/3` precedent — the loader also special-cases apply). We emulate
/// the wrapper directly because `erlang.erl` is not loaded on this VM.
/// `spawn_monitor(M,F,A) == spawn_opt(M,F,A,[monitor])` and `spawn_monitor(F) ==
/// spawn_opt(erlang,apply,[F,[]],[monitor])` — both return `{Pid, Ref}`. This is
/// consulted AFTER `resolve` misses, so it never shadows a real BIF, and it does
/// NOT participate in the "resolve AGREES with supported_bifs" law (a library fn
/// is not a capability). DIVERGENCE entry 50(c).
pub fn resolveLibrary(module: []const u8, name: []const u8, arity: u8) ?BifFn {
    // E5.3 (Task 3): the io OUTPUT verbs `io:put_chars/1,2` and `io:nl/0,1` are
    // STDLIB LIBRARY functions (defined in io.erl, NOT bif.tab rows), so like
    // spawn_monitor they are ABSENT from `bif_table`/`supported_bifs`/the ledger
    // — but each is a thin wrapper that ultimately drives the E4.6 group-leader
    // request protocol (`{io_request, From, ReplyAs, {put_chars, unicode, Chars}}`)
    // that `bifs/io.zig` + `proc.zig` already implement and law-prove. We expand
    // them inline (the `apply/3`/spawn_monitor precedent) so `io:put_chars` from
    // a COMPILED beam resolves to the protocol instead of trapping `undef` —
    // discharging DIVERGENCE 49 blocker (2) / the `u_io_put_chars` suite residual
    // (entry 50(d)). This is consulted AFTER `resolve` misses, never shadows a
    // real BIF, and does NOT participate in the "resolve AGREES with
    // supported_bifs" law (a library wrapper is not a capability).
    if (std.mem.eql(u8, module, "io")) {
        if (std.mem.eql(u8, name, "put_chars")) return switch (arity) {
            1 => &io.put_chars_1,
            2 => &io.put_chars_2,
            else => null,
        };
        if (std.mem.eql(u8, name, "nl")) return switch (arity) {
            0 => &io.nl_0,
            1 => &io.nl_1,
            else => null,
        };
        // gap-io-format: io:format/1,2,3 (renders via io_format, byte-EQ with
        // io_lib:format, then put_chars to the group leader).
        if (std.mem.eql(u8, name, "format") or std.mem.eql(u8, name, "fwrite")) return switch (arity) {
            1 => &io.format_1,
            2 => &io.format_2,
            3 => &io.format_3,
            else => null,
        };
        return null;
    }
    // gap-io-format: io_lib:format/2 — the PURE path (returns the charlist).
    if (std.mem.eql(u8, module, "io_lib") and std.mem.eql(u8, name, "format") and arity == 2)
        return &io.io_lib_format_2;
    // DIVERGENCE 715: io_lib:write_atom/1, write_string/1, write_char/1 (pure).
    if (std.mem.eql(u8, module, "io_lib") and arity == 1) {
        if (std.mem.eql(u8, name, "write_atom")) return &io.io_lib_write_atom_1;
        if (std.mem.eql(u8, name, "write_string")) return &io.io_lib_write_string_1;
        if (std.mem.eql(u8, name, "write_char")) return &io.io_lib_write_char_1;
    }
    // e47-a1: the logger-less node's logging surface — proc_lib/gen_server hit
    // these on every stock-beam start path (see the io.zig doc block; allow →
    // false is a DISCLOSED no-logger-tree bound, depth → the pinned default).
    if (std.mem.eql(u8, module, "logger")) {
        if (std.mem.eql(u8, name, "allow") and arity == 2)
            return &io.logger_allow_2;
        // gap-logger-null-sink (DIVERGENCE 742): the log API surface as a null sink
        // → `ok` (the SAME no-logger-tree bound as error_logger 650 + allow → false).
        // A DIRECT `logger:LEVEL(...)` / `logger:log(...)` in app code (a proc_lib
        // crash report, a gen_server `terminate`) would otherwise undef-KILL the
        // caller — the logging-spine FM-DISPATCH-DEAD instance. (This block is
        // DUPLICATED at the two resolveLibrary sites — keep them in lockstep.)
        if ((std.mem.eql(u8, name, "emergency") or std.mem.eql(u8, name, "alert") or
            std.mem.eql(u8, name, "critical") or std.mem.eql(u8, name, "error") or
            std.mem.eql(u8, name, "warning") or std.mem.eql(u8, name, "notice") or
            std.mem.eql(u8, name, "info") or std.mem.eql(u8, name, "debug")) and
            (arity == 1 or arity == 2 or arity == 3))
            return &io.logger_ok;
        if (std.mem.eql(u8, name, "log") and (arity == 2 or arity == 3 or arity == 4))
            return &io.logger_ok;
    }
    if (std.mem.eql(u8, module, "error_logger")) {
        if (std.mem.eql(u8, name, "get_format_depth") and arity == 0)
            return &io.error_logger_get_format_depth_0;
        // gap-error-logger-null-sink (DIVERGENCE 650): the REPORTING surface as a
        // null sink → `ok` (the logger-less node's disclosed bound). error_logger is
        // autoload-DENYLISTED (proc.zig autoloadDenied — the beam would pull the
        // logger tree the VM does not run), so these MUST resolve natively or a
        // SUPERVISOR crash-report path (ranch_conns_sup:report_error) undefs WHILE
        // handling a child crash → the trapping supervisor crashes → the M3 cascade
        // that tore down the acceptor tree. A null sink lets it contain the crash.
        if ((std.mem.eql(u8, name, "error_msg") or std.mem.eql(u8, name, "warning_msg") or
            std.mem.eql(u8, name, "info_msg") or std.mem.eql(u8, name, "error_report") or
            std.mem.eql(u8, name, "warning_report") or std.mem.eql(u8, name, "info_report")) and
            (arity == 1 or arity == 2))
            return &io.error_logger_ok;
    }
    // gap-socket-real-tcp: gen_tcp/inet name-dispatch (library wrappers, not bif.tab
    // rows) → the socket_op trap into the proc.zig handlers. First wave: the single-
    // arg lifecycle verbs (accept/connect/send/recv are the M0-completion wave).
    if (std.mem.eql(u8, module, "gen_tcp")) {
        if (std.mem.eql(u8, name, "listen") and arity == 2) return &socket.gen_tcp_listen_2;
        if (std.mem.eql(u8, name, "close") and arity == 1) return &socket.gen_tcp_close_1;
        if (std.mem.eql(u8, name, "accept") and arity == 1) return &socket.gen_tcp_accept_1;
        if (std.mem.eql(u8, name, "accept") and arity == 2) return &socket.gen_tcp_accept_2;
        if (std.mem.eql(u8, name, "connect") and arity == 3) return &socket.gen_tcp_connect_3;
        if (std.mem.eql(u8, name, "send") and arity == 2) return &socket.gen_tcp_send_2;
        if (std.mem.eql(u8, name, "recv") and arity == 2) return &socket.gen_tcp_recv_2;
        if (std.mem.eql(u8, name, "recv") and arity == 3) return &socket.gen_tcp_recv_3;
        if (std.mem.eql(u8, name, "controlling_process") and arity == 2) return &socket.gen_tcp_controlling_process_2;
        if (std.mem.eql(u8, name, "shutdown") and arity == 2) return &socket.gen_tcp_shutdown_2;
        return null;
    }
    if (std.mem.eql(u8, module, "gen_udp")) {
        // gap-socket-udp-dispatch: the datagram half of gen_tcp_udp_sockets.
        if (std.mem.eql(u8, name, "open") and arity == 1) return &socket.gen_udp_open_1;
        if (std.mem.eql(u8, name, "open") and arity == 2) return &socket.gen_udp_open_2;
        if (std.mem.eql(u8, name, "send") and arity == 4) return &socket.gen_udp_send_4;
        if (std.mem.eql(u8, name, "recv") and arity == 2) return &socket.gen_udp_recv_2;
        if (std.mem.eql(u8, name, "recv") and arity == 3) return &socket.gen_udp_recv_3;
        if (std.mem.eql(u8, name, "close") and arity == 1) return &socket.gen_tcp_close_1; // shared close
        return null;
    }
    if (std.mem.eql(u8, module, "inet")) {
        if (std.mem.eql(u8, name, "port") and arity == 1) return &socket.inet_port_1;
        if (std.mem.eql(u8, name, "sockname") and arity == 1) return &socket.inet_sockname_1;
        if (std.mem.eql(u8, name, "peername") and arity == 1) return &socket.inet_peername_1;
        if (std.mem.eql(u8, name, "setopts") and arity == 2) return &socket.inet_setopts_2;
        if (std.mem.eql(u8, name, "getopts") and arity == 2) return &socket.inet_getopts_2;
        return null;
    }
    // gap-app-boot-engine: application:get_env read-intercept (never routes to the
    // unbooted application_controller; OTP-faithful undefined/Default for an unset key).
    if (std.mem.eql(u8, module, "application") and std.mem.eql(u8, name, "get_env"))
        return switch (arity) {
            1 => &application.get_env_1,
            2 => &application.get_env_2,
            3 => &application.get_env_3,
            else => null,
        };
    if (std.mem.eql(u8, module, "code") and std.mem.eql(u8, name, "ensure_loaded") and arity == 1)
        return &application.code_ensure_loaded_1;
    // gap-hot-load-code-lib (DIVERGENCE 600): the code: hot-load LIBRARY surface —
    // the oracle-pinned two-version purge methods (code_index) made REACHABLE from a
    // compiled beam (FM-DISPATCH-DEAD: they were handler-proven but undef via dispatch).
    if (std.mem.eql(u8, module, "code") and std.mem.eql(u8, name, "purge") and arity == 1)
        return &code_bifs.purge_1;
    if (std.mem.eql(u8, module, "code") and std.mem.eql(u8, name, "soft_purge") and arity == 1)
        return &code_bifs.soft_purge_1;
    if (std.mem.eql(u8, module, "code") and std.mem.eql(u8, name, "delete") and arity == 1)
        return &code_bifs.delete_1;
    if (std.mem.eql(u8, module, "code") and std.mem.eql(u8, name, "modified_modules") and arity == 0)
        return &code_bifs.modified_modules_0;
    // gap-file-handle-io / gap-real-file-io: the file: LIBRARY surface over the proven
    // prim_file seam. THESE ARE LIBRARY WRAPPERS (file.erl -> prim_file), NOT bif.tab
    // rows, so they belong HERE — not in `implOf` (which `resolve` reaches ONLY for
    // bif.tab `.implemented` rows, AND its file arm early-returns on
    // native_name_encoding). The old placement in implOf was DEAD: a compiled
    // `file:read_file`/`open`/... resolved to NEITHER table -> call_ext_code -> undef
    // (DIVERGENCE 586 — the whole file: BIF surface was handler-tested only).
    if (std.mem.eql(u8, module, "file")) {
        if (std.mem.eql(u8, name, "read_file") and arity == 1) return &file_bifs.read_file_1;
        if (std.mem.eql(u8, name, "write_file") and arity == 2) return &file_bifs.write_file_2;
        if (std.mem.eql(u8, name, "list_dir") and arity == 1) return &file_bifs.list_dir_1;
        if (std.mem.eql(u8, name, "read_file_info") and arity == 1) return &file_bifs.read_file_info_1;
        // the live-Fd handle API over the RunFd table (gap-file-handle-io).
        if (std.mem.eql(u8, name, "open") and arity == 2) return &file_bifs.open_2;
        if (std.mem.eql(u8, name, "pread") and arity == 3) return &file_bifs.pread_3;
        if (std.mem.eql(u8, name, "pwrite") and arity == 3) return &file_bifs.pwrite_3;
        if (std.mem.eql(u8, name, "close") and arity == 1) return &file_bifs.close_1;
        // gap-file-seq-io: the sequential fd surface.
        if (std.mem.eql(u8, name, "read") and arity == 2) return &file_bifs.read_2;
        if (std.mem.eql(u8, name, "write") and arity == 2) return &file_bifs.write_2;
        if (std.mem.eql(u8, name, "position") and arity == 2) return &file_bifs.position_2;
        if (std.mem.eql(u8, name, "read_file_info") and arity == 2) return &file_bifs.read_file_info_2;
        // gap-file-fs-mutation: the filesystem-mutation surface (the FINAL file: slice).
        if (std.mem.eql(u8, name, "delete") and arity == 1) return &file_bifs.delete_1;
        if (std.mem.eql(u8, name, "rename") and arity == 2) return &file_bifs.rename_2;
        if (std.mem.eql(u8, name, "make_dir") and arity == 1) return &file_bifs.make_dir_1;
        if (std.mem.eql(u8, name, "del_dir") and arity == 1) return &file_bifs.del_dir_1;
        if (std.mem.eql(u8, name, "truncate") and arity == 1) return &file_bifs.truncate_1;
        if (std.mem.eql(u8, name, "sync") and arity == 1) return &file_bifs.sync_1;
        if (std.mem.eql(u8, name, "read_link_info") and arity == 1) return &file_bifs.read_link_info_1;
        if (std.mem.eql(u8, name, "read_link_info") and arity == 2) return &file_bifs.read_link_info_2;
        return null;
    }
    // ── DEAD-DISPATCH SWEEP (DIVERGENCE 587): these LIBRARY wrappers were in `implOf`
    // (bif.tab-only) but their (module,name,arity) is NOT a bif.tab `.implemented`
    // row (crypto: 0 rows; os:cmd/set_signal are `.justified`/absent; io_lib: 0 rows)
    // → resolve() misses → implOf never runs → a compiled call resolved to NEITHER
    // table → undef. Found by the empirical reachability sweep. Moved HERE (live). ──
    if (std.mem.eql(u8, module, "crypto")) {
        if (std.mem.eql(u8, name, "hash") and arity == 2) return &checksum.hash_2;
        if (std.mem.eql(u8, name, "mac") and arity == 4) return &checksum.mac_4;
        if (std.mem.eql(u8, name, "hmac") and arity == 3) return &checksum.hmac_3;
        if (std.mem.eql(u8, name, "hmac") and arity == 4) return &checksum.hmac_4;
        if (std.mem.eql(u8, name, "strong_rand_bytes") and arity == 1) return &checksum.strong_rand_bytes_1;
        if (std.mem.eql(u8, name, "crypto_one_time") and arity == 5) return &checksum.crypto_one_time_5;
        // gap-crypto-aes-gcm-cbc: AES-GCM AEAD (encrypt /6, encrypt-with-taglen or decrypt /7).
        if (std.mem.eql(u8, name, "crypto_one_time_aead") and arity == 6) return &checksum.crypto_one_time_aead_6;
        if (std.mem.eql(u8, name, "crypto_one_time_aead") and arity == 7) return &checksum.crypto_one_time_aead_7;
        return null;
    }
    if (std.mem.eql(u8, module, "os") and std.mem.eql(u8, name, "cmd") and arity == 1)
        return &os_bifs.cmd_1;
    // gap-open-port-dispatch: `os:cmd/2` (Cmd, Options-map) — the os.erl 2-arg
    // wrapper. Unwired before (only cmd_1 existed) → a compiled `os:cmd(C,#{})`
    // hit call_ext_code → undef.
    if (std.mem.eql(u8, module, "os") and std.mem.eql(u8, name, "cmd") and arity == 2)
        return &os_bifs.cmd_2;
    if (std.mem.eql(u8, module, "os") and std.mem.eql(u8, name, "set_signal") and arity == 2)
        return &os_bifs.set_signal_2;
    // gap-erl-cli-args (DIVERGENCE 598): the init CLI-argument BIFs — init.erl funcs
    // (NOT bif.tab rows) that answer from the Vm's parsed init argv. The drop-in-erl
    // contract escripts/release-scripts read.
    if (std.mem.eql(u8, module, "init") and std.mem.eql(u8, name, "get_plain_arguments") and arity == 0)
        return &procsys.get_plain_arguments_0;
    if (std.mem.eql(u8, module, "init") and std.mem.eql(u8, name, "get_argument") and arity == 1)
        return &procsys.get_argument_1;
    // gap-hof-parse (DIVERGENCE 673): init:get_arguments/0 — the whole parsed
    // init argv, which erl_features:keywords/0 (behind erl_scan) reads.
    if (std.mem.eql(u8, module, "init") and std.mem.eql(u8, name, "get_arguments") and arity == 0)
        return &procsys.get_arguments_0;
    // DIVERGENCE 676: erts_internal:mc_iterator/1 — the map-comprehension iterator
    // primitive (`K := V <- Map`). NOT in the pin's bif.tab — it is Erlang in the
    // preloaded erts_internal.erl (`mc_iterator(Map) -> map_next(0, Map, iterator)`),
    // so it lives here (a library wrapper), NOT in implOf. Native impl mirrors that
    // map_next result: the whole map as a {K,V,Next} chain ending in `none`.
    if (std.mem.eql(u8, module, "erts_internal") and std.mem.eql(u8, name, "mc_iterator") and arity == 1)
        return &maps.mc_iterator_1;
    // DIVERGENCE 678: the two ets.erl WRAPPERS (not bif.tab rows) over primitives
    // zigvm already implements — delete_all_objects(T) = internal_delete_all(T,_)
    // then `true`; select_delete(T, MS) = internal_select_delete(T, MS) (the
    // match-all `[{'_',[],[true]}]` fast path is subsumed by the general primitive).
    if (std.mem.eql(u8, module, "ets") and std.mem.eql(u8, name, "delete_all_objects") and arity == 1)
        return &ets.delete_all_objects_1;
    if (std.mem.eql(u8, module, "ets") and std.mem.eql(u8, name, "select_delete") and arity == 2)
        return &ets.internal_select_delete_2;
    // DIVERGENCE 719: ets:tab2list/1 — an ets.erl WRAPPER (a select-all over the
    // table, no bif.tab row on this pin). The `tab2list_1` handler + its E2.9 law
    // already existed but were wired NOWHERE → a compiled `ets:tab2list(T)` hit
    // undef (FM-DISPATCH-DEAD). Serve it here (the delete_all_objects/1 precedent).
    if (std.mem.eql(u8, module, "ets") and std.mem.eql(u8, name, "tab2list") and arity == 1)
        return &ets.tab2list_1;
    if (!std.mem.eql(u8, module, "erlang")) return null;
    // gap-app-boot-engine: erlang:universaltime/0 (UTC from the real clock) —
    // cowboy_clock:rfc1123 needs it for the HTTP Date header. `.justified` in
    // bif.tab (TZ residual) so `resolve` misses and this library path serves it.
    if (std.mem.eql(u8, name, "universaltime") and arity == 0) return &conv.universaltime_0;
    // gap-justified-bif-sweep (DIVERGENCE 653): erlang:now/0 — a TRUTHFUL system
    // timestamp {Mega,Sec,Micro} from the real UTC clock (host-nondeterministic, not
    // TZ-coupled). `.justified` (deferred-calendar-tz: the value is not byte-EQ), so
    // `resolve` misses and this library path serves it — undef → a working timestamp
    // for legacy code that still calls now(). FM-OBS-1: never a fabricated value.
    if (std.mem.eql(u8, name, "now") and arity == 0) return &conv.now_0;
    // gap-real-metrics (DIVERGENCE 627): erlang:memory/0,1 — truthful measured
    // bytes via a Vm trap (was FM-DISPATCH-DEAD/undef). `.justified` in bif.tab
    // (host-nondeterministic values), so `resolve` misses and this library path
    // serves it. FM-OBS-1: never a fabricated value.
    if (std.mem.eql(u8, name, "memory") and arity == 0) return &procsys.memory_0;
    if (std.mem.eql(u8, name, "memory") and arity == 1) return &procsys.memory_1;
    // gap-cowboy-serve (DIVERGENCE 646, FM-DISPATCH-DEAD): erlang:binary_to_integer/1,2
    // + list_to_integer/1,2 — a real beam CALLS these auto-imported verbs directly
    // (cowboy's `cow_http_hd:parse_host` does `binary_to_integer(Port)` on a Host
    // header's `:8099`). The conv.*_integer_* handlers already existed + were
    // law-proven by DIRECT call, but the COMPILED `erlang:binary_to_integer/1`
    // resolved to `undef`: these are NOT bif.tab `.implemented` rows (the pin's
    // primitive is `erts_internal:*_integer/2`), so `resolve`+`implOf` both missed.
    // Only a LITERAL-arg call worked — erlc CONSTANT-FOLDS `binary_to_integer(<<"8099">>)`
    // at compile time, so the fold MASKED the dead runtime dispatch. Serve them on
    // the library path (the halt/0 / memory/0 precedent) → badarg on bad digits,
    // matching OTP, NEVER undef.
    if (std.mem.eql(u8, name, "binary_to_integer")) return switch (arity) {
        1 => &conv.binary_to_integer_1,
        2 => &conv.binary_to_integer_2,
        else => null,
    };
    if (std.mem.eql(u8, name, "list_to_integer")) return switch (arity) {
        1 => &conv.list_to_integer_1,
        2 => &conv.list_to_integer_2,
        else => null,
    };
    // gap-atom-binary-1 (DIVERGENCE 716, FM-DISPATCH-DEAD): erlang:atom_to_binary/1
    // + binary_to_atom/1 — the utf8-default auto-imported verbs. The pin's bif.tab
    // declares ONLY /2 (these /1 are erlang.erl library wrappers `f(A) -> f(A,utf8)`),
    // so `resolve`+`implOf` both miss and a COMPILED `atom_to_binary(hello)` hit undef.
    // The conv.*_1 handlers already exist (utf8) — wire them on the library path.
    if (std.mem.eql(u8, name, "atom_to_binary") and arity == 1) return &conv.atom_to_binary_1;
    if (std.mem.eql(u8, name, "binary_to_atom") and arity == 1) return &conv.binary_to_atom_1;
    // DIVERGENCE 721: erlang:convert_time_unit/3 — an erlang.erl LIBRARY wrapper
    // (NOT a bif.tab row on this pin) doing the pure floor-toward-−∞ unit
    // conversion. The `time_algebra.convert` arithmetic already existed; only the
    // reachable BIF wrapper was missing (a compiled call hit undef).
    if (std.mem.eql(u8, name, "convert_time_unit") and arity == 3) return &time_bifs.convert_time_unit_3;
    // DIVERGENCE 722: erlang:get_cookie/0 — an auth/erlang.erl LIBRARY wrapper
    // (no bif.tab row); zigvm has no cookie machinery → the truthful `nocookie`.
    if (std.mem.eql(u8, name, "get_cookie") and arity == 0) return &procsys.get_cookie_0;
    // DIVERGENCE 723: erlang:is_alive/0 — net_kernel/erlang.erl library wrapper
    // (no bif.tab row); the VM-owned distribution state (false until distributed).
    if (std.mem.eql(u8, name, "is_alive") and arity == 0) return &procsys.is_alive_0;
    // e50-halt WIRING FIX: erlang:halt/0,1,2 terminate the node — the misc.halt_*
    // BifFns set the `node_halt` pending → doNodeHalt (exit code / abort / crashdump
    // slogan). The handler is e50-halt-LAW-proven, but a COMPILED `halt(N)` missed
    // this library path: the halt arm lived only in `implOf` (reached ONLY for
    // bif.tab `.implemented` rows — halt is NOT one → DEAD), so `resolve` + `implOf`
    // both missed → `call_ext_code` → `undef` (empirically: `halt(0)` printed a
    // trailing `undef` and never set the exit code). Wire it here on the library
    // path (the universaltime/0 / spawn/1 precedent): halt/2 is `.justified` in
    // bif.tab so `resolve` misses and this serves all three arities.
    if (std.mem.eql(u8, name, "halt")) return switch (arity) {
        0 => &misc.halt_0,
        1 => &misc.halt_1,
        2 => &misc.halt_2,
        else => null,
    };
    // DEAD-DISPATCH SWEEP (DIVERGENCE 587): erlang:trace/3 + trace_pattern/2,3 were
    // in implOf but erts_internal:trace/trace_pattern are `.justified` (not
    // .implemented) → resolve() missed → implOf never ran → undef. Moved here.
    if (std.mem.eql(u8, name, "trace") and arity == 3) return &trace_bifs.trace_3;
    if (std.mem.eql(u8, name, "trace_pattern")) return switch (arity) {
        2 => &trace_bifs.trace_pattern_2,
        3 => &trace_bifs.trace_pattern_3,
        else => null,
    };
    // gap-tracing-trace-info (DIVERGENCE 601): trace_delivered/1 (a trace flush
    // barrier — mint a ref, deliver {trace_delivered,T,Ref}). trace_info/2 is a
    // bif.tab .implemented row (reached via resolve → implOf), extended here for the
    // MFA function-trace query form.
    if (std.mem.eql(u8, name, "trace_delivered") and arity == 1) return &trace_bifs.trace_delivered_1;
    if (std.mem.eql(u8, name, "spawn_monitor")) return switch (arity) {
        1 => &procsys.spawn_monitor_1,
        3 => &procsys.spawn_monitor_3,
        else => null,
    };
    // e47-a5: erlang.erl wrapper tail — alias() -> alias([]) and
    // garbage_collect() -> erts_internal:garbage_collect(major) (both defined
    // in erlang.erl, not bif.tab rows; the spawn_monitor precedent).
    // hibernate/0 stays a NAMED deferral (an OTP-28 special loader
    // instruction — suspend-until-message keeping the stack; cold for P-APP).
    if (std.mem.eql(u8, name, "alias") and arity == 0) return &procsys.alias_0;
    if (std.mem.eql(u8, name, "garbage_collect") and arity == 0) return &procsys.garbage_collect_0;
    // e48-appctl-handoff: hibernate/0 IMPLEMENTED (the a5 deferral discharged
    // — OTP-30 proc_lib hibernates idle processes; a resident tree NEEDS it).
    if (std.mem.eql(u8, name, "hibernate") and arity == 0) return &procsys.hibernate_0;
    // E21.1 (DIVERGENCE 450): `spawn/1` + `spawn_link/1` are erlang.erl LIBRARY
    // wrappers (NOT bif.tab rows — real OTP defines `spawn(F) -> spawn_opt(erlang,
    // apply, [F,[]], [])`), so like `spawn_monitor`/`io:put_chars` they are ABSENT
    // from bif_table/supported_bifs/the ledger and expanded inline here. Each traps
    // `spawn_fun` (Vm-law-proven since E3.7 — child runs `F()` at the fun's label,
    // closure env copied cross-heap, link atomic). Before E21.1 wired this arm, a
    // compiled `spawn(fun...)` missed BOTH resolve tables → `call_ext_code` →
    // `undef` (empirically: sf:t(7) = `undef` on zigvm vs `7` on the OTP-28 host).
    // Consulted AFTER `resolve` misses; does NOT participate in the "resolve AGREES
    // with supported_bifs" law (a library wrapper is not a capability).
    if (std.mem.eql(u8, name, "spawn")) return switch (arity) {
        1 => &procsys.spawn_1,
        else => null,
    };
    if (std.mem.eql(u8, name, "spawn_link")) return switch (arity) {
        1 => &procsys.spawn_link_1,
        else => null,
    };
    // gap-open-port-dispatch (DIVERGENCE 594): the AUTO-IMPORTED `erlang:` port
    // verbs. FM-DISPATCH-DEAD instance #9 — the port BifFns were wired ONLY inside
    // `implOfErtsInternal` (reached via resolve() for the `.implemented`
    // erts_internal:* rows), but ALL user code auto-imports them as `erlang:`
    // BIFs (`open_port/2`, `port_command/2`, `port_close/1`, `ports/0`, …), which
    // have no bif.tab row → resolve() misses → this erlang region had no port verb
    // → undef (empirically: `open_port({spawn,"cat"},[])` = undef on zigvm vs a
    // live Port on OTP-30). The handlers were e5.4/e6.7-law-proven, but only ever
    // via `erts_internal:*` — masking the user-name gap. Wire the erlang: names to
    // the SAME proven BifFns (the halt/trace precedent above). port_command/2 is
    // the auto-imported 2-arg form (bifs/ports.zig).
    if (std.mem.eql(u8, name, "open_port") and arity == 2) return &ports.open_port_2;
    if (std.mem.eql(u8, name, "port_command")) return switch (arity) {
        2 => &ports.port_command_2,
        3 => &ports.port_command_3,
        else => null,
    };
    if (std.mem.eql(u8, name, "port_close") and arity == 1) return &ports.port_close_1;
    if (std.mem.eql(u8, name, "port_connect") and arity == 2) return &ports.port_connect_2;
    if (std.mem.eql(u8, name, "port_control") and arity == 3) return &ports.port_control_3;
    if (std.mem.eql(u8, name, "port_call") and arity == 3) return &ports.port_call_3;
    if (std.mem.eql(u8, name, "port_info")) return switch (arity) {
        1 => &ports.port_info_1,
        2 => &ports.port_info_2,
        else => null,
    };
    if (std.mem.eql(u8, name, "port_set_data") and arity == 2) return &ports.port_set_data_2;
    if (std.mem.eql(u8, name, "port_get_data") and arity == 1) return &ports.port_get_data_1;
    if (std.mem.eql(u8, name, "ports") and arity == 0) return &ports.ports_0;
    return null;
}

/// The family fn for an `.implemented` table entry. Each executable BIF adds ONE
/// arm here (never a branch at a call site). Returns `null` defensively if the
/// table marks a key `.implemented` this function has no fn for — a guard against
/// classification/impl drift (the caller then traps `undef`, never mis-executes).
fn implOf(module: []const u8, name: []const u8, arity: u8) ?BifFn {
    if (std.mem.eql(u8, module, "erts_internal")) return implOfErtsInternal(name, arity);
    if (std.mem.eql(u8, module, "lists")) return implOfLists(name, arity);
    if (std.mem.eql(u8, module, "maps")) return implOfMaps(name, arity);
    if (std.mem.eql(u8, module, "binary")) return implOfBinary(name, arity);
    if (std.mem.eql(u8, module, "ets")) return implOfEts(name, arity);
    if (std.mem.eql(u8, module, "math")) return implOfMath(name, arity);
    if (std.mem.eql(u8, module, "persistent_term")) return implOfPersistentTerm(name, arity);
    if (std.mem.eql(u8, module, "atomics")) return implOfAtomics(name, arity);
    if (std.mem.eql(u8, module, "unicode")) return implOfUnicode(name, arity);
    if (std.mem.eql(u8, module, "records")) return implOfRecords(name, arity);
    if (std.mem.eql(u8, module, "re")) return implOfRe(name, arity);
    // E8.2c: the net_kernel no-carrier distribution observer subset.
    if (std.mem.eql(u8, module, "net_kernel"))
        return if (arity == 1 and std.mem.eql(u8, name, "dflag_unicode_io")) &procsys.dflag_unicode_io_1 else null;
    // E6.3 (DIVERGENCE 108): the literal-area collector system-process BIFs —
    // release_area_switch/0 + send_copy_request/3 — RESTRICTED to their collector
    // process (a non-collector call raises error:notsup, host-verified). See
    // bifs/code.zig.
    if (std.mem.eql(u8, module, "erts_literal_area_collector")) {
        if (arity == 0 and std.mem.eql(u8, name, "release_area_switch")) return &code_bifs.release_area_switch_0;
        if (arity == 3 and std.mem.eql(u8, name, "send_copy_request")) return &code_bifs.send_copy_request_3;
        return null;
    }
    // E4.4: the native-name codec family (bifs/file.zig). On this pin the ENTIRE
    // prim_file:/file: bif.tab surface is these five codec rows (file I/O is the
    // NIF/driver surface, no bif.tab row — see src/prim_file.zig).
    if (std.mem.eql(u8, module, "prim_file")) return implOfPrimFile(name, arity);
    if (std.mem.eql(u8, module, "file"))
        return if (arity == 0 and std.mem.eql(u8, name, "native_name_encoding")) &file_bifs.native_name_encoding_0 else null;
    // E3.18 wave 5: the misc fast-follow modules (one BIF each) + string.
    if (std.mem.eql(u8, module, "error_logger"))
        return if (arity == 0 and std.mem.eql(u8, name, "warning_map")) &misc.warning_map_0 else null;
    // E7.7: the debugger-capability query. `erl_debugger:supported/0` is the ONE
    // erl_debugger row zigvm answers TRUTHFULLY (false — no debugger subsystem);
    // the rest stay `deferred-erl-debugger` (bif_gen.ml). See bifs/misc.zig.
    if (std.mem.eql(u8, module, "erl_debugger"))
        return if (arity == 0 and std.mem.eql(u8, name, "supported")) &misc.erl_debugger_supported_0 else null;
    // E8.2f: erts_debug:dist_ext_to_term/2 is a term decoder over an explicit
    // atom-cache tuple, not a live distribution channel handle.
    if (std.mem.eql(u8, module, "erts_debug"))
        return if (arity == 2 and std.mem.eql(u8, name, "dist_ext_to_term")) &misc.dist_ext_to_term_2 else null;
    if (std.mem.eql(u8, module, "io")) {
        // E3.18: the printable-range constant.
        if (arity == 0 and std.mem.eql(u8, name, "printable_range")) return &misc.printable_range_0;
        // E4.6 (Task 6): the output verbs riding the group-leader io protocol.
        if (std.mem.eql(u8, name, "put_chars")) return switch (arity) {
            1 => &io.put_chars_1,
            2 => &io.put_chars_2,
            else => null,
        };
        if (std.mem.eql(u8, name, "nl")) return switch (arity) {
            0 => &io.nl_0,
            1 => &io.nl_1,
            else => null,
        };
        // gap-io-format: io:format/1,2,3 (renders via io_format, byte-EQ with
        // io_lib:format, then put_chars to the group leader).
        if (std.mem.eql(u8, name, "format") or std.mem.eql(u8, name, "fwrite")) return switch (arity) {
            1 => &io.format_1,
            2 => &io.format_2,
            3 => &io.format_3,
            else => null,
        };
        return null;
    }
    // gap-io-format: io_lib:format/2 — the PURE path (returns the charlist).
    if (std.mem.eql(u8, module, "io_lib") and std.mem.eql(u8, name, "format") and arity == 2)
        return &io.io_lib_format_2;
    // DIVERGENCE 715: io_lib:write_atom/1, write_string/1, write_char/1 (pure).
    if (std.mem.eql(u8, module, "io_lib") and arity == 1) {
        if (std.mem.eql(u8, name, "write_atom")) return &io.io_lib_write_atom_1;
        if (std.mem.eql(u8, name, "write_string")) return &io.io_lib_write_string_1;
        if (std.mem.eql(u8, name, "write_char")) return &io.io_lib_write_char_1;
    }
    // e47-a1: the logger-less node's logging surface — proc_lib/gen_server hit
    // these on every stock-beam start path (see the io.zig doc block; allow →
    // false is a DISCLOSED no-logger-tree bound, depth → the pinned default).
    if (std.mem.eql(u8, module, "logger")) {
        if (std.mem.eql(u8, name, "allow") and arity == 2)
            return &io.logger_allow_2;
        // gap-logger-null-sink (DIVERGENCE 742): the log API surface as a null sink
        // → `ok` (the SAME no-logger-tree bound as error_logger 650 + allow → false).
        // A DIRECT `logger:LEVEL(...)` / `logger:log(...)` in app code (a proc_lib
        // crash report, a gen_server `terminate`) would otherwise undef-KILL the
        // caller — the logging-spine FM-DISPATCH-DEAD instance. (This block is
        // DUPLICATED at the two resolveLibrary sites — keep them in lockstep.)
        if ((std.mem.eql(u8, name, "emergency") or std.mem.eql(u8, name, "alert") or
            std.mem.eql(u8, name, "critical") or std.mem.eql(u8, name, "error") or
            std.mem.eql(u8, name, "warning") or std.mem.eql(u8, name, "notice") or
            std.mem.eql(u8, name, "info") or std.mem.eql(u8, name, "debug")) and
            (arity == 1 or arity == 2 or arity == 3))
            return &io.logger_ok;
        if (std.mem.eql(u8, name, "log") and (arity == 2 or arity == 3 or arity == 4))
            return &io.logger_ok;
    }
    if (std.mem.eql(u8, module, "error_logger") and std.mem.eql(u8, name, "get_format_depth") and arity == 0)
        return &io.error_logger_get_format_depth_0;
    // DEAD-DISPATCH SWEEP (DIVERGENCE 587): os:cmd/1 + os:set_signal/2 moved to
    // resolveLibrary (library wrappers, not bif.tab .implemented → implOf was DEAD).
    // e49-wire-real-file-io: file:read_file/1 + file:write_file/2 — file.erl
    // LIBRARY wrappers over the prim_file driver; expanded over the proven fd
    // seam (the port BIF precedent).
    // gap-real-file-io: the file: LIBRARY surface (read_file/write_file/list_dir/
    // read_file_info/open/pread/pwrite/close) lives in `resolveLibrary`, NOT here —
    // implOf is bif.tab-only and its file arm early-returns on native_name_encoding,
    // so this placement was DEAD (compiled dispatch → undef, DIVERGENCE 586). Moved.
    // DEAD-DISPATCH SWEEP (DIVERGENCE 587): crypto:hash/mac/hmac/strong_rand_bytes/
    // crypto_one_time + erlang:trace/3 + erlang:trace_pattern/2,3 moved to
    // resolveLibrary (library wrappers over pure std.crypto / the trace signal seam;
    // crypto has NO bif.tab rows and erts_internal:trace* are `.justified`, so these
    // implOf placements were DEAD — a compiled crypto:*/erlang:trace* → undef).
    // e50-halt: erlang:halt/0,1,2 is an erlang.erl LIBRARY wrapper (NOT a bif.tab
    // row — halt/2 is `.justified`), so it lives in `resolveLibrary`, NOT here.
    // (This arm previously duplicated it in `implOf`, which `resolve` reaches ONLY
    // for `.implemented` bif.tab rows — so it was DEAD and a compiled `halt(N)`
    // resolved to neither table → `call_ext_code` → `undef`. Removed to keep the
    // ONE halt wiring in resolveLibrary. DIVERGENCE 584.)
    if (std.mem.eql(u8, module, "string"))
        return if (arity == 1 and std.mem.eql(u8, name, "list_to_float")) &misc.string_list_to_float_1 else null;
    // E5.8b (Task 8b): the os: module clock/env family (bifs/os.zig). Every other
    // os row stays `deferred-E5` via the module-level justification in bif_gen.ml.
    if (std.mem.eql(u8, module, "os")) {
        if (std.mem.eql(u8, name, "getenv")) return if (arity == 1) &os_bifs.getenv_1 else null;
        if (std.mem.eql(u8, name, "putenv")) return if (arity == 2) &os_bifs.putenv_2 else null;
        if (std.mem.eql(u8, name, "unsetenv")) return if (arity == 1) &os_bifs.unsetenv_1 else null;
        if (std.mem.eql(u8, name, "getpid")) return if (arity == 0) &os_bifs.getpid_0 else null;
        if (std.mem.eql(u8, name, "timestamp")) return if (arity == 0) &os_bifs.timestamp_0 else null;
        if (std.mem.eql(u8, name, "perf_counter")) return if (arity == 0) &os_bifs.perf_counter_0 else null;
        if (std.mem.eql(u8, name, "system_time")) return switch (arity) {
            0 => &os_bifs.system_time_0,
            1 => &os_bifs.system_time_1,
            else => null,
        };
        return null;
    }
    if (!std.mem.eql(u8, module, "erlang")) return null;
    // E42-T1: decode_packet/3 is now FULLY implemented (framing + http/http_bin +
    // httph/httph_bin + ssl_tls, all byte-EQ) — flipped out of the
    // dispatch-needed-deferred carve-out into a normal `.implemented` resolution.
    if (arity == 3 and std.mem.eql(u8, name, "decode_packet")) return &erlang.decode_packet_3;
    const A = struct { n: []const u8, a: u8, f: BifFn };
    // The erlang guard family (E2.4). Keyed on (name, arity) so operator
    // overloads at different arities (`-`/1 vs `-`/2) map to distinct fns.
    const tbl = [_]A{
        .{ .n = "*", .a = 2, .f = &erlang.mul },
        .{ .n = "+", .a = 2, .f = &erlang.add },
        .{ .n = "-", .a = 1, .f = &erlang.unary_minus },
        .{ .n = "-", .a = 2, .f = &erlang.sub },
        .{ .n = "/=", .a = 2, .f = &erlang.cmp_ne },
        .{ .n = "<", .a = 2, .f = &erlang.cmp_lt },
        .{ .n = "=/=", .a = 2, .f = &erlang.cmp_exact_ne },
        .{ .n = "=:=", .a = 2, .f = &erlang.cmp_exact_eq },
        .{ .n = "=<", .a = 2, .f = &erlang.cmp_le },
        .{ .n = "==", .a = 2, .f = &erlang.cmp_eq },
        .{ .n = ">", .a = 2, .f = &erlang.cmp_gt },
        .{ .n = ">=", .a = 2, .f = &erlang.cmp_ge },
        .{ .n = "abs", .a = 1, .f = &erlang.abs },
        .{ .n = "and", .a = 2, .f = &erlang.bool_and },
        .{ .n = "band", .a = 2, .f = &erlang.band },
        .{ .n = "bnot", .a = 1, .f = &erlang.bnot },
        .{ .n = "bor", .a = 2, .f = &erlang.bor },
        .{ .n = "bsl", .a = 2, .f = &erlang.bsl },
        .{ .n = "bsr", .a = 2, .f = &erlang.bsr },
        .{ .n = "bxor", .a = 2, .f = &erlang.bxor },
        .{ .n = "byte_size", .a = 1, .f = &erlang.byte_size },
        .{ .n = "bit_size", .a = 1, .f = &erlang.bit_size },
        .{ .n = "ceil", .a = 1, .f = &erlang.ceil },
        .{ .n = "div", .a = 2, .f = &erlang.idiv },
        // E8.2g: no-carrier distribution control-data rows. Zigvm has no
        // constructible dist_handle, so this is the pinned direct-call rejection
        // surface only; channel creation/success paths remain justified.
        .{ .n = "dist_ctrl_get_data", .a = 1, .f = &dist_ctrl.dist_ctrl_get_data_1 },
        .{ .n = "dist_ctrl_get_data_notification", .a = 1, .f = &dist_ctrl.dist_ctrl_get_data_notification_1 },
        .{ .n = "dist_ctrl_get_opt", .a = 2, .f = &dist_ctrl.dist_ctrl_get_opt_2 },
        .{ .n = "dist_ctrl_input_handler", .a = 2, .f = &dist_ctrl.dist_ctrl_input_handler_2 },
        .{ .n = "dist_ctrl_put_data", .a = 2, .f = &dist_ctrl.dist_ctrl_put_data_2 },
        .{ .n = "dist_ctrl_set_opt", .a = 3, .f = &dist_ctrl.dist_ctrl_set_opt_3 },
        .{ .n = "dist_get_stat", .a = 1, .f = &dist_ctrl.dist_get_stat_1 },
        .{ .n = "element", .a = 2, .f = &erlang.element },
        .{ .n = "float", .a = 1, .f = &erlang.float },
        .{ .n = "floor", .a = 1, .f = &erlang.floor },
        .{ .n = "hd", .a = 1, .f = &erlang.hd },
        .{ .n = "is_map_key", .a = 2, .f = &erlang.is_map_key },
        .{ .n = "length", .a = 1, .f = &erlang.length },
        .{ .n = "map_get", .a = 2, .f = &erlang.map_get },
        .{ .n = "map_size", .a = 1, .f = &erlang.map_size },
        .{ .n = "not", .a = 1, .f = &erlang.bool_not },
        .{ .n = "or", .a = 2, .f = &erlang.bool_or },
        .{ .n = "rem", .a = 2, .f = &erlang.irem },
        .{ .n = "round", .a = 1, .f = &erlang.round },
        .{ .n = "size", .a = 1, .f = &erlang.size },
        .{ .n = "tl", .a = 1, .f = &erlang.tl },
        .{ .n = "trunc", .a = 1, .f = &erlang.trunc },
        .{ .n = "tuple_size", .a = 1, .f = &erlang.tuple_size },
        .{ .n = "xor", .a = 2, .f = &erlang.bool_xor },
        // E2.5: the term-conversion family (bifs/conv.zig). Only arities the
        // pin's bif.tab actually declares under `erlang:` are wired here —
        // `atom_to_binary/1`, `binary_to_atom/1` are erlang.erl LIBRARY wrappers
        // (`f(A) -> f(A,utf8)`), so they are served on the resolveLibrary erlang
        // path (DIVERGENCE 716), NOT here — a compiled `atom_to_binary(hello)`
        // was undef until then (FM-DISPATCH-DEAD).
        .{ .n = "atom_to_list", .a = 1, .f = &conv.atom_to_list },
        .{ .n = "list_to_atom", .a = 1, .f = &conv.list_to_atom },
        .{ .n = "list_to_existing_atom", .a = 1, .f = &conv.list_to_existing_atom },
        .{ .n = "atom_to_binary", .a = 2, .f = &conv.atom_to_binary_2 },
        .{ .n = "binary_to_atom", .a = 2, .f = &conv.binary_to_atom_2 },
        .{ .n = "integer_to_list", .a = 1, .f = &conv.integer_to_list_1 },
        .{ .n = "integer_to_list", .a = 2, .f = &conv.integer_to_list_2 },
        .{ .n = "integer_to_binary", .a = 1, .f = &conv.integer_to_binary_1 },
        .{ .n = "integer_to_binary", .a = 2, .f = &conv.integer_to_binary_2 },
        .{ .n = "binary_to_list", .a = 1, .f = &conv.binary_to_list_1 },
        .{ .n = "binary_to_list", .a = 3, .f = &conv.binary_to_list_3 },
        .{ .n = "list_to_binary", .a = 1, .f = &conv.list_to_binary },
        // E3.2: the bitstring conversion family.
        .{ .n = "bitstring_to_list", .a = 1, .f = &conv.bitstring_to_list },
        .{ .n = "list_to_bitstring", .a = 1, .f = &conv.list_to_bitstring },
        .{ .n = "iolist_to_binary", .a = 1, .f = &conv.iolist_to_binary },
        .{ .n = "tuple_to_list", .a = 1, .f = &conv.tuple_to_list },
        .{ .n = "list_to_tuple", .a = 1, .f = &conv.list_to_tuple },
        .{ .n = "term_to_binary", .a = 1, .f = &conv.term_to_binary_1 },
        .{ .n = "term_to_binary", .a = 2, .f = &conv.term_to_binary_2 },
        .{ .n = "binary_to_term", .a = 1, .f = &conv.binary_to_term_1 },
        .{ .n = "binary_to_term", .a = 2, .f = &conv.binary_to_term_2 },
        .{ .n = "float_to_list", .a = 1, .f = &conv.float_to_list_1 },
        .{ .n = "float_to_list", .a = 2, .f = &conv.float_to_list_2 },
        .{ .n = "list_to_float", .a = 1, .f = &conv.list_to_float },
        // E6.6 (Task 6): float<->binary — the float_to_list/list_to_float pair
        // over a binary carrier (round-trip law; /2 fixed-decimals byte form).
        .{ .n = "float_to_binary", .a = 1, .f = &conv.float_to_binary_1 },
        .{ .n = "float_to_binary", .a = 2, .f = &conv.float_to_binary_2 },
        .{ .n = "binary_to_float", .a = 1, .f = &conv.binary_to_float_1 },
        // E2.6: the lists/list-arithmetic family (bifs/lists.zig).
        .{ .n = "++", .a = 2, .f = &lists.append_2 },
        .{ .n = "--", .a = 2, .f = &lists.subtract_2 },
        // E3.12 (Task 12): the exception-raising family (bifs/erlang.zig) is now
        // WIRED — `call_ext` dispatches (they compile to `{call_ext_only,...}`),
        // and every one raises via the CATCH-AWARE `m.bifRaise` path, so the E3.10
        // class-discrimination/structured-reason laws hold end-to-end. `exit/1`
        // uses the CATCHABLE bifRaise `exit_1` (NOT procsys's scheduler-terminate
        // trap — that is `exit/2`, still deferred). Now EQ in `bif_gen.ml`.
        .{ .n = "error", .a = 1, .f = &erlang.error_1 },
        .{ .n = "error", .a = 2, .f = &erlang.error_2 },
        .{ .n = "error", .a = 3, .f = &erlang.error_3 },
        .{ .n = "throw", .a = 1, .f = &erlang.throw_1 },
        .{ .n = "exit", .a = 1, .f = &erlang.exit_1 },
        .{ .n = "exit_signal", .a = 2, .f = &procsys.exit_signal_2 },
        .{ .n = "exit_signal", .a = 3, .f = &procsys.exit_signal_3 },
        .{ .n = "raise", .a = 3, .f = &erlang.raise_3 },
        .{ .n = "nif_error", .a = 1, .f = &erlang.nif_error_1 },
        .{ .n = "nif_error", .a = 2, .f = &erlang.nif_error_2 },
        // E2.11: the process/system BIF family (bifs/procsys.zig) — the
        // non-pid/ref/scheduler-blocked subset only; see that module's doc
        // comment for the full implement/justify split.
        .{ .n = "node", .a = 0, .f = &procsys.node_0 },
        .{ .n = "nodes", .a = 0, .f = &procsys.nodes_0 },
        .{ .n = "nodes", .a = 1, .f = &procsys.nodes_1 },
        .{ .n = "nodes", .a = 2, .f = &procsys.nodes_2 },
        .{ .n = "monitor_node", .a = 2, .f = &procsys.monitor_node_2 },
        .{ .n = "monitor_node", .a = 3, .f = &procsys.monitor_node_3 },
        // E8.2k: no-carrier channel-start rejection. Live channel promotion
        // remains with the carrier owner; this direct BIF raises badarg.
        .{ .n = "setnode", .a = 2, .f = &procsys.setnode_2 },
        .{ .n = "process_flag", .a = 2, .f = &procsys.process_flag_2 },
        .{ .n = "registered", .a = 0, .f = &procsys.registered_0 },
        // E7.6 (S29): the honestly-observable tracing surface (bifs/trace_bifs.zig).
        // The dt_* non-dtrace constants/identity, the seq_trace token setter/reader
        // round-trip, seq_trace_print's no-tracer `false`, and trace_info/2's
        // empty-trace defaults. The delivery/session/breakpoint rows re-bind to
        // `deferred-trace-delivery` (not wired). See DIVERGENCE entry 158.
        .{ .n = "dt_get_tag", .a = 0, .f = &trace_bifs.dt_get_tag_0 },
        .{ .n = "dt_get_tag_data", .a = 0, .f = &trace_bifs.dt_get_tag_data_0 },
        .{ .n = "dt_put_tag", .a = 1, .f = &trace_bifs.dt_put_tag_1 },
        .{ .n = "dt_spread_tag", .a = 1, .f = &trace_bifs.dt_spread_tag_1 },
        .{ .n = "dt_restore_tag", .a = 1, .f = &trace_bifs.dt_restore_tag_1 },
        .{ .n = "dt_prepend_vm_tag_data", .a = 1, .f = &trace_bifs.dt_prepend_vm_tag_data_1 },
        .{ .n = "dt_append_vm_tag_data", .a = 1, .f = &trace_bifs.dt_append_vm_tag_data_1 },
        .{ .n = "seq_trace", .a = 2, .f = &trace_bifs.seq_trace_2 },
        .{ .n = "seq_trace_info", .a = 1, .f = &trace_bifs.seq_trace_info_1 },
        .{ .n = "seq_trace_print", .a = 1, .f = &trace_bifs.seq_trace_print_1 },
        .{ .n = "seq_trace_print", .a = 2, .f = &trace_bifs.seq_trace_print_2 },
        .{ .n = "trace_info", .a = 2, .f = &trace_bifs.trace_info_2 },
        // E3.7: the process-bridge BIFs. Only `self/0` and `node/1` flip EQ —
        // they are reachable end-to-end via `bif0`/`bif1` from a compiled `.beam`
        // TODAY. `self/0` names the running process (its pid term's `number` is
        // the proc index); `node/1` reports the current local node for a
        // local pid/port/ref, or an encoded foreign identity's node.
        // Every OTHER process BIF (spawn/send/exit/…) is `call_ext`-only and stays
        // `deferred-E4-procdispatch` (Task 12/E4) — implemented + law-proven via the Vm
        // in bifs/procsys.zig, but NOT wired here (a false-EQ otherwise; §10 UCA).
        .{ .n = "self", .a = 0, .f = &procsys.self_0 },
        .{ .n = "node", .a = 1, .f = &procsys.node_1 },
        // E4.6 (Task 6): group_leader/0 flips EQ — with the standard_io GL fixture
        // installed by cli (`installGroupLeader`), `group_leader() =/= self()`
        // matches the OTP shell GL end-to-end (the `gl_not_self` corpus row). The
        // pid VALUE still differs from `<0.N.0>`, so it is observed by INEQUALITY,
        // never printed raw. The setter erts_internal:group_leader/2,3 stays
        // deferred (not portably observable). DIVERGENCE entry 40.
        .{ .n = "group_leader", .a = 0, .f = &procsys.group_leader_0 },
        // E4.1: the scheduler-TRAPPING process BIFs, now reachable end-to-end
        // through the E3.12 `call_ext_bif` path + the E3.7 scheduler-as-driver
        // (`cli.runMulti`/`proc.Scheduler.drive`). Each sets `m.pending` = an
        // Action the scheduler interprets on resume (spawn/send/link/monitor/
        // registry/exit-signal). The bodies are the E3.7/E3.8 `procsys.zig` fns
        // VERBATIM — this task only makes their DISPATCH reachable (the
        // `deferred-E4-procdispatch` discharge, DIVERGENCE entry 33). The
        // process-list / group-leader / process_info / spawn_request rows stay
        // deferred with PRECISE new blockers (pid-value/system-process/io-protocol
        // parity) — see harness/bif_gen.ml; they are NOT wired here.
        .{ .n = "!", .a = 2, .f = &procsys.bang_2 },
        .{ .n = "send", .a = 2, .f = &procsys.send_2 },
        .{ .n = "send", .a = 3, .f = &procsys.send_3 },
        .{ .n = "spawn", .a = 3, .f = &procsys.spawn_3 },
        .{ .n = "spawn_link", .a = 3, .f = &procsys.spawn_link_3 },
        .{ .n = "spawn_opt", .a = 4, .f = &procsys.spawn_opt_4 },
        .{ .n = "exit", .a = 2, .f = &procsys.exit_2 },
        .{ .n = "exit", .a = 3, .f = &procsys.exit_3 },
        .{ .n = "is_process_alive", .a = 1, .f = &procsys.is_process_alive_1 },
        // E6.2 (Task 2): the LIVE receive/BIF timer family (bifs/procsys.zig →
        // the proc.zig timer wheel). `send_after`/`start_timer` arm a wheel entry
        // that delivers a message after `Time` ms; `cancel_timer`/`read_timer`
        // observe/retire it. Reachable end-to-end via call_ext_bif + the scheduler-
        // as-driver (the `receive after N` + timer corpus rows). deferred-E6 (the 8
        // timer rows) discharged. DIVERGENCE entry 5.
        .{ .n = "send_after", .a = 3, .f = &procsys.send_after_3 },
        .{ .n = "send_after", .a = 4, .f = &procsys.send_after_4 },
        .{ .n = "start_timer", .a = 3, .f = &procsys.start_timer_3 },
        .{ .n = "start_timer", .a = 4, .f = &procsys.start_timer_4 },
        .{ .n = "cancel_timer", .a = 1, .f = &procsys.cancel_timer_1 },
        .{ .n = "cancel_timer", .a = 2, .f = &procsys.cancel_timer_2 },
        .{ .n = "read_timer", .a = 1, .f = &procsys.read_timer_1 },
        .{ .n = "read_timer", .a = 2, .f = &procsys.read_timer_2 },
        // E6.5 (Task 5): the system introspection family (bifs/procsys.zig) — pure
        // Machine-state readers/writers (statistics counters, the version-
        // independent system_info subset, the system_flag/system_profile round-
        // trips, bump_reductions). The nondeterministic counter VALUES are
        // PROPERTY-FOLDED in the corpus, never byte-asserted. deferred-E6 (the 9
        // introspection rows) discharged. erts_internal:system_monitor/1,3 +
        // scheduler_wall_time/1 are in implOfErtsInternal below.
        .{ .n = "bump_reductions", .a = 1, .f = &procsys.bump_reductions_1 },
        .{ .n = "statistics", .a = 1, .f = &procsys.statistics_1 },
        .{ .n = "system_info", .a = 1, .f = &procsys.system_info_1 },
        .{ .n = "system_flag", .a = 2, .f = &procsys.system_flag_2 },
        .{ .n = "system_profile", .a = 0, .f = &procsys.system_profile_0 },
        .{ .n = "system_profile", .a = 2, .f = &procsys.system_profile_2 },
        // E5.5 (Task 5): the alias-signal model — alias/1 mints a process alias,
        // unalias/1 retires it; delivery + retirement ride the M7 signal
        // machinery (proc.zig's process-local alias table). deferred-E5-alias
        // discharged (DIVERGENCE entry 19/21/33).
        .{ .n = "alias", .a = 1, .f = &procsys.alias_1 },
        .{ .n = "unalias", .a = 1, .f = &procsys.unalias_1 },
        // E5.6 (Task 6): the async spawn/request protocol — spawn_request_abandon/1
        // cancels a still-parked spawn-reply (erts_internal:spawn_request/4 +
        // erts_internal:process_flag/3 are wired in implOfErtsInternal). DIVERGENCE 72.
        .{ .n = "spawn_request_abandon", .a = 1, .f = &procsys.spawn_request_abandon_1 },
        // E6.4 (Task 4): resume_process/1 — the erlang-module half of the
        // suspend/resume counting monoid (suspend_process/2 is erts_internal, below).
        .{ .n = "resume_process", .a = 1, .f = &procsys.resume_process_1 },
        // E7.5 (Task 5): hibernate/3 — DISCARD the call stack, RE-ENTER at M:F/A on
        // the next message (proc.zig doHibernate). Reachable end-to-end via call_ext
        // (the phibernate corpus case). See bifs/procsys.zig.
        .{ .n = "hibernate", .a = 3, .f = &procsys.hibernate_3 },
        .{ .n = "link", .a = 1, .f = &procsys.link_1 },
        .{ .n = "link", .a = 2, .f = &procsys.link_2 },
        .{ .n = "unlink", .a = 1, .f = &procsys.unlink_1 },
        .{ .n = "monitor", .a = 2, .f = &procsys.monitor_2 },
        .{ .n = "monitor", .a = 3, .f = &procsys.monitor_3 },
        .{ .n = "demonitor", .a = 1, .f = &procsys.demonitor_1 },
        .{ .n = "demonitor", .a = 2, .f = &procsys.demonitor_2 },
        .{ .n = "register", .a = 2, .f = &procsys.register_2 },
        .{ .n = "unregister", .a = 1, .f = &procsys.unregister_1 },
        .{ .n = "whereis", .a = 1, .f = &procsys.whereis_1 },
        // E3.9: the process dictionary (S24, bifs/pdict.zig) — pure
        // single-process BIFs (no pid/scheduler dependency). E3.9 fix: only
        // `get/1` is a guard bif reachable end-to-end via bif1 (bif_table
        // marks it `.implemented`, so `resolve` reaches this arm); `put/2`,
        // `get/0`, `erase/0,1`, `get_keys/0,1` compile to `call_ext` and are
        // `deferred-E4-procdispatch` in bif_table, so `resolve` never reaches
        // these arms today (dead-but-harmless — `implOf` is only consulted
        // after `resolve` confirms `.implemented`). Kept wired for Task 12/E4
        // when call_ext dispatch lands, rather than deleted and re-added.
        .{ .n = "put", .a = 2, .f = &pdict.put_2 },
        .{ .n = "get", .a = 0, .f = &pdict.get_0 },
        .{ .n = "get", .a = 1, .f = &pdict.get_1 },
        .{ .n = "erase", .a = 0, .f = &pdict.erase_0 },
        .{ .n = "erase", .a = 1, .f = &pdict.erase_1 },
        .{ .n = "get_keys", .a = 0, .f = &pdict.get_keys_0 },
        .{ .n = "get_keys", .a = 1, .f = &pdict.get_keys_1 },
        // E2.12: the term-inspection/hash/unique family (bifs/term_ops.zig).
        .{ .n = "phash2", .a = 1, .f = &term_ops.phash2_1 },
        .{ .n = "phash2", .a = 2, .f = &term_ops.phash2_2 },
        // E31-T2: the LEGACY erlang:phash/2 (make_hash port; byte-EQ on the
        // data-term fragment, coherent-total elsewhere — see term_ops.zig).
        .{ .n = "phash", .a = 2, .f = &term_ops.phash_2 },
        .{ .n = "setelement", .a = 3, .f = &term_ops.setelement_3 },
        .{ .n = "append_element", .a = 2, .f = &term_ops.append_element_2 },
        .{ .n = "make_tuple", .a = 2, .f = &term_ops.make_tuple_2 },
        .{ .n = "make_tuple", .a = 3, .f = &term_ops.make_tuple_3 },
        // E6.6 (Task 6): the dirty-TAGGED pure tuple splice/drop pair.
        .{ .n = "insert_element", .a = 3, .f = &term_ops.insert_element_3 },
        .{ .n = "delete_element", .a = 2, .f = &term_ops.delete_element_2 },
        // E6.6 (Task 6): the direct display verbs (bifs/io.zig).
        .{ .n = "display", .a = 1, .f = &io.display_1 },
        .{ .n = "display_string", .a = 2, .f = &io.display_string_2 },
        .{ .n = "unique_integer", .a = 0, .f = &term_ops.unique_integer_0 },
        .{ .n = "unique_integer", .a = 1, .f = &term_ops.unique_integer_1 },
        // E5.8b (Task 8b): the monotonic/system time family (bifs/time.zig over
        // the S21 clock seam). Property-EQ (type/monotonicity/offset-identity/
        // timestamp-shape), never byte-EQ. DIVERGENCE entry 93.
        .{ .n = "monotonic_time", .a = 0, .f = &time_bifs.monotonic_time_0 },
        .{ .n = "monotonic_time", .a = 1, .f = &time_bifs.monotonic_time_1 },
        .{ .n = "system_time", .a = 0, .f = &time_bifs.system_time_0 },
        .{ .n = "system_time", .a = 1, .f = &time_bifs.system_time_1 },
        .{ .n = "time_offset", .a = 0, .f = &time_bifs.time_offset_0 },
        .{ .n = "time_offset", .a = 1, .f = &time_bifs.time_offset_1 },
        .{ .n = "timestamp", .a = 0, .f = &time_bifs.timestamp_0 },
        .{ .n = "term_to_iovec", .a = 1, .f = &term_ops.term_to_iovec_1 },
        .{ .n = "term_to_iovec", .a = 2, .f = &term_ops.term_to_iovec_2 },
        // E2.12: the code-index QUERY family (bifs/code.zig).
        .{ .n = "loaded", .a = 0, .f = &code_bifs.loaded_0 },
        .{ .n = "module_loaded", .a = 1, .f = &code_bifs.module_loaded_1 },
        .{ .n = "pre_loaded", .a = 0, .f = &code_bifs.pre_loaded_0 },
        // E5.2b (Task 2 CONTINUATION): the runtime two-version QUERY BIFs over
        // the mutable code table (DIVERGENCE 61; code_q corpus differential).
        .{ .n = "check_old_code", .a = 1, .f = &code_bifs.check_old_code_1 },
        .{ .n = "delete_module", .a = 1, .f = &code_bifs.delete_module_1 },
        // e5-dispatch-codeidx (DIVERGENCE 81): finish_loading/1 — commit a list of
        // prepared handles (from erts_internal:prepare_loading/2) into the runtime
        // code table, making the modules callable via `call_ext`. Returns `ok`.
        .{ .n = "finish_loading", .a = 1, .f = &code_bifs.finish_loading_1 },
        // E7.2 (DIVERGENCE 147): the on_load STAGING trio — has_prepared_code_on_
        // load/1, call_on_load_function/1, finish_after_on_load/2 — driven end-to-
        // end over an embedded on_load beam blob (the `onload_call` corpus case).
        .{ .n = "has_prepared_code_on_load", .a = 1, .f = &code_bifs.has_prepared_code_on_load_1 },
        .{ .n = "call_on_load_function", .a = 1, .f = &code_bifs.call_on_load_function_1 },
        .{ .n = "finish_after_on_load", .a = 2, .f = &code_bifs.finish_after_on_load_2 },
        // E3.13: fun/module introspection (bifs/fun_info.zig). Only `is_builtin/3`
        // (pin bif.tab membership) and `function_exported/3` (the m.exports index)
        // flip EQ — both compile to `call_ext`, dispatch via `call_ext_bif` since
        // E3.12, and are PURE + corpus-proven. `fun_info/2` (arity/type/env subset)
        // is implemented + law-proven in the module but NOT wired: the row stays
        // `deferred_funmeta` (module/name/uniq items need a fun-term metadata
        // extension), and `fun_info_mfa/1`/`fun_to_list/1`/`make_fun/3`/
        // `get_module_info/1,2` are re-bounded (deferred_funmeta/deferred_modinfo).
        .{ .n = "is_builtin", .a = 3, .f = &fun_info.is_builtin_3 },
        .{ .n = "function_exported", .a = 3, .f = &fun_info.function_exported_3 },
        // e47-a2: make_fun/3 — the external-fun constructor (fun M:F/A over the
        // E7.1 export_fun term; the stock gen_server callback-cache keystone).
        .{ .n = "make_fun", .a = 3, .f = &fun_info.make_fun_3 },
        // E4.2: get_module_info/1,2 (behind M:module_info/0,1) over the retained
        // per-module metadata (Machine.mod_meta). md5/module/exports differential-
        // proven; attributes/compile correct-by-construction (ETF decode of the
        // SAME chunk bytes erts decodes). See bifs/erlang.zig, DIVERGENCE entry 29.
        .{ .n = "get_module_info", .a = 1, .f = &erlang.get_module_info_1 },
        .{ .n = "get_module_info", .a = 2, .f = &erlang.get_module_info_2 },
        // E3.6: pid/port/reference type predicates (bifs/erlang.zig) and
        // external representation + make_ref (bifs/conv.zig,
        // bifs/term_ops.zig).
        .{ .n = "is_pid", .a = 1, .f = &erlang.is_pid },
        .{ .n = "is_port", .a = 1, .f = &erlang.is_port },
        .{ .n = "is_reference", .a = 1, .f = &erlang.is_reference },
        // E3.18: the remaining `erlang:` type/guard predicates + min/max +
        // unary +/1 + float //2 + is_record/1,2,3 (the entry-13(a) fast-follow
        // siblings of the E2.4 guard family, all pure ubifs over existing
        // term_algebra observers).
        .{ .n = "is_atom", .a = 1, .f = &erlang.is_atom },
        .{ .n = "is_binary", .a = 1, .f = &erlang.is_binary },
        .{ .n = "is_bitstring", .a = 1, .f = &erlang.is_bitstring },
        .{ .n = "is_boolean", .a = 1, .f = &erlang.is_boolean },
        .{ .n = "is_float", .a = 1, .f = &erlang.is_float },
        .{ .n = "is_integer", .a = 1, .f = &erlang.is_integer },
        .{ .n = "is_integer", .a = 3, .f = &erlang.is_integer_3 },
        .{ .n = "is_list", .a = 1, .f = &erlang.is_list },
        .{ .n = "is_map", .a = 1, .f = &erlang.is_map },
        .{ .n = "is_number", .a = 1, .f = &erlang.is_number },
        .{ .n = "is_tuple", .a = 1, .f = &erlang.is_tuple },
        .{ .n = "is_function", .a = 1, .f = &erlang.is_function_1 },
        .{ .n = "is_function", .a = 2, .f = &erlang.is_function_2 },
        .{ .n = "is_record", .a = 1, .f = &erlang.is_record_1 },
        .{ .n = "is_record", .a = 2, .f = &erlang.is_record_2 },
        .{ .n = "is_record", .a = 3, .f = &erlang.is_record_3 },
        .{ .n = "+", .a = 1, .f = &erlang.unary_plus },
        .{ .n = "/", .a = 2, .f = &erlang.fdiv },
        .{ .n = "min", .a = 2, .f = &erlang.min_2 },
        .{ .n = "max", .a = 2, .f = &erlang.max_2 },
        // E3.18 wave 2: derivations/aliases of already-implemented BIFs.
        // erlang:binary_part/2,3 ARE binary:part/2,3 (identical arg shapes);
        // append/2, subtract/2 ARE ++/2, --/2 (lists.zig); the rest are pure
        // derivations over the ETF encoder / iolist flattener / binPart.
        .{ .n = "binary_part", .a = 2, .f = &binary.part_2 },
        .{ .n = "binary_part", .a = 3, .f = &binary.part_3 },
        .{ .n = "append", .a = 2, .f = &lists.append_2 },
        .{ .n = "subtract", .a = 2, .f = &lists.subtract_2 },
        .{ .n = "external_size", .a = 1, .f = &conv.external_size_1 },
        .{ .n = "external_size", .a = 2, .f = &conv.external_size_2 },
        .{ .n = "iolist_size", .a = 1, .f = &conv.iolist_size_1 },
        .{ .n = "iolist_to_iovec", .a = 1, .f = &conv.iolist_to_iovec_1 },
        .{ .n = "split_binary", .a = 2, .f = &conv.split_binary_2 },
        .{ .n = "binary_to_existing_atom", .a = 2, .f = &conv.binary_to_existing_atom_2 },
        // E3.18 wave 3: self-contained checksums/digests (bifs/checksum.zig) —
        // zlib adler32/crc32 + std MD5 (erts vendors its own md5.c; NOT
        // libcrypto/LA-7). All `erlang:` module BIFs.
        .{ .n = "adler32", .a = 1, .f = &checksum.adler32_1 },
        .{ .n = "adler32", .a = 2, .f = &checksum.adler32_2 },
        .{ .n = "adler32_combine", .a = 3, .f = &checksum.adler32_combine_3 },
        .{ .n = "crc32", .a = 1, .f = &checksum.crc32_1 },
        .{ .n = "crc32", .a = 2, .f = &checksum.crc32_2 },
        .{ .n = "crc32_combine", .a = 3, .f = &checksum.crc32_combine_3 },
        .{ .n = "md5", .a = 1, .f = &checksum.md5_1 },
        .{ .n = "md5_final", .a = 1, .f = &checksum.md5_final_1 },
        .{ .n = "md5_init", .a = 0, .f = &checksum.md5_init_0 },
        .{ .n = "md5_update", .a = 2, .f = &checksum.md5_update_2 },
        // E3.18 wave 4: the pure Gregorian-calendar pair (bifs/conv.zig) — no
        // OS clock / timezone dependency (unlike localtime*, deferred-E5).
        .{ .n = "posixtime_to_universaltime", .a = 1, .f = &conv.posixtime_to_universaltime_1 },
        .{ .n = "universaltime_to_posixtime", .a = 1, .f = &conv.universaltime_to_posixtime_1 },
        // gap-localtime-tz (DIVERGENCE 731): the LOCAL-time family — the pure pair
        // above + the host TZ offset (prim_file.tzOffsetAt over /etc/localtime).
        // bif.tab BIFs (implOf). localtime_to_universaltime/1 is NOT a bif.tab BIF
        // (only /2 is) — it's an erlang.erl LIBRARY WRAPPER, served on the
        // resolveLibrary erlang path below (DIVERGENCE 731), not here.
        .{ .n = "universaltime_to_localtime", .a = 1, .f = &conv.universaltime_to_localtime_1 },
        .{ .n = "localtime", .a = 0, .f = &conv.localtime_0 },
        .{ .n = "date", .a = 0, .f = &conv.date_0 },
        .{ .n = "time", .a = 0, .f = &conv.time_0 },
        .{ .n = "pid_to_list", .a = 1, .f = &conv.pid_to_list },
        .{ .n = "list_to_pid", .a = 1, .f = &conv.list_to_pid },
        .{ .n = "ref_to_list", .a = 1, .f = &conv.ref_to_list },
        .{ .n = "list_to_ref", .a = 1, .f = &conv.list_to_ref },
        .{ .n = "port_to_list", .a = 1, .f = &conv.port_to_list },
        .{ .n = "list_to_port", .a = 1, .f = &conv.list_to_port },
        .{ .n = "make_ref", .a = 0, .f = &term_ops.make_ref_0 },
        // E3.15: the matchspec compile-tester (bifs/ets.zig — it drives the same
        // matchspec-term compiler as the `ets:` select family). `table` type
        // only (trace matchspecs need the trace machinery — bounded, entry 13(b)).
        .{ .n = "match_spec_test", .a = 3, .f = &ets.match_spec_test_3 },
        // E5.4 (Task 4): the port opaque-data slots (bifs/ports.zig).
        .{ .n = "port_set_data", .a = 2, .f = &ports.port_set_data_2 },
        .{ .n = "port_get_data", .a = 1, .f = &ports.port_get_data_1 },
        // E6.7 (Task 7): erlang:ports/0 — the live-port list (SET-membership).
        .{ .n = "ports", .a = 0, .f = &ports.ports_0 },
    };
    for (tbl) |x| {
        if (x.a == arity and std.mem.eql(u8, x.n, name)) return x.f;
    }
    return null;
}

/// `lists:member/2`, `lists:reverse/2`, `lists:keyfind/3`,
/// `lists:keysearch/3`, `lists:keymember/3` (E2.6 — `bifs/lists.zig`). These
/// are genuine `lists:` bif.tab entries (not `erlang:`-module aliases), so
/// they get their own small `implOf*` arm, mirroring `implOfErtsInternal`.
fn implOfLists(name: []const u8, arity: u8) ?BifFn {
    const A = struct { n: []const u8, a: u8, f: BifFn };
    const tbl = [_]A{
        .{ .n = "member", .a = 2, .f = &lists.member },
        .{ .n = "reverse", .a = 2, .f = &lists.reverse_2 },
        .{ .n = "keyfind", .a = 3, .f = &lists.keyfind },
        .{ .n = "keysearch", .a = 3, .f = &lists.keysearch },
        .{ .n = "keymember", .a = 3, .f = &lists.keymember },
    };
    for (tbl) |x| {
        if (x.a == arity and std.mem.eql(u8, x.n, name)) return x.f;
    }
    return null;
}

/// `maps:find/2,get/2,from_list/1,is_key/2,keys/1,merge/2,put/3,remove/2,
/// take/2,update/3,values/1` (E2.7 — `bifs/maps.zig`). `maps:new/0`/`get/3`/
/// `to_list/1` are DELIBERATELY NOT wired here — the pin's bif.tab has no row
/// for them (they're `maps.erl` library wrappers/literal-compiles, see the
/// scope note atop `bifs/maps.zig`), so a wire would be dead code.
fn implOfMaps(name: []const u8, arity: u8) ?BifFn {
    const A = struct { n: []const u8, a: u8, f: BifFn };
    const tbl = [_]A{
        .{ .n = "find", .a = 2, .f = &maps.find_2 },
        .{ .n = "get", .a = 2, .f = &maps.get_2 },
        .{ .n = "from_list", .a = 1, .f = &maps.from_list_1 },
        .{ .n = "from_keys", .a = 2, .f = &maps.from_keys_2 }, // E3.18
        .{ .n = "is_key", .a = 2, .f = &maps.is_key_2 },
        .{ .n = "keys", .a = 1, .f = &maps.keys_1 },
        .{ .n = "merge", .a = 2, .f = &maps.merge_2 },
        .{ .n = "put", .a = 3, .f = &maps.put_3 },
        .{ .n = "remove", .a = 2, .f = &maps.remove_2 },
        .{ .n = "take", .a = 2, .f = &maps.take_2 },
        .{ .n = "update", .a = 3, .f = &maps.update_3 },
        .{ .n = "values", .a = 1, .f = &maps.values_1 },
    };
    for (tbl) |x| {
        if (x.a == arity and std.mem.eql(u8, x.n, name)) return x.f;
    }
    return null;
}

/// `binary:at/2,first/1,last/1,part/2,3,copy/1,2,list_to_bin/1,
/// referenced_byte_size/1,compile_pattern/1,match/2,3,matches/2,3,split/2,3,
/// longest_common_prefix/1,longest_common_suffix/1,encode_unsigned/1,2,
/// decode_unsigned/1,2` (E2.8 — `bifs/binary.zig`). `binary:bin_to_list/1,2,3`
/// is DELIBERATELY absent — a `binary.erl` LIBRARY wrapper (not a bif.tab
/// entry on this pin, see the scope note atop `bifs/binary.zig`).
fn implOfBinary(name: []const u8, arity: u8) ?BifFn {
    const A = struct { n: []const u8, a: u8, f: BifFn };
    const tbl = [_]A{
        .{ .n = "at", .a = 2, .f = &binary.at_2 },
        .{ .n = "first", .a = 1, .f = &binary.first_1 },
        .{ .n = "last", .a = 1, .f = &binary.last_1 },
        .{ .n = "part", .a = 2, .f = &binary.part_2 },
        .{ .n = "part", .a = 3, .f = &binary.part_3 },
        .{ .n = "copy", .a = 1, .f = &binary.copy_1 },
        .{ .n = "copy", .a = 2, .f = &binary.copy_2 },
        .{ .n = "list_to_bin", .a = 1, .f = &binary.list_to_bin_1 },
        .{ .n = "referenced_byte_size", .a = 1, .f = &binary.referenced_byte_size_1 },
        .{ .n = "compile_pattern", .a = 1, .f = &binary.compile_pattern_1 },
        .{ .n = "match", .a = 2, .f = &binary.match_2 },
        .{ .n = "match", .a = 3, .f = &binary.match_3 },
        .{ .n = "matches", .a = 2, .f = &binary.matches_2 },
        .{ .n = "matches", .a = 3, .f = &binary.matches_3 },
        .{ .n = "split", .a = 2, .f = &binary.split_2 },
        .{ .n = "split", .a = 3, .f = &binary.split_3 },
        .{ .n = "longest_common_prefix", .a = 1, .f = &binary.longest_common_prefix_1 },
        .{ .n = "longest_common_suffix", .a = 1, .f = &binary.longest_common_suffix_1 },
        .{ .n = "encode_unsigned", .a = 1, .f = &binary.encode_unsigned_1 },
        .{ .n = "encode_unsigned", .a = 2, .f = &binary.encode_unsigned_2 },
        .{ .n = "decode_unsigned", .a = 1, .f = &binary.decode_unsigned_1 },
        .{ .n = "decode_unsigned", .a = 2, .f = &binary.decode_unsigned_2 },
    };
    for (tbl) |x| {
        if (x.a == arity and std.mem.eql(u8, x.n, name)) return x.f;
    }
    return null;
}

/// The `ets:` BIF family (E2.9 — `bifs/ets.zig`), driving `ets_algebra`'s live
/// `TreeBackend` + the Machine-owned `EtsRegistry`. The core (new/insert/
/// insert_new/lookup/lookup_element/member/delete/delete_object/info) + ordered
/// traversal (first/next/last/prev). The `match`/`select` family stays `.stub`
/// (needs a runtime match-spec-term compiler — new matchspec semantics, a
/// separate slice); `ets:tab2list/1`/`delete_all_objects/1`/`select_delete/2` are
/// ets.erl LIBRARY wrappers (no bif.tab row on this pin), so they are wired in
/// `resolveLibrary` (DIVERGENCE 678/719), NOT in this `implOf`-reached table.
fn implOfEts(name: []const u8, arity: u8) ?BifFn {
    const A = struct { n: []const u8, a: u8, f: BifFn };
    const tbl = [_]A{
        .{ .n = "new", .a = 2, .f = &ets.new_2 },
        .{ .n = "insert", .a = 2, .f = &ets.insert_2 },
        .{ .n = "insert_new", .a = 2, .f = &ets.insert_new_2 },
        .{ .n = "lookup", .a = 2, .f = &ets.lookup_2 },
        .{ .n = "lookup_element", .a = 3, .f = &ets.lookup_element_3 },
        .{ .n = "lookup_element", .a = 4, .f = &ets.lookup_element_4 },
        .{ .n = "member", .a = 2, .f = &ets.member_2 },
        .{ .n = "delete", .a = 1, .f = &ets.delete_1 },
        .{ .n = "delete", .a = 2, .f = &ets.delete_2 },
        .{ .n = "delete_object", .a = 2, .f = &ets.delete_object_2 },
        .{ .n = "first", .a = 1, .f = &ets.first_1 },
        .{ .n = "next", .a = 2, .f = &ets.next_2 },
        .{ .n = "last", .a = 1, .f = &ets.last_1 },
        .{ .n = "prev", .a = 2, .f = &ets.prev_2 },
        .{ .n = "info", .a = 1, .f = &ets.info_1 },
        .{ .n = "info", .a = 2, .f = &ets.info_2 },
        // E3.18 wave 6: core extensions over the live TreeBackend.
        .{ .n = "take", .a = 2, .f = &ets.take_2 },
        .{ .n = "update_element", .a = 3, .f = &ets.update_element_3 },
        .{ .n = "update_element", .a = 4, .f = &ets.update_element_4 },
        // E31-T2: the increment-op grammar (byte-EQ vs erl_db.c db_do_update_counter).
        .{ .n = "update_counter", .a = 3, .f = &ets.update_counter_3 },
        .{ .n = "update_counter", .a = 4, .f = &ets.update_counter_4 },
        .{ .n = "first_lookup", .a = 1, .f = &ets.first_lookup_1 },
        .{ .n = "last_lookup", .a = 1, .f = &ets.last_lookup_1 },
        .{ .n = "next_lookup", .a = 2, .f = &ets.next_lookup_2 },
        .{ .n = "prev_lookup", .a = 2, .f = &ets.prev_lookup_2 },
        .{ .n = "safe_fixtable", .a = 2, .f = &ets.safe_fixtable_2 },
        // E5.9: name-registry remap (a pure single-Machine registry op).
        .{ .n = "rename", .a = 2, .f = &ets.rename_2 },
        // E6.7 (Task 7): the multi-process ownership surface. setopts/2 sets the
        // heir (round-trips via info(heir)); give_away/3 transfers ownership +
        // delivers {'ETS-TRANSFER',...} (traps to proc.zig); whereis/1 returns the
        // Tid (round-trips through lookup — the representation-free proof).
        .{ .n = "setopts", .a = 2, .f = &ets.setopts_2 },
        .{ .n = "give_away", .a = 3, .f = &ets.give_away_3 },
        .{ .n = "whereis", .a = 1, .f = &ets.whereis_1 },
        // E3.15: the match/select family — a runtime matchspec-term compiler
        // (matchspec.zig) driven over the live TreeBackend. match/match_object
        // are head-pattern filters; select* run full match specs; the /1,/3
        // continuation forms chunk by a snapshot-continuation (single-process
        // shadow). select_count/internal_select_delete use the `[true]`-predicate
        // compiler; select_replace verifies key-preservation.
        .{ .n = "match", .a = 1, .f = &ets.select_1 },
        .{ .n = "match", .a = 2, .f = &ets.match_2 },
        .{ .n = "match", .a = 3, .f = &ets.match_3 },
        .{ .n = "match_object", .a = 1, .f = &ets.select_1 },
        .{ .n = "match_object", .a = 2, .f = &ets.match_object_2 },
        .{ .n = "match_object", .a = 3, .f = &ets.match_object_3 },
        .{ .n = "select", .a = 1, .f = &ets.select_1 },
        .{ .n = "select", .a = 2, .f = &ets.select_2 },
        .{ .n = "select", .a = 3, .f = &ets.select_3 },
        .{ .n = "select_count", .a = 2, .f = &ets.select_count_2 },
        .{ .n = "select_replace", .a = 2, .f = &ets.select_replace_2 },
        .{ .n = "select_reverse", .a = 1, .f = &ets.select_1 },
        .{ .n = "select_reverse", .a = 2, .f = &ets.select_reverse_2 },
        .{ .n = "select_reverse", .a = 3, .f = &ets.select_reverse_3 },
        .{ .n = "match_spec_compile", .a = 1, .f = &ets.match_spec_compile_1 },
        .{ .n = "match_spec_run_r", .a = 3, .f = &ets.match_spec_run_r_3 },
        .{ .n = "is_compiled_ms", .a = 1, .f = &ets.is_compiled_ms_1 },
        .{ .n = "internal_select_delete", .a = 2, .f = &ets.internal_select_delete_2 },
        .{ .n = "internal_delete_all", .a = 2, .f = &ets.internal_delete_all_2 },
    };
    for (tbl) |x| {
        if (x.a == arity and std.mem.eql(u8, x.n, name)) return x.f;
    }
    return null;
}

/// `erts_internal:list_to_integer/2` / `binary_to_integer/2` — the pin's
/// ACTUAL base-explicit primitives underneath `erlang:list_to_integer/1,2`
/// and `erlang:binary_to_integer/1,2` (which are erlang.erl library wrappers,
/// not bif.tab entries themselves — see the E2.5 scope note in
/// `bifs/conv.zig`). Args are `(String|Binary, Base)`, matching
/// `conv.list_to_integer_2`/`binary_to_integer_2` exactly. `atomics_new/2`
/// (E2.10) is the SAME shape underneath `atomics:new/2` — see
/// `bifs/atomics.zig`'s scope note.
fn implOfErtsInternal(name: []const u8, arity: u8) ?BifFn {
    if (arity == 2 and std.mem.eql(u8, name, "abort_pending_connection")) return &procsys.abort_pending_connection_2;
    if (arity == 3 and std.mem.eql(u8, name, "create_dist_channel")) return &procsys.create_dist_channel_3;
    // DIVERGENCE 675: erts_internal:list_to_integer/2 is the LENIENT prefix
    // parser ({Int,Rest}|no_integer|big) the `string` module rides — NOT the
    // strict erlang:list_to_integer/2 (bare int|badarg). Was wrongly aliased to
    // the strict conv.list_to_integer_2, breaking string:to_integer.
    if (arity == 2 and std.mem.eql(u8, name, "list_to_integer")) return &conv.erts_internal_list_to_integer_2;
    if (arity == 2 and std.mem.eql(u8, name, "binary_to_integer")) return &conv.binary_to_integer_2;
    if (arity == 2 and std.mem.eql(u8, name, "atomics_new")) return &atomics.atomics_new_2;
    // E36-T1: the counters primitives (write_concurrency backend under
    // counters.erl) — reuse the atomics-array algebra (single-thread shadow).
    if (arity == 1 and std.mem.eql(u8, name, "counters_new")) return &counters.counters_new_1;
    if (arity == 2 and std.mem.eql(u8, name, "counters_get")) return &counters.counters_get_2;
    if (arity == 3 and std.mem.eql(u8, name, "counters_add")) return &counters.counters_add_3;
    if (arity == 3 and std.mem.eql(u8, name, "counters_put")) return &counters.counters_put_3;
    if (arity == 1 and std.mem.eql(u8, name, "counters_info")) return &counters.counters_info_1;
    // E8.2c/E8.2e: no-carrier distribution observers.
    if (arity == 0 and std.mem.eql(u8, name, "get_creation")) return &procsys.get_creation_0;
    if (arity == 0 and std.mem.eql(u8, name, "get_dflags")) return &procsys.get_dflags_0;
    // E3.18 wave 7: the two representation-INDEPENDENT erts_internal siblings.
    if (arity == 2 and std.mem.eql(u8, name, "cmp_term")) return &term_ops.cmp_term_2;
    // E31-T2: the Tier-1 HAMT iterator primitive (maps.erl to_list/1 & next/1
    // are driven by it). Byte-EQ for flatmaps + the ordered-iterator branch;
    // SET-EQ for >32-key HAMT order (the keys/1 standard). See maps.zig.
    if (arity == 3 and std.mem.eql(u8, name, "map_next")) return &maps.map_next_3;
    if (arity == 0 and std.mem.eql(u8, name, "erase_persistent_terms")) return &persistent_term.erase_persistent_terms_0;
    // E4.3 (Task 3): spawn_system_process/3 is IMPLEMENTED (traps `spawn_system`,
    // proc.zig flags the child a system process) but stays `deferred-E4-systemproc`
    // in the bif_table — a system process that returns is a fatal node error on
    // the oracle, so it is NOT differentially observable to completion (DIVERGENCE
    // entry 21, E4.3). Since `resolve` consults `implOf` only AFTER the bif_table
    // KIND is `.implemented`, this arm is dead-but-ready today (the pdict/E3.9
    // precedent) — wired so a future EQ-capable path lands one edit, not a re-add.
    if (arity == 3 and std.mem.eql(u8, name, "spawn_system_process")) return &procsys.spawn_system_process_3;
    // E5.5 (Task 5): erts_internal:is_process_alive/2 — the ASYNC form of
    // is_process_alive/1, replying `{Ref, boolean()}` via the alias-reply
    // protocol. deferred-E5-alias discharged (DIVERGENCE entry 19/21/33).
    if (arity == 2 and std.mem.eql(u8, name, "is_process_alive")) return &procsys.is_process_alive_2;
    // E5.6/E8.2i: spawn_request/4 is the local async spawn protocol;
    // dist_spawn_request/4 is the no-carrier remote doorway, returning the
    // OTP30 direct-BIF ref shape plus local noconnection/badopt reply.
    if (arity == 4 and std.mem.eql(u8, name, "dist_spawn_request")) return &procsys.dist_spawn_request_4;
    if (arity == 1 and std.mem.eql(u8, name, "new_connection")) return &procsys.new_connection_1;
    if (arity == 1 and std.mem.eql(u8, name, "check_process_code")) return &procsys.check_process_code_1;
    if (arity == 3 and std.mem.eql(u8, name, "request_system_task")) return &procsys.request_system_task_3;
    if (arity == 4 and std.mem.eql(u8, name, "request_system_task")) return &procsys.request_system_task_4;
    if (arity == 4 and std.mem.eql(u8, name, "spawn_request")) return &procsys.spawn_request_4;
    if (arity == 3 and std.mem.eql(u8, name, "process_flag")) return &procsys.process_flag_3;
    // E6.5 (Task 5): the introspection setters behind the erlang wrappers —
    // scheduler_wall_time/1 round-trips the enable flag; system_monitor/1,3 the
    // legacy get/set of the {MonitorPid,Opts} setting. Pure Machine-state
    // readers/writers, PROPERTY-FOLDED in the corpus. deferred-E6 discharged.
    if (arity == 1 and std.mem.eql(u8, name, "scheduler_wall_time")) return &procsys.scheduler_wall_time_1;
    if (arity == 1 and std.mem.eql(u8, name, "system_monitor")) return &procsys.system_monitor_1;
    if (arity == 3 and std.mem.eql(u8, name, "system_monitor")) return &procsys.system_monitor_3;
    // E4.2b (Task 2): beamfile_chunk/2 — PURE over a raw beam-binary argument
    // (no code table). The one code-loading-metadata BIF reachable end-to-end
    // this epoch (synthetic-IFF corpus). See bifs/code.zig.
    if (arity == 2 and std.mem.eql(u8, name, "beamfile_chunk")) return &code_bifs.beamfile_chunk_2;
    // E5.2c (Task 2 RELOAD half): beamfile_module_md5/1 — PURE over a raw beam-
    // binary argument (the whole-beam module checksum). Reachable end-to-end via
    // an embedded real-beam literal (the `bfmd5` corpus case). See bifs/code.zig.
    if (arity == 1 and std.mem.eql(u8, name, "beamfile_module_md5")) return &code_bifs.beamfile_module_md5_1;
    // E5.3 (Task 3): the GL SETTER pair erts_internal:group_leader/2,3 — sets
    // ANOTHER process's group leader (traps `set_group_leader`, mutating the
    // target Machine's `group_leader`). Now OBSERVABLE end-to-end: after
    // `group_leader(GL,P)` the child P reads its own `group_leader()` (the EQ
    // get form) and the value is compared representation-free (`=:= self()`) —
    // the `glset` corpus case. deferred-E5-io setter clause discharged.
    if (arity == 2 and std.mem.eql(u8, name, "group_leader")) return &procsys.group_leader_2;
    if (arity == 3 and std.mem.eql(u8, name, "group_leader")) return &procsys.group_leader_3;
    // e5-dispatch-codeidx (Task 2 RELOAD half, DIVERGENCE 81): prepare_loading/2 —
    // validate a beam binary and STAGE it (returns a magic-ref handle or
    // {error,badfile}); committed by erlang:finish_loading/1. The staged code is
    // spliced into the runtime code space so a finish_loaded module is callable
    // via `call_ext` (the runtime code_index-consulting dispatch). See bifs/code.zig.
    if (arity == 2 and std.mem.eql(u8, name, "prepare_loading")) return &code_bifs.prepare_loading_2;
    // E6.3 (DIVERGENCE 108, amending 75/81): purge_module/2 — RESTRICTED to the
    // erts_code_purger system process; a direct (non-purger) call raises
    // error:notsup (host-verified, the process check dominates arg validation).
    // The real purge is code_server.purgeModule, driven through the boot-spawned
    // purger (proven by the RUNTIME-driven purge-safety law). See bifs/code.zig.
    if (arity == 2 and std.mem.eql(u8, name, "purge_module")) return &code_bifs.purge_module_2;
    // E5.4 (Task 4): the live os-port primitives (bifs/ports.zig → src/os_port.zig).
    if (arity == 2 and std.mem.eql(u8, name, "open_port")) return &ports.open_port_2;
    if (arity == 3 and std.mem.eql(u8, name, "port_command")) return &ports.port_command_3;
    if (arity == 1 and std.mem.eql(u8, name, "port_close")) return &ports.port_close_1;
    // E6.7 (Task 7): the port-representation surface (deferred-E6-portrepr).
    // port_info/1,2 (proplist / item; undefined for a dead port), port_call/3 +
    // port_control/3 (the raw primitives RETURN the atom `badarg` — no driver),
    // port_connect/2 (reassign the connected pid). See bifs/ports.zig + proc.zig.
    if (arity == 1 and std.mem.eql(u8, name, "port_info")) return &ports.port_info_1;
    if (arity == 2 and std.mem.eql(u8, name, "port_info")) return &ports.port_info_2;
    if (arity == 3 and std.mem.eql(u8, name, "port_call")) return &ports.port_call_3;
    if (arity == 3 and std.mem.eql(u8, name, "port_control")) return &ports.port_control_3;
    if (arity == 2 and std.mem.eql(u8, name, "port_connect")) return &ports.port_connect_2;
    // E6.4 (Task 4): the process-suspension + system-task introspection family.
    // suspend_process/2 (the monoid's erts_internal half; resume_process/1 is in
    // the erlang table). is_system_process/1 reads the target's `system` flag.
    // garbage_collect/1 + system_check/1 are self-contained (true / ok). All
    // reachable end-to-end via call_ext_bif (E3.12). See bifs/procsys.zig.
    if (arity == 2 and std.mem.eql(u8, name, "suspend_process")) return &procsys.suspend_process_2;
    if (arity == 1 and std.mem.eql(u8, name, "is_system_process")) return &procsys.is_system_process_1;
    if (arity == 1 and std.mem.eql(u8, name, "garbage_collect")) return &procsys.garbage_collect_1;
    if (arity == 1 and std.mem.eql(u8, name, "system_check")) return &procsys.system_check_1;
    // E7.5 (Task 5): request_system_task/3,4 is MODELED (proc.zig
    // doRequestSystemTask + deliverParkedSysTask, the async {RequestId, Result}
    // reply queue) and law-proven, but its ledger row stays `justified` — the
    // internal request ENCODING is a 28-vs-30 skew (no host byte-EQ). Since
    // `resolve` gates justified rows to null, it is intentionally NOT wired here
    // (call_ext-blocked, the justified-BIF precedent); the reply CONTRACT is
    // exercised by the proc.zig exactly-once-reply law. See bifs/procsys.zig.
    // E6.6 (Task 6): the dirty-scheduler erts_internal rows (bifs/procsys.zig).
    // check_dirty_process_code/2 + dirty_process_handle_signals/1 are RESTRICTED
    // entries → error:notsup (host-verified, arg-independent); is_process_executing_dirty/1
    // → false (single synchronous pool); perf_counter_unit/0 → the ns unit (property-folded).
    if (arity == 2 and std.mem.eql(u8, name, "check_dirty_process_code")) return &procsys.check_dirty_process_code_2;
    if (arity == 1 and std.mem.eql(u8, name, "dirty_process_handle_signals")) return &procsys.dirty_process_handle_signals_1;
    if (arity == 1 and std.mem.eql(u8, name, "is_process_executing_dirty")) return &procsys.is_process_executing_dirty_1;
    if (arity == 0 and std.mem.eql(u8, name, "perf_counter_unit")) return &procsys.perf_counter_unit_0;
    return null;
}

/// `math:` (E2.10 — `bifs/math.zig`) — 24 bif.tab rows. `pi/0`/`tau/0` are
/// NOT bif.tab entries (see the module scope note) and stay unwired.
fn implOfMath(name: []const u8, arity: u8) ?BifFn {
    const A = struct { n: []const u8, a: u8, f: BifFn };
    const tbl = [_]A{
        .{ .n = "acos", .a = 1, .f = &math.acos_1 },
        .{ .n = "acosh", .a = 1, .f = &math.acosh_1 },
        .{ .n = "asin", .a = 1, .f = &math.asin_1 },
        .{ .n = "asinh", .a = 1, .f = &math.asinh_1 },
        .{ .n = "atan", .a = 1, .f = &math.atan_1 },
        .{ .n = "atan2", .a = 2, .f = &math.atan2_2 },
        .{ .n = "atanh", .a = 1, .f = &math.atanh_1 },
        .{ .n = "ceil", .a = 1, .f = &math.ceil_1 },
        .{ .n = "cos", .a = 1, .f = &math.cos_1 },
        .{ .n = "cosh", .a = 1, .f = &math.cosh_1 },
        .{ .n = "erf", .a = 1, .f = &math.erf_1 },
        .{ .n = "erfc", .a = 1, .f = &math.erfc_1 },
        .{ .n = "exp", .a = 1, .f = &math.exp_1 },
        .{ .n = "floor", .a = 1, .f = &math.floor_1 },
        .{ .n = "fmod", .a = 2, .f = &math.fmod_2 },
        .{ .n = "log", .a = 1, .f = &math.log_1 },
        .{ .n = "log10", .a = 1, .f = &math.log10_1 },
        .{ .n = "log2", .a = 1, .f = &math.log2_1 },
        .{ .n = "pow", .a = 2, .f = &math.pow_2 },
        .{ .n = "sin", .a = 1, .f = &math.sin_1 },
        .{ .n = "sinh", .a = 1, .f = &math.sinh_1 },
        .{ .n = "sqrt", .a = 1, .f = &math.sqrt_1 },
        .{ .n = "tan", .a = 1, .f = &math.tan_1 },
        .{ .n = "tanh", .a = 1, .f = &math.tanh_1 },
    };
    for (tbl) |x| {
        if (x.a == arity and std.mem.eql(u8, x.n, name)) return x.f;
    }
    return null;
}

/// `persistent_term:` (E2.10 — `bifs/persistent_term.zig`) — 7 bif.tab rows.
fn implOfPersistentTerm(name: []const u8, arity: u8) ?BifFn {
    const A = struct { n: []const u8, a: u8, f: BifFn };
    const tbl = [_]A{
        .{ .n = "erase", .a = 1, .f = &persistent_term.erase_1 },
        .{ .n = "get", .a = 0, .f = &persistent_term.get_0 },
        .{ .n = "get", .a = 1, .f = &persistent_term.get_1 },
        .{ .n = "get", .a = 2, .f = &persistent_term.get_2 },
        .{ .n = "info", .a = 0, .f = &persistent_term.info_0 },
        .{ .n = "put", .a = 2, .f = &persistent_term.put_2 },
        .{ .n = "put_new", .a = 2, .f = &persistent_term.put_new_2 },
    };
    for (tbl) |x| {
        if (x.a == arity and std.mem.eql(u8, x.n, name)) return x.f;
    }
    return null;
}

/// `atomics:` (E2.10 — `bifs/atomics.zig`) — 7 bif.tab rows. `new/2` itself
/// is NOT here — it dispatches under `erts_internal:atomics_new/2` (see
/// `implOfErtsInternal`), the real primitive `atomics.erl`'s `new/2` wraps.
/// `sub/3`/`sub_get/3` are NOT bif.tab entries (see the module scope note).
fn implOfAtomics(name: []const u8, arity: u8) ?BifFn {
    const A = struct { n: []const u8, a: u8, f: BifFn };
    const tbl = [_]A{
        .{ .n = "add", .a = 3, .f = &atomics.add_3 },
        .{ .n = "add_get", .a = 3, .f = &atomics.add_get_3 },
        .{ .n = "compare_exchange", .a = 4, .f = &atomics.compare_exchange_4 },
        .{ .n = "exchange", .a = 3, .f = &atomics.exchange_3 },
        .{ .n = "get", .a = 2, .f = &atomics.get_2 },
        .{ .n = "info", .a = 1, .f = &atomics.info_1 },
        .{ .n = "put", .a = 3, .f = &atomics.put_3 },
    };
    for (tbl) |x| {
        if (x.a == arity and std.mem.eql(u8, x.n, name)) return x.f;
    }
    return null;
}

/// `unicode:` (E2.12 — `bifs/unicode.zig`) — exactly the pin's 3 real
/// `unicode:` bif.tab rows; see that module's scope note.
fn implOfUnicode(name: []const u8, arity: u8) ?BifFn {
    const A = struct { n: []const u8, a: u8, f: BifFn };
    const tbl = [_]A{
        .{ .n = "bin_is_7bit", .a = 1, .f = &unicode_bifs.bin_is_7bit_1 },
        .{ .n = "characters_to_binary", .a = 2, .f = &unicode_bifs.characters_to_binary_2 },
        .{ .n = "characters_to_list", .a = 2, .f = &unicode_bifs.characters_to_list_2 },
    };
    for (tbl) |x| {
        if (x.a == arity and std.mem.eql(u8, x.n, name)) return x.f;
    }
    return null;
}

/// E3.14: the native-record reflection family (bifs/records.zig). Seven of
/// the pin's eight `records:` rows; `get_definition/2` needs the global
/// staged record-definition table (E4 code server) and is not here.
fn implOfRecords(name: []const u8, arity: u8) ?BifFn {
    const A = struct { n: []const u8, a: u8, f: BifFn };
    const tbl = [_]A{
        .{ .n = "get_module", .a = 1, .f = &records.get_module_1 },
        .{ .n = "get_name", .a = 1, .f = &records.get_name_1 },
        .{ .n = "get", .a = 2, .f = &records.get_2 },
        .{ .n = "get_field_names", .a = 1, .f = &records.get_field_names_1 },
        .{ .n = "is_exported", .a = 1, .f = &records.is_exported_1 },
        .{ .n = "create", .a = 4, .f = &records.create_4 },
        .{ .n = "update", .a = 4, .f = &records.update_4 },
        .{ .n = "get_definition", .a = 2, .f = &records.get_definition_2 },
    };
    for (tbl) |x| {
        if (x.a == arity and std.mem.eql(u8, x.n, name)) return x.f;
    }
    return null;
}

/// E4.4: the `prim_file:` native-name codec family (bifs/file.zig). Four of the
/// five pin rows across prim_file:/file: — the fifth, `file:native_name_encoding/0`,
/// lives under the `file` module (wired in `implOf` directly). The real file
/// OPERATIONS have no bif.tab row (the NIF/driver surface; the algebra is
/// src/prim_file.zig, law-tested but not BIF-reachable — DIVERGENCE entry 36).
fn implOfPrimFile(name: []const u8, arity: u8) ?BifFn {
    if (arity != 1) return null;
    if (std.mem.eql(u8, name, "internal_name2native")) return &file_bifs.internal_name2native_1;
    if (std.mem.eql(u8, name, "internal_native2name")) return &file_bifs.internal_native2name_1;
    if (std.mem.eql(u8, name, "internal_normalize_utf8")) return &file_bifs.internal_normalize_utf8_1;
    if (std.mem.eql(u8, name, "is_translatable")) return &file_bifs.is_translatable_1;
    return null;
}

/// E7.9: the hosted `re:` engine (bifs/re.zig -> re_engine.zig), a bounded
/// byte-PCRE subset with explicit rejection for unsupported constructs.
fn implOfRe(name: []const u8, arity: u8) ?BifFn {
    const A = struct { n: []const u8, a: u8, f: BifFn };
    const tbl = [_]A{
        .{ .n = "compile", .a = 1, .f = &re_bifs.compile_1 },
        .{ .n = "compile", .a = 2, .f = &re_bifs.compile_2 },
        .{ .n = "import", .a = 1, .f = &re_bifs.import_1 },
        .{ .n = "inspect", .a = 2, .f = &re_bifs.inspect_2 },
        .{ .n = "internal_run", .a = 4, .f = &re_bifs.internal_run_4 },
        .{ .n = "run", .a = 2, .f = &re_bifs.run_2 },
        .{ .n = "run", .a = 3, .f = &re_bifs.run_3 },
        .{ .n = "version", .a = 0, .f = &re_bifs.version_0 },
    };
    for (tbl) |x| {
        if (x.a == arity and std.mem.eql(u8, x.n, name)) return x.f;
    }
    return null;
}

// ============================================================================
// Laws
// ============================================================================

test "LAW E2.4 resolve executes the implemented guard family (a representative sample)" {
    try std.testing.expectEqual(@as(?BifFn, &erlang.element), resolve("erlang", "element", 2));
    try std.testing.expectEqual(@as(?BifFn, &erlang.add), resolve("erlang", "+", 2));
    try std.testing.expectEqual(@as(?BifFn, &erlang.sub), resolve("erlang", "-", 2));
    try std.testing.expectEqual(@as(?BifFn, &erlang.unary_minus), resolve("erlang", "-", 1));
    try std.testing.expectEqual(@as(?BifFn, &erlang.cmp_lt), resolve("erlang", "<", 2));
    try std.testing.expectEqual(@as(?BifFn, &erlang.mul), resolve("erlang", "*", 2));
    try std.testing.expectEqual(@as(?BifFn, &erlang.tuple_size), resolve("erlang", "tuple_size", 1));
}

test "LAW E2.4 resolve is ARITY-precise (a same-named other-arity key does not alias)" {
    // `-`/1 and `-`/2 map to DIFFERENT fns; `element/1` is absent entirely.
    try std.testing.expect(resolve("erlang", "-", 1) != resolve("erlang", "-", 2));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erlang", "element", 1));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erlang", "+", 3));
}

test "LAW E2.4 resolve is MODULE-precise (an operator name in another module does not alias)" {
    try std.testing.expectEqual(@as(?BifFn, null), resolve("lists", "+", 2));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erl_eval", "element", 2));
}

test "LAW E3.6 resolve executes the pid/ref/port representation family + make_ref" {
    try std.testing.expectEqual(@as(?BifFn, &erlang.is_pid), resolve("erlang", "is_pid", 1));
    try std.testing.expectEqual(@as(?BifFn, &erlang.is_port), resolve("erlang", "is_port", 1));
    try std.testing.expectEqual(@as(?BifFn, &erlang.is_reference), resolve("erlang", "is_reference", 1));
    try std.testing.expectEqual(@as(?BifFn, &conv.pid_to_list), resolve("erlang", "pid_to_list", 1));
    try std.testing.expectEqual(@as(?BifFn, &conv.list_to_pid), resolve("erlang", "list_to_pid", 1));
    try std.testing.expectEqual(@as(?BifFn, &conv.ref_to_list), resolve("erlang", "ref_to_list", 1));
    try std.testing.expectEqual(@as(?BifFn, &conv.list_to_ref), resolve("erlang", "list_to_ref", 1));
    try std.testing.expectEqual(@as(?BifFn, &conv.port_to_list), resolve("erlang", "port_to_list", 1));
    try std.testing.expectEqual(@as(?BifFn, &conv.list_to_port), resolve("erlang", "list_to_port", 1));
    try std.testing.expectEqual(@as(?BifFn, &term_ops.make_ref_0), resolve("erlang", "make_ref", 0));
    // E5.5 (Task 5): alias/1, unalias/1, erts_internal:is_process_alive/2 are
    // now the alias-signal model — deferred-E5-alias discharged.
    try std.testing.expectEqual(@as(?BifFn, &procsys.alias_1), resolve("erlang", "alias", 1));
    try std.testing.expectEqual(@as(?BifFn, &procsys.unalias_1), resolve("erlang", "unalias", 1));
    try std.testing.expectEqual(@as(?BifFn, &procsys.is_process_alive_2), resolve("erts_internal", "is_process_alive", 2));
    // E5.6 (Task 6): the async spawn/request protocol — deferred-E5-spawnreq
    // discharged; process_flag/3 moved out of deferred-E5-boot (DIVERGENCE 72).
    try std.testing.expectEqual(@as(?BifFn, &procsys.spawn_request_abandon_1), resolve("erlang", "spawn_request_abandon", 1));
    try std.testing.expectEqual(@as(?BifFn, &procsys.check_process_code_1), resolve("erts_internal", "check_process_code", 1));
    try std.testing.expectEqual(@as(?BifFn, &procsys.request_system_task_3), resolve("erts_internal", "request_system_task", 3));
    try std.testing.expectEqual(@as(?BifFn, &procsys.request_system_task_4), resolve("erts_internal", "request_system_task", 4));
    try std.testing.expectEqual(@as(?BifFn, &procsys.spawn_request_4), resolve("erts_internal", "spawn_request", 4));
    try std.testing.expectEqual(@as(?BifFn, &procsys.process_flag_3), resolve("erts_internal", "process_flag", 3));
}

test "LAW E4.4 resolve executes the prim_file:/file: native-name codec family" {
    try std.testing.expectEqual(@as(?BifFn, &file_bifs.internal_name2native_1), resolve("prim_file", "internal_name2native", 1));
    try std.testing.expectEqual(@as(?BifFn, &file_bifs.internal_native2name_1), resolve("prim_file", "internal_native2name", 1));
    try std.testing.expectEqual(@as(?BifFn, &file_bifs.internal_normalize_utf8_1), resolve("prim_file", "internal_normalize_utf8", 1));
    try std.testing.expectEqual(@as(?BifFn, &file_bifs.is_translatable_1), resolve("prim_file", "is_translatable", 1));
    try std.testing.expectEqual(@as(?BifFn, &file_bifs.native_name_encoding_0), resolve("file", "native_name_encoding", 0));
    // Arity/name-precise: an absent arity or a file-op name (no bif.tab row) → null.
    try std.testing.expectEqual(@as(?BifFn, null), resolve("prim_file", "internal_name2native", 2));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("prim_file", "read_file", 2));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("file", "write_file", 2));
}

test "LAW E2.4 a stub/justified table entry resolves to null (trap undef at runtime, not execute)" {
    // erlang:load_nif/2 is a real BIF in the table classified `.justified`
    // (a NIF loader this pure-Zig node does not run) and is NOT in the
    // dispatch-needed-deferred carve-out — so it resolves null. (The carve-out
    // members process_info/1,2 [e21-t2b DIVERGENCE 490-amend] and processes/0
    // [gap-processes-0 DIVERGENCE 651] resolve EXECUTABLE while staying
    // ledger-deferred; see the dispatch-needed-deferred law for that invariant.)
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erlang", "load_nif", 2));
    // erlang:list_to_integer/1 has NO bif.tab entry at all on this pin (it is
    // an erlang.erl library wrapper, not a BIF) — totality over an absent key.
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erlang", "list_to_integer", 1));
    // A wholly-unknown key is null too (totality).
    try std.testing.expectEqual(@as(?BifFn, null), resolve("no_such_mod", "nope", 7));
}

test "LAW E8.2g resolve executes no-carrier dist control-data rejection rows" {
    try std.testing.expectEqual(@as(?BifFn, &dist_ctrl.dist_ctrl_get_data_1), resolve("erlang", "dist_ctrl_get_data", 1));
    try std.testing.expectEqual(@as(?BifFn, &dist_ctrl.dist_ctrl_get_data_notification_1), resolve("erlang", "dist_ctrl_get_data_notification", 1));
    try std.testing.expectEqual(@as(?BifFn, &dist_ctrl.dist_ctrl_get_opt_2), resolve("erlang", "dist_ctrl_get_opt", 2));
    try std.testing.expectEqual(@as(?BifFn, &dist_ctrl.dist_ctrl_input_handler_2), resolve("erlang", "dist_ctrl_input_handler", 2));
    try std.testing.expectEqual(@as(?BifFn, &dist_ctrl.dist_ctrl_put_data_2), resolve("erlang", "dist_ctrl_put_data", 2));
    try std.testing.expectEqual(@as(?BifFn, &dist_ctrl.dist_ctrl_set_opt_3), resolve("erlang", "dist_ctrl_set_opt", 3));
    try std.testing.expectEqual(@as(?BifFn, &dist_ctrl.dist_get_stat_1), resolve("erlang", "dist_get_stat", 1));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erlang", "dist_ctrl_get_data", 2));
}

test "LAW E8.2h resolve executes the no-carrier exit_signal rows" {
    try std.testing.expectEqual(@as(?BifFn, &procsys.exit_signal_2), resolve("erlang", "exit_signal", 2));
    try std.testing.expectEqual(@as(?BifFn, &procsys.exit_signal_3), resolve("erlang", "exit_signal", 3));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erlang", "exit_signal", 1));
}

test "LAW E21.1 spawn-creates-scheduled-proc: resolveLibrary executes the fun-spawn wrappers spawn/1 + spawn_link/1 (end-to-end wiring, DIVERGENCE 450)" {
    // The gap DIVERGENCE 97-amend / 450 closed: the `spawn_fun` trap (child runs
    // `F()`, env copied cross-heap, link atomic) has been Vm-law-proven since E3.7,
    // but `spawn/1`/`spawn_link/1` — erlang.erl LIBRARY wrappers, NOT bif.tab rows —
    // were registered in NEITHER resolve table, so a compiled `spawn(fun...)` fell
    // through to `call_ext_code` → `undef` (empirically: sf:t(7) = `undef` on zigvm
    // vs `7` on the OTP-28 host). RED→GREEN: before E21.1 these returned null.
    try std.testing.expectEqual(@as(?BifFn, &procsys.spawn_1), resolveLibrary("erlang", "spawn", 1));
    try std.testing.expectEqual(@as(?BifFn, &procsys.spawn_link_1), resolveLibrary("erlang", "spawn_link", 1));
    // They are LIBRARY wrappers: absent from the capability `resolve` table (a
    // library wrapper is not a bif.tab capability — the spawn_monitor precedent).
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erlang", "spawn", 1));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erlang", "spawn_link", 1));
    // arity-precision: only the /1 wrapper exists in resolveLibrary; the /3 MFA
    // forms stay REAL bif.tab rows in `resolve` (distinct handlers).
    try std.testing.expectEqual(@as(?BifFn, null), resolveLibrary("erlang", "spawn", 3));
    try std.testing.expectEqual(@as(?BifFn, null), resolveLibrary("erlang", "spawn", 2));
    try std.testing.expectEqual(@as(?BifFn, &procsys.spawn_3), resolve("erlang", "spawn", 3));
    try std.testing.expectEqual(@as(?BifFn, &procsys.spawn_link_3), resolve("erlang", "spawn_link", 3));
}

test "LAW DIVERGENCE-678 ets.erl wrappers resolve to the primitives they wrap: delete_all_objects/1 -> delete_all_objects_1; select_delete/2 -> internal_select_delete_2" {
    try std.testing.expectEqual(@as(?BifFn, &ets.delete_all_objects_1), resolveLibrary("ets", "delete_all_objects", 1));
    try std.testing.expectEqual(@as(?BifFn, &ets.internal_select_delete_2), resolveLibrary("ets", "select_delete", 2));
    // wrong arities do NOT resolve (no spurious wiring).
    try std.testing.expectEqual(@as(?BifFn, null), resolveLibrary("ets", "delete_all_objects", 2));
    try std.testing.expectEqual(@as(?BifFn, null), resolveLibrary("ets", "select_delete", 1));
    try std.testing.expectEqual(@as(?BifFn, null), resolveLibrary("ets", "select_delete", 3));
}

test "LAW dispatch-reachability MANIFEST: every LIBRARY WRAPPER is reachable from compiled dispatch via resolve()∪resolveLibrary() (the FM-DISPATCH-DEAD net — DIVERGENCE 586/587)" {
    // THE FORMAL CHECK for the FM-DISPATCH-DEAD class: a library wrapper (a
    // file.erl/os.erl/crypto/trace/... function that is NOT a bif.tab `.implemented`
    // row) is reachable ONLY if it sits in `resolveLibrary` — NOT `implOf` (which the
    // loader's `resolve()` reaches ONLY for bif.tab rows). A compiled `M:F/A` lowers
    // to `call_ext_bif{resolve(M,F,A) orelse resolveLibrary(M,F,A)}` else `call_ext_code`
    // → undef. This MANIFEST enumerates every wrapper that MUST be reachable and asserts
    // `resolve ∪ resolveLibrary != null` — a future mis-placement into implOf reddens
    // it HERE, at build time, instead of surfacing as `undef` only under a compiled
    // differential. Five capabilities (file/crypto/os:cmd/os:signals/tracing) were
    // found DEAD by the empirical sweep that motivated this net.
    const M = struct { m: []const u8, f: []const u8, a: u8 };
    const manifest = [_]M{
        // file: (DIVERGENCE 586)
        .{ .m = "file", .f = "read_file", .a = 1 },   .{ .m = "file", .f = "write_file", .a = 2 },
        .{ .m = "file", .f = "list_dir", .a = 1 },    .{ .m = "file", .f = "read_file_info", .a = 1 },
        .{ .m = "file", .f = "open", .a = 2 },        .{ .m = "file", .f = "pread", .a = 3 },
        .{ .m = "file", .f = "pwrite", .a = 3 },      .{ .m = "file", .f = "close", .a = 1 },
        .{ .m = "file", .f = "read", .a = 2 },        .{ .m = "file", .f = "write", .a = 2 },
        .{ .m = "file", .f = "position", .a = 2 },    .{ .m = "file", .f = "read_file_info", .a = 2 },
        .{ .m = "file", .f = "delete", .a = 1 },      .{ .m = "file", .f = "rename", .a = 2 },
        .{ .m = "file", .f = "make_dir", .a = 1 },    .{ .m = "file", .f = "del_dir", .a = 1 },
        .{ .m = "file", .f = "truncate", .a = 1 },    .{ .m = "file", .f = "sync", .a = 1 },
        .{ .m = "file", .f = "read_link_info", .a = 1 }, .{ .m = "file", .f = "read_link_info", .a = 2 },
        // crypto: (DIVERGENCE 587)
        .{ .m = "crypto", .f = "hash", .a = 2 },      .{ .m = "crypto", .f = "mac", .a = 4 },
        .{ .m = "crypto", .f = "hmac", .a = 3 },      .{ .m = "crypto", .f = "hmac", .a = 4 },
        .{ .m = "crypto", .f = "strong_rand_bytes", .a = 1 }, .{ .m = "crypto", .f = "crypto_one_time", .a = 5 },
        .{ .m = "crypto", .f = "crypto_one_time_aead", .a = 6 }, .{ .m = "crypto", .f = "crypto_one_time_aead", .a = 7 },
        // os: (DIVERGENCE 587) + os:cmd/2 (DIVERGENCE 594)
        .{ .m = "os", .f = "cmd", .a = 1 },           .{ .m = "os", .f = "set_signal", .a = 2 },
        .{ .m = "os", .f = "cmd", .a = 2 },
        // erlang: AUTO-IMPORTED PORT VERBS (DIVERGENCE 594) — FM-DISPATCH-DEAD #9:
        // the port BifFns were reachable ONLY under module `erts_internal` (the DEAD
        // implOf path), but user code auto-imports them as `erlang:`. This is the net
        // that keeps them reachable by their real user-facing name.
        .{ .m = "erlang", .f = "open_port", .a = 2 }, .{ .m = "erlang", .f = "port_command", .a = 2 },
        .{ .m = "erlang", .f = "port_command", .a = 3 }, .{ .m = "erlang", .f = "port_close", .a = 1 },
        .{ .m = "erlang", .f = "port_connect", .a = 2 }, .{ .m = "erlang", .f = "port_control", .a = 3 },
        .{ .m = "erlang", .f = "port_call", .a = 3 }, .{ .m = "erlang", .f = "port_info", .a = 1 },
        .{ .m = "erlang", .f = "port_info", .a = 2 }, .{ .m = "erlang", .f = "ports", .a = 0 },
        .{ .m = "erlang", .f = "port_set_data", .a = 2 }, .{ .m = "erlang", .f = "port_get_data", .a = 1 },
        // erlang: tracing (DIVERGENCE 587 + 601)
        .{ .m = "erlang", .f = "trace", .a = 3 },     .{ .m = "erlang", .f = "trace_pattern", .a = 2 },
        .{ .m = "erlang", .f = "trace_pattern", .a = 3 }, .{ .m = "erlang", .f = "trace_delivered", .a = 1 },
        // logger: null-sink surface (DIVERGENCE 742) — a DIRECT logger:LEVEL/log call
        // in app code must resolve (was undef → killed the caller). allow/2 = e47-a1.
        .{ .m = "logger", .f = "error", .a = 2 },     .{ .m = "logger", .f = "warning", .a = 1 },
        .{ .m = "logger", .f = "info", .a = 3 },      .{ .m = "logger", .f = "notice", .a = 2 },
        .{ .m = "logger", .f = "debug", .a = 1 },     .{ .m = "logger", .f = "critical", .a = 3 },
        .{ .m = "logger", .f = "log", .a = 2 },       .{ .m = "logger", .f = "log", .a = 4 },
        // erlang: other library wrappers (halt 584, spawn 450, boot)
        .{ .m = "erlang", .f = "halt", .a = 0 },      .{ .m = "erlang", .f = "halt", .a = 1 },
        .{ .m = "erlang", .f = "halt", .a = 2 },      .{ .m = "erlang", .f = "universaltime", .a = 0 },
        .{ .m = "erlang", .f = "spawn", .a = 1 },     .{ .m = "erlang", .f = "spawn_link", .a = 1 },
        .{ .m = "erlang", .f = "spawn_monitor", .a = 1 }, .{ .m = "erlang", .f = "spawn_monitor", .a = 3 },
        // gen_tcp / gen_udp / inet (socket surface)
        .{ .m = "gen_tcp", .f = "listen", .a = 2 },   .{ .m = "gen_tcp", .f = "accept", .a = 1 },
        .{ .m = "gen_tcp", .f = "connect", .a = 3 },  .{ .m = "gen_tcp", .f = "send", .a = 2 },
        .{ .m = "gen_tcp", .f = "recv", .a = 2 },     .{ .m = "gen_tcp", .f = "close", .a = 1 },
        .{ .m = "gen_udp", .f = "open", .a = 2 },     .{ .m = "gen_udp", .f = "send", .a = 4 },
        .{ .m = "gen_udp", .f = "recv", .a = 3 },     .{ .m = "inet", .f = "port", .a = 1 },
        .{ .m = "inet", .f = "setopts", .a = 2 },     .{ .m = "gen_tcp", .f = "shutdown", .a = 2 },
        .{ .m = "inet", .f = "getopts", .a = 2 },
        // app-boot + logging + io_lib wrappers
        .{ .m = "application", .f = "get_env", .a = 1 }, .{ .m = "code", .f = "ensure_loaded", .a = 1 },
        .{ .m = "io_lib", .f = "format", .a = 2 },    .{ .m = "logger", .f = "allow", .a = 2 },
        // init CLI-argument BIFs (DIVERGENCE 598)
        .{ .m = "init", .f = "get_plain_arguments", .a = 0 }, .{ .m = "init", .f = "get_argument", .a = 1 },
        .{ .m = "init", .f = "get_arguments", .a = 0 }, // gap-hof-parse (DIVERGENCE 673)
        // code: hot-load library surface (DIVERGENCE 600)
        .{ .m = "code", .f = "purge", .a = 1 }, .{ .m = "code", .f = "soft_purge", .a = 1 },
        .{ .m = "code", .f = "delete", .a = 1 }, .{ .m = "code", .f = "modified_modules", .a = 0 },
        // observability: erlang:memory/0,1 (DIVERGENCE 627)
        .{ .m = "erlang", .f = "memory", .a = 0 }, .{ .m = "erlang", .f = "memory", .a = 1 },
        // gap-justified-bif-sweep (DIVERGENCE 653): erlang:now/0 (truthful system
        // timestamp) + universaltime/0 must resolve on the library path, not undef.
        .{ .m = "erlang", .f = "now", .a = 0 }, .{ .m = "erlang", .f = "universaltime", .a = 0 },
        // erlang: auto-imported integer parsers (DIVERGENCE 646, FM-DISPATCH-DEAD) —
        // a compiled `erlang:binary_to_integer(Port)` (cowboy's Host `:port` parse)
        // resolved to `undef`; only erlc-constant-folded LITERAL calls masked it.
        .{ .m = "erlang", .f = "binary_to_integer", .a = 1 }, .{ .m = "erlang", .f = "binary_to_integer", .a = 2 },
        .{ .m = "erlang", .f = "list_to_integer", .a = 1 }, .{ .m = "erlang", .f = "list_to_integer", .a = 2 },
        // erlang: atom<->binary /1 utf8-default wrappers (DIVERGENCE 716, FM-DISPATCH-DEAD).
        .{ .m = "erlang", .f = "atom_to_binary", .a = 1 }, .{ .m = "erlang", .f = "binary_to_atom", .a = 1 },
        // erlang:convert_time_unit/3 — erlang.erl library wrapper (DIVERGENCE 721).
        .{ .m = "erlang", .f = "convert_time_unit", .a = 3 },
        // erlang:get_cookie/0 — auth/erlang.erl library wrapper (DIVERGENCE 722).
        .{ .m = "erlang", .f = "get_cookie", .a = 0 },
        // erlang:is_alive/0 — net_kernel/erlang.erl library wrapper (DIVERGENCE 723).
        .{ .m = "erlang", .f = "is_alive", .a = 0 },
        // io_lib: quoted-term-text writers (DIVERGENCE 715).
        .{ .m = "io_lib", .f = "write_atom", .a = 1 }, .{ .m = "io_lib", .f = "write_string", .a = 1 },
        .{ .m = "io_lib", .f = "write_char", .a = 1 },
        // ets.erl wrappers (DIVERGENCE 678 + 719): select-all / delete helpers.
        .{ .m = "ets", .f = "delete_all_objects", .a = 1 }, .{ .m = "ets", .f = "select_delete", .a = 2 },
        .{ .m = "ets", .f = "tab2list", .a = 1 },
        // erts_internal:mc_iterator/1 — the map-comprehension iterator (DIVERGENCE 676).
        .{ .m = "erts_internal", .f = "mc_iterator", .a = 1 },
        // ets.erl wrappers: delete_all_objects/1 + select_delete/2 (DIVERGENCE 678).
        .{ .m = "ets", .f = "delete_all_objects", .a = 1 }, .{ .m = "ets", .f = "select_delete", .a = 2 },
    };
    for (manifest) |w| {
        const reachable = (resolve(w.m, w.f, w.a) orelse resolveLibrary(w.m, w.f, w.a)) != null;
        if (!reachable) {
            std.debug.print("FM-DISPATCH-DEAD: {s}:{s}/{d} resolves to NEITHER table (misplaced in implOf?) → a compiled call would undef\n", .{ w.m, w.f, w.a });
            return error.DispatchUnreachable;
        }
    }
}

test "LAW gap-open-port-dispatch: the AUTO-IMPORTED erlang: port verbs + os:cmd/2 reach their proven BifFns from compiled dispatch (FM-DISPATCH-DEAD #9, DIVERGENCE 594)" {
    // The bug: the port verbs were wired ONLY in implOfErtsInternal (reached via
    // resolve() for the erts_internal:* `.implemented` rows), so `erts_internal:
    // open_port/2` worked but the auto-imported `erlang:open_port/2` — what EVERY
    // compiled beam actually calls — missed resolve() AND had no resolveLibrary
    // erlang-region arm → undef. This LAW pins the user-facing names to the same
    // handlers; a revert to the erts_internal-only wiring reddens it here.
    // (1) the erts_internal path still works (the internal caller relies on it):
    try std.testing.expectEqual(@as(?BifFn, &ports.open_port_2), resolve("erts_internal", "open_port", 2));
    // (2) the AUTO-IMPORTED erlang: names now reach the SAME BifFns (the fix):
    try std.testing.expectEqual(@as(?BifFn, &ports.open_port_2), resolveLibrary("erlang", "open_port", 2));
    try std.testing.expectEqual(@as(?BifFn, &ports.port_command_2), resolveLibrary("erlang", "port_command", 2));
    try std.testing.expectEqual(@as(?BifFn, &ports.port_command_3), resolveLibrary("erlang", "port_command", 3));
    try std.testing.expectEqual(@as(?BifFn, &ports.port_close_1), resolveLibrary("erlang", "port_close", 1));
    try std.testing.expectEqual(@as(?BifFn, &ports.port_connect_2), resolveLibrary("erlang", "port_connect", 2));
    try std.testing.expectEqual(@as(?BifFn, &ports.port_info_1), resolveLibrary("erlang", "port_info", 1));
    try std.testing.expectEqual(@as(?BifFn, &ports.port_info_2), resolveLibrary("erlang", "port_info", 2));
    try std.testing.expectEqual(@as(?BifFn, &ports.ports_0), resolveLibrary("erlang", "ports", 0));
    // (3) os:cmd/2 is wired and DISTINCT from os:cmd/1 (a real arity, not aliased):
    try std.testing.expectEqual(@as(?BifFn, &os_bifs.cmd_2), resolveLibrary("os", "cmd", 2));
    try std.testing.expect(resolveLibrary("os", "cmd", 1) != resolveLibrary("os", "cmd", 2));
    // (4) the whole family lowers to call_ext_bif, never call_ext_code → undef:
    try std.testing.expect((resolve("erlang", "open_port", 2) orelse resolveLibrary("erlang", "open_port", 2)) != null);
}

test "LAW E8.2i resolve executes the no-carrier dist_spawn_request row" {
    try std.testing.expectEqual(@as(?BifFn, &procsys.dist_spawn_request_4), resolve("erts_internal", "dist_spawn_request", 4));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erts_internal", "dist_spawn_request", 3));
}

test "LAW E8.2j resolve executes the pending dist connection rows" {
    try std.testing.expectEqual(@as(?BifFn, &procsys.new_connection_1), resolve("erts_internal", "new_connection", 1));
    try std.testing.expectEqual(@as(?BifFn, &procsys.abort_pending_connection_2), resolve("erts_internal", "abort_pending_connection", 2));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erts_internal", "new_connection", 2));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erts_internal", "abort_pending_connection", 1));
}

test "LAW E8.2k resolve executes no-carrier channel-start rejection rows" {
    try std.testing.expectEqual(@as(?BifFn, &procsys.setnode_2), resolve("erlang", "setnode", 2));
    try std.testing.expectEqual(@as(?BifFn, &procsys.create_dist_channel_3), resolve("erts_internal", "create_dist_channel", 3));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erlang", "setnode", 3));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erts_internal", "create_dist_channel", 2));
}

test "LAW E8.2f resolve executes only the dist_ext_to_term debug decoder row in erts_debug" {
    try std.testing.expectEqual(@as(?BifFn, &misc.dist_ext_to_term_2), resolve("erts_debug", "dist_ext_to_term", 2));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erts_debug", "dist_ext_to_term", 1));
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erts_debug", "flat_size", 1));
}

test "LAW E2.5 list_to_atom/list_to_existing_atom flip .justified(deferred-E6) -> .implemented" {
    try std.testing.expectEqual(@as(?BifFn, &conv.list_to_atom), resolve("erlang", "list_to_atom", 1));
    try std.testing.expectEqual(@as(?BifFn, &conv.list_to_existing_atom), resolve("erlang", "list_to_existing_atom", 1));
}

test "LAW E2.5 erts_internal:list_to_integer/2 and binary_to_integer/2 are the real base-explicit primitives" {
    // DIVERGENCE 675: erts_internal:list_to_integer/2 is the LENIENT prefix parser
    // ({Int,Rest}|no_integer|big) the `string` module rides — NOT the strict
    // erlang:list_to_integer/2 (bare int|badarg, still conv.list_to_integer_2).
    try std.testing.expectEqual(@as(?BifFn, &conv.erts_internal_list_to_integer_2), resolve("erts_internal", "list_to_integer", 2));
    try std.testing.expectEqual(@as(?BifFn, &conv.binary_to_integer_2), resolve("erts_internal", "binary_to_integer", 2));
    // erts_internal is otherwise NOT the erlang guard family's module.
    try std.testing.expectEqual(@as(?BifFn, null), resolve("erts_internal", "element", 2));
}

test "LAW E2.4 resolve AGREES with the dump-caps ledger (supported_bifs) in both directions" {
    // Forward: every advertised capability resolves to a non-null fn.
    for (ia.supported_bifs) |b| {
        try std.testing.expect(resolve(b.module, b.name, b.arity) != null);
    }
    // Reverse: every `.implemented` table entry is advertised AND resolves — so
    // `implOf` and the ledger cannot drift apart.
    for (bif_table.entries) |e| {
        if (e.class != .implemented) continue;
        var found = false;
        for (ia.supported_bifs) |b| {
            if (b.arity == e.arity and std.mem.eql(u8, b.module, e.module) and std.mem.eql(u8, b.name, e.name)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
        try std.testing.expect(resolve(e.module, e.name, e.arity) != null);
    }
}

test "LAW e21-t2b dispatch-needed-deferred: resolvable = supported_bifs XOR dispatch_needed_deferred (disjoint carve-out)" {
    // Every dispatch-needed-deferred member RESOLVES (executable) ...
    for (dispatch_needed_deferred) |d| {
        try std.testing.expect(resolveDispatchNeededDeferred(d.module, d.name, d.arity) != null);
        try std.testing.expect(resolve(d.module, d.name, d.arity) != null);
        // ... and is DISJOINT from supported_bifs (deliberately NOT advertised EQ —
        // the full BIF stays a ledger residual; only its item subset is byte-EQ).
        for (ia.supported_bifs) |b| {
            const same = b.arity == d.arity and
                std.mem.eql(u8, b.module, d.module) and
                std.mem.eql(u8, b.name, d.name);
            try std.testing.expect(!same);
        }
        // ... and its bif_table row is genuinely `.justified` (never `.implemented`,
        // so it never double-counts as a supported cap; the ledger stays honest).
        for (bif_table.entries) |e| {
            if (e.arity == d.arity and std.mem.eql(u8, e.module, d.module) and std.mem.eql(u8, e.name, d.name)) {
                try std.testing.expect(e.class == .justified);
            }
        }
    }
    // A non-member `.justified` row STILL resolves null (the carve-out is a CLOSED
    // list, not a blanket "resolve all justified rows"): `spawn_request_abandon/1`
    // is deferred and NOT dispatch-needed, so it stays undef-trapping.
    try std.testing.expectEqual(@as(?BifFn, null), resolveDispatchNeededDeferred("erlang", "spawn_request_abandon", 1));
}

test "LAW e47-a1 logger-less surface: resolveLibrary wires logger:allow/2 (false — DISCLOSED no-logger bound) + error_logger:get_format_depth/0 (unlimited, the pinned default)" {
    const gpa = std.testing.allocator;
    const FinalTerms = @import("../term_algebra.zig").FinalTerms;
    const Machine = ia.Machine;
    var atoms = @import("../term_algebra.zig").AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    // wiring: the library resolver knows both (a compiled stock beam resolves
    // them instead of trapping undef on every proc_lib start path)
    try std.testing.expectEqual(@as(?BifFn, &io.logger_allow_2), resolveLibrary("logger", "allow", 2));
    try std.testing.expectEqual(@as(?BifFn, &io.error_logger_get_format_depth_0), resolveLibrary("error_logger", "get_format_depth", 0));
    try std.testing.expectEqual(@as(?BifFn, null), resolveLibrary("logger", "allow", 3)); // arity-exact
    // semantics: allow/2 is false for ANY level/module (no logger tree runs);
    // depth is the atom `unlimited` (probed on the pinned oracle)
    const lvl = FinalTerms.atom(&m.ctx, try atoms.intern("error"));
    const mod = FinalTerms.atom(&m.ctx, try atoms.intern("mymod"));
    const r = try io.logger_allow_2(&m, &.{ lvl, mod });
    try std.testing.expect(FinalTerms.repIsAtom(r) and FinalTerms.atomIdxOf(r) == m.bool_false);
    const d = try io.error_logger_get_format_depth_0(&m, &.{});
    try std.testing.expect(FinalTerms.repIsAtom(d) and FinalTerms.atomIdxOf(d) == try atoms.intern("unlimited"));

    // gap-logger-null-sink (DIVERGENCE 742): every logger:LEVEL/1,2,3 + logger:log/2,3,4
    // resolves to the null sink (was undef — the logging-spine FM-DISPATCH-DEAD instance
    // that undef-kills a direct logger:error(...) in app code). Arity-exact.
    inline for (.{ "emergency", "alert", "critical", "error", "warning", "notice", "info", "debug" }) |lname| {
        try std.testing.expectEqual(@as(?BifFn, &io.logger_ok), resolveLibrary("logger", lname, 1));
        try std.testing.expectEqual(@as(?BifFn, &io.logger_ok), resolveLibrary("logger", lname, 2));
        try std.testing.expectEqual(@as(?BifFn, &io.logger_ok), resolveLibrary("logger", lname, 3));
        try std.testing.expectEqual(@as(?BifFn, null), resolveLibrary("logger", lname, 4)); // levels are /1,/2,/3
    }
    try std.testing.expectEqual(@as(?BifFn, &io.logger_ok), resolveLibrary("logger", "log", 2));
    try std.testing.expectEqual(@as(?BifFn, &io.logger_ok), resolveLibrary("logger", "log", 3));
    try std.testing.expectEqual(@as(?BifFn, &io.logger_ok), resolveLibrary("logger", "log", 4));
    try std.testing.expectEqual(@as(?BifFn, null), resolveLibrary("logger", "log", 1)); // log is /2,/3,/4
    try std.testing.expectEqual(@as(?BifFn, null), resolveLibrary("logger", "bogus", 2)); // unknown fn stays undef
    // semantics: the null sink returns `ok` (byte-EQ return; the emit is the disclosed
    // no-logger-tree bound, exactly like error_logger_ok / DIVERGENCE 650).
    const okr = try io.logger_ok(&m, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("boom")), FinalTerms.nil(&m.ctx) });
    try std.testing.expect(FinalTerms.repIsAtom(okr) and FinalTerms.atomIdxOf(okr) == try atoms.intern("ok"));
}

test "LAW e47-a5/e48 wrapper tail: alias/0 traps make_alias(x0); garbage_collect/0,1 RUN the real collector (CAST-20 DISCHARGED: garbage reclaimed, rooted denotation preserved) — resolveLibrary wired" {
    const gpa = std.testing.allocator;
    const FinalTerms = @import("../term_algebra.zig").FinalTerms;
    const Machine = ia.Machine;
    var atoms = @import("../term_algebra.zig").AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    // wiring (arity-exact, both fns)
    try std.testing.expectEqual(@as(?BifFn, &procsys.alias_0), resolveLibrary("erlang", "alias", 0));
    try std.testing.expectEqual(@as(?BifFn, &procsys.garbage_collect_0), resolveLibrary("erlang", "garbage_collect", 0));
    try std.testing.expectEqual(@as(?BifFn, &procsys.hibernate_0), resolveLibrary("erlang", "hibernate", 0)); // e48: IMPLEMENTED (the deferral discharged)
    // alias/0 traps the E5.5 make_alias action with dst = x0
    _ = try procsys.alias_0(&m, &.{});
    try std.testing.expect(m.pending != null and m.pending.? == .make_alias);
    try std.testing.expectEqual(@as(u8, 0), m.pending.?.make_alias.dst);
    m.pending = null;
    // garbage_collect/0,1 (e48-gc-literal-area, CAST-20 discharged): the REAL
    // collector runs — garbage reclaimed, the rooted denotation exact (the
    // linked-code safety is the gc.zig literal-area law + the suspend_fam
    // corpus differential end-to-end).
    m.regs[0] = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 41), FinalTerms.int(&m.ctx, 42) });
    var k: usize = 0;
    while (k < 2000) : (k += 1) _ = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, @intCast(k)), FinalTerms.int(&m.ctx, 7) });
    const before = m.ctx.words.items.len;
    const r = try procsys.garbage_collect_0(&m, &.{});
    try std.testing.expect(FinalTerms.repIsAtom(r) and FinalTerms.atomIdxOf(r) == m.bool_true);
    try std.testing.expect(m.ctx.words.items.len < before); // the garbage is GONE
    try std.testing.expectEqual(@as(i64, 42), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, m.regs[0], 1)));
    const major = FinalTerms.atom(&m.ctx, try atoms.intern("major"));
    const r1 = try procsys.garbage_collect_1(&m, &.{major});
    try std.testing.expect(FinalTerms.repIsAtom(r1) and FinalTerms.atomIdxOf(r1) == m.bool_true);
    try std.testing.expectError(error.Badarg, procsys.garbage_collect_1(&m, &.{FinalTerms.int(&m.ctx, 3)}));
}

