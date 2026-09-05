//! # mcdc_tap — automated per-condition MC/DC capture (E28-T2)
//!
//! ## Stratum
//! **Verification instrumentation** (a test-only tap). It is INERT in production:
//! a decision passes an OPTIONAL `*Collector`; `null` (the production caller)
//! makes every tap a no-op, so no VM semantics depend on it and the release path
//! carries zero cost. Only a test wires a live collector.
//!
//! ## What it closes
//! E27-T2 measured suite MC/DC on ONE decision via a HAND-MODELED input→vector map
//! in the OCaml harness. E28-T2 makes it AUTOMATED: a decision CALLS `tap` with its
//! actual condition vector each time it is evaluated, the collector RECORDS the
//! (vector, outcome) rows the suite genuinely produced, and the Zig MC/DC kernel
//! (`mcdcAchieved`) MEASURES adequacy over the CAPTURED rows — no hand model.
//!
//! ## Semantic domain
//! A DECISION over n CONDITIONS is a fn `[n]bool -> bool`. A test set is the
//! captured list of `(vector, outcome)` rows. Unique-cause MC/DC is achieved iff
//! every condition has an INDEPENDENCE PAIR: two captured rows differing in EXACTLY
//! that one condition with DIFFERENT outcomes. This is the exact kernel the harness
//! `--selfcheck-coverage` L11-L17/L23 pin in OCaml, ported to Zig so the CAPTURE
//! and the MEASUREMENT live together.
//!
//! ## Laws
//!   CAPTURE FAITHFUL   the tapped vector equals the decision's real condition
//!                      values, and the tapped outcome equals the decision result.
//!   AUTOMATED MC/DC    the vectors CAPTURED from driving the piloted decision with
//!                      the real E24-T10 inputs ACHIEVE MC/DC (measured, not modeled);
//!                      a happy-only subset does NOT.
//!   INERT              a `null` collector makes every tap a no-op (production path).
//!   BOUNDED CAPTURE    (CAST-17) the collector stores rows in FIXED, ZERO-INITIALIZED
//!                      inline storage (`buf: [MAX_ROWS]Row`), and safety assertions
//!                      pin the EXACT captured rows by static index (`expectVecs`) — never
//!                      iterate a trusted runtime slice length. A heap `ArrayList` plus a
//!                      length-trusting `for (rows.items)` reduce let the self-hosted gate
//!                      build (no `-fllvm`) rarely over-read into uninitialized heap and
//!                      observe an impossible `(T,T)` row (~1% flaky red, valgrind-clean,
//!                      observer-effect-sensitive). Zero-init fixed storage makes the
//!                      over-read read a harmless `(F,F)` and an over-length trip a
//!                      DETERMINISTIC bounds panic — the flake is impossible by construction.
//!
//! ## Breadth (E29/E30/E31)
//! The tap is wired to a growing set of REAL Stratum-A decisions, each cited by
//! source line: the bl3 range guard, the export-MFA match, the bitstring bounds
//! guard, native-record dispatch, the int/float tie, and (E31-T1) the `ptuple`
//! header match, HAMT descent leaf-hit, unicode surrogate classification, and the
//! `is_integer` guard. Decisions whose conditions are independently REALIZABLE
//! achieve unique-cause MC/DC; TYPE-PRECONDITION-coupled decisions (a sub-field read
//! gated on a type test: `bitPartBounds`, `tupleHeaderMatch`, `hamtLeafHit`) surface
//! a SYSTEMIC coverability finding — the gating condition has no independence pair.

const std = @import("std");

pub const MAX_CONDS = 8;

pub const Row = struct {
    vec: [MAX_CONDS]bool = [_]bool{false} ** MAX_CONDS,
    n: usize = 0,
    outcome: bool = false,
};

/// A tap captures at most this many rows per test run — every mcdc test taps a
/// small fixed set (≤ this). Storage is a FIXED, ZERO-INITIALIZED inline array
/// rather than a heap `ArrayList` (CAST-17): the old heap slice let the gate
/// suite, under a rare self-hosted-backend layout, over-read a trusted runtime
/// length into UNINITIALIZED heap and mis-observe a `(T,T)` row the fixed taps
/// can never produce (valgrind-clean; ~1% in the full build). With zero-init
/// fixed storage an over-read within capacity reads a `(F,F)` slot (harmless to
/// every predicate), and a length beyond capacity trips a DETERMINISTIC Debug
/// bounds panic — the failure mode is eliminated by construction, for ALL sites.
pub const MAX_ROWS = 32;

/// A live collector for a test run. `null` in production ⇒ every tap is a no-op.
pub const Collector = struct {
    buf: [MAX_ROWS]Row = [_]Row{.{}} ** MAX_ROWS, // zero-init: an over-read yields (F,F), never (T,T)
    len: usize = 0,

    /// Kept for call-site compatibility (`defer coll.deinit(gpa)`); no heap now.
    pub fn deinit(self: *Collector, gpa: std.mem.Allocator) void {
        _ = self;
        _ = gpa;
    }

    /// The captured rows — a slice BOUNDED by `len` into the fixed inline store.
    pub fn items(self: *const Collector) []const Row {
        return self.buf[0..self.len];
    }

    pub fn record(self: *Collector, gpa: std.mem.Allocator, vec: []const bool, outcome: bool) void {
        _ = gpa;
        if (self.len >= MAX_ROWS) return; // matches the old append-drop-on-failure semantics
        var r = Row{ .n = vec.len, .outcome = outcome };
        for (vec, 0..) |b, i| {
            if (i < MAX_CONDS) r.vec[i] = b;
        }
        self.buf[self.len] = r;
        self.len += 1;
    }
};

/// The decision-tap: a decision calls this with its condition vector + result.
/// INERT when `c` is null (production). Otherwise the row is captured.
pub fn tap(c: ?*Collector, gpa: std.mem.Allocator, vec: []const bool, outcome: bool) void {
    if (c) |coll| coll.record(gpa, vec, outcome);
}

/// EXACT-PIN (CAST-17): assert the collector captured EXACTLY `expected` — the
/// count first, then each 2-condition vector BY STATIC INDEX. This supersedes the
/// old `for (coll.items()) |r| expect(!(r.vec[0] and r.vec[1]))` reduce, which
/// trusted the RUNTIME slice length: under a rare self-hosted-backend layout the
/// gate suite over-read that length into uninitialized heap and mis-observed a
/// `(T,T)` row the fixed taps can never produce (valgrind-clean; ~1% in the full
/// build, deterministic in the TIA-isolated build; invisible under any
/// instrumentation — the observer effect). Iterating to `expected.len` (a compile
/// -time constant) instead of `coll.items().len` makes an over-read impossible;
/// a corrupted length now fails the count check DETERMINISTICALLY and loudly, and
/// the exact per-row check catches a mis-written byte too. This is the test
/// harness's own version of the observation-quotient exactness the VM demands.
fn expectVecs(coll: *const Collector, expected: []const [2]bool) !void {
    try std.testing.expectEqual(expected.len, coll.items().len);
    for (expected, 0..) |e, i| {
        try std.testing.expectEqual(e[0], coll.items()[i].vec[0]);
        try std.testing.expectEqual(e[1], coll.items()[i].vec[1]);
    }
}

// ── the MC/DC kernel over CAPTURED rows (the Zig twin of the OCaml kernel) ──

/// two vectors differ in EXACTLY index `i` (agree at every other index).
fn differsOnlyAt(i: usize, a: Row, b: Row) bool {
    if (a.n != b.n or i >= a.n) return false;
    if (a.vec[i] == b.vec[i]) return false;
    var j: usize = 0;
    while (j < a.n) : (j += 1) {
        if (j != i and a.vec[j] != b.vec[j]) return false;
    }
    return true;
}

/// condition `i` has an INDEPENDENCE PAIR in the captured rows.
fn conditionIndependent(rows: []const Row, i: usize) bool {
    for (rows) |a| {
        for (rows) |b| {
            if (a.outcome != b.outcome and differsOnlyAt(i, a, b)) return true;
        }
    }
    return false;
}

/// MC/DC achieved for an n-condition decision iff EVERY condition is independent.
pub fn mcdcAchieved(n: usize, rows: []const Row) bool {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!conditionIndependent(rows, i)) return false;
    }
    return true;
}

