# Journal Template Reference

Use this when drafting `*-journal.md`.

## Required Front Matter Block

Include at the top:

- title;
- date and timezone;
- operator directive;
- sa-plan task ID and URN;
- bundle slug;
- links manifest path;
- route validation status;
- staging/commit status.

## Required 13 Sections

1. Scope & Trigger
2. Pre-State Assessment
3. Execution Detail
4. Root Cause Analysis
5. Fix Taxonomy
6. Patterns & Anti-Patterns Discovered
7. Verification Matrix
8. Files Modified
9. Architectural Observations
10. Remaining Gaps
11. Metrics Summary
12. STAMP & Constitutional Alignment
13. Conclusion

## Detail Requirements

- Separate facts observed in the current pass from historical evidence.
- Include exact commands and outcomes for `git status`, `sa-plan`, link validation, and JSON validation.
- If a command fails because the daemon, DB, service route, DNS, or network is unavailable, record the failure as degraded evidence rather than silently skipping it.
- Use tables for file deltas, validation gates, risks, and next actions.
- Do not claim task completion, route liveness, email dispatch, durable ingestion, or git commit unless verified in the same pass or explicitly identified as historical evidence.

## Closure Paragraph

The conclusion must state:

- what is ready;
- what is staged or not staged;
- what is blocked;
- what the operator should do next.
