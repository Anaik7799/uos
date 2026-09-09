# 20260909-1107 — R2 remediation: what was fixed, and the four repairs only the harness owner can land

#fractal-l0 #fractal-l4 #fractal-l5 #fractal-l9 #zero-muda #stamp-stpa #km-triad

**Live:** [http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-1107-harness-r2-remediation-and-owner-handover.md](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-1107-harness-r2-remediation-and-owner-handover.md)
· [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

**Not admission. No admission vote.** Observed 2026-09-09T11:48:07Z.
Advisory input: Antigravity (AGY, plan mode, read-only), 2026-09-09. Its analysis is
credited inline; every factual claim it made was re-checked against the tree before use,
and one was wrong — see §6.

---

## 1. The partition, and why it is the first question

Root froze 28 harness source paths. Four of the eight open items cannot be fixed without
mutating them, and four can. Doing the second group and *pretending* the first group is
closed would be the defect this whole review has been chasing, so the partition comes first.

| Finding | Fixable without touching frozen source | Status now |
|---|---|---|
| **R2-1** atlas does not encode spec §3 | **yes** — atlas JSON + spec, both unfrozen | **FIXED and gated** (§2) |
| **R2-5** Rete-UL claimed, not implemented | **yes** — spec + atlas | **FIXED** (§3) |
| **R2-6** no client mechanism for no-silent-fallback | **yes** — spec §1 narrowing | **FIXED** (§4) |
| **R2-7** completion receipts absent at observation | **yes** — superseded, record it | **CLOSED with evidence** (§5) |
| **R2-2** harness is unsupervised | no — `mcp.gleam`, `development.gleam` | **HANDOVER** (§7.1) |
| **R2-3** receipts carry no trace context | no — `development.gleam`, `mcp.gleam` | **HANDOVER** (§7.2) |
| **R2-4** two task models, two MCP servers | spec yes, code no | spec **PENDING**, code **HANDOVER** (§7.3) |
| **N10** no reviewer grant path | no — `development.gleam:188-199` | **HANDOVER** (§7.4) |

AGY independently produced the same partition. That is agreement, not verification: AGY
also confirmed all ten of an earlier finding set, two of which were wrong.

---

## 2. R2-1 — FIXED. The atlas now records its position instead of decorating it

### 2.1 What was actually wrong — larger than reported

Fable found three constant fields (`algebra.laws[1]`, `algebra.oracle`,
`traceability.aspects`). Counting per field rather than reading found the real extent:

```
  before:  48 of 74 leaf fields carried ONE identical value on all 30 rows   (65%)
  after:    0 of 29                                                            (0%)
```

A 16-field-group schema over 30 rows was carrying roughly 18 fields' worth of actual
per-row content. That is the defect class at document scale: the *observable* is "the
schema is populated", the *property* is "each capability is described", and the first
passed while the second was false for two thirds of the fields.

### 2.2 The repair, in three parts

**Hoisting.** A field with one value on every row is not 30 declarations. Genuinely uniform
policy — activation, authority predicate, roles, clock domains, transport correlation —
moved to a top-level `defaults` block where **each entry must carry a `rationale`**. An
invisible constant became an explicit, reviewable one. Two of those rationales say plainly
that the field is an *outstanding obligation* rather than a satisfied one
(`supervision.bounds`, and the four `state.*` fields), and
`per_capability_obligations_outstanding` lists all ten by name.

**Obligations.** Every row now carries one obligation per spec §3 structure — nine, closed,
exactly once each. Across 30 rows that is **270 obligations**:

| Status | Count | Meaning |
|---|---:|---|
| `UNKNOWN` | 181 | recorded and unproven. **Not a pass.** |
| `NOT_APPLICABLE` | 85 | with a stated reason drawn from the row's own denotation |
| `VIOLATED` | 3 | established by this review, each with its falsifier |
| `HOLDS` | 1 | `clients.hooks`, the one repair with its own receipt |

That distribution is the honest answer, and it is the point. A schema that made honesty
expensive would have produced 270 confident sentences instead.

**Enforcement.** `engines/hermes/modules/hermes_toolchain/atlas_algebra.{ml,mli}` is a pure
denotational core with a **35-law suite**; `atlas_check.ml` is the effectful shell;
`tools/atlas-check` supplies the OTP facts from the resolver that owns toolchain identity;
gate `G-ATLAS` executes it and runs in `verify-all`. Five negative controls kill:

| Control | Result |
|---|---|
| strip the falsifier from the one `HOLDS` | FAIL — "an unfalsifiable pass is decoration" |
| drop one structure from one row | FAIL — names the missing structure and its required law |
| launder a constant back in as a per-row field | FAIL — degeneracy arm |
| declare a bounded-domain field that is pinned to one value | FAIL — "an enumeration with one member is still a constant" |
| declare `otp_release: 27` | FAIL — compared against the running BEAM, which reports 29 |

### 2.3 Where AGY changed the design

AGY argued against forcing nine structures onto every row: authors will write generic prose
for the inapplicable ones, `grep associativity` will return 30 matches, and none will be
falsifiable. The keyword passes, the property is untouched.

The type already answered half of that — `UNKNOWN` and `NOT_APPLICABLE` are well-formed and
free, so nothing forces invention. AGY's other half was a real gap and was adopted: a
`HOLDS` now requires an **`oracle`** naming where the claim is actually executed, on top of
its predicate and falsifier. A claim nothing in the repository would notice breaking is not
a claim. That is law **L15a**.

AGY also observed that commutativity is a relation between *two* operations, not a property
of one — so recording `independent_operations` as a unary claim is a category error. All 30
rows now say exactly that, in the obligation itself.

### 2.4 The same defect, found inside the guard

First run of the finished checker: 49 degenerate fields, worse than before. The degeneracy
arm was counting `algebra.structures[i].structure` — necessarily the same nine names in the
same order, because that is what "all nine, exactly once" *means* — and the empty
`falsifier`/`oracle` of honest `UNKNOWN` entries.

The guard against punishing honesty had itself started punishing honesty. A ratio rule
cannot distinguish *uniform because required* from *uniform because empty*. The obligation
subtree is now excluded from that arm — it has its own, finer arm — and the exclusion is
commented as load-bearing rather than convenient. Categorical fields with a small legitimate
domain (`effect.class`, `transport.availability`) are judged by a finer rule instead: they
must exhibit more than one value, whatever their declared domain claims.

---

## 3. R2-5 — FIXED, and the finding was partly overstated

`hermes_rete.ml`'s own header has always said what it is: *"a NAIVE forward-chaining
matcher, not the Rete algorithm (no alpha/beta network, no token memories, no unlinking)"*.
The code was honest; two documents were not.

Corrected: formal spec §4 (`ETS, STM, Bayesian and Rete-UL` → `and the fail-closed rule
gate`) and §6 (`Rete rules` → `fail-closed rule-gate evaluation`). Spec §18 already said
semantic tests must not be mislabeled as validating a Rete-UL implementation; the repair is
that §4 and §6 now agree with it.

**R2-5 said D22 must not list Rete as covered. On reading D22, it never claimed coverage** —
its text is *"algorithms not verified (notably Rete-UL)"*. That part of the finding is
withdrawn. The atlas row keeps its id (renaming breaks every traceability reference) and
carries an explicit `retraction` block plus a `VIOLATED` obligation.

Not implementing Rete is the Zero-Muda answer, not a shortcut: Rete exists for 10,000+ rules
over 100,000+ churning facts. UOS evaluates about a dozen safety rules sequentially in
microseconds. A token-memory dataflow graph for that is overproduction, and its retraction
bugs would be pure defect Muda.

---

## 4. R2-6 — FIXED by narrowing the claim to one that can hold

Spec §1 said agents *"SHALL NOT silently fall back to host tools"*. Nothing enforced it, and
a `SessionStart` hook cannot: it appends text to a model's context, and a model is not
constrained by its own context window.

**The proof is in this review's own record.** The delegated Fable reviewer was refused with
`development_bootstrap_grant_mismatch` and then completed its entire review on `cat`,
`grep`, `wc`, `diff` and `python3`. Every finding above was produced by host-tool work
during exactly the hold that sentence forbade.

Pointing at the newly repaired hooks as evidence would have been the trap in its purest
form: observable "the hook fired", property "the agent cannot use host tools". The hooks
*are* wired now, validated against the installed client — and wiring is not enforcement.
The guarantee moved to the admission boundary, which sees receipts rather than intentions:
no state change, receipt, certificate or Sa-plan completion derived from direct host-tool
execution may be admitted.

---

## 5. R2-7 — CLOSED, superseded by receipts that now exist

At Fable's observation (06:38Z) no `bootstrap-completion-{intent,result}.json` existed.
They exist now and were independently verified by this reviewer:

| Receipt | Verified |
|---|---|
| `bootstrap-tracking-completion-{build,test}-1` | manifest `17a361e9…`, 28 entries, 0 changed on disk |
| `bootstrap-attempt2-{build,test}-1` | manifest `969845811bed…f21e19`, MD5 `cc4cf97a…`, 28 entries, 0 changed |
| attempt-1 → attempt-2 delta | manifest diff: no path added or removed, **exactly one** entry changed — `development.gleam`, line 193 `attempt == 1` → `attempt == 2` |

Both observations were correct and described **different receipts**. `peer_acknowledged:false`
remains true across peer receipts and is a separate open item, not part of R2-7.

---

## 6. Where AGY was wrong

AGY's illustrative `otp_inventory` proposed `target_otp_release: "27"`, `target_erts_version:
"15.0"`. This tree is pinned to **OTP 29.0.5, ERTS 17.0.5**, and OTP 27 is explicitly barred
(`SC-NIX-DEVENV-001` inv.4). Had that fragment been copied, the atlas would have declared a
barred toolchain.

The measured inventory went in instead — 35 applications enumerated from `code:lib_dir()` in
the pinned BEAM — and the checker compares it against the running installation, which is
what caught the substitution in negative control N5. The advice was valuable; the numbers in
it were not evidence. Same rule as always: agreement is not verification.

---

## 7. Handover: four repairs only the owner of the 28 frozen paths can land

Each carries the trap it must avoid, because each has an obvious cheap version that would
pass a check while leaving the property false.

### 7.1 R2-2 — supervision

`mcp.gleam:84-92 main()` is a bare loop; workers are `spawn_unlinked`
(`development.gleam:288-291`); no harness child appears in `uos_sup.gleam`, which is
*unfrozen* — but a supervisor needs something to supervise, and the `start_link` it would
need lives in frozen source. Either place the harness under `uos_sup` with a declared
restart budget, or state in the spec that the bootstrap is deliberately unsupervised.

**Falsifier:** kill a harness worker and observe whether anything restarts it.
**Trap:** adding a child spec that never starts. The observable is "uos_sup lists a harness
child"; the property is "a killed worker comes back".

### 7.2 R2-3 — trace context

Receipts carry `intent_id` and `signature`, no `trace_id`/`span_id`. Spec §2 requires a
trace ID; the C3I OTel contract requires W3C context.

**Trap (AGY's, and it is the sharp one):** minting a fresh random UUID per receipt.
`receipt.trace_id != null` passes and the causal chain is still broken. The `trace_id` must
come from the incoming `traceparent`; `span_id` must be the new child span.
**Falsifier:** issue two related calls and check the receipts share a `trace_id`.

### 7.3 R2-4 — one authority per concern

`sa_plan_bridge.gleam:627-736` holds an in-memory Task/ObanJob model and
`sdlc/sa_plan_engine.gleam:170` has `claim_task`, alongside the canonical SQLite the harness
reads directly. Separately the legacy `mcp/server.gleam` (authz default `AuditOnly`,
`serverInfo c3i-planning-mcp 1.0.0`) coexists with `uos-gleam-development-harness 0.1.0`;
spec §14.C reconciles neither pair. The spec half is unfrozen and still **pending**; the code
half needs the owner.

**Falsifier:** `grep claim_task`; `grep serverInfo`.

### 7.4 N10 — reviewer grant

`development.gleam:188-199` compares the binding against a single literal tuple, checked
*before* the transport loop, so a second reviewer cannot use the harness at all — which is
why every finding in this review is source-only, and why R2-6 had to be narrowed.

AGY's design, reviewed and endorsed: a distinct `Review` role, `attempt: 0` so a reviewer can
never collide with the worker's in-flight attempt, receipts stamped `role: "review"`, and
`harness_finish` verifying that build and test intents came from a `Development` binding —
otherwise a reviewer's test could produce a receipt the developer uses to satisfy
`harness_finish`.

**Trap:** loosening `load_binding()` alone. That is a perimeter check: the reviewer
authenticates and can then call `harness_write_file`. The capability mask has to be enforced
per tool call in `mcp.gleam`, not once at the door.

| Tool | Development | Review |
|---|---|---|
| `harness_read_file`, `harness_observe_clock`, `harness_status` | allowed | **allowed** |
| `harness_test` | allowed | allowed, isolated |
| `harness_write_file`, `harness_build`, `harness_finish` | allowed | **denied**, explicit error |

Environment-asserted identity stays forgeable in this bootstrap phase. That is acceptable
**only** because the `Review` role can mutate nothing — and it stops being acceptable the
moment any write is added to it.

### 7.5 Sequence

N10 first. Without it the next reviewer is forced into exactly the host-tool fallback §4
just narrowed the spec to stop pretending it prevents.

---

## 8. Limits

- Conformance is **not** capability. A `PASS` from `G-ATLAS` means the atlas states its
  position honestly and no field is a constant in disguise. 181 of 270 obligations are
  `UNKNOWN`; none of them became a pass by being recorded.
- Root's 28 frozen paths were not modified. No production runtime change.
- The four handover items are **open**, not closed by having been specified.
- Advisory input is advisory. AGY's analysis shaped §2.3 and §7.4 and was wrong in §6.

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) ·
Sa-plan is the sole execution authority; this document grants no admission and no effect authority.
