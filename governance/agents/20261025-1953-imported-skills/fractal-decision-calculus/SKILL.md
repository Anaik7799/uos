---
name: fractal-decision-calculus
description: Use when ranking or sequencing a backlog, selecting an architecture / approach / toolchain, prioritizing work, or making any high-stakes multi-criteria decision under uncertainty — especially when the inputs may be stale, the sources disagree, or it is unclear whether the problem is simple or genuinely complex. Governs how zigvm decisions are made, at every scale.
---

# Fractal Decision Calculus (FDC)

Sa-plan control-plane rule: every decision frame, Rete/ruliological result,
Admiralty/ACH assessment and agent transition is submitted through the typed
OCaml Store and remains advisory until durable task state and the harness gate
agree. Prose or UI state cannot complete a task.

The project's decision-making algebra: **one OODA-keyed pipeline that composes nine
techniques into a mathematically-robust, live-state-grounded, fail-closed decision**,
applied self-similarly at slice, epoch, and program scale. It is the ORIENT/DECIDE engine
under `algebraic-fractal-structures`' OODA loop.

**The failure it exists to prevent (a real one):** a sequencing plan authored from stale
`slice_backlog` notes ranked an already-shipping native JIT as "unbuilt XL work" and
omitted the true scale blocker (the coordinator lock). A three-way adversarial review
computed that decision to be **~99% wrong (Bayesian posterior 0.014)**. Root cause: a
low-grade input (a stale note — Admiralty **C3**) drove a decision as if it were verified
truth (**A1**). FDC makes that impossible by construction.

## THE LAW — decide only on FRESH, GRADED, LIVE state

Every decision-critical input carries an **Admiralty grade** = source reliability (A–F) ×
info credibility (1–6). **No input below A2 may drive a decision until re-verified against
HEAD.** A backlog note, a memory, a handover, a prior plan, an agent's summary = **C3 by
default** (stale / second-hand) → it MUST be re-confirmed against a PRIMARY source (a
source `file:line` at the exact commit, a live DB row, a `DIVERGENCE_LOG` entry) before it
counts. This is the OODA *Observe* step; it is mechanized (§5). The entire stale-input
class of error is fail-closed out — this is the one rule that, alone, would have blocked
the bad plan.

## §1 FRAME — Cynefin routes the decision (pick the pipeline depth)

| Domain | Signature | Technique | Loop |
|---|---|---|---|
| **Clear** | known cause→effect | best practice + Zero-Muda; just act | fast |
| **Complicated** | known unknowns, expert-analyzable | AHP + Pugh (§3) | full |
| **Complex** | unknown unknowns, emergent | **PROBE** — a cheap measure-first spike + ACH + Bayes (§2/§4); never rank-then-build | probe·sense·respond |
| **Chaotic** | no discernible cause (red gate, incident) | act to STABILIZE first, then re-frame | act-first |

**The cardinal routing error** (and the original one): applying a Complicated-domain rigid
ranking to a Complex sub-question. *"Is the JIT worth building?"* is Complex — unknown until
measured — so it must be **probed** (grep the source / measure the floor), never **assumed**
into a score. A Complicated program decision routinely nests Complex sub-decisions that
demand spikes, not numbers; route each independently.

## §2 ORIENT — de-bias before you score (three lenses, always)

- **ACH (competing hypotheses):** enumerate ≥2 rivals; build the hypothesis×evidence
  matrix; the winner has the **fewest DISCONFIRMATIONS** (not the most confirmations), and
  you must actively hunt disconfirming evidence. *Worked:* H1 "JIT is an unbuilt stub" vs
  H2 "JIT is built + wired default." `dispatch.zig:122=true`, `proc.zig:6510` default,
  DIVERGENCE 574/608 (bugs found *inside* the production JIT) each DISCONFIRM H1 at grade
  A1; only a C3 backlog note supports it → **H2 wins decisively.**
- **Devil's Advocate:** a present-tense adversary argues AGAINST the leading option.
  Mechanize as independent read-only critic agents — one per axis (muda / architecture /
  ranking); diversity of lens beats one skeptic.
- **Pre-mortem (prospective hindsight):** assume the plan has ALREADY failed
  catastrophically in the future; work backward to the killing cause. Surfaces the SPOFs
  groupthink buries. *Worked:* "scale-parity never arrived — why? we flipped
  multi-scheduler-default WITHOUT narrowing the coordinator lock → Amdahl on a
  hold-dominated global lock → ~zero real parallelism." → the mitigation (**narrow the lock
  BEFORE the default-flip**) becomes a hard edge in the plan DAG.

## §3 DECIDE — the math (Complicated domain)

**AHP for the criterion weights** — never ad-hoc numbers. Pairwise-compare the criteria on
Saaty's 1–9 scale, take the principal eigenvector (geometric-mean of each row, normalized)
as the weights, and **check the Consistency Ratio `CR = CI/RI < 0.10`** (`CI =
(λmax−n)/(n−1)`, RI the Saaty random index) — if CR ≥ 0.10 the judgments are incoherent,
redo them. The parity-decision criteria + derived weights (CR = **0.006**, consistent):

