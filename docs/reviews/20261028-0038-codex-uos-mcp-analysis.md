# 20261028-0038 — Codex analysis of remaining UOS MCP failures

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #tailscale-web #checklist-nav

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) › [Files](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews) › [This review](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261028-0038-codex-uos-mcp-analysis.md) · [Rendered view](http://nas-1.tail55d152.ts.net:4100/docs/reviews/20261028-0038-codex-uos-mcp-analysis.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Contents: [Scope](#1-scope--trigger) · [Causes](#4-root-cause-analysis) · [Minimal proposal](#5-fix-taxonomy-and-minimal-change-proposal) · [Acceptance](#7-verification-matrix) · [Gaps](#10-remaining-gaps)

## 1. Scope & Trigger

Analyze the operator-reported post-hardening sweep: **11 `isError` results = four `role_binding_missing` + six `UNAVAILABLE` legacy mutators + one missing-row `plan_get`**. No implementation, builds, mutator probes, grants, release, or service restart is authorized by this review. The supplied aggregate is treated as operator evidence; its raw request/response transcript was not supplied or independently reproduced here.

**Finding:** the 11 results are accounted for by explicit source branches. They do not establish 11 crashes. The binding failures expose obsolete bootstrap wiring, including an incompatible pair of task scopes. The six mutator refusals preserve the intended authority boundary. The absent task is an expected lookup outcome currently represented as an untyped backend error. Separate uncontained native exceptions and response-classification weaknesses prevent a general non-throw guarantee.

“Every invocation deterministic and non-throw” should mean a stable outcome category and valid, bounded protocol response for fixed request, authority, backend state, and policy inputs. It cannot mean every command succeeds, every response is byte-identical despite timestamps/rate windows, or an arbitrary client never throws on `isError`. Authority refusal must remain observable; client adapters should return typed outcomes rather than raise for expected refusals. Catastrophic VM/OS failure remains outside a response-totality guarantee.

## 2. Pre-State Assessment

- Observed host UTC: `2026-10-28T00:37:16Z`; `timedatectl` reported `NTPSynchronized=yes`. No numerical NTP offset was measured. The filename prefix is the operator-requested identifier, not a claim about observation seconds.
- Standalone JJ observation: change `pkyvxzuzrqyouyvnrvxpmzrmxnpmzskm`, commit `6cc13fbb412e7f52fef86fd71cce0bdd95353238`, using `--ignore-working-copy`. This is not a fresh snapshot of the dirty workspace; inspected file digests below bind the principal source evidence.
- Session tool discovery exposed only `uos_gleam` read-file, knowledge-search, capability-inventory, and selected-plan status tools. No callable `uos_harness` sweep, write, or claim surface was available. Used harness reads/status/inventory where exposed and local read-only source inspection for search/line references. The explicitly requested review is the sole local file addition. No bootstrap identity was synthesized.
- Fresh harness inventory: 65 declared, 12 statically unavailable, 53 declared-unprobed; `effect_authority=false`, admission unknown/not granted. This is catalog evidence, not a new 65-command sweep.
- Fresh harness Sa-plan status for `uos/symbiosis-sync/20261027-1741`: total 8, completed 2, ready 1, executing 0, `authority=report_only`. This does not identify or claim an authorized task for this review. No task/attempt, risk-preflight receipt, or active-check receipt is claimed.
- Advisory toolchain preflight was already FAIL: untracked `tools/validation/verify_guardian.exe`. Left untouched; no build/toolchain cleanliness claim.

## 3. Execution Detail

Read the debugging, verification-before-completion, UOS risk-prioritization/SOP/bindings, docs-design, and harness-operation policies. Inspected dispatcher, catalog, legacy binding/fences, feature runtime, successor admission, NIF/SQLite adapters, stdio/Zenoh entry points, and existing MCP tests. Compared the earlier [tool sweep](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-1810-harness-tool-sweep.md) and [review bundle](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-1910-code-review-bundle.md) with current source. Those historical documents predate the supplied post-hardening result and do not substitute for it.

No agent delegation, board/Zenoh messages, external-tree ingestion, dependency provisioning, database writes, source edits, or test execution was performed. The recommendations below are advisory dependencies and acceptance criteria, not an executable task queue; implementation must first be registered, assessed, and claimed through canonical Sa-plan.

## 4. Root Cause Analysis

Source references are repository-relative with observed line numbers; all are accessible under the [Tailnet file viewer](http://nas-1.tail55d152.ts.net:4100/files/). The main sources are [server.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam), [development.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam), [harness/mcp.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/harness/mcp.gleam), [system_feature_store.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/harness/system_feature_store.gleam), [planning.rs](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/native/c3i_nif/src/planning.rs), and [db.rs](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/native/c3i_nif/src/db.rs).

| Commands | Exact path and cause | Classification |
|---|---|---|
| `harness_system_feature_catalog`, `harness_system_feature_observations`, `harness_system_feature_intent`, `harness_execution_progress` | `server.gleam:499–509,1006–1021` decodes arguments and calls `task_mcp.call_task_bound`; `harness/mcp.gleam:575–580` first calls `dev.load_binding()`. `development.gleam:189–193` maps absent `UOS_HARNESS_ROLE` to `Error("role_binding_missing")`. Server converts that returned error to `result.isError=true`. | Expected immediate refusal; source wiring also prevents ordinary general-purpose admission. |
| `plan_add`, `plan_update`, `sa_task_claim`, `sa_task_complete`, `sa_job_enqueue`, `sa_workflow_start` | `server.gleam:214–225` classifies exactly these six as mutating. `execute_tool:378–424` runs Jidoka, authz, then preflight. Approved preflight returns literal `UNAVAILABLE: … Transport-bound task authority unavailable; legacy mutation refused; no action or verification was performed.` Veto returns a tool error. No approved branch enters the legacy mutation handler. | Deliberate deny-by-default containment; not an unavailable compiler/database and not fixed by lower risk or caller identity. |
| `plan_get` with nonexistent probe ID | `server.gleam:555–563` calls `c3i_nif.plan_get_task`. `planning.rs:92–115` uses `query_row` without optional-row handling. Missing row becomes a SQLite error, `db.rs:75–101` stringifies it, and `planning.rs:114` returns `Ok("{\"error\":…}")`. `server.gleam:1663–1691` recognizes the top-level error key and sets `isError=true`. | Domain lookup failure, already returned normally on this path. Not evidence of SQL injection, schema loss, or a NIF panic. |

### Binding failure hidden behind the first missing variable

`development.gleam:189–234` requires all seven launcher variables: role, plan, task, worker, attempt, session, epoch. It then accepts only the literal historical tuple: role `development`, plan `uos/ecology/20260909-0146`, task `HARNESSBOOT`, worker `codex-01a083d2-harness`, attempt 2, session `01a083d2-baa3-7783-8e45-5357cc9e96d8`, epoch 1. Other complete tuples produce `development_bootstrap_grant_mismatch`. These are source literals, not authorization to reuse them.

Catalog and observations then use `system_feature_store.canonical_runtime:65–91`, whose fence first requires plan `uos/system-mcp-features/20260919-1642` and task `t1-tracker`. **No tuple accepted by `load_binding()` can also satisfy this fence.** With well-formed arguments these two commands cannot reach their store successfully through this path, even if all missing variables are supplied. Malformed arguments may instead fail validation first.

Intent and progress do not use that feature-store scope check, but call `dev.fence`; `development.gleam:502–530` requires canonical task state, coordinator lease/epoch, clock continuity, and a 70-second remaining budget. Availability of the old task/leases was not tested. `execution_projection.gleam:10` also fixes progress to the system-features plan; this is a scoped projection, not a generic arbitrary-plan query. `system_feature_intent.decide` only selects catalog/observations reads and emits an empty effects list, yet still correctly traverses its current binding gate.

The successor is a distinct authority mechanism: `successor_mcp.gleam:48–60` loads `admission.load()`; `admission.gleam:586+` reads reviewed grant path/digest. The legacy `call_task_bound` path does **not** call this loader. Merely adding `UOS_HARNESS_GRANT_PATH`/`SHA256` to the old server cannot repair these four commands. Do not replace the loader with `Ok(Binding(...))` or remove the store scope check.

### Native exceptions and classification gaps beyond these 11 results

1. The Gleam declaration `c3i/nif.gleam:51–52` promises a `String`, but `planning.rs:93` maps `open_db()` failure to `rustler::Error::Term` and propagates it. Other planning reads (`plan_status`, pending/list/search) likewise propagate open/query errors. A Rustler error term can raise a BEAM exception before `tool_adapter_response` receives any string. Neither `server.process_line/execute_tool` nor `bridge/zenoh_mcp.gleam:100` contains that exception. Returning Gleam `Result` from unrelated branches does not catch it.
2. `adapter_failed` only recognizes JSON `error`, `ok=false`, or `status="error"`. Malformed adapter JSON falls through to success content. Legacy Rust error formatting escapes only quotes, not all JSON control/backslash characters, and serialization fallbacks such as `{}`/`[]` can hide a failure. Do not apply JSON validation to genuine plain-text tools; validate at each declared JSON adapter boundary.
3. `tools.gleam:18–49` filters only static unavailable tools and NIF absence. It does not model the six permanent legacy refusals or the bootstrap restriction. `server.gleam:974–1004` inventory counts only the 12 static unavailable names, so disabled mutators and impossible binding scopes remain `declared_unprobed`. Different catalogs describe different availability predicates.
4. Legacy mutation arms remain inside private `execute_available_tool` and legacy handler functions (`server.gleam:438+`, `1031+`). They are unreachable from current `execute_tool` for these six names. Retaining them creates a future regression risk, not proof of an active bypass.
5. Jidoka/authz denials currently use JSON-RPC errors, while preflight/authority/backend denials often use `result.isError`. Existing excessive-risk/negative-utility tests in `mcp_runtime_truth_test.gleam` still expect JSON-RPC `-32001`; the hardening branch now returns a tool error. This is a source-visible test expectation mismatch, not a freshly observed test failure.

### Competing hypotheses and disconfirmation

| Hypothesis | Evidence against / discriminating evidence | Verdict |
|---|---|---|
| All 11 are transport crashes | Explicit returned tool-error branches account for all 11. Raw client exceptions were not supplied. | Unsupported; investigate actual transport death separately. |
| Set role or provide a reviewed successor grant and all four work | Literal bootstrap match, mutually incompatible feature task scope, and no successor loader on this path. | Disconfirmed by source. |
| Mutators need valid payload identity or favorable forecast | Approved preflight still returns a literal refusal before handlers. | Disconfirmed by source. |
| No rows means the database is broken | `query_row` rejects absence; absent probe ID is sufficient. A database-open failure follows a different path. | Not required to explain supplied result. |
| Existing error conversion proves every command non-throw | Native error propagation occurs before conversion; malformed JSON is not rejected. | Disconfirmed by source. |

## 5. Fix Taxonomy and Minimal Change Proposal

Keep Gleam/OTP responsible for policy, routing, bounded dispatch, and verdicts. Native changes, if selected, only normalize bounded data/error results. These changes require development task authority and candidate-bound review before execution.

1. **Standardize outcomes at the existing dispatcher boundary (Poka-Yoke).** Introduce a small Gleam outcome type covering success, not-found, invalid arguments, binding/authority refusal, unavailable, backend failure, and uncertain outcome. Use one encoder preserving request ID, stable machine code, reason, retryability, and effect state. Preserve existing text content for compatibility; add a versioned machine-readable body. Failed/refused operations retain `isError=true`; missing rows should have a stable `NOT_FOUND` code (retain `isError=true` for compatibility). Pure successful reads can report `effect_authority=false`; do not globally label authorized successor effects this way. Malformed JSON-RPC/unknown methods remain protocol errors; valid tool requests receive tool outcomes, including policy denials. If the actual client wrapper raises on tool errors, make its boundary return this discriminated result; do not mislabel refusals as successful effects.

2. **Make catalog and legacy dispatch agree (Jidoka/Muda).** Centralize the six-name legacy deny list and the four binding requirements in Gleam capability metadata shared by tools/list, inventory, and execution. Add an explicit `unavailable_on_legacy_transport` reason for the six and `binding_required`/scope limitations for the four. The minimal safe option is to exclude unavailable/unusable entries from operational discovery while retaining them in the full inventory; direct calls still return deterministic refusals. After Jidoka/authz checks, reject known legacy-disabled mutators before heuristic preflight, which cannot grant their missing authority. Preserve bypass refusal and audit semantics. Remove the six unreachable legacy dispatch arms/handlers from this server so a later catalog change cannot reactivate them accidentally. Do not forward them to Planning.db or infer a successor command mapping from caller fields.

3. **Repair read binding only through reviewed authority (separate capability step).** Non-throw refusal does not require enabling these four APIs. For successful use, accept a validated, scoped read context from the reviewed launcher/admission mechanism and pass it explicitly into feature/progress dispatch. Make the accepted task scope and store scope agree; retain canonical Sa-plan/coordinator/clock checks and digest/pagination constraints. Keep the old one-time bootstrap isolated. Extend the successor's finite operation allowlist and schemas only if those read APIs are intentionally admitted there; they are not automatically successor commands today. No default role, environment-only impersonation, generic unscoped reads, or grant in request arguments. Keep this step deferred if a reviewed scope is unavailable.

4. **Normalize native failures without a broad NIF rewrite (Poka-Yoke).** At the planning/native call boundary, add a narrow exception-safe adapter returning a Gleam-visible `Result`, with Gleam mapping it to the common outcome. Apply it to all exposed native adapter calls that can raise, including failures before a string exists. Exception capture/encoding may use a minimal Erlang ABI helper; policy and deadlines remain in Gleam. Validate declared JSON responses; malformed or wrong-shaped data is `BACKEND_PROTOCOL_ERROR`, never success. Do not catch around a completed mutation and invent “not performed”: if dispatch may have occurred, return uncertain, require reconciliation, and prohibit automatic retries. Never include secret/raw stack data in public errors.

   For stable `plan_get` absence, change the existing Rust query to typed optional-row handling (`OptionalExtension` inside the closure before `execute_with_backoff` erases the error kind), serialize `NOT_FOUND` with `serde_json`, and encode open/query/serialization failures explicitly. Preserve the found-task object for compatibility. Avoid matching localized SQLite text in Gleam. This small native change needs the governed NIF rebuild/re-pin and ABI check; if that release is deferred, safe containment can land first while the legacy missing-row payload remains an explicit tool error.

5. **Bound execution and repair tests before claiming totality (Jidoka).** Add a finite monitored execution boundary under Gleam for read/native handlers, preserving serving-process rate state and audit behavior; do not move authz into a fresh process per call and reset its counters. A response timeout alone does not cancel a dirty NIF or bound accumulated workers. `db.rs` currently combines a 5-second busy timeout with up to ten jittered exponential sleeps (about 20.46 seconds plus jitter and repeated SQLite waits). Cap work against an explicit deadline and prevent timed-out workers accumulating; if native cancellation cannot be proved, use a supervised isolated backend rather than claiming a killed BEAM caller stopped native work. Reuse the bounded stdio transport where practical: `mcp_stdio_ffi` checks length only after `io:get_line` and has no partial-frame deadline, while the in-process raw entry has no equivalent frame-size guard. Keep this transport work separate from merely classifying the 11 known outcomes.

Smallest deliverable for the reported results: common typed refusal/not-found classification, truthful shared availability metadata, and contained native error normalization. Successful mutations and successful privileged reads are separate admission work, not prerequisites for making denied invocations safe. No NIF migration, new runtime, dependency, or broad architecture rewrite is proposed.

## 6. Patterns & Anti-Patterns Discovered

Returned tool errors are valuable negative evidence. “Zero `isError`” is an unsafe acceptance target for a no-grant sweep. Distinguish capability declaration, adapter presence, binding readiness, successful read, and effect authority. A favorable forecast cannot supply any of the latter. A missing first binding field can conceal an impossible downstream scope conjunction. Native functions declared as strings need explicit exception containment; string inspection after the call is insufficient. Challenge any proposed catch-all with a failure after dispatch and verify that it yields uncertainty, not a false no-effect receipt.

## 7. Verification Matrix

| Evidence/check | Actual state in this review | Implementation acceptance criteria |
|---|---|---|
| Operator sweep, 4 + 6 + 1 | Supplied aggregate; raw transcript unavailable | Retain exact requests/responses and client exception behavior, distinguish expected refusal from transport failure. |
| Source traces and incompatible scope | Inspected at hashes below | Tests show ordinary complete bindings cannot silently reuse the bootstrap; reviewed valid scope succeeds only in its intended lane. |
| Harness inventory and Sa-plan selected status | Fresh observed MCP responses | Catalog, inventory, direct-call refusal, and runtime availability use the same predicate; no admission implied. |
| Missing-row behavior | Source-confirmed; no live lookup rerun | Isolated fixture tests: known ID, absent ID, empty/mistyped ID, missing DB, wrong schema, permission failure, locked DB, JSON control characters. Missing ID is stable `NOT_FOUND`; backend faults are distinct. |
| Six mutation paths | Source-confirmed fail-closed branch | Each command with `{}`, valid-looking payload, caller identity, favorable/vetoed forecast, and bypass flags causes zero handler/backend mutation dispatches. Assert policy/refusal precedence and byte/state invariance in isolated fixtures. |
| Four feature/progress paths | Source-confirmed first refusal and deeper guards | Missing role/each field, wrong role/scope, invalid grant digest, stale attempt/epoch/lease, missing evidence, valid scoped read; intent never acquires effects. No hard-coded bootstrap impersonation in tests. |
| Native exception/protocol containment | Gap identified; tests UNRUN | Inject throw/exit, NIF absence, malformed/wrong-shape JSON, output overflow, deadline and late completion; next valid request still works with ID preserved. Assert no silent default success and no automatic retry. |
| Protocol/frontends | Source inspected; runtime UNRUN | Same outcome classification through stdio, raw handler, Zenoh, and actual client adapter. Malformed requests produce protocol errors; recoverable tool refusals are values; notifications produce no reply. Do not invoke effect tools from notifications. |
| Boundedness | Existing limits inspected; total deadline unproved | Partial/oversized frames, busy SQLite, output ceiling, concurrent timeouts, worker cleanup, and monotonic deadline tests. Demonstrate native work stops or remains safely bounded after timeout. |
| Existing tests | Read, not executed | Update stale preflight assertions and absent-NIF/catalog expectations; assert exact codes and no effects, not merely substring `error`. Enumerate every declared command against fixtures. |

No build, unit suite, checker gate, formal proof, peer verification, or new runtime sweep is reported passing. The author's fresh harness observations are not independent second-key evidence. Future acceptance requires fresh runtime observations plus machine-verifiable specification at the same candidate. Expected refusals may remain `isError=true` after all implementation acceptance checks pass.

## 8. Files Modified

Only `docs/reviews/20261028-0038-codex-uos-mcp-analysis.md` was added by this review. Source/tests/configuration, native artifacts, databases, coordinator state, grants, bookmarks, and shared journals were not edited. Existing dirty state is not attributed to this task. No native Git command or JJ mutation was used.

Principal inspected source SHA-256 digests:

```text
2aa3f08bfff328c3988884eba0bc735e7b638ead8837d864f2d096c0ec53e823  apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam
9af105c618bfdfcff21b6dd39aff81cb0fefad77b8b31de670f83f5913594787  apps/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam
4293b63149aed946d5326ea52565a1d59f09ce4941adeaf20e5b95e9681b7ae5  apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam
f17c4f66adefc761995a07080551a9539473f9fc0d83e8d492451fa9f36c46a1  apps/cepaf_gleam/src/cepaf_gleam/harness/mcp.gleam
5e634c84bafcd1d6eb39bcb6070984041b09ce7c30b49b613c22c71a29ea528d  apps/cepaf_gleam/src/cepaf_gleam/harness/system_feature_store.gleam
2cbabca6fa07f3c4de7e8f9a56c3ae3976cb4754d9779f267767817d3454e09d  apps/cepaf_gleam/native/c3i_nif/src/planning.rs
d99b64ffd6493ac168cacf61847f4b7654eb788733bf0b04bece3b313023fa12  apps/cepaf_gleam/native/c3i_nif/src/db.rs
```

## 9. Architectural Observations

The legacy string adapters, task-bound bootstrap, and reviewed successor grant are separate mechanisms. Composition does not confer the strongest mechanism's guarantees on the others. Repair the narrow boundary and shared metadata; retain Gleam control, bounded native ABI work, canonical Sa-plan effects, and the independent release authority. `db.rs` can choose an external VM-1 C3I path and opens SQLite with create/write capability plus a WAL pragma even for reads. This source observation does not prove which live DB the sweep used; pin an admitted UOS observation source and read-only open mode in implementation fixtures/release configuration. Never exercise failure probes against the external source tree.

## 10. Remaining Gaps

Raw post-hardening sweep receipts, actual failing client adapter, live server BEAM/NIF hashes, its database locator, and current privileged grants/leases were not available. Therefore this review proves source explanations at inspected bytes, not exact source-to-live-binary identity or runtime crash absence. Successful activation of the four reads remains blocked by reviewed binding/scope work. Legacy mutations remain intentionally unavailable. No transport can guarantee delivery after VM death; timeout must not be equated with native cancellation or “no effect.” Implementation scheduling, risk receipts, release, independent verification, and admission remain outstanding outside this review.

## 11. Metrics Summary

Reported outcomes explained: 11/11 across three direct causes; four of four share a first binding failure; two of those four also have a statically incompatible store scope; six of six mutators are refused before handlers; one lookup absence is already a returned JSON error. Fresh observations: MCP inventory and selected Sa-plan status, plus source/host/JJ inspection. Code changes 0; new review files 1; tests/builds 0; agents spawned 0; model/paid advisory calls 0. No statistical reliability rate, Bayesian posterior, measured Lyapunov derivative, or runtime pass count is inferred from source inspection or this selected failure sample.

## 12. STAMP & Constitutional Alignment

Controlled action: expose/execute an MCP command and report its outcome. Losses: unauthorized canonical mutation, false success/admission, hidden backend failure, and unbounded resource consumption. Safe state: explicit refusal or failure/uncertainty with no authority amplification and no unreviewed retry.

| UCA type | Hazard/context | Required constraint |
|---|---|---|
| Required action not provided | Missing binding/backend prevents intended read; catalog advertises unusable operation | Report exact unavailable reason and scoped recovery prerequisite; do not fabricate observations. |
| Unsafe action provided | Re-enable six legacy handlers or accept caller identities to clear sweep errors | Retain deny path; effects only through independently validated task-bound authority. |
| Wrong timing/order | Check stale lease or infer authority from forecast before dispatch; retry after ambiguous timeout | Fence at effect time, enforce deadlines, reconcile unknown outcomes before retry. |
| Stopped too soon/applied too long | Catch only after NIF call; timeout leaves native work running or drops receipt after effect | Bound backend lifetime/resources, preserve uncertain outcome, keep supervised cleanup and reconciliation. |

Raw FMEA is provisional: occurrence and detection ratings need an authorized fault campaign. Intervals are ordinal uncertainty, not probabilities.

| Mode | S | O | Det | RPN interval | F (severity floor) | Existing control / residual |
|---|---:|---:|---:|---:|---:|---|
| Authority widened to clear failures | 5 | unknown 1–5 | unknown 1–5 | 5–125 | 5 | Current literal refusal prevents these six effects; preserve it. |
| Native fault kills request/session | 3 | unknown 1–5 | unknown 1–5 | 3–75 | 3–5 | Some returned errors exist; thrown open/query failures remain uncontained here. |
| Malformed adapter output reported successful | 4 | unknown 1–5 | unknown 1–5 | 4–100 | 4–5 | Top-level error detection only; schema-safe decoding needed. |
| Busy/partial request exceeds resource budget | 3 | unknown 1–5 | unknown 1–5 | 3–75 | 3–5 | Partial byte/output limits; combined native/transport deadline unproved. |

Implementation is **P1 for any proposed widening/release of authority**; bounded reliability work with effects held is P2. Provisional factors for the combined boundary proposal: C=3 (necessary reliability), T=4 (critical authority/reporting controls need verification), F=5 (severity floor), Dep=unknown 1–4 (actual blocked task edges not supplied), I=3 (one critical MCP service). Score interval **180–720**; not scheduler selection or permission. No unsafe mutation was observed, so no P0 claim. Fresh implementation assessment must replace these intervals and name real dependencies in Sa-plan before claim; no fabricated preflight/active-check or passing gate is asserted here.

EV ceiling remains 93; EV-94..109 remain NOT_ADMITTED. No EV number minted. No external-tree writes, prohibited dependencies, inference-service changes, storage allocation, or release actions were introduced.

## 13. Conclusion

The immediate minimum is to make refusal/not-found/backend outcomes explicit and consistent, align discovery with actual dispatch, and contain native faults before they escape. Keep the six legacy mutations denied. Treat the four read APIs' bootstrap/scope contradiction as separate reviewed wiring work. A no-grant sweep can pass these safety requirements while still returning expected `isError` refusals.

Precommitted forecasts for the next authorized development fixture run, before any authority-enabling change: (a) probability 0.99 that removing the role binding yields the same typed refusal for all four APIs; (b) probability 0.99 that no complete tuple accepted by the inspected bootstrap loader satisfies the feature-store task fence; (c) probability 0.95 that all six legacy commands with otherwise admissible, low-risk arguments refuse without mutation dispatch; (d) probability 0.95 that an absent fixture task produces the existing error-string path rather than a missing-row native exception. Horizon: that first fixture run within seven days; if no run occurs, forecasts remain unscored. Score each observed binary outcome with `(p - outcome)^2`, retaining individual results. Backend-open failure, changed source bytes, or a live binary mismatch requires a separate observation rather than quietly changing the forecast.

## Comprehensive verification checklist

This checklist records scope and unknowns; unchecked items are not passing claims.

<details><summary>Domain 1 — Metadata, timestamp and navigation</summary>

- [x] CHK-01-TIME — Host UTC and synchronized flag observed; numerical offset unmeasured; requested prefix retained.
- [x] CHK-02-TAIL — Full Tailnet source/rendered/navigation links supplied; serving status unverified.
- [x] CHK-03-FRACT — L0 governance, L3 dispatch, L4 evidence, L9 caller experience tagged.
- [x] CHK-04-KM — Wiki/ZK and historical evidence linked; ingestion/index publication unverified.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [x] CHK-05-MUDA — Review adds no dependency or runtime role; fleet purity scan UNRUN.
- [x] CHK-06-GRAPH — Proposal preserves Gleam control and bounded native services; runtime conformance UNRUN.
- [x] CHK-07-DRIVE — No storage mutation; denied OS serial policy unaffected; runtime interlock tests out of scope.

</details>
<details><summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] CHK-08-C1C8 — UI/acceptance categories UNRUN; source-only review.
- [ ] CHK-09-MATH — Four mathematical gates UNRUN; no proof claim.
- [ ] CHK-10-9MOD — Test modalities UNRUN; proposed discriminating cases listed above.
- [ ] CHK-11-REGR — Live regression/transport sweep UNRUN.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Harness reads observed; supervised full-command containment unverified.
- [ ] CHK-13-HERMES — Report-only Sa-plan status observed; task claim/risk execution receipts absent.
- [ ] CHK-14-ZIGVM — Kernel checks out of scope; no kernel change.
- [ ] CHK-15-MAX — Inference daemon checks out of scope; no inference change.
- [ ] CHK-16-OTEL — End-to-end trace/clock correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and standalone Jujutsu</summary>

- [ ] CHK-17-SOV — Independent candidate-bound runtime/formal verification and admission NOT_GRANTED.
- [x] CHK-18-JJ — Read-only JJ identity observed; no native Git or VCS mutation performed.

</details>
<details><summary>Domain 6 — Provenance extension</summary>

Principal source digests retained; operator sweep distinguished from fresh observations; no EV admission or new cycle claim. Live-binary provenance remains UNKNOWN.

</details>

[Previous: historical review bundle](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-1910-code-review-bundle.md) · [Next: governing harness contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning)

**UOS footer:** advisory source review only; canonical Sa-plan and independently verified effect/release authority remain required.
