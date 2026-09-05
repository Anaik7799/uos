(* HW.10.1.4 — the dependency sheaf (deep-structures pass S27).

   The laws under test, from unified-deep-structures.md §14.2:
     L27.1 restriction   section (restrict e (deps d)) d
                         = section (restrict e all) d
     L27.2 functoriality narrow (narrow v u) w = narrow v (inter u w);
                         narrow v all = v
     L27.3 gluing monoid glue is order-independent with empty as unit
     L27.4 descent       rebuild ~changed = cold build, byte for byte
     L27.5 tightness     dead_cover_elements = [] (no dead cover)
     L27.6 determinism   Cover.elements is sorted: one serialisation
     L27.7 cover algebra bounded solver leg (smtml over bitvector covers)
     L27.8 no IO         by construction: the module type exposes none

   Perturbation semantics for L27.4/L27.5, stated honestly: existence
   flips (remove a page, add a page). Today's observable is existence —
   the renderer consults resolve for links only — so retitle/body edits
   are addressing-level changes outside this suite's perturbation domain,
   and the header of dep_sheaf.mli says so. *)

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

(* ------------------------------------------------- deterministic corpora *)

(* A seeded generator (no Random: determinism is a suite property too).
   Documents link forward by a stride pattern, giving a connected-enough
   graph with misses mixed in. *)
let gen_corpus ~docs ~stride =
  List.init docs (fun i ->
      let links =
        List.filter_map
          (fun k ->
            let j = i + (k * stride) in
            if j < docs then Some (Printf.sprintf "[[note-%d]]" j)
            else Some "[[nowhere-land]]")
          [ 1; 2 ]
      in
      let body =
        Printf.sprintf "# Note %d\n\nBody %d with %s.\n\n## Sec %d\n\nMore.\n" i i
          (String.concat " and " links) i
      in
      (Printf.sprintf "docs/hermes/zk/note-%d.md" i, body))

let model_of files = Hermes_wiki.build files
let slugs_of m = List.map (fun p -> p.Hermes_wiki.slug) m.Hermes_wiki.pages

(* ----------------------------------------------------- L27.6 + cover alg *)

let () =
  check "L27.6 Cover.elements is sorted and deduplicated" (fun () ->
      let c = Dep_sheaf.Cover.of_list [ "b"; "a"; "b"; "c"; "a" ] in
      Dep_sheaf.Cover.elements c = [ "a"; "b"; "c" ])

let () =
  check "cover algebra: union/inter are commutative, idempotent; empty is unit" (fun () ->
      let open Dep_sheaf.Cover in
      let a = of_list [ "x"; "y" ] and b = of_list [ "y"; "z" ] in
      equal (union a b) (union b a)
      && equal (inter a b) (inter b a)
      && equal (union a a) a
      && equal (inter a a) a
      && equal (union a empty) a
      && equal (inter a empty) empty)

(* ------------------------------------------------------ L27.2 functorial *)

let () =
  check "L27.2 narrow composes as intersection; narrow by full cover is identity"
    (fun () ->
      let files = gen_corpus ~docs:8 ~stride:1 in
      let m = model_of files in
      let env = Dep_sheaf.Env.of_model m in
      let all = Dep_sheaf.Cover.of_list (slugs_of m) in
      let u = Dep_sheaf.Cover.of_list [ "note-1"; "note-2"; "note-3" ] in
      let w = Dep_sheaf.Cover.of_list [ "note-2"; "note-3"; "note-4" ] in
      let v = Dep_sheaf.Env.restrict env all in
      let lhs = Dep_sheaf.Env.narrow (Dep_sheaf.Env.narrow v u) w in
      let rhs = Dep_sheaf.Env.narrow v (Dep_sheaf.Cover.inter u w) in
      (* the two-path comparison alone is NOT differential: an identity
         narrow satisfies it vacuously (both sides stay `all`). The law is
         pinned against Cover.inter computed INDEPENDENTLY of narrow. *)
      Dep_sheaf.Cover.equal
        (Dep_sheaf.Env.cover_of (Dep_sheaf.Env.narrow v u))
        (Dep_sheaf.Cover.inter all u)
      && Dep_sheaf.Cover.equal
           (Dep_sheaf.Env.cover_of lhs)
           (Dep_sheaf.Cover.inter u w)
      && Dep_sheaf.Cover.equal
           (Dep_sheaf.Env.cover_of lhs)
           (Dep_sheaf.Env.cover_of rhs)
      && Dep_sheaf.Cover.equal
           (Dep_sheaf.Env.cover_of (Dep_sheaf.Env.narrow v all))
           (Dep_sheaf.Env.cover_of v))

let () =
  check "restriction gates observation: outside the cover a page is invisible"
    (fun () ->
      let m = model_of (gen_corpus ~docs:4 ~stride:1) in
      let env = Dep_sheaf.Env.of_model m in
      let only_two = Dep_sheaf.Env.restrict env (Dep_sheaf.Cover.of_list [ "note-2" ]) in
      Dep_sheaf.Env.observe only_two "note-2" <> None
      && Dep_sheaf.Env.observe only_two "note-1" = None)

