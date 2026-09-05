(* HW.9.2.1 literalinclude · HW.2.6.6 code-block options · HW.2.6.7
   default highlight language — the fence-meta cluster that HW.2.0.2's
   info string made possible.

   The headline law is HW.9.2.1's: THE DENOTATION IS THE FILE. A rendered
   include equals a slice of the source, byte for byte, so a quoted
   snippet cannot drift from the code it quotes. Its dual matters as
   much: an unmatched marker is a DIAGNOSTIC, never an empty block —
   silence is the one failure mode this feature exists to prevent. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false ->
      incr failed;
      print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

(* ------------------------------------------------------- the grammar *)

let () =
  check "G1 a full directive parses: path and every selector" (fun () ->
      match
        Wiki_include.parse
          "literalinclude src/a.ml lines=3-7 start-after=BEGIN end-before=END dedent lang=ocaml emphasize=2,4"
      with
      | Some d ->
          d.Wiki_include.path = "src/a.ml"
          && d.Wiki_include.lines = Some (3, 7)
          && d.Wiki_include.start_after = Some "BEGIN"
          && d.Wiki_include.end_before = Some "END"
          && d.Wiki_include.dedent
          && d.Wiki_include.lang = Some "ocaml"
          && d.Wiki_include.emphasize = [ 2; 4 ]
      | None -> false);
  check "G2 a bare path directive parses with every selector absent" (fun () ->
      match Wiki_include.parse "literalinclude src/a.ml" with
      | Some d ->
          d.Wiki_include.path = "src/a.ml"
          && d.Wiki_include.lines = None
          && d.Wiki_include.start_after = None
          && (not d.Wiki_include.dedent)
          && d.Wiki_include.emphasize = []
      | None -> false);
  check "G3 a NON-include fence is None (the token is exact)" (fun () ->
      Wiki_include.parse "ocaml" = None
      && Wiki_include.parse "literalincludes src/a.ml" = None
      && Wiki_include.parse "" = None);
  check "G4 literalinclude with NO path is None, never a directive on \"\"" (fun () ->
      Wiki_include.parse "literalinclude" = None);
  check "G5 a malformed selector is IGNORED, never raised (total over author input)"
    (fun () ->
      match Wiki_include.parse "literalinclude a.ml lines=banana emphasize=x,-3" with
      | Some d -> d.Wiki_include.lines = None && d.Wiki_include.emphasize = []
      | None -> false);
  check "G6 emphasize_of_info reads ANY fence's meta, sorted and deduped" (fun () ->
      Wiki_include.emphasize_of_info "ocaml emphasize=4,2,4" = [ 2; 4 ]
      && Wiki_include.emphasize_of_info "ocaml" = []);
  check "G7 lang: explicit dominates; else inferred from the extension" (fun () ->
      let d p l =
        { Wiki_include.path = p; lines = None; start_after = None; end_before = None;
          dedent = false; lang = l; emphasize = []; bad = [] }
      in
      Wiki_include.lang_of (d "a.ml" (Some "text")) = Some "text"
      && Wiki_include.lang_of (d "a.ml" None) = Some "ocaml"
      && Wiki_include.lang_of (d "a.mli" None) = Some "ocaml"
      && Wiki_include.lang_of (d "a.md" None) = Some "markdown"
      && Wiki_include.lang_of (d "Makefile" None) = None)

(* ------------------------------------------------------- the slicing *)

let source = "zero\nlet one = 1\nBEGIN\n  keep me\n  and me\nEND\nlast\n"
let read_ok = function "src/a.ml" -> Some source | _ -> None

let dir ?lines ?start_after ?end_before ?(dedent = false) ?lang ?(emphasize = []) path =
  { Wiki_include.path; lines; start_after; end_before; dedent; lang; emphasize; bad = [] }

let () =
  check "S1 lines=a-b is 1-based and INCLUSIVE at both ends" (fun () ->
      Wiki_include.slice ~read:read_ok (dir ~lines:(2, 3) "src/a.ml")
      = Ok [ "let one = 1"; "BEGIN" ]);
  check "S2 markers select BETWEEN them, excluding the marker lines" (fun () ->
      Wiki_include.slice ~read:read_ok
        (dir ~start_after:"BEGIN" ~end_before:"END" "src/a.ml")
      = Ok [ "  keep me"; "  and me" ]);
  check "S3 a marker matches by SUBSTRING (the stated limit)" (fun () ->
      Wiki_include.slice ~read:read_ok (dir ~start_after:"EGI" ~end_before:"END" "src/a.ml")
      = Ok [ "  keep me"; "  and me" ]);
  check "S4 dedent removes the COMMON indent, blank lines ignored" (fun () ->
      Wiki_include.slice ~read:read_ok
        (dir ~start_after:"BEGIN" ~end_before:"END" ~dedent:true "src/a.ml")
      = Ok [ "keep me"; "and me" ]);
  check "S5 THE DENOTATION IS THE FILE: no selector yields the file verbatim" (fun () ->
      Wiki_include.slice ~read:read_ok (dir "src/a.ml")
      = Ok [ "zero"; "let one = 1"; "BEGIN"; "  keep me"; "  and me"; "END"; "last" ]);
  check "S6 an UNMATCHED marker is a named Error, never an empty Ok" (fun () ->
      match
        Wiki_include.slice ~read:read_ok (dir ~start_after:"NOPE" "src/a.ml")
      with
      | Error r -> contains r "NOPE"
      | Ok _ -> false);
  check "S7 a missing FILE is a named Error (fail closed)" (fun () ->
      match Wiki_include.slice ~read:read_ok (dir "src/gone.ml") with
      | Error r -> contains r "gone.ml"
      | Ok _ -> false);
  check "S8 an out-of-range line window is an Error, never a silent truncation"
    (fun () ->
      match Wiki_include.slice ~read:read_ok (dir ~lines:(3, 99) "src/a.ml") with
      | Error r -> contains r "99"
      | Ok _ -> false);
  check "S9 the empty reader (no IO injected) fails CLOSED for every include" (fun () ->
      match Wiki_include.slice ~read:(fun _ -> None) (dir "src/a.ml") with
      | Error _ -> true
      | Ok _ -> false);
  check "S10 dedent_lines is common-prefix, not per-line, and keeps blanks" (fun () ->
      Wiki_include.dedent_lines [ "  a"; ""; "    b" ] = [ "a"; ""; "  b" ])

(* --------------------------------------------- the rendering surface *)

let render ?read_source ?default_lang src =
  Hermes_wiki.render_markdown ?read_source ?default_lang ~resolve:(fun _ -> None) src

let both ?read_source ?default_lang src =
  ( render ?read_source ?default_lang src,
    Hermes_wiki.render_line_machine ?read_source ?default_lang ~resolve:(fun _ -> None) src )

let () =
  check "R1 an include renders the SLICE, byte-exact, in both renderers" (fun () ->
      let a, b =
        both ~read_source:read_ok
          "```literalinclude src/a.ml start-after=BEGIN end-before=END\n```\n"
      in
      a = b && contains a "  keep me\n  and me\n" && not (contains a "BEGIN"));
  check "R2 the language is inferred from the path (.ml -> ocaml)" (fun () ->
      let a, _ = both ~read_source:read_ok "```literalinclude src/a.ml lines=1-1\n```\n" in
      contains a "<pre><code class=\"language-ocaml\">zero");
  check "R3 an AUTHORED BODY IS IGNORED — the file is the only truth" (fun () ->
      let a, b =
        both ~read_source:read_ok
          "```literalinclude src/a.ml lines=1-1\nSTALE COPY\n```\n"
      in
      a = b && (not (contains a "STALE COPY")) && contains a "zero");
  check "R4 a FAILED include renders VISIBLY, never as an empty block" (fun () ->
      let a, b = both ~read_source:read_ok "```literalinclude src/gone.ml\n```\n" in
      a = b && contains a "literalinclude" && contains a "gone.ml"
      && not (contains a "<pre><code class=\"language-ocaml\"></code></pre>"));
  check "R5 with NO reader every include fails closed, identically in both" (fun () ->
      let a, b = both "```literalinclude src/a.ml\n```\n" in
      a = b && contains a "unresolved");
  check "R6 HW.2.6.6 emphasize wraps exactly the named lines" (fun () ->
      let a, b = both "```ocaml emphasize=2\nfirst\nsecond\nthird\n```\n" in
      a = b
      && contains a "<mark>second</mark>"
      && (not (contains a "<mark>first"))
      && not (contains a "<mark>third"));
  check "R7 HW.2.6.6 an OUT-OF-RANGE emphasis marks nothing (the diagnostic carries it)"
    (fun () ->
      let a, b = both "```ocaml emphasize=9\nfirst\n```\n" in
      a = b && not (contains a "<mark>"));
  check "R8 HW.2.6.7 the document default supplies a missing fence language" (fun () ->
      let a, b = both ~default_lang:"ocaml" "```\nlet x = 1\n```\n" in
      a = b && contains a "<pre><code class=\"language-ocaml\">");
  check "R9 HW.2.6.7 a fence's OWN language dominates the default" (fun () ->
      let a, _ = both ~default_lang:"ocaml" "```json\n{}\n```\n" in
      contains a "class=\"language-json\"" && not (contains a "language-ocaml"));
  check "R10 IDENTITY: no default, no options — the bytes are unchanged" (fun () ->
      let a, b = both "```\nplain\n```\n" in
      a = b && contains a "<pre><code>plain\n</code></pre>")

(* --------------------------------------------------- the model layer *)

let () =
  let page body = [ ("docs/x/inc.md", "# Inc\n\n" ^ body) ] in
  check "M1 an unresolved include is a NAMED model gap (page + path)" (fun () ->
      match
        Hermes_wiki.include_gaps
          (Hermes_wiki.build ~read_source:read_ok (page "```literalinclude src/gone.ml\n```\n"))
      with
      | [ line ] -> contains line "inc" && contains line "gone.ml"
      | _ -> false);
  check "M2 a RESOLVING include is silent, and its bytes are the file's" (fun () ->
      let m =
        Hermes_wiki.build ~read_source:read_ok
          (page "```literalinclude src/a.ml lines=2-2\n```\n")
      in
      Hermes_wiki.include_gaps m = []
      &&
      match Hermes_wiki.page m "inc" with
      | Some p -> contains p.Hermes_wiki.html "let one = 1"
      | None -> false);
  check "M3 HW.2.6.6 an out-of-range emphasis is a named model gap" (fun () ->
      match
        Hermes_wiki.fence_option_gaps (Hermes_wiki.build (page "```ocaml emphasize=9\nx\n```\n"))
      with
      | [ line ] -> contains line "inc" && contains line "9"
      | _ -> false);
  check "M4 HW.2.6.6 an IN-range emphasis is silent" (fun () ->
      Hermes_wiki.fence_option_gaps (Hermes_wiki.build (page "```ocaml emphasize=1\nx\n```\n"))
      = []);
  check "M5 HW.2.6.7 the frontmatter default reaches the built page" (fun () ->
      let m =
        Hermes_wiki.build
          [ ("docs/x/hl.md", "---\nhighlight: ocaml\n---\n# HL\n\n```\nlet x = 1\n```\n") ]
      in
      match Hermes_wiki.page m "hl" with
      | Some p -> contains p.Hermes_wiki.html "class=\"language-ocaml\""
      | None -> false);
  check "M6 build WITHOUT a reader leaves includes unresolved and SAYS SO" (fun () ->
      match Hermes_wiki.include_gaps (Hermes_wiki.build (page "```literalinclude src/a.ml\n```\n")) with
      | [ line ] -> contains line "a.ml"
      | _ -> false)

(* ------------------------------------------------- adversarial review
   Four defects an adversarial pass found in the first cut. Each law
   below is the one that was missing when the defect shipped. *)

let () =
  check "X1 the SHIPPED reader is total: a directory path returns None, never raises"
    (fun () ->
      (* open_in_bin SUCCEEDS on a directory on Linux; in_channel_length
         then raises. The original `match ... with | exception _` caught
         only the scrutinee, so this killed every tool that builds. *)
      Hermes_wiki.read_source_file "modules/hermes_wiki/src" = None
      && Hermes_wiki.read_source_file "no/such/file" = None
      && Hermes_wiki.read_source_file "modules/hermes_wiki/src/engine/wiki_include.mli" <> None);
  check "X2 BYTE-EQUALITY survives an UNCLOSED include fence at EOF" (fun () ->
      (* the line machine's EOF closer lacked the include guard, so it
         appended a stray </code></pre> the AST path never emits *)
      let a, b = both ~read_source:read_ok "```literalinclude src/a.ml\n" in
      a = b);
  check "X2b byte-equality also survives an unclosed PLAIN fence at EOF" (fun () ->
      let a, b = both "```ocaml\nlet x = 1\n" in
      a = b);
  check "X3 an EMPTY slice is an Error — a successful include can never be a blank block"
    (fun () ->
      (* markers on adjacent lines select nothing: Ok [] rendered as
         <pre><code class="language-ocaml"></code></pre>, the exact bytes
         R4 forbids, with NO gap reported *)
      (match
         Wiki_include.slice ~read:read_ok
           (dir ~start_after:"BEGIN" ~end_before:"keep" "src/a.ml")
       with
      | Error r -> contains r "empty"
      | Ok _ -> false)
      &&
      let m =
        Hermes_wiki.build ~read_source:read_ok
          [ ( "docs/x/e.md",
              "# E\n\n```literalinclude src/a.ml start-after=BEGIN end-before=keep\n```\n" ) ]
      in
      (match Hermes_wiki.page m "e" with
      | Some p ->
          not (contains p.Hermes_wiki.html "<pre><code class=\"language-ocaml\"></code></pre>")
      | None -> false)
      && List.length (Hermes_wiki.include_gaps m) = 1);
  check "X4 a language token is VALIDATED before it reaches the class attribute" (fun () ->
      (* lang= came straight from author text into class="language-%s" *)
      let a, b =
        both ~read_source:read_ok
          "```literalinclude src/a.ml lines=1-1 lang=x\"><script>alert(1)</script>\n```\n"
      in
      a = b
      && (not (contains a "<script>"))
      && not (contains a "language-x\""));
  check "X4b an invalid document default degrades to the info-less rendering" (fun () ->
      let a, _ = both ~default_lang:"x\"><img src=y>" "```\nplain\n```\n" in
      (not (contains a "<img")) && contains a "<pre><code>plain")

(* ------------------------------------ the six defects held over
   Each was found by the adversarial pass and recorded in the handover
   as the queue head, ahead of any new feature. *)

let () =
  check "Y1 a MALFORMED selector is an Error, never a silent whole-file inline"
    (fun () ->
      (* lines=0-5 / 5-0 / overflow / 3-7-9 all parsed to None, which
         slice read as "no window" — so a typo dumped the entire file *)
      List.for_all
        (fun v ->
          match Wiki_include.parse ("literalinclude src/a.ml lines=" ^ v) with
          | Some d -> (
              match Wiki_include.slice ~read:read_ok d with
              | Error r -> contains r "lines"
              | Ok _ -> false)
          | None -> false)
        [ "0-5"; "5-0"; "banana"; "3-7-9"; "9999999999999999999" ]);
  check "Y1b a WELL-FORMED selector still slices (the guard is not a blanket refusal)"
    (fun () ->
      Wiki_include.slice ~read:read_ok
        (match Wiki_include.parse "literalinclude src/a.ml lines=1-2" with
        | Some d -> d
        | None -> failwith "parse")
      = Ok [ "zero"; "let one = 1" ]);
  check "Y2 a NEAR-MISS directive is a named gap, not a stale code block" (fun () ->
      (* ```literalinclude with no path fell through to the language
         branch and rendered the authored body — the very hand-copy the
         feature abolishes, with no signal *)
      Wiki_include.attempted "literalinclude" = true
      && Wiki_include.attempted "ocaml" = false
      &&
      let m =
        Hermes_wiki.build ~read_source:read_ok
          [ ("docs/x/n.md", "# N\n\n```literalinclude\nSTALE COPY\n```\n") ]
      in
      List.length (Hermes_wiki.include_gaps m) = 1
      &&
      match Hermes_wiki.page m "n" with
      | Some p ->
          (not (contains p.Hermes_wiki.html "language-literalinclude"))
          && not (contains p.Hermes_wiki.html "STALE COPY")
      | None -> false);
  check "Y3 allow_example_links exempts the three NEW gauges too" (fun () ->
      let page body =
        [ ("docs/x/ex.md", "---\nallow_example_links: true\n---\n# Ex\n\n" ^ body) ]
      in
      Hermes_wiki.include_gaps
        (Hermes_wiki.build ~read_source:read_ok (page "```literalinclude nope.ml\n```\n"))
      = []
      && Hermes_wiki.fence_option_gaps
           (Hermes_wiki.build (page "```ocaml emphasize=9\nx\n```\n"))
         = []
      && Hermes_wiki.doctest_drift
           (Hermes_wiki.build (page "```doctest\n> a\n<p>wrong</p>\n```\n"))
         = []);
  check "Y4 a doctest survives a BLANK SEPARATOR between input and expected" (fun () ->
      Hermes_wiki.doctest_drift
        (Hermes_wiki.build
           [ ("docs/x/d.md", "# D\n\n```doctest\n> plain text\n\n<p>plain text</p>\n```\n") ])
      = []);
  check "Y4b interleaved input/output PAIRS are compared pairwise, not collapsed"
    (fun () ->
      Hermes_wiki.doctest_drift
        (Hermes_wiki.build
           [ ( "docs/x/d2.md",
               "# D2\n\n```doctest\n> one\n<p>one</p>\n> two\n<p>two</p>\n```\n" ) ])
      = []);
  check "Y4c a real mismatch is STILL caught (the fix did not defang the check)"
    (fun () ->
      List.length
        (Hermes_wiki.doctest_drift
           (Hermes_wiki.build
              [ ("docs/x/d3.md", "# D3\n\n```doctest\n> one\n\n<p>WRONG</p>\n```\n") ]))
      = 1);
  check "Y5 the reader is consulted ONCE per path: render and audit cannot disagree"
    (fun () ->
      let calls = ref 0 in
      let counting p =
        incr calls;
        read_ok p
      in
      let _ =
        Hermes_wiki.build ~read_source:counting
          [ ("docs/x/c.md", "# C\n\n```literalinclude src/a.ml lines=1-1\n```\n") ]
      in
      !calls = 1);
  check "Y6 ONE reason for the no-reader condition, in both entry points" (fun () ->
      let ast =
        Wiki_ast.render ~inline:(fun s -> s) ~anchor:(fun s -> s) ~escape:(fun s -> s)
          (Wiki_ast.parse "```literalinclude src/a.ml\n```\n")
      in
      let engine = render "```literalinclude src/a.ml\n```\n" in
      contains ast "no source reader injected" && contains engine "no source reader injected")

let () =
  Printf.printf "wiki_include: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_include" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_include ]);
  exit (Wiki_suite_telemetry.exit_code self)
