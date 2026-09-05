//! zigvm agent-codegen: the VERIFIED agent-code-generation firewall (Zig side).
//!
//! ── Signature ───────────────────────────────────────────────────────────────
//! This module holds AGENT-AUTHORED functions that are admitted into the VM ONLY
//! because a machine-checked Aeon refinement contract (specs/agent/<name>.ae) is
//! shown to hold of them. The module introduces NO new VM semantics — each unit
//! is a small total pure function whose obligation is stated externally as an SMT
//! refinement type and discharged by the harness `--verify-agent-codegen` stage
//! (contract soundness + non-triviality via Z3, conformance via seeded/boundary
//! property-testing of THIS impl against the contract predicate).
//!
//! ── Semantic domain ─────────────────────────────────────────────────────────
//! A unit `f : (x1:{v|P1}) … (xk:{v|Pk}) : {r | Q(x1..xk, r)}` denotes a total
//! function on the refined input domain whose output satisfies Q. The contract is
//! the SPEC (L4 feature-slice + L5 representation), the conformance property is
//! the LAW (L6): ∀ seeded/boundary inputs in the domain, Q(inputs, f(inputs)).
//!
//! ── Oracle / final ──────────────────────────────────────────────────────────
//! The contract's refinement predicate is the ORACLE (the intended meaning); the
//! Zig body is the FINAL encoding. They are glued by the conformance property —
//! in-tree here (the `clampU32 meets clamp_u32.ae` test) AND at the harness
//! firewall (differential over the SAME predicate, executed through the
//! `zigvm agent-eval` CLI probe). Property-testing over seeded + boundary inputs
//! is NOT a total proof for the infinite Int domain — it is the project's
//! standard discipline (differential over seeded generators + boundaries). The
//! Z3 checks that ride alongside are total (contract soundness + non-triviality).
//!
//! ── Scope ───────────────────────────────────────────────────────────────────
//! Int-only units for now (the SMT-tractable subset the native Aeon judge shares
//! with Z3). New units: add the pure fn here, wire it into `agentEvalU64` below
//! (so the CLI probe can reach it) and ship its `.ae` contract under specs/agent/.

const std = @import("std");

/// clamp_u32 (the demo unit). Contract specs/agent/clamp_u32.ae:
///   def clamp_u32 (n:{v:Int|v>=0}) (hi:{v:Int|v>=0}) : {r:Int | r>=0 && r<=hi}
/// i.e. saturate a non-negative `n` at the non-negative ceiling `hi`. The result
/// is always in [0, hi]. (`u64` inputs make n>=0 / hi>=0 structural; the harness
/// still exercises the refined-Int domain, negatives filtered by the contract.)
pub fn clampU32(n: u64, hi: u64) u64 {
    return if (n > hi) hi else n;
}

/// The domain error surface for the CLI probe (never a panic).
pub const AgentEvalError = error{ UnknownAgentFn, BadAgentArity };

/// Evaluate an Int-valued agent unit by name over positional u64 args. This is
/// the single dispatch the `zigvm agent-eval <fn> <args…>` CLI probe rides, so
/// the harness firewall can run the REAL impl on seeded/boundary inputs. Total:
/// an unknown fn or wrong arity is a NAMED error, never a panic.
pub fn agentEvalU64(fn_name: []const u8, args: []const u64) AgentEvalError!u64 {
    if (std.mem.eql(u8, fn_name, "clamp_u32")) {
        if (args.len != 2) return AgentEvalError.BadAgentArity;
        return clampU32(args[0], args[1]);
    }
    return AgentEvalError.UnknownAgentFn;
}

// ── in-tree conformance law (L6): clampU32 meets its contract ────────────────
// Mirrors the harness firewall in miniature — the SAME refinement predicate
// (r>=0 && r<=hi) property-tested over a seeded + boundary domain. A hang is a
// failed law (bounded loop); this is observational (value equality on the
// predicate), never pointer identity.
test "LAW agent-codegen: clampU32 satisfies clamp_u32.ae refinement (seeded+boundary)" {
    const boundary = [_][2]u64{
        .{ 0, 0 },       .{ 0, 5 },     .{ 5, 0 },
        .{ 3, 3 },       .{ 4000, 3 },  .{ 3, 4000 },
        .{ 4001, 4000 }, .{ 5000, 10 }, .{ 1, 1 },
    };
    for (boundary) |bc| {
        const r = clampU32(bc[0], bc[1]);
        // Q(n,hi,r) := r<=hi && (n<=hi => r==n) && (n>hi => r==hi)  — the HD-4
        // FUNCTIONAL predicate (r == min(n,hi)), not the old loose r<=hi envelope.
        try std.testing.expect(r <= bc[1]);
        try std.testing.expect(if (bc[0] <= bc[1]) r == bc[0] else r == bc[1]);
    }
    // seeded sweep: a fixed LCG so a failure echoes reproducibly.
    var seed: u64 = 0x9E3779B97F4A7C15;
    var i: usize = 0;
    while (i < 4096) : (i += 1) {
        seed = seed *% 6364136223846793005 +% 1442695040888963407;
        const n: u64 = (seed >> 11) % 6000;
        const hi: u64 = (seed >> 33) % 6000;
        const r = clampU32(n, hi);
        std.testing.expect(r == (if (n <= hi) n else hi)) catch |e| {
            std.debug.print("clampU32 functional contract violated: n={d} hi={d} r={d} (seed step {d})\n", .{ n, hi, r, i });
            return e;
        };
    }
}

// ── HD-4 E_complete witness (the eight-lens review's flagship counterexample) ──
// `return 0` (a constant impl ignoring both inputs) satisfied the OLD loose
// contract (r>=0 && r<=hi) on EVERY input yet is wrong. The strengthened
// FUNCTIONAL contract (r == min(n,hi)) EXCLUDES it. This standing law witnesses
// that the E_complete gap is closed: the constant-0 impl violates the functional
// predicate at an input where the correct output is non-zero — the same fact the
// harness degenerate-witness check (agent_contract_excludes_constants) proves via
// Z3 over ALL inputs. If a future edit re-loosens the contract, HD-4 reds the gate.
test "LAW HD-4 agent-codegen: constant-0 impl VIOLATES clamp_u32's functional contract (E_complete closed)" {
    const wrongConst0 = struct {
        fn f(_: u64, _: u64) u64 {
            return 0;
        }
    }.f;
    // witness input where the correct answer is non-zero: n=5, hi=9 → min=5.
    const n: u64 = 5;
    const hi: u64 = 9;
    const r = wrongConst0(n, hi);
    const functional_ok = r == (if (n <= hi) n else hi);
    // the constant-0 impl must FAIL the functional predicate here (E_complete excluded).
    try std.testing.expect(!functional_ok);
    // and the real impl must PASS it (sanity: the contract is satisfiable).
    try std.testing.expect(clampU32(n, hi) == (if (n <= hi) n else hi));
}

test "LAW agent-codegen: agentEvalU64 dispatch is total (named errors, no panic)" {
    try std.testing.expectEqual(@as(u64, 3), try agentEvalU64("clamp_u32", &.{ 5, 3 }));
    try std.testing.expectEqual(@as(u64, 5), try agentEvalU64("clamp_u32", &.{ 5, 9 }));
    try std.testing.expectError(AgentEvalError.UnknownAgentFn, agentEvalU64("nope", &.{ 1, 2 }));
    try std.testing.expectError(AgentEvalError.BadAgentArity, agentEvalU64("clamp_u32", &.{1}));
}
