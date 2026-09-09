# EV-02 supervision follow-up

1. **Scope & Trigger** — Strengthen the preserved successor after the reviewer reported it could not begin a new EV2 probe assignment.
2. **Pre-State Assessment** — Candidate a37f8f94 killed the owned group, but its local descendant control only checked elapsed time.
3. **Execution Detail** — The control now forks a would-be late writer, waits after return, and requires that its marker path was never created.
4. **Root Cause Analysis** — Elapsed time alone does not prove a descendant did not survive.
5. **Fix Taxonomy** — Concrete delayed-side-effect falsifier.
6. **Patterns & Anti-Patterns Discovered** — A process termination test needs a post-return externally visible negative control.
7. **Verification Matrix** — Harness 8/8 PASS and candidate suite valid:true at /tmp/ev02-governance-harness-2024/summary.json.
8. **Files Modified** — tools/ev02_governance/run_checks.ml.
9. **Architectural Observations** — The group session remains bounded to descendants that do not intentionally escape their session.
10. **Remaining Gaps** — Independent replay is pending assignment; semantic mapping and historical lineage remain HOLD.
11. **Metrics Summary** — Eight harness controls, including early EOF, aggregate quota, startup failure, and delayed descendant marker.
12. **STAMP & Constitutional Alignment** — The new falsifier rejects a process control action that leaves a later side effect.
13. **Conclusion** — Immutable candidate 1e2f28d24d9f8ac11f7461a81455a8d97560f331; ACTIVE_PASS at 2026-09-09T20:20:51Z, assessment 0cc6ce393ebf41c57d2fc881dddccf3cc7b5cb2a162d010ae87c04a200a43d6e. No admission.
