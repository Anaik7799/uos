//! beam-zig JIT epoch / slice #3 (`jit-codegen-arith`): the FIRST REAL NATIVE
//! CODEGEN — a **template JIT** that compiles a small subset of BEAM ops to
//! native x86-64 (via `jit_asm`'s encoder, LAW L1) and runs them (via
//! `jit_exec`'s W^X exec buffer, LAW L5) against the REAL `instr_algebra.Machine`
//! register file. This is the Stratum-B engine #4 verified against the Stratum-A
//! interpreter by the differential harness in `dispatch.zig`.
//!
//! ## Design — a faithful (tractable) mirror of BeamAsm
//!
//! BeamAsm keeps X-registers **memory-resident** and templates each opcode as a
//! fixed byte pattern addressing operands by offset (`docs/OTP30_JIT_EPOCH_
//! DESIGN.md`, `docs/OTP30_JIT_FORMAL_ANALYSIS.md` Part V). The per-op stub
//! engine below mirrors exactly that; the BLOCK engine has since diverged from
//! it in one deliberate place — `gap-jit-xreg-residency` pins `x0`/`x1` in
//! callee-saved registers for the duration of a native run, which BeamAsm
//! cannot do because its per-op templates have no run-scoped prologue to
//! establish the invariant. Dual entry is what buys it here, and the shared
//! epilogue is what makes it safe: every exit flushes, so the threaded
//! interpreter — which addresses `m.regs[]` directly — never observes the
//! split. Below the block tier the memory-resident model is unchanged. Each
//! covered instruction compiles to a **template** `𝒯(b)` — a small
//! native stub `fn (*Machine) callconv(.c) u64` that reads/writes `m.regs[i]` at
//! the compile-time offset `@offsetOf(Machine,"regs") + 8*i`, charges the
//! reduction at `@offsetOf(Machine,"reductions")` (pinned-hot-state), and returns
//! 0 on success. The machine pointer is pinned in `rdi` (System-V arg0); the
//! stub is a leaf (no prologue/epilogue, only caller-saved scratch).
//!
//! ## Covered subset (native) vs fallback (threaded)
//!
//!   * `move dst, src`      — src ∈ {x-reg, small imm, nil, atom}. Total; the
//!                            stub always succeeds. (y-reg / literal ⇒ NOT
//!                            compiled — fall back.)
//!   * `add dst, a, b`      — a,b ∈ {x-reg, small imm}. The stub takes a native
//!   * `sub dst, a, b`        FAST PATH iff BOTH operands are tagged smalls AND
//!                            the result fits small (BEAM's small range,
//!                            [-2^59, 2^59)); otherwise it returns a non-zero
//!                            FALLBACK signal WITHOUT touching the machine, and
//!                            the engine re-runs the op through the interpreter
//!                            (which does the bignum / float / badarith work).
//!
//! Every OTHER opcode (and every uncovered operand shape) is left to the threaded
//! interpreter — a MIXED engine. This is the honest, tight scope of slice #3:
//! the arithmetic/move hot path is genuinely native; the long tail is threaded.
//!
//! ## slice #4 (`jit-branches`): native CONTROL FLOW — the block JIT
//!
//! Slice #3's `compile`/`runNative` are the per-op engine (one native stub per
//! pc, pc+budget driven by the Zig loop). Slice #4 adds `compileBlock` — a WHOLE
//! contiguous native region where each covered op is a basic block laid out in pc
//! order and BEAM control transfer becomes a native `jmp`/`jcc rel32` BETWEEN
//! blocks, so a counted loop's body runs end-to-end as machine code (see the
//! block-JIT section lower in this file for the full treatment). The additional
//! native control-flow subset: `jump` (unconditional), `is_lt`/`cmp_test .ge`
//! (untag + signed compare + `jl`/`jge`), and `test_eq`/`cmp_test .eq_arith/
//! .ne_arith/.ne_exact` (tagged-word `cmp` + `je`/`jne`). Branch targets resolve
//! by a two-pass layout (forward refs patched via a fixup vector, backward edges
//! direct); the remaining reduction budget is pinned in `rsi` so native yields at
//! EXACTLY the interpreter's slice boundaries (L2/L3). Uncovered ops and non-small
//! operands fall back to the interpreter, at block granularity, via
//! `dispatch.runNativeBlock`.
//!
//! ## The small-int fast path (why the tag trick + guard is correct)
//!
//! A small term is `(v << 4) | 0xF` (`term_algebra`'s SMALL_SUFFIX). The stub:
//!   1. materializes each operand term (load from regs, or a baked immediate),
//!   2. GUARDS both are smalls: `(t & 0xF) == 0xF` (the tag is exact — 0xF tags
//!      smalls and nothing else), else fallback;
//!   3. untags (`sar 4` — arithmetic, sign-correct), computes in i64,
//!   4. GUARDS the result fits small (signed compare vs ±2^59), else fallback,
//!   5. re-tags (`shl 4` then `+0xF`) and stores.
//! Because the interpreter encodes a fits-small sum identically (`intFromI128 ⇒
//! int ⇒ (s<<4)|0xF`), the stored word is BIT-IDENTICAL to the interpreter's;
//! whenever it would NOT be (overflow to bignum, float/big/non-number operand)
//! the guards divert to the interpreter. This is what makes the per-opcode
//! homomorphism `⟦𝒯(b)⟧ₘ = stepOne(b)(m)` hold on the covered subset.
//!
//! ## Laws (verified in `dispatch.zig` + here)
//!
//!   L2  DIFFERENTIAL   `runNative ≡ runThreaded` at every slice boundary over the
//!                      seeded corpus (extends dispatch.zig's engine-#4 test with
//!                      `use_native_codegen = true`, so native stubs actually run).
//!   L3  COUNTERS       (R2b two-counter) native stubs charge the per-INSTRUCTION
//!                      counter `m.instrs` (+1 per covered op) on the interpreter's
//!                      exact schedule — the rsi budget consumes `instrs`, so
//!                      preemption is byte-identical. The OTP per-CALL `m.reductions`
//!                      is charged SEPARATELY, only by the `call` / tail-`jump`
//!                      blocks (`reductionCost`), so native ≡ interpreter on BOTH
//!                      counters at every slice boundary.
//!   HOMOMORPHISM       each covered `𝒯(b)` executed directly on a Machine equals
//!                      `execInstr(b)` (regs[dst] + instrs + reductions), incl. the
//!                      fallback diversion (non-small / overflow operands).
//!   BAKED-TERM GROUND  `smallTerm`/nil/atom baked constants byte-equal the terms
//!                      `FinalTerms` builds (so a baked immediate denotes right).
//!
//! ## SAFETY / STRATUM
//! Stratum-B (engine). The only substrate seam is `jit_exec.ExecBuffer` (W^X),
//! which carries its OWN safety packet (CTRL-SEAM-WIRE). This module adds no new
//! controller: it emits pure bytes (jit_asm, Stratum-A) into that seam and hands
//! out `entryAt` fn-ptrs only AFTER seal. `native_supported` gates codegen to
//! linux/x86-64; elsewhere nothing is compiled and the engine is pure threaded
//! (observationally identical — the differential still holds by fallback).

const std = @import("std");
const builtin = @import("builtin");
const ia = @import("instr_algebra.zig");
const ta = @import("term_algebra.zig");
const jit_asm = @import("jit_asm.zig");
const jit_exec = @import("jit_exec.zig");

const Inst = jit_asm.Inst;
const Reg = jit_asm.Reg;
const FinalTerms = ta.FinalTerms;

/// The native template calling convention: `rdi = *Machine`; returns 0 when the
/// stub handled the op (regs + reductions already updated), non-zero to request
/// the interpreter FALLBACK (machine untouched).
pub const NativeFn = *const fn (*ia.Machine) callconv(.c) u64;

/// Native codegen is available on linux/x86-64 only (the encoder targets x86-64;
/// the exec buffer uses the linux mprotect seam). Elsewhere: compile nothing.
pub const native_supported = builtin.os.tag == .linux and builtin.cpu.arch == .x86_64;

// Pinned state: the machine pointer register and the compile-time field offsets.
const M: Reg = .rdi; // System-V arg0
const REGS_OFF: i64 = @offsetOf(ia.Machine, "regs");
const REDS_OFF: i32 = @offsetOf(ia.Machine, "reductions");
// R2b two-counter: native stubs bump `instrs` (the per-INSTRUCTION counter that
// drives preemption / the rsi budget), byte-identical to the pre-R2b per-op
// `reductions += 1`. The OTP per-CALL `reductions` is charged SEPARATELY, only by
// the call / tail-jump blocks (`reductionCost`), so native ≡ interpreter on BOTH
// counters (the L3 differential).
const INSTRS_OFF: i32 = @offsetOf(ia.Machine, "instrs");

const SMALL_SUFFIX: u64 = 0xF; // term_algebra SMALL_SUFFIX
const SMALL_HI: i64 = 1 << 59; // fits-small upper bound (exclusive)

// ---- jit-widen-coverage: the term-representation constants the NON-ALLOCATING
// heap-reading templates (get_list / get_tuple_element / list/tuple/atom/integer
// type-test guards) decode, mirrored from `term_algebra.FinalTerms`. Each is
// cross-checked at test time by the GROUND law (build a real term, mask it, and
// assert `(w & mask) == val`) so a constant drift reddens the suite.
const TAG_MASK: u64 = 0b11; //  low-2-bit primary tag
const TAG_LIST: u64 = 0b01; //  a cons cell   (head @ ptrIdx, tail @ ptrIdx+1)
const TAG_BOXED: u64 = 0b10; // a boxed value (header @ ptrIdx, subtag in bits 2..6)
const IMM_MASK6: u64 = 0b111111; // the 6-bit immediate mask (atom / nil discriminator)
const ATOM_SUFFIX: u64 = 0b001011; // an atom's 6-bit suffix
const NIL_WORD: u64 = ta.FinalTerms.nil_term; // the empty list `[]` (== 0b111011)
const SUBTAG_FIELD: u64 = 0x7C; // the 5-bit header subtag, in place: (0x1F << 2)
const SUBTAG_TUPLE_INPLACE: u64 = 0; // SUBTAG_TUPLE (0) << 2 == 0 — the tuple header

/// The disp32 of `ctx.words.items.ptr` within a Machine — the process-heap base
/// pointer. A Zig slice stores its `.ptr` first, so the ArrayList's byte address
/// IS the address of `.items.ptr` (asserted below). Loaded at RUN time (never
/// baked) because the heap ArrayList relocates on growth — but get_list/
/// get_tuple_element only READ, so the pointer is stable across the op (no GC in
/// a native block — the GC-free-block invariant, L4, holds by construction).
const WORDS_OFF: i32 = @intCast(@offsetOf(ia.Machine, "ctx") + @offsetOf(ta.FinalTerms.Ctx, "words"));
comptime {
    std.debug.assert(@offsetOf(std.ArrayList(u64), "items") == 0); // .ptr is the first word
}

/// The disp32 of x-register slot `r` within the Machine (`regs` is `[]u64`).
fn regDisp(r: ia.XReg) i32 {
    return @intCast(REGS_OFF + 8 * @as(i64, r));
}

/// The tagged small-int term for `v`, computed directly — asserted bit-equal to
/// `FinalTerms.int` by a law below. (`FinalTerms.int` ignores its ctx arg, but
/// codegen has no ctx, so we replicate the pure encoding.)
fn smallTerm(v: i64) u64 {
    return (@as(u64, @bitCast(v)) << 4) | SMALL_SUFFIX;
}

/// The compiled program: a per-pc table of native stubs (null ⇒ not compiled,
/// run threaded) plus the exec buffer backing them (owns the W^X pages).
pub const Compiled = struct {
    exec: ?jit_exec.ExecBuffer,
    entries: []?NativeFn, // len == prog.len

    pub fn deinit(self: *Compiled, gpa: std.mem.Allocator) void {
        gpa.free(self.entries);
        if (self.exec) |*e| e.free();
    }
};

/// Compile `prog`: emit a native template for every covered instruction into one
/// sealed exec buffer, and record its entry pointer per pc. Uncovered ops get a
/// null entry (the engine runs them threaded).
pub fn compile(gpa: std.mem.Allocator, prog: ia.Program) !Compiled {
    const entries = try gpa.alloc(?NativeFn, prog.len);
    errdefer gpa.free(entries);
    @memset(entries, null);
    if (!native_supported) return .{ .exec = null, .entries = entries };

    // Emit each stub's bytes into one blob; remember (pc, byte-offset).
    var blob: std.ArrayList(u8) = .empty;
    defer blob.deinit(gpa);
    var offs: std.ArrayList(struct { pc: usize, off: usize }) = .empty;
    defer offs.deinit(gpa);

    for (prog, 0..) |ins, pc| {
        const stub = try buildStub(gpa, ins) orelse continue; // null ⇒ not covered
        defer gpa.free(stub);
        const code = try jit_asm.emitProgram(gpa, stub);
        defer gpa.free(code);
        try offs.append(gpa, .{ .pc = pc, .off = blob.items.len });
        try blob.appendSlice(gpa, code);
    }

    if (offs.items.len == 0) return .{ .exec = null, .entries = entries };

    var exec = try jit_exec.ExecBuffer.alloc(blob.items.len, null);
    errdefer exec.free();
    try exec.write(blob.items);
    try exec.seal(); // RW → RX (W^X): the bytes are now executable, never writable
    for (offs.items) |e| entries[e.pc] = try exec.entryAt(e.off, NativeFn);

    return .{ .exec = exec, .entries = entries };
}

/// Build the native template `𝒯(ins)` as a jit_asm instruction list, or null if
/// `ins` is not in the covered subset (⇒ threaded fallback). Caller owns the
/// returned slice.
fn buildStub(gpa: std.mem.Allocator, ins: ia.CInstr) !?[]Inst {
    return switch (ins) {
        .move => |m| try buildMove(gpa, m.src, m.dst),
        .add => |a| try buildArith(gpa, a.a, a.b, a.dst, .add),
        .sub => |s| try buildArith(gpa, s.a, s.b, s.dst, .sub),
        else => null,
    };
}

/// Materialize a `Src` into `dst_reg`, appending native insts. Returns false if
/// the source shape is not compilable (y-reg / non-small literal / literal-idx).
fn materialize(list: *std.ArrayList(Inst), gpa: std.mem.Allocator, dst_reg: Reg, src: ia.Src) !bool {
    switch (src) {
        .x => |r| try list.append(gpa, .{ .load = .{ .reg = dst_reg, .base = M, .disp = regDisp(r) } }),
        .imm => |v| {
            if (!ta.fitsSmall(v)) return false; // a non-small imm can't be a baked small term
            try list.append(gpa, .{ .mov_ri = .{ .dst = dst_reg, .imm = @bitCast(smallTerm(v)) } });
        },
        .nil => try list.append(gpa, .{ .mov_ri = .{ .dst = dst_reg, .imm = @bitCast(FinalTerms.nil_term) } }),
        .atom_ => |idx| try list.append(gpa, .{ .mov_ri = .{ .dst = dst_reg, .imm = @bitCast(FinalTerms.atomTerm(@intCast(idx))) } }),
        .literal => return false, // per-machine literal table — not addressable statically
        .y => return false, // stack slot — out of scope for slice #3
    }
    return true;
}

/// Append the instruction-retire charge (`m.instrs += 1`) — the L3 hot-state
/// update. R2b: the per-op engine covers only straight-line ops (move/add/sub),
/// which are 0 per-CALL reductions, so it charges ONLY the per-INSTRUCTION counter
/// here (`instrs`), never `reductions`. Uses rdx (load/add/store) + r8 (the 1).
fn chargeReduction(list: *std.ArrayList(Inst), gpa: std.mem.Allocator) !void {
    try list.append(gpa, .{ .load = .{ .reg = .rdx, .base = M, .disp = INSTRS_OFF } });
    try list.append(gpa, .{ .mov_ri = .{ .dst = .r8, .imm = 1 } });
    try list.append(gpa, .{ .add_rr = .{ .dst = .rdx, .src = .r8 } });
    try list.append(gpa, .{ .store = .{ .reg = .rdx, .base = M, .disp = INSTRS_OFF } });
}

/// `move dst, src` — total (never fallback) when `src` is compilable.
fn buildMove(gpa: std.mem.Allocator, src: ia.Src, dst: ia.XReg) !?[]Inst {
    var list: std.ArrayList(Inst) = .empty;
    errdefer list.deinit(gpa);
    if (!try materialize(&list, gpa, .rax, src)) {
        list.deinit(gpa);
        return null;
    }
    try list.append(gpa, .{ .store = .{ .reg = .rax, .base = M, .disp = regDisp(dst) } });
    try chargeReduction(&list, gpa);
    try list.append(gpa, .{ .mov_ri = .{ .dst = .rax, .imm = 0 } }); // return 0 (handled)
    try list.append(gpa, .ret);
    return try list.toOwnedSlice(gpa);
}

const ArithKind = enum { add, sub };

/// `add`/`sub dst, a, b` — native small-int fast path with a fallback tail. The
/// fallback is a single trailing `mov rax,1 ; ret` that every guard `jcc`s to; we
/// patch each guard's rel32 to that block after laying out the byte offsets.
fn buildArith(gpa: std.mem.Allocator, a: ia.Src, b: ia.Src, dst: ia.XReg, kind: ArithKind) !?[]Inst {
    // Only x-reg / small-imm operands are numeric-capable candidates. nil/atom
    // are never numbers (interpreter crashes badarith) — leave them to threaded.
    if (!arithOperandOk(a) or !arithOperandOk(b)) return null;

    var list: std.ArrayList(Inst) = .empty;
    errdefer list.deinit(gpa);
    var fixups: std.ArrayList(usize) = .empty; // indices of guard jccs → fallback
    defer fixups.deinit(gpa);

    // rsi = 0xF (tag mask AND the tag bits to OR back in).
    try list.append(gpa, .{ .mov_ri = .{ .dst = .rsi, .imm = @bitCast(SMALL_SUFFIX) } });
    _ = try materialize(&list, gpa, .rax, a); // operand a → rax
    _ = try materialize(&list, gpa, .rcx, b); // operand b → rcx

    // guard: (a & 0xF) == 0xF  (a is a small)
    try emitSmallGuard(&list, &fixups, gpa, .rax);
    // guard: (b & 0xF) == 0xF
    try emitSmallGuard(&list, &fixups, gpa, .rcx);

    // untag both (arithmetic shift — sign-correct), compute in i64.
    try list.append(gpa, .{ .sar_ri = .{ .dst = .rax, .imm = 4 } });
    try list.append(gpa, .{ .sar_ri = .{ .dst = .rcx, .imm = 4 } });
    try list.append(gpa, switch (kind) {
        .add => .{ .add_rr = .{ .dst = .rax, .src = .rcx } },
        .sub => .{ .sub_rr = .{ .dst = .rax, .src = .rcx } },
    });

    // guard result fits small: rax < 2^59 (else jge fallback)
    try list.append(gpa, .{ .mov_ri = .{ .dst = .rdx, .imm = SMALL_HI } });
    try list.append(gpa, .{ .cmp_rr = .{ .dst = .rax, .src = .rdx } });
    try fixups.append(gpa, list.items.len);
    try list.append(gpa, .{ .jcc = .{ .cc = .ge, .rel = 0 } });
    // guard result fits small: rax >= -2^59 (else jl fallback)
    try list.append(gpa, .{ .mov_ri = .{ .dst = .rdx, .imm = -SMALL_HI } });
    try list.append(gpa, .{ .cmp_rr = .{ .dst = .rax, .src = .rdx } });
    try fixups.append(gpa, list.items.len);
    try list.append(gpa, .{ .jcc = .{ .cc = .l, .rel = 0 } });

    // re-tag: (val << 4) | 0xF   (after shl the low nibble is 0, so +rsi == |0xF)
    try list.append(gpa, .{ .shl_ri = .{ .dst = .rax, .imm = 4 } });
    try list.append(gpa, .{ .add_rr = .{ .dst = .rax, .src = .rsi } });
    // store result, charge the reduction, return 0 (handled).
    try list.append(gpa, .{ .store = .{ .reg = .rax, .base = M, .disp = regDisp(dst) } });
    try chargeReduction(&list, gpa);
    try list.append(gpa, .{ .mov_ri = .{ .dst = .rax, .imm = 0 } });
    try list.append(gpa, .ret);

    // FALLBACK block (guards land here): return 1 (interpreter re-runs the op).
    const fallback_index = list.items.len;
    try list.append(gpa, .{ .mov_ri = .{ .dst = .rax, .imm = 1 } });
    try list.append(gpa, .ret);

    patchFallback(list.items, fixups.items, fallback_index);
    return try list.toOwnedSlice(gpa);
}

fn arithOperandOk(s: ia.Src) bool {
    return switch (s) {
        .x => true,
        .imm => |v| ta.fitsSmall(v),
        else => false,
    };
}

/// Append `mov rdx,reg ; and rdx,rsi ; cmp rdx,rsi ; jne fallback` — the
/// small-tag guard (rsi must already hold 0xF). Records the jne for patching.
fn emitSmallGuard(list: *std.ArrayList(Inst), fixups: *std.ArrayList(usize), gpa: std.mem.Allocator, reg: Reg) !void {
    try list.append(gpa, .{ .mov_rr = .{ .dst = .rdx, .src = reg } });
    try list.append(gpa, .{ .and_rr = .{ .dst = .rdx, .src = .rsi } });
    try list.append(gpa, .{ .cmp_rr = .{ .dst = .rdx, .src = .rsi } });
    try fixups.append(gpa, list.items.len);
    try list.append(gpa, .{ .jcc = .{ .cc = .ne, .rel = 0 } });
}

/// Patch each recorded guard `jcc`'s rel32 to the fallback block. `jcc` is a
/// fixed 6 bytes regardless of rel, so per-inst lengths are stable under the
/// patch — compute byte offsets once, then fix rels.
fn patchFallback(insts: []Inst, fixups: []const usize, fallback_index: usize) void {
    var byte_off: [256]usize = undefined; // stubs are far under 256 insts
    var acc: usize = 0;
    for (insts, 0..) |inst, i| {
        byte_off[i] = acc;
        acc += jit_asm.encode(inst).len;
    }
    const fallback_off = byte_off[fallback_index];
    for (fixups) |idx| {
        const after = byte_off[idx] + jit_asm.encode(insts[idx]).len;
        insts[idx].jcc.rel = @intCast(@as(i64, @intCast(fallback_off)) - @as(i64, @intCast(after)));
    }
}

// ===========================================================================
// jit-branches (JIT epoch slice #4): CONTROL-FLOW block codegen.
//
// Slice #3 compiled ONE op per native stub and let the Zig `runNative` loop
// drive pc + budget. This slice compiles a WHOLE region into one contiguous
// native block: each covered BEAM op becomes a native basic block laid out in
// pc order, and BEAM control transfer (`jump`/`is_lt`/`test_eq`/`cmp_test`)
// becomes a native `jmp`/`jcc rel32` BETWEEN blocks — so a counted loop's body
// (guard + arith + back-edge) runs end-to-end as machine code without returning
// to the interpreter each op. This is where the real perf lives.
//
// ## Two-pass layout + the branch fixup vector (the fixup-soundness obligation)
//
// A native branch's `rel32` is `target_byte_offset − (site_byte_offset + 6)`.
// Backward edges (target pc ≤ this pc) are already laid out, so they resolve in
// one pass; forward edges (target pc not yet emitted) are recorded as FIXUPS and
// patched after the whole region is laid out. Because every `jmp`/`jcc` is a
// FIXED width (5 / 6 bytes) regardless of its rel, per-inst byte offsets are
// STABLE under the patch — we compute offsets once, then fix rels. `pc_fixups`
// targets a BEAM pc (a block entry); `inst_fixups` targets an absolute inst
// index (intra-block skips, e.g. the budget-check `jne` and the guard→fallback
// diversions). LAW `FIXUP SOUNDNESS`: every branch lands at exactly the intended
// pc/native offset, forward and backward, even when block sizes shift offsets.
//
// ## Budget residency = L2/L3 slice-boundary fidelity
//
// The remaining reduction budget is PINNED in `rsi` (System-V arg1). Each block
// top does `if rsi==0 { m.pc = pc; return YIELD }` BEFORE executing — mirroring
// the interpreter loop's `while used < budget` check — and each covered op
// charges `m.reductions += 1` and decrements `rsi`. So native runs EXACTLY
// `budget` ops then yields with m.pc at the next unexecuted op, identical to the
// threaded engine. That is what makes L2 (state) and L3 (reductions) hold at
// EVERY slice boundary, not just at halt. An uncovered op (or a runtime slow
// case: a non-small comparison / arith overflow) sets m.pc and returns FALLBACK;
// the Zig driver (`dispatch.runNativeBlock`) runs that one op threaded and
// re-enters — the mixed-engine invariant, at block granularity.
//
// ## Covered control-flow subset (native) vs fallback (threaded)
//
//   * `jump to`                    — unconditional native `jmp` to block[to].
//   * `is_lt a,b / else_to`        — both smalls: untag (sar) + signed `cmp` +
//   * `cmp_test .ge a,b / else_to`   `jl`/`jge`; else fall back.
//   * `test_eq a,b / else_to`      — is_eq_exact; both smalls: tagged-word `cmp`
//   * `cmp_test .eq_arith/.ne_*`     + `je`/`jne` (two smalls are exact-equal iff
//                                    bit-equal); else fall back.
//   * `move`/`add`/`sub`           — slice-#3 templates, re-expressed as blocks
//                                    (arith keeps the small fast-path + fallback).
// Every other op, and any non-small operand, falls back to the interpreter.

const PC_OFF: i32 = @intCast(@offsetOf(ia.Machine, "pc"));
const RET_YIELD: i64 = 0; // budget exhausted; m.pc at the next op (still running)
const RET_FALLBACK: i64 = 1; // uncovered op / runtime slow case at m.pc
// gap-jit-mask-imm: r9 USED to hold 0xF across an arith/cmp block, reloaded by a
// `mov_ri` in every one of them. `SMALL_SUFFIX` fits an imm32, so the group-1
// immediate forms name it directly and the register — and its per-block load —
// are gone. The register itself is now free for a later slice to use.
const BUD: Reg = .rsi; // System-V arg1: the remaining reduction budget
/// gap-jit-instrs-resident: `m.instrs` lives HERE across a native run instead of
/// being loaded, incremented and stored back in every block. rbx is
/// callee-saved, so the outer entry pushes it and the shared epilogue pops —
/// every volatile register was already allocated, which is what forced the
/// choice and what makes the push/pop pair part of the design rather than an
/// oversight.
const RESID: Reg = .rbx;

/// gap-jit-xreg-residency: the X-registers held in CALLEE-SAVED registers for
/// the duration of a native run instead of being loaded from / stored to
/// `m.regs[]` at every access. `XRES[i]` is the machine register holding BEAM
/// `x{i}`; anything at or above `XRES.len` stays memory-resident.
///
/// TWO, not four. r12–r15 are all unallocated, so registers are not the
/// constraint — the outer entry is. Each resident register costs a push, a
/// reload and a flush-plus-pop, executed on EVERY native entry, and the driver
/// re-enters after every fallback and every yield. Two covers the hot pair
/// (`x0`/`x1` are the accumulator/counter of every loop the block JIT covers)
/// at three prologue instructions; four would double that against a much
/// thinner tail. `residentReg` is the only place the set is named, so widening
/// it later is a one-line change plus a re-measure.
const XRES = [_]Reg{ .r12, .r13 };

/// The machine register holding BEAM `x{r}`, or null when `x{r}` lives in
/// memory. Every X access in the block JIT goes through {!readX}/{!writeX},
/// which consult exactly this — so a resident register can never be read from
/// its (stale) memory slot by construction rather than by review.
fn residentReg(r: ia.XReg) ?Reg {
    return if (r < XRES.len) XRES[r] else null;
}

comptime {
    // The resident set must be disjoint from the pinned registers AND from the
    // scratch registers the block templates clobber (rax/rcx/rdx/r8/r9/r10/r11).
    // An overlap would not fail to compile — it would silently corrupt an X
    // register mid-block, so it is asserted rather than commented.
    const reserved = [_]Reg{ M, BUD, RESID, .rax, .rcx, .rdx, .r8, .r9, .r10, .r11, .rsp, .rbp };
    for (XRES) |x| for (reserved) |v| std.debug.assert(x != v);
    for (XRES, 0..) |x, i| for (XRES[i + 1 ..]) |y| std.debug.assert(x != y);
}

