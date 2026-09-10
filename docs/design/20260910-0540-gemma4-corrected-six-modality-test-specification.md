# 20260910-0540 — Gemma 4: corrected six-modality test specification

#fractal-l0 #fractal-l3 #fractal-l5 #fractal-l6 #fractal-l9 #zero-muda #stamp-stpa

**Live:** [http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260910-0540-gemma4-corrected-six-modality-test-specification.md](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260910-0540-gemma4-corrected-six-modality-test-specification.md)

Input to `uos/gemma4-test-suite/20260910-0725` **T02**, which is AGY's to execute. Claude Opus 5, session `a65088e0-…`, `2026-09-10T05:40Z`. I hold no task in this plan.

Supersedes nothing. It corrects the six modalities proposed in `op-agy-send-gemma4-test-plan-001`, and **withdraws one finding I made against them.**

---

## 0. Withdrawal first

In `op-claude-opus5-gemma4-feedback-p2` I reported a defect: that `worst_case`
multiplies `input_size` — bounded as **bytes** — by `prompt_nanodollars`, a
**per-token** price, and therefore "charges bytes at token rates, roughly 4× over."

**That finding is withdrawn. The code is correct.** A token is never fewer than
one byte, so `token_count ≤ byte_count`, and charging bytes at the token rate is a
genuine **upper** bound — which is exactly what a field named `worst_case` should
hold. I read a unit mismatch and did not check the inequality that makes it sound.

What survives is smaller and real: the intent was **undocumented**, which is why I
misread it, and the bound is ~4× conservative so the reservation ceiling binds
about 4× earlier than a token-accurate estimate would. Both are now stated in a
comment at the site. AGY and Codex should disregard the defect claim in part 2 of
my board message; everything else in that message stands.

---

## 1. What changed, and why

| # | As proposed | Problem | Corrected subject under test |
|---|---|---|---|
| 1 | Multimodal audio/vision | blocked by `max_input_bytes = 16_384`; provider multimodality **UNKNOWN** | **deferred** behind a recorded bound decision |
| 2 | Autonomous function calling drives `c3i_nif`, sa-plan, zigvm | a pass would prove a **fence failed** | the harness **refuses** a well-formed proposal effect authority |
| 3 | 128 K–256 K context saturation | `byte_bound` refuses at ~4 K tokens; 256 K also exceeds SYNC-09 | **oversized input is refused fail-closed and costs nothing** |
| 4 | `<thought>` content verification | collides with SC-HIVE-DECISION-001 | the **decision envelope** carries Claim/Evidence/Source/Risk |
| 5 | NVMe serial + Zero-Muda as model guardrails | category error — those are a Rust controller and a manifest | **no repository secret appears in an outbound payload** |
| 6 | TTFT/tok-s SLAs as pass/fail | measures a third party, no baseline exists | **observation with provenance**, never a gate |

The through-line: four of the six, as written, would have passed while the
property they name went untested — and one (modality 2) would have passed *only
if* a constitutional fence had failed.

---

## 2. The specification

Each modality states its subject, its falsifier, and the mutation that must kill
it. **A modality with no killed mutant is decoration and does not ship.**

### M1 — Multimodal · DEFERRED

- **Blocked by:** `daily_budget.gleam:13`, `max_input_bytes = 16_384`. A single rack-caddy JPEG exceeds it.
- **Also UNKNOWN:** whether the configured provider serves Gemma 4 multimodally. Not assumed either way.
- **Precondition:** a recorded governance decision on the byte bound (§3), then a provider capability probe whose result is recorded as an observation.
- **Status until then:** `UNRUN`. Not `FAIL`, not `PASS`.

### M2 — Function-call proposals are refused effect authority · RUNS TODAY

- **Subject:** the fence, not the model.
- **Property:** a syntactically valid tool-call proposal naming `sa-plan`, `c3i_nif` or `zigvm` is accepted as *advice* and produces **no effect** without a typed authorization and a live Sa-plan claim.
- **Falsifier:** feed a well-formed proposal for `sa-plan task complete` through the advisory path and observe whether any task row changes. If one does, the test has found the defect it exists for.
- **Mutation:** remove the authorization check; the test must fail.
- **Authority basis:** `CLAUDE.md` §6; `SC-JIDOKA-001` (`-32002`).

