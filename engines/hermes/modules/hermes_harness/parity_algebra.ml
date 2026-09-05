(* The algebra by which evidence at one fractal level yields a verdict at the
   level above.

   This law was previously implicit, spread across the tracker and the
   reporting code. Written as an algebra it becomes property-testable, and one
   of its laws is load-bearing enough that stating it explicitly is the point:

     roll_up over an EMPTY set of required children is Unmapped, never Verified.

   Vacuous truth is how an evidence system reports 100% while proving nothing:
   "all zero of my children are verified" is true and useless. Every capability
   in this catalog starts with no evidence, so a fold that returns the identity
   of conjunction would report the entire product verified on day one. The
   identity here is deliberately Unmapped, which makes the fold non-vacuous. *)

type verdict =
  | Unmapped    (* no evidence either way *)
  | Blocked     (* evidence was sought and could not be obtained *)
  | Verified    (* differential evidence obtained and it agreed *)
  | Divergent   (* differential evidence obtained and it disagreed *)

let name = function
  | Unmapped -> "unmapped"
  | Blocked -> "blocked"
  | Verified -> "verified"
  | Divergent -> "divergent"

(* Severity order for combination. Divergent dominates everything: one proved
   divergence sinks the parent regardless of how much agreement surrounds it.
   Blocked outranks Unmapped because "we tried and could not" is strictly more
   informative than "we never looked", and the parent should surface the more
   actionable of the two. Verified is weakest: it yields to any doubt. *)
let rank = function
  | Verified -> 0
  | Unmapped -> 1
  | Blocked -> 2
  | Divergent -> 3

(* Commutative, associative, idempotent: a semilattice join on severity. That
   it is a join is what makes roll-up order-independent, which matters because
   nothing should depend on the order children happen to be listed in. *)
let combine left right = if rank left >= rank right then left else right

(* The identity of [combine] is Verified -- it is the least element -- but the
   identity is NOT what an empty roll-up returns. See [roll_up]. *)
let identity = Verified

(* Roll a level's children up into the parent's verdict.

   [required] distinguishes a node whose children must all be proved from one
   whose evidence is optional. For a required node with no children at all, the
   answer is Unmapped: there is nothing to have proved. Returning [identity]
   here would be the vacuous-truth bug, and the property test pins it. *)
let roll_up ~required verdicts =
  match verdicts with
  | [] -> if required then Unmapped else Verified
  | _ -> List.fold_left combine identity verdicts

(* Whether a verdict grants parity credit. Only Verified does. Blocked and
   Unmapped withhold credit without asserting a defect; Divergent asserts one.
   This mirrors Fractal_diagnostic's rule that only an Implementation origin
   may deny credit. *)
let grants_credit = function
  | Verified -> true
  | Unmapped | Blocked | Divergent -> false

(* Whether a verdict asserts a proved defect, as opposed to absent evidence. *)
let asserts_defect = function
  | Divergent -> true
  | Verified | Unmapped | Blocked -> false

(* Map a diagnostic's parity impact onto the verdict lattice, so a diagnostic
   emitted anywhere in the harness composes with recorded evidence under the
   same law. *)
let of_diagnostic_impact (impact : Fractal_diagnostic.parity_effect) =
  match impact with
  | Fractal_diagnostic.Denies_credit -> Divergent
  | Fractal_diagnostic.Blocks_credit -> Blocked
  | Fractal_diagnostic.No_effect -> Unmapped

(* A whole level's report: the verdict plus the counts behind it, because a
   bare verdict hides whether it rests on one child or ninety-five. *)
type level_report = {
  verdict : verdict;
  total : int;
  verified : int;
  blocked : int;
  divergent : int;
  unmapped : int;
}

let report ~required verdicts =
  let count target = List.length (List.filter (fun v -> v = target) verdicts) in
  { verdict = roll_up ~required verdicts;
    total = List.length verdicts;
    verified = count Verified;
    blocked = count Blocked;
    divergent = count Divergent;
    unmapped = count Unmapped }

(* Percentage of children that granted credit. Deliberately separate from the
   verdict: a family at 94/95 verified is NOT verified, and reporting only the
   percentage is how a system talks itself into believing it is nearly done. *)
let credit_percent report =
  if report.total = 0 then 0 else report.verified * 100 / report.total

let render_report report =
  Printf.sprintf "%s (%d/%d verified, %d blocked, %d divergent, %d unmapped, %d%%)"
    (name report.verdict) report.verified report.total report.blocked
    report.divergent report.unmapped (credit_percent report)
