//! # bifs/ets — the `ets:` BIF family (E2.9)
//!
//! ## Signature
//! Same contract as the other family modules (`bifs/erlang.zig`/`maps.zig`/…):
//! each BIF is a `pub fn (m: *Machine, args: []const Term) BifError!Term` over
//! ALREADY-RESOLVED term arguments, computed by driving `ets_algebra`'s
//! `TreeBackend` (the live backend, see below) + the `EtsRegistry` — NO new ETS
//! or matchspec semantics live here. It NEVER panics on a well-formed call
//! (`badarg` on a bad Tid, bad options, a non-tuple object, or a bad position).
//!
//! ## The dispatch mechanism (unchanged — see `bifs/dispatch.zig`)
//! This task adds ONLY `pub fn`s here, `implOf`/`implOfEts` arms in
//! `bifs/dispatch.zig`, `implemented_map` rows in `harness/bif_gen.ml`, and the
//! matching `supported_bifs` rows in `instr_algebra.zig`. The `bif_call`
//! executor and loader are untouched.
//!
//! ## WHERE ETS STATE LIVES (the crux) — E7.3: shared, Vm-owned (DIVERGENCE 143)
//! ETS tables are mutable, process-external, and identified by a Tid — a
//! `ets:insert(Tid,Obj)` must FIND the table and mutate it across BIF calls AND
//! across processes. The live tables live in the ONE `EtsRegistry` the Vm owns
//! (`proc.zig`'s `Vm.ets`); every process reaches it via `m.etsReg()` (the
//! shared registry when the Vm set `m.shared_ets`, else the Machine's own
//! fallback for standalone law suites). `ets:new/2` allocates + registers a
//! table in that shared space and returns its Tid; every other BIF resolves the
//! Tid → `*EtsTable` and operates. So a table one process creates is visible to
//! ALL processes (real cross-process ETS), matching BEAM.
//!
//! ## THE COPY BOUNDARY + the ATOMICITY MODEL (E7.3)
//! Because a table outlives any single process, its stored objects cannot be
//! offsets into a process's `ctx` heap — they live in the registry's OWN
//! `region` heap (`m.etsReg().region`). Each ETS BIF is a SYNCHRONOUS,
//! ATOMIC operation on the CALLER's scheduler slice (no signal, no yield inside
//! a BIF — the sacred M7 per-pair signal order is untouched, ETS emits none):
//!   * a WRITE (insert/delete/update) gcCopies the object from the caller's
//!     `ctx` INTO `region`, then mutates the backend against `region`;
//!   * a READ (lookup/member/first/…) probes the backend against `region`
//!     (the key is copied in), then gcCopies each result back OUT to the
//!     caller's `ctx` — the M1 copy law, exactly as message send crosses heaps.
//! The BIF runs to completion before any other process is scheduled, so a
//! reader never observes a half-applied multi-object insert (all-or-nothing).
//! `region` is never collected (bounded runs — the erts ETS-heap / literal-area
//! precedent). Helpers `bInsert`/`bLookup`/`bDelete`/`dumpObjects` encapsulate
//! the boundary; every other line of this file still reasons over `m.ctx`.
//!
//! ## E6.7 (Task 7): the multi-process OWNERSHIP surface
//! Each table carries an `owner` pid (set to the creator at `ets:new`) and an
//! optional `heir`/`heir_data` (`ets_algebra.EtsTable`). `give_away/3` reassigns
//! the owner + delivers `{'ETS-TRANSFER',Tab,From,Gift}` (it TRAPS to proc.zig —
//! the recipient's liveness + the signal need the Vm); `setopts/2` sets the heir
//! (round-trips via `info(T,heir)`); `whereis/1` returns the Tid (round-trips
//! through `lookup`); `info(T,owner|heir)` reads them back. The owner-death
//! LIFECYCLE (heir-less auto-delete / heir transfer) is `EtsRegistry.ownerDied`.
//! STILL single-Machine: the tables are per-Machine, so a give_away recipient (a
//! separate Machine) never ACCESSES the table — only the ownership move + the
//! transfer SIGNAL are modelled (the observation the corpus checks). Access-
//! protection is still unmodelled; `internal_request_all/0` (a scheduler-wide
//! table collect) re-binds to `deferred-ets-sharedtab` (E7 shared-ETS: moving
//! `EtsRegistry` from Machine to Vm). DIVERGENCE 124.
//!
//! ## Tid REPRESENTATION (a documented E-scope simplification)
//! An UNNAMED table's Tid is a small-integer term (its dense registry id); a
//! `named_table`'s Tid is the Name atom. Both resolve: an integer arg → `byId`,
//! an atom arg → `byName` (a named table is reachable by EITHER, as on BEAM).
//! Real BEAM Tids are references; using an integer id is the single-Machine
//! simplification (a ref term / global table manager is the multi-process
//! epoch's job). Ids are never reused, so a Tid from a `delete/1`'d table
//! resolves to `null` → `badarg` (never a use-after-free).
//!
//! ## IMPLEMENTED vs DEFERRED (honest split)
//! IMPLEMENTED + wired (16 bif.tab rows): `new/2`, `insert/2`, `insert_new/2`,
//! `lookup/2`, `lookup_element/3,4`, `member/2`, `delete/1,2`, `delete_object/2`,
//! `first/1`, `next/2`, `last/1`, `prev/2`, `info/1,2`.
//! DEFINED but NOT wired (ets.erl library wrappers — not bif.tab rows on this
//! pin, the same shape as `maps:to_list/1`): `tab2list/1` (a `select`-all
//! wrapper), `delete_all_objects/1` (wraps `ets:internal_delete_all/2`).
//! DEFERRED (left `.stub` in the ledger — the pin knows them, the VM does not
//! implement them yet): the whole `match`/`match_object`/`select`/`select_count`/
//! `select_delete`/`select_replace`/`select_reverse` family. These take a
//! runtime match-spec/pattern TERM and require COMPILING it into the Zig
//! `matchspec.MatchSpec` struct (BEAM's `ets:match_spec_compile` /
//! `erl_db_util.c` `db_match_compile`). M11 provides the match-spec ENGINE
//! (`matchspec.run` over a pre-built `MatchSpec`, plus the SELECT≡filter law)
//! but NOT that term→program compiler — building it is genuinely NEW matchspec
//! semantics and a separate reviewable slice. Wiring `select` to a hand-built
//! `MatchSpec` would not accept a runtime spec, so the family defers whole.
//!
//! ## `duplicate_bag` — S22 open edge CLOSED (E3.16)
//! `ets_algebra` now implements set/ordered_set/bag/duplicate_bag. `ets:new/2`
//! accepts `duplicate_bag`; its one semantic delta from `bag` is exact-duplicate
//! RETENTION — `insert` appends every copy (bag dedupes), `lookup` returns N
//! copies for N inserts, and `delete_object` removes ALL equal copies (the
//! exact-object filter reinserts only the survivors — for duplicate_bag that
//! drops every match, mirroring `erl_db_hash.c`'s `DB_DUPLICATE_BAG` `continue`
//! loop; for bag, which holds ≤1 equal object, the effect is identical).
//! `update_element` stays set/ordered_set-only (duplicate_bag → badarg, like bag).
//!
//! ## `keypos` — only 1 supported (documented)
//! `ets_algebra` keys on tuple element 1 (keypos 1). `{keypos, N}` with N≠1
//! would need the key at a different position — new semantics — so it defers to
//! `error.Badarg`. Default keypos 1 (the overwhelming common case) is exact.
//!
//! ## `{badmap,…}`/structured-reason DIVERGENCE (consistent with E2.4/E2.7)
//! The E1-minimal `BifError` carries only `Badarg`/`Badarith`/`OutOfMemory` — no
//! payload term — so every bad-Tid / bad-option / bad-object / bad-position case
//! is a plain `error.Badarg` (BEAM's `badarg`). Recorded as an EXTENSION of
//! `DIVERGENCE_LOG.md` entry 6 (E1 exception model has no structured reason),
//! not a new entry. Likewise `info/1,2` return a documented SUBSET of BEAM's
//! fields (size/type/named_table/name/keypos/id/protection) — `memory`/`owner`/
//! etc. need the process/heap accounting model (deferred), so an unsupported
//! `info/2` item is `error.Badarg`.
//!
//! ## Table OPTIONS: declared, observed, and NOT acted upon (gap-ets-table-options)
//! `ets:new/2` accepts `read_concurrency` / `write_concurrency` /
//! `decentralized_counters` / `compressed` and the `public|protected|private`
//! access atoms, and `ets:info/2` reports each of them byte-EQ against OTP-30.
//! These were previously accepted and DISCARDED, so every one of them was a
//! `badarg` against a real OTP value, and `protection` was worse than absent —
//! it returned a hardcoded `protected`, which was truthful only while nothing
//! else could be declared.
//!
//! **They are DECLARATIONS, not behaviour, and that line is not blurred here.**
//! The registry remains one reentrant spinlock, so the concurrency hints change
//! no locking; `compressed` does not compress. This matches what OTP's `info/2`
//! itself reports — the option as set, never a measurement — so reporting it is
//! honest. The unmodelled engine behaviour is the {S}-axis work and stays with
//! `gap-ets-concurrency`.
//!
//! **`decentralized_counters` is DERIVED, not stored**, and the equation is not
//! guessable from the option's name:
//! ```
//!   dc = write_concurrency.enabled() AND (dc_option ORELSE (type == ordered_set))
//! ```
//! with `auto` counting as enabled. Nine operand cells were measured on OTP-30;
//! the obvious "report what was set" reading is wrong in three of them. The
//! semantic domain lives in `ets_algebra.TableOpts`; the cells are enumerated by
//! `LAW gap-ets-table-options DC-CELLS`.
//!
//! Option VALUES are validated (a non-boolean is `badarg`, and `{compressed,
//! true}` in tuple form is `badarg` — only the bare atom is legal), and a
//! repeated option takes its LAST value. **RESIDUAL:** `info/1` still returns
//! the 7-key subset below; OTP-30's has 15, and the missing `memory`/`node`
//! totality is its own slice.
//!
//! ## first/next ORDER (documented divergence, the maps-HAMT analog)
//! The live backend is `TreeBackend` for ALL types (sound: the M11 triple
//! homomorphism proves it denotation-equal to hash/catree). Traversal
//! (`first`/`next`/`last`/`prev`) is therefore ascending in the backend's
//! order: for `ordered_set` that IS BEAM's order (arithmetic term order);
//! for `set`/`bag` it is exact-term order — deterministic but not BEAM's
//! hash-bucket order (a divergence, exactly the maps-HAMT-order situation).
//! `next(K)`/`prev(K)` return the nearest strictly-greater/-lesser key in that
//! order, which handles a present OR absent `K` uniformly.
//!
//! ## Lifetime safety (the E2.5+ lesson, audited)
//! Every value flowing through here is a `Term` VALUE (a `ctx.words` offset),
//! never a raw `[]const u8` binary slice — so holding one across a later
//! `cons`/`tuple`/`insert` that reallocates `ctx.words` is SAFE (the offset
//! stays valid post-realloc). Objects are collected into `m.gpa`-owned buffers
//! BEFORE any table mutation, so `insert`/`insert_new` are all-or-nothing on a
//! bad element and never observe a half-built list. The one non-Term pointer —
//! a `*EtsTable` from `byId`/`byName` — is used only within a single BIF and
//! never held across a `create` (the only op that reallocs the registry).
//!
//! ## Laws (see the suite below; they REUSE the M11 backend laws)
//!   - REGISTRY ROUND-TRIP  insert(T,O) then lookup(T,key(O)) == [O] (set), and
//!     the value survives across other tables' ops (process-external state).
//!   - lookup DENOTATION    ets:lookup(T,K) == the backend's lookup (M11).
//!   - KEY SEMANTICS        set keeps 1 and 1.0 apart (=:= keys); ordered_set
//!     collapses them (== keys) — reuses `ets_algebra`'s comparators, no new one.
//!   - insert OVERWRITE     insert of an equal key into a `set` REPLACES it
//!     (mutant 1 target); a `bag` accumulates distinct objects.
//!   - first/next WALK      first/next/last/prev enumerate every key once, in
//!     order (ordered_set: arithmetic-ascending), no key skipped or repeated
//!     (mutant 2 target).
//!   - LIFETIME/OWNERSHIP   a delete/1'd Tid → badarg; leak-free (registry freed
//!     in Machine.deinit; std.testing.allocator proves it).
//!   - DUPLICATE_BAG        insert appends exact duplicates (bag dedupes them);
//!     delete_object removes ALL equal copies (E3.16 — the S22 open edge).
//!   - REJECTION            bad Tid / bad opts / keypos≠1 / non-tuple object /
//!     bad position → clean `error.Badarg` (never a panic).

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const ea = @import("../ets_algebra.zig");
const msc = @import("../matchspec.zig");
const pat = @import("../pattern_algebra.zig");

const FinalTerms = ta.FinalTerms;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;
const TableType = ea.TableType;
const EtsTable = ea.EtsTable;

// ── shared helpers ─────────────────────────────────────────────────────────

fn boolTerm(m: *Machine, cond: bool) Term {
    return FinalTerms.atom(&m.ctx, if (cond) m.bool_true else m.bool_false);
}

/// gap-ets-table-options: an option VALUE that must be `true` or `false`.
///
/// The rejection half matters as much as the acceptance half. Before this,
/// `ets:new(t, [{read_concurrency, notabool}])` SUCCEEDED here and is a
/// `badarg` on OTP-30 — an accept-everything reader satisfies every positive
/// law anyone might write about these options.
fn boolOpt(m: *Machine, v: Term) BifError!bool {
    if (atomEq(m, v, "true")) return true;
    if (atomEq(m, v, "false")) return false;
    return error.Badarg;
}

fn internAtom(m: *Machine, name: []const u8) BifError!Term {
    const idx = m.ctx.atoms.intern(name) catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

/// Does term `t` equal the atom named `name`?
fn atomEq(m: *Machine, t: Term, name: []const u8) bool {
    if (!FinalTerms.repIsAtom(t)) return false;
    const idx = m.ctx.atoms.intern(name) catch return false;
    return FinalTerms.atomIdxOf(t) == idx;
}

/// Resolve a Tid arg (integer id | name atom) to its live table, or `badarg`.
/// Resolves against the EFFECTIVE (shared, when under a Vm) registry.
pub fn resolveTable(m: *Machine, tid: Term) BifError!*EtsTable {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    if (FinalTerms.repIsSmall(tid)) {
        const v = FinalTerms.smallValOf(tid);
        if (v < 0) return error.Badarg;
        return m.etsReg().byId(@intCast(v)) orelse error.Badarg;
    }
    if (FinalTerms.repIsAtom(tid)) {
        return m.etsReg().byName(FinalTerms.atomIdxOf(tid)) orelse error.Badarg;
    }
    return error.Badarg;
}

// ── E7.3: the shared-table COPY BOUNDARY (see the module doc) ────────────────
// Every backend op runs against the registry's `region` heap; the caller's
// terms are gcCopied in on write and out on read, so all OTHER code in this
// file keeps reasoning over `m.ctx`.

/// The shared table-storage heap (`region`) of this Machine's effective registry.
fn rctx(m: *Machine) *FinalTerms.Ctx {
    return &m.etsReg().region;
}

/// Copy a caller-heap term INTO the shared storage heap (a write crossing in).
fn copyIn(m: *Machine, w: Term) BifError!Term {
    return FinalTerms.gcCopy(rctx(m), &m.ctx, w) catch return error.OutOfMemory;
}

/// Copy a stored (region) term back OUT to the caller's heap (a read crossing out).
fn copyOut(m: *Machine, w: Term) BifError!Term {
    return FinalTerms.gcCopy(&m.ctx, rctx(m), w) catch return error.OutOfMemory;
}

/// Insert `obj` (a caller-heap term) into table `t`: copy it into `region`, then
/// mutate the backend against `region`.
fn bInsert(m: *Machine, t: *EtsTable, obj: Term) BifError!void {
    const oc = try copyIn(m, obj);
    t.backend.insert(rctx(m), oc) catch return error.OutOfMemory;
}

/// Look up `key` (a caller-heap term) in table `t`, appending each match to
/// `out` as a CALLER-heap copy (so downstream code reasons over `m.ctx`).
fn bLookup(m: *Machine, t: *EtsTable, key: Term, out: *std.ArrayList(Term)) BifError!void {
    const kc = try copyIn(m, key);
    var probe: std.ArrayList(Term) = .empty;
    defer probe.deinit(m.gpa);
    t.backend.lookup(rctx(m), kc, &probe) catch return error.OutOfMemory;
    for (probe.items) |r| out.append(m.gpa, try copyOut(m, r)) catch return error.OutOfMemory;
}

/// Delete every object under `key` (a caller-heap term) from table `t`.
fn bDelete(m: *Machine, t: *EtsTable, key: Term) BifError!void {
    const kc = try copyIn(m, key);
    t.backend.delete(rctx(m), kc);
}

/// The key (tuple element 1) of a validated object.
fn keyOf(m: *Machine, obj: Term) Term {
    return FinalTerms.tupleElem(&m.ctx, obj, 0);
}

/// A well-formed ETS object is a tuple of arity ≥ 1 (keypos 1).
fn validObject(m: *Machine, obj: Term) bool {
    return FinalTerms.kindOf(&m.ctx, obj) == .tuple and FinalTerms.tupleArity(&m.ctx, obj) >= 1;
}

/// Two keys are "the same key" under the table's type: set/bag use =:= (exact),
/// ordered_set uses == (arithmetic) — mirroring `ets_algebra`'s `keyEq`.
fn sameKey(m: *Machine, ty: TableType, a: Term, b: Term) bool {
    return switch (ty) {
        .set, .bag, .duplicate_bag => FinalTerms.eqlExact(&m.ctx, a, b),
        .ordered_set => FinalTerms.eql(&m.ctx, a, b),
    };
}

/// The table's key order: ordered_set is arithmetic, set/bag is exact — the
/// SAME comparators `TreeBackend.cmpKeys` uses (reused, not reinvented).
fn cmpKeys(m: *Machine, ty: TableType, a: Term, b: Term) ta.Order {
    return switch (ty) {
        .ordered_set => FinalTerms.compare(&m.ctx, a, b),
        .set, .bag, .duplicate_bag => FinalTerms.compareExact(&m.ctx, a, b),
    };
}

/// Dump ALL objects of `t` in backend (ascending-key) order into an m.gpa-owned
/// list. Caller deinits.
fn dumpObjects(m: *Machine, t: *EtsTable) BifError!std.ArrayList(Term) {
    var raw: std.ArrayList(Term) = .empty; // region terms
    defer raw.deinit(m.gpa);
    t.backend.dumpInto(&raw) catch return error.OutOfMemory;
    var out: std.ArrayList(Term) = .empty; // caller-heap copies (E7.3 copy-out)
    errdefer out.deinit(m.gpa);
    for (raw.items) |r| out.append(m.gpa, try copyOut(m, r)) catch return error.OutOfMemory;
    return out;
}

/// Collect the object argument of insert/insert_new (a single tuple OR a list
/// of tuples) into an m.gpa-owned buffer, validating EVERY element up front so
/// the caller can be all-or-nothing. `nil` → empty. Non-tuple element, improper
/// list, or a non-tuple/non-list arg → badarg.
fn collectObjects(m: *Machine, arg: Term) BifError!std.ArrayList(Term) {
    var out: std.ArrayList(Term) = .empty;
    errdefer out.deinit(m.gpa);
    switch (FinalTerms.kindOf(&m.ctx, arg)) {
        .tuple => {
            if (!validObject(m, arg)) return error.Badarg;
            out.append(m.gpa, arg) catch return error.OutOfMemory;
        },
        .nil => {},
        .cons => {
            var cur = arg;
            while (true) {
                switch (FinalTerms.kindOf(&m.ctx, cur)) {
                    .nil => break,
                    .cons => {
                        const h = FinalTerms.listHead(&m.ctx, cur);
                        if (!validObject(m, h)) return error.Badarg;
                        out.append(m.gpa, h) catch return error.OutOfMemory;
                        cur = FinalTerms.listTail(&m.ctx, cur);
                    },
                    else => return error.Badarg, // improper list
                }
            }
        },
        else => return error.Badarg,
    }
    return out;
}

/// Build a proper list from `items` (head-first order preserved). Term VALUES,
/// realloc-safe.
fn listOf(m: *Machine, items: []const Term) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = items.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, items[i], acc) catch return error.OutOfMemory;
    }
    return acc;
}

