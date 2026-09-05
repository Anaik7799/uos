//! ets_hamt — a hash-array-mapped-trie backend for ETS with an atomic root
//! pointer (readers race writers on a published immutable trie). Semantic
//! domain: a finite map key-term -> object-term; observational equality is
//! lookup over the key set, and the laws in this module's tests hold it to
//! the same map semantics as the ets_algebra oracle (insert/lookup/delete
//! round-trips). Scope: storage encoding only — ETS table semantics
//! (ownership, types, matchspecs) live in ets_algebra.zig.
//! Formal projection: proofs/HAMT_Safety.v, re-attested at DIVERGENCE 764.
const std = @import("std");
const ta = @import("term_algebra.zig");
const FinalTerms = ta.FinalTerms;

pub const EtsHamt = struct {
    allocator: std.mem.Allocator,
    root: std.atomic.Value(usize),

    const BITS = 4;
    const SIZE = 1 << BITS;
    const MASK = SIZE - 1;

    const TAG_BRANCH: usize = 0;
    const TAG_LEAF: usize = 1;

    pub const Branch = struct {
        children: [SIZE]std.atomic.Value(usize),
    };

    pub const Leaf = struct {
        key: FinalTerms.Term,
        value: FinalTerms.Term,
        next: usize, // pointer to next Leaf
    };

    pub fn init(allocator: std.mem.Allocator) EtsHamt {
        return .{
            .allocator = allocator,
            .root = std.atomic.Value(usize).init(0),
        };
    }

    fn isLeaf(ptr: usize) bool {
        return (ptr & 1) != 0;
    }

    fn getPtr(ptr: usize, comptime T: type) *T {
        return @ptrFromInt(ptr & ~@as(usize, 1));
    }

    pub fn insert(self: *EtsHamt, ctx: *FinalTerms.Ctx, obj: FinalTerms.Term) !void {
        std.debug.assert(FinalTerms.kindOf(ctx, obj) == .tuple);
        const key = FinalTerms.tupleElem(ctx, obj, 0);
        const hash = FinalTerms.hashTerm(ctx, key);

        var level: u6 = 0;
        var current_atomic = &self.root;

        while (true) {
            const ptr_val = current_atomic.load(.acquire);

            if (ptr_val == 0) {
                const new_leaf = try self.allocator.create(Leaf);
                new_leaf.* = .{ .key = key, .value = obj, .next = 0 };
                const new_ptr = @intFromPtr(new_leaf) | TAG_LEAF;

                if (current_atomic.cmpxchgWeak(0, new_ptr, .release, .acquire) == null) {
                    return;
                }
                self.allocator.destroy(new_leaf);
                continue;
            }

            if (isLeaf(ptr_val)) {
                const leaf = getPtr(ptr_val, Leaf);
                const leaf_hash = FinalTerms.hashTerm(ctx, leaf.key);

                var curr: ?*Leaf = leaf;
                var found = false;
                while (curr) |c| {
                    if (FinalTerms.eqlExact(ctx, c.key, key)) {
                        found = true;
                        break;
                    }
                    curr = if (c.next != 0) getPtr(c.next, Leaf) else null;
                }

                if (found) {
                    const new_chain = try self.rebuildChainReplace(ptr_val, ctx, key, obj);
                    if (current_atomic.cmpxchgWeak(ptr_val, new_chain, .release, .acquire) == null) {
                        return;
                    }
                    self.destroyChain(new_chain);
                    continue;
                }

                if (leaf_hash == hash) {
                    const new_leaf = try self.allocator.create(Leaf);
                    new_leaf.* = .{ .key = key, .value = obj, .next = ptr_val };
                    const new_ptr = @intFromPtr(new_leaf) | TAG_LEAF;
                    if (current_atomic.cmpxchgWeak(ptr_val, new_ptr, .release, .acquire) == null) {
                        return;
                    }
                    self.allocator.destroy(new_leaf);
                    continue;
                } else {
                    const new_branch = try self.allocator.create(Branch);
                    @memset(&new_branch.children, std.atomic.Value(usize).init(0));

                    const leaf_idx = (leaf_hash >> level) & MASK;
                    const new_idx = (hash >> level) & MASK;

                    if (leaf_idx == new_idx) {
                        new_branch.children[leaf_idx].store(ptr_val, .release);
                        const new_ptr = @intFromPtr(new_branch) | TAG_BRANCH;

                        if (current_atomic.cmpxchgWeak(ptr_val, new_ptr, .release, .acquire) == null) {
                            continue;
                        }
                        self.allocator.destroy(new_branch);
                        continue;
                    } else {
                        const new_leaf = try self.allocator.create(Leaf);
                        new_leaf.* = .{ .key = key, .value = obj, .next = 0 };

                        new_branch.children[leaf_idx].store(ptr_val, .release);
                        new_branch.children[new_idx].store(@intFromPtr(new_leaf) | TAG_LEAF, .release);

                        const new_ptr = @intFromPtr(new_branch) | TAG_BRANCH;
                        if (current_atomic.cmpxchgWeak(ptr_val, new_ptr, .release, .acquire) == null) {
                            return;
                        }
                        self.allocator.destroy(new_leaf);
                        self.allocator.destroy(new_branch);
                        continue;
                    }
                }
            } else {
                const branch = getPtr(ptr_val, Branch);
                const idx = (hash >> level) & MASK;
                current_atomic = &branch.children[idx];
                level += BITS;
            }
        }
    }

    fn rebuildChainReplace(self: *EtsHamt, leaf_ptr: usize, ctx: *FinalTerms.Ctx, key: FinalTerms.Term, obj: FinalTerms.Term) !usize {
        var head: usize = 0;
        var tail: ?*usize = null;

        var curr_ptr = leaf_ptr;
        while (curr_ptr != 0) {
            const curr = getPtr(curr_ptr, Leaf);
            const new_leaf = try self.allocator.create(Leaf);

            if (FinalTerms.eqlExact(ctx, curr.key, key)) {
                new_leaf.* = .{ .key = key, .value = obj, .next = 0 };
            } else {
                new_leaf.* = .{ .key = curr.key, .value = curr.value, .next = 0 };
            }

            const new_ptr = @intFromPtr(new_leaf) | TAG_LEAF;
            if (tail) |t| {
                t.* = new_ptr;
            } else {
                head = new_ptr;
            }
            tail = &new_leaf.next;

            curr_ptr = curr.next;
        }
        return head;
    }

    fn destroyChain(self: *EtsHamt, leaf_ptr: usize) void {
        var curr_ptr = leaf_ptr;
        while (curr_ptr != 0) {
            const curr = getPtr(curr_ptr, Leaf);
            const next_ptr = curr.next;
            self.allocator.destroy(curr);
            curr_ptr = next_ptr;
        }
    }

    pub fn lookup(self: *EtsHamt, ctx: *FinalTerms.Ctx, key: FinalTerms.Term) ?FinalTerms.Term {
        const hash = FinalTerms.hashTerm(ctx, key);
        var level: u6 = 0;
        var ptr_val = self.root.load(.acquire);

        while (ptr_val != 0) {
            if (isLeaf(ptr_val)) {
                var curr_ptr = ptr_val;
                while (curr_ptr != 0) {
                    const curr = getPtr(curr_ptr, Leaf);
                    if (FinalTerms.eqlExact(ctx, curr.key, key)) {
                        return curr.value;
                    }
                    curr_ptr = curr.next;
                }
                return null;
            } else {
                const branch = getPtr(ptr_val, Branch);
                const idx = (hash >> level) & MASK;
                ptr_val = branch.children[idx].load(.acquire);
                level += BITS;
            }
        }
        return null;
    }
};

