//! # bifs/procsys — the process/system BIF family (E2.11, single-process subset)
//!
//! ## Signature
//! Same contract as the other family modules: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over ALREADY-
//! RESOLVED term arguments, computed via EXISTING Machine state (NO new term
//! semantics live here). It NEVER panics on a well-formed call.
//!
//! ## The crux — row honesty, not local convenience
//! This module started as the E2.11 single-process remainder, when pid/ref/port
//! terms were still absent. Since E3.5/E4.1/E5.7, pid/ref/port terms and the
//! `proc.zig` Vm bridge are real, so this file now contains two honest shapes:
//! pure BIF observers over `Machine` state, and BIFs that set a pending Vm
//! action for the scheduler to finish. A row flips only when the BEAM call site,
//! term representation, scheduler effect, and corpus/ledger evidence are all
//! present. Live distribution control-channel behavior still stays outside this
//! module until the carrier owner lands; no no-carrier observer below may imply
//! a connected peer or remote frame delivery.
//!
//! ## Semantic domain — reuse, not reinvention
//!   node/0        E8.2s routes local node identity through the Vm owner. Before
//!                 `setnode/2` installs a net_kernel-owned identity it observes
//!                 `nonode@nohost`; after install it observes the configured
//!                 local node atom. Total, no args.
//!   node/1        E3.7/E5.7 observes pid/ref/port identity nodes. E8.2t adds a
//!                 VM-synchronized derived local-node observer: locally encoded
//!                 identities observe the active `setnode/2` node while foreign
//!                 identities keep their encoded node atom. The underlying term
//!                 and ETF encodings are not rewritten in this slice.
//!   nodes/0       E8.2n routes connected-node observation through the Vm owner.
//!                 With no live distribution, `nodes()` is still `[]`; after an
//!                 internally promoted live DistEntry, the same public observer
//!                 reads the live connected peers.
//!   nodes/1,2     E8.2b discharges the no-distribution grammar and local
//!                 observer shape; E8.2n/E8.2o/E8.2s route every selector that
//!                 can observe either peers or the local node through the Vm
//!                 owner. `connected`/`visible` still read only live
//!                 `DistEntry` rows, hidden fabricates nothing until hidden-node
//!                 metadata exists, and `known`/`this` read the VM-owned local
//!                 identity (`nonode@nohost` before setnode, configured node
//!                 after setnode). This remains a carrier precursor, not a
//!                 socket/control-data success claim.
//!   get_creation/0 E8.2c/E8.2s: `erts_internal:get_creation/0` observes the
//!                 Vm-owned local distribution creation. With no live local
//!                 identity it returns `undefined`; after net_kernel-owned
//!                 `setnode/2` it returns the normalized creation.
//!   get_dflags/0  E8.2e: `erts_internal:get_dflags/0` is the pinned OTP30
//!                 DFLAG record observed before distribution starts. This is a
//!                 build/pin constant tuple, not a live-peer DFLAG exchange.
//!   dflag_unicode_io/1 E8.2c/E8.2p: `net_kernel:dflag_unicode_io(Pid)` is
//!                 true for a pid on this local node; foreign ETF-created pids
//!                 route through the Vm owner so a live `DistEntry`'s stored
//!                 peer DFLAGS are the only source for the remote answer. With
//!                 no live entry the public answer remains `false`. Non-pids
//!                 are `badarg`. This is stored-metadata observation, not DFLAG
//!                 exchange or socket/controller success.
//!   monitor_node/2,3 E8.2d/E8.2q: local monitor toggles still return true; a
//!                 foreign atom routes through the Vm owner so live `DistEntry`
//!                 state decides success vs `error:notalive` and owns later
//!                 `{nodedown,Node}` delivery. /3 accepts `[]` and bare
//!                 `[allow_passive_connect]`.
//!   new_connection/1 + abort_pending_connection/2 E8.2j: the no-socket pending
//!                 distribution connection handle surface. A valid foreign
//!                 node-name atom creates/reuses `{ConnId,Ref}` in the Vm's
//!                 pending dist-entry table; abort validates the same node/handle
//!                 identity and returns `true`, with wrong-node or malformed
//!                 handles raising `badarg`. This is not `setnode/2` and does
//!                 not promote a live channel.
//!   setnode/2 + create_dist_channel/3 E8.2k/E8.2m/E8.2r/E8.2s: the channel-start
//!                 surface. E8.2k pinned the direct no-pending observation:
//!                 `erlang:setnode/2` raises `badarg`, while
//!                 `erts_internal:create_dist_channel/3` returns atom `badarg`.
//!                 E8.2m routes valid-looking shapes through a Vm-owned pending
//!                 action; E8.2r promotes an existing pending entry only with a
//!                 live local controller pid and bounded `{DFlags,Creation}`;
//!                 E8.2s lets `setnode/2` install only a net_kernel-owned local
//!                 identity. No socket or remote process is installed.
//!   exit_signal/2,3 E8.2h/E8.2v: the lower-level signal surface. Local
//!                 pids and active local aliases route through the existing
//!                 `.exit_to` action; retired/plain refs drop after scheduler
//!                 resolution. Local ports route through `.port_close_sig`.
//!                 Foreign pid terms route through the Vm owner; without a live
//!                 matching `DistEntry` they remain inert `true`, and with one
//!                 they record a bounded outbound remote-exit observation.
//!                 Foreign refs remain inert `true`; foreign ports and bad
//!                 option lists reject with `badarg`. This is not a socket/TCP
//!                 delivery claim.
//!   dist_spawn_request/4 E8.2i: the no-carrier remote spawn doorway. It admits
//!                 only the direct OTP30 not-connected surface: validates node,
//!                 `{M,F,A}`, option-list grammar, and return mode; mints a
//!                 fresh request ref; returns `Ref` or `{Ref, SpawnsMonitor}`;
//!                 and enqueues the local `{Tag,Ref,error,noconnection|badopt}`
//!                 reply when OTP would. It does not install a carrier, create a
//!                 remote process, or claim connected-peer semantics.
//!   registered/0  e4-registered0 (repairs a latent unsoundness left by
//!                 E2.11/E3.8): `register/2` is NO LONGER `.stub` — it is the
//!                 Vm-owned `registry.Registry` bijection (`proc.zig`'s
//!                 `Vm.registry`), reachable end-to-end since E4.1's
//!                 scheduler-as-driver discharge. So the OLD E2.11 premise
//!                 ("nothing can ever be registered") is FALSE today, and
//!                 `registered()` must denote the ACTUAL registry contents —
//!                 the sorted list of registered name atoms. Sorted for the
//!                 SAME reason as `erlang:loaded/0` (bifs/code.zig): the
//!                 registry is a `std.AutoHashMapUnmanaged`, and a HashMap
//!                 iteration order must never leak into an observable BEAM
//!                 result (the ORDER-FREEDOM discipline). This BIF is
//!                 self-contained over a bare `Machine` (registry state lives
//!                 on the `Vm`, one level up — see `proc.zig`), so it traps
//!                 `list_registered` exactly like `processes/0` traps
//!                 `list_processes`; the Vm builds the sorted atom list and
//!                 writes it to x0.
//!   process_flag/2 the ONE flag implemented is `trap_exit`: reads/writes
//!                 `Machine.trap_exit` (a NEW single-process-scoped field —
//!                 see its doc comment on `Machine`), returning the OLD
//!                 value as the `true`/`false` atom, `badarg` on any other
//!                 flag name or a non-boolean value. Every other BEAM process
//!                 flag (`priority`, `min_heap_size`, `scheduler`, …) needs
//!                 process/scheduler state this Machine does not carry —
//!                 `badarg` for those too (an unrecognized-flag rejection,
//!                 not a silent no-op).
//!
//! ## The dispatch mechanism (unchanged — see `bifs/dispatch.zig`)
//! Process/system BIF rows use the same uniform `implOf`/`bif_call` mechanism as
//! every other family. Row-flip slices update the family functions, dispatch
//! arms, supported capability rows, `harness/bif_gen.ml`, and the generated
//! `bif_table.zig`; they do not add a second dispatch path.
//!
//! ## Laws (see the E2.11 suite below)
//!   - node()      routes through the Vm owner; the no-carrier observation is
//!     still the atom 'nonode@nohost'.
//!   - node(Pid|Port|Ref) returns the identity's encoded foreign node, or the
//!     VM-synchronized active local node for locally encoded identities after
//!     `setnode/2`; non-identities are `badarg`.
//!   - nodes()     == [], always, no args.
//!   - nodes(connected|visible|hidden|known|this) routes through the Vm owner
//!     when the selector observes peer or local distribution state; no-carrier
//!     values remain [] / ['nonode@nohost'] at the Vm boundary.
//!   - nodes(Type, #{node_type=>Bool,connection_id=>Bool}) routes through the
//!     Vm owner for local or remote selectors, rejects unknown map keys or
//!     non-boolean values, and never fabricates connected peers.
//!   - erts_internal:get_creation/0 routes through the Vm owner and is
//!     undefined until a real local distribution creation exists.
//!   - erts_internal:get_dflags/0 == the pinned OTP30 `{erts_dflags,...}`
//!     tuple observed on the non-distributed oracle; live peer DFLAG exchange is
//!     still outside this observer.
//!   - net_kernel:dflag_unicode_io/1 accepts only pid terms; a local pid returns
//!     true, and a foreign no-carrier pid returns false.
//!   - monitor_node/2,3 admits only atom node names, boolean flags, and the
//!     no-carrier-safe /3 options `[]` or `[allow_passive_connect]`; the local
//!     node returns true, and foreign atoms route through the Vm owner for the
//!     live/no-live decision.
//!   - new_connection/1 admits only foreign node-name atoms and returns a stable
//!     pending `{ConnId,Ref}` handle shape; abort_pending_connection/2 validates
//!     that shape and lets the Vm reject wrong-node handles with `badarg`.
//!   - setnode/2 and create_dist_channel/3 in the no-pending/no-net_kernel
//!     runtime reject before state install: setnode raises `badarg`,
//!     create_dist_channel returns atom `badarg`; `setnode/2` can install only a
//!     live registered `net_kernel`-owned local identity, and create_dist_channel
//!     may promote live only after that identity exists and with a live local
//!     controller owner.
//!   - exit_signal/2,3 admits only local pid/ref/port identities plus foreign
//!     pid/ref terms; foreign pids route through the Vm owner for live-carrier
//!     outbound exit observation while no-live/stale entries stay inert; /3
//!     accepts only a proper list of `priority` atoms, and foreign ids never
//!     alias local scheduler entities by numeric coincidence.
//!   - dist_spawn_request/4 on a foreign atom without a carrier returns the
//!     OTP30 direct-BIF request-ref shape, optionally sends the local
//!     noconnection/badopt reply, returns atom `badarg` for invalid direct
//!     inputs, and never creates remote or carrier state.
//!   - registered() == the sorted list of registered name atoms (e4-registered0;
//!     was `[]`-constant under E2.11 — that premise is now discharged, see the
//!     module doc-comment above).
//!   - process_flag(trap_exit, true/false) returns the OLD value (default
//!     `false` on a fresh Machine) and sets the new one; round-trip:
//!     process_flag(trap_exit, process_flag(trap_exit, X)) restores the
//!     ORIGINAL flag.
//!   - process_flag/2 REJECTS an unknown flag atom or a non-boolean value
//!     for `trap_exit` with `error.Badarg` (never a panic, never a silent
//!     accept).
//!
//! ## E6.5 (Task 5): the system introspection family
//! `statistics/1`, `system_info/1`, `system_flag/2`, `system_profile/0,2`,
//! `bump_reductions/1`, `erts_internal:scheduler_wall_time/1`, `system_monitor/1,3`
//! — pure readers/writers over EXISTING Machine state (the `reductions` counter +
//! the new `backtrace_depth`/`swt_enabled`/`sysmon`/`sysprof`/`stat_reds_last`
//! fields, the `trap_exit` single-process precedent). The host-nondeterministic
//! counter/setting VALUES are PROPERTY-FOLDED / version-INDEPENDENT (never
//! byte-asserted; `system_info` answers only wordsize/machine/endian/smp_support/
//! threads — W-11). See the family's section doc-comment below. DIVERGENCE 116.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const gc = @import("../gc.zig"); // e48-gc-literal-area: the real collector

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

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

fn raiseErrorAtom(m: *Machine, name: []const u8) BifError {
    const idx = m.ctx.atoms.intern(name) catch return error.OutOfMemory;
    return m.bifRaise(.error_, FinalTerms.atom(&m.ctx, idx));
}

/// `node/0` — local distribution identity is Vm-owned. The VM still reports
/// `nonode@nohost` until `setnode/2` installs a net_kernel-owned identity.
pub fn node_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .get_dist_node;
    return FinalTerms.nil(&m.ctx);
}

/// `erlang:is_alive/0` (DIVERGENCE 723) — is this node ALIVE (distributed)? erts
/// returns `true` once the node has a name (net_kernel started / setnode), else
/// `false`. VM-owned (the dist identity lives in the Vm), so this traps
/// `is_node_alive`; the scheduler answers `distLocalActive()`. Was `undef` (an
/// erlang.erl/net_kernel library wrapper, no bif.tab row on this pin).
pub fn is_alive_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .is_node_alive;
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the bool to x0
}

/// `erlang:get_cookie/0` (DIVERGENCE 722) — the magic-cookie observation. erts
/// returns `nocookie` until a cookie is set; zigvm has NO cookie/auth machinery
/// (its distribution is carrier-less and cookie-free — see the dist scope), so
/// the truthful value is ALWAYS `nocookie` (byte-EQ for a non-distributed node;
/// a disclosed EQUIV for a hypothetical cookie-bearing peer zigvm never models).
/// Was `undef` (an erlang.erl/auth library wrapper, no bif.tab row).
pub fn get_cookie_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return atomTerm(m, "nocookie");
}

/// `nodes/0` — connected-node observation is Vm-owned. No-carrier execution
/// still returns `[]`; live entries become observable after E8.2l promotion.
pub fn nodes_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .{ .list_dist_nodes = .{
        .connected = true,
        .visible = true,
        .hidden = false,
        .known = false,
        .this_node = false,
    } };
    return FinalTerms.nil(&m.ctx);
}

const NodeFilter = struct {
    connected: bool = false,
    visible: bool = false,
    hidden: bool = false,
    known: bool = false,
    this_node: bool = false,

    fn selectsRemote(self: NodeFilter) bool {
        return self.connected or self.visible or self.hidden;
    }

    fn selectsLocal(self: NodeFilter) bool {
        return self.known or self.this_node;
    }
};

fn addNodeFilterAtom(m: *Machine, f: *NodeFilter, opt: Term) bool {
    if (!FinalTerms.repIsAtom(opt)) return false;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(opt));
    if (std.mem.eql(u8, name, "connected")) {
        f.connected = true;
        return true;
    }
    if (std.mem.eql(u8, name, "visible")) {
        f.visible = true;
        return true;
    }
    if (std.mem.eql(u8, name, "hidden")) {
        f.hidden = true;
        return true;
    }
    if (std.mem.eql(u8, name, "known")) {
        f.known = true;
        return true;
    }
    if (std.mem.eql(u8, name, "this")) {
        f.this_node = true;
        return true;
    }
    return false;
}

fn parseNodeFilter(m: *Machine, w: Term) ?NodeFilter {
    var out = NodeFilter{};
    if (FinalTerms.repIsAtom(w)) {
        return if (addNodeFilterAtom(m, &out, w)) out else null;
    }
    var cur = w;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        if (!addNodeFilterAtom(m, &out, FinalTerms.listHead(&m.ctx, cur))) return null;
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    return if (FinalTerms.kindOf(&m.ctx, cur) == .nil) out else null;
}

fn localNodeAtom(m: *Machine) BifError!Term {
    return atomTerm(m, "nonode@nohost");
}

fn localNodesList(m: *Machine, f: NodeFilter) BifError!Term {
    if (!f.selectsLocal()) return FinalTerms.nil(&m.ctx);
    return FinalTerms.cons(&m.ctx, try localNodeAtom(m), FinalTerms.nil(&m.ctx)) catch return error.OutOfMemory;
}

/// `nodes/1` — filters that can observe peers or the local distributed node
/// route through the Vm owner so `DistEntry` rows and the local `setnode/2`
/// identity remain single-source.
pub fn nodes_1(m: *Machine, args: []const Term) BifError!Term {
    const f = parseNodeFilter(m, args[0]) orelse return error.Badarg;
    if (!f.selectsRemote() and !f.selectsLocal()) return FinalTerms.nil(&m.ctx);
    m.pending = .{ .list_dist_nodes = .{
        .connected = f.connected,
        .visible = f.visible,
        .hidden = f.hidden,
        .known = f.known,
        .this_node = f.this_node,
    } };
    return FinalTerms.nil(&m.ctx);
}

const NodesInfoOpts = struct {
    node_type: bool = false,
    connection_id: bool = false,
};

fn parseNodesInfoOpts(m: *Machine, opts: Term) ?NodesInfoOpts {
    if (!FinalTerms.repIsMap(&m.ctx, opts)) return null;
    const n = FinalTerms.mapSize(&m.ctx, opts);
    if (n > 2) return null;
    var keys: [2]Term = undefined;
    var vals: [2]Term = undefined;
    const got = FinalTerms.mapPairs(&m.ctx, opts, keys[0..], vals[0..]);
    var out = NodesInfoOpts{};
    for (0..got) |i| {
        if (!FinalTerms.repIsAtom(keys[i])) return null;
        const requested = asBool(m, vals[i]) orelse return null;
        const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(keys[i]));
        if (std.mem.eql(u8, name, "node_type")) {
            out.node_type = requested;
        } else if (std.mem.eql(u8, name, "connection_id")) {
            out.connection_id = requested;
        } else {
            return null;
        }
    }
    return out;
}

fn nodesInfoMap(m: *Machine, opts: NodesInfoOpts) BifError!Term {
    var keys: [2]Term = undefined;
    var vals: [2]Term = undefined;
    var n: usize = 0;
    if (opts.connection_id) {
        keys[n] = try atomTerm(m, "connection_id");
        vals[n] = try atomTerm(m, "undefined");
        n += 1;
    }
    if (opts.node_type) {
        keys[n] = try atomTerm(m, "node_type");
        vals[n] = try atomTerm(m, "this");
        n += 1;
    }
    return FinalTerms.mapNew(&m.ctx, keys[0..n], vals[0..n]) catch return error.OutOfMemory;
}

/// `nodes/2` — `nodes(Type, OptMap)`. Filters that can observe peers or the
/// local distributed node route through the Vm owner so live `DistEntry`
/// metadata and local identity share one authority. Unknown keys or
/// non-boolean values are `badarg`.
pub fn nodes_2(m: *Machine, args: []const Term) BifError!Term {
    const f = parseNodeFilter(m, args[0]) orelse return error.Badarg;
    const opts = parseNodesInfoOpts(m, args[1]) orelse return error.Badarg;
    if (!f.selectsRemote() and !f.selectsLocal()) return FinalTerms.nil(&m.ctx);
    m.pending = .{ .list_dist_node_infos = .{
        .connected = f.connected,
        .visible = f.visible,
        .hidden = f.hidden,
        .known = f.known,
        .this_node = f.this_node,
        .node_type = opts.node_type,
        .connection_id = opts.connection_id,
    } };
    return FinalTerms.nil(&m.ctx);
}

/// `erts_internal:get_creation/0` — local dist creation is Vm-owned and
/// `undefined` until `setnode/2` installs the local identity.
pub fn get_creation_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .get_dist_creation;
    return FinalTerms.nil(&m.ctx);
}

const otp30_dflags_default: i64 = 468283523004;
const otp30_dflags_mandatory: i64 = 17230663572;
const otp30_dflags_addable: i64 = 468283523004;
const otp30_dflags_rejectable: i64 = 8396866;
const otp30_dflags_strict_order: i64 = 8192;

/// `erts_internal:get_dflags/0` — the pinned OTP30 non-distributed DFLAG record.
/// The values are exact for the local OTP30 oracle selected by the harness.
pub fn get_dflags_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.tuple(&m.ctx, &.{
        try atomTerm(m, "erts_dflags"),
        FinalTerms.int(&m.ctx, otp30_dflags_default),
        FinalTerms.int(&m.ctx, otp30_dflags_mandatory),
        FinalTerms.int(&m.ctx, otp30_dflags_addable),
        FinalTerms.int(&m.ctx, otp30_dflags_rejectable),
        FinalTerms.int(&m.ctx, otp30_dflags_strict_order),
    }) catch return error.OutOfMemory;
}

fn pidIsOnLocalNode(m: *Machine, w: Term) bool {
    return FinalTerms.repIsPid(&m.ctx, w) and
        FinalTerms.pidCreation(&m.ctx, w) == 0 and
        std.mem.eql(u8, FinalTerms.pidNodeName(&m.ctx, w), ta.local_node_name);
}

fn exitSignalIdentityIsLocal(m: *Machine, w: Term) bool {
    if (FinalTerms.repIsPid(&m.ctx, w))
        return FinalTerms.pidCreation(&m.ctx, w) == 0 and
            std.mem.eql(u8, FinalTerms.pidNodeName(&m.ctx, w), ta.local_node_name);
    if (FinalTerms.repIsRef(&m.ctx, w))
        return FinalTerms.refCreation(&m.ctx, w) == 0 and
            std.mem.eql(u8, FinalTerms.refNodeName(&m.ctx, w), ta.local_node_name);
    if (FinalTerms.repIsPort(&m.ctx, w))
        return FinalTerms.portCreation(&m.ctx, w) == 0 and
            std.mem.eql(u8, FinalTerms.portNodeName(&m.ctx, w), ta.local_node_name);
    return false;
}

fn exitSignalOptsOk(m: *Machine, opts: Term) bool {
    var cur = opts;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const opt = FinalTerms.listHead(&m.ctx, cur);
        if (!FinalTerms.repIsAtom(opt)) return false;
        if (!std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(opt)), "priority")) return false;
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    return FinalTerms.kindOf(&m.ctx, cur) == .nil;
}

fn exitSignal(m: *Machine, id: Term, reason: Term, opts: Term) BifError!Term {
    if (!exitSignalOptsOk(m, opts)) return error.Badarg;
    if (FinalTerms.repIsPid(&m.ctx, id)) {
        if (exitSignalIdentityIsLocal(m, id)) {
            m.pending = .{ .exit_to = .{ .pid = id, .reason = reason } };
        } else {
            m.pending = .{ .remote_exit_signal = .{ .pid = id, .reason = reason } };
        }
        return boolTerm(m, true);
    }
    if (FinalTerms.repIsRef(&m.ctx, id)) {
        if (exitSignalIdentityIsLocal(m, id)) {
            m.pending = .{ .exit_to = .{ .pid = id, .reason = reason } };
        }
        return boolTerm(m, true);
    }
    if (FinalTerms.repIsPort(&m.ctx, id)) {
        if (!exitSignalIdentityIsLocal(m, id)) return error.Badarg;
        m.pending = .{ .port_close_sig = .{ .port = id } };
        return boolTerm(m, true);
    }
    return error.Badarg;
}

/// `net_kernel:dflag_unicode_io/1` — local pids observe this node's unicode-io
/// capability directly; foreign pids route through the Vm owner so live peer
/// DFLAGS are read from `DistEntry` metadata only.
pub fn dflag_unicode_io_1(m: *Machine, args: []const Term) BifError!Term {
    const pid = args[0];
    if (!FinalTerms.repIsPid(&m.ctx, pid)) return error.Badarg;
    if (pidIsOnLocalNode(m, pid)) return boolTerm(m, true);
    m.pending = .{ .dist_dflag_unicode_io = .{ .pid = pid } };
    return FinalTerms.nil(&m.ctx);
}

fn nodeNameOf(m: *Machine, node: Term) ?[]const u8 {
    if (!FinalTerms.repIsAtom(node)) return null;
    return m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(node));
}