// ── ets:new/2 ───────────────────────────────────────────────────────────────

pub fn new_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const name_term = args[0];
    if (!FinalTerms.repIsAtom(name_term)) return error.Badarg; // Name must be an atom
    const name = FinalTerms.atomIdxOf(name_term);

    var ty: TableType = .set; // BEAM default
    var named = false;
    var heir: u64 = 0; //             E6.7: {heir,Pid,Data} sets the death-heir (0 == none)
    // gap-ets-table-options: LAST WINS, which falls out of assigning into one
    // accumulator as the list is walked — measured on OTP-30, where
    // `[{read_concurrency,true},{read_concurrency,false}]` reports `false`.
    var opts: ea.TableOpts = .{};
    var heir_data: ?Term = null;

    var cur = args[1];
    while (true) {
        switch (FinalTerms.kindOf(&m.ctx, cur)) {
            .nil => break,
            .cons => {
                const opt = FinalTerms.listHead(&m.ctx, cur);
                cur = FinalTerms.listTail(&m.ctx, cur);
                // E6.7: {heir, Pid, HeirData} (arity 3) / {heir, none} (arity 2).
                if (FinalTerms.kindOf(&m.ctx, opt) == .tuple and FinalTerms.tupleArity(&m.ctx, opt) == 3 and
                    atomEq(m, FinalTerms.tupleElem(&m.ctx, opt, 0), "heir"))
                {
                    const hp = FinalTerms.tupleElem(&m.ctx, opt, 1);
                    if (!FinalTerms.repIsPid(&m.ctx, hp)) return error.Badarg;
                    heir = FinalTerms.pidNumber(&m.ctx, hp);
                    heir_data = FinalTerms.tupleElem(&m.ctx, opt, 2);
                } else if (FinalTerms.repIsAtom(opt)) {
                    if (atomEq(m, opt, "set")) {
                        ty = .set;
                    } else if (atomEq(m, opt, "ordered_set")) {
                        ty = .ordered_set;
                    } else if (atomEq(m, opt, "bag")) {
                        ty = .bag;
                    } else if (atomEq(m, opt, "duplicate_bag")) {
                        ty = .duplicate_bag;
                    } else if (atomEq(m, opt, "named_table")) {
                        named = true;
                    } else if (atomEq(m, opt, "public")) {
                        opts.protection = .public;
                    } else if (atomEq(m, opt, "protected")) {
                        opts.protection = .protected;
                    } else if (atomEq(m, opt, "private")) {
                        opts.protection = .private;
                    } else if (atomEq(m, opt, "compressed")) {
                        // gap-ets-table-options: DECLARED, and observable through
                        // `info/2`. It does NOT compress — the storage engine is
                        // unchanged — and that residual is disclosed in the module
                        // doc rather than hidden behind a truthful-looking flag.
                        opts.compressed = true;
                    } else return error.Badarg;
                } else if (FinalTerms.kindOf(&m.ctx, opt) == .tuple and FinalTerms.tupleArity(&m.ctx, opt) == 2) {
                    const tag = FinalTerms.tupleElem(&m.ctx, opt, 0);
                    if (atomEq(m, tag, "keypos")) {
                        const pv = FinalTerms.tupleElem(&m.ctx, opt, 1);
                        // only keypos 1 supported (see module doc).
                        if (!FinalTerms.repIsSmall(pv) or FinalTerms.smallValOf(pv) != 1) return error.Badarg;
                    } else if (atomEq(m, tag, "read_concurrency")) {
                        opts.read_concurrency = try boolOpt(m, FinalTerms.tupleElem(&m.ctx, opt, 1));
                    } else if (atomEq(m, tag, "write_concurrency")) {
                        // The one option with three values, not two. OTP-30
                        // reports `auto` back verbatim, so a bool would lose it.
                        const v = FinalTerms.tupleElem(&m.ctx, opt, 1);
                        opts.write_concurrency =
                            if (atomEq(m, v, "auto")) .auto
                            else if (try boolOpt(m, v)) .on
                            else .off;
                    } else if (atomEq(m, tag, "decentralized_counters")) {
                        // STORED, but never reported directly — see
                        // `TableOpts.decentralizedCounters`. The value is still
                        // VALIDATED here, because OTP badargs a non-bool even
                        // though the observation is derived.
                        opts.dc_opt = try boolOpt(m, FinalTerms.tupleElem(&m.ctx, opt, 1));
                    } else if (atomEq(m, tag, "heir")) {
                        // heir tuning is not modeled — accepted, ignored.
                    } else return error.Badarg;
                } else return error.Badarg;
            },
            else => return error.Badarg, // improper opts list
        }
    }

    if (named and m.etsReg().byName(name) != null) return error.Badarg; // name collision
    const id = m.etsReg().create(ty, named, name, 1) catch return error.OutOfMemory;
    // E6.7: the creating process OWNS the table (ets:info(T,owner) == self()).
    const t = m.etsReg().byId(id).?;
    t.owner = m.self_pid;
    t.heir = heir;
    t.opts = opts;
    // E7.3: heir_data is stored in the shared table, so it must live in the
    // registry's `region` heap (a caller-ctx offset would dangle for other
    // processes) — copy it in, like any stored object.
    t.heir_data = if (heir_data) |hd| try copyIn(m, hd) else null;
    return if (named) name_term else FinalTerms.int(&m.ctx, @intCast(id));
}

// ── ets:insert/2, ets:insert_new/2 ──────────────────────────────────────────

pub fn insert_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var objs = try collectObjects(m, args[1]);
    defer objs.deinit(m.gpa);
    for (objs.items) |o| {
        try bInsert(m, t, o);
    }
    return boolTerm(m, true);
}

pub fn insert_new_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var objs = try collectObjects(m, args[1]);
    defer objs.deinit(m.gpa);

    // Conflict iff any key already exists in the table OR repeats within the
    // batch — then insert NOTHING and return false.
    var batch_keys: std.ArrayList(Term) = .empty;
    defer batch_keys.deinit(m.gpa);
    for (objs.items) |o| {
        const k = keyOf(m, o);
        var probe: std.ArrayList(Term) = .empty;
        defer probe.deinit(m.gpa);
        try bLookup(m, t, k, &probe);
        if (probe.items.len != 0) return boolTerm(m, false);
        for (batch_keys.items) |pk| {
            if (sameKey(m, t.ty, k, pk)) return boolTerm(m, false);
        }
        batch_keys.append(m.gpa, k) catch return error.OutOfMemory;
    }
    for (objs.items) |o| {
        try bInsert(m, t, o);
    }
    return boolTerm(m, true);
}

// ── ets:lookup/2 ────────────────────────────────────────────────────────────

pub fn lookup_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var out: std.ArrayList(Term) = .empty;
    defer out.deinit(m.gpa);
    try bLookup(m, t, args[1], &out);
    return listOf(m, out.items);
}

// ── ets:lookup_element/3,4 ──────────────────────────────────────────────────

fn lookupElement(m: *Machine, t: *EtsTable, key: Term, pos_term: Term, default: ?Term) BifError!Term {
    if (!FinalTerms.repIsSmall(pos_term)) return error.Badarg;
    const pv = FinalTerms.smallValOf(pos_term);
    if (pv < 1) return error.Badarg;
    const pos: usize = @intCast(pv);

    var out: std.ArrayList(Term) = .empty;
    defer out.deinit(m.gpa);
    try bLookup(m, t, key, &out);
    if (out.items.len == 0) return default orelse error.Badarg;

    // Every matching object must have arity ≥ pos, else badarg (even with a /4
    // default — a present-but-too-short object is a genuine badarg on BEAM).
    for (out.items) |o| {
        if (FinalTerms.tupleArity(&m.ctx, o) < pos) return error.Badarg;
    }
    switch (t.ty) {
        .set, .ordered_set => return FinalTerms.tupleElem(&m.ctx, out.items[0], pos - 1),
        .bag, .duplicate_bag => {
            // multiple objects per key → the LIST of position elements (a
            // duplicate_bag may return the same element several times).
            var elems: std.ArrayList(Term) = .empty;
            defer elems.deinit(m.gpa);
            for (out.items) |o| {
                elems.append(m.gpa, FinalTerms.tupleElem(&m.ctx, o, pos - 1)) catch return error.OutOfMemory;
            }
            return listOf(m, elems.items);
        },
    }
}

pub fn lookup_element_3(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    return lookupElement(m, t, args[1], args[2], null);
}

pub fn lookup_element_4(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    return lookupElement(m, t, args[1], args[2], args[3]);
}

// ── ets:member/2 ────────────────────────────────────────────────────────────

pub fn member_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var out: std.ArrayList(Term) = .empty;
    defer out.deinit(m.gpa);
    try bLookup(m, t, args[1], &out);
    return boolTerm(m, out.items.len != 0);
}

// ── ets:delete/1 (whole table), ets:delete/2 (key), ets:delete_object/2 ─────

pub fn delete_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    m.etsReg().drop(t.id);
    return boolTerm(m, true);
}

pub fn delete_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    try bDelete(m, t, args[1]);
    return boolTerm(m, true);
}

pub fn delete_object_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    const obj = args[1];
    if (!validObject(m, obj)) return error.Badarg;
    const key = keyOf(m, obj);

    // Remove ONLY the exact object: read the key's run, delete the whole run,
    // reinsert the survivors in order (reuses insert/delete/lookup — no new
    // backend op). set/ordered_set have ≤1 object; bag preserves insert order.
    var run: std.ArrayList(Term) = .empty;
    defer run.deinit(m.gpa);
    try bLookup(m, t, key, &run);
    try bDelete(m, t, key);
    for (run.items) |o| {
        if (!FinalTerms.eqlExact(&m.ctx, o, obj)) {
            try bInsert(m, t, o);
        }
    }
    return boolTerm(m, true);
}

// ── ets:first/1, ets:next/2, ets:last/1, ets:prev/2 (traversal) ─────────────

fn endOfTable(m: *Machine) BifError!Term {
    return internAtom(m, "$end_of_table");
}

pub fn first_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    if (objs.items.len == 0) return endOfTable(m);
    return keyOf(m, objs.items[0]); // smallest key (ascending dump)
}

pub fn last_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    if (objs.items.len == 0) return endOfTable(m);
    return keyOf(m, objs.items[objs.items.len - 1]); // largest key
}

pub fn next_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    const k = args[1];
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    // nearest strictly-greater key (handles present OR absent K); ascending dump.
    for (objs.items) |o| {
        const ok = keyOf(m, o);
        if (cmpKeys(m, t.ty, ok, k) == .gt) return ok;
    }
    return endOfTable(m);
}

pub fn prev_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    const k = args[1];
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    // nearest strictly-lesser key: last key < K in the ascending dump.
    var i = objs.items.len;
    while (i > 0) {
        i -= 1;
        const ok = keyOf(m, objs.items[i]);
        if (cmpKeys(m, t.ty, ok, k) == .lt) return ok;
    }
    return endOfTable(m);
}

// ── E3.18: ets core extensions over the live TreeBackend ────────────────────
//
// The E2 fast-follow ets siblings (DIVERGENCE_LOG entry 13(a)) that resolve
// PURELY over the existing backend + registry (no new ETS/matchspec semantics,
// no cross-process ownership): `take/2`, `update_element/3,4`, the combined
// traversal+lookup `first_lookup/1`/`last_lookup/1`/`next_lookup/2`/
// `prev_lookup/2`, and the single-process no-op `safe_fixtable/2`. The rows that
// GENUINELY need machinery this single-Machine VM lacks (`give_away/3` — a live
// target process + the owner-death lifecycle; `whereis/1`/`slot/2` — a real
// ref-Tid / impl-defined hash; `update_counter/3,4` — the increment-op grammar;
// `setopts/2` — the owner/heir/protection model) stay re-bound in
// harness/bif_gen.ml with precise blockers (never a false EQ). `rename/2` is the
// EXCEPTION discharged at E5.9 (`rename_2` below): a pure name-registry remap
// the single-Machine registry models exactly — EQ, not deferred.

/// `ets:take(Tab, Key)` — return the key's objects AND remove them (atomic
/// lookup+delete). `[]` when absent.
pub fn take_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var out: std.ArrayList(Term) = .empty;
    defer out.deinit(m.gpa);
    try bLookup(m, t, args[1], &out);
    const res = try listOf(m, out.items);
    try bDelete(m, t, args[1]);
    return res;
}

/// `setelement`-equivalent over an ETS object: a fresh tuple with element `pos`
/// (1-based) replaced by `val`. `pos` already validated in [2, arity].
fn withElement(m: *Machine, obj: Term, pos: usize, val: Term) BifError!Term {
    const arity = FinalTerms.tupleArity(&m.ctx, obj);
    var elems: std.ArrayList(Term) = .empty;
    defer elems.deinit(m.gpa);
    var i: usize = 0;
    while (i < arity) : (i += 1) {
        elems.append(m.gpa, if (i == pos - 1) val else FinalTerms.tupleElem(&m.ctx, obj, i)) catch return error.OutOfMemory;
    }
    return FinalTerms.tuple(&m.ctx, elems.items) catch error.OutOfMemory;
}

/// One `{Pos, Value}` update spec, validated against `arity`. Pos must be a
/// small in [2, arity] (never the keypos 1). Returns `{pos, value}`.
fn parseElemSpec(m: *Machine, spec: Term, arity: usize) BifError!struct { pos: usize, val: Term } {
    if (FinalTerms.kindOf(&m.ctx, spec) != .tuple or FinalTerms.tupleArity(&m.ctx, spec) != 2) return error.Badarg;
    const pt = FinalTerms.tupleElem(&m.ctx, spec, 0);
    if (!FinalTerms.repIsSmall(pt)) return error.Badarg;
    const pv = FinalTerms.smallValOf(pt);
    if (pv < 2 or pv > @as(i64, @intCast(arity))) return error.Badarg; // never keypos 1
    return .{ .pos = @intCast(pv), .val = FinalTerms.tupleElem(&m.ctx, spec, 1) };
}

