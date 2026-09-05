//! beam-zig M1+M2+M4: the Erlang **Term algebra** — terms, atoms, bignums,
//! floats, binaries, maps.
//!
//! PART 1  SIGNATURE        — comptime contract over term-algebra encodings
//! PART 2  SEMANTIC DOMAIN  — spec.Value: atoms denote their NAMES; integers
//!                            denote mathematical integers (std.math.big is
//!                            the arithmetic oracle); floats denote finite
//!                            IEEE doubles; maps denote sorted assoc lists
//!                            (exact key order); + BOTH Erlang term orders
//! PART 3a INITIAL ENCODING — terms ARE canonical trees (the oracle)
//! PART 3b FINAL ENCODING   — erts-style tagged words: small ints & atom
//!                            indices immediate; bignums, floats, binaries,
//!                            maps boxed; cons = 2-word cells; copying GC.
//!                            Maps: FLATMAP (sorted arrays) for size ≤ 32,
//!                            HAMT above — the rep switch is law-governed.
//! PART 4  LAWS             — total preorder ×2 (arithmetic & exact),
//!                            spec-agreement, arithmetic vs oracle,
//!                            CANONICAL SMALLNESS, CANONICAL FLATNESS,
//!                            hash coherence, cross-encoding & GC
//!                            homomorphisms
//!
//! The two orders (M4): Erlang has `==` (arithmetic: 1 == 1.0) and `=:=`
//! (exact). `compare/eql` implement the arithmetic total preorder; ties
//! between int and float are EQUAL. `compareExact/eqlExact` refine it:
//! on a numeric tie the integer sorts BEFORE the float (erts map-key
//! order), and -0.0 sorts before 0.0. Map keys, hashing, and `test_eq`
//! use exact; `is_lt`/sorting use arithmetic. Laws bind the two.
//!
//! Kind ranks (erts subset; pin-exact per erl_utils.c `cmp` / erl_term.h _DEF):
//!   number 0 < atom 1 < reference 2 < fun 3 < port 4 < pid 5 <
//!   tuple 6 < native_record 7 < map 8 < nil/list 9 < binary/bitstring 10
//!   (matchctx 11, internal)
//! E7.1: the fun band (rank 3) holds BOTH local funs (`fun_`: label+arity+env)
//! and EXTERNAL funs (`export_fun`: `fun M:F/A`, ETF tag 113 EXPORT_EXT). erts
//! orders every local fun BELOW every external fun; external funs among
//! themselves compare by (module, function, arity) — module/function by atom
//! NAME (the same lexical order as `.atom`). External funs print `fun M:F/A`,
//! are `is_function/1`-true, and APPLY ≡ `apply(M,F,Args)` (dispatchMFA). All
//! verified empirically on the OTP host (term_to_binary + term-order probes).
//! (E3.5 renumbered these in lockstep across both encodings to insert the
//! reference/port/pid kinds; E3.14 inserted native_record between tuple and
//! map (erl_term.h RECORD_DEF sorts between TUPLE_DEF and MAP_DEF); the
//! authoritative list is restated at the ranks near the kind enum below.)
//!
//! E3.1 (LA-3): a `bitstring` kind joins rank 9 — "bitstrings sort WITH
//! binaries" (one order family): a byte-aligned bitstring IS a binary, and
//! cross-family comparison walks the shared bit-vector view (`bin_algebra`'s
//! byte-alignment homomorphism generalized to bits, `bitstring_algebra`).
//! SCOPE (semantic precursor, documented per ALGEBRAIC_FRACTAL_RULES §5):
//! `.binary` (existing, byte-array payload) and `.bitstring` (new, general
//! bit-vector payload) are kept as DISTINCT term-kind variants in this task
//! — additive, not a replacement of every existing `.binary` call site.
//! They already order and (for aligned content) HASH identically via the
//! shared bit-vector view, so `compare`-derived `eql` already treats an
//! aligned `<<1,2>>` binary and an equal-content bitstring as equal; a later
//! E3 task may choose to unify their FINAL-encoding storage as a pure
//! representation optimization — out of scope here. `kindOf` reports both
//! as `.binary` (mirrors how `.number` already buckets small/big/float);
//! `repIsBitstring`/`bitstringBits` are the finer discriminators (mirrors
//! `repIsSmall`/`repIsBig`/`repIsFloat`) — this keeps every PERIPHERAL
//! `switch (kindOf(...))` site (BIFs, ETF, matchspec, pattern_algebra)
//! untouched; only the algebra core (this file), `term_hash.zig`,
//! `diag.zig`, and `gc.zig` ripple, per the brief's file list.
//!
//! Floats are finite: NaN/±Inf are not terms (constructors assert/reject).
//! Engineering bounds, documented like erts': bignum magnitude ≤ 512 bits;
//! comparing two HAMT maps materializes denotations (erts also uses temp
//! buffers there) and panics on OOM — a documented final-encoding bound.
//!
//! E3.5 (LA-4/S27, Task 5 of Epoch E3): THREE new term kinds — pid,
//! reference, port. Each lands the TERM KIND (total order, equal-hash, ETF
//! wire codec, print shape) so `is_pid`/`is_reference`/`is_port`, sorting,
//! `ordsets`, `gb_trees`, map keys, and cross-node terms are TOTAL over
//! these kinds; the LIVE semantics they name are explicitly NOT this task's
//! scope (the E5 boundary below).
//!
//! E5.7 (S27, Task 7 of Epoch E5): pid/reference/port are WIDENED to carry a
//! `{node atom, creation}` identity. A locally-constructed identity keeps the
//! interned `local_node_name` (`nonode@nohost`) index and creation 0, so every
//! E3.5 order/hash/print/ETF law is byte-UNCHANGED for local terms — the
//! widening is a REPRESENTATION change whose regression net is exactly those
//! E3.5 laws. A FOREIGN identity (an external node's pid/port/ref, reachable
//! only via `etf.decode` of a `NEW_PID_EXT`/`V4_PORT_EXT`/`NEWER_REFERENCE_EXT`
//! from another node) carries the foreign node atom + its creation, observable
//! via `erlang:node/1` and byte-exact through `term_to_binary`. Order/hash now
//! discriminate node (lexical) then creation then the E3.5 fields; cross-node
//! ORDER is a total order, not claimed erts-byte-exact (no differential compares
//! foreign-identity order). The node word is a RAW atom INDEX (never a term
//! slot), so it inherits the "atoms move freely within a shared atom table"
//! gcCopy invariant unchanged — cross-node transfer is via ETF bytes, never gc.
//!
//!   pid       denotes a LOCAL process identity `(number, serial)` on the
//!             fixed node `nonode@nohost` — a pair of non-negative
//!             integers, nothing more (no scheduler binds it to a live
//!             process at this task; Tasks 6-8 wire `self/0`/`spawn/3` etc.
//!             on top of this kind).
//!   reference denotes a FRESH, NEVER-REUSED identity: the freshness law is
//!             that N refs generated from one `Ctx` are pairwise `=/=`.
//!             Compared by EXACT equality only (no numeric meaning). The
//!             `Ctx`-owned monotonic `ref_counter` (mirrors E2.12's
//!             `unique_counter` on `Machine`, here scoped to the term-algebra
//!             `Ctx` since references are a term-algebra concept, not a
//!             machine one) is the freshness SOURCE; `FinalTerms.ref`/
//!             `InitialTerms.ref` accept caller-supplied `[3]u32` words
//!             (needed for ETF decode, which reconstructs a ref from WIRE
//!             words, not from local freshness) — `freshRef`/`freshRefWords`
//!             are the freshness-guaranteeing convenience callers use when
//!             they need a genuinely NEW local reference (e.g. `make_ref/0`,
//!             landing in a later task).
//!   port      denotes a port-TABLE identity: a single non-negative integer.
//!             No live port I/O exists at this task (S27/E4 territory).
//!
//! E5 BOUNDARY (recorded per ALGEBRAIC_FRACTAL_RULES §5 — the deferral must
//! be visible, not silent): external/remote pids, MONITOR/dist wire frames,
//! and live port I/O are OUT OF SCOPE here. The ETF codec (etf.zig) accepts
//! ONLY the fixed local node atom (`nonode@nohost`) in a decoded
//! NEW_PID_EXT/NEW_PORT_EXT/V4_PORT_EXT/NEWER_REFERENCE_EXT frame — a
//! FOREIGN node atom is a clean `error.ForeignNode` decode reject (never a
//! panic), the documented boundary a later epoch (E5, dist) lifts. See
//! DIVERGENCE_LOG.md for the corresponding entry.
//!
//! E3.14 (Task 14, native records): a `native_record` kind — a DISTINCT
//! boxed product `(module_atom, name_atom, is_exported, keys[], values[])`
//! mirroring erts' `ErtsNativeRecord`. NEVER a tuple (`is_tuple` false,
//! `is_record/2` true). It sorts BETWEEN tuple and map (erl_term.h
//! RECORD_DEF 0x04 sits between TUPLE_DEF 0x05 and MAP_DEF 0x03, and
//! utils.c `cmp` orders mixed kinds by descending `_DEF`). Cross-record
//! order is by module atom, then name atom, then is_exported (false<true),
//! then field count, then keys, then values — the utils.c RECORD_SUBTAG
//! arm. zigvm INLINES the definition into the instance (module/name/keys/
//! exported are carried in the term itself): the global staged record table
//! erts keeps (populated by the compiler / `records:get_definition/2`) is a
//! code-server concern deferred to E4 — this slice's records are wholly
//! self-describing, which is exactly what `records:create/4` builds. Fields
//! are stored in INSERTION (declaration) order and looked up by exact atom
//! equality; `records:get_field_names/1` observes that order (erts stores
//! keys sorted and reconstructs insertion order via a field_order tuple —
//! observationally identical for the field-name list and for lookup; the
//! only divergence is cross-record compare of two same-module/same-name
//! records with differing key sets, which the compiler never emits — a
//! documented bound, DIVERGENCE entry 3 amendment).
//!
//! Total-order position (erts `erl_utils.c` `CMP_TERM`/`cmp` family; the
//! ranks below are BOTH encodings' `rank`, pin-exact):
//!   number(0) < atom(1) < reference(2) < fun(3) < port(4) < pid(5) <
//!   tuple(6) < native_record(7) < map(8) < nil/list(9) < binary/bitstring(10)
//! `reference`/`port`/`pid` compare by EXACT FIELD ORDER within their own
//! rank (never cross-kind, since same-rank here implies same-kind) — pid
//! orders `number` THEN `serial` (MUTANT 1: swapping this order is killed
//! by the total-order law below; see the `cmpPid`/`spec.orderMode` `.pid`
//! arm comments).

const std = @import("std");
pub const atom_table = @import("atom_table.zig");
pub const AtomTable = atom_table.AtomTable;
pub const AtomIdx = atom_table.AtomIdx;
pub const bsa = @import("bitstring_algebra.zig");
pub const Bits = bsa.Bits;

fn bitsOrder(o: bsa.Order) Order {
    return switch (o) {
        .lt => .lt,
        .eq => .eq,
        .gt => .gt,
    };
}

pub const Order = enum { lt, eq, gt };
pub const CmpMode = enum { arith, exact };

fn invert(o: Order) Order {
    return switch (o) {
        .lt => .gt,
        .eq => .eq,
        .gt => .lt,
    };
}

fn fromMathOrder(o: std.math.Order) Order {
    return switch (o) {
        .lt => .lt,
        .eq => .eq,
        .gt => .gt,
    };
}

// ============================================================================
// Shared numeric kernel: exact big-int vs float comparison (no allocation)
// ============================================================================

const FloatParts = struct { m: u64, k: i32 }; // |f| = m * 2^k, m == 0 iff f == 0

fn floatParts(f: f64) FloatParts {
    const bits: u64 = @bitCast(@abs(f));
    const expf: u64 = (bits >> 52) & 0x7FF;
    const frac: u64 = bits & ((@as(u64, 1) << 52) - 1);
    if (expf == 0) return .{ .m = frac, .k = -1074 }; // subnormal (or zero)
    return .{ .m = (@as(u64, 1) << 52) | frac, .k = @as(i32, @intCast(expf)) - 1075 };
}

fn limbsEffLen(a: []const u64) usize {
    var n = a.len;
    while (n > 1 and a[n - 1] == 0) n -= 1;
    return n;
}

fn limbsIsZero(a: []const u64) bool {
    const n = limbsEffLen(a);
    return n == 1 and a[0] == 0;
}

fn limbsBitLen(a: []const u64) i64 {
    const n = limbsEffLen(a);
    if (n == 1 and a[0] == 0) return 0;
    return @as(i64, @intCast((n - 1) * 64)) + @as(i64, 64 - @clz(a[n - 1]));
}

fn bitLen64(m: u64) i64 {
    return @as(i64, 64 - @clz(m));
}

fn cmpLimbs(a: []const u64, b: []const u64) Order {
    const na = limbsEffLen(a);
    const nb = limbsEffLen(b);
    if (na != nb) return if (na < nb) .lt else .gt;
    var k = na;
    while (k > 0) {
        k -= 1;
        if (a[k] != b[k]) return if (a[k] < b[k]) .lt else .gt;
    }
    return .eq;
}

/// Compare a nonzero magnitude (limbs) against a nonzero float magnitude
/// m·2^k, exactly. Scratch is stack-only (f64 shifts fit 17 limbs).
fn cmpMagVsFloatMag(limbs: []const u64, m: u64, k: i32) Order {
    const li = limbsBitLen(limbs);
    const fi = bitLen64(m) + k;
    if (li != fi) return if (li < fi) .lt else .gt;
    if (k >= 0) {
        var scratch: [18]u64 = @splat(0);
        const uk: usize = @intCast(k);
        const word = uk / 64;
        const sh: u7 = @intCast(uk % 64);
        const v = @as(u128, m) << sh;
        scratch[word] = @truncate(v);
        scratch[word + 1] = @truncate(v >> 64);
        return cmpLimbs(limbs, scratch[0 .. word + 2]);
    }
    // k < 0 and equal bit lengths ⇒ |f| ≥ 1 ⇒ -k < 53
    const kk: u6 = @intCast(-k);
    const ip = m >> kk;
    const frac = m & ((@as(u64, 1) << kk) - 1);
    std.debug.assert(limbsEffLen(limbs) == 1);
    if (limbs[0] != ip) return if (limbs[0] < ip) .lt else .gt;
    return if (frac != 0) .lt else .eq; // int == integer part, float has more
}

/// Exact order between a signed big integer (sign + limbs) and a finite f64.
/// .eq means NUMERIC equality (arithmetic order); exact mode's int<float
/// tie-break is applied by the caller.
fn cmpBigVsFloat(positive: bool, limbs: []const u64, f: f64) Order {
    const zi = limbsIsZero(limbs);
    const si: i8 = if (zi) 0 else if (positive) 1 else -1;
    const sf: i8 = if (f > 0) 1 else if (f < 0) -1 else 0;
    if (si != sf) return if (si < sf) .lt else .gt;
    if (si == 0) return .eq;
    const p = floatParts(f);
    const mag = cmpMagVsFloatMag(limbs, p.m, p.k);
    return if (si > 0) mag else invert(mag);
}

fn cmpF64(a: f64, b: f64, mode: CmpMode) Order {
    if (a < b) return .lt;
    if (a > b) return .gt;
    // numerically equal; exact mode distinguishes -0.0 < 0.0
    if (mode == .exact) {
        const sa = std.math.signbit(a);
        const sb = std.math.signbit(b);
        if (sa != sb) return if (sa) .lt else .gt;
    }
    return .eq;
}

fn limbsToF64(positive: bool, limbs: []const u64) f64 {
    var acc: f64 = 0;
    var k = limbsEffLen(limbs);
    while (k > 0) {
        k -= 1;
        acc = acc * 0x1p64 + @as(f64, @floatFromInt(limbs[k]));
    }
    return if (positive) acc else -acc;
}

// ============================================================================
// Shared hashing kernel — both encodings feed IDENTICAL bytes (hash coherence
// over exact equality is a law; 1 and 1.0 hash differently by design).
// ============================================================================

const Hasher = struct {
    h: u64 = 0xcbf29ce484222325,

    fn byte(self: *Hasher, b: u8) void {
        self.h = (self.h ^ b) *% 0x100000001b3;
    }
    fn bytes(self: *Hasher, bs: []const u8) void {
        for (bs) |b| self.byte(b);
    }
    fn word(self: *Hasher, w: u64) void {
        var v = w;
        for (0..8) |_| {
            self.byte(@truncate(v));
            v >>= 8;
        }
    }
};

/// Order-independent combine for map pairs (HAMT iterates unsorted).
fn mapPairMix(hk: u64, hv: u64) u64 {
    return (hk *% 0x9E3779B97F4A7C15) +% std.math.rotl(u64, hv, 17);
}

/// E5.7: the fixed LOCAL node identity. A pid/port/ref carries a node atom
/// (its owning node's name) and a creation stamp; terms constructed by the
/// local VM default to this name and creation 0. Foreign identities (an
/// external node's pid/port/ref, reachable only via ETF `binary_to_term`)
/// carry the FOREIGN node atom + its creation — see the pid/port/ref doc
/// comment. `etf.local_node_name` MUST equal this byte-for-byte.
pub const local_node_name = "nonode@nohost";

const HTag = struct {
    const int: u8 = 1;
    const float: u8 = 2;
    const atom: u8 = 3;
    const nil: u8 = 4;
    const cons: u8 = 5;
    const tuple: u8 = 6;
    const map: u8 = 7;
    const binary: u8 = 8;
    const fun_: u8 = 9;
    const bitstring: u8 = 10;
    const reference: u8 = 11;
    const port: u8 = 12;
    const pid: u8 = 13;
    const native_record: u8 = 14;
    const export_fun: u8 = 15; // E7.1: fun M:F/A (EXPORT_EXT)
};

fn hashInt(hs: *Hasher, positive: bool, limbs: []const u64) void {
    hs.byte(HTag.int);
    if (limbsIsZero(limbs)) {
        hs.byte(0);
        return;
    }
    hs.byte(if (positive) 1 else 2);
    const n = limbsEffLen(limbs);
    for (limbs[0..n]) |l| hs.word(l);
}

// ============================================================================
// PART 2: SEMANTIC DOMAIN — canonical trees + the term orders (the spec)
// ============================================================================

pub const spec = struct {
    pub const Big = std.math.big.int.Const;
    pub const Limb = std.math.big.Limb; // u64 on this target

    pub const KV = struct { key: *const Value, val: *const Value };

    pub const Value = union(enum) {
        int: Big, //            a mathematical integer (arbitrary precision)
        float: f64, //          a finite IEEE double
        atom: []const u8, //    an atom denotes its NAME (indices are rep)
        nil,
        cons: struct { head: *const Value, tail: *const Value },
        tuple: []const *const Value,
        map: []const KV, //     sorted by EXACT key order, keys distinct
        binary: []const u8,
        bitstring: Bits, //     E3.1: general bit-vector (rank WITH binary)
        fun_: Fun, //           M5: code label + arity + captured environment
        // E7.1: an EXTERNAL fun `fun M:F/A` (EXPORT_EXT, ETF tag 113). A
        // reference to an exported function by module/function NAME + arity —
        // NO code label, NO captured environment. Ranks in the fun band (3),
        // AFTER every local fun (erts: "locals are ordered before externals"),
        // and among external funs by (module, function, arity) — module and
        // function compared by atom NAME (the same lexical order as `.atom`).
        export_fun: ExportFun,
        // E3.5/E5.7: a pid (number, serial) on a NODE (atom name) with a
        // creation stamp. Local pids carry `local_node_name`, creation 0.
        pid: Pid,
        // E3.5/E5.7: a fresh, never-reused identity — 3 wire-shaped words on
        // a NODE + creation. Compared by node/creation/words (field order).
        reference: Ref,
        // E3.5/E5.7: a port-table identity (a non-negative integer) on a
        // NODE + creation.
        port: Port,
        // E3.14: a native record — a distinct product, ordered between
        // tuple and map (see the module doc comment).
        native_record: NativeRecord,
    };

    pub const Fun = struct { label: u64, arity: u64, env: []const *const Value };
    // E7.1: module/function are atom NAMES (indices are representation, like
    // `.atom`); arity is the exported arity. No label, no env.
    pub const ExportFun = struct { module: []const u8, function: []const u8, arity: u64 };
    // E5.7: node = the owning node's atom NAME (indices are representation);
    // creation = the node incarnation stamp. Local defaults keep every
    // pre-E5.7 law green (same node, creation 0 ⇒ node/creation compare eq,
    // so the surviving order/hash discriminator is exactly the old fields).
    pub const Pid = struct { number: u64, serial: u64, node: []const u8 = local_node_name, creation: u32 = 0 };
    pub const Ref = struct { words: [3]u32, node: []const u8 = local_node_name, creation: u32 = 0 };
    pub const Port = struct { number: u64, node: []const u8 = local_node_name, creation: u32 = 0 };
    /// E3.14: keys are atom Values (insertion order); values parallel keys.
    pub const NativeRecord = struct {
        module: *const Value,
        name: *const Value,
        is_exported: bool,
        keys: []const *const Value,
        values: []const *const Value,
    };

    /// Erlang kind rank (E3.5/E3.14, pin-exact — see the module doc comment):
    /// number < atom < reference < fun < port < pid < tuple <
    /// native_record < map < nil/list < binary/bitstring.
    fn rank(v: *const Value) u8 {
        return switch (v.*) {
            .int, .float => 0,
            .atom => 1,
            .reference => 2,
            .fun_, .export_fun => 3, // E7.1: external funs share the fun band
            .port => 4,
            .pid => 5,
            .tuple => 6,
            .native_record => 7,
            .map => 8,
            .nil, .cons => 9,
            .binary, .bitstring => 10,
        };
    }

    /// Both `.binary` and `.bitstring` denote a bit-vector; this view is
    /// what makes rank-9 (binary/bitstring) comparison/hash cross-family-coherent.
    fn toBits(v: *const Value) Bits {
        return switch (v.*) {
            .binary => |bs| bsa.fromBinary(bs),
            .bitstring => |b| b,
            else => unreachable,
        };
    }

    fn orderNum(a: *const Value, b: *const Value, mode: CmpMode) Order {
        switch (a.*) {
            .int => |x| switch (b.*) {
                .int => |y| return fromMathOrder(x.order(y)),
                .float => |g| {
                    const o = cmpBigVsFloat(x.positive, x.limbs, g);
                    if (o == .eq and mode == .exact) return .lt; // int < float on tie
                    return o;
                },
                else => unreachable,
            },
            .float => |f| switch (b.*) {
                .int => |y| {
                    const o = invert(cmpBigVsFloat(y.positive, y.limbs, f));
                    if (o == .eq and mode == .exact) return .gt;
                    return o;
                },
                .float => |g| return cmpF64(f, g, mode),
                else => unreachable,
            },
            else => unreachable,
        }
    }

    /// The Erlang total term orders on canonical trees — executable spec.
    pub fn orderMode(a: *const Value, b: *const Value, mode: CmpMode) Order {
        const ra = rank(a);
        const rb = rank(b);
        if (ra != rb) return if (ra < rb) .lt else .gt;
        if (ra == 0) return orderNum(a, b, mode);
        if (ra == 10) return bitsOrder(bsa.compare(toBits(a), toBits(b)));
        return switch (a.*) {
            .int, .float, .binary, .bitstring => unreachable,
            // E3.14: module, name, is_exported (false<true), field count,
            // then keys, then values — the utils.c RECORD_SUBTAG arm.
            .native_record => |x| blk: {
                const y = b.native_record;
                const om = orderMode(x.module, y.module, .exact);
                if (om != .eq) break :blk om;
                const on = orderMode(x.name, y.name, .exact);
                if (on != .eq) break :blk on;
                if (x.is_exported != y.is_exported)
                    break :blk if (!x.is_exported) Order.lt else Order.gt;
                if (x.keys.len != y.keys.len)
                    break :blk if (x.keys.len < y.keys.len) Order.lt else Order.gt;
                for (x.keys, y.keys) |xk, yk| {
                    const o = orderMode(xk, yk, .exact);
                    if (o != .eq) break :blk o;
                }
                for (x.values, y.values) |xv, yv| {
                    const o = orderMode(xv, yv, mode);
                    if (o != .eq) break :blk o;
                }
                break :blk Order.eq;
            },
            .atom => |x| fromMathOrder(std.mem.order(u8, x, b.atom)),
            // E5.7: node (lexical) then creation then the wire words. Local
            // refs share node/creation ⇒ this reduces to the pinned word
            // order. Cross-node ordering is a total order (not claimed erts-
            // byte-exact — no differential compares foreign identity ORDER).
            .reference => |x| blk: {
                const y = b.reference;
                const on = std.mem.order(u8, x.node, y.node);
                if (on != .eq) break :blk fromMathOrder(on);
                if (x.creation != y.creation) break :blk if (x.creation < y.creation) Order.lt else Order.gt;
                for (x.words, y.words) |xw, yw| {
                    if (xw != yw) break :blk if (xw < yw) Order.lt else Order.gt;
                }
                break :blk Order.eq;
            },
            .port => |x| blk: {
                const y = b.port;
                const on = std.mem.order(u8, x.node, y.node);
                if (on != .eq) break :blk fromMathOrder(on);
                if (x.creation != y.creation) break :blk if (x.creation < y.creation) Order.lt else Order.gt;
                break :blk if (x.number == y.number) Order.eq else if (x.number < y.number) Order.lt else Order.gt;
            },
            // MUTANT 1 site: a pid orders by `number` THEN `serial` — killed
            // by the total-order law if this pair is swapped (see the
            // module doc comment's Mutant-1 note and `cmpPid` below, the
            // Final-encoding twin of this arm). E5.7: node/creation first.
            .pid => |x| blk: {
                const y = b.pid;
                const on = std.mem.order(u8, x.node, y.node);
                if (on != .eq) break :blk fromMathOrder(on);
                if (x.creation != y.creation) break :blk if (x.creation < y.creation) Order.lt else Order.gt;
                if (x.number != y.number)
                    break :blk if (x.number < y.number) Order.lt else Order.gt;
                break :blk if (x.serial == y.serial) Order.eq else if (x.serial < y.serial) Order.lt else Order.gt;
            },
            .tuple => |xs| blk: {
                const ys = b.tuple;
                if (xs.len != ys.len)
                    break :blk if (xs.len < ys.len) Order.lt else Order.gt;
                for (xs, ys) |x, y| {
                    const o = orderMode(x, y, mode);
                    if (o != .eq) break :blk o;
                }
                break :blk Order.eq;
            },
            .map => |xs| blk: {
                const ys = b.map;
                if (xs.len != ys.len)
                    break :blk if (xs.len < ys.len) Order.lt else Order.gt;
                // keys compare EXACT in both modes (erts semantics) …
                for (xs, ys) |x, y| {
                    const o = orderMode(x.key, y.key, .exact);
                    if (o != .eq) break :blk o;
                }
                // … values in key order, with the requested mode
                for (xs, ys) |x, y| {
                    const o = orderMode(x.val, y.val, mode);
                    if (o != .eq) break :blk o;
                }
                break :blk Order.eq;
            },
            .nil => switch (b.*) {
                .nil => .eq,
                .cons => .lt, // nil sorts below every cons
                else => unreachable, // ranks already equal
            },
            .cons => |p| switch (b.*) {
                .nil => .gt,
                .cons => |q| blk: {
                    const oh = orderMode(p.head, q.head, mode);
                    break :blk if (oh != .eq) oh else orderMode(p.tail, q.tail, mode);
                },
                else => unreachable,
            },
            .fun_ => |x| switch (b.*) {
                // E7.1: every local fun sorts BELOW every external fun.
                .export_fun => Order.lt,
                .fun_ => |y| blk: {
                    if (x.label != y.label)
                        break :blk if (x.label < y.label) Order.lt else Order.gt;
                    if (x.arity != y.arity)
                        break :blk if (x.arity < y.arity) Order.lt else Order.gt;
                    if (x.env.len != y.env.len)
                        break :blk if (x.env.len < y.env.len) Order.lt else Order.gt;
                    for (x.env, y.env) |ex, ey| {
                        const o = orderMode(ex, ey, mode);
                        if (o != .eq) break :blk o;
                    }
                    break :blk Order.eq;
                },
                else => unreachable, // ranks already equal (fun band)
            },
            // E7.1: external funs sort ABOVE every local fun, and among
            // themselves by (module, function, arity) — module/function by
            // atom NAME (erts external-fun compare = module, function, arity).
            .export_fun => |x| switch (b.*) {
                .fun_ => Order.gt,
                .export_fun => |y| blk: {
                    const om = std.mem.order(u8, x.module, y.module);
                    if (om != .eq) break :blk fromMathOrder(om);
                    const of = std.mem.order(u8, x.function, y.function);
                    if (of != .eq) break :blk fromMathOrder(of);
                    break :blk if (x.arity == y.arity) Order.eq else if (x.arity < y.arity) Order.lt else Order.gt;
                },
                else => unreachable, // ranks already equal (fun band)
            },
        };
    }

    pub fn order(a: *const Value, b: *const Value) Order {
        return orderMode(a, b, .arith);
    }
    pub fn orderExact(a: *const Value, b: *const Value) Order {
        return orderMode(a, b, .exact);
    }

    pub fn cmpInt(x: i64, y: i64) Order {
        if (x < y) return .lt;
        if (x > y) return .gt;
        return .eq;
    }

    pub fn eql(a: *const Value, b: *const Value) bool {
        return order(a, b) == .eq;
    }
    pub fn eqlExact(a: *const Value, b: *const Value) bool {
        return orderExact(a, b) == .eq;
    }

    /// Exact-equality-coherent hash of a canonical tree (the hash spec).
    pub fn hashValue(v: *const Value) u64 {
        var hs = Hasher{};
        hashInto(&hs, v);
        return hs.h;
    }

    fn hashInto(hs: *Hasher, v: *const Value) void {
        switch (v.*) {
            .int => |x| hashInt(hs, x.positive, x.limbs),
            .float => |f| {
                hs.byte(HTag.float);
                hs.word(@bitCast(f));
            },
            .atom => |name| {
                hs.byte(HTag.atom);
                hs.word(name.len);
                hs.bytes(name);
            },
            .nil => hs.byte(HTag.nil),
            .cons => |p| {
                hs.byte(HTag.cons);
                hashInto(hs, p.head);
                hashInto(hs, p.tail);
            },
            .tuple => |xs| {
                hs.byte(HTag.tuple);
                hs.word(xs.len);
                for (xs) |x| hashInto(hs, x);
            },
            .map => |kvs| {
                hs.byte(HTag.map);
                hs.word(kvs.len);
                var acc: u64 = 0;
                for (kvs) |kv| acc ^= mapPairMix(hashValue(kv.key), hashValue(kv.val));
                hs.word(acc);
            },
            .binary => |bs| {
                hs.byte(HTag.binary);
                hs.word(bs.len);
                hs.bytes(bs);
            },
            // Hash-coherence with `.binary` when aligned (a `<<1,2>>` binary
            // and an equal-content bitstring already `eql` via the shared
            // rank-9 (binary/bitstring) order — the equal-hash law then FORCES equal hashes):
            // reuse the exact `.binary` tag/len/bytes hash for aligned
            // content; only a genuinely sub-byte tail gets its own tag.
            .bitstring => |bits| {
                if (bits.bit_len % 8 == 0) {
                    hs.byte(HTag.binary);
                    hs.word(bits.bytes.len);
                    hs.bytes(bits.bytes);
                } else {
                    hs.byte(HTag.bitstring);
                    hs.word(bits.bit_len);
                    hs.bytes(bits.bytes);
                }
            },
            .fun_ => |f| {
                hs.byte(HTag.fun_);
                hs.word(f.label);
                hs.word(f.arity);
                hs.word(f.env.len);
                for (f.env) |e| hashInto(hs, e);
            },
            // E7.1: mirrors FinalTerms.hashWords' SUBTAG_EXPORT_FUN arm
            // (length-prefixed names, then arity) — hash coherence across
            // encodings.
            .export_fun => |e| {
                hs.byte(HTag.export_fun);
                hs.word(e.module.len);
                hs.bytes(e.module);
                hs.word(e.function.len);
                hs.bytes(e.function);
                hs.word(e.arity);
            },
            .reference => |r| {
                hs.byte(HTag.reference);
                hs.bytes(r.node);
                hs.word(r.creation);
                hs.word(r.words[0]);
                hs.word(r.words[1]);
                hs.word(r.words[2]);
            },
            .port => |p| {
                hs.byte(HTag.port);
                hs.bytes(p.node);
                hs.word(p.creation);
                hs.word(p.number);
            },
            .pid => |p| {
                hs.byte(HTag.pid);
                hs.bytes(p.node);
                hs.word(p.creation);
                hs.word(p.number);
                hs.word(p.serial);
            },
            // E3.14: mirrors FinalTerms.hashWords' SUBTAG_NATIVE_RECORD arm.
            .native_record => |r| {
                hs.byte(HTag.native_record);
                hashInto(hs, r.module);
                hashInto(hs, r.name);
                hs.byte(if (r.is_exported) 1 else 0);
                hs.word(r.keys.len);
                for (r.keys) |k| hashInto(hs, k);
                for (r.values) |val| hashInto(hs, val);
            },
        }
    }

    // ---- arithmetic oracle: std.math.big + IEEE ---------------------------

    pub fn bigFromI128(arena: std.mem.Allocator, v: i128) !Big {
        const m = try std.math.big.int.Managed.initSet(arena, v);
        return m.toConst(); // limbs live in the arena
    }

    /// The specification of integer '+': mathematical integer addition.
    pub fn addValues(arena: std.mem.Allocator, a: Big, b: Big) !Big {
        var ma = try a.toManaged(arena);
        var mb = try b.toManaged(arena);
        var r = try std.math.big.int.Managed.init(arena);
        try r.add(&ma, &mb);
        return r.toConst();
    }

    pub fn numToF64(v: *const Value) f64 {
        return switch (v.*) {
            .int => |x| limbsToF64(x.positive, x.limbs),
            .float => |f| f,
            else => unreachable,
        };
    }

    /// '+' over Erlang numbers: int×int is exact; any float ⇒ IEEE double,
    /// overflow to ±Inf is badarith (erts semantics).
    pub fn addNum(arena: std.mem.Allocator, a: *const Value, b: *const Value) !*const Value {
        const out = try arena.create(Value);
        if (a.* == .int and b.* == .int) {
            out.* = .{ .int = try addValues(arena, a.int, b.int) };
            return out;
        }
        const s = numToF64(a) + numToF64(b);
        if (!std.math.isFinite(s)) return error.Badarith;
        out.* = .{ .float = s };
        return out;
    }
};

/// The one number-representation boundary, shared by spec and encodings:
/// values in [-2^59, 2^59) are "small".
pub fn fitsSmall(i: i64) bool {
    return i >= -(1 << 59) and i < (1 << 59);
}

/// Maps are FLAT (sorted arrays) up to this size, HAMT above — canonical,
/// like smallness: the representation is decidable from the size alone.
pub const max_flatmap_size = 32;

/// E3.14: engineering bound on native-record field count (documented
/// final-encoding capacity, like `max_flatmap_size`). 3+2·32=67 payload
/// words fit the GC evac scratch buffer (`[96]u64`).
pub const max_nr_fields = 32;

// ============================================================================
// PART 1: THE SIGNATURE — what every term encoding must provide
// ============================================================================

pub fn requireTermAlgebra(comptime T: type) void {
    comptime {
        const required = .{
            "Ctx",     "Term",           "int",     "intFromI128", "add",
            "atom",    "nil",            "cons",    "tuple",       "compare",
            "eql",     "denote",         "float",   "binary",      "mapNew",
            "mapGet",  "mapPut",         "mapRemove", "mapSize",   "compareExact",
            "eqlExact", "hashTerm",      "binConcat", "binPart",   "binSize",
            "iolistToBinary",            "makeFun", "kindOf",      "listHead",
            "listTail", "tupleArity",    "tupleElem", "funLabel",  "funArity",
            "bitstring", "pid",          "ref",       "port",
        };
        for (required) |name| {
            if (!@hasDecl(T, name)) {
                @compileError(@typeName(T) ++
                    " violates the Term signature: missing decl `" ++ name ++ "`");
            }
        }
        if (@TypeOf(T.int) != fn (*T.Ctx, i64) T.Term)
            @compileError(@typeName(T) ++ ": `int` must be `fn (*Ctx, i64) Term`");
        if (@TypeOf(T.compare) != fn (*T.Ctx, T.Term, T.Term) Order)
            @compileError(@typeName(T) ++ ": `compare` must be `fn (*Ctx, Term, Term) Order`");
        if (@TypeOf(T.eql) != fn (*T.Ctx, T.Term, T.Term) bool)
            @compileError(@typeName(T) ++ ": `eql` must be `fn (*Ctx, Term, Term) bool`");
    }
}

// ============================================================================
// PART 3a: INITIAL ENCODING — terms are canonical trees (the oracle)
// ============================================================================

