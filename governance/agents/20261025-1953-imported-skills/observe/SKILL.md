---
name: observe
description: "Check the actual running system state, not cached knowledge:"
---

# Observe — Real-time system state via live endpoints

Check the actual running system state, not cached knowledge:

```bash
# 1. Server health (is it running?)
curl -s https://localhost:4100/health 2>/dev/null | head -5 || echo "Server not running"

# 2. Task status (from authoritative Smriti.db)
sa-plan-daemon status

# 3. Navigation graph health (via Gleam NIF)
cd lib/cepaf_gleam && gleam run -m cepaf_gleam/claude_compute 2>&1 | grep -E "SCC:|Pages:|Boot DAG"

# 4. Test suite health
cd lib/cepaf_gleam && gleam test 2>&1 | grep "passed" | tail -1

# 5. Git status (uncommitted work?)
git status --short | head -10
```

Report: What is ACTUALLY true right now? Not what memory says — what the system says.
This is SC-SATYA-001: Only show truth. SC-TRUTH-001: Stale data is a lie.
