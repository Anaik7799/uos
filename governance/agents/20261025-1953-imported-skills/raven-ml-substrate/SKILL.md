---
name: raven-ml-substrate
description: Use the Raven OCaml ML ecosystem (nx, rune, kaun, talon, saga, hugin) in the harness under the sandwich doctrine — isolated executables, seed-determinism and persistence acceptance laws, differential admission against closed-form oracles, report-only suggestions with score/model-hash/seed. Use when building or modifying any learned component, ML dataset, ranking, regression, or telemetry visualization, or after ANY Raven-related opam change.
---

# raven ml substrate — learned components under the sandwich

Raven is the mandated ML substrate (user decision 2026-08-01; OCANNL not
selected). Formal spec: `docs/formal/harness-intelligence-algebra.md`
(Signature S). Landed exemplars: `harness/raven_substrate.ml` (acceptance),
`harness/ml_rank.ml` (first sandwich instance), `harness/raven_viz.ml`
(hugin telemetry), `harness/organ_learn.ml` (ontology trend organ).

## The doctrine (non-negotiable)

> ML SUGGESTS. SMT checks. Laws admit. Rete gates. A suggestion is a
> report row an agent or human verifies into a fact — never an authority.

- **Isolation (L47, mechanized over harness/dune):** no Raven package may
  appear in gate-critical `zigvm_harness.exe`'s libraries. Every ML
  consumer is its own executable (the organ_learn/zenoh_ffi precedent).
- **Differential admission:** a fitted result is admitted ONLY in
  agreement with an independent closed-form oracle (least-squares, exact
  counts) within tolerance — never "it trained, therefore it's right".
  On disagreement, fall back to the oracle and SAY SO in the output.
- **Label honesty:** the viability gate is real (`ml_train_viable`, ≥20
  positives). The P(fail) track stays dormant at ~1/702; priors do not
  create labels. Assert your dataset's viability as a LAW, not a hope.
- **Suggestion shape:** every emitted row carries score ∈ [0,1] (bounded
  by law), `model_hash` (models are versioned artifacts — FM-ML-DRIFT),
  and the seed (echoed on failure).

## Acceptance laws — run them, don't assume them

`./_build/default/harness/raven_substrate.exe` proves RS-L1
seed-determinism (at BOTH 3 pre-convergence steps and convergence),
RS-L2 hash-addressable persistence, RS-L3 differential admission.

**Rerun it after ANY Raven opam change.** Measured incident: a `kaun`
co-install DOWNGRADED nx/rune alpha3→alpha2, whose API splits `Rune.t`
from `Nx.t` — sources stopped compiling while stale binaries kept
passing. The acceptance exe is the drift detector.

## API notes (alpha2, the working idioms)

- `Rune` includes the full `Nx` module type over its OWN tensor type:
  build tensors with `Rune.create Rune.float32 [|n|] arr`,
  `Rune.scalar`, ops `Rune.{mul,sub,mean,square,broadcast_to,mul_s}`,
  read with `Rune.item [] t`, gradients with `Rune.grad loss w`.
  Do NOT mix `Nx.t` into autodiff code.
- Deterministic init derives from an explicit seed (`init_of_seed`), no
  library RNG in training loops.
- `hugin`: `Hugin.plot ~title ~xlabel ~ylabel x y |> Hugin.savefig path`
  — PNG only. `talon` (dataframes) and `saga` (text features) join when
  a dataset outgrows hand-rolled assembly; do not force alpha APIs where
  they add nothing.

## Law patterns for any new ML component

1. **Fixture-detector arm FIRST**: the component must demonstrably detect
   on a seeded fixture before it may suggest on real data (ml_rank's
   fx_dark-must-rank-first).
2. **Score-bound + bounded output** (FM-ML-SUGGEST-FLOOD).
3. **Byte-determinism** of the full rendered output from one seed —
   compare PRE-CONVERGENCE too: converged parameters are BLIND to
   seed-discipline faults (MUT-HIA-23's survival lesson).
4. **Data-truth for anything rendered**: plotted/reported aggregates
   recomputed independently in SQL (plotted max ≡ `SELECT MAX(...)`) —
   a fabricated series cannot hide behind a chart (MUT-HIA-31).
5. **No-write bracket**: read-only DB opens; count-unchanged laws.
6. ≥2 mutants per slice: ranking inversion, normalization drop, seed
   drift, fabricated series, skipped artifact — kill by law line + exit
   code, never by compiler error.

## Forward map (triggers recorded — do not build ahead of them)

S6 TIA cost sandwich (gate-latency complaint) · saga ranking features
(current ranking challenged) · neural embeddings (measured TF-IDF recall
failure; #47 instruments it) · survival prediction (≥20 survival labels).
Permanent rejects: learned routing/scheduling authority, any verdict or
gate contact, safety classification.
