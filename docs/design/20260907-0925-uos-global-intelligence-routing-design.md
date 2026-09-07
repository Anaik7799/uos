# 20260907-0925- Global intelligence routing: cheapest adequate tier for every operation
#fractal-l0 #fractal-l1 #fractal-l5 #fractal-l7 #km-triad #zero-muda #tailscale-web #uos-tui #swarm #cost #bayes

- **Design Identifier**: `DES-UOS-INTEL-ROUTING-001`
- **Timestamp**: `20260907-0925-`
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-0925-uos-global-intelligence-routing-design.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-0925-uos-global-intelligence-routing-design.md)
- **Operator directive (verbatim)**: "use the chepest intelligenge avaliable of a required operation - globally optimize from claude, codex, agy or openrouter for all operations"
- **Transclusions**: `[[zk:20260907-0537-adr-062-uos-tui-swarm-hive-mind-message-board-coordination-acl-and-zenoh-infra]]` `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]` `[[wiki:20260907-0537-uos-hive-mind-architecture-wiki]]`
- **Status**: design only (implementation paused by operator steering; prototypes not admitted). Authored by the L0 design authority (Fable); to be reviewed by Codex Astra and Antigravity.

## Comprehensive Verification Checklist (SC-CHECKLIST-001)
<details><summary>18 checkpoints (design-time status)</summary>
CHK-01 PASS · CHK-02 PASS · CHK-03 PASS · CHK-04 PASS · CHK-05 PASS (no new dependency) · CHK-06 PASS · CHK-07..11 DECLARED · CHK-12 PASS (router lives in Gleam policy, `coord`/`agent_runtime`) · CHK-13..15 DECLARED · CHK-16 PASS (every routing decision is a board message with trace/span ids) · CHK-17 DECLARED (review pending) · CHK-18 PASS
</details>

## 1. Problem
Four intelligences are available to the hive mind: Claude tiers (Haiku, Sonnet, Opus, Fable), Codex (gpt-6-astra), Antigravity (Gemini 3.8 Flash) and OpenRouter (any allowlisted model, free or paid). Today the choice is made by hand per swarm round. The directive asks for a global optimum: every operation goes to the cheapest intelligence that is adequate for it, with the more expensive tiers reserved for what only they can do.

## 2. Formal statement
Let `O` be the set of operation classes and `T` the set of tiers. For an operation `o` with candidate tiers `T(o) ⊆ T` (the tiers whose capability and authorization admit `o`):

```
route(o) = argmin_{t ∈ T(o)}  E[cost(t, o)]
           subject to  P(adequate(t, o)) ≥ θ(o)        (adequacy threshold per class)
                       cost(t, o) ≤ budget(o)           (hard cap per operation)
                       authorized(t, o)                 (coord policy: design kinds need model = fable)
E[cost(t, o)] = price_in(t)·tokens_in(o) + price_out(t)·tokens_out(o) + λ·latency(t, o) + ρ·retries(t, o)
P(adequate(t, o)) ~ Beta(α_{t,o}, β_{t,o})             (updated from verified outcomes on the board)
```

Escalation: if the routed tier fails verification, the next-cheapest tier in `T(o)` is tried once; a second failure is a jidoka stop (andon red) and the L0 authority decides. The posterior of the failed pair is updated so the router learns. This is the Thompson-sampling selector already present in `agent_runtime.choose_model`, generalized from Claude tiers to all four providers and from one global prior to one prior per (tier, operation class).

## 3. Measured prices and adequacy (this session, 2026-09-07)
| Tier | Provider | Price (USD / token, in / out) | Source of the number | Observed adequacy |
|---|---|---|---|---|
| deterministic (F´ manager, CLI, audits) | BEAM | 0 / 0 | by construction | 16/16 cycles; all audits; regeneration |
| OpenRouter free (`:free` models) | OpenRouter | 0 / 0 | live price list | unusable under this account's data policy (404 × 3, 403 × 1) |
| OpenRouter nano (`openai/gpt-4.1-nano`) | OpenRouter/Azure | 1.0e-7 / 4.0e-7 | live price list; call cost USD 0.0001061 | 1/1 sanitized advisory review, correct and specific |
| OpenRouter flash-lite, mistral-small | OpenRouter | 1.0e-7 / 4.0e-7; 7.5e-8 / 2.0e-7 | live price list | not yet exercised |
| Claude Haiku 4.5 | Claude (weight 0.27 of Sonnet) | 1.0e-6 / 5.0e-6 (via OpenRouter list) | ledger, `default_tiers` | 4/4 verifier slices, 1/1 doc slice |
| Claude Sonnet | Claude (weight 1.0) | relative weight only | ledger | 10/10 code slices round 1, 5/5 hardening slices H2 |
| Antigravity (Gemini 3.8 Flash) | agy CLI | not metered by UOS | subscription | sovereign review: correct P0; mainline verification 448/448 |
| Codex Astra (gpt-6-astra) | codex CLI | not metered by UOS | subscription | sovereign review: 8 correct P1; integration writer |
| Claude Opus / Fable | Claude (weight 5.0) | relative weight only | `default_tiers` | design authority; every Plan/Dispatch/Integrate |

