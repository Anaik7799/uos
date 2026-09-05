(* The fractal ontology: what exists in this system, at which level, governed
   by which algebra, and how each engineering aspect is addressed.

   This is data, not prose, for one reason: prose cannot be tested for gaps. An
   ontology written as a document drifts the moment a component is added, and
   nobody notices. Written as a total function from component to aspect
   coverage, a gap becomes a failing test.

   The enforcement rule is fail-closed. Every component must say something
   about every aspect. "Not applicable" is permitted but must carry a reason,
   because an unexamined aspect and a deliberately-excluded one look identical
   from outside, and only one of them is safe.

   Two fractals exist in this repository and are never mixed (rule R9). This
   ontology describes the EVIDENCE fractal in `hermes_harness/`. The runtime
   fractal in `agent/` has its own ontology, and a node in one has no meaning
   in the other. *)

(* ---------------------------------------------------------------- levels *)

type level = L0_product | L1_family | L2_capability | L3_contract | L4_fixture
           | L5_trace | L6_receipt | LX_control

let level_name = function
  | L0_product -> "L0/product"
  | L1_family -> "L1/family"
  | L2_capability -> "L2/capability"
  | L3_contract -> "L3/contract"
  | L4_fixture -> "L4/fixture"
  | L5_trace -> "L5/trace"
  | L6_receipt -> "L6/receipt"
  (* The control plane is not a level of the evidence chain; it is the
     machinery that builds it. Conflating the two is how a harness bug gets
     recorded as a parity finding. *)
  | LX_control -> "LX/control-plane"

let levels =
  [ L0_product; L1_family; L2_capability; L3_contract; L4_fixture; L5_trace;
    L6_receipt; LX_control ]

(* --------------------------------------------------------------- aspects *)

(* The engineering dimensions every component must address. Structural,
   control, data and observability are the classical four; the rest are the
   system-engineering properties that decide whether this survives contact with
   real use, plus the two lifecycle dimensions. *)
type aspect =
  | Structural     (* what it is composed of, and what composes it *)
  | Control        (* what drives it, and what it drives *)
  | Data           (* what it reads and writes, and where that lives *)
  | Observability  (* how a failure inside it becomes visible *)
  | Performance    (* cost per unit of work, and what dominates it *)
  | Scalability    (* what happens as the catalog or corpus grows *)
  | Availability   (* what happens when a dependency is absent *)
  | Integrity      (* how it prevents recording something unverified *)
  | Security       (* what it trusts, and what it must not *)
  | Sdlc           (* how a change to it is made and reviewed *)
  | Sre            (* how it is operated, and what an operator does on failure *)

let aspect_name = function
  | Structural -> "structural"
  | Control -> "control"
  | Data -> "data"
  | Observability -> "observability"
  | Performance -> "performance"
  | Scalability -> "scalability"
  | Availability -> "availability"
  | Integrity -> "integrity"
  | Security -> "security"
  | Sdlc -> "sdlc"
  | Sre -> "sre"

let aspects =
  [ Structural; Control; Data; Observability; Performance; Scalability;
    Availability; Integrity; Security; Sdlc; Sre ]

(* A coverage claim. [Addressed] states how; [Not_applicable] states why. The
   distinction is the whole point: silence is not permitted. *)
type coverage = Addressed of string | Not_applicable of string

let coverage_text = function Addressed text -> text | Not_applicable text -> text

(* --------------------------------------------------------------- algebra *)

