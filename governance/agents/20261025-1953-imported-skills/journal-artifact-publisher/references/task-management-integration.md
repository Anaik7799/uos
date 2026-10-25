# Task Management Integration Reference

Use this when a journal bundle claims full integration with `sa-plan`, planning, workflow, schedule, or task-management systems.

## Required Evidence Map

| Surface | Commands | Required Recording |
|---|---|---|
| Task lifecycle | `add`, `update`, `status`, `sync` | task ID, URN, priority, status, success/failure |
| Todo artifact | `sync`, `PROJECT_TODOLIST.md` status | synced, blocked, or not touched |
| Knowledge ingestion | `ingest-docs --dry-run`, optional `ingest-docs` | processed files, holons, STAMP refs, errors |
| Recall/search | `zk-recall`, `knowledge-search`, `count-citations` | query, result count, failures |
| Workflow | `workflow-list`, `workflow-start`, `workflow-describe`, `workflow-executions` | workflow id/run id/state when relevant |
| Scheduler/jobs | `schedule-list`, `job-list`, `queue-list`, `scheduler-tick` | schedule/job/queue state when relevant |
| Recommendation/session | `recommend`, `session-summary` | recommendation/session id when relevant |
| Email | `send-email` | recipient, subject, attachments, sent/blocked status |

## Degraded Mode

If `sa-plan` fails:

1. Stop mutation attempts after the first read/status failure unless the operator explicitly requests repair.
2. Record command, timestamp, and exact error.
3. Preserve historical task evidence separately from current-pass evidence.
4. Do not claim current sync, current completion, current ingestion, or current email dispatch.
5. Keep static artifacts valid and stageable if local checks pass.

## Planner Repair Handoff

When planner access is blocked, include next actions:

- inspect wrapper target and nested daemon state;
- verify planner DB path and permissions;
- run `./sa-plan status`;
- run `./sa-plan sync`;
- run `./sa-plan ingest-docs --dry-run`;
- send closure email with attachments once `send-email` is available.

## Manifest Fields

Add or update:

- `sa_plan.current_status_recheck`;
- `sa_plan.current_sync_recheck`;
- `plan_task_management_surfaces`;
- `validation.sa_plan_status_current_pass`;
- `validation.current_pass_blockers`;
- `next_actions`.
