# sa-plan Publication Workflow

All commands run from `/home/an/dev/ver/c3i`.

## Task Lifecycle

```bash
./sa-plan add "<bundle title>" P1
./sa-plan update <task-id> in_progress
./sa-plan status
./sa-plan sync
```

After artifacts are complete and validated:

```bash
./sa-plan update <task-id> completed
./sa-plan status
./sa-plan sync
```

If any command fails, capture:

- command;
- timestamp;
- exit status;
- stderr/stdout summary;
- impact on task state;
- whether historical task evidence already exists.

Do not mark the task gate green when the current command failed.

## Knowledge Ingestion

Dry-run first:

```bash
./sa-plan ingest-docs --dry-run
```

Durable ingestion when requested:

```bash
./sa-plan ingest-docs
```

If route/task service or database access fails, leave ingestion status as `blocked_current_pass` and preserve any historical evidence separately.

## Planning/Workflow Evidence

When the bundle summarizes plan, task, workflow, or scheduler work, capture whichever commands are applicable:

```bash
./sa-plan workflow-list
./sa-plan workflow-describe <workflow-id>
./sa-plan schedule-list
./sa-plan job-list
./sa-plan queue-list
./sa-plan recommend
./sa-plan session-summary
```

## Email

Create the email body file first. Send only with an explicit recipient:

```bash
./sa-plan send-email \
  --to "<recipient>" \
  --subject "<subject>" \
  --body "$(cat docs/journal/<slug>-email.md)" \
  -a docs/journal/<slug>-journal.md \
  -a docs/journal/<slug>-analysis.html \
  -a docs/journal/<slug>-deck.html \
  -a docs/journal/<slug>-index.html \
  -a docs/journal/task-<id>-links.json
```

## Google Drive

```bash
./sa-plan gdrive-upload --folder c3i \
  --file docs/journal/<slug>-journal.md \
  --file docs/journal/<slug>-analysis.html \
  --file docs/journal/<slug>-deck.html \
  --file docs/journal/<slug>-email.md \
  --file docs/journal/<slug>-index.html \
  --file docs/journal/task-<id>-links.json
```

Only upload when explicitly requested. If the operator says to skip GDrive, record `gdrive_skipped=true`.

## Link Validation

Validate local files deterministically:

```bash
jq empty docs/journal/task-<id>-links.json
for f in docs/journal/<slug>-journal.md docs/journal/<slug>-analysis.html docs/journal/<slug>-deck.html docs/journal/<slug>-email.md docs/journal/task-<id>-links.json; do
  test -f "$f" || exit 1
done
```

Also validate the handoff index:

```bash
test -f docs/journal/<slug>-index.html
```
