# FPP/SysML harness recovery — working journal

**Status:** IN PROGRESS / DEVELOPMENT BOOTSTRAP / NOT ADMITTED  
**Observed:** 2026-11-01T09:30:50Z; filename prefix uses UTC hour and seconds.  
**Latest evidence:** 2026-11-01T11:48:28Z; individual observations are timestamped below.  
**Tags:** #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l7 #zk-adr #zero-muda #km-triad  
**Plans:** `uos/fpp-sysml-integration/20261101-0852` and `uos/harness-build-recovery/20261101-0913`.  
**Design:** [Harness recovery and integration specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261101-0927-harness-recovery-and-fpp-sysml-integration.md). This is an intended locator, not proof of publication.

## 1. Scope & Trigger

The requested system integrates FPP and SysML with Gleam, Lean, MCP, Zenoh,
durable storage and agent model access. This journal records the first
development slice and the harness recovery needed before further effects.
The operator also requires task-scoped development grants to cover the complete
set of operations needed to run and control Codex, Claude, AGY and Pi. The
design records MCP for typed controls and Zenoh for addressed events and data;
actual adapter operation, delivery and persistence still need evidence.

## 2. Pre-State Assessment

The connected private route lacked a current task grant. FPP `SaveParams`
returned success without durable storage, and the SysML validator accepted
some unresolved references. The observed state of full integration and
production admission was unknown, not passing.

## 3. Execution Detail

Created isolated JJ workspaces and Sa-plan review/implementation tasks. A
Codex peer rejected the first grant proposal, then approved a narrower exact
proposal. The dedicated successor MCP claimed the task; the unified gateway
attached with coordinator epoch 2 and wrote two regression-test files. A
subsequent build failed on missing `cc`; the durable result remains held.
The separate recovery candidate adds a pinned compiler, preflight probes, a
diagnostic failure classifier, and candidate-only controls for agent, skill,
contract, SOP and agent-policy documents. An independent peer examined the
source/evidence boundary. No runtime cutover or task completion occurred.
Sa-plan continues to show FPP `IMPLEMENT` executing and `REVIEW` complete,
while the failed effect remains unresolved. FPP risk evidence expired at
09:24Z; a grant artifact expiring at 12:57Z does not by itself establish live
authority, a current lease or permission to resume the effect.

The continued recovery work reproduced a receipt-matching defect: a field
missing from both records compared equal. The candidate now requires typed
identity fields and current grant/task binding, emits both original receipt
paths and digests on a failed check, and observes the live fence before effect
reconciliation and immediately before sidecar writes. These observations are
not atomic with writes and do not resolve the original failed effect.
For a dangling intent, the candidate writes global retry blocks before the
quarantine record and retries identical completed prefixes. Torn or conflicting
files remain held; matching existing files are re-synced and rechecked. Exact intent IDs are blocked across grants, but the current
signature includes grant/attempt and cannot deduplicate an equivalent operation
using a new intent ID.

Replaying a bound resolution now re-scans task work before clearing the stop;
pending work or an unknown scan keeps the stop. The planning CURRENT pointer is
checked for the same task and logical ID, and newly submitted planning IDs must
fit the reconciler syntax. Twelve inspected existing IDs fit; older incompatible
records still require a separately designed recovery route. An independent peer
identified namespace shadows, and the candidate now holds when an identifier
appears in multiple assessment, planning, effect or completion namespaces.
The check is not atomic, does not select a resolution for a collision and does
not enumerate other-grant records or global burned-intent markers.

At 11:05Z an independent source review found that MCP effect-time admission
could rebind a call to a different otherwise-valid principal or task. A
regression reproduced the issue. The development candidate now compares the
admitted principal and task/grant identity after current authority validation;
the tests include lease renewal, changed attempts, changed clients/sessions and
dispatch refusal. `ValidatedCall` remains publicly constructible, route grants
are not re-read by this check, and principal metadata is only as trustworthy as
the transport that supplied it.

Built a development-only Lean axiom-audit prototype. A red test showed that
auditing only requested theorems missed an unrelated `sorry` in the same
module; the helper now scans all target-module declarations. Twenty-one direct
bootstrap fixture checks passed, including macro-generated axioms and
demonstrations that an axiom-clean theorem can have the wrong statement and
different source files can have the same module name.
This is not an MCP proof route and does not bind source/import hashes or
sandbox Lean elaboration.

