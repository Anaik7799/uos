//! # bifs/lists — the `lists`/list-arithmetic BIF family (E2.6)
//!
//! ## Signature
//! Same contract as `bifs/erlang.zig`/`bifs/conv.zig`: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over ALREADY-
//! RESOLVED term arguments, computed via `term_algebra`'s EXISTING list/
//! tuple accessors — NO new term semantics live here — returning the result
//! term or a clean `error.Badarg`. It NEVER panics on a well-formed call.
//!
//! ## The dispatch mechanism (unchanged — see `bifs/dispatch.zig`)
//! This task adds ONLY `pub fn`s here, `implOf`/`implOfLists` arms in
//! `bifs/dispatch.zig`, and `implemented_map` rows in `harness/bif_gen.ml`.
//! The generated `bif_table.zig`, the loader, and the `bif_call` executor
//! are untouched.
//!
//! ## Semantic domain — reuse, not reinvention
//!   `lists:member/2`     — a fold-or over `eqlExact` (BEAM's `=:=`, EXACT
//!                          equality — `member(1, [1.0])` is `false`).
//!   `lists:reverse/2`    — fold-cons `List` onto `Tail` (the differential
//!                          law: `reverse(L, T)` == cons each element of `L`,
//!                          front-to-back, onto `T`).
//!   `lists:keyfind/3`    — the first tuple in `TupleList` whose element `N`
//!                          (1-based) is `eqlExact` `Key`, else `false`. Per
//!                          the pin (`erl_bif_lists.c:1301-1381`) a NON-TUPLE
//!                          element or a tuple too small for position `N` is
//!                          SILENTLY SKIPPED (proplist tolerance); `badarg`
//!                          only on a bad `N` or an IMPROPER list tail.
//!   `lists:keysearch/3`  — `keyfind`, wrapped `{value, Tuple}` | `false`.
//!   `lists:keymember/3`  — `keyfind`, projected to `true`/`false`.
//!   `erlang:'++'/2`      — list append: `A` must be a PROPER list (`badarg`
//!                          otherwise); `B` may be ANY term — `A ++ B`
//!                          legitimately produces an improper list when `B`
//!                          isn't one (real Erlang semantics, preserved).
//!   `erlang:'--'/2`      — list subtraction: for each element of `B` (in
//!                          order), remove the first not-yet-removed
//!                          `eqlExact` match in `A`; both `A` and `B` must be
//!                          PROPER lists (`badarg` otherwise).
//!
//! ## Lifetime safety (the E2.5 lesson, audited per fn below)
//! `term_algebra`'s `listHead`/`listTail`/`tupleElem` return Term VALUES —
//! tagged offsets into `ctx.words`, not raw byte slices — so holding one
//! across a later `cons`/`tuple` call that reallocates `ctx.words` is SAFE
//! (the offset is still valid post-realloc; only a raw `[]const u8` slice
//! from `binBytes` would dangle). None of the fns below ever take a
//! `binBytes`-derived slice, so none needs an off-heap dupe:
//!   - `member`/`keyfind`/`keysearch`/`keymember`: read-only walks, build no
//!     new terms at all (except the `{value, Tuple}` wrapper in keysearch,
//!     which conses only ALREADY-RESOLVED Term values: an atom and a tuple
//!     term returned unmodified from the walk).
//!   - `reverse_2`: each loop iteration holds only `Term` VALUES (`acc`,
//!     `listHead(cur)`) across the `cons` call — safe.
//!   - `append_2`: collects `A`'s elements as `Term` VALUES into a
//!     `std.ArrayList(Term)` (an m.gpa-owned buffer, independent of
//!     `ctx.words`) BEFORE folding onto `B` with `cons` — safe by
//!     construction; nothing aliases `ctx.words` across the fold.
//!   - `subtract_2`: same pattern as `append_2` — both `A` and `B` are
//!     collected into `Term`-VALUE arrays before any `cons` call runs.
//!
//! ## Cyclic-list bounding
//! `term_algebra`'s `cons` only ever accepts an ALREADY-CONSTRUCTED `tail`
//! Term (no `setListTail`/mutation primitive exists over cons cells — only
//! `setTupleElem` mutates in place, and only tuples). A cons cell's tail
//! therefore always denotes a term built strictly before it; the list graph
//! is a DAG by construction and a `while (true) { switch (kindOf(cur)) }`
//! walk (the same pattern `erlang:length/1` already uses, unguarded) cannot
//! loop forever — every walk below terminates in the list's length, an
//! ordinary bound, not a defensive counter. An improper (non-nil,
//! non-cons-chain) tail is rejected as `error.Badarg` at the point the walk
//! reaches it, so a malformed list still cannot hang the walk.
//!
//! ## Laws (see the test suite below)
//!   - DENOTATION  member(2,[1,2,3]) == true; reverse([1,2,3],[]) == [3,2,1];
//!     keyfind(b,1,[{a,1},{b,2}]) == {b,2}; [1,2]++[3,4] == [1,2,3,4];
//!     [1,2,3,2]--[2] == [1,3,2]
//!   - EXACT-KEY-EQUALITY  keyfind(1, 1, [{1.0}]) does NOT match (returns
//!     `false`) — `=:=`, not `==` (MUTANT target: swapping in `compare`'s
//!     `.eq` would wrongly match `1.0`).
//!   - SKIP-NON-CANDIDATE  keyfind(b,1,[x,{b,2}]) == {b,2} (a non-tuple
//!     element is skipped); keyfind(k,2,[{k},{a,k}]) == {a,k} (a too-small
//!     tuple is skipped on position 2) — proplist tolerance, matches the pin.
//!   - ROUND-TRIP  reverse(reverse(L, []), []) == L
//!   - REJECTION  an improper list / bad `N` (key ops) / improper `A` or `B`
//!     in `--`, improper `A` in `++` → a clean `error.Badarg` (never a panic/
//!     hang). A non-tuple/too-small key-op element is SKIPPED, not rejected.

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

