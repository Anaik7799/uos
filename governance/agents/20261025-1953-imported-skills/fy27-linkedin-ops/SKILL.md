---
name: fy27-linkedin-ops
description: Automate LinkedIn interactions for FY27 semiconductor sales prospecting via Playwright browser automation. All operations are rate-limited, session-managed, and logged to the FY27 Zettelkasten.
---

# FY27 LinkedIn Operations Command

## Purpose
Automate LinkedIn interactions for FY27 semiconductor sales prospecting via Playwright browser automation. All operations are rate-limited, session-managed, and logged to the FY27 Zettelkasten.

## Prerequisites
- Playwright installed: `npx playwright install chromium`
- LinkedIn session cookie or credentials in Smriti.db secrets
- ZK binary: `/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten`
- ZK dir: `/home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten`

## Rate Limits (ENFORCED — SC-FY27-LI-001)

| Operation | Daily Limit | Cooldown | Notes |
|-----------|-------------|----------|-------|
| Profile views | 50 | 2s between views | Includes Sales Nav |
| Connection requests | 25 | 5s between sends | With personalized note |
| Messages | 50 | 3s between sends | InMail counted separately |
| Search queries | 100 | 1s between queries | |
| Post engagements | 30 | 10s between actions | Likes + comments |
| Company views | 75 | 1s between views | |

## Operations

### 1. login
Authenticate LinkedIn session via Playwright. User MUST enter password manually — agent NEVER handles credentials.

```bash
# Usage
npx playwright codegen --target javascript \
  --output /tmp/li-session.js \
  https://linkedin.com/login

# Session storage
# After manual login, save cookies:
# Browser -> DevTools -> Application -> Cookies -> linkedin.com
# Store li_at cookie value in Smriti.db:
./sub-projects/c3i/target/release/sa-plan-daemon secrets set LI_SESSION_COOKIE "<value>"
```

**Authentication flow:**
1. Agent opens Chromium browser to linkedin.com/login
2. Agent pre-fills email from Smriti secrets
3. HUMAN enters password (agent NEVER touches password field)
4. HUMAN completes any 2FA/CAPTCHA
5. Agent detects successful login (presence of feed URL)
6. Agent extracts and stores `li_at` cookie to Smriti.db
7. Session valid ~30 days; check expiry before each operation

### 2. search-people
Search LinkedIn for people matching semiconductor sales criteria.

```bash
# Search parameters
# --query: Search string (name, title, keywords)
# --company: Filter by company
# --location: Filter by location (e.g., "Sweden", "Finland")
# --title: Filter by job title keywords
# --limit: Max results (default 20, max 100)

# Example: ARM decision makers in Nordic region
# Playwright selectors for people search:
# URL: https://www.linkedin.com/search/results/people/?keywords=<query>&filters=...
# Results container: .search-results-container
# Profile cards: .entity-result__item
# Name: .entity-result__title-text a
# Title: .entity-result__primary-subtitle
# Location: .entity-result__secondary-subtitle
```

**Post-search ZK logging:**
```bash
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten \
  ingest \
  --dir /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten \
  --title "LinkedIn Search: <query> — $(date +%Y-%m-%d)" \
  --content "Query: <query>\nResults: <count>\nFilters: <filters>\nTop prospects: <names>" \
  --tags "linkedin,search,prospecting,fy27"
```

### 3. search-company
Search for a specific company and extract employee list/key contacts.

```bash
# URL pattern: https://www.linkedin.com/company/<company-slug>/people/
# Playwright selectors:
# Company header: .org-top-card-summary__title
# Employee count: .org-top-card-summary-info-list__info-item
# People tab: button[aria-label*="People"]
# Employee cards: .org-people-profile-card
# Name: .org-people-profile-card__profile-title
# Role: .org-people-profile-card__profile-info
```

**Target companies for FY27:**
- arm-holdings (ARM)
- nokia (Nokia)
- ericsson (Ericsson)
- infinera (Infinera)
- microchip-technology (Microchip Technology)
- nxp-semiconductors (NXP)
- st-microelectronics (STMicroelectronics)

### 4. view-profile
View a LinkedIn profile and extract structured data.

```bash
# URL pattern: https://www.linkedin.com/in/<profile-slug>/
# Playwright selectors:
# Name: h1.text-heading-xlarge
# Title: .text-body-medium.break-words (first)
# Company: .pv-text-details__right-panel .hoverable-link-text
# Location: .text-body-small.inline.t-black--light.break-words
# About: #about ~ div .visually-hidden
# Experience: #experience ~ div .pvs-list__item--line-separated
# Education: #education ~ div .pvs-list__item--line-separated
# Skills: #skills ~ div .pvs-list__item
# Connections: .pv-top-card--list-bullet li:first-child
```

