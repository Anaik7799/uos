# 20261027-1920 — Critical-interface formal checks (specifications)

#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[This spec](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261027-1920-mcp-critical-interface-formal-checks.md) · [Sweep](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-1810-harness-tool-sweep.md)

Status: **specifications** (the formal-specification key of two-key verification). Runtime/proof execution is the other key and remains UNRUN for the items so marked. Gospel/Lean-style contracts; not yet machine-checked.

## CI-1 — Bounded subprocess boundary (`ecology_capability_ffi:run_bounded|run_bounded_env|run_bounded_cd`)
- Pre: `Path` is a literal absolute/`uos_root`-resolved executable; `Args` is a list of non-NUL strings each ≤65536 bytes; `TimeoutMs ∈ [1,60000]`; `Cwd` (cd variant) is absolute and at-or-under `uos_root()`.
- Post: returns `{ok,{ExitCode,Output}}` with `|Output| ≤ 1048576`, or `{error,Reason}`; never blocks past `TimeoutMs+1000`; process-group cleaned.
- Invariant: no env injection (only allowlisted `UOS_SA_PLAN_DB` absolute value); no `..` escape from root; backend absence is reported, never simulated.
- Evidence: source `ecology_capability_ffi.erl`; `bounded_process_lifecycle_test`, `bounded_process_utf8_test` (suite green).

## CI-2 — MCP tool argument validation (`server.gleam` `decode.subfield(["params","arguments",…])`)
- Invariant: every required parameter is enforced; missing required params return a structured validation error, never a crash.
- Evidence: 25 required-arg tools correctly refused `{}` in the 53-tool sweep.

## CI-3 — `preflight_check` SEU gate
- Pre: `actor`,`action` non-empty strings; `benefit`,`cost` are JSON numbers (int **or** float).
- Post: returns a certificate `{status, certificate_id, actor, action, seu_score, gate}`; integer inputs accepted.
- Fix: `number_decoder = one_of(float, map(int, int.to_float))`.
- Evidence: end-to-end canary — integer args → `approved` (`seu_score:1.0`, `gate:PASS`).

## CI-4 — `verification_run` bounded check
- Post: `{ok, output(≤2000 graphemes), warnings, errors}` with `ok = (exit_code == 0)`; runs `gleam check` in `apps/cepaf_gleam` via BEAM `open_port` (no fork/wait ECHILD).
- Evidence: source rewrite; canary pending server restart.

## CI-5 — Privileged feature/execution role guard
- Invariant: `harness_execution_progress`, `harness_system_feature_{catalog,observations,intent}` return `role_binding_missing` (fail-closed) until a grant binds a role.
- Evidence: sweep — all four refused `role_binding_missing`.

## CI-6 — Mutation authority (`sa_task_claim|complete`, `sa_job_enqueue`, `sa_workflow_start`, `plan_add|update`)
- Invariant: required fields enforced; effects only under canonical Sa-plan/Planning authority; append-only ledger; no out-of-band mutation.
- Evidence: empty-arg validation refusals observed; `sa_plan` records this session additive only.

## CI-7 — Mirror-projection contract (`SC-MIRROR-PROJ-001`)
- Invariant: every canonical `contracts/rules/*.md` projected to all four vendor `rules/` surfaces; stale shadows preserved + mapped; 4-mirror isomorphism; broken-symlink count = 0.
- Evidence: 29 contracts projected; 4-mirror SAME; 0 broken symlinks.

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Specifications advise; machine proof (Lean/Gospel/Rete) of CI-1..CI-7 is UNRUN.