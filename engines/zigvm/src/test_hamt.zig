//! test_hamt — test-only fixture module for the HAMT/ETS storage backend: it
//! builds a term context and exercises the trie through the same public
//! surface a caller would use. Carries no VM semantics of its own; the map
//! laws it supports are stated in ets_hamt.zig and ets_algebra.zig.
const std = @import("std");
const ta = @import("term_algebra.zig");
const FinalTerms = ta.FinalTerms;

test "setup context" {
    const gpa = std.testing.allocator;
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    
    const key = FinalTerms.int(&ctx, 42);
    const hash = FinalTerms.hashTerm(&ctx, key);
    std.debug.print("hash: {}\n", .{hash});
}
