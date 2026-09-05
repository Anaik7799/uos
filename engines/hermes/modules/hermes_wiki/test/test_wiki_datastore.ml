(* HW.5.1.1 / HW.5.4.2 / HW.5.4.3 / HW.8.2.6 / HW.8.3.2 / HW.8.3.3 /
   HW.8.3.7 — the datastore, across the full functional envelope:

     N*  nominal      a base, a dataview, a version history, a comment
     X*  exhaustion   wide corpora, long histories, many slots
     S*  stuck        unparseable input, missing rows, orphaned anchors
     A*  anomaly      fenced markers, unknown kernels, non-monotone queries

   The headline law: THIS MODULE ADDS NO SECOND ENGINE. Every row it can
   show comes out of Wiki_query.eval, every fill it can produce is
   destined for HW.8.3.1's instantiate, and every anchor it can resolve
   comes out of Hermes_wiki.anchors. The checks below are therefore
   mostly DIFFERENTIALS against those three, because "same engine" is a
   measurement and not a promise.

   Its dual: a template is NOT a program. An unknown kernel is a named
   error that stops the instantiation; there is no fall-through. *)

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

(* ------------------------------------------------------------ fixtures *)

let corpus =
  [ ("docs/hermes/zk/alpha.md",
     "---\nstatus: published\ntype: claim\n---\n# Alpha\n\nOne two three #core.\n\n\
      See [[beta]].\n\nA claim worth citing ^c-1\n");
    ("docs/hermes/zk/beta.md",
     "---\nstatus: draft\ntype: note\n---\n# Beta\n\nFour five #core #edge.\n");
    ("docs/hermes/wiki/gamma.md",
     "---\nstatus: published\ntype: note\n---\n# Gamma\n\nSix #edge.\n") ]

let model = Hermes_wiki.build corpus
let pages = model.Hermes_wiki.pages
let slugs ps = List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug) ps

let engine src =
  match Wiki_query.parse src with
  | Ok q -> Wiki_query.eval pages q
  | Error e -> failwith ("fixture query is not valid zkquery: " ^ e)

let parsed src =
  match Wiki_query.parse src with Ok q -> q | Error e -> failwith e

let base_src =
  "name: recent claims\ncolumns: slug, title, status\nquery: from type:claim sort slug\n"

let the_base = match Wiki_datastore.parse_base base_src with
  | Ok b -> b
  | Error _ -> failwith "fixture base does not parse"

(* --------------------------------------------------------------- nominal *)

