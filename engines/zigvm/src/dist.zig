//! beam-zig M14 / S27: **distribution** — gate G6 (cf. erts dist.c,
//! erl_node_tables.c).
//!
//! The stack composes three finished algebras: control frames carry M9 ETF
//! payloads, framed by M12's packet-4 codec, over an in-process ordered
//! byte carrier. E8.2aa adds the first real loopback-TCP byte carrier law,
//! scoped deliberately to packet-4 movement of the existing frame stream; the
//! session algebra remains carrier-independent.
//!
//! Session algebra (handshake):
//!   HELLO(name, creation) → CHALLENGE(n) → ACK(n) ⇒ connected
//! Laws:
//!   PRE-HANDSHAKE QUEUING  sends attempted before the handshake completes
//!                          are delivered AFTER it, still in send order
//!   RECONNECT IDEMPOTENCE  a duplicate HELLO on an established connection
//!                          neither duplicates nor reorders pending traffic
//!   STALE CREATION         a SEND addressed with a wrong creation stamp is
//!                          dropped, never delivered to a reincarnated pid
//!
//! Control frames: SEND, REG_SEND (via the M10 registry), LINK, EXIT.
//! E8.2 adds the two-node carrier DOORSTEP observations future BIFs need:
//! each side records the peer node identity during handshake, exposes the
//! connected-node set as a representation-independent term, and supports a
//! local `monitor_node` precursor that delivers `{nodedown, Node}` exactly
//! once when the carrier disconnects.
//!
//! THE FLAGSHIP LAW — LOCATION TRANSPARENCY: a send to a process on node B
//! from node A produces the same delivered-message DENOTATION SEQUENCE at
//! the target as the same sends performed locally, under the per-pair
//! signal-order law preserved across the carrier. Verified by twin
//! scenario (one VM vs two nodes) over seeded term streams, with the
//! carrier chopped at adversarial chunk boundaries (the M12 trick).
//!
//! Cross-node LINK/EXIT: exit reasons cross as ETF; trap_exit semantics
//! are the M7 laws, unchanged — that they hold ACROSS the wire is the law.
//!
//! Scope (documented): remote pids are node-qualified addresses in the
//! control plane (u32 id + creation). E5.7 LANDED the external-pid TERM kind
//! — pids/ports/refs now carry a {node, creation} identity (`term_algebra`),
//! so a foreign identity travelling INSIDE a SEND payload survives the ETF
//! codec across the carrier with its node observable via `node/1` (the
//! FRAME-CARRIED EXTERNAL PID law below; the differential half is the ETF
//! foreign round-trip, `etf.zig`'s E5.7 law + the `fpid` corpus case).
//! STILL deferred (need a REAL second node / live carrier beyond the in-memory
//! pair): pid/ref/port term identities that reflect an installed local node,
//! socket/control-data handle ownership beyond the in-VM pending-entry
//! controller, full socket DFLAG negotiation/rejection, and real remote process
//! effects — owned by the remaining network-I/O/control-surface slice, named
//! honestly, never false-EQ. E8.2y narrows the remote-exit residual by draining
//! `proc.Vm`'s owned remote-exit wire intents into this in-memory EXIT carrier;
//! E8.2z exchanges peer DFLAGS in HELLO and refreshes only an already-live
//! matching `DistEntry`; E8.2aa proves that the same packet-4 frame bytes can be
//! owned by a real loopback TCP stream; E8.2ab proves those TCP-carried HELLO and
//! EXIT bytes can drive the existing guarded DFLAG refresh and trapped EXIT
//! delivery observations; E8.2ac/E8.2ad admit only peers carrying the pinned
//! mandatory DFLAG bitset and store the OTP-style effective DFLAG intersection
//! at the carrier boundary, without yet claiming OTP socket setup, control-data
//! process ownership, or full remote process parity.
//! E8.2b-k discharged only no-carrier observer/action/rejection subsets
//! (`nodes/1,2`, `get_creation/0`, `dflag_unicode_io/1`, `monitor_node/2,3`,
//! `get_dflags/0`, debug/control-data/spawn/exit/pending/channel-start direct
//! surfaces). E8.2l-s add the `proc.Vm` pending-to-live DistEntry semantic
//! precursor plus VM-owned public connected-node, `nodes/2` info-map, and
//! stored-DFLAG unicode, node-monitor, and controller-owned channel promotion
//! bridges, and the net_kernel-owned local identity used by `node/0`,
//! `get_creation/0`, `nodes/1,2`, and channel promotion. The E8.2 doorway below
//! proves the live two-node carrier algebra that later BIF/control rows must
//! reuse.
//!
//! E18 Task 3 (DIVERGENCE 212 — distributed signals over the LIVE carrier):
//! the `FTAG_*` frames above are the algebraic ORACLE. The real OTP wire uses
//! DOP (distribution-operation) control messages; `DOP_*`/`DIST_PASS_THROUGH`
//! are the FINAL encoding on the live packet-4 socket. Advertising `signalsFlags`
//! (required set minus DIST_HDR_ATOM_CACHE and FRAGMENTS) makes the pinned peer
//! emit every control message in simple PASS_THROUGH form: byte 112 + a versioned
//! control tuple + an optional versioned message. `decodePassThrough` splits that
//! at the exact ETF term boundary (`etf.decodeConsumed`), and `encodeRegSend`
//! produces it. `LiveCarrier.recvControl`/`sendRegSend` drive it over the real
//! fd. Proven end-to-end EQ against the pinned OTP-30 peer BOTH directions for a
//! remote registered-send (REG_SEND): OUTBOUND (a real peer process receives our
//! `term_to_binary` byte-identically) and INBOUND (`{name,us} ! T` decodes off
//! the socket into a `proc.Vm` mailbox), harness `dist-signal.{out,in}bound-
//! reg-send` rows. Laws: REG-SEND-ROUND-TRIP, INBOUND-CONTROL-DECODE ROUND-TRIP
//! (`etf.zig`), SIGNALS-FLAGS.
//!
//! E18 Task 3b (DIVERGENCE 260 residual — remote MONITOR + 'DOWN' + noconnection):
//! `encodeMonitorP` sends a real DOP `MONITOR_P {19, FromPid, Target, Ref}` with
//! a fresh reference minted on OUR node; the peer echoes that ref in the exit it
//! fires. Because our signals carrier negotiates DFLAG_EXIT_PAYLOAD, the peer
//! sends `PAYLOAD_MONITOR_P_EXIT` (28) — `{28, From, To, Ref}` + the Reason as a
//! TRAILING payload — not the classic `MONITOR_P_EXIT` (21); `matchMonitorExit`
//! accepts BOTH and returns the wire Reason only for our EXACT ref (`eqlExact`).
//! Proven live EQ against the pinned peer: `dist-signal.monitor-down` (MONITOR_P
//! a nonexistent name → peer replies `noproc` off the wire → 'DOWN' in a VM
//! mailbox) and `dist-signal.monitor-noconnection` (MONITOR_P a LIVE proc, peer
//! node dies → carrier teardown flushes a synthesized `noconnection` 'DOWN',
//! never a silent loss). Laws: MONITOR-P-ROUND-TRIP, MONITOR-FIRES-EXACTLY-ONCE
//! (right-ref-identity), TEARDOWN-FLUSHES-WITH-NOCONNECTION.
//!
//! E18 Task 3c (DIVERGENCE 261 residual — remote LINK/EXIT/EXIT2/DEMONITOR, the
//! PID-carrying signals): LINK/EXIT/EXIT2 carry PIDs, not names, so the live
//! driver first RECEIVES the peer's own pid over a REG_SEND (e18-t3 inbound),
//! then LINK/EXIT2s THAT exact pid. `encodeLink` sends DOP `LINK {1,From,To}`;
//! when the linked peer proc dies the peer sends `PAYLOAD_EXIT` (24) — or classic
//! `EXIT` (3) — addressed to our exact pid, and `matchLinkExit` yields {From,
//! Reason} ONLY for our exact target (`eqlExact`), across all four EXIT/EXIT2
//! encodings; `exitMessage` builds the delivered `{'EXIT',Pid,Reason}`.
//! `encodePayloadExit2` sends `PAYLOAD_EXIT2 {26,From,To}`+Reason to kill a peer
//! pid outbound. `sendDemonitorP` retracts a monitor (op 20) with the exact ref
//! so no 'DOWN' fires. Proven live EQ against the pinned peer: `dist-signal.link-
//! exit` (peer proc exits `linkboom` → zigvm observes `{'EXIT',Pid,linkboom}`),
//! `dist-signal.exit2` (zigvm kills a peer pid with `killme` → the peer's
//! trapping link observes the death reason), `dist-signal.demonitor` (MONITOR_P
//! then DEMONITOR_P a live peer proc → the retract fires NO 'DOWN' when it dies).
//! Laws: LINK-EXIT-ROUND-TRIP (link-symmetry), EXIT-PROPAGATES-REASON (right-
//! target-identity, both EXIT/PAYLOAD_EXIT), EXIT2-PAYLOAD-ROUND-TRIP, DEMONITOR-
//! RETRACT-ROUND-TRIP.
//!
//! E20 Task 1 (DIVERGENCE 262 residual — remote unlink / inbound-exit2 / exit1,
//! DRIVEN live): the three edges e18-t3c split off, each a genuine live EQ vs the
//! pinned peer, never a false EQ.
//!   - `unlink`: the OTP-30 TWO-FRAME retract (NOT the deprecated classic UNLINK
//!     4). zigvm LINKs a peer pid (received over REG_SEND) then sends DOP
//!     `UNLINK_ID {35, Id, OurPid, PeerPid}` (`encodeUnlinkId`); the peer's ERTS
//!     replies `UNLINK_ID_ACK {36, Id, PeerPid, OurPid}` echoing our EXACT id.
//!     `matchUnlinkIdAck` closes the loop keyed on BOTH the id and our exact
//!     originating pid (`eqlExact`). Row `dist-signal.unlink`.
//!   - inbound `exit2`: the MIRROR of the outbound `dist-exit2`. zigvm mints a
//!     local victim's foreign pid and REG_SENDs it to the peer, which `exit/2`s
//!     it; zigvm decodes the inbound `PAYLOAD_EXIT2` (`matchLinkExit`, right-
//!     target) and drives a REAL `exit_sig` that terminates the live local victim
//!     carrying exactly the wire reason. Row `dist-signal.inbound-exit2`.
//!   - remote `exit/1`: the NORMAL-reason self-exit (distinct from e18-t3c's
//!     abnormal `linkboom`). A linked peer proc `exit(normal)`s; over the link
//!     erts STILL transmits the normal-reason exit (a local link would drop it),
//!     and zigvm — TRAPPING — delivers `{'EXIT', PeerPid, normal}`. Row
//!     `dist-signal.exit1`.
//! Laws: UNLINK-TWO-FRAME-ROUND-TRIP (right-id + right-target), INBOUND-EXIT2-
//! DELIVERY (a real kill of the local victim), EXIT1-NORMAL-PROPAGATION (trapping
//! delivers / non-trapping drops). NAMED residual (DIVERGENCE 400): the deprecated
//! classic UNLINK (4) retract path and the emulator `distribution_SUITE` CT
//! closure stay UNTESTED — split honestly, never false-EQ.
//!
//! E18 Task 4 (DIVERGENCE 320/321/322 — GLOBAL COORDINATION: net_kernel, global,
//! pg): when zigvm completes the live signals handshake, the peer's coordination
//! services react to the nodeup and initiate their convergence protocols OVER THE
//! LIVE CARRIER, addressed to a like-named process on zigvm. Three genuine live
//! EQ sub-boundaries against the pinned peer (harness `dist-coord.*` rows):
//!   - `net_kernel`: a peer with a short `net_ticktime` runs `monitor_nodes`;
//!     zigvm connects (nodeup), holds the carrier PAST the tick window answering
//!     ticks (tick keepalive — the peer confirms zigvm is still connected), then
//!     tears down → a single clean nodedown. `foldNodeLifecycle` is the pure core
//!     (NODE-LIFECYCLE-ORDER law: up-then-down exactly once).
//!   - `global`: zigvm registers `global_name_server`; the peer's global casts
//!     `{'$gen_cast',{init_connect,{Vsn,Tag},Node,Locker}}` — the first step of
//!     the name-table sync enforcing single-owner consistency. `globalInitConnect-
//!     Node` extracts the initiating peer node (GLOBAL-INIT-CONNECT-EXTRACT law).
//!   - `pg`: zigvm registers the default `pg` scope; the peer's pg scope
//!     broadcasts `{discover,ScopePid,Ref}`. `pgDiscoverPid` extracts the peer's
//!     scope pid (PG-DISCOVER-EXTRACT law).
//! RESIDUAL (named, never false-EQ): completing global's lock/exchange/resolved
//! so a NAME is visible from BOTH nodes (DIVERGENCE 320) and pg's join/sync so a
//! GROUP membership is visible from both (DIVERGENCE 321) each need zigvm to run
//! the locker / pg-scope state machines — strictly larger, deferred to E19. The
//! full multi-node global/pg topologies stay UNTESTED (DIVERGENCE 322, → E19).
//!
//! E20 Task 2 (DIVERGENCE 320/321 — the coordination STATE MACHINES):
//!   - `pg` (321) COMPLETES live. `pgJoin`/`pgMembersOf` model the scope's global
//!     view as a JOIN-SEMILATTICE (set union of every node's group→member data —
//!     the CRDT-like convergence pg guarantees; PG-MEMBERSHIP-CONVERGENCE law:
//!     idempotent/commutative, a member on one node visible from both). Driven
//!     LIVE by `dist-pg-join`: on the peer's `discover` we cast our `local_data`
//!     (`pgLocalDataCast` + `encodeSend`/`sendToPid`, DOP SEND op 2) back to the
//!     peer scope pid, so the pinned peer's OWN `pg:get_members` converges to
//!     include our member (`dist-coord.pg-membership` **EQ**). DIVERGENCE 321
//!     discharged (live EQ).
//!   - `global` (320): `resolveGlobalNames`/`globalWhereis` land the PAYOFF of the
//!     locker exchange/resolved phase as a pure state machine — merging two name
//!     tables leaves AT MOST ONE owner per name (GLOBAL-REGISTRATION-CONSISTENCY
//!     law: unique names preserved, a clash resolved to a total-order winner,
//!     order-independent). The LIVE completion (a name visible from both) still
//!     needs the full 2-phase `the_locker` whose `set_lock` is a `gen_server:call`
//!     OVER DIST — a strictly larger boundary; nothing partial is sent live (peer
//!     -corruption risk), so the live global observation stays at init_connect.
//!     DIVERGENCE 320 residual sharpened; reserved range 410–419.
//!
//! E20 Task 3 (DIVERGENCE 322 — MULTI-NODE (≥3) topologies): zigvm holds ≥2 live
//! pinned-OTP-30 carriers at once (`holdCarriersTicks`), forming a 3-node triad
//! {zigvm, peer A, peer B}. Three live sub-boundaries, each with a pure bounding
//! law (E20.3):
//!   - TRANSITIVE-NODES-VISIBILITY: with all three edges present, each node's
//!     nodes/0 lists the OTHER two (the complete graph K3). zigvm's local vertex is
//!     the node-table SET projection (`distLiveNodesTerm` over two registered live
//!     peers — proc.zig companion law); the peers' views are the live observation
//!     (`dist-mesh` → `dist-coord.transitive-nodes` EQ). Auto-GOSSIP transitivity
//!     (a peer reaching zigvm with no direct edge) needs a zigvm ACCEPTOR + epmd
//!     listener — a named residual (DIVERGENCE 440), never false-EQ.
//!   - 3-NODE-PG-CONVERGENCE: `pgJoin` is ASSOCIATIVE, so a 3-way membership union
//!     is order-independent and a member on ANY one node is visible from ALL THREE.
//!     Driven LIVE by `dist-pg-mesh` casting our `local_data` to BOTH peers
//!     (`dist-coord.pg-multinode` EQ).
//!   - PARTITION-HEAL-RECONVERGENCE: a join-semilattice recovers its LUB after a
//!     node's retract+rejoin — `pgJoin(pgRemoveNode(full,C), C_data) == full`.
//!     Driven LIVE by `dist-pg-heal`: a real carrier tear makes a pinned peer's pg
//!     RETRACT our member on nodedown, and a reconnect+recast makes it RECONVERGE
//!     (`dist-coord.pg-partition-heal` EQ), while a third node witnesses continuity.
//!   RESIDUAL (named): 3-node GLOBAL NAME resolution stays DIVERGENCE 320/322 — it
//!   needs the full 2-phase `the_locker` (not sent live; peer-corruption risk).
//!
//! E21 Task 5 (DIVERGENCE 440 discharge — INBOUND distribution ACCEPTOR): every
//! E18/E20 dist slice had zigvm DIAL OUT (`liveConnectOpen`). This makes zigvm a
//! SYMMETRIC node a real peer can DIAL IN to. Two pieces compose with the finished
//! v6 codec + `genDigest`: (1) an epmd ALIVE2 registration (`epmd_bridge.zig`
//! codec + `openAcceptListener` socket glue) advertising zigvm's dist port so a
//! peer can look it up, plus a bound listening socket; (2) the distribution
//! ACCEPTOR side of the v6 handshake (`acceptHandshake`/`liveAcceptOpen`, mirror of
//! `dist_util.erl handshake_other_started`): recv `send_name` → reply
//! `send_status('sok')` → send our `send_challenge` (`V6.encodeChallenge`) → recv
//! `challenge_reply` → verify the peer's digest == `genDigest(cookie, OUR chal)` →
//! send `challenge_ack` ⇒ connected. `AcceptAuth` is the reject-atomic acceptor
//! auth state machine (mirror of `HsAuth`). Proven LIVE against the pinned peer
//! (`dist-coord.inbound-accept`): a real OTP-30 peer `net_kernel:connect_node`s
//! zigvm and its OWN `nodes/0` lists zigvm — a connection zigvm ACCEPTED. Laws:
//! ACCEPTOR-HANDSHAKE-ROUND-TRIP, ACCEPTOR-REJECT-ATOMICITY (+ EPMD-ALIVE2-REGISTER
//! in `epmd_bridge.zig`). Every accept/read is SO_RCVTIMEO-bounded — a silent
//! dialer returns `error.AcceptTimeout`, never a hang. RESIDUAL (DIVERGENCE 480,
//! named, never false-EQ): `net_adm:ping` returning `pong` additionally requires
//! zigvm to ANSWER the `net_kernel` `is_auth` `$gen_call` — a running net_kernel
//! gen_server, the E21 Task 1/2 OTP-behaviour boundary; connect_node (the
//! task-sanctioned acceptance) is the genuine acceptor EQ. FV-follow-up:
//! `Dist_Carrier.v` §1 proves reject-atomicity for the INITIATOR's `verifyAck`;
//! extending it to the acceptor's symmetric `AcceptAuth.verifyReply` is a named
//! proof follow-up (the Zig ACCEPTOR-REJECT-ATOMICITY law already pins it).
//! E21 Task 4 (DIVERGENCE 320 → LIVE — global REGISTER over dist): the E20-t2
//! resolve-core is now driven as a LIVE transaction for the UNCONTENDED single
//! name. `global:register_name(Name,Pid)` initiated on zigvm acquires the global
//! lock ACROSS BOTH nodes and inserts the name, so it becomes visible from the
//! PEER. The mechanism is `set_lock` as a `gen_server:call` over dist — the
//! alias/monitor `$gen_call` request-reply (`genCall` builds `{'$gen_call',
//! {From,[alias|Ref]}, Request}`; the peer's `gen:reply` routes `{[alias|Ref],
//! Reply}` back via `ALIAS_SEND` (33); `matchAliasReply` admits the reply ONLY for
//! our exact minted alias ref — `globalCallFlags` clears `DFLAG_ALTACT_SIG` so the
//! deterministic op-33 frame is used). The transaction: `sendGenCall` set_lock →
//! register(Name,Pid,`fun global:random_exit_name/3`) → del_lock, awaiting each
//! peer reply (`true`/`yes`/`true`), then hold the carrier. Driven LIVE by
//! `global-register`: the pinned peer's OWN `global:whereis_name(Name)` resolves a
//! pid on zigvm's node AND a competing `global:register_name` returns `no`
//! (`dist-coord.global-register` **EQ**, W-11-guarded). Bounded by three pure laws
//! (E21.4): locker-2phase-acquire (`matchAliasReply` admits a reply ONLY for our
//! exact alias — no fabricated lock-grant), global-register-peer-visible (the
//! register request encodes the exact Name/Pid the peer inserts + the resolver
//! export-fun; set_lock/del_lock name ONE resource), single-owner-under-contention
//! (`resolveGlobalNames`/`globalWhereis` is single-valued — a competing claim
//! never creates a second binding). RESIDUAL (named, DIVERGENCE 470, reserved
//! 470–479): the FULL 2-phase `the_locker` — the nodeup name-table MERGE (two
//! already-populated partitions joining), boss-node-ordered multi-node lock
//! acquisition (`lock_nodes_safely`/`the_boss`), and concurrent-locker deadlock
//! avoidance — stays UNTESTED; nothing partial is ever sent (no locker corruption).

const std = @import("std");
const ta = @import("term_algebra.zig");
const ia = @import("instr_algebra.zig");
const proc = @import("proc.zig");
const procsys = @import("bifs/procsys.zig");
const etf = @import("etf.zig");
const port = @import("port_algebra.zig");
const registry = @import("registry.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

// ---------------------------------------------------------------------------
// Frames
// ---------------------------------------------------------------------------

const FTAG_HELLO: u8 = 1;
const FTAG_CHALLENGE: u8 = 2;
const FTAG_ACK: u8 = 3;
const FTAG_SEND: u8 = 4;
const FTAG_REG_SEND: u8 = 5;
const FTAG_LINK: u8 = 6;
const FTAG_EXIT: u8 = 7;

const DIST_SYSTEM_PID: proc.Pid = 0xFFFF;
const otp30_dflags_required: i64 = 468283523004;
const otp30_dflags_mandatory: i64 = 17230663572;
const otp30_dflags_mandatory_25: i64 = 17239956;
const otp30_dflag_mandatory_25_digest: i64 = 0x04000000;
const otp30_dflag_unlink_id: i64 = 0x02000000;
const otp30_dflag_unicode_io: i64 = 0x1000;
const otp30_dflag_strict_order: i64 = 0x2000;

// ---------------------------------------------------------------------------
// E18 Task 3: real OTP DOP (distribution operation) control-message opcodes
// (erts/emulator/beam/dist.h). These travel on the LIVE packet-4 carrier as the
// first element of a `PASS_THROUGH`-framed control tuple — DISTINCT from the
// in-memory `FTAG_*` model frames above (the model is the algebraic oracle; the
// DOP layer is the live-carrier final encoding that must agree with the pinned
// OTP-30 peer end-to-end). We decode inbound control messages off the socket
// into `proc.Vm` signals and drive outbound ones.
pub const DOP_LINK: i64 = 1;
pub const DOP_SEND: i64 = 2;
pub const DOP_EXIT: i64 = 3;
pub const DOP_UNLINK: i64 = 4;
pub const DOP_REG_SEND: i64 = 6;
pub const DOP_GROUP_LEADER: i64 = 7;
pub const DOP_EXIT2: i64 = 8;
pub const DOP_MONITOR_P: i64 = 19;
pub const DOP_DEMONITOR_P: i64 = 20;
pub const DOP_MONITOR_P_EXIT: i64 = 21;
pub const DOP_SEND_SENDER: i64 = 22;
// EXIT-PAYLOAD variants (DFLAG_EXIT_PAYLOAD, 0x400000): the Reason travels in a
// TRAILING versioned payload term rather than in the control tuple. A peer that
// negotiated EXIT_PAYLOAD (our signals carrier does) emits THESE for exits and
// monitor-downs, so a live monitor→'DOWN' arrives as op 28, not op 21.
pub const DOP_PAYLOAD_EXIT: i64 = 24;
pub const DOP_PAYLOAD_EXIT_TT: i64 = 25;
pub const DOP_PAYLOAD_EXIT2: i64 = 26;
pub const DOP_PAYLOAD_EXIT2_TT: i64 = 27;
pub const DOP_PAYLOAD_MONITOR_P_EXIT: i64 = 28;
// E20 Task 1 (DIVERGENCE 262): the OTP-30 id-tagged unlink retract, negotiated
// under DFLAG_UNLINK_ID (0x02000000, in the required set) — the two-frame
// protocol that closes the unlink/exit race, superseding the deprecated classic
// UNLINK (4). `unlink/1` across a node sends UNLINK_ID {35, Id, From, To}; the
// receiving node's ERTS replies UNLINK_ID_ACK {36, Id, From, To} (From/To are the
// ack sender/receiver — the local unlinked proc / the remote originator).
pub const DOP_UNLINK_ID: i64 = 35;
pub const DOP_UNLINK_ID_ACK: i64 = 36;
pub const DIST_PASS_THROUGH: u8 = 112; // 'p' — non-atom-cache control framing

const otp30_dflag_dist_hdr_atom_cache: i64 = 0x2000;
const otp30_dflag_fragments: i64 = 0x800000;

/// The DFLAG bitset to advertise for a distributed-SIGNALS carrier: the full
/// required+published set with DIST_HDR_ATOM_CACHE and FRAGMENTS cleared. The
/// mandatory OTP-30 flags are all preserved (the peer still admits us), but with
/// atom-cache and fragmentation off the pinned peer sends every control message
/// in the simple `PASS_THROUGH` format (byte 112 + versioned control tuple +
/// optional versioned message) — the exact shape `decodePassThrough` handles.
pub fn signalsFlags() u64 {
    const base = otp30_dflags_required | otp30_dflag_published;
    return @bitCast(base & ~(otp30_dflag_dist_hdr_atom_cache | otp30_dflag_fragments));
}

fn expandMandatory25Digest(dflags: i64) i64 {
    if ((dflags & otp30_dflag_mandatory_25_digest) != 0)
        return dflags | otp30_dflags_mandatory_25;
    return dflags;
}

fn mandatoryDFlagsAdmitted(dflags: i64) bool {
    const expanded = expandMandatory25Digest(dflags);
    return (expanded & otp30_dflags_mandatory) == otp30_dflags_mandatory;
}

fn negotiatedDFlags(local_dflags: i64, peer_dflags: i64) i64 {
    return expandMandatory25Digest(local_dflags) & expandMandatory25Digest(peer_dflags);
}

/// E8.2aa: a real TCP byte carrier for the existing packet-4 distribution
/// stream. This is Stratum-C ownership only: it moves bytes over an OS stream
/// and reuses the S25 packet framing algebra. It does not perform OTP's socket
/// setup, distribution controller ownership, mandatory-flag negotiation, or
/// remote process effects.
pub const TcpStreamCarrier = struct {
    fd: i32,

    pub fn close(self: *const TcpStreamCarrier) void {
        _ = std.os.linux.close(self.fd);
    }

    pub fn writeBytes(self: *const TcpStreamCarrier, bytes: []const u8) !void {
        var pos: usize = 0;
        while (pos < bytes.len) {
            const n = try tcpWrite(self.fd, bytes[pos..]);
            if (n == 0) return error.TcpClosed;
            pos += n;
        }
    }

    pub fn readExactAlloc(self: *const TcpStreamCarrier, gpa: std.mem.Allocator, len: usize) ![]u8 {
        const out = try gpa.alloc(u8, len);
        errdefer gpa.free(out);
        var pos: usize = 0;
        while (pos < len) {
            const n = try tcpRead(self.fd, out[pos..]);
            if (n == 0) return error.TcpClosed;
            pos += n;
        }
        return out;
    }

    pub fn writePacket4Frame(self: *const TcpStreamCarrier, gpa: std.mem.Allocator, payload: []const u8) !void {
        var framed: std.ArrayList(u8) = .empty;
        defer framed.deinit(gpa);
        try port.frame(gpa, .p4, payload, &framed);
        try self.writeBytes(framed.items);
    }

    pub fn readPacket4FrameAlloc(self: *const TcpStreamCarrier, gpa: std.mem.Allocator, max_len: usize) ![]u8 {
        const header = try self.readExactAlloc(gpa, 4);
        defer gpa.free(header);
        const len: usize = getU32(header[0..4]);
        if (len > max_len) return error.TooLong;
        return self.readExactAlloc(gpa, len);
    }

    /// Fill `buf` exactly (blocking; TcpTimeout if SO_RCVTIMEO fires, TcpClosed
    /// on EOF). Stack-buffer variant of readExactAlloc for small headers.
    pub fn readExact(self: *const TcpStreamCarrier, buf: []u8) !void {
        var pos: usize = 0;
        while (pos < buf.len) {
            const n = try tcpRead(self.fd, buf[pos..]);
            if (n == 0) return error.TcpClosed;
            pos += n;
        }
    }

    /// E18.2: OTP distribution handshake framing is 2-byte length-prefixed
    /// (packet-2) until the connection is up, then switches to packet-4. These
    /// two helpers move one handshake frame over the real stream.
    pub fn writePacket2Frame(self: *const TcpStreamCarrier, gpa: std.mem.Allocator, payload: []const u8) !void {
        var framed: std.ArrayList(u8) = .empty;
        defer framed.deinit(gpa);
        try port.frame(gpa, .p2, payload, &framed);
        try self.writeBytes(framed.items);
    }

    pub fn readPacket2FrameAlloc(self: *const TcpStreamCarrier, gpa: std.mem.Allocator, max_len: usize) ![]u8 {
        var header: [2]u8 = undefined;
        try self.readExact(&header);
        const len: usize = (@as(usize, header[0]) << 8) | header[1];
        if (len > max_len) return error.TooLong;
        return self.readExactAlloc(gpa, len);
    }
};

fn tcpSocket() !i32 {
    while (true) {
        const rc = std.os.linux.socket(std.os.linux.AF.INET, std.os.linux.SOCK.STREAM | std.os.linux.SOCK.CLOEXEC, 0);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            else => return error.TcpSocket,
        }
    }
}

fn tcpBind(fd: i32, addr: *const std.os.linux.sockaddr.in) !void {
    const rc = std.os.linux.bind(fd, @ptrCast(addr), @sizeOf(std.os.linux.sockaddr.in));
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        else => return error.TcpBind,
    }
}

fn tcpListen(fd: i32) !void {
    const rc = std.os.linux.listen(fd, 1);
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        else => return error.TcpListen,
    }
}

fn tcpSockName(fd: i32, addr: *std.os.linux.sockaddr.in) !void {
    var len: std.os.linux.socklen_t = @sizeOf(std.os.linux.sockaddr.in);
    const rc = std.os.linux.getsockname(fd, @ptrCast(addr), &len);
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        else => return error.TcpName,
    }
}

fn tcpConnect(fd: i32, addr: *const std.os.linux.sockaddr.in) !void {
    while (true) {
        const rc = std.os.linux.connect(fd, addr, @sizeOf(std.os.linux.sockaddr.in));
        switch (std.posix.errno(rc)) {
            .SUCCESS => return,
            .INTR => continue,
            else => return error.TcpConnect,
        }
    }
}

fn tcpAccept(fd: i32) !i32 {
    while (true) {
        const rc = std.os.linux.accept4(fd, null, null, std.os.linux.SOCK.CLOEXEC);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            else => return error.TcpAccept,
        }
    }
}

fn tcpRead(fd: i32, out: []u8) !usize {
    while (true) {
        const rc = std.os.linux.read(fd, out.ptr, out.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return rc,
            .INTR => continue,
            // With SO_RCVTIMEO set (E18.2 handshake carrier) a read that
            // exceeds the deadline returns EAGAIN/EWOULDBLOCK. Surfacing it as
            // a distinct TcpTimeout is what makes the TIMEOUT-BOUNDED READ law
            // observable: a silent peer never hangs the initiator.
            .AGAIN => return error.TcpTimeout,
            else => return error.TcpRead,
        }
    }
}

/// E18.2: bound a socket's blocking reads with SO_RCVTIMEO (milliseconds). A
/// zero deadline (ms == 0) restores an infinite blocking read.
/// E18 Task 3: public bound-the-read wrapper so a live signals driver can tune
/// its per-poll timeout (a hang is a failed law).
pub fn setRecvTimeoutPub(fd: i32, ms: u32) !void {
    return setRecvTimeout(fd, ms);
}

fn setRecvTimeout(fd: i32, ms: u32) !void {
    const tv = std.os.linux.timeval{
        .sec = @intCast(ms / 1000),
        .usec = @intCast((ms % 1000) * 1000),
    };
    const rc = std.os.linux.setsockopt(
        fd,
        std.os.linux.SOL.SOCKET,
        std.os.linux.SO.RCVTIMEO,
        @ptrCast(&tv),
        @sizeOf(std.os.linux.timeval),
    );
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        else => return error.TcpSockOpt,
    }
}

/// E18.2: connect a fresh TCP socket to 127.0.0.1:<port_num> (the peer's
/// epmd-advertised distribution port, or epmd itself). Stratum-C ownership.
fn tcpConnectLoopbackPort(port_num: u16) !TcpStreamCarrier {
    const fd = try tcpSocket();
    errdefer _ = std.os.linux.close(fd);
    const addr = loopbackAddr(port_num);
    try tcpConnect(fd, &addr);
    return .{ .fd = fd };
}

fn tcpWrite(fd: i32, bytes: []const u8) !usize {
    while (true) {
        const rc = std.os.linux.write(fd, bytes.ptr, bytes.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return rc,
            .INTR => continue,
            else => return error.TcpWrite,
        }
    }
}

fn loopbackAddr(port_num: u16) std.os.linux.sockaddr.in {
    return .{
        .port = std.mem.nativeToBig(u16, port_num),
        .addr = std.mem.nativeToBig(u32, 0x7F00_0001),
    };
}

fn openLoopbackTcpPair() ![2]TcpStreamCarrier {
    const listener = try tcpSocket();
    errdefer _ = std.os.linux.close(listener);
    var bind_addr = loopbackAddr(0);
    try tcpBind(listener, &bind_addr);
    try tcpListen(listener);
    var actual_addr: std.os.linux.sockaddr.in = undefined;
    try tcpSockName(listener, &actual_addr);

    const client = try tcpSocket();
    errdefer _ = std.os.linux.close(client);
    try tcpConnect(client, &actual_addr);

    const accepted = try tcpAccept(listener);
    errdefer _ = std.os.linux.close(accepted);
    _ = std.os.linux.close(listener);
    return .{ .{ .fd = client }, .{ .fd = accepted } };
}

fn putU32(gpa: std.mem.Allocator, out: *std.ArrayList(u8), v: u32) !void {
    try out.append(gpa, @truncate(v >> 24));
    try out.append(gpa, @truncate(v >> 16));
    try out.append(gpa, @truncate(v >> 8));
    try out.append(gpa, @truncate(v));
}
fn getU32(b: []const u8) u32 {
    return (@as(u32, b[0]) << 24) | (@as(u32, b[1]) << 16) | (@as(u32, b[2]) << 8) | b[3];
}

fn putU64(gpa: std.mem.Allocator, out: *std.ArrayList(u8), v: u64) !void {
    try out.append(gpa, @truncate(v >> 56));
    try out.append(gpa, @truncate(v >> 48));
    try out.append(gpa, @truncate(v >> 40));
    try out.append(gpa, @truncate(v >> 32));
    try out.append(gpa, @truncate(v >> 24));
    try out.append(gpa, @truncate(v >> 16));
    try out.append(gpa, @truncate(v >> 8));
    try out.append(gpa, @truncate(v));
}

