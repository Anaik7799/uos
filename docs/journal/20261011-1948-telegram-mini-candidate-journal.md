# Telegram Mini App candidate and reproducibility journal

Observed 2026-10-11T19:48Z · #fractal-l0 #fractal-l2 #fractal-l3 #fractal-l6 #fractal-l9 #zk-adr #zero-muda

[Candidate manifest](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261011-1948-telegram-mini-candidate-handoff.json) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning)

## 1. Scope & Trigger

MINI_API_CANDIDATE under uos/telegram-runtime/20261001-1150, worker codex-telegram-20261011, attempt 1. The user requested all Telegram features and actual AGY/Gemini execution with Claude review. While AGY repairs the service, root prepared an isolated Mini App core candidate for AGY review and integration. This task does not close MINI_API_IMPL. Engine 5 formal gateway: existing accepted auth contract, adopted integration plan, exact typed ingress/identity/read boundaries. Fresh risk active-check passed at 19:45:34Z with 77 evidence files; coordinator workspace/task fences cover this sibling workspace.

## 2. Pre-State Assessment

The legacy Mini routes served hardcoded operational-looking data. Generic fallback handling accepted an unknown Mini-prefixed route. A server-side Telegram auth function existed but the browser-to-HTTP-to-reader path was incomplete. Engine 7 predictive prior UNKNOWN; no operational success probability is inferred from legacy HTML. Main remains a8adcc6958e5c2378678b56adf9d5d14f44f02b3 under the immutable-main guard.

## 3. Execution Detail

### Product candidate

The sibling workspace is /home/an/NAS-setup/uos/.uos-workspaces/codex-telegram-mini-20261011, change zsoxutzskksnlwvlpumxkwyvzmqtqpww, candidate 76360aa326fda8ecb918ff00a390c4d97bf78486. Fourteen typed public shells load operational fields only through POST /mini-app/api/data. The server verifies signed initData, age, configured user and optional signed chat identity before invoking a reader. Body input is bounded to 8192 bytes. Wrong methods, content type, malformed framing, invalid identities and paths refuse explicitly.

The Tasks backend uses the accepted pinned native observer against a server-configured Sa-plan database and plan. It reports expired executing leases explicitly. Thirteen other page backends return unavailable with empty fields. Read results are bounded, stale results lose fields, and authorization/time is rechecked after the read. The normal HTTP middleware change is limited to Mini data ingress; a separate protected mutation still returns 401.

### Tools and private effects

The candidate includes build.js, prepare-fixture.js, http-tests.js, an OCaml Playwright browser test and a bounded Mist fixture. Only already-realized repository toolchains and compiled dependency metadata are used. Two fixture listeners on Tailnet port 49134 were bounded, observed stopped, and their coordinator leases released. No Bot API call or Telegram message was sent. Engine 6 runtime Rete-UL verification UNRUN.

## 4. Root Cause Analysis

Engine 1 ACH disconfirmation matrix:

| Hypothesis | Falsifier / evidence | Result |
|---|---|---|
| H1 Existing auth implies a working Mini feature | No actual browser ingress/native read before candidate | Rejected |
| H2 Generic fallback safely handles unknown Mini URLs | Actual /mini-application returned 200 | Rejected; dedicated prefix ownership now returns 404 |
| H3 Correct backend data always appears faithfully | Uppercasing CSS transformed task field labels and browser assertion failed | Rejected; non-transforming field class passes |
| H4 A hand-maintained private DB is reproducible tooling | Initial new fixture command rejected a non-hierarchical plan name | Rejected; CLI-compliant names create a fresh fixture, 29 HTTP checks pass |
| H5 Every executing task owns a current lease | Private FENCE task remains executing after lease expiry | Rejected; UI explicitly renders lease expired |
| H6 Browser success establishes real Telegram acceptance | SDK identity was deliberately supplied by a synthetic browser fixture | Rejected; live Telegram acceptance remains UNRUN |