fn isDistNodeNameAtom(m: *Machine, node: Term) bool {
    const name = nodeNameOf(m, node) orelse return false;
    if (std.mem.eql(u8, name, ta.local_node_name)) return false;
    const at = std.mem.indexOfScalar(u8, name, '@') orelse return false;
    return at > 0 and at + 1 < name.len;
}

fn monitorNodeOptsOk(m: *Machine, opts: Term) bool {
    var cur = opts;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const opt = FinalTerms.listHead(&m.ctx, cur);
        if (!FinalTerms.repIsAtom(opt)) return false;
        if (!std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(opt)), "allow_passive_connect")) return false;
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    return FinalTerms.kindOf(&m.ctx, cur) == .nil;
}

fn monitorNodeBridge(m: *Machine, node: Term, flag: Term, opts: Term) BifError!Term {
    const enabled = asBool(m, flag) orelse return error.Badarg;
    if (!monitorNodeOptsOk(m, opts)) return error.Badarg;
    const name = nodeNameOf(m, node) orelse return error.Badarg;
    if (std.mem.eql(u8, name, ta.local_node_name)) return boolTerm(m, true);
    m.pending = .{ .monitor_dist_node = .{ .node = node, .enabled = enabled } };
    return FinalTerms.nil(&m.ctx);
}

/// `monitor_node/2` — local monitor toggles are accepted directly; remote atoms
/// route through the Vm carrier owner so live entries, no-carrier `notalive`,
/// and later `{nodedown,Node}` delivery share one authority.
pub fn monitor_node_2(m: *Machine, args: []const Term) BifError!Term {
    return monitorNodeBridge(m, args[0], args[1], FinalTerms.nil(&m.ctx));
}

/// `monitor_node/3` — same live bridge as /2; host also accepts the bare
/// `allow_passive_connect` option before a distribution carrier exists.
pub fn monitor_node_3(m: *Machine, args: []const Term) BifError!Term {
    return monitorNodeBridge(m, args[0], args[1], args[2]);
}

/// `registered/0` — see the module doc-comment (e4-registered0): the registry
/// bijection lives on the Vm, not the Machine, so this traps `list_registered`
/// (the same shape as `processes_0`'s `list_processes` trap) and the Vm
/// (`proc.zig`) writes the SORTED name-atom list to x0.
pub fn registered_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .list_registered;
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the sorted list to x0
}

/// `process_flag/2` — the `trap_exit` flag only (see module doc-comment).
/// Returns the OLD value; `badarg` on any other flag or a non-boolean value.
pub fn process_flag_2(m: *Machine, args: []const Term) BifError!Term {
    const flag = args[0];
    if (!FinalTerms.repIsAtom(flag)) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(flag));
    if (std.mem.eql(u8, name, "trap_exit")) {
        const val = asBool(m, args[1]) orelse return error.Badarg;
        const old = m.trap_exit;
        m.trap_exit = val;
        return boolTerm(m, old);
    }
    if (std.mem.eql(u8, name, "apoptosis_immune")) {
        const val = asBool(m, args[1]) orelse return error.Badarg;
        const old = m.apoptosis_immune;
        m.apoptosis_immune = val;
        return boolTerm(m, old);
    }
    // gap-eep76-priority-flag (DIVERGENCE 602): `process_flag(priority, Level)` —
    // Level ∈ {low, normal, high, max}; returns the OLD priority atom (default
    // `normal`), stores the new one. A non-atom / unknown level → badarg (matching
    // pinned OTP-30). The scheduler does not weight run-queues by it yet (bound).
    if (std.mem.eql(u8, name, "priority")) {
        if (!FinalTerms.repIsAtom(args[1])) return error.Badarg;
        const lvl = ia.ProcPriority.fromName(m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[1]))) orelse return error.Badarg;
        const old = m.priority;
        m.priority = lvl;
        return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern(old.name()));
    }
    // gap-atom-and-heap-limits: `process_flag(max_heap_size, N | Map)` — the flag
    // CONFIG round-trip (returns the OLD value as the 4-key erts map). An integer
    // sets `size` (0 = disabled); a map sets any subset of {size, kill,
    // error_logger, include_shared_binaries}. Negative size / non-int-non-map /
    // a present key of the wrong type → badarg. The ENFORCEMENT (kill +
    // error_logger when the heap exceeds `size`) and the set-time
    // "size < current heap → badarg" floor are the deferred follow-on (documented).
    if (std.mem.eql(u8, name, "max_heap_size")) {
        const old = m.max_heap_size;
        var neu = old;
        const v = args[1];
        if (FinalTerms.repIsSmall(v)) {
            const n = FinalTerms.smallValOf(v);
            if (n < 0) return error.Badarg;
            neu.size = @intCast(n);
        } else if (FinalTerms.repIsMap(&m.ctx, v)) {
            if (mapGetName(m, v, "size")) |sz| {
                if (!FinalTerms.repIsSmall(sz)) return error.Badarg;
                const n = FinalTerms.smallValOf(sz);
                if (n < 0) return error.Badarg;
                neu.size = @intCast(n);
            }
            if (mapGetName(m, v, "kill")) |k| neu.kill = asBool(m, k) orelse return error.Badarg;
            if (mapGetName(m, v, "error_logger")) |e| neu.error_logger = asBool(m, e) orelse return error.Badarg;
            if (mapGetName(m, v, "include_shared_binaries")) |i| neu.include_shared_binaries = asBool(m, i) orelse return error.Badarg;
        } else return error.Badarg;
        m.max_heap_size = neu;
        return maxHeapMap(m, old);
    }
    // DIVERGENCE 707: min_heap_size / min_bin_vheap_size — a non-negative int
    // CONFIG round-trip (returns the OLD value, stores the new); enforcement
    // deferred like max_heap_size. A negative or non-int → badarg (OTP-30).
    if (std.mem.eql(u8, name, "min_heap_size")) {
        if (!FinalTerms.repIsSmall(args[1])) return error.Badarg;
        const n = FinalTerms.smallValOf(args[1]);
        if (n < 0) return error.Badarg;
        const old = m.min_heap_size;
        m.min_heap_size = n;
        return FinalTerms.int(&m.ctx, old);
    }
    if (std.mem.eql(u8, name, "min_bin_vheap_size")) {
        if (!FinalTerms.repIsSmall(args[1])) return error.Badarg;
        const n = FinalTerms.smallValOf(args[1]);
        if (n < 0) return error.Badarg;
        const old = m.min_bin_vheap_size;
        m.min_bin_vheap_size = n;
        return FinalTerms.int(&m.ctx, old);
    }
    // message_queue_data ∈ {on_heap, off_heap} — returns the OLD atom (default
    // on_heap, consistent with process_info(_, message_queue_data)). Any other
    // value → badarg. (erts also allows `mixed`; unmodeled → badarg, disclosed.)
    if (std.mem.eql(u8, name, "message_queue_data")) {
        if (!FinalTerms.repIsAtom(args[1])) return error.Badarg;
        const vn = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[1]));
        const off = if (std.mem.eql(u8, vn, "off_heap")) true else if (std.mem.eql(u8, vn, "on_heap")) false else return error.Badarg;
        const old = m.mqd_off_heap;
        m.mqd_off_heap = off;
        return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern(if (old) "off_heap" else "on_heap"));
    }
    // sensitive ∈ {true, false} — a genuinely-truthful per-process bool, returns
    // the OLD value (default false; zigvm has no tracing to suppress, so it is
    // an honest accept+round-trip).
    if (std.mem.eql(u8, name, "sensitive")) {
        const val = asBool(m, args[1]) orelse return error.Badarg;
        const old = m.sensitive;
        m.sensitive = val;
        return boolTerm(m, old);
    }
    return error.Badarg;
}

/// `map_get(Map, atom(Name))` — the value or null (a small typed accessor).
fn mapGetName(m: *Machine, map: Term, name: []const u8) ?Term {
    const key = FinalTerms.atom(&m.ctx, m.ctx.atoms.intern(name) catch return null);
    return FinalTerms.mapGet(&m.ctx, map, key);
}

/// Build the erts `max_heap_size` config MAP (`#{error_logger, include_shared_
/// binaries, kill, size}`) from a `MaxHeapCfg` (map key order is irrelevant to
/// equality; this is the exact 4-key shape `process_flag`/`process_info` return).
fn maxHeapMap(m: *Machine, cfg: ia.MaxHeapCfg) BifError!Term {
    const keys = [_]Term{
        FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("error_logger")),
        FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("include_shared_binaries")),
        FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("kill")),
        FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("size")),
    };
    const vals = [_]Term{
        boolTerm(m, cfg.error_logger),
        boolTerm(m, cfg.include_shared_binaries),
        boolTerm(m, cfg.kill),
        FinalTerms.int(&m.ctx, @intCast(cfg.size)),
    };
    return FinalTerms.mapNew(&m.ctx, &keys, &vals) catch error.OutOfMemory;
}

// ============================================================================
// E3.7: the process bridge BIFs — self/spawn/send/exit over proc.zig's scheduler
// ============================================================================
//
// SCOPE / ledger honesty (coordinator-confirmed option B). These BIFs implement
// the FUNCTIONAL process semantics over the M7 `proc.zig` bridge — pid TERMs
// (Task 5) name real `proc` processes, `send` delivers to a pid's mailbox, the
// scheduler runs each process's Machine to a reduction budget, and the E1.11
// receive save-pointer wakes on delivery. But the ONLY two rows that flip EQ in
// the ledger are `self/0` and `node/1`: they are the sole process BIFs reachable
// end-to-end from a compiled `.beam` TODAY (`bif0`/`bif1`). Every other row here
// (`spawn/1,3`, `spawn_link/1,3`, `spawn_opt/4`, `!/2`, `send/2,3`, `exit/1,2`,
// `is_process_alive/1`, `processes/0`) is compiled as `call_ext` — and
// `call_ext`/`call_ext_only`/`call_ext_last` still translate to `func_info` (a
// crash) pending Task 12's BIF-dispatch + `M:F/A`→label resolution. So those
// rows stay `deferred-E4-procdispatch` (→ Task 12/E4) in `harness/bif_gen.ml`, EVEN
// THOUGH the functions are implemented and law-proven through the Vm here: EQ
// means proven end-to-end equivalent, and a row a compiled `.beam` cannot yet
// reach is a false-EQ (the exact UCA of this task's §10 safety packet). Task 12
// is the pin where they become end-to-end AND the eunit-spawn thread completes.
//
// E4.1 UPDATE (scheduler-as-driver, DIVERGENCE entry 34): the per-fn
// `deferred-E4-procdispatch` tags below are now DISCHARGED for 19 of these rows —
// they flip EQ and are reachable end-to-end from a compiled `.beam` through the
// E3.12 `call_ext_bif` path + the scheduler-as-driver (`cli.runMulti` →
// `proc.Scheduler.drive`), with `spawn/3` resolving its MFA over the live export
// index (`proc.resolveSpawnMFA`). The bodies here are UNCHANGED; only their
// dispatch reachability changed. E21.1 (DIVERGENCE 450) makes `spawn/1` +
// `spawn_link/1` (fun-spawn) reachable too — but as erlang.erl LIBRARY wrappers
// via `dispatch.resolveLibrary` (NOT bif.tab rows, ledger-invisible like
// spawn_monitor): the `spawn_fun` trap was Vm-law-proven since E3.7 but reached
// NEITHER resolve table, so a compiled `spawn(fun...)` fell through to
// `call_ext_code` → `undef`. Wiring the resolveLibrary arm makes them EQ
// end-to-end (`pspawn_fun`/`plink_fun` corpus). The rows that STAY
// deferred (re-bound to precise
// blockers `deferred-E4-{io,boot,procinfo,spawnreq}`) are: `processes/0`,
// `process_info/1,2`, `group_leader/0`, `erts_internal:group_leader/2,3`,
// `erts_internal:process_flag/3`, `spawn_request/4`, `spawn_request_abandon/1` —
// each with an observable divergence (GL identity / pid-value repr / item-subset /
// async-ref) owned by a later E4 task or E5. See `harness/bif_gen.ml`.
//
// The trapping mechanism: a process BIF that needs the scheduler (spawn/exit/…)
// sets `m.pending = <ia.Action>` and returns a placeholder; the `bif_call`
// executor writes the placeholder to the BIF's `dst`, the run loop stops (pending
// != null), and `proc.zig`'s `interpret` performs the effect — writing any RESULT
// to x0 (`regs[0]`), the BEAM call-return convention. `send`/`exit_2` return their
// value DIRECTLY (BEAM `send` returns the message; `exit/2` returns `true`), so
// they do not depend on the x0 write. The pid TERM's `number` field IS the proc
// index — the total, law-covered pid↔process mapping (see `proc.pidOfTerm`).

fn isLocalPid(m: *Machine, w: Term) bool {
    return FinalTerms.repIsPid(&m.ctx, w);
}

/// E5.8 (Task 8): a valid `send/2,3` DESTINATION — a local pid, a REFERENCE
/// (alias, E5.5), or an ATOM (a registered name, `Name ! Msg`, DIVERGENCE
/// entry 50(a)). The scheduler's `resolveSendTarget` performs the actual
/// name/alias→pid resolution; this only admits the trap. (The `!` operator
/// compiles to the `send` OPCODE, which needs no such guard; this widens the
/// explicit `erlang:send/2,3` BIF path to the SAME destination domain.)
fn isSendDest(m: *Machine, w: Term) bool {
    return FinalTerms.repIsPid(&m.ctx, w) or FinalTerms.repIsRef(&m.ctx, w) or FinalTerms.repIsAtom(w);
}

/// `self/0` — the running process's own pid TERM. SELF-CONTAINED (no scheduler
/// trap): the pid's `number` is the Machine's proc index (`m.self_pid`), set by
/// `proc.Vm.spawn`. This is the one spawn-family row reachable via `bif0` today,
/// so it flips EQ. `serial` is 0 (single incarnation — external/remote pids E5).
pub fn self_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.pid(&m.ctx, m.self_pid, 0) catch return error.Badarg;
}

fn localIdentityNodeIdx(m: *Machine, w: Term) ?ta.AtomIdx {
    if (FinalTerms.repIsPid(&m.ctx, w)) {
        if (FinalTerms.pidCreation(&m.ctx, w) == 0 and
            std.mem.eql(u8, FinalTerms.pidNodeName(&m.ctx, w), ta.local_node_name))
            return m.dist_local_node;
    } else if (FinalTerms.repIsPort(&m.ctx, w)) {
        if (FinalTerms.portCreation(&m.ctx, w) == 0 and
            std.mem.eql(u8, FinalTerms.portNodeName(&m.ctx, w), ta.local_node_name))
            return m.dist_local_node;
    } else if (FinalTerms.repIsRef(&m.ctx, w)) {
        if (FinalTerms.refCreation(&m.ctx, w) == 0 and
            std.mem.eql(u8, FinalTerms.refNodeName(&m.ctx, w), ta.local_node_name))
            return m.dist_local_node;
    }
    return null;
}

/// `node/1` — the node a pid/port/ref lives on. E5.7 returns the identity's
/// encoded foreign node atom. E8.2t keeps the direct BIF contract while
/// observing the VM-owned local distribution identity: a locally encoded
/// pid/port/ref maps to `m.dist_local_node` after `setnode/2`, and to
/// `nonode@nohost` before it. A non-identity argument is `badarg`.
pub fn node_1(m: *Machine, args: []const Term) BifError!Term {
    const w = args[0];
    if (localIdentityNodeIdx(m, w)) |idx| return FinalTerms.atom(&m.ctx, idx);
    const node_idx = if (FinalTerms.repIsPid(&m.ctx, w))
        FinalTerms.pidNode(&m.ctx, w)
    else if (FinalTerms.repIsPort(&m.ctx, w))
        FinalTerms.portNode(&m.ctx, w)
    else if (FinalTerms.repIsRef(&m.ctx, w))
        FinalTerms.refNode(&m.ctx, w)
    else
        return error.Badarg;
    return FinalTerms.atom(&m.ctx, node_idx);
}

/// `spawn/1` — spawn a fun `F` as a new process running `F()`. Traps `spawn_fun`;
/// the scheduler creates a fresh Machine at the fun's label (env copied cross-heap)
/// and writes the CHILD pid to x0. E21.1: wired via `dispatch.resolveLibrary` (an
/// erlang.erl LIBRARY wrapper, NOT a bif.tab row — ledger-invisible like
/// spawn_monitor; was never wired, so a compiled `spawn(fun...)` resolved to
/// `undef`) → EQ end-to-end (`pspawn_fun` corpus + FUN-SPAWN CLOSURE law).
/// DIVERGENCE 450.
pub fn spawn_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsFun(&m.ctx, args[0])) return error.Badarg;
    m.pending = .{ .spawn_fun = .{ .fun = args[0], .link = false } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the pid to x0
}

/// `spawn_link/1` — `spawn/1` + an atomic bidirectional link to the child. E21.1:
/// wired via `dispatch.resolveLibrary` (erlang.erl wrapper) → EQ end-to-end
/// (`plink_fun` corpus: trap_exit/'EXIT' propagation from a spawn_link'd fun).
/// DIVERGENCE 450.
pub fn spawn_link_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsFun(&m.ctx, args[0])) return error.Badarg;
    m.pending = .{ .spawn_fun = .{ .fun = args[0], .link = true } };
    return FinalTerms.nil(&m.ctx);
}

/// `spawn/3` — spawn `M:F/arity(Args)`. Traps `spawn_mfa`; MFA→entry resolution
/// is Task 12 (the code server), so the scheduler currently returns a valid pid
/// whose process immediately exits `undef` (BEAM-faithful for an unresolvable
/// MFA). `deferred-E4-procdispatch`.
pub fn spawn_3(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .spawn_mfa = .{ .module = args[0], .func = args[1], .args = args[2], .link = false } };
    return FinalTerms.nil(&m.ctx);
}

/// `spawn_link/3` — `spawn/3` + link.
pub fn spawn_link_3(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .spawn_mfa = .{ .module = args[0], .func = args[1], .args = args[2], .link = true } };
    return FinalTerms.nil(&m.ctx);
}

/// Scan a proper option list for the `link` atom (the LOCAL `spawn_opt` subset:
/// link/monitor flags that need neither dist nor SMP; `monitor`/`priority`/heap
/// opts are accepted-and-ignored here, documented as the deferred remainder).
fn optsHaveLink(m: *Machine, opts: Term) bool {
    var cur = opts;
    var guard: usize = 0;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons and guard < 64) : (guard += 1) {
        const head = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.repIsAtom(head)) {
            const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(head));
            if (std.mem.eql(u8, name, "link")) return true;
        }
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    return false;
}

/// E5.8 (Task 8): scan a proper option list for the `monitor` atom (the
/// `spawn_opt(_,_,_,[monitor])` form — the primitive `spawn_monitor` expands to).
/// `{monitor, _Opts}` tuples (alias-monitor spawn opts) are accepted as a plain
/// monitor request (their extra options are a documented deferral, the
/// `spawn_opt` link-subset precedent). DIVERGENCE entry 50(c).
fn optsHaveMonitor(m: *Machine, opts: Term) bool {
    var cur = opts;
    var guard: usize = 0;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons and guard < 64) : (guard += 1) {
        const head = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.repIsAtom(head)) {
            if (std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(head)), "monitor")) return true;
        } else if (FinalTerms.kindOf(&m.ctx, head) == .tuple and FinalTerms.tupleArity(&m.ctx, head) == 2) {
            const tag = FinalTerms.tupleElem(&m.ctx, head, 0);
            if (FinalTerms.repIsAtom(tag) and std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(tag)), "monitor")) return true;
        }
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    return false;
}

/// `spawn_opt/4` — `spawn_opt(M, F, Args, Opts)`, the LOCAL opts subset. The
/// `link` and `monitor` flags are honored (neither needs dist/SMP); a `monitor`
/// opt makes the trap return `{Pid, Ref}` (E5.8). The rest are
/// accepted-and-ignored (documented deferral). `deferred-E4-procdispatch`.
pub fn spawn_opt_4(m: *Machine, args: []const Term) BifError!Term {
    const link = optsHaveLink(m, args[3]);
    const monitor = optsHaveMonitor(m, args[3]);
    m.pending = .{ .spawn_mfa = .{ .module = args[0], .func = args[1], .args = args[2], .link = link, .monitor = monitor } };
    return FinalTerms.nil(&m.ctx);
}

/// E5.8 (Task 8): `spawn_monitor/3` — the erlang.erl LIBRARY WRAPPER
/// `spawn_monitor(M,F,A) -> erlang:spawn_opt(M,F,A,[monitor])`. NOT a bif.tab BIF
/// (so ledger-invisible — the apply/3 precedent), reached via the loader's
/// library-wrapper expansion (bifs/dispatch.resolveLibrary). Traps `spawn_mfa`
/// with `monitor = true`; the scheduler returns `{Pid, Ref}`. DIVERGENCE 50(c).
pub fn spawn_monitor_3(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0]) or !FinalTerms.repIsAtom(args[1])) return error.Badarg;
    m.pending = .{ .spawn_mfa = .{ .module = args[0], .func = args[1], .args = args[2], .link = false, .monitor = true } };
    return FinalTerms.nil(&m.ctx);
}

/// E5.8 (Task 8): `spawn_monitor/1` — `spawn_monitor(F) ->
/// erlang:spawn_opt(erlang,apply,[F,[]],[monitor])`. Traps `spawn_fun` with
/// `monitor = true`; returns `{Pid, Ref}`.
pub fn spawn_monitor_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsFun(&m.ctx, args[0])) return error.Badarg;
    m.pending = .{ .spawn_fun = .{ .fun = args[0], .link = false, .monitor = true } };
    return FinalTerms.nil(&m.ctx);
}

/// `send/2` (== `erlang:'!'/2`) — deliver `Msg` to `Pid`'s mailbox. Traps
/// `send_to`; the scheduler copies the message cross-heap (the M1 copy law at the
/// send boundary) and enqueues it per-pair-ordered. Returns `Msg` DIRECTLY (BEAM
/// contract). A send to a dead/absent pid is silently dropped (never a crash).
pub fn send_2(m: *Machine, args: []const Term) BifError!Term {
    if (!isSendDest(m, args[0])) return error.Badarg;
    m.pending = .{ .send_to = .{ .pid = args[0], .msg = args[1] } };
    return args[1];
}

/// `erlang:'!'/2` — the operator form of `send/2`.
pub fn bang_2(m: *Machine, args: []const Term) BifError!Term {
    return send_2(m, args);
}

/// `send/3` — `send(Pid, Msg, Opts)`. Same delivery; the LOCAL opts (`nosuspend`,
/// `noconnect`) are no-ops with no dist/SMP. Returns the atom `ok` (BEAM contract).
pub fn send_3(m: *Machine, args: []const Term) BifError!Term {
    if (!isSendDest(m, args[0])) return error.Badarg;
    m.pending = .{ .send_to = .{ .pid = args[0], .msg = args[1] } };
    const ok = try m.ctx.atoms.intern("ok");
    return FinalTerms.atom(&m.ctx, ok);
}

// ── E6.2 (Task 2): the LIVE receive/BIF timer family ─────────────────────────
// `send_after`/`start_timer` arm a `timer_wheel` entry that delivers a message
// (or `{timeout,TRef,Msg}`) to `Dest` after `Time` ms; `cancel_timer`/`read_timer`
// observe/retire a still-live entry by its TRef. Each TRAPS an ia.Action the Vm
// (proc.zig) interprets against its virtual-clock timer table — a bare Machine
// cannot reach the wheel (the `spawn`/`send` precedent). DIVERGENCE entry 5 +
// the 8 `deferred-E6` timer rows. `Time` must be a non-negative integer; `Dest`
// a pid or a registered-name atom (the `send`/`resolveSendTarget` domain).

fn isTimerDest(m: *Machine, w: Term) bool {
    return FinalTerms.repIsPid(&m.ctx, w) or FinalTerms.repIsAtom(w);
}

