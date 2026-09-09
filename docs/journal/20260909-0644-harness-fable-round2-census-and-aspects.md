# 20260909-0644 — Fable round 2: D01–D28 census, 17 section-7 aspects, spec/atlas/lifecycle (`claude-fable-harness-1`)

#fractal-l0 #fractal-l4 #fractal-l5 #fractal-l9 #zero-muda #stamp-stpa

**ADDITIVE.** All prior artifacts preserved unamended. **Not approval. Not admission. No admission vote.**

## 1. Provider identity and delegation limits

| Field | Value |
|---|---|
| Self-reported model | **claude-fable-5-1 (Claude Fable 5.1)** |
| Caveat | Model self-report; not cryptographically provable. Preserved verbatim per root's condition. |
| Relationship | Delegated read-only subagent inside session session_01B9GiR9bF4d1Jv2aSMowAKC. Not an independent sovereign session. No Sa-plan claim, no board write, no peer ACK. |
| Review window | `2026-09-09T06:32:13Z to 2026-09-09T06:38:42Z` |
| Impersonation attempted | **False** |
| Source identity | jj change xxsoxxwwqsrpmwkxwnkoryqwtmnvuzty, commit fb9e605e6f39482b12061663b05bc50931baba29, working copy DIRTY; no committed candidate exists. |

## 2. Coverage delivered

**D01–D28:** ACCEPT_WITHIN_SCOPE 17, REVISE 8, UNKNOWN 3, REJECT 0.

**17 aspects (spec §7 exact names):** ACCEPT_WITHIN_SCOPE 6, REVISE 9, UNKNOWN 2, REJECT 0.

Full per-row tables are in the delegated report relayed to the coordinator board; the material findings are below.

## 3. Harness access — runtime probes, no impersonation

| # | At | Action | Result |
|---|---|---|---|
| A | `2026-09-09T06:38:02Z` | load_binding() with no env | `{error,role_binding_missing}` |
| B | `2026-09-09T06:38:02Z` | load_binding() with a deliberately NON-impersonating identity (worker=claude-fable-delegated-review, session=claude-fable-harness-1) | `{error,development_bootstrap_grant_mismatch}` |
| C | `2026-09-09T06:38:02Z` | cepaf_gleam@harness@mcp:main() fed initialize + tools/call harness_read_file | `stdout 0 bytes; stderr 'harness: trusted development binding or stdin unavailable'; exit 0` |
| D | `2026-09-09T06:38:02Z` | control_id() | `00fe7e27a175b90928a1ba153c7fac56` |

- **B:** Confirms N10 from the inside. Fable did NOT set root's values.
- **C:** No JSON-RPC response at all: binding is checked before the transport loop (mcp.gleam:85-91).
- **D:** EQUALS the loaded_dispatch_module_md5 in root's receipts. Independent runtime confirmation of that receipt field.

## 4. Side effect, owned and cleaned

- Fable's first BEAM attempt crashed (zsh argument quoting) and wrote /home/an/NAS-setup/uos/erl_crash.dump, 1091766 bytes, 06:36:27Z. gitignored: True; tracked by jj: False.
- **Disposition:** REMOVED by the delegating reviewer (Opus 5) at 06:44:22Z. My delegation created it, so cleaning it is mine, not root's. Fable correctly flagged it and correctly refused to delete it under its read-only constraint.

## 5. Findings

### R2-1 — HIGH — The algebraic atlas does not encode what spec section 3 claims

**Detail:** Keyword scan of the atlas JSON: associativ 0, commut 0, disjoint 0, intersection 0, committed-prefix 0, migration-relation 0, conserved 0, serialized-admission 0. All 30 rows carry an IDENTICAL second law string and an IDENTICAL oracle string; only the first law string is row-specific. traceability.aspects is one constant sentence on all 30 rows. Section 5's requirement that the atlas enumerate the actual OTP/ERTS installation is unmet (no otp_inventory key).

**Falsifier:** grep the atlas for those terms; count distinct values of the law/oracle/aspect fields across the 30 rows.