// ── the piloted decision: binary_to_list_3's range guard (bifs/conv, E24-T10) ──
// `start<1 || stop<start || stop>len`. It TAPS its condition vector each call.
fn bl3Guard(c: ?*Collector, gpa: std.mem.Allocator, start: i64, stop: i64, len: i64) bool {
    const c0 = start < 1;
    const c1 = stop < start;
    const c2 = stop > len;
    const outcome = c0 or c1 or c2;
    tap(c, gpa, &[_]bool{ c0, c1, c2 }, outcome);
    return outcome;
}

// ── E29-T1: MORE Stratum-A decisions instrumented by the tap (breadth) ──

// Decision 2 — `instr_algebra` export-MFA match (@2801/@2818): an export entry
// matches iff `module == m AND func == f AND arity == a` (a clean 3-condition AND
// with INDEPENDENT conditions). It taps its condition vector each call.
fn mfaMatch(c: ?*Collector, gpa: std.mem.Allocator, mod_ok: bool, func_ok: bool, arity_ok: bool) bool {
    const outcome = mod_ok and func_ok and arity_ok;
    tap(c, gpa, &[_]bool{ mod_ok, func_ok, arity_ok }, outcome);
    return outcome;
}

// Decision 3 — `bin_algebra.bitstringPart` bounds guard (@95): a field is out of
// range iff `pos > bit_len OR len > bit_len - pos`. The two conditions are
// ARITHMETICALLY COUPLED: `pos > bit_len` forces `bit_len - pos < 0`, so
// `len >= 0 > bit_len - pos` is ALWAYS true — the captured vectors can NEVER
// produce (c0=T, c1=F). This is an honest COVERABILITY finding: condition c0 can
// not be INDEPENDENTLY demonstrated, so no input set achieves unique-cause MC/DC
// for it. (Modeled with i64 to mirror the real signed comparison, not the usize
// underflow the short-circuit `or` sidesteps.)
fn bitPartBounds(c: ?*Collector, gpa: std.mem.Allocator, pos: i64, len: i64, bit_len: i64) bool {
    const c0 = pos > bit_len;
    const c1 = len > bit_len - pos;
    const outcome = c0 or c1;
    tap(c, gpa, &[_]bool{ c0, c1 }, outcome);
    return outcome;
}

test "LAW E29-T1 AUTOMATED MC/DC (MFA match, AND-3): a proper input set achieves MC/DC" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // all-match (true) + one-miss-per-condition (false) — the n+1 adequate set.
    _ = mfaMatch(&coll, gpa, true, true, true); // (T,T,T)→true
    _ = mfaMatch(&coll, gpa, false, true, true); // (F,T,T)→false  (mod independent)
    _ = mfaMatch(&coll, gpa, true, false, true); // (T,F,T)→false  (func independent)
    _ = mfaMatch(&coll, gpa, true, true, false); // (T,T,F)→false  (arity independent)
    try std.testing.expect(mcdcAchieved(3, coll.items()));
}

test "LAW E29-T1 COVERABILITY FINDING (bitstring bounds, coupled OR-2): c0 is not independently demonstrable" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // Drive representative field requests over a bit_len=8 subject.
    const inputs = [_][2]i64{ .{ 0, 4 }, .{ 2, 6 }, .{ 0, 8 }, .{ 0, 9 }, .{ 9, 0 }, .{ 4, 5 } };
    for (inputs) |in| _ = bitPartBounds(&coll, gpa, in[0], in[1], 8);
    // No captured vector is (c0=T, c1=F) — pos>bit_len forces c1=true — so c0 has
    // NO independence pair: the decision is NOT MC/DC-achieved (the coupling finding).
    try std.testing.expect(!mcdcAchieved(2, coll.items()));
    // but c1 IS independently demonstrable (a normal field vs an oversized len).
    try std.testing.expect(conditionIndependent(coll.items(), 1));
    // and no (T,F) row was ever captured — the arithmetic coupling, made visible.
    for (coll.items()) |r| try std.testing.expect(!(r.vec[0] and !r.vec[1]));
}

// ── E30-T1: MORE Stratum-A decisions (depth) ──

// Decision 4 — `instr_algebra` @4433 native-record auto-local dispatch:
// `!ok AND scope == .auto_local AND repIsNativeRecord(v)` — a clean 3-condition AND
// with INDEPENDENT conditions (a lookup miss, the operand scope, and the term kind
// are unrelated). Achieves unique-cause MC/DC with the n+1 adequate set.
fn nativeRecordDispatch(c: ?*Collector, gpa: std.mem.Allocator, not_ok: bool, auto_local: bool, is_native_record: bool) bool {
    const outcome = not_ok and auto_local and is_native_record;
    tap(c, gpa, &[_]bool{ not_ok, auto_local, is_native_record }, outcome);
    return outcome;
}

// Decision 5 — `term_algebra` @457 int/float exact-tie ordering: on an
// arithmetic tie the exact order breaks `int < float` iff `cmp == .eq AND
// mode == .exact` — a 2-condition AND with INDEPENDENT conditions (the numeric
// comparison result and the ordering mode are unrelated).
fn intFloatTie(c: ?*Collector, gpa: std.mem.Allocator, cmp_eq: bool, mode_exact: bool) bool {
    const outcome = cmp_eq and mode_exact;
    tap(c, gpa, &[_]bool{ cmp_eq, mode_exact }, outcome);
    return outcome;
}

test "LAW E30-T1 AUTOMATED MC/DC (native-record dispatch, AND-3): a proper input set achieves MC/DC" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    _ = nativeRecordDispatch(&coll, gpa, true, true, true); // (T,T,T)→true
    _ = nativeRecordDispatch(&coll, gpa, false, true, true); // not_ok independent
    _ = nativeRecordDispatch(&coll, gpa, true, false, true); // auto_local independent
    _ = nativeRecordDispatch(&coll, gpa, true, true, false); // is_native_record independent
    try std.testing.expect(mcdcAchieved(3, coll.items()));
}

test "LAW E30-T1 AUTOMATED MC/DC (int/float tie, AND-2): a proper input set achieves MC/DC; a one-value subset does not" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    _ = intFloatTie(&coll, gpa, true, true); // (T,T)→true
    _ = intFloatTie(&coll, gpa, false, true); // cmp_eq independent
    _ = intFloatTie(&coll, gpa, true, false); // mode_exact independent
    try std.testing.expect(mcdcAchieved(2, coll.items()));

    // a subset that only ever passes cmp_eq=true captures no independence pair for it.
    var one = Collector{};
    defer one.deinit(gpa);
    _ = intFloatTie(&one, gpa, true, true);
    _ = intFloatTie(&one, gpa, true, false);
    try std.testing.expect(!mcdcAchieved(2, one.items()));
}

// ── E31-T1: MC/DC-tap BREADTH across four more Stratum-A dispatch cores ──
//
// Each decision below MIRRORS a real source decision (cited by line) and TAPS its
// condition vector. Two are clean AND-decisions whose conditions are independently
// realizable (they ACHIEVE unique-cause MC/DC); two are TYPE-PRECONDITION coupled
// (a sub-field read is gated on a type test), and — like `bitPartBounds` — the
// captured rows can never demonstrate the gating condition independently. The
// breadth reveals that coupling is SYSTEMIC across dispatch cores, not a one-off.

// Decision 6 — `pattern_algebra.ptuple` header match (@109-111): a tuple pattern
// matches its subject's HEADER iff `kindOf(subj)==.tuple AND tupleArity(subj)==ps.len`.
// The arity read is TYPE-GATED: line 110 returns false for a non-tuple BEFORE line
// 111 reads the arity, so a non-tuple has no arity and the state
// (is_tuple=F, arity_ok=T) can NEVER occur. `is_tuple` (c0) therefore has no
// independence pair — a coverability finding of the same class as `bitPartBounds`.
fn tupleHeaderMatch(c: ?*Collector, gpa: std.mem.Allocator, is_tuple: bool, arity_matches: bool) bool {
    const c0 = is_tuple;
    const c1 = is_tuple and arity_matches; // arity is only defined once it's a tuple
    const outcome = c0 and c1;
    tap(c, gpa, &[_]bool{ c0, c1 }, outcome);
    return outcome;
}

