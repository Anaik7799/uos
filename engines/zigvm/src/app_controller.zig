//! app_controller — the minimal `init` + `application_controller` +
//! `application:ensure_all_started/1` boot engine (gap-app-boot-engine, first
//! increment). The P-APP keystone: boot a `.app`-specified SUPERVISION TREE onto
//! the resident node (E45 `Scheduler.driveResident`).
//!
//! ## Semantic domain
//! `ensureAllStarted(App)` starts App's `{applications,Deps}` dependencies FIRST
//! (DFS post-order = OTP's serial topological start), then App itself: for an app
//! with `{mod,{M,Args}}` it starts the app's supervision tree (`M:start(normal,
//! Args)` → `{ok, SupPid}` in OTP `application_master`; modeled here by the
//! controller spawning a trapping supervisor + a worker, until `gap-fs-autoloader`
//! can load a real `supervisor.beam`). A library app (`mod == null`, e.g.
//! kernel/stdlib) just marks started. Idempotent (`{already_started,_}`); a cycle
//! is `error.CircularDependency`.
//!
//! ## Why a host-side Zig driver
//! `init`/`application_master` are themselves the host-side boot drivers in OTP;
//! `cli.runMulti`/`boot.zig` already play that role. The supervisor + worker are
//! REAL, linked, resident VM processes (spawn + trap_exit + links + signal
//! delivery), so `driveResident` keeps them up and a worker crash is trapped +
//! supervised on the already-EXACT signal core — exactly the resident-node-smoke
//! shape, now assembled by the boot engine instead of by hand.
const std = @import("std");
const proc = @import("proc.zig");
const ta = @import("term_algebra.zig");
const ia = @import("instr_algebra.zig");
const boot_script = @import("boot_script.zig");
const code_index = @import("code_index.zig");
const etf = @import("etf.zig");
const FinalTerms = ta.FinalTerms;
const AppSpec = boot_script.AppSpec;
const AtomIdx = ta.AtomIdx;
const Pid = proc.Pid;

pub const AppError = error{ AppNotFound, CircularDependency, StartUndef, OutOfMemory };

/// A started app's tree: `sup`/`worker` are the spawned pids; a LIBRARY app (no
/// supervision tree) has `has_tree = false`.
pub const StartedApp = struct { sup: Pid = 0, worker: Pid = 0, has_tree: bool = false };

// A trapping SUPERVISOR: drain any {'EXIT',_,_} messages, then suspend (the
// message-draining receive loop that avoids the lost-wakeup busy-spin). A bare
// WORKER blocks in receive forever.
const supervisor_prog: ia.Program = &.{
    .{ .recv_any = .{ .dst = 0, .else_to = 2 } }, // 0: consume a message; empty → 2
    .{ .jump = .{ .to = 0 } }, //                    1: loop (drain the next)
    .{ .wait = .{ .to = 0 } }, //                    2: suspend; resume at 0 on a new signal
};
const worker_prog: ia.Program = &.{.{ .wait = .{ .to = 0 } }};

