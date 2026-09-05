(* HW.1.3.10–14 — ordering and labelling, across the full functional
   envelope:

     N*  nominal      declared order, derived order, labels, keywords
     X*  exhaustion   a large corpus, every position equal, huge numbers
     S*  stuck        no positions declared at all, unknown slug, one page
     A*  anomaly      malformed positions, duplicate claims, empty corpus

   The headline law: THE ORDER IS TOTAL. Every corpus has exactly one
   sequence, it is a function of the declared metadata and never of the
   filesystem, and a reader walking `next` from the first page reaches
   the last and then stops. Its dual: pagination is MUTUALLY INVERSE, so
   a reader who goes forward and then back is where they started. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let page ?(group = "guide") ?fm ?(body = "") name =
  let front =
    match fm with None -> "" | Some f -> "---\n" ^ f ^ "\n---\n"
  in
  ("docs/hermes/" ^ group ^ "/" ^ name ^ ".md", front ^ body)

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

let model files = Hermes_wiki.build files
let slugs m = List.map (fun e -> e.Wiki_ordering.slug) (Wiki_ordering.ordered m)

(* ------------------------------------------------------------ nominal *)

let () =
  check "N1 sidebar_position gives the DECLARED order, not the input order" (fun () ->
      let m =
        model
          [ page ~fm:"sidebar_position: 3" "zulu";
            page ~fm:"sidebar_position: 1" "alpha";
            page ~fm:"sidebar_position: 2" "mike" ]
      in
      slugs m = [ "alpha"; "mike"; "zulu" ]);
  check "N2 a number PREFIX orders when no position is declared" (fun () ->
      let m = model [ page "20-late"; page "03-early"; page "10-middle" ] in
      slugs m = [ "03-early"; "10-middle"; "20-late" ]);
  check "N2b a DATE prefix is not a position — the live corpus proved this" (fun () ->
      (* without the digit bound the corpus reported 23 conflicts, every
         one a dated filename: an ordinal is a sequence number, and a
         sequence number is short *)
      let m =
        model [ page "2026-08-09-notes"; page "2026-08-08-plan"; page "20260807-adr" ]
      in
      List.for_all (fun e -> e.Wiki_ordering.position = None) (Wiki_ordering.ordered m)
      && Wiki_ordering.position_conflicts m = []
      (* they still order — by slug, byte-wise, which is not the same as
         chronological ('-' sorts before a digit) but IS total and does
         not depend on the filesystem *)
      && slugs m = [ "2026-08-08-plan"; "2026-08-09-notes"; "20260807-adr" ]);
  check "N2c the bound is on DIGITS, not on the value: 999- orders, 1000- does not"
    (fun () ->
      Wiki_ordering.number_prefix "999-x" = (Some 999, "x")
      && Wiki_ordering.number_prefix "1000-x" = (None, "1000-x")
      && Wiki_ordering.max_prefix_digits = 3);
  check "N3 EXPLICIT position DOMINATES a conflicting prefix on the same page" (fun () ->
      (* 90-first says 90; the frontmatter says 1 and must win, or two
         mechanisms decide the same question and ordering is a coin toss *)
      let m = model [ page ~fm:"sidebar_position: 1" "90-first"; page ~fm:"sidebar_position: 2" "b" ] in
      slugs m = [ "90-first"; "b" ]);
  check "N4 sidebar_label OVERRIDES the title; absent falls back to it" (fun () ->
      let m =
        model
          [ page ~fm:"sidebar_position: 1\nsidebar_label: Start Here" ~body:"# The Long Title\n" "a";
            page ~fm:"sidebar_position: 2" ~body:"# Plain Title\n" "b" ]
      in
      List.map (fun e -> e.Wiki_ordering.label) (Wiki_ordering.ordered m)
      = [ "Start Here"; "Plain Title" ]);
  check "N5 a filename-derived label loses its ordinal; an AUTHORED title keeps its digits"
    (fun () ->
      (* "2026 Roadmap" is a subject, not a position — stripping it would
         silently rename the page *)
      let m = model [ page "03-the-gate"; page ~body:"# 2026 Roadmap\n" "roadmap" ] in
      let label s =
        List.find (fun e -> e.Wiki_ordering.slug = s) (Wiki_ordering.ordered m)
      in
      (label "03-the-gate").Wiki_ordering.label = "the-gate"
      && (label "roadmap").Wiki_ordering.label = "2026 Roadmap");
  check "N5b an AUTHORED title that merely LOOKS numbered keeps every byte" (fun () ->
      (* mutant M8 (strip the ordinal from every title) survived N5,
         because number_prefix does not treat a SPACE as a separator, so
         "2026 Roadmap" was never at risk. This is the case that was:
         the title is prefix-shaped and is not the filename. *)
      let m = model [ page ~body:"# 03-the-plan\n" "gate" ] in
      (List.hd (Wiki_ordering.ordered m)).Wiki_ordering.label = "03-the-plan");
  check "N6 keywords are carried onto the entry" (fun () ->
      let m = model [ page ~fm:"keywords: [parity, oracle]" "a" ] in
      (List.hd (Wiki_ordering.ordered m)).Wiki_ordering.keywords = [ "parity"; "oracle" ]);
  check "N7 pagination is MUTUALLY INVERSE over the whole sequence" (fun () ->
      let m = model [ page "c"; page "a"; page "b"; page ~fm:"sidebar_position: 1" "z" ] in
      let es = Wiki_ordering.ordered m in
      List.for_all
        (fun e ->
          match Wiki_ordering.next es e.Wiki_ordering.slug with
          | None -> true
          | Some nxt -> Wiki_ordering.prev es nxt = Some e.Wiki_ordering.slug)
        es
      && List.for_all
           (fun e ->
             match Wiki_ordering.prev es e.Wiki_ordering.slug with
             | None -> true
             | Some p -> Wiki_ordering.next es p = Some e.Wiki_ordering.slug)
           es);
  check "N8 the sequence is ACYCLIC: the ends are None, it never wraps" (fun () ->
      let m = model [ page "a"; page "b"; page "c" ] in
      let es = Wiki_ordering.ordered m in
      Wiki_ordering.prev es "a" = None
      && Wiki_ordering.next es "c" = None
      && Wiki_ordering.next es "a" = Some "b")

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 walking next from the head reaches the tail in exactly n-1 steps" (fun () ->
      let n = 200 in
      let m = model (List.init n (fun i -> page (Printf.sprintf "p%03d" i))) in
      let es = Wiki_ordering.ordered m in
      let rec walk k s =
        match Wiki_ordering.next es s with None -> (k, s) | Some t -> walk (k + 1) t
      in
      let steps, last = walk 0 (List.hd es).Wiki_ordering.slug in
      List.length es = n && steps = n - 1
      && last = (List.nth es (n - 1)).Wiki_ordering.slug);
  check "X2 EVERY position equal still yields a total order (ties break by slug)" (fun () ->
      let m =
        model (List.map (fun s -> page ~fm:"sidebar_position: 7" s) [ "c"; "a"; "b" ])
      in
      slugs m = [ "a"; "b"; "c" ]);
  check "X3 an extreme position does not overflow the comparison" (fun () ->
      let m =
        model
          [ page ~fm:(Printf.sprintf "sidebar_position: %d" max_int) "last";
            page ~fm:(Printf.sprintf "sidebar_position: %d" min_int) "first" ]
      in
      slugs m = [ "first"; "last" ])

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 a corpus declaring NO order still has a total one (by slug)" (fun () ->
      let m = model [ page "gamma"; page "alpha"; page "beta" ] in
      slugs m = [ "alpha"; "beta"; "gamma" ]);
  check "S2 an UNKNOWN slug paginates to None at both ends, never raises" (fun () ->
      let es = Wiki_ordering.ordered (model [ page "a"; page "b" ]) in
      Wiki_ordering.next es "ghost" = None && Wiki_ordering.prev es "ghost" = None);
  check "S3 a ONE-PAGE corpus has no next and no prev" (fun () ->
      let es = Wiki_ordering.ordered (model [ page "only" ]) in
      Wiki_ordering.next es "only" = None && Wiki_ordering.prev es "only" = None);
  check "S4 an EMPTY corpus is an empty sequence, not a failure" (fun () ->
      let es = Wiki_ordering.ordered (model []) in
      es = [] && Wiki_ordering.next es "a" = None);
  check "S5 positionless pages sort AFTER positioned ones, never interleaved" (fun () ->
      let m =
        model
          [ page "aaa"; page ~fm:"sidebar_position: 5" "zzz"; page "bbb";
            page ~fm:"sidebar_position: 9" "yyy" ]
      in
      slugs m = [ "zzz"; "yyy"; "aaa"; "bbb" ])

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 a MALFORMED sidebar_position clamps to None — it never raises" (fun () ->
      let m = model [ page ~fm:"sidebar_position: banana" "a"; page ~fm:"sidebar_position: 1" "b" ] in
      slugs m = [ "b"; "a" ]
      && (List.find (fun e -> e.Wiki_ordering.slug = "a") (Wiki_ordering.ordered m))
           .Wiki_ordering.position
         = None);
  check "A2 a DUPLICATE position among siblings is REPORTED, not resolved silently"
    (fun () ->
      let m =
        model [ page ~fm:"sidebar_position: 2" "a"; page ~fm:"sidebar_position: 2" "b" ]
      in
      match Wiki_ordering.position_conflicts m with
      | [ line ] ->
          (* the report must name both claimants, or the author cannot act *)
          let has s =
            let n = String.length line and k = String.length s in
            let rec go i = i + k <= n && (String.sub line i k = s || go (i + 1)) in
            go 0
          in
          has "a" && has "b" && has "2"
      | _ -> false);
  check "A3 the SAME number in DIFFERENT groups is not a conflict" (fun () ->
      let m =
        model
          [ page ~group:"one" ~fm:"sidebar_position: 2" "a";
            page ~group:"two" ~fm:"sidebar_position: 2" "b" ]
      in
      Wiki_ordering.position_conflicts m = []);
  check "A4 a duplicate position still yields a DETERMINISTIC order" (fun () ->
      let mk order = model (List.map (fun s -> page ~fm:"sidebar_position: 2" s) order) in
      slugs (mk [ "a"; "b"; "c" ]) = slugs (mk [ "c"; "b"; "a" ]));
  check "A5 number_prefix is TOTAL over pathological input" (fun () ->
      List.for_all
        (fun s -> match Wiki_ordering.number_prefix s with _ -> true)
        [ ""; "-"; "0"; "03"; "03-"; "-03"; "999999999999999999999999-x";
          String.make 4000 '7'; "0x-a"; "3.a"; "3_a"; "3=a" ]);
  check "A6 digits with NO separator are not a position" (fun () ->
      Wiki_ordering.number_prefix "03" = (None, "03")
      && Wiki_ordering.number_prefix "03intro" = (None, "03intro")
      && Wiki_ordering.number_prefix "03-x" = (Some 3, "x"));
  check "A7 an unrepresentable numeric prefix is not a position (no raise)" (fun () ->
      Wiki_ordering.number_prefix "999999999999999999999999-x"
      = (None, "999999999999999999999999-x"));
  check "A8 the order does not depend on INPUT order — a shuffle is the same sequence"
    (fun () ->
      let mk order =
        model
          (List.map
             (fun (s, p) ->
               match p with
               | Some n -> page ~fm:(Printf.sprintf "sidebar_position: %d" n) s
               | None -> page s)
             order)
      in
      let a = [ ("q", Some 2); ("r", None); ("s", Some 1); ("t", None) ] in
      slugs (mk a) = slugs (mk (List.rev a)))