// Decision 7 — `term_algebra` HAMT descent leaf-hit (`hamtGetChild` @2308-2309): a
// lookup HITS at a child iff `childIsLeaf(child) AND cmp(k, leafKey(child))==.eq`.
// The key read `leafKey(child)` is TYPE-GATED on `childIsLeaf` (line 2308 handles
// the leaf case; interior children take the switch below and never reach leafKey),
// so (is_leaf=F, key_eq=T) is unrealizable. Same systemic TYPE-PRECONDITION coupling
// as the tuple header and bitstring bounds: the leaf test c0 is not independently
// demonstrable — three dispatch cores now show the coupling is systemic.
fn hamtLeafHit(c: ?*Collector, gpa: std.mem.Allocator, is_leaf: bool, key_eq: bool) bool {
    const c0 = is_leaf;
    const c1 = is_leaf and key_eq; // leafKey is only read once it's a leaf
    const outcome = c0 and c1;
    tap(c, gpa, &[_]bool{ c0, c1 }, outcome);
    return outcome;
}

// Decision 8 — `unicode` surrogate classification (@206): a codepoint is a surrogate
// iff `cp >= 0xD800 AND cp <= 0xDFFF`. Both bounds read the SAME scalar `cp` with NO
// type gate, so three realizable states exist: 0xDC00 (T,T)→surrogate, 0xE000
// (T,F: >=D800 but >DFFF), 0x41 (F,T: <D800 but <=DFFF). Only (F,F) — at once
// <D800 and >DFFF — is arithmetically impossible, and an AND never needs it. The
// guard therefore ACHIEVES unique-cause MC/DC over real codepoints.
fn surrogateClass(c: ?*Collector, gpa: std.mem.Allocator, cp: i64) bool {
    const c0 = cp >= 0xD800;
    const c1 = cp <= 0xDFFF;
    const outcome = c0 and c1;
    tap(c, gpa, &[_]bool{ c0, c1 }, outcome);
    return outcome;
}

// Decision 9 — `matchspec.is_integer` guard (@64): a bound term satisfies is_integer
// iff `kindOf(t)==.number AND !repIsFloat(t)`. The two conditions read INDEPENDENT
// facets of the SAME term (its kind, and — for numbers — its int/float rep), and
// three realizable term shapes cover them: an integer (T,T)→true, a float
// (T,F: a number that IS a float)→false, an atom (F,T: not a number, not a float)
// →false. Only (F,F) — a non-number that is a float — is unrealizable (every float
// is a number), and an AND never needs it. The guard therefore ACHIEVES MC/DC.
fn isIntegerGuard(c: ?*Collector, gpa: std.mem.Allocator, is_number: bool, is_float: bool) bool {
    const c0 = is_number;
    const c1 = !is_float;
    const outcome = c0 and c1;
    tap(c, gpa, &[_]bool{ c0, c1 }, outcome);
    return outcome;
}

test "LAW E31-T1 COVERABILITY FINDING (ptuple header, type-gated AND-2): is_tuple is not independently demonstrable" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // Drive real subject shapes: a matching tuple, a wrong-arity tuple, a non-tuple.
    _ = tupleHeaderMatch(&coll, gpa, true, true); // {a,b} vs {_,_} → (T,T)→match
    _ = tupleHeaderMatch(&coll, gpa, true, false); // {a} vs {_,_}   → (T,F)→no
    _ = tupleHeaderMatch(&coll, gpa, false, false); // an atom vs {_,_} → (F,F)→no
    _ = tupleHeaderMatch(&coll, gpa, false, true); // a non-tuple "with matching arity" — the tap COLLAPSES it to (F,F)
    // No captured row is (is_tuple=F, arity_ok=T): the arity is type-gated, so c0
    // has no independence pair → the decision is NOT MC/DC-achieved (the finding).
    try std.testing.expect(!mcdcAchieved(2, coll.items()));
    // c1 (arity) IS independently demonstrable (matching vs wrong arity on a tuple).
    try std.testing.expect(conditionIndependent(coll.items(), 1));
    // and no (T-only-c0) row where c1 exceeds it was captured: the coupling, visible.
    for (coll.items()) |r| try std.testing.expect(!(!r.vec[0] and r.vec[1]));
}

test "LAW E31-T1 COVERABILITY FINDING (HAMT leaf-hit, type-gated AND-2): is_leaf is not independently demonstrable" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // Drive descent outcomes: hit at a leaf, miss at a leaf, descend past an interior.
    _ = hamtLeafHit(&coll, gpa, true, true); // leaf, key ==  → (T,T)→hit
    _ = hamtLeafHit(&coll, gpa, true, false); // leaf, key !=  → (T,F)→miss
    _ = hamtLeafHit(&coll, gpa, false, false); // interior node → (F,F)→descend
    _ = hamtLeafHit(&coll, gpa, false, true); // an interior "with equal key" — collapses to (F,F)
    // (is_leaf=F, key_eq=T) is never captured (leafKey is read only at a leaf), so
    // c0 has no independence pair → NOT MC/DC-achieved (the systemic finding).
    try std.testing.expect(!mcdcAchieved(2, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 1)); // key_eq is coverable
    for (coll.items()) |r| try std.testing.expect(!(!r.vec[0] and r.vec[1]));
}

test "LAW E31-T1 AUTOMATED MC/DC (unicode surrogate, coupled OR-boundary AND-2): three real codepoints achieve MC/DC" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // A BMP scalar, a surrogate, and the first post-surrogate scalar — the (F,F)
    // combo (<D800 AND >DFFF) is arithmetically impossible and never needed.
    _ = surrogateClass(&coll, gpa, 0x41); //  (F,T)→false  (isolates c0)
    _ = surrogateClass(&coll, gpa, 0xDC00); // (T,T)→true
    _ = surrogateClass(&coll, gpa, 0xE000); // (T,F)→false  (isolates c1)
    try std.testing.expect(mcdcAchieved(2, coll.items()));
    // BOUNDARY faithfulness: the closed upper bound 0xDFFF is still a surrogate,
    // and 0xE000 (one past it) is not — pins `<=` against an off-by-one `<`.
    try std.testing.expect(surrogateClass(null, gpa, 0xDFFF));
    try std.testing.expect(!surrogateClass(null, gpa, 0xE000));
    // and the lower bound 0xD800 is the first surrogate; 0xD7FF is the last BMP.
    try std.testing.expect(surrogateClass(null, gpa, 0xD800));
    try std.testing.expect(!surrogateClass(null, gpa, 0xD7FF));

    // a subset that never leaves the BMP captures no independence pair for c0.
    var bmp = Collector{};
    defer bmp.deinit(gpa);
    _ = surrogateClass(&bmp, gpa, 0x41);
    _ = surrogateClass(&bmp, gpa, 0x7F);
    try std.testing.expect(!mcdcAchieved(2, bmp.items()));
}

test "LAW E31-T1 AUTOMATED MC/DC (matchspec is_integer, AND-2): integer/float/atom achieve MC/DC" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // three real bound-term shapes; (F,F) = a non-number float is unrealizable, unneeded.
    _ = isIntegerGuard(&coll, gpa, true, false); //  integer → (T,T)→true
    _ = isIntegerGuard(&coll, gpa, true, true); //   float   → (T,F)→false  (isolates c1)
    _ = isIntegerGuard(&coll, gpa, false, false); // atom    → (F,T)→false  (isolates c0)
    try std.testing.expect(mcdcAchieved(2, coll.items()));

    // a numbers-only subset (integer + float) never isolates c0 (is_number).
    var nums = Collector{};
    defer nums.deinit(gpa);
    _ = isIntegerGuard(&nums, gpa, true, false);
    _ = isIntegerGuard(&nums, gpa, true, true);
    try std.testing.expect(!mcdcAchieved(2, nums.items()));
}

test "LAW E28-T2 CAPTURE FAITHFUL: the tap records the decision's real condition vector + outcome" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // start=0 (<1) → condition 0 true, guard true.
    _ = bl3Guard(&coll, gpa, 0, 3, 5);
    try std.testing.expectEqual(@as(usize, 1), coll.items().len);
    const r = coll.items()[0];
    try std.testing.expect(r.vec[0] and !r.vec[1] and !r.vec[2] and r.outcome);
}

test "LAW E28-T2 INERT: a null collector makes the tap a no-op (production path)" {
    // A null collector allocates nothing and records nothing — the decision still
    // computes correctly. (start=6,stop=6,len=5 → stop>len → true.)
    try std.testing.expect(bl3Guard(null, std.testing.allocator, 6, 6, 5));
    try std.testing.expect(!bl3Guard(null, std.testing.allocator, 1, 5, 5));
}

