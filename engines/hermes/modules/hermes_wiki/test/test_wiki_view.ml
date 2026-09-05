(* HW.5.3.1–6 — the query VIEW family, across the full functional
   envelope:

     N*  nominal      one result, six views, and the set law between them
     X*  exhaustion   a 200-row result, a 10 000-character field, many buckets
     S*  stuck        an empty result, one row, one bucket, an empty grouping
     A*  anomaly      markup in a title, a forged identifier, an absent key,
                      duplicate identifiers, a malformed query

   The headline law is DIFFERENTIAL, not an assertion of intent: one
   result set is rendered all five ways, the identifiers each view
   ACTUALLY emitted are read back out of the finished markup, and the five
   sequences are compared — first against Wiki_query.eval, which is the
   only thing that knows what the answer was, and then against each other.
   Anchoring to eval is what stops the law passing vacuously when all five
   views drop the same row. *)

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
  let n = ref 0 in
  if nn > 0 then
    for i = 0 to nh - nn do
      if String.sub hay i nn = needle then incr n
    done;
  !n

(* ------------------------------------------------------------- fixtures *)

let corpus =
  [ ("docs/hermes/zk/alpha.md",
     "---\nstatus: published\ntype: claim\n---\n# Alpha\n\nOne two three #core.\n\nSee [[beta]].\n");
    ("docs/hermes/zk/beta.md",
     "---\nstatus: draft\ntype: note\n---\n# Beta\n\nFour five #core #edge.\n\nSee [[gamma]].\n");
    ("docs/hermes/zk/gamma.md",
     "---\nstatus: published\ntype: note\n---\n# Gamma\n\nSix #edge.\n");
    ("docs/hermes/wiki/delta.md",
     "---\nstatus: published\ntype: claim\n---\n# Delta\n\nSeven eight nine ten #core.\n") ]

let model = Hermes_wiki.build corpus
let pages = model.Hermes_wiki.pages
let slug (p : Hermes_wiki.page) = p.Hermes_wiki.slug

let view src =
  match Wiki_view.of_source pages src with
  | Ok t -> t
  | Error e -> failwith ("fixture query rejected: " ^ e)

let eval_slugs src =
  match Wiki_query.parse src with
  | Ok q -> List.map slug (Wiki_query.eval pages q)
  | Error e -> failwith ("fixture query rejected: " ^ e)

let t_flat = view "from all sort slug"
let t_group = view "group by status"

(* A decimal number: a dot BETWEEN two digits. The xmlns URL contains dots
   and no decimal, so this reads the geometry rather than the namespace. *)
let is_digit c = c >= '0' && c <= '9'

let has_decimal s =
  let n = String.length s in
  let rec go i =
    i + 1 < n
    && ((s.[i] = '.' && i > 0 && is_digit s.[i - 1] && is_digit s.[i + 1]) || go (i + 1))
  in
  go 0

