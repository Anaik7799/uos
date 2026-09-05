//! Semantic Domain: Continuous Apoptosis (Process preemption and random termination)
//! Design Purpose: Simulates process deaths to enforce continuous recovery and homeostasis under chaos.
//! Oracle/Final Encoding: Oracle is an immortal machine; Final Encoding is a periodic random killer.
//! Operations: schedule_next, tick
//! Observations: Alive process count, vclock
//! Invariants: Does not kill processes with experimental_apoptosis_immunity. Always reschedules the next tick.
//! Algebraic Laws: 
//!   - Preemption law: immortal machine trace is trace-equivalent to mortal machine trace with infinite retries (assuming external supervisor).
//! Scope limits: Stratum B engine. Quarantined to experimental config flag.

const std = @import("std");
const proc = @import("proc.zig");
const FinalTerms = @import("term_algebra.zig").FinalTerms;

pub const config = struct {
    pub var experimental_apoptosis_immunity: bool = false;
};

pub var experimental_apoptosis_rate_ms: ?u64 = null;
var prng: ?std.Random.DefaultPrng = null;

pub fn schedule_next(vm: *proc.Vm) !void {
    const rate = experimental_apoptosis_rate_ms orelse return;
    const deadline = vm.vclock + rate;
    const idx = vm.timer_meta.items.len;
    const wid = try vm.timers.start(deadline, idx);
    try vm.timer_meta.append(vm.gpa, .{
        .kind = .apoptosis_tick,
        .owner = 0,
        .deadline = deadline,
        .wheel_id = wid,
    });
}

pub fn tick(vm: *proc.Vm) !void {
    _ = experimental_apoptosis_rate_ms orelse return;

    if (prng == null) {
        prng = std.Random.DefaultPrng.init(0xA90970515);
    }
    const random = prng.?.random();

    var active_pids: std.ArrayList(proc.Pid) = .empty;
    defer active_pids.deinit(vm.gpa);

    for (vm.procs.items, 0..) |p, idx| {
        if (p.alive) {
            try active_pids.append(vm.gpa, @intCast(idx));
        }
    }

    if (active_pids.items.len > 0) {
        const victim_idx = random.uintLessThan(usize, active_pids.items.len);
        const victim_pid = active_pids.items[victim_idx];

        if (vm.procs.items[victim_pid].machine.apoptosis_immune and config.experimental_apoptosis_immunity) {
            // immune, skip kill
        } else {
            // Execute erlang:exit(Pid, kill)
            // Untrappable kill stops the process.
            const kill_atom = try vm.atoms.intern("kill");
            const reason = FinalTerms.atom(&vm.procs.items[victim_pid].machine.ctx, kill_atom);
            try vm.terminate(victim_pid, reason);
        }
    }

    // Reschedule the next tick
    try schedule_next(vm);
}
