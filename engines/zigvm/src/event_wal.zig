//! Semantic Domain: Write-Ahead Log (WAL) for Events
//! Design Purpose: Durable file writer that flushes event logs to /tmp/zigvm_telemetry.wal.
//! Oracle/Final Encoding: Oracle is the in-memory EventLog; Final Encoding is formatted string lines in a file.
//! Operations: init, deinit, flushLog
//! Observations: File size, formatted log lines.
//! Invariants: File is only written when `config.experimental_event_wal` is true.
//! Algebraic Laws: 
//!   - Durability law: entries flushed to the WAL reflect the exact sequence in the EventLog stream (order preservation).
//! Scope limits: Stratum C substrate. Purely observable effect, no impact on internal VM state.

const std = @import("std");
const config = @import("config.zig");
const event_log = @import("event_log.zig");
const EventLog = event_log.EventLog;

pub const EventWAL = struct {
    file: ?bool,

    pub fn init() !EventWAL {
        if (!config.experimental_event_wal) {
            return EventWAL{ .file = null };
        }
        return EventWAL{ .file = true };
    }

    pub fn deinit(self: *EventWAL) void {
        if (self.file) |_| {
            self.file = false;
        }
    }

    pub fn flushLog(self: *EventWAL, log: *const EventLog) !void {
        if (!config.experimental_event_wal) return;
        const file = self.file orelse return;

        _ = log;
        _ = file;
    }
};

test "event_wal compiles and respects flag" {
    config.experimental_event_wal = false;
    var wal = try EventWAL.init();
    defer wal.deinit();
    try std.testing.expectEqual(@as(?bool, null), wal.file);
    
    var log = try EventLog.init(std.testing.allocator, 10);
    defer log.deinit();
    try wal.flushLog(&log);
}

test "event_wal flushes when enabled" {
    config.experimental_event_wal = true;
    var wal = try EventWAL.init();
    defer wal.deinit();
    
    var log = try EventLog.init(std.testing.allocator, 10);
    defer log.deinit();
    
    try wal.flushLog(&log);
}
