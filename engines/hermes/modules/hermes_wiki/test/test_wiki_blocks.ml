(* The remaining block-level dialect — six rows across the full
   functional envelope:

     N*  nominal      each row's law, on the shape an author writes
     X*  exhaustion   500-deep nesting, 300 footnotes, a 5000-item list
     S*  stuck        empty input, one item, a definition with no reference
     A*  anomaly      malformed markers, markup in a title, FENCED examples,
                      mixed tabs and spaces, dedent by several levels

   The headline laws, one per row:

     HW.2.1.4   depth(parse s) = depth(s), over GENERATED inputs
     HW.2.1.11  a reference and its definition are MUTUALLY REFERRING
     HW.2.3.2   the body is a Block list
     HW.2.3.3   summary inline, body blocks, closed by default
     HW.2.3.5   every ToC anchor is an id the PRODUCTION renderer emits
     HW.2.0.3   two verdicts, because two fixes

   And the law under all of them: nothing an author wrote is ever lost.
   [source_lines (parse s) = split s] is checked on every anomaly in this
   file, because a parser that drops a line silently is worse than one
   that raises. *)

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

let render s = Wiki_blocks.html ~inline:(fun x -> x) ~escape:(fun x -> x) s
let preserved s = Wiki_blocks.source_lines (Wiki_blocks.parse s) = String.split_on_char '\n' s
let anchors s = List.map (fun e -> e.Wiki_blocks.anchor) (Wiki_blocks.toc s)
let note_ids t = List.map (fun f -> f.Wiki_blocks.fid) t.Wiki_blocks.notes
let diags t = List.map Wiki_blocks.diagnostic_line t.Wiki_blocks.diagnostics
let has_diag t d = List.mem (Wiki_blocks.diagnostic_line d) (diags t)
let count_sub hay needle =
  let nh = String.length hay and nn = String.length needle in
  let n = ref 0 in
  for i = 0 to nh - nn do
    if String.sub hay i nn = needle then incr n
  done;
  !n

(* ------------------------------------------- HW.2.1.4 the depth generator

   NOT one hand-written example. A shape is enumerated, rendered under
   several indentation styles and marker styles, and parsed back; the
   expected depth comes from the SHAPE, not from a second parser, so the
   law has something to fail against. The styles are chosen so that every
   level is strictly deeper in COLUMNS — including the tab/space mix,
   where a tab from column 4 lands on 8 exactly as four spaces would. *)

type shape = Sh of shape list

let rec shape_depth = function
  | [] -> 0
  | items -> 1 + List.fold_left (fun m (Sh cs) -> max m (shape_depth cs)) 0 items

let render_shape ~indent ~marker items =
  let b = Buffer.create 256 in
  let rec go level items =
    List.iteri
      (fun i (Sh cs) ->
        Buffer.add_string b
          (indent level ^ marker level (i + 1) ^ Printf.sprintf "item %d.%d\n" level (i + 1));
        go (level + 1) cs)
      items
  in
  go 0 items;
  Buffer.contents b

let styles =
  [ (fun k -> String.make (2 * k) ' ');
    (fun k -> String.make (4 * k) ' ');
    (fun k -> String.make (7 * k) ' ');
    (fun k -> String.make k '\t');
    (* tab, four spaces, tab, … — every level is exactly four columns
       deeper, which is the case a character-counting parser gets wrong *)
    (fun k -> String.concat "" (List.init k (fun i -> if i mod 2 = 0 then "\t" else "    ")));
    (* the whole list STARTS indented: level 0 is at column 4, and the
       list is still depth 1 there *)
    (fun k -> String.make (4 * (k + 1)) ' ') ]

let markers =
  [ (fun _ _ -> "- ");
    (fun _ _ -> "* ");
    (fun _ i -> string_of_int i ^ ". ");
    (fun l i -> if l mod 2 = 0 then "- " else string_of_int i ^ ") ") ]

let rec spine n = if n <= 1 then [ Sh [] ] else [ Sh (spine (n - 1)) ]