(* Every component names the algebra that governs how its values compose. A
   component whose composition is unspecified is one whose behaviour under
   aggregation is nobody's decision, which is where roll-up bugs live. *)
type algebra = {
  carrier : string;        (* the set of values *)
  operation : string;      (* how two values combine *)
  identity : string;       (* the neutral value, or why there is none *)
  laws : string list;      (* the equations that must hold *)
  absorbing : string;      (* the dominating element, or "none" *)
}

type component = {
  id : string;
  level : level;
  module_path : string;
  purpose : string;
  algebra : algebra;
  coverage : (aspect * coverage) list;
}

(* ------------------------------------------------------------ components *)

let digest_algebra name =
  { carrier = "SHA-256 digests over " ^ name;
    operation = "equality; digests do not combine, they witness";
    identity = "none - a digest of nothing is not a unit, it is a digest of the empty input";
    laws = [ "determinism: same input, same digest"; "collision-resistance assumed" ];
    absorbing = "none" }

let components =
  [ { id = "inventory";
      level = LX_control;
      module_path = "modules/hermes_harness/inventory.ml";
      purpose = "deterministic digest of the frozen reference tree";
      algebra =
        { carrier = "sorted (path, domain, digest) entries";
          operation = "concatenation under path order, then SHA-256";
          identity = "the empty entry list, digesting the empty string";
          laws = [ "order-independence of input: sorting is applied first";
                   "determinism: the same tree yields the same digest" ];
          absorbing = "none" };
      coverage =
        [ (Structural, Addressed "a flat entry list over the frozen tree, excluding .git and build outputs");
          (Control, Addressed "invoked by verify and by capture; never self-triggering");
          (Data, Addressed "reads external/hermes_source; writes nothing");
          (Observability, Addressed "returns Error with the offending path; no partial scans");
          (Performance, Addressed "one sha256 subprocess per file; dominated by process spawn, ~8.5k files");
          (Scalability, Addressed "linear in file count; the frozen tree does not grow");
          (Availability, Addressed "a missing root is Error, never an empty inventory");
          (Integrity, Addressed "symlinks are skipped rather than followed, so the digest cannot be inflated from outside the tree");
          (Security, Addressed "reads only; never executes anything from the reference");
          (Sdlc, Addressed "changing the exclusion list changes every downstream digest and must be deliberate");
          (Sre, Addressed "if the digest changes unexpectedly, the snapshot moved; do not re-pin without understanding why") ] };
    { id = "evidence_store";
      level = LX_control;
      module_path = "modules/hermes_harness/evidence_store.ml";
      purpose =
        "append-only, snapshot-bound record of what was checked, with a read-only immutable import planner";
      algebra =
        { carrier = "immutable rows keyed by (snapshot, entity, revision)";
          operation = "insert-if-identical; a divergent payload is rejected";
          identity = "the empty store";
          laws = [ "idempotence: replaying an identical row is a no-op";
                   "immutability: a key never changes payload";
                   "monotonicity: rows are only ever added";
                   "import noninterference: planning opens source and target read-only";
                   "import content binding: canonical logical-store and plan digests change when a non-key payload changes";
                   "import conflict preservation: a shared key with different payload blocks admission" ];
          absorbing = "a rejected divergent replay aborts the whole transaction" };
      coverage =
        [ (Structural, Addressed "one table per evidence kind, keyed by snapshot digest");
          (Control, Addressed "written only by admitted verify/capture paths; evidence_import is plan-only until Run_swarm_bridge admission");
          (Data, Addressed "SQLite under state/; import planning opens source and target READONLY and computes typed deltas");
          (Observability, Addressed "every store failure names the table/key; import plans expose canonical digests plus missing, target-only, conflict, pass, and fail counts");
          (Performance, Addressed "batched inserts in one transaction; 301 links commit together");
          (Scalability, Addressed "row count grows with snapshots x capabilities; indexes are the primary keys");
          (Availability, Addressed "a missing operational database is created; a missing import source or malformed schema refuses rather than becoming an empty store");
          (Integrity, Addressed "every immutable table rejects same-key/different-payload replay (R3)");
          (Security, Addressed "no credentials are stored; the OpenRouter key is never persisted");
          (Sdlc, Addressed "schema changes are additive; import requires exact relevant-schema agreement and tests preserve failed verdicts");
          (Sre, Addressed "on conflict, do not delete rows: the conflict is the finding; historical receipts never become current credit") ] };
    { id = "capability_catalog";
      level = L2_capability;
      module_path = "modules/hermes_harness/capability_catalog.ml";
      purpose = "the 95 source-anchored capability slices and their dependency graph";
      algebra =
        { carrier = "a directed acyclic graph over semantic keys";
          operation = "topological order by depth-first postorder";
          identity = "a slice with no dependencies";
          laws = [ "acyclicity, proved independently by z3";
                   "every dependency resolves to a declared slice";
                   "order is deterministic: catalog order breaks ties" ];
          absorbing = "a cycle, which makes the order undefined and is rejected" };
      coverage =
        [ (Structural, Addressed "95 slices under 18 families, each anchored to frozen paths");
          (Control, Addressed "drives Sa-plan task order and the implementation sequence");
          (Data, Addressed "pure OCaml values; no external state");
          (Observability, Addressed "a cycle names the trail; an unknown dependency names the key");
          (Performance, Addressed "O(V+E) traversal over 95 nodes and 93 edges; negligible");
          (Scalability, Addressed "z3 encoding is linear in edges and stays trivial at this size");
          (Availability, Addressed "no dependencies; always available");
          (Integrity, Addressed "every anchor is asserted to exist in the frozen snapshot, fail-closed");
          (Security, Not_applicable "pure data with no external input and no trust boundary");
          (Sdlc, Addressed "adding a slice requires an anchor that exists and a dependency that resolves");
          (Sre, Addressed "not an operational component; changes land through review only") ] };
    { id = "gospel_contracts";
      level = L3_contract;
      module_path = "modules/hermes_harness/contract_catalog.ml + gospel_check.ml";
      purpose = "Gospel-specified interfaces and their verifier receipts";
      algebra =
        { carrier = "declaration x (harness revision, verifier) -> verdict";
          operation = "receipts accumulate; only `checked` grants credit";
          identity = "no receipt, which is not a pass";
          laws = [ "a declaration is stable per snapshot";
                   "receipts keyed by revision and verifier coexist";
                   "unavailable never overwrites checked" ];
          absorbing = "rejected, for that revision and verifier" };
      coverage =
        [ (Structural, Addressed "declaration table plus receipt table, split so observation and property do not collide");
          (Control, Addressed "verify invokes gospel per contract; capture does not");
          (Data, Addressed "capability_contract and capability_contract_receipt");
          (Observability, Addressed "gospel-lint names cause, construct and fix; receipts record the verifier");
          (Performance, Addressed "one gospel process per contract, each parsing the stdlib; ~1s each");
          (Scalability, Addressed "linear in contracts; the stdlib parse dominates and is per-process");
          (Availability, Addressed "absent gospel yields unavailable, never checked (R2)");
          (Integrity, Addressed "a tooling gap is never recorded as a rejection (HZ-L3-01)");
          (Security, Addressed "gospel runs on a temp copy so it cannot write into the tree");
          (Sdlc, Addressed "every .mli is linted before commit (R8)");
          (Sre, Addressed "if every contract reports unavailable, the toolchain moved; check the switch pin") ] };
    { id = "reference_capture";
      level = L4_fixture;
      module_path = "modules/hermes_harness/reference_capture.ml";
      purpose = "harness-controlled capture of frozen-reference traces";
      algebra =
        { carrier = "(scenario, snapshot) -> trace, digest-pinned";
          operation = "capture then save; load re-derives the digest";
          identity = "no fixture, which is an error rather than an empty trace";
          laws = [ "pinning: a different snapshot is a different fixture";
                   "verification: a recorded digest must match its own trace";
                   "idempotence: recapture is byte-identical" ];
          absorbing = "any capture failure, which yields no fixture at all" };
      coverage =
        [ (Structural, Addressed "scenarios as OCaml values; fixtures as digest-named JSON");
          (Control, Addressed "a deliberate command, never a side effect of verify");
          (Data, Addressed "writes hermes_harness/fixtures/reference_traces, committed");
          (Observability, Addressed "seven distinct failure constructors, each mapped to a hazard");
          (Performance, Addressed "one subprocess per scenario, ~200ms; 120s deadline");
          (Scalability, Addressed "linear in scenarios; fixtures are small and committed");
          (Availability, Addressed "absent interpreter, adapter or reference each fail closed (HZ-CAP-01)");
          (Integrity, Addressed "an edited fixture is refused; the digest is re-derived, never trusted (HZ-FIX-01)");
          (Security, Addressed "the adapter makes no decisions and knows nothing about the candidate");
          (Sdlc, Addressed "the adapter is a declared exception with recorded reasoning (R1)");
          (Sre, Addressed "provision state/reference_env; a hung reference is killed on deadline") ] };
    { id = "parity_normalizer";
      level = L5_trace;
      module_path = "modules/hermes_harness/parity_normalizer.ml";
      purpose = "canonical form for comparing reference and candidate traces";
      algebra =
        { carrier = "JSON documents modulo declared volatile paths";
          operation = "normalize then compare rendered form";
          identity = "the identity normalizer, eliding nothing";
          laws = [ "idempotence: normalizing a normal form changes nothing";
                   "key order is erased; array order is preserved";
                   "elision only at declared paths" ];
          absorbing = "none - normalization never collapses two documents to a constant" };
      coverage =
        [ (Structural, Addressed "a recursive fold over JSON with a path context");
          (Control, Addressed "invoked by capture and by comparison; never standalone");
          (Data, Addressed "pure; the declared volatile set is part of recorded evidence");
          (Observability, Addressed "describe() names the version and the full volatile set");
          (Performance, Addressed "linear in document size; no backtracking");
          (Scalability, Addressed "traces are small; depth is bounded by the reference shape");
          (Availability, Not_applicable "pure function with no external dependency");
          (Integrity, Addressed "over-elision is the one way to manufacture parity, so elision is never inferred (HZ-NRM-01)");
          (Security, Not_applicable "no trust boundary; operates on already-captured data");
          (Sdlc, Addressed "widening the volatile set invalidates existing fixture digests, by design");
          (Sre, Addressed "if every comparison fails, check for an undeclared volatile field before widening (HZ-NRM-02)") ] };
    { id = "parity_compare";
      level = L6_receipt;
      module_path = "modules/hermes_harness/parity_compare.ml";
      purpose = "compare the candidate against pinned reference traces and record receipts";
      algebra =
        { carrier = "(reference, candidate) -> Verified | Divergent | Blocked";
          operation = "normalize both, compare, classify";
          identity = "no scenarios, which rolls up to Unmapped for a required node";
          laws = [ "a present pair is Verified or Divergent, never Unmapped";
                   "a divergence is Implementation origin and denies credit";
                   "a missing fixture or unmapped scenario blocks, never denies" ];
          absorbing = "Divergent, via the parity algebra roll-up" };
      coverage =
        [ (Structural, Addressed "one comparison per scenario, rolled up by the parity algebra");
          (Control, Addressed "a deliberate command; writes receipts, never part of verify");
          (Data, Addressed "reads pinned fixtures and the live candidate; writes parity_verification");
          (Observability, Addressed "every divergence emits a fractal diagnostic naming both digests");
          (Performance, Addressed "one candidate build and two normalizations per scenario; trivial");
          (Scalability, Addressed "linear in scenarios; the corpus is small and committed");
          (Availability, Addressed "a missing fixture blocks that scenario without failing the run");
          (Integrity, Addressed "only a proved divergence between present traces denies credit (R5)");
          (Security, Addressed "the candidate is pure OCaml; no external input crosses the comparison");
          (Sdlc, Addressed "candidate builds are faithful to each scenario and never tuned to pass");
          (Sre, Addressed "a divergence is the expected first result; do not widen the normalizer to clear it") ] };
    { id = "parity_algebra";
      level = L6_receipt;
      module_path = "modules/hermes_harness/parity_algebra.ml";
      purpose = "roll evidence up the fractal into a verdict";
      algebra =
        { carrier = "Unmapped | Blocked | Verified | Divergent";
          operation = "semilattice join on severity";
          identity = "Verified as the join identity; Unmapped as the EMPTY roll-up";
          laws = [ "commutative"; "associative"; "idempotent";
                   "Divergent absorbs"; "empty required roll-up is Unmapped, not Verified" ];
          absorbing = "Divergent" };
      coverage =
        [ (Structural, Addressed "a four-element lattice; the whole state space is enumerable");
          (Control, Addressed "consumes receipts and diagnostics; drives reported parity");
          (Data, Addressed "pure values only; reads and writes nothing outside its arguments");
          (Observability, Addressed "report carries counts, so a verdict never hides its denominator");
          (Performance, Addressed "linear fold; 100k children tested");
          (Scalability, Addressed "chaos-tested at 100k children without overflow");
          (Availability, Not_applicable "pure function with no external dependency");
          (Integrity, Addressed "the empty required case is Unmapped, blocking vacuous 100%");
          (Security, Not_applicable "consumes only verdicts already validated upstream; no untrusted input crosses it");
          (Sdlc, Addressed "laws are property-tested exhaustively over the lattice");
          (Sre, Addressed "a family at 94/95 is not verified; read the verdict, not the percentage") ] };
    { id = "fractal_diagnostic";
      level = LX_control;
      module_path = "modules/hermes_harness/fractal_diagnostic.ml";
      purpose = "fractally contextual, OTel-compliant diagnosis";
      algebra =
        { carrier = "(fractal level, RCA origin, parity impact, hazard)";
          operation = "classification; diagnostics do not combine, they accumulate";
          identity = "no diagnostic, meaning nothing was observed";
          laws = [ "only Implementation origin may deny credit (R5)";
                   "classification is total and deterministic";
                   "an unnamed hazard renders UNANALYSED" ];
          absorbing = "a Control origin, which makes every verdict in the run suspect" };
      coverage =
        [ (Structural, Addressed "level x origin x impact, plus the hazard it realises");
          (Control, Addressed "emitted by every subsystem; consumed by reporting and by Rete diagnosis");
          (Data, Addressed "OTLP log records; coordinates as attributes, not prose");
          (Observability, Addressed "this IS the observability component; it is itself fuzz-tested against hostile content");
          (Performance, Addressed "allocation-only; no I/O in construction");
          (Scalability, Addressed "records are independent; export batches them under one resource");
          (Availability, Not_applicable "pure construction; export is the caller's concern");
          (Integrity, Addressed "an Environment failure can never be recorded as a defect (R5)");
          (Security, Addressed "messages may carry hostile content, so JSON encoding is fuzz-tested");
          (Sdlc, Addressed "a new failure mode without a hazard is visible as UNANALYSED (R6)");
          (Sre, Addressed "filter on hermes.fractal.level and hermes.rca.origin; ERROR means a proved divergence") ] };
    { id = "dependency_smt";
      level = LX_control;
      module_path = "modules/hermes_harness/dependency_smt.ml";
      purpose = "independent proof that the capability graph admits a build order";
      algebra =
        { carrier = "integer ranks over capability keys";
          operation = "conjunction of rank(dependent) > rank(dependency)";
          identity = "the empty constraint set, trivially satisfiable";
          laws = [ "sat iff acyclic - a standard result, not a heuristic";
                   "the encoding shares no code with the traversal" ];
          absorbing = "unsat, which is a proved cycle" };
      coverage =
        [ (Structural, Addressed "one integer variable per slice, one constraint per edge");
          (Control, Addressed "run by its test; not part of verify");
          (Data, Addressed "reads the catalog directly, not a copy");
          (Observability, Addressed "four outcomes, each with a distinct description");
          (Performance, Addressed "QF_LIA over 95 vars and 93 constraints; milliseconds");
          (Scalability, Addressed "linear encoding; QF_LIA is decidable and fast at this scale");
          (Availability, Addressed "a missing solver is Solver_missing, never a proof (R2)");
          (Integrity, Addressed "proves a property of the real catalog, not of a restatement");
          (Security, Addressed "z3 reads a temp file and returns sat/unsat; output is validated");
          (Sdlc, Addressed "cross-checked against the traversal, so the two must agree");
          (Sre, Not_applicable "development-time analysis, not an operational path") ] };
    { id = "ocaml_only_guard";
      level = LX_control;
      module_path = "modules/hermes_harness/ocaml_only_guard.ml";
      purpose = "enforce that the harness is written in OCaml";
      algebra =
        { carrier = "workspace paths -> violations";
          operation = "scan; violations accumulate";
          identity = "a clean workspace, yielding no violations";
          laws = [ "declared exceptions are exempt and carry reasons";
                   "data roots are exempt: the rule is about authorship" ];
          absorbing = "any violation, which fails the suite" };
      coverage =
        [ (Structural, Addressed "a recursive walk with an exemption list and a declared-exception list");
          (Control, Addressed "run by its test against the real repository");
          (Data, Addressed "reads the tree; writes nothing");
          (Observability, Addressed "each violation names the path and the reason");
          (Performance, Addressed "one tree walk; vendored trees are skipped wholesale");
          (Scalability, Addressed "skipping data roots keeps it off the 780MB reference");
          (Availability, Not_applicable "reads only the local tree it is testing; a missing tree fails the test, which is the correct outcome");
          (Integrity, Addressed "fails closed: an undeclared match is a violation even when harmless");
          (Security, Addressed "detects a python shebang on any file, not just .py");
          (Sdlc, Addressed "this is the SDLC control; adding Python requires a written reason");
          (Sre, Not_applicable "development-time control, not an operational path") ] };
    { id = "resource_envelope";
      level = LX_control;
      module_path = "modules/hermes_harness/resource_envelope.ml";
      purpose = "fail-closed preflight that checks every resource before an operation consumes it";
      algebra =
        { carrier = "resource checks (resource, met, detail)";
          operation = "conjunction: an envelope is satisfied only when every check is met";
          identity = "the empty envelope, which is trivially satisfied";
          laws = [ "fail-closed: an unknown or mismatched observation is unmet";
                   "a space check needs both the proportional margin and the absolute floor";
                   "a shortfall blocks credit, never denies it" ];
          absorbing = "any unmet check, which fails the whole envelope" };
      coverage =
        [ (Structural, Addressed "a pure evaluate over (resource, observation) plus a single IO observe; a check pairs a resource with its verdict");
          (Control, Addressed "run before an operation (compare, capture) and refuses on any shortfall before the work begins, never mid-run");
          (Data, Addressed "reads free space via df, PATH and file metadata; writes nothing; the verdict is a pure function of the gathered facts");
          (Observability, Addressed "each shortfall becomes a fractal diagnostic on the OTLP path, naming the resource, the margin and the floor");
          (Performance, Addressed "one df subprocess per space check plus cheap stat/access probes; negligible beside the operation it guards");
          (Scalability, Addressed "linear in the number of declared resources; envelopes are small and composed per operation");
          (Availability, Addressed "an unknowable resource (df fails, a path is absent) is Unknown and therefore unmet; availability is never assumed");
          (Integrity, Addressed "fail-closed: unknown or mismatched observations are unmet, so the preflight cannot wave through a resource it did not confirm");
          (Security, Addressed "treats df as an oracle whose output is validated; runs no untrusted input and grants no capability, only refuses");
          (Sdlc, Addressed "adding a resource kind requires a classification in to_diagnostics, enforced by the structure test, so no kind stays unclassified");
          (Sre, Addressed "a refusal names the resource, the shortfall and the fix; the operator frees space or redirects TMPDIR and retries") ] };
    { id = "blueprint";
      level = LX_control;
      module_path = "modules/hermes_harness/blueprint.ml";
      purpose = "declarative intent: desired fractal verdicts reconciled against actual evidence";
      algebra =
        { carrier = "directives (target, desired verdict, intent, requires)";
          operation = "reconcile: per-directive diff of desired against actual in the parity lattice";
          identity = "the empty blueprint, which reconciles to converged vacuously and asserts nothing";
          laws = [ "report-only: reconcile never grants credit, it only names drift";
                   "a drift's diagnostic follows the actual verdict's origin (R5 respected)";
                   "the requires graph is acyclic, validated fail-closed" ];
          absorbing = "any drift, which leaves the loop unconverged" };
      coverage =
        [ (Structural, Addressed "typed IO-free directives -- the seed pattern; intent mirrored in comments");
          (Control, Addressed "consumed by reconcile_blueprint and Harness_config.Reconcile; never self-executing");
          (Data, Addressed "pure values in; the actual verdicts come from the caller (evidence roll-up)");
          (Observability, Addressed "every drift is a fractal diagnostic on the standard OTLP path");
          (Performance, Addressed "linear in directives; validation is a topo-sort over a small graph");
          (Scalability, Addressed "blueprints stay small (tens of intents); ordering is O(V+E)");
          (Availability, Not_applicable "pure function of its arguments; no external dependency");
          (Integrity, Addressed "report-only by construction: reconcile cannot write evidence or grant credit (R10)");
          (Security, Not_applicable "no trust boundary; consumes verdicts already validated upstream");
          (Sdlc, Addressed "a new intent requires substantive rationale, a resolvable target and an acyclic requires -- validate fails closed");
          (Sre, Addressed "the reconciliation summary is the operator's drift report; converged means intent is met") ] };
    { id = "harness_config";
      level = LX_control;
      module_path = "modules/hermes_harness/harness_config.ml";
      purpose = "the declarative configuration grammar and activity algebra: what the harness does, composed";
      algebra =
        { carrier = "activity ASTs; outcomes in the parity verdict lattice";
          operation = "Seq/Par fold outcomes with the evidence join; Gate is fail-closed sequencing";
          identity = "Verified for non-empty composition; the EMPTY composite is Unmapped (vacuous-truth guard)";
          laws = [ "commutative/associative/idempotent join; Divergent absorbs";
                   "Gate(a,b): b runs only when a grants credit";
                   "Annotate is outcome-transparent: intent never changes semantics";
                   "plan is total and pure: it executes nothing" ];
          absorbing = "Divergent, exactly as in the evidence roll-up" };
      coverage =
        [ (Structural, Addressed "a typed AST of seven primitives and four combinators; drivers bind primitives to subsystems");
          (Control, Addressed "this IS the control grammar: it names and composes every activity the harness performs");
          (Data, Addressed "pure AST in; outcomes out; all IO lives behind the injected driver");
          (Observability, Addressed "execute returns the per-primitive outcome trail; failures surface as the subsystems' fractal diagnostics");
          (Performance, Addressed "interpretation is a linear walk; the work is in the driven subsystems");
          (Scalability, Addressed "configs are small ASTs; composition is structural, not quadratic");
          (Availability, Addressed "a missing subsystem surfaces as that primitive's Blocked verdict, never a silent skip");
          (Integrity, Addressed "empty composites are Unmapped, gates are fail-closed, and no outcome grants parity credit (R10)");
          (Security, Not_applicable "no untrusted input: configs are typed OCaml authored in-repo and reviewed");
          (Sdlc, Addressed "a new activity is a new constructor: the compiler forces plan, execute and the label total");
          (Sre, Addressed "the plan is the operator's dry-run; the outcome trail says exactly what ran and what it concluded") ] };
    { id = "hermes_rete";
      level = LX_control;
      module_path = "modules/hermes_harness/hermes_rete.ml";
      purpose = "forward-chaining production-rule engine: the fail-closed drift-diagnosis rule gate";
      algebra =
        { carrier = "facts (kind, attribute rows) and rules (pattern joins with variable bindings)";
          operation = "fire: match every rule's patterns over working memory, joining across patterns via bindings";
          identity = "the empty rule set, which accepts every working memory vacuously";
          laws = [ "zero-trust: the first Error action rejects the whole run, naming the rule";
                   "bindings join ACROSS patterns, never within one fact (checked in actions)";
                   "naive re-match per fire: honest about not being the Rete algorithm" ];
          absorbing = "an Error action, which rejects everything after it" };
      coverage =
        [ (Structural, Addressed "a faithful mirror of the zigvm rete.ml engine (R14), including its honest naming note");
          (Control, Addressed "fired by drift_rules over reconciliation output; the gate can reject the run");
          (Data, Addressed "in-memory working set only; facts are projected in, advice facts are read back");
          (Observability, Addressed "a rejection names the violated rule; advice facts carry target, action and detail");
          (Performance, Addressed "naive O(facts x rules) re-match: 0.35ms over 1000 facts, measured in bench_rules");
          (Scalability, Addressed "linear at harness volume (dozens of facts); a true Rete network is scoped only if volume grows");
          (Availability, Not_applicable "pure in-process values; no external dependency to be absent");
          (Integrity, Addressed "fail-closed by construction: gate rules reject rather than skip; tested with a corrupted reconciliation");
          (Security, Not_applicable "no untrusted input: facts are projected from typed harness values in-repo");
          (Sdlc, Addressed "rules are OCaml values reviewed like code; a new drift kind without a rule is caught by the drift tests");
          (Sre, Addressed "a gate rejection is the operator signal that the reconciliation itself is corrupt, not the candidate") ] };
    { id = "rust_rules";
      level = LX_control;
      module_path = "modules/hermes_harness/rust_rules.ml + rust/drift_engine";
      purpose = "the embedded Rust GRL rule engine (rust-rule-engine), integrated via FFI as an advisory cross-check";
      algebra =
        { carrier = "GRL rule sets and JSON fact objects crossing one C-ABI call";
          operation = "eval: parse GRL, execute over facts, return fired count and mutated facts";
          identity = "the empty rule set, which fires nothing and returns the facts unchanged";
          laws = [ "never raises: every failure is an Error value (the oracle discipline)";
                   "never panics across the FFI: the Rust side catches everything into {error}";
                   "ADVISORY ONLY: the lenient GRL parser accepts malformed rules silently (measured), so it can never be the fail-closed gate" ];
          absorbing = "an engine-reported error, which yields Error for the whole eval" };
      coverage =
        [ (Structural, Addressed "staticlib crate (rust/drift_engine) + one C stub + one external; JSON in, JSON out, serde tags untagged in OCaml");
          (Control, Addressed "called only from tests and cross-checks; the OCaml hermes_rete engine stays authoritative");
          (Data, Addressed "no state: each eval is a fresh knowledge base over the supplied facts");
          (Observability, Addressed "errors carry the engine's reason verbatim; fired/cycle counts are returned");
          (Performance, Addressed "~0.17ms per eval (GRL re-parse + JSON both ways), measured in bench_rules with result identity vs the OCaml engine");
          (Scalability, Addressed "linear in calls; a persistent-KB binding is the known optimization if volume grows");
          (Availability, Addressed "statically linked: present by construction; a null/panic reply degrades to an Error value");
          (Integrity, Addressed "admitted DIFFERENTIALLY: test_rust_rules proves agreement with the OCaml engine over the drift domain, and pins the lenient-parser finding");
          (Security, Addressed "the FFI boundary is one string call; hostile fact content is fuzz-crossed; the Rust side aborts on panic rather than corrupting");
          (Sdlc, Addressed "vendored deps + --offline cargo build inside dune: hermetic, reviewable, no network at build time");
          (Sre, Addressed "if the engines disagree, trust the OCaml verdict and treat the disagreement as the finding") ] };
    { id = "drift_rules";
      level = LX_control;
      module_path = "modules/hermes_harness/drift_rules.ml";
      purpose = "drift diagnosis: reconciliation output projected into the rule engine, advice out";
      algebra =
        { carrier = "drift/hazard/countermeasure facts in, advice facts out";
          operation = "project then fire: each drift joins the analysis tables through bindings";
          identity = "a converged reconciliation, which projects no drift and yields no advice";
          laws = [ "the consistency gate rejects a drift whose actual equals its desired verdict";
                   "every drift kind yields exactly one advice (auto-countermeasure suppresses the manual duplicate)";
                   "advice is deterministic and sorted; diagnosis never mutates the reconciliation" ];
          absorbing = "a gate rejection, which discards all advice" };
      coverage =
        [ (Structural, Addressed "the zigvm rete_rules projection discipline: typed harness values become facts, rules join them");
          (Control, Addressed "run by run_config after reconcile; its gate can reject a corrupted reconciliation");
          (Data, Addressed "reads Blueprint.reconciled, the hazard analysis and the countermeasure table; writes nothing");
          (Observability, Addressed "advice lines name target, action and detail; printed in the run_config trail");
          (Performance, Addressed "a handful of rules over tens of facts; microseconds beside the pipeline it advises");
          (Scalability, Addressed "linear in drifts; rule count grows only with drift KINDS, which are the verdict lattice");
          (Availability, Not_applicable "pure projection over in-process values; nothing external to be absent");
          (Integrity, Addressed "advises only -- it cannot touch verdicts or evidence, and its gate fails closed");
          (Security, Not_applicable "inputs are typed reconciliation values produced in-process; no trust boundary");
          (Sdlc, Addressed "a new drift verdict without a diagnosis rule fails the drift tests, not silence");
          (Sre, Addressed "the advice IS the runbook: fix-candidate, capture-and-compare, or the named countermeasure") ] };
    { id = "hermes_zenoh";
      level = LX_control;
      module_path = "modules/hermes_harness/hermes_zenoh.ml";
      purpose = "mesh telemetry publisher: sweeps/alerts to zenoh topics via the vendored zenoh-c FFI (c3i zenoh-module mirror, R14)";
      algebra =
        { carrier = "publish attempts: (key, payload) -> Ok or Error detail";
          operation = "fire-and-forget puts; attempts do not compose -- each is witnessed by its own result";
          identity = "none -- publishing nothing is the absence of an attempt, not a unit";
          laws = [ "system-to-system only: intra-process composition stays pure function calls (the algebra IS the proof)";
                   "published data is observation or advice, never authority -- the store remains the only source of parity truth";
                   "fail-open at call sites: an unreachable router degrades to a printed note, never a failed run";
                   "a publisher's key is concrete: wildcards are rejected before the wire";
                   "client mode only: an absent router fails fast, never drifts into peer scouting" ];
          absorbing = "none -- one failed publish never poisons another" };
      coverage =
        [ (Structural, Addressed "one C stub (hz_stubs.c) over the vendored prebuilt libzenohc.a -- the drift_engine foreign-archive discipline; pure OCaml validation before the FFI");
          (Control, Addressed "HERMES_ZENOH=0 opts out (reported, not silent); HERMES_ZENOH_ENDPOINT overrides the router; no new external tool -- FFI, not subprocess");
          (Data, Addressed "publishes rendered sweeps and worst-alerts at hermes/control/*; reads nothing; writes nothing to the store");
          (Observability, Addressed "every call site prints published-to-key or the failure detail -- telemetry about the telemetry");
          (Performance, Addressed "one session open/put/close per run (milliseconds against the local router); zero cost when disabled");
          (Scalability, Addressed "one put per surface per run; the mesh fans out to any number of subscribers without harness changes");
          (Availability, Addressed "chaos-tested: a closed port returns a typed Error fast (client mode, no scouting) and the run continues");
          (Integrity, Addressed "cannot mutate verdicts, receipts, or intent; subscribers get copies, never the record (the two-lattice law)");
          (Security, Addressed "connects only to the explicitly configured local endpoint; publishes derived telemetry, never fixtures or reference content");
          (Sdlc, Addressed "TDD stub-RED first; 14 checks: pure key rules, chaos unreachable-router, explicit-opt-out, live mesh leg (disclosed skip when the router is down)");
          (Sre, Addressed "the pager path: P0/P1 alerts reach the mesh the c3i cockpit and RETE rules already watch") ] };
    { id = "control_plane";
      level = LX_control;
      module_path = "modules/hermes_harness/control_plane.ml";
      purpose = "the full-fractal controller sweep: one control leg per fractal level, composed per entry point, unsensed levels named";
      algebra =
        { carrier = "legs (level x alert) and sweeps (legs + unsensed reasons)";
          operation = "worst over the legs' alerts -- inherited from the homeostasis join";
          identity = "the empty sweep, whose worst is Green";
          laws = [ "each leg is a pure total function of one real signal";
                   "a level without a live sensor appears in unsensed with its reason -- never silently omitted";
                   "regressions dominate: any regressed scenario makes L1 P0 and the sweep's worst P0";
                   "no leg reads or writes a parity verdict; the two lattices meet only at read-only observation and exit codes (R10)" ];
          absorbing = "a P0 leg, which stops the line through the exit teeth" };
      coverage =
        [ (Structural, Addressed "seven leg constructors (L0 frontier, L1 regressions, L2 flaps, L3 oracle, L4 currency, L6 coverage, LX envelope) + sweep composition");
          (Control, Addressed "every entry point (compare, run_config, auto_converge) composes its sweep and exits 2 on P0; the dashboard composes the store-only subset");
          (Data, Addressed "inputs are the store's receipt history, evolution trajectory, latest revision, and per-run corpus facts; writes nothing");
          (Observability, Addressed "render emits one aligned line per leg plus one per unsensed level -- the sweep IS the loop's health surface");
          (Performance, Addressed "folds over receipt history (hundreds of rows); immeasurable beside one compare");
          (Scalability, Addressed "linear in history length; legs are independent and could parallelize if ever needed");
          (Availability, Addressed "a missing store degrades telemetry legs to empty windows (Green -- absence is not a violation); the loop's own refusal stays with R13");
          (Integrity, Addressed "pure over pinned inputs; cannot mutate verdicts, receipts, or intent -- the forbidden alert-to-verdict morphism does not typecheck here");
          (Security, Not_applicable "consumes in-process typed values only; no trust boundary crossed");
          (Sdlc, Addressed "TDD stub-RED first (26 checks); the store-to-sensor law is pinned end-to-end in test_evidence_rollup");
          (Sre, Addressed "the graduated ladder per level: P0 stops the line, P1 names quarantine/runbook items (incl. the registry-drift sensor), P2 is lead-time advice") ] };
    { id = "homeostasis";
      level = LX_control;
      module_path = "modules/hermes_harness/homeostasis.ml";
      purpose = "pure control algorithms for the convergence loop: Lyapunov frontier descent, flap hysteresis, oracle circuit breaking (c3i controller mirror, R14)";
      algebra =
        { carrier = "graduated alerts Green < P2 < P1 < P0 over telemetry windows";
          operation = "worst: keep-highest-severity join, the control-plane twin of the parity combine";
          identity = "Green -- and the empty window is Green: absence of telemetry is never a violation";
          laws = [ "commutative, associative, idempotent; P0 absorbs";
                   "frontier: a strict shrink in recorded satisfied counts is P0, always (chaos-pinned)";
                   "monotone frontiers never alarm, so growing the blueprint cannot false-alarm";
                   "an open breaker never re-closes on its own -- re-closing is a deliberate human act";
                   "alerts advise and refuse only: no controller output can grant or deny parity credit (R10)" ];
          absorbing = "P0, which also carries the stop-the-line exit" };
      coverage =
        [ (Structural, Addressed "three pure controllers (frontier gate, flap sensor, breaker) behind one alert type; no IO in the module");
          (Control, Addressed "auto_converge runs the frontier gate after every loop and exits 2 on P0 or in-run Anomaly -- the exit teeth");
          (Data, Addressed "reads the store's recorded evolution trajectory and receipt windows; writes nothing, ever");
          (Observability, Addressed "describe renders every alert with its runbook hint in the loop's report");
          (Performance, Addressed "folds over windows of at most tens of observations; immeasurable beside one compare");
          (Scalability, Addressed "linear in window length and scenario count; breakers are O(1) per observation");
          (Availability, Addressed "store absent or unreadable degrades to Green with a printed note -- the c3i absence rule, fail-safe for a SENSOR (the loop's own preflights own refusal)");
          (Integrity, Addressed "pure over inputs the store already pinned; cannot mutate verdicts, receipts, or intent");
          (Security, Not_applicable "consumes in-process typed values only; no trust boundary crossed");
          (Sdlc, Addressed "TDD stub-RED first; unit + 600 property windows + 400 chaos injections pin every law above");
          (Sre, Addressed "the c3i P0/P1/P2/green severity ladder: P0 stops the line, P1 names a quarantine/runbook item, P2 is a note") ] };
    { id = "receipt_reliability";
      level = LX_control;
      module_path = "modules/hermes_harness/receipt_reliability.ml";
      purpose = "Bayesian reliability annotation over parity receipts: exact Beta-Binomial posteriors per fractal node";
      algebra =
        { carrier = "Beta posteriors over per-node pass probability";
          operation = "exact conjugate update: Beta(a,b) + k of n latest scenario verdicts -> Beta(a+k, b+n-k)";
          identity = "the uniform prior Beta(1,1), the posterior under zero evidence";
          laws = [ "pseudo-replication-safe: the observation unit is a scenario's LATEST verdict, never its correlated history";
                   "censoring: an unmeasured node is disclosed beside the table, never denominated";
                   "NO AUTHORITY: posteriors annotate; they never gate, decide, or move credit (R10)" ];
          absorbing = "none - evidence only sharpens a posterior, nothing collapses it" };
      coverage =
        [ (Structural, Addressed "the zigvm stan_bridge conjugate core mirrored exactly (R14); the closed form is the oracle a future MCMC sampler is admitted against");
          (Control, Addressed "read-only over Evidence_store.parity_results; surfaced by the stan_receipts command");
          (Data, Addressed "latest-per-scenario (contract, passed) rows in; posteriors and a censoring disclosure out");
          (Observability, Addressed "each node renders k/n, the posterior mean and the bounded 95% moment band");
          (Performance, Addressed "closed-form arithmetic; linear in receipts, microseconds");
          (Scalability, Addressed "per-node grouping over at most the scenario corpus; no sampling, no iteration");
          (Availability, Not_applicable "pure arithmetic over rows the caller supplies; nothing external to be absent");
          (Integrity, Addressed "advisory by construction: the module exposes no verdict type, so it cannot leak authority into the parity algebra");
          (Security, Not_applicable "consumes typed rows from the harness's own store; no trust boundary");
          (Sdlc, Addressed "the honest-units laws (pseudo-replication, censoring) are carried from zigvm W1-1/W1-2 and pinned in tests");
          (Sre, Addressed "a wide band is the true state of knowledge -- act on the verdicts, read the band for confidence") ] };
    { id = "irmin";
      level = LX_control;
      module_path = "modules/hermes_harness/sop_execution.ml";
      purpose = "branchable memory & CRDT state merging: versioned state trees, snapshots, and conflict-free data synthesis across agents";
      algebra =
        { carrier = "versioned state trees and CRDT state merges";
          operation = "3-way CRDT state merge and branching commit history";
          identity = "empty root snapshot tree";
          laws = [ "branching determinism: parent and commits yield identical merge";
                   "associativity and commutativity of CRDT state merge" ];
          absorbing = "unreconcilable conflict forces explicit branch isolation" };
      coverage =
        [ (Structural, Addressed "versioned commit graph with parent pointers and key-value state trees");
          (Control, Addressed "agents commit state snapshots on task completion and merge branch histories");
          (Data, Addressed "reads and writes branch state trees in memory; immutable commits");
          (Observability, Addressed "commit hashes and merge results are logged in temporal history");
          (Performance, Addressed "fast in-memory structural sharing; microsecond commit times");
          (Scalability, Addressed "handles arbitrary branch depth and parallel agent commits");
          (Availability, Addressed "missing branch degrades to default initial state snapshot");
          (Integrity, Addressed "cryptographic commit hashing guarantees history immutability");
          (Security, Not_applicable "in-process data structure; no external network boundary");
          (Sdlc, Addressed "unit tested with 3-way merge laws and branch divergence checks");
          (Sre, Addressed "divergent branch heads produce explicit merge conflict records") ] };
    { id = "eio";
      level = LX_control;
      module_path = "modules/hermes_harness/sop_execution.ml";
      purpose = "effects-based non-blocking concurrent I/O: fiber management and direct-style asynchronous effect handling across agents";
      algebra =
        { carrier = "concurrent fiber effect computations and I/O handlers";
          operation = "fiber spawn and structured effect composition";
          identity = "noop fiber returning empty unit";
          laws = [ "structured concurrency: parent fiber awaits all child fibers";
                   "effect cancellation propagation across fiber hierarchies" ];
          absorbing = "unhandled fiber exception cancels child fiber subtree" };
      coverage =
        [ (Structural, Addressed "Eio fiber effect handlers for non-blocking I/O and task dispatch");
          (Control, Addressed "spawns fibers per agent step action with effect handler interception");
          (Data, Addressed "buffers input/output payloads through effect events without blocking");
          (Observability, Addressed "effect traces record payload reads, telemetry writes, and fiber yields");
          (Performance, Addressed "lightweight fibers with microsecond context switch overhead");
          (Scalability, Addressed "scales to thousands of concurrent fibers per domain");
          (Availability, Addressed "fiber failures trigger parent context cancellation and error capture");
          (Integrity, Addressed "structured fiber scope guarantees no leaked active fibers");
          (Security, Not_applicable "in-process effect handlers; safe concurrency model");
          (Sdlc, Addressed "verified via fiber concurrency test suites and effect trace assertions");
          (Sre, Addressed "fiber panics capture stack traces and trigger controlled cancellation") ] };
    { id = "ruliad";
      level = LX_control;
      module_path = "modules/hermes_harness/ruliad.ml";
      purpose = "multiway-system exploration: causal invariance, build-order spaces, and the memoized state collapse";
      algebra =
        { carrier = "move systems (initial state, applicable moves, application) and their multiway graphs";
          operation = "explore: BFS to fixpoint over canonically-memoized states, then an exact path/depth DP";
          identity = "the terminal-only system: one state, one empty path, trivially confluent";
          laws = [ "confluence IS causal invariance: one terminal under every ordering";
                   "the detector can fire: a non-commutative system reports non-confluent (chaos-proven)";
                   "bounded honestly: a cap hit or a cycle is an Error, never truncation or a hang";
                   "irreducibility respected: orders are enumerated, the per-edge work is not shortcut (R10)" ];
          absorbing = "none - exploration only maps the space; nothing collapses it" };
      coverage =
        [ (Structural, Addressed "mirrors zigvm sm_reachable's BFS-and-signature discipline (R14) with HashLife-style canonical-key memoization");
          (Control, Addressed "driven by ruliad_frontier over the parity intent and the config fold; annotates, never gates");
          (Data, Addressed "pure over the supplied system; the live frontier reads the evidence roll-up for its initial state");
          (Observability, Addressed "reports states, edges, exact path counts, depth, terminals and confluence");
          (Performance, Addressed "memoization collapses factorial paths onto the state lattice: 362880 paths on 512 states in 1.6ms, measured");
          (Scalability, Addressed "bounded by max_states with a fail-closed Error; DP is linear in the deduped graph");
          (Availability, Not_applicable "pure exploration over in-process values; nothing external to be absent");
          (Integrity, Addressed "NO AUTHORITY is structural: the graph type carries no verdict; confluence findings annotate the z3-proved laws");
          (Security, Not_applicable "no untrusted input: systems are typed OCaml values authored in-repo");
          (Sdlc, Addressed "a new move system states its monotonicity; the cycle detector catches a violation as an Error in tests");
          (Sre, Addressed "the live frontier's next-move options are the operator's real choices; 30 build orders, all converging, means order is free") ] };
    { id = "quint_frontier";
      level = LX_control;
      module_path = "modules/hermes_harness/quint_specs/parity_frontier.qnt + test_quint_frontier.ml";
      purpose = "the quint differential: the frontier machine specified twice, verdicts compared";
      algebra =
        { carrier = "one state machine in two encodings: the .qnt spec and the OCaml transition system";
          operation = "differential: quint's bounded seeded verdict vs the OCaml exact-fixpoint verdict per invariant";
          identity = "agreement -- identical verdicts and a matching reachable signature";
          laws = [ "reqClosed (requires-closure) holds in both encodings";
                   "the FALSE invariant notConverged is Violated in both -- the checker provably checks";
                   "bounded-checker equivalence honestly: quint is bounded and seeded, the OCaml side is the exact finite fixpoint";
                   "an absent quint skips the differential with disclosure (R2), never fabricates a verdict" ];
          absorbing = "any verdict disagreement, which fails the law outright" };
      coverage =
        [ (Structural, Addressed "mirrors the zigvm quint-sm law shape (R14): .qnt artifact + OCaml system + verdict/signature comparison");
          (Control, Addressed "run as a fast suite; quint is invoked as an oracle with fixed steps/samples/seed");
          (Data, Addressed "reads the shared Parity_intent blueprint; the .qnt duplicates its DAG deliberately, as the independent encoding");
          (Observability, Addressed "the test prints the verdict pair and the signature size; a skip is disclosed, never silent");
          (Performance, Addressed "two quint invocations (~seconds) plus a 20-state exact exploration (microseconds)");
          (Scalability, Addressed "the machine grows with intents, not scenarios; quint sampling and the exact fixpoint both stay trivial at blueprint scale");
          (Availability, Addressed "quint absent => rc other than 0/1 => Unavailable => disclosed skip; the OCaml-side invariants still run");
          (Integrity, Addressed "the two encodings are maintained independently; drift between them is exactly what the differential exists to catch");
          (Security, Not_applicable "a local checker over an in-repo spec; no untrusted input crosses the boundary");
          (Sdlc, Addressed "changing the blueprint DAG requires updating the .qnt too -- a verdict/signature mismatch fails the suite, not silence");
          (Sre, Addressed "a disagreement means one encoding lies about the plan space; trust neither until the drift is explained") ] };
    { id = "fpp_model";
      level = LX_control;
      module_path = "modules/hermes_harness/fpp_model.ml";
      purpose = "the FPP (F Prime Prime) metamodel in OCaml: components, typed ports, C&DH dictionaries, state machines, topologies, and every semantic check the FPP spec mandates (imported 2026-08-08, docs/hermes/references/fprime-digest.md)";
      algebra =
        { carrier = "FPP models: typed component/port/instance/topology terms";
          operation = "validate: the conjunction of the spec's semantic checks; connections: direct graphs + pattern expansion";
          identity = "the empty model, which validates clean";
          laws = [ "passive components carry no async machinery; queued/active must (FPP-CMP-01/02)";
                   "names and identifiers are per-component dictionaries: distinct or rejected (FPP-CMP-03..09)";
                   "instance base-id ranges [base, base+span) are pairwise disjoint (FPP-INST-02), and the consecutive-gap criterion is Z3-proven to imply it";
                   "connections run output -> input over equal port types, one connection per output index (FPP-TOPO-02/03/04)";
                   "internal state machines have exactly one initial transition and an acyclic choice graph (FPP-SM-01/03)";
                   "emitters are fail-closed: an invalid model refuses to emit" ];
          absorbing = "any diagnostic -- one violation makes the model invalid" };
      coverage =
        [ (Structural, Addressed "pure data types mirroring the FPP construct inventory 1:1 (14 definitions, 18 specifiers, 11 state-machine elements); no IO");
          (Control, Addressed "validate gates the emitters; harness_topology gates its artifacts on validate = []");
          (Data, Addressed "reads nothing; emits FPP text and the JSON dictionary per the published dictionary spec");
          (Observability, Addressed "every violation is a fractal diagnostic at L3/contract with Specification origin and a named FPP-* check id");
          (Performance, Addressed "validation is a fold over the model; the 60-component chaos model validates in well under a second");
          (Scalability, Addressed "checks are per-component/per-pair; base-id disjointness is sorted-consecutive, O(n log n)");
          (Availability, Addressed "no external dependency: the solver leg lives in its own test, the module never needs one");
          (Integrity, Addressed "model diagnostics carry No_effect on parity -- a specification defect can never touch credit (R10); overflow-safe span arithmetic chaos-pinned near max_int");
          (Security, Not_applicable "consumes in-process typed values only; no trust boundary crossed");
          (Sdlc, Addressed "TDD stub-RED first; 64 checks: unit per FPP law, 200 generated models, 100 injected-defect mutations each caught by its own check");
          (Sre, Addressed "a validation failure names the component, the check id, and the fix; the dictionary is the operator's index of every opcode/id in the system") ] };
    { id = "harness_topology";
      level = LX_control;
      module_path = "modules/hermes_harness/harness_topology.ml";
      purpose = "the harness described AS an F Prime topology: eleven real components as FPP instances, the real dataflow as connection graphs, the converge loop as an FPP state machine, the two lattices as separate FPP enums";
      algebra =
        { carrier = "one concrete Fpp_model.model value describing this harness";
          operation = "ontology_gaps: the differential law against Fractal_ontology (instances registered; every direct connection over an ontology edge)";
          identity = "the empty gap list -- the two encodings agree";
          laws = [ "every instance is named after a registered ontology component";
                   "every direct connection lies over an ontology edge; pattern graphs are framework plumbing governed by the FPP checks instead";
                   "the two-lattice boundary is structural: no connection carries alerts into the evidence side, and Verdict/Alert are distinct FPP enums";
                   "the law can fail and tests prove it (meta-falsification both directions)";
                   "found live: the parity_compare -> evidence_store receipt flow had no ontology edge until this law demanded it" ];
          absorbing = "any gap -- one disagreement means an encoding is wrong" };
      coverage =
        [ (Structural, Addressed "pure data over fpp_model; instances/connections/machine mirror real modules only -- nothing aspirational");
          (Control, Addressed "harness_config is the single active component (the dispatcher); its ConvergeLoop machine is the real OODA loop with the R13 preflight gate and terminal Anomalous state");
          (Data, Addressed "reads Fractal_ontology (components + atlas) for the differential; emits the .fpp and dictionary atlas artifacts");
          (Observability, Addressed "gaps render as named sentences; FPP validity failures render as fractal diagnostics");
          (Performance, Addressed "eleven instances, thirteen direct connections; every check is milliseconds");
          (Scalability, Addressed "adding a component = one instance + its edges; the differential law immediately demands the ontology entry (R12 made executable)");
          (Availability, Addressed "no external dependency; the SMT leg discloses its own status separately");
          (Integrity, Addressed "describes, never actuates: no runtime behavior changes because the model says so; the model follows the code, gaps say which side lies");
          (Security, Not_applicable "a description of in-repo structure; no trust boundary crossed");
          (Sdlc, Addressed "TDD stub-RED first; 16 checks including both meta-falsification directions and the structural two-lattice law");
          (Sre, Addressed "the emitted dictionary gives operators the full command/event/telemetry index; SWEEP_P0 is FATAL and maps to the exit-2 stop-the-line response") ] };
    { id = "fpp_interp";
      level = LX_control;
      module_path = "modules/hermes_harness/fpp_interp.ml";
      purpose = "pure simulator for the executable FPP semantics: state-machine dispatch (exit -> do -> entry, guard gating, dropped unhandled signals, fuel-bounded choice resolution) and command dispatch with the assert/block/drop queue-full policies";
      algebra =
        { carrier = "machine states (current state + action log) and bounded queues";
          operation = "dispatch: one signal step per the FPP spec; send_command: opcode resolution through an instance's base-id window";
          identity = "the unhandled signal -- dropped, state unchanged, log untouched";
          laws = [ "exit before do before entry, pinned by action-log order";
                   "a guarded transition with a false guard is a drop, not an error";
                   "unknown signals and tampered states are caller errors, never silent";
                   "choice resolution is fuel-bounded: total even on unvalidated garbage";
                   "queue depth never exceeds capacity; drops are monotone (mutant-proven)";
                   "simulation only: nothing here actuates or touches parity (R10)" ];
          absorbing = "a terminal state -- every signal drops there (Anomalous is the harness's)" };
      coverage =
        [ (Structural, Addressed "two pure functions over fpp_model data plus a queue record; no IO");
          (Control, Addressed "drives nothing; the BDD runner and fuzz suites drive it");
          (Data, Addressed "reads model values; writes nothing");
          (Observability, Addressed "the action log is the trace: every executed action, in order");
          (Performance, Addressed "one list scan per dispatch; the 80-state ring does 500 steps in the chaos leg without effort");
          (Scalability, Addressed "linear in states/transitions per step; fuel bounds choice chains");
          (Availability, Addressed "no dependency; total on garbage (fuzz-pinned)");
          (Integrity, Addressed "cannot write evidence; errors on out-of-window opcodes exactly like CmdDispatcher");
          (Security, Not_applicable "in-process simulation of in-repo models; no trust boundary");
          (Sdlc, Addressed "TDD stub-RED first; 25 checks incl. the real ConvergeLoop OODA walk; a live mutant proof fixed the fuzz's own blind spot");
          (Sre, Addressed "lets an operator dry-run a workflow (signal script or opcode) against the model before touching the real harness") ] };
    { id = "fpp_usecases";
      level = LX_control;
      module_path = "modules/hermes_harness/test_fpp_usecases.ml";
      purpose = "the BDD catalog: 8 generic F Prime use cases on purpose-built models and 15 harness workflows mapped into FPP terms, executed by test_fpp_bdd against the real topology, dictionary, and ConvergeLoop machine";
      algebra =
        { carrier = "scenarios: Given prose + a model + typed When/Then steps";
          operation = "catalog concatenation (generic @ workflows); execution lives in the runner";
          identity = "the empty step list -- a scenario that asserts nothing";
          laws = [ "workflow scenarios run against the REAL Harness_topology.model, never a copy";
                   "read-only laws are asserted as ABSENCE: no CAPTURE opcode, no REPORT opcode";
                   "the two-lattice law appears as a scenario (no direct connection control -> evidence)";
                   "the coverage floor is enforced by the runner: >= 8 generic, >= 12 workflows" ];
          absorbing = "a failing step fails the scenario and the suite" };
      coverage =
        [ (Structural, Addressed "pure data: scenario records over fpp_model values; the runner owns all machinery");
          (Control, Addressed "executed by test_fpp_bdd; scenarios cannot execute themselves");
          (Data, Addressed "reads the harness model and its dictionary; writes nothing");
          (Observability, Addressed "every scenario prints its Given/When/Then walk; a failure names the exact step");
          (Performance, Addressed "23 scenarios, 85 steps, sub-second");
          (Scalability, Addressed "a new workflow is one scenario value; the floor check pulls the catalog forward");
          (Availability, Addressed "no dependency beyond the model; dictionary computed in-process");
          (Integrity, Addressed "asserts against the model and dictionary only; cannot touch stores or verdicts");
          (Security, Not_applicable "in-repo descriptions; no trust boundary");
          (Sdlc, Addressed "RED observed with the empty catalog (coverage floor); GREEN with 23 scenarios / 85 steps / 0 failures");
          (Sre, Addressed "the workflow scenarios ARE the operator's story cards: pipeline dispatch, R13 refusal, anomaly stop-the-line, divergence-as-measurement, health/time/telemetry patterns") ] };
    { id = "sop";
      level = LX_control;
      module_path = "docs/hermes/sop/";
      purpose = "Standard Operating Procedures defining multi-agent execution workflows and step sequences";
      algebra =
        { carrier = "procedure steps (step_id, action, state_transition)";
          operation = "sequence composition and parallel step branching";
          identity = "empty procedure step (no-op)";
          laws = [ "step determinism: unique step ordering within procedure";
                   "precondition satisfaction before step execution";
                   "fail-closed on unhandled step error" ];
          absorbing = "fatal procedure exception (workflow abort)" };
      coverage =
        [ (Structural, Addressed "SOP workflow steps defined as structured Markdown/SysML procedures");
          (Control, Addressed "invoked by agent workflows; dictates step transitions across 5 agent instances");
          (Data, Addressed "reads procedure documents and task context; emits status updates");
          (Observability, Addressed "step transitions and failures emit fractal diagnostics on OTLP path");
          (Performance, Addressed "O(N) step traversal; negligible overhead beside agent execution");
          (Scalability, Addressed "procedures scale linearly with task complexity; step evaluation is bounded");
          (Availability, Addressed "missing procedure file raises error and halts step execution");
          (Integrity, Addressed "procedure verification requires all steps and preconditions to be validated before execution");
          (Security, Addressed "procedure content is read-only and immutable during agent execution");
          (Sdlc, Addressed "SOP changes reviewed and versioned alongside mandatory rules");
          (Sre, Addressed "failed SOP step names offending step_id, error cause, and fallback runbook") ] };
    { id = "planning";
      level = LX_control;
      module_path = "modules/hermes_harness/sop_execution.ml";
      purpose = "Planning and scheduling engine coordinating step dependencies and resource allocations for multi-agent workflows";
      algebra =
        { carrier = "workflow plans (plan_id, goal, steps, dependencies)";
          operation = "sequential and topological step composition";
          identity = "empty plan (no steps)";
          laws = [ "dependency acyclicity: DAG ordering of plan steps";
                   "plan determinism: identical inputs yield identical plan graphs";
                   "fail-closed on unresolvable step dependency" ];
          absorbing = "invalid plan topology (plan abort)" };
      coverage =
        [ (Structural, Addressed "Planning scheduler and step dependency graph structure");
          (Control, Addressed "Schedules execution order of SOP steps across 5 discrete agent instances");
          (Data, Addressed "Reads goal parameters and dependency specs; emits scheduled step queues");
          (Observability, Addressed "Plan generation and step scheduling events emitted on OTLP path");
          (Performance, Addressed "Topological sort and DAG scheduling completed in O(V + E) time");
          (Scalability, Addressed "Scales linearly with plan step count and agent worker pool capacity");
          (Availability, Addressed "Missing plan dependency raises error and halts scheduled step execution");
          (Integrity, Addressed "DAG invariant checked prior to plan step dispatch to prevent deadlock");
          (Security, Addressed "Plans operate under read-only step definition rules without privilege escalation");
          (Sdlc, Addressed "Planning algorithms and scheduling policies version controlled and tested");
          (Sre, Addressed "Failed plan step scheduling logs dependency chain and offending step ID") ] };
    { id = "job_manager";
      level = LX_control;
      module_path = "modules/hermes_harness/sop_execution.ml";
      purpose = "Oban-equivalent job management and queue dispatch system for asynchronous task execution";
      algebra =
        { carrier = "async jobs (job_id, queue_name, payload, retry_count, state)";
          operation = "queue enqueue, dequeue, and priority sorting";
          identity = "empty job queue (idle state)";
          laws = [ "job uniqueness: unique job_id within queue state";
                   "retry monotonicity: retry count increments strictly until max retries";
                   "fail-closed on unhandled job exception" ];
          absorbing = "dead job queue state (poison pill event)" };
      coverage =
        [ (Structural, Addressed "Job queue data structures, worker domain pool, and priority dispatch queues");
          (Control, Addressed "Enqueues, schedules, and dispatches async tasks to 5 agent domains");
          (Data, Addressed "Persists job payloads and execution records in job queue state store");
          (Observability, Addressed "Job lifecycle events emitted to diagnostic log");
          (Performance, Addressed "Constant time O(1) job queue push and pop using priority heap structure");
          (Scalability, Addressed "Concurrent job execution scales across 5 discrete worker domain pools");
          (Availability, Addressed "Failed job retries automatically with exponential backoff up to limit");
          (Integrity, Addressed "Job state transitions enforced atomically via transactional queue state");
          (Security, Addressed "Job payloads sanitized and executed within worker domain sandbox boundary");
          (Sdlc, Addressed "Job manager behavior and queue semantics verified by automated unit tests");
          (Sre, Addressed "Poisoned jobs routed to dead-letter queue with diagnostic stack traces") ] };
    { id = "temporal";
      level = LX_control;
      module_path = "modules/hermes_harness/sop_execution.ml";
      purpose = "Temporal workflow orchestration engine for durable event-driven state machine checkpoints";
      algebra =
        { carrier = "workflow histories (event_id, event_type, checkpoint_state)";
          operation = "history replay and event append";
          identity = "initial workflow state (empty history)";
          laws = [ "history determinism: replay of identical history yields identical workflow state";
                   "checkpoint monotonicity: workflow state version increases monotonically";
                   "fail-closed on non-deterministic execution drift" ];
          absorbing = "unhandled workflow divergence (terminal fault)" };
      coverage =
        [ (Structural, Addressed "Durable workflow state machine, event history log, and timer mechanisms");
          (Control, Addressed "Orchestrates multi-agent execution steps with durable checkpoint recovery");
          (Data, Addressed "Appends event records to durable workflow history log");
          (Observability, Addressed "Workflow state changes and checkpoint events logged to diagnostic stream");
          (Performance, Addressed "Event history replay optimized with incremental state snapshots");
          (Scalability, Addressed "Supports arbitrary concurrent workflow instances across domain pool");
          (Availability, Addressed "Workflow state persisted across failures for seamless execution resume");
          (Integrity, Addressed "Deterministic replay validation prevents execution drift between runs");
          (Security, Addressed "Workflow history logs encrypted and protected against unauthorized mutation");
          (Sdlc, Addressed "Temporal state machine transitions unit-tested and formally verified");
          (Sre, Addressed "Workflow timeouts and stuck states trigger automatic alert sweeps") ] };
    { id = "agents";
      level = LX_control;
      module_path = ".agents/";
      purpose = "Agentic swarms and single workers executing the plan";
      algebra =
        { carrier = "prompts";
          operation = "compose";
          identity = "system prompt";
          laws = [ "mandatory rules override prompts" ];
          absorbing = "violation" };
      coverage =
        [ (Structural, Addressed "defined by AGENTS.md constraints");
          (Control, Addressed "OODA execution through prompts");
          (Data, Addressed "agent session state and progress logs written to .agents directory");
          (Observability, Addressed "agent execution status and heartbeat monitored via progress tracking");
          (Performance, Addressed "parallel domain execution bounded by OCaml domain pool capacity");
          (Scalability, Addressed "agent count scales dynamically from 1 to 5 worker domains");
          (Availability, Addressed "absent agent prompt degrades to safe default or halts execution");
          (Integrity, Addressed "agent state updates verified through transaction locks and ASSP protocol");
          (Security, Addressed "agents operate under strict read/write boundaries defined by workspace layout");
          (Sdlc, Addressed "agent role specifications version controlled and reviewed before deployment");
          (Sre, Addressed "agent failures logged to handoff reports with explicit error diagnostics") ] };
    { id = "skills";
      level = LX_control;
      module_path = ".agents/skills/";
      purpose = "Composable skill routines for agents";
      algebra =
        { carrier = "instructions";
          operation = "concat";
          identity = "empty";
          laws = [ "skills compose" ];
          absorbing = "error" };
      coverage =
        [ (Structural, Addressed "skills defined in SKILL.md files within .agents/skills/ directory");
          (Control, Addressed "skills supply domain instructions to guide agent step execution");
          (Data, Addressed "reads skill specification markdown files; produces no persistent state");
          (Observability, Addressed "skill loading and execution recorded in agent session logs");
          (Performance, Addressed "zero runtime overhead; skills loaded into agent memory at invocation");
          (Scalability, Addressed "skill tree expands additively with new domain skill packages");
          (Availability, Addressed "missing skill falls back to base agent operational instructions");
          (Integrity, Addressed "skill specifications validated against system rules and schema");
          (Security, Addressed "skills execute strictly within agent sandbox capabilities");
          (Sdlc, Addressed "skills versioned in repository under tracked .agents/skills path");
          (Sre, Addressed "malformed skill file fails preflight check before execution starts") ] };
    { id = "rules";
      level = LX_control;
      module_path = "docs/hermes/mandatory-rules.md";
      purpose = "Mandatory rule definitions";
      algebra =
        { carrier = "rule text";
          operation = "union";
          identity = "empty";
          laws = [ "rules restrict" ];
          absorbing = "violation" };
      coverage =
        [ (Structural, Addressed "mandatory rules defined in docs/hermes/mandatory-rules.md");
          (Control, Addressed "rules enforce invariant constraints that immediately abort violating runs");
          (Data, Addressed "immutable rule declarations loaded at harness startup time");
          (Observability, Addressed "rule violations emit fatal fractal diagnostics identifying rule ID");
          (Performance, Addressed "evaluated as constant time constraint checks prior to execution");
          (Scalability, Addressed "rule set remains static and compact during pipeline execution");
          (Availability, Addressed "missing rule file causes immediate fail-closed pipeline halt");
          (Integrity, Addressed "rules cannot be overridden or bypassed by agent prompts or skills");
          (Security, Addressed "enforces strict integrity and safety boundaries across all components");
          (Sdlc, Addressed "rule modifications require architecture review and formal verification");
          (Sre, Addressed "rule violation halts execution line with non-zero exit code") ] };
    { id = "superpowers";
      level = LX_control;
      module_path = "docs/superpowers/";
      purpose = "Advanced swarm/agent workflows";
      algebra =
        { carrier = "workflows";
          operation = "compose";
          identity = "empty";
          laws = [ "workflows compose" ];
          absorbing = "failure" };
      coverage =
        [ (Structural, Addressed "advanced workflows specified in docs/superpowers/ directory");
          (Control, Addressed "coordinates multi-agent interaction sequences and parallel execution");
          (Data, Addressed "reads workflow manifests and coordinates inter-agent state passing");
          (Observability, Addressed "workflow phase transitions and state changes reported to control plane");
          (Performance, Addressed "parallel execution optimizes multi-worker domain throughput");
          (Scalability, Addressed "supports complex composite workflows across multi-agent swarms");
          (Availability, Addressed "unsupported workflow step degrades gracefully to fallback procedure");
          (Integrity, Addressed "workflow execution verified against formal state machine specifications");
          (Security, Addressed "workflow actions checked against security policy before execution");
          (Sdlc, Addressed "superpower workflows developed, tested, and tracked in repository");
          (Sre, Addressed "workflow failure triggers automatic recovery or structured halt") ] };
    { id = "formal_coverage";
      level = LX_control;
      module_path = "modules/hermes_harness/formal_coverage.ml";
      purpose = "the formal-coverage registry: every component's formal artifacts (Rocq/solver/differential/property/contract) with four-aspect claims, the atlas-element usage census, and the coverage floor as declarative intent reconciled against computed actuals";
      algebra =
        { carrier = "entries (component -> artifacts, aspects, interactions, scenarios) and census counts";
          operation = "grade = best artifact rank per entry; system grade = min over entries (c3i worst-of); reconcile = declared floor vs actual";
          identity = "the empty gap list in every completeness direction";
          laws = [ "completeness is fail-closed five ways: components vs ontology, four aspects per entry, scenarios vs the BDD catalog, interactions vs the topology, cited anchors vs the filesystem";
                   "the registry grants nothing: parity credit still flows only through L4-L6 differential evidence (R10)";
                   "every law is meta-falsified: fabricated inputs must produce gaps";
                   "the floor is DECLARED intent (RFC 9315 shape): system >= property-tested, algebra machine-checked, control solver-proved" ];
          absorbing = "any gap or drift -- one uncovered element fails the suite" };
      coverage =
        [ (Structural, Addressed "a total map mirroring fractal_ontology's fail-closed coverage discipline, applied to formal evidence itself");
          (Control, Addressed "test_formal_coverage gates the suite; render_formal_coverage refuses to render on any gap or drift");
          (Data, Addressed "reads the ontology, the topology, the BDD catalog, and the dictionary; writes nothing");
          (Observability, Addressed "the grid prints component x grade x aspects; every gap is a named sentence");
          (Performance, Addressed "pure folds over in-memory data plus one dictionary emission; sub-second");
          (Scalability, Addressed "a new ontology component fails completeness until it gets an entry -- the registry pulls itself forward (R12 made executable twice over)");
          (Availability, Addressed "no external dependency; anchors are stat'ed locally");
          (Integrity, Addressed "citations must exist on disk; grades derive from artifacts, never asserted; the census recounts live structures every run");
          (Security, Not_applicable "in-repo description of in-repo evidence; no trust boundary");
          (Sdlc, Addressed "TDD stub-RED first; the one RED->GREEN gap was itself the law working (the registry claimed formal_coverage before the ontology carried it)");
          (Sre, Addressed "the rendered atlas page is the operator's map of where every proof lives and what the weakest link is") ] };
    { id = "hermes_wiki";
      level = LX_control;
      module_path = "modules/hermes_wiki/src/engine/hermes_wiki.ml";
      purpose = "the wiki/Zettelkasten core ported from the zigvm docs_wiki model (R14): frontmatter metadata, wikilinks and markdown-link edges, backlinks with citation context, typed [[T|@rel]] edges, tags, and a fence-aware markdown renderer";
      algebra =
        { carrier = "a model: pages with their link envelope, plus anomalies";
          operation = "build: (path, content) list -> model; every relation derived, never declared";
          identity = "the empty corpus -- a model with no pages and no anomalies";
          laws = [ "fst back_ctx == backlinks (the zigvm domain law, ported verbatim)";
                   "a missing wikilink renders visibly missing, never silently dropped";
                   "code fences yield no links and no tags";
                   "markdown links to sibling .md files are the same relation as a wikilink; external URLs never are";
                   "absent frontmatter gets honest defaults with an id derived from the slug";
                   "build is deterministic; duplicate slugs are an anomaly, not a silent shadow" ];
          absorbing = "an anomaly -- the render and serve drivers refuse on a non-empty anomaly list" };
      coverage =
        [ (Structural, Addressed "pure model over (path, content) pairs; read_tree is the single IO edge");
          (Control, Addressed "drives nothing; the site builder and the drivers consume it");
          (Data, Addressed "reads docs/hermes/**/*.md; writes nothing");
          (Observability, Addressed "anomalies are named sentences; the ZK page renders the graph and the unlinked notes");
          (Performance, Addressed "linear passes per file; the 47-note tree builds in milliseconds inside the site build");
          (Scalability, Addressed "backlink computation is per-page over the corpus; fine at corpus scale, revisit if notes reach thousands");
          (Availability, Addressed "no dependency; an absent docs tree yields an empty model rather than an error");
          (Integrity, Addressed "escapes before rendering; code fences never interpret; nothing here can write a note");
          (Security, Addressed "all content is escaped; no script tags are emitted and no external asset is referenced");
          (Sdlc, Addressed "TDD stub-RED first; 27 checks including the back_ctx law and both md-link directions");
          (Sre, Addressed "the wiki and ZK pages are how an operator reads the system's own knowledge base") ] };
    { id = "web_read_model";
      level = LX_control;
      module_path = "modules/hermes_harness/web_read_model.ml";
      purpose = "the typed projection behind the web surface: parity from the store, components and edges from the ontology, grades and census from the coverage registry, notes from the wiki -- one value, derived, never asserted";
      algebra =
        { carrier = "one record of counts, grades, census rows and an optional parity block";
          operation = "load: root -> t; to_json for the machine-readable face";
          identity = "the store-absent case: parity = None, which the site reports as absence";
          laws = [ "counts EQUAL their sources (ontology, catalog, registry) -- test-pinned both ways";
                   "an absent store yields None, never a fabricated number (the dashboard law)";
                   "load is deterministic for a fixed tree and store" ];
          absorbing = "none -- the read model reports, it never refuses" };
      coverage =
        [ (Structural, Addressed "a single record; every field traceable to one registry or the store");
          (Control, Addressed "read-only: opens the store, reads, closes; no write path exists");
          (Data, Addressed "evidence store + ontology + coverage registry + use-case catalog + wiki");
          (Observability, Addressed "to_json exposes the same numbers the pages render");
          (Performance, Addressed "one store session and pure folds; sub-second inside the site build");
          (Scalability, Addressed "linear in components and notes; the parity query is the store's own indexed read");
          (Availability, Addressed "store absent or unreadable degrades to parity = None with the rest intact");
          (Integrity, Addressed "cannot write; every KPI is derived at load time so a stale page is impossible");
          (Security, Not_applicable "in-process projection of local state; no trust boundary crossed");
          (Sdlc, Addressed "TDD stub-RED first; equality-to-source checks are part of test_site_build");
          (Sre, Addressed "model.json is the operator's machine-readable snapshot of system state") ] };
    { id = "site_build";
      level = LX_control;
      module_path = "modules/hermes_harness/site_build.ml";
      purpose = "the static site: one index hub reaching every component, use case, operational surface, KPI, wiki/ZK note and analytic, with inline SVG analytics and the gap plan";
      algebra =
        { carrier = "an ordered (filename, html) list plus the read model and wiki it was built from";
          operation = "build: root -> t; every page a pure function of the model";
          identity = "the shared shell -- every page carries it and links back to the hub";
          laws = [ "the hub links a page for EVERY ontology component, use case, and note";
                   "every internal link on the hub resolves to a generated page (no dead links)";
                   "no page contains a form, a POST, or an external asset host (read-only, self-contained)";
                   "charts are deterministic: no clock, no randomness, circle-laid graphs";
                   "the whole build is deterministic" ];
          absorbing = "a completeness gap -- the render and serve drivers refuse" };
      coverage =
        [ (Structural, Addressed "pure page functions over the read model; the page list is the route table");
          (Control, Addressed "render_site writes; serve_site serves; both refuse on gaps or wiki anomalies");
          (Data, Addressed "reads the read model and the wiki; writes only under state/site via the driver");
          (Observability, Addressed "the site IS the observability surface: KPIs, sweeps, coverage, plan, graphs");
          (Performance, Addressed "85 pages built in well under a second; charts are string building");
          (Scalability, Addressed "one page per component and per note; growth is linear and visible in the census");
          (Availability, Addressed "no external asset, no CDN, no script: the site works offline and in any browser");
          (Integrity, Addressed "every number comes from the read model; nothing is hard-coded (the H1 lesson)");
          (Security, Addressed "no forms, no scripts, no external hosts; content escaped through the wiki renderer");
          (Sdlc, Addressed "TDD stub-RED first; 30 checks incl. five completeness directions and meta-falsification");
          (Sre, Addressed "the operations page carries every command, its exit codes and the mesh topics") ] };
    { id = "hermes_httpd";
      level = LX_control;
      module_path = "modules/hermes_harness/hermes_httpd.ml";
      purpose = "the read-only static HTTP surface: a zero-dependency Unix server whose route table IS the built site, so traversal is impossible by construction rather than by sanitizing";
      algebra =
        { carrier = "responses (status, content type, body) over (pages, method, path)";
          operation = "respond: a total pure function; serve is the socket loop around it";
          identity = "GET / -> the index page";
          laws = [ "only GET and HEAD are answered; every other method is 405";
                   "an unknown path is 404 and NEVER a filesystem read (no path can escape the page list)";
                   "HEAD returns an empty body with the same status";
                   "responses are deterministic" ];
          absorbing = "405 -- the surface refuses every write method" };
      coverage =
        [ (Structural, Addressed "pure respond split from the socket loop; the loop is the only IO");
          (Control, Addressed "serves what serve_site built; it cannot rebuild or mutate anything");
          (Data, Addressed "serves in-memory pages; never opens a file per request");
          (Observability, Addressed "prints its bind address and page count at startup");
          (Performance, Addressed "in-memory lookup per request; no disk, no template rendering at request time");
          (Scalability, Addressed "sequential accept loop -- honest limit: one client at a time, sufficient for a local ops surface");
          (Availability, Addressed "binds loopback only; a taken port fails loudly at bind rather than silently");
          (Integrity, Addressed "no write method reaches any code path that could touch evidence");
          (Security, Addressed "loopback-only bind, no traversal reachable, no method but GET/HEAD, no-store cache header");
          (Sdlc, Addressed "TDD stub-RED first; 11 checks incl. traversal refusal and a LIVE loopback leg against the real server");
          (Sre, Addressed "one command brings the whole system dashboard up locally; kill it and nothing is left behind") ] };
    { id = "gap_plan";
      level = LX_control;
      module_path = "modules/hermes_harness/gap_plan.ml";
      purpose = "the execution plan as tracked data: every open gap item with its phase and approach, and -- where a live predicate exists -- a status DERIVED from the running system rather than hand-maintained";
      algebra =
        { carrier = "items with phase, approach, an optional live predicate, and a declared fallback";
          operation = "status: prefer the predicate over the declaration; summary folds the states";
          identity = "an item with no predicate -- it reports exactly what it declares, and says so";
          laws = [ "a derived item's status comes from the system, so closing the work flips the tracker with no edit";
                   "stale_declarations reports every place a declaration disagrees with its predicate";
                   "the tracker grants nothing: it observes progress, it never records evidence (R10)" ];
          absorbing = "none -- the plan reports; the suites and the registries enforce" };
      coverage =
        [ (Structural, Addressed "pure data plus predicates over the live registries; no IO beyond file existence and the docs tree");
          (Control, Addressed "consumed by the site's plan page; drives nothing");
          (Data, Addressed "reads the ontology, coverage registry, use-case catalog and wiki to decide derived statuses");
          (Observability, Addressed "the plan page renders every item with its status colour and its evidence line");
          (Performance, Addressed "predicates are registry folds; the whole plan resolves in milliseconds");
          (Scalability, Addressed "one entry per gap item; new gaps are added as data with a predicate wherever one is possible");
          (Availability, Addressed "predicates that cannot answer fall back to the declaration rather than raising");
          (Integrity, Addressed "cannot mark itself done: derived statuses come from the system, and disagreements are reported");
          (Security, Not_applicable "an in-repo description of in-repo work; no trust boundary");
          (Sdlc, Addressed "the tracker is the plan's execution surface: each closed item is a predicate flipping green");
          (Sre, Addressed "an operator sees at a glance what is open, what is partial, and what evidence closes each item") ] };
    { id = "hermes_sysml";
      level = LX_control;
      module_path = "modules/hermes_sysml/sysml_grammar.ml + sysml_algebra.ml";
      purpose = "a small, tested categorical kernel (composable typed transitions) underneath a mostly-inert SysML v2 / MBSE EDSL shell that three components already call to build system models nobody downstream reads";
      algebra =
        { carrier =
            "the ('src,'dst) transition GADT -- Id : ('a,'a) transition and Step of ('a,'b) transition * \
             ('b,'c) transition -> ('a,'c) transition -- plus a one-shot-message PORT/Connect functor";
          operation =
            "compose : ('b,'c) transition -> ('a,'b) transition -> ('a,'c) transition, pattern-matched to \
             elide an Id operand rather than nest it";
          identity = "Id, the identity morphism at every phantom object";
          laws =
            [ "left/right identity hold as literal structural equality, QCheck-exact (test_sysml_algebra)";
              "associativity is a declared Gospel axiom but is NOT checked as literal equality -- the one test \
               touching it (test_assoc) compares leaf COUNT of the two differently-associated trees, a \
               strictly weaker invariant a reassociating bug would also satisfy (verified directly against the \
               test body, not asserted)" ];
          absorbing = "none -- no annihilating transition; Id is eliminated by pattern match, not absorbed" };
      coverage =
        [ (Structural,
           Addressed
             "a nine-module library (sysml_types, sysml_algebra[.mli], sysml_grammar, sysml_vocabularies, \
              sysml_flows, sysml_activity, trace_projection, oml_projection, gospel_contracts[.mli-only, no \
              implementing .ml]) plus two standalone, unwired demo executables (z3_topology_check.ml, \
              zenoh_mesh.ml)");
          (Control,
           Addressed
             "Sysml_grammar's five combinators (System.define, Part.create, Block.define, Connection.connect, \
              Behavior.state_machine) are the real call surface three components already reach \
              (fractal_ontology's own sysml_ontology_model above, harness_config's sysml_behavior_model, the \
              unregistered hermes_agent_model.ml) -- but every combinator is typed `unit` and ignores its \
              arguments (verified directly in sysml_grammar.ml), so composing a model has no effect: what it \
              drives is nothing");
          (Data,
           Addressed
             "pure in-memory values in the nine core modules; the two standalone executables are the \
              exceptions -- z3_topology_check.ml writes an SMT2 file to the CWD and shells to a real z3 \
              binary, but only from its own hardcoded demo; zenoh_mesh.ml's ZenohMock never opens a socket, \
              it only prints");
          (Observability,
           Addressed
             "sysml_flows.ml's effect-handler tracer prints each emitted flow/trace as it fires, and \
              trace_projection renders a directive trace to a string; neither integrates with this repo's \
              Fractal_diagnostic/OTel path, so a failure inside this module carries no fractal coordinate");
          (Performance,
           Addressed
             "the tested surface (compose) is O(depth) tree construction with no IO; the Sysml_grammar \
              combinators are O(1) no-ops per call regardless of model size; no benchmark exists and current \
              model sizes (18 parts / 28 connections, above) don't warrant one");
          (Scalability,
           Addressed
             "the transition tree scales with the QCheck generator's size parameter; Sysml_grammar's list \
              arguments are bounded by how many parts/connections an author writes by hand and cost nothing \
              per element since the constructors discard them");
          (Availability,
           Addressed
             "z3_topology_check.ml depends on an external z3 binary but collapses every non-zero exit -- \
              missing binary, crash, or malformed input alike -- into one generic error string, unlike this \
              repo's own dependency_smt.ml which distinguishes Solver_missing (R2); the nine pure modules \
              have no external dependency to be absent");
          (Integrity,
           Addressed
             "neither system model this module builds is read by any other code today, so nothing here can \
              yet leak an unchecked value into a parity verdict -- but because every Sysml_grammar type is \
              `unit`, anything that DID assert against a built model would be asserting against (), not a \
              checked structure, and nothing here would catch that");
          (Security,
           Addressed
             "in-process typed values authored in-repo; the one process boundary (z3_topology_check.ml \
              shelling to z3) interpolates identifiers unescaped into SMT2 text and a shell command, but its \
              only caller is the module's own two hardcoded literals, so nothing untrusted reaches it today");
          (Sdlc,
           Addressed
             "test_agent_fuzz is declared as an executable, not a test, in its dune stanza, so it does not run \
              under dune runtest despite being counted as a suite in the generated module guide; a \
              self-reported coverage doc elsewhere in docs/ claims full fractal alignment while its own \
              verified-via-tests column reads zero for every row -- prose, not the L4-L6 evidence this \
              repository's own rule requires for a claim like that (R10)");
          (Sre,
           Not_applicable
             "no operational surface: not wired into control_plane, hermes_zenoh, evidence_store, or any \
              operator command; the two live standalone executables are manually-invoked demos, not part of \
              dune runtest or ops verify -- GOV-09's FPP modeling requirement is inapplicable for the same \
              reason: there is no runtime/control surface here to model") ] };
    { id = "local_slm_engine";
      level = L2_capability;
      module_path = "modules/swarm/lmstudio_intent.ml";
      purpose = "local execution of the Gemma SLM family via LM Studio for autonomous agent reasoning and function calling";
      algebra =
        { carrier = "declarative LMStudio envelopes and completion results";
          operation = "pure projection of intent into HTTP requests, and parsing of responses";
          identity = "the empty envelope, returning an empty string without network calls";
          laws = [ "R10: inference never grants parity credit directly";
                  "fail-closed: an unreachable endpoint is an Error, not a hallucination";
                  "structured output parses deterministically" ];
          absorbing = "a context window overflow or token limit, terminating generation" };
      coverage =
        [ (Structural, Addressed "declarative intent module mapping LM Studio topology and Gemma parameters");
          (Control, Addressed "consumed by swarm executors; drives HTTP requests to the local LM Studio instance");
          (Data, Addressed "reads prompts and parameters; writes telemetry to Zenoh and returns generated text or JSON");
          (Observability, Addressed "telemetry hooks trace token velocity and context window usage");
          (Performance, Addressed "local quantized execution on CPU/GPU; token generation speed bounded by local hardware");
          (Scalability, Addressed "scales to context limits (e.g. 128k for Gemma 4); concurrent requests queue at the server");
          (Availability, Addressed "absent server or unreachable port immediately degrades to an Error, failing closed");
          (Integrity, Addressed "no LLM output is trusted as parity evidence; used strictly for reasoning and orchestration");
          (Security, Addressed "all inference stays completely local; no data leaves the network loopback or Tailscale mesh");
          (Sdlc, Addressed "tested via property tests for envelope synthesis and curl generation");
          (Sre, Addressed "local API failure routes to fail-safe OODA loop abort") ] } ]

(* ------------------------------------------------------------------ atlas *)

(* Typed edges. [Derives_from] is the evidence chain proper: a receipt derives
   from a trace, which derives from a fixture. [Governs] is control-plane
   authority. [Constrains] is a rule relationship. Keeping them distinct means
   "show the evidence path" is a traversal of one edge kind, not a filter over
   an untyped graph. *)
type relation = Derives_from | Governs | Constrains | Observes

let relation_name = function
  | Derives_from -> "derives_from"
  | Governs -> "governs"
  | Constrains -> "constrains"
  | Observes -> "observes"

type edge = { source : string; relation : relation; target : string }

let atlas =
  [ (* The evidence chain, bottom-up. *)
    { source = "parity_compare"; relation = Derives_from; target = "parity_algebra" };
    { source = "parity_algebra"; relation = Derives_from; target = "parity_normalizer" };
    { source = "parity_normalizer"; relation = Derives_from; target = "reference_capture" };
    { source = "reference_capture"; relation = Derives_from; target = "capability_catalog" };
    { source = "gospel_contracts"; relation = Derives_from; target = "capability_catalog" };
    { source = "capability_catalog"; relation = Derives_from; target = "inventory" };
    (* Control-plane authority. *)
    { source = "evidence_store"; relation = Governs; target = "gospel_contracts" };
    { source = "evidence_store"; relation = Governs; target = "reference_capture" };
    { source = "evidence_store"; relation = Governs; target = "capability_catalog" };
    (* The store's append-only authority also governs what compare may
       record. Surfaced by the F Prime topology differential (2026-08-08):
       the receipt flow parity_compare -> evidence_store existed in code
       with no edge here — the two encodings disagreed, and this one was
       wrong. *)
    { source = "evidence_store"; relation = Governs; target = "parity_compare" };
    (* Rules that constrain. *)
    { source = "ocaml_only_guard"; relation = Constrains; target = "reference_capture" };
    { source = "dependency_smt"; relation = Constrains; target = "capability_catalog" };
    (* The resource envelope gates the operations that consume resources, before
       they run. *)
    { source = "resource_envelope"; relation = Constrains; target = "reference_capture" };
    { source = "resource_envelope"; relation = Constrains; target = "parity_compare" };
    (* Declarative intent: the config grammar governs the activities; a blueprint
       observes the evidence roll-up (it reads verdicts, writes nothing). *)
    { source = "harness_config"; relation = Governs; target = "reference_capture" };
    { source = "harness_config"; relation = Governs; target = "parity_compare" };
    { source = "blueprint"; relation = Observes; target = "parity_algebra" };
    (* Drift diagnosis: the rules constrain the blueprint's reconciliation (the
       gate can reject it); the engines observe/serve it. *)
    { source = "drift_rules"; relation = Constrains; target = "blueprint" };
    { source = "hermes_rete"; relation = Observes; target = "blueprint" };
    { source = "rust_rules"; relation = Observes; target = "blueprint" };
    (* Reliability annotates the receipts in the store; it constrains nothing. *)
    { source = "receipt_reliability"; relation = Observes; target = "evidence_store" };
    (* Multiway exploration observes the intent space and the config algebra. *)
    { source = "ruliad"; relation = Observes; target = "blueprint" };
    { source = "ruliad"; relation = Observes; target = "harness_config" };
    { source = "homeostasis"; relation = Observes; target = "evidence_store" };
    { source = "homeostasis"; relation = Observes; target = "blueprint" };
    { source = "control_plane"; relation = Derives_from; target = "homeostasis" };
    { source = "control_plane"; relation = Observes; target = "evidence_store" };
    { source = "hermes_zenoh"; relation = Observes; target = "control_plane" };
    (* Observation. *)
    { source = "fractal_diagnostic"; relation = Observes; target = "reference_capture" };
    { source = "fractal_diagnostic"; relation = Observes; target = "gospel_contracts" };
    { source = "fractal_diagnostic"; relation = Observes; target = "parity_algebra" };
    (* The F Prime layer: the topology description derives from the FPP
       metamodel; diagnostics observe model validation; the description
       observes the store's authority structure it mirrors. *)
    { source = "harness_topology"; relation = Derives_from; target = "fpp_model" };
    { source = "fractal_diagnostic"; relation = Observes; target = "fpp_model" };
    { source = "harness_topology"; relation = Observes; target = "evidence_store" };
    (* The FPP testing layer: the simulator interprets the metamodel; the
       BDD catalog exercises the topology description through it. *)
    { source = "fpp_interp"; relation = Derives_from; target = "fpp_model" };
    { source = "fpp_usecases"; relation = Derives_from; target = "harness_topology" };
    { source = "fpp_usecases"; relation = Observes; target = "fpp_interp" };
    (* The coverage registry observes its two evidence sources beyond the
       ontology itself. *)
    { source = "formal_coverage"; relation = Observes; target = "harness_topology" };
    { source = "formal_coverage"; relation = Observes; target = "fpp_usecases" };
    (* The web surface: the read model observes the store and the
       registries, the site derives from it, the server carries it, and
       the plan observes the coverage registry it tracks. *)
    { source = "web_read_model"; relation = Observes; target = "evidence_store" };
    { source = "web_read_model"; relation = Observes; target = "formal_coverage" };
    { source = "web_read_model"; relation = Observes; target = "hermes_wiki" };
    { source = "site_build"; relation = Derives_from; target = "web_read_model" };
    { source = "site_build"; relation = Derives_from; target = "gap_plan" };
    { source = "hermes_httpd"; relation = Observes; target = "site_build" };
    { source = "gap_plan"; relation = Observes; target = "formal_coverage" };
    { source = "skills"; relation = Derives_from; target = "agents" };
    { source = "superpowers"; relation = Derives_from; target = "agents" };
    { source = "rules"; relation = Constrains; target = "agents" };
    { source = "rules"; relation = Constrains; target = "skills" };
    { source = "rules"; relation = Constrains; target = "superpowers" };
    { source = "sop"; relation = Governs; target = "agents" };
    { source = "rules"; relation = Constrains; target = "sop" };
    { source = "sop"; relation = Governs; target = "skills" };
    { source = "planning"; relation = Governs; target = "sop" };
    { source = "temporal"; relation = Governs; target = "sop" };
    { source = "planning"; relation = Governs; target = "agents" };
    { source = "job_manager"; relation = Governs; target = "agents" };
    { source = "temporal"; relation = Governs; target = "agents" };
    { source = "hermes_zenoh"; relation = Governs; target = "agents" };
    { source = "hermes_zenoh"; relation = Governs; target = "sop" };
    { source = "irmin"; relation = Governs; target = "agents" };
    { source = "irmin"; relation = Governs; target = "sop" };
    { source = "homeostasis"; relation = Constrains; target = "agents" };
    { source = "homeostasis"; relation = Constrains; target = "sop" };
    { source = "eio"; relation = Governs; target = "agents" };
    { source = "eio"; relation = Governs; target = "sop" };
    (* harness_config.ml's own dune stanza depends on hermes_sysml directly
       (verified: modules/hermes_harness/dune, the harness_config library
       stanza) and calls Sysml_vocabularies/Sysml_grammar to build its own
       projection. The edge fractal_ontology.ml -> hermes_sysml visible just
       above (the SysML integration section) cannot itself be expressed
       here: "fractal_ontology" is not a registered component id. *)
    { source = "harness_config"; relation = Derives_from; target = "hermes_sysml" };
    { source = "agents"; relation = Governs; target = "local_slm_engine" };
    { source = "rules"; relation = Constrains; target = "local_slm_engine" } ]

let component id = List.find_opt (fun c -> c.id = id) components

let edges_from id = List.filter (fun edge -> edge.source = id) atlas
let edges_to id = List.filter (fun edge -> edge.target = id) atlas

(* The evidence path from a component down to its foundation, following
   Derives_from only. A broken chain shows up as a short path. *)
let rec evidence_path id =
  match List.find_opt (fun e -> e.source = id && e.relation = Derives_from) atlas with
  | None -> [ id ]
  | Some edge -> id :: evidence_path edge.target

(* ------------------------------------------------------------- coverage *)

let covered component aspect = List.assoc_opt aspect component.coverage

let missing_aspects component =
  List.filter (fun aspect -> covered component aspect = None) aspects

(* A coverage claim that says nothing is worse than none, because it looks
   like diligence. Both kinds must carry substantive text. *)
let vacuous_claims component =
  List.filter_map
    (fun (aspect, claim) ->
      if String.length (String.trim (coverage_text claim)) < 20 then Some aspect else None)
    component.coverage

let not_applicable_count component =
  List.length
    (List.filter
       (fun (_, claim) -> match claim with Not_applicable _ -> true | Addressed _ -> false)
       component.coverage)

let render_component component =
  let buffer = Buffer.create 512 in
  Buffer.add_string buffer
    (Printf.sprintf "%s [%s] %s\n  %s\n" component.id (level_name component.level)
       component.module_path component.purpose);
  Buffer.add_string buffer
    (Printf.sprintf "  algebra: %s under %s, identity %s, absorbing %s\n"
       component.algebra.carrier component.algebra.operation component.algebra.identity
       component.algebra.absorbing);
  List.iter
    (fun law -> Buffer.add_string buffer (Printf.sprintf "    law: %s\n" law))
    component.algebra.laws;
  List.iter
    (fun (aspect, claim) ->
      let marker = match claim with Addressed _ -> "+" | Not_applicable _ -> "-" in
      Buffer.add_string buffer
        (Printf.sprintf "    %s %-14s %s\n" marker (aspect_name aspect)
           (coverage_text claim)))
    component.coverage;
  Buffer.contents buffer

(* ------------------------------------------------------------- SysML v2 Ontology Integration *)

let sysml_ontology_model =
  let open Hermes_sysml in
  let _vocab =
    Sysml_vocabularies.harness_vocabulary "http://hermes/ontology" "hermes"
      [ Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("evidence_store", "Evidence Store"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("capability_catalog", "Capability Catalog"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("gospel_contracts", "Gospel Contracts"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("reference_capture", "Reference Capture"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("parity_normalizer", "Parity Normalizer"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("parity_compare", "Parity Compare"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("parity_algebra", "Parity Algebra"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("sop", "Standard Operating Procedures"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("planning", "Planning Scheduler"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("job_manager", "Job Manager"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("temporal", "Temporal Engine"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("hermes_zenoh", "Decentralized Gossip Mesh"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("irmin", "Branchable Memory"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("homeostasis", "Immune Resilience"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("eio", "Effects I/O Engine"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("agents", "Agents"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("skills", "Skills"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("rules", "Rules"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("superpowers", "Superpowers"));
        Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("local_slm_engine", "Local SLM Engine")) ]
  in
  Sysml_grammar.System.define
    ~name:"HermesHarnessOntology"
    ~parts:
      [ Sysml_grammar.Part.create ~name:"evidence_store" ~typ:"store" ();
        Sysml_grammar.Part.create ~name:"capability_catalog" ~typ:"catalog" ();
        Sysml_grammar.Part.create ~name:"gospel_contracts" ~typ:"specification" ();
        Sysml_grammar.Part.create ~name:"reference_capture" ~typ:"capture" ();
        Sysml_grammar.Part.create ~name:"parity_normalizer" ~typ:"normalizer" ();
        Sysml_grammar.Part.create ~name:"parity_compare" ~typ:"compare" ();
        Sysml_grammar.Part.create ~name:"parity_algebra" ~typ:"algebra" ();
        Sysml_grammar.Part.create ~name:"sop" ~typ:"procedure" ();
        Sysml_grammar.Part.create ~name:"planning" ~typ:"scheduler" ();
        Sysml_grammar.Part.create ~name:"job_manager" ~typ:"queue" ();
        Sysml_grammar.Part.create ~name:"temporal" ~typ:"workflow" ();
        Sysml_grammar.Part.create ~name:"hermes_zenoh" ~typ:"gossip" ();
        Sysml_grammar.Part.create ~name:"irmin" ~typ:"memory" ();
        Sysml_grammar.Part.create ~name:"homeostasis" ~typ:"resilience" ();
        Sysml_grammar.Part.create ~name:"eio" ~typ:"effects" ();
        Sysml_grammar.Part.create ~name:"agents" ~typ:"actor" ();
        Sysml_grammar.Part.create ~name:"skills" ~typ:"capability" ();
        Sysml_grammar.Part.create ~name:"rules" ~typ:"constraint" ();
        Sysml_grammar.Part.create ~name:"superpowers" ~typ:"capability" ();
        Sysml_grammar.Part.create ~name:"local_slm_engine" ~typ:"engine" () ]
    ~connections:
      [ Sysml_grammar.Connection.connect "evidence_store" "capability_catalog";
        Sysml_grammar.Connection.connect "evidence_store" "gospel_contracts";
        Sysml_grammar.Connection.connect "evidence_store" "reference_capture";
        Sysml_grammar.Connection.connect "capability_catalog" "gospel_contracts";
        Sysml_grammar.Connection.connect "capability_catalog" "reference_capture";
        Sysml_grammar.Connection.connect "reference_capture" "parity_normalizer";
        Sysml_grammar.Connection.connect "parity_compare" "evidence_store";
        Sysml_grammar.Connection.connect "parity_compare" "parity_algebra";
        Sysml_grammar.Connection.connect "skills" "agents";
        Sysml_grammar.Connection.connect "superpowers" "agents";
        Sysml_grammar.Connection.connect "rules" "agents";
        Sysml_grammar.Connection.connect "rules" "skills";
        Sysml_grammar.Connection.connect "rules" "superpowers";
        Sysml_grammar.Connection.connect "sop" "agents";
        Sysml_grammar.Connection.connect "rules" "sop";
        Sysml_grammar.Connection.connect "planning" "sop";
        Sysml_grammar.Connection.connect "temporal" "sop";
        Sysml_grammar.Connection.connect "planning" "agents";
        Sysml_grammar.Connection.connect "job_manager" "agents";
        Sysml_grammar.Connection.connect "temporal" "agents";
        Sysml_grammar.Connection.connect "hermes_zenoh" "agents";
        Sysml_grammar.Connection.connect "hermes_zenoh" "sop";
        Sysml_grammar.Connection.connect "irmin" "agents";
        Sysml_grammar.Connection.connect "irmin" "sop";
        Sysml_grammar.Connection.connect "homeostasis" "agents";
        Sysml_grammar.Connection.connect "homeostasis" "sop";
        Sysml_grammar.Connection.connect "eio" "agents";
        Sysml_grammar.Connection.connect "eio" "sop";
        Sysml_grammar.Connection.connect "agents" "local_slm_engine";
        Sysml_grammar.Connection.connect "rules" "local_slm_engine" ]
    ~behavior:(Sysml_grammar.Behavior.state_machine ~states:[] ~transitions:[])