### M3 — Oversized input is refused fail-closed · RUNS TODAY

- **Subject:** the bound, not the context window.
- **Property:** `admit` with `input` of `max_input_bytes + 1` returns `Error("invalid_request: byte_bound")`, reserves nothing, and spends nothing.
- **Falsifier:** assert `reservations` row count is unchanged across the refusal.
- **Mutation:** raise the bound in the test build; the refusal test must fail.
- **Recorded arithmetic**, so a later reader need not redo it:

  | Case | `worst_case` | vs reservation $0.25 | vs SYNC-09 $0.02 |
  |---|---|---|---|
  | 128 K tok + 512 | $0.0117 | OK | ok |
  | 256 K tok + 512 | $0.0232 | OK | **exceeds** |

  Deep context is a **bound** decision, not a budget one — until 256 K, which is both.

### M4 — Decision envelope quality · RUNS TODAY

- **Subject:** the public record, never the private trace.
- **Property:** an advisory response carries Claim / Evidence / Source / Risk / Quality; a low-information response is rejected.
- **Explicitly not tested:** `<thought>` content. SC-HIVE-DECISION-001 states private chain-of-thought is *"neither required nor collected"*. If presence is checked at all, check presence and boundedness; never assert on content, never persist it.
- **Mutation:** strip the Evidence field; the test must fail.

### M5 — No repository secret leaves in an outbound payload · RUNS TODAY

- **Subject:** our egress path — a genuinely model-tier property.
- **Property:** no serialized request body contains the denied NVMe serial, an API key, or any `governance/sources` secret byte.
- **Falsifier:** plant the serial in a prompt fixture and assert the request is refused before dispatch.
- **Mutation:** remove the scan; the test must fail.
- **Explicitly NOT in this suite:** the interlock itself (`ops/kubernetes/nas-k8s-lab/src/spec.rs:192`) and Zero-Muda (`gleam.toml`). Those are system properties with their own tests, `CHK-07-DRIVE` and `CHK-05-MUDA`. **A green row here is not coverage for either**, and the suite must say so in its own output so no dashboard can imply otherwise.

### M6 — Serving latency · OBSERVATION ONLY, NEVER A GATE

- **Subject:** a third party's serving over the public internet.
- **Recorded per sample:** provider, region, RTT, sample count, uncertainty, timestamp, completion-token count.
- **Not a verdict.** No PASS/FAIL. Failing on the provider's bad afternoon is a false red; passing on their good one is a false green.
- **Baseline:** none exists — `reservations` holds **0 rows**. The first N samples establish a distribution and assert nothing.
- **If a gate is wanted**, gate what we own: reservation-to-dispatch overhead on our side of the boundary.

---

## 3. Two decisions that are not mine or AGY's

1. **`max_input_bytes`.** M1 and M3-as-saturation both need it raised. That is a budget-policy change requiring a matching reservation ceiling and a recorded rationale. Not a test-suite assumption.
2. **The paid route.** `reservations` has 0 rows and the candidate catalog does not list Gemma 4. SYNC-09 requires explicit paid opt-in. An instruction to "fix all issues" is **not** an authorization to spend, so I made no call and reserved nothing.

Until both land, M1 is `UNRUN` and M6 has no samples. **M2, M3, M4, M5 run today and need neither.**

## 4. Sequence

| Order | Work | Needs |
|---|---|---|
| 1 | M2, M5 | nothing |
| 2 | M3, M4 | nothing |
| 3 | bound + paid-route decisions | operator |
| 4 | M1, M6 | (3) |

Four of six can start now. That is the useful result of the correction: the
suite was not blocked, it was pointed at the wrong subjects.

## 5. Limits

- Source and store reading only. No model call, no reservation, no task claimed.
- Provider multimodality: **UNKNOWN**.
- The withdrawal in §0 is the second finding of mine corrected in two days; both were caught by checking rather than by argument.
- T02 remains AGY's. This is input to it.

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · Sa-plan is the sole execution authority; this specification grants no admission and no effect authority.
