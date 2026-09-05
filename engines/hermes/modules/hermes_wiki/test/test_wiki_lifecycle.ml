(* The lifecycle / governance rows, across the full functional envelope:

     N*  nominal      the law on its intended input
     X*  exhaustion   a large corpus, many URLs, many placeholders
     S*  stuck        no date, no links, no placeholders, no body
     A*  anomaly      a malformed date, a slug collision, a URL in a
                      fence, a value outside the vocabulary

   The headline law across all six rows: THE SYSTEM NEVER INVENTS THE
   FACT IT LACKS. An absent date is "unknown", an unchecked URL is
   UNCHECKED, an unfilled placeholder is an error, a contested slug is
   reported. Each of those has a cheaper wrong answer that looks
   healthier, and every one of these tests exists to make the cheaper
   answer fail. *)

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

let any_contains l needle = List.exists (fun s -> contains s needle) l

(* ============================================ HW.8.1.5 last_update *)

let () =
  check "N1 last_update: GIT WINS over an authored frontmatter date" (fun () ->
      let u = Wiki_lifecycle.last_update ~git:(Some "2026-08-09") ~frontmatter:"2020-01-01" in
      u.Wiki_lifecycle.stamp = Wiki_lifecycle.Known "2026-08-09"
      && u.Wiki_lifecycle.origin = Wiki_lifecycle.From_git);
  check "N2 last_update: frontmatter is a DISCLOSED fallback, never mistaken for git"
    (fun () ->
      let u = Wiki_lifecycle.last_update ~git:None ~frontmatter:"2026-08-09" in
      u.Wiki_lifecycle.stamp = Wiki_lifecycle.Known "2026-08-09"
      && u.Wiki_lifecycle.origin = Wiki_lifecycle.From_frontmatter);
  check "N3 parse_date accepts the ISO shape and only the ISO shape" (fun () ->
      Wiki_lifecycle.parse_date "2026-08-09" = Wiki_lifecycle.Known "2026-08-09"
      && Wiki_lifecycle.parse_date "  2026-08-09  " = Wiki_lifecycle.Known "2026-08-09"
      && Wiki_lifecycle.parse_date "09/08/2026" <> Wiki_lifecycle.Known "09/08/2026");
  check "N4 the report DISCLOSES the origin of every date it prints" (fun () ->
      let r =
        Wiki_lifecycle.last_update_report
          [ ("a", Some "2026-01-02", ""); ("b", None, "2025-12-31"); ("c", None, "") ]
      in
      List.length r = 3
      && any_contains r "a: 2026-01-02 [git]"
      && any_contains r "b: 2025-12-31 [frontmatter]"
      && any_contains r "c: unknown [absent]")

let () =
  check "S1 R16 KILLER: no git, no frontmatter -> UNKNOWN, never a date" (fun () ->
      let u = Wiki_lifecycle.last_update ~git:None ~frontmatter:"" in
      u.Wiki_lifecycle.stamp = Wiki_lifecycle.Unknown
      && u.Wiki_lifecycle.origin = Wiki_lifecycle.Absent
      && Wiki_lifecycle.render_stamp u.Wiki_lifecycle.stamp = "unknown"
      (* the surface must contain no digit at all: a fabricated stamp
         would have to print one somewhere *)
      && not (String.exists (fun c -> c >= '0' && c <= '9')
                (Wiki_lifecycle.render_stamp u.Wiki_lifecycle.stamp)));
  check "S2 an EMPTY git answer is silence, and the authored date is consulted" (fun () ->
      let u = Wiki_lifecycle.last_update ~git:(Some "") ~frontmatter:"2026-02-03" in
      u.Wiki_lifecycle.origin = Wiki_lifecycle.From_frontmatter);
  check "S3 an empty corpus reports nothing rather than raising" (fun () ->
      Wiki_lifecycle.last_update_report [] = [])

