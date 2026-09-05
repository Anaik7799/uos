//! vm_all — the suite aggregator: the single root the canonical gate compiles
//! and runs (`zig test src/vm_all.zig`). Semantic domain: none of its own. It
//! re-exports every module so `std.testing.refAllDecls` pulls in that
//! module's tests, which is what makes the law suite TOTAL — a module absent
//! from this file is a module whose laws never run. Adding a module to `src/`
//! therefore means adding it here; that omission is the failure mode this
//! file exists to prevent.
pub const term_algebra = @import("term_algebra.zig");
pub const bitstring_algebra = @import("bitstring_algebra.zig");
pub const atom_table = @import("atom_table.zig");
pub const config = @import("config.zig");
pub const otlp = @import("otlp.zig");
pub const otlp_test = @import("otlp_test.zig");
// harness-P6 finding: atomics_algebra was reached only TRANSITIVELY (via
// bifs/atomics.zig), so its tests ran under the monolith but no shard key
// owned their namespace — the shard-union law caught it. The aggregator now
// lists every law-carrying module EXPLICITLY.
pub const atomics_algebra = @import("atomics_algebra.zig");
pub const instr_algebra = @import("instr_algebra.zig");
pub const map_algebra = @import("map_algebra.zig");
pub const bin_algebra = @import("bin_algebra.zig");
pub const term_hash = @import("term_hash.zig");
pub const pattern_algebra = @import("pattern_algebra.zig");
pub const mailbox_algebra = @import("mailbox_algebra.zig");
pub const gc = @import("gc.zig");
pub const proc = @import("proc.zig");
pub const timer_wheel = @import("timer_wheel.zig");
pub const beam_loader = @import("beam_loader.zig");
pub const transform = @import("transform.zig");
pub const etf = @import("etf.zig");
pub const unicode = @import("unicode.zig");
pub const code_index = @import("code_index.zig");
pub const code_server = @import("code_server.zig");
pub const registry = @import("registry.zig");
pub const trace = @import("trace.zig");
pub const re_engine = @import("re_engine.zig");
pub const boot = @import("boot.zig");
pub const matchspec = @import("matchspec.zig");
pub const eval = @import("eval.zig");
pub const erl_expr = @import("erl_expr.zig");
pub const ets_algebra = @import("ets_algebra.zig");
pub const ets_hamt = @import("ets_hamt.zig");
pub const port_algebra = @import("port_algebra.zig");
pub const os_port = @import("os_port.zig"); // E5.4: the live os-port driver (Stratum C)
pub const socket_algebra = @import("socket_algebra.zig"); // gap-socket-real-tcp: real gen_tcp/gen_udp transport (Stratum C)
pub const nif_resource = @import("nif_resource.zig");
pub const nif_env = @import("nif_env.zig");
pub const nif = @import("nif.zig");
pub const diag = @import("diag.zig");
pub const mcdc_tap = @import("mcdc_tap.zig"); // E28-T2: automated per-condition MC/DC capture
pub const smp_trace = @import("smp_trace.zig"); // S-epoch SMP-OBS: lock-order checker + contention + seed replay + its LAWs
pub const jit_asm = @import("jit_asm.zig"); // jit-asm-x86-64: pure x86-64 encoder+decoder (JIT epoch slice #2, LAW L1 encoder bijection)
pub const jit_exec = @import("jit_exec.zig"); // jit-exec-buffer: Stratum-C W^X exec-memory seam (JIT epoch slice #1, LAW L5 + first real native execution)
pub const jit_codegen = @import("jit_codegen.zig"); // jit-codegen-arith: template JIT — first REAL native codegen (engine #4, LAW L2/L3), JIT epoch slice #3
pub const substrate_effect = @import("substrate/effect.zig"); // E32-T4: the E-substrate effect-algebra core (Model/Trace, host-free)
pub const substrate_alloc = @import("substrate/alloc.zig"); // E33-T1: Real[Alloc] — the first host-touching substrate handler
pub const substrate_sched = @import("substrate/sched.zig"); // E34-T2: Real[Sched] — the second host-touching substrate handler (per-core run-queue)
pub const substrate_reactor = @import("substrate/reactor.zig"); // E35-T1: Real[IO] — the third host-touching substrate handler (io_uring-shaped completion reactor)
pub const substrate_row = @import("substrate/row.zig"); // E36-T2: the effect ROW — Alloc+IO+Clock composed; handlers commute on disjoint effects
pub const substrate_boot = @import("substrate/boot.zig"); // E39-T1: the full Stratum-C boot — Real[Sched] running Real[Alloc] fibers
pub const dispatch = @import("dispatch.zig");
pub const bif_table = @import("bifs/bif_table.zig");
pub const bif_dispatch = @import("bifs/dispatch.zig");
pub const bif_erlang = @import("bifs/erlang.zig");
pub const bif_ets = @import("bifs/ets.zig");
pub const bif_checksum = @import("bifs/checksum.zig");
pub const bif_file = @import("bifs/file.zig");
pub const prim_file = @import("prim_file.zig");
pub const bif_misc = @import("bifs/misc.zig");
pub const bif_io_format = @import("bifs/io_format.zig"); // gap-io-format: io_lib:format interpreter
pub const bif_dist_ctrl = @import("bifs/dist_ctrl.zig");
pub const bif_fun_info = @import("bifs/fun_info.zig");
pub const bif_records = @import("bifs/records.zig");
pub const bif_re = @import("bifs/re.zig");
pub const bif_trace = @import("bifs/trace_bifs.zig");
pub const bif_code = @import("bifs/code.zig"); // E5.2b: code-server query BIF laws
pub const time_algebra = @import("time_algebra.zig"); // E5.8b/S21: OS clock + env seam
pub const bif_time = @import("bifs/time.zig"); // E5.8b: erlang: monotonic/system time family
pub const bif_os = @import("bifs/os.zig"); // E5.8b: the os: module family
pub const dist = @import("dist.zig");
pub const dist_tailscale = @import("dist_tailscale.zig");
pub const agent_codegen = @import("agent_codegen.zig"); // verify-agent-codegen: agent-authored units admitted only by a machine-checked Aeon contract
pub const cli = @import("cli.zig");

pub const boot_script = @import("boot_script.zig");
pub const app_controller = @import("app_controller.zig"); // gap-app-boot-engine: ensure_all_started
pub const release_upgrade = @import("release_upgrade.zig"); // gap-release-handler: the relup low-level fold
pub const crdt = @import("crdt.zig");
pub const gossip = @import("gossip.zig"); // e18-t5: mesh substrate under law (PeerView CvRDT + MeshState = mesh_spec.qnt)
pub const init_lifecycle = @import("init_lifecycle.zig");
pub const slm_bif = @import("slm_bif.zig");
pub const apoptosis = @import("apoptosis.zig");
pub const a2ui = @import("a2ui.zig");
pub const event_log = @import("event_log.zig");
pub const event_wal = @import("event_wal.zig");
pub const event_wal_test = @import("event_wal_test.zig");
test {
    @import("std").testing.refAllDecls(@This());
}
pub const epmd_bridge = @import("epmd_bridge.zig");
