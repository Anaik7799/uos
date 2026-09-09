# 20260909-0249 — Capability symmetry with selective activation

#fractal-l0 #fractal-l5 #fractal-l8 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260909-0249-agentic-ecology.md) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Machine specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0249-agentic-ecology-spec.json)

Observed host UTC: 2026-09-09T02:16:49Z. Sa-plan `uos/ecology/20260909-0146`. Task-local permanent decision; no numbered ADR or EV admission is asserted.

The operator wants the whole agentic ecology to participate, with each holon selecting the services it needs. Use a shared typed capability catalogue, an independent activation mask and execution receipts. Keep runtime ownership and effect authorization outside the capability result.

A service is a function from a bounded typed request and current context to `Masked | Unavailable | Engaged(result, evidence)`. The catalogue is identical for every participant; the active set can be empty. Models, live storage, ML computation and remote advice retain distinct backend identities.

The rejected alternative was treating executable presence, invocation counters or static simulated drift as evidence that an intelligence service had run. That obscures failure and cannot support autonomous recovery. The accepted implementation retains actual failure receipts, finite bounds and a supervised state lifetime.

Consequences: local analysis can continue when OpenRouter is unavailable. A failed worker cannot block the ecology heartbeat indefinitely. Learning from cadence observations changes local belief state; it is not a claim of open-ended intelligence improvement, model training or safe self-modifying deployment. External Claude/Codex/AGY and UCon bindings still require explicit connection evidence.

The review falsifier `{choices:[]}` previously produced a successful empty model answer; strict decoding now refuses it. A child that calls `setsid()` escapes process-group cleanup, so that helper's claim is narrowed and managed service containment must be observed separately.

The actual free model and MAX ports subsequently passed startup and controlled restart recovery on the canonical OTP29 service. The operator added10USD/day paid model authorization and requested a needs-based engine review. Extend the existing pure operation-class router with one durable reservation/receipt path; keep paid profiles explicit, keep model-quality claims tied to independently verified outcomes, and preserve the separate free path. [Review and recommendation](http://nas-1.tail55d152.ts.net:4100/docs/design/20260909-0314-openrouter-engine-review-and-recommendation.md) records the source findings and design. Paid/adaptive operation is not implied by a healthy free/MAX baseline.

**Previous:** [Shared ecology wiki](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260909-0249-agentic-ecology.md) · **Next:** [KM machine index](http://nas-1.tail55d152.ts.net:4100/files/governance/capability-inventory/20260909-0249-ecology-km-index.json)

<details><summary>Verification checklist — 5 domains, 18 checkpoints</summary>

| Domain | Checkpoints | Current scope |
|---|---|---|
| Metadata/navigation | CHK-01-TIME, CHK-02-TAIL, CHK-03-FRACT, CHK-04-KM | Observed host UTC; linked grouped artifacts. Live publication checked separately. |
| Purity/storage | CHK-05-MUDA, CHK-06-GRAPH, CHK-07-DRIVE | Existing tools reused; no storage-device actions. Fleet gates UNRUN. |
| Verification | CHK-08-C1C8, CHK-09-MATH, CHK-10-9MOD, CHK-11-REGR | Scoped tests and finite models; full system checks UNRUN. |
| Runtime/observability | CHK-12-GLEAM, CHK-13-HERMES, CHK-14-ZIGVM, CHK-15-MAX, CHK-16-OTEL | OTP, bounded OCaml and actual MAX checked separately. ZigVM and complete OTel binding UNRUN. |
| Governance/JJ | CHK-17-SOV, CHK-18-JJ | Sa-plan task ownership; standalone JJ. Whole-system admission NOT_ADMITTED. |

Domain 6 provenance: admitted EV ceiling remains 93. No EV or ADR number is minted by this task.
</details>

**UOS footer:** Local implementation and observed behavior have explicitly bounded scope; no whole-system admission.