/// A 1-based tuple position from a SMALL int term; `badarg` on anything else
/// (non-integer, zero, or negative) — BEAM's `keyfind`/`keysearch`/
/// `keymember` contract on a malformed `N`.
fn needPos(w: Term) BifError!usize {
    if (!FinalTerms.repIsSmall(w)) return error.Badarg;
    const v = FinalTerms.smallValOf(w);
    if (v < 1) return error.Badarg;
    return @intCast(v);
}

// ── lists:member/2, lists:reverse/2 ─────────────────────────────────────────

pub fn member(m: *Machine, args: []const Term) BifError!Term {
    const elem = args[0];
    var cur = args[1];
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => return boolTerm(m, false),
            .cons => {
                // MUTANT (member uses arith-eq instead of exact): swapping
                // `eqlExact` for `FinalTerms.compare(...) == .eq` would wrongly
                // match e.g. `member(1, [1.0])`.
                if (FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, cur), elem)) return boolTerm(m, true);
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg,
        }
    }
}

pub fn reverse_2(m: *Machine, args: []const Term) BifError!Term {
    // MUTANT (reverse/2 ignores the tail arg): seeding `acc` with `nil(&m.ctx)`
    // instead of `args[1]` would drop the tail and break the fold-cons law.
    var acc = args[1];
    var cur = args[0];
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => return acc,
            .cons => {
                acc = FinalTerms.cons(&m.ctx, FinalTerms.listHead(&m.ctx, cur), acc) catch return error.OutOfMemory;
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg,
        }
    }
}

// ── lists:keyfind/3, lists:keysearch/3, lists:keymember/3 ──────────────────

