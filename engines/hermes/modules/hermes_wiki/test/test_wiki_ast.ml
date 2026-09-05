(* HW.2.0.1 admission. The AST path replaces a streaming line machine that
   produced every page of this wiki, so the bar is OBSERVATIONAL
   EQUIVALENCE to that oracle — not "looks right".

   Two legs:
     1. the whole real corpus renders byte-identically through both paths;
     2. the preserved quirks are pinned individually, so changing any one
        is a deliberate act with a failing law rather than an accident.

   Plus the observation that justifies the change at all: the carrier now
   admits a block inside a block. *)

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

let resolve _ = None
let oracle s = Hermes_wiki.render_line_machine ~resolve s
let final s = Hermes_wiki.render_markdown ~resolve s
let agree s = oracle s = final s

(* ------------------------------------------- 1. the whole real corpus *)

let corpus =
  Hermes_wiki.read_tracked "modules/hermes_wiki/pages" @ Hermes_wiki.read_tracked "docs/hermes"

let () =
  check "the corpus is non-trivial (the differential must have something to compare)"
    (fun () -> List.length corpus > 150)

let () =
  check "EVERY corpus document renders identically through oracle and AST" (fun () ->
      let disagreeing =
        List.filter (fun (_, raw) -> not (agree raw)) corpus |> List.map fst
      in
      match disagreeing with
      | [] -> true
      | paths ->
          Printf.printf "  %d document(s) disagree:\n" (List.length paths);
          List.iteri (fun i p -> if i < 8 then print_endline ("    " ^ p)) paths;
          false)

(* --------------------------------------------- 2. the preserved quirks *)

let () = check "quirk: each `> ` line is its OWN blockquote, never merged" (fun () ->
    let h = final "> one\n> two\n" in
    let count needle =
      let n = String.length needle and t = String.length h in
      let rec go i acc =
        if i + n > t then acc else go (i + 1) (if String.sub h i n = needle then acc + 1 else acc)
      in
      go 0 0
    in
    count "<blockquote>" = 2 && agree "> one\n> two\n")

let () = check "quirk: a heading needs a space after the hashes" (fun () ->
    (not (String.length (final "#nospace") > 0 && String.sub (final "#nospace") 0 2 = "<h"))
    && agree "#nospace")

let () = check "quirk: heading level is capped at 4, so ##### is a paragraph" (fun () ->
    let h = final "##### five\n" in
    (not (String.length h >= 3 && String.sub h 0 3 = "<h5")) && agree "##### five\n")

let () = check "quirk: a table separator row is dropped, not rendered" (fun () ->
    let h = final "| a |\n|---|\n| b |\n" in
    (not
       (let n = String.length "---" and t = String.length h in
        let rec go i = i + n <= t && (String.sub h i n = "---" || go (i + 1)) in
        go 0))
    && agree "| a |\n|---|\n| b |\n")

let () = check "quirk: a paragraph joins its lines with a single space" (fun () ->
    let h = final "one\ntwo\n" in
    (let n = String.length "one two" and t = String.length h in
     let rec go i = i + n <= t && (String.sub h i n = "one two" || go (i + 1)) in
     go 0)
    && agree "one\ntwo\n")

let () = check "quirk: an unterminated fence is closed at end of input" (fun () ->
    let h = final "```\nunclosed\n" in
    (let n = String.length "</code></pre>" and t = String.length h in
     let rec go i = i + n <= t && (String.sub h i n = "</code></pre>" || go (i + 1)) in
     go 0)
    && agree "```\nunclosed\n")

let () = check "quirk: a bullet run and a numbered run do not merge" (fun () ->
    agree "- bullet\n1. number\n")

let () = check "quirk: an ordered list following a bullet list LOSES its start" (fun () ->
    (* the oracle computes the start attribute before closing the previous
       list, so `start` is dropped here but kept when the ordered list
       stands alone. Both directions pinned. *)
    let after_bullets = final "- a\n4. four\n" and alone = final "4. four\n" in
    let has h needle =
      let n = String.length needle and t = String.length h in
      let rec go i = i + n <= t && (String.sub h i n = needle || go (i + 1)) in
      go 0
    in
    (not (has after_bullets "start=")) && has alone "start=\"4\""
    && agree "- a\n4. four\n" && agree "4. four\n")

(* ---------------------------------------- constructs, through both paths *)