let () =
  check "N1 HW.5.4.2 a Base IS the engine: base_rows = Wiki_query.eval, row for row"
    (fun () ->
      (* quantified over SEVERAL queries on purpose: a base that happened
         to hard-code the fixture's answer would satisfy one of these *)
      List.for_all
        (fun q ->
          match Wiki_datastore.parse_base ("name: n\nquery: " ^ q ^ "\n") with
          | Ok b -> Wiki_datastore.base_rows pages b = engine q
          | Error _ -> false)
        [ "from all"; "from type:claim sort slug"; "from type:note sort slug desc";
          "from tag:edge"; "where status=published"; "from all limit 1";
          "where backlinks>0"; "from group:zk sort title" ]
      && Wiki_datastore.base_rows pages the_base = engine "from type:claim sort slug");
  check "N2 HW.5.4.2 the table is header-then-rows, cells in the AUTHOR's column order"
    (fun () ->
      match Wiki_datastore.base_table pages the_base with
      | [ "slug"; "title"; "status" ] :: rows ->
          rows = [ [ "alpha"; "Alpha"; "published" ] ]
      | _ -> false);
  check "N3 HW.5.4.2 every cell AGREES with the engine: where <col>=<cell> finds the page"
    (fun () ->
      let p = List.hd (engine "from type:claim") in
      List.for_all
        (fun col ->
          match Wiki_datastore.cell p col with
          | None -> false
          | Some v ->
              List.mem p.Hermes_wiki.slug (slugs (engine (Printf.sprintf "where %s=%s" col v))))
        [ "slug"; "status"; "type"; "group"; "outlinks"; "backlinks"; "degree" ]);
  check "N4 HW.5.4.3 a dataview DESUGARS to zkquery text and nothing else" (fun () ->
      Wiki_datastore.to_zkquery
        "TABLE slug, status FROM #core WHERE status = published SORT slug DESC LIMIT 2"
      = Ok "from tag:core where status=published sort slug desc limit 2");
  check "N5 HW.5.4.3 dataview_rows = the ENGINE on the desugared text (differential)"
    (fun () ->
      let src = "TABLE slug FROM #core WHERE status = published SORT slug" in
      match (Wiki_datastore.to_zkquery src, Wiki_datastore.dataview_rows pages src) with
      | Ok zq, Ok rows -> rows = engine zq && rows <> []
      | _ -> false);
  check "N6 HW.5.4.3 a TABLE block is a Base by another spelling" (fun () ->
      match Wiki_datastore.base_of_dataview ~name:"live" "TABLE slug, title FROM all" with
      | Ok b ->
          b.Wiki_datastore.columns = [ "slug"; "title" ]
          && Wiki_datastore.base_rows pages b = engine "from all"
          && Wiki_datastore.base_of_dataview ~name:"x" "TABLE words FROM all"
             = Error (Wiki_datastore.Dv_column "words")
      | Error _ -> false);
  check "N7 HW.5.1.1 the from selector is MONOTONE, and the classifier says so" (fun () ->
      Wiki_datastore.monotone (parsed "from type:claim")
      && Wiki_datastore.monotone (parsed "from tag:core where status=published")
      && Wiki_datastore.monotone_defect ~base:corpus
           ~added:[ ("docs/hermes/zk/delta.md", "# Delta\n\nSee [[alpha]].\n") ]
           (parsed "from type:claim")
         = None);
  check "N8 HW.5.1.1 the selector MENU offers only selectors the corpus answers" (fun () ->
      let s = Wiki_datastore.selectors pages in
      s = List.sort_uniq String.compare s
      && List.mem "all" s && List.mem "type:claim" s && List.mem "tag:core" s
      && List.mem "group:zk" s
      && not (List.mem "type:policy" s));
  check "N9 HW.8.2.6 lifecycle directives parse, and sort into a TOTAL order" (fun () ->
      let body =
        ".. versionadded:: 1.2 first shipped\n.. deprecated:: 1.10 use the other one\n\
         .. versionchanged:: 2.0\n"
      in
      let rs, ds = Wiki_datastore.releases body in
      ds = []
      && List.map (fun r -> Wiki_datastore.show_version r.Wiki_datastore.version) rs
         = [ "1.2"; "1.10"; "2" ]
      && Wiki_datastore.version_history body
         = [ "versionadded 1.2: first shipped"; "deprecated 1.10: use the other one";
             "versionchanged 2" ]);
  check "N10 HW.8.2.6 1.10 > 1.9 NUMERICALLY, and 1.2 = 1.2.0 by zero extension"
    (fun () ->
      let v s = match Wiki_datastore.version_of_string s with Ok v -> v | Error e -> failwith e in
      Wiki_datastore.compare_version (v "1.10") (v "1.9") > 0
      && Wiki_datastore.compare_version (v "1.2") (v "1.2.0") = 0
      && Wiki_datastore.show_version (v "1.2.0") = "1.2"
      && Wiki_datastore.show_version (v "1.2") = Wiki_datastore.show_version (v "1.2.0"));
  check "N11 HW.8.3.3 a computed slot is a NAMED KERNEL the harness runs" (fun () ->
      Wiki_datastore.fills ~row:[ ("title", " Hello World ") ]
        ~placeholders:[ "title"; "upper:title"; "slug:title"; "trim:title"; "length:title" ]
      = Ok
          [ ("length:title", "13"); ("slug:title", "hello-world"); ("title", " Hello World ");
            ("trim:title", "Hello World"); ("upper:title", " HELLO WORLD ") ]);
  check "N12 HW.8.3.3 the kernel set is CLOSED and its names round-trip" (fun () ->
      Wiki_datastore.kernels
      = [ "first_line"; "length"; "lower"; "slug"; "trim"; "upper" ]
      && List.for_all
           (fun n ->
             match Wiki_datastore.kernel_of_name n with
             | Some k -> Wiki_datastore.kernel_name k = n
             | None -> false)
           Wiki_datastore.kernels
      && Wiki_datastore.kernel_of_name "now" = None
      && Wiki_datastore.kernel_of_name "date" = None
      && Wiki_datastore.kernel_of_name "random" = None);
  check "N13 HW.8.3.2 a Base IS a database, and its rows are the engine's rows" (fun () ->
      let db = Wiki_datastore.database_of_base pages the_base in
      db.Wiki_datastore.db_columns = [ "slug"; "title"; "status" ]
      && List.map fst db.Wiki_datastore.db_rows = slugs (engine "from type:claim sort slug"));
  check "N14 HW.8.3.2 SAME MECHANISM: the database path produces fills, not text" (fun () ->
      let db = Wiki_datastore.database_of_base pages the_base in
      Wiki_datastore.database_fills db ~row:"alpha"
        ~placeholders:[ "slug"; "title"; "status"; "upper:title" ]
      = Ok
          [ ("slug", "alpha"); ("status", "published"); ("title", "Alpha");
            ("upper:title", "ALPHA") ]);
  check "N15 HW.8.3.7 a comment is a NOTE, resolved through Hermes_wiki.anchors" (fun () ->
      let m =
        Hermes_wiki.build
          (corpus
          @ [ ("docs/hermes/zk/reply.md",
               "---\ntype: note\n---\n# Reply\n\n@comments-on: alpha#^c-1\n\nI disagree.\n") ])
      in
      List.mem "^c-1" (Hermes_wiki.anchors m "alpha")
      && Wiki_datastore.comments m
         = ( [ { Wiki_datastore.comment_slug = "reply";
                 on = { Wiki_datastore.target_slug = "alpha"; target_anchor = Some "^c-1" } } ],
             [] ));
  check "N16 HW.8.3.7 a PAGE-level comment needs only that the page exists" (fun () ->
      let m =
        Hermes_wiki.build
          (corpus
          @ [ ("docs/hermes/zk/reply.md", "---\ntype: note\n---\n# R\n\n@comments-on: beta\n") ])
      in
      Wiki_datastore.thread m "beta"
      = [ { Wiki_datastore.comment_slug = "reply";
            on = { Wiki_datastore.target_slug = "beta"; target_anchor = None } } ]
      && Wiki_datastore.discussion_report m = [ "beta <- reply" ]);
  check "N17 HW.8.3.2 the fill set EXACTLY covers a template's placeholders (so instantiate is Ok)"
    (fun () ->
      (* the datastore half of the register probe: the placeholder list a
         page template declares, answered exactly — no unfilled slot, no
         unknown key — so HW.8.3.1's instantiate has nothing to report *)
      let placeholders = [ "slug"; "title"; "upper:title" ] in
      match Wiki_datastore.parse_base "name: b\ncolumns: slug, title\nquery: from type:claim\n" with
      | Error _ -> false
      | Ok b ->
          let db = Wiki_datastore.database_of_base pages b in
          Wiki_datastore.database_fills db ~row:"alpha" ~placeholders
          = Ok [ ("slug", "alpha"); ("title", "Alpha"); ("upper:title", "ALPHA") ]
          && List.map fst
               (match Wiki_datastore.database_fills db ~row:"alpha" ~placeholders with
                | Ok f -> f
                | Error _ -> [])
             = placeholders)

(* ------------------------------------------------------------ exhaustion *)

let () =
  check "X1 a WIDE corpus stays monotone and stays sorted" (fun () ->
      let many =
        List.init 60 (fun i ->
            ( Printf.sprintf "docs/hermes/zk/n%02d.md" i,
              Printf.sprintf "---\nstatus: published\ntype: note\n---\n# N%02d\n\nbody #bulk.\n" i ))
      in
      let m = Hermes_wiki.build many in
      let s = Wiki_datastore.selectors m.Hermes_wiki.pages in
      s = List.sort_uniq String.compare s
      && Wiki_datastore.monotone_defect ~base:many
           ~added:[ ("docs/hermes/zk/zz.md", "---\ntype: note\n---\n# ZZ\n") ]
           (parsed "from tag:bulk")
         = None);
  check "X2 a LONG version history is totally ordered: sorted, transitive, trichotomous"
    (fun () ->
      let vs =
        List.filter_map
          (fun s -> match Wiki_datastore.version_of_string s with Ok v -> Some v | Error _ -> None)
          [ "0"; "0.1"; "1"; "1.0"; "1.0.1"; "1.2"; "1.9"; "1.10"; "2"; "2.0.0"; "10.0" ]
      in
      let cmp = Wiki_datastore.compare_version in
      List.for_all (fun a -> cmp a a = 0) vs
      && List.for_all
           (fun a -> List.for_all (fun b -> cmp a b = -cmp b a || (cmp a b = 0 && cmp b a = 0)) vs)
           vs
      && List.for_all
           (fun a ->
             List.for_all
               (fun b ->
                 List.for_all
                   (fun c -> not (cmp a b <= 0 && cmp b c <= 0 && cmp a c > 0))
                   vs)
               vs)
           vs);
  check "X3 MANY slots: every placeholder is classified, none silently dropped" (fun () ->
      let row = List.init 30 (fun i -> (Printf.sprintf "c%02d" i, string_of_int i)) in
      let ph = List.init 30 (fun i -> Printf.sprintf "upper:c%02d" i) in
      match Wiki_datastore.fills ~row ~placeholders:ph with
      | Ok f ->
          List.length f = 60
          && List.map fst f = List.sort String.compare (List.map fst f)
          && List.assoc_opt "upper:c07" f = Some "7"
      | Error _ -> false);
  check "X4 many fences: sources, JS blocks and defects are all counted" (fun () ->
      let body =
        String.concat ""
          (List.init 8 (fun i ->
               if i mod 2 = 0 then "```dataview\nLIST FROM all\n```\n"
               else "```dataviewjs\ndv.pages()\n```\n"))
      in
      List.length (Wiki_datastore.dataview_sources body) = 4
      && List.length (Wiki_datastore.dataview_js body) = 4
      && List.length (Wiki_datastore.dataview_defects body) = 4)

(* ----------------------------------------------------------------- stuck *)

let () =
  check "S1 an unparseable base is a NAMED error list, never a base that shows nothing"
    (fun () ->
      match Wiki_datastore.parse_base "colums: slug\nquery: from all\n" with
      | Error es ->
          List.mem (Wiki_datastore.Base_unknown_key "colums") es
          && List.mem (Wiki_datastore.Base_missing "name") es
      | Ok _ -> false);
  check "S2 the base carries the ENGINE's error VERBATIM, not a paraphrase" (fun () ->
      let engine_msg = match Wiki_query.parse "wibble" with Error e -> e | Ok _ -> "" in
      match Wiki_datastore.parse_base "name: n\nquery: wibble\n" with
      | Error es -> engine_msg <> "" && List.mem (Wiki_datastore.Base_query engine_msg) es
      | Ok _ -> false);
  check "S3 an unknown COLUMN is refused; `tag` and `words` are deliberately not columns"
    (fun () ->
      (match Wiki_datastore.parse_base "name: n\ncolumns: words\nquery: from all\n" with
       | Error es -> List.mem (Wiki_datastore.Base_unknown_column "words") es
       | Ok _ -> false)
      && (not (List.mem "tag" Wiki_datastore.column_names))
      && (not (List.mem "words" Wiki_datastore.column_names))
      && Wiki_datastore.cell (List.hd pages) "tag" = None
      && Wiki_datastore.cell (List.hd pages) "words" = None);
  check "S4 every dataview malformation is a DISTINCT named error, never an empty result"
    (fun () ->
      Wiki_datastore.to_zkquery "" = Error Wiki_datastore.Dv_empty
      && Wiki_datastore.to_zkquery "table FROM all" = Error (Wiki_datastore.Dv_head "table")
      && Wiki_datastore.to_zkquery "TABLE FROM bogus" = Error (Wiki_datastore.Dv_from "bogus")
      && Wiki_datastore.to_zkquery "TABLE FROM all WHERE status published"
         = Error (Wiki_datastore.Dv_where "status published")
      && Wiki_datastore.to_zkquery "TABLE FROM all SORT slug SIDEWAYS"
         = Error (Wiki_datastore.Dv_sort "slug SIDEWAYS")
      && Wiki_datastore.to_zkquery "TABLE FROM all LIMIT x" = Error (Wiki_datastore.Dv_limit "x")
      && Wiki_datastore.to_zkquery "TABLE FROM #a FROM #b"
         = Error (Wiki_datastore.Dv_from "duplicate FROM"));
  check "S5 a dataview whose desugaring the ENGINE rejects reports the engine's words"
    (fun () ->
      match Wiki_datastore.dataview_rows pages "TABLE FROM all WHERE nosuch = 1" with
      | Error (Wiki_datastore.Dv_query e) -> contains e "zkquery" && contains e "nosuch"
      | Error _ | Ok _ -> false);
  check "S6 an unorderable version is a NAMED diagnostic and is NOT admitted" (fun () ->
      let bad = [ ""; "v3"; "1.2-rc1"; "1..2"; "1."; "one" ] in
      List.for_all
        (fun s -> match Wiki_datastore.version_of_string s with Error _ -> true | Ok _ -> false)
        bad
      && (let rs, ds = Wiki_datastore.releases ".. versionadded:: v3\n.. versionchanged::\n" in
          rs = []
          && List.length ds = 2
          && List.exists (fun d -> contains d "no version") ds
          && List.exists (fun d -> contains d "not a dotted numeric version") ds));
  check "S7 an unknown database ROW and an off-schema CELL are named before any kernel runs"
    (fun () ->
      let db = Wiki_datastore.database_of_base pages the_base in
      Wiki_datastore.database_fills db ~row:"nope" ~placeholders:[ "slug" ]
      = Error [ Wiki_datastore.Unknown_row "nope" ]
      && Wiki_datastore.database_fills
           { Wiki_datastore.db_name = "d"; db_columns = [ "slug" ];
             db_rows = [ ("r", [ ("slug", "r"); ("bogus", "x") ]) ] }
           ~row:"r" ~placeholders:[ "frobnicate:slug" ]
         = Error [ Wiki_datastore.Off_schema "bogus" ]);
  check "S8 HW.8.3.7 an ORPHANED comment is a named diagnostic, in TWO distinct flavours"
    (fun () ->
      let m =
        Hermes_wiki.build
          (corpus
          @ [ ("docs/hermes/zk/r1.md", "---\ntype: note\n---\n# R1\n\n@comments-on: ghost\n");
              ("docs/hermes/zk/r2.md", "---\ntype: note\n---\n# R2\n\n@comments-on: alpha#^nope\n");
              ("docs/hermes/zk/r3.md", "---\ntype: note\n---\n# R3\n\n@comments-on:\n") ])
      in
      let cs, ds = Wiki_datastore.comments m in
      cs = []
      && List.length ds = 3
      && ds = List.sort compare ds
      && List.mem (Wiki_datastore.Missing_page ("r1", "ghost")) ds
      && List.mem (Wiki_datastore.Missing_anchor ("r2", "alpha", "^nope")) ds
      && List.mem (Wiki_datastore.Empty_target "r3") ds
      && contains
           (Wiki_datastore.show_comment_defect (Wiki_datastore.Missing_page ("r1", "ghost")))
           "ORPHANED"
      && contains
           (Wiki_datastore.show_comment_defect
              (Wiki_datastore.Missing_anchor ("r2", "alpha", "^nope")))
           "emits no anchor")

(* --------------------------------------------------------------- anomaly *)

let () =
  check "A1 THE KILLER: an unknown kernel is a NAMED ERROR, never evaluated, never a fall-through"
    (fun () ->
      Wiki_datastore.fills ~row:[ ("title", "x") ] ~placeholders:[ "frobnicate:title" ]
      = Error [ Wiki_datastore.Unknown_kernel "frobnicate" ]
      && Wiki_datastore.classify_slot "exec:rm -rf"
         = Error (Wiki_datastore.Unknown_kernel "exec")
      && Wiki_datastore.classify_slot "a:b:c" = Error (Wiki_datastore.Unknown_kernel "a")
      && Wiki_datastore.classify_slot "upper:" = Error (Wiki_datastore.Empty_argument "upper:")
      && contains
           (Wiki_datastore.show_template_error (Wiki_datastore.Unknown_kernel "frobnicate"))
           "nothing is evaluated");
  check "A2 on an unknown kernel NO fills are produced at all — never a partial stamp"
    (fun () ->
      match
        Wiki_datastore.fills ~row:[ ("title", "x") ]
          ~placeholders:[ "title"; "upper:title"; "frobnicate:title" ]
      with
      | Error es -> es = [ Wiki_datastore.Unknown_kernel "frobnicate" ]
      | Ok _ -> false);
  check "A3 a kernel ARGUMENT is DATA: template syntax in a cell is never re-expanded"
    (fun () ->
      Wiki_datastore.fills ~row:[ ("t", "{{secret}}") ] ~placeholders:[ "upper:t" ]
      = Ok [ ("t", "{{secret}}"); ("upper:t", "{{SECRET}}") ]);
  check "A4 a MISSING column omits the fill, so HW.8.3.1 reports Unfilled by its slot name"
    (fun () ->
      Wiki_datastore.fills ~row:[] ~placeholders:[ "upper:title" ] = Ok []
      && Wiki_datastore.fills ~row:[] ~placeholders:[ "title" ] = Ok []);
  check "A5 a row cell with NO slot is passed through, so HW.8.3.1 reports Unknown_placeholder"
    (fun () ->
      Wiki_datastore.fills ~row:[ ("orphaned", "v") ] ~placeholders:[]
      = Ok [ ("orphaned", "v") ]);
  check "A6 HW.5.4.3 NO JS: a dataviewjs fence is never a source, and the refusal is DISCLOSED"
    (fun () ->
      let body = "```dataviewjs\ndv.pages(\"#core\").forEach(p => p.rm())\n```\n" in
      Wiki_datastore.dataview_sources body = []
      && Wiki_datastore.dataview_js body = [ "dv.pages(\"#core\").forEach(p => p.rm())" ]
      && (match Wiki_datastore.dataview_defects body with
         | [ d ] -> contains d "REFUSED" && contains d "never evaluated"
         | _ -> false));
  check "A7 the tagged fence walk AGREES with Wiki_query.fences on every body" (fun () ->
      List.for_all
        (fun body -> Wiki_datastore.fences ~tag:"zkquery" body = Wiki_query.fences body)
        [ "";
          "no fences here\n";
          "```zkquery\nfrom all\n```\n";
          "```zkquery\nfrom all\n```\ntext\n```zkquery\nfrom tag:x\n```\n";
          "```dataview\nLIST\n```\n```zkquery\nfrom all\n```\n";
          "```zkquery\nunterminated\n";
          "```\nplain fence\n```\n" ]);
  check "A8 CODE IS NOT PROSE: a fenced lifecycle directive is an EXAMPLE" (fun () ->
      let body = "```\n.. versionadded:: 9.9 not real\n```\n.. versionadded:: 1.0 real\n" in
      let rs, ds = Wiki_datastore.releases body in
      ds = []
      && List.map (fun r -> r.Wiki_datastore.version_text) rs = [ "1.0" ]);
  check "A9 CODE IS NOT PROSE: a fenced or indented @comments-on is an EXAMPLE" (fun () ->
      Wiki_datastore.comment_markers "```\n@comments-on: alpha\n```\n" = []
      && Wiki_datastore.comment_markers "  @comments-on: alpha\n" = []
      && Wiki_datastore.comment_markers "@comments-on: alpha#^c-1\n" = [ "alpha#^c-1" ]);
  check "A10 HW.8.3.7 TWO markers is an ambiguous subject: named, and NO comment" (fun () ->
      let m =
        Hermes_wiki.build
          (corpus
          @ [ ("docs/hermes/zk/r.md",
               "---\ntype: note\n---\n# R\n\n@comments-on: alpha\n@comments-on: beta\n") ])
      in
      Wiki_datastore.comments m = ([], [ Wiki_datastore.Duplicate_marker "r" ]));
  check "A11 HW.5.1.1 the ORPHAN report is NOT monotone, and the checker PROVES it" (fun () ->
      let q = parsed "where backlinks<1" in
      let added = [ ("docs/hermes/zk/delta.md", "---\ntype: note\n---\n# D\n\nSee [[alpha]].\n") ] in
      (not (Wiki_datastore.monotone q))
      && (match Wiki_datastore.monotone_defect ~base:corpus ~added q with
         | Some msg -> contains msg "alpha" && contains msg "NOT monotone"
         | None -> false));
  check "A12 HW.5.1.1 `limit` is a PREFIX, so it too is excluded from the claim" (fun () ->
      let q = parsed "from all sort slug limit 1" in
      (not (Wiki_datastore.monotone q))
      && Wiki_datastore.monotone (parsed "from all sort slug")
      && (match
            Wiki_datastore.monotone_defect ~base:corpus
              ~added:[ ("docs/hermes/zk/aaa.md", "---\ntype: note\n---\n# A\n") ]
              q
          with
         | Some msg -> contains msg "alpha"
         | None -> false));
  check "A13 corpus-dependent fields are exactly the neighbourhood ones" (fun () ->
      Wiki_datastore.corpus_dependent_fields = [ "backlinks"; "degree" ]
      && List.for_all
           (fun f -> List.mem f Wiki_query.int_fields)
           Wiki_datastore.corpus_dependent_fields
      && Wiki_datastore.monotone (parsed "where words>1")
      && Wiki_datastore.monotone (parsed "where outlinks>0")
      && not (Wiki_datastore.monotone (parsed "where degree>0")));
  check "A14 TOTAL: no input raises — every malformed surface has a value" (fun () ->
      let ok f = try ignore (f ()) ; true with _ -> false in
      ok (fun () -> Wiki_datastore.parse_base "")
      && ok (fun () -> Wiki_datastore.parse_base ":::\n")
      && ok (fun () -> Wiki_datastore.to_zkquery "TABLE FROM")
      && ok (fun () -> Wiki_datastore.to_zkquery "\n\n\t")
      && ok (fun () -> Wiki_datastore.version_of_string "999999999999999999999999")
      && ok (fun () -> Wiki_datastore.releases ".. ::\n.. versionadded::\n..")
      && ok (fun () -> Wiki_datastore.comment_markers "@comments-on:")
      && ok (fun () -> Wiki_datastore.classify_slot ":")
      && ok (fun () -> Wiki_datastore.fills ~row:[] ~placeholders:[ ""; ":"; "::" ])
      && ok (fun () -> Wiki_datastore.comments (Hermes_wiki.build [])));
  check "A15 DETERMINISM: every emitted list is sorted, and two runs agree" (fun () ->
      let body =
        ".. versionchanged:: 2.0 b\n.. versionadded:: 1.0 a\n.. deprecated:: 1.0 c\n"
      in
      Wiki_datastore.releases body = Wiki_datastore.releases body
      && (let rs, _ = Wiki_datastore.releases body in
          rs = List.sort Wiki_datastore.compare_release rs)
      && Wiki_datastore.selectors pages = Wiki_datastore.selectors (List.rev pages));
  check "A16 an empty corpus yields an empty answer, and says nothing else" (fun () ->
      let m = Hermes_wiki.build [] in
      Wiki_datastore.comments m = ([], [])
      && Wiki_datastore.selectors m.Hermes_wiki.pages = [ "all" ]
      && Wiki_datastore.base_rows m.Hermes_wiki.pages the_base = []
      && Wiki_datastore.base_table m.Hermes_wiki.pages the_base
         = [ [ "slug"; "title"; "status" ] ])

let () =
  Printf.printf "wiki_datastore: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_datastore" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_datastore ]);
  exit (Wiki_suite_telemetry.exit_code self)
