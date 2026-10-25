---
name: fy27-salesnav-ops
description: "LinkedIn Sales Navigator automation for FY27 semiconductor sales: lead discovery, account mapping, InMail outreach, and buyer intent monitoring. Integrates with FY27 Zettelkasten for persistent prospect intelligence."
---

# FY27 Sales Navigator Operations Command

## Purpose
LinkedIn Sales Navigator automation for FY27 semiconductor sales: lead discovery, account mapping, InMail outreach, and buyer intent monitoring. Integrates with FY27 Zettelkasten for persistent prospect intelligence.

## Prerequisites
- LinkedIn Sales Navigator subscription (Team or Advanced)
- Playwright session from fy27-linkedin-ops `login` operation
- ZK binary: `/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten`
- ZK dir: `/home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten`
- Sales Navigator base URL: `https://www.linkedin.com/sales/`

## Rate Limits (ENFORCED — SC-FY27-LI-002)

| Operation | Daily Limit | Monthly Limit | Cooldown |
|-----------|-------------|---------------|----------|
| Lead profile views | 25 | 500 | 3s between views |
| Account views | 50 | 1000 | 2s between views |
| InMail sends | — | 20 | 5s between sends |
| Saved leads | 1000 total | — | — |
| Lead list exports | 10/day | 100 | — |
| Saved searches | Unlimited | — | — |
| Buyer intent views | Unlimited | — | 1s |

## Pre-Built Saved Searches

### ARM-Decision-Makers
```
URL parameters:
  keywords: "verification" OR "hardware" OR "IP licensing"
  title: "VP" OR "Director" OR "Head of" OR "CTO" OR "Principal"
  company: ARM (company ID: 7257)
  geography: Global (for initial; refine to EU for FY27 focus)
  seniority: Director, VP, C-level

Saved search name: FY27-ARM-Decision-Makers
Expected results: 150-400 leads
Update frequency: Weekly (Monday)
```

### Nokia-5G-Leaders
```
URL parameters:
  keywords: "5G" OR "semiconductor" OR "ASIC" OR "SoC" OR "RF"
  title: "VP" OR "Director" OR "Senior Manager" OR "Lead"
  company: Nokia (company ID: 1025)
  geography: Finland, Sweden, Germany, UK
  seniority: Senior IC, Manager, Director, VP

Saved search name: FY27-Nokia-5G-Leaders
Expected results: 200-600 leads
Update frequency: Weekly (Monday)
```

### Ericsson-Semicon
```
URL parameters:
  keywords: "ASIC" OR "chip design" OR "verification" OR "RTL" OR "semiconductor"
  title: "Engineer" OR "Architect" OR "Manager" OR "Director"
  company: Ericsson (company ID: 1430)
  geography: Sweden, Finland, USA
  department: Engineering, Research & Development

Saved search name: FY27-Ericsson-Semicon
Expected results: 300-800 leads
Update frequency: Bi-weekly
```

### Infinera-Optical
```
URL parameters:
  keywords: "optical" OR "photonics" OR "DSP" OR "semiconductor" OR "ASIC"
  title: "VP" OR "Director" OR "Manager" OR "Architect"
  company: Infinera (company ID: 13253)
  geography: USA, Sweden (Stockholm site)
  seniority: Manager+

Saved search name: FY27-Infinera-Optical
Expected results: 50-150 leads
Update frequency: Monthly
```

### EU-Semicon-VPs
```
URL parameters:
  keywords: "semiconductor" OR "chip" OR "VLSI" OR "ASIC" OR "verification"
  title: "VP" OR "Vice President" OR "SVP" OR "EVP"
  geography: European Union, Norway, Switzerland, UK
  industry: Semiconductors, Electronic Hardware, Telecommunications
  seniority: VP, C-level

Saved search name: FY27-EU-Semicon-VPs
Expected results: 400-1200 leads
Update frequency: Weekly (Friday — for Monday outreach)
```

### EU-Verification-Leads
```
URL parameters:
  keywords: "formal verification" OR "simulation" OR "UVM" OR "SystemVerilog"
            OR "hardware verification" OR "design verification" OR "DV"
  title: "Engineer" OR "Lead" OR "Manager" OR "Architect" OR "Director"
  geography: European Union, Norway, Sweden, Finland, UK
  seniority: Senior IC, Lead, Manager, Director

Saved search name: FY27-EU-Verification-Leads
Expected results: 500-1500 leads
Update frequency: Weekly (Wednesday)
```

## Operations

