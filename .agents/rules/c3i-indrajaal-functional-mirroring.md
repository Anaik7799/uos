# C3I & Indrajaal Functional Mirroring Rule (SC-C3I-MIRROR-001)

## Mandate & Scope
All applicable C3I and Indrajaal capabilities from the external authority (`/home/an/dev/ver/c3i`) are mirrored into the canonical UOS monorepo under strict Zero-Muda purity (0 Bevy, 0 Graphite, 0 foreign NIFs) and standalone Jujutsu discipline.

## Key Mirrored Pillars
1. **ZMOF Fractal Backplane**: 8-layer namespace (`indrajaal/l0/const/**` to `indrajaal/l7/fed/**`), OoZ (OTel-over-Zenoh), MoZ (MCP-over-Zenoh) implemented in `cepaf_gleam/zenoh/zmof_transport.gleam`.
2. **AG-UI 32-Event Protocol**: All 32 event variants preserved in `cepaf_gleam/agui/events.gleam`.
3. **A2UI Declarative Component Catalog**: 233 component types across 22 domains in `cepaf_gleam/a2ui/catalog.gleam`.
4. **Triple-Interface Parity**: Every capability simultaneously available across Lustre 5.6+ WebUI (port 4100), Wisp 2.2.2 REST API (port 4100), and ANSI TUI.
5. **Autonomic Homeostasis**: Dynamic PID loop ($|e| < 0.05$, Lyapunov $V(e) \le 0.001$, $\dot{V} \le 0$) serving as the orchestra Tanpura drone.
6. **Sa-Plan Sole Authority**: All jobs and workflows must execute through `sa-plan` Oban queues and Temporal state graphs (`SC-JIDOKA-001`, `SC-SA-PLAN-001`).
7. **Admitted EV Ceiling**: Pinned at `EV-93` (`SC-PROVENANCE-001`).