A separate development sandbox probe ran the pinned Lean binary with a hidden
host home and sentinel environment variable, a read-only source mount, and
separate PID/network namespaces. A fixed good theorem passed and a `sorry`
fixture was refused by the audit. A timed transient unit also stopped one
detached test child. These are four observed probes, not proof of general
containment or a task-bound MCP effect. A first 768 MB Lean allocation limit
failed while compiling the audit helper; narrowed Lean imports subsequently
reduced the measured single-run host peak RSS from 1,545,824 KB to 853,580 KB.
The sandbox audit passed using a 1,024 MB Lean limit and a 1,536 MB unit limit;
these measurements are not a general capacity forecast.

An independent adversarial review then found two false-pass paths in the
imported-wrapper audit. A target initializer can call `IO.Process.exit 0`
before the audit, and a target command elaborator can suppress the wrapper's
`run_elab` while a forbidden axiom remains. The separate adversarial test
reproduced both and intentionally exits nonzero. The current wrapper is UNSAFE
for untrusted modules; the fixed-fixture sandbox results above do not change
that assessment.

A separate native data-only prototype now imports fixed compiled fixtures
without target extensions or plugins, checks target origin and statement
against a separately named expected declaration, and audits target declarations
and their resolved dependencies for forbidden axioms. The comparison supports
alpha-renamed universe parameters but may reject definitionally equal types.
After reproducing false passes from a forged builtin and a missing dependency,
the candidate rejects both. Twenty-eight fixed checks passed; three further tests
ran the driver in bounded transient units with read-only mounts, accepted a
clean fixture, did not run an early-exit initializer, and rejected a hostile
axiom fixture. These are development
observations, not a task-bound or admitted proof route.
The bounded cases were selected with `UOS_LEAN_DATA_SANDBOX_PROBE=1 bash
tools/test-harness-lean-data-audit`; retained output is
`var/harness/20261101-1147-data-audit-sandbox.log` (SHA-256
`0fe5996ee0de74cfd69f7c421b516ce7d0eeebeca58528fc2d73d3874999994e`).

A more subtle counterexample remains: changing a dependency's value while
retaining its name passes the metadata check, whereas a separate target-module
kernel replay rejects that fixture. The caller can also select the specification
and artifact paths. The complete source/import closure, toolchain and expected
statement therefore need independent, immutable task-bound provenance, required
kernel replay, qualified containment and trustworthy completion evidence.

On 2026-11-01T09:56Z an MCP health probe reported the KM triad healthy. A
separate Zenoh probe reported reachable transport endpoints with the subscriber
stopped and overall degraded status. The connected `knowledge_search` schema
does not expose a `limit` argument; `zk_transclude` was bounded to five. Recalled
the [20261028 failed-check recovery observation](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261028-2242-failed-check-recovery-observation.json)
and the [historical SysML validator journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1841-ocaml-worker-pool-sysml-validator-and-ui-manifest-journal.md).
The latter's broad completion claims are historical and conflict with current
inspection of reference validation and PRM durability; neither is current
admission evidence.

## 4. Root Cause Analysis

Analysis of Competing Hypotheses (ACH): evidence is assessed for what would
disconfirm each explanation; the grades are observations, not probabilities.

| Hypothesis | Supporting observation | Counterevidence / residual |
|---|---|---|
| H1: restricted build PATH lacks a compiler | Failed receipt contains `cc: not found`; the existing profile has no `cc`. | A compiler alone does not satisfy the 60 s cold-build bound. |
| H2: SQLite source is inherently unbuildable | None observed. | A separate pinned-compiler candidate built the application; this does not prove every deployment. |
| H3: failure settlement is unavailable | Attach stops at the pending-effect guard; existing resolution accepts only a narrow write conflict. | A future reviewed recovery mechanism may settle a failure without calling it success or no-effect. |
| H4: reachable Zenoh sockets imply end-to-end delivery | REST and TCP probes report reachable. | The same current probe reports the subscriber stopped; no message delivery was observed. |
| H5: matching optional fields imply valid identity | Earlier matcher compared field lookups for equality. | A regression demonstrated that both-missing fields compared equal; the candidate now requires present typed fields. |
| H6: any reconciled record permits the whole task to resume | Per-intent success previously cleared a task-wide flag. | An injected second pending record and scan error retain the stop; real concurrent MCP interleavings remain untested. |
| H7: textual intent IDs unambiguously identify their record kind | Assessment, planning, effect and completion use overlapping identifier syntax. | Pairwise and isolated-file tests reproduce the overlap; the candidate refuses it without providing a collision-resolution route. |
| H8: fresh effect-time authorization automatically preserves original task identity | The original check reconstructed a call from the current context. | A red regression reproduced a change of plan; candidate tests reject changed identities and permit the same lease to renew. |
| H9: an axiom-clean requested theorem proves every declaration in its module is complete | Initial audit checked only requested theorem dependencies. | A deliberately unrelated `sorry` passed until the helper scanned all target-module declarations. Source binding and statement matching remain separate. |
| H10: a successful Lean wrapper exit establishes that the audit ran | Fixed good/sorry fixtures returned expected statuses. | Adversarial initializer and elaborator fixtures both produced zero exit without running the intended audit. The route remains unsafe. |
| H11: a module name establishes the dependency's meaning | An imported constant still has the expected name. | Changing its definition preserved metadata-audit success; separate target replay rejected the altered proof. |
| H12: a resolved axiom set implies every dependency exists | The axiom collector returned an empty allowed set. | A same-name replacement missing a referenced declaration previously passed; the candidate closure scan now refuses that fixture. |

