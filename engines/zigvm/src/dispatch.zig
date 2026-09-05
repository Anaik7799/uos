//! beam-zig M13 / S14 slot: **dispatch encoding #3** — pre-decoded,
//! indirect-threaded execution + THE DIFFERENTIAL HARNESS.
//!
//! Scope (roadmap ledger): this is the structural JIT milestone — the
//! mechanical essence of BeamJIT's dispatch (pre-resolved operands, one
//! handler pointer per instruction, no switch in the hot loop) WITHOUT
//! native codegen. The differential harness built here is the permanent
//! admission gate for any future machine-code backend: it compares FULL
//! machine states at every preemption boundary, so a backend that gets
//! fuel, traps, mailboxes, or heap semantics subtly wrong cannot pass.
//!
//! Encodings of S13 now:
//!   #1 seq-tree walker      (M3 InitialBlocks — straight-line oracle)
//!   #2 flat-array + switch  (M3 run/stepOne — the production interpreter)
//!   #3 pre-decoded threaded (this file)
//!   #4 native codegen       (LA-5 stub, optional and off by default)
//!
//! Instruction SEMANTICS are shared (ia.execInstr — exactly how erts emu/
//! and jit/ share ops.tab semantics); what differs is fetch + dispatch:
//! the predecoder resolves each pc to a comptime-specialized handler
//! pointer, and the run loop is `handlers[pc](machine, &instrs[pc])` —
//! no tag switch.
//!
//! Laws:
//!   DIFFERENTIAL   for seeded random programs (full op mix incl. mailbox
//!                  and effect traps) run in MATCHED slices, engine #3's
//!                  machine state equals engine #2's at EVERY slice
//!                  boundary (eqMachines: regs, ystack, stack, mailbox,
//!                  pending, status, reductions)
//!   COMPILED CODE  the M8 fixtures (real erlc output) produce identical
//!                  results under both engines
//!   FUEL + SLICE   the M3 fuel exactness and slice-invariance laws are
//!                  RE-VERIFIED on engine #3

const std = @import("std");
const ta = @import("term_algebra.zig");
const ia = @import("instr_algebra.zig");
const loader = @import("beam_loader.zig");
const jit_codegen = @import("jit_codegen.zig");
const gc = @import("gc.zig"); // jit-gc-roots (L4): the machine-level copying GC (collectMachineRoots)

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

pub const Handler = *const fn (m: *ia.Machine, ins: *const ia.CInstr) anyerror!void;

/// A comptime-specialized handler per instruction TAG: the tag dispatch
/// happens ONCE, at predecode time — never in the run loop.
fn handlerFor(comptime tag: std.meta.Tag(ia.CInstr)) Handler {
    return struct {
        fn h(m: *ia.Machine, ins: *const ia.CInstr) anyerror!void {
            // the payload union is re-tagged at comptime: this call inlines
            // to exactly one execInstr arm
            std.debug.assert(std.meta.activeTag(ins.*) == tag);
            try ia.execInstr(m, ins.*);
        }
    }.h;
}

pub const DProg = struct {
    handlers: []Handler,
    instrs: []ia.CInstr,

    pub fn deinit(self: *DProg, gpa: std.mem.Allocator) void {
        gpa.free(self.handlers);
        gpa.free(self.instrs);
    }
};

/// The predecoder: one pass, all dispatch decisions made here.
pub fn predecode(gpa: std.mem.Allocator, prog: ia.Program) !DProg {
    const handlers = try gpa.alloc(Handler, prog.len);
    errdefer gpa.free(handlers);
    const instrs = try gpa.dupe(ia.CInstr, prog);
    errdefer gpa.free(instrs);
    for (prog, 0..) |ins, i| {
        handlers[i] = switch (std.meta.activeTag(ins)) {
            inline else => |tag| handlerFor(tag),
        };
    }
    return .{ .handlers = handlers, .instrs = instrs };
}

/// Engine #3's run loop — the threaded dispatcher. Semantics of `run`
/// (budget, traps, fall-off-the-end) must match engine #2 EXACTLY; the
/// differential law is what enforces it.
pub fn runThreaded(m: *ia.Machine, d: *const DProg, budget: u64) !void {
    var used: u64 = 0;
    while (m.status == .running and m.pending == null and used < budget) : (used += 1) {
        if (m.pc >= d.instrs.len) {
            // e5-dispatch-codeidx / jit-wire-production: `pc >= prog.len` is a
            // fall-off ONLY when NO runtime code is loaded. If `dyn_code` became
            // non-empty MID-GRANT (a `prepare_loading`/`finish_loading` spliced a
            // module and a subsequent BODY `call_ext` dispatched INTO it), this pc
            // indexes `dyn_code`, which this engine does not fetch. YIELD (stay
            // `.running`, pc intact) so `runProduction` re-checks `dyn_code` and
            // defers the remainder to the reference interpreter `ia.run` — which
            // fetches `dyn_code` once `pc >= code_base`. (runProduction's entry
            // guard only saw `dyn_code` EMPTY.) Else it is the true return-with-x0.
            if (m.dyn_code.items.len != 0) return;
            m.status = .halted;
            m.result = m.regs[0];
            return;
        }
        const pc = m.pc;
        m.pc += 1;
        try d.handlers[pc](m, &d.instrs[pc]);
    }
}

/// jit-codegen-arith: native codegen is now LIVE. Engine #4 executes real
/// x86-64 machine code for the covered subset (`move`/`add`/`sub` on smalls —
/// see `jit_codegen.zig`) and falls back to the threaded interpreter for every
/// other op — a MIXED engine. Admitted ONLY by passing the L2 differential
/// below (per docs/OTP30_JIT_FORMAL_ANALYSIS.md: "a native template is admitted
/// only by passing L2"). Flipping this to `true` turns on native execution for
/// covered blocks; uncovered blocks are unaffected (they run threaded). This is
/// NOT the Performance/{P} ledger flip — that waits for the bench-ratchet slice.
pub const use_native_codegen = true;

/// Engine #4's program — the native codegen backend. `native` holds the per-pc
/// table of native templates (+ the W^X exec buffer backing them); `threaded` is
/// the fallback dispatch for any pc with no native template.
pub const NativeProg = struct {
    native: jit_codegen.Compiled,
    threaded: DProg,

    pub fn deinit(self: *NativeProg, gpa: std.mem.Allocator) void {
        self.native.deinit(gpa);
        self.threaded.deinit(gpa);
    }
};

/// The native compiler: emit a native template per covered instruction (into one
/// sealed exec buffer) and keep the threaded dispatch as the fallback engine.
pub fn compileNative(gpa: std.mem.Allocator, prog: ia.Program) !NativeProg {
    var native = try jit_codegen.compile(gpa, prog);
    errdefer native.deinit(gpa);
    const t = try predecode(gpa, prog);
    return .{ .native = native, .threaded = t };
}

/// Engine #4's run loop — the native codegen dispatcher. Mirrors `runThreaded`
/// EXACTLY (budget, fall-off-the-end, pc advance) so the slice/fuel laws carry;
/// the ONLY difference is that a pc with a native template runs its machine-code
/// stub (which updates regs + charges the reduction). A stub returning non-zero
/// is a FALLBACK request (guard failed, e.g. non-small / overflow operand): the
/// op is re-run through the threaded handler, exactly as if it were never
/// compiled — so `runNative ≡ runThreaded` regardless of which path a step takes.
pub fn runNative(m: *ia.Machine, n: *const NativeProg, budget: u64) !void {
    if (!use_native_codegen) return runThreaded(m, &n.threaded, budget);
    var used: u64 = 0;
    while (m.status == .running and m.pending == null and used < budget) : (used += 1) {
        if (m.pc >= n.threaded.instrs.len) { // fell off the end: normal return with x0
            m.status = .halted;
            m.result = m.regs[0];
            return;
        }
        const pc = m.pc;
        m.pc += 1;
        const handled = if (n.native.entries[pc]) |stub| stub(m) == 0 else false;
        if (!handled) try n.threaded.handlers[pc](m, &n.threaded.instrs[pc]);
    }
}

// ============================================================================
// jit-branches (engine #4, CONTROL-FLOW block JIT)
// ============================================================================

/// Engine #4's block-JIT program: a whole-program native region (`jit_codegen.
/// compileBlock`) that runs covered basic blocks — arith AND control flow — end
/// to end as machine code, plus the threaded dispatch as the fallback engine for
/// uncovered ops / runtime slow cases.
pub const NativeBlockProg = struct {
    block: jit_codegen.NativeBlock,
    threaded: DProg,

    pub fn deinit(self: *NativeBlockProg, gpa: std.mem.Allocator) void {
        self.block.deinit(gpa);
        self.threaded.deinit(gpa);
    }
};

/// gap-jit-bif-safepoint: PREDECODE FIRST, then compile against the predecoded
/// copy — not against the caller's `prog`.
///
/// The safepoint blocks bake a POINTER to their instruction into the emitted
/// machine code, so whatever slice `compileBlock` is handed must outlive the
/// exec buffer. `predecode` already `dupe`s the program into `DProg.instrs`,
/// which `NativeBlockProg` owns and frees together with the block — so
/// compiling against THAT copy makes the lifetime a property of this struct
/// rather than an obligation on every caller. The alternative (baking pointers
/// into the caller's slice) would work today and dangle the first time someone
/// compiles a program they then free, with the failure appearing as a wild jump
/// inside JIT'd code.
pub fn compileNativeBlock(gpa: std.mem.Allocator, prog: ia.Program) !NativeBlockProg {
    const t = try predecode(gpa, prog);
    errdefer {
        var tt = t;
        tt.deinit(gpa);
    }
    const block = try jit_codegen.compileBlock(gpa, t.instrs);
    return .{ .block = block, .threaded = t };
}

/// Engine #4's block-JIT run loop. It enters the native region at `m.pc` with the
/// remaining budget pinned in `rsi`; the native code runs covered blocks (native
/// branches included) until (a) the budget is exhausted (YIELD, m.pc at the next
/// op) or (b) it reaches an uncovered op / slow case (FALLBACK, m.pc at that op).
/// Reductions charged by native == covered ops executed, so `used` tracks the
/// interpreter's schedule exactly. On FALLBACK the one uncovered op is run
/// threaded and native is re-entered — a MIXED engine at block granularity, so
/// `runNativeBlock ≡ runThreaded` at every slice boundary (L2/L3).
///
/// jit-wire-production / R2b: `used` tracks retired INSTRUCTIONS (`m.instrs`),
/// which is the budget currency preemption rides (the native rsi budget consumes
/// `instrs` too), NOT the per-call `m.reductions`. A threaded fallback op charges
/// `m.instrs - before` (its REAL instr delta — 1, or N for a `bump_reductions(N)`
/// which bumps BOTH counters), so `used == m.instrs - start` EXACTLY — the loop's
/// `used < budget` is precisely `ia.run`'s instr-based budget check, making
/// `runNativeBlock ≡ ia.run` even on the production path where a process calls
/// `bump_reductions`. The per-call `m.reductions` is charged in lock-step by both
/// engines (`reductionCost`) and compared by `eqMachines`.
pub fn runNativeBlock(m: *ia.Machine, n: *const NativeBlockProg, budget: u64) !void {
    if (!use_native_codegen or !jit_codegen.native_supported) return runThreaded(m, &n.threaded, budget);
    var used: u64 = 0;
    while (m.status == .running and m.pending == null and used < budget) {
        if (m.pc >= n.threaded.instrs.len) {
            // jit-wire-production: see runThreaded — a `pc >= prog.len` with
            // `dyn_code` populated MID-GRANT is a dispatch INTO runtime code, not a
            // fall-off. YIELD so `runProduction` re-checks and defers to `ia.run`.
            if (m.dyn_code.items.len != 0) return;
            m.status = .halted;
            m.result = m.regs[0];
            return;
        }
        const entry = n.block.entries[m.pc] orelse {
            // no native block at this pc (non-supported host path): one threaded op
            const pc = m.pc;
            m.pc += 1;
            const before = m.instrs;
            try n.threaded.handlers[pc](m, &n.threaded.instrs[pc]);
            used += m.instrs - before; // REAL instr delta (bump charges N)
            continue;
        };
        const before = m.instrs;
        const rc = entry(m, budget - used); // ← REAL native block execution
        used += m.instrs - before; // instr delta == covered ops run
        if (rc == 1 and used < budget and
            m.status == .running and m.pending == null and m.pc < n.threaded.instrs.len)
        {
            // FALLBACK: run the single uncovered op through the interpreter, then
            // re-enter native at the resulting pc.
            const pc = m.pc;
            m.pc += 1;
            const before2 = m.instrs;
            try n.threaded.handlers[pc](m, &n.threaded.instrs[pc]);
            used += m.instrs - before2; // REAL instr delta (bump charges N)
        }
    }
}

/// jit-bench-realprog: the executed-op NATIVE COVERAGE split of a native-block
/// run. `native_reds` = reductions charged by a native machine-code stub;
/// `fallback_reds` = reductions charged by the threaded fallback (uncovered op
/// or a runtime slow-case guard failing). `native_reds/(native_reds+fallback_reds)`
/// is the honest fraction of the program's EXECUTED work that ran as machine code
/// — the number that tells you whether a real program is native-bound (≈1.0) or
/// interpreter-bound (≈0.0, e.g. alloc-heavy programs whose put_list/test_heap
/// still fall back). Zero-cost to the timed path (a separate, un-timed probe).
pub const NativeSplit = struct {
    native_reds: u64,
    fallback_reds: u64,
    pub fn coverage(self: NativeSplit) f64 {
        const total = self.native_reds + self.fallback_reds;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.native_reds)) / @as(f64, @floatFromInt(total));
    }
};

/// Run engine #4 EXACTLY like `runNativeBlock` but attribute each charged
/// reduction to native vs fallback. Semantically identical to `runNativeBlock`
/// (same regs/pc/reductions/status afterwards); only used to MEASURE coverage,
/// never on the timed hot path. On a non-supported host every op is a threaded
/// fallback, so coverage honestly reports 0.0 (no native path, no fabrication).
pub fn runNativeBlockCounted(m: *ia.Machine, n: *const NativeBlockProg, budget: u64) !NativeSplit {
    return runNativeBlockAttributed(m, n, budget, null);
}