let () =
  let cases =
    [ ("empty", "");
      ("single paragraph", "hello");
      ("heading levels", "# one\n## two\n### three\n#### four\n");
      ("repeated headings (slugger state)", "# Section\n\n# Section\n\n# Section\n");
      ("bulleted list", "- a\n- b\n* c\n");
      ("ordered list", "1. a\n2. b\n");
      ("ordered list with start", "7. seven\n8. eight\n");
      ("ordered with paren delimiter", "1) a\n2) b\n");
      ("task list", "- [ ] open\n- [x] done\n- [X] also done\n");
      ("thematic breaks", "a\n\n---\n\nb\n\n***\n\nc\n\n___\n\nd\n");
      ("table", "| h1 | h2 |\n|---|---|\n| a | b |\n| c | d |\n");
      ("blockquote", "> quoted\n");
      ("fence", "```\ncode <here> & \"there\"\n```\n");
      ("fence with info", "```ocaml\nlet x = 1\n```\n");
      ("inline mix", "**bold** and `code` and ~~gone~~ and [link](http://x) and [[wiki]] #tag\n");
      ("list then table then quote", "- a\n\n| x |\n|---|\n| y |\n\n> q\n");
      ("list interrupted by rule", "- a\n---\n- b\n");
      ("bare number is a paragraph", "10 items counted\n");
      ("html-ish text is escaped", "a < b & c > d\n");
      ("crlf-ish trailing spaces", "trailing   \nlines   \n");
      ("blank lines everywhere", "\n\na\n\n\nb\n\n");
      ("fence containing markdown", "```\n# not a heading\n- not a list\n```\n");
      ("nested-looking indent", "- a\n  - b\n");
      ("table with no separator", "| a | b |\n| c | d |\n") ]
  in
  List.iter (fun (name, src) -> check ("agrees: " ^ name) (fun () -> agree src)) cases

(* ------------------------------- the observation that justifies it all *)

let () = check "the carrier is FLAT for a flat document (depth 1)" (fun () ->
    Wiki_ast.depth (Wiki_ast.parse "# h\n\npara\n") = 1)

let () = check "a list is depth 2 -- an item already CONTAINS a block" (fun () ->
    Wiki_ast.depth (Wiki_ast.parse "- a\n- b\n") = 2)

let () = check "the carrier ADMITS a block inside a block (depth > 1)" (fun () ->
    (* the whole point of HW.2.0.1: this value is constructible, which it
       was not under the depth-2 carrier. Nothing PARSES to it yet — the
       parser still produces the oracle's flat shapes — but the type no
       longer forbids it, and that is what unblocks callout bodies,
       nested lists, footnotes and transclusion. *)
    let nested =
      [ Wiki_ast.Quote
          [ Wiki_ast.Para "outer";
            Wiki_ast.List_block
              { ordered = false; start = 1;
                content = [ Wiki_ast.Item { Wiki_ast.task = None; body = [ Wiki_ast.Para "inner" ] } ] } ] ]
    in
    Wiki_ast.depth nested >= 3)

let () = check "a nested block RENDERS, so the carrier is usable not decorative" (fun () ->
    let nested =
      [ Wiki_ast.Quote
          [ Wiki_ast.Para "outer";
            Wiki_ast.List_block
              { ordered = false; start = 1;
                content = [ Wiki_ast.Item { Wiki_ast.task = None; body = [ Wiki_ast.Para "inner" ] } ] } ] ]
    in
    let html =
      Wiki_ast.render ~inline:(fun s -> s) ~anchor:(fun s -> s) ~escape:(fun s -> s) nested
    in
    let has needle =
      let n = String.length needle and t = String.length html in
      let rec go i = i + n <= t && (String.sub html i n = needle || go (i + 1)) in
      go 0
    in
    has "<blockquote>" && has "<ul>" && has "<p>inner</p>")

let () = check "parse is total: no input raises" (fun () ->
    List.for_all
      (fun s -> (try ignore (Wiki_ast.parse s); true with _ -> false))
      [ ""; "#"; "```"; "|"; ">"; "- "; "1."; "~~"; "\000"; String.make 5000 '#' ])

(* ---- HW.3.3.1 block anchors ^id — both renderers, byte for byte ---- *)

let both src =
  ( Hermes_wiki.render_line_machine ~resolve:(fun _ -> None) src,
    Hermes_wiki.render_markdown ~resolve:(fun _ -> None) src )

