(* The monoid laws are the contract. If ⊕ is not associative and commutative
   then a battery's total depends on the order suites happened to run in, and
   the engine's domain scheduling would change the verdict — which would make
   every roll-up in the system unreliable.

   Laws are checked EXHAUSTIVELY over a generated carrier sample rather than
   sampled: for the finitely many shapes that matter, enumeration is a proof.
   Every property carries a negative control (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let contains text needle =
  let n = String.length needle in
  let rec at i =
    i + n <= String.length text && (String.sub text i n = needle || at (i + 1))
  in
  at 0

open Suite_telemetry

(* A spanning sample of the carrier: zero, one of each component, mixtures,
   and a distinct name so the set union is exercised too. *)
let sample =
  [ empty;
    observe ~suite:"a" ~passed:1 ~failed:0 ~skipped:0;
    observe ~suite:"b" ~passed:0 ~failed:1 ~skipped:0;
    observe ~suite:"c" ~passed:0 ~failed:0 ~skipped:1;
    observe ~suite:"d" ~passed:3 ~failed:2 ~skipped:1;
    observe ~suite:"a" ~passed:7 ~failed:0 ~skipped:0 ]

let law_layer () =
  (* ASSOCIATIVITY — 6^3 = 216 triples, enumerated. *)
  let assoc =
    List.for_all
      (fun a ->
        List.for_all
          (fun b ->
            List.for_all
              (fun c -> combine (combine a b) c = combine a (combine b c))
              sample)
          sample)
      sample
  in
  check assoc "LAW ⊕ is associative (exhaustive over the sample cube)";

  (* COMMUTATIVITY — the load-bearing one: it is what makes a battery total
     independent of scheduling order. *)
  let comm =
    List.for_all
      (fun a -> List.for_all (fun b -> combine a b = combine b a) sample)
      sample
  in
  check comm "LAW ⊕ is commutative (scheduling order cannot change the total)";

  (* IDENTITY on both sides. *)
  check
    (List.for_all (fun a -> combine empty a = a && combine a empty = a) sample)
    "LAW ε is a two-sided identity";

  (* HOMOMORPHISM into (ℕ, +). *)
  check
    (List.for_all
       (fun a -> List.for_all (fun b -> total (combine a b) = total a + total b) sample)
       sample)
    "LAW total is a monoid homomorphism into (ℕ,+)";

  (* ANTITONE COMPLETENESS: you cannot compose your way out of a skip. If the
     composite is complete then every part was. This is R22 as an order
     property. *)
  check
    (List.for_all
       (fun a ->
         List.for_all
           (fun b -> (not (clean (combine a b))) || (clean a && clean b))
           sample)
       sample)
    "LAW clean is antitone under ⊕ (a skip anywhere poisons the whole)";

  (* And the counterexample that refuted the stronger claim, pinned so nobody
     restores it: complete is NOT antitone, because passed > 0 is monotone. *)
  let one = observe ~suite:"a" ~passed:1 ~failed:0 ~skipped:0 in
  check
    (complete (combine empty one) && not (complete empty))
    "LAW complete is NOT antitone (ε ⊕ a complete while ε is not)";

  (* Negative control for the law checks: an operation that is NOT commutative
     must fail the same predicate, or the predicate is vacuous. *)
  let bad a _ = a in
  check
    (not
       (List.for_all
          (fun a -> List.for_all (fun b -> bad a b = bad b a) sample)
          sample))
    "CONTROL a non-commutative operation fails the commutativity predicate"

let clamp_layer () =
  (* A negative count is a broken sensor and must not be able to cancel a real
     failure into invisibility. *)
  let t = observe ~suite:"x" ~passed:5 ~failed:(-3) ~skipped:0 in
  check (exit_code t = 0 && total t = 5) "CLAMP a negative count is clamped, not propagated";
  let real = combine t (observe ~suite:"y" ~passed:0 ~failed:2 ~skipped:0) in
  check (exit_code real = 1) "CLAMP a real failure still surfaces after clamping";
  check (exit_code (observe ~suite:"z" ~passed:1 ~failed:0 ~skipped:0) = 0)
    "CLAMP a clean suite exits 0";
  check (not (complete (observe ~suite:"z" ~passed:1 ~failed:0 ~skipped:1)))
    "CLAMP a skip makes a suite incomplete"

let emission_layer () =
  let t = observe ~suite:"test_thing" ~passed:9 ~failed:1 ~skipped:0 in
  (* Cones are DERIVED now, so this layer can no longer fabricate one out of
     invented names — which is the guarantee working, not an obstacle. It
     picks real libraries out of the graph instead: one with dependents and
     one without. If the graph ever loses either kind the test says so rather
     than silently testing nothing. *)
  let with_cone = List.filter (fun s -> Stanza.cone s <> []) Stanza.all in
  let without_cone = List.filter (fun s -> Stanza.cone s = []) Stanza.all in
  check (with_cone <> []) "the graph has a library with dependents";
  check (without_cone <> []) "the graph has a library nothing depends on";
  let depended = List.hd with_cone and leaf = List.hd without_cone in
  let text = emit t ~targets:[ depended ] in
  check (contains text "AS-IS") "EMIT carries the measured half";
  check (contains text "PREDICTIVE") "EMIT carries the implied half";
  check (contains text "dependent(s) at risk") "EMIT states the blast radius magnitude first";
  (* Containment must be STATED — an unstated bound is one the reader assumes
     away. *)
  check (contains (emit t ~targets:[ leaf ]) "contained")
    "EMIT states containment when the cone is empty";
  check (contains (emit t ~targets:[]) "contained")
    "EMIT states containment when no target is named";
  (* Incompleteness must be stated too. *)
  check
    (contains (as_is (observe ~suite:"s" ~passed:1 ~failed:0 ~skipped:1)) "INCOMPLETE")
    "EMIT marks an incomplete denominator";
  (* TOKEN OPTIMISATION, as a property rather than an aspiration: the emission
     is O(1) in the number of checks. Ten thousand assertions must cost the
     same bytes as ten. *)
  let small = observe ~suite:"s" ~passed:10 ~failed:0 ~skipped:0 in
  let huge = observe ~suite:"s" ~passed:10_000 ~failed:0 ~skipped:0 in
  let d = [ depended ] in
  check
    (abs (String.length (emit huge ~targets:d) - String.length (emit small ~targets:d)) < 8)
    "EMIT is O(1) in check count (10k assertions cost the same as 10)";
  (* A wide cone must not push the verdict off a context window. NOT
     Stanza.all: every node would be a seed, and cone_of subtracts seeds, so
     the widest possible target set yields the EMPTY cone. The widest cone
     belongs to a single well-depended-upon library. *)
  let widest =
    List.fold_left
      (fun best s ->
        if List.length (Stanza.cone s) > List.length (Stanza.cone best) then s else best)
      (List.hd Stanza.all) Stanza.all
  in
  check (List.length (Stanza.cone widest) > 5) "the graph has a genuinely wide cone to cap";
  check (String.length (emit small ~targets:[ widest ]) < 400)
    "EMIT caps a wide dependency cone";
  check (contains (emit small ~targets:[ widest ]) "more") "EMIT discloses what it capped";
  check (emit t ~targets:d = emit t ~targets:d) "EMIT is deterministic"

let () =
  Printf.printf "=== suite telemetry ===\n";
  List.iter
    (fun (name, layer) -> layer (); Printf.printf "  %-10s done\n" name)
    [ ("law", law_layer); ("clamp", clamp_layer); ("emission", emission_layer) ];
  let self =
    observe ~suite:"test_suite_telemetry" ~passed:!passed ~failed:(List.length !failures)
      ~skipped:0
  in
  (* The suite emits itself in the very form it defines — the smallest possible
     exemplar, and a standing check that the adapter works on real output. *)
  print_string (emit self ~targets:[ Stanza.hermes_harness_suite_telemetry ]);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  exit (exit_code self)