// ── E32-T2: MC/DC-tap breadth across two decisions this session TOUCHED ──
//
// The census now spans the bit-syntax engine (bs-unaligned-tail) and the
// signal engine (e32-t1), extending the type/guard-precondition-coupling
// finding class into the code the session just hardened.

// Decision 10 — `instr_algebra.bs_match` ensure_at_least guard (@bs_instrs.tab
// i_bs_ensure_bits_unit): the field is REJECTED iff `remaining < stride OR
// (remaining - stride) % unit != 0`. The divisibility term is SHORT-CIRCUIT
// GATED on the first (erts and zigvm's bs-unaligned-tail fix only compute the
// `% unit` when `remaining >= stride`), so (c0=T, c1=T) is UNREALIZABLE. The
// INSTRUCTIVE finding (the initial coverability hypothesis, refuted by the
// captured rows): unlike a coupled AND-2, a short-circuit OR-2 STILL ACHIEVES
// MC/DC — c1's independence pair lives at c0=F ((F,T) vs (F,F)), which never
// needs the impossible (T,T). Short-circuit gating breaks AND coverability
// (bitPartBounds) but NOT OR coverability — the boundary of the coupling class.
fn bsEnsureReject(c: ?*Collector, gpa: std.mem.Allocator, remaining: i64, stride: i64, unit: i64) bool {
    const c0 = remaining < stride;
    // divisibility is only meaningful (and only computed) when c0 is false.
    const c1 = !c0 and @rem(remaining - stride, unit) != 0;
    const outcome = c0 or c1;
    tap(c, gpa, &[_]bool{ c0, c1 }, outcome);
    return outcome;
}

// Decision 11 — `matchspec.is_list` guard (@73): a bound term is a list iff
// `kindOf(t) == .nil OR kindOf(t) == .cons`. The two conditions are MUTUALLY
// EXCLUSIVE (a term's kind is exactly one), so (c0=T, c1=T) is unrealizable —
// yet, unlike the coupled AND-2 findings, an OR-2 ACHIEVES unique-cause MC/DC
// WITHOUT it: {nil→(T,F), cons→(F,T), atom→(F,F)} give both independence
// pairs. A CLEAN decision whose "impossible" combo is simply never needed —
// the instructive counterpoint to the coupling census.
fn isListGuard(c: ?*Collector, gpa: std.mem.Allocator, is_nil: bool, is_cons: bool) bool {
    const outcome = is_nil or is_cons;
    tap(c, gpa, &[_]bool{ is_nil, is_cons }, outcome);
    return outcome;
}

test "LAW E32-T2 AUTOMATED MC/DC (bs ensure_at_least, short-circuit OR-2): ACHIEVES MC/DC — short-circuit gating breaks AND, not OR, coverability" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // real (remaining, stride) requests over unit=8: too-few-bits (T,F),
    // an indivisible remainder (F,T), and an exact/divisible one (F,F) —
    // mirroring the compiler's `/binary`-tail ensure.
    // (10,16) is the KEY vector: too few bits AND an indivisible difference —
    // the ONE state where the short-circuit gate matters. Gated it is (T,F);
    // DROP the gate and it becomes (T,T), tripping the no-(T,T) assertion below
    // (this is what kills the "drop the !c0 gate" mutant).
    const inputs = [_][2]i64{ .{ 8, 16 }, .{ 10, 16 }, .{ 20, 16 }, .{ 24, 16 }, .{ 32, 16 } };
    for (inputs) |in| _ = bsEnsureReject(&coll, gpa, in[0], in[1], 8);
    // Both conditions are independently demonstrable — c0 via (T,F) vs (F,F),
    // c1 via (F,T) vs (F,F) — so MC/DC IS achieved, WITHOUT the unrealizable
    // (T,T). The refuted coverability hypothesis is itself the finding.
    try std.testing.expect(mcdcAchieved(2, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 0));
    try std.testing.expect(conditionIndependent(coll.items(), 1));
    // the short-circuit-impossible (T,T) never appears, and was never needed.
    for (coll.items()) |r| try std.testing.expect(!(r.vec[0] and r.vec[1]));
}

test "LAW E32-T2 AUTOMATED MC/DC (matchspec is_list, mutually-exclusive OR-2): nil/cons/atom achieve MC/DC; the impossible (T,T) is never needed" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    _ = isListGuard(&coll, gpa, true, false); //  nil  → (T,F)→true  (isolates c0)
    _ = isListGuard(&coll, gpa, false, true); //  cons → (F,T)→true  (isolates c1)
    _ = isListGuard(&coll, gpa, false, false); // atom → (F,F)→false
    try std.testing.expect(mcdcAchieved(2, coll.items()));
    // the mutually-exclusive (T,T) never appears — and MC/DC did not need it.
    // EXACT-PIN (CAST-17): nil(T,F), cons(F,T), atom(F,F) — no (T,T).
    try expectVecs(&coll, &.{ .{ true, false }, .{ false, true }, .{ false, false } });

    // a subset that never sees `cons` cannot isolate c1 (is_cons).
    var sub = Collector{};
    defer sub.deinit(gpa);
    _ = isListGuard(&sub, gpa, true, false);
    _ = isListGuard(&sub, gpa, false, false);
    try std.testing.expect(!mcdcAchieved(2, sub.items()));
}

// ── E33-T3: the census reaches the SUBSTRATE (substrate/alloc.zig) ──
//
// Decision 12 — `substrate.alloc.Allctr.liveBlock` guard: a handle is INVALID
// iff `h >= blocks.len OR !block.live` (the affine-handle gate the AFFINE law
// pins). `!live` is SHORT-CIRCUIT gated on the bounds check (a dead-block read
// only happens when h is in range), so (c0=T, c1=T) is unrealizable — and, per
// the E32-T2 boundary finding, this OR-2 STILL ACHIEVES MC/DC (c1's pair lives
// at c0=F). The census now spans Stratum A (terms/matchspec/bits) AND the
// E-substrate final encoding — the SAME coupling-class boundary in both.
fn allocLiveGuard(c: ?*Collector, gpa: std.mem.Allocator, out_of_range: bool, is_dead: bool) bool {
    const c0 = out_of_range;
    const c1 = !c0 and is_dead; // liveness is only read once the handle is in range
    const outcome = c0 or c1;
    tap(c, gpa, &[_]bool{ c0, c1 }, outcome);
    return outcome;
}

test "LAW E33-T3 AUTOMATED MC/DC (substrate alloc liveBlock guard, short-circuit OR-2): ACHIEVES MC/DC — the census reaches the substrate" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // real handle states: out-of-range (T,F), a live in-range handle (F,F),
    // a dead in-range handle (F,T) — the three AFFINE-law inputs.
    _ = allocLiveGuard(&coll, gpa, true, false); //  oob    → (T,F)→invalid  (isolates c0)
    _ = allocLiveGuard(&coll, gpa, false, false); // live   → (F,F)→valid
    _ = allocLiveGuard(&coll, gpa, false, true); //  dead   → (F,T)→invalid  (isolates c1)
    // KEY vector: a caller passing an out-of-range handle it also thinks is
    // dead — the short-circuit gate collapses it to (T,F); DROP the gate and it
    // becomes (T,T), tripping the no-(T,T) assertion (kills the drop-gate mutant).
    _ = allocLiveGuard(&coll, gpa, true, true);
    try std.testing.expect(mcdcAchieved(2, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 0));
    try std.testing.expect(conditionIndependent(coll.items(), 1));
    // the short-circuit-impossible (oob AND dead) never appears, never needed.
    // EXACT-PIN (CAST-17) replaces the length-trusting reduce: the 4 taps are
    // oob(T,F), live(F,F), dead(F,T), oob+dead-collapsed(T,F) — no (T,T).
    try expectVecs(&coll, &.{ .{ true, false }, .{ false, false }, .{ false, true }, .{ true, false } });
}