pub const InitialTerms = struct {
    pub const Term = *const spec.Value;

    pub const Ctx = struct {
        arena: std.heap.ArenaAllocator,
        atoms: *AtomTable, // VM-global; heaps hold indices, table owns names
        // E3.5: the reference-freshness SOURCE (module doc comment). Scoped
        // to the term-algebra Ctx (mirrors E2.12's Machine-owned
        // `unique_counter`, but references are a term-algebra concept).
        ref_counter: u64 = 0,

        pub fn init(gpa: std.mem.Allocator, atoms: *AtomTable) Ctx {
            return .{ .arena = std.heap.ArenaAllocator.init(gpa), .atoms = atoms };
        }
        pub fn deinit(self: *Ctx) void {
            self.arena.deinit();
        }
        fn a(self: *Ctx) std.mem.Allocator {
            return self.arena.allocator();
        }
    };

    fn mk(ctx: *Ctx, v: spec.Value) Term {
        const p = ctx.a().create(spec.Value) catch @panic("oracle arena OOM");
        p.* = v;
        return p;
    }

    pub fn int(ctx: *Ctx, i: i64) Term {
        return mk(ctx, .{ .int = spec.bigFromI128(ctx.a(), i) catch @panic("oracle OOM") });
    }
    pub fn intFromI128(ctx: *Ctx, v: i128) !Term {
        return mk(ctx, .{ .int = try spec.bigFromI128(ctx.a(), v) });
    }
    pub fn float(ctx: *Ctx, f: f64) Term {
        std.debug.assert(std.math.isFinite(f));
        return mk(ctx, .{ .float = f });
    }
    /// '+' — the oracle computes with the spec directly.
    pub fn add(ctx: *Ctx, x: Term, y: Term) !Term {
        std.debug.assert((x.* == .int or x.* == .float) and (y.* == .int or y.* == .float));
        return try spec.addNum(ctx.a(), x, y);
    }
    pub fn atom(ctx: *Ctx, idx: AtomIdx) Term {
        return mk(ctx, .{ .atom = ctx.atoms.nameOf(idx) });
    }
    pub fn nil(ctx: *Ctx) Term {
        return mk(ctx, .nil);
    }
    pub fn cons(ctx: *Ctx, head: Term, tail: Term) !Term {
        return mk(ctx, .{ .cons = .{ .head = head, .tail = tail } });
    }
    pub fn tuple(ctx: *Ctx, elems: []const Term) !Term {
        const copy = try ctx.a().dupe(*const spec.Value, elems);
        return mk(ctx, .{ .tuple = copy });
    }
    pub fn binary(ctx: *Ctx, bytes: []const u8) !Term {
        return mk(ctx, .{ .binary = try ctx.a().dupe(u8, bytes) });
    }

    /// E3.1: construct a canonical bitstring (see `bitstring_algebra`'s
    /// `canonicalize` — the oracle routes through the SAME enforcement
    /// point as the final encoding).
    pub fn bitstring(ctx: *Ctx, bytes: []const u8, bit_len: usize) !Term {
        return mk(ctx, .{ .bitstring = try bsa.canonicalize(ctx.a(), bytes, bit_len) });
    }
    pub fn repIsBitstring(_: *Ctx, t: Term) bool {
        return t.* == .bitstring;
    }
    pub fn bitstringBits(_: *Ctx, t: Term) Bits {
        return t.bitstring;
    }

    // ---- E3.5: pid / reference / port (term-kind construction only — no
    // live process/port/dist semantics; see the module doc comment) --------

    pub fn pid(ctx: *Ctx, number: u64, serial: u64) !Term {
        return mk(ctx, .{ .pid = .{ .number = number, .serial = serial } });
    }
    /// E5.7: a pid on a FOREIGN node (`node_idx` interned in `ctx.atoms`).
    pub fn pidExt(ctx: *Ctx, number: u64, serial: u64, node_idx: AtomIdx, creation: u32) !Term {
        return mk(ctx, .{ .pid = .{ .number = number, .serial = serial, .node = ctx.atoms.nameOf(node_idx), .creation = creation } });
    }
    pub fn repIsPid(_: *Ctx, t: Term) bool {
        return t.* == .pid;
    }
    pub fn pidNumber(_: *Ctx, t: Term) u64 {
        return t.pid.number;
    }
    pub fn pidSerial(_: *Ctx, t: Term) u64 {
        return t.pid.serial;
    }
    /// E5.7: the node atom NAME (local pids: `local_node_name`).
    pub fn pidNodeName(_: *Ctx, t: Term) []const u8 {
        return t.pid.node;
    }
    pub fn pidCreation(_: *Ctx, t: Term) u32 {
        return t.pid.creation;
    }

    /// Construct a reference from caller-supplied wire words (ETF decode's
    /// path). Freshness (the term-kind law) is NOT this constructor's job —
    /// see `freshRef`/`freshRefWords`.
    pub fn ref(ctx: *Ctx, words: [3]u32) !Term {
        return mk(ctx, .{ .reference = .{ .words = words } });
    }
    /// E5.7: a reference on a FOREIGN node.
    pub fn refExt(ctx: *Ctx, words: [3]u32, node_idx: AtomIdx, creation: u32) !Term {
        return mk(ctx, .{ .reference = .{ .words = words, .node = ctx.atoms.nameOf(node_idx), .creation = creation } });
    }
    /// The freshness-guaranteeing generator: increments the Ctx-owned
    /// monotonic counter, so N calls on one Ctx are pairwise `=/=`.
    pub fn freshRefWords(ctx: *Ctx) [3]u32 {
        ctx.ref_counter += 1;
        const c = ctx.ref_counter;
        return .{ @truncate(c), @truncate(c >> 32), 0 };
    }
    pub fn freshRef(ctx: *Ctx) !Term {
        return ref(ctx, freshRefWords(ctx));
    }
    pub fn repIsRef(_: *Ctx, t: Term) bool {
        return t.* == .reference;
    }
    pub fn refWords(_: *Ctx, t: Term) [3]u32 {
        return t.reference.words;
    }
    pub fn refNodeName(_: *Ctx, t: Term) []const u8 {
        return t.reference.node;
    }
    pub fn refCreation(_: *Ctx, t: Term) u32 {
        return t.reference.creation;
    }

    pub fn port(ctx: *Ctx, number: u64) !Term {
        return mk(ctx, .{ .port = .{ .number = number } });
    }
    /// E5.7: a port on a FOREIGN node.
    pub fn portExt(ctx: *Ctx, number: u64, node_idx: AtomIdx, creation: u32) !Term {
        return mk(ctx, .{ .port = .{ .number = number, .node = ctx.atoms.nameOf(node_idx), .creation = creation } });
    }
    pub fn repIsPort(_: *Ctx, t: Term) bool {
        return t.* == .port;
    }
    pub fn portNumber(_: *Ctx, t: Term) u64 {
        return t.port.number;
    }
    pub fn portNodeName(_: *Ctx, t: Term) []const u8 {
        return t.port.node;
    }
    pub fn portCreation(_: *Ctx, t: Term) u32 {
        return t.port.creation;
    }

    // ---- E3.14: native records (a distinct product kind) ------------------

    /// Build a native record. `keys`/`values` are parallel (insertion order);
    /// `module`/`name` are atom Terms.
    pub fn nativeRecord(ctx: *Ctx, module: Term, name: Term, is_exported: bool, keys: []const Term, values: []const Term) !Term {
        std.debug.assert(keys.len == values.len);
        return mk(ctx, .{ .native_record = .{
            .module = module,
            .name = name,
            .is_exported = is_exported,
            .keys = try ctx.a().dupe(*const spec.Value, keys),
            .values = try ctx.a().dupe(*const spec.Value, values),
        } });
    }
    pub fn repIsNativeRecord(_: *Ctx, t: Term) bool {
        return t.* == .native_record;
    }
    pub fn nrModule(_: *Ctx, t: Term) Term {
        return t.native_record.module;
    }
    pub fn nrName(_: *Ctx, t: Term) Term {
        return t.native_record.name;
    }
    pub fn nrIsExported(_: *Ctx, t: Term) bool {
        return t.native_record.is_exported;
    }
    pub fn nrFieldCount(_: *Ctx, t: Term) usize {
        return t.native_record.keys.len;
    }
    pub fn nrKeyAt(_: *Ctx, t: Term, i: usize) Term {
        return t.native_record.keys[i];
    }
    pub fn nrValAt(_: *Ctx, t: Term, i: usize) Term {
        return t.native_record.values[i];
    }

    // ---- maps: sorted assoc list on trees (the oracle representation) -----

    /// Build from unsorted pairs; duplicate (exact-equal) keys: LAST wins,
    /// exactly like maps:from_list/1.
    pub fn mapNew(ctx: *Ctx, keys: []const Term, vals: []const Term) !Term {
        std.debug.assert(keys.len == vals.len);
        const idxs = try ctx.a().alloc(usize, keys.len);
        for (idxs, 0..) |*s, i| s.* = i;
        const SortCtx = struct {
            keys: []const Term,
            pub fn less(s: @This(), x: usize, y: usize) bool {
                return spec.orderExact(s.keys[x], s.keys[y]) == .lt;
            }
        };
        std.sort.insertion(usize, idxs, SortCtx{ .keys = keys }, SortCtx.less); // stable
        var kvs: std.ArrayList(spec.KV) = .empty;
        for (idxs) |i| {
            if (kvs.items.len > 0 and
                spec.eqlExact(kvs.items[kvs.items.len - 1].key, keys[i]))
            {
                kvs.items[kvs.items.len - 1] = .{ .key = keys[i], .val = vals[i] }; // last wins
            } else {
                try kvs.append(ctx.a(), .{ .key = keys[i], .val = vals[i] });
            }
        }
        return mk(ctx, .{ .map = try kvs.toOwnedSlice(ctx.a()) });
    }

    pub fn mapGet(_: *Ctx, m: Term, k: Term) ?Term {
        for (m.map) |kv| if (spec.eqlExact(kv.key, k)) return kv.val;
        return null;
    }

    pub fn mapPut(ctx: *Ctx, m: Term, k: Term, v: Term) !Term {
        var kvs: std.ArrayList(spec.KV) = .empty;
        var inserted = false;
        for (m.map) |kv| {
            if (!inserted) {
                const o = spec.orderExact(k, kv.key);
                if (o == .lt) {
                    try kvs.append(ctx.a(), .{ .key = k, .val = v });
                    inserted = true;
                } else if (o == .eq) {
                    try kvs.append(ctx.a(), .{ .key = k, .val = v });
                    inserted = true;
                    continue; // replace
                }
            }
            try kvs.append(ctx.a(), kv);
        }
        if (!inserted) try kvs.append(ctx.a(), .{ .key = k, .val = v });
        return mk(ctx, .{ .map = try kvs.toOwnedSlice(ctx.a()) });
    }

    pub fn mapRemove(ctx: *Ctx, m: Term, k: Term) !Term {
        var kvs: std.ArrayList(spec.KV) = .empty;
        var removed = false;
        for (m.map) |kv| {
            if (!removed and spec.eqlExact(kv.key, k)) {
                removed = true;
                continue;
            }
            try kvs.append(ctx.a(), kv);
        }
        if (!removed) return m; // absent key: same map
        return mk(ctx, .{ .map = try kvs.toOwnedSlice(ctx.a()) });
    }

    pub fn mapSize(_: *Ctx, m: Term) usize {
        return m.map.len;
    }

    // ---- binaries on trees -------------------------------------------------

    pub fn binConcat(ctx: *Ctx, x: Term, y: Term) !Term {
        const out = try ctx.a().alloc(u8, x.binary.len + y.binary.len);
        @memcpy(out[0..x.binary.len], x.binary);
        @memcpy(out[x.binary.len..], y.binary);
        return mk(ctx, .{ .binary = out });
    }
    pub fn binPart(ctx: *Ctx, b: Term, pos: usize, len: usize) !Term {
        if (pos + len > b.binary.len) return error.BadArg;
        return mk(ctx, .{ .binary = try ctx.a().dupe(u8, b.binary[pos .. pos + len]) });
    }
    pub fn binSize(_: *Ctx, b: Term) usize {
        return b.binary.len;
    }

    pub fn iolistToBinary(ctx: *Ctx, t: Term) !Term {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(ctx.a());
        try ioAccTop(ctx, t, &out);
        return mk(ctx, .{ .binary = try ctx.a().dupe(u8, out.items) });
    }

    fn ioAccTop(ctx: *Ctx, t: Term, out: *std.ArrayList(u8)) !void {
        switch (t.*) {
            .binary => |bs| try out.appendSlice(ctx.a(), bs),
            .nil, .cons => try ioAccList(ctx, t, out),
            else => return error.BadArg,
        }
    }
    fn ioAccList(ctx: *Ctx, t0: Term, out: *std.ArrayList(u8)) !void {
        var t = t0;
        while (true) switch (t.*) {
            .nil => return,
            .cons => |p| {
                try ioAccElem(ctx, p.head, out);
                t = p.tail;
            },
            .binary => |bs| { // improper tail binary is legal iodata
                try out.appendSlice(ctx.a(), bs);
                return;
            },
            else => return error.BadArg,
        };
    }
    fn ioAccElem(ctx: *Ctx, t: Term, out: *std.ArrayList(u8)) error{ BadArg, OutOfMemory }!void {
        switch (t.*) {
            .int => |x| {
                if (x.positive and limbsEffLen(x.limbs) == 1 and x.limbs[0] <= 255) {
                    try out.append(ctx.a(), @intCast(x.limbs[0]));
                } else return error.BadArg;
            },
            .binary => |bs| try out.appendSlice(ctx.a(), bs),
            .nil, .cons => try ioAccList(ctx, t, out),
            else => return error.BadArg,
        }
    }

    // ---- funs (M5) ---------------------------------------------------------

    pub fn makeFun(ctx: *Ctx, label: u32, arity: u8, env: []const Term) !Term {
        const copy = try ctx.a().dupe(*const spec.Value, env);
        return mk(ctx, .{ .fun_ = .{ .label = label, .arity = arity, .env = copy } });
    }

    // ---- structural reflection (the observation set matchers need) ---------

    pub const Kind = enum { number, atom, fun_, tuple, map, nil, cons, binary, reference, port, pid, native_record };

    pub fn kindOf(_: *Ctx, t: Term) Kind {
        return switch (t.*) {
            .int, .float => .number,
            .atom => .atom,
            .fun_ => .fun_,
            .export_fun => .fun_, // E7.1: is_function/1 holds for external funs
            .tuple => .tuple,
            .map => .map,
            .nil => .nil,
            .cons => .cons,
            .binary, .bitstring => .binary, // E3.1: bucketed like number/small/big/float
            .reference => .reference, // E3.5
            .port => .port, // E3.5
            .pid => .pid, // E3.5
            .native_record => .native_record, // E3.14
        };
    }
    pub fn listHead(_: *Ctx, t: Term) Term {
        return t.cons.head;
    }
    pub fn listTail(_: *Ctx, t: Term) Term {
        return t.cons.tail;
    }
    pub fn tupleArity(_: *Ctx, t: Term) usize {
        return t.tuple.len;
    }
    pub fn tupleElem(_: *Ctx, t: Term, i: usize) Term {
        return t.tuple[i];
    }
    pub fn funLabel(_: *Ctx, t: Term) u32 {
        return @intCast(t.fun_.label);
    }
    pub fn funArity(_: *Ctx, t: Term) u8 {
        return @intCast(t.fun_.arity);
    }

    // ---- E7.1: external funs (fun M:F/A) — module/function are atom Terms ----
    pub fn makeExportFun(ctx: *Ctx, module: Term, function: Term, arity: u8) !Term {
        // module/function names live in the (VM-global) atom table, exactly
        // like `.atom` — store the name slices directly (stable lifetime).
        return mk(ctx, .{ .export_fun = .{
            .module = module.atom,
            .function = function.atom,
            .arity = arity,
        } });
    }
    pub fn repIsExportFun(_: *Ctx, t: Term) bool {
        return t.* == .export_fun;
    }
    pub fn exportFunModuleName(_: *Ctx, t: Term) []const u8 {
        return t.export_fun.module;
    }
    pub fn exportFunFuncName(_: *Ctx, t: Term) []const u8 {
        return t.export_fun.function;
    }
    pub fn exportFunArity(_: *Ctx, t: Term) u8 {
        return @intCast(t.export_fun.arity);
    }

    // ---- observations ------------------------------------------------------

    pub fn compare(_: *Ctx, a: Term, b: Term) Order {
        return spec.order(a, b);
    }
    pub fn compareExact(_: *Ctx, a: Term, b: Term) Order {
        return spec.orderExact(a, b);
    }
    pub fn eql(_: *Ctx, a: Term, b: Term) bool {
        return spec.eql(a, b);
    }
    pub fn eqlExact(_: *Ctx, a: Term, b: Term) bool {
        return spec.eqlExact(a, b);
    }
    pub fn hashTerm(_: *Ctx, t: Term) u64 {
        return spec.hashValue(t);
    }
    /// The oracle's denotation is the identity: its terms ARE spec trees.
    pub fn denote(_: *Ctx, _: std.mem.Allocator, t: Term) !*const spec.Value {
        return t;
    }
};

// ============================================================================
// PART 3b: FINAL ENCODING — erts-style tagged words on a process heap
//
// 64-bit word, primary tag in bits 0..1 (as in erts/emulator):
//   00 header (on-heap only) — subtag in bits 2..6 (E3.14: 5-bit field):
//        0b0000 tuple arityval; 0b0010 pos bignum; 0b0011 neg bignum
//        0b0100 float; 0b0110 binary; 0b1000 flatmap; 0b1001 hashmap root
//        0b1010 hashmap node; 0b1011 hashmap collision node;
//        0b10000 native record (E3.14)
//        payload word count in bits 7..
//   01 list  — heap index << 2 of a 2-word cell [head, tail]
//   10 boxed — heap index << 2 of a header word
//   11 immediate — bits 2..3: 11 = small int (i60 payload in bits 4..63)
//                              10 = immed2 → bits 4..5: 00 atom (idx << 6)
//                                                        11 nil (word 0x3B)
// ============================================================================

