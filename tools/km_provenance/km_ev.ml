(* SC-PROVENANCE-001 — legacy evidence containment and sequential decisions.

   A legacy row carries file references and a caller-written revision label.
   It cannot establish execution, freshness, source-byte identity or independent
   sovereign authority. `admit` therefore never promotes a legacy row.

   The Admitted constructor represents a separately established decision; its
   use in prefix tests is synthetic. Prefix normalization starts at EV1,
   rejects duplicate/out-of-range identifiers and cannot skip a missing cycle.
   The operator's existing scope is EV1..109; no new identifier is minted here.
   None of these computations changes the policy ceiling or grants effects. *)

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

(* Presence can explain missing legacy artifacts, but never supplies a key. *)
type presence = string -> bool

let key_present (present : presence) = function
  | None -> false
  | Some r -> String.trim r <> "" && present r

(* Fail-closed compatibility entrypoint for historical evidence rows. *)
let admit ~(present : presence) ~(at_revision : string) (e : evidence) : verdict =
  if e.ev < 1 || e.ev > 109 then Not_admitted "EV is outside the authorized range 1..109"
  else if String.trim at_revision = "" then Not_admitted "no candidate revision given"
  else if e.revision <> at_revision then
    Not_admitted
      ("evidence is bound to revision " ^ e.revision ^ ", not to " ^ at_revision)
  else
    match key_present present e.runtime_ref, key_present present e.formal_ref with
    | true, true -> Not_admitted
        "legacy file references do not establish executed evidence or sovereign admission"
    | false, true -> Not_admitted "runtime key absent: no fresh observed behaviour"
    | true, false -> Not_admitted "formal key absent: no machine-checkable specification"
    | false, false -> Not_admitted "no evidence"

(* L4: cycles are sequential, so a gap makes every later cycle inadmissible
   regardless of its own evidence. Returns the verdicts with the gap rule
   applied, lowest EV first. *)
let apply_no_gap (results : (int * verdict) list) : (int * verdict) list =
  let sorted = List.sort (fun (a, _) (b, _) -> compare a b) results in
  let rec duplicate = function
    | (a, _) :: (b, _) :: _ when a = b -> true
    | _ :: tl -> duplicate tl
    | [] -> false in
  let malformed =
    if List.exists (fun (n, _) -> n < 1 || n > 109) sorted then
      Some "EV is outside the authorized range 1..109"
    else if duplicate sorted then Some "duplicate EV identifier"
    else None in
  let rec go expected prev_admitted acc = function
    | [] -> List.rev acc
    | (n, v) :: tl ->
      let v' =
        match v, (prev_admitted && n = expected) with
        | Admitted, false ->
          Not_admitted ("gap: EV-" ^ string_of_int (n - 1) ^ " is not admitted")
        | _ -> v in
      go (n + 1) (v' = Admitted) ((n, v') :: acc) tl in
  match malformed with
  | Some reason -> List.map (fun (n, _) -> n, Not_admitted reason) sorted
  | None -> go 1 true [] sorted

let admitted_count results =
  List.length (List.filter (fun (_, v) -> v = Admitted) (apply_no_gap results))

(* The ceiling is derived, never asserted: it is the highest EV such that every
   cycle up to and including it is admitted. *)
let ceiling results =
  let sorted = apply_no_gap results in
  let rec go last = function
    | (n, Admitted) :: tl when n = last + 1 -> go n tl
    | _ -> last in
  go 0 sorted
