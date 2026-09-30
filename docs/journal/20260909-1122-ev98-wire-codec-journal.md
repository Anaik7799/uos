# EV98 bounded lossless mesh wire codec

Observed: 2026-09-09T11:59:22Z. Source candidate: `5e1edaa7bb1b3b39a501e771720bc2ef63174a87`; base: `fac5d6791bdf3a816294a314275960baad3ee09d`.

Tags: #fractal-l0 #fractal-l6 #fractal-l7 #zk-adr #zero-muda

Navigation: [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [Verification record](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1102-ev98-codec-verification.json).

## 1. Scope & Trigger

Parent PROGRAM authorized task CODEC in Sa-plan `uos/ev98-wire-codec/20260909`, worker `codex-ev98-wire-codec`. The existing SyncDelta diagnostic serializer omitted the entire delta-state and health-map payload and had no receive codec. This task implements bounded lossless component serialization and validated reconciliation. Authentication, transport deployment, formal proof and admission are outside the task.

## 2. Pre-State Assessment

Mesh state contains origin/epoch, vector clock, worker OR-set live dots and tombstones, PN-counter components and a leader LWW register. Health entries additionally distinguish physical sample time, logical register version and writer. None may be reconstructed from the previous three-field delta diagnostic object. Existing source constructors permit mutable record values, so the wire boundary must validate before acceptance.

## 3. Execution Detail

Native preflight passed at 11:36:55Z. Canonical claim returned attempt 1. The first active observation correctly held because the assessment still declared available; refreshed executing state passed at 11:37:21Z before code work. Latest source-bound active observation passed at 11:57:30Z with assessment `6478d784012d8d6409892bf971abd9ac43090c2fa0f7a84fb749fb705d9c3a33`, manifest `docs/reviews/20260909-1123-ev98-codec-risk-1788955043.json`.

The original serializer compiled and failed an actual assertion requiring a nonempty worker payload to survive. The implementation adds typed encode/decode APIs directly to mesh_sync and a reconcile_remote_wire function that calls the existing merge only after decoding succeeds. Existing object diagnostics retain their fields and gain the complete delta/health payload as positional arrays; they are explicitly documented as diagnostic rather than validated transport. The existing campaign acceptance test bytes remain unchanged.

Root review found that per-list limits still allowed a compact shared generic Value to create large output. An actual shared-tree regression returned IntegerLimit for a trailing invalid value instead of stopping earlier with ByteLimit. Aggregate encoded-byte accounting is now fused into validation, consuming array brackets/commas and locally encoded primitive lengths. It bounds validation traversal itself before recursive JSON construction, including a 256-way tree at depth 12.

Thirteen exact source files were extracted through full commit_id selection into `/tmp/ev98-codec-final-5e1edaa7`. The native Gleam compiler used only three copied realized dependencies (128 files). The final direct ERTS invocation used only those staged dependency ebin paths and the private compiled output, with no_dot_erlang startup. Source, dependency, compiled artifact and output hashes were checked after execution.

## 4. Root Cause Analysis

The original JSON function was a lossy diagnostic representation with a transport-like name. A local typed merge could pass while transmission silently removed its operands. The first codec repair also confused local collection bounds with aggregate work bounds; structural sharing can make the expanded tree enormous. A complete positional grammar fixes representation loss, and an exact shared byte allowance makes traversal and rendering bounded.

## 5. Fix Taxonomy

Version 1 uses closed arrays with exact arity and tags. Objects/null, extra fields, invalid types, duplicate association keys and repeated dots are refused. Health-map keys must match telemetry nodes. A forwarding sender may differ from the merged state's origin. Strings retain content/order and use UTF-8 byte limits; all epochs/counters/register versions are nonnegative safe JSON integers; health floats must be finite.

| Boundary | Limit |
|---|---|
| Input and canonical encoded bytes | 131072 |
| Array nesting | 12 |
| Entries in each collection | 256 |
| UTF-8 bytes per string | 1024 |
| Epoch/counter/version/count integer | 0 through 9007199254740991 |

## 6. Patterns & Anti-Patterns Discovered

An independent literal wire fixture complements roundtrip tests so encoder and decoder cannot silently share a layout error. Physical and logical clocks use different values in fixtures; a compiled mutation replacing physical sample time with logical version fails the designated all-field roundtrip assertion. Aggregate budget exhaustion precedes traversal of later malformed tails. Initial compiler-argument/API errors and a generated-runner formatting failure remain preserved; they were corrected before the final clean compile and format check.

## 7. Verification Matrix

| Observation | Actual result | Scope |
|---|---|---|
| Original lossy diagnostic | Compiled, designated assertion failed | Preserved red |
| Aggregate shared-tree regression | Compiled, ByteLimit assertion failed before repair | Preserved red |
| Immutable final suite | 72 PASS: 25 new and 47 existing | Exact START/PASS denominator |
| Sample-time substitution mutant | Compiled cleanly, designated assertion failed | Source/output bytes bound |
| Formatting and compilation | PASS, no final warnings | Four scoped code files |
| Independent review | APPROVED; reviewer ran 72 calls plus 10 private groups | Receipt read, those 10 not rerun by author |
| Codec formal evidence/live mesh | Not established | No admission credit |

<details><summary>18-checkpoint verification structure</summary>

| Domain | Checkpoint | Status |
|---|---|---|
| Metadata | Timestamp and current clock | PASS |
| Metadata | Tailscale navigation | PASS |
| Metadata | Immutable source/evidence references | PASS |
| Purity/storage | Gleam implementation and OCaml automation | PASS |
| Purity/storage | No downloads or new dependency | PASS |
| Purity/storage | Private fixtures; no live storage effects | PASS |
| Testing | Observed pre-fix behavioral failures | PASS |
| Testing | Exact positive denominator | PASS |
| Testing | Compiled designated negative control | PASS |
| Testing | Codec formal proof | NOT ESTABLISHED |
| Observability | Typed bounds and refusal | PASS |
| Observability | Source/tool/dependency/output hashes | PASS |
| Observability | Live multi-host transport | NOT ESTABLISHED |
| Governance | Canonical current task attempt | PASS |
| Governance | Owned JJ sibling and frozen source | PASS |
| Governance | Independent bounded review | APPROVED |
| Provenance | EV93 admitted ceiling retained | PASS |
| Provenance | New admission | NOT GRANTED |

</details>

## 8. Files Modified

`apps/cepaf_gleam/src/cepaf_gleam/crdt/mesh_sync.gleam` integrates complete diagnostics, typed wire APIs and validated reconciliation. New `mesh_wire.gleam` implements closed primitives, preparse byte/depth scanning and aggregate validation. New `mesh_sync_codec_test.gleam` and `ev98_codec_runner.gleam` provide the explicit codec controls and scoped regression runner. Timestamped risk manifests, source-bound receipts, mutant sources and this journal record the work.

## 9. Architectural Observations

The top-level grammar is `[1, tag, sender, payload1, payload2, epoch]`. Digest payloads are clock and count; acknowledgement payloads are clock and status; delta payloads are state and health. State is `[origin, epoch, clock, [elements, tombstones], [positive, negative], [leader, version, writer]]`. Health entries are `[key, [[node, score, exponent, stable, breaker, sample], version, writer]]`. Clocks are `[node, count]` entries, dots are `[node, counter]`, and worker entries are `[worker, dot]`. List order is retained exactly, including repeated worker names with distinct dots.

## 10. Remaining Gaps

This is a local wire representation and pure reconciliation boundary. No live transport, authentication, sender authorization, replay-sensitive effect fence, codec formal proof or sovereign admission is established. Diagnostic rendering is explicitly outside the validated wire API. The separately reviewed EV98 producer must add mesh_wire to its closed source staging recipe before observing this candidate; its five-source recipe otherwise correctly fails compilation. This task did not change that producer. Native dynamic-library release closure and hostile same-UID races remain outside the cooperative test environment.

## 11. Metrics Summary

Twenty-five codec cases and 47 existing regressions passed, with 72 unique exact observed calls. Thirteen source files and 128 dependency files were rebound after execution. Two actual pre-fix assertion failures and one compiled field-loss mutation are preserved. The independent reviewer supplied ten additional private adverse/roundtrip groups. The public APIs return typed refusal and provide no admission authority.

## 12. STAMP & Constitutional Alignment

Omitted state fields, malformed accepted payloads, invalid temporal values and overlong parsing/rendering map to the four unsafe-control forms. Lossless fixtures, closed validation, nonnegative safe clock bounds and aggregate budgets constrain those cases. Raw task FMEA is 5/3/4 (RPN 60), priority 2500; it does not grant effects. Canonical Sa-plan and the parent's workspace lease remain separate authorities. No agent impersonation, live state mutation or EV ceiling change occurred.

## 13. Conclusion

Candidate `5e1edaa7...` has clean native component observations and independent bounded approval. CODEC remains executing at attempt 1 for parent-owned completion and composition. The codec is not a full EV98 runtime or admission result.

Previous: [Provenance contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260908-0912-provenance-integrity-contract.md) · Next: [Verification record](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1102-ev98-codec-verification.json).

UOS evidence footer: bounded component result · authority NONE · EV93 admitted ceiling.
