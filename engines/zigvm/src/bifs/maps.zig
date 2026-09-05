//! # bifs/maps — the `maps:` BIF family (E2.7)
//!
//! ## Signature
//! Same contract as `bifs/erlang.zig`/`bifs/conv.zig`/`bifs/lists.zig`: each
//! BIF is a `pub fn (m: *Machine, args: []const Term) BifError!Term` over
//! ALREADY-RESOLVED term arguments, computed via `term_algebra`'s EXISTING
//! `mapNew`/`mapGet`/`mapPut`/`mapRemove`/`mapSize`/`mapPairs` accessors — NO
//! new map semantics live here — returning the result term or a clean
//! `error.Badarg`. It NEVER panics on a well-formed call.
//!
//! ## The dispatch mechanism (unchanged — see `bifs/dispatch.zig`)
//! This task adds ONLY `pub fn`s here, `implOf`/`implOfMaps` arms in
//! `bifs/dispatch.zig`, and `implemented_map` rows in `harness/bif_gen.ml`.
//! The generated `bif_table.zig`, the loader, and the `bif_call` executor are
//! untouched.
//!
//! ## Semantic domain — reuse, not reinvention
//!   `get/2`      — `mapGet`, crash on absent key or non-map.
//!   `get/3`      — `mapGet`, `Default` on absent key; crash only on non-map.
//!   `find/2`     — `{ok,Value}` | `error` (never crashes on an absent key).
//!   `is_key/2`   — `mapGet != null`; crash only on non-map.
//!   `put/3`      — `mapPut` (insert-or-overwrite).
//!   `remove/2`   — `mapRemove`; `mapRemove` ITSELF already treats an absent
//!                  key as a no-op (returns `m` unchanged) — this wrapper
//!                  must NOT add its own "absent key errors" check (mutant 2).
//!   `take/2`     — `{Value, mapRemove(Map,Key)}` | `error` on absent key.
//!   `update/3`   — `mapPut`, but ONLY when the key already exists (checked
//!                  via `mapGet` first) — crash on an ABSENT key (unlike
//!                  `put/3`, which always succeeds).
//!   `keys/1`, `values/1`, `to_list/1` — `mapPairs`, projected/paired/kept.
//!   `from_list/1` — fold `mapPut`-equivalent via a single `mapNew` call
//!                  (`mapNew` already implements "last key wins" over
//!                  unsorted pairs — the exact `from_list/1` contract).
//!   `merge/2`    — `Map1`, then `mapPut` every `Map2` pair on top — so
//!                  `Map2` (the RIGHT map) wins on a shared key (mutant 1
//!                  targets a left-biased fold, i.e. folding `Map1` onto
//!                  `Map2` instead).
//!   `new/0`      — the empty map (`mapNew(&.{}, &.{})`).
//!
//! ## PIN LEDGER NOTE (the `maps:new/0`, `get/3`, `to_list/1` scope, honest)
//! The pinned `bif.tab` declares ONLY `maps:find/2`, `get/2`, `from_list/1`,
//! `is_key/2`, `keys/1`, `merge/2`, `put/3`, `remove/2`, `take/2`, `update/3`,
//! `values/1` (11 rows) as real BIFs. `maps:new/0` compiles directly to the
//! literal `#{}` (`maps.erl`: `new() -> #{}.` — never even calls a BIF);
//! `maps:get/3` and `maps:to_list/1` are erlang.erl-STYLE LIBRARY wrappers in
//! `maps.erl` built atop lower-level primitives (`get/3` catches `get/2`'s
//! badkey; `to_list/1` walks `erts_internal:map_next/3`), not bif.tab entries
//! themselves — the SAME shape as E2.5's `list_to_integer/1` scope note. This
//! module still defines `new_0`/`get_3`/`to_list_1` below (law-tested
//! directly) but does NOT wire them into `bifs/dispatch.zig`/
//! `harness/bif_gen.ml`'s `implemented_map` — there is no ledger row for them,
//! so a wire-anyway would be dead code (`resolve` never reaches `implOf` for
//! an absent `bif_table` key).
//!
//! ## `{badmap,M}`/`{badkey,K}` — DISCHARGED at E3.10 (`DIVERGENCE_LOG.md`
//! entries 6c + 23)
//! BEAM raises the STRUCTURED reasons `{badmap,M}` (non-map arg) and
//! `{badkey,K}` (absent key in `get/2`/`update/3`). As of E3.10 (the exception
//! model, `instr_algebra.zig`'s `Machine.bifRaise`/`raiseBadmap`/`raiseBadkey`
//! + the `error.Raise` executor arm), this family now raises those EXACT
//! structured reasons: `needMap` → `error:{badmap,Map}`; `get/2`/`update/3` on
//! an absent key → `error:{badkey,Key}`. The GUARD-context behaviour is
//! UNCHANGED (a guard-usable BIF still BRANCHES to `else_to` — the structured
//! raise only changes the BODY-context reason, routed through the same
//! guard/body split as the old `Badarg`). ONE case stays a plain `error.Badarg`
//! and is CORRECT: `from_list/1`'s non-`{K,V}`-element / improper-list case is a
//! bad LIST, not a map op, so BEAM raises `badarg` there too. Bounded by the
//! E2.7 rejection laws (now `expectBadmap`/`expectBadkey`, not `error.Badarg`).
//!
//! ## `erts_internal:map_next/3` (E31-T2, Tier-1 HAMT iterator primitive)
//! `maps.erl`'s `to_list/1` and `next/1` are driven by the internal BIF
//! `erts_internal:map_next(Path, Map, ThirdArg)`. THIS module implements it as
//! `map_next_3` (wired into the ledger — unlike `to_list_1`, `map_next/3` IS a
//! real bif.tab row on the pin). Its OBSERVABLE contract, read straight off
//! `erts/emulator/beam/erl_map.c:erts_internal_map_next_3`:
//!   - non-map `Map` -> PLAIN `error.Badarg` (NOT the user-facing `{badmap,M}`
//!     structured reason — this is an internal primitive; `maps.erl` re-wraps).
//!   - `ThirdArg`: the atom `iterator` -> ITERATOR mode ({K,V,Next}|none nested
//!     chain); `[]`/a list (the caller's `Acc`) -> LIST mode ([{K,V}...|Acc]);
//!     anything else -> `error.Badarg`.
//!   - ORDERED-ITERATOR branch (iterator mode + `Path` is a key list/nil):
//!     look each key up via `mapGet` IN THE SUPPLIED ORDER, building the chain;
//!     an absent key -> `error.Badarg`; `[]` -> `none`. This branch is
//!     representation-INDEPENDENT (pure `mapGet` over a caller order) -> BYTE-EQ.
//!   - UNORDERED branch (`Path` a non-negative small int): OTP returns a whole
//!     flatmap in one call regardless of the (in-range `0..n`) path value; a
//!     larger-than-size path -> `error.Badarg`.
//! ## SCOPE / iterator-integer encoding (honest, DIVERGENCE-consistent)
//! zigvm returns the COMPLETE result in ONE reduction-unbounded call (it has no
//! reduction budget / preemption), so it NEVER emits OTP's integer-path
//! continuation (`[Iter,Map|Acc]` / mid-chain integer tail) — those integers
//! bit-pack a route into OTP's SPECIFIC HAMT node layout, which this VM's HAMT
//! (a different hash/branching, per the ORDER note below) cannot reproduce
//! byte-for-byte. This is observationally EQ for the two real drivers: the
//! `to_list_internal` loop and the `next/1` unfold both terminate on the SAME
//! final value (a complete `[{K,V}...|Acc]` list / `none`-terminated chain),
//! differing only in OPAQUE intermediate iterator values no well-formed caller
//! inspects. ORDER: sequence-EQ for a flatmap (sorted key order == OTP's), and
//! SET-EQ for a >32-key HAMT (the SAME documented divergence already accepted
//! by `keys/1`/`values/1`, both `implemented`). A nonzero integer path into a
//! HAMT is honoured as a start index into `mapPairs` order — a documented,
//! never-driver-observed divergence (the driver only ever passes `0`).
//!
//! ## `keys/1`/`values/1`/`to_list/1` ORDER (documented choice)
//! `term_algebra`'s map representation is a FLATMAP (sorted-by-exact-term-
//! order assoc array) up to `max_flatmap_size` (32) keys, promoting to a HAMT
//! above that. `mapPairs` returns the flatmap in SORTED order — which matches
//! BEAM's small-map (flatmap) key order exactly — but the HAMT branch returns
//! TRIE order, which is NOT guaranteed to match BEAM's own HAMT iteration
//! order (a different hash/branching scheme). This module does not attempt to
//! reproduce BEAM's HAMT order; the laws below assert exact order for
//! small (flatmap-backed) maps and assert SET equality (order-insensitive)
//! for a >32-key (HAMT-backed) map — the honest choice already used by
//! `map_algebra.zig`'s own oracle/final cross-laws for the promoted case.
//!
//! ## Lifetime safety (the E2.5/E2.6 lesson, audited per fn below)
//! `mapPairs`/`mapGet`/`mapRemove`/`mapPut` all return/consume Term VALUES —
//! tagged offsets into `ctx.words`, not raw byte slices — so holding one
//! across a later `cons`/`tuple`/`mapPut` call that reallocates `ctx.words`
//! is SAFE (the offset stays valid post-realloc; only a raw `[]const u8`
//! slice from `binBytes` would dangle, and NOTHING here ever takes one):
//!   - `keys_1`/`values_1`/`to_list_1`: `mapPairs` fills `m.gpa`-owned
//!     buffers (`pk`/`pv`) BEFORE any `cons`/`tuple` call runs, and the fold
//!     that builds the result list holds only `Term` VALUES from those
//!     buffers across each `cons` — safe by the same pattern as
//!     `lists.reverse_2`.
//!   - `from_list_1`: collects `{key,val}` `Term` VALUES into `m.gpa`-owned
//!     arrays (mirroring `lists.properListElems`) BEFORE the single
//!     `mapNew` call that builds the result map — safe by construction.
//!   - `merge_2`: folds `mapPut` directly over `Map2`'s already-off-heap
//!     `pv`/`pk` buffer entries (Term VALUES) — safe; no slice survives a
//!     realloc.
//!
//! ## Laws (see the test suite below)
//!   - DENOTATION  get(a,#{a=>1}) == 1; get(x,#{},9) == 9;
//!     find(a,#{a=>1}) == {ok,1}; find(x,#{}) == error;
//!     is_key(a,#{a=>1}) == true; put(a,9,#{a=>1}) == #{a=>9};
//!     remove(x,#{a=>1}) == #{a=>1} (absent key: unchanged, NOT an error);
//!     take(a,#{a=>1,b=>2}) == {1,#{b=>2}}; take(x,#{}) == error;
//!     update(a,9,#{a=>1}) == #{a=>9}; update(x,9,#{}) crashes badkey (badarg);
//!     from_list([{a,1},{a,2}]) == #{a=>2} (last wins);
//!     merge(#{a=>1,b=>2}, #{b=>9,c=>3}) == #{a=>1,b=>9,c=>3} (Map2 wins)
//!   - EXACT-KEY-EQUALITY  get(1.0, #{1=>x}) crashes badkey — `1` and `1.0`
//!     are DIFFERENT keys (reuses `term_algebra`'s own `.exact` comparator,
//!     no new comparator here).
//!   - ROUND-TRIP  from_list(to_list(M)) == M
//!   - REJECTION  a non-map first-class arg (`get`/`find`/`is_key`/`put`/
//!     `remove`/`take`/`update`/`keys`/`values`/`to_list`/`merge`) → a clean
//!     `error.Badarg` (never a panic); a non-`{K,V}` element or an improper
//!     list in `from_list` → `error.Badarg`.

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