/// `ets:update_element(Tab, Key, {Pos,Val} | [{Pos,Val}])` — set/ordered_set
/// only (bag → badarg). Returns `true` if the key exists (and updates it),
/// `false` if absent. All specs validated BEFORE any mutation (all-or-nothing).
fn updateElement(m: *Machine, t: *EtsTable, key: Term, spec_arg: Term) BifError!Term {
    if (t.ty == .bag or t.ty == .duplicate_bag) return error.Badarg; // set/ordered_set only
    var cur: std.ArrayList(Term) = .empty;
    defer cur.deinit(m.gpa);
    try bLookup(m, t, key, &cur);
    if (cur.items.len == 0) return boolTerm(m, false);
    var obj = cur.items[0];
    const arity = FinalTerms.tupleArity(&m.ctx, obj);
    // Collect specs (a single {Pos,Val} tuple or a proper list of them).
    var specs: std.ArrayList(Term) = .empty;
    defer specs.deinit(m.gpa);
    switch (FinalTerms.kindOf(&m.ctx, spec_arg)) {
        .tuple => specs.append(m.gpa, spec_arg) catch return error.OutOfMemory,
        .cons, .nil => {
            var c = spec_arg;
            while (FinalTerms.kindOf(&m.ctx, c) == .cons) {
                specs.append(m.gpa, FinalTerms.listHead(&m.ctx, c)) catch return error.OutOfMemory;
                c = FinalTerms.listTail(&m.ctx, c);
            }
            if (FinalTerms.kindOf(&m.ctx, c) != .nil) return error.Badarg; // improper
        },
        else => return error.Badarg,
    }
    // Apply each validated spec onto a running copy.
    for (specs.items) |s| {
        const p = try parseElemSpec(m, s, arity);
        obj = try withElement(m, obj, p.pos, p.val);
    }
    try bDelete(m, t, key);
    try bInsert(m, t, obj);
    return boolTerm(m, true);
}

pub fn update_element_3(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    return updateElement(m, t, args[1], args[2]);
}
/// `/4` accepts (and ignores) an `{no_return, on_error}`-style options tuple —
/// no supported option changes the success semantics here.
pub fn update_element_4(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    return updateElement(m, t, args[1], args[2]);
}

// ── E31-T2: ets:update_counter/3,4 (erl_db.c db_do_update_counter) ───────────
//
// ## The increment-op grammar (byte-EQ vs erl_db.c `do_update_counter`)
//   UpdateOp = Incr                                (bare integer)
//            | {Pos, Incr}
//            | {Pos, Incr, Threshold, SetValue}    (saturating)
//            | [UpdateOp']  where UpdateOp' is a 2- or 4-tuple (NOT a bare int)
// A bare integer `Incr` is `{keypos+1, Incr}` — keypos is always 1 here, so the
// default position is 2 (the canonical `{Key,Count}` counter idiom). A single
// integer/tuple UpdateOp returns the ONE new counter value; a list returns the
// LIST of new values (one per op, applied left-to-right to the SAME running
// object — later ops see earlier ops' mutations). `[]` returns `[]`.
//
// ## Saturation (exact erl_db.c order): compute `new = current + Incr`; if
// `Incr >= 0` and `new > Threshold` → `new = SetValue`; if `Incr < 0` and
// `new < Threshold` → `new = SetValue`. The stored AND returned value is `new`.
//
// ## /3 vs /4 on a MISSING key: /3 → badarg; /4 inserts the Default object with
// its keypos element replaced by Key (erl_db.c `db_do_update_counter`'s
// default-object path), then applies the ops to it. Default must be a tuple of
// arity ≥ keypos; when the key EXISTS the Default is ignored (never validated).
//
// ## Rejection (all → clean `error.Badarg`, ATOMIC — no mutation on any badarg,
// mirroring erl_db.c which computes on a working copy and inserts once):
//   * table type not set/ordered_set (bag/duplicate_bag counters are ambiguous)
//   * Pos not a small integer, Pos < 1, Pos == keypos(1), or Pos > object arity
//   * the element at Pos is not an integer; Incr/Threshold/SetValue not integers
//   * a list element that is not a 2-/4-tuple; an improper list; a malformed op
//
// ## Integer domain: uses `FinalTerms.add` (full-bignum limb path) + numeric
// `compare` — EXACT over the VM's whole integer range (bignum ≤ 512 bits, the
// documented VM-wide arithmetic bound shared with erlang:'+'; results beyond it
// diverge identically to every other arithmetic BIF — no NEW divergence here).

const CounterOp = struct { pos: usize, incr: Term, thres: ?Term, setval: ?Term };

/// Is `t` an integer term (small or bignum)? Counters and their operands must be.
fn isInt(m: *Machine, t: Term) bool {
    return FinalTerms.repIsSmall(t) or FinalTerms.repIsBig(&m.ctx, t);
}

/// `current + incr` over the VM's integer domain (bignum-exact via limb add).
/// A non-integer operand cannot reach here (the family validates first), so a
/// `Badarith` (finite-only float guard) is mapped to the family-uniform badarg.
fn addInt(m: *Machine, x: Term, y: Term) BifError!Term {
    return FinalTerms.add(&m.ctx, x, y) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        error.Badarith => error.Badarg,
    };
}

/// Parse ONE update-op tuple (arity 2 `{Pos,Incr}` or 4 `{Pos,Incr,Thr,Set}`),
/// validating Pos against the working object's `arity`. keypos is 1, so a valid
/// Pos is a small in `[2, arity]` (never the key position). Every integer field
/// is integer-checked. Any deviation → badarg.
fn parseCounterOp(m: *Machine, spec: Term, arity: usize) BifError!CounterOp {
    if (FinalTerms.kindOf(&m.ctx, spec) != .tuple) return error.Badarg;
    const ar = FinalTerms.tupleArity(&m.ctx, spec);
    if (ar != 2 and ar != 4) return error.Badarg;
    const pt = FinalTerms.tupleElem(&m.ctx, spec, 0);
    if (!FinalTerms.repIsSmall(pt)) return error.Badarg;
    const pv = FinalTerms.smallValOf(pt);
    if (pv < 2 or pv > @as(i64, @intCast(arity))) return error.Badarg; // <2 covers Pos<1 and Pos==keypos(1)
    const incr = FinalTerms.tupleElem(&m.ctx, spec, 1);
    if (!isInt(m, incr)) return error.Badarg;
    if (ar == 2) return .{ .pos = @intCast(pv), .incr = incr, .thres = null, .setval = null };
    const thres = FinalTerms.tupleElem(&m.ctx, spec, 2);
    const setval = FinalTerms.tupleElem(&m.ctx, spec, 3);
    if (!isInt(m, thres) or !isInt(m, setval)) return error.Badarg;
    return .{ .pos = @intCast(pv), .incr = incr, .thres = thres, .setval = setval };
}

/// Parse the whole UpdateOp arg into `out`, returning whether it was a LIST form
/// (so the result is a list of values, not a single value). A bare integer is
/// the `{keypos+1, Incr}` op; a bare 2-/4-tuple is a single op; a proper list of
/// such tuples is the list form; `[]` is the empty list form.
fn parseCounterOps(m: *Machine, alloc: std.mem.Allocator, arg: Term, arity: usize, out: *std.ArrayList(CounterOp)) BifError!bool {
    if (isInt(m, arg)) {
        // bare Incr == {keypos+1, Incr}; keypos is 1 so Pos is 2 (needs arity ≥ 2).
        if (2 > @as(i64, @intCast(arity))) return error.Badarg;
        out.append(alloc, .{ .pos = 2, .incr = arg, .thres = null, .setval = null }) catch return error.OutOfMemory;
        return false;
    }
    switch (FinalTerms.kindOf(&m.ctx, arg)) {
        .tuple => {
            out.append(alloc, try parseCounterOp(m, arg, arity)) catch return error.OutOfMemory;
            return false;
        },
        .nil => return true, // [] — empty list form
        .cons => {
            var cur = arg;
            while (FinalTerms.kindOf(&m.ctx, cur) == .cons) : (cur = FinalTerms.listTail(&m.ctx, cur)) {
                const h = FinalTerms.listHead(&m.ctx, cur);
                out.append(alloc, try parseCounterOp(m, h, arity)) catch return error.OutOfMemory;
            }
            if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg; // improper list
            return true;
        },
        else => return error.Badarg,
    }
}

/// The shared /3,/4 core. `default_obj` is `null` for /3, the Default tuple for
/// /4. Set/ordered_set only. Fully validates + computes on a working copy, then
/// performs a SINGLE insert (atomic: any badarg leaves the table untouched).
fn updateCounter(m: *Machine, t: *EtsTable, key: Term, arg: Term, default_obj: ?Term) BifError!Term {
    if (t.ty != .set and t.ty != .ordered_set) return error.Badarg;

    // gap-ets-op-cost: a STACK-FALLBACK allocator for the per-call scratch.
    //
    // Incrementing one integer used to make four heap allocations — the lookup
    // result list, the parsed op list, the per-op result list, and the probe
    // list inside `bLookup`. Under an arena that is ~850ns; under the
    // safety-instrumented allocator the real binary runs, the SAME operations
    // cost ~53,000ns, because a leak-tracking allocator captures a stack trace
    // per allocation (DIVERGENCE 778). The allocator, not ETS, is the dominant
    // term, so the win is in not calling it.
    //
    // 1 KiB covers the overwhelmingly common shapes (a bare `Incr`, or a short
    // op list on a small tuple) without touching the heap at all; anything
    // larger falls back to `m.gpa` and behaves exactly as before. Semantics are
    // unchanged by construction — `stackFallback` IS an allocator, so every
    // list still grows, still bounds-checks, and still frees.
    var sfa = std.heap.stackFallback(1024, m.gpa);
    const scratch = sfa.get();

    // Find the working object, or synthesise it from the /4 Default.
    var cur: std.ArrayList(Term) = .empty;
    defer cur.deinit(m.gpa);
    try bLookup(m, t, key, &cur);
    var obj: Term = undefined;
    if (cur.items.len != 0) {
        obj = cur.items[0];
    } else {
        const d = default_obj orelse return error.Badarg; // /3 on a missing key
        if (FinalTerms.kindOf(&m.ctx, d) != .tuple or FinalTerms.tupleArity(&m.ctx, d) < 1) return error.Badarg;
        obj = try withElement(m, d, 1, key); // keypos(1) element := Key
    }
    const arity = FinalTerms.tupleArity(&m.ctx, obj);

    // Parse (and fully validate) every op before any mutation.
    var ops: std.ArrayList(CounterOp) = .empty;
    defer ops.deinit(scratch);
    const is_list = try parseCounterOps(m, scratch, arg, arity, &ops);

    // Apply left-to-right on the running object, collecting per-op results.
    const zero = FinalTerms.int(&m.ctx, 0);
    var results: std.ArrayList(Term) = .empty;
    defer results.deinit(scratch);
    for (ops.items) |op| {
        const current = FinalTerms.tupleElem(&m.ctx, obj, op.pos - 1);
        if (!isInt(m, current)) return error.Badarg; // element at Pos must be an integer
        var nv = try addInt(m, current, op.incr);
        if (op.thres) |th| {
            const sv = op.setval.?;
            const incr_neg = FinalTerms.compare(&m.ctx, op.incr, zero) == .lt;
            if (!incr_neg) {
                if (FinalTerms.compare(&m.ctx, nv, th) == .gt) nv = sv; // Incr≥0 & new>Threshold
            } else {
                if (FinalTerms.compare(&m.ctx, nv, th) == .lt) nv = sv; // Incr<0 & new<Threshold
            }
        }
        obj = try withElement(m, obj, op.pos, nv);
        results.append(scratch, nv) catch return error.OutOfMemory;
    }

    // Single atomic write-back (set replaces the same-key object; /4 inserts new).
    try bInsert(m, t, obj);

    if (is_list) return listOf(m, results.items);
    return results.items[0]; // a single (non-list) op always yields exactly one value
}

pub fn update_counter_3(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    return updateCounter(m, t, args[1], args[2], null);
}
pub fn update_counter_4(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    return updateCounter(m, t, args[1], args[2], args[3]);
}

/// `{Key, Objects}` for the *_lookup traversal variants, or `$end_of_table`.
fn keyLookupResult(m: *Machine, t: *EtsTable, key: Term) BifError!Term {
    var out: std.ArrayList(Term) = .empty;
    defer out.deinit(m.gpa);
    try bLookup(m, t, key, &out);
    const objs = try listOf(m, out.items);
    return FinalTerms.tuple(&m.ctx, &.{ key, objs }) catch error.OutOfMemory;
}

pub fn first_lookup_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    if (objs.items.len == 0) return endOfTable(m);
    return keyLookupResult(m, t, keyOf(m, objs.items[0]));
}
pub fn last_lookup_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    if (objs.items.len == 0) return endOfTable(m);
    return keyLookupResult(m, t, keyOf(m, objs.items[objs.items.len - 1]));
}
pub fn next_lookup_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    for (objs.items) |o| {
        const ok = keyOf(m, o);
        if (cmpKeys(m, t.ty, ok, args[1]) == .gt) return keyLookupResult(m, t, ok);
    }
    return endOfTable(m);
}
pub fn prev_lookup_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    var i = objs.items.len;
    while (i > 0) {
        i -= 1;
        const ok = keyOf(m, objs.items[i]);
        if (cmpKeys(m, t.ty, ok, args[1]) == .lt) return keyLookupResult(m, t, ok);
    }
    return endOfTable(m);
}

/// `ets:safe_fixtable(Tab, true|false)` — a SINGLE-PROCESS no-op returning
/// `true`. Fixation only affects concurrent traversal-vs-delete visibility,
/// which this single-Machine VM has no way to observe (no other process can
/// mutate the table mid-traversal), so fixing/unfixing has no observable effect
/// — the honest single-process shadow. A bad Tid or non-boolean flag → badarg.
pub fn safe_fixtable_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    _ = t;
    const flag = args[1];
    if (!FinalTerms.repIsAtom(flag) or !(atomEq(m, flag, "true") or atomEq(m, flag, "false"))) return error.Badarg;
    return boolTerm(m, true);
}

// ── E3.15: the match/select family (matchspec.zig compiler over the backend) ─
//
// A runtime matchspec-TERM compiler (`matchspec.zig`, S23) driven over the live
// `TreeBackend`. `match`/`match_object` are HEAD-pattern filters; `select*` run
// full compiled match specs; `select_count`/`internal_select_delete` use the
// `[true]`-predicate compiler; `select_replace` verifies key-preservation. NO
// matching semantics live here — every match is `pat.match`/`matchspec.run`.
//
// ## Continuation & compiled-ms REPRESENTATION (documented divergence)
// erts continuations / compiled match specs are opaque magic terms this VM has
// no analog for. `select/3` returns `{Chunk, {'$zigvm_ms_cont', Rest, Limit}}`
// (the not-yet-returned results embedded — the single-process SNAPSHOT shadow of
// erts's live continuation, sound because no concurrent process can mutate the
// table mid-traversal, exactly `safe_fixtable`'s justification); `select/1`
// re-chunks it. `match_spec_compile/1` returns `{'$zigvm_compiled_ms', MSTerm}`;
// `is_compiled_ms/1` tests that tag; `match_spec_run_r/3` recompiles + runs it.
// A user-forged tuple with the same tag would fool `is_compiled_ms` — a bounded
// divergence (erts uses a magic ref), recorded as an extension of entry 13(b).

const cont_tag = "$zigvm_ms_cont";
const compiled_ms_tag = "$zigvm_compiled_ms";

/// A compiled match spec: value-body, or a `[true]` predicate. Compiled in a
/// per-call arena; the clauses hold Term VALUES (realloc-safe).
const Form = union(enum) {
    value: []const msc.MatchSpec,
    predicate: []const msc.MatchSpec,
};

/// Compile a match-spec term as a value spec, falling back to a predicate
/// (`[true]` body). Neither -> badarg (the rejection law).
fn compileForm(m: *Machine, arena: std.mem.Allocator, ms_term: Term) BifError!Form {
    if (msc.compile(&m.ctx, arena, ms_term)) |c| {
        return .{ .value = c };
    } else |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadSpec => {},
    }
    if (msc.compilePredicate(&m.ctx, arena, ms_term)) |c| {
        return .{ .predicate = c };
    } else |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadSpec => return error.Badarg,
    }
}

/// Run a compiled form on one object: the body term, or null on no match
/// (a predicate form yields the atom `true` for a match).
fn runForm(m: *Machine, form: Form, obj: Term) BifError!?Term {
    switch (form) {
        .value => |c| return msc.runMulti(&m.ctx, c, obj) catch return error.OutOfMemory,
        .predicate => |c| {
            const r = msc.runMulti(&m.ctx, c, obj) catch return error.OutOfMemory;
            return if (r != null) try internAtom(m, "true") else null;
        },
    }
}

/// The dumped objects of `t`, ascending key order, reversed if `reverse`.
fn dumpDir(m: *Machine, t: *EtsTable, reverse: bool) BifError!std.ArrayList(Term) {
    const objs = try dumpObjects(m, t);
    if (reverse) std.mem.reverse(Term, objs.items);
    return objs;
}

/// A positive-integer limit (>=1), else badarg.
fn posLimit(t: Term) BifError!usize {
    if (!FinalTerms.repIsSmall(t)) return error.Badarg;
    const v = FinalTerms.smallValOf(t);
    if (v < 1) return error.Badarg;
    return @intCast(v);
}

