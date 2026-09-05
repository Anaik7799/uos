//! # bifs/erlang — the `erlang` guard-BIF family (E2.4)
//!
//! ## Signature
//! Each guard BIF is a `pub fn (m: *Machine, args: []const Term) BifError!Term`
//! over ALREADY-RESOLVED term arguments. It reads its args, computes via an
//! EXISTING `term_algebra` operation (NO new term semantics live here), and
//! returns the result term or a clean `error.Badarg`/`error.Badarith`. It NEVER
//! panics on a well-formed call and has NO side effect (the `ubif` contract).
//!
//! ## The dispatch mechanism (the crux — scales to ~300 BIFs)
//! `bifs/dispatch.resolve(module,name,arity)` maps an `.implemented` `bif_table`
//! entry to one of these `pub fn`s, returning `?ia.BifFn` (a function pointer).
//! The loader bakes that pointer into `BifRef{ .func }`; the machine's `bif_call`
//! arm calls it with the resolved args and routes any error through the ONE
//! guard-vs-body site (`Machine.bifFail`): GUARD context (a fail label present)
//! BRANCHES to `else_to`; BODY context (no label) CRASHES the exact BEAM reason
//! (`badarg`/`badarith`). Every later family task (E2.5+) adds `pub fn`s here and
//! one `implOf` arm — never an executor edit, never a giant enum.
//!
//! ## Semantic domain — reuse, not reinvention
//! The wired algebra per BIF:
//!   accessors  element/tuple_size/size → tupleElem/tupleArity; hd/tl → listHead/
//!              listTail; length → cons walk; byte_size/size → binBytes.len;
//!              map_size → mapSize; map_get/is_map_key → mapGet.
//!   arith      +,-,* → add / add∘negate / mul; div,rem → idiv,irem; band/bor/
//!              bxor/bnot/bsl/bsr → the term_algebra bitwise ops; abs → sign;
//!              -/1 → negate. (SMALL-INT domain: a bignum operand defers to the
//!              dedicated bignum-arith slice via a clean badarith — see
//!              term_algebra's E2.4 note.)
//!   compare    ==,/=,<,>,=<,>= → compare (arith order); =:=,=/= → eqlExact —
//!              TOTAL over all terms, returning the `true`/`false` atoms.
//!   rounding   float → float(numToF64); trunc/round/floor/ceil → f64 rounding
//!              (integer input returned unchanged; a float whose rounded value
//!              exceeds i128 defers via badarith).
//!   bool       not/and/or/xor over the `true`/`false` atoms.
//!   type_test  (E3.6) is_pid/is_port/is_reference → `repIsPid`/`repIsPort`/
//!              `repIsRef` (the E3.5 term-kind observers) — TOTAL over every
//!              term (never badarg), the `ubif` guard-context law.
//!
//! ## Scope limits (documented, honest)
//!   - Arith `*`,`div`,`rem`,`band`,`bor`,`bxor`,`bnot`,`bsl`,`bsr` are
//!     SMALL-INTEGER-only; a bignum operand is a clean badarith (deferred to the
//!     bignum-arithmetic follow-up), NOT a panic. `+`,`-`,`abs`,`-/1` ARE
//!     bignum-aware (they reuse the E1 bignum add/negate).
//!   - `map_get/2`/`is_map_key/2` on a non-map raise `error:{badmap,Map}` and
//!     `map_get/2` on an absent key `error:{badkey,Key}` — the EXACT structured
//!     reasons, DISCHARGED at E3.10 (`raiseBadmap`/`raiseBadkey`, DIVERGENCE 6b
//!     + 23; was simplified `badarg`). The GUARD-context BRANCH behaviour — the
//!     part guards depend on — is UNCHANGED (still branches to `else_to`).
//!   - E3.10 exception-RAISING family (`error_1`..`raise_3`, `nif_error_1/2`):
//!     implemented + law-proven directly, but `deferred-E4-procdispatch` (NOT
//!     wired into dispatch, NOT EQ) — they compile to `{call_ext_only,...}`, so
//!     they are call_ext-unreachable from a compiled `.beam` until Task 12/E4.
//!   - `self/0`, `node/1` are NOT implemented (they need a pid term — an E3
//!     term-representation concern); they stay `stub`, classified `justified:
//!     deferred-E3` in `harness/bif_gen.ml` (see `bifs/procsys.zig`'s doc
//!     comment for the full process/system BIF implement/justify split).
//!     `node/0` (no pid needed — the constant non-distributed node name) IS
//!     implemented, but lives in `bifs/procsys.zig` (E2.11), not here.
//!
//! ## Laws (see the E2.4 suite below + bifs/dispatch + instr_algebra)
//!   - DENOTATION (per BIF): the fn == its wired algebra (element(2,{a,b}) ==
//!     tupleElem idx 1; abs(-3) == 3; (X<Y) == compare==.lt).
//!   - GUARD-CONTEXT (over element): element(0,{a}) BRANCHES in guard, CRASHES
//!     badarg in body (the `ubif` law).
//!   - MIGRATION: erlang.add/sub == the pre-E2.4 `.add`/`.sub` result.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

// ── shared helpers ─────────────────────────────────────────────────────────

fn boolTerm(m: *Machine, cond: bool) Term {
    return FinalTerms.atom(&m.ctx, if (cond) m.bool_true else m.bool_false);
}

/// The Zig bool a `true`/`false` atom denotes, or null if `w` is neither.
fn asBool(m: *Machine, w: Term) ?bool {
    if (!FinalTerms.repIsAtom(w)) return null;
    const idx = FinalTerms.atomIdxOf(w);
    if (idx == m.bool_true) return true;
    if (idx == m.bool_false) return false;
    return null;
}

fn isInteger(m: *Machine, w: Term) bool {
    return FinalTerms.repIsSmall(w) or FinalTerms.repIsBig(&m.ctx, w);
}

// ── accessors / type observers ─────────────────────────────────────────────

/// `element(N, Tuple)` — 1-based indexing (the worked BIF). Off-by-one here is
/// mutant 1 (`i` instead of `i-1`).
pub fn element(m: *Machine, args: []const Term) BifError!Term {
    const n = args[0];
    const tup = args[1];
    if (!FinalTerms.repIsSmall(n)) return error.Badarg;
    if (FinalTerms.kindOf(&m.ctx, tup) != .tuple) return error.Badarg;
    const i = FinalTerms.smallValOf(n); // 1-based
    const arity: i64 = @intCast(FinalTerms.tupleArity(&m.ctx, tup));
    if (i < 1 or i > arity) return error.Badarg;
    return FinalTerms.tupleElem(&m.ctx, tup, @intCast(i - 1));
}

pub fn tuple_size(m: *Machine, args: []const Term) BifError!Term {
    if (FinalTerms.kindOf(&m.ctx, args[0]) != .tuple) return error.Badarg;
    return FinalTerms.int(&m.ctx, @intCast(FinalTerms.tupleArity(&m.ctx, args[0])));
}

pub fn hd(m: *Machine, args: []const Term) BifError!Term {
    if (FinalTerms.kindOf(&m.ctx, args[0]) != .cons) return error.Badarg;
    return FinalTerms.listHead(&m.ctx, args[0]);
}

pub fn tl(m: *Machine, args: []const Term) BifError!Term {
    if (FinalTerms.kindOf(&m.ctx, args[0]) != .cons) return error.Badarg;
    return FinalTerms.listTail(&m.ctx, args[0]);
}

/// `length/1` — walk the proper list; an improper tail or non-list is badarg.
pub fn length(m: *Machine, args: []const Term) BifError!Term {
    var t = args[0];
    var n: i128 = 0;
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, t)) {
            .nil => break,
            .cons => {
                n += 1;
                t = FinalTerms.listTail(&m.ctx, t);
            },
            else => return error.Badarg,
        }
    }
    return FinalTerms.intFromI128(&m.ctx, n);
}

/// `byte_size/1`'s core: `.binary` buckets BOTH true binaries (SUBTAG_BINARY)
/// and bitstrings (SUBTAG_BITSTRING) — see term_algebra's E3.1 `kindOf`
/// bucketing note. A true binary's byte count is `binBytes(...).len`; a
/// bitstring's `bit_len` HEADER WORD IS NOT A BYTE COUNT (E3.1-fix: reading
/// it as one via `binBytes` on a sub-byte bitstring under-reports or panics
/// OOB). BEAM: `byte_size(<<..:N>>) == ceil(N/8)`, matching a true binary
/// when N is a multiple of 8 (so this single formula covers both cases via
/// the bitstring branch, but we keep the binary fast-path for the common
/// case).
fn binaryByteSize(m: *Machine, t: Term) usize {
    if (FinalTerms.repIsBitstring(&m.ctx, t)) {
        const bits = FinalTerms.bitstringBits(&m.ctx, t);
        return (bits.bit_len + 7) / 8;
    }
    return FinalTerms.binBytes(&m.ctx, t).len;
}

pub fn byte_size(m: *Machine, args: []const Term) BifError!Term {
    // bs-unaligned-tail: byte_size of a MATCH CONTEXT = ceil(remaining/8)
    // (the bit_size sibling — see its comment for the erts grounding).
    if (FinalTerms.repIsMatchCtx(&m.ctx, args[0])) {
        const bin = FinalTerms.matchCtxBin(&m.ctx, args[0]);
        const rem = FinalTerms.bitsOf(&m.ctx, bin).bit_len - FinalTerms.matchCtxOffset(&m.ctx, args[0]);
        return FinalTerms.int(&m.ctx, @intCast((rem + 7) / 8));
    }
    if (FinalTerms.kindOf(&m.ctx, args[0]) != .binary) return error.Badarg;
    return FinalTerms.int(&m.ctx, @intCast(binaryByteSize(m, args[0])));
}

/// `bit_size/1` (E3.2, fka the E2 fast-follow row) — the TRUE bit count of a
/// binary or bitstring: `bit_size(<<..:N>>) == N`, agreeing with
/// `byte_size` * 8 only when aligned. Before E3.1's bitstring kind this was
/// necessarily `byte_size * 8` (no sub-byte representation existed); now
/// that a bitstring's real `bit_len` is available (`FinalTerms.bitsOf`),
/// this is the TRUE observation, not the byte-rounded approximation.
pub fn bit_size(m: *Machine, args: []const Term) BifError!Term {
    // bs-unaligned-tail: a MATCH CONTEXT is a positioned view (erts OTP-26+
    // unified bitstrings: the context IS an ErlSubBits, and `bit_size(sb)` is
    // `end - start` = the REMAINING bits). The compiler exploits this —
    // `bit_size(Tail)` compiles to `gc_bif bit_size` applied DIRECTLY to the
    // context (`{tr,_,{t_bs_context,_}}`), so the BIF must answer with the
    // remaining size, not the underlying binary's total (the pre-fix arm fell
    // into the plain-binary path and read the context BOX as if it were a
    // binary — fleet finding: 64 instead of 8).
    if (FinalTerms.repIsMatchCtx(&m.ctx, args[0])) {
        const bin = FinalTerms.matchCtxBin(&m.ctx, args[0]);
        const rem = FinalTerms.bitsOf(&m.ctx, bin).bit_len - FinalTerms.matchCtxOffset(&m.ctx, args[0]);
        return FinalTerms.int(&m.ctx, @intCast(rem));
    }
    if (FinalTerms.kindOf(&m.ctx, args[0]) != .binary) return error.Badarg;
    return FinalTerms.int(&m.ctx, @intCast(FinalTerms.bitsOf(&m.ctx, args[0]).bit_len));
}

/// `size/1` — tuple arity OR binary/bitstring byte size (BEAM's polymorphic
/// `size`; on a bitstring it agrees with `byte_size/1`, i.e. `ceil(bit_len/8)`
/// — see `binaryByteSize`).
pub fn size(m: *Machine, args: []const Term) BifError!Term {
    return switch (FinalTerms.kindOf(&m.ctx, args[0])) {
        .tuple => FinalTerms.int(&m.ctx, @intCast(FinalTerms.tupleArity(&m.ctx, args[0]))),
        .binary => FinalTerms.int(&m.ctx, @intCast(binaryByteSize(m, args[0]))),
        else => error.Badarg,
    };
}

pub fn map_size(m: *Machine, args: []const Term) BifError!Term {
    if (FinalTerms.kindOf(&m.ctx, args[0]) != .map) return error.Badarg;
    return FinalTerms.int(&m.ctx, @intCast(FinalTerms.mapSize(&m.ctx, args[0])));
}

/// `map_get(Key, Map)`. E3.10 (DIVERGENCE entry 6b, discharged): a non-map is
/// `error:{badmap, Map}` and an absent key is `error:{badkey, Key}` — the exact
/// BEAM structured reasons (was: simplified `badarg`). In GUARD context the
/// executor still BRANCHES on either (guard behaviour unchanged — `raiseBadmap`/
/// `raiseBadkey` stage via the same `error.Raise` path `Badarg` used).
pub fn map_get(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const map = args[1];
    if (FinalTerms.kindOf(&m.ctx, map) != .map) return m.raiseBadmap(map);
    return FinalTerms.mapGet(&m.ctx, map, key) orelse m.raiseBadkey(key);
}

/// `is_map_key(Key, Map)` → `true`/`false`. E3.10 (entry 6b): a non-map is
/// `error:{badmap, Map}` (was `badarg`); guard behaviour unchanged (branch).
pub fn is_map_key(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const map = args[1];
    if (FinalTerms.kindOf(&m.ctx, map) != .map) return m.raiseBadmap(map);
    return boolTerm(m, FinalTerms.mapGet(&m.ctx, map, key) != null);
}

// ── E3.6: pid/port/reference type predicates ────────────────────────────────
//
// `ubif`s (the guard-context law): TOTAL over every term — unlike
// `is_map_key`/`map_get` above, these NEVER badarg on a well-formed call
// (matching every `is_*` type predicate BEAM ships). Each reuses the E3.5
// `repIsPid`/`repIsPort`/`repIsRef` observer directly — the SAME predicate
// `instr_algebra.zig`'s `typeTestHolds` already flipped truthful for the
// `type_test` opcode; this is only the BIF-call surface for it, no new
// semantics.

pub fn is_pid(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.repIsPid(&m.ctx, args[0]));
}

pub fn is_port(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.repIsPort(&m.ctx, args[0]));
}

pub fn is_reference(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.repIsRef(&m.ctx, args[0]));
}

// ── E3.18: the remaining `erlang:` type/guard predicates ────────────────────
//
// The E2.4 fast-follow siblings of the type-test family (DIVERGENCE_LOG entry
// 13(a)): every one is a `ubif` (guard BIF, TOTAL over every term — never
// badarg) that reuses an EXISTING `term_algebra` observer, no new semantics.
// `is_bitstring` is `repIsBinary ∨ repIsBitstring` — a byte-aligned value is a
// binary (repIsBinary) AND a bitstring; a sub-byte value is only a bitstring
// (repIsBitstring). `is_binary` is the aligned half only.