/// E3.10 (DIVERGENCE entry 6c, discharged): a non-map first argument to any
/// `maps:` op is `error:{badmap, Map}` — the exact BEAM structured reason (was:
/// simplified `badarg`). `raiseBadmap` stages it via the `error.Raise` path; in
/// a guard context the executor still branches (guard behaviour unchanged).
fn needMap(m: *Machine, w: Term) BifError!void {
    if (FinalTerms.kindOf(&m.ctx, w) != .map) return m.raiseBadmap(w);
}

fn okAtom(m: *Machine) BifError!Term {
    const idx = m.ctx.atoms.intern("ok") catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

fn errorAtom(m: *Machine) BifError!Term {
    const idx = m.ctx.atoms.intern("error") catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

/// Collect ALL pairs of `map` into fresh `m.gpa`-owned buffers (Term VALUES,
/// realloc-safe — see the module lifetime note). Caller frees via
/// `m.gpa.free` on both slices.
fn collectPairs(m: *Machine, map: Term) BifError!struct { keys: []Term, vals: []Term } {
    const n = FinalTerms.mapSize(&m.ctx, map);
    const pk = m.gpa.alloc(Term, n) catch return error.OutOfMemory;
    errdefer m.gpa.free(pk);
    const pv = m.gpa.alloc(Term, n) catch return error.OutOfMemory;
    errdefer m.gpa.free(pv);
    const got = FinalTerms.mapPairs(&m.ctx, map, pk, pv);
    std.debug.assert(got == n);
    return .{ .keys = pk, .vals = pv };
}

// ── maps:get/2, maps:get/3 (get/3 is a library wrapper, see scope note) ────

pub fn get_2(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const map = args[1];
    try needMap(m, map);
    // E3.10 (entry 6c, discharged): {badkey,Key} on an absent key (was `badarg`).
    return FinalTerms.mapGet(&m.ctx, map, key) orelse m.raiseBadkey(key);
}

/// Library wrapper (`maps.erl`'s `get/3`, not a bif.tab entry) — not wired.
pub fn get_3(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const map = args[1];
    const default = args[2];
    try needMap(m, map);
    return FinalTerms.mapGet(&m.ctx, map, key) orelse default;
}

// ── maps:find/2 ─────────────────────────────────────────────────────────────

pub fn find_2(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const map = args[1];
    try needMap(m, map);
    if (FinalTerms.mapGet(&m.ctx, map, key)) |v| {
        const ok = try okAtom(m);
        return FinalTerms.tuple(&m.ctx, &.{ ok, v }) catch error.OutOfMemory;
    }
    return errorAtom(m);
}

// ── maps:is_key/2 ────────────────────────────────────────────────────────────

pub fn is_key_2(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const map = args[1];
    try needMap(m, map);
    return boolTerm(m, FinalTerms.mapGet(&m.ctx, map, key) != null);
}

// ── maps:put/3 ───────────────────────────────────────────────────────────────

pub fn put_3(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const val = args[1];
    const map = args[2];
    try needMap(m, map);
    return FinalTerms.mapPut(&m.ctx, map, key, val) catch error.OutOfMemory;
}

// ── maps:remove/2 ────────────────────────────────────────────────────────────

pub fn remove_2(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const map = args[1];
    try needMap(m, map);
    // MUTANT (remove errors on an absent key): inserting
    // `if (FinalTerms.mapGet(&m.ctx, map, key) == null) return error.Badarg;`
    // here would break the REJECTION-EXCEPTION law `remove(x, #{a=>1}) ==
    // #{a=>1}` — `mapRemove` ITSELF already returns the map unchanged on an
    // absent key; this wrapper must add NO extra absent-key check.
    return FinalTerms.mapRemove(&m.ctx, map, key) catch error.OutOfMemory;
}

// ── maps:take/2 ──────────────────────────────────────────────────────────────

pub fn take_2(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const map = args[1];
    try needMap(m, map);
    const val = FinalTerms.mapGet(&m.ctx, map, key) orelse return errorAtom(m);
    const rest = FinalTerms.mapRemove(&m.ctx, map, key) catch return error.OutOfMemory;
    return FinalTerms.tuple(&m.ctx, &.{ val, rest }) catch error.OutOfMemory;
}

// ── maps:update/3 (existing-key-only put) ───────────────────────────────────

pub fn update_3(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const val = args[1];
    const map = args[2];
    try needMap(m, map);
    // E3.10 (entry 6c, discharged): {badkey,Key} on an absent key (was `badarg`).
    if (FinalTerms.mapGet(&m.ctx, map, key) == null) return m.raiseBadkey(key);
    return FinalTerms.mapPut(&m.ctx, map, key, val) catch error.OutOfMemory;
}

// ── maps:keys/1, maps:values/1, maps:to_list/1 (to_list/1 not wired) ───────

pub fn keys_1(m: *Machine, args: []const Term) BifError!Term {
    const map = args[0];
    try needMap(m, map);
    const pairs = try collectPairs(m, map);
    defer m.gpa.free(pairs.keys);
    defer m.gpa.free(pairs.vals);
    var acc = FinalTerms.nil(&m.ctx);
    var i = pairs.keys.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, pairs.keys[i], acc) catch return error.OutOfMemory;
    }
    return acc;
}