pub const FinalTerms = struct {
    pub const Term = u64;

    const TAG_MASK: u64 = 0b11;
    const TAG_LIST: u64 = 0b01;
    const TAG_BOXED: u64 = 0b10;
    const SMALL_SUFFIX: u64 = 0b1111;
    const ATOM_SUFFIX: u64 = 0b001011;
    const NIL_WORD: u64 = 0b111011;
    const IMM_MASK6: u64 = 0b111111;

    const SUBTAG_TUPLE: u64 = 0b0000;
    const SUBTAG_POS_BIG: u64 = 0b0010;
    const SUBTAG_NEG_BIG: u64 = 0b0011;
    const SUBTAG_FLOAT: u64 = 0b0100;
    const SUBTAG_FUN: u64 = 0b0101;
    const SUBTAG_BINARY: u64 = 0b0110;
    const SUBTAG_FLATMAP: u64 = 0b1000;
    const SUBTAG_HMAP_ROOT: u64 = 0b1001;
    const SUBTAG_HMAP_NODE: u64 = 0b1010;
    const SUBTAG_HMAP_COLL: u64 = 0b1011;
    /// E3.1: general bit-vector, rank 9 (WITH SUBTAG_BINARY). 0b0001 is
    /// unused subtag space (0b1111 is reserved for the GC forwarding word).
    const SUBTAG_BITSTRING: u64 = 0b0001;
    /// E3.3: the bit-syntax MATCH CONTEXT — a VM-INTERNAL control value, never
    /// a real Erlang term (never printed, never sent, never a map key). Boxed
    /// like every other compound value so the EXISTING `Src`/`Dst`
    /// resolve/setDst register discipline carries it for free — no new
    /// Machine field, no new register-value union. Layout: header(MATCHCTX,2)
    /// | offset_bits (RAW word, NOT a term slot) | bin (a TERM slot: the
    /// matched bitstring/binary). The raw-then-term field order (offset
    /// first) matches the FLATMAP/HMAP_ROOT/HMAP_NODE `term_from = 2`
    /// pattern (one raw prefix word, then term slots) used by GC evacuation
    /// (`Collector.evac`) and `gcCopy`/`checkNoOldToYoung` below — so those
    /// generic heap-walkers need only ONE extra case-list entry each, not a
    /// bespoke traversal. `bs_start_match3/4` construct it; `bs_get_*`/
    /// `bs_skip_bits2`/`bs_match`'s consuming commands PRODUCE A FRESH
    /// MatchCtx term with the advanced offset (functional update, like every
    /// other term in this VM — no in-place mutation, so no aliasing hazard if
    /// a `move` copies the register) and `setDst` it back to the SAME
    /// register the input ctx came from (the BEAM `Ctx` operand is both read
    /// and write). `eqMachines` observes it through `denote`, which maps it
    /// to a synthetic 2-tuple `{bin_denotation, offset_bits}` (see `denoteC`
    /// below) — so two independently-built MatchCtx terms with the same bin
    /// content and the same cursor compare EQUAL even though they live at
    /// different heap words (observational equality, never pointer/word
    /// identity — the cursor-monotonicity law's differential half rides on
    /// this).
    const SUBTAG_MATCHCTX: u64 = 0b0111;

    /// E3.5: pid/reference/port — all THREE boxed with an all-raw payload
    /// (no term slots, exactly like bignum/float/binary), so GC evacuation
    /// and `checkNoOldToYoung` need no new case at all (they already bucket
    /// unlisted subtags as "no term slots" — see `Collector.evac`'s
    /// `term_from` switch below). 0b1100/0b1101/0b1110 were the three
    /// unused 4-bit subtag codes (0b1111 is the GC forwarding word).
    /// E5.7 WIDENED each with two trailing RAW words — a node atom INDEX and
    /// a creation stamp — so a foreign-node identity (ETF `binary_to_term` of
    /// a NEW_PID_EXT/NEW_PORT_EXT/NEWER_REFERENCE_EXT from another node) is a
    /// first-class term (`node/1` observes it; the ETF codec round-trips it
    /// byte-exactly). Local terms carry the interned `local_node_name` index
    /// and creation 0, so every pre-E5.7 order/hash/print law is unchanged.
    /// The node index is a RAW word (an atom index, never a term slot), so it
    /// inherits the "atoms move freely within a shared atom table" gcCopy
    /// invariant unchanged — cross-node transfer is via ETF bytes, never gc.
    ///   SUBTAG_REF:  header(REF,5)   | w0 | w1 | w2 | node_idx | creation
    ///   SUBTAG_PORT: header(PORT,3)  | number | node_idx | creation
    ///   SUBTAG_PID:  header(PID,4)   | number | serial | node_idx | creation
    const SUBTAG_REF: u64 = 0b1100;
    const SUBTAG_PORT: u64 = 0b1101;
    const SUBTAG_PID: u64 = 0b1110;

    /// E3.14: native record — the 4-bit subtag space was full (0b1111 is the
    /// GC forwarding word), so the subtag field was widened to 5 bits and
    /// this is the first code beyond it. Layout:
    ///   SUBTAG_NATIVE_RECORD: header(NR, 3+2n) | module | name | exported |
    ///                         key_0..key_{n-1} | val_0..val_{n-1}
    /// where module/name/keys are atom immediates and `exported` is small 0/1;
    /// field count n = (headerCount - 3) / 2.
    const SUBTAG_NATIVE_RECORD: u64 = 0b10000;

    /// E7.1: external fun `fun M:F/A` (EXPORT_EXT). The next 5-bit subtag code
    /// after the native record. All-raw payload (module/function are atom
    /// immediates, arity a raw word) → no term slots, so GC evacuation and
    /// `checkNoOldToYoung` bucket it with bignum/float/ref/port/pid.
    ///   SUBTAG_EXPORT_FUN: header(EXPORT_FUN,3) | module_atom | function_atom | arity
    const SUBTAG_EXPORT_FUN: u64 = 0b10001;
    // e49-binary-refc: a SUB-BINARY VIEW (erts ErlSubBin) — a zero-copy window
    // {offset, len, base} into a byte-aligned base binary. Layout:
    //   header(SUBTAG_SUBBIN, 3) | offset | len | <TERM SLOT: base>
    // The base is a ROOTED term slot (evac term_from = 3), so the copying GC
    // relocates + SHARES it and the window survives across collections with
    // the offset still valid (bytes move with the base). `binBytesOf`
    // resolves it; every consumer (eql/hash/compare/etf/denote) reads through
    // that one choke point, so no per-site sub-binary logic is needed.
    const SUBTAG_SUBBIN: u64 = 0b10010;

    // e51-t2 procbin-refc: a REFCOUNTED off-heap binary (erts `ProcBin`). The
    //   heap box is exactly two words: header(SUBTAG_PROCBIN, 1) | @intFromPtr(*Refc)
    // — the payload is a SEPARATELY gpa-allocated `Refc` (count + bytes), so it
    // survives being SHARED across heaps: `gcCopy` (send/spawn/reply) RETAINS
    // (bumps count) and copies only the one pointer word instead of flattening
    // the bytes — the share-on-send win. The pointer is one FULL u64 word (never
    // `@truncate`d — that would corrupt the high 32 bits and abort on the next
    // `@ptrFromInt` with a misaligned pointer). count=1 in the header means the
    // scanners (evac / checkNoOldToYoung) skip exactly the pointer word.
    //
    // gap-binary-share-across-gc SHARE-ACROSS-GC (supersedes the e51-t2 first
    //   increment's borrow-on-flatten): the copying collector (`Collector.evac`)
    //   RELOCATES only the 2-word ProcBin box (header + pointer) — the off-heap
    //   payload STAYS PUT and is shared, never byte-copied — exactly like erts,
    //   whose copying GC never copies a refc binary's payload. Refcount discipline
    //   is kept exact across a collection by `finishInPlace`'s reconciliation:
    //     • a ProcBin below the water line (old/literal space) is unmoved and LIVE
    //       → its strong ref is kept untouched (NO premature free of a literal-area
    //       payload — the U1 UAF the first increment sidestepped by flattening is
    //       now closed properly, by keeping below-water refs);
    //     • a SURVIVING ProcBin (reachable, relocated) keeps its ref, count
    //       unchanged (the reference rides along with the moved box);
    //     • a DEAD ProcBin (unreachable this collect) releases ONE strong ref —
    //       the payload frees IFF the count reaches 0 (its last box died), never
    //       while a live box still points at it, and at most once.
    //   So `Refc.count == number of live ProcBin boxes` is an invariant preserved
    //   across every GC. `Ctx.refcs` records the box INDEX of each owned ProcBin
    //   (the Refc pointer is `words[box+1]`) so the reconciliation can classify
    //   below-water / survivor / dead without a linear heap scan. Two heaps
    //   sharing one payload: GC-ing one heap that drops its box does not free the
    //   payload while the other heap's box lives (the count stays ≥ 1).
    //   std.testing.allocator + the count invariant prove zero leaks AND zero
    //   double-frees.
    const SUBTAG_PROCBIN: u64 = 0b10011;

    /// e51-t2: an off-heap refcounted binary payload. One `Refc` per distinct
    /// payload; many heap boxes (across heaps) may point at it. `count` is the
    /// number of live boxes holding it (one strong ref each, tracked in the
    /// owning `Ctx.refcs`).
    pub const Refc = struct { count: usize, bytes: []u8 };

    /// M2 engineering bound on bignum magnitude. The algebra is
    /// unbounded; this is a documented final-encoding capacity, asserted.
    pub const max_limbs = 1024;

    pub const Ctx = struct {
        gpa: std.mem.Allocator,
        atoms: *AtomTable,
        words: std.ArrayList(u64),
        // E3.5: the reference-freshness SOURCE (see the module doc comment
        // and `InitialTerms.Ctx`'s twin field).
        ref_counter: u64 = 0,
        // e51-t2 procbin-refc: strong references this ctx holds to off-heap
        // refcounted binaries — one entry per live PROCBIN box in `words`.
        // Stored as the box's WORD INDEX (not the `*Refc` directly): the Refc
        // pointer is always readable from `words[box + 1]`, and the index lets an
        // in-place collect (`finishInPlace`) tell a below-water box (unmoved) from
        // a collected-region survivor (relocated) from a dead box (released) —
        // the gap-binary-share-across-gc reconciliation. Released at deinit;
        // structure-driven (never a linear heap scan, which would mis-read a raw
        // payload word as a header — the reverted bug).
        refcs: std.ArrayList(usize) = .empty,

        pub fn init(gpa: std.mem.Allocator, atoms: *AtomTable) Ctx {
            return .{ .gpa = gpa, .atoms = atoms, .words = .empty };
        }
        pub fn deinit(self: *Ctx) void {
            // e51-t2: drop this ctx's strong refs; free a payload at the last one.
            // The Refc pointer lives in the box's second word (`words[box + 1]`).
            for (self.refcs.items) |box| {
                const r: *Refc = @ptrFromInt(self.words.items[box + 1]);
                refcRelease(self.gpa, r);
            }
            self.refcs.deinit(self.gpa);
            self.words.deinit(self.gpa);
        }
        fn alloc(self: *Ctx, n: usize) !usize {
            const base = self.words.items.len;
            try self.words.appendNTimes(self.gpa, 0, n);
            return base;
        }
    };

    // ---- constructors -----------------------------------------------------

    pub fn int(_: *Ctx, i: i64) Term {
        std.debug.assert(fitsSmall(i));
        return (@as(u64, @bitCast(i)) << 4) | SMALL_SUFFIX;
    }

    /// Canonical at construction: fits-small values are ALWAYS encoded small.
    pub fn intFromI128(ctx: *Ctx, v: i128) !Term {
        if (v >= -(1 << 59) and v < (1 << 59)) return int(ctx, @intCast(v));
        const mag: u128 = @abs(v);
        var limbs: [2]u64 = .{ @truncate(mag), @truncate(mag >> 64) };
        const n: usize = if (limbs[1] == 0) 1 else 2;
        return makeBig(ctx, v > 0, limbs[0..n]);
    }

    pub fn float(ctx: *Ctx, f: f64) Term {
        std.debug.assert(std.math.isFinite(f));
        return makeFloat(ctx, f) catch @panic("heap OOM on float");
    }

    /// Construct an integer from raw magnitude limbs (M9: wire decode).
    /// Canonical: small-fitting values are encoded small.
    pub fn intFromLimbs(ctx: *Ctx, positive: bool, limbs: []const u64) !Term {
        var buf: [max_limbs]u64 = undefined;
        const n = limbsEffLen(limbs);
        std.debug.assert(n <= max_limbs);
        @memcpy(buf[0..n], limbs[0..n]);
        return normalized(ctx, positive, buf[0..n]);
    }
    fn makeFloat(ctx: *Ctx, f: f64) !Term {
        const base = try ctx.alloc(2);
        ctx.words.items[base] = header(SUBTAG_FLOAT, 1);
        ctx.words.items[base + 1] = @bitCast(f);
        return (@as(u64, base) << 2) | TAG_BOXED;
    }

    /// The `[]` (nil) term as a plain constant — usable without a live `Ctx`
    /// (its encoding is a fixed immediate). `randProgram` needs a valid tag
    /// term but has no heap; this is the canonical ctx-free term literal.
    pub const nil_term: Term = NIL_WORD;
    /// The atom term for `idx` computed WITHOUT a `Ctx` — atoms are immediates,
    /// so the encoding never touches the heap. Callers with an interned index
    /// but no `Ctx` (the loader's `is_tagged_tuple` decode) use this; `atom`
    /// below is the `*Ctx` sibling the Term signature requires.
    pub fn atomTerm(idx: AtomIdx) Term {
        return (@as(u64, idx) << 6) | ATOM_SUFFIX;
    }
    pub fn atom(_: *Ctx, idx: AtomIdx) Term {
        return atomTerm(idx);
    }
    pub fn nil(_: *Ctx) Term {
        return nil_term;
    }
    pub fn cons(ctx: *Ctx, head: Term, tail: Term) !Term {
        const base = try ctx.alloc(2);
        ctx.words.items[base] = head;
        ctx.words.items[base + 1] = tail;
        return (@as(u64, base) << 2) | TAG_LIST;
    }
    pub fn tuple(ctx: *Ctx, elems: []const Term) !Term {
        const base = try ctx.alloc(1 + elems.len);
        ctx.words.items[base] = header(SUBTAG_TUPLE, elems.len);
        for (elems, 0..) |e, k| ctx.words.items[base + 1 + k] = e;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }

    /// erts ERL_ONHEAP_BIN_LIMIT: binaries at/above this many bytes are stored
    /// OFF-HEAP (refcounted), smaller ones on-heap. e51-t2 reroute.
    pub const onheap_bin_limit: usize = 64;

    pub fn binary(ctx: *Ctx, bytes: []const u8) !Term {
        // e51-t2 REROUTE: a large binary is built OFF-HEAP as a refcounted
        // ProcBin (erts heap-vs-refc split at ERL_ONHEAP_BIN_LIMIT). This is
        // what makes the share-on-send win REAL in production — a ≥64B binary is
        // now a ProcBin the moment it is built, so `gcCopy` (send/spawn/reply)
        // SHARES its payload instead of flattening — and (gap-binary-share-across-gc)
        // that sharing now also survives a collection: the copying GC relocates the
        // box but not the payload, with exact refcount reconciliation in
        // `finishInPlace` (see SUBTAG_PROCBIN's doc comment).
        if (bytes.len >= onheap_bin_limit) return procBinary(ctx, bytes);
        const nwords = (bytes.len + 7) / 8;
        const base = try ctx.alloc(2 + nwords);
        ctx.words.items[base] = header(SUBTAG_BINARY, 1 + nwords);
        ctx.words.items[base + 1] = bytes.len;
        const dst = std.mem.sliceAsBytes(ctx.words.items[base + 2 .. base + 2 + nwords]);
        @memcpy(dst[0..bytes.len], bytes);
        return (@as(u64, base) << 2) | TAG_BOXED;
    }

    /// e51-t2: release one strong ref to an off-heap payload; free at zero.
    fn refcRelease(gpa: std.mem.Allocator, r: *Refc) void {
        r.count -= 1;
        if (r.count == 0) {
            gpa.free(r.bytes);
            gpa.destroy(r);
        }
    }

    /// e51-t2 procbin-refc: build a REFCOUNTED off-heap binary. The bytes are
    /// gpa-copied ONCE into a fresh `Refc`; the heap box is two words
    /// (header + the u64 pointer). This ctx takes the first strong ref (count=1,
    /// recorded in `refcs`). A later `gcCopy` into another heap SHARES this same
    /// payload (retain) instead of copying the bytes — the send-side win.
    pub fn procBinary(ctx: *Ctx, bytes: []const u8) !Term {
        const r = try ctx.gpa.create(Refc);
        errdefer ctx.gpa.destroy(r);
        r.* = .{ .count = 1, .bytes = try ctx.gpa.dupe(u8, bytes) };
        errdefer ctx.gpa.free(r.bytes);
        const base = try ctx.alloc(2);
        ctx.words.items[base] = header(SUBTAG_PROCBIN, 1);
        ctx.words.items[base + 1] = @intFromPtr(r); // ONE full u64 word — never @truncate'd
        try ctx.refcs.append(ctx.gpa, base); // record the box index (Refc read from words[base+1])
        return (@as(u64, base) << 2) | TAG_BOXED;
    }
    fn procBinRefc(ctx: *const Ctx, w: Term) *Refc {
        return @ptrFromInt(ctx.words.items[ptrIdx(w) + 1]);
    }
    /// Introspection (gap-binary-share-across-gc laws): the strong refcount of a
    /// ProcBin's off-heap payload — the number of live ProcBin boxes (across all
    /// heaps) that hold it. Used by the REFCOUNT-CONSERVATION law to observe that
    /// `count == live-box count` is preserved across a collection.
    pub fn procBinRefCount(ctx: *const Ctx, w: Term) usize {
        return procBinRefc(ctx, w).count;
    }

    /// e49-binary-refc: build a zero-copy sub-binary window into `base_bin`
    /// (a byte-aligned binary or another sub-binary — chains are COLLAPSED so
    /// a window is always one hop from a real binary). Caller guarantees
    /// `offset + len <= base byte length` (binary:part validates). Immediates
    /// only: no byte copy — the whole point.
    pub fn subBinary(ctx: *Ctx, base_bin: Term, offset: usize, len: usize) !Term {
        var real_base = base_bin;
        var real_off = offset;
        if ((base_bin & TAG_MASK) == TAG_BOXED and headerSubtag(ctx, base_bin) == SUBTAG_SUBBIN) {
            const bb = ptrIdx(base_bin);
            real_off += @intCast(ctx.words.items[bb + 1]); // add the parent window's offset
            real_base = ctx.words.items[bb + 3]; // hop to the parent's base
        }
        const b = try ctx.alloc(4);
        ctx.words.items[b] = header(SUBTAG_SUBBIN, 3);
        ctx.words.items[b + 1] = real_off;
        ctx.words.items[b + 2] = len;
        ctx.words.items[b + 3] = real_base;
        return (@as(u64, b) << 2) | TAG_BOXED;
    }
    pub fn repIsSubBin(ctx: *const Ctx, w: Term) bool {
        return (w & TAG_MASK) == TAG_BOXED and headerSubtag(ctx, w) == SUBTAG_SUBBIN;
    }

    /// E3.1 layout: header(BITSTRING, 1+nwords) | bit_len | packed bytes.
    /// `bytes` must hold at least `ceil(bit_len/8)` live bytes; the stored
    /// copy is CANONICALIZED (last byte's padding bits masked to zero — the
    /// canonical-padding invariant, enforced HERE, once).
    ///
    /// MUTANT 2 site: deleting the `if (rem != 0)` masking below leaves
    /// junk bits in the last byte, breaking eql/hash coherence between two
    /// equal-denotation bitstrings built with different incoming padding.
    pub fn bitstring(ctx: *Ctx, bytes: []const u8, bit_len: usize) !Term {
        std.debug.assert(bytes.len * 8 >= bit_len);
        const blen = (bit_len + 7) / 8;
        const nwords = (blen + 7) / 8;
        const base = try ctx.alloc(2 + nwords);
        ctx.words.items[base] = header(SUBTAG_BITSTRING, 1 + nwords);
        ctx.words.items[base + 1] = bit_len;
        const dst = std.mem.sliceAsBytes(ctx.words.items[base + 2 .. base + 2 + nwords]);
        @memset(dst, 0);
        @memcpy(dst[0..blen], bytes[0..blen]);
        const rem = bit_len % 8;
        if (rem != 0) {
            const keep_mask: u8 = @as(u8, 0xFF) << @intCast(8 - rem);
            dst[blen - 1] &= keep_mask;
        }
        return (@as(u64, base) << 2) | TAG_BOXED;
    }

    pub fn repIsBitstring(ctx: *const Ctx, w: Term) bool {
        return (w & TAG_MASK) == TAG_BOXED and headerSubtag(ctx, w) == SUBTAG_BITSTRING;
    }
    pub fn bitstringBits(ctx: *const Ctx, w: Term) Bits {
        const base = ptrIdx(w);
        const bit_len: usize = @intCast(ctx.words.items[base + 1]);
        const blen = (bit_len + 7) / 8;
        const nwords = (blen + 7) / 8;
        const bytes = std.mem.sliceAsBytes(ctx.words.items[base + 2 .. base + 2 + nwords])[0..blen];
        return .{ .bytes = bytes, .bit_len = bit_len };
    }
    /// The shared bit-vector view over EITHER binary-family representation
    /// (used by cross-family compare/hash — the order-family homomorphism).
    fn finalBitsOf(ctx: *const Ctx, w: Term) Bits {
        if (headerSubtag(ctx, w) == SUBTAG_BITSTRING) return bitstringBits(ctx, w);
        return bsa.fromBinary(binBytesOf(ctx, w));
    }

    /// E3.2: public alias of `finalBitsOf` — the bit-vector view over EITHER
    /// binary-family representation (true binary OR bitstring). Used by
    /// `bit_size/1` (`bifs/erlang.zig`) and the bitstring conversion BIFs
    /// (`bifs/conv.zig`) so neither reinvents the SUBTAG dispatch `byte_size`
    /// already got burned by (E3.1-fix note above `binBytesOf`).
    pub fn bitsOf(ctx: *const Ctx, w: Term) Bits {
        return finalBitsOf(ctx, w);
    }

    /// E3.3: construct a match context {bin, offset_bits}. `bin` must already
    /// be a binary/bitstring term (the caller — `bs_start_match`'s executor —
    /// checks that BEFORE calling; this constructor trusts its caller, like
    /// `tuple`/`makeFun`).
    pub fn makeMatchCtx(ctx: *Ctx, bin: Term, offset_bits: usize) !Term {
        const base = try ctx.alloc(3);
        ctx.words.items[base] = header(SUBTAG_MATCHCTX, 2);
        ctx.words.items[base + 1] = offset_bits;
        ctx.words.items[base + 2] = bin;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }
    pub fn repIsMatchCtx(ctx: *const Ctx, w: Term) bool {
        return (w & TAG_MASK) == TAG_BOXED and headerSubtag(ctx, w) == SUBTAG_MATCHCTX;
    }
    pub fn matchCtxOffset(ctx: *const Ctx, w: Term) usize {
        return @intCast(ctx.words.items[ptrIdx(w) + 1]);
    }
    pub fn matchCtxBin(ctx: *const Ctx, w: Term) Term {
        return ctx.words.items[ptrIdx(w) + 2];
    }
    /// Functional update: a FRESH MatchCtx term with the same `bin` and a new
    /// cursor — see the SUBTAG_MATCHCTX doc comment (no in-place mutation).
    pub fn withMatchCtxOffset(ctx: *Ctx, w: Term, new_offset_bits: usize) !Term {
        return makeMatchCtx(ctx, matchCtxBin(ctx, w), new_offset_bits);
    }

    // ---- E3.5: pid / reference / port (term-kind construction only — no
    // live process/port/dist semantics; see the module doc comment) --------

    /// E5.7: the interned index of `local_node_name` in this Ctx's atom table
    /// (idempotent). Every locally-constructed pid/port/ref stamps this.
    pub fn localNodeIdx(ctx: *Ctx) !AtomIdx {
        return ctx.atoms.intern(local_node_name);
    }

    pub fn pid(ctx: *Ctx, number: u64, serial: u64) !Term {
        return pidExt(ctx, number, serial, try localNodeIdx(ctx), 0);
    }
    /// E5.7: a pid on a FOREIGN node (`node_idx` interned in `ctx.atoms`).
    pub fn pidExt(ctx: *Ctx, number: u64, serial: u64, node_idx: AtomIdx, creation: u32) !Term {
        const base = try ctx.alloc(5);
        ctx.words.items[base] = header(SUBTAG_PID, 4);
        ctx.words.items[base + 1] = number;
        ctx.words.items[base + 2] = serial;
        ctx.words.items[base + 3] = node_idx;
        ctx.words.items[base + 4] = creation;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }
    pub fn repIsPid(ctx: *const Ctx, w: Term) bool {
        return (w & TAG_MASK) == TAG_BOXED and headerSubtag(ctx, w) == SUBTAG_PID;
    }
    pub fn pidNumber(ctx: *const Ctx, w: Term) u64 {
        return ctx.words.items[ptrIdx(w) + 1];
    }
    pub fn pidSerial(ctx: *const Ctx, w: Term) u64 {
        return ctx.words.items[ptrIdx(w) + 2];
    }
    pub fn pidNode(ctx: *const Ctx, w: Term) AtomIdx {
        return @intCast(ctx.words.items[ptrIdx(w) + 3]);
    }
    pub fn pidNodeName(ctx: *const Ctx, w: Term) []const u8 {
        return ctx.atoms.nameOf(pidNode(ctx, w));
    }
    pub fn pidCreation(ctx: *const Ctx, w: Term) u32 {
        return @intCast(ctx.words.items[ptrIdx(w) + 4]);
    }

    /// Construct a reference from caller-supplied wire words (ETF decode's
    /// path). Freshness (the term-kind law) is NOT this constructor's job —
    /// see `freshRef`/`freshRefWords`.
    pub fn ref(ctx: *Ctx, words: [3]u32) !Term {
        return refExt(ctx, words, try localNodeIdx(ctx), 0);
    }
    /// E5.7: a reference on a FOREIGN node.
    pub fn refExt(ctx: *Ctx, words: [3]u32, node_idx: AtomIdx, creation: u32) !Term {
        const base = try ctx.alloc(6);
        ctx.words.items[base] = header(SUBTAG_REF, 5);
        ctx.words.items[base + 1] = words[0];
        ctx.words.items[base + 2] = words[1];
        ctx.words.items[base + 3] = words[2];
        ctx.words.items[base + 4] = node_idx;
        ctx.words.items[base + 5] = creation;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }
    /// The freshness-guaranteeing generator: increments the Ctx-owned
    /// monotonic counter, so N calls on one Ctx are pairwise `=/=`.
    pub fn freshRefWords(ctx: *Ctx) [3]u32 {
        ctx.ref_counter += 1;
        const c = ctx.ref_counter;
        return .{ @truncate(c), @truncate(c >> 32), 0 };
    }
    pub fn freshRef(ctx: *Ctx) !Term {
        return ref(ctx, freshRefWords(ctx));
    }
    pub fn repIsRef(ctx: *const Ctx, w: Term) bool {
        return (w & TAG_MASK) == TAG_BOXED and headerSubtag(ctx, w) == SUBTAG_REF;
    }
    pub fn refWords(ctx: *const Ctx, w: Term) [3]u32 {
        const base = ptrIdx(w);
        return .{
            @truncate(ctx.words.items[base + 1]),
            @truncate(ctx.words.items[base + 2]),
            @truncate(ctx.words.items[base + 3]),
        };
    }
    pub fn refNode(ctx: *const Ctx, w: Term) AtomIdx {
        return @intCast(ctx.words.items[ptrIdx(w) + 4]);
    }
    pub fn refNodeName(ctx: *const Ctx, w: Term) []const u8 {
        return ctx.atoms.nameOf(refNode(ctx, w));
    }
    pub fn refCreation(ctx: *const Ctx, w: Term) u32 {
        return @intCast(ctx.words.items[ptrIdx(w) + 5]);
    }

    pub fn port(ctx: *Ctx, number: u64) !Term {
        return portExt(ctx, number, try localNodeIdx(ctx), 0);
    }
    /// E5.7: a port on a FOREIGN node.
    pub fn portExt(ctx: *Ctx, number: u64, node_idx: AtomIdx, creation: u32) !Term {
        const base = try ctx.alloc(4);
        ctx.words.items[base] = header(SUBTAG_PORT, 3);
        ctx.words.items[base + 1] = number;
        ctx.words.items[base + 2] = node_idx;
        ctx.words.items[base + 3] = creation;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }
    pub fn repIsPort(ctx: *const Ctx, w: Term) bool {
        return (w & TAG_MASK) == TAG_BOXED and headerSubtag(ctx, w) == SUBTAG_PORT;
    }
    pub fn portNumber(ctx: *const Ctx, w: Term) u64 {
        return ctx.words.items[ptrIdx(w) + 1];
    }
    pub fn portNode(ctx: *const Ctx, w: Term) AtomIdx {
        return @intCast(ctx.words.items[ptrIdx(w) + 2]);
    }
    pub fn portNodeName(ctx: *const Ctx, w: Term) []const u8 {
        return ctx.atoms.nameOf(portNode(ctx, w));
    }
    pub fn portCreation(ctx: *const Ctx, w: Term) u32 {
        return @intCast(ctx.words.items[ptrIdx(w) + 3]);
    }

    // ---- E3.14: native records --------------------------------------------
    /// Layout: header(NR, 3+2n) | module | name | exported(small 0/1) |
    ///         key_0..key_{n-1} | val_0..val_{n-1}
    /// module/name/keys are atom immediates; values are arbitrary terms.
    pub fn nativeRecord(ctx: *Ctx, module: Term, name: Term, is_exported: bool, keys: []const Term, values: []const Term) !Term {
        std.debug.assert(keys.len == values.len);
        const n = keys.len;
        const base = try ctx.alloc(4 + 2 * n);
        ctx.words.items[base] = header(SUBTAG_NATIVE_RECORD, 3 + 2 * n);
        ctx.words.items[base + 1] = module;
        ctx.words.items[base + 2] = name;
        ctx.words.items[base + 3] = int(ctx, if (is_exported) 1 else 0);
        for (keys, 0..) |k, i| ctx.words.items[base + 4 + i] = k;
        for (values, 0..) |v, i| ctx.words.items[base + 4 + n + i] = v;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }
    pub fn repIsNativeRecord(ctx: *const Ctx, w: Term) bool {
        return (w & TAG_MASK) == TAG_BOXED and headerSubtag(ctx, w) == SUBTAG_NATIVE_RECORD;
    }
    pub fn nrModule(ctx: *const Ctx, w: Term) Term {
        return ctx.words.items[ptrIdx(w) + 1];
    }
    pub fn nrName(ctx: *const Ctx, w: Term) Term {
        return ctx.words.items[ptrIdx(w) + 2];
    }
    pub fn nrIsExported(ctx: *const Ctx, w: Term) bool {
        return smallVal(ctx.words.items[ptrIdx(w) + 3]) != 0;
    }
    pub fn nrFieldCount(ctx: *const Ctx, w: Term) usize {
        return (headerCount(ctx, w) - 3) / 2;
    }
    pub fn nrKeyAt(ctx: *const Ctx, w: Term, i: usize) Term {
        return ctx.words.items[ptrIdx(w) + 4 + i];
    }
    pub fn nrValAt(ctx: *const Ctx, w: Term, i: usize) Term {
        const n = nrFieldCount(ctx, w);
        return ctx.words.items[ptrIdx(w) + 4 + n + i];
    }
    /// Linear lookup by EXACT key equality (atoms compare by index==index for
    /// the same interned name); returns the field's value or null.
    pub fn nrLookup(ctx: *const Ctx, w: Term, key: Term) ?Term {
        const n = nrFieldCount(ctx, w);
        for (0..n) |i| {
            if (cmp(ctx, nrKeyAt(ctx, w, i), key, .exact) == .eq) return nrValAt(ctx, w, i);
        }
        return null;
    }

    /// Fun layout: header(FUN, 2+n) | label | arity | env0..env(n-1)
    pub fn makeFun(ctx: *Ctx, label: u32, arity: u8, env: []const Term) !Term {
        const base = try ctx.alloc(3 + env.len);
        ctx.words.items[base] = header(SUBTAG_FUN, 2 + env.len);
        ctx.words.items[base + 1] = label;
        ctx.words.items[base + 2] = arity;
        for (env, 0..) |e, k| ctx.words.items[base + 3 + k] = e;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }

    pub fn repIsFun(ctx: *const Ctx, w: Term) bool {
        return (w & TAG_MASK) == TAG_BOXED and headerSubtag(ctx, w) == SUBTAG_FUN;
    }
    pub fn funLabel(ctx: *const Ctx, w: Term) u32 {
        return @intCast(ctx.words.items[ptrIdx(w) + 1]);
    }
    pub fn funArity(ctx: *const Ctx, w: Term) u8 {
        return @intCast(ctx.words.items[ptrIdx(w) + 2]);
    }
    fn funEnvLen(ctx: *const Ctx, w: Term) usize {
        return headerCount(ctx, w) - 2;
    }
    fn funEnvAt(ctx: *const Ctx, w: Term, i: usize) Term {
        return ctx.words.items[ptrIdx(w) + 3 + i];
    }

    // ---- E7.1: external funs (fun M:F/A) ----------------------------------
    /// module/function are atom immediates (interned); arity a raw word.
    pub fn makeExportFun(ctx: *Ctx, module: Term, function: Term, arity: u8) !Term {
        std.debug.assert(isAtom(module) and isAtom(function));
        const base = try ctx.alloc(4);
        ctx.words.items[base] = header(SUBTAG_EXPORT_FUN, 3);
        ctx.words.items[base + 1] = module;
        ctx.words.items[base + 2] = function;
        ctx.words.items[base + 3] = arity;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }
    pub fn repIsExportFun(ctx: *const Ctx, w: Term) bool {
        return (w & TAG_MASK) == TAG_BOXED and headerSubtag(ctx, w) == SUBTAG_EXPORT_FUN;
    }
    pub fn exportFunModule(ctx: *const Ctx, w: Term) Term {
        return ctx.words.items[ptrIdx(w) + 1];
    }
    pub fn exportFunFunction(ctx: *const Ctx, w: Term) Term {
        return ctx.words.items[ptrIdx(w) + 2];
    }
    pub fn exportFunModuleIdx(ctx: *const Ctx, w: Term) AtomIdx {
        return atomIdx(exportFunModule(ctx, w));
    }
    pub fn exportFunFuncIdx(ctx: *const Ctx, w: Term) AtomIdx {
        return atomIdx(exportFunFunction(ctx, w));
    }
    pub fn exportFunModuleName(ctx: *const Ctx, w: Term) []const u8 {
        return ctx.atoms.nameOf(exportFunModuleIdx(ctx, w));
    }
    pub fn exportFunFuncName(ctx: *const Ctx, w: Term) []const u8 {
        return ctx.atoms.nameOf(exportFunFuncIdx(ctx, w));
    }
    pub fn exportFunArity(ctx: *const Ctx, w: Term) u8 {
        return @intCast(ctx.words.items[ptrIdx(w) + 3]);
    }

    fn header(subtag: u64, count: usize) u64 {
        // E3.14: subtag is a 5-bit field (bits 2..7); count starts at bit 7.
        // Widened from 4 bits when native records exhausted the 4-bit space
        // (0b1111 is the GC forwarding marker). SUBTAG_FWD stays 15; the new
        // native-record subtag is 16.
        return (@as(u64, count) << 7) | (subtag << 2);
    }

    fn makeBig(ctx: *Ctx, positive: bool, limbs: []const u64) !Term {
        std.debug.assert(limbs.len >= 1 and limbs.len <= max_limbs);
        std.debug.assert(limbs[limbs.len - 1] != 0); // normalized
        const base = try ctx.alloc(1 + limbs.len);
        ctx.words.items[base] =
            header(if (positive) SUBTAG_POS_BIG else SUBTAG_NEG_BIG, limbs.len);
        for (limbs, 0..) |l, k| ctx.words.items[base + 1 + k] = l;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }

    // ---- decoders ----------------------------------------------------------

    pub fn repIsSmall(w: Term) bool {
        return (w & 0b1111) == SMALL_SUFFIX;
    }
    pub fn repIsBig(ctx: *const Ctx, w: Term) bool {
        if ((w & TAG_MASK) != TAG_BOXED) return false;
        const st = headerSubtag(ctx, w);
        return st == SUBTAG_POS_BIG or st == SUBTAG_NEG_BIG;
    }
    pub fn repIsFloat(ctx: *const Ctx, w: Term) bool {
        return (w & TAG_MASK) == TAG_BOXED and headerSubtag(ctx, w) == SUBTAG_FLOAT;
    }
    /// Observation used by arithmetic guards (badarith detection).
    pub fn repIsNumber(ctx: *const Ctx, w: Term) bool {
        return repIsSmall(w) or repIsBig(ctx, w) or repIsFloat(ctx, w);
    }
    /// `is_binary` truth: TRUE for a true binary (SUBTAG_BINARY) OR a
    /// byte-aligned bitstring (SUBTAG_BITSTRING with `bit_len % 8 == 0`) —
    /// an aligned bitstring IS a binary denotationally (byte-alignment
    /// homomorphism, bitstring_algebra.zig doc). E3.1-fix: previously only
    /// checked SUBTAG_BINARY, so an aligned-but-SUBTAG_BITSTRING value
    /// wrongly failed `is_binary`.
    pub fn repIsBinary(ctx: *const Ctx, w: Term) bool {
        if ((w & TAG_MASK) != TAG_BOXED) return false;
        const st = headerSubtag(ctx, w);
        if (st == SUBTAG_BINARY) return true;
        if (st == SUBTAG_SUBBIN) return true; // e49-binary-refc: a window into a binary IS a binary
        if (st == SUBTAG_PROCBIN) return true; // e51-t2: a refcounted binary IS a binary
        if (st == SUBTAG_BITSTRING) return bitstringBits(ctx, w).bit_len % 8 == 0;
        return false;
    }
    pub fn repIsMap(ctx: *const Ctx, w: Term) bool {
        if ((w & TAG_MASK) != TAG_BOXED) return false;
        const st = headerSubtag(ctx, w);
        return st == SUBTAG_FLATMAP or st == SUBTAG_HMAP_ROOT;
    }
    /// Canonical flatness observation (for the law suite).
    pub fn mapRepIsFlat(ctx: *const Ctx, w: Term) bool {
        std.debug.assert(repIsMap(ctx, w));
        return headerSubtag(ctx, w) == SUBTAG_FLATMAP;
    }
    fn isAtom(w: Term) bool {
        return (w & IMM_MASK6) == ATOM_SUFFIX;
    }
    fn isNil(w: Term) bool {
        return w == NIL_WORD;
    }
    fn smallVal(w: Term) i64 {
        return @as(i64, @bitCast(w)) >> 4; // arithmetic shift: sign-correct
    }
    fn atomIdx(w: Term) AtomIdx {
        return @intCast(w >> 6);
    }
    fn ptrIdx(w: Term) usize {
        return @intCast(w >> 2);
    }
    fn headerSubtag(ctx: *const Ctx, w: Term) u64 {
        return (ctx.words.items[ptrIdx(w)] >> 2) & 0x1F;
    }
    fn headerCount(ctx: *const Ctx, w: Term) usize {
        return @intCast(ctx.words.items[ptrIdx(w)] >> 7);
    }
    fn floatVal(ctx: *const Ctx, w: Term) f64 {
        return @bitCast(ctx.words.items[ptrIdx(w) + 1]);
    }
    pub fn binBytesOf(ctx: *const Ctx, w: Term) []const u8 {
        const base = ptrIdx(w);
        // e49-binary-refc: a sub-binary window resolves to its base's bytes,
        // sliced [offset, offset+len) — the ZERO-COPY read (no dupe).
        if (headerSubtag(ctx, w) == SUBTAG_SUBBIN) {
            const off: usize = @intCast(ctx.words.items[base + 1]);
            const len: usize = @intCast(ctx.words.items[base + 2]);
            const base_bytes = binBytesOf(ctx, ctx.words.items[base + 3]);
            return base_bytes[off .. off + len];
        }
        // e51-t2: an off-heap refcounted binary reads its shared payload — the
        // single read choke point, so byte_size/part/denote/hash/compare/iolist
        // see a ProcBin transparently (no per-site logic).
        if (headerSubtag(ctx, w) == SUBTAG_PROCBIN) {
            return procBinRefc(ctx, w).bytes;
        }
        // gap-cowboy-serve (DIVERGENCE 646): a byte-aligned BITSTRING (what a
        // `<< _, Rest/bits >>` / `Rest/binary` TAIL bind produces — the pervasive
        // binary-parser idiom) stores its BIT length at `base+1`, NOT a byte
        // length. The flat-binary branch below reads `base+1` as bytes → for a
        // 32-bit ("8099") tail it read 32 BYTES (4× over) into adjacent heap
        // (binary_to_list gave 32 garbage bytes where byte_size gave 4, and
        // binary_to_integer/binBytes badarg'd/panicked). `bitstringBits` computes
        // the correct byte length `ceil(bit_len/8)`; return exactly those bytes.
        // (repIsBinary already gates to byte-aligned bitstrings, so this read is
        // whole-byte.)
        if (headerSubtag(ctx, w) == SUBTAG_BITSTRING) {
            return bitstringBits(ctx, w).bytes;
        }
        const len: usize = @intCast(ctx.words.items[base + 1]);
        const nwords = (len + 7) / 8;
        return std.mem.sliceAsBytes(ctx.words.items[base + 2 .. base + 2 + nwords])[0..len];
    }
    pub const BigParts = struct { positive: bool, limbs: []const u64 };
    pub fn bigParts(ctx: *const Ctx, w: Term) BigParts {
        const base = ptrIdx(w);
        const n = headerCount(ctx, w);
        return .{
            .positive = headerSubtag(ctx, w) == SUBTAG_POS_BIG,
            .limbs = ctx.words.items[base + 1 .. base + 1 + n],
        };
    }

    /// E3.5/E3.14: ranks renumbered to insert reference/port/pid then
    /// native_record pin-exactly (see the module doc comment): number(0) <
    /// atom(1) < reference(2) < fun(3) < port(4) < pid(5) < tuple(6) <
    /// native_record(7) < map(8) < nil/list(9) < binary/bitstring(10);
    /// matchctx(11, internal-only) stays last.
    fn rank(ctx: *const Ctx, w: Term) u8 {
        if (repIsSmall(w)) return 0;
        if (isAtom(w)) return 1;
        if (isNil(w)) return 9;
        return switch (w & TAG_MASK) {
            TAG_LIST => 9,
            TAG_BOXED => switch (headerSubtag(ctx, w)) {
                SUBTAG_TUPLE => 6,
                SUBTAG_POS_BIG, SUBTAG_NEG_BIG, SUBTAG_FLOAT => 0,
                SUBTAG_REF => 2,
                SUBTAG_FUN, SUBTAG_EXPORT_FUN => 3, // E7.1: external funs share the fun band
                SUBTAG_PORT => 4,
                SUBTAG_PID => 5,
                SUBTAG_NATIVE_RECORD => 7, // E3.14: between tuple and map
                SUBTAG_FLATMAP, SUBTAG_HMAP_ROOT => 8,
                SUBTAG_BINARY, SUBTAG_BITSTRING, SUBTAG_SUBBIN, SUBTAG_PROCBIN => 10, // e49-binary-refc / e51-t2
                // E3.3-fix (Fix 3, review of 34997cb): SUBTAG_MATCHCTX is an
                // internal, compiler-emitted-only control value — no BEAM
                // program can ever construct one that reaches `compare`/
                // `hash`/`kindOf` (a match context never escapes to a
                // comparison, sort, or type-test guard in compiler-emitted
                // code). An ADVERSARIAL `.beam` could still route one
                // through `is_eq_exact`/a sort BIF, so this is a real (if
                // out-of-scope) reachable path — routed to a DEFINED
                // outcome (own rank 11) instead of `unreachable`/panic. See
                // DIVERGENCE_LOG entry 16(c).
                SUBTAG_MATCHCTX => 11,
                else => unreachable, // interior map nodes are never term handles
            },
            else => unreachable, // headers are never term handles
        };
    }

    // ---- arithmetic: '+' on tagged words ------------------------------------

    /// '+' computed directly on the word representation (limb arithmetic for
    /// integers, IEEE for floats), verified against the spec oracle.
    pub fn add(ctx: *Ctx, x: Term, y: Term) error{ OutOfMemory, Badarith }!Term {
        if (repIsFloat(ctx, x) or repIsFloat(ctx, y)) {
            const s = numToF64(ctx, x) + numToF64(ctx, y);
            if (!std.math.isFinite(s)) return error.Badarith;
            return makeFloat(ctx, s);
        }
        if (repIsSmall(x) and repIsSmall(y)) {
            const s = @as(i128, smallVal(x)) + @as(i128, smallVal(y));
            return intFromI128(ctx, s); // canonical (may promote to big)
        }
        var bufx: [1]u64 = undefined;
        var bufy: [1]u64 = undefined;
        const a = operand(ctx, x, &bufx);
        const b = operand(ctx, y, &bufy);
        var out: [max_limbs + 1]u64 = undefined;

        if (a.positive == b.positive) {
            const n = addMag(a.limbs, b.limbs, &out);
            return normalized(ctx, a.positive, out[0..n]);
        }
        return switch (cmpLimbs(a.limbs, b.limbs)) {
            .eq => int(ctx, 0),
            .gt => normalized(ctx, a.positive, out[0..subMag(a.limbs, b.limbs, &out)]),
            .lt => normalized(ctx, b.positive, out[0..subMag(b.limbs, a.limbs, &out)]),
        };
    }

    /// Numeric negation (M8: gc_bif '-'). Canonical smallness is preserved
    /// (the one asymmetric case: -(-2^59) does not fit small → boxed).
    pub fn negate(ctx: *Ctx, w: Term) error{OutOfMemory}!Term {
        if (repIsSmall(w)) {
            const v = smallVal(w);
            return intFromI128(ctx, -@as(i128, v));
        }
        if (repIsFloat(ctx, w)) return makeFloat(ctx, -floatVal(ctx, w));
        const p = bigParts(ctx, w);
        // copy limbs to a scratch buffer: makeBig appends to the same heap
        var buf: [max_limbs]u64 = undefined;
        @memcpy(buf[0..p.limbs.len], p.limbs);
        return makeBig(ctx, !p.positive, buf[0..p.limbs.len]);
    }

    // ── E2.4 small-integer arithmetic extensions ──────────────────────────
    // SCOPED SEMANTIC PRECURSOR (ALGEBRAIC_FRACTAL_RULES §5) to the full bignum
    // ops: a dedicated bignum-arithmetic slice will implement `*`/`div`/`rem`/
    // bitwise over limbs (schoolbook multiply, limb long-division). Each op here
    // is TOTAL and CORRECT over SMALL integers (|v| < 2^59); `mul` is correct
    // over any small×small product (≤ ~2^119, canonicalized by intFromI128,
    // which spans the full i128 range and promotes to a 2-limb big when needed).
    // A bignum OPERAND (repIsBig) — producible only by a prior overflow — and a
    // shift whose result exceeds i128 are NOT yet handled: those return
    // error.Badarith (a CLEAN path, never a panic) — the documented deferral
    // point. `mul` also accepts floats (like `add`); the integer ops require the
    // caller to have already rejected non-integers (the family fn checks).
    // Homomorphism/denotation law (PART 4): denote(op(x,y)) == op_ℤ(x, y).

    /// `*`: numeric multiply. Float path mirrors `add`; small×small is exact via
    /// i128; a bignum operand defers (error.Badarith). Precondition: both are
    /// numbers (the family fn checks; float mixing needs a number partner).
    pub fn mul(ctx: *Ctx, x: Term, y: Term) error{ OutOfMemory, Badarith }!Term {
        if (repIsFloat(ctx, x) or repIsFloat(ctx, y)) {
            const p = numToF64(ctx, x) * numToF64(ctx, y);
            if (!std.math.isFinite(p)) return error.Badarith;
            return makeFloat(ctx, p);
        }
        if (repIsSmall(x) and repIsSmall(y)) {
            return intFromI128(ctx, @as(i128, smallVal(x)) * @as(i128, smallVal(y)));
        }
        // triage-big-divergences (2026-07-23): the FULL bignum multiply — the
        // former "deferred to the bignum-arith slice" badarith arm, discharged.
        // Schoolbook limb multiply over the SAME magnitude carrier `add` uses
        // (operand() lifts a small to a 1-limb magnitude, so every small/big MIX
        // rides one code path). Sign: product is positive iff signs agree.
        // Zero: a small 0 operand short-circuits (bigs are never zero — the
        // canonical small/big boundary guarantees magnitude ≥ 2^59).
        var bufx: [1]u64 = undefined;
        var bufy: [1]u64 = undefined;
        const a = operand(ctx, x, &bufx);
        const b = operand(ctx, y, &bufy);
        if ((a.limbs.len == 1 and a.limbs[0] == 0) or (b.limbs.len == 1 and b.limbs[0] == 0))
            return int(ctx, 0);
        if (a.limbs.len + b.limbs.len > max_limbs + 1) return error.Badarith; // the documented cap
        var out: [max_limbs + 1]u64 = undefined;
        const n = mulMag(a.limbs, b.limbs, &out);
        if (limbsEffLen(out[0..n]) > max_limbs) return error.Badarith; // cap (≈2^65536)
        return normalized(ctx, a.positive == b.positive, out[0..n]);
    }

    /// `div`: integer division truncated toward zero (BEAM `div`). Zero divisor
    /// → error.Badarith. Small operands only; bignum defers. Precondition:
    /// integer operands (the family fn rejects floats/non-numbers first).
    pub fn idiv(ctx: *Ctx, x: Term, y: Term) error{ OutOfMemory, Badarith }!Term {
        if (repIsSmall(x) and repIsSmall(y)) {
            const b = smallVal(y);
            if (b == 0) return error.Badarith;
            return intFromI128(ctx, @divTrunc(@as(i128, smallVal(x)), @as(i128, b)));
        }
        // triage-big-divergences: full bignum division, truncated toward zero.
        // Magnitude division (divRemMag) + the BEAM sign rule: sign(q) = signs
        // agree (a zero quotient is canonically non-negative via normalized).
        var bufx: [1]u64 = undefined;
        var bufy: [1]u64 = undefined;
        const a = operand(ctx, x, &bufx);
        const b = operand(ctx, y, &bufy);
        if (b.limbs.len == 1 and b.limbs[0] == 0) return error.Badarith; // ÷0
        var q: [max_limbs + 1]u64 = undefined;
        var r: [max_limbs + 1]u64 = undefined;
        const lens = divRemMag(a.limbs, b.limbs, &q, &r);
        return normalized(ctx, a.positive == b.positive, q[0..lens.q]);
    }

    /// `rem`: remainder with the sign of the dividend (BEAM `rem`; the exact
    /// inverse partner of `idiv`: `(x div y)*y + (x rem y) == x`). Zero divisor
    /// → error.Badarith. Small operands only; bignum defers.
    pub fn irem(ctx: *Ctx, x: Term, y: Term) error{ OutOfMemory, Badarith }!Term {
        if (repIsSmall(x) and repIsSmall(y)) {
            const b = smallVal(y);
            if (b == 0) return error.Badarith;
            return intFromI128(ctx, @rem(@as(i128, smallVal(x)), @as(i128, b)));
        }
        // triage-big-divergences: full bignum remainder — the exact inverse
        // partner of `idiv` ((x div y)*y + (x rem y) == x, |r| < |y|), carrying
        // the DIVIDEND's sign (BEAM `rem`; a zero remainder is canonically
        // non-negative via normalized).
        var bufx: [1]u64 = undefined;
        var bufy: [1]u64 = undefined;
        const a = operand(ctx, x, &bufx);
        const b = operand(ctx, y, &bufy);
        if (b.limbs.len == 1 and b.limbs[0] == 0) return error.Badarith; // ÷0
        var q: [max_limbs + 1]u64 = undefined;
        var r: [max_limbs + 1]u64 = undefined;
        const lens = divRemMag(a.limbs, b.limbs, &q, &r);
        return normalized(ctx, a.positive, r[0..lens.r]);
    }

    /// `band`/`bor`/`bxor`: two's-complement bitwise ops over the INFINITE word
    /// (Erlang integer semantics). Small×small stays the i64 fast path;
    /// bitwise-big (2026-07-23) discharges the former bignum badarith deferral:
    /// both operands are materialized as two's-complement limb arrays of a
    /// common width (max(an,bn)+1 limbs, so the sign bit always lives in a
    /// fresh top limb), the op is applied limbwise, and the result converts
    /// back from two's complement (top-bit ⇒ negative ⇒ magnitude = ~r + 1).
    /// This is exactly the sign-extension semantics of the infinite word —
    /// the same construction erts' big.c implements case-by-case.
    fn toTwos(p: BigParts, out: []u64) void {
        for (out, 0..) |*l, k| l.* = if (k < p.limbs.len) p.limbs[k] else 0;
        if (!p.positive) {
            for (out) |*l| l.* = ~l.*;
            var carry: u64 = 1;
            for (out) |*l| {
                const s = @addWithOverflow(l.*, carry);
                l.* = s[0];
                carry = s[1];
                if (carry == 0) break;
            }
        }
    }

    fn fromTwos(ctx: *Ctx, r: []u64) !Term {
        const negative = (r[r.len - 1] >> 63) != 0;
        if (!negative) return normalized(ctx, true, r);
        for (r) |*l| l.* = ~l.*;
        var carry: u64 = 1;
        for (r) |*l| {
            const s = @addWithOverflow(l.*, carry);
            l.* = s[0];
            carry = s[1];
            if (carry == 0) break;
        }
        return normalized(ctx, false, r);
    }

    const BitOp = enum { band, bor, bxor };

    fn bitwiseBig(ctx: *Ctx, x: Term, y: Term, comptime op: BitOp) error{ OutOfMemory, Badarith }!Term {
        var bufx: [1]u64 = undefined;
        var bufy: [1]u64 = undefined;
        const a = operand(ctx, x, &bufx);
        const b = operand(ctx, y, &bufy);
        const len = @max(a.limbs.len, b.limbs.len) + 1; // fresh sign limb
        if (len > max_limbs) return error.Badarith; // cap (cannot occur for real terms)
        var ta_: [max_limbs + 1]u64 = undefined;
        var tb_: [max_limbs + 1]u64 = undefined;
        toTwos(a, ta_[0..len]);
        toTwos(b, tb_[0..len]);
        for (ta_[0..len], tb_[0..len]) |*la, lb| {
            la.* = switch (op) {
                .band => la.* & lb,
                .bor => la.* | lb,
                .bxor => la.* ^ lb,
            };
        }
        return fromTwos(ctx, ta_[0..len]);
    }

    pub fn band(ctx: *Ctx, x: Term, y: Term) error{ OutOfMemory, Badarith }!Term {
        if (repIsSmall(x) and repIsSmall(y)) return intFromI128(ctx, @as(i128, smallVal(x) & smallVal(y)));
        return bitwiseBig(ctx, x, y, .band);
    }
    pub fn bor(ctx: *Ctx, x: Term, y: Term) error{ OutOfMemory, Badarith }!Term {
        if (repIsSmall(x) and repIsSmall(y)) return intFromI128(ctx, @as(i128, smallVal(x) | smallVal(y)));
        return bitwiseBig(ctx, x, y, .bor);
    }
    pub fn bxor(ctx: *Ctx, x: Term, y: Term) error{ OutOfMemory, Badarith }!Term {
        if (repIsSmall(x) and repIsSmall(y)) return intFromI128(ctx, @as(i128, smallVal(x) ^ smallVal(y)));
        return bitwiseBig(ctx, x, y, .bxor);
    }

    /// `bnot X` == `-X - 1`. Total over small integers; bitwise-big discharges
    /// the bignum arm via the sign-magnitude identity: bnot(+m) = -(m+1),
    /// bnot(-m) = +(m-1) — magnitude ±1, sign flipped (never grows past cap+1).
    pub fn bnot(ctx: *Ctx, x: Term) error{ OutOfMemory, Badarith }!Term {
        if (repIsSmall(x)) return intFromI128(ctx, -@as(i128, smallVal(x)) - 1);
        var bufx: [1]u64 = undefined;
        const a = operand(ctx, x, &bufx);
        var out: [max_limbs + 1]u64 = undefined;
        const one = [_]u64{1};
        if (a.positive) {
            const n = addMag(a.limbs, &one, &out);
            return normalized(ctx, false, out[0..n]);
        }
        const n = subMag(a.limbs, &one, &out); // |x| ≥ 2^59 > 1, safe
        return normalized(ctx, true, out[0..n]);
    }

    /// `bsl`/`bsr`: arithmetic shifts over the infinite word. A NEGATIVE shift
    /// count flips direction (BEAM: `X bsl -N == X bsr N`). bitwise-big
    /// discharges the former deferrals (big operand, or a small-path left
    /// result beyond i128) via magnitude limb shifts: bsl shifts the magnitude
    /// (sign preserved; beyond max_limbs ⇒ error.Badarith, the family cap);
    /// bsr on a POSITIVE value truncates the magnitude; on a NEGATIVE value it
    /// must FLOOR (arithmetic shift): -m bsr n == -(((m-1) >> n) + 1). A shift
    /// count too big to matter saturates (bsr ⇒ 0 / -1; bsl of nonzero ⇒ cap).
    pub fn bsl(ctx: *Ctx, x: Term, y: Term) error{ OutOfMemory, Badarith }!Term {
        if (repIsSmall(x) and repIsSmall(y)) {
            const r = shiftLeftI128(ctx, @as(i128, smallVal(x)), smallVal(y));
            if (r) |t| return t else |e| if (e != error.Badarith) return e;
            // fall through: small operands whose LEFT result exceeds i128
        }
        return shiftBig(ctx, x, y, false);
    }
    pub fn bsr(ctx: *Ctx, x: Term, y: Term) error{ OutOfMemory, Badarith }!Term {
        if (repIsSmall(x) and repIsSmall(y)) {
            const r = shiftLeftI128(ctx, @as(i128, smallVal(x)), -smallVal(y));
            if (r) |t| return t else |e| if (e != error.Badarith) return e;
        }
        return shiftBig(ctx, x, y, true);
    }
    /// Shared shift core: shift `v` left by `n` (negative `n` shifts right).
    fn shiftLeftI128(ctx: *Ctx, v: i128, n: i64) error{ OutOfMemory, Badarith }!Term {
        if (n == 0 or v == 0) return intFromI128(ctx, v);
        if (n > 0) {
            if (n > 68) return error.Badarith; // beyond i128: the caller's big path takes over
            return intFromI128(ctx, v * (@as(i128, 1) << @intCast(n)));
        }
        const sh: u64 = @intCast(-n);
        if (sh >= 127) return intFromI128(ctx, if (v < 0) -1 else 0);
        return intFromI128(ctx, v >> @intCast(sh));
    }

    /// The bignum shift kernel (`right` selects bsr; a negative count flips it).
    fn shiftBig(ctx: *Ctx, x: Term, y: Term, right: bool) error{ OutOfMemory, Badarith }!Term {
        var bufx: [1]u64 = undefined;
        const a = operand(ctx, x, &bufx);
        if (a.limbs.len == 1 and a.limbs[0] == 0) return int(ctx, 0); // 0 shifted is 0
        // The count: a small fits i64; a BIG count saturates by its sign alone
        // (magnitudes ≥ 2^59 dwarf any representable bit-length).
        var n: i128 = undefined;
        if (repIsSmall(y)) {
            n = smallVal(y);
        } else {
            var bufy: [1]u64 = undefined;
            n = if (operand(ctx, y, &bufy).positive) std.math.maxInt(i128) else std.math.minInt(i128);
        }
        const shift_right = if (right) (n >= 0) else (n < 0);
        const mag_n: u128 = if (n == std.math.minInt(i128)) @as(u128, 1) << 127 else @abs(n);
        if (!shift_right) {
            // LEFT: magnitude grows by mag_n bits; beyond the cap ⇒ Badarith.
            const bits = (a.limbs.len - 1) * 64 + (64 - @clz(a.limbs[a.limbs.len - 1]));
            if (mag_n > @as(u128, max_limbs) * 64 - bits) return error.Badarith;
            const limb_sh: usize = @intCast(mag_n / 64);
            const bit_sh: u6 = @intCast(mag_n % 64);
            var out: [max_limbs + 1]u64 = undefined;
            @memset(out[0..limb_sh], 0);
            var carry: u64 = 0;
            for (a.limbs, 0..) |l, k| {
                if (bit_sh == 0) {
                    out[limb_sh + k] = l;
                } else {
                    out[limb_sh + k] = (l << bit_sh) | carry;
                    carry = l >> @intCast(64 - @as(u7, bit_sh));
                }
            }
            var n_out = limb_sh + a.limbs.len;
            if (bit_sh != 0 and carry != 0) {
                out[n_out] = carry;
                n_out += 1;
            }
            return normalized(ctx, a.positive, out[0..n_out]);
        }
        // RIGHT (arithmetic): positive truncates; negative floors.
        const bits: u128 = @intCast((a.limbs.len - 1) * 64 + (64 - @clz(a.limbs[a.limbs.len - 1])));
        if (a.positive) {
            if (mag_n >= bits) return int(ctx, 0);
            return normalized(ctx, true, shiftMagRight(a.limbs, @intCast(mag_n)));
        }
        // -m bsr n == -(((m-1) >> n) + 1)
        var dec: [max_limbs + 1]u64 = undefined;
        const one = [_]u64{1};
        const dn = subMag(a.limbs, &one, &dec);
        const eff = limbsEffLen(dec[0..dn]);
        const dec_bits: u128 = if (eff == 1 and dec[0] == 0) 0 else @intCast((eff - 1) * 64 + (64 - @clz(dec[eff - 1])));
        if (mag_n >= dec_bits) return int(ctx, -1); // floor of a negative fraction
        const sh = shiftMagRight(dec[0..eff], @intCast(mag_n));
        var out: [max_limbs + 1]u64 = undefined;
        const n_out = addMag(sh, &one, &out);
        return normalized(ctx, false, out[0..n_out]);
    }

    /// In-place-safe magnitude right shift (returns a slice of the scratch).
    var shift_scratch: [max_limbs + 1]u64 = undefined; // single-threaded VM scratch
    fn shiftMagRight(m: []const u64, n: u64) []u64 {
        const limb_sh: usize = @intCast(n / 64);
        const bit_sh: u6 = @intCast(n % 64);
        const rem_len = m.len - limb_sh;
        for (0..rem_len) |k| {
            const lo = m[limb_sh + k] >> bit_sh;
            const hi = if (bit_sh != 0 and limb_sh + k + 1 < m.len)
                m[limb_sh + k + 1] << @intCast(64 - @as(u7, bit_sh))
            else
                0;
            shift_scratch[k] = lo | hi;
        }
        return shift_scratch[0..rem_len];
    }

    fn numToF64(ctx: *const Ctx, w: Term) f64 {
        if (repIsSmall(w)) return @floatFromInt(smallVal(w));
        if (repIsFloat(ctx, w)) return floatVal(ctx, w);
        const p = bigParts(ctx, w);
        return limbsToF64(p.positive, p.limbs);
    }

    fn operand(ctx: *const Ctx, w: Term, buf: *[1]u64) BigParts {
        if (repIsSmall(w)) {
            const v = smallVal(w);
            buf[0] = @abs(v);
            return .{ .positive = v >= 0, .limbs = buf[0..1] };
        }
        std.debug.assert(repIsBig(ctx, w));
        return bigParts(ctx, w);
    }

    fn addMag(a: []const u64, b: []const u64, out: *[max_limbs + 1]u64) usize {
        const long = if (a.len >= b.len) a else b;
        const short = if (a.len >= b.len) b else a;
        std.debug.assert(long.len <= max_limbs);
        var carry: u64 = 0;
        for (long, 0..) |la, k| {
            const sb: u64 = if (k < short.len) short[k] else 0;
            const r1 = @addWithOverflow(la, sb);
            const r2 = @addWithOverflow(r1[0], carry);
            out[k] = r2[0];
            carry = @as(u64, r1[1]) + @as(u64, r2[1]);
        }
        out[long.len] = carry;
        return long.len + 1;
    }

    /// Requires |a| >= |b|.
    fn subMag(a: []const u64, b: []const u64, out: *[max_limbs + 1]u64) usize {
        var borrow: u64 = 0;
        for (a, 0..) |la, k| {
            const sb: u64 = if (k < b.len) b[k] else 0;
            const r1 = @subWithOverflow(la, sb);
            const r2 = @subWithOverflow(r1[0], borrow);
            out[k] = r2[0];
            borrow = @as(u64, r1[1]) + @as(u64, r2[1]);
        }
        std.debug.assert(borrow == 0);
        return a.len;
    }

    /// Strip high zero limbs; demote to small when the value fits.
    /// This function IS the canonical-smallness law, applied at every result.
    /// Schoolbook magnitude multiply: out = a × b (little-endian limbs), u128
    /// partial products with carry propagation. Caller guarantees
    /// `a.len + b.len ≤ out.len`. Returns the written length (a.len + b.len;
    /// the top limb may be zero — callers trim via limbsEffLen/normalized).
    /// triage-big-divergences: the multiply kernel the former deferral lacked.
    fn mulMag(a: []const u64, b: []const u64, out: *[max_limbs + 1]u64) usize {
        const n = a.len + b.len;
        std.debug.assert(n <= out.len);
        @memset(out[0..n], 0);
        for (a, 0..) |la, i| {
            if (la == 0) continue;
            var carry: u64 = 0;
            for (b, 0..) |lb, j| {
                // out[i+j] + la*lb + carry, split into low/high u64 halves.
                const p = @as(u128, la) * @as(u128, lb) + @as(u128, out[i + j]) + @as(u128, carry);
                out[i + j] = @truncate(p);
                carry = @intCast(p >> 64);
            }
            var k = i + b.len;
            while (carry != 0) : (k += 1) {
                const s = @addWithOverflow(out[k], carry);
                out[k] = s[0];
                carry = s[1];
            }
        }
        return n;
    }

    /// Magnitude division with remainder: q = ⌊a / b⌋, r = a mod b (b ≠ 0),
    /// returning the effective lengths of each. Two paths:
    ///   - single-limb divisor: one u128-chunked pass (the common fast case);
    ///   - multi-limb divisor: restoring BINARY long division — bounded by
    ///     a's bit-length (≤ 64·max_limbs iterations), each step O(b.len).
    ///     Chosen for VERIFIABILITY over Knuth-D speed: the loop invariant
    ///     (0 ≤ r < b, a = q·b + r over the consumed prefix) is directly the
    ///     div/rem law the suite pins; a Knuth-D upgrade is a later perf slice
    ///     that must preserve exactly these laws.
    /// triage-big-divergences: the division kernel the former deferral lacked.
    fn divRemMag(a: []const u64, b: []const u64, q: *[max_limbs + 1]u64, r: *[max_limbs + 1]u64) struct { q: usize, r: usize } {
        const an = limbsEffLen(a);
        const bn = limbsEffLen(b);
        std.debug.assert(!(bn == 1 and b[0] == 0)); // caller rejects ÷0
        // |a| < |b| ⇒ q = 0, r = a (the common guard-clause case).
        if (cmpLimbs(a[0..an], b[0..bn]) == .lt) {
            q[0] = 0;
            @memcpy(r[0..an], a[0..an]);
            return .{ .q = 1, .r = an };
        }
        if (bn == 1) {
            // Fast path: divide by one limb, top-down, carrying the remainder.
            const d = b[0];
            var rem: u64 = 0;
            @memset(q[0..an], 0);
            var i = an;
            while (i > 0) {
                i -= 1;
                const cur = (@as(u128, rem) << 64) | @as(u128, a[i]);
                q[i] = @intCast(cur / d);
                rem = @intCast(cur % d);
            }
            r[0] = rem;
            return .{ .q = limbsEffLen(q[0..an]), .r = 1 };
        }
        // General path: restoring binary long division, msb-first.
        @memset(q[0..an], 0);
        @memset(r[0 .. bn + 1], 0);
        var rn: usize = 1; // effective remainder length (r < b throughout)
        const top_bits = 64 - @clz(a[an - 1]);
        var bit: usize = (an - 1) * 64 + top_bits;
        while (bit > 0) {
            bit -= 1;
            // r = (r << 1) | a[bit]  — shift left one bit, bring down the next.
            var carry: u64 = (a[bit / 64] >> @intCast(bit % 64)) & 1;
            for (r[0..rn], 0..) |rl, k| {
                const nc = rl >> 63;
                r[k] = (rl << 1) | carry;
                carry = nc;
            }
            if (carry != 0) {
                r[rn] = carry;
                rn += 1;
            }
            // if r ≥ b: r -= b, q[bit] = 1  (the restoring step).
            if (cmpLimbs(r[0..rn], b[0..bn]) != .lt) {
                var tmp: [max_limbs + 1]u64 = undefined;
                const sn = subMag(r[0..rn], b[0..bn], &tmp);
                @memcpy(r[0..sn], tmp[0..sn]);
                rn = limbsEffLen(r[0..sn]);
                q[bit / 64] |= @as(u64, 1) << @intCast(bit % 64);
            }
        }
        return .{ .q = limbsEffLen(q[0..an]), .r = rn };
    }

    fn normalized(ctx: *Ctx, positive: bool, mag: []const u64) !Term {
        const n = limbsEffLen(mag);
        if (n == 1) {
            const l = mag[0];
            if (positive and l < (1 << 59))
                return int(ctx, @intCast(l));
            if (!positive and l <= (1 << 59))
                return int(ctx, -@as(i64, @intCast(l)));
        }
        return makeBig(ctx, positive, mag[0..n]);
    }

    // ---- maps: FLATMAP (≤32, sorted) / HAMT (>32) ---------------------------
    //
    // Flatmap layout:  header(FLATMAP, 1+2n) | n | k0..k(n-1) | v0..v(n-1)
    //                  keys sorted by EXACT order, distinct.
    // Hashmap root:    header(HMAP_ROOT, 2) | size | top-child
    // Interior node:   header(HMAP_NODE, 1+n) | bitmap(u32) | n children
    //                  child = leaf (a TAG_LIST 2-cell [k|v]) or boxed node
    // Collision node:  header(HMAP_COLL, 2n) | k0 v0 .. (full-hash collisions)
    // The trie is CANONICAL: structure depends only on the key-hash set, so
    // equal maps have equal shapes regardless of insertion order.

    const HAMT_SHIFT_LIMIT = 60; // beyond this, fall back to collision nodes

    fn keyHash(ctx: *const Ctx, k: Term) u64 {
        return hashTermC(ctx, k);
    }
    fn chunk(h: u64, shift: u6) u5 {
        return @truncate(h >> shift);
    }

    fn makeFlat(ctx: *Ctx, keys: []const Term, vals: []const Term) !Term {
        const n = keys.len;
        std.debug.assert(n <= max_flatmap_size);
        const base = try ctx.alloc(2 + 2 * n);
        ctx.words.items[base] = header(SUBTAG_FLATMAP, 1 + 2 * n);
        ctx.words.items[base + 1] = n;
        for (keys, 0..) |k, i| ctx.words.items[base + 2 + i] = k;
        for (vals, 0..) |v, i| ctx.words.items[base + 2 + n + i] = v;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }

    fn flatN(ctx: *const Ctx, m: Term) usize {
        return @intCast(ctx.words.items[ptrIdx(m) + 1]);
    }
    fn flatKeys(ctx: *const Ctx, m: Term) []const u64 {
        const base = ptrIdx(m);
        const n = flatN(ctx, m);
        return ctx.words.items[base + 2 .. base + 2 + n];
    }
    fn flatVals(ctx: *const Ctx, m: Term) []const u64 {
        const base = ptrIdx(m);
        const n = flatN(ctx, m);
        return ctx.words.items[base + 2 + n .. base + 2 + 2 * n];
    }

    fn makeLeaf(ctx: *Ctx, k: Term, v: Term) !Term {
        return cons(ctx, k, v); // a raw [k|v] 2-cell; never a term handle
    }
    fn leafKey(ctx: *const Ctx, leaf: Term) Term {
        return ctx.words.items[ptrIdx(leaf)];
    }
    fn leafVal(ctx: *const Ctx, leaf: Term) Term {
        return ctx.words.items[ptrIdx(leaf) + 1];
    }
    fn childIsLeaf(w: Term) bool {
        return (w & TAG_MASK) == TAG_LIST;
    }

    fn makeNode(ctx: *Ctx, bitmap: u32, children: []const Term) !Term {
        const base = try ctx.alloc(2 + children.len);
        ctx.words.items[base] = header(SUBTAG_HMAP_NODE, 1 + children.len);
        ctx.words.items[base + 1] = bitmap;
        for (children, 0..) |c, i| ctx.words.items[base + 2 + i] = c;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }
    fn nodeBitmap(ctx: *const Ctx, node: Term) u32 {
        return @truncate(ctx.words.items[ptrIdx(node) + 1]);
    }
    fn nodeChildren(ctx: *const Ctx, node: Term) []const u64 {
        const base = ptrIdx(node);
        const n = headerCount(ctx, node) - 1;
        return ctx.words.items[base + 2 .. base + 2 + n];
    }

    fn makeCollision(ctx: *Ctx, pairs: []const [2]Term) !Term {
        const base = try ctx.alloc(1 + 2 * pairs.len);
        ctx.words.items[base] = header(SUBTAG_HMAP_COLL, 2 * pairs.len);
        for (pairs, 0..) |p, i| {
            ctx.words.items[base + 1 + 2 * i] = p[0];
            ctx.words.items[base + 2 + 2 * i] = p[1];
        }
        return (@as(u64, base) << 2) | TAG_BOXED;
    }

    fn makeRoot(ctx: *Ctx, size: usize, top: Term) !Term {
        const base = try ctx.alloc(3);
        ctx.words.items[base] = header(SUBTAG_HMAP_ROOT, 2);
        ctx.words.items[base + 1] = size;
        ctx.words.items[base + 2] = top;
        return (@as(u64, base) << 2) | TAG_BOXED;
    }
    fn rootSize(ctx: *const Ctx, m: Term) usize {
        return @intCast(ctx.words.items[ptrIdx(m) + 1]);
    }
    fn rootTop(ctx: *const Ctx, m: Term) Term {
        return ctx.words.items[ptrIdx(m) + 2];
    }

    pub fn mapSize(ctx: *Ctx, m: Term) usize {
        return if (mapRepIsFlat(ctx, m)) flatN(ctx, m) else rootSize(ctx, m);
    }

    /// Build from unsorted pairs; duplicate keys: LAST wins (maps:from_list).
    pub fn mapNew(ctx: *Ctx, keys: []const Term, vals: []const Term) !Term {
        std.debug.assert(keys.len == vals.len);
        const idxs = try ctx.gpa.alloc(usize, keys.len);
        defer ctx.gpa.free(idxs);
        for (idxs, 0..) |*s, i| s.* = i;
        const SortCtx = struct {
            ctx: *const Ctx,
            keys: []const Term,
            pub fn less(s: @This(), x: usize, y: usize) bool {
                return cmp(s.ctx, s.keys[x], s.keys[y], .exact) == .lt;
            }
        };
        std.sort.insertion(usize, idxs, SortCtx{ .ctx = ctx, .keys = keys }, SortCtx.less);
        var dk: std.ArrayList(Term) = .empty;
        defer dk.deinit(ctx.gpa);
        var dv: std.ArrayList(Term) = .empty;
        defer dv.deinit(ctx.gpa);
        for (idxs) |i| {
            if (dk.items.len > 0 and
                cmp(ctx, dk.items[dk.items.len - 1], keys[i], .exact) == .eq)
            {
                dv.items[dv.items.len - 1] = vals[i]; // last wins (stable sort)
            } else {
                try dk.append(ctx.gpa, keys[i]);
                try dv.append(ctx.gpa, vals[i]);
            }
        }
        if (dk.items.len <= max_flatmap_size) return makeFlat(ctx, dk.items, dv.items);
        return hamtFromPairs(ctx, dk.items, dv.items);
    }

    fn hamtFromPairs(ctx: *Ctx, keys: []const Term, vals: []const Term) !Term {
        var top = try makeNode(ctx, 0, &.{});
        for (keys, vals) |k, v| {
            const r = try hamtPutChild(ctx, top, k, v, keyHash(ctx, k), 0);
            top = r.w;
            std.debug.assert(r.added); // keys are distinct here
        }
        return makeRoot(ctx, keys.len, top);
    }

    const PutRes = struct { w: Term, added: bool };

    fn hamtPutChild(ctx: *Ctx, child: Term, k: Term, v: Term, h: u64, shift: u6) error{OutOfMemory}!PutRes {
        if (childIsLeaf(child)) {
            const k2 = leafKey(ctx, child);
            if (cmp(ctx, k, k2, .exact) == .eq)
                return .{ .w = try makeLeaf(ctx, k, v), .added = false };
            if (shift >= HAMT_SHIFT_LIMIT) {
                return .{ .w = try makeCollision(ctx, &.{
                    .{ k2, leafVal(ctx, child) }, .{ k, v },
                }), .added = true };
            }
            // split: node containing the existing leaf, then insert into it
            const h2 = keyHash(ctx, k2);
            const idx2 = chunk(h2, shift);
            const single = try makeNode(ctx, @as(u32, 1) << idx2, &.{child});
            return hamtPutChild(ctx, single, k, v, h, shift);
        }
        switch (headerSubtag(ctx, child)) {
            SUBTAG_HMAP_COLL => {
                const base = ptrIdx(child);
                const n = headerCount(ctx, child) / 2;
                var pairs: [40][2]Term = undefined;
                std.debug.assert(n < 40);
                var found = false;
                for (0..n) |i| {
                    pairs[i] = .{ ctx.words.items[base + 1 + 2 * i], ctx.words.items[base + 2 + 2 * i] };
                    if (cmp(ctx, pairs[i][0], k, .exact) == .eq) {
                        pairs[i][1] = v;
                        found = true;
                    }
                }
                if (!found) pairs[n] = .{ k, v };
                const total = if (found) n else n + 1;
                return .{ .w = try makeCollision(ctx, pairs[0..total]), .added = !found };
            },
            SUBTAG_HMAP_NODE => {
                const bm = nodeBitmap(ctx, child);
                const idx = chunk(h, shift);
                const bit = @as(u32, 1) << idx;
                const pos: usize = @popCount(bm & (bit - 1));
                // SNAPSHOT before any allocation: nodeChildren slices into
                // ctx.words, which REALLOCATES as the heap grows.
                var buf: [33]Term = undefined;
                const nkids = nodeChildren(ctx, child).len;
                @memcpy(buf[0..nkids], nodeChildren(ctx, child));
                if (bm & bit != 0) {
                    const r = try hamtPutChild(ctx, buf[pos], k, v, h, shift + 5);
                    buf[pos] = r.w;
                    return .{ .w = try makeNode(ctx, bm, buf[0..nkids]), .added = r.added };
                }
                var out: [33]Term = undefined;
                @memcpy(out[0..pos], buf[0..pos]);
                out[pos] = try makeLeaf(ctx, k, v);
                @memcpy(out[pos + 1 .. nkids + 1], buf[pos..nkids]);
                return .{ .w = try makeNode(ctx, bm | bit, out[0 .. nkids + 1]), .added = true };
            },
            else => unreachable,
        }
    }

    fn hamtGetChild(ctx: *const Ctx, child: Term, k: Term, h: u64, shift: u6) ?Term {
        if (childIsLeaf(child)) {
            if (cmp(ctx, k, leafKey(ctx, child), .exact) == .eq) return leafVal(ctx, child);
            return null;
        }
        switch (headerSubtag(ctx, child)) {
            SUBTAG_HMAP_COLL => {
                const base = ptrIdx(child);
                const n = headerCount(ctx, child) / 2;
                for (0..n) |i| {
                    if (cmp(ctx, ctx.words.items[base + 1 + 2 * i], k, .exact) == .eq)
                        return ctx.words.items[base + 2 + 2 * i];
                }
                return null;
            },
            SUBTAG_HMAP_NODE => {
                const bm = nodeBitmap(ctx, child);
                const idx = chunk(h, shift);
                const bit = @as(u32, 1) << idx;
                if (bm & bit == 0) return null;
                const pos: usize = @popCount(bm & (bit - 1));
                return hamtGetChild(ctx, nodeChildren(ctx, child)[pos], k, h, shift + 5);
            },
            else => unreachable,
        }
    }

    const RemRes = struct { w: ?Term, removed: bool }; // w==null ⇒ child vanished

    fn hamtRemoveChild(ctx: *Ctx, child: Term, k: Term, h: u64, shift: u6) error{OutOfMemory}!RemRes {
        if (childIsLeaf(child)) {
            if (cmp(ctx, k, leafKey(ctx, child), .exact) == .eq)
                return .{ .w = null, .removed = true };
            return .{ .w = child, .removed = false };
        }
        switch (headerSubtag(ctx, child)) {
            SUBTAG_HMAP_COLL => {
                const base = ptrIdx(child);
                const n = headerCount(ctx, child) / 2;
                var pairs: [40][2]Term = undefined;
                var m: usize = 0;
                var removed = false;
                for (0..n) |i| {
                    const pk = ctx.words.items[base + 1 + 2 * i];
                    if (!removed and cmp(ctx, pk, k, .exact) == .eq) {
                        removed = true;
                        continue;
                    }
                    pairs[m] = .{ pk, ctx.words.items[base + 2 + 2 * i] };
                    m += 1;
                }
                if (!removed) return .{ .w = child, .removed = false };
                if (m == 1) return .{ .w = try makeLeaf(ctx, pairs[0][0], pairs[0][1]), .removed = true };
                return .{ .w = try makeCollision(ctx, pairs[0..m]), .removed = true };
            },
            SUBTAG_HMAP_NODE => {
                const bm = nodeBitmap(ctx, child);
                const idx = chunk(h, shift);
                const bit = @as(u32, 1) << idx;
                if (bm & bit == 0) return .{ .w = child, .removed = false };
                const pos: usize = @popCount(bm & (bit - 1));
                // SNAPSHOT before recursion (heap growth invalidates slices)
                var buf: [33]Term = undefined;
                const nkids = nodeChildren(ctx, child).len;
                @memcpy(buf[0..nkids], nodeChildren(ctx, child));
                const r = try hamtRemoveChild(ctx, buf[pos], k, h, shift + 5);
                if (!r.removed) return .{ .w = child, .removed = false };
                if (r.w) |nw| {
                    buf[pos] = nw;
                    // canonical collapse: single remaining LEAF child hoists up
                    if (nkids == 1 and childIsLeaf(nw))
                        return .{ .w = nw, .removed = true };
                    return .{ .w = try makeNode(ctx, bm, buf[0..nkids]), .removed = true };
                }
                // child vanished entirely
                var out: [33]Term = undefined;
                @memcpy(out[0..pos], buf[0..pos]);
                @memcpy(out[pos .. nkids - 1], buf[pos + 1 .. nkids]);
                const nb = bm & ~bit;
                if (nkids - 1 == 1 and childIsLeaf(out[0]))
                    return .{ .w = out[0], .removed = true };
                if (nkids - 1 == 0) return .{ .w = null, .removed = true };
                return .{ .w = try makeNode(ctx, nb, out[0 .. nkids - 1]), .removed = true };
            },
            else => unreachable,
        }
    }

    pub fn mapGet(ctx: *Ctx, m: Term, k: Term) ?Term {
        if (mapRepIsFlat(ctx, m)) {
            const keys = flatKeys(ctx, m);
            for (keys, 0..) |mk_, i| {
                if (cmp(ctx, mk_, k, .exact) == .eq) return flatVals(ctx, m)[i];
            }
            return null;
        }
        return hamtGetChild(ctx, rootTop(ctx, m), k, keyHash(ctx, k), 0);
    }

    pub fn mapPut(ctx: *Ctx, m: Term, k: Term, v: Term) !Term {
        if (mapRepIsFlat(ctx, m)) {
            const keys = flatKeys(ctx, m);
            const vals = flatVals(ctx, m);
            const n = keys.len;
            var nk: [max_flatmap_size + 1]Term = undefined;
            var nv: [max_flatmap_size + 1]Term = undefined;
            var i: usize = 0;
            var out: usize = 0;
            var inserted = false;
            while (i < n) : (i += 1) {
                if (!inserted) {
                    const o = cmp(ctx, k, keys[i], .exact);
                    if (o == .lt) {
                        nk[out] = k;
                        nv[out] = v;
                        out += 1;
                        inserted = true;
                    } else if (o == .eq) {
                        nk[out] = k;
                        nv[out] = v;
                        out += 1;
                        inserted = true;
                        continue;
                    }
                }
                nk[out] = keys[i];
                nv[out] = vals[i];
                out += 1;
            }
            if (!inserted) {
                nk[out] = k;
                nv[out] = v;
                out += 1;
            }
            if (out <= max_flatmap_size) return makeFlat(ctx, nk[0..out], nv[0..out]);
            return hamtFromPairs(ctx, nk[0..out], nv[0..out]); // promote at 33
        }
        const r = try hamtPutChild(ctx, rootTop(ctx, m), k, v, keyHash(ctx, k), 0);
        return makeRoot(ctx, rootSize(ctx, m) + @intFromBool(r.added), r.w);
    }

    pub fn mapRemove(ctx: *Ctx, m: Term, k: Term) !Term {
        if (mapRepIsFlat(ctx, m)) {
            const keys = flatKeys(ctx, m);
            const vals = flatVals(ctx, m);
            var nk: [max_flatmap_size]Term = undefined;
            var nv: [max_flatmap_size]Term = undefined;
            var out: usize = 0;
            var removed = false;
            for (keys, 0..) |mk_, i| {
                if (!removed and cmp(ctx, mk_, k, .exact) == .eq) {
                    removed = true;
                    continue;
                }
                nk[out] = mk_;
                nv[out] = vals[i];
                out += 1;
            }
            if (!removed) return m; // absent: same map
            return makeFlat(ctx, nk[0..out], nv[0..out]);
        }
        const r = try hamtRemoveChild(ctx, rootTop(ctx, m), k, keyHash(ctx, k), 0);
        if (!r.removed) return m;
        const nsize = rootSize(ctx, m) - 1;
        if (nsize <= max_flatmap_size) {
            // demote: collect, sort exact, rebuild flat — CANONICAL FLATNESS
            var pk: [max_flatmap_size + 1]Term = undefined;
            var pv: [max_flatmap_size + 1]Term = undefined;
            var count: usize = 0;
            if (r.w) |top| hamtCollect(ctx, top, &pk, &pv, &count);
            std.debug.assert(count == nsize);
            const SortCtx = struct {
                ctx: *const Ctx,
                pk: []Term,
                pv: []Term,
                pub fn less(s: @This(), x: usize, y: usize) bool {
                    return cmp(s.ctx, s.pk[x], s.pk[y], .exact) == .lt;
                }
            };
            var idxs: [max_flatmap_size + 1]usize = undefined;
            for (0..count) |i| idxs[i] = i;
            std.sort.insertion(usize, idxs[0..count], SortCtx{ .ctx = ctx, .pk = pk[0..count], .pv = pv[0..count] }, SortCtx.less);
            var sk: [max_flatmap_size]Term = undefined;
            var sv: [max_flatmap_size]Term = undefined;
            for (idxs[0..count], 0..) |src, dst| {
                sk[dst] = pk[src];
                sv[dst] = pv[src];
            }
            return makeFlat(ctx, sk[0..count], sv[0..count]);
        }
        return makeRoot(ctx, nsize, r.w.?);
    }

    fn hamtCollect(ctx: *const Ctx, child: Term, pk: []Term, pv: []Term, count: *usize) void {
        if (childIsLeaf(child)) {
            pk[count.*] = leafKey(ctx, child);
            pv[count.*] = leafVal(ctx, child);
            count.* += 1;
            return;
        }
        switch (headerSubtag(ctx, child)) {
            SUBTAG_HMAP_COLL => {
                const base = ptrIdx(child);
                const n = headerCount(ctx, child) / 2;
                for (0..n) |i| {
                    pk[count.*] = ctx.words.items[base + 1 + 2 * i];
                    pv[count.*] = ctx.words.items[base + 2 + 2 * i];
                    count.* += 1;
                }
            },
            SUBTAG_HMAP_NODE => {
                for (nodeChildren(ctx, child)) |c| hamtCollect(ctx, c, pk, pv, count);
            },
            else => unreachable,
        }
    }

    // ---- binaries on words ---------------------------------------------------

    pub fn binConcat(ctx: *Ctx, x: Term, y: Term) !Term {
        const xb = binBytesOf(ctx, x);
        const yb = binBytesOf(ctx, y);
        const buf = try ctx.gpa.alloc(u8, xb.len + yb.len);
        defer ctx.gpa.free(buf);
        @memcpy(buf[0..xb.len], xb);
        @memcpy(buf[xb.len..], yb);
        return binary(ctx, buf);
    }
    pub fn binPart(ctx: *Ctx, b: Term, pos: usize, len: usize) !Term {
        // e49-binary-refc: binary:part/2,3 is ZERO-COPY — a sub-binary window
        // {pos, len, b} shares b's bytes instead of duping them (the erts
        // ErlSubBin). Bounds are validated against the resolved length; the
        // denotation is identical (binBytesOf resolves the window), so every
        // eql/hash/compare/etf/BIF law over the result is byte-for-byte
        // unchanged — this is a pure representation optimization.
        if (pos + len > binSize(ctx, b)) return error.BadArg;
        return subBinary(ctx, b, pos, len);
    }
    pub fn binSize(ctx: *Ctx, b: Term) usize {
        return binBytesOf(ctx, b).len;
    }

    pub fn iolistToBinary(ctx: *Ctx, t: Term) !Term {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(ctx.gpa);
        if (repIsBinary(ctx, t)) {
            try out.appendSlice(ctx.gpa, binBytesOf(ctx, t));
        } else if (isNil(t) or (t & TAG_MASK) == TAG_LIST) {
            try ioAccList(ctx, t, &out);
        } else return error.BadArg;
        return binary(ctx, out.items);
    }

    fn ioAccList(ctx: *Ctx, t0: Term, out: *std.ArrayList(u8)) error{ BadArg, OutOfMemory }!void {
        var t = t0;
        while (true) {
            if (isNil(t)) return;
            if ((t & TAG_MASK) == TAG_LIST) {
                const base = ptrIdx(t);
                try ioAccElem(ctx, ctx.words.items[base], out);
                t = ctx.words.items[base + 1];
                continue;
            }
            if (repIsBinary(ctx, t)) { // improper tail binary is legal iodata
                try out.appendSlice(ctx.gpa, binBytesOf(ctx, t));
                return;
            }
            return error.BadArg;
        }
    }
    fn ioAccElem(ctx: *Ctx, t: Term, out: *std.ArrayList(u8)) error{ BadArg, OutOfMemory }!void {
        if (repIsSmall(t)) {
            const v = smallVal(t);
            if (v < 0 or v > 255) return error.BadArg;
            try out.append(ctx.gpa, @intCast(v));
            return;
        }
        if (repIsBinary(ctx, t)) {
            try out.appendSlice(ctx.gpa, binBytesOf(ctx, t));
            return;
        }
        if (isNil(t) or (t & TAG_MASK) == TAG_LIST) return ioAccList(ctx, t, out);
        return error.BadArg;
    }

    // ---- observations ------------------------------------------------------

    // ---- wire-level observations (M9: the external format needs these) -----

    pub fn repIsAtom(w: Term) bool {
        return isAtom(w);
    }
    pub fn atomIdxOf(w: Term) AtomIdx {
        return atomIdx(w);
    }
    pub fn smallValOf(w: Term) i64 {
        std.debug.assert(repIsSmall(w));
        return smallVal(w);
    }
    pub const BigPartsPub = struct { positive: bool, limbs: []const u64 };
    pub fn bigPartsOf(ctx: *const Ctx, w: Term) BigPartsPub {
        const p = bigParts(ctx, w);
        return .{ .positive = p.positive, .limbs = p.limbs };
    }
    pub fn floatValOf(ctx: *const Ctx, w: Term) f64 {
        return floatVal(ctx, w);
    }
    /// E1.12: the IEEE `f64` value of ANY number term (small, bignum, or float)
    /// — the numeric-conversion observation the `fconv` opcode denotes. This is a
    /// CONVERSION (int→float), NOT a bit-reinterpretation: `numToF64Of(int 5)`
    /// is `5.0`, exactly `@floatFromInt(5)`. Precondition: `w` is a number
    /// (`repIsNumber`); the caller (execInstr `.fconv`) guards and crashes
    /// `badarith` on a non-number, so this never sees one.
    pub fn numToF64Of(ctx: *const Ctx, w: Term) f64 {
        return numToF64(ctx, w);
    }
    pub fn binBytes(ctx: *const Ctx, w: Term) []const u8 {
        return binBytesOf(ctx, w);
    }
    pub fn funParts(ctx: *const Ctx, w: Term) struct { label: u32, arity: u8, env_len: usize } {
        return .{ .label = funLabel(ctx, w), .arity = funArity(ctx, w), .env_len = funEnvLen(ctx, w) };
    }
    pub fn funEnvElem(ctx: *const Ctx, w: Term, i: usize) Term {
        return funEnvAt(ctx, w, i);
    }
    /// Collect all map pairs into caller buffers (flat: sorted-exact order;
    /// HAMT: trie order). Returns the pair count; buffers must hold size(m).
    pub fn mapPairs(ctx: *const Ctx, m: Term, pk: []Term, pv: []Term) usize {
        if (mapRepIsFlat(ctx, m)) {
            const keys = flatKeys(ctx, m);
            const vals = flatVals(ctx, m);
            @memcpy(pk[0..keys.len], keys);
            @memcpy(pv[0..vals.len], vals);
            return keys.len;
        }
        var count: usize = 0;
        mapPairsWalk(ctx, rootTop(ctx, m), pk, pv, &count);
        return count;
    }
    fn mapPairsWalk(ctx: *const Ctx, child: Term, pk: []Term, pv: []Term, count: *usize) void {
        if (childIsLeaf(child)) {
            pk[count.*] = leafKey(ctx, child);
            pv[count.*] = leafVal(ctx, child);
            count.* += 1;
            return;
        }
        switch (headerSubtag(ctx, child)) {
            SUBTAG_HMAP_COLL => {
                const base = ptrIdx(child);
                const n = headerCount(ctx, child) / 2;
                for (0..n) |i| {
                    pk[count.*] = ctx.words.items[base + 1 + 2 * i];
                    pv[count.*] = ctx.words.items[base + 2 + 2 * i];
                    count.* += 1;
                }
            },
            SUBTAG_HMAP_NODE => {
                for (nodeChildren(ctx, child)) |c| mapPairsWalk(ctx, c, pk, pv, count);
            },
            else => unreachable,
        }
    }

    // ---- structural reflection (the observation set matchers need) ---------

    pub const Kind = enum { number, atom, fun_, tuple, map, nil, cons, binary, reference, port, pid, native_record };

    pub fn kindOf(ctx: *Ctx, w: Term) Kind {
        return switch (rank(ctx, w)) {
            0 => .number,
            1 => .atom,
            2 => .reference, // E3.5
            3 => .fun_,
            4 => .port, // E3.5
            5 => .pid, // E3.5
            6 => .tuple,
            7 => .native_record, // E3.14
            8 => .map,
            9 => if (isNil(w)) .nil else .cons,
            // E3.3-fix (Fix 3): rank 11 is SUBTAG_MATCHCTX — an internal
            // control value with no `Kind` of its own. It denotes
            // `{bin, offset}` (see `denoteC`'s SUBTAG_MATCHCTX arm), and its
            // `bin` field is always a binary/bitstring by construction
            // (`makeMatchCtx`'s precondition), so `.binary` is the CLOSEST
            // defined `Kind` — a deliberate, documented boundary choice
            // (never `unreachable`) for the adversarial-bytecode case where
            // a match context reaches a type-test guard. DIVERGENCE_LOG
            // entry 16(c).
            10, 11 => .binary,
            else => unreachable,
        };
    }
    pub fn listHead(ctx: *Ctx, w: Term) Term {
        return ctx.words.items[ptrIdx(w)];
    }
    pub fn listTail(ctx: *Ctx, w: Term) Term {
        return ctx.words.items[ptrIdx(w) + 1];
    }
    pub fn tupleArity(ctx: *Ctx, w: Term) usize {
        return headerCount(ctx, w);
    }
    pub fn tupleElem(ctx: *Ctx, w: Term, i: usize) Term {
        return ctx.words.items[ptrIdx(w) + 1 + i];
    }
    /// E1.5: BEAM `set_tuple_element` — DESTRUCTIVELY overwrite element `i`
    /// (0-based) of tuple `w` with `v`, in place. The tuple's heap word at
    /// `base + 1 + i` is the tagged element slot `tupleElem` reads, so this is
    /// its exact inverse observation. Homomorphism law (below): after
    /// `setTupleElem(w, i, v)`, `denote(w)` equals the tuple with element `i`
    /// replaced by `denote(v)` and all others unchanged.
    ///
    /// SCOPE (mirrors BEAM's contract): the compiler only ever emits
    /// `set_tuple_element` on a freshly built, UNSHARED tuple (record update),
    /// so an in-place write is safe. This setter does NOT copy — an aliased
    /// tuple (two terms sharing `base`) would observe the write through both.
    /// Callers must uphold the no-sharing precondition, exactly as erts does.
    pub fn setTupleElem(ctx: *Ctx, w: Term, i: usize, v: Term) void {
        ctx.words.items[ptrIdx(w) + 1 + i] = v;
    }

    /// Arithmetic total term order computed by walking raw tagged words in
    /// place (cf. erts utils.c). Engineering note: comparing two maps where
    /// either is a HAMT materializes denotations into a scratch arena (erts
    /// uses temp stacks there too); OOM in that path panics, documented.
    pub fn compare(ctx: *Ctx, a: Term, b: Term) Order {
        return cmp(ctx, a, b, .arith);
    }
    pub fn compareExact(ctx: *Ctx, a: Term, b: Term) Order {
        return cmp(ctx, a, b, .exact);
    }

    fn cmp(ctx: *const Ctx, a: Term, b: Term, mode: CmpMode) Order {
        const ra = rank(ctx, a);
        const rb = rank(ctx, b);
        if (ra != rb) return if (ra < rb) .lt else .gt;
        if (ra == 0) return cmpNum(ctx, a, b, mode);
        if (isAtom(a)) // LEXICAL on names — the law that retired index order
            return fromMathOrder(std.mem.order(
                u8,
                ctx.atoms.nameOf(atomIdx(a)),
                ctx.atoms.nameOf(atomIdx(b)),
            ));
        // E3.5: reference/port/pid, EXACT field order within their own rank
        // (same rank here implies same kind).
        if (ra == 2) return cmpRef(ctx, a, b);
        if (ra == 4) return cmpPort(ctx, a, b);
        // MUTANT 1 site: pid orders `number` THEN `serial` — swapping this
        // (comparing serial before number) is killed by the total-order law
        // (see the module doc comment's Mutant-1 note and `spec.orderMode`'s
        // `.pid` arm, this function's Initial-encoding twin).
        if (ra == 5) return cmpPid(ctx, a, b);
        if (ra == 6) { // tuple vs tuple: arity first, then elementwise
            const na = headerCount(ctx, a);
            const nb = headerCount(ctx, b);
            if (na != nb) return if (na < nb) .lt else .gt;
            const ia = ptrIdx(a) + 1;
            const ib = ptrIdx(b) + 1;
            for (0..na) |k| {
                const o = cmp(ctx, ctx.words.items[ia + k], ctx.words.items[ib + k], mode);
                if (o != .eq) return o;
            }
            return .eq;
        }
        if (ra == 3) { // fun band: locals < externals; then per-kind fields
            // E7.1: this function's Initial-encoding twin is spec.orderMode's
            // `.fun_`/`.export_fun` arms. A local fun sorts below every
            // external fun; externals compare by (module, function, arity) with
            // module/function by atom NAME.
            const a_exp = repIsExportFun(ctx, a);
            const b_exp = repIsExportFun(ctx, b);
            if (a_exp != b_exp) return if (a_exp) .gt else .lt;
            if (a_exp) {
                const om = std.mem.order(u8, exportFunModuleName(ctx, a), exportFunModuleName(ctx, b));
                if (om != .eq) return fromMathOrder(om);
                const of = std.mem.order(u8, exportFunFuncName(ctx, a), exportFunFuncName(ctx, b));
                if (of != .eq) return fromMathOrder(of);
                const xa = exportFunArity(ctx, a);
                const xb = exportFunArity(ctx, b);
                return if (xa == xb) .eq else if (xa < xb) .lt else .gt;
            }
            // fun vs fun: label, arity, env length, env elementwise
            const la = funLabel(ctx, a);
            const lb = funLabel(ctx, b);
            if (la != lb) return if (la < lb) .lt else .gt;
            const aa = funArity(ctx, a);
            const ab_ = funArity(ctx, b);
            if (aa != ab_) return if (aa < ab_) .lt else .gt;
            const na = funEnvLen(ctx, a);
            const nb = funEnvLen(ctx, b);
            if (na != nb) return if (na < nb) .lt else .gt;
            for (0..na) |k| {
                const o = cmp(ctx, funEnvAt(ctx, a, k), funEnvAt(ctx, b, k), mode);
                if (o != .eq) return o;
            }
            return .eq;
        }
        if (ra == 7) return cmpNativeRecord(ctx, a, b, mode); // E3.14
        if (ra == 8) return cmpMap(ctx, a, b, mode);
        if (ra == 10) return bitsOrder(bsa.compare(finalBitsOf(ctx, a), finalBitsOf(ctx, b)));
        // E3.3-fix (Fix 3): SUBTAG_MATCHCTX orders like denote's synthetic
        // `{bin, offset}` 2-tuple (see `denoteC`'s SUBTAG_MATCHCTX arm) —
        // bin first, offset (as an int) second, mirroring the `ra == 6`
        // tuple-comparison shape above. Never reached by compiler-emitted
        // code; a defined, non-panicking outcome for adversarial bytecode.
        // DIVERGENCE_LOG entry 16(c). E3.14: matchctx moved to rank 11.
        if (ra == 11) {
            const ob = cmp(ctx, matchCtxBin(ctx, a), matchCtxBin(ctx, b), mode);
            if (ob != .eq) return ob;
            return cmp(ctx, int(undefined, @intCast(matchCtxOffset(ctx, a))), int(undefined, @intCast(matchCtxOffset(ctx, b))), mode);
        }
        // list kind: nil < cons; cons vs cons head-then-tail
        if (isNil(a)) return if (isNil(b)) .eq else .lt;
        if (isNil(b)) return .gt;
        const oh = cmp(ctx, ctx.words.items[ptrIdx(a)], ctx.words.items[ptrIdx(b)], mode);
        if (oh != .eq) return oh;
        return cmp(ctx, ctx.words.items[ptrIdx(a) + 1], ctx.words.items[ptrIdx(b) + 1], mode);
    }

    /// E5.7: node (lexical) then creation then the wire words — the Final
    /// twin of `spec.orderMode`'s `.reference` arm. Local refs share
    /// node/creation ⇒ this reduces to the pinned word order.
    fn cmpRef(ctx: *const Ctx, a: Term, b: Term) Order {
        const on = std.mem.order(u8, refNodeName(ctx, a), refNodeName(ctx, b));
        if (on != .eq) return fromMathOrder(on);
        const ca = refCreation(ctx, a);
        const cb = refCreation(ctx, b);
        if (ca != cb) return if (ca < cb) .lt else .gt;
        const wa = refWords(ctx, a);
        const wb = refWords(ctx, b);
        for (wa, wb) |x, y| {
            if (x != y) return if (x < y) .lt else .gt;
        }
        return .eq;
    }
    fn cmpPort(ctx: *const Ctx, a: Term, b: Term) Order {
        const on = std.mem.order(u8, portNodeName(ctx, a), portNodeName(ctx, b));
        if (on != .eq) return fromMathOrder(on);
        const ca = portCreation(ctx, a);
        const cb = portCreation(ctx, b);
        if (ca != cb) return if (ca < cb) .lt else .gt;
        const na = portNumber(ctx, a);
        const nb = portNumber(ctx, b);
        return if (na == nb) .eq else if (na < nb) .lt else .gt;
    }
    /// MUTANT 1 site: `number` compares FIRST, `serial` second — see the
    /// module doc comment's Mutant-1 note. E5.7: node/creation compare first.
    fn cmpPid(ctx: *const Ctx, a: Term, b: Term) Order {
        const on = std.mem.order(u8, pidNodeName(ctx, a), pidNodeName(ctx, b));
        if (on != .eq) return fromMathOrder(on);
        const ca = pidCreation(ctx, a);
        const cb = pidCreation(ctx, b);
        if (ca != cb) return if (ca < cb) .lt else .gt;
        const na = pidNumber(ctx, a);
        const nb = pidNumber(ctx, b);
        if (na != nb) return if (na < nb) .lt else .gt;
        const sa = pidSerial(ctx, a);
        const sb = pidSerial(ctx, b);
        return if (sa == sb) .eq else if (sa < sb) .lt else .gt;
    }

    /// E3.14: module, name, is_exported (false<true), field count, then keys
    /// (exact), then values (mode) — mirrors utils.c's RECORD_SUBTAG arm and
    /// the oracle `spec.orderMode` `.native_record` arm.
    fn cmpNativeRecord(ctx: *const Ctx, a: Term, b: Term, mode: CmpMode) Order {
        const om = cmp(ctx, nrModule(ctx, a), nrModule(ctx, b), .exact);
        if (om != .eq) return om;
        const on = cmp(ctx, nrName(ctx, a), nrName(ctx, b), .exact);
        if (on != .eq) return on;
        const ea = nrIsExported(ctx, a);
        const eb = nrIsExported(ctx, b);
        if (ea != eb) return if (!ea) .lt else .gt;
        const na = nrFieldCount(ctx, a);
        const nb = nrFieldCount(ctx, b);
        if (na != nb) return if (na < nb) .lt else .gt;
        for (0..na) |i| {
            const o = cmp(ctx, nrKeyAt(ctx, a, i), nrKeyAt(ctx, b, i), .exact);
            if (o != .eq) return o;
        }
        for (0..na) |i| {
            const o = cmp(ctx, nrValAt(ctx, a, i), nrValAt(ctx, b, i), mode);
            if (o != .eq) return o;
        }
        return .eq;
    }

    fn cmpMap(ctx: *const Ctx, a: Term, b: Term, mode: CmpMode) Order {
        const na = if (mapRepIsFlat(ctx, a)) flatN(ctx, a) else rootSize(ctx, a);
        const nb = if (mapRepIsFlat(ctx, b)) flatN(ctx, b) else rootSize(ctx, b);
        if (na != nb) return if (na < nb) .lt else .gt;
        if (mapRepIsFlat(ctx, a) and mapRepIsFlat(ctx, b)) {
            const ka = flatKeys(ctx, a);
            const kb = flatKeys(ctx, b);
            for (ka, kb) |x, y| {
                const o = cmp(ctx, x, y, .exact); // keys are exact in both modes
                if (o != .eq) return o;
            }
            for (flatVals(ctx, a), flatVals(ctx, b)) |x, y| {
                const o = cmp(ctx, x, y, mode);
                if (o != .eq) return o;
            }
            return .eq;
        }
        // HAMT involved: materialize both denotations (documented bound).
        var arena = std.heap.ArenaAllocator.init(ctx.gpa);
        defer arena.deinit();
        const sa = arena.allocator();
        const va = denoteC(ctx, sa, a) catch @panic("map compare OOM");
        const vb = denoteC(ctx, sa, b) catch @panic("map compare OOM");
        return spec.orderMode(va, vb, mode);
    }

    fn cmpNum(ctx: *const Ctx, a: Term, b: Term, mode: CmpMode) Order {
        const fa = repIsFloat(ctx, a);
        const fb = repIsFloat(ctx, b);
        if (fa and fb) return cmpF64(floatVal(ctx, a), floatVal(ctx, b), mode);
        if (fa or fb) {
            // one float, one integer: exact comparison, then mode tie-break
            var buf: [1]u64 = undefined;
            if (fb) {
                const p = operand(ctx, a, &buf);
                const o = cmpBigVsFloat(p.positive, p.limbs, floatVal(ctx, b));
                if (o == .eq and mode == .exact) return .lt; // int < float
                return o;
            }
            const p = operand(ctx, b, &buf);
            const o = invert(cmpBigVsFloat(p.positive, p.limbs, floatVal(ctx, a)));
            if (o == .eq and mode == .exact) return .gt;
            return o;
        }
        const sa = repIsSmall(a);
        const sb = repIsSmall(b);
        if (sa and sb) return spec.cmpInt(smallVal(a), smallVal(b));
        // Mixed small/big is O(1) — LICENSED BY the canonical-smallness law:
        // a bignum's magnitude never fits a small, so sign alone decides.
        if (sa) return if (bigParts(ctx, b).positive) .lt else .gt;
        if (sb) return if (bigParts(ctx, a).positive) .gt else .lt;
        const pa = bigParts(ctx, a);
        const pb = bigParts(ctx, b);
        if (pa.positive != pb.positive) return if (pa.positive) .gt else .lt;
        const m = cmpLimbs(pa.limbs, pb.limbs);
        return if (pa.positive) m else invert(m);
    }

    pub fn eql(ctx: *Ctx, a: Term, b: Term) bool {
        return cmp(ctx, a, b, .arith) == .eq;
    }
    pub fn eqlExact(ctx: *Ctx, a: Term, b: Term) bool {
        return cmp(ctx, a, b, .exact) == .eq;
    }

    // ── erlang:phash/2 legacy hash (erts `make_hash`) ───────────────────────
    // Faithful port of erts' `make_hash` (erl_term_hashing.c) — the LEGACY,
    // deprecated hash behind `erlang:phash/2`. This is a DIFFERENT algorithm
    // from `phash2`/`make_hash2` (different constant table, different term
    // walk); it must NOT be faked as `hashTerm`.
    //
    // All arithmetic is u32 WRAPPING: erts accumulates in a 64-bit word and
    // truncates to `Uint32` at return. Because reduction mod 2^32 is a ring
    // quotient of mod 2^64, every `+`/`*` commutes with the final truncation,
    // so u32-wrapping intermediates give the BYTE-IDENTICAL result.
    //
    // BYTE-EQ is PROVEN (LAW E31-T2) against pinned OTP-30 oracle values for
    // the DATA-TERM fragment: small ints, bignums, ASCII atoms, nil, lists
    // (incl. the string byte-optimization), tuples, floats, and byte-aligned
    // binaries. Non-data subtags (pid/port/ref/fun/export-fun/native-record/
    // map/hmap/non-byte-aligned bitstring/matchctx) are handled by a COHERENT
    // TOTAL extension — erts' own map-arm shape `h*N13 + N14 + make_hash2(t)`,
    // here `hashTermC` — so the BIF is total and =:=-coherent. That extension
    // is NOT byte-EQ to erts and is never claimed to be (see term_ops.zig doc).
    const PH_N1: u32 = 268440163; // FUNNY_NUMBER1
    const PH_N2: u32 = 268439161; // FUNNY_NUMBER2
    const PH_N3: u32 = 268435459; // FUNNY_NUMBER3 (positive int / nil)
    const PH_N4: u32 = 268436141; // FUNNY_NUMBER4 (negative int / binary tail)
    const PH_N6: u32 = 268437017; // FUNNY_NUMBER6 (float)
    const PH_N8: u32 = 268437511; // FUNNY_NUMBER8 (list CDR-post)
    const PH_N9: u32 = 268439627; // FUNNY_NUMBER9 (tuple arity)
    const PH_N12: u32 = 268440581; // FUNNY_NUMBER12 (bitstring tail bits)
    const PH_N13: u32 = 268440593; // FUNNY_NUMBER13 (extension mix)
    const PH_N14: u32 = 268440611; // FUNNY_NUMBER14 (extension add)

    /// One 4-byte little-endian pass of a u32 through the hash — erts'
    /// `UINT32_HASH_STEP` macro, exactly.
    fn phashUint32Step(h: u32, x: u32, prime: u32) u32 {
        return (((h *% prime +% (x & 0xFF)) *% prime +% ((x >> 8) & 0xFF)) *%
            prime +% ((x >> 16) & 0xFF)) *% prime +% (x >> 24);
    }

    /// hashpjw over an atom's stored name bytes — erts' `atom_hash` (atom.c),
    /// whose result is stored as the atom's `hvalue` and folded into the ATOM
    /// arm of make_hash. The 0xC2/0xC3 latin1→codepoint clutch matches r16-era
    /// behaviour for those UTF-8 pairs; for ASCII names `v` is the plain byte.
    fn phashAtomHval(name: []const u8) u32 {
        var h: u32 = 0;
        var i: usize = 0;
        while (i < name.len) : (i += 1) {
            var v: u32 = name[i];
            if (i + 1 < name.len and (name[i] & 0xFE) == 0xC2 and (name[i + 1] & 0xC0) == 0x80) {
                v = @as(u32, @as(u8, @truncate(@as(u32, name[i]) << 6))) | (name[i + 1] & 0x3F);
                i += 1;
            }
            h = (h << 4) +% v;
            const g = h & 0xf0000000;
            if (g != 0) {
                h ^= (g >> 24);
                h ^= g;
            }
        }
        return h;
    }

    /// erts' `hash_binary_bytes` for a byte-offset-0 view. `bytes` covers the
    /// full bytes, plus (when `bitsize > 0`) one trailing partial byte holding
    /// the tail bits in its high `bitsize` bits.
    fn phashBinaryBytes(h0: u32, bytes: []const u8, bitsize: u32) u32 {
        var h = h0;
        const bytesize: usize = if (bitsize > 0) bytes.len - 1 else bytes.len;
        var i: usize = 0;
        while (i < bytesize) : (i += 1) h = h *% PH_N1 +% bytes[i];
        if (bitsize > 0) {
            var b: u32 = bytes[bytesize];
            b >>= @intCast(8 - bitsize);
            h = (h *% PH_N1 +% b) *% PH_N12 +% bitsize;
        }
        return h *% PH_N4 +% @as(u32, @truncate(bytesize));
    }

    /// erts' BIG_DEF arm — magnitude hashed bytewise, little-endian, base-2^64
    /// limbs (== `ErtsDigit` on a 64-bit build); the last limb drops to 4 bytes
    /// when its top 32 bits are zero. Identical algorithm to the SMALL arm.
    fn phashBig(h0: u32, positive: bool, limbs: []const u64) u32 {
        var h = h0;
        if (limbs.len == 0) return h *% (if (positive) PH_N3 else PH_N4);
        const k = limbs.len - 1;
        var idx: usize = 0;
        while (idx < k) : (idx += 1) {
            var d = limbs[idx];
            var j: usize = 0;
            while (j < 8) : (j += 1) {
                h = h *% PH_N2 +% @as(u32, @intCast(d & 0xFF));
                d >>= 8;
            }
        }
        var d = limbs[k];
        const kbytes: usize = if ((d >> 32) == 0) 4 else 8;
        var j: usize = 0;
        while (j < kbytes) : (j += 1) {
            h = h *% PH_N2 +% @as(u32, @intCast(d & 0xFF));
            d >>= 8;
        }
        return h *% (if (positive) PH_N3 else PH_N4);
    }

    fn phashIsByte(w: Term) bool {
        return repIsSmall(w) and smallVal(w) >= 0 and smallVal(w) <= 255;
    }

    /// erts' LIST_DEF/CDR_PRE/CDR_POST control flow, unrolled. Consecutive
    /// small-byte CARs are folded inline (the string optimization, `*N2`); a
    /// non-byte CAR recurses; the improper/nil tail is hashed then the whole
    /// list run is closed with a single `*N8`.
    fn phashList(ctx: *const Ctx, h0: u32, term0: Term) u32 {
        var h = h0;
        var term = term0;
        while (true) {
            var base = ptrIdx(term);
            var car = ctx.words.items[base];
            var cdr = ctx.words.items[base + 1];
            while (phashIsByte(car)) {
                h = h *% PH_N2 +% @as(u32, @intCast(smallVal(car)));
                if ((cdr & TAG_MASK) != TAG_LIST) { // is_not_list(cdr)
                    h = phashWalk(ctx, h, cdr);
                    return h *% PH_N8;
                }
                base = ptrIdx(cdr);
                car = ctx.words.items[base];
                cdr = ctx.words.items[base + 1];
            }
            h = phashWalk(ctx, h, car); // non-byte CAR
            if ((cdr & TAG_MASK) != TAG_LIST) { // CDR_PRE: is_not_list(cdr)
                h = phashWalk(ctx, h, cdr);
                return h *% PH_N8;
            }
            term = cdr; // CDR is a list → continue the spine
        }
    }

    fn phashWalk(ctx: *const Ctx, h0: u32, term: Term) u32 {
        var h = h0;
        if (repIsSmall(term)) {
            const v = smallVal(term);
            const mag: u64 = @abs(v);
            h = phashUint32Step(h, @truncate(mag), PH_N2);
            if ((mag >> 32) != 0) h = phashUint32Step(h, @truncate(mag >> 32), PH_N2);
            return h *% (if (v < 0) PH_N4 else PH_N3);
        }
        if (isAtom(term)) {
            return h *% PH_N1 +% phashAtomHval(ctx.atoms.nameOf(atomIdx(term)));
        }
        if (isNil(term)) return h *% PH_N3 +% 1;
        switch (term & TAG_MASK) {
            TAG_LIST => return phashList(ctx, h, term),
            TAG_BOXED => switch (headerSubtag(ctx, term)) {
                SUBTAG_TUPLE => {
                    const base = ptrIdx(term);
                    const n = headerCount(ctx, term);
                    for (0..n) |k| h = phashWalk(ctx, h, ctx.words.items[base + 1 + k]);
                    return h *% PH_N9 +% @as(u32, @truncate(n));
                },
                SUBTAG_POS_BIG, SUBTAG_NEG_BIG => {
                    const p = bigParts(ctx, term);
                    return phashBig(h, p.positive, p.limbs);
                },
                SUBTAG_FLOAT => {
                    const fv = floatVal(ctx, term);
                    const bits: u64 = if (fv == 0.0) 0 else @bitCast(fv); // +0.0 canonicalizes -0.0
                    const fw0: u32 = @truncate(bits);
                    const fw1: u32 = @truncate(bits >> 32);
                    return h *% PH_N6 +% (fw0 ^ fw1);
                },
                SUBTAG_BINARY, SUBTAG_SUBBIN => return phashBinaryBytes(h, binBytesOf(ctx, term), 0), // e49-binary-refc: window hashes as its bytes
                SUBTAG_BITSTRING => {
                    const b = bitstringBits(ctx, term);
                    const full: usize = b.bit_len / 8;
                    const tail: u32 = @intCast(b.bit_len % 8);
                    if (tail == 0) return phashBinaryBytes(h, b.bytes[0..full], 0);
                    return phashBinaryBytes(h, b.bytes[0 .. full + 1], tail);
                },
                // COHERENT TOTAL extension for non-data subtags (see doc above).
                else => return h *% PH_N13 +% PH_N14 +% @as(u32, @truncate(hashTermC(ctx, term))),
            },
            else => unreachable,
        }
    }

    /// `erlang:phash/2`'s raw 32-bit hash — erts `make_hash`, BEFORE the BIF's
    /// `1 + (hash % Range)` range reduction. Byte-EQ over the data-term
    /// fragment; coherent total extension elsewhere (see doc above).
    pub fn phashLegacy(ctx: *Ctx, w: Term) u32 {
        return phashWalk(ctx, 0, w);
    }

    /// Exact-equality-coherent hash, computed by walking words in place;
    /// agrees with spec.hashValue∘denote by law.
    pub fn hashTerm(ctx: *Ctx, w: Term) u64 {
        return hashTermC(ctx, w);
    }
    fn hashTermC(ctx: *const Ctx, w: Term) u64 {
        var hs = Hasher{};
        hashWords(ctx, &hs, w);
        return hs.h;
    }
    fn hashWords(ctx: *const Ctx, hs: *Hasher, w: Term) void {
        if (repIsSmall(w)) {
            const v = smallVal(w);
            const mag: u64 = @abs(v);
            hashInt(hs, v >= 0, &.{mag});
            return;
        }
        if (isAtom(w)) {
            const name = ctx.atoms.nameOf(atomIdx(w));
            hs.byte(HTag.atom);
            hs.word(name.len);
            hs.bytes(name);
            return;
        }
        if (isNil(w)) {
            hs.byte(HTag.nil);
            return;
        }
        switch (w & TAG_MASK) {
            TAG_LIST => {
                const base = ptrIdx(w);
                hs.byte(HTag.cons);
                hashWords(ctx, hs, ctx.words.items[base]);
                hashWords(ctx, hs, ctx.words.items[base + 1]);
            },
            TAG_BOXED => switch (headerSubtag(ctx, w)) {
                SUBTAG_TUPLE => {
                    const base = ptrIdx(w);
                    const n = headerCount(ctx, w);
                    hs.byte(HTag.tuple);
                    hs.word(n);
                    for (0..n) |k| hashWords(ctx, hs, ctx.words.items[base + 1 + k]);
                },
                SUBTAG_POS_BIG, SUBTAG_NEG_BIG => {
                    const p = bigParts(ctx, w);
                    hashInt(hs, p.positive, p.limbs);
                },
                SUBTAG_FLOAT => {
                    hs.byte(HTag.float);
                    hs.word(@bitCast(floatVal(ctx, w)));
                },
                SUBTAG_BINARY, SUBTAG_SUBBIN, SUBTAG_PROCBIN => { // e49-binary-refc / e51-t2: hash as the bytes
                    const bs = binBytesOf(ctx, w);
                    hs.byte(HTag.binary);
                    hs.word(bs.len);
                    hs.bytes(bs);
                },
                SUBTAG_BITSTRING => {
                    const bits = bitstringBits(ctx, w);
                    if (bits.bit_len % 8 == 0) { // coherent with SUBTAG_BINARY (see spec.hashInto)
                        hs.byte(HTag.binary);
                        hs.word(bits.bytes.len);
                        hs.bytes(bits.bytes);
                    } else {
                        hs.byte(HTag.bitstring);
                        hs.word(bits.bit_len);
                        hs.bytes(bits.bytes);
                    }
                },
                SUBTAG_FUN => {
                    hs.byte(HTag.fun_);
                    hs.word(funLabel(ctx, w));
                    hs.word(funArity(ctx, w));
                    hs.word(funEnvLen(ctx, w));
                    for (0..funEnvLen(ctx, w)) |k| hashWords(ctx, hs, funEnvAt(ctx, w, k));
                },
                // E7.1: agrees with `spec.hashInto`'s `.export_fun` arm
                // (length-prefixed module/function NAMES, then arity).
                SUBTAG_EXPORT_FUN => {
                    hs.byte(HTag.export_fun);
                    const mn = exportFunModuleName(ctx, w);
                    hs.word(mn.len);
                    hs.bytes(mn);
                    const fnn = exportFunFuncName(ctx, w);
                    hs.word(fnn.len);
                    hs.bytes(fnn);
                    hs.word(exportFunArity(ctx, w));
                },
                // E3.5: agrees with `spec.hashInto`'s `.reference`/`.port`/
                // `.pid` arms (same tag byte + field order).
                SUBTAG_REF => {
                    const words = refWords(ctx, w);
                    hs.byte(HTag.reference);
                    hs.bytes(refNodeName(ctx, w));
                    hs.word(refCreation(ctx, w));
                    hs.word(words[0]);
                    hs.word(words[1]);
                    hs.word(words[2]);
                },
                SUBTAG_PORT => {
                    hs.byte(HTag.port);
                    hs.bytes(portNodeName(ctx, w));
                    hs.word(portCreation(ctx, w));
                    hs.word(portNumber(ctx, w));
                },
                SUBTAG_PID => {
                    hs.byte(HTag.pid);
                    hs.bytes(pidNodeName(ctx, w));
                    hs.word(pidCreation(ctx, w));
                    hs.word(pidNumber(ctx, w));
                    hs.word(pidSerial(ctx, w));
                },
                // E3.14: mirrors spec.hashInto's `.native_record` arm.
                SUBTAG_NATIVE_RECORD => {
                    hs.byte(HTag.native_record);
                    hashWords(ctx, hs, nrModule(ctx, w));
                    hashWords(ctx, hs, nrName(ctx, w));
                    hs.byte(if (nrIsExported(ctx, w)) 1 else 0);
                    const n = nrFieldCount(ctx, w);
                    hs.word(n);
                    for (0..n) |i| hashWords(ctx, hs, nrKeyAt(ctx, w, i));
                    for (0..n) |i| hashWords(ctx, hs, nrValAt(ctx, w, i));
                },
                SUBTAG_FLATMAP => {
                    const n = flatN(ctx, w);
                    hs.byte(HTag.map);
                    hs.word(n);
                    var acc: u64 = 0;
                    for (flatKeys(ctx, w), flatVals(ctx, w)) |k, v|
                        acc ^= mapPairMix(hashTermC(ctx, k), hashTermC(ctx, v));
                    hs.word(acc);
                },
                SUBTAG_HMAP_ROOT => {
                    hs.byte(HTag.map);
                    hs.word(rootSize(ctx, w));
                    var acc: u64 = 0;
                    hashHamtPairs(ctx, rootTop(ctx, w), &acc);
                    hs.word(acc);
                },
                // E3.3-fix (Fix 3): hash MatchCtx exactly the way `denoteC`
                // observes it — the synthetic `{bin, offset}` 2-tuple —
                // mirroring the SUBTAG_TUPLE arm above so this stays
                // coherent with `compareExact`'s ra==7 branch and with the
                // "hashTerm agrees with spec.hashValue∘denote" law. Never
                // reached by compiler-emitted code. DIVERGENCE_LOG entry
                // 16(c).
                SUBTAG_MATCHCTX => {
                    hs.byte(HTag.tuple);
                    hs.word(2);
                    hashWords(ctx, hs, matchCtxBin(ctx, w));
                    hashWords(ctx, hs, int(undefined, @intCast(matchCtxOffset(ctx, w))));
                },
                else => unreachable,
            },
            else => unreachable,
        }
    }
    fn hashHamtPairs(ctx: *const Ctx, child: Term, acc: *u64) void {
        if (childIsLeaf(child)) {
            acc.* ^= mapPairMix(hashTermC(ctx, leafKey(ctx, child)), hashTermC(ctx, leafVal(ctx, child)));
            return;
        }
        switch (headerSubtag(ctx, child)) {
            SUBTAG_HMAP_COLL => {
                const base = ptrIdx(child);
                const n = headerCount(ctx, child) / 2;
                for (0..n) |i| acc.* ^= mapPairMix(
                    hashTermC(ctx, ctx.words.items[base + 1 + 2 * i]),
                    hashTermC(ctx, ctx.words.items[base + 2 + 2 * i]),
                );
            },
            SUBTAG_HMAP_NODE => {
                for (nodeChildren(ctx, child)) |c| hashHamtPairs(ctx, c, acc);
            },
            else => unreachable,
        }
    }

    /// Decode tagged words back into the semantic domain.
    pub fn denote(ctx: *Ctx, arena: std.mem.Allocator, w: Term) error{OutOfMemory}!*const spec.Value {
        return denoteC(ctx, arena, w);
    }
    fn denoteC(ctx: *const Ctx, arena: std.mem.Allocator, w: Term) error{OutOfMemory}!*const spec.Value {
        const out = try arena.create(spec.Value);
        if (repIsSmall(w)) {
            out.* = .{ .int = try spec.bigFromI128(arena, smallVal(w)) };
        } else if (isAtom(w)) {
            out.* = .{ .atom = ctx.atoms.nameOf(atomIdx(w)) };
        } else if (isNil(w)) {
            out.* = .nil;
        } else switch (w & TAG_MASK) {
            TAG_LIST => {
                const base = ptrIdx(w);
                out.* = .{ .cons = .{
                    .head = try denoteC(ctx, arena, ctx.words.items[base]),
                    .tail = try denoteC(ctx, arena, ctx.words.items[base + 1]),
                } };
            },
            TAG_BOXED => switch (headerSubtag(ctx, w)) {
                SUBTAG_TUPLE => {
                    const base = ptrIdx(w);
                    const n = headerCount(ctx, w);
                    const elems = try arena.alloc(*const spec.Value, n);
                    for (elems, 0..) |*slot, k|
                        slot.* = try denoteC(ctx, arena, ctx.words.items[base + 1 + k]);
                    out.* = .{ .tuple = elems };
                },
                SUBTAG_POS_BIG, SUBTAG_NEG_BIG => {
                    const p = bigParts(ctx, w);
                    const limbs = try arena.alloc(spec.Limb, p.limbs.len);
                    for (p.limbs, 0..) |l, k| limbs[k] = @intCast(l);
                    out.* = .{ .int = .{ .limbs = limbs, .positive = p.positive } };
                },
                SUBTAG_FLOAT => out.* = .{ .float = floatVal(ctx, w) },
                SUBTAG_FUN => {
                    const n = funEnvLen(ctx, w);
                    const env = try arena.alloc(*const spec.Value, n);
                    for (env, 0..) |*slot, k|
                        slot.* = try denoteC(ctx, arena, funEnvAt(ctx, w, k));
                    out.* = .{ .fun_ = .{
                        .label = funLabel(ctx, w),
                        .arity = funArity(ctx, w),
                        .env = env,
                    } };
                },
                // E7.1: names are stable atom-table slices (like refNodeName).
                SUBTAG_EXPORT_FUN => out.* = .{ .export_fun = .{
                    .module = exportFunModuleName(ctx, w),
                    .function = exportFunFuncName(ctx, w),
                    .arity = exportFunArity(ctx, w),
                } },
                SUBTAG_REF => out.* = .{ .reference = .{ .words = refWords(ctx, w), .node = refNodeName(ctx, w), .creation = refCreation(ctx, w) } },
                SUBTAG_PORT => out.* = .{ .port = .{ .number = portNumber(ctx, w), .node = portNodeName(ctx, w), .creation = portCreation(ctx, w) } },
                SUBTAG_PID => out.* = .{ .pid = .{ .number = pidNumber(ctx, w), .serial = pidSerial(ctx, w), .node = pidNodeName(ctx, w), .creation = pidCreation(ctx, w) } },
                SUBTAG_NATIVE_RECORD => { // E3.14
                    const n = nrFieldCount(ctx, w);
                    const keys = try arena.alloc(*const spec.Value, n);
                    const vals = try arena.alloc(*const spec.Value, n);
                    for (0..n) |i| {
                        keys[i] = try denoteC(ctx, arena, nrKeyAt(ctx, w, i));
                        vals[i] = try denoteC(ctx, arena, nrValAt(ctx, w, i));
                    }
                    out.* = .{ .native_record = .{
                        .module = try denoteC(ctx, arena, nrModule(ctx, w)),
                        .name = try denoteC(ctx, arena, nrName(ctx, w)),
                        .is_exported = nrIsExported(ctx, w),
                        .keys = keys,
                        .values = vals,
                    } };
                },
                SUBTAG_BINARY, SUBTAG_SUBBIN, SUBTAG_PROCBIN => out.* = .{ .binary = try arena.dupe(u8, binBytesOf(ctx, w)) }, // e49-binary-refc / e51-t2: denotes its resolved bytes
                SUBTAG_BITSTRING => {
                    const bits = bitstringBits(ctx, w);
                    // gap-display-bitstring-binary (DIVERGENCE 649): a BYTE-ALIGNED
                    // bitstring (what a `<< _, Rest/binary >>` / `Rest/bits` TAIL bind
                    // produces) IS a binary — `repIsBinary` agrees, and the E3.1 law
                    // "an aligned bitstring orders/eql/hashes exactly like its binary
                    // twin" already fixes its observation. Denote it as `.binary` so it
                    // rides the SAME denotation as a flat binary — including the
                    // erlang:display printable-string heuristic (`<<"hello">>` not
                    // `<<104,...>>`, matching OTP). Only a genuinely SUB-BYTE bitstring
                    // stays `.bitstring` (the `<<5:4>>` form).
                    if (bits.bit_len % 8 == 0) {
                        out.* = .{ .binary = try arena.dupe(u8, bits.bytes) };
                    } else {
                        out.* = .{ .bitstring = .{ .bytes = try arena.dupe(u8, bits.bytes), .bit_len = bits.bit_len } };
                    }
                },
                SUBTAG_FLATMAP => {
                    const n = flatN(ctx, w);
                    const kvs = try arena.alloc(spec.KV, n);
                    for (flatKeys(ctx, w), flatVals(ctx, w), 0..) |k, v, i| {
                        kvs[i] = .{
                            .key = try denoteC(ctx, arena, k),
                            .val = try denoteC(ctx, arena, v),
                        };
                    }
                    out.* = .{ .map = kvs };
                },
                SUBTAG_HMAP_ROOT => {
                    const n = rootSize(ctx, w);
                    var pk = try arena.alloc(Term, n);
                    var pv = try arena.alloc(Term, n);
                    var count: usize = 0;
                    hamtCollectAlloc(ctx, rootTop(ctx, w), &pk, &pv, &count);
                    std.debug.assert(count == n);
                    const kvs = try arena.alloc(spec.KV, n);
                    for (0..n) |i| kvs[i] = .{
                        .key = try denoteC(ctx, arena, pk[i]),
                        .val = try denoteC(ctx, arena, pv[i]),
                    };
                    const SortCtx = struct {
                        pub fn less(_: @This(), x: spec.KV, y: spec.KV) bool {
                            return spec.orderExact(x.key, y.key) == .lt;
                        }
                    };
                    std.sort.insertion(spec.KV, kvs, SortCtx{}, SortCtx.less);
                    out.* = .{ .map = kvs };
                },
                // E3.3: a MatchCtx observes as the synthetic 2-tuple
                // {bin_denotation, offset_bits} — see the SUBTAG_MATCHCTX doc
                // comment. This is what makes `eqMachines` compare two
                // MatchCtx registers OBSERVATIONALLY (bin content + cursor),
                // never by heap-word identity.
                SUBTAG_MATCHCTX => {
                    const elems = try arena.alloc(*const spec.Value, 2);
                    elems[0] = try denoteC(ctx, arena, matchCtxBin(ctx, w));
                    elems[1] = try denoteC(ctx, arena, int(undefined, @intCast(matchCtxOffset(ctx, w))));
                    out.* = .{ .tuple = elems };
                },
                else => unreachable, // interior map nodes are never term handles
            },
            else => unreachable, // headers are never term handles
        }
        return out;
    }
    fn hamtCollectAlloc(ctx: *const Ctx, child: Term, pk: *[]Term, pv: *[]Term, count: *usize) void {
        if (childIsLeaf(child)) {
            pk.*[count.*] = leafKey(ctx, child);
            pv.*[count.*] = leafVal(ctx, child);
            count.* += 1;
            return;
        }
        switch (headerSubtag(ctx, child)) {
            SUBTAG_HMAP_COLL => {
                const base = ptrIdx(child);
                const n = headerCount(ctx, child) / 2;
                for (0..n) |i| {
                    pk.*[count.*] = ctx.words.items[base + 1 + 2 * i];
                    pv.*[count.*] = ctx.words.items[base + 2 + 2 * i];
                    count.* += 1;
                }
            },
            SUBTAG_HMAP_NODE => {
                for (nodeChildren(ctx, child)) |c| hamtCollectAlloc(ctx, c, pk, pv, count);
            },
            else => unreachable,
        }
    }

    // ---- copying GC ---------------------------------------------------------
    pub fn gcCopy(dst: *Ctx, src: *const Ctx, w: Term) error{OutOfMemory}!Term {
        if (repIsSmall(w) or isAtom(w) or isNil(w)) return w; // immediates move freely
        return switch (w & TAG_MASK) {
            TAG_LIST => blk: {
                const base = ptrIdx(w);
                const h = try gcCopy(dst, src, src.words.items[base]);
                const t = try gcCopy(dst, src, src.words.items[base + 1]);
                break :blk try cons(dst, h, t);
            },
            TAG_BOXED => switch (headerSubtag(src, w)) {
                SUBTAG_TUPLE => blk: {
                    const base = ptrIdx(w);
                    const n = headerCount(src, w);
                    var buf = try dst.gpa.alloc(Term, n);
                    defer dst.gpa.free(buf);
                    for (0..n) |k|
                        buf[k] = try gcCopy(dst, src, src.words.items[base + 1 + k]);
                    break :blk try tuple(dst, buf);
                },
                SUBTAG_POS_BIG, SUBTAG_NEG_BIG => blk: {
                    const p = bigParts(src, w);
                    break :blk try makeBig(dst, p.positive, p.limbs);
                },
                SUBTAG_FLOAT => try makeFloat(dst, floatVal(src, w)),
                SUBTAG_FUN => blk: {
                    const n = funEnvLen(src, w);
                    var buf = try dst.gpa.alloc(Term, n);
                    defer dst.gpa.free(buf);
                    for (0..n) |k| buf[k] = try gcCopy(dst, src, funEnvAt(src, w, k));
                    break :blk try makeFun(dst, funLabel(src, w), funArity(src, w), buf);
                },
                // E7.1: module/function are atom immediates — they move freely
                // (the "atoms move freely" gcCopy invariant), arity a raw word.
                SUBTAG_EXPORT_FUN => try makeExportFun(dst, exportFunModule(src, w), exportFunFunction(src, w), exportFunArity(src, w)),
                // E5.7: node atom idx moves verbatim (shared atom table —
                // the "atoms move freely" gcCopy invariant; cross-node goes
                // via ETF, never gc). creation carried alongside.
                SUBTAG_REF => try refExt(dst, refWords(src, w), refNode(src, w), refCreation(src, w)),
                SUBTAG_PORT => try portExt(dst, portNumber(src, w), portNode(src, w), portCreation(src, w)),
                SUBTAG_PID => try pidExt(dst, pidNumber(src, w), pidSerial(src, w), pidNode(src, w), pidCreation(src, w)),
                SUBTAG_NATIVE_RECORD => blk: { // E3.14
                    const n = nrFieldCount(src, w);
                    var nk: [max_nr_fields]Term = undefined;
                    var nv: [max_nr_fields]Term = undefined;
                    std.debug.assert(n <= max_nr_fields);
                    for (0..n) |i| {
                        nk[i] = try gcCopy(dst, src, nrKeyAt(src, w, i)); // atoms: immediate
                        nv[i] = try gcCopy(dst, src, nrValAt(src, w, i));
                    }
                    break :blk try nativeRecord(dst, nrModule(src, w), nrName(src, w), nrIsExported(src, w), nk[0..n], nv[0..n]);
                },
                SUBTAG_BINARY, SUBTAG_SUBBIN => try binary(dst, binBytesOf(src, w)), // e49-binary-refc: cross-heap copy FLATTENS the window (erts small-bin materialize)
                SUBTAG_PROCBIN => blk: {
                    // e51-t2 THE SHARE-ON-SEND WIN: a cross-heap copy of a
                    // refcounted binary RETAINS the payload (bumps count) and
                    // copies only the one pointer word — the receiver's box
                    // points at the SAME bytes, not a fresh copy. `dst` takes a
                    // strong ref (recorded in its refcs, released at its deinit).
                    const r = procBinRefc(src, w);
                    r.count += 1;
                    const b = try dst.alloc(2);
                    dst.words.items[b] = header(SUBTAG_PROCBIN, 1);
                    dst.words.items[b + 1] = @intFromPtr(r);
                    try dst.refcs.append(dst.gpa, b); // record the box index
                    break :blk (@as(u64, b) << 2) | TAG_BOXED;
                },
                SUBTAG_BITSTRING => blk: {
                    const bits = bitstringBits(src, w);
                    break :blk try bitstring(dst, bits.bytes, bits.bit_len);
                },
                SUBTAG_FLATMAP => blk: {
                    const n = flatN(src, w);
                    var nk: [max_flatmap_size]Term = undefined;
                    var nv: [max_flatmap_size]Term = undefined;
                    for (flatKeys(src, w), 0..) |k, i| nk[i] = try gcCopy(dst, src, k);
                    for (flatVals(src, w), 0..) |v, i| nv[i] = try gcCopy(dst, src, v);
                    // keys' values are preserved ⇒ exact order is preserved
                    break :blk try makeFlat(dst, nk[0..n], nv[0..n]);
                },
                SUBTAG_HMAP_ROOT => blk: {
                    // rebuild by insertion: the trie is canonical, so the
                    // destination structure equals the source's.
                    var top = try makeNode(dst, 0, &.{});
                    var size: usize = 0;
                    try hamtCopyInto(dst, src, rootTop(src, w), &top, &size);
                    std.debug.assert(size == rootSize(src, w));
                    break :blk try makeRoot(dst, size, top);
                },
                SUBTAG_MATCHCTX => blk: { // E3.3: raw offset + a recursively-copied bin term
                    const off = matchCtxOffset(src, w);
                    const bin = try gcCopy(dst, src, matchCtxBin(src, w));
                    break :blk try makeMatchCtx(dst, bin, off);
                },
                else => unreachable,
            },
            else => unreachable,
        };
    }

    fn hamtCopyInto(dst: *Ctx, src: *const Ctx, child: Term, top: *Term, size: *usize) error{OutOfMemory}!void {
        if (childIsLeaf(child)) {
            const k = try gcCopy(dst, src, leafKey(src, child));
            const v = try gcCopy(dst, src, leafVal(src, child));
            const r = try hamtPutChild(dst, top.*, k, v, keyHash(dst, k), 0);
            std.debug.assert(r.added);
            top.* = r.w;
            size.* += 1;
            return;
        }
        switch (headerSubtag(src, child)) {
            SUBTAG_HMAP_COLL => {
                const base = ptrIdx(child);
                const n = headerCount(src, child) / 2;
                for (0..n) |i| {
                    const k = try gcCopy(dst, src, src.words.items[base + 1 + 2 * i]);
                    const v = try gcCopy(dst, src, src.words.items[base + 2 + 2 * i]);
                    const r = try hamtPutChild(dst, top.*, k, v, keyHash(dst, k), 0);
                    std.debug.assert(r.added);
                    top.* = r.w;
                    size.* += 1;
                }
            },
            SUBTAG_HMAP_NODE => {
                for (nodeChildren(src, child)) |c| try hamtCopyInto(dst, src, c, top, size);
            },
            else => unreachable,
        }
    }

    // ------------------------------------------------------------------------
    // M6: the REAL collector — evacuation with FORWARDING WORDS.
    //
    // gcCopy above stays as the M1 duplicating oracle. This collector
    // preserves SHARING (a DAG-shaped rootset copies each cell once) and
    // supports in-place generational collection via the erts high-water
    // discipline: indices below `keep_below` are OLD (or literal) space —
    // immutable, unmoved, never scanned, and by construction never point
    // above the water line (terms are immutable, so old→young references
    // cannot exist; this is why BEAM needs no write barrier).
    //
    // Forwarding marker: a tag-00 word with subtag 0b1111 (never a real
    // header) carrying the target index in bits 6.. . A cons cell's word 0
    // is always a term handle (tags 01/10/11), so a tag-00 word there is
    // unambiguously a forwarding word too.
    // ------------------------------------------------------------------------

    const SUBTAG_FWD: u64 = 0b1111;

    fn fwdWord(target: usize) u64 {
        return (@as(u64, target) << 7) | (SUBTAG_FWD << 2);
    }
    fn fwdTarget(w: u64) ?usize {
        if ((w & TAG_MASK) == 0 and ((w >> 2) & 0x1F) == SUBTAG_FWD)
            return @intCast(w >> 7);
        return null;
    }

    pub const Collector = struct {
        src: *Ctx,
        out: std.ArrayList(u64),
        base_offset: usize,
        keep_below: usize,
        gpa: std.mem.Allocator,
        // gap-binary-share-across-gc: the DESTINATION ctx when evacuating into a
        // FRESH heap (collectInto) — non-null there, null for an in-place collect
        // (src == dst). A ProcBin evacuated into a fresh heap RETAINS its off-heap
        // payload (bumps the refcount, records the box in `dst.refcs`); an in-place
        // collect shares without retaining and reconciles `src.refcs` afterward.
        dst: ?*Ctx = null,

        /// Evacuate one root slot in place.
        pub fn root(self: *Collector, slot: *Term) error{OutOfMemory}!void {
            slot.* = try self.evac(slot.*);
        }

        fn evac(self: *Collector, w: Term) error{OutOfMemory}!Term {
            if (repIsSmall(w) or isAtom(w) or isNil(w)) return w;
            const tag = w & TAG_MASK;
            const base = ptrIdx(w);
            if (base < self.keep_below) return w; // old/literal space: immovable
            if (fwdTarget(self.src.words.items[base])) |t|
                return (@as(u64, t) << 2) | tag; // already evacuated: SHARE
            return switch (tag) {
                TAG_LIST => blk: {
                    const h = try self.evac(self.src.words.items[base]);
                    const t = try self.evac(self.src.words.items[base + 1]);
                    const pos = self.out.items.len;
                    try self.out.append(self.gpa, h);
                    try self.out.append(self.gpa, t);
                    const final = self.base_offset + pos;
                    self.src.words.items[base] = fwdWord(final);
                    break :blk (@as(u64, final) << 2) | TAG_LIST;
                },
                TAG_BOXED => blk: {
                    const hdr = self.src.words.items[base];
                    const subtag = (hdr >> 2) & 0x1F;
                    const count: usize = @intCast(hdr >> 7);
                    if (subtag == SUBTAG_PROCBIN) {
                        // gap-binary-share-across-gc THE SHARE-ACROSS-GC WIN: a
                        // copying collect relocates only the 2-word ProcBin box
                        // (header + pointer) — the off-heap payload STAYS PUT and
                        // is SHARED, never byte-copied. The pointer word is copied
                        // verbatim, so `binBytes` still resolves the same buffer.
                        //   • into a FRESH heap (dst != null): the new heap gains a
                        //     logical reference → RETAIN (bump count, record box).
                        //   • in place (dst == null): the reference count is
                        //     unchanged (the ref moves with the box); dead ProcBins
                        //     are released by `finishInPlace`'s reconciliation, which
                        //     reads the forwarding word this evac stamps below.
                        const pos = self.out.items.len;
                        try self.out.append(self.gpa, hdr);
                        try self.out.append(self.gpa, self.src.words.items[base + 1]);
                        const final = self.base_offset + pos;
                        if (self.dst) |d| {
                            const r: *Refc = @ptrFromInt(self.src.words.items[base + 1]);
                            r.count += 1;
                            try d.refcs.append(d.gpa, final);
                        }
                        self.src.words.items[base] = fwdWord(final);
                        break :blk (@as(u64, final) << 2) | TAG_BOXED;
                    }
                    // which payload offsets (1-based) hold term handles?
                    // raw prefix words: none for tuple/coll; 1 for flatmap
                    // (n), fun (label,arity → 2), hmap node (bitmap → 1),
                    // hmap root (size → 1); everything for bigs/float/binary.
                    const term_from: usize = switch (subtag) {
                        // E3.14: native-record prefix (module/name/exported/
                        // keys) is all immediates (evac is a no-op on them),
                        // values are terms → evac EVERY payload word (=1),
                        // like a tuple.
                        SUBTAG_TUPLE, SUBTAG_HMAP_COLL, SUBTAG_NATIVE_RECORD => 1,
                        // E3.3: MatchCtx's one raw prefix word (offset_bits)
                        // then its one term slot (bin) — same shape as
                        // FLATMAP's `n`-prefix / HMAP's bitmap-or-size prefix.
                        SUBTAG_FLATMAP, SUBTAG_HMAP_NODE, SUBTAG_HMAP_ROOT, SUBTAG_MATCHCTX => 2,
                        SUBTAG_FUN => 3,
                        // e49-binary-refc: offset|len raw, then the base TERM
                        // slot — so the GC relocates+shares the base and the
                        // window survives collections (offset stays valid).
                        SUBTAG_SUBBIN => 3,
                        // E3.5: reference/port/pid are all-raw payload too
                        // (no term slots) — see the SUBTAG_REF/PORT/PID doc
                        // comment.
                        // E7.1: export fun is all-raw too (module/function atom
                        // immediates + raw arity) — bucket with the no-slot kinds.
                        SUBTAG_POS_BIG, SUBTAG_NEG_BIG, SUBTAG_FLOAT, SUBTAG_BINARY, SUBTAG_BITSTRING, SUBTAG_REF, SUBTAG_PORT, SUBTAG_PID, SUBTAG_EXPORT_FUN => 1 + count, // no term slots
                        else => unreachable, // FWD handled above; headers exhaustive
                    };
                    var buf: [96]u64 = undefined;
                    std.debug.assert(1 + count <= 96);
                    buf[0] = hdr;
                    // raw words copied verbatim
                    for (1..@min(term_from, 1 + count)) |k| buf[k] = self.src.words.items[base + k];
                    // term slots evacuated (recursively) BEFORE placing parent
                    var k = term_from;
                    while (k < 1 + count) : (k += 1)
                        buf[k] = try self.evac(self.src.words.items[base + k]);
                    const pos = self.out.items.len;
                    try self.out.appendSlice(self.gpa, buf[0 .. 1 + count]);
                    const final = self.base_offset + pos;
                    self.src.words.items[base] = fwdWord(final);
                    break :blk (@as(u64, final) << 2) | TAG_BOXED;
                },
                else => unreachable, // headers are never term handles
            };
        }
    };

    /// Full collection into a FRESH heap (sharing-preserving gcCopy).
    pub fn collectInto(dst: *Ctx, src: *Ctx) Collector {
        return .{
            .src = src,
            .out = dst.words, // moved back by finishInto
            .base_offset = dst.words.items.len,
            .keep_below = 0,
            .gpa = dst.gpa,
            .dst = dst, // gap-binary-share-across-gc: retain ProcBins into the fresh heap
        };
    }
    pub fn finishInto(dst: *Ctx, c: *Collector) void {
        dst.words = c.out;
    }

    /// In-place collection: everything at index ≥ keep_below is evacuated
    /// and compacted onto the water line; below it nothing moves. Call
    /// root() for EVERY live root between begin and finish.
    ///   minor GC:  keep_below = current high water (old gen stays put)
    ///   major GC:  keep_below = literal water line (only literals stay)
    ///   full compaction: keep_below = 0
    pub fn collectInPlace(ctx: *Ctx, keep_below: usize) Collector {
        return .{
            .src = ctx,
            .out = .empty,
            .base_offset = keep_below,
            .keep_below = keep_below,
            .gpa = ctx.gpa,
        };
    }
    /// Splice survivors onto the water line; returns the new high water.
    pub fn finishInPlace(ctx: *Ctx, c: *Collector) !usize {
        // gap-binary-share-across-gc: RECONCILE the off-heap refcounts across the
        // in-place collect BEFORE the from-space (which still holds the forwarding
        // stamps `evac` wrote) is discarded by the shrink. For each ProcBin box
        // this ctx owns a strong ref through:
        //   • box < keep_below   → OLD/LITERAL space: never scanned, unmoved, LIVE
        //                          → keep the entry verbatim (no premature free).
        //   • forwarding word    → SURVIVOR: relocated to `final` → keep, retarget
        //                          the entry (the ref rides along, count unchanged).
        //   • otherwise          → DEAD (unreachable this collect) → release ONE
        //                          strong ref; the payload frees IFF its count hit 0
        //                          (its last box died) — never while a live box
        //                          points at it, and at most once.
        // This makes refcount == number-of-live-boxes an invariant across GC.
        var kept: std.ArrayList(usize) = .empty;
        errdefer kept.deinit(ctx.gpa);
        for (ctx.refcs.items) |box| {
            if (box < c.keep_below) {
                try kept.append(ctx.gpa, box);
            } else if (fwdTarget(ctx.words.items[box])) |final| {
                try kept.append(ctx.gpa, final);
            } else {
                const r: *Refc = @ptrFromInt(ctx.words.items[box + 1]);
                refcRelease(ctx.gpa, r);
            }
        }
        ctx.refcs.deinit(ctx.gpa);
        ctx.refcs = kept;

        ctx.words.shrinkRetainingCapacity(c.keep_below);
        try ctx.words.appendSlice(ctx.gpa, c.out.items);
        c.out.deinit(c.gpa);
        return ctx.words.items.len;
    }

    /// Old-space invariant (why BEAM needs no write barrier): no term slot
    /// below the water line points at or above it. Checked as a LAW.
    pub fn checkNoOldToYoung(ctx: *const Ctx, water: usize) bool {
        var i: usize = 0;
        while (i < water) {
            const w = ctx.words.items[i];
            if ((w & TAG_MASK) == 0 and fwdTarget(w) == null) {
                // a header: skip raw payload words, check term slots
                const subtag = (w >> 2) & 0x1F;
                const count: usize = @intCast(w >> 7);
                const term_from: usize = switch (subtag) {
                    SUBTAG_TUPLE, SUBTAG_HMAP_COLL, SUBTAG_NATIVE_RECORD => 1,
                    // E3.3: see the matching note in `Collector.evac` above.
                    SUBTAG_FLATMAP, SUBTAG_HMAP_NODE, SUBTAG_HMAP_ROOT, SUBTAG_MATCHCTX => 2,
                    SUBTAG_FUN => 3,
                    SUBTAG_SUBBIN => 3, // e49-binary-refc: base term slot at word 3
                    else => 1 + count,
                };
                var k = term_from;
                while (k < 1 + count) : (k += 1) {
                    if (!slotBelow(ctx.words.items[i + k], water)) return false;
                }
                i += 1 + count;
                continue;
            }
            // otherwise: a cons-cell region or unreachable garbage; treat the
            // word as a potential term slot conservatively
            if (!slotBelow(w, water)) return false;
            i += 1;
        }
        return true;
    }
    fn slotBelow(w: u64, water: usize) bool {
        if (repIsSmall(w) or isAtom(w) or isNil(w)) return true;
        if ((w & TAG_MASK) == 0) return true; // header/fwd, not a handle
        return ptrIdx(w) < water;
    }
};

