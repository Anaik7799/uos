# 20261027-1815 — preflight_check fix + Pi grant review request

#fractal-l0 #fractal-l3 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[This journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-1815-preflight-fix-and-grant-review-request.md) · [Sweep](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-1810-harness-tool-sweep.md) · [Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261027-1747-symbiosis-hive-execution-plan.md)

## (a) preflight_check schema mismatch — fixed

- **Root cause**: `tool_preflight_check` (and `verify_mutating_action_preflight`) decoded numeric args with strict `gleam/json` `decode.float`, which rejects JSON integers. The declared `inputSchema` types `benefit`/`cost` as `"number"` (allows int+float), so schema-valid integer input passed the MCP layer then failed the handler.
- **Fix** (minimal, in-tree pattern already used by `tool_rete_rule_conflict:1249`): `number_decoder = decode.one_of(decode.float, [decode.map(decode.int, int.to_float)])` applied to `actor`/`benefit`/`cost` in `tool_preflight_check`, and `benefit`/`cost`/`risk_score` in `verify_mutating_action_preflight`.
- **Verification**: `gleam check` in `apps/cepaf_gleam` compiles (0 errors; pre-existing unused-import warnings only). Live effect requires `gleam build` + MCP server restart (next Pi MCP refresh).

## (a) second finding — verification_run cannot spawn

`verification_run` returns `{"ok":false,"output":"Failed to run gleam check: No child processes (os error 10)"}`. The read-surface server cannot spawn the `gleam check` child (ECHILD). Flagged in sweep; needs the grant-gated build path or a fixed spawn in the Gleam server.

## (b) Pi grant — ready for independent review

- Proposal: `var/harness/20261027-1808-pi-bound-grant-proposal.json` (valid JSON; `expires_utc_us` is a decimal string of microseconds; 3 scopes; 13 read / 2 write / 8 source / 6 test paths).
- Status: **PROPOSAL_UNSIGNED**, `admission: pending_independent_review_and_harness_signature`.
- Review request: OUTSTANDING. Requires a live, independently-verified Claude/Codex session (SYNC-07); not auto-dispatched from this Pi session (no verified receiving identity transport).

## Residual

- `preflight_check`/`verification_run` live repair depends on `gleam build` + MCP restart.
- Grant admission depends on operator authorization + independent peer review + harness signature. Neither a proposal file nor a passing `gleam check` grants effect authority.

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this contract grants no admission.