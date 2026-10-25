---
name: fy27-log
description: "Log an activity for \"$ARGUMENTS\":"
---

# FY27 Activity Log -- Record any activity to Zettelkasten

Log an activity for "$ARGUMENTS":

## Parse the Activity
From the user's input, extract:
- **Category**: meeting | email | linkedin | call | deal | contact | task | decision | intel | note | proposal | event | internal | escalation
- **Account**: Which OEM/customer (if applicable)
- **Contacts**: People involved (verify in ZK)
- **Summary**: What happened
- **Outcome**: Result
- **Follow-up**: Next action with due date

## Write to Activity Log

Append to the daily activity log file at:
`/home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/activities/YYYY-MM-DD-activity-log.md`

If the file doesn't exist yet, create with header:
`# Activity Log -- YYYY-MM-DD`

Then append:

### HH:MM -- [CATEGORY] Title
- **Account**: account name
- **Contacts**: names (from ZK or user input)
- **Action**: what happened
- **Outcome**: result or status
- **Follow-up**: next action, due date, owner
- **Tags**: category, account, relevant keywords

## For Meetings -- Create Dedicated Meeting Note

If category is `meeting`, also create a dedicated file at:
`/home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/activities/meetings/YYYY-MM-DD-account-topic.md`

With structure: Date, Attendees, Type, Agenda, Key Discussion Points, Decisions Made, Action Items table, Competitive Intelligence, Next Steps, Raw Notes.

## For Decisions -- Create Decision Record

If category is `decision`, also create at:
`/home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/activities/decisions/YYYY-MM-DD-topic.md`

With structure: Context, Options Considered table (Pros/Cons/Risk), Decision rationale, Impact, Review Date.

## Post-Log Actions
After writing the activity:
1. Confirm entry written with file path
2. Run FY27-ZK import if possible: `cd /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten && /home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten import ..`
3. Run C3I-ZK ingest via MCP: knowledge_ingest
4. If there are follow-up tasks, suggest creating them