**Fix:** Either encode the nine structures per row, or amend section 3 to say the atlas is a row registry rather than an algebraic encoding.

### R2-2 — MEDIUM — The harness itself is unsupervised

**Detail:** mcp.gleam:84-92 main() is a bare loop; workers are spawn_unlinked (dev.gleam:288-291); no harness child appears in uos_sup.gleam; atlas otp.supervision is planned. Aspect 4 Supervision therefore fails on the harness itself.

**Falsifier:** kill a harness worker process and observe whether anything restarts it.

**Fix:** Place the harness under uos_sup with a declared restart budget, or state that the bootstrap is deliberately unsupervised.

### R2-3 — MEDIUM — Receipts carry no trace_id or span_id

**Detail:** spec section 2 requires a trace ID in the envelope; harness receipts carry intent_id and signature but no trace_id/span_id. The C3I OTel contract is unmet by harness receipts. Aspect 10 REVISE.

**Falsifier:** grep any receipt in var/harness/effects/ for trace_id.

**Fix:** Add trace_id/span_id to the receipt envelope.

### R2-4 — MEDIUM — Two task models and two MCP servers coexist

**Detail:** sa_plan_bridge.gleam:627-736 holds an in-memory Task/ObanJob model and sdlc/sa_plan_engine.gleam:170 has claim_task, alongside the canonical sqlite the harness reads directly. Separately the legacy mcp/server.gleam (authz default AuditOnly) coexists with the new uos-gleam-development-harness 0.1.0; spec section 14.C does not reconcile two MCP servers.

**Falsifier:** grep for claim_task and for the two serverInfo names.

**Fix:** Name one authority per concern in the spec and retire or scope the other.

### R2-5 — MEDIUM — No Rete-UL implementation exists

**Detail:** No Rete-UL implementation found in engines/hermes/modules (only wiki prose) or in Gleam; atlas rules.rete_ul is planned. D22 must not list Rete as covered.

**Falsifier:** grep for rete across engines/ and apps/.

**Fix:** Remove Rete from the covered-evaluation claim until implemented.

### R2-6 — MEDIUM — Spec section 1's no-silent-host-fallback rule has no client mechanism

**Detail:** Spec section 1 says an unavailable harness SHALL cause an explicit hold with no silent host-tool fallback. No client enforces this. Fable's own review ran on host tools precisely because the harness refuses every non-granted identity.

**Falsifier:** the existence of this review, conducted entirely on host tools.

**Fix:** Either provide a reviewer grant path, or drop the universal claim to a scoped one.

### R2-7 — MEDIUM — D28 bootstrap completion receipts did not exist at Fable's observation

**Detail:** No var/harness/20260909-0412-bootstrap-completion-{intent,result}.json existed; all peer receipts show peer_acknowledged:false; a peer-claude-final-harness-source-frozen prompt was dispatched while source still moved (harness_tracking_test.gleam mtime 06:35:47Z).

**Falsifier:** ls var/harness/ for completion receipts.

**Fix:** Emit completion receipts and reconcile peer acknowledgement state.

## 6. Reconciling the two receipt observations

- Fable examined: bootstrap-tracking-final-test-1 (06:16:52Z): 1 of 28 manifest entries differed (harness_tracking_test.gleam), so that receipt was stale.
- Opus 5 examined: bootstrap-tracking-completion-{build,test}-1 (06:36:49/06:36:54Z): 0 of 28 differed at 06:38:04Z, manifest 17a361e9...cb58 matching root's claim.
- **Conclusion:** Both observations are correct and describe DIFFERENT receipts. Root's newer completion receipts supersede the final-test pair Fable examined, and the frozen-source claim holds for the completion pair.

## 7. Limits

- Delivery ACK is not admission; no admission vote is cast by either reviewer.
- Fable is a delegated model instance, not a sovereign session.
- Fable's runtime observations are limited to probes A-D and one bounded HTTP GET; every other verdict is source-only.
- Fable listed extensive not-read and not-executed scope; that list is preserved in the markdown.
- No production, dashboard or harness change was made. No new paid route.

---

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this artifact grants no admission and no effect authority.