pub fn is_atom(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.repIsAtom(args[0]));
}
pub fn is_binary(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.repIsBinary(&m.ctx, args[0]));
}
pub fn is_bitstring(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.repIsBinary(&m.ctx, args[0]) or FinalTerms.repIsBitstring(&m.ctx, args[0]));
}
pub fn is_boolean(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, asBool(m, args[0]) != null);
}
pub fn is_float(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.repIsFloat(&m.ctx, args[0]));
}
pub fn is_integer(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, isInteger(m, args[0]));
}
/// `is_integer(Term, LB, UB)` — new in OTP 29 (a pure range-check guard BIF,
/// `erlang.erl`): `true` iff `Term`, `LB`, `UB` are all integers and
/// `LB =< Term =< UB`; `badarg` if `LB` or `UB` is not an integer; `false` if
/// only `Term` is a non-integer. The bound comparison reuses `FinalTerms.compare`
/// (numeric over small+big integers), so the row is exact over the whole integer
/// domain, not just smalls. E3.19: flips the last generic `deferred-E3` ledger
/// row to EQ (a pure function with no real blocker — the honest close).
pub fn is_integer_3(m: *Machine, args: []const Term) BifError!Term {
    const t = args[0];
    const lb = args[1];
    const ub = args[2];
    if (!isInteger(m, lb) or !isInteger(m, ub)) return error.Badarg;
    if (!isInteger(m, t)) return boolTerm(m, false);
    const lb_le = FinalTerms.compare(&m.ctx, lb, t) != .gt; // LB =< Term
    const t_le = FinalTerms.compare(&m.ctx, t, ub) != .gt; // Term =< UB
    return boolTerm(m, lb_le and t_le);
}
pub fn is_list(m: *Machine, args: []const Term) BifError!Term {
    const k = FinalTerms.kindOf(&m.ctx, args[0]);
    return boolTerm(m, k == .nil or k == .cons);
}
pub fn is_map(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.repIsMap(&m.ctx, args[0]));
}
pub fn is_number(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.repIsNumber(&m.ctx, args[0]));
}
pub fn is_tuple(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.kindOf(&m.ctx, args[0]) == .tuple);
}
pub fn is_function_1(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.repIsFun(&m.ctx, args[0]));
}
/// `is_function(F, Arity)` — a fun of exactly `Arity`. Non-small `Arity` (or
/// negative) is `badarg`, matching erts (`erl_bif_op.c`'s `is_function_2`).
pub fn is_function_2(m: *Machine, args: []const Term) BifError!Term {
    const ar = args[1];
    if (!FinalTerms.repIsSmall(ar)) return error.Badarg;
    const want = FinalTerms.smallValOf(ar);
    if (want < 0) return error.Badarg;
    if (!FinalTerms.repIsFun(&m.ctx, args[0])) return boolTerm(m, false);
    return boolTerm(m, @as(i64, FinalTerms.funArity(&m.ctx, args[0])) == want);
}

// `is_record` — the tuple-record structural test (erts `erl_bif_op.c`). zigvm
// has no NATIVE-record term kind (the E3 Task 3 residual), so the native-record
// arm is vacuously false over every representable zigvm term: `is_record/1`
// (native-only) is `false` always; `is_record/2,3` reduce to the tuple test
// {tag-atom [+ matching arity]}. A non-atom tag is `badarg`.
pub fn is_record_1(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return boolTerm(m, false); // no native-record term kind is representable
}
pub fn is_record_2(m: *Machine, args: []const Term) BifError!Term {
    const t = args[0];
    const tag = args[1];
    if (!FinalTerms.repIsAtom(tag)) return error.Badarg;
    if (FinalTerms.kindOf(&m.ctx, t) != .tuple) return boolTerm(m, false);
    if (FinalTerms.tupleArity(&m.ctx, t) < 1) return boolTerm(m, false);
    return boolTerm(m, FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 0), tag));
}
pub fn is_record_3(m: *Machine, args: []const Term) BifError!Term {
    const t = args[0];
    const tag = args[1];
    const sz = args[2];
    if (!FinalTerms.repIsAtom(tag)) return error.Badarg;
    if (FinalTerms.repIsAtom(sz)) return boolTerm(m, false); // native-record arm: unrepresentable
    if (!FinalTerms.repIsSmall(sz)) return error.Badarg;
    if (FinalTerms.kindOf(&m.ctx, t) != .tuple) return boolTerm(m, false);
    const want = FinalTerms.smallValOf(sz);
    if (@as(i64, @intCast(FinalTerms.tupleArity(&m.ctx, t))) != want) return boolTerm(m, false);
    return boolTerm(m, FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 0), tag));
}

// ── arithmetic family ──────────────────────────────────────────────────────

fn needNumbers(m: *Machine, x: Term, y: Term) BifError!void {
    if (!FinalTerms.repIsNumber(&m.ctx, x) or !FinalTerms.repIsNumber(&m.ctx, y)) return error.Badarith;
}
fn needIntegers(m: *Machine, x: Term, y: Term) BifError!void {
    if (!isInteger(m, x) or !isInteger(m, y)) return error.Badarith;
}

pub fn add(m: *Machine, args: []const Term) BifError!Term {
    try needNumbers(m, args[0], args[1]);
    return FinalTerms.add(&m.ctx, args[0], args[1]);
}

pub fn sub(m: *Machine, args: []const Term) BifError!Term {
    try needNumbers(m, args[0], args[1]);
    return FinalTerms.add(&m.ctx, args[0], try FinalTerms.negate(&m.ctx, args[1]));
}

pub fn mul(m: *Machine, args: []const Term) BifError!Term {
    try needNumbers(m, args[0], args[1]);
    return FinalTerms.mul(&m.ctx, args[0], args[1]);
}

pub fn idiv(m: *Machine, args: []const Term) BifError!Term {
    try needIntegers(m, args[0], args[1]);
    return FinalTerms.idiv(&m.ctx, args[0], args[1]);
}

pub fn irem(m: *Machine, args: []const Term) BifError!Term {
    try needIntegers(m, args[0], args[1]);
    return FinalTerms.irem(&m.ctx, args[0], args[1]);
}

pub fn band(m: *Machine, args: []const Term) BifError!Term {
    try needIntegers(m, args[0], args[1]);
    return FinalTerms.band(&m.ctx, args[0], args[1]);
}
pub fn bor(m: *Machine, args: []const Term) BifError!Term {
    try needIntegers(m, args[0], args[1]);
    return FinalTerms.bor(&m.ctx, args[0], args[1]);
}
pub fn bxor(m: *Machine, args: []const Term) BifError!Term {
    try needIntegers(m, args[0], args[1]);
    return FinalTerms.bxor(&m.ctx, args[0], args[1]);
}
pub fn bnot(m: *Machine, args: []const Term) BifError!Term {
    if (!isInteger(m, args[0])) return error.Badarith;
    return FinalTerms.bnot(&m.ctx, args[0]);
}
pub fn bsl(m: *Machine, args: []const Term) BifError!Term {
    try needIntegers(m, args[0], args[1]);
    return FinalTerms.bsl(&m.ctx, args[0], args[1]);
}
pub fn bsr(m: *Machine, args: []const Term) BifError!Term {
    try needIntegers(m, args[0], args[1]);
    return FinalTerms.bsr(&m.ctx, args[0], args[1]);
}

/// unary `-/1`: bignum-aware negation. Non-number → badarith.
pub fn unary_minus(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsNumber(&m.ctx, args[0])) return error.Badarith;
    return FinalTerms.negate(&m.ctx, args[0]);
}

/// E3.18: unary `+/1` — the identity on any number, `badarith` otherwise
/// (erts `splus_1` returns the argument unchanged).
pub fn unary_plus(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsNumber(&m.ctx, args[0])) return error.Badarith;
    return args[0];
}

/// E3.18: float division `//2` — ALWAYS a float result (BEAM `/` never yields
/// an integer). Division by zero and a non-number operand are `badarith`.
pub fn fdiv(m: *Machine, args: []const Term) BifError!Term {
    try needNumbers(m, args[0], args[1]);
    const y = FinalTerms.numToF64Of(&m.ctx, args[1]);
    if (y == 0.0) return error.Badarith;
    return FinalTerms.float(&m.ctx, FinalTerms.numToF64Of(&m.ctx, args[0]) / y);
}

/// E3.18: `min/2`/`max/2` — the arith term order (`erlang:min/max`, ubif). TOTAL
/// over every pair; ties return the FIRST argument (erts `erl_bif_op.c`: `min`
/// returns arg1 when `arg1 =< arg2`, `max` returns arg1 when `arg1 >= arg2`).
pub fn min_2(m: *Machine, args: []const Term) BifError!Term {
    return if (FinalTerms.compare(&m.ctx, args[0], args[1]) == .gt) args[1] else args[0];
}
pub fn max_2(m: *Machine, args: []const Term) BifError!Term {
    return if (FinalTerms.compare(&m.ctx, args[0], args[1]) == .lt) args[1] else args[0];
}

/// `abs/1` — bignum-aware absolute value (sign flip; no arithmetic width growth).
pub fn abs(m: *Machine, args: []const Term) BifError!Term {
    const w = args[0];
    if (FinalTerms.repIsFloat(&m.ctx, w)) return FinalTerms.float(&m.ctx, @abs(FinalTerms.floatValOf(&m.ctx, w)));
    if (FinalTerms.repIsSmall(w)) return FinalTerms.intFromI128(&m.ctx, @as(i128, @intCast(@abs(FinalTerms.smallValOf(w)))));
    if (FinalTerms.repIsBig(&m.ctx, w)) {
        return if (FinalTerms.bigPartsOf(&m.ctx, w).positive) w else FinalTerms.negate(&m.ctx, w);
    }
    return error.Badarg; // BEAM: abs on a non-number is badarg
}

// ── rounding / float conversion ────────────────────────────────────────────

/// A finite float rounded to i128 range, or badarith if it exceeds i128 (the
/// documented bignum deferral). Integer inputs never reach here.
fn floatToInt(m: *Machine, f: f64) BifError!Term {
    if (!std.math.isFinite(f)) return error.Badarith;
    // i128 spans ~±1.70141e38; anything beyond needs a bignum (deferred).
    if (f >= 1.7014118346046922e38 or f < -1.7014118346046922e38) return error.Badarith;
    return FinalTerms.intFromI128(&m.ctx, @intFromFloat(f));
}

/// `float/1` — number → float term. Non-number → badarg.
pub fn float(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsNumber(&m.ctx, args[0])) return error.Badarg;
    return FinalTerms.float(&m.ctx, FinalTerms.numToF64Of(&m.ctx, args[0]));
}

fn roundWith(m: *Machine, args: []const Term, comptime op: fn (f64) f64) BifError!Term {
    const w = args[0];
    if (isInteger(m, w)) return w; // already integral
    if (!FinalTerms.repIsFloat(&m.ctx, w)) return error.Badarg;
    return floatToInt(m, op(FinalTerms.floatValOf(&m.ctx, w)));
}

pub fn trunc(m: *Machine, args: []const Term) BifError!Term {
    return roundWith(m, args, struct {
        fn f(x: f64) f64 {
            return @trunc(x);
        }
    }.f);
}
pub fn round(m: *Machine, args: []const Term) BifError!Term {
    return roundWith(m, args, struct {
        fn f(x: f64) f64 {
            return std.math.round(x); // half away from zero (BEAM semantics)
        }
    }.f);
}
pub fn floor(m: *Machine, args: []const Term) BifError!Term {
    return roundWith(m, args, struct {
        fn f(x: f64) f64 {
            return @floor(x);
        }
    }.f);
}
pub fn ceil(m: *Machine, args: []const Term) BifError!Term {
    return roundWith(m, args, struct {
        fn f(x: f64) f64 {
            return @ceil(x);
        }
    }.f);
}

// ── comparisons (TOTAL over all terms; return true/false) ──────────────────

pub fn cmp_eq(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.compare(&m.ctx, args[0], args[1]) == .eq);
}
pub fn cmp_ne(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.compare(&m.ctx, args[0], args[1]) != .eq);
}
pub fn cmp_lt(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.compare(&m.ctx, args[0], args[1]) == .lt);
}
pub fn cmp_gt(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.compare(&m.ctx, args[0], args[1]) == .gt);
}
pub fn cmp_le(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.compare(&m.ctx, args[0], args[1]) != .gt);
}
pub fn cmp_ge(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.compare(&m.ctx, args[0], args[1]) != .lt);
}
pub fn cmp_exact_eq(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, FinalTerms.eqlExact(&m.ctx, args[0], args[1]));
}
pub fn cmp_exact_ne(m: *Machine, args: []const Term) BifError!Term {
    return boolTerm(m, !FinalTerms.eqlExact(&m.ctx, args[0], args[1]));
}

// ── boolean guards ─────────────────────────────────────────────────────────

pub fn bool_not(m: *Machine, args: []const Term) BifError!Term {
    const b = asBool(m, args[0]) orelse return error.Badarg;
    return boolTerm(m, !b);
}
pub fn bool_and(m: *Machine, args: []const Term) BifError!Term {
    const a = asBool(m, args[0]) orelse return error.Badarg;
    const b = asBool(m, args[1]) orelse return error.Badarg;
    return boolTerm(m, a and b);
}
pub fn bool_or(m: *Machine, args: []const Term) BifError!Term {
    const a = asBool(m, args[0]) orelse return error.Badarg;
    const b = asBool(m, args[1]) orelse return error.Badarg;
    return boolTerm(m, a or b);
}
pub fn bool_xor(m: *Machine, args: []const Term) BifError!Term {
    const a = asBool(m, args[0]) orelse return error.Badarg;
    const b = asBool(m, args[1]) orelse return error.Badarg;
    return boolTerm(m, a != b);
}

// ── E3.10: the exception-raising BIF family ─────────────────────────────────
//
// These are the FIRST BIFs that RAISE an arbitrary-class exception rather than
// returning a value or a fixed `badarg`/`badarith`. Each stages the exception
// on `m.bif_raise` via `Machine.bifRaise` and returns `error.Raise`; the
// `bif_call` executor unwinds it through `raiseWith` (BODY context) or — for a
// guard-usable BIF — branches (there are none here: error/throw/exit/raise/3/
// nif_error are NEVER guard BIFs, so the compiler always emits them in body
// context with no fail label, and the raise always fires). They are pure over
// the CALLING Machine (no pid/ref/Vm/scheduler state), hence — like `self/0`
// and the E3.9 pdict BIFs — reachable end-to-end via `bif1`/`bif2`/`bif3` from
// a compiled `.beam`, so they classify EQ. An UNCAUGHT raise crashes the
// Machine (`raiseWith`'s empty-catch-stack halt path); under the proc scheduler
// that `.crashed` status terminates the process with the reason (proc.zig
// `interpret`), so `exit/1` is the correct process-exit "raise form" (and,
// unlike the E3.7 `.exit_proc` opcode trap, it RESPECTS an enclosing `catch`).
//
// Stacktrace handling is E1-minimal (`nil`) until Task 11; `error/2`'s `Args`
// and `error/3`'s `Args`/`Options` only shape the (deferred) stacktrace, so the
// REASON is `args[0]` in every arity (documented — not a silent drop).

/// `erlang:error/1` — raise `error:Reason`.
pub fn error_1(m: *Machine, args: []const Term) BifError!Term {
    return m.bifRaise(.error_, args[0]);
}

/// `erlang:error/2` — raise `error:Reason`; `Args` (args[1]) decorates only the
/// stacktrace (E1-minimal nil), so the reason is `args[0]`.
pub fn error_2(m: *Machine, args: []const Term) BifError!Term {
    return m.bifRaise(.error_, args[0]);
}

