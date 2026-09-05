(* The declarative configuration grammar and activity algebra of the harness.

   The grammar is a typed OCaml AST built by constructors (the DSL); intent lives
   in OCaml comments and Annotate nodes. The algebra: composite outcomes fold with
   the SAME semilattice join as the evidence roll-up (Parity_algebra.combine),
   with the empty composite Unmapped -- the vacuous-truth guard -- so
   configuration composes exactly like evidence. The behaviour: plan is a pure
   linearization (the Terraform plan); execute interprets each primitive through
   an injected driver and is fail-closed at every Gate. R14: the typed
   command-variant-then-dispatch shape mirrors the zigvm harness's mode variant. *)

type target = string
type corpus = All | Slices of target list

type activity =
  | Capture of corpus
  | Compare of corpus
  | Check_contracts
  | Check_determinism
  | Preflight of Resource_envelope.resource list
  | Reconcile of Blueprint.t
  | Report
  | Seq of activity list
  | Par of activity list
  | Gate of activity * activity
  | Annotate of string * activity

let corpus_label = function
  | All -> "all"
  | Slices targets -> String.concat "," targets

let primitive_label = function
  | Capture corpus -> "capture(" ^ corpus_label corpus ^ ")"
  | Compare corpus -> "compare(" ^ corpus_label corpus ^ ")"
  | Check_contracts -> "check-contracts"
  | Check_determinism -> "check-determinism"
  | Preflight resources -> Printf.sprintf "preflight(%d resources)" (List.length resources)
  | Reconcile blueprint -> Printf.sprintf "reconcile(%d intents)" (List.length blueprint)
  | Report -> "report"
  | Seq _ | Par _ | Gate _ | Annotate _ -> "composite"

(* ------------------------------------------------------------- the plan *)

type step = { action : string; why : string option }

(* Pure linearization with the innermost enclosing intent. Gate plans BOTH arms:
   the plan shows what would run, and whether B actually runs is decided at
   execution time by A's outcome. *)
let plan activity =
  let rec walk why activity =
    match activity with
    | Seq children | Par children -> List.concat_map (walk why) children
    | Gate (condition, guarded) -> walk why condition @ walk why guarded
    | Annotate (intent, child) -> walk (Some intent) child
    | primitive -> [ { action = primitive_label primitive; why } ]
  in
  walk None activity

let render_plan steps =
  let buffer = Buffer.create 256 in
  List.iteri
    (fun index step ->
      Buffer.add_string buffer
        (Printf.sprintf "%2d. %s%s\n" (index + 1) step.action
           (match step.why with Some why -> "  -- " ^ why | None -> "")))
    steps;
  Buffer.contents buffer

(* ---------------------------------------------------------------- algebra *)

(* The composite fold: Unmapped on empty (a composite that ran nothing proved
   nothing), else the semilattice join. Same lattice as the evidence roll-up. *)
let outcome_of_list = function
  | [] -> Parity_algebra.Unmapped
  | first :: rest -> List.fold_left Parity_algebra.combine first rest

(* The Gate combinator, pure and exposed so formal_specs can emit its table from
   the code under test: the thunk runs only when the condition grants credit. *)
let gate_verdict condition guarded =
  if Parity_algebra.grants_credit condition then
    outcome_of_list [ condition; guarded () ]
  else condition

(* Fractal-layer coverage as data: the levels an activity's work lives at.
   Composites are the union of their children, so "does this configuration
   exercise every level" is a set inclusion, not a hope. *)
let levels_of activity =
  let rec walk activity =
    match activity with
    | Capture _ -> [ Fractal_ontology.L4_fixture; Fractal_ontology.L5_trace ]
    | Compare _ ->
        [ Fractal_ontology.L4_fixture; Fractal_ontology.L5_trace; Fractal_ontology.L6_receipt ]
    | Check_contracts -> [ Fractal_ontology.L3_contract ]
    | Check_determinism -> [ Fractal_ontology.LX_control ]
    | Preflight _ -> [ Fractal_ontology.LX_control ]
    | Reconcile _ ->
        [ Fractal_ontology.L0_product; Fractal_ontology.L1_family;
          Fractal_ontology.L2_capability ]
    | Report -> [ Fractal_ontology.L0_product ]
    | Seq children | Par children -> List.concat_map walk children
    | Gate (condition, guarded) -> walk condition @ walk guarded
    | Annotate (_, child) -> walk child
  in
  List.sort_uniq compare (walk activity)

(* The canonical read-only configuration: preflight GATES everything (R13);
   compare produces the differential evidence; contracts, determinism and
   intent-reconciliation run as order-independent checks; the report closes the
   loop. Capture stays outside -- writing evidence is a deliberate act. *)
let standard_pipeline ~preflight ~blueprint =
  Gate
    ( Preflight preflight,
      Seq
        [ Annotate ("measure differential parity against the frozen reference", Compare All);
          Par [ Check_contracts; Check_determinism;
                Annotate ("reconcile declared intent against the evidence", Reconcile blueprint) ];
          Report ] )

(* -------------------------------------------------------------- execution *)

type driver = {
  capture : corpus -> Parity_algebra.verdict;
  compare : corpus -> Parity_algebra.verdict;
  check_contracts : unit -> Parity_algebra.verdict;
  check_determinism : unit -> Parity_algebra.verdict;
  preflight : Resource_envelope.resource list -> Parity_algebra.verdict;
  reconcile : Blueprint.t -> Parity_algebra.verdict;
  report : unit -> Parity_algebra.verdict;
}

type outcome = { activity_label : string; verdict : Parity_algebra.verdict }

let execute driver activity =
  (* trail accumulates outcomes in execution order. A crashing driver fails
     CLOSED as that primitive's Blocked verdict: an exception proves nothing
     about the candidate, and one broken subsystem must not kill the run --
     the same discipline as Resource_envelope.observe. *)
  let trail = ref [] in
  let run_primitive primitive produce =
    let verdict = try produce () with _ -> Parity_algebra.Blocked in
    trail := { activity_label = primitive_label primitive; verdict } :: !trail;
    verdict
  in
  let rec run activity =
    match activity with
    | Capture corpus as p -> run_primitive p (fun () -> driver.capture corpus)
    | Compare corpus as p -> run_primitive p (fun () -> driver.compare corpus)
    | Check_contracts as p -> run_primitive p (fun () -> driver.check_contracts ())
    | Check_determinism as p -> run_primitive p (fun () -> driver.check_determinism ())
    | Preflight resources as p -> run_primitive p (fun () -> driver.preflight resources)
    | Reconcile blueprint as p -> run_primitive p (fun () -> driver.reconcile blueprint)
    | Report as p -> run_primitive p (fun () -> driver.report ())
    | Seq children | Par children ->
        (* Same fold for both: Par declares order-independent INTENT; execution
           order here is declaration order, and the join makes the outcome
           order-independent. *)
        outcome_of_list (List.map run children)
    | Gate (condition, guarded) -> gate_verdict (run condition) (fun () -> run guarded)
    | Annotate (_, child) -> run child
  in
  let verdict = run activity in
  (verdict, List.rev !trail)

(* ------------------------------------------------------------- SysML v2 Configuration Behavior *)

let sysml_behavior_model =
  let open Hermes_sysml in
  let _vocab =
    Sysml_vocabularies.harness_vocabulary "http://hermes/config" "config"
      [ Sysml_vocabularies.Concept (Sysml_vocabularies.Component ("pipeline", "Standard Pipeline")) ]
  in
  Sysml_grammar.System.define
    ~name:"HarnessConfigBehavior"
    ~parts:[ Sysml_grammar.Part.create ~name:"pipeline" ~typ:"Activity" () ]
    ~connections:[]
    ~behavior:(Sysml_grammar.Behavior.state_machine ~states:[] ~transitions:[])
