# Source Prompt Provenance

The authoritative user-authored prompt transcript is
[`source-prompt.jsonl`](source-prompt.jsonl). It contains the five consecutive
Codex history records that define this skill and its final scope.

Extraction source: `/home/an/.codex/history.jsonl`, records at file lines
404-408 as observed on 2026-08-03. The committed artifact is 76,108 bytes,
including one newline after each complete record.

The JSONL file is intentionally preserved as raw source rather than normalized
Markdown. Each line retains the original `session_id`, timestamp, JSON escaping,
Unicode, whitespace, spelling, repetition, and complete `text` field. The five
records preserve, in order:

1. the full InfraNodus, OCaml, Playwright, journal, ontology, and
   Algebra-Driven OCaml Doctrine request;
2. the request to make the doctrine a skill;
3. the expansion across every fractal layer, system component, STPA, Rete-UL,
   Stan, ruliology, harness, skill, agent, and artifact surface;
4. the expansion across structure, control/data/evidence planes, system quality,
   distributed and functional criteria, actor/Zenoh messaging, observability,
   debugging, and tracing;
5. the instruction to perform another pass, include the prompt, and lose no
   information.

Treat `source-prompt.jsonl` as immutable provenance. Do not hand-edit, reflow,
deduplicate, spell-correct, or replace it with a summary. Operational documents
may derive concise requirements from it, but must link back here and disclose
any interpretation or assumption.

## Integrity Law

`PROMPT-ROUNDTRIP`: selecting the five source records from the local Codex
history and concatenating each complete JSON line plus its newline yields bytes
identical to `source-prompt.jsonl`.

The journal records the extraction source, record range, byte count, and the
verification result. Hidden model reasoning is not part of this transcript;
the artifact preserves the complete user-authored prompt records available in
the session history.
