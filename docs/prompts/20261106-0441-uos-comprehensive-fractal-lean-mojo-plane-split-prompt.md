# 20261106-0441 — Comprehensive fractal prompt: splitting a proof tree into a Lean algebra plane and a Mojo observation plane

Tags: #fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #km-triad #zk-adr #zero-muda #stamp-stpa

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Source](http://nas-1.tail55d152.ts.net:4100/files/docs/prompts/20261106-0441-uos-comprehensive-fractal-lean-mojo-plane-split-prompt.md)

Observed from the host clock at `2026-11-06T04:41Z`. Authority NONE. EV ceiling 93; `EV-94..109` `NOT_ADMITTED`; no new EV number minted. This is a reusable method, not an admission.

---

## 0. What this prompt is for

Reuse it when a formal tree has grown an **observation plane** inside its **proof plane** — when files that prove theorems also spawn processes, read the live system, and print verdicts. It is written as an executable procedure with its own failure modes attached, because the failure modes are the part that generalises.

It is fractal: the same seven POODAVR steps apply at `L0` (constitutional invariants) and at `L9` (sovereign gate), and the same three checks (`algebra` / `world` / `observe`) apply to a single predicate and to a whole subsystem.

---

## 1. The boundary rule

| Plane | Owns | Never |
|---|---|---|
| **Lean** (algebra) | types, defs, theorems over finite domains, `by decide`, total functions | `IO.Process`, `IO.FS`, sockets, **recorded observations** |
| **Mojo** (world) | process spawn, HTTP, SSH, systemd, sqlite, filesystem scans, SIMD numerics | claiming a proof |

A **differential pair** is: Lean proves symbolically; a Mojo oracle **derives or observes** — never *restates* — the identical algebra concretely. Agreement is two-key evidence (`Trust = Fresh Empirical Behavior ∧ Formal Spec`). Disagreement means the decide-domain and the derived domain are not the same domain, and that is graver than any outage.

**The barred thing is not IO. It is an observation feeding a verdict into a theorem.** A generator that writes a file deterministically from the model is sanctioned work; a prober that reads the world and proves something about the reading is not, because its claim rots while the kernel keeps re-certifying the arithmetic.

---

## 2. The defect class this finds: a proof that outlives its subject

```lean
def observationNow := { observedUtc := "2026-11-05T17:05:00Z", unownedNames := 2 }
theorem THM_RUN_01_diverges_today : aligned expectation observationNow = false := by decide
```

The kernel re-verifies the arithmetic forever and **never re-verifies the fact**. The underlying rename landed at `22:20Z`; every live config went to zero. The theorem stayed green for four hours after its subject became false, because a hardcoded constant cannot go stale in the kernel's eyes.

Historical fixtures are fine — `observationDuringOutage` names a past moment and claims nothing about now. **Present tense is not fine.** The rule is *fixtures yes, present tense no.*

The generalisation, which is the valuable part: **a recorded verdict whose subject can change, and which nothing re-measures, is the same defect at every scale** — in a theorem, in a journal that says "100% green", in a capability inventory, in a preflight receipt honoured past its subject's lifetime, in a governance manifest naming a file that was deleted.

---

## 3. POODAVR, once per phase

| Step | What it means here |
|---|---|
| **Predict** | Write the expected count *before* measuring. "18 of 20 `sorry` are in prober files." Precommit it so the measurement can refute it. |
| **Observe** | Measure with an instrument that cannot lie the way the last one did. Not grep over source — a lexer. Not `curl` exit codes — HTTP status. |
| **Orient** | When the measurement contradicts the prediction, the prediction is what moves. Three predictions were refuted in this work; see §6. |
| **Decide** | Choose the arm that **fails closed** on the real property, not the arm that is easy to write. |
| **Act** | Change one plane at a time, typecheck after each, keep the pre-change bytes. |
| **Verify** | Both planes run; the driver compares; a negative control proves the check can fail. |
| **Reflect** | Record what the instrument got wrong, additively, in the artifact itself. The comment that explains a removal is worth more than the removal. |

---

## 4. The procedure

### Phase 1 — Inventory, and distrust the inventory

```bash
# count files with real IO in theorem-bearing files
grep -lE 'IO\.Process\.|IO\.FS\.' formal/lean/*.lean | xargs -r grep -lE '^theorem '
```

Then **immediately** ask what that grep cannot see. It cannot distinguish a proof term from a docstring. It cannot distinguish code from a comment describing removed code. Write the lexer before trusting any count.

### Phase 2 — Build the substrate before the first oracle

One shared module with **three kinds of check kept apart**:

- `algebra(name, ok)` — re-evaluates what Lean proves. Failure ⇒ **DIVERGENT**.
- `world(name, ok)` — model vs live system. Failure ⇒ **WORLD_FAIL**, an ordinary outage.
- `observe(name, raw)` — records that the world could be *looked at*. Empty ⇒ **BLIND**.

Plus the three that stop the common lies:

- `world_or_blind(name, present, ok)` / `world_json(name, flag, expected)` — **an absent field is not a false field.**
- `world_count(name, observed, expected)` — count the enumeration; never trust a summary integer to agree with the list beside it.
- `mutation_probe(name, wrong_is_rejected)` — the negative control. An oracle that cannot fail is theatre.

Verdict lattice, worst wins:

```
PASS(0) < BLIND(1) < WORLD_FAIL(2) < DIVERGENT(3) < VACUOUS(4) < LEAN_FAIL(6) < UNRUN(7)
```

`VACUOUS` is checked **first**, because a blind oracle's other verdicts are worthless. `BLIND` is *a started observer that got no evidence*; `UNRUN` is *an observer that never started* — it cannot emit its own verdict, so the launcher must classify it.

### Phase 3 — One oracle per subject, deriving not transcribing

The oracle must **re-derive** the algebra from the spec, independently. If it transcribes the Lean model into Mojo, a shared wrong mapping passes both languages and the pair proves nothing. This is not hypothetical: deriving instead of transcribing is what caught a wrong ownership model that had already been written into both planes.

Each oracle declares its own `formal/lean/<Subject>.lean` in its header, and the driver discovers pairs by reading that string — so the mapping lives in one place and cannot drift out of sync with the files.

### Phase 4 — The boundary arm, built on ordering not names

```
G3a  HARD, no exemption: no IO and no `def main` BEFORE the last theorem.
G3b  a file whose IO sits AFTER its theorems is a TRAILING RENDERER and must be
     DECLARED with a stated sanction; undeclared fails; over-budget fails.
```

**Why ordering is sound:** Lean requires declaration before use, so a theorem at line 205 cannot reference a definition at line 266. One syntactic fact therefore carries the semantic property that matters — *no observation in this file can be an input to any proof in it.*

**Why not a name allowlist:** an allowlist says a file is trusted, not *why*, and nothing re-checks the why. A declared manifest whose every entry is re-verified against the scanner each run is a different object: the sanction is checked, not asserted.

### Phase 5 — Wire it where it fails closed

```
driver → preflight arm → gate. Only PASS passes.
BLIND and UNRUN are nonpassing by design.
```

If the arm is behind a flag, say so plainly — a gate nobody reaches is not a gate.

---

## 5. Fractal RCA template

Apply at every layer; the shape repeats.

```
L0 constitutional — does the change touch an invariant, a ceiling, an authority?
L1 atomic        — the single predicate, the single field lookup
L2 component     — one oracle, one twin
L3 transaction   — one differential run
L4 system        — the driver, the preflight arm
L5 cognitive     — the prediction that was refuted, and why I believed it
L6 ecosystem     — the other planes (Gleam, OCaml, JSON) that assert the same counts
L7 federation    — remote nodes the oracle probes
L8 evolutionary  — what the next instance of this defect will look like
L9 sovereign     — who may admit it; and the answer is never the tool that found it
```

For each finding, five questions, in order:

1. **What was observed**, verbatim, with the command that observed it?
2. **What did the instrument claim**, and *could the instrument have been wrong*?
3. If the instrument was wrong, **what class of instrument error** is it — and does that class have other instances in the tree *right now*?
4. **What fails closed** after the fix, and what is the negative control that proves it can fail?
5. **What is still unmeasured**, named as `BLIND`/`UNRUN`/`UNKNOWN` rather than omitted?

Question 3 is the one that pays. Three separate false positives in this work were one class — *prose describing removed code scored as present code* — and the first two were "fixed" by tightening a regex, which is how the third survived in the one place the regex had not been touched.

---

## 6. TPS / Jidoka: the andon pulls, recorded

A **Jidoka stop** is pulled when an instrument is found lying, not when a subject is found broken. Each of these stopped the work until the instrument was rebuilt:

| Pull | What lied | Fix | Generalisation |
|---|---|---|---|
| 1 | "18 of 20 `sorry` are in prober files" | Zero `sorry` proof terms exist; the grep matched the *word* in docstrings and `=PASS` banners | A metric can measure boasts about rigour instead of rigour. The 18/20 "correlation" was an artifact: files printing PASS are exactly the files boasting "0 sorry". |
| 2 | A clean file flagged `BOUNDARY VIOLATION` | Its comment said "this file has no `IO.Process`" | Prose describing absence read as presence |
| 3 | Same, again, with the member-access dot present | Regex "tightening" is a narrower guess, not a fix | **Build the lexer** |
| 4 | Same, a third time, in the driver | The one place the regex had not been touched | There must be exactly ONE thing that knows how to read the language, and everything else asks it |
| 5 | Six "outages" on a healthy node | Probe asked `"k":true`; gateway emits `"k": true` | An absent field scored as a false field. Return **three** values: 1 / 0 / −1-absent, and let the type forbid the confusion |
| 6 | `curl -s` exit 0 on HTTP 500 | Read the **status**, not the exit code | An exit code is not a verdict |
| 7 | Preflight FAIL on correct state | The arm compared an ignore-aware VCS listing against an ignore-unaware `find`; all 9 "untracked" files were build artifacts already ignored | **A guard that fails on correct state teaches people to ignore it** — which is strictly worse than no guard |
| 8 | A negative control that restated the model | `mutation_probe` must mutate a **real input** | A control that cannot fail is not a control |

**Muda eliminated:** four regexes replaced by one lexer; a name allowlist replaced by a checked manifest; a receipt-overwrite removed (it destroyed the prior run's evidence, which `INV-PROV-03` forbids).

**Poka-yoke added:** three-valued field lookup; counted cardinalities; the plane supplied by the recording method rather than by the check's name.

---

## 7. Naming and ontology: measure before you unify

This is where the method earns its keep, because two "drifts" were my own measurement artifacts:

- I was about to canonise `THM_<FAM>_<nn>_<claim>` tree-wide. Census: **185 of 1,493** theorems use it. It is the **minority** regime, and the one that puts an opaque family code where the claim already is. A mass rename would have been churn in the wrong direction.
- I then counted ~146 "information-free" names from prefix shapes `t<n>_`, `T<n>_`, `c<n>_`. Exact count of names that are **only** an index: **zero**. Every one carries its claim after the index. There was no defect.

**The rule, therefore:** state the rule both regimes already satisfy — *a theorem name states its claim* — and guard against regression. A regression guard for a property the tree already has is honest; a cleanup announcement for a defect that was never there is not.

**Where unification stops:** `INV-PROV-03` — historical names are never retroactively changed. Four namespace roots are cited by immutable journals and the ZK/wiki corpus; renaming them would dangle those citations. They are **declared** in the manifest, not rewritten. Three roots whose references were confined to live source authored in the same work *were* renamed. The line is: **rename what only live code sees; declare what history has already cited.**

---

## 8. The checklist, as obligations

These carry their real state. `UNRUN`, `UNKNOWN`, `STALE`, `BLIND`, `NOT_ADMITTED` remain nonpassing.

<details><summary>Domain 1 — Metadata, timestamp, navigation</summary>

- [ ] **CHK-01-TIME** — prefix read from `date -u` immediately before the write, never extrapolated. *(This prompt's own first filename carried an invented prefix and was corrected; the failure is recorded rather than hidden.)*
- [ ] **CHK-02-TAIL** — full Tailnet links, and their live serving state stated separately
- [ ] **CHK-03-FRACT** — `L0..L9` tagged and actually mapped
- [ ] **CHK-04-KM** — spec, wiki, ZK and journal reconciled

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [ ] **CHK-05-MUDA** — exclusions verified against candidate dependencies
- [ ] **CHK-06-GRAPH** — pure BEAM/Hermes graph boundary
- [ ] **CHK-07-DRIVE** — `HARD_DENIED_SYSTEM_OS_SERIAL` preserved; interlocks tested only in scope

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — applicable surfaces
- [ ] **CHK-09-MATH** — the four declared gates, measured
- [ ] **CHK-10-9MOD** — unit, system, TDD, BDD, performance, scalability, property, fuzz, chaos
- [ ] **CHK-11-REGR** — regressions plus bounded observation

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — observed OTP supervision behaviour
- [ ] **CHK-13-HERMES** — bounded analysis, authoritative evidence
- [ ] **CHK-14-ZIGVM** — deterministic execution, descriptor-relative VFS
- [ ] **CHK-15-MAX** — actual isolated inference when applicable
- [ ] **CHK-16-OTEL** — clock plus nonzero trace/span identity

</details>
<details><summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — candidate-bound independent review; authorised admission
- [ ] **CHK-18-JJ** — standalone JJ, source ownership, exact candidate identity

</details>
<details><summary>Domain 6 — Provenance</summary>

EV ceiling 93. `EV-94..109` `NOT_ADMITTED`. No new EV number minted.

</details>

---

## 9. Precommitted forecast, for Brier scoring

Record these *before* the next run, so they can be scored rather than remembered favourably.

| # | Claim | p |
|---|---|---|
| F1 | The ordering argument (§4) survives peer review without a counterexample in Lean 4 | 0.70 |
| F2 | The next false positive in this system is again an instrument error, not a subject error | 0.80 |
| F3 | At least one declared renderer in the manifest acquires new IO within 30 days and the budget arm catches it | 0.35 |
| F4 | The cockpit `status:"unavailable"` while answering 7/7 routes is a reporting defect, not an outage | 0.65 |
| F5 | The KM census delta (2,609 measured vs 1,727 declared) resolves as a scope difference, not a corpus change | 0.75 |

---

## 10. What this prompt does not grant

A passing differential is evidence that a model and a concrete evaluation agree **at one candidate**. It is not admission, not a release gate, not a Sa-plan completion, and not a statement about any other candidate. A refusal proves the guard fired, not that the guarded operation works. Sa-plan remains the sole execution authority.

**UOS footer:** [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist) · document evidence does not grant system admission. EV ceiling 93.