let shapes =
  [ [ Sh [] ];
    [ Sh []; Sh []; Sh [] ];
    spine 2;
    spine 3;
    spine 4;
    spine 6;
    spine 8;
    (* a dedent of two levels at once *)
    [ Sh [ Sh [ Sh [] ] ]; Sh [] ];
    (* a dedent of three levels at once, after a shallow sibling *)
    [ Sh []; Sh [ Sh [ Sh [ Sh [] ] ] ]; Sh [] ];
    [ Sh [ Sh []; Sh [ Sh [] ] ]; Sh [ Sh [] ] ] ]

let rec count_items = function [] -> 0 | Sh cs :: rest -> 1 + count_items cs + count_items rest

(* ------------------------------------------------------------ nominal *)

let () =
  check "N1 HW.2.1.4 a nested list is a LIST INSIDE A LIST, not two lists" (fun () ->
      match Wiki_blocks.parse_lists "- a\n  - b\n" with
      | [ Wiki_ast.List_block { content = [ Wiki_ast.Item i ]; _ } ] -> (
          match i.Wiki_ast.body with
          | [ Wiki_ast.Inline_run "a"; Wiki_ast.List_block { content = [ Wiki_ast.Item j ]; _ } ] ->
              j.Wiki_ast.body = [ Wiki_ast.Inline_run "b" ]
          | _ -> false)
      | _ -> false);
  check "N2 HW.2.1.4 depth(parse s) = depth(s) over GENERATED shapes x indents x markers"
    (fun () ->
      List.for_all
        (fun sh ->
          List.for_all
            (fun indent ->
              List.for_all
                (fun marker ->
                  let src = render_shape ~indent ~marker sh in
                  Wiki_blocks.list_depth (Wiki_blocks.parse_lists src) = shape_depth sh
                  && Wiki_blocks.source_list_depth src = shape_depth sh)
                markers)
            styles)
        shapes);
  check "N2b every generated item survives the parse — depth is not bought with loss"
    (fun () ->
      List.for_all
        (fun sh ->
          List.for_all
            (fun indent ->
              let src = render_shape ~indent ~marker:(fun _ _ -> "- ") sh in
              let html = Wiki_ast.render ~inline:(fun x -> x) ~anchor:(fun x -> x)
                           ~escape:(fun x -> x) (Wiki_blocks.parse_lists src) in
              count_sub html "<li>" = count_items sh)
            styles)
        shapes);
  check "N2c the nested carrier IS HW.2.0.1's: Wiki_ast.depth is list_depth + 1" (fun () ->
      let d = Wiki_blocks.parse_lists "- a\n  - b\n    - c\n" in
      Wiki_blocks.list_depth d = 3 && Wiki_ast.depth d = 4);
  check "N3 HW.2.1.11 a reference and its definition are MUTUALLY REFERRING" (fun () ->
      let src = "Claim[^a] holds.\n\n[^a]: Because of the proof.\n" in
      let h = render src in
      contains h "id=\"fnref-a\"" && contains h "href=\"#fn-a\""
      && contains h "id=\"fn-a\"" && contains h "href=\"#fnref-a\""
      && Wiki_blocks.footnote_links_resolve src);
  check "N3b the definition's TEXT reaches the note, and the marker is numbered" (fun () ->
      let h = render "Claim[^a] holds.\n\n[^a]: Because of the proof.\n" in
      contains h "Because of the proof." && contains h ">1</a></sup>");
  check "N4 HW.2.1.11 ORDER IS BY FIRST REFERENCE, never by definition order" (fun () ->
      let src = "[^a]: ay\n\n[^z]: zee\n\nText with [^z] and then [^a].\n" in
      let t = Wiki_blocks.parse src in
      note_ids t = [ "z"; "a" ]
      && List.map (fun f -> f.Wiki_blocks.label) t.Wiki_blocks.notes = [ 1; 2 ]);
  check "N4b a definition collected from ANYWHERE — before, after, inside a block" (fun () ->
      let src = ":::note\n[^inner]: defined inside an admonition\n:::\n\nSee [^inner].\n" in
      let t = Wiki_blocks.parse src in
      note_ids t = [ "inner" ]
      && List.for_all (fun f -> f.Wiki_blocks.defined) t.Wiki_blocks.notes
      && preserved src);
  check "N5 HW.2.3.2 title AND a BLOCK body: a fence and a nested list inside" (fun () ->
      let src =
        ":::note My **Title**\nprose\n\n- a\n  - b\n\n```\ncode\n```\n:::\n"
      in
      let t = Wiki_blocks.parse src in
      match Wiki_blocks.blocks t with
      | [ b ] ->
          b.Wiki_blocks.title = "My **Title**"
          && Wiki_blocks.kind_name b.Wiki_blocks.kind = "note"
          && Wiki_blocks.list_depth (Wiki_blocks.body_blocks b) = 2
          && List.exists
               (function Wiki_ast.Fence _ -> true | _ -> false)
               (Wiki_blocks.body_blocks b)
          && preserved src
      | _ -> false);
  check "N5b HW.2.3.2 the rendered admonition carries type, title and block body" (fun () ->
      let h = render ":::warning Take **care**\n- a\n  - b\n:::\n" in
      contains h "class=\"callout callout-warning\""
      && contains h "<p class=\"callout-title\">Take **care**</p>"
      && count_sub h "<ul>" = 2);
  check "N5c an alias resolves to its canonical type (Wiki_callout's vocabulary, reused)"
    (fun () ->
      match Wiki_blocks.blocks (Wiki_blocks.parse ":::tldr T\nx\n:::\n") with
      | [ b ] -> Wiki_blocks.kind_name b.Wiki_blocks.kind = "abstract"
      | _ -> false);
  check "N6 HW.2.3.3 a toggle is <details>/<summary>, CLOSED by default" (fun () ->
      let h = render ":::details Show me\n- a\n  - b\n:::\n" in
      contains h "<details class=\"callout callout-details\">"
      && (not (contains h "callout-details\" open"))
      && contains h "<summary class=\"callout-title\">Show me</summary>"
      && count_sub h "<ul>" = 2);
  check "N6b `+` opens it and `-` closes it — the author's suffix wins" (fun () ->
      contains (render ":::details+ Open me\nx\n:::\n") "callout-details\" open"
      && not (contains (render ":::toggle- Shut\nx\n:::\n") "callout-toggle\" open"));
  check "N6c an ADMONITION is not a disclosure: no suffix means a <div>" (fun () ->
      let h = render ":::note plain\nx\n:::\n" in
      contains h "<div class=\"callout callout-note\">" && not (contains h "<details"));
  check "N7 HW.2.3.5 the outline is the PAGE'S OWN headings, in order" (fun () ->
      let src = "# Alpha\n\n[TOC]\n\n## Beta\n\n### Gamma\n" in
      Wiki_blocks.has_toc_marker src
      && List.map (fun e -> (e.Wiki_blocks.level, e.Wiki_blocks.text)) (Wiki_blocks.toc src)
         = [ (1, "Alpha"); (2, "Beta"); (3, "Gamma") ]
      && anchors src = [ "alpha"; "beta"; "gamma" ]);
  check "N7b HW.2.3.5 EVERY ToC anchor is an id the PRODUCTION renderer emits" (fun () ->
      let src = "# Alpha\n\n[TOC]\n\n## Beta & Co\n\n### Gamma\n" in
      Wiki_blocks.toc_resolves src
      && List.for_all
           (fun a -> List.mem a (Wiki_blocks.emitted_ids src))
           (anchors src));
  check "N7c the marker renders an outline that LINKS to those anchors" (fun () ->
      let h = render "# Alpha\n\n[TOC]\n\n## Beta\n" in
      contains h "<nav class=\"toc\">"
      && contains h "<li class=\"toc-l1\"><a href=\"#alpha\">Alpha</a></li>"
      && contains h "<li class=\"toc-l2\"><a href=\"#beta\">Beta</a></li>");
  check "N7d the outline is the WHOLE page's: a marker before the headings lists them all"
    (fun () -> List.length (Wiki_blocks.toc "[TOC]\n\n# One\n\n# Two\n") = 2);
  check "N8 HW.2.0.3 verdict one: directive-like and in no vocabulary" (fun () ->
      let t = Wiki_blocks.parse ":::mermaid\ngraph\n:::\n\n:::note\nhi\n:::\n" in
      has_diag t (Wiki_blocks.Unrecognised_directive "mermaid")
      && not (has_diag t (Wiki_blocks.Unrecognised_directive "note")));
  check "N8b HW.2.0.3 verdict two: REGISTERED and used nowhere — a different fix" (fun () ->
      let t = Wiki_blocks.parse ":::mermaid\ngraph\n:::\n" in
      let l = Wiki_blocks.lint ~registered:[ "mermaid"; "tabs" ] t in
      List.mem (Wiki_blocks.Unused_directive "tabs") l
      && not (List.exists
                (function Wiki_blocks.Unrecognised_directive _ -> true | _ -> false) l));
  check "N8c the two verdicts are DISTINCT — same name, different line" (fun () ->
      Wiki_blocks.diagnostic_line (Wiki_blocks.Unrecognised_directive "x")
      <> Wiki_blocks.diagnostic_line (Wiki_blocks.Unused_directive "x"));
  check "N8d registering a name SILENCES verdict one without silencing verdict two" (fun () ->
      let t = Wiki_blocks.parse ":::mermaid\ngraph\n:::\n" in
      Wiki_blocks.lint ~registered:[ "mermaid" ] t = []);
  check "N8e every builtin_directives name is recognised — the vocabularies agree" (fun () ->
      List.for_all
        (fun n ->
          match Wiki_blocks.blocks (Wiki_blocks.parse (":::" ^ n ^ "\nx\n:::\n")) with
          | [ b ] -> (
              match b.Wiki_blocks.kind with
              | Wiki_blocks.Unrecognised _ -> false
              | Wiki_blocks.Admonition _ | Wiki_blocks.Toggle _ -> true)
          | _ -> false)
        Wiki_blocks.builtin_directives);
  check "N8f an ALIAS resolves without appearing in builtin_directives — no stale list"
    (fun () ->
      (not (List.mem "tldr" Wiki_blocks.builtin_directives))
      && Wiki_blocks.lint (Wiki_blocks.parse ":::tldr T\nx\n:::\n") = []);
  check "N9 the PRESERVATION LAW on a document using every construct at once" (fun () ->
      let src =
        "# Head\n\n[TOC]\n\n- a\n  - b\n\nSee [^n] and [^gone].\n\n\
         :::note Title\nbody\n:::\n\n```\n:::fenced\n```\n\n[^n]: the note\n    continued\n"
      in
      preserved src)

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 a 500-LEVEL nesting parses, reports its depth, and renders" (fun () ->
      let n = 500 in
      let src =
        String.concat "\n"
          (List.init n (fun i -> String.make (2 * i) ' ' ^ Printf.sprintf "- l%d" i))
      in
      let d = Wiki_blocks.parse_lists src in
      Wiki_blocks.list_depth d = n && Wiki_blocks.source_list_depth src = n
      && count_sub
           (Wiki_ast.render ~inline:(fun x -> x) ~anchor:(fun x -> x) ~escape:(fun x -> x) d)
           "<li>"
         = n);
  check "X2 300 FOOTNOTES: numbering by first reference, every link resolves" (fun () ->
      let ids = List.init 300 (fun i -> Printf.sprintf "n%d" i) in
      let body = String.concat " " (List.map (fun i -> Printf.sprintf "x[^%s]" i) ids) in
      (* definitions in REVERSE order, so definition order cannot pass for
         reference order *)
      let defs =
        String.concat "\n" (List.rev_map (fun i -> Printf.sprintf "[^%s]: def %s" i i) ids)
      in
      let src = body ^ "\n\n" ^ defs ^ "\n" in
      let t = Wiki_blocks.parse src in
      note_ids t = ids
      && List.for_all (fun f -> f.Wiki_blocks.defined) t.Wiki_blocks.notes
      && Wiki_blocks.footnote_links_resolve src);
  check "X3 a 5000-ITEM flat list stays depth 1 and keeps every item" (fun () ->
      let n = 5000 in
      let src = String.concat "\n" (List.init n (fun i -> Printf.sprintf "- item %d" i)) in
      let d = Wiki_blocks.parse_lists src in
      Wiki_blocks.list_depth d = 1 && Wiki_blocks.source_list_depth src = 1
      && count_sub
           (Wiki_ast.render ~inline:(fun x -> x) ~anchor:(fun x -> x) ~escape:(fun x -> x) d)
           "<li>"
         = n);
  check "X4 50 IDENTICAL headings: 50 distinct anchors, all of them resolving" (fun () ->
      let src = String.concat "\n\n" (List.init 50 (fun _ -> "# Same")) in
      let a = anchors src in
      List.length a = 50
      && List.length (List.sort_uniq compare a) = 50
      && Wiki_blocks.toc_resolves src);
  check "X5 a 200-deep colon-block nesting terminates and preserves every line" (fun () ->
      let n = 200 in
      let src =
        String.concat "\n"
          (List.init n (fun i -> String.make (n + 3 - i) ':' ^ "note")
          @ [ "core" ]
          @ List.init n (fun i -> String.make (i + 4) ':')
          @ [ "" ])
      in
      let t = Wiki_blocks.parse src in
      List.length (Wiki_blocks.all_blocks t) = n && preserved src)

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 EMPTY input: total everywhere, nothing invented" (fun () ->
      let t = Wiki_blocks.parse "" in
      Wiki_blocks.source_lines t = [ "" ]
      && t.Wiki_blocks.notes = []
      && t.Wiki_blocks.diagnostics = []
      && Wiki_blocks.list_depth (Wiki_blocks.parse_lists "") = 0
      && Wiki_blocks.source_list_depth "" = 0
      && Wiki_blocks.toc "" = []
      && Wiki_blocks.toc_resolves ""
      && not (Wiki_blocks.has_toc_marker ""));
  check "S2 ONE item is depth 1, on both sides of the law" (fun () ->
      Wiki_blocks.list_depth (Wiki_blocks.parse_lists "- only\n") = 1
      && Wiki_blocks.source_list_depth "- only\n" = 1);
  check "S3 a DEFINITION WITH NO REFERENCE is unreferenced, and NOT undefined" (fun () ->
      let src = "[^a]: a note nobody cites\n" in
      let t = Wiki_blocks.parse src in
      has_diag t (Wiki_blocks.Unreferenced_footnote "a")
      && (not (has_diag t (Wiki_blocks.Undefined_footnote "a")))
      && t.Wiki_blocks.notes = []
      && preserved src);
  check "S4 a REFERENCE WITH NO DEFINITION is undefined, and NOT unreferenced" (fun () ->
      let src = "See [^a].\n" in
      let t = Wiki_blocks.parse src in
      has_diag t (Wiki_blocks.Undefined_footnote "a")
      && (not (has_diag t (Wiki_blocks.Unreferenced_footnote "a")))
      && note_ids t = [ "a" ]);
  check "S4b an undefined reference still RENDERS, still LINKS, and says so" (fun () ->
      let src = "See [^a].\n" in
      let h = render src in
      contains h "id=\"fnref-a\"" && contains h "href=\"#fn-a\""
      && contains h "footnote definition missing: a"
      && Wiki_blocks.footnote_links_resolve src);
  check "S5 [TOC] with NO HEADINGS is a named gap, not an empty promise" (fun () ->
      let src = "[TOC]\n\njust prose here\n" in
      let t = Wiki_blocks.parse src in
      has_diag t Wiki_blocks.Toc_without_headings
      && Wiki_blocks.toc src = []
      && not (contains (render src) "<li class=\"toc-"));
  check "S6 an EMPTY admonition body still renders, with the type as its title" (fun () ->
      let src = ":::note\n:::\n" in
      match Wiki_blocks.blocks (Wiki_blocks.parse src) with
      | [ b ] ->
          Wiki_blocks.body_blocks b = []
          && contains (render src) "<p class=\"callout-title\">Note</p>"
          && preserved src
      | _ -> false);
  check "S7 a document with no list at all has depth 0 on both sides" (fun () ->
      Wiki_blocks.list_depth (Wiki_blocks.parse_lists "just a paragraph\n") = 0
      && Wiki_blocks.source_list_depth "just a paragraph\n" = 0)

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 MALFORMED footnote markers are preserved verbatim, and raise nothing" (fun () ->
      let src = "[^] and [^ ] and [^a and [^a b] and ^a alone\n" in
      let t = Wiki_blocks.parse src in
      t.Wiki_blocks.notes = [] && preserved src && contains (render src) "[^]");
  check "A1b TOTAL over pathological input, preservation included" (fun () ->
      List.for_all
        (fun s ->
          let t = Wiki_blocks.parse s in
          ignore (Wiki_blocks.source_lines t);
          ignore (Wiki_blocks.list_depth (Wiki_blocks.parse_lists s));
          ignore (Wiki_blocks.source_list_depth s);
          ignore (Wiki_blocks.toc s);
          preserved s)
        [ ""; "\n"; ":"; "::"; ":::"; ":::::::"; ":::note"; "[^"; "[^]"; "[^]:"; "[TOC"; "[TOC]";
          "```"; "```\n:::note"; "- "; "-"; "\t"; "   "; "1."; "1. "; String.make 500 ':';
          String.make 500 '\t'; "- a\n\t\t\t- b"; ":::a\n:::b\n:::\n:::" ]);
  check "A2 MARKUP IN A TITLE reaches the inline renderer, unescaped" (fun () ->
      contains (render ":::tip **do** this\nx\n:::\n")
        "<p class=\"callout-title\">**do** this</p>");
  check "A2b a bracketed title is unwrapped (`:::note[Title]`, the newer form)" (fun () ->
      match Wiki_blocks.blocks (Wiki_blocks.parse ":::note[Boxed]\nx\n:::\n") with
      | [ b ] -> b.Wiki_blocks.title = "Boxed"
      | _ -> false);
  check "A3 A FENCED EXAMPLE IS AN EXAMPLE: no block, no note, no marker, no list"
    (fun () ->
      let src = "```\n:::note\n[^a]: def\n[TOC]\n- a\n  - b\n```\n" in
      let t = Wiki_blocks.parse src in
      Wiki_blocks.all_blocks t = []
      && t.Wiki_blocks.notes = []
      && (not (Wiki_blocks.has_toc_marker src))
      && Wiki_blocks.source_list_depth src = 0
      && Wiki_blocks.list_depth (Wiki_blocks.parse_lists src) = 0
      && preserved src);
  check "A3b INLINE BACKTICKS are an example too — `[^a]` and `:::note` in prose" (fun () ->
      let src = "the `[^a]` marker, and a `:::note` block, described\n" in
      let t = Wiki_blocks.parse src in
      t.Wiki_blocks.notes = [] && Wiki_blocks.all_blocks t = []);
  check "A3c a fenced [TOC] does not make an outline; an unfenced one does" (fun () ->
      (not (Wiki_blocks.has_toc_marker "```\n[TOC]\n```\n"))
      && Wiki_blocks.has_toc_marker "[TOC]\n");
  check "A4 MIXED TABS AND SPACES at one column are SIBLINGS, not levels" (fun () ->
      let src = "- a\n    - b\n\t- c\n" in
      Wiki_blocks.list_depth (Wiki_blocks.parse_lists src) = 2
      && Wiki_blocks.source_list_depth src = 2
      &&
      match Wiki_blocks.parse_lists src with
      | [ Wiki_ast.List_block { content = [ Wiki_ast.Item i ]; _ } ] -> (
          match i.Wiki_ast.body with
          | [ Wiki_ast.Inline_run "a"; Wiki_ast.List_block { content = [ _; _ ]; _ } ] -> true
          | _ -> false)
      | _ -> false);
  check "A4b a tab and four spaces parse to the SAME TREE, byte for byte" (fun () ->
      Wiki_blocks.parse_lists "- a\n\t- b\n" = Wiki_blocks.parse_lists "- a\n    - b\n");
  check "A5 a list STARTING AT DEPTH 2 is depth 1 — the first marker opens level 1"
    (fun () ->
      let src = "        - a\n        - b\n" in
      Wiki_blocks.list_depth (Wiki_blocks.parse_lists src) = 1
      && Wiki_blocks.source_list_depth src = 1);
  check "A6 a DEDENT OF THREE LEVELS AT ONCE lands where it dedented to" (fun () ->
      let src = "- a\n  - b\n    - c\n      - d\n- e\n" in
      Wiki_blocks.list_depth (Wiki_blocks.parse_lists src) = 4
      && Wiki_blocks.source_list_depth src = 4
      &&
      match Wiki_blocks.parse_lists src with
      | [ Wiki_ast.List_block { content = [ Wiki_ast.Item _; Wiki_ast.Item e ]; _ } ] ->
          e.Wiki_ast.body = [ Wiki_ast.Inline_run "e" ]
      | _ -> false);
  check "A6b a BLANK LINE ends the list — two lists, not one nested pair" (fun () ->
      let src = "- a\n\n  - b\n" in
      Wiki_blocks.list_depth (Wiki_blocks.parse_lists src) = 1
      && Wiki_blocks.source_list_depth src = 1);
  check "A6c an INDENTED CONTINUATION joins its item, and adds no level" (fun () ->
      let src = "- a\n  more text\n" in
      Wiki_blocks.list_depth (Wiki_blocks.parse_lists src) = 1
      &&
      match Wiki_blocks.parse_lists src with
      | [ Wiki_ast.List_block { content = [ Wiki_ast.Item i ]; _ } ] ->
          i.Wiki_ast.body = [ Wiki_ast.Inline_run "a more text" ]
      | _ -> false);
  check "A6d a KIND SWITCH at one column is one level, and two lists" (fun () ->
      let src = "- a\n1. b\n" in
      Wiki_blocks.list_depth (Wiki_blocks.parse_lists src) = 1
      && Wiki_blocks.source_list_depth src = 1
      && List.length (Wiki_blocks.parse_lists src) = 2);
  check "A7 an UNCLOSED block clamps at EOF, is NAMED, and loses nothing" (fun () ->
      let src = ":::note\nbody\n" in
      let t = Wiki_blocks.parse src in
      has_diag t (Wiki_blocks.Unclosed_block "note")
      && (match Wiki_blocks.blocks t with [ b ] -> b.Wiki_blocks.closer = None | _ -> false)
      && preserved src);
  check "A8 NESTING: an outer :::: holds an inner :::, and both are seen" (fun () ->
      let src = "::::warning Outer\nbefore\n:::note Inner\ndeep\n:::\nafter\n::::\n" in
      let t = Wiki_blocks.parse src in
      List.length (Wiki_blocks.blocks t) = 1
      && List.length (Wiki_blocks.all_blocks t) = 2
      && List.map (fun b -> Wiki_blocks.kind_name b.Wiki_blocks.kind) (Wiki_blocks.all_blocks t)
         = [ "warning"; "note" ]
      && preserved src);
  check "A8b the closer needs AT LEAST as many colons — a longer one still closes" (fun () ->
      let src = ":::note\nbody\n::::\n" in
      let t = Wiki_blocks.parse src in
      (match Wiki_blocks.blocks t with
      | [ b ] -> b.Wiki_blocks.closer = Some "::::" && b.Wiki_blocks.body_source = [ "body" ]
      | _ -> false)
      && not (has_diag t (Wiki_blocks.Unclosed_block "note")));
  check "A9 a `:::` INSIDE A FENCE in the body does not close the block" (fun () ->
      let src = ":::note\n```text\n:::\n```\nstill inside\n:::\n" in
      match Wiki_blocks.blocks (Wiki_blocks.parse src) with
      | [ b ] ->
          b.Wiki_blocks.body_source = [ "```text"; ":::"; "```"; "still inside" ]
          && List.exists
               (function Wiki_blocks.Fenced _ -> true | _ -> false)
               b.Wiki_blocks.body
          && preserved src
      | _ -> false);
  check "A10 DUPLICATE HEADINGS take the renderer's -1/-2 anchors, not a plain slug"
    (fun () ->
      let src = "# a\n\n# a-1\n\n# a\n" in
      anchors src = [ "a"; "a-1"; "a-2" ]
      && Wiki_blocks.emitted_ids src = [ "a"; "a-1"; "a-2" ]
      && Wiki_blocks.toc_resolves src);
  check "A10b an EMPTY heading slug becomes `section`, exactly as the renderer's does"
    (fun () ->
      let src = "# !!!\n\n# ???\n" in
      anchors src = [ "section"; "section-1" ] && Wiki_blocks.emitted_ids src = anchors src);
  check "A10c a heading INSIDE a callout is anchored by the renderer, so it is in the ToC"
    (fun () ->
      let src = "> [!note] T\n> # Inner\n\n# Outer\n" in
      Wiki_blocks.toc_resolves src
      && List.mem "inner" (anchors src)
      && anchors src = Wiki_blocks.emitted_ids src);
  check "A11 an UNKNOWN directive is preserved verbatim, RENDERED, and recorded" (fun () ->
      let src = ":::warnign Careful\nbody\n:::\n" in
      let t = Wiki_blocks.parse src in
      has_diag t (Wiki_blocks.Unrecognised_directive "warnign")
      && contains (render src) "callout-warnign"
      && contains (render src) "body"
      && preserved src);
  check "A12 a DUPLICATE footnote definition: first wins, second is named and kept" (fun () ->
      let src = "[^a]: one\n\n[^a]: two\n\nRef [^a].\n" in
      let t = Wiki_blocks.parse src in
      has_diag t (Wiki_blocks.Duplicate_footnote "a")
      && (match t.Wiki_blocks.notes with
         | [ f ] -> f.Wiki_blocks.definition = [ "one" ]
         | _ -> false)
      && preserved src);
  check "A13 THREE references to one note link back three times, each to its own marker"
    (fun () ->
      let src = "a[^n] b[^n] c[^n]\n\n[^n]: once\n" in
      let h = render src in
      (match Wiki_blocks.parse src with
      | { Wiki_blocks.notes = [ f ]; _ } -> f.Wiki_blocks.refs = 3
      | _ -> false)
      && contains h "id=\"fnref-n\"" && contains h "id=\"fnref-n-2\"" && contains h "id=\"fnref-n-3\""
      && contains h "href=\"#fnref-n-3\""
      && Wiki_blocks.footnote_links_resolve src);
  check "A14 an indented `:::` is NOT an opener — the grammar is column zero" (fun () ->
      Wiki_blocks.all_blocks (Wiki_blocks.parse "  :::note\n  x\n  :::\n") = []);
  check "A16 the stated divergence: a nested reading KEEPS an ordered start the flat one loses"
    (fun () ->
      let src = "- a\n3. b\n" in
      let start_of = function
        | [ _; Wiki_ast.List_block { start; _ } ] -> Some start
        | _ -> None
      in
      start_of (Wiki_blocks.parse_lists src) = Some 3
      && start_of (Wiki_ast.parse src) = Some 1);
  check "A15 a hyphenated name keeps its word; a TRAILING hyphen is the fold suffix"
    (fun () ->
      (match Wiki_blocks.blocks (Wiki_blocks.parse ":::my-block\nx\n:::\n") with
      | [ b ] -> Wiki_blocks.kind_name b.Wiki_blocks.kind = "my-block"
      | _ -> false)
      && contains (render ":::note- Folded\nx\n:::\n") "<details class=\"callout callout-note\">")

let () =
  Printf.printf "wiki_blocks: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_blocks" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_blocks ]);
  exit (Wiki_suite_telemetry.exit_code self)
