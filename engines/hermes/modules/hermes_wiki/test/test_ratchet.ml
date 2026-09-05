(* HW.10.2.1 + HW.10.2.2 — the control plane's laws.

   Mutation battery (killers named in advance):
     R-M1 boundary       — check uses >= instead of >   (killed: equal-is-Ok leg)
     R-M2 optimistic     — evaluate drops unknown gauges (killed: fail-closed legs)
     R-M3 blanket        — applies matches kind only     (killed: typed law)
     R-M4 unsorted       — serialize_pins loses the canonical order
                                                        (killed: canonical leg) *)

let passed = ref 0
let failed = ref 0

let check_ name f =
  match f () with
  | true -> incr passed
  | false ->
      incr failed;
      print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

(* ------------------------------------------------------------- ratchet *)

let () =
  check_ "check: equal counts HOLD (the boundary is >, never >=)" (fun () ->
      Ratchet.check ~previous:5 ~current:5 = Ok ());
  check_ "check: a decrease holds" (fun () -> Ratchet.check ~previous:5 ~current:4 = Ok ());
  check_ "check: an increase refuses" (fun () ->
      match Ratchet.check ~previous:5 ~current:6 with Error _ -> true | Ok () -> false);
  check_ "judge: trichotomy Held/Improved/Breached" (fun () ->
      Ratchet.judge ~gauge:"g" ~previous:3 ~current:3 = Ratchet.Held { gauge = "g"; at = 3 }
      && Ratchet.judge ~gauge:"g" ~previous:3 ~current:1
         = Ratchet.Improved { gauge = "g"; previous = 3; current = 1 }
      && Ratchet.judge ~gauge:"g" ~previous:3 ~current:9
         = Ratchet.Breached { gauge = "g"; previous = 3; current = 9 })

let () =
  check_ "parse_pins is total: a malformed line is a NAMED error" (fun () ->
      match Ratchet.parse_pins [ "schema_debt 12"; "what even is this line" ] with
      | Error e -> e <> ""
      | Ok _ -> false);
  check_ "parse_pins refuses a duplicate gauge (write functionality)" (fun () ->
      match Ratchet.parse_pins [ "a 1"; "a 2" ] with Error _ -> true | Ok _ -> false);
  check_ "parse_pins skips comments and blanks" (fun () ->
      Ratchet.parse_pins [ "# ratchet pins"; ""; "b 2"; "a 1" ] = Ok [ ("a", 1); ("b", 2) ]);
  check_ "serialize/parse round-trip on the canonical (sorted) form" (fun () ->
      let pins = [ ("zeta", 9); ("alpha", 3); ("mid", 0) ] in
      match Ratchet.parse_pins (Ratchet.serialize_pins pins) with
      | Ok p -> p = List.sort compare pins
      | Error _ -> false);
  check_ "serialize is canonical: already-sorted in, byte-stable out" (fun () ->
      Ratchet.serialize_pins [ ("b", 2); ("a", 1) ] = [ "a 1"; "b 2" ])

let () =
  check_ "evaluate: verdicts per gauge, sorted by gauge" (fun () ->
      match
        Ratchet.evaluate
          ~pins:[ ("a", 5); ("b", 5); ("c", 5) ]
          ~gauges:[ ("c", 9); ("a", 5); ("b", 1) ]
      with
      | Ok
          [ Ratchet.Held { gauge = "a"; at = 5 };
            Ratchet.Improved { gauge = "b"; previous = 5; current = 1 };
            Ratchet.Breached { gauge = "c"; previous = 5; current = 9 } ] ->
          true
      | _ -> false);
  check_ "evaluate fails closed: a sensed gauge without a pin is drift, NAMED" (fun () ->
      match Ratchet.evaluate ~pins:[ ("a", 1) ] ~gauges:[ ("a", 1); ("ghost", 0) ] with
      | Error e -> (try ignore (Str.search_forward (Str.regexp_string "ghost") e 0); true with Not_found -> false)
      | Ok _ -> false);
  check_ "evaluate fails closed: a pin nobody sensed is drift, NAMED" (fun () ->
      match Ratchet.evaluate ~pins:[ ("a", 1); ("unsensed", 3) ] ~gauges:[ ("a", 1) ] with
      | Error e -> (try ignore (Str.search_forward (Str.regexp_string "unsensed") e 0); true with Not_found -> false)
      | Ok _ -> false);
  check_ "breaches selects exactly the Breached verdicts" (fun () ->
      match Ratchet.evaluate ~pins:[ ("a", 0); ("b", 0) ] ~gauges:[ ("a", 1); ("b", 0) ] with
      | Ok vs -> (
          match Ratchet.breaches vs with
          | [ Ratchet.Breached { gauge = "a"; _ } ] -> true
          | _ -> false)
      | Error _ -> false)

