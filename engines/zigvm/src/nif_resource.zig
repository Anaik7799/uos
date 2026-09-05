//! beam-zig M12 / S26: the **NIF resource algebra** (cf. erts erl_nif.c
//! resource objects) — the refcount/destructor slice of the NIF ABI.
//!
//! Signature:
//!   make    : () -> Handle              (refcount 1, term-unreachable)
//!   keep    : Handle -> ()              (enif_keep_resource)
//!   release : Handle -> ()              (enif_release_resource)
//!   setReachable : (Handle, bool)       (the GC rootset's view — in the
//!                                        full VM this comes from the M6
//!                                        collector's scan; modeled
//!                                        explicitly here so the law can
//!                                        drive it adversarially)
//!   gcSweep : () -> fires destructors   (erts: destructors run at GC, not
//!                                        at release time)
//!
//! Laws (over random op walks, checked against oracle bookkeeping):
//!   EXACTLY ONCE   a destructor fires at most once, ever; and it DOES fire
//!                  by the sweep after the resource becomes dead
//!   NEVER EARLY    never fires while refcount > 0 OR while a live term
//!                  still references the resource
//!   AT GC ONLY     release alone never fires a destructor mid-operation
//!   UNDERFLOW      releasing below zero is a named error, not a wrap

const std = @import("std");

pub const NifError = error{ OutOfMemory, ReleaseUnderflow, UseAfterDestroy };

pub const ResourceTable = struct {
    const Slot = struct {
        refcount: u32,
        term_reachable: bool,
        destroyed: bool,
        destroy_count: u32, // law observation: must never exceed 1
    };

    gpa: std.mem.Allocator,
    slots: std.ArrayList(Slot),
    destroyed_log: std.ArrayList(usize), // order of destructor firings

    pub fn init(gpa: std.mem.Allocator) ResourceTable {
        return .{ .gpa = gpa, .slots = .empty, .destroyed_log = .empty };
    }
    pub fn deinit(self: *ResourceTable) void {
        self.slots.deinit(self.gpa);
        self.destroyed_log.deinit(self.gpa);
    }

    pub fn make(self: *ResourceTable) !usize {
        try self.slots.append(self.gpa, .{
            .refcount = 1,
            .term_reachable = false,
            .destroyed = false,
            .destroy_count = 0,
        });
        return self.slots.items.len - 1;
    }

    pub fn keep(self: *ResourceTable, h: usize) NifError!void {
        const s = &self.slots.items[h];
        if (s.destroyed) return error.UseAfterDestroy;
        s.refcount += 1;
    }

    pub fn release(self: *ResourceTable, h: usize) NifError!void {
        const s = &self.slots.items[h];
        if (s.destroyed) return error.UseAfterDestroy;
        if (s.refcount == 0) return error.ReleaseUnderflow;
        s.refcount -= 1;
        // NOTE: no destructor here — erts defers to GC (the AT-GC-ONLY law)
    }

    pub fn setReachable(self: *ResourceTable, h: usize, reachable: bool) void {
        const s = &self.slots.items[h];
        if (!s.destroyed) s.term_reachable = reachable;
    }

    /// The GC point: fire destructors for every dead resource.
    pub fn gcSweep(self: *ResourceTable) !void {
        for (self.slots.items, 0..) |*s, h| {
            if (!s.destroyed and s.refcount == 0 and !s.term_reachable) {
                s.destroyed = true;
                s.destroy_count += 1;
                try self.destroyed_log.append(self.gpa, h);
            }
        }
    }
};

// ============================================================================
// Law suite — adversarial op walks vs oracle bookkeeping
// ============================================================================

test "EXACTLY-ONCE + NEVER-EARLY + AT-GC-ONLY + UNDERFLOW over op walks" {
    const gpa = std.testing.allocator;

    for (0..40) |iter| {
        var prng = std.Random.DefaultPrng.init(0x71F0 +% iter);
        const random = prng.random();
        var tab = ResourceTable.init(gpa);
        defer tab.deinit();

        // oracle view: expected liveness per handle
        var made: usize = 0;

        for (0..300) |_| {
            switch (random.uintLessThan(u8, 6)) {
                0 => {
                    _ = try tab.make();
                    made += 1;
                },
                1 => if (made > 0) {
                    const h = random.uintLessThan(usize, made);
                    // keep on a live handle only (API contract)
                    if (!tab.slots.items[h].destroyed) try tab.keep(h);
                },
                2, 3 => if (made > 0) {
                    const h = random.uintLessThan(usize, made);
                    const s = tab.slots.items[h];
                    if (!s.destroyed) {
                        if (s.refcount == 0) {
                            try std.testing.expectError(error.ReleaseUnderflow, tab.release(h));
                        } else {
                            try tab.release(h);
                            // AT-GC-ONLY: still not destroyed, even if dead
                            try std.testing.expect(!tab.slots.items[h].destroyed);
                        }
                    }
                },
                4 => if (made > 0) {
                    const h = random.uintLessThan(usize, made);
                    tab.setReachable(h, random.boolean());
                },
                else => try tab.gcSweep(),
            }
            // invariants at EVERY step
            for (tab.slots.items) |s| {
                try std.testing.expect(s.destroy_count <= 1); // exactly-once
                if (s.destroyed) {
                    // NEVER-EARLY (checked at destruction time by state):
                    try std.testing.expect(s.refcount == 0);
                    try std.testing.expect(!s.term_reachable);
                }
            }
        }

        // final: release everything, clear reachability, sweep — every
        // handle must be destroyed EXACTLY once
        for (0..made) |h| {
            tab.setReachable(h, false);
            while (!tab.slots.items[h].destroyed and tab.slots.items[h].refcount > 0)
                try tab.release(h);
        }
        try tab.gcSweep();
        for (tab.slots.items) |s| {
            try std.testing.expect(s.destroyed);
            try std.testing.expectEqual(@as(u32, 1), s.destroy_count);
        }
        try std.testing.expectEqual(made, tab.destroyed_log.items.len);
    }
}

test "GC tie-in scenario: a term keeps a released resource alive until the term dies" {
    const gpa = std.testing.allocator;
    var tab = ResourceTable.init(gpa);
    defer tab.deinit();

    const h = try tab.make();
    tab.setReachable(h, true); // a heap term now references it
    try tab.release(h); // NIF released its own reference
    try tab.gcSweep();
    try std.testing.expect(!tab.slots.items[h].destroyed); // term keeps it alive

    tab.setReachable(h, false); // the term became garbage & was collected
    try tab.gcSweep();
    try std.testing.expect(tab.slots.items[h].destroyed); // NOW it fires
    try std.testing.expectEqual(@as(u32, 1), tab.slots.items[h].destroy_count);

    // use-after-destroy is a named error
    try std.testing.expectError(error.UseAfterDestroy, tab.keep(h));
    try std.testing.expectError(error.UseAfterDestroy, tab.release(h));
}