let () =
  check "^id on a paragraph: byte-equal, id keeps ^, marker stripped" (fun () ->
      let a, b = both "a claim worth citing ^claim-1\n" in
      a = b && a = "<p id=\"^claim-1\">a claim worth citing</p>\n");
  check "^id on a bullet item: byte-equal, li carries the id" (fun () ->
      let a, b = both "- first thing ^b1\n" in
      a = b
      && (try ignore (Str.search_forward (Str.regexp_string "<li id=\"^b1\">first thing</li>") a 0); true
          with Not_found -> false));
  check "^id on an ordered item: byte-equal, li carries the id" (fun () ->
      let a, b = both "1. one thing ^o1\n" in
      a = b
      && (try ignore (Str.search_forward (Str.regexp_string "<li id=\"^o1\">one thing</li>") a 0); true
          with Not_found -> false));
  check "^id on a task item: byte-equal, the task li carries the id" (fun () ->
      let a, b = both "- [x] done thing ^t1\n" in
      a = b
      && (try ignore (Str.search_forward (Str.regexp_string "id=\"^t1\"") a 0); true
          with Not_found -> false));
  check "the alphabet is narrow: an underscore does not mark" (fun () ->
      let a, b = both "text ^not_ok\n" in
      a = b && a = "<p>text ^not_ok</p>\n");
  check "a bare ^id line is a paragraph, not an anchor (no preceding text)" (fun () ->
      let a, b = both "^solo\n" in
      a = b && a = "<p>^solo</p>\n");
  check "a fence body is immune to the marker" (fun () ->
      let a, b = both "```\ncode ^x\n```\n" in
      a = b
      && not
           (try ignore (Str.search_forward (Str.regexp_string "id=\"^x\"") a 0); true
            with Not_found -> false))

(* ------------------------- HW.2.0.2: the fence info string (lang+meta) *)

let contains hay needle =
  try ignore (Str.search_forward (Str.regexp_string needle) hay 0); true
  with Not_found -> false

let () =
  check "F1 the info string is carried VERBATIM (parse o print = id)" (fun () ->
      Wiki_ast.fence_infos (Wiki_ast.parse "```ocaml linenums {3}\nx\n```\n")
      = [ "ocaml linenums {3}" ]);
  check "F2 lang_of_info: first token, validated, lowercased; junk is None" (fun () ->
      Wiki_ast.lang_of_info "ocaml linenums" = Some "ocaml"
      && Wiki_ast.lang_of_info "OCaml" = Some "ocaml"
      && Wiki_ast.lang_of_info "c++" = Some "c++"
      && Wiki_ast.lang_of_info "{bad}" = None
      && Wiki_ast.lang_of_info "" = None);
  check "F3 a valid lang reaches BOTH renders as class=language-L, byte-equal"
    (fun () ->
      let a, b = both "```ocaml\nlet x = 1\n```\n" in
      a = b && contains a "<pre><code class=\"language-ocaml\">");
  check "F4 an invalid token degrades to EXACTLY the info-less rendering" (fun () ->
      let a, _ = both "```{bad}\nx\n```\n" in
      let plain, _ = both "```\nx\n```\n" in
      a = plain);
  check "F5 an info-less fence renders exactly as before (identity guard)" (fun () ->
      let a, b = both "```\nx\n```\n" in
      a = b && contains a "<pre><code>x")

(* ------------------------------- HW.2.3.1 callouts, in BOTH renderers *)

let () =
  check "CO1 a callout renders as a typed block, identically in both renderers"
    (fun () ->
      let a, b = both "> [!warning] Mind the gap\n> body text\n" in
      a = b
      && contains a "class=\"callout callout-warning\""
      && contains a "Mind the gap"
      && contains a "body text");
  check "CO2 an ALIAS resolves to its canonical type (case-insensitively)" (fun () ->
      let a, b = both "> [!TLDR]\n> x\n" in
      a = b && contains a "callout-abstract");
  check "CO3 an UNKNOWN type is preserved verbatim, never coerced" (fun () ->
      let a, b = both "> [!warnign]\n> x\n" in
      a = b && contains a "callout-warnign" && not (contains a "callout-note"));
  check "CO4 the fold suffix maps to details/open" (fun () ->
      let c, _ = both "> [!note]- collapsed\n> x\n" in
      let e, _ = both "> [!note]+ expanded\n> x\n" in
      contains c "<details class=\"callout callout-note\">"
      && contains e "<details class=\"callout callout-note\" open>");
  check "CO5 ARBITRARY BLOCK CONTENT: a list inside a callout survives" (fun () ->
      let a, b = both "> [!tip] Steps\n> - one\n> - two\n" in
      a = b && contains a "<ul>" && contains a "<li>one</li>");
  check "CO6 an ORDINARY blockquote is untouched — still one per line" (fun () ->
      let a, b = both "> plain one\n> plain two\n" in
      a = b
      && a = "<blockquote>plain one</blockquote>\n<blockquote>plain two</blockquote>\n");
  check "CO7 a callout ends at the first non-quote line" (fun () ->
      let a, b = both "> [!note]\n> inside\n\nafter\n" in
      a = b && contains a "<p>after</p>")

let () =
  Printf.printf "wiki_ast: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_ast" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_ast ]);
  exit (Wiki_suite_telemetry.exit_code self)