fn getU64(b: []const u8) u64 {
    return (@as(u64, b[0]) << 56) |
        (@as(u64, b[1]) << 48) |
        (@as(u64, b[2]) << 40) |
        (@as(u64, b[3]) << 32) |
        (@as(u64, b[4]) << 24) |
        (@as(u64, b[5]) << 16) |
        (@as(u64, b[6]) << 8) |
        b[7];
}

fn putI64(gpa: std.mem.Allocator, out: *std.ArrayList(u8), v: i64) !void {
    try putU64(gpa, out, @bitCast(v));
}

fn getI64(b: []const u8) i64 {
    return @bitCast(getU64(b));
}

// ---------------------------------------------------------------------------
// Node
// ---------------------------------------------------------------------------

pub const HsState = enum { idle, hello_sent, challenged, connected };

pub const Node = struct {
    gpa: std.mem.Allocator,
    name: []const u8,
    creation: u32,
    dflags: i64,
    atoms: *AtomTable,
    vm: proc.Vm,
    reg: registry.Registry,

    // single-peer connection (two-node scope)
    hs: HsState = .idle,
    peer_creation: u32 = 0,
    peer_dflags: i64 = 0,
    peer_admitted: bool = false,
    peer_rejected: bool = false,
    peer_name: ?[]u8 = null,
    sent_challenge: u32 = 0, // what WE challenged the peer with
    out: std.ArrayList(u8), //     bytes we have written toward the peer
    deframer: port.Deframer, //    reassembles frames from carrier chunks
    pending: std.ArrayList([]u8), // pre-handshake sends, queued IN ORDER
    node_monitors: std.ArrayList(proc.Pid), // local pids monitoring peer DOWN

    pub fn init(gpa: std.mem.Allocator, atoms: *AtomTable, name: []const u8, creation: u32) !Node {
        return try initWithDFlags(gpa, atoms, name, creation, otp30_dflags_required);
    }

    pub fn initWithDFlags(gpa: std.mem.Allocator, atoms: *AtomTable, name: []const u8, creation: u32, dflags: i64) !Node {
        return .{
            .gpa = gpa,
            .name = name,
            .creation = creation,
            .dflags = dflags,
            .atoms = atoms,
            .vm = try proc.Vm.init(gpa, atoms),
            .reg = registry.Registry.init(gpa),
            .out = .empty,
            .deframer = port.Deframer.init(gpa, .p4),
            .pending = .empty,
            .node_monitors = .empty,
        };
    }
    pub fn deinit(self: *Node) void {
        self.vm.deinit();
        self.reg.deinit();
        if (self.peer_name) |name| self.gpa.free(name);
        self.out.deinit(self.gpa);
        self.deframer.deinit();
        for (self.pending.items) |p| self.gpa.free(p);
        self.pending.deinit(self.gpa);
        self.node_monitors.deinit(self.gpa);
    }

    fn pushFrame(self: *Node, payload: []const u8) !void {
        try port.frame(self.gpa, .p4, payload, &self.out);
    }

    fn setPeerName(self: *Node, name: []const u8) !void {
        if (self.peer_name) |old| {
            if (std.mem.eql(u8, old, name)) return;
            self.gpa.free(old);
        }
        self.peer_name = try self.gpa.dupe(u8, name);
    }

    /// Connected-peer observation for future `nodes/*` BIF wiring.
    pub fn peerNodeName(self: *const Node) ?[]const u8 {
        if (self.hs != .connected) return null;
        return self.peer_name;
    }

    pub fn connectedPeerCount(self: *const Node) usize {
        return if (self.peerNodeName() == null) 0 else 1;
    }

    /// E8.2z/E8.2ad: effective DFLAGS observed after connected HELLO exchange.
    pub fn peerDFlags(self: *const Node) ?i64 {
        if (self.hs != .connected) return null;
        return self.peer_dflags;
    }

    /// E8.2z/E8.2ad: refresh only an existing live Vm DistEntry for this
    /// connected peer. The carrier neither fabricates handles nor creates
    /// remote processes here.
    pub fn syncPeerDFlagsToVm(self: *Node) bool {
        if (self.hs != .connected) return false;
        const peer = self.peer_name orelse return false;
        const peer_node = self.atoms.lookup.get(peer) orelse return false;
        return self.vm.refreshLiveDistPeerDFlags(peer_node, self.peer_creation, self.peer_dflags);
    }

    /// Build the connected-node list in the observer's heap. This is the
    /// representation-independent observation that `nodes/1,2` will reuse once
    /// the BIF/control-surface owner lands.
    pub fn connectedNodesTerm(self: *const Node, m: *ia.Machine) !FinalTerms.Term {
        const name = self.peerNodeName() orelse return FinalTerms.nil(&m.ctx);
        const idx = try m.ctx.atoms.intern(name);
        return try FinalTerms.cons(&m.ctx, FinalTerms.atom(&m.ctx, idx), FinalTerms.nil(&m.ctx));
    }

    pub fn startHandshake(self: *Node) !void {
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(self.gpa);
        try f.append(self.gpa, FTAG_HELLO);
        try putU32(self.gpa, &f, self.creation);
        try putI64(self.gpa, &f, self.dflags);
        try f.appendSlice(self.gpa, self.name);
        try self.pushFrame(f.items);
        if (self.hs == .idle) self.hs = .hello_sent;
    }

    /// Queue a message toward remote pid `to` (with the creation stamp the
    /// sender BELIEVES the peer has). Pre-handshake sends are buffered.
    pub fn sendRemote(self: *Node, from: proc.Pid, to: u32, to_creation: u32, term: FinalTerms.Term, src: *FinalTerms.Ctx) !void {
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(self.gpa);
        try f.append(self.gpa, FTAG_SEND);
        try putU32(self.gpa, &f, from);
        try putU32(self.gpa, &f, to);
        try putU32(self.gpa, &f, to_creation);
        var payload = try etf.encode(self.gpa, src, term);
        defer payload.deinit(self.gpa);
        try f.appendSlice(self.gpa, payload.items);
        if (self.hs != .connected) {
            try self.pending.append(self.gpa, try self.gpa.dupe(u8, f.items));
        } else {
            try self.pushFrame(f.items);
        }
    }

    pub fn sendRegRemote(self: *Node, from: proc.Pid, reg_name: []const u8, term: FinalTerms.Term, src: *FinalTerms.Ctx) !void {
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(self.gpa);
        try f.append(self.gpa, FTAG_REG_SEND);
        try putU32(self.gpa, &f, from);
        try f.append(self.gpa, @intCast(reg_name.len));
        try f.appendSlice(self.gpa, reg_name);
        var payload = try etf.encode(self.gpa, src, term);
        defer payload.deinit(self.gpa);
        try f.appendSlice(self.gpa, payload.items);
        if (self.hs != .connected) {
            try self.pending.append(self.gpa, try self.gpa.dupe(u8, f.items));
        } else {
            try self.pushFrame(f.items);
        }
    }

    pub fn sendLink(self: *Node, from: proc.Pid, to: u32) !void {
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(self.gpa);
        try f.append(self.gpa, FTAG_LINK);
        try putU32(self.gpa, &f, from);
        try putU32(self.gpa, &f, to);
        try self.pushFrame(f.items);
    }

    pub fn sendExit(self: *Node, from: proc.Pid, to: u32, reason: FinalTerms.Term, src: *FinalTerms.Ctx) !void {
        var payload = try etf.encode(self.gpa, src, reason);
        defer payload.deinit(self.gpa);
        try self.sendExitWire(from, to, payload.items);
    }

    fn sendExitWire(self: *Node, from: proc.Pid, to: u32, reason_wire: []const u8) !void {
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(self.gpa);
        try f.append(self.gpa, FTAG_EXIT);
        try putU32(self.gpa, &f, from);
        try putU32(self.gpa, &f, to);
        try f.appendSlice(self.gpa, reason_wire);
        try self.pushFrame(f.items);
    }

    /// E8.2y: drain proc.Vm's owned outbound remote-exit intents for this
    /// connected peer into the carrier's existing EXIT frame stream. Rows for
    /// other peers remain queued in order.
    pub fn flushRemoteExitIntents(self: *Node) !usize {
        if (self.hs != .connected) return 0;
        const peer = self.peer_name orelse return 0;
        const peer_node = self.atoms.lookup.get(peer) orelse return 0;
        var drained: usize = 0;
        var i: usize = 0;
        while (i < self.vm.dist_remote_exits.items.len) {
            const ev = self.vm.dist_remote_exits.items[i];
            if (ev.node != peer_node) {
                i += 1;
                continue;
            }
            const to = std.math.cast(u32, ev.to) orelse {
                i += 1;
                continue;
            };
            try self.sendExitWire(ev.from, to, ev.reason_wire);
            self.vm.removeDistRemoteExitAt(i);
            drained += 1;
        }
        return drained;
    }

    /// E8.2 monitor-node precursor: a local process asks to observe peer loss.
    /// It is deliberately over the dist carrier model, not a BIF row flip.
    pub fn monitorPeer(self: *Node, watcher: proc.Pid) !bool {
        if (watcher >= self.vm.procs.items.len or !self.vm.procs.items[watcher].alive) return false;
        for (self.node_monitors.items) |pid| {
            if (pid == watcher) return true;
        }
        if (self.hs != .connected) {
            if (self.peer_name) |name| try self.deliverNodeDown(watcher, name);
            return true;
        }
        try self.node_monitors.append(self.gpa, watcher);
        return true;
    }

    pub fn unmonitorPeer(self: *Node, watcher: proc.Pid) bool {
        for (self.node_monitors.items, 0..) |pid, i| {
            if (pid == watcher) {
                _ = self.node_monitors.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Carrier loss. Monitor notifications are local signals into this node's
    /// Vm and fire at most once because the monitor set is cleared after send.
    pub fn disconnectPeer(self: *Node) !void {
        if (self.hs != .connected) return;
        self.hs = .idle;
        self.peer_creation = 0;
        self.peer_dflags = 0;
        self.peer_admitted = false;
        self.peer_rejected = false;
        self.sent_challenge = 0;
        if (self.peer_name) |name| try self.notifyNodeDown(name);
    }

    fn notifyNodeDown(self: *Node, name: []const u8) !void {
        for (self.node_monitors.items) |watcher| {
            try self.deliverNodeDown(watcher, name);
        }
        self.node_monitors.clearRetainingCapacity();
    }

    fn deliverNodeDown(self: *Node, watcher: proc.Pid, name: []const u8) !void {
        if (watcher >= self.vm.procs.items.len) return;
        const target = self.vm.procs.items[watcher];
        if (!target.alive) return;
        const tag = try target.machine.ctx.atoms.intern("nodedown");
        const node = try target.machine.ctx.atoms.intern(name);
        const msg = try FinalTerms.tuple(&target.machine.ctx, &.{
            FinalTerms.atom(&target.machine.ctx, tag),
            FinalTerms.atom(&target.machine.ctx, node),
        });
        try self.vm.signal(DIST_SYSTEM_PID, watcher, .{ .message = msg });
    }

    fn flushPending(self: *Node) !void {
        for (self.pending.items) |p| {
            try self.pushFrame(p);
            self.gpa.free(p);
        }
        self.pending.clearRetainingCapacity();
    }

    /// Feed carrier bytes from the peer (arbitrary chunking) and interpret
    /// every complete frame. Remote senders appear as pseudo-pids
    /// 0x8000|remote so the per-pair order law is observable in the trace.
    pub fn pump(self: *Node, chunk: []const u8) !void {
        try self.deframer.feed(chunk);
        for (self.deframer.out.items) |frame_bytes| {
            try self.handleFrame(frame_bytes);
            self.gpa.free(frame_bytes);
        }
        self.deframer.out.clearRetainingCapacity();
    }

    fn handleFrame(self: *Node, b: []const u8) !void {
        switch (b[0]) {
            FTAG_HELLO => {
                if (b.len < 13) return;
                const cr = getU32(b[1..5]);
                const dflags = getI64(b[5..13]);
                if (!mandatoryDFlagsAdmitted(dflags)) {
                    self.peer_admitted = false;
                    self.peer_rejected = true;
                    return;
                }
                try self.setPeerName(b[13..]);
                if (self.hs == .connected) {
                    // RECONNECT IDEMPOTENCE: duplicate hello is a no-op
                    return;
                }
                self.peer_creation = cr;
                self.peer_dflags = negotiatedDFlags(self.dflags, dflags);
                if (!mandatoryDFlagsAdmitted(self.peer_dflags)) {
                    self.peer_admitted = false;
                    self.peer_rejected = true;
                    return;
                }
                self.peer_admitted = true;
                self.peer_rejected = false;
                self.sent_challenge = cr ^ 0x5A5A_5A5A;
                var f: std.ArrayList(u8) = .empty;
                defer f.deinit(self.gpa);
                try f.append(self.gpa, FTAG_CHALLENGE);
                try putU32(self.gpa, &f, self.sent_challenge);
                try self.pushFrame(f.items);
                self.hs = .challenged;
            },
            FTAG_CHALLENGE => {
                if (self.peer_rejected) return;
                const n = getU32(b[1..5]);
                var f: std.ArrayList(u8) = .empty;
                defer f.deinit(self.gpa);
                try f.append(self.gpa, FTAG_ACK);
                try putU32(self.gpa, &f, n);
                try self.pushFrame(f.items);
                self.hs = .connected;
                try self.flushPending();
            },
            FTAG_ACK => {
                if (self.peer_rejected) return;
                const n = getU32(b[1..5]);
                if (n != self.sent_challenge) return; // bad ack: ignore
                self.hs = .connected;
                try self.flushPending();
            },
            FTAG_SEND => {
                const from = getU32(b[1..5]);
                const to = getU32(b[5..9]);
                const to_creation = getU32(b[9..13]);
                // STALE CREATION: wrong incarnation is DROPPED
                if (to_creation != self.creation) return;
                if (to >= self.vm.procs.items.len) return;
                const target = self.vm.procs.items[to];
                if (!target.alive) return;
                const msg = etf.decode(self.gpa, &target.machine.ctx, b[13..]) catch return;
                try self.vm.signal(0x8000 | @as(proc.Pid, @intCast(from & 0x7FFF)), to, .{ .message = msg });
            },
            FTAG_REG_SEND => {
                const from = getU32(b[1..5]);
                const nlen: usize = b[5];
                const rname = b[6 .. 6 + nlen];
                const payload = b[6 + nlen ..];
                const name_atom = self.atoms.intern(rname) catch return;
                const to = self.reg.whereis(name_atom) orelse return;
                // BOUND GUARD (parity with FTAG_SEND @above): a name resolving to
                // an out-of-range process index is best-effort DROPPED, never an
                // OOB panic. OTP's DOP_REG_SEND likewise discards when the
                // registered-name lookup yields no live local process.
                if (to >= self.vm.procs.items.len) return;
                const target = self.vm.procs.items[to];
                if (!target.alive) return;
                const msg = etf.decode(self.gpa, &target.machine.ctx, payload) catch return;
                try self.vm.signal(0x8000 | @as(proc.Pid, @intCast(from & 0x7FFF)), to, .{ .message = msg });
            },
            FTAG_LINK => {
                const from = getU32(b[1..5]);
                const to = getU32(b[5..9]);
                if (to >= self.vm.procs.items.len) return;
                const target = self.vm.procs.items[to];
                if (!target.alive) return;
                // record the remote link as a pseudo-pid entry
                try target.links.append(self.gpa, 0x8000 | @as(proc.Pid, @intCast(from & 0x7FFF)));
            },
            FTAG_EXIT => {
                const to = getU32(b[5..9]);
                if (to >= self.vm.procs.items.len) return;
                const target = self.vm.procs.items[to];
                if (!target.alive) return;
                const from = getU32(b[1..5]);
                // N8 (DIVERGENCE 622): decode the inbound exit reason into a
                // SENDER-OWNED fragment — never into the target's live heap
                // (the target may be running; the drain merges owner-side).
                const frag = self.gpa.create(proc.Fragment) catch return;
                frag.ctx = FinalTerms.Ctx.init(self.gpa, self.vm.atoms);
                frag.prio = false;
                frag.root = etf.decode(self.gpa, &frag.ctx, b[9..]) catch {
                    frag.ctx.deinit();
                    self.gpa.destroy(frag);
                    return;
                };
                try self.vm.signal(0x8000 | @as(proc.Pid, @intCast(from & 0x7FFF)), to, .{ .exit_sig = .{ .rfrag = frag } });
            },
            else => return, // unknown frames ignored (forward compat)
        }
    }

    /// Take the bytes queued toward the peer (the "network" reads them).
    pub fn takeOutput(self: *Node, out: *std.ArrayList(u8)) !void {
        try out.appendSlice(self.gpa, self.out.items);
        self.out.clearRetainingCapacity();
    }
};

/// Shuttle bytes both ways with SEEDED ADVERSARIAL CHUNKING until quiet.
fn shuttle(gpa: std.mem.Allocator, random: std.Random, a: *Node, b: *Node) !void {
    var quiet: usize = 0;
    while (quiet < 2) {
        var ab: std.ArrayList(u8) = .empty;
        defer ab.deinit(gpa);
        try a.takeOutput(&ab);
        var ba: std.ArrayList(u8) = .empty;
        defer ba.deinit(gpa);
        try b.takeOutput(&ba);
        if (ab.items.len == 0 and ba.items.len == 0) {
            quiet += 1;
            continue;
        }
        quiet = 0;
        var pos: usize = 0;
        while (pos < ab.items.len) {
            const step = 1 + random.uintLessThan(usize, 13);
            const end = @min(pos + step, ab.items.len);
            try b.pump(ab.items[pos..end]);
            pos = end;
        }
        pos = 0;
        while (pos < ba.items.len) {
            const step = 1 + random.uintLessThan(usize, 13);
            const end = @min(pos + step, ba.items.len);
            try a.pump(ba.items[pos..end]);
            pos = end;
        }
    }
}

/// Establish a symmetric two-node connection. Starting both sides means each
/// endpoint learns the peer's node name, so observations such as `nodes/*` and
/// `monitor_node/*` have a real carrier identity to report.
pub fn connectPair(gpa: std.mem.Allocator, random: std.Random, a: *Node, b: *Node) !void {
    try a.startHandshake();
    try b.startHandshake();
    try shuttle(gpa, random, a, b);
}

fn tcpTransferQueued(gpa: std.mem.Allocator, from: *Node, to: *Node, out_carrier: *const TcpStreamCarrier, in_carrier: *const TcpStreamCarrier) !usize {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(gpa);
    try from.takeOutput(&bytes);
    if (bytes.items.len == 0) return 0;
    try out_carrier.writeBytes(bytes.items);
    const wire = try in_carrier.readExactAlloc(gpa, bytes.items.len);
    defer gpa.free(wire);
    try to.pump(wire);
    return bytes.items.len;
}

/// Shuttle the existing dist byte stream over real loopback TCP. The byte
/// counts are known from the sender's `takeOutput`, so reads stay bounded and
/// cannot wait for an unannounced frame.
fn tcpShuttle(gpa: std.mem.Allocator, a: *Node, b: *Node, ab: *const TcpStreamCarrier, ba: *const TcpStreamCarrier) !void {
    var quiet: usize = 0;
    while (quiet < 2) {
        const moved_ab = try tcpTransferQueued(gpa, a, b, ab, ba);
        const moved_ba = try tcpTransferQueued(gpa, b, a, ba, ab);
        if (moved_ab == 0 and moved_ba == 0) quiet += 1 else quiet = 0;
    }
}

// ============================================================================
// Laws + gate G6
// ============================================================================

const echo_prog: ia.Program = &.{
    // echo: receive parent-pid-ish tag? Remote replies go back over the
    // wire at the VM-test level; the echo process here just accumulates:
    // x5 = count; receive any → x0, x5 += 1, loop
    .{ .move = .{ .src = .{ .imm = 0 }, .dst = 5 } },
    .{ .recv_any = .{ .dst = 0, .else_to = 1 } },
    .{ .add = .{ .a = .{ .x = 5 }, .b = .{ .imm = 1 }, .dst = 5 } },
    .{ .jump = .{ .to = 1 } },
};

test "E8.2aa TCP PACKET4 CARRIER: real stream preserves framed payloads" {
    const gpa = std.testing.allocator;
    const pair = try openLoopbackTcpPair();
    const client = pair[0];
    defer client.close();
    const peer = pair[1];
    defer peer.close();
    const payload_a = "hello-over-real-tcp";
    const payload_b = "\x01\x02dist-frame\x00";

    try client.writePacket4Frame(gpa, payload_a);
    const got_a = try peer.readPacket4FrameAlloc(gpa, 128);
    defer gpa.free(got_a);
    try std.testing.expectEqualStrings(payload_a, got_a);

    try peer.writePacket4Frame(gpa, payload_b);
    const got_b = try client.readPacket4FrameAlloc(gpa, 128);
    defer gpa.free(got_b);
    try std.testing.expect(std.mem.eql(u8, payload_b, got_b));
}

test "E8.2aa TCP DIST HANDSHAKE: real stream carries existing HELLO bytes" {
    const gpa = std.testing.allocator;
    const pair = try openLoopbackTcpPair();
    const ab = pair[0];
    defer ab.close();
    const ba = pair[1];
    defer ba.close();

    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    const no_unicode: i64 = 468283518908;
    const unicode: i64 = 468283523004;
    var a = try Node.initWithDFlags(gpa, &atoms_a, "a@tcp", 101, no_unicode);
    defer a.deinit();
    var b = try Node.initWithDFlags(gpa, &atoms_b, "b@tcp", 202, unicode);
    defer b.deinit();

    try a.startHandshake();
    try b.startHandshake();
    try tcpShuttle(gpa, &a, &b, &ab, &ba);

    try std.testing.expectEqual(HsState.connected, a.hs);
    try std.testing.expectEqual(HsState.connected, b.hs);
    try std.testing.expectEqualStrings("b@tcp", a.peerNodeName().?);
    try std.testing.expectEqualStrings("a@tcp", b.peerNodeName().?);
    try std.testing.expectEqual(no_unicode, a.peerDFlags().?);
    try std.testing.expectEqual(no_unicode, b.peerDFlags().?);
}

test "E8.2ab TCP DFLAG REFRESH: loopback hello updates live DistEntry flags" {
    const gpa = std.testing.allocator;
    const pair = try openLoopbackTcpPair();
    const ab = pair[0];
    defer ab.close();
    const ba = pair[1];
    defer ba.close();

    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    const no_unicode: i64 = 468283518908;
    const unicode: i64 = 468283523004;
    var a = try Node.initWithDFlags(gpa, &atoms_a, "a@tcp", 301, unicode);
    defer a.deinit();
    var b = try Node.initWithDFlags(gpa, &atoms_b, "b@tcp", 302, unicode);
    defer b.deinit();

    try a.startHandshake();
    try b.startHandshake();
    try tcpShuttle(gpa, &a, &b, &ab, &ba);
    try std.testing.expectEqual(HsState.connected, a.hs);
    try std.testing.expectEqual(unicode, a.peerDFlags().?);

    const observer = try a.vm.spawn(echo_prog, 0, null);
    const p = a.vm.procs.items[observer];
    const m = &p.machine;
    const peer_node = try atoms_a.intern("b@tcp");
    const foreign = try FinalTerms.pidExt(&m.ctx, 7, 0, peer_node, 302);
    try a.vm.dist_entries.append(gpa, .{
        .node = peer_node,
        .handle_ref = 1,
        .conn_id = 1,
        .pending = false,
        .live = true,
        .peer_creation = 302,
        .peer_dflags = no_unicode,
    });

    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try procsys.dflag_unicode_io_1(m, &.{foreign}), FinalTerms.nil(&m.ctx)));
    try a.vm.grant(observer, 1);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], FinalTerms.atom(&m.ctx, m.bool_false)));

    try std.testing.expect(a.syncPeerDFlagsToVm());
    try std.testing.expectEqual(unicode, a.vm.dist_entries.items[0].peer_dflags);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try procsys.dflag_unicode_io_1(m, &.{foreign}), FinalTerms.nil(&m.ctx)));
    try a.vm.grant(observer, 1);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], FinalTerms.atom(&m.ctx, m.bool_true)));
}

test "E8.2ab TCP REMOTE EXIT INTENT: loopback stream delivers drained EXIT frame" {
    const gpa = std.testing.allocator;
    const pair = try openLoopbackTcpPair();
    const ab = pair[0];
    defer ab.close();
    const ba = pair[1];
    defer ba.close();

    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    var a = try Node.init(gpa, &atoms_a, "a@tcp", 401);
    defer a.deinit();
    var b = try Node.init(gpa, &atoms_b, "b@tcp", 402);
    defer b.deinit();

    try a.startHandshake();
    try b.startHandshake();
    try tcpShuttle(gpa, &a, &b, &ab, &ba);

    const sender = try a.vm.spawn(echo_prog, 0, null);
    const victim = try b.vm.spawn(echo_prog, 0, null);
    b.vm.procs.items[victim].machine.trap_exit = true;

    const peer_node = try atoms_a.intern("b@tcp");
    const other_node = try atoms_a.intern("c@tcp");
    try a.vm.dist_entries.append(gpa, .{
        .node = peer_node,
        .handle_ref = 1,
        .conn_id = 1,
        .pending = false,
        .live = true,
        .peer_creation = 402,
        .peer_dflags = otp30_dflags_required,
    });
    try a.vm.dist_entries.append(gpa, .{
        .node = other_node,
        .handle_ref = 2,
        .conn_id = 2,
        .pending = false,
        .live = true,
        .peer_creation = 403,
        .peer_dflags = otp30_dflags_required,
    });

    const sm = &a.vm.procs.items[sender].machine;
    const reason = FinalTerms.atom(&sm.ctx, try atoms_a.intern("tcp_wire_boom"));
    const foreign_pid = try FinalTerms.pidExt(&sm.ctx, victim, 0, peer_node, 402);
    try std.testing.expect(FinalTerms.eqlExact(&sm.ctx, try procsys.exit_signal_2(sm, &.{ foreign_pid, reason }), FinalTerms.atom(&sm.ctx, sm.bool_true)));
    try a.vm.grant(sender, 1);

    const other_reason = FinalTerms.atom(&sm.ctx, try atoms_a.intern("still_queued"));
    const other_foreign_pid = try FinalTerms.pidExt(&sm.ctx, 99, 0, other_node, 403);
    try std.testing.expect(FinalTerms.eqlExact(&sm.ctx, try procsys.exit_signal_2(sm, &.{ other_foreign_pid, other_reason }), FinalTerms.atom(&sm.ctx, sm.bool_true)));
    try a.vm.grant(sender, 1);
    try std.testing.expectEqual(@as(usize, 2), a.vm.dist_remote_exits.items.len);

    try std.testing.expectEqual(@as(usize, 1), try a.flushRemoteExitIntents());
    try std.testing.expectEqual(@as(usize, 1), a.vm.dist_remote_exits.items.len);
    try std.testing.expectEqual(other_node, a.vm.dist_remote_exits.items[0].node);
    try tcpShuttle(gpa, &a, &b, &ab, &ba);
    try b.vm.drainSignalsPub(victim);

    const target = b.vm.procs.items[victim];
    try std.testing.expect(target.alive);
    var qbuf: [4]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
    const q = target.machine.mbox.toSeq(&qbuf);
    try std.testing.expectEqual(@as(usize, 1), q.len);
    const msg = q[0].payload;
    try std.testing.expectEqual(FinalTerms.Kind.tuple, FinalTerms.kindOf(&target.machine.ctx, msg));
    try std.testing.expectEqualStrings("EXIT", target.machine.ctx.atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&target.machine.ctx, msg, 0))));
    try std.testing.expectEqualStrings("tcp_wire_boom", target.machine.ctx.atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&target.machine.ctx, msg, 2))));
}

test "E8.2ac TCP MANDATORY DFLAGS: peer missing mandatory flags is not admitted" {
    const gpa = std.testing.allocator;
    const pair = try openLoopbackTcpPair();
    const ab = pair[0];
    defer ab.close();
    const ba = pair[1];
    defer ba.close();

    var atoms_good = AtomTable.init(gpa);
    defer atoms_good.deinit();
    var atoms_bad = AtomTable.init(gpa);
    defer atoms_bad.deinit();
    const missing_mandatory = otp30_dflags_required & ~otp30_dflags_mandatory;
    const optional_unicode_missing = otp30_dflags_required & ~@as(i64, 0x1000);
    var good = try Node.initWithDFlags(gpa, &atoms_good, "good@tcp", 501, optional_unicode_missing);
    defer good.deinit();
    var bad = try Node.initWithDFlags(gpa, &atoms_bad, "bad@tcp", 502, missing_mandatory);
    defer bad.deinit();

    try good.startHandshake();
    try bad.startHandshake();
    try tcpShuttle(gpa, &good, &bad, &ab, &ba);
    try std.testing.expect(good.hs != .connected);
    try std.testing.expect(bad.hs != .connected);
    try std.testing.expect(good.peerNodeName() == null);
    try std.testing.expect(good.peerDFlags() == null);

    const peer_node = try atoms_good.intern("bad@tcp");
    try good.vm.dist_entries.append(gpa, .{
        .node = peer_node,
        .handle_ref = 1,
        .conn_id = 1,
        .pending = false,
        .live = true,
        .peer_creation = 502,
        .peer_dflags = optional_unicode_missing,
    });
    try std.testing.expect(!good.syncPeerDFlagsToVm());
    try std.testing.expectEqual(optional_unicode_missing, good.vm.dist_entries.items[0].peer_dflags);

    const accepted_pair = try openLoopbackTcpPair();
    const cd = accepted_pair[0];
    defer cd.close();
    const dc = accepted_pair[1];
    defer dc.close();
    var atoms_c = AtomTable.init(gpa);
    defer atoms_c.deinit();
    var atoms_d = AtomTable.init(gpa);
    defer atoms_d.deinit();
    var c = try Node.initWithDFlags(gpa, &atoms_c, "c@tcp", 601, optional_unicode_missing);
    defer c.deinit();
    var d = try Node.init(gpa, &atoms_d, "d@tcp", 602);
    defer d.deinit();
    try c.startHandshake();
    try d.startHandshake();
    try tcpShuttle(gpa, &c, &d, &cd, &dc);
    try std.testing.expectEqual(HsState.connected, c.hs);
    try std.testing.expectEqual(HsState.connected, d.hs);
}

test "E8.2ad DFLAG NEGOTIATION: effective flags are intersection after OTP25 digest expansion" {
    const gpa = std.testing.allocator;
    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    const no_unicode = otp30_dflags_required & ~otp30_dflag_unicode_io;
    var a = try Node.initWithDFlags(gpa, &atoms_a, "a@neg", 701, no_unicode);
    defer a.deinit();
    var b = try Node.init(gpa, &atoms_b, "b@neg", 702);
    defer b.deinit();
    var prng = std.Random.DefaultPrng.init(0xE82AD);
    const random = prng.random();

    try connectPair(gpa, random, &a, &b);
    try std.testing.expectEqual(HsState.connected, a.hs);
    try std.testing.expectEqual(HsState.connected, b.hs);
    try std.testing.expectEqual(no_unicode, a.peerDFlags().?);
    try std.testing.expectEqual(no_unicode, b.peerDFlags().?);

    const peer_node = try atoms_a.intern("b@neg");
    try a.vm.dist_entries.append(gpa, .{
        .node = peer_node,
        .handle_ref = 1,
        .conn_id = 1,
        .pending = false,
        .live = true,
        .peer_creation = 702,
        .peer_dflags = otp30_dflags_required,
    });
    try std.testing.expect(a.syncPeerDFlagsToVm());
    try std.testing.expectEqual(no_unicode, a.vm.dist_entries.items[0].peer_dflags);

    var atoms_c = AtomTable.init(gpa);
    defer atoms_c.deinit();
    var atoms_d = AtomTable.init(gpa);
    defer atoms_d.deinit();
    const digest_peer_flags = otp30_dflags_required & ~otp30_dflags_mandatory_25;
    var c = try Node.init(gpa, &atoms_c, "c@digest", 801);
    defer c.deinit();
    var d = try Node.initWithDFlags(gpa, &atoms_d, "d@digest", 802, digest_peer_flags);
    defer d.deinit();
    var digest_prng = std.Random.DefaultPrng.init(0xD1E25);
    const digest_random = digest_prng.random();
    try connectPair(gpa, digest_random, &c, &d);
    try std.testing.expectEqual(HsState.connected, c.hs);
    try std.testing.expectEqual(otp30_dflags_required, c.peerDFlags().?);

    var atoms_e = AtomTable.init(gpa);
    defer atoms_e.deinit();
    var atoms_f = AtomTable.init(gpa);
    defer atoms_f.deinit();
    const strict_order_missing = otp30_dflags_required & ~otp30_dflag_strict_order;
    const real_mandatory_missing = otp30_dflags_required & ~otp30_dflag_unlink_id;
    var e = try Node.init(gpa, &atoms_e, "e@strict", 901);
    defer e.deinit();
    var f = try Node.initWithDFlags(gpa, &atoms_f, "f@strict", 902, strict_order_missing);
    defer f.deinit();
    var strict_prng = std.Random.DefaultPrng.init(0x5171C7);
    const strict_random = strict_prng.random();
    try connectPair(gpa, strict_random, &e, &f);
    try std.testing.expectEqual(HsState.connected, e.hs);
    try std.testing.expectEqual(strict_order_missing, e.peerDFlags().?);

    const pair = try openLoopbackTcpPair();
    const gh = pair[0];
    defer gh.close();
    const hg = pair[1];
    defer hg.close();
    var atoms_g = AtomTable.init(gpa);
    defer atoms_g.deinit();
    var atoms_h = AtomTable.init(gpa);
    defer atoms_h.deinit();
    var g = try Node.init(gpa, &atoms_g, "g@tcp", 1001);
    defer g.deinit();
    var h = try Node.initWithDFlags(gpa, &atoms_h, "h@tcp", 1002, real_mandatory_missing);
    defer h.deinit();
    try g.startHandshake();
    try h.startHandshake();
    try tcpShuttle(gpa, &g, &h, &gh, &hg);
    try std.testing.expect(g.hs != .connected);
    try std.testing.expect(h.hs != .connected);
    try std.testing.expect(g.peerDFlags() == null);
}