| Criterion | Weight |
|---|---|
| **Needle-movement** — flips UNTESTED/DIVERGENT → measured/EQ | **0.413** |
| Unblocking-power | 0.176 |
| Real-user-value | 0.162 |
| Low-risk | 0.162 |
| Lean-effort | 0.088 |

`Score(item) = Σ wᵢ·sᵢ` with each `sᵢ∈[0,1]`, and the value+needle terms multiplied by
**γ = 0.7 for work that merely hardens an already-achieved milestone** (the *already-achieved
discount* — else sunk cost masquerades as value).

**Pugh vs a baseline** — for iterative / design choices: fix the status quo as baseline,
score each alternative Better(+1)/Same(0)/Worse(−1) per criterion; the winner must PROVE
where it beats the baseline. *Worked:* the corrected parity plan vs the stale-note baseline
scored **+5** (better on needle, effort, risk-honesty, state-fidelity, muda) — total
domination flags the baseline as *broken*, not merely weaker.

## §4 ACT + VERIFY — pull-based, measure-first, Bayesian-gated

- **ACT** is Zero-Muda gated: an XL "build" is never executed on faith — first run the
  cheapest **prove-the-need spike** (measure before build), and build only what a real
  consumer **PULLS** (just-in-time, not just-in-case). Automate recurring heartbeats
  (smoke / re-measure) into timers/CI; never hand-sequence them. Single-piece-flow, not
  batched WIP.
- **VERIFY** updates a **Bayesian posterior** `P(decision-correct | new live evidence)`
  after acting + re-observing HEAD; below threshold → re-loop. *Worked:* prior 0.5; after
  E1 (JIT-built, A1) → 0.10; after E2 (lock omitted, A1) → **0.014** — a number, not a
  vibe, that made the rewrite mandatory. This IS the fast OODA-verify: a targeted
  fact-check against source, not a fresh analysis.
- **The posterior is INTERPRETED, not just reported** (`harness/prob_classify.ml`, the
  intelligence-assessment classification): it is mapped onto the **PHIA/NATO estimative-
  probability yardstick** (0.67 → "Likely / probably, 55–75%"; a value in a gap → an honest
  buffer, never false precision), framed by **subjective expected utility** (relying pays off
  only above the break-even `p* = cost/(benefit+cost)`), and overlaid with a **behavioural
  bias taxonomy** (mindware gaps / valuation biases / anchoring distortions, each with the
  guard the report provides). The full Stan pipeline backs it — stanc3 validation, cmdstan
  NUTS + non-conjugate models, a **native in-process OCaml MCMC** (no CLI), and the exact
  conjugate oracle (the admission triangle) — all **report-only, never gating**
  (`skills/stan-probabilistic-substrate`). Runnable over real telemetry via
  `--stan-scenarios`; published each cycle with an idiot-proof lead + ASCII yardstick.
  **Post-S12:** the native tier carries its OWN two-leg trust verdict (split-R-hat/ESS
  convergence AND posterior-predictive adequacy), is **SBC-measured CALIBRATED**
  (`--stan-sbc`), and feeds the calibration ledger (`--stan-predictions` /
  `--stan-resolve`) toward the empirically-earned vocabulary.

## §5 The mechanism — intimately bound to live state (fast OODA-verify)

OBSERVE and VERIFY pull inputs LIVE and grade them; the loop stays fast because Cynefin lets
Clear decisions skip §2–§3 and VERIFY is a one-query fact-check:

```
Observe : slice_backlog + verdicts + source@HEAD + DIVERGENCE_LOG   → each Admiralty-graded
Orient  : ACH matrix (disconfirm) · devil's-advocate agents · pre-mortem
Decide  : AHP weights (CR<0.10) · Pugh vs baseline
Act     : Cynefin-routed — probe/spike (Complex) | top score (Complicated) | stabilize (Chaotic)
Verify  : Bayesian posterior on re-observed HEAD; < threshold → re-loop
```

Concrete OBSERVE/VERIFY sources — **the harness is the ONLY database path; never a raw
SQLite/CLI/foreign client** (Database Access Law): `--ooda-observe` (live backlog +
`next_slice`), `--capability-ledger` / `--conformance` (the verdict + {C} ledgers), and
`grep -n … src/<file>.zig` at `git rev-parse HEAD` for primary source truth. **An input is
A1 only if it is a fresh read at current HEAD through the harness or the source tree.**
**Mechanized (LANDED): `--decision-frame`** (`harness/decision_frame.ml`) — a REPORT-ONLY
OCaml mode that reads live `slice_backlog` through the `Db` actor, **self-verifies its own
math every run** (15 fail-closed laws + 2 killed mutants), and emits the Admiralty-graded
inputs + the AHP weights/CR + the ranked frame + the STPA risk posture (`safety_ucas`) + the
Bayesian VERIFY leg — now rendered as the **full per-cycle Stan report** (idiot-proof
plain-language lead + ASCII credible-interval chart + PHIA/NATO estimative classification +
ASCII yardstick + bias-taxonomy overlay + a glossary explaining every term, the native
in-process MH supplying the band admitted vs the exact closed form) — + a conservative FRAME
VERDICT + its OWN blind spots.