pub fn values_1(m: *Machine, args: []const Term) BifError!Term {
    const map = args[0];
    try needMap(m, map);
    const pairs = try collectPairs(m, map);
    defer m.gpa.free(pairs.keys);
    defer m.gpa.free(pairs.vals);
    var acc = FinalTerms.nil(&m.ctx);
    var i = pairs.vals.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, pairs.vals[i], acc) catch return error.OutOfMemory;
    }
    return acc;
}

/// Library wrapper (`maps.erl`'s `to_list/1` walks `erts_internal:map_next/3`
/// for a real map — not a bif.tab entry itself); not wired. Order matches
/// `keys_1`/`values_1` (flatmap: sorted; HAMT: trie order — see module note).
pub fn to_list_1(m: *Machine, args: []const Term) BifError!Term {
    const map = args[0];
    try needMap(m, map);
    const pairs = try collectPairs(m, map);
    defer m.gpa.free(pairs.keys);
    defer m.gpa.free(pairs.vals);
    var acc = FinalTerms.nil(&m.ctx);
    var i = pairs.keys.len;
    while (i > 0) {
        i -= 1;
        const kv = FinalTerms.tuple(&m.ctx, &.{ pairs.keys[i], pairs.vals[i] }) catch return error.OutOfMemory;
        acc = FinalTerms.cons(&m.ctx, kv, acc) catch return error.OutOfMemory;
    }
    return acc;
}

// ── maps:from_list/1 ─────────────────────────────────────────────────────────

pub fn from_list_1(m: *Machine, args: []const Term) BifError!Term {
    var keys: std.ArrayList(Term) = .empty;
    defer keys.deinit(m.gpa);
    var vals: std.ArrayList(Term) = .empty;
    defer vals.deinit(m.gpa);
    var cur = args[0];
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => break,
            .cons => {
                const h = FinalTerms.listHead(&m.ctx, cur);
                if (FinalTerms.kindOf(&m.ctx, h) != .tuple or FinalTerms.tupleArity(&m.ctx, h) != 2) {
                    return error.Badarg;
                }
                keys.append(m.gpa, FinalTerms.tupleElem(&m.ctx, h, 0)) catch return error.OutOfMemory;
                vals.append(m.gpa, FinalTerms.tupleElem(&m.ctx, h, 1)) catch return error.OutOfMemory;
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg,
        }
    }
    // `mapNew` already implements "last key wins" over unsorted pairs — the
    // exact `from_list/1` contract; no separate fold needed.
    return FinalTerms.mapNew(&m.ctx, keys.items, vals.items) catch error.OutOfMemory;
}

/// E3.18: `maps:from_keys(Keys, Value)` — a map mapping every key in the proper
/// list `Keys` to the SAME `Value` (last duplicate key wins, exactly `mapNew`'s
/// contract). An improper/non-list `Keys` is `badarg`.
pub fn from_keys_2(m: *Machine, args: []const Term) BifError!Term {
    const value = args[1];
    var keys: std.ArrayList(Term) = .empty;
    defer keys.deinit(m.gpa);
    var vals: std.ArrayList(Term) = .empty;
    defer vals.deinit(m.gpa);
    var cur = args[0];
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => break,
            .cons => {
                keys.append(m.gpa, FinalTerms.listHead(&m.ctx, cur)) catch return error.OutOfMemory;
                vals.append(m.gpa, value) catch return error.OutOfMemory;
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg,
        }
    }
    return FinalTerms.mapNew(&m.ctx, keys.items, vals.items) catch error.OutOfMemory;
}

// ── maps:merge/2 ─────────────────────────────────────────────────────────────

