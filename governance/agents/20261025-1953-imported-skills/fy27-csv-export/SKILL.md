---
name: fy27-csv-export
description: "Export data from \"$ARGUMENTS\" (contacts | pipeline | activities | accounts | meetings | linkedin | all):"
---

# FY27 CSV Data Export -- Export ZK data to CSV for CRM, Excel, and reporting

Export data from "$ARGUMENTS" (contacts | pipeline | activities | accounts | meetings | linkedin | all):

## Available Exports

### 1. contacts
Export all contacts from FY27-ZK to CSV.
```sql
sqlite3 fy27-plan.db ".mode csv" ".headers on" \
  "SELECT first_name, last_name, email, company, job_title, phone, source FROM contacts ORDER BY company, last_name;"
```
Output: FY27-Plan/exports/contacts-YYYY-MM-DD.csv

### 2. pipeline
Export deal/opportunity data from ZK.
Search ZK for all deal-tagged holons, extract structured deal data.
Output: FY27-Plan/exports/pipeline-YYYY-MM-DD.csv
Columns: deal_name, account, stage, value, probability, weighted_value, days_in_stage, last_activity, next_action, meddpicc_score, owner

### 3. activities
Parse all activity log files from FY27-Plan/activities/YYYY-MM-DD-activity-log.md
Output: FY27-Plan/exports/activities-YYYY-MM-DD.csv
Columns: date, time, category, account, contacts, action, outcome, follow_up, tags

### 4. accounts
Export account status summary.
Output: FY27-Plan/exports/accounts-YYYY-MM-DD.csv
Columns: account, last_touch_date, open_deals, total_pipeline_value, key_contact, relationship_score, constraint, next_action

### 5. meetings
Parse all files from FY27-Plan/activities/meetings/
Output: FY27-Plan/exports/meetings-YYYY-MM-DD.csv
Columns: date, account, attendees, type, key_decisions, action_items, next_steps

### 6. linkedin
Parse activity logs for linkedin-tagged entries.
Output: FY27-Plan/exports/linkedin-activity-YYYY-MM-DD.csv
Columns: date, action_type, target_person, target_company, message_sent, response_received, connection_status

### 7. all
Run all exports above. Create summary report.
Output: FY27-Plan/exports/full-export-YYYY-MM-DD/ (directory with all CSVs + summary.md)

## Execution

### Step 1: Query Data
```bash
cd /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten
ZK=/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten

# For contacts (direct SQL)
sqlite3 fy27-plan.db ".mode csv" ".headers on" "SELECT * FROM contacts ORDER BY company;"

# For holons (search and parse)
$ZK search "deal opportunity"
$ZK search "activity log"
```

### Step 2: Parse and Format
- Parse output into structured CSV
- Proper escaping (RFC 4180: double-quote fields with commas)
- UTF-8 encoding with BOM for Excel compatibility
- Header row always present

### Step 3: Write CSV
Create exports directory if needed: FY27-Plan/exports/
Write CSV with proper formatting.

### Step 4: Post-Export
1. Report: file path, row count, column count, file size
2. Log to ZK: /fy27-log task "Exported N records to CSV"
3. If requested, email via sa-plan-daemon send-email

## CSV Format Standards
| Standard | Value |
|----------|-------|
| Delimiter | comma (,) |
| Encoding | UTF-8 with BOM |
| Quoting | RFC 4180 |
| Date format | YYYY-MM-DD |
| Time format | HH:MM (24h) |
| Currency | plain number (150000 not $150,000) |
| Empty fields | empty string |
| Line endings | CRLF (Windows compatible) |

## CRM Import Compatibility
Designed for direct import to Salesforce, HubSpot, Pipedrive, Excel, Google Sheets.

### Salesforce Field Mapping
| CSV Column | SF Object | SF Field |
|-----------|-----------|----------|
| first_name | Contact | FirstName |
| last_name | Contact | LastName |
| email | Contact | Email |
| company | Account | Name |
| job_title | Contact | Title |
| phone | Contact | Phone |
| deal_name | Opportunity | Name |
| stage | Opportunity | StageName |
| value | Opportunity | Amount |

### HubSpot Field Mapping
| CSV Column | HubSpot Property |
|-----------|-----------------|
| first_name | firstname |
| last_name | lastname |
| email | email |
| company | company |
| job_title | jobtitle |
| phone | phone |
| deal_name | dealname |
| stage | dealstage |
| value | amount |
