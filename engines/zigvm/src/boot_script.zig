//! boot_script — the boot-script algebra: OTP's `start.boot` command list as
//! a first-class term. Semantic domain: an ordered list of boot commands
//! (path/preLoaded/kernel-proc/apply …) denoting the ordered effect sequence
//! a boot performs. Oracle: the recorded effect log (fold over commands,
//! 1:1 with the command list — the order law); final: live execution through
//! init_lifecycle composing with ensureAllStarted (the P-APP law). Laws in
//! this module's tests; a failed command aborts the fold (rejection law).
const std = @import("std");
const ta = @import("term_algebra.zig");
const etf = @import("etf.zig");
const erl_expr = @import("erl_expr.zig");

const FinalTerms = ta.FinalTerms;
const expectLaw = ta.expectLaw;
const LawConfig = ta.LawConfig;

pub const CommandType = enum {
    progress,
    preLoaded,
    path,
    primLoad,
    kernelProcess,
    apply,
    kernel_load_completed,
    unknown,
};

pub const Command = union(CommandType) {
    progress: ta.AtomIdx,
    preLoaded: FinalTerms.Term, // `{preLoaded,[Mod...]}` — the module list
    path: FinalTerms.Term,
    primLoad: FinalTerms.Term,
    kernelProcess: struct { name: ta.AtomIdx, mfa: FinalTerms.Term },
    apply: FinalTerms.Term, // `{apply,{M,F,A}}` — the {M,F,A} tuple
    kernel_load_completed: void, // `{kernel_load_completed}` — an arity-1 phase marker
    unknown: FinalTerms.Term,
};

pub const BootScript = struct {
    name: FinalTerms.Term,
    vsn: FinalTerms.Term,
    commands: []const Command,
    
    pub fn deinit(self: *BootScript, gpa: std.mem.Allocator) void {
        gpa.free(self.commands);
    }
};

pub const ParseError = error{
    OutOfMemory,
    NotAScriptTuple,
    MissingHeader,
    MissingCommands,
    InvalidCommand,
} || etf.DecodeError;

// ── gap-app-boot-engine: the `.app` spec (a subset of the OTP application resource) ──
pub const AppMod = struct { m: ta.AtomIdx, args: FinalTerms.Term };

/// A parsed `.app` resource: `{application, Name, Opts}` where Opts is a proplist.
/// `mod` = the `{mod,{M,Args}}` entry (null for a library app that just marks
/// started); `applications` = the `{applications,[Dep...]}` dependency list.
pub const AppSpec = struct {
    name: ta.AtomIdx,
    mod: ?AppMod = null,
    applications: []const ta.AtomIdx = &.{},

    pub fn deinit(self: *AppSpec, gpa: std.mem.Allocator) void {
        gpa.free(self.applications);
    }
};

/// Parse `{application, Name, Opts}` → AppSpec. Reuses the boot-script accessor
/// idiom. Unknown proplist keys are ignored (a partial-but-honest reader).
pub fn parseAppSpec(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, term: FinalTerms.Term) ParseError!AppSpec {
    if (FinalTerms.kindOf(ctx, term) != .tuple or FinalTerms.tupleArity(ctx, term) != 3)
        return error.NotAScriptTuple;
    const tag = FinalTerms.tupleElem(ctx, term, 0);
    if (FinalTerms.kindOf(ctx, tag) != .atom or
        !std.mem.eql(u8, ctx.atoms.nameOf(FinalTerms.atomIdxOf(tag)), "application"))
        return error.NotAScriptTuple;
    const name_t = FinalTerms.tupleElem(ctx, term, 1);
    if (FinalTerms.kindOf(ctx, name_t) != .atom) return error.InvalidCommand;

    var mod: ?AppMod = null;
    var apps: std.ArrayList(ta.AtomIdx) = .empty;
    errdefer apps.deinit(gpa);

    var cur = FinalTerms.tupleElem(ctx, term, 2);
    while (FinalTerms.kindOf(ctx, cur) == .cons) {
        const opt = FinalTerms.listHead(ctx, cur);
        cur = FinalTerms.listTail(ctx, cur);
        if (FinalTerms.kindOf(ctx, opt) != .tuple or FinalTerms.tupleArity(ctx, opt) != 2) continue;
        const k = FinalTerms.tupleElem(ctx, opt, 0);
        if (FinalTerms.kindOf(ctx, k) != .atom) continue;
        const kn = ctx.atoms.nameOf(FinalTerms.atomIdxOf(k));
        const v = FinalTerms.tupleElem(ctx, opt, 1);
        if (std.mem.eql(u8, kn, "mod") and
            FinalTerms.kindOf(ctx, v) == .tuple and FinalTerms.tupleArity(ctx, v) == 2)
        {
            const mt = FinalTerms.tupleElem(ctx, v, 0);
            if (FinalTerms.kindOf(ctx, mt) == .atom)
                mod = .{ .m = FinalTerms.atomIdxOf(mt), .args = FinalTerms.tupleElem(ctx, v, 1) };
        } else if (std.mem.eql(u8, kn, "applications")) {
            var vc = v;
            while (FinalTerms.kindOf(ctx, vc) == .cons) {
                const a = FinalTerms.listHead(ctx, vc);
                if (FinalTerms.kindOf(ctx, a) == .atom) try apps.append(gpa, FinalTerms.atomIdxOf(a));
                vc = FinalTerms.listTail(ctx, vc);
            }
        }
    }
    return .{ .name = FinalTerms.atomIdxOf(name_t), .mod = mod, .applications = try apps.toOwnedSlice(gpa) };
}

