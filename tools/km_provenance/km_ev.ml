(* SC-PROVENANCE-001 — denotational model of EV admission, and its computation.

   ================= DENOTATIONAL DESIGN =================

   The policy defines admission as two-key verification: fresh observed runtime
   behaviour AND a machine-checkable formal specification, both at the candidate
   revision. That is a total function from an EV cycle and a revision to a
   verdict:

     [[admit]] : Ev -> Revision -> Verdict

     [[admit]](n, r) = Admitted
                         iff  exists e in Evidence.
                                  runtime(e, n, r) and formal(e, n, r)
                                  and bound_to(e, r)
                     = NotAdmitted   otherwise

   Verdict is deliberately two-valued with NotAdmitted absorbing: there is no
   Unknown that a reader can mistake for a pass. Absence of evidence denotes
   NotAdmitted, never Unknown-treated-as-green.

   Seven laws follow from that denotation. They are stated here and executed in
   km_gate --ev-selftest; each is falsifiable and each is a property the current
   `uos doctor` VIOLATES.

     L1 fail-closed      no evidence            => NotAdmitted
     L2 two-key          runtime xor formal     => NotAdmitted
     L3 revision-bound   evidence at r          => says nothing at r' <> r
     L4 no-gap           admitted(n)            => admitted(n-1)
     L5 non-inflation    a claim without evidence never raises the admitted count
     L6 idempotent       same (n, r, evidence)  => same verdict
     L7 falsifiable      removing evidence flips Admitted -> NotAdmitted

   L7 is the decisive one. A verdict function that cannot be flipped by
   destroying its evidence is not measuring anything. *)

exception Invalid of string
let require c m = if not c then raise (Invalid m)

type verdict = Admitted | Not_admitted of string

let verdict_to_string = function
  | Admitted -> "ADMITTED"
  | Not_admitted _ -> "NOT_ADMITTED"

let reason = function Admitted -> "" | Not_admitted r -> r

(* Evidence is what a claim is redeemed against. Both keys are separate fields
   precisely so that possessing one cannot be mistaken for possessing both. *)
type evidence = {
  ev : int;
  revision : string;          (* the candidate revision the evidence binds to *)
  runtime_ref : string option; (* fresh observed behaviour, e.g. a test receipt *)
  formal_ref : string option;  (* machine-checkable spec, e.g. a Lean/Quint file *)
}

(* A reference redeems only if the artifact it names is actually present. The
   presence predicate is supplied by the caller so this module stays pure and so
   the falsifier can substitute a hostile one. *)
type presence = string -> bool

let key_present (present : presence) = function
  | None -> false
  | Some r -> String.trim r <> "" && present r

(* [[admit]] itself. Note there is no branch that returns Admitted without both
   keys, and none that treats a missing key as neutral. *)
let admit ~(present : presence) ~(at_revision : string) (e : evidence) : verdict =
  if String.trim at_revision = "" then Not_admitted "no candidate revision given"
  else if e.revision <> at_revision then
    Not_admitted
      ("evidence is bound to revision " ^ e.revision ^ ", not to " ^ at_revision)
  else
    match key_present present e.runtime_ref, key_present present e.formal_ref with
    | true, true -> Admitted
    | false, true -> Not_admitted "runtime key absent: no fresh observed behaviour"
    | true, false -> Not_admitted "formal key absent: no machine-checkable specification"
    | false, false -> Not_admitted "no evidence"

(* L4: cycles are sequential, so a gap makes every later cycle inadmissible
   regardless of its own evidence. Returns the verdicts with the gap rule
   applied, lowest EV first. *)
let apply_no_gap (results : (int * verdict) list) : (int * verdict) list =
  let sorted = List.sort (fun (a, _) (b, _) -> compare a b) results in
  let rec go prev_admitted acc = function
    | [] -> List.rev acc
    | (n, v) :: tl ->
      let v' =
        match v, prev_admitted with
        | Admitted, false ->
          Not_admitted ("gap: EV-" ^ string_of_int (n - 1) ^ " is not admitted")
        | _ -> v in
      go (v' = Admitted) ((n, v') :: acc) tl in
  match sorted with
  | [] -> []
  | (first, _) :: _ ->
    (* the first cycle in the range has no predecessor obligation *)
    let rec start acc = function
      | [] -> List.rev acc
      | (n, v) :: tl when n = first -> go (v = Admitted) ((n, v) :: acc) tl
      | (n, v) :: tl -> start ((n, v) :: acc) tl in
    start [] sorted

let admitted_count results =
  List.length (List.filter (fun (_, v) -> v = Admitted) results)

(* The ceiling is derived, never asserted: it is the highest EV such that every
   cycle up to and including it is admitted. *)
let ceiling results =
  let sorted = List.sort (fun (a, _) (b, _) -> compare a b) results in
  let rec go last = function
    | (n, Admitted) :: tl when n = last + 1 -> go n tl
    | _ -> last in
  go 0 sorted