/// Remove the ONE stored object exact-equal to `obj` (leaving same-key others).
/// Reuses lookup/delete/insert — no new backend op.
fn removeExact(m: *Machine, t: *EtsTable, obj: Term) BifError!void {
    const key = keyOf(m, obj);
    var run: std.ArrayList(Term) = .empty;
    defer run.deinit(m.gpa);
    try bLookup(m, t, key, &run);
    try bDelete(m, t, key);
    for (run.items) |o| {
        if (!FinalTerms.eqlExact(&m.ctx, o, obj)) {
            try bInsert(m, t, o);
        }
    }
}

/// `{Chunk, {'$zigvm_ms_cont', Rest, Limit}}`, or `$end_of_table` when `all`
/// is empty.
fn chunkResult(m: *Machine, all: []const Term, limit: usize) BifError!Term {
    if (all.len == 0) return endOfTable(m);
    const take = @min(limit, all.len);
    const chunk = try listOf(m, all[0..take]);
    const rest = try listOf(m, all[take..]);
    const tag = try internAtom(m, cont_tag);
    const cont = FinalTerms.tuple(&m.ctx, &.{ tag, rest, FinalTerms.int(&m.ctx, @intCast(limit)) }) catch return error.OutOfMemory;
    return FinalTerms.tuple(&m.ctx, &.{ chunk, cont }) catch error.OutOfMemory;
}

/// `select_2` core: every body result over the table, in (reverse?) key order.
fn selectResults(m: *Machine, t: *EtsTable, ms_term: Term, reverse: bool) BifError!std.ArrayList(Term) {
    var arena = std.heap.ArenaAllocator.init(m.gpa);
    defer arena.deinit();
    const form = try compileForm(m, arena.allocator(), ms_term);
    var objs = try dumpDir(m, t, reverse);
    defer objs.deinit(m.gpa);
    var out: std.ArrayList(Term) = .empty;
    errdefer out.deinit(m.gpa);
    for (objs.items) |o| {
        if (try runForm(m, form, o)) |val| out.append(m.gpa, val) catch return error.OutOfMemory;
    }
    return out;
}

pub fn select_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var res = try selectResults(m, t, args[1], false);
    defer res.deinit(m.gpa);
    return listOf(m, res.items);
}
pub fn select_3(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    const limit = try posLimit(args[2]);
    var res = try selectResults(m, t, args[1], false);
    defer res.deinit(m.gpa);
    return chunkResult(m, res.items, limit);
}
pub fn select_reverse_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var res = try selectResults(m, t, args[1], true);
    defer res.deinit(m.gpa);
    return listOf(m, res.items);
}
pub fn select_reverse_3(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    const limit = try posLimit(args[2]);
    var res = try selectResults(m, t, args[1], true);
    defer res.deinit(m.gpa);
    return chunkResult(m, res.items, limit);
}

fn isMsCont(m: *Machine, t: Term) bool {
    return FinalTerms.kindOf(&m.ctx, t) == .tuple and FinalTerms.tupleArity(&m.ctx, t) == 3 and
        atomEq(m, FinalTerms.tupleElem(&m.ctx, t, 0), cont_tag);
}

/// `select/1` (and `match/1`, `match_object/1`, `select_reverse/1` — they share
/// this snapshot-continuation): re-chunk the embedded rest.
pub fn select_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const cont = args[0];
    if (!isMsCont(m, cont)) return error.Badarg;
    const limit = try posLimit(FinalTerms.tupleElem(&m.ctx, cont, 2));
    var rest: std.ArrayList(Term) = .empty;
    defer rest.deinit(m.gpa);
    var cur = FinalTerms.tupleElem(&m.ctx, cont, 1);
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) : (cur = FinalTerms.listTail(&m.ctx, cur)) {
        rest.append(m.gpa, FinalTerms.listHead(&m.ctx, cur)) catch return error.OutOfMemory;
    }
    return chunkResult(m, rest.items, limit);
}

/// Compile a head pattern; per matching object collect either the whole object
/// (`match_object`) or the `'$$'` bindings-list (`match`). m.gpa-owned.
fn matchResults(m: *Machine, t: *EtsTable, pattern_term: Term, want_object: bool) BifError!std.ArrayList(Term) {
    var arena = std.heap.ArenaAllocator.init(m.gpa);
    defer arena.deinit();
    const hs = msc.compileHead(&m.ctx, arena.allocator(), pattern_term) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadSpec => return error.Badarg,
    };
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    var out: std.ArrayList(Term) = .empty;
    errdefer out.deinit(m.gpa);
    for (objs.items) |o| {
        var b = pat.Bindings(FinalTerms){};
        if (!pat.match(FinalTerms, &m.ctx, hs.head, o, &b)) continue;
        if (want_object) {
            out.append(m.gpa, o) catch return error.OutOfMemory;
        } else {
            var elems: std.ArrayList(Term) = .empty;
            defer elems.deinit(m.gpa);
            for (hs.used) |slot| elems.append(m.gpa, b.slots[slot].?) catch return error.OutOfMemory;
            out.append(m.gpa, try listOf(m, elems.items)) catch return error.OutOfMemory;
        }
    }
    return out;
}

pub fn match_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var res = try matchResults(m, t, args[1], false);
    defer res.deinit(m.gpa);
    return listOf(m, res.items);
}
pub fn match_3(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    const limit = try posLimit(args[2]);
    var res = try matchResults(m, t, args[1], false);
    defer res.deinit(m.gpa);
    return chunkResult(m, res.items, limit);
}
pub fn match_object_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var res = try matchResults(m, t, args[1], true);
    defer res.deinit(m.gpa);
    return listOf(m, res.items);
}
pub fn match_object_3(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    const limit = try posLimit(args[2]);
    var res = try matchResults(m, t, args[1], true);
    defer res.deinit(m.gpa);
    return chunkResult(m, res.items, limit);
}

pub fn select_count_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var arena = std.heap.ArenaAllocator.init(m.gpa);
    defer arena.deinit();
    const clauses = msc.compilePredicate(&m.ctx, arena.allocator(), args[1]) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadSpec => return error.Badarg,
    };
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    var count: i64 = 0;
    for (objs.items) |o| {
        if ((msc.runMulti(&m.ctx, clauses, o) catch return error.OutOfMemory) != null) count += 1;
    }
    return FinalTerms.int(&m.ctx, count);
}

/// `ets:internal_select_delete(Tab, MatchSpec)` — delete every matched object,
/// return the count DELETED. The count MUST equal the number actually removed
/// (mutant 2's target).
pub fn internal_select_delete_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var arena = std.heap.ArenaAllocator.init(m.gpa);
    defer arena.deinit();
    const clauses = msc.compilePredicate(&m.ctx, arena.allocator(), args[1]) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadSpec => return error.Badarg,
    };
    // Snapshot matches FIRST (mutating mid-dump would skip rows), then remove.
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    var matched: std.ArrayList(Term) = .empty;
    defer matched.deinit(m.gpa);
    for (objs.items) |o| {
        if ((msc.runMulti(&m.ctx, clauses, o) catch return error.OutOfMemory) != null)
            matched.append(m.gpa, o) catch return error.OutOfMemory;
    }
    for (matched.items) |o| try removeExact(m, t, o);
    return FinalTerms.int(&m.ctx, @intCast(matched.items.len));
}

/// `ets:internal_delete_all(Tab, undefined)` — clear all objects, return the
/// count removed (the primitive under `ets:delete_all_objects/1`).
pub fn internal_delete_all_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    if (!atomEq(m, args[1], "undefined")) return error.Badarg;
    const n = t.backend.size();
    t.backend.deinit();
    t.backend = ea.TreeBackend.init(m.gpa, t.ty);
    return FinalTerms.int(&m.ctx, @intCast(n));
}

/// `ets:select_replace(Tab, MatchSpec)` — replace each matched object with the
/// body result, which MUST keep the same key (erts badargs otherwise). Returns
/// the count replaced.
pub fn select_replace_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var arena = std.heap.ArenaAllocator.init(m.gpa);
    defer arena.deinit();
    const clauses = msc.compile(&m.ctx, arena.allocator(), args[1]) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadSpec => return error.Badarg,
    };
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    var olds: std.ArrayList(Term) = .empty;
    defer olds.deinit(m.gpa);
    var news: std.ArrayList(Term) = .empty;
    defer news.deinit(m.gpa);
    for (objs.items) |o| {
        if (msc.runMulti(&m.ctx, clauses, o) catch return error.OutOfMemory) |nw| {
            if (FinalTerms.kindOf(&m.ctx, nw) != .tuple or FinalTerms.tupleArity(&m.ctx, nw) < 1) return error.Badarg;
            if (!sameKey(m, t.ty, keyOf(m, nw), keyOf(m, o))) return error.Badarg;
            olds.append(m.gpa, o) catch return error.OutOfMemory;
            news.append(m.gpa, nw) catch return error.OutOfMemory;
        }
    }
    for (olds.items, news.items) |o, nw| {
        try removeExact(m, t, o);
        try bInsert(m, t, nw);
    }
    return FinalTerms.int(&m.ctx, @intCast(olds.items.len));
}

pub fn is_compiled_ms_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = args[0];
    const ok = FinalTerms.kindOf(&m.ctx, t) == .tuple and FinalTerms.tupleArity(&m.ctx, t) == 2 and
        atomEq(m, FinalTerms.tupleElem(&m.ctx, t, 0), compiled_ms_tag);
    return boolTerm(m, ok);
}

pub fn match_spec_compile_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    var arena = std.heap.ArenaAllocator.init(m.gpa);
    defer arena.deinit();
    _ = try compileForm(m, arena.allocator(), args[0]); // validate (badarg on a bad spec)
    const tag = try internAtom(m, compiled_ms_tag);
    return FinalTerms.tuple(&m.ctx, &.{ tag, args[0] }) catch error.OutOfMemory;
}

/// `erlang:match_spec_run_r(List, CompiledMS, Tail)` — prepend each match's
/// body to Tail front-to-back (so the caller's `lists:reverse` yields input
/// order). Non-matching elements skipped.
pub fn match_spec_run_r_3(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const cms = args[1];
    if (!(FinalTerms.kindOf(&m.ctx, cms) == .tuple and FinalTerms.tupleArity(&m.ctx, cms) == 2 and
        atomEq(m, FinalTerms.tupleElem(&m.ctx, cms, 0), compiled_ms_tag))) return error.Badarg;
    var arena = std.heap.ArenaAllocator.init(m.gpa);
    defer arena.deinit();
    const form = try compileForm(m, arena.allocator(), FinalTerms.tupleElem(&m.ctx, cms, 1));
    var acc = args[2];
    var cur = args[0];
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) : (cur = FinalTerms.listTail(&m.ctx, cur)) {
        if (try runForm(m, form, FinalTerms.listHead(&m.ctx, cur))) |val|
            acc = FinalTerms.cons(&m.ctx, val, acc) catch return error.OutOfMemory;
    }
    if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg;
    return acc;
}

fn charlist(m: *Machine, s: []const u8) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = s.len;
    while (i > 0) {
        i -= 1;
        acc = FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, s[i]), acc) catch return error.OutOfMemory;
    }
    return acc;
}

/// `erlang:match_spec_test(Object, MatchSpec, Type)` — the `table` tester
/// (`ets:test_ms`'s primitive). Returns erts's `{ok, Result, Flags, Warnings}`
/// (`Result` = the body, or `false` on no match; Flags/Warnings `[]`), or
/// `{error, Errors}` on a malformed spec. `trace` type is bounded -> badarg.
pub fn match_spec_test_3(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    // `trace` type: the object is a call's ARGUMENT LIST; the body runs the
    // trace-action functions ({message,_}/{return_trace}/{exception_trace} + value
    // exprs). Returns {ok, Result, Flags, []} | {error, [{error, _}]} (E-shared).
    if (atomEq(m, args[2], "trace")) return matchSpecTestTrace(m, args[0], args[1]);
    if (!atomEq(m, args[2], "table")) return error.Badarg;
    var arena = std.heap.ArenaAllocator.init(m.gpa);
    defer arena.deinit();
    const form = compileForm(m, arena.allocator(), args[1]) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            // Malformed spec is a RESULT, not a raise: {error, [{error, Str}]}.
            const errtag = try internAtom(m, "error");
            const inner = FinalTerms.tuple(&m.ctx, &.{ errtag, try charlist(m, "invalid matchspec") }) catch return error.OutOfMemory;
            const errs = try listOf(m, &.{inner});
            return FinalTerms.tuple(&m.ctx, &.{ errtag, errs }) catch error.OutOfMemory;
        },
    };
    const result = (try runForm(m, form, args[0])) orelse boolTerm(m, false);
    const empty = FinalTerms.nil(&m.ctx);
    return FinalTerms.tuple(&m.ctx, &.{ try internAtom(m, "ok"), result, empty, empty }) catch error.OutOfMemory;
}

/// `match_spec_test(ArgList, MatchSpec, trace)` — run the trace-body ACTION
/// functions and return `{ok, Result, Flags, []}` (Result = the body value,
/// `false` on no match; Flags = `[return_trace?, exception_trace?]`), or
/// `{error, [{error, _}]}` on a malformed spec (a RESULT, never a raise).
fn matchSpecTestTrace(m: *Machine, obj: Term, ms_term: Term) BifError!Term {
    var arena = std.heap.ArenaAllocator.init(m.gpa);
    defer arena.deinit();
    const clauses = msc.compileTrace(&m.ctx, arena.allocator(), ms_term) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadSpec => {
            const errtag = try internAtom(m, "error");
            const inner = FinalTerms.tuple(&m.ctx, &.{ errtag, try charlist(m, "invalid matchspec") }) catch return error.OutOfMemory;
            const errs = try listOf(m, &.{inner});
            return FinalTerms.tuple(&m.ctx, &.{ errtag, errs }) catch error.OutOfMemory;
        },
    };
    const empty = FinalTerms.nil(&m.ctx);
    const maybe = msc.runTrace(&m.ctx, clauses, obj) catch return error.OutOfMemory;
    var result = boolTerm(m, false);
    var flags = empty;
    if (maybe) |tr| {
        result = tr.result;
        // Flags in the canonical return_trace-before-exception_trace order.
        var fl: std.ArrayList(Term) = .empty;
        defer fl.deinit(m.gpa);
        if (tr.return_trace) fl.append(m.gpa, try internAtom(m, "return_trace")) catch return error.OutOfMemory;
        if (tr.exception_trace) fl.append(m.gpa, try internAtom(m, "exception_trace")) catch return error.OutOfMemory;
        flags = try listOf(m, fl.items);
    }
    return FinalTerms.tuple(&m.ctx, &.{ try internAtom(m, "ok"), result, flags, empty }) catch error.OutOfMemory;
}

// ── ets:info/1, ets:info/2 (a documented SUBSET of BEAM's fields) ───────────

fn typeAtom(m: *Machine, ty: TableType) BifError!Term {
    return internAtom(m, switch (ty) {
        .set => "set",
        .ordered_set => "ordered_set",
        .bag => "bag",
        .duplicate_bag => "duplicate_bag",
    });
}

fn tidTerm(m: *Machine, t: *EtsTable) Term {
    return if (t.named) FinalTerms.atom(&m.ctx, t.name) else FinalTerms.int(&m.ctx, @intCast(t.id));
}

pub fn info_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    const pairs = [_]struct { k: []const u8, v: Term }{
        .{ .k = "id", .v = tidTerm(m, t) },
        .{ .k = "name", .v = FinalTerms.atom(&m.ctx, t.name) },
        .{ .k = "size", .v = FinalTerms.int(&m.ctx, @intCast(t.backend.size())) },
        .{ .k = "type", .v = try typeAtom(m, t.ty) },
        .{ .k = "keypos", .v = FinalTerms.int(&m.ctx, @intCast(t.keypos)) },
        .{ .k = "named_table", .v = boolTerm(m, t.named) },
        .{ .k = "protection", .v = try internAtom(m, @tagName(t.opts.protection)) },
        // E6.7: `owner`/`heir` are exposed via info/2 (the corpus + law path); info/1
        // stays the documented 7-field SUBSET (the REJECTION law counts it).
    };
    var items: std.ArrayList(Term) = .empty;
    defer items.deinit(m.gpa);
    for (pairs) |p| {
        const kt = try internAtom(m, p.k);
        const tup = FinalTerms.tuple(&m.ctx, &.{ kt, p.v }) catch return error.OutOfMemory;
        items.append(m.gpa, tup) catch return error.OutOfMemory;
    }
    return listOf(m, items.items);
}