// --------------------------------------------------------------------------
// Timer BIF option parsing — the OTP-30 `parse_bif_timer_options` model.
//
// SEMANTIC DOMAIN. A timer-BIF options list is a PROPER list of `{Key, Bool}`
// 2-tuples over the three keys `async` / `info` / `abs`. It denotes a settings
// record `⟦opts⟧ = {is_async, info, abs}` folded left over the list (later
// entries override earlier ones), starting from the OTP defaults
// `{async=false, info=true, abs=false}`. It is a PARTIAL function: a non-tuple
// element, a non-2 arity, a non-atom key, a non-boolean value, an UNGATED key,
// or an improper tail all map to ⊥ (`badarg`).
//
// The crux — PER-BIF KEY GATING (this is where a real bug hid, e24-t7). OTP's
// `erl_hl_timer.c:parse_bif_timer_options` (@2352) does NOT accept the same
// keys for every timer BIF: it takes an `int*` per key and treats a NULL
// pointer as "this key is a badarg for this caller" (`case am_info: if (!info
// || !bool_arg(...)) return 0;`). So the SAME option name is valid for one BIF
// and a `badarg` for another:
//   send_after/4, start_timer/4 : parse(_, async=NULL, info=NULL, &abs )  → only {abs,_}
//   cancel_timer/2              : parse(_, &async,     &info,     NULL )  → {async,_}+{info,_}
//   read_timer/2                : parse(_, &async,     info=NULL, NULL )  → only {async,_}
// We model the NULL/non-NULL C pointers as a `TimerOptGate` of accept-flags.
// The pre-e24-t7 code collapsed cancel/read onto ONE parser that accepted both
// `async` AND `info`, so `read_timer(Ref, [{info,_}])` was wrongly accepted —
// OTP rejects it (`info` pointer is NULL). See DIVERGENCE_LOG entry 89-adjacent
// note / the e24-t7 slice; the gate makes the model exact.
//
// OTP CORRELATION. `bool_arg` (@2342) accepts ONLY `am_true`/`am_false` — our
// `asBool` is byte-identical. `arityval(tp[0]) != 2` → 0 is our arity!=2 guard;
// `is_not_tuple(opt)` → our kind!=tuple guard; `is_not_nil(list)` tail check →
// our final nil guard; the `default:` switch arm → our `else` (ungated key).
// The one honest boundary: OTP loops with no length cap; we bound the walk at
// 16 (a hang is a failed law — cyclic-list safety), far beyond the 3 real keys.

const TimerOptGate = struct { async: bool = false, info: bool = false, abs: bool = false };
const TimerOptInfo = struct { is_async: bool = false, info: bool = true, abs: bool = false };

/// Parse a timer-BIF options list against a per-BIF key `gate` (OTP's NULL/
/// non-NULL pointer set). Returns the folded settings, or null (`badarg`) on any
/// malformed element, non-boolean value, UNGATED key, or improper tail.
fn parseTimerOptions(m: *Machine, opts: Term, gate: TimerOptGate) ?TimerOptInfo {
    var out = TimerOptInfo{};
    var cur = opts;
    var guard: usize = 0;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons and guard < 16) : (guard += 1) {
        const head = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.kindOf(&m.ctx, head) != .tuple) return null;
        if (FinalTerms.tupleArity(&m.ctx, head) != 2) return null;
        const key = FinalTerms.tupleElem(&m.ctx, head, 0);
        const val = FinalTerms.tupleElem(&m.ctx, head, 1);
        if (!FinalTerms.repIsAtom(key)) return null;
        const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(key));
        if (gate.async and std.mem.eql(u8, name, "async")) {
            out.is_async = asBool(m, val) orelse return null;
        } else if (gate.info and std.mem.eql(u8, name, "info")) {
            out.info = asBool(m, val) orelse return null;
        } else if (gate.abs and std.mem.eql(u8, name, "abs")) {
            out.abs = asBool(m, val) orelse return null;
        } else return null; // ungated/unknown key → OTP `default: return 0`
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return null;
    return out;
}

fn timerStartTrap(m: *Machine, kind: ia.TimerStartKind, time: Term, dest: Term, msg: Term, abs: bool) BifError!Term {
    if (!FinalTerms.repIsSmall(time)) return error.Badarg;
    if (FinalTerms.smallValOf(time) < 0) return error.Badarg;
    if (!isTimerDest(m, dest)) return error.Badarg;
    m.pending = .{ .timer_start = .{ .kind = kind, .time = time, .dest = dest, .msg = msg, .abs = abs } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the TRef to x0
}

/// `erlang:send_after/3` — deliver `Msg` to `Dest` after `Time` ms. → TRef.
pub fn send_after_3(m: *Machine, args: []const Term) BifError!Term {
    return timerStartTrap(m, .send_after, args[0], args[1], args[2], false);
}
/// `erlang:send_after/4` — `send_after/3` + an options list (`{abs, Bool}` only;
/// `{async,_}`/`{info,_}` are `badarg` here — OTP passes NULL for those keys).
pub fn send_after_4(m: *Machine, args: []const Term) BifError!Term {
    const o = parseTimerOptions(m, args[3], .{ .abs = true }) orelse return error.Badarg;
    return timerStartTrap(m, .send_after, args[0], args[1], args[2], o.abs);
}
/// `erlang:start_timer/3` — deliver `{timeout, TRef, Msg}` to `Dest` after
/// `Time` ms (the `start_timer` wrapper shape). → TRef.
pub fn start_timer_3(m: *Machine, args: []const Term) BifError!Term {
    return timerStartTrap(m, .start_timer, args[0], args[1], args[2], false);
}
/// `erlang:start_timer/4` — `start_timer/3` + an options list (`{abs, Bool}`
/// only; `{async,_}`/`{info,_}` are `badarg` — OTP passes NULL for those keys).
pub fn start_timer_4(m: *Machine, args: []const Term) BifError!Term {
    const o = parseTimerOptions(m, args[3], .{ .abs = true }) orelse return error.Badarg;
    return timerStartTrap(m, .start_timer, args[0], args[1], args[2], o.abs);
}

/// `erlang:cancel_timer/1` — cancel a still-live timer; → remaining-ms | false.
pub fn cancel_timer_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsRef(&m.ctx, args[0])) return error.Badarg;
    m.pending = .{ .timer_cancel = .{ .tref = args[0], .info = true, .is_async = false } };
    return boolTerm(m, false); // placeholder; the VM writes the real result to x0
}
/// `erlang:cancel_timer/2` — `cancel_timer/1` + `{async,Bool}`/`{info,Bool}`.
/// With `{info,false}` → `ok`; with `{async,true}` → `ok` and a
/// `{cancel_timer,TRef,Result}` message to the caller.
pub fn cancel_timer_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsRef(&m.ctx, args[0])) return error.Badarg;
    // OTP: parse_bif_timer_options(_, &async, &info, NULL) — `{abs,_}` is badarg.
    const o = parseTimerOptions(m, args[1], .{ .async = true, .info = true }) orelse return error.Badarg;
    m.pending = .{ .timer_cancel = .{ .tref = args[0], .info = o.info, .is_async = o.is_async } };
    return boolTerm(m, false);
}
/// `erlang:read_timer/1` — remaining-ms of a still-live timer | false.
pub fn read_timer_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsRef(&m.ctx, args[0])) return error.Badarg;
    m.pending = .{ .timer_read = .{ .tref = args[0], .is_async = false } };
    return boolTerm(m, false);
}
/// `erlang:read_timer/2` — `read_timer/1` + `{async,Bool}` ONLY. OTP passes
/// `parse_bif_timer_options(_, &async, NULL, NULL)`, so `{info,_}` (and
/// `{abs,_}`) are `badarg` here — read_timer always reports (info is hardcoded
/// true in OTP's `access_bif_timer` call). Pre-e24-t7 this wrongly accepted
/// `{info,_}` via the shared cancel/read parser; the gate now rejects it.
pub fn read_timer_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsRef(&m.ctx, args[0])) return error.Badarg;
    const o = parseTimerOptions(m, args[1], .{ .async = true }) orelse return error.Badarg;
    m.pending = .{ .timer_read = .{ .tref = args[0], .is_async = o.is_async } };
    return boolTerm(m, false);
}

// ============================================================================
// E6.5 (Task 5): the system introspection family — statistics/system_info/
// system_flag/system_profile/system_monitor/scheduler_wall_time/bump_reductions.
//
// SCOPE / ledger honesty. Every row here is DIFFERENTIALLY observable EQ over a
// DETERMINISTIC subset (the corpus proves it end-to-end on both VMs; the fields
// whose VALUES are host-nondeterministic are PROPERTY-FOLDED — type/monotonicity/
// round-trip — never byte-asserted):
//   statistics/1        counter tuples; the corpus asserts type + monotonicity.
//   system_info/1       a VERSION-INDEPENDENT constant subset (wordsize=8,
//                       machine="BEAM", endian, smp_support, threads); the
//                       release/ERTS-version items are host-specific and are NOT
//                       answered here (a caller of an unmodeled item gets
//                       `badarg`, never a WRONG value) — the corpus never asserts
//                       them (W-11: the host is OTP-28, the target OTP-30).
//   system_flag/2       backtrace_depth round-trips an int (default 8).
//   system_profile/0,2  the profiler setting; an `undefined` profiler clears it.
//   system_monitor/1,3  the legacy get(/1) / set(/3, {Pid,Opts}) round-trip.
//   scheduler_wall_time/1  round-trips the enable flag (OLD boolean).
//   bump_reductions/1   bumps the running process's reduction counter → `true`.
// State lives on the Machine (single-process scope, the `trap_exit` precedent —
// see the Machine field doc-comments). No pid/ref/scheduler dependency: each is a
// pure reader/writer over EXISTING Machine state, so each returns via `bif1`/`bif2`
// (never a scheduler trap).
// ============================================================================

fn atomIs(m: *Machine, t: Term, name: []const u8) bool {
    if (!FinalTerms.repIsAtom(t)) return false;
    return std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(t)), name);
}

fn atomTerm(m: *Machine, name: []const u8) BifError!Term {
    const idx = m.ctx.atoms.intern(name) catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

/// Erlang string (list of byte code points), built tail-first (leak-free — every
/// cons is a `ctx` heap ref).
fn charList(m: *Machine, bytes: []const u8) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = bytes.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, bytes[i]), acc) catch return error.OutOfMemory;
    }
    return acc;
}

fn needNonNegSmall(t: Term) ?i64 {
    if (!FinalTerms.repIsSmall(t)) return null;
    const v = FinalTerms.smallValOf(t);
    if (v < 0) return null;
    return v;
}

/// The `undefined`-or-`{Pid,Opts}` shape a system_monitor/system_profile getter
/// returns.
fn sysSettingTerm(m: *Machine, s: ?ia.SysSetting) BifError!Term {
    if (s) |v| {
        return FinalTerms.tuple(&m.ctx, &.{ v.pid, v.opts }) catch return error.OutOfMemory;
    }
    return atomTerm(m, "undefined");
}

/// `erlang:bump_reductions/1` — bump the running process's reduction counter by
/// `Reductions` (a non-negative small int); returns the `true` atom (the erts
/// contract). A negative / non-int argument is `badarg`.
pub fn bump_reductions_1(m: *Machine, args: []const Term) BifError!Term {
    const n = needNonNegSmall(args[0]) orelse return error.Badarg;
    // R2b two-counter: this is a REDUCTION bump (accounting), but in OTP a
    // reduction bump also brings preemption FORWARD by N. Since zigvm bounds
    // preemption on `instrs` (byte-identical scheduling), bump BOTH: `reductions`
    // for the accounting and `instrs` so preemption is still brought forward by
    // exactly N (the PREEMPTION-LATENCY law, byte-identical to the pre-R2b model).
    m.reductions += @as(u64, @intCast(n));
    m.instrs += @as(u64, @intCast(n));
    return boolTerm(m, true);
}

/// `erlang:statistics/1` — the counter-observation subset. The VALUES are host-
/// nondeterministic; the corpus PROPERTY-FOLDS them (type + monotonicity), never
/// byte-asserts. `reductions`/`exact_reductions` → `{Total, SinceLastCall}` off
/// the Machine's monotone `reductions`; `wall_clock` → REAL clock ms and
/// `runtime` → REAL per-process CPU-time ms, both `{Total, SinceLastCall}` off
/// the S21 clock seam (lazy epoch); `run_queue` → the real `Vm.liveCount()`
/// runnable count (traps to the Vm). An unmodeled item is `badarg`. No item
/// returns a fabricated constant (FM-OBS-1 honesty).
/// gap-real-metrics (DIVERGENCE 627, FM-OBS-1): `erlang:memory/0` — traps to the
/// Vm which builds the TRUTHFUL measured-bytes proplist. No fabricated value.
pub fn memory_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .{ .stat_memory = .all };
    return FinalTerms.atom(&m.ctx, m.bool_true); // placeholder; the trap writes x0
}

/// `erlang:memory/1` — one category. Only the categories zigvm TRULY measures
/// (total/processes/atom) are supported; a valid-OTP-but-unmodeled category
/// (code/system/binary/ets/...) or a non-atom → badarg (FM-OBS-1: an honest
/// "not modeled" beats a fabricated number — the DISCLOSED bound).
pub fn memory_1(m: *Machine, args: []const Term) BifError!Term {
    const it = args[0];
    if (!FinalTerms.repIsAtom(it)) return error.Badarg;
    const kind: ia.MemKind = if (atomIs(m, it, "total"))
        .total
    else if (atomIs(m, it, "processes") or atomIs(m, it, "processes_used"))
        .processes
    else if (atomIs(m, it, "atom") or atomIs(m, it, "atom_used"))
        .atom
    else
        return error.Badarg;
    m.pending = .{ .stat_memory = kind };
    return FinalTerms.atom(&m.ctx, m.bool_true); // placeholder; the trap writes x0
}

pub fn statistics_1(m: *Machine, args: []const Term) BifError!Term {
    const item = args[0];
    if (atomIs(m, item, "reductions") or atomIs(m, item, "exact_reductions")) {
        const total = m.reductions;
        const since = total - m.stat_reds_last; // total >= last (reductions grow)
        m.stat_reds_last = total;
        return FinalTerms.tuple(&m.ctx, &.{
            FinalTerms.int(&m.ctx, @intCast(total)),
            FinalTerms.int(&m.ctx, @intCast(since)),
        }) catch return error.OutOfMemory;
    }
    if (atomIs(m, item, "wall_clock")) {
        // gap-real-metrics (FM-OBS-1): REAL wall-clock ms off the S21 clock seam
        // (`m.clock`, real clock_gettime), not the old fabricated {0,0}. OTP
        // shape: {Total, SinceLastCall}. Epoch = the FIRST observation (lazy) —
        // Total measures from there (honest bound: per-process basis, not node
        // start; host-nondeterministic either way, the corpus property-folds).
        const now: i64 = @intCast(m.clock.monotonic(1000));
        if (m.stat_wall_epoch_ms == null) {
            m.stat_wall_epoch_ms = now;
            m.stat_wall_last_ms = now;
        }
        const total = now - m.stat_wall_epoch_ms.?;
        const diff = now - m.stat_wall_last_ms;
        m.stat_wall_last_ms = now;
        return FinalTerms.tuple(&m.ctx, &.{
            FinalTerms.int(&m.ctx, total),
            FinalTerms.int(&m.ctx, diff),
        }) catch return error.OutOfMemory;
    }
    if (atomIs(m, item, "runtime")) {
        // gap-real-metrics (FM-OBS-1): REAL per-process CPU time (ms) off the S21
        // clock seam's PROCESS_CPUTIME source — the honest getrusage-equivalent
        // that retired the fabricated {0,0}. OTP shape: {Total, SinceLastCall}.
        // Epoch = the FIRST observation (lazy); Total measures CPU time from
        // there. This is CPU time, NOT a wall_clock alias (a wall alias would be
        // a WRONG value). Host-nondeterministic; the corpus property-folds
        // shape + monotonicity + the SinceLast reset, never bytes.
        const now: i64 = @intCast(m.clock.processCpuTime(1000));
        if (m.stat_runtime_epoch_ms == null) {
            m.stat_runtime_epoch_ms = now;
            m.stat_runtime_last_ms = now;
        }
        const total = now - m.stat_runtime_epoch_ms.?;
        const diff = now - m.stat_runtime_last_ms;
        m.stat_runtime_last_ms = now;
        return FinalTerms.tuple(&m.ctx, &.{
            FinalTerms.int(&m.ctx, total),
            FinalTerms.int(&m.ctx, diff),
        }) catch return error.OutOfMemory;
    }
    if (atomIs(m, item, "run_queue")) {
        // gap-real-metrics (FM-OBS-1): the run-queue length is Vm SCHEDULER state,
        // unreachable from a bare Machine — TRAP to the Vm, which writes the REAL
        // `Vm.liveCount()` runnable count to x0 (not the old fabricated 0 that
        // reported an idle node on a saturated one). Placeholder 0 → x0 until the
        // trap resolves.
        m.pending = .stat_run_queue;
        return FinalTerms.int(&m.ctx, 0);
    }
    return error.Badarg;
}

/// `erlang:system_info/1` — the VERSION-INDEPENDENT deterministic item subset.
/// The corpus asserts these byte-EQ on both VMs (W-11: never an OTP-release- or
/// ERTS-version-specific item). An item outside this subset is `badarg` (never a
/// WRONG value).
pub fn system_info_1(m: *Machine, args: []const Term) BifError!Term {
    const item = args[0];
    // {wordsize, internal|external} → 8 (64-bit words).
    if (FinalTerms.kindOf(&m.ctx, item) == .tuple and FinalTerms.tupleArity(&m.ctx, item) == 2) {
        if (atomIs(m, FinalTerms.tupleElem(&m.ctx, item, 0), "wordsize")) return FinalTerms.int(&m.ctx, 8);
        return error.Badarg;
    }
    if (atomIs(m, item, "wordsize")) return FinalTerms.int(&m.ctx, 8);
    if (atomIs(m, item, "machine")) return charList(m, "BEAM");
    // DIVERGENCE 720: the PIN-CONSTANT version strings (OTP 30-rc0 @ 679f9dbb).
    // These describe the emulated erts/OTP the pin fixes — byte-EQ for the pin,
    // and they change deliberately on a re-pin (never fabricated; the values
    // come straight from the pinned `third_party/otp/bin/erl`).
    if (atomIs(m, item, "otp_release")) return charList(m, "30");
    if (atomIs(m, item, "version")) return charList(m, "17.0.3"); // erts version
    if (atomIs(m, item, "nif_version")) return charList(m, "2.18");
    if (atomIs(m, item, "driver_version")) return charList(m, "3.3");
    if (atomIs(m, item, "endian")) return atomTerm(m, "little");
    if (atomIs(m, item, "smp_support")) return boolTerm(m, true);
    if (atomIs(m, item, "threads")) return boolTerm(m, true);
    // gap-atom-and-heap-limits (atom observability): `atom_limit` is the erts
    // default max atom count (byte-EQ 1_048_576); `atom_count` is the TRUTHFUL
    // live count of interned atoms (VM-specific — reported, never fabricated;
    // FM-OBS-1). The enforcement (intern past `atom_limit` → system_limit) is the
    // deferred follow-on (atom-exhaustion needs a limit + system_limit threading).
    if (atomIs(m, item, "atom_limit")) return FinalTerms.int(&m.ctx, 1_048_576);
    if (atomIs(m, item, "atom_count")) return FinalTerms.int(&m.ctx, @intCast(m.ctx.atoms.count()));
    return error.Badarg;
}

/// `erlang:system_flag/2` — the backtrace_depth flag round-trips an int (default
/// 8; the VALUE is never byte-asserted, only the round-trip New==Set +
/// is_integer(Old)); scheduler_wall_time round-trips its boolean. Every other flag
/// is `badarg` (an unrecognized-flag rejection, not a silent no-op).
pub fn system_flag_2(m: *Machine, args: []const Term) BifError!Term {
    const flag = args[0];
    if (atomIs(m, flag, "backtrace_depth")) {
        const n = needNonNegSmall(args[1]) orelse return error.Badarg;
        const old = m.backtrace_depth;
        m.backtrace_depth = n;
        return FinalTerms.int(&m.ctx, old);
    }
    if (atomIs(m, flag, "scheduler_wall_time")) {
        const on = asBool(m, args[1]) orelse return error.Badarg;
        const old = m.swt_enabled;
        m.swt_enabled = on;
        return boolTerm(m, old);
    }
    return error.Badarg;
}

/// `erlang:system_profile/0` — the current profiler setting (`undefined` when
/// unset, else `{ProfilerPid, Opts}`).
pub fn system_profile_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return sysSettingTerm(m, m.sysprof);
}

/// `erlang:system_profile/2` — set the profiler; returns the PREVIOUS setting. An
/// `undefined` profiler clears it (disables profiling).
pub fn system_profile_2(m: *Machine, args: []const Term) BifError!Term {
    const prev = try sysSettingTerm(m, m.sysprof);
    if (atomIs(m, args[0], "undefined")) {
        m.sysprof = null;
    } else {
        m.sysprof = .{ .pid = args[0], .opts = args[1] };
    }
    return prev;
}

/// `erts_internal:scheduler_wall_time/1` — round-trips the enable flag; returns
/// the OLD boolean. `badarg` on a non-boolean arg.
pub fn scheduler_wall_time_1(m: *Machine, args: []const Term) BifError!Term {
    const on = asBool(m, args[0]) orelse return error.Badarg;
    const old = m.swt_enabled;
    m.swt_enabled = on;
    return boolTerm(m, old);
}

/// `erts_internal:system_monitor/1` — the legacy GET; returns the current
/// {MonitorPid, Opts} setting (`undefined` when unset). The `legacy` tag arg is
/// accepted (the erlang:system_monitor/0 wrapper always passes it).
pub fn system_monitor_1(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return sysSettingTerm(m, m.sysmon);
}

/// `erts_internal:system_monitor/3` — the legacy SET (`legacy`, MonitorPid,
/// Opts); returns the PREVIOUS setting. An `undefined` MonitorPid clears it.
pub fn system_monitor_3(m: *Machine, args: []const Term) BifError!Term {
    const prev = try sysSettingTerm(m, m.sysmon);
    if (atomIs(m, args[1], "undefined")) {
        m.sysmon = null;
    } else {
        m.sysmon = .{ .pid = args[1], .opts = args[2] };
    }
    return prev;
}

// ============================================================================
// E6.6 (Task 6): the dirty-scheduler erts_internal rows. zigvm runs every BIF
// SYNCHRONOUSLY on the sole scheduler pool (the dirty-migration homomorphism in
// proc.zig proves the dirty pool is a scheduling hint that never changes
// `denote`), so:
//   - `check_dirty_process_code/2` + `dirty_process_handle_signals/1` are
//     RESTRICTED erts-internal entry points; a direct call raises `error:notsup`
//     on the OTP-28 host (the process/context restriction DOMINATES arg
//     validation, host-verified arg-independent) — the same rejection
//     differential that flipped the purger rows (bifs/code.zig, DIVERGENCE 108).
//   - `is_process_executing_dirty/1` is `false` (no process ever executes on a
//     dirty scheduler here — there is no separate dirty runtime), byte-EQ.
//   - `perf_counter_unit/0` is the perf-counter resolution; a raw value is host/
//     config-coupled (W-11), so it flips PROPERTY-FOLDED (is_integer & > 0) — the
//     honest observable, returning the nanosecond unit zigvm's monotonic clock uses.
// The remaining dirty rows (`no_aux_work_threads/0` — a host aux-thread COUNT;
// `gather_alloc_histograms/1`, `gather_carrier_info/1` — allocator-representation-
// coupled) are RE-BOUND precisely in harness/bif_gen.ml (never a false EQ).
// ============================================================================

