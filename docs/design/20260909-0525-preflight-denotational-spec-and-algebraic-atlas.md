# 20260909-0525 — Toolchain Preflight: Denotational Specification & Algebraic Atlas

#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l7 #zero-muda #km-triad #algebraic-atlas #denotational-intent #formal-lean4 #stamp-stpa #toolchain

**UOS / Design / Formal Specification** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)
**Contract:** `SC-NIX-DEVENV-001`, `SC-TOOLCHAIN-INPROJECT-001`
**Live document:** [http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0525-preflight-denotational-spec-and-algebraic-atlas.md](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0525-preflight-denotational-spec-and-algebraic-atlas.md)

**Artifacts specified here**

| Layer | Artifact |
|---|---|
| Denotational core (pure) | `engines/hermes/modules/hermes_toolchain/preflight_algebra.{ml,mli}` |
| Executable law suite | `engines/hermes/modules/hermes_toolchain/test_preflight_algebra.ml` — 27 laws |
| Lean 4 proofs | `formal/lean/Preflight_Verdict_Algebra.lean` — no `sorry`, axiom audit printed |
| Temporal model | `formal/quint/preflight_receipt.qnt` — Apalache `NoError` |
| Effectful shell | `tools/preflight` |
| Wiring | `uos-cli gate G-PREFLIGHT`, `var/preflight/*.json`, agent hooks |

---

## 1. Why a denotational treatment at all

Three passes of this work produced the same defect three times in different clothes:

| Pass | Observable used | What it could not distinguish |
|---|---|---|
| 1 | `erlang:system_info(otp_release)` | pinned 29.0.5 from unpinned 29.0.6 |
| 2 | `test -x` | a working binary from a broken one |
| 3 | exit status | doing the job from doing nothing |

Each was the obvious API. Each was **coarser than the property being enforced**. A checklist of "don't use the coarse API" does not survive the next API, because the failure is not a coding habit — it is a missing semantics. If the meaning of an observation is never written down, every new check re-invents it and re-discovers the same gap.

So the split enforced here is:

$$\text{shell} : \text{World} \rightarrow \text{Observation} \qquad\qquad \llbracket \cdot \rrbracket : \text{Observation} \rightarrow \text{Verdict}$$

`tools/preflight` decides **what was observed**. `Preflight_algebra` decides **what that means**. Only the second half is provable, and it is proved.

## 2. Semantic domain

$$\mathcal{V} = \{\, \mathsf{Pass} \,\} \cup \{\, \mathsf{Fail}(\phi) \mid \phi \in \text{Finding}^{*} \,\}$$

ordered $\mathsf{Fail} < \mathsf{Pass}$, with meet

$$
v_1 \sqcap v_2 =
\begin{cases}
\mathsf{Pass} & v_1 = v_2 = \mathsf{Pass}\\
\mathsf{Fail}(\phi) & \{v_1,v_2\} = \{\mathsf{Pass}, \mathsf{Fail}(\phi)\}\\
\mathsf{Fail}(\phi_1 \mathbin{+\!\!+} \phi_2) & v_i = \mathsf{Fail}(\phi_i)
\end{cases}
$$

$(\mathcal{V}, \sqcap, \mathsf{Pass})$ is a **bounded commutative idempotent monoid** — a meet-semilattice with top $\mathsf{Pass}$ and absorbing $\mathsf{Fail}$.

**There is deliberately no $\mathsf{Unknown}$.** An absent, unreadable, or unparseable observation denotes $\mathsf{Fail}$. Because $\mathsf{Fail}$ absorbs, one unknown anywhere sinks the composite. *Fail-closed is therefore a theorem about the absorbing element, proved once* — not a discipline re-applied at every call site and forgotten at one of them.

Commutativity holds **on the observable**, not on the nose: $\phi_1 \mathbin{+\!\!+} \phi_2 \neq \phi_2 \mathbin{+\!\!+} \phi_1$, so the law is stated as $\mathsf{isPass}(v_1 \sqcap v_2) = \mathsf{isPass}(v_2 \sqcap v_1)$. Swapping two arms cannot change whether the run passed, only the order failures are reported. Associativity *does* hold on the nose, because `++` is associative.