pub const AppController = struct {
    gpa: std.mem.Allocator,
    vm: *proc.Vm,
    specs: []const AppSpec,
    started: std.AutoHashMap(AtomIdx, StartedApp),
    starting: std.AutoHashMap(AtomIdx, void),
    /// e47-a6b: an optional CODE-BEARING template process (a linked node's
    /// entry, e.g. cli.runMulti's p0). When set, a `{mod,{M,Args}}` app
    /// dispatches `M:start(normal, Args)` into the REAL loaded code (the E4.1
    /// spawn_mfa machinery: code inheritance + cross-heap arg copy + export
    /// resolution) instead of the hand-built model tree. `null` (default) =
    /// the landed model behavior, byte-identical.
    template: ?Pid = null,

    pub fn init(gpa: std.mem.Allocator, vm: *proc.Vm, specs: []const AppSpec) AppController {
        return .{
            .gpa = gpa,
            .vm = vm,
            .specs = specs,
            .started = std.AutoHashMap(AtomIdx, StartedApp).init(gpa),
            .starting = std.AutoHashMap(AtomIdx, void).init(gpa),
        };
    }

    pub fn deinit(self: *AppController) void {
        self.started.deinit();
        self.starting.deinit();
    }

    fn specLookup(self: *AppController, name: AtomIdx) ?*const AppSpec {
        for (self.specs) |*s| if (s.name == name) return s;
        return null;
    }

    pub fn isStarted(self: *AppController, name: AtomIdx) bool {
        return self.started.contains(name);
    }

    /// Start `name` and (deps-first, serial/topological) every application it
    /// depends on. Idempotent; a dependency cycle is `error.CircularDependency`.
    pub fn ensureAllStarted(self: *AppController, name: AtomIdx) AppError!void {
        if (self.started.contains(name)) return; // {already_started,_} → no-op
        const spec = self.specLookup(name) orelse {
            // a dependency with no .app spec (e.g. kernel/stdlib) → library no-op.
            try self.started.put(name, .{ .has_tree = false });
            return;
        };
        if (self.starting.contains(name)) return error.CircularDependency;
        try self.starting.put(name, {});
        for (spec.applications) |dep| try self.ensureAllStarted(dep); // DEPS FIRST
        try self.startApplication(spec);
        _ = self.starting.remove(name);
    }

    /// M:start(normal, Args) → {ok, SupPid}. For a `{mod,_}` app, spawn the app's
    /// supervision tree (trapping supervisor + linked worker) as resident VM
    /// processes; a library app just marks started.
    fn startApplication(self: *AppController, spec: *const AppSpec) AppError!void {
        if (spec.mod == null) {
            try self.started.put(spec.name, .{ .has_tree = false });
            return;
        }
        if (self.template) |tpl| return self.startApplicationReal(spec, tpl);
        const sup = try self.vm.spawn(supervisor_prog, 0, null);
        self.vm.procs.items[sup].machine.trap_exit = true; // supervisor traps child exits
        const worker = try self.vm.spawn(worker_prog, 0, null);
        try self.vm.procs.items[sup].links.append(self.gpa, worker);
        try self.vm.signal(sup, worker, .link_req);
        try self.vm.drainSignals(worker);
        try self.started.put(spec.name, .{ .sup = sup, .worker = worker, .has_tree = true });
    }

    /// e47-a6b: REAL M:start — dispatch `M:start(normal, Args)` into the
    /// template's LOADED code space. The child inherits the template's linked
    /// exports/literals/locs (E4.1 `inheritCode`), the argument list is built
    /// in the template's heap and CROSS-HEAP-copied into the child's registers
    /// by `resolveSpawnMFA` (the spawn/3 machinery), and the entry pc is the
    /// linked export `M:start/2` — an unresolvable start is `error.StartUndef`
    /// (fail-closed; no half-started app row). The spawned root rides
    /// `driveResident` exactly like the model tree it replaces.
    fn startApplicationReal(self: *AppController, spec: *const AppSpec, tpl: Pid) AppError!void {
        const tp = self.vm.procs.items[tpl];
        const tm = &tp.machine;
        const child = self.vm.spawn(tp.prog, 0, null) catch return error.OutOfMemory;
        const cp = self.vm.procs.items[child];
        cp.machine.group_leader = tm.group_leader;
        self.vm.inheritCode(child, tm) catch return error.OutOfMemory;
        const mod = spec.mod.?;
        const normal_t = FinalTerms.atom(&tm.ctx, self.vm.atoms.intern("normal") catch return error.OutOfMemory);
        const start_t = FinalTerms.atom(&tm.ctx, self.vm.atoms.intern("start") catch return error.OutOfMemory);
        const mod_t = FinalTerms.atom(&tm.ctx, mod.m);
        // [normal, Args] — built in the template heap; resolveSpawnMFA copies
        // each element cross-heap into the child's x0..x1.
        var args_l = FinalTerms.nil(&tm.ctx);
        args_l = FinalTerms.cons(&tm.ctx, mod.args, args_l) catch return error.OutOfMemory;
        args_l = FinalTerms.cons(&tm.ctx, normal_t, args_l) catch return error.OutOfMemory;
        if (self.vm.resolveSpawnMFA(cp, tm, mod_t, start_t, args_l)) |_| {
            // e48-appctl-handoff: the APPLICATION-MASTER shape — the root must
            // STAY RESIDENT after M:start returns (proc_lib-supervised trees
            // shut down when their PARENT dies; a halting root would take the
            // whole tree with it — observed live: the supervisor terminated
            // the moment the root halted). A 2-instruction private trampoline
            // in the root's OWN dyn_code: dispatch M:start(normal, Args)
            // (args already cross-heap in x0/x1 via resolveSpawnMFA), then
            // suspend forever as the master.
            const start_f = self.vm.atoms.intern("start") catch return error.OutOfMemory;
            const base: u32 = @intCast(cp.machine.code_base + cp.machine.dyn_code.items.len);
            cp.machine.dyn_code.append(self.gpa, .{ .call_ext_code = .{ .module = mod.m, .func = start_f, .arity = 2, .push_ret = true } }) catch return error.OutOfMemory;
            cp.machine.dyn_code.append(self.gpa, .{ .wait = .{ .to = base + 1 } }) catch return error.OutOfMemory;
            cp.machine.pc = base;
        } else {
            self.vm.terminate(child, FinalTerms.atom(&cp.machine.ctx, self.vm.atoms.intern("undef") catch return error.OutOfMemory)) catch return error.OutOfMemory;
            return error.StartUndef;
        }
        try self.started.put(spec.name, .{ .sup = child, .worker = child, .has_tree = true });
    }
};