/// gap-jit-fallback-attribution: WHERE a run's fallback work goes, per BEAM pc.
///
/// `NativeSplit` answers "how much of this program ran as machine code" with one
/// scalar. That is the right number for a verdict and the wrong number for a
/// decision: a coverage of 0.58 does not say whether the missing 42% is one
/// trivially-coverable op executed constantly or a long tail of hard ones, and
/// those call for opposite work. Four codegen increments have now been spent on
/// the COVERED subset without anything measuring whether the covered subset is
/// where a real program's time goes — the same blind spot `attribute` was built
/// to close statically, still open dynamically.
///
/// `by_pc[i]` is the number of INSTRUCTIONS retired by the threaded fallback at
/// BEAM pc `i` (the same currency `NativeSplit` counts, so the two compose).
/// Ranking it names the op to cover next, instead of reading the emitter and
/// guessing — which is how this epoch already produced one 2x-wrong estimate.
pub const FallbackProfile = struct {
    split: NativeSplit,
    /// len == prog.len. Owned by the caller.
    by_pc: []u64,

    pub fn deinit(self: *FallbackProfile, gpa: std.mem.Allocator) void {
        gpa.free(self.by_pc);
    }

    /// The pc that retired the most fallback instructions, or null when the run
    /// fell back nowhere (a fully native run — the honest answer is "no op to
    /// cover", never an arbitrary index).
    pub fn hottestPc(self: FallbackProfile) ?usize {
        var best: ?usize = null;
        for (self.by_pc, 0..) |v, i| {
            if (v == 0) continue;
            if (best == null or v > self.by_pc[best.?]) best = i;
        }
        return best;
    }
};

/// Run engine #4 and attribute fallback work per pc. Identical execution to
/// `runNativeBlockCounted` (they are the same driver); this one allocates the
/// attribution vector. Never on a timed path.
pub fn runNativeBlockProfiled(
    gpa: std.mem.Allocator,
    m: *ia.Machine,
    n: *const NativeBlockProg,
    budget: u64,
) !FallbackProfile {
    const by_pc = try gpa.alloc(u64, n.threaded.instrs.len);
    errdefer gpa.free(by_pc);
    @memset(by_pc, 0);
    const split = try runNativeBlockAttributed(m, n, budget, by_pc);
    return .{ .split = split, .by_pc = by_pc };
}

/// The ONE driver behind both. `by_pc` null ⇒ aggregate only. Sharing the body
/// is what makes "the profiled run executes exactly what the counted run
/// executes" true by construction rather than by two implementations agreeing.
fn runNativeBlockAttributed(
    m: *ia.Machine,
    n: *const NativeBlockProg,
    budget: u64,
    by_pc: ?[]u64,
) !NativeSplit {
    // R2b: native-coverage is attributed per retired INSTRUCTION (`m.instrs`) —
    // the fraction of OPS that ran as machine code (the per-call `reductions`
    // would count only calls, a useless coverage denominator).
    var split = NativeSplit{ .native_reds = 0, .fallback_reds = 0 };
    if (!use_native_codegen or !jit_codegen.native_supported) {
        // no native path: everything the threaded engine charges is fallback.
        // Attributing it per pc would need a threaded-path hook and would say
        // nothing useful (EVERY op is uncovered here), so the vector stays zero
        // and `split` carries the honest 0.0 coverage.
        const before = m.instrs;
        try runThreaded(m, &n.threaded, budget);
        split.fallback_reds = m.instrs - before;
        return split;
    }
    var used: u64 = 0;
    while (m.status == .running and m.pending == null and used < budget) {
        if (m.pc >= n.threaded.instrs.len) {
            m.status = .halted;
            m.result = m.regs[0];
            return split;
        }
        const entry = n.block.entries[m.pc] orelse {
            const pc = m.pc;
            m.pc += 1;
            const before = m.instrs;
            try n.threaded.handlers[pc](m, &n.threaded.instrs[pc]);
            const d = m.instrs - before;
            used += d;
            split.fallback_reds += d;
            // UNEXERCISED, and said so rather than left to look tested. On a
            // supported host `compileBlock` fills EVERY entry (an uncovered op
            // gets a trampoline block, not a null), so this `orelse` arm cannot
            // fire — and on an unsupported host the early `runThreaded` return
            // above takes over. It is defensive code for a shape the current
            // compiler does not produce, mirrored from `runNativeBlock`; the
            // attribution here is kept consistent with the live site below, but
            // no law reaches it.
            if (by_pc) |v| v[pc] += d;
            continue;
        };
        const before = m.instrs;
        const rc = entry(m, budget - used);
        const dn = m.instrs - before;
        used += dn;
        split.native_reds += dn;
        if (rc == 1 and used < budget and
            m.status == .running and m.pending == null and m.pc < n.threaded.instrs.len)
        {
            const pc = m.pc;
            m.pc += 1;
            const before2 = m.instrs;
            try n.threaded.handlers[pc](m, &n.threaded.instrs[pc]);
            const d2 = m.instrs - before2;
            used += d2;
            split.fallback_reds += d2;
            // THE LIVE SITE — every fallback on a supported host arrives here,
            // both the uncovered-op trampoline and a covered block whose runtime
            // guard failed (a non-small operand, an overflow, a full CP stack).
            // `pc` is captured BEFORE the handler moved `m.pc`: reading `m.pc`
            // afterwards names the next op, the off-by-one that makes a profiler
            // blame the innocent instruction after the guilty one (MUT-FBA-1,
            // killed by LOCALISATION and by the coverage ratchet's
            // residual-accounting arm). Dropping it entirely is MUT-FBA-2,
            // killed by CONSERVATION.
            if (by_pc) |v| v[pc] += d2;
        }
    }
    return split;
}

// ============================================================================
// jit-wire-production — engine #4 on the REAL per-process run path
// ============================================================================

/// jit-wire-production: the runtime selector for the PRODUCTION run path. When
/// `true` (the default), the sequential scheduler's per-process grant
/// (`proc.Vm.grantOnly`) runs each covered block through engine #4 (native
/// machine code for arith/move/branch, threaded fallback otherwise) via
/// `runProduction`; when `false` it runs the reference interpreter `ia.run`.
/// This is a pure ENGINE swap — the denotation is identical (`runProduction ≡
/// ia.run`, the whole-corpus law below) — never a semantics change. Flip it off
/// for the safest possible landing (interpreter everywhere); the seam and its
/// proof stand either way. It is NOT the Performance/{P} ledger flip: that waits
/// for a measured end-to-end gain on this wired path against BeamAsm.
pub var use_production_native: bool = true;

/// jit-wire-production: the PRODUCTION dispatch cache — compile-ONCE per program
/// identity. Real BEAM processes SHARE one immutable `Program` slice (`p.prog`),
/// stable for a Vm's lifetime; compiling it per grant would be O(n) waste, so we
/// key the compiled `NativeBlockProg` by `(ptr,len)` and reuse it across every
/// grant and every process on that program. The compiled block owns its sealed
/// W^X exec buffer (jit_exec's page ledger); `deinit` frees every entry — no
/// leak, no double-free. Vm-owned; freed in `proc.Vm.deinit`.
pub const ProdCache = struct {
    const Key = struct { ptr: usize, len: usize };
    map: std.AutoHashMapUnmanaged(Key, *NativeBlockProg) = .{},

    pub fn deinit(self: *ProdCache, gpa: std.mem.Allocator) void {
        var it = self.map.valueIterator();
        while (it.next()) |v| {
            v.*.deinit(gpa);
            gpa.destroy(v.*);
        }
        self.map.deinit(gpa);
    }

    /// get-or-compile the NativeBlockProg for `prog` (keyed by slice identity).
    fn getOrCompile(self: *ProdCache, gpa: std.mem.Allocator, prog: ia.Program) !*NativeBlockProg {
        const key = Key{ .ptr = @intFromPtr(prog.ptr), .len = prog.len };
        if (self.map.get(key)) |nbp| return nbp;
        const nbp = try gpa.create(NativeBlockProg);
        errdefer gpa.destroy(nbp);
        nbp.* = try compileNativeBlock(gpa, prog);
        errdefer nbp.deinit(gpa);
        try self.map.put(gpa, key, nbp);
        return nbp;
    }
};

/// jit-wire-production: the PRODUCTION native run — the drop-in replacement for
/// `ia.run(m, prog, budget)` on the sequential scheduler path. Runs engine #4
/// (native block JIT + threaded fallback), caching the compiled program by
/// identity. Falls back to the reference interpreter `ia.run` (never crashes,
/// never mis-executes) whenever engine #4 is not a faithful equal of `ia.run`:
///   * the switch is off (operator chose the interpreter), OR
///   * `use_native_codegen` is off / the host lacks native codegen (non
///     x86-64-linux — `runNativeBlock` would already fall back, but we short-
///     circuit to skip the useless compile), OR
///   * DYNAMIC code is present (`m.dyn_code` non-empty): `stepOne` fetches
///     runtime-loaded code once `pc >= prog.len`, but engine #4 only indexes
///     `prog` and treats `pc >= prog.len` as fall-off-the-end. With `dyn_code`
///     empty the two agree exactly (both HALT at `pc >= prog.len`); with dyn_code
///     loaded they would diverge, so we defer to `ia.run`. Re-checked every call
///     (grantOnly loops), so a process that hot-loads code transparently moves to
///     the interpreter from that point, OR
///   * compilation FAILS (FMEA: OOM / unsupported shape → interpreter, never a
///     crash and never a wrong result).
/// LAW jit-wire-production (whole corpus): `runProduction(cache, m, p, F) ≡
/// ia.run(m, p, F)` — identical denotation AND reductions (L3) for EVERY program,
/// not just the native-covered subset (the mixed engine handles all of them).
pub fn runProduction(
    cache: *ProdCache,
    gpa: std.mem.Allocator,
    m: *ia.Machine,
    prog: ia.Program,
    budget: u64,
) !void {
    if (!use_production_native or !use_native_codegen or !jit_codegen.native_supported or
        m.dyn_code.items.len != 0)
        return ia.run(m, prog, budget);
    const nbp = cache.getOrCompile(gpa, prog) catch return ia.run(m, prog, budget); // FMEA
    return runNativeBlock(m, nbp, budget);
}

/// gap-r2c-behavioral-parity-native (R2c epoch Inc2, DIVERGENCE 608): a
/// REDUCTION-bounded driver over the production JIT. Preempts on the OTP-faithful
/// per-call `m.reductions` while KEEPING `runProduction`'s native-block coverage —
/// the interpreter path (`ia.runReductionPreempt`, Inc1) does the reduction bound
/// but throws away the JIT. This closes that gap: a reduction-preempted process
/// still runs its arith/move hot path as machine code.
///
/// ★ THE EXACTNESS THEOREM (why no codegen change is needed). `reductionCost(ins)
/// ∈ {0,1}` for EVERY instruction (`call`/tail-`jump` charge 1, everything else 0
/// — see `ia.reductionCost`/`reductionCostBlock`). Therefore running the JIT for
/// `k` instructions charges AT MOST `k` reductions. Bounding each `runProduction`
/// call's INSTR budget by `chunk = min(reds_left, instrs_left)` gives:
///   (a) NO OVERSHOOT — `m.reductions` can rise by ≤ `chunk ≤ reds_left`, so it
///       never passes `red_budget`;
///   (b) EXACTNESS — the tail chunks shrink to size 1 (a single reduction-charging
///       op is the finest grain), so it converges to EXACTLY `red_budget`
///       reductions, identical to the interpreter's per-op `runReductionPreempt`.
/// `instr_cap` is the UCA-R2C-1 hang fail-safe: a 0-reduction straight-line region
/// charges 0 reds forever, but `chunk = instrs_left` keeps advancing `m.instrs`
/// until the cap binds — bounded preemption, no hang. Both budgets are DELTAS from
/// entry (like `ia.runReductionPreempt`). Additive: unreachable unless the
/// scheduler opts in (`Vm.reduction_preempt_native`), so all default results are
/// byte-identical.
pub fn runProductionReds(
    cache: *ProdCache,
    gpa: std.mem.Allocator,
    m: *ia.Machine,
    prog: ia.Program,
    red_budget: u64,
    instr_cap: u64,
) !void {
    const r_start = m.reductions;
    const i_start = m.instrs;
    while (m.status == .running and m.pending == null and
        m.reductions - r_start < red_budget and m.instrs - i_start < instr_cap)
    {
        const reds_left = red_budget - (m.reductions - r_start); // ≥ 1 (loop guard)
        const instrs_left = instr_cap - (m.instrs - i_start); //   ≥ 1 (loop guard)
        const chunk = @min(reds_left, instrs_left); // ≥ 1 — the JIT instr budget
        const before = m.instrs;
        try runProduction(cache, gpa, m, prog, chunk);
        // A live proc under a ≥1 budget retires ≥1 instr; the `== before` guard is
        // a belt-and-braces stall-breaker (a degenerate host can't spin the loop).
        if (m.instrs == before) break;
    }
}

// ============================================================================
// THE DIFFERENTIAL HARNESS
// ============================================================================

fn freshPair(gpa: std.mem.Allocator, atoms: *AtomTable, seed: u64) !struct { a: ia.Machine, b: ia.Machine } {
    var m1 = try ia.Machine.init(gpa, atoms);
    errdefer m1.deinit();
    var m2 = try ia.Machine.init(gpa, atoms);
    errdefer m2.deinit();
    var p1 = std.Random.DefaultPrng.init(seed);
    var p2 = std.Random.DefaultPrng.init(seed);
    const r1 = p1.random();
    const r2 = p2.random();
    // E5.2: seed only the low 16 x-slots (the threaded/interpreter differential
    // corpus references x0..x15 only); higher slots stay nil in BOTH twins.
    for (m1.regs[0..16]) |*r| r.* = FinalTerms.int(&m1.ctx, @as(i64, r1.int(i32)));
    for (m2.regs[0..16]) |*r| r.* = FinalTerms.int(&m2.ctx, @as(i64, r2.int(i32)));
    return .{ .a = m1, .b = m2 };
}

test "DIFFERENTIAL: threaded engine ≡ switch interpreter at every slice boundary" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0xD13A, .iterations = 60 };

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();

        var buf: [16]ia.CInstr = undefined;
        const prog = ia.randProgram(random, &buf);
        var d = try predecode(gpa, prog);
        defer d.deinit(gpa);

        var pair = try freshPair(gpa, &atoms, cfg.seed +% i +% 77);
        defer pair.a.deinit();
        defer pair.b.deinit();

        // matched random slices; compare FULL machine state at every boundary
        var left: u64 = 90;
        while (left > 0) {
            const slice = 1 + random.uintLessThan(u64, 9);
            const take = @min(slice, left);
            try ia.run(&pair.a, prog, take);
            try runThreaded(&pair.b, &d, take);
            try expectLaw(try ia.eqMachines(&pair.a, &pair.b, sa), "differential: states equal at slice boundary", cfg, i);
            left -= take;
            if (pair.a.status != .running or pair.a.pending != null) break;
        }
    }
}