## 3. Observations and their denotations

### 3.1 Useability

$$\text{Execution} ::= \mathsf{NotExecutable} \mid \mathsf{ExitedNonzero}(n) \mid \mathsf{ExitedZeroSilent} \mid \mathsf{ExitedZeroWithOutput}(s)$$

`ExitedZeroSilent` is a **distinct constructor** from `ExitedZeroWithOutput`. That distinction is the whole point: a zero-byte file with the execute bit set is a valid empty shell script — it exits 0 and prints nothing. Collapsing the two into "success" is what let a broken `npm` report itself healthy.

A probe declares its expectation, $\epsilon \in \{\mathsf{SilentOk}, \mathsf{OutputRequired}\}$:

$$
\llbracket \text{obs} \rrbracket_\epsilon =
\begin{cases}
\mathsf{Pass} & \text{obs} = \mathsf{ExitedZeroWithOutput}(\_)\\
\mathsf{Pass} & \text{obs} = \mathsf{ExitedZeroSilent},\ \epsilon = \mathsf{SilentOk}\\
\mathsf{Fail} & \text{otherwise}
\end{cases}
$$

$\mathsf{SilentOk}$ is granted only to tools that legitimately say nothing (`erlc`, `quint typecheck`), and each carries a **separate artefact assertion** — `erlc` must leave a real `.beam` behind.

### 3.2 Locality

$$\llbracket \text{loc} \rrbracket = (\text{entrypoint} \sqsubseteq \text{root}) \sqcap \neg\!\!\bigvee_{p \in B}(\text{resolved} \sqsubseteq p)$$

The asymmetry is the **honest boundary**: the entrypoint must be ours; where it *resolves* may be `/nix/store`, because Nix binaries carry absolute store paths in their RPATH and interpreter and cannot be relocated. $B$ bars `$HOME`, `/usr`, `/opt`, and the read-only evidence trees.

### 3.3 Tracking

$$\llbracket \text{track} \rrbracket = (\text{present} \setminus \text{tracked} = \emptyset) \sqcap (\text{tracked} \setminus \text{present} = \emptyset)$$

Both directions. `tracked` comes from the VCS, `present` from the filesystem; **neither alone is the property**, and a tracked-but-absent phantom is as much a defect as an untracked file.

### 3.4 Receipts

$$\mathsf{valid}(r, t, \alpha, c, \tau) = \mathsf{isPass}(r.\text{status}) \sqcap \mathsf{fresh}(r,t,\alpha) \sqcap (r.c = c) \sqcap (r.\tau = \tau)$$

A cached verdict is evidence about **a specific checker reading a specific table**. Drop either digest and a cached $\mathsf{Pass}$ would lend its confidence to code it never examined. Freshness is a $\mathbb{N}$ comparison, which makes "stale" and "from the future" the same refusal rather than two cases.

## 4. Algebraic atlas: where this chart sits

The preflight occupies a chart in the property lattice, and the atlas records which rung each authority owns:

| Chart | Property | Checkable by | Authority |
|---|---|---|---|
| $U_{\text{id}}$ | exact store derivation | evaluation | `nix flake check`, `devenv test` |
| $U_{\text{loc}}$ | provenance of the path | inspection | `uos_toolchain_verify`, `beam_pin_check` |
| $U_{\text{par}}$ | two tables agree | text compare | `tool_table_parity` |
| $U_{\text{pre}}$ | entrypoint exists | `stat` | `uos_have` |
| $U_{\text{use}}$ | **the tool does its job** | **execution** | preflight arm 2 |
| $U_{\text{trk}}$ | **it is in the VCS** | **ask `jj`** | preflight arm 4 |

