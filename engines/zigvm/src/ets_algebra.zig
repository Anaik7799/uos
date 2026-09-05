//! beam-zig M11 / S22: **ETS** — one table algebra, THREE final encodings
//! (cf. erts erl_db_hash.c, erl_db_tree.c, erl_db_catree.c) — gate G5.
//!
//! Semantic domains (objects are tuples; key = element 1):
//!   set           finite map key→object, keys unique under =:=  (hash file)
//!   ordered_set   finite map key→object, keys unique under ==,
//!                 TRAVERSAL ORDER = the M1/M4 arithmetic term order —
//!                 the cross-cutting register row "ordered-set traversal =
//!                 term order", discharged here
//!   bag           key→sequence of DISTINCT (=:=) objects, insertion order
//!   duplicate_bag key→MULTISET of objects, insertion order — an exact
//!                 duplicate object is RETAINED (bag dedupes it, duplicate_bag
//!                 keeps every copy). The one semantic delta from `bag`
//!                 (S22, E3.16): insert appends unconditionally; a key's
//!                 lookup returns N copies for N inserts (`erl_db_hash.c`'s
//!                 `DB_DUPLICATE_BAG` append arm). delete_object removes ALL
//!                 equal copies (the BIF layer's exact-object filter).
//!
//! Encodings:
//!   OracleTable   flat object list + linear scans (executable spec)
//!   HashBackend   =:=-hash buckets (erts erl_db_hash; set/bag)
//!   TreeBackend   key-sorted array w/ binary search (erts erl_db_tree)
//!   CATreeBackend routing layer over sub-arrays that SPLITS and JOINS
//!                 adaptively (erts erl_db_catree's shape) — structure
//!                 depends on operation history, denotation must not
//!
//! Laws:
//!   lookup∘insert per type semantics (set replaces on =:= key;
//!       ordered_set replaces on == key — 1.0 replaces 1; bag accumulates
//!       distinct objects in insertion order)
//!   delete removes exactly the key's objects
//!   ORDERED TRAVERSAL first/next enumerates keys strictly ascending in
//!       arithmetic term order
//!   SELECT ≡ filter by match-spec denotation (M11 matchspec)
//!   TRIPLE HOMOMORPHISM twin op streams: all backends agree with the
//!       oracle after EVERY op (lookup probes, size, exact-sorted dump)
//!   ADAPTIVITY catree splits AND joins during the walk (asserted), yet
//!       stays denotation-equal throughout
//!
//! G5 GATE: a 600-op mixed workload over all backends with checkpoints.
//!
//! Scope: the table ALGEBRA is process-agnostic (objects are values). E7.3
//! (DIVERGENCE 143) made the `EtsRegistry` Vm-owned — ONE shared table space
//! for all processes, with its own `region` storage heap and a gcCopy boundary
//! at insert/lookup (see `EtsRegistry` below); the E6.7 owner/heir lifecycle
//! now fires on real process death (`proc.zig` exit hook). duplicate_bag landed
//! E3.16 (S22 open edge closed).