let () =
  check "A1 a MALFORMED date is preserved VERBATIM, never normalised away" (fun () ->
      match Wiki_lifecycle.parse_date "2026-13-45" with
      | Wiki_lifecycle.Malformed s -> s = "2026-13-45"
      | Wiki_lifecycle.Known _ | Wiki_lifecycle.Unknown -> false);
  check "A2 a malformed GIT date does NOT fall back to the authored one" (fun () ->
      let u = Wiki_lifecycle.last_update ~git:(Some "yesterday") ~frontmatter:"2026-08-09" in
      u.Wiki_lifecycle.origin = Wiki_lifecycle.From_git
      && u.Wiki_lifecycle.stamp = Wiki_lifecycle.Malformed "yesterday");
  check "A3 render distinguishes malformed from unknown from known" (fun () ->
      Wiki_lifecycle.render_stamp (Wiki_lifecycle.Malformed "x") <> "unknown"
      && contains (Wiki_lifecycle.render_stamp (Wiki_lifecycle.Malformed "x")) "malformed"
      && Wiki_lifecycle.render_stamp (Wiki_lifecycle.Known "2026-01-01") = "2026-01-01");
  check "A4 parse_date is TOTAL over pathological input" (fun () ->
      List.for_all
        (fun s -> match Wiki_lifecycle.parse_date s with _ -> true)
        [ ""; "-"; "----------"; "2026-0a-09"; "26-8-9"; String.make 5000 '-'; "\n\t" ])

(* ============================================ HW.8.2.5 external links *)

let () =
  check "N5 external_urls finds bare, markdown and autolink forms" (fun () ->
      let body =
        "bare https://one.example\n\
         a [label](https://two.example/path) link\n\
         an <https://three.example> autolink\n\
         and plain http://plain.example too\n"
      in
      (* BOTH schemes: an http:// link is as checkable as an https:// one,
         and a checker that only sees one of them silently under-reports *)
      Wiki_lifecycle.external_urls body
      = [ "http://plain.example"; "https://one.example"; "https://three.example";
          "https://two.example/path" ]);
  check "N6 verdicts follow the injected evidence, both ways" (fun () ->
      let v =
        Wiki_lifecycle.classify
          ~evidence:[ ("https://a", Wiki_lifecycle.Reachable);
                      ("https://b", Wiki_lifecycle.Dead "404") ]
          [ "https://a"; "https://b" ]
      in
      v = [ Wiki_lifecycle.Live "https://a"; Wiki_lifecycle.Broken ("https://b", "404") ]);
  check "N7 the summary always prints all three counts" (fun () ->
      let s =
        Wiki_lifecycle.summarise
          [ Wiki_lifecycle.Live "a"; Wiki_lifecycle.Broken ("b", "r");
            Wiki_lifecycle.Unchecked "c"; Wiki_lifecycle.Unchecked "d" ]
      in
      s.Wiki_lifecycle.live = 1 && s.Wiki_lifecycle.broken = 1
      && s.Wiki_lifecycle.unchecked = 2)

let () =
  check "S4 THE KILLER: a URL with NO evidence is UNCHECKED, never Live" (fun () ->
      let v = Wiki_lifecycle.classify ~evidence:[] [ "https://never.looked" ] in
      v = [ Wiki_lifecycle.Unchecked "https://never.looked" ]
      && (Wiki_lifecycle.summarise v).Wiki_lifecycle.live = 0
      && (Wiki_lifecycle.summarise v).Wiki_lifecycle.broken = 0
      && (Wiki_lifecycle.summarise v).Wiki_lifecycle.unchecked = 1);
  check "S5 partial evidence leaves the REST unchecked, it does not spread" (fun () ->
      let v =
        Wiki_lifecycle.classify
          ~evidence:[ ("https://a", Wiki_lifecycle.Reachable) ]
          [ "https://a"; "https://b"; "https://c" ]
      in
      let s = Wiki_lifecycle.summarise v in
      s.Wiki_lifecycle.live = 1 && s.Wiki_lifecycle.unchecked = 2 && s.Wiki_lifecycle.broken = 0);
  check "S6 a document with no external links yields no verdicts at all" (fun () ->
      Wiki_lifecycle.external_urls "plain prose, a [[wikilink]] and nothing else\n" = []
      && Wiki_lifecycle.external_urls "" = []
      && Wiki_lifecycle.summarise [] = { Wiki_lifecycle.live = 0; broken = 0; unchecked = 0 })