/// Generator fan-out bound (also bounds the GC scratch buffer).
pub const max_tuple_arity = 4;
/// Fun environment capture bound (final-encoding GC scratch).
pub const max_fun_env = 4;

// ============================================================================
// PART 4: LAWS — generator + property suites, generic over the encoding
// ============================================================================

fn randomAtomIdx(random: std.Random, atoms: *AtomTable) !AtomIdx {
    var buf: [6]u8 = undefined;
    const len = 1 + random.uintLessThan(usize, buf.len);
    for (buf[0..len]) |*b| b.* = 'a' + random.uintLessThan(u8, 26);
    return atoms.intern(buf[0..len]);
}

fn randomBigI128(random: std.Random) i128 {
    // magnitude in [2^61, 2^126): always beyond small range
    const mag: u128 = (@as(u128, 1) << 61) |
        (@as(u128, random.int(u64)) << 62) | random.int(u64);
    return if (random.boolean()) @intCast(mag) else -@as(i128, @intCast(mag));
}

/// Finite floats; half are exactly integer-valued to exercise the
/// int/float tie laws.
fn randomFloat(random: std.Random) f64 {
    if (random.boolean())
        return @floatFromInt(@as(i64, random.int(i16)));
    return @as(f64, @floatFromInt(@as(i64, random.int(i32)))) * 0x1p-8;
}