/// gap-app-boot-keystone (DIVERGENCE 681): parse a `.app` RESOURCE FILE's TEXT
/// (`{application, Name, [Opts]}.`) directly into an `AppSpec` — the on-demand
/// `.app` discovery primitive the CLI app-boot intercept needs (the boot path
/// gets its spec from a binary-ETF `.boot` script via `parse`; a real app on the
/// code_path ships only the human-readable `.app` text, which OTP reads with
/// `file:consult`). Tokenizes+parses via `erl_expr.readValue` (a temp arena owns
/// the tokenizer scratch; the term lands in `ctx`), then reuses `parseAppSpec`.
/// A malformed `.app` is a fail-closed error (never a half-built spec).
pub fn parseAppSpecText(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, text: []const u8) (ParseError || erl_expr.ReadError)!AppSpec {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const term = try erl_expr.readValue(arena.allocator(), ctx, text);
    return parseAppSpec(gpa, ctx, term);
}

pub fn parse(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, buf: []const u8) ParseError!BootScript {
    const term = try etf.decode(gpa, ctx, buf);
    if (FinalTerms.kindOf(ctx, term) != .tuple or FinalTerms.tupleArity(ctx, term) != 3) {
        return error.NotAScriptTuple;
    }
    
    const tag = FinalTerms.tupleElem(ctx, term, 0);
    if (FinalTerms.kindOf(ctx, tag) != .atom or !std.mem.eql(u8, ctx.atoms.nameOf(FinalTerms.atomIdxOf(tag)), "script")) {
        return error.NotAScriptTuple;
    }
    
    const header = FinalTerms.tupleElem(ctx, term, 1);
    if (FinalTerms.kindOf(ctx, header) != .tuple or FinalTerms.tupleArity(ctx, header) != 2) {
        return error.MissingHeader;
    }
    
    const name = FinalTerms.tupleElem(ctx, header, 0);
    const vsn = FinalTerms.tupleElem(ctx, header, 1);
    
    const cmds_list = FinalTerms.tupleElem(ctx, term, 2);
    
    var n: usize = 0;
    var cur = cmds_list;
    while (FinalTerms.kindOf(ctx, cur) == .cons) {
        n += 1;
        cur = FinalTerms.listTail(ctx, cur);
    }
    
    const commands = try gpa.alloc(Command, n);
    errdefer gpa.free(commands);
    
    cur = cmds_list;
    var i: usize = 0;
    while (FinalTerms.kindOf(ctx, cur) == .cons) : (i += 1) {
        const cmd_tuple = FinalTerms.listHead(ctx, cur);
        // Every boot instruction is at least a 1-tuple `{Tag}`; `{kernel_load_completed}`
        // is the only arity-1 form (a phase marker), so the guard is arity >= 1.
        if (FinalTerms.kindOf(ctx, cmd_tuple) != .tuple or FinalTerms.tupleArity(ctx, cmd_tuple) < 1) {
            return error.InvalidCommand;
        }

        const arity = FinalTerms.tupleArity(ctx, cmd_tuple);
        const ctag = FinalTerms.tupleElem(ctx, cmd_tuple, 0);
        if (FinalTerms.kindOf(ctx, ctag) != .atom) {
            return error.InvalidCommand;
        }

        const ctag_name = ctx.atoms.nameOf(FinalTerms.atomIdxOf(ctag));
        if (std.mem.eql(u8, ctag_name, "kernel_load_completed")) {
            commands[i] = .kernel_load_completed;
        } else if (std.mem.eql(u8, ctag_name, "progress")) {
            if (arity < 2) return error.InvalidCommand;
            const val = FinalTerms.tupleElem(ctx, cmd_tuple, 1);
            if (FinalTerms.kindOf(ctx, val) != .atom) return error.InvalidCommand;
            commands[i] = .{ .progress = FinalTerms.atomIdxOf(val) };
        } else if (std.mem.eql(u8, ctag_name, "preLoaded")) {
            if (arity < 2) return error.InvalidCommand;
            commands[i] = .{ .preLoaded = FinalTerms.tupleElem(ctx, cmd_tuple, 1) };
        } else if (std.mem.eql(u8, ctag_name, "path")) {
            if (arity < 2) return error.InvalidCommand;
            commands[i] = .{ .path = FinalTerms.tupleElem(ctx, cmd_tuple, 1) };
        } else if (std.mem.eql(u8, ctag_name, "primLoad")) {
            if (arity < 2) return error.InvalidCommand;
            commands[i] = .{ .primLoad = FinalTerms.tupleElem(ctx, cmd_tuple, 1) };
        } else if (std.mem.eql(u8, ctag_name, "apply")) {
            if (arity < 2) return error.InvalidCommand;
            commands[i] = .{ .apply = FinalTerms.tupleElem(ctx, cmd_tuple, 1) };
        } else if (std.mem.eql(u8, ctag_name, "kernelProcess")) {
            if (arity != 3) return error.InvalidCommand;
            const pname = FinalTerms.tupleElem(ctx, cmd_tuple, 1);
            if (FinalTerms.kindOf(ctx, pname) != .atom) return error.InvalidCommand;
            commands[i] = .{ .kernelProcess = .{
                .name = FinalTerms.atomIdxOf(pname),
                .mfa = FinalTerms.tupleElem(ctx, cmd_tuple, 2),
            } };
        } else {
            commands[i] = .{ .unknown = ctag };
        }

        cur = FinalTerms.listTail(ctx, cur);
    }
    
    return BootScript{
        .name = name,
        .vsn = vsn,
        .commands = commands,
    };
}

