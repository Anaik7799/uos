(* The site: one index hub linking every component, use case, operational
   surface and KPI, plus wiki/ZK/analytics. Laws: the read model equals
   the store (derived-not-asserted at web scale), the index reaches every
   registry element (five completeness directions, meta-falsified), no
   page can write evidence, and rendering is deterministic + self-
   contained. *)

let passed = ref 0
let failed = ref 0
let skipped = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false ->
      incr failed;
      print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let contains text needle =
  let n = String.length needle and h = String.length text in
  let rec go i = i + n <= h && (String.sub text i n = needle || go (i + 1)) in
  go 0

let site = Site_build.build ~root:"."

let find name =
  match List.assoc_opt name site.Site_build.pages with
  | Some html -> html
  | None -> failwith ("no page " ^ name)

let index = find "index.html"

(* ------------------------------------------------------------ read model *)

let () =
  let m = site.Site_build.model in
  check "the read model loads without inventing data" (fun () ->
      m.Web_read_model.components > 0 && m.Web_read_model.edges > 0
      && m.Web_read_model.scenarios > 0);
  check "read model component/edge counts EQUAL the ontology" (fun () ->
      m.Web_read_model.components = List.length Fractal_ontology.components
      && m.Web_read_model.edges = List.length Fractal_ontology.atlas);
  check "read model use-case count EQUALS the BDD catalog" (fun () ->
      m.Web_read_model.scenarios = List.length Fpp_usecases.all);
  check "read model census EQUALS the registry census" (fun () ->
      m.Web_read_model.census = Formal_coverage.census ());
  check "parity KPIs are honest when the store is absent or present" (fun () ->
      match m.Web_read_model.parity with
      | None -> true (* no store: the site says so, never fabricates *)
      | Some p -> p.Web_read_model.verified <= p.Web_read_model.total);
  check "the coverage grade comes from the registry, not a constant" (fun () ->
      m.Web_read_model.system_grade = Formal_coverage.system_grade ());
  check "json export round-trips the counts" (fun () ->
      match Web_read_model.to_json m with
      | `Assoc fields -> (
          match List.assoc_opt "components" fields with
          | Some (`Int n) -> n = m.Web_read_model.components
          | _ -> false)
      | _ -> false);
  check "the read model is deterministic" (fun () ->
      Web_read_model.load ~root:"." = Web_read_model.load ~root:".")

(* -------------------------------------------------- index completeness *)

let () =
  check "the index links a page for EVERY ontology component" (fun () ->
      List.for_all
        (fun (c : Fractal_ontology.component) ->
          contains index ("component-" ^ c.Fractal_ontology.id ^ ".html"))
        Fractal_ontology.components);
  check "every component page is actually generated" (fun () ->
      List.for_all
        (fun (c : Fractal_ontology.component) ->
          List.mem_assoc ("component-" ^ c.Fractal_ontology.id ^ ".html")
            site.Site_build.pages)
        Fractal_ontology.components);
  check "the index reaches every use case" (fun () ->
      List.for_all
        (fun (s : Fpp_usecases.scenario) -> contains (find "usecases.html") s.Fpp_usecases.name)
        Fpp_usecases.all
      && contains index "usecases.html");
  check "the index reaches every wiki/ZK note" (fun () ->
      let wiki = find "wiki.html" in
      List.for_all
        (fun (p : Hermes_wiki.page) -> contains wiki (p.Hermes_wiki.slug ^ ".html"))
        site.Site_build.wiki.Hermes_wiki.pages
      && contains index "wiki.html");
  check "every wiki note has its own rendered page with backlinks section"
    (fun () ->
      List.for_all
        (fun (p : Hermes_wiki.page) ->
          match List.assoc_opt (p.Hermes_wiki.slug ^ ".html") site.Site_build.pages with
          | Some html -> contains html "Backlinks" || contains html "backlinks"
          | None -> false)
        site.Site_build.wiki.Hermes_wiki.pages);
  check "the index reaches every operational surface (admin use cases)"
    (fun () ->
      let ops = find "operations.html" in
      List.for_all (fun s -> contains ops s)
        [ "run_config"; "auto_converge"; "compare_reference_traces";
          "render_fprime_atlas"; "render_formal_coverage"; "serve_site" ]
      && contains ops "exit 2" && contains index "operations.html");
  check "the index carries the KPI band derived from the model" (fun () ->
      contains index "kpi"
      && contains index (string_of_int site.Site_build.model.Web_read_model.components)
      && contains index (string_of_int site.Site_build.model.Web_read_model.scenarios));
  check "the index links analytics, zk graph, atlas and dashboard" (fun () ->
      List.for_all (fun p -> contains index p)
        [ "analytics.html"; "zk.html"; "atlas.html"; "dashboard.html" ]);
  check "every linked page exists (no dead internal links on the hub)"
    (fun () ->
      let rec hrefs i acc =
        match String.index_from_opt index i '"' with
        | None -> acc
        | Some j -> (
            match String.index_from_opt index (j + 1) '"' with
            | None -> acc
            | Some k ->
                let value = String.sub index (j + 1) (k - j - 1) in
                let acc =
                  if
                    Filename.check_suffix value ".html"
                    && not (contains value "://")
                  then value :: acc
                  else acc
                in
                hrefs (k + 1) acc)
      in
      let links = List.sort_uniq compare (hrefs 0 []) in
      links <> []
      && List.for_all (fun l -> List.mem_assoc l site.Site_build.pages) links)