pub fn genNumber(comptime Impl: type, random: std.Random, ctx: *Impl.Ctx) !Impl.Term {
    return if (random.boolean())
        Impl.int(ctx, @as(i64, random.int(i48)))
    else
        try Impl.intFromI128(ctx, randomBigI128(random));
}

/// Numbers including floats — for laws that hold over all Erlang numbers
/// (commutativity, oracle agreement), NOT for associativity (IEEE).
pub fn genNumberMixed(comptime Impl: type, random: std.Random, ctx: *Impl.Ctx) !Impl.Term {
    return switch (random.uintLessThan(u8, 3)) {
        0 => Impl.int(ctx, @as(i64, random.int(i48))),
        1 => try Impl.intFromI128(ctx, randomBigI128(random)),
        else => Impl.float(ctx, randomFloat(random)),
    };
}

pub fn genTerm(
    comptime Impl: type,
    random: std.Random,
    ctx: *Impl.Ctx,
    depth: usize,
) error{ OutOfMemory, BadArg }!Impl.Term {
    const Variant = enum { int, bigint, float, atom, nil, binary, bitstring, reference, port, pid, cons, tuple, map, fun_, export_fun };
    const pick: Variant = if (depth == 0) switch (random.uintLessThan(u8, 10)) {
        0 => .int,
        1 => .bigint,
        2 => .float,
        3 => .atom,
        4 => .binary,
        5 => .bitstring,
        6 => .reference,
        7 => .port,
        8 => .pid,
        else => .nil,
    } else random.enumValue(Variant);

    return switch (pick) {
        .int => Impl.int(ctx, @as(i64, random.int(i48))),
        .bigint => try Impl.intFromI128(ctx, randomBigI128(random)),
        .float => Impl.float(ctx, randomFloat(random)),
        .atom => Impl.atom(ctx, try randomAtomIdx(random, ctx.atoms)),
        .nil => Impl.nil(ctx),
        .binary => blk: {
            var buf: [12]u8 = undefined;
            const len = random.uintLessThan(usize, buf.len + 1);
            for (buf[0..len]) |*b| b.* = random.int(u8);
            break :blk try Impl.binary(ctx, buf[0..len]);
        },
        // E3.1: mixed into every generic law suite (order/hash/GC/encoding
        // homomorphism) that already drives on genTerm — the "seeded MIX
        // of the new kind with ALL existing term kinds" the Recipe asks for.
        .bitstring => blk: {
            var buf: [12]u8 = undefined;
            const nbytes = random.uintLessThan(usize, buf.len + 1);
            for (buf[0..nbytes]) |*b| b.* = random.int(u8);
            const bit_len = if (nbytes == 0) 0 else random.uintLessThan(usize, nbytes * 8 + 1);
            break :blk try Impl.bitstring(ctx, buf[0..nbytes], bit_len);
        },
        // E3.5: mixed into every generic law suite the same way E3.1's
        // bitstring was — the "seeded MIX of the new kinds with ALL
        // existing term kinds" the Recipe asks for.
        .reference => blk: {
            const words: [3]u32 = .{ random.int(u32), random.int(u32), random.int(u32) };
            break :blk try Impl.ref(ctx, words);
        },
        .port => try Impl.port(ctx, random.int(u32)),
        // pid number/serial are bounded to u32 here (a documented
        // engineering bound at the wire boundary — NEW_PID_EXT's ID/Serial
        // fields are u32; see etf.zig): keeping the generator in-range
        // means the ETF round-trip law never has to reject its own output.
        .pid => try Impl.pid(ctx, random.int(u32), random.int(u32)),
        .cons => try Impl.cons(
            ctx,
            try genTerm(Impl, random, ctx, depth - 1),
            try genTerm(Impl, random, ctx, depth - 1),
        ),
        .tuple => blk: {
            const n = random.uintLessThan(u8, max_tuple_arity + 1);
            var buf: [max_tuple_arity]Impl.Term = undefined;
            for (0..n) |k| buf[k] = try genTerm(Impl, random, ctx, depth - 1);
            break :blk try Impl.tuple(ctx, buf[0..n]);
        },
        .map => blk: {
            const n = random.uintLessThan(u8, max_tuple_arity + 1);
            var ks: [max_tuple_arity]Impl.Term = undefined;
            var vs: [max_tuple_arity]Impl.Term = undefined;
            for (0..n) |k| {
                ks[k] = try genTerm(Impl, random, ctx, depth - 1);
                vs[k] = try genTerm(Impl, random, ctx, depth - 1);
            }
            break :blk try Impl.mapNew(ctx, ks[0..n], vs[0..n]);
        },
        .fun_ => blk: {
            const label: u32 = random.int(u8);
            const arity: u8 = random.uintLessThan(u8, 4);
            const n = random.uintLessThan(u8, 3);
            var env: [2]Impl.Term = undefined;
            for (0..n) |k| env[k] = try genTerm(Impl, random, ctx, depth - 1);
            break :blk try Impl.makeFun(ctx, label, arity, env[0..n]);
        },
        // E7.1: external funs mixed into every generic law suite (order/hash/
        // GC/denote homomorphism) — the "seeded MIX of the new kind with ALL
        // existing kinds" the Recipe asks for. A small atom pool (via
        // randomAtomIdx) keeps module/function collisions frequent so the
        // total-order/equality laws exercise the tie-break fields.
        .export_fun => blk: {
            const m = Impl.atom(ctx, try randomAtomIdx(random, ctx.atoms));
            const f = Impl.atom(ctx, try randomAtomIdx(random, ctx.atoms));
            const arity: u8 = random.uintLessThan(u8, 5);
            break :blk try Impl.makeExportFun(ctx, m, f, arity);
        },
    };
}

