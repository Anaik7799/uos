(* Report-only isolation prover — a REAL, law-carrying gate-coupling guard.

   Promoted from a phase-7 scaffolding stub (DIVERGENCE 669). Controller class
   CTRL-HARNESS-MOD. It MECHANIZES the reservation SAFETY_ANALYSIS §11 UCA-SCRIPT-4
   made explicit: `wiki_gate_coupling_prover.ml` "reserved for mechanizing" the
   report-only-isolation constraint — a documentation-anomaly sweep (orphans,
   unlinked mentions, broken wiki links) must NEVER be able to block or flip the
   canonical build gate (the hazard: a doc typo reddening a green build).

   THE MECHANISM.  The gate verdict is decided by the Rete-UL production rules
   (`Rete_rules.all_rules`): a `record_cycle` is admitted iff no rule's action
   returns `Error`, and a rule can only fire on the fact KINDS its patterns name
   (`pattern.pat_kind`). So the gate is DECOUPLED from documentation exactly when
   the set of fact kinds the gate rules consume is DISJOINT from the doc/wiki/ZK
   report-only vocabulary. A doc anomaly, which lives in that vocabulary, then has
   no pattern to match and cannot influence any verdict — isolation by
   construction, not by convention.

   SIGNATURE / SEMANTIC DOMAIN.  `check : rule list -> verdict` in the two-point
   lattice Decoupled < Coupled:
     denote(rules) = Decoupled  iff  consumed_kinds(rules) ∩ doc_report_kinds = ∅
                   = Coupled ks  otherwise (ks = the offending doc kinds a rule consumes)
   The ORACLE is the ACTUAL rule set — `consumed_kinds` reads every rule's real
   `pat_kind`s, so the law tracks the live gate, not a copy of it. This module is
   PURE (no I/O): `check` is a total function of the rule list, so the CLI runs it
   over `Rete_rules.all_rules` and the laws run it over synthetic rule lists.

   LAWS ([laws], `--selfcheck-gate-coupling`):
     - ISOLATION    : the REAL Rete_rules.all_rules is Decoupled
     - COVERAGE     : all_rules consumes > 0 control kinds (we ARE reading real rules,
                      not an empty list that would make ISOLATION vacuous)
     - DETECTION    : a synthetic rule consuming a doc-anomaly kind => Coupled (rejection)
     - DISJOINTNESS : a synthetic control-only rule set => Decoupled
     - TOTALITY     : the empty rule set => Decoupled, no crash

   MUTANTS (MUTATION_LOG, DIVERGENCE 669):
     MUT-1  make the coupling filter never match (k in doc_report_kinds -> false)
            -> DETECTION reds (a doc-coupled rule wrongly passes)
     MUT-2  make consumed_kinds return [] -> COVERAGE reds (we would no longer be
            reading the real gate, so ISOLATION would pass vacuously)

   SCOPE.  This guards the report-only-isolation HALF of UCA-SCRIPT-4 (no doc
   fact-kind couples to a gate rule). The other half of SC-48.1 — a mechanized
   `scripts/` OCaml-only boundary + a fabricated-telemetry check — remains a
   named, queued gap. The twin stub `zk_gate_isolation_prover.ml` (a code-path
   claim: no ZK read/write path writes `harness_runs.status`) stays unwired. *)

open Rete

(* The report-only doc/wiki/ZK fact-kind vocabulary. A documentation-anomaly sweep
   produces these; NONE may be consumed by a gate-verdict rule. This is the gate's
   negative space — the set the gate must stay disjoint from. *)
let doc_report_kinds =
  [ "Anomaly"; "DocAnomaly"; "WikiAnomaly"; "ZkAnomaly"; "Orphan";
    "UnlinkedMention"; "StructuralHole"; "BrokenLink"; "WikiLink"; "DocNote";
    "ZkNote"; "Transclusion"; "DiscourseEdge"; "MocMembership"; "BacklinkCtx" ]

type verdict = Decoupled | Coupled of string list

let string_of_verdict = function
  | Decoupled -> "decoupled (no gate rule consumes a doc/wiki/anomaly fact kind)"
  | Coupled ks ->
      "COUPLED: gate rule(s) consume report-only doc kind(s): " ^ String.concat ", " ks

let is_decoupled = function Decoupled -> true | Coupled _ -> false

(* Every fact kind the rule set's patterns consume (deduped, sorted). Reads the
   real `pat_kind`s so the verdict tracks the live gate. *)
let consumed_kinds (rules : Rete.rule list) : string list =
  rules
  |> List.concat_map (fun (r : Rete.rule) ->
         List.map (fun (p : Rete.pattern) -> p.pat_kind) r.patterns)
  |> List.sort_uniq String.compare

(* Report-only isolation verdict: the gate is decoupled iff its consumed fact
   kinds are disjoint from the doc/wiki report-only vocabulary. TOTAL. *)
let check (rules : Rete.rule list) : verdict =
  let coupled = List.filter (fun k -> List.mem k doc_report_kinds) (consumed_kinds rules) in
  if coupled = [] then Decoupled else Coupled coupled

(* The real gate: check the live Rete_rules.all_rules. *)
let check_all () = check Rete_rules.all_rules

(* ------------------------------------------------------------------ laws ---- *)

let laws () : int =
  let n = ref 0 in
  let check_law name ok =
    incr n; if not ok then failwith ("gate-coupling law: " ^ name)
  in
  let mk_rule name kind : Rete.rule =
    { name;
      patterns = [ { pat_kind = kind; conds = []; bind_name = None } ];
      action = (fun _ _ -> Ok ()) }
  in
  (* ISOLATION: the real gate rule set consumes no doc kind. *)
  check_law "ISOLATION (real all_rules is decoupled)"
    (is_decoupled (check Rete_rules.all_rules));
  (* COVERAGE: we are genuinely reading the real rules (non-empty consumed set),
     so ISOLATION is not vacuously true over an empty read. *)
  check_law "COVERAGE (gate consumes >0 control kinds)"
    (List.length (consumed_kinds Rete_rules.all_rules) > 0);
  (* DETECTION: a synthetic rule that consumes a doc-anomaly kind is flagged. *)
  (match check [ mk_rule "synthetic-coupled" "Anomaly" ] with
   | Decoupled -> check_law "DETECTION (a doc-coupled rule is flagged)" false
   | Coupled ks -> check_law "DETECTION (a doc-coupled rule is flagged)" (List.mem "Anomaly" ks));
  (* DISJOINTNESS: a synthetic control-only rule set is decoupled. *)
  check_law "DISJOINTNESS (a control-only rule set is decoupled)"
    (is_decoupled (check [ mk_rule "synthetic-clean" "RecordCycle" ]));
  (* TOTALITY: the empty rule set is decoupled, no crash. *)
  check_law "TOTALITY (empty rule set decoupled)" (is_decoupled (check []));
  !n
