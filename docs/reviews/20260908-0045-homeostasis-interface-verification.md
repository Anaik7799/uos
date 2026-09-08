# Homeostasis interface verification and recordings

#fractal-l0 #fractal-l2 #fractal-l5 #zk-adr #zero-muda #tailscale-web

Checked: **2026-09-08 01:56:45 UTC**. Result: **scoped candidate checks PASS; production admission NOT GRANTED**.
Source revision: `294661d3941946413b591285b394969def88c42e`.
[Machine receipt and SHA-256 manifest](20260908-0045-homeostasis-interface-verification.json).
[Contract and test strategy](../design/20260908-0045-homeostasis-interface-specification.md).
[Rules/skills/Superpowers](../design/20260908-0045-gui-tui-skills-rules-and-superpowers.md).
[Journal](../journal/20260908-0045-homeostasis-interface-repair-journal.md).

The implementation was exercised in a private OTP 29 HTTP process and actual Chrome, outside
the production supervisor. Real mode means **the serving test VM's measured counters**.
Physical CPU/host-memory percentages, health, latency, PID stability and peer votes remain UNKNOWN.
Test mode is visibly SIMULATED. Controls preview data and cannot execute production changes.

## Verification receipts

| Check | Observed result |
|---|---|
| Focused Gleam/EUnit | 69 passed, 0 failed; OTP 29; [log](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-unit.log) |
| Chrome browser checks | 43 passed at 320, 768 and 1280 px; [log](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-browser.log) |
| Model evolution | 30 simulated transitions; generation/history/time/energy assertions |
| Cross-surface algebra | 30 cycles × four scenarios = 120 projection cases |
| Final browser recordings | 26 recordings, 780 checked cycles, 21 fields checked per cycle = 16,380 field comparisons |
| Continuous updates | All 26 receipts have strictly advancing frame counters; all real receipts have advancing source UTC |
| Native PTY | Real and test: 30 rendered cycles each; exit 0, expected mode and authority NONE |
| Media integrity | Every clip is at least 30 seconds (30.92–31.36 s); SHA-256 and byte sizes recorded |
| Receipt checker controls | Four corruptions rejected: missing cycle, stalled update, backward clock, false real attribution |
| Source identity | 682 application files + 12 test/probe modules equal the compiled copy; changed-file hashes recorded |
| Historical preservation | 15 earlier design/ADR bodies are byte-identical below their new correction notices |
| Local skill package | 3 skills, 12 aliases, 10 resources; 8 negative fixtures rejected |
| Full system / formal / admission | Full UOS suite, independent Lean/Quint, live deployment and peer admission **UNRUN** |

The initial red check found eight regressions before repair. Intermediate failures included
compiler keyword/option issues, an old TUI test expecting a fabricated open gate and a stale risk
task-state field; those were corrected before these passing receipts. The first capture pass predates
the final controls/schema fixes and is retained as history. **Use pass2 below** for current evidence.

## Browser recordings

Each component has its own focused recording in both modes. The full-page clips tour all panels;
the terminal page shows the shared text projection. The captured window is slightly longer than
30 seconds to preserve 30 complete checked update intervals. No deployment or agent dispatch occurred.