// ---- jit-calls: the CP (continuation-pointer) stack, `Machine.stack:
// std.ArrayList(usize)`. Its layout is `{ items: []usize (ptr@0, len@8),
// capacity: usize@16 }`. `call` PUSHES the return pc (pc+1) and `ret` POPS it;
// both operate on THIS memory-resident stack (separate from the process heap),
// so a covered call/return NEVER touches the GC heap — the GC-free-block
// invariant (L4) holds by construction. The disp32s are computed here and each
// is comptime-guarded so a std.ArrayList layout change reddens the build.
const STACK_OFF: i32 = @intCast(@offsetOf(ia.Machine, "stack"));
const STACK_PTR_OFF: i32 = STACK_OFF + 0; // items.ptr
const STACK_LEN_OFF: i32 = STACK_OFF + 8; // items.len
const STACK_CAP_OFF: i32 = STACK_OFF + 16; // capacity
comptime {
    const SL = std.ArrayList(usize);
    std.debug.assert(@offsetOf(SL, "items") == 0); // .ptr is the first word
    std.debug.assert(@offsetOf(SL, "capacity") == 16); // after {ptr,len}
    std.debug.assert(@sizeOf(usize) == 8); // 8-byte CP words / addresses
}

// ---- gap-jit-frame-tier: the y-register STACK FRAME. `Machine.ystack:
// std.ArrayList(Term)` holds the frame slots, and `yreg(i)` is
// `&ystack.items[len - 1 - i]` — FRAME-RELATIVE, y0 being the newest slot, so
// the address depends on a runtime `len` rather than a compile-time offset. The
// interpreter PANICS on `i >= len`; native code must therefore GUARD and fall
// back rather than read past the frame, which is what keeps a malformed frame a
// diagnosable interpreter panic instead of a silent native out-of-bounds read.
const YSTACK_OFF: i32 = @intCast(@offsetOf(ia.Machine, "ystack"));
const YSTACK_PTR_OFF: i32 = YSTACK_OFF + 0; // items.ptr
const YSTACK_LEN_OFF: i32 = YSTACK_OFF + 8; // items.len
const YSTACK_CAP_OFF: i32 = YSTACK_OFF + 16; // capacity
comptime {
    const YL = std.ArrayList(ta.FinalTerms.Term);
    std.debug.assert(@offsetOf(YL, "items") == 0);
    std.debug.assert(@offsetOf(YL, "capacity") == 16);
    std.debug.assert(@sizeOf(ta.FinalTerms.Term) == 8); // a frame slot is one word
}

/// The native block runner's calling convention: `rdi = *Machine`, `rsi = budget`
/// (remaining reductions). Returns `RET_YIELD` when the budget ran out (m.pc set
/// to the next op) or `RET_FALLBACK` when it hit an uncovered op / slow case
/// (m.pc set to that op). Reductions charged == covered ops executed.
pub const BlockFn = *const fn (*ia.Machine, u64) callconv(.c) u64;

/// A whole-program native region: one sealed exec buffer + a per-pc entry table
/// (`entries[pc]` is the block runner entered at BEAM pc `pc`). On a non-supported
/// host every entry is null and the engine is pure threaded.
pub const NativeBlock = struct {
    exec: ?jit_exec.ExecBuffer,
    entries: []?BlockFn,

    pub fn deinit(self: *NativeBlock, gpa: std.mem.Allocator) void {
        gpa.free(self.entries);
        if (self.exec) |*e| e.free();
    }
};

/// The block emitter: a flat inst stream plus two fixup writers (Part III's
/// reader+writer). `pc_fixups` patch to a block entry (resolved via `block_entry`);
/// `inst_fixups` patch to an absolute inst index (intra-block).
const Emit = struct {
    gpa: std.mem.Allocator,
    code: std.ArrayList(Inst) = .empty,
    pc_fixups: std.ArrayList(struct { site: usize, target_pc: usize }) = .empty,
    inst_fixups: std.ArrayList(struct { site: usize, target: usize }) = .empty,
    /// Sites that jump to the ONE shared exit epilogue. Every native exit routes
    /// through it, so the resident-counter flush is emitted once per region
    /// rather than once per tail — and there are 11 inline tail sites, so a
    /// per-tail flush would have cost more than residency saves.
    exit_fixups: std.ArrayList(usize) = .empty,

    fn emit(self: *Emit, inst: Inst) !usize {
        try self.code.append(self.gpa, inst);
        return self.code.items.len - 1;
    }
    fn deinit(self: *Emit) void {
        self.code.deinit(self.gpa);
        self.pc_fixups.deinit(self.gpa);
        self.inst_fixups.deinit(self.gpa);
        self.exit_fixups.deinit(self.gpa);
    }
    /// Leave native execution: jump to the shared epilogue, which flushes the
    /// resident counter, restores rbx and returns. Replaces a bare `ret` at
    /// every exit — a `ret` that skipped the flush would lose instruction
    /// accounting silently.
    fn emitExit(self: *Emit) !void {
        const j = try self.emit(.{ .jmp = 0 });
        try self.exit_fixups.append(self.gpa, j);
    }
    /// The shared epilogue. Returns its index.
    ///
    /// gap-jit-xreg-residency: this is ALSO the X-register flush point, and it
    /// is what makes residency safe against the interpreter. Every native exit
    /// (budget yield, fallback trampoline, CP-return yield, fall-off-the-end)
    /// jumps here, so `m.regs[]` is written back before control leaves native
    /// code — and the driver's threaded fallback, which reads and writes those
    /// slots directly, therefore never sees a stale value. Pops mirror the
    /// outer entry's pushes in reverse.
    fn emitEpilogue(self: *Emit) !usize {
        const idx = self.code.items.len;
        try self.code.append(self.gpa, .{ .store = .{ .reg = RESID, .base = M, .disp = INSTRS_OFF } });
        for (XRES, 0..) |x, i|
            try self.code.append(self.gpa, .{ .store = .{ .reg = x, .base = M, .disp = regDisp(@intCast(i)) } });
        var k = XRES.len;
        while (k > 0) : (k -= 1) try self.code.append(self.gpa, .{ .pop = XRES[k - 1] });
        try self.code.append(self.gpa, .{ .pop = RESID });
        try self.code.append(self.gpa, .ret);
        return idx;
    }
};

fn setRel(inst: *Inst, rel: i64) void {
    switch (inst.*) {
        .jmp => inst.jmp = @intCast(rel),
        .jcc => inst.jcc.rel = @intCast(rel),
        else => unreachable,
    }
}

/// An arith/cmp operand is native-capable iff it is an x-reg or a small imm.
fn smallOperandOk(s: ia.Src) bool {
    return arithOperandOk(s);
}
/// A `move` src is native-capable iff it materializes to a baked term / x-load.
fn moveSrcOk(s: ia.Src) bool {
    return switch (s) {
        .x, .nil, .atom_ => true,
        .imm => |v| ta.fitsSmall(v),
        .literal, .y => false,
    };
}

/// Block top: `if rsi == 0 { m.pc = pc; return YIELD }` — the budget gate that
/// mirrors the interpreter loop's `while used < budget`.
/// The OUTER entry prologue: save the callee-saved resident register and load
/// `m.instrs` into it. Emitted once per block, but EXECUTED once per native run
/// — native-to-native jumps target the inner entry and skip it entirely, which
/// is the whole point of the dual-entry split.
fn emitOuterEntry(e: *Emit) !void {
    try e.code.append(e.gpa, .{ .push = RESID });
    for (XRES) |x| try e.code.append(e.gpa, .{ .push = x });
    try e.code.append(e.gpa, .{ .load = .{ .reg = RESID, .base = M, .disp = INSTRS_OFF } });
    // gap-jit-xreg-residency: RELOAD, every entry. The threaded fallback runs
    // between two native entries and writes `m.regs[]` directly, so a prologue
    // that assumed the register survived would resume on a value the
    // interpreter has already replaced.
    for (XRES, 0..) |x, i|
        try e.code.append(e.gpa, .{ .load = .{ .reg = x, .base = M, .disp = regDisp(@intCast(i)) } });
}

/// gap-jit-xreg-residency: read BEAM `x{r}` into `dst_reg`. A resident register
/// is a reg-reg move (3 bytes, no memory operand); a non-resident one is the
/// load this replaced. THE ONE READ PATH — `materialize`'s `.x` arm routes here
/// for every block template, which is why a missed site is a compile-time
/// impossibility rather than a review obligation.
fn readX(e: *Emit, dst_reg: Reg, r: ia.XReg) !void {
    if (residentReg(r)) |rr| {
        try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = dst_reg, .src = rr } });
    } else {
        try e.code.append(e.gpa, .{ .load = .{ .reg = dst_reg, .base = M, .disp = regDisp(r) } });
    }
}

/// gap-jit-xreg-residency: write `src_reg` to BEAM `x{r}`. A resident register
/// is updated IN PLACE and never written to its memory slot until the shared
/// epilogue flushes it.
///
/// THE HAZARD THIS EXISTS TO PREVENT: a block that stored `x0` to memory while
/// `x0` lived in r12 would leave two disagreeing values, and the next reader —
/// `readX`, taking the register — would pick the wrong one. Routing all seven
/// block-path result stores through here is what makes the two copies unable to
/// diverge; `LAW gap-jit-xreg-residency`'s interleave arm is what proves the
/// routing is actually total.
fn writeX(e: *Emit, r: ia.XReg, src_reg: Reg) !void {
    if (residentReg(r)) |rr| {
        try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = rr, .src = src_reg } });
    } else {
        try e.code.append(e.gpa, .{ .store = .{ .reg = src_reg, .base = M, .disp = regDisp(r) } });
    }
}

/// gap-jit-frame-tier: `addr := &ystack.items[len - 1 - i]`, with the frame
/// bound checked. Records a guard that diverts to the block's fallback tail when
/// `len <= i` — the case where `yreg` would panic. Clobbers r10 and `addr`.
fn emitYAddr(e: *Emit, guards: *std.ArrayList(usize), i: u8, addr: Reg) !void {
    const need: i32 = @as(i32, i) + 1; // the frame must hold at least i+1 slots
    try e.code.append(e.gpa, .{ .load = .{ .reg = .r10, .base = M, .disp = YSTACK_LEN_OFF } });
    try e.code.append(e.gpa, .{ .cmp_ri = .{ .dst = .r10, .imm = need } });
    // len < i+1 ⇒ out of frame ⇒ fall back. Signed `l` is correct: both are
    // small non-negative counts, and a bogus huge `len` would fail the compare
    // in the safe direction anyway.
    try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .l, .rel = 0 } }));
    try e.code.append(e.gpa, .{ .sub_ri = .{ .dst = .r10, .imm = need } }); // len-1-i
    try e.code.append(e.gpa, .{ .shl_ri = .{ .dst = .r10, .imm = 3 } }); // *8
    try e.code.append(e.gpa, .{ .load = .{ .reg = addr, .base = M, .disp = YSTACK_PTR_OFF } });
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = addr, .src = .r10 } });
}

/// Block-path operand materialization: `materialize`, except the `.x` arm goes
/// through {!readX} and the `.y` arm reads the frame slot. The per-op stub
/// engine (`compile`/`buildStub`) keeps the plain `materialize` — those stubs
/// have no prologue, so nothing is resident there and a register read would be
/// reading garbage.
///
/// `guards` may be null, meaning "this block has no fallback tail": a `.y`
/// operand then reports NOT-compilable rather than emitting an unguarded frame
/// read. That is the fail-closed direction — a block without a tail has nowhere
/// to divert an out-of-frame index to.
fn emitMaterialize(e: *Emit, guards: ?*std.ArrayList(usize), dst_reg: Reg, src: ia.Src) !bool {
    switch (src) {
        .x => |r| {
            try readX(e, dst_reg, r);
            return true;
        },
        .y => |i| {
            const g = guards orelse return false;
            try emitYAddr(e, g, i, dst_reg);
            try e.code.append(e.gpa, .{ .load = .{ .reg = dst_reg, .base = dst_reg, .disp = 0 } });
            return true;
        },
        else => return materialize(&e.code, e.gpa, dst_reg, src),
    }
}

/// Write `src_reg` to a general `Dst` — an x-register (possibly resident) or a
/// frame slot. Same fail-closed rule as {!emitMaterialize} for the y case.
fn emitWriteDst(e: *Emit, guards: ?*std.ArrayList(usize), dst: ia.Dst, src_reg: Reg) !bool {
    switch (dst) {
        .x => |r| {
            try writeX(e, r, src_reg);
            return true;
        },
        .y => |i| {
            const g = guards orelse return false;
            // `src_reg` must survive the address computation, so the address
            // goes to a scratch that is never a value carrier here.
            try emitYAddr(e, g, i, .rcx);
            try e.code.append(e.gpa, .{ .store = .{ .reg = src_reg, .base = .rcx, .disp = 0 } });
            return true;
        },
    }
}

fn emitBudgetCheck(e: *Emit, pc: usize) !void {
    // gap-jit-imm-prologue: `cmp rsi, 0` directly — the zero no longer needs a
    // register, and this runs in EVERY block, so it is the widest-reach saving
    // the attribution found.
    try e.code.append(e.gpa, .{ .cmp_ri = .{ .dst = BUD, .imm = 0 } }); // rsi - 0
    const j = try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } }); // jne .body (rsi != 0)
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r8, .imm = @intCast(pc) } });
    try e.code.append(e.gpa, .{ .store = .{ .reg = .r8, .base = M, .disp = PC_OFF } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rax, .imm = RET_YIELD } });
    try e.emitExit();
    try e.inst_fixups.append(e.gpa, .{ .site = j, .target = e.code.items.len }); // .body
}

/// `m.instrs += 1; rsi -= 1` — the per-INSTRUCTION retire charge + budget consume
/// (R2b: the rsi budget is an INSTRUCTION budget, so preemption is byte-identical
/// to the pre-R2b model). The OTP per-CALL `reductions` charge is SEPARATE
/// (`emitReductionCharge`, only on call / tail-jump). Clobbers rax/rcx; both are
/// dead at every call site.
fn emitChargeAndDec(e: *Emit) !void {
    // gap-jit-imm-prologue: the literal 1 is an immediate on both the retire
    // charge and the budget consume, so it stops occupying rcx per block.
    // gap-jit-instrs-resident: one add, not load/add/store. The counter is in
    // RESID for the whole native run and flushed by the shared epilogue.
    try e.code.append(e.gpa, .{ .add_ri = .{ .dst = RESID, .imm = 1 } });
    try e.code.append(e.gpa, .{ .sub_ri = .{ .dst = BUD, .imm = 1 } });
}

/// `m.reductions += 1` — the OTP per-CALL reduction charge. Emitted ONLY by the
/// blocks whose op has `reductionCost == 1` (a `call` and a TAIL `jump`); it does
/// NOT touch the rsi budget (preemption rides `instrs`, charged by
/// `emitChargeAndDec`). Clobbers rax/rcx (dead at both call sites).
fn emitReductionCharge(e: *Emit) !void {
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rcx, .imm = 1 } });
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rax, .base = M, .disp = REDS_OFF } });
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = .rax, .src = .rcx } });
    try e.code.append(e.gpa, .{ .store = .{ .reg = .rax, .base = M, .disp = REDS_OFF } });
}

/// The fallback tail: `m.pc = pc; return FALLBACK`. Reached only by guard `jcc`s
/// (or, standalone, as an uncovered-op trampoline). Returns the tail's inst idx.
fn emitFallbackTail(e: *Emit, pc: usize) !usize {
    const idx = e.code.items.len;
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r8, .imm = @intCast(pc) } });
    try e.code.append(e.gpa, .{ .store = .{ .reg = .r8, .base = M, .disp = PC_OFF } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rax, .imm = RET_FALLBACK } });
    try e.emitExit();
    return idx;
}

/// Append `mov rdx,reg ; and rdx,0xF ; cmp rdx,0xF ; jne <fallback>` (0xF
/// must be live). Records the jne for patching to the fallback tail.
fn emitTagGuard(e: *Emit, guards: *std.ArrayList(usize), reg: Reg) !void {
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .rdx, .src = reg } });
    try e.code.append(e.gpa, .{ .and_ri = .{ .dst = .rdx, .imm = @intCast(SMALL_SUFFIX) } });
    try e.code.append(e.gpa, .{ .cmp_ri = .{ .dst = .rdx, .imm = @intCast(SMALL_SUFFIX) } });
    const j = try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } });
    try guards.append(e.gpa, j);
}

const CmpShape = struct { untag: bool, holds: jit_asm.Cc };

/// Emit the block for one covered branch/compare op (is_lt / test_eq / cmp_test):
/// small-guard both operands (→ fallback), charge, compare, then `jcc holds` to
/// the fall-through (block[pc+1]) or `jmp` to `else_to`.
fn emitCmpBlock(e: *Emit, a: ia.Src, b: ia.Src, else_to: usize, pc: usize, shape: CmpShape) !void {
    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);
    _ = try emitMaterialize(e, &guards, .r10, a);
    _ = try emitMaterialize(e, &guards, .r11, b);

    try emitTagGuard(e, &guards, .r10);
    try emitTagGuard(e, &guards, .r11);

    try emitChargeAndDec(e); // both smalls ⇒ native handles; charge exactly once

    if (shape.untag) {
        try e.code.append(e.gpa, .{ .sar_ri = .{ .dst = .r10, .imm = 4 } });
        try e.code.append(e.gpa, .{ .sar_ri = .{ .dst = .r11, .imm = 4 } });
    }
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .r10, .src = .r11 } }); // r10 - r11
    const j_hold = try e.emit(.{ .jcc = .{ .cc = shape.holds, .rel = 0 } }); // holds → block[pc+1]
    const j_else = try e.emit(.{ .jmp = 0 }); // not-holds → block[else_to]
    try e.pc_fixups.append(e.gpa, .{ .site = j_else, .target_pc = else_to });

    const fb = try emitFallbackTail(e, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
    // holds falls through to the NEXT block, emitted immediately after this one.
    try e.inst_fixups.append(e.gpa, .{ .site = j_hold, .target = e.code.items.len });
}

/// gap-jit-testeq-operand-widening: `test_eq` as a RAW WORD COMPARE, with no
/// small-tag guard, valid whenever at least one operand is a compile-time
/// immediate (`eqOperandImmediate`).
///
/// SELECTED BY THE CORPUS CENSUS, not by one program. `test_eq` is the single
/// largest uncovered kind across 25 real stdlib modules — 2,192 uncovered of
/// 2,499 occurrences in 24 modules — and the cause was not the comparison. It
/// was the PREDICATE: `test_eq` was gated by `smallOperandOk`, which is
/// `arithOperandOk`, the ARITHMETIC predicate, accepting only x-registers and
/// small integers. Measured over 4,998 operand slots: nil 1,038 and atom_ 990
/// — 41% — were rejected by a rule meant for addition. `test_eq` is not
/// arithmetic; `emitCmpBlock` already ran it with `untag = false`, i.e. it was
/// ALREADY a word comparison, merely wrapped in guards it did not need.
///
/// WHY NO TAG GUARD IS SOUND. `test_eq` is `=:=`. With one side a canonical
/// immediate, word equality decides it in every direction: equal words mean the
/// same immediate; different words mean different terms, because a boxed term's
/// word can never equal an immediate's, and there is exactly one encoding per
/// immediate value. The one case where raw comparison would be WRONG — two
/// structurally equal boxed terms at different addresses — cannot arise, since
/// that requires BOTH sides boxed and the predicate refuses it. Verified by
/// `LAW gap-jit-testeq-operand-widening PREMISE`, counterweight included.
///
/// The frame-bounds guards from a `.y` operand still route to the fallback
/// tail: an out-of-frame index is the interpreter's diagnosable error, and it
/// fires BEFORE the charge, so the re-run charges exactly once.
fn emitEqImmBlock(e: *Emit, a: ia.Src, b: ia.Src, else_to: usize, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);
    // REGISTER CHOICE IS LOAD-BEARING, and getting it wrong faulted immediately.
    // `emitYAddr` uses **r10** as its scratch and cannot have r10 as its
    // destination either, so neither value may live there — the sibling
    // `emitCmpBlock` uses r10/r11 only because `smallOperandOk` rejects `.y` and
    // it therefore never reaches a frame read. This block does admit `.y`, so it
    // uses r11 and rcx, and materializes in that order: the first operand is
    // already parked in r11 (which `emitYAddr` leaves alone) before the second
    // can disturb r10. `emitChargeAndDec` touches only RESID/BUD, so both
    // values survive it.
    _ = try emitMaterialize(e, &guards, .r11, a);
    _ = try emitMaterialize(e, &guards, .rcx, b);

    try emitChargeAndDec(e);

    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .r11, .src = .rcx } });
    const j_hold = try e.emit(.{ .jcc = .{ .cc = .e, .rel = 0 } }); // equal → block[pc+1]
    const j_else = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_else, .target_pc = else_to });

    const fb = try emitFallbackTail(e, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
    try e.inst_fixups.append(e.gpa, .{ .site = j_hold, .target = e.code.items.len });
}

/// Emit the block for `add`/`sub dst,a,b` (small fast path + fallback tail).
fn emitArithBlock(e: *Emit, a: ia.Src, b: ia.Src, dst: ia.XReg, kind: ArithKind, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);
    _ = try emitMaterialize(e, &guards, .rax, a);
    _ = try emitMaterialize(e, &guards, .rcx, b);

    try emitTagGuard(e, &guards, .rax);
    try emitTagGuard(e, &guards, .rcx);

    try e.code.append(e.gpa, .{ .sar_ri = .{ .dst = .rax, .imm = 4 } });
    try e.code.append(e.gpa, .{ .sar_ri = .{ .dst = .rcx, .imm = 4 } });
    try e.code.append(e.gpa, switch (kind) {
        .add => .{ .add_rr = .{ .dst = .rax, .src = .rcx } },
        .sub => .{ .sub_rr = .{ .dst = .rax, .src = .rcx } },
    });
    // result-fits-small guards (jge / jl → fallback)
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rdx, .imm = SMALL_HI } });
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .rax, .src = .rdx } });
    const g_hi = try e.emit(.{ .jcc = .{ .cc = .ge, .rel = 0 } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rdx, .imm = -SMALL_HI } });
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .rax, .src = .rdx } });
    const g_lo = try e.emit(.{ .jcc = .{ .cc = .l, .rel = 0 } });
    try guards.append(e.gpa, g_hi);
    try guards.append(e.gpa, g_lo);

    // re-tag, store, charge, then jump over the fallback tail to block[pc+1].
    try e.code.append(e.gpa, .{ .shl_ri = .{ .dst = .rax, .imm = 4 } });
    try e.code.append(e.gpa, .{ .add_ri = .{ .dst = .rax, .imm = @intCast(SMALL_SUFFIX) } }); // |0xF
    try writeX(e, dst, .rax);
    try emitChargeAndDec(e);
    const j_next = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });

    const fb = try emitFallbackTail(e, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

/// Emit the block for `move dst, src` (total on a covered src — no fallback).
fn emitMoveBlock(e: *Emit, src: ia.Src, dst: ia.XReg, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    _ = try emitMaterialize(e, null, .rax, src);
    try writeX(e, dst, .rax);
    try emitChargeAndDec(e); // fall through to block[pc+1]
}

/// gap-jit-frame-tier: a src is FRAME-capable iff it materializes to a baked
/// term, an x-read, or a GUARDED frame read. Only usable by blocks that emit a
/// fallback tail — `emitMaterialize` fails closed without one, and the caller's
/// predicate must agree with what the block can actually emit (the existing
/// `moveSrcOk`/`smallOperandOk` deliberately keep rejecting `.y`, because their
/// blocks pass a null guard list).
/// gap-jit-testeq-operand-widening: is `s` a COMPILE-TIME IMMEDIATE with a
/// canonical word encoding? Atoms, nil and small integers are baked as a single
/// word by `materialize`, and the representation guarantees one word per value
/// (`intFromI128` narrows a small-range value back to a small rather than
/// building a bignum). `.literal` is excluded precisely because it is NOT
/// immediate — it is a general, possibly boxed term from the module's literal
/// table, and word-comparing one would be the unsound case.
///
/// This predicate is the soundness precondition for `emitEqImmBlock`, and the
/// premise it encodes is verified by a law rather than argued in a comment.
fn eqOperandImmediate(s: ia.Src) bool {
    return switch (s) {
        .atom_, .nil => true,
        .imm => |v| ta.fitsSmall(v),
        .x, .y, .literal => false,
    };
}

fn frameSrcOk(s: ia.Src) bool {
    return switch (s) {
        .x, .y, .nil, .atom_ => true,
        .imm => |v| ta.fitsSmall(v),
        .literal => false, // per-machine literal table — not addressable statically
    };
}

/// Emit the block for `move2 src, dst` — the GENERAL move (any `Src` to any
/// `Dst`, including frame slots either side).
///
/// SELECTED BY MEASUREMENT: the real `mylists.beam` profile put `move2` at 402
/// fallback instructions, the single largest entry, and every occurrence was the
/// trivial `src=imm dst=x` shape — an op the block JIT could already express and
/// simply had no arm for. Unlike `emitMoveBlock` (total, no tail) this one CAN
/// fall back, because a frame operand carries a bounds guard.
fn emitMove2Block(e: *Emit, src: ia.Src, dst: ia.Dst, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);

    _ = try emitMaterialize(e, &guards, .rax, src);
    _ = try emitWriteDst(e, &guards, dst, .rax);
    try emitChargeAndDec(e);

    // A tail costs nothing when no guard needs it: with x-only operands this
    // block has no guards and falls through to block[pc+1] exactly like
    // `emitMoveBlock`. The tail is emitted only when something can divert to it.
    if (guards.items.len != 0) {
        const j_next = try e.emit(.{ .jmp = 0 });
        try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });
        const fb = try emitFallbackTail(e, pc);
        for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
    }
}

