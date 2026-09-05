(* The feature register under test. The register's whole value is that it
   cannot drift from the system it describes, so the laws here are about
   INTEGRITY (ids unique, references resolve, counts consistent) and
   HONESTY (a live probe overrides a declaration, and disagreements are
   reported rather than silently preferred). *)

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

open Feature_register

(* ------------------------------------------------------------- integrity *)

let () = check "the register carries every feature in the plan" (fun () ->
    (* 276 from the plan + HW.10.1.4, added by the deep-structures pass
       (unified-deep-structures.md §14.4) — a DELIBERATE bump, like a
       baseline re-pin *)
    (* 277 + HW.1.3.16, the PKM schema conformance row
       (docs/hermes/specs/2026-08-09-pkm-longterm-architecture.md §3) *)
    (* 284 + HW.6.9.8, rendered-surface verification: the row the eight
       browser mirrors were always about. They had been scheduled against
       HW.6.9.1 (URL parsing) — a mis-targeting the import audit found,
       and a missing row is the honest diagnosis, not a re-labelling. *)
    List.length features = 285)

let () = check "ids are unique" (fun () ->
    let ids = List.sort compare (List.map (fun f -> f.id) features) in
    List.length (List.sort_uniq compare ids) = List.length ids)

let () = check "every id is HW.<area>.<group>.<feature>" (fun () ->
    List.for_all
      (fun f ->
        match String.split_on_char '.' f.id with
        | [ "HW"; a; b; c ] ->
            List.for_all (fun s -> s <> "" && String.for_all (fun ch -> ch >= '0' && ch <= '9') s)
              [ a; b; c ]
        | _ -> false)
      features)

let () = check "the id's area segment agrees with the area field" (fun () ->
    let n = function
      | Corpus -> 1 | Dialect -> 2 | Address -> 3 | Graph -> 4 | Query -> 5
      | Surface -> 6 | Present -> 7 | Lifecycle -> 8 | Source -> 9 | Build -> 10
    in
    List.for_all
      (fun f ->
        match String.split_on_char '.' f.id with
        | [ "HW"; a; _; _ ] -> int_of_string a = n f.area
        | _ -> false)
      features)

let () = check "no blocker or gate names a feature that does not exist" (fun () ->
    dangling_references () = [])

let () = check "no feature is blocked on itself" (fun () ->
    List.for_all (fun f -> match f.declared with Blocked on -> on <> f.id | _ -> false || true)
      features
    && List.for_all (fun f -> not (List.mem f.id f.gates)) features)

let () = check "the blocking relation is acyclic" (fun () ->
    let rec chase seen id depth =
      if depth > 20 then false
      else if List.mem id seen then false
      else
        match List.find_opt (fun f -> f.id = id) features with
        | Some { declared = Blocked on; _ } -> chase (id :: seen) on (depth + 1)
        | _ -> true
    in
    List.for_all (fun f -> chase [] f.id 0) features)

let () = check "every audit row referenced is in 1..116" (fun () ->
    List.for_all (fun f -> List.for_all (fun r -> r >= 1 && r <= 116) f.audit_rows) features)

let () = check "all 116 audit rows are covered" (fun () ->
    let rows = List.concat_map (fun f -> f.audit_rows) features in
    List.length (List.sort_uniq compare rows) = 116)

let () = check "only the two documented rows are decomposed into several features" (fun () ->
    (* audit row 23 (Filters & sorts) is where + sort; row 98 (Graph analysis)
       is pagerank + communities + betweenness. Any OTHER duplicate would mean
       two features claim the same requirement. *)
    let rows = List.sort compare (List.concat_map (fun f -> f.audit_rows) features) in
    let rec dups = function
      | a :: (b :: _ as r) -> (if a = b then [ a ] else []) @ dups r
      | _ -> []
    in
    List.sort_uniq compare (dups rows) = [ 23; 98 ])