const AtomTable = ta.AtomTable;

test "LAW gap-app-boot-engine: ensure_all_started boots a RESIDENT supervision tree — deps FIRST, .idle after boot, worker-crash SURVIVED, idempotent" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    var m0 = try ia.Machine.init(gpa, &atoms); // a ctx for the (unused) args nil
    defer m0.deinit();

    // two apps: app_a (a service), app_b depends on app_a. Both have a supervision
    // tree ({mod,_}); the dep `kernel` has no spec (a library no-op).
    const a_name = try atoms.intern("app_a");
    const b_name = try atoms.intern("app_b");
    const a_mod = try atoms.intern("app_a_app");
    const b_mod = try atoms.intern("app_b_app");
    const kernel = try atoms.intern("kernel");
    const nil = FinalTerms.nil(&m0.ctx); // the mod.args placeholder (ignored this increment)
    const specs = [_]AppSpec{
        .{ .name = a_name, .mod = .{ .m = a_mod, .args = nil }, .applications = &.{kernel} },
        .{ .name = b_name, .mod = .{ .m = b_mod, .args = nil }, .applications = &.{a_name} },
    };
    var ac = AppController.init(gpa, &vm, &specs);
    defer ac.deinit();

    // BOOT the tree.
    try ac.ensureAllStarted(b_name);
    const sched: proc.Scheduler = .round_robin;

    // DEPS FIRST: app_a + kernel started before app_b; app_a's sup spawned BEFORE
    // app_b's (a lower pid — the topological start order).
    try std.testing.expect(ac.isStarted(a_name));
    try std.testing.expect(ac.isStarted(b_name));
    try std.testing.expect(ac.isStarted(kernel));
    const a_sup = ac.started.get(a_name).?.sup;
    const b_sup = ac.started.get(b_name).?.sup;
    try std.testing.expect(a_sup < b_sup); // app_a's tree came up first

    // RESIDENT: the whole tree (2 supervisors + 2 workers) is alive-but-idle → the
    // node STAYS UP (.idle), not a deadlock.
    try std.testing.expectEqual(@as(usize, 4), vm.residentAliveCount());
    try std.testing.expectEqual(proc.Scheduler.ResidentOutcome.idle, try sched.driveResident(&vm, 7, 100_000, 4));

    // CRASH SUPERVISION: app_a's worker crashes; its trapping supervisor SURVIVES
    // and the node stays up (crash isolation — one app's worker fault does not take
    // the node down).
    const a_worker = ac.started.get(a_name).?.worker;
    const boom = FinalTerms.int(&vm.procs.items[a_worker].machine.ctx, 777);
    try vm.terminate(a_worker, boom);
    try vm.drainSignals(a_sup);
    try std.testing.expect(vm.procs.items[a_sup].alive); // supervisor survived
    try std.testing.expect(!vm.procs.items[a_worker].alive); // worker died
    try std.testing.expectEqual(proc.Scheduler.ResidentOutcome.idle, try sched.driveResident(&vm, 7, 100_000, 4));

    // IDEMPOTENT: ensure_all_started again spawns NOTHING new ({already_started,_}).
    const before = vm.procs.items.len;
    try ac.ensureAllStarted(b_name);
    try std.testing.expectEqual(before, vm.procs.items.len);
}