pub const LawConfig = struct {
    iterations: usize = 120,
    max_depth: usize = 4,
    seed: u64 = 0xBEA0CAFE,
};

pub fn expectLaw(ok: bool, name: []const u8, cfg: LawConfig, iter: usize) !void {
    if (!ok) {
        std.debug.print("LAW FAILED: {s} (seed=0x{x}, iteration={d}, depth={d})\n", .{ name, cfg.seed, iter, cfg.max_depth });
        return error.LawViolated;
    }
}

fn le(o: Order) bool {
    return o != .gt;
}

pub fn verifyTermLaws(comptime Impl: type, gpa: std.mem.Allocator, cfg: LawConfig) !void {
    comptime requireTermAlgebra(Impl);
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var ctx = Impl.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        var spec_arena = std.heap.ArenaAllocator.init(gpa);
        defer spec_arena.deinit();
        const sa = spec_arena.allocator();

        const a = try genTerm(Impl, random, &ctx, cfg.max_depth);
        const b = try genTerm(Impl, random, &ctx, cfg.max_depth);
        const c = try genTerm(Impl, random, &ctx, cfg.max_depth);

        // Order laws — BOTH orders are total preorders agreeing with spec
        try expectLaw(Impl.compare(&ctx, a, a) == .eq, "reflexivity (arith)", cfg, i);
        try expectLaw(Impl.compareExact(&ctx, a, a) == .eq, "reflexivity (exact)", cfg, i);
        try expectLaw(Impl.compare(&ctx, a, b) == invert(Impl.compare(&ctx, b, a)), "antisymmetry (arith)", cfg, i);
        try expectLaw(Impl.compareExact(&ctx, a, b) == invert(Impl.compareExact(&ctx, b, a)), "antisymmetry (exact)", cfg, i);
        if (le(Impl.compare(&ctx, a, b)) and le(Impl.compare(&ctx, b, c)))
            try expectLaw(le(Impl.compare(&ctx, a, c)), "transitivity (arith)", cfg, i);
        if (le(Impl.compareExact(&ctx, a, b)) and le(Impl.compareExact(&ctx, b, c)))
            try expectLaw(le(Impl.compareExact(&ctx, a, c)), "transitivity (exact)", cfg, i);
        try expectLaw(Impl.eql(&ctx, a, b) == (Impl.compare(&ctx, a, b) == .eq), "eql iff compare-eq", cfg, i);
        try expectLaw(Impl.eqlExact(&ctx, a, b) == (Impl.compareExact(&ctx, a, b) == .eq), "eqlExact iff compareExact-eq", cfg, i);
        // exact refines arithmetic
        if (Impl.eqlExact(&ctx, a, b))
            try expectLaw(Impl.eql(&ctx, a, b), "exact-eq implies arith-eq", cfg, i);
        try expectLaw(Impl.compare(&ctx, a, b) ==
            spec.order(try Impl.denote(&ctx, sa, a), try Impl.denote(&ctx, sa, b)), "spec agreement (arith)", cfg, i);
        try expectLaw(Impl.compareExact(&ctx, a, b) ==
            spec.orderExact(try Impl.denote(&ctx, sa, a), try Impl.denote(&ctx, sa, b)), "spec agreement (exact)", cfg, i);

        // Hash laws — coherent with EXACT equality, agrees with the spec hash
        try expectLaw(Impl.hashTerm(&ctx, a) == spec.hashValue(try Impl.denote(&ctx, sa, a)), "hash agrees with spec hash", cfg, i);
        if (Impl.eqlExact(&ctx, a, b))
            try expectLaw(Impl.hashTerm(&ctx, a) == Impl.hashTerm(&ctx, b), "exact-eq implies equal hash", cfg, i);

        // Arithmetic laws — '+' against the spec oracle (ints: exact big math)
        const n1 = try genNumber(Impl, random, &ctx);
        const n2 = try genNumber(Impl, random, &ctx);
        const n3 = try genNumber(Impl, random, &ctx);
        const sum = try Impl.add(&ctx, n1, n2);
        const expected = try spec.addValues(
            sa,
            (try Impl.denote(&ctx, sa, n1)).int,
            (try Impl.denote(&ctx, sa, n2)).int,
        );
        try expectLaw((try Impl.denote(&ctx, sa, sum)).int.order(expected) == .eq, "add agrees with the big-int oracle", cfg, i);
        try expectLaw(Impl.eql(&ctx, sum, try Impl.add(&ctx, n2, n1)), "add commutativity", cfg, i);
        try expectLaw(Impl.eql(
            &ctx,
            try Impl.add(&ctx, try Impl.add(&ctx, n1, n2), n3),
            try Impl.add(&ctx, n1, try Impl.add(&ctx, n2, n3)),
        ), "add associativity (ints)", cfg, i);
        try expectLaw(Impl.eql(&ctx, try Impl.add(&ctx, n1, Impl.int(&ctx, 0)), n1), "add right identity (0)", cfg, i);

        // Mixed-number '+': agreement with the spec oracle + commutativity
        const f1 = try genNumberMixed(Impl, random, &ctx);
        const f2 = try genNumberMixed(Impl, random, &ctx);
        const fsum = try Impl.add(&ctx, f1, f2);
        const fexp = try spec.addNum(sa, try Impl.denote(&ctx, sa, f1), try Impl.denote(&ctx, sa, f2));
        try expectLaw(spec.eqlExact(try Impl.denote(&ctx, sa, fsum), fexp), "mixed add agrees with the spec oracle", cfg, i);
        try expectLaw(Impl.eqlExact(&ctx, fsum, try Impl.add(&ctx, f2, f1)), "mixed add commutativity", cfg, i);

        // Equality is by VALUE, never by address/representation history.
        var twin1 = std.Random.DefaultPrng.init(cfg.seed +% i);
        var twin2 = std.Random.DefaultPrng.init(cfg.seed +% i);
        const x1 = try genTerm(Impl, twin1.random(), &ctx, cfg.max_depth);
        const x2 = try genTerm(Impl, twin2.random(), &ctx, cfg.max_depth);
        try expectLaw(Impl.eqlExact(&ctx, x1, x2), "value-not-address equality (exact)", cfg, i);
        try expectLaw(Impl.hashTerm(&ctx, x1) == Impl.hashTerm(&ctx, x2), "value-not-address hashing", cfg, i);
    }
}

pub fn verifyEncodingHomomorphism(gpa: std.mem.Allocator, cfg: LawConfig) !void {
    comptime requireTermAlgebra(InitialTerms);
    comptime requireTermAlgebra(FinalTerms);
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng_a = std.Random.DefaultPrng.init(cfg.seed);
    var prng_b = std.Random.DefaultPrng.init(cfg.seed);

    for (0..cfg.iterations) |i| {
        var ic = InitialTerms.Ctx.init(gpa, &atoms);
        defer ic.deinit();
        var fc = FinalTerms.Ctx.init(gpa, &atoms);
        defer fc.deinit();
        var spec_arena = std.heap.ArenaAllocator.init(gpa);
        defer spec_arena.deinit();
        const sa = spec_arena.allocator();

        const ra = prng_a.random();
        const rb = prng_b.random();
        const t1a = try genTerm(InitialTerms, ra, &ic, cfg.max_depth);
        const t1b = try genTerm(InitialTerms, ra, &ic, cfg.max_depth);
        const t2a = try genTerm(FinalTerms, rb, &fc, cfg.max_depth);
        const t2b = try genTerm(FinalTerms, rb, &fc, cfg.max_depth);

        try expectLaw(spec.eqlExact(
            try InitialTerms.denote(&ic, sa, t1a),
            try FinalTerms.denote(&fc, sa, t2a),
        ), "homomorphism: denotations agree (exact)", cfg, i);
        try expectLaw(InitialTerms.compare(&ic, t1a, t1b) == FinalTerms.compare(&fc, t2a, t2b), "homomorphism: compares agree", cfg, i);
        try expectLaw(InitialTerms.compareExact(&ic, t1a, t1b) == FinalTerms.compareExact(&fc, t2a, t2b), "homomorphism: exact compares agree", cfg, i);
        try expectLaw(InitialTerms.hashTerm(&ic, t1a) == FinalTerms.hashTerm(&fc, t2a), "homomorphism: hashes agree", cfg, i);

        // '+' through both encodings on twin numbers
        const m1a = try genNumberMixed(InitialTerms, ra, &ic);
        const m1b = try genNumberMixed(InitialTerms, ra, &ic);
        const m2a = try genNumberMixed(FinalTerms, rb, &fc);
        const m2b = try genNumberMixed(FinalTerms, rb, &fc);
        try expectLaw(spec.eqlExact(
            try InitialTerms.denote(&ic, sa, try InitialTerms.add(&ic, m1a, m1b)),
            try FinalTerms.denote(&fc, sa, try FinalTerms.add(&fc, m2a, m2b)),
        ), "homomorphism: '+' agrees across encodings", cfg, i);
    }
}

pub fn verifyGcHomomorphism(gpa: std.mem.Allocator, cfg: LawConfig) !void {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var from = FinalTerms.Ctx.init(gpa, &atoms);
        defer from.deinit();
        var to = FinalTerms.Ctx.init(gpa, &atoms);
        defer to.deinit();
        var spec_arena = std.heap.ArenaAllocator.init(gpa);
        defer spec_arena.deinit();
        const sa = spec_arena.allocator();

        const root = try genTerm(FinalTerms, random, &from, cfg.max_depth);
        const before = try FinalTerms.denote(&from, sa, root);
        const hash_before = FinalTerms.hashTerm(&from, root);

        const copied = try FinalTerms.gcCopy(&to, &from, root);
        @memset(from.words.items, 0xAAAA_AAAA_AAAA_AAAA); // poison from-space

        const after = try FinalTerms.denote(&to, sa, copied);
        try expectLaw(spec.eqlExact(before, after), "gc: denotation preserved across poisoned from-space", cfg, i);
        try expectLaw(FinalTerms.hashTerm(&to, copied) == hash_before, "gc: hash invariant", cfg, i);
    }
}