/// Raise `error:notsup` — the restricted-entry rejection the dirty code-check
/// BIFs return to a normal caller (host-verified arg-independent). The dirty
/// pool never changes `denote`, so nothing is lost by rejecting the direct call.
fn raiseNotsup(m: *Machine) BifError {
    const notsup = m.ctx.atoms.intern("notsup") catch return error.OutOfMemory;
    return m.bifRaise(.error_, FinalTerms.atom(&m.ctx, notsup));
}

/// `erts_internal:check_dirty_process_code/2` — RESTRICTED (the dirty code-purge
/// path); a direct call raises `error:notsup` (arg-independent, host-verified).
pub fn check_dirty_process_code_2(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return raiseNotsup(m);
}

/// `erts_internal:dirty_process_handle_signals/1` — RESTRICTED; a direct call
/// raises `error:notsup` (arg-independent, host-verified).
pub fn dirty_process_handle_signals_1(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return raiseNotsup(m);
}

/// `erts_internal:is_process_executing_dirty/1` — always `false` (no process
/// executes on a dirty scheduler in zigvm's single synchronous pool). A non-pid
/// argument is `badarg`.
pub fn is_process_executing_dirty_1(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    return boolTerm(m, false);
}

/// `erts_internal:perf_counter_unit/0` — the perf-counter resolution as a
/// positive integer (nanoseconds, matching the monotonic clock). Observed
/// property-folded (is_integer & > 0) — the raw value is host/config-coupled.
pub fn perf_counter_unit_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.int(&m.ctx, 1_000_000_000);
}

/// `exit/1` — the process exits with `Reason` (an un-catchable exit for the
/// SELF form is BEAM-modeled as an `exit` signal to self; here the scheduler
/// terminates the running process). Traps `exit_proc`; never returns normally.
pub fn exit_1(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .exit_proc = .{ .reason = args[0] } };
    return FinalTerms.nil(&m.ctx); // unreachable value: the process dies
}

/// `exit/2` — send an EXIT signal to `Pid` (per-pair signal order — the sacred M7
/// law over the bridge). Traps `exit_to`; returns `true` DIRECTLY (BEAM contract).
/// A signal to a dead/absent pid is dropped.
pub fn exit_2(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    m.pending = .{ .exit_to = .{ .pid = args[0], .reason = args[1] } };
    return boolTerm(m, true);
}

/// `exit_signal/2` — OTP30's lower-level signal BIF. Local pid/ref/port
/// identities are executable; a foreign pid routes to the Vm owner where live
/// DistEntry state may record a remote-exit observation; a foreign ref remains
/// inert `true`; and a foreign port is `badarg`.
pub fn exit_signal_2(m: *Machine, args: []const Term) BifError!Term {
    return exitSignal(m, args[0], args[1], FinalTerms.nil(&m.ctx));
}

/// `is_process_alive/1` — `true` iff `Pid` names a live local process. Traps
/// `is_alive`; the scheduler consults the live-process registry and writes the
/// bool to x0 (a delivery to a reaped pid is a clean `false`, never a UAF — the
/// §10 FMEA mitigation). `deferred-E4-procdispatch`.
pub fn is_process_alive_1(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    m.pending = .{ .is_alive = .{ .pid = args[0] } };
    return boolTerm(m, false); // placeholder; the VM writes the real bool to x0
}

/// `alias/1` — mint a fresh process alias (a reference the calling process can be
/// sent messages through while active — `Alias ! Msg` lands in the owner's
/// mailbox). Traps `make_alias`; the scheduler mints a ref, records it in the
/// caller's process-local alias table, and writes the ref to x0. The options
/// list is validated (a proper list) but its modes beyond the default
/// (`explicit_unalias` — retire only on `unalias/1`) are accepted-and-ignored
/// (the `monitor/3` `{tag,_}` precedent); `[reply]`/`[priority]` behave as the
/// default. E5.5 (DIVERGENCE entry 19/21/33).
pub fn alias_1(m: *Machine, args: []const Term) BifError!Term {
    // options must be a proper list (`alias([])` is the common `alias/0` form).
    var cur = args[0];
    var guard: usize = 0;
    var priority = false;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons and guard < 64) : (guard += 1) {
        // e50-eep76: `alias([priority])` mints a PRIORITY alias — messages sent
        // through it jump ahead of the normal mailbox (front-of-mailbox). Other
        // option atoms (`reply`, `explicit_unalias`) keep default semantics.
        const opt = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.repIsAtom(opt) and std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(opt)), "priority")) priority = true;
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg;
    m.pending = .{ .make_alias = .{ .dst = 0, .priority = priority } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the alias ref to x0
}

/// `unalias/1` — deactivate an alias `Alias` (a reference) previously created by
/// the calling process. Traps `unalias_ref`; the VM deactivates a caller-owned
/// active alias and writes `true`, else `false` (an alias owned by another
/// process, an already-retired one, or a non-alias ref). E5.5.
pub fn unalias_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsRef(&m.ctx, args[0])) return error.Badarg;
    m.pending = .{ .unalias_ref = .{ .ref = args[0] } };
    return boolTerm(m, false); // placeholder; the VM writes the real bool to x0
}

/// `erts_internal:is_process_alive/2` — the ASYNC form of `is_process_alive/1`
/// (`is_process_alive(Pid, Ref)`). Traps `is_alive_request`; the scheduler sends
/// the caller an async mailbox reply `{Ref, boolean()}` and writes `ok` to x0
/// (erts contract). `Ref` must be a reference; `Pid` a local pid. E5.5
/// (DIVERGENCE entry 19/21/33 — the alias-reply protocol twin of `alias/1`).
pub fn is_process_alive_2(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    if (!FinalTerms.repIsRef(&m.ctx, args[1])) return error.Badarg;
    m.pending = .{ .is_alive_request = .{ .pid = args[0], .ref = args[1] } };
    const ok = try m.ctx.atoms.intern("ok");
    return FinalTerms.atom(&m.ctx, ok);
}

/// `processes/0` — the list of all live local pids. Traps `list_processes`; the
/// scheduler builds the pid-term list and writes it to x0. `deferred-E4-procdispatch`.
pub fn processes_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .list_processes;
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the pid list to x0
}

// ============================================================================
// E3.8: link/monitor/registry process BIFs — the entry-11 remainder over
// proc.zig's ALREADY-LAW-COVERED link/monitor signal machinery ("Links:
// symmetry, exit propagation, trap_exit, normal-exit semantics" and
// "Monitors: 'DOWN' exactly once; demonitor prevents it; dead pid → noproc",
// both above `proc.zig`'s E3.7 section) and the registry bijection
// (`registry.zig`'s own homomorphism/bijection law suite, now Vm-owned via
// `proc.Vm.registry`). This task adds ONLY the BIF surface + two new pieces of
// genuine Vm-level machinery: the registry integration (bijection now
// reachable from a BIF, DEATH unregisters via `terminate`/`normalExit`) and
// `demonitor(Ref,[flush])`'s race-DOWN clearing (`proc.zig`'s
// `doDemonitorFlush` — Mutant 1's target). SAME call_ext-honesty discipline as
// E3.7: every row below is functionally implemented + Vm-law-proven but
// `call_ext`-blocked (Task 12/E4) — none flips EQ (see `bif_gen.ml`).
//
// Two documented simplifications, both because a Vm TRAP cannot unwind the
// caller's stack to raise an exception (only write an x0 result): (1)
// `register/2`/`unregister/1`/`erts_internal:group_leader/2,3` return a
// `true`/`false` BOOL instead of real BEAM's raise-`badarg`-on-failure
// contract. (2) `process_info/1,2`'s documented item subset — `status`, `links`,
// `monitors`, `registered_name`, `messages`, `dictionary`, `message_queue_len`,
// `trap_exit`, `priority`, `error_handler`, `message_queue_data`,
// `current_stacktrace`, `current_function`, `catchlevel`, `reductions`,
// `stack_size`, `group_leader`, `monitored_by`, and (DIVERGENCE 754) `initial_call`
// (the {M,F,A} the process was SPAWNED with) — is a SCOPE LIMIT vs. real BEAM's
// larger default item set: an unsupported item is STILL a genuine synchronous
// `badarg` (validated before any trap is set — the entry-9(d) precedent), just over
// a smaller supported set. The BYTE-TOTAL items (the config defaults + the birth
// MFA `initial_call`) are proven by the item-totality law; the counters that ARE
// returned (reductions/catchlevel/stack_size) + the pid-valued items (group_leader/
// monitored_by, and links/monitors' boot-set pid numbers) are honest EQUIV — real
// functions of state, never fabricated constants (FM-OBS-1). The row STAYS deferred
// (`deferred-E5-procinfo`) for the RESIDUAL: process_info/1's FULL default list still
// omits `memory`/`heap_size`/`total_heap_size` (erts word/byte counts — need a
// principled heap measure) + `garbage_collection` (a GC proplist), which the accept-
// gate STILL rejects (synchronous `badarg`) — never a false EQ.
// gap-stdlib-bif-audit ADDED the one supported TUPLE item — `{dictionary, Key}`
// — a byte-total single-key projection of the pdict (present -> the stored value,
// absent -> the atom `undefined`; host-verified). This is exactly the item
// `proc_lib` reads for `$initial_call`/`$process_label`; every other tuple item
// stays a synchronous `badarg`. The row still STAYS deferred (the FULL default
// list residual above is unchanged).
// ============================================================================

/// Scan a proper option list for `name` (the LOCAL-subset opts convention
/// shared by `monitor/3`'s `{tag,_}`, `demonitor/2`'s `flush`/`info`,
/// `link/2`'s opts, `exit/3`'s opts, … — everywhere a real BEAM option is
/// accepted but this VM's LOCAL-only model has nothing to DO with it besides
/// the ones it explicitly interprets, same precedent as `optsHaveLink`).
fn optsHaveAtom(m: *Machine, opts: Term, name: []const u8) bool {
    var cur = opts;
    var guard: usize = 0;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons and guard < 64) : (guard += 1) {
        const head = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.repIsAtom(head)) {
            const got = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(head));
            if (std.mem.eql(u8, got, name)) return true;
        }
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    return false;
}

/// A supported `process_info` item name — see this section's doc comment.
/// Validated SYNCHRONOUSLY (no Vm/trap needed for a plain string compare), so
/// an unsupported item is a REAL `badarg` raised HERE, before any trap is
/// ever set (the entry-9(d) `ets:info` unsupported-item precedent).
fn isSupportedProcessInfoItem(name: []const u8) bool {
    // E5.9 extended the supported subset with three DETERMINISTIC non-pid items
    // (message_queue_len/trap_exit/priority) — each a single scalar computed
    // from the target's own state, byte-total against OTP's value for the
    // default-shaped process (unlike the impl-specific counters — reductions/
    // heap_size/gc — that keep process_info/1's FULL default list deferred).
    // E7.5 (Task 5) added two more DETERMINISTIC non-pid defaults verified
    // byte-total on the host: `error_handler` (always the atom `error_handler` —
    // the default error handler module) and `message_queue_data` (always `on_heap`
    // for a default-shaped process). Both are portable config defaults, not the
    // impl-specific counters (reductions/heap_size/gc) that keep the FULL list
    // deferred, and not the pid-valued items (links/monitors) that ride boot-set
    // pid numbering. See the process_info residual in the ledger reason.
    const items = [_][]const u8{
        "status",   "links",         "monitors",           "registered_name",
        "messages", "dictionary",    "message_queue_len",  "trap_exit",
        "priority", "error_handler", "message_queue_data",
        // DIVERGENCE 684: the CURRENT call stack — OTP `?STACKTRACE()`'s source.
        "current_stacktrace",
        // gap-procinfo-keys (DIVERGENCE 735): four items computable from the target's
        // LIVE machine state — `current_function` (byte-EQ mfa) + `catchlevel`/
        // `reductions`/`stack_size` (EQUIV, real functions of state, disclosed). These
        // valid keys must RETURN, not `badarg` (FM-OBS-1).
        "current_function", "catchlevel", "reductions", "stack_size",
        // gap-procinfo-keys2 (DIVERGENCE 736): `group_leader` (the gl proc index → a
        // pid, EQUIV) + `monitored_by` (the reverse-monitor watcher pids — `[]` byte-EQ
        // when none, EQUIV list otherwise). The remaining memory/heap-word items
        // (memory/heap_size/total_heap_size — need a principled heap measure),
        // garbage_collection (a GC proplist) stays deferred.
        "group_leader", "monitored_by",
        // gap-procinfo-initial-call (DIVERGENCE 754): `initial_call` — the {M,F,A} the
        // process was SPAWNED with, recorded at birth (proc.zig resolveSpawnMFA),
        // BYTE-EQ vs OTP's PCB initial_call (default `{erlang,apply,2}` for the root).
        // Discharges the 735 residual. The remaining memory/heap-word items (memory/
        // heap_size/total_heap_size — need a principled heap measure) stay deferred
        // (never silently accepted — an unknown item still synchronous-badargs).
        "initial_call",
    };
    for (items) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

test "LAW gap-procinfo-keys gate (DIVERGENCE 735): the 4 live-state items are SUPPORTED (process_info/2 no longer badargs them); an unknown item still rejects" {
    // These are valid OTP items — a valid key must RETURN, not synchronous-badarg
    // (FM-OBS-1). current_function is byte-EQ; the other three are EQUIV.
    try std.testing.expect(isSupportedProcessInfoItem("current_function"));
    try std.testing.expect(isSupportedProcessInfoItem("catchlevel"));
    try std.testing.expect(isSupportedProcessInfoItem("reductions"));
    try std.testing.expect(isSupportedProcessInfoItem("stack_size"));
    // DIVERGENCE 736: group_leader + monitored_by also supported.
    try std.testing.expect(isSupportedProcessInfoItem("group_leader"));
    try std.testing.expect(isSupportedProcessInfoItem("monitored_by"));
    // DIVERGENCE 754: initial_call also supported (discharges the 735 residual).
    try std.testing.expect(isSupportedProcessInfoItem("initial_call"));
    // the gate still REJECTS a genuinely-unknown item (no over-broad acceptance).
    try std.testing.expect(!isSupportedProcessInfoItem("no_such_item"));
    // and a still-DEFERRED item stays rejected (honest residual, not silently accepted).
    try std.testing.expect(!isSupportedProcessInfoItem("garbage_collection"));
    try std.testing.expect(!isSupportedProcessInfoItem("memory"));
}

/// `link/1` — bidirectional link to `Pid` (M7 `link_to`, already
/// law-covered). Returns `true` DIRECTLY (BEAM contract). `deferred-E4-procdispatch`.
pub fn link_1(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    m.pending = .{ .link_to = .{ .pid = args[0] } };
    return boolTerm(m, true);
}

/// `link/2` — `link(Pid, OptList)`, the modern option form (e.g. `priority`).
/// LOCAL subset: options are accepted-and-ignored (`spawn_opt/4`'s
/// convention). `deferred-E4-procdispatch`.
pub fn link_2(m: *Machine, args: []const Term) BifError!Term {
    return link_1(m, args[0..1]);
}

/// `unlink/1` — cancel a link (M7 `unlink_to`). Returns `true` DIRECTLY.
/// `deferred-E4-procdispatch`.
pub fn unlink_1(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    m.pending = .{ .unlink_to = .{ .pid = args[0] } };
    return boolTerm(m, true);
}

/// `monitor/2` — `monitor(process, Pid)`. Traps `monitor_to` (M7, already
/// law-covered — fires 'DOWN' exactly once); the VM writes a fresh ref to x0.
/// The `Type` argument must be the atom `process` (port/time_offset monitors
/// are out of scope — this VM models neither). `deferred-E4-procdispatch`.
pub fn monitor_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const kname = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    if (!std.mem.eql(u8, kname, "process")) return error.Badarg;
    if (!isLocalPid(m, args[1])) return error.Badarg;
    m.pending = .{ .monitor_to = .{ .pid = args[1], .dst = 0 } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the ref to x0
}

/// `monitor/3` — `monitor(process, Pid, OptList)`. LOCAL subset: `{tag,_}` is
/// accepted-and-ignored; E5.5 HONORS `{alias, Mode}` — the returned ref doubles
/// as a process alias (`Ref ! Reply` routes to the monitoring process), retiring
/// on the 'DOWN' unless `explicit_unalias` (DIVERGENCE entry 19). Other opts
/// accepted-and-ignored. `deferred-E4-procdispatch` (monitor itself is EQ).
pub fn monitor_3(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const kname = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    if (!std.mem.eql(u8, kname, "process")) return error.Badarg;
    if (!isLocalPid(m, args[1])) return error.Badarg;
    m.pending = .{ .monitor_to = .{ .pid = args[1], .dst = 0, .alias = aliasModeOf(m, args[2]) } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the ref to x0
}

/// E5.5: scan a `monitor/3` option list for `{alias, Mode}`. Absent → `.none`
/// (plain monitor). `{alias, explicit_unalias}` → `.explicit` (alias survives the
/// 'DOWN' until `unalias/1`); any other mode (`demonitor`/`reply_demonitor`) →
/// `.retire` (auto-retires on the 'DOWN' — erts' default).
fn aliasModeOf(m: *Machine, opts: Term) ia.MonAlias {
    var cur = opts;
    var guard: usize = 0;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons and guard < 64) : (guard += 1) {
        const head = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.kindOf(&m.ctx, head) == .tuple and FinalTerms.tupleArity(&m.ctx, head) == 2) {
            const k = FinalTerms.tupleElem(&m.ctx, head, 0);
            if (FinalTerms.repIsAtom(k) and std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(k)), "alias")) {
                const mode = FinalTerms.tupleElem(&m.ctx, head, 1);
                if (FinalTerms.repIsAtom(mode) and std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(mode)), "explicit_unalias"))
                    return .explicit;
                return .retire;
            }
        }
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    return .none;
}

/// `demonitor/1` — cancel a monitor (M7 `demonitor_ref`). Returns `true`
/// DIRECTLY. `deferred-E4-procdispatch`.
pub fn demonitor_1(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .demonitor_ref = .{ .ref = args[0], .info = false } };
    return boolTerm(m, true);
}

/// `demonitor/2` — `demonitor(Ref, OptList)`. The `flush` option ALSO clears a
/// race 'DOWN' already queued or delivered (traps `demonitor_flush`, not the
/// plain `demonitor_ref` — see `proc.zig`'s `doDemonitorFlush`, the
/// exactly-once law's race guard and Mutant 1's target). `info` (whether the
/// monitor existed) is accepted-and-ignored — this VM always returns `true`.
/// `deferred-E4-procdispatch`.
pub fn demonitor_2(m: *Machine, args: []const Term) BifError!Term {
    if (optsHaveAtom(m, args[1], "flush")) {
        m.pending = .{ .demonitor_flush = .{ .ref = args[0], .info = false } };
    } else {
        m.pending = .{ .demonitor_ref = .{ .ref = args[0], .info = false } };
    }
    return boolTerm(m, true);
}

/// `register/2` — bind `Name` (an atom) to `Pid` in the registry bijection.
/// Traps `register_name`; the VM enforces the bijection (duplicate name OR
/// pid-already-named OR a dead pid → `false` — see this section's doc comment
/// on the bool-not-raise simplification). `deferred-E4-procdispatch`.
pub fn register_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    if (!isLocalPid(m, args[1])) return error.Badarg;
    m.pending = .{ .register_name = .{ .name = args[0], .pid = args[1] } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes true/false to x0
}

/// `unregister/1` — remove `Name`'s registration. Traps `unregister_name`.
/// `deferred-E4-procdispatch`.
pub fn unregister_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    m.pending = .{ .unregister_name = .{ .name = args[0] } };
    return FinalTerms.nil(&m.ctx);
}

/// `whereis/1` — `Name`'s registered pid, or the atom `undefined`. Traps
/// `whereis_name`. `deferred-E4-procdispatch`.
pub fn whereis_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    m.pending = .{ .whereis_name = .{ .name = args[0] } };
    return FinalTerms.nil(&m.ctx);
}

/// `exit/3` — `exit(Pid, Reason, OptList)`, a real exported `erlang:exit/3`
/// bif.tab row sharing `exit/2`'s underlying signal (M7 `exit_to`). LOCAL
/// subset: `OptList` accepted-and-ignored (`send/3`'s convention).
/// `deferred-E4-procdispatch`.
pub fn exit_3(m: *Machine, args: []const Term) BifError!Term {
    return exit_2(m, args[0..2]);
}

/// `exit_signal/3` — same identity/remote-exit bridge semantics as /2 plus the
/// OTP30 option grammar: a proper list containing only `priority` atoms.
pub fn exit_signal_3(m: *Machine, args: []const Term) BifError!Term {
    return exitSignal(m, args[0], args[1], args[2]);
}

/// `group_leader/0` — the calling process's own group-leader pid.
/// SELF-CONTAINED (no trap): `m.group_leader` is mirrored onto the Machine by
/// `proc.Vm.spawn`/`interpret` exactly like `self_pid`, so this reads Machine
/// state directly — the same shape as `self_0`. `deferred-E4-procdispatch` (still
/// `call_ext`-gated; being self-contained does not by itself make a row
/// reachable — only `bif0`/`bif1`/`gc_bif` dispatch does, and `call_ext` is
/// Task 12).
pub fn group_leader_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.pid(&m.ctx, m.group_leader, 0) catch return error.Badarg;
}

/// `erts_internal:group_leader/2` — `group_leader(GroupLeader, Pid)` sets
/// `Pid`'s group leader (a DIFFERENT process's Machine field — needs the Vm
/// trap `set_group_leader`). The io PROTOCOL (routing `io:format` through the
/// group leader) stays E4 — this sets only the pointer. `true`/`false` via x0
/// (bad pid/leader → `false`, the same bool-not-raise simplification as
/// `register_2`). `deferred-E4-procdispatch`.
pub fn group_leader_2(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0]) or !isLocalPid(m, args[1])) return error.Badarg;
    m.pending = .{ .set_group_leader = .{ .leader = args[0], .pid = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// `erts_internal:group_leader/3` — `group_leader(GroupLeader, Pid, Ref)`, the
/// distributed handshake-ack form. LOCAL subset: `Ref` accepted-and-ignored
/// (no distribution modeled); delegates to `/2`. `deferred-E4-procdispatch`.
pub fn group_leader_3(m: *Machine, args: []const Term) BifError!Term {
    return group_leader_2(m, args[0..2]);
}

/// E5.6 (Task 6): `erts_internal:process_flag/3` — the async-ref request/reply
/// BIF DIVERGENCE entry 33's E4.3 amendment observed on the oracle (NOT the
/// synchronous cross-process `trap_exit` BIF this VM modeled at E3.8). On the
/// pin the ONLY flag it accepts is `save_calls` (a non-neg call-trace ring size,
/// `erlang.erl`'s `-spec process_flag(Pid, save_calls, Value)`); it returns the
/// OLD flag value. Empirically TOTAL — it RETURNS the atoms `badtype`/`badarg`
/// (the `erlang.erl` wrapper turns them into exceptions), it never raises here:
///   - a non-pid first arg → `badtype`;
///   - a flag name other than `save_calls`, or a value that is not a non-neg
///     integer → `badarg`.
/// SELF target: SYNCHRONOUS — returns the old value directly (no ref). Another
/// local process: ASYNCHRONOUS — `proc.zig` (`doProcessFlag3`) mints a ReqId ref
/// and replies `{ReqId, OldValue}` (verified on OTP-28: a non-self target
/// returns `#Ref<...>`), returning the ref via x0. The `save_calls` RING itself
/// is a debug facility not modeled; only the observable flag VALUE is (see
/// `Machine.save_calls`). DIVERGENCE entry 72.
pub fn process_flag_3(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0]))
        return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("badtype"));
    if (!FinalTerms.repIsAtom(args[1]) or
        !std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[1])), "save_calls"))
        return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("badarg"));
    if (!FinalTerms.repIsSmall(args[2]) or FinalTerms.smallValOf(args[2]) < 0)
        return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("badarg"));
    const value = FinalTerms.smallValOf(args[2]);
    if (FinalTerms.pidNumber(&m.ctx, args[0]) == m.self_pid) {
        const old = m.save_calls; // SELF: synchronous old-value return
        m.save_calls = value;
        return FinalTerms.int(&m.ctx, old);
    }
    m.pending = .{ .process_flag3 = .{ .pid = args[0], .value = value } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the ReqId ref to x0
}