(* ------------------------------------------------------------- analytics *)

let () =
  let analytics = find "analytics.html" in
  check "analytics renders inline SVG charts, not external scripts" (fun () ->
      contains analytics "<svg" && not (contains analytics "<script src="));
  check "the coverage-grade distribution chart covers every entry" (fun () ->
      List.for_all
        (fun (e : Formal_coverage.entry) -> contains analytics e.Formal_coverage.component)
        Formal_coverage.entries);
  check "the census bar chart renders every census key" (fun () ->
      List.for_all (fun (k, _) -> contains analytics k) (Formal_coverage.census ()));
  check "the level-coverage chart renders every populated level" (fun () ->
      List.for_all
        (fun (level, _, _) -> contains analytics level)
        (Formal_coverage.level_coverage ()));
  check "the zk graph page draws nodes and edges as SVG" (fun () ->
      let zk = find "zk.html" in
      contains zk "<svg" && contains zk "<line" && contains zk "<circle");
  check "charts are deterministic (no clock, no randomness)" (fun () ->
      let again = Site_build.build ~root:"." in
      List.assoc "analytics.html" again.Site_build.pages = analytics)

(* ------------------------------------------------------ safety + shape *)

let () =
  check "no page embeds a form, POST, or write affordance (read-only law)"
    (fun () ->
      List.for_all
        (fun (_, html) ->
          (not (contains html "<form")) && (not (contains html "method=\"post\""))
          && not (contains html "XMLHttpRequest"))
        site.Site_build.pages);
  check "pages are self-contained (no external asset hosts)" (fun () ->
      List.for_all
        (fun (_, html) ->
          (not (contains html "http://cdn")) && not (contains html "https://cdn"))
        site.Site_build.pages);
  check "every page carries the shared shell (nav back to the hub)" (fun () ->
      List.for_all
        (fun (name, html) -> name = "index.html" || contains html "index.html")
        site.Site_build.pages);
  check "the site is a decent size and every page is non-empty" (fun () ->
      List.length site.Site_build.pages >= 40
      && List.for_all (fun (_, html) -> String.length html > 200) site.Site_build.pages);
  (* Deterministic FOR A FIXED INPUT — which is the only determinism a build
     over live state can honestly claim.

     `Site_build.build` reads `state/hermes_harness.sqlite3` (via
     `Web_read_model.load`). Under the battery that store is being written by
     other suites while this one runs, so two builds legitimately observe two
     database states and differ. The old check called that a build defect; it
     was a shared-mutable-input race between suites, and the verdict measured
     scheduling rather than the renderer.

     Rebuilding and comparing is still the right law — it just has to be
     conditioned on the input not having moved underneath. If the store
     changed mid-check, the comparison is DISCLOSED as unavailable rather than
     failed: absent evidence blocks credit and never denies it (R5, R22). *)
  (* Fingerprint the WAL SIBLINGS too, not just the database file.
     SQLite runs this store in WAL mode, so a concurrent writer appends to
     `-wal` and leaves the main file's mtime and size untouched — a fingerprint
     over the database alone is blind to precisely the writes that change what
     a reader sees. That blindness let this check fail once more after the
     first fix: the guard reported "unchanged" and the comparison then
     legitimately differed. *)
  (* Fingerprint EVERY mutable input the build reads, not a guessed subset.

     This guard has now been wrong twice by under-covering. First it watched
     only the database and missed the WAL siblings, where a concurrent writer
     actually lands. Then it missed the CORPUS — another actor editing
     `pages/` or `docs/hermes/` changes what the renderer reads, and two
     builds seconds apart legitimately differ.

     Enumerating inputs by guesswork is how a guard ends up blind, so this
     walks the corpus roots rather than naming files. The check is still the
     right law — render twice, compare — it simply has to be conditioned on
     the inputs holding still, and to say so when they did not. *)
  let stat_of path =
    match Unix.stat path with
    | s -> Some (s.Unix.st_mtime, s.Unix.st_size)
    | exception _ -> None
  in
  let rec tree_fingerprint acc path =
    match Sys.is_directory path with
    | true ->
        Array.fold_left
          (fun acc entry -> tree_fingerprint acc (Filename.concat path entry))
          acc (Sys.readdir path)
    | false -> (path, stat_of path) :: acc
    | exception _ -> acc
  in
  let store_fingerprint () =
    let files =
      List.map (fun p -> (p, stat_of p))
        [ "state/hermes_harness.sqlite3"; "state/hermes_harness.sqlite3-wal";
          "state/hermes_harness.sqlite3-shm" ]
    in
    let corpus =
      List.fold_left tree_fingerprint []
        [ "modules/hermes_wiki/pages"; "docs/hermes" ]
    in
    List.sort compare (files @ corpus)
  in
  let before = store_fingerprint () in
  let rebuilt = Site_build.build ~root:"." in
  let after = store_fingerprint () in
  if before <> after then begin
    incr skipped;
    print_endline
      "SKIPPED (disclosed): the whole site build is deterministic — a build input \
       (evidence store or corpus) changed under the rebuild; no claim either way"
  end
  else check "the whole site build is deterministic" (fun () -> rebuilt = site)