pub fn info_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    const item = args[1];
    if (atomEq(m, item, "size")) return FinalTerms.int(&m.ctx, @intCast(t.backend.size()));
    if (atomEq(m, item, "type")) return typeAtom(m, t.ty);
    if (atomEq(m, item, "named_table")) return boolTerm(m, t.named);
    if (atomEq(m, item, "name")) return FinalTerms.atom(&m.ctx, t.name);
    if (atomEq(m, item, "keypos")) return FinalTerms.int(&m.ctx, @intCast(t.keypos));
    if (atomEq(m, item, "id")) return tidTerm(m, t);
    // gap-ets-table-options. `protection` used to be a hardcoded "protected",
    // which was truthful only while nothing else could be declared — the same
    // rotted-constant shape as `process_info(P, priority)`. The four keys below
    // it were absent entirely and badarg'd against real OTP-30 values.
    if (atomEq(m, item, "protection")) return internAtom(m, @tagName(t.opts.protection));
    if (atomEq(m, item, "read_concurrency")) return boolTerm(m, t.opts.read_concurrency);
    if (atomEq(m, item, "write_concurrency")) return switch (t.opts.write_concurrency) {
        .off => boolTerm(m, false),
        .on => boolTerm(m, true),
        .auto => internAtom(m, "auto"),
    };
    if (atomEq(m, item, "decentralized_counters"))
        return boolTerm(m, t.opts.decentralizedCounters(t.ty));
    if (atomEq(m, item, "compressed")) return boolTerm(m, t.opts.compressed);
    // E6.7: the multi-process ownership items.
    if (atomEq(m, item, "owner")) return FinalTerms.pid(&m.ctx, t.owner, 0) catch error.OutOfMemory;
    if (atomEq(m, item, "heir")) {
        if (t.heir == 0) return internAtom(m, "none");
        return FinalTerms.pid(&m.ctx, t.heir, 0) catch error.OutOfMemory;
    }
    // DIVERGENCE 691: `ets:info(Tab, memory)` — a size-derived WORD estimate for
    // zigvm's ETS representation. erts returns an impl-specific word count tied to
    // its slot/tuple heap layout; zigvm's storage model differs, so this is
    // REPR-COUPLED (EQUIV, NOT byte-EQ to erts — the flat_size/word-count family)
    // rather than a fabricated constant: a MONOTONE function of the live object
    // count (a fixed empty-table overhead + a per-object word cost), truthful for
    // zigvm's own representation. This unblocks `digraph_utils:subgraph/2,3` and
    // `digraph_utils:condensation/1`, which SUM `ets:info(VT, memory)` across the
    // graph's vertex/edge tables and only require an integer.
    if (atomEq(m, item, "memory")) {
        const base_words: i64 = 305; // empty-table struct overhead (zigvm model)
        const per_object_words: i64 = 6; // key+value term + slot bookkeeping
        const n: i64 = @intCast(t.backend.size());
        return FinalTerms.int(&m.ctx, base_words + per_object_words * n);
    }
    // the remaining stats items (compressed/… ) need the heap-accounting model — deferred.
    return error.Badarg;
}

// ── ets:rename/2 — a pure NAME-REGISTRY remap (E5.9) ────────────────────────

/// `ets:rename(Tab, NewName)` rebinds the table's name (and, for a `named_table`,
/// the by-name registry) to the atom `NewName`, then returns `NewName`. The
/// objects are UNTOUCHED — a denotation-preserving remap (see
/// `ets_algebra.EtsRegistry.rename`). `NewName` must be an atom; a collision
/// with a DIFFERENT live named table is `badarg`. This is the single row that
/// left the `deferred-E5-ets-tidrep` bucket at E5.9 (unlike `whereis/1`/`slot/2`
/// it needs no ref-Tid / hash-slot machinery — the single-Machine name registry
/// already models it exactly).
pub fn rename_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    if (!FinalTerms.repIsAtom(args[1])) return error.Badarg;
    const new_name = FinalTerms.atomIdxOf(args[1]);
    try m.etsReg().rename(t.id, new_name);
    return args[1]; // ets:rename/2 returns NewName
}

// ── E6.7: the multi-process ownership surface (give_away/setopts/whereis) ────

/// `ets:setopts(Tab, Opts)` — set the table's `{heir,Pid,Data}`/`{heir,none}`
/// (the death-heir) or `{protection,Level}` (accepted, unmodeled). `Opts` is a
/// single option tuple OR a proper list of them. Only the OWNER may setopts
/// (`badarg` otherwise — erts' owner restriction); a malformed option is
/// `badarg`. Returns `true`. Observationally: `ets:info(T,heir)` reads the set
/// heir back (the heir round-trip law).
pub fn setopts_2(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    if (t.owner != m.self_pid) return error.Badarg; // erts: only the owner sets opts
    if (FinalTerms.kindOf(&m.ctx, args[1]) == .tuple) {
        try applySetopt(m, t, args[1]);
    } else {
        var cur = args[1];
        while (FinalTerms.kindOf(&m.ctx, cur) == .cons) : (cur = FinalTerms.listTail(&m.ctx, cur)) {
            try applySetopt(m, t, FinalTerms.listHead(&m.ctx, cur));
        }
        if (FinalTerms.kindOf(&m.ctx, cur) != .nil) return error.Badarg; // improper list
    }
    return boolTerm(m, true);
}

fn applySetopt(m: *Machine, t: *EtsTable, opt: Term) BifError!void {
    if (FinalTerms.kindOf(&m.ctx, opt) != .tuple) return error.Badarg;
    const ar = FinalTerms.tupleArity(&m.ctx, opt);
    if (ar < 2) return error.Badarg;
    const tag = FinalTerms.tupleElem(&m.ctx, opt, 0);
    if (atomEq(m, tag, "heir")) {
        if (ar == 2) {
            // {heir, none}
            if (!atomEq(m, FinalTerms.tupleElem(&m.ctx, opt, 1), "none")) return error.Badarg;
            t.heir = 0;
            t.heir_data = null;
        } else if (ar == 3) {
            const hp = FinalTerms.tupleElem(&m.ctx, opt, 1);
            if (!FinalTerms.repIsPid(&m.ctx, hp)) return error.Badarg;
            t.heir = FinalTerms.pidNumber(&m.ctx, hp);
            // E7.3: copy heir_data into the shared `region` (see new_2).
            t.heir_data = try copyIn(m, FinalTerms.tupleElem(&m.ctx, opt, 2));
        } else return error.Badarg;
    } else if (atomEq(m, tag, "protection")) {
        if (ar != 2) return error.Badarg;
        // {protection, private|protected|public} — accepted, not modeled.
    } else return error.Badarg;
}

/// `ets:give_away(Tab, Pid, GiftData)` — transfer OWNERSHIP of `Tab` to the
/// live local process `Pid` and deliver `{'ETS-TRANSFER',Tab,From,GiftData}` to
/// it. The caller must be the current owner; `Pid` a live LOCAL process ≠ the
/// caller (erts' contract; else `badarg`). Aliveness + the signal delivery need
/// the Vm, so this TRAPS to `proc.zig` (the port precedent), which reassigns
/// `t.owner`, sends the transfer message, and writes `true`/`badarg` to x0.
pub fn give_away_3(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    m.pending = .{ .ets_give_away = .{ .tid = args[0], .to = args[1], .gift = args[2] } };
    return FinalTerms.nil(&m.ctx); // placeholder; proc.zig writes the real x0
}

/// `ets:whereis(Name)` — the table identifier bound to atom `Name`, or
/// `undefined`. On BEAM this is a ref-Tid; the single-Machine simplification
/// returns the SAME Tid every other ets BIF accepts (the name atom for a named
/// table). The end-to-end proof is representation-FREE: the Tid is never printed,
/// only round-tripped — `ets:lookup(ets:whereis(N),K) == ets:lookup(N,K)` — so
/// `whereis` leaves the `deferred-ets-tidrep` bucket (`slot/2` stays: it needs a
/// hash-bucket slot order the TreeBackend does not reproduce).
pub fn whereis_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    if (!FinalTerms.repIsAtom(args[0])) return error.Badarg;
    const t = m.etsReg().byName(FinalTerms.atomIdxOf(args[0])) orelse return internAtom(m, "undefined");
    return tidTerm(m, t);
}

// ── ets:tab2list/1, ets:delete_all_objects/1 (ets.erl wrappers) ──

/// `ets.erl`'s `tab2list/1` (a `select`-all over the table — not a bif.tab
/// entry itself, so wired via `resolveLibrary` at DIVERGENCE 719). Returns every
/// object in traversal order (key order for `ordered_set`).
pub fn tab2list_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    var objs = try dumpObjects(m, t);
    defer objs.deinit(m.gpa);
    return listOf(m, objs.items);
}

/// `ets.erl`'s `delete_all_objects/1` (wraps `ets:internal_delete_all/2` — not
/// a first-class bif.tab row, so NOT wired). Clears every object, keeps the
/// table: swap in a fresh empty backend.
pub fn delete_all_objects_1(m: *Machine, args: []const Term) BifError!Term {
    m.etsReg().lockShared();
    defer m.etsReg().unlockShared();
    const t = try resolveTable(m, args[0]);
    t.backend.deinit();
    t.backend = ea.TreeBackend.init(m.gpa, t.ty);
    return boolTerm(m, true);
}

// ============================================================================
// E2.9 LAWS
// ============================================================================

const AtomTable = ta.AtomTable;

fn mkTuple(m: *Machine, elems: []const Term) !Term {
    return FinalTerms.tuple(&m.ctx, elems);
}

fn newTable(m: *Machine, name: []const u8, opts: []const Term) !Term {
    const nm = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern(name));
    const optlist = try listOf(m, opts);
    return new_2(m, &.{ nm, optlist });
}

/// `ets:info(T, Key)` must equal `want`, and say WHICH key failed if not.
fn expectInfo(m: *Machine, tab: Term, key: []const u8, want: Term) !void {
    const got = try info_2(m, &.{ tab, try internAtom(m, key) });
    if (!FinalTerms.eqlExact(&m.ctx, got, want)) {
        std.debug.print("\ninfo/2 key '{s}' mismatch\n", .{key});
        return error.TestUnexpectedResult;
    }
}

/// Pull `Key` out of an `info/1` proplist. Absent is an error, not a default —
/// a missing key must not read as a passing comparison against `undefined`.
fn proplistGet(m: *Machine, list: Term, key: []const u8) !Term {
    const k = try internAtom(m, key);
    var cur = list;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) : (cur = FinalTerms.listTail(&m.ctx, cur)) {
        const pair = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.kindOf(&m.ctx, pair) == .tuple and FinalTerms.tupleArity(&m.ctx, pair) == 2 and
            FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, pair, 0), k))
            return FinalTerms.tupleElem(&m.ctx, pair, 1);
    }
    std.debug.print("\ninfo/1 proplist has no key '{s}'\n", .{key});
    return error.TestUnexpectedResult;
}

fn listLen(m: *Machine, l: Term) usize {
    var n: usize = 0;
    var cur = l;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) : (cur = FinalTerms.listTail(&m.ctx, cur)) n += 1;
    return n;
}

test "LAW E2.9 registry: insert then lookup round-trips; table is process-external (survives other tables' ops)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const t1 = try newTable(&m, "t1", &.{});
    const t2 = try newTable(&m, "t2", &.{});

    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    const obj = try mkTuple(&m, &.{ one, two });
    try std.testing.expect(FinalTerms.repIsAtom(try insert_2(&m, &.{ t1, obj }))); // true

    // Mutating t2 does not disturb t1's stored object (process-external state).
    _ = try insert_2(&m, &.{ t2, try mkTuple(&m, &.{ two, one }) });

    const got = try lookup_2(&m, &.{ t1, one });
    try std.testing.expectEqual(@as(usize, 1), listLen(&m, got));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, got), obj));

    // member/2 and lookup_element/3.
    try std.testing.expect(FinalTerms.atomIdxOf(try member_2(&m, &.{ t1, one })) == m.bool_true);
    try std.testing.expect(FinalTerms.atomIdxOf(try member_2(&m, &.{ t1, two })) == m.bool_false);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try lookup_element_3(&m, &.{ t1, one, FinalTerms.int(&m.ctx, 2) }), two));
    try std.testing.expectError(error.Badarg, lookup_element_3(&m, &.{ t1, two, FinalTerms.int(&m.ctx, 2) })); // absent
    // /4 default on an absent key.
    const nine = FinalTerms.int(&m.ctx, 9);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try lookup_element_4(&m, &.{ t1, two, FinalTerms.int(&m.ctx, 2), nine }), nine));
}

test "LAW E2.9 insert OVERWRITE: set replaces an equal key (mutant 1); bag accumulates distinct objects" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const s = try newTable(&m, "s", &.{});
    const one = FinalTerms.int(&m.ctx, 1);
    const a = FinalTerms.int(&m.ctx, 100);
    const b = FinalTerms.int(&m.ctx, 200);
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ one, a }) });
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ one, b }) }); // same key -> replace
    const got = try lookup_2(&m, &.{ s, one });
    try std.testing.expectEqual(@as(usize, 1), listLen(&m, got)); // MUTANT 1: not 2
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, FinalTerms.listHead(&m.ctx, got), 1), b));

    // bag: two DISTINCT objects with the same key coexist.
    const bag = try newTable(&m, "bg", &.{try internAtom(&m, "bag")});
    _ = try insert_2(&m, &.{ bag, try mkTuple(&m, &.{ one, a }) });
    _ = try insert_2(&m, &.{ bag, try mkTuple(&m, &.{ one, b }) });
    _ = try insert_2(&m, &.{ bag, try mkTuple(&m, &.{ one, a }) }); // exact dup: no-op
    try std.testing.expectEqual(@as(usize, 2), listLen(&m, try lookup_2(&m, &.{ bag, one })));

    // lookup_element on a bag returns the LIST of position elements.
    const els = try lookup_element_3(&m, &.{ bag, one, FinalTerms.int(&m.ctx, 2) });
    try std.testing.expectEqual(@as(usize, 2), listLen(&m, els));
}

test "LAW E2.9 KEY SEMANTICS: set keeps 1 and 1.0 apart; ordered_set collapses them (reuses ets_algebra comparators)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const one_i = FinalTerms.int(&m.ctx, 1);
    const one_f = FinalTerms.float(&m.ctx, 1.0);
    const v = FinalTerms.int(&m.ctx, 7);

    const s = try newTable(&m, "s", &.{});
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ one_i, v }) });
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ one_f, v }) });
    try std.testing.expectEqual(@as(i64, 2), FinalTerms.smallValOf(try info_2(&m, &.{ s, try internAtom(&m, "size") })));

    const os = try newTable(&m, "os", &.{try internAtom(&m, "ordered_set")});
    _ = try insert_2(&m, &.{ os, try mkTuple(&m, &.{ one_i, v }) });
    _ = try insert_2(&m, &.{ os, try mkTuple(&m, &.{ one_f, v }) });
    try std.testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(try info_2(&m, &.{ os, try internAtom(&m, "size") })));
}

test "LAW E2.9 first/next/last/prev WALK: every key once, ordered (mutant 2); $end_of_table terminates" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const os = try newTable(&m, "os", &.{try internAtom(&m, "ordered_set")});
    // insert keys 3,1,2 out of order; ordered_set must walk 1,2,3.
    const v = FinalTerms.int(&m.ctx, 0);
    for ([_]i64{ 3, 1, 2 }) |k| {
        _ = try insert_2(&m, &.{ os, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, k), v }) });
    }
    const eot = try endOfTable(&m);

    // forward walk via first/next collects exactly [1,2,3] in order (mutant 2:
    // a skip or repeat breaks this).
    var seen: std.ArrayList(i64) = .empty;
    defer seen.deinit(gpa);
    var key = try first_1(&m, &.{os});
    while (!FinalTerms.eqlExact(&m.ctx, key, eot)) {
        try seen.append(gpa, FinalTerms.smallValOf(key));
        key = try next_2(&m, &.{ os, key });
    }
    try std.testing.expectEqualSlices(i64, &.{ 1, 2, 3 }, seen.items);

    // backward walk via last/prev collects [3,2,1].
    var rev: std.ArrayList(i64) = .empty;
    defer rev.deinit(gpa);
    var rk = try last_1(&m, &.{os});
    while (!FinalTerms.eqlExact(&m.ctx, rk, eot)) {
        try rev.append(gpa, FinalTerms.smallValOf(rk));
        rk = try prev_2(&m, &.{ os, rk });
    }
    try std.testing.expectEqualSlices(i64, &.{ 3, 2, 1 }, rev.items);

    // empty table: first/last are $end_of_table straight away.
    const e = try newTable(&m, "e", &.{try internAtom(&m, "ordered_set")});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try first_1(&m, &.{e}), eot));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try last_1(&m, &.{e}), eot));
}

