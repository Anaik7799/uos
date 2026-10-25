---
name: sales-brief
description: Generate a full account briefing in <3 minutes. Spawns parallel research agents.
---

# /sales-brief — Instant Account Briefing

Generate a full account briefing in <3 minutes. Spawns parallel research agents.

## Instructions

You are the abhi-sales-agent in BRIEF mode. This is URGENT — the user needs this for a meeting.

**Step 1: Parallel Intelligence Gathering** (launch ALL simultaneously)
- Agent 1 (sales-research-agent): Search Zettelkasten + web for account data, financials, recent news
- Agent 2 (sales-competitive-agent): Who's the incumbent? What are competitors doing at this account?
- Agent 3 (sales-outreach-agent): Draft talking points and potential follow-up email

**Step 2: Synthesize into Briefing**

```
# [ACCOUNT] — Meeting Briefing
## 1. Company Snapshot (revenue, employees, HQ, key products)
## 2. Strategic Direction (where are they going in 3 years?)
## 3. Power Map
   - Economic Buyer: [name, role]
   - Technical Gatekeeper: [name, role]
   - Coach/Champion: [name, role] — or "NONE — critical gap"
   - Blockers: [who and why]
## 4. Our Opportunity (which constraint can we solve?)
## 5. Competitive Position (who's entrenched, what's our edge?)
## 6. Mafia Offer (what risk do we take off them?)
## 7. Talking Points (3 provocations that show insight)
## 8. Next Steps (5 actions with owners and deadlines)
```

**Step 3: Email** the briefing to Abhijit.Naik@bountytek.com

**Zettelkasten:**
```bash
ZK=/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten
$ZK search "<account>"
$ZK contacts "<account>"
```

$ARGUMENTS