let () =
  check "A5 a URL inside a CODE FENCE is an example, not a link to check" (fun () ->
      (* this exact bug shipped twice here: 10 phantom dead links *)
      Wiki_lifecycle.external_urls "```\nhttps://fenced.example\n```\n" = []);
  check "A6 a URL inside INLINE BACKTICKS is an example too" (fun () ->
      Wiki_lifecycle.external_urls "write `https://inline.example` to link\n" = []);
  check "A7 a fenced URL does not hide a real one on a neighbouring line" (fun () ->
      Wiki_lifecycle.external_urls
        "before https://real.example\n```\nhttps://fenced.example\n```\nafter\n"
      = [ "https://real.example" ]);
  check "A8 trailing sentence punctuation is not part of the host" (fun () ->
      Wiki_lifecycle.external_urls "see https://example.org.\n" = [ "https://example.org" ]);
  check "A9 a string that is not a URL is not extracted" (fun () ->
      Wiki_lifecycle.external_urls "ftp://x mailto:a@b http:/broken https:// tail\n" = []);
  check "A10 evidence for a URL the document does not cite is IGNORED" (fun () ->
      let v =
        Wiki_lifecycle.classify
          ~evidence:[ ("https://stale.cache", Wiki_lifecycle.Dead "410") ]
          [ "https://a" ]
      in
      v = [ Wiki_lifecycle.Unchecked "https://a" ])

let () =
  check "X1 300 distinct URLs extract, dedupe and classify without loss" (fun () ->
      let body =
        String.concat "\n"
          (List.init 300 (fun i -> Printf.sprintf "line %d: https://h%03d.example/p" i i))
      in
      let urls = Wiki_lifecycle.external_urls body in
      List.length urls = 300
      && (let s = Wiki_lifecycle.summarise (Wiki_lifecycle.classify ~evidence:[] urls) in
          s.Wiki_lifecycle.unchecked = 300 && s.Wiki_lifecycle.live = 0));
  check "X2 the same URL cited 200 times is ONE link to check" (fun () ->
      let body = String.concat "\n" (List.init 200 (fun _ -> "see https://one.example here")) in
      Wiki_lifecycle.external_urls body = [ "https://one.example" ])

(* ============================================ HW.8.3.1 page templates *)

let () =
  check "N8 a template DECLARES its placeholders, sorted and deduped" (fun () ->
      let t = Wiki_lifecycle.template ~name:"note" "# {{title}}\n\nby {{author}}, {{title}}\n" in
      t.Wiki_lifecycle.placeholders = [ "author"; "title" ]);
  check "N9 instantiation is a pure text substitution" (fun () ->
      let t = Wiki_lifecycle.template ~name:"note" "# {{title}}\n\nby {{author}}\n" in
      Wiki_lifecycle.instantiate t [ ("title", "Parity"); ("author", "hermes") ]
      = Ok "# Parity\n\nby hermes\n");
  check "N10 instantiation is DETERMINISTIC: same inputs, same bytes" (fun () ->
      let t = Wiki_lifecycle.template ~name:"n" "{{a}}-{{b}}" in
      let f = [ ("a", "1"); ("b", "2") ] in
      Wiki_lifecycle.instantiate t f = Wiki_lifecycle.instantiate t f
      && Wiki_lifecycle.instantiate t f = Ok "1-2")

let () =
  check "S7 a template with NO placeholders returns its body BYTE-IDENTICAL" (fun () ->
      let src = "plain\n\n- a list\n\n```\ncode\n```\n" in
      let t = Wiki_lifecycle.template ~name:"flat" src in
      t.Wiki_lifecycle.placeholders = [] && Wiki_lifecycle.instantiate t [] = Ok src);
  check "S8 an empty template with an empty fill set is the empty page" (fun () ->
      Wiki_lifecycle.instantiate (Wiki_lifecycle.template ~name:"e" "") [] = Ok "")