pub fn merge_2(m: *Machine, args: []const Term) BifError!Term {
    const map1 = args[0];
    const map2 = args[1];
    try needMap(m, map1);
    try needMap(m, map2);
    const pairs2 = try collectPairs(m, map2);
    defer m.gpa.free(pairs2.keys);
    defer m.gpa.free(pairs2.vals);
    // MUTANT (merge left-biased): folding `map1`'s pairs ONTO `map2` here
    // (instead of `map2`'s pairs onto `map1`) would make Map1 win on a shared
    // key — BEAM's `merge/2` has Map2 (the RIGHT/second map) win.
    var acc = map1;
    for (pairs2.keys, pairs2.vals) |k, v| {
        acc = FinalTerms.mapPut(&m.ctx, acc, k, v) catch return error.OutOfMemory;
    }
    return acc;
}

// ── maps:new/0 (compiles to a literal `#{}` on real BEAM — not a bif.tab
// entry itself; not wired, see scope note) ──────────────────────────────────

pub fn new_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    return FinalTerms.mapNew(&m.ctx, &.{}, &.{}) catch error.OutOfMemory;
}

// ── erts_internal:map_next/3 (E31-T2, Tier-1 HAMT iterator) ─────────────────

fn noneAtom(m: *Machine) BifError!Term {
    const idx = m.ctx.atoms.intern("none") catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

fn isIteratorAtom(m: *Machine, t: Term) bool {
    if (!FinalTerms.repIsAtom(t)) return false;
    const idx = m.ctx.atoms.intern("iterator") catch return false;
    return FinalTerms.atomIdxOf(t) == idx;
}

/// The ordered-iterator branch: fold the caller-supplied key list into a
/// `{K,V,Next}` chain terminating in `none`, looking each key up in the given
/// order. An absent key or an improper key list is `error.Badarg`. `[]` (nil)
/// yields `none`. Representation-independent -> byte-EQ with OTP.
fn orderedIterChain(m: *Machine, map: Term, path: Term) BifError!Term {
    var keys: std.ArrayList(Term) = .empty;
    defer keys.deinit(m.gpa);
    var vals: std.ArrayList(Term) = .empty;
    defer vals.deinit(m.gpa);
    var cur = path;
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => break,
            .cons => {
                const key = FinalTerms.listHead(&m.ctx, cur);
                // MUTANT (ordered branch drops the absent-key gate): replacing
                // `orelse return error.Badarg` with `orelse continue` (skip the
                // key) makes `map_next([x], Map, iterator)` return `none`/a
                // short chain instead of crashing badarg — breaks the ordered
                // REJECTION law.
                const v = FinalTerms.mapGet(&m.ctx, map, key) orelse return error.Badarg;
                keys.append(m.gpa, key) catch return error.OutOfMemory;
                vals.append(m.gpa, v) catch return error.OutOfMemory;
                cur = FinalTerms.listTail(&m.ctx, cur);
            },
            else => return error.Badarg, // improper key list
        }
    }
    var acc = try noneAtom(m);
    var i = keys.items.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.tuple(&m.ctx, &.{ keys.items[i], vals.items[i], acc }) catch return error.OutOfMemory;
    }
    return acc;
}

/// `erts_internal:mc_iterator/1` (DIVERGENCE 676) — the "map collection iterator"
/// primitive behind MAP-COMPREHENSION generators (`K := V <- Map`, used by
/// sets:filter/map, json:encode, etc.). Materializes the WHOLE map into a
/// `{K, V, Next}` chain ending in the atom `none`. zigvm SIDESTEPS erts's
/// large-map chunk/refill continuation (`[N|RestMap]`): the compiled comprehension
/// walks `{K,V,Next}` until `none`, so a complete single chain works for small
/// AND HAMT maps. Iteration order is zigvm's `mapPairs` (key-SORTED); erts uses
/// its internal atom-index order — so a comprehension whose RESULT is
/// order-independent (a set/map, or `lists:sort`ed) is byte-EQ, while a raw-order
/// list is not (an inherent small-map key-order repr-coupling, not a defect).
pub fn mc_iterator_1(m: *Machine, args: []const Term) BifError!Term {
    const map = args[0];
    if (FinalTerms.kindOf(&m.ctx, map) != .map) return error.Badarg;
    const pairs = try collectPairs(m, map);
    defer m.gpa.free(pairs.keys);
    defer m.gpa.free(pairs.vals);
    var acc = try noneAtom(m);
    var i = pairs.keys.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.tuple(&m.ctx, &.{ pairs.keys[i], pairs.vals[i], acc }) catch return error.OutOfMemory;
    }
    return acc;
}

pub fn map_next_3(m: *Machine, args: []const Term) BifError!Term {
    const path = args[0];
    const map = args[1];
    const third = args[2];
    // OTP: `if (!is_map(map)) BIF_ERROR(BADARG)` — a PLAIN badarg (this internal
    // primitive does NOT raise the user-facing {badmap,M}; maps.erl re-wraps).
    if (FinalTerms.kindOf(&m.ctx, map) != .map) return error.Badarg;

    // Mode select: `iterator` atom -> iterator mode; nil/list Acc -> list mode;
    // else badarg.
    const iter_mode = isIteratorAtom(m, third);
    if (!iter_mode) {
        const tk = FinalTerms.kindOf(&m.ctx, third);
        if (tk != .nil and tk != .cons) return error.Badarg;
    }

    // Ordered iterator: iterator mode + a key-list (or nil) path.
    if (iter_mode) {
        const pk = FinalTerms.kindOf(&m.ctx, path);
        if (pk == .nil or pk == .cons) return orderedIterChain(m, map, path);
    }

    // Unordered branch: `path` must be a non-negative small integer.
    if (!FinalTerms.repIsSmall(path)) return error.Badarg;
    const pv = FinalTerms.smallValOf(path);
    if (pv < 0) return error.Badarg;
    const p: usize = @intCast(pv);
    const n = FinalTerms.mapSize(&m.ctx, map);
    // MUTANT (drop the path-range gate): removing `if (p > n) ...` lets an
    // out-of-range path (e.g. `map_next(3, #{a=>1,b=>2}, [])`) fall through and
    // return a result instead of the OTP `error.Badarg` — breaks the REJECTION
    // law's `p > n` case.
    if (p > n) return error.Badarg; // OTP flatmap gate: `n < path` -> badarg

    const pairs = try collectPairs(m, map);
    defer m.gpa.free(pairs.keys);
    defer m.gpa.free(pairs.vals);

    // A flatmap is always returned whole in one call (OTP ignores the in-range
    // path value); a HAMT single-shot from 0 likewise emits everything. A
    // nonzero HAMT path is a start index into `mapPairs` order (never driver-
    // observed — see the scope note).
    const start: usize = if (FinalTerms.mapRepIsFlat(&m.ctx, map)) 0 else p;

    if (iter_mode) {
        var acc = try noneAtom(m);
        var i = pairs.keys.len;
        while (i > start) {
            i -= 1;
            acc = FinalTerms.tuple(&m.ctx, &.{ pairs.keys[i], pairs.vals[i], acc }) catch return error.OutOfMemory;
        }
        return acc;
    } else {
        var acc = third; // the caller's Acc list
        var i = pairs.keys.len;
        while (i > start) {
            i -= 1;
            const kv = FinalTerms.tuple(&m.ctx, &.{ pairs.keys[i], pairs.vals[i] }) catch return error.OutOfMemory;
            acc = FinalTerms.cons(&m.ctx, kv, acc) catch return error.OutOfMemory;
        }
        return acc;
    }
}

