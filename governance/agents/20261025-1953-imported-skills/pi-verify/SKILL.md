---
name: pi-verify
description: "Verify Pi symbiosis integration — run after every feature"
---

# Pi Symbiosis Verification

Run the complete Pi x C3I symbiosis verification suite.

## Required flow

1. **Pi build verification**
   ```bash
   cd /home/an/dev/ver/c3i/sub-projects/pi-mono && npm run build
   ```

2. **Gleam build verification**
   ```bash
   cd /home/an/dev/ver/c3i/lib/cepaf_gleam && gleam build
   ```
   Must compile with 0 errors/warnings including Pi bridge modules.

3. **Pi integration tests**
   ```bash
   cd /home/an/dev/ver/c3i/lib/cepaf_gleam && gleam test -- --module pi_integration
   ```

4. **Full regression (as required by feature scope)**
   ```bash
   cd /home/an/dev/ver/c3i/lib/cepaf_gleam && gleam test
   ```

5. **Bridge module inventory (6/6)**
   Verify these files exist and compile:
   - `bridge/pi_agent.gleam` (L6, event bridge)
   - `bridge/pi_zenoh.gleam` (L6, Zenoh publisher)
   - `bridge/pi_tools.gleam` (L3, tool federation)
   - `bridge/pi_session.gleam` (L3, session bridge)
   - `bridge/pi_provider.gleam` (L5, provider bridge)
   - `bridge/pi_claude_code.gleam` (bidirectional Pi↔AG-UI bridge)

6. **Federation + event parity checks**
   - Tool federation target: 93 total (6 Claude + 14 Pi + 73 C3I MCP) unless documented change
   - Event mapping parity validated (Pi events ↔ AG-UI)

7. **Safety + transport checks**
   - Guardian gating for L0/privileged operations
   - Circuit breakers active for Pi LLM calls
   - Smriti.db persistence intact (prod path)
   - MoZ + Zenoh publish path intact
   - AG-UI + A2UI payload validation intact

8. **KPI + observability update**
   Update Pi dashboard artifact with latest metrics and verify Pi OTel spans are published.

9. **ZK ingest**
   ```bash
   cd /home/an/dev/ver/c3i && ./sub-projects/c3i/target/release/sa-plan-daemon ingest-docs
   ```

## Success criteria
- `npm run build` in pi-mono: PASS
- `gleam build`: 0 errors/warnings
- `gleam test -- --module pi_integration`: PASS
- Bridge modules: 6/6 present and compiling
- Tool/event parity checks: PASS
- Safety/transport checks: PASS
- ZK ingest: PASS
