(* HW.6.2.1 / HW.6.3.7 / HW.6.5.1 / HW.6.9.2 / HW.6.9.3 / HW.6.10.1 —
   the export surfaces, across the full functional envelope:

     N*  nominal      each row's headline law over a live corpus
     X*  exhaustion   a wide corpus, a long page, a many-token query
     S*  stuck        empty corpus, empty page, empty query, undefined name
     A*  anomaly      duplicate ids, broken fragments, markup and quotes
                      in a title, control bytes, fenced examples

   The two laws this slice is really about:

   GLOBALLY UNIQUE ANCHORS (HW.6.9.2). Concatenating N pages makes every
   per-page anchor a potential collision, and a single-file export whose
   links point at the WRONG section is worse than no export. The suite
   therefore proves uniqueness over the WHOLE concatenation and proves
   that a link still lands on the section it named — not merely that it
   lands somewhere.

   OFFLINE SEARCH IS ONLINE SEARCH (HW.6.3.7). Not one example: a
   DIFFERENTIAL over every single-token query the corpus admits, every
   pair drawn from its vocabulary, repeated tokens, and misses. The
   reference here is an independent scan of the corpus written to
   `Wiki_search`'s specification; the register probe runs the same
   differential against the real `Wiki_search`. *)

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

let occurrences hay needle =
  let nh = String.length hay and nn = String.length needle in
  let n = ref 0 in
  if nn > 0 then
    for i = 0 to nh - nn do
      if String.sub hay i nn = needle then incr n
    done;
  !n

let page_of m slug =
  match Hermes_wiki.page m slug with Some p -> p | None -> failwith ("no page " ^ slug)

(* ------------------------------------------------------------ corpus *)

let alpha_body =
  "# Alpha Note\n\n\
   ## Overview\n\n\
   Shared zebra word here. See [[Beta Note#Overview]] and [[beta]].\n\n\
   A claim block. ^parity\n\n\
   ```ocaml\n\
   let fenced = zebra harpsichord\n\
   ```\n"

let beta_body =
  "# Beta Note\n\n## Overview\n\nzebra appears twice: zebra here.\n\n- item text ^it\n"

let gamma_body =
  "# Gamma \"quoted\" **title**\n\nBody with an [external](https://example.com/x) link.\n"

let delta_body = "# Delta\n\nfirst line ^dup\n\nsecond line ^dup\n"

let corpus =
  [ ("docs/hermes/wiki/alpha.md", alpha_body);
    ("docs/hermes/wiki/beta.md", beta_body);
    ("docs/hermes/wiki/gamma.md", gamma_body);
    ("docs/hermes/wiki/delta.md", delta_body) ]

let m = Hermes_wiki.build corpus
let slugs = List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug) m.Hermes_wiki.pages

(* ------------------------------ the independent search reference ---- *)

(* Written to `Wiki_search`'s specification and NOT to this module's
   implementation: headings weigh 3, declared keywords 2, the
   description 1, the body 1, fences excluded, a page scores only when
   it carries EVERY query token, ties break by slug. *)

let ref_tokens s =
  let lower = String.lowercase_ascii s in
  let out = ref [] and buf = Buffer.create 16 in
  let flush () =
    if Buffer.length buf >= 2 then out := Buffer.contents buf :: !out;
    Buffer.clear buf
  in
  String.iter
    (fun c -> if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') then Buffer.add_char buf c
              else flush ())
    lower;
  flush ();
  List.rev !out

let ref_body_lines raw =
  let in_fence = ref false in
  String.split_on_char '\n' raw
  |> List.filter (fun line ->
         let t = String.trim line in
         if String.length t >= 3 && String.sub t 0 3 = "```" then (in_fence := not !in_fence; false)
         else not !in_fence)

