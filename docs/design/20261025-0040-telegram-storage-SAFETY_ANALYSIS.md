# 20261025-0040 Telegram storage observation and policy probes

Observed 2026-10-25T00:40:09.758Z. #fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

## Contract

/storage and /nvme are aliases for query_storage; /tool query_storage accepts exactly empty arguments. Gleam owns validation, fixed executable/hash selection, isolated guardian reads and before/after current_read authority fences. Three fixed calls read lsblk flat JSON, root df capacity, and a no-argument native Rust policy probe. Each has a 1000ms guardian deadline and explicit output bound; total projection age <=5000ms. Host devices are never opened by the probe, and there are no allocation, wipe, mount, network or shell operations. Native Rust is an isolated bounded executable, not a NIF.

The AGY-authored probe compiles the unchanged canonical LabSpec source and evaluates seven actual positive/negative configurations. Policy results remain false on failed checks; they are not fixed PASS strings. Typed fixture errors replace indexing/panics. Raw serials and non-root mount paths are omitted from Telegram output. Root/device ancestry is bounded, cyclic/ambiguous/missing-parent topology is refused, capacity is range checked, and missing root/serial observations remain unknown. Snapshot is explicitly non-atomic. Kernel read-only status and configured protection are distinct. Production interlock enforcement is NOT_ESTABLISHED; allocation authority and runtime admission are NOT_GRANTED. A policy probe cannot establish physical safety or release authority.

## STPA and FMEA

|UCA|Failure|Raw S/O/D; RPN|Mitigation|
|---|---|---|---|
|Not provided|No current capacity/device observation|3/3/3;27|Actual bounded lsblk/df plus service tests|
|Incorrectly provided|False protected-device safety or leaked serial|5/3/4;60|Exact source/worker hashes, seven actual probes, redaction, explicit scope|
|Wrong timing/order|Stale task, changed executable, ambiguous root topology|5/3/4;60|Current authority fences, pinned binary, bounded topology and observation duration|
|Too long/repeated|Process or output stalls scheduler|4/3/3;36|Isolated guardian deadlines, cleanup receipts and byte caps|

Engineering estimates 1..5; high criticality for false safety. Residual risk: non-atomic observations, device topology outside supported schema, development artifact location and system binary drift. Drift refuses until reviewed rebuild. No production storage effects authorized.

## Structural launch binding repair

Adding a module exceeded the 4096byte child-launch expression cap again. Packing independent hashes had only postponed growth. The test-only launcher now hashes the ordered list of module names and SHA256 bytecode digests into one aggregate digest. The child recomputes the same digest from all module bytes before loading any bound module. Names/order/bytecode remain bound; paths, raw packet and expression caps remain unchanged. Three negative tests reject truncated digest, altered digest and omitted module before runner startup. This is a test-launch mechanism, not production admission.

## Acceptance and residual work

49 focused EUnit tests pass:44 unit/binding,3 service positive/refusal and RETE regression,2 authority. Four unchanged native policy tests pass. Two isolated policy mutants (disabled serial denial, disabled path denial) produce false checks as expected; production source and executable are unchanged. A fresh read observed24 block rows,6 disks and the protected root serial match without outputting serial values. Service tests use the real isolated backend with test transport; live Telegram remains pending. Independent candidate review is required before the reviewed coverage counter increases. Production native packaging, complete command/API/media/gateway coverage and system admission remain separate release tasks. No new formal theorem or global safety claim.

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