Transition morphism $\varphi: U_{\text{static}} \to U_{\text{dynamic}}$ is **not** an isomorphism, and that is the content of the atlas: every static chart is fully satisfiable by a binary that does not work. Negative test N5 exhibits the witness — a zero-byte executable inside `$UOS_ROOT` satisfies presence, locality and parity, and is caught only by $U_{\text{use}}$.

The gluing condition is exactly the meet: the global verdict on $\bigcup_i U_i$ is $\bigsqcap_i v_i$, and §5 proves this agrees with "every chart passes".

## 5. Proof obligations and where each is discharged

| Obligation | Discharged by | Status |
|---|---|---|
| $\sqcap$ associative | `Verdict.meet_assoc` (Lean) + L1 | **PROVED** / 27-law suite |
| $\sqcap$ commutative on the observable | `meet_comm_isPass` + L2 | **PROVED** |
| $\sqcap$ idempotent, $\mathsf{Pass}$ identity | `meet_idem_isPass`, `meet_pass_{left,right}` + L3, L4 | **PROVED** |
| $\mathsf{Fail}$ absorbs ⇒ fail-closed | `fail_absorbs_{left,right}` + L5 | **PROVED** |
| composite passes iff all arms pass | `meetAll_isPass_iff_all` + L6 | **PROVED** |
| one failing arm sinks the run | `meetAll_fails_of_mem_fail` + L26 | **PROVED** |
| findings accumulate | L7 (OCaml) | **LAW** (Lean states the algebra, not the ordering) |
| silent-zero ≠ success | L9 | **LAW** |
| digest change voids a receipt | `checker_change_invalidates`, `table_change_invalidates` + L23 | **PROVED** |
| cached FAIL never valid | `cached_fail_never_valid` + L24 | **PROVED** |
| validity antitone in age | `fresh_antitone` + L21 | **PROVED** |
| no stale/foreign accept **across interleavings** | `preflight_receipt.qnt` `inv_all` | **Apalache `NoError`** (bounded) |

**Axiom audit** is printed at check time: every theorem depends only on `propext` and `Quot.sound`. No `sorryAx`, no declared axiom, no Mathlib.

## 6. What is NOT claimed

Stated plainly, because a formal result that oversteps its invocation carries no authority under canonical policy §7:

1. **Nothing here proves the shell observes correctly.** Whether `erl` ran, and what it printed, is empirical evidence from `tools/preflight` — not a theorem. The proofs are about meaning.
2. **The Quint result is bounded**, not universal. `NoError` at the default depth is a bounded model-check, not an inductive invariant proof.
3. **A passing preflight is not admission.** It is evidence the toolchain works. It does not complete a Sa-plan task, and it grants no deploy authority.
4. **`Silent_ok` is a trust decision, not a derivation.** Granting it to a tool is a judgement that its silence is legitimate; the accompanying artefact assertion is what makes that judgement checkable.

## 7. Mutation evidence

Laws that have never failed are decoration. Each was killed on purpose:

| Mutation | Killed |
|---|---|
| M1 — `Exited_zero_silent, Output_required ↦ Pass` (re-introduce the npm defect) | L9 only |
| M2 — `Fail f, Fail _ ↦ Fail f` (drop finding accumulation) | L7 only |
| M3 — drop `r.checker == checkerNow` from Quint `valid` | `inv_no_foreign_accept` violated |
| M4 — drop the age bound from Quint `valid` | `inv_no_stale_accept` violated |

Each mutation kills exactly the law that names it, and no other — the suite is neither vacuous nor over-coupled.

---

**Related:** [[wiki:20260909-0525-uos-toolchain-preflight-guide]] · [[zk:20260909-0525-adr-096-toolchain-preflight-denotational-semantics-and-verdict-algebra]] · [[wiki:20260908-1345-uos-intent-based-config-and-algebraic-atlas-guide]]
**UOS footer:** `nas-1.tail55d152.ts.net:4100` · OTP 29 pinned at `…-erlang-29.0.5` · Sa-plan is the sole execution authority; this specification grants no admission.