### 1. search-leads
Execute a lead search in Sales Navigator and capture results.

```bash
# Base URL: https://www.linkedin.com/sales/search/people
# With saved search: https://www.linkedin.com/sales/search/people?savedSearchId=<id>

# Playwright selectors:
# Search input: input[placeholder*="Search by name"]
# Filter panel: .search-filters-panel
# Title filter: input[aria-label*="Title"]
# Company filter: input[aria-label*="Current company"]
# Geography filter: input[aria-label*="Geography"]
# Results list: .artdeco-list
# Lead card: .artdeco-list__item
# Lead name: .actor-name
# Lead title: .subline-level-1
# Lead company: .subline-level-2
# Save lead button: button[aria-label*="Save"]

# Execute search and collect leads:
# 1. Navigate to saved search or build new search
# 2. Scroll through results (lazy loading)
# 3. Extract lead data (name, title, company, geography, mutual connections)
# 4. Save promising leads (see save-lead operation)
# 5. Export to CSV (see export-list operation)
```

**Post-search ZK log:**
```bash
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten \
  ingest \
  --dir /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten \
  --title "SalesNav Search: <search-name> — $(date +%Y-%m-%d)" \
  --content "Search: <name>\nResults: <count>\nNew leads: <n>\nTop prospects:\n<list>" \
  --tags "salesnav,search,leads,fy27,$(date +%Y-%m)"
```

### 2. search-accounts
Search for target companies in Sales Navigator.

```bash
# Base URL: https://www.linkedin.com/sales/search/company
# Playwright selectors:
# Account result: .account-result
# Company name: .result-lockup__name
# Industry: .result-lockup__highlight-keyword (industry tag)
# Employee count: .result-lockup__misc-item (employees)
# HQ location: .result-lockup__misc-item (location)
# Growth: .account-growth-icon

# Key account attributes to capture:
# - Company name and LinkedIn company ID
# - Industry (Semiconductors, Telecom Equipment, etc.)
# - Employee count (proxy for budget size)
# - HQ location (EU or global)
# - Recent hires in target roles (growth signal)
# - Technologies used (from job postings)
# - Decision maker count (from people search)
```

**Account intelligence schema for ZK:**
```markdown
# Account: <Company Name>
## Profile
- Industry: <industry>
- Employees: <count>
- HQ: <location>
- LinkedIn: <URL>

## Decision Makers (FY27 targets)
- <Name> (<Title>) — <LinkedIn URL>

## Intelligence
- Recent hires: <relevant roles>
- Job postings: <relevant open roles>
- Buyer intent signals: <signals>
- Last activity: <date>

## Opportunity
- Product fit: <product>
- Est. deal size: <range>
- Next action: <action>
```

### 3. view-lead
View a lead profile in Sales Navigator for enriched data.

```bash
# URL: https://www.linkedin.com/sales/lead/<lead-id>,NAME,<type>
# Playwright selectors:
# Lead name: h1.profile-topcard-person-entity__name
# Current title: .profile-topcard-person-entity__title
# Current company: .profile-topcard-person-entity__company-name
# Location: .profile-topcard-person-entity__location
# Mutual connections: .mutual-connections-count
# Shared experiences: .shared-experiences-count
# Buyer intent score: .lead-score-badge
# TeamLink connections: .teamlink-intro-count
# Recent activity: .lead-activity-section
# Notes: .notes-module-text
```

**Enriched data → ZK:**
```bash
ZK_BIN=/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten
${ZK_BIN} ingest \
  --dir /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten \
  --title "Lead Profile: <name> — <company>" \
  --content "<full lead profile markdown>" \
  --tags "salesnav,lead,<company-slug>,fy27"
```

### 4. save-lead
Save a lead to a Sales Navigator list.

```bash
# Playwright selectors:
# Save button: button[aria-label*="Save to list"]
# List selector: .list-picker-dropdown
# New list button: button[aria-label*="Create list"]
# List name input: input.list-name-input
# Confirm button: button[aria-label*="Save"]

# FY27 lead lists:
# - FY27-ARM-Targets (ARM decision makers)
# - FY27-Nokia-Targets (Nokia 5G team)
# - FY27-Ericsson-Targets (Ericsson semiconductor)
# - FY27-Infinera-Targets (Infinera optical)
# - FY27-EU-VPs (EU semiconductor VPs)
# - FY27-Active-Conversations (currently engaged)
# - FY27-Nurture (longer-term prospects)
```