test "LAW gap-app-boot-engine parseAppSpec: {application,Name,[{mod,{M,A}},{applications,[D]}]} → AppSpec" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    const ctx = &m.ctx;
    const A = struct {
        c: *FinalTerms.Ctx,
        fn atom(self: @This(), n: []const u8) !FinalTerms.Term {
            return FinalTerms.atom(self.c, try self.c.atoms.intern(n));
        }
        fn tup(self: @This(), it: []const FinalTerms.Term) FinalTerms.Term {
            return FinalTerms.tuple(self.c, it) catch unreachable;
        }
        fn list(self: @This(), it: []const FinalTerms.Term) FinalTerms.Term {
            var l = FinalTerms.nil(self.c);
            var i = it.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(self.c, it[i], l) catch unreachable;
            }
            return l;
        }
    };
    const h = A{ .c = ctx };
    // {application, my_app, [{mod,{my_app_app,[]}}, {applications,[dep_a]}]}
    const term = h.tup(&.{
        try h.atom("application"),
        try h.atom("my_app"),
        h.list(&.{
            h.tup(&.{ try h.atom("mod"), h.tup(&.{ try h.atom("my_app_app"), FinalTerms.nil(ctx) }) }),
            h.tup(&.{ try h.atom("applications"), h.list(&.{try h.atom("dep_a")}) }),
        }),
    });
    var spec = try boot_script.parseAppSpec(gpa, ctx, term);
    defer spec.deinit(gpa);
    try std.testing.expectEqual(try atoms.intern("my_app"), spec.name);
    try std.testing.expect(spec.mod != null);
    try std.testing.expectEqual(try atoms.intern("my_app_app"), spec.mod.?.m);
    try std.testing.expectEqual(@as(usize, 1), spec.applications.len);
    try std.testing.expectEqual(try atoms.intern("dep_a"), spec.applications[0]);
}

test "LAW e47-a6b REAL-DISPATCH: with a code-bearing template, ensure_all_started runs M:start(normal, Args) from the LINKED exports (cross-heap Args reach the child); an unresolvable start is a fail-closed StartUndef" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    var m0 = try ia.Machine.init(gpa, &atoms);
    defer m0.deinit();

    const myapp = try atoms.intern("myapp");
    const app_name = try atoms.intern("myapp_app");
    const bad_name = try atoms.intern("ghost_app");
    const ghost = try atoms.intern("ghost");
    const f_start = try atoms.intern("start");

    // The "linked code space": pc 0 = the template's own idle body; pc 1.. =
    // the exported myapp:start/2 whose body COMPUTES FROM ITS SECOND ARGUMENT
    // (x1 = Args) — the observation that the cross-heap arg copy + the export
    // entry dispatch both really happened (a wrong pc or a lost Args cannot
    // produce 42).
    const prog: ia.Program = &.{
        .{ .wait = .{ .to = 0 } }, // 0: template idles (a resident node's entry)
        .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .imm = 2 }, .dst = 0 } }, // 1: start/2: x0 = Args + 2
        .{ .halt = .{ .src = .{ .x = 0 } } }, // 2
    };
    const exports = [_]ia.Export{
        .{ .module = myapp, .func = f_start, .arity = 2, .pc = 1 },
    };
    const tpl = try vm.spawn(prog, 0, null);
    vm.procs.items[tpl].machine.exports = &exports;
    vm.procs.items[tpl].machine.status = .suspended; // idle template

    const specs = [_]AppSpec{
        .{ .name = app_name, .mod = .{ .m = myapp, .args = FinalTerms.int(&m0.ctx, 40) }, .applications = &.{} },
        .{ .name = bad_name, .mod = .{ .m = ghost, .args = FinalTerms.nil(&m0.ctx) }, .applications = &.{} },
    };
    var ac = AppController.init(gpa, &vm, &specs);
    defer ac.deinit();
    ac.template = tpl;

    // REAL DISPATCH: the app's root is spawned INTO myapp:start/2 with
    // (normal, 40) and computes 40 + 2 = 42 — args crossed heaps, the entry
    // was the linked export.
    try ac.ensureAllStarted(app_name);
    try std.testing.expect(ac.isStarted(app_name));
    const root = ac.started.get(app_name).?.sup;
    const sched: proc.Scheduler = .round_robin;
    try sched.drive(&vm, 20, 10_000);
    const rm = &vm.procs.items[root].machine;
    try std.testing.expectEqual(ia.Status.halted, rm.status);
    try std.testing.expectEqual(@as(i64, 42), @as(i64, @bitCast(rm.result)) >> 4);

    // FAIL-CLOSED: a {mod,_} app whose M:start/2 is NOT in the linked exports
    // is StartUndef — and leaves NO half-started row.
    try std.testing.expectError(error.StartUndef, ac.ensureAllStarted(bad_name));
    try std.testing.expect(!ac.isStarted(bad_name));
}