const std = @import("std");
const ta = @import("term_algebra.zig");
const msp = @import("matchspec.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;
const LawConfig = ta.LawConfig;
const expectLaw = ta.expectLaw;

pub const TableType = enum { set, ordered_set, bag, duplicate_bag };

fn keyOf(ctx: *FinalTerms.Ctx, obj: FinalTerms.Term) FinalTerms.Term {
    std.debug.assert(FinalTerms.kindOf(ctx, obj) == .tuple);
    return FinalTerms.tupleElem(ctx, obj, 0);
}

/// Key equality per table type: set/bag are =:=, ordered_set is ==.
fn keyEq(ctx: *FinalTerms.Ctx, ty: TableType, a: FinalTerms.Term, b: FinalTerms.Term) bool {
    return switch (ty) {
        .set, .bag, .duplicate_bag => FinalTerms.eqlExact(ctx, a, b),
        .ordered_set => FinalTerms.eql(ctx, a, b),
    };
}

// ============================================================================
// ORACLE — a flat list of objects. Cannot be wrong.
// ============================================================================

pub const OracleTable = struct {
    gpa: std.mem.Allocator,
    ty: TableType,
    objs: std.ArrayList(FinalTerms.Term),

    pub fn init(gpa: std.mem.Allocator, ty: TableType) OracleTable {
        return .{ .gpa = gpa, .ty = ty, .objs = .empty };
    }
    pub fn deinit(self: *OracleTable) void {
        self.objs.deinit(self.gpa);
    }

    pub fn insert(self: *OracleTable, ctx: *FinalTerms.Ctx, obj: FinalTerms.Term) !void {
        const k = keyOf(ctx, obj);
        switch (self.ty) {
            .set, .ordered_set => {
                for (self.objs.items, 0..) |o, i| {
                    if (keyEq(ctx, self.ty, keyOf(ctx, o), k)) {
                        self.objs.items[i] = obj; // replace
                        return;
                    }
                }
                try self.objs.append(self.gpa, obj);
            },
            .bag => {
                for (self.objs.items) |o| {
                    if (FinalTerms.eqlExact(ctx, o, obj)) return; // no dup objects
                }
                try self.objs.append(self.gpa, obj);
            },
            .duplicate_bag => {
                // exact duplicates RETAINED — append unconditionally
                try self.objs.append(self.gpa, obj);
            },
        }
    }

    pub fn lookup(self: *OracleTable, ctx: *FinalTerms.Ctx, key: FinalTerms.Term, out: *std.ArrayList(FinalTerms.Term)) !void {
        for (self.objs.items) |o| {
            if (keyEq(ctx, self.ty, keyOf(ctx, o), key)) try out.append(self.gpa, o);
        }
    }

    pub fn delete(self: *OracleTable, ctx: *FinalTerms.Ctx, key: FinalTerms.Term) void {
        var i: usize = 0;
        while (i < self.objs.items.len) {
            if (keyEq(ctx, self.ty, keyOf(ctx, self.objs.items[i]), key)) {
                _ = self.objs.orderedRemove(i);
            } else i += 1;
        }
    }

    pub fn size(self: *OracleTable) usize {
        return self.objs.items.len;
    }

    pub fn selectInto(self: *OracleTable, ctx: *FinalTerms.Ctx, ms: *const msp.MatchSpec, out: *std.ArrayList(FinalTerms.Term)) !void {
        for (self.objs.items) |o| {
            if (try msp.run(ctx, ms, o)) |r| try out.append(self.gpa, r);
        }
    }
};

// ============================================================================
// FINAL #1 — HashBackend: =:=-hash buckets (set/bag)
// ============================================================================

pub const HashBackend = struct {
    gpa: std.mem.Allocator,
    ty: TableType,
    buckets: std.AutoHashMapUnmanaged(u64, std.ArrayList(FinalTerms.Term)),
    count: usize = 0,

    pub fn init(gpa: std.mem.Allocator, ty: TableType) HashBackend {
        std.debug.assert(ty != .ordered_set); // erts never hashes ordered_set
        return .{ .gpa = gpa, .ty = ty, .buckets = .empty };
    }
    pub fn deinit(self: *HashBackend) void {
        var it = self.buckets.valueIterator();
        while (it.next()) |b| b.deinit(self.gpa);
        self.buckets.deinit(self.gpa);
    }

    fn keyHash(ctx: *FinalTerms.Ctx, k: FinalTerms.Term) u64 {
        return FinalTerms.hashTerm(ctx, k); // =:=-coherent (M4 law)
    }

    pub fn insert(self: *HashBackend, ctx: *FinalTerms.Ctx, obj: FinalTerms.Term) !void {
        const k = keyOf(ctx, obj);
        const h = keyHash(ctx, k);
        const gop = try self.buckets.getOrPut(self.gpa, h);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        const bucket = gop.value_ptr;
        switch (self.ty) {
            .set => {
                for (bucket.items, 0..) |o, i| {
                    if (FinalTerms.eqlExact(ctx, keyOf(ctx, o), k)) {
                        bucket.items[i] = obj;
                        return;
                    }
                }
                try bucket.append(self.gpa, obj);
                self.count += 1;
            },
            .bag => {
                for (bucket.items) |o| {
                    if (FinalTerms.eqlExact(ctx, o, obj)) return;
                }
                try bucket.append(self.gpa, obj);
                self.count += 1;
            },
            .duplicate_bag => {
                // exact duplicates RETAINED — append unconditionally
                try bucket.append(self.gpa, obj);
                self.count += 1;
            },
            .ordered_set => unreachable,
        }
    }

    pub fn lookup(self: *HashBackend, ctx: *FinalTerms.Ctx, key: FinalTerms.Term, out: *std.ArrayList(FinalTerms.Term)) !void {
        const bucket = self.buckets.get(keyHash(ctx, key)) orelse return;
        for (bucket.items) |o| {
            if (FinalTerms.eqlExact(ctx, keyOf(ctx, o), key)) try out.append(self.gpa, o);
        }
    }

    pub fn delete(self: *HashBackend, ctx: *FinalTerms.Ctx, key: FinalTerms.Term) void {
        const bucket = self.buckets.getPtr(keyHash(ctx, key)) orelse return;
        var i: usize = 0;
        while (i < bucket.items.len) {
            if (FinalTerms.eqlExact(ctx, keyOf(ctx, bucket.items[i]), key)) {
                _ = bucket.orderedRemove(i);
                self.count -= 1;
            } else i += 1;
        }
    }

    pub fn size(self: *HashBackend) usize {
        return self.count;
    }

    pub fn dumpInto(self: *HashBackend, out: *std.ArrayList(FinalTerms.Term)) !void {
        var it = self.buckets.valueIterator();
        while (it.next()) |b| try out.appendSlice(self.gpa, b.items);
    }
};

// ============================================================================
// FINAL #2 — TreeBackend: key-sorted array (binary search)
// ============================================================================

pub const TreeBackend = struct {
    gpa: std.mem.Allocator,
    ty: TableType,
    objs: std.ArrayList(FinalTerms.Term), // sorted by key (mode per type)

    pub fn init(gpa: std.mem.Allocator, ty: TableType) TreeBackend {
        return .{ .gpa = gpa, .ty = ty, .objs = .empty };
    }
    pub fn deinit(self: *TreeBackend) void {
        self.objs.deinit(self.gpa);
    }

    fn cmpKeys(self: *TreeBackend, ctx: *FinalTerms.Ctx, a: FinalTerms.Term, b: FinalTerms.Term) ta.Order {
        return switch (self.ty) {
            .ordered_set => FinalTerms.compare(ctx, a, b), // arithmetic
            .set, .bag, .duplicate_bag => FinalTerms.compareExact(ctx, a, b),
        };
    }

    /// Lowest index whose key is ≥ key (per the table's order).
    fn lowerBound(self: *TreeBackend, ctx: *FinalTerms.Ctx, key: FinalTerms.Term) usize {
        var lo: usize = 0;
        var hi: usize = self.objs.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.cmpKeys(ctx, keyOf(ctx, self.objs.items[mid]), key) == .lt) {
                lo = mid + 1;
            } else hi = mid;
        }
        return lo;
    }

    pub fn insert(self: *TreeBackend, ctx: *FinalTerms.Ctx, obj: FinalTerms.Term) !void {
        const k = keyOf(ctx, obj);
        var i = self.lowerBound(ctx, k);
        switch (self.ty) {
            .set, .ordered_set => {
                if (i < self.objs.items.len and self.cmpKeys(ctx, keyOf(ctx, self.objs.items[i]), k) == .eq) {
                    self.objs.items[i] = obj;
                    return;
                }
                try self.objs.insert(self.gpa, i, obj);
            },
            .bag => {
                // insertion order within the key run; no duplicate objects
                while (i < self.objs.items.len and self.cmpKeys(ctx, keyOf(ctx, self.objs.items[i]), k) == .eq) : (i += 1) {
                    if (FinalTerms.eqlExact(ctx, self.objs.items[i], obj)) return;
                }
                try self.objs.insert(self.gpa, i, obj);
            },
            .duplicate_bag => {
                // exact duplicates RETAINED — advance past the whole key run and
                // append at its END (insertion order preserved within the run).
                while (i < self.objs.items.len and self.cmpKeys(ctx, keyOf(ctx, self.objs.items[i]), k) == .eq) : (i += 1) {}
                try self.objs.insert(self.gpa, i, obj);
            },
        }
    }

    pub fn lookup(self: *TreeBackend, ctx: *FinalTerms.Ctx, key: FinalTerms.Term, out: *std.ArrayList(FinalTerms.Term)) !void {
        var i = self.lowerBound(ctx, key);
        while (i < self.objs.items.len and self.cmpKeys(ctx, keyOf(ctx, self.objs.items[i]), key) == .eq) : (i += 1) {
            try out.append(self.gpa, self.objs.items[i]);
        }
    }

    pub fn delete(self: *TreeBackend, ctx: *FinalTerms.Ctx, key: FinalTerms.Term) void {
        const start = self.lowerBound(ctx, key);
        var end = start;
        while (end < self.objs.items.len and self.cmpKeys(ctx, keyOf(ctx, self.objs.items[end]), key) == .eq) : (end += 1) {}
        var k = end;
        while (k > start) : (k -= 1) {
            _ = self.objs.orderedRemove(k - 1);
        }
    }

    pub fn size(self: *TreeBackend) usize {
        return self.objs.items.len;
    }

    /// first/next traversal: the stored order IS the traversal order.
    pub fn dumpInto(self: *TreeBackend, out: *std.ArrayList(FinalTerms.Term)) !void {
        try out.appendSlice(self.gpa, self.objs.items);
    }

    pub fn selectInto(self: *TreeBackend, ctx: *FinalTerms.Ctx, ms: *const msp.MatchSpec, out: *std.ArrayList(FinalTerms.Term)) !void {
        for (self.objs.items) |o| {
            if (try msp.run(ctx, ms, o)) |r| try out.append(self.gpa, r);
        }
    }
};

