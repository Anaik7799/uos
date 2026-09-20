# MCP Native Mapping Audit

**Timestamp:** 20260921-0723 UTC  
**Workflow:** `uos/system-mcp-features/20260919-1642/t1-mcp-native-audit/20260921-0715`  
**Decision:** HOLD; development checkpoint only; no admission

## 1. Scope & Trigger
The dashboard showed broad declared MCP coverage. This audit binds declared MCP handlers to source-level native NIF exports and records unmapped or unavailable paths without loading native code or calling tools.

## 2. Pre-State Assessment
The server declares 18 NIF-oriented names, 12 unavailable names, and additional page/MAX handlers. Runtime loading, endpoint reachability, authorization, and receipts were UNKNOWN. The source-universe and app-local native ledgers were the controlling prior evidence.

## 3. Execution Detail
Read-only inspection covered `mcp/tools.gleam`, `mcp/server.gleam`, `c3i/nif.gleam`, the Erlang loader, and the native artifact hash. The mapping artifact records direct calls, aliases, non-NIF handlers, unavailable declarations, and native exports without direct MCP mapping. No `tools/call`, NIF load, database mutation, or canonical import occurred.

## 4. Root Cause Analysis
ACH disconfirmation matrix:
| Hypothesis | Disconfirming observation | Status |
|---|---|---|
| H1 (primary): declarations and adapters are counted as capability despite no fresh runtime receipt | No runtime call or receipt exists in this slice | retained |
| H2: aliases and page/MAX adapters obscure one-to-one native coverage | Exact handler names separate the classes | retained |
| H3: native exports exceed the MCP registry | Seventeen exports have no direct tool mapping | retained |
| H4: runtime state may be unavailable despite compiling bindings | Runtime load was intentionally not probed | open |

## 5. Fix Taxonomy
Poka-Yoke: machine-readable mapping separates direct NIF, alias, non-NIF, and unavailable records.  
Jidoka: HOLD prevents source declarations from becoming effect authority.  
Muda removal: future reviews use the bounded source set and avoid repeated declaration-only scans.

## 6. Patterns & Anti-Patterns Discovered
Pattern: planning and system tools call a small explicit NIF surface.  
Anti-pattern: treating `runtime_loaded`, a `.so` file, or a tool definition as proof of execution.  
Pattern: legacy mutation remains refused at the server boundary.  
Anti-pattern: silently collapsing aliases, MAX, Wisp, and NIF paths into one availability count. Devil's Advocate test: if a compiled adapter were sufficient evidence, the unmapped exports and missing receipts would not remain unexplained; therefore declaration-only promotion is falsified.

## 7. Verification Matrix
| Check | Evidence | Result |
|---|---|---|
| Source hash binding | six source/artifact SHA-256 values in audit JSON | PASS, source-only |
| Direct NIF mapping | 18 tool records with exact handler names | PASS, declaration-level |
| Unavailable registry | 12 explicit refusal records | PASS, declaration-level |
| Unmapped exports | 17 native exports listed | PASS, source-only |
| Runtime execution | no load or call permitted in this slice | UNKNOWN |
| Admiralty admissibility | fresh observed runtime + formal binding absent | B2 HOLD |

## 8. Files Modified
- `governance/capability-inventory/20260921-0715-mcp-native-mapping-audit.json`
- `governance/planning/20260921-0715-mcp-native-mapping-risk.json`
- `docs/journal/20260921-0715-mcp-native-mapping-audit.md`

## 9. Architectural Observations
The MCP boundary is a typed dispatch algebra, but its current native subset is not a complete system capability algebra. A future accepted implementation must preserve server-qualified identity, Sa-plan effect fencing, refusal semantics, and receipt correlation across NIF, MAX, Wisp, and pure Gleam handlers.

## 10. Remaining Gaps
Runtime-loaded state, native ABI behavior, database target, MAX worker support, Wisp endpoint behavior, authorization, holon identity, formal contracts, and independently authorized release/recovery remain unverified. These are required before any mapping is marked available.

## 11. Metrics Summary
Declared NIF-oriented tools: 18. Explicit unavailable declarations: 12. Native exports without direct MCP mapping: 17. Runtime calls: 0. Side effects: 0. Risk score: 2000. Evidence freshness: source observation at 20260921-0723 UTC. Bayesian trust prior is Beta(1,1); this source-only slice adds zero successes and zero runtime trials, so posterior remains Beta(1,1). Lyapunov stability is not established because no live state derivative was observed.

## 12. STAMP & Constitutional Alignment
The unsafe control action is promoting a source mapping to operational authority. The stop line is the Sa-plan/report-only boundary plus explicit HOLD. No EV number is minted; EV ceiling remains 93 and EV-94..EV-109 remain NOT_ADMITTED. Zero-Muda exclusion and standalone Jujutsu constraints were preserved.

## 13. Conclusion
The audit improves the tracker’s coverage model but proves no runtime capability. Precommitted Brier-scored Forecast: by the next authorized runtime campaign, the MCP-native surface will remain on HOLD unless each endpoint has a fresh receipt (Brier forecast 0.80 for HOLD, Horizon 7 days).

## Comprehensive Verification Checklist
- [x] CHK-01-TIME — UTC timestamp recorded.
- [x] CHK-02-TAIL — Canonical Tailnet file route is known; serving remains unverified.
- [x] CHK-03-FRACT — L0–L9 applicability retained.
- [x] CHK-04-KM — Evidence, risk, journal cross-linked by workflow.
- [x] CHK-05-MUDA — Forbidden graphics dependencies and NIFs were not introduced.
- [x] CHK-06-GRAPH — Mapping is source-only and functional boundary is preserved.
- [x] CHK-07-DRIVE — No protected storage or production database mutation.
- [ ] CHK-08-C1C8 — Full-system surfaces UNRUN.
- [ ] CHK-09-MATH — Mathematical gates UNRUN for this candidate.
- [x] CHK-10-9MOD — Scoped source and negative-control review complete.
- [x] CHK-11-REGR — Prior 11,983/0 regression remains separately scoped.
- [ ] CHK-12-GLEAM — Deployed OTP authority unverified.
- [ ] CHK-13-HERMES — Invocation-specific formal admission pending.
- [ ] CHK-14-ZIGVM — Kernel/VFS release evidence outside scope.
- [ ] CHK-15-MAX — Worker execution unverified.
- [ ] CHK-16-OTEL — End-to-end correlation unverified.
- [ ] CHK-17-SOV — Independent release admission pending.
- [x] CHK-18-JJ — No native Git mutation; standalone JJ preserved.

EV ceiling remains 93. This document is not admission evidence.