/// The shared walk: the first tuple in `list` whose (1-based) element `n` is
/// `eqlExact` `key`, or `null` if none matches. Faithful to the pin's shared
/// `keyfind` helper (`erl_bif_lists.c:1301-1381`): a list element is a match
/// CANDIDATE only when it `is_tuple` AND its arity `>= pos`; a non-tuple
/// element OR a too-small tuple is SILENTLY SKIPPED (the walk continues, NOT
/// an error). `error.Badarg` is raised in exactly TWO places: a bad `N` (not
/// a positive integer — `needPos` up front) and an IMPROPER list tail (the
/// `else => error.Badarg` after the walk exhausts the proper prefix — the pin
/// raises `BADARG` only at `if (is_not_nil(List))`). So: bad-N → badarg;
/// improper-tail → badarg; non-tuple/too-small element → skip; found → tuple;
/// exhausted (reached nil) → null (`false` at the public boundary).
fn keyFindImpl(m: *Machine, key: Term, n: Term, list: Term) BifError!?Term {
    const pos = try needPos(n);
    var cur = list;
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => return null,
            .cons => {
                const h = FinalTerms.listHead(&m.ctx, cur);
                // A non-tuple element or a tuple too short for position `pos`
                // is a NON-CANDIDATE — skip it (matches BEAM's proplist-style
                // tolerance: config lists mixing atoms and tuples work).
                // MUTANT-A (keyfind matches position 1 regardless of N):
                // hard-coding `tupleElem(&m.ctx, h, 0)` instead of `pos - 1`
                // would ignore the position argument entirely.
                // MUTANT-B (non-tuple element errors instead of skipping):
                // reverting the `.tuple` guard to `return error.Badarg` would
                // break the skip law `keyfind(b,1,[x,{b,2}]) == {b,2}`.
                if (FinalTerms.kindOf(&m.ctx, h) == .tuple) {
                    const arity = FinalTerms.tupleArity(&m.ctx, h);
                    if (pos <= arity and FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, h, pos - 1), key)) return h;
                }
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg,
        }
    }
}

pub fn keyfind(m: *Machine, args: []const Term) BifError!Term {
    if (try keyFindImpl(m, args[0], args[1], args[2])) |tup| return tup;
    return boolTerm(m, false);
}

pub fn keysearch(m: *Machine, args: []const Term) BifError!Term {
    if (try keyFindImpl(m, args[0], args[1], args[2])) |tup| {
        const value_idx = m.ctx.atoms.intern("value") catch return error.OutOfMemory;
        const value_atom = FinalTerms.atom(&m.ctx, value_idx);
        return FinalTerms.tuple(&m.ctx, &.{ value_atom, tup }) catch error.OutOfMemory;
    }
    return boolTerm(m, false);
}

pub fn keymember(m: *Machine, args: []const Term) BifError!Term {
    const found = try keyFindImpl(m, args[0], args[1], args[2]);
    return boolTerm(m, found != null);
}

// ── erlang:'++'/2, erlang:'--'/2 ────────────────────────────────────────────

/// A proper list's elements, collected as Term VALUES (realloc-safe, see the
/// module lifetime-safety note) into a caller-owned `m.gpa` array. `badarg`
/// on a non-list / improper tail.
fn properListElems(m: *Machine, l: Term) BifError!std.ArrayList(Term) {
    var out: std.ArrayList(Term) = .empty;
    errdefer out.deinit(m.gpa);
    var cur = l;
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => break,
            .cons => {
                out.append(m.gpa, FinalTerms.listHead(&m.ctx, cur)) catch return error.OutOfMemory;
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg,
        }
    }
    return out;
}

pub fn append_2(m: *Machine, args: []const Term) BifError!Term {
    var elems = try properListElems(m, args[0]);
    defer elems.deinit(m.gpa);
    // Fold-cons the collected (already off-heap) elements onto B from the
    // right — B may be ANY term (an improper result is legal when B isn't a
    // list, matching real `++` semantics).
    var acc = args[1];
    var i = elems.items.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, elems.items[i], acc) catch return error.OutOfMemory;
    }
    return acc;
}