// ============================================================================
// E2.7 LAWS
// ============================================================================

const AtomTable = ta.AtomTable;

fn expectEqlExact(m: *Machine, got: BifError!Term, want: Term) !void {
    const t = try got;
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, t, want));
}

fn mkMap(m: *Machine, keys: []const Term, vals: []const Term) !Term {
    return FinalTerms.mapNew(&m.ctx, keys, vals);
}

// E3.10 (entry 6c discharge): assert a `maps:`/`erlang:map_get` call raised the
// STRUCTURED reason `error:{Tag, Payload}` (was `error.Badarg`). The fn returns
// `error.Raise` and stages `{class,reason}` on `m.bif_raise`; this consumes and
// clears it (so the next call in the same law starts clean). `Tag` is
// `m.badmap_atom` (non-map arg) or `m.badkey_atom` (absent key).
fn expectStructuredRaise(m: *Machine, got: BifError!Term, tag: ta.AtomIdx, payload: Term) !void {
    try std.testing.expectError(error.Raise, got);
    const staged = m.bif_raise orelse return error.TestUnexpectedResult;
    m.bif_raise = null;
    try std.testing.expectEqual(ia.ExcClass.error_, staged.class);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.tupleArity(&m.ctx, staged.reason));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, staged.reason, 0), FinalTerms.atom(&m.ctx, tag)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, staged.reason, 1), payload));
}
fn expectBadmap(m: *Machine, got: BifError!Term, map: Term) !void {
    return expectStructuredRaise(m, got, m.badmap_atom, map);
}
fn expectBadkey(m: *Machine, got: BifError!Term, key: Term) !void {
    return expectStructuredRaise(m, got, m.badkey_atom, key);
}

test "LAW E2.7 get/2,3 denote lookup; get/2 crashes on absent key or non-map, get/3 returns Default" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const x = FinalTerms.atom(&m.ctx, try atoms.intern("x"));
    const one = FinalTerms.int(&m.ctx, 1);
    const map = try mkMap(&m, &.{a}, &.{one});

    try expectEqlExact(&m, get_2(&m, &.{ a, map }), one);
    // E3.10 (entry 6c): absent key -> {badkey,Key}; non-map -> {badmap,Map}.
    try expectBadkey(&m, get_2(&m, &.{ x, map }), x);
    try expectBadmap(&m, get_2(&m, &.{ a, one }), one); // non-map

    const nine = FinalTerms.int(&m.ctx, 9);
    try expectEqlExact(&m, get_3(&m, &.{ x, map, nine }), nine);
    try expectEqlExact(&m, get_3(&m, &.{ a, map, nine }), one);
    try expectBadmap(&m, get_3(&m, &.{ a, one, nine }), one); // non-map

    // EXACT-KEY-EQUALITY: 1 (int key) and 1.0 (float) are DIFFERENT keys —
    // looking up int `1` in `#{1.0=>_}` is an absent key -> {badkey,1}.
    const fmap = try mkMap(&m, &.{FinalTerms.float(&m.ctx, 1.0)}, &.{one});
    try expectBadkey(&m, get_2(&m, &.{ one, fmap }), one);
}

test "LAW E2.7 find/2 denotes {ok,Value}|error; is_key/2 denotes membership" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const x = FinalTerms.atom(&m.ctx, try atoms.intern("x"));
    const one = FinalTerms.int(&m.ctx, 1);
    const map = try mkMap(&m, &.{a}, &.{one});

    const ok_idx = try atoms.intern("ok");
    const want_ok = try FinalTerms.tuple(&m.ctx, &.{ FinalTerms.atom(&m.ctx, ok_idx), one });
    try expectEqlExact(&m, find_2(&m, &.{ a, map }), want_ok);
    const err_idx = try atoms.intern("error");
    try expectEqlExact(&m, find_2(&m, &.{ x, map }), FinalTerms.atom(&m.ctx, err_idx));
    try expectBadmap(&m, find_2(&m, &.{ a, one }), one); // non-map -> {badmap,Map}

    try expectEqlExact(&m, is_key_2(&m, &.{ a, map }), FinalTerms.atom(&m.ctx, m.bool_true));
    try expectEqlExact(&m, is_key_2(&m, &.{ x, map }), FinalTerms.atom(&m.ctx, m.bool_false));
    try expectBadmap(&m, is_key_2(&m, &.{ a, one }), one); // non-map -> {badmap,Map}
}

test "LAW E2.7 put/3 inserts-or-overwrites; remove/2 is absent-key-unchanged (NOT an error)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const x = FinalTerms.atom(&m.ctx, try atoms.intern("x"));
    const one = FinalTerms.int(&m.ctx, 1);
    const nine = FinalTerms.int(&m.ctx, 9);
    const map = try mkMap(&m, &.{a}, &.{one});

    const put_new = try put_3(&m, &.{ x, nine, map });
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.mapSize(&m.ctx, put_new));
    const overwritten = try put_3(&m, &.{ a, nine, map });
    try expectEqlExact(&m, get_2(&m, &.{ a, overwritten }), nine);
    try std.testing.expectEqual(@as(usize, 1), FinalTerms.mapSize(&m.ctx, overwritten));
    try expectBadmap(&m, put_3(&m, &.{ a, nine, one }), one); // non-map -> {badmap,Map}

    // REJECTION-EXCEPTION: remove on an ABSENT key leaves the map unchanged
    // (never an error) — the mutant target.
    try expectEqlExact(&m, remove_2(&m, &.{ x, map }), map);
    const removed = try remove_2(&m, &.{ a, map });
    try std.testing.expectEqual(@as(usize, 0), FinalTerms.mapSize(&m.ctx, removed));
    try expectBadmap(&m, remove_2(&m, &.{ a, one }), one); // non-map -> {badmap,Map}
}

test "LAW E2.7 take/2 denotes {Value,MapWithoutKey}|error; update/3 crashes on an ABSENT key" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const x = FinalTerms.atom(&m.ctx, try atoms.intern("x"));
    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    const nine = FinalTerms.int(&m.ctx, 9);
    const map = try mkMap(&m, &.{ a, b }, &.{ one, two });

    const taken = try take_2(&m, &.{ a, map });
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, taken) == .tuple);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, taken, 0), one));
    const rest = FinalTerms.tupleElem(&m.ctx, taken, 1);
    try std.testing.expectEqual(@as(usize, 1), FinalTerms.mapSize(&m.ctx, rest));
    try expectEqlExact(&m, get_2(&m, &.{ b, rest }), two);
    const err_idx = try atoms.intern("error");
    try expectEqlExact(&m, take_2(&m, &.{ x, map }), FinalTerms.atom(&m.ctx, err_idx));
    try expectBadmap(&m, take_2(&m, &.{ a, one }), one); // non-map -> {badmap,Map}

    // update/3: existing key -> overwrite; ABSENT key -> crash (unlike put/3).
    const updated = try update_3(&m, &.{ a, nine, map });
    try expectEqlExact(&m, get_2(&m, &.{ a, updated }), nine);
    // E3.10 (entry 6c): absent key -> {badkey,Key} (MUTANT target); non-map -> {badmap,Map}.
    try expectBadkey(&m, update_3(&m, &.{ x, nine, map }), x);
    try expectBadmap(&m, update_3(&m, &.{ a, nine, one }), one);
}