### 5. view-list
View a saved lead list and check for updates/alerts.

```bash
# URL: https://www.linkedin.com/sales/lists/people/<list-id>
# Playwright selectors:
# List items: .lead-list-member
# Lead name: .lead-list-member-name
# Company: .lead-list-member-company
# Alert badge: .list-member-alert-badge
# Alert text: .list-member-alert-text

# Alert types to watch:
# - Job change (high priority — warm trigger event)
# - Posted on LinkedIn (engagement opportunity)
# - Mentioned in news (conversation starter)
# - Shared connections added (warm intro path)
# - Company news (account intelligence)
```

### 6. export-list
Export a Sales Navigator lead list to CSV.

```bash
# Sales Navigator native export:
# List page -> Actions -> Export (up to 1000 leads per export)

# Playwright automation:
# Selector: button[aria-label*="Export"] or .export-button
# Download: Listen for download event

# Output path:
# /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/exports/
# salesnav-<list-name>-$(date +%Y%m%d).csv

# RFC 4180 CSV format with UTF-8 BOM:
# Fields:
# "First Name","Last Name","Title","Company","Email (work)","Email (personal)",
# "Phone","LinkedIn URL","Location","Industry","Company Size","Seniority",
# "Saved Date","Last Activity","Notes"
```

**Post-export ZK log:**
```bash
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten \
  ingest \
  --dir /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten \
  --title "SalesNav Export: <list-name> — $(date +%Y-%m-%d)" \
  --content "List: <name>\nExported: <count> leads\nFile: <path>\nNew since last export: <delta>\nTop companies: <list>" \
  --tags "salesnav,export,leads,fy27,$(date +%Y-%m)"
```

### 7. check-alerts
Check Sales Navigator alerts for trigger events across all saved leads.

```bash
# URL: https://www.linkedin.com/sales/homepage
# Alerts section: .homepage-alerts
# Alert types:
# - Lead job change: highest priority (timing signal)
# - Lead shared content: engagement opportunity
# - Account news: account intelligence
# - Lead viewed your profile: warm signal
# - TeamLink path opened: intro opportunity

# Playwright selectors:
# Alert feed: .insights-feed
# Alert item: .insights-feed__item
# Alert type icon: .insights-feed__item-icon
# Lead name: .insights-feed__item-actor-name
# Alert description: .insights-feed__item-description
# Time: .insights-feed__item-time

# Alert → action matrix (see SC-FY27-LI-005):
# job_change + target_company → send connection + trigger email sequence
# profile_view → send connection request
# shared_content (relevant) → like + thoughtful comment
# account_news (funding/expansion) → prioritize account
```

**Alert digest → ZK:**
```bash
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten \
  ingest \
  --dir /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten \
  --title "SalesNav Alert Digest — $(date +%Y-%m-%d)" \
  --content "Date: $(date)\nTotal alerts: <n>\nJob changes: <n>\nHigh priority: <list>\nActions queued: <list>" \
  --tags "salesnav,alerts,trigger-events,fy27"
```

### 8. inmail
Send an InMail to a prospect (bypasses connection requirement).

```bash
# InMail budget: 20/month (Sales Navigator Team plan)
# Use InMail for: VP+ who are not connections, high-value prospects

# Playwright selectors:
# InMail button: button[aria-label*="Send InMail"] or button[aria-label*="Message"]
# Subject input: input[name="subject"] or .compose-subject-input
# Body input: .compose-message-input .ql-editor
# Send button: button[aria-label*="Send"]

# SAFETY: InMail requires human review before send
# Agent composes draft, presents preview, HUMAN confirms

# InMail templates (subject + body):
# Template 1 — VP of Engineering:
#   Subject: "Formal verification at <company> — quick question"
#   Body: 150-200 words, personalized to their role/company news

# Template 2 — CTO/CPO:
#   Subject: "Semiconductor verification for <product-area>"
#   Body: Business case focused, 100-150 words

# InMail best practices:
# - Subject: <10 words, specific to their context
# - Body: <200 words, mobile-readable
# - Include: specific observation about their work/company
# - CTA: specific time slot or low-friction next step
# - Send: Tuesday-Thursday, 8-10am their timezone
```

**InMail log → ZK:**
```bash
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten \
  ingest \
  --dir /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten \
  --title "InMail Sent: <name> — <company>" \
  --content "To: <name> (<title> at <company>)\nSubject: <subject>\nBody:\n<body>\nSent: $(date)\nTemplate: <template-id>\nInMail budget remaining: <n>/20" \
  --tags "salesnav,inmail,outreach,fy27,$(date +%Y-%m)"
```

