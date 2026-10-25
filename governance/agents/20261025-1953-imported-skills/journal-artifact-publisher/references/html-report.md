# HTML Report Reference

Use this when drafting `*-analysis.html` and `*-index.html`.

## Common Requirements

- Self-contained HTML with inline CSS.
- No remote JavaScript, remote CSS, or external fonts.
- Works from local disk when opened directly.
- Use relative `href` links for same-bundle artifacts.
- Include file paths in `<code>` blocks.
- Include task ID, task URN, status, and validation state above the fold.

## Analysis Report Sections

1. Executive summary.
2. Bundle inventory.
3. Task-management evidence.
4. Link validation matrix.
5. Work performed.
6. Risk register.
7. Next actions.

## Handoff Index Sections

1. Bundle navigation cards.
2. Local verification commands.
3. Route status.
4. sa-plan status/sync/ingest status.
5. Git staging state.
6. Email/send status.

## Route Status Values

- `verified`: checked in the current pass and returned success.
- `expected`: route is structurally correct but not checked.
- `unavailable`: route was checked and failed, with failure reason recorded.
- `local-only`: artifact exists and relative links work, but no server route is claimed.