test "LAW E2.7 keys/1, values/1, to_list/1 denote mapPairs; round-trip from_list(to_list(M)) == M" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    // build unsorted -> the flatmap representation still emits SORTED order.
    const map = try mkMap(&m, &.{ b, a }, &.{ two, one });

    const want_keys = try FinalTerms.cons(&m.ctx, a, try FinalTerms.cons(&m.ctx, b, FinalTerms.nil(&m.ctx)));
    try expectEqlExact(&m, keys_1(&m, &.{map}), want_keys);
    const want_vals = try FinalTerms.cons(&m.ctx, one, try FinalTerms.cons(&m.ctx, two, FinalTerms.nil(&m.ctx)));
    try expectEqlExact(&m, values_1(&m, &.{map}), want_vals);

    const kv_a = try FinalTerms.tuple(&m.ctx, &.{ a, one });
    const kv_b = try FinalTerms.tuple(&m.ctx, &.{ b, two });
    const want_list = try FinalTerms.cons(&m.ctx, kv_a, try FinalTerms.cons(&m.ctx, kv_b, FinalTerms.nil(&m.ctx)));
    const list = try to_list_1(&m, &.{map});
    try expectEqlExact(&m, to_list_1(&m, &.{map}), want_list);

    // ROUND-TRIP: from_list(to_list(M)) == M.
    const back = try from_list_1(&m, &.{list});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, back, map));

    // E3.10 (entry 6c): a non-map arg -> {badmap,Map}.
    try expectBadmap(&m, keys_1(&m, &.{one}), one);
    try expectBadmap(&m, values_1(&m, &.{one}), one);
    try expectBadmap(&m, to_list_1(&m, &.{one}), one);
}

test "LAW E2.7 from_list/1 denotes mapNew (last key wins); badarg on a non-{K,V} element or improper list" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    const kv1 = try FinalTerms.tuple(&m.ctx, &.{ a, one });
    const kv2 = try FinalTerms.tuple(&m.ctx, &.{ a, two });
    const l = try FinalTerms.cons(&m.ctx, kv1, try FinalTerms.cons(&m.ctx, kv2, FinalTerms.nil(&m.ctx)));

    const got = try from_list_1(&m, &.{l});
    try std.testing.expectEqual(@as(usize, 1), FinalTerms.mapSize(&m.ctx, got));
    try expectEqlExact(&m, get_2(&m, &.{ a, got }), two); // last wins

    try expectEqlExact(&m, from_list_1(&m, &.{FinalTerms.nil(&m.ctx)}), try mkMap(&m, &.{}, &.{}));

    // non-{K,V} element -> badarg.
    const bad_elem = try FinalTerms.cons(&m.ctx, a, FinalTerms.nil(&m.ctx));
    try std.testing.expectError(error.Badarg, from_list_1(&m, &.{bad_elem}));
    const bad_arity = try FinalTerms.cons(&m.ctx, try FinalTerms.tuple(&m.ctx, &.{a}), FinalTerms.nil(&m.ctx));
    try std.testing.expectError(error.Badarg, from_list_1(&m, &.{bad_arity}));

    // improper list -> badarg.
    const improper = try FinalTerms.cons(&m.ctx, kv1, one);
    try std.testing.expectError(error.Badarg, from_list_1(&m, &.{improper}));
}

test "LAW E3.18 from_keys/2: every key maps to the SAME value (last-dup wins); non-list -> badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const v = FinalTerms.int(&m.ctx, 0);
    // from_keys([a, b, a], 0) == #{a => 0, b => 0} (2 keys, dup collapses).
    const keys = try FinalTerms.cons(&m.ctx, a, try FinalTerms.cons(&m.ctx, b, try FinalTerms.cons(&m.ctx, a, FinalTerms.nil(&m.ctx))));
    const got = try from_keys_2(&m, &.{ keys, v });
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.mapSize(&m.ctx, got));
    try expectEqlExact(&m, get_2(&m, &.{ a, got }), v);
    try expectEqlExact(&m, get_2(&m, &.{ b, got }), v);
    // empty keys -> empty map.
    try expectEqlExact(&m, from_keys_2(&m, &.{ FinalTerms.nil(&m.ctx), v }), try mkMap(&m, &.{}, &.{}));
    // non-list keys -> badarg.
    try std.testing.expectError(error.Badarg, from_keys_2(&m, &.{ a, v }));
}

test "LAW E2.7 merge/2 denotes RIGHT-biased union (Map2 wins on a shared key)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const c = FinalTerms.atom(&m.ctx, try atoms.intern("c"));
    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    const nine = FinalTerms.int(&m.ctx, 9);
    const three = FinalTerms.int(&m.ctx, 3);

    const map1 = try mkMap(&m, &.{ a, b }, &.{ one, two });
    const map2 = try mkMap(&m, &.{ b, c }, &.{ nine, three });
    const want = try mkMap(&m, &.{ a, b, c }, &.{ one, nine, three });

    try expectEqlExact(&m, merge_2(&m, &.{ map1, map2 }), want);
    // E3.10 (entry 6c): a non-map arg (either position) -> {badmap,Map}.
    try expectBadmap(&m, merge_2(&m, &.{ map1, one }), one);
    try expectBadmap(&m, merge_2(&m, &.{ one, map2 }), one);
}

test "LAW E2.7 new/0 denotes the empty map" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const empty = try new_0(&m, &.{});
    try std.testing.expectEqual(@as(usize, 0), FinalTerms.mapSize(&m.ctx, empty));
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, empty) == .map);
}

test "LAW E2.7 keys/1,values/1,to_list/1 over a >32-key (HAMT-backed) map: SET-equality (order divergence)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const n = 40; // exceeds max_flatmap_size (32) -> HAMT-backed
    var keys: [n]Term = undefined;
    var vals: [n]Term = undefined;
    var buf: [16]u8 = undefined;
    for (0..n) |i| {
        const name = std.fmt.bufPrint(&buf, "k{d}", .{i}) catch unreachable;
        keys[i] = FinalTerms.atom(&m.ctx, try atoms.intern(name));
        vals[i] = FinalTerms.int(&m.ctx, @intCast(i));
    }
    const map = try mkMap(&m, &keys, &vals);
    try std.testing.expect(!FinalTerms.mapRepIsFlat(&m.ctx, map));
    try std.testing.expectEqual(@as(usize, n), FinalTerms.mapSize(&m.ctx, map));

    // keys_1 returns exactly `n` DISTINCT elements, each `eqlExact` some
    // `keys[i]` — order-insensitive (SET equality), per the module's
    // documented HAMT-order divergence.
    const got_keys = try keys_1(&m, &.{map});
    var count: usize = 0;
    var cur = got_keys;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const h = FinalTerms.listHead(&m.ctx, cur);
        var found = false;
        for (keys) |k| {
            if (FinalTerms.eqlExact(&m.ctx, h, k)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
        count += 1;
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    try std.testing.expectEqual(@as(usize, n), count);

    // ROUND-TRIP still holds over the HAMT-backed map (order-independent by
    // construction — `mapNew` re-sorts/re-hashes).
    const list = try to_list_1(&m, &.{map});
    const back = try from_list_1(&m, &.{list});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, back, map));
}

