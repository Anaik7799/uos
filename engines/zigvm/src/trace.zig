//! beam-zig M10 / S29: **tracing** (cf. erts erl_trace.c, beam_bp.c) —
//! formalized as an ADDITIONAL OBSERVATION on the execution LTS.
//!
//! The one governing law, adopted from the map verbatim:
//!
//!   TRACE TRANSPARENCY — enabling tracing must not change any program
//!   denotation: same final results, same reduction counts, same mailbox
//!   sequences, same event trace. Tracing only ENRICHES the observation.
//!
//! Implementation: a per-VM optional sink that grant() feeds with
//! per-slice snapshots (pid, pc-before, reductions-before). The sink write
//! path never touches machine state — transparency is architectural, then
//! verified by twin-VM law anyway (the M5 lesson: verify the architecture).
//!
//! beam_bp-style breakpoints and coverage counters are later slices of the
//! same observation; they inherit the transparency law unchanged.
//!
//! E7.6 (S29 tracing surface): the USER-VISIBLE tracing BIFs — the sequential-
//! trace token (`seq_trace/2` + `seq_trace_info/1`), the `dt_*` dynamic-trace
//! tags, `seq_trace_print/1,2`, and `trace_info/2` — live in
//! `bifs/trace_bifs.zig`. The honestly-observable, version-stable subset flipped
//! EQ (token round-trips, non-dtrace constants, empty-trace defaults); the trace
//! DELIVERY surface (a tracer process receiving repr-coupled trace tuples,
//! match-spec breakpoints, sessions) re-binds to `deferred-trace-delivery` and
//! would, when landed, inherit THIS module's TRANSPARENCY law verbatim.
//!
//! gap-tracing-e7 (S29, DIVERGENCE 158 extension): the DELIVERY surface is now
//! partly landed — `erlang:trace/3`'s send/receive events (e50-tracing) plus
//! `erlang:trace_pattern/2,3` + the `call` event (`{trace,Pid,call,{M,F,Args}}`,
//! delivered when a `call`-traced process dispatches a pattern-matched MFA;
//! `bifs/trace_bifs.zig` + the `dispatchMFA` trace trap). Still deferred (never a
//! fabricated event): compiled match-spec BODIES / `{return_trace}` / `return_to`,
//! the `meta` tracer, trace SESSIONS, and `erts_internal:trace/3,4`. The `call`
//! trap builds the args list with registers intact and the run loop breaks on
//! `pending` at once, so the untraced dispatch path stays byte-identical — the
//! transparency argument this module's law re-checks.

