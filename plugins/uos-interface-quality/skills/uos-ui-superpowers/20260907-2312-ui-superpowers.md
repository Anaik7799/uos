---
name: uos-ui-superpowers
description: Use when planning, debugging, testing or reviewing UOS GUI/TUI work that needs an explicit design decision and evidence of user-visible behavior.
---

# 20260907-2312 — uos-ui-superpowers

Created: 2026-09-07T23:30:00Z. #fractal-l0 #fractal-l2 #fractal-l4 #fractal-l7 #fractal-l9 #zk-adr #zero-muda

[Candidate source](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-interface-quality/skills/uos-ui-superpowers/SKILL.md) · [Journal](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-2312-interface-skills-journal.md)

Candidate files are local in this workspace; publication at these URLs is unverified.

This is a UOS adaptation of useful Superpowers practices, not an upstream Superpowers installation. It is self-contained. Read [interface rules](../../references/20260907-2312-interface-rules.md) Process and the relevant GUI/TUI section.

- **Design:** State the user outcome, constraints and two meaningful alternatives when a real tradeoff exists. Reuse current primitives. Record the selected behavior and acceptance cases before a substantial change; keep minor edits proportionate.
- **Plan:** Use Sa-plan for execution authority. Rank actual work by safety class and dependency eligibility before C × STPA × FMEA × dependency × impact. Use the repository risk SOP, a bounded own task and an isolated JJ workspace.
- **Debug:** Reproduce the visible failure; trace source → transport → state → rendered output. Test the cheapest discriminating hypothesis before broad changes.
- **Implement:** For behavior fixes, make the relevant regression fail, apply the smallest fix and rerun. Use examples/property tests for pure models and actual browser/PTY tests for interactions. Do not add tests that only duplicate a literal.
- **Review:** Examine changed lines and callers, unknown/stale states, authority boundaries and adverse cases. Prioritize findings by consequence and evidence; explain uncertainty.
- **Verify:** Bind each claim to revision, command, time and result. Packaging, unit tests, live integration, accessibility and formal proof are separate evidence classes. Document unrun checks and residuals in the 13-section journal.

Run scenarios UI-01–12, including the negative scope and false-completion cases. Use deterministic tools before paid inference. This skill grants no authority to contact agents, spend money, install global tools or deploy. Respect a side session's prohibition on subagents; record independent skill testing as UNRUN when unavailable.

<details><summary>Verification — 5 domains / 18 checkpoints</summary>

Status applies to this guidance package; unchecked means unrun, not passed.

- Domain 1: [x] CHK-01-TIME host time; [x] CHK-02-TAIL FQDN references (publication unverified); [x] CHK-03-FRACT tags; [x] CHK-04-KM local rules and journal.
- Domain 2: [ ] CHK-05-MUDA fleet scan; [ ] CHK-06-GRAPH runtime language conformance; [ ] CHK-07-DRIVE hardware interlock.
- Domain 3: [ ] CHK-08-C1C8 full UI matrix; [ ] CHK-09-MATH mathematical gates; [ ] CHK-10-9MOD nine modalities; [ ] CHK-11-REGR deployed regression.
- Domain 4: [ ] CHK-12-GLEAM supervision; [ ] CHK-13-HERMES independent formal evidence; [ ] CHK-14-ZIGVM kernel; [ ] CHK-15-MAX inference; [ ] CHK-16-OTEL live trace correlation.
- Domain 5: [ ] CHK-17-SOV independent admission; [x] CHK-18-JJ isolated Jujutsu only.

</details>

UOS: scoped guidance; evidence does not confer runtime authority.

