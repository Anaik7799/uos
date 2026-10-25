# Journal Artifact Contract

## Naming

Use one stable slug per bundle:

```text
YYYYMMDD-<topic-slug>-journal.md
YYYYMMDD-<topic-slug>-analysis.html
YYYYMMDD-<topic-slug>-deck.html
YYYYMMDD-<topic-slug>-email.md
task-<sa-plan-task-id>-links.json
```

Add an operator handoff index for closure/dissemination packets:

```text
YYYYMMDD-<topic-slug>-index.html
```

If a task-local directory is used, prefer:

```text
docs/journal/task-<id>/journal.md
docs/journal/task-<id>/analysis.html
docs/journal/task-<id>/deck.html
docs/journal/task-<id>/email.md
docs/journal/task-<id>/index.html
docs/journal/task-<id>/links.json
```

## Journal Sections

Use the existing `journal-protocol` 13-section structure unless the operator requests a shorter incident log:

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

## HTML Report

HTML must be self-contained:

- inline CSS;
- no remote JavaScript;
- no external fonts required;
- local paths shown as code;
- task ID and commit evidence visible above the fold;
- risk register and next actions included.

## Operator Handoff Index

The index HTML must:

- link every bundle artifact with relative `href` values so local file browsing works;
- include task ID, task URN, status, route validation state, and staging/commit state;
- include a "how to verify" command block;
- include a note when route serving or sa-plan is unavailable;
- avoid remote JavaScript, remote fonts, and remote CSS.

## Slide Deck

Deck HTML must:

- be scrollable without JS;
- contain 8-14 slides for operator review;
- include closure state, dirty-state counts, risk register, and next actions;
- include the task ID and bundle slug.

## Email

Email artifact must include:

- subject;
- intended recipient or placeholder;
- attachment list;
- handoff index attachment and URL/path;
- concise executive summary;
- verification evidence;
- action requested;
- sa-plan send command when recipient is known.

## Links Manifest

The links manifest must include:

- `task_id`;
- `task_urn`;
- `title`;
- `date`;
- `operator`;
- `priority`;
- `status`;
- `tailscale_base_https`;
- `customer_base_https`;
- `localhost_base_http`;
- `local_base`;
- `artifacts` with local paths and expected HTTPS URLs;
- `sa_plan` commands used or expected;
- `validation` results.

Artifact entries should include `path`, `relative_href`, `localhost_url`, `customer_url`, `internal_url`, `exists_local`, and `route_status`.