test "Handshake: pre-handshake sends queue and deliver IN ORDER after connect" {
    const gpa = std.testing.allocator;
    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    var a = try Node.init(gpa, &atoms_a, "a@box", 11);
    defer a.deinit();
    var b = try Node.init(gpa, &atoms_b, "b@box", 22);
    defer b.deinit();
    var prng = std.Random.DefaultPrng.init(0xD157);
    const random = prng.random();

    const rx = try b.vm.spawn(echo_prog, 0, null);
    var sender_heap = FinalTerms.Ctx.init(gpa, &atoms_a);
    defer sender_heap.deinit();

    // sends BEFORE any handshake — must all queue
    for (0..5) |k| {
        try a.sendRemote(1, rx, 22, FinalTerms.int(&sender_heap, @intCast(100 + k)), &sender_heap);
    }
    try std.testing.expectEqual(@as(usize, 5), a.pending.items.len);
    try std.testing.expectEqual(@as(usize, 0), a.out.items.len);

    try a.startHandshake();
    try shuttle(gpa, random, &a, &b);
    try std.testing.expectEqual(HsState.connected, a.hs);
    try std.testing.expectEqual(HsState.connected, b.hs);

    try b.vm.drainSignalsPub(rx);
    const p = b.vm.procs.items[rx];
    var qbuf: [16]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
    const q = p.machine.mbox.toSeq(&qbuf);
    try std.testing.expectEqual(@as(usize, 5), q.len);
    for (q, 0..) |m, k| { // IN ORDER
        try std.testing.expect(FinalTerms.eqlExact(&p.machine.ctx, m.payload, FinalTerms.int(&p.machine.ctx, @intCast(100 + k))));
    }

    // RECONNECT IDEMPOTENCE: a duplicate hello changes nothing observable
    try a.startHandshake();
    try shuttle(gpa, random, &a, &b);
    try b.vm.drainSignalsPub(rx);
    const q2 = p.machine.mbox.toSeq(&qbuf);
    try std.testing.expectEqual(@as(usize, 5), q2.len); // no duplicates
}

test "STALE CREATION: wrong incarnation stamps are dropped" {
    const gpa = std.testing.allocator;
    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    var a = try Node.init(gpa, &atoms_a, "a@box", 11);
    defer a.deinit();
    var b = try Node.init(gpa, &atoms_b, "b@box", 22);
    defer b.deinit();
    var prng = std.Random.DefaultPrng.init(0xD158);
    const random = prng.random();

    const rx = try b.vm.spawn(echo_prog, 0, null);
    var heap = FinalTerms.Ctx.init(gpa, &atoms_a);
    defer heap.deinit();
    try a.startHandshake();
    try shuttle(gpa, random, &a, &b);

    try a.sendRemote(1, rx, 21, FinalTerms.int(&heap, 666), &heap); // STALE (21 ≠ 22)
    try a.sendRemote(1, rx, 22, FinalTerms.int(&heap, 777), &heap); // fresh
    try shuttle(gpa, random, &a, &b);
    try b.vm.drainSignalsPub(rx);
    const p = b.vm.procs.items[rx];
    var qbuf: [8]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
    const q = p.machine.mbox.toSeq(&qbuf);
    try std.testing.expectEqual(@as(usize, 1), q.len); // 666 never arrived
    try std.testing.expect(FinalTerms.eqlExact(&p.machine.ctx, q[0].payload, FinalTerms.int(&p.machine.ctx, 777)));
}

test "E5.7 FRAME-CARRIED EXTERNAL PID: a foreign-node pid inside a SEND payload survives the ETF codec across the carrier, node preserved" {
    const gpa = std.testing.allocator;
    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    var a = try Node.init(gpa, &atoms_a, "a@box", 11);
    defer a.deinit();
    var b = try Node.init(gpa, &atoms_b, "b@box", 22);
    defer b.deinit();
    var prng = std.Random.DefaultPrng.init(0xD15A);
    const random = prng.random();

    const rx = try b.vm.spawn(echo_prog, 0, null);
    var heap = FinalTerms.Ctx.init(gpa, &atoms_a);
    defer heap.deinit();
    try a.startHandshake();
    try shuttle(gpa, random, &a, &b);

    // payload = {foreign_pid, 99} where foreign_pid lives on 'other@host'.
    const other_a = try atoms_a.intern("other@host");
    const fp = try FinalTerms.pidExt(&heap, 100, 7, other_a, 3);
    const payload = try FinalTerms.tuple(&heap, &.{ fp, FinalTerms.int(&heap, 99) });
    try a.sendRemote(1, rx, 22, payload, &heap);
    try shuttle(gpa, random, &a, &b);
    try b.vm.drainSignalsPub(rx);

    const p = b.vm.procs.items[rx];
    var qbuf: [8]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
    const q = p.machine.mbox.toSeq(&qbuf);
    try std.testing.expectEqual(@as(usize, 1), q.len);
    const got = q[0].payload;
    const got_pid = FinalTerms.tupleElem(&p.machine.ctx, got, 0);
    // the foreign node identity survived encode→carrier→decode on node B.
    try std.testing.expect(FinalTerms.repIsPid(&p.machine.ctx, got_pid));
    try std.testing.expectEqualStrings("other@host", FinalTerms.pidNodeName(&p.machine.ctx, got_pid));
    try std.testing.expectEqual(@as(u32, 3), FinalTerms.pidCreation(&p.machine.ctx, got_pid));
    try std.testing.expectEqual(@as(u64, 100), FinalTerms.pidNumber(&p.machine.ctx, got_pid));
}

test "G6 GATE + LOCATION TRANSPARENCY: remote sends ≡ local sends, denotationally" {
    const gpa = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0x6006 };

    for (0..8) |iter| {
        var prng = std.Random.DefaultPrng.init(cfg.seed +% iter);
        const random = prng.random();

        // ---------- scenario L: everything local (the oracle) ----------
        var atoms_l = AtomTable.init(gpa);
        defer atoms_l.deinit();
        var vm_l = try proc.Vm.init(gpa, &atoms_l);
        defer vm_l.deinit();
        const rx_l = try vm_l.spawn(echo_prog, 0, null);
        var heap_l = FinalTerms.Ctx.init(gpa, &atoms_l);
        defer heap_l.deinit();

        // ---------- scenario D: two nodes over the carrier ----------
        var atoms_a = AtomTable.init(gpa);
        defer atoms_a.deinit();
        var atoms_b = AtomTable.init(gpa);
        defer atoms_b.deinit();
        var a = try Node.init(gpa, &atoms_a, "a@box", 7);
        defer a.deinit();
        var b = try Node.init(gpa, &atoms_b, "b@box", 9);
        defer b.deinit();
        const rx_d = try b.vm.spawn(echo_prog, 0, null);
        const echo_atom = try atoms_b.intern("echo");
        try b.reg.register(echo_atom, rx_d, true);
        var heap_a = FinalTerms.Ctx.init(gpa, &atoms_a);
        defer heap_a.deinit();
        try a.startHandshake();
        try shuttle(gpa, random, &a, &b);

        // 40 seeded wire terms; identical streams to both scenarios (twin
        // generators). Half via SEND, half via REG_SEND ("echo").
        var gen_l = std.Random.DefaultPrng.init(cfg.seed +% iter +% 1);
        var gen_d = std.Random.DefaultPrng.init(cfg.seed +% iter +% 1);
        const rl = gen_l.random();
        const rd = gen_d.random();
        for (0..40) |k| {
            const t_l = try etf.genWireTerm(rl, &heap_l, 3);
            const t_d = try etf.genWireTerm(rd, &heap_a, 3);
            // local delivery (the oracle): straight into the local echo
            {
                const target = vm_l.procs.items[rx_l];
                const copy = try FinalTerms.gcCopy(&target.machine.ctx, &heap_l, t_l);
                try vm_l.signal(1, rx_l, .{ .message = copy });
            }
            if (k % 2 == 0) {
                try a.sendRemote(1, rx_d, 9, t_d, &heap_a);
            } else {
                try a.sendRegRemote(1, "echo", t_d, &heap_a);
            }
        }
        try shuttle(gpa, random, &a, &b);
        try vm_l.drainSignalsPub(rx_l);
        try b.vm.drainSignalsPub(rx_d);

        // LOCATION TRANSPARENCY: identical delivered denotation sequences
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        const pl = vm_l.procs.items[rx_l];
        const pd = b.vm.procs.items[rx_d];
        var buf_l: [64]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
        var buf_d: [64]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
        const ql = pl.machine.mbox.toSeq(&buf_l);
        const qd = pd.machine.mbox.toSeq(&buf_d);
        try expectLaw(ql.len == qd.len, "dist: same number of deliveries", cfg, iter);
        for (ql, qd) |ml, md| {
            try expectLaw(spec.eqlExact(
                try FinalTerms.denote(&pl.machine.ctx, sa, ml.payload),
                try FinalTerms.denote(&pd.machine.ctx, sa, md.payload),
            ), "dist: LOCATION TRANSPARENCY — denotation sequences agree", cfg, iter);
        }

        // per-pair order across the carrier: stamps ascend per remote sender
        var last: ?u64 = null;
        for (b.vm.events.items) |e| switch (e) {
            .deliver => |dv| {
                if (dv.to == rx_d) {
                    if (last) |prev| try expectLaw(dv.stamp > prev, "dist: per-pair order across the wire", cfg, iter);
                    last = dv.stamp;
                }
            },
            else => {},
        };

        // both echoes drained the SAME count under their schedulers
        const sched = proc.Scheduler{ .round_robin = {} };
        try sched.drive(&vm_l, 8, 400);
        const schedb = proc.Scheduler{ .round_robin = {} };
        try schedb.drive(&b.vm, 8, 400);
        // (echo loops forever; drive just lets it consume — counts equal)
        const c_l = @as(i64, @bitCast(pl.machine.regs[5])) >> 4;
        const c_d = @as(i64, @bitCast(pd.machine.regs[5])) >> 4;
        try expectLaw(c_l == c_d, "dist: echo consumed identically local and remote", cfg, iter);
    }
}

test "Cross-node LINK/EXIT: remote exit kills (or is trapped by) the linked process" {
    const gpa = std.testing.allocator;
    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    var a = try Node.init(gpa, &atoms_a, "a@box", 1);
    defer a.deinit();
    var b = try Node.init(gpa, &atoms_b, "b@box", 2);
    defer b.deinit();
    var prng = std.Random.DefaultPrng.init(0xD159);
    const random = prng.random();
    try a.startHandshake();
    try shuttle(gpa, random, &a, &b);

    // (a) untrapped: remote EXIT kills
    {
        const victim = try b.vm.spawn(echo_prog, 0, null);
        try a.sendLink(3, victim);
        try shuttle(gpa, random, &a, &b);
        var heap = FinalTerms.Ctx.init(gpa, &atoms_a);
        defer heap.deinit();
        try a.sendExit(3, victim, FinalTerms.int(&heap, 911), &heap);
        try shuttle(gpa, random, &a, &b);
        try b.vm.drainSignalsPub(victim);
        try std.testing.expect(!b.vm.procs.items[victim].alive);
    }
    // (b) trapped: remote EXIT becomes {'EXIT', PseudoPid, Reason}
    {
        const victim = try b.vm.spawn(echo_prog, 0, null);
        b.vm.procs.items[victim].machine.trap_exit = true;
        var heap = FinalTerms.Ctx.init(gpa, &atoms_a);
        defer heap.deinit();
        try a.sendExit(3, victim, FinalTerms.int(&heap, 411), &heap);
        try shuttle(gpa, random, &a, &b);
        try b.vm.drainSignalsPub(victim);
        const p = b.vm.procs.items[victim];
        try std.testing.expect(p.alive);
        var qbuf: [8]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
        const q = p.machine.mbox.toSeq(&qbuf);
        try std.testing.expectEqual(@as(usize, 1), q.len);
        const t = q[0].payload;
        try std.testing.expectEqual(FinalTerms.Kind.tuple, FinalTerms.kindOf(&p.machine.ctx, t));
        try std.testing.expect(FinalTerms.eqlExact(&p.machine.ctx, FinalTerms.tupleElem(&p.machine.ctx, t, 2), FinalTerms.int(&p.machine.ctx, 411)));
    }
}

// E24-T5 (dist hardening — the INBOUND message-delivery frames). `handleFrame`'s
// `FTAG_SEND` and `FTAG_REG_SEND` arms — the `Node.pump` path that turns a remote
// distribution message into a local mailbox delivery — were untested (the G6
// location-transparency test exercises the DIFFERENT `sendRemote`/`shuttle` ETF
// carrier path, not `handleFrame`). This law drives `handleFrame` directly with
// hand-built frames and asserts delivery, name resolution, and the stale-
// incarnation drop.
//
// SEMANTIC DOMAIN. An inbound frame `[FTAG_SEND, From(4), To(4), ToCreation(4),
// ETF-payload]` denotes "deliver the decoded payload to local process `To`" —
// DEFINED (message enters `To`'s mailbox) iff `ToCreation` matches THIS node's
// incarnation and `To` is a live local process; a stale incarnation, an
// out-of-range/dead target, or an undecodable payload is DROPPED (never a crash).
// `FTAG_REG_SEND` is the same, addressed by a REGISTERED NAME resolved through
// the node's name registry. All multi-byte fields are big-endian (`getU32`).
//
// OTP-30 CORRELATION. `erts/emulator/beam/dist.c` decodes each control message
// off the carrier: `DOP_SEND` (2) → deliver to the pid, `DOP_REG_SEND` (6) →
// resolve the registered name (`erts_whereis_name`) then deliver
// (`erts_queue_dist_message`); a message to a stale node incarnation is dropped.
// This VM's `pump`/`handleFrame` is the internal-carrier analogue (DIVERGENCE
// 212's inbound-routing surface). NOTE: the frame wire-shape here is the VM's
// simplified `Node.pump` framing, NOT the exact ETF DOP control tuple — so this
// is a DELIVERY-SEMANTICS law over the internal carrier, not an ETF-wire EQ.
//
// EVOLUTION NOTES. `FTAG_LINK`/`FTAG_EXIT` (remote link + exit-signal delivery)
// are the sibling still-untested arms — the natural next dist slice. Mutants
// MUTATION_LOG e24-t5 m1 (drop the stale-incarnation guard) / m2 (REG_SEND
// resolves the wrong registry).
test "LAW E24-T5 dist inbound FTAG_SEND/REG_SEND deliver to a local mailbox; stale incarnation dropped (OTP-30 dist.c DOP_SEND/DOP_REG_SEND)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var b = try Node.init(gpa, &atoms, "b@box", 9);
    defer b.deinit();
    const rx = try b.vm.spawn(echo_prog, 0, null);
    var heap = FinalTerms.Ctx.init(gpa, &atoms);
    defer heap.deinit();

    // Helper: encode a term as an ETF payload (freed by the caller).
    const enc = struct {
        fn f(g: std.mem.Allocator, h: *FinalTerms.Ctx, t: FinalTerms.Term) !std.ArrayList(u8) {
            return etf.encode(g, h, t);
        }
    }.f;

    // (1) FTAG_SEND with the CORRECT incarnation → the message reaches rx.
    {
        var payload = try enc(gpa, &heap, FinalTerms.int(&heap, 7));
        defer payload.deinit(gpa);
        var frame: std.ArrayList(u8) = .empty;
        defer frame.deinit(gpa);
        try frame.append(gpa, FTAG_SEND);
        try putU32(gpa, &frame, 42); // From (opaque remote pid)
        try putU32(gpa, &frame, @intCast(rx)); // To (local pid index)
        try putU32(gpa, &frame, b.creation); // ToCreation = our incarnation
        try frame.appendSlice(gpa, payload.items);
        try b.handleFrame(frame.items);
    }
    try b.vm.drainSignalsPub(rx);
    try std.testing.expectEqual(@as(usize, 1), b.vm.procs.items[rx].machine.mbox.len());

    // (2) STALE incarnation → DROPPED (mailbox unchanged).
    {
        var payload = try enc(gpa, &heap, FinalTerms.int(&heap, 8));
        defer payload.deinit(gpa);
        var frame: std.ArrayList(u8) = .empty;
        defer frame.deinit(gpa);
        try frame.append(gpa, FTAG_SEND);
        try putU32(gpa, &frame, 42);
        try putU32(gpa, &frame, @intCast(rx));
        try putU32(gpa, &frame, b.creation ^ 0xFFFF); // WRONG incarnation
        try frame.appendSlice(gpa, payload.items);
        try b.handleFrame(frame.items);
    }
    try b.vm.drainSignalsPub(rx);
    try std.testing.expectEqual(@as(usize, 1), b.vm.procs.items[rx].machine.mbox.len()); // still 1

    // (3) FTAG_REG_SEND addressed by a registered name → reaches rx.
    const srv = try atoms.intern("srv");
    try b.reg.register(srv, rx, true);
    {
        var payload = try enc(gpa, &heap, FinalTerms.int(&heap, 9));
        defer payload.deinit(gpa);
        var frame: std.ArrayList(u8) = .empty;
        defer frame.deinit(gpa);
        try frame.append(gpa, FTAG_REG_SEND);
        try putU32(gpa, &frame, 42); // From
        try frame.append(gpa, @intCast("srv".len)); // name length (1 byte)
        try frame.appendSlice(gpa, "srv");
        try frame.appendSlice(gpa, payload.items);
        try b.handleFrame(frame.items);
    }
    try b.vm.drainSignalsPub(rx);
    try std.testing.expectEqual(@as(usize, 2), b.vm.procs.items[rx].machine.mbox.len()); // now 2
}

// E24-T6 (dist hardening — the sibling inbound control frames). `handleFrame`'s
// `FTAG_LINK` (record a remote link) and `FTAG_EXIT` (deliver a remote exit
// signal) arms were the untested siblings of the E24-T5 SEND/REG_SEND delivery.
// This law drives both directly.
//
// SEMANTIC DOMAIN. `[FTAG_LINK, From(4), To(4)]` records that the REMOTE process
// `From` is linked to local process `To` — a foreign-pid link entry
// (`0x8000 | From`) on `To`, so that `To`'s death later propagates an exit back
// over the carrier. `[FTAG_EXIT, From(4), To(4), ETF-reason]` delivers an EXIT
// signal to `To`: a TRAPPING target converts it to an `{'EXIT', From, Reason}`
// mailbox message; a non-trapping target dies with `Reason` (unless `normal`).
// Both DROP silently on an out-of-range/dead target (never a crash).
//
// OTP-30 CORRELATION. `erts/emulator/beam/dist.c`: `DOP_LINK` (1) establishes a
// link to the remote pid (`erts_link_to_other_node` bookkeeping); `DOP_EXIT` (3)
// delivers an exit signal to the local process (`erts_send_exit_signal`), which
// erts's signal machinery turns into an `{'EXIT',_,_}` message for a trapping
// process — exactly the observable below. (As in E24-T5, the frame wire-shape is
// the VM's internal `Node.pump` framing, not the ETF DOP tuple — a delivery-
// semantics law, not an ETF-wire EQ.)
//
// EVOLUTION NOTES. The foreign-pid encoding `0x8000 | (From & 0x7FFF)` is the
// VM's compact remote-pid tag; a fuller remote-pid model (node + serial) would
// widen it (and the link/exit bookkeeping) — tracked with the S27 dist surface.
// Mutants MUTATION_LOG e24-t6 m1 (FTAG_LINK records the wrong pid) / m2
// (FTAG_EXIT skips the trapping delivery).
test "LAW E24-T6 dist inbound FTAG_LINK records a remote link; FTAG_EXIT delivers an exit signal to a trapping target (OTP-30 dist.c DOP_LINK/DOP_EXIT)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var b = try Node.init(gpa, &atoms, "b@box", 9);
    defer b.deinit();
    const rx = try b.vm.spawn(echo_prog, 0, null);
    var heap = FinalTerms.Ctx.init(gpa, &atoms);
    defer heap.deinit();

    // (1) FTAG_LINK: a remote link (pseudo-pid 0x8000|From) is recorded on `To`.
    {
        var frame: std.ArrayList(u8) = .empty;
        defer frame.deinit(gpa);
        try frame.append(gpa, FTAG_LINK);
        try putU32(gpa, &frame, 42); // From (remote)
        try putU32(gpa, &frame, @intCast(rx)); // To (local pid index)
        try b.handleFrame(frame.items);
    }
    const want_link: proc.Pid = 0x8000 | 42;
    var found = false;
    for (b.vm.procs.items[rx].links.items) |l| {
        if (l == want_link) found = true;
    }
    try std.testing.expect(found);

    // (2) FTAG_EXIT to a TRAPPING target → an {'EXIT', From, Reason} message.
    b.vm.procs.items[rx].machine.trap_exit = true;
    {
        var reason = try etf.encode(gpa, &heap, FinalTerms.int(&heap, 42));
        defer reason.deinit(gpa);
        var frame: std.ArrayList(u8) = .empty;
        defer frame.deinit(gpa);
        try frame.append(gpa, FTAG_EXIT);
        try putU32(gpa, &frame, 42); // From
        try putU32(gpa, &frame, @intCast(rx)); // To
        try frame.appendSlice(gpa, reason.items);
        try b.handleFrame(frame.items);
    }
    try b.vm.drainSignalsPub(rx);
    try std.testing.expectEqual(@as(usize, 1), b.vm.procs.items[rx].machine.mbox.len());
}

// E24-T8 (dist hardening — the DARK defensive DROP branches of the inbound frame
// arms). E24-T5/T6 drove the HAPPY delivery paths of FTAG_SEND/REG_SEND/LINK/EXIT;
// their unreachable-target / malformed-frame guard arms stayed dark. This law
// drives every "silently drop" branch and pins that an undeliverable inbound
// frame NEVER delivers and NEVER crashes the VM.
//
// SEMANTIC DOMAIN. dist delivery is BEST-EFFORT: a frame addressed to a process
// that does not exist (out-of-range index), is dead, or resolves via a stale
// registered name, and a frame whose ETF payload fails to decode, are all
// DISCARDED with no observable effect — the target mailbox / link set is
// unchanged and no panic occurs. `⟦drop(frame)⟧ = identity on VM state`.
//
// OTP-30 CORRELATION. Throughout `erts/emulator/beam/dist.c`, the inbound signal
// handlers look up the local receiver (`erts_proc_lookup` / registered-name
// resolution) and, on a NULL/miss, DISCARD the signal — dist message/exit/link
// delivery is best-effort, never an error back to the sender. The FTAG_REG_SEND
// bound guard added in this slice (parity with FTAG_SEND) is exactly that
// "lookup yields no live local process → drop" contract; without it a name
// registered to an out-of-range index would OOB-panic instead of dropping.
//
// Mutants MUTATION_LOG e24-t8 m1 (remove the FTAG_REG_SEND bound guard →
// OOB-index name panics) / m2 (FTAG_SEND drops the dead-target guard → delivers
// into a dead process).
test "LAW E24-T8 dist inbound frames to an unreachable/dead/malformed target are best-effort DROPPED, never a crash (OTP-30 dist.c best-effort delivery)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var b = try Node.init(gpa, &atoms, "b@box", 9);
    defer b.deinit();
    const rx = try b.vm.spawn(echo_prog, 0, null);
    var heap = FinalTerms.Ctx.init(gpa, &atoms);
    defer heap.deinit();
    const oob: u32 = 9999; // way past the 1-entry process table

    // Baseline: rx's mailbox and link set are empty.
    try std.testing.expectEqual(@as(usize, 0), b.vm.procs.items[rx].machine.mbox.len());

    // (1) FTAG_SEND to an OUT-OF-RANGE index → dropped (no panic, mbox unchanged).
    {
        var payload = try etf.encode(gpa, &heap, FinalTerms.int(&heap, 1));
        defer payload.deinit(gpa);
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(gpa);
        try f.append(gpa, FTAG_SEND);
        try putU32(gpa, &f, 42); // From
        try putU32(gpa, &f, oob); // To (OOB)
        try putU32(gpa, &f, b.creation); // correct incarnation
        try f.appendSlice(gpa, payload.items);
        try b.handleFrame(f.items);
    }

    // (2) FTAG_SEND with a MALFORMED (empty) ETF payload → decode fails → dropped.
    {
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(gpa);
        try f.append(gpa, FTAG_SEND);
        try putU32(gpa, &f, 42);
        try putU32(gpa, &f, @intCast(rx)); // valid, live target
        try putU32(gpa, &f, b.creation);
        // no payload bytes: b[13..] is empty → etf.decode returns an error
        try b.handleFrame(f.items);
    }

    // (3) FTAG_REG_SEND to an UNREGISTERED name → dropped.
    {
        var payload = try etf.encode(gpa, &heap, FinalTerms.int(&heap, 2));
        defer payload.deinit(gpa);
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(gpa);
        try f.append(gpa, FTAG_REG_SEND);
        try putU32(gpa, &f, 42);
        try f.append(gpa, @intCast("ghost".len));
        try f.appendSlice(gpa, "ghost");
        try f.appendSlice(gpa, payload.items);
        try b.handleFrame(f.items);
    }

    // (4) FTAG_REG_SEND to a name registered to an OUT-OF-RANGE index → dropped
    //     via the new bound guard (WITHOUT it: procs.items[oob] OOB-panics).
    {
        const oobname = try atoms.intern("oob");
        try b.reg.register(oobname, @intCast(oob), true);
        var payload = try etf.encode(gpa, &heap, FinalTerms.int(&heap, 3));
        defer payload.deinit(gpa);
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(gpa);
        try f.append(gpa, FTAG_REG_SEND);
        try putU32(gpa, &f, 42);
        try f.append(gpa, @intCast("oob".len));
        try f.appendSlice(gpa, "oob");
        try f.appendSlice(gpa, payload.items);
        try b.handleFrame(f.items);
    }

    // (5) FTAG_LINK to an OOB index → dropped (no link recorded on rx).
    {
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(gpa);
        try f.append(gpa, FTAG_LINK);
        try putU32(gpa, &f, 42);
        try putU32(gpa, &f, oob);
        try b.handleFrame(f.items);
    }

    // (6) FTAG_EXIT to an OOB index → dropped (no panic).
    {
        var reason = try etf.encode(gpa, &heap, FinalTerms.int(&heap, 4));
        defer reason.deinit(gpa);
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(gpa);
        try f.append(gpa, FTAG_EXIT);
        try putU32(gpa, &f, 42);
        try putU32(gpa, &f, oob);
        try f.appendSlice(gpa, reason.items);
        try b.handleFrame(f.items);
    }

    // (7) FTAG_SEND to a DEAD (but in-range) target → dropped.
    b.vm.procs.items[rx].alive = false;
    {
        var payload = try etf.encode(gpa, &heap, FinalTerms.int(&heap, 5));
        defer payload.deinit(gpa);
        var f: std.ArrayList(u8) = .empty;
        defer f.deinit(gpa);
        try f.append(gpa, FTAG_SEND);
        try putU32(gpa, &f, 42);
        try putU32(gpa, &f, @intCast(rx));
        try putU32(gpa, &f, b.creation);
        try f.appendSlice(gpa, payload.items);
        try b.handleFrame(f.items);
    }
    b.vm.procs.items[rx].alive = true; // restore for the final observation

    // OBSERVATION: after every undeliverable frame, rx's mailbox is STILL empty
    // and NO remote link was recorded — nothing was delivered, nothing crashed.
    try b.vm.drainSignalsPub(rx);
    try std.testing.expectEqual(@as(usize, 0), b.vm.procs.items[rx].machine.mbox.len());
    try std.testing.expectEqual(@as(usize, 0), b.vm.procs.items[rx].links.items.len);
}

test "E8.2y REMOTE EXIT INTENT: proc.Vm queue drains into carrier EXIT frames" {
    const gpa = std.testing.allocator;
    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    var a = try Node.init(gpa, &atoms_a, "a@box", 11);
    defer a.deinit();
    var b = try Node.init(gpa, &atoms_b, "b@box", 22);
    defer b.deinit();
    var prng = std.Random.DefaultPrng.init(0xE82A);
    const random = prng.random();
    try connectPair(gpa, random, &a, &b);

    const sender = try a.vm.spawn(echo_prog, 0, null);
    const victim = try b.vm.spawn(echo_prog, 0, null);
    b.vm.procs.items[victim].machine.trap_exit = true;

    const peer_node = try atoms_a.intern("b@box");
    const other_node = try atoms_a.intern("c@box");
    try a.vm.dist_entries.append(gpa, .{
        .node = peer_node,
        .handle_ref = 1,
        .conn_id = 1,
        .pending = false,
        .live = true,
        .peer_creation = 22,
        .peer_dflags = 468283523004,
    });
    try a.vm.dist_entries.append(gpa, .{
        .node = other_node,
        .handle_ref = 2,
        .conn_id = 2,
        .pending = false,
        .live = true,
        .peer_creation = 33,
        .peer_dflags = 468283523004,
    });

    const sm = &a.vm.procs.items[sender].machine;
    const reason = FinalTerms.atom(&sm.ctx, try atoms_a.intern("wire_boom"));
    const foreign_pid = try FinalTerms.pidExt(&sm.ctx, victim, 0, peer_node, 22);
    try std.testing.expect(FinalTerms.eqlExact(&sm.ctx, try procsys.exit_signal_2(sm, &.{ foreign_pid, reason }), FinalTerms.atom(&sm.ctx, sm.bool_true)));
    try a.vm.grant(sender, 1);
    const other_reason = FinalTerms.atom(&sm.ctx, try atoms_a.intern("stay_queued"));
    const other_foreign_pid = try FinalTerms.pidExt(&sm.ctx, 99, 0, other_node, 33);
    try std.testing.expect(FinalTerms.eqlExact(&sm.ctx, try procsys.exit_signal_2(sm, &.{ other_foreign_pid, other_reason }), FinalTerms.atom(&sm.ctx, sm.bool_true)));
    try a.vm.grant(sender, 1);

    try std.testing.expectEqual(@as(usize, 2), a.vm.dist_remote_exits.items.len);
    const decoded = try etf.decode(gpa, &sm.ctx, a.vm.dist_remote_exits.items[0].reason_wire);
    try std.testing.expect(FinalTerms.eqlExact(&sm.ctx, decoded, reason));
    const other_decoded = try etf.decode(gpa, &sm.ctx, a.vm.dist_remote_exits.items[1].reason_wire);
    try std.testing.expect(FinalTerms.eqlExact(&sm.ctx, other_decoded, other_reason));

    try std.testing.expectEqual(@as(usize, 1), try a.flushRemoteExitIntents());
    try std.testing.expectEqual(@as(usize, 1), a.vm.dist_remote_exits.items.len);
    try std.testing.expectEqual(other_node, a.vm.dist_remote_exits.items[0].node);
    try std.testing.expectEqual(@as(u64, 99), a.vm.dist_remote_exits.items[0].to);
    const remaining_decoded = try etf.decode(gpa, &sm.ctx, a.vm.dist_remote_exits.items[0].reason_wire);
    try std.testing.expect(FinalTerms.eqlExact(&sm.ctx, remaining_decoded, other_reason));
    try shuttle(gpa, random, &a, &b);
    try b.vm.drainSignalsPub(victim);

    const target = b.vm.procs.items[victim];
    try std.testing.expect(target.alive);
    var qbuf: [4]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
    const q = target.machine.mbox.toSeq(&qbuf);
    try std.testing.expectEqual(@as(usize, 1), q.len);
    const msg = q[0].payload;
    try std.testing.expectEqual(FinalTerms.Kind.tuple, FinalTerms.kindOf(&target.machine.ctx, msg));
    try std.testing.expectEqualStrings("EXIT", target.machine.ctx.atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&target.machine.ctx, msg, 0))));
    try std.testing.expectEqualStrings("wire_boom", target.machine.ctx.atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&target.machine.ctx, msg, 2))));
}

test "E8.2z DFLAG EXCHANGE: carrier hello refreshes live DistEntry flags" {
    const gpa = std.testing.allocator;
    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    const no_unicode: i64 = 468283518908;
    const unicode: i64 = 468283523004;
    var a = try Node.initWithDFlags(gpa, &atoms_a, "a@box", 11, unicode);
    defer a.deinit();
    var b = try Node.initWithDFlags(gpa, &atoms_b, "b@box", 22, unicode);
    defer b.deinit();
    var prng = std.Random.DefaultPrng.init(0xE82B);
    const random = prng.random();

    try connectPair(gpa, random, &a, &b);
    try std.testing.expectEqual(HsState.connected, a.hs);
    try std.testing.expectEqual(HsState.connected, b.hs);
    try std.testing.expectEqual(unicode, a.peerDFlags().?);
    try std.testing.expectEqual(unicode, b.peerDFlags().?);

    const observer = try a.vm.spawn(echo_prog, 0, null);
    const p = a.vm.procs.items[observer];
    const m = &p.machine;
    const peer_node = try atoms_a.intern("b@box");
    const foreign = try FinalTerms.pidExt(&m.ctx, 7, 0, peer_node, 22);
    try a.vm.dist_entries.append(gpa, .{
        .node = peer_node,
        .handle_ref = 1,
        .conn_id = 1,
        .pending = false,
        .live = true,
        .peer_creation = 22,
        .peer_dflags = no_unicode,
    });

    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try procsys.dflag_unicode_io_1(m, &.{foreign}), FinalTerms.nil(&m.ctx)));
    try a.vm.grant(observer, 1);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], FinalTerms.atom(&m.ctx, m.bool_false)));

    try std.testing.expect(a.syncPeerDFlagsToVm());
    try std.testing.expectEqual(unicode, a.vm.dist_entries.items[0].peer_dflags);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try procsys.dflag_unicode_io_1(m, &.{foreign}), FinalTerms.nil(&m.ctx)));
    try a.vm.grant(observer, 1);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.regs[0], FinalTerms.atom(&m.ctx, m.bool_true)));
}

test "E8.2 DIST CARRIER DOORSTEP: connected-node observation survives handshake chunks" {
    const gpa = std.testing.allocator;
    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    var a = try Node.init(gpa, &atoms_a, "a@box", 31);
    defer a.deinit();
    var b = try Node.init(gpa, &atoms_b, "b@box", 32);
    defer b.deinit();
    var prng = std.Random.DefaultPrng.init(0xE802);
    const random = prng.random();

    try connectPair(gpa, random, &a, &b);
    try std.testing.expectEqual(HsState.connected, a.hs);
    try std.testing.expectEqual(HsState.connected, b.hs);
    try std.testing.expectEqual(@as(usize, 1), a.connectedPeerCount());
    try std.testing.expectEqual(@as(usize, 1), b.connectedPeerCount());
    try std.testing.expectEqualStrings("b@box", a.peerNodeName().?);
    try std.testing.expectEqualStrings("a@box", b.peerNodeName().?);

    const observer = try a.vm.spawn(echo_prog, 0, null);
    const list = try a.connectedNodesTerm(&a.vm.procs.items[observer].machine);
    try std.testing.expectEqual(FinalTerms.Kind.cons, FinalTerms.kindOf(&a.vm.procs.items[observer].machine.ctx, list));
    const head = FinalTerms.listHead(&a.vm.procs.items[observer].machine.ctx, list);
    try std.testing.expect(FinalTerms.repIsAtom(head));
    try std.testing.expectEqualStrings("b@box", a.vm.procs.items[observer].machine.ctx.atoms.nameOf(FinalTerms.atomIdxOf(head)));
}