let ref_counts (p : Hermes_wiki.page) =
  let tbl = Hashtbl.create 64 in
  let add w t = Hashtbl.replace tbl t (w + Option.value ~default:0 (Hashtbl.find_opt tbl t)) in
  List.iter (fun (_, text, _) -> List.iter (add 3) (ref_tokens text)) p.Hermes_wiki.headings;
  List.iter (fun k -> List.iter (add 2) (ref_tokens k)) p.Hermes_wiki.meta.Hermes_wiki.keywords;
  List.iter (add 1) (ref_tokens p.Hermes_wiki.meta.Hermes_wiki.description);
  List.iter
    (fun line ->
      if not (String.length (String.trim line) > 0 && (String.trim line).[0] = '#') then begin
        let text, _ = Wiki_ast.block_anchor_split line in
        List.iter (add 1) (ref_tokens text)
      end)
    (ref_body_lines p.Hermes_wiki.raw);
  Hashtbl.fold (fun t c acc -> (t, c) :: acc) tbl [] |> List.sort compare

let ref_index (model : Hermes_wiki.model) =
  model.Hermes_wiki.pages
  |> List.map (fun (p : Hermes_wiki.page) -> (p.Hermes_wiki.slug, ref_counts p))
  |> List.sort compare

let ref_search idx q =
  match ref_tokens q with
  | [] -> []
  | qs ->
      idx
      |> List.filter_map (fun (slug, counts) ->
             let scores =
               List.map (fun t -> Option.value ~default:0 (List.assoc_opt t counts)) qs
             in
             if List.exists (fun s -> s = 0) scores then None
             else Some (slug, List.fold_left ( + ) 0 scores))
      |> List.sort (fun (s1, x1) (s2, x2) -> if x1 = x2 then compare s1 s2 else compare x2 x1)

let online = ref_index m
let idx =
  Wiki_export.search_index ~tokenise:ref_tokens ~search:(ref_search online) ~digest:"pin-0001" m

let rec take n xs = if n <= 0 then [] else match xs with [] -> [] | x :: t -> x :: take (n - 1) t

let query_set =
  let vocab = Wiki_export.vocabulary idx in
  let head = take 9 vocab in
  vocab
  @ List.concat_map (fun a -> List.map (fun b -> a ^ " " ^ b) head) head
  @ [ ""; " "; "a"; "!!"; "harpsichord"; "nosuchtoken"; "zebra zebra";
      "zebra overview note alpha beta"; "ZEBRA"; "zebra!nosuchtoken" ]

(* ------------------------------------------------------------ nominal *)

let () =
  check "N1 HW.6.2.1 the API serves the SAME PAGE SET the site serves" (fun () ->
      Wiki_export.json_slugs m = List.sort compare slugs
      && List.length (Wiki_export.json_slugs m) = 4);
  check "N1b HW.6.2.1 the API carries the HTML surface's bytes VERBATIM" (fun () ->
      List.for_all
        (fun (p : Hermes_wiki.page) ->
          contains (Wiki_export.json m)
            ("\"html\":" ^ Wiki_export.json_string p.Hermes_wiki.html))
        m.Hermes_wiki.pages);
  check "N1c HW.6.2.1 the API's anchors ARE Hermes_wiki.anchors" (fun () ->
      List.for_all
        (fun (p : Hermes_wiki.page) ->
          let a = Hermes_wiki.anchors m p.Hermes_wiki.slug in
          contains (Wiki_export.json m)
            ("\"anchors\":["
            ^ String.concat "," (List.map Wiki_export.json_string a)
            ^ "]"))
        m.Hermes_wiki.pages
      && Hermes_wiki.anchors m "alpha" <> []);
  check "N1d HW.6.2.1 the API cannot hide the builder's anomalies" (fun () ->
      contains (Wiki_export.json m) "\"anomalies\":");
  check "N2 the export is DETERMINISTIC: byte-identical over an unchanged corpus"
    (fun () ->
      let m2 = Hermes_wiki.build corpus in
      Wiki_export.json m2 = Wiki_export.json m
      && Wiki_export.single_file_html m2 = Wiki_export.single_file_html m
      && Wiki_export.plain_text m2 = Wiki_export.plain_text m
      && Wiki_export.index_json
           (Wiki_export.search_index ~tokenise:ref_tokens
              ~search:(ref_search (ref_index m2)) ~digest:"pin-0001" m2)
         = Wiki_export.index_json idx);
  check "N2b the export carries NO timestamp, host or moving version" (fun () ->
      let h = Wiki_export.single_file_html m in
      (not (contains h "generated"))
      && (not (contains h "2026"))
      && not (contains (Wiki_export.json m) "generated_at"))

