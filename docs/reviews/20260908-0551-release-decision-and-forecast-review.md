# 20260908-0551 — Reviewable release decisions, forecasts and convergence

#fractal-l0 #fractal-l4 #fractal-l8 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Runbook](http://nas-1.tail55d152.ts.net:4100/docs/sop/20260908-0551-web-release-sdlc-sre-runbook.md) · [Evidence](http://nas-1.tail55d152.ts.net:4100/docs/reviews/20260908-0551-homeostasis-release-verification.json)

Recorded 2026-09-08. This is an external decision summary: observable task state, evidence, choices, uncertainties and plans. It is not private model reasoning, hidden model internals, a consciousness measurement, a live hive registration or a board message.

## Task state, context and resources

Owner: codex-side-homeostasis-release; local session codex-side-homeostasis-release-20260908-0551. Plan: uos/homeostasis-release/20260908-0551, PREPARE attempt2. Work is confined to an isolated JJ workspace and explicitly owned bounded private staging. Production and peers' source remain unchanged. No subagents, peer dispatch, paid inference or external model calls were used.

Goal: repeatable, bounded web/homeostasis release preparation with equivalent OCaml/Mojo commands, typed Gleam lifecycle, truthful health, manual checks and fail-closed gates. The larger goal of a fully admitted stable UOS remains open.

Resources: existing OCaml5.5, Gleam1.16, OTP29.0.6/ERTS17.0.6, Mojo1.0.0, existing Python stdlib, Chrome/OCaml Playwright, pinned Determinate Nix profile, own Sa-plan task, cooperative lease and read-only VM-1 source access through its Tailscale FQDN.

Current evidence: build c0480a3a91323e4819e0d7e5c3eb7a1249565728; 84 scoped EUnit tests; 113 checker tests; 338 finite-model rows; 15 frontend parity cases; 69 browser assertions. Counts overlap and cannot be summed into a system-wide coverage percentage.

## Decisions and alternatives

| Decision | Evidence and rationale | Alternative / limit |
|---|---|---|
| Shared OCaml operational core, Mojo entrypoint and independent model | Existing OCaml process/JSON/crypto/browser tooling; shared semantics reduce drift | A separate Mojo deployment core needs its own process/security conformance. Finite parity does not prove all inputs. |
| Observe actual OTP/ERTS | Old production reports OTP29 with actual ERTS15; fixed candidate reports OTP29/ERTS17 and rejects contradictions | Configuration labels cannot establish runtime health. |
| Preserve production, verify private candidate | Empty production revision, unbound rollback and unresolved file-viewer security boundary | Immediate replacement lacks target-specific recovery evidence. A high score cannot override a blocker. |
| Keep missing measurements UNKNOWN | BEAM counters do not measure CPU percentage, application health, PID-control stability or quorum | Synthetic healthy values would invalidate operations. |
| Stop after relevant final checks pass | Final browser/parity passed at the packaged revision | Repeat tests only for changed behavior, a failure or a new material uncertainty. |

OCaml is easier for Codex to generate, inspect and test reliably for this repository's operational core because its required libraries and toolchain are established. Mojo supplies the compatible entrypoint and independent computational oracle. This is task-specific, not a universal language ranking.

## Forecasting: code presence versus measured use

The repository contains EMA/Kalman forecasts, subjective expected utility, Brier scoring and a persistent forecast store. Source inspection does not prove production uses calibrated live predictions.

In ha/fractal_forecast.gleam, forecast_health_json returns fixed nominal/converged/stable strings and Brier0.024 while explicitly setting demonstration_baseline, live_ledger_calibrated=false and live_ledger_sample_count=0. These are demonstration outputs. The separate forecast_store.calibration_from_db reads stored records and returns Undetermined for no resolved predictions. Its Calibrated constructor contains empirical mean squared probability error and sample count; the constructor name does not establish statistical calibration. No live forecast DB or calibration history was changed or verified here.

Five native builds took 44.918, 45.746, 48.079, 45.912 and 46.774 seconds. That post-outcome summary demonstrates inexpensive local rebuilds under observed cache/load conditions. It is not a precommitted forecast, confidence interval, SLO or guarantee for another host.

There is no calibrated probability of production success or completion ETA. Deployment has deterministic blockers. Future scored forecasts must be recorded before outcomes, with event, horizon, probability/range, source fingerprint, candidate, assumptions and resolution criterion. Resolve later; compute Brier only over resolved precommitted binary events with denominator, base-rate comparison and out-of-time reliability checks. Duration/cost forecasts need measured error and interval coverage. Never backdate a forecast.

For eligible work, expected loss reduction and information value per bounded cost/time are advisory tie-breakers. Safety constraints and dependency closure remain outside the optimization. With weak probability inputs use explicit scenarios and sensitivity checks, not invented precision.