test "DIFFERENTIAL on REAL compiled code: mylists under engine #3" {
    const gpa = std.testing.allocator;
    var mod = try loader.parse(gpa, @embedFile("mylists.beam"));
    defer mod.deinit();
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const t = try loader.translate(gpa, &mod, &atoms, null);
    defer {
        gpa.free(t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs); // E3.11: pc->source-location table
    }
    var d = try predecode(gpa, t.prog);
    defer d.deinit(gpa);
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    // sum(seq(20)) under both engines, slice-driven, states compared at
    // every boundary AND the final result pinned to the node's 210
    var m1 = try ia.Machine.init(gpa, &atoms);
    defer m1.deinit();
    var m2 = try ia.Machine.init(gpa, &atoms);
    defer m2.deinit();
    const seq_pc = loader.entryOf(&t, "seq", 1).?;
    const sum_pc = loader.entryOf(&t, "sum", 1).?;

    for ([_]u32{ seq_pc, sum_pc }) |entry| {
        m1.status = .running;
        m2.status = .running;
        m1.pc = entry;
        m2.pc = entry;
        m1.regs[0] = if (entry == seq_pc) FinalTerms.int(&m1.ctx, 20) else m1.result;
        m2.regs[0] = if (entry == seq_pc) FinalTerms.int(&m2.ctx, 20) else m2.result;
        m1.stack.clearRetainingCapacity();
        m2.stack.clearRetainingCapacity();
        m1.ystack.clearRetainingCapacity();
        m2.ystack.clearRetainingCapacity();
        var guard: usize = 0;
        while (m1.status == .running) : (guard += 1) {
            if (guard > 100_000) return error.GateDidNotTerminate;
            try ia.run(&m1, t.prog, 7);
            try runThreaded(&m2, &d, 7);
            try std.testing.expect(try ia.eqMachines(&m1, &m2, sa));
        }
    }
    try std.testing.expect(FinalTerms.eqlExact(&m1.ctx, m1.result, FinalTerms.int(&m1.ctx, 210)));
    try std.testing.expect(FinalTerms.eqlExact(&m2.ctx, m2.result, FinalTerms.int(&m2.ctx, 210)));
}

test "FUEL + SLICE INVARIANCE re-verified on engine #3" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0xD13B, .iterations = 50 };

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();
        var buf: [16]ia.CInstr = undefined;
        const prog = ia.randProgram(random, &buf);
        var d = try predecode(gpa, prog);
        defer d.deinit(gpa);
        const fuel: u64 = 60;

        var pair = try freshPair(gpa, &atoms, cfg.seed +% i +% 5);
        defer pair.a.deinit();
        defer pair.b.deinit();

        // one shot vs random partition, both on engine #3
        try runThreaded(&pair.a, &d, fuel);
        var left: u64 = fuel;
        while (left > 0) {
            const slice = 1 + random.uintLessThan(u64, @min(left, 7));
            try runThreaded(&pair.b, &d, slice);
            left -= slice;
        }
        try expectLaw(try ia.eqMachines(&pair.a, &pair.b, sa), "threaded: slice invariance", cfg, i);
        try expectLaw(pair.a.instrs <= fuel, "threaded: fuel upper bound", cfg, i); // R2b: preemption rides instrs
        if (pair.a.status == .running and pair.a.pending == null)
            try expectLaw(pair.a.instrs == fuel, "threaded: fuel exactness", cfg, i);
    }
}

test "DIFFERENTIAL: native engine ≡ threaded engine at every slice boundary" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0xD13C, .iterations = 60 };

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();

        var buf: [16]ia.CInstr = undefined;
        const prog = ia.randProgram(random, &buf);
        var t = try predecode(gpa, prog);
        defer t.deinit(gpa);
        var n = try compileNative(gpa, prog);
        defer n.deinit(gpa);

        var pair = try freshPair(gpa, &atoms, cfg.seed +% i +% 88);
        defer pair.a.deinit();
        defer pair.b.deinit();

        var left: u64 = 90;
        while (left > 0) {
            const slice = 1 + random.uintLessThan(u64, 9);
            const take = @min(slice, left);
            try runThreaded(&pair.a, &t, take);
            try runNative(&pair.b, &n, take);
            try expectLaw(try ia.eqMachines(&pair.a, &pair.b, sa), "differential: native states equal at slice boundary", cfg, i);
            left -= take;
            if (pair.a.status != .running or pair.a.pending != null) break;
        }
    }
}

test "L2/L3 native codegen: move/add/SUB over adversarial operands ≡ threaded (aliasing, imm boundaries, overflow fallback)" {
    // The auto-generated corpus never emits `sub` and rarely forces the
    // small-overflow FALLBACK path inside the native engine. This law builds
    // programs of ONLY natively-covered ops (move/add/sub) over adversarial
    // operands — immediate boundaries (±i32 max, small-range max), register
    // ALIASING (dst == a source), and sums that OVERFLOW the small range (so a
    // native stub returns the fallback signal and the interpreter re-runs it) —
    // and checks native ≡ threaded at every slice boundary, INCLUDING reductions
    // (L3). It also asserts the covered ops actually compiled to native stubs.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x3A17, .iterations = 200 };

    const maxsmall: i64 = (1 << 59) - 1;
    const boundary_imms = [_]i64{ 0, 1, -1, 2, -2, 7, maxsmall, -maxsmall, 0x7fff_ffff, -0x8000_0000, 100, -100 };

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();

        // Build a straight-line program of covered ops only. Operands are drawn
        // from x0..x5 (encouraging aliasing) and boundary immediates.
        const plen = 4 + random.uintLessThan(usize, 10);
        var buf: [16]ia.CInstr = undefined;
        const randCovSrc = struct {
            fn f(r: std.Random, imms: []const i64) ia.Src {
                return switch (r.uintLessThan(u8, 3)) {
                    0, 1 => .{ .x = @as(ia.XReg, @intCast(r.uintLessThan(u8, 6))) },
                    else => .{ .imm = imms[r.uintLessThan(usize, imms.len)] },
                };
            }
        }.f;
        for (buf[0..plen]) |*ins| {
            ins.* = switch (random.uintLessThan(u8, 3)) {
                0 => .{ .move = .{ .src = randCovSrc(random, &boundary_imms), .dst = @as(ia.XReg, @intCast(random.uintLessThan(u8, 6))) } },
                1 => .{ .add = .{ .a = randCovSrc(random, &boundary_imms), .b = randCovSrc(random, &boundary_imms), .dst = @as(ia.XReg, @intCast(random.uintLessThan(u8, 6))) } },
                else => .{ .sub = .{ .a = randCovSrc(random, &boundary_imms), .b = randCovSrc(random, &boundary_imms), .dst = @as(ia.XReg, @intCast(random.uintLessThan(u8, 6))) } },
            };
        }
        const prog: ia.Program = buf[0..plen];

        var t = try predecode(gpa, prog);
        defer t.deinit(gpa);
        var n = try compileNative(gpa, prog);
        defer n.deinit(gpa);

        // every covered op compiled to a REAL native stub (on the supported host)
        if (jit_codegen.native_supported) {
            for (0..plen) |k| try std.testing.expect(n.native.entries[k] != null);
        }

        // seed x0..x5 with boundary smalls (so a later add/sub can overflow).
        var pair = try freshPair(gpa, &atoms, cfg.seed +% i +% 123);
        defer pair.a.deinit();
        defer pair.b.deinit();
        for (0..6) |r| {
            const v = boundary_imms[random.uintLessThan(usize, boundary_imms.len)];
            pair.a.regs[r] = FinalTerms.int(&pair.a.ctx, v);
            pair.b.regs[r] = FinalTerms.int(&pair.b.ctx, v);
        }

        var left: u64 = @intCast(plen);
        while (left > 0) {
            const take = @min(1 + random.uintLessThan(u64, 4), left);
            try runThreaded(&pair.a, &t, take);
            try runNative(&pair.b, &n, take);
            try expectLaw(try ia.eqMachines(&pair.a, &pair.b, sa), "L2/L3 native≡threaded (adversarial arith)", cfg, i);
            left -= take;
            if (pair.a.status != .running or pair.a.pending != null) break;
        }
    }
}

// ---- jit-branches: L2/L3 over CONTROL-FLOW programs (block JIT) -------------

// A generator of control-flow programs of covered ops (move/add/sub/jump/is_lt/
// test_eq/cmp_test) with valid branch targets. Terminating is NOT required — the
// budget bounds execution and we compare native vs threaded under the SAME
// budget, so a back-edge loop just runs `budget` ops in both engines.
fn randCfSrc(r: std.Random, imms: []const i64) ia.Src {
    return switch (r.uintLessThan(u8, 3)) {
        0, 1 => .{ .x = @as(ia.XReg, @intCast(r.uintLessThan(u8, 6))) },
        else => .{ .imm = imms[r.uintLessThan(usize, imms.len)] },
    };
}

fn randCfProg(r: std.Random, buf: []ia.CInstr, imms: []const i64) ia.Program {
    const len: u32 = @intCast(buf.len);
    for (buf, 0..) |*ins, pc| {
        // bias branch targets toward BACKWARD edges (loops) and forward exits.
        const tgt: u32 = @intCast(r.uintLessThan(usize, buf.len + 1)); // 0..len (len==end)
        ins.* = switch (r.uintLessThan(u8, 8)) {
            0 => .{ .move = .{ .src = randCfSrc(r, imms), .dst = @intCast(r.uintLessThan(u8, 6)) } },
            1 => .{ .add = .{ .a = randCfSrc(r, imms), .b = randCfSrc(r, imms), .dst = @intCast(r.uintLessThan(u8, 6)) } },
            2 => .{ .sub = .{ .a = randCfSrc(r, imms), .b = randCfSrc(r, imms), .dst = @intCast(r.uintLessThan(u8, 6)) } },
            3 => .{ .jump = .{ .to = tgt } },
            4 => .{ .is_lt = .{ .a = randCfSrc(r, imms), .b = randCfSrc(r, imms), .else_to = tgt } },
            5 => .{ .test_eq = .{ .a = randCfSrc(r, imms), .b = randCfSrc(r, imms), .else_to = tgt } },
            6 => .{ .cmp_test = .{ .op = switch (r.uintLessThan(u8, 4)) {
                0 => .ge,
                1 => .eq_arith,
                2 => .ne_arith,
                else => .ne_exact,
            }, .a = randCfSrc(r, imms), .b = randCfSrc(r, imms), .else_to = tgt } },
            else => .{ .move = .{ .src = randCfSrc(r, imms), .dst = @intCast(r.uintLessThan(u8, 6)) } },
        };
        _ = pc;
        _ = len;
    }
    return buf[0..];
}

test "L2/L3 native BLOCK ≡ threaded over CONTROL-FLOW programs (branches, loops, fuel boundaries)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x8A17, .iterations = 300 };

    const maxsmall: i64 = (1 << 59) - 1;
    const boundary_imms = [_]i64{ 0, 1, -1, 2, -2, 7, maxsmall, -maxsmall, 0x7fff_ffff, -0x8000_0000, 20, -20 };

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();

        const plen = 3 + random.uintLessThan(usize, 11);
        var buf: [16]ia.CInstr = undefined;
        const prog = randCfProg(random, buf[0..plen], &boundary_imms);

        var t = try predecode(gpa, prog);
        defer t.deinit(gpa);
        var n = try compileNativeBlock(gpa, prog);
        defer n.deinit(gpa);

        // every covered op has a native block entry (on the supported host)
        if (jit_codegen.native_supported) {
            for (0..plen) |k| try std.testing.expect(n.block.entries[k] != null);
        }

        var pair = try freshPair(gpa, &atoms, cfg.seed +% i +% 321);
        defer pair.a.deinit();
        defer pair.b.deinit();
        // seed x0..x5 with boundary smalls, and occasionally a NON-small (nil/atom)
        // in x0 to force a branch/arith FALLBACK to the interpreter.
        for (0..6) |rr| {
            const v = boundary_imms[random.uintLessThan(usize, boundary_imms.len)];
            pair.a.regs[rr] = FinalTerms.int(&pair.a.ctx, v);
            pair.b.regs[rr] = FinalTerms.int(&pair.b.ctx, v);
        }
        if (random.uintLessThan(u8, 4) == 0) {
            pair.a.regs[0] = FinalTerms.nil(&pair.a.ctx);
            pair.b.regs[0] = FinalTerms.nil(&pair.b.ctx);
        }

        // Random slices whose TOTAL fuel is fixed; a back-edge loop keeps running
        // (bounded by the fuel — a hang would be a failed law). Fuel boundaries
        // {1, small} are covered by the random slice widths.
        var left: u64 = 120;
        while (left > 0) {
            const take = @min(1 + random.uintLessThan(u64, 7), left);
            try runThreaded(&pair.a, &t, take);
            try runNativeBlock(&pair.b, &n, take);
            try expectLaw(try ia.eqMachines(&pair.a, &pair.b, sa), "L2/L3 native-block ≡ threaded (control flow)", cfg, i);
            try expectLaw(pair.a.reductions == pair.b.reductions, "L3 native-block reductions equal", cfg, i);
            left -= take;
            if (pair.a.status != .running or pair.a.pending != null) break;
        }
    }
}

test "NATIVE COUNTED LOOP runs end-to-end under engine #4 block JIT (sum(20)=210)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    // while (N >= 1) { Acc += N; N -= 1 }  then `halt Acc` (uncovered → threaded).
    const prog = [_]ia.CInstr{
        .{ .cmp_test = .{ .op = .ge, .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .else_to = 4 } },
        .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 0 }, .dst = 1 } },
        .{ .sub = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } },
        .{ .jump = .{ .to = 0 } },
        .{ .halt = .{ .src = .{ .x = 1 } } },
    };
    var t = try predecode(gpa, prog[0..]);
    defer t.deinit(gpa);
    var n = try compileNativeBlock(gpa, prog[0..]);
    defer n.deinit(gpa);
    // the loop body (guard/add/sub/jump) is genuinely native; only `halt` falls back.
    if (jit_codegen.native_supported) {
        for (0..4) |k| try std.testing.expect(n.block.entries[k] != null);
    }

    var m1 = try ia.Machine.init(gpa, &atoms); // threaded reference
    defer m1.deinit();
    var m2 = try ia.Machine.init(gpa, &atoms); // native block JIT
    defer m2.deinit();
    m1.regs[0] = FinalTerms.int(&m1.ctx, 20);
    m1.regs[1] = FinalTerms.int(&m1.ctx, 0);
    m2.regs[0] = FinalTerms.int(&m2.ctx, 20);
    m2.regs[1] = FinalTerms.int(&m2.ctx, 0);
    // slice-driven so the loop crosses many budget boundaries mid-iteration
    var guard: usize = 0;
    while (m1.status == .running) : (guard += 1) {
        if (guard > 100_000) return error.GateDidNotTerminate; // a native hang is a failed law
        try runThreaded(&m1, &t, 3);
        try runNativeBlock(&m2, &n, 3);
        try std.testing.expect(try ia.eqMachines(&m1, &m2, sa));
    }
    try std.testing.expect(m2.status == .halted);
    try std.testing.expect(FinalTerms.eqlExact(&m2.ctx, m2.result, FinalTerms.int(&m2.ctx, 210)));
    try std.testing.expect(FinalTerms.eqlExact(&m1.ctx, m1.result, FinalTerms.int(&m1.ctx, 210)));
}