// ── E34-T3: the census reaches the RECEIVE ENGINE (instr_algebra wait_timeout) ──
//
// Decision 13 — `instr_algebra.wait_timeout` lost-wakeup guard (E34-T1, the
// recv-after-uncond fix): re-enter the receive loop WITHOUT arming iff
// `recv_scanned AND mbox.len() > recv_cursor`. A short-circuit AND-2 whose second
// operand (the mailbox comparison) is EVALUATED only when `recv_scanned` holds.
// This COMPLETES the coupling-class boundary: Decisions 10/11/12 showed a
// short-circuit OR-2 STILL achieves MC/DC (the second condition's independence
// pair lives at c0=F, which the gate permits); this AND-2 does NOT — c0
// (recv_scanned) has NO independence pair, because holding c1 (the gated
// comparison) TRUE while flipping c0 to false is exactly what short-circuiting
// forbids (c1 is masked to false whenever c0 is false). So the general rule is
// symmetric to Decision 3's arithmetic coupling but STRUCTURAL: short-circuit AND
// breaks first-condition coverability; short-circuit OR does not. (c1 IS
// independently demonstrable — (T,T) vs (T,F) — so only c0 is uncovered.) The
// finding is the REFUTED naive hypothesis "independent inputs ⇒ AND is coverable",
// captured from the real tapped rows, not asserted.
fn recvLostWakeupGuard(c: ?*Collector, gpa: std.mem.Allocator, recv_scanned: bool, has_unseen_msg: bool) bool {
    const c0 = recv_scanned;
    const c1 = c0 and has_unseen_msg; // the comparison is short-circuit-gated on c0
    const outcome = c1;
    tap(c, gpa, &[_]bool{ c0, c1 }, outcome);
    return outcome;
}

test "LAW E34-T3 AUTOMATED MC/DC (wait_timeout lost-wakeup guard, short-circuit AND-2): does NOT achieve MC/DC — short-circuit AND breaks first-condition coverability" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // the realizable receive states (all reachable in the real VM):
    _ = recvLostWakeupGuard(&coll, gpa, true, true); //   selective + new msg      → (T,T)→re-scan
    _ = recvLostWakeupGuard(&coll, gpa, false, true); //  UNCONDITIONAL + queued    → (F,·)→(F,F) gated (the bug case)
    _ = recvLostWakeupGuard(&coll, gpa, true, false); //  selective, fully scanned  → (T,F)→arm
    _ = recvLostWakeupGuard(&coll, gpa, false, false); // unconditional, empty      → (F,F)
    // c1 (the gated comparison) IS independently demonstrable — (T,T) vs (T,F) —
    // but c0 (recv_scanned) is NOT: every c0-flip drags c1 from T to F (the mask),
    // so no pair differs in c0 ALONE. Hence MC/DC is NOT achieved (the AND-side of
    // the short-circuit coupling boundary — the OR-side, Decisions 10/12, DID).
    try std.testing.expect(!mcdcAchieved(2, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 1));
    try std.testing.expect(!conditionIndependent(coll.items(), 0));
    // the gate holds in every tapped row: c1 is never true while c0 is false.
    for (coll.items()) |r| try std.testing.expect(!(!r.vec[0] and r.vec[1]));
}

// ── E43-T3: a NESTED (a OR b) AND (c OR d) decision (term number-cmp guard) ──
//
// Decision 22 — `term_algebra` @874 number-comparison precondition:
// `(x is int OR x is float) AND (y is int OR y is float)` — a genuinely NESTED
// decision (two ORs under an AND), the frontier the earlier flat AND-n/OR-n/mixed
// decisions did not reach. Tapping the SHORT-CIRCUIT-evaluated values (the second
// OR is gated on the first being true; each OR's 2nd disjunct is gated on its 1st
// being false), the masking interacts across BOTH levels. The finding, read from
// the realizable {int,float,other}² inputs: the outer-AND gating masks the SECOND
// operand's conditions when the first operand is false, and the OR gating masks
// each 2nd disjunct — so NOT every condition is independently coverable and MC/DC
// is not achieved; the coverable set is exactly those conditions whose flip
// changes the outcome with all gates satisfied. The nested structure inherits both
// the AND-side and OR-side masking simultaneously.
fn numberCmpGuard(c: ?*Collector, gpa: std.mem.Allocator, x_int: bool, x_float: bool, y_int: bool, y_float: bool) bool {
    const left = x_int or x_float;
    const c0 = x_int; //                         evaluated always
    const c1 = !x_int and x_float; //            OR: 2nd disjunct eval'd iff 1st false
    const c2 = left and y_int; //                AND: right eval'd iff left; then y_int
    const c3 = left and !y_int and y_float; //   right OR: 2nd disjunct eval'd iff 1st false
    const outcome = left and (y_int or y_float);
    tap(c, gpa, &[_]bool{ c0, c1, c2, c3 }, outcome);
    return outcome;
}

test "LAW E43-T3 AUTOMATED MC/DC (nested (a OR b) AND (c OR d) number-cmp guard): the nested structure inherits AND+OR masking — MC/DC not achieved" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // x,y each exactly one kind: int (T,F), float (F,T), other (F,F). Drive all 9.
    const kinds = [_][2]bool{ .{ true, false }, .{ false, true }, .{ false, false } };
    for (kinds) |xk| for (kinds) |yk| {
        _ = numberCmpGuard(&coll, gpa, xk[0], xk[1], yk[0], yk[1]);
    };
    // the nested short-circuit gates hold in every tapped row:
    //   c1 ⇒ !c0 (OR: 2nd disjunct only when 1st is false)
    //   c2 ⇒ (c0 or c1) i.e. the left side (AND: right only when left)
    //   c3 ⇒ (c0 or c1) and !c2 (right OR: 2nd disjunct only when left AND !y_int)
    for (coll.items()) |r| {
        try std.testing.expect(!(r.vec[1] and r.vec[0])); //           c1 ⇒ !c0
        try std.testing.expect(!(r.vec[2] and !(r.vec[0] or r.vec[1]))); // c2 ⇒ left
        try std.testing.expect(!(r.vec[3] and !(r.vec[0] or r.vec[1]))); // c3 ⇒ left
        try std.testing.expect(!(r.vec[3] and r.vec[2])); //          c3 ⇒ !c2
    }
    // the nested decision does NOT achieve unique-cause MC/DC — the two-level
    // short-circuit gating masks conditions the flat shapes could cover.
    try std.testing.expect(!mcdcAchieved(4, coll.items()));
    // but SOME conditions ARE coverable (the ones whose flip changes the outcome
    // with the gates satisfied) — the nested structure is not fully masked either.
    var any_cov = false;
    var k: usize = 0;
    while (k < 4) : (k += 1) if (conditionIndependent(coll.items(), k)) {
        any_cov = true;
    };
    try std.testing.expect(any_cov);
}

// ── E42-T3: the census reaches decode_packet's ssl_tls framer (record guard) ──
//
// Decision 21 — `bifs/erlang.decode_packet_3` ssl_tls completeness guard (E42-T1):
// a TLS record is fully present iff `bin_sz >= 5 (the header) AND bin_sz >= total
// (5 + record length)`. A SHORT-CIRCUIT AND-2 with a REAL dependency: `total` is
// computed from the 5-byte header, so `bin_sz >= total` is only MEANINGFUL once
// `bin_sz >= 5` — the exact type-precondition coupling of Decisions 13/15. So only
// the second condition (`bin_sz >= total`) is independently coverable; the first
// (`bin_sz >= 5`) is masked. The census now spans EVERY decode_packet structured
// parser (http version AND-4 Decision 20, this ssl_tls AND-2) — the AND-side rule
// holds identically in the newly-EQ bif's code.
fn sslTlsCompleteGuard(c: ?*Collector, gpa: std.mem.Allocator, has_header: bool, has_full_record: bool) bool {
    const c0 = has_header; //             bin_sz >= 5
    const c1 = c0 and has_full_record; // bin_sz >= total (total needs the header)
    tap(c, gpa, &[_]bool{ c0, c1 }, c1);
    return c1;
}

test "LAW E42-T3 AUTOMATED MC/DC (ssl_tls record guard, short-circuit AND-2): only the 2nd condition coverable — the census reaches the ssl_tls framer" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // the realizable buffer states: full record (T,T); header-but-short-data
    // (T,F); no header (F,·)→(F,F gated).
    _ = sslTlsCompleteGuard(&coll, gpa, true, true); //   full record          → (T,T)→ok
    _ = sslTlsCompleteGuard(&coll, gpa, true, false); //  header, short data   → (T,F)→more,total (isolates c1)
    _ = sslTlsCompleteGuard(&coll, gpa, false, false); // < 5 bytes            → (F,F)→more,undefined
    try std.testing.expect(!mcdcAchieved(2, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 1)); //  the 2nd condition
    try std.testing.expect(!conditionIndependent(coll.items(), 0)); // masked (total needs the header)
    for (coll.items()) |r| try std.testing.expect(!(r.vec[1] and !r.vec[0])); // c1 ⇒ c0
}

