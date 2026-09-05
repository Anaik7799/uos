(* R14 MIRROR of Hermes_harness.Suite_telemetry across the wiki liftability
   boundary (the guard law forbids hermes_harness_* here). Same algebra, same
   emission format; a later consolidation is mechanical. Do not let the two
   drift: the format is the contract.

   R30 in one line of code, so that conforming is cheaper than not.

   The carrier is a commutative monoid over (ℕ³, +) with the suite name
   degrading to a set union. Commutativity is the property that matters: it
   makes a battery's total independent of the order suites run in, which is
   what lets the engine schedule across domains without changing the verdict.

   Completeness is antitone under composition — a skip anywhere poisons the
   whole — so there is no way to compose out of an incomplete denominator.
   That is R22 expressed as an order property rather than a habit. *)

type t = {
  suites : string list;   (* set, kept sorted and unique so ⊕ is commutative *)
  passed : int;
  failed : int;
  skipped : int;
}

let empty = { suites = []; passed = 0; failed = 0; skipped = 0 }

(* Clamp rather than propagate. A negative count is a broken sensor, and a
   broken sensor must never be able to make a total look healthier by
   cancelling a real failure (R19 cl. 2: fail closed on a value the tool
   cannot determine, never a default that reads as health). *)
let nonneg n = if n < 0 then 0 else n

let observe ~suite ~passed ~failed ~skipped =
  { suites = (if suite = "" then [] else [ suite ]);
    passed = nonneg passed; failed = nonneg failed; skipped = nonneg skipped }

let combine a b =
  { suites = List.sort_uniq compare (a.suites @ b.suites);
    passed = a.passed + b.passed;
    failed = a.failed + b.failed;
    skipped = a.skipped + b.skipped }

let concat ts = List.fold_left combine empty ts

let total t = t.passed + t.failed + t.skipped

(* The antitone part: sums of non-negatives, so a zero total forces zero
   parts. This is what cannot be composed away. *)
let clean t = t.failed = 0 && t.skipped = 0

(* complete adds a NON-VACUITY condition, and that part is monotone: ε is not
   complete but ε ⊕ a can be. Keeping them separate is why the law test
   passes; conflating them is why an earlier draft failed. *)
let complete t = clean t && t.passed > 0

let exit_code t = if t.failed > 0 then 1 else 0

let name t = match t.suites with [] -> "(none)" | [ s ] -> s | l -> String.concat "+" l

(* ------------------------------------------------------------- emission *)

let as_is t =
  Printf.sprintf "AS-IS %s: %d/%d passed, %d failed, %d skipped%s\n" (name t) t.passed
    (total t) t.failed t.skipped
    (if clean t then (if complete t then "" else "  [NO CHECKS RAN]")
     else if t.skipped > 0 then "  [INCOMPLETE DENOMINATOR]"
     else "  [FAILURES PRESENT]")

(* Cone DERIVED from typed targets. A caller states what the suite covers —
   a fact it knows and the type checks — and the blast radius follows from
   the dune graph, which the caller cannot state at all. Before this, 201 of
   241 declared names were executables or bare directories: things that
   cannot be a reverse dependency of anything. *)
let predictive t ~targets =
  let dependents = List.map Stanza.name (Stanza.cone_of targets) in
  match dependents with
  | [] ->
      Printf.sprintf "PREDICTIVE %s: no dependents — a failure here is contained\n" (name t)
  | _ ->
      (* The cone is the bound on foresight, so it is stated as a count first:
         a reader sizing risk needs the magnitude before the names, and the
         names are capped so a wide cone cannot push the verdict off the end
         of a context window. *)
      let shown = List.filteri (fun i _ -> i < 5) dependents in
      let hidden = List.length dependents - List.length shown in
      Printf.sprintf "PREDICTIVE %s: %d dependent(s) at risk if this is wrong: %s%s\n" (name t)
        (List.length dependents) (String.concat ", " shown)
        (if hidden > 0 then Printf.sprintf " … +%d more" hidden else "")

let render_line t =
  Printf.sprintf "%s %d/%d passed, %d failed, %d skipped, exit %d" (name t) t.passed
    (total t) t.failed t.skipped (exit_code t)

(* Token-optimised by construction: the emission is O(1) in the number of
   checks. A suite with ten thousand assertions emits exactly as many lines as
   one with three, which is what makes this affordable across every suite
   rather than only the interesting ones. *)
let emit t ~targets = as_is t ^ predictive t ~targets