let () =
  check "A11 an UNFILLED placeholder is a NAMED ERROR, never literal {{x}}" (fun () ->
      let t = Wiki_lifecycle.template ~name:"n" "# {{title}}\n" in
      match Wiki_lifecycle.instantiate t [] with
      | Ok body -> ignore body; false
      | Error errs ->
          errs = [ Wiki_lifecycle.Unfilled "title" ]
          && contains (Wiki_lifecycle.show_fill_error (List.hd errs)) "title");
  check "A12 an UNKNOWN key in the fill set is an error, never silently dropped" (fun () ->
      let t = Wiki_lifecycle.template ~name:"n" "{{a}}" in
      match Wiki_lifecycle.instantiate t [ ("a", "1"); ("typo", "2") ] with
      | Ok _ -> false
      | Error errs -> errs = [ Wiki_lifecycle.Unknown_placeholder "typo" ]);
  check "A13 BOTH faults are collected, not just the first" (fun () ->
      let t = Wiki_lifecycle.template ~name:"n" "{{a}}{{b}}" in
      match Wiki_lifecycle.instantiate t [ ("a", "1"); ("zz", "2") ] with
      | Ok _ -> false
      | Error errs ->
          errs = [ Wiki_lifecycle.Unfilled "b"; Wiki_lifecycle.Unknown_placeholder "zz" ]);
  check "A14 on error NOTHING is rendered — no partially filled page exists" (fun () ->
      let t = Wiki_lifecycle.template ~name:"n" "{{a}} and {{b}}" in
      match Wiki_lifecycle.instantiate t [ ("a", "1") ] with
      | Ok _ -> false
      | Error _ -> true);
  check "A15 a FENCED {{x}} is an example: not declared, not filled, still literal" (fun () ->
      let src = "```\nuse {{example}} here\n```\nreal {{real}}\n" in
      let t = Wiki_lifecycle.template ~name:"doc" src in
      t.Wiki_lifecycle.placeholders = [ "real" ]
      && Wiki_lifecycle.instantiate t [ ("real", "R") ]
         = Ok "```\nuse {{example}} here\n```\nreal R\n");
  check "A16 a BACKTICKED {{x}} is an example too" (fun () ->
      let t = Wiki_lifecycle.template ~name:"doc" "write `{{x}}` for a slot" in
      t.Wiki_lifecycle.placeholders = []
      && Wiki_lifecycle.instantiate t [] = Ok "write `{{x}}` for a slot");
  check "A17 unterminated and empty placeholder syntax is text, never a raise" (fun () ->
      List.for_all
        (fun s ->
          let t = Wiki_lifecycle.template ~name:"t" s in
          t.Wiki_lifecycle.placeholders = [] && Wiki_lifecycle.instantiate t [] = Ok s)
        [ "{{a"; "{{}}"; "{{"; "}}"; "{ {a} }"; "{{ }}" ]);
  check "X3 a template with 200 placeholders fills every one of them" (fun () ->
      let body = String.concat "\n" (List.init 200 (fun i -> Printf.sprintf "p%03d={{k%03d}}" i i)) in
      let t = Wiki_lifecycle.template ~name:"wide" body in
      let fills = List.init 200 (fun i -> (Printf.sprintf "k%03d" i, string_of_int i)) in
      List.length t.Wiki_lifecycle.placeholders = 200
      && (match Wiki_lifecycle.instantiate t fills with
          | Ok out -> (not (contains out "{{")) && contains out "p199=199"
          | Error _ -> false));
  check "X4 dropping ONE fill from 200 fails, and names exactly that one" (fun () ->
      let body = String.concat "\n" (List.init 200 (fun i -> Printf.sprintf "{{k%03d}}" i)) in
      let t = Wiki_lifecycle.template ~name:"wide" body in
      let fills =
        List.filteri (fun i _ -> i <> 42) (List.init 200 (fun i -> (Printf.sprintf "k%03d" i, "v")))
      in
      match Wiki_lifecycle.instantiate t fills with
      | Ok _ -> false
      | Error errs -> errs = [ Wiki_lifecycle.Unfilled "k042" ])

(* ============================================ HW.8.5.3 ontology *)

let mk path body = (path, body)

let onto_model =
  Hermes_wiki.build
    [ mk "docs/hermes/zk/good.md"
        "---\nktype: atomic\nmaturity: evergreen\ndomain: parity\nstatus: published\ntype: claim\n---\n# Good\n\nBody.\n";
      mk "docs/hermes/zk/bad.md"
        "---\nktype: sketchbook\nmaturity: ripe\ndomain: anything-at-all\nstatus: published\ntype: note\n---\n# Bad\n\nBody.\n";
      mk "docs/hermes/zk/bare.md" "# Bare\n\nBody.\n" ]

