//! a2ui — EXPERIMENTAL, flag-gated (config-style `experimental_a2ui`, default
//! off) placeholder for an agent-to-UI event surface over the event log.
//! Semantic domain: none yet — `startServer` is a deliberate no-op stub; no
//! laws are stated because no behavior is claimed (FM-OBS-1: a stub must not
//! pose as a capability). Stratum C adjacent; nothing in Stratum A may depend
//! on this module.
const std = @import("std");
const event_log = @import("event_log.zig");

pub var experimental_a2ui: bool = false;

pub fn startServer(allocator: std.mem.Allocator, log: *const event_log.EventLog, port: u16) !void {
    _ = allocator;
    _ = log;
    _ = port;
    if (!experimental_a2ui) return;
}

test "a2ui compilability" {
    // Just ensuring the file compiles cleanly
    try std.testing.expect(true);
}