// ── E44-T? (cp-decode-packet-fold): the httph obs-fold continuation guard ──
//
// Decision 22 — `bifs/erlang.decode_packet_3` httph fold guard (cp-decode-packet-fold):
// a header value continues onto the next line iff `isWs(byte-after-\n) AND line-len>2`.
// A SHORT-CIRCUIT AND-2 whose two conditions are SEMANTICALLY INDEPENDENT (the next
// byte being whitespace and the current line being longer than "\r\n" are unrelated
// facts — unlike Decisions 13/15/21 where the 2nd condition DEPENDS on the 1st).
// Yet the coverability outcome is IDENTICAL: only c1 (`len>2`) is independently
// coverable, c0 (`isWs`) is masked — because the SHORT-CIRCUIT `and` forbids the
// (F,T) row (when isWs is false, `len>2` is never evaluated). This ISOLATES the cause
// of AND-side masking as STRUCTURAL (short-circuit evaluation), not semantic coupling:
// the masking holds even when the conditions are independent. The distinguishing case
// in the coupling-boundary census.
fn foldContinueGuard(c: ?*Collector, gpa: std.mem.Allocator, is_ws: bool, line_gt2: bool) bool {
    const c0 = is_ws;
    const c1 = c0 and line_gt2; // short-circuit: length only checked once ws holds
    tap(c, gpa, &[_]bool{ c0, c1 }, c1);
    return c1;
}

test "LAW E44 (cp-decode-packet-fold) AUTOMATED MC/DC (httph fold guard, short-circuit AND-2 with INDEPENDENT conditions): only c1 coverable — masking is STRUCTURAL not semantic" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // realizable inputs: fold (T,T); ws but short line (T,F)→isolates c1; non-ws (F,·)→(F,F gated).
    _ = foldContinueGuard(&coll, gpa, true, true); //   ws + long line → (T,T)→fold
    _ = foldContinueGuard(&coll, gpa, true, false); //  ws + "\r\n"     → (T,F)→stop (isolates c1)
    _ = foldContinueGuard(&coll, gpa, false, false); // non-ws         → (F,F)→stop
    try std.testing.expect(!mcdcAchieved(2, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 1)); //  c1 (len>2) coverable
    try std.testing.expect(!conditionIndependent(coll.items(), 0)); // c0 (isWs) masked by short-circuit
    // the short-circuit forbids (F,T): c1 ⇒ c0, EXACTLY as when the conditions are
    // semantically coupled — proving the masking is structural.
    for (coll.items()) |r| try std.testing.expect(!(r.vec[1] and !r.vec[0]));
}

// ── E41-T3: a 4-CONDITION short-circuit AND (decode_packet http version guard) ──
//
// Decision 20 — `bifs/erlang.versionTerm` (E41-T1 http parser): an HTTP version
// token is valid iff `startsWith("HTTP/") AND has '.' AND major parses AND minor
// parses`. A SHORT-CIRCUIT AND-4, each condition gated on all the earlier ones
// (`indexOf('.')` needs the prefix stripped; `parseInt(major)` needs the dot;
// `parseInt(minor)` needs the dot). This EXTENDS the AND-side masking finding
// (Decisions 13/15, AND-2/AND-3) to n=4: ONLY the LAST condition (minor parses) is
// independently coverable; the first THREE are masked (flipping any drags all the
// following gated conditions to false). The count of masked conditions grows with
// n exactly as the AND-n rule predicts — the highest-arity confirmation in the census.
fn httpVersionGuard(c: ?*Collector, gpa: std.mem.Allocator, has_prefix: bool, has_dot: bool, maj_ok: bool, min_ok: bool) bool {
    const c0 = has_prefix;
    const c1 = c0 and has_dot;
    const c2 = c1 and maj_ok;
    const c3 = c2 and min_ok;
    tap(c, gpa, &[_]bool{ c0, c1, c2, c3 }, c3);
    return c3;
}

test "LAW E41-T3 AUTOMATED MC/DC (http version guard, short-circuit AND-4): only the LAST condition is coverable — AND-side masking at n=4" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // the realizable version-token states (all reachable in the parser):
    _ = httpVersionGuard(&coll, gpa, true, true, true, true); //   "HTTP/1.1" → (T,T,T,T)→valid
    _ = httpVersionGuard(&coll, gpa, true, true, true, false); //  "HTTP/1."  → (T,T,T,F)→invalid (isolates c3)
    _ = httpVersionGuard(&coll, gpa, true, true, false, false); // "HTTP/x.y" → (T,T,F,F) (maj parse fails)
    _ = httpVersionGuard(&coll, gpa, true, false, false, false); // "HTTP/11" → (T,F,F,F) (no dot)
    _ = httpVersionGuard(&coll, gpa, false, false, false, false); // "GET"    → (F,F,F,F) (no prefix)
    // ONLY c3 (minor parses) has an independence pair — (T,T,T,T) vs (T,T,T,F).
    // c0/c1/c2 are masked (each flip drags the later gated conditions to false).
    try std.testing.expect(!mcdcAchieved(4, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 3));
    try std.testing.expect(!conditionIndependent(coll.items(), 2));
    try std.testing.expect(!conditionIndependent(coll.items(), 1));
    try std.testing.expect(!conditionIndependent(coll.items(), 0));
    // the gate chain holds: c_{k+1} ⇒ c_k in every tapped row.
    for (coll.items()) |r| {
        try std.testing.expect(!(r.vec[1] and !r.vec[0]));
        try std.testing.expect(!(r.vec[2] and !r.vec[1]));
        try std.testing.expect(!(r.vec[3] and !r.vec[2]));
    }
}

// ── E40-T3: the census REACHES the boot's IO domain (boot.zig RealRes fd guard) ──
//
// Decision 19 — the boot IO backend's fd guard (`substrate/boot.zig` `RealRes`/
// `ModelRes` iowrite/ioread/ioclose): an fd is INVALID iff `fd >= files.len OR
// !fopen[fd]`. `!fopen[fd]` is SHORT-CIRCUIT gated on the bounds check (a
// closed-flag read only happens once the fd is in range), so (c0=T, c1=T) is
// unrealizable — and, per the OR-side result, this OR-2 STILL ACHIEVES MC/DC (c1's
// pair lives at c0=F). This EXTENDS the census's REACH: the coverability map now
// spans Stratum A (terms/matchspec/bits), the resource kernels (alloc), the receive
// engine, AND the full boot's IO domain — the same OR-side coverability throughout.
fn bootIoFdGuard(c: ?*Collector, gpa: std.mem.Allocator, out_of_range: bool, is_closed: bool) bool {
    const c0 = out_of_range;
    const c1 = !c0 and is_closed; // the closed-flag is read only when the fd is in range
    const outcome = c0 or c1;
    tap(c, gpa, &[_]bool{ c0, c1 }, outcome);
    return outcome;
}

test "LAW E40-T3 AUTOMATED MC/DC (boot IO fd guard, short-circuit OR-2): ACHIEVES MC/DC — the census reaches the boot's IO domain" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // real fd states: out-of-range (T,F), an open in-range fd (F,F), a closed
    // in-range fd (F,T) — the three fd-validity inputs the boot io ops face.
    _ = bootIoFdGuard(&coll, gpa, true, false); //  oob    → (T,F)→invalid (isolates c0)
    _ = bootIoFdGuard(&coll, gpa, false, false); // open   → (F,F)→valid
    _ = bootIoFdGuard(&coll, gpa, false, true); //  closed → (F,T)→invalid (isolates c1)
    // KEY vector: a caller passing an out-of-range fd it also thinks is closed —
    // the short-circuit gate collapses it to (T,F); DROP the gate and it becomes
    // (T,T), tripping the no-(T,T) assertion (kills the drop-gate mutant).
    _ = bootIoFdGuard(&coll, gpa, true, true);
    try std.testing.expect(mcdcAchieved(2, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 0));
    try std.testing.expect(conditionIndependent(coll.items(), 1));
    for (coll.items()) |r| try std.testing.expect(!(r.vec[0] and r.vec[1]));
}

