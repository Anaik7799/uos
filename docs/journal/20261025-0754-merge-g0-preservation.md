# 20261025-0754 — Merge G0 preservation and GitHub checkpoint

#fractal-l0 #fractal-l5 #fractal-l9 #zk-adr #zero-muda

[Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

## 1. Scope & Trigger

Operator directed all-code mainline consolidation and GitHub publication before further Telegram feature work. G0_PRESERVE attempt1, Codex worker, through Gleam-bound adapter and canonical Sa-plan.

## 2. Pre-State Assessment

Main 2ab40165 was 228 commits ahead of origin; source and evidence were distributed across sibling workspaces. Claude v5 underestimated divergence: fresh census found 25 changes / 50 variants.

## 3. Execution Detail

Created 57 preservation/recovery bookmarks including both variants and unreviewed config work. Backed up .jj and 14112 tracked working files; stable JJ operation during capture. Local restore matched. AES-256-GCM archives copied to vm-1 and authenticated, restored, compared. jj push main succeeded and fresh fetch confirmed 2ab40165.

## 4. Root Cause Analysis

ACH hypotheses: H1 absent code; H2 integration debt; H3 unsafe source loss. Current source and many completed task receipts disconfirm absence as the sole cause. 228 unpushed revisions and distributed evidence support integration debt. No data loss observed; backup and exact restore falsify loss for the captured scope.

## 5. Fix Taxonomy

Poka-Yoke: explicit main-only push and outgoing-history scan. Jidoka: expired ordinary release refusal preserved without SQL bypass. Muda: reused proven Gleam/SQLite adapter and existing toolchain; no new scheduler or packages.

## 6. Patterns & Anti-Patterns Discovered

A filtered code inventory missed evidence/skill paths. A no-output model success cannot establish review. Repository-global op restore and blanket preserved-bookmark push remain prohibited in this execution. Devil's Advocate / Popperian falsification: remote backup was decrypted and read through JJ, not accepted from copy exit alone.

## 7. Verification Matrix

PASS: 14112 local restored files, main identity, preservation-list digest; both remote AES-GCM authentication checks and plaintext archive digests; remote JJ restored main and bookmark digest; GitHub fetch/readback 2ab40165. Pattern scan: 13386 main files and 228 outgoing commit diffs; matches classified as existing baseline or test literals. Admiralty A1 for the scoped deterministic backup observations: primary command receipts and direct local/remote byte comparisons agree. This exceeds the B2 observation threshold for source preservation only; runtime admission and all seven verification engines are not claimed.

## 8. Files Modified

Own workspace contains frozen Claude plan and risk portfolio plus this journal and checkpoint. Operational evidence is under var/recovery-runtime/20261025-0747-merge-g0; backups are private /home/an/uos-backups/20261025-0747 on NAS and vm-1. No product source modified in G0.

## 9. Architectural Observations

session_store_cli provides current SQLite coordinator authority. Legacy session_sync_cli journal replay failure is separate; it must not trigger journal reconstruction. Shared historical divergence persists; no ancestor rewriting performed.

## 10. Remaining Gaps

733 trunk differences and other heads still need integration. 22 expired tasks and 23 expired/over-budget jobs explicitly held. Existing token-shaped script fallback and tracked SQLite database already present identically at origin need separate cleanup. Pattern scanning is not exhaustive credential proof. Canonical live runtime databases are outside this source backup.

## 11. Metrics Summary

57 new preservation/recovery bookmarks; 1,688,176,640 archive bytes; 14112 restored tracked files; 0 file mismatches; 228 revisions pushed. No fabricated Bayesian probability update or negative Lyapunov derivative; those measurements are UNRUN.

## 12. STAMP & Constitutional Alignment

No data abandonment, default reset, native Git, unmounted disk access, production effect or new EV number. Main push is source publication, not release/admission. Explicit operator authority supersedes optional decision prompts in the advisory plan.

## 13. Conclusion

G0 preservation and source-publication acceptance passed with explicit per-row holds for expired authority. Forecast: next integration inventory will expose additional old/new version conflicts; p=0.8 within two active hours. Brier score pending horizon; full restoration and all-code merge remain incomplete.

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