test "E8.2 MONITOR_NODE PRECURSOR: peer disconnect delivers nodedown exactly once" {
    const gpa = std.testing.allocator;
    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    var a = try Node.init(gpa, &atoms_a, "a@box", 41);
    defer a.deinit();
    var b = try Node.init(gpa, &atoms_b, "b@box", 42);
    defer b.deinit();
    var prng = std.Random.DefaultPrng.init(0xE803);
    const random = prng.random();

    try connectPair(gpa, random, &a, &b);
    const watcher = try a.vm.spawn(echo_prog, 0, null);
    try std.testing.expect(try a.monitorPeer(watcher));
    try std.testing.expectEqual(@as(usize, 1), a.node_monitors.items.len);

    try a.disconnectPeer();
    try a.vm.drainSignalsPub(watcher);
    const p = a.vm.procs.items[watcher];
    var qbuf: [4]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
    const q = p.machine.mbox.toSeq(&qbuf);
    try std.testing.expectEqual(@as(usize, 1), q.len);
    const msg = q[0].payload;
    try std.testing.expectEqual(FinalTerms.Kind.tuple, FinalTerms.kindOf(&p.machine.ctx, msg));
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&p.machine.ctx, msg));
    const tag = FinalTerms.tupleElem(&p.machine.ctx, msg, 0);
    const node = FinalTerms.tupleElem(&p.machine.ctx, msg, 1);
    try std.testing.expectEqualStrings("nodedown", p.machine.ctx.atoms.nameOf(FinalTerms.atomIdxOf(tag)));
    try std.testing.expectEqualStrings("b@box", p.machine.ctx.atoms.nameOf(FinalTerms.atomIdxOf(node)));

    try a.disconnectPeer();
    try a.vm.drainSignalsPub(watcher);
    const q2 = p.machine.mbox.toSeq(&qbuf);
    try std.testing.expectEqual(@as(usize, 1), q2.len);
}

test "E8.2 EXTERNAL IDENTITY ROUND-TRIP: pid/ref/port payloads cross the carrier" {
    const gpa = std.testing.allocator;
    var atoms_a = AtomTable.init(gpa);
    defer atoms_a.deinit();
    var atoms_b = AtomTable.init(gpa);
    defer atoms_b.deinit();
    var a = try Node.init(gpa, &atoms_a, "a@box", 51);
    defer a.deinit();
    var b = try Node.init(gpa, &atoms_b, "b@box", 52);
    defer b.deinit();
    var prng = std.Random.DefaultPrng.init(0xE804);
    const random = prng.random();

    const rx = try b.vm.spawn(echo_prog, 0, null);
    var heap = FinalTerms.Ctx.init(gpa, &atoms_a);
    defer heap.deinit();
    try connectPair(gpa, random, &a, &b);

    const other = try atoms_a.intern("other@host");
    const fp = try FinalTerms.pidExt(&heap, 100, 7, other, 3);
    const fr = try FinalTerms.refExt(&heap, .{ 1, 2, 3 }, other, 3);
    const fport = try FinalTerms.portExt(&heap, 5, other, 3);
    const payload = try FinalTerms.tuple(&heap, &.{ fp, fr, fport });
    try a.sendRemote(1, rx, 52, payload, &heap);
    try shuttle(gpa, random, &a, &b);
    try b.vm.drainSignalsPub(rx);

    const p = b.vm.procs.items[rx];
    var qbuf: [4]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
    const q = p.machine.mbox.toSeq(&qbuf);
    try std.testing.expectEqual(@as(usize, 1), q.len);
    const got = q[0].payload;
    try std.testing.expect(FinalTerms.repIsPid(&p.machine.ctx, FinalTerms.tupleElem(&p.machine.ctx, got, 0)));
    try std.testing.expect(FinalTerms.repIsRef(&p.machine.ctx, FinalTerms.tupleElem(&p.machine.ctx, got, 1)));
    try std.testing.expect(FinalTerms.repIsPort(&p.machine.ctx, FinalTerms.tupleElem(&p.machine.ctx, got, 2)));
    try std.testing.expectEqualStrings("other@host", FinalTerms.pidNodeName(&p.machine.ctx, FinalTerms.tupleElem(&p.machine.ctx, got, 0)));
    try std.testing.expectEqual(@as(u32, 3), FinalTerms.refCreation(&p.machine.ctx, FinalTerms.tupleElem(&p.machine.ctx, got, 1)));
    try std.testing.expectEqual(@as(u32, 3), FinalTerms.portCreation(&p.machine.ctx, FinalTerms.tupleElem(&p.machine.ctx, got, 2)));
}

// ===========================================================================
// E18.1 — OTP-30 distribution handshake AUTHENTICATION algebra.
//
// This is the REAL Erlang distribution challenge-response authentication of
// `lib/kernel/src/dist_util.erl` (`gen_digest/2`), the wire scheme a live
// OTP-30 peer runs. It is DISTINCT from the in-memory doorway carrier above
// (whose `sent_challenge` transform is a placeholder for the two-node message-
// ordering model, never claimed to be the OTP digest). Landing this auth core
// under law + against the pinned OTP-30 oracle is E18 Task-1's algebraic
// substance; wiring it into a live loopback-TCP handshake that reaches mutual
// `nodes/0` visibility with a booted peer is the NAMED residual, bounded by
// DIVERGENCE 210 and driven by the harness `--run-dist-handshake` mode.
//
// Semantic domain (oracle, from dist_util.erl:546-547):
//   gen_digest(Challenge, Cookie) = erlang:md5([atom_to_list(Cookie) |
//                                               integer_to_list(Challenge)])
// where Challenge is the UNSIGNED 32-bit handshake nonce rendered in decimal.
// The digest is thus a pure total function of (cookie bytes, u32 challenge).
//
// Laws (below and cross-checked LIVE by the harness):
//   DIGEST DETERMINISM     genDigest is a pure total function — equal inputs,
//                          equal 16-byte output; total over the whole u32 range.
//   DIGEST ORACLE-EQ       genDigest == OTP-30 `erlang:md5` over pinned golden
//                          vectors (the harness re-derives them from the booted
//                          peer and cross-checks `zigvm dist-digest`).
//   MUTUAL-AUTH ROUND-TRIP two parties sharing a cookie each verify the other's
//                          reply digest and BOTH reach `.connected`.
//   REJECT-PATH REJECTION  a cookie mismatch yields `.rejected` with NO peer
//                          identity recorded — the reject is atomic (no partial
//                          connected state ever observable).

/// gen_digest/2: the OTP distribution handshake challenge digest. Pure, total.
pub fn genDigest(cookie: []const u8, challenge: u32) [16]u8 {
    var h = std.crypto.hash.Md5.init(.{});
    h.update(cookie);
    var dec: [10]u8 = undefined; // u32 max = 4294967295 -> 10 decimal digits
    const s = std.fmt.bufPrint(&dec, "{d}", .{challenge}) catch unreachable;
    h.update(s);
    var out: [16]u8 = undefined;
    h.final(&out);
    return out;
}

/// Lower-hex render of a 16-byte digest into a 32-byte buffer (CLI/ledger use).
pub fn digestHex(d: [16]u8) [32]u8 {
    const lut = "0123456789abcdef";
    var out: [32]u8 = undefined;
    for (d, 0..) |b, i| {
        out[i * 2] = lut[b >> 4];
        out[i * 2 + 1] = lut[b & 0x0f];
    }
    return out;
}

pub const AuthState = enum { awaiting_challenge, awaiting_ack, connected, rejected };

/// The initiator/acceptor side of the handshake auth exchange, as a small
/// state machine over the real digest scheme. `peer_node` is recorded ONLY on
/// a verified ack, so the REJECT-PATH REJECTION law can observe that a failed
/// auth leaves no partial peer identity behind.
pub const HsAuth = struct {
    cookie: []const u8,
    our_challenge: u32,
    state: AuthState = .awaiting_challenge,
    peer_node: ?[]const u8 = null,

    pub fn init(cookie: []const u8, our_challenge: u32) HsAuth {
        return .{ .cookie = cookie, .our_challenge = our_challenge };
    }

    /// Acceptor step: peer sent us its challenge; return the reply digest we
    /// must send back (gen_digest of THEIR challenge under OUR cookie).
    pub fn replyDigest(self: *HsAuth, peer_challenge: u32) [16]u8 {
        if (self.state == .awaiting_challenge) self.state = .awaiting_ack;
        return genDigest(self.cookie, peer_challenge);
    }

    /// Verify the ack digest the peer computed for OUR challenge. On success we
    /// bind the peer identity and become `.connected`; on ANY mismatch we go
    /// `.rejected` and record NOTHING (atomic reject — no partial state).
    pub fn verifyAck(self: *HsAuth, ack: [16]u8, peer_node: []const u8) bool {
        const expect = genDigest(self.cookie, self.our_challenge);
        if (!std.mem.eql(u8, &expect, &ack)) {
            self.state = .rejected;
            self.peer_node = null;
            return false;
        }
        self.state = .connected;
        self.peer_node = peer_node;
        return true;
    }
};

/// Full two-party auth outcome: run both verification directions (A verifies
/// B's reply to A's challenge, B verifies A's reply to B's challenge). This is
/// the closed-form MUTUAL-AUTH predicate the round-trip law pins.
pub fn mutualAuth(cookie_a: []const u8, chal_a: u32, cookie_b: []const u8, chal_b: u32) AuthState {
    // A sends chal_a; B replies gen_digest(cookie_b, chal_a); A checks against
    // gen_digest(cookie_a, chal_a). Symmetrically for B.
    const a_ok = std.mem.eql(u8, &genDigest(cookie_b, chal_a), &genDigest(cookie_a, chal_a));
    const b_ok = std.mem.eql(u8, &genDigest(cookie_a, chal_b), &genDigest(cookie_b, chal_b));
    return if (a_ok and b_ok) .connected else .rejected;
}

test "LAW E18.1 DIGEST ORACLE-EQ: genDigest matches pinned OTP-30 erlang:md5" {
    // Golden vectors derived LIVE from the pinned third_party/otp node:
    //   erlang:md5([Cookie | integer_to_list(Challenge)]).
    // (recorded 2026-07-22; the harness --run-dist-handshake re-derives these
    // from a freshly booted peer and cross-checks `zigvm dist-digest`.)
    const Vec = struct { cookie: []const u8, chal: u32, hex: *const [32]u8 };
    const vecs = [_]Vec{
        .{ .cookie = "cookie", .chal = 0, .hex = "e607172a1a7adb262d2d98462463b1a9" },
        .{ .cookie = "cookie", .chal = 12345, .hex = "5563360ee47f359fc1cb107e01052d08" },
        .{ .cookie = "secret", .chal = 4294967295, .hex = "5dfd181e69aa587cc812eb333e6536b6" },
        .{ .cookie = "", .chal = 1, .hex = "c4ca4238a0b923820dcc509a6f75849b" },
        .{ .cookie = "AbCdEf", .chal = 305419896, .hex = "df9e54af271cc1bb641bb2d1f4e5a6b1" },
    };
    for (vecs) |v| {
        const got = digestHex(genDigest(v.cookie, v.chal));
        try std.testing.expectEqualStrings(v.hex, &got);
    }
}

test "LAW E18.1 DIGEST DETERMINISM: pure/total over seeded u32 challenges" {
    var prng = std.Random.DefaultPrng.init(0x18E1_D16E_57D1_2345);
    const r = prng.random();
    var i: usize = 0;
    while (i < 512) : (i += 1) {
        const cookie_len = r.intRangeAtMost(usize, 0, 24);
        var cbuf: [24]u8 = undefined;
        for (0..cookie_len) |k| cbuf[k] = r.intRangeAtMost(u8, 'a', 'z');
        const cookie = cbuf[0..cookie_len];
        const chal = r.int(u32);
        // Purity: two independent computations agree, bit for bit.
        try std.testing.expectEqual(genDigest(cookie, chal), genDigest(cookie, chal));
    }
}

test "LAW E18.1 MUTUAL-AUTH ROUND-TRIP: shared cookie connects both sides" {
    var prng = std.Random.DefaultPrng.init(0x18E1_A047_C0FF_EE00);
    const r = prng.random();
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const clen = r.intRangeAtMost(usize, 1, 16);
        var cbuf: [16]u8 = undefined;
        for (0..clen) |k| cbuf[k] = r.intRangeAtMost(u8, 'a', 'z');
        const cookie = cbuf[0..clen];
        const chal_a = r.int(u32);
        const chal_b = r.int(u32);
        // Closed form: shared cookie ⇒ connected.
        try std.testing.expectEqual(AuthState.connected, mutualAuth(cookie, chal_a, cookie, chal_b));
        // Stateful acceptor: A challenges, we reply, A's ack verifies.
        var b = HsAuth.init(cookie, chal_b);
        _ = b.replyDigest(chal_a);
        const a_ack = genDigest(cookie, chal_b); // what A computes for OUR challenge
        try std.testing.expect(b.verifyAck(a_ack, "peer@host"));
        try std.testing.expectEqual(AuthState.connected, b.state);
        try std.testing.expectEqualStrings("peer@host", b.peer_node.?);
    }
}

test "LAW E18.1 REJECT-PATH REJECTION: bad cookie leaves no partial state" {
    var prng = std.Random.DefaultPrng.init(0x18E1_BAD0_C007_1E00);
    const r = prng.random();
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const chal_a = r.int(u32);
        const chal_b = r.int(u32);
        // Distinct cookies ⇒ mutual auth must reject (mismatch is atomic).
        try std.testing.expectEqual(AuthState.rejected, mutualAuth("right", chal_a, "wrong", chal_b));
        // Stateful acceptor with cookie "right"; peer authenticated under
        // "wrong" ⇒ verifyAck fails, state rejected, NO peer identity recorded.
        var b = HsAuth.init("right", chal_b);
        _ = b.replyDigest(chal_a);
        const bad_ack = genDigest("wrong", chal_b);
        try std.testing.expect(!b.verifyAck(bad_ack, "peer@host"));
        try std.testing.expectEqual(AuthState.rejected, b.state);
        try std.testing.expect(b.peer_node == null);
    }
}

test "LAW gap-dist-real-node COMPOSED-WIRE HANDSHAKE: a full v6 handshake driven through the REAL codec (encodeSendName→decodeSendName→encodeChallenge→parseChallenge→encodeChallengeReply→decodeChallengeReply→encodeChallengeAck→decodeChallengeAck) reaches MUTUAL auth over shared cookie, crossing each side's node identity; a tampered challenge or wrong cookie leaves BOTH sides unconnected" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xD157_C0FF_EE18_2A00);
    const r = prng.random();
    // Drive the handshake ENTIRELY through the wire codec (no closed-form
    // shortcut): the bytes one side emits are exactly the bytes the other side
    // parses. This is the end-to-end wire proof the individual frame round-trips
    // + the closed-form mutualAuth predicate did NOT compose. Pure — no socket.
    const runWire = struct {
        fn go(alloc: std.mem.Allocator, cookie_i: []const u8, cookie_a: []const u8, chal_i: u32, chal_a: u32, tamper_reply: bool) !bool {
            const flags: u64 = 0x1234_5678_9ABC;
            const creation: u32 = 0xCAFE;
            // 1) initiator → acceptor: send_name
            const sn = try V6.encodeSendName(alloc, flags, creation, "init@host");
            defer alloc.free(sn);
            const dsn = try V6.decodeSendName(sn);
            try std.testing.expectEqualStrings("init@host", dsn.name); // acceptor sees initiator's name over the wire
            // 2) acceptor → initiator: send_challenge (acceptor's chal_a)
            const ch = try V6.encodeChallenge(alloc, flags, chal_a, creation, "acc@host");
            defer alloc.free(ch);
            const dch = try V6.parseChallenge(ch);
            try std.testing.expectEqualStrings("acc@host", dch.name); // initiator sees acceptor's name
            try std.testing.expectEqual(chal_a, dch.challenge);
            // 3) initiator → acceptor: challenge_reply — digest over the ACCEPTOR's
            //    challenge (dch.challenge), using the initiator's cookie.
            const reply_over: u32 = if (tamper_reply) chal_i else dch.challenge; // tamper: reply over the WRONG challenge
            const reply = V6.encodeChallengeReply(chal_i, genDigest(cookie_i, reply_over));
            const dreply = try V6.decodeChallengeReply(&reply);
            // acceptor verifies the initiator's digest over ITS OWN challenge (chal_a) + ITS cookie.
            const acc_ok = std.mem.eql(u8, &dreply.digest, &genDigest(cookie_a, chal_a));
            if (!acc_ok) return false; // acceptor rejects → not connected
            // 4) acceptor → initiator: challenge_ack — digest over the INITIATOR's
            //    challenge (dreply.challenge), using the acceptor's cookie.
            const ack = V6.encodeChallengeAck(genDigest(cookie_a, dreply.challenge));
            const dack = try V6.decodeChallengeAck(&ack);
            // initiator verifies the ack over ITS challenge (chal_i) + ITS cookie.
            return std.mem.eql(u8, &dack, &genDigest(cookie_i, chal_i));
        }
    };

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const clen = r.intRangeAtMost(usize, 1, 16);
        var cbuf: [16]u8 = undefined;
        for (0..clen) |k| cbuf[k] = r.intRangeAtMost(u8, 'a', 'z');
        const cookie = cbuf[0..clen];
        const chal_i = r.int(u32);
        const chal_a = r.int(u32);
        // (a) HAPPY: shared cookie, honest reply ⇒ mutual connected over the wire.
        try std.testing.expect(try runWire.go(gpa, cookie, cookie, chal_i, chal_a, false));
        // (b) WRONG COOKIE: the acceptor's cookie differs ⇒ neither side connects.
        try std.testing.expect(!try runWire.go(gpa, cookie, "otherck", chal_i, chal_a, false));
        // (c) TAMPERED CHALLENGE: the reply digest is computed over the wrong
        //     challenge ⇒ the acceptor's verify fails ⇒ not connected.
        if (chal_i != chal_a) // (equal challenges would make the tamper a no-op)
            try std.testing.expect(!try runWire.go(gpa, cookie, cookie, chal_i, chal_a, true));
    }
}

// ===========================================================================
// E18.2 — Live OTP-30 v6 distribution handshake (INITIATOR carrier).
//
// This is the DIVERGENCE 210 residual of E18 Task 1: the full live TCP
// distribution carrier. zigvm acts as the CONNECTING node ("handshake we
// started", dist_util.erl:454-469) against a booted, pinned OTP-30 acceptor:
//
//   epmd PORT_PLEASE2  ->  send_name('N', v6)  ->  recv_status('s',"ok")
//     ->  recv_challenge('N')  ->  challenge_reply('r')  ->  challenge_ack('a')
//
// completing to the point where the PEER'S `nodes(connected)` shows zigvm — a
// real OTP-30 node accepting zigvm as a distribution peer. Every handshake
// message is packet-2 framed (the OTP handshake framing) and carries the exact
// wire layout of `dist_util.erl` (send_name:692, send_challenge:711,
// send_challenge_reply:725, send_challenge_ack:731; recv_challenge_new:932,
// recv_status:1033). The challenge digest reuses the E18.1 `genDigest` algebra.
//
// Wire layout (big-endian; packet-2 framed):
//   send_name       'N' | Flags:64 | Creation:32 | NameLen:16 | Name
//   recv_status     's' | Status (ascii: "ok"|"ok_simultaneous"|"nok"|...)
//   recv_challenge  'N' | Flags:64 | Challenge:32 | Creation:32 | NameLen:16 | Name
//   challenge_reply 'r' | Challenge:32 | Digest:16
//   challenge_ack   'a' | Digest:16
//
// Semantic domain: the codec below is a pair of total inverse maps over each
// message shape (encode/decode), and the initiator is a linear state machine
// whose ONLY accepting terminal is a verified challenge_ack. It owns NO
// persistent DistEntry: a rejected handshake tears the socket down (the CLI
// process exits nonzero) and records nothing, so "no partial connected state"
// is structural.
//
// Laws:
//   V6 FRAMING ROUND-TRIP   decode∘encode == identity for send_name /
//                           challenge_reply / challenge_ack; parseChallenge
//                           recovers the fields of a hand-built 'N' challenge.
//   REJECT-PATH REJECTION   a bad status ("nok"/"not_allowed"), a wrong frame
//                           tag, a short frame, and a bad ack digest each yield
//                           a NAMED error and never a connected outcome.
//   TIMEOUT-BOUNDED READ    a read against a silent peer (SO_RCVTIMEO) returns
//                           error.TcpTimeout — a hang is a failed law.
// The full live flow (to the peer's nodes/0) is proven against the pinned
// OTP-30 oracle by the harness `--run-dist-handshake` live-carrier driver.
//
// E18.3 (DIVERGENCE 211 residual, REVERSE direction): `liveConnectOpen` factors
// the handshake out of `liveConnect` and returns the CONNECTED `LiveCarrier`
// with the socket still open. This is the bridge the REVERSE direction needs —
// a running `proc.Vm` registers the authenticated peer in its OWN node table
// (`proc.Vm.registerLiveDistPeer`) so zigvm's own `nodes/0` reflects it, then
// answers ticks (`LiveCarrier.holdTicks`) and tears the node down. Additional
// law: TICK-KEEPALIVE-BOUNDED (an empty packet-4 tick is echoed and the hold
// loop always returns within its bounded slice count). The reverse flow (to
// zigvm's OWN nodes/0) is proven live by the harness `dist-reverse` driver.

const otp30_dflag_published: i64 = 0x01;

pub const HsWireError = error{
    ShortFrame,
    BadTag,
    BadStatus,
    StatusNok,
    StatusNotAllowed,
    StatusAlive,
    BadAck,
    BadNodeName,
    EpmdBadResp,
    EpmdNoNode,
    TcpSockOpt,
    TcpTimeout,
};

/// The v6 handshake message codec. Pure, total, allocation only where a frame's
/// length is data-dependent (send_name / challenge); fixed frames are stack.
pub const V6 = struct {
    pub const SendName = struct { flags: u64, creation: u32, name: []const u8 };
    pub const Challenge = struct { flags: u64, challenge: u32, creation: u32, name: []const u8 };
    pub const Reply = struct { challenge: u32, digest: [16]u8 };
    pub const Status = enum { ok, ok_simultaneous, nok, not_allowed, alive, other };

    pub fn encodeSendName(gpa: std.mem.Allocator, flags: u64, creation: u32, name: []const u8) ![]u8 {
        var b: std.ArrayList(u8) = .empty;
        errdefer b.deinit(gpa);
        try b.append(gpa, 'N');
        try putU64(gpa, &b, flags);
        try putU32(gpa, &b, creation);
        const nl: u16 = @intCast(name.len);
        try b.append(gpa, @truncate(nl >> 8));
        try b.append(gpa, @truncate(nl));
        try b.appendSlice(gpa, name);
        return b.toOwnedSlice(gpa);
    }

    pub fn decodeSendName(buf: []const u8) HsWireError!SendName {
        if (buf.len < 15) return error.ShortFrame;
        if (buf[0] != 'N') return error.BadTag;
        const flags = getU64(buf[1..9]);
        const creation = getU32(buf[9..13]);
        const nl: usize = (@as(usize, buf[13]) << 8) | buf[14];
        if (buf.len < 15 + nl) return error.ShortFrame;
        return .{ .flags = flags, .creation = creation, .name = buf[15 .. 15 + nl] };
    }

    /// E21.5 (ACCEPTOR direction): render a `send_challenge` frame — the exact
    /// inverse of `parseChallenge`. The acceptor sends OUR flags, OUR fresh
    /// challenge, OUR creation, and OUR node name; the initiating peer parses it
    /// with the same layout `liveConnectOpen` uses inbound. Caller owns the slice.
    pub fn encodeChallenge(gpa: std.mem.Allocator, flags: u64, challenge: u32, creation: u32, name: []const u8) ![]u8 {
        var b: std.ArrayList(u8) = .empty;
        errdefer b.deinit(gpa);
        try b.append(gpa, 'N');
        try putU64(gpa, &b, flags);
        try putU32(gpa, &b, challenge);
        try putU32(gpa, &b, creation);
        const nl: u16 = @intCast(name.len);
        try b.append(gpa, @truncate(nl >> 8));
        try b.append(gpa, @truncate(nl));
        try b.appendSlice(gpa, name);
        return b.toOwnedSlice(gpa);
    }

    /// E21.5 (ACCEPTOR direction): the two `send_status` frames the acceptor
    /// emits — `sok` to admit the initiator, `snok` to refuse. Inverse images of
    /// the initiator's `parseStatus` ('s' | Status ascii).
    pub const status_ok: []const u8 = "sok";
    pub const status_nok: []const u8 = "snok";

    pub fn parseChallenge(buf: []const u8) HsWireError!Challenge {
        if (buf.len < 19) return error.ShortFrame;
        if (buf[0] != 'N') return error.BadTag;
        const flags = getU64(buf[1..9]);
        const challenge = getU32(buf[9..13]);
        const creation = getU32(buf[13..17]);
        const nl: usize = (@as(usize, buf[17]) << 8) | buf[18];
        if (buf.len < 19 + nl) return error.ShortFrame;
        return .{ .flags = flags, .challenge = challenge, .creation = creation, .name = buf[19 .. 19 + nl] };
    }

    pub fn encodeChallengeReply(challenge: u32, digest: [16]u8) [21]u8 {
        var out: [21]u8 = undefined;
        out[0] = 'r';
        out[1] = @truncate(challenge >> 24);
        out[2] = @truncate(challenge >> 16);
        out[3] = @truncate(challenge >> 8);
        out[4] = @truncate(challenge);
        @memcpy(out[5..21], &digest);
        return out;
    }

    pub fn decodeChallengeReply(buf: []const u8) HsWireError!Reply {
        if (buf.len != 21) return error.ShortFrame;
        if (buf[0] != 'r') return error.BadTag;
        const challenge = getU32(buf[1..5]);
        var d: [16]u8 = undefined;
        @memcpy(&d, buf[5..21]);
        return .{ .challenge = challenge, .digest = d };
    }

    pub fn encodeChallengeAck(digest: [16]u8) [17]u8 {
        var out: [17]u8 = undefined;
        out[0] = 'a';
        @memcpy(out[1..17], &digest);
        return out;
    }

    pub fn decodeChallengeAck(buf: []const u8) HsWireError![16]u8 {
        if (buf.len != 17) return error.ShortFrame;
        if (buf[0] != 'a') return error.BadTag;
        var d: [16]u8 = undefined;
        @memcpy(&d, buf[1..17]);
        return d;
    }

    pub fn parseStatus(buf: []const u8) HsWireError!Status {
        if (buf.len < 1) return error.ShortFrame;
        if (buf[0] != 's') return error.BadTag;
        const s = buf[1..];
        if (std.mem.eql(u8, s, "ok")) return .ok;
        if (std.mem.eql(u8, s, "ok_simultaneous")) return .ok_simultaneous;
        if (std.mem.eql(u8, s, "nok")) return .nok;
        if (std.mem.eql(u8, s, "not_allowed")) return .not_allowed;
        if (std.mem.eql(u8, s, "alive")) return .alive;
        return .other;
    }
};

/// Query epmd (127.0.0.1:<epmd_port>) for the distribution port of `node_prefix`
/// (the part of the node name before '@'). PORT_PLEASE2_REQ (0x7A) / PORT2_RESP
/// (0x79). Returns the peer's live dist port. Stratum-C network I/O.
pub fn epmdPortPlease(gpa: std.mem.Allocator, node_prefix: []const u8, epmd_port: u16) !u16 {
    const c = try tcpConnectLoopbackPort(epmd_port);
    defer c.close();
    var req: std.ArrayList(u8) = .empty;
    defer req.deinit(gpa);
    const len: u16 = @intCast(1 + node_prefix.len);
    try req.append(gpa, @truncate(len >> 8));
    try req.append(gpa, @truncate(len));
    try req.append(gpa, 0x7A); // PORT_PLEASE2_REQ
    try req.appendSlice(gpa, node_prefix);
    try c.writeBytes(req.items);

    var head: [2]u8 = undefined;
    try c.readExact(&head);
    if (head[0] != 0x77) return error.EpmdBadResp; // PORT2_RESP tag (119)
    if (head[1] != 0) return error.EpmdNoNode; // result != 0 -> node not registered
    var portbuf: [2]u8 = undefined;
    try c.readExact(&portbuf);
    return (@as(u16, portbuf[0]) << 8) | portbuf[1];
}

pub const ConnectConfig = struct {
    peer_node: []const u8, // "peer@127.0.0.1"
    our_node: []const u8, // "zigvm@127.0.0.1"
    cookie: []const u8,
    epmd_port: u16 = 4369,
    creation: u32 = 1,
    read_timeout_ms: u32 = 5000,
    hold_iters: u32 = 12, // post-connect hold: ~hold_iters * 200ms, answering ticks
    // E18 Task 3: the DFLAG bitset to advertise in send_name. `null` uses the
    // full required+published set (handshake/nodes-reflection paths). The
    // distributed-signals paths pass `signalsFlags()` so the peer emits every
    // control message in simple PASS_THROUGH format (no atom cache / fragments).
    flags_override: ?u64 = null,
};

pub const ConnectOutcome = struct {
    peer_port: u16,
    our_challenge: u32,
    peer_challenge: u32,
    peer_creation: u32, // E18.3: the peer's creation from recv_challenge (node incarnation)
    peer_flags: u64,
};

/// E18.3 (DIVERGENCE 211 residual, REVERSE direction): a CONNECTED v6 carrier
/// whose socket is still OPEN, handed to the caller so a running `proc.Vm` can
/// register the authenticated peer in its OWN node table (`nodes/0`) and answer
/// distribution ticks to keep the connection alive. The forward-direction
/// `liveConnect` (t1b) wraps this with an immediate hold+close; the reverse
/// driver (`zigvm dist-reverse`) keeps the carrier while the VM observes the
/// peer, then tears it down. Ownership of the socket transfers to the returned
/// value: the caller MUST `close()` it (or hand it to `liveConnect`'s wrapper).
pub const LiveCarrier = struct {
    carrier: TcpStreamCarrier,
    outcome: ConnectOutcome,

    pub fn close(self: *const LiveCarrier) void {
        self.carrier.close();
    }

    /// Bounded tick keepalive: for up to `iters` ~200ms slices, echo a TICK if
    /// the peer sends one. SO_RCVTIMEO bounds every read, so a silent peer never
    /// hangs (the tick-keepalive-bounded law).
    pub fn holdTicks(self: *const LiveCarrier, gpa: std.mem.Allocator, iters: u32) void {
        holdAnsweringTicks(gpa, &self.carrier, iters);
    }

    /// E18 Task 3 OUTBOUND: send a real DOP `REG_SEND` control message to the
    /// registered name `to_name` on the peer, carrying `msg`. FromPid is stamped
    /// with our node identity (so the peer accepts it as a pid on our node). The
    /// frame is PASS_THROUGH: byte 112 + versioned `{6, FromPid, '', ToName}` +
    /// versioned `msg`, wrapped by packet-4. Traverses the real socket.
    pub fn sendRegSend(
        self: *const LiveCarrier,
        gpa: std.mem.Allocator,
        ctx: *FinalTerms.Ctx,
        our_node: ta.AtomIdx,
        our_creation: u32,
        to_name: []const u8,
        msg: FinalTerms.Term,
    ) !void {
        const from_pid = try FinalTerms.pidExt(ctx, 1, 0, our_node, our_creation);
        const to_atom = FinalTerms.atom(ctx, try ctx.atoms.intern(to_name));
        const frame = try encodeRegSend(gpa, ctx, from_pid, to_atom, msg);
        defer gpa.free(frame);
        try self.carrier.writePacket4Frame(gpa, frame);
    }

    /// E20 Task 2 OUTBOUND: send a real DOP `SEND` (op 2) to the peer PID
    /// `to_pid`, carrying `msg`. This is `gen_server:cast` / `erlang:send` to a
    /// remote pid — the pg membership handshake casts our `local_data` and
    /// `discover` back to the peer's scope pid over THIS. Traverses the real fd.
    pub fn sendToPid(
        self: *const LiveCarrier,
        gpa: std.mem.Allocator,
        ctx: *FinalTerms.Ctx,
        to_pid: FinalTerms.Term,
        msg: FinalTerms.Term,
    ) !void {
        const frame = try encodeSend(gpa, ctx, to_pid, msg);
        defer gpa.free(frame);
        try self.carrier.writePacket4Frame(gpa, frame);
    }

    /// E21 Task 4 OUTBOUND `$gen_call`: send a `gen_server:call` to the peer's
    /// registered name `to_name`, carrying `{'$gen_call', {FromPid, [alias|Ref]},
    /// Request}`. `from_pid` and `alias_ref` are minted by the caller (who holds
    /// `alias_ref` to `matchAliasReply` the reply). Travels as a REG_SEND over the
    /// real fd; the peer's `gen:reply` routes `{[alias|Ref], Reply}` back to the
    /// alias. Returns after the request is on the wire (reply is read separately).
    pub fn sendGenCall(
        self: *const LiveCarrier,
        gpa: std.mem.Allocator,
        ctx: *FinalTerms.Ctx,
        from_pid: FinalTerms.Term,
        alias_ref: FinalTerms.Term,
        to_name: []const u8,
        request: FinalTerms.Term,
    ) !void {
        const msg = try genCall(ctx, from_pid, alias_ref, request);
        const to_atom = FinalTerms.atom(ctx, try ctx.atoms.intern(to_name));
        const frame = try encodeRegSend(gpa, ctx, from_pid, to_atom, msg);
        defer gpa.free(frame);
        try self.carrier.writePacket4Frame(gpa, frame);
    }

    /// E18 Task 3b OUTBOUND monitor: send a real DOP `MONITOR_P` for the peer's
    /// registered name `target_name`, using a fresh reference (`ref_id`) minted
    /// on OUR node. The peer echoes that ref in the `MONITOR_P_EXIT` it fires
    /// when the target dies / is absent. Returns the minted ref term (in `ctx`)
    /// so the caller can `matchMonitorExit` the reply. Traverses the real fd.
    pub fn sendMonitorP(
        self: *const LiveCarrier,
        gpa: std.mem.Allocator,
        ctx: *FinalTerms.Ctx,
        our_node: ta.AtomIdx,
        our_creation: u32,
        target_name: []const u8,
        ref_id: u32,
    ) !FinalTerms.Term {
        const from_pid = try FinalTerms.pidExt(ctx, 1, 0, our_node, our_creation);
        const target = FinalTerms.atom(ctx, try ctx.atoms.intern(target_name));
        const ref = try FinalTerms.refExt(ctx, .{ ref_id, 0, 0 }, our_node, our_creation);
        const frame = try encodeMonitorP(gpa, ctx, from_pid, target, ref);
        defer gpa.free(frame);
        try self.carrier.writePacket4Frame(gpa, frame);
        return ref;
    }

    /// E18 Task 3c OUTBOUND link: send a real DOP `LINK` for the peer pid
    /// `to_pid` (received earlier over a REG_SEND), from our minted pid. Returns
    /// our pid term so the caller can `matchLinkExit` the exit the peer sends when
    /// `to_pid` dies (it is addressed to exactly this pid). Traverses the real fd.
    pub fn sendLink(
        self: *const LiveCarrier,
        gpa: std.mem.Allocator,
        ctx: *FinalTerms.Ctx,
        our_node: ta.AtomIdx,
        our_creation: u32,
        to_pid: FinalTerms.Term,
    ) !FinalTerms.Term {
        const from_pid = try FinalTerms.pidExt(ctx, 1, 0, our_node, our_creation);
        const frame = try encodeLink(gpa, ctx, from_pid, to_pid);
        defer gpa.free(frame);
        try self.carrier.writePacket4Frame(gpa, frame);
        return from_pid;
    }

    /// E18 Task 3c OUTBOUND exit2: send a real DOP `PAYLOAD_EXIT2` to kill the
    /// peer pid `to_pid` with `reason`. The peer's linked/monitoring processes
    /// observe the death carrying exactly `reason`. Traverses the real fd.
    pub fn sendExit2(
        self: *const LiveCarrier,
        gpa: std.mem.Allocator,
        ctx: *FinalTerms.Ctx,
        our_node: ta.AtomIdx,
        our_creation: u32,
        to_pid: FinalTerms.Term,
        reason: FinalTerms.Term,
    ) !void {
        const from_pid = try FinalTerms.pidExt(ctx, 1, 0, our_node, our_creation);
        const frame = try encodePayloadExit2(gpa, ctx, from_pid, to_pid, reason);
        defer gpa.free(frame);
        try self.carrier.writePacket4Frame(gpa, frame);
    }

    /// E18 Task 3c OUTBOUND demonitor: send a real DOP `DEMONITOR_P` retracting a
    /// monitor on the peer's registered name `target_name` with the EXACT `ref`
    /// minted by an earlier `sendMonitorP`. After this the peer must NOT fire a
    /// 'DOWN' for that ref even if the target dies. Traverses the real fd.
    pub fn sendDemonitorP(
        self: *const LiveCarrier,
        gpa: std.mem.Allocator,
        ctx: *FinalTerms.Ctx,
        our_node: ta.AtomIdx,
        our_creation: u32,
        target_name: []const u8,
        ref: FinalTerms.Term,
    ) !void {
        const from_pid = try FinalTerms.pidExt(ctx, 1, 0, our_node, our_creation);
        const target = FinalTerms.atom(ctx, try ctx.atoms.intern(target_name));
        const frame = try encodeDemonitorP(gpa, ctx, from_pid, target, ref);
        defer gpa.free(frame);
        try self.carrier.writePacket4Frame(gpa, frame);
    }

    /// E20 Task 1 OUTBOUND unlink: send a real DOP `UNLINK_ID` retracting a link
    /// on the peer pid `to_pid` with a fresh non-zero `id` minted on OUR node. The
    /// peer's ERTS replies `UNLINK_ID_ACK` echoing that exact id, addressed back to
    /// our originating pid; `matchUnlinkIdAck` re-associates it. Returns our
    /// originating pid so the caller can match the ack. Traverses the real fd.
    pub fn sendUnlinkId(
        self: *const LiveCarrier,
        gpa: std.mem.Allocator,
        ctx: *FinalTerms.Ctx,
        our_node: ta.AtomIdx,
        our_creation: u32,
        id: FinalTerms.Term,
        to_pid: FinalTerms.Term,
    ) !FinalTerms.Term {
        const from_pid = try FinalTerms.pidExt(ctx, 1, 0, our_node, our_creation);
        const frame = try encodeUnlinkId(gpa, ctx, id, from_pid, to_pid);
        defer gpa.free(frame);
        try self.carrier.writePacket4Frame(gpa, frame);
        return from_pid;
    }

    /// E18 Task 3 INBOUND: bounded-read one DOP control message off the live
    /// packet-4 carrier, skipping (and echoing) empty ticks. Returns the decoded
    /// control message, or `null` if `iters` ~read_timeout slices elapse with no
    /// data frame (a silent peer never hangs — the bounded-read law). Decoded
    /// terms live in `ctx`. A malformed data frame propagates a named error.
    pub fn recvControl(
        self: *const LiveCarrier,
        gpa: std.mem.Allocator,
        ctx: *FinalTerms.Ctx,
        iters: u32,
    ) !?InboundControl {
        var i: u32 = 0;
        while (i < iters) : (i += 1) {
            const frame = self.carrier.readPacket4FrameAlloc(gpa, 1 << 20) catch |e| switch (e) {
                error.TcpTimeout => continue,
                else => return e,
            };
            defer gpa.free(frame);
            if (frame.len == 0) {
                const tick = [_]u8{ 0, 0, 0, 0 };
                self.carrier.writeBytes(&tick) catch {};
                continue;
            }
            return try decodePassThrough(gpa, ctx, frame);
        }
        return null;
    }
};

