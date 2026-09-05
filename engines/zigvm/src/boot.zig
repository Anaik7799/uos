//! beam-zig M10 / S33: **boot** — gate G4 (cf. erts erl_init.c and the
//! preloaded set).
//!
//! The boot path, in miniature but with every layer real:
//!   1. atom table up
//!   2. CODE: the vendored, erlc-compiled mylists.beam is parsed (M8),
//!      translated, and LINKED with the hand-assembled server code (a tiny
//!      linker: concatenation + pc fixups — beam_load's essence)
//!   3. code index bound (M10), module registered as "mylists+eval"
//!   4. VM up (M7); init process spawns the eval SERVER; the registry (M10)
//!      binds the name "eval" to the server pid
//!   5. the DRIVER (init) resolves "eval" via the registry, then runs the
//!      G4 protocol: for each request N — send own pid, send N; the server
//!      computes sum(seq(N)) by CALLING THE COMPILED CODE and replies;
//!      driver accumulates replies IN ORDER and halts with the total.
//!
//! G4 GATE: the transcript is deterministic and equals the closed form
//! Σ N(N+1)/2 for N ∈ {3, 5, 7} → 6 + 15 + 28 = 49, under both scheduler
//! engines — and the arithmetic inside came from erlc-compiled code, so
//! this is real BEAM output running under our scheduler, registry, and
//! code index at once.
//!
//! E7.4 (DIVERGENCE 150): the KERNEL BOOT TREE. Beyond the G4 app, boot now
//! brings up the dependency-ordered set of long-lived SYSTEM processes the real
//! OTP node registers (init, erl_prim_loader, the kernel/logger supervision
//! trees, code_server, application_controller, …) — extending E6.3's 2-process
//! head (purger + literal-area collector). The oracle boots 43 processes with a
//! deterministic ~28-name `registered()` SET; the pid NUMBERS are per-node
//! nondeterministic and several of the 43 are ports/drivers (`user_drv`,
//! `standard_error`, …) with no process this single-node interpreter can model,
//! so a pid-VALUE list (`processes/0`) can never byte-match. The honest,
//! byte-comparable observation is the registered-NAME set (atoms): zigvm boots
//! the 19-name subset that is a pure idle-loop system process, PROVEN a subset of
//! (and exhaustively accounted against) the oracle's registered() set — see
//! `boot_registered`/`boot_excluded`/`oracle_registered` and the E7.4 laws
//! (boot-set name differential, boot-order dependency, boot determinism).

