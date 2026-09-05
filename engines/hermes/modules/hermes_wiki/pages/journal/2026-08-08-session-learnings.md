# Session Learnings — 2026-08-08

The fractal learnings journal, seeded. Each entry is a thing that was
non-obvious, cost real effort, and changed the design — the *why* the git log
does not carry. Keyed to the hazard or rule it produced.

## L-01 — PYTHONPATH precedence (→ HZ-CAP-01, fixed ed407e0's predecessor)

`execve` getenv takes the FIRST of duplicate environment entries, so appending
the frozen `PYTHONPATH` after an inherited one let the inherited path win. A
trace from an unpinned reference could be recorded under the frozen digest.
Found by the fable max-mode review, reproduced with a probe. Fix: strip inherited
`PYTHONPATH`/`PYTHONHOME`/`PYTHONSTARTUP` rather than shadow them. Lesson:
appending to an inherited environment is not the same as controlling it.

## L-02 — normalizer int/float asymmetry (→ HZ-NRM, fixed 75edc99's predecessor)

`Float 1.0` rendered as `"1.0"` while `Int 1` stayed a number, so `{"x":1}` and
`{"x":1.0}` diverged on encoder tagging alone — and the code comment falsely
claimed they were already equal. Reference and candidate JSON encoders need not
agree on int-vs-float tagging, so this was a live false-divergence source.
Lesson: a comment asserting an invariant is not the invariant; test it.

## L-03 — immutable trace pair vs evolving candidate (→ fixed ed407e0)

`parity_trace_pair` was keyed by `(snapshot, scenario, trace_id)` and immutable
— correct for the frozen reference half, wrong for the candidate half, which
changes as the candidate is developed. Fixing a candidate gap produced a
different candidate trace that collided with the pinned divergent one; the
immutability guard rejected it and the corrected receipt silently failed to
record. Found by grepping the `record failed` stderr I had been discarding. Fix:
revision-scope the trace id. Lesson: immutability is right for what is frozen
and wrong for what evolves; do not key them the same. And a failure printed to
stderr while the run exits 0 is a hidden failure — it now fails the run.

## L-04 — generic-vs-OpenRouter profile boundary (→ corpus scoping, 81a3529)

The generic `ChatCompletionsTransport` IGNORES `reasoning_config` (it lives in a
provider profile) and passes `timeout` as a client param the candidate keeps
out of the body. Comparing the OpenRouter candidate's reasoning/extra_body
against the generic reference would manufacture divergences reflecting a
profile mismatch, not real candidate defects. Lesson: the oracle must be the
*right* reference profile; a fair differential test requires matching the
provider path, and scenarios that cannot be fairly compared are excluded, not
added as noise. Probed each scenario against the reference before adding it.

## L-05 — decode needs no SDK (→ normalize_response_adapter, 86e3c98)

`normalize_response` uses attribute access and `getattr`, so a provider response
can be presented to it as a recursive attribute view over the JSON, avoiding the
heavy `openai` dependency. The subtlety: the SDK exposes optional fields as
None, so a missing field must read as None — but pydantic `model_*` internals
must stay genuinely absent, because the reference probes them with `hasattr` and
returning None would change its branch. Lesson: a faithful shim mimics the
contract the code reads, including which absences are None and which are
AttributeError.

## L-06 — decode candidate gaps (→ frontier, next to close)

The candidate `Openrouter_transport.decode` reproduces content and tool calls
but lacks `usage.total_tokens` and the reference's refusal→content_filter
promotion. Surfaced as honest divergences (decode 2/4) rather than trimmed away,
because the comparison schema is the reference contract. Lesson: project to the
spec's schema, not the intersection; a field the candidate lacks must diverge.

## L-07 — ENOSPC on the shared tmpfs (→ resource-envelope preflight, implemented)

The 23 GB `/tmp` tmpfs reached 99% (mostly stale `zigvm-*` scratch from the
prior harness) and a test run died with ENOSPC — a resource used without being
checked. Worked around by pointing test `TMPDIR` at the 441 GB project disk.
This motivated the fractal resource-envelope preflight design
(`docs/hermes/specs/2026-08-08-fractal-resource-envelope-preflight.md`). Lesson:
the discipline that governs evidence — nothing used that was not checked,
absence fails closed — must extend to resources, with a margin of safety and an
absolute floor. Operational note: the `zigvm-*` dirs under `/tmp` are stale
scratch from the replaced harness and are safe to clear.

