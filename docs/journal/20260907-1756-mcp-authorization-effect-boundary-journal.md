# 20260907-1756- Journal: Authorization at the MCP Tool-Call Effect Boundary

`#fractal-l0` `#fractal-l1` `#fractal-l2` `#fractal-l3` `#fractal-l4` `#fractal-l5` `#fractal-l6` `#fractal-l7` `#fractal-l8` `#fractal-l9` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#journal`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-mcp-authorization-effect-boundary-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-mcp-authorization-effect-boundary-journal.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Clock**: host `2026-09-07T18:11:32Z` (chrony stratum 3). **Sa-plan**: plan `uos/agentic-infra-checklist/20260907-1722`, task `t4-mcp-authz-wiring` (P1, score 960), preflight `PREFLIGHT_PASS`, worker `claude-fable-5.1-session-019m7SjJ`.  
**Checklist rows moved**: AIC-IS-02 (policy on the dispatch path), AIC-DT-02 (rate limiting and path validation on the dispatch path), AIC-PR-06 (separation of policy).

## 1. Scope & Trigger
Operator: "go further". Second SOP follow-up: authorization at real effect boundaries. Scope: `apps/cepaf_gleam` MCP server only (new module `mcp/authz.gleam`, one FFI file, one dispatcher change, tests). No deploy, no rule or agent surface change.

## 2. Pre-State Assessment
`mcp/server.gleam` ran the Jidoka bypass check and, for six mutating tools, a STPA and forecast preflight, then executed. The guardian gate (`bridge/pi_tools.check_gate`) and the access enforcer (`planning/enforcer`) had no caller on that path. Any caller could read any path the process could read, at any rate. The enforcer requires a proof token from every AI agent for any operation, so it could not be applied wholesale without denying every existing caller.

## 3. Execution Detail
1. New module `apps/cepaf_gleam/src/cepaf_gleam/mcp/authz.gleam`: pure `authorize(policy, rate_state, max, window, name, mutating, raw_line)` runs three controls in order and fails closed: per-caller, per-minute rate limit (`enforcer.check_rate_limit`, window rollover); path controls (forbidden fragments via `enforcer.is_forbidden_path`, and `enforcer.enforce_access` for the SC-TODO-001 planning ledger, with proof-token pass-through); guardian gate (`pi_tools.check_gate`) using the federated catalog entry or a synthesized L3 entry that is guardian-gated when the tool is mutating.
2. Policy is configuration, never the request: `UOS_MCP_GUARDIAN_MODE` selects permissive, audit_only, enforce_non_l0, enforce_all or lockdown; an unparseable value falls back to audit_only, never permissive. `UOS_MCP_RATE_LIMIT_PER_MINUTE` defaults to 600.
3. `apps/cepaf_gleam/src/mcp_authz_ffi.erl`: environment read, process-dictionary rate state, minute window key, UTC timestamp. No ETS, no shell, no network.
4. `mcp/server.gleam` `execute_tool`: after the Jidoka check and before any preflight or execution, `authz.authorize_and_persist`; a denial returns JSON-RPC error -32003 (guardian), -32004 (rate limit) or -32005 (access) and nothing runs. One audit line per call goes to stderr as JSON.
5. `test/mcp_authz_wiring_test.gleam`: 18 tests covering every mode, unknown tools, request-supplied policy being ignored, rate windows and per-agent buckets, forbidden paths including the sa-plan database, SC-TODO-001 for anonymous and AI callers, ordinary paths, identity extraction, and two end-to-end calls through `handle_request_raw`.

## 4. Root Cause Analysis
Policy modules were written as libraries with their own tests and never called from the dispatcher; the dispatcher's only gates were bypass-flag detection and hazard scoring for six tool names. Nothing bound "policy exists" to "policy runs".

## 5. Fix Taxonomy
Runtime control wiring (Gleam and Erlang) plus tests. Behaviour change for callers: forbidden paths and rate limits now deny; guardian denials deny only when an operator sets a blocking mode.

## 6. Patterns & Anti-Patterns Discovered
Pattern: one pure `authorize` function with an explicit state argument, wrapped by one effectful function that owns configuration and persistence; tests exercise the pure function per mode and the wrapper end to end. Interim compromise, stated in code: guardian mode defaults to audit_only because a `Blocked` decision has nowhere to go until an approval store exists (AIC-EC-03). Anti-pattern found: the enforcer's "AI agents always need a proof token" rule makes it unusable as a general gate; it is scoped to the ledger it protects.

## 7. Verification Matrix
| Check | Result |
|---|---|
| `gleam build` (apps/cepaf_gleam) | clean |
| `gleam test` (apps/cepaf_gleam, full suite) | 10,412 passed, 0 failed (includes 18 new tests; existing MCP suites unchanged) |
| End-to-end forbidden path | `read_file` on `/home/an/.ssh/id_rsa` returns `"code":-32005` |
| End-to-end read-only tool under default configuration | not denied by -32003, -32004 or -32005 |
| Request-supplied policy | ignored (test) |

## 8. Files Modified
| File | Change |
|---|---|
| `apps/cepaf_gleam/src/cepaf_gleam/mcp/authz.gleam` | New, authorization module |
| `apps/cepaf_gleam/src/mcp_authz_ffi.erl` | New, minimal FFI |
| `apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam` | Import and one `execute_tool` branch |
| `apps/cepaf_gleam/test/mcp_authz_wiring_test.gleam` | New, 18 tests |

## 9. Architectural Observations
The dispatcher now has a single choke point shared by stdio and the Zenoh bridge (`handle_request`). The next control that belongs there is a persisted approval record so that `Blocked` can become "held pending approval" instead of a hard error, which also unlocks the blocking default.

## 10. Remaining Gaps
Approval store and pause/resume (AIC-EC-03); operator decision on the default guardian mode once that exists; rate state is per serving process, not cluster-wide; call-frequency limits per tool class; externalizing policy to a store is still open (policy is typed Gleam code, which satisfies "decoupled from prompts" but not "managed independently in a policy engine").

## 11. Metrics Summary
| Metric | Value |
|---|---|
| New source lines | about 330 (Gleam) + 30 (Erlang) |
| Tests added / suite total | 18 / 10,412 |
| Denial codes introduced | -32003, -32004, -32005 |
| Default rate limit | 600 calls per caller per minute |

## 12. STAMP & Constitutional Alignment
Loss L-RISK-UNAUTHORIZED-EFFECT, hazard H-1. UCA "not provided" (no policy check before execution) is constrained by the authorize step preceding preflight and execution; UCA "provided unsafe" (denial logged but tool runs) is constrained by the denial being the response. Fail-closed on parse errors of configuration. Zero-Muda intact (no new dependency). Work ran under a claimed sa-plan lease with preflight pass; no Git inside UOS.

## 13. Conclusion
Policy now runs where effects happen. Forbidden paths and rate limits block today; guardian blocking is one environment variable away and will become the default once approvals can be held rather than refused.

---
**Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md) · **Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md) · **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md)  
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · peer `vm-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.