pub fn subtract_2(m: *Machine, args: []const Term) BifError!Term {
    var a = try properListElems(m, args[0]);
    defer a.deinit(m.gpa);
    var b = try properListElems(m, args[1]);
    defer b.deinit(m.gpa);

    const removed = m.gpa.alloc(bool, a.items.len) catch return error.OutOfMemory;
    defer m.gpa.free(removed);
    @memset(removed, false);

    // For each element of B, remove the first not-yet-removed exact match in A.
    for (b.items) |be| {
        var j: usize = 0;
        while (j < a.items.len) : (j += 1) {
            if (!removed[j] and FinalTerms.eqlExact(&m.ctx, a.items[j], be)) {
                removed[j] = true;
                break;
            }
        }
    }

    var acc = FinalTerms.nil(&m.ctx);
    var i = a.items.len;
    while (i > 0) {
        i -= 1;
        if (!removed[i]) acc = FinalTerms.cons(&m.ctx, a.items[i], acc) catch return error.OutOfMemory;
    }
    return acc;
}

// ============================================================================
// E2.6 LAWS
// ============================================================================

const AtomTable = ta.AtomTable;

fn expectEqlExact(m: *Machine, got: BifError!Term, want: Term) !void {
    const t = try got;
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, t, want));
}

fn listTerm(m: *Machine, elems: []const i64) !Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = elems.len;
    while (i > 0) {
        i -= 1;
        acc = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, elems[i]), acc);
    }
    return acc;
}

test "LAW E2.6 member/2 denotes exact-equality membership; badarg on an improper list" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const l = try listTerm(&m, &.{ 1, 2, 3 });
    try expectEqlExact(&m, member(&m, &.{ FinalTerms.int(&m.ctx, 2), l }), FinalTerms.atom(&m.ctx, m.bool_true));
    try expectEqlExact(&m, member(&m, &.{ FinalTerms.int(&m.ctx, 9), l }), FinalTerms.atom(&m.ctx, m.bool_false));

    // EXACT equality: 1 (int) does NOT member-match 1.0 (float).
    const fl = try FinalTerms.cons(&m.ctx, FinalTerms.float(&m.ctx, 1.0), FinalTerms.nil(&m.ctx));
    try expectEqlExact(&m, member(&m, &.{ FinalTerms.int(&m.ctx, 1), fl }), FinalTerms.atom(&m.ctx, m.bool_false));

    // Improper list -> badarg (element sought is absent from the proper
    // prefix, so the walk must actually reach the malformed tail).
    const improper = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2));
    try std.testing.expectError(error.Badarg, member(&m, &.{ FinalTerms.int(&m.ctx, 5), improper }));
}

test "LAW E2.6 reverse/2 is the fold-cons of List onto Tail; reverse(reverse(L,[]),[]) == L" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const l = try listTerm(&m, &.{ 1, 2, 3 });
    const want = try listTerm(&m, &.{ 3, 2, 1 });
    try expectEqlExact(&m, reverse_2(&m, &.{ l, FinalTerms.nil(&m.ctx) }), want);

    // onto a non-nil tail.
    const tail = try listTerm(&m, &.{ 9, 8 });
    const want2 = try listTerm(&m, &.{ 3, 2, 1, 9, 8 });
    try expectEqlExact(&m, reverse_2(&m, &.{ l, tail }), want2);

    // ROUND-TRIP: reverse(reverse(L, []), []) == L.
    const once = try reverse_2(&m, &.{ l, FinalTerms.nil(&m.ctx) });
    const back = try reverse_2(&m, &.{ once, FinalTerms.nil(&m.ctx) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, back, l));

    // Improper list -> badarg.
    const improper = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2));
    try std.testing.expectError(error.Badarg, reverse_2(&m, &.{ improper, FinalTerms.nil(&m.ctx) }));
}