| Mode | Page / component | Recording | Update receipt |
|---|---|---|---|
| real | homeostasis | [30.92 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-all.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-all.json) |
| real | homeostasis/evolution | [31.36 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-evolution-all.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-evolution-all.json) |
| real | homeostasis/terminal | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-terminal-all.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-terminal-all.json) |
| real | homeostasis/components / provenance | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-provenance.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-provenance.json) |
| real | homeostasis/components / controls | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-controls.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-controls.json) |
| real | homeostasis/components / pid | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-pid.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-pid.json) |
| real | homeostasis/components / phase | [30.92 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-phase.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-phase.json) |
| real | homeostasis/components / physiology | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-physiology.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-physiology.json) |
| real | homeostasis/components / runtime | [31.00 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-runtime.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-runtime.json) |
| real | homeostasis/components / pareto | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-pareto.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-pareto.json) |
| real | homeostasis/components / quorum | [30.92 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-quorum.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-quorum.json) |
| real | homeostasis/components / stream | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-stream.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-stream.json) |
| real | homeostasis/components / checklist | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-checklist.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-real-homeostasis-components-checklist.json) |
| test | homeostasis | [31.36 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-all.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-all.json) |
| test | homeostasis/evolution | [31.20 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-evolution-all.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-evolution-all.json) |
| test | homeostasis/terminal | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-terminal-all.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-terminal-all.json) |
| test | homeostasis/components / provenance | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-provenance.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-provenance.json) |
| test | homeostasis/components / controls | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-controls.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-controls.json) |
| test | homeostasis/components / pid | [30.92 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-pid.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-pid.json) |
| test | homeostasis/components / phase | [30.92 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-phase.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-phase.json) |
| test | homeostasis/components / physiology | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-physiology.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-physiology.json) |
| test | homeostasis/components / runtime | [30.92 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-runtime.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-runtime.json) |
| test | homeostasis/components / pareto | [30.92 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-pareto.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-pareto.json) |
| test | homeostasis/components / quorum | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-quorum.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-quorum.json) |
| test | homeostasis/components / stream | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-stream.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-stream.json) |
| test | homeostasis/components / checklist | [30.96 s](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-checklist.webm) | [30 cycles](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-test-homeostasis-components-checklist.json) |

## Native terminal and screenshots

- [Real terminal transcript](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-pty-real.txt) · [timing](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-pty-real.timing)
- [Test terminal transcript](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-pty-test.txt) · [timing](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-pty-test.timing)
- [320 px screenshot](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-homeostasis-320.png)
- [768 px screenshot](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-homeostasis-768.png)
- [1280 px screenshot](../../var/evidence/homeostasis/20260908-0045/pass2/20260908-0045-homeostasis-1280.png)

The PTY transcripts are genuine terminal output and timing, not browser screenshots relabelled as
native execution. They cover the renderer/data entrypoints. Full-screen host input, mouse, resize,
TTY restoration under every signal and integration with the complete interactive UOS TUI remain
separate acceptance work.

## Integration boundary

The intended [production homeostasis page](http://nas-1.tail55d152.ts.net:4100/homeostasis/evolution)
was not redeployed or used as candidate proof. Integrators must use the JJ review candidate and
re-run the tests against their integration revision. Real control authority requires trusted
physiological adapters, current Sa-plan ownership, revision-bound evidence and independent release
approval. A green screenshot or this receipt cannot substitute for those gates.

Binary clips/screenshots stay in the ignored local evidence directory. Their source, checks,
reproduction instructions and integrity manifest are repository-contained. Copy the evidence
directory with the manifest when handing the review to a machine without these local artifacts.


<details><summary>Verification: 5 domains / 18 checkpoints</summary>

| Domain | Checkpoints and current scope |
|---|---|
| Metadata/time/navigation | CHK-01 observed host time; CHK-02 FQDN references, publication UNVERIFIED; CHK-03 fractal tags; CHK-04 local specification/knowledge links |
| Purity/storage | CHK-05 no new foreign runtime; CHK-06 native boundaries unchanged; CHK-07 storage interlock UNRUN |
| Tests/mathematics | CHK-08 full C1–C8 UNRUN; CHK-09 bounded algebraic tests only; CHK-10 nine modalities UNRUN; CHK-11 candidate UI checks in attached receipt |
| Control/observability | CHK-12 private OTP 29 run; CHK-13 independent formal proof UNRUN; CHK-14 ZigVM UNRUN; CHK-15 MAX UNRUN; CHK-16 source timestamps and SSE tested, full OTel correlation UNRUN |
| Governance/JJ | CHK-17 independent admission UNRUN; CHK-18 isolated JJ candidate, no mainline cutover |

</details>


