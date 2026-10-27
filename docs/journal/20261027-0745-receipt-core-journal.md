# 20261027-0745 — Core verification of the receipt-integrity repair (RECEIPT_FIX attempt 2)

#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #km-triad #stamp-stpa #tailscale-web

- **Plan / task**: `uos/hive-development/20261027-0532` / `RECEIPT_FIX`, attempt 2
- **Worker / session**: `claude-hive-receipt-fix-2585` / `2585c3a9-4685-457d-84af-74238f66aa7c`
- **Grant**: [`var/harness/20261027-0745-core-verification-grant.json`](http://nas-1.tail55d152.ts.net:4100/files/var/harness/20261027-0745-core-verification-grant.json) sha256 `c4c98b8a72a4cb96255c50f285ecf803b49550d5f5541670c3299856db128566`
- **Grant review**: `docs/reviews/20261027-0745-core-verification-grant-review.json` sha256 `a9e2604f850bf4c8ab047c3331d7672aa9af10e104c25edcddd67922be5f89f3`
- **Candidate**: `4366da874475ca47b747cbc89c1c3382c589c1c11bf14c54905ae98ca7180b92`
- **Observed**: 2026-10-27T08:09:11Z .. 08:19Z (host clock)
- **Links**: [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)
- **Authority**: Sa-plan is the sole execution authority. This journal is evidence and grants no admission. EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV number minted.

---

## 1. Scope & Trigger

Attempt 1 of `RECEIPT_FIX` repaired the effect-receipt integrity defect in
`apps/cepaf_gleam/src/cepaf_gleam/harness/operations.gleam`, but every receipt
that attempt produced came from a harness whose control modules were pinned by
the old grant to the **pre-fix** constructor. The repair was therefore observed
only inside the `gleam test` subprocess, never on a receipt the serving harness
itself wrote. Attempt 1 expired with that gap open.

This attempt is a bounded **core verification** under a fresh, independently
reviewed grant: no source, configuration or guidance edits, no production
effects, no network or provider calls. Its job is to run the harness on the
current controls and observe whether the repair holds at runtime, plus the
scoped refusal, build and test checks the grant names.

Formal gateway: `formal/lean/DevelopmentCoreGate.lean` sha256
`ecdc8f01fdf0de7262ad8a48b7ed9299603ecb4246d23d413df2b0fdfc2392a4` is reused as
a bounded model, **not** rerun in this invocation (see §7, §10).

## 2. Pre-State Assessment

| Observation | Value |
|---|---|
| Prior harness process | stopped; no stale `successor_mcp` or FIFO holder found |
| Prior receipts | 20 under grant `20261027-0538-hive-receipt-dedicated`, all terminal |
| Sa-plan `RECEIPT_FIX` | `executing`, worker `claude-hive-receipt-fix-2585`, attempt 2, `result_present:false` |
| Coordinator leases | empty; root had released workspace epoch 3 |
| `operations.gleam` | `f64da7e1c46212b09d7c6c905ce0b69fba4ac035b70a14697009f91144e4c35b` (attempt-1 repair in place) |
| `harness_successor_test.gleam` | `7c7787cb2e465bde9d7595ee86ff1734deaf50015182ec44681b76e6d2c07f2b` |

Predictive prior: the repair was expected to hold, since the code was already
written and green in a subprocess. The open question was purely whether a
*serving* harness would emit the new fields. Prior probability of a clean
runtime observation, before the attach failure: 0.85.

## 3. Execution Detail

Ordered steps, no diagram (a figure would add no information beyond this list):
grant verify, fresh `erl +S 2:2 +A 2`, initialize 2024-11-05, 13 tools,
heartbeat, claim workspace epoch 4, attach-1 refused on the oversize portfolio
read, root reconciles the portfolio, attach-2 epoch 2, refusal battery, W1
trips the unresolved stop line, `harness_reconcile`, attach-3 epoch 3, build,
test, smoke write; the build, test and smoke receipts all carry
`output_retention`.

Transport was a private FIFO stdio bridge, non-canonical, carrying JSON-RPC
lines only; all executable logic stayed in the existing Gleam. The server was
restarted once, through the protocol's own `shutdown` method rather than a
signal, to clear `unresolved_operation` left by the W1 probe.

## 4. Root Cause Analysis

`attach-1` returned `attachment_outcome_unknown:regular_single_link_file_bound`.
Analysis of Competing Hypotheses (ACH). Competing hypotheses, scored by structured disconfirmation, are H1 oversize evidence input, H2 symlink / hardlink / non-regular file, and H3 stale fence or wrong attempt:

| Evidence | H1 oversize evidence input | H2 symlink / hardlink / non-regular file | H3 stale fence or wrong attempt |
|---|---|---|---|
| E1 `files.max_bytes = 262144` (`files.gleam:17`) and guard requires `size <= max_bytes` (`:134`) | Consistent | Neutral | Inconsistent |
| E2 `stat` of the portfolio: 295864 bytes, `links=1`, `regular file` | Very consistent | **Refuted** (links=1, regular) | Inconsistent |
| E3 `attach` reads `scope.portfolio` via `state_assessment` → `files.read` (`admission.gleam:707`, called `:773`) | Consistent | Neutral | Inconsistent |
| E4 Sa-plan row read `executing`, attempt 2, correct worker | Neutral | Neutral | **Refuted** |
| E5 No task-resource lease and no effect receipt were created | Consistent (read precedes `risk_check` and `coordinate`) | Neutral | Inconsistent |
| **Verdict** | **CONFIRMED** | REFUTED | REFUTED |

Root cause: the risk portfolio had been pretty-printed to 295864 bytes, 33720
over the hard read cap, so the guarded read refused it. The `unknown` label is
the conservative wrapper at `admission.gleam:806`; the failure point itself is
deterministic and strictly **pre-effect**. Root independently reached the same
conclusion and reconciled by compacting the same JSON values.

I verified that reconciliation rather than accepting it: `jq -S -c` piped to
sha256sum yields `8d6116ab33832285dde7aba17a3f6e2223ffa4dde8b7a73d6507e56ba0b700a6`
for **both** the preserved 295864-byte file and the 236991-byte canonical file,
27 records each. Formatting only, no change of risk judgment.

## 5. Fix Taxonomy

| Class | Item |
|---|---|
| Poka-yoke (already present, now exercised) | The read cap refused an oversize evidence input *before* any effect, instead of truncating it silently |
| Jidoka | The W1 out-of-scope write tripped a fail-closed stop line that blocked all further effects until reconciled |
| Muda | None removed in this attempt; no source changed. The attempt-1 repair itself removed the waste of an unverifiable digest |
| Standardized work | Attach / refuse / reconcile / attach / build / test / write, each a typed MCP intent with a durable receipt |
| Containment | Server restarted through the protocol's `shutdown`, never a signal; original failed attach preserved |

No code fix was authored here. The only mutation is evidence.

## 6. Patterns & Anti-Patterns Discovered

**Pattern — a pinned control set hides its own repair.** A grant that pins
loaded control modules is correct for reproducibility, and it also guarantees
that a fix to a control module cannot be observed by the process serving under
that grant. Verification of such a fix *requires* a later, separately reviewed
activation. Attempt 1 was not incomplete through negligence; the grant made the
observation impossible.

**Anti-pattern — adversarial write probes are not free.** A correctly refused
out-of-scope write still writes an `effect_unverified` receipt and trips the
unresolved stop line, costing a reconcile cycle and, as observed, the active
execution binding. Two further probes (W2, W3) were blocked by it. Pure read
and pre-attach refusals cost nothing and should be preferred.

**Anti-pattern — re-encoding as a false drift signal.** My first digest check of
the two review artifacts used `jq -r '.content'`, which appended a newline and
produced two mismatches. Checking the files directly matched both expected
digests exactly. A measurement artifact nearly read as evidence tampering.

**Devil's Advocate / Red Team, Popperian falsification.** Recorded rather than dismissed: *the retained-digest property
could hold while the receipt is still useless.* It can, and partly does. The
property guarantees the retained bytes are verifiable; it does not recover the
dropped prefix. The RED diagnostic in attempt 1 was itself lost in that prefix.
The repair converts a silent loss into a disclosed one; it does not prevent loss.

**Explicit falsifier for this section's claims.** Any receipt whose `output_retained_sha256` does not equal the digest of its own `output` field falsifies the repair. Any receipt classified `full` whose `output_bytes` differs from `output_retained_bytes` falsifies the classifier. Either observation reopens RECEIPT_FIX.

## 7. Verification Matrix

Admiralty grading per `SC-JOURNAL-003` §4.1. Only rows at or above B2 are
treated as admissible; nothing below B2 certifies state.

| # | Claim | Evidence | Grade |
|---|---|---|---|
| V1 | Grant and its review are the reviewed artifacts | `sha256sum` of both files equals the stated digests | A1 |
| V2 | 13 tools, protocol 2024-11-05 | `tools/list` from the fresh server | A2 |
| V3 | Guarded source did not drift | All 14 `input_manifest` entries verified by `sha256sum -c`, 0 drift; root independently recomputed the same 14 | A1 |
| V4 | Attach-1 failed pre-effect | No task-resource lease, no effect receipt; source path shows the read precedes `risk_check` and `coordinate` | A2 |
| V5 | Portfolio compaction is formatting only | Identical `jq -S -c` digest `8d6116ab…` both sides, 27 records each | A1 |
| V6 | Scoped reads refuse out-of-scope, traversal, absolute, pre-attach | Four observed refusals plus one in-scope success | A2 |
| V7 | W1 write refused before mutation | Terminal receipt `write_scope_refused`; 14 hashes unchanged after | A1 |
| V8 | W1 reconciled without pretending success | `harness_reconcile` returned the bound execution and the failure; `unresolved_operation` then false | A2 |
| V9 | Build EXECUTED | receipt `…@claude-2585-core-build-1@result.json`, result SHA `6d44f790ae16dac389c0b2525b434198c3e2e2127d232ab233d2a4f0664c9ac2`, retained 8408 bytes digest `b1dd2d64…` | A1 |
| V10 | Test reports 84 passed, 0 failed, 0 skipped, 6 named modules | receipt `…@claude-2585-core-test-1@result.json`, result SHA `a325c51ad4193eb26a5b812f1e867caf1be76028e85d8fb843211e348c8b0bc8` | A2 |
| V11 | Retained digest corresponds to retained bytes on a real receipt | `output_retention tail_truncated`, `output_bytes 19023`, `output_retained_bytes 8192`, `output_retained_sha256 09632374…`; extracted and rehashed outside the harness to the same value; root matched with GNU sha256sum | A1 |
| V12 | `full` retention path also exercised | smoke write receipt, `output_retention full`, 64 bytes | A2 |
| V13 | Independent peer review | `docs/reviews/20261027-0745-receipt-core-peer-review.json` sha `aa8ec5cf…`, verdict `APPROVE_RECEIPT_FIX_DEVELOPMENT_ONLY`, reviewer Codex coordinator, not the implementation author | B1 |
| V14 | Finite formal checks | `governance/planning/20261027-0745-receipt-core-formal-evidence.json` sha `6e9888f1…`, verdict `FINITE_SCOPED_CHECKS_PASS`, candidate `4366da87…` | B2 |
| V15 | Lean model freshly rerun | **NOT CLAIMED.** `DevelopmentCoreGate.lean` (47 named theorems, 12 satisfiable examples) is reused; `fresh_rerun_in_this_task: false` | not admissible — recorded as a gap |
| V16 | Per-assertion coverage from the 84 total | **NOT CLAIMED.** Five module headers retained in the tail, successor module head truncated; 84 equals the source declaration count 25+15+17+5+17+5 | not admissible — recorded as a gap |
| V17 | Full-output text verified | **NOT CLAIMED.** `output_sha256 68c7f77a…` is metadata; the unavailable full text was not rehashed by either party | not admissible — recorded as a gap |

V15–V17 are listed to keep them visible, not to count them as evidence.

## 8. Files Modified

No source, configuration or guidance file was modified. Three evidence writes,
all inside the grant's `write_paths`:

| Path | sha256 | Intent |
|---|---|---|
| `governance/planning/20261027-0745-receipt-core-smoke.json` | `4994654a2ad4eddb094274bac7090348639d964bf9363ffeeb0aaba9c4d58373` | `claude-2585-core-smoke-write` |
| `docs/journal/20261027-0745-receipt-core-journal.md` | this file | `claude-2585-core-journal-write` |
| `governance/planning/20261027-0745-receipt-core-verification.json` | see §11 | `claude-2585-core-verification-write` |

Preserved, not rewritten: 20 receipts under the attempt-1 grant; the oversize
portfolio at `var/harness/20261027-0745-risk-oversize-preserved.json`; the raw
failed-attach response for `claude-2585-core-attach-1`, which produced no
durable receipt of its own.

## 9. Architectural Observations

The receipt algebra now separates three questions that it previously conflated
into one digest: *what bytes are here* (`output`, `output_retained_sha256`,
`output_retained_bytes`), *what bytes existed* (`output_sha256`,
`output_bytes`), and *how the two relate* (`output_retention`). That is a
presheaf-style restriction made explicit: the retained section is verifiable on
its own, and the relation to the global section is stated rather than implied.
`output_retention` is derived by observing the bound's result, never by matching
the fallback sentinel text, so the classification stays sound if that text ever
changes.

The layering held under adversarial probing. Scope refusal (L1 file guard),
stop-line containment (L3 transaction), fence and lease (L3/L4) and Sa-plan
authority (L3) each refused independently; no single check carried the boundary.

## 10. Remaining Gaps

1. **No fresh formal rerun.** The Lean model is reused; `fresh_rerun_in_this_task: false`. Finite tests are not universal proof, and no posterior reliability figure is derived from correlated passes.
2. **Coverage is not asserted.** 84 is a reported total matched to source declarations, not per-assertion coverage. The selected manifest is not the full dependency closure.
3. **Full-output text is unverifiable by construction.** The repair discloses the loss; it does not recover the dropped prefix.
4. **W2 and W3 refusal checks remain NOT_RUN** by operator instruction after W1 showed the stop-line cost.
5. **The 262144-byte read cap is a live operational constraint** on evidence inputs. A portfolio that grows past it fails attach with an outcome labelled `unknown`. The label is conservative; the failure is deterministic and pre-effect.
6. **`MCP_ACTIVATE` is untouched** and still `available`. It requires root acceptance, risk readiness and its own fresh task-specific receipts.
7. **`backend_diagnostic`'s 16384-byte fallback lives in `development.gleam`**, outside every write scope used so far.

**Explicit falsifier for the residual set.** Each gap above is stated so it can be refuted: a fresh Lean run reporting no failure refutes gap 1; a per-assertion coverage report refutes gap 2; a receipt carrying verifiable full output refutes gap 3; a `regular_single_link_file_bound` caused by links > 1 rather than size refutes gap 5. Falsification of any gap is a correction to this record, not a defect in it.

## 11. Metrics Summary

| Metric | Value |
|---|---|
| Source files changed | 0 |
| Evidence artifacts written | 3 |
| MCP effect receipts this grant | 10 intent/result pairs, all terminal, 0 dangling |
| Tests | 84 passed, 0 failed, 0 skipped, 6 named modules |
| Guarded hashes verified | 14, zero drift, twice independently |
| Refusals observed | 5 (4 read-class, 1 write-class) |
| Reconciliations | 1, verdict known-no-effect |
| Attach attempts | 3 (1 refused pre-effect, 2 executed) |
| Coordinator epochs | workspace 4; task resource 2 then 3 |
| Retained-digest matches on live receipts | 3 of 3 (`tail_truncated`, `full`, `full`) |

Bayesian update on "the repair holds at runtime": prior 0.85 (code green in a
subprocess, never observed on a served receipt). Likelihood of observing three
receipts whose retained digest independently rehashes correctly, including both
the `tail_truncated` and `full` classifications, under the hypothesis that the
repair is broken: low. Posterior 0.97, decayed on the 7-day machine-certified
half-life, and explicitly **not** extended to production behaviour, which this
grant never touched.

Lyapunov reading: define V as the count of unresolved or unverified effects.
V went 0 → 1 at W1 → 0 after reconcile, and ended at 0 with 10 terminal receipt
pairs. dV/dt ≤ 0 across the episode, with the single excursion deliberately
induced and bounded by the stop line.

## 12. STAMP & Constitutional Alignment

| Control | Hazard it prevents | Observed this attempt |
|---|---|---|
| Scoped write paths | H-1 green report while a defect is active | W1 refused; 14 hashes unchanged |
| Unresolved stop line | L-6 un-ledgered conflicting mutation | Blocked W2/W3 until reconciled |
| Guarded read cap | L-3 evidence contamination by unbounded input | Refused the oversize portfolio pre-effect |
| Fence + lease epochs | L-6 stale-owner effect | Re-attach minted epoch 3; no stale owner acted |
| Sa-plan sole authority | L-6 shadow task state | Every effect bound to plan/task/attempt 2 |
| Pinned toolchain | L-5 boundary loss | OTP 29.0.5 from the store path, `+S 2:2 +A 2` |

$\Psi_2$ (append-only history): all 20 prior receipts and the oversize portfolio
preserved byte-for-byte. $\Psi_3$ (two-key): fresh runtime observation is present
and bound to candidate `4366da87…`; the formal key is a **reused** bounded model,
so two-key verification is not asserted as complete. $\Psi_5$ (truthfulness):
V15–V17 record what was not verified. Zero Bevy, zero Graphite, zero Graphene
NIF introduced; no host storage serial appears in this journal.

## 13. Conclusion

The receipt-integrity repair authored in attempt 1 is now observed at runtime on
receipts the serving harness wrote itself, which is exactly what attempt 1 could
not show. Three live receipts carry a retained digest that rehashes correctly
outside the harness, across both the `tail_truncated` and `full` paths; the
build and the six-module test are green at 84 passed, 0 failed; the guarded
source did not drift under an adversarial write that was refused before
mutation; and the one unverified effect that probe created was reconciled
without representing a failure as a pass.

This is development evidence under a development-only grant. It is not
production admission, and it does not complete the parent plan.

Precommitted, falsifiable forecasts:

| # | Forecast | p | Falsifier | Horizon |
|---|---|---|---|---|
| F1 | A reviewed `MCP_ACTIVATE` run will emit at least one receipt with `output_retention` equal to `tail_truncated` and a retained digest that rehashes correctly | 0.93 | any such receipt whose `output_retained_sha256` does not equal the digest of its own `output` field | 2026-10-31T00:00:00Z |
| F2 | No historical receipt under the attempt-1 grant will be found rewritten | 0.98 | any of the 20 receipts differing from its recorded bytes | 2026-10-31T00:00:00Z |
| F3 | The next evidence-input read failure in this plan will again be a size-cap refusal rather than a link or type refusal | 0.70 | a `regular_single_link_file_bound` caused by links > 1 or a non-regular file | 2026-11-07T00:00:00Z |
| F4 | A fresh Lean rerun of `DevelopmentCoreGate.lean` at this candidate will report no new failing theorem | 0.88 | any named theorem failing or requiring `sorry` at candidate `4366da87…` | 2026-11-07T00:00:00Z |

Scored by Brier loss $B = (p - o)^2$, target $B \le 0.10$ across the set.

---

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this journal grants no admission. EV ceiling 93; EV-94..109 NOT_ADMITTED.