All original failures remain in the handoff negative_evidence paths.

## 5. Fix Taxonomy

Poka-Yoke: typed route parser, opaque authenticated read handle, configured identity scope, bounded fields and body, exact observer pins. Jidoka: missing auth, stale data and unavailable backends cannot produce healthy-looking data. Muda: reuse the accepted auth and observer rather than implement parallel signature or Sa-plan readers. Existing theme and Lustre rendering are retained without adding packages.

## 6. Patterns & Anti-Patterns Discovered

Engine 4 Devil's Advocate and Red Team: test the actual server middleware path, not only an isolated auth function. Exercise unsigned user data and expired signatures before backend invocation. Treat provider identity fixtures as fixtures. Physical browser clicks and keyboard interaction caught a presentation error that JSON tests missed. Domain checklist boxes are operator obligations and start unchecked; checking one in a browser test grants no admission. No explanatory diagrams were authored.

## 7. Verification Matrix

Engine 2 STANAG B2 is the working assessment for directly observed private development evidence, pending AGY independent acceptance.

| Surface | Observation | Limit |
|---|---|---|
| Gleam unit suite | 8 groups PASS, multiple assertions for routes, auth, body, stale/late reads and shells | Component tests |
| Real HTTP | 29 checks PASS against final candidate | Private synthetic identity |
| Fresh CLI-created database | Separate 29 checks PASS | Synthetic private data, actual native reader |
| Chromium | 3 scenarios PASS: SDK blocked, mobile authenticated, desktop authenticated | SDK identity deliberately substituted |
| Visual review | Root inspected final mobile and desktop screenshots | Full navigation and real Telegram client UNRUN |
| Private service lifetime | Both harness processes exited 0; no port 49134 listener; leases released | No production deployment |
| Broad gates/formal | Not claimed | Full candidate release gates pending |

Final evidence is var/recovery-runtime/20261011-1941-mini-final-build2; independent fixture creation and HTTP rerun are var/recovery-runtime/20261011-1946-mini-fixture2. Existing observer catch deprecation and OCaml package deprecation warnings are preserved.

## 8. Files Modified

The handoff pins 21 source/tool inputs. The sibling JJ change contains 19 added/modified files relative to main: accepted auth/observer dependencies; mini_api, mini_runtime, mini_view and mini_http; router, Mini routes and server integration; clock FFI; three test files; five test/build tools. The root authored this journal and handoff, and updated only task/risk/coordination evidence within owned scope. No AGY service source was edited by the Mini task. Baseline provenance remains in var/recovery-runtime/20261011-1912-mini-api-candidate/baseline-manifest.json.

## 9. Architectural Observations

Gleam owns identity policy, route authorization, configuration and read-result state. The bounded native observer supplies evidence only. The FFI exposes a clock, and the OCaml browser tool drives actual Chromium without downloading a browser. Server configuration is never accepted from request data. Engine 5 sheaf/category consistency is not newly proved. TUI parity and complete shared-site navigation remain review obligations; a responsive shell alone does not meet them.

## 10. Remaining Gaps

AGY independent review/adoption is pending. Thirteen page adapters and all actions remain unimplemented. Real Telegram SDK/client testing, full navigation interactions, broader regressions, formal repair, command/media/gateway integration and release remain pending. Mist normalizes headers before the adapter: logical duplicate Content-Length tests do not prove raw duplicate-wire handling. Future reader adapters need their own finite cancellation/cleanup contracts. The build reuses existing compiled dependency metadata and is not claimed as a full clean repository build. No production, global admission or main merge occurred.

### Reproduction

Run all commands through the admitted Gleam development launcher, with repository-pinned toolchain environment, current Sa-plan authority and coordinator runtime ownership. The builder takes a new absolute directory under var/recovery-runtime. prepare-fixture.js takes an existing private output directory and creates a new fixture.sqlite3 through Sa-plan CLI only. Use a separate output directory when preserving earlier failures.

