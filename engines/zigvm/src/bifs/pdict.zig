//! # bifs/pdict — the process dictionary BIF family (E3.9/S24)
//!
//! ## Signature
//! Same contract as the other family modules: each BIF is a
//! `pub fn (m: *Machine, args: []const Term) BifError!Term` over ALREADY-
//! RESOLVED term arguments, computed via EXISTING Machine state (NO new term
//! semantics live here). It NEVER panics on a well-formed call.
//!
//! ## Semantic domain — reuse, not reinvention
//! The process dictionary denotes a finite map `pdict : Term ⇀ Term`, keyed
//! by EXACT (`=:=`) equality — `1` and `1.0` are DISTINCT keys, exactly
//! `map_algebra`'s key discipline. Oracle: a sorted assoc list (the same
//! oracle `map_algebra`/`term_algebra`'s `InitialTerms.denote` already uses
//! for maps). Final: `Machine.pdict` (`instr_algebra.zig`) — a PLAIN
//! `FinalTerms` map TERM living in the Machine's own `ctx` heap, built and
//! read with `term_algebra`'s existing `mapNew`/`mapGet`/`mapPut`/
//! `mapRemove`/`mapPairs` VERBATIM — no divergent map implementation lives
//! here (the pdict-map homomorphism: every BIF observation below agrees with
//! `map_algebra`'s denotation because it IS a map_algebra map). See
//! `Machine.pdict`'s doc comment for the GC-root crux and the lifecycle law
//! (fresh Machine ⇒ empty pdict; freed with `ctx` on `deinit`, no leak).
//!
//! ## The BEAM return-value contract (exact, per erlang.erl / bif.tab)
//!   put(K,V)     stores V under K; returns the OLD value, or the atom
//!                `undefined` if K was absent. (Mutant 1: returning the NEW
//!                value instead — killed by the worked return-contract law.)
//!   get()        the WHOLE dictionary as a `[{K,V}]` proplist (no defined
//!                order is documented by BEAM; this VM uses `mapPairs`'
//!                sorted-key order, consistent with `maps:to_list/1`).
//!   get(K)       the value under K, or `undefined` if absent.
//!   erase()      returns the FULL PRIOR `[{K,V}]` list AND clears the whole
//!                dictionary (both effects, one call — the lifecycle law).
//!   erase(K)     returns the OLD value under K (or `undefined`) and removes
//!                K.
//!   get_keys()   all keys, as a list (any order — sorted here).
//!   get_keys(V)  all keys whose value is `=:=` V (exact equality).
//!
//! ## Reachability (call_ext honesty — see DIVERGENCE_LOG.md entry 13(b))
//! Every one of these seven BIFs operates PURELY on the CALLING process's own
//! Machine state — no pid/ref argument, no scheduler interaction, nothing
//! that can block or reschedule. That is exactly the shape `self/0`, `node/1`
//! (E3.7), `nodes/0`/`process_flag/2` (E2.11) already proved reachable
//! end-to-end via the `bif0`/`bif1`/`gc_bif1`/`gc_bif2` opcode family
//! (`dispatch.implOf`/`implOf`'s main `erlang` table — the ONE opcode-level
//! path genuinely reachable from a compiled `.beam` today, per the E3.8
//! report's reachable-set criterion). `registered/0` ALSO compiles to a
//! `bif0` (still opcode-reachable — e4-registered0 did not change that), but
//! it is NO LONGER Machine-self-contained: it traps into the Vm for the
//! registry (`bifs/procsys.zig`'s doc comment); the pending-action mechanism
//! is opcode-agnostic (`proc.zig`'s scheduler resumes on ANY `m.pending`,
//! whether set by a `bif0` or a `call_ext_bif` call), so reachability is
//! unaffected. The pin's `bif.tab` confirms
//! the exact opcode shape each takes: `bif erlang:get/0`, `bif erlang:
//! get/1`, `bif erlang:get_keys/0`, `bif erlang:get_keys/1`, `bif erlang:
//! erase/0` compile to `bif0`/`bif1` (no GC-live hint needed — arity ≤ 1,
//! no `gc_bif0` opcode exists); `hbif erlang:erase/1`, `hbif erlang:put/2`
//! compile to `gc_bif1`/`gc_bif2` (the heap-allocating variant our loader
//! ALREADY decodes through the SAME unified `bif`/`gc_bif` path — see
//! `instr_algebra.zig`'s CInstr `bif`/`gc_bif` doc comment). So all SEVEN
//! flip EQ in `harness/bif_gen.ml`'s `implemented_map` — none is
//! `deferred-E4-procdispatch`; this family needed no `Vm`/Action-trap bridge at
//! all (unlike `procsys.zig`'s pid/scheduler-blocked remainder).
//!
//! ## Laws (see the test section below)
//!   - worked return-contract law (differential vs the assoc-list oracle)
//!   - GC-root interaction law (THE crux — see below): a value survives a
//!     full collection of the Machine's heap bit-identically, because
//!     `Machine.pdict` is rooted exactly like `regs`/`result`/the mailbox.
//!   - exact-key law: `1` and `1.0` are distinct keys.
//!   - lifecycle law: a fresh Machine's pdict is empty; `erase/0` returns the
//!     full prior list AND empties it.
//!   - pdict-map homomorphism: BIF-mediated state agrees with directly-built
//!     `map_algebra` state after the same op sequence.