// ---- jit-widen-coverage: L2/L3 over LIST/TUPLE/TYPE-TEST-heavy programs -------

// Structural registers, seeded IDENTICALLY in both twins and NEVER written by a
// generated op, so get_list/get_tuple_element always read a valid cons/tuple and
// the interpreter never dereferences a bad word:
//   x0 = a proper 3-element list   x1 = a 3-tuple   x2 = an atom
//   x3 = a small int               x4 = nil         x5 = a bignum (boxed non-tuple)
// Scratch registers x8..x11 hold smalls and are the only arith/move/get targets.
fn seedListStructural(m: *ia.Machine) !void {
    const c1 = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 30), FinalTerms.nil(&m.ctx));
    const c2 = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 20), c1);
    m.regs[0] = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 10), c2);
    m.regs[1] = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, 100), FinalTerms.int(&m.ctx, 200), FinalTerms.int(&m.ctx, 300) });
    m.regs[2] = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern("jitatom")); // real interned atom (nameOf-safe)
    m.regs[3] = FinalTerms.int(&m.ctx, 7);
    m.regs[4] = FinalTerms.nil(&m.ctx);
    m.regs[5] = try FinalTerms.intFromI128(&m.ctx, (@as(i128, 1) << 70)); // bignum
    for ([_]usize{ 8, 9, 10, 11 }) |r| m.regs[r] = FinalTerms.int(&m.ctx, @intCast(r));
}

const scratch_regs = [_]ia.XReg{ 8, 9, 10, 11 };
const struct_regs = [_]ia.XReg{ 0, 1, 2, 3, 4, 5 };

fn randScratch(r: std.Random) ia.XReg {
    return scratch_regs[r.uintLessThan(usize, scratch_regs.len)];
}
fn randScratchSrc(r: std.Random, imms: []const i64) ia.Src {
    return switch (r.uintLessThan(u8, 3)) {
        0, 1 => .{ .x = randScratch(r) },
        else => .{ .imm = imms[r.uintLessThan(usize, imms.len)] },
    };
}
fn randStructSrc(r: std.Random) ia.Src {
    return .{ .x = struct_regs[r.uintLessThan(usize, struct_regs.len)] };
}

// Generate a program mixing the NEW non-allocating heap-reading ops (get_list on
// x0, get_tuple_element on x1, is_cons / type_test over the structural set) with
// the register-only tier (move/add/sub/jump/is_lt/cmp_test on the scratch set).
fn randListProg(r: std.Random, buf: []ia.CInstr, imms: []const i64) ia.Program {
    const len: u32 = @intCast(buf.len);
    const tt_kinds = [_]ia.TypeTestKind{ .list, .atom, .integer, .tuple };
    for (buf) |*ins| {
        const tgt: u32 = @intCast(r.uintLessThan(usize, buf.len + 1)); // 0..len (len==end)
        ins.* = switch (r.uintLessThan(u8, 10)) {
            0 => .{ .get_list = .{ .src = .{ .x = 0 }, .hd = .{ .x = randScratch(r) }, .tl = .{ .x = randScratch(r) } } },
            1 => .{ .get_tuple_elem = .{ .src = .{ .x = 1 }, .index = @intCast(r.uintLessThan(u16, 3)), .dst = .{ .x = randScratch(r) } } },
            2 => .{ .is_cons = .{ .src = randStructSrc(r), .else_to = tgt } },
            3 => .{ .type_test = .{ .kind = tt_kinds[r.uintLessThan(usize, tt_kinds.len)], .src = randStructSrc(r), .else_to = tgt } },
            4 => .{ .move = .{ .src = randScratchSrc(r, imms), .dst = randScratch(r) } },
            5 => .{ .add = .{ .a = randScratchSrc(r, imms), .b = randScratchSrc(r, imms), .dst = randScratch(r) } },
            6 => .{ .sub = .{ .a = randScratchSrc(r, imms), .b = randScratchSrc(r, imms), .dst = randScratch(r) } },
            7 => .{ .jump = .{ .to = tgt } },
            8 => .{ .is_lt = .{ .a = randScratchSrc(r, imms), .b = randScratchSrc(r, imms), .else_to = tgt } },
            else => .{ .cmp_test = .{ .op = .ge, .a = randScratchSrc(r, imms), .b = randScratchSrc(r, imms), .else_to = tgt } },
        };
    }
    _ = len;
    return buf[0..];
}

test "L2/L3 native BLOCK ≡ threaded over LIST/TUPLE/TYPE-TEST programs (get_list/get_tuple_element/type-tests)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x715, .iterations = 300 };
    const boundary_imms = [_]i64{ 0, 1, -1, 2, -2, 7, 20, -20 };

    var covered_ops: usize = 0; // op-shapes we expect native
    var native_entries: usize = 0; // of those, how many actually compiled native
    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();

        const plen = 4 + random.uintLessThan(usize, 10);
        var buf: [16]ia.CInstr = undefined;
        const prog = randListProg(random, buf[0..plen], &boundary_imms);

        var t = try predecode(gpa, prog);
        defer t.deinit(gpa);
        var n = try compileNativeBlock(gpa, prog);
        defer n.deinit(gpa);

        // Every generated op is in the covered subset ⇒ every pc has a native
        // block entry (proves real list programs run native, not all-fallback).
        if (jit_codegen.native_supported) {
            for (0..plen) |k| {
                covered_ops += 1;
                if (n.block.entries[k] != null) native_entries += 1;
                try std.testing.expect(n.block.entries[k] != null);
            }
        }

        var ma = try ia.Machine.init(gpa, &atoms);
        defer ma.deinit();
        var mb = try ia.Machine.init(gpa, &atoms);
        defer mb.deinit();
        try seedListStructural(&ma);
        try seedListStructural(&mb);

        var left: u64 = 120;
        while (left > 0) {
            const take = @min(1 + random.uintLessThan(u64, 7), left);
            try runThreaded(&ma, &t, take);
            try runNativeBlock(&mb, &n, take);
            try expectLaw(try ia.eqMachines(&ma, &mb, sa), "L2/L3 native-block ≡ threaded (list/tuple/type-test)", cfg, i);
            try expectLaw(ma.reductions == mb.reductions, "L3 native-block reductions equal (list/tuple)", cfg, i);
            left -= take;
            if (ma.status != .running or ma.pending != null) break;
        }
    }
    // Honest native-coverage report: on the supported host EVERY covered op got a
    // native block entry (100% static coverage of this list/tuple/type-test mix).
    if (jit_codegen.native_supported) {
        try std.testing.expect(native_entries == covered_ops and covered_ops > 0);
    }
}

test "REAL list program runs get_list/type-test ops NATIVE (mylists:sum-style loop over a list)" {
    // sum(L) = fold over a cons list: while is_nonempty_list(L) { get_list L→[H|T];
    // Acc += H; L := T }.  The list SPINE ops (is_cons, get_list) and the arith
    // are ALL native — only the loop's trailing halt/return falls back. This is
    // the coverage the widen slice buys: a real list traversal stays native.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // regs: x0 = L (the list), x1 = Acc, x2 = H, x3 = T
    //   pc0 is_cons x0 else END(6)
    //   pc1 get_list x0 -> x2(H), x3(T)
    //   pc2 add x1, x1, x2            (Acc += H)
    //   pc3 move x0 <- x3            (L := T)     [move src=x3 (scratch), dst x0]
    //   pc4 jump 0
    //   pc5 (unused pad)  — put a halt at END
    //   pc6 halt x1
    const prog = [_]ia.CInstr{
        .{ .is_cons = .{ .src = .{ .x = 0 }, .else_to = 6 } },
        .{ .get_list = .{ .src = .{ .x = 0 }, .hd = .{ .x = 2 }, .tl = .{ .x = 3 } } },
        .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 2 }, .dst = 1 } },
        .{ .move = .{ .src = .{ .x = 3 }, .dst = 0 } },
        .{ .jump = .{ .to = 0 } },
        .{ .move = .{ .src = .nil, .dst = 5 } }, // pad (never reached)
        .{ .halt = .{ .src = .{ .x = 1 } } },
    };

    var n = try compileNativeBlock(gpa, prog[0..]);
    defer n.deinit(gpa);
    // The list-spine + arith ops (pc0..pc4) are ALL native (get_list & is_cons
    // included); only `halt` falls back. Prove the traversal is NOT all-fallback.
    if (jit_codegen.native_supported) {
        for (0..5) |k| try std.testing.expect(n.block.entries[k] != null);
    }
    var t = try predecode(gpa, prog[0..]);
    defer t.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    // Build the list [10,20,30,40] in both machines and run to completion,
    // slice-driven so the loop crosses budget boundaries mid-traversal.
    var mi = try ia.Machine.init(gpa, &atoms);
    defer mi.deinit();
    var mn = try ia.Machine.init(gpa, &atoms);
    defer mn.deinit();
    for ([_]*ia.Machine{ &mi, &mn }) |m| {
        var lst = FinalTerms.nil(&m.ctx);
        var v: i64 = 40;
        while (v >= 10) : (v -= 10) lst = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, v), lst);
        m.regs[0] = lst; // [10,20,30,40]
        m.regs[1] = FinalTerms.int(&m.ctx, 0); // Acc
    }

    var guard: usize = 0;
    while (mi.status == .running) : (guard += 1) {
        if (guard > 100_000) return error.GateDidNotTerminate;
        try runThreaded(&mi, &t, 2);
        try runNativeBlock(&mn, &n, 2);
        try std.testing.expect(try ia.eqMachines(&mi, &mn, sa));
    }
    try std.testing.expect(mn.status == .halted);
    try std.testing.expect(FinalTerms.eqlExact(&mn.ctx, mn.result, FinalTerms.int(&mn.ctx, 100))); // 10+20+30+40
    try std.testing.expect(FinalTerms.eqlExact(&mi.ctx, mi.result, FinalTerms.int(&mi.ctx, 100)));
}

// ============================================================================
// jit-calls: the native CONTROL-TRANSFER tier (call / ret) — whole-corpus
// differential + a REAL recursive program running call/return NATIVE.
// ============================================================================

test "L2/L3 native BLOCK ≡ threaded over CALL-heavy programs (CP push/pop, ret redispatch)" {
    // The whole-corpus differential for the call/ret tier. `ia.randProgram`
    // already sprinkles `.call` (a CP-frame push + jump); the reference engine
    // #3 and the native block-JIT must agree at EVERY slice boundary on the CP
    // stack contents, pc, and reductions. Runs the SAME slice-driven differential
    // the arith/branch corpus uses, with the CP stack pre-grown on the native
    // twin so a native `call` takes the fast path (no realloc) rather than
    // falling back on every push — proving `call` runs NATIVE across the corpus.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0xCA11, .iterations = 300 };

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();

        var pbuf: [16]ia.CInstr = undefined;
        const prog = ia.randProgram(random, &pbuf);

        var t = try predecode(gpa, prog);
        defer t.deinit(gpa);
        var n = try compileNativeBlock(gpa, prog);
        defer n.deinit(gpa);

        var pair = try freshPair(gpa, &atoms, cfg.seed +% i +% 55);
        defer pair.a.deinit();
        defer pair.b.deinit();
        // Pre-grow the native twin's CP stack so `call` pushes stay native (the
        // interpreter twin grows on demand; eqMachines compares stack CONTENTS,
        // which match regardless of capacity).
        try pair.b.stack.ensureTotalCapacity(gpa, 64);

        var left: u64 = 200;
        while (left > 0) {
            const take = @min(1 + random.uintLessThan(u64, 7), left);
            try runThreaded(&pair.a, &t, take);
            try runNativeBlock(&pair.b, &n, take);
            try expectLaw(try ia.eqMachines(&pair.a, &pair.b, sa), "L2 native-block ≡ threaded (call-heavy: CP stack, pc)", cfg, i);
            try expectLaw(pair.a.reductions == pair.b.reductions, "L3 native-block reductions equal (call-heavy)", cfg, i);
            left -= take;
            if (pair.a.status != .running or pair.a.pending != null) break;
        }
    }
}

test "REAL recursive program runs call/return NATIVE (body-recursive sum via CP push/pop)" {
    // recur(N,Acc): if N<1 return; else Acc+=N; N-=1; recur(); return.  A NON-tail
    // recursion: every level pushes a CP frame (native `call`) and unwinds through
    // native `ret` (pop → pc → driver redispatch). The ONLY fallback is the final
    // `halt`. Proves a real call/return-dominated program stays in machine code.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    //   pc0 call{to=2}              ; enter recur (pushes the outer return, pc1)
    //   pc1 halt x1                 ; done — result in x1 (the sum)
    //   pc2 cmp_test .ge x0,1 else=6; N>=1 ? continue : ret
    //   pc3 add x1,x1,x0            ; Acc += N
    //   pc4 sub x0,x0,1             ; N  -= 1
    //   pc5 call{to=2}              ; recurse (pushes return pc6)
    //   pc6 ret                     ; return to caller
    const prog = [_]ia.CInstr{
        .{ .call = .{ .to = 2 } },
        .{ .halt = .{ .src = .{ .x = 1 } } },
        .{ .cmp_test = .{ .op = .ge, .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .else_to = 6 } },
        .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 0 }, .dst = 1 } },
        .{ .sub = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } },
        .{ .call = .{ .to = 2 } },
        .ret,
    };

    var n = try compileNativeBlock(gpa, prog[0..]);
    defer n.deinit(gpa);
    // Every op EXCEPT the halt (pc1) is native — including BOTH calls (pc0,pc5)
    // and the ret (pc6). Prove the recursion is NOT all-fallback.
    if (jit_codegen.native_supported) {
        for ([_]usize{ 0, 2, 3, 4, 5, 6 }) |k| try std.testing.expect(n.block.entries[k] != null);
    }
    var t = try predecode(gpa, prog[0..]);
    defer t.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    const N: i64 = 20; // recursion depth 20 (sum 1..20 = 210)
    var mi = try ia.Machine.init(gpa, &atoms);
    defer mi.deinit();
    var mn = try ia.Machine.init(gpa, &atoms);
    defer mn.deinit();
    // Pre-grow the native twin's CP stack past the recursion depth so every
    // `call` push takes the native fast path (no realloc mid-recursion).
    try mn.stack.ensureTotalCapacity(gpa, @intCast(N + 8));
    for ([_]*ia.Machine{ &mi, &mn }) |m| {
        m.regs[0] = FinalTerms.int(&m.ctx, N); // N
        m.regs[1] = FinalTerms.int(&m.ctx, 0); // Acc
    }

    var guard: usize = 0;
    while (mi.status == .running) : (guard += 1) {
        if (guard > 100_000) return error.GateDidNotTerminate;
        try runThreaded(&mi, &t, 3);
        try runNativeBlock(&mn, &n, 3);
        try std.testing.expect(try ia.eqMachines(&mi, &mn, sa)); // CP stack + regs + pc agree mid-recursion
        try std.testing.expect(mi.reductions == mn.reductions);
    }
    try std.testing.expect(mn.status == .halted);
    try std.testing.expect(FinalTerms.eqlExact(&mn.ctx, mn.result, FinalTerms.int(&mn.ctx, 210))); // 1+2+…+20
}

