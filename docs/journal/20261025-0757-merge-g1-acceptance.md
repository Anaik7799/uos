# 20261025-0757 — Exact mainline source acceptance

#fractal-l0 #fractal-l5 #fractal-l9 #zk-adr #zero-muda

[Planning](http://nas-1.tail55d152.ts.net:4100/planning)

## 1. Scope & Trigger

G1_ACCEPT reconciles the already integrated source-only main 2ab40165, without moving main or changing production.

## 2. Pre-State Assessment

Claude plan mixed the integration review with the later retry-fix review. Current source identity and review bindings needed independent reconciliation before applying remaining trunk changes.

## 3. Execution Detail

Compared 1735 current source/test paths against executed full-app, targeted, native and final retry manifests: zero mismatches. Verified AGY 09e210fd binds 8169e1b9, and AGY 5093ed55 binds 2ab40165. Fresh retry-budget binary replay passed 26 checks.

## 4. Root Cause Analysis

ACH H1 stale or mismatched candidate; H2 correct candidate with incomplete plan references. Exact 1735-path equality and two exact review identifiers disconfirm H1 for this scoped acceptance and support H2. Full unrelated system behavior remains unestablished.

## 5. Fix Taxonomy

Poka-Yoke: exact current bytes bound to independent reviews. Muda: reuse unchanged candidate-bound build/browser/native receipts; new integrated source will receive fresh tests. No global fitness or admission claim.

## 6. Patterns & Anti-Patterns Discovered

Devil's Advocate: could trunk restore remove newer fixes? Four both-changed paths and one main-only test were identified; they require explicit preservation in G2. A branch name is not proof of source equivalence.

## 7. Verification Matrix

Admiralty A1 direct byte equality and fresh deterministic 26-check replay; B2 or better applies only to these bounded observations. Prior unchanged evidence remains 289 targeted Gleam checks, 174 store assertions, 3383 lease/recovery checks, two full application compiles and health/chat HTTP/Chromium groups. Unrelated full-monorepo gates and all seven engines are UNRUN, not green.

## 8. Files Modified

Full trunk ledger: 733 paths, comprising 117 code, 29 agent-surface, 586 evidence and one binary. Four both-changed paths require review; one main-only test stays. Own-workspace ledger and this journal; operational receipts var/recovery-runtime/20261025-0757-merge-g1.

## 9. Architectural Observations

Source-only integration acceptance uses relevant current candidate evidence. The advisory plan's unconditional all-ancestor divergence gate cannot pass existing main without rewriting historical authorship; historical variants are preserved, current tip conflicts remain separately checked.

## 10. Remaining Gaps

G2+ still open. 733 differences are inventoried, not automatically accepted. All-code merge, Telegram completeness, global admission and production activation remain incomplete.

## 11. Metrics Summary

1735 source bindings matched; zero mismatches; 26 fresh retry tests passed; two independent AGY candidate bindings reconciled. Bayesian stability and Lyapunov measurements are UNRUN.

## 12. STAMP & Constitutional Alignment

No main movement, release, unsafe history graft or default reset. Newer retry-budget behavior must survive G2; source acceptance is separate from deployment and admission.

## 13. Conclusion

Scoped G1 acceptance passed. Forecast p=0.8: at least one deferred integration group needs a source repair within the next two active hours; Brier result pending. Remaining full-code consolidation proceeds through G2.

## Comprehensive verification checklist

These are obligations for executing the plan. Only the document-level items are checked.

<details><summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [ ] **CHK-01-TIME** — `20261025-0638-` prefix from the host clock; all times converted to Z; versions recorded.
- [ ] **CHK-02-TAIL** — Full Tailscale FQDN links; whether they are served is unverified.
- [ ] **CHK-03-FRACT** — L0–L9 mapped (§10, §12.2).
- [ ] **CHK-04-KM** — MOC, corpus index and related contracts linked.

</details>
<details><summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Per-generation scan: UNRUN.
- [ ] **CHK-06-GRAPH** — No new foreign NIF: UNRUN.
- [ ] **CHK-07-DRIVE** — Interlock 7/7; unmounted disks untouched: UNRUN.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Applicable UI surfaces: UNRUN.
- [ ] **CHK-09-MATH** — Four declared gates: UNRUN.
- [ ] **CHK-10-9MOD** — Relevant modalities: UNRUN.
- [ ] **CHK-11-REGR** — Telegram/browser regression at each tip: UNRUN.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — OTP 29 build/test: UNRUN.
- [ ] **CHK-13-HERMES** — dune build/test: UNRUN.
- [ ] **CHK-14-ZIGVM** — If touched: UNRUN.
- [ ] **CHK-15-MAX** — Not applicable unless `services/inference/max` changes.
- [ ] **CHK-16-OTEL** — Not applicable to a VCS merge.

</details>
<details><summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Independent AGY review on v4: APPROVE_WITH_CHANGES, all findings dispositioned (§17). Per-generation reviews remain UNRUN.
- [ ] **CHK-18-JJ** — jj only; no native Git; the off-host push is a jj command under D3.

</details>
<details><summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted. EV-98 test files are deferred by default.

</details>

**Previous:** [Telegram critical path](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · **Next:** per-generation merge journals · [ZK Master MOC](http://nas-1.tail55d152.ts.net:4100/zk) · [Wiki Corpus Index](http://nas-1.tail55d152.ts.net:4100/wiki)

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · peer `vm-1.tail55d152.ts.net:4100` · Proposed plan only; Sa-plan is the sole execution authority; integration grants no release or admission.