## 5. Fix Taxonomy

Poka-yoke: add a pinned compiler resolver and a compile-and-run preflight.
Jidoka: keep failed and unknown effects blocked. Muda: select the Nix `out`
output, reducing the profile dry run from 360 derivations to one assembly.
The classifier improves diagnosis but does not itself recover the blocked task.

## 6. Patterns & Anti-Patterns Discovered

An executable version probe is insufficient for a dependency that must compile
C; a real compile-and-run probe found the missing coverage. A recorded nonzero
exit must not be transformed into `KNOWN_NOT_APPLIED`, because partial artifacts
and escaped child processes remain possible. A warm-cache result cannot stand
in for a cold build.

Devil's Advocate falsifier: if a clean, candidate-bound MCP build completes
within 60 s without a prewarmed cache, the observed 82.17 s cold-build concern
may not generalize to that environment; retain both measurements and conditions.

## 7. Verification Matrix

Admiralty B2 is a provisional analyst judgment for the compiler-absence
observation: the task-bound failed receipt and a separate profile inspection
agree. It is not an independent certification or an admission decision.

| Evidence | Result | Limit |
|---|---|---|
| Candidate preflight | 33/33 passed with an explicitly linked canonical Mojo environment; absence of `cc` was rejected. | Direct bootstrap observation; re-run after candidate changes, not task-bound admission. |
| Isolated Gleam build | Passed with pinned compiler; cold 82.17 s and warm approximately 0.30 s. | Active MCP build deadline is 60 s; original failed receipt unchanged. |
| Gleam recovery tests | 188 tests passed across eight harness/MCP modules, including receipt ownership, fence ordering, interrupted prefixes, a simulated torn tombstone, task-wide stop behavior, namespace collisions and effect-time identity binding. Temporary-directory tests used isolated file reads and an in-memory planning store. | Actual sync failures, live stale-lease reconciliation, concurrent namespace creation and a complete MCP recovery path remain untested. |
| Earlier broader MCP test | 187 passed; one route-parity test returned `SA_PLAN_STORE_UNAVAILABLE` because its in-memory-store expectation encountered the canonical store directory. The adapter's inspected path refused before a database write. The fixture was changed to use a unique temporary workspace and the eight-module run then passed. | This does not exercise canonical Sa-plan transaction behavior or constitute a passing full application suite. |
| Release checker | 114 checks passed, including rejection of `CC`/`PATH` overrides and a poisoned OCaml-path fixture for child processes. | Parent interpreter startup and inherited HOME are not proved safe; does not authorize release. |
| Lean | Twenty-eight abstract theorems in three models checked; explicit audits allowed only `propext`, and sixteen identity/stop/effect-binding theorems need no axioms. | No proof of Gleam refinement, principal authentication, scan completeness, live lease ownership, torn writes, filesystem semantics or process containment. |
| Lean axiom-audit prototype | Twenty-one fixed positive and negative fixture checks passed using pinned Lean 4.33.0 in the direct bootstrap. The wrong-statement fixture passed the axiom audit and failed a separate expected-type check; two same-named modules with different source hashes both passed. | Module names are not source hashes; imports, process effects and actual MCP proof receipts are not verified. |
| Lean data-only prototype | Twenty-eight fixed-fixture checks passed, including multi-hop axiom and missing mutual-constructor cases; three additional bounded-unit fixtures accepted a clean theorem, suppressed an initializer and refused a hostile axiom. Target-only kernel replay refused a changed dependency. | Metadata success is explicitly not proof replay. Caller-selected artifacts/specification, full dependency replay, source hashes, general resource bounds and task-bound receipts remain unverified. |
| Lean sandbox prototype | Four direct probes passed: hidden home/cleared sentinel and refused source write; fixed good/sorry audit; distinct network namespace; and timed cleanup of one detached child. | Host isolation binaries are not pinned; arbitrary escape, network nonreachability, output/resource exhaustion and task-bound receipts remain unverified. |
| Lean adversarial gate | FAILED as intended: initializer early exit and command-elaborator suppression both reproduced. | The imported-wrapper prototype cannot authenticate audit completion and is barred from untrusted proof admission. |
| Independent reviews | Codex grant/candidate review and actual Claude/Fable and AGY Argon candidate reviews occurred. Both initial model reviews and a follow-up AGY review returned `REVISE`; a follow-up Claude request exceeded its threshold without a verdict. A Codex peer later reviewed the namespace guard and found no critical regression while recording race and liveness gaps. | The latest candidate has no AGY or Claude approval; cold-build and full recovery remain open. |
| Gleam formatter | The targeted format check failed on the four touched Gleam files, and the same check also failed on their canonical baseline. | Existing formatting debt remains; no broad reformat was made. |
| KM and Zenoh | KM health fields reported healthy; Zenoh REST/TCP reachable with subscriber stopped. | Point-in-time observations only; neither shows end-to-end FPP/SysML delivery. |
| MCP inventory | At 11:47Z the projection reported 101 declared, 89 implemented, zero observed and zero admitted; it describes its ledger as self-attested and unpinned. | Inventory status is not an independent capability audit, nor evidence that no individual call can work. |
| Receipt corpus | A read-only JSON comparison found 491 current effect pairs consistent on inspected identity fields. | Not execution of the candidate matcher; no provenance or live authority claim. |
| Full application tests | UNRUN. Some tests call `ensure_db_exists` or `execute_boot` against shared infrastructure. | Run only under a reviewed isolated environment and task-bound harness authority. |