// ============================================================================
// Verification suite
// ============================================================================

test "Laws: Initial (tree oracle, spec arithmetic) is lawful" {
    try verifyTermLaws(InitialTerms, std.testing.allocator, .{});
}

test "Laws: Final (erts-style tagged words, limb arithmetic) is lawful" {
    try verifyTermLaws(FinalTerms, std.testing.allocator, .{});
}

test "Homomorphism: oracle and tagged-word heap denote the same algebra" {
    try verifyEncodingHomomorphism(std.testing.allocator, .{});
}

test "GC: copying collection is a heap-to-heap homomorphism (all kinds)" {
    try verifyGcHomomorphism(std.testing.allocator, .{});
}

// E1.5: the `setTupleElem` HOMOMORPHISM law. `set_tuple_element` is a real new
// term-algebra primitive (destructive in-place write), so it ships its own law:
// mutating element `i` of a tuple in place is DENOTATIONALLY identical to
// building the tuple fresh with element `i` replaced — and every other element
// is left untouched. Random arities/positions/values; the seed is echoed by the
// std.testing harness on failure.
test "LAW E1.5 setTupleElem homomorphism: denote(after) == tuple with elem i replaced" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(0x5E77_1E5E);
    const random = prng.random();

    for (0..300) |it| {
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();

        const n: usize = 1 + random.uintLessThan(usize, 5);
        var elems: [6]FinalTerms.Term = undefined;
        for (elems[0..n]) |*e| e.* = FinalTerms.int(&ctx, random.int(i16));
        const t = try FinalTerms.tuple(&ctx, elems[0..n]);

        const i = random.uintLessThan(usize, n);
        const v = FinalTerms.int(&ctx, 1000 + @as(i64, @intCast(it)));

        // Expected: a FRESH tuple with element i replaced (the oracle value).
        var exp: [6]FinalTerms.Term = undefined;
        @memcpy(exp[0..n], elems[0..n]);
        exp[i] = v;
        const expected = try FinalTerms.tuple(&ctx, exp[0..n]);

        // Destructive mutation of the original.
        FinalTerms.setTupleElem(&ctx, t, i, v);

        // Homomorphism: the mutated tuple and the fresh one denote the same value.
        const da = try FinalTerms.denote(&ctx, sa, t);
        const db = try FinalTerms.denote(&ctx, sa, expected);
        try std.testing.expect(spec.eqlExact(da, db));

        // Element-wise: position i is v; every other position is unchanged.
        for (0..n) |k| {
            const want = if (k == i) v else elems[k];
            try std.testing.expect(FinalTerms.eqlExact(&ctx, FinalTerms.tupleElem(&ctx, t, k), want));
        }
    }
}

// E2.4: the small-integer arithmetic-extension HOMOMORPHISM laws. Each new op
// is a homomorphism from the term algebra into ℤ (Zig i128 ground truth):
// denote(op(x,y)) == op_ℤ(x, y). Scoped to small operands (the documented
// precursor domain); the div/rem PARTNER identity `(x div y)*y + (x rem y) == x`
// and the shift symmetry `x bsl -n == x bsr n` are pinned too. Seed is echoed by
// the std.testing harness on failure. Mutant target: an off-by-one in bnot
// (`-x` instead of `-x-1`) or a wrong div rounding (@divFloor) breaks this.
test "LAW E2.4 small-int arithmetic homomorphisms agree with ℤ (mul/div/rem/band/bor/bxor/bnot/bsl/bsr)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var prng = std.Random.DefaultPrng.init(0x2E44_A817);
    const random = prng.random();

    for (0..2000) |_| {
        const a: i64 = random.int(i32);
        var b: i64 = random.int(i32);
        const xa = FinalTerms.int(&ctx, a);
        const xb = FinalTerms.int(&ctx, b);

        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.mul(&ctx, xa, xb), try FinalTerms.intFromI128(&ctx, @as(i128, a) * @as(i128, b))));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.band(&ctx, xa, xb), FinalTerms.int(&ctx, a & b)));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bor(&ctx, xa, xb), FinalTerms.int(&ctx, a | b)));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bxor(&ctx, xa, xb), FinalTerms.int(&ctx, a ^ b)));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bnot(&ctx, xa), FinalTerms.int(&ctx, ~a)));

        if (b == 0) b = 1;
        const yb = FinalTerms.int(&ctx, b);
        const q = try FinalTerms.idiv(&ctx, xa, yb);
        const r = try FinalTerms.irem(&ctx, xa, yb);
        try std.testing.expect(FinalTerms.eqlExact(&ctx, q, try FinalTerms.intFromI128(&ctx, @divTrunc(@as(i128, a), @as(i128, b)))));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, r, try FinalTerms.intFromI128(&ctx, @rem(@as(i128, a), @as(i128, b)))));
        // partner identity: (x div y)*y + (x rem y) == x
        const back = try FinalTerms.add(&ctx, try FinalTerms.mul(&ctx, q, yb), r);
        try std.testing.expect(FinalTerms.eqlExact(&ctx, back, FinalTerms.int(&ctx, a)));

        const sc: i64 = random.uintLessThan(u8, 40);
        const small_a: i64 = random.int(i16);
        const shl = try FinalTerms.bsl(&ctx, FinalTerms.int(&ctx, small_a), FinalTerms.int(&ctx, sc));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, shl, try FinalTerms.intFromI128(&ctx, @as(i128, small_a) << @intCast(sc))));
        const shr = try FinalTerms.bsr(&ctx, xa, FinalTerms.int(&ctx, sc));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, shr, try FinalTerms.intFromI128(&ctx, @as(i128, a) >> @intCast(sc))));
        // symmetry: x bsl -n == x bsr n
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bsl(&ctx, xa, FinalTerms.int(&ctx, -sc)), try FinalTerms.bsr(&ctx, xa, FinalTerms.int(&ctx, sc))));
    }

    // Rejection: div/rem by zero is a CLEAN error (badarith), never a panic.
    const z = FinalTerms.int(&ctx, 0);
    const one = FinalTerms.int(&ctx, 1);
    try std.testing.expectError(error.Badarith, FinalTerms.idiv(&ctx, one, z));
    try std.testing.expectError(error.Badarith, FinalTerms.irem(&ctx, one, z));
    // triage-big-divergences + bitwise-big (CORRECT the original deferral
    // assertions): a bignum operand is now EXACT for the whole integer family —
    // `mul` (the mulMag kernel), and `band` (the two's-complement limb path:
    // 2^59 band 1 == 0). The former "defers cleanly" badarith arms were the
    // documented gaps those slices discharged.
    const big = try FinalTerms.add(&ctx, FinalTerms.int(&ctx, (1 << 59) - 1), one); // promotes to big
    try std.testing.expect(FinalTerms.repIsBig(&ctx, big));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.mul(&ctx, big, one), big));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.band(&ctx, big, one), z));
}

test "Canonical smallness: promotion and demotion at the 2^59 boundary" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const sa = arena.allocator();

    // Promotion: (2^59 - 1) + 1 == 2^59 must leave the small range → boxed big
    const near = FinalTerms.int(&ctx, (1 << 59) - 1);
    const one = FinalTerms.int(&ctx, 1);
    const promoted = try FinalTerms.add(&ctx, near, one);
    try std.testing.expect(!FinalTerms.repIsSmall(promoted));
    try std.testing.expect(FinalTerms.repIsBig(&ctx, promoted));
    const want = try spec.bigFromI128(sa, 1 << 59);
    try std.testing.expect((try FinalTerms.denote(&ctx, sa, promoted)).int.order(want) == .eq);

    // Negative edge: -(2^59) is the smallest small
    const neg_edge = try FinalTerms.add(&ctx, FinalTerms.int(&ctx, -(1 << 59) + 1), FinalTerms.int(&ctx, -1));
    try std.testing.expect(FinalTerms.repIsSmall(neg_edge));
    const neg_over = try FinalTerms.add(&ctx, neg_edge, FinalTerms.int(&ctx, -1));
    try std.testing.expect(FinalTerms.repIsBig(&ctx, neg_over));

    // Demotion: big + big landing back in small range must be encoded small
    const big_pos = try FinalTerms.intFromI128(&ctx, 1 << 61);
    const big_neg = try FinalTerms.intFromI128(&ctx, -(1 << 61) + 7);
    const demoted = try FinalTerms.add(&ctx, big_pos, big_neg);
    try std.testing.expect(FinalTerms.repIsSmall(demoted));
    try std.testing.expect(FinalTerms.eql(&ctx, demoted, FinalTerms.int(&ctx, 7)));
}

test "Atom order is LEXICAL on names, not numeric on indices (M1 retrofit)" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    // Intern in anti-lexical order so index order and name order disagree.
    const zebra = try atoms.intern("zebra"); // idx 0
    const apple = try atoms.intern("apple"); // idx 1
    const ab = try atoms.intern("ab");
    const b = try atoms.intern("b");
    try std.testing.expect(zebra < apple); // indices really are inverted

    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, FinalTerms.atom(&ctx, apple), FinalTerms.atom(&ctx, zebra)));
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, FinalTerms.atom(&ctx, ab), FinalTerms.atom(&ctx, b)));

    var ic = InitialTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ic.deinit();
    try std.testing.expectEqual(Order.lt, InitialTerms.compare(&ic, InitialTerms.atom(&ic, apple), InitialTerms.atom(&ic, zebra)));
}

test "LAW triage-big-divergences BIGNUM mul/div/rem homomorphisms agree with ℤ (mixed small/big + big/big, seeded)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var prng = std.Random.DefaultPrng.init(0x81D_B16D);
    const random = prng.random();

    // Seeded i128-scale operands cross the small/big boundary in every mix
    // (small×big, big×small, big×big) with all four sign combinations; the
    // ℤ side is computed in i128 — a genuinely independent oracle for the
    // limb kernels (mulMag products up to 2^126 stay in-range).
    for (0..2000) |_| {
        // a ≤ ~2^71, b ≤ ~2^55 ⇒ |a·b| ≤ ~2^126 < i128 max (the ℤ oracle must
        // itself not overflow — `*%` would silently wrap and blame the kernel).
        const a: i128 = @as(i128, random.int(i64)) * (@as(i128, random.int(u8)) + 1);
        var b: i128 = @as(i128, random.int(i64) >> 8) >> @intCast(random.uintLessThan(u6, 48));
        if (b == 0) b = 3;
        const xa = try FinalTerms.intFromI128(&ctx, a);
        const xb = try FinalTerms.intFromI128(&ctx, b);
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.mul(&ctx, xa, xb), try FinalTerms.intFromI128(&ctx, a *% b)));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.idiv(&ctx, xa, xb), try FinalTerms.intFromI128(&ctx, @divTrunc(a, b))));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.irem(&ctx, xa, xb), try FinalTerms.intFromI128(&ctx, @rem(a, b))));
    }

    // The div/rem LAW (the inverse-pair identity the BEAM pins): for bignum
    // operands beyond i128 (built multiplicatively at runtime, no oracle
    // constant): x == (x div y)*y + (x rem y), 0 <= |rem| < |y|, rem carries
    // the dividend's sign; and exact division has zero remainder.
    const big1 = try FinalTerms.intFromI128(&ctx, (1 << 100) + 7); // ~2^100
    const p = try FinalTerms.mul(&ctx, big1, big1); // ~2^200 (beyond i128)
    const q = try FinalTerms.idiv(&ctx, p, big1);
    const r = try FinalTerms.irem(&ctx, p, big1);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, q, big1)); // (b*b) div b == b
    try std.testing.expect(FinalTerms.eqlExact(&ctx, r, FinalTerms.int(&ctx, 0)));
    const p1 = try FinalTerms.add(&ctx, p, FinalTerms.int(&ctx, 5)); // b*b + 5
    const q1 = try FinalTerms.idiv(&ctx, p1, big1);
    const r1 = try FinalTerms.irem(&ctx, p1, big1);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, q1, big1));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, r1, FinalTerms.int(&ctx, 5)));
    // reassemble: q1*y + r1 == x  (the law itself, over the >i128 domain)
    const back = try FinalTerms.add(&ctx, try FinalTerms.mul(&ctx, q1, big1), r1);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, back, p1));

    // CARRY-DENSE vectors (added after mutant m1b — truncating the trailing
    // carry chain in mulMag SURVIVED the seeded set): all-ones limbs make the
    // partial-product sums saturate, forcing multi-limb carry propagation.
    // (2^63-1)·(2^63+1) = 2^126-1 is checkable directly in the i128 oracle;
    // the (2^126-1)² product (beyond i128) is pinned by the div/rem identity.
    const m63 = try FinalTerms.intFromI128(&ctx, (1 << 63) - 1);
    const p63 = try FinalTerms.intFromI128(&ctx, (1 << 63) + 1);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.mul(&ctx, m63, p63), try FinalTerms.intFromI128(&ctx, (1 << 126) - 1)));
    const ones126 = try FinalTerms.intFromI128(&ctx, (1 << 126) - 1);
    const sq = try FinalTerms.mul(&ctx, ones126, ones126);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.idiv(&ctx, sq, ones126), ones126));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.irem(&ctx, sq, ones126), FinalTerms.int(&ctx, 0)));
    // (x+1)·(x-1) = x²-1 with x = 2^126-1: the binomial identity over the
    // carry-dense domain, reassembled through add — three kernels agreeing.
    const xp1 = try FinalTerms.add(&ctx, ones126, FinalTerms.int(&ctx, 1));
    const xm1 = try FinalTerms.add(&ctx, ones126, FinalTerms.int(&ctx, -1));
    const lhs = try FinalTerms.mul(&ctx, xp1, xm1);
    const rhs = try FinalTerms.add(&ctx, sq, FinalTerms.int(&ctx, -1));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, lhs, rhs));

    // ÷0 is badarith for every operand mix (small and big dividends).
    try std.testing.expectError(error.Badarith, FinalTerms.idiv(&ctx, p, FinalTerms.int(&ctx, 0)));
    try std.testing.expectError(error.Badarith, FinalTerms.irem(&ctx, big1, FinalTerms.int(&ctx, 0)));
}

test "LAW bitwise-big TWO'S-COMPLEMENT bitwise/shift homomorphisms agree with ℤ (mixed small/big, infinite word)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var prng = std.Random.DefaultPrng.init(0xB17_B16);
    const random = prng.random();

    // Seeded i128-scale operands, all sign mixes, crossing the small/big
    // boundary. i128's native &,|,^,>> are exactly the infinite-word
    // two's-complement semantics for in-range values — an independent oracle.
    for (0..2000) |_| {
        const a: i128 = @as(i128, random.int(i64)) * (@as(i128, random.int(u8)) + 1);
        const b: i128 = @as(i128, random.int(i64)) >> @intCast(random.uintLessThan(u6, 48));
        const xa = try FinalTerms.intFromI128(&ctx, a);
        const xb = try FinalTerms.intFromI128(&ctx, b);
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.band(&ctx, xa, xb), try FinalTerms.intFromI128(&ctx, a & b)));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bor(&ctx, xa, xb), try FinalTerms.intFromI128(&ctx, a | b)));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bxor(&ctx, xa, xb), try FinalTerms.intFromI128(&ctx, a ^ b)));
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bnot(&ctx, xa), try FinalTerms.intFromI128(&ctx, -a - 1)));
        // arithmetic right shift: i128 `>>` floors — the bsr semantics.
        const sh: i64 = random.uintLessThan(u6, 63);
        const xsh = FinalTerms.int(&ctx, sh);
        try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bsr(&ctx, xa, xsh), try FinalTerms.intFromI128(&ctx, a >> @intCast(sh))));
    }

    // >i128 domain: the boolean-algebra identities over a runtime-built bignum
    // (x = (2^126-1)·(2^100+7) — beyond i128, carry-dense) with cross-kernel
    // reassembly. minus_one is the infinite word of all ones.
    const f126 = try FinalTerms.intFromI128(&ctx, (1 << 126) - 1);
    const b100 = try FinalTerms.intFromI128(&ctx, (1 << 100) + 7);
    const x = try FinalTerms.mul(&ctx, f126, b100);
    const nx = try FinalTerms.bnot(&ctx, x);
    const minus_one = FinalTerms.int(&ctx, -1);
    const zero = FinalTerms.int(&ctx, 0);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bnot(&ctx, nx), x)); // involution
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.band(&ctx, x, nx), zero));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bor(&ctx, x, nx), minus_one));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bxor(&ctx, x, nx), minus_one));
    // shifts: left-then-right round-trip; bsl ≡ ×2^k (cross-kernel: mul);
    // negative bsr floors (-x bsr n == -(((x-1) bsr n) + 1), via the oracle-free
    // reassembly bnot(x) bsr n == bnot(x bsr n) — a two's-complement identity).
    const k = FinalTerms.int(&ctx, 100);
    const xl = try FinalTerms.bsl(&ctx, x, k);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bsr(&ctx, xl, k), x));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, xl, try FinalTerms.mul(&ctx, x, try FinalTerms.bsl(&ctx, FinalTerms.int(&ctx, 1), k))));
    const sh7 = FinalTerms.int(&ctx, 7);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bsr(&ctx, nx, sh7), try FinalTerms.bnot(&ctx, try FinalTerms.bsr(&ctx, x, sh7))));
    // saturation: a shift count so large only the sign survives.
    const huge = try FinalTerms.intFromI128(&ctx, 1 << 100);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bsr(&ctx, x, huge), zero));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, try FinalTerms.bsr(&ctx, nx, huge), minus_one));
    try std.testing.expectError(error.Badarith, FinalTerms.bsl(&ctx, x, huge)); // the cap
}

test "Doctrine guard: same value at different heap addresses is EQUAL" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const one = FinalTerms.int(&ctx, 1);
    const n = FinalTerms.nil(&ctx);
    const l1 = try FinalTerms.cons(&ctx, one, n);
    const l2 = try FinalTerms.cons(&ctx, one, n);
    try std.testing.expect(l1 != l2); // different raw words
    try std.testing.expect(FinalTerms.eql(&ctx, l1, l2)); // same value

    const big1 = try FinalTerms.intFromI128(&ctx, 1 << 100);
    const big2 = try FinalTerms.intFromI128(&ctx, 1 << 100);
    try std.testing.expect(big1 != big2);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, big1, big2));

    const bin1 = try FinalTerms.binary(&ctx, "hello");
    const bin2 = try FinalTerms.binary(&ctx, "hello");
    try std.testing.expect(bin1 != bin2);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, bin1, bin2));
}

test "Spot checks: Erlang kind order on the word encoding (M4 kinds)" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const i = FinalTerms.int(&ctx, 999);
    const bigneg = try FinalTerms.intFromI128(&ctx, -(1 << 100));
    const f = FinalTerms.float(&ctx, 2.5);
    const at = FinalTerms.atom(&ctx, try atoms.intern("x"));
    const tup = try FinalTerms.tuple(&ctx, &.{i});
    const m = try FinalTerms.mapNew(&ctx, &.{i}, &.{at});
    const n = FinalTerms.nil(&ctx);
    const l = try FinalTerms.cons(&ctx, i, n);
    const bin = try FinalTerms.binary(&ctx, "b");

    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, bigneg, i)); // -2^100 < 999
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, f, i)); // 2.5 < 999
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, i, at)); // number < atom
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, at, tup)); // atom < tuple
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, tup, m)); // tuple < map
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, m, n)); // map < nil
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, n, l)); // nil < cons
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, l, bin)); // list < binary
}

test "Two orders: int/float ties — 1 == 1.0 arithmetically, 1 < 1.0 exactly" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const one_i = FinalTerms.int(&ctx, 1);
    const one_f = FinalTerms.float(&ctx, 1.0);
    try std.testing.expectEqual(Order.eq, FinalTerms.compare(&ctx, one_i, one_f));
    try std.testing.expectEqual(Order.lt, FinalTerms.compareExact(&ctx, one_i, one_f));
    try std.testing.expect(FinalTerms.eql(&ctx, one_i, one_f));
    try std.testing.expect(!FinalTerms.eqlExact(&ctx, one_i, one_f));

    // -0.0 and 0.0: arithmetically equal, exactly ordered (neg first)
    const nz = FinalTerms.float(&ctx, -0.0);
    const pz = FinalTerms.float(&ctx, 0.0);
    try std.testing.expectEqual(Order.eq, FinalTerms.compare(&ctx, nz, pz));
    try std.testing.expectEqual(Order.lt, FinalTerms.compareExact(&ctx, nz, pz));

    // 2^53 precision edges — comparison is exact, not via f64 rounding
    const f53 = FinalTerms.float(&ctx, 0x1p53);
    const int53 = try FinalTerms.intFromI128(&ctx, 1 << 53);
    const int53p1 = try FinalTerms.intFromI128(&ctx, (1 << 53) + 1);
    try std.testing.expectEqual(Order.eq, FinalTerms.compare(&ctx, int53, f53));
    try std.testing.expectEqual(Order.gt, FinalTerms.compare(&ctx, int53p1, f53));
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, f53, int53p1));

    // big negative vs float: sign and magnitude decide exactly
    const bneg = try FinalTerms.intFromI128(&ctx, -(1 << 90));
    const fneg = FinalTerms.float(&ctx, -1.0e12);
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, bneg, fneg));
}

// ============================================================================
// E3.1: bitstring term kind (LA-3) — Produces-interface + term-kind laws
// ============================================================================

test "E3.1 Produces: FinalTerms.bitstring/repIsBitstring/bitstringBits round-trip" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const b = try FinalTerms.bitstring(&ctx, &.{ 0xAB, 0b1010_0000 }, 11); // 8 + 3 bits
    try std.testing.expect(FinalTerms.repIsBitstring(&ctx, b));
    try std.testing.expect(!FinalTerms.repIsBinary(&ctx, b));
    const bits = FinalTerms.bitstringBits(&ctx, b);
    try std.testing.expectEqual(@as(usize, 11), bits.bit_len);
    try std.testing.expect(bsa.isCanonical(bits));
    try std.testing.expectEqual(@as(u8, 0xAB), bits.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0b1010_0000), bits.bytes[1]); // already-clean padding
}

test "E3.1 CANONICAL-PADDING INVARIANT (term level): junk padding never survives construction" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    // same logical 5 bits (10110), different junk in the incoming low 3 bits
    const clean = try FinalTerms.bitstring(&ctx, &.{0b1011_0000}, 5);
    const junky = try FinalTerms.bitstring(&ctx, &.{0b1011_0111}, 5);

    // MUTANT 2 (canonical-padding invariant dropped) is killed by this pair:
    // without masking, `junky`'s stored byte differs from `clean`'s, and
    // BOTH the equality and the hash below would then disagree.
    try std.testing.expect(FinalTerms.eqlExact(&ctx, clean, junky));
    try std.testing.expectEqual(FinalTerms.hashTerm(&ctx, clean), FinalTerms.hashTerm(&ctx, junky));
    try std.testing.expect(bsa.isCanonical(FinalTerms.bitstringBits(&ctx, clean)));
    try std.testing.expect(bsa.isCanonical(FinalTerms.bitstringBits(&ctx, junky)));
}

test "E3.1 ORDER FAMILY: an aligned bitstring orders (and eql/hashes) exactly like its binary twin" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const bin = try FinalTerms.binary(&ctx, &.{ 1, 2, 3 });
    const bs = try FinalTerms.bitstring(&ctx, &.{ 1, 2, 3 }, 24); // aligned: bit_len == 3*8
    try std.testing.expectEqual(Order.eq, FinalTerms.compare(&ctx, bin, bs));
    try std.testing.expectEqual(Order.eq, FinalTerms.compareExact(&ctx, bin, bs));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, bin, bs));
    try std.testing.expectEqual(FinalTerms.hashTerm(&ctx, bin), FinalTerms.hashTerm(&ctx, bs));

    // a genuinely sub-byte bitstring still ranks WITH the binary family
    // (same rank), strictly ordered against it (not cross-family unequal
    // by construction — the shared bit-vector view decides).
    const tail = try FinalTerms.bitstring(&ctx, &.{ 1, 2, 0b0000_0000 }, 20); // shorter than bin
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, tail, bin));
    try std.testing.expectEqual(Order.gt, FinalTerms.compare(&ctx, bin, tail));

    // and it still sorts WITH (never before/after) the whole binary family
    // relative to every OTHER kind rank (list < binary-family < ... none above)
    const l = FinalTerms.nil(&ctx);
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, l, bs));
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, l, tail));
}

test "LAW gap-cowboy-serve binBytes(byte-aligned BITSTRING): the WHOLE-BYTE read of a byte-aligned bitstring returns EXACTLY ceil(bit_len/8) bytes — never an over-read of base+1-as-byte-length (DIVERGENCE 646). A `<< _, Rest/bits >>` / `Rest/binary` TAIL bind produces a byte-aligned SUBTAG_BITSTRING; its len word holds BITS, so the flat-binary reader over-read 4x into adjacent heap (binary_to_list gave 32 garbage bytes where byte_size gave 4; binary_to_integer badarg'd/panicked)." {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    // A byte-aligned bitstring "8099" (32 bits) — exactly what cowboy's
    // cow_http_hd:parse_host binds as the port sub-binary from `<< $:, Port/bits >>`.
    const bs = try FinalTerms.bitstring(&ctx, &.{ 56, 48, 57, 57 }, 32);
    // (1) repIsBinary accepts it (byte-aligned), and byte_size sees 4.
    try std.testing.expect(FinalTerms.repIsBinary(&ctx, bs));
    // (2) THE FIX: binBytes returns EXACTLY the 4 payload bytes — not 32
    //     (the old flat read: len=words[base+1]=bit_len=32 → 32 bytes over-read).
    try std.testing.expectEqualSlices(u8, &.{ 56, 48, 57, 57 }, FinalTerms.binBytes(&ctx, bs));
    // (3) it denotes EQ to its flat-binary twin under the whole-byte read.
    const twin = try FinalTerms.binary(&ctx, &.{ 56, 48, 57, 57 });
    try std.testing.expectEqualSlices(u8, FinalTerms.binBytes(&ctx, twin), FinalTerms.binBytes(&ctx, bs));
    // (4) a LARGER aligned bitstring reads exactly its own bytes (no bleed past len).
    const big = try FinalTerms.bitstring(&ctx, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, 80);
    try std.testing.expectEqual(@as(usize, 10), FinalTerms.binBytes(&ctx, big).len);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, FinalTerms.binBytes(&ctx, big));
}

test "E3.1 ENCODING HOMOMORPHISM: InitialTerms and FinalTerms bitstring denote identically (seeded)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(0x8171);
    const random = prng.random();

    for (0..80) |iter| {
        var ic = InitialTerms.Ctx.init(gpa, &atoms);
        defer ic.deinit();
        var fc = FinalTerms.Ctx.init(gpa, &atoms);
        defer fc.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();

        var buf: [12]u8 = undefined;
        const nbytes = random.uintLessThan(usize, buf.len + 1);
        for (buf[0..nbytes]) |*b| b.* = random.int(u8);
        const bit_len = if (nbytes == 0) 0 else random.uintLessThan(usize, nbytes * 8 + 1);

        const it = try InitialTerms.bitstring(&ic, buf[0..nbytes], bit_len);
        const ft = try FinalTerms.bitstring(&fc, buf[0..nbytes], bit_len);

        try expectLaw(spec.eqlExact(
            try InitialTerms.denote(&ic, sa, it),
            try FinalTerms.denote(&fc, sa, ft),
        ), "E3.1: Initial/Final bitstring denotations agree", LawConfig{ .seed = 0x8171 }, iter);
        try expectLaw(InitialTerms.hashTerm(&ic, it) == FinalTerms.hashTerm(&fc, ft), "E3.1: Initial/Final bitstring hashes agree", LawConfig{ .seed = 0x8171 }, iter);
        try expectLaw(InitialTerms.repIsBitstring(&ic, it) and FinalTerms.repIsBitstring(&fc, ft), "E3.1: both encodings report .bitstring", LawConfig{ .seed = 0x8171 }, iter);
        try expectLaw(FinalTerms.kindOf(&fc, ft) == .binary, "E3.1: kindOf buckets bitstring WITH binary", LawConfig{ .seed = 0x8171 }, iter);
    }
}

test "E3.1 GC survival: a heap holding a non-byte-aligned bitstring copies denote-preserving" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var src = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer src.deinit();
    var dst = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer dst.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const sa = arena.allocator();

    const w = try FinalTerms.bitstring(&src, &.{ 0xFF, 0xFF, 0b1110_0000 }, 19);
    const tup = try FinalTerms.tuple(&src, &.{ w, w }); // shared bitstring, exercises sharing too
    const before = try FinalTerms.denote(&src, sa, tup);

    const copied = try FinalTerms.gcCopy(&dst, &src, tup);
    const after = try FinalTerms.denote(&dst, sa, copied);
    try std.testing.expect(spec.eqlExact(before, after));
    try std.testing.expect(bsa.isCanonical(FinalTerms.bitstringBits(&dst, FinalTerms.tupleElem(&dst, copied, 0))));
}

// ============================================================================
// E3.5: pid / reference / port
// ============================================================================

test "E3.5 Produces: FinalTerms.pid/ref/port + repIsPid/repIsRef/repIsPort round-trip" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const p = try FinalTerms.pid(&ctx, 42, 7);
    try std.testing.expect(FinalTerms.repIsPid(&ctx, p));
    try std.testing.expect(!FinalTerms.repIsRef(&ctx, p));
    try std.testing.expect(!FinalTerms.repIsPort(&ctx, p));
    try std.testing.expectEqual(@as(u64, 42), FinalTerms.pidNumber(&ctx, p));
    try std.testing.expectEqual(@as(u64, 7), FinalTerms.pidSerial(&ctx, p));

    const r = try FinalTerms.ref(&ctx, .{ 11, 22, 33 });
    try std.testing.expect(FinalTerms.repIsRef(&ctx, r));
    try std.testing.expect(!FinalTerms.repIsPid(&ctx, r));
    try std.testing.expect(!FinalTerms.repIsPort(&ctx, r));
    try std.testing.expectEqual([3]u32{ 11, 22, 33 }, FinalTerms.refWords(&ctx, r));

    const port_t = try FinalTerms.port(&ctx, 99);
    try std.testing.expect(FinalTerms.repIsPort(&ctx, port_t));
    try std.testing.expect(!FinalTerms.repIsPid(&ctx, port_t));
    try std.testing.expect(!FinalTerms.repIsRef(&ctx, port_t));
    try std.testing.expectEqual(@as(u64, 99), FinalTerms.portNumber(&ctx, port_t));
}

test "E3.5 InitialTerms Produces mirrors FinalTerms (oracle twin)" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = InitialTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const p = try InitialTerms.pid(&ctx, 42, 7);
    try std.testing.expect(InitialTerms.repIsPid(&ctx, p));
    try std.testing.expectEqual(@as(u64, 42), InitialTerms.pidNumber(&ctx, p));
    try std.testing.expectEqual(@as(u64, 7), InitialTerms.pidSerial(&ctx, p));

    const r = try InitialTerms.ref(&ctx, .{ 11, 22, 33 });
    try std.testing.expect(InitialTerms.repIsRef(&ctx, r));
    try std.testing.expectEqual([3]u32{ 11, 22, 33 }, InitialTerms.refWords(&ctx, r));

    const port_t = try InitialTerms.port(&ctx, 99);
    try std.testing.expect(InitialTerms.repIsPort(&ctx, port_t));
    try std.testing.expectEqual(@as(u64, 99), InitialTerms.portNumber(&ctx, port_t));
}

test "E3.5 REF FRESHNESS: N generated refs are pairwise =/=, each =:= to itself" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var fc = FinalTerms.Ctx.init(gpa, &atoms);
    defer fc.deinit();
    var ic = InitialTerms.Ctx.init(gpa, &atoms);
    defer ic.deinit();

    const n = 64;
    var frefs: [n]FinalTerms.Term = undefined;
    var irefs: [n]InitialTerms.Term = undefined;
    for (0..n) |i| {
        frefs[i] = try FinalTerms.freshRef(&fc);
        irefs[i] = try InitialTerms.freshRef(&ic);
    }
    for (0..n) |i| {
        try std.testing.expect(FinalTerms.eqlExact(&fc, frefs[i], frefs[i]));
        try std.testing.expect(InitialTerms.eqlExact(&ic, irefs[i], irefs[i]));
        for (i + 1..n) |j| {
            try std.testing.expect(!FinalTerms.eqlExact(&fc, frefs[i], frefs[j]));
            try std.testing.expect(!InitialTerms.eqlExact(&ic, irefs[i], irefs[j]));
        }
    }
}

test "E3.5 TOTAL-ORDER PIN: number < atom < reference < fun < port < pid < tuple < map < nil/list < binary" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const num = FinalTerms.int(&ctx, 1);
    const at = FinalTerms.atom(&ctx, try atoms.intern("z")); // lexically LAST atom, still ranks above reference
    const r = try FinalTerms.freshRef(&ctx);
    const f = try FinalTerms.makeFun(&ctx, 0, 0, &.{});
    const pt = try FinalTerms.port(&ctx, 0);
    const p = try FinalTerms.pid(&ctx, 0, 0);
    const tup = try FinalTerms.tuple(&ctx, &.{});
    const m = try FinalTerms.mapNew(&ctx, &.{}, &.{});
    const l = FinalTerms.nil(&ctx);
    const b = try FinalTerms.binary(&ctx, &.{});

    const chain = [_]FinalTerms.Term{ num, at, r, f, pt, p, tup, m, l, b };
    for (chain[0 .. chain.len - 1], chain[1..]) |lo, hi| {
        try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, lo, hi));
        try std.testing.expectEqual(Order.gt, FinalTerms.compare(&ctx, hi, lo));
    }
}

test "E3.5 PID ORDER: number compares before serial (MUTANT 1's exact target)" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    // number differs, serial would disagree if compared first: 1.99 vs 2.0
    const a = try FinalTerms.pid(&ctx, 1, 99);
    const b = try FinalTerms.pid(&ctx, 2, 0);
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, a, b));
    try std.testing.expectEqual(Order.gt, FinalTerms.compare(&ctx, b, a));
    // same number: serial breaks the tie
    const c = try FinalTerms.pid(&ctx, 5, 1);
    const d = try FinalTerms.pid(&ctx, 5, 2);
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, c, d));
}

test "MUTANT 1 RED-demo (documented, planted+run+reverted — see MUTATION_LOG.md E3.5 mutant 1)" {
    // Plant: swap `cmpPid`'s field comparison order (serial first, number
    // second). RED, as run against "E3.5 PID ORDER: number compares before
    // serial": `expected .lt, found .gt` at the `pid(1,99)` vs `pid(2,0)`
    // assertion (99 > 0 outranks 1 < 2 under the mutant). Reverted; the
    // suite is green again with the field order restored above.
}

test "E3.5 ENCODING HOMOMORPHISM: InitialTerms and FinalTerms pid/ref/port denote identically (seeded)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(0xE305);
    const random = prng.random();

    for (0..80) |iter| {
        var ic = InitialTerms.Ctx.init(gpa, &atoms);
        defer ic.deinit();
        var fc = FinalTerms.Ctx.init(gpa, &atoms);
        defer fc.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();

        const number = random.int(u32);
        const serial = random.int(u32);
        const ip = try InitialTerms.pid(&ic, number, serial);
        const fp = try FinalTerms.pid(&fc, number, serial);
        try expectLaw(spec.eqlExact(
            try InitialTerms.denote(&ic, sa, ip),
            try FinalTerms.denote(&fc, sa, fp),
        ), "E3.5: Initial/Final pid denotations agree", LawConfig{ .seed = 0xE305 }, iter);
        try expectLaw(InitialTerms.hashTerm(&ic, ip) == FinalTerms.hashTerm(&fc, fp), "E3.5: Initial/Final pid hashes agree", LawConfig{ .seed = 0xE305 }, iter);

        const words: [3]u32 = .{ random.int(u32), random.int(u32), random.int(u32) };
        const ir = try InitialTerms.ref(&ic, words);
        const fr = try FinalTerms.ref(&fc, words);
        try expectLaw(spec.eqlExact(
            try InitialTerms.denote(&ic, sa, ir),
            try FinalTerms.denote(&fc, sa, fr),
        ), "E3.5: Initial/Final reference denotations agree", LawConfig{ .seed = 0xE305 }, iter);

        const n = random.int(u32);
        const iport = try InitialTerms.port(&ic, n);
        const fport = try FinalTerms.port(&fc, n);
        try expectLaw(spec.eqlExact(
            try InitialTerms.denote(&ic, sa, iport),
            try FinalTerms.denote(&fc, sa, fport),
        ), "E3.5: Initial/Final port denotations agree", LawConfig{ .seed = 0xE305 }, iter);
    }
}

test "E3.5 GC survival: pid/reference/port copy denote-preserving, sharing exercised" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var src = FinalTerms.Ctx.init(gpa, &atoms);
    defer src.deinit();
    var dst = FinalTerms.Ctx.init(gpa, &atoms);
    defer dst.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    const p = try FinalTerms.pid(&src, 3, 1);
    const r = try FinalTerms.freshRef(&src);
    const pt = try FinalTerms.port(&src, 9);
    const tup = try FinalTerms.tuple(&src, &.{ p, r, pt, p }); // p shared twice
    const before = try FinalTerms.denote(&src, sa, tup);

    const copied = try FinalTerms.gcCopy(&dst, &src, tup);
    const after = try FinalTerms.denote(&dst, sa, copied);
    try std.testing.expect(spec.eqlExact(before, after));
    try std.testing.expect(FinalTerms.repIsPid(&dst, FinalTerms.tupleElem(&dst, copied, 0)));
    try std.testing.expect(FinalTerms.repIsRef(&dst, FinalTerms.tupleElem(&dst, copied, 1)));
    try std.testing.expect(FinalTerms.repIsPort(&dst, FinalTerms.tupleElem(&dst, copied, 2)));
}