(* meta-falsification: the gate can fire — a staged increase is refused
   end to end through check, judge and evaluate. *)
let () =
  check_ "meta-falsification: a staged +1 breaches through every layer" (fun () ->
      Ratchet.check ~previous:0 ~current:1 <> Ok ()
      && (match Ratchet.judge ~gauge:"x" ~previous:0 ~current:1 with
         | Ratchet.Breached _ -> true
         | _ -> false)
      &&
      match Ratchet.evaluate ~pins:[ ("x", 0) ] ~gauges:[ ("x", 1) ] with
      | Ok vs -> Ratchet.breaches vs <> []
      | Error _ -> false)

(* ---------------------------------------------------------- suppression *)

let lines =
  [ "# suppressions";
    "dead_anchor|features/yuque-toc.md#missing|imported doc, backfill scheduled|2026-09-01";
    "schema_gap|import-manifest|manifest is not corpus|" ]

let () =
  check_ "suppression parse is total and named on malformed input" (fun () ->
      match Suppression.parse [ "no pipes here at all" ] with
      | Error e -> e <> ""
      | Ok _ -> false);
  check_ "an empty reason is refused — an unexplained exception is a hole" (fun () ->
      match Suppression.parse [ "kind|key||2026-01-01" ] with
      | Error _ -> true
      | Ok _ -> false);
  check_ "parse/serialize round-trip" (fun () ->
      match Suppression.parse lines with
      | Ok ts -> Suppression.parse (Suppression.serialize ts) = Ok ts
      | Error _ -> false)

let () =
  check_ "THE TYPED LAW: suppressing (kind, key) leaves every other diagnostic active"
    (fun () ->
      match Suppression.parse lines with
      | Error _ -> false
      | Ok ts ->
          Suppression.applies ts ~kind:"dead_anchor" ~key:"features/yuque-toc.md#missing"
          && (not (Suppression.applies ts ~kind:"dead_anchor" ~key:"some/other/page.md#x"))
          && (not (Suppression.applies ts ~kind:"dead_link" ~key:"features/yuque-toc.md#missing"))
          && not (Suppression.applies ts ~kind:"schema_gap" ~key:"features/yuque-toc.md#missing"))

let () =
  check_ "expiry: dated suppressions lapse; undated ones stand (R16: date supplied)"
    (fun () ->
      match Suppression.parse lines with
      | Error _ -> false
      | Ok ts ->
          List.length (Suppression.active ts ~today:"2026-08-09") = 2
          && List.length (Suppression.active ts ~today:"2026-09-02") = 1
          && List.length (Suppression.expired ts ~today:"2026-09-02") = 1)

let () =
  check_ "R2: disclose renders EVERY suppression, active or not" (fun () ->
      match Suppression.parse lines with
      | Error _ -> false
      | Ok ts -> List.length (Suppression.disclose ts) = 2)

