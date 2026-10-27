# 20261027-1805 — UOS harness → Pi MCP connection (Zenoh-backed) journal

#fractal-l0 #fractal-l3 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[This journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-1805-uos-harness-pi-mcp-connection-journal.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

## 1. Scope & Trigger
Operator: fully connect the UOS harness to Pi via MCP; use Zenoh for control and data.

## 2. As-is (diagnosis)
- UOS-local Gleam/OTP harness MCP **built and ready**: `cepaf_gleam@mcp@server.beam` and `cepaf_gleam@harness@successor_mcp.beam` present; `erl` 29 present at `toolchains/nix-profile/bin/erl`.
- Zenoh **active**: `c3i-zenoh-router-1.service` running; `zenohd` process up (`/zenohd -c /zenoh.json5`).
- `~/.pi/agent/mcp.json` registered only the **external** `zigvm-harness` (`/home/an/dev/ver/zigvm`) and `hermes-ops` (`/home/an/NAS-setup/harness-bionic`) trees — not the UOS harness.

## 3. Execution Detail
1. Backed up `~/.pi/agent/mcp.json` → `mcp.json.bak-20261027-1758`.
2. Added `uos-harness` (read surface: `cepaf_gleam@mcp@server:main()`) and `uos-harness-dev` (grant-gated effect surface: `cepaf_gleam@harness@successor_mcp:main()`), `cwd=/home/an/NAS-setup/uos`, `ERL_CRASH_DUMP_SECONDS=0`.
3. JSON validated.
4. **Smoke test** (stdio JSON-RPC initialize + tools/list): server `c3i-planning-mcp` v1.0.0 answered and enumerated ~40 tools.

## 4. Tool surface observed
Planning (plan_status/list/get/add/update/search), system/health/dashboard, **Zenoh** (`system_zenoh`, `mesh_topology`), verification (`verification_run`, `integrity_check`), fractal/OODA/prajna/dark-cockpit, forecast/lyapunov/preflight, **Sa-plan** (`sa_plan_status`, `sa_plan_status_for`, `sa_plan_list`, `sa_task_claim`, `sa_task_complete`, `sa_job_enqueue`, `sa_workflow_start`), STPA/Rete/ruliad, **ZK** (`zk_transclude`), **KM** (`knowledge_search`), feature tracker/catalog/observations/intent/execution-progress, capability inventory, holon/swarm/agent-hierarchy.

## 5. Verification Matrix
Admiralty B2 (author): server launch + tool enumeration observed directly. JSON parse of mcp.json OK. This is a transport-surface observation, not runtime admission of any mutation tool.

## 6. Remaining Gaps / boundaries
- The new `uos-harness` surface becomes callable on the **next Pi MCP refresh/session** (this running session loaded its server list at startup).
- **Effect/grant surface** (`uos-harness-dev`, successor_mcp) refuses startup without `UOS_HARNESS_GRANT_PATH`+`_SHA256`; no Pi-bound grant minted — expected fail-closed.
- Zenoh is the harness mesh transport (router active); direct Zenoh key/board control still requires the reviewed grant and a controlling session.

## 7. Conclusion
UOS harness is now wired into Pi's MCP config and proven launchable; it exposes the Zenoh/ZK/KM/Sa-plan control-and-data surface. Live in-session call still needs a Pi refresh; effect mutators remain grant-gated.

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this contract grants no admission.