/// gap-release-boot: the LIVE (final) boot-instruction driver. It interprets a
/// `.script`'s ordered instruction list (`boot_script.interpret`) against the
/// REAL node — `primLoad` drives the CodeIndex loader (ensure_loaded, composing
/// AUTOLOAD==STATIC-LINK), `{kernelProcess,application_controller,_}` composes
/// with the already-proven P-APP `ensureAllStarted` (booting the resident
/// supervision tree), and every other `kernelProcess` spawns a resident kernel
/// process. `progress`/`preLoaded`/`path`/`kernel_load_completed`/`apply` are the
/// phase/effect markers the fold visits in order. The residual is the `.boot`
/// BINARY decode (it is `term_to_binary` of this same script term, so it reuses
/// the ETF path `parse` already exercises) and `release_handler` (upgrades).
pub const LiveBootDriver = struct {
    gpa: std.mem.Allocator,
    vm: *proc.Vm,
    code: *code_index.CodeIndex,
    ac: *AppController,
    boot_app: AtomIdx,
    app_ctrl_atom: AtomIdx,

    pub fn progress(_: *LiveBootDriver, _: AtomIdx) !void {}
    pub fn preloaded(_: *LiveBootDriver, _: AtomIdx) !void {}
    pub fn setPath(_: *LiveBootDriver, _: usize) !void {}
    pub fn kernelLoadCompleted(_: *LiveBootDriver) !void {}
    pub fn apply(_: *LiveBootDriver, _: AtomIdx, _: AtomIdx) !void {}

    /// ensure_loaded M: idempotent — a module already resolvable is a no-op
    /// (OTP's `code:ensure_loaded/1`); otherwise link its (stub) code so it
    /// resolves. A real `.beam` decode is the STATIC-LINK residual.
    pub fn load(self: *LiveBootDriver, m: AtomIdx) !void {
        const name = self.vm.atoms.nameOf(m);
        if (self.code.resolve(name) != null) return;
        try self.code.load(name, worker_prog);
    }

    pub fn kernelProcess(self: *LiveBootDriver, name: AtomIdx) !void {
        if (name == self.app_ctrl_atom) {
            // compose with the P-APP law: the application_controller boots the tree.
            self.ac.ensureAllStarted(self.boot_app) catch return error.BootFailed;
            return;
        }
        const sup = try self.vm.spawn(supervisor_prog, 0, null);
        self.vm.procs.items[sup].machine.trap_exit = true;
    }
};

