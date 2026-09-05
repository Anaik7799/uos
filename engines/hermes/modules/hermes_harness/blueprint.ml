(* Declarative, intent-based configuration: desired-state reconciliation over the
   fractal evidence model. A blueprint declares intended verdicts for fractal
   targets (the Terraform/Pulumi resource + desired-state idea, in real OCaml);
   reconcile is the plan/diff against actual reality (the evidence roll-up),
   reporting drift as a fractal diagnostic. Report-only: like a Terraform dry-run
   and decision_frame's advisory mode, it never applies -- building the candidate
   is the operator's/agent's job -- it only shows the gap between intent and
   reality, closing the loop as that gap shrinks. Typed IO-free data, the seed
   pattern (R14). *)

type directive = {
  id : string;
  target : string;
  desired : Parity_algebra.verdict;
  intent : string;
  requires : string list;
}

type t = directive list

type error =
  | Vacuous_intent of string
  | Duplicate_id of string
  | Unresolved_requirement of { directive : string; missing : string }
  | Unknown_target of { directive : string; target : string }
  | Cycle of string list

let describe_error = function
  | Vacuous_intent id -> "vacuous intent: " ^ id
  | Duplicate_id id -> "duplicate directive id: " ^ id
  | Unresolved_requirement { directive; missing } ->
      Printf.sprintf "%s requires undeclared directive %s" directive missing
  | Unknown_target { directive; target } ->
      Printf.sprintf "%s targets %s, which the fractal does not contain" directive target
  | Cycle ids -> "dependency cycle: " ^ String.concat " -> " ids

(* Dependency order (each directive after all it requires), with cycle detection.
   Mirrors the capability_catalog / dependency_smt ordering discipline. *)
let order blueprint =
  let ids = List.map (fun d -> d.id) blueprint in
  let requires_of id =
    match List.find_opt (fun d -> d.id = id) blueprint with
    | Some d -> List.filter (fun r -> List.mem r ids) d.requires
    | None -> []
  in
  let visited = Hashtbl.create 16 and on_stack = Hashtbl.create 16 in
  let result = ref [] and cycle = ref None in
  let rec visit stack id =
    if !cycle <> None then ()
    else if Hashtbl.mem visited id then ()
    else if Hashtbl.mem on_stack id then cycle := Some (List.rev (id :: stack))
    else begin
      Hashtbl.replace on_stack id ();
      List.iter (fun r -> visit (id :: stack) r) (requires_of id);
      Hashtbl.remove on_stack id;
      if !cycle = None then begin
        Hashtbl.replace visited id ();
        result := id :: !result
      end
    end
  in
  List.iter (fun id -> visit [] id) ids;
  match !cycle with Some c -> Error (Cycle c) | None -> Ok (List.rev !result)

let validate ?resolve blueprint =
  let errors = ref [] in
  let add error = errors := error :: !errors in
  (* The ontology/catalog alignment check: an intent about a node the fractal
     does not contain is a typo, not a plan. *)
  (match resolve with
  | None -> ()
  | Some resolves ->
      List.iter
        (fun d ->
          if not (resolves d.target) then
            add (Unknown_target { directive = d.id; target = d.target }))
        blueprint);
  let seen = Hashtbl.create 16 in
  List.iter
    (fun d ->
      if Hashtbl.mem seen d.id then add (Duplicate_id d.id) else Hashtbl.replace seen d.id ())
    blueprint;
  List.iter
    (fun d -> if String.length (String.trim d.intent) <= 20 then add (Vacuous_intent d.id))
    blueprint;
  let ids = List.map (fun d -> d.id) blueprint in
  List.iter
    (fun d ->
      List.iter
        (fun r ->
          if not (List.mem r ids) then add (Unresolved_requirement { directive = d.id; missing = r }))
        d.requires)
    blueprint;
  (match order blueprint with Error (Cycle c) -> add (Cycle c) | _ -> ());
  match List.rev !errors with [] -> Ok () | es -> Error es

(* -------------------------------------------------------- reconciliation *)

type outcome =
  | Satisfied
  | Drift of { desired : Parity_algebra.verdict; actual : Parity_algebra.verdict }

type reconciled = {
  directive : directive;
  outcome : outcome;
  diagnostic : Fractal_diagnostic.t option;
}

(* A drift is a fractal diagnostic. Its origin/impact follow the actual verdict:
   a Divergent actual is a proved Implementation defect (denies); a Blocked one is
   Environment (nothing proved); an Unmapped intent has no evidence yet, which is a
   Control gap (the harness has not been pointed at it). Never grants credit. *)
let drift_diagnostic directive desired actual =
  let origin, impact =
    match actual with
    | Parity_algebra.Divergent -> (Fractal_diagnostic.Implementation, Fractal_diagnostic.Denies_credit)
    | Parity_algebra.Blocked -> (Fractal_diagnostic.Environment, Fractal_diagnostic.Blocks_credit)
    | Parity_algebra.Unmapped | Parity_algebra.Verified ->
        (Fractal_diagnostic.Control, Fractal_diagnostic.Blocks_credit)
  in
  Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt ~origin ~impact
    ~node:directive.target ~subject:directive.id
    ~message:
      (Printf.sprintf "intent drift: %s wants %s, actual is %s" directive.id
         (Parity_algebra.name desired) (Parity_algebra.name actual))
    ~cause:("the intended state is not met -- " ^ directive.intent)
    ~fix:
      "build or fix the target until it reaches the desired verdict, then re-reconcile \
       to converge"
    ()

let reconcile blueprint ~actual =
  List.map
    (fun directive ->
      let a = actual directive.target in
      if a = directive.desired then { directive; outcome = Satisfied; diagnostic = None }
      else
        { directive;
          outcome = Drift { desired = directive.desired; actual = a };
          diagnostic = Some (drift_diagnostic directive directive.desired a) })
    blueprint

let converged reconciled = List.for_all (fun r -> r.outcome = Satisfied) reconciled

let summary reconciled =
  let satisfied = List.length (List.filter (fun r -> r.outcome = Satisfied) reconciled) in
  Printf.sprintf "%d/%d intents satisfied" satisfied (List.length reconciled)

let render blueprint =
  let buffer = Buffer.create 512 in
  List.iter
    (fun d ->
      Buffer.add_string buffer
        (Printf.sprintf "%s -> %s [want %s]\n  intent: %s\n" d.id d.target
           (Parity_algebra.name d.desired) d.intent);
      if d.requires <> [] then
        Buffer.add_string buffer ("  requires: " ^ String.concat ", " d.requires ^ "\n"))
    blueprint;
  Buffer.contents buffer