// ── E31-T2: erts_internal:map_next/3 test helpers ───────────────────────────

fn isNoneAtom(m: *Machine, t: Term) bool {
    if (!FinalTerms.repIsAtom(t)) return false;
    const idx = m.ctx.atoms.intern("none") catch return false;
    return FinalTerms.atomIdxOf(t) == idx;
}

/// Drive `maps:to_list/1`'s LIST-mode loop over map_next/3 to a fixed point:
/// `to_list_internal([Iter,Map|Acc]) when is_integer(Iter) -> ...map_next...;
/// to_list_internal(Acc) -> Acc.` Our single-shot never returns an integer
/// head, so this terminates in one step — but the driver is exercised faithfully.
fn driveToList(m: *Machine, map: Term) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var iter = FinalTerms.int(&m.ctx, 0);
    var guard: usize = 0;
    while (guard < 1024) : (guard += 1) {
        const res = try map_next_3(m, &.{ iter, map, acc });
        // to_list_internal: is the result of shape [Iter,Map|Acc] with integer head?
        if (FinalTerms.kindOf(&m.ctx, res) == .cons) {
            const h = FinalTerms.listHead(&m.ctx, res);
            if (FinalTerms.repIsSmall(h)) {
                const t2 = FinalTerms.listTail(&m.ctx, res);
                iter = h;
                // t2 = [Map|Acc]
                acc = FinalTerms.listTail(&m.ctx, t2);
                continue;
            }
        }
        return res;
    }
    return error.Badarg; // non-termination is a failed law
}

/// Drive `maps:next/1`'s ITERATOR-mode unfold, collecting visited {K,V} pairs
/// into caller buffers; asserts the chain terminates in the `none` atom.
fn driveIterator(m: *Machine, path: Term, map: Term, ks: *std.ArrayList(Term), vs: *std.ArrayList(Term)) anyerror!void {
    var cur = try map_next_3(m, &.{ path, map, FinalTerms.atom(&m.ctx, m.ctx.atoms.intern("iterator") catch return error.OutOfMemory) });
    var guard: usize = 0;
    while (guard < 1024) : (guard += 1) {
        if (isNoneAtom(m, cur)) return; // terminated at 'none'
        // Otherwise a {K,V,Next} triple; `maps:next({K,V,I}) -> {K,V,I}` passes
        // triples through, so we walk the nested chain directly.
        try std.testing.expect(FinalTerms.kindOf(&m.ctx, cur) == .tuple);
        try std.testing.expectEqual(@as(usize, 3), FinalTerms.tupleArity(&m.ctx, cur));
        ks.append(m.gpa, FinalTerms.tupleElem(&m.ctx, cur, 0)) catch return error.OutOfMemory;
        vs.append(m.gpa, FinalTerms.tupleElem(&m.ctx, cur, 1)) catch return error.OutOfMemory;
        cur = FinalTerms.tupleElem(&m.ctx, cur, 2);
    }
    return error.Badarg;
}

test "LAW DIVERGENCE-676 erts_internal:mc_iterator/1 == map_next(0,Map,iterator): the whole map as a {K,V,Next} chain ending in `none` (mapPairs sorted); empty->none; non-map->badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const c = FinalTerms.atom(&m.ctx, try atoms.intern("c"));
    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    const three = FinalTerms.int(&m.ctx, 3);
    const none_at = FinalTerms.atom(&m.ctx, try atoms.intern("none"));
    // UNSORTED #{c=>3, a=>1, b=>2} → chain in SORTED key order {a,1,{b,2,{c,3,none}}}.
    const map = try mkMap(&m, &.{ c, a, b }, &.{ three, one, two });
    const want = try FinalTerms.tuple(&m.ctx, &.{ a, one, try FinalTerms.tuple(&m.ctx, &.{ b, two, try FinalTerms.tuple(&m.ctx, &.{ c, three, none_at }) }) });
    try expectEqlExact(&m, mc_iterator_1(&m, &.{map}), want);
    // denotes IDENTICALLY to erts_internal:map_next(0, Map, iterator) — the OTP definition.
    const iter_atom = FinalTerms.atom(&m.ctx, try atoms.intern("iterator"));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try mc_iterator_1(&m, &.{map}), try map_next_3(&m, &.{ FinalTerms.int(&m.ctx, 0), map, iter_atom })));
    // empty map → the atom `none` (an empty comprehension domain).
    const empty = try mkMap(&m, &.{}, &.{});
    try expectEqlExact(&m, mc_iterator_1(&m, &.{empty}), none_at);
    // a non-map argument → badarg (the internal primitive's plain badarg).
    try std.testing.expectError(error.Badarg, mc_iterator_1(&m, &.{one}));
}