(* --------------------------------------------------- meta-falsification *)

let () =
  check "the component-completeness law CAN fail (fabricated component)"
    (fun () -> not (contains index "component-not_a_real_component.html"));
  check "the dead-link law CAN fail (a fabricated page name is absent)"
    (fun () -> not (List.mem_assoc "ghost.html" site.Site_build.pages))


(* ------------------------------------------------- rendered-layout laws *)

(* These exist because a real browser render exposed two defects the
   markup checks could not: a long KPI value overflowing its card, and a
   level row wider than its own viewBox (clipping its count). Both are
   now laws. *)
let () =
  let analytics = find "analytics.html" in
  check "the level chart's viewBox fits its widest row" (fun () ->
      let widest =
        List.fold_left (fun acc (_, total, _) -> max acc total) 1
          (Formal_coverage.level_coverage ())
      in
      let needed = 200 + (widest * 26) + 90 in
      contains analytics (Printf.sprintf "viewBox=\"0 0 %d " needed));
  check "long KPI values wrap inside their card instead of overflowing"
    (fun () -> contains index "overflow-wrap:anywhere");
  check "every chart declares a viewBox (scales instead of clipping)" (fun () ->
      let rec count from acc =
        let needle = "<svg" in
        let n = String.length needle and h = String.length analytics in
        let rec find i = if i + n > h then None
          else if String.sub analytics i n = needle then Some i else find (i + 1) in
        match find from with None -> acc | Some i -> count (i + 1) (acc + 1)
      in
      let svgs = count 0 0 in
      let rec vbs from acc =
        let needle = "viewBox=" in
        let n = String.length needle and h = String.length analytics in
        let rec find i = if i + n > h then None
          else if String.sub analytics i n = needle then Some i else find (i + 1) in
        match find from with None -> acc | Some i -> vbs (i + 1) (acc + 1)
      in
      svgs > 0 && vbs 0 0 = svgs)

let () =
  Printf.printf "site_build: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_site_build" ~passed:!passed ~failed:!failed
      ~skipped:!skipped
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_site_build ]);
  exit (Suite_telemetry.exit_code self)