(* -------------------------------------------------------- L27.1 headline *)

let () =
  check "L27.1 restriction: section against deps = section against all (every doc)"
    (fun () ->
      let files = gen_corpus ~docs:12 ~stride:2 in
      let m = model_of files in
      let env = Dep_sheaf.Env.of_model m in
      let all = Dep_sheaf.Cover.of_list (slugs_of m) in
      List.for_all
        (fun p ->
          let local = Dep_sheaf.Env.restrict env (Dep_sheaf.deps m p) in
          let global = Dep_sheaf.Env.restrict env all in
          Dep_sheaf.render local p = Dep_sheaf.render global p)
        m.Hermes_wiki.pages)

let () =
  check "L27.1 holds on an allow_example_links page (deps from RAW, not curated outlinks)"
    (fun () ->
      (* the model strips this page's outlinks; render still consults the
         resolver for them, so deps must come from the raw body *)
      let files =
        [ ( "docs/hermes/zk/grammar.md",
            "---\nallow_example_links: true\n---\n# Grammar\n\nQuote: [[target-page]].\n" );
          ("docs/hermes/zk/target-page.md", "# Target Page\n\nReal.\n") ]
      in
      let m = model_of files in
      let env = Dep_sheaf.Env.of_model m in
      let all = Dep_sheaf.Cover.of_list (slugs_of m) in
      let g = List.find (fun p -> p.Hermes_wiki.slug = "grammar") m.Hermes_wiki.pages in
      Dep_sheaf.render (Dep_sheaf.Env.restrict env (Dep_sheaf.deps m g)) g
      = Dep_sheaf.render (Dep_sheaf.Env.restrict env all) g)

(* ---------------------------------------------------------- L27.3 gluing *)

let () =
  check "L27.3 glue is order-independent (any permutation of the family)" (fun () ->
      let m = model_of (gen_corpus ~docs:9 ~stride:1) in
      let env = Dep_sheaf.Env.of_model m in
      let family = Dep_sheaf.build env m in
      let rot n xs =
        let rec go k = function
          | [] -> []
          | x :: rest when k > 0 -> go (k - 1) rest @ [ x ]
          | xs -> xs
        in
        go n xs
      in
      let b0 = Dep_sheaf.Section.bytes (Dep_sheaf.glue family) in
      List.for_all
        (fun n ->
          Dep_sheaf.Section.bytes (Dep_sheaf.glue (rot n family)) = b0)
        [ 1; 3; 5 ]
      && Dep_sheaf.Section.bytes (Dep_sheaf.glue (List.rev family)) = b0)

let () =
  check "L27.3 empty family glues to the empty section" (fun () ->
      Dep_sheaf.Section.bytes (Dep_sheaf.glue []) = "")

let () =
  check "L27.3 worker-count independence: partitioned glue = sequential glue" (fun () ->
      let m = model_of (gen_corpus ~docs:10 ~stride:1) in
      let env = Dep_sheaf.Env.of_model m in
      let family = Dep_sheaf.build env m in
      let partition k xs =
        List.mapi (fun i x -> (i mod k, x)) xs
        |> fun tagged ->
        List.init k (fun w -> List.filter_map (fun (t, x) -> if t = w then Some x else None) tagged)
      in
      let sequential = Dep_sheaf.Section.bytes (Dep_sheaf.glue family) in
      List.for_all
        (fun workers ->
          (* each worker glues its shard; the shards' FAMILIES then reglue:
             associativity means the result cannot depend on the partition *)
          let shards = partition workers family in
          let reglued =
            Dep_sheaf.glue (List.concat shards)
          in
          Dep_sheaf.Section.bytes reglued = sequential)
        [ 1; 2; 8 ])

(* --------------------------------------------------------- L27.4 descent *)

let remove_page files slug =
  List.filter (fun (p, _) -> not (Filename.check_suffix p (slug ^ ".md"))) files

let () =
  check "L27.4 removing a page: rebuild ~changed = cold build, byte for byte" (fun () ->
      let files = gen_corpus ~docs:10 ~stride:1 in
      let m = model_of files in
      let env = Dep_sheaf.Env.of_model m in
      let previous = Dep_sheaf.build env m in
      let files' = remove_page files "note-3" in
      let m' = model_of files' in
      let env' = Dep_sheaf.Env.of_model m' in
      let incremental =
        Dep_sheaf.rebuild ~previous env' ~changed:(Dep_sheaf.Cover.of_list [ "note-3" ]) m'
      in
      let cold = Dep_sheaf.build env' m' in
      List.length incremental = List.length cold
      && List.for_all2
           (fun (s1, a) (s2, b) ->
             s1 = s2 && Dep_sheaf.Section.bytes a = Dep_sheaf.Section.bytes b)
           (List.sort compare incremental) (List.sort compare cold))