let () =
  check "N11 the vocabularies are the ones hermes_wiki.mli declares" (fun () ->
      Wiki_lifecycle.vocabulary Wiki_lifecycle.Ktype
      = [ "atomic"; "moc"; "source"; "journal" ]
      && Wiki_lifecycle.vocabulary Wiki_lifecycle.Maturity
         = [ "seed"; "incubating"; "evergreen"; "archived" ]
      && Wiki_lifecycle.vocabulary Wiki_lifecycle.Status
         = [ "draft"; "published"; "flagged_for_review" ]
      && List.mem "decision" (Wiki_lifecycle.vocabulary Wiki_lifecycle.Ntype)
      && List.mem "unlisted" (Wiki_lifecycle.vocabulary Wiki_lifecycle.Visibility));
  check "N12 domain is an OPEN axis: [] means any term, not no term" (fun () ->
      Wiki_lifecycle.is_open Wiki_lifecycle.Domain
      && Wiki_lifecycle.vocabulary Wiki_lifecycle.Domain = []
      && Wiki_lifecycle.classify_value Wiki_lifecycle.Domain "anything"
         = Wiki_lifecycle.Open_term
      && List.for_all
           (fun a -> a = Wiki_lifecycle.Domain || not (Wiki_lifecycle.is_open a))
           Wiki_lifecycle.axes);
  check "N13 the required axes are the PKM schema's ktype/maturity/domain" (fun () ->
      List.filter (fun a -> Wiki_lifecycle.requirement a = Wiki_lifecycle.Required)
        Wiki_lifecycle.axes
      = [ Wiki_lifecycle.Ktype; Wiki_lifecycle.Maturity; Wiki_lifecycle.Domain ]);
  check "N14 every axis reads its own field off meta" (fun () ->
      match Hermes_wiki.page onto_model "good" with
      | None -> false
      | Some p ->
          let m = p.Hermes_wiki.meta in
          Wiki_lifecycle.axis_value m Wiki_lifecycle.Ktype = "atomic"
          && Wiki_lifecycle.axis_value m Wiki_lifecycle.Maturity = "evergreen"
          && Wiki_lifecycle.axis_value m Wiki_lifecycle.Ntype = "claim"
          && List.for_all
               (fun a ->
                 Wiki_lifecycle.classify_value a (Wiki_lifecycle.axis_value m a)
                 <> Wiki_lifecycle.Outside)
               Wiki_lifecycle.axes)

let () =
  check "A18 THE VERDICT: a value outside a closed vocabulary is REPORTED" (fun () ->
      let gaps = Wiki_lifecycle.vocabulary_gaps onto_model in
      any_contains gaps "bad: ktype outside vocabulary: sketchbook"
      && any_contains gaps "bad: maturity outside vocabulary: ripe");
  check "A19 an OPEN axis never produces a gap, however exotic the term" (fun () ->
      not (any_contains (Wiki_lifecycle.vocabulary_gaps onto_model) "domain outside"));
  check "S9 an UNSET value is NOT a vocabulary gap (that is schema_gaps' job)" (fun () ->
      let gaps = Wiki_lifecycle.vocabulary_gaps onto_model in
      Wiki_lifecycle.classify_value Wiki_lifecycle.Ktype "" = Wiki_lifecycle.Unset
      && (not (any_contains gaps "bare:"))
      && not (any_contains gaps "good:"));
  check "S10 an empty corpus has no vocabulary gaps and does not raise" (fun () ->
      Wiki_lifecycle.vocabulary_gaps (Hermes_wiki.build []) = []);
  check "A20 classify_value is total over pathological values" (fun () ->
      List.for_all
        (fun v ->
          List.for_all
            (fun a -> match Wiki_lifecycle.classify_value a v with _ -> true)
            Wiki_lifecycle.axes)
        [ ""; " "; "\n"; String.make 4000 'x'; "ATOMIC"; "atomic " ])

(* ============================================ HW.1.2.6 slug override *)

let claim ?declared path derived = { Wiki_lifecycle.path; declared; derived }

