(* HW.9.3.2–.6 — the doctest extension family, across the full
   functional envelope:

     N*  nominal      declared grammar, pairing, transcripts, fixtures
     D*  declaration  normalisation is DECLARED, never inferred (HW.9.3.2)
     P*  pairing      testcode/testoutput, and fence ownership (HW.9.3.3)
     C*  cleanup      runs on every path, especially failure (HW.9.3.4)
     I*  isolation    groups together = each group alone (HW.9.3.5)
     K*  skipif       declared, answered, DISCLOSED and counted (HW.9.3.6)
     X*  exhaustion   many groups, many cases, a large body
     S*  stuck        no blocks, only fixtures, a broken interpreter
     A*  anomaly      malformed info, malformed bodies, foreign fences

   The differential ones are actually differential: I1 runs the whole
   corpus and each group alone and compares the two RESULTS, rather than
   asserting that isolation was intended. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

let has_prefix p l = String.length l >= String.length p && String.sub l 0 (String.length p) = p

(* ------------------------------------------------ the injected world *)

(* A pure world: the list of sources the interpreter has been handed, in
   order. Cleanup's effect is therefore OBSERVABLE rather than asserted,
   and `count` makes a leaked world change a STATUS, not merely a log. *)
let eval w src =
  let w' = w @ [ src ] in
  if src = "boom" then (w', Wiki_doctest.Raised "the example blew up")
  else if src = "kaboom" then raise (Failure "interpreter is broken")
  else if src = "count" then (w', Wiki_doctest.Output (string_of_int (List.length w)))
  else if has_prefix "echo " src then
    (w', Wiki_doctest.Output (String.sub src 5 (String.length src - 5)))
  else (w', Wiki_doctest.Output "")

(* DECLARED conditions only: two the environment can answer, everything
   else it honestly cannot. *)
let env = function "win32" -> Some true | "posix" -> Some false | _ -> None
let blocks md = Wiki_doctest.blocks_of_markdown ~page:"p" md
let run md = Wiki_doctest.run ~eval ~world:[] ~env (blocks md)
let fence info body = "```" ^ info ^ "\n" ^ body ^ "```\n\n"

let statuses r =
  List.concat_map (fun g -> List.map (fun x -> x.Wiki_doctest.status) g.Wiki_doctest.results)
    r.Wiki_doctest.runs

let worlds r = List.map (fun g -> (g.Wiki_doctest.name, g.Wiki_doctest.world)) r.Wiki_doctest.runs

(* ------------------------------------------------------------ nominal *)

let () =
  check "N1 each of the five directives is RECOGNISED, and only those" (fun () ->
      let k i = Option.map (fun h -> h.Wiki_doctest.kind) (Wiki_doctest.header_of_info i) in
      k "testsetup" = Some Wiki_doctest.Testsetup
      && k "testcode" = Some Wiki_doctest.Testcode
      && k "testoutput" = Some Wiki_doctest.Testoutput
      && k "testcleanup" = Some Wiki_doctest.Testcleanup
      && k "doctest" = Some Wiki_doctest.Transcript
      && k "ocaml" = None && k "" = None && k "testcodex" = None);
  check "N2 an undeclared group is the DEFAULT group, never inferred from position"
    (fun () ->
      match Wiki_doctest.header_of_info "testcode" with
      | None -> false
      | Some h ->
          h.Wiki_doctest.group = Wiki_doctest.default_group
          && h.Wiki_doctest.skipif = None
          && h.Wiki_doctest.norm = Wiki_doctest.no_normalisation
          && h.Wiki_doctest.bad = []);
  check "N3 a DECLARED pair whose output matches byte-exact PASSES" (fun () ->
      let r = run (fence "testcode" "echo hi\n" ^ fence "testoutput" "hi\n") in
      r.Wiki_doctest.passed = 1 && r.Wiki_doctest.failed = 0 && r.Wiki_doctest.refused = 0);
  check "N4 a DECLARED pair whose output differs FAILS, and names both sides" (fun () ->
      let r = run (fence "testcode" "echo hi\n" ^ fence "testoutput" "bye\n") in
      r.Wiki_doctest.failed = 1 && r.Wiki_doctest.passed = 0
      && List.exists
           (function Wiki_doctest.Failed m -> contains m "\"hi\"" && contains m "\"bye\"" | _ -> false)
           (statuses r));
  check "N5 blocks are collected in DOCUMENT ORDER with stable ordinals" (fun () ->
      let bs = blocks (fence "testsetup" "a\n" ^ fence "testcode" "b\n" ^ fence "testoutput" "\n") in
      List.map (fun b -> b.Wiki_doctest.ordinal) bs = [ 0; 1; 2 ]
      && List.map (fun b -> b.Wiki_doctest.head.Wiki_doctest.kind) bs
         = [ Wiki_doctest.Testsetup; Wiki_doctest.Testcode; Wiki_doctest.Testoutput ]);
  check "N6 a SETUP runs before the cases and its effect is in the world" (fun () ->
      let r =
        run
          (fence "testsetup" "echo prepared\n" ^ fence "testcode" "count\n"
         ^ fence "testoutput" "1\n")
      in
      (* count sees exactly one prior evaluation: the setup *)
      r.Wiki_doctest.passed = 1 && worlds r = [ (Wiki_doctest.default_group, [ "echo prepared"; "count" ]) ]);
  check "N7 a successful FIXTURE is not a test: it inflates no counter" (fun () ->
      let r = run (fence "testsetup" "echo a\n" ^ fence "testcleanup" "echo b\n") in
      r.Wiki_doctest.passed = 0 && r.Wiki_doctest.failed = 0
      && r.Wiki_doctest.skipped = 0 && r.Wiki_doctest.refused = 0
      && worlds r = [ (Wiki_doctest.default_group, [ "echo a"; "echo b" ]) ])

(* ---------------------------------- HW.9.3.2 normalisation, DECLARED *)

let () =
  check "D1 with NOTHING declared, comparison is byte equality and nothing else" (fun () ->
      Wiki_doctest.compare_output Wiki_doctest.no_normalisation ~expected:"a" ~observed:"a"
      && (not
            (Wiki_doctest.compare_output Wiki_doctest.no_normalisation ~expected:"a "
               ~observed:"a"))
      && not
           (Wiki_doctest.compare_output Wiki_doctest.no_normalisation ~expected:"a  b"
              ~observed:"a b"));
  check "D2 KILLER: an output differing ONLY by whitespace FAILS when nothing was declared"
    (fun () ->
      (* the runner must never decide two outputs are close enough *)
      let r = run (fence "testcode" "echo hi \n" ^ fence "testoutput" "hi\n") in
      r.Wiki_doctest.failed = 1 && r.Wiki_doctest.passed = 0);
  check "D3 the SAME case passes once `:trim-whitespace:` is DECLARED" (fun () ->
      let r = run (fence "testcode" "echo hi \n" ^ fence "testoutput :trim-whitespace:" "hi\n") in
      r.Wiki_doctest.passed = 1 && r.Wiki_doctest.failed = 0);
  check "D4 each flag does ONLY what it says: trim does not collapse, collapse does not trim"
    (fun () ->
      let trim = { Wiki_doctest.trim_whitespace = true; normalise_whitespace = false } in
      let coll = { Wiki_doctest.trim_whitespace = false; normalise_whitespace = true } in
      (not (Wiki_doctest.compare_output trim ~expected:"a  b" ~observed:"a b"))
      && Wiki_doctest.compare_output trim ~expected:"  a b  " ~observed:"a b"
      && Wiki_doctest.compare_output coll ~expected:"a  b" ~observed:"a b"
      && not (Wiki_doctest.compare_output coll ~expected:" a" ~observed:"a"));
  check "D5 the declaration may sit on EITHER half of the pair" (fun () ->
      let a = run (fence "testcode :trim-whitespace:" "echo hi \n" ^ fence "testoutput" "hi\n") in
      let b = run (fence "testcode" "echo hi \n" ^ fence "testoutput :trim-whitespace:" "hi\n") in
      a.Wiki_doctest.passed = 1 && b.Wiki_doctest.passed = 1);
  check "D6 an UNKNOWN option is refused, never ignored" (fun () ->
      (* ignoring an unparsed option is how :skipif: becomes "run anyway" *)
      (match Wiki_doctest.header_of_info "testcode :fuzzy:" with
      | Some h -> h.Wiki_doctest.bad <> []
      | None -> false)
      &&
      let r = run (fence "testcode :fuzzy:" "echo hi\n" ^ fence "testoutput" "hi\n") in
      r.Wiki_doctest.refused = 1 && r.Wiki_doctest.passed = 0);
  check "D7 an option with a MISSING argument is a named gap, not a silent rebinding" (fun () ->
      match Wiki_doctest.header_of_info "testcode :group:" with
      | None -> false
      | Some h -> h.Wiki_doctest.bad <> [] && h.Wiki_doctest.group = Wiki_doctest.default_group);
  check "D9 `:trim-whitespace:` drops leading/trailing BLANK LINES too — and only when declared"
    (fun () ->
      (* an authored expectation is usually written with air around it;
         dropping that air is part of what the flag DECLARES, and is not
         something the runner may do on its own *)
      let padded = fence "testcode" "echo hi\n" ^ fence "testoutput" "\nhi\n\n" in
      let declared = fence "testcode" "echo hi\n" ^ fence "testoutput :trim-whitespace:" "\nhi\n\n" in
      (run padded).Wiki_doctest.failed = 1
      && (run declared).Wiki_doctest.passed = 1
      && Wiki_doctest.compare_output
           { Wiki_doctest.trim_whitespace = true; normalise_whitespace = false }
           ~expected:"\n\nhi\n\n" ~observed:"hi"
      && not
           (Wiki_doctest.compare_output
              { Wiki_doctest.trim_whitespace = false; normalise_whitespace = true }
              ~expected:"\n\nhi\n\n" ~observed:"hi"));
  check "D8 an option cannot swallow the NEXT option as its value" (fun () ->
      match Wiki_doctest.header_of_info "testcode :group: :skipif: win32" with
      | None -> false
      | Some h -> h.Wiki_doctest.bad <> [] && h.Wiki_doctest.skipif = Some "win32")

(* -------------------- HW.9.3.2/.3 pairing and fence OWNERSHIP *)

let () =
  check "P1 pairing survives a FIXTURE written between the two halves" (fun () ->
      let r =
        run
          (fence "testcode" "echo hi\n" ^ fence "testcleanup" "echo bye\n"
         ^ fence "testoutput" "hi\n")
      in
      r.Wiki_doctest.passed = 1 && r.Wiki_doctest.refused = 0);
  check "P2 KILLER: a testcode with NO testoutput is REFUSED, never passed" (fun () ->
      let r = run (fence "testcode" "echo hi\n") in
      r.Wiki_doctest.refused = 1 && r.Wiki_doctest.passed = 0 && r.Wiki_doctest.failed = 0
      && List.exists (fun d -> contains d "no testoutput") r.Wiki_doctest.disclosures);
  check "P3 an ORPHAN testoutput is refused: an expectation with nothing to expect" (fun () ->
      let r = run (fence "testoutput" "hi\n") in
      r.Wiki_doctest.refused = 1 && r.Wiki_doctest.passed = 0);
  check "P4 TRANSCRIPT: `>>>` runs split in order and each is its own case" (fun () ->
      let r = run (fence "doctest" ">>> echo one\none\n>>> echo two\ntwo\n") in
      r.Wiki_doctest.passed = 2 && r.Wiki_doctest.failed = 0);
  check "P5 TRANSCRIPT order is preserved: a blank separator is not an expectation" (fun () ->
      let r = run (fence "doctest" ">>> echo one\n\none\n\n>>> echo two\n\ntwo\n") in
      r.Wiki_doctest.passed = 2 && r.Wiki_doctest.failed = 0);
  check "P6 TRANSCRIPT continuation `...` joins the statement above it" (fun () ->
      let cs = Wiki_doctest.transcript_cases [ ">>> echo a"; "... b"; "a"; "b" ] in
      cs = [ ([ "echo a"; "b" ], [ "a"; "b" ]) ]);
  check "P7 a transcript case that DIVERGES fails and is named" (fun () ->
      let r = run (fence "doctest" ">>> echo one\nTWO\n") in
      r.Wiki_doctest.failed = 1 && r.Wiki_doctest.passed = 0);
  check "P8 OWNERSHIP: a `> ` doctest fence is the PARENT builder's and yields no case here"
    (fun () ->
      let bs = blocks (fence "doctest" "> plain\n<p>plain</p>\n") in
      List.length bs = 1
      && Wiki_doctest.transcript_cases (List.hd bs).Wiki_doctest.body = []
      &&
      let r = Wiki_doctest.run ~eval ~world:[] ~env bs in
      r.Wiki_doctest.passed = 0 && r.Wiki_doctest.failed = 0 && r.Wiki_doctest.refused = 0);
  check "P9 OWNERSHIP: a `>>>` transcript is invisible to the parent builder (no false drift)"
    (fun () ->
      let m =
        Hermes_wiki.build [ ("docs/x/dt.md", "# DT\n\n" ^ fence "doctest" ">>> echo one\none\n") ]
      in
      Hermes_wiki.doctest_drift m = []
      && List.length (Wiki_doctest.blocks_of_model m) = 1
      && (Wiki_doctest.run ~eval ~world:[] ~env (Wiki_doctest.blocks_of_model m))
           .Wiki_doctest.passed
         = 1);
  check "P10 a doctest fence declaring NEITHER marker is checked by nobody, and says so"
    (fun () ->
      let md = fence "doctest" "just prose\n" in
      let m = Hermes_wiki.build [ ("docs/x/dt.md", "# DT\n\n" ^ md) ] in
      (* the parent is silent on it too — which is exactly why we are not *)
      Hermes_wiki.doctest_drift m = []
      && List.length (Wiki_doctest.unchecked (blocks md)) = 1
      && (run md).Wiki_doctest.refused = 1)

(* --------------------------- HW.9.3.4 cleanup runs on EVERY path *)

let () =
  check "C1 cleanup runs after a PASSING group, and its effect is in the world" (fun () ->
      let r =
        run
          (fence "testcode" "echo hi\n" ^ fence "testoutput" "hi\n"
         ^ fence "testcleanup" "echo swept\n")
      in
      r.Wiki_doctest.passed = 1
      && worlds r = [ (Wiki_doctest.default_group, [ "echo hi"; "echo swept" ]) ]);
  check "C2 KILLER: cleanup runs even when the BODY FAILS (differential on the world)"
    (fun () ->
      let ok =
        run
          (fence "testcode" "echo hi\n" ^ fence "testoutput" "hi\n"
         ^ fence "testcleanup" "echo swept\n")
      in
      let bad =
        run
          (fence "testcode" "echo hi\n" ^ fence "testoutput" "WRONG\n"
         ^ fence "testcleanup" "echo swept\n")
      in
      bad.Wiki_doctest.failed = 1 && ok.Wiki_doctest.failed = 0
      (* the failing run must sweep exactly as the passing one did *)
      && worlds bad = worlds ok);
  check "C3 cleanup runs even when the example blew the interpreter up" (fun () ->
      let r =
        run (fence "testcode" "boom\n" ^ fence "testoutput" "\n" ^ fence "testcleanup" "echo swept\n")
      in
      r.Wiki_doctest.failed = 1
      && worlds r = [ (Wiki_doctest.default_group, [ "boom"; "echo swept" ]) ]);
  check "C4 cleanup runs even when the SETUP itself failed" (fun () ->
      let r =
        run
          (fence "testsetup" "boom\n" ^ fence "testcode" "echo hi\n" ^ fence "testoutput" "hi\n"
         ^ fence "testcleanup" "echo swept\n")
      in
      (* FAIL-CLOSED: the case is refused, not run without its fixture *)
      r.Wiki_doctest.refused = 1 && r.Wiki_doctest.passed = 0 && r.Wiki_doctest.failed = 1
      && worlds r = [ (Wiki_doctest.default_group, [ "boom"; "echo swept" ]) ]);
  check "C5 cleanup runs when the group has NO cases at all" (fun () ->
      let r = run (fence "testcleanup" "echo swept\n") in
      worlds r = [ (Wiki_doctest.default_group, [ "echo swept" ]) ]);
  check "C6 cleanup runs when every case was SKIPPED" (fun () ->
      let r =
        run
          (fence "testcode :skipif: win32" "echo hi\n" ^ fence "testoutput" "hi\n"
         ^ fence "testcleanup" "echo swept\n")
      in
      r.Wiki_doctest.skipped = 1
      && worlds r = [ (Wiki_doctest.default_group, [ "echo swept" ]) ])

(* --------------------------------- HW.9.3.5 the ISOLATION law *)

(* Three groups that would interfere if anything threaded between them:
   `a` evaluates twice, `b` asserts it has seen NOTHING, `c` fails. *)
let iso =
  fence "testsetup :group: a" "echo one\n"
  ^ fence "testcode :group: a" "echo two\n"
  ^ fence "testoutput :group: a" "two\n"
  ^ fence "testcode :group: b" "count\n"
  ^ fence "testoutput :group: b" "0\n"
  ^ fence "testcode :group: c" "echo x\n"
  ^ fence "testoutput :group: c" "y\n"
  ^ fence "testcleanup :group: a" "echo swept\n"

let iso_blocks = blocks iso

let only g =
  List.filter (fun b -> b.Wiki_doctest.head.Wiki_doctest.group = g) iso_blocks

let () =
  check "I1 KILLER: for EVERY group, together = alone — same results, ids and world" (fun () ->
      let together = Wiki_doctest.run ~eval ~world:[] ~env iso_blocks in
      List.for_all
        (fun g ->
          let alone = Wiki_doctest.run ~eval ~world:[] ~env (only g) in
          match
            ( List.find_opt (fun r -> r.Wiki_doctest.name = g) together.Wiki_doctest.runs,
              alone.Wiki_doctest.runs )
          with
          | Some x, [ y ] -> x = y
          | Some _, ([] | _ :: _ :: _) | None, _ -> false)
        (Wiki_doctest.groups iso_blocks));
  check "I2 no group is made to PASS by a neighbour's leftovers" (fun () ->
      (* group b asserts it has seen nothing; group a runs three sources *)
      let r = Wiki_doctest.run ~eval ~world:[] ~env iso_blocks in
      r.Wiki_doctest.passed = 2 && r.Wiki_doctest.failed = 1);
  check "I3 no group is BROKEN by a neighbour either: c fails identically alone" (fun () ->
      let alone = Wiki_doctest.run ~eval ~world:[] ~env (only "c") in
      alone.Wiki_doctest.failed = 1 && alone.Wiki_doctest.passed = 0);
  check "I4 every group starts from the SAME initial world" (fun () ->
      let r = Wiki_doctest.run ~eval ~world:[] ~env iso_blocks in
      worlds r
      = [ ("a", [ "echo one"; "echo two"; "echo swept" ]); ("b", [ "count" ]); ("c", [ "echo x" ]) ]);
  check "I5 the report is in `groups` order regardless of the order blocks arrived" (fun () ->
      let a = Wiki_doctest.run ~eval ~world:[] ~env iso_blocks in
      let b = Wiki_doctest.run ~eval ~world:[] ~env (List.rev iso_blocks) in
      List.map (fun g -> g.Wiki_doctest.name) a.Wiki_doctest.runs = [ "a"; "b"; "c" ]
      && List.map (fun g -> g.Wiki_doctest.name) b.Wiki_doctest.runs = [ "a"; "b"; "c" ]);
  check "I6 membership is DECLARED, never inferred from adjacency" (fun () ->
      let bs =
        blocks
          (fence "testcode :group: far" "echo hi\n" ^ fence "testcode :group: near" "echo no\n"
         ^ fence "testoutput :group: far" "hi\n")
      in
      let r = Wiki_doctest.run ~eval ~world:[] ~env bs in
      (* the `far` pair pairs across an intervening block of another group *)
      r.Wiki_doctest.passed = 1 && r.Wiki_doctest.refused = 1)

(* ------------------------------------ HW.9.3.6 :skipif:, disclosed *)

let () =
  check "K1 a DECLARED condition the environment answers TRUE skips the case" (fun () ->
      let r = run (fence "testcode :skipif: win32" "echo hi\n" ^ fence "testoutput" "hi\n") in
      r.Wiki_doctest.skipped = 1 && r.Wiki_doctest.passed = 0 && r.Wiki_doctest.failed = 0);
  check "K2 KILLER: a skip NEVER counts as a pass, and the world shows it did not run"
    (fun () ->
      let r = run (fence "testcode :skipif: win32" "echo hi\n" ^ fence "testoutput" "hi\n") in
      r.Wiki_doctest.passed = 0 && worlds r = [ (Wiki_doctest.default_group, []) ]);
  check "K3 KILLER: every skip is DISCLOSED by name and reason (R2)" (fun () ->
      let r = run (fence "testcode :skipif: win32" "echo hi\n" ^ fence "testoutput" "hi\n") in
      List.length r.Wiki_doctest.disclosures = 1
      && List.exists
           (fun d -> contains d "SKIPPED" && contains d "win32")
           r.Wiki_doctest.disclosures);
  check "K4 a condition answered FALSE runs the case normally" (fun () ->
      let r = run (fence "testcode :skipif: posix" "echo hi\n" ^ fence "testoutput" "hi\n") in
      r.Wiki_doctest.passed = 1 && r.Wiki_doctest.skipped = 0);
  check "K5 KILLER: a condition the environment CANNOT answer is REFUSED, fail-closed" (fun () ->
      let r = run (fence "testcode :skipif: plan9" "echo hi\n" ^ fence "testoutput" "hi\n") in
      r.Wiki_doctest.refused = 1 && r.Wiki_doctest.passed = 0 && r.Wiki_doctest.skipped = 0
      && r.Wiki_doctest.failed = 0
      (* neither run nor quietly skipped *)
      && worlds r = [ (Wiki_doctest.default_group, []) ]
      && List.exists (fun d -> contains d "cannot answer") r.Wiki_doctest.disclosures);
  check "K6 an environment that RAISES is a refusal, never a silent run" (fun () ->
      let env_bad _ = raise (Failure "no such oracle") in
      let r =
        Wiki_doctest.run ~eval ~world:[] ~env:env_bad
          (blocks (fence "testcode :skipif: win32" "echo hi\n" ^ fence "testoutput" "hi\n"))
      in
      r.Wiki_doctest.refused = 1 && r.Wiki_doctest.passed = 0);
  check "K7 CONFLICTING conditions across a pair refuse rather than pick one" (fun () ->
      let r =
        run
          (fence "testcode :skipif: win32" "echo hi\n" ^ fence "testoutput :skipif: posix" "hi\n")
      in
      r.Wiki_doctest.refused = 1
      && List.exists (fun d -> contains d "conflicting") r.Wiki_doctest.disclosures);
  check "K8 a skipped SETUP refuses its group's cases (fail-closed on a missing fixture)"
    (fun () ->
      let r =
        run
          (fence "testsetup :skipif: win32" "echo prep\n" ^ fence "testcode" "echo hi\n"
         ^ fence "testoutput" "hi\n")
      in
      r.Wiki_doctest.skipped = 1 && r.Wiki_doctest.refused = 1 && r.Wiki_doctest.passed = 0)

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 many GROUPS: each is run once, and the counters add up" (fun () ->
      let md =
        String.concat ""
          (List.init 60 (fun i ->
               let g = Printf.sprintf ":group: g%d" i in
               fence ("testcode " ^ g) "echo hi\n" ^ fence ("testoutput " ^ g) "hi\n"))
      in
      let r = run md in
      List.length r.Wiki_doctest.runs = 60 && r.Wiki_doctest.passed = 60
      && r.Wiki_doctest.failed = 0);
  check "X2 many CASES in one transcript" (fun () ->
      let body =
        String.concat "" (List.init 200 (fun i -> Printf.sprintf ">>> echo %d\n%d\n" i i))
      in
      let r = run (fence "doctest" body) in
      r.Wiki_doctest.passed = 200 && r.Wiki_doctest.failed = 0);
  check "X3 a LARGE body is compared without truncation" (fun () ->
      let big = String.make 40000 'x' in
      let r = run (fence "testcode" ("echo " ^ big ^ "\n") ^ fence "testoutput" (big ^ "\n")) in
      r.Wiki_doctest.passed = 1);
  check "X4 a large body differing in ONE byte still fails" (fun () ->
      let big = String.make 40000 'x' in
      let r =
        run (fence "testcode" ("echo " ^ big ^ "\n") ^ fence "testoutput" (big ^ "y\n"))
      in
      r.Wiki_doctest.failed = 1)

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 NO blocks: an empty report, every counter zero, nothing invented" (fun () ->
      let r = run "" in
      r.Wiki_doctest.runs = [] && r.Wiki_doctest.passed = 0 && r.Wiki_doctest.failed = 0
      && r.Wiki_doctest.skipped = 0 && r.Wiki_doctest.refused = 0
      && r.Wiki_doctest.disclosures = []);
  check "S2 an EMPTY fence body is a declared expectation of nothing" (fun () ->
      let r = run (fence "testcode" "" ^ fence "testoutput" "") in
      r.Wiki_doctest.passed = 1);
  check "S3 a BROKEN interpreter refuses and leaves the world untouched" (fun () ->
      let r = run (fence "testcode" "kaboom\n" ^ fence "testoutput" "\n") in
      r.Wiki_doctest.refused = 1 && r.Wiki_doctest.failed = 0 && r.Wiki_doctest.passed = 0
      && worlds r = [ (Wiki_doctest.default_group, []) ]);
  check "S4 the example blowing up (Failed) is NEVER conflated with the interpreter breaking"
    (fun () ->
      let ex = run (fence "testcode" "boom\n" ^ fence "testoutput" "\n") in
      let it = run (fence "testcode" "kaboom\n" ^ fence "testoutput" "\n") in
      ex.Wiki_doctest.failed = 1 && ex.Wiki_doctest.refused = 0
      && it.Wiki_doctest.refused = 1 && it.Wiki_doctest.failed = 0);
  check "S5 a group of only REFUSALS still reports them, one per block" (fun () ->
      let r = run (fence "testoutput" "a\n" ^ fence "testoutput" "b\n") in
      r.Wiki_doctest.refused = 2 && List.length r.Wiki_doctest.disclosures = 2)

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 TOTAL over pathological info strings" (fun () ->
      List.for_all
        (fun i -> match Wiki_doctest.header_of_info i with Some _ | None -> true)
        [ ""; " "; ":"; "::"; ":group:"; "testcode :"; "testcode ::::";
          "testcode :group:"; String.make 5000 ':'; "\t\t"; "testcode\ttestoutput" ]);
  check "A2 TOTAL over pathological bodies" (fun () ->
      List.for_all
        (fun b -> match run (fence "doctest" b) with _ -> true)
        [ ""; ">>>\n"; "...\n"; ">>> \n"; ">\n"; ">>>>\n"; String.make 3000 '>' ^ "\n" ]);
  check "A3 a foreign fence is NOT a doctest block" (fun () ->
      blocks (fence "ocaml" "let x = 1\n") = [] && blocks (fence "" "plain\n") = []);
  check "A4 a literalinclude fence never becomes a doctest block" (fun () ->
      (* its body belongs to a file; counting it as a test invents drift *)
      blocks (fence "literalinclude doctest" "whatever\n") = []);
  check "A5 an allow_example_links page is EXCLUDED from the corpus sweep" (fun () ->
      let body = "# DT\n\n" ^ fence "testcode" "echo hi\n" ^ fence "testoutput" "hi\n" in
      let plain = Hermes_wiki.build [ ("docs/x/dt.md", body) ] in
      let exempt =
        Hermes_wiki.build
          [ ("docs/x/dt.md", "---\nallow_example_links: true\n---\n\n" ^ body) ]
      in
      List.length (Wiki_doctest.blocks_of_model plain) = 2
      && Wiki_doctest.blocks_of_model exempt = []);
  check "A6 a marker that only LOOKS like one opens no case" (fun () ->
      Wiki_doctest.transcript_cases [ ">>>>x"; "a" ] = []
      && Wiki_doctest.transcript_cases [ ">>x"; "a" ] = []);
  check "A7 `groups` is sorted and deduplicated, so the report is deterministic" (fun () ->
      let bs =
        blocks
          (fence "testcode :group: z" "a\n" ^ fence "testcode :group: a" "b\n"
         ^ fence "testcode :group: z" "c\n")
      in
      Wiki_doctest.groups bs = [ "a"; "z" ]);
  check "A8 `unchecked` reports only the doubly-silent fence, not every fence" (fun () ->
      Wiki_doctest.unchecked (blocks (fence "doctest" ">>> echo a\na\n")) = []
      && Wiki_doctest.unchecked (blocks (fence "doctest" "> a\n<p>a</p>\n")) = []
      && Wiki_doctest.unchecked (blocks (fence "testcode" "prose\n")) = []
      && List.length (Wiki_doctest.unchecked (blocks (fence "doctest" "prose\n"))) = 1)

(* ------------------------------------------- the REGISTER probes *)

(* The five `~derived` bodies handed to feature_register, verbatim and
   self-contained. They live here so they are compiled and RUN by this
   suite: a probe that has quietly stopped exercising its row is a green
   register entry backed by nothing. *)

let () =
  check "R1 HW.9.3.2 probe: testcode/testoutput, normalisation DECLARED" (fun () ->
      try
        let b i o =
          Wiki_doctest.blocks_of_markdown ~page:"p"
            ("```testcode\necho hi \n```\n\n```testoutput" ^ i ^ "\n" ^ o ^ "\n```\n")
        in
        let ev w s =
          ( w @ [ s ],
            if String.length s > 5 && String.sub s 0 5 = "echo " then
              Wiki_doctest.Output (String.sub s 5 (String.length s - 5))
            else Wiki_doctest.Output "" )
        in
        let go bs = Wiki_doctest.run ~eval:ev ~world:[] ~env:(fun _ -> None) bs in
        (go (b "" "hi")).Wiki_doctest.failed = 1
        && (go (b " :trim-whitespace:" "hi")).Wiki_doctest.passed = 1
        && (go (b "" "hi")).Wiki_doctest.passed = 0
        && not
             (Wiki_doctest.compare_output Wiki_doctest.no_normalisation ~expected:"hi "
                ~observed:"hi")
      with _ -> false);
  check "R2 HW.9.3.3 probe: transcript form, ordered, invisible to the parent" (fun () ->
      try
        let md = "```doctest\n>>> echo one\none\n>>> echo two\ntwo\n```\n" in
        let ev w s =
          ( w @ [ s ],
            Wiki_doctest.Output
              (if String.length s > 5 then String.sub s 5 (String.length s - 5) else "") )
        in
        let r =
          Wiki_doctest.run ~eval:ev ~world:[] ~env:(fun _ -> None)
            (Wiki_doctest.blocks_of_markdown ~page:"p" md)
        in
        let m = Hermes_wiki.build [ ("docs/x/dt.md", "# DT\n\n" ^ md) ] in
        r.Wiki_doctest.passed = 2 && r.Wiki_doctest.failed = 0
        && Wiki_doctest.transcript_cases [ ">>> a"; "1"; ">>> b"; "2" ]
           = [ ([ "a" ], [ "1" ]); ([ "b" ], [ "2" ]) ]
        && Hermes_wiki.doctest_drift m = []
      with _ -> false);
  check "R3 HW.9.3.4 probe: cleanup runs even on failure" (fun () ->
      try
        let ev w s = (w @ [ s ], Wiki_doctest.Output "") in
        let go exp =
          Wiki_doctest.run ~eval:ev ~world:[] ~env:(fun _ -> None)
            (Wiki_doctest.blocks_of_markdown ~page:"p"
               ("```testcode\nbody\n```\n\n```testoutput\n" ^ exp
              ^ "\n```\n\n```testcleanup\nsweep\n```\n"))
        in
        let w r = List.map (fun g -> g.Wiki_doctest.world) r.Wiki_doctest.runs in
        let ok = go "" and bad = go "WRONG" in
        bad.Wiki_doctest.failed = 1 && ok.Wiki_doctest.failed = 0
        && w bad = [ [ "body"; "sweep" ] ]
        && w bad = w ok
      with _ -> false);
  check "R4 HW.9.3.5 probe: groups together = each group alone" (fun () ->
      try
        let ev w s =
          (w @ [ s ], Wiki_doctest.Output (if s = "count" then string_of_int (List.length w) else ""))
        in
        let f k g = "```" ^ k ^ " :group: " ^ g ^ "\n" in
        let md =
          f "testcode" "a" ^ "x\n```\n\n" ^ f "testoutput" "a" ^ "\n```\n\n" ^ f "testcode" "b"
          ^ "count\n```\n\n" ^ f "testoutput" "b" ^ "0\n```\n"
        in
        let bs = Wiki_doctest.blocks_of_markdown ~page:"p" md in
        let go l = Wiki_doctest.run ~eval:ev ~world:[] ~env:(fun _ -> None) l in
        let all = go bs in
        all.Wiki_doctest.passed = 2
        && List.for_all
             (fun g ->
               match
                 ( List.find_opt (fun r -> r.Wiki_doctest.name = g) all.Wiki_doctest.runs,
                   (go
                      (List.filter (fun b -> b.Wiki_doctest.head.Wiki_doctest.group = g) bs))
                     .Wiki_doctest.runs )
               with
               | Some x, [ y ] -> x = y
               | _ -> false)
             (Wiki_doctest.groups bs)
      with _ -> false);
  check "R5 HW.9.3.6 probe: skips DISCLOSED and counted, unknown condition refused" (fun () ->
      try
        let ev w s = (w @ [ s ], Wiki_doctest.Output "") in
        let go c e =
          Wiki_doctest.run ~eval:ev ~world:[] ~env:e
            (Wiki_doctest.blocks_of_markdown ~page:"p"
               ("```testcode :skipif: " ^ c ^ "\nbody\n```\n\n```testoutput\n\n```\n"))
        in
        let yes = go "win32" (fun _ -> Some true) in
        let no = go "win32" (fun _ -> Some false) in
        let dunno = go "plan9" (fun _ -> None) in
        yes.Wiki_doctest.skipped = 1 && yes.Wiki_doctest.passed = 0
        && List.exists
             (fun d -> String.length d > 7 && String.sub d 0 7 = "SKIPPED")
             yes.Wiki_doctest.disclosures
        && List.map (fun g -> g.Wiki_doctest.world) yes.Wiki_doctest.runs = [ [] ]
        && no.Wiki_doctest.passed = 1
        && dunno.Wiki_doctest.refused = 1
        && dunno.Wiki_doctest.skipped = 0
        && dunno.Wiki_doctest.passed = 0
      with _ -> false)

let () =
  Printf.printf "wiki_doctest: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_doctest" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_doctest ]);
  exit (Wiki_suite_telemetry.exit_code self)