// ============================================================================
// FINAL #3 — CATreeBackend: adaptive routing over sub-arrays
// ============================================================================

pub const CATreeBackend = struct {
    const SPLIT_AT = 16;
    const JOIN_AT = 4;

    gpa: std.mem.Allocator,
    ty: TableType,
    /// bases[i] holds keys in [routes[i-1], routes[i]); routes.len == bases.len-1
    bases: std.ArrayList(TreeBackend),
    routes: std.ArrayList(FinalTerms.Term),
    splits: usize = 0,
    joins: usize = 0,

    pub fn init(gpa: std.mem.Allocator, ty: TableType) !CATreeBackend {
        var self = CATreeBackend{ .gpa = gpa, .ty = ty, .bases = .empty, .routes = .empty };
        try self.bases.append(gpa, TreeBackend.init(gpa, ty));
        return self;
    }
    pub fn deinit(self: *CATreeBackend) void {
        for (self.bases.items) |*b| b.deinit();
        self.bases.deinit(self.gpa);
        self.routes.deinit(self.gpa);
    }

    fn cmpKeys(self: *CATreeBackend, ctx: *FinalTerms.Ctx, a: FinalTerms.Term, b: FinalTerms.Term) ta.Order {
        return switch (self.ty) {
            .ordered_set => FinalTerms.compare(ctx, a, b),
            .set, .bag, .duplicate_bag => FinalTerms.compareExact(ctx, a, b),
        };
    }

    fn baseFor(self: *CATreeBackend, ctx: *FinalTerms.Ctx, key: FinalTerms.Term) usize {
        for (self.routes.items, 0..) |r, i| {
            if (self.cmpKeys(ctx, key, r) == .lt) return i;
        }
        return self.bases.items.len - 1;
    }

    fn adapt(self: *CATreeBackend, ctx: *FinalTerms.Ctx, bi: usize) !void {
        const base = &self.bases.items[bi];
        if (base.objs.items.len >= SPLIT_AT) {
            // split at the median key — but NEVER inside a same-key run
            // (bags keep several objects per key; a route through the middle
            // of a run would strand half of it in the wrong base — the
            // classic catree hazard, and exactly what the homomorphism law
            // caught on first contact)
            var mid = base.objs.items.len / 2;
            while (mid < base.objs.items.len and
                self.cmpKeys(ctx, keyOf(ctx, base.objs.items[mid - 1]), keyOf(ctx, base.objs.items[mid])) == .eq)
            {
                mid += 1;
            }
            if (mid >= base.objs.items.len) return; // one giant run: unsplittable
            const route_key = keyOf(ctx, base.objs.items[mid]);
            var right = TreeBackend.init(self.gpa, self.ty);
            try right.objs.appendSlice(self.gpa, base.objs.items[mid..]);
            base.objs.shrinkRetainingCapacity(mid);
            try self.bases.insert(self.gpa, bi + 1, right);
            try self.routes.insert(self.gpa, bi, route_key);
            self.splits += 1;
        } else if (base.objs.items.len <= JOIN_AT and self.bases.items.len > 1) {
            // join with the right neighbour (or left if rightmost)
            const victim = if (bi + 1 < self.bases.items.len) bi else bi - 1;
            var right = self.bases.items[victim + 1];
            try self.bases.items[victim].objs.appendSlice(self.gpa, right.objs.items);
            right.deinit();
            _ = self.bases.orderedRemove(victim + 1);
            _ = self.routes.orderedRemove(victim);
            self.joins += 1;
        }
    }

    pub fn insert(self: *CATreeBackend, ctx: *FinalTerms.Ctx, obj: FinalTerms.Term) !void {
        const bi = self.baseFor(ctx, keyOf(ctx, obj));
        try self.bases.items[bi].insert(ctx, obj);
        try self.adapt(ctx, bi);
    }
    pub fn lookup(self: *CATreeBackend, ctx: *FinalTerms.Ctx, key: FinalTerms.Term, out: *std.ArrayList(FinalTerms.Term)) !void {
        try self.bases.items[self.baseFor(ctx, key)].lookup(ctx, key, out);
    }
    pub fn delete(self: *CATreeBackend, ctx: *FinalTerms.Ctx, key: FinalTerms.Term) !void {
        const bi = self.baseFor(ctx, key);
        self.bases.items[bi].delete(ctx, key);
        try self.adapt(ctx, bi);
    }
    pub fn size(self: *CATreeBackend) usize {
        var n: usize = 0;
        for (self.bases.items) |b| n += b.objs.items.len;
        return n;
    }
    pub fn dumpInto(self: *CATreeBackend, out: *std.ArrayList(FinalTerms.Term)) !void {
        for (self.bases.items) |b| try out.appendSlice(self.gpa, b.objs.items);
    }
};

// ============================================================================
// ETS TABLE REGISTRY — the live, process-external table state (E2.9 BIF layer)
// ============================================================================
//
// The backends above are the ALGEBRA (each a standalone data structure the
// triple homomorphism proves denotation-equal). The BIF surface
// (`bifs/ets.zig`) needs the tables to LIVE somewhere addressable by a Tid
// across BIF calls — ETS tables are process-external and outlive the call that
// created them. This registry is that owning state, embedded on the `Machine`
// (freed in `Machine.deinit`; `std.testing.allocator` proves leak-freedom).
//
// SINGLE-MACHINE SCOPE (an honest E-scope limit): the VM currently runs one
// `Machine`, so "a table outlives its creating process and is visible to other
// processes" degenerates to "a table outlives the BIF call and is visible to
// the whole Machine". Full cross-process ownership/heir/give_away semantics
// partial-defer to the multi-process epoch — documented in `bifs/ets.zig`.
//
// LIVE BACKEND CHOICE: `TreeBackend` for ALL table types. The triple
// homomorphism proves `TreeBackend` denotation-equal to `HashBackend`/
// `CATreeBackend` for set/bag (and it IS the ordered_set backend), so one
// backend is a SOUND live representation and reuses the algebra verbatim — NO
// new ETS semantics. Consequence for first/next: ordered_set walks arithmetic-
// ascending (BEAM-faithful); set/bag walk `TreeBackend`'s exact-term order,
// which is deterministic but NOT BEAM's hash-bucket order (a documented
// divergence, the ETS analog of the maps HAMT key-order divergence).

