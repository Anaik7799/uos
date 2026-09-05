# Continuation Plan: Formal Methods Across the Evidence Fractal

**Date:** August 8, 2026
**Purpose:** concrete, executable specs for the requested formal-analysis
techniques, written so a fresh session can implement them without re-deriving
the design.

Each entry states what the technique computes *here*, why that is defensible in
this system, and what would make it decoration. The last part matters: several
of these can be name-dropped without doing anything, and a fake result in an
evidence store is worse than no result.

## Done

| Technique | Where | What it proves |
|---|---|---|
| STPA | `fractal_diagnostic.ml` hazards | 1 system hazard, 11 unsafe control actions, 8 realising H-1 |
| FMEA | same | failure mode, effect if undetected, current detection per hazard |
| Z3 | `dependency_smt.ml` | the L2 graph admits a build order (95 slices, 93 edges), independently of the traversal |
| OTel | `fractal_diagnostic.ml` | OTLP log records, coordinates as attributes |
| Fractal RCA | `fractal_diagnostic.ml` | level × origin classification, tested |

## 1. Fractal algebra — `parity_algebra.ml`

**Computes:** the composition law by which evidence at level N+1 yields a
verdict at level N. An L1 family is verified exactly when all its required L2
slices are; an L2 slice when all its L3 contracts are checked *and* it has an
L6 receipt; and so on down.

**Why defensible:** this law is currently implicit, scattered across
`parity_tracker` and the reporting code. Written as an algebra it becomes
property-testable: associativity of combination, identity (an empty family is
not verified — the vacuous-truth trap), monotonicity (adding evidence never
lowers a verdict), and absorption (one unverified required child forces the
parent unverified).

**Spec:**
```ocaml
type verdict = Unmapped | Blocked | Verified | Divergent
val combine : verdict -> verdict -> verdict   (* commutative, associative *)
val identity : verdict                        (* Unmapped, NOT Verified *)
val roll_up : required:bool -> verdict list -> verdict
```
Laws to property-test: commutativity, associativity, `combine identity v = v`,
`roll_up ~required:true [] = Unmapped` (never Verified — vacuous truth is how
an empty catalog reports 100%), absorption of `Divergent`, monotonicity.

**Decoration risk:** defining an algebra that merely restates the existing
if-chain. It earns its place only if the laws are property-tested and at least
one law contradicts the current implementation.

## 2. Ruliological rule-space exploration — `normalizer_rulespace.ml`

**Computes:** exhaustive enumeration of normalizer configurations over the
declared volatile-path set (2^n subsets), classifying each by which divergences
it would hide.

**Why defensible:** the normalizer is the one component that can manufacture
parity, and its safety depends entirely on which paths are declared volatile.
Exploring the rule space finds configurations that are *unsafe* — those that
equate documents differing at a semantically load-bearing path. This is genuine
combinatorial exploration of a rule space, and it answers a real question:
"which elisions would hide a real divergence?"

**Spec:**
```ocaml
val subsets : string list -> string list list
val classify : volatile:string list -> corpus:(Yojson.Safe.t * Yojson.Safe.t) list
            -> [ `Safe | `Hides_divergence of string ]
val unsafe_configurations : unit -> (string list * string) list
```
Run over a corpus of (reference, deliberately-diverged) pairs. Any configuration
that equates a pair which differs at a non-volatile path is unsafe. Assert the
*current* configuration is safe, and report which additions would break it.

**Decoration risk:** enumerating subsets and printing them. It earns its place
only if it flags at least one plausible-but-unsafe configuration.

## 3. Rete-UL diagnosis network — `diagnosis_rete.ml`

**Computes:** forward-chaining inference over accumulated diagnostics, deriving
conclusions no single diagnostic contains.

**Why defensible:** individual diagnostics are already good. What is missing is
*pattern* diagnosis: three Environment failures across different scenarios in
one run is an environment problem, not three capture problems; an Evidence
failure immediately after a normalizer change implicates the change, not the
fixture. Those are joins over facts, which is what Rete is for.

**Keep it in the harness fractal.** `agent/hermes_rete.ml` models the agent
runtime; reusing it here would conflate the two fractals (R9).

**Spec:**
```ocaml
type fact = Fractal_diagnostic.t
type conclusion = { rule : string; message : string; supporting : fact list }
val rules : (string * (fact list -> conclusion option)) list
val infer : fact list -> conclusion list
```
Starting rules: `environment-instability` (≥3 Environment across ≥2 nodes),
`evidence-after-normalizer-change` (Evidence origin + normalization differs from
recorded), `unanalysed-cluster` (≥2 diagnostics with empty hazard — the analysis
is out of date), `control-fault-invalidates-run` (any Control origin ⇒ every
verdict in the run is suspect).

**Decoration risk:** a rule engine with one rule that a match expression would
express. It earns its place only for conclusions requiring joins across facts.

## 4. Stan reliability model — `hazard_reliability.stan`

**Computes:** posterior credible intervals on the *escape probability* of each
hazard's detection, given observed fuzz and chaos outcomes.

**Why defensible:** the suites currently report "120 corrupted fixtures, all
refused". That is evidence of detection but says nothing quantitative about the
next corruption. A Beta-Binomial posterior turns it into a bounded claim: with
120/120 detections and a Jeffreys prior, the 95% upper bound on escape
probability is roughly 2.4%. That is an honest statement of how much the tests
actually buy, and it makes the case for more trials where the bound is weak.

**Spec:** per hazard, `trials` and `escapes` from the suites, model
`escapes ~ binomial(trials, theta)` with `theta ~ beta(0.5, 0.5)`. Report the
posterior mean and 95% upper bound per hazard. Fail the build if any H-1 hazard
has an upper bound above a declared threshold — that is the actionable output.

**Feed it real counts.** cmdstan is vendored under `vendor/cmdstan`. The OCaml
side must emit the observed counts from actual suite runs; hand-written counts
would make the posterior fiction.

**Decoration risk:** running Stan on invented data. It earns its place only if
the counts come from instrumented suite runs and the threshold can fail a build.

## 5. Fractal atlas and ontology — extend `fractal_catalog.ml`

**Computes:** the evidence fractal as an explicit graph (atlas) over a typed
vocabulary (ontology), so the structure is queryable rather than implied by
table joins.

**Why defensible:** L0–L2 are already persisted as `fractal_node`. L3–L6 are
not: contracts, fixtures, traces and receipts live in their own tables with no
node identity. Giving them node identity makes "show the evidence path from this
receipt up to the product" one traversal instead of four joins, and makes a
broken chain visible as a missing edge.

**Spec:** extend `Fractal_catalog` to emit L3–L6 nodes from the contract
catalog, scenarios, trace pairs and verifications; add `node_edge` with
`derives_from` / `evidences` relations; assert every L6 receipt has a path to
L0, and that no level is skipped.

## Ordering

1 and 5 first: they are pure, self-contained, and everything else reports
against them. Then 3 (consumes diagnostics), then 2 (needs a diverged corpus,
which arrives with the first real comparison), then 4 (needs instrumented counts
from stable suites).

## Standing constraint

Every item above must satisfy R7: unit, feature, TDD, BDD, property, fuzz,
chaos, structure. An analysis without a chaos layer has not been battle-tested,
and an analysis nobody can break is one nobody has tried to break.