test "LAW E2.6 keyfind/keysearch/keymember denote position-N EXACT-equality lookup" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const tup_a = try FinalTerms.tuple(&m.ctx, &.{ a, FinalTerms.int(&m.ctx, 1) });
    const tup_b = try FinalTerms.tuple(&m.ctx, &.{ b, FinalTerms.int(&m.ctx, 2) });
    const l = try FinalTerms.cons(&m.ctx, tup_a, try FinalTerms.cons(&m.ctx, tup_b, FinalTerms.nil(&m.ctx)));

    try expectEqlExact(&m, keyfind(&m, &.{ b, FinalTerms.int(&m.ctx, 1), l }), tup_b);
    const value_idx = try atoms.intern("value");
    const want_search = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.atom(&m.ctx, value_idx), tup_b });
    try expectEqlExact(&m, keysearch(&m, &.{ b, FinalTerms.int(&m.ctx, 1), l }), want_search);
    try expectEqlExact(&m, keymember(&m, &.{ b, FinalTerms.int(&m.ctx, 1), l }), FinalTerms.atom(&m.ctx, m.bool_true));

    // Not found -> false.
    const c = FinalTerms.atom(&m.ctx, try atoms.intern("c"));
    try expectEqlExact(&m, keyfind(&m, &.{ c, FinalTerms.int(&m.ctx, 1), l }), FinalTerms.atom(&m.ctx, m.bool_false));
    try expectEqlExact(&m, keysearch(&m, &.{ c, FinalTerms.int(&m.ctx, 1), l }), FinalTerms.atom(&m.ctx, m.bool_false));
    try expectEqlExact(&m, keymember(&m, &.{ c, FinalTerms.int(&m.ctx, 1), l }), FinalTerms.atom(&m.ctx, m.bool_false));

    // EXACT-KEY-EQUALITY: keyfind(1, 1, [{1.0}]) does NOT match.
    const tup_float = try FinalTerms.tuple(&m.ctx, &.{FinalTerms.float(&m.ctx, 1.0)});
    const l_float = try FinalTerms.cons(&m.ctx, tup_float, FinalTerms.nil(&m.ctx));
    try expectEqlExact(&m, keyfind(&m, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 1), l_float }), FinalTerms.atom(&m.ctx, m.bool_false));

    // SKIP-NON-TUPLE (pin `erl_bif_lists.c:1301-1381`): a non-tuple element is
    // silently skipped, NOT an error. keyfind(b, 1, [x, {b,2}]) == {b,2}.
    const x = FinalTerms.atom(&m.ctx, try atoms.intern("x"));
    const l_mixed = try FinalTerms.cons(&m.ctx, x, try FinalTerms.cons(&m.ctx, tup_b, FinalTerms.nil(&m.ctx)));
    try expectEqlExact(&m, keyfind(&m, &.{ b, FinalTerms.int(&m.ctx, 1), l_mixed }), tup_b);
    try expectEqlExact(&m, keysearch(&m, &.{ b, FinalTerms.int(&m.ctx, 1), l_mixed }), want_search);
    try expectEqlExact(&m, keymember(&m, &.{ b, FinalTerms.int(&m.ctx, 1), l_mixed }), FinalTerms.atom(&m.ctx, m.bool_true));

    // SKIP-TOO-SMALL: a tuple whose arity < N is skipped on that position.
    // keyfind(k, 2, [{k}, {a,k}]) == {a,k} (the arity-1 {k} has no position 2).
    const k = FinalTerms.atom(&m.ctx, try atoms.intern("k"));
    const tup_k = try FinalTerms.tuple(&m.ctx, &.{k});
    const tup_ak = try FinalTerms.tuple(&m.ctx, &.{ a, k });
    const l_small = try FinalTerms.cons(&m.ctx, tup_k, try FinalTerms.cons(&m.ctx, tup_ak, FinalTerms.nil(&m.ctx)));
    try expectEqlExact(&m, keyfind(&m, &.{ k, FinalTerms.int(&m.ctx, 2), l_small }), tup_ak);

    // EXHAUSTED (reached nil): keyfind(z, 1, [{a,1},{b,2}]) == false.
    const z = FinalTerms.atom(&m.ctx, try atoms.intern("z"));
    try expectEqlExact(&m, keyfind(&m, &.{ z, FinalTerms.int(&m.ctx, 1), l }), FinalTerms.atom(&m.ctx, m.bool_false));

    // BADARG only on an IMPROPER tail: keyfind(a, 1, [{a,1} | improper]) — the
    // key is absent from the proper prefix so the walk reaches the bad tail.
    // (`a` != `tup_a`'s position-1 which IS `a`; use a key that matches nothing
    // in the prefix so the walk must reach the improper tail: `absent`.)
    const absent = FinalTerms.atom(&m.ctx, try atoms.intern("absent"));
    const improper = try FinalTerms.cons(&m.ctx, tup_a, FinalTerms.int(&m.ctx, 99));
    try std.testing.expectError(error.Badarg, keyfind(&m, &.{ absent, FinalTerms.int(&m.ctx, 1), improper }));
    try std.testing.expectError(error.Badarg, keysearch(&m, &.{ absent, FinalTerms.int(&m.ctx, 1), improper }));
    try std.testing.expectError(error.Badarg, keymember(&m, &.{ absent, FinalTerms.int(&m.ctx, 1), improper }));

    // BADARG on a bad N (not a positive integer).
    try std.testing.expectError(error.Badarg, keyfind(&m, &.{ b, FinalTerms.int(&m.ctx, 0), l }));
    try std.testing.expectError(error.Badarg, keyfind(&m, &.{ b, FinalTerms.int(&m.ctx, -1), l }));
}

