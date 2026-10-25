---
name: swarm-verification-expert
description: Expert for high-assurance SIL-6 mesh verification. Use when porting SwarmVerificationTools from F# to Gleam, verifying OODA loop compliance, performing fractal layer validation (L0-L7), or implementing TCP/HTTP mesh probes.
---
# Swarm Verification Expert Skill
This skill provides deep domain knowledge for verifying the health, integrity, and safety of the 16-container SIL-6 Biomorphic Fractal Mesh.
# Core Mandates
1.  **OODA Compliance**: Verify that every node completes its OODA cycle within established latency budgets:
- Agent: < 30ms
- Intelligence: < 100ms
- Cortex: < 50ms
2.  **Fractal Validation**: Enforce 7 levels of invariants:
- L0 (Constitutional): Immutable axioms.
- L1 (Cellular): Container-local health.
- L2 (Component): Inter-service contracts.
- L3 (Holon): Agentic autonomy.
- L4 (Container): Substrate isolation.
- L5 (Node): Compute plane stability.
- L6 (Cluster): Swarm-wide consensus (2oo3).
- L7 (Federation): Multi-holon coordination.
3.  **Proactive Probing**: Use non-destructive TCP and HTTP probes to verify connectivity and API readiness without impacting workload performance.
4.  **Evidence-Based Reporting**: Every verification run MUST generate a structured evidence report (JSON) for the `DigitalTwin`.
# Verification Patterns
# TCP Probe (Gleam/Erlang FFI)
```gleam
pub fn check_port(host: String, port: Int) -> Bool {
// FFI to erlang:gen_tcp.connect
}
```
# OODA Latency Check
Measure the time delta between `Observe` (Sensor Event) and `Act` (Control Command) published on Zenoh.
# Gleam Integration
Implement the `GleamSwarmVerifier` as a collection of stateless verification modules coordinated by a `VerificationOrchestrator` actor.
# Troubleshooting
- **Probe Timeout**: Check Podman network isolation settings and ensure the target service is in the same container network.
- **Drift Detected**: Run `sa-status` (or the Gleam equivalent) to compare the `DigitalTwin` model against the live substrate.
- **OODA Breach**: Analyze the `indrajaal/logs/**` stream for scheduling delays or resource contention.