/// `erlang:error/3` — raise `error:Reason`; `Args`/`Options` (args[1]/args[2])
/// decorate only the stacktrace/error_info (deferred), so the reason is args[0].
pub fn error_3(m: *Machine, args: []const Term) BifError!Term {
    return m.bifRaise(.error_, args[0]);
}

/// `erlang:throw/1` — raise `throw:Value`. Caught bare by `catch` (a thrown
/// value is caught as itself — the class-discrimination law's throw arm).
pub fn throw_1(m: *Machine, args: []const Term) BifError!Term {
    return m.bifRaise(.throw_, args[0]);
}

/// `erlang:exit/1` — raise `exit:Reason` (the process-exit "raise form"). Caught
/// as `{'EXIT',Reason}` by `catch`; uncaught, terminates the process with Reason.
pub fn exit_1(m: *Machine, args: []const Term) BifError!Term {
    return m.bifRaise(.exit_, args[0]);
}

/// `erlang:nif_error/1` — behaves exactly like `error/1` (BEAM uses it to mark a
/// stub a NIF should have replaced; the raised exception is identical).
pub fn nif_error_1(m: *Machine, args: []const Term) BifError!Term {
    return m.bifRaise(.error_, args[0]);
}

/// `erlang:nif_error/2` — like `error/2` (reason args[0], Args decorate trace).
pub fn nif_error_2(m: *Machine, args: []const Term) BifError!Term {
    return m.bifRaise(.error_, args[0]);
}

/// `erlang:raise(Class, Reason, Stacktrace)` — the BIF form. Raises with the
/// EXACT class named by `args[0]` (error/exit/throw). BEAM's contract (entry 2d):
/// an invalid class (or malformed stacktrace) makes raise/3 RETURN the atom
/// `badarg` as its VALUE — it does NOT raise. `Stacktrace` (args[2]) is
/// accepted but not re-cooked (E1-minimal). Mutant target: hardcoding `.error_`
/// here loses a re-raised throw/exit class (the class-preservation law).
pub fn raise_3(m: *Machine, args: []const Term) BifError!Term {
    const cls = m.classOfAtom(args[0]) orelse
        return FinalTerms.atom(&m.ctx, m.badarg); // bad class: a VALUE, no raise
    return m.bifRaise(cls, args[1]);
}

// ============================================================================
// E31-T2: erlang:decode_packet/3 — the pure `binary -> {ok|more|error,…}`
// packet framer. A faithful port of erts `decode_packet_3`
// (third_party/otp/erts/emulator/beam/erl_bif_port.c) over the FRAMING kernel
// in `bin_algebra.zig` (`packetGetLength`/`packetGetBody`, ports of erts
// `packet_get_length`/`packet_get_body`). NO inet-driver dependency.
//
// ## Return contract (byte-EQ to OTP for the covered types)
//   {ok, PacketBodyBin, RestBin} | {more, Length|undefined} | {error, invalid}
// with the SAME framing/more/error verdicts OTP produces:
//   packet_sz < 0            → {error, invalid}
//   packet_sz == 0           → {more, undefined}
//   packet_sz  > bin_sz      → {more, packet_sz}
//   0 < packet_sz <= bin_sz  → {ok, <sub-binary body>, <sub-binary rest>}
// Body is `packet_get_body`'s sub-range (sz1/2/4 skip the length header, fcgi
// trims trailing padding, everything else is the whole packet); Rest is the
// bytes after packet_sz. Sub-binaries are materialised via `binPart` (a copy)
// — observationally EQ to OTP's reference sub-binaries (byte equality only).
//
// ## COVERED Type values (genuine byte-EQ, law-proven below)
//   0 | raw, 1, 2, 4, line, sunrm, cdr, fcgi, tpkt, asn1  — every type whose
//   erts `packet_parse` returns code 0 (a plain-binary body). Options honoured:
//   {packet_size,N} (max_plen cap), {line_length,N} (trunc_len), and
//   {line_delimiter,C} (only for `line`, C =< 255) — matching the exact
//   OTP option-validation surface (a bad option / bad value → badarg).
//
// ## STRUCTURED Type values
//   http / http_bin — IMPLEMENTED (E41-T1): the REQUEST/RESPONSE-line parse
//   (`{http_request, Method, Uri, {Maj,Min}}` / `{http_response, {Maj,Min},
//   Status, Phrase}` / `{http_error, Line}`), byte-EQ to OTP over the curated
//   `decode_packet_SUITE` http cases (7 known methods → atoms; `abs_path`/
//   `absoluteURI`/`scheme`/`'*'` URI forms; charlist vs binary bodies). Headers
//   only parse under `httph` (a header line under `http` is `{http_error,_}`).
//   httph / httph_bin / ssl_tls — STILL DEFERRED (raise badarg): the header-only
//   continuation + the SSL record parser (the erts header-name atom hash). A
//   documented divergence kept OUT of the differential suite until they land
//   (ranked `cp-decode-packet-structured`) — never a silent false-EQ. So
//   `decode_packet/3` stays JUSTIFIED (resolvable via the dispatch-needed-deferred
//   carve-out) until httph*/ssl_tls are byte-EQ.

const ba = @import("../bin_algebra.zig");

fn pktAtom(m: *Machine, name: []const u8) BifError!Term {
    return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern(name) catch return error.OutOfMemory);
}

const PacketTypeClass = union(enum) { framing: ba.PacketType, http: bool, httph: bool, ssl_tls, unknown };

/// Classify decode_packet/3's arg-1 exactly like the OTP `switch (BIF_ARG_1)`.
/// `.http = false` is `http` (charlist bodies), `.http = true` is `http_bin`
/// (binary bodies) — E41-T1 implements the REQUEST/RESPONSE-line parse. `httph`/
/// `httph_bin` (header-only) and `ssl_tls` stay `.deferred`.
fn classifyPacketType(m: *Machine, w: Term) PacketTypeClass {
    if (FinalTerms.repIsSmall(w)) {
        return switch (FinalTerms.smallValOf(w)) {
            0 => .{ .framing = .raw },
            1 => .{ .framing = .sz1 },
            2 => .{ .framing = .sz2 },
            4 => .{ .framing = .sz4 },
            else => .unknown,
        };
    }
    if (!FinalTerms.repIsAtom(w)) return .unknown;
    const name = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(w));
    const framing = [_]struct { []const u8, ba.PacketType }{
        .{ "raw", .raw },   .{ "line", .line }, .{ "sunrm", .sunrm },
        .{ "cdr", .cdr },   .{ "fcgi", .fcgi }, .{ "tpkt", .tpkt },
        .{ "asn1", .asn1 },
    };
    inline for (framing) |f| {
        if (std.mem.eql(u8, name, f[0])) return .{ .framing = f[1] };
    }
    if (std.mem.eql(u8, name, "http")) return .{ .http = false };
    if (std.mem.eql(u8, name, "http_bin")) return .{ .http = true };
    if (std.mem.eql(u8, name, "httph")) return .{ .httph = false };
    if (std.mem.eql(u8, name, "httph_bin")) return .{ .httph = true };
    if (std.mem.eql(u8, name, "ssl_tls")) return .ssl_tls;
    return .unknown;
}

// ── E42-T1: the httph/httph_bin header-line parser (erts packet_parse_http) ──
//
// A header line `Field: Value` → `{http_header, Bit, Field, Reserved, Value}`; an
// empty line → `http_eoh`. `Bit`/`Field` come from the 52-entry erts header table
// (case-INSENSITIVE match → the canonical Bit + atom); an unknown field → Bit 0 and
// the http-capitalised name. `Reserved` is the ORIGINAL field string as-input; the
// value has leading whitespace stripped (trailing kept). Bodies are charlists for
// `httph`, binaries for `httph_bin`. Continuation (RFC obs-fold) header lines ARE
// handled (cp-decode-packet-fold): the framing loop below spans lines whose first
// byte is SP/HT, and the folded value keeps the embedded `\r\n<ws>` RAW (byte-EQ
// with the erts decode_packet_SUITE Multi-Line oracle).

/// The erts header table, in Bit order (1..52). Index i ⇒ Bit i+1.
const http_hdr_table = [_][]const u8{
    "Cache-Control",       "Connection",        "Date",              "Pragma",
    "Transfer-Encoding",   "Upgrade",           "Via",               "Accept",
    "Accept-Charset",      "Accept-Encoding",   "Accept-Language",   "Authorization",
    "From",                "Host",              "If-Modified-Since", "If-Match",
    "If-None-Match",       "If-Range",          "If-Unmodified-Since", "Max-Forwards",
    "Proxy-Authorization", "Range",             "Referer",           "User-Agent",
    "Age",                 "Location",          "Proxy-Authenticate", "Public",
    "Retry-After",         "Server",            "Vary",              "Warning",
    "Www-Authenticate",    "Allow",             "Content-Base",      "Content-Encoding",
    "Content-Language",    "Content-Length",    "Content-Location",  "Content-Md5",
    "Content-Range",       "Content-Type",      "Etag",              "Expires",
    "Last-Modified",       "Accept-Ranges",     "Set-Cookie",        "Set-Cookie2",
    "X-Forwarded-For",     "Cookie",            "Keep-Alive",        "Proxy-Connection",
};

/// erts `http_capitalize`: the first char and every char after a '-' is uppercased,
/// the rest lowercased ("x-foo" → "X-Foo"). Writes into `buf` (caller-owned).
fn httpCapitalize(field: []const u8, buf: []u8) void {
    var up = true;
    for (field, 0..) |c, i| {
        buf[i] = if (up) std.ascii.toUpper(c) else std.ascii.toLower(c);
        up = (c == '-');
    }
}

const HdrHit = struct { bit: i64, canonical: []const u8 }; // canonical="" ⇒ unknown

fn lookupHeader(field: []const u8) HdrHit {
    for (http_hdr_table, 0..) |h, i| {
        if (std.ascii.eqlIgnoreCase(field, h)) return .{ .bit = @intCast(i + 1), .canonical = h };
    }
    return .{ .bit = 0, .canonical = "" };
}

// ── E41-T1: the http/http_bin structured parser (erts packet_parse_http) ─────
//
// For `http`/`http_bin`, decode_packet frames on the line (\n) then parses the
// line into a REQUEST or RESPONSE term; anything that is neither (a header, an
// empty line, garbage) is `{http_error, Line}` — exactly what the OTP-30 oracle
// returns (headers only parse under `httph`, deferred). Bodies are charlists for
// `http`, binaries for `http_bin`; recognised methods and schemes are atoms in both.

/// A string body: a binary for `http_bin`, a charlist for `http`.
fn strOrBin(m: *Machine, bytes: []const u8, bin: bool) BifError!Term {
    if (bin) return FinalTerms.binary(&m.ctx, bytes) catch error.OutOfMemory;
    var lst = FinalTerms.nil(&m.ctx);
    var i = bytes.len;
    while (i > 0) {
        i -= 1;
        lst = FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, bytes[i]), lst) catch return error.OutOfMemory;
    }
    return lst;
}

fn isWs(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// The 7 erts-recognised HTTP methods → an atom; anything else → a string/binary.
fn methodTerm(m: *Machine, tok: []const u8, bin: bool) BifError!Term {
    const known = [_][]const u8{ "OPTIONS", "GET", "HEAD", "POST", "PUT", "DELETE", "TRACE" };
    for (known) |k| if (std.mem.eql(u8, tok, k)) return pktAtom(m, k);
    return strOrBin(m, tok, bin);
}

/// Parse `HTTP/Maj.Min` → `{Maj, Min}` (or null if not that shape).
fn versionTerm(m: *Machine, tok: []const u8) BifError!?Term {
    if (!std.mem.startsWith(u8, tok, "HTTP/")) return null;
    const v = tok["HTTP/".len..];
    const dot = std.mem.indexOfScalar(u8, v, '.') orelse return null;
    const maj = std.fmt.parseInt(i64, v[0..dot], 10) catch return null;
    const min = std.fmt.parseInt(i64, v[dot + 1 ..], 10) catch return null;
    return FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, maj), FinalTerms.int(&m.ctx, min) }) catch error.OutOfMemory;
}

/// Parse a request URI into the erts term: `'*'` | `{abs_path,P}` |
/// `{absoluteURI,Scheme,Host,Port|undefined,Path}` | `{scheme,Host,Port}`.
fn uriTerm(m: *Machine, uri: []const u8, bin: bool) BifError!Term {
    if (std.mem.eql(u8, uri, "*")) return pktAtom(m, "*");
    if (uri.len > 0 and uri[0] == '/') {
        return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "abs_path"), try strOrBin(m, uri, bin) }) catch error.OutOfMemory;
    }
    if (std.mem.indexOf(u8, uri, "://")) |sep| {
        const scheme = uri[0..sep];
        var rest = uri[sep + 3 ..];
        // split host[:port] from /path
        const slash = std.mem.indexOfScalar(u8, rest, '/');
        const host_port = if (slash) |s| rest[0..s] else rest;
        const path = if (slash) |s| rest[s..] else "/";
        var host = host_port;
        var port_term = try pktAtom(m, "undefined");
        if (std.mem.indexOfScalar(u8, host_port, ':')) |c| {
            host = host_port[0..c];
            const p = std.fmt.parseInt(i64, host_port[c + 1 ..], 10) catch return httpErrorFallback;
            port_term = FinalTerms.int(&m.ctx, p);
        }
        // scheme atom: http/https recognised case-insensitively; else a string.
        const scheme_term = try schemeAtom(m, scheme, bin);
        return FinalTerms.tuple(&m.ctx, &.{
            try pktAtom(m, "absoluteURI"), scheme_term, try strOrBin(m, host, bin), port_term, try strOrBin(m, path, bin),
        }) catch error.OutOfMemory;
    }
    if (std.mem.indexOfScalar(u8, uri, ':')) |c| {
        return FinalTerms.tuple(&m.ctx, &.{
            try pktAtom(m, "scheme"), try strOrBin(m, uri[0..c], bin), try strOrBin(m, uri[c + 1 ..], bin),
        }) catch error.OutOfMemory;
    }
    // a bare token (no '/', no ':') — erts treats it as an abs_path.
    return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "abs_path"), try strOrBin(m, uri, bin) }) catch error.OutOfMemory;
}

const httpErrorFallback = error.Badarg; // sentinel: caught by buildHttp to emit {http_error,_}

fn schemeAtom(m: *Machine, scheme: []const u8, bin: bool) BifError!Term {
    if (std.ascii.eqlIgnoreCase(scheme, "http")) return pktAtom(m, "http");
    if (std.ascii.eqlIgnoreCase(scheme, "https")) return pktAtom(m, "https");
    return strOrBin(m, scheme, bin);
}

/// tokenise on runs of whitespace: returns up to 3 tokens + the remainder after
/// the 2nd whitespace run (for the response phrase, which may contain spaces).
const Tok = struct { toks: [3][]const u8, n: usize, after2: []const u8 };
fn tokenize3(line: []const u8) Tok {
    var r = Tok{ .toks = undefined, .n = 0, .after2 = "" };
    var i: usize = 0;
    while (r.n < 3) {
        while (i < line.len and isWs(line[i])) i += 1;
        if (i >= line.len) break;
        const start = i;
        while (i < line.len and !isWs(line[i])) i += 1;
        r.toks[r.n] = line[start..i];
        r.n += 1;
        if (r.n == 2) {
            var j = i;
            while (j < line.len and isWs(line[j])) j += 1;
            r.after2 = line[j..];
        }
    }
    return r;
}

