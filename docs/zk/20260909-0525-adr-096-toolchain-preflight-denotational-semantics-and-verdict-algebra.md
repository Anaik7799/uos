# 20260909-0525- ADR-096: Toolchain Preflight — Denotational Semantics and the Verdict Algebra

<!--
Metadata:
- Timestamp: 20260909-0525-
- Author: Claude (Opus 5), UOS toolchain slice
- Status: ACCEPTED (design + formal layer); the toolchain it governs is VERIFIED, not ADMITTED
- Sa-Plan: uos-nix-devenv-toolchain-20260908 (task-06..task-21)
- Gate: G-PREFLIGHT (executes), KM-GATE, G-CHECKLIST
- Tailscale URI: http://nas-1.tail55d152.ts.net:4100/docs/zk/20260909-0525-adr-096-toolchain-preflight-denotational-semantics-and-verdict-algebra.md
- Tags: #fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l7 #zk-adr #zero-muda #algebraic-atlas #denotational-intent #formal-lean4 #toolchain
- Provenance note: ADR numbering continues from ADR-095. Per the standing EV>93
  quarantine, no claim in this record inherits admission from any EV cycle above
  93; every status below is bound to observations made at the cited revision.
-->

## Status

**ACCEPTED.** The semantics, laws, proofs and temporal model are complete and checked. The toolchain they govern is `verified`, not `admitted`.

## Context

Three consecutive hardening passes on the UOS toolchain produced the same defect three times, each time in a different disguise:

1. Every OTP assertion in the tree used `erlang:system_info(otp_release)`. It answers `"29"` for both the pinned 29.0.5 and an unpinned 29.0.6, so a hardcoded `/nix/store/…-erlang-29.0.6` sat in `tools/release_process.ml` while every check stayed green.
2. `uos_toolchain_report` used `test -x`. It cannot distinguish a working binary from a broken one.
3. The first useability probe used exit status. A zero-byte file with the execute bit set is a valid empty shell script: exit 0, no output. It reported **PASS**.

Each was the obvious API for the job. Each had an **output space strictly coarser than the property being enforced**, so no amount of care at the call site could have closed the gap. The recurrence is the signal: this is not a coding-habit problem, it is a **missing semantics** problem. Without a written denotation, every new check re-invents the meaning of its observations and re-discovers the same hole.

A fourth instance arrived to confirm the diagnosis: wiring the check into a second caller exposed that `toolchains/node-22`'s `npm` had been **incomplete since installation** — 41 bundled modules, no `semver`. `npm --version` never loads config, so it answered `9.2.0`; anything that loads config died. Present, self-identifying, non-working.

## Decision

**Separate observation from interpretation, and give the interpretation a proved algebra.**

$$\text{shell} : \text{World} \to \text{Observation} \qquad \llbracket \cdot \rrbracket : \text{Observation} \to \mathcal{V}$$

1. **`tools/preflight` (effectful)** decides what was observed. It runs every entrypoint — it never stats one — under `uos_env`, never the caller's shell.
2. **`Preflight_algebra` (pure OCaml)** decides what observations mean. No filesystem, process, network or clock.
3. **$\mathcal{V}$ is a meet-semilattice with top `Pass` and absorbing `Fail`.** There is deliberately no `Unknown`: an absent or unparseable observation *denotes* `Fail`, so **fail-closed is a theorem about the absorbing element, proved once**, not a discipline re-applied per call site.
4. **`ExitedZeroSilent` is a distinct constructor** from `ExitedZeroWithOutput`, and a probe must declare whether silence is legitimate. This is the third defect above, made unrepresentable.
5. **A receipt binds the digests of the checker and the resolver table.** A cached verdict is evidence about *specific code reading a specific table*; without both digests it would lend confidence to code it never examined.
6. **Locality and identity are separate charts with separate authorities.** Locality (`$HOME` / `/usr` / evidence trees) belongs to the shell; identity (the exact store derivation) belongs to the flake. No layer below the flake hardcodes a store path — copying "just one constant" downward is precisely how 29.0.6 survived.

## Consequences

**Positive.**
- Fail-closed, finding-accumulation, and "one arm sinks the run" are proved in Lean with an axiom audit printed at check time (`propext`, `Quot.sound`; no `sorryAx`).
- The temporal question — *can a caller accept a cached verdict it shouldn't, across arbitrary interleavings?* — is answered separately by Apalache (`inv_all`, `NoError`). A predicate correct at every instant can still be consulted at the wrong one.
- 27 executable laws link the **shipped** module, so a green suite is evidence about the code the gate, receipts and hooks all rest on.
- Mutation tests M1–M4 each kill exactly the law that names them, and no other.
- Adding a tool now fails closed until both tables agree (`tool_table_parity`).

**Negative / accepted costs.**
- Two resolver tables (shell and OCaml) exist. Duplication is a liability, accepted only because a parity guard proves the mirror and is itself mutation-tested.
- `Silent_ok` is a **trust decision**, not a derivation. It is granted narrowly and paired with an artefact assertion (`erlc` must leave a real `.beam`).
- The Quint result is bounded, not inductive.
- Functional probes cost more than `--version` — about 4.5 s in total, which is the budget that keeps the gate cheap enough not to be routed around.

**Explicitly not claimed.** Nothing here proves the shell observes correctly; that is empirical. A passing preflight is evidence the toolchain works — it is not Sa-plan completion, not deploy authority, and not system admission.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Keep ad-hoc checks, add a lint rule against coarse APIs | Does not survive the next API; the defect recurred three times under exactly this regime. |
| One table only (delete the OCaml mirror) | `release_process.ml` is an `ocaml` toplevel script with no link-time access to the shell library; a parsed parity guard was cheaper and is verifiable. |
| Hardcode the pinned store path in the shell resolver | Creates a third source of truth that drifts silently — the mechanism that produced the original 29.0.6 defect. |
| Trust exit status, skip the output requirement | Directly re-introduces defect 3; M1 demonstrates it kills L9. |
| Prove everything in Lean, drop Quint | Different question. Lean proves the predicate; Quint asks whether it can be consulted at the wrong moment. |

## Evidence at this revision

| Claim | Evidence |
|---|---|
| Laws hold | `test_preflight_algebra.exe` — **27/27 passed, 0 failed** |
| Laws are live | M1 kills L9 only; M2 kills L7 only |
| Theorems check | `tools/lean formal/lean/Preflight_Verdict_Algebra.lean` exit 0; axiom audit shows no `sorryAx` |
| Temporal invariants hold | `tools/quint verify … --invariant inv_all` → `NoError` |
| Model is non-vacuous | `not(accepted)` **violates** — `acceptCached` is reachable |
| Model has teeth | M3 → `inv_no_foreign_accept` violated; M4 → `inv_no_stale_accept` violated |
| The gate runs | `uos-cli gate G-PREFLIGHT` → PASS |
| The shell runs | `tools/preflight` 29/29; `--full` 31/31 |

---

**Related:** [[wiki:20260909-0525-uos-toolchain-preflight-guide]] · [[zk:adr-095]] · [[wiki:20260908-1345-uos-intent-based-config-and-algebraic-atlas-guide]]
**Design spec:** [20260909-0525-preflight-denotational-spec-and-algebraic-atlas.md](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0525-preflight-denotational-spec-and-algebraic-atlas.md)
**UOS footer:** `nas-1.tail55d152.ts.net:4100` · OTP 29 pinned at `…-erlang-29.0.5` · Sa-plan is the sole execution authority; this record grants no admission.
