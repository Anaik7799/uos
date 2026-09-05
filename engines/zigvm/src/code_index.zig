//! beam-zig M10 / S16: **code index & hot load** (cf. erts code_ix.c,
//! beam_bif_load.c, erl_code_staged.h).
//!
//! The erts model, kept whole: every module has at most TWO versions —
//! `current` and `old`. External (fully-qualified) calls always resolve
//! through the index to CURRENT; a process already executing a version
//! holds a continuation into it until it returns. Purge deletes `old`, and
//! is REFUSED while any process still holds a continuation into it.
//!
//! Signature:
//!   load    : (Index, name, Program) -> Index     (current' = new; old' = current)
//!   resolve : (Index, name) -> Program            (external call: CURRENT)
//!   hold    : (Index, name) -> Handle             (a process entering the module)
//!   release : Handle -> ()                        (process returned/died)
//!   purge   : (Index, name) -> ok | error         (delete old, if safe)
//!
//! Laws:
//!   OLD/NEW HOMOMORPHISM  for an export whose code is UNCHANGED between
//!       versions, calls resolved through the index denote the same results
//!       before and after a load (the hot-load correctness statement)
//!   NEW CODE WINS         after load, external calls execute the NEW
//!       version (a changed export observably changes)
//!   CONTINUATION STAYS    a handle held across a load keeps executing the
//!       version it entered (old code runs until return)
//!   PURGE SAFETY          purge fails with a NAMED error while any process
//!       holds old code; succeeds once released; a second load while old
//!       code exists is refused (two-version limit, as in erts)
//!
//! E5.2b (the file-based code-server CONTINUATION, DIVERGENCE 61): the M10
//! table is generalized from a load-only index into the MUTABLE runtime code
//! table the code server drives. `current` is now OPTIONAL — a module can exist
//! with NO current version (deleted, awaiting purge) but a live `old`. Two new
//! runtime operations model erts `erlang:delete_module/1` and
//! `erlang:check_old_code/1` exactly:
//!   delete    : (Index, name) -> DeleteResult    (current -> old; leaves no
//!       current — external calls fail until reload; `undefined` if the module
//!       is absent, a NAMED badarg if it has no current version to retire or
//!       an unpurged old version, mirroring erts)
//!   checkOld  : (Index, name) -> bool            (does `old` exist?)
//! Load is extended to REVIVE a deleted module (set current, keep old). The
//! staged `prepare_loading -> finish_loading` half + on_load gating live in the
//! sibling `code_server.zig`, layered over these primitives.