// ---- jit-wire-production: the PRODUCTION path ≡ the reference interpreter ----

test "jit-wire-production: runProduction ≡ ia.run over the WHOLE corpus (denotation + reductions), compile-once cache" {
    // The production wiring law. For a broad corpus of FULL-op-mix programs
    // (`ia.randProgram` — the same generator the engine-#3 differential uses,
    // including mailbox + effect-trap ops that engine #4 hands to the threaded
    // fallback), a machine run through `runProduction` (the real grantOnly path,
    // engine #4 + cache) equals the reference interpreter `ia.run` at EVERY slice
    // boundary — full state AND reductions (L3). One ProdCache spans the whole
    // corpus: `getOrCompile` compiles each distinct program exactly once and the
    // testing allocator proves the cache frees clean (no leak, no double-free).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x711E, .iterations = 120 };

    std.debug.assert(use_production_native); // the wired default
    var cache = ProdCache{};
    defer cache.deinit(gpa);

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();

        // The corpus program must OUTLIVE the cache (the cache keys by slice
        // identity + holds a compiled block for it), so allocate it on `gpa`, not
        // the per-iteration arena, and keep it live until after `cache.deinit`.
        var pbuf: [16]ia.CInstr = undefined;
        const tmp = ia.randProgram(random, &pbuf);
        const prog = try gpa.dupe(ia.CInstr, tmp);
        defer gpa.free(prog);

        var pair = try freshPair(gpa, &atoms, cfg.seed +% i +% 909);
        defer pair.a.deinit();
        defer pair.b.deinit();

        var left: u64 = 90;
        while (left > 0) {
            const take = @min(1 + random.uintLessThan(u64, 9), left);
            try ia.run(&pair.a, prog, take); // the REFERENCE interpreter
            try runProduction(&cache, gpa, &pair.b, prog, take); // the PRODUCTION path
            try expectLaw(try ia.eqMachines(&pair.a, &pair.b, sa), "jit-wire-production: production ≡ interpreter at slice boundary", cfg, i);
            try expectLaw(pair.a.reductions == pair.b.reductions, "jit-wire-production: reductions equal (L3)", cfg, i);
            left -= take;
            if (pair.a.status != .running or pair.a.pending != null) break;
        }
    }

    // COMPILE-ONCE: distinct program slices in the corpus ⇒ at most that many
    // cache entries, and re-running the SAME slice never grows the map. Re-drive
    // the seed-0 program many times and assert the entry count is unchanged.
    if (native_supported_here()) {
        var pbuf: [16]ia.CInstr = undefined;
        var prng = std.Random.DefaultPrng.init(cfg.seed);
        const prog = try gpa.dupe(ia.CInstr, ia.randProgram(prng.random(), &pbuf));
        defer gpa.free(prog);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 3);
        _ = try runProduction(&cache, gpa, &m, prog, 5);
        const n1 = cache.map.count();
        // three more grants of the identical program: no new entries.
        for (0..3) |_| try runProduction(&cache, gpa, &m, prog, 5);
        try std.testing.expectEqual(n1, cache.map.count());
    }
}

test "jit-alloc-tier: native put_list survives heap GROWTH (region realloc across the len==cap boundary)" {
    // A loop that CONSes x1 onto the list in x0 and increments x1, run for many
    // reductions → the process heap grows through several ArrayList reallocs. At
    // each len==cap boundary the native fast path MUST decline (the capacity guard)
    // and yield to the interpreter's grow. The whole run must denote EXACTLY the
    // pure interpreter (L2 differential over a GROWING heap) — a broken cap check
    // writes PAST the buffer at the first boundary (OOB → testing.allocator RED).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const prog = [_]ia.CInstr{
        .{ .put_list = .{ .h = .{ .x = 1 }, .t = .{ .x = 0 }, .dst = 0 } }, // x0 = [x1 | x0]
        .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .imm = 1 }, .dst = 1 } }, //    x1 += 1
        .{ .jump = .{ .to = 0 } },
    };
    var mi = try ia.Machine.init(gpa, &atoms); // reference
    defer mi.deinit();
    mi.regs[0] = FinalTerms.nil(&mi.ctx);
    mi.regs[1] = FinalTerms.int(&mi.ctx, 0);
    try ia.run(&mi, prog[0..], 300); // 100 conses → ~7 reallocs

    var mn = try ia.Machine.init(gpa, &atoms); // production native (composes fallback)
    defer mn.deinit();
    mn.regs[0] = FinalTerms.nil(&mn.ctx);
    mn.regs[1] = FinalTerms.int(&mn.ctx, 0);
    var n = try compileNativeBlock(gpa, prog[0..]);
    defer n.deinit(gpa);
    try runNativeBlock(&mn, &n, 300);

    try std.testing.expectEqual(mi.regs[0], mn.regs[0]); // identical 100-elem list (same indices)
    try std.testing.expectEqual(mi.regs[1], mn.regs[1]); // x1 == 100
    try std.testing.expectEqual(mi.reductions, mn.reductions);
    try std.testing.expectEqualSlices(u64, mi.ctx.words.items, mn.ctx.words.items); // heaps identical
}

test "jit-wire-production: REAL program (mylists sum(20)=210) runs NATIVE end-to-end through the production cache" {
    const gpa = std.testing.allocator;
    var mod = try loader.parse(gpa, @embedFile("mylists.beam"));
    defer mod.deinit();
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const t = try loader.translate(gpa, &mod, &atoms, null);
    defer {
        gpa.free(t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    var cache = ProdCache{};
    defer cache.deinit(gpa);

    // sum(seq(20)) through runProduction (the grantOnly engine), slice-driven,
    // compared to the reference interpreter at every boundary, result pinned 210.
    var m1 = try ia.Machine.init(gpa, &atoms); // reference (ia.run)
    defer m1.deinit();
    var m2 = try ia.Machine.init(gpa, &atoms); // production native path
    defer m2.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();
    const seq_pc = loader.entryOf(&t, "seq", 1).?;
    const sum_pc = loader.entryOf(&t, "sum", 1).?;

    for ([_]u32{ seq_pc, sum_pc }) |entry| {
        for ([_]*ia.Machine{ &m1, &m2 }) |mm| {
            mm.status = .running;
            mm.pc = entry;
            mm.regs[0] = if (entry == seq_pc) FinalTerms.int(&mm.ctx, 20) else mm.result;
            mm.stack.clearRetainingCapacity();
            mm.ystack.clearRetainingCapacity();
        }
        var guard: usize = 0;
        while (m1.status == .running) : (guard += 1) {
            if (guard > 100_000) return error.GateDidNotTerminate;
            try ia.run(&m1, t.prog, 7);
            try runProduction(&cache, gpa, &m2, t.prog, 7);
            try std.testing.expect(try ia.eqMachines(&m1, &m2, sa));
        }
    }
    try std.testing.expect(FinalTerms.eqlExact(&m2.ctx, m2.result, FinalTerms.int(&m2.ctx, 210)));

    // PROVE it went native (not silently all-fallback): on the supported host the
    // compiled block for `t.prog` has at least one real native entry.
    if (native_supported_here()) {
        const nbp = cache.map.get(.{ .ptr = @intFromPtr(t.prog.ptr), .len = t.prog.len }).?;
        var any_native = false;
        for (nbp.block.entries) |e| {
            if (e != null) {
                any_native = true;
                break;
            }
        }
        try std.testing.expect(any_native);
    }
}

test "jit-wire-production: FALLBACK guards — switch-off, dyn_code, and both engines agree" {
    // The FMEA/guard law: `runProduction` defers to `ia.run` (a) when the switch
    // is off and (b) when dynamic code is present — and in BOTH cases the result
    // still equals `ia.run` (it IS `ia.run`). Restores the switch after.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const prog = [_]ia.CInstr{
        .{ .move = .{ .src = .{ .imm = 7 }, .dst = 1 } },
        .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .imm = 5 }, .dst = 0 } },
        .{ .halt = .{ .src = .{ .x = 0 } } },
    };
    var cache = ProdCache{};
    defer cache.deinit(gpa);

    // (a) switch OFF ⇒ pure interpreter, no compile: cache stays empty.
    const saved = use_production_native;
    defer use_production_native = saved;
    use_production_native = false;
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    try runProduction(&cache, gpa, &m, prog[0..], 10);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, m.result, FinalTerms.int(&m.ctx, 12)));
    try std.testing.expectEqual(@as(usize, 0), cache.map.count()); // never compiled

    // (b) switch ON but dyn_code present ⇒ interpreter fallback (still no compile,
    // because engine #4 can't see runtime-loaded code).
    use_production_native = true;
    var m2 = try ia.Machine.init(gpa, &atoms);
    defer m2.deinit();
    try m2.dyn_code.append(gpa, .{ .halt = .{ .src = .{ .x = 0 } } });
    try runProduction(&cache, gpa, &m2, prog[0..], 10);
    try std.testing.expect(FinalTerms.eqlExact(&m2.ctx, m2.result, FinalTerms.int(&m2.ctx, 12)));
    try std.testing.expectEqual(@as(usize, 0), cache.map.count()); // dyn_code ⇒ no compile
}

test "LAW jit-wire-production DYN-MID-GRANT: the engine YIELDS into runtime code loaded mid-grant, never halts early" {
    // Regression (CAST-22 / DIVERGENCE): `runProduction` defers to `ia.run` when
    // `dyn_code` is non-empty — but only checks AT GRANT ENTRY. `reload_call`
    // enters with `dyn_code` EMPTY (the native/threaded engine runs), then
    // `prepare_loading` splices a module MID-GRANT, and a BODY `call_ext` sets
    // `pc >= prog.len` INTO the runtime code. The engines index only `prog` and
    // (pre-fix) treated `pc >= prog.len` as fall-off-the-end → HALT with a stale x0
    // (the `ok` from `finish_loading`), dropping the continuation. The fix: on
    // fall-off WITH `dyn_code` present, YIELD so `runProduction` re-checks and
    // defers the remainder to `ia.run`. This law drives that exact post-dispatch
    // state directly through the threaded engine.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();

    // Static image: [add x0+=10; halt x0]  (the continuation after a body call).
    const stat = [_]ia.CInstr{
        .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 10 }, .dst = 0 } },
        .{ .halt = .{ .src = .{ .x = 0 } } },
    };
    m.code_base = stat.len;
    // Runtime code (spliced "mid-grant"): [move 7 -> x0; ret], at pc == code_base.
    try m.dyn_code.append(gpa, .{ .move = .{ .src = .{ .imm = 7 }, .dst = 0 } });
    try m.dyn_code.append(gpa, .ret);

    // The exact post-dispatch state a BODY call_ext_code into the runtime module
    // leaves: pc INTO dyn_code, the continuation pc (stat[0]) pushed as the CP,
    // x0 = the stale pre-call value (the sentinel that leaks on the bug).
    m.pc = @intCast(m.code_base); // dyn_code[0]
    try m.stack.append(gpa, 0); // ret target = stat[0] (the `add` continuation)
    m.regs[0] = FinalTerms.int(&m.ctx, 99); // sentinel: leaks as the result iff the bug halts early

    var d = try predecode(gpa, stat[0..]);
    defer d.deinit(gpa);

    // The threaded engine is invoked with pc already >= prog.len (dyn present).
    // FIXED: it YIELDS — returns with status still `.running`, pc untouched — so
    // no premature halt and no stale-x0 leak. (BUG: halts here with result == 99.)
    try runThreaded(&m, &d, 100);
    try std.testing.expectEqual(ia.Status.running, m.status); // yielded, did NOT halt early

    // runProduction re-checks `dyn_code` (now non-empty) and defers the rest to the
    // reference interpreter, which fetches dyn_code once pc >= code_base and runs
    // the continuation to completion: move 7 -> x0; ret -> stat[0]; 7+10 = 17.
    var guard: usize = 0;
    while (m.status == .running and guard < 100) : (guard += 1) try ia.run(&m, stat[0..], 8);
    try std.testing.expectEqual(ia.Status.halted, m.status);
    try std.testing.expectEqual(@as(i64, 17), FinalTerms.smallValOf(m.result)); // continuation completed, not 99
}

/// The compiled path only materializes on the x86-64-linux native host; off it,
/// `runProduction` is `ia.run` and the cache stays empty. Tests key their
/// native-only assertions on this so they pass on every host.
fn native_supported_here() bool {
    return use_native_codegen and jit_codegen.native_supported;
}