/// Build the http/http_bin term for one framed packet (`packet` includes the
/// trailing \n / \r\n). `bin` selects charlist vs binary bodies.
fn buildHttp(m: *Machine, packet_in: []const u8, bin: bool) BifError!Term {
    // `packet_in` is a slice INTO the term heap (`ctx.words`); building charlist/
    // tuple terms below GROWS that heap and would DANGLE the slice (a real bug the
    // first run segfaulted on). Dupe it into a stable buffer first.
    const packet = m.ctx.gpa.dupe(u8, packet_in) catch return error.OutOfMemory;
    defer m.ctx.gpa.free(packet);

    // strip the trailing terminator to get the line content.
    var end = packet.len;
    if (end > 0 and packet[end - 1] == '\n') end -= 1;
    if (end > 0 and packet[end - 1] == '\r') end -= 1;
    const line = packet[0..end];

    const parsed: ?Term = buildRequestOrResponse(m, line, bin) catch |e| switch (e) {
        error.Badarg => null, // a malformed request/response ⇒ fall to http_error
        else => return e,
    };
    if (parsed) |t| return t;
    // {http_error, WholeLineIncludingTerminator}
    return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "http_error"), try strOrBin(m, packet, bin) }) catch error.OutOfMemory;
}

fn buildRequestOrResponse(m: *Machine, line: []const u8, bin: bool) BifError!?Term {
    // RESPONSE: starts with "HTTP/".
    if (std.mem.startsWith(u8, line, "HTTP/")) {
        const t = tokenize3(line);
        if (t.n < 2) return null;
        const ver = (try versionTerm(m, t.toks[0])) orelse return null;
        const status = std.fmt.parseInt(i64, t.toks[1], 10) catch return null;
        const phrase = try strOrBin(m, t.after2, bin); // may be empty
        return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "http_response"), ver, FinalTerms.int(&m.ctx, status), phrase }) catch error.OutOfMemory;
    }
    // REQUEST: METHOD SP URI SP HTTP/Ver.
    const t = tokenize3(line);
    if (t.n != 3) return null;
    const ver = (try versionTerm(m, t.toks[2])) orelse return null;
    const method = try methodTerm(m, t.toks[0], bin);
    const uri = try uriTerm(m, t.toks[1], bin);
    return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "http_request"), method, uri, ver }) catch error.OutOfMemory;
}

/// Build the httph header term for one framed packet (`packet` includes the
/// trailing \n / \r\n). An empty line → `http_eoh`; else `{http_header, Bit, Field,
/// Reserved, Value}`. `bin` selects charlist vs binary bodies.
fn buildHeader(m: *Machine, packet_in: []const u8, bin: bool) BifError!Term {
    const packet = m.ctx.gpa.dupe(u8, packet_in) catch return error.OutOfMemory;
    defer m.ctx.gpa.free(packet);

    var end = packet.len;
    if (end > 0 and packet[end - 1] == '\n') end -= 1;
    if (end > 0 and packet[end - 1] == '\r') end -= 1;
    const content = packet[0..end];
    if (content.len == 0) return pktAtom(m, "http_eoh");

    const colon = std.mem.indexOfScalar(u8, content, ':') orelse
        return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "http_error"), try strOrBin(m, packet, bin) }) catch error.OutOfMemory;
    const field = content[0..colon];
    var vraw = content[colon + 1 ..];
    var vs: usize = 0;
    while (vs < vraw.len and isWs(vraw[vs])) vs += 1;
    const value = vraw[vs..];

    const hit = lookupHeader(field);
    const field_term = if (hit.canonical.len > 0)
        try pktAtom(m, hit.canonical)
    else blk: {
        const buf = m.ctx.gpa.alloc(u8, field.len) catch return error.OutOfMemory;
        defer m.ctx.gpa.free(buf);
        httpCapitalize(field, buf);
        break :blk try strOrBin(m, buf, bin);
    };
    return FinalTerms.tuple(&m.ctx, &.{
        try pktAtom(m, "http_header"),
        FinalTerms.int(&m.ctx, hit.bit),
        field_term,
        try strOrBin(m, field, bin), // Reserved = the ORIGINAL field string as-input
        try strOrBin(m, value, bin),
    }) catch error.OutOfMemory;
}

/// A decode_packet option value: a non-negative small integer =< UINT_MAX
/// (mirrors erts `term_to_Uint(v,&val) && val <= UINT_MAX`). Anything else
/// (negative, non-integer, or a bignum > UINT_MAX) makes the option invalid.
fn optUint(w: Term) ?u32 {
    if (!FinalTerms.repIsSmall(w)) return null;
    const v = FinalTerms.smallValOf(w);
    if (v < 0 or v > 0xFFFFFFFF) return null;
    return @intCast(v);
}

pub fn decode_packet_3(m: *Machine, args: []const Term) BifError!Term {
    // (1) Parse the packet type FIRST (OTP checks arg-1 before arg-2/arg-3).
    const class = classifyPacketType(m, args[0]);
    // E41-T1: `http`/`http_bin` frame like `line` (\n) then PARSE the line; the
    // remaining structured types (httph*/ssl_tls) are still deferred.
    const http_bin: ?bool = switch (class) {
        .http => |b| b,
        else => null,
    };
    const httph_bin: ?bool = switch (class) {
        .httph => |b| b,
        else => null,
    };
    const is_line = switch (class) {
        .framing => |t| t == .line,
        else => false,
    };
    // E42-T1: ssl_tls parses a TLS RECORD (fixed 5-byte header) — handled before
    // the generic framing (it needs arg-2 to be a binary first, checked below).
    const is_ssl_tls = switch (class) {
        .ssl_tls => true,
        else => false,
    };
    const htype: ba.PacketType = switch (class) {
        .framing => |t| t,
        .http, .httph => .line, // http/httph frame on \n like line, then parse
        .ssl_tls => .raw, // placeholder; the ssl_tls branch below returns early
        // Unknown arg-1 → OTP badarg (am_badopt ext info, not modeled) == badarg.
        .unknown => return error.Badarg,
    };

    // (2) arg-2 must be a (byte-aligned) binary.
    if (!FinalTerms.repIsBinary(&m.ctx, args[1])) return error.Badarg;

    // (3) Walk the options proper-list; a non-list arg-3, an improper tail, a
    //     non-2-tuple element, a bad key, or a bad value all → badarg.
    var max_plen: u32 = 0;
    var trunc_len: u32 = 0;
    var delimiter: u8 = '\n';
    {
        var opts = args[2];
        while (true) {
            const k = FinalTerms.kindOf(&m.ctx, opts);
            if (k == .nil) break;
            if (k != .cons) return error.Badarg;
            const head = FinalTerms.listHead(&m.ctx, opts);
            opts = FinalTerms.listTail(&m.ctx, opts);
            if (FinalTerms.kindOf(&m.ctx, head) != .tuple or
                FinalTerms.tupleArity(&m.ctx, head) != 2) return error.Badarg;
            const key = FinalTerms.tupleElem(&m.ctx, head, 0);
            if (!FinalTerms.repIsAtom(key)) return error.Badarg;
            const val = optUint(FinalTerms.tupleElem(&m.ctx, head, 1)) orelse
                return error.Badarg;
            const kname = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(key));
            if (std.mem.eql(u8, kname, "packet_size")) {
                max_plen = val;
            } else if (std.mem.eql(u8, kname, "line_length")) {
                trunc_len = val;
            } else if (std.mem.eql(u8, kname, "line_delimiter") and
                is_line and val <= 255)
            {
                delimiter = @intCast(val);
            } else return error.Badarg;
        }
    }

    // (4) Frame the packet (pure kernel), then build the result term.
    const bytes = FinalTerms.binBytes(&m.ctx, args[1]);
    const bin_sz = bytes.len;

    // E42-T1: ssl_tls — a TLS record `Type(1) Maj(1) Min(1) Len(2 BE) Data(Len)` →
    // `{ssl_tls, [], ContentType, {Maj,Min}, Data}` (Data always a binary; the 2nd
    // element is the empty-list Port placeholder). {more, undefined} if < 5 header
    // bytes; {more, 5+Len} if the data is short.
    if (is_ssl_tls) {
        if (bin_sz < 5) return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "more"), try pktAtom(m, "undefined") }) catch error.OutOfMemory;
        const ct = bytes[0];
        const maj = bytes[1];
        const min = bytes[2];
        const rlen = (@as(usize, bytes[3]) << 8) | @as(usize, bytes[4]);
        const total = 5 + rlen;
        if (bin_sz < total) return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "more"), FinalTerms.int(&m.ctx, @intCast(total)) }) catch error.OutOfMemory;
        const data = FinalTerms.binPart(&m.ctx, args[1], 5, rlen) catch return error.OutOfMemory;
        const rest = FinalTerms.binPart(&m.ctx, args[1], total, bin_sz - total) catch return error.OutOfMemory;
        const ver = FinalTerms.tuple(&m.ctx, &.{ FinalTerms.int(&m.ctx, maj), FinalTerms.int(&m.ctx, min) }) catch return error.OutOfMemory;
        const rec = FinalTerms.tuple(&m.ctx, &.{
            try pktAtom(m, "ssl_tls"), FinalTerms.nil(&m.ctx), FinalTerms.int(&m.ctx, ct), ver, data,
        }) catch return error.OutOfMemory;
        return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "ok"), rec, rest }) catch error.OutOfMemory;
    }

    // E42-T1: httph/httph_bin have their OWN framing — a header line needs a byte
    // AFTER its \n (the erts continuation-line lookahead), so a buffer ending at
    // \n is {more, undefined}. The empty line (http_eoh) needs no lookahead.
    if (httph_bin) |hbin| {
        // cp-decode-packet-fold: find the end of the (possibly FOLDED) header. erts
        // `packet_parser.c` continuation rule: a header value continues across a line
        // whose first byte is SP/HT (`SP(ptr2+1) && plen>2`), so the framed packet
        // spans all folded lines and stops at the first line NOT so continued. The
        // empty line (`http_eoh`) is never folded. A buffer ending at a header's \n
        // (or mid-fold) with no following byte is `{more, undefined}` — the lookahead
        // needs the next line's first byte to decide. The folded VALUE keeps the
        // embedded `\r\n<ws>` RAW (decode_packet_SUITE Multi-Line case).
        const psz: usize = blk: {
            var line_start: usize = 0;
            while (true) {
                const rel = std.mem.indexOfScalar(u8, bytes[line_start..], '\n') orelse
                    return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "more"), try pktAtom(m, "undefined") }) catch error.OutOfMemory;
                const nl = line_start + rel;
                // The FIRST line empty (\r\n or \n)? → http_eoh, ends immediately.
                if (line_start == 0) {
                    var cend = nl;
                    if (cend > 0 and bytes[cend - 1] == '\r') cend -= 1;
                    if (cend == 0) break :blk nl + 1;
                }
                const plen = nl - line_start + 1; // current line length incl \n
                // Continuation lookahead: the byte AFTER \n decides fold vs done.
                if (nl + 1 >= bin_sz)
                    return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "more"), try pktAtom(m, "undefined") }) catch error.OutOfMemory;
                if (isWs(bytes[nl + 1]) and plen > 2) {
                    line_start = nl + 1; // folded: keep scanning
                    continue;
                }
                break :blk nl + 1; // header complete at this \n
            }
        };
        const hdr = try buildHeader(m, bytes[0..psz], hbin);
        const rest = FinalTerms.binPart(&m.ctx, args[1], psz, bin_sz - psz) catch return error.OutOfMemory;
        return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "ok"), hdr, rest }) catch error.OutOfMemory;
    }

    const packet_sz = ba.packetGetLength(htype, bytes, max_plen, trunc_len, delimiter);

    if (packet_sz < 0) {
        return FinalTerms.tuple(&m.ctx, &.{
            try pktAtom(m, "error"),
            try pktAtom(m, "invalid"),
        }) catch error.OutOfMemory;
    }
    if (packet_sz == 0 or @as(usize, @intCast(packet_sz)) > bin_sz) {
        const len_term = if (packet_sz == 0)
            try pktAtom(m, "undefined")
        else
            FinalTerms.int(&m.ctx, packet_sz);
        return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "more"), len_term }) catch
            error.OutOfMemory;
    }

    // Whole packet present → {ok, Body, Rest}.
    const psz: usize = @intCast(packet_sz);
    const rest_bin = FinalTerms.binPart(&m.ctx, args[1], psz, bin_sz - psz) catch
        return error.OutOfMemory;

    // E41-T1: for http/http_bin the Body is the PARSED structured term.
    if (http_bin) |bin| {
        const http_term = try buildHttp(m, bytes[0..psz], bin);
        return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "ok"), http_term, rest_bin }) catch error.OutOfMemory;
    }

    const body = ba.packetGetBody(htype, bytes, psz);
    const body_bin = FinalTerms.binPart(&m.ctx, args[1], body.off, body.len) catch
        return error.OutOfMemory;
    return FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, "ok"), body_bin, rest_bin }) catch
        error.OutOfMemory;
}

// ============================================================================
// E4.2: get_module_info/1,2 — the reflection API behind M:module_info/0,1.
// Reads the retained per-module metadata (`Machine.mod_meta`, set by
// `cli.runMulti`): attributes/compile are the ETF-decoded Attr/CInf chunks, md5
// is `beam_loader.computeMd5`'s checksum, exports/functions are derived from
// `Machine.exports`. Mirrors erts `erl_bif_info.c:get_module_info`.
// ============================================================================

const etf = @import("../etf.zig");

fn keyAtom(m: *Machine, name: []const u8) BifError!Term {
    return FinalTerms.atom(&m.ctx, m.ctx.atoms.intern(name) catch return error.OutOfMemory);
}

fn findMeta(m: *Machine, mod: ta.AtomIdx) ?*const ia.ModMeta {
    for (m.mod_meta) |*meta| if (meta.module == mod) return meta;
    return null;
}

/// The exported {F,A} pairs of `mod`, drawn from `Machine.exports`. NOTE: erts'
/// `module_info(exports)` returns them in internal-atom-INDEX order (its global
/// export table is sorted by atom index, then CONS-reversed) — an ordering this
/// VM's atom table does not reproduce, so this list is NOT byte-EQ to OTP's
/// (the `deferred-E4-modinfo` residual; see bif_gen.ml / DIVERGENCE entry 29).
fn exportsList(m: *Machine, mod: ta.AtomIdx) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = m.exports.len;
    while (i > 0) {
        i -= 1;
        const e = m.exports[i];
        if (e.module != mod) continue;
        const fa = FinalTerms.tuple(&m.ctx, &.{
            FinalTerms.atom(&m.ctx, e.func),
            FinalTerms.int(&m.ctx, @intCast(e.arity)),
        }) catch return error.OutOfMemory;
        acc = FinalTerms.cons(&m.ctx, fa, acc) catch return error.OutOfMemory;
    }
    return acc;
}

/// Decode a retained ETF chunk (`Attr`/`CInf`) to its proplist term; an absent
/// chunk denotes `[]` (erts returns NIL when `attr_ptr`/`compile_ptr` is NULL).
fn decodeChunk(m: *Machine, bytes: []const u8) BifError!Term {
    if (bytes.len == 0) return FinalTerms.nil(&m.ctx);
    return etf.decode(m.gpa, &m.ctx, bytes) catch return error.Badarg;
}