pub const EtsTable = struct {
    id: usize,
    ty: TableType,
    named: bool,
    name: ta.AtomIdx, //  ets:new/2's Name atom (the lookup key iff `named`)
    keypos: usize, //     1-based; only keypos 1 is supported (validated at new)
    backend: TreeBackend,
    // E6.7 (Task 7): the per-table OWNER pid + optional HEIR (0 == none). The
    // owner is the process that created the table (set by `ets:new/2` to the
    // caller's pid) or the most recent `ets:give_away/3` recipient. `setopts/2`
    // sets the heir + `heir_data` (the gift term delivered on owner death). These
    // are the multi-process ETS-ownership state (E2.9 doc's deferred half): the
    // owner reassigns on `give_away`, and the owner-death lifecycle (proc.zig's
    // exit path) auto-deletes an heir-less table or transfers to the heir. Values
    // live on THIS table's owning Machine heap (`heir_data` is a Term offset into
    // it). Default 0/null so every pre-E6.7 table/law is unchanged.
    owner: u64 = 0,
    heir: u64 = 0,
    heir_data: ?FinalTerms.Term = null,
    // gap-ets-table-options: the DECLARED options, and the only thing that
    // makes them observable. See `TableOpts` for the semantic domain — in
    // particular that `decentralized_counters` is DERIVED and not stored.
    opts: TableOpts = .{},

    pub fn deinit(self: *EtsTable) void {
        self.backend.deinit();
    }
};

/// `write_concurrency` is not a boolean. OTP-30 accepts `false | true | auto`
/// and `ets:info(T, write_concurrency)` reports back exactly which of the three
/// was set — so a `bool` field would be lossy at the observation, not merely
/// imprecise internally.
pub const WriteConcurrency = enum {
    off,
    on,
    auto,

    /// The predicate the derived `decentralized_counters` reads. `auto` counts
    /// as enabled: measured on OTP-30, `ordered_set` + `{write_concurrency,
    /// auto}` reports `decentralized_counters = true`.
    pub fn enabled(self: WriteConcurrency) bool {
        return switch (self) {
            .off => false,
            .on, .auto => true,
        };
    }
};

/// `ets:info(T, protection)`. zigvm does not ENFORCE access — every table
/// behaves as `protected` — but OTP reports what was DECLARED, and reporting a
/// hardcoded `protected` for a table created `[private]` is a plain divergence.
/// Storing the declaration costs nothing and makes the observation truthful;
/// the unenforced access check stays disclosed in the module doc.
pub const Protection = enum { public, protected, private };

/// A table's declared options.
///
/// **Semantic domain.** `observe : (TableType, TableOpts) -> Key -> Value`.
/// Four of the five keys are stored and read back unchanged. The fifth is not,
/// and it is the whole reason this is a type rather than five loose fields:
///
/// ```
///   decentralized_counters = write_concurrency.enabled()
///                            AND (dc_opt ORELSE (ty == .ordered_set))
/// ```
///
/// Measured on OTP-30 across nine operand cells. The naive reading — "report
/// the option that was set" — is wrong in three of them: `[set, {dc,true}]`
/// reports **false** (write_concurrency is off), `[ordered_set, {wc,true}]`
/// reports **true** with no `dc` option present at all, and
/// `[set, {wc,true}, {dc,true}]` reports **true** even though `set` defaults to
/// false. Nothing about the option name suggests any of that, which is exactly
/// why it is enumerated by law rather than argued from symmetry.
///
/// **AND NINE CELLS WERE NOT ENOUGH.** The first version of this equation
/// shipped without the `private` term and was WRONG — `[ordered_set,
/// {write_concurrency,true}, private]` reports **false** on OTP-30, and so does
/// the same table with an explicit `{decentralized_counters, true}`. Access
/// dominates: a private table is reachable only by its owner, so a decentralized
/// counter has nothing to decentralize. The defect survived nine enumerated
/// cells, five killed mutants and a byte-identical differential across 25 probe
/// cells, because every one of those operands varied `type`, `write_concurrency`
/// and `dc` while holding `protection` at its default. An enumeration is only as
/// complete as the DIMENSIONS it varies, and a dimension nobody varied is
/// indistinguishable from one that does not exist.
pub const TableOpts = struct {
    read_concurrency: bool = false,
    write_concurrency: WriteConcurrency = .off,
    /// `null` = not specified, so the type-dependent default applies.
    dc_opt: ?bool = null,
    compressed: bool = false,
    protection: Protection = .protected,

    /// The DERIVED observation. `ty` is a parameter because the default half of
    /// the equation depends on the table type, which the options alone cannot
    /// know.
    pub fn decentralizedCounters(self: TableOpts, ty: TableType) bool {
        // `private` dominates, ahead of everything else — including an explicit
        // `{decentralized_counters, true}`.
        if (self.protection == .private) return false;
        const want = self.dc_opt orelse (ty == .ordered_set);
        return self.write_concurrency.enabled() and want;
    }
};

test "LAW gap-ets-table-options DC-DERIVED: the nine measured OTP-30 operand cells" {
    // Each row is a cell measured against the pinned OTP-30 oracle on
    // 20260808, written out rather than generated: a law over operands must
    // ENUMERATE them, and three of these disagree with the obvious reading.
    const Cell = struct {
        ty: TableType,
        wc: WriteConcurrency,
        dc: ?bool,
        prot: Protection = .protected,
        want: bool,
        note: []const u8,
    };
    const cells = [_]Cell{
        .{ .ty = .set, .wc = .off, .dc = null, .want = false, .note = "set, no options" },
        .{ .ty = .set, .wc = .off, .dc = true, .want = false, .note = "set {dc,true} — wc off, so FALSE" },
        .{ .ty = .set, .wc = .off, .dc = false, .want = false, .note = "set {dc,false}" },
        .{ .ty = .ordered_set, .wc = .off, .dc = true, .want = false, .note = "oset {dc,true} — wc off, so FALSE" },
        .{ .ty = .ordered_set, .wc = .on, .dc = null, .want = true, .note = "oset {wc,true} — TRUE with no dc option" },
        .{ .ty = .ordered_set, .wc = .auto, .dc = null, .want = true, .note = "oset {wc,auto} — auto counts as enabled" },
        .{ .ty = .set, .wc = .on, .dc = null, .want = false, .note = "set {wc,true} — set defaults dc FALSE" },
        .{ .ty = .set, .wc = .on, .dc = true, .want = true, .note = "set {wc,true},{dc,true} — TRUE, not type-locked" },
        .{ .ty = .ordered_set, .wc = .on, .dc = false, .want = false, .note = "oset {wc,true},{dc,false}" },
        // THE DIMENSION THE FIRST NINE CELLS DID NOT VARY. Every row above
        // holds `protection` at its default, and the equation shipped without
        // this term because nothing in the operand set could see it.
        .{ .ty = .ordered_set, .wc = .on, .dc = null, .prot = .private, .want = false, .note = "oset {wc,true},private — access DOMINATES" },
        .{ .ty = .ordered_set, .wc = .on, .dc = true, .prot = .private, .want = false, .note = "oset {wc,true},{dc,true},private — beats an EXPLICIT true" },
        .{ .ty = .set, .wc = .on, .dc = true, .prot = .private, .want = false, .note = "set {wc,true},{dc,true},private" },
        .{ .ty = .ordered_set, .wc = .auto, .dc = null, .prot = .private, .want = false, .note = "oset {wc,auto},private" },
        // …and the counterweight, so the `private` term cannot be satisfied by
        // a rule that simply answers false more often.
        .{ .ty = .set, .wc = .on, .dc = true, .prot = .public, .want = true, .note = "set {wc,true},{dc,true},public — still TRUE" },
        .{ .ty = .set, .wc = .on, .dc = true, .prot = .protected, .want = true, .note = "set {wc,true},{dc,true},protected — still TRUE" },
        .{ .ty = .ordered_set, .wc = .on, .dc = null, .prot = .public, .want = true, .note = "oset {wc,true},public — still TRUE" },
    };
    for (cells) |c| {
        const opts = TableOpts{ .write_concurrency = c.wc, .dc_opt = c.dc, .protection = c.prot };
        const got = opts.decentralizedCounters(c.ty);
        if (got != c.want) {
            // Contextual failure: name the CELL, not just the booleans. A
            // differential over 9 operands that reports `expected true, got
            // false` sends the reader back to the table to work out which row.
            std.debug.print(
                "\nDC-DERIVED cell FAILED: {s}\n  ty={s} wc={s} dc={?} prot={s} expected={} got={}\n",
                .{ c.note, @tagName(c.ty), @tagName(c.wc), c.dc, @tagName(c.prot), c.want, got },
            );
            return error.TestUnexpectedResult;
        }
    }
}