test "LAW E3.18 ets core extensions: take removes+returns; update_element mutates; *_lookup pairs key+objects; safe_fixtable no-op" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const os = try newTable(&m, "os", &.{try internAtom(&m, "ordered_set")});
    // {1,a}, {2,b}, {3,c}
    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const c = FinalTerms.atom(&m.ctx, try atoms.intern("c"));
    for ([_]struct { k: i64, v: Term }{ .{ .k = 1, .v = a }, .{ .k = 2, .v = b }, .{ .k = 3, .v = c } }) |row| {
        _ = try insert_2(&m, &.{ os, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, row.k), row.v }) });
    }

    // take(2) returns [{2,b}] AND removes key 2; a second take is [].
    const taken = try take_2(&m, &.{ os, FinalTerms.int(&m.ctx, 2) });
    try std.testing.expectEqual(@as(usize, 1), listLen(&m, taken));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try take_2(&m, &.{ os, FinalTerms.int(&m.ctx, 2) }), FinalTerms.nil(&m.ctx)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try member_2(&m, &.{ os, FinalTerms.int(&m.ctx, 2) }), boolTerm(&m, false)));

    // update_element(1, {2, z}) sets element 2 of {1,a} to z; returns true.
    const z = FinalTerms.atom(&m.ctx, try atoms.intern("z"));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try update_element_3(&m, &.{ os, FinalTerms.int(&m.ctx, 1), try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), z }) }), boolTerm(&m, true)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try lookup_element_3(&m, &.{ os, FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 2) }), z));
    // absent key -> false (no crash); keypos (1) update -> badarg.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try update_element_3(&m, &.{ os, FinalTerms.int(&m.ctx, 99), try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), z }) }), boolTerm(&m, false)));
    try std.testing.expectError(error.Badarg, update_element_3(&m, &.{ os, FinalTerms.int(&m.ctx, 1), try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 1), z }) }));

    // first_lookup pairs the smallest key with its objects: {1, [{1,z}]}.
    const fl = try first_lookup_1(&m, &.{os});
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, fl) == .tuple and FinalTerms.tupleArity(&m.ctx, fl) == 2);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, fl, 0), FinalTerms.int(&m.ctx, 1)));
    try std.testing.expectEqual(@as(usize, 1), listLen(&m, FinalTerms.tupleElem(&m.ctx, fl, 1)));
    // next_lookup(1) -> key 3 (2 was taken); last_lookup -> 3; prev_lookup(3) -> 1.
    const nl = try next_lookup_2(&m, &.{ os, FinalTerms.int(&m.ctx, 1) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, nl, 0), FinalTerms.int(&m.ctx, 3)));
    const ll = try last_lookup_1(&m, &.{os});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, ll, 0), FinalTerms.int(&m.ctx, 3)));
    const pl = try prev_lookup_2(&m, &.{ os, FinalTerms.int(&m.ctx, 3) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, pl, 0), FinalTerms.int(&m.ctx, 1)));
    // past-the-end returns $end_of_table.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try next_lookup_2(&m, &.{ os, FinalTerms.int(&m.ctx, 3) }), try endOfTable(&m)));

    // safe_fixtable(_, true|false) is a no-op returning true; a bad flag -> badarg.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try safe_fixtable_2(&m, &.{ os, boolTerm(&m, true) }), boolTerm(&m, true)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try safe_fixtable_2(&m, &.{ os, boolTerm(&m, false) }), boolTerm(&m, true)));
    try std.testing.expectError(error.Badarg, safe_fixtable_2(&m, &.{ os, FinalTerms.int(&m.ctx, 1) }));

    // update_element on a bag -> badarg (set/ordered_set only).
    const bag = try newTable(&m, "bg", &.{try internAtom(&m, "bag")});
    _ = try insert_2(&m, &.{ bag, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 1), a }) });
    try std.testing.expectError(error.Badarg, update_element_3(&m, &.{ bag, FinalTerms.int(&m.ctx, 1), try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), z }) }));
}

test "LAW E2.9 delete/1 whole table -> stale Tid is badarg; delete/2 key; delete_object exact; delete_all_objects clears" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const bag = try newTable(&m, "bg", &.{try internAtom(&m, "bag")});
    const one = FinalTerms.int(&m.ctx, 1);
    const a = FinalTerms.int(&m.ctx, 10);
    const b = FinalTerms.int(&m.ctx, 20);
    const oa = try mkTuple(&m, &.{ one, a });
    const ob = try mkTuple(&m, &.{ one, b });
    _ = try insert_2(&m, &.{ bag, oa });
    _ = try insert_2(&m, &.{ bag, ob });

    // delete_object removes ONLY the exact object.
    _ = try delete_object_2(&m, &.{ bag, oa });
    const rest = try lookup_2(&m, &.{ bag, one });
    try std.testing.expectEqual(@as(usize, 1), listLen(&m, rest));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, rest), ob));

    // delete/2 removes the whole key.
    _ = try delete_2(&m, &.{ bag, one });
    try std.testing.expectEqual(@as(usize, 0), listLen(&m, try lookup_2(&m, &.{ bag, one })));

    // delete_all_objects clears but keeps the table usable.
    _ = try insert_2(&m, &.{ bag, ob });
    _ = try delete_all_objects_1(&m, &.{bag});
    try std.testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(try info_2(&m, &.{ bag, try internAtom(&m, "size") })));
    _ = try insert_2(&m, &.{ bag, oa }); // still usable
    try std.testing.expectEqual(@as(usize, 1), listLen(&m, try lookup_2(&m, &.{ bag, one })));

    // delete/1 drops the table; the (integer) Tid then resolves to badarg.
    _ = try delete_1(&m, &.{bag});
    try std.testing.expectError(error.Badarg, lookup_2(&m, &.{ bag, one }));
    try std.testing.expectError(error.Badarg, insert_2(&m, &.{ bag, oa }));
}

test "LAW E3.16 duplicate_bag: insert appends exact copies (mutant 1); delete_object removes ALL copies (mutant 2); update_element badarg; info type" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const db = try newTable(&m, "db", &.{try internAtom(&m, "duplicate_bag")});
    const one = FinalTerms.int(&m.ctx, 1);
    const a = FinalTerms.int(&m.ctx, 10);
    const b = FinalTerms.int(&m.ctx, 20);
    const oa = try mkTuple(&m, &.{ one, a });
    const ob = try mkTuple(&m, &.{ one, b });

    // info type reports duplicate_bag.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try info_2(&m, &.{ db, try internAtom(&m, "type") }), try internAtom(&m, "duplicate_bag")));

    // insert the SAME object 3x -> 3 copies RETAINED (bag would keep 1) — mutant 1.
    _ = try insert_2(&m, &.{ db, oa });
    _ = try insert_2(&m, &.{ db, oa });
    _ = try insert_2(&m, &.{ db, oa });
    try std.testing.expectEqual(@as(usize, 3), listLen(&m, try lookup_2(&m, &.{ db, one })));
    // same-key DIFFERENT object coexists.
    _ = try insert_2(&m, &.{ db, ob });
    try std.testing.expectEqual(@as(usize, 4), listLen(&m, try lookup_2(&m, &.{ db, one })));
    // lookup_element returns the LIST of position-2 elements (with duplicates).
    const els = try lookup_element_3(&m, &.{ db, one, FinalTerms.int(&m.ctx, 2) });
    try std.testing.expectEqual(@as(usize, 4), listLen(&m, els)); // [10,10,10,20]

    // delete_object removes ALL 3 equal copies of oa (the BEAM contract) — mutant 2;
    // ob (a different object) survives.
    _ = try delete_object_2(&m, &.{ db, oa });
    const rest = try lookup_2(&m, &.{ db, one });
    try std.testing.expectEqual(@as(usize, 1), listLen(&m, rest));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, rest), ob));

    // update_element is set/ordered_set-only -> badarg (like bag).
    try std.testing.expectError(error.Badarg, update_element_3(&m, &.{ db, one, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), a }) }));
}

test "LAW E2.9 named_table: Tid is the name atom, reachable by name AND id; whereis-style resolution" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const tid = try newTable(&m, "reg", &.{try internAtom(&m, "named_table")});
    try std.testing.expect(FinalTerms.repIsAtom(tid)); // named -> returns the name atom
    const one = FinalTerms.int(&m.ctx, 1);
    _ = try insert_2(&m, &.{ tid, try mkTuple(&m, &.{ one, one }) });
    // reachable by the name atom.
    try std.testing.expect(FinalTerms.atomIdxOf(try member_2(&m, &.{ tid, one })) == m.bool_true);
    // a second named_table with the same name collides -> badarg.
    try std.testing.expectError(error.Badarg, newTable(&m, "reg", &.{try internAtom(&m, "named_table")}));
}

test "LAW E5.9 rename REMAP: reachable by NewName, old name gone, objects preserved; collision rejects" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const tid = try newTable(&m, "old", &.{try internAtom(&m, "named_table")});
    const one = FinalTerms.int(&m.ctx, 1);
    const seven = FinalTerms.int(&m.ctx, 7);
    _ = try insert_2(&m, &.{ tid, try mkTuple(&m, &.{ one, seven }) });

    // rename returns the NEW name atom.
    const new_name = try internAtom(&m, "fresh");
    const ret = try rename_2(&m, &.{ tid, new_name });
    try std.testing.expect(FinalTerms.repIsAtom(ret) and FinalTerms.atomIdxOf(ret) == FinalTerms.atomIdxOf(new_name));

    // REMAP: reachable by the new name; the info(name) attribute is the new name.
    try std.testing.expect(FinalTerms.atomIdxOf(try member_2(&m, &.{ new_name, one })) == m.bool_true);
    try std.testing.expect(FinalTerms.atomIdxOf(try info_2(&m, &.{ new_name, try internAtom(&m, "name") })) == FinalTerms.atomIdxOf(new_name));
    // OBJECTS PRESERVED: the {1,7} row survives the remap under the new name.
    const got = try lookup_2(&m, &.{ new_name, one });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, got), try mkTuple(&m, &.{ one, seven })));
    // the OLD name no longer resolves.
    try std.testing.expectError(error.Badarg, member_2(&m, &.{ try internAtom(&m, "old"), one }));

    // COLLISION: renaming to a DIFFERENT live named table's name -> badarg.
    const other = try newTable(&m, "other", &.{try internAtom(&m, "named_table")});
    try std.testing.expectError(error.Badarg, rename_2(&m, &.{ other, new_name }));
    // NewName must be an atom.
    try std.testing.expectError(error.Badarg, rename_2(&m, &.{ new_name, FinalTerms.int(&m.ctx, 3) }));
}

test "LAW E2.9 insert_new: false (and no insert) when any key already exists or repeats in the batch" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const s = try newTable(&m, "s", &.{});
    const one = FinalTerms.int(&m.ctx, 1);
    const two = FinalTerms.int(&m.ctx, 2);
    const v = FinalTerms.int(&m.ctx, 0);
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ one, v }) });

    // key 1 already present -> false, nothing added.
    try std.testing.expect(FinalTerms.atomIdxOf(try insert_new_2(&m, &.{ s, try mkTuple(&m, &.{ one, two }) })) == m.bool_false);
    try std.testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(try info_2(&m, &.{ s, try internAtom(&m, "size") })));

    // fresh key -> true.
    try std.testing.expect(FinalTerms.atomIdxOf(try insert_new_2(&m, &.{ s, try mkTuple(&m, &.{ two, v }) })) == m.bool_true);

    // a batch with an internal duplicate key -> false, nothing added.
    const three = FinalTerms.int(&m.ctx, 3);
    const dupbatch = try listOf(&m, &.{ try mkTuple(&m, &.{ three, v }), try mkTuple(&m, &.{ three, one }) });
    try std.testing.expect(FinalTerms.atomIdxOf(try insert_new_2(&m, &.{ s, dupbatch })) == m.bool_false);
    try std.testing.expect(FinalTerms.atomIdxOf(try member_2(&m, &.{ s, three })) == m.bool_false); // untouched
}

test "LAW E2.9 REJECTION: bad Tid, keypos<>1, bad option, non-tuple object, tab2list, info subset" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    // bad Tid (never created).
    try std.testing.expectError(error.Badarg, lookup_2(&m, &.{ FinalTerms.int(&m.ctx, 999), FinalTerms.int(&m.ctx, 1) }));
    // keypos != 1 defers -> badarg.
    const kp = try mkTuple(&m, &.{ try internAtom(&m, "keypos"), FinalTerms.int(&m.ctx, 2) });
    try std.testing.expectError(error.Badarg, newTable(&m, "k", &.{kp}));
    // unknown option atom -> badarg.
    try std.testing.expectError(error.Badarg, newTable(&m, "u", &.{try internAtom(&m, "no_such_opt")}));
    // Name must be an atom.
    try std.testing.expectError(error.Badarg, new_2(&m, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.nil(&m.ctx) }));

    const s = try newTable(&m, "s", &.{});
    // non-tuple object -> badarg; a 0-arity tuple has no key -> badarg.
    try std.testing.expectError(error.Badarg, insert_2(&m, &.{ s, FinalTerms.int(&m.ctx, 5) }));
    try std.testing.expectError(error.Badarg, insert_2(&m, &.{ s, try mkTuple(&m, &.{}) }));
    // a list with a bad element inserts NOTHING (all-or-nothing).
    const badlist = try listOf(&m, &.{ try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 1) }), FinalTerms.int(&m.ctx, 7) });
    try std.testing.expectError(error.Badarg, insert_2(&m, &.{ s, badlist }));
    try std.testing.expectEqual(@as(i64, 0), FinalTerms.smallValOf(try info_2(&m, &.{ s, try internAtom(&m, "size") })));

    // info/2 supported subset works; an unsupported item -> badarg.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try info_2(&m, &.{ s, try internAtom(&m, "type") }), try internAtom(&m, "set")));
    // DIVERGENCE 691: `memory` is now IMPLEMENTED (a size-derived word estimate, an
    // integer — see LAW gap-ets-info-memory); a genuinely-unsupported item still badargs.
    try std.testing.expect(FinalTerms.repIsSmall(try info_2(&m, &.{ s, try internAtom(&m, "memory") })));
    // AMENDED by gap-ets-table-options: `compressed` was the witness here, and
    // it is now IMPLEMENTED and byte-EQ against OTP-30 (`false` by default), so
    // it can no longer serve. The rejection arm is not dropped — it is made
    // STRONGER, with two witnesses instead of one: `node` is a real OTP-30
    // info item zigvm genuinely does not implement (so the honest
    // not-yet-implemented boundary is still under test, and this line will
    // demand attention on the day it lands), and `no_such_item` is a permanent
    // rejection that no future slice can quietly implement away.
    try std.testing.expectError(error.Badarg, info_2(&m, &.{ s, try internAtom(&m, "node") }));
    try std.testing.expectError(error.Badarg, info_2(&m, &.{ s, try internAtom(&m, "no_such_item") }));
    // …and the newly-implemented keys are NOT badargs, so the amendment above
    // cannot pass by having broken them.
    try std.testing.expect(FinalTerms.repIsAtom(try info_2(&m, &.{ s, try internAtom(&m, "compressed") })));
    // info/1 returns a proplist (subset) — 7 rows here.
    try std.testing.expectEqual(@as(usize, 7), listLen(&m, try info_1(&m, &.{s})));
    // tab2list over an empty table is [].
    try std.testing.expectEqual(@as(usize, 0), listLen(&m, try tab2list_1(&m, &.{s})));
    // DIVERGENCE 719: tab2list over an ordered_set returns EVERY object in KEY
    // order — {3,c},{1,a},{2,b} inserted → [{1,a},{2,b},{3,c}] (byte-EQ OTP-30).
    {
        const os = try newTable(&m, "os2", &.{try internAtom(&m, "ordered_set")});
        _ = try insert_2(&m, &.{ os, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 3), try internAtom(&m, "c") }) });
        _ = try insert_2(&m, &.{ os, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 1), try internAtom(&m, "a") }) });
        _ = try insert_2(&m, &.{ os, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), try internAtom(&m, "b") }) });
        const l = try tab2list_1(&m, &.{os});
        try std.testing.expectEqual(@as(usize, 3), listLen(&m, l));
        var cur = l;
        var expect: i64 = 1;
        while (FinalTerms.kindOf(&m.ctx, cur) == .cons) : (expect += 1) {
            const obj = FinalTerms.listHead(&m.ctx, cur);
            try std.testing.expectEqual(expect, FinalTerms.smallValOf(FinalTerms.tupleElem(&m.ctx, obj, 0)));
            cur = FinalTerms.listTail(&m.ctx, cur);
        }
    }
}

test "LAW gap-ets-info-memory (DIVERGENCE 691): ets:info(Tab, memory) is an INTEGER that GROWS with the live object count — a size-derived word estimate (repr-coupled, not byte-EQ to erts, NEVER a constant); unblocks digraph_utils which sum it" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    const s = try newTable(&m, "t", &.{});
    const memItem = try internAtom(&m, "memory");
    // empty table: an integer (the base overhead), > 0.
    const m0 = try info_2(&m, &.{ s, memItem });
    try std.testing.expect(FinalTerms.repIsSmall(m0));
    const w0 = FinalTerms.smallValOf(m0);
    try std.testing.expect(w0 > 0);
    // insert 3 objects → memory STRICTLY INCREASES (proves it is a function of the
    // object count, not a constant — the MUT-B kill).
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ try internAtom(&m, "a"), FinalTerms.int(&m.ctx, 1) }) });
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ try internAtom(&m, "b"), FinalTerms.int(&m.ctx, 2) }) });
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ try internAtom(&m, "c"), FinalTerms.int(&m.ctx, 3) }) });
    const m3 = try info_2(&m, &.{ s, memItem });
    try std.testing.expect(FinalTerms.repIsSmall(m3));
    const w3 = FinalTerms.smallValOf(m3);
    try std.testing.expect(w3 > w0); // strictly grew with 3 inserts
    // and it appears in info/1's proplist too (via the {memory, _} pair) — not asserted
    // here since info/1 is a fixed subset; the /2 path is the digraph_utils entry point.
}

// ── E3.15 match/select family laws ──────────────────────────────────────────

/// A 5-row ordered_set `{1,a}..{5,e}` for the select-family laws (ordered_set
/// so the result ORDER is deterministic and BEAM-equal).
fn seedOsTable(m: *Machine) !Term {
    const os = try newTable(m, "os", &.{try internAtom(m, "ordered_set")});
    const vals = [_][]const u8{ "a", "b", "c", "d", "e" };
    for (vals, 1..) |name, k| {
        const v = FinalTerms.atom(&m.ctx, try m.ctx.atoms.intern(name));
        _ = try insert_2(m, &.{ os, try mkTuple(m, &.{ FinalTerms.int(&m.ctx, @intCast(k)), v }) });
    }
    return os;
}