(* --------------------------- HW.1.3.10 keywords ARE additive to search *)

let () =
  check "K1 a declared keyword makes a page reachable by a word it never says" (fun () ->
      let m = model [ page ~fm:"keywords: [zoology]" ~body:"# Gate\n\nNothing about animals.\n" "a" ] in
      let idx = Wiki_search.build m in
      List.mem_assoc "a" (Wiki_search.search idx "zoology"));
  check "K2 keywords are ADDITIVE: the body's own words still find the page" (fun () ->
      (* the failure this forbids: declaring keywords REPLACING the body
         index, which would hide a page from a search for its own text *)
      let body = "# Gate\n\nThe parity claim holds.\n" in
      let bare = model [ page ~body "a" ] in
      let keyed = model [ page ~fm:"keywords: [zoology]" ~body "a" ] in
      let hit m q = List.assoc_opt "a" (Wiki_search.search (Wiki_search.build m) q) in
      hit bare "parity" <> None && hit keyed "parity" <> None
      && hit keyed "zoology" <> None);
  check "K3 a keyword BOOSTS a word the body already has — never lowers it" (fun () ->
      let body = "# Gate\n\nThe parity claim holds.\n" in
      let bare = model [ page ~body "a" ] in
      let keyed = model [ page ~fm:"keywords: [parity]" ~body "a" ] in
      let score m = List.assoc "a" (Wiki_search.search (Wiki_search.build m) "parity") in
      score keyed > score bare);
  check "K4 no keywords declared leaves the index BYTE-IDENTICAL (no phantom terms)"
    (fun () ->
      let body = "# Gate\n\nThe parity claim holds.\n" in
      Wiki_search.digest (Wiki_search.build (model [ page ~body "a" ]))
      = Wiki_search.digest (Wiki_search.build (model [ page ~fm:"status: published" ~body "a" ])))

