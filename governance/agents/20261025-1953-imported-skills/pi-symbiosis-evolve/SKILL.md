---
name: pi-symbiosis-evolve
description: When user says `/pi-symbiosis-evolve` or requests Pi integration work.
---

# Pi-Mono Symbiosis Evolution Command

## Trigger
When user says `/pi-symbiosis-evolve` or requests Pi integration work.

## Pipeline

### Phase 1: Observe (OODA-O)
```bash
# Pi-mono build status
cd sub-projects/pi-mono && npm run build 2>&1 | tail -20

# Gleam Pi bridge status
cd lib/cepaf_gleam && gleam build 2>&1 | tail -20

# Pi integration verification slice
cd lib/cepaf_gleam && gleam test -- --module pi_integration 2>&1 | tail -20

# Search ZK for Pi symbiosis patterns
sa-plan-daemon knowledge-search "pi-mono symbiosis bridge"
```

### Phase 2: Orient (OODA-O)
- Read `pi_claude_code.gleam` for bridge state
- Read `pi_tools.gleam` for tool federation
- Read `pi_agent.gleam` for event mapping
- Build fractal-criticality matrix (L0-L7 × components × RETE-UL/ruliology × STAMP × FMEA/FEMA)
- Compare against current CLAUDE.md Pi constraints and totals

### Phase 3: Decide (OODA-D)
- If new tools detected → update federation mapping
- If AG-UI/Pi events changed → update event bridge
- If Pi runtime/protocol changed → verify JSONL + MoZ compatibility
- If any safety gate weakens (Guardian/circuit-breaker/Smriti) → block closure

### Phase 4: Act (OODA-A)
1. Remediate in P0→P3 order
2. Update affected bridge modules
3. Run `gleam test -- --module pi_integration`
4. Run full relevant test suite
5. Update Pi dashboard metrics artifact
6. Capture screenshots if UI was touched
7. Write journal entry + ingest ZK

### Phase 5: Verify (OODA-V)
```bash
cd lib/cepaf_gleam && gleam build
cd lib/cepaf_gleam && gleam test -- --module pi_integration
```

## Constraints
- SC-PI-001..010 (Pi integration)
- SC-PI-EVO-001..010 (verification)
- SC-PI-AUTO-001..008 (automation)
- SC-PI-RUNTIME-001..008 (runtime lifecycle)
- SC-GLM-ZEN-* (spans + Zenoh)
- SC-WIRE-001 (wiring guard)
- SC-MUDA-001 (zero warnings)