const std = @import("std");
const ia = @import("../instr_algebra.zig");
const ta = @import("../term_algebra.zig");
const gc_mod = @import("../gc.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;
const Term = FinalTerms.Term;
const Machine = ia.Machine;
const BifError = ia.BifError;

fn undefinedAtom(m: *Machine) BifError!Term {
    const idx = m.ctx.atoms.intern("undefined") catch return error.OutOfMemory;
    return FinalTerms.atom(&m.ctx, idx);
}

/// Collect every (K,V) pair of the pdict into fresh `m.gpa`-owned buffers
/// (same shape as `bifs/maps.zig`'s `collectPairs` — reuse of the pattern,
/// not the code, since the map lives on `m.pdict` not an argument Term).
fn collectPairs(m: *Machine) BifError!struct { keys: []Term, vals: []Term } {
    const n = FinalTerms.mapSize(&m.ctx, m.pdict);
    const pk = m.gpa.alloc(Term, n) catch return error.OutOfMemory;
    errdefer m.gpa.free(pk);
    const pv = m.gpa.alloc(Term, n) catch return error.OutOfMemory;
    errdefer m.gpa.free(pv);
    const got = FinalTerms.mapPairs(&m.ctx, m.pdict, pk, pv);
    std.debug.assert(got == n);
    return .{ .keys = pk, .vals = pv };
}

/// Build the `[{K,V}, ...]` proplist for `get/0`/`erase/0`.
fn pairsToProplist(m: *Machine, keys: []const Term, vals: []const Term) BifError!Term {
    var acc = FinalTerms.nil(&m.ctx);
    var i = keys.len;
    while (i > 0) {
        i -= 1;
        const kv = FinalTerms.tuple(&m.ctx, &.{ keys[i], vals[i] }) catch return error.OutOfMemory;
        acc = FinalTerms.cons(&m.ctx, kv, acc) catch return error.OutOfMemory;
    }
    return acc;
}

// ── erlang:put/2 ─────────────────────────────────────────────────────────────

/// Returns the OLD value under `K` (or `undefined`); stores `V`. MUTANT 1:
/// returning `val` (the NEW value) here instead of `old` is killed by the
/// worked return-contract law below.
pub fn put_2(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const val = args[1];
    const old = FinalTerms.mapGet(&m.ctx, m.pdict, key) orelse try undefinedAtom(m);
    m.pdict = FinalTerms.mapPut(&m.ctx, m.pdict, key, val) catch return error.OutOfMemory;
    return old;
}

// ── erlang:get/0, erlang:get/1 ──────────────────────────────────────────────

pub fn get_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const pairs = try collectPairs(m);
    defer m.gpa.free(pairs.keys);
    defer m.gpa.free(pairs.vals);
    return pairsToProplist(m, pairs.keys, pairs.vals);
}

pub fn get_1(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    return FinalTerms.mapGet(&m.ctx, m.pdict, key) orelse try undefinedAtom(m);
}

// ── erlang:erase/0, erlang:erase/1 ──────────────────────────────────────────

/// Returns the FULL PRIOR `[{K,V}]` list AND clears the whole dictionary —
/// BOTH effects from one call (the lifecycle law).
pub fn erase_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const pairs = try collectPairs(m);
    defer m.gpa.free(pairs.keys);
    defer m.gpa.free(pairs.vals);
    const list = try pairsToProplist(m, pairs.keys, pairs.vals);
    m.pdict = FinalTerms.mapNew(&m.ctx, &.{}, &.{}) catch return error.OutOfMemory;
    return list;
}