/// DIVERGENCE 700: `module_info(functions)` — the FULL function set of `mod`
/// (every LOCAL + exported + auto `module_info/0,1`), read from the pc→source
/// `m.locs` table (every function is delimited by a `func_info` op the loader
/// interns into `m.locs` as `{m,f,a}`), deduped by `{func,arity}`. This is the
/// complete set OTP returns — `exports ⊆ functions` — unlike the old code, which
/// returned only the export index (locals lost). SET-equality with OTP; the list
/// ORDER stays the deferred-E4-modinfo residual (not byte-EQ), same as `exports`.
fn functionsList(m: *Machine, mod: ta.AtomIdx) BifError!Term {
    var fs: std.ArrayList([2]u32) = .empty;
    defer fs.deinit(m.gpa);
    for (m.locs) |loc| {
        if (loc.m != mod or loc.f == 0) continue; // 0 = the pre-func_info preamble
        var dup = false;
        for (fs.items) |p| {
            if (p[0] == loc.f and p[1] == loc.a) {
                dup = true;
                break;
            }
        }
        if (!dup) fs.append(m.gpa, .{ loc.f, loc.a }) catch return error.OutOfMemory;
    }
    var acc = FinalTerms.nil(&m.ctx);
    var i = fs.items.len;
    while (i > 0) {
        i -= 1;
        const fa = FinalTerms.tuple(&m.ctx, &.{
            FinalTerms.atom(&m.ctx, fs.items[i][0]),
            FinalTerms.int(&m.ctx, @intCast(fs.items[i][1])),
        }) catch return error.OutOfMemory;
        acc = FinalTerms.cons(&m.ctx, fa, acc) catch return error.OutOfMemory;
    }
    return acc;
}

/// The value of a single `get_module_info(Mod, What)` key. `null` == erts'
/// THE_NON_VALUE (an unknown key / unloaded module → the caller badargs).
fn moduleInfoItem(m: *Machine, meta: *const ia.ModMeta, what: []const u8) BifError!?Term {
    if (std.mem.eql(u8, what, "module"))
        return FinalTerms.atom(&m.ctx, meta.module);
    if (std.mem.eql(u8, what, "exports"))
        return try exportsList(m, meta.module);
    if (std.mem.eql(u8, what, "functions"))
        return try functionsList(m, meta.module); // DIVERGENCE 700: FULL set from m.locs
    if (std.mem.eql(u8, what, "nifs"))
        return FinalTerms.nil(&m.ctx); // no NIF-loaded module in this VM (load_nif
    // is deferred-E4); a module with no NIFs denotes [] exactly as OTP.
    if (std.mem.eql(u8, what, "attributes"))
        return try decodeChunk(m, meta.attr_bytes);
    if (std.mem.eql(u8, what, "compile"))
        return try decodeChunk(m, meta.compile_bytes);
    if (std.mem.eql(u8, what, "md5")) {
        if (!meta.has_md5) return null;
        return FinalTerms.binary(&m.ctx, &meta.md5) catch return error.OutOfMemory;
    }
    if (std.mem.eql(u8, what, "native"))
        return FinalTerms.atom(&m.ctx, m.bool_false); // interpreter-only VM
    return null;
}

/// `erlang:get_module_info/1` (behind `M:module_info/0`): the proplist erts'
/// `module_info_0` builds — `[{module,M},{exports,E},{attributes,A},{compile,C},
/// {md5,MD5}]` (that exact order).
pub fn get_module_info_1(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const mod = FinalTerms.atomIdxOf(args[0]);
    const meta = findMeta(m, mod) orelse return error.Badarg;
    const keys = [_][]const u8{ "md5", "compile", "attributes", "exports", "module" };
    var acc = FinalTerms.nil(&m.ctx);
    for (keys) |k| {
        const v = (try moduleInfoItem(m, meta, k)) orelse return error.Badarg;
        const tup = FinalTerms.tuple(&m.ctx, &.{ try keyAtom(m, k), v }) catch return error.OutOfMemory;
        acc = FinalTerms.cons(&m.ctx, tup, acc) catch return error.OutOfMemory;
    }
    return acc;
}

/// `erlang:get_module_info/2` (behind `M:module_info/1`).
pub fn get_module_info_2(m: *Machine, args: []const Term) BifError!Term {
    if (!FinalTerms.repIsAtom(args[0]) or !FinalTerms.repIsAtom(args[1])) return error.Badarg;
    const mod = FinalTerms.atomIdxOf(args[0]);
    const meta = findMeta(m, mod) orelse return error.Badarg;
    const what = m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(args[1]));
    return (try moduleInfoItem(m, meta, what)) orelse error.Badarg;
}

// ============================================================================
// E2.4 DENOTATION LAWS — each family fn == its wired term-algebra denotation.
// Args are passed as already-resolved terms (exactly as the executor delivers
// them). The seed is echoed by the std.testing harness on failure.
// ============================================================================

const AtomTable = ta.AtomTable;

fn expectInt(m: *Machine, got: BifError!Term, want: i64) !void {
    const t = try got;
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, t, FinalTerms.int(&m.ctx, want)));
}
fn expectAtom(m: *Machine, got: BifError!Term, want: ta.AtomIdx) !void {
    const t = try got;
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, t, FinalTerms.atom(&m.ctx, want)));
}

test "LAW E4.2 get_module_info metadata round-trip (module/md5/exports/attributes) + rejection" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const modn = try atoms.intern("mymod");
    const f_a = try atoms.intern("foo");
    const f_b = try atoms.intern("bar");

    // exports for mymod (ExpT order: foo/1 then bar/2) + an unrelated module's
    // export that must be FILTERED OUT of mymod's exports list.
    const other = try atoms.intern("othermod");
    const exps = [_]ia.Export{
        .{ .module = modn, .func = f_a, .arity = 1, .pc = 0 },
        .{ .module = modn, .func = f_b, .arity = 2, .pc = 1 },
        .{ .module = other, .func = f_a, .arity = 0, .pc = 2 },
    };
    m.exports = &exps;

    // attributes: a real ETF-encoded proplist [{k,1}] round-trips through decode.
    const attr_term = try FinalTerms.cons(&m.ctx, try FinalTerms.tuple(&m.ctx, &.{
        FinalTerms.atom(&m.ctx, try atoms.intern("k")),
        FinalTerms.int(&m.ctx, 1),
    }), FinalTerms.nil(&m.ctx));
    var attr_enc = try etf.encode(gpa, &m.ctx, attr_term);
    defer attr_enc.deinit(gpa);

    var md5: [16]u8 = undefined;
    for (&md5, 0..) |*b, i| b.* = @intCast(i * 7 % 256);
    const meta = [_]ia.ModMeta{.{ .module = modn, .attr_bytes = attr_enc.items, .compile_bytes = &.{}, .md5 = md5, .has_md5 = true }};
    m.mod_meta = &meta;

    const mod_t = FinalTerms.atom(&m.ctx, modn);

    // module → the atom itself.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try get_module_info_2(&m, &.{ mod_t, try keyAtom(&m, "module") }), mod_t));
    // md5 → the exact stored 16-byte binary.
    const got_md5 = try get_module_info_2(&m, &.{ mod_t, try keyAtom(&m, "md5") });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got_md5, try FinalTerms.binary(&m.ctx, &md5)));
    // exports → [{foo,1},{bar,2}] in ExpT order, othermod filtered out.
    const got_exp = try get_module_info_2(&m, &.{ mod_t, try keyAtom(&m, "exports") });
    const want_exp = try FinalTerms.cons(&m.ctx, try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.atom(&m.ctx, f_a), FinalTerms.int(&m.ctx, 1) }), try FinalTerms.cons(&m.ctx, try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.atom(&m.ctx, f_b), FinalTerms.int(&m.ctx, 2) }), FinalTerms.nil(&m.ctx)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got_exp, want_exp));
    // attributes → the decoded [{k,1}] (ETF homomorphism: decode∘encode == id).
    const got_attr = try get_module_info_2(&m, &.{ mod_t, try keyAtom(&m, "attributes") });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, got_attr, attr_term));

    // get_module_info/1 → the erts proplist ORDER [{module},{exports},{attributes},{compile},{md5}].
    const pl = try get_module_info_1(&m, &.{mod_t});
    const h0 = FinalTerms.listHead(&m.ctx, pl);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, h0, 0), try keyAtom(&m, "module")));
    const h1 = FinalTerms.listHead(&m.ctx, FinalTerms.listTail(&m.ctx, pl));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, h1, 0), try keyAtom(&m, "exports")));

    // REJECTION: an unloaded module and an unknown key both badarg.
    const nope = FinalTerms.atom(&m.ctx, try atoms.intern("nope"));
    try std.testing.expectError(error.Badarg, get_module_info_1(&m, &.{nope}));
    try std.testing.expectError(error.Badarg, get_module_info_2(&m, &.{ mod_t, try keyAtom(&m, "no_such_key") }));
    try std.testing.expectError(error.Badarg, get_module_info_1(&m, &.{FinalTerms.int(&m.ctx, 3)}));
}

test "LAW gap-modinfo-functions (DIVERGENCE 700): module_info(functions) returns the FULL set — LOCALS + exports + module_info/0,1 — read from m.locs, deduped by {f,a}; exports ⊆ functions; other modules filtered" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const modn = try atoms.intern("mymod");
    const other = try atoms.intern("othermod");
    const foo = try atoms.intern("foo"); // exported
    const bar = try atoms.intern("bar"); // exported
    const baz = try atoms.intern("baz"); // LOCAL (non-exported)
    const mi = try atoms.intern("module_info");
    // pc→loc table: multiple pcs per fn (dedup), a LOCAL, module_info/0,1, an
    // othermod entry (filtered), and the f==0 preamble (skipped).
    const locs = [_]ia.Loc{
        .{ .m = modn, .f = foo, .a = 1 }, .{ .m = modn, .f = foo, .a = 1 }, // duplicate
        .{ .m = modn, .f = bar, .a = 2 },
        .{ .m = modn, .f = baz, .a = 0 }, // the LOCAL — absent from the export table
        .{ .m = modn, .f = mi, .a = 0 },  .{ .m = modn, .f = mi, .a = 1 },
        .{ .m = other, .f = foo, .a = 9 }, // other module → filtered out
        .{ .m = 0, .f = 0, .a = 0 }, // pre-func_info preamble → skipped
    };
    m.locs = &locs;
    const exps = [_]ia.Export{ .{ .module = modn, .func = foo, .arity = 1, .pc = 0 }, .{ .module = modn, .func = bar, .arity = 2, .pc = 1 } };
    m.exports = &exps;
    const meta = [_]ia.ModMeta{.{ .module = modn }};
    m.mod_meta = &meta;

    const H = struct {
        fn has(mm: *Machine, list: Term, f: ta.AtomIdx, a: i64) bool {
            var cur = list;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) {
                const h = FinalTerms.listHead(&mm.ctx, cur);
                if (FinalTerms.tupleArity(&mm.ctx, h) == 2 and
                    FinalTerms.atomIdxOf(FinalTerms.tupleElem(&mm.ctx, h, 0)) == f and
                    FinalTerms.smallValOf(FinalTerms.tupleElem(&mm.ctx, h, 1)) == a) return true;
                cur = FinalTerms.listTail(&mm.ctx, cur);
            }
            return false;
        }
        fn len(mm: *Machine, list: Term) usize {
            var n: usize = 0;
            var cur = list;
            while (FinalTerms.kindOf(&mm.ctx, cur) == .cons) : (cur = FinalTerms.listTail(&mm.ctx, cur)) n += 1;
            return n;
        }
    };
    const fns = try get_module_info_2(&m, &.{ FinalTerms.atom(&m.ctx, modn), try keyAtom(&m, "functions") });
    try std.testing.expectEqual(@as(usize, 5), H.len(&m, fns)); // 5 DISTINCT fns (dedup + other filtered)
    try std.testing.expect(H.has(&m, fns, foo, 1));
    try std.testing.expect(H.has(&m, fns, bar, 2));
    try std.testing.expect(H.has(&m, fns, baz, 0)); // ★ the LOCAL — the RANK-5 fix
    try std.testing.expect(H.has(&m, fns, mi, 0));
    try std.testing.expect(H.has(&m, fns, mi, 1));
    try std.testing.expect(!H.has(&m, fns, foo, 9)); // othermod filtered
    // exports ⊆ functions
    try std.testing.expect(H.has(&m, fns, foo, 1) and H.has(&m, fns, bar, 2));
}

test "LAW E2.4 accessors denote their term-algebra observation (element is 1-based)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const c = FinalTerms.atom(&m.ctx, try atoms.intern("c"));
    const tup = try FinalTerms.tuple(&m.ctx, &.{ a, b, c });

    // element/2 — 1-based (MUTANT 1: 0-based indexing breaks these two asserts).
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try element(&m, &.{ FinalTerms.int(&m.ctx, 1), tup }), a));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try element(&m, &.{ FinalTerms.int(&m.ctx, 3), tup }), c));
    try expectInt(&m, tuple_size(&m, &.{tup}), 3);
    try expectInt(&m, size(&m, &.{tup}), 3);

    // hd/tl/length over [a,b,c].
    const lst = try FinalTerms.cons(&m.ctx, a, try FinalTerms.cons(&m.ctx, b, try FinalTerms.cons(&m.ctx, c, FinalTerms.nil(&m.ctx))));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try hd(&m, &.{lst}), a));
    try expectInt(&m, length(&m, &.{lst}), 3);
    // tl denotes the tail.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try hd(&m, &.{try tl(&m, &.{lst})}), b));

    // byte_size / size over a binary.
    const bin = try FinalTerms.binary(&m.ctx, "hello");
    try expectInt(&m, byte_size(&m, &.{bin}), 5);
    try expectInt(&m, size(&m, &.{bin}), 5);

    // map_size / map_get / is_map_key over #{a => 1, b => 2}.
    const mp = try FinalTerms.mapNew(&m.ctx, &.{ a, b }, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) });
    try expectInt(&m, map_size(&m, &.{mp}), 2);
    try expectInt(&m, map_get(&m, &.{ b, mp }), 2);
    try expectAtom(&m, is_map_key(&m, &.{ a, mp }), m.bool_true);
    try expectAtom(&m, is_map_key(&m, &.{ c, mp }), m.bool_false);

    // Rejection: out-of-range / wrong-kind → badarg (never a panic).
    try std.testing.expectError(error.Badarg, element(&m, &.{ FinalTerms.int(&m.ctx, 0), tup }));
    try std.testing.expectError(error.Badarg, element(&m, &.{ FinalTerms.int(&m.ctx, 4), tup }));
    try std.testing.expectError(error.Badarg, hd(&m, &.{FinalTerms.nil(&m.ctx)}));
    try std.testing.expectError(error.Badarg, tuple_size(&m, &.{a}));
    // E3.10 (entry 6b, discharged): map_get on an absent key raises the
    // STRUCTURED reason error:{badkey,Key} (was simplified `badarg`). The fn
    // returns `error.Raise` staging the tuple on `m.bif_raise`.
    try std.testing.expectError(error.Raise, map_get(&m, &.{ c, mp })); // absent key -> {badkey,c}
    {
        const staged = m.bif_raise.?;
        m.bif_raise = null;
        try std.testing.expectEqual(ia.ExcClass.error_, staged.class);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, staged.reason, 0), FinalTerms.atom(&m.ctx, m.badkey_atom)));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, staged.reason, 1), c));
    }
}

