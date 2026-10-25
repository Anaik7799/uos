---
name: predict
description: "Instead of reacting to problems, PREDICT them using the system's own math:"
---

# Predict — Use health calculus to forecast system trajectory

Instead of reacting to problems, PREDICT them using the system's own math:

```bash
# Run Gleam health calculus
cd lib/cepaf_gleam && gleam run -m cepaf_gleam/claude_compute 2>&1 | grep -v warning

# What the derivatives tell you:
# d(H)/dt > 0 : System improving, keep current approach
# d(H)/dt < 0 : System degrading, investigate NOW before it gets worse
# d²(H)/dt² < 0 : Deceleration — improvement is slowing, find new approach
# d²(H)/dt² > 0 : Acceleration — either rapid improvement or rapid decline

# Check test count trend (must be non-decreasing per SC-MOKSHA-002)
gleam test 2>&1 | grep passed | tail -1
```

Use this BEFORE making architectural decisions. Don't guess — compute.
This is SC-SATYA-002: System MUST observe its OWN output periodically.
