# Harness ↔ Model Interaction Ontology, Patterns of Use, and Optimization Use Cases

#fractal-l0 #fractal-l3 #fractal-l5 #fractal-l9 #km-triad #zk-adr #zero-muda #stamp-stpa #tailscale-web

**Observed:** host clock `2026-11-08T01:30:45Z` · **Contract basis:** `SC-INTEL-ROUTING-001`, `SC-MCP-KM-BRAIN-001`, `SC-JOURNAL-v3`, `SC-DIAGRAM-001`, `SC-PEER-ARTIFACTS-001`
**Tool:** [`tools/model_interaction_ontology.ml`](http://nas-1.tail55d152.ts.net:4100/files/tools/model_interaction_ontology.ml) · **Evidence:** [`governance/sources/20261108-0145-harness-model-interaction-ontology.json`](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20261108-0145-harness-model-interaction-ontology.json)

---

## 1. Corpus and its boundary

Measured in one native pass (17.1 s) over every Claude Code transcript on this host, plus the authored corpus and the Pi session stores:

| Corpus | Volume | What it is |
|---|---|---|
| Claude transcripts | 172 files, 529 MB, **164 sessions** | `api-request` (8,083 model calls) + `api-request-blob` (16,197 content-addressed payloads) |
| Authored artifacts | 5,477 files, 224 MB | `docs/**`, `governance/**`, `contracts/**` — what the exchanges produced |
| Pi session stores | 23 SQLite DBs | `session_events` (2,574), `tool_calls`, with `bytes_avoided`/`bytes_returned` |

**Two trees were deliberately not opened.** `~/.codex` (9.8 GB) and `~/.gemini/antigravity` (5.1 GB) are the two largest log stores on this host and are exactly the request/response logs the task asks for — but `SC-PEER-ARTIFACTS-001` rule 4 marks them private home state, referenced presence-only. They are **59% of the available log bytes**. Every figure below therefore describes one harness of five, and no cross-harness claim is made. That is the single largest limitation of this analysis and no amount of care elsewhere compensates for it.

Byte shares are **estimates** from marker scanning, not tokenizer accounting. Facet F presence is measured over a bounded 128 KB prefix of each blob; 211 blobs (1.3%) exceed that cap and are counted as such.

---

## 2. The ontology is faceted, not a tree

A single call is simultaneously a tool continuation, at medium effort, with a stable prefix, carrying a transcript-heavy payload, about Jujutsu and Sa-plan at once. A single taxonomy would force each call to pick one label and every count would then be a lie by omission. So: **six orthogonal facets**, A–E single-label and total, F multi-label.

```text
ASCII source generated from the mermaid block below, edge for edge (SC-DIAGRAM-001).

[one logged model call] --> [facet A: interaction kind]
[one logged model call] --> [facet B: context discipline]
[one logged model call] --> [facet C: reasoning mode]
[one logged model call] --> [facet D: payload composition]
[one logged model call] --> [facet E: response shape]
[one logged model call] --> [facet F: subject domain multi-label]
[facet A: interaction kind] --> [patterns of use = co-occurrence and sequence]
[facet B: context discipline] --> [patterns of use = co-occurrence and sequence]
[facet C: reasoning mode] --> [patterns of use = co-occurrence and sequence]
[facet D: payload composition] --> [patterns of use = co-occurrence and sequence]
[facet E: response shape] --> [patterns of use = co-occurrence and sequence]
[facet F: subject domain multi-label] --> [patterns of use = co-occurrence and sequence]
[patterns of use = co-occurrence and sequence] --> [optimization use cases]
```

```mermaid
flowchart TD
    call["one logged model call"] --> A["facet A: interaction kind"]
    call --> B["facet B: context discipline"]
    call --> C["facet C: reasoning mode"]
    call --> D["facet D: payload composition"]
    call --> E["facet E: response shape"]
    call --> F["facet F: subject domain (multi-label)"]
    A --> pattern["patterns of use = co-occurrence and sequence"]
    B --> pattern
    C --> pattern
    D --> pattern
    E --> pattern
    F --> pattern
    pattern --> uc["optimization use cases"]
```

| Facet | Classes | Measured distribution |
|---|---|---|
| **A** interaction kind | A1 bootstrap, A2 user turn, A3 tool continuation, A4 subagent, A5 meta | 48.3% / 33.1% / 16.6% / 2.0% (A5 unobserved) |
| **B** context discipline | B1 full prefix, B4 prefix break | **97.8%** / 2.2% |
| **C** reasoning mode | model × effort × thinking | Opus 67.8%, effort medium 63.9%, thinking adaptive 100% |
| **D** payload composition | D1 system, D2 schema, D3 transcript, D4 reminder | dominant: **D3 transcript, 78.4%** |
| **E** response shape | E1 text, E2 single tool, E3 parallel tools, E4 thinking-then-act | 0.3% / 32.9% / 10.5% / **56.3%** |
| **F** subject domain | F01–F17, multi-label | formal 15.1%, jj 14.7%, sa-plan 13.3%, … km-triad 2.3% |

Two facets were corrected during measurement, and both corrections changed conclusions:

- **Facet B first reported 100.0% `thinking_cleared`** — because that `context_management` edit is a standing configuration on every call of this harness version, not an event. A facet whose classes are decided by a constant measures the constant. B now has two relational classes; clearing and compaction are reported as independent flags.
- **Facet F × E first made `E1_text_only` the modal response** — because I computed a response shape for *user* blobs too, counting inputs as if they were outputs. User payloads now carry their own label.

---

## 3. Patterns of use (each tied to a measurement)

### P1 — One tool per round trip, 3:1 over batching
`E2_tool_single` 1,697 vs `E3_tool_parallel` 540 — a **3.14:1** ratio; 0.79 `tool_use` blocks per call. Consecutive tool-continuation runs: 568 runs, 39.4% of depth 1, but a long tail — depth ≥10 in ~13% of runs, **maximum 73**. Every one of those round trips re-sends the transcript, which is 78.4% of request bytes.

### P2 — Bash monoculture
**78.9%** of all 6,365 tool invocations are `Bash` (5,022). `Read` 7.6%, `Grep` 2.4%, `Glob` 0.3%. Bash returns unstructured text, which the harness cannot truncate, summarize or cache structurally — so P2 directly inflates P1's cost. (This session runs under an auto-mode instruction that *prefers* Bash, so the figure is partly policy-induced, not purely model choice.)

### P3 — Transcript dominates; instruction text does not
| Component | Estimated share |
|---|---|
| conversation transcript | **78.4%** |
| instruction / rule text | 17.2% |
| injected `<system-reminder>` | 3.0% |
| tool schemas | 1.5% |

The intuition that `AGENTS.md`/`CLAUDE.md`/rule projection dominates the context is **wrong by 4.5×**. Reminder injection, a frequent suspect, is 3.0% at 0.2 blocks per call.

### P4 — Request shape is already near-optimal
97.8% `B1_full_prefix`. Of 181 prefix breaks, **164 are session bootstraps** (unavoidable), leaving **17 controllable breaks in 7,919 calls — 0.21%**. Twelve of the 17 land on tool continuations, consistent with mid-conversation tool changes (deferred-tool loading). 3.4 reused prefix blobs and 2.5 1h-TTL cache breakpoints per call.

### P5 — Growth is controlled by clearing thinking, never by compaction
`clear_thinking` present on **8,083 of 8,083** calls; compaction edits on **0**. At 49.3 calls per session mean, the only active history-growth control in this corpus is thinking-clearing.

### P6 — Routing contract is not being honored
`SC-INTEL-ROUTING-001` R1 routes mechanical verification to "script, else Haiku"; R2 sends docs/summaries to Haiku or nano. Measured:

| Model | Calls | Share |
|---|---|---|
| Opus (5, 5.5, 4.6) | 5,572 | **67.8%** |
| Fable 5.1 | 1,667 | 20.6% |
| Sonnet 5.5 | 841 | 10.4% |
| **Haiku (5.5 + 4.5)** | **2** | **0.02%** |

Effort: medium 63.9%, high 30.9%, max 5.1%, **low 0.1% (11 calls)**. With 78.9% of tool calls being Bash — much of it `ls`, `wc`, `grep` — the cheapest adequate tier is essentially never selected. This is a measured non-compliance with an admitted contract, not a style preference.

### P7 — Subagent calls cost ~72 model calls per spawn
19 `Agent` invocations against 1,372 `agent:builtin:general-purpose` calls (A4 = 16.6% of all calls). Each spawn starts cold and re-derives context.

### P8 — Sa-plan is the vocabulary hub
Strongest domain co-occurrences: `vcs_jj + sa_plan` 1,177 · `sa_plan + formal` 1,142 · `sdlc + sa_plan` 945 · `vcs_jj + formal` 910. In the authored corpus `F14_sa_plan` is the **primary** domain of 33.2% of files. Governance vocabulary, not application vocabulary, dominates both sides of the exchange.

### P9 — The KM-triad mandate is the least-evidenced mandate
`SC-MCP-KM-BRAIN-001` requires a triad check *before planning, claiming, editing or reviewing*. Measured presence in logs: `F01_km_triad` **2.3%** of blobs, primary in **0.3%**. ZK 2.3%, wiki 2.0%. The authored corpus shows the inverse (zk 6.2%, wiki 4.2%, km 4.0%) — **writing exceeds reading**. *Honest limit:* a triad check performed through an MCP tool call may carry none of these markers, so this undercounts by an unknown amount. The defensible claim is narrower: the mandate is **not observable** in the interaction log, which means compliance with it cannot currently be verified either way.

### P10 — A sibling harness already measures what this one does not
Pi's store records `bytes_avoided` 457 KB against `bytes_returned` 866 KB — a **34% context reduction** from its own context layer — and 96 `retry_detected` events of the form *"ctx_execute called 3 times with similar input"*, plus 122 `error_tool` and 103 `error_resolved`. The Claude transcripts carry **no equivalent signal**: model-side repetition and tool-error recovery are invisible in them.

---

## 4. Optimization use cases

Ranked by `C × T × F × Dep × I` per `SC-RISK-PRIORITY-001`; each carries the measurement that falsifies or confirms it. **These are proposals. None is implemented, none is admitted.**

| # | Use case | Target metric | Now | Class |
|---|---|---|---|---|
| **UC-1** | Batch independent tool calls in one assistant turn | E3:E2 ratio | 0.32 | P2 |
| **UC-2** | Prefer structured tools over Bash where one fits | Bash share of invocations | 78.9% | P2 |
| **UC-3** | Spend optimization effort on transcript economy, not on trimming rule text | transcript share | 78.4% | P2 |
| **UC-4** | Route mechanical verification to the cheapest adequate tier per R1/R2 | Haiku+low-effort share | 0.02% / 0.1% | **P1** |
| **UC-5** | Keep deferred-tool loading to one batched `ToolSearch` | controllable shape breaks | 17 (0.21%) | P3 |
| **UC-6** | Port Pi's `bytes_avoided` accounting into the Claude harness | measured avoided bytes | not instrumented | P2 |
| **UC-7** | Emit a `retry_detected` signal on near-identical repeated tool calls | repetition events | not instrumented | P2 |
| **UC-8** | Instrument the KM-triad step so the mandate becomes verifiable | triad observability | 2.3% marker-only | **P1** |
| **UC-9** | Budget subagent spawns against their true cost | calls per spawn | ~72 | P2 |
| **UC-10** | Decide whether compaction should ever fire at 49 calls/session | compaction rate | 0.0% | P3 |

**UC-4 and UC-8 are P1** because each is an unresolved conformance condition against an admitted contract, not an efficiency idea: UC-4 contradicts `SC-INTEL-ROUTING-001` R1/R2 as measured, and UC-8 makes an existing mandate checkable rather than assumed. Per the risk SOP, a P1 is not displaced by any score in a lower class.

### 4.1 As-is → to-be → acceptance criteria

A target metric without a falsifier is a wish. Each row states the measured as-is, the to-be, and the criterion that decides it — all computable by re-running `tools/model_interaction_ontology.ml` over a later log window, so no new judgement is needed to score them.

| # | As-is (measured) | To-be | Acceptance criterion (falsifiable) |
|---|---|---|---|
| UC-1 | E3:E2 = 0.32 (540 parallel vs 1,697 single) | ≥ 1.0 | Over a ≥500-call window, `E3_tool_parallel / E2_tool_single ≥ 1.0`. **Falsified** if the ratio stays < 0.5, or if total calls per completed task does not fall. |
| UC-2 | Bash = 78.9% of 6,365 invocations | ≤ 50% | Bash share ≤ 0.50 **and** `Read+Grep+Glob` share ≥ 0.30, with no rise in calls per task. Falsified if task count rises. |
| UC-3 | transcript = 78.4% of request bytes | ≤ 65% | Estimated transcript share ≤ 0.65 at equal or better task completion. **Falsified** if instruction share rises to compensate — moving bytes is not saving them. |
| UC-4 | Haiku 0.02%, effort `low` 0.1%, Opus 67.8% | ≥ 20% of calls on cheapest adequate tier | Over a ≥500-call window, (Haiku + `low` effort) ≥ 0.20 **with zero** mechanical-verification regressions. Falsified by any gate that passes at a cheap tier and fails on re-check. |
| UC-5 | 17 controllable shape breaks (0.21%) | ≤ 17 | Non-bootstrap `B4_prefix_break` count does not grow as deferred-tool use grows. Falsified if breaks/call rises above 0.0021. |
| UC-6 | no avoided-byte accounting exists | field emitted per call | A `bytes_avoided` figure is present and reconciles to within 5% of an independent recomputation. **Falsified by a number that cannot be recomputed** — an unverifiable savings figure is worse than none. |
| UC-7 | repetition invisible; Pi detects 96 | signal emitted | Near-identical repeated tool calls raise a counter; validated against ≥20 hand-labelled cases at ≥0.8 precision. |
| UC-8 | KM-triad marker presence 2.3%, primary 0.3% | step observable | Every triad check emits a typed record, so the mandate's satisfaction is readable from the log. **Criterion is observability, not a share** — raising a keyword count would be gaming the measurement, not honoring the mandate. |
| UC-9 | ~72 model calls per `Agent` spawn | budget enforced | Spawns carry a declared call budget; overruns are reported. Falsified if mean calls/spawn rises. |
| UC-10 | compaction rate 0.0% at 49.3 calls/session | explicit decision | A recorded decision either enables compaction with a threshold or states why clearing thinking suffices. Satisfied by a written decision, not by a number. |

Three criteria deliberately resist being gamed: UC-3 fails if bytes merely move between components, UC-6 fails on an unrecomputable savings figure, and UC-8 is scored on observability rather than on a marker count that this very analysis could inflate.

The cheapest high-value pair is **UC-1 + UC-3**: both attack the same cost (transcript re-sent per round trip), both are behavioural rather than infrastructural, and both are measurable from the existing log with no new instrumentation.

---

## 5. What this analysis does not establish

- **59% of the log bytes were never read** (`~/.codex`, `~/.gemini/antigravity`). Any claim about *the swarm's* interaction profile is unsupported; this is one harness.
- Byte shares are marker-derived **estimates**, not token counts. The 78.4%/17.2% split is robust to the method (the gap is 4.5×); the 3.0% reminder figure is not robust and should not be quoted precisely.
- Facet F is **keyword presence**, so it measures what the exchange *mentions*, not what it accomplished. P9's undercount risk is the clearest instance.
- `A5_meta` never fired: titling and summarization calls are not labelled distinguishably in `querySource`, so that class is **unobserved, not absent**.
- No optimization here has been implemented or A/B tested. Every "now" column is a baseline, and a baseline is not an improvement.
- No Sa-plan task was claimed for this analysis, and no `integration/main` lease is held.

EV ceiling 93; `EV-94..109` and `ADR-071..086` remain `NOT_ADMITTED`; no new EV number is minted. This document is model self-attestation and grants no admission.

**UOS footer:** [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · Sa-plan is the sole execution authority.