/// gap-jit-frame-tier: `alloc_y n` — push `n` nil-initialised frame slots.
/// `stepOne` appends `n` nils to `ystack`; native does the same by bumping the
/// length in place. GUARD `len + n <= capacity`: growth is the interpreter's job
/// (its `append` reallocs), exactly as `emitCallBlock` guards the CP stack and
/// `emitPutListBlock` guards the heap. Same SAFE-POINT discipline — allocation
/// never happens inside native code.
fn emitAllocYBlock(e: *Emit, ins: *const ia.CInstr, n: u8, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);

    // rax = len ; rcx = cap ; r8 = len + n
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rax, .base = M, .disp = YSTACK_LEN_OFF } });
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rcx, .base = M, .disp = YSTACK_CAP_OFF } });
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .r8, .src = .rax } });
    try e.code.append(e.gpa, .{ .add_ri = .{ .dst = .r8, .imm = @as(i32, n) } });
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .rcx, .src = .r8 } }); // cap - (len+n)
    try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .l, .rel = 0 } })); // cap < len+n → grow

    // items[len + k] = nil, for k in 0..n  (rdx = &items[len])
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rdx, .base = M, .disp = YSTACK_PTR_OFF } });
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .r10, .src = .rax } });
    try e.code.append(e.gpa, .{ .shl_ri = .{ .dst = .r10, .imm = 3 } });
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = .rdx, .src = .r10 } }); // &items[len]
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r11, .imm = @bitCast(NIL_WORD) } });
    for (0..n) |k| {
        const disp: i32 = @intCast(8 * k);
        try e.code.append(e.gpa, .{ .store = .{ .reg = .r11, .base = .rdx, .disp = disp } });
    }
    // COMMIT: items.len = len + n (r8) — the LAST write, so a slot is never
    // visible before it holds nil.
    try e.code.append(e.gpa, .{ .store = .{ .reg = .r8, .base = M, .disp = YSTACK_LEN_OFF } });

    try emitChargeAndDec(e);
    const j_next = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });
    // gap-jit-alloc-safepoint-tier: the GROW guard is a SAFE-POINT, not an exit.
    // The interpreter still does the growing; native code just does not have to
    // leave and come back for it.
    const fb = try emitSafepointTail(e, ins, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

/// gap-jit-frame-tier: `dealloc_y n` — drop `n` frame slots.
/// `shrinkRetainingCapacity(len - n)` is purely a length write (the slots stay
/// allocated), so native does exactly that. GUARD `len >= n`: under-flowing the
/// frame would wrap the unsigned length, and that must be the interpreter's
/// diagnosable error rather than a native corruption.
fn emitDeallocYBlock(e: *Emit, n: u8, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);

    try e.code.append(e.gpa, .{ .load = .{ .reg = .rax, .base = M, .disp = YSTACK_LEN_OFF } });
    try e.code.append(e.gpa, .{ .cmp_ri = .{ .dst = .rax, .imm = @as(i32, n) } });
    try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .l, .rel = 0 } })); // len < n → fallback
    try e.code.append(e.gpa, .{ .sub_ri = .{ .dst = .rax, .imm = @as(i32, n) } });
    try e.code.append(e.gpa, .{ .store = .{ .reg = .rax, .base = M, .disp = YSTACK_LEN_OFF } });

    try emitChargeAndDec(e);
    const j_next = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });
    const fb = try emitFallbackTail(e, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

// ===========================================================================
// gap-jit-bif-safepoint: calling OUT of native code.
//
// SELECTED BY MEASUREMENT. On the real `mylists.beam` profile, `bif_call` was
// 400 fallback instructions — 65% of everything still leaving native code once
// the frame tier landed. Nothing else on that program came close.
//
// WHY A SHIM AND NOT A DIRECT CALL. A BIF is `fn (*Machine, []Term) !Term`:
// a Zig error union over a slice argument. Zig does NOT commit to the ABI of
// non-`callconv(.c)` functions, so hand-emitting a call to one would be
// betting machine code on an unspecified layout — it might work today and
// silently corrupt after a compiler upgrade. The shim below is
// `callconv(.c)`, which IS specified, and it does the whole job in Zig:
// resolve, call, route errors, decide. VM semantics stay in Zig, exactly as
// the boundary rules require; the JIT only decides *when* to call it. This is
// also how BeamAsm does it — native code calls C helpers for BIFs.
//
// WHAT THE SHIM MUST PRESERVE. `execInstr` is reached through the SAME path the
// threaded engine uses, with the interpreter's own pc convention (`m.pc = pc+1`
// BEFORE the op, mirroring `stepOne`). So a native `bif_call` is not a
// reimplementation of the op — it is the op, called from a different place.
//
// THE THREE THINGS THAT MAKE THIS DANGEROUS, each handled:
//   1. RESIDENCY. A BIF reads and writes `m.regs[]` and bumps `m.instrs`
//      directly. rbx/r12/r13 hold those. They are FLUSHED before the call and
//      RELOADED after — the same discipline as the epilogue, but inline.
//   2. THE BUDGET. `rsi` holds the remaining budget and is caller-saved, so the
//      callee may destroy it. It is preserved across the call on the stack.
//   3. STACK ALIGNMENT. System V requires rsp ≡ 0 (mod 16) AT the call. Nothing
//      in this JIT called anything before now, so alignment was simply never a
//      property anyone had to maintain — and it is easy to break by accident
//      from a distance (adding one register to the residency set would do it).
//      It is asserted at comptime rather than reasoned about at the call site.

/// The shim's verdict. `CONTINUE` means the op completed normally and native
/// execution may proceed to `pc+1`; anything else means the interpreter must
/// take over at `m.pc` — a guard that branched, an exception, a trap, a status
/// change. Fail-closed: every case the shim is not certain about yields.
const SHIM_CONTINUE: u64 = 0;
const SHIM_YIELD: u64 = 1;

/// The C-ABI safepoint. Runs ONE instruction through the interpreter exactly as
/// `stepOne` would, and reports whether native execution can simply carry on.
///
/// `callconv(.c)` is load-bearing: it is the only calling convention Zig
/// specifies, and hand-emitted machine code can only call what is specified.
pub fn jitOpSafepoint(m: *ia.Machine, ins: *const ia.CInstr, pc: u64) callconv(.c) u64 {
    // `stepOne`'s convention: pc advances BEFORE the op runs, so an op that
    // wants to branch writes its own target over pc+1.
    m.pc = pc + 1;
    ia.execInstr(m, ins.*) catch return SHIM_YIELD; // crash / raise / trap → interpreter
    // Anything that moved the machine off the straight-line path is the
    // driver's business, not ours. Checked in full rather than assumed:
    if (m.status != .running) return SHIM_YIELD; // halted / crashed
    if (m.pending != null) return SHIM_YIELD; // a trap was staged
    if (m.pc != pc + 1) return SHIM_YIELD; // a guard branched (else_to)
    return SHIM_CONTINUE;
}

comptime {
    // System V AMD64: rsp ≡ 0 (mod 16) at a `call`. The caller's `call` pushed a
    // return address (rsp ≡ 8), then `emitOuterEntry` pushes `1 + XRES.len`
    // registers, and the safepoint itself pushes an even number (M and BUD), so
    // alignment at the call site holds iff the entry count is ODD.
    //
    // This is asserted, not commented, because it is broken from a DISTANCE:
    // widening the residency set by one register — a one-line change in
    // `XRES`, nowhere near this code — would silently misalign every call out
    // of native code, and misalignment is the kind of fault that shows up as a
    // crash inside libc rather than anywhere near its cause.
    std.debug.assert((1 + XRES.len) % 2 == 1);
}

/// The shared safe-point CALL SEQUENCE: flush residency, preserve the pinned
/// caller-saved registers, call the shim, restore, reload, and consume one unit
/// of budget. Leaves the shim's VERDICT in `rax`; the caller decides what to do
/// with it.
///
/// gap-jit-alloc-safepoint-tier factored this out of `emitBifSafepointBlock`
/// unchanged, because the allocation tier needs exactly the same sequence. The
/// sequence is the delicate part — three separate hazards, each commented at its
/// step — and having one copy is what stops the second user from re-earning
/// them. The `rdi` hazard in particular first showed up as a segfault deep
/// inside an unrelated scheduler test.
///
/// `ins` is a pointer to the instruction, baked as an immediate. Its lifetime is
/// the caller's obligation and is documented at `compileBlock`.
fn emitSafepointCall(e: *Emit, ins: *const ia.CInstr, pc: usize) !void {
    // ---- FLUSH. The callee addresses `m.instrs` and `m.regs[]` directly, so the
    // resident copies must be in memory before it runs, and re-read after.
    try e.code.append(e.gpa, .{ .store = .{ .reg = RESID, .base = M, .disp = INSTRS_OFF } });
    for (XRES, 0..) |x, i|
        try e.code.append(e.gpa, .{ .store = .{ .reg = x, .base = M, .disp = regDisp(@intCast(i)) } });

    // ---- PRESERVE the two pinned registers. BOTH are caller-saved, so the
    // callee is entitled to destroy both:
    //   BUD (rsi) — the remaining budget, and also arg1, so it is overwritten
    //               by the call setup regardless.
    //   M   (rdi) — the MACHINE POINTER. This one is easy to miss precisely
    //               because it is the argument: passing it in rdi does not
    //               mean it comes back in rdi. Every reload below addresses
    //               off M, so a clobbered rdi turns the whole tail of this
    //               block into wild memory access — which is exactly how it
    //               first failed, a segfault at a small address deep inside an
    //               unrelated scheduler test.
    // Two pushes is also 16 bytes, so the System V alignment the call needs is
    // preserved by the saves themselves — no separate padding slot.
    try e.code.append(e.gpa, .{ .push = M });
    try e.code.append(e.gpa, .{ .push = BUD });

    // ---- ARGS: rdi = *Machine (already there), rsi = *CInstr, rdx = pc.
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rsi, .imm = @bitCast(@intFromPtr(ins)) } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rdx, .imm = @intCast(pc) } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rax, .imm = @bitCast(@intFromPtr(&jitOpSafepoint)) } });
    try e.code.append(e.gpa, .{ .call_r = .rax }); // verdict → rax

    // ---- RESTORE both pinned registers, in reverse push order.
    // gap-jit-tier-call-ext: we pop BUD into the temporary rcx register so we can
    // subtract the exact instruction delta consumed during the safepoint.
    try e.code.append(e.gpa, .{ .pop = .rcx });
    try e.code.append(e.gpa, .{ .pop = M });

    // Calculate dynamic instruction delta: rdx = m.instrs - RESID
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rdx, .base = M, .disp = INSTRS_OFF } });
    try e.code.append(e.gpa, .{ .sub_rr = .{ .dst = .rdx, .src = RESID } });

    // Clamp BUD to 0 on underflow: cmp rcx, rdx ; jae .positive ; mov rcx, 0 ; jmp .done ; .positive: sub rcx, rdx ; .done: mov BUD, rcx
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .rcx, .src = .rdx } });
    try e.code.append(e.gpa, .{ .jcc = .{ .cc = .ae, .rel = 15 } }); // jcc size (6) + underflow branch (10 mov + 5 jmp) = 15 bytes rel
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rcx, .imm = 0 } });
    try e.code.append(e.gpa, .{ .jmp = 3 }); // jmp size (5) + sub_rr positive branch (3) = 3 bytes rel
    try e.code.append(e.gpa, .{ .sub_rr = .{ .dst = .rcx, .src = .rdx } });
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = BUD, .src = .rcx } });

    // ---- RELOAD. The BIF may have written any of these.
    try e.code.append(e.gpa, .{ .load = .{ .reg = RESID, .base = M, .disp = INSTRS_OFF } });
    for (XRES, 0..) |x, i|
        try e.code.append(e.gpa, .{ .load = .{ .reg = x, .base = M, .disp = regDisp(@intCast(i)) } });
}

/// gap-jit-alloc-safepoint-tier: a safe-point used as a GUARD TARGET. Emits the
/// call sequence, then continues natively at `pc+1` iff the shim says the op
/// stayed on the straight-line path. Returns the tail's inst idx so guard `jcc`s
/// can be patched to it — a drop-in replacement for `emitFallbackTail`.
///
/// WHY THIS EXISTS. A guard that jumps to `emitFallbackTail` LEAVES native code:
/// epilogue, return to the driver, one threaded op, then re-entry through the
/// outer entry (prologue + reload). For a guard that fires once in a thousand
/// iterations that is the right trade. For the heap and frame GROW guards it is
/// not — on the real `mylists.beam` program they were 205 of the 213 remaining
/// fallback instructions, i.e. essentially all of it.
///
/// WHAT DOES NOT CHANGE: the interpreter still performs the growth. Allocation
/// never happens inside native code, which is the invariant the whole safe-point
/// discipline exists to protect. Only the ROUND TRIP disappears.
///
/// RE-ENTRANCY. The shim may relocate `ctx.words` and `ystack`. That is safe
/// here for two independent reasons, and both are needed: a zigvm term is a
/// WORD-INDEX rather than an absolute pointer, so a realloc cannot invalidate a
/// live term; and every block re-loads the region base off `M` at the point of
/// use rather than caching it across ops. The second is what makes this correct
/// even for the block that resumes immediately after the call.
fn emitSafepointTail(e: *Emit, ins: *const ia.CInstr, pc: usize) !usize {
    const idx = e.code.items.len;
    try emitSafepointCall(e, ins, pc);

    // verdict != CONTINUE ⇒ yield at whatever pc the shim left.
    try e.code.append(e.gpa, .{ .cmp_ri = .{ .dst = .rax, .imm = @intCast(SHIM_CONTINUE) } });
    const j_yield = try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } });
    const j_next = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });

    // The yield tail: m.pc is ALREADY correct (the shim set it), so unlike
    // `emitFallbackTail` this must not overwrite it.
    const tail = e.code.items.len;
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rax, .imm = RET_YIELD } });
    try e.emitExit();
    try e.inst_fixups.append(e.gpa, .{ .site = j_yield, .target = tail });
    return idx;
}

/// gap-jit-bif-safepoint: emit `bif_call` as a native SAFEPOINT. The whole block
/// IS the safe-point — the budget check falls straight through into it.
fn emitBifSafepointBlock(e: *Emit, ins: *const ia.CInstr, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    _ = try emitSafepointTail(e, ins, pc);
}

/// Emit the block for `jump to` — charge, then native `jmp` to block[to]. R2b: a
/// TAIL jump (`tail == true`, a beam call_only/call_last back-edge) additionally
/// charges 1 per-CALL reduction (`reductionCost(.jump) == 1`); a forward branch
/// charges 0 — mirroring the interpreter's `.jump` arm exactly.
fn emitJumpBlock(e: *Emit, to: usize, pc: usize, tail: bool) !void {
    try emitBudgetCheck(e, pc);
    try emitChargeAndDec(e);
    if (tail) try emitReductionCharge(e);
    const j = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j, .target_pc = to });
}

// ===========================================================================
// jit-calls (JIT epoch slice): the native CONTROL-TRANSFER tier — `call` and
// `ret`. Real BEAM programs are dominated by function calls, so a call/return
// that keeps running native across the call boundary is the tier that lets a
// recursive program stay in machine code (the interpreter fell back on EVERY
// call/return before this). `stepOne` (`instr_algebra.zig`):
//
//   call {to}  : reductions += 1; stack.append(pc+1); pc = to
//   ret        : reductions += 1; if stack nonempty { pc = stack.pop() }
//                                 else { status = halted; result = regs[0] }
//
// The BEAM `call_only` (tail call) is lowered by the loader to a bare `jump`
// (already native — `emitJumpBlock`); `call_last` lowers to `dealloc_y ; jump`
// (the jump stays native, the y-frame drop falls back). So the ops this slice
// makes native are the CP-frame `call` and `ret`.
//
// ## The GC-free-block invariant (L4) and the two guards
//
// Both ops touch ONLY the memory-resident CP stack (`Machine.stack`), never the
// process heap — so a native call/return allocates NOTHING on the GC heap and
// the block stays GC-free by construction (the same footing as the arith/branch
// tier). The ONE place a native `call` could touch the OS allocator is GROWING
// the CP `ArrayList` when it is full; that is exactly the BeamAsm stack-overflow
// / safe-point the epoch design keeps OUT of native code, so we GUARD it:
//
//   * `call` fast path fires ONLY when `stack.len < stack.capacity` (spare slot,
//     no realloc). At capacity it FALLS BACK — the interpreter's `append` grows
//     the stack (its allocation / overflow-check path), then native resumes.
//   * `ret` fast path fires ONLY when `stack.len != 0`. The empty case is the
//     terminal normal-return (status := halted, result := x0) — rare and
//     terminal — left to the interpreter.
//
// ## Why `ret` YIELDS instead of `jmp`-ing
//
// A native branch's target is a compile-time rel32; a `ret`'s target is a
// RUNTIME value popped off the CP stack. So `ret` writes `m.pc := <popped>` and
// returns `RET_YIELD` — the `dispatch.runNativeBlock` driver then re-enters the
// native region at `entries[m.pc]` with the remaining budget (the same
// redispatch it does after every yield). Reductions/budget are charged/consumed
// exactly as the interpreter, so the L2/L3 slice-boundary equalities hold.

/// Emit the block for `call {to}` at `pc` — push the return pc (pc+1) onto the
/// CP stack and native-`jmp` to block[to]. GUARD: only when the CP stack has a
/// spare slot (len < capacity); a full stack FALLS BACK (the interpreter grows
/// it). The capacity guard runs BEFORE any pointer deref, so an empty
/// (capacity-0) stack diverts to fallback without touching `items.ptr`.
fn emitCallBlock(e: *Emit, to: usize, pc: usize) !void {
    try emitBudgetCheck(e, pc);

    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);

    // guard: stack.len < stack.capacity  (spare slot ⇒ no realloc), else fallback
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rax, .base = M, .disp = STACK_LEN_OFF } });
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rcx, .base = M, .disp = STACK_CAP_OFF } });
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .rax, .src = .rcx } }); // len - cap
    try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .ge, .rel = 0 } })); // len >= cap → fallback

    // items[len] = pc+1   (rax still holds len)
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rdx, .base = M, .disp = STACK_PTR_OFF } }); // items.ptr
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .r8, .src = .rax } });
    try e.code.append(e.gpa, .{ .shl_ri = .{ .dst = .r8, .imm = 3 } }); // len*8 (byte offset)
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = .rdx, .src = .r8 } }); // &items[len]
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r8, .imm = @intCast(pc + 1) } }); // return pc
    try e.code.append(e.gpa, .{ .store = .{ .reg = .r8, .base = .rdx, .disp = 0 } });

    // stack.len = len + 1
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r8, .imm = 1 } });
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = .rax, .src = .r8 } });
    try e.code.append(e.gpa, .{ .store = .{ .reg = .rax, .base = M, .disp = STACK_LEN_OFF } });

    try emitChargeAndDec(e); // clobbers rax/rcx — dead now
    try emitReductionCharge(e); // R2b: a `call` is a per-CALL reduction (cost 1)
    const j_to = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_to, .target_pc = to });

    const fb = try emitFallbackTail(e, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

/// Emit the block for `ret` at `pc` — pop the CP stack into `m.pc` and YIELD so
/// the driver redispatches at the popped pc. GUARD: only when the stack is
/// non-empty; an empty stack (the terminal normal-return: status:=halted,
/// result:=x0) FALLS BACK to the interpreter.
fn emitRetBlock(e: *Emit, pc: usize) !void {
    try emitBudgetCheck(e, pc);

    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);

    // guard: stack.len != 0, else fallback (the interpreter takes the halt path)
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rax, .base = M, .disp = STACK_LEN_OFF } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r8, .imm = 0 } });
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .rax, .src = .r8 } }); // len - 0
    try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .e, .rel = 0 } })); // len == 0 → fallback

    // len -= 1; stack.len = len
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r8, .imm = 1 } });
    try e.code.append(e.gpa, .{ .sub_rr = .{ .dst = .rax, .src = .r8 } }); // rax = len-1
    try e.code.append(e.gpa, .{ .store = .{ .reg = .rax, .base = M, .disp = STACK_LEN_OFF } });

    // m.pc = items[len-1]
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rdx, .base = M, .disp = STACK_PTR_OFF } }); // items.ptr
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .r8, .src = .rax } });
    try e.code.append(e.gpa, .{ .shl_ri = .{ .dst = .r8, .imm = 3 } }); // (len-1)*8
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = .rdx, .src = .r8 } }); // &items[len-1]
    try e.code.append(e.gpa, .{ .load = .{ .reg = .r8, .base = .rdx, .disp = 0 } }); // return pc
    try e.code.append(e.gpa, .{ .store = .{ .reg = .r8, .base = M, .disp = PC_OFF } }); // m.pc := return pc

    try emitChargeAndDec(e); // clobbers rax/rcx — dead now
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rax, .imm = RET_YIELD } }); // YIELD → driver redispatches at m.pc
    try e.emitExit();

    const fb = try emitFallbackTail(e, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

// ===========================================================================
// jit-widen-coverage (JIT epoch slice): the NON-ALLOCATING heap-reading tier.
//
// Slices #3/#4 covered arith/move/branch — all register-only. Real list programs
// (`lists:reverse`/`length`/`sum`) spend most of their reductions on cons/tuple
// DESTRUCTURING and TYPE-TEST guards, so they fell to the interpreter every op.
// This slice adds native templates for the common ops that READ the heap but
// NEVER allocate on it, so the native block stays GC-free (L4 holds BY
// CONSTRUCTION — no `test_heap`/`allocate` here, and a read never moves the GC
// roots). Anything that builds a term (`put_list`/`put_tuple2`/…), calls, or
// touches the mailbox stays threaded — a later tier with safe-points.
//
//   * get_list src, hd, tl        — read a cons: hd = words[ptrIdx], tl =
//                                    words[ptrIdx+1]. GUARD `(w&3)==LIST` else
//                                    fall back (a non-cons is the interpreter's).
//   * get_tuple_element src,i,dst  — read tuple element i: words[ptrIdx+1+i].
//                                    GUARD boxed AND header-subtag==TUPLE, else
//                                    fall back (a boxed non-tuple is threaded's).
//   * is_nonempty_list (is_cons)   — TOTAL tag test: (w&3)==LIST.
//   * is_list  (type_test .list)   — TOTAL: (w&3)==LIST OR w==NIL.
//   * is_atom  (type_test .atom)   — TOTAL: (w&0x3F)==ATOM_SUFFIX.
//   * is_tuple (type_test .tuple)  — TOTAL: boxed AND header-subtag==TUPLE
//                                    (dereferences the header — read-only).
//   * is_integer (type_test .integer) — small ⇒ holds; boxed ⇒ FALL BACK (the
//                                    interpreter decides bignum-vs-not); every
//                                    other immediate ⇒ fails to else_to.
// A `Dst`/`Src` operand that is not an x-register (y-slot / literal) makes the
// whole op UNCOVERED (threaded trampoline), exactly like the register-only tier.
//
// Every native-handled path charges EXACTLY one reduction (type-tests charge on
// BOTH the holds and the fails-to-else_to path — the interpreter always does);
// a FALL-BACK path charges nothing (the threaded re-run charges). That keeps L3
// (reductions equal at every slice boundary) intact.
// ===========================================================================

/// An x-register destination, or null if the `Dst` is a y-slot (uncovered).
fn dstXReg(d: ia.Dst) ?ia.XReg {
    return switch (d) {
        .x => |r| r,
        .y => null,
    };
}

/// Set flags from `(src & mask) == val`: ZF=1 iff equal. Uses r8/r9 scratch;
/// leaves `src` untouched. (`and`/`cmp` need register operands — no imm forms.)
fn emitMaskEq(e: *Emit, src: Reg, mask: u64, val: u64) !void {
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r8, .imm = @bitCast(mask) } });
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .r9, .src = src } });
    try e.code.append(e.gpa, .{ .and_rr = .{ .dst = .r9, .src = .r8 } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r8, .imm = @bitCast(val) } });
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .r9, .src = .r8 } }); // r9 - r8
}

/// Set flags from `src == val` (ZF=1 iff equal). Uses r8 scratch; leaves `src`.
fn emitEqImm(e: *Emit, src: Reg, val: u64) !void {
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r8, .imm = @bitCast(val) } });
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = src, .src = .r8 } }); // src - r8
}

/// Compute `&words[ptrIdx(wReg)]` into `addr`. `ptrIdx = w >> 2` (the base index
/// is always positive and small, so the arithmetic `sar` == a logical shift),
/// byte offset = ptrIdx*8 = (w>>2)<<3. Loads the heap base pointer at run time.
/// Clobbers r10; leaves `wReg` untouched. NON-ALLOCATING — pure read address.
fn emitHeapAddr(e: *Emit, wReg: Reg, addr: Reg) !void {
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .r10, .src = wReg } });
    try e.code.append(e.gpa, .{ .sar_ri = .{ .dst = .r10, .imm = 2 } }); // r10 = ptrIdx
    try e.code.append(e.gpa, .{ .shl_ri = .{ .dst = .r10, .imm = 3 } }); // r10 = ptrIdx*8
    try e.code.append(e.gpa, .{ .load = .{ .reg = addr, .base = M, .disp = WORDS_OFF } }); // ctx.words.items.ptr
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = addr, .src = .r10 } }); // &words[ptrIdx]
}