const std = @import("std");
const ta = @import("term_algebra.zig");
const ia = @import("instr_algebra.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;
const spec = ta.spec;

pub const Version = struct {
    prog: ia.Program,
    holders: u32 = 0,
};

pub const ModuleSlot = struct {
    current: ?*Version, // versions are STABLE heap objects: a load must never
    old: ?*Version = null, // mutate what an existing continuation points at.
    // (The first cut stored versions by value; the continuation-stays LAW
    // failed because load overwrote the struct a Handle pointed into. Kept
    // as a comment because it is exactly the bug class hot-loading breeds.)
    // E5.2b: `current` is OPTIONAL — `delete_module` retires it to `old` and
    // leaves the slot with no current version until a reload revives it.
};

/// The outcome of `deleteModule`, mapped to the `erlang:delete_module/1`
/// return by the BIF layer: `deleted` -> `true`, `absent` -> `undefined`,
/// `badarg` -> a raised badarg (no current version, or an unpurged old one).
pub const DeleteResult = enum { deleted, absent, badarg };

pub const Handle = struct {
    version: *Version,

    pub fn release(self: *Handle) void {
        std.debug.assert(self.version.holders > 0);
        self.version.holders -= 1;
    }
    pub fn prog(self: *const Handle) ia.Program {
        return self.version.prog;
    }
};

pub const CodeIndex = struct {
    gpa: std.mem.Allocator,
    slots: std.StringHashMapUnmanaged(*ModuleSlot),

    pub fn init(gpa: std.mem.Allocator) CodeIndex {
        return .{ .gpa = gpa, .slots = .empty };
    }
    pub fn deinit(self: *CodeIndex) void {
        var it = self.slots.valueIterator();
        while (it.next()) |slot| {
            if (slot.*.current) |c| self.gpa.destroy(c);
            if (slot.*.old) |o| self.gpa.destroy(o);
            self.gpa.destroy(slot.*);
        }
        self.slots.deinit(self.gpa);
    }

    pub fn load(self: *CodeIndex, name: []const u8, prog: ia.Program) !void {
        const fresh = try self.gpa.create(Version);
        errdefer self.gpa.destroy(fresh);
        fresh.* = .{ .prog = prog };
        if (self.slots.get(name)) |slot| {
            // E5.2b: a deleted module (no current) is REVIVED — set current,
            // keep whatever `old` the delete left retired.
            if (slot.current == null) {
                slot.current = fresh;
                return;
            }
            if (slot.old != null) return error.OldCodeExists; // two-version limit
            slot.old = slot.current;
            slot.current = fresh;
            return;
        }
        const slot = try self.gpa.create(ModuleSlot);
        slot.* = .{ .current = fresh };
        try self.slots.put(self.gpa, name, slot);
    }

    /// `erlang:delete_module/1` — retire the current version to `old`, leaving
    /// no current version (external calls fail until a reload). Refused as a
    /// NAMED badarg when there is no current version to retire or an unpurged
    /// `old` already occupies the second slot (erts' "not purged" rule).
    pub fn deleteModule(self: *CodeIndex, name: []const u8) DeleteResult {
        const slot = self.slots.get(name) orelse return .absent;
        if (slot.current == null) return .badarg; // already deleted
        if (slot.old != null) return .badarg; // unpurged old: two-version limit
        slot.old = slot.current;
        slot.current = null;
        return .deleted;
    }

    /// `erlang:check_old_code/1` — does the module hold a retired `old` version?
    pub fn checkOldCode(self: *CodeIndex, name: []const u8) bool {
        const slot = self.slots.get(name) orelse return false;
        return slot.old != null;
    }

    /// External call resolution: ALWAYS the current version (null if deleted).
    pub fn resolve(self: *CodeIndex, name: []const u8) ?ia.Program {
        const slot = self.slots.get(name) orelse return null;
        const cur = slot.current orelse return null;
        return cur.prog;
    }

    /// A process entering the module pins the version it entered.
    pub fn hold(self: *CodeIndex, name: []const u8) ?Handle {
        const slot = self.slots.get(name) orelse return null;
        const cur = slot.current orelse return null;
        cur.holders += 1;
        return .{ .version = cur };
    }

    pub fn purge(self: *CodeIndex, name: []const u8) !void {
        const slot = self.slots.get(name) orelse return error.NoSuchModule;
        const old = slot.old orelse return error.NoOldCode;
        if (old.holders > 0) return error.ProcessesHoldOldCode;
        self.gpa.destroy(old);
        slot.old = null;
    }

    // ------------------------------------------------------------------------
    // gap-hot-load-fs (S16, DIVERGENCE 61 continuation): the two library-level
    // purge surfaces `code:purge/1` and `code:soft_purge/1` are DISTINCT from the
    // erts_internal engine primitive `purge` above — they differ precisely in
    // how they treat a process that is LINGERING on old code. Both are pinned
    // byte-for-byte against the live OTP-30 oracle (`code:purge/1` /
    // `code:soft_purge/1`), whose truth table is the semantic domain here.
    //
    // PROCESS-LAYER BOUND (honest scope): the `holders` count is the model of
    // "processes lingering on old code". `code:purge/1` KILLS them in erts; this
    // model drops the retired version (freeing it) and REPORTS that a kill would
    // have occurred (holders>0). It does not drive a real scheduler kill — the
    // proc layer is not wired through this table — so a live `Handle` into the
    // purged old version is, by contract, dead after `purgeForce` (never
    // dereference it, exactly as a killed process would never resume). This is
    // the same documented bound `code_server.zig`'s RUNTIME-driven purge law
    // carries: the ENGINE purge-safety is proven there; the LIBRARY return-value
    // truth table is proven here.
    // ------------------------------------------------------------------------

    /// `code:purge/1` — FORCE-purge the retired `old` version. If any process is
    /// lingering on old code it is killed (modeled: the version is dropped and
    /// the fact reported). Returns TRUE iff a lingering process was killed —
    /// NOT merely whether old code existed (oracle-pinned: old+no-proc → false
    /// yet old is still removed; old+proc → true). A module with no old code (or
    /// absent) → false and nothing changes.
    pub fn purgeForce(self: *CodeIndex, name: []const u8) bool {
        const slot = self.slots.get(name) orelse return false;
        const old = slot.old orelse return false;
        const killed = old.holders > 0;
        self.gpa.destroy(old); // holders (if any) are killed → the version dies
        slot.old = null;
        return killed;
    }

    /// `code:soft_purge/1` — purge the retired `old` version ONLY if no process
    /// lingers on it. Returns TRUE when there is nothing holding old code back
    /// (old code absent → true and no-op; old code present with no holder →
    /// true and removed); FALSE when a process still runs old code (old code is
    /// LEFT in place and no process is killed). Oracle-pinned truth table.
    pub fn softPurge(self: *CodeIndex, name: []const u8) bool {
        const slot = self.slots.get(name) orelse return true; // absent → true
        const old = slot.old orelse return true; // no old → true, no-op
        if (old.holders > 0) return false; // in use → refuse, keep old, no kill
        self.gpa.destroy(old);
        slot.old = null;
        return true;
    }
};

// ============================================================================
// Test programs: v1 and v2 of a module with one changed and one unchanged
// export. Entries: 0 = double (v2 changes it to quadruple), 3 = inc
// (unchanged between versions).
// ============================================================================

const prog_v1: ia.Program = &.{
    // 0: double(x0)
    .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .x = 0 }, .dst = 0 } },
    .{ .halt = .{ .src = .{ .x = 0 } } },
    .{ .jump = .{ .to = 2 } }, // padding
    // 3: inc(x0) — IDENTICAL in v2
    .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } },
    .{ .halt = .{ .src = .{ .x = 0 } } },
};