(* Every renderer's ids, as (view name, ids). *)
let all_ids t = List.map (fun (n, r) -> (n, Wiki_view.row_ids (r t))) Wiki_view.renderers

(* THE differential observation. Two obligations, and they are different
   obligations: the five views must agree with EACH OTHER exactly — same
   ids, same order — and their common answer must be the SAME MULTISET
   the query engine returned. Bucket order permutes eval's sequence, so
   the anchor to eval is a multiset equality; N1 pins the sequence itself
   for an ungrouped result, where no permutation is possible. *)
let agree t expected =
  let got = all_ids t in
  match got with
  | [] -> false
  | (_, first) :: _ ->
      List.for_all (fun (_, ids) -> ids = first) got
      && List.length got = List.length Wiki_view.renderers
      && List.sort compare first = List.sort compare expected

(* Hand-built pages, for the results a corpus cannot produce: an absent
   status (build defaults it to "published"), a forged identifier, a
   duplicate slug (build resolves collisions). An abstract result type
   would make these edge cases untestable, which is why it is concrete. *)
let tmpl = List.hd pages

let mk ?(status = "published") ?(ntype = "note") ?(tags = []) ~slug ~title () =
  { tmpl with
    Hermes_wiki.slug;
    title;
    tags;
    meta = { tmpl.Hermes_wiki.meta with Hermes_wiki.status; ntype } }

let mk_t ?(grouped = false) ?(source = "") buckets =
  { Wiki_view.source; grouped; buckets }

(* ------------------------------------------------------------- nominal *)

let () =
  check "N1 ANCHOR: the table emits EXACTLY the rows Wiki_query.eval returned" (fun () ->
      let expected = eval_slugs "from all sort slug" in
      expected <> [] && Wiki_view.row_ids (Wiki_view.table t_flat) = expected);
  check "N2 THE SET LAW: all five views emit the identical id sequence, = eval's" (fun () ->
      let expected = eval_slugs "from all sort slug" in
      List.length expected = 4 && agree t_flat expected);
  check "N2b the set law is not vacuous: the views do emit ids" (fun () ->
      List.for_all (fun (_, ids) -> List.length ids = 4) (all_ids t_flat));
  check "N3 HW.5.3.1 rows are DERIVED: |columns| headers and |columns| cells per row"
    (fun () ->
      let html = Wiki_view.table t_flat in
      let n = List.length Wiki_view.columns in
      count html "<th>" = n && count html "<td>" = n * 4
      && contains html "<td>Alpha</td>"
      && contains html "<td>published</td>");
  check "N3b the table states its own row count (never a silent truncation)" (fun () ->
      contains (Wiki_view.table t_flat) "4 rows"
      && contains (Wiki_view.table (view "sort slug limit 1")) "1 row</td>");
  check "N4 HW.5.3.2 the board is one COLUMN per bucket, each named" (fun () ->
      let b = Wiki_view.board t_group in
      count b "class=\"zq-col\"" = 2
      && contains b "data-bucket=\"draft\""
      && contains b "data-bucket=\"published\"");
  check "N4b an UNGROUPED board is one named column, not an unlabelled blob" (fun () ->
      let b = Wiki_view.board t_flat in
      count b "class=\"zq-col\"" = 1
      && contains b ("data-bucket=\"" ^ Wiki_view.unbucketed_label ^ "\""));
  check "N5 HW.5.3.3 the kanban is QUERY-defined: it carries the query, never a file"
    (fun () ->
      let k = Wiki_view.kanban t_group in
      contains k "data-defined-by=\"query\""
      && contains k "data-query=\"group by status\""
      && (not (contains k "data-defined-by=\"file\""))
      && not (contains k ".md"));
  check "N5b the kanban shows the SAME rows as the board — provenance is the only difference"
    (fun () ->
      Wiki_view.row_ids (Wiki_view.kanban t_group)
      = Wiki_view.row_ids (Wiki_view.board t_group));
  check "N6 HW.5.3.4 the gallery is a CARD GRID: one figure per row" (fun () ->
      let g = Wiki_view.gallery t_flat in
      count g "<figure" = 4 && count g "<figcaption>" = 4 && contains g "zq-grid");
  check "N7 HW.5.3.5 the list is COMPACT: fewer bytes per row than the table" (fun () ->
      (* stated MARGINALLY, which is what "compact rendering" means: the
         cost of one more row. A whole-document comparison is dominated by
         the table's thead and tfoot, so a list that grew per-row cells
         would still measure smaller and the claim would go unchecked. *)
      let one = mk_t [ ("", [ mk ~slug:"a" ~title:"A" () ]) ] in
      let two = mk_t [ ("", [ mk ~slug:"a" ~title:"A" (); mk ~slug:"b" ~title:"B" () ]) ] in
      let marginal r = String.length (r two) - String.length (r one) in
      marginal Wiki_view.list_view > 0
      && marginal Wiki_view.list_view < marginal Wiki_view.table
      && marginal Wiki_view.list_view < marginal Wiki_view.gallery
      && count (Wiki_view.list_view t_flat) "<li " = 4
      && String.length (Wiki_view.list_view t_flat) < String.length (Wiki_view.table t_flat)
      && String.length (Wiki_view.list_view t_group) < String.length (Wiki_view.table t_group));
  check "N8 HW.5.3.6 the chart is inline SVG whose counts COVER the result" (fun () ->
      let c = Wiki_view.chart t_group in
      contains c "<svg" && contains c "</svg>"
      && (not (contains c "<script"))
      && List.fold_left (fun a (_, v) -> a + v) 0 (Wiki_view.chart_counts t_group)
         = Wiki_view.row_count t_group
      && List.map fst (Wiki_view.chart_counts t_group) = [ "draft"; "published" ]);
  check "N9 HW.5.3.6 the chart's BYTES are pinned: integer geometry, no float drift"
    (fun () ->
      let c = Wiki_view.chart t_group in
      (* a golden pin: the whole SVG, byte for byte. Any change to the
         geometry arithmetic moves these bytes, which is the point. *)
      c
      = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 480 64\" width=\"480\" \
         height=\"64\" role=\"img\" aria-label=\"query result by bucket\" class=\"zq zq-chart\" \
         data-view=\"chart\" data-rows=\"4\"><g data-bucket=\"draft\" \
         data-count=\"1\"><title>draft: 1</title><text x=\"8\" y=\"30\" \
         font-size=\"11\">draft</text><rect x=\"160\" y=\"21\" width=\"93\" \
         height=\"12\"/><text x=\"259\" y=\"30\" font-size=\"11\">1</text></g><g \
         data-bucket=\"published\" data-count=\"3\"><title>published: 3</title><text x=\"8\" \
         y=\"50\" font-size=\"11\">published</text><rect x=\"160\" y=\"41\" width=\"280\" \
         height=\"12\"/><text x=\"446\" y=\"50\" font-size=\"11\">3</text></g></svg>"
      && not (has_decimal c));
  check "N10 renderers IS the law's scope: exactly the five set-equal views" (fun () ->
      List.map fst Wiki_view.renderers = [ "table"; "board"; "kanban"; "gallery"; "list" ]);
  check "N11 GROUPED: all five agree under group by, and the partition is covering"
    (fun () ->
      let expected = eval_slugs "group by status" in
      agree t_group expected && List.length expected = 4);
  check "N12 every view declares its row count on its root element" (fun () ->
      List.for_all
        (fun (_, r) -> contains (r t_flat) "data-rows=\"4\"")
        Wiki_view.renderers
      && contains (Wiki_view.chart t_flat) "data-rows=\"4\"")

(* --------------------------------------------------------- exhaustion *)

let big_corpus =
  List.init 200 (fun i ->
      ( Printf.sprintf "docs/hermes/zk/gen-%03d.md" i,
        Printf.sprintf "---\nstatus: %s\ntype: note\n---\n# Gen %03d\n\nbody %d\n"
          (if i mod 3 = 0 then "draft" else "published")
          i i ))

let big_pages = (Hermes_wiki.build big_corpus).Hermes_wiki.pages

let big_view src =
  match Wiki_view.of_source big_pages src with Ok t -> t | Error e -> failwith e

let big_eval src =
  match Wiki_query.parse src with
  | Ok q -> List.map slug (Wiki_query.eval big_pages q)
  | Error e -> failwith e

let () =
  check "X1 a 200-row result: all five views agree with eval, none loses a row" (fun () ->
      let t = big_view "from all sort slug" in
      let expected = big_eval "from all sort slug" in
      List.length expected = 200 && agree t expected);
  check "X2 a 10 000-character field renders IN FULL in every view, ids unaffected"
    (fun () ->
      let long = String.make 10_000 'x' in
      let t = mk_t [ ("", [ mk ~slug:"long" ~title:long () ]) ] in
      List.for_all
        (fun (_, r) ->
          let h = r t in
          contains h long && Wiki_view.row_ids h = [ "long" ])
        Wiki_view.renderers);
  check "X3 many buckets: a grouped 200-row result still agrees with eval" (fun () ->
      let t = big_view "group by status" in
      let expected = big_eval "group by status" in
      agree t expected
      && List.length (Wiki_view.chart_counts t) = 2
      && List.fold_left (fun a (_, v) -> a + v) 0 (Wiki_view.chart_counts t) = 200);
  check "X4 a bucket per row (200 columns) does not crash the board or the chart"
    (fun () ->
      let t =
        mk_t ~grouped:true
          (List.init 200 (fun i ->
               let s = Printf.sprintf "k%03d" i in
               (s, [ mk ~slug:s ~title:s () ])))
      in
      count (Wiki_view.board t) "class=\"zq-col\"" = 200
      && count (Wiki_view.chart t) "<rect" = 200
      && List.length (Wiki_view.row_ids (Wiki_view.gallery t)) = 200)

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 an EMPTY result renders an EMPTY VIEW — no crash, no placeholder row" (fun () ->
      let t = view "sort slug limit 0" in
      Wiki_view.row_count t = 0
      && List.for_all
           (fun (_, r) ->
             let h = r t in
             h <> "" && Wiki_view.row_ids h = [] && contains h "data-rows=\"0\""
             && contains h "zq-empty")
           Wiki_view.renderers
      && contains (Wiki_view.chart t) "<svg"
      && Wiki_view.row_ids (Wiki_view.chart t) = []);
  check "S1b an empty table still shows its COLUMNS — an empty view, not a missing one"
    (fun () ->
      let h = Wiki_view.table (view "sort slug limit 0") in
      count h "<th>" = List.length Wiki_view.columns
      && count h "<td>" = 0
      && contains h (Printf.sprintf "<td colspan=\"%d\">0 rows" (List.length Wiki_view.columns)));
  check "S2 ONE row: every view renders it, and only it" (fun () ->
      let t = view "sort slug limit 1" in
      agree t [ "alpha" ]);
  check "S3 ALL rows in ONE bucket: a single column holding everything" (fun () ->
      let t = view "from type:note group by type" in
      List.length t.Wiki_view.buckets = 1
      && agree t (eval_slugs "from type:note group by type")
      && count (Wiki_view.board t) "class=\"zq-col\"" = 1);
  check "S4 a GROUPED EMPTY result has no buckets, no bars, and does not divide" (fun () ->
      let t = mk_t ~grouped:true [] in
      Wiki_view.row_count t = 0
      && Wiki_view.chart_counts t = []
      && count (Wiki_view.chart t) "<rect" = 0
      && count (Wiki_view.board t) "class=\"zq-col\"" = 0
      && List.for_all (fun (_, r) -> Wiki_view.row_ids (r t) = []) Wiki_view.renderers);
  check "S5 a bucket with NO rows is still rendered — a vanished column is a lie" (fun () ->
      let t = mk_t ~grouped:true [ ("done", []); ("open", [ mk ~slug:"a" ~title:"A" () ]) ] in
      count (Wiki_view.board t) "class=\"zq-col\"" = 2
      && contains (Wiki_view.board t) "data-bucket=\"done\""
      && contains (Wiki_view.board t) "0 rows"
      && Wiki_view.chart_counts t = [ ("done", 0); ("open", 1) ])

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 MARKUP in a title is escaped in every view; the ids are unchanged" (fun () ->
      let t = mk_t [ ("", [ mk ~slug:"x" ~title:"<b>bold</b> & <script>" () ]) ] in
      List.for_all
        (fun (_, r) ->
          let h = r t in
          (not (contains h "<b>"))
          && (not (contains h "<script>"))
          && contains h "&lt;b&gt;bold&lt;/b&gt; &amp; &lt;script&gt;"
          && Wiki_view.row_ids h = [ "x" ])
        Wiki_view.renderers);
  check "A1b markup in a BUCKET KEY is escaped too — a key is author text" (fun () ->
      let t = mk_t ~grouped:true [ ("<i>k</i>", [ mk ~slug:"x" ~title:"X" () ]) ] in
      List.for_all
        (fun (_, r) -> (not (contains (r t) "<i>")) && contains (r t) "&lt;i&gt;")
        Wiki_view.renderers
      && (not (contains (Wiki_view.chart t) "<i>"))
      && contains (Wiki_view.chart t) "&lt;i&gt;");
  check "A2 a title cannot FORGE a row identifier" (fun () ->
      let t = mk_t [ ("", [ mk ~slug:"real" ~title:"z\" data-row=\"ghost" () ]) ] in
      List.for_all
        (fun (_, r) -> Wiki_view.row_ids (r t) = [ "real" ])
        Wiki_view.renderers);
  check "A2b the query text cannot forge one either (the kanban carries it)" (fun () ->
      let t =
        mk_t ~source:"q\" data-row=\"ghost" [ ("", [ mk ~slug:"real" ~title:"R" () ]) ]
      in
      Wiki_view.row_ids (Wiki_view.kanban t) = [ "real" ]);
  check "A3 an ABSENT grouping key gets a NAMED bucket, never silent omission" (fun () ->
      let ps = [ mk ~status:"" ~slug:"p1" ~title:"P1" (); mk ~status:"open" ~slug:"p2" ~title:"P2" () ] in
      match Wiki_view.of_source ps "group by status" with
      | Error _ -> false
      | Ok t ->
          List.map fst t.Wiki_view.buckets = [ ""; "open" ]
          (* NAMED is the whole claim, so it is checked against the bytes,
             not against the constant: a test written as
             ("data-bucket=\"" ^ absent_key_label ^ "\"") passes even when
             the label is blanked to "", which is the defect. *)
          && Wiki_view.absent_key_label <> ""
          && Wiki_view.unbucketed_label <> ""
          && Wiki_view.absent_key_label <> Wiki_view.unbucketed_label
          && List.for_all
               (fun (_, r) -> not (contains (r t) "data-bucket=\"\""))
               Wiki_view.renderers
          && (not (contains (Wiki_view.chart t) "data-bucket=\"\""))
          && contains (Wiki_view.board t) ("data-bucket=\"" ^ Wiki_view.absent_key_label ^ "\"")
          && List.mem (Wiki_view.absent_key_label, 1) (Wiki_view.chart_counts t)
          && agree t [ "p1"; "p2" ]);
  check "A3b an ungrouped bucket is NOT reported as an absent key" (fun () ->
      (* the two look identical in the bucket list; conflating them would
         label a whole corpus (none) *)
      Wiki_view.bucket_label t_flat "" = Wiki_view.unbucketed_label
      && Wiki_view.bucket_label t_group "" = Wiki_view.absent_key_label);
  check "A4 DUPLICATE identifiers are preserved by every view, never deduped" (fun () ->
      let t =
        mk_t [ ("", [ mk ~slug:"dup" ~title:"One" (); mk ~slug:"dup" ~title:"Two" () ]) ]
      in
      List.for_all (fun (_, r) -> Wiki_view.row_ids (r t) = [ "dup"; "dup" ]) Wiki_view.renderers);
  check "A5 of_source is TOTAL: pathological input never raises" (fun () ->
      List.for_all
        (fun q -> try match Wiki_view.of_source pages q with _ -> true with _ -> false)
        [ ""; " "; "from"; "where"; "sort"; "limit"; "\000"; String.make 3000 'x';
          "group by"; "where colour=red" ]);
  check "A5b a malformed query is the parser's NAMED error, never an empty view" (fun () ->
      match Wiki_view.of_source pages "from all wibble" with
      | Error e -> contains e "wibble"
      | Ok _ -> false);
  check "A6 an absent derived FIELD is NAMED, never a blank cell" (fun () ->
      let t = mk_t [ ("", [ mk ~ntype:"" ~slug:"x" ~title:"X" () ]) ] in
      let h = Wiki_view.table t in
      contains h ("<td>" ^ Wiki_view.absent_key_label ^ "</td>")
      && (not (contains h "<td></td>"))
      && contains (Wiki_view.gallery t) Wiki_view.absent_key_label);
  check "A7 a view is a FRAGMENT: no document, no style, no script, no external asset"
    (fun () ->
      List.for_all
        (fun (_, r) ->
          let h = r t_group in
          (not (contains h "<html"))
          && (not (contains h "<style"))
          && (not (contains h "<script"))
          && (not (contains h "http://"))
          && not (contains h "https://"))
        Wiki_view.renderers)

let () =
  Printf.printf "wiki_view: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_view" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_view ]);
  exit (Wiki_suite_telemetry.exit_code self)