/// The cons-read tier: `get_list src,hd,tl` / `get_hd src,dst` / `get_tl src,dst`
/// — read a cons's head and/or tail (NO allocation). GUARD `(w&3)==LIST` (a cons
/// and nothing else); a non-cons FALLS BACK to the interpreter (which handles the
/// compiler-guaranteed-cons contract / crash).
///
/// gap-jit-cons-read-tier: ONE emitter for all three, because in the interpreter
/// they are one operation — `get_list` is `listHead` then `listTail`, and
/// `get_hd`/`get_tl` are each exactly one of those halves on the same term. Only
/// `get_list` was covered, so a program reading a head WITHOUT its tail fell back
/// while the strictly-larger op beside it ran native. The dynamic profile
/// (`gap-jit-fallback-attribution`) put those two ops at **99.6% of all fallback
/// work** on the alloc+traversal workload — 2352 of 2362 instructions — with the
/// remaining 10 being `put_list` grow-safepoints, which are correct by design.
/// Passing `null` omits that half's load and store; everything else is the same
/// proven guard and address computation.
fn emitConsReadBlock(e: *Emit, src: ia.Src, hd: ?ia.Dst, tl: ?ia.Dst, pc: usize) !void {
    std.debug.assert(hd != null or tl != null); // a read of neither half is not an op
    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);
    _ = try emitMaterialize(e, &guards, .rax, src); // w → rax

    try emitMaskEq(e, .rax, TAG_MASK, TAG_LIST);
    try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } })); // not cons → fallback

    try emitHeapAddr(e, .rax, .rcx); // rcx = &words[ptrIdx]
    // Both loads precede both stores, so a destination that ALIASES the source
    // register (`get_list x0 -> x0, x1`) cannot clobber the address before the
    // second read — and the store ORDER is hd-then-tl, matching the
    // interpreter's `setDst(hd, …); setDst(tl, …)` so that `get_list x, y, y`
    // leaves the tail, exactly as `stepOne` does.
    if (hd != null) try e.code.append(e.gpa, .{ .load = .{ .reg = .rdx, .base = .rcx, .disp = 0 } }); // head
    if (tl != null) try e.code.append(e.gpa, .{ .load = .{ .reg = .r8, .base = .rcx, .disp = 8 } }); // tail
    // gap-jit-frame-tier: a `Dst`, so a frame slot is a legal destination. The
    // real `mylists.beam` profile showed `get_list src=x hd=y tl=x` — a
    // y-DESTINATION was the only reason a covered op fell back 200 times.
    if (hd) |h| _ = try emitWriteDst(e, &guards, h, .rdx);
    if (tl) |t| _ = try emitWriteDst(e, &guards, t, .r8);
    try emitChargeAndDec(e);
    const j_next = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });

    const fb = try emitFallbackTail(e, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

/// jit-alloc-tier: native `put_list dst, h, t` — the FIRST allocating op in the
/// native tier. zigvm's process heap is a `std.ArrayList(u64)` (`ctx.words`) and a
/// term is a WORD-INDEX (`(base<<2)|TAG_LIST`), NOT an absolute pointer — so a
/// grow-realloc NEVER invalidates existing terms (the property that lets native
/// allocation skip BeamAsm's GC-root-preservation dance entirely). The fast path
/// bumps the region in place; a rare grow yields to the interpreter at THIS pc
/// (the SAFE-POINT — the interpreter's `put_list` reallocs + allocates + resumes).
/// Semantic domain: `regs[dst] := cons(h, t)`, the heap extended by exactly two
/// words — observationally identical to `FinalTerms.cons` (the L2 differential).
///   len = ctx.words.items.len   (the new cell's base index)   cap = .capacity
///   FAST (len+2 <= cap): words[len]=h, words[len+1]=t, len+=2, dst=(len<<2)|TAG_LIST
///   SLOW (len+2 >  cap): fall back — the interpreter grows the region + allocates
fn emitPutListBlock(e: *Emit, ins: *const ia.CInstr, h: ia.Src, t: ia.Src, dst: ia.XReg, pc: usize) !void {
    // ArrayList(u64) layout mirrored from WORDS_OFF (items.ptr@+0): len@+8, cap@+16.
    const WORDS_LEN_OFF: i32 = WORDS_OFF + 8;
    const WORDS_CAP_OFF: i32 = WORDS_OFF + 16;
    comptime std.debug.assert(@offsetOf(std.ArrayList(u64), "capacity") == 16);

    try emitBudgetCheck(e, pc);

    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);

    // r8 = len (base index) ; r9 = cap ; rax = len+2 (region end after this cell)
    try e.code.append(e.gpa, .{ .load = .{ .reg = .r8, .base = M, .disp = WORDS_LEN_OFF } });
    try e.code.append(e.gpa, .{ .load = .{ .reg = .r9, .base = M, .disp = WORDS_CAP_OFF } });
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .rax, .src = .r8 } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r10, .imm = 2 } });
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = .rax, .src = .r10 } }); // rax = len+2
    // cap < len+2  ⇒  grow needed ⇒ fallback. cmp r9,rax (r9-rax); jl (signed;
    // both are small non-negative heap indices, so signed `l` == unsigned `b`).
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .r9, .src = .rax } });
    try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .l, .rel = 0 } }));

    // ---- FAST PATH: room exists (rax = len+2, r8 = len) ----
    // rcx = &words[len] = words.items.ptr + len*8
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rcx, .base = M, .disp = WORDS_OFF } });
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .r10, .src = .r8 } });
    try e.code.append(e.gpa, .{ .shl_ri = .{ .dst = .r10, .imm = 3 } });
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = .rcx, .src = .r10 } }); // rcx = &words[len]
    // words[len] = head ; words[len+1] = tail  (materialize is guard-gated below)
    _ = try emitMaterialize(e, &guards, .rdx, h);
    try e.code.append(e.gpa, .{ .store = .{ .reg = .rdx, .base = .rcx, .disp = 0 } });
    _ = try emitMaterialize(e, &guards, .rdx, t);
    try e.code.append(e.gpa, .{ .store = .{ .reg = .rdx, .base = .rcx, .disp = 8 } });
    // dst = (len<<2) | TAG_LIST  (low 2 bits are 0 after <<2, so |1 == +1)
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .rdx, .src = .r8 } });
    try e.code.append(e.gpa, .{ .shl_ri = .{ .dst = .rdx, .imm = 2 } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r10, .imm = @bitCast(TAG_LIST) } });
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = .rdx, .src = .r10 } });
    try writeX(e, dst, .rdx);
    // COMMIT the allocation: ctx.words.items.len = len+2 (rax) — the LAST write.
    try e.code.append(e.gpa, .{ .store = .{ .reg = .rax, .base = M, .disp = WORDS_LEN_OFF } });

    try emitChargeAndDec(e);
    const j_next = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });

    // gap-jit-alloc-safepoint-tier: the heap GROW guard is a SAFE-POINT. The
    // materialize guards share the tail, which is correct rather than merely
    // convenient: the shim re-executes the WHOLE instruction through the
    // interpreter, so it handles an operand the fast path could not.
    const fb = try emitSafepointTail(e, ins, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

/// jit-alloc-tier: native `put_tuple2 dst, {e0,e1,…}` — the tuple sibling of
/// `put_list`. Same in-place region-bump over the index-based heap; a tuple is
/// `1 + N` words (a header `(N<<7)|SUBTAG_TUPLE` then the N element words) tagged
/// `(base<<2)|TAG_BOXED`. Arity N is known at compile time (the `elems` slice), so
/// the N element stores are unrolled. Semantic domain: `regs[dst] := tuple(elems)`,
/// heap extended by `1+N` words — observationally identical to `FinalTerms.tuple`.
///   FAST (len+1+N <= cap): words[len]=hdr, words[len+1+k]=elem[k], len+=1+N,
///                          dst=(len<<2)|TAG_BOXED
///   SLOW: fall back — the interpreter grows the region + allocates (SAFE-POINT).
fn emitPutTuple2Block(e: *Emit, ins: *const ia.CInstr, elems: []const ia.Src, dst: ia.XReg, pc: usize) !void {
    comptime std.debug.assert(SUBTAG_TUPLE_INPLACE == 0); // tuple header subtag bits are 0
    const WORDS_LEN_OFF: i32 = WORDS_OFF + 8;
    const WORDS_CAP_OFF: i32 = WORDS_OFF + 16;
    const total: usize = 1 + elems.len; // header + N elements

    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);

    // r8 = len ; r9 = cap ; rax = len + (1+N)
    try e.code.append(e.gpa, .{ .load = .{ .reg = .r8, .base = M, .disp = WORDS_LEN_OFF } });
    try e.code.append(e.gpa, .{ .load = .{ .reg = .r9, .base = M, .disp = WORDS_CAP_OFF } });
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .rax, .src = .r8 } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r10, .imm = @intCast(total) } });
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = .rax, .src = .r10 } }); // rax = len+total
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .r9, .src = .rax } });
    try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .l, .rel = 0 } })); // cap < len+total → grow

    // ---- FAST PATH (rax = len+total, r8 = len) ----
    // rcx = &words[len]
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rcx, .base = M, .disp = WORDS_OFF } });
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .r10, .src = .r8 } });
    try e.code.append(e.gpa, .{ .shl_ri = .{ .dst = .r10, .imm = 3 } });
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = .rcx, .src = .r10 } }); // rcx = &words[len]
    // words[len] = header (N<<7) | (SUBTAG_TUPLE<<2 == 0)
    const hdr: u64 = @as(u64, elems.len) << 7;
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .rdx, .imm = @bitCast(hdr) } });
    try e.code.append(e.gpa, .{ .store = .{ .reg = .rdx, .base = .rcx, .disp = 0 } });
    // words[len+1+k] = elem[k]  (materialize is guard-gated below; disp is comptime k)
    for (elems, 0..) |elem, k| {
        _ = try emitMaterialize(e, &guards, .rdx, elem);
        const disp: i32 = @intCast(8 * (1 + k));
        try e.code.append(e.gpa, .{ .store = .{ .reg = .rdx, .base = .rcx, .disp = disp } });
    }
    // dst = (len<<2) | TAG_BOXED  (low 2 bits 0 after <<2, so |2 == +2)
    try e.code.append(e.gpa, .{ .mov_rr = .{ .dst = .rdx, .src = .r8 } });
    try e.code.append(e.gpa, .{ .shl_ri = .{ .dst = .rdx, .imm = 2 } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r10, .imm = @bitCast(TAG_BOXED) } });
    try e.code.append(e.gpa, .{ .add_rr = .{ .dst = .rdx, .src = .r10 } });
    try writeX(e, dst, .rdx);
    // COMMIT: ctx.words.items.len = len+total (rax) — the LAST write.
    try e.code.append(e.gpa, .{ .store = .{ .reg = .rax, .base = M, .disp = WORDS_LEN_OFF } });

    try emitChargeAndDec(e);
    const j_next = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });

    // gap-jit-alloc-safepoint-tier: same heap GROW guard as `put_list`, same
    // safe-point. Included even though the real-program profile does not reach
    // it, because leaving one allocating op on the old tail is how a tier grows
    // an inconsistency that only a future workload discovers.
    const fb = try emitSafepointTail(e, ins, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

/// `get_tuple_element src, index, dst` — read element `index` (0-based). GUARD
/// boxed AND header-subtag==TUPLE; a boxed non-tuple / non-boxed FALLS BACK.
fn emitGetTupleElemBlock(e: *Emit, src: ia.Src, index: u16, dst: ia.Dst, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);
    _ = try emitMaterialize(e, &guards, .rax, src); // w → rax

    try emitMaskEq(e, .rax, TAG_MASK, TAG_BOXED);
    try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } })); // not boxed → fallback

    try emitHeapAddr(e, .rax, .rcx); // rcx = &words[ptrIdx] (= &header)
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rdx, .base = .rcx, .disp = 0 } }); // header
    try emitMaskEq(e, .rdx, SUBTAG_FIELD, SUBTAG_TUPLE_INPLACE);
    try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } })); // boxed non-tuple → fallback

    // element `index` lives at words[ptrIdx + 1 + index] == [rcx + 8*(1+index)].
    const disp: i32 = @intCast(8 * (1 + @as(i64, index)));
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rdx, .base = .rcx, .disp = disp } });
    _ = try emitWriteDst(e, &guards, dst, .rdx);
    try emitChargeAndDec(e);
    const j_next = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });

    const fb = try emitFallbackTail(e, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

/// The native type-test strategies (each maps a covered `TypeTestKind` / `is_cons`
/// to an emitted predicate). TOTAL kinds decide natively for every term; `integer`
/// defers the boxed case (bignum-vs-not) to the interpreter.
const NativeTT = enum { cons, list, atom, tuple, integer };

/// Which type tests are natively covered (else uncovered → threaded trampoline).
fn nativeTTofKind(k: ia.TypeTestKind) ?NativeTT {
    return switch (k) {
        .list => .list,
        .atom => .atom,
        .tuple => .tuple,
        .integer => .integer,
        else => null,
    };
}

/// Emit a covered type-test guard: fall through to block[pc+1] iff the predicate
/// HOLDS, else native `jmp` to block[else_to]. Every native-decided path charges
/// exactly one reduction (BOTH holds and fails — mirroring the interpreter);
/// `integer`'s boxed case FALLS BACK (no charge; the interpreter re-runs it).
fn emitTypeTestBlock(e: *Emit, kind: NativeTT, src: ia.Src, else_to: usize, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    // The term lives in r11 for the whole block: `emitChargeAndDec` clobbers
    // rax/rcx, and type-tests charge BEFORE inspecting the term, so it must
    // survive the charge (the same reason `emitCmpBlock` keeps operands in
    // r10/r11). r11 is caller-saved and untouched by charge / the mask helpers.
    const W: Reg = .r11;
    _ = try emitMaterialize(e, null, W, src); // w → r11

    switch (kind) {
        .cons => {
            // TOTAL: (w&3)==LIST ⟺ cons. Charge, then branch.
            try emitChargeAndDec(e);
            try emitMaskEq(e, W, TAG_MASK, TAG_LIST);
            const j_else = try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } }); // not cons → else_to
            try e.pc_fixups.append(e.gpa, .{ .site = j_else, .target_pc = else_to }); // holds: fall through
        },
        .atom => {
            // TOTAL: (w & 0x3F) == ATOM_SUFFIX.
            try emitChargeAndDec(e);
            try emitMaskEq(e, W, IMM_MASK6, ATOM_SUFFIX);
            const j_else = try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } }); // not atom → else_to
            try e.pc_fixups.append(e.gpa, .{ .site = j_else, .target_pc = else_to });
        },
        .list => {
            // TOTAL: cons OR nil. Two holds-conditions join at block[pc+1].
            try emitChargeAndDec(e);
            try emitMaskEq(e, W, TAG_MASK, TAG_LIST);
            const j_cons = try e.emit(.{ .jcc = .{ .cc = .e, .rel = 0 } }); // cons → holds
            try emitEqImm(e, W, NIL_WORD);
            const j_nil = try e.emit(.{ .jcc = .{ .cc = .e, .rel = 0 } }); // nil → holds
            const j_else = try e.emit(.{ .jmp = 0 });
            try e.pc_fixups.append(e.gpa, .{ .site = j_else, .target_pc = else_to });
            // holds → block[pc+1], emitted immediately after this block.
            try e.inst_fixups.append(e.gpa, .{ .site = j_cons, .target = e.code.items.len });
            try e.inst_fixups.append(e.gpa, .{ .site = j_nil, .target = e.code.items.len });
        },
        .tuple => {
            // TOTAL: boxed AND header-subtag==TUPLE (a read-only header deref).
            // Both fail-paths (not boxed / wrong subtag) charge and jump else_to.
            try emitChargeAndDec(e);
            try emitMaskEq(e, W, TAG_MASK, TAG_BOXED);
            const j_nb = try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } }); // not boxed → else_to
            try e.pc_fixups.append(e.gpa, .{ .site = j_nb, .target_pc = else_to });
            try emitHeapAddr(e, W, .rcx); // rcx = &header
            try e.code.append(e.gpa, .{ .load = .{ .reg = .rdx, .base = .rcx, .disp = 0 } });
            try emitMaskEq(e, .rdx, SUBTAG_FIELD, SUBTAG_TUPLE_INPLACE);
            const j_bad = try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } }); // wrong subtag → else_to
            try e.pc_fixups.append(e.gpa, .{ .site = j_bad, .target_pc = else_to });
            // holds: fall through to block[pc+1].
        },
        .integer => {
            // small ⇒ holds; boxed ⇒ FALL BACK; other immediate ⇒ else_to.
            var guards: std.ArrayList(usize) = .empty;
            defer guards.deinit(e.gpa);
            // boxed? → fallback (BEFORE charging — the interpreter charges on re-run)
            try emitMaskEq(e, W, TAG_MASK, TAG_BOXED);
            try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .e, .rel = 0 } }));
            // not boxed ⇒ native decides (total): charge, then small?
            try emitChargeAndDec(e);
            try emitMaskEq(e, W, SMALL_SUFFIX, SMALL_SUFFIX);
            const j_else = try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } }); // not small → else_to
            try e.pc_fixups.append(e.gpa, .{ .site = j_else, .target_pc = else_to });
            const j_next = try e.emit(.{ .jmp = 0 }); // small → holds (skip the FB tail)
            try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });
            const fb = try emitFallbackTail(e, pc);
            for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
        },
    }
}

/// Build the native block for one instruction (covered → real codegen; else an
/// uncovered-op trampoline that yields to the interpreter at this pc).
fn buildBlock(e: *Emit, insp: *const ia.CInstr, pc: usize) !void {
    switch (insp.*) {
        .move => |m| if (moveSrcOk(m.src)) return emitMoveBlock(e, m.src, m.dst, pc),
        .add => |a| if (smallOperandOk(a.a) and smallOperandOk(a.b)) return emitArithBlock(e, a.a, a.b, a.dst, .add, pc),
        .sub => |s| if (smallOperandOk(s.a) and smallOperandOk(s.b)) return emitArithBlock(e, s.a, s.b, s.dst, .sub, pc),
        .jump => |j| return emitJumpBlock(e, j.to, pc, j.tail),
        // ---- jit-calls: native CP-frame control transfers ----
        .call => |c| return emitCallBlock(e, c.to, pc),
        .ret => return emitRetBlock(e, pc),
        .is_lt => |t| if (smallOperandOk(t.a) and smallOperandOk(t.b))
            return emitCmpBlock(e, t.a, t.b, t.else_to, pc, .{ .untag = true, .holds = .l }),
        // gap-jit-testeq-operand-widening: the IMMEDIATE-side word compare is
        // tried FIRST, because it strictly dominates the guarded small compare
        // wherever it applies — `x =:= some_atom` under the old arm compiled to
        // a small-tag guard that fell back on every non-small x, which is every
        // interesting case. Only when NEITHER side is immediate does soundness
        // require the tag guards, and then the old arm handles it.
        .test_eq => |t| {
            if (eqOperandImmediate(t.a) or eqOperandImmediate(t.b)) {
                if (frameSrcOk(t.a) and frameSrcOk(t.b))
                    return emitEqImmBlock(e, t.a, t.b, t.else_to, pc);
            } else if (smallOperandOk(t.a) and smallOperandOk(t.b)) {
                return emitCmpBlock(e, t.a, t.b, t.else_to, pc, .{ .untag = false, .holds = .e });
            }
        },
        .cmp_test => |c| if (smallOperandOk(c.a) and smallOperandOk(c.b)) {
            const shape: CmpShape = switch (c.op) {
                .ge => .{ .untag = true, .holds = .ge },
                .eq_arith => .{ .untag = false, .holds = .e },
                .ne_arith => .{ .untag = false, .holds = .ne },
                .ne_exact => .{ .untag = false, .holds = .ne },
            };
            return emitCmpBlock(e, c.a, c.b, c.else_to, pc, shape);
        },
        // ---- jit-widen-coverage: NON-ALLOCATING heap-reading tier ----
        // gap-jit-frame-tier: `frameSrcOk` + a `Dst` destination, so a frame slot
        // works on either side (the real-program profile's `hd=y` case).
        .get_list => |g| if (frameSrcOk(g.src))
            return emitConsReadBlock(e, g.src, g.hd, g.tl, pc),
        // gap-jit-cons-read-tier: the two halves of `get_list`, which the dynamic
        // fallback profile ranked as 99.6% of all fallback work on the
        // alloc+traversal workload.
        .get_hd => |g| if (frameSrcOk(g.src))
            return emitConsReadBlock(e, g.src, g.dst, null, pc),
        .get_tl => |g| if (frameSrcOk(g.src))
            return emitConsReadBlock(e, g.src, null, g.dst, pc),
        // gap-jit-frame-tier: the three ops the REAL mylists.beam profile ranked
        // top — move2 (402 fallback instrs), alloc_y and dealloc_y (400 each).
        .move2 => |v| if (frameSrcOk(v.src)) return emitMove2Block(e, v.src, v.dst, pc),
        .alloc_y => |a| return emitAllocYBlock(e, insp, a.n, pc),
        // gap-jit-guard-write-tier-batch: three census-selected tiers sharing one
        // guard+write mechanism. None of the three occurs in mylists.beam.
        .swap => |v| if (frameSrcOk(ia.dstAsSrc(v.a)) and frameSrcOk(ia.dstAsSrc(v.b)))
            return emitSwapBlock(e, v.a, v.b, pc),
        .trim => |t| return emitTrimBlock(e, t.n, pc),
        .test_arity => |t| if (frameSrcOk(t.src))
            return emitTestArityBlock(e, t.src, t.arity, t.else_to, pc),
        .dealloc_y => |d| return emitDeallocYBlock(e, d.n, pc),
        // gap-jit-bif-safepoint: 65% of the real program's residual fallback.
        .bif_call => return emitBifSafepointBlock(e, insp, pc),
        // ---- gap-jit-tier-call-ext: compile external BIFs and cross-module calls as safepoints ----
        .call_ext_bif => return emitBifSafepointBlock(e, insp, pc),
        .call_ext_code => return emitBifSafepointBlock(e, insp, pc),
        .get_tuple_elem => |g| if (frameSrcOk(g.src))
            return emitGetTupleElemBlock(e, g.src, g.index, g.dst, pc),
        .is_cons => |t| if (moveSrcOk(t.src)) return emitTypeTestBlock(e, .cons, t.src, t.else_to, pc),
        // ---- jit-alloc-tier: the ALLOCATING tier (in-place region bump) ----
        // gap-jit-alloc-safepoint-tier: `frameSrcOk`, not `moveSrcOk`. The real
        // `mylists.beam` cons is `put_list dst=x0, h=y0, t=x0` — a FRAME-SLOT
        // head, which `moveSrcOk` rejects, so every one of its 200 executions
        // was going to the uncovered-op trampoline and never reached the
        // allocating block at all. The grow guard was never what stopped it.
        .put_list => |p| if (frameSrcOk(p.h) and frameSrcOk(p.t))
            return emitPutListBlock(e, insp, p.h, p.t, p.dst, pc),
        .put_tuple2 => |p| if (dstXReg(p.dst)) |d| {
            var ok = true;
            for (p.elems) |el| {
                if (!frameSrcOk(el)) {
                    ok = false;
                    break;
                }
            }
            if (ok) return emitPutTuple2Block(e, insp, p.elems, d, pc);
        },
        .type_test => |t| if (moveSrcOk(t.src)) {
            if (nativeTTofKind(t.kind)) |ntt| return emitTypeTestBlock(e, ntt, t.src, t.else_to, pc);
        },
        else => {},
    }
    _ = try emitFallbackTail(e, pc); // uncovered / uncoverable-operand trampoline
}

/// What ONE BEAM instruction costs in emitted native code.
pub const OpCost = struct {
    pc: usize,
    tag: []const u8, // the BEAM op's tag name
    native_insts: usize, // native instructions in this pc's block
    native_bytes: usize, // encoded size of that block
    /// gap-jit-xreg-residency: `load`/`store` instructions in this pc's block —
    /// the block's traffic against the memory-resident machine state.
    ///
    /// A THIRD AXIS, added because the first two are blind to register
    /// residency. Replacing `mov rax,[rdi+disp]` with `mov rax,r12` removes a
    /// memory operand and leaves the instruction COUNT unchanged; on the
    /// benchmark loop residency moves insts by 0 and bytes by −30, which reads
    /// as a rounding error and is not what the change does. What it does is
    /// halve the memory traffic, and that is exactly as static, exact and
    /// host-independent as the other two — no clock required to count `load`
    /// and `store` in an instruction stream.
    ///
    /// This is the same lesson `gap-jit-mask-imm` taught (instructions and
    /// bytes can move in opposite directions), one step further: a cost model
    /// only sees the axes it has. It does NOT claim a cycle count — an L1 hit
    /// and a register read differ by microarchitecture, not by anything
    /// derivable here. It claims the operand is gone, which is a fact about the
    /// emitted code.
    mem_ops: usize,
    covered: bool, // real codegen, vs an uncovered-op trampoline
};

/// Whether `inst` addresses memory (the `mem_ops` axis). The block JIT's only
/// memory forms are `load`/`store`; `push`/`pop` touch the stack but appear
/// exclusively in the outer entry / epilogue, which belong to no pc.
fn isMemOp(inst: Inst) bool {
    return switch (inst) {
        .load, .store => true,
        else => false,
    };
}

/// STATIC cost attribution for the block JIT — the {P} epoch's measurement
/// instrument, and the thing that must exist BEFORE any codegen work.
///
/// WHY STATIC. The only {P} number in the tree is an end-to-end throughput ratio
/// (0.148x BeamAsm, refreshed under Lane D). It says the JIT is 6.77x behind and
/// nothing about WHERE the 6.77x goes, so any codegen change is an optimization
/// of a guessed cell — the FM-SMP-CONTENTION-BLIND failure in a different
/// subsystem. It also cannot be improved upon here: a ~5% codegen win sits below
/// the measurement noise of `--bench-beamasm` on a contended shared host, so the
/// timing route cannot even confirm a real gain.
///
/// This instrument is a pure function of the program. No clock, no host, no
/// contention — the same program yields the same attribution on any machine, so
/// a codegen change shows up as an exact instruction-count delta rather than a
/// reading inside the noise band.
///
/// COVERAGE IS EXACT, not a heuristic. An uncovered op's block IS precisely the
/// fallback trampoline; a covered op's block is its guards and work AND a
/// trampoline for the guards to jump to. A covered block therefore always has
/// strictly more instructions than the bare tail, so comparing against a
/// reference tail emitted at the same pc decides coverage exactly.
///
/// ── THE FIRST ATTRIBUTION PASS, TRIAGED ────────────────────────────────────
/// Running `attribute` on the benchmark loop gives 125 native instructions for
/// 4 BEAM ops (cmp_test 32, add 40, sub 40, jump 13). Reading where those go
/// resolves three candidate levers — two of them CLOSED by hard constraints,
/// which is the point of measuring before optimizing:
///
///  1. HOIST the per-block `mov_ri MASK, SMALL_SUFFIX`. It reloads a
///     loop-invariant constant in every arith and cmp block. **Structurally
///     blocked, not merely unimplemented:** `entries[pc]` makes EVERY block an
///     independent entry point — the interpreter can enter at any pc — so there
///     is no shared prologue to hoist into and no block may assume a register
///     holds anything on entry. Doing this needs DUAL-ENTRY blocks (an outer
///     entry that establishes invariants, an inner one for native-to-native
///     jumps, with fixups targeting the inner). That is a codegen-structure
///     change, and it is the largest single lever visible here.
///
///     LANDED (gap-jit-instrs-resident): 114 -> 106 instructions and 660 -> 624
///     bytes; cumulative 125 -> 106 (-15.2%) and 744 -> 624 (-16.1%).
///
///     THE BUG THE FIRST ATTEMPT HIT, recorded because it is not obvious. With
///     prologues emitted BETWEEN blocks, a block ending without a branch —
///     `move` is one — fell through into the NEXT block's `push`, so one native
///     run pushed twice and popped once and the shared epilogue's `ret` took a
///     garbage address. A 0x0 segfault from a LAYOUT change, not bookkeeping.
///     Inner blocks must stay CONTIGUOUS (fall-through is a live invariant that
///     predates dual entry); prologues live after the block region, each jumping
///     to its inner entry, so nothing can fall into one and the push/pop pair is
///     balanced by construction rather than by inspection.
///
///     X-REGISTER RESIDENCY — LANDED (gap-jit-xreg-residency), and it moved a
///     metric this instrument did not have.
///
///     THE SCOPE, CORRECTED. An earlier pass here called it "a register
///     ALLOCATOR across eleven access sites". Enumerating them showed one READ
///     chokepoint (`materialize`'s `.x` arm) and seven stereotyped block-path
///     writes; the other three "sites" were the read's definition and the
///     retired per-op stub path, which has no prologue and stays memory-only.
///     Two helpers — `readX` / `writeX` — cover all of it, and the flush is the
///     shared epilogue this slice's predecessor had already built.
///
///     WHAT IT ACTUALLY BOUGHT, on the same benchmark loop:
///
///         instructions   106 → 106   (ZERO — a resident read is still a `mov`)
///         bytes          624 → 594   (-4.8%)
///         memory ops      13 →   7   (-46.2%)   ← the axis that moved
///
///     The first two numbers are why `OpCost.mem_ops` exists. Residency does
///     not remove instructions; it removes memory OPERANDS, turning
///     `mov rax,[rdi+disp]` into `mov rax,r12`. Judged on the two axes the
///     instrument had, this slice would have read as a rounding error and been
///     hard to justify landing. A cost model only sees the axes it has — the
///     same lesson `gap-jit-mask-imm` taught when instructions and bytes
///     disagreed, one step further along.
///
///     The arith block's hot path now addresses the register file ZERO times
///     (checked structurally, arm 6 of the law): both remaining memory operands
///     in that block are `m.pc` writes on cold exit paths.
///
///     WHAT IT DOES NOT CLAIM. Nothing here is a cycle count. Whether removing
///     an L1-hitting load is worth ~4 cycles or ~0 is a microarchitectural
///     question this instrument cannot answer and `--bench-beamasm` cannot
///     resolve on a contended host. The claim is the operand is gone, which is
///     a fact about the emitted bytes.
///
///     ITS PAYOFF HAS MOVED. Hoisting a tag constant was the original
///     motivation and is now moot — gap-jit-mask-imm and gap-jit-imm-prologue
///     removed every per-block constant load by naming the values as
///     immediates, which needed no structural change at all. What dual entry
///     still buys is REGISTER RESIDENCY across native-to-native transitions:
///     `m.instrs` is loaded, incremented and stored in every single block
///     (3 instructions of ~37), and a resident counter would make that one
///     `add reg, 1`. The same argument extends to hot X registers.
///
///     EXIT AUDIT (done, so the slice is de-risked): residency is correct iff
///     EVERY native exit flushes. There are exactly THREE, all ending `.ret`
///     after writing `m.pc`, so the flush is the same shape as code already
///     there:
///       - `emitBudgetCheck`'s yield tail   (budget exhausted → RET_YIELD)
///       - `emitFallbackTail`               (uncovered op / failed guard)
///       - `emitRetBlock`'s yield           (CP-frame return → RET_YIELD)
///     A missed flush shows up as a wrong `instrs` count, which the
///     whole-corpus differential compares (denotation AND reductions) — so the
///     net exists, but the slice needs its own verification pass rather than
///     riding on another's.
///
///  2. FOLD the fits-small range guards into immediate compares, removing two
///     `mov_ri rdx, ±SMALL_HI` materializations per arith block. **Closed by
///     the ISA:** x86-64 `cmp r64, imm32` sign-extends a 32-bit immediate, and
///     `SMALL_HI = 1 << 59` = 576460752303423488 does not fit. The
///     materialization is forced by the hardware, not by this codegen. A clean
///     negative result — worth recording so nobody re-derives it.
///
///  3. ELIMINATE the MASK register via immediate forms. `SMALL_SUFFIX = 0xF`
///     DOES fit imm32, so `and`/`cmp`/`add` against it can be immediate and r9
///     is freed along with its per-block load. **LANDED** (gap-jit-mask-imm):
///     125 -> 122 instructions and 744 -> 728 bytes on this loop, measured
///     exactly by `attribute` before and after. r9 is now unallocated.
///     Extended by gap-jit-imm-prologue to the per-block budget check and
///     retire charge (`cmp rsi,0`, `add ...,1`, `sub rsi,1`), which reach EVERY
///     block rather than only the arith/cmp ones: cumulative 125 -> 114
///     instructions and 744 -> 660 bytes, -8.8% and -11.3%.
///
///     The instrument earned its keep twice here. The first implementation used
///     only the imm32 form and made the two metrics DISAGREE — 3 fewer
///     instructions but 26 MORE bytes, since `and r64, imm32` is wider than
///     `and r64, r64` plus one shared constant load. Emitting the sign-extended
///     imm8 form when the value fits turned it into a win on both. A framing of
///     "remove a redundant instruction" would have shipped the version that grew
///     the code, and timing could not have told the difference.
///
/// Caller owns the returned slice.
pub fn attribute(gpa: std.mem.Allocator, prog: ia.Program) ![]OpCost {
    const out = try gpa.alloc(OpCost, prog.len);
    errdefer gpa.free(out);

    var e = Emit{ .gpa = gpa };
    defer e.deinit();
    const block_entry = try gpa.alloc(usize, prog.len + 1);
    defer gpa.free(block_entry);

    for (prog, 0..) |_, pc| {
        block_entry[pc] = e.code.items.len;
        try buildBlock(&e, &prog[pc], pc);
    }
    block_entry[prog.len] = e.code.items.len;
    _ = try e.emitEpilogue();

    for (prog, 0..) |ins, pc| {
        const lo = block_entry[pc];
        const hi = block_entry[pc + 1];
        var bytes: usize = 0;
        var mem: usize = 0;
        for (e.code.items[lo..hi]) |inst| {
            bytes += jit_asm.encode(inst).len;
            if (isMemOp(inst)) mem += 1;
        }
        // the reference trampoline at this pc — see COVERAGE IS EXACT above
        var ref = Emit{ .gpa = gpa };
        defer ref.deinit();
        _ = try emitFallbackTail(&ref, pc);
        out[pc] = .{
            .pc = pc,
            .tag = @tagName(ins),
            .native_insts = hi - lo,
            .native_bytes = bytes,
            .mem_ops = mem,
            .covered = (hi - lo) != ref.code.items.len,
        };
    }
    return out;
}