pub fn erase_1(m: *Machine, args: []const Term) BifError!Term {
    const key = args[0];
    const old = FinalTerms.mapGet(&m.ctx, m.pdict, key) orelse try undefinedAtom(m);
    m.pdict = FinalTerms.mapRemove(&m.ctx, m.pdict, key) catch return error.OutOfMemory;
    return old;
}

// ── erlang:get_keys/0, erlang:get_keys/1 ────────────────────────────────────

pub fn get_keys_0(m: *Machine, args: []const Term) BifError!Term {
    _ = args;
    const pairs = try collectPairs(m);
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

pub fn get_keys_1(m: *Machine, args: []const Term) BifError!Term {
    const target = args[0];
    const pairs = try collectPairs(m);
    defer m.gpa.free(pairs.keys);
    defer m.gpa.free(pairs.vals);
    var acc = FinalTerms.nil(&m.ctx);
    var i = pairs.keys.len;
    while (i > 0) {
        i -= 1;
        if (FinalTerms.eqlExact(&m.ctx, pairs.vals[i], target)) {
            acc = FinalTerms.cons(&m.ctx, pairs.keys[i], acc) catch return error.OutOfMemory;
        }
    }
    return acc;
}

// ============================================================================
// LAWS
// ============================================================================

fn freshMachine(gpa: std.mem.Allocator, atoms: *AtomTable) !Machine {
    return ia.Machine.init(gpa, atoms);
}

fn expectEqlExact(m: *Machine, got: BifError!Term, want: Term) !void {
    const g = try got;
    try std.testing.expect(FinalTerms.eqlExact(&m.ctx, g, want));
}

test "LAW E3.9 lifecycle: a fresh Machine's pdict is empty (mapSize 0, denotes [])" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try freshMachine(gpa, &atoms);
    defer m.deinit();

    try std.testing.expectEqual(@as(usize, 0), FinalTerms.mapSize(&m.ctx, m.pdict));
    try expectEqlExact(&m, get_0(&m, &.{}), FinalTerms.nil(&m.ctx));
    try expectEqlExact(&m, get_keys_0(&m, &.{}), FinalTerms.nil(&m.ctx));
}

test "LAW E3.9 worked return-contract: put/get/erase over one key (mutant 1: put returns NEW value)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try freshMachine(gpa, &atoms);
    defer m.deinit();

    const k = FinalTerms.atom(&m.ctx, try atoms.intern("k"));
    const v1 = FinalTerms.int(&m.ctx, 1);
    const v2 = FinalTerms.int(&m.ctx, 2);

    // put(k, v1) -> undefined (absent)
    try expectEqlExact(&m, put_2(&m, &.{ k, v1 }), try undefinedAtom(&m));
    // put(k, v2) -> v1 (the OLD value — mutant 1 returns v2 here instead)
    try expectEqlExact(&m, put_2(&m, &.{ k, v2 }), v1);
    // get(k) -> v2
    try expectEqlExact(&m, get_1(&m, &.{k}), v2);
    // erase(k) -> v2, and it's gone
    try expectEqlExact(&m, erase_1(&m, &.{k}), v2);
    try expectEqlExact(&m, get_1(&m, &.{k}), try undefinedAtom(&m));
}

test "LAW E3.9 exact-key: 1 and 1.0 are DISTINCT pdict keys" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try freshMachine(gpa, &atoms);
    defer m.deinit();

    const ki = FinalTerms.int(&m.ctx, 1);
    const kf = FinalTerms.float(&m.ctx, 1.0);
    const va = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const vb = FinalTerms.atom(&m.ctx, try atoms.intern("b"));

    _ = try put_2(&m, &.{ ki, va });
    _ = try put_2(&m, &.{ kf, vb });
    try expectEqlExact(&m, get_1(&m, &.{ki}), va);
    try expectEqlExact(&m, get_1(&m, &.{kf}), vb);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.mapSize(&m.ctx, m.pdict));
}

test "LAW E3.9 erase/0: returns the FULL prior list AND empties the dictionary" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try freshMachine(gpa, &atoms);
    defer m.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    _ = try put_2(&m, &.{ a, FinalTerms.int(&m.ctx, 1) });
    _ = try put_2(&m, &.{ b, FinalTerms.int(&m.ctx, 2) });

    const before_denote = try FinalTerms.denote(&m.ctx, sa, try get_0(&m, &.{}));
    const erased = try erase_0(&m, &.{});
    try std.testing.expect(spec.eqlExact(before_denote, try FinalTerms.denote(&m.ctx, sa, erased)));
    try std.testing.expectEqual(@as(usize, 0), FinalTerms.mapSize(&m.ctx, m.pdict));
    try expectEqlExact(&m, get_0(&m, &.{}), FinalTerms.nil(&m.ctx));
}

