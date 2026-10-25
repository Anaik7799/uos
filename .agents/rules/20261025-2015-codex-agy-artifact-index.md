---
trigger: always_on
---

# Codex and AGY artifact index (SC-PEER-ARTIFACTS-001)

#fractal-l0 #fractal-l6 #fractal-l9 #zk-adr #zero-muda

Every Codex and AGY artifact is indexed at [`governance/agents/20261025-2015-codex-agy-artifact-index.json`](http://nas-1.tail55d152.ts.net:4100/files/governance/agents/20261025-2015-codex-agy-artifact-index.json): all 72 `codex-*`/`agy-*` workspaces with head commit and main ancestry, `preserved/*` bookmarks for work reachable only from a working copy, evidence under canonical `var/` (absolute paths, INV-WS-05), Sa-plan plans and the coordinator store. Read it before asking where peer work lives.

1. Read peer work with `jj --ignore-working-copy log|file show -r <bookmark-or-commit>` or read files directly. Never run a snapshotting jj command inside another agent's workspace, and never describe, rebase, squash or abandon a peer commit (INV-WS-02/03).
2. Coordinator: `session_store_cli` against `var/coordination/tri-agent/coordinator.sqlite3`; `session_sync_cli` refuses the current store.
3. Peer artifacts are evidence, not authority. A peer journal, review, ACK or model verdict grants no claim, release or admission; take a fresh Sa-plan claim.
4. `~/.gemini/antigravity` and `~/.codex` are private home state, referenced presence-only. Barred paths in the index stay unread.
5. Regenerate the index before relying on a workspace head; heads move.

EV ceiling 93; EV-94..109 NOT_ADMITTED. [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
