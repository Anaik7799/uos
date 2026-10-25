---
name: cepaf-zenoh-expert
description: Domain-specific expert for Zenoh-based mesh communication and telemetry. Use when porting F# Zenoh logic to Gleam, managing real-time mesh data streams, or implementing situational awareness in the C3I dashboard.
---
# CEPAF Zenoh Expert Skill
This skill provides expert guidance for implementing the Zenoh messaging backbone in Gleam, ensuring real-time telemetry and control for the SIL-6 mesh.
# Core Mandates
1.  **Zenoh-Erl Foundation**: Use the `zenoh-erl` Erlang bindings via Gleam FFI for all mesh communication.
2.  **Actor-Based Sessions**: Manage Zenoh sessions using Gleam `otp` actors to handle life-cycle and automatic reconnections.
3.  **Schema Alignment**: Adhere to the established Indrajaal key expression schema:
- Logs: `indrajaal/logs/{node_id}/{container_id}`
- Telemetry: `indrajaal/telemetry/{node_id}/**`
- Control: `indrajaal/control/{node_id}/request` and `response`
4.  **Byte-Efficient Payloads**: Prefer JSON over UTF-8 BitArrays for payload encoding, consistent with the F# implementation.
# Communication Patterns
# Pub/Sub
- **Publishing**: Use `Zenoh.put` for telemetry updates.
- **Subscribing**: Use `Zenoh.declare_subscriber` with a callback that forwards to a Gleam actor.
# Queryable State (GET)
- **Declarations**: Key-value pairs intended for persistent storage should be declared as Queryables.
- **Retrieval**: Use `Zenoh.get` for point-in-time state retrieval (e.g., fetching current task status from Smriti).
# Gleam Implementation Pattern
```gleam
import gleam/otp/actor
import gleam/erlang/process
pub type ZenohMessage {
ZenohMessage(key: String, payload: BitArray, timestamp: Int)
}
// Managed Zenoh Subscriber Actor
pub fn start_subscriber(topic: String, target: process.Subject(ZenohMessage)) {
// FFI to zenoh-erl to setup subscription
}
```
# Troubleshooting
- **Session Timeout**: Ensure the Zenoh router IP/Port is correctly configured in `devenv.nix`.
- **NIF Collision**: Ensure `SKIP_ZENOH_NIF=0` is set in the environment.
- **Key Conflict**: Verify key expressions do not overlap with reserved system topics.