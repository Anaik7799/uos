# Email Payload Reference

Use this when drafting `*-email.md` or preparing `sa-plan send-email`.

## Required Fields

- Subject.
- To: explicit recipient or placeholder.
- Date/timezone.
- sa-plan task ID and URN.
- Handoff index path/URL.
- Attachments list.
- Executive summary.
- Verification evidence.
- Risks/gaps.
- Action requested.
- Send command.

## Attachments

Attach at minimum:

- `*-journal.md`
- `*-analysis.html`
- `*-deck.html`
- `*-index.html`
- `task-<id>-links.json`

If a higher-priority local rule requires the journal itself as an attachment, include it even if the body repeats the summary.

## Send Gate

Send only when:

- a concrete recipient is explicit in the user request; or
- a higher-priority local notification rule names the recipient; and
- `sa-plan send-email` is available.

If send fails, record the exact failure in the journal and links manifest.

## Command Template

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