(* ----------------------------- backfill: the converge loop's pure core *)

let facts =
  {
    Backfill.slug = "pa";
    group = "features";
    authored = [ "type"; "status" ];
    ntype = "reference";
    status = "draft";
    tags = [ "wiki"; "zk" ];
    first_add = Some "2026-08-09";
    missing = [ "ktype"; "maturity"; "domain"; "topics"; "created" ];
  }

let () =
  check_ "backfill proposes EXACTLY one entry per missing field, in order" (fun () ->
      let ps = Backfill.propose facts in
      List.length ps = 5
      && List.map
           (function Backfill.Set { field; _ } -> field | Backfill.Ask { field; _ } -> field)
           ps
         = [ "ktype"; "maturity"; "domain"; "topics"; "created" ]);
  check_ "backfill never invents: created is git evidence or an Ask" (fun () ->
      let with_git = Backfill.propose facts in
      let without = Backfill.propose { facts with Backfill.first_add = None } in
      List.exists
        (function
          | Backfill.Set { field = "created"; value = "2026-08-09"; evidence = Backfill.From_git _ } ->
              true
          | _ -> false)
        with_git
      && List.exists
           (function Backfill.Ask { field = "created"; _ } -> true | _ -> false)
           without);
  check_ "backfill maps the evidence it has: reference->source, draft->seed, tags->topics"
    (fun () ->
      let ps = Backfill.propose facts in
      List.exists
        (function Backfill.Set { field = "ktype"; value = "source"; _ } -> true | _ -> false)
        ps
      && List.exists
           (function Backfill.Set { field = "maturity"; value = "seed"; _ } -> true | _ -> false)
           ps
      && List.exists
           (function Backfill.Set { field = "topics"; value = "[wiki, zk]"; _ } -> true | _ -> false)
           ps);
  check_ "backfill asks instead of guessing: no type, no status, no tags" (fun () ->
      let bare =
        Backfill.propose
          { facts with Backfill.ntype = ""; status = ""; tags = []; first_add = None }
      in
      (* domain included: it has no exemption any more — see below *)
      List.for_all (function Backfill.Ask _ -> true | Backfill.Set _ -> false) bare);
  check_ "DOMAIN IS NEVER SET: a directory name is not a controlled-vocabulary term"
    (fun () ->
      (* The defect this pins: proposing domain = the page's GROUP wrote a
         path fragment into a field whose vocabulary is closed, and
         disagreed with every human-authored value in the corpus. A
         directory is a location, not a subject — so domain is always an
         authoring decision. *)
      List.for_all
        (fun g ->
          List.for_all
            (function Backfill.Set { field = "domain"; _ } -> false | _ -> true)
            (Backfill.propose { facts with Backfill.group = g }))
        [ "features"; "zk"; "bonsai"; "playbooks"; "journal"; "" ]);
  check_ "A MODEL DEFAULT IS NOT EVIDENCE: an unauthored status/type is never cited"
    (fun () ->
      (* The defect this pins: a document that carries a frontmatter block
         but never writes `status:` still reads back status="published"
         (meta_of's default). Citing that as From_status manufactures
         provenance for a claim the author never made. The values below
         are exactly what such a page presents; only `authored` tells the
         truth, so only `authored` may decide. *)
      let defaulted =
        { facts with Backfill.authored = [ "id" ]; ntype = "note"; status = "published" }
      in
      List.for_all
        (function
          | Backfill.Set { field = "ktype"; _ } | Backfill.Set { field = "maturity"; _ } -> false
          | _ -> true)
        (Backfill.propose defaulted));
  check_ "an AUTHORED status/type is still evidence (the guard is not a blanket refusal)"
    (fun () ->
      let ps = Backfill.propose facts in
      List.exists (function Backfill.Set { field = "ktype"; _ } -> true | _ -> false) ps
      && List.exists (function Backfill.Set { field = "maturity"; _ } -> true | _ -> false) ps);
  check_ "domain is ASKED, and the ask names the vocabulary the author must pick from"
    (fun () ->
      List.exists
        (function
          | Backfill.Ask { field = "domain"; why } ->
              let has n =
                let nh = String.length why and nn = String.length n in
                let rec go i = i + nn <= nh && (String.sub why i nn = n || go (i + 1)) in
                go 0
              in
              has "controlled"
          | _ -> false)
        (Backfill.propose facts));
  check_ "backfill never touches a field that is not missing" (fun () ->
      let ps = Backfill.propose { facts with Backfill.missing = [ "created" ] } in
      List.length ps = 1);
  check_ "backfill is deterministic (two runs equal)" (fun () ->
      Backfill.propose facts = Backfill.propose facts);
  check_ "maturity is never PROPOSED as evergreen (evergreen is earned)" (fun () ->
      List.for_all
        (fun st ->
          List.for_all
            (function Backfill.Set { field = "maturity"; value = "evergreen"; _ } -> false | _ -> true)
            (Backfill.propose { facts with Backfill.status = st }))
        [ "draft"; "published"; "archived"; "" ])

(* ------------------------------- OTel logging: R4 outward, one line each *)

let () =
  check_ "otel severity numbers are the OTel anchors, strictly monotone" (fun () ->
      List.map Wiki_otel.severity_number
        [ Wiki_otel.Trace; Wiki_otel.Debug; Wiki_otel.Info; Wiki_otel.Warn; Wiki_otel.Error_ ]
      = [ 1; 5; 9; 13; 17 ]);
  check_ "otel render is deterministic and byte-pinned" (fun () ->
      let r =
        Wiki_otel.record ~ts:"2026-08-09T12:00:00Z" ~severity:Wiki_otel.Info
          ~body:"gauge sensed" ~attrs:[ ("gauge", "schema_debt"); ("value", "1224") ]
      in
      Wiki_otel.render r
      = "{\"ts\":\"2026-08-09T12:00:00Z\",\"severity_number\":9,\"severity_text\":\"INFO\","
        ^ "\"body\":\"gauge sensed\",\"attributes\":{\"gauge\":\"schema_debt\",\"value\":\"1224\"}}"
      && Wiki_otel.render r = Wiki_otel.render r);
  check_ "otel verdict mapping: breach WARNs, hold and improvement INFO" (fun () ->
      let sev v = (Wiki_otel.of_verdict ~ts:"t" v).Wiki_otel.severity in
      sev (Ratchet.Breached { gauge = "g"; previous = 0; current = 1 }) = Wiki_otel.Warn
      && sev (Ratchet.Held { gauge = "g"; at = 0 }) = Wiki_otel.Info
      && sev (Ratchet.Improved { gauge = "g"; previous = 2; current = 1 }) = Wiki_otel.Info);
  check_ "otel state transitions carry actor and both states as attributes" (fun () ->
      let r = Wiki_otel.state_transition ~ts:"t" ~actor:"auditLoop" ~from_:"Idle" ~to_:"Sensing" in
      List.mem ("actor", "auditLoop") r.Wiki_otel.attrs
      && List.mem ("from", "Idle") r.Wiki_otel.attrs
      && List.mem ("to", "Sensing") r.Wiki_otel.attrs);
  check_ "otel quotes and backslashes are escaped (the line stays one JSON object)"
    (fun () ->
      let r =
        Wiki_otel.record ~ts:"t" ~severity:Wiki_otel.Warn ~body:"say \"hi\" \\ there" ~attrs:[]
      in
      let s = Wiki_otel.render r in
      (try ignore (Str.search_forward (Str.regexp_string "\\\"hi\\\"") s 0); true
       with Not_found -> false))

(* ------------------------- the FPP correspondence law (model <-> control) *)

let topology_channels =
  List.concat_map
    (fun (c : Fpp_model.component) ->
      List.map (fun (ch : Fpp_model.channel) -> ch.Fpp_model.chan_name) c.Fpp_model.channels)
    Wiki_topology.model.Fpp_model.components

let () =
  check_ "every pinned gauge is a Wiki_topology telemetry channel (the FPP law)"
    (fun () ->
      let path = "modules/hermes_wiki/baseline/ratchet-gauges.txt" in
      if not (Sys.file_exists path) then (
        print_endline "  (pin file absent — the audit tool pins it; failing closed)";
        false)
      else
        let ic = open_in path in
        let rec go acc = match input_line ic with
          | l -> go (l :: acc)
          | exception End_of_file -> close_in ic; List.rev acc
        in
        match Ratchet.parse_pins (go []) with
        | Error e -> print_endline ("  " ^ e); false
        | Ok pins ->
            List.for_all
              (fun (g, _) ->
                List.mem g topology_channels
                || (print_endline ("  gauge not in the actor model: " ^ g); false))
              pins)

let () =
  Printf.printf "ratchet: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_ratchet" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