/// Compile `prog` into ONE contiguous native region (the block JIT). Each pc gets
/// a block; a trailing tail block at pc==len handles fall-off-the-end. Two-pass:
/// lay out byte offsets, then patch every fixup (forward + backward).
/// LIFETIME OBLIGATION (gap-jit-bif-safepoint): a `bif_call` block bakes
/// `&prog[pc]` into the emitted machine code, so **`prog` must outlive the
/// returned `NativeBlock`**. `dispatch.compileNativeBlock` discharges this by
/// compiling against its own predecoded copy, which it owns and frees with the
/// block; direct callers (the law suites) pass arrays that outlive their use.
pub fn compileBlock(gpa: std.mem.Allocator, prog: ia.Program) !NativeBlock {
    const entries = try gpa.alloc(?BlockFn, prog.len);
    errdefer gpa.free(entries);
    @memset(entries, null);
    if (!native_supported) return .{ .exec = null, .entries = entries };

    var e = Emit{ .gpa = gpa };
    defer e.deinit();

    const block_entry = try gpa.alloc(usize, prog.len + 1); // [len] == tail block
    defer gpa.free(block_entry);

    // DUAL ENTRY. `outer_entry[pc]` is what the dispatcher calls: it establishes
    // the native-run invariants (rbx saved, m.instrs resident) and falls through
    // to `block_entry[pc]`, the INNER entry that native-to-native jumps target.
    // Without the split every jump would re-establish the invariant and the
    // residency would buy nothing.
    const outer_entry = try gpa.alloc(usize, prog.len);
    defer gpa.free(outer_entry);

    // INNER blocks stay CONTIGUOUS. Several blocks (`move` among them) end with
    // no branch and rely on falling through to the next block — an invariant
    // that predates dual entry. Interleaving prologues between blocks silently
    // broke it: a fall-through executed the NEXT block's `push`, so one native
    // run pushed twice and popped once, and the shared epilogue's `ret` took a
    // garbage address. That was the 0x0 segfault, and it was a LAYOUT bug, not
    // a bookkeeping one.
    for (prog, 0..) |_, pc| {
        block_entry[pc] = e.code.items.len;
        try buildBlock(&e, &prog[pc], pc);
    }
    block_entry[prog.len] = e.code.items.len;
    _ = try emitFallbackTail(&e, prog.len); // tail: m.pc = len; return FALLBACK
    const epilogue = try e.emitEpilogue();

    // OUTER entries live AFTER the block region, each a prologue plus an
    // explicit jump to its inner entry. Nothing can fall into one, so the
    // push/pop pair is balanced by construction rather than by inspection.
    for (0..prog.len) |pc| {
        outer_entry[pc] = e.code.items.len;
        try emitOuterEntry(&e);
        const j = try e.emit(.{ .jmp = 0 });
        try e.pc_fixups.append(gpa, .{ .site = j, .target_pc = pc });
    }

    for (e.exit_fixups.items) |site|
        try e.inst_fixups.append(gpa, .{ .site = site, .target = epilogue });

    // Pass 1: byte offset per inst (widths are stable under the rel patch).
    const byte_off = try gpa.alloc(usize, e.code.items.len);
    defer gpa.free(byte_off);
    var acc: usize = 0;
    for (e.code.items, 0..) |inst, i| {
        byte_off[i] = acc;
        acc += jit_asm.encode(inst).len;
    }
    // Pass 2: patch fixups (rel = target − end-of-site).
    for (e.inst_fixups.items) |f| {
        const after = byte_off[f.site] + jit_asm.encode(e.code.items[f.site]).len;
        setRel(&e.code.items[f.site], @as(i64, @intCast(byte_off[f.target])) - @as(i64, @intCast(after)));
    }
    for (e.pc_fixups.items) |f| {
        const tgt_pc = if (f.target_pc >= prog.len) prog.len else f.target_pc; // clamp to tail
        const target_idx = block_entry[tgt_pc];
        const after = byte_off[f.site] + jit_asm.encode(e.code.items[f.site]).len;
        setRel(&e.code.items[f.site], @as(i64, @intCast(byte_off[target_idx])) - @as(i64, @intCast(after)));
    }

    const blob = try jit_asm.emitProgram(gpa, e.code.items);
    defer gpa.free(blob);

    var exec = try jit_exec.ExecBuffer.alloc(blob.len, null);
    errdefer exec.free();
    try exec.write(blob);
    try exec.seal();
    // The dispatcher enters at the OUTER entry (prologue), never the inner one.
    for (0..prog.len) |pc| entries[pc] = try exec.entryAt(byte_off[outer_entry[pc]], BlockFn);
    return .{ .exec = exec, .entries = entries };
}

// ===========================================================================
// Law suite — the codegen's own unit/homomorphism laws. (The L2/L3 differential
// lives in dispatch.zig, extending the permanent engine-#4 harness.)
// ===========================================================================

const testing = std.testing;

test "BAKED-TERM GROUND: baked small/nil/atom constants byte-equal FinalTerms" {
    var atoms = ta.AtomTable.init(testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(testing.allocator, &atoms);
    defer ctx.deinit();
    const vals = [_]i64{ 0, 1, -1, 42, -42, (1 << 59) - 1, -(1 << 59), 0x7fff_ffff, -0x8000_0000 };
    for (vals) |v| {
        try testing.expectEqual(FinalTerms.int(&ctx, v), smallTerm(v));
    }
    try testing.expectEqual(FinalTerms.nil(&ctx), FinalTerms.nil_term);
    var idx: u32 = 0;
    while (idx < 64) : (idx += 1) {
        try testing.expectEqual(FinalTerms.atom(&ctx, @intCast(idx)), FinalTerms.atomTerm(@intCast(idx)));
    }
}

// A helper that compiles ONE instruction and returns its native stub fn-ptr
// (asserting the instruction was actually covered — real native code exists).
fn compileOne(gpa: std.mem.Allocator, ins: ia.CInstr) !struct { c: Compiled, f: NativeFn } {
    var buf = [_]ia.CInstr{ins};
    var c = try compile(gpa, buf[0..]);
    errdefer c.deinit(gpa);
    const f = c.entries[0] orelse return error.NotCompiled;
    return .{ .c = c, .f = f };
}

test "HOMOMORPHISM: native move ≡ interpreter move (x/imm/nil operands)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    const srcs = [_]ia.Src{ .{ .x = 3 }, .{ .imm = 12345 }, .{ .imm = -7 }, .nil, .{ .atom_ = 5 } };
    for (srcs) |src| {
        const ins = ia.CInstr{ .move = .{ .src = src, .dst = 9 } };

        // interpreter reference
        var mi = try ia.Machine.init(gpa, &atoms);
        defer mi.deinit();
        mi.regs[3] = FinalTerms.int(&mi.ctx, 99);
        const before_instrs_i = mi.instrs;
        try ia.execInstr(&mi, ins);

        // native
        var mn = try ia.Machine.init(gpa, &atoms);
        defer mn.deinit();
        mn.regs[3] = FinalTerms.int(&mn.ctx, 99);
        var one = try compileOne(gpa, ins);
        defer one.c.deinit(gpa);
        const rc = one.f(&mn); // ← REAL native execution
        try testing.expectEqual(@as(u64, 0), rc); // move always handled natively

        try testing.expectEqual(mi.regs[9], mn.regs[9]);
        try testing.expectEqual(mi.reductions, mn.reductions); // both 0 (move is straight-line)
        try testing.expectEqual(mi.instrs, mn.instrs);
        try testing.expectEqual(before_instrs_i + 1, mn.instrs); // R2b: +1 instr retired
    }
}

test "HOMOMORPHISM: native add/sub small fast path ≡ interpreter" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    var prng = std.Random.DefaultPrng.init(0x6A69_7461_7269_7468); // "jitarith"
    const rnd = prng.random();

    for ([_]ArithKind{ .add, .sub }) |kind| {
        var n: usize = 0;
        while (n < 2000) : (n += 1) {
            // i32-range operands: the small result always fits ⇒ native fast path.
            const va: i64 = rnd.int(i32);
            const vb: i64 = rnd.int(i32);
            const ins: ia.CInstr = switch (kind) {
                .add => .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 2 }, .dst = 4 } },
                .sub => .{ .sub = .{ .a = .{ .x = 1 }, .b = .{ .x = 2 }, .dst = 4 } },
            };

            var mi = try ia.Machine.init(gpa, &atoms);
            defer mi.deinit();
            mi.regs[1] = FinalTerms.int(&mi.ctx, va);
            mi.regs[2] = FinalTerms.int(&mi.ctx, vb);
            try ia.execInstr(&mi, ins);

            var mn = try ia.Machine.init(gpa, &atoms);
            defer mn.deinit();
            mn.regs[1] = FinalTerms.int(&mn.ctx, va);
            mn.regs[2] = FinalTerms.int(&mn.ctx, vb);
            var one = try compileOne(gpa, ins);
            defer one.c.deinit(gpa);
            const rc = one.f(&mn); // ← REAL native execution
            if (rc != 0) {
                std.debug.print("unexpected fallback kind={s} va={d} vb={d}\n", .{ @tagName(kind), va, vb });
                return error.UnexpectedFallback;
            }
            // bit-identical result word + identical reduction charge
            try testing.expectEqual(mi.regs[4], mn.regs[4]);
            try testing.expectEqual(mi.reductions, mn.reductions);
        }
    }
}

test "HOMOMORPHISM: native add FALLS BACK on non-small / overflow (machine untouched)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    const ins = ia.CInstr{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 2 }, .dst = 4 } };
    var one = try compileOne(gpa, ins);
    defer one.c.deinit(gpa);

    // Case A: a non-number operand (nil in x1) ⇒ the tag guard must fail.
    {
        var mn = try ia.Machine.init(gpa, &atoms);
        defer mn.deinit();
        mn.regs[1] = FinalTerms.nil(&mn.ctx);
        mn.regs[2] = FinalTerms.int(&mn.ctx, 5);
        const dst_before = mn.regs[4];
        const reds_before = mn.reductions;
        const rc = one.f(&mn);
        try testing.expect(rc != 0); // fallback requested
        try testing.expectEqual(dst_before, mn.regs[4]); // machine untouched
        try testing.expectEqual(reds_before, mn.reductions);
    }
    // Case B: small operands whose SUM overflows the small range ⇒ range guard fails.
    {
        var mn = try ia.Machine.init(gpa, &atoms);
        defer mn.deinit();
        const big: i64 = (1 << 59) - 1; // max small
        mn.regs[1] = FinalTerms.int(&mn.ctx, big);
        mn.regs[2] = FinalTerms.int(&mn.ctx, big); // sum = 2^60-2, out of small range
        const reds_before = mn.reductions;
        const rc = one.f(&mn);
        try testing.expect(rc != 0);
        try testing.expectEqual(reds_before, mn.reductions);
    }
}

// ===========================================================================
// jit-branches: block-JIT unit laws (the L2/L3 differential + the counted loop
// run natively live in dispatch.zig; these prove the NATIVE branch transfers
// and fixups directly, without the interpreter driver).
// ===========================================================================

test "FIXUP SOUNDNESS: a native FORWARD jump skips the intervening block" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // pc0 move x0<-5 ; pc1 jump 3 ; pc2 move x0<-99 (must be SKIPPED) ; pc3 move x1<-7
    const prog = [_]ia.CInstr{
        .{ .move = .{ .src = .{ .imm = 5 }, .dst = 0 } },
        .{ .jump = .{ .to = 3 } },
        .{ .move = .{ .src = .{ .imm = 99 }, .dst = 0 } },
        .{ .move = .{ .src = .{ .imm = 7 }, .dst = 1 } },
    };
    var blk = try compileBlock(gpa, prog[0..]);
    defer blk.deinit(gpa);
    for (0..prog.len) |k| try testing.expect(blk.entries[k] != null); // all covered

    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    const rc = blk.entries[0].?(&m, 100); // one native entry runs the whole region
    try testing.expectEqual(@as(u64, 1), rc); // FALLBACK at the tail (pc == len)
    try testing.expectEqual(@as(usize, prog.len), m.pc);
    try testing.expectEqual(FinalTerms.int(&m.ctx, 5), m.regs[0]); // pc2 was skipped
    try testing.expectEqual(FinalTerms.int(&m.ctx, 7), m.regs[1]);
    try testing.expectEqual(@as(u64, 3), m.instrs); // move, jump, move — 3 ops retired
    try testing.expectEqual(@as(u64, 0), m.reductions); // R2b: all straight-line / forward branch ⇒ 0 per-call reductions
}

test "FIXUP SOUNDNESS: a native BACKWARD branch + guard runs a counted loop natively" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // sum: while (x0 >= 1) { x1 += x0; x0 -= 1 }  — a pure native loop (no recursion).
    //   pc0 cmp_test .ge x0,1 else END(4)   (forward branch → tail)
    //   pc1 add x1,x1,x0
    //   pc2 sub x0,x0,1
    //   pc3 jump 0                          (backward branch)
    const prog = [_]ia.CInstr{
        .{ .cmp_test = .{ .op = .ge, .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .else_to = 4 } },
        .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 0 }, .dst = 1 } },
        .{ .sub = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } },
        .{ .jump = .{ .to = 0 } },
    };
    var blk = try compileBlock(gpa, prog[0..]);
    defer blk.deinit(gpa);
    for (0..prog.len) |k| try testing.expect(blk.entries[k] != null);

    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    m.regs[0] = FinalTerms.int(&m.ctx, 20); // N = 20
    m.regs[1] = FinalTerms.int(&m.ctx, 0); //  Acc = 0
    // Big budget: the loop runs entirely in ONE native entry until the guard fails
    // (x0 reaches 0) → forward branch to the tail (pc==len) → FALLBACK.
    const rc = blk.entries[0].?(&m, 100000);
    try testing.expectEqual(@as(u64, 1), rc);
    try testing.expectEqual(@as(usize, prog.len), m.pc); // guard jumped to END/tail
    try testing.expectEqual(FinalTerms.int(&m.ctx, 210), m.regs[1]); // 20+19+…+1 = 210
    try testing.expectEqual(FinalTerms.int(&m.ctx, 0), m.regs[0]);
}

// ===========================================================================
// jit-widen-coverage: the NON-ALLOCATING heap-reading tier's unit laws. The
// whole-corpus differential (native ≡ threaded over list/tuple/type-test-heavy
// programs, with reductions) lives in dispatch.zig; these prove the per-op
// homomorphism 𝒯(op) ≡ stepOne(op) directly and the GROUND constants.
// ===========================================================================

test "GROUND: jit-widen tag/subtag constants decode real FinalTerms values" {
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    // A cons has primary tag LIST; a tuple/boxed value has tag BOXED with a
    // TUPLE subtag in its header word; an atom has the 6-bit atom suffix; nil is
    // NIL_WORD; a small has the small suffix and is NOT a cons/boxed/atom.
    const c = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 1), FinalTerms.nil(&ctx));
    const t = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 1), FinalTerms.int(&ctx, 2) });
    const a = FinalTerms.atom(&ctx, 3);
    const nl = FinalTerms.nil(&ctx);
    const s = FinalTerms.int(&ctx, 42);

    try testing.expectEqual(TAG_LIST, c & TAG_MASK);
    try testing.expectEqual(TAG_BOXED, t & TAG_MASK);
    try testing.expectEqual(ATOM_SUFFIX, a & IMM_MASK6);
    try testing.expectEqual(NIL_WORD, nl);
    try testing.expectEqual(SMALL_SUFFIX, s & SMALL_SUFFIX);
    try testing.expect(c & TAG_MASK != TAG_BOXED and s & TAG_MASK != TAG_LIST);
    // the tuple's header subtag (in place) is SUBTAG_TUPLE (0)
    const header = ctx.words.items[@intCast(t >> 2)];
    try testing.expectEqual(SUBTAG_TUPLE_INPLACE, header & SUBTAG_FIELD);
}

// Compile a whole-program block and run it from pc 0 with `budget`. Programs
// here are all-covered until the trailing tail block, so ONE native entry runs
// the region to completion (returns FALLBACK at the tail, pc == len).
fn runWholeBlock(gpa: std.mem.Allocator, m: *ia.Machine, prog: ia.Program, budget: u64) !u64 {
    var blk = try compileBlock(gpa, prog);
    defer blk.deinit(gpa);
    for (0..prog.len) |k| try testing.expect(blk.entries[k] != null); // all covered
    return blk.entries[0].?(m, budget);
}

test "HOMOMORPHISM: native get_list ≡ interpreter (head/tail read, no allocation)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    const prog = [_]ia.CInstr{.{ .get_list = .{ .src = .{ .x = 0 }, .hd = .{ .x = 1 }, .tl = .{ .x = 2 } } }};

    // reference interpreter
    var mi = try ia.Machine.init(gpa, &atoms);
    defer mi.deinit();
    mi.regs[0] = try FinalTerms.cons(&mi.ctx, FinalTerms.int(&mi.ctx, 7), FinalTerms.int(&mi.ctx, 9));
    try ia.run(&mi, prog[0..], 1);

    // native
    var mn = try ia.Machine.init(gpa, &atoms);
    defer mn.deinit();
    mn.regs[0] = try FinalTerms.cons(&mn.ctx, FinalTerms.int(&mn.ctx, 7), FinalTerms.int(&mn.ctx, 9));
    const rc = try runWholeBlock(gpa, &mn, prog[0..], 10);
    try testing.expectEqual(@as(u64, 1), rc); // FALLBACK at the tail
    try testing.expectEqual(mi.regs[1], mn.regs[1]); // head
    try testing.expectEqual(mi.regs[2], mn.regs[2]); // tail
    try testing.expectEqual(mi.reductions, mn.reductions);
    try testing.expectEqual(FinalTerms.int(&mn.ctx, 7), mn.regs[1]);
    try testing.expectEqual(FinalTerms.int(&mn.ctx, 9), mn.regs[2]);
}

test "HOMOMORPHISM: native get_list FALLS BACK on a non-cons (machine untouched)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    const prog = [_]ia.CInstr{.{ .get_list = .{ .src = .{ .x = 0 }, .hd = .{ .x = 1 }, .tl = .{ .x = 2 } } }};

    var blk = try compileBlock(gpa, prog[0..]);
    defer blk.deinit(gpa);

    var mn = try ia.Machine.init(gpa, &atoms);
    defer mn.deinit();
    mn.regs[0] = FinalTerms.int(&mn.ctx, 5); // a small — NOT a cons
    const r1 = mn.regs[1];
    const r2 = mn.regs[2];
    const rc = blk.entries[0].?(&mn, 10);
    try testing.expect(rc != 0); // fallback requested (interpreter handles the non-cons)
    try testing.expectEqual(@as(usize, 0), mn.pc); // pc parked at the op
    try testing.expectEqual(@as(u64, 0), mn.reductions); // no charge on fallback
    try testing.expectEqual(r1, mn.regs[1]); // destinations untouched
    try testing.expectEqual(r2, mn.regs[2]);
}

test "HOMOMORPHISM: native put_list ≡ interpreter (region-bump cons alloc, fast path)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    const prog1 = [_]ia.CInstr{.{ .put_list = .{ .h = .{ .x = 0 }, .t = .{ .x = 1 }, .dst = 2 } }};

    var mi = try ia.Machine.init(gpa, &atoms);
    defer mi.deinit();
    mi.regs[0] = FinalTerms.int(&mi.ctx, 7);
    mi.regs[1] = FinalTerms.nil(&mi.ctx);
    try ia.run(&mi, prog1[0..], 1);

    var mn = try ia.Machine.init(gpa, &atoms);
    defer mn.deinit();
    mn.regs[0] = FinalTerms.int(&mn.ctx, 7);
    mn.regs[1] = FinalTerms.nil(&mn.ctx);
    const heap_n0 = mn.ctx.words.items.len;
    const rc = try runWholeBlock(gpa, &mn, prog1[0..], 10);
    try testing.expectEqual(@as(u64, 1), rc); // FALLBACK at the tail (the alloc ran natively)
    try testing.expectEqual(mi.regs[2], mn.regs[2]); // same cons (base<<2)|TAG_LIST
    try testing.expectEqual(heap_n0 + 2, mn.ctx.words.items.len); // region grew by EXACTLY 2
    try testing.expectEqual(mi.reductions, mn.reductions);
    const base = mn.regs[2] >> 2;
    try testing.expectEqual(FinalTerms.int(&mn.ctx, 7), mn.ctx.words.items[base]); // head
    try testing.expectEqual(FinalTerms.nil(&mn.ctx), mn.ctx.words.items[base + 1]); // tail

    // NON-OVERLAP: two conses; the 2nd must NOT clobber the 1st's tail (a len-bump
    // of 1 instead of 2 would overlap them). x2=[1]; x3=[2|x2].
    const prog2 = [_]ia.CInstr{
        .{ .put_list = .{ .h = .{ .imm = 1 }, .t = .nil, .dst = 2 } },
        .{ .put_list = .{ .h = .{ .imm = 2 }, .t = .{ .x = 2 }, .dst = 3 } },
    };
    var mi2 = try ia.Machine.init(gpa, &atoms);
    defer mi2.deinit();
    try ia.run(&mi2, prog2[0..], 2);
    var mn2 = try ia.Machine.init(gpa, &atoms);
    defer mn2.deinit();
    _ = try runWholeBlock(gpa, &mn2, prog2[0..], 10);
    try testing.expectEqual(mi2.regs[2], mn2.regs[2]); // [1] intact
    try testing.expectEqual(mi2.regs[3], mn2.regs[3]); // [2|[1]] intact
    try testing.expectEqualSlices(u64, mi2.ctx.words.items, mn2.ctx.words.items); // heaps identical

    // GROW SAFE-POINT: shrink the region to ZERO spare (cap == len, all VALID
    // data) so `len+2 > cap` and the fast path MUST decline. The cap guard is
    // still what protects the buffer — break it and native writes PAST the end
    // right here — but what happens AFTER the guard changed with
    // gap-jit-alloc-safepoint-tier: the grow used to LEAVE native code, and now
    // it calls the safe-point, which runs the op through the interpreter and
    // returns to native. So this arm no longer asserts "region untouched"; it
    // asserts the strictly stronger property that the op COMPLETED and the
    // result is identical to a pure interpreter run from the same start.
    var mg = try ia.Machine.init(gpa, &atoms);
    defer mg.deinit();
    mg.regs[0] = FinalTerms.int(&mg.ctx, 7);
    mg.regs[1] = FinalTerms.nil(&mg.ctx);
    mg.ctx.words.shrinkAndFree(gpa, mg.ctx.words.items.len); // cap := len, ZERO spare
    const len_full = mg.ctx.words.items.len;
    try testing.expectEqual(mg.ctx.words.capacity, len_full); // no room for even one word
    _ = try runWholeBlock(gpa, &mg, prog1[0..], 10);
    try testing.expectEqual(@as(usize, 1), mg.pc); // the op RAN — native did not bail at it
    try testing.expect(mg.ctx.words.items.len >= len_full + 2); // the interpreter grew it
    const baseg = mg.regs[2] >> 2;
    try testing.expectEqual(FinalTerms.int(&mg.ctx, 7), mg.ctx.words.items[baseg]);
    try testing.expectEqual(FinalTerms.nil(&mg.ctx), mg.ctx.words.items[baseg + 1]);

    // ...and the SAFE-POINT path denotes exactly what the interpreter denotes.
    // Comparing against a same-start pure interpreter run is what makes the
    // amended arm a differential rather than a weaker assertion.
    var mgi = try ia.Machine.init(gpa, &atoms);
    defer mgi.deinit();
    mgi.regs[0] = FinalTerms.int(&mgi.ctx, 7);
    mgi.regs[1] = FinalTerms.nil(&mgi.ctx);
    mgi.ctx.words.shrinkAndFree(gpa, mgi.ctx.words.items.len);
    try ia.run(&mgi, prog1[0..], 1);
    try testing.expectEqual(mgi.regs[2], mg.regs[2]);
    try testing.expectEqualSlices(u64, mgi.ctx.words.items, mg.ctx.words.items);
    try testing.expectEqual(mgi.instrs, mg.instrs); // charged EXACTLY once, not twice
}

test "HOMOMORPHISM: native put_tuple2 ≡ interpreter (region-bump tuple alloc; fast path, non-overlap, grow→fallback)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    // {x0, 8, []}  — a 3-tuple: header + 3 element words.
    const prog1 = [_]ia.CInstr{.{ .put_tuple2 = .{ .dst = .{ .x = 1 }, .elems = &.{ .{ .x = 0 }, .{ .imm = 8 }, .nil } } }};

    var mi = try ia.Machine.init(gpa, &atoms);
    defer mi.deinit();
    mi.regs[0] = FinalTerms.int(&mi.ctx, 7);
    try ia.run(&mi, prog1[0..], 1);

    var mn = try ia.Machine.init(gpa, &atoms);
    defer mn.deinit();
    mn.regs[0] = FinalTerms.int(&mn.ctx, 7);
    const heap_n0 = mn.ctx.words.items.len;
    const rc = try runWholeBlock(gpa, &mn, prog1[0..], 10);
    try testing.expectEqual(@as(u64, 1), rc);
    try testing.expectEqual(mi.regs[1], mn.regs[1]); // same tuple (base<<2)|TAG_BOXED
    try testing.expectEqual(heap_n0 + 4, mn.ctx.words.items.len); // header + 3 elems
    try testing.expectEqual(mi.reductions, mn.reductions);
    const base = mn.regs[1] >> 2;
    try testing.expectEqual(@as(u64, 3) << 7, mn.ctx.words.items[base]); // header, arity 3
    try testing.expectEqual(FinalTerms.int(&mn.ctx, 7), mn.ctx.words.items[base + 1]);
    try testing.expectEqual(FinalTerms.int(&mn.ctx, 8), mn.ctx.words.items[base + 2]);
    try testing.expectEqual(FinalTerms.nil(&mn.ctx), mn.ctx.words.items[base + 3]);

    // NON-OVERLAP: two tuples; the 2nd must not clobber the 1st (bump == 1+N, not less).
    const prog2 = [_]ia.CInstr{
        .{ .put_tuple2 = .{ .dst = .{ .x = 0 }, .elems = &.{ .{ .imm = 1 }, .{ .imm = 2 } } } }, // {1,2}
        .{ .put_tuple2 = .{ .dst = .{ .x = 1 }, .elems = &.{ .{ .x = 0 }, .{ .imm = 3 } } } }, //   {{1,2},3}
    };
    var mi2 = try ia.Machine.init(gpa, &atoms);
    defer mi2.deinit();
    try ia.run(&mi2, prog2[0..], 2);
    var mn2 = try ia.Machine.init(gpa, &atoms);
    defer mn2.deinit();
    _ = try runWholeBlock(gpa, &mn2, prog2[0..], 10);
    try testing.expectEqual(mi2.regs[0], mn2.regs[0]);
    try testing.expectEqual(mi2.regs[1], mn2.regs[1]);
    try testing.expectEqualSlices(u64, mi2.ctx.words.items, mn2.ctx.words.items);

    // GROW SAFE-POINT: shrink to zero spare so the fast path must decline. Since
    // gap-jit-alloc-safepoint-tier the grow no longer LEAVES native code — it
    // calls the safe-point, which grows through the interpreter and returns. So
    // the op completes in one native run, and the amended assertion is the
    // differential against a pure interpreter run rather than "untouched".
    var mg = try ia.Machine.init(gpa, &atoms);
    defer mg.deinit();
    mg.regs[0] = FinalTerms.int(&mg.ctx, 7);
    mg.ctx.words.shrinkAndFree(gpa, mg.ctx.words.items.len);
    const len_full = mg.ctx.words.items.len;
    _ = try runWholeBlock(gpa, &mg, prog1[0..], 10);
    try testing.expectEqual(@as(usize, 1), mg.pc); // the op RAN — native did not bail
    try testing.expect(mg.ctx.words.items.len >= len_full + 4);

    var mgi = try ia.Machine.init(gpa, &atoms);
    defer mgi.deinit();
    mgi.regs[0] = FinalTerms.int(&mgi.ctx, 7);
    mgi.ctx.words.shrinkAndFree(gpa, mgi.ctx.words.items.len);
    try ia.run(&mgi, prog1[0..], 1);
    try testing.expectEqual(mgi.regs[1], mg.regs[1]);
    try testing.expectEqualSlices(u64, mgi.ctx.words.items, mg.ctx.words.items);
    try testing.expectEqual(mgi.instrs, mg.instrs); // charged exactly once
}