// ── gap-release-boot: the boot-instruction CONSUMER (interpreter) ──────────────
//
// ## Semantic domain
// An OTP release boots by executing the `.script`'s ordered boot-instruction list
// (the `.boot` is `term_to_binary` of the same term, so decoding it is the ETF
// path already exercised by `parse`). `interpret` is a FOLD over that list: the
// node state after the script is the sequential composition of each instruction's
// effect, in order —
//
//     interpret([]) = booted
//     interpret(instr :: rest) = effect(instr) ⨟ interpret(rest)   (if effect ok)
//     interpret(instr :: rest) = halted(i)                          (if effect fails)
//
// Each instruction's effect is delegated to a DRIVER (a comptime-duck-typed sink),
// so the fold is polymorphic over its interpretation: the pure `TraceDriver`
// (oracle — records the ordered effect log for the algebraic laws) and the LIVE
// driver in `app_controller.zig` (final — drives the real CodeIndex loader +
// `ensureAllStarted`, composing with the P-APP law). Order matters and a failed
// instruction HALTS the boot with an OTP-shaped reason at that index — never a
// silent skip, matching `init`'s "boot function failed" halt.
//
// Instruction → effect:
//   {progress,P}              → driver.progress(P)            phase marker
//   {preLoaded,[M...]}        → driver.preloaded(M) each      already-resident mods
//   {path,[D...]}             → driver.setPath(N)             code path (N dirs)
//   {primLoad,[M...]}         → driver.load(M) each           ensure_loaded (loader)
//   {kernel_load_completed}   → driver.kernelLoadCompleted()  phase marker
//   {kernelProcess,Name,MFA}  → driver.kernelProcess(Name)    start a kernel proc
//   {apply,{M,F,A}}           → driver.apply(M,F)             apply exactly once
//   {Unknown,...}             → HALT (unknown_command)        never skipped
//   malformed {apply,_}/list  → HALT (malformed_*)            never skipped

