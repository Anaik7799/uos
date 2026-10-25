---
name: stan-probabilistic-substrate
description: Govern any use of Stan/stanc in the harness — posterior estimation over the system's own telemetry, trigger-gated behind the substrate test (real data + a uniquely-Bayesian question + an independent oracle), report-only forever. Use when a slice proposes probabilistic modeling, credible intervals, population/remaining-work estimation, flake-rate posteriors, or anything touching vendor/stanc3, and to check whether the S20 trigger has fired before ANY Stan runtime work.
---

# stan probabilistic substrate — posteriors without authority

Stan's unique offer to this system: **posterior uncertainty over small
generative models of data the harness already records**. Not
classification, not ranking (Raven owns those), and NEVER a decision
authority. Catalogs of record:
`docs/journal/20260801-stan-usecase-catalog.md` (50 solo uses, ranked) ·
`docs/journal/20260801-composed-intelligence-catalog.md` (compositions +
waves + the FVSI argument) ·
`docs/journal/20260801-substrate-usage-map-pass4.md` (disposition).

## Current state (verify before believing any doc)

- **LANDED (2026-08-03, under an explicit standing user mandate — "fully
  implement, integrate and use stanc in all decision-making, mandatory"):
  a full four-layer integration, all REPORT-ONLY.** (1) stanc3 validates
  models in-process (`harness/stan_infer.ml` links `stanc.driver`/
  `stanc.frontend`; isolated exe — the Jane-Street `Core` conflict); (2)
  the cmdstan NUTS runtime is built (`vendor/cmdstan/`, gitignored) and
  sampled via Unix exec, NON-conjugate models included
  (`docs/stan/fdc_logistic.stan`); (2b) a NATIVE pure-OCaml seeded
  Metropolis-Hastings sampler (`harness/stan_mcmc.ml`) runs MCMC with NO
  CLI/C++ — the answer to "MCMC directly via OCaml"; (3)
  `harness/stan_report.ml` publishes, per decision cycle, the posterior +
  diagnostics + a fail-closed TRUST verdict + a plain-language ("idiot-
  proof") lead + an ASCII credible-interval chart + a STANDARDIZED
  INTELLIGENCE-ASSESSMENT classification (`harness/prob_classify.ml`:
  PHIA/NATO linguistic-probability yardstick + ASCII yardstick + subjective
  expected utility + a behavioural bias taxonomy — mindware gaps / valuation
  biases / anchoring distortions — with a glossary explaining every term) +
  the full interpretation, to a durable ZK note. `--stan-scenarios` RUNS the
  whole classification over REAL recorded telemetry (gate reliability, slice
  completion, cycle success, capability EQ), over the **20 most-exercised
  implemented features** (P(conformant = EQ or documented-EQUIV), byte-EQ shown
  separately so an EQUIV feature is never mislabelled broken), and over **12
  complex high-stakes decision-areas** (distribution, SMP/signals, GC, maps,
  binaries, ETF, match-specs, phash2, atomics, exceptions, arith) — each a
  portfolio confidence view with a DECISION-USE note; and fail-closed VERIFIES
  utility (a data-bearing scenario that cannot yield a well-defined, admitted,
  classified posterior reddens the mode). Areas are HEURISTIC name-based
  groupings — a surprising band is a prompt to investigate, never an auto-block.
- **Utilization plan of record: `docs/STAN_DECISION_UTILIZATION_PLAN.md`**
  (2026-08-03 Fable analysis): the tier doctrine T0–T4, the four access
  layers' unused surface (8 cmdstan methods incl. `log_prob` gradients via
  exec; stanc3 pedantic + `--info`), ranked waves W1–W3, the fractal
  cross-product (L0–L10 × components × STPA UCA-STAN-1..4 × FM-STAN-* FMEA),
  and the standing rejects. **W1-1/2 LANDED (slice `stan-w1-honest-units`):**
  the serving path is `Stan_bridge.latest_verdict`+`censored_counts` (pure,
  law-covered, MUT-17/18); features report latest-verdict FACTS + a group
  posterior; areas are P(conformant|tested) over units' LATEST verdicts,
  UNTESTED censored; gate-reliability is P(a day CLOSES green) — per-day
  dedup, deliberate intraday mutant-kill reds excluded by construction.
  Honest shift: small groups get humble bands; the earlier phash2-79%/GC-84%
  "tail" was stale-history artifact — current-state latest verdicts are
  conformant across all areas.
- **PROGRAM COMPLETE (2026-08-03, S1–S12): W1 + W2 fully landed + SBC (W3
  trigger fired).** The serving stack is 100% P-class OCaml (SC-STAN-5 scan
  law): exact forms + Dirichlet vectors + prior-sensitivity → native MH + HMC
  with dual-number AD (`stan_ad.ml`) → native split-R-hat/ESS (vs stansummary
  on identical draws: |ΔR-hat|=0.0012, ESS 0.8%) → native PPC → the TWO-LEG
  trust verdict (converged AND adequate) → **SBC-measured CALIBRATED**
  (`--stan-sbc`, ranks uniform). cmdstan is oracle-only (verdicts surface;
  `stan-oracle-still-exercised` + the log_prob gradient admission |d|=0).
  ACH exact Bayes factors + SEU grounded in recorded magnitudes serve in
  `--decision-frame`; stanc3 pedantic-lint + `--info` schema laws bind the
  models; the calibration ledger (`--stan-predictions`/`--stan-resolve`)
  accumulates toward the earned vocabulary (honest-empty below 20). STPA
  closure: **SAFETY_ANALYSIS.md §15** (CTRL-STAN-ADVISORY, all constraints
  mechanized). ~70 laws; 42 mutants (40 killed + 2 EQUIVALENT with proof).
  Remaining W3 items strictly trigger-gated (flake-mixture / capture-recapture
  / latency / drift / wargame-priors / MIR-evaluator — triggers in the
  implementation plan; none fired). **v2 MANDATE (plan §11, binding): ALL Stan access via OCaml
  ONLY** — every decision-SERVING read is computed in OCaml (T0 exact / T1-T2
  native samplers+MAP/Laplace / native R-hat/ESS/PPC); cmdstan is DEMOTED to
  an oracle inside admission laws (its numbers never reach a report — only
  ADMITTED/FAILED does); SC-STAN-5: no serving module may touch a subprocess
  (source-scan law; `--decision-frame` already complies, zero `open_process`
  in serving modules). Keystones: W1-9 serving-path flip, W2-N native
  AD+HMC+diagnostics, W3-21 the stanc3 in-process MIR evaluator (single
  source of truth — the `.stan` file itself executable in OCaml).
  **Execution plan (slice-by-slice, cold-start ready):
  `docs/STAN_IMPLEMENTATION_PLAN.md`** — S1 `stan-w1-honest-units` FIRST
  (fixes published overconfidence), then S2 serving-flip … S11, W3
  trigger-gated backlog; each slice carries its named laws + mutants +
  done-criteria.
  (`docs/zk/episodic/stan-results-latest.md`). The ADMISSION TRIANGLE —
  exact conjugate closed form (`stan_bridge.ml`) == cmdstan NUTS ~= native
  MH — is the trust argument; no single sampler is believed on its own
  word. Command: `--stan` (22 self-verifying laws, MUT-1..8). Journal:
  `docs/journal/20260803-stan-full-integration-journal.md`; schema +
  build recipe: `docs/stan/README.md`.
- **The NO-AUTHORITY invariant is UNCHANGED and permanent:** posteriors
  ANNOTATE decisions, they NEVER gate. The mandate is satisfied by carrying
  a real Bayesian confidence beside every decision, advisory-only;
  posterior-gating remains the permanent reject.
- **The S20 trigger still governs NEW *autonomous* Stan work**
  (`stan-flake-posterior`, ≥10 recurrent `--seed-sweep` reds): outside the
  standing user mandate, proposing a new Stan use that does not pass the
  three-leg substrate test below is still scope creep — decline it.

## The substrate test (apply to EVERY proposed use)

A Stan use case earns a slice only with all three:
1. **Real data** already recorded (a SQLite table, a log, a ledger);
2. **A uniquely-Bayesian question** — the uncertainty IS the answer
   (population size, rate with credible interval, rule-out probability);
3. **An independent oracle** to admit against (frequency counts, SQL
   aggregates, later discoveries falsifying the posterior).

Failing any leg → REJECT or record a trigger. Standing rejects that no
argument reopens: P(fail) with informative priors (priors don't create
labels), posterior GATING of anything, replacement of ratchets/verdicts/
determinacy rules (posteriors ANNOTATE beside hard rules, never replace),
Bayesian re-treatment of working deterministic machinery (CUSUM-first for
changepoints; the seeded EJ Monte-Carlo stays).

## The high-value queue (pre-ranked; implement top-down when unlocked)

1. Population estimates: remaining bounded gaps / dead-dispatch instances
   (capture-recapture over DIVERGENCE discovery dates) — turns "exhausted"
   claims into falsifiable posteriors.
2. Suite-yield curation prioritization (Beta-Binomial over
   bugs-per-curated-suite).
3. Flake pair: per-test flake posterior + order-sensitivity rule-out
   (S20 itself).
4. Backend-latency posteriors over `smt_obligations`/`z3_solver_calls`
   (supplies S16's trigger EVIDENCE).
5. Obligation-outcome mixture drift (unknown-creep early warning).

## Mechanics when S20 fires (not before)

- A `.stan` model is an AUTHORED artifact; `stanc` output is a GENERATED
  codegen target (the `web/atlas.ts` precedent); the Stan math runtime is
  a vendored external C++ lib — all three land ONLY with a DISCLOSED
  carve-out entry in CLAUDE.md's boundary section (the sancov shim
  precedent), written in the same slice.
- The harness invokes `stanc` and the compiled model like it invokes the
  Zig toolchain: OCaml `Unix` execution, timeout-bounded, fail-closed on
  nonzero exit; NO shell scripts.
- Sampler outputs are seeded (fixed seed + chain count in the law),
  summarized by an OCaml kernel, and admitted against the analytic
  posterior where one exists (Beta-Binomial has closed form — the FIRST
  model must be conjugate precisely so the differential-admission oracle
  is exact).
- Laws per slice: seed-determinism of summaries, admission-vs-closed-form
  tolerance, report-boundedness, no-write; ≥2 mutants (chain-count drop,
  prior swap, summary fabrication — data-truth style).

## Ranking discipline for new proposals

Score on FMEA risk-reduction, STPA class (`obs`/`obs→trig` only — a
`ctrl` proposal needs a §10 packet and near-certainly indicates a design
error here), OODA stage (Observe/Orient; Decide only ever ADVISORY),
criticality, dependence depth. Anything Rank < 5 waits; anything touching
authority is refused regardless of rank.