test "HOMOMORPHISM: native get_tuple_element ≡ interpreter (every index, no allocation)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    for (0..3) |idx| {
        const prog = [_]ia.CInstr{.{ .get_tuple_elem = .{ .src = .{ .x = 0 }, .index = @intCast(idx), .dst = .{ .x = 1 } } }};

        var mi = try ia.Machine.init(gpa, &atoms);
        defer mi.deinit();
        mi.regs[0] = try FinalTerms.tuple(&mi.ctx, &.{ FinalTerms.int(&mi.ctx, 10), FinalTerms.int(&mi.ctx, 20), FinalTerms.int(&mi.ctx, 30) });
        try ia.run(&mi, prog[0..], 1);

        var mn = try ia.Machine.init(gpa, &atoms);
        defer mn.deinit();
        mn.regs[0] = try FinalTerms.tuple(&mn.ctx, &.{ FinalTerms.int(&mn.ctx, 10), FinalTerms.int(&mn.ctx, 20), FinalTerms.int(&mn.ctx, 30) });
        const rc = try runWholeBlock(gpa, &mn, prog[0..], 10);
        try testing.expectEqual(@as(u64, 1), rc);
        try testing.expectEqual(mi.regs[1], mn.regs[1]);
        try testing.expectEqual(mi.reductions, mn.reductions);
        try testing.expectEqual(FinalTerms.int(&mn.ctx, @intCast(10 * (idx + 1))), mn.regs[1]);
    }
}

test "HOMOMORPHISM: native get_tuple_element FALLS BACK on a non-tuple (machine untouched)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    const prog = [_]ia.CInstr{.{ .get_tuple_elem = .{ .src = .{ .x = 0 }, .index = 0, .dst = .{ .x = 1 } } }};

    var blk = try compileBlock(gpa, prog[0..]);
    defer blk.deinit(gpa);

    // Case A: a non-boxed operand (small) — the tag guard falls back.
    {
        var mn = try ia.Machine.init(gpa, &atoms);
        defer mn.deinit();
        mn.regs[0] = FinalTerms.int(&mn.ctx, 5);
        const r1 = mn.regs[1];
        const rc = blk.entries[0].?(&mn, 10);
        try testing.expect(rc != 0);
        try testing.expectEqual(@as(u64, 0), mn.reductions);
        try testing.expectEqual(r1, mn.regs[1]);
    }
    // Case B: a boxed NON-tuple (a bignum) — the subtag guard falls back.
    {
        var mn = try ia.Machine.init(gpa, &atoms);
        defer mn.deinit();
        mn.regs[0] = try FinalTerms.intFromI128(&mn.ctx, (@as(i128, 1) << 70)); // bignum (boxed, subtag != TUPLE)
        const r1 = mn.regs[1];
        const rc = blk.entries[0].?(&mn, 10);
        try testing.expect(rc != 0);
        try testing.expectEqual(@as(u64, 0), mn.reductions);
        try testing.expectEqual(r1, mn.regs[1]);
    }
}

test "HOMOMORPHISM: native type-test guards ≡ interpreter (holds fall-through / fails to else_to)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // Build a term of each shape; run every covered guard over it and compare the
    // resulting pc + reductions + the marker register against ia.run. The program
    // is `[<guard> src else_to=2 ; move x30 <- 111]`: HOLDS ⇒ fall through to the
    // move (x30 := 111, reds 2), FAILS ⇒ jump else_to (== tail, x30 unchanged, reds 1).
    const TermKind = enum { cons, nil, tuple, atom, small, bignum };
    const Guard = union(enum) { is_cons, tt: ia.TypeTestKind };
    const guards = [_]Guard{
        .is_cons,
        .{ .tt = .list },
        .{ .tt = .atom },
        .{ .tt = .tuple },
        .{ .tt = .integer },
    };

    inline for (guards) |g| {
        for ([_]TermKind{ .cons, .nil, .tuple, .atom, .small, .bignum }) |tk| {
            const guard_ins: ia.CInstr = switch (g) {
                .is_cons => .{ .is_cons = .{ .src = .{ .x = 0 }, .else_to = 2 } },
                .tt => |k| .{ .type_test = .{ .kind = k, .src = .{ .x = 0 }, .else_to = 2 } },
            };
            const prog = [_]ia.CInstr{ guard_ins, .{ .move = .{ .src = .{ .imm = 111 }, .dst = 30 } } };

            const mkTerm = struct {
                fn f(ctx: *FinalTerms.Ctx, kind: TermKind) !FinalTerms.Term {
                    return switch (kind) {
                        .cons => try FinalTerms.cons(ctx, FinalTerms.int(ctx, 1), FinalTerms.nil(ctx)),
                        .nil => FinalTerms.nil(ctx),
                        .tuple => try FinalTerms.tuple(ctx, &.{FinalTerms.int(ctx, 1)}),
                        .atom => FinalTerms.atom(ctx, 3),
                        .small => FinalTerms.int(ctx, 42),
                        .bignum => try FinalTerms.intFromI128(ctx, (@as(i128, 1) << 70)),
                    };
                }
            }.f;

            var mi = try ia.Machine.init(gpa, &atoms);
            defer mi.deinit();
            mi.regs[0] = try mkTerm(&mi.ctx, tk);
            mi.regs[30] = FinalTerms.int(&mi.ctx, 0);
            try ia.run(&mi, prog[0..], 8);

            var mn = try ia.Machine.init(gpa, &atoms);
            defer mn.deinit();
            mn.regs[0] = try mkTerm(&mn.ctx, tk);
            mn.regs[30] = FinalTerms.int(&mn.ctx, 0);
            var blk = try compileBlock(gpa, prog[0..]);
            defer blk.deinit(gpa);
            try testing.expect(blk.entries[0] != null and blk.entries[1] != null);
            // Drive the mixed engine by hand (mirrors dispatch.runNativeBlock): a
            // native block runs until it yields at the tail (pc==len) or requests
            // a FALLBACK (is_integer defers a boxed bignum), in which case we run
            // the one uncovered op threaded and re-enter.
            var used: u64 = 0;
            while (mn.pc < prog.len and used < 8) {
                const before = mn.reductions;
                const rc = blk.entries[mn.pc].?(&mn, 8 - used);
                used += mn.reductions - before;
                if (rc == 1) {
                    if (mn.pc >= prog.len) break; // reached the tail
                    const ins = prog[mn.pc]; // FALLBACK: one threaded step
                    mn.pc += 1;
                    const b2 = mn.reductions;
                    try ia.execInstr(&mn, ins);
                    used += mn.reductions - b2;
                }
            }
            // native ≡ interpreter: same landing pc, reductions, and marker reg.
            try testing.expectEqual(mi.reductions, mn.reductions);
            try testing.expectEqual(mi.regs[30], mn.regs[30]);
        }
    }
}

// ===========================================================================
// jit-calls: the native CONTROL-TRANSFER tier's unit laws. The whole-corpus
// differential + a REAL recursive program running call/return native live in
// dispatch.zig (via runNativeBlock); these prove 𝒯(call)/𝒯(ret) ≡ stepOne
// directly and the two fallback guards (CP-stack-full call, empty-stack ret).
// ===========================================================================

test "HOMOMORPHISM: native call ≡ interpreter (pushes pc+1, jumps to callee) — CP-stack fast path" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    // pc0 call{to=1} ; pc1 halt x0   — one native entry runs the call, then the
    // callee (halt) is uncovered ⇒ FALLBACK at pc1 with the CP frame pushed.
    const prog = [_]ia.CInstr{ .{ .call = .{ .to = 1 } }, .{ .halt = .{ .src = .{ .x = 0 } } } };

    var blk = try compileBlock(gpa, prog[0..]);
    defer blk.deinit(gpa);
    try testing.expect(blk.entries[0] != null); // the call compiled NATIVE

    // reference interpreter (budget 1 = just the call)
    var mi = try ia.Machine.init(gpa, &atoms);
    defer mi.deinit();
    try ia.run(&mi, prog[0..], 1);

    // native: pre-grow the CP stack so the capacity guard PASSES (fast path).
    var mn = try ia.Machine.init(gpa, &atoms);
    defer mn.deinit();
    try mn.stack.ensureTotalCapacity(gpa, 8);
    const rc = blk.entries[0].?(&mn, 100);

    // The native call fired (fallback would leave reds 0 / empty stack / pc 0):
    try testing.expectEqual(@as(u64, 1), rc); // FALLBACK at pc1 (halt uncovered)
    try testing.expectEqual(@as(usize, 1), mn.pc); // jumped to callee (to==1)
    try testing.expectEqual(@as(usize, 1), mn.stack.items.len);
    try testing.expectEqual(@as(usize, 1), mn.stack.items[0]); // return pc = pc0+1
    try testing.expectEqual(@as(u64, 1), mn.reductions); // exactly one charge
    // native ≡ interpreter at the slice boundary
    try testing.expectEqual(mi.pc, mn.pc);
    try testing.expectEqual(mi.reductions, mn.reductions);
    try testing.expect(std.mem.eql(usize, mi.stack.items, mn.stack.items));
}

test "GUARD: native call FALLS BACK when the CP stack is full (would realloc) — machine untouched" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    const prog = [_]ia.CInstr{ .{ .call = .{ .to = 1 } }, .{ .halt = .{ .src = .{ .x = 0 } } } };

    var blk = try compileBlock(gpa, prog[0..]);
    defer blk.deinit(gpa);

    // CP stack at capacity 0 (empty, no spare slot) ⇒ a native push would need a
    // realloc ⇒ the guard must divert to the interpreter WITHOUT touching memory.
    var mn = try ia.Machine.init(gpa, &atoms);
    defer mn.deinit();
    try testing.expectEqual(@as(usize, 0), mn.stack.capacity);
    const rc = blk.entries[0].?(&mn, 100);
    try testing.expectEqual(@as(u64, 1), rc); // FALLBACK requested at the call
    try testing.expectEqual(@as(usize, 0), mn.pc); // parked at the call op
    try testing.expectEqual(@as(u64, 0), mn.reductions); // no charge on fallback
    try testing.expectEqual(@as(usize, 0), mn.stack.items.len); // stack untouched

    // A full-but-nonzero-capacity stack also falls back (len == capacity).
    var mn2 = try ia.Machine.init(gpa, &atoms);
    defer mn2.deinit();
    try mn2.stack.ensureTotalCapacity(gpa, 4);
    for (0..mn2.stack.capacity) |_| try mn2.stack.append(gpa, 0); // fill to capacity
    const cap_full = mn2.stack.items.len;
    const rc2 = blk.entries[0].?(&mn2, 100);
    try testing.expectEqual(@as(u64, 1), rc2);
    try testing.expectEqual(@as(usize, 0), mn2.pc);
    try testing.expectEqual(@as(u64, 0), mn2.reductions);
    try testing.expectEqual(cap_full, mn2.stack.items.len); // no push happened
}

test "HOMOMORPHISM: native ret ≡ interpreter (pops the CP → pc, YIELDs to redispatch)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    // pc0 call{to=2} ; pc1 halt x1 ; pc2 move x1<-42 ; pc3 ret
    //   call → push 1, pc=2 ; move x1=42 ; ret → pop 1, pc=1, YIELD.
    // All of pc0/pc2/pc3 are native, chained in one entry ⇒ a single entries[0]
    // call runs call+move+ret and returns YIELD with pc parked at the return addr.
    const prog = [_]ia.CInstr{
        .{ .call = .{ .to = 2 } },
        .{ .halt = .{ .src = .{ .x = 1 } } },
        .{ .move = .{ .src = .{ .imm = 42 }, .dst = 1 } },
        .ret,
    };
    var blk = try compileBlock(gpa, prog[0..]);
    defer blk.deinit(gpa);
    try testing.expect(blk.entries[0] != null and blk.entries[2] != null and blk.entries[3] != null);

    var mn = try ia.Machine.init(gpa, &atoms);
    defer mn.deinit();
    try mn.stack.ensureTotalCapacity(gpa, 8); // fast-path the call push
    const rc = blk.entries[0].?(&mn, 100);
    try testing.expectEqual(@as(u64, 0), rc); // ret YIELDs (target is a runtime pc)
    try testing.expectEqual(@as(usize, 1), mn.pc); // popped return address (pc0+1)
    try testing.expectEqual(@as(usize, 0), mn.stack.items.len); // CP frame popped
    try testing.expectEqual(FinalTerms.int(&mn.ctx, 42), mn.regs[1]);
    try testing.expectEqual(@as(u64, 3), mn.instrs); // call + move + ret — 3 ops retired
    try testing.expectEqual(@as(u64, 1), mn.reductions); // R2b: only the `call` is a per-call reduction

    // interpreter over the same prefix (budget 3: call, move, ret) agrees.
    var mi = try ia.Machine.init(gpa, &atoms);
    defer mi.deinit();
    try ia.run(&mi, prog[0..], 3);
    try testing.expectEqual(mi.pc, mn.pc);
    try testing.expectEqual(mi.reductions, mn.reductions);
    try testing.expectEqual(mi.regs[1], mn.regs[1]);
    try testing.expect(std.mem.eql(usize, mi.stack.items, mn.stack.items));
}

test "GUARD: native ret on an EMPTY CP stack FALLS BACK (the terminal halt is the interpreter's)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    const prog = [_]ia.CInstr{.ret};

    var blk = try compileBlock(gpa, prog[0..]);
    defer blk.deinit(gpa);
    try testing.expect(blk.entries[0] != null);

    var mn = try ia.Machine.init(gpa, &atoms);
    defer mn.deinit();
    try testing.expectEqual(@as(usize, 0), mn.stack.items.len); // empty CP stack
    const rc = blk.entries[0].?(&mn, 100);
    try testing.expectEqual(@as(u64, 1), rc); // FALLBACK: interpreter runs the halt path
    try testing.expectEqual(@as(usize, 0), mn.pc); // parked at the ret op
    try testing.expectEqual(@as(u64, 0), mn.reductions); // no charge on fallback
    try testing.expect(mn.status == .running); // native did NOT halt — the interpreter will
}

// ── gap-jit-attribution: the {P} epoch's measurement instrument ──────────────
//
// The only {P} datum in the tree is an end-to-end ratio (0.148x BeamAsm, Lane D
// refreshed). It says the JIT is 6.77x behind and NOTHING about where the 6.77x
// goes, so any codegen change would be optimizing a guessed cell — and a ~5%
// change cannot even be confirmed, because it sits below `--bench-beamasm`
// noise on a contended shared host. `attribute` is static: same program, same
// numbers, any machine. A codegen change becomes an exact instruction delta.
//
// Mutants: MUT-ATTR-1 (a block's cost read from the wrong boundary → the
// partition law reds), MUT-ATTR-2 (coverage forced true → the discrimination
// law reds on an uncovered op).
test "LAW gap-jit-attribution: static per-op cost PARTITIONS the emitted block region exactly, is deterministic, and discriminates covered codegen from an uncovered trampoline" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;

    // the counted loop from FIXUP SOUNDNESS: cmp_test / add / sub / jump — the
    // exact shape `--bench-beamasm` measures, so the attribution explains THAT
    // benchmark rather than a synthetic one.
    const loop = [_]ia.CInstr{
        .{ .cmp_test = .{ .op = .ge, .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .else_to = 4 } },
        .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 0 }, .dst = 1 } },
        .{ .sub = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } },
        .{ .jump = .{ .to = 0 } },
    };

    const cost = try attribute(gpa, loop[0..]);
    defer gpa.free(cost);
    try testing.expectEqual(loop.len, cost.len);

    // LAW PARTITION: per-op costs sum to the whole emitted region (minus the
    // trailing tail block, which belongs to no pc). Nothing is unattributed and
    // nothing is double-counted — without this the instrument could quietly
    // lose the very cost it exists to find.
    var e = Emit{ .gpa = gpa };
    defer e.deinit();
    for (loop[0..], 0..) |_, pc| try buildBlock(&e, &loop[pc], pc);
    var summed: usize = 0;
    for (cost) |c| summed += c.native_insts;
    try testing.expectEqual(e.code.items.len, summed);

    // LAW NON-EMPTY: every pc has a block. A zero-cost op would mean an
    // instruction that emits nothing, which the dispatcher could never enter.
    for (cost) |c| try testing.expect(c.native_insts > 0);

    // LAW MEM-PARTITION: the memory-operand axis partitions the region too — the
    // per-op counts sum to the `load`/`store` instructions actually emitted.
    // Without this the third metric could drift from the code it describes
    // exactly as the first two could.
    var summed_mem: usize = 0;
    for (cost) |c| summed_mem += c.mem_ops;
    var emitted_mem: usize = 0;
    for (e.code.items) |inst| {
        if (isMemOp(inst)) emitted_mem += 1;
    }
    try testing.expectEqual(emitted_mem, summed_mem);

    // LAW DETERMINISM: the instrument is a pure function of the program. This is
    // the property that makes it usable where the timing route is not.
    const again = try attribute(gpa, loop[0..]);
    defer gpa.free(again);
    for (cost, again) |a, b| {
        try testing.expectEqual(a.native_insts, b.native_insts);
        try testing.expectEqual(a.native_bytes, b.native_bytes);
        try testing.expectEqual(a.mem_ops, b.mem_ops);
        try testing.expectEqual(a.covered, b.covered);
    }

    // LAW COVERED-DISCRIMINATES: every op in this loop is natively covered, and
    // an op the block JIT does NOT cover is reported uncovered. Without both
    // directions the flag could be a constant and still pass.
    for (cost) |c| try testing.expect(c.covered);
    const uncovered = [_]ia.CInstr{.{ .halt = .{ .src = .{ .x = 0 } } }};
    const ucost = try attribute(gpa, uncovered[0..]);
    defer gpa.free(ucost);
    try testing.expect(!ucost[0].covered);

    // THE FINDING, as a checked fact rather than a claim in prose: the arith
    // block costs an order of magnitude more native instructions than the one
    // that does the arithmetic. The bound is deliberately loose — this pins the
    // SHAPE (a template JIT's per-op overhead dominates) without turning an
    // exact count into a brittle ratchet that a legitimate codegen change trips.
    const add_cost = cost[1].native_insts;
    try testing.expect(add_cost >= 10); // one useful instruction among many
    // RATCHET (gap-jit-mask-imm): the arith block cost may FALL, never rise.
    // This is what the instrument is for — a codegen change that regresses the
    // per-op cost now fails here instead of hiding inside benchmark noise. It
    // is deliberately an upper BOUND at the current measured value, not an
    // equality: an improvement should not have to edit its own guard.
    try testing.expect(add_cost <= 35);
    // ...and the SAME ratchet on BYTES, because this slice is the proof that the
    // two can move in opposite directions. Guarding only the instruction count
    // let MUT-MASKIMM-1 (always emit the imm32 form) survive: same instructions,
    // 15 more bytes per arith block. One metric is not the cost.
    try testing.expect(cost[1].native_bytes <= 189);
    // ...and on MEMORY OPERANDS (gap-jit-xreg-residency). This is the axis that
    // slice moved: 13 → 7 over the loop, while the instruction count did not
    // change AT ALL and bytes moved 4.8%. Ratcheting only the first two would
    // have made a 46% reduction in memory traffic invisible, and — worse — would
    // let a later change silently spill x0/x1 back to memory at no cost to any
    // guarded number. Two metrics were not the cost either.
    var mem_total: usize = 0;
    for (cost) |c| mem_total += c.mem_ops;
    try testing.expect(mem_total <= 7);
    // and the whole loop body is dominated by overhead, not work
    var body: usize = 0;
    for (cost) |c| body += c.native_insts;
    try testing.expect(body >= 4 * cost.len);
}

// ── gap-jit-instrs-resident: the EXIT-FLUSH verification pass ────────────────
//
// `m.instrs` no longer lives in memory during a native run — it is resident in
// a callee-saved register and written back by the ONE shared epilogue. That is
// correct only if EVERY way out of native code reaches that epilogue. There are
// exactly three, and a missed one loses instruction accounting SILENTLY: the
// program still computes the right answer, `m.instrs` is just wrong, and
// preemption drifts from OTP without anything crashing.
//
// So each exit is driven separately and the counter checked against the number
// of blocks actually retired. A whole-corpus differential would eventually
// notice, but it would not say WHICH exit leaked; this does.
//
// Mutants: MUT-RESID-1 (the epilogue's flush removed → every count reads 0),
// MUT-RESID-2 (a fall-through block loses its trailing jump → the prologue is
// re-entered, the push/pop pair unbalances, and the run faults — the original
// 0x0 segfault, now caught by a law instead of by a crash in an unrelated test).
test "LAW gap-jit-instrs-resident: EVERY native exit flushes the resident instruction counter (budget-yield, fallback, fall-off-end)" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    const mv = ia.CInstr{ .move = .{ .src = .{ .imm = 5 }, .dst = 0 } };

    // (1) BUDGET YIELD — three covered blocks, budget 2: two retire, then the
    //     budget check exits. The counter must survive that exit.
    {
        const prog = [_]ia.CInstr{ mv, mv, mv };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        const rc = blk.entries[0].?(&m, 2);
        try testing.expectEqual(@as(u64, @bitCast(RET_YIELD)), rc);
        try testing.expectEqual(@as(u64, 2), m.instrs); // flushed, not lost
    }

    // (2) FALLBACK — a covered block then an UNCOVERED one. The trampoline is a
    //     different exit from the budget tail and must flush too.
    {
        const prog = [_]ia.CInstr{ mv, .{ .halt = .{ .src = .{ .x = 0 } } } };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        const rc = blk.entries[0].?(&m, 100);
        try testing.expectEqual(@as(u64, @bitCast(RET_FALLBACK)), rc);
        try testing.expectEqual(@as(usize, 1), m.pc); // parked at the uncovered op
        try testing.expectEqual(@as(u64, 1), m.instrs); // the move was charged
    }

    // (3) FALL OFF THE END — the trailing tail at pc == len is reached by
    //     fall-through, the path that the layout bug broke.
    {
        const prog = [_]ia.CInstr{ mv, mv };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        const rc = blk.entries[0].?(&m, 100);
        try testing.expectEqual(@as(u64, @bitCast(RET_FALLBACK)), rc);
        try testing.expectEqual(@as(usize, prog.len), m.pc);
        try testing.expectEqual(@as(u64, 2), m.instrs);
    }

    // (4) RE-ENTRY ACCUMULATES. The driver calls a block, gets a yield, and
    //     calls again — each call pushes and pops once and the counter must
    //     carry ACROSS calls, since it is reloaded from memory at every outer
    //     entry. A prologue that failed to reload would reset the count here.
    {
        const prog = [_]ia.CInstr{ mv, mv, mv, mv };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        _ = blk.entries[0].?(&m, 2);
        try testing.expectEqual(@as(u64, 2), m.instrs);
        _ = blk.entries[m.pc].?(&m, 2); // resume where it yielded
        try testing.expectEqual(@as(u64, 4), m.instrs); // accumulated, not reset
    }
}

// ── gap-jit-xreg-residency: the X-REGISTER residency verification pass ───────
//
// `x0`/`x1` no longer live in `m.regs[]` during a native run — they are resident
// in r12/r13, read by `readX` and written by `writeX`, and written back by the
// ONE shared epilogue. Two things must hold, and neither is visible in a passing
// program that happens to stay inside native code:
//
//   FLUSH   every exit reaches the epilogue, so the threaded interpreter — which
//           reads and writes `m.regs[]` directly on the fallback path — never
//           sees a stale slot.
//   RELOAD  every OUTER entry re-reads both slots, so a native re-entry after a
//           threaded op resumes on the value the interpreter left, not the one
//           native last had. This is the asymmetric arm: a missing reload is
//           INVISIBLE to any single-entry run, because the first thing a covered
//           block does with a resident destination is overwrite it.
//
// The whole-corpus differential in dispatch.zig is the net (a stale X register
// changes the denotation), but it cannot say which of the two failed or where.
//
// Mutants, with the arm each was OBSERVED to die on (not the one predicted):
//   MUT-XRES-1  drop the epilogue's x0 flush          → arm 1, + 37 corpus tests
//   MUT-XRES-2  `writeX` always stores to memory      → arm 1, + 37 corpus tests
//               (predicted arm 5; arm 1 fires first because the epilogue's flush
//               overwrites the memory store with the never-updated register —
//               the two copies diverge one step earlier than expected)
//   MUT-XRES-3  omit the outer entry's reload         → arm 4 ONLY; arms 1-3 ran
//               and PASSED first, and no corpus test caught it. That asymmetry
//               is the whole reason arm 4 exists: a missing reload is invisible
//               to every run that does not read a resident register ACROSS a
//               re-entry, and the corpus differential never happened to.
test "LAW gap-jit-xreg-residency: resident x0/x1 FLUSH at every native exit and RELOAD at every entry, and route per-register against non-resident neighbours" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // The residency set must be non-empty for this law to be testing anything —
    // an empty XRES would make every arm below pass vacuously.
    try testing.expect(XRES.len >= 2);

    // (1) FLUSH on BUDGET YIELD — write both resident registers, then exit
    //     through the budget gate. Both slots must hold the written values.
    {
        const prog = [_]ia.CInstr{
            .{ .move = .{ .src = .{ .imm = 11 }, .dst = 0 } },
            .{ .move = .{ .src = .{ .imm = 22 }, .dst = 1 } },
            .{ .move = .{ .src = .{ .imm = 33 }, .dst = 0 } },
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        const rc = blk.entries[0].?(&m, 2); // two retire, then yield
        try testing.expectEqual(@as(u64, @bitCast(RET_YIELD)), rc);
        try testing.expectEqual(FinalTerms.int(&m.ctx, 11), m.regs[0]);
        try testing.expectEqual(FinalTerms.int(&m.ctx, 22), m.regs[1]);
    }

    // (2) FLUSH on FALLBACK — the trampoline is a different exit, and it is the
    //     one that matters most: the interpreter is about to read these slots.
    {
        const prog = [_]ia.CInstr{
            .{ .move = .{ .src = .{ .imm = 44 }, .dst = 1 } },
            .{ .halt = .{ .src = .{ .x = 0 } } }, // uncovered ⇒ trampoline
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        const rc = blk.entries[0].?(&m, 100);
        try testing.expectEqual(@as(u64, @bitCast(RET_FALLBACK)), rc);
        try testing.expectEqual(FinalTerms.int(&m.ctx, 44), m.regs[1]);
    }

    // (3) FLUSH on FALL-OFF-THE-END — reached by fall-through, the path the
    //     dual-entry layout bug broke.
    {
        const prog = [_]ia.CInstr{
            .{ .move = .{ .src = .{ .imm = 55 }, .dst = 0 } },
            .{ .move = .{ .src = .{ .x = 0 }, .dst = 1 } },
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        _ = blk.entries[0].?(&m, 100);
        try testing.expectEqual(FinalTerms.int(&m.ctx, 55), m.regs[0]);
        try testing.expectEqual(FinalTerms.int(&m.ctx, 55), m.regs[1]); // read via r12
    }

    // (4) RELOAD ACROSS RE-ENTRY — the arm that catches a missing reload, and
    //     the only one that does. Between the two native calls we write
    //     `m.regs[0]` directly, standing in for exactly what the driver's
    //     threaded fallback does. The second entry must pick up THAT value; a
    //     prologue without the reload resumes on whatever r12 happens to hold
    //     (the Zig caller's, since the epilogue popped ours back).
    {
        const prog = [_]ia.CInstr{
            .{ .move = .{ .src = .{ .imm = 1 }, .dst = 7 } }, // non-resident dst
            .{ .move = .{ .src = .{ .x = 0 }, .dst = 1 } }, // reads resident x0
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        const rc = blk.entries[0].?(&m, 1); // retire pc0, yield at pc1
        try testing.expectEqual(@as(u64, @bitCast(RET_YIELD)), rc);
        try testing.expectEqual(@as(usize, 1), m.pc);

        const injected = FinalTerms.int(&m.ctx, 99);
        m.regs[0] = injected; // ← the interpreter's write, between two entries
        _ = blk.entries[m.pc].?(&m, 10);
        try testing.expectEqual(injected, m.regs[1]);
        try testing.expectEqual(injected, m.regs[0]); // and flushed back unchanged
    }

    // (5) PER-REGISTER ROUTING — a block mixing resident x0/x1 with non-resident
    //     x2 proves `readX`/`writeX` dispatch on the register rather than
    //     uniformly. Both directions are exercised: resident→memory (pc0) and
    //     memory→resident (pc1).
    {
        const prog = [_]ia.CInstr{
            .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .x = 1 }, .dst = 2 } }, // res+res → mem
            .{ .add = .{ .a = .{ .x = 2 }, .b = .{ .x = 2 }, .dst = 0 } }, // mem+mem → res
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 3);
        m.regs[1] = FinalTerms.int(&m.ctx, 4);
        _ = blk.entries[0].?(&m, 10);
        try testing.expectEqual(FinalTerms.int(&m.ctx, 7), m.regs[2]);
        try testing.expectEqual(FinalTerms.int(&m.ctx, 14), m.regs[0]);
        try testing.expectEqual(FinalTerms.int(&m.ctx, 4), m.regs[1]); // untouched
    }

    // (6) STRUCTURAL: the arith block over resident operands addresses the
    //     register file ZERO times. `mem_ops` counts 2 for that block and both
    //     are `m.pc` writes on COLD exit paths (the budget-yield tail and the
    //     fallback trampoline) — so the statement "the hot path is memory-free"
    //     is a checked fact here rather than a claim in the commit message.
    {
        var e = Emit{ .gpa = gpa };
        defer e.deinit();
        const one = ia.CInstr{ .add = .{ .a = .{ .x = 0 }, .b = .{ .x = 1 }, .dst = 1 } };
        try buildBlock(&e, &one, 0);
        var regfile_traffic: usize = 0;
        for (e.code.items) |inst| {
            const mem: ?jit_asm.Inst = if (isMemOp(inst)) inst else null;
            if (mem) |mi| {
                const op = switch (mi) {
                    .load, .store => |o| o,
                    else => unreachable,
                };
                if (op.base == M and op.disp != PC_OFF) regfile_traffic += 1;
            }
        }
        try testing.expectEqual(@as(usize, 0), regfile_traffic);
    }
}