// ── E39-T3: an AND-2 whose conditions ARE both coverable (scheduler runnable gate) ──
//
// Decision 18 — the substrate scheduler's RUNNABLE gate (`substrate/boot.zig`/
// `sched.zig` run-loop): a process runs iff `alive AND !blocked`. This CLOSES the
// AND-side coverability map. Decisions 13/15 showed a short-circuit AND masks its
// earlier conditions — but ONLY because their second condition is UNSAFE to evaluate
// without the first (`smallVal(w)` needs `repIsSmall(w)`; the type-precondition
// coupling). Here the two conditions are INDEPENDENT PROCESS-STATE FACTS: reading
// `blocked` never depends on `alive` (both are always-valid struct fields), so the
// honest tap is the RAW values — both always meaningful — and ALL FOUR combos are
// realizable process states {alive+runnable, alive+blocked, dead, dead+blocked}. So
// the AND-2 ACHIEVES unique-cause MC/DC. The sharp rule: a (short-circuit) AND masks
// its first condition IFF the second is unsafe-to-evaluate-independently; when both
// conditions are independently evaluable facts, the AND is fully coverable.
fn runnableGuard(c: ?*Collector, gpa: std.mem.Allocator, alive: bool, not_blocked: bool) bool {
    // both operands are independent facts (safe to read in either order) ⇒ tapped RAW.
    const outcome = alive and not_blocked;
    tap(c, gpa, &[_]bool{ alive, not_blocked }, outcome);
    return outcome;
}

test "LAW E39-T3 AUTOMATED MC/DC (scheduler runnable gate alive AND !blocked, independent AND-2): ACHIEVES MC/DC — the AND is coverable when its conditions are independently evaluable" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // all four realizable process states (the run-loop actually reaches each):
    _ = runnableGuard(&coll, gpa, true, true); //   alive + runnable   → (T,T)→run
    _ = runnableGuard(&coll, gpa, true, false); //  alive but blocked  → (T,F)→skip (isolates c1)
    _ = runnableGuard(&coll, gpa, false, true); //  dead, not blocked  → (F,T)→skip (isolates c0)
    _ = runnableGuard(&coll, gpa, false, false); // dead + blocked     → (F,F)→skip
    // BOTH conditions have an independence pair — c0 via (T,T) vs (F,T), c1 via
    // (T,T) vs (T,F) — because the "impossible" combo is realizable here (unlike a
    // short-circuit-coupled AND). So the AND-2 achieves unique-cause MC/DC.
    try std.testing.expect(mcdcAchieved(2, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 0));
    try std.testing.expect(conditionIndependent(coll.items(), 1));
    // the coupled-AND's forbidden combo (F,T) — impossible for Decisions 13/15 — IS
    // present here, which is exactly WHY both conditions are coverable.
    var saw_ft = false;
    for (coll.items()) |r| if (!r.vec[0] and r.vec[1]) {
        saw_ft = true;
    };
    try std.testing.expect(saw_ft);
}

// ── E38-T3: a MIXED (a AND b) OR c decision (bin_algebra packetRemain guard) ──
//
// Decision 17 — `bin_algebra.packetRemain` @151 invalid-guard: a framed packet is
// INVALID iff `(max_plen != 0 AND plen > max_plen) OR tlen < hlen` — a MIXED
// AND/OR (`(c0 AND c1) OR c2`). This combines both boundary findings. Tapping the
// SHORT-CIRCUIT-evaluated values (c1 evaluated only when c0; c2 only when the AND
// is false), the analysis is NUANCED: the OR arm c2 is coverable, AND the inner
// AND's SECOND condition c1 is coverable (via c0=T rows), but the inner AND's FIRST
// condition c0 is MASKED — c0 alone never flips the outcome (it needs c1), so no
// pair differs in c0 with a different result. So the short-circuit AND masking of
// the first condition SURVIVES embedding in an OR, while the OR arm stays fully
// coverable — MC/DC is NOT achieved, but for a different reason than pure AND-n.
fn packetInvalidGuard(c: ?*Collector, gpa: std.mem.Allocator, c0_raw: bool, c1_raw: bool, c2_raw: bool) bool {
    const and_part = c0_raw and c1_raw;
    const ev_c0 = c0_raw;
    const ev_c1 = c0_raw and c1_raw; //     c1 (plen>max_plen) evaluated only when c0 (max_plen!=0)
    const ev_c2 = !and_part and c2_raw; //  c2 (tlen<hlen) evaluated only when the AND is false
    const outcome = and_part or c2_raw;
    tap(c, gpa, &[_]bool{ ev_c0, ev_c1, ev_c2 }, outcome);
    return outcome;
}

test "LAW E38-T3 AUTOMATED MC/DC (packetRemain (a AND b) OR c, mixed): NOT achieved — the OR arm + inner-AND's 2nd cond cover, but its 1st is masked" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // the distinct realizable raw states (max_plen/plen/tlen/hlen combinations):
    _ = packetInvalidGuard(&coll, gpa, false, false, false); // in-range, no cap      → (F,F,F)→valid
    _ = packetInvalidGuard(&coll, gpa, false, false, true); //  tlen<hlen overflow     → (F,F,T)→invalid (isolates c2)
    _ = packetInvalidGuard(&coll, gpa, true, false, false); //  capped, plen<=max      → (T,F,F)→valid
    _ = packetInvalidGuard(&coll, gpa, true, false, true); //   capped ok, tlen<hlen   → (T,F,T)→invalid
    _ = packetInvalidGuard(&coll, gpa, true, true, false); //   over the cap           → (T,T,F)→invalid (isolates c1)
    // c1 (the cap comparison) and c2 (the OR arm) each have an independence pair, but
    // c0 (max_plen!=0) does NOT — c0 alone never changes the result (it gates c1), so
    // the short-circuit AND masks it even inside the OR. MC/DC is NOT achieved.
    try std.testing.expect(!mcdcAchieved(3, coll.items()));
    try std.testing.expect(!conditionIndependent(coll.items(), 0)); // masked
    try std.testing.expect(conditionIndependent(coll.items(), 1)); //  the inner-AND's 2nd cond
    try std.testing.expect(conditionIndependent(coll.items(), 2)); //  the OR arm
    // the gates hold: c1 ⇒ c0 (evaluated only when c0), and c2 is never true while
    // the AND part is true (c2 is the OR arm, reached only when the AND is false).
    for (coll.items()) |r| {
        try std.testing.expect(!(r.vec[1] and !r.vec[0]));
        try std.testing.expect(!(r.vec[2] and r.vec[1]));
    }
}

// ── E37-T3: a 3-CONDITION OR — the OR-side generalises to n (is_number guard) ──
//
// Decision 16 — `is_number` guard: a term is a number iff `repIsSmall(w) OR
// repIsBig(w) OR repIsFloat(w)` (the BEAM `is_number` type test). A 3-condition OR
// whose conditions are MUTUALLY EXCLUSIVE (a term is exactly one kind), so every
// (T,T,·)/(·,T,T)/… combo is unrealizable — yet, unlike the short-circuit AND-3
// (Decision 15, where only the LAST condition is coverable), this OR-3 ACHIEVES
// unique-cause MC/DC: each condition is isolated against the ALL-FALSE anchor
// {small→(T,F,F), big→(F,T,F), float→(F,F,T), atom→(F,F,F)}. This is the OR-side
// counterpart of Decision 15 and confirms the boundary is AND-vs-OR at EVERY arity:
// short-circuit AND-n masks all but the last condition; OR-n stays fully coverable
// via the all-false anchor (the impossible high combos are never needed).
fn isNumberGuard(c: ?*Collector, gpa: std.mem.Allocator, is_small: bool, is_big: bool, is_float: bool) bool {
    const outcome = is_small or is_big or is_float;
    tap(c, gpa, &[_]bool{ is_small, is_big, is_float }, outcome);
    return outcome;
}