// ---------------------------------------------------------------------------
// E18 Task 3: pure DOP control-message codec (final encoding, law-governed).
// ---------------------------------------------------------------------------

/// A decoded inbound DOP control message. `op` is element 0 of the control
/// tuple; `ctrl` is the whole tuple; `msg` is the trailing payload term for
/// data-carrying ops (SEND/REG_SEND/SEND_SENDER) or `null` for control-only
/// ops (LINK/EXIT/MONITOR/...). All terms are decoded into the caller's ctx.
pub const InboundControl = struct {
    op: i64,
    ctrl: FinalTerms.Term,
    msg: ?FinalTerms.Term,
};

/// Encode a DOP `REG_SEND` frame in PASS_THROUGH format:
///   112, enc({6, FromPid, '', ToName}), enc(Msg)
/// Returns the packet-4 PAYLOAD (the caller frames it). Caller owns the slice.
pub fn encodeRegSend(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    from_pid: FinalTerms.Term,
    to_name: FinalTerms.Term,
    msg: FinalTerms.Term,
) ![]u8 {
    const empty_atom = FinalTerms.atom(ctx, try ctx.atoms.intern(""));
    const ctrl = try FinalTerms.tuple(ctx, &.{
        FinalTerms.int(ctx, DOP_REG_SEND),
        from_pid,
        empty_atom,
        to_name,
    });
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, DIST_PASS_THROUGH);
    var ce = try etf.encode(gpa, ctx, ctrl);
    defer ce.deinit(gpa);
    try out.appendSlice(gpa, ce.items);
    var me = try etf.encode(gpa, ctx, msg);
    defer me.deinit(gpa);
    try out.appendSlice(gpa, me.items);
    return out.toOwnedSlice(gpa);
}

/// Encode a DOP `SEND` frame (to a PID, not a registered name) in PASS_THROUGH
/// format: `112, enc({2, '', ToPid}), enc(Msg)`. `gen_server:cast(RemotePid, M)`
/// travels as THIS (op 2). Returns the packet-4 PAYLOAD; the caller frames it and
/// owns the slice. Used by the pg membership handshake to cast our local_data /
/// discover back to the peer's scope pid.
pub fn encodeSend(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    to_pid: FinalTerms.Term,
    msg: FinalTerms.Term,
) ![]u8 {
    const empty_atom = FinalTerms.atom(ctx, try ctx.atoms.intern(""));
    const ctrl = try FinalTerms.tuple(ctx, &.{
        FinalTerms.int(ctx, DOP_SEND),
        empty_atom,
        to_pid,
    });
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, DIST_PASS_THROUGH);
    var ce = try etf.encode(gpa, ctx, ctrl);
    defer ce.deinit(gpa);
    try out.appendSlice(gpa, ce.items);
    var me = try etf.encode(gpa, ctx, msg);
    defer me.deinit(gpa);
    try out.appendSlice(gpa, me.items);
    return out.toOwnedSlice(gpa);
}

/// Decode a single inbound DOP control frame in PASS_THROUGH format. Splits the
/// control tuple from the trailing message at the exact ETF term boundary
/// (`etf.decodeConsumed`). Returns a named error on a malformed frame — never a
/// partial or fabricated delivery.
pub fn decodePassThrough(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    frame: []const u8,
) !InboundControl {
    if (frame.len < 1 or frame[0] != DIST_PASS_THROUGH) return error.BadDistFrame;
    const dc = try etf.decodeConsumed(gpa, ctx, frame[1..]);
    if (FinalTerms.kindOf(ctx, dc.term) != .tuple) return error.BadDistFrame;
    if (FinalTerms.tupleArity(ctx, dc.term) < 1) return error.BadDistFrame;
    const op_term = FinalTerms.tupleElem(ctx, dc.term, 0);
    if (!FinalTerms.repIsSmall(op_term)) return error.BadDistFrame;
    const op = FinalTerms.smallValOf(op_term);
    const rest = frame[1 + dc.consumed ..];
    const msg: ?FinalTerms.Term = if (rest.len > 0) try etf.decode(gpa, ctx, rest) else null;
    return .{ .op = op, .ctrl = dc.term, .msg = msg };
}

/// The registered-name target of a REG_SEND control tuple `{6, From, '', Name}`.
pub fn regSendName(ctx: *FinalTerms.Ctx, ctrl: FinalTerms.Term) ?ta.AtomIdx {
    if (FinalTerms.tupleArity(ctx, ctrl) < 4) return null;
    const name = FinalTerms.tupleElem(ctx, ctrl, 3);
    if (!FinalTerms.repIsAtom(name)) return null;
    return FinalTerms.atomIdxOf(name);
}

// ---------------------------------------------------------------------------
// E18 Task 3b (DIVERGENCE 260 residual): remote MONITOR_P → 'DOWN' + the
// `noconnection` teardown flush. A control-only PASS_THROUGH frame (no trailing
// message) carries LINK/UNLINK/MONITOR_P/DEMONITOR_P/MONITOR_P_EXIT/EXIT/EXIT2;
// `decodePassThrough` already surfaces every one (op + ctrl tuple, msg=null).
// This slice DRIVES the monitor pair end-to-end against the pinned peer.
// ---------------------------------------------------------------------------

/// Encode a control-ONLY DOP frame in PASS_THROUGH format: `112, enc(ctrl)`
/// with NO trailing message. This is the shared final encoding for every
/// control-only op (MONITOR_P/DEMONITOR_P/LINK/UNLINK/EXIT/EXIT2). Returns the
/// packet-4 PAYLOAD; the caller frames it and owns the slice.
pub fn encodePassThroughCtrl(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    ctrl: FinalTerms.Term,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, DIST_PASS_THROUGH);
    var ce = try etf.encode(gpa, ctx, ctrl);
    defer ce.deinit(gpa);
    try out.appendSlice(gpa, ce.items);
    return out.toOwnedSlice(gpa);
}

/// Encode a DOP `MONITOR_P` frame `{19, FromPid, Target, Ref}`. `Target` is the
/// monitored process — a registered-name atom (`{Name, Node}` monitor) or a pid
/// on the peer. `Ref` is the monitor reference minted on OUR node; the peer
/// echoes it verbatim in the `MONITOR_P_EXIT` that fires when the target dies /
/// is absent, which is how `matchMonitorExit` re-associates the reply.
pub fn encodeMonitorP(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    from_pid: FinalTerms.Term,
    target: FinalTerms.Term,
    ref: FinalTerms.Term,
) ![]u8 {
    const ctrl = try FinalTerms.tuple(ctx, &.{
        FinalTerms.int(ctx, DOP_MONITOR_P),
        from_pid,
        target,
        ref,
    });
    return encodePassThroughCtrl(gpa, ctx, ctrl);
}

/// Encode a DOP `DEMONITOR_P` frame `{20, FromPid, Target, Ref}` (the symmetric
/// retract of `encodeMonitorP`). Same shape, op 20 — a demonitored ref must
/// never fire a 'DOWN'.
pub fn encodeDemonitorP(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    from_pid: FinalTerms.Term,
    target: FinalTerms.Term,
    ref: FinalTerms.Term,
) ![]u8 {
    const ctrl = try FinalTerms.tuple(ctx, &.{
        FinalTerms.int(ctx, DOP_DEMONITOR_P),
        from_pid,
        target,
        ref,
    });
    return encodePassThroughCtrl(gpa, ctx, ctrl);
}

/// The core of "monitor-fires-exactly-once, right-ref-identity": if `ic` is a
/// monitor-exit control message whose `Ref` (element 3) is EXACTLY the reference
/// we minted for this monitor (same node atom, creation, and id words —
/// `eqlExact`), return the wire `Reason` term. Two on-wire encodings are
/// accepted, per the negotiated DFLAGs:
///   - `MONITOR_P_EXIT` (21): `{21, FromProc, ToPid, Ref, Reason}` — Reason in
///     the control tuple (element 4), no trailing payload.
///   - `PAYLOAD_MONITOR_P_EXIT` (28): `{28, FromProc, ToPid, Ref}` — Reason is
///     the TRAILING payload term (`ic.msg`); this is what an EXIT_PAYLOAD peer
///     (our signals carrier) actually sends.
/// A different ref, a non-exit op, or a malformed tuple returns `null` (no
/// 'DOWN' — a mis-delivered/fabricated signal is unrepresentable). The returned
/// term lives in `ctx` (decoded off the live carrier).
pub fn matchMonitorExit(
    ctx: *FinalTerms.Ctx,
    ic: InboundControl,
    our_ref: FinalTerms.Term,
) ?FinalTerms.Term {
    if (ic.op != DOP_MONITOR_P_EXIT and ic.op != DOP_PAYLOAD_MONITOR_P_EXIT) return null;
    if (FinalTerms.tupleArity(ctx, ic.ctrl) < 4) return null;
    const wire_ref = FinalTerms.tupleElem(ctx, ic.ctrl, 3);
    if (!FinalTerms.repIsRef(ctx, wire_ref)) return null;
    if (!FinalTerms.eqlExact(ctx, wire_ref, our_ref)) return null;
    if (ic.op == DOP_MONITOR_P_EXIT) {
        if (FinalTerms.tupleArity(ctx, ic.ctrl) < 5) return null;
        return FinalTerms.tupleElem(ctx, ic.ctrl, 4);
    }
    // PAYLOAD variant: reason is the trailing payload term.
    return ic.msg;
}

/// Build the deterministic `{Type, Object, Reason}` triple a remote by-name
/// monitor's 'DOWN' delivers — `{process, {Name, PeerNode}, Reason}`. This is
/// the comparison surface for the live oracle (the monitor Ref is opaque/fresh
/// and is verified structurally by `matchMonitorExit`, not by byte-compare).
/// `reason` is either the wire reason (`matchMonitorExit`) or the synthesized
/// `noconnection` atom on carrier teardown.
pub fn downTriple(
    ctx: *FinalTerms.Ctx,
    name: []const u8,
    peer_node: []const u8,
    reason: FinalTerms.Term,
) !FinalTerms.Term {
    const object = try FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern(name)),
        FinalTerms.atom(ctx, try ctx.atoms.intern(peer_node)),
    });
    return FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern("process")),
        object,
        reason,
    });
}

/// Build the full `{'DOWN', Ref, process, {Name, PeerNode}, Reason}` 5-tuple —
/// exactly what erts delivers into the watcher's mailbox for a remote by-name
/// monitor. The live driver delivers THIS as a real `Vm.signal(.message)`.
pub fn downMessage(
    ctx: *FinalTerms.Ctx,
    ref: FinalTerms.Term,
    name: []const u8,
    peer_node: []const u8,
    reason: FinalTerms.Term,
) !FinalTerms.Term {
    const object = try FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern(name)),
        FinalTerms.atom(ctx, try ctx.atoms.intern(peer_node)),
    });
    return FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern("DOWN")),
        ref,
        FinalTerms.atom(ctx, try ctx.atoms.intern("process")),
        object,
        reason,
    });
}


// ---------------------------------------------------------------------------
// E18 Task 3c (DIVERGENCE 261 residual): remote LINK + inbound EXIT propagation,
// remote EXIT2 (outbound kill), and DEMONITOR retract. LINK/EXIT/EXIT2 carry
// PIDS (not names): the live driver first receives the peer's OWN pid over a
// REG_SEND (e18-t3 inbound), then LINK/EXIT2s THAT exact pid. When the linked
// peer proc dies the peer sends EXIT (3) — or, under the negotiated EXIT_PAYLOAD
// DFLAG, PAYLOAD_EXIT (24) with the reason as a TRAILING payload — addressed to
// our exact pid; `matchLinkExit` accepts both and yields {From, Reason} only for
// our exact target pid (`eqlExact`). `exitMessage` builds the delivered
// `{'EXIT', From, Reason}`. This is the pid-carrying analogue of the e18-t3b
// monitor codec.
// ---------------------------------------------------------------------------

/// Encode a DOP `LINK` frame `{1, FromPid, ToPid}` (control-only PASS_THROUGH).
/// The cross-node link is established when the peer receives this; the peer then
/// delivers our pid the EXIT signal when `ToPid` dies. Caller owns the slice.
pub fn encodeLink(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    from_pid: FinalTerms.Term,
    to_pid: FinalTerms.Term,
) ![]u8 {
    const ctrl = try FinalTerms.tuple(ctx, &.{
        FinalTerms.int(ctx, DOP_LINK),
        from_pid,
        to_pid,
    });
    return encodePassThroughCtrl(gpa, ctx, ctrl);
}

/// Encode a DOP `PAYLOAD_EXIT2` frame `{26, FromPid, ToPid}` + a TRAILING Reason
/// payload — the EXIT_PAYLOAD-negotiated form of `exit/2` to a remote pid (op 26,
/// mirroring the peer's own exit encoding under DFLAG_EXIT_PAYLOAD). Delivering
/// this kills `ToPid` on the peer with `reason`. Caller owns the slice.
pub fn encodePayloadExit2(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    from_pid: FinalTerms.Term,
    to_pid: FinalTerms.Term,
    reason: FinalTerms.Term,
) ![]u8 {
    const ctrl = try FinalTerms.tuple(ctx, &.{
        FinalTerms.int(ctx, DOP_PAYLOAD_EXIT2),
        from_pid,
        to_pid,
    });
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, DIST_PASS_THROUGH);
    var ce = try etf.encode(gpa, ctx, ctrl);
    defer ce.deinit(gpa);
    try out.appendSlice(gpa, ce.items);
    var me = try etf.encode(gpa, ctx, reason);
    defer me.deinit(gpa);
    try out.appendSlice(gpa, me.items);
    return out.toOwnedSlice(gpa);
}

/// A decoded cross-node exit signal: the pid that died (`from`) and the exit
/// `reason`, recovered from a LINK exit (peer proc death) or an EXIT2.
pub const LinkExit = struct { from: FinalTerms.Term, reason: FinalTerms.Term };

/// The core of "exit-propagates-reason, right-target-identity": if `ic` is an
/// exit control message whose `ToPid` (element 2) is EXACTLY our linked pid
/// (`eqlExact`), return {FromPid, Reason}. Four on-wire encodings are accepted:
///   - `EXIT` (3)  / `EXIT2` (8):  `{op, From, To, Reason}` — reason in element 3.
///   - `PAYLOAD_EXIT` (24) / `PAYLOAD_EXIT2` (26): `{op, From, To}` — reason is
///     the TRAILING payload (`ic.msg`); this is what an EXIT_PAYLOAD peer (our
///     signals carrier) actually sends on a linked peer proc's death.
/// A different target pid, a non-exit op, or a malformed tuple returns `null`
/// (a mis-delivered/fabricated exit is unrepresentable). Terms live in `ctx`.
pub fn matchLinkExit(
    ctx: *FinalTerms.Ctx,
    ic: InboundControl,
    our_pid: FinalTerms.Term,
) ?LinkExit {
    const is_payload = ic.op == DOP_PAYLOAD_EXIT or ic.op == DOP_PAYLOAD_EXIT2;
    const is_ctrl = ic.op == DOP_EXIT or ic.op == DOP_EXIT2;
    if (!is_payload and !is_ctrl) return null;
    if (FinalTerms.tupleArity(ctx, ic.ctrl) < 3) return null;
    const from = FinalTerms.tupleElem(ctx, ic.ctrl, 1);
    const to = FinalTerms.tupleElem(ctx, ic.ctrl, 2);
    if (!FinalTerms.repIsPid(ctx, to)) return null;
    if (!FinalTerms.eqlExact(ctx, to, our_pid)) return null;
    const reason: FinalTerms.Term = if (is_ctrl) blk: {
        if (FinalTerms.tupleArity(ctx, ic.ctrl) < 4) return null;
        break :blk FinalTerms.tupleElem(ctx, ic.ctrl, 3);
    } else (ic.msg orelse return null);
    return .{ .from = from, .reason = reason };
}

/// Build the `{'EXIT', From, Reason}` message erts delivers into a trapping
/// linked process's mailbox when the linked (remote) pid `from` dies. The live
/// driver delivers THIS as a real `Vm.signal(.message)`.
pub fn exitMessage(
    ctx: *FinalTerms.Ctx,
    from: FinalTerms.Term,
    reason: FinalTerms.Term,
) !FinalTerms.Term {
    return FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern("EXIT")),
        from,
        reason,
    });
}

// ---------------------------------------------------------------------------
// E20 Task 1 (DIVERGENCE 262 residual): remote `unlink` as the OTP-30 two-frame
// UNLINK_ID/UNLINK_ID_ACK retract, inbound `exit/2` TO a zigvm-local victim (the
// mirror of the outbound `dist-exit2`), and remote `exit/1` self-exit (the
// normal-reason link edge distinct from e18-t3c's abnormal `linkboom`). unlink is
// a genuine two-frame handshake — strictly more than the one-shot LINK: zigvm
// sends UNLINK_ID and the peer's ERTS ACKs it with our EXACT id, over the real
// socket. `matchUnlinkIdAck` closes the loop, keyed on both the id and our exact
// originating pid (`eqlExact`), so a mis-delivered/fabricated ack is
// unrepresentable.
// ---------------------------------------------------------------------------

/// Encode a DOP `UNLINK_ID` frame `{35, Id, FromPid, ToPid}` (control-only
/// PASS_THROUGH). `Id` is a NON-ZERO unlink id minted on OUR node; the peer
/// echoes it verbatim in the `UNLINK_ID_ACK` it sends back, which is how
/// `matchUnlinkIdAck` re-associates the ack with this exact retract. `FromPid` is
/// our originating pid, `ToPid` the remote process being unlinked. Caller owns
/// the slice.
pub fn encodeUnlinkId(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    id: FinalTerms.Term,
    from_pid: FinalTerms.Term,
    to_pid: FinalTerms.Term,
) ![]u8 {
    const ctrl = try FinalTerms.tuple(ctx, &.{
        FinalTerms.int(ctx, DOP_UNLINK_ID),
        id,
        from_pid,
        to_pid,
    });
    return encodePassThroughCtrl(gpa, ctx, ctrl);
}

/// Encode a DOP `UNLINK_ID_ACK` frame `{36, Id, FromPid, ToPid}` — the symmetric
/// acknowledgement of `encodeUnlinkId` (same shape, op 36). On the wire the ERTS
/// receiver builds this with `FromPid` = the (formerly) linked local proc and
/// `ToPid` = the original unlinker; the ack echoes the exact `Id`. Provided so the
/// two-frame round-trip is a pure law (encode-both → decode → match), not only a
/// live observation. Caller owns the slice.
pub fn encodeUnlinkIdAck(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    id: FinalTerms.Term,
    from_pid: FinalTerms.Term,
    to_pid: FinalTerms.Term,
) ![]u8 {
    const ctrl = try FinalTerms.tuple(ctx, &.{
        FinalTerms.int(ctx, DOP_UNLINK_ID_ACK),
        id,
        from_pid,
        to_pid,
    });
    return encodePassThroughCtrl(gpa, ctx, ctrl);
}

/// The core of "unlink two-frame round-trip, right-id-and-target-identity": if
/// `ic` is an `UNLINK_ID_ACK` (op 36) whose `Id` (element 1) is EXACTLY the id we
/// minted for this unlink AND whose `ToPid` (element 3) is EXACTLY our originating
/// pid (both `eqlExact`), return `true` — the peer completed the handshake for OUR
/// retract. A different id, a different target, a non-ack op, or a malformed tuple
/// returns `false` (a mis-delivered/fabricated ack is unrepresentable).
pub fn matchUnlinkIdAck(
    ctx: *FinalTerms.Ctx,
    ic: InboundControl,
    our_pid: FinalTerms.Term,
    our_id: FinalTerms.Term,
) bool {
    if (ic.op != DOP_UNLINK_ID_ACK) return false;
    if (FinalTerms.tupleArity(ctx, ic.ctrl) < 4) return false;
    const wire_id = FinalTerms.tupleElem(ctx, ic.ctrl, 1);
    if (!FinalTerms.eqlExact(ctx, wire_id, our_id)) return false;
    const to = FinalTerms.tupleElem(ctx, ic.ctrl, 3);
    if (!FinalTerms.repIsPid(ctx, to)) return false;
    return FinalTerms.eqlExact(ctx, to, our_pid);
}

// ---------------------------------------------------------------------------
// E18 Task 4 (DIVERGENCE 320/321/322): global coordination — net_kernel,
// global, pg. When zigvm completes the live signals handshake, the peer's
// COORDINATION services react to the nodeup and initiate their convergence
// protocols OVER THE LIVE CARRIER, addressed to a like-named process on zigvm:
//   - `global`: the peer's `global_name_server` casts an `init_connect` to
//     `{global_name_server, zigvm}` — the first step of the name-table sync
//     that enforces the single-owner consistency law.
//   - `pg`: the peer's default `pg` scope casts a `discover` to `{pg, zigvm}` —
//     the membership-broadcast handshake that precedes group sync.
//   - `net_kernel`: the peer's `net_kernel:monitor_nodes` observes zigvm's
//     nodeup, keeps it up across a net_ticktime window via the tick keepalive
//     (already lawed — TICK-KEEPALIVE-BOUNDED), then observes a single clean
//     nodedown on teardown.
// These matchers extract the OBSERVABLE identity from the REG_SEND payload the
// peer sends, so the live driver can assert the peer's coordination service
// genuinely admitted zigvm as a cluster member. Completing the transactions
// (global's lock/exchange/resolved → a name visible from BOTH nodes; pg's
// join/sync → group membership visible from both) needs zigvm to run the
// locker / pg-scope state machines — a strictly larger boundary, named honestly
// (DIVERGENCE 320 global, 321 pg), never false-EQ here.
// ---------------------------------------------------------------------------

/// True iff `msg` is a tuple whose element 0 is the atom `tag`. The shared
/// tag-dispatch for coordination casts (`'$gen_cast'`, `discover`).
fn msgTagIs(ctx: *FinalTerms.Ctx, msg: FinalTerms.Term, tag: []const u8) bool {
    if (FinalTerms.kindOf(ctx, msg) != .tuple) return false;
    if (FinalTerms.tupleArity(ctx, msg) < 1) return false;
    const t0 = FinalTerms.tupleElem(ctx, msg, 0);
    if (!FinalTerms.repIsAtom(t0)) return false;
    return std.mem.eql(u8, ctx.atoms.nameOf(FinalTerms.atomIdxOf(t0)), tag);
}

/// GLOBAL name-exchange initiation: if `msg` is the `global_name_server` cast
/// `{'$gen_cast', {init_connect, {Vsn, MyTag}, Node, Locker}}` the peer sends to
/// a newly connected node, return the `Node` atom term (the initiating peer's
/// node identity — element 2 of the inner `init_connect` tuple). Any other shape
/// (a foreign cast, a non-init_connect payload, a malformed tuple) returns
/// `null` — a fabricated global membership is unrepresentable. The returned term
/// lives in `ctx` (decoded off the live carrier).
pub fn globalInitConnectNode(ctx: *FinalTerms.Ctx, msg: FinalTerms.Term) ?FinalTerms.Term {
    if (!msgTagIs(ctx, msg, "$gen_cast")) return null;
    if (FinalTerms.tupleArity(ctx, msg) < 2) return null;
    const inner = FinalTerms.tupleElem(ctx, msg, 1);
    if (!msgTagIs(ctx, inner, "init_connect")) return null;
    if (FinalTerms.tupleArity(ctx, inner) < 3) return null;
    const node = FinalTerms.tupleElem(ctx, inner, 2);
    if (!FinalTerms.repIsAtom(node)) return null;
    return node;
}

/// PG membership discovery: if `msg` is the default-scope `pg` broadcast
/// `{discover, ScopePid, ...}` the peer's pg scope sends on nodeup, return the
/// `ScopePid` term (element 1 — a pid on the peer's node). Any other shape
/// returns `null`. The returned pid's node (`pidNodeName`) identifies the peer
/// whose pg scope initiated the membership handshake. Term lives in `ctx`.
pub fn pgDiscoverPid(ctx: *FinalTerms.Ctx, msg: FinalTerms.Term) ?FinalTerms.Term {
    if (!msgTagIs(ctx, msg, "discover")) return null;
    if (FinalTerms.tupleArity(ctx, msg) < 2) return null;
    const scope_pid = FinalTerms.tupleElem(ctx, msg, 1);
    if (!FinalTerms.repIsPid(ctx, scope_pid)) return null;
    return scope_pid;
}

// ---------------------------------------------------------------------------
// E20 Task 2 (DIVERGENCE 320/321): the coordination STATE MACHINES beyond
// E18.4's cast decoding. Two pure cores carry the convergence semantics whose
// live completion the two services promise:
//   - pg  (321): membership-convergence — a scope's global view is the JOIN
//     (set union) of every node's local group→member data, a join-semilattice.
//     Merging a peer's local_data is the CRDT-like union that makes a member on
//     one node visible from BOTH. This core is DRIVEN LIVE by `dist-pg-join`:
//     on the peer's `discover`, zigvm casts back its local_data so the pinned
//     peer's own `pg:get_members/1` converges to include zigvm's member.
//   - global (320): registration-consistency — the PAYOFF of the locker
//     exchange/resolved phase. Merging two name-tables must leave AT MOST ONE
//     owner per name (single-owner). The live completion needs the full 2-phase
//     locker (`set_lock` gen:call over dist), a strictly larger boundary named
//     honestly (DIVERGENCE 320 residual); the resolve core + its law land here.
// ---------------------------------------------------------------------------

/// A pg membership as a (group, member-pid-identity) pair. The member pid is
/// modelled by its OBSERVABLE identity — the node it lives on plus its number —
/// which is all `pg:get_members/1` compares and all the convergence law needs.
pub const GroupMember = struct {
    group: []const u8,
    node: []const u8,
    num: u64,

    pub fn eql(a: GroupMember, b: GroupMember) bool {
        return a.num == b.num and std.mem.eql(u8, a.group, b.group) and std.mem.eql(u8, a.node, b.node);
    }
};

/// True iff the pair-set `set` already contains `m` (membership is a SET — no
/// duplicate pair). The dedup guard for the join.
pub fn pgContains(set: []const GroupMember, m: GroupMember) bool {
    for (set) |x| if (x.eql(m)) return true;
    return false;
}

/// The JOIN (set union) of two pg views into `out` (deduped, `a` first then the
/// new members of `b`). This is the pure core of `update_global_view_and_notify`:
/// a peer's members are ADDED, never duplicated. Idempotent, commutative and
/// associative up to set equality — the join-semilattice that makes membership
/// CONVERGE regardless of message order. Returns the count written (≤ a.len+b.len).
pub fn pgJoin(a: []const GroupMember, b: []const GroupMember, out: []GroupMember) usize {
    var n: usize = 0;
    for (a) |m| {
        if (!pgContains(out[0..n], m)) {
            out[n] = m;
            n += 1;
        }
    }
    for (b) |m| {
        if (!pgContains(out[0..n], m)) {
            out[n] = m;
            n += 1;
        }
    }
    return n;
}

/// E20 Task 3 (DIVERGENCE 322): the RETRACT half of the reconvergence cycle —
/// drop every member living on `node` from `set` (append the survivors into
/// `out`). This is the pure core of pg's `nodedown` handler: when a node
/// partitions away, its members leave the global view; on `nodeup` a fresh
/// `pgJoin` of its re-cast local_data restores them. `pgJoin(pgRemoveNode(full,
/// C), C_data) == full` (up to set equality) is the partition-heal law — a
/// join-semilattice recovers its LUB after a retract+rejoin. Returns the count.
pub fn pgRemoveNode(set: []const GroupMember, node: []const u8, out: []GroupMember) usize {
    var n: usize = 0;
    for (set) |m| {
        if (!std.mem.eql(u8, m.node, node)) {
            out[n] = m;
            n += 1;
        }
    }
    return n;
}

/// The members of `group` visible in `set` — the `get_members/1` observable —
/// appended into `out`. Order-independent (a set projection).
pub fn pgMembersOf(set: []const GroupMember, group: []const u8, out: []GroupMember) usize {
    var n: usize = 0;
    for (set) |m| {
        if (std.mem.eql(u8, m.group, group)) {
            out[n] = m;
            n += 1;
        }
    }
    return n;
}

/// A global name binding: a registered `name` owned by a pid whose observable
/// identity is (node, number). The single-owner consistency law ranges over sets
/// of these.
pub const GlobalName = struct {
    name: []const u8,
    node: []const u8,
    num: u64,
};

/// The TOTAL ORDER on owner identity the resolve uses to break a name clash:
/// node lexicographic, then number. Returns true iff `a` should WIN over `b`
/// (the surviving owner). Total + antisymmetric ⇒ a clash resolves to exactly
/// ONE owner, the SAME one regardless of argument order (the order-independence
/// the both-nodes consistency needs). Real global's default resolver kills one
/// clashing registration; the INVARIANT it preserves is exactly at-most-one-owner.
pub fn ownerWins(a: GlobalName, b: GlobalName) bool {
    return switch (std.mem.order(u8, a.node, b.node)) {
        .lt => true,
        .gt => false,
        .eq => a.num < b.num,
    };
}

/// Resolve two partitions' name tables into ONE consistent table (append into
/// `out`). Every emitted name is UNIQUE (at-most-one-owner-both-nodes): a name
/// bound in only one partition is preserved with its owner; a name bound in BOTH
/// (a clash) keeps exactly the `ownerWins` owner. The pure payoff of the locker
/// exchange/resolved phase. Returns the count written.
pub fn resolveGlobalNames(a: []const GlobalName, b: []const GlobalName, out: []GlobalName) usize {
    var n: usize = 0;
    // Seed with `a`, then fold `b`: on a name already present keep the winner.
    for (a) |x| {
        out[n] = x;
        n += 1;
    }
    for (b) |y| {
        var clashed = false;
        for (out[0..n]) |*slot| {
            if (std.mem.eql(u8, slot.name, y.name)) {
                clashed = true;
                if (ownerWins(y, slot.*)) slot.* = y;
                break;
            }
        }
        if (!clashed) {
            out[n] = y;
            n += 1;
        }
    }
    return n;
}

/// The owner of `name` in a resolved table, or `null` if unbound — the
/// `global:whereis_name/1` observable over the pure core.
pub fn globalWhereis(table: []const GlobalName, name: []const u8) ?GlobalName {
    for (table) |x| if (std.mem.eql(u8, x.name, name)) return x;
    return null;
}

// ---------------------------------------------------------------------------
// E21 Task 4 (DIVERGENCE 320 → LIVE): the `$gen_call` over dist and the 2-phase
// global REGISTER transaction. E20-t2 landed the resolve-core + at-most-one-owner
// law but deferred the LIVE single-owner-visible-from-both transaction because it
// needs `set_lock` as a `gen_server:call` OVER DIST — the alias/monitor
// `$gen_call` request-reply. This block drives that transaction against the
// pinned peer for the UNCONTENDED single-name case:
//   1. `set_lock`  $gen_call {set_lock, {global, Requester}} → peer replies true
//      (the global lock is granted to us on the peer — `handle_set_lock`).
//   2. `register`  $gen_call {register, Name, Pid, Method}   → peer replies yes
//      (the peer INSERTS Name→Pid via `ins_name`, so `global:whereis_name(Name)`
//      on the PEER resolves the single owner on OUR node — peer-visible).
//   3. `del_lock`  $gen_call {del_lock, {global, Requester}} → peer replies true
//      (release; `trans_all_known`'s `after delete_global_lock`).
// Each call is a REG_SEND to the peer's `global_name_server` carrying
// `{'$gen_call', {FromPid, [alias|Ref]}, Request}`; the peer's `gen:reply` routes
// `{[alias|Ref], Reply}` back to OUR alias. Single-owner consistency is OBSERVED
// on the real peer: the name is visible AND a competing `global:register_name`
// on the peer returns `no` (the name is already owned). The FULL 2-phase
// `the_locker` nodeup name-table MERGE, boss-ordered multi-node lock acquisition,
// and concurrent-locker deadlock avoidance stay a NAMED residual (DIVERGENCE 470,
// reserved 470–479) — never sent partial (no locker corruption).
// ---------------------------------------------------------------------------