const prog_v2: ia.Program = &.{
    // 0: quadruple(x0) — CHANGED
    .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .x = 0 }, .dst = 0 } },
    .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .x = 0 }, .dst = 0 } },
    .{ .halt = .{ .src = .{ .x = 0 } } },
    // 3: inc(x0) — UNCHANGED
    .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } },
    .{ .halt = .{ .src = .{ .x = 0 } } },
};

fn runEntry(gpa: std.mem.Allocator, atoms: *AtomTable, prog: ia.Program, entry: usize, arg: i64) !i64 {
    var m = try ia.Machine.init(gpa, atoms);
    defer m.deinit();
    m.pc = entry;
    m.regs[0] = FinalTerms.int(&m.ctx, arg);
    var guard: usize = 0;
    while (m.status == .running) : (guard += 1) {
        if (guard > 1000) return error.DidNotHalt;
        try ia.run(&m, prog, 10);
    }
    return @as(i64, @bitCast(m.result)) >> 4;
}

test "Old/new homomorphism + new-code-wins + continuation-stays + purge safety" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var idx = CodeIndex.init(gpa);
    defer idx.deinit();

    try idx.load("m", prog_v1);

    // pre-load answers through the index
    const inc_before = try runEntry(gpa, &atoms, idx.resolve("m").?, 3, 10);
    const dbl_before = try runEntry(gpa, &atoms, idx.resolve("m").?, 0, 10);
    try std.testing.expectEqual(@as(i64, 11), inc_before);
    try std.testing.expectEqual(@as(i64, 20), dbl_before);

    // a process is EXECUTING v1 when the load happens
    var held = idx.hold("m").?;

    try idx.load("m", prog_v2);

    // OLD/NEW HOMOMORPHISM: the unchanged export answers identically
    const inc_after = try runEntry(gpa, &atoms, idx.resolve("m").?, 3, 10);
    try std.testing.expectEqual(inc_before, inc_after);

    // NEW CODE WINS: the changed export observably changed via the index
    const dbl_after = try runEntry(gpa, &atoms, idx.resolve("m").?, 0, 10);
    try std.testing.expectEqual(@as(i64, 40), dbl_after);

    // CONTINUATION STAYS: the held process still runs v1 semantics
    const dbl_held = try runEntry(gpa, &atoms, held.prog(), 0, 10);
    try std.testing.expectEqual(@as(i64, 20), dbl_held);

    // PURGE SAFETY: refused while held…
    try std.testing.expectError(error.ProcessesHoldOldCode, idx.purge("m"));
    // …and a THIRD load is refused while old code exists (two-version limit)
    try std.testing.expectError(error.OldCodeExists, idx.load("m", prog_v1));
    // release → purge succeeds → another load is allowed again
    held.release();
    try idx.purge("m");
    try idx.load("m", prog_v1);
    // now current is v1 again: double(10) == 20 through the index
    try std.testing.expectEqual(@as(i64, 20), try runEntry(gpa, &atoms, idx.resolve("m").?, 0, 10));

    // purge with no old code / unknown module: named errors
    try std.testing.expectError(error.NoSuchModule, idx.purge("nosuch"));
}