### 9. account-map
Map the decision-making structure of a target account.

```bash
# URL: https://www.linkedin.com/sales/company/<company-id>/map
# Account map shows: org chart view, relationship scores, TeamLink paths

# Playwright selectors:
# Map container: .account-map-container
# Person node: .account-map-person
# Role label: .account-map-person-role
# Relationship score: .account-map-relationship-score
# Connection indicator: .account-map-connection-indicator

# Data to capture for each account:
# Tier 1 (Economic Buyer): CEO, CTO, CPO, SVP Engineering
# Tier 2 (Technical Buyer): VP Eng, Director of Engineering, Principal Architect
# Tier 3 (Champion): Senior Engineer, Lead, Manager (day-to-day contact)
# Tier 4 (Blocker): Procurement, Legal, IT Security

# Account map output format:
# org_structure.json → ZK holon per account
```

**Account map → ZK:**
```bash
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten \
  ingest \
  --dir /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten \
  --title "Account Map: <company> — $(date +%Y-%m-%d)" \
  --content "# <company> Decision-Making Map\n\n## Economic Buyers\n<list>\n\n## Technical Buyers\n<list>\n\n## Champions\n<list>\n\n## Relationships\n<connection-paths>" \
  --tags "salesnav,account-map,<company-slug>,fy27"
```

### 10. buyer-intent
Check buyer intent signals for target accounts.

```bash
# URL: https://www.linkedin.com/sales/buyers-circle/accounts
# Intent data: Based on LinkedIn member activity (profile views, content engagement)

# Playwright selectors:
# Intent dashboard: .buyer-intent-dashboard
# Account row: .buyer-intent-account-row
# Intent score: .buyer-intent-score
# Trend indicator: .buyer-intent-trend
# Category: .buyer-intent-category (e.g., "Research", "Evaluation")

# Intent categories and actions:
# High intent (score 80-100): Immediate outreach priority
# Medium intent (50-79): Schedule for next week
# Low intent (0-49): Monitor, no immediate action
# Rising (trending up): Accelerate timing

# Data to log:
# - Account name + intent score
# - Intent trend (up/stable/down)
# - Topic clusters (what are they researching?)
# - Key decision makers showing intent
# - Recommended actions from Sales Navigator
```

**Intent digest → ZK:**
```bash
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten \
  ingest \
  --dir /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten \
  --title "Buyer Intent Report — $(date +%Y-%m-%d)" \
  --content "Week of: $(date)\n\nHigh Intent Accounts:\n<list with scores>\n\nRising Intent:\n<list>\n\nKey Topic Clusters:\n<list>\n\nPriority Actions:\n<action-list>" \
  --tags "salesnav,buyer-intent,pipeline,fy27,$(date +%Y-%m)"
```

## Data Enrichment Flow

```
Sales Navigator Lead → view-lead → extract profile data
  ↓
ZK ingest (lead holon)
  ↓
Cross-reference with existing ZK holons:
  - Prior conversations (check by name/company)
  - Account intelligence (check by company)
  - Pipeline data (check for existing opportunity)
  ↓
Enriched lead record = ZK holon + pipeline stage + next action
  ↓
Export to CSV for CRM import (see fy27-csv-export.md)
```

## CSV Export Format (RFC 4180)

```
\xEF\xBB\xBF
"First Name","Last Name","Title","Company","LinkedIn URL","Sales Nav URL",
"Email","Phone","Location","Industry","Seniority","Saved Date",
"List Name","Intent Score","Last Activity","Notes","Next Action","Due Date"
```

All exports: `/home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/exports/`

File naming: `salesnav-<list-name>-$(date +%Y%m%d).csv`

## Weekly Operations Cadence

| Day | Operations | Saved Searches to Run |
|-----|-----------|----------------------|
| Monday | check-alerts, search-leads (ARM, EU-VPs) | ARM-Decision-Makers, EU-Semicon-VPs |
| Tuesday | view-lead (top 5), save-lead, inmail (2-3) | — |
| Wednesday | search-leads (Nokia, Verification), export-list | Nokia-5G-Leaders, EU-Verification-Leads |
| Thursday | account-map (1 account), view-lead (top 5) | Ericsson-Semicon |
| Friday | buyer-intent, check-alerts, export-list | Infinera-Optical |
| Weekend | — (no LinkedIn activity — avoid detection) | — |