test "LAW E31-T2 map_next/3 flatmap: list-mode & iterator-mode denote mapPairs in sorted order; drivers + rejections" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const x = FinalTerms.atom(&m.ctx, try atoms.intern("x"));
    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    // build UNSORTED -> the flatmap emits sorted (a<b) order, matching OTP.
    const map = try mkMap(&m, &.{ b, a }, &.{ two, one });
    const nil = FinalTerms.nil(&m.ctx);
    const iter_atom = FinalTerms.atom(&m.ctx, try atoms.intern("iterator"));

    // LIST mode, path 0, Acc []: byte-EQ [{a,1},{b,2}] (sorted key order).
    const kv_a = try FinalTerms.tuple(&m.ctx, &.{ a, one });
    const kv_b = try FinalTerms.tuple(&m.ctx, &.{ b, two });
    const want_list = try FinalTerms.cons(&m.ctx, kv_a, try FinalTerms.cons(&m.ctx, kv_b, nil));
    try expectEqlExact(&m, map_next_3(&m, &.{ FinalTerms.int(&m.ctx, 0), map, nil }), want_list);
    // to_list/1 driver yields the same complete list.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try driveToList(&m, map), want_list));
    // LIST mode prepends onto a non-empty Acc (OTP: res = BIF_ARG_3).
    const tail_seed = try FinalTerms.cons(&m.ctx, x, nil);
    const want_seeded = try FinalTerms.cons(&m.ctx, kv_a, try FinalTerms.cons(&m.ctx, kv_b, tail_seed));
    try expectEqlExact(&m, map_next_3(&m, &.{ FinalTerms.int(&m.ctx, 0), map, tail_seed }), want_seeded);

    // ITERATOR mode, path 0: nested chain {a,1,{b,2,none}} (byte-EQ, sorted).
    const none_at = FinalTerms.atom(&m.ctx, try atoms.intern("none"));
    const want_chain = try FinalTerms.tuple(&m.ctx, &.{ a, one, try FinalTerms.tuple(&m.ctx, &.{ b, two, none_at }) });
    try expectEqlExact(&m, map_next_3(&m, &.{ FinalTerms.int(&m.ctx, 0), map, iter_atom }), want_chain);

    // next/1 unfold visits [{a,1},{b,2}] and terminates at 'none'.
    var ks: std.ArrayList(Term) = .empty;
    defer ks.deinit(m.gpa);
    var vs: std.ArrayList(Term) = .empty;
    defer vs.deinit(m.gpa);
    try driveIterator(&m, FinalTerms.int(&m.ctx, 0), map, &ks, &vs);
    try std.testing.expectEqual(@as(usize, 2), ks.items.len);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ks.items[0], a) and FinalTerms.eqlExact(&m.ctx, vs.items[0], one));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ks.items[1], b) and FinalTerms.eqlExact(&m.ctx, vs.items[1], two));

    // ORDERED iterator: caller-supplied key order [b,a] -> {b,2,{a,1,none}} (byte-EQ).
    const order_ba = try FinalTerms.cons(&m.ctx, b, try FinalTerms.cons(&m.ctx, a, nil));
    const want_ord = try FinalTerms.tuple(&m.ctx, &.{ b, two, try FinalTerms.tuple(&m.ctx, &.{ a, one, none_at }) });
    try expectEqlExact(&m, map_next_3(&m, &.{ order_ba, map, iter_atom }), want_ord);
    // ordered nil path -> none.
    try expectEqlExact(&m, map_next_3(&m, &.{ nil, map, iter_atom }), none_at);
    // ordered absent key -> badarg.
    const order_x = try FinalTerms.cons(&m.ctx, x, nil);
    try std.testing.expectError(error.Badarg, map_next_3(&m, &.{ order_x, map, iter_atom }));

    // EMPTY map: list mode -> []; iterator mode -> none.
    const empty = try mkMap(&m, &.{}, &.{});
    try expectEqlExact(&m, map_next_3(&m, &.{ FinalTerms.int(&m.ctx, 0), empty, nil }), nil);
    try expectEqlExact(&m, map_next_3(&m, &.{ FinalTerms.int(&m.ctx, 0), empty, iter_atom }), none_at);

    // REJECTION: non-map -> PLAIN badarg (NOT {badmap,_}); bad third arg;
    // negative path; path > size.
    try std.testing.expectError(error.Badarg, map_next_3(&m, &.{ FinalTerms.int(&m.ctx, 0), one, nil }));
    try std.testing.expectError(error.Badarg, map_next_3(&m, &.{ FinalTerms.int(&m.ctx, 0), map, a })); // third = atom 'a' (not iterator/list)
    try std.testing.expectError(error.Badarg, map_next_3(&m, &.{ FinalTerms.int(&m.ctx, -1), map, nil }));
    try std.testing.expectError(error.Badarg, map_next_3(&m, &.{ FinalTerms.int(&m.ctx, 3), map, nil })); // 3 > size 2
    // in-range boundary path == size is accepted (OTP flatmap: n < path is the gate).
    try expectEqlExact(&m, map_next_3(&m, &.{ FinalTerms.int(&m.ctx, 2), map, nil }), want_list);
}

test "LAW E31-T2 map_next/3 HAMT (>32 keys): drivers visit exactly mapPairs (SET-eq), terminating at none" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const n = 40; // > max_flatmap_size (32) -> HAMT-backed
    var keys: [n]Term = undefined;
    var vals: [n]Term = undefined;
    var buf: [16]u8 = undefined;
    for (0..n) |i| {
        const name = std.fmt.bufPrint(&buf, "k{d}", .{i}) catch unreachable;
        keys[i] = FinalTerms.atom(&m.ctx, try atoms.intern(name));
        vals[i] = FinalTerms.int(&m.ctx, @intCast(i));
    }
    const map = try mkMap(&m, &keys, &vals);
    try std.testing.expect(!FinalTerms.mapRepIsFlat(&m.ctx, map));

    // helper: check a visited {k,v} pair is one of the constructed associations.
    const S = struct {
        fn matches(mm: *Machine, keyset: []const Term, valset: []const Term, k: Term, v: Term) bool {
            for (keyset, valset) |kk, vv| {
                if (FinalTerms.eqlExact(&mm.ctx, k, kk)) return FinalTerms.eqlExact(&mm.ctx, v, vv);
            }
            return false;
        }
    };

    // ITERATOR mode driver: unfold, collect, assert SET-equality + count n +
    // termination at 'none' (driveIterator asserts the terminator).
    var iks: std.ArrayList(Term) = .empty;
    defer iks.deinit(m.gpa);
    var ivs: std.ArrayList(Term) = .empty;
    defer ivs.deinit(m.gpa);
    try driveIterator(&m, FinalTerms.int(&m.ctx, 0), map, &iks, &ivs);
    try std.testing.expectEqual(@as(usize, n), iks.items.len);
    for (iks.items, ivs.items) |k, v| try std.testing.expect(S.matches(&m, &keys, &vals, k, v));

    // LIST mode driver (maps:to_list/1): walk the returned proper list, assert
    // SET-equality + count n + proper nil termination.
    const lst = try driveToList(&m, map);
    var count: usize = 0;
    var cur = lst;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const kv = FinalTerms.listHead(&m.ctx, cur);
        try std.testing.expect(FinalTerms.kindOf(&m.ctx, kv) == .tuple and FinalTerms.tupleArity(&m.ctx, kv) == 2);
        try std.testing.expect(S.matches(&m, &keys, &vals, FinalTerms.tupleElem(&m.ctx, kv, 0), FinalTerms.tupleElem(&m.ctx, kv, 1)));
        count += 1;
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
    try std.testing.expectEqual(@as(usize, n), count);
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, cur) == .nil); // proper list

    // ORDERED iterator over the HAMT is representation-independent -> the visited
    // sequence is EXACTLY the supplied key order (byte-EQ even for a HAMT).
    var order = FinalTerms.nil(&m.ctx);
    var j: usize = n;
    while (j > 0) {
        j -= 1;
        order = try FinalTerms.cons(&m.ctx, keys[j], order);
    }
    var oks: std.ArrayList(Term) = .empty;
    defer oks.deinit(m.gpa);
    var ovs: std.ArrayList(Term) = .empty;
    defer ovs.deinit(m.gpa);
    try driveIterator(&m, order, map, &oks, &ovs);
    try std.testing.expectEqual(@as(usize, n), oks.items.len);
    for (0..n) |i| {
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, oks.items[i], keys[i]));
        try std.testing.expect(FinalTerms.eqlExact(&m.ctx, ovs.items[i], vals[i]));
    }
}
