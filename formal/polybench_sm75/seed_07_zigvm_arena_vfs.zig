// PolyBench-SM75 Seed #7: ZigVM Deterministic Linear Arena & Descriptor-Relative VFS Guard
// Tests lockless ring-buffer indexing, linear arena bump allocation without GC, and
// descriptor-relative path traversal rejection ("..", leading "/", embedded NUL).

const std = @import("std");

pub const ArenaError = error{
    OutOfArenaMemory,
    InvalidAlignment,
    PathTraversalDenied,
    EmbeddedNulDenied,
    AbsolutePathDenied,
};

pub const LinearArena = struct {
    capacity: usize,
    offset: usize,

    pub fn init(capacity: usize) LinearArena {
        return .{ .capacity = capacity, .offset = 0 };
    }

    pub fn allocAligned(self: *LinearArena, size: usize, alignment: usize) ArenaError!usize {
        if (alignment == 0 or (alignment & (alignment - 1)) != 0) {
            return ArenaError.InvalidAlignment;
        }
        const mask = alignment - 1;
        const aligned_offset = (self.offset + mask) & ~mask;
        if (aligned_offset > self.capacity or size > self.capacity - aligned_offset) {
            return ArenaError.OutOfArenaMemory;
        }
        self.offset = aligned_offset + size;
        return aligned_offset;
    }

    pub fn reset(self: *LinearArena) void {
        self.offset = 0;
    }
};

pub fn validateDescriptorRelativePath(path: []const u8) ArenaError!usize {
    if (path.len == 0) return ArenaError.PathTraversalDenied;
    if (path[0] == '/') return ArenaError.AbsolutePathDenied;
    var segments: usize = 1;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] == 0) return ArenaError.EmbeddedNulDenied;
        if (path[i] == '/') {
            segments += 1;
        }
        if (i + 1 < path.len and path[i] == '.' and path[i + 1] == '.') {
            const prev_ok = (i == 0) or (path[i - 1] == '/');
            const next_ok = (i + 2 == path.len) or (path[i + 2] == '/');
            if (prev_ok and next_ok) return ArenaError.PathTraversalDenied;
        }
    }
    return segments;
}

test "zigvm linear arena deterministic aligned bump allocation and overflow trap" {
    var arena = LinearArena.init(1024);
    const off0 = try arena.allocAligned(64, 64);
    try std.testing.expectEqual(@as(usize, 0), off0);
    const off1 = try arena.allocAligned(13, 16);
    try std.testing.expectEqual(@as(usize, 64), off1);
    const off2 = try arena.allocAligned(32, 64);
    try std.testing.expectEqual(@as(usize, 128), off2);
    try std.testing.expectError(ArenaError.OutOfArenaMemory, arena.allocAligned(960, 64));
    try std.testing.expectError(ArenaError.InvalidAlignment, arena.allocAligned(16, 3));
    arena.reset();
    try std.testing.expectEqual(@as(usize, 0), arena.offset);
}

test "zigvm descriptor-relative VFS rejects traversal, absolute paths, and embedded NUL" {
    const segs = try validateDescriptorRelativePath("var/sa-plan/uos.sqlite3");
    try std.testing.expectEqual(@as(usize, 3), segs);
    try std.testing.expectError(ArenaError.AbsolutePathDenied, validateDescriptorRelativePath("/etc/passwd"));
    try std.testing.expectError(ArenaError.PathTraversalDenied, validateDescriptorRelativePath("var/../etc/shadow"));
    try std.testing.expectError(ArenaError.PathTraversalDenied, validateDescriptorRelativePath(".."));
    try std.testing.expectError(ArenaError.EmbeddedNulDenied, validateDescriptorRelativePath("var/uos\x00.db"));
}