## L-08 — no statvfs, and the pure/IO split that made fail-closed testable (→ resource_envelope)

Building the preflight surfaced two things. First, OCaml's stdlib `Unix` has no
`statvfs` and `extunix` is not installed, so free space comes from `df -P -k`
run as a declared oracle (like `sha256sum`): its output is parsed and validated,
and any failure to read a positive figure is `Unknown`, never "available". `-P`
forces the portable one-line format; `-k` fixes the block size. Second — and the
load-bearing design decision — the module splits a pure `evaluate` (resource +
already-gathered fact → verdict) from the one IO function `observe` (which
catches everything and returns `Unknown`). That split is what let the margin and
floor be tested at their exact byte boundaries deterministically, while the
chaos layer drove the *real* environment (an exabyte need on the real disk, a
missing path, a read-only dir) and asserted each fails closed rather than
crashing. The floor earns its place independently of the margin: a small need
with a huge denominator passes the percentage but is refused by the absolute
512 MiB backstop — the case that a percentage alone waves through. Lesson: to
prove "fails closed under exhaustion", make the decision pure and the world a
value; then exhaustion is a test input, not an outage you have to stage.

## L-09 — the auto-yes destructive downgrade (→ toolchain-provisioning countermeasures)

Installing coq-iris into the EXISTING zigvm switch (judged "additive, low-risk")
combined three mistakes into one incident. (1) The install command piped opam's
output through `tail`, so the SOLVER PLAN — which included downgrading the
switch's pinned prover (rocq 9.1.1 → coq 8.19.1) and REMOVING rocq-stdlib — was
never seen before it ran. (2) `OPAMYES=1` auto-accepted that destructive plan.
(3) The target was another project's pinned toolchain: the zigvm harness's own
proof gate cites Rocq 9.1.1, so the "additive" install mutated a sibling
system's verified environment — exactly the cross-harness damage the R9/R14
boundary exists to prevent. Iris itself did not even land. Recovery: jidoka —
stop, `opam switch import` the automatic backup export (zigvm restored to
9.1.1), and provision iris in a FRESH side switch (`rocq-iris`), which is the
gospel-side-switch pattern the earlier session had already established and this
incident deviated from. Lessons, each a countermeasure: never combine OPAMYES
with a piped/truncated plan — dry-run (`--show-actions`) first when the switch
is not disposable; a "shared toolchain" install into another project's switch
is never additive if the solver may downgrade; and when a pattern exists
(side switch first), deviating from it needs a stated reason, not convenience.

## L-10 — a frozen function's stdout side-effect corrupts capture (adapter must guarantee pure stdout)

Capturing anthropic_adapter failed: the frozen `convert_tools_to_anthropic`
emits a `logger.warning` on a duplicate tool name, and in the capture
environment that handler writes to STDOUT — landing at byte 0 of the adapter's
reply and making the JSON unparseable. Two fixes that did NOT work, and why:
a stream-level `contextlib.redirect_stdout(sys.stderr)` failed because the
logging handler bound to the stdout stream OBJECT at import, before the redirect;
an `os.dup2(2, 1)` fd-level redirect failed too, because the message sat in a
TextIOWrapper buffer and flushed at process exit — AFTER fd 1 was restored — back
onto the real stdout. The fix that worked: `logging.disable(logging.CRITICAL)`
BEFORE importing the frozen module, so the warning never emits. This is faithful:
a log side-effect is not part of the trace, and the return value (which still
dedups) is unchanged. **Lesson / countermeasure:** an adapter's contract is PURE
JSON on stdout; a frozen function may print or log there. Disable logging before
the frozen import, and treat any non-JSON on stdout as an adapter bug to fix at
the source of the noise, never by loosening the parser. Watch for this in the
remaining adapters (codex/bedrock/gemini) — bedrock additionally may attempt a
network install at import (neutralize before capture).

## Standing method that worked

Probe the frozen reference directly before adding any scenario; implement the
candidate faithfully from the frozen source, never tuned to pass; let genuine
gaps surface as divergences; and treat a design review by an independent agent
(fable, max mode) as adversarial — its job is to find where H-1 still hides.