pub const HaltReason = enum { unknown_command, malformed_apply, malformed_module };

/// The OTP-shaped boot failure: `{error, {Reason, Instruction#index}}`.
pub const BootHalt = struct { reason: HaltReason, index: usize };

/// The denotation of a whole boot: the node either reaches a serving state
/// (`booted`) or `init` halts at the first failing instruction.
pub const BootOutcome = union(enum) {
    booted: void,
    halted: BootHalt,
};

fn halted(reason: HaltReason, index: usize) BootOutcome {
    return .{ .halted = .{ .reason = reason, .index = index } };
}

/// Read `{M,F,A}` → the {M,F} atom pair; null if the term is not a
/// well-formed MFA tuple with atom M and F (a malformed instruction).
fn extractMF(ctx: *FinalTerms.Ctx, mfa: FinalTerms.Term) ?struct { m: ta.AtomIdx, f: ta.AtomIdx } {
    if (FinalTerms.kindOf(ctx, mfa) != .tuple or FinalTerms.tupleArity(ctx, mfa) != 3) return null;
    const m = FinalTerms.tupleElem(ctx, mfa, 0);
    const f = FinalTerms.tupleElem(ctx, mfa, 1);
    if (FinalTerms.kindOf(ctx, m) != .atom or FinalTerms.kindOf(ctx, f) != .atom) return null;
    return .{ .m = FinalTerms.atomIdxOf(m), .f = FinalTerms.atomIdxOf(f) };
}

/// The FOLD. `D` is any driver exposing the effect sinks (see the effect table
/// above); a sink may fail (`!void`) and any such failure HALTS the boot at the
/// current index (an OTP boot-instruction failure is a normal `init` halt, not a
/// crash of the interpreter — so it is a `BootOutcome`, not a Zig error).
pub fn interpret(comptime D: type, driver: *D, ctx: *FinalTerms.Ctx, script: *const BootScript) BootOutcome {
    for (script.commands, 0..) |cmd, i| {
        switch (cmd) {
            .progress => |p| driver.progress(p) catch return halted(.malformed_module, i),
            .kernel_load_completed => driver.kernelLoadCompleted() catch return halted(.malformed_module, i),
            .preLoaded => |list| {
                var cur = list;
                while (FinalTerms.kindOf(ctx, cur) == .cons) {
                    const m = FinalTerms.listHead(ctx, cur);
                    cur = FinalTerms.listTail(ctx, cur);
                    if (FinalTerms.kindOf(ctx, m) != .atom) return halted(.malformed_module, i);
                    driver.preloaded(FinalTerms.atomIdxOf(m)) catch return halted(.malformed_module, i);
                }
            },
            .path => |list| {
                var n: usize = 0;
                var cur = list;
                while (FinalTerms.kindOf(ctx, cur) == .cons) : (cur = FinalTerms.listTail(ctx, cur)) n += 1;
                driver.setPath(n) catch return halted(.malformed_module, i);
            },
            .primLoad => |list| {
                var cur = list;
                while (FinalTerms.kindOf(ctx, cur) == .cons) {
                    const m = FinalTerms.listHead(ctx, cur);
                    cur = FinalTerms.listTail(ctx, cur);
                    if (FinalTerms.kindOf(ctx, m) != .atom) return halted(.malformed_module, i);
                    // ensure_loaded — composes with the loader (AUTOLOAD==STATIC-LINK).
                    driver.load(FinalTerms.atomIdxOf(m)) catch return halted(.malformed_module, i);
                }
            },
            .kernelProcess => |kp| driver.kernelProcess(kp.name) catch return halted(.malformed_module, i),
            .apply => |mfa| {
                const mf = extractMF(ctx, mfa) orelse return halted(.malformed_apply, i);
                driver.apply(mf.m, mf.f) catch return halted(.malformed_apply, i);
            },
            .unknown => return halted(.unknown_command, i), // never silently skipped
        }
    }
    return .booted;
}

