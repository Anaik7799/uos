# Tailscale FQDN Web Navigation & Ingress Contract

- **Contract ID**: `SC-TAILSCALE-WEB-001`
- **Domain**: Web Ingress, Telemetry, and Living Knowledge Navigation
- **Authority**: UOS Operational Policy / Operator Directive
- **Tailnet Base FQDN**: `nas-1.tail55d152.ts.net` (Tailscale IP: `100.87.7.78`)
- **Primary Web Port**: `4100` (Gleam Lustre WebUI / Wisp REST API / Mist HTTP)
- **Peer Runtime Host**: `vm-1.tail55d152.ts.net` (Tailscale IP: `100.78.98.18`, Port `8088`)

## 1. Universal Tailscale FQDN Link Rule
All generated dashboards, web pages, wiki articles, Zettelkasten decision records, journals, and reports MUST provide full, clickable Tailscale FQDN links using the format:
`http://nas-1.tail55d152.ts.net:4100/<path>`

## 2. Canonical Route Directory

| Surface | Path | Full Tailscale FQDN Link | Content / Purpose |
|---|---|---|---|
| **Main Cockpit** | `/` | `http://nas-1.tail55d152.ts.net:4100/` | System Overview, Health Badges, API Explorer |
| **Planning Cockpit** | `/planning` | `http://nas-1.tail55d152.ts.net:4100/planning` | 8-panel SIL-6 Task Board, OODA, Safety Kernel, Dark Cockpit |
| **AG-UI Stream** | `/ag-ui/events` | `http://nas-1.tail55d152.ts.net:4100/ag-ui/events` | 32-event SSE real-time streaming telemetry bus |
| **Wiki Corpus** | `/wiki` | `http://nas-1.tail55d152.ts.net:4100/wiki` | Hermes Wiki Master Index & Living Knowledge Graph |
| **ZK Master MOC** | `/zk` | `http://nas-1.tail55d152.ts.net:4100/zk` | Master Map of Content & 16 Architectural Decision Records |
| **Pages API** | `/api/v1/pages` | `http://nas-1.tail55d152.ts.net:4100/api/v1/pages` | Typed JSON listing of all 31 C3I pages |
| **Health API** | `/api/health` | `http://nas-1.tail55d152.ts.net:4100/api/health` | Substrate, BEAM, and mesh health status |
| **Verification API** | `/api/verification/status` | `http://nas-1.tail55d152.ts.net:4100/api/verification/status` | Formal verification & parity verification status |
| **Zenoh Mesh API** | `/api/zenoh/health` | `http://nas-1.tail55d152.ts.net:4100/api/zenoh/health` | Zenoh session, throughput, and topic health |

## 3. Machine Enforcement
1. Validated via `tools/uos web-links` CLI command.
2. Verified by UOS admission gate `tools/uos gate G-TAILSCALE-WEB`.
3. Tracked under `EV-18` in `tools/uos doctor`.