## 8. Files Modified

Recovery candidate: `apps/cepaf_gleam/src/cepaf_gleam/harness/operations.gleam`,
`apps/cepaf_gleam/src/cepaf_gleam/harness/admission.gleam`,
`apps/cepaf_gleam/src/cepaf_gleam/harness/planning_intents.gleam`,
`apps/cepaf_gleam/src/cepaf_gleam/harness/successor_mcp.gleam`,
`apps/cepaf_gleam/src/cepaf_gleam/mcp/admission.gleam`,
`apps/cepaf_gleam/test/harness_pre_attach_assessment_test.gleam`,
`apps/cepaf_gleam/test/harness_successor_test.gleam`,
`apps/cepaf_gleam/test/mcp_admission_test.gleam`,
`apps/cepaf_gleam/test/mcp_route_parity_test.gleam`, `flake.nix`,
`devenv.nix`, `tools/lib/uos-toolchain.sh`, `tools/preflight`,
`tools/release_process.ml`, `formal/lean/HarnessFailedCheck.lean`,
`formal/lean/HarnessSourceScope.lean`, `formal/lean/HarnessReceiptBinding.lean`,
`formal/lean/HarnessAxiomAudit.lean`, `formal/lean/HarnessDataAudit.lean`,
`tools/test-harness-lean-audit`, `tools/test-harness-lean-data-audit`,
`tools/test-harness-lean-audit-adversarial`, `tools/test-harness-lean-sandbox`,
this journal and the linked design draft.
The separate FPP/SysML workspace contains only the
two MCP-written regression-test files. The peer grant-review record is separate.

## 9. Architectural Observations

MCP route availability, Sa-plan ownership and coordinator fencing are distinct
facts. A reviewed grant does not repair a gateway claim deadlock, a stale
heartbeat, or missing compiler. The local coordinator is cooperative; it is not
hostile-tenant IAM. Candidate-bound policy paths require a separate workspace;
other explicitly scoped Markdown/JSON evidence writes still resolve to the
canonical root and need separate authority review. Zenoh private ingress,
durable parameter storage and full SysML/FPP conformance remain unverified.

## 10. Remaining Gaps