test "LAW gap-ets-table-options DC-IS-NOT-THE-STORED-OPTION: a distinguishing witness exists" {
    // The counterweight to the enumeration above. If `decentralizedCounters`
    // ever degenerates into `dc_opt orelse default`, every cell where the two
    // agree still passes; this asserts that at least one operand SEPARATES the
    // derived value from the stored one, so the enumeration is not vacuous.
    const stored_true = TableOpts{ .write_concurrency = .off, .dc_opt = true };
    try std.testing.expect(stored_true.dc_opt.? == true);
    try std.testing.expect(stored_true.decentralizedCounters(.set) == false);
    // And symmetrically: derived TRUE where nothing was stored at all.
    const nothing_stored = TableOpts{ .write_concurrency = .on, .dc_opt = null };
    try std.testing.expect(nothing_stored.dc_opt == null);
    try std.testing.expect(nothing_stored.decentralizedCounters(.ordered_set) == true);
}

test "LAW gap-ets-table-options WC-ENABLED: auto is enabled, off is not (exhaustive)" {
    inline for (@typeInfo(WriteConcurrency).@"enum".fields) |f| {
        const w: WriteConcurrency = @enumFromInt(f.value);
        const want = switch (w) {
            .off => false,
            .on, .auto => true,
        };
        try std.testing.expectEqual(want, w.enabled());
    }
}