test "LAW E3.1-fix: byte_size/size over bitstrings == ceil(bit_len/8), agrees with the binary twin" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // <<>> — the empty bitstring: byte_size == 0.
    const empty = try FinalTerms.bitstring(&m.ctx, &.{}, 0);
    try expectInt(&m, byte_size(&m, &.{empty}), 0);
    try expectInt(&m, size(&m, &.{empty}), 0);

    // <<0:1>> — sub-byte, 1 bit: byte_size == 1 (not 0, not `bit_len`).
    const one_bit = try FinalTerms.bitstring(&m.ctx, &.{0}, 1);
    try expectInt(&m, byte_size(&m, &.{one_bit}), 1);
    try expectInt(&m, size(&m, &.{one_bit}), 1);

    // <<255,3:3>> — 8+3=11 bits: byte_size == ceil(11/8) == 2.
    const eleven_bits = try FinalTerms.bitstring(&m.ctx, &.{ 255, 0b011_00000 }, 11);
    try expectInt(&m, byte_size(&m, &.{eleven_bits}), 2);
    try expectInt(&m, size(&m, &.{eleven_bits}), 2);

    // Aligned bitstring (bit_len % 8 == 0) agrees with the equal-content binary.
    const aligned_bits = try FinalTerms.bitstring(&m.ctx, "hello", 40);
    const aligned_bin = try FinalTerms.binary(&m.ctx, "hello");
    try expectInt(&m, byte_size(&m, &.{aligned_bits}), 5);
    try expectInt(&m, byte_size(&m, &.{aligned_bin}), 5);

    // REGRESSION for the OOB-panic landmine (E3.1-fix): a bit_len large
    // enough that misreading it AS A BYTE COUNT (the pre-fix `binBytes`
    // path) would slice far past this term's actual (small) word
    // allocation — this is the last heap allocation, so the old code
    // panicked here instead of returning a wrong-but-safe value.
    const last_alloc = try FinalTerms.bitstring(&m.ctx, &.{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x80 }, 61);
    try expectInt(&m, byte_size(&m, &.{last_alloc}), 8); // ceil(61/8) == 8
    try expectInt(&m, size(&m, &.{last_alloc}), 8);
}

test "LAW E3.1-fix: byte_size(bitstring) == (bit_len+7)/8 (seeded)" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xB512E3);
    const random = prng.random();

    for (0..100) |iter| {
        var atoms = AtomTable.init(gpa);
        defer atoms.deinit();
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();

        var buf: [16]u8 = undefined;
        random.bytes(&buf);
        const bit_len = random.uintLessThan(usize, buf.len * 8 + 1);
        const t = try FinalTerms.bitstring(&m.ctx, &buf, bit_len);
        const want: i64 = @intCast((bit_len + 7) / 8);
        const got = byte_size(&m, &.{t}) catch |err| {
            std.debug.print("LAW FAILED: byte_size(bitstring) errored (seed=0xB512E3, iter={d}, bit_len={d}): {any}\n", .{ iter, bit_len, err });
            return err;
        };
        if (!FinalTerms.eqlExact(&m.ctx, got, FinalTerms.int(&m.ctx, want))) {
            std.debug.print("LAW FAILED: byte_size(bitstring) (seed=0xB512E3, iter={d}, bit_len={d})\n", .{ iter, bit_len });
            return error.LawViolated;
        }
    }
}

test "LAW E3.2: bit_size/1 is TRUTHFUL over unaligned values (bit_size(<<..:N>>) == N), and agrees with byte_size*8 when aligned" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // <<>> — empty: bit_size == 0.
    const empty = try FinalTerms.bitstring(&m.ctx, &.{}, 0);
    try expectInt(&m, bit_size(&m, &.{empty}), 0);

    // <<0:1>> — sub-byte, 1 bit: bit_size == 1 (NOT byte_size*8 == 8 — the
    // truthfulness this task adds; before, only a `byte_size*8` proxy would
    // have been possible, since no term-level bitstring `bit_len` existed).
    const one_bit = try FinalTerms.bitstring(&m.ctx, &.{0}, 1);
    try expectInt(&m, bit_size(&m, &.{one_bit}), 1);

    // <<255,3:3>> — 8+3=11 bits: bit_size == 11 (byte_size == 2, so
    // byte_size*8 == 16 would be WRONG — this is exactly the truthfulness gap).
    const eleven_bits = try FinalTerms.bitstring(&m.ctx, &.{ 255, 0b011_00000 }, 11);
    try expectInt(&m, bit_size(&m, &.{eleven_bits}), 11);

    // Aligned bitstring / true binary agreement: bit_size == byte_size*8.
    const aligned_bits = try FinalTerms.bitstring(&m.ctx, "hello", 40);
    const aligned_bin = try FinalTerms.binary(&m.ctx, "hello");
    try expectInt(&m, bit_size(&m, &.{aligned_bits}), 40);
    try expectInt(&m, bit_size(&m, &.{aligned_bin}), 40);

    // Non-binary/bitstring → badarg (never a panic).
    try std.testing.expectError(error.Badarg, bit_size(&m, &.{FinalTerms.int(&m.ctx, 1)}));

    // bs-unaligned-tail: bit_size/byte_size of a MATCH CONTEXT = the REMAINING
    // view (erts unified bitstrings: the ctx IS an ErlSubBits; `bit_size(sb)`
    // = end - start). The compiler applies bit_size DIRECTLY to the context
    // (`{tr,_,{t_bs_context,_}}`) when the argument is a match tail — a wrong
    // answer here broke `bit_size(T)` after `<<_:3,Y:5,T/bits>>` (returned the
    // ctx box's word-size instead of 8; the fleet finding).
    const cbin = try FinalTerms.binary(&m.ctx, &.{ 0xFF, 0xFF });
    const mc = try FinalTerms.makeMatchCtx(&m.ctx, cbin, 8); // 8 of 16 consumed
    try expectInt(&m, bit_size(&m, &.{mc}), 8);
    try expectInt(&m, byte_size(&m, &.{mc}), 1);
    const mc3 = try FinalTerms.makeMatchCtx(&m.ctx, cbin, 3); // 13 remaining
    try expectInt(&m, bit_size(&m, &.{mc3}), 13);
    try expectInt(&m, byte_size(&m, &.{mc3}), 2); // ceil(13/8)
}

test "LAW E3.2: bit_size(bitstring) == bit_len exactly (seeded, no byte-rounding)" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xB512E4);
    const random = prng.random();

    for (0..100) |iter| {
        var atoms = AtomTable.init(gpa);
        defer atoms.deinit();
        var m = try Machine.init(gpa, &atoms);
        defer m.deinit();

        var buf: [16]u8 = undefined;
        random.bytes(&buf);
        const bit_len = random.uintLessThan(usize, buf.len * 8 + 1);
        const t = try FinalTerms.bitstring(&m.ctx, &buf, bit_len);
        const got = bit_size(&m, &.{t}) catch |err| {
            std.debug.print("LAW FAILED: bit_size(bitstring) errored (seed=0xB512E4, iter={d}, bit_len={d}): {any}\n", .{ iter, bit_len, err });
            return err;
        };
        if (!FinalTerms.eqlExact(&m.ctx, got, FinalTerms.int(&m.ctx, @intCast(bit_len)))) {
            std.debug.print("LAW FAILED: bit_size(bitstring) (seed=0xB512E4, iter={d}, bit_len={d})\n", .{ iter, bit_len });
            return error.LawViolated;
        }
    }
}

test "LAW E2.4 arith/sign/abs denote ℤ (small-int); non-number → badarith" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const i = struct {
        fn f(mm: *Machine, v: i64) Term {
            return FinalTerms.int(&mm.ctx, v);
        }
    }.f;

    try expectInt(&m, add(&m, &.{ i(&m, 40), i(&m, 2) }), 42);
    try expectInt(&m, sub(&m, &.{ i(&m, 40), i(&m, 2) }), 38);
    try expectInt(&m, mul(&m, &.{ i(&m, 6), i(&m, 7) }), 42);
    try expectInt(&m, idiv(&m, &.{ i(&m, 7), i(&m, 2) }), 3);
    try expectInt(&m, irem(&m, &.{ i(&m, 7), i(&m, 2) }), 1);
    try expectInt(&m, band(&m, &.{ i(&m, 6), i(&m, 3) }), 2);
    try expectInt(&m, bor(&m, &.{ i(&m, 6), i(&m, 1) }), 7);
    try expectInt(&m, bxor(&m, &.{ i(&m, 6), i(&m, 3) }), 5);
    try expectInt(&m, bnot(&m, &.{i(&m, 5)}), -6);
    try expectInt(&m, bsl(&m, &.{ i(&m, 1), i(&m, 4) }), 16);
    try expectInt(&m, bsr(&m, &.{ i(&m, 16), i(&m, 2) }), 4);
    try expectInt(&m, unary_minus(&m, &.{i(&m, 7)}), -7);
    try expectInt(&m, abs(&m, &.{i(&m, -3)}), 3);
    try expectInt(&m, abs(&m, &.{i(&m, 3)}), 3);

    // Rejections (clean errors, never a panic).
    const atom_a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    try std.testing.expectError(error.Badarith, add(&m, &.{ atom_a, i(&m, 1) }));
    try std.testing.expectError(error.Badarith, idiv(&m, &.{ i(&m, 1), i(&m, 0) })); // div by zero
    try std.testing.expectError(error.Badarith, band(&m, &.{ i(&m, 1), atom_a }));
}

test "LAW E2.4 comparisons are total and denote the term order (true/false atoms)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    const onef = FinalTerms.float(&m.ctx, 1.0);

    try expectAtom(&m, cmp_lt(&m, &.{ one, two }), m.bool_true);
    try expectAtom(&m, cmp_lt(&m, &.{ two, one }), m.bool_false);
    try expectAtom(&m, cmp_gt(&m, &.{ two, one }), m.bool_true);
    try expectAtom(&m, cmp_le(&m, &.{ one, one }), m.bool_true);
    try expectAtom(&m, cmp_ge(&m, &.{ one, two }), m.bool_false);
    // arith `==` collapses 1 and 1.0; exact `=:=` distinguishes them.
    try expectAtom(&m, cmp_eq(&m, &.{ one, onef }), m.bool_true);
    try expectAtom(&m, cmp_exact_eq(&m, &.{ one, onef }), m.bool_false);
    try expectAtom(&m, cmp_exact_ne(&m, &.{ one, onef }), m.bool_true);
    try expectAtom(&m, cmp_ne(&m, &.{ one, two }), m.bool_true);
}

test "LAW E2.4 bool guards over true/false; non-bool → badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const T = FinalTerms.atom(&m.ctx, m.bool_true);
    const F = FinalTerms.atom(&m.ctx, m.bool_false);

    try expectAtom(&m, bool_not(&m, &.{T}), m.bool_false);
    try expectAtom(&m, bool_not(&m, &.{F}), m.bool_true);
    try expectAtom(&m, bool_and(&m, &.{ T, F }), m.bool_false);
    try expectAtom(&m, bool_or(&m, &.{ T, F }), m.bool_true);
    try expectAtom(&m, bool_xor(&m, &.{ T, T }), m.bool_false);
    const atom_x = FinalTerms.atom(&m.ctx, try atoms.intern("x"));
    try std.testing.expectError(error.Badarg, bool_not(&m, &.{atom_x}));
    try std.testing.expectError(error.Badarg, bool_and(&m, &.{ T, atom_x }));
}

test "LAW E2.4 rounding: integer passthrough, float rounding, float/1 conversion" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const f = struct {
        fn g(mm: *Machine, v: f64) Term {
            return FinalTerms.float(&mm.ctx, v);
        }
    }.g;

    try expectInt(&m, trunc(&m, &.{f(&m, 2.7)}), 2);
    try expectInt(&m, trunc(&m, &.{f(&m, -2.7)}), -2);
    try expectInt(&m, round(&m, &.{f(&m, 2.5)}), 3); // half away from zero
    try expectInt(&m, round(&m, &.{f(&m, -2.5)}), -3);
    try expectInt(&m, floor(&m, &.{f(&m, -1.5)}), -2);
    try expectInt(&m, ceil(&m, &.{f(&m, 1.1)}), 2);
    // integer input passes through unchanged.
    try expectInt(&m, trunc(&m, &.{FinalTerms.int(&m.ctx, 5)}), 5);
    try expectInt(&m, floor(&m, &.{FinalTerms.int(&m.ctx, 5)}), 5);
    // float/1 converts int → float.
    const r = try float(&m, &.{FinalTerms.int(&m.ctx, 3)});
    try std.testing.expect(FinalTerms.repIsFloat(&m.ctx, r));
    try std.testing.expect(FinalTerms.floatValOf(&m.ctx, r) == 3.0);
    // non-number → badarg.
    try std.testing.expectError(error.Badarg, trunc(&m, &.{FinalTerms.atom(&m.ctx, m.bool_true)}));
    try std.testing.expectError(error.Badarg, float(&m, &.{FinalTerms.atom(&m.ctx, m.bool_true)}));
}

test "LAW E2.4 MIGRATION: erlang.add/sub == the pre-E2.4 term-algebra path" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    var prng = std.Random.DefaultPrng.init(0xADD_5AB);
    const random = prng.random();

    for (0..500) |_| {
        const x = FinalTerms.int(&m.ctx, random.int(i32));
        const y = FinalTerms.int(&m.ctx, random.int(i32));
        // add: identical to FinalTerms.add (the old `.add` path).
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try add(&m, &.{ x, y }), try FinalTerms.add(&m.ctx, x, y)));
        // sub: identical to add∘negate (the old `.sub` path was negate then add).
        const want = try FinalTerms.add(&m.ctx, x, try FinalTerms.negate(&m.ctx, y));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try sub(&m, &.{ x, y }), want));
    }
}

test "LAW E3.19 is_integer/3 (Term,LB,UB): inclusive range check, badarg on non-int bounds" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const T = FinalTerms.atom(&m.ctx, m.bool_true);
    const F = FinalTerms.atom(&m.ctx, m.bool_false);
    const notint = FinalTerms.atom(&m.ctx, m.bool_true); // an atom stands in for "not an integer"
    const i = FinalTerms.int;
    // In-range, and the INCLUSIVE boundaries (kills the `<`/`>` exclusive mutant m1).
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try is_integer_3(&m, &.{ i(&m.ctx, 15), i(&m.ctx, 0), i(&m.ctx, 1024) }), T));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try is_integer_3(&m, &.{ i(&m.ctx, 0), i(&m.ctx, 0), i(&m.ctx, 1024) }), T)); // Term == LB
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try is_integer_3(&m, &.{ i(&m.ctx, 1024), i(&m.ctx, 0), i(&m.ctx, 1024) }), T)); // Term == UB
    // Out of range -> false.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try is_integer_3(&m, &.{ i(&m.ctx, -1), i(&m.ctx, 0), i(&m.ctx, 1) }), F));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try is_integer_3(&m, &.{ i(&m.ctx, 2), i(&m.ctx, 0), i(&m.ctx, 1) }), F));
    // Non-integer Term (with integer bounds) -> false, NOT badarg (kills mutant m2).
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try is_integer_3(&m, &.{ notint, i(&m.ctx, 0), i(&m.ctx, 10) }), F));
    // Non-integer LB or UB -> badarg (the documented failure).
    try std.testing.expectError(error.Badarg, is_integer_3(&m, &.{ i(&m.ctx, 5), notint, i(&m.ctx, 10) }));
    try std.testing.expectError(error.Badarg, is_integer_3(&m, &.{ i(&m.ctx, 5), i(&m.ctx, 0), notint }));
}