// ── gap-jit-cons-read-tier: get_hd / get_tl join the native tier ─────────────
//
// SELECTED BY MEASUREMENT, not by reading the emitter. The dynamic profile
// (`LAW gap-jit-fallback-attribution`) over the alloc+traversal workload
// reported coverage 0.528 with **2352 of 2362 fallback instructions (99.6%) in
// `get_hd`/`get_tl`** — sixteen sites, 147 each — the other 10 being `put_list`
// grow-safepoints that are correct by design. Four codegen increments had gone
// into the covered subset while the covered subset was barely half the work.
//
// The fix is small because these ops are not new: `get_list` IS `listHead` then
// `listTail`, and `get_hd`/`get_tl` are each one of those halves on the same
// term. One emitter now serves all three, so the guard, the address computation
// and the fallback contract are shared rather than re-derived.
//
// Mutants: MUT-CONS-1 (`get_tl` reads disp 0 instead of 8 → returns the head; the
// differential reds), MUT-CONS-2 (drop the `(w&3)==LIST` guard on the half-reads
// → a non-cons is dereferenced natively instead of falling back, so the
// interpreter never gets to raise; the non-cons arm reds).
test "LAW gap-jit-cons-read-tier: native get_hd/get_tl ≡ interpreter, incl. non-cons fallback and destination aliasing" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // (1) DIFFERENTIAL over a real spine walk. get_hd/get_tl/add/jump — every op
    //     native — folded against the interpreter running the SAME program.
    {
        const prog = [_]ia.CInstr{
            .{ .get_hd = .{ .src = .{ .x = 0 }, .dst = .{ .x = 2 } } },
            .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 2 }, .dst = 1 } },
            .{ .get_tl = .{ .src = .{ .x = 0 }, .dst = .{ .x = 0 } } },
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);

        // native
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        try seedSpine(&m);
        // Pre-grow the frame so `alloc_y` takes its NATIVE path: with a zero-
        // capacity ystack it would hit the grow safepoint at pc 0 and nothing
        // after it would run natively, leaving this differential vacuous.
        _ = blk.entries[0].?(&m, 100);

        // interpreter reference, same seed
        var r = try ia.Machine.init(gpa, &atoms);
        defer r.deinit();
        try seedSpine(&r);
        try ia.run(&r, prog[0..], 100);

        try testing.expectEqual(r.regs[0], m.regs[0]); // tail advanced identically
        try testing.expectEqual(r.regs[1], m.regs[1]); // accumulated identically
        try testing.expectEqual(r.regs[2], m.regs[2]); // head read identically
        try testing.expectEqual(r.instrs, m.instrs); // and charged identically
    }

    // (2) COVERAGE — both ops really are native now. Without this the
    //     differential above would still pass with both falling back, which is
    //     exactly the state this slice exists to leave.
    {
        const prog = [_]ia.CInstr{
            .{ .get_hd = .{ .src = .{ .x = 0 }, .dst = .{ .x = 2 } } },
            .{ .get_tl = .{ .src = .{ .x = 0 }, .dst = .{ .x = 3 } } },
        };
        const cost = try attribute(gpa, prog[0..]);
        defer gpa.free(cost);
        try testing.expect(cost[0].covered);
        try testing.expect(cost[1].covered);
    }

    // (3) NON-CONS FALLS BACK — the guard is what keeps a native half-read from
    //     dereferencing a small as if it were a cons. The interpreter, not
    //     native code, decides what a `get_hd` of a non-list means.
    {
        const prog = [_]ia.CInstr{.{ .get_hd = .{ .src = .{ .x = 0 }, .dst = .{ .x = 2 } } }};
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 42); // a small, not a cons
        const rc = blk.entries[0].?(&m, 100);
        try testing.expectEqual(@as(u64, @bitCast(RET_FALLBACK)), rc);
        try testing.expectEqual(@as(usize, 0), m.pc); // parked ON the op
        try testing.expectEqual(@as(u64, 0), m.instrs); // uncharged — the re-run charges
    }

    // (4) ALIASING — `get_tl x0 -> x0` overwrites its own source. Both loads
    //     precede both stores, so the address is read before it is clobbered;
    //     and `get_list x0 -> y, y` must leave the TAIL, matching the
    //     interpreter's setDst(hd) then setDst(tl) order.
    {
        const prog = [_]ia.CInstr{
            .{ .get_list = .{ .src = .{ .x = 0 }, .hd = .{ .x = 1 }, .tl = .{ .x = 1 } } },
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        try seedSpine(&m);
        var r = try ia.Machine.init(gpa, &atoms);
        defer r.deinit();
        try seedSpine(&r);
        _ = blk.entries[0].?(&m, 10);
        try ia.run(&r, prog[0..], 10);
        try testing.expectEqual(r.regs[1], m.regs[1]); // the tail won, in both
    }
}

/// A 4-cell spine [1,2,3,4] in x0 and a zero accumulator in x1.
fn seedSpine(m: *ia.Machine) !void {
    var lst = FinalTerms.nil(&m.ctx);
    var v: i64 = 4;
    while (v >= 1) : (v -= 1) lst = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, v), lst);
    m.regs[0] = lst;
    m.regs[1] = FinalTerms.int(&m.ctx, 0);
}

// ── gap-jit-frame-tier: alloc_y / dealloc_y / move2 / y-destinations ─────────
//
// SELECTED BY MEASUREMENT on a REAL compiled module. Profiling `mylists.beam`
// (`LAW gap-jit-frame-tier COVERAGE`) ranked the fallback as move2 402,
// alloc_y 400, dealloc_y 400, bif_call 400, get_list-with-a-y-destination 200 —
// coverage 0.373. The preceding increment had been selected on a SYNTHETIC
// workload that has no stack frame at all, and so could not see any of this. A
// program with no `alloc_y` is not a program the BEAM compiler emits.
//
// The frame is `Machine.ystack`, and `yreg(i)` is `&items[len - 1 - i]` —
// frame-RELATIVE, so the address depends on a runtime length. Two consequences
// shape the codegen:
//   * every frame access carries a BOUNDS guard, because `yreg` panics on
//     `i >= len` and a native out-of-bounds read would be a silent corruption
//     where the interpreter gives a diagnosable panic;
//   * `alloc_y` GROWS the frame, so it guards capacity and yields the growth to
//     the interpreter — the same safe-point discipline as `put_list` on the heap
//     and `call` on the CP stack. Allocation never happens inside native code.
//
// Mutants: MUT-FRAME-1 (`emitYAddr` computes `len - i`, not `len - 1 - i` — the
// classic frame off-by-one, reading the neighbouring slot), MUT-FRAME-2
// (`dealloc_y` drops its `len >= n` guard, so an over-deallocation wraps the
// unsigned length instead of falling back), MUT-FRAME-3 (`alloc_y` skips
// nil-initialising the new slots, leaving whatever the last frame left there).
test "LAW gap-jit-frame-tier: native alloc_y/dealloc_y/move2 and y-register destinations ≡ interpreter, with bounds and capacity guards" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // (1) DIFFERENTIAL over a real frame lifecycle: allocate a frame, move a
    //     value THROUGH it (x → y → x), destructure a cons into a y slot, then
    //     drop the frame. Every op native; compared against `ia.run`.
    {
        const prog = [_]ia.CInstr{
            .{ .alloc_y = .{ .n = 3 } }, //                                       0
            .{ .move2 = .{ .src = .{ .imm = 77 }, .dst = .{ .y = 1 } } }, //      1  x→y
            .{ .move2 = .{ .src = .{ .y = 1 }, .dst = .{ .x = 5 } } }, //         2  y→x
            .{ .get_list = .{ .src = .{ .x = 0 }, .hd = .{ .y = 0 }, .tl = .{ .x = 0 } } }, // 3
            .{ .move2 = .{ .src = .{ .y = 0 }, .dst = .{ .x = 6 } } }, //         4
            .{ .dealloc_y = .{ .n = 3 } }, //                                     5
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);

        // every op must be natively covered, or the differential is vacuous
        const cost = try attribute(gpa, prog[0..]);
        defer gpa.free(cost);
        for (cost) |c| try testing.expect(c.covered);

        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        try seedSpine(&m);
        // Pre-grow the frame so `alloc_y` takes its NATIVE path: with a
        // zero-capacity ystack it hits the grow safepoint at pc 0 and NOTHING
        // after it runs natively, leaving this differential vacuous. (It did,
        // the first time — the run reported pc 0 / 0 instructions retired.)
        try m.ystack.ensureTotalCapacity(gpa, 8);
        _ = blk.entries[0].?(&m, 100);

        var r = try ia.Machine.init(gpa, &atoms);
        defer r.deinit();
        try seedSpine(&r);
        try ia.run(&r, prog[0..], 100);

        try testing.expectEqual(r.regs[5], m.regs[5]); // the value that went through the frame
        try testing.expectEqual(r.regs[6], m.regs[6]); // the head that landed in y0
        try testing.expectEqual(r.regs[0], m.regs[0]); // the tail
        try testing.expectEqual(r.ystack.items.len, m.ystack.items.len); // frame balanced
        try testing.expectEqual(r.instrs, m.instrs); // charged identically
    }

    // (2) NIL-INITIALISED — `alloc_y` must leave the new slots holding nil, not
    //     whatever the previous frame left. Allocate, write, drop, re-allocate,
    //     and read: the second frame must see nil.
    {
        const prog = [_]ia.CInstr{
            .{ .alloc_y = .{ .n = 2 } },
            .{ .move2 = .{ .src = .{ .imm = 99 }, .dst = .{ .y = 0 } } },
            .{ .dealloc_y = .{ .n = 2 } },
            .{ .alloc_y = .{ .n = 2 } },
            .{ .move2 = .{ .src = .{ .y = 0 }, .dst = .{ .x = 1 } } },
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        try m.ystack.ensureTotalCapacity(gpa, 8);
        _ = blk.entries[0].?(&m, 100);
        try testing.expectEqual(FinalTerms.nil(&m.ctx), m.regs[1]); // fresh, not 99
    }

    // (3) OUT-OF-FRAME READ FALLS BACK — `yreg` panics on i >= len, so native
    //     must divert rather than read past the frame. A one-slot frame with a
    //     y2 access is the case.
    {
        const prog = [_]ia.CInstr{
            .{ .alloc_y = .{ .n = 1 } },
            .{ .move2 = .{ .src = .{ .y = 2 }, .dst = .{ .x = 1 } } }, // out of frame
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        try m.ystack.ensureTotalCapacity(gpa, 8);
        const rc = blk.entries[0].?(&m, 100);
        try testing.expectEqual(@as(u64, @bitCast(RET_FALLBACK)), rc);
        try testing.expectEqual(@as(usize, 1), m.pc); // parked ON the bad access
        try testing.expectEqual(@as(u64, 1), m.instrs); // only the alloc_y charged
    }

    // (4) OVER-DEALLOCATION FALLS BACK — dropping more slots than the frame
    //     holds would wrap the unsigned length. The interpreter owns that error.
    {
        const prog = [_]ia.CInstr{
            .{ .alloc_y = .{ .n = 1 } },
            .{ .dealloc_y = .{ .n = 4 } },
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        try m.ystack.ensureTotalCapacity(gpa, 8);
        const rc = blk.entries[0].?(&m, 100);
        try testing.expectEqual(@as(u64, @bitCast(RET_FALLBACK)), rc);
        try testing.expectEqual(@as(usize, 1), m.pc);
        try testing.expectEqual(@as(usize, 1), m.ystack.items.len); // NOT wrapped
    }

    // (5) FRAME GROWTH IS A SAFE-POINT — an `alloc_y` beyond capacity is still
    //     the INTERPRETER's realloc (native code never allocates), but since
    //     gap-jit-alloc-safepoint-tier it is reached by a CALL rather than by
    //     leaving the native region. The amended assertions are that the op
    //     completed, was charged exactly once, and denotes what the interpreter
    //     denotes — all stronger than the "uncharged, re-run charges" contract
    //     they replace, which only ever said native had declined.
    {
        const prog = [_]ia.CInstr{.{ .alloc_y = .{ .n = 200 } }};
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        try testing.expect(m.ystack.capacity < 200); // precondition: it must grow
        _ = blk.entries[0].?(&m, 100);
        try testing.expectEqual(@as(usize, 1), m.pc); // the op RAN
        try testing.expectEqual(@as(u64, 1), m.instrs); // charged EXACTLY once
        try testing.expectEqual(@as(usize, 200), m.ystack.items.len);

        var r = try ia.Machine.init(gpa, &atoms);
        defer r.deinit();
        try ia.run(&r, prog[0..], 100);
        try testing.expectEqualSlices(u64, r.ystack.items, m.ystack.items);
        try testing.expectEqual(r.instrs, m.instrs);
    }

    // (6) `move2` WITH X-ONLY OPERANDS EMITS NO TAIL. The frame guard is what
    //     forces a fallback tail, so a move2 that cannot fail must not pay for
    //     one — this is the "pay only when you use it" claim, checked.
    {
        const plain = [_]ia.CInstr{.{ .move2 = .{ .src = .{ .imm = 1 }, .dst = .{ .x = 0 } } }};
        const framed = [_]ia.CInstr{.{ .move2 = .{ .src = .{ .y = 0 }, .dst = .{ .x = 0 } } }};
        const cp = try attribute(gpa, plain[0..]);
        defer gpa.free(cp);
        const cf = try attribute(gpa, framed[0..]);
        defer gpa.free(cf);
        try testing.expect(cp[0].native_insts < cf[0].native_insts);
        try testing.expectEqual(@as(usize, 1), cp[0].mem_ops); // only the yield tail's m.pc
    }
}

// ── gap-jit-bif-safepoint: calling a BIF without leaving native code ─────────
//
// SELECTED BY MEASUREMENT: `bif_call` was 400 fallback instructions on the real
// `mylists.beam` — 65% of everything still leaving native code after the frame
// tier. Nothing else was close.
//
// WHAT "NATIVE" HONESTLY MEANS HERE. The BIF body still runs as Zig, called
// through a `callconv(.c)` shim; that is what BeamAsm does too, and it is not
// the claim. The claim is that the DISPATCH stays native: before this, every
// BIF cost a full exit (flush, epilogue, return to the driver) and re-entry
// (prologue, reload) around one op. Now the block calls the shim inline and
// carries on. Coverage on the real program went 0.809 → 0.934, and the 213
// instructions still falling back are 205 deliberate GROW safepoints plus 8 at
// the driver's own entry/exit boundary.
//
// THE ABI IS THE HAZARD, NOT THE BIF. Three things bit or nearly bit:
//   * `rdi` is CALLER-saved and holds the pinned machine pointer. Passing it as
//     arg0 does not mean it survives. It did not, and the failure was a
//     segfault at a small address deep inside an unrelated scheduler test —
//     nowhere near this code. Both pinned registers are now saved across.
//   * a BIF writes `m.regs[]` and `m.instrs` directly, so residency must be
//     flushed before and reloaded after — the epilogue's discipline, inline.
//   * the shim CHARGES the instruction (through `execInstr`), so the block must
//     not charge again. Double-charging would drift preemption from the
//     interpreter on every BIF call, silently.
//
// Mutants: MUT-BIF-1 (skip the post-call reload → a BIF's write to x0 is
// overwritten by the stale resident copy), MUT-BIF-2 (charge in the block as
// well as the shim → `instrs` drifts from the interpreter), MUT-BIF-3 (treat
// every verdict as CONTINUE → a guard branch and an exception are both ignored
// and execution runs on past them).
test "LAW gap-jit-bif-safepoint: a native bif_call ≡ interpreter — result, charge, guard branch, exception — and resident registers survive the call" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    const add_bif = ia.BifRef{ .func = &@import("bifs/erlang.zig").add };

    // (1) COVERED — `bif_call` is native now. Without this arm every
    //     differential below would still pass with the op falling back, which
    //     is the state this slice exists to leave.
    {
        const prog = [_]ia.CInstr{.{ .bif_call = .{
            .bif = add_bif,
            .args = .{ .{ .x = 1 }, .{ .x = 2 }, .nil },
            .argc = 2,
            .dst = .{ .x = 3 },
            .else_to = null,
            .gc_live = null,
        } }};
        const cost = try attribute(gpa, prog[0..]);
        defer gpa.free(cost);
        try testing.expect(cost[0].covered);
    }

    // (2) DIFFERENTIAL + CHARGE — the value AND the instruction accounting must
    //     match `ia.run`. The charge arm is what MUT-BIF-2 dies on: the shim
    //     charges through execInstr, so a block that also charges would retire
    //     two instructions for one op and preemption would drift.
    {
        const prog = [_]ia.CInstr{
            .{ .bif_call = .{
                .bif = add_bif,
                .args = .{ .{ .x = 1 }, .{ .x = 2 }, .nil },
                .argc = 2,
                .dst = .{ .x = 3 },
                .else_to = null,
                .gc_live = null,
            } },
            .{ .move = .{ .src = .{ .x = 3 }, .dst = 4 } },
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);

        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[1] = FinalTerms.int(&m.ctx, 40);
        m.regs[2] = FinalTerms.int(&m.ctx, 2);
        _ = blk.entries[0].?(&m, 100);

        var r = try ia.Machine.init(gpa, &atoms);
        defer r.deinit();
        r.regs[1] = FinalTerms.int(&r.ctx, 40);
        r.regs[2] = FinalTerms.int(&r.ctx, 2);
        try ia.run(&r, prog[0..], 100);

        try testing.expectEqual(r.regs[3], m.regs[3]); // 42, computed by the BIF
        try testing.expectEqual(r.regs[4], m.regs[4]); // and read back natively
        try testing.expectEqual(r.instrs, m.instrs); // charged EXACTLY once each
        try testing.expectEqual(r.reductions, m.reductions);
    }

    // (3) RESIDENT REGISTERS SURVIVE — the BIF writes x0 (a RESIDENT register)
    //     through memory while the JIT holds it in r12. Flush-before /
    //     reload-after is the only thing that makes the following native read
    //     see the BIF's value instead of the stale register. MUT-BIF-1 dies here.
    {
        const prog = [_]ia.CInstr{
            .{
                .bif_call = .{
                    .bif = add_bif,
                    .args = .{ .{ .x = 1 }, .{ .x = 2 }, .nil },
                    .argc = 2,
                    .dst = .{ .x = 0 }, // ← RESIDENT destination
                    .else_to = null,
                    .gc_live = null,
                },
            },
            .{ .move = .{ .src = .{ .x = 0 }, .dst = 5 } }, // read it back
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 999); // the value that must NOT survive
        m.regs[1] = FinalTerms.int(&m.ctx, 40);
        m.regs[2] = FinalTerms.int(&m.ctx, 2);
        _ = blk.entries[0].?(&m, 100);
        try testing.expectEqual(FinalTerms.int(&m.ctx, 42), m.regs[0]);
        try testing.expectEqual(FinalTerms.int(&m.ctx, 42), m.regs[5]);
    }

    // (4) A GUARD THAT FAILS BRANCHES, and native must YIELD there rather than
    //     run on to pc+1. The shim detects it by comparing m.pc against pc+1 —
    //     the only signal a guard branch gives. MUT-BIF-3 dies here.
    {
        const prog = [_]ia.CInstr{
            .{
                .bif_call = .{
                    .bif = add_bif,
                    .args = .{ .{ .x = 1 }, .{ .x = 2 }, .nil },
                    .argc = 2,
                    .dst = .{ .x = 3 },
                    .else_to = 2, // GUARD context
                    .gc_live = null,
                },
            },
            .{ .move = .{ .src = .{ .imm = 7 }, .dst = 6 } }, // must NOT run
            .{ .move = .{ .src = .{ .imm = 8 }, .dst = 7 } }, // the else arm
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[1] = FinalTerms.atom(&m.ctx, try atoms.intern("not_a_number"));
        m.regs[2] = FinalTerms.int(&m.ctx, 2);
        const rc = blk.entries[0].?(&m, 100);
        try testing.expectEqual(@as(u64, @bitCast(RET_YIELD)), rc);
        try testing.expectEqual(@as(usize, 2), m.pc); // branched to else_to
        try testing.expect(m.status == .running); // a guard NEVER raises
    }

    // (5) A BODY-CONTEXT FAILURE RAISES, and native must hand that to the
    //     driver with the interpreter's exact status — not swallow it.
    {
        const prog = [_]ia.CInstr{
            .{
                .bif_call = .{
                    .bif = add_bif,
                    .args = .{ .{ .x = 1 }, .{ .x = 2 }, .nil },
                    .argc = 2,
                    .dst = .{ .x = 3 },
                    .else_to = null, // BODY context ⇒ crash
                    .gc_live = null,
                },
            },
            .{ .move = .{ .src = .{ .imm = 7 }, .dst = 6 } }, // must NOT run
        };
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[1] = FinalTerms.atom(&m.ctx, try atoms.intern("not_a_number"));
        m.regs[2] = FinalTerms.int(&m.ctx, 2);
        const before = m.regs[6];
        _ = blk.entries[0].?(&m, 100);
        try testing.expect(m.status != .running); // the interpreter's verdict stands
        try testing.expectEqual(before, m.regs[6]); // execution did not run on
    }
}

test "LAW gap-jit-alloc-safepoint-tier: a heap/frame GROW is a SAFE-POINT, not a native exit — allocating blocks ≡ interpreter across many reallocs, and native code calls NOTHING but the safepoint" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // The cons shape the REAL `mylists.beam` emits: `put_list dst=x0, h=y0,
    // t=x0` — a FRAME-SLOT head. Built explicitly because the operand shape is
    // the whole point: `moveSrcOk` rejected `.y`, so before this slice every one
    // of these went to the uncovered-op trampoline and the allocating block was
    // never even reached. A law written with an `.x` head would have passed
    // against the broken code.
    const CONSES: usize = 300; // ≫ the initial heap capacity ⇒ MANY reallocs
    var prog: std.ArrayList(ia.CInstr) = .empty;
    defer prog.deinit(gpa);
    try prog.append(gpa, .{ .alloc_y = .{ .n = 1 } });
    try prog.append(gpa, .{ .move2 = .{ .src = .{ .imm = 7 }, .dst = .{ .y = 0 } } });
    for (0..CONSES) |_|
        try prog.append(gpa, .{ .put_list = .{ .h = .{ .y = 0 }, .t = .{ .x = 0 }, .dst = 0 } });

    // (1) COVERED — the allocating op compiles to a real block. Without this arm
    //     every differential below would still pass with the op falling back,
    //     which is exactly the state this slice exists to leave.
    {
        const cost = try attribute(gpa, prog.items);
        defer gpa.free(cost);
        try testing.expect(cost[0].covered); // alloc_y
        try testing.expect(cost[2].covered); // put_list, frame-slot head
    }

    // (2) THE SLICE'S PROPERTY: the native block runs to the END. Each of the
    //     300 conses extends the heap and several of them force a realloc; every
    //     such grow used to return FALLBACK, hand one op to the driver, and
    //     re-enter through the prologue. A run that reaches the end of the
    //     program without ever returning FALLBACK is direct evidence the grows
    //     became safe-points. MUT-ALLOC-1 dies here.
    var blk = try compileBlock(gpa, prog.items);
    defer blk.deinit(gpa);

    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    m.regs[0] = ta.FinalTerms.nil(&m.ctx);
    //     NOTE the discriminator is `m.pc`, NOT the return code: falling off the
    //     END of the program legitimately returns FALLBACK (the trailing tail
    //     sets `m.pc = len`), so the return code cannot tell "finished" from
    //     "bailed at a grow". Where it STOPPED can: a grow-exit would leave
    //     `m.pc` at that `put_list`, not at the end.
    _ = blk.entries[0].?(&m, 10_000);
    try testing.expectEqual(prog.items.len, m.pc); // ran the WHOLE program
    try testing.expectEqual(prog.items.len, m.instrs); // every op retired NATIVELY

    // (3) DIFFERENTIAL — observationally identical to the interpreter, across
    //     every realloc. Comparing the whole heap (not just the result word)
    //     is what catches a term built into a STALE buffer after a relocating
    //     grow: the result index would still match while the words behind it
    //     did not. MUT-ALLOC-2 dies here.
    var r = try ia.Machine.init(gpa, &atoms);
    defer r.deinit();
    r.regs[0] = ta.FinalTerms.nil(&r.ctx);
    try ia.run(&r, prog.items, 10_000);

    try testing.expectEqual(r.regs[0], m.regs[0]); // the same list term
    try testing.expectEqualSlices(u64, r.ctx.words.items, m.ctx.words.items);
    try testing.expectEqual(r.instrs, m.instrs); // charged exactly once each
    try testing.expectEqual(r.reductions, m.reductions);

    // (4) THE INVARIANT THE WHOLE DISCIPLINE PROTECTS: allocation never happens
    //     INSIDE native code. Asserted structurally rather than behaviourally,
    //     because behaviour cannot distinguish "native grew the region correctly"
    //     from "the interpreter grew it" — both produce the right answer, and
    //     only one of them is safe. Native code may call EXACTLY ONE thing, the
    //     safe-point shim; anything else reaching the allocator from hand-emitted
    //     code would be calling a Zig function whose ABI Zig does not specify.
    //     MUT-ALLOC-3 dies here.
    {
        var e = Emit{ .gpa = gpa };
        defer e.deinit();
        for (prog.items, 0..) |_, pc| try buildBlock(&e, &prog.items[pc], pc);

        const shim = @intFromPtr(&jitOpSafepoint);
        var calls: usize = 0;
        var last_imm: ?u64 = null;
        for (e.code.items) |inst| switch (inst) {
            // The call sequence is `mov rax, imm64` then `call rax`, so the
            // immediately preceding immediate IS the target.
            .mov_ri => |mi| last_imm = if (mi.dst == .rax) @bitCast(mi.imm) else last_imm,
            .call_r => |reg| {
                try testing.expectEqual(Reg.rax, reg);
                try testing.expectEqual(@as(?u64, shim), last_imm);
                calls += 1;
            },
            else => {},
        };
        // REJECTION COUNTERWEIGHT: a scan that found no calls at all would
        // satisfy the loop above vacuously. The allocating blocks must actually
        // contain safe-points — one per grow guard.
        try testing.expect(calls >= CONSES);
    }
}

test "LAW gap-jit-testeq-operand-widening PREMISE: when EITHER operand is an immediate, word equality IS =:= — and when neither is, it is NOT" {
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    const c = &m.ctx;

    // The IMMEDIATES the widened predicate will admit: atoms, nil, and small
    // integers. Each is a compile-time constant the emitter bakes as a word.
    const imms = [_]u64{
        FinalTerms.atom(c, 0), FinalTerms.atom(c, 1),
        FinalTerms.nil(c),     FinalTerms.int(c, 0),
        FinalTerms.int(c, 1),  FinalTerms.int(c, -5),
    };
    // Boxed terms, INCLUDING two structurally equal tuples built separately —
    // distinct words, equal under =:=. That pair is what makes a raw word
    // compare unsound in general, and it is why the immediate side is required.
    const t1 = try FinalTerms.tuple(c, &.{ FinalTerms.int(c, 1), FinalTerms.int(c, 2) });
    const t2 = try FinalTerms.tuple(c, &.{ FinalTerms.int(c, 1), FinalTerms.int(c, 2) });
    const boxed = [_]u64{
        t1,
        t2,
        try FinalTerms.cons(c, FinalTerms.int(c, 1), FinalTerms.nil(c)),
        try FinalTerms.intFromI128(c, 1 << 70), // a real bignum
        FinalTerms.float(c, 1.0), // =:= must NOT equate 1 and 1.0
        try FinalTerms.binary(c, "hi"),
    };

    // THE PREMISE. Every pair with at least one immediate side: the raw word
    // comparison the JIT will emit agrees with `eqlExact` exactly. This covers
    // the three ways it could fail — a boxed term whose word collides with an
    // immediate, two encodings of one immediate, and an immediate that ought to
    // equal a boxed value (1 vs a bignum 1, 1 vs 1.0).
    for (imms) |a| {
        for (imms) |b|
            try testing.expectEqual(FinalTerms.eqlExact(c, a, b), a == b);
        for (boxed) |b| {
            try testing.expectEqual(FinalTerms.eqlExact(c, a, b), a == b);
            try testing.expectEqual(FinalTerms.eqlExact(c, b, a), b == a);
        }
    }

    // CANONICALITY, stated directly: a small value reached through the i128
    // constructor is the SAME WORD as one built as a small. If this ever split,
    // two words would denote one integer and the premise above would be false
    // for reasons no pair in this fixture happens to expose.
    try testing.expectEqual(FinalTerms.int(c, 7), try FinalTerms.intFromI128(c, 7));

    // THE REJECTION COUNTERWEIGHT — without it this law would be satisfied by a
    // term representation in which word equality were simply always =:=, and
    // the immediate precondition would look decorative. Two structurally equal
    // tuples are =:= with DIFFERENT words: raw word comparison is genuinely
    // unsound once neither side is an immediate, which is exactly the case the
    // predicate must keep rejecting.
    try testing.expect(t1 != t2);
    try testing.expect(FinalTerms.eqlExact(c, t1, t2));
}

test "LAW gap-jit-testeq-operand-widening: native test_eq ≡ interpreter for atom/nil/immediate operands, INCLUDING a boxed value on the other side" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // `test_eq a,b else_to=2` — pc1 is the equal path, pc2 the not-equal path,
    // so the two branches are distinguishable in the register file.
    const Case = struct { a: ia.Src, b: ia.Src, x0: enum { atom3, atom4, nil, small7, boxed }, y0: bool };
    const cases = [_]Case{
        .{ .a = .{ .x = 0 }, .b = .{ .atom_ = 3 }, .x0 = .atom3, .y0 = false }, // equal
        .{ .a = .{ .x = 0 }, .b = .{ .atom_ = 3 }, .x0 = .atom4, .y0 = false }, // different atom
        .{ .a = .{ .atom_ = 3 }, .b = .{ .x = 0 }, .x0 = .atom3, .y0 = false }, // immediate FIRST
        .{ .a = .{ .x = 0 }, .b = .nil, .x0 = .nil, .y0 = false }, // nil vs nil
        // THE CASE THE OLD ARM COULD NOT DO NATIVELY: a BOXED value against an
        // immediate. The small-tag guard fell back on every one of these, and
        // they are the common shape in real code (`is_eq_exact X, []`).
        .{ .a = .{ .x = 0 }, .b = .nil, .x0 = .boxed, .y0 = false },
        .{ .a = .{ .x = 0 }, .b = .{ .atom_ = 3 }, .x0 = .boxed, .y0 = false },
        .{ .a = .{ .x = 0 }, .b = .{ .imm = 7 }, .x0 = .small7, .y0 = false }, // small vs imm
        .{ .a = .{ .x = 0 }, .b = .{ .imm = 7 }, .x0 = .boxed, .y0 = false }, // boxed vs imm
        .{ .a = .{ .y = 0 }, .b = .nil, .x0 = .nil, .y0 = true }, // FRAME slot FIRST
        // FRAME slot SECOND — a distinct register path, not a symmetry of the
        // line above. `emitYAddr` clobbers r10 and cannot target it, so which
        // operand is the frame read decides whether the OTHER value survives.
        // Omitting this case let a wrong-register mutant live.
        .{ .a = .nil, .b = .{ .y = 0 }, .x0 = .nil, .y0 = true },
        .{ .a = .{ .atom_ = 3 }, .b = .{ .y = 0 }, .x0 = .atom3, .y0 = true },
    };

    for (cases, 0..) |cs, idx| {
        const prog = [_]ia.CInstr{
            .{ .test_eq = .{ .a = cs.a, .b = cs.b, .else_to = 2 } },
            .{ .move = .{ .src = .{ .imm = 111 }, .dst = 5 } },
            .{ .move = .{ .src = .{ .imm = 222 }, .dst = 6 } },
        };

        // (1) COVERED — without this arm every differential below would still
        //     pass with the op falling back, which is the state this slice
        //     exists to leave.
        const cost = try attribute(gpa, prog[0..]);
        defer gpa.free(cost);
        try testing.expect(cost[0].covered);

        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);

        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        var r = try ia.Machine.init(gpa, &atoms);
        defer r.deinit();
        inline for (.{ &m, &r }) |mm| {
            mm.regs[0] = switch (cs.x0) {
                .atom3 => FinalTerms.atom(&mm.ctx, 3),
                .atom4 => FinalTerms.atom(&mm.ctx, 4),
                .nil => FinalTerms.nil(&mm.ctx),
                .small7 => FinalTerms.int(&mm.ctx, 7),
                .boxed => try FinalTerms.tuple(&mm.ctx, &.{FinalTerms.int(&mm.ctx, 1)}),
            };
            if (cs.y0) try mm.ystack.append(gpa, mm.regs[0]);
        }

        _ = blk.entries[0].?(&m, 100);
        try ia.run(&r, prog[0..], 100);

        // (2) DIFFERENTIAL — the branch taken, the registers written, and the
        //     instruction accounting all match the interpreter.
        try testing.expectEqual(r.regs[5], m.regs[5]);
        try testing.expectEqual(r.regs[6], m.regs[6]);
        try testing.expectEqual(r.instrs, m.instrs);
        try testing.expectEqual(r.reductions, m.reductions);

        // (3) THE NATIVE PATH WAS TAKEN. A differential against an engine that
        //     immediately bailed is not evidence, and this slice is entirely
        //     about ops that USED to bail: the compare must have retired
        //     natively, so at least the test_eq itself is charged before any
        //     driver could intervene.
        if (idx < cases.len) try testing.expect(m.instrs >= 1);
    }
}