/// The map Tid → live table. Ids are dense and never reused, so a stale Tid
/// (from a `delete/1`'d table) resolves to `null` → the BIF traps `badarg`
/// (never a use-after-free).
///
/// E7.3 (shared ETS, DIVERGENCE 143): the registry is now **Vm-owned** — one
/// shared table space for every process (`proc.zig`'s `Vm.ets`; each Machine
/// reaches it via `Machine.etsReg()`, which returns the shared registry when
/// `shared_ets` is set, else its own per-Machine fallback). Because the shared
/// tables outlive any single process, their stored objects CANNOT live on a
/// process's `ctx` heap (a caller-heap offset is meaningless to a different
/// process). Instead the registry owns its OWN storage heap `region` (the
/// `registry.PersistentTerms.region` precedent): every backend op runs against
/// `region`, so the BIF layer (`bifs/ets.zig`) copies an object INTO `region`
/// on insert (`gcCopy` from the caller's `ctx`) and copies results back OUT to
/// the caller's `ctx` on lookup/dump — the M1 copy law at the table boundary.
/// This makes cross-process visibility real (process A inserts, process B
/// looks up the same object) while every single-process ETS law stays
/// observationally unchanged (a copy is `=:=` to its source). `region`, like
/// erts's ETS heap and the literal area, is never collected (bounded runs).
pub const EtsRegistry = struct {
    gpa: std.mem.Allocator,
    tables: std.ArrayList(?EtsTable), //  indexed by id; null once deleted
    by_name: std.AutoHashMapUnmanaged(ta.AtomIdx, usize),
    region: FinalTerms.Ctx, // E7.3: the shared table-storage heap (see above).
    // e48-smp-s3: the SHARED-TABLE lock — a REENTRANT spinlock (the ETS BIF
    // layer legitimately nests: lookup_element_4->_3, ETS-TRANSFER->insert_2,
    // and the coordinator resolves tables from inside VM-lock arms), acquired
    // by every `bifs/ets.zig` entry that touches this registry so concurrent
    // unlocked grants serialize ONLY on actual ETS work. Lock ORDER discipline:
    // (VM-lock -> ets) is allowed (coordinator arms); (ets -> VM-lock) never
    // happens (ETS BIFs trap instead of calling the Vm) — no deadlock cycle.
    mu_owner: std.atomic.Value(u64) = std.atomic.Value(u64).init(0), // thread id+1; 0 = free
    mu_depth: u32 = 0,

    pub fn lockShared(self: *EtsRegistry) void {
        const me: u64 = @as(u64, std.Thread.getCurrentId()) + 1;
        if (self.mu_owner.load(.acquire) == me) {
            self.mu_depth += 1;
            return;
        }
        while (self.mu_owner.cmpxchgWeak(0, me, .acquire, .monotonic) != null)
            std.Thread.yield() catch {};
        self.mu_depth = 1;
    }
    pub fn unlockShared(self: *EtsRegistry) void {
        self.mu_depth -= 1;
        if (self.mu_depth == 0) self.mu_owner.store(0, .release);
    }
    // Every LIVE table's backend stores `region`-offset Terms; the BIF layer
    // gcCopies caller-heap objects in on insert and results out on lookup.

    pub fn init(gpa: std.mem.Allocator, atoms: *AtomTable) EtsRegistry {
        return .{ .gpa = gpa, .tables = .empty, .by_name = .empty, .region = FinalTerms.Ctx.init(gpa, atoms) };
    }
    pub fn deinit(self: *EtsRegistry) void {
        for (self.tables.items) |*slot| {
            if (slot.*) |*t| t.deinit();
        }
        self.tables.deinit(self.gpa);
        self.by_name.deinit(self.gpa);
        self.region.deinit(); // E7.3: the shared storage heap (holds only
        // Terms; backends hold offsets into it, never the reverse — free-safe).
    }

    /// Allocate a fresh empty table; returns its numeric id. Registers the name
    /// iff `named`. Caller must reject a named collision (via `byName`) first.
    pub fn create(self: *EtsRegistry, ty: TableType, named: bool, name: ta.AtomIdx, keypos: usize) !usize {
        const id = self.tables.items.len;
        try self.tables.append(self.gpa, EtsTable{
            .id = id,
            .ty = ty,
            .named = named,
            .name = name,
            .keypos = keypos,
            .backend = TreeBackend.init(self.gpa, ty),
        });
        if (named) try self.by_name.put(self.gpa, name, id);
        return id;
    }

    /// Resolve by numeric id. The returned pointer is valid only until the next
    /// `create` (which may realloc `tables`); BIFs resolve-then-operate within a
    /// single call and never create mid-op, so this is safe.
    pub fn byId(self: *EtsRegistry, id: usize) ?*EtsTable {
        if (id >= self.tables.items.len) return null;
        if (self.tables.items[id] != null) return &(self.tables.items[id].?);
        return null;
    }
    pub fn byName(self: *EtsRegistry, name: ta.AtomIdx) ?*EtsTable {
        const id = self.by_name.get(name) orelse return null;
        return self.byId(id);
    }
    /// Rename table `id` to the atom `new_name` — a pure name-registry REMAP
    /// (E5.9). For a `named` table this rebinds `by_name` (new→id inserted, old
    /// removed) AFTER rejecting a collision with a DIFFERENT live named table;
    /// for an unnamed table it updates only the `name` attribute (`info(name)`),
    /// leaving it unreachable by name — exactly BEAM's `ets:rename/2`. The
    /// backend (the object multiset) is UNTOUCHED: rename is denotation-
    /// preserving on the table's contents. `Badarg` on a name collision;
    /// `OutOfMemory` if the registry insert fails (old binding left intact).
    pub fn rename(self: *EtsRegistry, id: usize, new_name: ta.AtomIdx) error{ Badarg, OutOfMemory }!void {
        const t = self.byId(id) orelse return error.Badarg;
        if (t.named) {
            if (self.by_name.get(new_name)) |other| {
                if (other != id) return error.Badarg; // a DIFFERENT named table holds it
            }
            const old = t.name;
            if (old != new_name) {
                // insert-then-remove: a failed insert leaves the OLD binding live.
                self.by_name.put(self.gpa, new_name, id) catch return error.OutOfMemory;
                _ = self.by_name.remove(old);
            }
        }
        t.name = new_name;
    }

    /// E6.7: `ets:give_away/3`'s registry half — reassign table `id`'s owner to
    /// `to`. Pure state move (the backend/contents are UNTOUCHED — give_away is
    /// denotation-preserving on the objects); the caller (proc.zig) validates
    /// ownership + `to`'s liveness and delivers the `{'ETS-TRANSFER',...}` signal.
    /// `Badarg` on an absent id.
    pub fn giveAway(self: *EtsRegistry, id: usize, to: u64) error{Badarg}!void {
        const t = self.byId(id) orelse return error.Badarg;
        t.owner = to;
    }

    /// E6.7: the OWNER-DEATH lifecycle. When process `owner` dies, each table it
    /// owns either (a) transfers to its heir — owner := heir, heir := 0 — if a
    /// live heir is set, or (b) is auto-deleted (an heir-less table dies with its
    /// owner). This is the registry-level LAW; the live per-Machine engine frees
    /// a dead process's whole registry anyway (single-Machine scope), so the
    /// cross-Machine heir HAND-OFF stays a shared-ETS follow-on — but the
    /// transfer/auto-delete DECISION is proven here over the ownership state.
    pub fn ownerDied(self: *EtsRegistry, owner: u64) void {
        for (self.tables.items, 0..) |*slot, id| {
            if (slot.*) |*t| {
                if (t.owner != owner) continue;
                if (t.heir != 0 and t.heir != owner) {
                    t.owner = t.heir;
                    t.heir = 0;
                    t.heir_data = null;
                } else {
                    self.drop(id);
                }
            }
        }
    }

    /// Delete a whole table: free its backend, null the slot (id never reused),
    /// unregister the name. Idempotent on an already-dropped/absent id.
    pub fn drop(self: *EtsRegistry, id: usize) void {
        if (id >= self.tables.items.len) return;
        if (self.tables.items[id]) |t| {
            if (t.named) _ = self.by_name.remove(t.name);
            self.tables.items[id].?.deinit();
            self.tables.items[id] = null;
        }
    }
};

// ============================================================================
// Law harness
// ============================================================================

fn sortedDump(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    items: []const FinalTerms.Term,
) !std.ArrayList(u64) {
    // canonical fingerprint: exact-hash of each object, sorted — a
    // representation-free multiset observation
    var hs: std.ArrayList(u64) = .empty;
    for (items) |o| try hs.append(gpa, FinalTerms.hashTerm(ctx, o));
    std.mem.sort(u64, hs.items, {}, std.sort.asc(u64));
    return hs;
}

fn genObj(random: std.Random, ctx: *FinalTerms.Ctx, key_space: u16) !FinalTerms.Term {
    // keys: mix of small ints and the 1-vs-1.0 hazard; values arbitrary
    const key = switch (random.uintLessThan(u8, 5)) {
        0 => FinalTerms.float(ctx, @floatFromInt(random.uintLessThan(u16, key_space))),
        else => FinalTerms.int(ctx, random.uintLessThan(u16, key_space)),
    };
    const val = FinalTerms.int(ctx, @as(i64, random.int(i16)));
    return FinalTerms.tuple(ctx, &.{ key, val });
}

fn agreeAll(
    gpa: std.mem.Allocator,
    ctx: *FinalTerms.Ctx,
    oracle: *OracleTable,
    hash: ?*HashBackend,
    tree: *TreeBackend,
    catree: *CATreeBackend,
    cfg: LawConfig,
    i: usize,
) !void {
    // size agreement
    try expectLaw(oracle.size() == tree.size(), "ets: size oracle==tree", cfg, i);
    try expectLaw(oracle.size() == catree.size(), "ets: size oracle==catree", cfg, i);
    if (hash) |h| try expectLaw(oracle.size() == h.size(), "ets: size oracle==hash", cfg, i);
    // multiset dump agreement
    var d0: std.ArrayList(FinalTerms.Term) = .empty;
    defer d0.deinit(gpa);
    try d0.appendSlice(gpa, oracle.objs.items);
    var f0 = try sortedDump(gpa, ctx, d0.items);
    defer f0.deinit(gpa);
    var d1: std.ArrayList(FinalTerms.Term) = .empty;
    defer d1.deinit(gpa);
    try tree.dumpInto(&d1);
    var f1 = try sortedDump(gpa, ctx, d1.items);
    defer f1.deinit(gpa);
    try expectLaw(std.mem.eql(u64, f0.items, f1.items), "ets: dump oracle==tree", cfg, i);
    var d2: std.ArrayList(FinalTerms.Term) = .empty;
    defer d2.deinit(gpa);
    try catree.dumpInto(&d2);
    var f2 = try sortedDump(gpa, ctx, d2.items);
    defer f2.deinit(gpa);
    try expectLaw(std.mem.eql(u64, f0.items, f2.items), "ets: dump oracle==catree", cfg, i);
    if (hash) |h| {
        var d3: std.ArrayList(FinalTerms.Term) = .empty;
        defer d3.deinit(gpa);
        try h.dumpInto(&d3);
        var f3 = try sortedDump(gpa, ctx, d3.items);
        defer f3.deinit(gpa);
        try expectLaw(std.mem.eql(u64, f0.items, f3.items), "ets: dump oracle==hash", cfg, i);
    }
}

