# Telegram main-protection journal

Observed 2026-10-11T18:52:49.092Z · #fractal-l0 #fractal-l3 #fractal-l9 #zk-adr #zero-muda

[Guard evidence](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261011-1746-telegram-vcs-guard-observation.json) · [AGY acknowledgement](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261011-2045-telegram-observer-independent-review-agy.json)

## 1. Scope & Trigger

TELEGRAM_VCS_GUARD, uos/telegram-runtime/20261001-1150, codex-telegram-20261011. Configuration was installed under attempt 1; closure is under fresh attempt 2 after explicit AGY acknowledgement. Engine 5 formal gateway: standalone JJ policy, protected main and preservation of both histories.

## 2. Pre-State Assessment

AGY's older ancestor workspace ran jj status at 16:37:21Z. Snapshotting that mutable ancestor automatically rebased descendants, moving main from 83dca039 to a8adcc69. Only three evidence JSON files were added by the exact main-tree difference; this was not a reviewed Telegram service merge. Engine 7 Kalman prior UNKNOWN.

## 3. Execution Detail

An isolated standalone JJ fixture reproduced the ancestor/descendant case and proved that adding main to immutable_heads creates a fresh child for local edits while preserving main. Root installed repository-only revset-aliases.immutable_heads() = builtin_immutable_heads() | main, preserving unrelated configuration and backing it up privately. Fresh readback still reports that rule and main a8adcc6958e5c2378678b56adf9d5d14f44f02b3. Actual AGY acknowledged the guard and the --ignore-working-copy observation rule. Engine 6 Rete-UL execution UNRUN.

## 4. Root Cause Analysis

Engine 1 ACH: H1 read-like jj status cannot change history was disproved by operation d441cd7b55d1. H2 local main was already protected was disproved by the original builtin_immutable_heads() configuration. The structural fix protects main and its ancestors from ordinary rewrites; no destructive undo was used.

## 5. Fix Taxonomy

Poka-Yoke: immutable main and explicit snapshot-free observation commands. Jidoka: keep unreviewed service integration and release on HOLD. Muda: one repository-scoped configuration change, with both old histories and all evidence retained.

## 6. Patterns & Anti-Patterns Discovered

Engine 4 Red Team fixture verifies actual JJ behavior rather than relying on the command's name. The first task-specific coordinator claim was refused because the heartbeat was stale; a private fixture command incorrectly followed in the same orchestration call. That deviation remains recorded. Root refreshed the heartbeat, obtained claim/check success, and only then changed canonical configuration.

## 7. Verification Matrix

Engine 2 STANAG 2017 B2 for direct observations: private ancestor snapshot creates a child, preserves edited bytes, and leaves main commit/tree unchanged. Actual installation preserves unrelated config and main; current readback matches. AGY receipt SHA-256 9d6a0bcab51255497ceaeb63741c6d6197683386b567b8598a81934b2300fea7 explicitly acknowledges both the guard and observation rule. This is development protection, not release authority.

## 8. Files Modified

Repository config /home/an/.config/jj/repos/797c18a8a6d06a90b41a/config.toml; owned private fixture/evidence under var/recovery-runtime/20261011-1746-telegram-vcs-guard; governance/planning/20261011-1746-telegram-vcs-guard-observation.json; this journal. Other configuration was preserved, and no root bookmark move, history reset, source-tree cleanup or Git mutation occurred.

## 9. Architectural Observations

Immutable-head protection is a local JJ safeguard. It complements canonical task ownership and independent release review; it does not replace either. Engine 5 categorical/sheaf consistency is not newly proved. Explicit ignore-immutable could bypass this cooperative protection and is not authorized by this task.

## 10. Remaining Gaps

Full Telegram service recovery, Mini App, commands, media, gateway, formal repair, end-to-end release checks and stabilized main integration remain pending. Other agents' historical claims remain evidence, not admission. The main tree is preserved while those obligations are completed.

## 11. Metrics Summary

One canonical configuration key changed; unrelated config preserved; one private behavioral fixture and fresh actual readback passed; one explicit AGY acknowledgement received. Engine 3 Bayesian Beta-Binomial posterior NOT_ESTIMATED; correlated checks do not support an independent-trial estimate. Lyapunov dV/dt < 0 UNRUN.

## 12. STAMP & Constitutional Alignment

FMEA S4/O2/Det3, RPN 24: an ancestor snapshot can silently move the release reference. UCAs: not_provided—missing protection; provided_unsafe—unreviewed main rewrite; wrong_timing—snapshot before reviewed integration; duration—mutable ancestor remains writable indefinitely. The guard and isolated-workspace discipline reduce these risks. EV ceiling 93 unchanged; no new EV number or global admission.

## 13. Conclusion

The scoped main-protection task is complete in substance and this journal accompanies canonical closure under attempt 2. Engine 7 Forecast p=.8: the guard and main a8adcc69 remain unchanged through Horizon 2026-10-11T19:15:00Z while service stabilization continues. Evaluate Brier=(p-o)^2 against a fresh readonly JJ/config observation.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [ ] **CHK-01-TIME** — Observe synchronized clock evidence and document prefix.
- [ ] **CHK-02-TAIL** — Verify full Tailnet links and actual serving status.
- [ ] **CHK-03-FRACT** — Verify L0–L9 tags and applicable layer mapping.
- [ ] **CHK-04-KM** — Reconcile specification, wiki, ZK and journal links.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Verify exclusions against the candidate dependencies.
- [ ] **CHK-06-GRAPH** — Verify the pure BEAM/Hermes graph boundary.
- [ ] **CHK-07-DRIVE** — Preserve the denied OS serial and test real interlocks only in scope.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Verify all applicable C1–C8 surfaces.
- [ ] **CHK-09-MATH** — Measure the four declared mathematical gates.
- [ ] **CHK-10-9MOD** — Apply relevant unit, system, TDD, BDD, performance, scalability, property, fuzz and chaos checks.
- [ ] **CHK-11-REGR** — Run applicable regressions and bounded observation.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Observe actual OTP control/supervision behavior.
- [ ] **CHK-13-HERMES** — Observe bounded analysis and authoritative evidence.
- [ ] **CHK-14-ZIGVM** — Verify deterministic execution and descriptor-relative VFS.
- [ ] **CHK-15-MAX** — Observe actual isolated inference when applicable.
- [ ] **CHK-16-OTEL** — Verify clock and nonzero trace/span identity.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Obtain candidate-bound independent review and authorized admission.
- [ ] **CHK-18-JJ** — Preserve standalone JJ, source ownership and exact candidate identity.

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted.

</details>

[Previous: formal specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

UOS footer: document and component evidence do not grant system admission.

[Previous ledger](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261001-1202-telegram-browser-admission-recovery.md) · [Next: planning status](http://nas-1.tail55d152.ts.net:4100/planning)