test "LAW E5.7 FOREIGN-NODE WIDENING: node/creation participate in identity, order, equal-hash; local defaults preserve the pinned local behavior; GC-survives" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    const other = try atoms.intern("other@host"); // "o" > "n" ⇒ foreign > local

    // (1) A local pid built by the plain constructor carries local_node_name /
    // creation 0 — the pre-E5.7 print/order/hash behavior is unchanged.
    const lp = try FinalTerms.pid(&ctx, 3, 1);
    try std.testing.expectEqualStrings(local_node_name, FinalTerms.pidNodeName(&ctx, lp));
    try std.testing.expectEqual(@as(u32, 0), FinalTerms.pidCreation(&ctx, lp));

    // (2) A pid differing ONLY in node is a DISTINCT term, ordered by node.
    const fp = try FinalTerms.pidExt(&ctx, 3, 1, other, 0);
    try std.testing.expect(!FinalTerms.eqlExact(&ctx, lp, fp));
    try std.testing.expectEqual(Order.lt, FinalTerms.compareExact(&ctx, lp, fp)); // local < foreign
    // and ONLY in creation is likewise distinct, ordered by creation.
    const fp_c = try FinalTerms.pidExt(&ctx, 3, 1, other, 5);
    try std.testing.expect(!FinalTerms.eqlExact(&ctx, fp, fp_c));
    try std.testing.expectEqual(Order.lt, FinalTerms.compareExact(&ctx, fp, fp_c));

    // (3) equal-hash coherence: two independently-built EXACT-equal foreign
    // pids hash equal; a node/creation difference need not (but identity must).
    const fp2 = try FinalTerms.pidExt(&ctx, 3, 1, other, 0);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, fp, fp2));
    try std.testing.expectEqual(FinalTerms.hashTerm(&ctx, fp), FinalTerms.hashTerm(&ctx, fp2));

    // (4) Initial/Final denote agree on a foreign identity (homomorphism).
    var ic = InitialTerms.Ctx.init(gpa, &atoms);
    defer ic.deinit();
    const ifp = try InitialTerms.pidExt(&ic, 3, 1, other, 0);
    try std.testing.expect(spec.eqlExact(
        try InitialTerms.denote(&ic, sa, ifp),
        try FinalTerms.denote(&ctx, sa, fp),
    ));

    // (5) GC survival: node atom idx + creation copy verbatim (shared table).
    const foreign_ref = try FinalTerms.refExt(&ctx, .{ 1, 2, 3 }, other, 9);
    const foreign_port = try FinalTerms.portExt(&ctx, 5, other, 7);
    const tup = try FinalTerms.tuple(&ctx, &.{ fp, foreign_ref, foreign_port });
    var dst = FinalTerms.Ctx.init(gpa, &atoms);
    defer dst.deinit();
    const copied = try FinalTerms.gcCopy(&dst, &ctx, tup);
    try std.testing.expect(spec.eqlExact(
        try FinalTerms.denote(&ctx, sa, tup),
        try FinalTerms.denote(&dst, sa, copied),
    ));
    try std.testing.expectEqualStrings("other@host", FinalTerms.pidNodeName(&dst, FinalTerms.tupleElem(&dst, copied, 0)));
    try std.testing.expectEqual(@as(u32, 9), FinalTerms.refCreation(&dst, FinalTerms.tupleElem(&dst, copied, 1)));
}

// ---- E3.14: native-record term-kind laws --------------------------------

test "E3.14 Produces: FinalTerms.nativeRecord + repIsNativeRecord + observers round-trip" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const m = FinalTerms.atomTerm(try atoms.intern("mod"));
    const nm = FinalTerms.atomTerm(try atoms.intern("point"));
    const kx = FinalTerms.atomTerm(try atoms.intern("x"));
    const ky = FinalTerms.atomTerm(try atoms.intern("y"));
    const r = try FinalTerms.nativeRecord(&ctx, m, nm, true, &.{ kx, ky }, &.{ FinalTerms.int(&ctx, 1), FinalTerms.int(&ctx, 2) });

    try std.testing.expect(FinalTerms.repIsNativeRecord(&ctx, r));
    try std.testing.expect(!FinalTerms.repIsNativeRecord(&ctx, try FinalTerms.tuple(&ctx, &.{ kx, ky }))); // NOT a tuple
    try std.testing.expectEqual(FinalTerms.Kind.native_record, FinalTerms.kindOf(&ctx, r));
    try std.testing.expectEqual(m, FinalTerms.nrModule(&ctx, r));
    try std.testing.expectEqual(nm, FinalTerms.nrName(&ctx, r));
    try std.testing.expect(FinalTerms.nrIsExported(&ctx, r));
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.nrFieldCount(&ctx, r));
    try std.testing.expectEqual(kx, FinalTerms.nrKeyAt(&ctx, r, 0));
    // lookup by exact key equality
    try std.testing.expect(FinalTerms.compare(&ctx, FinalTerms.nrLookup(&ctx, r, ky).?, FinalTerms.int(&ctx, 2)) == .eq);
    try std.testing.expect(FinalTerms.nrLookup(&ctx, r, FinalTerms.atomTerm(try atoms.intern("z"))) == null);
}

test "E3.14 TOTAL-ORDER PIN: tuple < native_record < map; refl/antisym over a mix" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const at = FinalTerms.atomTerm(try atoms.intern("a"));
    const p = try FinalTerms.pid(&ctx, 0, 0);
    const tup = try FinalTerms.tuple(&ctx, &.{});
    const rec = try FinalTerms.nativeRecord(&ctx, at, at, true, &.{}, &.{});
    const m = try FinalTerms.mapNew(&ctx, &.{}, &.{});
    const l = FinalTerms.nil(&ctx);

    // full kind chain including native_record in its pin position
    const chain = [_]FinalTerms.Term{ p, tup, rec, m, l };
    for (chain[0 .. chain.len - 1], chain[1..]) |lo, hi| {
        try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, lo, hi));
        try std.testing.expectEqual(Order.gt, FinalTerms.compare(&ctx, hi, lo));
    }
    // reflexivity + =:= coherence
    try std.testing.expectEqual(Order.eq, FinalTerms.compareExact(&ctx, rec, rec));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, rec, rec));
}

// cp-term-order: WITHIN-map ordering (cmpMap). The E3.5/E3.14 pins place a map in
// the type-rank order but never exercise the map-vs-map dispatch, which BEAM defines
// as a lexicographic fold: SIZE first (a smaller map is unconditionally less), then
// KEYS compared in EXACT mode (so a `1` key and a `1.0` key are DISTINCT regardless
// of the ambient compare mode — the load-bearing `.exact` in cmpMap), then VALUES
// compared in the ambient mode. term_algebra has the widest fan-in (60), so a wrong
// map order propagates into every map-keyed ETS/compare path. No bug — dark-arm cover.
test "LAW cp-term-order: BEAM map ordering — size dominates, then keys (EXACT), then values (by mode)" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();
    const ka = FinalTerms.atomTerm(try atoms.intern("a"));
    const kb = FinalTerms.atomTerm(try atoms.intern("b"));
    const kz = FinalTerms.atomTerm(try atoms.intern("z"));
    const v = FinalTerms.atomTerm(try atoms.intern("v"));
    const iv0 = FinalTerms.int(&ctx, 0);
    const iv1 = FinalTerms.int(&ctx, 1);
    const iv2 = FinalTerms.int(&ctx, 2);
    const fv1 = FinalTerms.float(&ctx, 1.0);

    // (1) SIZE dominates: |{}|<|{a}|<|{a,b}| regardless of contents — a 1-key map with
    // a huge key/value is STILL < any 2-key map.
    const m0 = try FinalTerms.mapNew(&ctx, &.{}, &.{});
    const m1 = try FinalTerms.mapNew(&ctx, &.{ka}, &.{iv0});
    const m1z = try FinalTerms.mapNew(&ctx, &.{kz}, &.{FinalTerms.int(&ctx, 999)});
    const m2 = try FinalTerms.mapNew(&ctx, &.{ ka, kb }, &.{ iv0, iv0 });
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, m0, m1));
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, m1, m2));
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, m1z, m2));
    try std.testing.expectEqual(Order.gt, FinalTerms.compare(&ctx, m2, m1z));

    // (2) same size: KEYS dominate VALUES — #{a=>2} < #{b=>1} (key a<b beats value 2>1).
    const ma2 = try FinalTerms.mapNew(&ctx, &.{ka}, &.{iv2});
    const mb1 = try FinalTerms.mapNew(&ctx, &.{kb}, &.{iv1});
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, ma2, mb1));
    try std.testing.expectEqual(Order.gt, FinalTerms.compare(&ctx, mb1, ma2));

    // (3) same size + same keys: VALUES decide — #{a=>1} < #{a=>2}.
    const ma1 = try FinalTerms.mapNew(&ctx, &.{ka}, &.{iv1});
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, ma1, ma2));

    // (4) KEYS are compared EXACT even in the ARITH compare: #{1=>v} vs #{1.0=>v}.
    // exact term order puts int 1 < float 1.0, so the int-keyed map < the float-keyed
    // map in BOTH compare (arith) and compareExact — the load-bearing `.exact` on keys.
    const mki = try FinalTerms.mapNew(&ctx, &.{iv1}, &.{v});
    const mkf = try FinalTerms.mapNew(&ctx, &.{fv1}, &.{v});
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, mki, mkf));
    try std.testing.expectEqual(Order.lt, FinalTerms.compareExact(&ctx, mki, mkf));

    // (5) VALUES follow the compare MODE: #{a=>1} vs #{a=>1.0} — same key a; values
    // 1 and 1.0 are ARITH-equal but EXACT-distinct, so arith compare ⇒ eq, exact ⇒ lt.
    const maf = try FinalTerms.mapNew(&ctx, &.{ka}, &.{fv1});
    try std.testing.expectEqual(Order.eq, FinalTerms.compare(&ctx, ma1, maf));
    try std.testing.expectEqual(Order.lt, FinalTerms.compareExact(&ctx, ma1, maf));

    // reflexivity
    try std.testing.expectEqual(Order.eq, FinalTerms.compareExact(&ctx, m2, m2));
    try std.testing.expect(FinalTerms.eqlExact(&ctx, m2, m2));
}

test "E3.14 cross-record order: module, then name, then exported, then fields" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();
    const ma = FinalTerms.atomTerm(try atoms.intern("a"));
    const mb = FinalTerms.atomTerm(try atoms.intern("b"));
    const kx = FinalTerms.atomTerm(try atoms.intern("x"));

    const ra = try FinalTerms.nativeRecord(&ctx, ma, kx, true, &.{kx}, &.{FinalTerms.int(&ctx, 1)});
    const rb = try FinalTerms.nativeRecord(&ctx, mb, kx, true, &.{kx}, &.{FinalTerms.int(&ctx, 1)});
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, ra, rb)); // module a < b

    // exported false < true (same module/name/fields)
    const re_f = try FinalTerms.nativeRecord(&ctx, ma, kx, false, &.{kx}, &.{FinalTerms.int(&ctx, 1)});
    const re_t = try FinalTerms.nativeRecord(&ctx, ma, kx, true, &.{kx}, &.{FinalTerms.int(&ctx, 1)});
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, re_f, re_t));

    // value order (same shape, differing value)
    const rv1 = try FinalTerms.nativeRecord(&ctx, ma, kx, true, &.{kx}, &.{FinalTerms.int(&ctx, 1)});
    const rv2 = try FinalTerms.nativeRecord(&ctx, ma, kx, true, &.{kx}, &.{FinalTerms.int(&ctx, 2)});
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, rv1, rv2));
}

test "E3.14 EQUAL-HASH: T =:= T' ⇒ hashTerm(T) == hashTerm(T'); Initial/Final agree (seeded)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var prng = std.Random.DefaultPrng.init(0xE314);
    const random = prng.random();

    for (0..80) |iter| {
        var fc = FinalTerms.Ctx.init(gpa, &atoms);
        defer fc.deinit();
        var ic = InitialTerms.Ctx.init(gpa, &atoms);
        defer ic.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const sa = arena.allocator();

        const mod = FinalTerms.atomTerm(try atoms.intern("m"));
        const nm = FinalTerms.atomTerm(try atoms.intern("rec"));
        const exp = random.boolean();
        const n = random.uintLessThan(u8, 4);
        var fk: [4]FinalTerms.Term = undefined;
        var fv: [4]FinalTerms.Term = undefined;
        var iv: [4]InitialTerms.Term = undefined;
        for (0..n) |k| {
            var buf: [4]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "f{d}", .{k}) catch unreachable;
            fk[k] = FinalTerms.atomTerm(try atoms.intern(s));
            const val: i64 = random.int(i32);
            fv[k] = FinalTerms.int(&fc, val);
            iv[k] = InitialTerms.int(&ic, val);
        }
        // two independent constructions with the same denotation
        const r1 = try FinalTerms.nativeRecord(&fc, mod, nm, exp, fk[0..n], fv[0..n]);
        const r2 = try FinalTerms.nativeRecord(&fc, mod, nm, exp, fk[0..n], fv[0..n]);
        try expectLaw(FinalTerms.eqlExact(&fc, r1, r2), "E3.14: equal records are =:=", LawConfig{ .seed = 0xE314 }, iter);
        try expectLaw(FinalTerms.hashTerm(&fc, r1) == FinalTerms.hashTerm(&fc, r2), "E3.14: =:= ⇒ equal hash", LawConfig{ .seed = 0xE314 }, iter);

        // Initial/Final encoding homomorphism: denote + hash agree
        const im = InitialTerms.atom(&ic, try atoms.intern("m"));
        const inm = InitialTerms.atom(&ic, try atoms.intern("rec"));
        var ik: [4]InitialTerms.Term = undefined;
        for (0..n) |k| {
            var buf: [4]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "f{d}", .{k}) catch unreachable;
            ik[k] = InitialTerms.atom(&ic, try atoms.intern(s));
        }
        const ir = try InitialTerms.nativeRecord(&ic, im, inm, exp, ik[0..n], iv[0..n]);
        try expectLaw(spec.eqlExact(
            try InitialTerms.denote(&ic, sa, ir),
            try FinalTerms.denote(&fc, sa, r1),
        ), "E3.14: Initial/Final native_record denotations agree", LawConfig{ .seed = 0xE314 }, iter);
        try expectLaw(InitialTerms.hashTerm(&ic, ir) == FinalTerms.hashTerm(&fc, r1), "E3.14: Initial/Final native_record hashes agree", LawConfig{ .seed = 0xE314 }, iter);
    }
}

test "E3.14 GC survival: native record copy denote-preserving; value slots relocated" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var src = FinalTerms.Ctx.init(gpa, &atoms);
    defer src.deinit();
    var dst = FinalTerms.Ctx.init(gpa, &atoms);
    defer dst.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const sa = arena.allocator();

    const mod = FinalTerms.atomTerm(try atoms.intern("m"));
    const nm = FinalTerms.atomTerm(try atoms.intern("r"));
    const kx = FinalTerms.atomTerm(try atoms.intern("x"));
    const ky = FinalTerms.atomTerm(try atoms.intern("y"));
    // a boxed value (bignum) forces a real heap relocation, not just immediates
    const bigv = try FinalTerms.intFromI128(&src, 1 << 70);
    const rec = try FinalTerms.nativeRecord(&src, mod, nm, true, &.{ kx, ky }, &.{ FinalTerms.int(&src, 7), bigv });
    const before = try FinalTerms.denote(&src, sa, rec);

    // full sharing-preserving collection into a fresh heap
    var col = FinalTerms.collectInto(&dst, &src);
    var root = rec;
    try col.root(&root);
    FinalTerms.finishInto(&dst, &col);
    const after = try FinalTerms.denote(&dst, sa, root);

    try std.testing.expect(spec.eqlExact(before, after));
    try std.testing.expect(FinalTerms.repIsNativeRecord(&dst, root));
    try std.testing.expect(FinalTerms.compare(&dst, FinalTerms.nrLookup(&dst, root, ky).?, try FinalTerms.intFromI128(&dst, 1 << 70)) == .eq);
}

test "MUTANT E3.14 RED-demos (documented, planted+run+reverted — see MUTATION_LOG.md E3.14)" {
    // Mutant 1: `repIsNativeRecord` returns true for SUBTAG_TUPLE (native
    // record accepts a same-shape tuple). RED against the "Produces" test's
    // `!repIsNativeRecord(tuple)` assertion (distinct-kind law).
    // Mutant 2: `nrValAt` reads `+ 4 + i` (dropping the `+ n` key-block
    // offset → off-by-field-block). RED against the "Produces" lookup
    // assertion (`nrLookup(y) == 2` reads key `x`'s slot instead). Both
    // reverted; the suite is green with the constructors above.
}

// ============================================================================
// E7.1: EXPORT_EXT term kind (fun M:F/A) — dedicated laws pinning the erts
// semantics verified empirically on the OTP host (term_to_binary(fun
// lists:map/2) and the term-order probes). The generic order/hash/GC/denote/
// ETF-round-trip homomorphism laws already exercise export funs MIXED with
// every other kind via genTerm/genWireTerm's new `.export_fun` variant; these
// tests pin the CONCRETE tie-break order + observations.
// ============================================================================

test "E7.1 Produces: makeExportFun/repIsExportFun + observers round-trip (both encodings)" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const m = FinalTerms.atom(&ctx, try atoms.intern("lists"));
    const f = FinalTerms.atom(&ctx, try atoms.intern("map"));
    const ef = try FinalTerms.makeExportFun(&ctx, m, f, 2);
    try std.testing.expect(FinalTerms.repIsExportFun(&ctx, ef));
    try std.testing.expect(!FinalTerms.repIsFun(&ctx, ef)); // distinct from a local fun
    try std.testing.expectEqualStrings("lists", FinalTerms.exportFunModuleName(&ctx, ef));
    try std.testing.expectEqualStrings("map", FinalTerms.exportFunFuncName(&ctx, ef));
    try std.testing.expectEqual(@as(u8, 2), FinalTerms.exportFunArity(&ctx, ef));
    try std.testing.expectEqual(FinalTerms.Kind.fun_, FinalTerms.kindOf(&ctx, ef)); // is_function/1 holds

    // oracle twin
    var octx = InitialTerms.Ctx.init(std.testing.allocator, &atoms);
    defer octx.deinit();
    const om = InitialTerms.atom(&octx, try atoms.intern("lists"));
    const of = InitialTerms.atom(&octx, try atoms.intern("map"));
    const oef = try InitialTerms.makeExportFun(&octx, om, of, 2);
    try std.testing.expect(InitialTerms.repIsExportFun(&octx, oef));
    try std.testing.expectEqualStrings("lists", InitialTerms.exportFunModuleName(&octx, oef));
    try std.testing.expectEqual(@as(u8, 2), InitialTerms.exportFunArity(&octx, oef));

    // denote agreement (encoding homomorphism, single point)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const dv = try FinalTerms.denote(&ctx, arena.allocator(), ef);
    try std.testing.expect(spec.eqlExact(dv, oef));
}

test "E7.1 TOTAL-ORDER PIN: local fun < export fun; export funs by (module,function,arity); export in the fun band" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(std.testing.allocator, &atoms);
    defer ctx.deinit();

    const A = FinalTerms.atom(&ctx, try atoms.intern("erlang")); // 'e'
    const L = FinalTerms.atom(&ctx, try atoms.intern("lists")); //  'l'
    const abs_ = FinalTerms.atom(&ctx, try atoms.intern("abs"));
    const foldl = FinalTerms.atom(&ctx, try atoms.intern("foldl")); // 'f'
    const map_ = FinalTerms.atom(&ctx, try atoms.intern("map")); //    'm'

    // module-first: erlang:abs/1 < lists:map/2 (host: e<l)
    const e_erl_abs = try FinalTerms.makeExportFun(&ctx, A, abs_, 1);
    const e_lists_map2 = try FinalTerms.makeExportFun(&ctx, L, map_, 2);
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, e_erl_abs, e_lists_map2));
    // function-second: lists:foldl/3 < lists:map/2 (host: f<m)
    const e_lists_foldl3 = try FinalTerms.makeExportFun(&ctx, L, foldl, 3);
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, e_lists_foldl3, e_lists_map2));
    // arity-third: lists:map/2 < lists:map/3
    const e_lists_map3 = try FinalTerms.makeExportFun(&ctx, L, map_, 3);
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, e_lists_map2, e_lists_map3));

    // local fun < EVERY export fun, regardless of the local fun's label
    // (host: "locals are ordered before externals").
    const local_hi = try FinalTerms.makeFun(&ctx, 999999, 9, &.{});
    try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, local_hi, e_erl_abs));
    try std.testing.expectEqual(Order.gt, FinalTerms.compare(&ctx, e_erl_abs, local_hi));

    // fun band placement: number < atom < reference < LOCAL fun < EXPORT fun
    //                     < port < pid < tuple.
    const num = FinalTerms.int(&ctx, 1);
    const at = FinalTerms.atom(&ctx, try atoms.intern("zzz"));
    const r = try FinalTerms.freshRef(&ctx);
    const pt = try FinalTerms.port(&ctx, 0);
    const p = try FinalTerms.pid(&ctx, 0, 0);
    const tup = try FinalTerms.tuple(&ctx, &.{});
    const chain = [_]FinalTerms.Term{ num, at, r, local_hi, e_erl_abs, pt, p, tup };
    for (chain[0 .. chain.len - 1], chain[1..]) |lo, hi| {
        try std.testing.expectEqual(Order.lt, FinalTerms.compare(&ctx, lo, hi));
        try std.testing.expectEqual(Order.gt, FinalTerms.compare(&ctx, hi, lo));
    }

    // reflexive equality + equal-hash (a copy compares eq and hashes equal)
    const e_copy = try FinalTerms.makeExportFun(&ctx, L, map_, 2);
    try std.testing.expectEqual(Order.eq, FinalTerms.compareExact(&ctx, e_lists_map2, e_copy));
    try std.testing.expectEqual(FinalTerms.hashTerm(&ctx, e_lists_map2), FinalTerms.hashTerm(&ctx, e_copy));
    // a different arity is =/= and (with overwhelming probability) hashes apart
    try std.testing.expect(FinalTerms.compareExact(&ctx, e_lists_map2, e_lists_map3) != .eq);
}

test "MUTANT E7.1 RED-demos (documented, planted+run+reverted — see MUTATION_LOG.md E7.1)" {
    // Mutant 1: EXPORT_EXT decode swaps Function and Module (etf.zig T_EXPORT
    // builds makeExportFun(function, module, arity)). RED against etf.zig's
    // "E7.1 ETF byte-exact + round-trip" (decoded module/function transposed →
    // print `fun map:lists/2`, bytes mismatch).
    // Mutant 2: `call_fun` on an export fun uses funLabel (skips the runtime
    // code table) instead of fullDispatch. RED against instr_algebra's "E7.1
    // call homomorphism" (jumps to a garbage label / badfun instead of
    // dispatching M:F/A). Both reverted; the suite is green above.
}

test "LAW e49-binary-refc SUB-BINARY: binary:part is zero-copy (no heap growth for the window), denotes/eql/hashes as its byte slice, SURVIVES a GC with the window intact (base relocated + shared), collapses nested windows, and cross-heap gcCopy FLATTENS it" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const base = try FinalTerms.binary(&ctx, "hello world");
    const words_after_base = ctx.words.items.len;

    // ZERO-COPY: a 5-byte window costs only the 4-word sub-binary header — NOT
    // the 5 payload bytes re-materialized (a full binary would add ceil(5/8)+2).
    const sub = try FinalTerms.binPart(&ctx, base, 6, 5); // "world"
    try std.testing.expect(FinalTerms.repIsSubBin(&ctx, sub));
    try std.testing.expectEqual(@as(usize, 4), ctx.words.items.len - words_after_base); // exactly the window header
    // DENOTATION: it reads, is_binary-tests, and eql/hashes as its byte slice.
    try std.testing.expectEqualStrings("world", FinalTerms.binBytes(&ctx, sub));
    try std.testing.expect(FinalTerms.repIsBinary(&ctx, sub));
    const flat = try FinalTerms.binary(&ctx, "world");
    try std.testing.expect(FinalTerms.eqlExact(&ctx, sub, flat)); // window == flat binary
    try std.testing.expectEqual(FinalTerms.hashTerm(&ctx, flat), FinalTerms.hashTerm(&ctx, sub));
    // NESTED windows COLLAPSE (one hop from a real binary — no chains).
    const sub2 = try FinalTerms.binPart(&ctx, sub, 1, 3); // "orl"
    try std.testing.expect(FinalTerms.repIsSubBin(&ctx, sub2));
    try std.testing.expectEqualStrings("orl", FinalTerms.binBytes(&ctx, sub2));

    // GC SURVIVAL: root the window + garbage above, collect — the window is
    // intact (base relocated & shared) and still denotes "world".
    var sroot = sub;
    var k: usize = 0;
    while (k < 500) : (k += 1) _ = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, @intCast(k)), FinalTerms.int(&ctx, 1) });
    var c = FinalTerms.collectInPlace(&ctx, 0);
    try c.root(&sroot);
    _ = try FinalTerms.finishInPlace(&ctx, &c);
    try std.testing.expect(FinalTerms.repIsSubBin(&ctx, sroot)); // still a window (sharing preserved)
    try std.testing.expectEqualStrings("world", FinalTerms.binBytes(&ctx, sroot));

    // CROSS-HEAP gcCopy FLATTENS (erts small-bin materialize) — denotation exact.
    var ctx2 = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx2.deinit();
    const copied = try FinalTerms.gcCopy(&ctx2, &ctx, sroot);
    try std.testing.expect(!FinalTerms.repIsSubBin(&ctx2, copied)); // FLAT in the new heap
    try std.testing.expectEqualStrings("world", FinalTerms.binBytes(&ctx2, copied));
}

test "LAW e51-t2 procbin-refc SHARE-ON-SEND: a refcounted binary reads/denotes/eql/hashes as its bytes; cross-heap gcCopy SHARES the payload (pointer identity, not a byte copy); shares across in-place GC; leak- and double-free-free under the testing allocator" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const payload = "the quick brown fox jumps over the lazy dog — refcounted off-heap!";

    var sender = FinalTerms.Ctx.init(gpa, &atoms);
    defer sender.deinit(); // (declared first ⇒ deinits LAST — the final decref → free)
    var receiver = FinalTerms.Ctx.init(gpa, &atoms);
    defer receiver.deinit(); // deinits FIRST (LIFO): decrefs to 1, sender's frees at 0

    // (A) CONSTRUCT + READ: a ProcBin reads, is_binary-tests, and eql/hashes
    //     EXACTLY like a flat on-heap binary of the same bytes.
    const pb = try FinalTerms.procBinary(&sender, payload);
    try std.testing.expect(FinalTerms.repIsBinary(&sender, pb));
    try std.testing.expectEqualStrings(payload, FinalTerms.binBytes(&sender, pb));
    const flat = try FinalTerms.binary(&sender, payload);
    try std.testing.expect(FinalTerms.eqlExact(&sender, pb, flat));
    try std.testing.expectEqual(FinalTerms.hashTerm(&sender, flat), FinalTerms.hashTerm(&sender, pb));
    const shared_ptr = FinalTerms.binBytes(&sender, pb).ptr; // the off-heap payload address

    // (B) SHARE-ON-SEND (THE WIN): a cross-heap copy RETAINS and shares the
    //     payload — the receiver's bytes are the SAME buffer, not a fresh copy.
    //     This pointer identity is the discriminator vs a flatten-copy (m1).
    const sent = try FinalTerms.gcCopy(&receiver, &sender, pb);
    try std.testing.expect(FinalTerms.repIsBinary(&receiver, sent));
    try std.testing.expectEqualStrings(payload, FinalTerms.binBytes(&receiver, sent));
    try std.testing.expectEqual(shared_ptr, FinalTerms.binBytes(&receiver, sent).ptr); // SHARED, not copied

    // (C) SHARE-ACROSS-GC: an in-place collect RELOCATES the ProcBin box but NOT
    //     the off-heap payload — so a surviving ProcBin keeps sharing the SAME
    //     buffer after GC (pointer identity preserved), never a byte copy.
    var pbroot = pb;
    var k: usize = 0;
    while (k < 300) : (k += 1) _ = try FinalTerms.tuple(&sender, &.{ FinalTerms.int(&sender, @intCast(k)), FinalTerms.int(&sender, 1) });
    var c = FinalTerms.collectInPlace(&sender, 0);
    try c.root(&pbroot);
    _ = try FinalTerms.finishInPlace(&sender, &c);
    try std.testing.expectEqualStrings(payload, FinalTerms.binBytes(&sender, pbroot)); // denotation survives
    try std.testing.expectEqual(shared_ptr, FinalTerms.binBytes(&sender, pbroot).ptr); // SHARED across GC, not copied
    // the receiver still shares the (still-live) payload — refcount kept it alive.
    try std.testing.expectEqual(shared_ptr, FinalTerms.binBytes(&receiver, sent).ptr);

    // (leak + double-free): the two `deinit`s decref the shared payload exactly
    // twice (receiver→1, sender→0→free). std.testing.allocator fails the test on
    // any leak (m2: deinit skips the decref) or double-free.
}

test "LAW e51-t2-reroute binary()>=64B IS a ProcBin (production share-on-send): a large binary built by the NORMAL constructor shares its payload across gcCopy by pointer identity, while a small (<64B) binary is copied — the erts on-heap/off-heap split" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var sender = FinalTerms.Ctx.init(gpa, &atoms);
    defer sender.deinit();
    var receiver = FinalTerms.Ctx.init(gpa, &atoms);
    defer receiver.deinit();

    // A ≥64B binary built by the ORDINARY `binary()` constructor (the path every
    // producer uses: ETF decode, list_to_binary, <<>>…) is now OFF-HEAP — so a
    // send (gcCopy) SHARES its bytes. This is the reroute that makes the E51-T2
    // share-on-send win REAL in production, not just via explicit procBinary.
    const big = "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF!!"; // 66 bytes ≥ 64
    try std.testing.expect(big.len >= FinalTerms.onheap_bin_limit);
    const bigt = try FinalTerms.binary(&sender, big);
    try std.testing.expect(FinalTerms.repIsBinary(&sender, bigt));
    try std.testing.expectEqualStrings(big, FinalTerms.binBytes(&sender, bigt));
    const big_ptr = FinalTerms.binBytes(&sender, bigt).ptr;
    const big_sent = try FinalTerms.gcCopy(&receiver, &sender, bigt);
    try std.testing.expectEqualStrings(big, FinalTerms.binBytes(&receiver, big_sent));
    try std.testing.expectEqual(big_ptr, FinalTerms.binBytes(&receiver, big_sent).ptr); // SHARED (m1: raise the limit → flattened → ptr differs)

    // A <64B binary stays ON-HEAP, so a send FLATTENS it (a fresh copy) — the two
    // buffers differ. (m2: lower the limit to 0 → the small one shares too → this
    // inequality breaks.)
    const small = "small-and-on-heap"; // 17 bytes < 64
    try std.testing.expect(small.len < FinalTerms.onheap_bin_limit);
    const smallt = try FinalTerms.binary(&sender, small);
    const small_ptr = FinalTerms.binBytes(&sender, smallt).ptr;
    const small_sent = try FinalTerms.gcCopy(&receiver, &sender, smallt);
    try std.testing.expectEqualStrings(small, FinalTerms.binBytes(&receiver, small_sent));
    try std.testing.expect(FinalTerms.binBytes(&receiver, small_sent).ptr != small_ptr); // COPIED, not shared
}

test "LAW gap-binary-share-across-gc SHARE + CONSERVATION: a copying GC relocates refc-binary BOXES but SHARES their off-heap payloads (pointer identity preserved, never a byte copy), the count == live-box invariant is conserved across the collect, and dead payloads free exactly once (no leak, no double free)" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = LawConfig{ .seed = 0xB1A5_C0DE, .iterations = 80 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();

    for (0..cfg.iterations) |i| {
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit(); // std.testing.allocator proves: every DEAD payload freed once, every LIVE one still held.

        // M distinct off-heap payloads (≥64B ⇒ ProcBin), each with a KNOWN buffer
        // address so "payload not copied" is checkable by pointer identity.
        const M = 3 + random.uintLessThan(usize, 4); // 3..6
        var payloads: [8][]u8 = undefined;
        var boxes: [8]FinalTerms.Term = undefined;
        var ptrs: [8][*]const u8 = undefined;
        for (0..M) |m| {
            const len = FinalTerms.onheap_bin_limit + random.uintLessThan(usize, 48);
            const buf = try gpa.alloc(u8, len);
            defer gpa.free(buf);
            for (buf) |*b| b.* = random.int(u8);
            boxes[m] = try FinalTerms.procBinary(&ctx, buf); // dupes buf into a fresh Refc
            payloads[m] = @constCast(FinalTerms.binBytes(&ctx, boxes[m])); // the payload's OWN buffer
            ptrs[m] = payloads[m].ptr;
            try expectLaw(FinalTerms.procBinRefCount(&ctx, boxes[m]) == 1, "gap-share-gc: fresh ProcBin count is 1", cfg, i);
        }
        // garbage to force real compaction/relocation of the survivors
        for (0..24) |g| _ = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, @intCast(g)), FinalTerms.int(&ctx, 2) });

        // keep a random subset alive as roots
        var roots: std.ArrayList(FinalTerms.Term) = .empty;
        defer roots.deinit(gpa);
        var slot_of: [8]usize = undefined; // root-slot -> payload index
        for (0..M) |m| if (random.boolean()) {
            try roots.append(gpa, boxes[m]);
            slot_of[roots.items.len - 1] = m;
        };

        // COPYING in-place collect: relocates everything reachable, drops the rest.
        var col = FinalTerms.collectInPlace(&ctx, 0);
        for (roots.items) |*r| try col.root(r);
        _ = try FinalTerms.finishInPlace(&ctx, &col);

        // SHARE-ACROSS-GC + REFCOUNT CONSERVATION for the survivors:
        for (roots.items, 0..) |r, j| {
            const m = slot_of[j];
            const bytes = FinalTerms.binBytes(&ctx, r); // r was relocated in place by col.root
            try expectLaw(bytes.ptr == ptrs[m], "gap-share-gc: survivor payload NOT copied (pointer identity across GC)", cfg, i);
            try expectLaw(std.mem.eql(u8, bytes, payloads[m]), "gap-share-gc: survivor bytes byte-identical across GC", cfg, i);
            try expectLaw(FinalTerms.procBinRefCount(&ctx, r) == 1, "gap-share-gc: count == live-box count conserved across GC", cfg, i);
        }
        // Dead payloads (roots subset excluded them) were freed during the collect;
        // std.testing.allocator would flag a leak (premature-non-free) here or a
        // double-free anywhere. ctx.deinit releases exactly the survivors.
    }
}

test "LAW gap-binary-share-across-gc NO-PREMATURE-FREE / NO-DOUBLE-FREE: two heaps sharing one refc-binary — GC-ing the heap that drops its box does NOT free the payload while the other heap's box lives; the shared payload frees exactly once at the last box" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const payload = "a long refcounted payload shared by two processes across a collection!!"; // ≥64B

    var sender = FinalTerms.Ctx.init(gpa, &atoms);
    defer sender.deinit();
    var receiver = FinalTerms.Ctx.init(gpa, &atoms);
    defer receiver.deinit(); // LIFO: deinits first; drops to the sender's last ref

    const pb = try FinalTerms.procBinary(&sender, payload);
    const shared_ptr = FinalTerms.binBytes(&sender, pb).ptr;
    try std.testing.expectEqual(@as(usize, 1), FinalTerms.procBinRefCount(&sender, pb));

    // share-on-send: the receiver's box points at the SAME payload → count 2.
    const sent = try FinalTerms.gcCopy(&receiver, &sender, pb);
    try std.testing.expectEqual(shared_ptr, FinalTerms.binBytes(&receiver, sent).ptr);
    try std.testing.expectEqual(@as(usize, 2), FinalTerms.procBinRefCount(&receiver, sent));

    // Add garbage, then GC the SENDER rooting NOTHING (its ProcBin box DIES). This
    // MUST NOT free the payload — the receiver's live box still points at it.
    var k: usize = 0;
    while (k < 100) : (k += 1) _ = try FinalTerms.tuple(&sender, &.{ FinalTerms.int(&sender, @intCast(k)), FinalTerms.int(&sender, 3) });
    var col = FinalTerms.collectInPlace(&sender, 0);
    _ = try FinalTerms.finishInPlace(&sender, &col); // no roots ⇒ the ProcBin is unreachable

    // NO-PREMATURE-FREE: receiver still reads the exact bytes at the SAME address,
    // and the count dropped to exactly 1 (the receiver's remaining box).
    try std.testing.expectEqual(shared_ptr, FinalTerms.binBytes(&receiver, sent).ptr);
    try std.testing.expectEqualStrings(payload, FinalTerms.binBytes(&receiver, sent));
    try std.testing.expectEqual(@as(usize, 1), FinalTerms.procBinRefCount(&receiver, sent));

    // Re-GC the sender (idempotent — no ProcBin left): must not double-release.
    var col2 = FinalTerms.collectInPlace(&sender, 0);
    _ = try FinalTerms.finishInPlace(&sender, &col2);
    try std.testing.expectEqual(@as(usize, 1), FinalTerms.procBinRefCount(&receiver, sent));
    // The two deinits free the payload EXACTLY ONCE (receiver→0→free; sender holds
    // no ref). std.testing.allocator fails on any leak or double free.
}
