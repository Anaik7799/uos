# Swarm Omni-Prover CLI Manual (v15.0.0-cps)

The `swarm` CLI is a deterministic command-line interface built in OCaml for interfacing with the 15+N+M Cyber-Physical Swarm Engine. It interacts directly with the Core Council over the Zenoh mesh.

## Installation / Compilation
Ensure you are in the `zigvm` opam switch, then build via Dune:
```bash
eval $(opam env --switch=/home/an/dev/ver/zigvm --set-switch)
dune build modules/swarm/swarm_cli.exe
```
The executable will be located at: `_build/default/modules/swarm/swarm_cli.exe`

---

## Command Reference

### 1. `swarm start <INTENT_FILE>`
**Description**: Submits a Declarative Intent payload directly to the *Synthesizer* agent, bypassing imperative scripting.
**Sub-Routine Trace**:
1. Synthesizer parses the SysML/JSON Intent.
2. Conductor calculates fiber density and spins up $N$ Worker Executors.
3. Chrono-Arbiter bounds the real-time execution.
4. Topologist boots the CRDT Working Memory layer.
5. Sensorium subscribes to physical telemetry.

**Usage**:
```bash
./_build/default/modules/swarm/swarm_cli.exe start mission_intent.sysml
```

### 2. `swarm status`
**Description**: Triggers a global heartbeat check across the Zenoh network mesh. Returns the active homeostasis state of all 15 Core Council members, the active $N$ Executor count, and the active $M$ Domain Expert count.
**Usage**:
```bash
./_build/default/modules/swarm/swarm_cli.exe status
```
**Example Output**:
```text
=========================================================
      SWARM OMNI-PROVER CLI (15+N+M CPS TOPOLOGY)        
=========================================================
Querying Zenoh Mesh for Core Council Heartbeats...
[PASS] 1. Synthesizer         [PASS] 9. Byzantine Sentinel
[PASS] 2. Cybernetic Nav      [PASS] 10. Chrono-Arbiter
[PASS] 3. Conservator         [PASS] 11. Crypto Sentinel
[PASS] 4. Bayesian Critic     [PASS] 12. Quantum Arbiter
[PASS] 5. Neural Weaver       [PASS] 13. Kinematic Weaver
[PASS] 6. Conductor           [PASS] 14. Fluidic Controller
[PASS] 7. Topologist          [PASS] 15. Hive-Mind
[PASS] 8. Sensorium           
=========================================================
Fabric Fibers (N): 20,412 Active | Domain Experts (M): 3 Active
Status: OPTIMAL (0 Invariant Failures)
```

### 3. `swarm inject-fault <AGENT_NAME>`
**Description**: Intentionally disrupts the state of a targeted Core Council agent (simulating cosmic radiation bit-flips or sensor decay). Use this to test the *Byzantine Sentinel's* BFT validation matrices in real-time.
**Usage**:
```bash
./_build/default/modules/swarm/swarm_cli.exe inject-fault Sensorium
```
**Example Output**:
```text
[Chaos Injector] Firing simulated radiation bit-flip at Sensorium
[Byzantine Sentinel] THREAT DETECTED. Quarantining state vector.
[Topologist] CRDT Working Memory remains intact.
[SYSTEM] Fault successfully mitigated. Swarm homeostasis maintained.
```

---

## Architectural Guarantees
Because this CLI interfaces exclusively through the Zenoh mesh and is compiled under OCaml 5's type safety:
- **No Data Races**: The commands will not crash the $N$ executor threads.
- **Zero-Latency Drops**: Querying `swarm status` will not block the `Chrono-Arbiter`'s nanosecond RTOS scheduling.