/// The oracle driver: an ordered log of the effects the fold produced. Each sink
/// appends one entry, so the log IS the denotation `effect₀ ⨟ effect₁ ⨟ …` and a
/// direct witness of apply-order + exactly-once.
pub const TraceEntry = union(enum) {
    progress: ta.AtomIdx,
    preloaded: ta.AtomIdx,
    path: usize,
    load: ta.AtomIdx,
    kernel_process: ta.AtomIdx,
    apply: struct { m: ta.AtomIdx, f: ta.AtomIdx },
    kernel_load_completed: void,
};

pub const TraceDriver = struct {
    gpa: std.mem.Allocator,
    log: std.ArrayList(TraceEntry) = .empty,

    pub fn deinit(self: *TraceDriver) void {
        self.log.deinit(self.gpa);
    }
    pub fn progress(self: *TraceDriver, p: ta.AtomIdx) !void {
        try self.log.append(self.gpa, .{ .progress = p });
    }
    pub fn preloaded(self: *TraceDriver, m: ta.AtomIdx) !void {
        try self.log.append(self.gpa, .{ .preloaded = m });
    }
    pub fn setPath(self: *TraceDriver, n: usize) !void {
        try self.log.append(self.gpa, .{ .path = n });
    }
    pub fn load(self: *TraceDriver, m: ta.AtomIdx) !void {
        try self.log.append(self.gpa, .{ .load = m });
    }
    pub fn kernelProcess(self: *TraceDriver, name: ta.AtomIdx) !void {
        try self.log.append(self.gpa, .{ .kernel_process = name });
    }
    pub fn apply(self: *TraceDriver, m: ta.AtomIdx, f: ta.AtomIdx) !void {
        try self.log.append(self.gpa, .{ .apply = .{ .m = m, .f = f } });
    }
    pub fn kernelLoadCompleted(self: *TraceDriver) !void {
        try self.log.append(self.gpa, .kernel_load_completed);
    }
};

// A tiny seeded term-builder for the boot-instruction generators.
const Rng = std.Random.DefaultPrng;

const BootTestHelp = struct {
    ctx: *FinalTerms.Ctx,
    fn atom(self: @This(), n: []const u8) !FinalTerms.Term {
        return FinalTerms.atom(self.ctx, try self.ctx.atoms.intern(n));
    }
    fn tup(self: @This(), it: []const FinalTerms.Term) FinalTerms.Term {
        return FinalTerms.tuple(self.ctx, it) catch unreachable;
    }
    fn list(self: @This(), it: []const FinalTerms.Term) FinalTerms.Term {
        var l = FinalTerms.nil(self.ctx);
        var i = it.len;
        while (i > 0) {
            i -= 1;
            l = FinalTerms.cons(self.ctx, it[i], l) catch unreachable;
        }
        return l;
    }
    // one random SINGLE-EFFECT instruction (each produces exactly one trace entry
    // so the fold log lines up 1:1 with the command list for the order law).
    fn oneInstr(self: @This(), rng: *Rng) !FinalTerms.Term {
        return switch (rng.random().intRangeAtMost(u8, 0, 4)) {
            0 => self.tup(&.{ try self.atom("progress"), try self.atom("preloaded") }),
            1 => self.tup(&.{ try self.atom("path"), self.list(&.{try self.atom("dir_a")}) }),
            2 => self.tup(&.{ try self.atom("primLoad"), self.list(&.{try self.atom("mod_x")}) }),
            3 => self.tup(&.{ try self.atom("apply"), self.tup(&.{ try self.atom("m"), try self.atom("f"), FinalTerms.nil(self.ctx) }) }),
            else => self.tup(&.{try self.atom("kernel_load_completed")}),
        };
    }
};