let () =
  check "N15 an EXPLICIT slug WINS over the derived one" (fun () ->
      let r = Wiki_lifecycle.resolve_slug (claim ~declared:"the-gate" "a/b.md" "b") in
      r.Wiki_lifecycle.slug = "the-gate"
      && r.Wiki_lifecycle.source = Wiki_lifecycle.Declared_slug);
  check "N16 with no claim the DERIVED slug stands" (fun () ->
      let r = Wiki_lifecycle.resolve_slug (claim "a/b.md" "b") in
      r.Wiki_lifecycle.slug = "b" && r.Wiki_lifecycle.source = Wiki_lifecycle.Derived_slug);
  check "N17 a declared slug is normalised by the ENGINE's own slugify" (fun () ->
      let r = Wiki_lifecycle.resolve_slug (claim ~declared:"The Gate!" "a/b.md" "b") in
      r.Wiki_lifecycle.slug = Hermes_wiki.slugify "The Gate!"
      && r.Wiki_lifecycle.slug <> "The Gate!");
  check "N18 THE MARK: every claim is countable, including a no-op one" (fun () ->
      let marks =
        Wiki_lifecycle.slug_overrides
          [ claim ~declared:"b" "a/b.md" "b"; claim "a/c.md" "c" ]
      in
      List.length marks = 1 && any_contains marks "a/b.md")

let () =
  check "A21 THE KILLER: two EXPLICIT claims on one slug is a reported COLLISION"
    (fun () ->
      let c =
        Wiki_lifecycle.slug_collisions
          [ claim ~declared:"gate" "a/x.md" "x"; claim ~declared:"gate" "a/y.md" "y" ]
      in
      List.length c = 1
      && any_contains c "explicit slug collision: gate"
      && any_contains c "a/x.md"
      && any_contains c "a/y.md");
  check "A22 an explicit claim colliding with a DERIVED slug is still explicit" (fun () ->
      let c =
        Wiki_lifecycle.slug_collisions
          [ claim ~declared:"gate" "a/x.md" "x"; claim "a/gate.md" "gate" ]
      in
      any_contains c "explicit slug collision: gate");
  check "A23 a derived-vs-derived clash is a DISTINCT, lesser verdict" (fun () ->
      let c = Wiki_lifecycle.slug_collisions [ claim "a/n.md" "n"; claim "b/n.md" "n" ] in
      any_contains c "derived slug collision: n" && not (any_contains c "explicit"));
  check "A24 a MALFORMED claim keeps the derived slug and leaves a mark" (fun () ->
      let c = claim ~declared:"   " "a/b.md" "b" in
      let r = Wiki_lifecycle.resolve_slug c in
      r.Wiki_lifecycle.slug = "b"
      && r.Wiki_lifecycle.source = Wiki_lifecycle.Declared_malformed
      && any_contains (Wiki_lifecycle.slug_overrides [ c ]) "malformed");
  check "A25 a malformed claim collides as DERIVED — no explicit slug is in effect"
    (fun () ->
      let c =
        Wiki_lifecycle.slug_collisions [ claim ~declared:"!!!" "a/n.md" "n"; claim "b/n.md" "n" ]
      in
      any_contains c "derived slug collision: n" && not (any_contains c "explicit"));
  check "S11 no claims, no collisions, no marks — and no raise on []" (fun () ->
      Wiki_lifecycle.slug_collisions [] = []
      && Wiki_lifecycle.slug_overrides [] = []
      && Wiki_lifecycle.resolve_slugs [] = []
      && Wiki_lifecycle.slug_collisions [ claim "a/x.md" "x" ] = []);
  check "X5 400 documents: INJECTIVE resolution reports exactly the one clash" (fun () ->
      let cs =
        List.init 400 (fun i -> claim (Printf.sprintf "d/%03d.md" i) (Printf.sprintf "s%03d" i))
      in
      let cs = claim ~declared:"s007" "d/rogue.md" "rogue" :: cs in
      let c = Wiki_lifecycle.slug_collisions cs in
      List.length c = 1 && any_contains c "explicit slug collision: s007")

(* ============================================ HW.1.3.9 description *)