/// A single-clause spec term `[{Head, Guards, Body}]`.
fn spec1(m: *Machine, head: Term, guards: []const Term, body: []const Term) !Term {
    const clause = try mkTuple(m, &.{ head, try listOf(m, guards), try listOf(m, body) });
    return listOf(m, &.{clause});
}

test "LAW E3.15 select/match family: select value bodies, match '$$', match_object, select_count/replace/delete over the compiler" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const os = try seedOsTable(&m);
    const d1 = try internAtom(&m, "$1");
    const d2 = try internAtom(&m, "$2");
    const two = FinalTerms.int(&m.ctx, 2);

    // select {'$1','$2'} when '$1' > 2 -> '$2'  =>  [c,d,e] (keys 3,4,5).
    const head = try mkTuple(&m, &.{ d1, d2 });
    const g_gt2 = try mkTuple(&m, &.{ try internAtom(&m, ">"), d1, two });
    const sel = try select_2(&m, &.{ os, try spec1(&m, head, &.{g_gt2}, &.{d2}) });
    try std.testing.expectEqual(@as(usize, 3), listLen(&m, sel));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, sel), FinalTerms.atom(&m.ctx, try atoms.intern("c"))));

    // select with a TUPLE-construction body {{'$2','$1'}} -> swapped pairs.
    const swap_body = try mkTuple(&m, &.{try mkTuple(&m, &.{ d2, d1 })});
    const sel2 = try select_2(&m, &.{ os, try spec1(&m, head, &.{g_gt2}, &.{swap_body}) });
    const first_swap = FinalTerms.listHead(&m.ctx, sel2); // {c,3}
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, first_swap) == .tuple and FinalTerms.tupleArity(&m.ctx, first_swap) == 2);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, first_swap, 1), FinalTerms.int(&m.ctx, 3)));

    // match {'$1', b} -> '$$' = [[2]] (only {2,b} matches; $1 bound to 2).
    const bmatch = try mkTuple(&m, &.{ d1, FinalTerms.atom(&m.ctx, try atoms.intern("b")) });
    const mres = try match_2(&m, &.{ os, bmatch });
    try std.testing.expectEqual(@as(usize, 1), listLen(&m, mres));
    const binding_row = FinalTerms.listHead(&m.ctx, mres);
    try std.testing.expectEqual(@as(usize, 1), listLen(&m, binding_row));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, binding_row), two));

    // match_object {'$1','$2'} when '$1' < 3 has no guards form -> use a whole
    // wildcard head '{'$1','_'}' returning whole objects for keys<3.
    const wild = try internAtom(&m, "_");
    const anyhead = try mkTuple(&m, &.{ d1, wild });
    const mo = try match_object_2(&m, &.{ os, anyhead });
    try std.testing.expectEqual(@as(usize, 5), listLen(&m, mo)); // all 5 objects
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, mo), try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.atom(&m.ctx, try atoms.intern("a")) })));

    // select_count of '$1' > 2 -> 3.
    const truebody = try internAtom(&m, "true");
    const cnt = try select_count_2(&m, &.{ os, try spec1(&m, head, &.{g_gt2}, &.{truebody}) });
    try std.testing.expectEqual(@as(i64, 3), FinalTerms.smallValOf(cnt));

    // select_replace {'$1','$2'} when '$1' =:= 1 -> {{'$1','$1'}} (same key 1).
    const g_eq1 = try mkTuple(&m, &.{ try internAtom(&m, "=:="), d1, FinalTerms.int(&m.ctx, 1) });
    const rep_body = try mkTuple(&m, &.{try mkTuple(&m, &.{ d1, d1 })});
    const rep = try select_replace_2(&m, &.{ os, try spec1(&m, head, &.{g_eq1}, &.{rep_body}) });
    try std.testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(rep));
    // {1,a} is now {1,1}.
    const look1 = try lookup_2(&m, &.{ os, FinalTerms.int(&m.ctx, 1) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, look1), try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 1) })));

    // internal_select_delete of '$1' > 2 -> 3 removed; size 5 -> 2 (MUTANT 2:
    // a count that overstates or a delete that under-removes breaks BOTH).
    const del = try internal_select_delete_2(&m, &.{ os, try spec1(&m, head, &.{g_gt2}, &.{truebody}) });
    try std.testing.expectEqual(@as(i64, 3), FinalTerms.smallValOf(del));
    try std.testing.expectEqual(@as(i64, 2), FinalTerms.smallValOf(try info_2(&m, &.{ os, try internAtom(&m, "size") })));
}

test "LAW E3.15 continuation select/3+select/1 round-trips: every row exactly once, in chunks" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const os = try seedOsTable(&m);
    const d1 = try internAtom(&m, "$1");
    const d2 = try internAtom(&m, "$2");
    const head = try mkTuple(&m, &.{ d1, d2 });
    // select ALL keys -> '$1', in chunks of 2.
    const ms = try spec1(&m, head, &.{}, &.{d1});
    const eot = try endOfTable(&m);

    var collected: std.ArrayList(i64) = .empty;
    defer collected.deinit(gpa);
    var reply = try select_3(&m, &.{ os, ms, FinalTerms.int(&m.ctx, 2) });
    while (!FinalTerms.eqlExact(&m.ctx, reply, eot)) {
        try std.testing.expect(FinalTerms.kindOf(&m.ctx, reply) == .tuple and FinalTerms.tupleArity(&m.ctx, reply) == 2);
        var chunk = FinalTerms.tupleElem(&m.ctx, reply, 0);
        while (FinalTerms.kindOf(&m.ctx, chunk) == .cons) : (chunk = FinalTerms.listTail(&m.ctx, chunk)) {
            try collected.append(gpa, FinalTerms.smallValOf(FinalTerms.listHead(&m.ctx, chunk)));
        }
        reply = try select_1(&m, &.{FinalTerms.tupleElem(&m.ctx, reply, 1)});
    }
    // exactly [1,2,3,4,5] once each, ascending.
    try std.testing.expectEqualSlices(i64, &.{ 1, 2, 3, 4, 5 }, collected.items);

    // select_reverse/2 yields descending order.
    const rev = try select_reverse_2(&m, &.{ os, ms });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, rev), FinalTerms.int(&m.ctx, 5)));
    // an empty table -> select/3 is $end_of_table straight away.
    const e = try newTable(&m, "e", &.{try internAtom(&m, "ordered_set")});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try select_3(&m, &.{ e, ms, FinalTerms.int(&m.ctx, 2) }), eot));
}

test "LAW E3.15 match_spec_compile/is_compiled_ms/run_r + match_spec_test/3 agree with select; rejection is clean badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const d1 = try internAtom(&m, "$1");
    const d2 = try internAtom(&m, "$2");
    const head = try mkTuple(&m, &.{ d1, d2 });
    const g_gt2 = try mkTuple(&m, &.{ try internAtom(&m, ">"), d1, FinalTerms.int(&m.ctx, 2) });
    const ms = try spec1(&m, head, &.{g_gt2}, &.{d2});

    // compile -> is_compiled_ms true; a plain term -> false.
    const cms = try match_spec_compile_1(&m, &.{ms});
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try is_compiled_ms_1(&m, &.{cms}), boolTerm(&m, true)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try is_compiled_ms_1(&m, &.{ms}), boolTerm(&m, false)));

    // match_spec_run_r over [{1,a},{3,c}] with tail [] -> results reversed:
    // {1,a} fails (1 not > 2); {3,c} -> c. So [c] (front-to-back prepend).
    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const c = FinalTerms.atom(&m.ctx, try atoms.intern("c"));
    const list = try listOf(&m, &.{ try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 1), a }), try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 3), c }) });
    const run = try match_spec_run_r_3(&m, &.{ list, cms, FinalTerms.nil(&m.ctx) });
    try std.testing.expectEqual(@as(usize, 1), listLen(&m, run));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, run), c));

    // match_spec_test(Object, MS, table): {ok, Result, [], []} — Result equals
    // what select would produce for that one object.
    const t3 = try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 3), c });
    const mst = try match_spec_test_3(&m, &.{ t3, ms, try internAtom(&m, "table") });
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, mst) == .tuple and FinalTerms.tupleArity(&m.ctx, mst) == 4);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, mst, 0), try internAtom(&m, "ok")));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, mst, 1), c)); // body '$2' -> c
    // a non-matching object -> Result is `false`.
    const t1 = try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 1), a });
    const mst1 = try match_spec_test_3(&m, &.{ t1, ms, try internAtom(&m, "table") });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, mst1, 1), boolTerm(&m, false)));

    // REJECTION: a malformed spec is a clean badarg on select/compile, and a
    // {error,_} RESULT on match_spec_test (never a panic).
    const os = try seedOsTable(&m);
    const bad = FinalTerms.int(&m.ctx, 7); // not a list
    try std.testing.expectError(error.Badarg, select_2(&m, &.{ os, bad }));
    try std.testing.expectError(error.Badarg, match_spec_compile_1(&m, &.{bad}));
    const badtest = try match_spec_test_3(&m, &.{ t3, bad, try internAtom(&m, "table") });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, badtest, 0), try internAtom(&m, "error")));
    // trace type is now IMPLEMENTED (DIVERGENCE 633): it returns {ok,Result,
    // Flags,[]} — the body actions run (here `ms`'s value body sets no trace
    // {message,_}, so the trace result defaults to `true`). Full trace-body
    // action semantics are proven in matchspec.zig's LAW matchspec-trace-actions
    // + fixtures/erl/zigvm_matchspec_trace_diff.erl (byte-EQ vs OTP-30).
    const mstr = try match_spec_test_3(&m, &.{ t3, ms, try internAtom(&m, "trace") });
    try std.testing.expect(FinalTerms.kindOf(&m.ctx, mstr) == .tuple and FinalTerms.tupleArity(&m.ctx, mstr) == 4);
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.tupleElem(&m.ctx, mstr, 0), try internAtom(&m, "ok")));
    // a stale Tid still badargs on the whole family.
    _ = try delete_1(&m, &.{os});
    try std.testing.expectError(error.Badarg, select_2(&m, &.{ os, ms }));
}

test "LAW E6.7 ownership BIF surface: new sets owner=self; setopts heir round-trips via info; whereis round-trips through lookup" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();
    m.self_pid = 7; // this Machine's process pid

    // A named table: owner == self() (pid 7), heir == none by default.
    const named = try internAtom(&m, "named_table");
    const public = try internAtom(&m, "public");
    const t = try newTable(&m, "ot", &.{ named, public });
    const owner_v = try info_2(&m, &.{ t, try internAtom(&m, "owner") });
    try std.testing.expect(FinalTerms.repIsPid(&m.ctx, owner_v));
    try std.testing.expectEqual(@as(u64, 7), FinalTerms.pidNumber(&m.ctx, owner_v));
    try std.testing.expect(atomEq(&m, try info_2(&m, &.{ t, try internAtom(&m, "heir") }), "none"));

    // setopts {heir, Pid, Data}: info(heir) reads the heir pid back (the round-trip).
    const heir_pid = try FinalTerms.pid(&m.ctx, 42, 0);
    const hdata = try internAtom(&m, "hd");
    const heir_opt = try mkTuple(&m, &.{ try internAtom(&m, "heir"), heir_pid, hdata });
    _ = try setopts_2(&m, &.{ t, heir_opt });
    const heir_v = try info_2(&m, &.{ t, try internAtom(&m, "heir") });
    try std.testing.expectEqual(@as(u64, 42), FinalTerms.pidNumber(&m.ctx, heir_v));

    // {heir, none} clears it.
    const none_opt = try mkTuple(&m, &.{ try internAtom(&m, "heir"), try internAtom(&m, "none") });
    _ = try setopts_2(&m, &.{ t, none_opt });
    try std.testing.expect(atomEq(&m, try info_2(&m, &.{ t, try internAtom(&m, "heir") }), "none"));

    // setopts by a NON-owner is Badarg (erts' owner restriction).
    m.self_pid = 999;
    try std.testing.expectError(error.Badarg, setopts_2(&m, &.{ t, none_opt }));
    m.self_pid = 7;

    // whereis(Name) returns a Tid that round-trips through lookup (representation-
    // free: the same value every other ets BIF accepts).
    const kv = try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 99) });
    _ = try insert_2(&m, &.{ t, kv });
    const tid = try whereis_1(&m, &.{try internAtom(&m, "ot")});
    const got = try lookup_2(&m, &.{ tid, FinalTerms.int(&m.ctx, 1) });
    try std.testing.expectEqual(@as(usize, 1), listLen(&m, got));
    // whereis of an unknown name is `undefined`.
    try std.testing.expect(atomEq(&m, try whereis_1(&m, &.{try internAtom(&m, "nope")}), "undefined"));
}

test "LAW E31-T2 update_counter grammar + saturation + list + default + rejection (byte-EQ erl_db.c)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const s = try newTable(&m, "s", &.{}); // set (default)
    const k = FinalTerms.int(&m.ctx, 1);

    // Seed {1, 10, 100}. Bare Incr targets keypos+1 == position 2.
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ k, FinalTerms.int(&m.ctx, 10), FinalTerms.int(&m.ctx, 100) }) });

    // (a) bare Incr 5 -> position 2 becomes 15, returns 15 (single integer).
    const r_bare = try update_counter_3(&m, &.{ s, k, FinalTerms.int(&m.ctx, 5) });
    try std.testing.expectEqual(@as(i64, 15), FinalTerms.smallValOf(r_bare));
    // stored object is now {1,15,100}.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try lookup_element_3(&m, &.{ s, k, FinalTerms.int(&m.ctx, 2) }), FinalTerms.int(&m.ctx, 15)));

    // (b) {Pos,Incr} form: {3, -40} -> position 3 becomes 60, returns 60.
    const r_tup = try update_counter_3(&m, &.{ s, k, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 3), FinalTerms.int(&m.ctx, -40) }) });
    try std.testing.expectEqual(@as(i64, 60), FinalTerms.smallValOf(r_tup));

    // (c) 4-tuple saturation UP: {2, 100, 20, 7} -> 15+100=115 > 20 -> SetValue 7.
    const r_up = try update_counter_3(&m, &.{ s, k, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 100), FinalTerms.int(&m.ctx, 20), FinalTerms.int(&m.ctx, 7) }) });
    try std.testing.expectEqual(@as(i64, 7), FinalTerms.smallValOf(r_up)); // position 2 now 7
    // NOT saturating (result <= Threshold): {2, 1, 1000, 999} -> 7+1=8, 8<=1000 -> 8.
    const r_nosat = try update_counter_3(&m, &.{ s, k, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 1000), FinalTerms.int(&m.ctx, 999) }) });
    try std.testing.expectEqual(@as(i64, 8), FinalTerms.smallValOf(r_nosat));

    // (d) 4-tuple saturation DOWN: {2, -100, 0, -1} -> 8-100=-92 < 0 -> SetValue -1.
    const r_dn = try update_counter_3(&m, &.{ s, k, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, -100), FinalTerms.int(&m.ctx, 0), FinalTerms.int(&m.ctx, -1) }) });
    try std.testing.expectEqual(@as(i64, -1), FinalTerms.smallValOf(r_dn));

    // (e) LIST form on the SAME object, left-to-right: reset {1,0,0} then
    //     [{2,1},{2,1},{3,5}] -> position 2: 0->1->2 (results 1,2), position 3: 0->5.
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ k, FinalTerms.int(&m.ctx, 0), FinalTerms.int(&m.ctx, 0) }) });
    const ops = try listOf(&m, &.{
        try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 1) }),
        try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 1) }),
        try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 3), FinalTerms.int(&m.ctx, 5) }),
    });
    const r_list = try update_counter_3(&m, &.{ s, k, ops });
    try std.testing.expectEqual(@as(usize, 3), listLen(&m, r_list));
    var it = r_list;
    inline for ([_]i64{ 1, 2, 5 }) |want| {
        try std.testing.expectEqual(want, FinalTerms.smallValOf(FinalTerms.listHead(&m.ctx, it)));
        it = FinalTerms.listTail(&m.ctx, it);
    }
    // shared-object mutations persisted: {1,2,5}.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try lookup_element_3(&m, &.{ s, k, FinalTerms.int(&m.ctx, 2) }), FinalTerms.int(&m.ctx, 2)));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try lookup_element_3(&m, &.{ s, k, FinalTerms.int(&m.ctx, 3) }), FinalTerms.int(&m.ctx, 5)));

    // (f) empty list [] -> [] and no crash.
    const r_empty = try update_counter_3(&m, &.{ s, k, FinalTerms.nil(&m.ctx) });
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, r_empty, FinalTerms.nil(&m.ctx)));

    // (g) arity-3 on a MISSING key -> badarg (no default).
    const miss = FinalTerms.int(&m.ctx, 999);
    try std.testing.expectError(error.Badarg, update_counter_3(&m, &.{ s, miss, FinalTerms.int(&m.ctx, 1) }));
    // arity-4 default-insert: Default {x, 0} with key replaced -> {999,0}, +1 -> 1.
    const dflt = try mkTuple(&m, &.{ FinalTerms.atom(&m.ctx, try atoms.intern("x")), FinalTerms.int(&m.ctx, 0) });
    const r_def = try update_counter_4(&m, &.{ s, miss, FinalTerms.int(&m.ctx, 1), dflt });
    try std.testing.expectEqual(@as(i64, 1), FinalTerms.smallValOf(r_def));
    // the inserted object has its keypos element == Key (999), position 2 == 1.
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, FinalTerms.listHead(&m.ctx, try lookup_2(&m, &.{ s, miss })), try mkTuple(&m, &.{ miss, FinalTerms.int(&m.ctx, 1) })));

    // (h) REJECTION arms, each a clean badarg (never a panic):
    //   Pos == keypos(1)
    try std.testing.expectError(error.Badarg, update_counter_3(&m, &.{ s, k, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 1) }) }));
    //   Pos out of range (position 9 > arity 3)
    try std.testing.expectError(error.Badarg, update_counter_3(&m, &.{ s, k, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 9), FinalTerms.int(&m.ctx, 1) }) }));
    //   non-integer Incr
    const foo = FinalTerms.atom(&m.ctx, try atoms.intern("foo"));
    try std.testing.expectError(error.Badarg, update_counter_3(&m, &.{ s, k, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), foo }) }));
    //   element at Pos is not an integer: seed {2, notint} and bump it.
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), foo }) });
    try std.testing.expectError(error.Badarg, update_counter_3(&m, &.{ s, FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 1) }));
    //   malformed 3-tuple op
    try std.testing.expectError(error.Badarg, update_counter_3(&m, &.{ s, k, try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 1), FinalTerms.int(&m.ctx, 3) }) }));
    //   bag/duplicate_bag counters are ambiguous -> badarg
    const bag = try newTable(&m, "bg", &.{try internAtom(&m, "bag")});
    _ = try insert_2(&m, &.{ bag, try mkTuple(&m, &.{ k, FinalTerms.int(&m.ctx, 0) }) });
    try std.testing.expectError(error.Badarg, update_counter_3(&m, &.{ bag, k, FinalTerms.int(&m.ctx, 1) }));
    //   bad Tid -> badarg
    try std.testing.expectError(error.Badarg, update_counter_3(&m, &.{ FinalTerms.int(&m.ctx, 12345), k, FinalTerms.int(&m.ctx, 1) }));

    // (i) ATOMICITY: a list with a BAD second op leaves the object UNCHANGED.
    _ = try insert_2(&m, &.{ s, try mkTuple(&m, &.{ k, FinalTerms.int(&m.ctx, 50), FinalTerms.int(&m.ctx, 60) }) });
    const bad_ops = try listOf(&m, &.{
        try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 2), FinalTerms.int(&m.ctx, 5) }),
        try mkTuple(&m, &.{ FinalTerms.int(&m.ctx, 9), FinalTerms.int(&m.ctx, 5) }), // pos 9 > arity 3
    });
    try std.testing.expectError(error.Badarg, update_counter_3(&m, &.{ s, k, bad_ops }));
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, try lookup_element_3(&m, &.{ s, k, FinalTerms.int(&m.ctx, 2) }), FinalTerms.int(&m.ctx, 50))); // still 50
}