/// `process_info/1` — the DOCUMENTED subset (see this section's doc comment)
/// as a `[{Item,Value}]` list. A dead/absent Pid → the WHOLE result is the
/// atom `undefined` (matches real BEAM's whole-result-undefined convention,
/// not a per-item one). Traps `process_info_all`. `deferred-E4-procdispatch`.
pub fn process_info_1(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    m.pending = .{ .process_info_all = .{ .pid = args[0] } };
    return FinalTerms.nil(&m.ctx);
}

/// `process_info/2` — a single item atom → `{Item, Value}` (real BEAM's
/// special case: an unregistered `registered_name` denotes the bare atom `[]`,
/// NOT `{registered_name, []}` — see `proc.zig`'s `procInfoValue`); a list of
/// item atoms → `[{Item,Value}, …]`. Every item name is validated
/// SYNCHRONOUSLY against the documented subset (`isSupportedProcessInfoItem`)
/// — an unsupported item, or a non-atom/improper item list, is a genuine
/// `badarg` raised HERE, before any trap is set (the entry-9(d) precedent).
/// `deferred-E4-procdispatch`.
pub fn process_info_2(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    const item = args[1];
    if (FinalTerms.repIsAtom(item)) {
        const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(item));
        if (!isSupportedProcessInfoItem(name)) return error.Badarg;
    } else if (FinalTerms.kindOf(&m.ctx, item) == .tuple) {
        // gap-stdlib-bif-audit: the ONLY supported TUPLE item is `{dictionary,
        // Key}` — a single-key projection of the target's process dictionary
        // (proc_lib's `$initial_call`/`$process_label` path). Any other tuple
        // (wrong arity, or a non-`dictionary` tag) is a genuine `badarg`, raised
        // HERE before the trap is set (host-verified: `{dictionary}` and
        // `{foo,bar}` both raise badarg — the entry-9(d) unsupported-item
        // precedent). The Key (element 1) is unconstrained — ANY term is a valid
        // key, and an absent key denotes the atom `undefined` at readout, never a
        // rejection.
        if (FinalTerms.tupleArity(&m.ctx, item) != 2) return error.Badarg;
        const tag = FinalTerms.tupleElem(&m.ctx, item, 0);
        if (!FinalTerms.repIsAtom(tag)) return error.Badarg;
        const tagname = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(tag));
        if (!std.mem.eql(u8, tagname, "dictionary")) return error.Badarg;
    } else {
        var cur = item;
        var guard: usize = 0;
        while (FinalTerms.kindOf(&m.ctx, cur) == .cons and guard < 64) : (guard += 1) {
            const head = FinalTerms.listHead(&m.ctx, cur);
            if (!FinalTerms.repIsAtom(head)) return error.Badarg;
            const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(head));
            if (!isSupportedProcessInfoItem(name)) return error.Badarg;
            cur = FinalTerms.listTail(&m.ctx, cur);
        }
        if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg; // improper list
    }
    m.pending = .{ .process_info_item = .{ .pid = args[0], .item = item } };
    return FinalTerms.nil(&m.ctx);
}

// ============================================================================
// E6.4 (Task 4): the process-SUSPENSION + system-task introspection family.
//
// suspend_process/2 + resume_process/1 are the counting-MONOID pair (host-
// verified on OTP-28: both return `true`; `resume_process` on a NON-suspended
// process raises `badarg`). They trap to proc.zig's `Process.suspend_count`
// (gated by `proc.schedulable` — a suspended process is never granted CPU), the
// suspension semantics the M7 scheduler now honors post-E6.1-SMP. The counting
// monoid (nested suspends need matching resumes; resume never drives the count
// below zero) is proven by the Zig law in proc.zig + the corpus differential
// (balanced suspend/resume folds `true` on both VMs).
//
// is_system_process/1, garbage_collect/1 and system_check/1 are the
// self-contained-or-flag rows of the family (host-verified): a normal process is
// never a system process (`false`); `erts_internal:garbage_collect(major|minor)`
// is a GC request that returns `true` (zigvm's copying GC is denote-preserving,
// so the request is observably `true`); `system_check(schedulers)` is `ok`. Each
// rejects an out-of-domain argument with a synchronous `badarg` (the entry-9(d)
// precedent), matching erts exactly. See DIVERGENCE entry 112.
// ============================================================================

/// `erts_internal:suspend_process/2` — `suspend_process(Pid, OptList)`. Traps
/// `suspend_proc`; proc.zig increments the target's `suspend_count` (the monoid).
/// A non-pid first arg raises `badarg` synchronously (host-verified). The
/// OptList (`asynchronous`/`unless_suspending`) is accepted-and-ignored — this
/// LOCAL model has no async-suspend window (the `spawn_opt` opts precedent);
/// both VMs fold the same `true` on the synchronous path the corpus exercises.
pub fn suspend_process_2(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    m.pending = .{ .suspend_proc = .{ .pid = args[0] } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes true|badarg to x0
}

/// gap-erl-cli-args (DIVERGENCE 598): `init:get_plain_arguments/0` — the `-extra`/
/// bare tokens the emulator passed after the boot flags, as a list of STRINGS
/// (charlists). Traps `init_plain_args`; proc.zig builds the list from the Vm's
/// parsed init argv (`[]` when no CLI args were given). The drop-in-`erl` contract
/// escripts/release-scripts read.
pub fn get_plain_arguments_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .{ .init_plain_args = .{} };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the string list to x0
}

/// gap-erl-cli-args: `init:get_argument/1` — `{ok, [[Value…]…]}` for a user init
/// flag (one inner list per OCCURRENCE), or `error` for a missing flag OR one the
/// `init` boot process CONSUMES (`-s`/`-run`/`-eval`/`-boot`/`-config`/`-name`/…,
/// per `Vm.initFlagConsumed`). The arg is a flag ATOM; a non-atom raises `badarg`
/// (the erts contract). Traps `init_get_argument`.
pub fn get_argument_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    m.pending = .{ .init_get_argument = .{ .flag = args[0] } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes {ok,_}|error to x0
}

/// gap-hof-parse (DIVERGENCE 673): `init:get_arguments/0` — the WHOLE parsed init
/// argv as `[{Flag, [Value…]}…]` (one tuple per flag occurrence, argv order), `[]`
/// when no CLI args were given. This is what `erl_features:keywords/0` reads to
/// discover `-enable-feature`/`-disable-feature` flags, so `erl_scan:scan_atom`
/// (every atom/keyword) needs it. Traps `init_get_arguments`.
pub fn get_arguments_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .{ .init_get_arguments = .{} };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the flag list to x0
}

/// `erlang:resume_process/1` — the monoid's other half. Traps `resume_proc`;
/// proc.zig decrements the target's `suspend_count` (never below zero — a
/// non-suspended target yields `badarg`, host-verified). A non-pid arg raises
/// `badarg` synchronously.
pub fn resume_process_1(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    m.pending = .{ .resume_proc = .{ .pid = args[0] } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes true|badarg to x0
}

/// `erts_internal:is_system_process/1` — `true` iff the target pid is a system
/// process (`Process.system`), else `false` (host-verified: a normal/self pid →
/// `false`). Traps `is_system_process` (the flag lives on the target Process, one
/// level up from a bare Machine — the process_info precedent). A non-pid → badarg.
pub fn is_system_process_1(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    m.pending = .{ .is_system_process = .{ .pid = args[0] } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes true|false to x0
}

/// `erts_internal:garbage_collect/1` — a GC request on the CALLING process,
/// returning `true` (host-verified for `major`/`minor`). SELF-CONTAINED: zigvm's
/// GC is a denote-preserving copying collector, so the request is observably
/// `true` with no term change (the collection itself is a Stratum-C effect). Any
/// type atom other than `major`/`minor` → synchronous `badarg` (host-verified).
pub fn garbage_collect_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    if (!std.mem.eql(u8, name, "major") and !std.mem.eql(u8, name, "minor")) return error.Badarg;
    // e48-gc-literal-area: the CAST-20 precondition is DISCHARGED — the
    // rootset now includes the ystack/dyn_literals/staged-exception terms and
    // the literal area is collection-exempt below the water line — so the
    // request runs the REAL denote-preserving collector (the suspend_fam
    // corpus differential is the standing end-to-end guard).
    gc.collectMachineRoots(m) catch return error.OutOfMemory;
    return boolTerm(m, true);
}

/// e47-a5/e48-gc-literal-area: `erlang:garbage_collect/0` — the erlang.erl
/// wrapper for `erts_internal:garbage_collect(major)` (resolveLibrary). Runs
/// the REAL collector (the CAST-20 bound discharged — see garbage_collect_1).
pub fn garbage_collect_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    gc.collectMachineRoots(m) catch return error.OutOfMemory;
    return boolTerm(m, true);
}

/// e48-appctl-handoff: `erlang:hibernate/0` (OTP-28) — GC-minimize the caller
/// and SUSPEND until a signal arrives; control resumes normally after the
/// call (the stack is KEPT — unlike hibernate/3), returning `ok`. A REAL
/// runtime dependency: OTP-30 proc_lib/gen_server hibernate idle processes —
/// the e47-a5 "cold" deferral crashed every resident tree that idled (found
/// by the appctl-handoff law's fractal RCA). Safe to really-collect since
/// e48-gc-literal-area (the trap interpret point is the safe point).
pub fn hibernate_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .hibernate_wait;
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes `ok` to x0
}

/// e47-a5: `erlang:alias/0` — the erlang.erl wrapper for `alias([])`
/// (resolveLibrary). Traps the E5.5 `make_alias` action; the Vm mints the ref,
/// registers it in the caller's alias table, and writes it to x0.
pub fn alias_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    m.pending = .{ .make_alias = .{ .dst = 0 } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the alias ref to x0
}

/// `erts_internal:system_check/1` — `system_check(schedulers)` returns the atom
/// `ok` (host-verified; it forces a scheduler liveness check that always succeeds
/// on a healthy node — both VMs are healthy). Any other argument → synchronous
/// `badarg` (host-verified). SELF-CONTAINED (a constant over the one valid arg).
pub fn system_check_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[0]));
    if (!std.mem.eql(u8, name, "schedulers")) return error.Badarg;
    return FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("ok"));
}

// ==== E7.5 (Task 5) — process-engine completions. One clearly-blocked group so
// the parallel E7.6 trace slice never straddles these edits. ====

/// E7.5 (Task 5): `erlang:hibernate/3` — `hibernate(Module, Function, ArgList)`.
/// Traps `.hibernate`; `proc.zig` (`doHibernate`) DISCARDS the calling process's
/// call stack and re-enters at `M:F/A` when the next message arrives (the MFA-
/// reentry homomorphism; the mailbox is preserved). Never returns to the caller —
/// the BIF stages the trap and writes a placeholder x0 that the reentry overwrites
/// (the arg list lands in x0..x[A-1], or is unread when A==0). `Module`/`Function`
/// must be atoms (else `badarg`, host-verified); the arg-list arity is validated
/// in `proc.zig` against the export index (an unresolvable MFA exits `undef`).
pub fn hibernate_3(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0]) or !FinalTerms.repIsAtom(args[1])) return error.Badarg;
    m.pending = .{ .hibernate = .{ .module = args[0], .func = args[1], .args = args[2] } };
    return FinalTerms.nil(&m.ctx); // placeholder; the reentry replaces control flow
}

/// E7.5 (Task 5): the async system-task queue op named by a `request_system_task`
/// request tuple's head atom. `garbage_collect` is the modeled op; every other
/// accepted op folds to the generic `other` (the request is enqueued, Result
/// `true`). A non-atom head defaults to `other` (still enqueued — the reply
/// contract does not depend on the op for a well-formed request).
fn sysTaskOpOf(m: *Machine, req: Term) ia.SysTaskOp {
    if (FinalTerms.kindOf(&m.ctx, req) != .tuple or FinalTerms.tupleArity(&m.ctx, req) < 2) return .other;
    const head = FinalTerms.tupleElem(&m.ctx, req, 0);
    if (!FinalTerms.repIsAtom(head)) return .other;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(head));
    if (std.mem.eql(u8, name, "garbage_collect")) return .garbage_collect;
    return .other;
}

/// E7.5 (Task 5): `erts_internal:request_system_task/3` —
/// `request_system_task(TargetPid, Prio, {Op, RequestId, ...})`. Traps
/// `.request_system_task`; `proc.zig` PARKS a `{RequestId, Result}` reply to the
/// REQUESTER (the calling process for /3) delivered on the next scheduler tick
/// (the E5.6 parked-reply protocol). Returns `true` synchronously. The request
/// tuple must carry `{Op, RequestId, ...}` (arity >= 2, `RequestId` any term);
/// otherwise `badarg`. NOT byte-EQ against the OTP-28 host — the internal request
/// encoding is a 28-vs-30 skew (host raises `badarg` on the /4 encoding, `undef`
/// on /3) — only the reply-delivery CONTRACT is law-proven (no false EQ).
pub fn request_system_task_3(m: *Machine, args: []const Term) BifError!Term {
    const req = args[2];
    if (FinalTerms.kindOf(&m.ctx, req) != .tuple or FinalTerms.tupleArity(&m.ctx, req) < 2) return error.Badarg;
    const reqid = FinalTerms.tupleElem(&m.ctx, req, 1);
    const self_term = try FinalTerms.pid(&m.ctx, m.self_pid, 0);
    m.pending = .{ .request_system_task = .{ .requester = self_term, .reqid = reqid, .op = sysTaskOpOf(m, req) } };
    return boolTerm(m, true);
}

/// E7.5 (Task 5): `erts_internal:request_system_task/4` —
/// `request_system_task(Requester, TargetPid, Prio, {Op, RequestId, ...})`. As /3
/// but the `{RequestId, Result}` reply is parked to the explicit `Requester` pid
/// (a non-pid Requester → `badarg`). Same 28-vs-30 skew as /3 (no host byte-EQ).
pub fn request_system_task_4(m: *Machine, args: []const Term) BifError!Term {
    if (!isLocalPid(m, args[0])) return error.Badarg;
    const req = args[3];
    if (FinalTerms.kindOf(&m.ctx, req) != .tuple or FinalTerms.tupleArity(&m.ctx, req) < 2) return error.Badarg;
    const reqid = FinalTerms.tupleElem(&m.ctx, req, 1);
    m.pending = .{ .request_system_task = .{ .requester = args[0], .reqid = reqid, .op = sysTaskOpOf(m, req) } };
    return boolTerm(m, true);
}

/// E5.6 (Task 6): `erts_internal:spawn_request/4` —
/// `spawn_request(Module, Function, ArgList, OptList)`, the LOCAL-node subset.
/// Traps `spawn_request`; `proc.zig` (`doSpawnRequest`) mints a ReqId ref,
/// spawns+RUNS the child over the live export index (the `spawn_mfa` machinery —
/// a resolvable `M:F/A` runs, an unresolvable one exits `undef`), honors
/// `link`/`monitor` opts, and PARKS the `{spawn_reply, ReqId, ok, ChildPid}`
/// reply for delivery on the NEXT scheduler tick (the async window the real SMP
/// protocol has — see `ParkedSpawn`). Returns the fresh ReqId ref via x0.
/// DIVERGENCE entry 72.
pub fn spawn_request_4(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .spawn_request = .{ .module = args[0], .func = args[1], .args = args[2], .opts = args[3] } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the ReqId ref to x0
}

fn properList(m: *Machine, list: Term) bool {
    var cur = list;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    return FinalTerms.kindOf(&m.ctx, cur) == .nil;
}

fn distSpawnBadarg(m: *Machine) BifError!Term {
    return atomTerm(m, "badarg");
}

fn distSpawnMfaOk(m: *Machine, mfa: Term) bool {
    if (FinalTerms.kindOf(&m.ctx, mfa) != .tuple or FinalTerms.tupleArity(&m.ctx, mfa) != 3) return false;
    if (!FinalTerms.repIsAtom(FinalTerms.tupleElem(&m.ctx, mfa, 0))) return false;
    if (!FinalTerms.repIsAtom(FinalTerms.tupleElem(&m.ctx, mfa, 1))) return false;
    return properList(m, FinalTerms.tupleElem(&m.ctx, mfa, 2));
}

const DistSpawnOpts = struct {
    spawns_monitor: bool = false,
    send_error_reply: bool = true,
    tag: Term,
    error_reason: Term,
};

fn parseDistSpawnOpts(m: *Machine, opts: Term, mode: ia.DistSpawnRequestMode) BifError!?DistSpawnOpts {
    var out = DistSpawnOpts{
        .tag = try atomTerm(m, "spawn_reply"),
        .error_reason = try atomTerm(m, "noconnection"),
    };

    var cur = opts;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const opt = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.repIsAtom(opt)) {
            if (atomIs(m, opt, "monitor")) out.spawns_monitor = true;
        } else if (FinalTerms.kindOf(&m.ctx, opt) == .tuple and FinalTerms.tupleArity(&m.ctx, opt) == 2) {
            const key = FinalTerms.tupleElem(&m.ctx, opt, 0);
            const val = FinalTerms.tupleElem(&m.ctx, opt, 1);
            if (atomIs(m, key, "reply_tag")) {
                if (mode != .spawn_request) return null;
                out.tag = val;
            } else if (atomIs(m, key, "reply")) {
                if (mode != .spawn_request) return null;
                if (atomIs(m, val, "yes") or atomIs(m, val, "error_only")) {
                    out.send_error_reply = true;
                } else if (atomIs(m, val, "no") or atomIs(m, val, "success_only")) {
                    out.send_error_reply = false;
                } else {
                    out.error_reason = try atomTerm(m, "badopt");
                    return out;
                }
            } else if (atomIs(m, key, "monitor")) {
                if (!properList(m, val)) {
                    if (mode != .spawn_request) return null;
                    out.error_reason = try atomTerm(m, "badopt");
                    return out;
                }
                out.spawns_monitor = true;
            } else if (atomIs(m, key, "link")) {
                if (!properList(m, val)) {
                    if (mode != .spawn_request) return null;
                    out.error_reason = try atomTerm(m, "badopt");
                    return out;
                }
            }
        }
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return null;
    return out;
}

/// E8.2i: `erts_internal:dist_spawn_request/4` — direct no-carrier remote spawn
/// request. The OTP30 direct BIF returns the atom `badarg` for invalid inputs,
/// not a raised exception. A valid non-local atom node with no carrier mints a
/// fresh request ref, returns `Ref` for `spawn_request` or `{Ref,Bool}` for the
/// spawn-opt shape, and sends the local spawn error reply unless `{reply,no}` or
/// `{reply,success_only}` suppresses error replies.
pub fn dist_spawn_request_4(m: *Machine, args: []const Term) BifError!Term {
    if (!isDistNodeNameAtom(m, args[0])) return distSpawnBadarg(m);
    if (!distSpawnMfaOk(m, args[1])) return distSpawnBadarg(m);

    const mode: ia.DistSpawnRequestMode = if (atomIs(m, args[3], "spawn_request")) .spawn_request else .spawn_opt;
    const opts = (try parseDistSpawnOpts(m, args[2], mode)) orelse return distSpawnBadarg(m);
    m.pending = .{ .dist_spawn_request = .{
        .mode = mode,
        .spawns_monitor = opts.spawns_monitor,
        .send_error_reply = opts.send_error_reply,
        .tag = opts.tag,
        .error_reason = opts.error_reason,
    } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the ref or {Ref,bool} to x0
}

fn distConnectionShapeOk(m: *Machine, conn: Term) bool {
    if (FinalTerms.kindOf(&m.ctx, conn) != .tuple or FinalTerms.tupleArity(&m.ctx, conn) != 2) return false;
    const cid = FinalTerms.tupleElem(&m.ctx, conn, 0);
    const ref = FinalTerms.tupleElem(&m.ctx, conn, 1);
    return FinalTerms.repIsSmall(cid) and FinalTerms.smallValOf(cid) >= 0 and FinalTerms.repIsRef(&m.ctx, ref);
}

fn distLiveOptsShapeOk(m: *Machine, opts: Term) bool {
    if (FinalTerms.kindOf(&m.ctx, opts) != .tuple or FinalTerms.tupleArity(&m.ctx, opts) != 2) return false;
    const dflags = FinalTerms.tupleElem(&m.ctx, opts, 0);
    const creation = FinalTerms.tupleElem(&m.ctx, opts, 1);

    return FinalTerms.repIsSmall(dflags) and FinalTerms.repIsSmall(creation) and FinalTerms.smallValOf(creation) >= 0;
}

/// E8.2j: `erts_internal:new_connection/1` — create or observe a pending
/// no-socket dist handle for a foreign node-name atom. The Vm owns the stable
/// node→handle table and writes `{ConnId,Ref}` to x0.
pub fn new_connection_1(m: *Machine, args: []const Term) BifError!Term {
    if (!isDistNodeNameAtom(m, args[0])) return error.Badarg;
    m.pending = .{ .new_dist_connection = .{ .node = args[0] } };
    return FinalTerms.nil(&m.ctx);
}

/// E8.2j: `erts_internal:abort_pending_connection/2` — validate the caller's
/// `{ConnId,Ref}` handle shape before the Vm checks node/handle identity.
pub fn abort_pending_connection_2(m: *Machine, args: []const Term) BifError!Term {
    if (!isDistNodeNameAtom(m, args[0])) return error.Badarg;
    if (!distConnectionShapeOk(m, args[1])) return error.Badarg;
    m.pending = .{ .abort_pending_dist_connection = .{ .node = args[0], .conn = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// E8.2m/E8.2s: `erlang:setnode/2` — route valid-looking local-node identity
/// attempts to the Vm carrier owner. The Vm installs only when a live registered
/// `net_kernel` owner exists; invalid node/creation shapes reject here.
pub fn setnode_2(m: *Machine, args: []const Term) BifError!Term {
    if (!isDistNodeNameAtom(m, args[0])) return error.Badarg;
    if (!FinalTerms.repIsSmall(args[1]) or FinalTerms.smallValOf(args[1]) < 0) return error.Badarg;
    m.pending = .{ .set_dist_node = .{ .node = args[0], .creation = args[1] } };
    return FinalTerms.nil(&m.ctx);
}

/// E8.2m/E8.2r/E8.2s: `erts_internal:create_dist_channel/3` — route a valid-looking
/// channel request to the Vm carrier owner. With no pending entry the Vm still
/// returns atom `badarg`; with a pending entry, active local identity, and live
/// local controller it may promote the carrier precursor. Malformed requests
/// return `badarg` here.
pub fn create_dist_channel_3(m: *Machine, args: []const Term) BifError!Term {
    if (!isDistNodeNameAtom(m, args[0])) return atomTerm(m, "badarg");
    if (!FinalTerms.repIsPid(&m.ctx, args[1])) return atomTerm(m, "badarg");
    if (!distLiveOptsShapeOk(m, args[2])) return atomTerm(m, "badarg");
    m.pending = .{ .create_dist_channel = .{ .node = args[0], .controller = args[1], .opts = args[2] } };
    return FinalTerms.nil(&m.ctx);
}

/// E5.6 (Task 6): `erlang:spawn_request_abandon/1`. Traps `abandon_spawn`;
/// `proc.zig` (`doAbandonSpawn`) answers `true` iff the caller's spawn-reply for
/// this ReqId is STILL PARKED (not yet delivered by the scheduler tick) — the
/// reply is then cancelled and the child orphaned; otherwise `false` (already
/// delivered, already abandoned, or an unknown/foreign ref). This is the real
/// erts contract over the deterministic parked-reply window (DIVERGENCE entry
/// 72): the abandon-BEFORE-delivery `true` is a Vm law (the SMP race that yields
/// it is not host-deterministic, so it is NOT in the differential corpus); the
/// host-deterministic `false` cases (abandon AFTER the reply, abandon of a
/// foreign ref) ARE differentially proven.
pub fn spawn_request_abandon_1(m: *Machine, args: []const Term) BifError!Term {
    m.pending = .{ .abandon_spawn = .{ .ref = args[0] } };
    return boolTerm(m, false); // placeholder; the VM writes true|false to x0
}

/// E4.3 (Task 3): `erts_internal:spawn_system_process/3` —
/// `spawn_system_process(Mod, Func, Args)` spawns a SYSTEM process running
/// `Mod:Func(Args…)`. The kernel bring-up set (prim_file's port owner,
/// socket_registry, the code/purger servers) runs as system processes so an
/// unrelated supervision-tree crash cannot cascade into them. Traps
/// `spawn_system`; the VM (`proc.zig`) flags the child `Process.system` (the
/// no-kill-cascade law) and writes its pid to x0. `Mod`/`Func` must be atoms
/// and `Args` a proper list (a synchronous `badarg` otherwise — validated here
/// before the trap, the entry-9(d) precedent). NOT ledger-EQ: a system process
/// that RETURNS is a fatal node error on the oracle (crash dump), so it is not
/// differentially observable to completion — see DIVERGENCE entry 21 (E4.3
/// amendment). Stays `deferred-E4-systemproc`.
pub fn spawn_system_process_3(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0]) or !FinalTerms.repIsAtom(args[1])) return error.Badarg;
    // Args must be a proper (bounded) list.
    var cur = args[2];
    var guard: usize = 0;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons and guard < 64) : (guard += 1)
        cur = FinalTerms.listTail(&m.ctx, cur);
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg;
    m.pending = .{ .spawn_system = .{ .module = args[0], .func = args[1], .args = args[2] } };
    return FinalTerms.nil(&m.ctx); // placeholder; the VM writes the system-process pid to x0
}

