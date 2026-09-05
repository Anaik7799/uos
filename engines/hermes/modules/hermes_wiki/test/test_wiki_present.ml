(* The PRESENTATION family — HW.7.1.2, .7.1.3, .7.2.2, .7.2.3, .7.3.1,
   .7.3.2, .7.3.4, .7.8.1 — across the full functional envelope:

     N*  nominal      the eight laws, each stated as an assertion
     X*  exhaustion   a very long block, a very long line, many marks,
                      thousands of captions
     S*  stuck        an empty fence, no language, zero figures
     A*  anomaly      markup inside code, an out-of-range mark, an unknown
                      language, a duplicate caption, a quote-breaking lang

   The headline law of the family: NO SCRIPT. Every row here is an anchor
   plus CSS, so everything this module emits must render correctly with
   scripting off — and the printer is the reader that proves it. *)

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

let count hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i acc =
    if i + nn > nh then acc
    else go (i + 1) (if String.sub hay i nn = needle then acc + 1 else acc)
  in
  if nn = 0 then 0 else go 0 0

let ok_css = match Wiki_present.stylesheet with Ok s -> s | Error _ -> ""

let block_text body =
  (* the text a reader receives from [code_block]: the newline after the
     wrapper's open tag, every line, then the two closing newlines *)
  "\n" ^ String.concat "" (List.map (fun l -> l ^ "\n") body) ^ "\n\n"

(* ------------------------------------------------------------ nominal *)

let () =
  (* HW.7.1.2 — dark mode *)
  check "N1 DARK MODE'S LAW: light and dark bind exactly the SAME token names"
    (fun () ->
      Wiki_present.token_keys Wiki_present.Light = Wiki_present.token_keys Wiki_present.Dark
      && Wiki_present.token_keys Wiki_present.Light <> []);
  check "N2 and every one of them is REBOUND — a token that never changes is not a theme token"
    (fun () ->
      let l = Wiki_present.palette Wiki_present.Light in
      let d = Wiki_present.palette Wiki_present.Dark in
      List.for_all
        (fun (k, v) -> match List.assoc_opt k d with Some dv -> dv <> v | None -> false)
        l);
  check "N3 dark mode reaches the reader with NO SCRIPT: a prefers-color-scheme query"
    (fun () ->
      match Wiki_present.theme_css with
      | Error _ -> false
      | Ok css ->
          contains css "@media (prefers-color-scheme: dark)"
          (* the :not guard: an explicit light choice must still win *)
          && contains css ":root:not([data-theme=\"light\"])"
          && not (Wiki_present.has_script css));
  check "N4 the media block declares the SAME variables as the token set, no more, no fewer"
    (fun () ->
      let expected =
        List.sort compare
          (List.map Wiki_present.variable_of_key (Wiki_present.token_keys Wiki_present.Dark))
      in
      Wiki_present.declared_variables Wiki_present.dark_media_css = expected);
  check "N5 the dark values in the media block are the DARK palette, annotated with their token"
    (fun () ->
      List.for_all
        (fun (k, v) ->
          contains Wiki_present.dark_media_css
            (Printf.sprintf "%s: %s; /* dark/%s */" (Wiki_present.variable_of_key k) v k))
        (Wiki_present.palette Wiki_present.Dark));
  check "N6 the sheet COMPOSES with HW.7.1.1: Wiki_theme's :root and data-theme blocks are there"
    (fun () ->
      match Wiki_present.theme_css with
      | Error _ -> false
      | Ok css ->
          contains css Wiki_theme.banner
          && contains css ":root {"
          && contains css ":root[data-theme=\"dark\"]"
          && Wiki_present.declared_variables css
             = List.sort compare
                 (List.map Wiki_present.variable_of_key
                    (Wiki_present.token_keys Wiki_present.Light)));
  check "N6b A REFERENCE IS NOT A DECLARATION: the full sheet var()s a token it does not redeclare"
    (fun () ->
      (* the anchor, code and figure rules all read tokens through
         `var(--…)`. If a reader of the stylesheet counted those as
         declarations, the token set would silently grow — and the whole
         same-names law would be measured against the wrong set. *)
      contains ok_css "var(--color-accent)"
      && contains ok_css "var(--color-border)"
      && Wiki_present.declared_variables ok_css
         = List.sort compare
             (List.map Wiki_present.variable_of_key (Wiki_present.token_keys Wiki_present.Light))
      (* and the discrimination is real, not an accident of this sheet
         happening to reference only tokens it declares: a var() of a
         name nobody declares must NOT enter the set. *)
      && Wiki_present.declared_variables "a { color: var(--ghost); }\n:root { --real: #fff; }"
         = [ "--real" ]);

  (* HW.7.1.3 — print stylesheet *)
  check "N7 PRINT IS CONTENT-COMPLETE: no violation of the three set facts" (fun () ->
      Wiki_present.print_violations () = []);
  check "N8 exactly the declared chrome is hidden — nothing else disappears on paper"
    (fun () ->
      List.sort compare (Wiki_present.hidden_selectors Wiki_present.print_css)
      = List.sort compare Wiki_present.print_chrome);
  check "N9 chrome and content are DISJOINT — otherwise 'hidden is only chrome' proves nothing"
    (fun () ->
      List.for_all (fun s -> not (List.mem s Wiki_present.print_content)) Wiki_present.print_chrome);
  check "N10 paper has no hyperlinks, so every URL is DISCLOSED" (fun () ->
      contains Wiki_present.print_css "attr(href)"
      && contains Wiki_present.print_css "a[href]::after");

  (* HW.7.2.2 / HW.7.2.3 — the two anchors *)
  check "N11 EVERY ANCHOR RESOLVES: the assembled page has no dangling fragment" (fun () ->
      let page = Wiki_present.document_chrome ~content:"<p>body</p>" in
      Wiki_present.dangling_anchors page = []
      && List.mem Wiki_present.top_id (Wiki_present.anchor_ids page)
      && List.mem Wiki_present.main_id (Wiki_present.anchor_ids page)
      && List.mem "top" (Wiki_present.internal_hrefs page)
      && List.mem "main" (Wiki_present.internal_hrefs page));
  check "N12 SKIP-TO-CONTENT IS FIRST: no anchor precedes it, or it skips nothing" (fun () ->
      let page = Wiki_present.document_chrome ~content:"<p><a href=\"#main\">x</a></p>" in
      match (Wiki_present.internal_hrefs page, Wiki_present.anchor_ids page) with
      | first_href :: _, _ ->
          first_href = Wiki_present.main_id
          && contains page "class=\"skip-link\""
          (* and it is the first '<a' in source order *)
          && (let rec idx i =
                if i + 2 > String.length page then None
                else if String.sub page i 2 = "<a" then Some i
                else idx (i + 1)
              in
              match idx 0 with
              | Some i -> contains (String.sub page i 40) "skip-link"
              | None -> false)
      | [], _ -> false);
  check "N13 the skip link is OFF-SCREEN, never display:none — display:none leaves the focus order"
    (fun () ->
      contains Wiki_present.skip_link_css ".skip-link:focus"
      && contains Wiki_present.skip_link_css "position: absolute"
      && not (contains Wiki_present.skip_link_css "display: none")
      && not (contains Wiki_present.skip_link_css "display:none"));
  check "N14 BACK-TO-TOP is an anchor and CSS only — no script anywhere in what we emit"
    (fun () ->
      contains Wiki_present.back_to_top_html "href=\"#top\""
      && (not (Wiki_present.has_script Wiki_present.back_to_top_html))
      && (not (Wiki_present.has_script Wiki_present.skip_link_html))
      && (not (Wiki_present.has_script ok_css))
      && not (Wiki_present.has_script (Wiki_present.document_chrome ~content:"<p>hi</p>")));

  (* HW.7.3.1 — syntax highlighting *)
  check "N15 SERVER-SIDE: a known language emits token spans from a closed class set" (fun () ->
      let r = Wiki_present.code_block ~lang:"ocaml" [ "let x = \"hi\" (* note *) 42" ] in
      contains r.Wiki_present.html "<span class=\"tok-kw\">let</span>"
      && contains r.Wiki_present.html "<span class=\"tok-str\">&quot;hi&quot;</span>"
      && contains r.Wiki_present.html "<span class=\"tok-com\">(* note *)</span>"
      && contains r.Wiki_present.html "<span class=\"tok-num\">42</span>"
      && contains r.Wiki_present.html "class=\"language-ocaml\"");
  check "N16 THE ROUND-TRIP LAW: strip the markup and the source line comes back, byte for byte"
    (fun () ->
      let lines =
        [ "let f x = x + 1";
          "let s = \"a < b & c > d\"";
          "(* a comment with \"quotes\" *)";
          "  indented\tand\ttabbed";
          "";
          "let x' = 3.14 in x'" ]
      in
      List.for_all
        (fun l -> Wiki_present.strip_markup (Wiki_present.highlight_line (Some Wiki_present.Ocaml) l) = l)
        lines
      && List.for_all
           (fun l -> Wiki_present.strip_markup (Wiki_present.highlight_line (Some Wiki_present.Shell) l) = l)
           [ "echo \"hi\" # done"; "for f in *.ml; do echo $f; done"; "x='a<b'" ]
      && List.for_all
           (fun l -> Wiki_present.strip_markup (Wiki_present.highlight_line (Some Wiki_present.Json) l) = l)
           [ "{\"a\": true, \"b\": [1, 2, null]}" ]);
  check "N17 the whole block round-trips too: highlighting adds markup and changes NOTHING else"
    (fun () ->
      let body = [ "let a = 1"; "let b = \"<x>\""; "(* end *)" ] in
      let r = Wiki_present.code_block ~lang:"ocaml" body in
      Wiki_present.strip_markup r.Wiki_present.html = block_text body);
  check "N18 the class attribute is drawn from a CLOSED SET — author text cannot reach it"
    (fun () ->
      List.for_all
        (fun l ->
          let r = Wiki_present.code_block ?lang:l [ "x" ] in
          List.exists
            (fun c -> contains r.Wiki_present.html (Printf.sprintf "class=\"%s\"" c))
            Wiki_present.code_classes)
        [ None; Some "ocaml"; Some "json"; Some "sh"; Some "brainfuck"; Some "OCaml" ]);

  (* HW.7.3.2 — code language label *)
  check "N19 THE LABEL IS A PURE FUNCTION OF THE LANG: the body cannot change it" (fun () ->
      let label_in html =
        let n = String.length html in
        let pat = "data-lang=\"" in
        let m = String.length pat in
        let rec go i =
          if i + m > n then None
          else if String.sub html i m = pat then
            let s = i + m in
            let rec close j = if j >= n || html.[j] = '"' then j else close (j + 1) in
            Some (String.sub html s (close s - s))
          else go (i + 1)
        in
        go 0
      in
      let a = Wiki_present.code_block ~lang:"ocaml" [ "let a = 1" ] in
      let b = Wiki_present.code_block ~lang:"ocaml" [ "totally"; "different"; "body" ] in
      label_in a.Wiki_present.html = label_in b.Wiki_present.html
      && label_in a.Wiki_present.html = Some "OCaml"
      && Wiki_present.label_of_lang (Some "ml") = Some "OCaml"
      && Wiki_present.label_of_lang (Some "sh") = Some "Shell"
      && Wiki_present.label_of_lang (Some "json") = Some "JSON");
  check "N20 the label is drawn by CSS from data-lang, so it never joins the copied text"
    (fun () -> contains Wiki_present.code_css ".wiki-code[data-lang]::after"
               && contains Wiki_present.code_css "content: attr(data-lang)");

  (* HW.7.3.4 — line highlighting *)
  check "N21 a mark WITHIN RANGE marks exactly its line, and reports nothing" (fun () ->
      let r = Wiki_present.code_block ~lang:"ocaml" ~highlight:[ 2 ] [ "one"; "two"; "three" ] in
      r.Wiki_present.diagnostics = []
      && count r.Wiki_present.html "<mark class=\"wiki-hl\">" = 1
      && contains r.Wiki_present.html "<mark class=\"wiki-hl\">two</mark>");
  check "N22 the renderer and the checker are the SAME RULE — they cannot drift" (fun () ->
      List.for_all
        (fun (body, hl) ->
          let r = Wiki_present.code_block ~highlight:hl body in
          r.Wiki_present.diagnostics = Wiki_present.check_highlight ~line_count:(List.length body) hl)
        [ ([ "a"; "b" ], [ 1 ]); ([ "a"; "b" ], [ 9 ]); ([], [ 1 ]); ([ "a" ], [ 0; 1; 2 ]) ]);

  (* HW.7.8.1 — numbered figures and tables *)
  check "N23 NUMBERS ARE DERIVED FROM POSITION, per kind: Fig,Tab,Fig -> 1,1,2" (fun () ->
      let ns =
        Wiki_present.number_captions
          [ (Wiki_present.Figure, "a"); (Wiki_present.Table, "b"); (Wiki_present.Figure, "c") ]
      in
      List.map (fun n -> (n.Wiki_present.kind, n.Wiki_present.number, n.Wiki_present.id)) ns
      = [ (Wiki_present.Figure, 1, "figure-1");
          (Wiki_present.Table, 1, "table-1");
          (Wiki_present.Figure, 2, "figure-2") ]);
  check "N24 INSERTING a figure RENUMBERS the ones after it — nothing is authored" (fun () ->
      let before = Wiki_present.number_captions [ (Wiki_present.Figure, "x"); (Wiki_present.Figure, "y") ] in
      let after =
        Wiki_present.number_captions
          [ (Wiki_present.Figure, "new"); (Wiki_present.Figure, "x"); (Wiki_present.Figure, "y") ]
      in
      List.map (fun n -> n.Wiki_present.number) before = [ 1; 2 ]
      && List.map (fun n -> (n.Wiki_present.caption, n.Wiki_present.number)) after
         = [ ("new", 1); ("x", 2); ("y", 3) ]);
  check "N25 a cross-reference RESOLVES against the figure it cites — same anchor law as the two links"
    (fun () ->
      match Wiki_present.number_captions [ (Wiki_present.Figure, "The gate"); (Wiki_present.Table, "Rows") ] with
      | [ f; t ] ->
          let page =
            Wiki_present.document_chrome
              ~content:
                (Wiki_present.figure_html ~content:"<img alt=\"\">" f
                ^ Wiki_present.figure_html ~content:"<table></table>" t
                ^ "<p>see " ^ Wiki_present.caption_ref_html f ^ " and "
                ^ Wiki_present.caption_ref_html t ^ "</p>")
          in
          Wiki_present.dangling_anchors page = []
          && contains page "Figure 1"
          && contains page "Table 1"
          && contains page "<figcaption>"
          && not (Wiki_present.has_script page)
      | _ -> false)

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 a 2000-line block renders every line, in order, and still round-trips" (fun () ->
      let body = List.init 2000 (fun i -> Printf.sprintf "let v%d = %d" i i) in
      let r = Wiki_present.code_block ~lang:"ocaml" body in
      count r.Wiki_present.html "<span class=\"tok-kw\">let</span>" = 2000
      && Wiki_present.strip_markup r.Wiki_present.html = block_text body);
  check "X2 EVERY line highlighted: 2000 marks, and not one diagnostic" (fun () ->
      let body = List.init 2000 (fun i -> string_of_int i) in
      let r = Wiki_present.code_block ~highlight:(List.init 2000 (fun i -> i + 1)) body in
      r.Wiki_present.diagnostics = []
      && count r.Wiki_present.html "<mark class=\"wiki-hl\">" = 2000);
  check "X3 a 100k-character single line survives tokenizing and round-trips" (fun () ->
      let line = String.concat " " (List.init 30000 (fun i -> if i mod 3 = 0 then "let" else "x<y")) in
      let out = Wiki_present.highlight_line (Some Wiki_present.Ocaml) line in
      String.length line > 90000 && Wiki_present.strip_markup out = line);
  check "X4 5000 captions number 1..n per kind, with no collision between the namespaces"
    (fun () ->
      let items =
        List.init 5000 (fun i ->
            ((if i mod 2 = 0 then Wiki_present.Figure else Wiki_present.Table), string_of_int i))
      in
      let ns = Wiki_present.number_captions items in
      let ids = List.map (fun n -> n.Wiki_present.id) ns in
      List.length ns = 5000
      && List.length (List.sort_uniq compare ids) = 5000
      && List.length (List.filter (fun n -> n.Wiki_present.kind = Wiki_present.Figure) ns) = 2500
      && List.nth ns 4998 = { Wiki_present.kind = Wiki_present.Figure; number = 2500;
                              caption = "4998"; id = "figure-2500" })