test "LAW gap-release-boot FOLD/apply-order: the trace log equals the command list in ORDER (fold homomorphism); {apply,_} applies EXACTLY ONCE per apply instruction; a satisfiable script boots" {
    const gpa = std.testing.allocator;
    var seed: u64 = 0;
    while (seed < 32) : (seed += 1) {
        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        const h = BootTestHelp{ .ctx = &ctx };
        var rng = Rng.init(seed);

        const n = rng.random().intRangeAtMost(usize, 0, 8);
        const cmds = try gpa.alloc(Command, n);
        defer gpa.free(cmds);
        var cmd_terms = try gpa.alloc(FinalTerms.Term, n);
        defer gpa.free(cmd_terms);
        var expected_applies: usize = 0;
        for (0..n) |k| {
            cmd_terms[k] = try h.oneInstr(&rng);
            if (FinalTerms.kindOf(&ctx, FinalTerms.tupleElem(&ctx, cmd_terms[k], 0)) == .atom and
                std.mem.eql(u8, ctx.atoms.nameOf(FinalTerms.atomIdxOf(FinalTerms.tupleElem(&ctx, cmd_terms[k], 0))), "apply"))
                expected_applies += 1;
        }
        // parse the assembled script so the FULL pipeline (decode→parse→fold) runs.
        const script_t = h.tup(&.{ try h.atom("script"), h.tup(&.{ try FinalTerms.binary(&ctx, "T"), try FinalTerms.binary(&ctx, "1") }), h.list(cmd_terms) });
        var arr = try etf.encode(gpa, &ctx, script_t);
        defer arr.deinit(gpa);
        var script = try parse(gpa, &ctx, arr.items);
        defer script.deinit(gpa);

        var td = TraceDriver{ .gpa = gpa };
        defer td.deinit();
        const outcome = interpret(TraceDriver, &td, &ctx, &script);

        // BOOTED: every instruction was satisfiable → the node reached a serving state.
        try expectLaw(outcome == .booted, "boot: a fully-satisfiable script boots (no halt)", LawConfig{ .seed = seed }, seed);
        // FOLD ORDER: one trace entry per single-effect instruction, IN ORDER.
        try expectLaw(td.log.items.len == n, "boot: fold trace length == command count (single-effect gens)", LawConfig{ .seed = seed }, seed);
        var applies: usize = 0;
        for (script.commands, 0..) |c, k| {
            const entry = td.log.items[k];
            const ok = switch (c) {
                .progress => entry == .progress,
                .path => entry == .path,
                .primLoad => entry == .load,
                .apply => entry == .apply,
                .kernel_load_completed => entry == .kernel_load_completed,
                else => false,
            };
            try expectLaw(ok, "boot: trace[k] denotes command[k] (order-preserving fold homomorphism)", LawConfig{ .seed = seed }, seed);
            if (entry == .apply) applies += 1;
        }
        // EXACTLY ONCE: #apply effects == #apply instructions (no drop, no double-apply).
        try expectLaw(applies == expected_applies, "boot: {apply,_} applied exactly once, in order", LawConfig{ .seed = seed }, seed);
    }
}

test "LAW gap-release-boot HALT: an unknown/malformed instruction HALTS the boot at its index (never silently skipped) — instructions after it do NOT run" {
    const gpa = std.testing.allocator;
    var seed: u64 = 0;
    while (seed < 24) : (seed += 1) {
        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        const h = BootTestHelp{ .ctx = &ctx };
        var rng = Rng.init(seed +% 1000);

        // prefix of good single-effect instrs, then an UNKNOWN instr, then a suffix
        // whose effects MUST NOT appear (halt stops the fold).
        const pre = rng.random().intRangeAtMost(usize, 0, 4);
        const post = rng.random().intRangeAtMost(usize, 1, 4);
        const total = pre + 1 + post;
        var cmd_terms = try gpa.alloc(FinalTerms.Term, total);
        defer gpa.free(cmd_terms);
        for (0..pre) |k| cmd_terms[k] = try h.oneInstr(&rng);
        cmd_terms[pre] = h.tup(&.{ try h.atom("frobnicate"), FinalTerms.nil(&ctx) }); // unknown tag
        // suffix = apply instructions; if the fold wrongly continued, we'd see them.
        for (pre + 1..total) |k|
            cmd_terms[k] = h.tup(&.{ try h.atom("apply"), h.tup(&.{ try h.atom("m"), try h.atom("f"), FinalTerms.nil(&ctx) }) });

        const script_t = h.tup(&.{ try h.atom("script"), h.tup(&.{ try FinalTerms.binary(&ctx, "T"), try FinalTerms.binary(&ctx, "1") }), h.list(cmd_terms) });
        var arr = try etf.encode(gpa, &ctx, script_t);
        defer arr.deinit(gpa);
        var script = try parse(gpa, &ctx, arr.items);
        defer script.deinit(gpa);

        var td = TraceDriver{ .gpa = gpa };
        defer td.deinit();
        const outcome = interpret(TraceDriver, &td, &ctx, &script);

        try expectLaw(outcome == .halted, "boot: an unknown instruction HALTS (not booted)", LawConfig{ .seed = seed }, seed);
        try expectLaw(outcome.halted.reason == .unknown_command, "boot: halt reason is unknown_command", LawConfig{ .seed = seed }, seed);
        try expectLaw(outcome.halted.index == pre, "boot: halt index == the unknown instruction's position", LawConfig{ .seed = seed }, seed);
        // NEVER SKIPPED: exactly the `pre` good instructions ran; the suffix did not.
        try expectLaw(td.log.items.len == pre, "boot: instructions after the halt are NOT executed", LawConfig{ .seed = seed }, seed);
    }
}