test "LAW E37-T3 AUTOMATED MC/DC (is_number, mutually-exclusive OR-3): ACHIEVES MC/DC — the OR-side stays fully coverable at n=3 (unlike AND-3)" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // the four realizable term kinds (all reachable — real is_number inputs):
    _ = isNumberGuard(&coll, gpa, true, false, false); //  a small  → (T,F,F)→number (isolates c0)
    _ = isNumberGuard(&coll, gpa, false, true, false); //  a bignum → (F,T,F)→number (isolates c1)
    _ = isNumberGuard(&coll, gpa, false, false, true); //  a float  → (F,F,T)→number (isolates c2)
    _ = isNumberGuard(&coll, gpa, false, false, false); // an atom  → (F,F,F)→not-a-number (the anchor)
    // every condition has an independence pair against the all-false anchor, so the
    // OR-3 achieves unique-cause MC/DC — WITHOUT any unrealizable multi-true combo.
    try std.testing.expect(mcdcAchieved(3, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 0));
    try std.testing.expect(conditionIndependent(coll.items(), 1));
    try std.testing.expect(conditionIndependent(coll.items(), 2));
    // the mutually-exclusive multi-true combos never appear (a term is one kind).
    for (coll.items()) |r| {
        const trues = @as(u8, @intFromBool(r.vec[0])) + @intFromBool(r.vec[1]) + @intFromBool(r.vec[2]);
        try std.testing.expect(trues <= 1);
    }
}

// ── E36-T3: the census's FIRST 3-CONDITION decision (term_algebra byte guard) ──
//
// Decision 15 — `term_algebra` @3345 byte-range guard `isByte(w)`: a term is a
// valid byte iff `repIsSmall(w) AND smallVal(w) >= 0 AND smallVal(w) <= 255`. A
// SHORT-CIRCUIT AND-3: `smallVal` is read only when `repIsSmall` (c1/c2 gated on
// c0), and `<= 255` is evaluated only when `>= 0` (c2 gated on c1). This EXTENDS
// the AND-side coupling finding (Decisions 3/13, both AND-2) to three conditions,
// and the masking is RICHER: in a short-circuit AND-n, ONLY the LAST condition is
// independently coverable — every earlier condition is masked, because flipping it
// to false drags all following (gated) conditions to false too, so no pair differs
// in that condition ALONE. Here c2 (`<= 255`) IS coverable (a small in-range vs a
// small over 255), but c0 (`is_small`) and c1 (`>= 0`) are BOTH masked. So MC/DC is
// NOT achieved, and the count of masked conditions grows with n — the general shape
// of the boundary the 2-condition decisions only hinted at.
fn isByteGuard(c: ?*Collector, gpa: std.mem.Allocator, is_small: bool, ge0: bool, le255: bool) bool {
    const c0 = is_small;
    const c1 = c0 and ge0; //   the value is read only when small
    const c2 = c1 and le255; // the upper bound is checked only when small AND >= 0
    tap(c, gpa, &[_]bool{ c0, c1, c2 }, c2);
    return c2;
}

test "LAW E36-T3 AUTOMATED MC/DC (term byte-range guard, short-circuit AND-3): only the LAST condition is coverable — the AND-side masking extends to n conditions" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // the realizable term states (all reachable — real byte/latin1 inputs):
    _ = isByteGuard(&coll, gpa, true, true, true); //   a small in [0,255]  → (T,T,T)→byte
    _ = isByteGuard(&coll, gpa, true, true, false); //  a small > 255       → (T,T,F)→not (isolates c2)
    _ = isByteGuard(&coll, gpa, true, false, false); // a NEGATIVE small    → (T,F,F) (c1 false ⇒ c2 gated F)
    _ = isByteGuard(&coll, gpa, false, false, false); // a non-small (atom) → (F,F,F) (c0 false ⇒ all gated F)
    // ONLY c2 has an independence pair — (T,T,T) vs (T,T,F). c0 and c1 are masked:
    // flipping either drags the later gated conditions to false, so no pair differs
    // in c0 (or c1) alone. Hence MC/DC is NOT achieved for the AND-3.
    try std.testing.expect(!mcdcAchieved(3, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 2));
    try std.testing.expect(!conditionIndependent(coll.items(), 1));
    try std.testing.expect(!conditionIndependent(coll.items(), 0));
    // the gate holds in every tapped row: a later condition is never true unless
    // every earlier one is (c1 ⇒ c0; c2 ⇒ c1).
    for (coll.items()) |r| {
        try std.testing.expect(!(r.vec[1] and !r.vec[0]));
        try std.testing.expect(!(r.vec[2] and !r.vec[1]));
    }
}

// ── E35-T3: a NUMERICALLY mutually-exclusive OR-2 (recv-after-badtimeout range) ──
//
// Decision 14 — `instr_algebra.wait_timeout` timeout-value range check (E34-T1,
// the recv-after-badtimeout fix): a timeout is INVALID iff `ms < 0 OR ms >
// 0xFFFF_FFFF`. The two conditions are MUTUALLY EXCLUSIVE by ARITHMETIC — a single
// integer cannot be both below 0 and above 2^32-1 — so (c0=T, c1=T) is
// unrealizable. This is a THIRD kind of "impossible (T,T)" in the census: not
// short-circuit gating (Decisions 10/12) and not a type-tag partition (Decision 11
// is_list nil/cons), but NUMERIC mutual exclusion. And, like every OR-2 in the
// census, it STILL ACHIEVES MC/DC without the impossible combo: {below→(T,F),
// above→(F,T), in-range→(F,F)} give both independence pairs — reinforcing that the
// coupling boundary is AND-vs-OR (Decision 13), independent of WHY (T,T) is
// impossible. Neither condition is short-circuit-gated here (both are pure
// comparisons on `ms`), so the tap records the real evaluated values of each.
fn badTimeoutRange(c: ?*Collector, gpa: std.mem.Allocator, below_zero: bool, above_max: bool) bool {
    const outcome = below_zero or above_max;
    tap(c, gpa, &[_]bool{ below_zero, above_max }, outcome);
    return outcome;
}

test "LAW E35-T3 AUTOMATED MC/DC (recv-after-badtimeout range, numerically mutually-exclusive OR-2): ACHIEVES MC/DC; the impossible (T,T) is never needed" {
    const gpa = std.testing.allocator;
    var coll = Collector{};
    defer coll.deinit(gpa);
    // real ms values: -1 (below,  T,F), 2^32 (above, F,T), 5 (in-range, F,F).
    _ = badTimeoutRange(&coll, gpa, true, false); //  ms=-1     → (T,F)→invalid (isolates c0)
    _ = badTimeoutRange(&coll, gpa, false, true); //  ms=2^32   → (F,T)→invalid (isolates c1)
    _ = badTimeoutRange(&coll, gpa, false, false); // ms=5      → (F,F)→valid
    try std.testing.expect(mcdcAchieved(2, coll.items()));
    try std.testing.expect(conditionIndependent(coll.items(), 0));
    try std.testing.expect(conditionIndependent(coll.items(), 1));
    // the arithmetically-impossible (below AND above) never appears — nor is it
    // needed for MC/DC (the OR-side of the boundary, as Decisions 10/11/12).
    for (coll.items()) |r| try std.testing.expect(!(r.vec[0] and r.vec[1]));
}

test "LAW E28-T2 AUTOMATED MC/DC: vectors CAPTURED from the real E24-T10 inputs achieve MC/DC; a happy-only subset does not" {
    const gpa = std.testing.allocator;
    // the ACTUAL (start,stop) inputs the E24-T10 law drives (len = 5).
    const t10 = [_][2]i64{
        .{ 1, 5 }, .{ 1, 1 }, .{ 5, 5 }, .{ 3, 3 }, .{ 2, 4 },
        .{ 0, 3 }, .{ -1, 3 }, .{ 1, 6 }, .{ 6, 6 }, .{ 3, 2 }, .{ 1, 0 },
    };
    var coll = Collector{};
    defer coll.deinit(gpa);
    for (t10) |in| _ = bl3Guard(&coll, gpa, in[0], in[1], 5);
    // MEASURED (not hand-modeled): the captured rows achieve MC/DC for the guard.
    try std.testing.expect(mcdcAchieved(3, coll.items()));

    // a happy-cases-only subset captures no independence pair → NOT MC/DC.
    var happy = Collector{};
    defer happy.deinit(gpa);
    const happy_inputs = [_][2]i64{ .{ 1, 5 }, .{ 1, 1 }, .{ 5, 5 }, .{ 3, 3 }, .{ 2, 4 } };
    for (happy_inputs) |in| _ = bl3Guard(&happy, gpa, in[0], in[1], 5);
    try std.testing.expect(!mcdcAchieved(3, happy.items()));
}