let () = check "utility and criticality are in 0..5" (fun () ->
    List.for_all
      (fun f -> f.utility >= 0 && f.utility <= 5 && f.criticality >= 0 && f.criticality <= 5)
      features)

let () = check "an excluded feature scores zero utility and criticality" (fun () ->
    List.for_all
      (fun f -> if f.declared = Excluded then f.utility = 0 && f.criticality = 0 else true)
      features)

let () = check "every feature states a law" (fun () ->
    List.for_all (fun f -> String.length (String.trim f.law) > 10) features)

let () = check "every feature names at least one source" (fun () ->
    List.for_all (fun f -> f.sources <> []) features)

(* --------------------------------------------------------------- honesty *)

let () = check "a live probe overrides the declaration" (fun () ->
    (* HW.2.1.2 (bulleted lists) is declared Built AND probed; the probe
       must be what decides, so status is Built for the right reason. *)
    match List.find_opt (fun f -> f.id = "HW.2.1.2") features with
    | Some f -> f.derived <> None && status f = Built
    | None -> false)

let () = check "declarations and probes agree (no stale rows)" (fun () ->
    match stale_declarations () with
    | [] -> true
    | rows ->
        List.iter (fun r -> print_endline ("  stale: " ^ r)) rows;
        false)

let () = check "meta-falsification: a failing probe overrides a Built declaration" (fun () ->
    (* the register must never let a declaration outrank the system *)
    let bogus =
      { id = "HW.0.0.0"; area = Corpus; name = "probe"; sources = [ Own ]; audit_rows = [];
        law = "a law long enough to pass the law check"; utility = 1; criticality = 1;
        gates = []; declared = Built; derived = Some (fun () -> false) }
    in
    status bogus <> Built)

(* ------------------------------------------------------------ priorities *)

let () = check "priority weights criticality above utility" (fun () ->
    let mk c u =
      { id = "HW.1.1.1"; area = Corpus; name = "x"; sources = [ Own ]; audit_rows = [];
        law = "a law long enough to pass"; utility = u; criticality = c; gates = [];
        declared = Ready; derived = None }
    in
    priority (mk 5 1) > priority (mk 1 5))

let () = check "gating raises priority" (fun () ->
    let mk gates =
      { id = "HW.1.1.1"; area = Corpus; name = "x"; sources = [ Own ]; audit_rows = [];
        law = "a law long enough to pass"; utility = 3; criticality = 3; gates;
        declared = Ready; derived = None }
    in
    priority (mk [ "a"; "b"; "c" ]) > priority (mk []))

let () = check "built and excluded features score zero" (fun () ->
    List.for_all
      (fun f -> match status f with Built | Excluded -> priority f = 0 | _ -> true)
      features)

let () = check "nothing actionable is blocked by an unsatisfied blocker" (fun () ->
    List.for_all
      (fun f ->
        match (actionable f, status f) with
        | true, Blocked on -> (
            match List.find_opt (fun b -> b.id = on) features with
            | Some b -> status b = Built
            | None -> false)
        | _ -> true)
      features)

let () = check "prioritized is sorted, descending, ties by id" (fun () ->
    let rec ordered = function
      | a :: (b :: _ as rest) ->
          (priority a > priority b || (priority a = priority b && a.id <= b.id)) && ordered rest
      | _ -> true
    in
    ordered (prioritized ()))

let () = check "next is the head of prioritized" (fun () ->
    match (next (), prioritized ()) with
    | Some n, top :: _ -> n.id = top.id
    | None, [] -> true
    | _ -> false)

let () = check "everything actionable is Ready or unblocked, never Excluded" (fun () ->
    List.for_all (fun f -> match status f with Excluded | Forked _ -> false | _ -> true)
      (prioritized ()))

(* ---------------------------------------------------------------- counts *)

let () = check "the summary partitions the register" (fun () ->
    let s = summary () in
    s.built + s.ready + s.blocked + s.forked + s.excluded = List.length features)