**Rate limiting enforcement:**
```javascript
// Between each profile view, enforce 2s minimum delay
await page.waitForTimeout(2000 + Math.random() * 1000);
// Track daily count in /tmp/li-daily-counts.json
const counts = JSON.parse(fs.readFileSync('/tmp/li-daily-counts.json'));
if (counts.profile_views >= 50) {
  throw new Error('Daily profile view limit reached (50). Resume tomorrow.');
}
```

**Profile data → ZK:**
```bash
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten \
  ingest \
  --dir /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten \
  --title "LinkedIn Profile: <name> — <company>" \
  --content "<extracted profile data as markdown>" \
  --tags "linkedin,profile,<company-tag>,fy27"
```

### 5. send-message
Send a LinkedIn message to a first-degree connection.

```bash
# Navigate to messaging
# URL: https://www.linkedin.com/messaging/compose/?recipient=<profile-id>
# Playwright selectors:
# Message input: .msg-form__contenteditable
# Send button: .msg-form__send-button

# SAFETY: Message must be reviewed by human before sending
# Agent composes draft, presents to user, user confirms before send

# Template variables:
# {{first_name}} - recipient's first name
# {{company}} - their company
# {{my_name}} - sender name from Smriti
# {{context}} - why reaching out (product/service context)
```

**Message templates (FY27 semiconductor context):**
```
Template 1 — Initial outreach:
"Hi {{first_name}}, I noticed your work at {{company}} on verification/semiconductor IP.
At Bountytek we're helping teams like yours accelerate {{context}}. Would you be open
to a 20-min call this week? Best, Abhijit"

Template 2 — Follow-up after connection:
"Hi {{first_name}}, thanks for connecting. I'd love to learn more about {{company}}'s
current challenges with {{context}}. Are you available for a brief call? Best, Abhijit"
```

**Daily limit enforcement:** 50 messages/day. Agent halts and logs warning at 45 (buffer for manual sends).

### 6. send-connection
Send a connection request with personalized note.

```bash
# Playwright selectors:
# Connect button: button[aria-label*="Connect"]
# Add note button: button[aria-label="Add a note"]
# Note textarea: #custom-message
# Send button: button[aria-label="Send invitation"]

# Connection note (300 char max):
# "Hi {{first_name}}, I work with semiconductor teams on {{context}}.
#  Your background at {{company}} caught my eye. Would love to connect. — Abhijit"
```

**Daily limit:** 25/day. Requests exceeding limit queued to next day in ZK.

**Queue format:**
```bash
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten \
  ingest \
  --dir /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten \
  --title "Connection Queue: $(date +%Y-%m-%d)" \
  --content "Queued connections:\n- <name> (<url>)\n- <name> (<url>)" \
  --tags "linkedin,connection-queue,fy27"
```

### 7. export-connections
Export all LinkedIn connections to CSV for CRM import.

```bash
# LinkedIn native export (recommended — most complete):
# Settings & Privacy -> Data Privacy -> Get a copy of your data
# Select "Connections" -> Request archive
# Download ZIP -> extract Connections.csv

# Playwright automation for export request:
# URL: https://www.linkedin.com/mypreferences/d/data-download
# Selector: input[value="CONNECTIONS"] (checkbox)
# Request button: button.download-btn

# CSV output location:
# /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/exports/linkedin-connections-$(date +%Y%m%d).csv

# Post-export: ingest summary to ZK
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten \
  ingest \
  --dir /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten \
  --title "LinkedIn Connections Export — $(date +%Y-%m-%d)" \
  --content "Export file: linkedin-connections-$(date +%Y%m%d).csv\nTotal: <count>\nNew since last export: <delta>" \
  --tags "linkedin,export,connections,fy27"
```

**CSV schema (LinkedIn native export):**
```
First Name, Last Name, Email Address, Company, Position, Connected On, Profile URL
```

### 8. check-notifications
Check LinkedIn notifications for engagement signals (profile views, connection accepts, message replies).

```bash
# URL: https://www.linkedin.com/notifications/
# Playwright selectors:
# Notification list: .nt-card-list
# Individual notification: .nt-card
# Notification type: .nt-card__text
# Time: .nt-card__time-ago

# Signal types to capture:
# - Profile viewed my profile → warm prospect
# - Accepted my connection → ready for message
# - Replied to message → active conversation
# - Commented on my post → engagement signal
# - Job change at target company → trigger event
```