// E3.10: the exception-raising BIF family. Each fn stages a class-tagged
// exception on `m.bif_raise` and returns `error.Raise`; these laws call the fns
// DIRECTLY (the E3.8 precedent — they are implemented + law-proven here but
// `deferred-E4-procdispatch` until Task 12 wires call_ext, so the differential engine
// does not reach them). Each asserts the STAGED (class, reason) is exactly right.
fn expectRaises(m: *Machine, got: BifError!Term, class: ia.ExcClass, reason: Term) !void {
    try std.testing.expectError(error.Raise, got);
    const staged = m.bif_raise orelse return error.TestUnexpectedResult;
    m.bif_raise = null;
    try std.testing.expectEqual(class, staged.class);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, staged.reason, reason));
}

test "LAW E3.10 exception BIFs stage the right class+reason (error/throw/exit/nif_error)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const r = FinalTerms.atom(&m.ctx, try atoms.intern("boom"));
    const args = FinalTerms.nil(&m.ctx); // the Args/Options decorations (ignored)
    // error/1,2,3 -> error:Reason (Args/Options only shape the deferred trace).
    try expectRaises(&m, error_1(&m, &.{r}), .error_, r);
    try expectRaises(&m, error_2(&m, &.{ r, args }), .error_, r);
    try expectRaises(&m, error_3(&m, &.{ r, args, args }), .error_, r);
    // throw/1 -> throw:Value; exit/1 -> exit:Reason.
    try expectRaises(&m, throw_1(&m, &.{r}), .throw_, r);
    try expectRaises(&m, exit_1(&m, &.{r}), .exit_, r);
    // nif_error/1,2 behave exactly like error/1,2.
    try expectRaises(&m, nif_error_1(&m, &.{r}), .error_, r);
    try expectRaises(&m, nif_error_2(&m, &.{ r, args }), .error_, r);
}

test "LAW E3.10 raise/3 raises the named class; a bad class RETURNS badarg (no raise)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const r = FinalTerms.int(&m.ctx, 7);
    // A valid class atom raises with that EXACT class (mutant: hardcode error).
    try expectRaises(&m, raise_3(&m, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("throw")), r, FinalTerms.nil(&m.ctx) }), .throw_, r);
    try expectRaises(&m, raise_3(&m, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("exit")), r, FinalTerms.nil(&m.ctx) }), .exit_, r);
    // A NON-class first arg RETURNS the atom `badarg` as a VALUE — does NOT raise
    // (entry 2d). `bif_raise` stays null.
    const bad = try raise_3(&m, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("nope")), r, FinalTerms.nil(&m.ctx) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, bad, FinalTerms.atom(&m.ctx, m.badarg)));
    try std.testing.expect(m.bif_raise == null);
}

test "LAW E3.6: is_pid/is_port/is_reference are TRUTHFUL exactly on their own kind (never badarg)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const p = try FinalTerms.pid(&m.ctx, 3, 1);
    const r = try FinalTerms.freshRef(&m.ctx);
    const port = try FinalTerms.port(&m.ctx, 9);
    const other = FinalTerms.int(&m.ctx, 42);

    // Truthful exactly on own kind.
    try std.testing.expect(asBool(&m, try is_pid(&m, &.{p})).?);
    try std.testing.expect(!asBool(&m, try is_pid(&m, &.{r})).?);
    try std.testing.expect(!asBool(&m, try is_pid(&m, &.{port})).?);
    try std.testing.expect(!asBool(&m, try is_pid(&m, &.{other})).?);

    try std.testing.expect(asBool(&m, try is_reference(&m, &.{r})).?);
    try std.testing.expect(!asBool(&m, try is_reference(&m, &.{p})).?);
    try std.testing.expect(!asBool(&m, try is_reference(&m, &.{other})).?);

    try std.testing.expect(asBool(&m, try is_port(&m, &.{port})).?);
    try std.testing.expect(!asBool(&m, try is_port(&m, &.{p})).?);
    try std.testing.expect(!asBool(&m, try is_port(&m, &.{other})).?);

    // The guard-context law: never badarg (unlike map_get/is_map_key above),
    // over EVERY kind — an ordinary atom/tuple/list is a clean `false`.
    const atom_a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    try std.testing.expect(!asBool(&m, try is_pid(&m, &.{atom_a})).?);
    try std.testing.expect(!asBool(&m, try is_reference(&m, &.{FinalTerms.nil(&m.ctx)})).?);
}

test "LAW E3.18: type predicates partition the term domain (TRUE on exactly one kind, never badarg)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const tt = FinalTerms.atom(&m.ctx, m.bool_true);
    const i = FinalTerms.int(&m.ctx, 7);
    const fl = FinalTerms.float(&m.ctx, 1.5);
    const bin = try FinalTerms.binary(&m.ctx, "hi");
    const bits = try FinalTerms.bitstring(&m.ctx, &.{0}, 3); // <<0:3>> — sub-byte
    const nil = FinalTerms.nil(&m.ctx);
    const lst = try FinalTerms.cons(&m.ctx, i, nil);
    const tup = try FinalTerms.tuple(&m.ctx, &.{ a, i });
    const mp = try FinalTerms.mapNew(&m.ctx, &.{a}, &.{i});
    const fun = try FinalTerms.makeFun(&m.ctx, 5, 2, &.{});

    const T = struct {
        fn yes(mm: *Machine, got: BifError!Term) !void {
            try std.testing.expect(asBool(mm, try got).?);
        }
        fn no(mm: *Machine, got: BifError!Term) !void {
            try std.testing.expect(!asBool(mm, try got).?);
        }
    };

    // is_atom — TRUE on atoms (incl. booleans), FALSE elsewhere.
    try T.yes(&m, is_atom(&m, &.{a}));
    try T.yes(&m, is_atom(&m, &.{tt}));
    try T.no(&m, is_atom(&m, &.{i}));
    // is_boolean — TRUE only on the true/false atoms.
    try T.yes(&m, is_boolean(&m, &.{tt}));
    try T.no(&m, is_boolean(&m, &.{a}));
    // is_integer / is_float / is_number.
    try T.yes(&m, is_integer(&m, &.{i}));
    try T.no(&m, is_integer(&m, &.{fl}));
    try T.yes(&m, is_float(&m, &.{fl}));
    try T.no(&m, is_float(&m, &.{i}));
    try T.yes(&m, is_number(&m, &.{i}));
    try T.yes(&m, is_number(&m, &.{fl}));
    try T.no(&m, is_number(&m, &.{a}));
    // is_binary vs is_bitstring: a byte-aligned binary is BOTH; a sub-byte
    // bitstring is a bitstring but NOT a binary (MUTANT surface).
    try T.yes(&m, is_binary(&m, &.{bin}));
    try T.yes(&m, is_bitstring(&m, &.{bin}));
    try T.no(&m, is_binary(&m, &.{bits}));
    try T.yes(&m, is_bitstring(&m, &.{bits}));
    // is_list — TRUE on [] and cons, FALSE on tuple/map.
    try T.yes(&m, is_list(&m, &.{nil}));
    try T.yes(&m, is_list(&m, &.{lst}));
    try T.no(&m, is_list(&m, &.{tup}));
    // is_map / is_tuple.
    try T.yes(&m, is_map(&m, &.{mp}));
    try T.no(&m, is_map(&m, &.{tup}));
    try T.yes(&m, is_tuple(&m, &.{tup}));
    try T.no(&m, is_tuple(&m, &.{lst}));
    // is_function/1,2 — arity-precise.
    try T.yes(&m, is_function_1(&m, &.{fun}));
    try T.no(&m, is_function_1(&m, &.{a}));
    try T.yes(&m, is_function_2(&m, &.{ fun, FinalTerms.int(&m.ctx, 2) }));
    try T.no(&m, is_function_2(&m, &.{ fun, FinalTerms.int(&m.ctx, 3) }));
    try std.testing.expectError(error.Badarg, is_function_2(&m, &.{ fun, a }));

    // is_record — the tuple-record test. {a, 7} IS a record tagged `a` of
    // arity 2; native-record arm is vacuously false (is_record/1 never true).
    try T.no(&m, is_record_1(&m, &.{tup}));
    try T.yes(&m, is_record_2(&m, &.{ tup, a }));
    try T.no(&m, is_record_2(&m, &.{ tup, tt }));
    try T.no(&m, is_record_2(&m, &.{ lst, a }));
    try std.testing.expectError(error.Badarg, is_record_2(&m, &.{ tup, i })); // non-atom tag
    try T.yes(&m, is_record_3(&m, &.{ tup, a, FinalTerms.int(&m.ctx, 2) }));
    try T.no(&m, is_record_3(&m, &.{ tup, a, FinalTerms.int(&m.ctx, 3) })); // wrong arity
}

test "LAW E3.18: min/max denote the arith order (ties -> first arg); +/1 identity; //2 always float" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    // min/max over the term order.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try min_2(&m, &.{ one, two }), one));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try min_2(&m, &.{ two, one }), one));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try max_2(&m, &.{ one, two }), two));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try max_2(&m, &.{ two, one }), two));
    // TOTAL across kinds: number < atom (the standard order), so max picks the atom.
    const a = FinalTerms.atom(&m.ctx, try atoms.intern("z"));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try max_2(&m, &.{ one, a }), a));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try min_2(&m, &.{ one, a }), one));

    // +/1 identity on a number; badarith on a non-number.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try unary_plus(&m, &.{two}), two));
    try std.testing.expectError(error.Badarith, unary_plus(&m, &.{a}));

    // //2 is ALWAYS a float: 4/2 == 2.0 (a float term, NOT the integer 2).
    const q = try fdiv(&m, &.{ FinalTerms.int(&m.ctx, 4), two });
    try std.testing.expect(FinalTerms.repIsFloat(&m.ctx, q));
    try std.testing.expectEqual(@as(f64, 2.0), FinalTerms.floatValOf(&m.ctx, q));
    try std.testing.expectError(error.Badarith, fdiv(&m, &.{ one, FinalTerms.int(&m.ctx, 0) })); // div by zero
    try std.testing.expectError(error.Badarith, fdiv(&m, &.{ a, one })); // non-number
}

// ── E31-T2 decode_packet/3 test helpers ─────────────────────────────────────

fn dpOpt(m: *Machine, name: []const u8, val: i64) !Term {
    const t = try FinalTerms.tuple(&m.ctx, &.{ try pktAtom(m, name), FinalTerms.int(&m.ctx, val) });
    return FinalTerms.cons(&m.ctx, t, FinalTerms.nil(&m.ctx));
}

fn dpExpectOk(m: *Machine, res: Term, exp_body: []const u8, exp_rest: []const u8) !void {
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, res) == .tuple);
    try std.testing.expectEqual(@as(usize, 3), FinalTerms.tupleArity(&m.ctx, res));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, res, 0), try pktAtom(m, "ok")));
    const body = FinalTerms.tupleElem(&m.ctx, res, 1);
    const rest = FinalTerms.tupleElem(&m.ctx, res, 2);
    try std.testing.expect(FinalTerms.repIsBinary(&m.ctx, body));
    try std.testing.expect(FinalTerms.repIsBinary(&m.ctx, rest));
    try std.testing.expectEqualSlices(u8, exp_body, FinalTerms.binBytes(&m.ctx, body));
    try std.testing.expectEqualSlices(u8, exp_rest, FinalTerms.binBytes(&m.ctx, rest));
}

fn dpExpectMoreUndef(m: *Machine, res: Term) !void {
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, res) == .tuple);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&m.ctx, res));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, res, 0), try pktAtom(m, "more")));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, res, 1), try pktAtom(m, "undefined")));
}

fn dpExpectMoreLen(m: *Machine, res: Term, len: i64) !void {
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, res) == .tuple);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&m.ctx, res));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, res, 0), try pktAtom(m, "more")));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, res, 1), FinalTerms.int(&m.ctx, len)));
}

fn dpExpectError(m: *Machine, res: Term) !void {
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, res) == .tuple);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&m.ctx, res));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, res, 0), try pktAtom(m, "error")));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, res, 1), try pktAtom(m, "invalid")));
}

