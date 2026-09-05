# Quarantined stub reference traces — captured 2026-08-09, quarantined 2026-08-11

These 88 files are **not evidence**. They are kept because they are the
record of how a false-parity trap formed, and destroying the record while
keeping the lesson is the wrong trade. Nothing reads this directory.

## What they are

Each is a well-formed, correctly digested L4 reference trace, pinned at the
frozen snapshot `70b2efe9…` under a capability's name, whose entire payload
is the stub template:

```json
"scenario_id": "interactive_cli.repl_session",
"trace": { "messages": [ {"content": "stub for repl_session", "role": "user"} ],
           "model": "openai/gpt-5.4" }
```

They originate from `stub_slices.ml`, a one-shot migration that injected 88
placeholder scenarios into `capture_reference_traces.ml`. Those scenarios
were captured against the frozen reference and committed in `e2ffeb0`. The
migration itself was retired in `c484985`.

## Why they had to leave `reference_traces/`

A trace of this shape **cannot distinguish a correct implementation from no
implementation**. It exercises one-line generic request shaping — the path
`model_routing.provider_transports` already verified 9/9 — while carrying
the name of a capability it never touches. Any candidate reproduces it. A
receipt built on one grants capability credit that no scenario earned, which
is H-1 (false parity), and R14 names the shape: the **proven-not-differential
trap**.

Two consumers made that live rather than theoretical:

- `Parity_compare.agent_loop_scenarios` names seven of them, so every
  `compare_reference_traces` run compared a candidate against stub payloads
  and recorded seven receipts.
- `Parity_dashboard.count_fixtures` globs `reference_traces/` and counted
  every `.json`, so the dashboard reported **112 pinned reference traces**
  when the real corpus was **24** — the same 24 that back the 24/24
  differential receipts.

## What replaced them

Nothing. The 88 capability slices they were named for remain **unverified**,
which is the honest state and was always the honest state. Restoring them is
not a matter of moving files back: each slice needs scenarios authored by
probing the frozen reference for behaviour that actually distinguishes a
correct candidate from a wrong one.

## The guard

`Parity_compare.record` now refuses any comparison whose reference payload
begins with `stub for `, returning a Control-origin, credit-**blocking**
refusal (R5 — the harness's fixture corpus is at fault, never the candidate).
The guard is the durable protection; this quarantine is housekeeping. Both
are needed: the guard stops recurrence, the move stops the dashboard and the
agent_loop group from consuming these.

`test_parity_compare`'s stub-guard layer asserts, against the real corpus,
that every live fixture is clean and every quarantined one is flagged. If a
stub payload ever reappears under `reference_traces/`, that check fails.

Full account: `docs/hermes/journal/2026-08-11-stub-reference-traces.md`.