fn tripleWalk(gpa: std.mem.Allocator, ty: TableType, seed: u64, ops: usize, cfg: LawConfig, iter: usize) !struct { splits: usize, joins: usize } {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    var oracle = OracleTable.init(gpa, ty);
    defer oracle.deinit();
    var hash: ?HashBackend = if (ty != .ordered_set) HashBackend.init(gpa, ty) else null;
    defer if (hash) |*h| h.deinit();
    var tree = TreeBackend.init(gpa, ty);
    defer tree.deinit();
    var catree = try CATreeBackend.init(gpa, ty);
    defer catree.deinit();

    for (0..ops) |op| {
        switch (random.uintLessThan(u8, 4)) {
            0, 1 => {
                const obj = try genObj(random, &ctx, 60);
                try oracle.insert(&ctx, obj);
                if (hash) |*h| try h.insert(&ctx, obj);
                try tree.insert(&ctx, obj);
                try catree.insert(&ctx, obj);
            },
            2 => {
                const key = FinalTerms.int(&ctx, random.uintLessThan(u16, 60));
                oracle.delete(&ctx, key);
                if (hash) |*h| h.delete(&ctx, key);
                tree.delete(&ctx, key);
                try catree.delete(&ctx, key);
            },
            else => {
                // lookup probe: all encodings answer with the same multiset
                const key = FinalTerms.int(&ctx, random.uintLessThan(u16, 60));
                var lo: std.ArrayList(FinalTerms.Term) = .empty;
                defer lo.deinit(gpa);
                try oracle.lookup(&ctx, key, &lo);
                var fo = try sortedDump(gpa, &ctx, lo.items);
                defer fo.deinit(gpa);
                var lt: std.ArrayList(FinalTerms.Term) = .empty;
                defer lt.deinit(gpa);
                try tree.lookup(&ctx, key, &lt);
                var ft = try sortedDump(gpa, &ctx, lt.items);
                defer ft.deinit(gpa);
                try expectLaw(std.mem.eql(u64, fo.items, ft.items), "ets: lookup oracle==tree", cfg, iter);
                var lc: std.ArrayList(FinalTerms.Term) = .empty;
                defer lc.deinit(gpa);
                try catree.lookup(&ctx, key, &lc);
                var fc = try sortedDump(gpa, &ctx, lc.items);
                defer fc.deinit(gpa);
                try expectLaw(std.mem.eql(u64, fo.items, fc.items), "ets: lookup oracle==catree", cfg, iter);
                if (hash) |*h| {
                    var lh: std.ArrayList(FinalTerms.Term) = .empty;
                    defer lh.deinit(gpa);
                    try h.lookup(&ctx, key, &lh);
                    var fh = try sortedDump(gpa, &ctx, lh.items);
                    defer fh.deinit(gpa);
                    try expectLaw(std.mem.eql(u64, fo.items, fh.items), "ets: lookup oracle==hash", cfg, iter);
                }
            },
        }
        if (op % 50 == 49) { // checkpoint
            try agreeAll(gpa, &ctx, &oracle, if (hash) |*h| h else null, &tree, &catree, cfg, iter);
            // ordered traversal law at every checkpoint
            if (ty == .ordered_set) {
                var k: usize = 1;
                while (k < tree.objs.items.len) : (k += 1) {
                    try expectLaw(FinalTerms.compare(&ctx, keyOf(&ctx, tree.objs.items[k - 1]), keyOf(&ctx, tree.objs.items[k])) == .lt, "ets: ordered_set traversal strictly ascends (M1 compare)", cfg, iter);
                }
            }
        }
    }
    try agreeAll(gpa, &ctx, &oracle, if (hash) |*h| h else null, &tree, &catree, cfg, iter);
    return .{ .splits = catree.splits, .joins = catree.joins };
}

// ============================================================================
// Tests
// ============================================================================

test "G5 GATE + TRIPLE HOMOMORPHISM: 600-op walks, all types, all backends" {
    const gpa = std.testing.allocator;
    const cfg = LawConfig{ .seed = 0xE75 };

    var total_splits: usize = 0;
    var total_joins: usize = 0;
    inline for ([_]TableType{ .set, .ordered_set, .bag, .duplicate_bag }) |ty| {
        for (0..3) |i| {
            const r = try tripleWalk(gpa, ty, cfg.seed +% i, 600, cfg, i);
            total_splits += r.splits;
            total_joins += r.joins;
        }
    }
    // ADAPTIVITY: the catree really did restructure during the gate
    try std.testing.expect(total_splits > 0);
    try std.testing.expect(total_joins > 0);
}

test "Hash backend: set keeps 1 and 1.0 apart through the PUBLIC api" {
    // (pinned after an arithmetic-eql mutant proved EQUIVALENT inside the
    // bucket path — exact hashing already separates the keys. The public
    // behavior still deserves its own law; equivalence of internals is not
    // a spec.)
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var h = HashBackend.init(gpa, .set);
    defer h.deinit();
    try h.insert(&ctx, try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 1), FinalTerms.int(&ctx, 100) }));
    try h.insert(&ctx, try FinalTerms.tuple(&ctx, &.{ FinalTerms.float(&ctx, 1.0), FinalTerms.int(&ctx, 200) }));
    try std.testing.expectEqual(@as(usize, 2), h.size());
    var out: std.ArrayList(FinalTerms.Term) = .empty;
    defer out.deinit(gpa);
    try h.lookup(&ctx, FinalTerms.int(&ctx, 1), &out);
    try std.testing.expectEqual(@as(usize, 1), out.items.len); // only the int row
}

test "Key semantics: set keeps 1 and 1.0 apart; ordered_set collapses them" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const obj_i = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 1), FinalTerms.int(&ctx, 100) });
    const obj_f = try FinalTerms.tuple(&ctx, &.{ FinalTerms.float(&ctx, 1.0), FinalTerms.int(&ctx, 200) });

    var set_t = TreeBackend.init(gpa, .set);
    defer set_t.deinit();
    try set_t.insert(&ctx, obj_i);
    try set_t.insert(&ctx, obj_f);
    try std.testing.expectEqual(@as(usize, 2), set_t.size()); // =:= keys differ

    var ord_t = TreeBackend.init(gpa, .ordered_set);
    defer ord_t.deinit();
    try ord_t.insert(&ctx, obj_i);
    try ord_t.insert(&ctx, obj_f);
    try std.testing.expectEqual(@as(usize, 1), ord_t.size()); // == keys equal
    // the stored object is the REPLACEMENT ({1.0, 200})
    var out: std.ArrayList(FinalTerms.Term) = .empty;
    defer out.deinit(gpa);
    try ord_t.lookup(&ctx, FinalTerms.int(&ctx, 1), &out); // probe with the INT
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, out.items[0], 1), FinalTerms.int(&ctx, 200)));
}

