//! event_log — an append-only in-memory event record for VM observability
//! (actor spawn/exit, partitions, …). Semantic domain: a sequence of typed
//! events; append is the only constructor, so the denotation is the ordered
//! event list (append monotonicity is the implicit law, exercised by this
//! module's test). Report-only: nothing in the VM's semantics may read this
//! log to make a decision.
const std = @import("std");

pub const EventType = enum {
    actor_spawn,
    actor_exit,
    network_partition,
};

pub const Event = union(EventType) {
    actor_spawn: struct {
        pid: u32,
    },
    actor_exit: struct {
        pid: u32,
        reason: u64, // represented generically
    },
    network_partition: struct {
        node_id: u32,
        duration_ms: u64,
    },
};

pub const ServiceTags = struct {
    env: []const u8,
    service: []const u8,
    version: []const u8,
};

pub const LogEntry = struct {
    timestamp_ms: u64,
    event: Event,
    trace_context: ?@import("otlp.zig").TraceContext = null,
    tags: ?ServiceTags = null,
};

pub var experimental_event_log: bool = false;

pub const EventLog = struct {
    buffer: []LogEntry,
    head: usize,
    count: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !EventLog {
        const buffer = try allocator.alloc(LogEntry, capacity);
        return EventLog{
            .buffer = buffer,
            .head = 0,
            .count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EventLog) void {
        self.allocator.free(self.buffer);
    }

    pub fn append(self: *EventLog, ts: u64, event: Event) void {
        self.appendWithTrace(ts, event, null, null);
    }

    pub fn appendWithTrace(self: *EventLog, ts: u64, event: Event, trace_context: ?@import("otlp.zig").TraceContext, tags: ?ServiceTags) void {
        if (!experimental_event_log) return;
        if (self.buffer.len == 0) return;
        self.buffer[self.head] = LogEntry{
            .timestamp_ms = ts,
            .event = event,
            .trace_context = trace_context,
            .tags = tags,
        };
        self.head = (self.head + 1) % self.buffer.len;
        if (self.count < self.buffer.len) {
            self.count += 1;
        }
    }

    pub const Iterator = struct {
        log: *const EventLog,
        current_idx: usize,
        items_yielded: usize,

        pub fn next(self: *Iterator) ?LogEntry {
            if (self.items_yielded >= self.log.count) {
                return null;
            }
            const entry = self.log.buffer[self.current_idx];
            self.current_idx = (self.current_idx + 1) % self.log.buffer.len;
            self.items_yielded += 1;
            return entry;
        }
    };

    pub fn stream(self: *const EventLog) Iterator {
        var start_idx: usize = 0;
        if (self.count == self.buffer.len) {
            start_idx = self.head;
        }
        return Iterator{
            .log = self,
            .current_idx = start_idx,
            .items_yielded = 0,
        };
    }
};

test "event_log: append and stream chronologically" {
    experimental_event_log = true;
    var log = try EventLog.init(std.testing.allocator, 3);
    defer log.deinit();

    log.append(100, .{ .actor_spawn = .{ .pid = 1 } });
    log.append(200, .{ .actor_exit = .{ .pid = 1, .reason = 0 } });
    log.append(300, .{ .network_partition = .{ .node_id = 42, .duration_ms = 5000 } });
    log.append(400, .{ .actor_spawn = .{ .pid = 2 } });

    var it = log.stream();

    const e1 = it.next().?;
    try std.testing.expectEqual(@as(u64, 200), e1.timestamp_ms);
    try std.testing.expectEqual(EventType.actor_exit, std.meta.activeTag(e1.event));

    const e2 = it.next().?;
    try std.testing.expectEqual(@as(u64, 300), e2.timestamp_ms);
    try std.testing.expectEqual(EventType.network_partition, std.meta.activeTag(e2.event));

    const e3 = it.next().?;
    try std.testing.expectEqual(@as(u64, 400), e3.timestamp_ms);
    try std.testing.expectEqual(EventType.actor_spawn, std.meta.activeTag(e3.event));

    try std.testing.expectEqual(@as(?LogEntry, null), it.next());
}