test "LAW E31-T2 decode_packet framing byte-EQ vs OTP packet_get_length/body over covered types" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const nil = FinalTerms.nil(&m.ctx);
    const raw_a = try pktAtom(&m, "raw");
    const line_a = try pktAtom(&m, "line");
    const t1 = FinalTerms.int(&m.ctx, 1);
    const t2 = FinalTerms.int(&m.ctx, 2);
    const t4 = FinalTerms.int(&m.ctx, 4);

    // ── raw|0: whole binary is the body, empty rest; empty binary → more,undefined
    {
        const empty = try FinalTerms.binary(&m.ctx, "");
        try dpExpectMoreUndef(&m, try decode_packet_3(&m, &.{ FinalTerms.int(&m.ctx, 0), empty, nil }));
        const b = try FinalTerms.binary(&m.ctx, &[_]u8{ 1, 2, 3 });
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ FinalTerms.int(&m.ctx, 0), b, nil }), &[_]u8{ 1, 2, 3 }, "");
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ raw_a, b, nil }), &[_]u8{ 1, 2, 3 }, "");
    }

    // ── type 1: 1-byte big-endian length prefix, body skips the header
    {
        const b = try FinalTerms.binary(&m.ctx, &[_]u8{ 3, 'a', 'b', 'c', 4, 5 });
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ t1, b, nil }), "abc", &[_]u8{ 4, 5 });
        const partial = try FinalTerms.binary(&m.ctx, &[_]u8{ 3, 'a', 'b' }); // plen 3, only 2 present
        try dpExpectMoreLen(&m, try decode_packet_3(&m, &.{ t1, partial, nil }), 4);
        const empty = try FinalTerms.binary(&m.ctx, "");
        try dpExpectMoreUndef(&m, try decode_packet_3(&m, &.{ t1, empty, nil }));
    }

    // ── type 2 / type 4: 2- and 4-byte big-endian prefixes
    {
        const b2 = try FinalTerms.binary(&m.ctx, &[_]u8{ 0, 3, 'a', 'b', 'c' });
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ t2, b2, nil }), "abc", "");
        const short2 = try FinalTerms.binary(&m.ctx, &[_]u8{0});
        try dpExpectMoreUndef(&m, try decode_packet_3(&m, &.{ t2, short2, nil }));
        const b4 = try FinalTerms.binary(&m.ctx, &[_]u8{ 0, 0, 0, 2, 9, 9, 7 });
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ t4, b4, nil }), &[_]u8{ 9, 9 }, &[_]u8{7});
    }

    // ── sunrm: 4-byte prefix with the MSB (record-end) bit masked off; body is
    //    the WHOLE packet (sunrm is NOT a header-stripping type — only 1/2/4 are)
    {
        const b = try FinalTerms.binary(&m.ctx, &[_]u8{ 0x80, 0, 0, 3, 'a', 'b', 'c' });
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ try pktAtom(&m, "sunrm"), b, nil }), &[_]u8{ 0x80, 0, 0, 3, 'a', 'b', 'c' }, "");
    }

    // ── line: default '\n', line_delimiter, line_length (trunc), packet_size (cap)
    {
        const b = try FinalTerms.binary(&m.ctx, "hello\nworld");
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ line_a, b, nil }), "hello\n", "world");
        const noln = try FinalTerms.binary(&m.ctx, "noline");
        try dpExpectMoreUndef(&m, try decode_packet_3(&m, &.{ line_a, noln, nil }));
        const semi = try FinalTerms.binary(&m.ctx, "a;b");
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ line_a, semi, try dpOpt(&m, "line_delimiter", ';') }), "a;", "b");
        const long = try FinalTerms.binary(&m.ctx, "abcdef");
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ line_a, long, try dpOpt(&m, "line_length", 3) }), "abc", "def");
        try dpExpectError(&m, try decode_packet_3(&m, &.{ line_a, long, try dpOpt(&m, "packet_size", 3) }));
    }

    // ── tpkt: 4-byte header, plen = int16(len) - hlen; body is the WHOLE packet
    {
        const b = try FinalTerms.binary(&m.ctx, &[_]u8{ 3, 0, 0, 6, 1, 2 });
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ try pktAtom(&m, "tpkt"), b, nil }), &[_]u8{ 3, 0, 0, 6, 1, 2 }, "");
        const bad = try FinalTerms.binary(&m.ctx, &[_]u8{ 4, 0, 0, 6 }); // vrsn != 3
        try dpExpectError(&m, try decode_packet_3(&m, &.{ try pktAtom(&m, "tpkt"), bad, nil }));
    }

    // ── cdr: "GIOP" magic, byte-order flag selects BE/LE 4-byte message size
    {
        const cdr = try pktAtom(&m, "cdr");
        const be = try FinalTerms.binary(&m.ctx, &[_]u8{ 'G', 'I', 'O', 'P', 1, 0, 0, 0, 0, 0, 0, 2, 88, 89 });
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ cdr, be, nil }), &[_]u8{ 'G', 'I', 'O', 'P', 1, 0, 0, 0, 0, 0, 0, 2, 88, 89 }, "");
        const le = try FinalTerms.binary(&m.ctx, &[_]u8{ 'G', 'I', 'O', 'P', 1, 0, 1, 0, 2, 0, 0, 0, 88, 89 });
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ cdr, le, nil }), &[_]u8{ 'G', 'I', 'O', 'P', 1, 0, 1, 0, 2, 0, 0, 0, 88, 89 }, "");
        const bad = try FinalTerms.binary(&m.ctx, &[_]u8{ 'X', 'I', 'O', 'P', 1, 0, 0, 0, 0, 0, 0, 2 });
        try dpExpectError(&m, try decode_packet_3(&m, &.{ cdr, bad, nil }));
    }

    // ── fcgi: 8-byte header, plen = contentLen + padding; body trims the padding
    {
        const fcgi = try pktAtom(&m, "fcgi");
        // version 1, type 0, reqId 0, contentLen 3, padding 2, reserved 0, + 3 content + 2 pad
        const b = try FinalTerms.binary(&m.ctx, &[_]u8{ 1, 0, 0, 0, 0, 3, 2, 0, 10, 11, 12, 0, 0 });
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ fcgi, b, nil }), &[_]u8{ 1, 0, 0, 0, 0, 3, 2, 0, 10, 11, 12 }, "");
        const bad = try FinalTerms.binary(&m.ctx, &[_]u8{ 2, 0, 0, 0, 0, 3, 2, 0 }); // version != 1
        try dpExpectError(&m, try decode_packet_3(&m, &.{ fcgi, bad, nil }));
    }

    // ── asn1: short-form and long-length (1-byte) BER length; body is whole
    {
        const asn1 = try pktAtom(&m, "asn1");
        const short = try FinalTerms.binary(&m.ctx, &[_]u8{ 0x04, 0x03, 10, 11, 12 });
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ asn1, short, nil }), &[_]u8{ 0x04, 0x03, 10, 11, 12 }, "");
        const long = try FinalTerms.binary(&m.ctx, &[_]u8{ 0x04, 0x81, 0x03, 10, 11, 12 });
        try dpExpectOk(&m, try decode_packet_3(&m, &.{ asn1, long, nil }), &[_]u8{ 0x04, 0x81, 0x03, 10, 11, 12 }, "");
        const more = try FinalTerms.binary(&m.ctx, &[_]u8{0x04});
        try dpExpectMoreUndef(&m, try decode_packet_3(&m, &.{ asn1, more, nil }));
    }

    // ── REJECTION surface (byte-EQ badarg) + the HONEST structured-type deferral
    {
        const b = try FinalTerms.binary(&m.ctx, &[_]u8{ 1, 2, 3 });
        // unknown packet type (int and atom) → badarg
        try std.testing.expectError(error.Badarg, decode_packet_3(&m, &.{ FinalTerms.int(&m.ctx, 99), b, nil }));
        try std.testing.expectError(error.Badarg, decode_packet_3(&m, &.{ try pktAtom(&m, "bogus"), b, nil }));
        // E41-T1: http/http_bin are now IMPLEMENTED (request/response-line parse);
        // <<1,2,3>> has no line terminator so http frames to {more, undefined}.
        {
            const more = try decode_packet_3(&m, &.{ try pktAtom(&m, "http"), b, nil });
            try std.testing.expect(FinalTerms.kindOf(&m.ctx, more) == .tuple);
            try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, more, 0), try pktAtom(&m, "more")));
        }
        // the REMAINING structured types stay DEFERRED → badarg (documented, NOT EQ)
        // E42-T1: ssl_tls + httph are now IMPLEMENTED; <<1,2,3>> is a short TLS
        // header / a header with no \n ⇒ {more, undefined} for both.
        {
            const s = try decode_packet_3(&m, &.{ try pktAtom(&m, "ssl_tls"), b, nil });
            try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, s, 0), try pktAtom(&m, "more")));
            const more = try decode_packet_3(&m, &.{ try pktAtom(&m, "httph"), b, nil });
            try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, more, 0), try pktAtom(&m, "more")));
        }
        // arg-2 not a binary → badarg
        try std.testing.expectError(error.Badarg, decode_packet_3(&m, &.{ raw_a, raw_a, nil }));
        // bad option key → badarg
        try std.testing.expectError(error.Badarg, decode_packet_3(&m, &.{ raw_a, b, try dpOpt(&m, "bogus_opt", 1) }));
        // line_delimiter on a non-line type → badarg
        try std.testing.expectError(error.Badarg, decode_packet_3(&m, &.{ raw_a, b, try dpOpt(&m, "line_delimiter", ';') }));
        // line_delimiter value > 255 on line → badarg
        try std.testing.expectError(error.Badarg, decode_packet_3(&m, &.{ line_a, b, try dpOpt(&m, "line_delimiter", 300) }));
        // negative option value → badarg
        try std.testing.expectError(error.Badarg, decode_packet_3(&m, &.{ raw_a, b, try dpOpt(&m, "packet_size", -1) }));
        // improper / non-list options → badarg
        try std.testing.expectError(error.Badarg, decode_packet_3(&m, &.{ raw_a, b, raw_a }));
    }
}

test "LAW E41-T1 decode_packet http/http_bin: request/response line parse + http_error fallback, byte-EQ to OTP" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const H = struct {
        fn body(mm: *Machine, ty: []const u8, s: []const u8) !Term {
            const bin = try FinalTerms.binary(&mm.ctx, s);
            const r = try decode_packet_3(mm, &.{ try pktAtom(mm, ty), bin, FinalTerms.nil(&mm.ctx) });
            try std.testing.expect(FinalTerms.tupleArity(&mm.ctx, r) == 3);
            try std.testing.expect(FinalTerms.eqlExact(&mm.ctx, FinalTerms.tupleElem(&mm.ctx, r, 0), try pktAtom(mm, "ok")));
            return FinalTerms.tupleElem(&mm.ctx, r, 1);
        }
    };

    // {http_request, 'GET', {abs_path, "/path"}, {1,1}}
    {
        const t = try H.body(&m, "http", "GET /path HTTP/1.1\r\n");
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 0), try pktAtom(&m, "http_request")));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 1), try pktAtom(&m, "GET")));
        const uri = FinalTerms.tupleElem(&m.ctx, t, 2);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, uri, 0), try pktAtom(&m, "abs_path")));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, uri, 1), try strOrBin(&m, "/path", false)));
        const ver = FinalTerms.tupleElem(&m.ctx, t, 3);
        try std.testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, ver, 0)));
        try std.testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, ver, 1)));
    }
    // an UNKNOWN method stays a string; http_bin uses binary bodies
    {
        const t = try H.body(&m, "http_bin", "PATCH /x HTTP/1.0\r\n");
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 1), try strOrBin(&m, "PATCH", true)));
        const uri = FinalTerms.tupleElem(&m.ctx, t, 2);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, uri, 1), try strOrBin(&m, "/x", true)));
    }
    // {http_response, {1,0}, 404, "Not Found"}
    {
        const t = try H.body(&m, "http", "HTTP/1.0 404 Not Found\r\n");
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 0), try pktAtom(&m, "http_response")));
        try std.testing.expectEqual(@as(i64, 404), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t, 2)));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 3), try strOrBin(&m, "Not Found", false)));
    }
    // a header line is NOT a request/response ⇒ {http_error, WholeLineIncludingCRLF}
    {
        const t = try H.body(&m, "http", "Host: example.com\r\n");
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 0), try pktAtom(&m, "http_error")));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 1), try strOrBin(&m, "Host: example.com\r\n", false)));
    }
    // absoluteURI form: {absoluteURI, http, "h", 8, "/p"}
    {
        const t = try H.body(&m, "http", "GET http://h:8/p HTTP/1.1\r\n");
        const uri = FinalTerms.tupleElem(&m.ctx, t, 2);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, uri, 0), try pktAtom(&m, "absoluteURI")));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, uri, 1), try pktAtom(&m, "http")));
        try std.testing.expectEqual(@as(i64, 8), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, uri, 3)));
    }
}

test "LAW E42-T1 decode_packet httph/httph_bin: header parse — Bit table, case-insensitivity, capitalise, value-trim, http_eoh, lookahead framing" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const H = struct {
        fn hdr(mm: *Machine, ty: []const u8, s: []const u8) !Term {
            const bin = try FinalTerms.binary(&mm.ctx, s);
            const r = try decode_packet_3(mm, &.{ try pktAtom(mm, ty), bin, FinalTerms.nil(&mm.ctx) });
            try std.testing.expect(FinalTerms.eqlExact(&mm.ctx, FinalTerms.tupleElem(&mm.ctx, r, 0), try pktAtom(mm, "ok")));
            return FinalTerms.tupleElem(&mm.ctx, r, 1);
        }
    };

    // a KNOWN header (case-insensitive) → {http_header, 38, 'Content-Length', Reserved, Value}
    {
        const t = try H.hdr(&m, "httph", "content-length: 42\r\nx");
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 0), try pktAtom(&m, "http_header")));
        try std.testing.expectEqual(@as(i64, 38), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t, 1)));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 2), try pktAtom(&m, "Content-Length"))); // canonical atom
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 3), try strOrBin(&m, "content-length", false))); // original
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 4), try strOrBin(&m, "42", false)));
    }
    // an UNKNOWN field → Bit 0 + http-capitalised Field ("x-foo" → "X-Foo")
    {
        const t = try H.hdr(&m, "httph", "x-foo: bar\r\nx");
        try std.testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t, 1)));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 2), try strOrBin(&m, "X-Foo", false)));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 3), try strOrBin(&m, "x-foo", false)));
    }
    // value: leading ws stripped, trailing KEPT
    {
        const t = try H.hdr(&m, "httph", "Host:   v  \r\nx");
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 4), try strOrBin(&m, "v  ", false)));
    }
    // the empty line → http_eoh; a header with no lookahead byte → {more, undefined}
    {
        const eoh = try H.hdr(&m, "httph", "\r\n");
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, eoh, try pktAtom(&m, "http_eoh")));
        const more = try decode_packet_3(&m, &.{ try pktAtom(&m, "httph"), try FinalTerms.binary(&m.ctx, "Host: x\r\n"), FinalTerms.nil(&m.ctx) });
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, more, 0), try pktAtom(&m, "more")));
    }
}

test "LAW cp-decode-packet-fold decode_packet httph: RFC obs-fold continuation lines keep the embedded \\r\\n<ws> RAW (decode_packet_SUITE Multi-Line oracle)" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const H = struct {
        fn hdr(mm: *Machine, ty: []const u8, s: []const u8) !Term {
            const bin = try FinalTerms.binary(&mm.ctx, s);
            const r = try decode_packet_3(mm, &.{ try pktAtom(mm, ty), bin, FinalTerms.nil(&mm.ctx) });
            try std.testing.expect(FinalTerms.eqlExact(&mm.ctx, FinalTerms.tupleElem(&mm.ctx, r, 0), try pktAtom(mm, "ok")));
            return FinalTerms.tupleElem(&mm.ctx, r, 1);
        }
    };

    // The AUTHORITATIVE OTP case (erts decode_packet_SUITE): a 3-line folded header
    // → the value keeps the embedded `\r\n<space>` RAW, the final \r\n stripped. The
    // trailing 'x' is the non-WS lookahead byte that terminates the fold.
    const ml_in = "Multi-Line: Once upon a time in a land far far away,\r\n there lived a princess imprisoned in the highest tower\r\n of the most haunted castle.\r\nx";
    const ml_val = "Once upon a time in a land far far away,\r\n there lived a princess imprisoned in the highest tower\r\n of the most haunted castle.";
    {
        const t = try H.hdr(&m, "httph", ml_in);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 0), try pktAtom(&m, "http_header")));
        try std.testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, t, 1)));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 2), try strOrBin(&m, "Multi-Line", false)));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 3), try strOrBin(&m, "Multi-Line", false)));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 4), try strOrBin(&m, ml_val, false)));
    }
    // httph_bin: same fold, binary value.
    {
        const t = try H.hdr(&m, "httph_bin", ml_in);
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 4), try strOrBin(&m, ml_val, true)));
    }
    // a single fold, properly terminated → value keeps the one embedded \r\n<ws>.
    {
        const t = try H.hdr(&m, "httph", "X-L: a\r\n b\r\nY");
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 4), try strOrBin(&m, "a\r\n b", false)));
    }
    // a buffer ending MID-FOLD (continuation started, no terminating line) → {more, undefined}
    // — the lookahead cannot yet decide the header is complete.
    {
        const r = try decode_packet_3(&m, &.{ try pktAtom(&m, "httph"), try FinalTerms.binary(&m.ctx, "X-L: a\r\n b"), FinalTerms.nil(&m.ctx) });
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, r, 0), try pktAtom(&m, "more")));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, r, 1), try pktAtom(&m, "undefined")));
    }
    // a non-folded next line (starts non-WS) terminates the header at the first \n.
    {
        const t = try H.hdr(&m, "httph", "Host: v\r\nNext: w\r\nx");
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, t, 4), try strOrBin(&m, "v", false)));
    }
}