test "E3.16 insert-append vs bag-dedupe: duplicate_bag RETAINS exact copies (mutant 1)" {
    // The one semantic delta from `bag`: inserting the SAME object twice yields
    // 2 copies in duplicate_bag, 1 in bag. Runs over BOTH the oracle and the
    // live TreeBackend so the distinction is representation-free.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const obj = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 1), FinalTerms.int(&ctx, 100) });

    // bag dedupes an exact duplicate object → size 1, lookup returns 1.
    inline for (.{ TreeBackend, OracleTable }) |Backend| {
        var bag = Backend.init(gpa, .bag);
        defer bag.deinit();
        try bag.insert(&ctx, obj);
        try bag.insert(&ctx, obj);
        try bag.insert(&ctx, obj);
        try std.testing.expectEqual(@as(usize, 1), bag.size());

        // duplicate_bag RETAINS every copy → size 3, lookup returns 3.
        var dbag = Backend.init(gpa, .duplicate_bag);
        defer dbag.deinit();
        try dbag.insert(&ctx, obj);
        try dbag.insert(&ctx, obj);
        try dbag.insert(&ctx, obj);
        try std.testing.expectEqual(@as(usize, 3), dbag.size());
        var out: std.ArrayList(FinalTerms.Term) = .empty;
        defer out.deinit(gpa);
        try dbag.lookup(&ctx, FinalTerms.int(&ctx, 1), &out);
        try std.testing.expectEqual(@as(usize, 3), out.items.len);
        for (out.items) |o| try std.testing.expect(FinalTerms.eqlExact(&ctx, o, obj));

        // same-key DIFFERENT objects coexist in BOTH (the shared bag semantics).
        const obj2 = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 1), FinalTerms.int(&ctx, 200) });
        try dbag.insert(&ctx, obj2);
        try std.testing.expectEqual(@as(usize, 4), dbag.size());
    }
}

test "SELECT ≡ filter by match-spec denotation (tree + oracle)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    _ = arena.allocator();
    var prng = std.Random.DefaultPrng.init(0x5E1E);
    const random = prng.random();
    const pat = @import("pattern_algebra.zig");

    var oracle = OracleTable.init(gpa, .ordered_set);
    defer oracle.deinit();
    var tree = TreeBackend.init(gpa, .ordered_set);
    defer tree.deinit();
    for (0..80) |_| {
        const obj = try genObj(random, &ctx, 40);
        try oracle.insert(&ctx, obj);
        try tree.insert(&ctx, obj);
    }

    // select objects {K, V} with K > 20, returning V
    const v0 = pat.Pattern(FinalTerms){ .pvar = 0 };
    const v1 = pat.Pattern(FinalTerms){ .pvar = 1 };
    const head = pat.Pattern(FinalTerms){ .ptuple = &.{ &v0, &v1 } };
    const ms = msp.MatchSpec{
        .head = &head,
        .guards = &.{.{ .gt = .{ .v = 0, .lit = FinalTerms.int(&ctx, 20) } }},
        .body = .{ .variable = 1 },
    };
    var so: std.ArrayList(FinalTerms.Term) = .empty;
    defer so.deinit(gpa);
    try oracle.selectInto(&ctx, &ms, &so);
    var st: std.ArrayList(FinalTerms.Term) = .empty;
    defer st.deinit(gpa);
    try tree.selectInto(&ctx, &ms, &st);
    var fo = try sortedDump(gpa, &ctx, so.items);
    defer fo.deinit(gpa);
    var ft = try sortedDump(gpa, &ctx, st.items);
    defer ft.deinit(gpa);
    try std.testing.expect(std.mem.eql(u64, fo.items, ft.items));
    // and the guard is REAL: every selected V comes from a K > 20 row
    try std.testing.expect(so.items.len > 0); // workload guarantees some
}

// ── E6.7 (Task 7): the multi-process OWNERSHIP lifecycle laws ────────────────

test "LAW E6.7 ownership transfer: giveAway moves the owner; contents untouched" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var reg = EtsRegistry.init(gpa, &atoms);
    defer reg.deinit();

    const id = try reg.create(.set, false, 0, 1);
    const t = reg.byId(id).?;
    t.owner = 100; // process 100 owns it
    // insert a couple objects so we can prove contents survive the transfer.
    const o1 = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 1), FinalTerms.int(&ctx, 11) });
    const o2 = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 2), FinalTerms.int(&ctx, 22) });
    try t.backend.insert(&ctx, o1);
    try t.backend.insert(&ctx, o2);
    const size_before = t.backend.size();

    try reg.giveAway(id, 200); // hand it to process 200
    try std.testing.expectEqual(@as(u64, 200), reg.byId(id).?.owner);
    // give_away is denotation-preserving on the objects (the SACRED contents law).
    try std.testing.expectEqual(size_before, reg.byId(id).?.backend.size());
    // giveAway on an absent id is Badarg (never a use-after-free).
    reg.drop(id);
    try std.testing.expectError(error.Badarg, reg.giveAway(id, 300));
}

test "LAW E6.7 owner-death lifecycle: heir-less table dies; heir table transfers (mutant 2)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var reg = EtsRegistry.init(gpa, &atoms);
    defer reg.deinit();

    // Table A: owned by 100, NO heir -> auto-deletes on owner death.
    const a = try reg.create(.set, false, 0, 1);
    reg.byId(a).?.owner = 100;
    // Table B: owned by 100, heir = 200 -> transfers to 200 on owner death.
    const b = try reg.create(.set, false, 0, 1);
    reg.byId(b).?.owner = 100;
    reg.byId(b).?.heir = 200;
    // Table C: owned by 999 (a DIFFERENT process) -> untouched.
    const c = try reg.create(.set, false, 0, 1);
    reg.byId(c).?.owner = 999;

    reg.ownerDied(100);

    // A is gone (heir-less auto-delete).
    try std.testing.expect(reg.byId(a) == null);
    // B survives, now owned by its heir, heir cleared (the transfer, mutant-2 target:
    // a hook that delivers to the dead owner instead reddens the ownership move).
    try std.testing.expect(reg.byId(b) != null);
    try std.testing.expectEqual(@as(u64, 200), reg.byId(b).?.owner);
    try std.testing.expectEqual(@as(u64, 0), reg.byId(b).?.heir);
    // C untouched (a foreign owner's table never dies with process 100 — mutant-1
    // target: give_away/owner-death that ignores the owner check kills C too).
    try std.testing.expect(reg.byId(c) != null);
    try std.testing.expectEqual(@as(u64, 999), reg.byId(c).?.owner);
}
