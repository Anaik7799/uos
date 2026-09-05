(* HW.5.1.* / HW.5.2.* — zkquery. Mirrored from zigvm's docs_wiki.ml
   §2253-2485 (R14), extended with `group by` (HW.5.1.5), which is Missing
   in BOTH comparators and is the natural shape of the grammar.

   The laws are the acceptance criterion (plan §8.0.5):
     total       every input yields Ok or a NAMED Error; never raises,
                 and NEVER a silently empty result
     sound       every returned row satisfies every condition
     commute     where a and b  ==  where b and a
     monotone    limit n is a PREFIX of limit m for m >= n
     determinism sort is a total order via the slug tiebreak
     partition   group by is disjoint and covering *)

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

let run q =
  match Wiki_query.parse q with
  | Ok query -> Ok (Wiki_query.eval pages query)
  | Error e -> Error e

let slugs q =
  match run q with Ok rows -> List.map (fun p -> p.Hermes_wiki.slug) rows | Error _ -> []

let ok q = match run q with Ok _ -> true | Error _ -> false
let rejects q = match Wiki_query.parse q with Error _ -> true | Ok _ -> false

(* ------------------------------------------------------------- totality *)

let () = check "HW.5.2.1 parse is total: no input raises" (fun () ->
    List.for_all
      (fun q -> (try ignore (Wiki_query.parse q); true with _ -> false))
      [ ""; " "; "from"; "where"; "sort"; "limit"; "from all where"; "\000";
        String.make 3000 'x'; "where ="; "where =x"; "where x="; "limit -1" ])

let () = check "HW.5.2.1 an empty query selects everything" (fun () ->
    List.length (slugs "") = 4)

let () = check "HW.5.2.1 an unknown token is a NAMED error, not an empty result" (fun () ->
    match Wiki_query.parse "from all wibble" with
    | Error e ->
        let has needle =
          let n = String.length needle and t = String.length e in
          let rec go i = i + n <= t && (String.sub e i n = needle || go (i + 1)) in
          go 0
        in
        has "wibble"
    | Ok _ -> false)

let () = check "HW.5.2.1 an unknown field is rejected by name" (fun () ->
    rejects "where colour=red")

let () = check "HW.5.2.1 an unknown sort key is rejected" (fun () -> rejects "sort wibble")

let () = check "HW.5.2.1 a bad from-selector is rejected" (fun () ->
    rejects "from wibble" && rejects "from type:" && rejects "from :x")

let () = check "HW.5.2.1 incomplete clauses are rejected, not defaulted" (fun () ->
    rejects "from" && rejects "sort" && rejects "limit" && rejects "where")

(* ------------------------------------- the type errors that matter most *)

let () = check "HW.5.1.2 a numeric field with != is a NAMED error, never empty" (fun () ->
    match Wiki_query.parse "where words!=3" with
    | Error e ->
        let has needle =
          let n = String.length needle and t = String.length e in
          let rec go i = i + n <= t && (String.sub e i n = needle || go (i + 1)) in
          go 0
        in
        has "words" && has "numeric"
    | Ok _ -> false)

let () = check "HW.5.1.2 a numeric field given a non-number is rejected" (fun () ->
    rejects "where words=many")

let () = check "HW.5.1.2 a string field with an ordering operator is rejected" (fun () ->
    rejects "where status>draft")

let () = check "HW.5.1.2 a bad limit is rejected" (fun () ->
    rejects "limit x" && rejects "limit -1")

(* --------------------------------------------------------------- from *)

let () = check "HW.5.1.1 from all selects the whole corpus" (fun () ->
    List.length (slugs "from all") = 4)

let () = check "HW.5.1.1 from type:T selects by discourse type" (fun () ->
    List.sort compare (slugs "from type:claim") = [ "alpha"; "delta" ])

let () = check "HW.5.1.1 from group:G selects by group" (fun () ->
    slugs "from group:wiki" = [ "delta" ])

let () = check "HW.5.1.1 from tag:T selects by tag" (fun () ->
    List.sort compare (slugs "from tag:edge") = [ "beta"; "gamma" ])

(* -------------------------------------------------------------- where *)

let () = check "HW.5.1.2 where filters on a string field" (fun () ->
    List.sort compare (slugs "where status=published") = [ "alpha"; "delta"; "gamma" ])

let () = check "HW.5.1.2 where != negates" (fun () ->
    slugs "where status!=published" = [ "beta" ])

let () = check "HW.5.1.2 where conditions combine with and" (fun () ->
    slugs "where status=published and type=claim" |> List.sort compare = [ "alpha"; "delta" ])

let () = check "HW.5.1.2 numeric comparators work" (fun () ->
    ok "where words>2" && ok "where words>=2" && ok "where words<99" && ok "where words<=99"
    && List.length (slugs "where words<99") = 4)

let () = check "LAW sound: every row satisfies every condition" (fun () ->
    List.for_all
      (fun p -> p.Hermes_wiki.meta.Hermes_wiki.status = "published")
      (match run "where status=published" with Ok r -> r | Error _ -> []))