**SAFETY-CRITICAL posture (aerospace/medical/military/automotive):** the tool is an ADVISORY,
NEVER an authority — a frame with ANY sub-A2 input DEGRADES to advisory-only (*absence of
verification == presence of risk*, fail-closed); over-trust (automation bias) is the named
dominant hazard, countered by emitting the blind spots on every run; the analyzer's own math
fails closed if a law reddens. Substrate coverage is HONESTLY **4/9**: `Db` + STPA +
closed-form Bayesian + **formal-proof** (`proofs/Decision_Calculus.v` machine-checks
**12 theorems** to Qed — the pointwise algebra (fail-closed verdict, Admiralty cut, score
monotonicity, CR gate, ratchet) AND the FRACTAL SYSTEM: all-10-layers exhaustiveness,
control-flow fail-closed, data-flow degrade, the all-layers fractal invariant, and
closed-loop convergence — gated by `--verify-formal`) + **ZK** (`--decision-frame` records
each frame as a traceable `docs/zk/episodic/` note) + **Rete-UL** (the `SP-DEC-A2-GUARD` gate
rule is ARMED + gate-live in `rete_rules.ml`; 2 more candidates generated-not-armed) +
**durable Oban/Temporal-style orchestration** (`--fdc-workflow` persists the OODA-stage DAG
in a dedicated `fdc_workflow` table and RESUMES from the DB, dependency-ordered) + **Stan**
(`harness/stan_infer.ml` links stanc3's OCaml libraries in-process — validates the authored
Beta-Binomial `.stan` model, fail-closed; the exact conjugate posterior annotates EVERY
decision's VERIFY, report-only / no-authority) are WIRED — **8 of 9**; only Raven ML is
staged. Arming the other 2 Rete candidates + building Stan's C++ MCMC sampler are
reviewed/deferred steps (never auto-modify a gate; conjugate closed-form is the exact
oracle). Never overclaimed. Full analysis,
strengths, blind spots, and the honest weaknesses:
`docs/journal/20260803-fractal-decision-calculus-journal.md`. Authored in OCaml, never Python
(a scratch calculator may derive numbers but never enters the tree).

**FRACTAL reliability:** the identical pipeline runs at slice (go/no-go), epoch
(sequencing), and program (strategy) scale; each scale's VERIFY feeds its parent's OBSERVE.
Dependability is the fixpoint — no scale decides on ungraded state, so a stale input can
never propagate upward.

## §6 Closed-loop learning + red/blue war-gaming (SAFETY-CRITICAL)

A decision tool that does not learn from its own errors is unsafe. Every blind-spot,
mistake, or error is recorded in **`docs/DECISION_RCA_LOG.md`** (the fractal RCA history)
and closed through a PERMANENT, mechanically-enforced guard: a SAFETY hazard → an STPA UCA +
constraint (`--safety-sync`); a mechanically-checkable error → a Rete-UL fail-closed rule
(the `SP-SIF-GUARD` shape, facts projected from reality); a recurring judgment gap → a
LEARNING update (Bayesian priors, the `blind_spots` list that GROWS and is emitted every
run, the calibrated instruments, Raven once labelled). The loop is closed only when a fresh
occurrence is stopped MECHANICALLY, not by intention.

**Red/blue war-gaming:** a high-stakes decision must SURVIVE an adversarial play before
acceptance — RED team (independent critic agents, one per lens, no shared scratchpad) attacks
the leading option, exploits each emitted blind-spot, and injects worst-case / stale /
correlated-failure inputs; BLUE team defends with primary-source evidence or concedes;
scenario checks S1–S5 (every input one grade worse; the fresh input is actually stale;
"independent" critics share a hidden source; the true best option is outside the frame; the
objective was mis-specified). **An un-war-gamed high-stakes decision is DEGRADED to
advisory-only, exactly like an unverified input.** Every red finding → an RCA entry → the
closed loop. The 3-agent review that computed the v1 plan's posterior at 0.014 WAS such a
play. Full protocol + this session's RCA entries: `docs/DECISION_RCA_LOG.md`.

## Composes with
`algebraic-fractal-structures` (the per-slice packet FDC ranks) · `otp-conformance-protocol`
(verdicts move only by fixing — the Needle axis reads that ledger) · `stpa-safety-protocol`
(the Risk axis + Pre-mortem feed the UCA/FMEA tables) · `formal-technique-selection` (the
Cynefin stage routes into it) · `smp-concurrency-slice` (the Complex-domain probe protocol
for the coordinator-lock decision). Worked end-to-end example: `docs/OTP30_TOBE_SEQUENCING_PLAN.md`.