(* ------------------------------------------------------- stuck states *)

let () =
  check "S1 an EMPTY fence renders an empty block — no crash, no invented content" (fun () ->
      let r = Wiki_present.code_block ~lang:"ocaml" [] in
      r.Wiki_present.diagnostics = []
      && contains r.Wiki_present.html "<pre><code class=\"language-ocaml\"></code></pre>"
      && Wiki_present.strip_markup r.Wiki_present.html = block_text []);
  check "S2 NO LANGUAGE: the neutral class, and NO data-lang at all (absent is not empty)"
    (fun () ->
      let r = Wiki_present.code_block [ "plain <text>" ] in
      contains r.Wiki_present.html "class=\"language-plaintext\""
      && (not (contains r.Wiki_present.html "data-lang"))
      && contains r.Wiki_present.html "plain &lt;text&gt;"
      && (not (contains r.Wiki_present.html "<span"))
      && Wiki_present.label_of_lang None = None);
  check "S3 ZERO figures: an empty document numbers nothing and says so" (fun () ->
      Wiki_present.number_captions [] = []);
  check "S4 an empty LINE inside a block is preserved, not collapsed" (fun () ->
      let body = [ "a"; ""; "b" ] in
      let r = Wiki_present.code_block ~lang:"ocaml" body in
      Wiki_present.strip_markup r.Wiki_present.html = block_text body);
  check "S5 no marks requested: no <mark> is emitted anywhere" (fun () ->
      let r = Wiki_present.code_block ~lang:"ocaml" [ "a"; "b" ] in
      count r.Wiki_present.html "<mark" = 0 && r.Wiki_present.diagnostics = []);
  check "S6 an EMPTY language string is an absent label, not an empty one" (fun () ->
      Wiki_present.label_of_lang (Some "") = None
      && Wiki_present.label_of_lang (Some "   ") = None
      && not (contains (Wiki_present.code_block ~lang:"" [ "x" ]).Wiki_present.html "data-lang"))

