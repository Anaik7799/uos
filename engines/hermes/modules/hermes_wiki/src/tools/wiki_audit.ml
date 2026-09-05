(* --wiki-audit — the AuditLoop actor run once, on the command line.
   States mirror the Wiki_topology machine: Idle -> Sensing -> Diffing ->
   Reporting. Monitors SENSE and REPORT; the only actuator is the ratchet's
   refusal (exit 1) — nothing here writes the corpus (the report-only law).

   Gauges wired today (each a Wiki_topology telemetry channel):
     schema_debt · dead_links · dead_anchors · drift_count ·
     stale_declarations · query_rejects_named
   Named skips (no silent caps): orphans, grounded_anomalies, ecc_hub,
   dead_cover, playwright_fail — their features are not landed yet.

   --pin rewrites hermes_wiki/baseline/ratchet-gauges.txt from the sensed
   values: a DELIBERATE act, outside the battery, like the render re-pin. *)

let pin_path = "modules/hermes_wiki/baseline/ratchet-gauges.txt"
let suppression_path = "modules/hermes_wiki/baseline/suppressions.txt"
let baseline_path = "modules/hermes_wiki/baseline/render-baseline.txt"

let otel_path = "state/wiki-audit.otel.jsonl"

let now_iso () =
  let t = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1)
    t.Unix.tm_mday t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec

let emit r =
  (try
     if not (Sys.file_exists "state") then Unix.mkdir "state" 0o755;
     let oc = open_out_gen [ Open_append; Open_creat ] 0o644 otel_path in
     output_string oc (Wiki_otel.render r ^ "\n");
     close_out oc
   with _ -> () (* telemetry must never break the audit — R4's direction *));
  ()

(* every finding leaves BOTH traces: the fractal diagnostic (rendered,
   coordinate first) and the OTel record carrying that coordinate as
   attributes. Neither can deny parity credit — the type forbids it. *)
let diag_count = ref 0

let fractal ?(print = true) finding =
  let d = Wiki_diagnostics.diagnose finding in
  incr diag_count;
  (try
     if not (Sys.file_exists "state") then Unix.mkdir "state" 0o755;
     let oc = open_out_gen [ Open_append; Open_creat ] 0o644 otel_path in
     output_string oc (Wiki_otel.render (Wiki_diagnostics.to_otel ~ts:(now_iso ()) d) ^ "\n");
     close_out oc
   with _ -> ());
  if print then print_endline ("  " ^ Fractal_diagnostic.render d)

let current_state = ref "Idle"

let state s =
  emit (Wiki_otel.state_transition ~ts:(now_iso ()) ~actor:"auditLoop" ~from_:!current_state ~to_:s);
  current_state := s;
  Printf.printf "[auditLoop] -> %s\n%!" s

let read_lines path =
  if not (Sys.file_exists path) then []
  else begin
    let ic = open_in_bin path in
    let rec go acc =
      match input_line ic with
      | l -> go (l :: acc)
      | exception End_of_file -> close_in ic; List.rev acc
    in
    go []
  end

let today () =
  (* R16: the clock is read from the environment, never invented. *)
  let t = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02d" (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1) t.Unix.tm_mday

let () =
  (* R19 — unknown flags are REFUSED. `--pinn`, `-pin` and `--pin=true`
     used to run a full default audit with no complaint, which reads to
     an operator exactly like a successful re-pin that did not happen. *)
  let pin_mode =
    match List.tl (Array.to_list Sys.argv) with
    | [] -> false
    | [ "--pin" ] -> true
    | args ->
        prerr_endline
          ("unknown argument(s): " ^ String.concat " " args
         ^ "\nusage: wiki_audit [--pin]\n  (no flag)  sense every gauge and check the ratchet\n\
           \  --pin      rewrite the pins from the sensed values (deliberate)");
        exit 2
  in
  state "Sensing";
  let pages_files = Hermes_wiki.read_tracked "modules/hermes_wiki/pages" in
  let docs_files = Hermes_wiki.read_tracked "docs/hermes" in
  let m = Hermes_wiki.build ~read_source:Hermes_wiki.read_source_file (pages_files @ docs_files) in
  let m_pages = Hermes_wiki.build ~read_source:Hermes_wiki.read_source_file pages_files in
  let schema_debt = List.length (Hermes_wiki.schema_gaps m) in
  (* HW.3.7.3 made the gauge honest: dead_links now counts UNRESOLVED
     REFERENCES (nitpicky mode — any unresolved reference fails), and the
     corpus defects the render gate refuses on keep their own pin. *)
  let dead_links = List.length (Hermes_wiki.unresolved_refs m) in
  let corpus_defects = List.length (Hermes_wiki.defects m) in
  let dead_anchors = List.length (Hermes_wiki.broken_anchors m) in
  (* HW.3.7.2: contested reference keys at the USE site — the opposite
     failure from a dead link, sensed and ratcheted separately. *)
  let ambiguous = List.length (Hermes_wiki.ambiguous_refs m) in
  (* HW.3.7.6: the per-reference opt-outs, DISCLOSED but never ratcheted —
     pinning them would forbid the legitimate escape hatch (R2 shape). *)
  let suppressed = List.length (Hermes_wiki.suppressed_refs m) in
  (* HW.3.7.4: terms used and defined nowhere — the vocabulary's teeth. *)
  let term_gaps = List.length (Hermes_wiki.term_gaps m) in
  (* HW.1.4.1: the visibility split — drafts are a legitimate state and
     are merely counted; a MALFORMED visibility is a defect, because a
     misspelled value must never publish a page by accident. *)
  let vis_census = Wiki_visibility.census m in
  let drafts =
    match List.assoc_opt Wiki_visibility.Draft vis_census with Some l -> List.length l | None -> 0
  in
  let visibility_malformed = List.length (Wiki_visibility.malformed m) in
  (* HW.1.3.11: two siblings both declaring the same sidebar_position.
     The sort still resolves it (by slug, deterministically), which is
     exactly why it must be COUNTED — a tie the author did not intend is
     invisible in the output and only visible here. *)
  let position_conflicts = List.length (Wiki_ordering.position_conflicts m) in
  (* HW.8.5.3 / HW.1.2.6 — the governance checks over the live corpus.
     vocabulary_gaps counts values OUTSIDE a closed vocabulary, which is a
     different fact from schema_debt's ABSENT values: a misspelled ktype
     and a missing one want different fixes. slug_claims are the declared
     overrides, disclosed rather than pinned because the escape hatch is
     legitimate; a COLLISION between two of them is not. *)
  let vocabulary_gaps = List.length (Wiki_lifecycle.vocabulary_gaps m) in
  let slug_claims =
    List.map
      (fun (p : Hermes_wiki.page) ->
        { Wiki_lifecycle.path = p.Hermes_wiki.path;
          declared =
            (match p.Hermes_wiki.meta.Hermes_wiki.slug_claim with "" -> None | s -> Some s);
          derived = p.Hermes_wiki.slug })
      m.Hermes_wiki.pages
  in
  let slug_overrides = List.length (Wiki_lifecycle.slug_overrides slug_claims) in
  let slug_collisions = List.length (Wiki_lifecycle.slug_collisions slug_claims) in
  (* HW.3.5.1 — transclusion. Expansion happens at build; the audit
     re-derives it over the same corpus to COUNT what could not be
     expanded. `embed_cycles` is not a defect of the author so much as a
     shape of the corpus, but it is pinned because a cycle silently
     truncates a reader's document. *)
  let embed_lookup t =
    let key = Hermes_wiki.slugify t in
    List.find_opt
      (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug = key)
      m.Hermes_wiki.pages
    |> Option.map (fun (p : Hermes_wiki.page) -> (p.Hermes_wiki.slug, p.Hermes_wiki.raw))
  in
  let embed_outcomes =
    m.Hermes_wiki.pages
    |> List.filter (fun (p : Hermes_wiki.page) -> Wiki_transclude.has_embed p.Hermes_wiki.raw)
    |> List.map (fun (p : Hermes_wiki.page) ->
           Wiki_transclude.expand ~lookup:embed_lookup ~self:p.Hermes_wiki.slug p.Hermes_wiki.raw)
  in
  let embed_gaps =
    List.fold_left (fun a o -> a + List.length o.Wiki_transclude.missing) 0 embed_outcomes
  in
  let embed_cycles =
    List.fold_left (fun a o -> a + List.length o.Wiki_transclude.cycles) 0 embed_outcomes
  in
  (* HW.2.6.3: see-entries redirecting into nothing. *)
  let index_violations = List.length (Hermes_wiki.index_violations m) in
  (* HW.9.3.1: tested examples that no longer render as documented. *)
  let doctest_drift = List.length (Hermes_wiki.doctest_drift m) in
  (* HW.9.2.1: includes whose slice did not resolve under the real
     reader — the dual of the denotation law, never silently empty. *)
  let include_gaps = List.length (Hermes_wiki.include_gaps m) in
  (* HW.2.6.6: emphasize outside the fence's own line range. *)
  let fence_option_gaps = List.length (Hermes_wiki.fence_option_gaps m) in
  (* HW.6.8.1: the DECLARED navigation tree — unresolved declarations,
     and the navigation debt (pages the tree does not place). The debt
     falls as navigation is authored, which is the row's whole point. *)
  let toc = Wiki_toc.of_model m_pages in
  let toc_gaps = List.length (Wiki_toc.gaps toc) in
  let toc_unplaced = List.length (Wiki_toc.unplaced m_pages toc) in
  (* HW.6.8.2: the VERDICT — unplaced minus the disclosed entry points.
     The disclosure count is reported but never pinned: pinning it would
     forbid the legitimate escape hatch (the R2 shape, as with
     suppressed_refs). *)
  let toc_unreachable = List.length (Wiki_toc.unreachable m_pages toc) in
  let disclosed = List.length (Wiki_toc.disclosed_orphans m_pages) in
  let stale = List.length (Feature_register.stale_declarations ()) in
  let query_rejects_unnamed =
    List.fold_left
      (fun acc (_, raw) ->
        List.fold_left
          (fun acc fence ->
            match Wiki_query.parse fence with
            | Ok _ -> acc
            | Error "" -> acc + 1 (* an UNNAMED rejection is the defect *)
            | Error _ -> acc)
          acc
          (Wiki_query.fences raw))
      0 pages_files
  in
  let drift =
    (* A MISSING BASELINE IS NOT ZERO DRIFT. `read_lines` returns [] for an
       absent file and `of_lines` silently drops malformed lines, and
       `drift` reports only Drifted — never Unlisted — so deleting the
       baseline made the gauge read 0 and the audit pass. The gate cannot
       be allowed to certify its own absence. *)
    let baseline_lines = read_lines baseline_path in
    if baseline_lines = [] then begin
      Printf.eprintf
        "  [L4/fixture evidence] REFUSED: the render baseline at %s is missing or empty\n\
        \    cause: drift is measured against it, so its absence would read as zero drift\n\
        \    fix:   restore it from git, or regenerate deliberately with gen_render_baseline\n"
        baseline_path;
      exit 1
    end;
    let baseline = Wiki_baseline.of_lines baseline_lines in
    if List.length baseline * 2 < List.length baseline_lines then begin
      Printf.eprintf
        "  [L4/fixture evidence] REFUSED: %d of %d baseline lines did not parse\n\
        \    cause: a half-parsed baseline measures drift against a fiction\n"
        (List.length baseline_lines - List.length baseline)
        (List.length baseline_lines);
      exit 1
    end;
    let docs =
      List.map
        (fun (p : Hermes_wiki.page) -> (p.Hermes_wiki.path, p.Hermes_wiki.raw, p.Hermes_wiki.html))
        m_pages.Hermes_wiki.pages
    in
    List.length (Wiki_baseline.drift (Wiki_baseline.check ~baseline docs))
  in
  let graph = Wiki_graph.of_model m_pages in
  let orphans =
    (* the graph kernel's gauge (HW.4.2.x landed): pages nobody links to,
       hub and index pages included honestly — the pin captures the level *)
    List.length (Wiki_graph.orphans graph)
  in
  let ecc_hub =
    (* navigability: BFS eccentricity from the knowledge-fractal-map hub;
       unreachable pages are the orphans gauge's business. A MISSING hub
       is loud (sentinel 9999 breaches any sane pin) — never a quiet 0. *)
    (if Sys.getenv_opt "WIKI_AUDIT_DEBUG" <> None then
       match
         List.find_opt
           (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug = "knowledge-fractal-map")
           m_pages.Hermes_wiki.pages
       with
       | None -> print_endline "  DEBUG hub page NOT in pages-root model"
       | Some p ->
           Printf.printf "  DEBUG hub outlinks (%d): %s\n"
             (List.length p.Hermes_wiki.outlinks)
             (String.concat ", "
                (List.filteri (fun i _ -> i < 5) p.Hermes_wiki.outlinks)));
    match Wiki_graph.ecc_from graph "knowledge-fractal-map" with
    | Some e -> e
    | None ->
        print_endline "  WARNING: hub knowledge-fractal-map missing from the graph";
        9999
  in
  let grounded_anomalies = List.length (Discourse.anomalies m) in
  let reuse = Import_coverage.census () in
  let unported = reuse.Import_coverage.scheduled in
  emit
    (Wiki_otel.record ~ts:(now_iso ()) ~severity:Wiki_otel.Info ~body:"import reuse census"
       ~attrs:
         [ ("actor", "auditLoop");
           ("ported", string_of_int reuse.Import_coverage.ported);
           ("operational", string_of_int reuse.Import_coverage.operational);
           ("scheduled", string_of_int unported);
           ("superseded", string_of_int reuse.Import_coverage.superseded) ]);
  List.iter
    (fun (m, row) ->
      fractal ~print:false (Wiki_diagnostics.Unported_mirror { module_ = m; row }))
    (Import_coverage.next_mirrors ());
  (* every corpus finding, as a fractal diagnostic in the stream *)
  List.iter
    (fun s -> fractal ~print:false (Wiki_diagnostics.Dead_link { source = s; target = "" }))
    (Hermes_wiki.unresolved_refs m);
  Printf.printf "  disclosed suppressed_refs     %d (opt-outs, never ratcheted)\n" suppressed;
  Printf.printf "  disclosed orphan_entrypoints  %d (declared, never ratcheted)\n" disclosed;
  (* MBSE: the model gate. Elements and verified counts are DISCLOSED and
     never ratcheted — both must rise as the register grows, and a
     ratchet on a number that should increase fires on progress. Only the
     GAP count is pinned, because that is the number that must fall. *)
  let mcov = Feature_model.coverage () in
  Printf.printf "  disclosed model_elements      %d (the model of record, never ratcheted)\n"
    mcov.Feature_model.total;
  Printf.printf "  disclosed model_verified      %d (probe-backed, never ratcheted)\n"
    mcov.Feature_model.verified;
  Printf.printf "  disclosed slug_overrides      %d (declared, never ratcheted)\n" slug_overrides;
  List.iter
    (fun line ->
      emit
        (Wiki_otel.record ~ts:(now_iso ()) ~severity:Wiki_otel.Warn
           ~body:"value outside the controlled vocabulary"
           ~attrs:[ ("actor", "schemaAuditor"); ("event", "VOCABULARY_GAP"); ("subject", line) ]))
    (Wiki_lifecycle.vocabulary_gaps m);
  emit
    (Wiki_otel.record ~ts:(now_iso ()) ~severity:Wiki_otel.Info ~body:"model coverage disclosed"
       ~attrs:
         [ ("actor", "modelGate");
           ("elements", string_of_int mcov.Feature_model.total);
           ("verified", string_of_int mcov.Feature_model.verified);
           ("gaps", string_of_int mcov.Feature_model.declared_only) ]);
  List.iter
    (fun line ->
      emit
        (Wiki_otel.record ~ts:(now_iso ()) ~severity:Wiki_otel.Warn
           ~body:"requirement with no verification method"
           ~attrs:[ ("actor", "modelGate"); ("event", "MODEL_GAP"); ("subject", line) ]))
    (Feature_model.model_gaps ());
  List.iter
    (fun line ->
      emit
        (Wiki_otel.record ~ts:(now_iso ()) ~severity:Wiki_otel.Warn
           ~body:"dependency on an element the model lacks"
           ~attrs:[ ("actor", "modelGate"); ("event", "MODEL_DANGLING"); ("subject", line) ]))
    (Feature_model.dangling_dependencies ());
  emit
    (Wiki_otel.record ~ts:(now_iso ()) ~severity:Wiki_otel.Info
       ~body:"suppressed references disclosed"
       ~attrs:[ ("actor", "linkAuditor"); ("count", string_of_int suppressed) ]);
  List.iter
    (fun s ->
      fractal ~print:false (Wiki_diagnostics.Dead_anchor { source = s; target = ""; anchor = "" }))
    (Hermes_wiki.broken_anchors m);
  List.iter
    (fun line -> fractal ~print:false (Wiki_diagnostics.Ambiguous_ref { source = line; target = "" }))
    (Hermes_wiki.ambiguous_refs m);
  List.iter
    (fun line -> fractal ~print:false (Wiki_diagnostics.Term_gap { page = line; term = "" }))
    (Hermes_wiki.term_gaps m);
  List.iter
    (fun line ->
      fractal ~print:false (Wiki_diagnostics.Index_violation { page = line; target = "" }))
    (Hermes_wiki.index_violations m);
  List.iter
    (fun d -> fractal ~print:false (Wiki_diagnostics.Corpus_defect { detail = d }))
    (Hermes_wiki.defects m);
  List.iter
    (fun line ->
      fractal ~print:false (Wiki_diagnostics.Include_gap { page = line; path = ""; reason = "" }))
    (Hermes_wiki.include_gaps m);
  List.iter
    (fun line -> fractal ~print:false (Wiki_diagnostics.Toc_gap { page = line; target = "" }))
    (Wiki_toc.gaps toc);
  List.iter
    (fun s -> fractal ~print:false (Wiki_diagnostics.Schema_gap { page = s; field = "" }))
    (Hermes_wiki.schema_gaps m);
  List.iter
    (fun c -> fractal ~print:false (Wiki_diagnostics.Grounded_anomaly { claim = c }))
    (Discourse.anomalies m);
  List.iter
    (fun p -> fractal ~print:false (Wiki_diagnostics.Orphan { page = p }))
    (Wiki_graph.orphans graph);
  List.iter
    (fun r -> fractal ~print:false (Wiki_diagnostics.Stale_declaration { row = r }))
    (Feature_register.stale_declarations ());
  let sensed =
    [ ("ambiguous_refs", ambiguous);
      ("corpus_defects", corpus_defects);
      ("dead_anchors", dead_anchors);
      ("drafts", drafts);
      ("embed_cycles", embed_cycles);
      ("embed_gaps", embed_gaps);
      ("visibility_malformed", visibility_malformed);
      ("dead_links", dead_links);
      ("doctest_drift", doctest_drift);
      ("drift_count", drift);
      ("ecc_hub", ecc_hub);
      ("fence_option_gaps", fence_option_gaps);
      ("grounded_anomalies", grounded_anomalies);
      ("include_gaps", include_gaps);
      ("index_violations", index_violations);
      ("model_gaps", List.length (Feature_model.model_gaps ()));
      ("vocabulary_gaps", vocabulary_gaps);
      ("slug_collisions", slug_collisions);
      ("model_dangling", List.length (Feature_model.dangling_dependencies ()));
      ("orphans", orphans);
      ("position_conflicts", position_conflicts);
      ("query_rejects_named", query_rejects_unnamed);
      ("schema_debt", schema_debt);
      ("stale_declarations", stale);
      ("term_gaps", term_gaps);
      ("toc_gaps", toc_gaps);
      ("toc_unplaced", toc_unplaced);
      ("toc_unreachable", toc_unreachable);
      ("unported_mirrors", unported) ]
  in
  List.iter
    (fun (g, v) ->
      emit
        (Wiki_otel.record ~ts:(now_iso ()) ~severity:Wiki_otel.Info ~body:"gauge sensed"
           ~attrs:[ ("actor", "auditLoop"); ("gauge", g); ("value", string_of_int v) ]);
      Printf.printf "  sensed %-24s %d\n" g v)
    sensed;
  emit
    (Wiki_otel.record ~ts:(now_iso ()) ~severity:Wiki_otel.Debug ~body:"corpus sensed"
       ~attrs:
         [ ("actor", "auditLoop");
           ("pages", string_of_int (List.length m.Hermes_wiki.pages));
           ("pinned", string_of_int (List.length m_pages.Hermes_wiki.pages)) ]);
  List.iter
    (fun g ->
      emit
        (Wiki_otel.record ~ts:(now_iso ()) ~severity:Wiki_otel.Debug
           ~body:"gauge skipped (feature not landed yet)"
           ~attrs:[ ("actor", "auditLoop"); ("gauge", g) ]);
      Printf.printf "  skipped (feature not landed yet): %s\n" g)
    [ "dead_cover"; "playwright_fail" ];
  if pin_mode then begin
    state "Reporting";
    (* VALIDATE BEFORE WRITING. A re-pin used to write whatever was
       sensed, unconditionally. Two ways that destroyed the gate: an
       undetermined corpus sensed 19 zeros (making the ratchet
       unfalsifiable downward), and `ecc_hub` sensed its 9999 sentinel —
       pinning that PERMANENTLY DISARMS the one check that makes an
       unreadable corpus fail closed. A pin is a commitment; a commitment
       to a sentinel is a commitment to never noticing again. *)
    let sentinels =
      List.filter (fun (g, v) -> g = "ecc_hub" && v >= 9999) sensed
      @ List.filter (fun (_, v) -> v < 0) sensed
    in
    if sentinels <> [] then begin
      List.iter
        (fun (g, v) ->
          Printf.eprintf
            "[LX/control-plane control] REFUSED to pin %s at %d\n\
            \  cause: that is a fail-closed sentinel or an impossible count — pinning it\n\
            \         would make the gauge unable to breach ever again\n\
            \  fix:   repair what the sensor is reporting, then re-pin\n"
            g v)
        sentinels;
      exit 1
    end;
    let old_pins = match Ratchet.parse_pins (read_lines pin_path) with Ok p -> p | Error _ -> [] in
    (* print the diff the message tells the operator to review *)
    List.iter
      (fun (g, v) ->
        match List.assoc_opt g old_pins with
        | Some prev when prev = v -> ()
        | Some prev ->
            Printf.printf "  re-pin %-22s %d -> %d%s\n" g prev v
              (if v > prev then "   *** RAISED — this accepts a regression ***" else "")
        | None -> Printf.printf "  re-pin %-22s (new) -> %d\n" g v)
      sensed;
    let tmp = pin_path ^ ".tmp" in
    (match
       try
         let oc = open_out tmp in
         Fun.protect
           ~finally:(fun () -> close_out_noerr oc)
           (fun () ->
             output_string oc
               "# ratchet pins — one gauge per line; re-pinning is a DELIBERATE act.\n";
             List.iter (fun l -> output_string oc (l ^ "\n")) (Ratchet.serialize_pins sensed));
         Some ()
       with _ -> None
     with
    | Some () -> Sys.rename tmp pin_path
    | None ->
        Printf.eprintf "[LX/control-plane control] REFUSED: could not write %s\n" tmp;
        (try Sys.remove tmp with _ -> ());
        exit 1);
    Printf.printf "PINNED %d gauges -> %s (deliberate re-pin; the diff is above)\n"
      (List.length sensed) pin_path;
    exit 0
  end;
  state "Diffing";
  match Ratchet.parse_pins (read_lines pin_path) with
  | Error e ->
      print_endline ("ratchet pins unreadable (fail closed): " ^ e);
      print_endline "run --pin ONCE, deliberately, to establish them";
      exit 1
  | Ok pins -> (
      match Ratchet.evaluate ~pins ~gauges:sensed with
      | Error e ->
          print_endline ("ratchet refuses (fail closed): " ^ e);
          exit 1
      | Ok verdicts -> (
          state "Reporting";
          List.iter
            (fun v ->
              emit (Wiki_otel.of_verdict ~ts:(now_iso ()) v);
              (match v with
              | Ratchet.Breached { gauge; previous; current } ->
                  fractal (Wiki_diagnostics.Ratchet_breach { gauge; previous; current })
              | _ -> ());
              print_endline ("  " ^ Ratchet.render v))
            verdicts;
          match Suppression.parse (read_lines suppression_path) with
          | Error e ->
              print_endline ("suppressions unreadable (fail closed): " ^ e);
              exit 1
          | Ok sups ->
              let today = today () in
              List.iter
                (fun (s : Suppression.t) ->
                  emit
                    (Wiki_otel.record ~ts:(now_iso ()) ~severity:Wiki_otel.Debug
                       ~body:"suppression disclosed"
                       ~attrs:
                         [ ("actor", "auditLoop"); ("kind", s.Suppression.kind);
                           ("key", s.Suppression.key); ("reason", s.Suppression.reason) ]))
                sups;
              List.iter (fun l -> print_endline ("  " ^ l)) (Suppression.disclose sups);
              List.iter
                (fun (s : Suppression.t) ->
                  print_endline ("  EXPIRED suppression (no longer applied): " ^ s.Suppression.key))
                (Suppression.expired sups ~today);
              let active = Suppression.active sups ~today in
              let unsuppressed =
                List.filter
                  (function
                    | Ratchet.Breached { gauge; _ } ->
                        not (Suppression.applies active ~kind:"ratchet_breach" ~key:gauge)
                    | _ -> false)
                  verdicts
              in
              (* the worklist: name what moved, so the breach is actionable *)
              List.iter
                (function
                  | Ratchet.Breached { gauge = "schema_debt"; _ } ->
                      List.iteri
                        (fun i g -> if i < 10 then print_endline ("    gap: " ^ g))
                        (Hermes_wiki.schema_gaps m)
                  | Ratchet.Breached { gauge = "dead_anchors"; _ } ->
                      List.iteri
                        (fun i g -> if i < 10 then print_endline ("    anchor: " ^ g))
                        (Hermes_wiki.broken_anchors m)
                  (* the worklist must show the SAME predicate the gauge
                     counts: this printed `defects` while dead_links counts
                     `unresolved_refs`, so a breach named an unrelated set
                     (often empty) and never showed the actual references *)
                  | Ratchet.Breached { gauge = "dead_links"; _ } ->
                      List.iteri
                        (fun i g -> if i < 10 then print_endline ("    link: " ^ g))
                        (Hermes_wiki.unresolved_refs m)
                  | Ratchet.Breached { gauge = "corpus_defects"; _ } ->
                      List.iteri
                        (fun i g -> if i < 10 then print_endline ("    defect: " ^ g))
                        (Hermes_wiki.defects m)
                  | Ratchet.Breached { gauge = "stale_declarations"; _ } ->
                      List.iter
                        (fun g -> print_endline ("    stale: " ^ g))
                        (Feature_register.stale_declarations ())
                  | _ -> ())
                unsuppressed;
              if unsuppressed = [] then begin
                Printf.printf "wiki-audit: %d gauges, ratchet holds\n" (List.length sensed);
                exit 0
              end
              else begin
                Printf.printf "wiki-audit: RATCHET BREACHED on %d gauge(s)\n"
                  (List.length unsuppressed);
                exit 1
              end))