const std = @import("std");
const ta = @import("term_algebra.zig");
const ia = @import("instr_algebra.zig");
const proc = @import("proc.zig");
const loader = @import("beam_loader.zig");
const codeix = @import("code_index.zig");
const registry = @import("registry.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

/// Link: append `extra` after `base`, patching every pc-shaped target in
/// `extra` by +base.len. (Targets that point INTO base — cross-module
/// calls — are passed through a per-instruction whitelist instead.)
pub fn link(gpa: std.mem.Allocator, base: ia.Program, extra: []const ia.CInstr) ![]ia.CInstr {
    const off: u16 = @intCast(base.len);
    var out = try std.ArrayList(ia.CInstr).initCapacity(gpa, base.len + extra.len);
    errdefer out.deinit(gpa);
    out.appendSliceAssumeCapacity(base);
    for (extra) |ins0| {
        var ins = ins0;
        switch (ins) {
            .test_eq => |*v| v.else_to += off,
            .is_lt => |*v| v.else_to += off,
            .is_cons => |*v| v.else_to += off,
            .jump => |*v| v.to += off,
            .make_fun => |*v| v.to += off,
            .recv_eq => |*v| v.else_to += off,
            .recv_any => |*v| v.else_to += off,
            .spawn => |*v| v.to += off,
            .call => |*v| {
                // convention: targets < base.len are absolute (cross-module
                // into the compiled code); others are server-relative
                if (v.to >= 0x8000) {
                    v.to = (v.to - 0x8000) + off;
                }
            },
            else => {},
        }
        out.appendAssumeCapacity(ins);
    }
    return out.toOwnedSlice(gpa);
}

// ============================================================================
// E7.4 (DIVERGENCE 150): the kernel boot tree.
//
// The real OTP node boots 43 processes; `registered()` on that node returns a
// DETERMINISTIC set of ~28 registered NAMES. The pid NUMBERS those processes
// carry are per-node nondeterministic (and several of the 43 are ports/drivers —
// user_drv, standard_error, ... — with no process this single-node interpreter
// can model), so a pid-VALUE list (`processes/0`) can never byte-match the
// oracle. But the registered-NAME set is a set of ATOMS — byte-comparable. That
// is the honest differential observation E6.3's 2-process head is extended
// toward here: zigvm boots the subset of the oracle's registered names that IS a
// pure long-lived idle-loop SYSTEM process, in erts dependency order.
// ============================================================================

/// The full `registered()` set of the pinned oracle boot (host OTP-28, captured
/// empirically as the differential reference). Every name zigvm boots MUST be a
/// member (no fabricated name), and the COMPLEMENT is exactly the port/driver/
/// tty/io-backed + transient names below — an exhaustive accounting.
pub const oracle_registered = [_][]const u8{
    "application_controller", "code_server",          "erl_prim_loader",    "erl_signal_server",
    "erts_code_purger",       "file_server_2",        "global_group",       "global_group_check",
    "global_name_server",     "inet_db",              "init",               "kernel_refc",
    "kernel_safe_sup",        "kernel_sup",           "logger",             "logger_handler_watcher",
    "logger_proxy",           "logger_std_h_default", "logger_sup",         "rex",
    "socket_registry",        "standard_error",       "standard_error_sup", "standard_error_writer",
    "user",                   "user_drv",             "user_drv_reader",    "user_drv_writer",
};

/// The registered names DELIBERATELY NOT booted: port/driver/tty/io-backed
/// (`user*`, `standard_error*`, `logger_std_h_default`) or a transient checker
/// (`global_group_check`). Booting them would fabricate a process this
/// interpreter does not model — the honest-exclusion complement of
/// `boot_registered` within `oracle_registered`.
pub const boot_excluded = [_][]const u8{
    "global_group_check",    "logger_std_h_default", "standard_error", "standard_error_sup",
    "standard_error_writer", "user",                 "user_drv",       "user_drv_reader",
    "user_drv_writer",
};

/// The kernel boot tree zigvm actually spawns — the dependency-ordered list of
/// long-lived SYSTEM processes the oracle registers a NAME for AND that model
/// cleanly as a pure idle-loop process. Order is erts' boot order (`erl_init.c`
/// + the kernel supervision tree): init first, then the prim loader + purger,
/// then the kernel supervisors, the logger tree, the name/registry servers, and
/// finally code_server + application_controller (which depend on the loader and
/// the kernel supervisor being up). `boot_registered ++ boot_excluded` is a
/// permutation of `oracle_registered` — nothing silently dropped.
pub const boot_registered = [_][]const u8{
    "init",
    "erts_code_purger",
    "erl_prim_loader",
    "erl_signal_server",
    "kernel_sup",
    "kernel_safe_sup",
    "kernel_refc",
    "logger_sup",
    "logger",
    "logger_proxy",
    "logger_handler_watcher",
    "inet_db",
    "file_server_2",
    "global_name_server",
    "global_group",
    "rex",
    "socket_registry",
    "code_server",
    "application_controller",
};

/// A boot-order dependency edge: `node` must not boot until `needs` is already
/// registered. Modelling erts' dependency order — the "wrong load order → undef"
/// invariant (the E4 Task-3 mutant-1 theme): if the boot order is permuted so a
/// dependent boots before `needs`, its `whereis(needs)` is `null` (undef) and
/// the boot-order law reddens.
pub const BootDep = struct { node: []const u8, needs: []const u8 };
pub const boot_deps = [_]BootDep{
    .{ .node = "erts_code_purger", .needs = "init" },
    .{ .node = "erl_prim_loader", .needs = "init" },
    .{ .node = "kernel_sup", .needs = "erl_prim_loader" },
    .{ .node = "kernel_safe_sup", .needs = "kernel_sup" },
    .{ .node = "logger_sup", .needs = "kernel_sup" },
    .{ .node = "logger", .needs = "logger_sup" },
    .{ .node = "logger_proxy", .needs = "logger" },
    .{ .node = "code_server", .needs = "erl_prim_loader" },
    .{ .node = "code_server", .needs = "file_server_2" },
    .{ .node = "application_controller", .needs = "code_server" },
    .{ .node = "application_controller", .needs = "kernel_sup" },
};

fn nameMember(set: []const []const u8, name: []const u8) bool {
    for (set) |s| if (std.mem.eql(u8, s, name)) return true;
    return false;
}

pub const BootReport = struct {
    atoms_up: bool = false,
    code_loaded: bool = false,
    index_bound: bool = false,
    server_registered: bool = false,
    transcript_total: i64 = 0,
    // E6.3 (Task 3, DIVERGENCE 108): the head of the boot SYSTEM-process set — the
    // erts_code_purger and erts_literal_area_collector. The kernel spawns them so
    // the long-lived system processes that OWN code purging / literal-area
    // collection exist for the run's lifetime (the process the purge_module/2 +
    // collector BIFs are RESTRICTED to). Recorded here as `system=true` + alive.
    system_set_up: bool = false,
    // E7.4 (DIVERGENCE 150): the full kernel boot tree (extending E6.3's 2-process
    // head). `boot_names_ok` iff EVERY booted tree process is `system=true` +
    // alive AND its registered name is a real `oracle_registered` member (no
    // fabrication). `boot_registered_count` is the size of the booted registered-
    // NAME set (the byte-comparable differential observation); `boot_system_count`
    // counts all system processes (registered tree + the unregistered literal-area
    // collector).
    boot_names_ok: bool = false,
    boot_registered_count: usize = 0,
    boot_system_count: usize = 0,
};

/// The whole boot path; returns the report the gate checks.
pub fn boot(gpa: std.mem.Allocator, sched: proc.Scheduler) !BootReport {
    var report = BootReport{};

    // 1. atoms
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    report.atoms_up = true;

    // 2. code: parse + translate the REAL compiled module
    var mod = try loader.parse(gpa, @embedFile("mylists.beam"));
    defer mod.deinit();
    const t = try loader.translate(gpa, &mod, &atoms, null);
    defer {
        gpa.free(t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs); // E3.11: pc->source-location table
    }
    const sum_pc = loader.entryOf(&t, "sum", 1).?;
    const seq_pc = loader.entryOf(&t, "seq", 1).?;
    report.code_loaded = true;

    // server code (linked after the compiled module):
    //   x14 = own pid (VM convention)
    //   loop: recv reply-to pid → x2; recv N → x0;
    //         x0 = seq(N); x0 = sum(x0); send x2 x0; goto loop
    const server = [_]ia.CInstr{
        .{ .recv_any = .{ .dst = 2, .else_to = 0 } }, // +0
        .{ .recv_any = .{ .dst = 0, .else_to = 1 } }, // +1
        .{ .call = .{ .to = @intCast(0x8000 + 6) } }, // +2 → helper below
        .{ .send_to = .{ .pid = .{ .x = 2 }, .msg = .{ .x = 0 } } }, // +3
        .{ .jump = .{ .to = 0 } }, // +4 loop
        .{ .halt = .{ .src = .nil } }, // +5 (unreachable)
        // +6 helper: x0 = sum(seq(x0)) via the COMPILED code
        .{ .call = .{ .to = @intCast(seq_pc) } }, // absolute: < base
        .{ .call = .{ .to = @intCast(sum_pc) } },
        .ret, // +8
    };
    // driver: x15 = server pid (spawn arg); requests 3, 5, 7; total in x5
    const driver = [_]ia.CInstr{
        // +9  (driver entry)
        .{ .move = .{ .src = .{ .imm = 0 }, .dst = 5 } },
        // request 3
        .{ .send_to = .{ .pid = .{ .x = 15 }, .msg = .{ .x = 14 } } },
        .{ .send_to = .{ .pid = .{ .x = 15 }, .msg = .{ .imm = 3 } } },
        .{ .recv_any = .{ .dst = 6, .else_to = 3 } },
        .{ .add = .{ .a = .{ .x = 5 }, .b = .{ .x = 6 }, .dst = 5 } },
        // request 5
        .{ .send_to = .{ .pid = .{ .x = 15 }, .msg = .{ .x = 14 } } },
        .{ .send_to = .{ .pid = .{ .x = 15 }, .msg = .{ .imm = 5 } } },
        .{ .recv_any = .{ .dst = 6, .else_to = 7 } },
        .{ .add = .{ .a = .{ .x = 5 }, .b = .{ .x = 6 }, .dst = 5 } },
        // request 7
        .{ .send_to = .{ .pid = .{ .x = 15 }, .msg = .{ .x = 14 } } },
        .{ .send_to = .{ .pid = .{ .x = 15 }, .msg = .{ .imm = 7 } } },
        .{ .recv_any = .{ .dst = 6, .else_to = 11 } },
        .{ .add = .{ .a = .{ .x = 5 }, .b = .{ .x = 6 }, .dst = 5 } },
        .{ .halt = .{ .src = .{ .x = 5 } } },
    };
    const linked_server = try link(gpa, t.prog, &server);
    defer gpa.free(linked_server);
    const full = try link(gpa, linked_server, &driver);
    defer gpa.free(full);
    const server_entry: u16 = @intCast(t.prog.len);
    const driver_entry: u16 = @intCast(linked_server.len);

    // 3. code index
    var idx = codeix.CodeIndex.init(gpa);
    defer idx.deinit();
    try idx.load("boot", full);
    report.index_bound = idx.resolve("boot") != null;

    // 4. VM + registry
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    var reg = registry.Registry.init(gpa);
    defer reg.deinit();

    const boot_prog = idx.resolve("boot").?;
    const server_pid = try vm.spawn(boot_prog, server_entry, null);
    const eval_atom = try atoms.intern("eval");
    try reg.register(eval_atom, server_pid, true);
    report.server_registered = reg.whereis(eval_atom) == server_pid;

    // 5. the driver resolves the server THROUGH THE REGISTRY
    const resolved = reg.whereis(eval_atom).?;
    const driver_pid = try vm.spawn(boot_prog, driver_entry, @intCast(resolved));

    // 5b. E7.4 (DIVERGENCE 150): the kernel boot tree — extending E6.3's 2-process
    // head (erts_code_purger + erts_literal_area_collector) to the dependency-
    // ordered set of long-lived SYSTEM processes the real node registers. Each is
    // an idle receive loop (`system=true`), spawned in `boot_registered` order and
    // registered under its OTP name. Before each node boots, its declared boot-
    // dependency names must ALREADY be registered — the "wrong load order → undef"
    // invariant: a permuted order makes `whereis(needs)` null and this loop fails.
    const idle_entry: u16 = server_entry; // reuse the server's recv-loop head
    var boot_names_ok = true;
    for (boot_registered) |name| {
        // boot-order dependency gate (undef == whereis null on a not-yet-booted dep)
        for (boot_deps) |dep| {
            if (std.mem.eql(u8, dep.node, name)) {
                const need_atom = try atoms.intern(dep.needs);
                if (reg.whereis(need_atom) == null) return error.BootDependencyUnmet;
            }
        }
        const sys_pid = try vm.spawn(boot_prog, idle_entry, null);
        vm.procs.items[sys_pid].system = true;
        const name_atom = try atoms.intern(name);
        try reg.register(name_atom, sys_pid, true);
        // every booted name must be a REAL oracle registered() name (no fabrication)
        boot_names_ok = boot_names_ok and
            nameMember(&oracle_registered, name) and
            vm.procs.items[sys_pid].system and vm.procs.items[sys_pid].alive;
    }
    // the erts_literal_area_collector is one of the 43 processes but carries NO
    // registered name (unregistered system process) — spawned system, unnamed.
    const collector_pid = try vm.spawn(boot_prog, idle_entry, null);
    vm.procs.items[collector_pid].system = true;

    report.boot_names_ok = boot_names_ok and vm.procs.items[collector_pid].system;
    report.boot_registered_count = boot_registered.len;
    // count all live system processes (the registered tree + the unregistered
    // collector) — the boot SET size zigvm honestly models of the oracle's 43.
    var syscount: usize = 0;
    for (vm.procs.items) |pr| {
        if (pr.system and pr.alive) syscount += 1;
    }
    report.boot_system_count = syscount;
    // E6.3 compatibility: system_set_up stays true iff the purger head + collector
    // are up (erts_code_purger is the FIRST registered tree node here).
    report.system_set_up = reg.whereis(try atoms.intern("erts_code_purger")) != null and
        vm.procs.items[collector_pid].system and vm.procs.items[collector_pid].alive;

    try sched.drive(&vm, 9, 60_000);

    const dm = &vm.procs.items[driver_pid].machine;
    if (dm.status != .halted) return error.BootDidNotComplete;
    report.transcript_total = @as(i64, @bitCast(dm.result)) >> 4;
    return report;
}

// ============================================================================
// G4 gate
// ============================================================================

test "G4 GATE: boot to a registry-bound eval server running compiled code" {
    const gpa = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0x6004 };

    // Σ N(N+1)/2 for N ∈ {3,5,7} = 6 + 15 + 28 = 49
    const rr = try boot(gpa, .round_robin);
    try expectLaw(rr.atoms_up and rr.code_loaded and rr.index_bound and rr.server_registered, "boot: every stage came up", cfg, 0);
    // E6.3 (DIVERGENCE 108): the purger/collector SYSTEM-process set came up and
    // both are flagged `system=true` + alive (the boot-set head the purge_module/2
    // + collector BIFs are restricted to).
    try expectLaw(rr.system_set_up, "boot: the purger/collector system-process set is up", cfg, 0);
    // E7.4 (DIVERGENCE 150): the full kernel boot tree came up — every booted tree
    // process is a real oracle registered() name flagged system=true + alive.
    try expectLaw(rr.boot_names_ok, "boot: the kernel boot tree is up (all names real, all system+alive)", cfg, 0);
    try expectLaw(rr.boot_registered_count == boot_registered.len, "boot: the registered-name set has the modelled size", cfg, 0);
    try expectLaw(rr.boot_system_count == boot_registered.len + 1, "boot: system-process count == tree + unregistered collector", cfg, 0);
    try expectLaw(rr.transcript_total == 49, "boot: transcript equals the closed form", cfg, 0);

    // engine-independence (the M7 law, re-checked at the boot level)
    for (0..4) |i| {
        const en = try boot(gpa, .{ .seeded = cfg.seed +% i });
        try expectLaw(en.transcript_total == 49, "boot: transcript engine-invariant", cfg, i);
        // boot DETERMINISM: two boots denote the same boot set (a wedged/divergent
        // boot is a failed law) — fuel-bounded by `drive`.
        try expectLaw(en.boot_registered_count == rr.boot_registered_count and
            en.boot_system_count == rr.boot_system_count and
            en.boot_names_ok == rr.boot_names_ok, "boot: boot-set determinism (two boots denote identically)", cfg, i);
    }
}