(* ----------------------------------------------------------- anomalies *)

let () =
  check "A1 MARKUP INSIDE CODE is escaped — an injection and a byte-difference at once" (fun () ->
      let body = [ "<script>alert(\"x\")</script>"; "a & b < c" ] in
      let r = Wiki_present.code_block ~lang:"ocaml" body in
      (not (contains r.Wiki_present.html "<script"))
      && contains r.Wiki_present.html "&lt;script&gt;"
      && contains r.Wiki_present.html "a &amp; b &lt; c"
      && (not (Wiki_present.has_script r.Wiki_present.html))
      && Wiki_present.strip_markup r.Wiki_present.html = block_text body);
  check "A2 AN UNKNOWN LANGUAGE falls back: verbatim escaped text, neutral class, no guess"
    (fun () ->
      let body = [ "fn main() { let x = \"hi\"; }" ] in
      let r = Wiki_present.code_block ~lang:"rust" body in
      contains r.Wiki_present.html "class=\"language-plaintext\""
      && (not (contains r.Wiki_present.html "<span"))
      (* the author's own token still survives, as data *)
      && contains r.Wiki_present.html "data-lang=\"RUST\""
      && Wiki_present.strip_markup r.Wiki_present.html = block_text body
      && Wiki_present.language_of_lang (Some "rust") = None);
  check "A3 AN OUT-OF-RANGE MARK IS A NAMED DIAGNOSTIC AND MARKS NOTHING — never clamped"
    (fun () ->
      let r = Wiki_present.code_block ~lang:"ocaml" ~highlight:[ 99 ] [ "one"; "two"; "three" ] in
      r.Wiki_present.diagnostics
      = [ Wiki_present.Highlight_out_of_range { requested = 99; line_count = 3 } ]
      && count r.Wiki_present.html "<mark" = 0
      && contains (Wiki_present.describe (List.hd r.Wiki_present.diagnostics)) "NOT clamped"
      (* R4/R5: it names a level and an origin, and the origin is never Implementation *)
      && Wiki_present.diagnostic_level (List.hd r.Wiki_present.diagnostics) = "L2"
      && Wiki_present.diagnostic_origin (List.hd r.Wiki_present.diagnostics) = "Specification");
  check "A4 a mixed request marks the valid line and reports ONLY the invalid one" (fun () ->
      let r = Wiki_present.code_block ~highlight:[ 2; 99 ] [ "one"; "two"; "three" ] in
      count r.Wiki_present.html "<mark class=\"wiki-hl\">" = 1
      && contains r.Wiki_present.html "<mark class=\"wiki-hl\">two</mark>"
      && r.Wiki_present.diagnostics
         = [ Wiki_present.Highlight_out_of_range { requested = 99; line_count = 3 } ]);
  check "A5 a NON-POSITIVE mark names no line and says so" (fun () ->
      let r = Wiki_present.code_block ~highlight:[ 0; -3 ] [ "one" ] in
      r.Wiki_present.diagnostics
      = [ Wiki_present.Highlight_not_positive { requested = 0 };
          Wiki_present.Highlight_not_positive { requested = -3 } ]
      && count r.Wiki_present.html "<mark" = 0);
  check "A6 DUPLICATE captions still get DISTINCT numbers — the caption is not the number"
    (fun () ->
      let ns =
        Wiki_present.number_captions
          [ (Wiki_present.Figure, "same"); (Wiki_present.Figure, "same"); (Wiki_present.Figure, "same") ]
      in
      List.map (fun n -> n.Wiki_present.number) ns = [ 1; 2; 3 ]
      && List.length (List.sort_uniq compare (List.map (fun n -> n.Wiki_present.id) ns)) = 3);
  check "A7 a caption carrying markup is ESCAPED into the figcaption" (fun () ->
      match Wiki_present.number_captions [ (Wiki_present.Figure, "<b>bold</b> & \"quoted\"") ] with
      | [ n ] ->
          let h = Wiki_present.figure_html ~content:"<img alt=\"\">" n in
          contains h "&lt;b&gt;bold&lt;/b&gt; &amp; &quot;quoted&quot;"
          && (not (contains h "<b>bold"))
          && not (Wiki_present.has_script h)
      | _ -> false);
  check "A8 a lang that tries to BREAK OUT of the attribute is escaped, and the class is unchanged"
    (fun () ->
      let evil = "ml\" onload=\"x()" in
      let r = Wiki_present.code_block ~lang:evil [ "x" ] in
      (* the class comes from a closed set, so the token never reaches it *)
      contains r.Wiki_present.html "class=\"language-plaintext\""
      && (not (contains r.Wiki_present.html "onload=\"x()\""))
      && contains r.Wiki_present.html "&quot;"
      && Wiki_present.language_of_lang (Some evil) = None);
  check "A9 an UNTERMINATED string or comment stays PLAIN — no cross-line state, no guess"
    (fun () ->
      let l1 = "let s = \"unterminated" and l2 = "(* unterminated comment" in
      let h1 = Wiki_present.highlight_line (Some Wiki_present.Ocaml) l1 in
      let h2 = Wiki_present.highlight_line (Some Wiki_present.Ocaml) l2 in
      (not (contains h1 "tok-str"))
      && (not (contains h2 "tok-com"))
      && Wiki_present.strip_markup h1 = l1
      && Wiki_present.strip_markup h2 = l2);
  check "A10 the DANGLING-ANCHOR detector actually detects — a law nothing can fail is no law"
    (fun () ->
      Wiki_present.dangling_anchors "<a href=\"#ghost\">x</a><span id=\"real\"></span>" = [ "ghost" ]
      && Wiki_present.dangling_anchors "<a href=\"#real\">x</a><span id=\"real\"></span>" = []);
  check "A11 the SCRIPT detector actually detects, and does not cry wolf over prose" (fun () ->
      Wiki_present.has_script "<body onload=\"boom()\">"
      && Wiki_present.has_script "<script>x</script>"
      && Wiki_present.has_script "<a href=\"javascript:x\">y</a>"
      && (not (Wiki_present.has_script "<p>one=1 and only=2</p>"))
      && not (Wiki_present.has_script "<p>a &lt; b</p>"));
  check "A12 the ESCAPER is injective: unescape . escape = id on adversarial text" (fun () ->
      List.for_all
        (fun s -> Wiki_present.unescape (Wiki_present.escape s) = s)
        [ "&lt;"; "&amp;lt;"; "<>&\""; ""; "plain"; "&&&"; "\"&quot;\"" ]);
  check "A13 hidden_selectors is scoped to @media print — the dark query's braces do not leak"
    (fun () ->
      let css = Wiki_present.dark_media_css ^ Wiki_present.print_css in
      List.sort compare (Wiki_present.hidden_selectors css)
      = List.sort compare Wiki_present.print_chrome
      && Wiki_present.hidden_selectors "no media here { display: none; }" = []
      && Wiki_present.hidden_selectors "@media print { .a, .b { display:none } }" = [ ".a"; ".b" ]);
  check "A14 a print sheet that hid CONTENT would be REPORTED — the checker can fail" (fun () ->
      Wiki_present.hidden_selectors "@media print { .wiki-main { display: none; } }"
      = [ ".wiki-main" ]
      && List.mem ".wiki-main" Wiki_present.print_content)

let () =
  Printf.printf "wiki_present: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_present" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_present ]);
  exit (Wiki_suite_telemetry.exit_code self)
