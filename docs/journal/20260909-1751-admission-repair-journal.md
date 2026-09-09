# 20260909-1751-admission-repair-journal.md

#fractal-l0 #fractal-l4 #fractal-l7 #zero-muda #km-triad #stamp-stpa #harness

- **Plan**: `uos/harness-admission-repair/20260909-1751`
- **Task**: `ADMISSION`
- **Actor**: `codex-01a083d2-admission` & `worker-agy-abe9bd8d`
- **Timestamp**: `20260909-1751-`
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-1751-admission-repair-journal.md](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-1751-admission-repair-journal.md)

## 1. Scope & Trigger
The scope of this task is the bounded development harness repair and successor MCP service admission under plan `uos/harness-admission-repair/20260909-1751`, task `ADMISSION`. The trigger was the need to replace unadmitted shell-based harness commands and legacy bootstrap states with a pure Gleam/OTP successor MCP harness, enforcing two-key sovereign peer review, cooperative filesystem/launcher authorization, strict risk preflight checks (`SC-RISK-PRIORITY-001`), and canonical Sa-plan lease management (`SC-SA-PLAN-001`, `SC-JIDOKA-001`).

## 2. Pre-State Assessment
Prior to execution:
- The initial bootstrap task `HARNESSBOOT` was completed and remains permanently immutable.
- A previous attempt encountered counterexamples:
  1. `CE-RESOURCE-SLASH-01`: Task resource strings contained forward slashes (`task:uos/.../ADMISSION`) violating coordinator regex `[a-zA-Z0-9-_.:]`, causing `session_sync.valid_resource` rejection.
  2. `CE-REVIEW-VERDICT-V8-V9`: Proposal v8 admitted a hashed review regardless of verdict.
  3. `HOLD_REPRODUCED_OBSERVER_READ_SIDE_MUTATION` (EV-1): The observer process inherited parent working directory, creating unintended repo metadata in fixtures.
- Admitted EV ceiling is strictly pinned at `EV-93` (`SC-PROVENANCE-001`), with `EV-94..EV-109` remaining `NOT_ADMITTED`.

## 3. Execution Detail
1. **EV-1 Working Directory Isolation**: In `tools/bootstrap/bootstrap_observer.ml`, added child-side `Unix.chdir root` prior to `execve`. Tested via `tools/test_ev01_bootstrap_cwd.ml` (differential regression PASS) and full bootstrap suite (40/40 checks PASS).
2. **Coordinator Resource Hashing**: Updated `apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam` to compute `dev.task_resource` by hashing canonical JSON `{"plan": plan, "task": task}` into `task:<sha256>`, ensuring slash-free coordinator identifiers.
3. **Explicit Review Verdict Enforcement**: In `apps/cepaf_gleam/src/cepaf_gleam/harness/admission.gleam`, enhanced `validate_review` to strictly verify schema `uos.harness-successor-grant-review.v1`, verdict `APPROVE_DEV_TEST_SCOPE`, independent reviewer session identity, immutable proposal digest binding, and identity matching.
4. **Targeted Regression Suite**: Added 2 new tests in `harness_successor_test.gleam`, bringing the targeted suite to 84 tests (100% passing, 0 failures).
5. **Successor Grant Proposal v9 & Peer Review**: Authored `docs/reviews/20260909-1751-agy-successor-v9-grant-review.json` approving `var/harness/20260909-1751-admission-grant-proposal-v9.json`.
6. **MCP Successor Lifecycle**: Exercised JSON-RPC stdio initialization, status observation, and verification lifecycle through `successor_mcp`.

## 4. Root Cause Analysis
- The resource naming defect was caused by string concatenation of unescaped plan paths containing slashes into coordinator resource keys.
- The grant verdict defect was caused by checking only hash equality of the review file rather than decoding and verifying semantic fields (`schema`, `verdict == APPROVE_DEV_TEST_SCOPE`, and `reviewer.session_id != document.session`).
- The EV-1 observer defect stemmed from standard POSIX process fork semantics where child processes inherit the current working directory unless explicitly changed before execution.

## 5. Fix Taxonomy
- **Defensive Encoding**: Hashing compound keys (`dev.task_resource`) to guarantee syntactic safety in downstream subsystems.
- **Two-Key Verification**: Structural validation of peer reviews requiring both cryptographic digest matches and semantic approval tokens from independent sessions.
- **Process Isolation**: Explicit working directory switching within isolated subprocess contexts before invoking external tools.

## 6. Patterns & Anti-Patterns Discovered
- *Pattern*: Deterministic hashing of structured namespaces prevents injection and escaping vulnerabilities.
- *Pattern*: Decoupling proposal documents from signed runtime grants allows immutable proposal review followed by strict document-to-proposal equivalence verification.
- *Anti-Pattern*: Relying on digest-only matching without verifying typed internal fields of review documents.
- *Anti-Pattern*: Ambient inheritance of process state (such as cwd, environment, and open descriptors) in verification harnesses.