test "LAW E3.9 get_keys/1: keys whose value is =:= the argument" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try freshMachine(gpa, &atoms);
    defer m.deinit();

    const a = FinalTerms.atom(&m.ctx, try atoms.intern("a"));
    const b = FinalTerms.atom(&m.ctx, try atoms.intern("b"));
    const c = FinalTerms.atom(&m.ctx, try atoms.intern("c"));
    const v1 = FinalTerms.int(&m.ctx, 1);
    const v2 = FinalTerms.int(&m.ctx, 2);
    _ = try put_2(&m, &.{ a, v1 });
    _ = try put_2(&m, &.{ b, v2 });
    _ = try put_2(&m, &.{ c, v1 });

    const ks = try get_keys_1(&m, &.{v1});
    var n: usize = 0;
    var cur = ks;
    var saw_a = false;
    var saw_c = false;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const head = FinalTerms.listHead(&m.ctx, cur);
        if (FinalTerms.eqlExact(&m.ctx, head, a)) saw_a = true;
        if (FinalTerms.eqlExact(&m.ctx, head, c)) saw_c = true;
        cur = FinalTerms.listTail(&m.ctx, cur);
        n += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expect(saw_a and saw_c);
}

// THE CRUX: put a value, force a FULL collection of the Machine's heap
// (mirroring `gc.zig`'s "GC transparency" root list — regs/result/mailbox —
// EXTENDED with `pdict`), and verify `get` denotes the SAME value
// afterwards. Mutant 2 (pdict omitted from the root list) corrupts/frees the
// map's words during compaction — killed here.
test "LAW E3.9 GC-root interaction: pdict survives a full collection (denote(after) == denote(before))" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0xF00D9, .iterations = 20 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var m = try freshMachine(gpa, &atoms);
        defer m.deinit();

        // put a handful of random (int-key, generated-term-value) pairs.
        const n = 1 + random.uintLessThan(usize, 8);
        for (0..n) |j| {
            const k = FinalTerms.int(&m.ctx, @intCast(j));
            const v = try ta.genTerm(FinalTerms, random, &m.ctx, 3);
            _ = try put_2(&m, &.{ k, v });
        }
        const before = try FinalTerms.denote(&m.ctx, sa, try get_0(&m, &.{}));

        // force a full in-place collection, rooting EVERYTHING live
        // (regs/result/mailbox — the gc.zig "GC transparency" root set —
        // PLUS pdict, the E3.9 extension: THE crux).
        try gc_mod.collectMachineRoots(&m);

        const after = try FinalTerms.denote(&m.ctx, sa, try get_0(&m, &.{}));
        try expectLaw(spec.eqlExact(before, after), "pdict: survives a full collection (GC-root law)", cfg, i);
    }
}

test "LAW E3.9 pdict-map homomorphism: BIF-mediated state agrees with a direct map_algebra op sequence" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0x9D1C7, .iterations = 30 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();
    const key_space = 12;

    for (0..cfg.iterations) |i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        var m = try freshMachine(gpa, &atoms);
        defer m.deinit();
        var direct = try FinalTerms.mapNew(&m.ctx, &.{}, &.{});

        const steps = random.uintLessThan(usize, 40);
        for (0..steps) |_| {
            const k = FinalTerms.int(&m.ctx, @intCast(random.uintLessThan(usize, key_space)));
            if (random.boolean()) {
                const v = FinalTerms.int(&m.ctx, @as(i64, random.int(i32)));
                _ = try put_2(&m, &.{ k, v });
                direct = try FinalTerms.mapPut(&m.ctx, direct, k, v);
            } else {
                _ = try erase_1(&m, &.{k});
                direct = try FinalTerms.mapRemove(&m.ctx, direct, k);
            }
        }

        const bif_denote = try FinalTerms.denote(&m.ctx, sa, m.pdict);
        const direct_denote = try FinalTerms.denote(&m.ctx, sa, direct);
        try expectLaw(spec.eqlExact(bif_denote, direct_denote), "pdict-map homomorphism: BIF state == direct map_algebra state", cfg, i);
    }
}