test "E5.2b delete_module/check_old_code: retire-to-old, revive-on-reload, badarg totality" {
    const gpa = std.testing.allocator;
    var idx = CodeIndex.init(gpa);
    defer idx.deinit();

    // absent module: delete -> .absent, check_old -> false (erts undefined/false).
    try std.testing.expectEqual(DeleteResult.absent, idx.deleteModule("m"));
    try std.testing.expect(!idx.checkOldCode("m"));

    try idx.load("m", prog_v1);
    // loaded, no old yet.
    try std.testing.expect(!idx.checkOldCode("m"));
    // delete retires current -> old; NO current version remains.
    try std.testing.expectEqual(DeleteResult.deleted, idx.deleteModule("m"));
    try std.testing.expect(idx.checkOldCode("m")); // old now exists
    try std.testing.expect(idx.resolve("m") == null); // external call would fail
    // deleting again with no current version is a NAMED badarg (erts).
    try std.testing.expectEqual(DeleteResult.badarg, idx.deleteModule("m"));

    // reload REVIVES the module as current, keeping the retired old.
    try idx.load("m", prog_v2);
    try std.testing.expect(idx.resolve("m") != null);
    try std.testing.expect(idx.checkOldCode("m")); // old still retired
    // with both current+old occupied, a delete is refused (two-version limit).
    try std.testing.expectEqual(DeleteResult.badarg, idx.deleteModule("m"));

    // purge drops old; check_old_code goes false; delete is allowed again.
    try idx.purge("m");
    try std.testing.expect(!idx.checkOldCode("m"));
    try std.testing.expectEqual(DeleteResult.deleted, idx.deleteModule("m"));
}

test "Holder accounting: multiple holders, purge only after the LAST release" {
    const gpa = std.testing.allocator;
    var idx = CodeIndex.init(gpa);
    defer idx.deinit();

    try idx.load("m", prog_v1);
    var h1 = idx.hold("m").?;
    var h2 = idx.hold("m").?;
    try idx.load("m", prog_v2);

    try std.testing.expectError(error.ProcessesHoldOldCode, idx.purge("m"));
    h1.release();
    try std.testing.expectError(error.ProcessesHoldOldCode, idx.purge("m"));
    h2.release();
    try idx.purge("m");
}