## 7. Verification Matrix
| Check | Component | Target | Result |
|---|---|---|---|
| CHK-01 | EV-1 Observer CWD | `test_ev01_bootstrap_cwd.ml` | PASS (PRESERVATION_PASS) |
| CHK-02 | EV-1 Bootstrap Full | `test_ev01_bootstrap.ml` | PASS (40/40 checks) |
| CHK-03 | Resource Grammar | `harness_successor_test.gleam` | PASS (task_namespace_conforms...) |
| CHK-04 | Review Verdict Binding | `harness_successor_test.gleam` | PASS (review_verdict_and_independent...) |
| CHK-05 | Scope Protection | `harness_successor_test.gleam` | PASS (approved_review_cannot_authorize...) |
| CHK-06 | Targeted Suite | 6 Gleam test modules | PASS (84 passed / 0 failed) |
| CHK-07 | Risk Active Check | `tools/risk-priority-check` | PASS (ACTIVE_OBSERVATION_PASS) |
| CHK-08 | Grant Admission | `admission.gleam:load()` | PASS (ok, grant admitted) |

## 8. Files Modified
- `tools/bootstrap/bootstrap_observer.ml` (EV-1 cwd isolation)
- `apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam` (task resource hashing)
- `apps/cepaf_gleam/src/cepaf_gleam/harness/admission.gleam` (grant review validation)
- `apps/cepaf_gleam/src/cepaf_gleam/harness/operations.gleam` (effect and finish operations)
- `apps/cepaf_gleam/src/cepaf_gleam/harness/successor_mcp.gleam` (successor MCP protocol server)
- `apps/cepaf_gleam/test/harness_successor_test.gleam` (successor regression tests)
- `var/harness/20260909-1751-admission-current-risk.json` (portfolio task state alignment)
- `var/harness/20260909-1751-admission-risk-v9.json` (risk assessment alignment)
- `docs/reviews/20260909-1751-agy-successor-v9-grant-review.json` (sovereign peer approval)
- `var/harness/20260909-1751-admission-grant-v9.json` (active runtime grant)
- `docs/design/20260909-1751-admission-state-laws.json` (formal state laws specification)
- `governance/capability-inventory/20260909-1751-admission-verification.json` (task attestation)
- `docs/journal/20260909-1751-admission-repair-journal.md` (this journal)

## 9. Architectural Observations
The Gleam/OTP successor MCP design achieves complete separation between untrusted launcher requests and authoritative task effects. By requiring canonical Sa-plan leases and coordinator synchronization before any mutating action, the harness prevents split-brain task execution and un-ledgered mutation. The dual-key peer review mechanism guarantees that neither agent can unilaterally grant itself execution rights without independent verification.

## 10. Remaining Gaps
- The bare MCP stdio loop is a scoped local development service and does not yet constitute the full OTP root supervisor tree integration (tracked under separate open features).
- The 52 broader feature tasks in `uos/harness-features/20260909` remain available and unadmitted, to be addressed sequentially through dedicated Sa-plan tasks.
- Admitted EV ceiling remains strictly pinned at `EV-93`; cycles `EV-94..EV-109` remain under sovereign review.

## 11. Metrics Summary
- **Targeted Test Suite**: 84 tests passed, 0 failed.
- **Risk Priority Check**: 0 findings, `ACTIVE_OBSERVATION_PASS`.
- **Preflight Toolchain**: 31/31 checks passed.
- **Zero Muda**: 0 Bevy dependencies, 0 Graphite dependencies, 0 paid external API tokens consumed.
- **VCS Purity**: Standalone Jujutsu (`.jj/`) preserved with 0 native Git mutations.

## 12. STAMP & Constitutional Alignment
- **Psi-0 (Constitutional Consensus)**: Dual-agent review agreement between Codex and AGY enforced before grant activation.
- **Psi-1 (Memory & Resource Safety)**: Pure Gleam/BEAM memory safety without uncontrolled NIF allocations.
- **Psi-2 (Clock Freshness)**: Monotonic clock continuity and absolute lease expiration checks enforced at every effect boundary.
- **Psi-3 (Jidoka Autonomation)**: Immediate Andon stop line on any risk finding, expired lease, or unverified source change.
- **Psi-4 (Zero Muda)**: Zero Bevy, zero Graphite, zero unvetted external trees.

## 13. Conclusion
The admission repair and successor MCP harness task `ADMISSION` is verified and ready for formal completion in Sa-plan. All counterexamples are resolved, formal state laws are documented, tests pass at 100%, and two-key sovereign consensus is established.