/// DOP for a reply delivered to a process ALIAS (an external reference used as a
/// send target). A `gen_server` reply to a REMOTE alias travels as `ALIAS_SEND`
/// (33) — or, when `DFLAG_ALTACT_SIG` is negotiated, as `ALTACT_SIG_SEND` (37).
/// `globalCallFlags` clears ALTACT_SIG so the pinned peer uses the simple 33.
pub const DOP_ALIAS_SEND: i64 = 33;
pub const DOP_ALIAS_SEND_TT: i64 = 34;
pub const DOP_ALTACT_SIG_SEND: i64 = 37;

const otp30_dflag_altact_sig: i64 = @as(i64, 0x20) << 32;

/// The DFLAG set for the global-locker carrier: `signalsFlags()` with ALTACT_SIG
/// CLEARED, so the peer replies to our alias via the deterministic `ALIAS_SEND`
/// (33) frame rather than `ALTACT_SIG_SEND` (37). ALTACT_SIG is a HOPEFUL (non
/// -mandatory) OTP-30 flag, so clearing it still leaves every mandatory flag set
/// and the pinned peer admits the handshake.
pub fn globalCallFlags() u64 {
    return signalsFlags() & ~@as(u64, @bitCast(otp30_dflag_altact_sig));
}

/// Build the `$gen_call` request envelope a `gen_server:call` sends over dist:
/// `{'$gen_call', {FromPid, [alias|AliasRef]}, Request}`. `AliasRef` is a fresh
/// reference minted on OUR node and used as a process alias; the peer's
/// `gen:reply` sends `{[alias|AliasRef], Reply}` to it. `[alias|AliasRef]` is the
/// IMPROPER cons (atom head, ref tail). Term lives in `ctx`.
pub fn genCall(
    ctx: *FinalTerms.Ctx,
    from_pid: FinalTerms.Term,
    alias_ref: FinalTerms.Term,
    request: FinalTerms.Term,
) !FinalTerms.Term {
    const alias_atom = FinalTerms.atom(ctx, try ctx.atoms.intern("alias"));
    const alias_tag = try FinalTerms.cons(ctx, alias_atom, alias_ref);
    const from = try FinalTerms.tuple(ctx, &.{ from_pid, alias_tag });
    return FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern("$gen_call")),
        from,
        request,
    });
}

/// The global lock resource id `{global, RequesterPid}` — resource `global` (the
/// `?GLOBAL_RID` `trans_all_known` uses), requester a pid on OUR node. set_lock/
/// del_lock range over THIS id. Term lives in `ctx`.
fn globalLockId(ctx: *FinalTerms.Ctx, requester_pid: FinalTerms.Term) !FinalTerms.Term {
    return FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern("global")),
        requester_pid,
    });
}

/// `{set_lock, {global, Requester}}` — the request `set_lock_on_nodes` gen_calls
/// to each node's `global_name_server`; the peer replies `true` when the global
/// lock is granted (uncontended resource) or `false` when held by another
/// requester (`handle_set_lock`/`can_set_lock`). Term lives in `ctx`.
pub fn globalSetLockReq(ctx: *FinalTerms.Ctx, requester_pid: FinalTerms.Term) !FinalTerms.Term {
    return FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern("set_lock")),
        try globalLockId(ctx, requester_pid),
    });
}

/// `{del_lock, {global, Requester}}` — release of `globalSetLockReq`; the peer
/// replies `true` (`handle_del_lock`). Term lives in `ctx`.
pub fn globalDelLockReq(ctx: *FinalTerms.Ctx, requester_pid: FinalTerms.Term) !FinalTerms.Term {
    return FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern("del_lock")),
        try globalLockId(ctx, requester_pid),
    });
}

/// `{register, Name, Pid, Method}` — the request `register_name/2`'s transaction
/// fun gen_calls to every known node; the peer INSERTS Name→Pid into its global
/// name table (`ins_name`) and replies `yes`. `Method` is the external resolver
/// fun `fun global:random_exit_name/3` (EXPORT_EXT) — the peer stores it and only
/// invokes it on a later clash, so it is never called in the uncontended path.
/// Term lives in `ctx`.
pub fn globalRegisterReq(
    ctx: *FinalTerms.Ctx,
    name: []const u8,
    pid: FinalTerms.Term,
) !FinalTerms.Term {
    const method = try FinalTerms.makeExportFun(
        ctx,
        FinalTerms.atom(ctx, try ctx.atoms.intern("global")),
        FinalTerms.atom(ctx, try ctx.atoms.intern("random_exit_name")),
        3,
    );
    return FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern("register")),
        FinalTerms.atom(ctx, try ctx.atoms.intern(name)),
        pid,
        method,
    });
}

/// The reply to our `$gen_call`: `gen:reply` to our alias arrives as an
/// `ALIAS_SEND` (33/34) or `ALTACT_SIG_SEND` (37) whose trailing message is
/// `{[alias|AliasRef], Reply}`. Return `Reply` IFF the tag's alias reference is
/// EXACTLY the one we minted (`eqlExact`) — a reply routed to a foreign alias, a
/// non-alias op, or a malformed tag yields `null`. A fabricated lock-grant is
/// unrepresentable: the acquire is admitted ONLY for the reply to OUR request.
/// Returned term lives in `ctx` (decoded off the live carrier).
pub fn matchAliasReply(
    ctx: *FinalTerms.Ctx,
    ic: InboundControl,
    our_alias_ref: FinalTerms.Term,
) ?FinalTerms.Term {
    if (ic.op != DOP_ALIAS_SEND and ic.op != DOP_ALIAS_SEND_TT and ic.op != DOP_ALTACT_SIG_SEND) return null;
    const msg = ic.msg orelse return null;
    if (FinalTerms.kindOf(ctx, msg) != .tuple) return null;
    if (FinalTerms.tupleArity(ctx, msg) < 2) return null;
    const tag = FinalTerms.tupleElem(ctx, msg, 0);
    if (FinalTerms.kindOf(ctx, tag) != .cons) return null;
    const head = FinalTerms.listHead(ctx, tag);
    if (!FinalTerms.repIsAtom(head)) return null;
    if (!std.mem.eql(u8, ctx.atoms.nameOf(FinalTerms.atomIdxOf(head)), "alias")) return null;
    const tail = FinalTerms.listTail(ctx, tag);
    if (!FinalTerms.repIsRef(ctx, tail)) return null;
    if (!FinalTerms.eqlExact(ctx, tail, our_alias_ref)) return null;
    return FinalTerms.tupleElem(ctx, msg, 1);
}

/// True iff `reply` is the atom `atom_name` — the shape check for a `$gen_call`
/// reply (`true`/`yes`/`false`/`no`). A non-atom or a different atom is false.
pub fn replyIsAtom(ctx: *FinalTerms.Ctx, reply: FinalTerms.Term, atom_name: []const u8) bool {
    if (!FinalTerms.repIsAtom(reply)) return false;
    return std.mem.eql(u8, ctx.atoms.nameOf(FinalTerms.atomIdxOf(reply)), atom_name);
}

/// Build the pg `local_data` reply a v1 scope casts back on `discover`:
/// `{'$gen_cast', {local_data, OurScopePid, 1, #{Group => [Member]}}}`. Sending
/// THIS to the peer's scope pid makes the pinned peer MERGE our member into its
/// global view (`data_publisher` handle for `{local_data,...}`), so
/// `pg:get_members(Group)` on the PEER converges to include `member` — the
/// membership-convergence observable (DIVERGENCE 321). Term lives in `ctx`.
pub fn pgLocalDataCast(
    ctx: *FinalTerms.Ctx,
    our_scope_pid: FinalTerms.Term,
    group: []const u8,
    member: FinalTerms.Term,
) !FinalTerms.Term {
    const group_atom = FinalTerms.atom(ctx, try ctx.atoms.intern(group));
    const member_list = try FinalTerms.cons(ctx, member, FinalTerms.nil(ctx));
    const ld_map = try FinalTerms.mapNew(ctx, &.{group_atom}, &.{member_list});
    const inner = try FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern("local_data")),
        our_scope_pid,
        FinalTerms.int(ctx, 1), // data_publisher version() = 1 (OTP-30)
        ld_map,
    });
    return FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern("$gen_cast")),
        inner,
    });
}

/// Build the pg `discover` a v1 scope sends back to a peer scope pid:
/// `{discover, OurScopePid, 1}` — the symmetric half of the membership handshake
/// (so OUR view would converge too). Term lives in `ctx`.
pub fn pgDiscoverMsg(ctx: *FinalTerms.Ctx, our_scope_pid: FinalTerms.Term) !FinalTerms.Term {
    return FinalTerms.tuple(ctx, &.{
        FinalTerms.atom(ctx, try ctx.atoms.intern("discover")),
        our_scope_pid,
        FinalTerms.int(ctx, 1),
    });
}

/// A `net_kernel:monitor_nodes` lifecycle event for a monitored node.
pub const NodeEvent = enum { up, down };

/// The verdict of folding a monitored node's event stream. `net_kernel` promises
/// a monitored node goes UP exactly once, then DOWN exactly once, in that order:
/// any other sequence (down-before-up, a repeated up/down, an empty stream) is a
/// lifecycle violation. The live driver observes the REAL peer's event stream
/// and requires exactly `.down_after_up` (a completed single lifecycle).
pub const NodeLifecycle = enum { none, up_only, down_after_up, invalid };

/// Fold a monitored node's event stream into its lifecycle verdict (the pure
/// core of the net_kernel monitor-nodes ordering law). A single `.up` → `.up_only`
/// (still connected); `.up` then `.down` → `.down_after_up` (a clean lifecycle);
/// anything else → `.invalid` or `.none`.
pub fn foldNodeLifecycle(events: []const NodeEvent) NodeLifecycle {
    var state: NodeLifecycle = .none;
    for (events) |e| {
        state = switch (state) {
            .none => switch (e) {
                .up => .up_only,
                .down => .invalid, // down before up
            },
            .up_only => switch (e) {
                .up => .invalid, // repeated up
                .down => .down_after_up,
            },
            .down_after_up => .invalid, // any event after the clean lifecycle
            .invalid => .invalid,
        };
    }
    return state;
}

/// E18.3: drive the full v6 handshake as the connecting node against a live
/// pinned OTP-30 acceptor and return the CONNECTED carrier with its socket still
/// open (no hold, no close). Returns the open `LiveCarrier` on a verified ack,
/// or a NAMED error with the socket already closed (no partial state escapes —
/// the errdefer tears the fd down on every reject path).
pub fn liveConnectOpen(gpa: std.mem.Allocator, cfg: ConnectConfig, rng: std.Random) !LiveCarrier {
    const at = std.mem.indexOfScalar(u8, cfg.peer_node, '@') orelse return error.BadNodeName;
    const prefix = cfg.peer_node[0..at];
    const peer_port = try epmdPortPlease(gpa, prefix, cfg.epmd_port);

    const carrier = try tcpConnectLoopbackPort(peer_port);
    errdefer carrier.close();
    try setRecvTimeout(carrier.fd, cfg.read_timeout_ms);

    // send_name (v6, published + OTP-30 required DFLAGs, or the caller's
    // signals-carrier override that clears atom-cache/fragments).
    const flags: u64 = cfg.flags_override orelse @as(u64, @bitCast(otp30_dflags_required | otp30_dflag_published));
    const sn = try V6.encodeSendName(gpa, flags, cfg.creation, cfg.our_node);
    defer gpa.free(sn);
    try carrier.writePacket2Frame(gpa, sn);

    // recv_status
    const st_frame = try carrier.readPacket2FrameAlloc(gpa, 512);
    defer gpa.free(st_frame);
    switch (try V6.parseStatus(st_frame)) {
        .ok, .ok_simultaneous => {},
        .nok => return error.StatusNok,
        .not_allowed => return error.StatusNotAllowed,
        .alive => return error.StatusAlive,
        .other => return error.BadStatus,
    }

    // recv_challenge
    const ch_frame = try carrier.readPacket2FrameAlloc(gpa, 1024);
    defer gpa.free(ch_frame);
    const ch = try V6.parseChallenge(ch_frame);

    // challenge_reply: our fresh challenge + gen_digest(peer_challenge, cookie)
    const our_challenge = rng.int(u32);
    const reply = V6.encodeChallengeReply(our_challenge, genDigest(cfg.cookie, ch.challenge));
    try carrier.writePacket2Frame(gpa, &reply);

    // recv_challenge_ack: must equal gen_digest(our_challenge, cookie)
    const ack_frame = try carrier.readPacket2FrameAlloc(gpa, 64);
    defer gpa.free(ack_frame);
    const ack = try V6.decodeChallengeAck(ack_frame);
    const expect = genDigest(cfg.cookie, our_challenge);
    if (!std.mem.eql(u8, &expect, &ack)) return error.BadAck;

    // CONNECTED. Framing is now packet-4; the socket is OPEN and owned by the
    // returned value.
    return .{
        .carrier = carrier,
        .outcome = .{
            .peer_port = peer_port,
            .our_challenge = our_challenge,
            .peer_challenge = ch.challenge,
            .peer_creation = ch.creation,
            .peer_flags = ch.flags,
        },
    };
}

/// Drive the full v6 handshake as the connecting node against a live pinned
/// OTP-30 acceptor, then hold the connection so the peer observes zigvm in
/// `nodes(connected)`. Returns the negotiated outcome on a verified ack, or a
/// named error (no persistent state is ever created here). FORWARD direction
/// (t1b): a thin wrapper over `liveConnectOpen` + a bounded tick hold + close.
pub fn liveConnect(gpa: std.mem.Allocator, cfg: ConnectConfig, rng: std.Random) !ConnectOutcome {
    var lc = try liveConnectOpen(gpa, cfg, rng);
    defer lc.close();
    lc.holdTicks(gpa, cfg.hold_iters);
    return lc.outcome;
}

/// Post-connect: keep the (now packet-4) connection alive for a bounded number
/// of ~200ms slices, echoing a distribution TICK (empty packet-4 frame) if the
/// peer sends one. Any read timeout just advances the slice; a peer close ends
/// the hold early (the peer already observed us — success).
fn holdAnsweringTicks(gpa: std.mem.Allocator, carrier: *const TcpStreamCarrier, iters: u32) void {
    setRecvTimeout(carrier.fd, 200) catch return;
    var i: u32 = 0;
    while (i < iters) : (i += 1) {
        const frame = carrier.readPacket4FrameAlloc(gpa, 65536) catch |e| switch (e) {
            error.TcpTimeout => continue,
            else => return, // closed / torn — done holding
        };
        defer gpa.free(frame);
        if (frame.len == 0) {
            const tick = [_]u8{ 0, 0, 0, 0 };
            carrier.writeBytes(&tick) catch return;
        }
    }
}

/// E20 Task 3 (DIVERGENCE 322, multi-node): bounded tick keepalive over MANY
/// live carriers at once, so zigvm can hold a 3-node topology (peer A + peer B)
/// simultaneously without either peer's net_kernel dropping zigvm for a missed
/// tick. Each ~200ms slice reads one frame from EVERY carrier, echoing a TICK on
/// an empty keepalive frame and draining (ignoring) any data frame. A carrier
/// whose fd is negative is treated as torn (skipped) so a partition-heal driver
/// can null out a dropped peer. Every read is SO_RCVTIMEO-bounded, so a silent
/// peer never hangs (the multi-carrier-tick-keepalive-bounded law). Total wall
/// time ≤ iters * carriers.len * 200ms.
pub fn holdCarriersTicks(gpa: std.mem.Allocator, carriers: []const TcpStreamCarrier, iters: u32) void {
    for (carriers) |c| {
        if (c.fd >= 0) setRecvTimeout(c.fd, 200) catch {};
    }
    var i: u32 = 0;
    while (i < iters) : (i += 1) {
        for (carriers) |c| {
            if (c.fd < 0) continue;
            const frame = c.readPacket4FrameAlloc(gpa, 65536) catch |e| switch (e) {
                error.TcpTimeout => continue,
                else => continue, // this carrier torn — keep holding the others
            };
            defer gpa.free(frame);
            if (frame.len == 0) {
                const tick = [_]u8{ 0, 0, 0, 0 };
                c.writeBytes(&tick) catch {};
            }
        }
    }
}

// ===========================================================================
// E21 Task 5 — Inbound distribution ACCEPTOR (DIVERGENCE 440 discharge).
//
// Every E18/E20 dist slice had zigvm DIAL OUT (`liveConnectOpen`). This section
// is the MIRROR: zigvm as a SYMMETRIC node a real OTP-30 peer can DIAL IN to.
// Two new pieces compose with the finished v6 codec + `genDigest`/`HsAuth`:
//   (1) an epmd ALIVE2 registration (`epmd_bridge.zig` codec + `epmdAlive2Register`
//       socket glue) so epmd advertises zigvm's dist port and a peer can look it
//       up, plus a bound listening socket;
//   (2) the distribution ACCEPTOR side of the v6 handshake — the exact reverse of
//       `liveConnectOpen`'s initiator (`dist_util.erl handshake_other_started`):
//         recv send_name('N') → send send_status('sok') → send send_challenge('N',
//         OUR flags/challenge/creation/name) → recv challenge_reply('r') → VERIFY
//         the peer's digest == genDigest(cookie, OUR challenge) → send
//         challenge_ack('a', genDigest(cookie, PEER challenge)) ⇒ connected.
//
// `AcceptAuth` is the pure acceptor auth state machine (the reject-atomic mirror
// of `HsAuth`): a bad reply digest ⇒ `.rejected`, NO peer identity recorded.
//
// Laws:
//   ACCEPTOR-HANDSHAKE-ROUND-TRIP  the full framed exchange between a peer that
//                                  shares the cookie and this acceptor round-trips
//                                  through the v6 codec and reaches `.connected`
//                                  with the peer identity bound.
//   ACCEPTOR-REJECT-ATOMICITY      a peer authenticating under the WRONG cookie
//                                  fails digest verification ⇒ `.rejected`, peer
//                                  identity == null (no partial connected state).
//   EPMD-ALIVE2-REGISTER           (in `epmd_bridge.zig`) the ALIVE2_REQ we send
//                                  is exactly the one epmd will parse.
// The full live flow (a real pinned OTP-30 peer `net_adm:ping`s zigvm and its
// `nodes/0` shows zigvm from a connection zigvm ACCEPTED) is proven against the
// pinned oracle by the harness `--run-dist-handshake` `drive_accept` driver.
//
// Boundedness: the listening `accept()` is SO_RCVTIMEO-bounded and looped a fixed
// number of slices, and every handshake read is SO_RCVTIMEO-bounded — a silent /
// absent peer returns a NAMED error, never a hang (a stuck accept is a failed
// law, not a stuck suite).

const epmd_bridge = @import("epmd_bridge.zig");

/// The pure acceptor-side auth state machine — the reject-atomic mirror of
/// `HsAuth`. We minted OUR challenge and sent it in `send_challenge`; the peer
/// replied with (its challenge, digest-of-our-challenge). `peer_node` is bound
/// ONLY on a verified reply, so ACCEPTOR-REJECT-ATOMICITY can observe that a
/// failed auth leaves no partial peer identity.
pub const AcceptAuth = struct {
    cookie: []const u8,
    our_challenge: u32,
    state: AuthState = .awaiting_ack, // awaiting the peer's challenge_reply
    peer_node: ?[]const u8 = null,

    pub fn init(cookie: []const u8, our_challenge: u32) AcceptAuth {
        return .{ .cookie = cookie, .our_challenge = our_challenge };
    }

    /// Verify the peer's challenge_reply. On success bind the peer identity,
    /// become `.connected`, and return the challenge_ack digest to send back
    /// (`genDigest(cookie, PEER challenge)`). On ANY digest mismatch go
    /// `.rejected`, record NOTHING, and return null (atomic reject).
    pub fn verifyReply(self: *AcceptAuth, reply: V6.Reply, peer_node: []const u8) ?[16]u8 {
        const expect = genDigest(self.cookie, self.our_challenge);
        if (!std.mem.eql(u8, &expect, &reply.digest)) {
            self.state = .rejected;
            self.peer_node = null;
            return null;
        }
        self.state = .connected;
        self.peer_node = peer_node;
        return genDigest(self.cookie, reply.challenge);
    }
};

pub const AcceptConfig = struct {
    our_node: []const u8, // "zigvm@127.0.0.1"
    cookie: []const u8,
    epmd_port: u16 = 4369,
    creation: u32 = 1,
    read_timeout_ms: u32 = 5000, // per handshake read
    accept_timeout_ms: u32 = 200, // per accept() poll slice
    accept_iters: u32 = 150, // bounded accept loop (~150 * 200ms = 30s)
    hold_iters: u32 = 12, // post-connect tick hold
    flags_override: ?u64 = null,
};

/// A bound distribution acceptor: a listening socket plus the HELD-OPEN epmd
/// registration connection (epmd unregisters the node the instant this fd
/// closes). Stratum-C ownership; the caller MUST `close()` it.
pub const AcceptListener = struct {
    listen_fd: i32,
    epmd_fd: i32,
    port: u16,

    pub fn close(self: *const AcceptListener) void {
        _ = std.os.linux.close(self.listen_fd);
        _ = std.os.linux.close(self.epmd_fd);
    }
};

/// Bind a loopback listening socket (OS-chosen port), register that port with
/// the local epmd under `node_prefix` via ALIVE2_REQ, and KEEP the epmd
/// connection open (returned in the listener) so the registration persists. A
/// non-zero ALIVE2 result (name already taken) is a NAMED error. Stratum-C I/O.
pub fn openAcceptListener(gpa: std.mem.Allocator, node_prefix: []const u8, epmd_port: u16, creation: u32) !AcceptListener {
    _ = creation;
    // Listening socket on 127.0.0.1:0 → OS picks a free port.
    const listen_fd = try tcpSocket();
    errdefer _ = std.os.linux.close(listen_fd);
    var bind_addr = loopbackAddr(0);
    try tcpBind(listen_fd, &bind_addr);
    try tcpListen(listen_fd);
    var actual: std.os.linux.sockaddr.in = undefined;
    try tcpSockName(listen_fd, &actual);
    const dist_port = std.mem.bigToNative(u16, actual.port);

    // Register that port with epmd; hold the connection open.
    const epmd = try tcpConnectLoopbackPort(epmd_port);
    errdefer epmd.close();
    const body = try epmd_bridge.encodeAlive2Req(gpa, .{ .port = dist_port, .name = node_prefix });
    defer gpa.free(body);
    try epmd.writePacket2Frame(gpa, body);
    // The ALIVE2 reply is NOT packet-framed: it is a bare 4-byte ('y') or 6-byte
    // ('v') response. Read the tag, then the shape-determined remainder.
    var tag: [1]u8 = undefined;
    try epmd.readExact(&tag);
    const rest_len: usize = switch (tag[0]) {
        epmd_bridge.ALIVE2_RESP => 3,
        epmd_bridge.ALIVE2_X_RESP => 5,
        else => return error.EpmdBadResp,
    };
    const rest = try epmd.readExactAlloc(gpa, rest_len);
    defer gpa.free(rest);
    var full: [6]u8 = undefined;
    full[0] = tag[0];
    @memcpy(full[1 .. 1 + rest_len], rest);
    const resp = epmd_bridge.decodeAlive2Resp(full[0 .. 1 + rest_len]) catch return error.EpmdBadResp;
    if (resp.result != 0) return error.EpmdAliveTaken;

    return .{ .listen_fd = listen_fd, .epmd_fd = epmd.fd, .port = dist_port };
}

/// Drive the v6 handshake as the ACCEPTING node against a peer that has DIALED
/// IN over `conn`, returning the CONNECTED carrier with the socket still open
/// (framing now packet-4). A rejected handshake returns a NAMED error with the
/// connection already closed (no partial state escapes). The peer's node name
/// is copied into `peer_name_out` (caller-owned buffer of ≥ MAXHOSTNAMELEN).
pub fn acceptHandshake(
    gpa: std.mem.Allocator,
    conn: TcpStreamCarrier,
    cfg: AcceptConfig,
    our_challenge: u32,
    peer_name_out: *std.ArrayList(u8),
) !LiveCarrier {
    errdefer conn.close();
    try setRecvTimeout(conn.fd, cfg.read_timeout_ms);

    // recv send_name (the initiator's 'N' frame).
    const name_frame = try conn.readPacket2FrameAlloc(gpa, 1024);
    defer gpa.free(name_frame);
    const sn = try V6.decodeSendName(name_frame);
    const peer_flags = sn.flags;
    const peer_creation = sn.creation;
    // Admit only a peer carrying the mandatory OTP-30 DFLAG set. A non-mandatory
    // peer is refused with 'snok' (NAMED reject; no connected state).
    if (!mandatoryDFlagsAdmitted(@bitCast(peer_flags))) {
        conn.writePacket2Frame(gpa, V6.status_nok) catch {};
        return error.StatusNok;
    }
    try peer_name_out.appendSlice(gpa, sn.name);

    // send send_status('sok').
    try conn.writePacket2Frame(gpa, V6.status_ok);

    // send send_challenge: OUR flags/challenge/creation/name.
    const flags: u64 = cfg.flags_override orelse @as(u64, @bitCast(otp30_dflags_required | otp30_dflag_published));
    const ch = try V6.encodeChallenge(gpa, flags, our_challenge, cfg.creation, cfg.our_node);
    defer gpa.free(ch);
    try conn.writePacket2Frame(gpa, ch);

    // recv challenge_reply and verify the peer's digest for OUR challenge.
    const reply_frame = try conn.readPacket2FrameAlloc(gpa, 64);
    defer gpa.free(reply_frame);
    const reply = try V6.decodeChallengeReply(reply_frame);
    var auth = AcceptAuth.init(cfg.cookie, our_challenge);
    const ack_digest = auth.verifyReply(reply, peer_name_out.items) orelse return error.BadReply;

    // send challenge_ack ⇒ connected.
    const ack = V6.encodeChallengeAck(ack_digest);
    try conn.writePacket2Frame(gpa, &ack);

    return .{
        .carrier = conn,
        .outcome = .{
            .peer_port = 0, // the peer dialed us; we hold no epmd port for it
            .our_challenge = our_challenge,
            .peer_challenge = reply.challenge,
            .peer_creation = peer_creation,
            .peer_flags = peer_flags,
        },
    };
}

/// Full inbound-acceptor flow: register with epmd + listen, then bounded-accept
/// ONE inbound dial-in and run the acceptor handshake. Returns the connected
/// `LiveCarrier` (socket open) and, via `listener_out`, the held listener/epmd
/// registration so the caller can keep zigvm advertised while it holds ticks and
/// then tear both down. A silent/absent dialer returns `error.AcceptTimeout`
/// (bounded — never a hang). `peer_name_out` receives the peer's node name.
pub fn liveAcceptOpen(
    gpa: std.mem.Allocator,
    cfg: AcceptConfig,
    rng: std.Random,
    listener_out: *AcceptListener,
    peer_name_out: *std.ArrayList(u8),
) !LiveCarrier {
    const at = std.mem.indexOfScalar(u8, cfg.our_node, '@') orelse return error.BadNodeName;
    const prefix = cfg.our_node[0..at];
    const listener = try openAcceptListener(gpa, prefix, cfg.epmd_port, cfg.creation);
    errdefer listener.close();
    listener_out.* = listener;

    // Bounded accept: SO_RCVTIMEO makes a blocking accept() return EAGAIN after
    // the deadline, so an absent dialer never hangs the loop.
    try setRecvTimeout(listener.listen_fd, cfg.accept_timeout_ms);
    var i: u32 = 0;
    const conn_fd: i32 = while (i < cfg.accept_iters) : (i += 1) {
        // A blocking accept() with SO_RCVTIMEO returns EAGAIN after the deadline,
        // surfaced here as error.TcpAccept — an absent dialer never hangs the loop.
        const fd = tcpAccept(listener.listen_fd) catch continue;
        break fd;
    } else return error.AcceptTimeout;

    const conn = TcpStreamCarrier{ .fd = conn_fd };
    const our_challenge = rng.int(u32);
    return acceptHandshake(gpa, conn, cfg, our_challenge, peer_name_out);
}

// --- E21 Task 5 (inbound acceptor) laws --------------------------------------

test "LAW E21.5 ACCEPTOR-HANDSHAKE-ROUND-TRIP: a shared-cookie peer drives the acceptor to connected" {
    // The pure composition of the v6 codec (both directions) with the acceptor
    // auth: an initiating peer and this acceptor sharing a cookie complete the
    // framed exchange and BOTH reach connected, with the peer identity bound.
    var prng = std.Random.DefaultPrng.init(0x21E5_ACCE_9701_0001);
    const r = prng.random();
    var it: usize = 0;
    while (it < 256) : (it += 1) {
        const clen = r.intRangeAtMost(usize, 1, 16);
        var cbuf: [16]u8 = undefined;
        for (0..clen) |k| cbuf[k] = r.intRangeAtMost(u8, 'a', 'z');
        const cookie = cbuf[0..clen];
        const our_challenge = r.int(u32); // acceptor (zigvm) challenge
        const peer_challenge = r.int(u32); // initiator (peer) challenge

        // The peer, sharing the cookie, replies to OUR challenge with the digest
        // it computes; the reply also carries the peer's own challenge.
        const reply = V6.Reply{ .challenge = peer_challenge, .digest = genDigest(cookie, our_challenge) };
        var auth = AcceptAuth.init(cookie, our_challenge);
        const ack = auth.verifyReply(reply, "peer@host") orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(AuthState.connected, auth.state);
        try std.testing.expectEqualStrings("peer@host", auth.peer_node.?);
        // The ack we send is what the peer expects for ITS challenge, so the peer
        // (as initiator) verifies us and reaches connected too — mutual auth.
        try std.testing.expectEqual(genDigest(cookie, peer_challenge), ack);
    }
}

test "LAW E21.5 ACCEPTOR-REJECT-ATOMICITY: a wrong-cookie reply rejects with no partial peer identity" {
    var prng = std.Random.DefaultPrng.init(0x21E5_BAD0_C007_0001);
    const r = prng.random();
    var it: usize = 0;
    while (it < 256) : (it += 1) {
        const our_challenge = r.int(u32);
        const peer_challenge = r.int(u32);
        // Peer authenticated under "wrong"; acceptor cookie is "right".
        const reply = V6.Reply{ .challenge = peer_challenge, .digest = genDigest("wrong", our_challenge) };
        var auth = AcceptAuth.init("right", our_challenge);
        const ack = auth.verifyReply(reply, "peer@host");
        try std.testing.expect(ack == null);
        try std.testing.expectEqual(AuthState.rejected, auth.state);
        try std.testing.expect(auth.peer_node == null);
    }
}

test "LAW E21.5 ACCEPTOR framing: encodeChallenge is the exact inverse of parseChallenge" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0x21E5_F1A6_0000_0001);
    const r = prng.random();
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const flags = r.int(u64);
        const challenge = r.int(u32);
        const creation = r.int(u32);
        const nlen = r.intRangeAtMost(usize, 1, 40);
        var nbuf: [40]u8 = undefined;
        for (0..nlen) |k| nbuf[k] = r.intRangeAtMost(u8, 'a', 'z');
        const name = nbuf[0..nlen];
        const enc = try V6.encodeChallenge(gpa, flags, challenge, creation, name);
        defer gpa.free(enc);
        const dec = try V6.parseChallenge(enc);
        try std.testing.expectEqual(flags, dec.flags);
        try std.testing.expectEqual(challenge, dec.challenge);
        try std.testing.expectEqual(creation, dec.creation);
        try std.testing.expectEqualStrings(name, dec.name);
    }
    // Status frames the acceptor emits parse back to the right verdict.
    try std.testing.expectEqual(V6.Status.ok, try V6.parseStatus(V6.status_ok));
    try std.testing.expectEqual(V6.Status.nok, try V6.parseStatus(V6.status_nok));
}

test "LAW E21.5 ACCEPTOR live loopback: a scripted peer dials in and the handshake reaches connected over a real socket" {
    // A REAL loopback socket pair stands in for the peer's dial-in: end [1] plays
    // the initiator (send_name → recv status → recv challenge → reply → recv
    // ack), end [0] runs the acceptor handshake. This exercises the socket path
    // (bounded reads, packet-2 framing) without needing a booted OTP peer — the
    // live-vs-pinned-peer EQ is the harness `drive_accept` row.
    const gpa = std.testing.allocator;
    const cookie = "loopcookie";
    var pair = try openLoopbackTcpPair();
    // The acceptor takes ownership of pair[0] (closes it); we own pair[1].
    defer pair[1].close();
    try setRecvTimeout(pair[1].fd, 1000);

    // Drive the initiator end on the acceptor's behalf, interleaved: because the
    // handshake is request/response we script the peer inline via a thread-free
    // ping-pong. We pre-send send_name, then react after the acceptor replies.
    const peer_flags: u64 = @bitCast(otp30_dflags_required | otp30_dflag_published);
    const sn = try V6.encodeSendName(gpa, peer_flags, 7, "peerloop@127.0.0.1");
    defer gpa.free(sn);
    try pair[1].writePacket2Frame(gpa, sn);

    // Run the acceptor handshake against pair[0] in-line; it will read send_name,
    // reply sok + challenge, then block reading our challenge_reply — so we must
    // feed the reply. Do the acceptor read/writes and peer responses in lockstep
    // by running the acceptor to the point it needs the reply. Simplest: perform
    // the peer side fully first is impossible (needs the acceptor's challenge).
    // So we run the acceptor in a helper that yields after sending its challenge.
    // Here we inline the exact acceptor steps mirroring acceptHandshake to keep
    // the law single-threaded and deterministic.
    try setRecvTimeout(pair[0].fd, 1000);
    const name_frame = try pair[0].readPacket2FrameAlloc(gpa, 1024);
    defer gpa.free(name_frame);
    const dsn = try V6.decodeSendName(name_frame);
    try std.testing.expectEqualStrings("peerloop@127.0.0.1", dsn.name);
    try pair[0].writePacket2Frame(gpa, V6.status_ok);
    const our_challenge: u32 = 0x1234_5678;
    const chal = try V6.encodeChallenge(gpa, peer_flags, our_challenge, 1, "zigvmloop@127.0.0.1");
    defer gpa.free(chal);
    try pair[0].writePacket2Frame(gpa, chal);

    // Peer side: recv status, recv challenge, send reply.
    const st = try pair[1].readPacket2FrameAlloc(gpa, 64);
    defer gpa.free(st);
    try std.testing.expectEqual(V6.Status.ok, try V6.parseStatus(st));
    const cf = try pair[1].readPacket2FrameAlloc(gpa, 1024);
    defer gpa.free(cf);
    const pc = try V6.parseChallenge(cf);
    const peer_challenge: u32 = 0x0BAD_F00D;
    const reply = V6.encodeChallengeReply(peer_challenge, genDigest(cookie, pc.challenge));
    try pair[1].writePacket2Frame(gpa, &reply);

    // Acceptor: recv reply, verify, send ack.
    const rf = try pair[0].readPacket2FrameAlloc(gpa, 64);
    defer gpa.free(rf);
    const drep = try V6.decodeChallengeReply(rf);
    var auth = AcceptAuth.init(cookie, our_challenge);
    const ack_digest = auth.verifyReply(drep, dsn.name) orelse return error.TestUnexpectedResult;
    const ackf = V6.encodeChallengeAck(ack_digest);
    try pair[0].writePacket2Frame(gpa, &ackf);
    pair[0].close();

    // Peer verifies the ack for ITS challenge — connection established.
    const af = try pair[1].readPacket2FrameAlloc(gpa, 64);
    defer gpa.free(af);
    const adig = try V6.decodeChallengeAck(af);
    try std.testing.expectEqualSlices(u8, &genDigest(cookie, peer_challenge), &adig);
    try std.testing.expectEqual(AuthState.connected, auth.state);
}

