# 20261028-0050 — Codex read-only harness fallback analysis

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #tailscale-web #checklist-nav

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) › [Reviews](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews) › [This review](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261028-0050-codex-readonly-fallback-analysis.md) · [Rendered view](http://nas-1.tail55d152.ts.net:4100/docs/reviews/20261028-0050-codex-readonly-fallback-analysis.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Contents: [Cause](#4-root-cause-analysis) · [Exact changes](#5-fix-taxonomy-and-minimal-proposal) · [Acceptance](#7-verification-matrix) · [Risk](#10-remaining-gaps-and-short-risk-note)

## 1. Scope & Trigger

**Recommendation: add an explicit four-tool read-only fallback in `harness/mcp.call_task_bound`, backed by a separate read-only feature-store runtime. Never synthesize a development binding or weaken an existing fence.** This makes valid diagnostic reads possible when `UOS_HARNESS_ROLE` is absent while preserving mutation refusal.

Requested tools: `harness_execution_progress`, `harness_system_feature_catalog`, `harness_system_feature_observations`, and `harness_system_feature_intent`. This is an advisory source analysis, not an implementation or execution plan. Only this requested document is written; no code/configuration, grant, task, database, release, or service is changed. Future implementation requires its own canonical Sa-plan assessment/claim and candidate-bound verification.

## 2. Pre-State Assessment

- Host observation: `2026-10-28T00:50:52Z`; `chronyc tracking` reported leap status Normal and system time `0.000236524 seconds fast of NTP time`. The requested `0050` filename prefix is retained.
- JJ change `pkyvxzuzrqyouyvnrvxpmzrmxnpmzskm`, observed commit `44f28e6f31467802c9d6744c23aabbd5ef28c413`; workspace already dirty. Principal source hashes below bind this analysis more precisely than the working-copy commit alone.
- The [00:45 command matrix](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261028-0045-uos-mcp-command-matrix-v2.json) records all four returning `UNAVAILABLE: … — role_binding_missing`. This is inherited evidence, not a sweep independently reproduced here.
- No callable UOS harness MCP tool is exposed in this session's tool inventory. Local source/policy inspection supports this requested analysis; it does not establish an admitted alternative execution path. No task/attempt, risk-preflight, active-check, or effect authority is claimed or borrowed from another session's matrix.
- Advisory toolchain preflight remains FAIL for untracked `tools/validation/verify_guardian.exe`. Left untouched; no toolchain or runtime gate is claimed passing.

## 3. Execution Detail

Applied the repository's debugging, risk-prioritization, documentation, and verification guidance. Traced the main MCP server, legacy harness dispatcher, binding loader, feature APIs/store, pure intent evaluator, execution observer, Sa-plan CLI/store opener, and existing tests. No builds, tests, mutator probes, peer messages, delegation, or external-source ingestion were performed.

## 4. Root Cause Analysis

File references below are relative to `apps/cepaf_gleam/src/cepaf_gleam/` unless explicitly qualified. Line numbers describe the inspected source.

| Boundary | Exact function/file | Finding |
|---|---|---|
| Main read surface | `mcp/server.gleam:498–509`, `tool_task_bound_feature:1012` | All four tool arms decode `params.arguments`, then call `task_mcp.call_task_bound`. The error is returned as a normal MCP tool error. |
| First failure | `harness/mcp.gleam:575`, `call_task_bound` | Calls `dev.load_binding()` before any tool-specific logic. |
| Missing role | `harness/development.gleam:189`, `load_binding` | Missing `UOS_HARNESS_ROLE` returns exactly `Error("role_binding_missing")`. A complete binding must match one historical bootstrap tuple. |
| Additional incompatible scope | `harness/system_feature_store.gleam:65`, `canonical_runtime` | Requires plan `uos/system-mcp-features/20260919-1642`, task `t1-tracker`, then `dev.fence`. The loader only accepts `uos/ecology/20260909-0146` / `HARNESSBOOT`. Supplying bootstrap environment values cannot satisfy both. |
| Pure intent unnecessarily coupled to execution | `harness/mcp.gleam:549`, `call_tool` | Calls `dev.fence` before `system_feature_intent.decide`, although that evaluator only selects two reads and returns `effects=[]`. |
| Existing bounded progress observer | `planning/execution_observer.gleam:143,169,260`, `read_tasks`, `observe`, `query` | Fixed canonical database, fixed system-features plan, `sqlite3 -readonly -json`, strict empty arguments, bounded observation, false effect/admission flags. The MCP call injects `dev.fence` as its gate. |

There is a second, less obvious problem: **the current feature-store backend is not strictly a read-only database opener.** `canonical_runtime` uses `tracking.canonical_argv` (`harness/tracking.gleam:39`) to run the normal Sa-plan CLI. `engines/hermes/modules/sa_plan/test/sa_plan_main.ml:545–547` opens ordinary commands, including `workflow history`, with `Store.open_db`. `engines/hermes/modules/sa_plan/sa_plan_store.ml:764`, `open_db`, executes schema initialization and possible migration; its schema includes `PRAGMA journal_mode = WAL` and `CREATE TABLE IF NOT EXISTS`. Allowlisting the words `workflow history` around that CLI is insufficient to guarantee no logical database mutation.

Competing explanations: a missing role explains the immediate error; an absent NIF does not explain this explicit branch. Adding a successor grant does not fix this legacy loader. Replacing only `dev.fence` with success leaves the loader and store scope problem, and reusing the CLI would introduce hidden writes. Source establishes these paths; deployed-byte identity and fresh runtime behavior remain unverified.

## 5. Fix Taxonomy and Minimal Proposal

### A. Add a narrow fallback at the shared entry point

In **`apps/cepaf_gleam/src/cepaf_gleam/harness/mcp.gleam`**, change **`call_task_bound`** and add private **`call_read_only`**. The branch structure should be:

```gleam
case dev.load_binding() {
  Ok(binding) -> call_tool(binding, name, args)
  Error("role_binding_missing") -> call_read_only(name, args)
  Error(reason) -> Error(reason)
}
```

This is proposed code, not an applied patch. `call_read_only` must match exactly the following four names; its default arm returns `Error("role_binding_missing")` without dispatching anything. Do not use the main server's `!is_mutating_tool(name)` as an allowlist: that classifier defaults unknown names to false and is much broader than these four reads.

| Tool | Body of the new `call_read_only` arm |
|---|---|
| `harness_execution_progress` | Reuse `execution_observer.query(args, fn() { Ok(Nil) }, execution_observer.observe)`. The successful callback represents an explicitly permitted observation lane, never a task lease or fabricated fence. Retain all argument, clock, source, and risk checks inside the observer. |
| `harness_system_feature_catalog` | Construct `system_feature_store.readonly_runtime()`; reuse `system_feature_api.query(args, runtime.fence, fn(digest) { system_feature_store.load(runtime, digest) })`. |
| `harness_system_feature_observations` | Use the same read-only runtime with `system_feature_api.observations`, `system_feature_store.load`, and `system_feature_store.load_ledger`, matching the existing callbacks. |
| `harness_system_feature_intent` | Call `system_feature_intent.decide(args)` and map `system_feature_intent.encode`; do not dispatch the returned `operation` or persist an intent. It remains a pure decision with an empty effect list. |

Keep **`development.load_binding`, `development.fence`, `call_tool`, `system_feature_store.canonical_runtime`, and successor grant/admission code unchanged**. In particular, do not retry through the fallback after a bound call returns a lease/epoch, scope, clock, grant, or backend error. A present but invalid role, missing later binding field, bootstrap mismatch, or expired binding remains refused. Only the exact loader result `role_binding_missing` selects this lane; never substring-match an arbitrary backend error for fallback selection.

This changes the main `mcp/server` adapter path. It does not make legacy `harness/mcp.main()` start without its binding, nor change `successor_mcp.main()` grant requirements. Those transports need no change for this request.

### B. Give the feature store a backend that cannot mutate

In **`apps/cepaf_gleam/src/cepaf_gleam/harness/system_feature_store.gleam`**, add **`readonly_runtime()`** and private **`readonly_history_run(args)`**. Reuse the existing `Runtime`, `execute`, `history`, `load_record`, `load`, `load_ledger`, and digest/canonical validation code. No Sa-plan schema or general CLI change is needed.

`readonly_runtime()` supplies an observation-only gate and the new runner. The runner must enforce these conditions independently of the outer dispatcher:

1. Accept only the exact internal argv shape `["workflow", "history", id, "--format", "json"]`; `execute` appends the last two tokens. Refuse `start`, `complete`, `fail`, activity/task/job commands, extra flags, and every other shape **before spawning a backend**. Validate `id` as exactly a `record_id` product: `uos/system-features/{feature|catalog|observation|ledger}/<valid SHA-256>`. No arbitrary workflow name, database, SQL, shell, or path comes from the caller.
2. Read the fixed `tracking.canonical_db` through the existing bounded native process adapter using a truly read-only SQLite connection. A small Gleam-owned adapter around the already-used SQLite executable is the minimal development option: `-batch -init /dev/null -readonly -json`, fixed SQL, no shell, `PRAGMA query_only=ON`, and a bounded read transaction. Do not invoke `tracking.canonical_argv`, `tools/sa-plan`, `Store.open_db`, or any schema initialization, repair, migration, or publishing path.
3. Query `sa_plan_workflow` by exact **ID**, then `sa_plan_workflow_event` ordered by `sequence`, in one transaction. Return at most three events: the third is an overflow sentinel, since existing `history` accepts only one or two. Distinguish an absent workflow from an existing workflow with empty/malformed history. Use parameter binding where supported; with the existing CLI, interpolate only a fully validated ID assembled from fixed prefixes plus hexadecimal digest, never raw input.
4. Normalize SQLite rows to the current **newline-delimited JSON objects with string fields** `sequence`, `kind`, `payload`, `occurred_at_ns`. `tracking.decode_cli` does not accept a SQLite JSON array or numeric fields unchanged. Encode through `gleam/json`; do not construct JSON by text concatenation. Only a confirmed absent workflow may produce the existing exact missing-workflow convention; other failures remain errors.
5. Keep the existing 3-second child bound, 262,144-byte store response ceiling, record/manifest limits, canonical re-encoding, and catalog/ledger digest checks. Preserve `budgeted` checks, and share one 60-second runtime budget across the complete catalog-plus-ledger observation; constructing a fresh budget per nested load must not reset the outer deadline. Refuse missing database/schema, oversized payloads, busy/timeout, bad UTF-8, incomplete records, and conflicts. No fallback create, automatic retry, or materialization.

The repository profile currently has **no `toolchains/nix-profile/bin/sqlite3`**. `execution_observer.read_tasks` already uses `/usr/bin/sqlite3` as a declared development-bootstrap host exception. Reusing that exception is a development proposal only; it is not a newly pinned or production-admitted dependency. Before operational release, bind a realized repository-pinned SQLite backend or the applicable reviewed development exception. Do not silently fetch/install a package. A new general-purpose native observer is unnecessary for this bounded fix.

The observation gate may return success without an execution lease only because this runtime's runner is restricted to read-only storage operations and the four-tool lane is explicitly allowed by server policy. It must never be wired into `canonical_runtime` or interpreted as proof of execution authority. This is Poka-Yoke at both dispatch and storage boundaries; the existing Jidoka mutation stops remain intact.

### C. Keep the outer policy and describe the surface accurately

No behavioral edit is needed in **`apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam`**: `tool_task_bound_feature` can retain its decoding, result wrapping, and deterministic unavailable errors. Keep `execute_tool`'s Jidoka check, `authz.authorize_and_persist`, path/rate/guardian controls, mutation preflight, and all six legacy mutation refusals. Do not place an early return ahead of authorization. Existing authorization counters/audit telemetry are not task/domain effect authority; read-only here means no logical control/domain database mutation.

In **`apps/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam`**, update the four entries in **`get_tool_definitions()`** (line 87) to describe binding-free diagnostic reads/pure intent evaluation, conditional on policy and available verified data. Remove misleading unconditional “admitted task-bound” wording. Input schemas need no widening. `harness/mcp.tool_definitions()` describes its separately bound legacy transport and need not be changed.

For this repository's Codex client, **`.codex/config.toml`**, **`mcp_servers.uos_gleam.enabled_tools`**, currently permits only four other read tools. If that client must expose these operations, append exactly these four names after verification and refresh its MCP connection; leave `uos_development` disabled and add no grant variables. The operator's `mcp__uos_harness` registration may be elsewhere: verify its actual tool filter instead of assuming this project's Codex config controls it. This client step is conditional configuration work, not a server code requirement.

Successful catalog/observation reads still require real caller-supplied content digests and existing canonical records. Keep exact argument sets and textual offsets (`"0"`, not numeric `0`); do not add a “latest”, arbitrary plan/database, or auto-publish fallback. Missing records remain honest errors. Intent success validates a read decision; it does not establish that either digest exists.

## 6. Patterns & Anti-Patterns Discovered

A read-classified tool can still call a schema-writing opener. A missing environment variable can conceal incompatible downstream scopes. An empty effect list and `effect_authority=false` describe a result; only restrictive dispatch plus a read-only backend prevent effects. Avoid synthetic roles, shared-fence weakening, catching every error as an availability fallback, and using a catalog declaration as proof that a runtime is operational.

## 7. Verification Matrix

These are proposed acceptance cases, **UNRUN**; no code change or test result is claimed.

| Exact test file / area | Required evidence |
|---|---|
| `apps/cepaf_gleam/test/mcp_runtime_truth_test.gleam` | Through `server.handle_request_raw`, missing role plus valid fixtures yields successful results for all four names. Missing/corrupt data yields bounded tool errors; no false success or dropped request ID. |
| New `apps/cepaf_gleam/test/harness_readonly_fallback_test.gleam` | Exact missing-role selection; wrong role, missing later field, bootstrap mismatch, expired lease/epoch, and bound backend failure cannot downgrade. Every nonallowlisted name is refused before backend dispatch. Dependency-injected counters prove no calls to `dev.call`, peers/tracking mutation, publication, claim, build, or write functions. |
| `apps/cepaf_gleam/test/system_feature_store_test.gleam` | Isolated SQLite fixtures: real read-only open; valid catalog/ledger round trip; absent versus empty/incomplete/foreign/tampered record; event overflow; strings/NDJSON compatibility; missing DB is not created; wrong schema is not migrated. All mutation-shaped runtime commands rejected before spawn. Compare schema and logical row contents before/after reads. |
| Same store tests and bounded runner | Query/operation deadlines, oversized output/payload, busy database, unknown cleanup, and concurrent writer cases. Do not assert all WAL/SHM bytes are invariant; distinguish reader bookkeeping from logical writes. |
| `apps/cepaf_gleam/test/system_feature_api_test.gleam`, `system_feature_intent_test.gleam`, `execution_observer_test.gleam` | Reuse exact-key/digest/offset validation; reject injected authority/backend/path arguments and unknown/write intents. Successful outputs retain `effect_authority=false`, `system_admission=false`, and intent `effects=[]`; progress preserves stale/unknown risk rather than inventing readiness. |
| Existing bound tests | Preserve `mcp_lists_catalog_tool_but_unbound_session_cannot_read_test` and `mcp_discovery_exposes_strict_tool_and_unbound_calls_fail_closed_test` for `mcp.handle(binding, …)`. They exercise the bound transport, not the new missing-role adapter branch; do not delete them to make the fallback pass. |
| `apps/cepaf_gleam/test/mcp_authz_wiring_test.gleam` and mutation regressions | Guardian/path/rate/Jidoka denials still dominate; six legacy mutators (`plan_add`, `plan_update`, `sa_task_claim`, `sa_task_complete`, `sa_job_enqueue`, `sa_workflow_start`) remain refused under favorable forecasts and fabricated caller identities, with zero domain writes. |
| Actual client, after candidate verification | Initialize/list/call through its real registration. Valid diagnostic fixtures succeed, errors stay typed, notifications do not dispatch, and a denied request does not kill the next read. Bind observations and machine-verifiable no-authority invariants to the same source/build candidate. |

## 8. Files Modified

Only this review document is added by this task. Existing source, tests, configs, binaries, control databases, shared journals, and unrelated dirty changes are preserved. No native Git mutation or JJ commit/bookmark/integration operation is performed.

Principal inspected SHA-256 values:

```text
f17c4f66adefc761995a07080551a9539473f9fc0d83e8d492451fa9f36c46a1  harness/mcp.gleam
5e634c84bafcd1d6eb39bcb6070984041b09ce7c30b49b613c22c71a29ea528d  harness/system_feature_store.gleam
4293b63149aed946d5326ea52565a1d59f09ce4941adeaf20e5b95e9681b7ae5  harness/development.gleam
3c65edf060b175ce59950b8cda88691b639c325295edf948bd9bdadbc9b94ca2  mcp/server.gleam
7cef170c48633862ceb9d6f76a1dff1f84943e06ef093f826548e12ce4253d56  harness/system_feature_api.gleam
0e75c796dfbc6f6c136a7ce12c9e258894fcf19530ea7626fa30ddff7436538c  harness/system_feature_intent.gleam
aba0fd8c7062f633cfeba4cb02a9c4f50f5f5830d2a21a63b84d78b7ecea86ed  planning/execution_observer.gleam
```

Paths in this hash block share prefix `apps/cepaf_gleam/src/cepaf_gleam/`.

## 9. Architectural Observations

The minimal implementation is two behavioral source files (`harness/mcp.gleam`, `harness/system_feature_store.gleam`), one tool-description update (`mcp/tools.gleam`), and targeted tests. Gleam keeps policy/dispatch; bounded native SQLite work remains behind it. Sa-plan remains the sole owner of execution state. No new runtime, schema, inference service, dependency family, or EV identifier is needed. Capability/read success never establishes system admission.

## 10. Remaining Gaps and Short Risk Note

**Risk:** removing a role requirement exposes diagnostic metadata (including task titles/worker identifiers and feature evidence) to every client already allowed to use this read transport. Confirm that visibility is intended; hashes are content selectors, not credentials. The main privilege-escalation risks are a broad fallback and hidden writes through the ordinary Sa-plan CLI. Exact four-name dispatch, no downgrade after an invalid binding, and a genuinely read-only history runner address those risks. SQLite WAL readers may update/create coordination sidecars; do not claim zero filesystem writes or use `immutable=1` on a live changing database to hide that behavior. Missing digests/records, stale risk evidence, backend availability, and the unpinned SQLite exception remain explicit limitations.

Raw FMEA for future implementation review, using ordinal analyst estimates rather than observed failure probabilities: broad dispatch/hidden CLI write `S5 O2 Det3, RPN30, F5`; diagnostic disclosure `S3 O3 Det3, RPN27`; stale progress misread as clearance `S4 O3 Det3, RPN36`. These are unmitigated design risks, not measured residual rates. Four STPA UCA types: providing unauthorized effects → exact whitelist/read-only backend; failing to provide diagnostics → preserve honest unavailable results and repair prerequisites; providing stale/out-of-order clearance → retain digests/unknown status and no effect authority; providing reads too long/repeatedly → bounded deadlines, output limits, and existing rate control.

Authority and dependency readiness precede ranking. There is no competing task selection or implementation claim here; unassessed C/T/Dep/I factors remain `[1,5]`, not invented scores. With F5 the provisional product interval is `[5,3125]`, which confers no clearance. Resolve storage/visibility policy and candidate evidence before registering and claiming implementation through Sa-plan.

## 11. Metrics Summary

Four tools traced; two behavioral source edits and one description edit proposed; zero code edits, builds, tests, effect probes, or production changes performed. Evidence is source inspection plus an inherited command matrix, not independent B2 runtime acceptance. No observed trials support a Bayesian reliability update or a measured Lyapunov derivative; both remain unassessed rather than synthetic passing metrics.

## 12. STAMP & Constitutional Alignment

This proposal separates diagnostic visibility from effect authority while preserving outer MCP policy and bound task fencing. Its read-lane exception must be explicit in the reviewed policy/specification; it does not reinterpret the general harness contract as allowing unfenced mutations. Relevant controls: SC-HARNESS-MCP-001, SC-SA-PLAN-001, SC-JIDOKA-001, SC-RISK-PRIORITY-001, and SC-PROVENANCE-001. No data/control state is admitted by this review.

## 13. Conclusion

Adopt the narrow missing-role branch plus a separate read-only store runner, retaining existing API validation and false authority/admission flags. Do not repair availability by impersonating the bootstrap or weakening canonical fences. Forecast for the first isolated candidate verification, before any restart/release: valid persisted metadata should be readable without a role while invalid binding/effect requests remain refused. Any mutation dispatch, schema/row change, authority-true output, or swallowed bound denial falsifies the design. No calibrated numerical forecast or Brier score is claimed before that trial occurs.

## Comprehensive Verification Checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Observed UTC/NTP receipt and requested timestamp prefix recorded.
- [x] CHK-02-TAIL — Full Tailnet links provided; live serving UNVERIFIED.
- [x] CHK-03-FRACT — Applicable L0/L3/L4/L9 tags provided.
- [x] CHK-04-KM — Prior review, evidence matrix, wiki/ZK and contract navigation linked; publication/index reconciliation UNRUN.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [x] CHK-05-MUDA — Document adds no dependency; fleet purity scan UNRUN.
- [x] CHK-06-GRAPH — Proposal retains Gleam policy and bounded native backend; runtime conformance UNRUN.
- [x] CHK-07-DRIVE — No storage-control operation; OS-serial interlock unchanged and runtime test out of scope.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8 — UI/acceptance execution UNRUN; source review only.
- [ ] CHK-09-MATH — Mathematical gates UNRUN; no formal proof claim.
- [ ] CHK-10-9MOD — Runtime test modalities UNRUN; acceptance cases proposed.
- [ ] CHK-11-REGR — Live transport/client regression UNRUN.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — New read dispatch/OTP behavior UNIMPLEMENTED and UNRUN.
- [ ] CHK-13-HERMES — Read-only persistence adapter and logical invariance UNRUN.
- [ ] CHK-14-ZIGVM — Kernel tests out of scope; no kernel change.
- [ ] CHK-15-MAX — Inference tests out of scope; no inference change.
- [ ] CHK-16-OTEL — End-to-end tracing/clock correlation UNRUN.

</details>
<details><summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] CHK-17-SOV — Independent candidate-bound verification/admission NOT_GRANTED.
- [x] CHK-18-JJ — Standalone JJ identity observed; no native Git mutation or integration used.

</details>
<details><summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93; EV-94..109 remain NOT_ADMITTED. Source hashes and inherited evidence are distinguished. No EV number minted; runtime deployment identity remains UNVERIFIED.

</details>

[Previous: broader MCP failure analysis](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261028-0038-codex-uos-mcp-analysis.md) · [Next: governing harness contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning)

**UOS footer:** advisory source review; no mutating authority, runtime admission, or release is granted.
