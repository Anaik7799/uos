# 20261027-1758 — Agent-surface rule & skill mirror projection contract (SC-MIRROR-PROJ-001)

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[This contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261027-1758-agent-surface-mirror-projection-contract.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Authority: operator-directed symbiosis sync (2026-10-27). Status: development rule; runtime admission capability-specific. Read with root `AGENTS.md`, `20261001-1117` full-symbiosis rule and `20261009-0412-gleam-harness-agent-operation-contract.md`.

## 1. Canonical sources

1. `contracts/rules/*.md` is the **canonical rule home** (59 contracts).
2. The four vendor surfaces `.claude/rules`, `.codex/rules`, `.gemini/rules`, `.agents/rules` are **projections**, not forks.
3. `.agents/skills`, `.claude/skills`, `.codex/skills`, `.gemini/skills` are **symlink mirrors** whose canonical bodies live under `governance/agents/20261025-1953-imported-skills/` and `governance/agents/20261001-1118-skills/` and `plugins/*/skills/`.

## 2. Projection policy (project every canonical contract)

Every canonical `contracts/rules/*.md` is projected as a byte-identical copy into **all four** vendor `rules/` surfaces. Vendor-local adapter files (e.g. `full-symbiosis.md`, `uos-governance.md`, `20260907-1330-iam-ferriskey-nif-rule.md`) are not canonical contracts and are permitted to carry **vendor-path FQDN links and vendor frontmatter (`trigger: always_on`)** as their only per-vendor variation; their substance must stay identical.

## 3. Stale-shadow law

A short-name rule file that shadows a later timestamped canonical contract (`swarm-monitoring-protocol.md` vs `20260908-0935-…`) is a **stale shadow**. It must never be deleted and never silently diverged. Record its mapping to the canonical contract; a governed pass may preserve its bytes under `governance/sources/` and then replace it with a symlink to the canonical contract. Until then the timestamped name is canonical and agents must not treat the short name as newer authority.

## 4. Validation gate (after any mirror edit)

1. Four-mirror name-set isomorphism (`.codex` may additionally carry `README.md`).
2. JSON parse: `.claude/settings.json`, `.codex/hooks.json`, `.gemini/hooks.json`, `.agents/hooks.json`, `~/.pi/agent/mcp.json`, `~/.pi/agent/settings.json`.
3. Skill frontmatter (`---` + `name:`) for every `SKILL.md` under the canonical skill dirs.
4. Broken-symlink count = 0 across all four surfaces.

## 5. Sa-plan dependency-graph law

A sa-plan task is claimable only when its declared dependencies are complete. Filesystem/documentation work must **not** depend on grant or runtime tasks; DSA-plan deps must reflect actual blockers. A task whose substance is done but whose deps are mis-wired remains `available` — never force-complete the blocking task or mutate the Sa-plan store out-of-band (SC-JIDOKA-001).

## 6. Harness-MCP truth law

A declared MCP server in `mcp.json` / `config.toml` is **not evidence of a connected, admitted runtime surface**. Before relying on harness capabilities, verify the live surface (e.g. `describeNamespace` / actual tool listing / a heartbeat receipt). Unconnected servers are recorded as `Unavailable_observed`, not assumed callable.

## 7. Provenance

EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV. Mirroring canonical contracts is not citing their EV cycles as admitted. This contract grants no admission authority.

## Comprehensive verification checklist

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — `20261027-1758` prefix; host clock observed.
- [x] **CHK-02-TAIL** — Full Tailscale FQDN refs present.
- [x] **CHK-03-FRACT** — L0/L3/L4/L9 tags.
- [x] **CHK-04-KM** — Root policy, symbiosis rule and harness contract cross-linked.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] **CHK-05-MUDA** — No dependency/binary/registry introduced.
- [ ] **CHK-06-GRAPH** — UNRUN.
- [ ] **CHK-07-DRIVE** — UNRUN.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08..11** — UNRUN.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12..16** — UNRUN.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Independent review OUTSTANDING.
- [x] **CHK-18-JJ** — Authored additively under standalone JJ.

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

- [x] EV ceiling 93; no new EV.

</details>

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this contract grants no admission.