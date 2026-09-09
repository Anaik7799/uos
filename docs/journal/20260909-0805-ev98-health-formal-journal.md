# EV98 health-order formal slice — 20260909-0805

## 1. Scope & Trigger

This isolated FORMAL task creates a bounded OCaml/Smtml ordering model and candidate-bound Gleam projections for EV98 health merge ordering. It does not modify health merge production behavior.

## 2. Pre-State Assessment

`health_bridge.merge_health_registers` orders sample observation first, then `delta_state.merge_lww` logical timestamp and writer. Raw lists are not structurally commutative and equal ordering keys with different payloads are order-dependent.

## 3. Execution Detail

`tools/ev_health_formal` contains an independent finite OCaml selector, exhaustive bounded enumeration, and a dedicated Smtml/Z3 child executable. The Gleam runner emits line-delimited JSON projections for sample, logical, writer, and payload selections.

## 4. Root Cause Analysis

The existing source comments asserted convergence without a candidate-bound machine relation that separated extensional map meaning from association-list order or declared collision preconditions.

## 5. Fix Taxonomy

This is bounded evidence tooling: independent reference model, finite symbolic laws, SAT witnesses, two mutation controls, and actual compiled Gleam projections.

## 6. Patterns & Anti-Patterns Discovered

Ordering keys must identify payloads. A raw association list is not an extensional map. Smtml integer ITE must use the realized Boolean-constructor API pattern; using the nominal integer encoding failed with an unsupported-ternary error and was repaired.

## 7. Verification Matrix

`test_ev98_health_formal.exe` passes independent controls and full finite enumeration. `ev98_health_smt_child.exe` passes named bounded UNSAT laws, SAT witness, and two SAT mutant catches. Gleam compile output `/tmp/ev98-health-projection-final-20260909-0803` ran `ev98_health_projection_runner` and emitted four valid projections. Active risk passed at `2026-09-09T06:04:15Z`, assessment `ccfc4813a6bb4f99a51cb5779d9a39e9a17bafcf966990ee9d7c1e883f6be18d`.

## 8. Files Modified

- `tools/ev_health_formal/{dune,dune-project,ev98_health_model.ml,ev98_health_smt.ml,ev98_health_smt_child.ml,test_ev98_health_formal.ml}`
- `apps/cepaf_gleam/test/ev98_health_projection_runner.gleam`
- `docs/reviews/20260909-0754-ev98-health-formal-risk.json`
- `docs/reviews/20260909-0805-ev98-health-formal-source-summary.json`

## 9. Architectural Observations

The model proves a finite rank algebra and checks four actual Gleam projections. It does not authenticate telemetry, enforce map well-formedness at transport boundaries, or observe a multi-host health merge.

## 10. Remaining Gaps

Independent review is pending. Full projection enumeration, receipt-carrier integration, runtime fencing, distributed execution, sovereign EV98 admission, and full proof over unbounded integers remain outside this slice.

## 11. Metrics Summary

Finite register domain: sample/logical/writer ranks 0..2 with two payload tags. Symbolic laws: six UNSAT, one SAT witness, two SAT mutant catches. Candidate source and runner bytes are summarized separately.

## 12. STAMP & Constitutional Alignment

The active Sa-plan task is `uos/ev98-health-formal/20260909`/`FORMAL`, attempt 1. Native risk validation reports authority `NONE` and runtime admission `NOT_GRANTED`. Containment prerequisite: the accidental `sa-plan task claim --help` claim was released by root; receipts `/tmp/ev-accidental-help-claim-{before,release,after}.json` preserve the incident.

## 13. Conclusion

Candidate-bound bounded formal evidence is ready for independent review. FORMAL remains executing and this journal grants no runtime authority, completion, integration, or admission.

## Verification checklist — 18 checkpoints

1. Timestamped journal: pass. 2. Candidate/base identity: pass. 3. Task identity: pass. 4. Active risk: pass.
5. Pure OCaml/Gleam scope: pass. 6. No Bevy: pass. 7. No Graphite: pass. 8. No download: pass.
9. Red model scaffold: pass. 10. Finite enumeration: pass. 11. Smtml UNSAT laws: pass. 12. SAT controls: pass.
13. Dedicated solver child: pass. 14. Gleam projection compile: pass. 15. Projection runtime: pass. 16. Hashes: pass.
17. JJ candidate: pass. 18. Independent review/admission: pending.