**Signal → action mapping:**
| Signal | Action | Priority |
|--------|--------|----------|
| Profile view from target company | Send connection request | High |
| Connection accepted | Send intro message within 24h | High |
| Message reply | Respond within 2h | Critical |
| Job change at target | Update CRM contact | Medium |
| Post comment | Like + reply | Medium |

### 9. post-engagement
Engage with posts from target contacts/companies (like, comment, share).

```bash
# URL: https://www.linkedin.com/feed/
# Target accounts feed: https://www.linkedin.com/in/<profile>/recent-activity/
# Playwright selectors:
# Post container: .feed-shared-update-v2
# Like button: button[aria-label*="React Like"]
# Comment button: button[aria-label*="Comment"]
# Comment input: .ql-editor[role="textbox"]
# Post button: .comments-comment-box__submit-button

# Engagement rules:
# - Like: technical/business posts from target contacts
# - Comment: add value (insight, question) — 2-3 sentences max
# - Share: only if directly relevant to semiconductor/verification
```

**Engagement rate limits:** 30 total/day (likes + comments combined). Comments limited to 10/day (quality over quantity).

### 10. sales-nav-search
Quick Sales Navigator search accessible from this command (redirects to fy27-salesnav-ops for full capabilities).

```bash
# Quick access URL:
# https://www.linkedin.com/sales/search/people?query=<encoded-query>

# For full Sales Navigator operations, use:
# .claude/commands/fy27-salesnav-ops.md

# Pre-built searches available:
# ARM-Decision-Makers, Nokia-5G-Leaders, Ericsson-Semicon,
# Infinera-Optical, EU-Semicon-VPs, EU-Verification-Leads
```

## Session Management

```javascript
// Playwright session template for all LinkedIn operations
const { chromium } = require('playwright');

async function getLinkedInPage() {
  const browser = await chromium.launch({
    headless: false,  // Always visible — LinkedIn detects headless
    slowMo: 100,      // Human-like timing
    args: ['--no-sandbox']
  });

  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    viewport: { width: 1280, height: 800 },
    locale: 'en-US',
    timezoneId: 'Europe/Stockholm'
  });

  // Restore session from Smriti secrets
  const liAt = process.env.LI_SESSION_COOKIE;
  if (liAt) {
    await context.addCookies([{
      name: 'li_at',
      value: liAt,
      domain: '.linkedin.com',
      path: '/',
      httpOnly: true,
      secure: true
    }]);
  }

  const page = await context.newPage();
  return { browser, context, page };
}
```

## Error Handling

| Error | Detection | Response |
|-------|-----------|----------|
| CAPTCHA challenge | Page contains `challenge` in URL | STOP immediately. Alert user. Log to ZK. Manual intervention required. |
| Account restricted | "Your account has been restricted" text | STOP all operations. Log to ZK. Email alert via sa-plan-daemon. |
| Rate limit warning | "You've reached the weekly limit" | STOP operation type. Log limit hit. Resume next day. |
| Login expired | Redirect to /login | Re-authenticate (user enters password). |
| Network error | Page load timeout > 30s | Retry 3x with exponential backoff. Log failure. |
| Selector not found | Element not found after 10s wait | Log page HTML snapshot. Skip item. Continue. |
| Bot detection | Unusual activity banner | STOP. Wait 24h. Log incident to ZK. |

## Post-Operation ZK Logging (Mandatory — SC-FY27-LI-007)

After every operation batch, log to Zettelkasten:

```bash
ZK_BIN=/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten
ZK_DIR=/home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten

${ZK_BIN} ingest \
  --dir "${ZK_DIR}" \
  --title "LinkedIn Ops Log — $(date +%Y-%m-%d %H:%M)" \
  --content "Operation: <op>\nTarget: <target>\nResult: <result>\nCount: <n>\nNotes: <notes>" \
  --tags "linkedin,ops-log,fy27,$(date +%Y-%m)"
```

## CSV Export Format

All exported data uses RFC 4180 CSV with UTF-8 BOM for Excel compatibility:

```
\xEF\xBB\xBF (UTF-8 BOM)
"First Name","Last Name","Email","Company","Title","LinkedIn URL","Connected Date","Notes"
"Jane","Smith","j.smith@arm.com","ARM","VP Engineering","https://linkedin.com/in/jsmith","2026-04-13",""
```

Export location: `/home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/exports/`