// ============================================================================
// Laws
// ============================================================================

const AtomTable = ta.AtomTable;

test "LAW gap-eep76-priority-flag: process_flag(priority, Level) reads/writes the process priority (old value, default normal); bad level + priority_messages (rc off) → badarg (DIVERGENCE 602)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const at = struct {
        fn a(mm: *Machine, s: []const u8) Term {
            return FinalTerms.atom(&mm.ctx, mm.ctx.atoms.intern(s) catch unreachable);
        }
    }.a;
    const prio = at(&m, "priority");

    // default is `normal`; setting `high` returns the OLD `normal` and stores high.
    try std.testing.expectEqual(ia.ProcPriority.normal, m.priority);
    const r1 = try process_flag_2(&m, &.{ prio, at(&m, "high") });
    try std.testing.expectEqualStrings("normal", m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(r1)));
    try std.testing.expectEqual(ia.ProcPriority.high, m.priority); // the field actually moved

    // roundtrip: setting `low` now returns the OLD `high`.
    const r2 = try process_flag_2(&m, &.{ prio, at(&m, "low") });
    try std.testing.expectEqualStrings("high", m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(r2)));
    try std.testing.expectEqual(ia.ProcPriority.low, m.priority);

    // all four levels are accepted.
    _ = try process_flag_2(&m, &.{ prio, at(&m, "max") });
    try std.testing.expectEqual(ia.ProcPriority.max, m.priority);

    // rejection: an unknown level → badarg (kills a mutant that defaults it).
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ prio, at(&m, "bogus") }));
    // the priority stays at `max` after the rejected set (no partial write).
    try std.testing.expectEqual(ia.ProcPriority.max, m.priority);
    // a non-atom level → badarg.
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ prio, FinalTerms.int(&m.ctx, 1) }));

    // EEP-76 feature-off contract: process_flag(priority_messages, _) → badarg on the
    // pinned rc (the flag is unimplemented — the disclosed bound, oracle-confirmed).
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ at(&m, "priority_messages"), at(&m, "true") }));
}

test "LAW gap-atom-and-heap-limits max_heap_size: process_flag(max_heap_size, Int|Map) round-trips the 4-key erts config map (OLD value returned), byte-EQ shape vs OTP-30; negative/non-int-non-map/bad-typed-key → badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const at = struct {
        fn a(mm: *Machine, s: []const u8) Term {
            return FinalTerms.atom(&mm.ctx, mm.ctx.atoms.intern(s) catch unreachable);
        }
    }.a;
    const get = struct {
        fn g(mm: *Machine, map: Term, key: []const u8) Term {
            return FinalTerms.mapGet(&mm.ctx, map, FinalTerms.atom(&mm.ctx, mm.ctx.atoms.intern(key) catch unreachable)).?;
        }
    }.g;
    const flag = at(&m, "max_heap_size");

    // Default config #{size=>0, kill=>true, error_logger=>true, include_shared_binaries=>false}.
    // Setting size=1_000_000 returns the OLD (default) map (byte-EQ shape vs OTP-30).
    const old0 = try process_flag_2(&m, &.{ flag, FinalTerms.int(&m.ctx, 1_000_000) });
    try std.testing.expect(FinalTerms.repIsMap(&m.ctx, old0) and FinalTerms.mapSize(&m.ctx, old0) == 4);
    try std.testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(get(&m, old0, "size")));
    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(get(&m, old0, "kill")));
    try std.testing.expectEqual(m.bool_true, FinalTerms.atomIdxOf(get(&m, old0, "error_logger")));
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(get(&m, old0, "include_shared_binaries")));

    // Read-back: the stored size is now 1_000_000.
    const cur = try process_flag_2(&m, &.{ flag, FinalTerms.int(&m.ctx, 0) });
    try std.testing.expectEqual(@as(i64, 1_000_000), FinalTerms.smallValOf(get(&m, cur, "size")));

    // The MAP form sets a subset (kill=>false, error_logger=>false, size=>5000).
    const inmap = try FinalTerms.mapNew(&m.ctx, &.{ at(&m, "kill"), at(&m, "error_logger"), at(&m, "size") }, &.{ boolTerm(&m, false), boolTerm(&m, false), FinalTerms.int(&m.ctx, 5000) });
    _ = try process_flag_2(&m, &.{ flag, inmap });
    const cur2 = try process_flag_2(&m, &.{ flag, FinalTerms.int(&m.ctx, 0) });
    try std.testing.expectEqual(@as(i64, 5000), FinalTerms.smallValOf(get(&m, cur2, "size")));
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(get(&m, cur2, "kill")));
    try std.testing.expectEqual(m.bool_false, FinalTerms.atomIdxOf(get(&m, cur2, "error_logger")));

    // TOTALITY: negative size / non-int-non-map / a present key of the wrong type → badarg.
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ flag, FinalTerms.int(&m.ctx, -1) }));
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ flag, at(&m, "foo") }));
    const badmap = try FinalTerms.mapNew(&m.ctx, &.{at(&m, "kill")}, &.{FinalTerms.int(&m.ctx, 7)}); // kill must be a bool
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ flag, badmap }));
}

test "LAW gap-process-flag-tuning (DIVERGENCE 707): process_flag(min_heap_size|min_bin_vheap_size|message_queue_data|sensitive, _) accept+round-trip the OLD value (was badarg); OTP-30 defaults 233/46422/on_heap/false; bad values → badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const at = struct {
        fn a(mm: *Machine, s: []const u8) Term {
            return FinalTerms.atom(&mm.ctx, mm.ctx.atoms.intern(s) catch unreachable);
        }
    }.a;

    // min_heap_size: default 233 (byte-EQ vs OTP-30), returns OLD, then stores.
    const mhs = at(&m, "min_heap_size");
    try std.testing.expectEqual(@as(i64, 233), FinalTerms.smallValOf(try process_flag_2(&m, &.{ mhs, FinalTerms.int(&m.ctx, 500) })));
    try std.testing.expectEqual(@as(i64, 500), FinalTerms.smallValOf(try process_flag_2(&m, &.{ mhs, FinalTerms.int(&m.ctx, 999) }))); // round-trip (exact; OTP rounds — repr-coupled, disclosed)
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ mhs, FinalTerms.int(&m.ctx, -1) })); // negative
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ mhs, at(&m, "x") })); // non-int

    // min_bin_vheap_size: default 46422 (byte-EQ vs OTP-30).
    try std.testing.expectEqual(@as(i64, 46422), FinalTerms.smallValOf(try process_flag_2(&m, &.{ at(&m, "min_bin_vheap_size"), FinalTerms.int(&m.ctx, 100) })));

    // message_queue_data: default on_heap; off_heap round-trips; a bad atom → badarg.
    const mqd = at(&m, "message_queue_data");
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try process_flag_2(&m, &.{ mqd, at(&m, "off_heap") }), at(&m, "on_heap")));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try process_flag_2(&m, &.{ mqd, at(&m, "on_heap") }), at(&m, "off_heap"))); // round-trip
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ mqd, at(&m, "bogus") }));

    // sensitive: default false; true round-trips.
    const sen = at(&m, "sensitive");
    try std.testing.expect(FinalTerms.atomIdxOf(try process_flag_2(&m, &.{ sen, at(&m, "true") })) == m.bool_false);
    try std.testing.expect(FinalTerms.atomIdxOf(try process_flag_2(&m, &.{ sen, at(&m, "false") })) == m.bool_true); // round-trip
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ sen, FinalTerms.int(&m.ctx, 1) })); // non-bool
}

test "LAW E8.2s node/0 routes local identity through the Vm owner" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const r = try node_0(&m, &.{});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r, FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .get_dist_node);
    m.pending = null;
    // idempotent / no-args-sensitive: calling again parks the same observation.
    const r2 = try node_0(&m, &.{});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r2, FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .get_dist_node);
}

test "LAW E8.2n nodes/0 routes connected-node observation through the Vm owner" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const r = try nodes_0(&m, &.{});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r, FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .list_dist_nodes);
    try std.testing.expect(m.pending.?.list_dist_nodes.connected);
    try std.testing.expect(m.pending.?.list_dist_nodes.visible);
    try std.testing.expect(!m.pending.?.list_dist_nodes.hidden);
    try std.testing.expect(!m.pending.?.list_dist_nodes.known);
    try std.testing.expect(!m.pending.?.list_dist_nodes.this_node);
}

test "LAW E8.2n nodes/1 filter projection routes remote selectors through the Vm owner" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const connected = try atomTerm(&m, "connected");
    const visible = try atomTerm(&m, "visible");
    const hidden = try atomTerm(&m, "hidden");
    const known = try atomTerm(&m, "known");
    const this_node = try atomTerm(&m, "this");

    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try nodes_1(&m, &.{connected}), FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .list_dist_nodes);
    try std.testing.expect(m.pending.?.list_dist_nodes.connected);
    try std.testing.expect(!m.pending.?.list_dist_nodes.visible);
    try std.testing.expect(!m.pending.?.list_dist_nodes.hidden);
    try std.testing.expect(!m.pending.?.list_dist_nodes.known);
    try std.testing.expect(!m.pending.?.list_dist_nodes.this_node);
    m.pending = null;

    const empty_visible_hidden = try FinalTerms.cons(&m.ctx, visible, try FinalTerms.cons(&m.ctx, hidden, FinalTerms.nil(&m.ctx)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try nodes_1(&m, &.{empty_visible_hidden}), FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .list_dist_nodes);
    try std.testing.expect(!m.pending.?.list_dist_nodes.connected);
    try std.testing.expect(m.pending.?.list_dist_nodes.visible);
    try std.testing.expect(m.pending.?.list_dist_nodes.hidden);
    try std.testing.expect(!m.pending.?.list_dist_nodes.known);
    try std.testing.expect(!m.pending.?.list_dist_nodes.this_node);
    m.pending = null;

    const known_result = try nodes_1(&m, &.{known});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, known_result, FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .list_dist_nodes);
    try std.testing.expect(!m.pending.?.list_dist_nodes.connected);
    try std.testing.expect(!m.pending.?.list_dist_nodes.visible);
    try std.testing.expect(!m.pending.?.list_dist_nodes.hidden);
    try std.testing.expect(m.pending.?.list_dist_nodes.known);
    try std.testing.expect(!m.pending.?.list_dist_nodes.this_node);
    m.pending = null;

    const union_opts = try FinalTerms.cons(&m.ctx, connected, try FinalTerms.cons(&m.ctx, this_node, try FinalTerms.cons(&m.ctx, known, FinalTerms.nil(&m.ctx))));
    const union_result = try nodes_1(&m, &.{union_opts});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, union_result, FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .list_dist_nodes);
    try std.testing.expect(m.pending.?.list_dist_nodes.connected);
    try std.testing.expect(!m.pending.?.list_dist_nodes.visible);
    try std.testing.expect(!m.pending.?.list_dist_nodes.hidden);
    try std.testing.expect(m.pending.?.list_dist_nodes.known);
    try std.testing.expect(m.pending.?.list_dist_nodes.this_node);
    m.pending = null;

    try std.testing.expectError(error.Badarg, nodes_1(&m, &.{try atomTerm(&m, "all")}));
    try std.testing.expectError(error.Badarg, nodes_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    const improper = try FinalTerms.cons(&m.ctx, known, FinalTerms.int(&m.ctx, 1));
    try std.testing.expectError(error.Badarg, nodes_1(&m, &.{improper}));
    try std.testing.expect(m.pending == null);
}

test "LAW E8.2o nodes/2 option-map projection routes remote selectors through the Vm owner" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const known = try atomTerm(&m, "known");
    const connected = try atomTerm(&m, "connected");
    const node_type = try atomTerm(&m, "node_type");
    const connection_id = try atomTerm(&m, "connection_id");
    const unknown = try atomTerm(&m, "foo");
    const empty_map = try FinalTerms.mapNew(&m.ctx, &.{}, &.{});

    const empty_info = try nodes_2(&m, &.{ known, empty_map });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, empty_info, FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .list_dist_node_infos);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.connected);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.visible);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.hidden);
    try std.testing.expect(m.pending.?.list_dist_node_infos.known);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.this_node);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.node_type);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.connection_id);
    m.pending = null;

    const full_req = try FinalTerms.mapNew(
        &m.ctx,
        &.{ node_type, connection_id },
        &.{ boolTerm(&m, true), boolTerm(&m, true) },
    );
    const full = try nodes_2(&m, &.{ known, full_req });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, full, FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .list_dist_node_infos);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.connected);
    try std.testing.expect(m.pending.?.list_dist_node_infos.known);
    try std.testing.expect(m.pending.?.list_dist_node_infos.node_type);
    try std.testing.expect(m.pending.?.list_dist_node_infos.connection_id);
    m.pending = null;

    const false_req = try FinalTerms.mapNew(
        &m.ctx,
        &.{ node_type, connection_id },
        &.{ boolTerm(&m, false), boolTerm(&m, true) },
    );
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try nodes_2(&m, &.{ known, false_req }), FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .list_dist_node_infos);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.node_type);
    try std.testing.expect(m.pending.?.list_dist_node_infos.connection_id);
    m.pending = null;

    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try nodes_2(&m, &.{ connected, full_req }), FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .list_dist_node_infos);
    try std.testing.expect(m.pending.?.list_dist_node_infos.connected);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.visible);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.hidden);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.known);
    try std.testing.expect(!m.pending.?.list_dist_node_infos.this_node);
    try std.testing.expect(m.pending.?.list_dist_node_infos.node_type);
    try std.testing.expect(m.pending.?.list_dist_node_infos.connection_id);
    m.pending = null;
    try std.testing.expectError(error.Badarg, nodes_2(&m, &.{ known, FinalTerms.nil(&m.ctx) }));
    try std.testing.expect(m.pending == null);
    const unknown_req = try FinalTerms.mapNew(&m.ctx, &.{unknown}, &.{boolTerm(&m, true)});
    try std.testing.expectError(error.Badarg, nodes_2(&m, &.{ known, unknown_req }));
    const bad_value_req = try FinalTerms.mapNew(&m.ctx, &.{node_type}, &.{try atomTerm(&m, "this")});
    try std.testing.expectError(error.Badarg, nodes_2(&m, &.{ known, bad_value_req }));
}

test "LAW E8.2c dist local observers match the no-carrier OTP surface" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try get_creation_0(&m, &.{}), FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .get_dist_creation);
    m.pending = null;

    const local = try FinalTerms.pid(&m.ctx, 3, 0);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try dflag_unicode_io_1(&m, &.{local}), boolTerm(&m, true)));

    const foreign_node = try m.ctx.atoms.intern("other@host");
    const foreign = try FinalTerms.pidExt(&m.ctx, 100, 7, foreign_node, 3);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try dflag_unicode_io_1(&m, &.{foreign}), FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .dist_dflag_unicode_io);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.dist_dflag_unicode_io.pid, foreign));
    m.pending = null;

    try std.testing.expectError(error.Badarg, dflag_unicode_io_1(&m, &.{FinalTerms.int(&m.ctx, 0)}));
    try std.testing.expect(m.pending == null);
}

test "LAW E8.2h/E8.2v exit_signal/2,3 routes local ids and foreign pid carrier intent" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const local_pid = try FinalTerms.pid(&m.ctx, 2, 0);
    const reason = try atomTerm(&m, "boom");
    const ok2 = try exit_signal_2(&m, &.{ local_pid, reason });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ok2, boolTerm(&m, true)));
    try std.testing.expect(m.pending.? == .exit_to);
    m.pending = null;

    const priority = try atomTerm(&m, "priority");
    const prio_opts = try FinalTerms.cons(&m.ctx, priority, FinalTerms.nil(&m.ctx));
    const ok3 = try exit_signal_3(&m, &.{ local_pid, reason, prio_opts });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ok3, boolTerm(&m, true)));
    try std.testing.expect(m.pending.? == .exit_to);
    m.pending = null;

    const bad_opt = try atomTerm(&m, "bad");
    const bad_opts = try FinalTerms.cons(&m.ctx, bad_opt, FinalTerms.nil(&m.ctx));
    try std.testing.expectError(error.Badarg, exit_signal_3(&m, &.{ local_pid, reason, bad_opts }));
    const improper_opts = try FinalTerms.cons(&m.ctx, priority, FinalTerms.int(&m.ctx, 0));
    try std.testing.expectError(error.Badarg, exit_signal_3(&m, &.{ local_pid, reason, improper_opts }));

    const local_ref = try FinalTerms.ref(&m.ctx, .{ 0, 1, 2 });
    _ = try exit_signal_2(&m, &.{ local_ref, reason });
    try std.testing.expect(m.pending.? == .exit_to);
    m.pending = null;

    const local_port = try FinalTerms.port(&m.ctx, 4);
    _ = try exit_signal_2(&m, &.{ local_port, reason });
    try std.testing.expect(m.pending.? == .port_close_sig);
    m.pending = null;

    const foreign_node = try m.ctx.atoms.intern("other@host");
    const foreign_pid = try FinalTerms.pidExt(&m.ctx, 100, 7, foreign_node, 3);
    const fp = try exit_signal_2(&m, &.{ foreign_pid, reason });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, fp, boolTerm(&m, true)));
    try std.testing.expect(m.pending.? == .remote_exit_signal);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.remote_exit_signal.pid, foreign_pid));
    m.pending = null;

    const foreign_ref = try FinalTerms.refExt(&m.ctx, .{ 0, 1, 2 }, foreign_node, 3);
    const fr = try exit_signal_2(&m, &.{ foreign_ref, reason });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, fr, boolTerm(&m, true)));
    try std.testing.expect(m.pending == null);

    const foreign_port = try FinalTerms.portExt(&m.ctx, 5, foreign_node, 3);
    try std.testing.expectError(error.Badarg, exit_signal_2(&m, &.{ foreign_port, reason }));
    try std.testing.expectError(error.Badarg, exit_signal_2(&m, &.{ FinalTerms.int(&m.ctx, 0), reason }));
}

test "LAW E8.2i dist_spawn_request/4 matches the no-carrier direct-BIF surface" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const remote = try atomTerm(&m, "other@host");
    const local = try localNodeAtom(&m);
    const erlang = try atomTerm(&m, "erlang");
    const self_atom = try atomTerm(&m, "self");
    const mfa = try FinalTerms.tuple(&m.ctx, &.{ erlang, self_atom, FinalTerms.nil(&m.ctx) });
    const spawn_request_atom = try atomTerm(&m, "spawn_request");
    const spawn_opt_atom = try atomTerm(&m, "spawn_opt");

    const bad_node = try dist_spawn_request_4(&m, &.{ local, mfa, FinalTerms.nil(&m.ctx), spawn_request_atom });
    try std.testing.expect(atomIs(&m, bad_node, "badarg"));
    try std.testing.expect(m.pending == null);

    const bad_mfa = try dist_spawn_request_4(&m, &.{ remote, try FinalTerms.tuple(&m.ctx, &.{ erlang, self_atom }), FinalTerms.nil(&m.ctx), spawn_request_atom });
    try std.testing.expect(atomIs(&m, bad_mfa, "badarg"));
    try std.testing.expect(m.pending == null);

    _ = try dist_spawn_request_4(&m, &.{ remote, mfa, FinalTerms.nil(&m.ctx), spawn_request_atom });
    try std.testing.expect(m.pending.? == .dist_spawn_request);
    try std.testing.expectEqual(ia.DistSpawnRequestMode.spawn_request, m.pending.?.dist_spawn_request.mode);
    try std.testing.expect(!m.pending.?.dist_spawn_request.spawns_monitor);
    try std.testing.expect(m.pending.?.dist_spawn_request.send_error_reply);
    try std.testing.expect(atomIs(&m, m.pending.?.dist_spawn_request.tag, "spawn_reply"));
    try std.testing.expect(atomIs(&m, m.pending.?.dist_spawn_request.error_reason, "noconnection"));
    m.pending = null;

    const monitor_opt = try FinalTerms.cons(&m.ctx, try atomTerm(&m, "monitor"), FinalTerms.nil(&m.ctx));
    _ = try dist_spawn_request_4(&m, &.{ remote, mfa, monitor_opt, spawn_opt_atom });
    try std.testing.expectEqual(ia.DistSpawnRequestMode.spawn_opt, m.pending.?.dist_spawn_request.mode);
    try std.testing.expect(m.pending.?.dist_spawn_request.spawns_monitor);
    m.pending = null;

    const reply_no = try FinalTerms.tuple(&m.ctx, &.{ try atomTerm(&m, "reply"), try atomTerm(&m, "no") });
    const reply_no_opts = try FinalTerms.cons(&m.ctx, reply_no, FinalTerms.nil(&m.ctx));
    _ = try dist_spawn_request_4(&m, &.{ remote, mfa, reply_no_opts, spawn_request_atom });
    try std.testing.expect(!m.pending.?.dist_spawn_request.send_error_reply);
    m.pending = null;

    const reply_bad = try FinalTerms.tuple(&m.ctx, &.{ try atomTerm(&m, "reply"), try atomTerm(&m, "bad") });
    const reply_bad_opts = try FinalTerms.cons(&m.ctx, reply_bad, FinalTerms.nil(&m.ctx));
    _ = try dist_spawn_request_4(&m, &.{ remote, mfa, reply_bad_opts, spawn_request_atom });
    try std.testing.expect(atomIs(&m, m.pending.?.dist_spawn_request.error_reason, "badopt"));
    m.pending = null;

    const improper_opts = try FinalTerms.cons(&m.ctx, try atomTerm(&m, "monitor"), FinalTerms.int(&m.ctx, 0));
    const bad_opts = try dist_spawn_request_4(&m, &.{ remote, mfa, improper_opts, spawn_request_atom });
    try std.testing.expect(atomIs(&m, bad_opts, "badarg"));
}