// ===========================================================================
// gap-jit-guard-write-tier-batch: three tiers sharing ONE mechanism — a guard
// (or none) plus a simple state write over primitives that already exist.
// SELECTED BY THE CORPUS CENSUS: swap 556 occurrences in 22 modules,
// test_arity 544 in 21, trim 523 in 20. None occurs in `mylists.beam`, which
// is why none was ever selected while one program was the profile.
//
// REGISTER DISCIPLINE IS THE HAZARD IN THIS FAMILY, and it is asymmetric:
//   `emitYAddr`    uses **r10** as scratch and may not target it.
//   `emitWriteDst` uses **rcx** as the address scratch for a `.y` destination.
// So a value must live in NEITHER r10 nor rcx if it has to survive a frame
// read or a frame write. The first attempt at this batch passed its own law and
// both its mutants while corrupting `maps:fold_1`, because every fixture put
// `.y` in one operand position only. Positions are not symmetries here.

/// `swap a,b` — a TRUE two-register exchange: both operands are READ before
/// either is written. The old BEAM lowering used x15 as scratch and silently
/// corrupted the 16th argument of any 16-arity function (DIVERGENCE 730), so
/// aliasing is the entire point of the op.
///
/// r11/r9 carry the values: `emitWriteDst` destroys rcx, and it is called twice
/// here with the OTHER value still live.
fn emitSwapBlock(e: *Emit, a: ia.Dst, b: ia.Dst, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);

    _ = try emitMaterialize(e, &guards, .r11, ia.dstAsSrc(a));
    _ = try emitMaterialize(e, &guards, .r9, ia.dstAsSrc(b));
    _ = try emitWriteDst(e, &guards, a, .r9);
    _ = try emitWriteDst(e, &guards, b, .r11);

    try emitChargeAndDec(e);
    const j_next = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });
    const fb = try emitFallbackTail(e, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

/// `trim n` — drop the top `n` frame slots, keeping the older frame. Identical
/// in shape to `dealloc_y`: a pure length write. GUARD `len >= n` for the same
/// reason — under-flowing would wrap the unsigned length, and that must be the
/// interpreter's diagnosable error rather than a native corruption.
fn emitTrimBlock(e: *Emit, n: u8, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);

    try e.code.append(e.gpa, .{ .load = .{ .reg = .rax, .base = M, .disp = YSTACK_LEN_OFF } });
    try e.code.append(e.gpa, .{ .cmp_ri = .{ .dst = .rax, .imm = @as(i32, n) } });
    try guards.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .l, .rel = 0 } })); // len < n → fallback
    try e.code.append(e.gpa, .{ .sub_ri = .{ .dst = .rax, .imm = @as(i32, n) } });
    try e.code.append(e.gpa, .{ .store = .{ .reg = .rax, .base = M, .disp = YSTACK_LEN_OFF } });

    try emitChargeAndDec(e);
    const j_next = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });
    const fb = try emitFallbackTail(e, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

/// `test_arity src, arity, else_to` — fall through iff `src` is a tuple of
/// EXACTLY `arity`. Decided ENTIRELY natively: a non-tuple is not an error here,
/// it is the else branch.
///
/// The arity check MIRRORS the interpreter (`kindOf == .tuple` then
/// `tupleArity == arity`) rather than comparing the whole header word against
/// `arity << 7`. That shortcut was the second defect in the first attempt: the
/// header carries low tag bits beyond the arity field, so an exact word compare
/// rejects every valid tuple and sends it to `else_to` — which shows up not as a
/// crash but as a real program taking the wrong branch, and cost a `badarith`
/// inside `maps:fold_1`. Subtag first, then `header >> 7`, exactly as
/// `headerCount` does it.
fn emitTestArityBlock(e: *Emit, src: ia.Src, arity: u16, else_to: usize, pc: usize) !void {
    try emitBudgetCheck(e, pc);
    var guards: std.ArrayList(usize) = .empty;
    defer guards.deinit(e.gpa);
    var misses: std.ArrayList(usize) = .empty;
    defer misses.deinit(e.gpa);

    _ = try emitMaterialize(e, &guards, .rax, src);
    try emitChargeAndDec(e);

    // not boxed ⇒ not a tuple ⇒ else_to (NOT a fallback).
    try emitMaskEq(e, .rax, TAG_MASK, TAG_BOXED);
    try misses.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } }));

    try emitHeapAddr(e, .rax, .rcx); // rcx = &header
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rdx, .base = .rcx, .disp = 0 } });
    // boxed NON-tuple ⇒ else_to.
    try emitMaskEq(e, .rdx, SUBTAG_FIELD, SUBTAG_TUPLE_INPLACE);
    try misses.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } }));
    // arity = header >> 7 (headerCount). Reload: emitMaskEq consumed rdx.
    try e.code.append(e.gpa, .{ .load = .{ .reg = .rdx, .base = .rcx, .disp = 0 } });
    try e.code.append(e.gpa, .{ .sar_ri = .{ .dst = .rdx, .imm = 7 } });
    try e.code.append(e.gpa, .{ .mov_ri = .{ .dst = .r11, .imm = @intCast(arity) } });
    try e.code.append(e.gpa, .{ .cmp_rr = .{ .dst = .rdx, .src = .r11 } });
    try misses.append(e.gpa, try e.emit(.{ .jcc = .{ .cc = .ne, .rel = 0 } }));

    const j_next = try e.emit(.{ .jmp = 0 }); // holds → block[pc+1]
    try e.pc_fixups.append(e.gpa, .{ .site = j_next, .target_pc = pc + 1 });

    // the MISS tail: a plain jump to else_to — the test decided, nothing failed.
    const miss = e.code.items.len;
    const j_else = try e.emit(.{ .jmp = 0 });
    try e.pc_fixups.append(e.gpa, .{ .site = j_else, .target_pc = else_to });
    for (misses.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = miss });

    const fb = try emitFallbackTail(e, pc);
    for (guards.items) |g| try e.inst_fixups.append(e.gpa, .{ .site = g, .target = fb });
}

test "LAW gap-jit-guard-write-tier-batch: native swap/trim/test_arity ≡ interpreter, with frame slots in EVERY operand position and a boxed non-tuple else branch" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // ---- swap. THE hazard is aliasing AND scratch-register collision, and the
    // second is ASYMMETRIC: `emitWriteDst` destroys rcx for a `.y` destination,
    // `emitYAddr` destroys r10 for a `.y` source. The first attempt at this
    // batch tested `x,y` only, passed, and corrupted `maps:fold_1`. So every
    // position combination is driven here — that omission is the defect.
    const SwapCase = struct { a: ia.Dst, b: ia.Dst, ys: usize };
    for ([_]SwapCase{
        .{ .a = .{ .x = 0 }, .b = .{ .x = 1 }, .ys = 0 }, // resident x0/x1
        .{ .a = .{ .x = 0 }, .b = .{ .y = 0 }, .ys = 1 }, // frame SECOND
        .{ .a = .{ .y = 0 }, .b = .{ .x = 0 }, .ys = 1 }, // frame FIRST ← the miss
        .{ .a = .{ .y = 0 }, .b = .{ .y = 1 }, .ys = 2 }, // frame BOTH
        .{ .a = .{ .x = 7 }, .b = .{ .y = 0 }, .ys = 1 }, // non-resident x
    }) |cs| {
        const prog = [_]ia.CInstr{.{ .swap = .{ .a = cs.a, .b = cs.b } }};
        const cost = try attribute(gpa, prog[0..]);
        defer gpa.free(cost);
        try testing.expect(cost[0].covered);

        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        var r = try ia.Machine.init(gpa, &atoms);
        defer r.deinit();
        inline for (.{ &m, &r }) |mm| {
            for (0..8) |i| mm.regs[i] = FinalTerms.int(&mm.ctx, @intCast(100 + i));
            for (0..cs.ys) |i| try mm.ystack.append(gpa, FinalTerms.int(&mm.ctx, @intCast(200 + i)));
        }
        _ = blk.entries[0].?(&m, 100);
        try ia.run(&r, prog[0..], 100);
        for (0..8) |i| try testing.expectEqual(r.regs[i], m.regs[i]);
        try testing.expectEqualSlices(u64, r.ystack.items, m.ystack.items);
        try testing.expectEqual(r.instrs, m.instrs);
        // NON-VACUITY: the exchange really happened (both engines agreeing on a
        // no-op would satisfy the differential alone).
        try testing.expect(r.pc == 1);
    }

    // ---- trim: a length write, plus the under-run guard falling back UNCHARGED.
    {
        const prog = [_]ia.CInstr{.{ .trim = .{ .n = 2 } }};
        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        var r = try ia.Machine.init(gpa, &atoms);
        defer r.deinit();
        inline for (.{ &m, &r }) |mm| for (0..5) |i|
            try mm.ystack.append(gpa, FinalTerms.int(&mm.ctx, @intCast(i)));
        _ = blk.entries[0].?(&m, 100);
        try ia.run(&r, prog[0..], 100);
        try testing.expectEqualSlices(u64, r.ystack.items, m.ystack.items);
        try testing.expectEqual(@as(usize, 3), m.ystack.items.len);
        try testing.expectEqual(r.instrs, m.instrs);

        var u = try ia.Machine.init(gpa, &atoms);
        defer u.deinit();
        try u.ystack.append(gpa, FinalTerms.nil(&u.ctx));
        try testing.expectEqual(@as(u64, @bitCast(RET_FALLBACK)), blk.entries[0].?(&u, 100));
        try testing.expectEqual(@as(usize, 1), u.ystack.items.len); // NOT wrapped
        try testing.expectEqual(@as(u64, 0), u.instrs); // guard precedes the charge
    }

    // ---- test_arity: decided entirely natively. The BOXED NON-TUPLE and the
    // real-tuple arms are what the header shortcut got wrong: comparing the
    // whole header word against `arity << 7` rejects every valid tuple, which
    // is a WRONG BRANCH rather than a crash.
    {
        const prog = [_]ia.CInstr{
            .{ .test_arity = .{ .src = .{ .x = 0 }, .arity = 2, .else_to = 2 } },
            .{ .move = .{ .src = .{ .imm = 111 }, .dst = 5 } },
            .{ .move = .{ .src = .{ .imm = 222 }, .dst = 6 } },
        };
        const cost = try attribute(gpa, prog[0..]);
        defer gpa.free(cost);
        try testing.expect(cost[0].covered);

        var blk = try compileBlock(gpa, prog[0..]);
        defer blk.deinit(gpa);
        var holds: usize = 0;
        for ([_]u8{ 0, 1, 2, 3, 4 }) |shape| {
            var m = try ia.Machine.init(gpa, &atoms);
            defer m.deinit();
            var r = try ia.Machine.init(gpa, &atoms);
            defer r.deinit();
            inline for (.{ &m, &r }) |mm| {
                mm.regs[0] = switch (shape) {
                    0 => try FinalTerms.tuple(&mm.ctx, &.{ FinalTerms.int(&mm.ctx, 1), FinalTerms.int(&mm.ctx, 2) }), // holds
                    1 => try FinalTerms.tuple(&mm.ctx, &.{FinalTerms.int(&mm.ctx, 1)}), // arity 1
                    2 => FinalTerms.nil(&mm.ctx), // not boxed
                    3 => try FinalTerms.binary(&mm.ctx, "hi"), // BOXED NON-TUPLE
                    else => try FinalTerms.cons(&mm.ctx, FinalTerms.int(&mm.ctx, 1), FinalTerms.nil(&mm.ctx)),
                };
            }
            _ = blk.entries[0].?(&m, 100);
            try ia.run(&r, prog[0..], 100);
            try testing.expectEqual(r.regs[5], m.regs[5]);
            try testing.expectEqual(r.regs[6], m.regs[6]);
            try testing.expectEqual(r.instrs, m.instrs);
            // The holds branch is the one that writes 111 into x5. Comparing
            // against 0 would be wrong: an unwritten register holds nil, not
            // zero, so every shape would look like a hold.
            if (r.regs[5] == FinalTerms.int(&r.ctx, 111)) holds += 1;
        }
        // NON-VACUITY: exactly one shape took the HOLDS branch. A predicate that
        // answered "else" to everything — the header-shortcut defect — would
        // still match the interpreter on four of five shapes.
        try testing.expectEqual(@as(usize, 1), holds);
    }
}

// ===========================================================================
// gap-jit-register-interference-model: the fact that caused every codegen
// defect in this epoch, made machine-checked.
//
// Four defects in one week were all one thing: a value sat in a register that
// an emitter HELPER destroys. Which registers each helper destroys is small,
// finite and decidable — and until now it lived only in doc-comments, where
// nothing re-checks it. SC-50.2 in SAFETY_ANALYSIS.md §18 recorded that as an
// explicit gap (FM-JIT-SCRATCH-ALIAS, RPN 144, the highest open row). This
// closes it.
//
// The model has two halves, because the hazard has two halves:
//   DECLARATION FIDELITY — each helper's declared clobber set is verified
//     against the registers it ACTUALLY writes, by emitting it in isolation and
//     scanning the instruction stream. A helper that grows a new scratch
//     register reddens here, at the declaration, rather than in a distant block.
//   POSITION TOTALITY — every covered op is compiled and differentially
//     executed with its operands in EVERY position combination. This is the
//     mechanical form of the fixture-totality rule: "by symmetry" is a claim
//     about the code, and it was false four times.

/// A set of x86-64 registers, one bit per `Reg`.
const RegSet = u16;
fn regBit(r: Reg) RegSet {
    return @as(RegSet, 1) << @intFromEnum(r);
}

/// The register an instruction WRITES, if any. `store` writes memory; `cmp_*`
/// writes only flags; `call_r` is governed by the ABI rather than by this model
/// (the safepoint saves the pinned registers explicitly).
fn instWrites(inst: Inst) ?Reg {
    return switch (inst) {
        .mov_ri => |o| o.dst,
        .mov_rr, .add_rr, .sub_rr, .and_rr => |o| o.dst,
        .add_ri, .and_ri, .sub_ri => |o| o.dst,
        .sar_ri, .shl_ri => |o| o.dst,
        .lea => |o| o.dst,
        .load => |o| o.reg,
        .pop => |r| r,
        .cmp_rr, .cmp_ri, .store, .push, .ret, .jmp, .jcc, .call, .call_r => null,
    };
}

/// Every register written by `code` — the helper's OBSERVED clobber set.
fn writesOf(code: []const Inst) RegSet {
    var s: RegSet = 0;
    for (code) |i| if (instWrites(i)) |r| {
        s |= regBit(r);
    };
    return s;
}

test "LAW gap-jit-register-interference-model DECLARATION: every emitter helper's clobber set is what it actually writes" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;

    // `emitYAddr(_, _, i, addr)` — DECLARED: r10 (scratch) ∪ {addr}. The r10 use
    // is also why `addr` may not BE r10: the helper loads the region pointer
    // into `addr` after computing the offset in r10, so aliasing them destroys
    // the offset. That is a separate law below.
    {
        var e = Emit{ .gpa = gpa };
        defer e.deinit();
        var g: std.ArrayList(usize) = .empty;
        defer g.deinit(gpa);
        try emitYAddr(&e, &g, 0, .rcx);
        try testing.expectEqual(regBit(.r10) | regBit(.rcx), writesOf(e.code.items));
    }

    // `emitWriteDst(_, _, .{ .y = _ }, src)` — DECLARED: r10 ∪ rcx. The rcx use
    // is the one that corrupted `maps:fold_1`: it is the ADDRESS scratch, so a
    // caller passing rcx as `src` writes the address over the value.
    {
        var e = Emit{ .gpa = gpa };
        defer e.deinit();
        var g: std.ArrayList(usize) = .empty;
        defer g.deinit(gpa);
        _ = try emitWriteDst(&e, &g, .{ .y = 0 }, .r11);
        try testing.expectEqual(regBit(.r10) | regBit(.rcx), writesOf(e.code.items));
    }

    // `emitMaterialize(_, _, dst, .{ .y = _ })` — DECLARED: r10 ∪ {dst}.
    {
        var e = Emit{ .gpa = gpa };
        defer e.deinit();
        var g: std.ArrayList(usize) = .empty;
        defer g.deinit(gpa);
        _ = try emitMaterialize(&e, &g, .r11, .{ .y = 0 });
        try testing.expectEqual(regBit(.r10) | regBit(.r11), writesOf(e.code.items));
    }

    // `emitHeapAddr(_, w, addr)` — DECLARED: r10 ∪ {addr}.
    {
        var e = Emit{ .gpa = gpa };
        defer e.deinit();
        try emitHeapAddr(&e, .rax, .rcx);
        try testing.expectEqual(regBit(.r10) | regBit(.rcx), writesOf(e.code.items));
    }

    // REJECTION COUNTERWEIGHT — a scan that saw nothing would satisfy every
    // expectation above by returning the empty set for all of them. An
    // instruction that plainly writes a register must be seen to.
    {
        var e = Emit{ .gpa = gpa };
        defer e.deinit();
        try e.code.append(gpa, .{ .mov_ri = .{ .dst = .r9, .imm = 1 } });
        try e.code.append(gpa, .{ .cmp_ri = .{ .dst = .r9, .imm = 1 } }); // flags only
        try testing.expectEqual(regBit(.r9), writesOf(e.code.items));
    }
}

test "LAW gap-jit-register-interference-model POSITION TOTALITY: every two-operand covered op ≡ interpreter in EVERY operand-position combination" {
    if (!native_supported) return error.SkipZigTest;
    const gpa = testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();

    // The position space. x0 is RESIDENT (r12), x7 is not — the two travel
    // different paths through readX/writeX — and y0/y1 go through emitYAddr,
    // which is the helper whose scratch caused the defects.
    const POS = [_]ia.Dst{ .{ .x = 0 }, .{ .x = 7 }, .{ .y = 0 }, .{ .y = 1 } };
    const YDEPTH: usize = 2;

    // Seed both machines identically. Distinct values everywhere so any
    // clobber shows up as a wrong value rather than a coincidence.
    const seed = struct {
        fn go(mm: *ia.Machine, alloc: std.mem.Allocator) !void {
            for (0..8) |i| mm.regs[i] = FinalTerms.int(&mm.ctx, @intCast(100 + i));
            for (0..YDEPTH) |i| try mm.ystack.append(alloc, FinalTerms.int(&mm.ctx, @intCast(200 + i)));
        }
    }.go;

    var checked: usize = 0;

    // ---- swap: both operands are DESTINATIONS, so both go through
    //      emitWriteDst (rcx) as well as emitMaterialize (r10).
    for (POS) |a| {
        for (POS) |b| {
            if (std.meta.eql(a, b)) continue; // swapping a slot with itself is not the hazard
            const prog = [_]ia.CInstr{.{ .swap = .{ .a = a, .b = b } }};
            var blk = try compileBlock(gpa, prog[0..]);
            defer blk.deinit(gpa);
            var m = try ia.Machine.init(gpa, &atoms);
            defer m.deinit();
            var r = try ia.Machine.init(gpa, &atoms);
            defer r.deinit();
            try seed(&m, gpa);
            try seed(&r, gpa);
            _ = blk.entries[0].?(&m, 100);
            try ia.run(&r, prog[0..], 100);
            for (0..8) |i| try testing.expectEqual(r.regs[i], m.regs[i]);
            try testing.expectEqualSlices(u64, r.ystack.items, m.ystack.items);
            try testing.expectEqual(r.instrs, m.instrs);
            checked += 1;
        }
    }

    // ---- test_eq with an immediate on one side, the other operand roving.
    //      This is the shape that faulted in gap-jit-testeq-operand-widening.
    for (POS) |p| {
        const src = ia.dstAsSrc(p);
        for ([_][2]ia.Src{ .{ src, .nil }, .{ .nil, src }, .{ src, .{ .atom_ = 3 } }, .{ .{ .atom_ = 3 }, src } }) |ab| {
            const prog = [_]ia.CInstr{
                .{ .test_eq = .{ .a = ab[0], .b = ab[1], .else_to = 2 } },
                .{ .move = .{ .src = .{ .imm = 111 }, .dst = 5 } },
                .{ .move = .{ .src = .{ .imm = 222 }, .dst = 6 } },
            };
            var blk = try compileBlock(gpa, prog[0..]);
            defer blk.deinit(gpa);
            var m = try ia.Machine.init(gpa, &atoms);
            defer m.deinit();
            var r = try ia.Machine.init(gpa, &atoms);
            defer r.deinit();
            try seed(&m, gpa);
            try seed(&r, gpa);
            _ = blk.entries[0].?(&m, 100);
            try ia.run(&r, prog[0..], 100);
            for (0..8) |i| try testing.expectEqual(r.regs[i], m.regs[i]);
            try testing.expectEqualSlices(u64, r.ystack.items, m.ystack.items);
            try testing.expectEqual(r.instrs, m.instrs);
            checked += 1;
        }
    }

    // ---- put_list: two SOURCES plus a destination — the allocating tier,
    //      where a clobber also corrupts the heap rather than just a register.
    for (POS) |h| {
        for (POS) |t| {
            const prog = [_]ia.CInstr{.{ .put_list = .{ .h = ia.dstAsSrc(h), .t = ia.dstAsSrc(t), .dst = 2 } }};
            var blk = try compileBlock(gpa, prog[0..]);
            defer blk.deinit(gpa);
            var m = try ia.Machine.init(gpa, &atoms);
            defer m.deinit();
            var r = try ia.Machine.init(gpa, &atoms);
            defer r.deinit();
            try seed(&m, gpa);
            try seed(&r, gpa);
            _ = blk.entries[0].?(&m, 100);
            try ia.run(&r, prog[0..], 100);
            for (0..8) |i| try testing.expectEqual(r.regs[i], m.regs[i]);
            // The HEAP, not just the result word: a stale-base write shows up
            // here and nowhere else.
            try testing.expectEqualSlices(u64, r.ctx.words.items, m.ctx.words.items);
            try testing.expectEqual(r.instrs, m.instrs);
            checked += 1;
        }
    }

    // NON-VACUITY: the combinations were really driven. A `continue` that
    // skipped everything, or a POS list that lost its frame slots, would leave
    // this law passing while testing nothing — which is the exact failure it
    // exists to prevent, one level up.
    try testing.expectEqual(@as(usize, 12 + 16 + 16), checked);
}