let () = check "by_area partitions the register" (fun () ->
    List.length (List.concat_map snd (by_area ())) = List.length features)


(* ------- ALL existing code reused: the biconditional, mechanically ------ *)

let import_root = "modules/hermes_wiki/import/zigvm/code"

let observed_modules () =
  let rec walk dir acc =
    match Sys.readdir dir with
    | entries ->
        Array.fold_left
          (fun acc name ->
            let p = Filename.concat dir name in
            if Sys.is_directory p then walk p acc
            else if Filename.check_suffix name ".ml"
                    && not (String.length name > 5 && String.sub name 0 5 = "test_")
            then Filename.remove_extension name :: acc
            else acc)
          acc entries
    | exception _ -> acc
  in
  List.sort_uniq compare (walk import_root [])

let () = check "every imported module has a disposition (nothing arrived unclassified)"
    (fun () ->
      let observed = observed_modules () in
      match Import_coverage.unclassified ~observed with
      | [] -> observed <> []
      | ms -> List.iter (fun m -> print_endline ("  unclassified: " ^ m)) ms; false)

let () = check "no phantom rows (every disposition names a module that is there)" (fun () ->
    let observed = observed_modules () in
    match Import_coverage.phantom ~observed with
    | [] -> true
    | ms -> List.iter (fun m -> print_endline ("  phantom: " ^ m)) ms; false)

let () = check "every Ported row names register rows that EXIST" (fun () ->
    List.for_all
      (fun (x : Import_coverage.entry) ->
        match x.Import_coverage.disposition with
        | Import_coverage.Ported rows ->
            List.for_all
              (fun r ->
                List.exists (fun f -> f.id = r) features
                || (print_endline ("  ported names a missing row: " ^ r); false))
              rows
        | _ -> true)
      Import_coverage.entries)

let () = check "every Ported row's register rows are actually Built (reuse is REAL)" (fun () ->
    List.for_all
      (fun (x : Import_coverage.entry) ->
        match x.Import_coverage.disposition with
        | Import_coverage.Ported rows ->
            List.for_all
              (fun r ->
                match List.find_opt (fun f -> f.id = r) features with
                | Some f when status f = Built -> true
                | _ ->
                    print_endline ("  " ^ x.Import_coverage.module_ ^ " claims ported into " ^ r
                                   ^ ", which is not Built");
                    false)
              rows
        | _ -> true)
      Import_coverage.entries)

let () = check "every Scheduled row names an existing register row (the queue is real)"
    (fun () ->
      List.for_all
        (fun (x : Import_coverage.entry) ->
          match x.Import_coverage.disposition with
          | Import_coverage.Scheduled r ->
              List.exists (fun f -> f.id = r) features
              || (print_endline ("  scheduled against a missing row: " ^ r); false)
          | _ -> true)
        Import_coverage.entries)

let () = check "Operational and Superseded rows state a reason (never a bare label)" (fun () ->
    List.for_all
      (fun (x : Import_coverage.entry) ->
        match x.Import_coverage.disposition with
        | Import_coverage.Operational w | Import_coverage.Superseded w -> String.length w > 20
        | _ -> true)
      Import_coverage.entries)

let () =
  let c = Import_coverage.census () in
  Printf.printf "  import reuse: %d ported · %d operational · %d scheduled · %d superseded\n"
    c.Import_coverage.ported c.Import_coverage.operational c.Import_coverage.scheduled
    c.Import_coverage.superseded

let () =
  let s = summary () in
  Printf.printf
    "feature_register: %d passed, %d failed  [built %d · ready %d · blocked %d · fork %d · n/a %d]\n"
    !passed !failed s.built s.ready s.blocked s.forked s.excluded;
  (match next () with
  | Some f -> Printf.printf "  next: %s %s (priority %d)\n" f.id f.name (priority f)
  | None -> print_endline "  next: nothing actionable");
  let self = Wiki_suite_telemetry.observe ~suite:"test_feature_register" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