Round-1 workers produced 57,033 output tokens against 52.5 M cache-read tokens; H2 workers consumed about 330–390 k harness tokens each. The deterministic manager costs 0 tokens per cycle. The cheapest external intelligence that worked is four orders of magnitude cheaper per call than a Sonnet slice.

## 4. Operation classes and their default route
| Class | Examples | Default tier | Escalation | θ |
|---|---|---|---|---|
| R0 runtime control | reconcile, leases, heartbeats, health, audits, regeneration, dashboards | deterministic (0) | none (it is code) | 1.0 |
| R1 mechanical verification | format, warnings, test runs, ownership and forbidden-pattern checks | deterministic script, else Haiku | Sonnet | 0.95 |
| R2 summaries and docs from code | feature sheets, lexicons, KPI tables, wiki sections | Haiku; OpenRouter nano for prose polish | Sonnet | 0.9 |
| R3 advisory second opinion | sanity check of an invariant, alternative listing, risk brainstorm | OpenRouter nano (≤ USD 0.02, ≤ 512 tokens) | Haiku → AGY | 0.8 |
| R4 bounded implementation | one Gleam module + tests with a written brief and disjoint ownership | Sonnet | Opus / Codex Astra | 0.9 |
| R5 security and architecture review | sovereign review of a candidate revision | Codex Astra and Antigravity (both, independent) | Fable arbitration | 0.95 |
| R6 design authority | plans, dispatch briefs, integration, cross-cutting refactors, admission | Fable (policy-enforced) | none | 1.0 |

Free tiers are always tried first when their data policy allows the payload class; the account's current policy blocks them, so the router must record the refusal and fall through to the paid floor without retrying every call (cache the refusal for one hour).

## 5. Mechanism (to implement when the pause lifts)
1. `coord.Policy` gains `routes: List(#(OperationClass, List(Tier)))` and `budgets`; `authorize` already enforces the design-authority rule.
2. `agent_runtime.choose_model` takes `(class, candidates, posteriors)` and returns the cheapest tier whose sampled adequacy meets θ; the posterior key is `(tier, class)`; updates come only from verified outcomes (a green verifier or a passed audit), never from self-report.
3. Every routing decision is a `Dispatch` on the board with payload `class`, `tier`, `estimated_usd`, `reason`, `alternatives`; every outcome is a `Report` with `actual_usd` and `adequate=true|false`. Costs roll into the shared `usage` state so the global spend is visible per agent and per class.
4. OpenRouter goes through the existing advisory worker (allowlist, live price check, budget, timeout, no tools). Codex and Antigravity are invoked through their CLIs by the L0/L1 layer only, with the invocations recorded in the ledger (they are not metered, so their cost is tracked as calls and wall time).
5. Global optimization: the manager's OODA loop reads the per-class spend and adequacy from the usage state and lowers θ-satisfying tiers over time (Haiku takes over what Sonnet proved unnecessary), and raises them on jidoka. The objective is total USD per verified outcome, not per call.

## 6. Risks and controls
- Adequacy drift: a cheap tier that passes verification on easy slices may fail on hard ones; θ is per class and the posterior is per (tier, class); a jidoka stop resets to the previous tier.
- Data policy: free and cheap external tiers must never see private source or prompts (`sanitize_check`); only R2/R3 payload classes are eligible for OpenRouter.
- Metering gaps: Codex and Antigravity are subscription CLIs; their cost is tracked as calls and time until a metered path exists.
- Authority: the router can lower cost, never lower authority; R6 stays with Fable by policy.

## 7. Decision
Adopt the routing function of §2 with the defaults of §4 as the hive mind's dispatch rule. Until implementation resumes, the L0 authority applies it by hand: deterministic first, OpenRouter nano for advisory checks, Haiku for verification and docs, Sonnet for bounded code, Codex and Antigravity for sovereign review, Fable only for design and integration.