## Which mechanisms actually ran

| Mechanism | Use in this slice | Unverified boundary |
|---|---|---|
| STPA / STAMP | Four unsafe-control-action categories mapped to rollback, target, freshness and bounded-retry constraints | Whole-system hazard analysis and independent certification |
| FMEA (operator “FEMA”) | Severity/occurrence/detection judgments and tested failure controls; PREPARE product768 | Calibrated failure probabilities or globally optimal ranking; ordinal product is a heuristic |
| STM / two-lattice discipline | Canonical attempt, own session, fresh heartbeat and epoch3 checked before effects; stale epoch2 refused an action | Atomic compare-and-act at every OS effect, linearizable distributed STM or new Lean/Quint proof; fence is cooperative |
| Rete-UL | Existing rule/anomaly verifier reviewed as reusable advisory substrate; new gates are explicit typed/checker predicates | No Rete service was wired into or used to authorize this release |
| F Prime / denotation | Existing UOS FPP interpreter reused for 12 stages, typed intents, held/recovering/rolled_back, fold/replay and finite differential tests | Official FPP compiler conformance or unrestricted temporal proof |
| Fractal RCA / Jidoka | Causes and containment traced L0–L9; failed prerequisites stop the smallest owned operation | No new global autonomous controller deployed |
| Forecasting / probabilistic advice | Measured cost, explicit uncertainty and forecast code review | No live calibrated forecast or model-authorized admission |

## Fast OODA standard work

1. Observe exact source/runtime identity, fresh task/lease, clock and named evidence. Preserve UNKNOWN.
2. Orient around loss and violated constraint. Apply hard blockers, then dependencies and criticality × STPA × FMEA band × dependency × impact. Check sensitivity; multiplied ordinal scores are not physical measurements.
3. Decide on the smallest bounded test/change that resolves a material uncertainty. Record expected observation, alternatives and a falsifier. Precommit forecasts if later scored.
4. Act only after fresh authority checks. Retain results and compare predictions with observations. Failure stops the affected transition; no blind retries.
5. Close or replan with source-bound evidence and gaps. Avoid duplicate dispatch and unnecessary rebuild/test repetition.

Future Rete integration should derive advisory hold/review recommendations from typed fresh facts with candidate, source and expiry. Test contradictions, stale facts and bounded execution against a simple independent oracle. Rule conclusions must never mint a lease, override an STPA constraint or deploy code.

## Requested Gemma advisory review

The operator requested OpenRouter Gemma4. Existing UOS code allowlists google/gemma-4-31b-it:free, and the approved environment credential is present (presence only checked). Live model availability/prices have not been queried. The installed client directly addresses the public provider; no existing Tailscale gateway was found in the bounded configuration review. This conflicts with the operator's all-operations Tailscale-FQDN rule. The gateway address was requested, and a sanitized bounded512-token/30-second/free-only review packet is retained in 20260908-0551-gemma-release-advisory-request.json. No provider request, spending or model verification is claimed. Once a compliant gateway is known, fetch the exact current model/price, issue one advisory request and retain actual usage/cost and response provenance. Never silently fall back to paid or another model.

## Next gates

Priority1: bind a recoverable production artifact and verify file-viewer authorization/path containment. Priority2: independent review, integration, target-specific draining/rollback and observed cutover. Priority3: broaden semantic UI/metric coverage and validate live forecast provenance, telemetry and distributed fencing.

Expected direction: resolving these prerequisites reduces the largest known release uncertainty. Magnitude and delivery date are unquantified until scoped owners and receipts exist. A successful private canary supports bounded local behavior; it cannot establish global stability or consciousness.


<details><summary>Verification checklist — five domains, 18 checkpoints</summary>

| Domain | Checkpoints | Scope |
|---|---|---|
| Metadata and navigation | CHK-01-TIME, CHK-02-TAIL, CHK-03-FRACT, CHK-04-KM | Timestamp, full Tailnet links, tags and evidence references |
| Purity and storage | CHK-05-MUDA, CHK-06-GRAPH, CHK-07-DRIVE | Existing runtimes only; no drive operations |
| Verification | CHK-08-C1C8, CHK-09-MATH, CHK-10-9MOD, CHK-11-REGR | Scoped test receipts; broader gates remain unverified |
| Runtime and observability | CHK-12-GLEAM, CHK-13-HERMES, CHK-14-ZIGVM, CHK-15-MAX, CHK-16-OTEL | Distinguish actual process observations from simulations |
| Governance and JJ | CHK-17-SOV, CHK-18-JJ | Independent admission outstanding; isolated JJ work |

No row grants a passing global checklist. Consult the revision-bound verification receipt.
</details>