test "FIXUP SOUNDNESS: branch targets survive block-size shifts (padded loop bodies)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    // For a range of PADDING widths, build the same loop with `pad` extra `move`
    // ops spliced into the body — shifting every downstream block's byte offset.
    // Native ≡ threaded for all paddings ⇒ the forward+backward fixups tracked the
    // shifting layout exactly.
    var pad: usize = 0;
    while (pad <= 6) : (pad += 1) {
        var buf: std.ArrayList(ia.CInstr) = .empty;
        defer buf.deinit(gpa);
        // pc0: cmp_test .ge x0,1 else END
        const end_pc: u32 = @intCast(4 + pad);
        try buf.append(gpa, .{ .cmp_test = .{ .op = .ge, .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .else_to = end_pc } });
        try buf.append(gpa, .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 0 }, .dst = 1 } });
        var p: usize = 0;
        while (p < pad) : (p += 1) try buf.append(gpa, .{ .move = .{ .src = .{ .x = 2 }, .dst = 3 } }); // filler
        try buf.append(gpa, .{ .sub = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } });
        try buf.append(gpa, .{ .jump = .{ .to = 0 } }); // backward
        try buf.append(gpa, .{ .halt = .{ .src = .{ .x = 1 } } }); // END
        const prog = buf.items;

        var t = try predecode(gpa, prog);
        defer t.deinit(gpa);
        var n = try compileNativeBlock(gpa, prog);
        defer n.deinit(gpa);

        var m1 = try ia.Machine.init(gpa, &atoms);
        defer m1.deinit();
        var m2 = try ia.Machine.init(gpa, &atoms);
        defer m2.deinit();
        m1.regs[0] = FinalTerms.int(&m1.ctx, 12);
        m1.regs[1] = FinalTerms.int(&m1.ctx, 0);
        m2.regs[0] = FinalTerms.int(&m2.ctx, 12);
        m2.regs[1] = FinalTerms.int(&m2.ctx, 0);
        var guard: usize = 0;
        while (m1.status == .running) : (guard += 1) {
            if (guard > 100_000) return error.GateDidNotTerminate;
            try runThreaded(&m1, &t, 4);
            try runNativeBlock(&m2, &n, 4);
            try std.testing.expect(try ia.eqMachines(&m1, &m2, sa));
        }
        // 12+11+…+1 = 78, regardless of the padding
        try std.testing.expect(FinalTerms.eqlExact(&m2.ctx, m2.result, FinalTerms.int(&m2.ctx, 78)));
    }
}

test "DIFFERENTIAL on REAL compiled code: mylists under engine #4" {
    const gpa = std.testing.allocator;
    var mod = try loader.parse(gpa, @embedFile("mylists.beam"));
    defer mod.deinit();
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const t_prog = try loader.translate(gpa, &mod, &atoms, null);
    defer {
        gpa.free(t_prog.prog);
        gpa.free(t_prog.label_pc);
        gpa.free(t_prog.entries);
        gpa.free(t_prog.locs);
    }
    var t = try predecode(gpa, t_prog.prog);
    defer t.deinit(gpa);
    var n = try compileNative(gpa, t_prog.prog);
    defer n.deinit(gpa);
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    var m1 = try ia.Machine.init(gpa, &atoms);
    defer m1.deinit();
    var m2 = try ia.Machine.init(gpa, &atoms);
    defer m2.deinit();
    const seq_pc = loader.entryOf(&t_prog, "seq", 1).?;
    const sum_pc = loader.entryOf(&t_prog, "sum", 1).?;

    for ([_]u32{ seq_pc, sum_pc }) |entry| {
        m1.status = .running;
        m2.status = .running;
        m1.pc = entry;
        m2.pc = entry;
        m1.regs[0] = if (entry == seq_pc) FinalTerms.int(&m1.ctx, 20) else m1.result;
        m2.regs[0] = if (entry == seq_pc) FinalTerms.int(&m2.ctx, 20) else m2.result;
        m1.stack.clearRetainingCapacity();
        m2.stack.clearRetainingCapacity();
        m1.ystack.clearRetainingCapacity();
        m2.ystack.clearRetainingCapacity();
        var guard: usize = 0;
        while (m1.status == .running) : (guard += 1) {
            if (guard > 100_000) return error.GateDidNotTerminate;
            try runThreaded(&m1, &t, 7);
            try runNative(&m2, &n, 7);
            try std.testing.expect(try ia.eqMachines(&m1, &m2, sa));
        }
    }
    try std.testing.expect(FinalTerms.eqlExact(&m1.ctx, m1.result, FinalTerms.int(&m1.ctx, 210)));
    try std.testing.expect(FinalTerms.eqlExact(&m2.ctx, m2.result, FinalTerms.int(&m2.ctx, 210)));
}

test "FUEL + SLICE INVARIANCE re-verified on engine #4" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0xD13D, .iterations = 50 };

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var prng = std.Random.DefaultPrng.init(cfg.seed +% i);
        const random = prng.random();
        var buf: [16]ia.CInstr = undefined;
        const prog = ia.randProgram(random, &buf);
        var n = try compileNative(gpa, prog);
        defer n.deinit(gpa);
        const fuel: u64 = 60;

        var pair = try freshPair(gpa, &atoms, cfg.seed +% i +% 6);
        defer pair.a.deinit();
        defer pair.b.deinit();

        try runNative(&pair.a, &n, fuel);
        var left: u64 = fuel;
        while (left > 0) {
            const slice = 1 + random.uintLessThan(u64, @min(left, 7));
            try runNative(&pair.b, &n, slice);
            left -= slice;
        }
        try expectLaw(try ia.eqMachines(&pair.a, &pair.b, sa), "native: slice invariance", cfg, i);
        try expectLaw(pair.a.instrs <= fuel, "native: fuel upper bound", cfg, i); // R2b: preemption rides instrs
        if (pair.a.status == .running and pair.a.pending == null)
            try expectLaw(pair.a.instrs == fuel, "native: fuel exactness", cfg, i);
    }
}

// ============================================================================
// jit-gc-roots (JIT epoch slice #5): L4 GC-ROOT PRESERVATION ∘ copying-GC
// ============================================================================
//
// LAW L4 (docs/OTP30_JIT_FORMAL_ANALYSIS.md): ⟦after-GC-around-native⟧ == ⟦before⟧,
// composed with the copying-GC homomorphism `denote(after)=denote(before)`.
//
// PROOF-BY-CONSTRUCTION (the honest bound). In the MIXED engine #4, a native block
// executes the arith/move/branch fast path and does NOT allocate — `test_heap`/`gc`/
// heap-building ops are threaded fallbacks. Every native op writes its result
// STRAIGHT BACK to the memory-resident X-register `m.regs[dst]` (jit_codegen
// `buildMove`/`buildArith`: the trailing `store [M + regDisp(dst)]`), which lives
// INSIDE the `Machine` struct at `@offsetOf(Machine,"regs")`. That is exactly the
// slice `gc.collectMachineRoots` roots first (`for (&m.regs) |*r| try c.root(r)`).
// So a native-produced value — including a HEAP POINTER a native `move` copies from
// one X-reg to another (regDisp load/store move the raw tagged word, so `move x2→x5`
// propagates a live cons/tuple pointer) — is a GC-visible root BY CONSTRUCTION, with
// NO `live_roots` registration or safe-point write-back machinery required. This is
// the BeamAsm mirror (Part I.5: "X/Y live in the same memory layout the interpreter
// used, so the existing copying GC's root set still works").
//
// THEREFORE this slice adds NO new machinery; the deliverable is the L4 PROOF: a
// differential that runs a native-compute + GC program under engine #4 and asserts
// (a) a mid-run collection AROUND native execution preserves the whole machine's
// denotation vs an uncollected engine-#4 twin, and (b) the collected native run
// equals a collected THREADED run (native+GC ≡ threaded+GC). The mutants
// (MUTATION_LOG.md jit-gc-roots M1/M2) prove the property is load-bearing, not
// vacuous: dropping the reg rooting OR the native write-back reddens L4.

/// Seed IDENTICAL machine state for the L4 differential: heap terms (a cons list in
/// x2, a tuple in x3) that a native `move` will propagate to fresh X-regs, plus
/// seeded smalls for native arith. Deterministic in `seed` (echoed on failure).
fn seedL4(m: *ia.Machine, seed: u64) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const a = @as(i64, r.int(i16));
    const b = @as(i64, r.int(i16));
    const c = @as(i64, r.int(i16));
    const d = @as(i64, r.int(i16));
    const e = @as(i64, r.int(i16));
    // x2 := [a, b, c]  (a heap-allocated cons chain — a GC-relocated boxed term)
    const list = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, a), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, b), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, c), FinalTerms.nil(&m.ctx))));
    // x3 := {d, e}  (a heap-allocated tuple — another relocated boxed term)
    const tup = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, d), FinalTerms.int(&m.ctx, e) });
    m.regs[0] = FinalTerms.int(&m.ctx, @as(i64, r.int(i16)));
    m.regs[1] = FinalTerms.int(&m.ctx, @as(i64, r.int(i16)));
    m.regs[2] = list;
    m.regs[3] = tup;
    m.regs[4] = FinalTerms.int(&m.ctx, @as(i64, r.int(i16)));
}

/// The L4 program — ALL covered by native codegen except the trailing `halt`:
///   move x2→x5   native: propagate the heap LIST pointer into a fresh X-reg
///   add  x0,x1→x6 native arith on smalls
///   move x3→x7   native: propagate the heap TUPLE pointer into a fresh X-reg
///   sub  x6,1→x6  native arith
///   move x5→x8   native: chain the moved list pointer once more
///   halt x5       threaded fallback; result := the (native-moved) list
const l4_prog = [_]ia.CInstr{
    .{ .move = .{ .src = .{ .x = 2 }, .dst = 5 } },
    .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .x = 1 }, .dst = 6 } },
    .{ .move = .{ .src = .{ .x = 3 }, .dst = 7 } },
    .{ .sub = .{ .a = .{ .x = 6 }, .b = .{ .imm = 1 }, .dst = 6 } },
    .{ .move = .{ .src = .{ .x = 5 }, .dst = 8 } },
    .{ .halt = .{ .src = .{ .x = 5 } } },
};

test "L4 GC-ROOT PRESERVATION: native-produced values survive a collection around engine #4 (∘ copying-GC homomorphism)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x64C7, .iterations = 40 };

    var t = try predecode(gpa, l4_prog[0..]);
    defer t.deinit(gpa);
    var n = try compileNativeBlock(gpa, l4_prog[0..]);
    defer n.deinit(gpa);

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        const seed = cfg.seed +% i;

        // Three twins, identically seeded. m_ref: engine #4, never collected ("before").
        // m_gc: engine #4, collected mid-run ("after GC around native"). m_thr: engine #3
        // threaded, collected identically (the composed native+GC ≡ threaded+GC differential).
        var m_ref = try ia.Machine.init(gpa, &atoms);
        defer m_ref.deinit();
        var m_gc = try ia.Machine.init(gpa, &atoms);
        defer m_gc.deinit();
        var m_thr = try ia.Machine.init(gpa, &atoms);
        defer m_thr.deinit();
        try seedL4(&m_ref, seed);
        try seedL4(&m_gc, seed);
        try seedL4(&m_thr, seed);

        // Remember the original heap LIST denotation (x2) — a native `move` will copy it
        // into x5; after the collection the native-produced x5 must still denote it.
        const list_before = try FinalTerms.denote(&m_gc.ctx, sa, m_gc.regs[2]);

        // Slice 1: run 2 native ops (move x2→x5 ; add) so x5 holds a NATIVE-PRODUCED heap
        // pointer BEFORE the collection. m.pc lands at op 2 (yield on budget).
        try runNativeBlock(&m_ref, &n, 2);
        try runNativeBlock(&m_gc, &n, 2);
        try runThreaded(&m_thr, &t, 2);

        // SAFE-POINT WRITE-BACK: the native value is in a GC-visible root (regs[5]), not
        // a lost scratch — so it denotes the moved list at the safe-point, pre-collection.
        try expectLaw(spec.eqlExact(list_before, try FinalTerms.denote(&m_gc.ctx, sa, m_gc.regs[5])), "L4 safe-point: native-produced x5 is in a GC-visible X-reg root", cfg, i);

        // Pile UNREACHABLE garbage onto m_gc's heap so the collection genuinely compacts
        // and relocates the live (native-produced + seeded) boxed terms.
        var g: usize = 0;
        while (g < 500) : (g += 1) _ = try FinalTerms.tuple(&m_gc.ctx, &.{ FinalTerms.int(&m_gc.ctx, @intCast(g)), FinalTerms.int(&m_gc.ctx, 7) });
        const heap_before = m_gc.ctx.words.items.len;

        // THE GC AROUND NATIVE EXECUTION — the copying-GC homomorphism, rooting every
        // X-reg (incl. the native-produced x5) + result + pdict + y-regs + mailbox.
        try gc.collectMachineRoots(&m_gc);
        // The collector actually did work (garbage reclaimed) — the law is non-vacuous.
        try expectLaw(m_gc.ctx.words.items.len < heap_before, "L4: collection compacted the heap (relocation happened)", cfg, i);

        // L4: ⟦after GC around native⟧ == ⟦before⟧ — the collected native machine is
        // observationally identical to the uncollected native twin AND to the threaded
        // twin at the collection boundary.
        try expectLaw(try ia.eqMachines(&m_gc, &m_ref, sa), "L4 GC-root preservation: GC around native ≡ uncollected native at boundary", cfg, i);
        try expectLaw(try ia.eqMachines(&m_gc, &m_thr, sa), "L4 composed: native+GC ≡ threaded at boundary", cfg, i);
        // The native-produced x5 pointer RELOCATED and still denotes the original list.
        try expectLaw(spec.eqlExact(list_before, try FinalTerms.denote(&m_gc.ctx, sa, m_gc.regs[5])), "L4: native-produced x5 heap pointer relocated + denotation preserved", cfg, i);

        // Run all three to completion (the remaining native ops incl. move x3→x7 produce
        // MORE native values AFTER the collection; halt falls back to threaded).
        var guard: usize = 0;
        while (m_ref.status == .running) : (guard += 1) {
            if (guard > 10_000) return error.GateDidNotTerminate; // a native hang is a failed law
            try runNativeBlock(&m_ref, &n, 3);
            try runNativeBlock(&m_gc, &n, 3);
            try runThreaded(&m_thr, &t, 3);
        }
        // L4 THROUGH COMPLETION: the collected native run finishes identically to the
        // uncollected native run and the threaded run.
        try expectLaw(try ia.eqMachines(&m_gc, &m_ref, sa), "L4 GC-root preservation: through completion (native)", cfg, i);
        try expectLaw(try ia.eqMachines(&m_gc, &m_thr, sa), "L4 composed: native+GC ≡ threaded through completion", cfg, i);
        // Result is the native-moved list, denotation preserved across the collection.
        try expectLaw(m_gc.status == .halted, "L4: native+GC machine halted", cfg, i);
        try expectLaw(spec.eqlExact(list_before, try FinalTerms.denote(&m_gc.ctx, sa, m_gc.result)), "L4: final result (native-moved list) denotation preserved across GC", cfg, i);
    }
}

