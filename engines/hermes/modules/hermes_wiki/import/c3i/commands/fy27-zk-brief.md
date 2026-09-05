# FY27 ZK Brief — Instant intelligence briefing from Zettelkasten

Pull an intelligence briefing from the FY27 Zettelkasten on "$ARGUMENTS":

## Execution
Search the FY27 Zettelkasten across multiple dimensions:

```
cd /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten
ZK=/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten

# 1. Primary search
$ZK search "$ARGUMENTS"

# 2. Contact search
$ZK contacts "$ARGUMENTS"

# 3. Related searches (agent should expand query intelligently)
# e.g., if $ARGUMENTS = "ARM", also search:
#   $ZK search "ARM Neoverse verification"
#   $ZK search "ARM account plan service targeting"
#   $ZK search "ARM rate card pricing"
#   $ZK search "ARM competitor"
```

## Output Format

### Intelligence Summary
Synthesize ALL ZK hits into a structured briefing:

1. **What We Know**: Key facts from ZK holons (cite holon UUIDs)
2. **Key People**: Contacts found (name, title, company, email)
3. **Historical Context**: Prior plans, proposals, or deals
4. **Pricing Reference**: Rate cards or deal values if found
5. **Competitive Angle**: Competitor mentions in this context
6. **Gaps**: What the ZK does NOT know (requires primary research)

### Verification
- [ ] All facts traced to ZK holon UUIDs
- [ ] No fabricated data
- [ ] Gaps explicitly identified
- [ ] Confidence level stated (high/medium/low per section)