// --- E18 Task 3 (distributed signals) laws -----------------------------------

test "LAW E18.3sig REG-SEND-ROUND-TRIP: decodePassThrough∘encodeRegSend recovers op=REG_SEND, the target name, and the message denotation" {
    // The final DOP encoding of a remote registered-send must decode back to the
    // same control op, the same target name, and a message that denotes exactly
    // what was sent — the algebraic core the LIVE inbound/outbound signal paths
    // depend on. Twin-seeded over generated message terms (seed echoed below).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();
    const seed: u64 = 0x18E3_51_9A_10DE_0001;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const our_node = try atoms.intern("zigvmnode@127.0.0.1");
    const names = [_][]const u8{ "shell", "collector", "rex", "a", "reg_name_42" };
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const name = names[i % names.len];
        const msg = try etf.genWireTerm(r, &ctx, 3);
        const before = try FinalTerms.denote(&ctx, sa, msg);
        const from_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);
        const to_atom = FinalTerms.atom(&ctx, try atoms.intern(name));
        const frame = try encodeRegSend(gpa, &ctx, from_pid, to_atom, msg);
        defer gpa.free(frame);
        // PASS_THROUGH prefix (byte 112) — the live-carrier control framing.
        try std.testing.expectEqual(DIST_PASS_THROUGH, frame[0]);
        const ic = try decodePassThrough(gpa, &ctx, frame);
        try std.testing.expectEqual(DOP_REG_SEND, ic.op);
        const recovered = regSendName(&ctx, ic.ctrl) orelse return error.NoName;
        try std.testing.expectEqualStrings(name, atoms.nameOf(recovered));
        try std.testing.expect(ic.msg != null);
        try std.testing.expect(spec.eqlExact(before, try FinalTerms.denote(&ctx, sa, ic.msg.?)));
    }
}

test "LAW E18.3sig SIGNALS-FLAGS: the signals carrier clears atom-cache+fragments but keeps every mandatory OTP-30 flag (peer still admits us)" {
    // A signals carrier must strip DIST_HDR_ATOM_CACHE and FRAGMENTS (so the
    // peer emits PASS_THROUGH) WITHOUT dropping any mandatory flag (else the peer
    // rejects the handshake). This pins that boundary — mutating signalsFlags to
    // keep the atom cache, or to drop a mandatory flag, fails this law.
    const sf: i64 = @bitCast(signalsFlags());
    try std.testing.expectEqual(@as(i64, 0), sf & otp30_dflag_dist_hdr_atom_cache);
    try std.testing.expectEqual(@as(i64, 0), sf & otp30_dflag_fragments);
    // every mandatory flag is still advertised → mandatoryDFlagsAdmitted holds.
    try std.testing.expect(mandatoryDFlagsAdmitted(sf));
    try std.testing.expectEqual(otp30_dflags_mandatory, sf & otp30_dflags_mandatory);
}

test "LAW E18.3b MONITOR-P-ROUND-TRIP: decodePassThrough∘encodeMonitorP recovers op=MONITOR_P, the target name, and the ref identity" {
    // The final DOP encoding of a remote monitor must decode back to the same
    // control op (19), the same registered-name target, and a ref that is
    // EXACTLY the reference we minted (node atom + creation + id words) — the
    // ref-identity the MONITOR_P_EXIT reply is later matched against. Twin-
    // seeded over generated names/ref-ids (seed echoed below).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const seed: u64 = 0x18E3_B_10DE_0002;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const our_node = try atoms.intern("zigvmmon@127.0.0.1");
    const names = [_][]const u8{ "ghost", "keeper", "rex", "a", "victim_9" };
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const name = names[i % names.len];
        const ref_id = r.int(u32);
        const from_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);
        const target = FinalTerms.atom(&ctx, try atoms.intern(name));
        const ref = try FinalTerms.refExt(&ctx, .{ ref_id, 0, 0 }, our_node, 3);
        const frame = try encodeMonitorP(gpa, &ctx, from_pid, target, ref);
        defer gpa.free(frame);
        try std.testing.expectEqual(DIST_PASS_THROUGH, frame[0]);
        const ic = try decodePassThrough(gpa, &ctx, frame);
        try std.testing.expectEqual(DOP_MONITOR_P, ic.op);
        try std.testing.expect(ic.msg == null); // control-only: no trailing payload
        const rec_target = FinalTerms.tupleElem(&ctx, ic.ctrl, 2);
        try std.testing.expect(FinalTerms.repIsAtom(rec_target));
        try std.testing.expectEqualStrings(name, atoms.nameOf(FinalTerms.atomIdxOf(rec_target)));
        const rec_ref = FinalTerms.tupleElem(&ctx, ic.ctrl, 3);
        try std.testing.expect(FinalTerms.eqlExact(&ctx, rec_ref, ref));
    }
}

test "LAW E18.3b MONITOR-FIRES-EXACTLY-ONCE: matchMonitorExit yields the wire reason ONLY for our exact ref, never for a foreign ref or a non-exit op" {
    // A remote 'DOWN' must fire iff the peer's MONITOR_P_EXIT carries the exact
    // ref we monitored with — a mis-delivered/fabricated signal is unrepresent-
    // able. We synthesize the frame the peer WOULD send (same PASS_THROUGH codec)
    // and prove: our ref → the wire reason; a different ref → null; a non-exit
    // op (LINK) with our ref → null.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const our_node = try atoms.intern("zigvmmon@127.0.0.1");
    const noproc = FinalTerms.atom(&ctx, try atoms.intern("noproc"));
    const our_ref = try FinalTerms.refExt(&ctx, .{ 0xCAFE, 0, 0 }, our_node, 3);
    const other_ref = try FinalTerms.refExt(&ctx, .{ 0xBEEF, 0, 0 }, our_node, 3);
    const peer_pid = try FinalTerms.pidExt(&ctx, 7, 0, our_node, 3);
    const my_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);

    // The peer's MONITOR_P_EXIT {21, FromProc, ToPid, Ref, Reason} for OUR ref.
    const exit_ctrl = try FinalTerms.tuple(&ctx, &.{
        FinalTerms.int(&ctx, DOP_MONITOR_P_EXIT), peer_pid, my_pid, our_ref, noproc,
    });
    const exit_frame = try encodePassThroughCtrl(gpa, &ctx, exit_ctrl);
    defer gpa.free(exit_frame);
    const ic = try decodePassThrough(gpa, &ctx, exit_frame);
    try std.testing.expectEqual(DOP_MONITOR_P_EXIT, ic.op);
    // our ref → the wire reason (noproc), and it is exactly `noproc`.
    const got = matchMonitorExit(&ctx, ic, our_ref) orelse return error.NoDown;
    try std.testing.expect(FinalTerms.eqlExact(&ctx, got, noproc));
    // a FOREIGN ref → no 'DOWN' (never fabricated).
    try std.testing.expect(matchMonitorExit(&ctx, ic, other_ref) == null);

    // a LINK control message with our ref in a ref slot → still no 'DOWN'
    // (wrong op — a monitor only fires on a monitor exit).
    const link_ctrl = try FinalTerms.tuple(&ctx, &.{
        FinalTerms.int(&ctx, DOP_LINK), peer_pid, my_pid,
    });
    const link_frame = try encodePassThroughCtrl(gpa, &ctx, link_ctrl);
    defer gpa.free(link_frame);
    const lic = try decodePassThrough(gpa, &ctx, link_frame);
    try std.testing.expect(matchMonitorExit(&ctx, lic, our_ref) == null);

    // The PAYLOAD variant (op 28) an EXIT_PAYLOAD peer actually sends: the ref is
    // in the control tuple {28, From, To, Ref} and the Reason is the TRAILING
    // payload term. Our ref → that trailing reason; a foreign ref → null.
    const pexit_ctrl = try FinalTerms.tuple(&ctx, &.{
        FinalTerms.int(&ctx, DOP_PAYLOAD_MONITOR_P_EXIT), peer_pid, my_pid, our_ref,
    });
    var pframe: std.ArrayList(u8) = .empty;
    defer pframe.deinit(gpa);
    try pframe.append(gpa, DIST_PASS_THROUGH);
    var pce = try etf.encode(gpa, &ctx, pexit_ctrl);
    defer pce.deinit(gpa);
    try pframe.appendSlice(gpa, pce.items);
    var pme = try etf.encode(gpa, &ctx, noproc);
    defer pme.deinit(gpa);
    try pframe.appendSlice(gpa, pme.items);
    const pic = try decodePassThrough(gpa, &ctx, pframe.items);
    try std.testing.expectEqual(DOP_PAYLOAD_MONITOR_P_EXIT, pic.op);
    const pgot = matchMonitorExit(&ctx, pic, our_ref) orelse return error.NoPayloadDown;
    try std.testing.expect(FinalTerms.eqlExact(&ctx, pgot, noproc));
    try std.testing.expect(matchMonitorExit(&ctx, pic, other_ref) == null);
}

test "LAW E18.3b TEARDOWN-FLUSHES-WITH-NOCONNECTION: the DOWN triple built on carrier teardown carries reason=noconnection and the peer-node object identity" {
    // When the carrier tears down with a monitor outstanding, the synthesized
    // 'DOWN' must carry reason `noconnection` (never a silent loss) and an
    // Object `{Name, PeerNode}` that names the exact peer node — the cross-node
    // identity. downTriple/downMessage encode that deterministic surface.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const noconn = FinalTerms.atom(&ctx, try atoms.intern("noconnection"));
    const triple = try downTriple(&ctx, "keeper", "zigvmpeer@127.0.0.1", noconn);
    try std.testing.expectEqual(@as(usize, 3), FinalTerms.tupleArity(&ctx, triple));
    // Type = process
    const ty = FinalTerms.tupleElem(&ctx, triple, 0);
    try std.testing.expectEqualStrings("process", atoms.nameOf(FinalTerms.atomIdxOf(ty)));
    // Object = {keeper, peernode}
    const obj = FinalTerms.tupleElem(&ctx, triple, 1);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&ctx, obj));
    try std.testing.expectEqualStrings("keeper", atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, obj, 0))));
    try std.testing.expectEqualStrings("zigvmpeer@127.0.0.1", atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, obj, 1))));
    // Reason = noconnection (never silently dropped)
    try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, triple, 2), noconn));

    // The full DOWN message keeps the ref in slot 1 and the same triple in 0/2..4.
    const ref = try FinalTerms.refExt(&ctx, .{ 1, 0, 0 }, try atoms.intern("zigvmmon@127.0.0.1"), 3);
    const dm = try downMessage(&ctx, ref, "keeper", "zigvmpeer@127.0.0.1", noconn);
    try std.testing.expectEqual(@as(usize, 5), FinalTerms.tupleArity(&ctx, dm));
    try std.testing.expectEqualStrings("DOWN", atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, dm, 0))));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, dm, 1), ref));
    try std.testing.expectEqualStrings("process", atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, dm, 2))));
}

// --- E18 Task 3c (remote link/exit2/demonitor) laws --------------------------

test "LAW E18.3c LINK-EXIT-ROUND-TRIP: encodeLink recovers op=LINK and the exact pid pair; a peer EXIT for that pair matches (link-symmetry)" {
    // A remote LINK's control tuple {1, FromPid, ToPid} must decode back to op 1
    // with BOTH pids recovered EXACTLY (the link-symmetry surface: our pid links
    // the peer pid, and the peer's EXIT for that peer-pid death is addressed back
    // to our exact pid). Twin-seeded over generated pid identities (seed echoed).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const seed: u64 = 0x18E3_C_10DE_0001;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const our_node = try atoms.intern("zigvmlnk@127.0.0.1");
    const peer_node = try atoms.intern("zigvmpeer@127.0.0.1");
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const our_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);
        const peer_pid = try FinalTerms.pidExt(&ctx, r.int(u32), r.int(u32), peer_node, r.int(u32));
        const frame = try encodeLink(gpa, &ctx, our_pid, peer_pid);
        defer gpa.free(frame);
        try std.testing.expectEqual(DIST_PASS_THROUGH, frame[0]);
        const ic = try decodePassThrough(gpa, &ctx, frame);
        try std.testing.expectEqual(DOP_LINK, ic.op);
        try std.testing.expect(ic.msg == null); // control-only, no payload
        try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, ic.ctrl, 1), our_pid));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, ic.ctrl, 2), peer_pid));
    }
}

test "LAW E18.3c EXIT-PROPAGATES-REASON: matchLinkExit yields {From,Reason} ONLY for our exact linked pid, across EXIT(3)/PAYLOAD_EXIT(24), never a foreign target or non-exit op" {
    // The linked peer proc's death must deliver {'EXIT', From, Reason} iff the
    // exit is addressed to OUR exact pid — a mis-delivered/fabricated exit is
    // unrepresentable. Both wire encodings are proven: classic EXIT {3,F,T,R}
    // (reason in the tuple) and the EXIT_PAYLOAD peer's PAYLOAD_EXIT {24,F,T}+R
    // (reason trailing). A foreign target pid, or a non-exit op (LINK), → null.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const our_node = try atoms.intern("zigvmlnk@127.0.0.1");
    const peer_node = try atoms.intern("zigvmpeer@127.0.0.1");
    const our_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);
    const other_pid = try FinalTerms.pidExt(&ctx, 2, 0, our_node, 3);
    const peer_pid = try FinalTerms.pidExt(&ctx, 7, 0, peer_node, 5);
    const reason = FinalTerms.atom(&ctx, try atoms.intern("linkboom"));

    // classic EXIT {3, PeerPid, OurPid, Reason} — reason in the control tuple.
    const exit_ctrl = try FinalTerms.tuple(&ctx, &.{
        FinalTerms.int(&ctx, DOP_EXIT), peer_pid, our_pid, reason,
    });
    const exit_frame = try encodePassThroughCtrl(gpa, &ctx, exit_ctrl);
    defer gpa.free(exit_frame);
    const ic = try decodePassThrough(gpa, &ctx, exit_frame);
    try std.testing.expectEqual(DOP_EXIT, ic.op);
    const le = matchLinkExit(&ctx, ic, our_pid) orelse return error.NoExit;
    try std.testing.expect(FinalTerms.eqlExact(&ctx, le.from, peer_pid));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, le.reason, reason));
    // addressed to a DIFFERENT local pid → no exit (right-target identity).
    try std.testing.expect(matchLinkExit(&ctx, ic, other_pid) == null);
    // the delivered {'EXIT', From, Reason} carries exactly the wire pid+reason.
    const em = try exitMessage(&ctx, le.from, le.reason);
    try std.testing.expectEqualStrings("EXIT", atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, em, 0))));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, em, 1), peer_pid));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, em, 2), reason));

    // PAYLOAD_EXIT {24, PeerPid, OurPid} + trailing Reason — the EXIT_PAYLOAD form.
    const pexit_ctrl = try FinalTerms.tuple(&ctx, &.{
        FinalTerms.int(&ctx, DOP_PAYLOAD_EXIT), peer_pid, our_pid,
    });
    var pframe: std.ArrayList(u8) = .empty;
    defer pframe.deinit(gpa);
    try pframe.append(gpa, DIST_PASS_THROUGH);
    var pce = try etf.encode(gpa, &ctx, pexit_ctrl);
    defer pce.deinit(gpa);
    try pframe.appendSlice(gpa, pce.items);
    var pre = try etf.encode(gpa, &ctx, reason);
    defer pre.deinit(gpa);
    try pframe.appendSlice(gpa, pre.items);
    const pic = try decodePassThrough(gpa, &ctx, pframe.items);
    try std.testing.expectEqual(DOP_PAYLOAD_EXIT, pic.op);
    const ple = matchLinkExit(&ctx, pic, our_pid) orelse return error.NoPayloadExit;
    try std.testing.expect(FinalTerms.eqlExact(&ctx, ple.from, peer_pid));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, ple.reason, reason));
    try std.testing.expect(matchLinkExit(&ctx, pic, other_pid) == null);

    // a LINK control message (op 1) is NOT an exit → null even for our pid.
    const link_ctrl = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, DOP_LINK), peer_pid, our_pid });
    const link_frame = try encodePassThroughCtrl(gpa, &ctx, link_ctrl);
    defer gpa.free(link_frame);
    const lic = try decodePassThrough(gpa, &ctx, link_frame);
    try std.testing.expect(matchLinkExit(&ctx, lic, our_pid) == null);
}

test "LAW E18.3c EXIT2-PAYLOAD-ROUND-TRIP: encodePayloadExit2 recovers op=PAYLOAD_EXIT2, the target pid, and the reason as the trailing payload" {
    // Outbound exit/2 to a remote pid under EXIT_PAYLOAD is {26, From, To} + a
    // trailing Reason. It must decode back to op 26, the EXACT target pid, and the
    // reason as the trailing message (never fused into the control tuple). Twin-
    // seeded over generated reasons (seed echoed below).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();
    const seed: u64 = 0x18E3_C_10DE_0002;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const our_node = try atoms.intern("zigvmlnk@127.0.0.1");
    const peer_node = try atoms.intern("zigvmpeer@127.0.0.1");
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const from_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);
        const to_pid = try FinalTerms.pidExt(&ctx, r.int(u32), 0, peer_node, 5);
        const reason = try etf.genWireTerm(r, &ctx, 3);
        const before = try FinalTerms.denote(&ctx, sa, reason);
        const frame = try encodePayloadExit2(gpa, &ctx, from_pid, to_pid, reason);
        defer gpa.free(frame);
        try std.testing.expectEqual(DIST_PASS_THROUGH, frame[0]);
        const ic = try decodePassThrough(gpa, &ctx, frame);
        try std.testing.expectEqual(DOP_PAYLOAD_EXIT2, ic.op);
        try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, ic.ctrl, 2), to_pid));
        try std.testing.expect(ic.msg != null);
        try std.testing.expect(spec.eqlExact(before, try FinalTerms.denote(&ctx, sa, ic.msg.?)));
        // matchLinkExit also recovers it as an exit addressed to `to_pid`.
        const le = matchLinkExit(&ctx, ic, to_pid) orelse return error.NoExit2;
        try std.testing.expect(spec.eqlExact(before, try FinalTerms.denote(&ctx, sa, le.reason)));
    }
}

test "LAW E18.3c DEMONITOR-RETRACT-ROUND-TRIP: encodeDemonitorP recovers op=DEMONITOR_P with the EXACT ref (ref-symmetric to encodeMonitorP); a demonitored ref never matches a monitor exit" {
    // demonitor must carry the SAME ref as the monitor it retracts (op 20, the
    // symmetric retract of op 19) — the peer keys the retraction on that exact
    // ref. And a DEMONITOR_P control message is not itself a monitor exit, so
    // matchMonitorExit never fabricates a 'DOWN' from it.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const our_node = try atoms.intern("zigvmmon@127.0.0.1");
    const from_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);
    const target = FinalTerms.atom(&ctx, try atoms.intern("keeper"));
    const ref = try FinalTerms.refExt(&ctx, .{ 0xD3A0, 0, 0 }, our_node, 3);

    const mon = try encodeMonitorP(gpa, &ctx, from_pid, target, ref);
    defer gpa.free(mon);
    const dem = try encodeDemonitorP(gpa, &ctx, from_pid, target, ref);
    defer gpa.free(dem);
    const mic = try decodePassThrough(gpa, &ctx, mon);
    const dic = try decodePassThrough(gpa, &ctx, dem);
    try std.testing.expectEqual(DOP_MONITOR_P, mic.op);
    try std.testing.expectEqual(DOP_DEMONITOR_P, dic.op);
    // ref-symmetry: monitor and its retract carry the EXACT same ref + target.
    try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, mic.ctrl, 3), FinalTerms.tupleElem(&ctx, dic.ctrl, 3)));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, mic.ctrl, 3), ref));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, dic.ctrl, 2), target));
    // a DEMONITOR_P is not a monitor exit → no 'DOWN' is ever fabricated from it.
    try std.testing.expect(matchMonitorExit(&ctx, dic, ref) == null);
}

// --- E20 Task 1 (remote unlink / inbound-exit2 / exit1) laws ------------------

test "LAW E20.1 UNLINK-TWO-FRAME-ROUND-TRIP: encodeUnlinkId/encodeUnlinkIdAck recover ops 35/36 with the EXACT id; matchUnlinkIdAck accepts the ack ONLY for our exact id AND our exact originating pid" {
    // unlink/1 across a node is a two-frame handshake: UNLINK_ID {35,Id,From,To}
    // out, UNLINK_ID_ACK {36,Id,AckFrom,AckTo} back with the SAME id, addressed to
    // our originating pid. The retract is re-associated on BOTH the exact id and
    // the exact target — a foreign id or a foreign target must NOT close the loop
    // (a mis-delivered/fabricated ack is unrepresentable). Twin-seeded over ids +
    // peer pids (seed echoed below).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const seed: u64 = 0x20E1_0001_C0DE_1122;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const our_node = try atoms.intern("zigvmunl@127.0.0.1");
    const peer_node = try atoms.intern("zigvmpeer@127.0.0.1");
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const our_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);
        const peer_pid = try FinalTerms.pidExt(&ctx, r.int(u32), 0, peer_node, 5);
        const id_val: u32 = (r.int(u32) | 1); // non-zero unlink id
        const id = FinalTerms.int(&ctx, @intCast(id_val));

        // Frame 1: UNLINK_ID out — decodes back to op 35, the exact id + pid pair.
        const uframe = try encodeUnlinkId(gpa, &ctx, id, our_pid, peer_pid);
        defer gpa.free(uframe);
        try std.testing.expectEqual(DIST_PASS_THROUGH, uframe[0]);
        const uic = try decodePassThrough(gpa, &ctx, uframe);
        try std.testing.expectEqual(DOP_UNLINK_ID, uic.op);
        try std.testing.expect(uic.msg == null); // control-only
        try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, uic.ctrl, 1), id));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, uic.ctrl, 2), our_pid));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, uic.ctrl, 3), peer_pid));

        // Frame 2: UNLINK_ID_ACK back — ERTS builds {36, Id, AckFrom(=peer), AckTo(=our)}.
        const aframe = try encodeUnlinkIdAck(gpa, &ctx, id, peer_pid, our_pid);
        defer gpa.free(aframe);
        const aic = try decodePassThrough(gpa, &ctx, aframe);
        try std.testing.expectEqual(DOP_UNLINK_ID_ACK, aic.op);
        // the ack closes the loop ONLY for our exact id AND our exact pid.
        try std.testing.expect(matchUnlinkIdAck(&ctx, aic, our_pid, id));
        // a foreign id → no match (right-id identity).
        const other_id = FinalTerms.int(&ctx, @intCast((id_val ^ 0x5A5A5A5A) | 1));
        try std.testing.expect(!matchUnlinkIdAck(&ctx, aic, our_pid, other_id));
        // addressed to a different local pid → no match (right-target identity).
        const other_pid = try FinalTerms.pidExt(&ctx, 2, 0, our_node, 3);
        try std.testing.expect(!matchUnlinkIdAck(&ctx, aic, other_pid, id));
        // a non-ack op (the UNLINK_ID itself) is never an ack.
        try std.testing.expect(!matchUnlinkIdAck(&ctx, uic, our_pid, id));
    }
}

test "LAW E20.1 INBOUND-EXIT2-DELIVERY: an inbound PAYLOAD_EXIT2 for a zigvm-local victim pid kills exactly that proc with the wire reason (never a foreign target)" {
    // The mirror of the outbound dist-exit2: the peer targets a zigvm-local victim
    // with exit/2. zigvm mints the victim's foreign pid, the peer addresses
    // PAYLOAD_EXIT2 to it, matchLinkExit recovers {From,Reason} ONLY for that exact
    // pid, and the recovered reason drives a REAL exit_sig that terminates the live
    // local victim proc with exactly that reason. An exit2 for a DIFFERENT pid
    // leaves the victim alive (right-target identity through the whole kill path).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    const idle: ia.Program = &.{
        .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
        .{ .jump = .{ .to = 0 } },
    };
    const victim = try vm.spawn(idle, 0, null);
    const vctx = &vm.procs.items[victim].machine.ctx;
    const our_node = try atoms.intern("zigvmvic@127.0.0.1");
    const peer_node = try atoms.intern("zigvmpeer@127.0.0.1");
    const victim_pid = try FinalTerms.pidExt(vctx, 2, 0, our_node, 3);
    const peer_pid = try FinalTerms.pidExt(vctx, 7, 0, peer_node, 5);
    const reason = FinalTerms.atom(vctx, try atoms.intern("killzig"));

    // A PAYLOAD_EXIT2 addressed to a DIFFERENT local pid must NOT match our victim.
    const other_pid = try FinalTerms.pidExt(vctx, 99, 0, our_node, 3);
    const wrong = try encodePayloadExit2(gpa, vctx, peer_pid, other_pid, reason);
    defer gpa.free(wrong);
    const wic = try decodePassThrough(gpa, vctx, wrong);
    try std.testing.expect(matchLinkExit(vctx, wic, victim_pid) == null);
    try std.testing.expect(vm.procs.items[victim].alive); // still alive

    // The real inbound EXIT2 for the victim pid → recover reason → kill the proc.
    const frame = try encodePayloadExit2(gpa, vctx, peer_pid, victim_pid, reason);
    defer gpa.free(frame);
    const ic = try decodePassThrough(gpa, vctx, frame);
    try std.testing.expectEqual(DOP_PAYLOAD_EXIT2, ic.op);
    const le = matchLinkExit(vctx, ic, victim_pid) orelse return error.NoInboundExit2;
    try vm.signal(0xFFFF, victim, .{ .exit_sig = .{ .rfrag = try vm.reasonFrag(vctx, le.reason) } });
    try vm.drainSignalsPub(victim);
    try std.testing.expect(!vm.procs.items[victim].alive); // killed
    // terminated with EXACTLY the wire reason.
    try std.testing.expect(FinalTerms.eqlExact(vctx, vm.procs.items[victim].machine.result, reason));
}

test "LAW E20.1 EXIT1-NORMAL-PROPAGATION: a remote linked proc's exit/1(normal) delivers {'EXIT',Pid,normal} to a TRAPPING local proc, but is silently dropped by a NON-trapping one" {
    // exit/1 with reason `normal` is the edge e18-t3c's abnormal `linkboom` did NOT
    // cover: over a link erts still transmits a normal-reason exit, and a TRAPPING
    // partner receives {'EXIT',Pid,normal} while a NON-trapping partner drops it
    // (no cascade). Both halves are asserted through the REAL exit_sig path.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    const idle: ia.Program = &.{
        .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
        .{ .jump = .{ .to = 0 } },
    };
    const peer_node = try atoms.intern("zigvmpeer@127.0.0.1");

    // Decode a live-shape normal-reason exit for our pid (PAYLOAD_EXIT {24,...}+R).
    const trapper = try vm.spawn(idle, 0, null);
    vm.procs.items[trapper].machine.trap_exit = true;
    const tctx = &vm.procs.items[trapper].machine.ctx;
    const our_pid = try FinalTerms.pidExt(tctx, 1, 0, try atoms.intern("zigvmex1@127.0.0.1"), 3);
    const child_pid = try FinalTerms.pidExt(tctx, 8, 0, peer_node, 5);
    const normal = FinalTerms.atom(tctx, try atoms.intern("normal"));
    const frame = try encodePayloadExit2(gpa, tctx, child_pid, our_pid, normal);
    defer gpa.free(frame);
    const ic = try decodePassThrough(gpa, tctx, frame);
    const le = matchLinkExit(tctx, ic, our_pid) orelse return error.NoNormalExit;
    try std.testing.expect(FinalTerms.eqlExact(tctx, le.reason, normal));

    // TRAPPING proc: exit_sig(normal) → {'EXIT', <sender pid>, normal} delivered.
    try vm.signal(0xFFFF, trapper, .{ .exit_sig = .{ .rfrag = try vm.reasonFrag(tctx, le.reason) } });
    try vm.drainSignalsPub(trapper);
    try std.testing.expect(vm.procs.items[trapper].alive); // trapping: survives
    var qbuf: [8]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
    const q = vm.procs.items[trapper].machine.mbox.toSeq(&qbuf);
    try std.testing.expectEqual(@as(usize, 1), q.len);
    const t = q[0].payload;
    try std.testing.expectEqualStrings("EXIT", atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(tctx, t, 0))));
    try std.testing.expect(FinalTerms.eqlExact(tctx, FinalTerms.tupleElem(tctx, t, 2), normal));

    // NON-trapping proc: exit_sig(normal) is silently dropped (no kill, no msg).
    const plain = try vm.spawn(idle, 0, null);
    const pctx = &vm.procs.items[plain].machine.ctx;
    const pnormal = FinalTerms.atom(pctx, try atoms.intern("normal"));
    try vm.signal(0xFFFF, plain, .{ .exit_sig = .{ .rfrag = try vm.reasonFrag(tctx, pnormal) } });
    try vm.drainSignalsPub(plain);
    try std.testing.expect(vm.procs.items[plain].alive); // normal untrapped: ignored
    var pbuf: [8]@import("mailbox_algebra.zig").Msg(FinalTerms) = undefined;
    try std.testing.expectEqual(@as(usize, 0), vm.procs.items[plain].machine.mbox.toSeq(&pbuf).len);
}

// --- E18.4 laws (global coordination: net_kernel / global / pg) ---------------

test "LAW E18.4 GLOBAL-INIT-CONNECT-EXTRACT: globalInitConnectNode recovers the peer node ONLY from a well-formed {'$gen_cast',{init_connect,_,Node,_}} cast, never a foreign cast" {
    // The peer's global_name_server casts init_connect to a newly connected
    // node's global_name_server; the extractor must yield exactly the initiating
    // Node atom (element 2 of the inner tuple) and reject every other shape — a
    // fabricated global membership is unrepresentable. Round-trips a synthetic
    // cast whose byte shape matches the pinned peer's, plus negative shapes.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const peer_node = try atoms.intern("gpeer@127.0.0.1");
    const peer_atom = FinalTerms.atom(&ctx, peer_node);
    const vsn_tag = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 8), FinalTerms.int(&ctx, 12345) });
    const locker = FinalTerms.atom(&ctx, try atoms.intern("no_longer_a_pid"));
    const init_connect = try FinalTerms.tuple(&ctx, &.{
        FinalTerms.atom(&ctx, try atoms.intern("init_connect")), vsn_tag, peer_atom, locker,
    });
    const cast = try FinalTerms.tuple(&ctx, &.{
        FinalTerms.atom(&ctx, try atoms.intern("$gen_cast")), init_connect,
    });
    const got = globalInitConnectNode(&ctx, cast) orelse return error.NoInitConnect;
    try std.testing.expect(FinalTerms.eqlExact(&ctx, got, peer_atom));
    try std.testing.expectEqualStrings("gpeer@127.0.0.1", atoms.nameOf(FinalTerms.atomIdxOf(got)));

    // Negatives: a plain $gen_cast that is not init_connect, and a non-cast tuple.
    const other_inner = try FinalTerms.tuple(&ctx, &.{ FinalTerms.atom(&ctx, try atoms.intern("whereis")), peer_atom });
    const other_cast = try FinalTerms.tuple(&ctx, &.{ FinalTerms.atom(&ctx, try atoms.intern("$gen_cast")), other_inner });
    try std.testing.expect(globalInitConnectNode(&ctx, other_cast) == null);
    const bare = FinalTerms.atom(&ctx, try atoms.intern("hello"));
    try std.testing.expect(globalInitConnectNode(&ctx, bare) == null);
    try std.testing.expect(globalInitConnectNode(&ctx, init_connect) == null); // missing $gen_cast wrapper
}

test "LAW E18.4 PG-DISCOVER-EXTRACT: pgDiscoverPid recovers the peer scope pid ONLY from a {discover, Pid, ...} broadcast, never a foreign message" {
    // The peer's default pg scope broadcasts {discover, ScopePid, Ref} on nodeup;
    // the extractor yields exactly that pid (whose node identifies the peer) and
    // rejects any other shape. Round-trips a synthetic discover + negatives.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const peer_node = try atoms.intern("pgpeer@127.0.0.1");
    const scope_pid = try FinalTerms.pidExt(&ctx, 42, 0, peer_node, 7);
    const ref = try FinalTerms.refExt(&ctx, .{ 0xABCD, 0, 0 }, peer_node, 7);
    const discover = try FinalTerms.tuple(&ctx, &.{
        FinalTerms.atom(&ctx, try atoms.intern("discover")), scope_pid, ref,
    });
    const got = pgDiscoverPid(&ctx, discover) orelse return error.NoDiscover;
    try std.testing.expect(FinalTerms.eqlExact(&ctx, got, scope_pid));
    try std.testing.expectEqualStrings("pgpeer@127.0.0.1", FinalTerms.pidNodeName(&ctx, got));

    // Negatives: a discover whose element 1 is NOT a pid, and a foreign tag.
    const bad = try FinalTerms.tuple(&ctx, &.{ FinalTerms.atom(&ctx, try atoms.intern("discover")), FinalTerms.int(&ctx, 1) });
    try std.testing.expect(pgDiscoverPid(&ctx, bad) == null);
    const foreign = try FinalTerms.tuple(&ctx, &.{ FinalTerms.atom(&ctx, try atoms.intern("sync")), scope_pid });
    try std.testing.expect(pgDiscoverPid(&ctx, foreign) == null);
}

test "LAW E18.4 NODE-LIFECYCLE-ORDER: foldNodeLifecycle admits UP-then-DOWN exactly once, rejecting every other monitor_nodes stream" {
    // net_kernel monitor_nodes promises a monitored node goes up exactly once,
    // then down exactly once, in that order. The fold is the pure core of the
    // live net_kernel driver's EQ (the peer must emit exactly this stream for
    // zigvm). Exhaustive over the discriminating short streams.
    try std.testing.expectEqual(NodeLifecycle.none, foldNodeLifecycle(&.{}));
    try std.testing.expectEqual(NodeLifecycle.up_only, foldNodeLifecycle(&.{.up}));
    try std.testing.expectEqual(NodeLifecycle.down_after_up, foldNodeLifecycle(&.{ .up, .down }));
    try std.testing.expectEqual(NodeLifecycle.invalid, foldNodeLifecycle(&.{.down})); // down before up
    try std.testing.expectEqual(NodeLifecycle.invalid, foldNodeLifecycle(&.{ .up, .up })); // repeated up
    try std.testing.expectEqual(NodeLifecycle.invalid, foldNodeLifecycle(&.{ .up, .down, .up })); // event after lifecycle
    try std.testing.expectEqual(NodeLifecycle.invalid, foldNodeLifecycle(&.{ .down, .down }));
}