test "LAW gap-release-boot HALT: a malformed {apply,NotAnMFA} halts with malformed_apply (the fold rejects it, never skips)" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const h = BootTestHelp{ .ctx = &ctx };
    // {apply, foo} — the value is an atom, not an {M,F,A} tuple.
    const cmd_terms = [_]FinalTerms.Term{
        h.tup(&.{ try h.atom("progress"), try h.atom("start") }),
        h.tup(&.{ try h.atom("apply"), try h.atom("foo") }),
        h.tup(&.{ try h.atom("apply"), h.tup(&.{ try h.atom("m"), try h.atom("f"), FinalTerms.nil(&ctx) }) }),
    };
    const script_t = h.tup(&.{ try h.atom("script"), h.tup(&.{ try FinalTerms.binary(&ctx, "T"), try FinalTerms.binary(&ctx, "1") }), h.list(&cmd_terms) });
    var arr = try etf.encode(gpa, &ctx, script_t);
    defer arr.deinit(gpa);
    var script = try parse(gpa, &ctx, arr.items);
    defer script.deinit(gpa);

    var td = TraceDriver{ .gpa = gpa };
    defer td.deinit();
    const outcome = interpret(TraceDriver, &td, &ctx, &script);
    try expectLaw(outcome == .halted, "boot: malformed apply halts", LawConfig{ .seed = 0 }, 0);
    try expectLaw(outcome.halted.reason == .malformed_apply, "boot: reason malformed_apply", LawConfig{ .seed = 0 }, 0);
    try expectLaw(outcome.halted.index == 1, "boot: halted at the malformed apply (index 1)", LawConfig{ .seed = 0 }, 0);
    try expectLaw(td.log.items.len == 1, "boot: only the progress before it ran", LawConfig{ .seed = 0 }, 0);
}