const std = @import("std");
const ta = @import("term_algebra.zig");
const ia = @import("instr_algebra.zig");
const proc = @import("proc.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

pub const TraceEvent = struct { pid: proc.Pid, pc: usize, reductions: u64 };

/// Drive a VM exactly like Scheduler.drive, but optionally feeding a trace
/// sink before every grant. (Kept beside the scheduler rather than inside
/// it so the untraced path is BYTE-IDENTICAL code — the strongest possible
/// transparency argument, then the law re-checks it observationally.)
pub fn driveTraced(
    vm: *proc.Vm,
    sched: proc.Scheduler,
    fuel_per_slice: u64,
    max_slices: usize,
    sink: ?*std.ArrayList(TraceEvent),
    gpa: std.mem.Allocator,
) !void {
    _ = sched;
    var slice: usize = 0;
    var cursor: proc.Pid = 0;
    while (slice < max_slices and vm.liveCount() > 0) : (slice += 1) {
        const n: u32 = @intCast(vm.procs.items.len);
        var pid: proc.Pid = cursor;
        var k: u32 = 0;
        while (k < n) : (k += 1) {
            const cand: proc.Pid = (cursor + k) % n;
            const p = vm.procs.items[cand];
            if (p.alive and p.machine.status == .running) {
                pid = cand;
                break;
            }
        }
        cursor = (pid + 1) % n;
        if (sink) |s| {
            const m = &vm.procs.items[pid].machine;
            try s.append(gpa, .{ .pid = pid, .pc = m.pc, .reductions = m.reductions });
        }
        try vm.grant(pid, fuel_per_slice);
    }
}

// ============================================================================
// The law
// ============================================================================

const ring: ia.Program = &.{
    // 0: worker — receive next-pid, receive token, add own pid, forward
    .{ .recv_any = .{ .dst = 2, .else_to = 0 } },
    .{ .recv_any = .{ .dst = 3, .else_to = 1 } },
    .{ .add = .{ .a = .{ .x = 3 }, .b = .{ .x = 14 }, .dst = 3 } },
    .{ .send_to = .{ .pid = .{ .x = 2 }, .msg = .{ .x = 3 } } },
    .{ .halt = .{ .src = .{ .x = 3 } } },
    // 5: collector
    .{ .recv_any = .{ .dst = 0, .else_to = 5 } },
    .{ .halt = .{ .src = .{ .x = 0 } } },
};

fn buildRing(vm: *proc.Vm) !proc.Pid {
    const collector = try vm.spawn(ring, 5, null);
    var workers: [4]proc.Pid = undefined;
    for (0..4) |k| workers[k] = try vm.spawn(ring, 0, null);
    for (0..4) |k| {
        const target = vm.procs.items[workers[k]];
        const next: proc.Pid = if (k + 1 < 4) workers[k + 1] else collector;
        try vm.signal(collector, workers[k], .{ .message = FinalTerms.int(&target.machine.ctx, next) });
    }
    const t0 = vm.procs.items[workers[0]];
    try vm.signal(collector, workers[0], .{ .message = FinalTerms.int(&t0.machine.ctx, 500) });
    return collector;
}

test "TRACE TRANSPARENCY: traced and untraced twins are observationally identical" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x76AC };

    var vm_plain = try proc.Vm.init(gpa, &atoms);
    defer vm_plain.deinit();
    var vm_traced = try proc.Vm.init(gpa, &atoms);
    defer vm_traced.deinit();

    const c1 = try buildRing(&vm_plain);
    const c2 = try buildRing(&vm_traced);

    var sink: std.ArrayList(TraceEvent) = .empty;
    defer sink.deinit(gpa);

    try driveTraced(&vm_plain, .round_robin, 6, 3000, null, gpa);
    try driveTraced(&vm_traced, .round_robin, 6, 3000, &sink, gpa);

    // identical results…
    const m1 = &vm_plain.procs.items[c1].machine;
    const m2 = &vm_traced.procs.items[c2].machine;
    try expectLaw(m1.status == .halted and m2.status == .halted, "trace: both rings completed", cfg, 0);
    try expectLaw(m1.result == m2.result, "trace: identical results", cfg, 0);
    // …identical reduction counts, per process (the sharp transparency edge:
    // tracing must not consume fuel — the M10 mutant target)
    for (vm_plain.procs.items, vm_traced.procs.items) |p1, p2| {
        try expectLaw(p1.machine.reductions == p2.machine.reductions, "trace: identical reductions per process", cfg, 0);
    }
    // …identical event traces (sends/delivers/exits, stamps and all)
    try expectLaw(vm_plain.events.items.len == vm_traced.events.items.len, "trace: identical event counts", cfg, 0);
    for (vm_plain.events.items, vm_traced.events.items) |e1, e2| {
        try expectLaw(std.meta.eql(e1, e2), "trace: identical event streams", cfg, 0);
    }
    // …and the trace itself is a real enrichment
    try expectLaw(sink.items.len > 0, "trace: the observation is non-empty", cfg, 0);
    // trace snapshots are per-pid monotone in reductions (a sanity law on
    // the observation itself)
    var last_red: [8]?u64 = @splat(null);
    for (sink.items) |ev| {
        if (last_red[ev.pid]) |prev|
            try expectLaw(ev.reductions >= prev, "trace: per-pid reduction snapshots are monotone", cfg, 0);
        last_red[ev.pid] = ev.reductions;
    }
}
