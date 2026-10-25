---
name: learn-rule
description: "When Claude discovers a pattern or anti-pattern during work, create a new rule:"
---

# Learn Rule — Create a new rule from session findings

When Claude discovers a pattern or anti-pattern during work, create a new rule:

1. Identify the pattern: What happened? What was the root cause?
2. Classify: Is this a PATTERN (repeat) or ANTI-PATTERN (avoid)?
3. Create the rule file at `.claude/rules/<name>.md` with:
   - STAMP constraint ID
   - Severity
   - What to do / what NOT to do
   - Why (the incident that created this rule)
4. Ingest to Zettelkasten: `sa-plan-daemon ingest-docs`

Pattern: "$ARGUMENTS"

This is SC-ZK-CLAUDE-005: Claude MUST create rules from session learnings.
The system literally gets smarter with each session.
