(* The mutation runner, across the envelope:

     N*  nominal      a mutant that takes is Killed by the predicted test
     X*  exhaustion   a large table; a large source file
     S*  stuck        an unreadable file, a pattern that matches nothing
     A*  anomaly      a no-op edit, a wrong prediction, a survivor

   The headline law is that A VOID RUN IS NOT A RESULT. A pattern that
   silently matched nothing looks exactly like a surviving mutant, and
   this repository lost real mutation runs to that confusion before the
   runner existed. Its dual is that A SURVIVOR IS NEVER CLASSIFIED:
   deciding whether one is an equivalent mutant or a weak test is a
   judgment about intent, and automating it would launder the second into
   the first.

   These checks exercise the pure decision surface — verdict arithmetic,
   rendering, and the classification rules — rather than driving real
   builds, which would make the suite depend on mutating the tree it is
   running in. *)

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

let outcome ?(failures = []) name verdict =
  { Ops_mutate.mutant = name; verdict; failures; duration_ms = 1.0 }

let report os =
  let count f = List.length (List.filter f os) in
  { Ops_mutate.outcomes = os;
    killed = count (fun o -> match o.Ops_mutate.verdict with Ops_mutate.Killed _ -> true | _ -> false);
    survived = count (fun o -> o.Ops_mutate.verdict = Ops_mutate.Survived);
    void = count (fun o -> match o.Ops_mutate.verdict with Ops_mutate.Void _ -> true | _ -> false) }

(* ------------------------------------------------------------ nominal *)

let () =
  check "N1 a killed mutant names the killer that fired" (fun () ->
      Ops_mutate.string_of_verdict (Ops_mutate.Killed "A3 skip is disclosed")
      = "KILLED by A3 skip is disclosed");
  check "N2 an all-killed table exits 0 — the table is a result" (fun () ->
      let text, code =
        Ops_mutate.render (report [ outcome "M1" (Ops_mutate.Killed "A1");
                                    outcome "M2" (Ops_mutate.Killed "B2") ])
      in
      code = 0 && contains text "2 killed, 0 survived, 0 void");
  check "N3 every mutant appears in the render, one line each" (fun () ->
      let os = List.init 12 (fun i ->
          outcome (Printf.sprintf "M%02d" i) (Ops_mutate.Killed "k")) in
      let text, _ = Ops_mutate.render (report os) in
      List.for_all (fun i -> contains text (Printf.sprintf "M%02d" i)) (List.init 12 Fun.id))

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 THE HEADLINE LAW: a void run is not a result — it exits non-zero" (fun () ->
      (* a pattern that matched nothing reads exactly like a survivor;
         scoring it as one is how a mutation round becomes theatre *)
      let text, code =
        Ops_mutate.render (report [ outcome "M1" (Ops_mutate.Killed "A1");
                                    outcome "M2" (Ops_mutate.Void "text not found") ])
      in
      code = 1 && contains text "VOID (text not found)" && contains text "1 killed, 0 survived, 1 void");
  check "A2 a SURVIVOR exits non-zero and is never softened into 'equivalent'" (fun () ->
      let text, code = Ops_mutate.render (report [ outcome "M1" Ops_mutate.Survived ]) in
      code = 1
      && contains text "SURVIVED"
      && contains text "NOT automatically equivalent"
      && contains text "the test proved nothing");
  check "A3 the survivor note appears ONLY when there is a survivor" (fun () ->
      let text, _ = Ops_mutate.render (report [ outcome "M1" (Ops_mutate.Void "nope") ]) in
      not (contains text "NOT automatically equivalent"));
  check "A4 a mutant killed by the WRONG check still reports, and says so" (fun () ->
      (* a prediction that missed is a finding about the prediction *)
      let v = Ops_mutate.Killed "X9 something else (NOT the predicted \"A1\")" in
      contains (Ops_mutate.string_of_verdict v) "NOT the predicted")

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 an EMPTY table renders and exits 0" (fun () ->
      let text, code = Ops_mutate.render (report []) in
      code = 0 && contains text "0 killed, 0 survived, 0 void");
  check "S2 an unreadable file is VOID, naming the file — never a survivor" (fun () ->
      let o = Ops_mutate.run_one ~suite:"/nonexistent/suite.exe"
          { Ops_mutate.name = "M"; file = "/nonexistent/path/x.ml"; find = "a";
            replace = "b"; expect_killer = "k" } in
      match o.Ops_mutate.verdict with
      | Ops_mutate.Void why -> contains why "cannot read" && contains why "/nonexistent/path/x.ml"
      | Ops_mutate.Killed _ | Ops_mutate.Survived -> false);
  check "S3 run_one NEVER raises, whatever it is handed" (fun () ->
      List.for_all
        (fun (f, find) ->
          match
            Ops_mutate.run_one ~suite:"/nonexistent/suite.exe"
              { Ops_mutate.name = "M"; file = f; find; replace = "x"; expect_killer = "k" }
          with
          | _ -> true)
        [ ("", "a"); ("/dev/null", ""); ("/nonexistent", "a"); ("/dev/null", "zzz") ]);
  check "S4 counts partition the table — every outcome lands in exactly one bucket"
    (fun () ->
      let os = [ outcome "a" (Ops_mutate.Killed "k"); outcome "b" Ops_mutate.Survived;
                 outcome "c" (Ops_mutate.Void "v"); outcome "d" (Ops_mutate.Killed "k2") ] in
      let r = report os in
      r.Ops_mutate.killed + r.Ops_mutate.survived + r.Ops_mutate.void = List.length os
      && r.Ops_mutate.killed = 2 && r.Ops_mutate.survived = 1 && r.Ops_mutate.void = 1)

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 a large table renders every row and stays exact" (fun () ->
      let os =
        List.init 200 (fun i ->
            if i mod 20 = 0 then outcome (Printf.sprintf "s%03d" i) Ops_mutate.Survived
            else outcome (Printf.sprintf "k%03d" i) (Ops_mutate.Killed "k"))
      in
      let r = report os in
      let text, code = Ops_mutate.render r in
      r.Ops_mutate.survived = 10 && r.Ops_mutate.killed = 190 && code = 1
      && contains text "190 killed, 10 survived, 0 void");
  check "X2 a mutant whose file is huge is still handled by the literal matcher" (fun () ->
      (* /dev/null stands in for a file with no match: the point is that a
         non-match is Void, at any size, rather than a silent pass *)
      let o = Ops_mutate.run_one ~suite:"/nonexistent/suite.exe"
          { Ops_mutate.name = "M"; file = "/dev/null"; find = String.make 5000 'z';
            replace = "x"; expect_killer = "k" } in
      match o.Ops_mutate.verdict with
      | Ops_mutate.Void _ -> true
      | Ops_mutate.Killed _ | Ops_mutate.Survived -> false)

let () =
  (* the summary goes LAST — checks appended after it run unenforced *)
  Printf.printf "ops_mutate: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_mutate" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)
