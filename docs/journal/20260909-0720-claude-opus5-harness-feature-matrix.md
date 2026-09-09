# 20260909-0720 — Feature matrix, dashboard truthfulness and completion status (`claude-fable-harness-1`, follow-up 2)

#fractal-l0 #fractal-l4 #fractal-l5 #fractal-l8 #fractal-l9 #zero-muda #km-triad #stamp-stpa #tailscale-web

**UOS / Journal / Independent Review** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Ecology](http://nas-1.tail55d152.ts.net:4110/ecology) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)
**Status:** REVIEW DELIVERED. **Not approval. Not admission. No effect authority. Delivery ACK is not admission.**

## 0. Session and model ACK

| Field | Value |
|---|---|
| Model | **Claude Opus 5** (`claude-opus-5`) |
| Requested **Fable**? | **NO** — Fable is `claude-fable-5-1`. This is the Claude half only. |
| Session | `session_01B9GiR9bF4d1Jv2aSMowAKC` · board identity `a65088e0-0f2b-497e-bd5c-97eeed9c3594` |
| Root coordinator `01a083d2-…`? | **NO** |
| AGY review | **OUTSTANDING** |
| Sa-plan | `task-30`, worker `claude-opus5-harness-review`, attempt 1 |

**Review artifact paths (all three):**

| Artifact | sha256 |
|---|---|
| `docs/journal/20260909-0721-claude-opus5-harness-evolution-review.md` | `871087bcafa31bcb4c07bea2032ecba47fd8ac68a8b273b563ecdee699c3a979` |
| `docs/journal/20260909-0721-claude-opus5-harness-evolution-review.json` | `4e5958f8787228d55f5ca035d5e3793825f781d8e3c1a824b8715572a2dd2bf1` |
| `docs/journal/20260909-0720-claude-opus5-harness-feature-matrix.{md,json}` | this document, digest relayed separately |

## 1. The three direct answers

**Q: Are ALL requested features implemented?** **No.** Of 15 mapped capabilities: 1 VERIFIED, 3 EXECUTED, 3 IMPLEMENTED (source only), 3 PLANNED, 4 UNKNOWN, and 1 EXECUTED-but-FALSE. Nothing in the harness bootstrap reached VERIFIED.

**Q: Does the dashboard show current truthful state?** **Partly, and one surface does not.**

- `http://nas-1.tail55d152.ts.net:4110/ecology` — **yes, within its declared scope.** It states its own limits and marks 7 of 18 checkpoints `UNRUN in this view`. Its timestamp resolves to the current minute.
- `http://nas-1.tail55d152.ts.net:4100/` — **no.** It renders static demo data under a panel headed **Live**, asserting `health=100% containers=16/16` while `podman ps` at the same instant showed **2** containers. See H1.
- **The harness itself has no surface on either dashboard.** See H2.

**Q: Completion status?** **Bootstrap INCOMPLETE and correctly self-declared so.** Sa-plan `HARNESSBOOT` observed `state=executing`, worker `codex-01a083d2-harness`, attempt 1, risk assessment `valid_until 06:09:11Z` still valid at observation. No completion claim is supported by anything this reviewer observed.

## 2. Live dashboard observations

Observed `2026-09-09T05:42:34Z` with `/usr/bin/curl`. Actual reachability, not historical totals:

| URL | HTTP | Bytes | Note |
|---|---|---|---|
| `http://nas-1.tail55d152.ts.net:4110/ecology` | **200** | 27 545 | live |
| `http://nas-1.tail55d152.ts.net:4100/` | **200** | 77 763 | live |
| `http://nas-1.tail55d152.ts.net:4100/planning` | **200** | 57 501 | live |
| `http://127.0.0.1:4110/ecology` | **000** | 0 | **not** bound to loopback; Tailnet interface only |
| `http://127.0.0.1:4100/` | 200 | 77 763 | bound to loopback too |

## 3. Feature matrix

| ID | Capability | Source | Observed evidence | Status | Dashboard surface | Blockers | Falsifier |
|---|---|---|---|---|---|---|---|
| C01 | Gleam MCP development service (finite stdio interface) | apps/cepaf_gleam/src/cepaf_gleam/harness/mcp.gleam (320 L); mcp/{server,tools,authz}.gleam | Source read only. No live initialize/notification observed by this reviewer; service not started. | IMPLEMENTED | MISSING — neither 4100 nor 4110 renders any harness/MCP service state (grep: harness 0 hits on both pages) | No started service in this review scope | Start it and observe an initialize handshake; absence of any surface means a dead service is indistinguishable from a healthy one on the dashboards |
| C02 | Bounded task-fenced file edit (compare/replace) | harness/files.gleam:126-263 | VERIFIED BY READING: lstat + nlinks==1 + 262144 bound, open-descriptor inode/dev recheck before pread, O_EXCL create, fsync of file and parent, digest CAS re-read before rename, pending cleanup on failure, symlinked parents refused | IMPLEMENTED | MISSING | Not executed in this pass; TOCTOU between second read and rename is disclosed in the module header | Rename the parent directory between the second read and the rename; the module states this needs a cooperative workspace lease |
| C03 | Clock policy (UTC / monotonic / boot / reference age / delivery age) | harness/clock.gleam (138 L); uos_swarm/clock_contract.gleam | Source read only. Live chronyc sampling not exercised by this reviewer. | IMPLEMENTED | MISSING — 'clock' appears 0 times on both pages | F1 hardcoded /usr/bin/chronyc; F5 one policy field carries two semantics and is 30x looser than strict_policy | Run on a host without chrony: observe() returns bounded_clock_sampler_failed and no gate reports it |
| C04 | Sa-plan sole authority with attempt/lease/dependency fencing | harness/development.gleam:96-164, 203-215; planning/sa_plan_bridge.gleam | OBSERVED: HARNESSBOOT state=executing worker=codex-01a083d2-harness attempt=1; risk assessment valid_until 06:09:11Z still valid at 05:32:44Z | EXECUTED | MISSING — HARNESSBOOT appears 0 times on both dashboards | F2 grant is seven getenv reads against one hardcoded tuple; environment is caller-controlled | Set the seven UOS_HARNESS_* variables in any local process to present the root coordinator identity |
| C05 | Stable logical effect identity across retries | harness/development.gleam:148-164 | NOT EXERCISED. attempt is pinned to 1 by the grant, so the retry path is unreachable in this configuration. | PLANNED | MISSING | F3 | Set UOS_HARNESS_ATTEMPT=2: binding fails before any replay logic runs |
| C06 | OpenRouter paid routing under a USD10/UTC-day aggregate ledger | ecology/openrouter_engine.gleam, ecology/daily_budget.gleam; tools/ecology_budget.ml | OBSERVED ABSENCE: no paid-call receipt exists under var/harness/. Design declared in the risk receipt budget/assumptions fields. | PLANNED | PARTIAL — 'budget/openrouter' matches twice on each page, but no spend, reservation or remaining-balance figure is rendered | F6 absence of spend cannot distinguish enforced from unexercised | Make a paid call without a reservation: no artifact would appear either, so the control is unobservable from outside |
| C07 | Ecology capability discovery and authorized activation | ecology/living_swarm.gleam, ecology/capability_port.gleam | OBSERVED LIVE at 4110/ecology 05:42:34Z: 26 participants, 11 discoverable capabilities, observed cycle 8912, invocation receipts 8914; page states plainly 'Participant models share one ecology actor; external system bindings are absent.' | EXECUTED | PRESENT at http://nas-1.tail55d152.ts.net:4110/ecology (HTTP 200, 27545 B) | External bindings absent by the page's own statement | Query any of the 26 participants for an external system response; the page already asserts there is none |
| C08 | Shared service Andon (modular_max, openrouter_free) | ecology/* | OBSERVED LIVE: both render 'ready'. | EXECUTED | PRESENT at 4110/ecology | 'ready' is a readiness label, not an executed-request receipt | Disable the MAX daemon and reload: verify whether 'ready' changes |
| C09 | Comprehensive 18-checkpoint verification checklist on every surface | contracts/rules/comprehensive-checklist-contract.md | OBSERVED LIVE at 4110: all 5 domains rendered, and 7 of 18 explicitly marked 'UNRUN in this view' (CHK-05,07,08,10,11,14,16). It does NOT claim a blanket pass. | VERIFIED | PRESENT at 4110/ecology | None for this item | Look for a claimed 18/18 green on that page: there is none |
| C10 | Dashboard shows CURRENT truthful state | apps/cepaf_gleam/src/cepaf_gleam/agui/event_stream_widget.gleam:27-40 | FALSIFIED ON THE CANONICAL COCKPIT. 4100 renders a panel titled 'AG-UI Event Stream (Live)' whose content is the static demo_events() list. Observed 05:42Z: it displays 'health=100% containers=16/16' with fixed timestamps 01:42:10.49x. Actual podman ps at the same moment: 2 containers (c3i-zenoh-router-1, c3i-docs-server); docker 0. The words demo/sample/synthetic/mock appear 0 times in the rendered page. | EXECUTED (rendering) / FALSE (content) | PRESENT and MISLABELLED at http://nas-1.tail55d152.ts.net:4100/ | H1 below | Reload the page: identical timestamps every time. Stop both containers: it still reports 16/16. |
| C11 | Harness evolution visible on a dashboard | — | OBSERVED ABSENCE: 'harness' matches 0 times on both 4100 and 4110; HARNESSBOOT 0 times. | PLANNED | MISSING ENTIRELY | No surface exists | Ask either dashboard for harness bootstrap state; nothing answers |
| C12 | Native generation via constrained typed kernel IR | — | NOT EXERCISED; no generated artifact inspected. | UNKNOWN | MISSING | Out of source-only scope | Produce a generated native artifact and diff its semantics against the Gleam source |
| C13 | Dev / production-primary / production-standby role isolation | — | NOT OBSERVED; no standby node inspected. | UNKNOWN | MISSING | Out of scope; production is separate authority | Point a dev candidate at the standby role and see whether anything refuses it |
| C14 | Conditional hot upgrade (appup/relup/sys) | — | NOT EXERCISED. | UNKNOWN | MISSING | Out of scope | Attempt a live upgrade with a native resource held open |
| C15 | Formal evaluation set (Lean, Quint, STM, Bayesian, Rete, STPA/FMEA) | formal/, tools/validation/ | NOT RE-RUN in this pass. This reviewer separately holds current evidence for Lean and Quint from its own work, not for Rete-UL. | UNKNOWN | MISSING | Packet itself flags Rete-UL as unverified | Execute Rete-UL against an independent oracle |

Status vocabulary is the packet's: PLANNED / IMPLEMENTED / EXECUTED / VERIFIED / UNKNOWN. **IMPLEMENTED means source read, nothing run.** No count, catalog or prior EV claim was treated as passing evidence.

## 4. Dashboard findings

### H1 — HIGH — Canonical cockpit renders static demo data under a panel titled Live

**Where:**
- `apps/cepaf_gleam/src/cepaf_gleam/agui/event_stream_widget.gleam:27-40 (fn demo_events, doc comment: 'Create demo events showing a typical AG-UI lifecycle')`
- `rendered at http://nas-1.tail55d152.ts.net:4100/ observed 2026-09-09T05:42:34Z, HTTP 200, 77763 B`

**What:** The panel heading is 'AG-UI Event Stream (Live)'. Its content is the static demo_events list: fixed timestamps 01:42:10.496-.502 and the literal 'health=100% containers=16/16'. The words demo, sample, synthetic, illustrative and mock appear zero times in the rendered page, so a viewer has no way to tell this from live telemetry. The source is honest; the page is not.

**Observed:** podman ps at the same moment: 2 containers running (c3i-zenoh-router-1 Up 4 hours, c3i-docs-server Up 4 hours). docker: 0. The page claims 16/16 and health=100%.

**Falsifier:** Reload the page: the timestamps never change. Stop both containers: it still reports 16/16.

**Fix:** Either bind the panel to real telemetry, or label it 'Demo' in the rendered output and drop the word 'Live'. A health indicator that cannot be wrong is not a health indicator.

**Residual:** Any other panel sourced from demo_* helpers has the same exposure; this review checked one.

### H2 — MEDIUM — Harness evolution has no dashboard surface at all

**Where:**
- `http://nas-1.tail55d152.ts.net:4100/ (grep 'harness': 0)`
- `http://nas-1.tail55d152.ts.net:4110/ecology (grep 'harness': 0, 'HARNESSBOOT': 0)`

**What:** None of the bootstrap subject matter is visible anywhere: no MCP development service state, no HARNESSBOOT task state, no clock observation, no budget balance. The operator's question about dashboard truthfulness cannot be answered affirmatively for the harness because the harness is not shown.

**Observed:** Both pages fetched and text-extracted at 05:42:34Z; zero matches.

**Falsifier:** Kill the development MCP service: no dashboard changes, because none observes it.

**Fix:** Add a harness panel bound to the Sa-plan task row and the service heartbeat, or state explicitly that the harness is deliberately headless during bootstrap.

**Residual:** Dashboard changes are separate authority; this is a finding, not a request to change production.

### H3 — LOW — False precision on the ecology cockpit

**Where:**
- `http://nas-1.tail55d152.ts.net:4110/ecology`

**What:** HARMONIC CONSONANCE is rendered as 43.08255132291642 % — 16 significant figures for a derived aesthetic metric.

**Observed:** Read directly from the live page at 05:42:34Z.

**Falsifier:** No measurement in this system carries 16 significant figures.

**Fix:** Round to the precision the input actually supports.

**Residual:** Cosmetic, but it invites reading a synthesised number as a measured one.

### H4 — INFO — The ecology cockpit is materially honest and should be the pattern

**Where:**
- `http://nas-1.tail55d152.ts.net:4110/ecology`

**What:** It states 'Participant models share one ecology actor; external system bindings are absent', 'Local cognition and diagnostics; backend availability and system admission require separate evidence', and 'Initial snapshot; awaiting live refresh'. Its checklist marks 7 of 18 checkpoints 'UNRUN in this view' rather than claiming a blanket pass. CHK-01-TIME carries a host observation of 1788932570331637 us, which resolves to 2026-09-09T05:42:50Z, i.e. current.

**Observed:** Read directly from the live page.

**Falsifier:** None sought; this is a positive observation.

**Fix:** Apply the same disclosure discipline to the 4100 cockpit, which currently does the opposite (H1).

**Residual:** Honest labelling is not the same as verified behaviour; the page says so itself.

## 5. Limits

- Dashboard changes and production effects remain **separate authority**; nothing here requests or performs one. This review made no dashboard or production change.
- Findings from the first delivery (F1 HIGH host/`$HOME` toolchain paths at 8 call sites, F2, F3, F5, F6, F7) stand unchanged.
- EV ceiling 93 and EV-94..109 NOT_ADMITTED untouched; no new EV number created.
- **A delivery ACK on the coordinator board is transport, not admission and not approval.**

---

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this review grants no admission and no effect authority.