test "LAW gap-release-boot SERVING-STATE: interpreting a satisfiable .script boots the node — primLoad'd modules RESOLVE (loader composed), application_controller boots the app tree (P-APP composed), the node serves (.idle)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    var ci = code_index.CodeIndex.init(gpa);
    defer ci.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const H = struct {
        c: *FinalTerms.Ctx,
        fn atom(self: @This(), n: []const u8) !FinalTerms.Term {
            return FinalTerms.atom(self.c, try self.c.atoms.intern(n));
        }
        fn tup(self: @This(), it: []const FinalTerms.Term) FinalTerms.Term {
            return FinalTerms.tuple(self.c, it) catch unreachable;
        }
        fn list(self: @This(), it: []const FinalTerms.Term) FinalTerms.Term {
            var l = FinalTerms.nil(self.c);
            var i = it.len;
            while (i > 0) {
                i -= 1;
                l = FinalTerms.cons(self.c, it[i], l) catch unreachable;
            }
            return l;
        }
    };
    const h = H{ .c = &ctx };

    // the boot app: `myapp` (a supervision tree) depending on the library app `kernel`.
    const app_name = try atoms.intern("myapp");
    const app_mod = try atoms.intern("myapp_app");
    const kernel = try atoms.intern("kernel");
    const nil_args = FinalTerms.nil(&ctx);
    const specs = [_]AppSpec{
        .{ .name = app_name, .mod = .{ .m = app_mod, .args = nil_args }, .applications = &.{kernel} },
    };
    var ac = AppController.init(gpa, &vm, &specs);
    defer ac.deinit();

    // a satisfiable release `.script` in the exact OTP grammar (pinned to
    // third_party/otp/bin/start_clean.script): preLoaded → progress → path →
    // primLoad → kernel_load_completed → kernelProcess…
    const mfa_none = h.tup(&.{ try h.atom("logger_server"), try h.atom("start_link"), FinalTerms.nil(&ctx) });
    const mfa_ac = h.tup(&.{ try h.atom("application_controller"), try h.atom("start"), h.list(&.{FinalTerms.nil(&ctx)}) });
    const cmds = h.list(&.{
        h.tup(&.{ try h.atom("preLoaded"), h.list(&.{try h.atom("erlang")}) }),
        h.tup(&.{ try h.atom("progress"), try h.atom("preloaded") }),
        h.tup(&.{ try h.atom("path"), h.list(&.{ try FinalTerms.binary(&ctx, "ebin"), try FinalTerms.binary(&ctx, "ebin2") }) }),
        h.tup(&.{ try h.atom("primLoad"), h.list(&.{ try h.atom("gen_server"), try h.atom("supervisor") }) }),
        h.tup(&.{try h.atom("kernel_load_completed")}),
        h.tup(&.{ try h.atom("progress"), try h.atom("kernel_load_completed") }),
        h.tup(&.{ try h.atom("kernelProcess"), try h.atom("logger"), mfa_none }),
        h.tup(&.{ try h.atom("kernelProcess"), try h.atom("application_controller"), mfa_ac }),
    });
    const script_t = h.tup(&.{ try h.atom("script"), h.tup(&.{ try FinalTerms.binary(&ctx, "OTP"), try FinalTerms.binary(&ctx, "30") }), cmds });
    var arr = try etf.encode(gpa, &ctx, script_t);
    defer arr.deinit(gpa);
    var script = try boot_script.parse(gpa, &ctx, arr.items);
    defer script.deinit(gpa);

    var drv = LiveBootDriver{
        .gpa = gpa,
        .vm = &vm,
        .code = &ci,
        .ac = &ac,
        .boot_app = app_name,
        .app_ctrl_atom = try atoms.intern("application_controller"),
    };
    const outcome = boot_script.interpret(LiveBootDriver, &drv, &ctx, &script);

    // BOOTED: the whole ordered script was satisfiable.
    try std.testing.expect(outcome == .booted);
    // LOADER COMPOSED: every primLoad'd module now RESOLVES (ensure_loaded).
    try std.testing.expect(ci.resolve("gen_server") != null);
    try std.testing.expect(ci.resolve("supervisor") != null);
    // P-APP COMPOSED: application_controller booted `myapp` (+ its library dep).
    try std.testing.expect(ac.isStarted(app_name));
    try std.testing.expect(ac.isStarted(kernel));
    // SERVING: logger sup (1) + myapp's sup+worker (2) are resident, and the node
    // drives to IDLE-BUT-ALIVE (it stays up serving, not a deadlock/exit).
    try std.testing.expectEqual(@as(usize, 3), vm.residentAliveCount());
    const sched: proc.Scheduler = .round_robin;
    try std.testing.expectEqual(proc.Scheduler.ResidentOutcome.idle, try sched.driveResident(&vm, 7, 100_000, 4));
}