let () = check "LAW commute: where a and b == where b and a" (fun () ->
    slugs "where status=published and type=claim"
    = slugs "where type=claim and status=published")

(* --------------------------------------------------------------- sort *)

let () = check "HW.5.1.3 sort by slug, ascending by default" (fun () ->
    slugs "sort slug" = [ "alpha"; "beta"; "delta"; "gamma" ])

let () = check "HW.5.1.3 sort desc reverses" (fun () ->
    slugs "sort slug desc" = [ "gamma"; "delta"; "beta"; "alpha" ])

let () = check "HW.5.1.3 sort by a numeric key" (fun () -> ok "sort words")

let () = check "LAW determinism: within a tie group the order is slug-ascending" (fun () ->
    (* stated structurally rather than as a literal expectation: for every
       adjacent pair whose SORT KEY is equal, the slugs must ascend. That is
       what makes the order total, and therefore the result pinnable. *)
    match run "sort outlinks" with
    | Error _ -> false
    | Ok rows ->
        let key (p : Hermes_wiki.page) = List.length p.Hermes_wiki.outlinks in
        let rec ordered = function
          | a :: (b :: _ as rest) ->
              (key a < key b || (key a = key b && a.Hermes_wiki.slug <= b.Hermes_wiki.slug))
              && ordered rest
          | _ -> true
        in
        List.length rows = 4 && ordered rows)

let () = check "LAW determinism: repeated evaluation is identical" (fun () ->
    slugs "sort outlinks" = slugs "sort outlinks"
    && slugs "from type:note sort title" = slugs "from type:note sort title")

let () = check "sort rejects a field that is not a sort key" (fun () ->
    (* `status` is a filter field but NOT a sort key; offering it would be
       a silently empty result, which the totality law forbids *)
    rejects "sort status")

(* -------------------------------------------------------------- limit *)

let () = check "HW.5.1.4 limit bounds the result" (fun () ->
    List.length (slugs "sort slug limit 2") = 2)

let () = check "LAW monotone: limit n is a PREFIX of limit m for m >= n" (fun () ->
    let two = slugs "sort slug limit 2" and four = slugs "sort slug limit 4" in
    List.filteri (fun i _ -> i < 2) four = two)

let () = check "HW.5.1.4 limit 0 is empty, not everything" (fun () ->
    slugs "sort slug limit 0" = [])

(* ----------------------------------------------------------- group by *)

let () = check "HW.5.1.5 group by partitions: disjoint and covering" (fun () ->
    match Wiki_query.parse "group by status" with
    | Error _ -> false
    | Ok q ->
        let groups = Wiki_query.group pages q in
        let all = List.concat_map snd groups in
        List.length all = List.length pages
        && List.length (List.sort_uniq compare (List.map (fun p -> p.Hermes_wiki.slug) all))
           = List.length pages)

let () = check "HW.5.1.5 group by yields the expected buckets" (fun () ->
    match Wiki_query.parse "group by status" with
    | Error _ -> false
    | Ok q -> List.map fst (Wiki_query.group pages q) = [ "draft"; "published" ])

let () = check "HW.5.1.5 group by composes with where" (fun () ->
    match Wiki_query.parse "where type=claim group by status" with
    | Error _ -> false
    | Ok q ->
        let groups = Wiki_query.group pages q in
        List.map fst groups = [ "published" ]
        && List.length (List.concat_map snd groups) = 2)

let () = check "HW.5.1.5 an unknown group key is rejected" (fun () ->
    rejects "group by wibble" && rejects "group by" && rejects "group")

let () = check "HW.5.1.5 groups are ordered deterministically" (fun () ->
    match Wiki_query.parse "group by type" with
    | Error _ -> false
    | Ok q ->
        let a = List.map fst (Wiki_query.group pages q) in
        let b = List.map fst (Wiki_query.group pages q) in
        a = b && a = List.sort compare a)

(* ------------------------------------------------------------- fences *)

let () = check "HW.5.4.1 a zkquery fence is extracted from a note" (fun () ->
    Wiki_query.fences "text\n\n```zkquery\nfrom type:claim\n```\n\nmore\n"
    = [ "from type:claim" ])

let () = check "HW.5.4.1 an ordinary fence is NOT a query" (fun () ->
    Wiki_query.fences "```\nfrom type:claim\n```\n" = []
    && Wiki_query.fences "```ocaml\nlet x = 1\n```\n" = [])

let () = check "HW.5.4.1 several fences are extracted in order" (fun () ->
    Wiki_query.fences "```zkquery\na\n```\n\n```zkquery\nb\n```\n" = [ "a"; "b" ])

(* ---------------------------------------------------- meta-falsification *)

let () = check "meta-falsification: the soundness law can FAIL" (fun () ->
    (* if eval ignored conditions, this would return all four *)
    List.length (slugs "where status=draft") = 1)

let () = check "meta-falsification: rejection is not vacuous" (fun () ->
    (* a well-formed query must be ACCEPTED, else 'rejects' proves nothing *)
    ok "from type:claim where words>1 and status=published sort words desc limit 3")

let () =
  Printf.printf "wiki_query: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_query" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_query ]);
  exit (Wiki_suite_telemetry.exit_code self)