// ============================================================================
// E7.4 (DIVERGENCE 150): the boot-set registered-NAME differential + boot-order
// dependency laws. The pid-VALUE list (`processes/0`) can never byte-match the
// oracle (per-node pid numbering + un-modellable port/driver processes), so the
// honest byte-comparable observation is the registered-NAME set (atoms).
// ============================================================================

/// True iff `order` respects every `boot_deps` edge (each `needs` appears before
/// its `node`). The dependency-order law's decision procedure — `boot()`
/// enforces the SAME predicate incrementally via the registry `whereis` gate
/// (undef == whereis null on a not-yet-booted dependency).
pub fn bootOrderValid(order: []const []const u8) bool {
    for (boot_deps) |dep| {
        var ni: ?usize = null;
        var di: ?usize = null;
        for (order, 0..) |nm, k| {
            if (std.mem.eql(u8, nm, dep.node)) ni = k;
            if (std.mem.eql(u8, nm, dep.needs)) di = k;
        }
        if (ni == null or di == null or di.? >= ni.?) return false;
    }
    return true;
}

test "E7.4 boot-set registered-NAME differential: booted names ⊆ oracle registered(); the complement is exactly the port/driver set" {
    const cfg = LawConfig{ .seed = 0x7004 };

    // SET EQUALITY: boot_registered ++ boot_excluded is a PERMUTATION of the
    // oracle's registered() set — nothing fabricated, nothing silently dropped.
    try expectLaw(boot_registered.len + boot_excluded.len == oracle_registered.len,
        "boot-set: |booted| + |excluded| == |oracle registered()|", cfg, 0);
    // every booted name is a REAL oracle registered() name (no fabrication)
    for (boot_registered, 0..) |nm, i| {
        try expectLaw(nameMember(&oracle_registered, nm), "boot-set: every booted name is a real oracle name", cfg, i);
        // booted and excluded are DISJOINT
        try expectLaw(!nameMember(&boot_excluded, nm), "boot-set: booted ∩ excluded == ∅", cfg, i);
    }
    // every excluded name is a real oracle name too (the honest complement)
    for (boot_excluded, 0..) |nm, i| {
        try expectLaw(nameMember(&oracle_registered, nm), "boot-set: every excluded name is a real oracle name", cfg, i);
    }
    // every oracle name is EITHER booted OR excluded (exhaustive accounting)
    for (oracle_registered, 0..) |nm, i| {
        try expectLaw(nameMember(&boot_registered, nm) or nameMember(&boot_excluded, nm),
            "boot-set: every oracle name is booted xor excluded", cfg, i);
    }
}

test "E7.4 boot-order dependency law: boot_registered respects every dependency edge; a permuted order is rejected (wrong load order → undef)" {
    const gpa = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0x7005 };

    // the shipped order is dependency-valid
    try expectLaw(bootOrderValid(&boot_registered), "boot-order: boot_registered respects every dependency edge", cfg, 0);

    // a PERMUTED order that moves a dependent BEFORE its dependency is REJECTED —
    // model of "wrong load order → undef" (the E4 Task-3 mutant-1 theme). Build a
    // copy of boot_registered with code_server hoisted before erl_prim_loader.
    var permuted: std.ArrayList([]const u8) = .empty;
    defer permuted.deinit(gpa);
    // code_server first (it depends on erl_prim_loader + file_server_2, neither yet placed)
    try permuted.append(gpa, "code_server");
    for (boot_registered) |nm| {
        if (!std.mem.eql(u8, nm, "code_server")) try permuted.append(gpa, nm);
    }
    try expectLaw(!bootOrderValid(permuted.items), "boot-order: a dependent-before-dependency permutation is rejected", cfg, 0);
}