test "LAW E2.6 erlang:'++'/2 denotes append; A must be proper, B may be any term" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = try listTerm(&m, &.{ 1, 2 });
    const b = try listTerm(&m, &.{ 3, 4 });
    const want = try listTerm(&m, &.{ 1, 2, 3, 4 });
    try expectEqlExact(&m, append_2(&m, &.{ a, b }), want);

    // B not a list -> a legitimately improper result.
    const atom_b = FinalTerms.atom(&m.ctx, try atoms.intern("tail"));
    const improper_want = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 2), atom_b));
    try expectEqlExact(&m, append_2(&m, &.{ a, atom_b }), improper_want);

    // [] ++ B == B.
    try expectEqlExact(&m, append_2(&m, &.{ FinalTerms.nil(&m.ctx), b }), b);

    // A improper -> badarg.
    const improper_a = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2));
    try std.testing.expectError(error.Badarg, append_2(&m, &.{ improper_a, b }));
}

test "LAW E2.6 erlang:'--'/2 removes the first occurrence of each B element from A" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = try listTerm(&m, &.{ 1, 2, 3, 2 });
    const b = try listTerm(&m, &.{2});
    const want = try listTerm(&m, &.{ 1, 3, 2 });
    try expectEqlExact(&m, subtract_2(&m, &.{ a, b }), want);

    // A missing element in B is a no-op removal for that element.
    const b2 = try listTerm(&m, &.{9});
    try expectEqlExact(&m, subtract_2(&m, &.{ a, b2 }), a);

    // Removing more occurrences than present just exhausts A's matches.
    const a2 = try listTerm(&m, &.{ 1, 1 });
    const b3 = try listTerm(&m, &.{ 1, 1, 1 });
    try expectEqlExact(&m, subtract_2(&m, &.{ a2, b3 }), FinalTerms.nil(&m.ctx));

    // Improper A or B -> badarg.
    const improper = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2));
    try std.testing.expectError(error.Badarg, subtract_2(&m, &.{ improper, b }));
    try std.testing.expectError(error.Badarg, subtract_2(&m, &.{ a, improper }));
}