(* ----------------------------- HW.6.4.4 pagination as a SURFACE *)

let () =
  check "P1 the rendered nav AGREES with the relation, both sides" (fun () ->
      let es = Wiki_ordering.ordered (model [ page "a"; page "b"; page "c" ]) in
      Wiki_ordering.nav_targets es "b" = [ "a"; "c" ]
      && contains (Wiki_ordering.nav_html es "b") "href=\"a.html\""
      && contains (Wiki_ordering.nav_html es "b") "href=\"c.html\"");
  check "P2 at an END the nav emits NOTHING for that side, not a dead control" (fun () ->
      (* a greyed-out next on the last page tells a reader there is more
         and there is not; an absent one tells them they have finished *)
      let es = Wiki_ordering.ordered (model [ page "a"; page "b"; page "c" ]) in
      Wiki_ordering.nav_targets es "a" = [ "b" ]
      && Wiki_ordering.nav_targets es "c" = [ "b" ]
      && (not (contains (Wiki_ordering.nav_html es "a") "pager-prev"))
      && not (contains (Wiki_ordering.nav_html es "c") "pager-next"));
  check "P3 a ONE-PAGE sequence renders no pager at all" (fun () ->
      let es = Wiki_ordering.ordered (model [ page "only" ]) in
      Wiki_ordering.nav_html es "only" = "" && Wiki_ordering.nav_targets es "only" = []);
  check "P4 every nav target is a page IN the sequence — no link to nowhere" (fun () ->
      let es = Wiki_ordering.ordered (model [ page "a"; page "b"; page "c"; page "d" ]) in
      let slugs = List.map (fun e -> e.Wiki_ordering.slug) es in
      List.for_all
        (fun e ->
          List.for_all
            (fun t -> List.mem t slugs)
            (Wiki_ordering.nav_targets es e.Wiki_ordering.slug))
        es);
  check "P5 the nav LABEL is the sidebar label — you land on the name you clicked" (fun () ->
      let m =
        model
          [ page ~fm:"sidebar_position: 1" "a";
            page ~fm:"sidebar_position: 2\nsidebar_label: Second Thing" ~body:"# Long Title\n" "b" ]
      in
      let es = Wiki_ordering.ordered m in
      contains (Wiki_ordering.nav_html es "a") ">Second Thing<");
  check "P6 markup in a title is ESCAPED, never emitted as markup" (fun () ->
      let m = model [ page ~fm:"sidebar_position: 1" "a";
                      page ~fm:"sidebar_position: 2\nsidebar_label: <script>x</script>" "b" ] in
      let h = Wiki_ordering.nav_html (Wiki_ordering.ordered m) "a" in
      contains h "&lt;script&gt;" && not (contains h "<script>"));
  check "P7 an UNKNOWN slug renders nothing rather than raising" (fun () ->
      let es = Wiki_ordering.ordered (model [ page "a"; page "b" ]) in
      Wiki_ordering.nav_html es "ghost" = "" && Wiki_ordering.nav_targets es "ghost" = [])

let () =
  Printf.printf "wiki_ordering: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_ordering" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_ordering ]);
  exit (Wiki_suite_telemetry.exit_code self)
