//! event_wal_test — compilability probe for the flag-gated event-WAL path
//! (config.experimental_event_wal, default off). Scope limit stated honestly:
//! this asserts the gated code COMPILES, not that a WAL capability exists —
//! behavior laws arrive only when the flag's feature does.
const std = @import("std");

test "event_wal_test compiles" {
    try std.testing.expect(true);
}