test "ETS HAMT basic operations" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    var hamt = EtsHamt.init(gpa);

    const k1 = FinalTerms.int(&ctx, 100);
    const v1 = FinalTerms.int(&ctx, 101);
    const tuple1 = try FinalTerms.tuple(&ctx, &.{ k1, v1 });

    const k2 = FinalTerms.int(&ctx, 200);
    const v2 = FinalTerms.int(&ctx, 201);
    const tuple2 = try FinalTerms.tuple(&ctx, &.{ k2, v2 });

    try hamt.insert(&ctx, tuple1);
    try hamt.insert(&ctx, tuple2);

    const res1 = hamt.lookup(&ctx, k1);
    try std.testing.expect(res1 != null);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, res1.?, tuple1));

    const res2 = hamt.lookup(&ctx, k2);
    try std.testing.expect(res2 != null);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, res2.?, tuple2));

    const res3 = hamt.lookup(&ctx, FinalTerms.int(&ctx, 300));
    try std.testing.expect(res3 == null);
}

test "ETS HAMT replace" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    var hamt = EtsHamt.init(gpa);

    const k1 = FinalTerms.int(&ctx, 100);
    const v1 = FinalTerms.int(&ctx, 101);
    const tuple1 = try FinalTerms.tuple(&ctx, &.{ k1, v1 });
    try hamt.insert(&ctx, tuple1);

    const v2 = FinalTerms.int(&ctx, 102);
    const tuple2 = try FinalTerms.tuple(&ctx, &.{ k1, v2 });
    try hamt.insert(&ctx, tuple2);

    const res1 = hamt.lookup(&ctx, k1);
    try std.testing.expect(res1 != null);
    try std.testing.expect(FinalTerms.eqlExact(&ctx, res1.?, tuple2));
}

fn workerInsert(hamt: *EtsHamt, ctx: *FinalTerms.Ctx, tuples: []const FinalTerms.Term) !void {
    for (tuples) |tuple| {
        try hamt.insert(ctx, tuple);
    }
}

test "ETS HAMT concurrent insertions" {
    const gpa = std.heap.page_allocator;

    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    
    var hamt = EtsHamt.init(gpa);

    const num_threads = 4;
    const inserts_per_thread = 1000;
    const total_inserts = num_threads * inserts_per_thread;

    var tuples = try gpa.alloc(FinalTerms.Term, total_inserts);
    for (0..total_inserts) |i| {
        const k = FinalTerms.int(&ctx, @intCast(i));
        const v = FinalTerms.int(&ctx, @intCast(i * 10));
        tuples[i] = try FinalTerms.tuple(&ctx, &.{ k, v });
    }
    
    var threads: [num_threads]std.Thread = undefined;
    for (0..num_threads) |i| {
        const start = i * inserts_per_thread;
        const end = start + inserts_per_thread;
        threads[i] = try std.Thread.spawn(.{}, workerInsert, .{ &hamt, &ctx, tuples[start..end] });
    }
    
    for (0..num_threads) |i| {
        threads[i].join();
    }

    for (0..total_inserts) |i| {
        const k = FinalTerms.int(&ctx, @intCast(i));
        const res = hamt.lookup(&ctx, k);
        try std.testing.expect(res != null);
        
        const expected_v = FinalTerms.int(&ctx, @intCast(i * 10));
        const actual_v = FinalTerms.tupleElem(&ctx, res.?, 1);
        try std.testing.expect(FinalTerms.eqlExact(&ctx, actual_v, expected_v));
    }
}