test "LAW E8.2j pending dist connection BIFs validate node names and handle shape" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const remote = try atomTerm(&m, "other@host");
    const local = try localNodeAtom(&m);
    const bare = try atomTerm(&m, "other");
    const conn = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 1), try FinalTerms.ref(&m.ctx, .{ 0, 0, 7 }) });

    try std.testing.expectError(error.Badarg, new_connection_1(&m, &.{local}));
    try std.testing.expectError(error.Badarg, new_connection_1(&m, &.{bare}));
    _ = try new_connection_1(&m, &.{remote});
    try std.testing.expect(m.pending.? == .new_dist_connection);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.new_dist_connection.node, remote));
    m.pending = null;

    try std.testing.expectError(error.Badarg, abort_pending_connection_2(&m, &.{ local, conn }));
    try std.testing.expectError(error.Badarg, abort_pending_connection_2(&m, &.{ remote, try FinalTerms.ref(&m.ctx, .{ 0, 0, 8 }) }));
    _ = try abort_pending_connection_2(&m, &.{ remote, conn });
    try std.testing.expect(m.pending.? == .abort_pending_dist_connection);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.abort_pending_dist_connection.conn, conn));
}

test "LAW E8.2m channel-start BIF rows route through the Vm carrier owner" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const remote = try atomTerm(&m, "other@host");
    const bare = try atomTerm(&m, "other");
    const controller = try FinalTerms.pid(&m.ctx, m.self_pid, 0);
    const opts = try FinalTerms.tuple(&m.ctx, &.{
        FinalTerms.int(&m.ctx, otp30_dflags_default),
        FinalTerms.int(&m.ctx, 4),
    });

    _ = try setnode_2(&m, &.{ remote, FinalTerms.int(&m.ctx, 4) });
    try std.testing.expect(m.pending.? == .set_dist_node);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.set_dist_node.node, remote));
    m.pending = null;
    try std.testing.expectError(error.Badarg, setnode_2(&m, &.{ bare, FinalTerms.int(&m.ctx, 0) }));
    try std.testing.expectError(error.Badarg, setnode_2(&m, &.{ remote, FinalTerms.int(&m.ctx, -1) }));
    try std.testing.expect(m.pending == null);

    const good_shape = try create_dist_channel_3(&m, &.{ remote, controller, opts });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, good_shape, FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .create_dist_channel);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.create_dist_channel.node, remote));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.create_dist_channel.controller, controller));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.create_dist_channel.opts, opts));
    m.pending = null;
    const bad_opts = try create_dist_channel_3(&m, &.{ remote, controller, FinalTerms.int(&m.ctx, 0) });
    try std.testing.expect(atomIs(&m, bad_opts, "badarg"));
    const bad_node = try create_dist_channel_3(&m, &.{ bare, controller, opts });
    try std.testing.expect(atomIs(&m, bad_node, "badarg"));
    try std.testing.expect(m.pending == null);
}

test "LAW E8.2e get_dflags no-carrier OTP30 tuple is exact" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const got = try get_dflags_0(&m, &.{});
    const want = try FinalTerms.tuple(&m.ctx, &.{
        try atomTerm(&m, "erts_dflags"),
        FinalTerms.int(&m.ctx, otp30_dflags_default),
        FinalTerms.int(&m.ctx, otp30_dflags_mandatory),
        FinalTerms.int(&m.ctx, otp30_dflags_addable),
        FinalTerms.int(&m.ctx, otp30_dflags_rejectable),
        FinalTerms.int(&m.ctx, otp30_dflags_strict_order),
    });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got, want));
}

test "LAW E8.2d monitor_node no-carrier observer surface is host-compatible" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const local = try localNodeAtom(&m);
    const other = try atomTerm(&m, "other@host");
    const truth = boolTerm(&m, true);
    const falsity = boolTerm(&m, false);

    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try monitor_node_2(&m, &.{ local, truth }), truth));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try monitor_node_2(&m, &.{ local, falsity }), truth));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try monitor_node_3(&m, &.{ local, truth, FinalTerms.nil(&m.ctx) }), truth));
    const allow_passive = try FinalTerms.cons(&m.ctx, try atomTerm(&m, "allow_passive_connect"), FinalTerms.nil(&m.ctx));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try monitor_node_3(&m, &.{ local, truth, allow_passive }), truth));

    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try monitor_node_2(&m, &.{ other, truth }), FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .monitor_dist_node);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.monitor_dist_node.node, other));
    try std.testing.expect(m.pending.?.monitor_dist_node.enabled);
    m.pending = null;
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try monitor_node_3(&m, &.{ other, falsity, FinalTerms.nil(&m.ctx) }), FinalTerms.nil(&m.ctx)));
    try std.testing.expect(m.pending.? == .monitor_dist_node);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.pending.?.monitor_dist_node.node, other));
    try std.testing.expect(!m.pending.?.monitor_dist_node.enabled);
    m.pending = null;

    try std.testing.expectError(error.Badarg, monitor_node_2(&m, &.{ local, try atomTerm(&m, "maybe") }));
    try std.testing.expectError(error.Badarg, monitor_node_3(&m, &.{ local, truth, try atomTerm(&m, "bad") }));
    try std.testing.expectError(error.Badarg, monitor_node_2(&m, &.{ FinalTerms.int(&m.ctx, 0), truth }));
    try std.testing.expect(m.pending == null);
}

test "LAW e4-registered0 registered/0 traps list_registered (registry-backed, no longer constant-[])" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // no Vm here (bare Machine), so this proves ONLY the trap-setting half —
    // the actual sorted-registry-contents law lives in proc.zig (the Vm owns
    // `registry.Registry`), same split as the E3.8 register/whereis laws.
    try std.testing.expect(m.pending == null);
    const r = try registered_0(&m, &.{});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r, FinalTerms.nil(&m.ctx))); // placeholder
    try std.testing.expect(m.pending != null and m.pending.? == .list_registered);
}

test "LAW E2.11 process_flag(trap_exit, _) returns the OLD value and sets the new one" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const trap_exit_atom = FinalTerms.atom(&m.ctx, try atoms.intern("trap_exit"));

    // Default flag state is `false`.
    try std.testing.expect(!m.trap_exit);
    const r1 = try process_flag_2(&m, &.{ trap_exit_atom, boolTerm(&m, true) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r1, boolTerm(&m, false))); // OLD value
    try std.testing.expect(m.trap_exit); // NEW value took effect

    const r2 = try process_flag_2(&m, &.{ trap_exit_atom, boolTerm(&m, false) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r2, boolTerm(&m, true))); // OLD value
    try std.testing.expect(!m.trap_exit);
}

test "LAW E2.11 process_flag(trap_exit, _) round-trip restores the original flag" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const trap_exit_atom = FinalTerms.atom(&m.ctx, try atoms.intern("trap_exit"));
    m.trap_exit = true; // an arbitrary starting flag

    const before = m.trap_exit;
    const old = try process_flag_2(&m, &.{ trap_exit_atom, boolTerm(&m, false) });
    _ = try process_flag_2(&m, &.{ trap_exit_atom, old });
    try std.testing.expectEqual(before, m.trap_exit);
}

test "LAW E3.7 self/0 returns the running process's pid TERM (number == proc index)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    m.self_pid = 9; // as proc.Vm.spawn assigns

    const r = try self_0(&m, &.{});
    try std.testing.expect(FinalTerms.repIsPid(&m.ctx, r));
    try std.testing.expectEqual(@as(u64, 9), FinalTerms.pidNumber(&m.ctx, r));
    try std.testing.expectEqual(@as(u64, 0), FinalTerms.pidSerial(&m.ctx, r));
    // no trap: self/0 is self-contained (reachable via bif0 today → EQ).
    try std.testing.expect(m.pending == null);
}

test "LAW E3.7/E8.2t node/1 default local identity is nonode@nohost; foreign preserved; non-identity is badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const p = try FinalTerms.pid(&m.ctx, 3, 0);
    const r = try node_1(&m, &.{p});
    try std.testing.expect(FinalTerms.repIsAtom(r));
    try std.testing.expectEqualStrings("nonode@nohost", m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(r)));
    // a port and a ref are also local identities.
    _ = try node_1(&m, &.{try FinalTerms.port(&m.ctx, 1)});
    _ = try node_1(&m, &.{try FinalTerms.ref(&m.ctx, .{ 1, 2, 3 })});
    // a non-identity argument (an int) is badarg.
    try std.testing.expectError(error.Badarg, node_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));

    // E5.7: node/1 of a FOREIGN identity is that identity's OWN node atom.
    const fn_idx = try m.ctx.atoms.intern("other@host");
    const fp = try FinalTerms.pidExt(&m.ctx, 100, 7, fn_idx, 3);
    const rf = try node_1(&m, &.{fp});
    try std.testing.expectEqualStrings("other@host", m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(rf)));
    const foreign_port = try FinalTerms.portExt(&m.ctx, 5, fn_idx, 3);
    const rpf = try node_1(&m, &.{foreign_port});
    try std.testing.expectEqualStrings("other@host", m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(rpf)));
}

test "LAW E3.7 spawn/send/exit BIFs set the correct scheduler trap (call_ext-deferred surface)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // spawn_1: a fun arg traps spawn_fun{link=false}; a non-fun is badarg.
    const f = try FinalTerms.makeFun(&m.ctx, 0, 0, &.{});
    const sr = try spawn_1(&m, &.{f});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, sr, FinalTerms.nil(&m.ctx))); // placeholder
    try std.testing.expect(m.pending != null and m.pending.? == .spawn_fun);
    try std.testing.expect(!m.pending.?.spawn_fun.link);
    m.pending = null;
    try std.testing.expectError(error.Badarg, spawn_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    m.pending = null;

    // spawn_link_1 sets link=true.
    _ = try spawn_link_1(&m, &.{f});
    try std.testing.expect(m.pending.?.spawn_fun.link);
    m.pending = null;

    // send_2: a pid target traps send_to and RETURNS the message; a non-pid is badarg.
    const pid = try FinalTerms.pid(&m.ctx, 2, 0);
    const msg = FinalTerms.int(&m.ctx, 42);
    const rr = try send_2(&m, &.{ pid, msg });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, rr, msg)); // send returns the msg
    try std.testing.expect(m.pending != null and m.pending.? == .send_to);
    m.pending = null;
    try std.testing.expectError(error.Badarg, send_2(&m, &.{ FinalTerms.int(&m.ctx, 1), msg }));
    m.pending = null;

    // exit/1 traps exit_proc; exit/2 traps exit_to and returns true.
    _ = try exit_1(&m, &.{FinalTerms.int(&m.ctx, 7)});
    try std.testing.expect(m.pending.? == .exit_proc);
    m.pending = null;
    const er = try exit_2(&m, &.{ pid, FinalTerms.int(&m.ctx, 7) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, er, boolTerm(&m, true)));
    try std.testing.expect(m.pending.? == .exit_to);
    m.pending = null;

    // is_process_alive/1 traps is_alive; processes/0 traps list_processes.
    _ = try is_process_alive_1(&m, &.{pid});
    try std.testing.expect(m.pending.? == .is_alive);
    m.pending = null;
    _ = try processes_0(&m, &.{});
    try std.testing.expect(m.pending.? == .list_processes);
    m.pending = null;

    // spawn_opt/4 honors the `link` option atom in its opts list.
    const link_atom = FinalTerms.atom(&m.ctx, try atoms.intern("link"));
    const opts = try FinalTerms.cons(&m.ctx, link_atom, FinalTerms.nil(&m.ctx));
    const ma = FinalTerms.atom(&m.ctx, try atoms.intern("m"));
    const fa = FinalTerms.atom(&m.ctx, try atoms.intern("f"));
    _ = try spawn_opt_4(&m, &.{ ma, fa, FinalTerms.nil(&m.ctx), opts });
    try std.testing.expect(m.pending.? == .spawn_mfa and m.pending.?.spawn_mfa.link);
    m.pending = null;
}

test "LAW E2.11 process_flag/2 REJECTS an unknown flag or a non-boolean value" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const trap_exit_atom = FinalTerms.atom(&m.ctx, try atoms.intern("trap_exit"));
    const priority_atom = FinalTerms.atom(&m.ctx, try atoms.intern("priority"));

    // unknown flag name.
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ priority_atom, boolTerm(&m, true) }));
    // non-boolean value for the known flag.
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ trap_exit_atom, FinalTerms.int(&m.ctx, 1) }));
    // non-atom flag position.
    try std.testing.expectError(error.Badarg, process_flag_2(&m, &.{ FinalTerms.int(&m.ctx, 1), boolTerm(&m, true) }));
}

// LAW E24-T7 — timer-BIF option parsing gates keys PER BIF, matching OTP-30
// `erl_hl_timer.c:parse_bif_timer_options` (@2352). The dark-branch sweep of
// the never-tested option BIFs (send_after/4, start_timer/4, cancel_timer/2,
// read_timer/2) surfaced a REAL divergence: `read_timer/2` accepted `{info,_}`,
// which OTP rejects (`parse_bif_timer_options(_, &async, NULL, NULL)` — the
// `info` pointer is NULL → `default`-adjacent `!info` → return 0 → badarg).
// This law pins the per-BIF gate: each BIF accepts EXACTLY the keys whose OTP
// out-pointer is non-NULL, and rejects the rest with `badarg` — plus the shared
// shape rejections (non-tuple, wrong arity, non-atom key, non-bool value,
// improper tail) and the default settings for `[]`.
test "LAW E24-T7 timer-BIF option parsing gates keys per BIF (OTP parse_bif_timer_options)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const t = boolTerm(&m, true);
    const fbool = boolTerm(&m, false);
    const dest = try FinalTerms.pid(&m.ctx, 2, 0); // a valid timer destination
    const time = FinalTerms.int(&m.ctx, 100); // a valid non-negative relative delay
    const tref = try FinalTerms.ref(&m.ctx, .{ 5, 6, 7 }); // a live TRef stand-in
    const abs_key = FinalTerms.atom(&m.ctx, try atoms.intern("abs"));
    const async_key = FinalTerms.atom(&m.ctx, try atoms.intern("async"));
    const info_key = FinalTerms.atom(&m.ctx, try atoms.intern("info"));
    const bogus_key = FinalTerms.atom(&m.ctx, try atoms.intern("nope"));

    // Build a single `[{Key, Val}]` option list.
    const opt1 = struct {
        fn f(mm: *Machine, k: Term, v: Term) !Term {
            const tup = try FinalTerms.tuple(&mm.ctx, &.{ k, v });
            return FinalTerms.cons(&mm.ctx, tup, FinalTerms.nil(&mm.ctx));
        }
    }.f;

    // --- start_timer/4 & send_after/4: ABS is the only gated key. ---
    // {abs, true} is accepted → traps timer_start with abs=true.
    _ = try start_timer_4(&m, &.{ time, dest, FinalTerms.int(&m.ctx, 0), try opt1(&m, abs_key, t) });
    try std.testing.expect(m.pending.? == .timer_start and m.pending.?.timer_start.abs);
    m.pending = null;
    // {abs, false} default-ish → abs=false; empty list → abs=false.
    _ = try send_after_4(&m, &.{ time, dest, FinalTerms.int(&m.ctx, 0), FinalTerms.nil(&m.ctx) });
    try std.testing.expect(m.pending.? == .timer_start and !m.pending.?.timer_start.abs);
    m.pending = null;
    // {async,_} and {info,_} are UNGATED for start/send → badarg (OTP NULL ptr).
    try std.testing.expectError(error.Badarg, start_timer_4(&m, &.{ time, dest, FinalTerms.int(&m.ctx, 0), try opt1(&m, async_key, t) }));
    try std.testing.expectError(error.Badarg, send_after_4(&m, &.{ time, dest, FinalTerms.int(&m.ctx, 0), try opt1(&m, info_key, t) }));

    // --- cancel_timer/2: async AND info gated; abs is NOT. ---
    _ = try cancel_timer_2(&m, &.{ tref, try opt1(&m, info_key, fbool) });
    try std.testing.expect(m.pending.? == .timer_cancel and !m.pending.?.timer_cancel.info);
    m.pending = null;
    _ = try cancel_timer_2(&m, &.{ tref, try opt1(&m, async_key, t) });
    try std.testing.expect(m.pending.? == .timer_cancel and m.pending.?.timer_cancel.is_async);
    m.pending = null;
    // default (empty list): info=true, is_async=false.
    _ = try cancel_timer_2(&m, &.{ tref, FinalTerms.nil(&m.ctx) });
    try std.testing.expect(m.pending.?.timer_cancel.info and !m.pending.?.timer_cancel.is_async);
    m.pending = null;
    // {abs,_} is UNGATED for cancel → badarg.
    try std.testing.expectError(error.Badarg, cancel_timer_2(&m, &.{ tref, try opt1(&m, abs_key, t) }));

    // --- read_timer/2: ONLY async gated. THE FIX: {info,_} is badarg. ---
    _ = try read_timer_2(&m, &.{ tref, try opt1(&m, async_key, t) });
    try std.testing.expect(m.pending.? == .timer_read and m.pending.?.timer_read.is_async);
    m.pending = null;
    // {info,_} — OTP passes NULL for info here → badarg (pre-e24-t7 BUG accepted it).
    try std.testing.expectError(error.Badarg, read_timer_2(&m, &.{ tref, try opt1(&m, info_key, fbool) }));
    // {abs,_} also badarg for read.
    try std.testing.expectError(error.Badarg, read_timer_2(&m, &.{ tref, try opt1(&m, abs_key, t) }));

    // --- Shared shape rejections (exercised on cancel_timer/2's parser). ---
    // non-boolean value.
    try std.testing.expectError(error.Badarg, cancel_timer_2(&m, &.{ tref, try opt1(&m, async_key, FinalTerms.int(&m.ctx, 1)) }));
    // unknown key.
    try std.testing.expectError(error.Badarg, cancel_timer_2(&m, &.{ tref, try opt1(&m, bogus_key, t) }));
    // a non-tuple list element.
    try std.testing.expectError(error.Badarg, cancel_timer_2(&m, &.{ tref, try FinalTerms.cons(&m.ctx, t, FinalTerms.nil(&m.ctx)) }));
    // a wrong-arity tuple ({async} arity 1).
    const arity1 = try FinalTerms.tuple(&m.ctx, &.{async_key});
    try std.testing.expectError(error.Badarg, cancel_timer_2(&m, &.{ tref, try FinalTerms.cons(&m.ctx, arity1, FinalTerms.nil(&m.ctx)) }));
    // a non-atom key.
    const badkey_tup = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 1), t });
    try std.testing.expectError(error.Badarg, cancel_timer_2(&m, &.{ tref, try FinalTerms.cons(&m.ctx, badkey_tup, FinalTerms.nil(&m.ctx)) }));
    // an improper (non-nil) tail.
    const good_tup = try FinalTerms.tuple(&m.ctx, &.{ async_key, t });
    try std.testing.expectError(error.Badarg, cancel_timer_2(&m, &.{ tref, try FinalTerms.cons(&m.ctx, good_tup, t) }));
}

// ============================================================================
// E3.8: link/monitor/registry BIF-surface laws
// ============================================================================

test "LAW E3.8 link/unlink/monitor/demonitor BIFs set the correct scheduler trap" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const pid = try FinalTerms.pid(&m.ctx, 3, 0);

    // link/1 traps link_to and returns true directly.
    const lr = try link_1(&m, &.{pid});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, lr, boolTerm(&m, true)));
    try std.testing.expect(m.pending.? == .link_to);
    m.pending = null;
    try std.testing.expectError(error.Badarg, link_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    m.pending = null;

    // link/2 delegates to link/1 (opts ignored).
    const opts = try FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, try atoms.intern("priority")), FinalTerms.nil(&m.ctx));
    _ = try link_2(&m, &.{ pid, opts });
    try std.testing.expect(m.pending.? == .link_to);
    m.pending = null;

    // unlink/1 traps unlink_to.
    _ = try unlink_1(&m, &.{pid});
    try std.testing.expect(m.pending.? == .unlink_to);
    m.pending = null;

    // monitor/2 requires the atom `process`; traps monitor_to.
    const process_atom = FinalTerms.atom(&m.ctx, try atoms.intern("process"));
    _ = try monitor_2(&m, &.{ process_atom, pid });
    try std.testing.expect(m.pending.? == .monitor_to);
    m.pending = null;
    try std.testing.expectError(error.Badarg, monitor_2(&m, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("port")), pid }));
    m.pending = null;

    // monitor/3 delegates (opts ignored).
    _ = try monitor_3(&m, &.{ process_atom, pid, FinalTerms.nil(&m.ctx) });
    try std.testing.expect(m.pending.? == .monitor_to);
    m.pending = null;

    // demonitor/1 traps the plain demonitor_ref.
    const ref = FinalTerms.int(&m.ctx, 7);
    _ = try demonitor_1(&m, &.{ref});
    try std.testing.expect(m.pending.? == .demonitor_ref);
    m.pending = null;

    // demonitor/2 WITHOUT flush traps demonitor_ref; WITH [flush] traps demonitor_flush.
    _ = try demonitor_2(&m, &.{ ref, FinalTerms.nil(&m.ctx) });
    try std.testing.expect(m.pending.? == .demonitor_ref);
    m.pending = null;
    const flush_opts = try FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, try atoms.intern("flush")), FinalTerms.nil(&m.ctx));
    _ = try demonitor_2(&m, &.{ ref, flush_opts });
    try std.testing.expect(m.pending.? == .demonitor_flush);
    m.pending = null;
}

test "LAW E3.8 register/unregister/whereis BIFs set the correct scheduler trap" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const pid = try FinalTerms.pid(&m.ctx, 1, 0);
    const name = FinalTerms.atom(&m.ctx, try atoms.intern("myname"));

    _ = try register_2(&m, &.{ name, pid });
    try std.testing.expect(m.pending.? == .register_name);
    m.pending = null;
    try std.testing.expectError(error.Badarg, register_2(&m, &.{ FinalTerms.int(&m.ctx, 1), pid }));
    m.pending = null;
    try std.testing.expectError(error.Badarg, register_2(&m, &.{ name, FinalTerms.int(&m.ctx, 1) }));
    m.pending = null;

    _ = try unregister_1(&m, &.{name});
    try std.testing.expect(m.pending.? == .unregister_name);
    m.pending = null;
    try std.testing.expectError(error.Badarg, unregister_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    m.pending = null;

    _ = try whereis_1(&m, &.{name});
    try std.testing.expect(m.pending.? == .whereis_name);
    m.pending = null;
    try std.testing.expectError(error.Badarg, whereis_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    m.pending = null;
}

test "LAW E3.8 exit/3, group_leader family, process_flag/3 BIFs set the correct trap" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const pid = try FinalTerms.pid(&m.ctx, 4, 0);

    // exit/3 shares exit/2's exit_to trap; opts ignored.
    const er = try exit_3(&m, &.{ pid, FinalTerms.int(&m.ctx, 7), FinalTerms.nil(&m.ctx) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, er, boolTerm(&m, true)));
    try std.testing.expect(m.pending.? == .exit_to);
    m.pending = null;

    // group_leader/0 is SELF-CONTAINED (no trap) — mirrors self_0.
    m.group_leader = 5;
    const gl = try group_leader_0(&m, &.{});
    try std.testing.expect(FinalTerms.repIsPid(&m.ctx, gl));
    try std.testing.expectEqual(@as(u64, 5), FinalTerms.pidNumber(&m.ctx, gl));
    try std.testing.expect(m.pending == null);

    // erts_internal:group_leader/2,3 trap set_group_leader.
    _ = try group_leader_2(&m, &.{ pid, pid });
    try std.testing.expect(m.pending.? == .set_group_leader);
    m.pending = null;
    _ = try group_leader_3(&m, &.{ pid, pid, FinalTerms.int(&m.ctx, 99) });
    try std.testing.expect(m.pending.? == .set_group_leader);
    m.pending = null;
    try std.testing.expectError(error.Badarg, group_leader_2(&m, &.{ FinalTerms.int(&m.ctx, 1), pid }));
    m.pending = null;

    // erts_internal:process_flag/3 (E5.6): `save_calls` only. A non-self pid traps
    // process_flag3 (the async ref form); self is synchronous (old value, no
    // trap); an unsupported flag returns the `badarg` ATOM (never a raise/trap).
    const save_calls_atom = FinalTerms.atom(&m.ctx, try atoms.intern("save_calls"));
    _ = try process_flag_3(&m, &.{ pid, save_calls_atom, FinalTerms.int(&m.ctx, 3) });
    try std.testing.expect(m.pending.? == .process_flag3); // pid.number 4 != self 0
    m.pending = null;
    const self_pid_term = try FinalTerms.pid(&m.ctx, m.self_pid, 0);
    const old = try process_flag_3(&m, &.{ self_pid_term, save_calls_atom, FinalTerms.int(&m.ctx, 5) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, old, FinalTerms.int(&m.ctx, 0))); // old default 0
    try std.testing.expect(m.pending == null);
    try std.testing.expectEqual(@as(i64, 5), m.save_calls); // new value set
    const priority_atom = FinalTerms.atom(&m.ctx, try atoms.intern("priority"));
    const bad = try process_flag_3(&m, &.{ pid, priority_atom, FinalTerms.int(&m.ctx, 1) });
    try std.testing.expect(FinalTerms.repIsAtom(bad) and
        std.mem.eql(u8, atoms.nameOf(FinalTerms.atomIdxOf(bad)), "badarg"));
    try std.testing.expect(m.pending == null);
}