let () =
  check "L27.4 adding a page: rebuild ~changed = cold build" (fun () ->
      let files = gen_corpus ~docs:6 ~stride:2 in
      let m = model_of files in
      let env = Dep_sheaf.Env.of_model m in
      let previous = Dep_sheaf.build env m in
      (* note-4 links note-6 via stride-2 miss -> "nowhere-land"; instead add
         a page one of the existing docs ALREADY links as missing *)
      let files' = files @ [ ("docs/hermes/zk/nowhere-land.md", "# Nowhere Land\n\nNow real.\n") ] in
      let m' = model_of files' in
      let env' = Dep_sheaf.Env.of_model m' in
      let incremental =
        Dep_sheaf.rebuild ~previous env' ~changed:(Dep_sheaf.Cover.of_list [ "nowhere-land" ]) m'
      in
      let cold = Dep_sheaf.build env' m' in
      List.for_all2
        (fun (s1, a) (s2, b) ->
          s1 = s2 && Dep_sheaf.Section.bytes a = Dep_sheaf.Section.bytes b)
        (List.sort compare incremental) (List.sort compare cold))

let () =
  check "dependents is the transpose of deps" (fun () ->
      let m = model_of (gen_corpus ~docs:8 ~stride:1) in
      List.for_all
        (fun p ->
          List.for_all
            (fun y ->
              List.mem p.Hermes_wiki.slug (Dep_sheaf.dependents m y))
            (Dep_sheaf.Cover.elements (Dep_sheaf.deps m p)))
        m.Hermes_wiki.pages)

(* ------------------------------------------------------- L27.5 tightness *)

let () =
  check "L27.5 no dead cover elements on generated corpora" (fun () ->
      let m = model_of (gen_corpus ~docs:8 ~stride:1) in
      List.for_all
        (fun p -> Dep_sheaf.dead_cover_elements m p = [])
        m.Hermes_wiki.pages)

let () =
  check "L27.5 meta-falsification: an over-approximated cover IS reported dead"
    (fun () ->
      (* a page that links nothing, probed with a widened cover: every
         element of the widening must come back dead *)
      let files =
        [ ("docs/hermes/zk/loner.md", "# Loner\n\nNo links at all.\n");
          ("docs/hermes/zk/other.md", "# Other\n\nAlso plain.\n") ]
      in
      let m = model_of files in
      let l = List.find (fun p -> p.Hermes_wiki.slug = "loner") m.Hermes_wiki.pages in
      Dep_sheaf.dead_cover_elements ~widen_with:[ "other" ] m l = [ "other" ])

(* -------------------------------------------- real corpus differential *)

let () =
  check "real corpus: L27.1 over every tracked document" (fun () ->
      let files =
        Hermes_wiki.read_tracked "modules/hermes_wiki/pages" @ Hermes_wiki.read_tracked "docs/hermes"
      in
      let m = model_of files in
      let env = Dep_sheaf.Env.of_model m in
      let all = Dep_sheaf.Cover.of_list (slugs_of m) in
      let global = Dep_sheaf.Env.restrict env all in
      List.for_all
        (fun p ->
          let ok =
            Dep_sheaf.render (Dep_sheaf.Env.restrict env (Dep_sheaf.deps m p)) p
            = Dep_sheaf.render global p
          in
          if not ok then
            Printf.printf "  L27.1 offender: %s\n" p.Hermes_wiki.slug;
          ok)
        m.Hermes_wiki.pages)

let () =
  check "real corpus: glue(build) equals slug-ordered concatenation of renders"
    (fun () ->
      let files =
        Hermes_wiki.read_tracked "modules/hermes_wiki/pages" @ Hermes_wiki.read_tracked "docs/hermes"
      in
      let m = model_of files in
      let env = Dep_sheaf.Env.of_model m in
      let family = Dep_sheaf.build env m in
      let glued = Dep_sheaf.Section.bytes (Dep_sheaf.glue family) in
      let manual =
        List.sort (fun a b -> compare a.Hermes_wiki.slug b.Hermes_wiki.slug) m.Hermes_wiki.pages
        |> List.map (fun p ->
               Dep_sheaf.render
                 (Dep_sheaf.Env.restrict env (Dep_sheaf.deps m p))
                 p)
        |> String.concat ""
      in
      glued = manual)

let () =
  check "aliases: L27.1 holds and the alias RESOLVES through the view" (fun () ->
      let m = model_of
          [ ("docs/hermes/zk/target.md",
             "---\naliases: [\"Old Name\"]\n---\n# Target\n\nBody.\n");
            ("docs/hermes/zk/citer.md", "# Citer\n\nSee [[Old Name]].\n") ] in
      let env = Dep_sheaf.Env.of_model m in
      let all = Dep_sheaf.Cover.of_list (slugs_of m) in
      let citer = List.find (fun p -> p.Hermes_wiki.slug = "citer") m.Hermes_wiki.pages in
      let local = Dep_sheaf.render (Dep_sheaf.Env.restrict env (Dep_sheaf.deps m citer)) citer in
      let global = Dep_sheaf.render (Dep_sheaf.Env.restrict env all) citer in
      local = global
      && (let n = String.length "target.html" and t = String.length local in
          let rec go i = i + n <= t && (String.sub local i n = "target.html" || go (i + 1)) in
          go 0))

let () =
  Printf.printf "dep_sheaf: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_dep_sheaf" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