let () =
  check "N19 a DECLARED description wins over the body" (fun () ->
      let d = Wiki_lifecycle.describe ~declared:"The parity gate." ~body:"Something else.\n" in
      d.Wiki_lifecycle.text = "The parity gate."
      && d.Wiki_lifecycle.origin = Wiki_lifecycle.Declared_desc
      && not d.Wiki_lifecycle.truncated);
  check "N20 absent, it is DERIVED from the first prose paragraph" (fun () ->
      let d =
        Wiki_lifecycle.describe ~declared:""
          ~body:"# Heading\n\nFirst para line one\nline two\n\nSecond para.\n"
      in
      d.Wiki_lifecycle.text = "First para line one line two"
      && d.Wiki_lifecycle.origin = Wiki_lifecycle.Derived_desc);
  check "N21 derivation skips a leading code fence — code is not a summary" (fun () ->
      let d = Wiki_lifecycle.describe ~declared:"" ~body:"```\nlet x = 1\n```\n\nReal prose.\n" in
      d.Wiki_lifecycle.text = "Real prose."
      && d.Wiki_lifecycle.origin = Wiki_lifecycle.Derived_desc);
  check "N22 FEEDS RANKING, ADDITIVELY: body terms survive verbatim" (fun () ->
      let d = Wiki_lifecycle.describe ~declared:"Parity Gate" ~body:"" in
      let body_terms = [ "frozen"; "reference"; "zzz" ] in
      let r = Wiki_lifecycle.ranking_terms d ~body_terms in
      List.for_all (fun t -> List.mem t r) body_terms
      && List.mem "parity" r && List.mem "gate" r);
  check "N23 description_terms lowercases, splits and dedupes" (fun () ->
      let d = Wiki_lifecycle.describe ~declared:"Gate, gate; GATE parity!" ~body:"" in
      Wiki_lifecycle.description_terms d = [ "gate"; "parity" ])

let () =
  check "S12 nothing declared and nothing to derive -> \"\" with No_desc" (fun () ->
      let d = Wiki_lifecycle.describe ~declared:"" ~body:"" in
      d.Wiki_lifecycle.text = ""
      && d.Wiki_lifecycle.origin = Wiki_lifecycle.No_desc
      && not d.Wiki_lifecycle.truncated);
  check "S13 a body of only headings and fences yields NO description" (fun () ->
      let d = Wiki_lifecycle.describe ~declared:"" ~body:"# A\n\n## B\n\n```\nx\n```\n" in
      d.Wiki_lifecycle.origin = Wiki_lifecycle.No_desc && d.Wiki_lifecycle.text = "");
  check "S14 a page with no description cannot outrank its own body words" (fun () ->
      let d = Wiki_lifecycle.describe ~declared:"" ~body:"" in
      Wiki_lifecycle.ranking_terms d ~body_terms:[ "a"; "b" ] = [ "a"; "b" ])

let () =
  check "A26 an over-long description is CUT and the cut is DISCLOSED" (fun () ->
      let long = String.make 500 'x' in
      let d = Wiki_lifecycle.describe ~declared:long ~body:"" in
      d.Wiki_lifecycle.truncated
      && String.length d.Wiki_lifecycle.text = Wiki_lifecycle.max_description
      (* no ellipsis: the flag is the disclosure, the bytes stay the bytes *)
      && not (contains d.Wiki_lifecycle.text "."));
  check "A27 a whitespace-only declaration is ABSENT, not an empty description" (fun () ->
      let d = Wiki_lifecycle.describe ~declared:"   \t " ~body:"Prose here.\n" in
      d.Wiki_lifecycle.origin = Wiki_lifecycle.Derived_desc
      && d.Wiki_lifecycle.text = "Prose here.");
  check "A28 describe is TOTAL over pathological bodies" (fun () ->
      List.for_all
        (fun b -> match Wiki_lifecycle.describe ~declared:"" ~body:b with _ -> true)
        [ ""; "\n\n\n"; "```"; "```\n"; "#"; String.make 20000 'y'; "\t\r\n" ]);
  check "X6 a 2000-line body derives from the FIRST paragraph only" (fun () ->
      let body =
        "first para.\n\n" ^ String.concat "\n" (List.init 2000 (fun i -> Printf.sprintf "l%d" i))
      in
      let d = Wiki_lifecycle.describe ~declared:"" ~body in
      d.Wiki_lifecycle.text = "first para." && not d.Wiki_lifecycle.truncated)

let () =
  Printf.printf "wiki_lifecycle: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_lifecycle" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_lifecycle ]);
  exit (Wiki_suite_telemetry.exit_code self)
