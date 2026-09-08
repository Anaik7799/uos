# 20260908-0045 — GUI, TUI, design and testing skill index

Task stamp observed at 2026-09-08T00:27:45Z. #fractal-l0 #fractal-l2 #fractal-l4 #fractal-l7 #fractal-l9 #zk-adr #zero-muda

[Candidate file](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260908-0045-gui-tui-skills-rules-and-superpowers.md) · [Current homeostasis contract](http://nas-1.tail55d152.ts.net:4100/docs/design/20260908-0045-homeostasis-interface-specification.md)

These are repository-contained guidance and candidate code. FQDN publication and activation by other agent sessions are not asserted.

## Default skills

| Need | Repository skill | What to use it for |
|---|---|---|
| GUI design and implementation | [uos-gui-design](../../plugins/uos-interface-quality/skills/uos-gui-design/SKILL.md) | Operator hierarchy, Lustre semantics, accessible controls, responsive layout, truthful observations |
| TUI design and implementation | [uos-tui-design](../../plugins/uos-interface-quality/skills/uos-tui-design/SKILL.md) | Terminal layout/input, plain output, cell width, escape safety, lifecycle and evidence |
| Design/testing process | [uos-ui-superpowers](../../plugins/uos-interface-quality/skills/uos-ui-superpowers/SKILL.md) | Scoped design, regression-first debugging, risk ordering, evidence before completion |
| GUI framework detail | [.codex/skills/lustre-gleam-ui-expert](../../.codex/skills/lustre-gleam-ui-expert/SKILL.md) | Lustre/OTP conventions; adapt inherited external paths before use |
| Responsive behavior | [.codex/skills/mobile-first-adaptive-ui](../../.codex/skills/mobile-first-adaptive-ui/SKILL.md) | Reflow, density, pointer/keyboard/touch adaptation |
| UI/report quality | [.codex/skills/ui-report-quality](../../.codex/skills/ui-report-quality/SKILL.md) | Information quality, provenance, report review |
| Browser evidence | [.codex/skills/ocaml-playwright-control](../../.codex/skills/ocaml-playwright-control/SKILL.md) | Bounded OCaml browser control; this change's checks are under tools/validation |
| Gleam fundamentals | [.codex/skills/gleam-expert](../../.codex/skills/gleam-expert/SKILL.md) | Types, total updates, explicit effects and OTP boundaries |

The first three have local relative discovery links under .agents, .codex, .claude and .gemini. The package does not depend on a global plugin installation. The remaining skills are optional existing resources, subject to the current task scope and UOS policy.

## Applicable rules

The authoritative local UI rule set is [UOS-UI-QUALITY-001](../../plugins/uos-interface-quality/references/20260907-2312-interface-rules.md).

| Rule | Required behavior |
|---|---|
| UI-R01 | Attribute observations; distinguish source UTC, receiver time, model time and freshness bounds. |
| UI-R02 | Show observed, simulated, stale and unavailable distinctly. Unknown is not healthy. |
| UI-R03 | Controls emit reviewable requests; only an authorized executor receipt confirms a real effect. |
| UI-R04 | GUI, TUI and API consume the same typed field projection. |
| UI-R05 | Reject stale/out-of-order observations; do not invent replay IDs or Lamport guarantees. |
| UI-R06 | Bound frame size, row history, timers, refresh work and subscription lifetime. |
| GUI | Semantic labels, keyboard/focus, reflow, readable contrast, named SSE listeners, text-only payload rendering. |
| TUI | Explicit plain/ASCII fallback, bounded lines, escaped control bytes, documented entrypoint and terminal lifecycle. |
| Data modes | Real reads observed runtime counters; test scenarios are deterministic and cannot claim peer contact or deployment. |
| Validation | Cover schema/model, HTTP transport, browser behavior, PTY output and candidate provenance separately. |
| Repository | Standalone JJ; scoped Sa-plan claim; timestamped docs; 13-section journal; ASCII plus Mermaid for new explanatory diagrams. |

Use WCAG 2.2 and ARIA patterns as design references, not as an automatic compliance badge: [W3C WCAG](https://www.w3.org/TR/2024/REC-WCAG22-20241212/), [ARIA APG](https://www.w3.org/WAI/ARIA/apg/). Named SSE behavior follows [WHATWG EventSource](https://html.spec.whatwg.org/multipage/server-sent-events.html). Terminal fallback references are pinned in the package's primary-source manifest.

## Superpowers workflow

| Capability | Local skill | When |
|---|---|---|
| Brainstorming | [.codex/skills/brainstorming](../../.codex/skills/brainstorming/SKILL.md) | Resolve interaction/state choices before new design |
| Writing plans | [.codex/skills/writing-plans](../../.codex/skills/writing-plans/SKILL.md) | Define bounded work, dependencies and acceptance |
| Systematic debugging | [.codex/skills/systematic-debugging](../../.codex/skills/systematic-debugging/SKILL.md) | Reproduce the actual fault before changing code |
| Regression-first testing | [.codex/skills/test-driven-development](../../.codex/skills/test-driven-development/SKILL.md) | Behavior/security defects; observe failure then repair |
| Executing plans | [.codex/skills/executing-plans](../../.codex/skills/executing-plans/SKILL.md) | Execute within the current Sa-plan authority |
| Review handling | [.codex/skills/receiving-code-review](../../.codex/skills/receiving-code-review/SKILL.md) | Verify findings and attach concrete receipts |
| Completion verification | [.codex/skills/verification-before-completion](../../.codex/skills/verification-before-completion/SKILL.md) | Bind commands/results to candidate source |
| Isolated work | [.codex/skills/using-jj-workspaces](../../.codex/skills/using-jj-workspaces/SKILL.md) | Protect parallel development and live processes |

The scoped uos-ui-superpowers skill is the default composition. Imported worktree/delegation/approval guidance cannot override JJ, this side-conversation boundary, or the user's existing authorization. No peer-agent or subagent invocation occurred here.

## Executable checks

- `bash tools/ui-skill-check --selftest`: package/discovery/catalog validation and negative fixtures.
- `bash tools/homeostasis-ui-check --unit`: isolated OTP 29 compile and focused model/interface tests.
- `bash tools/homeostasis-ui-check --browser`: the same checks plus private HTTP/browser behavior.
- `tools/validation/homeostasis_recording_check.ml`: 30 verified update cycles per page/component recording.
- `apps/cepaf_gleam/test/homeostasis_algebra_test.gleam`: generation/history, deterministic scenarios, mode isolation and cross-surface field denotation.

Prerequisites are standard toolchains and prepared Gleam dependencies; none of these checks install global software, dispatch agents or deploy the candidate.

<details><summary>Verification: 5 domains / 18 checkpoints</summary>

| Domain | Checkpoints and current scope |
|---|---|
| Metadata/time/navigation | CHK-01 observed host time; CHK-02 FQDN references, publication UNVERIFIED; CHK-03 fractal tags; CHK-04 local specification/knowledge links |
| Purity/storage | CHK-05 no new foreign runtime; CHK-06 native boundaries unchanged; CHK-07 storage interlock UNRUN |
| Tests/mathematics | CHK-08 full C1–C8 UNRUN; CHK-09 bounded algebraic tests only; CHK-10 nine modalities UNRUN; CHK-11 candidate UI checks in attached receipt |
| Control/observability | CHK-12 private OTP 29 run; CHK-13 independent formal proof UNRUN; CHK-14 ZigVM UNRUN; CHK-15 MAX UNRUN; CHK-16 source timestamps and SSE tested, full OTel correlation UNRUN |
| Governance/JJ | CHK-17 independent admission UNRUN; CHK-18 isolated JJ candidate, no mainline cutover |

</details>