// --- E20.2 laws (global / pg convergence state machines) ---------------------

test "LAW E20.2 PG-MEMBERSHIP-CONVERGENCE: the pg global view is a join-semilattice — merging a peer's local_data is set union (idempotent/commutative), so a member on ONE node is visible from BOTH" {
    // The pure core of pg's membership convergence: view = JOIN (set union) of
    // every node's (group,member) pairs. Merging a peer's local_data ADDS its
    // members without duplication and CONVERGES regardless of order. This is
    // exactly what makes the pinned peer's get_members include zigvm's member
    // once zigvm casts local_data back (DIVERGENCE 321). Seeded generators.
    const seed: u64 = 0x2002_9C_C0_11DE_0001;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const groups = [_][]const u8{ "grp", "workers", "sessions" };
    const nodes = [_][]const u8{ "zigvm@127.0.0.1", "peer@127.0.0.1" };
    var it: usize = 0;
    while (it < 256) : (it += 1) {
        var a_buf: [8]GroupMember = undefined;
        var b_buf: [8]GroupMember = undefined;
        const na = r.intRangeAtMost(usize, 0, 4);
        const nb = r.intRangeAtMost(usize, 1, 4);
        for (0..na) |k| a_buf[k] = .{ .group = groups[r.uintLessThan(usize, groups.len)], .node = nodes[0], .num = r.uintLessThan(u64, 6) };
        // The peer's local_data: members on the PEER node — the cross-node case.
        for (0..nb) |k| b_buf[k] = .{ .group = groups[r.uintLessThan(usize, groups.len)], .node = nodes[1], .num = r.uintLessThan(u64, 6) };
        const a = a_buf[0..na];
        const b = b_buf[0..nb];

        var ab: [16]GroupMember = undefined;
        var ba: [16]GroupMember = undefined;
        const nab = pgJoin(a, b, &ab);
        const nba = pgJoin(b, a, &ba);

        // COMMUTATIVE (set equality): join(a,b) and join(b,a) have the same members.
        try std.testing.expectEqual(nab, nba);
        for (ab[0..nab]) |m| try std.testing.expect(pgContains(ba[0..nba], m));

        // IDEMPOTENT: join(a,a) == a as a SET (the deduped size of a, since the
        // generator may repeat a pair — a set absorbs the repeat).
        var aa: [16]GroupMember = undefined;
        const naa = pgJoin(a, a, &aa);
        var a_set: [16]GroupMember = undefined;
        const na_set = pgJoin(a, &.{}, &a_set);
        try std.testing.expectEqual(na_set, naa);

        // MEMBER-VISIBLE (cross-node): every peer member (seed echoed above) is
        // visible in the merged view under its group — the convergence observable.
        for (b) |m| {
            try std.testing.expect(pgContains(ab[0..nab], m));
            var mm: [16]GroupMember = undefined;
            const nmm = pgMembersOf(ab[0..nab], m.group, &mm);
            var found = false;
            for (mm[0..nmm]) |x| if (x.eql(m)) {
                found = true;
            };
            try std.testing.expect(found);
        }
        if (it == 0 and false) std.debug.print("seed={x}\n", .{seed});
    }
}

test "LAW E20.2 GLOBAL-REGISTRATION-CONSISTENCY: resolveGlobalNames leaves AT MOST ONE owner per name — unique names preserved, a clash keeps the same single owner regardless of merge order" {
    // The pure payoff of global's locker exchange/resolved phase: merging two
    // partitions' name tables yields a table where every name has EXACTLY ONE
    // owner (at-most-one-owner-both-nodes). A name unique to one partition is
    // preserved (registration visible from both); a clash resolves to the total
    // -order winner, the SAME owner whether we resolve(a,b) or resolve(b,a).
    const seed: u64 = 0x2002_61_08_A1DE_0002;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const names = [_][]const u8{ "alpha", "beta", "gamma", "delta" };
    const nodes = [_][]const u8{ "zigvm@127.0.0.1", "peer@127.0.0.1" };
    var it: usize = 0;
    while (it < 256) : (it += 1) {
        var a_buf: [8]GlobalName = undefined;
        var b_buf: [8]GlobalName = undefined;
        var na: usize = 0;
        var nb: usize = 0;
        // Each partition binds a subset of names to a random owner; names WITHIN a
        // partition are unique (a single node can't bind a global name twice).
        for (names) |nm| {
            if (r.boolean()) {
                a_buf[na] = .{ .name = nm, .node = nodes[r.uintLessThan(usize, nodes.len)], .num = r.uintLessThan(u64, 5) };
                na += 1;
            }
            if (r.boolean()) {
                b_buf[nb] = .{ .name = nm, .node = nodes[r.uintLessThan(usize, nodes.len)], .num = r.uintLessThan(u64, 5) };
                nb += 1;
            }
        }
        const a = a_buf[0..na];
        const b = b_buf[0..nb];

        var ab: [16]GlobalName = undefined;
        var ba: [16]GlobalName = undefined;
        const nab = resolveGlobalNames(a, b, &ab);
        const nba = resolveGlobalNames(b, a, &ba);

        // AT-MOST-ONE-OWNER: no name appears twice in the resolved table.
        for (ab[0..nab], 0..) |x, i| {
            for (ab[0..nab], 0..) |y, j| {
                if (i != j) try std.testing.expect(!std.mem.eql(u8, x.name, y.name));
            }
        }

        // ORDER-INDEPENDENT SINGLE OWNER: whereis(name) agrees across merge order.
        for (names) |nm| {
            const oa = globalWhereis(ab[0..nab], nm);
            const ob = globalWhereis(ba[0..nba], nm);
            try std.testing.expectEqual(oa == null, ob == null);
            if (oa) |x| {
                const y = ob.?;
                try std.testing.expectEqualStrings(x.node, y.node);
                try std.testing.expectEqual(x.num, y.num);
            }
        }

        // UNIQUE-NAME PRESERVED: a name bound in exactly ONE partition keeps that
        // owner (the registration is visible from both after the merge).
        for (names) |nm| {
            const in_a = globalWhereis(a, nm);
            const in_b = globalWhereis(b, nm);
            if (in_a != null and in_b == null) {
                const got = globalWhereis(ab[0..nab], nm).?;
                try std.testing.expectEqualStrings(in_a.?.node, got.node);
                try std.testing.expectEqual(in_a.?.num, got.num);
            }
            // CLASH: resolves to the ownerWins winner.
            if (in_a) |xa| if (in_b) |xb| {
                const got = globalWhereis(ab[0..nab], nm).?;
                const winner = if (ownerWins(xa, xb)) xa else xb;
                try std.testing.expectEqualStrings(winner.node, got.node);
                try std.testing.expectEqual(winner.num, got.num);
            };
        }
    }
}

// --- E20 Task 3 (DIVERGENCE 322, multi-node topologies) laws -----------------

test "LAW E20.3 TRANSITIVE-NODES-VISIBILITY: in a 3-node clique each node's nodes/0 is exactly the OTHER two — the visibility relation is the complete graph K3 (symmetric, irreflexive, order-independent)" {
    // The pure model of the transitive triad {zigvm, A, B}: with all three edges
    // present, viewOf(x) = nodes \ {x}. zigvm's OWN nodes/0 (its live-peer set,
    // distLiveNodesTerm over the node table — see the proc.zig companion test) is
    // the local vertex of this relation; the peers' views are the pinned OTP-30
    // observation the harness `dist-coord.transitive-nodes` row proves live. The
    // relation is a SET (register is idempotent/order-independent) and symmetric.
    const nodes = [_][]const u8{ "zigvm@127.0.0.1", "peerA@127.0.0.1", "peerB@127.0.0.1" };
    // Edge set of the clique: every unordered pair connected.
    const view = struct {
        fn of(all: []const []const u8, x: usize, out: [][]const u8) usize {
            var n: usize = 0;
            for (all, 0..) |nm, i| {
                if (i != x) {
                    out[n] = nm;
                    n += 1;
                }
            }
            return n;
        }
    };
    // IRREFLEXIVE + SIZE-2: each node sees exactly the two others, never itself.
    for (nodes, 0..) |_, x| {
        var buf: [3][]const u8 = undefined;
        const n = view.of(&nodes, x, &buf);
        try std.testing.expectEqual(@as(usize, 2), n);
        for (buf[0..n]) |seen| try std.testing.expect(!std.mem.eql(u8, seen, nodes[x]));
    }
    // SYMMETRIC: x sees y iff y sees x (a live bidirectional carrier).
    for (nodes, 0..) |_, x| {
        for (nodes, 0..) |_, y| {
            if (x == y) continue;
            var bx: [3][]const u8 = undefined;
            var by: [3][]const u8 = undefined;
            const nx = view.of(&nodes, x, &bx);
            const ny = view.of(&nodes, y, &by);
            var x_sees_y = false;
            for (bx[0..nx]) |s| if (std.mem.eql(u8, s, nodes[y])) {
                x_sees_y = true;
            };
            var y_sees_x = false;
            for (by[0..ny]) |s| if (std.mem.eql(u8, s, nodes[x])) {
                y_sees_x = true;
            };
            try std.testing.expect(x_sees_y and y_sees_x);
        }
    }
}

test "LAW E20.3 3-NODE-PG-CONVERGENCE: pgJoin is ASSOCIATIVE so a 3-way membership union is order-independent — a member on ANY one node is visible from ALL THREE" {
    // The 3-node lift of PG-MEMBERSHIP-CONVERGENCE: the global view of a 3-clique
    // is join(join(a,b),c); associativity (up to set equality) makes it the same
    // set however the three nodes' local_data are folded — so a member cast by
    // ONE node (zigvm) reaches BOTH peers (visible-from-all-three), the live claim
    // `dist-coord.pg-multinode` proves against two pinned OTP-30 peers.
    const seed: u64 = 0x2003_3C_0D_E00E_0003;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const groups = [_][]const u8{ "grp", "workers" };
    const nodes = [_][]const u8{ "zigvm@127.0.0.1", "peerA@127.0.0.1", "peerB@127.0.0.1" };
    var it: usize = 0;
    while (it < 256) : (it += 1) {
        var a_buf: [6]GroupMember = undefined;
        var b_buf: [6]GroupMember = undefined;
        var c_buf: [6]GroupMember = undefined;
        const na = r.intRangeAtMost(usize, 1, 3);
        const nb = r.intRangeAtMost(usize, 0, 3);
        const nc = r.intRangeAtMost(usize, 0, 3);
        for (0..na) |k| a_buf[k] = .{ .group = groups[r.uintLessThan(usize, groups.len)], .node = nodes[0], .num = r.uintLessThan(u64, 5) };
        for (0..nb) |k| b_buf[k] = .{ .group = groups[r.uintLessThan(usize, groups.len)], .node = nodes[1], .num = r.uintLessThan(u64, 5) };
        for (0..nc) |k| c_buf[k] = .{ .group = groups[r.uintLessThan(usize, groups.len)], .node = nodes[2], .num = r.uintLessThan(u64, 5) };
        const a = a_buf[0..na];
        const b = b_buf[0..nb];
        const c = c_buf[0..nc];

        // ASSOCIATIVE (set equality): (a⋁b)⋁c == a⋁(b⋁c).
        var ab: [18]GroupMember = undefined;
        var abc_l: [18]GroupMember = undefined;
        var bc: [18]GroupMember = undefined;
        var abc_r: [18]GroupMember = undefined;
        const nab = pgJoin(a, b, &ab);
        const nabc_l = pgJoin(ab[0..nab], c, &abc_l);
        const nbc = pgJoin(b, c, &bc);
        const nabc_r = pgJoin(a, bc[0..nbc], &abc_r);
        try std.testing.expectEqual(nabc_l, nabc_r);
        for (abc_l[0..nabc_l]) |m| try std.testing.expect(pgContains(abc_r[0..nabc_r], m));

        // VISIBLE-FROM-ALL-THREE: every member of a (zigvm's local_data) is in the
        // 3-way merged view — so both peers' get_members converge to include it.
        for (a) |m| try std.testing.expect(pgContains(abc_l[0..nabc_l], m));
        if (it == 0 and false) std.debug.print("seed={x}\n", .{seed});
    }
}

test "LAW E20.3 PARTITION-HEAL-RECONVERGENCE: a join-semilattice recovers its LUB after a node's retract+rejoin — pgJoin(pgRemoveNode(full,C), C_data) == full" {
    // The pure core of pg's nodedown→nodeup cycle: with full = a⋁b⋁c, a partition
    // that drops node C removes exactly C's members (pgRemoveNode); the heal
    // re-casts C's local_data and pgJoin restores the SAME view. Idempotent LUB
    // recovery — no member is lost or duplicated across the cycle. The live
    // `dist-coord.pg-partition-heal` row proves a real pinned peer B retract
    // zigvm's member on nodedown and reconverge on the reconnect+recast.
    const seed: u64 = 0x2003_9E_A1_7EA1_0003;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const groups = [_][]const u8{ "grp", "sessions" };
    const nodes = [_][]const u8{ "zigvm@127.0.0.1", "peerA@127.0.0.1", "peerB@127.0.0.1" };
    var it: usize = 0;
    while (it < 256) : (it += 1) {
        var a_buf: [6]GroupMember = undefined;
        var b_buf: [6]GroupMember = undefined;
        var c_buf: [6]GroupMember = undefined;
        const na = r.intRangeAtMost(usize, 1, 3);
        const nb = r.intRangeAtMost(usize, 1, 3);
        const nc = r.intRangeAtMost(usize, 1, 3);
        for (0..na) |k| a_buf[k] = .{ .group = groups[r.uintLessThan(usize, groups.len)], .node = nodes[0], .num = r.uintLessThan(u64, 5) };
        for (0..nb) |k| b_buf[k] = .{ .group = groups[r.uintLessThan(usize, groups.len)], .node = nodes[1], .num = r.uintLessThan(u64, 5) };
        for (0..nc) |k| c_buf[k] = .{ .group = groups[r.uintLessThan(usize, groups.len)], .node = nodes[2], .num = r.uintLessThan(u64, 5) };
        const c = c_buf[0..nc];

        // full = a ⋁ b ⋁ c (the pre-partition 3-node view).
        var ab: [18]GroupMember = undefined;
        var full: [18]GroupMember = undefined;
        const nab = pgJoin(a_buf[0..na], b_buf[0..nb], &ab);
        const nfull = pgJoin(ab[0..nab], c, &full);

        // PARTITION: node C (peerB) drops — its members leave the view.
        var partitioned: [18]GroupMember = undefined;
        const npart = pgRemoveNode(full[0..nfull], nodes[2], &partitioned);
        // C's members are GONE while partitioned (the retract observable).
        for (c) |m| try std.testing.expect(!pgContains(partitioned[0..npart], m));

        // HEAL: C reconnects and re-casts its local_data — the view reconverges to
        // EXACTLY full (same set: no loss, no duplication).
        var healed: [18]GroupMember = undefined;
        const nheal = pgJoin(partitioned[0..npart], c, &healed);
        try std.testing.expectEqual(nfull, nheal);
        for (full[0..nfull]) |m| try std.testing.expect(pgContains(healed[0..nheal], m));
        for (healed[0..nheal]) |m| try std.testing.expect(pgContains(full[0..nfull], m));
        if (it == 0 and false) std.debug.print("seed={x}\n", .{seed});
    }
}

// --- E21 Task 4 (DIVERGENCE 320 → live global register) laws -----------------

// Build a synthetic inbound alias-reply frame (as the pinned peer's gen:reply
// emits): PASS_THROUGH + enc({op, From, Alias}) + enc({[alias|AliasRef], Reply}).
// Returns the owned packet-4 PAYLOAD (caller frees). Used to exercise the reply
// matcher over the REAL decode path (decodePassThrough) rather than a hand-built
// InboundControl.
fn buildAliasReplyFrame(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    op: i64,
    from_pid: FinalTerms.Term,
    alias_ref: FinalTerms.Term,
    reply: FinalTerms.Term,
) ![]u8 {
    const alias_atom = FinalTerms.atom(ctx, try ctx.atoms.intern("alias"));
    const tag = try FinalTerms.cons(ctx, alias_atom, alias_ref);
    const ctrl = try FinalTerms.tuple(ctx, &.{ FinalTerms.int(ctx, op), from_pid, alias_ref });
    const msg = try FinalTerms.tuple(ctx, &.{ tag, reply });
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, DIST_PASS_THROUGH);
    var ce = try etf.encode(gpa, ctx, ctrl);
    defer ce.deinit(gpa);
    try out.appendSlice(gpa, ce.items);
    var me = try etf.encode(gpa, ctx, msg);
    defer me.deinit(gpa);
    try out.appendSlice(gpa, me.items);
    return out.toOwnedSlice(gpa);
}

test "LAW E21.4 locker-2phase-acquire: matchAliasReply admits the $gen_call reply ONLY for the EXACT alias reference we minted — a foreign alias, a non-alias op, or a non-alias tag yields null (no fabricated lock-grant)" {
    // The honesty core of "the lock was granted to US": a set_lock/register reply
    // is a gen:reply routed to OUR process alias, arriving as ALIAS_SEND (33) whose
    // trailing message is {[alias|OurRef], Reply}. matchAliasReply returns Reply
    // IFF the tag's ref is eqlExact ours — so a reply meant for another node's alias
    // (or a stray op) can NEVER be mistaken for our acquire. Also pins that the two
    // alias-carrying ops (33/34/37) are accepted while REG_SEND is not.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const seed: u64 = 0x2104_A11A_5_1DE_0001;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const our_node = try atoms.intern("zigvmsgl@127.0.0.1");
    const peer_node = try atoms.intern("zigvmgl@127.0.0.1");
    const replies = [_][]const u8{ "true", "yes", "false", "no" };
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const from_pid = try FinalTerms.pidExt(&ctx, 1, 0, peer_node, 3);
        const our_ref = try FinalTerms.refExt(&ctx, .{ r.int(u32), r.int(u32), 0 }, our_node, 3);
        const reply = FinalTerms.atom(&ctx, try atoms.intern(replies[i % replies.len]));

        // (1) A well-formed ALIAS_SEND to OUR alias → matchAliasReply == Reply.
        const good = try buildAliasReplyFrame(gpa, &ctx, DOP_ALIAS_SEND, from_pid, our_ref, reply);
        defer gpa.free(good);
        const ic_good = try decodePassThrough(gpa, &ctx, good);
        const got = matchAliasReply(&ctx, ic_good, our_ref) orelse return error.NoReply;
        try std.testing.expect(FinalTerms.eqlExact(&ctx, got, reply));

        // (2) A reply to a DIFFERENT alias ref → null (never our acquire).
        const other_ref = try FinalTerms.refExt(&ctx, .{ r.int(u32) | 1, r.int(u32), 7 }, our_node, 3);
        const foreign = try buildAliasReplyFrame(gpa, &ctx, DOP_ALIAS_SEND, from_pid, other_ref, reply);
        defer gpa.free(foreign);
        const ic_foreign = try decodePassThrough(gpa, &ctx, foreign);
        try std.testing.expect(matchAliasReply(&ctx, ic_foreign, our_ref) == null);

        // (3) The SAME reply payload under a non-alias op (REG_SEND) → null.
        const wrong_op = try buildAliasReplyFrame(gpa, &ctx, DOP_REG_SEND, from_pid, our_ref, reply);
        defer gpa.free(wrong_op);
        const ic_wrong = try decodePassThrough(gpa, &ctx, wrong_op);
        try std.testing.expect(matchAliasReply(&ctx, ic_wrong, our_ref) == null);

        // (4) ALTACT_SIG_SEND (37) is ALSO an accepted alias-carrying op.
        const altact = try buildAliasReplyFrame(gpa, &ctx, DOP_ALTACT_SIG_SEND, from_pid, our_ref, reply);
        defer gpa.free(altact);
        const ic_alt = try decodePassThrough(gpa, &ctx, altact);
        try std.testing.expect(matchAliasReply(&ctx, ic_alt, our_ref) != null);
    }
    if (false) std.debug.print("seed={x}\n", .{seed});
}

test "LAW E21.4 global-register-peer-visible: the register request encodes {register, Name, Pid, fun global:random_exit_name/3} faithfully (Name/Pid round-trip; Method is the export-fun) and the set_lock/del_lock pair share ONE resource id" {
    // The register $gen_call the peer inserts (ins_name) must carry EXACTLY the
    // (Name, Pid) that becomes peer-visible: mutating the name or the pid the
    // request encodes would make whereis_name resolve the wrong owner. Also pins
    // that set_lock and del_lock name the SAME {global, Requester} resource — a
    // release that referenced a different id would leak the lock.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const our_node = try atoms.intern("zigvmsgr@127.0.0.1");
    const names = [_][]const u8{ "gtest", "a", "reg_42", "shell" };
    for (names, 0..) |nm, k| {
        const owner = try FinalTerms.pidExt(&ctx, @intCast(2000 + k), 0, our_node, 3);
        const req = try globalRegisterReq(&ctx, nm, owner);
        // Round-trip through the REG_SEND envelope (the on-wire form).
        const from_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);
        const gc = try genCall(&ctx, from_pid, try FinalTerms.refExt(&ctx, .{ 1, 0, 0 }, our_node, 3), req);
        const to_atom = FinalTerms.atom(&ctx, try atoms.intern("global_name_server"));
        const frame = try encodeRegSend(gpa, &ctx, from_pid, to_atom, gc);
        defer gpa.free(frame);
        const ic = try decodePassThrough(gpa, &ctx, frame);
        // Unwrap {'$gen_call', {From, [alias|Ref]}, Request}.
        const call = ic.msg orelse return error.NoMsg;
        try std.testing.expectEqualStrings("$gen_call", atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, call, 0))));
        const request = FinalTerms.tupleElem(&ctx, call, 2);
        try std.testing.expectEqualStrings("register", atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, request, 0))));
        try std.testing.expectEqualStrings(nm, atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, request, 1))));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, request, 2), owner));
        const method = FinalTerms.tupleElem(&ctx, request, 3);
        try std.testing.expect(FinalTerms.repIsExportFun(&ctx, method));
        try std.testing.expectEqualStrings("global", FinalTerms.exportFunModuleName(&ctx, method));
        try std.testing.expectEqualStrings("random_exit_name", FinalTerms.exportFunFuncName(&ctx, method));
        try std.testing.expectEqual(@as(u8, 3), FinalTerms.exportFunArity(&ctx, method));

        // set_lock / del_lock name the SAME resource {global, Requester}.
        const sl = try globalSetLockReq(&ctx, from_pid);
        const dl = try globalDelLockReq(&ctx, from_pid);
        try std.testing.expectEqualStrings("set_lock", atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, sl, 0))));
        try std.testing.expectEqualStrings("del_lock", atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, dl, 0))));
        const sl_id = FinalTerms.tupleElem(&ctx, sl, 1);
        const dl_id = FinalTerms.tupleElem(&ctx, dl, 1);
        try std.testing.expectEqualStrings("global", atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, sl_id, 0))));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, sl_id, dl_id));
    }
}

test "LAW E21.4 single-owner-under-contention: two nodes registering the SAME name resolve to ONE owner (globalWhereis is single-valued) — the competing registration cannot create a second binding, regardless of order" {
    // The consistency the LIVE row OBSERVES on the peer (a competing register_name
    // returns `no`) has this pure core: under the global lock, the second binding
    // of a name never survives — resolveGlobalNames keeps exactly the ownerWins
    // owner, so whereis is a FUNCTION. This is the contention lift of E20.2's
    // at-most-one-owner: the two claimants are on the two nodes and clash.
    const seed: u64 = 0x2104_5106_0E_A1_0003;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const nodes = [_][]const u8{ "zigvmsgr@127.0.0.1", "zigvmgr@127.0.0.1" };
    var it: usize = 0;
    while (it < 256) : (it += 1) {
        // Both partitions claim the SAME name "gtest" with independent owners.
        const a = [_]GlobalName{.{ .name = "gtest", .node = nodes[r.uintLessThan(usize, 2)], .num = r.uintLessThan(u64, 6) }};
        const b = [_]GlobalName{.{ .name = "gtest", .node = nodes[r.uintLessThan(usize, 2)], .num = r.uintLessThan(u64, 6) }};
        var ab: [4]GlobalName = undefined;
        var ba: [4]GlobalName = undefined;
        const nab = resolveGlobalNames(&a, &b, &ab);
        const nba = resolveGlobalNames(&b, &a, &ba);
        // SINGLE BINDING: exactly one owner survives (the competitor is rejected).
        try std.testing.expectEqual(@as(usize, 1), nab);
        try std.testing.expectEqual(@as(usize, 1), nba);
        // ORDER-INDEPENDENT: the surviving owner is the same either way.
        const oa = globalWhereis(ab[0..nab], "gtest").?;
        const ob = globalWhereis(ba[0..nba], "gtest").?;
        try std.testing.expectEqualStrings(oa.node, ob.node);
        try std.testing.expectEqual(oa.num, ob.num);
        // It is exactly the ownerWins winner of the two claimants.
        const winner = if (ownerWins(a[0], b[0])) a[0] else b[0];
        try std.testing.expectEqualStrings(winner.node, oa.node);
        try std.testing.expectEqual(winner.num, oa.num);
    }
    if (false) std.debug.print("seed={x}\n", .{seed});
}

// --- E18.2 laws --------------------------------------------------------------

test "LAW E18.2 V6 FRAMING ROUND-TRIP: send_name/reply/ack decode∘encode == id" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0x18E2_F00D_CAFE_0001);
    const r = prng.random();
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        // send_name round-trip over seeded flags/creation/name.
        const flags = r.int(u64);
        const creation = r.int(u32);
        const nlen = r.intRangeAtMost(usize, 1, 40);
        var nbuf: [40]u8 = undefined;
        for (0..nlen) |k| nbuf[k] = r.intRangeAtMost(u8, 'a', 'z');
        const name = nbuf[0..nlen];
        const enc = try V6.encodeSendName(gpa, flags, creation, name);
        defer gpa.free(enc);
        const dec = try V6.decodeSendName(enc);
        try std.testing.expectEqual(flags, dec.flags);
        try std.testing.expectEqual(creation, dec.creation);
        try std.testing.expectEqualStrings(name, dec.name);

        // challenge_reply round-trip.
        const chal = r.int(u32);
        var digest: [16]u8 = undefined;
        r.bytes(&digest);
        const rep = V6.encodeChallengeReply(chal, digest);
        const rdec = try V6.decodeChallengeReply(&rep);
        try std.testing.expectEqual(chal, rdec.challenge);
        try std.testing.expectEqualSlices(u8, &digest, &rdec.digest);

        // challenge_ack round-trip.
        var adig: [16]u8 = undefined;
        r.bytes(&adig);
        const ackf = V6.encodeChallengeAck(adig);
        const adec = try V6.decodeChallengeAck(&ackf);
        try std.testing.expectEqualSlices(u8, &adig, &adec);

        // recv_challenge parse recovers a hand-built 'N' challenge frame.
        var cf: std.ArrayList(u8) = .empty;
        defer cf.deinit(gpa);
        try cf.append(gpa, 'N');
        try putU64(gpa, &cf, flags);
        try putU32(gpa, &cf, chal);
        try putU32(gpa, &cf, creation);
        try cf.append(gpa, @truncate(nlen >> 8));
        try cf.append(gpa, @truncate(nlen));
        try cf.appendSlice(gpa, name);
        const pc = try V6.parseChallenge(cf.items);
        try std.testing.expectEqual(flags, pc.flags);
        try std.testing.expectEqual(chal, pc.challenge);
        try std.testing.expectEqual(creation, pc.creation);
        try std.testing.expectEqualStrings(name, pc.name);
    }
}

test "LAW E18.2 REJECT-PATH REJECTION: bad status/tag/short-frame/bad-ack are named, never connected" {
    // Status parsing maps rejection states to distinct enum values.
    try std.testing.expectEqual(V6.Status.nok, try V6.parseStatus("snok"));
    try std.testing.expectEqual(V6.Status.not_allowed, try V6.parseStatus("snot_allowed"));
    try std.testing.expectEqual(V6.Status.ok, try V6.parseStatus("sok"));
    try std.testing.expectEqual(V6.Status.other, try V6.parseStatus("sgarbage"));

    // Wrong frame tag on each fixed-shape message.
    try std.testing.expectError(error.BadTag, V6.parseStatus("Xok"));
    try std.testing.expectError(error.BadTag, V6.decodeChallengeAck(&([_]u8{'r'} ++ [_]u8{0} ** 16)));
    try std.testing.expectError(error.BadTag, V6.decodeChallengeReply(&([_]u8{'a'} ++ [_]u8{0} ** 20)));
    try std.testing.expectError(error.BadTag, V6.decodeSendName(&([_]u8{'X'} ++ [_]u8{0} ** 20)));

    // Short frames on every shape.
    try std.testing.expectError(error.ShortFrame, V6.parseStatus(""));
    try std.testing.expectError(error.ShortFrame, V6.decodeChallengeAck(&[_]u8{ 'a', 0, 0 }));
    try std.testing.expectError(error.ShortFrame, V6.decodeChallengeReply(&[_]u8{ 'r', 0, 0 }));
    try std.testing.expectError(error.ShortFrame, V6.decodeSendName(&[_]u8{ 'N', 0, 0 }));
    try std.testing.expectError(error.ShortFrame, V6.parseChallenge(&[_]u8{ 'N', 0, 0 }));

    // Bad-ack rejection: the digest the initiator expects for OUR challenge
    // must not verify against a digest computed under a WRONG cookie. This is
    // the exact check liveConnect performs before returning connected — a
    // mismatch is atomic (the initiator owns no DistEntry to leave partial).
    const our_challenge: u32 = 0xDEAD_BEEF;
    const good = genDigest("right", our_challenge);
    const bad = genDigest("wrong", our_challenge);
    try std.testing.expect(!std.mem.eql(u8, &good, &bad));
    const ack_frame = V6.encodeChallengeAck(bad);
    const parsed = try V6.decodeChallengeAck(&ack_frame);
    try std.testing.expect(!std.mem.eql(u8, &genDigest("right", our_challenge), &parsed));
}

test "LAW E18.2 TIMEOUT-BOUNDED READ: a silent peer read returns TcpTimeout, never hangs" {
    const gpa = std.testing.allocator;
    var pair = try openLoopbackTcpPair();
    defer pair[0].close();
    defer pair[1].close();
    // Bound reads on end [0]; the peer end [1] sends nothing. A handshake read
    // must return error.TcpTimeout within the deadline — a hang would fail this
    // law by stalling the bounded suite.
    try setRecvTimeout(pair[0].fd, 200);
    try std.testing.expectError(error.TcpTimeout, pair[0].readPacket2FrameAlloc(gpa, 512));
}

// --- E18.3 laws (DIVERGENCE 211 residual, REVERSE direction) -----------------

test "LAW E18.3 TICK-KEEPALIVE-BOUNDED: holdAnsweringTicks echoes a peer tick and never hangs" {
    const gpa = std.testing.allocator;
    var pair = try openLoopbackTcpPair();
    defer pair[0].close();
    defer pair[1].close();
    // Both ends bound their reads: a distribution TICK is an empty packet-4
    // frame. The peer end [1] sends one tick; holdAnsweringTicks on end [0] must
    // (a) read it, (b) echo a TICK back, and (c) RETURN within `iters` bounded
    // slices even though the peer then goes silent — a hang fails this law.
    try setRecvTimeout(pair[0].fd, 200);
    try setRecvTimeout(pair[1].fd, 200);
    // inbound tick frame round-trip: an empty packet-4 frame decodes to len 0.
    try pair[1].writePacket4Frame(gpa, &[_]u8{});
    holdAnsweringTicks(gpa, &pair[0], 2); // bounded: reads the tick on slice 0, then times out
    // The echoed tick is the 4-byte zero length prefix (an empty packet-4 frame).
    const echoed = try pair[1].readPacket4FrameAlloc(gpa, 16);
    defer gpa.free(echoed);
    try std.testing.expectEqual(@as(usize, 0), echoed.len);
    // Boundedness against a fully silent peer: no traffic pending, must return.
    holdAnsweringTicks(gpa, &pair[0], 1);
}

// ── e21-t7: FUZZ target — malformed DOP handshake-frame surface ────────────
// SEMANTIC DOMAIN: the V6 handshake codec's decoders (`decodeSendName`,
// `decodeChallengeReply`, `decodeChallengeAck`) are partial functions
// `bytes ⇀ Frame`. Safety obligation (Dist_Carrier.v `dec_consumed_overrun_safe`
// made executable): a truncated or hostile frame prefix returns a named
// `HsWireError`, NEVER over-reads past the buffer. LAW (rejection/no-over-read):
// ∀ b . decode(b) ∈ {Ok(frame)} ∪ HsWireError, no read outside b[0..b.len].
fn fuzzLenPrefix(comptime raw: []const u8) []const u8 {
    const n: u32 = @intCast(raw.len);
    const pre = [_]u8{
        @intCast(n & 0xFF),        @intCast((n >> 8) & 0xFF),
        @intCast((n >> 16) & 0xFF), @intCast((n >> 24) & 0xFF),
    };
    return pre ++ raw;
}
fn fuzzDopFrame(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [512]u8 = undefined;
    const n = smith.sliceWithHash(&buf, 0xD09_F3A3E);
    const input = buf[0..n];
    // All three decoders are pure and allocation-free; any error is acceptable,
    // a read outside `input[0..input.len]` (safety panic) is NOT.
    if (V6.decodeSendName(input)) |sn| std.mem.doNotOptimizeAway(sn) else |_| {}
    if (V6.decodeChallengeReply(input)) |r| std.mem.doNotOptimizeAway(r) else |_| {}
    if (V6.decodeChallengeAck(input)) |a| std.mem.doNotOptimizeAway(a) else |_| {}
}

test "FUZZ e21-t7: DOP handshake decoders reject/no-over-read on adversarial frames (corpus replay)" {
    try std.testing.fuzz({}, fuzzDopFrame, .{ .corpus = &.{
        fuzzLenPrefix(&[_]u8{ 'N', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 'a', 'b' }), // send_name
        fuzzLenPrefix(&[_]u8{ 'N', 1 }), // short send_name
        fuzzLenPrefix(&[_]u8{ 'N', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, 'a' }), // send_name nl≫buf: overrun bait
        fuzzLenPrefix(&([_]u8{ 'r', 0, 0, 0, 1 } ++ [_]u8{0} ** 16)), // challenge_reply (21B)
        fuzzLenPrefix(&([_]u8{ 'a', 0, 0, 0, 1 } ++ [_]u8{0} ** 16)), // challenge_ack (17B)
        fuzzLenPrefix(&[_]u8{ 'X', 0, 0 }), // bad tag
        fuzzLenPrefix(&[_]u8{}), // empty
    } });
}
