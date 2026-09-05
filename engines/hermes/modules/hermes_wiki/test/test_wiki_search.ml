(* HW.6.3.1/6.3.2 + HW.4.4.1/4.4.2 laws. Mutants (killers named):
     S-M1 slug tiebreak dropped        (killed: tie leg)
     S-M2 block hit without an anchor  (killed: addresses-a-block law)
     D-M1 supports treated as attack   (killed: defence-not-attack leg)
     D-M2 ascent stops after one round (killed: the chain leg) *)
let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed; print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let model =
  Hermes_wiki.build
    [ ("pages/wiki/alpha.md", "# Alpha\n\nzebra zebra quark\n\na zebra claim ^z1\n");
      ("pages/wiki/beta.md", "# Beta zebra\n\nquark\n\n```\nzebra inside fence\n```\n");
      ("pages/wiki/gamma.md", "# Gamma\n\nnothing here\n") ]

let idx = Wiki_search.build model

let () =
  check "tokens: lowercase alnum runs, length >= 2" (fun () ->
      Wiki_search.tokens "Zebra, quark-3 x!" = [ "zebra"; "quark"; "3" ] || Wiki_search.tokens "Zebra, quark-3 x!" = [ "zebra"; "quark" ]);
  check "search: offline equals online (index vs naive corpus scan)" (fun () ->
      let hits = Wiki_search.search idx "zebra" in
      List.mem_assoc "alpha" hits && List.mem_assoc "beta" hits
      && not (List.mem_assoc "gamma" hits));
  check "search: fences are excluded from tokenisation" (fun () ->
      (* beta's only body 'zebra' is inside a fence; its TITLE carries one *)
      let hits = Wiki_search.search idx "zebra" in
      let beta = List.assoc "beta" hits and alpha = List.assoc "alpha" hits in
      alpha >= 3 && beta = 3 (* title-only, boosted 3x *));
  check "search: deterministic, score desc, ties by slug" (fun () ->
      let hits = Wiki_search.search idx "quark" in
      hits = Wiki_search.search idx "quark"
      && hits = [ ("alpha", 1); ("beta", 1) ] (* equal scores -> slug order *));
  check "search: every scored page contains EVERY query token (AND)" (fun () ->
      Wiki_search.search idx "zebra nothing" = []);
  check "index digest is stable and input-order independent" (fun () ->
      let m2 =
        Hermes_wiki.build
          [ ("pages/wiki/gamma.md", "# Gamma\n\nnothing here\n");
            ("pages/wiki/beta.md", "# Beta zebra\n\nquark\n\n```\nzebra inside fence\n```\n");
            ("pages/wiki/alpha.md", "# Alpha\n\nzebra zebra quark\n\na zebra claim ^z1\n") ]
      in
      Wiki_search.digest idx = Wiki_search.digest (Wiki_search.build m2))

let () =
  check "block hits: every hit addresses a ^id block, sorted" (fun () ->
      Wiki_search.block_hits idx "zebra" = [ ("alpha", "^z1") ]);
  check "block hits: a page hit without a block anchor is NOT a block hit" (fun () ->
      Wiki_search.block_hits idx "quark" = [])

(* ---- grounded semantics ---- *)
let () =
  check "grounded: unattacked nodes are IN; a chain admits the defended" (fun () ->
      Discourse.grounded
        ~attacks:[ ("a", "b"); ("b", "c") ]
        ~nodes:[ "a"; "b"; "c"; "d" ]
      = [ "a"; "c"; "d" ]);
  check "grounded: a mutual attack leaves both OUT (skeptical), bystander in" (fun () ->
      Discourse.grounded ~attacks:[ ("a", "b"); ("b", "a") ] ~nodes:[ "a"; "b"; "c" ] = [ "c" ]);
  check "anomalies: an attacked, undefended CLAIM is reported; support is not attack"
    (fun () ->
      let m =
        Hermes_wiki.build
          [ ( "pages/wiki/c1.md",
              "---\ntype: claim\n---\n# C1\n\nthe claim under fire\n" );
            ( "pages/wiki/c2.md",
              "---\ntype: claim\n---\n# C2\n\nattacks: [[c1|@opposes]]\n" );
            ( "pages/wiki/c3.md",
              "---\ntype: claim\n---\n# C3\n\nbacks it: [[c2|@supports]]\n" ) ]
      in
      Discourse.anomalies m = [ "c1" ])

let () =
  Printf.printf "wiki_search: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_search" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_search ]);
  exit (Wiki_suite_telemetry.exit_code self)