(* ------------------------------------- HW.6.9.2 the anchor law *)

let () =
  check "N3 HW.6.9.2 GLOBALLY UNIQUE ANCHORS over the WHOLE concatenation" (fun () ->
      let a = Wiki_export.single_file_anchors m in
      a <> [] && List.length (List.sort_uniq compare a) = List.length a);
  check "N3b the collision the law exists for: two pages, one `## Overview` each"
    (fun () ->
      (* both pages emit the bare id `overview`; in one document only one
         of them could be reached unless they are namespaced *)
      let a = Wiki_export.single_file_anchors m in
      List.mem "alpha--overview" a && List.mem "beta--overview" a
      && occurrences (Wiki_export.single_file_html m) "id=\"overview\"" = 0);
  check "N4 HW.6.9.2 every emitted in-document link RESOLVES" (fun () ->
      let a = Wiki_export.single_file_anchors m and l = Wiki_export.single_file_links m in
      l <> [] && List.for_all (fun t -> List.mem t a) l && Wiki_export.dead_links m = []);
  check "N4b a link lands on the section it NAMED, not merely somewhere" (fun () ->
      (* alpha links to [[Beta Note#Overview]]; before namespacing both
         pages' Overview were `#overview` and this link resolved to
         ALPHA's own section — the exact failure the row is about *)
      let h = Wiki_export.single_file_html m in
      contains h "href=\"#beta--overview\""
      && occurrences h "href=\"#alpha--overview\"" = 0);
  check "N4c an inter-page link becomes an in-document link" (fun () ->
      let h = Wiki_export.single_file_html m in
      contains h "href=\"#page-beta\"" && occurrences h ".html\"" = 0);
  check "N4d every page is reachable from the export's own contents list" (fun () ->
      let h = Wiki_export.single_file_html m in
      List.for_all (fun s -> contains h ("href=\"#page-" ^ s ^ "\"")) slugs
      && List.for_all (fun s -> contains h ("id=\"page-" ^ s ^ "\"")) slugs)

(* --------------------------------- HW.6.9.3 the second render target *)

let () =
  check "N5 HW.6.9.3 the heading STRUCTURE survives into a target with no tags"
    (fun () ->
      List.for_all
        (fun (p : Hermes_wiki.page) ->
          Wiki_export.text_headings (Wiki_export.page_text p.Hermes_wiki.raw)
          = List.map
              (fun (l, t, _) -> (l, Wiki_export.inline_text t))
              p.Hermes_wiki.headings)
        m.Hermes_wiki.pages
      && Wiki_export.text_headings (Wiki_export.page_text alpha_body)
         = [ (1, "Alpha Note"); (2, "Overview") ]);
  check "N5b the text target is PRESENTATION-free: no tags, no hrefs, no ids"
    (fun () ->
      let t = Wiki_export.plain_text m in
      (not (contains t "<h1"))
      && (not (contains t "href="))
      && (not (contains t "id=\""))
      && not (contains t "[["));
  check "N5c the text target keeps the CODE (a render that drops it is not a render)"
    (fun () -> contains (Wiki_export.page_text alpha_body) "let fenced = zebra harpsichord");
  check "N6 the corpus text render is the pages' renders, in slug order" (fun () ->
      Wiki_export.text_headings (Wiki_export.plain_text m)
      = List.concat_map
          (fun s ->
            Wiki_export.text_headings (Wiki_export.page_text (page_of m s).Hermes_wiki.raw))
          (List.sort compare slugs))

(* ---------------------------------------------- HW.6.5.1 word count *)

let () =
  check "N7 HW.6.5.1 FENCE-EXCLUDED: a pasted fence adds exactly zero" (fun () ->
      let without = "# T\n\nalpha beta gamma\n" in
      let with_fence = "# T\n\nalpha beta gamma\n\n```sh\none two three four five\n```\n" in
      Wiki_export.word_count without = Wiki_export.word_count with_fence
      && Wiki_export.word_count without = 4);
  check "N7b a word needs a letter or digit; punctuation is not prose" (fun () ->
      Wiki_export.word_count "one two three" = 3
      && Wiki_export.word_count "- | > *** ---" = 0
      && Wiki_export.word_count "a1 b2" = 2);
  check "N7c a ^id ADDRESS is not a word the author wrote" (fun () ->
      Wiki_export.word_count "three plain words ^anchor" = 3);
  check "N7d markup is not counted as words of its own" (fun () ->
      Wiki_export.word_count "see [[Beta Note]] now" = 4
      && Wiki_export.word_count "**bold** text" = 2);
  check "N8 the corpus total is ADDITIVE over its pages" (fun () ->
      let per = Wiki_export.page_word_counts m in
      List.length per = 4
      && per = List.sort compare per
      && Wiki_export.corpus_word_count m = List.fold_left (fun a (_, n) -> a + n) 0 per
      && Wiki_export.corpus_word_count m > 0);
  check "N8b HW.6.5.1 DETERMINISTIC: the same bytes give the same number" (fun () ->
      Wiki_export.word_count alpha_body = Wiki_export.word_count alpha_body
      && Wiki_export.page_word_counts m = Wiki_export.page_word_counts (Hermes_wiki.build corpus))

(* ------------------------------------------------- HW.6.10.1 extlinks *)

let defs =
  [ { Wiki_export.name = "issue"; base = "https://tracker/%s"; caption = "issue %s" };
    { Wiki_export.name = "rfc"; base = "https://rfc/"; caption = "" } ]

let () =
  check "N9 HW.6.10.1 ONE DEFINITION PER NAME: a distinct table is admitted" (fun () ->
      Wiki_export.extlink_table defs = Ok defs);
  check "N9b a name defined TWICE is REFUSED, and every offender named" (fun () ->
      let dup =
        defs @ [ { Wiki_export.name = "issue"; base = "https://other/%s"; caption = "" };
                 { Wiki_export.name = "rfc"; base = "https://x/"; caption = "" } ]
      in
      Wiki_export.extlink_table dup = Error [ "issue"; "rfc" ]);
  check "N9c a use EXPANDS, with the value substituted into base and caption" (fun () ->
      Wiki_export.expand_extlinks defs "see :issue:`42` today"
      = "see <a href=\"https://tracker/42\">issue 42</a> today");
  check "N9d a caption-less definition shows the URL it built" (fun () ->
      Wiki_export.expand_extlinks defs ":rfc:`2119`"
      = "<a href=\"https://rfc/2119\">https://rfc/2119</a>");
  check "N9e uses are COUNTABLE, defined or not" (fun () ->
      Wiki_export.extlink_uses "a :issue:`1` b :ghost:`2`" = [ ("issue", "1"); ("ghost", "2") ])

(* --------------------------- HW.6.3.7 offline search IS online search *)

let () =
  check "N10 HW.6.3.7 THE DIFFERENTIAL: offline = online over every query" (fun () ->
      List.length query_set > 60
      && List.for_all
           (fun q -> Wiki_export.offline_search idx q = ref_search online q)
           query_set);
  check "N10b the differential is NOT VACUOUS: real hits, real ranking, real misses"
    (fun () ->
      Wiki_export.offline_search idx "zebra" = [ ("beta", 2); ("alpha", 1) ]
      && Wiki_export.offline_search idx "zebra overview" <> []
      && Wiki_export.offline_search idx "nosuchtoken" = []);
  check "N10c the postings ARE the online engine's own answers" (fun () ->
      List.for_all
        (fun t -> Wiki_export.postings idx t = ref_search online t)
        (Wiki_export.vocabulary idx)
      && Wiki_export.vocabulary idx <> []);
  check "N10d a REPEATED query token counts twice, as a corpus scan counts it" (fun () ->
      Wiki_export.offline_search idx "zebra zebra"
      = List.map (fun (s, n) -> (s, 2 * n)) (Wiki_export.offline_search idx "zebra"));
  check "N10e DIGEST-PINNED: the online index's pin travels into the export" (fun () ->
      Wiki_export.index_digest idx = "pin-0001"
      && contains (Wiki_export.index_json idx) "\"digest\":\"pin-0001\"");
  check "N10f a moved pin is a ONE-LINE, VISIBLE diff of the export" (fun () ->
      let stale =
        Wiki_export.search_index ~tokenise:ref_tokens ~search:(ref_search online)
          ~digest:"pin-0002" m
      in
      Wiki_export.index_json stale <> Wiki_export.index_json idx
      && Wiki_export.index_canonical stale = Wiki_export.index_canonical idx);
  check "N10g the export is the SAME index — a fenced-only word is absent from it"
    (fun () ->
      (* `harpsichord` appears in the corpus ONLY inside a fence; the
         online engine excluded it, and the export inherits that *)
      (not (List.mem "harpsichord" (Wiki_export.vocabulary idx)))
      && Wiki_export.offline_search idx "harpsichord" = []
      && contains alpha_body "harpsichord")

(* --------------------------------------------------------- exhaustion *)

let wide =
  List.init 60 (fun i ->
      ( Printf.sprintf "docs/hermes/wiki/p%02d.md" i,
        Printf.sprintf "# Page %02d\n\n## Overview\n\nword%02d shared\n\nblock %02d ^ref\n" i i i ))

let wide_m = Hermes_wiki.build wide
let long_body = "# Long\n\n" ^ String.concat "\n\n" (List.init 2000 (fun i -> Printf.sprintf "line number %d here" i))

let () =
  check "X1 a WIDE corpus: 60 pages, 60 identical anchors, all still unique" (fun () ->
      let a = Wiki_export.single_file_anchors wide_m in
      List.length (List.sort_uniq compare a) = List.length a
      && List.length a >= 60 * 4
      && Wiki_export.dead_links wide_m = []);
  check "X1b a wide corpus's links all resolve" (fun () ->
      let a = Wiki_export.single_file_anchors wide_m in
      List.for_all (fun l -> List.mem l a) (Wiki_export.single_file_links wide_m));
  check "X2 a LONG page counts, renders and exports without blowing up" (fun () ->
      Wiki_export.word_count long_body = 1 + (4 * 2000)
      && String.length (Wiki_export.page_text long_body) > 10000
      && Wiki_export.text_headings (Wiki_export.page_text long_body) = [ (1, "Long") ]);
  check "X3 a MANY-TOKEN query still agrees with the online engine" (fun () ->
      let q = "zebra overview note alpha beta appears twice here shared word" in
      Wiki_export.offline_search idx q = ref_search online q);
  check "X4 a DEEPLY NESTED body is total and keeps its headings" (fun () ->
      let body = "# Deep\n\n> quoted\n>\n> - a\n>   - b\n>     - c\n\n## After\n\ntail\n" in
      Wiki_export.word_count body >= 0
      && Wiki_export.text_headings (Wiki_export.page_text body) = [ (1, "Deep"); (2, "After") ])

(* -------------------------------------------------------------- stuck *)

let empty_m = Hermes_wiki.build []

let () =
  check "S1 the EMPTY CORPUS is a defined value on every surface, never a raise"
    (fun () ->
      Wiki_export.json empty_m = "{\"pages\":[],\"anomalies\":[]}"
      && Wiki_export.json_slugs empty_m = []
      && Wiki_export.single_file_anchors empty_m = []
      && Wiki_export.single_file_links empty_m = []
      && Wiki_export.dead_links empty_m = []
      && Wiki_export.plain_text empty_m = ""
      && Wiki_export.page_word_counts empty_m = []
      && Wiki_export.corpus_word_count empty_m = 0
      && contains (Wiki_export.single_file_html empty_m) "<body>");
  check "S1b a ONE-PAGE corpus needs no special case" (fun () ->
      let one = Hermes_wiki.build [ ("docs/hermes/wiki/solo.md", "# Solo\n\nword\n") ] in
      Wiki_export.json_slugs one = [ "solo" ]
      && Wiki_export.dead_links one = []
      && Wiki_export.corpus_word_count one = 2);
  check "S2 a page with NO WORDS is zero, not an error" (fun () ->
      let none = Hermes_wiki.build [ ("docs/hermes/wiki/nil.md", "") ] in
      Wiki_export.corpus_word_count none = 0
      && Wiki_export.page_text "" = ""
      && Wiki_export.text_headings "" = []
      && List.length (Wiki_export.json_slugs none) = 1
      && contains (Wiki_export.single_file_html none) "id=\"page-nil\"");
  check "S3 a query with NO TOKENS returns nothing (never everything)" (fun () ->
      Wiki_export.offline_search idx "" = []
      && Wiki_export.offline_search idx " " = []
      && Wiki_export.offline_search idx "a" = []
      && Wiki_export.offline_search idx "!!" = []);
  check "S4 an UNDEFINED extlink name is left VERBATIM — a mark, not a dead link"
    (fun () ->
      Wiki_export.expand_extlinks defs "see :ghost:`9` here" = "see :ghost:`9` here"
      && Wiki_export.expand_extlinks [] ":issue:`1`" = ":issue:`1`");
  check "S5 an EMPTY definition table admits and expands nothing" (fun () ->
      Wiki_export.extlink_table [] = Ok [] && Wiki_export.expand_extlinks [] "plain" = "plain")

(* ------------------------------------------------------------ anomaly *)

let broken_m =
  Hermes_wiki.build
    [ ("docs/hermes/wiki/alpha.md", "# Alpha\n\nSee [[beta#Ghost]] and [[beta#^parity]].\n");
      ("docs/hermes/wiki/beta.md", "# Beta\n\n## Real\n\nbody. ^parity\n") ]

let () =
  check "A1 a DUPLICATE block id on one page stays globally unique" (fun () ->
      (* the engine reports the duplicate and emits BOTH; a per-key
         namespacing would have produced two identical anchors and made
         this row's law false on a corpus the engine accepts *)
      let a = Wiki_export.single_file_anchors m in
      List.length (List.sort_uniq compare a) = List.length a
      && List.mem "delta--^dup" a && List.mem "delta--^dup-2" a);
  check "A2 an ALREADY-BROKEN fragment is DISCLOSED, never invented away" (fun () ->
      Wiki_export.dead_links broken_m <> []
      && Hermes_wiki.broken_anchors broken_m <> []
      && List.mem "beta--ghost" (Wiki_export.dead_links broken_m)
      (* and it was NOT silently redirected to the page top *)
      && not (List.mem "page-beta" (Wiki_export.dead_links broken_m)));
  check "A2b a link that RESOLVED on the per-page surface still resolves" (fun () ->
      let a = Wiki_export.single_file_anchors broken_m in
      List.mem "beta--real" a
      && List.for_all
           (fun l -> List.mem l a || List.mem l (Wiki_export.dead_links broken_m))
           (Wiki_export.single_file_links broken_m));
  check "A3 an EXTERNAL href is not this document's to rewrite" (fun () ->
      contains (Wiki_export.single_file_html m) "href=\"https://example.com/x\"");
  check "A4 a QUOTE in a title cannot corrupt the JSON parse" (fun () ->
      Wiki_export.json_string "say \"hi\"" = "\"say \\\"hi\\\"\""
      && contains (Wiki_export.json m) "Gamma \\\"quoted\\\""
      && not (contains (Wiki_export.json m) "\"title\":\"Gamma \"quoted\""));
  check "A4b CONTROL BYTES are escaped, and no byte is DROPPED" (fun () ->
      Wiki_export.json_string "a\001b" = "\"a\\u0001b\""
      && Wiki_export.json_string "a\rb" = "\"a\\rb\""
      && Wiki_export.json_string "a\\b" = "\"a\\\\b\""
      && Wiki_export.json_string "\n\t" = "\"\\n\\t\"");
  check "A4c a corpus carrying a control byte still exports" (fun () ->
      let odd = Hermes_wiki.build [ ("docs/hermes/wiki/odd.md", "# Odd\n\nx\001y \"q\"\n") ] in
      contains (Wiki_export.json odd) "\\u0001" && contains (Wiki_export.json odd) "\\\"");
  check "A5 MARKUP in a title reaches the surfaces as text, never as markup" (fun () ->
      let h = Wiki_export.single_file_html m in
      let evil =
        Hermes_wiki.build [ ("docs/hermes/wiki/x.md", "# <script>alert(1)</script>\n") ]
      in
      contains h "Gamma &quot;quoted&quot;"
      (* `<script` and not `<script>`: escaping only the closing bracket
         leaves an opening tag a browser still parses, and a killer that
         looked for the full `<script>` would let that mutant live *)
      && (not (contains (Wiki_export.single_file_html evil) "<script"))
      && contains (Wiki_export.single_file_html evil) "&lt;script&gt;");
  check "A5c html_escape escapes EVERY character its grammar reserves" (fun () ->
      Wiki_export.html_escape "<a>&\"'" = "&lt;a&gt;&amp;&quot;&#39;"
      && Wiki_export.html_escape "" = ""
      && Wiki_export.html_escape "plain" = "plain");
  check "A5b a heading made ENTIRELY of markup is never rendered nameless" (fun () ->
      Wiki_export.inline_text "**" = "**"
      && Wiki_export.inline_text "" = ""
      && Wiki_export.text_headings (Wiki_export.page_text "# **\n\nbody\n") = [ (1, "**") ]);
  check "A6 an extlink inside a CODE FENCE is an example, not a use" (fun () ->
      let body = "real :issue:`1`\n```\nfenced :issue:`2`\n```\ntail :issue:`3`\n" in
      Wiki_export.extlink_uses body = [ ("issue", "1"); ("issue", "3") ]
      && contains (Wiki_export.expand_extlinks defs body) "fenced :issue:`2`"
      && occurrences (Wiki_export.expand_extlinks defs body) "<a href=" = 2);
  check "A7 TOTAL over pathological input — every surface, no raise" (fun () ->
      List.for_all
        (fun s ->
          let _ = Wiki_export.word_count s in
          let _ = Wiki_export.page_text s in
          let _ = Wiki_export.text_headings s in
          let _ = Wiki_export.inline_text s in
          let _ = Wiki_export.json_string s in
          let _ = Wiki_export.html_escape s in
          let _ = Wiki_export.expand_extlinks defs s in
          let _ = Wiki_export.extlink_uses s in
          true)
        [ ""; "\n"; "["; "[["; "]]"; "![["; "`"; ":"; "::"; ":a:"; ":a:`"; "```";
          "```\n"; "|||"; "^"; " ^ "; "%s"; "\000"; String.make 4000 '*';
          String.make 4000 '#'; "[x](" ; "[x](y" ]);
  check "A7b an UNTERMINATED extlink is text, never a raise" (fun () ->
      Wiki_export.expand_extlinks defs ":issue:`42" = ":issue:`42"
      && Wiki_export.extlink_uses ":issue:`42" = []
      && Wiki_export.expand_extlinks defs ":issue:" = ":issue:");
  check "A8 a corpus whose every page is empty is still a well-formed export" (fun () ->
      let blank =
        Hermes_wiki.build
          [ ("docs/hermes/wiki/a.md", ""); ("docs/hermes/wiki/b.md", "\n\n\n") ]
      in
      Wiki_export.dead_links blank = []
      && Wiki_export.corpus_word_count blank = 0
      && List.length (Wiki_export.single_file_anchors blank) = 2
      && Wiki_export.text_headings (Wiki_export.plain_text blank) = [])

let () =
  Printf.printf "wiki_export: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_export" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_export ]);
  exit (Wiki_suite_telemetry.exit_code self)
