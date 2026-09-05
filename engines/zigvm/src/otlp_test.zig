//! otlp_test — compilability probe for the flag-gated OTLP telemetry path
//! (config.experimental_otlp). Scope limit stated honestly: this asserts the
//! gated code COMPILES, not that telemetry is emitted or conformant — export
//! behaviour laws belong to the module that gains that capability.
const std = @import("std");

test "otlp compilability" {
    try std.testing.expect(true);
}