The exact successful fixture launch argument vector is saved in var/recovery-runtime/20261011-1946-mini-fixture2/launch-args.json. For a new build, replace its code path and database path with the new output. The fixture's Erlang timer stops it after 18 seconds; the outer Gleam deadline is 25 seconds. Run http-tests.js while it is live. For browser verification use a 48-second fixture timer with a 55-second outer deadline, then mini_browser.exe NEW_BROWSER_DIRECTORY HTTP_FIXTURE_IDENTITY_JSON under a 35-second bound. Browser route interception allows only the private Mini GET/POST paths and the explicit synthetic SDK response, denying all other requests and sockets. Check process exit and port closure before releasing runtime ownership.

## 11. Metrics Summary

Eight unit groups, 29 HTTP checks, three browser scenarios and a separate 29-check fixture reproduction passed. These correlated tests are not independent reliability trials. Engine 3 Bayesian Beta-Binomial posterior NOT_ESTIMATED; half-life decay and Lyapunov dV/dt UNRUN. No overall feature completion percentage is derived from task counts.

## 12. STAMP & Constitutional Alignment

FMEA S4/O3/Det3 RPN36 for false operational data or identity bypass. UCAs: not_provided—reader absent; provided_unsafe—unsigned identity or invented healthy data; wrong_timing—expired signature/stale observation; duration—unbounded reader blocks service. Controls are signed scoped identity, actual source observations, explicit unavailable/stale state, finite bounds and independently reviewed integration. EV ceiling remains 93; EV94..109 NOT_ADMITTED. Sa-plan evidence and board messages do not confer deployment authority.

## 13. Conclusion

The core Mini candidate is implemented, built and executed in private development. Handoff to actual AGY is requested; it is not independently verified or admitted. Engine 7 Forecast p=.65 that AGY will record a concrete independent review decision for this exact candidate by Horizon 2026-10-11T21:00:00Z. Brier outcome PENDING until that horizon. The all-Telegram objective remains open.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [ ] **CHK-01-TIME** — Observe synchronized clock evidence and document prefix.
- [ ] **CHK-02-TAIL** — Verify full Tailnet links and actual serving status.
- [ ] **CHK-03-FRACT** — Verify L0–L9 tags and applicable layer mapping.
- [ ] **CHK-04-KM** — Reconcile specification, wiki, ZK and journal links.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Verify exclusions against the candidate dependencies.
- [ ] **CHK-06-GRAPH** — Verify the pure BEAM/Hermes graph boundary.
- [ ] **CHK-07-DRIVE** — Preserve the denied OS serial and test real interlocks only in scope.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Verify all applicable C1–C8 surfaces.
- [ ] **CHK-09-MATH** — Measure the four declared mathematical gates.
- [ ] **CHK-10-9MOD** — Apply relevant unit, system, TDD, BDD, performance, scalability, property, fuzz and chaos checks.
- [ ] **CHK-11-REGR** — Run applicable regressions and bounded observation.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Observe actual OTP control/supervision behavior.
- [ ] **CHK-13-HERMES** — Observe bounded analysis and authoritative evidence.
- [ ] **CHK-14-ZIGVM** — Verify deterministic execution and descriptor-relative VFS.
- [ ] **CHK-15-MAX** — Observe actual isolated inference when applicable.
- [ ] **CHK-16-OTEL** — Verify clock and nonzero trace/span identity.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Obtain candidate-bound independent review and authorized admission.
- [ ] **CHK-18-JJ** — Preserve standalone JJ, source ownership and exact candidate identity.

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted.

</details>

[Previous: formal specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

UOS footer: document and component evidence do not grant system admission.

[Previous ledger](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261001-1202-telegram-browser-admission-recovery.md) · [Next: planning status](http://nas-1.tail55d152.ts.net:4100/planning)