test "LAW E6.6 dirty erts_internal rows: notsup rejection (arg-independent) + executing-dirty false + perf-unit positive" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // notsup rejection: the restricted dirty code-check entries raise error:notsup
    // regardless of (here ill-typed) arguments — the process/context restriction
    // dominates, exactly the purger-row differential.
    const notsup = try atoms.intern("notsup");
    const junk = FinalTerms.int(&m.ctx, 123);
    const expectNotsup = struct {
        fn f(mm: *Machine, ns: ta.AtomIdx, got: BifError!Term) !void {
            try std.testing.expectError(error.Raise, got);
            const staged = mm.bif_raise orelse return error.TestUnexpectedResult;
            mm.bif_raise = null;
            try std.testing.expectEqual(ia.ExcClass.error_, staged.class);
            try std.testing.expect(FinalTerms.eqlExact(&mm.ctx, staged.reason, FinalTerms.atom(&mm.ctx, ns)));
        }
    }.f;
    try expectNotsup(&m, notsup, check_dirty_process_code_2(&m, &.{ junk, junk }));
    try expectNotsup(&m, notsup, dirty_process_handle_signals_1(&m, &.{junk}));

    // is_process_executing_dirty/1: false for a well-typed pid, badarg otherwise.
    const self_pid = try FinalTerms.pid(&m.ctx, m.self_pid, 0);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try is_process_executing_dirty_1(&m, &.{self_pid}), boolTerm(&m, false)));
    try std.testing.expectError(error.Badarg, is_process_executing_dirty_1(&m, &.{junk}));

    // perf_counter_unit/0: a positive integer (property-folded observable).
    const u = try perf_counter_unit_0(&m, &.{});
    try std.testing.expect(FinalTerms.repIsSmall(u) and FinalTerms.smallValOf(u) > 0);
}

test "LAW E3.8 process_info/1,2 set the correct trap; unsupported item is a synchronous badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const pid = try FinalTerms.pid(&m.ctx, 2, 0);

    _ = try process_info_1(&m, &.{pid});
    try std.testing.expect(m.pending.? == .process_info_all);
    m.pending = null;
    try std.testing.expectError(error.Badarg, process_info_1(&m, &.{FinalTerms.int(&m.ctx, 1)}));
    m.pending = null;

    const status_atom = FinalTerms.atom(&m.ctx, try atoms.intern("status"));
    _ = try process_info_2(&m, &.{ pid, status_atom });
    try std.testing.expect(m.pending.? == .process_info_item);
    m.pending = null;

    // a supported LIST of items is fine.
    const links_atom = FinalTerms.atom(&m.ctx, try atoms.intern("links"));
    const items = try FinalTerms.cons(&m.ctx, status_atom, try FinalTerms.cons(&m.ctx, links_atom, FinalTerms.nil(&m.ctx)));
    _ = try process_info_2(&m, &.{ pid, items });
    try std.testing.expect(m.pending.? == .process_info_item);
    m.pending = null;

    // an UNSUPPORTED item (entry-9(d) precedent) is a synchronous badarg —
    // NO trap is set (m.pending stays null).
    const heap_size_atom = FinalTerms.atom(&m.ctx, try atoms.intern("heap_size"));
    try std.testing.expectError(error.Badarg, process_info_2(&m, &.{ pid, heap_size_atom }));
    try std.testing.expect(m.pending == null);
    const bad_items = try FinalTerms.cons(&m.ctx, status_atom, try FinalTerms.cons(&m.ctx, heap_size_atom, FinalTerms.nil(&m.ctx)));
    try std.testing.expectError(error.Badarg, process_info_2(&m, &.{ pid, bad_items }));
    try std.testing.expect(m.pending == null);
}

test "LAW gap-stdlib-bif-audit process_info/2 tuple item {dictionary,Key}: accept + rejection" {
    // The tuple item {dictionary, Key} is the ONLY supported tuple form (proc_lib
    // reads it for $initial_call/$process_label). Its shape is validated
    // SYNCHRONOUSLY: a well-formed {dictionary, AnyKey} sets the trap; every other
    // tuple (wrong arity, non-`dictionary` tag) is a genuine badarg with NO trap
    // set (host-verified: `{dictionary}` and `{foo,bar}` both raise badarg).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const pid = try FinalTerms.pid(&m.ctx, 2, 0);
    const dict_atom = FinalTerms.atom(&m.ctx, try atoms.intern("dictionary"));

    // {dictionary, foo} — accepted, trap set (Key is ANY term).
    const foo = FinalTerms.atom(&m.ctx, try atoms.intern("foo"));
    const ok_item = try FinalTerms.tuple(&m.ctx, &.{ dict_atom, foo });
    _ = try process_info_2(&m, &.{ pid, ok_item });
    try std.testing.expect(m.pending.? == .process_info_item);
    m.pending = null;

    // {dictionary, {1,2}} — Key is a compound term, still accepted.
    const compound_key = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) });
    const ok_item2 = try FinalTerms.tuple(&m.ctx, &.{ dict_atom, compound_key });
    _ = try process_info_2(&m, &.{ pid, ok_item2 });
    try std.testing.expect(m.pending.? == .process_info_item);
    m.pending = null;

    // {dictionary} — arity-1 tuple → badarg, no trap.
    const arity1 = try FinalTerms.tuple(&m.ctx, &.{dict_atom});
    try std.testing.expectError(error.Badarg, process_info_2(&m, &.{ pid, arity1 }));
    try std.testing.expect(m.pending == null);

    // {dictionary, a, b} — arity-3 tuple → badarg, no trap.
    const arity3 = try FinalTerms.tuple(&m.ctx, &.{ dict_atom, foo, foo });
    try std.testing.expectError(error.Badarg, process_info_2(&m, &.{ pid, arity3 }));
    try std.testing.expect(m.pending == null);

    // {foo, bar} — a 2-tuple with a NON-`dictionary` tag → badarg, no trap.
    const bar = FinalTerms.atom(&m.ctx, try atoms.intern("bar"));
    const wrong_tag = try FinalTerms.tuple(&m.ctx, &.{ foo, bar });
    try std.testing.expectError(error.Badarg, process_info_2(&m, &.{ pid, wrong_tag }));
    try std.testing.expect(m.pending == null);
}

test "LAW E5.6 spawn_request/4 traps spawn_request; spawn_request_abandon/1 traps abandon_spawn" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const ma = FinalTerms.atom(&m.ctx, try atoms.intern("m"));
    const fa = FinalTerms.atom(&m.ctx, try atoms.intern("f"));

    _ = try spawn_request_4(&m, &.{ ma, fa, FinalTerms.nil(&m.ctx), FinalTerms.nil(&m.ctx) });
    try std.testing.expect(m.pending.? == .spawn_request);
    m.pending = null;

    // E5.6: abandon now TRAPS (the VM answers true|false over the parked window).
    _ = try spawn_request_abandon_1(&m, &.{try FinalTerms.ref(&m.ctx, .{ 0, 0, 1 })});
    try std.testing.expect(m.pending.? == .abandon_spawn);
    m.pending = null;
}

// ============================================================================
// E6.5 (Task 5): the system introspection family laws (bounded, leak-free).
// ============================================================================

test "LAW gap-real-metrics wall-clock-real: statistics(wall_clock) is REAL clock ms — first read {T,T-basis D==T==0}, MONOTONE, and Diff == the Total delta (not the fabricated {0,0})" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const wc = FinalTerms.atom(&m.ctx, try atoms.intern("wall_clock"));

    // First read: the lazy epoch — Total and Diff share the observation basis.
    const t1 = try statistics_1(&m, &.{wc});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, t1) == .tuple and FinalTerms.tupleArity(&m.ctx, t1) == 2);
    const total1 = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t1, 0));
    const diff1 = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t1, 1));
    try std.testing.expectEqual(total1, diff1); // same basis (mutant: last seeded 0 ⇒ diff1 = raw clock ≠ 0)
    try std.testing.expectEqual(@as(i64, 0), total1);

    // A REAL bounded delay (spin on the SAME seam until ≥3ms elapse — the real
    // monotonic clock bounds the loop at 3ms wall time), then: monotone Total,
    // and REAL advance (kills the fabricated-constant mutant — {0,0} can't move).
    const spin_from = m.clock.monotonic(1000);
    while (m.clock.monotonic(1000) - spin_from < 3) {}
    const t2 = try statistics_1(&m, &.{wc});
    const total2 = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t2, 0));
    const diff2 = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t2, 1));
    try std.testing.expect(total2 >= total1); // MONOTONICITY
    try std.testing.expect(total2 >= 2); // the clock REALLY advanced (≥2ms of a 3ms sleep)
    try std.testing.expectEqual(total2 - total1, diff2); // Diff ≡ the Total delta (mutant: last not updated breaks a THIRD read)

    // Third read immediately: Diff resets against the SECOND read's basis.
    const t3 = try statistics_1(&m, &.{wc});
    const total3 = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t3, 0));
    const diff3 = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t3, 1));
    try std.testing.expectEqual(total3 - total2, diff3); // last WAS advanced by read 2
}

test "LAW gap-real-metrics runtime-real: statistics(runtime) is REAL per-process CPU-time ms — first read {T,T-basis D==T==0}, MONOTONE Total, Diff resets each call, and REALLY advances under load (not the fabricated {0,0})" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const rt = FinalTerms.atom(&m.ctx, try atoms.intern("runtime"));

    // First read: the lazy epoch — Total and Diff share the observation basis.
    const t1 = try statistics_1(&m, &.{rt});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, t1) == .tuple and FinalTerms.tupleArity(&m.ctx, t1) == 2);
    const total1 = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t1, 0));
    const diff1 = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t1, 1));
    try std.testing.expectEqual(total1, diff1); // same basis
    try std.testing.expectEqual(@as(i64, 0), total1);

    // Burn REAL CPU (a busy arithmetic loop — accrues process CPU time), bounded
    // by wall time so a coarse-CPU-clock host can never hang the driver. Real CPU
    // time advances → the raw CPU reading moves past the epoch (kills the
    // fabricated-constant mutant: {0,0} is frozen). Bound: 2s of wall time; on any
    // real host a busy loop yields ≥1ms of CPU well within that.
    const wall_from = m.clock.monotonic(1000);
    var sink: u64 = 0;
    while (m.clock.processCpuTime(1000) - @as(i128, m.stat_runtime_epoch_ms.?) < 1) {
        var i: u64 = 0;
        while (i < 200_000) : (i += 1) sink +%= i *% 2654435761;
        if (m.clock.monotonic(1000) - wall_from > 2000) break; // 2s wall safety bound
    }
    std.mem.doNotOptimizeAway(sink);
    // The epoch is fixed; take a fresh pair of reads to assert the algebra cleanly.
    const tr_a = try statistics_1(&m, &.{rt});
    const total_a = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, tr_a, 0));
    try std.testing.expect(total_a >= 1); // CPU REALLY advanced (mutant: {0,0} can't)
    try std.testing.expect(total_a >= total1); // MONOTONICITY

    const tb = try statistics_1(&m, &.{rt});
    const total_b = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, tb, 0));
    const diff_b = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, tb, 1));
    try std.testing.expect(total_b >= total_a); // MONOTONICITY
    try std.testing.expectEqual(total_b - total_a, diff_b); // Diff ≡ Total delta (SinceLast reset each call)
    try std.testing.expect(diff_b >= 0); // HONESTY: CPU time never runs backward
}

test "LAW E6.5 statistics reductions monotone + bump_reductions raises the counter" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const reds = FinalTerms.atom(&m.ctx, try atoms.intern("reductions"));

    m.reductions = 5;
    const t1 = try statistics_1(&m, &.{reds});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, t1) == .tuple and FinalTerms.tupleArity(&m.ctx, t1) == 2);
    const total1 = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t1, 0));
    try std.testing.expectEqual(@as(i64, 5), total1);

    // bump_reductions returns `true` and RAISES the running counter.
    const b = try bump_reductions_1(&m, &.{FinalTerms.int(&m.ctx, 10)});
    try std.testing.expect(FinalTerms.repIsAtom(b) and FinalTerms.atomIdxOf(b) == m.bool_true);
    try std.testing.expectEqual(@as(u64, 15), m.reductions);

    const t2 = try statistics_1(&m, &.{reds});
    const total2 = FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t2, 0));
    // MONOTONICITY: a later reductions reading never decreases (the property the
    // corpus folds). Mutant m2 (bump the WRONG process) breaks this.
    try std.testing.expect(total2 >= total1);
    try std.testing.expectEqual(@as(i64, 15), total2);

    // A negative bump is `badarg` (totality), the counter untouched.
    try std.testing.expectError(error.Badarg, bump_reductions_1(&m, &.{FinalTerms.int(&m.ctx, -1)}));
    try std.testing.expectEqual(@as(u64, 15), m.reductions);
}

test "LAW e50-bump ADDITIVITY (monoid) + TOTALITY: bump_reductions is additive on the reduction counter, identity at 0, order-free, and rejects non-nonneg-int args (the {R} bump-cost contract)" {
    // gap-reduction-cost-model. SEMANTIC DOMAIN: `erlang:bump_reductions/1` is the
    // operator that charges N extra reductions to the running process's counter.
    // Its denotation is the monoid homomorphism (ℕ, +, 0) → (counter, +, no-op):
    // bumping N raises `m.reductions` by exactly N, composing additively; a bump
    // of 0 is the identity; the return is always the `true` atom (the erts
    // contract — bump_reductions/1 does NOT expose the old count). A non-nonneg
    // integer argument is `badarg` (the partial→total rejection law).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // ADDITIVITY: each bump raises the counter by EXACTLY its argument; returns `true`.
    m.reductions = 0;
    for ([_]u64{ 0, 1, 7, 1000, 250_000 }) |n| {
        const before = m.reductions;
        const r = try bump_reductions_1(&m, &.{FinalTerms.int(&m.ctx, @intCast(n))});
        try std.testing.expect(FinalTerms.repIsAtom(r) and FinalTerms.atomIdxOf(r) == m.bool_true);
        try std.testing.expectEqual(before + n, m.reductions);
    }

    // HOMOMORPHISM / ASSOCIATIVITY: bump N then M == one bump of (N+M).
    var m2 = try Machine.init(gpa, &atoms);
    defer m2.deinit();
    m2.reductions = 100;
    _ = try bump_reductions_1(&m2, &.{FinalTerms.int(&m2.ctx, 40)});
    _ = try bump_reductions_1(&m2, &.{FinalTerms.int(&m2.ctx, 2)});
    var m3 = try Machine.init(gpa, &atoms);
    defer m3.deinit();
    m3.reductions = 100;
    _ = try bump_reductions_1(&m3, &.{FinalTerms.int(&m3.ctx, 42)});
    try std.testing.expectEqual(m2.reductions, m3.reductions); // 100+40+2 == 100+42

    // IDENTITY: a bump of 0 leaves the counter fixed.
    const fixed = m3.reductions;
    _ = try bump_reductions_1(&m3, &.{FinalTerms.int(&m3.ctx, 0)});
    try std.testing.expectEqual(fixed, m3.reductions);

    // TOTALITY / REJECTION: a negative int and a non-integer (atom) are `badarg`
    // and leave the counter UNTOUCHED (partial→total via rejection).
    try std.testing.expectError(error.Badarg, bump_reductions_1(&m3, &.{FinalTerms.int(&m3.ctx, -1)}));
    try std.testing.expectEqual(fixed, m3.reductions);
    const an_atom = FinalTerms.atom(&m3.ctx, try atoms.intern("notint"));
    try std.testing.expectError(error.Badarg, bump_reductions_1(&m3, &.{an_atom}));
    try std.testing.expectEqual(fixed, m3.reductions);
}

test "LAW E6.5 system_info deterministic version-independent subset + unmodeled rejects" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const ws = try system_info_1(&m, &.{FinalTerms.atom(&m.ctx, try atoms.intern("wordsize"))});
    try std.testing.expectEqual(@as(i64, 8), FinalTerms.smallValOf(ws));

    // {wordsize, internal} → 8 too.
    const wint = try FinalTerms.tuple(&m.ctx, &.{
        FinalTerms.atom(&m.ctx, try atoms.intern("wordsize")),
        FinalTerms.atom(&m.ctx, try atoms.intern("internal")),
    });
    try std.testing.expectEqual(@as(i64, 8), FinalTerms.smallValOf(try system_info_1(&m, &.{wint})));

    // machine → the "BEAM" char list (head 'B' == 66).
    const mach = try system_info_1(&m, &.{FinalTerms.atom(&m.ctx, try atoms.intern("machine"))});
    try std.testing.expectEqual(@as(i64, 'B'), FinalTerms.smallValOf(FinalTerms.listHead(&m.ctx, mach)));

    // endian → little (atom).
    const en = try system_info_1(&m, &.{FinalTerms.atom(&m.ctx, try atoms.intern("endian"))});
    try std.testing.expect(atomIs(&m, en, "little"));

    // DIVERGENCE 720: the PIN-CONSTANT version strings (OTP 30-rc0) are byte-EQ.
    const SI = struct {
        fn str(mm: *Machine, aa: *AtomTable, item: []const u8, want: []const u8) !void {
            const r = try system_info_1(mm, &.{FinalTerms.atom(&mm.ctx, try aa.intern(item))});
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
    try SI.str(&m, &atoms, "otp_release", "30");
    try SI.str(&m, &atoms, "version", "17.0.3");
    try SI.str(&m, &atoms, "nif_version", "2.18");
    try SI.str(&m, &atoms, "driver_version", "3.3");

    // A genuinely UNMODELED item still rejects (never a WRONG value) — W-11 honesty.
    try std.testing.expectError(error.Badarg, system_info_1(&m, &.{FinalTerms.atom(&m.ctx, try atoms.intern("cpu_topology"))}));
}

test "LAW gap-get-cookie (DIVERGENCE 722): erlang:get_cookie/0 is the atom nocookie (zigvm has no cookie machinery); byte-EQ OTP-30 non-distributed node" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var m = try Machine.init(std.testing.allocator, &atoms);
    defer m.deinit();
    const r = try get_cookie_0(&m, &.{});
    try std.testing.expect(atomIs(&m, r, "nocookie"));
}

test "LAW gap-atom-and-heap-limits atom observability: system_info(atom_limit) == 1048576 (byte-EQ); system_info(atom_count) is the TRUTHFUL live count (rises when a fresh atom is interned) < atom_limit" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const si = struct {
        fn f(mm: *Machine, name: []const u8) BifError!Term {
            return system_info_1(mm, &.{FinalTerms.atom(&mm.ctx, mm.ctx.atoms.intern(name) catch unreachable)});
        }
    }.f;

    // atom_limit is the erts default max (byte-EQ vs OTP-30's 1_048_576).
    try std.testing.expectEqual(@as(i64, 1_048_576), FinalTerms.smallValOf(try si(&m, "atom_limit")));

    // atom_count is the REAL live count: non-neg, below the limit, and it RISES by
    // exactly 1 when a brand-new atom is interned (proves it reads the table, not
    // a fabricated constant — FM-OBS-1).
    const c0 = FinalTerms.smallValOf(try si(&m, "atom_count"));
    try std.testing.expect(c0 >= 0 and c0 < 1_048_576);
    _ = try m.ctx.atoms.intern("a_brand_new_never_seen_atom_xyzzy");
    const c1 = FinalTerms.smallValOf(try si(&m, "atom_count"));
    try std.testing.expectEqual(c0 + 1, c1);
    // interning the SAME atom again does NOT grow the count (idempotent table).
    _ = try m.ctx.atoms.intern("a_brand_new_never_seen_atom_xyzzy");
    try std.testing.expectEqual(c1, FinalTerms.smallValOf(try si(&m, "atom_count")));
}

test "LAW E6.5 flag/scheduler_wall_time/monitor/profile set-get round-trip" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const bt = FinalTerms.atom(&m.ctx, try atoms.intern("backtrace_depth"));
    const undef = FinalTerms.atom(&m.ctx, try atoms.intern("undefined"));

    // system_flag(backtrace_depth): New == Set, and setting Old back restores.
    const old = try system_flag_2(&m, &.{ bt, FinalTerms.int(&m.ctx, 12) });
    try std.testing.expectEqual(@as(i64, 8), FinalTerms.smallValOf(old)); // default 8
    const back = try system_flag_2(&m, &.{ bt, old });
    try std.testing.expectEqual(@as(i64, 12), FinalTerms.smallValOf(back));
    try std.testing.expectEqual(@as(i64, 8), m.backtrace_depth);

    // scheduler_wall_time: round-trips the OLD boolean.
    const swt0 = try scheduler_wall_time_1(&m, &.{boolTerm(&m, true)});
    try std.testing.expect(FinalTerms.atomIdxOf(swt0) == m.bool_false); // default false
    const swt1 = try scheduler_wall_time_1(&m, &.{boolTerm(&m, false)});
    try std.testing.expect(FinalTerms.atomIdxOf(swt1) == m.bool_true);

    // system_monitor: get undefined; set returns prev undefined; get is {Pid,Opts};
    // clear with undefined returns the prior setting; get is undefined again.
    try std.testing.expect(atomIs(&m, try system_monitor_1(&m, &.{FinalTerms.atom(&m.ctx, try atoms.intern("legacy"))}), "undefined"));
    const pidph = FinalTerms.atom(&m.ctx, try atoms.intern("p")); // placeholder monitor pid
    const opts = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 100), FinalTerms.nil(&m.ctx));
    const smprev = try system_monitor_3(&m, &.{ undef, pidph, opts });
    try std.testing.expect(atomIs(&m, smprev, "undefined"));
    const cur = try system_monitor_1(&m, &.{undef});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, cur) == .tuple and FinalTerms.tupleArity(&m.ctx, cur) == 2);
    try std.testing.expect(atomIs(&m, FinalTerms.tupleElem(&m.ctx, cur, 0), "p"));
    const cleared = try system_monitor_3(&m, &.{ undef, undef, FinalTerms.nil(&m.ctx) });
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, cleared) == .tuple); // returns the prior {p,opts}
    try std.testing.expect(atomIs(&m, try system_monitor_1(&m, &.{undef}), "undefined"));

    // system_profile: symmetric round-trip (undefined profiler clears).
    try std.testing.expect(atomIs(&m, try system_profile_0(&m, &.{}), "undefined"));
    const spprev = try system_profile_2(&m, &.{ undef, FinalTerms.nil(&m.ctx) });
    try std.testing.expect(atomIs(&m, spprev, "undefined"));
    try std.testing.expect(atomIs(&m, try system_profile_0(&m, &.{}), "undefined"));
}


// E8.T6: check_process_code/1
pub fn check_process_code_1(m: *Machine, args: []const Term) BifError!Term {
    const pid = args[0];
    if (FinalTerms.kindOf(&m.ctx, pid) != .pid) return error.Badarg;
    return m.badarg;
}