// ── gap-ets-table-options ───────────────────────────────────────────────────
//
// The table-option OBSERVATION algebra: what `ets:new/2` accepts, and what
// `ets:info/2` reports back. Every expected value below was measured against
// the pinned OTP-30 oracle on 20260808 — none of it is inferred.
//
// SCOPE, stated once and not softened: these options are DECLARED and OBSERVED.
// They do not change the engine. `read_concurrency`/`write_concurrency` do not
// alter locking (the registry stays a single reentrant spinlock) and
// `compressed` does not compress. Reporting the declaration is what OTP's
// `info/2` does — it reports the option, not a measurement — so this is
// truthful, and the unmodelled behaviour stays the {S}-axis work in
// `gap-ets-concurrency`.

/// A `{Key, Value}` option tuple, for the tests below.
fn optTuple(m: *Machine, k: []const u8, v: Term) !Term {
    return mkTuple(m, &.{ try internAtom(m, k), v });
}

test "LAW gap-ets-table-options OBSERVATION: info/2 reports every declared option byte-EQ vs OTP-30" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const t_true = FinalTerms.atom(&m.ctx, m.bool_true);
    const t_false = FinalTerms.atom(&m.ctx, m.bool_false);

    // read_concurrency + write_concurrency round-trip, and the DEFAULTS.
    const plain = try newTable(&m, "p", &.{try internAtom(&m, "set")});
    try expectInfo(&m, plain, "read_concurrency", t_false);
    try expectInfo(&m, plain, "write_concurrency", t_false);
    try expectInfo(&m, plain, "compressed", t_false);
    try expectInfo(&m, plain, "decentralized_counters", t_false);

    const rc = try newTable(&m, "rc", &.{
        try internAtom(&m, "set"),
        try optTuple(&m, "read_concurrency", t_true),
        try optTuple(&m, "write_concurrency", t_true),
    });
    try expectInfo(&m, rc, "read_concurrency", t_true);
    try expectInfo(&m, rc, "write_concurrency", t_true);

    // `auto` is a THIRD write_concurrency value, reported verbatim. A boolean
    // field would silently coerce it to `true` and pass every other law here.
    const wa = try newTable(&m, "wa", &.{
        try internAtom(&m, "set"),
        try optTuple(&m, "write_concurrency", try internAtom(&m, "auto")),
    });
    try expectInfo(&m, wa, "write_concurrency", try internAtom(&m, "auto"));

    // `compressed` is the BARE atom form only (the tuple form is rejected below).
    const cz = try newTable(&m, "cz", &.{try internAtom(&m, "compressed")});
    try expectInfo(&m, cz, "compressed", t_true);

    // protection: the rotted constant. All three values, through info/2 AND the
    // info/1 proplist, because the hardcoded "protected" sat in both.
    inline for (.{ "public", "protected", "private" }, .{ "gp", "gt", "gv" }) |p, nm| {
        const tab = try newTable(&m, nm, &.{try internAtom(&m, p)});
        try expectInfo(&m, tab, "protection", try internAtom(&m, p));
        try std.testing.expect(FinalTerms.eqlExact(
            &m.ctx,
            try proplistGet(&m, try info_1(&m, &.{tab}), "protection"),
            try internAtom(&m, p),
        ));
    }
}

test "LAW gap-ets-table-options DC-CELLS: the nine measured decentralized_counters operands, end to end" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const t_true = FinalTerms.atom(&m.ctx, m.bool_true);
    const t_false = FinalTerms.atom(&m.ctx, m.bool_false);

    // ty, write_concurrency (null = absent), dc option (null = absent), expected.
    const Cell = struct { ty: []const u8, wc: ?[]const u8, dc: ?bool, prot: ?[]const u8 = null, want: bool, note: []const u8 };
    const cells = [_]Cell{
        .{ .ty = "set", .wc = null, .dc = null, .want = false, .note = "set, no options" },
        .{ .ty = "set", .wc = null, .dc = true, .want = false, .note = "set {dc,true} — wc off, so FALSE" },
        .{ .ty = "set", .wc = null, .dc = false, .want = false, .note = "set {dc,false}" },
        .{ .ty = "ordered_set", .wc = null, .dc = true, .want = false, .note = "oset {dc,true} — wc off, so FALSE" },
        .{ .ty = "ordered_set", .wc = "true", .dc = null, .want = true, .note = "oset {wc,true} — TRUE with no dc option" },
        .{ .ty = "ordered_set", .wc = "auto", .dc = null, .want = true, .note = "oset {wc,auto} — auto counts as enabled" },
        .{ .ty = "set", .wc = "true", .dc = null, .want = false, .note = "set {wc,true} — set defaults dc FALSE" },
        .{ .ty = "set", .wc = "true", .dc = true, .want = true, .note = "set {wc,true},{dc,true} — TRUE, not type-locked" },
        .{ .ty = "ordered_set", .wc = "true", .dc = false, .want = false, .note = "oset {wc,true},{dc,false}" },
        // THE DIMENSION THE FIRST NINE CELLS DID NOT VARY — `protection` was
        // held at its default in every row above, so the equation could ship
        // without an access term and no operand could see it.
        .{ .ty = "ordered_set", .wc = "true", .dc = null, .prot = "private", .want = false, .note = "oset {wc,true},private — access DOMINATES" },
        .{ .ty = "ordered_set", .wc = "true", .dc = true, .prot = "private", .want = false, .note = "oset {wc,true},{dc,true},private — beats an EXPLICIT true" },
        .{ .ty = "set", .wc = "true", .dc = true, .prot = "private", .want = false, .note = "set {wc,true},{dc,true},private" },
        .{ .ty = "ordered_set", .wc = "auto", .dc = null, .prot = "private", .want = false, .note = "oset {wc,auto},private" },
        // …and the counterweight, so the access term cannot be satisfied by a
        // rule that merely answers false more often.
        .{ .ty = "set", .wc = "true", .dc = true, .prot = "public", .want = true, .note = "set {wc,true},{dc,true},public — still TRUE" },
        .{ .ty = "set", .wc = "true", .dc = true, .prot = "protected", .want = true, .note = "set {wc,true},{dc,true},protected — still TRUE" },
        .{ .ty = "ordered_set", .wc = "true", .dc = null, .prot = "public", .want = true, .note = "oset {wc,true},public — still TRUE" },
    };

    for (cells, 0..) |c, i| {
        var opts: [4]Term = undefined;
        var n: usize = 0;
        opts[n] = try internAtom(&m, c.ty);
        n += 1;
        if (c.wc) |w| {
            const wv = if (std.mem.eql(u8, w, "auto")) try internAtom(&m, "auto") else t_true;
            opts[n] = try optTuple(&m, "write_concurrency", wv);
            n += 1;
        }
        if (c.dc) |d| {
            opts[n] = try optTuple(&m, "decentralized_counters", if (d) t_true else t_false);
            n += 1;
        }
        if (c.prot) |p| {
            opts[n] = try internAtom(&m, p);
            n += 1;
        }
        var buf: [8]u8 = undefined;
        const nm = try std.fmt.bufPrint(&buf, "dc{d}", .{i});
        const tab = try newTable(&m, nm, opts[0..n]);
        const got = try info_2(&m, &.{ tab, try internAtom(&m, "decentralized_counters") });
        const want = if (c.want) t_true else t_false;
        if (!FinalTerms.eqlExact(&m.ctx, got, want)) {
            // Name the CELL. A nine-operand differential that prints only
            // "expected true, got false" sends the reader back to the source to
            // work out which row failed and why it was written that way.
            std.debug.print(
                "\nDC-CELL {d} FAILED: {s}\n  ty={s} wc={?s} dc={?} prot={?s} expected={}\n",
                .{ i, c.note, c.ty, c.wc, c.dc, c.prot, c.want },
            );
            return error.TestUnexpectedResult;
        }
    }
}

test "LAW gap-ets-table-options REJECTION: bad option VALUES and the tuple-form compressed are badarg" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const t_true = FinalTerms.atom(&m.ctx, m.bool_true);
    const bad = try internAtom(&m, "notabool");
    const seven = FinalTerms.int(&m.ctx, 7);

    // Every option that takes a boolean rejects a non-boolean — measured on
    // OTP-30, which badargs all three. Without this the parser accepts anything
    // and every positive law above is satisfied by a reader that checks nothing.
    inline for (.{ "read_concurrency", "write_concurrency", "decentralized_counters" }) |k| {
        try std.testing.expectError(error.Badarg, newTable(&m, "bad", &.{try optTuple(&m, k, bad)}));
        try std.testing.expectError(error.Badarg, newTable(&m, "bad", &.{try optTuple(&m, k, seven)}));
    }
    // `auto` is legal for write_concurrency ONLY.
    const auto = try internAtom(&m, "auto");
    try std.testing.expectError(error.Badarg, newTable(&m, "bad", &.{try optTuple(&m, "read_concurrency", auto)}));
    try std.testing.expectError(error.Badarg, newTable(&m, "bad", &.{try optTuple(&m, "decentralized_counters", auto)}));

    // `compressed` in TUPLE form is a badarg on OTP-30 — only the bare atom is
    // legal, which is easy to get wrong in the permissive direction.
    try std.testing.expectError(error.Badarg, newTable(&m, "bad", &.{try optTuple(&m, "compressed", t_true)}));
}

test "LAW gap-ets-table-options LAST-WINS: a repeated option takes its final value" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try Machine.init(gpa, &atoms);
    defer m.deinit();

    const t_true = FinalTerms.atom(&m.ctx, m.bool_true);
    const t_false = FinalTerms.atom(&m.ctx, m.bool_false);
    const tab = try newTable(&m, "lw", &.{
        try optTuple(&m, "read_concurrency", t_true),
        try optTuple(&m, "read_concurrency", t_false),
    });
    try expectInfo(&m, tab, "read_concurrency", t_false);
    // …and the other order, so the law cannot pass by always reporting `false`.
    const tab2 = try newTable(&m, "lw2", &.{
        try optTuple(&m, "read_concurrency", t_false),
        try optTuple(&m, "read_concurrency", t_true),
    });
    try expectInfo(&m, tab2, "read_concurrency", t_true);
}

/// Monotonic nanoseconds, for the cost-attribution law below. A raw
/// `clock_gettime` rather than `std.Io` because a law must not need an event
/// loop injected to ask what time it is.
fn probeNowNs() i128 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    return @as(i128, ts.sec) * 1_000_000_000 + @as(i128, ts.nsec);
}

test "LAW gap-ets-lock-attribution LOCK-IS-NOT-THE-SERIAL-TERM: the registry lock is a negligible fraction of an ETS operation, so narrowing it cannot move the scaling curve" {
    // WHY THIS LAW EXISTS. `gap-ets-concurrency` was ranked for months on the
    // premise that ETS does not scale because of the global registry lock, and
    // `gap-ets-scale-unit` measured a curve that DOES degrade — s(4)=0.813 —
    // which looks like confirmation. It is not. At n=1 there is no contention
    // at all, and a single `update_counter/3` still costs tens of microseconds.
    // The serial term is the OPERATION, not the lock, and a lock narrowing
    // would be the wasted slice `skills/smp-concurrency-slice` warns about
    // (FM-SMP-CONTENTION-BLIND).
    //
    // THE LAW IS A RATIO, DELIBERATELY. An absolute nanosecond bound on a
    // shared host is a flake generator; a ratio moves with the host in both
    // terms and stays stable.
    //
    // AND IT MEASURES UNDER AN ARENA, which is the correction to the first
    // version of this law. That version used the test allocator and read
    // lock=6ns against op=26,000ns — a factor of 4000 that looked like an
    // overwhelming margin. It was mostly ALLOCATOR: a leak-tracking allocator
    // captures a stack trace per allocation, `update_counter/3` makes several,
    // and a bare ArrayList append+deinit alone cost 12,662ns on the same
    // harness. Under an arena the same operations cost 649ns and 48ns. The law
    // PASSED for the wrong reason, and a law that passes for the wrong reason
    // is one allocator change away from being a law that fails for no reason.
    //
    // Honest numbers on this host, arena: lock=5ns, update_counter/3=649ns — a
    // factor of ~130. The law asserts 20, leaving ~6x of headroom, which is a
    // real margin rather than an inflated one.
    //
    // AND IT IS SELF-CORRECTING, which is the real reason to keep it. If a
    // future slice makes ETS operations genuinely fast, the ratio narrows and
    // this law FAILS — telling the next reader that the lock has finally become
    // the serial term and the narrowing is now worth doing. A one-off
    // measurement decays silently; this one announces when it stops being true.
    // An ARENA, so the measurement is of ETS and not of allocator bookkeeping.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var atoms = AtomTable.init(gpa);
    var m = try Machine.init(gpa, &atoms);

    const tab = try newTable(&m, "attr_tab", &.{try internAtom(&m, "set")});
    const key = try internAtom(&m, "k");
    _ = try insert_2(&m, &.{ tab, try mkTuple(&m, &.{ key, FinalTerms.int(&m.ctx, 0) }) });
    const incr = FinalTerms.int(&m.ctx, 1);

    const N: usize = 300;
    var t0 = probeNowNs();
    for (0..N) |_| _ = try update_counter_3(&m, &.{ tab, key, incr });
    const op_ns = @divTrunc(probeNowNs() - t0, @as(i128, N));

    t0 = probeNowNs();
    for (0..N) |_| {
        m.etsReg().lockShared();
        m.etsReg().unlockShared();
    }
    const lock_ns = @divTrunc(probeNowNs() - t0, @as(i128, N));

    // NON-VACUITY: a clock that returned a constant would make both zero and
    // satisfy any ratio. The operation must have taken measurable time.
    if (op_ns <= 0) {
        std.debug.print("\nlock-attribution: op_ns={d} — the clock produced no elapsed time\n", .{op_ns});
        return error.TestUnexpectedResult;
    }
    if (lock_ns * 20 >= op_ns) {
        // Not necessarily a regression — possibly very good news. Say so, so
        // nobody reads a red gate here as a defect to suppress.
        std.debug.print(
            "\nlock-attribution: lock={d}ns is >=5% of op={d}ns.\n" ++
                "  Either ETS operations got MUCH faster (good — the lock is now the\n" ++
                "  serial term and gap-ets-concurrency's narrowing is finally worth\n" ++
                "  doing), or the lock got slower. Re-measure before changing this law.\n",
            .{ lock_ns, op_ns },
        );
        return error.TestUnexpectedResult;
    }
}