Implement and independently review safe failed-effect adjudication, partial
artifact isolation and cold-build scheduling; restore the original task through
real MCP evidence. Then implement the FPP/SysML source changes, Lean/runtime
traceability, persistence, messaging, agent access and their end-to-end tests.
Verify live stale-lease rejection, atomic fencing around sidecar effects, and
full reconciliation/no-replay behavior; the present fence-ordering test uses a
supplied failing guard and is not a live coordinator test.
Test real multi-intent MCP routing, transactional namespace checks and explicit
collision resolution; inspect other-grant and global tombstone interactions.
Provide a safe route for historical planning IDs outside the new syntax.
Make the admitted-call provenance unforgeable for in-process callers, bind and
recheck route grants at the actual effect boundary, and authenticate each agent
and Zenoh sender independently instead of trusting shared labels.
Implement a bounded task-scoped Lean checker with an independently approved
expected statement, immutable complete-import binding, required kernel replay,
process containment and a trusted transitive axiom audit. A separate formal
FPP port-graph task is a possible next slice under the recorded isolated-task
precedent; it must leave this failed task and its immutable receipts held.
Test partial/torn file writes and implement a stable cross-attempt logical effect
identity before claiming deduplication for newly named equivalent operations.
Completion-scope evidence paths require a new reviewed grant. Investigate the
stopped Zenoh subscriber through its owning service and authorized fence. Exercise policy
grant decoding and JJ registration end to end, and review remaining canonical
evidence-write authority. Wiki/ZK writeback, the 18-checkpoint final gate and
Tailnet publication are pending.

## 11. Metrics Summary

Observed counts and timings are in section 7. The Claude CLI reported an
earlier budget-stopped review with estimated usage of USD 0.34731075 against
its USD 0.20 threshold; the first candidate review reported USD 0.43737. A
follow-up request configured with a USD 0.45 threshold returned no verdict and
reported USD 13.85694 at list-cost basis and 685,176 cache-creation tokens.
The three reported estimates total USD 14.64162075; actual provider charges
have not been independently reconciled. Its per-model token counters report the
cache usage while its top-level aggregate counters report zeros; the receipt is
internally inconsistent and must not be treated as confirmed billing. The submitted follow-up packet was
34,350 bytes. The local API-request trace records 167 attached instruction
files totaling 1,244,534 bytes, including 163 project-rule files totaling
1,145,694 bytes; its assembled first user-text block was 1,295,988 bytes.
This establishes substantial automatic context expansion but not the final
provider charge or the provider's exact tokenization.
Further paid dispatch is paused pending measured context and an externally
enforced pre-dispatch spending bound. Across two AGY reviews the CLI reported
86,366 input and 3,639 output tokens; monetary cost is unknown. No fleet-wide
cost or calibrated performance improvement is asserted. No Bayesian update or
Lyapunov derivative is computed without suitable observations.

## 12. STAMP & Constitutional Alignment

Not providing the stop, providing a false success, resuming at the wrong time,
or retaining authority too long are unsafe control actions. The candidate
retains the stop and provides no production authority. Sa-plan, JJ isolation,
EV-93 provenance ceiling, and the existing failed receipt are preserved.

## 13. Conclusion

The compiler defect has an isolated candidate fix and diagnostic evidence; the
full FPP/SysML integration and harness recovery are not complete. Forecast:
uncalibrated `p = 0.6` that an independently reviewed recovery design can be
specified by the Horizon 2026-11-03T18:00:00Z. Score the forecast only after
the outcome is observed using `(p - outcome)^2`; its current Brier score is
pending.

## Verification checklist

- [ ] CHK-01 Final timestamp and clock evidence bound.
- [ ] CHK-02 Tailnet publication and bytes observed.
- [ ] CHK-03 Fractal tags and layers verified.
- [ ] CHK-04 Wiki/ZK/KM reciprocal links reconciled.
- [ ] CHK-05 Zero-Muda checks executed.
- [ ] CHK-06 Graph/native-kernel boundaries verified where applicable.
- [ ] CHK-07 Storage interlocks verified in scope.
- [ ] CHK-08 Applicable C1–C8 checks executed.
- [ ] CHK-09 Mathematical gates evaluated on current evidence.
- [ ] CHK-10 Applicable unit, property, fault and performance checks executed.
- [ ] CHK-11 Candidate-bound regression and runtime observations recorded.
- [ ] CHK-12 OTP supervision and restart behavior observed.
- [ ] CHK-13 Hermes and bounded workers checked.
- [ ] CHK-14 ZigVM and VFS behavior checked where used.
- [ ] CHK-15 Inference isolation and actual model access checked.
- [ ] CHK-16 Trace and telemetry propagation observed.
- [ ] CHK-17 Required independent reviews and effect authority verified.
- [ ] CHK-18 JJ candidate and Sa-plan evidence reconciled.
- [ ] Provenance: EV-93 ceiling preserved; later claims remain unadmitted.
