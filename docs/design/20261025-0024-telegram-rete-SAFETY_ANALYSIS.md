# 20261025-0024 Telegram bounded OCaml rule evaluation

Observed 2026-10-25T00:23:52.322Z. #fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

## Contract

/rete accepts comma-separated boolean facts; /tool evaluate_rete accepts exactly a facts string. Closed keys watchdog,mesh_running,e_stop,high_drift,divergent;1..256ASCII bytes, at most5unique pairs. No default nominal facts. The existing canonical C3i_ocaml_bridge.ocaml_rete_eval function is compiled unchanged into an isolated native executable with AGY-authored1927byte facade. Only that evaluator is invoked; other legacy bridge callbacks are not dispatched. The implementation is explicitly a naive fixed production-rule matcher, not an alpha/beta RETE-UL network. No new network-algorithm capability is claimed.

Gleam owns validation, typed dispatch,1000ms/4096byte guardian policy and before/after current_read fences. Executable and guardian SHA256 must match. A pass means only supplied assertions satisfy the fixed rule set; runtime_facts_verified=false, authority=advisory_only, runtime_admission=NOT_GRANTED. Missing watchdog/mesh_running rejects except higher-priority hazardous facts also reject directly. Worker and report outputs are whitelisted and bounded; no path/tool/rule overrides or input echo.

## STPA and FMEA

| UCA | Failure | Raw S/O/D; RPN | Mitigation |
|---|---|---|---|
| Not provided | Valid facts never evaluated |3/3/3;27|Real native worker and service dispatch|
| Incorrectly provided | Supplied facts become runtime permission or malformed output becomes pass |5/3/4;60|Explicit advisory scope, strict schema/envelope,32combination oracle|
| Wrong timing/order | Stale task or wrong native artifact used |4/3/4;48|Current service fences and exact executable hash|
| Too long/repeated | Evaluation stalls scheduler or unbounded input exhausts resources |4/3/3;36|Isolated1second guardian, bounded arguments/output and process reaping|

Engineering estimates1..5; criticality high for false authority. Facts remain unverified caller assertions. Legacy rule names include SIL/OODA tokens; those names do not certify safety levels, reinstate retired loops, or grant admission. No physical interlock is controlled.

## Binding regression and acceptance

A new pinned module pushed the test child launch expression to4101bytes, beyond4096. Highest compression alone was insufficient. Test-only binding now packs SHA256values into one byte vector, verifies exactly32bytes per module, then verifies every original module hash. No cap or hash check is removed. Negative tests truncate the vector and alter one digest; both refuse before runner startup. Service positive/refusal and prior ecology regression pass.

Verification requires fixed-schema positives/refusals,32boolean truth-table combinations, malformed receipt/control text, authority regression, native argument redaction and independent exact candidate review. Build source/compiled artifact hashes must be retained. Production artifact packaging remains release work; current development executable is retained under var/recovery-runtime/20261025-0017-rete/native. No live Telegram transport, full-system admission or new mathematical proof claimed.

<details><summary>Verification domain 1</summary>

- [ ] CHK-01 Timestamp — scoped evidence above; no blanketPASS
- [ ] CHK-02 Tailnet navigation — scoped evidence above; no blanketPASS
- [ ] CHK-03 Fractal scope — scoped evidence above; no blanketPASS
- [ ] CHK-04 Knowledge links — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 2</summary>

- [ ] CHK-05 Dependency exclusions — scoped evidence above; no blanketPASS
- [ ] CHK-06 Pure graph boundary — scoped evidence above; no blanketPASS
- [ ] CHK-07 Storage safety — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 3</summary>

- [ ] CHK-08 C1-C8 — scoped evidence above; no blanketPASS
- [ ] CHK-09 Math gates — scoped evidence above; no blanketPASS
- [ ] CHK-10 Test modalities — scoped evidence above; no blanketPASS
- [ ] CHK-11 Regression — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 4</summary>

- [ ] CHK-12 GleamOTP — scoped evidence above; no blanketPASS
- [ ] CHK-13 Hermes — scoped evidence above; no blanketPASS
- [ ] CHK-14 ZigVM — scoped evidence above; no blanketPASS
- [ ] CHK-15 MAX — scoped evidence above; no blanketPASS
- [ ] CHK-16 Trace correlation — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 5</summary>

- [ ] CHK-17 Independentreview — scoped evidence above; no blanketPASS
- [ ] CHK-18 Jujutsu — scoped evidence above; no blanketPASS

</details>

Provenance: EV>93 NOT_ADMITTED.


[Previous](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261024-2059-telegram-current-task-bridge.md) · [Next](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

UOS footer: component evidence is not admission.