// ── gap-jit-fallback-attribution: the DYNAMIC coverage instrument ────────────
//
// `attribute` (jit_codegen) says what each BEAM op COSTS in native code, and
// `NativeSplit` says what fraction of a run WAS native. Neither says which op is
// spending the fallback, and that is the question every remaining {P} decision
// turns on: better codegen for the covered subset, or wider coverage? Four
// increments went into the first without anything measuring the second.
//
// The instrument must satisfy three things to be worth trusting, and each is a
// law here rather than a comment:
//   CONSERVATION    the per-pc vector accounts for exactly the fallback the
//                   aggregate reports — nothing dropped, nothing double-counted.
//   NON-PERTURBATION  a profiled run leaves the machine in EXACTLY the state an
//                   unprofiled one does. An instrument that changes what it
//                   measures is worse than no instrument, because it is
//                   believed.
//   LOCALISATION    it names the RIGHT pc. A vector that is merely conserved
//                   could spread the total uniformly, or name the op after the
//                   guilty one, and still pass conservation.
//
// Mutants: MUT-FBA-1 (attribute after the handler ran, i.e. to `m.pc` rather
// than the executing pc → the classic profiler off-by-one; conservation still
// holds, LOCALISATION reds), MUT-FBA-2 (drop the guard-failure site's
// attribution → CONSERVATION reds on a program whose covered block falls back at
// runtime, which is precisely the partial-coverage case worth seeing).
test "LAW gap-jit-fallback-attribution: per-pc fallback CONSERVES the aggregate, does not perturb the run, and LOCALISES to the executing op" {
    if (!use_native_codegen or !jit_codegen.native_supported) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // A mixed program: covered arith/jump around ONE uncovered op. The op at
    // pc 1 is a `number` type-test — `nativeTTofKind` covers list/atom/tuple/
    // integer and nothing else — applied to a small in x0, so it always holds,
    // falls through, and re-executes every trip without changing state.
    const prog: ia.Program = &.{
        .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } }, //   0 covered
        .{ .type_test = .{ .kind = .number, .src = .{ .x = 0 }, .else_to = 3 } }, // 1 UNCOVERED
        .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .imm = 1 }, .dst = 1 } }, //   2 covered
        .{ .jump = .{ .to = 0 } }, //                                        3 covered
    };

    // THE FIXTURE'S OWN PRECONDITION, checked rather than assumed. This law
    // needs pc 1 to be uncovered; if a later coverage slice makes it native the
    // run falls back nowhere and every assertion below passes VACUOUSLY. The
    // first version of this law used `get_hd` and that is exactly what happened
    // — the very next increment covered it. Asserting the precondition through
    // the static instrument turns silent rot into a message naming the fix.
    const static_cost = try jit_codegen.attribute(gpa, prog);
    defer gpa.free(static_cost);
    if (static_cost[1].covered) {
        std.debug.print(
            "\nFIXTURE ROT: pc1 ({s}) is now natively covered — this law needs an " ++
                "UNCOVERED op at pc 1. Pick one that is still absent from buildBlock.\n",
            .{static_cost[1].tag},
        );
        return error.FixtureNoLongerUncovered;
    }

    var n = try compileNativeBlock(gpa, prog);
    defer n.deinit(gpa);

    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    m.regs[0] = ta.FinalTerms.int(&m.ctx, 0);
    m.regs[1] = ta.FinalTerms.int(&m.ctx, 0);
    var prof = try runNativeBlockProfiled(gpa, &m, &n, 200);
    defer prof.deinit(gpa);

    // CONSERVATION — the vector is exactly the aggregate, decomposed.
    var summed: u64 = 0;
    for (prof.by_pc) |v| summed += v;
    try std.testing.expectEqual(prof.split.fallback_reds, summed);
    try std.testing.expectEqual(prog.len, prof.by_pc.len);
    // ...and the run really did both kinds of work, so neither side is vacuous.
    try std.testing.expect(prof.split.fallback_reds > 0);
    try std.testing.expect(prof.split.native_reds > 0);

    // LOCALISATION — ALL of it lands on pc 1, the only uncovered op. A uniform
    // or off-by-one attribution fails here while still conserving.
    try std.testing.expectEqual(summed, prof.by_pc[1]);
    try std.testing.expectEqual(@as(u64, 0), prof.by_pc[0]);
    try std.testing.expectEqual(@as(u64, 0), prof.by_pc[2]);
    try std.testing.expectEqual(@as(u64, 0), prof.by_pc[3]);
    try std.testing.expectEqual(@as(?usize, 1), prof.hottestPc());

    // NON-PERTURBATION — an unprofiled run from the same start reaches the same
    // state. Compared on the full observable tuple, not just the answer.
    var m2 = try ia.Machine.init(gpa, &atoms);
    defer m2.deinit();
    m2.regs[0] = ta.FinalTerms.int(&m2.ctx, 0);
    m2.regs[1] = ta.FinalTerms.int(&m2.ctx, 0);
    try runNativeBlock(&m2, &n, 200);
    try std.testing.expectEqual(m2.regs[0], m.regs[0]);
    try std.testing.expectEqual(m2.regs[2], m.regs[2]);
    try std.testing.expectEqual(m2.pc, m.pc);
    try std.testing.expectEqual(m2.instrs, m.instrs);
    try std.testing.expectEqual(m2.reductions, m.reductions);
    try std.testing.expect(m2.status == m.status);

    // AGREEMENT — the aggregate path and the profiled path are the same driver,
    // so they must report the same split from the same start.
    var m3 = try ia.Machine.init(gpa, &atoms);
    defer m3.deinit();
    m3.regs[0] = ta.FinalTerms.int(&m3.ctx, 0);
    m3.regs[1] = ta.FinalTerms.int(&m3.ctx, 0);
    const agg = try runNativeBlockCounted(&m3, &n, 200);
    try std.testing.expectEqual(agg.native_reds, prof.split.native_reds);
    try std.testing.expectEqual(agg.fallback_reds, prof.split.fallback_reds);

    // A FULLY NATIVE run attributes nothing and says so — `hottestPc` returns
    // null rather than an arbitrary index, so "nothing to cover" is not
    // reported as "cover pc 0".
    {
        const nat: ia.Program = &.{
            .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } },
            .{ .jump = .{ .to = 0 } },
        };
        var nn = try compileNativeBlock(gpa, nat);
        defer nn.deinit(gpa);
        var mn = try ia.Machine.init(gpa, &atoms);
        defer mn.deinit();
        mn.regs[0] = ta.FinalTerms.int(&mn.ctx, 0);
        var p2 = try runNativeBlockProfiled(gpa, &mn, &nn, 50);
        defer p2.deinit(gpa);
        try std.testing.expectEqual(@as(u64, 0), p2.split.fallback_reds);
        try std.testing.expectEqual(@as(?usize, null), p2.hottestPc());
        try std.testing.expectEqual(@as(f64, 1.0), p2.split.coverage());
    }
}

// ── gap-jit-cons-read-tier: the COVERAGE RATCHET on a realistic workload ─────
//
// The instrument above turns coverage into a decision; this turns it into a
// GUARD. The workload is the alloc+traversal shape (`cli.mixed_prog`): build an
// 8-cell list with `put_list`, then walk it with `get_hd`/`add`/`get_tl`. Before
// the cons-read tier it ran at coverage 0.528, with 2352 of 2362 fallback
// instructions in the two half-reads. After, 0.998 — and every instruction still
// falling back is a `put_list` heap-GROW safepoint, which is deliberate: the
// interpreter owns reallocation.
//
// Ratcheting COVERAGE, not time, is the point. A wall-clock number for this
// workload could not be defended on a contended shared host, and the four
// preceding increments in this epoch each moved a static metric by single-digit
// percent. This one moved measured native coverage by 47 points, and a
// regression that silently un-covers `get_hd`/`get_tl` — or any other hot op in
// this shape — now fails here instead of showing up as an unexplained slowdown
// nobody can reproduce.
test "LAW gap-jit-cons-read-tier COVERAGE: the alloc+traversal workload runs ≥99% native, and every residual fallback is a put_list grow-safepoint" {
    if (!use_native_codegen or !jit_codegen.native_supported) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // mixed_prog's shape: 8x put_list, then 8x (get_hd; add; get_tl), then loop.
    var prog: std.ArrayList(ia.CInstr) = .empty;
    defer prog.deinit(gpa);
    try prog.append(gpa, .{ .move = .{ .src = .nil, .dst = 1 } });
    for (0..8) |_| try prog.append(gpa, .{ .put_list = .{ .h = .{ .x = 0 }, .t = .{ .x = 1 }, .dst = 1 } });
    for (0..8) |_| {
        try prog.append(gpa, .{ .get_hd = .{ .src = .{ .x = 1 }, .dst = .{ .x = 3 } } });
        try prog.append(gpa, .{ .add = .{ .a = .{ .x = 2 }, .b = .{ .x = 3 }, .dst = 2 } });
        try prog.append(gpa, .{ .get_tl = .{ .src = .{ .x = 1 }, .dst = .{ .x = 1 } } });
    }
    try prog.append(gpa, .{ .jump = .{ .to = 0 } });

    var n = try compileNativeBlock(gpa, prog.items);
    defer n.deinit(gpa);
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    m.regs[0] = ta.FinalTerms.int(&m.ctx, 1);
    m.regs[2] = ta.FinalTerms.int(&m.ctx, 0);
    var prof = try runNativeBlockProfiled(gpa, &m, &n, 5000);
    defer prof.deinit(gpa);

    // RATCHET: may rise, never fall. Measured 0.998; the floor is set below that
    // so an unrelated safepoint does not trip it, and above the 0.528 this
    // replaced so the regression it guards cannot hide.
    try std.testing.expect(prof.split.coverage() >= 0.99);

    // ...and the residual is ACCOUNTED FOR, not merely small. Every remaining
    // fallback instruction must be a `put_list` — if a different op starts
    // falling back, this names it rather than absorbing it into the 1%.
    for (prof.by_pc, 0..) |v, i| {
        if (v == 0) continue;
        try std.testing.expect(prog.items[i] == .put_list);
    }
    // The run must actually have done the work, or the assertions above are
    // statements about an empty execution.
    try std.testing.expect(prof.split.native_reds > 4000);
}

