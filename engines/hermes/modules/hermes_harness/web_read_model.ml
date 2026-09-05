(* The typed read model. See web_read_model.mli. Everything is projected
   from the store and the registries; nothing is asserted. Store absence
   yields [parity = None] — the site says "no store", never a number. *)

type parity = {
  verified : int;
  total : int;
  divergent : int;
  blocked : int;
  snapshot : string;
}

type t = {
  revision : string;
  components : int;
  edges : int;
  scenarios : int;
  usecase_names : string list;
  system_grade : int;
  grades : (string * int) list;
  census : (string * int) list;
  levels : (string * int * int) list;
  parity : parity option;
  wiki_pages : int;
  wiki_links : int;
  intent_drift : string list;
  gaps : string list;
}

let git_revision root =
  let command = "git -C " ^ Filename.quote root ^ " rev-parse HEAD" in
  try
    let channel = Unix.open_process_in command in
    Fun.protect
      ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> String.trim (input_line channel))
  with _ -> "unknown"

let parity_of ~root =
  let path = Filename.concat root "state/hermes_harness.sqlite3" in
  if not (Sys.file_exists path) then None
  else
    match Evidence_store.open_db ~path with
    | Error _ -> None
    | Ok store ->
        let result =
          match Evidence_store.latest_snapshot store with
          | Ok (Some snapshot) -> (
              match Evidence_store.parity_results store ~snapshot_digest:snapshot with
              | Ok rows ->
                  let nodes = Evidence_rollup.per_node rows in
                  let count predicate =
                    List.length (List.filter (fun (_, v) -> predicate v) nodes)
                  in
                  Some
                    { verified = count (fun v -> v = Parity_algebra.Verified);
                      divergent = count (fun v -> v = Parity_algebra.Divergent);
                      blocked = count (fun v -> v = Parity_algebra.Blocked);
                      total = List.length nodes;
                      snapshot =
                        (if String.length snapshot > 12 then String.sub snapshot 0 12
                         else snapshot) }
              | Error _ -> None)
          | _ -> None
        in
        Evidence_store.close store;
        result

let load ~root =
  (* G-STR-1: during the migration the corpus spans BOTH roots —
     hermes_wiki/pages (moved) and docs/hermes (not yet). Reading one
     silently dropped every moved note and left its page stale. *)
  let wiki =
    Hermes_wiki.build
      (Hermes_wiki.read_tracked (Filename.concat root "modules/hermes_wiki/pages")
      @ Hermes_wiki.read_tracked (Filename.concat root "docs/hermes"))
  in
  { revision = git_revision root;
    components = List.length Fractal_ontology.components;
    edges = List.length Fractal_ontology.atlas;
    scenarios = List.length Fpp_usecases.all;
    usecase_names =
      List.map (fun (s : Fpp_usecases.scenario) -> s.Fpp_usecases.name) Fpp_usecases.all;
    system_grade = Formal_coverage.system_grade ();
    grades =
      List.map
        (fun (e : Formal_coverage.entry) ->
          (e.Formal_coverage.component, Formal_coverage.grade e))
        Formal_coverage.entries;
    census = Formal_coverage.census ();
    levels = Formal_coverage.level_coverage ();
    parity = parity_of ~root;
    wiki_pages = List.length wiki.Hermes_wiki.pages;
    wiki_links =
      List.fold_left
        (fun acc (p : Hermes_wiki.page) -> acc + List.length p.Hermes_wiki.outlinks)
        0 wiki.Hermes_wiki.pages;
    intent_drift = Formal_coverage.reconcile ();
    gaps =
      Formal_coverage.component_gaps () @ Formal_coverage.aspect_gaps ()
      @ Formal_coverage.scenario_gaps () @ Formal_coverage.interaction_gaps ()
      @ Formal_coverage.missing_files () }

let to_json t =
  `Assoc
    [ ("revision", `String t.revision);
      ("components", `Int t.components);
      ("edges", `Int t.edges);
      ("scenarios", `Int t.scenarios);
      ("systemGrade", `Int t.system_grade);
      ("grades", `Assoc (List.map (fun (k, v) -> (k, `Int v)) t.grades));
      ("census", `Assoc (List.map (fun (k, v) -> (k, `Int v)) t.census));
      ("levels",
       `List
         (List.map
            (fun (level, total, covered) ->
              `Assoc
                [ ("level", `String level); ("components", `Int total);
                  ("covered", `Int covered) ])
            t.levels));
      ("parity",
       (match t.parity with
       | None -> `Null
       | Some p ->
           `Assoc
             [ ("verified", `Int p.verified); ("total", `Int p.total);
               ("divergent", `Int p.divergent); ("blocked", `Int p.blocked);
               ("snapshot", `String p.snapshot) ]));
      ("wikiPages", `Int t.wiki_pages);
      ("wikiLinks", `Int t.wiki_links);
      ("intentDrift", `List (List.map (fun d -> `String d) t.intent_drift));
      ("gaps", `List (List.map (fun g -> `String g) t.gaps)) ]