test "LAW E11.2: Boot script parser unmarshals ETF tuple into commands" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const atom_script = FinalTerms.atom(&ctx, try ctx.atoms.intern("script"));
    const atom_progress = FinalTerms.atom(&ctx, try ctx.atoms.intern("progress"));
    const atom_init = FinalTerms.atom(&ctx, try ctx.atoms.intern("init"));
    const atom_path = FinalTerms.atom(&ctx, try ctx.atoms.intern("path"));
    const atom_primLoad = FinalTerms.atom(&ctx, try ctx.atoms.intern("primLoad"));
    const atom_apply = FinalTerms.atom(&ctx, try ctx.atoms.intern("apply"));
    const atom_kernelProcess = FinalTerms.atom(&ctx, try ctx.atoms.intern("kernelProcess"));
    const atom_my_proc = FinalTerms.atom(&ctx, try ctx.atoms.intern("my_proc"));

    const str_test = try FinalTerms.binary(&ctx, "Test");
    const str_vsn = try FinalTerms.binary(&ctx, "1.0");
    const header = try FinalTerms.tuple(&ctx, &.{ str_test, str_vsn });

    const cmd1 = try FinalTerms.tuple(&ctx, &.{ atom_progress, atom_init });
    const cmd2 = try FinalTerms.tuple(&ctx, &.{ atom_path, FinalTerms.nil(&ctx) });
    const cmd3 = try FinalTerms.tuple(&ctx, &.{ atom_primLoad, FinalTerms.nil(&ctx) });
    const cmd4 = try FinalTerms.tuple(&ctx, &.{ atom_apply, FinalTerms.nil(&ctx) });
    const mfa = try FinalTerms.tuple(&ctx, &.{ FinalTerms.nil(&ctx), FinalTerms.nil(&ctx), FinalTerms.nil(&ctx) });
    const cmd5 = try FinalTerms.tuple(&ctx, &.{ atom_kernelProcess, atom_my_proc, mfa });

    var cmds_list = FinalTerms.nil(&ctx);
    cmds_list = try FinalTerms.cons(&ctx, cmd5, cmds_list);
    cmds_list = try FinalTerms.cons(&ctx, cmd4, cmds_list);
    cmds_list = try FinalTerms.cons(&ctx, cmd3, cmds_list);
    cmds_list = try FinalTerms.cons(&ctx, cmd2, cmds_list);
    cmds_list = try FinalTerms.cons(&ctx, cmd1, cmds_list);

    const script_tuple = try FinalTerms.tuple(&ctx, &.{ atom_script, header, cmds_list });

    var arr = try etf.encode(gpa, &ctx, script_tuple);
    defer arr.deinit(gpa);

    var script = try parse(gpa, &ctx, arr.items);
    defer script.deinit(gpa);

    try expectLaw(script.commands.len == 5, "boot_script: parsed 5 commands", LawConfig{.seed=0}, 0);
    try expectLaw(script.commands[0] == .progress, "boot_script: parsed progress", LawConfig{.seed=0}, 0);
    try expectLaw(script.commands[1] == .path, "boot_script: parsed path", LawConfig{.seed=0}, 0);
    try expectLaw(script.commands[2] == .primLoad, "boot_script: parsed primLoad", LawConfig{.seed=0}, 0);
    try expectLaw(script.commands[3] == .apply, "boot_script: parsed apply", LawConfig{.seed=0}, 0);
    try expectLaw(script.commands[4] == .kernelProcess, "boot_script: parsed kernelProcess", LawConfig{.seed=0}, 0);
}

test "LAW gap-app-boot-keystone parseAppSpecText (DIVERGENCE 681): reads a `.app` resource TEXT into an AppSpec — name/mod/applications extracted; strings + atom-lists + nested {mod,{M,A}} tolerated; a library app has mod==null; a malformed text is fail-closed" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const text =
        \\{application, myapp,
        \\ [{description, "test app"},
        \\  {vsn, "1.0"},
        \\  {modules, [myapp, myapp_sup, myapp_srv]},
        \\  {registered, [myapp_srv]},
        \\  {applications, [kernel, stdlib]},
        \\  {mod, {myapp, []}}]}.
    ;
    var spec = try parseAppSpecText(gpa, &ctx, text);
    defer spec.deinit(gpa);
    try std.testing.expectEqual(try atoms.intern("myapp"), spec.name);
    try std.testing.expect(spec.mod != null);
    try std.testing.expectEqual(try atoms.intern("myapp"), spec.mod.?.m); // {mod,{M,_}} module
    try std.testing.expect(FinalTerms.kindOf(&ctx, spec.mod.?.args) == .nil); // Args == []
    // applications = [kernel, stdlib], IN ORDER (past the description/vsn/modules/registered opts)
    try std.testing.expectEqual(@as(usize, 2), spec.applications.len);
    try std.testing.expectEqual(try atoms.intern("kernel"), spec.applications[0]);
    try std.testing.expectEqual(try atoms.intern("stdlib"), spec.applications[1]);
    // a LIBRARY app (no {mod,_}) parses with mod == null (marks-started, no tree)
    var lib = try parseAppSpecText(gpa, &ctx, "{application, stdlib, [{vsn, \"5.0\"}, {applications, [kernel]}]}.");
    defer lib.deinit(gpa);
    try std.testing.expect(lib.mod == null);
    try std.testing.expectEqual(try atoms.intern("stdlib"), lib.name);
    try std.testing.expectEqual(try atoms.intern("kernel"), lib.applications[0]);
    // a malformed `.app` text → fail-closed error (never a half-built spec)
    try std.testing.expectError(error.Syntax, parseAppSpecText(gpa, &ctx, "{application, oops"));
    // TRAILING JUNK after a well-formed term is rejected too (endOfProgram enforces
    // single-term-then-eof; a `.app` file is exactly one `{application,...}.`).
    try std.testing.expectError(error.Syntax, parseAppSpecText(gpa, &ctx, "{application, a, []}. garbage"));
}