// ── gap-jit-frame-tier: the REAL-PROGRAM coverage ratchet ────────────────────
//
// Every coverage number before this one came from a hand-written program. This
// one comes from `mylists.beam` — a real compiled BEAM module, loaded and
// translated by the real loader, running `seq(200)` then `sum/1`. That matters
// because the synthetic and the real workloads ranked DIFFERENTLY, and only the
// real one was right about where the work goes:
//
//   synthetic (alloc+traversal):  get_hd/get_tl at 99.6% of fallback
//   real (mylists.beam):          move2 402, alloc_y 400, dealloc_y 400,
//                                 bif_call 400, get_list-with-y-dst 200
//
// The synthetic shape has no stack frame at all, so it could not see the frame
// ops that dominate a compiled function — and a program with no `alloc_y` is not
// a program the BEAM compiler emits. Coverage went 0.373 → 0.809 here.
//
// The residual is ACCOUNTED FOR, not merely small. After gap-jit-bif-safepoint
// it is ONLY the `put_list`/`alloc_y` GROW safepoints, where reallocation is
// deliberately the interpreter's job, plus 8 instructions at the driver's own
// entry/exit boundary. Coverage across this epoch: 0.373 -> 0.809 (frame tier)
// -> 0.934 (bif safepoint). If anything else starts falling back, this names it.
test "LAW gap-jit-real-program COVERAGE: the REAL mylists.beam program runs ≥99% native, computes the right answer, and NOTHING is excused from the residual accounting" {
    if (!use_native_codegen or !jit_codegen.native_supported) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var mod = try loader.parse(gpa, @embedFile("mylists.beam"));
    defer mod.deinit();
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const t = try loader.translate(gpa, &mod, &atoms, null);
    defer {
        gpa.free(t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    var n = try compileNativeBlock(gpa, t.prog);
    defer n.deinit(gpa);

    var nat: u64 = 0;
    var fb: u64 = 0;
    var other_fb: u64 = 0; // fallback instructions in ops NOT deferred by design
    const seq_pc = loader.entryOf(&t, "seq", 1).?;
    const sum_pc = loader.entryOf(&t, "sum", 1).?;
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();

    for ([_]u32{ seq_pc, sum_pc }) |entry| {
        m.status = .running;
        m.pc = entry;
        m.regs[0] = if (entry == seq_pc) ta.FinalTerms.int(&m.ctx, 200) else m.result;
        m.stack.clearRetainingCapacity();
        m.ystack.clearRetainingCapacity();
        var guard: usize = 0;
        while (m.status == .running) : (guard += 1) {
            if (guard > 20_000) return error.DidNotTerminate; // bounded: a hang is a failed law
            var p = try runNativeBlockProfiled(gpa, &m, &n, 50);
            defer p.deinit(gpa);
            nat += p.split.native_reds;
            fb += p.split.fallback_reds;
            for (p.by_pc, 0..) |v, i| {
                if (v == 0) continue;
                // gap-jit-alloc-safepoint-tier: the deferred-by-design set is now
                // EMPTY. It held `put_list` and `alloc_y` — the two GROW cases —
                // and both are safe-points now, so nothing on this program is
                // allowed to fall back for a reason we have excused in advance.
                // An empty allowlist is the point: every residual instruction is
                // counted and bounded below, with no category that gets a pass.
                other_fb += v;
                _ = i;
            }
        }
    }

    // CORRECTNESS FIRST — a faster engine that computes the wrong answer is not
    // an improvement. sum(seq(200)) = 200*201/2 = 20100.
    try std.testing.expectEqual(@as(?i64, 20100), ta.FinalTerms.smallValOf(m.result));

    // RATCHET: measured 0.9975 on a real compiled module; may rise, never fall.
    // The epoch's arc on THIS program is 0.373 → 0.809 → 0.934 → 0.9975. Set
    // just below the measurement so an unrelated safepoint cannot trip it, and
    // far above what it replaced so the regression it guards cannot hide.
    const cov = @as(f64, @floatFromInt(nat)) / @as(f64, @floatFromInt(nat + fb));
    try std.testing.expect(cov >= 0.99);
    try std.testing.expect(nat > 2000); // the run really did the work

    // THE RESIDUAL ACCOUNTING. With no deferred-by-design set left, `other_fb`
    // is simply ALL of it: measured 8 (call 5, ret 2, test_eq 1), every one on
    // the driver loop's entry/exit boundary rather than inside the program.
    // Bounding this separately from the percentage is what stops a new op
    // quietly joining the fallback set and hiding inside a still-passing
    // coverage figure.
    try std.testing.expect(other_fb <= 16);
    try std.testing.expectEqual(other_fb, fb); // nothing is excused any more
    try std.testing.expect(fb <= 16);
}

// ===========================================================================
// gap-jit-workload-census: WHAT the JIT should cover next, measured over a
// CORPUS rather than over one program.
//
// WHY THIS EXISTS. Two tier selections in a row were made from a single
// program's profile and both were wrong in a way that was invisible from
// inside that program. A hand-written loop ranked `get_hd`/`get_tl` at 99.6%
// of fallback; the real `mylists.beam` ranked `move2`/`alloc_y`/`bif_call`
// and never mentioned them, because it has no stack frame. Then `mylists.beam`
// itself ran out: at coverage 0.9975 its entire residual is 8 driver-boundary
// instructions, which are a property of the test harness rather than of any
// program. Selecting the next tier from an exhausted profile is selecting from
// noise.
//
// WHAT IT MEASURES, AND WHAT IT DOES NOT. This is a STATIC census: how often
// each op appears in real compiled OTP stdlib code, and how much of that is
// natively covered. It answers "what is WIDESPREAD". It does NOT answer "what
// is HOT" — that needs a runnable corpus with entry points and arguments, and
// claiming otherwise would be exactly the over-reading this instrument exists
// to prevent. The dynamic profiler (`runNativeBlockProfiled`) still answers the
// second question, for the one program it can run.
//
// THE UNIT OF COVERAGE IS (op, operand-shape), NOT op. This is the lesson
// `gap-jit-alloc-safepoint-tier` paid for: `put_list` was treated as an
// op-level category and recorded as "deferred, heap grow", when in fact it was
// covered for x-register operands and uncovered for a frame-slot head — and the
// frame-slot head was every single occurrence in the real program. So the
// census reports covered/total PER KIND rather than a boolean, and a kind with
// 0 < covered < total is precisely a partially-covered op whose uncovered
// operand shape is a candidate tier.

/// One row of the census: an instruction kind, how often the corpus contains
/// it, how much of that compiles to real native code, and how many modules it
/// appears in. `modules` is breadth — an op with a big count in one module is a
/// different proposition from one spread across twenty.
pub const KindCensus = struct {
    tag: []const u8,
    total: usize,
    covered: usize,
    modules: usize,

    /// The ranking key: uncovered occurrences. This is the work the JIT is not
    /// doing, which is the only quantity a tier decision should be made on.
    pub fn uncovered(self: KindCensus) usize {
        return self.total - self.covered;
    }
};

/// The corpus: real compiled OTP stdlib modules, already vendored as fixtures
/// and byte-mirrored. Deliberately BROAD and deliberately not hand-picked for
/// the JIT — a corpus curated to flatter the instrument is the failure mode
/// this whole slice is a response to.
pub const census_corpus = [_][]const u8{
    @embedFile("otp_lists.beam"),    @embedFile("otp_maps.beam"),
    @embedFile("otp_proplists.beam"), @embedFile("otp_string.beam"),
    @embedFile("otp_unicode.beam"),  @embedFile("otp_sets.beam"),
    @embedFile("otp_gb_trees.beam"), @embedFile("otp_ordsets.beam"),
    @embedFile("otp_queue.beam"),    @embedFile("otp_dict.beam"),
    @embedFile("otp_orddict.beam"),  @embedFile("otp_array.beam"),
    @embedFile("otp_gb_sets.beam"),  @embedFile("otp_digraph.beam"),
    @embedFile("otp_calendar.beam"), @embedFile("otp_timer.beam"),
    @embedFile("otp_base64.beam"),   @embedFile("otp_erl_anno.beam"),
    @embedFile("otp_erl_scan.beam"), @embedFile("otp_math.beam"),
    @embedFile("otp_sofs.beam"),     @embedFile("otp_supervisor.beam"),
    @embedFile("otp_gen_server.beam"), @embedFile("otp_proc_lib.beam"),
    @embedFile("mylists.beam"),
};

const CInstrTag = std.meta.Tag(ia.CInstr);
const N_KINDS = @typeInfo(CInstrTag).@"enum".fields.len;

/// Build the census over `corpus`. Rows come back sorted by uncovered count
/// descending, with the kind index as a deterministic tiebreak so two runs of
/// the same corpus produce byte-identical rankings.
pub fn censusCorpus(gpa: std.mem.Allocator, corpus: []const []const u8) ![]KindCensus {
    var total = [_]usize{0} ** N_KINDS;
    var covered = [_]usize{0} ** N_KINDS;
    var modules = [_]usize{0} ** N_KINDS;

    for (corpus) |bytes| {
        var mod = loader.parse(gpa, bytes) catch continue;
        defer mod.deinit();
        var atoms = AtomTable.init(gpa);
        defer atoms.deinit();
        const t = loader.translate(gpa, &mod, &atoms, null) catch continue;
        // `freeProg`, NOT a bare `free(t.prog)`: real stdlib modules carry ops
        // with OWNED operand slices (`select_val.pairs`, `put_tuple2.elems`,
        // `bs_match.cmds`, …). The single-module coverage law gets away with the
        // shorter form only because `mylists.beam` happens to contain none of
        // them — which is the corpus-vs-one-program point again, this time about
        // memory rather than about coverage.
        defer {
            loader.freeProg(gpa, t.prog);
            gpa.free(t.label_pc);
            gpa.free(t.entries);
            gpa.free(t.locs);
        }
        const cost = try jit_codegen.attribute(gpa, t.prog);
        defer gpa.free(cost);

        var seen = [_]bool{false} ** N_KINDS;
        for (t.prog, 0..) |ins, pc| {
            const k = @intFromEnum(std.meta.activeTag(ins));
            total[k] += 1;
            if (cost[pc].covered) covered[k] += 1;
            seen[k] = true;
        }
        for (seen, 0..) |s, k| if (s) {
            modules[k] += 1;
        };
    }

    var rows: std.ArrayList(KindCensus) = .empty;
    errdefer rows.deinit(gpa);
    inline for (@typeInfo(CInstrTag).@"enum".fields) |f| {
        if (total[f.value] > 0)
            try rows.append(gpa, .{
                .tag = f.name,
                .total = total[f.value],
                .covered = covered[f.value],
                .modules = modules[f.value],
            });
    }
    const out = try rows.toOwnedSlice(gpa);
    std.mem.sort(KindCensus, out, {}, struct {
        fn lt(_: void, a: KindCensus, b: KindCensus) bool {
            if (a.uncovered() != b.uncovered()) return a.uncovered() > b.uncovered();
            return std.mem.order(u8, a.tag, b.tag) == .lt; // deterministic tiebreak
        }
    }.lt);
    return out;
}

test "LAW gap-jit-workload-census: the corpus census CONSERVES, spans real breadth, exposes PARTIAL coverage per (op,operand), and DISAGREES with the single-program profile" {
    if (!use_native_codegen or !jit_codegen.native_supported) return error.SkipZigTest;
    const gpa = std.testing.allocator;

    const rows = try censusCorpus(gpa, census_corpus[0..]);
    defer gpa.free(rows);

    var total: usize = 0;
    var covered: usize = 0;
    var partial_kinds: usize = 0;
    var broad_kinds: usize = 0;
    for (rows) |r| {
        // CONSERVATION (per row): coverage is a sub-count, never a separate
        // tally that could drift from the thing it describes.
        try std.testing.expect(r.covered <= r.total);
        try std.testing.expect(r.total > 0); // zero-count kinds are not emitted
        try std.testing.expect(r.modules >= 1);
        try std.testing.expect(r.modules <= census_corpus.len);
        total += r.total;
        covered += r.covered;
        if (r.covered > 0 and r.covered < r.total) partial_kinds += 1;
        if (r.modules >= 10) broad_kinds += 1;
    }

    // BREADTH — THE ANTI-SYNTHETIC GUARD, and the reason this slice exists.
    // Two tier selections in a row were made from ONE program and both were
    // wrong. A corpus that silently shrinks to a handful of modules would
    // reproduce that failure while still reporting a confident ranking, so the
    // breadth of the input is asserted, not assumed.
    try std.testing.expect(census_corpus.len >= 20);
    try std.testing.expect(total > 40_000); // real compiled code, not a toy
    try std.testing.expect(rows.len >= 50); // ≥50 distinct instruction kinds
    try std.testing.expect(broad_kinds >= 15); // ≥15 kinds spread over ≥10 modules

    // PARTIAL COVERAGE IS VISIBLE. The unit of coverage is (op, operand-shape),
    // not op — the lesson gap-jit-alloc-safepoint-tier paid for, where
    // `put_list` was recorded as an op-level "deferred" category while being
    // covered for x-registers and uncovered for the frame-slot head that was
    // every real occurrence. A census reporting a BOOLEAN per op would hide
    // exactly that, so it must report kinds that are neither fully covered nor
    // fully uncovered.
    try std.testing.expect(partial_kinds >= 3);

    // RANKING IS A TOTAL ORDER and deterministic — same corpus, same ranking,
    // so a top-N read on two different days names the same work.
    for (rows[0 .. rows.len - 1], rows[1..]) |a, b|
        try std.testing.expect(a.uncovered() >= b.uncovered());
    const again = try censusCorpus(gpa, census_corpus[0..]);
    defer gpa.free(again);
    try std.testing.expectEqual(rows.len, again.len);
    for (rows, again) |a, b| {
        try std.testing.expectEqualStrings(a.tag, b.tag);
        try std.testing.expectEqual(a.total, b.total);
        try std.testing.expectEqual(a.covered, b.covered);
    }

    // THE FINDING, ASSERTED SO IT CANNOT BE QUIETLY LOST: the corpus disagrees
    // with the single program, and by a lot. `mylists.beam` reads 0.9975 and is
    // exhausted; across 25 real stdlib modules the JIT covers ~0.77. Citing the
    // single-program figure as "the" coverage is the mis-reading this law
    // exists to prevent — a program is not a workload.
    const cov = @as(f64, @floatFromInt(covered)) / @as(f64, @floatFromInt(total));
    try std.testing.expect(cov < 0.90); // materially below the single-program figure

    // RATCHET — measured 0.8342 after gap-jit-guard-write-tier-batch (0.7695
    // when this instrument landed, 0.8055 after test_eq); may rise, never fall. This REPLACES the
    // single-program ratchet as the {P} axis's regression guard, because that
    // one is pinned at 0.9975 with nothing left to measure.
    try std.testing.expect(cov >= 0.83);
}

// ===========================================================================
// gap-jit-tier-call-ext (measurement first): STATIC TEXT IS NOT DYNAMIC WEIGHT.
//
// The corpus census ranks instruction kinds by how often they appear in the
// program TEXT across 25 real stdlib modules. Its top uncovered row is
// `func_info` — 2154 occurrences, 0 covered, present in every module — and
// `func_info` is the function-header trap that raises `function_clause`. It
// never runs on the happy path. Selecting the next JIT tier by static frequency
// would therefore put the most-never-executed instruction first.
//
// This is the third form of one mistake this epoch has now made three times:
// a hand-written loop ranked `get_hd`/`get_tl` at 99.6% of fallback and was
// wrong because it was ONE program; `mylists.beam` then ran out at 0.9975 with
// a residual that belonged to the test harness; and the corpus census fixed the
// breadth problem by trading executions for text. Breadth and dynamism are
// different axes and this instrument has never had both.
//
// The law below is small on purpose. It does not build the missing dynamic
// corpus profile — that needs runnable entry points for 25 stdlib modules,
// which is its own slice. It pins the DISAGREEMENT so the trap cannot be
// forgotten, on the same principle as `PARSE-IS-NOT-GREP`: compute both
// numbers and assert they differ, because the failure mode is a plausible
// figure that looks right.

test "LAW gap-jit-tier-call-ext STATIC-IS-NOT-DYNAMIC: the census's top uncovered kind is one a real run NEVER executes" {
    const gpa = std.testing.allocator;

    // The STATIC ranking, over the corpus.
    const rows = try censusCorpus(gpa, census_corpus[0..]);
    defer gpa.free(rows);
    try std.testing.expect(rows.len > 0);
    const top = rows[0]; // sorted by uncovered, descending
    // The top uncovered kind is `func_info`, and it is uncovered EVERYWHERE.
    try std.testing.expect(std.mem.eql(u8, top.tag, "func_info"));
    try std.testing.expect(top.covered == 0);
    try std.testing.expect(top.modules == census_corpus.len);
    try std.testing.expect(top.uncovered() > 1000);

    // The DYNAMIC picture, on a real compiled module that actually runs.
    const beam = @embedFile("mylists.beam");
    var mod = try loader.parse(gpa, beam);
    defer mod.deinit();
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const t = try loader.translate(gpa, &mod, &atoms, null);
    defer {
        gpa.free(t.prog);
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    var n = try compileNativeBlock(gpa, t.prog);
    defer n.deinit(gpa);

    // Count EXECUTED fallback per kind, not per pc — the census's unit.
    var dyn = [_]u64{0} ** N_KINDS;
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    // BOTH entries, as the coverage law does — one function is not a program.
    const seq_pc = loader.entryOf(&t, "seq", 1).?;
    const sum_pc = loader.entryOf(&t, "sum", 1).?;
    var executed: u64 = 0;
    for ([_]u32{ seq_pc, sum_pc }) |entry| {
        m.status = .running;
        m.pc = entry;
        m.regs[0] = if (entry == seq_pc) ta.FinalTerms.int(&m.ctx, 200) else m.result;
        m.stack.clearRetainingCapacity();
        m.ystack.clearRetainingCapacity();
        var guard: usize = 0;
        while (m.status == .running) : (guard += 1) {
            if (guard > 20_000) return error.DidNotTerminate; // a hang is a failed law
            var p = try runNativeBlockProfiled(gpa, &m, &n, 50);
            defer p.deinit(gpa);
            executed += p.split.native_reds + p.split.fallback_reds;
            for (p.by_pc, 0..) |v, pc| {
                if (v == 0) continue;
                dyn[@intFromEnum(std.meta.activeTag(t.prog[pc]))] += v;
            }
        }
    }

    // NON-VACUITY: the run must really have executed the program, or "nothing
    // ran and nothing was attributed" satisfies the disagreement for free.
    try std.testing.expect(executed > 2000);

    // THE DISAGREEMENT, asserted. The kind the static census ranks FIRST for
    // JIT work retires ZERO instructions in a real execution.
    const top_kind_dynamic = blk: {
        inline for (@typeInfo(CInstrTag).@"enum".fields) |f| {
            if (std.mem.eql(u8, f.name, "func_info")) break :blk dyn[f.value];
        }
        break :blk @as(u64, 0);
    };
    if (top_kind_dynamic != 0) {
        std.debug.print(
            "\nstatic-is-not-dynamic: func_info retired {d} instruction(s) on a real run.\n" ++
                "  If that is genuinely reachable now, the census's top row has become a\n" ++
                "  real tier target and this law should be re-derived — not relaxed.\n",
            .{top_kind_dynamic},
        );
        return error.TestUnexpectedResult;
    }
}
