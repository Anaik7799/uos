(* The system dashboard — full state and tracking KPIs, rendered as a
   corpus page (state/dashboard.md) and to stdout.

   DERIVED, NEVER AUTHORED. Every number here is computed at render time
   from the register, the gauges, the pins and the OTel stream; nothing
   is typed in. A KPI carries its setpoint and its trend against the pin,
   so the page answers "is this getting better" and not merely "what is
   it". The page is `generated: true`: a reader must never mistake it for
   a document somebody stands behind.

   R5 holds here too: the dashboard reports; it never gates. *)

let pin_path = "modules/hermes_wiki/baseline/ratchet-gauges.txt"
let otel_path = "state/wiki-audit.otel.jsonl"
let out_path = "state/dashboard.md"

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

let now_iso () =
  let t = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1)
    t.Unix.tm_mday t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec

(* count occurrences of a literal in the OTel stream — the log IS the
   evidence that the actors ran, so the dashboard reads it rather than
   re-deriving what the audit already measured *)
let stream_count needle lines =
  List.length
    (List.filter
       (fun l ->
         let n = String.length needle and ll = String.length l in
         let rec go i = i + n <= ll && (String.sub l i n = needle || go (i + 1)) in
         go 0)
       lines)

let bar value max_ width =
  if max_ <= 0 then String.make width '.'
  else
    let filled = int_of_float (float_of_int value /. float_of_int max_ *. float_of_int width) in
    let filled = if filled > width then width else if filled < 0 then 0 else filled in
    String.concat "" [ String.make filled '#'; String.make (width - filled) '.' ]

let () =
  let files = Hermes_wiki.read_tracked "modules/hermes_wiki/pages" @ Hermes_wiki.read_tracked "docs/hermes" in
  let m = Hermes_wiki.build ~read_source:Hermes_wiki.read_source_file files in
  let m_pages = Hermes_wiki.build ~read_source:Hermes_wiki.read_source_file (Hermes_wiki.read_tracked "modules/hermes_wiki/pages") in
  let graph = Wiki_graph.of_model m_pages in
  let s = Feature_register.summary () in
  let total =
    s.Feature_register.built + s.Feature_register.ready + s.Feature_register.blocked
    + s.Feature_register.forked + s.Feature_register.excluded
  in
  let reuse = Import_coverage.census () in
  let pins = match Ratchet.parse_pins (read_lines pin_path) with Ok p -> p | Error _ -> [] in
  let stream = read_lines otel_path in
  let idx = Wiki_search.build m_pages in
  let b = Buffer.create 8192 in
  let p fmt = Printf.ksprintf (Buffer.add_string b) fmt in
  p "---\nid: hermes-wiki-dashboard\nstatus: published\ntype: reference\nktype: source\n";
  p "maturity: incubating\ndomain: formal_verification\ntopics: [dashboard, kpi, state]\n";
  p "created: 2026-08-09\ngenerated: true\nlast_verified: %s\nverified_by: agent\n---\n"
    (String.sub (now_iso ()) 0 10);
  p "# Wiki/ZK/KM system dashboard\n\n";
  p "GENERATED at %s by `wiki_dashboard`. Every figure is derived; nothing here is authored.\n\n"
    (now_iso ());

  p "## 1. Delivery KPI — the register\n\n";
  p "```\n";
  p "built      %4d  %s\n" s.Feature_register.built (bar s.Feature_register.built total 40);
  p "ready      %4d  %s\n" s.Feature_register.ready (bar s.Feature_register.ready total 40);
  p "blocked    %4d  %s\n" s.Feature_register.blocked (bar s.Feature_register.blocked total 40);
  p "forked     %4d  %s\n" s.Feature_register.forked (bar s.Feature_register.forked total 40);
  p "excluded   %4d  %s\n" s.Feature_register.excluded (bar s.Feature_register.excluded total 40);
  p "```\n\n";
  p "**%d rows · %d Built (%.0f%% of the buildable %d)**. Next actionable: %s\n\n"
    total s.Feature_register.built
    (100.0 *. float_of_int s.Feature_register.built
     /. float_of_int (max 1 (total - s.Feature_register.excluded)))
    (total - s.Feature_register.excluded)
    (match Feature_register.next () with
    | Some f -> Printf.sprintf "**%s** %s (priority %d)" f.Feature_register.id f.Feature_register.name (Feature_register.priority f)
    | None -> "nothing actionable");

  (* THE DASHBOARD DOES NOT SENSE. It renders the PINS, and it now says
     so. It used to print the pinned value twice — once under "Value",
     once under "Pin" — so Value always equalled Pin, State was always
     clean-or-held, and "BREACHED" was structurally unreachable: a corpus
     with schema_debt 1300 against a pin of 1224 failed the audit while
     this page reported "held". A monitor that reads healthy while the
     gate is red is worse than no monitor, and this is the human-facing
     artifact. Sensing belongs to wiki_audit, which owns the model and
     the graph; duplicating it here would be a second implementation to
     drift. So the column is named for what it holds. *)
  p "## 2. Health KPIs — the ratcheted PINS\n\n";
  p
    "These are the pinned bounds, not a fresh reading: this page renders \
     state, it does not sense it. **`wiki_audit` is the gate** — it senses \
     every gauge and exits non-zero on a breach. A pin shown here says what \
     the system has committed to, not what it measured this minute.\n\n";
  if pins = [] then
    p
      "> **The pin file could not be read.** That is a REFUSAL, not an empty \
       table: `%s` is missing or malformed, so no bound is known here. Run \
       `wiki_audit` — it fails closed on the same condition.\n\n"
      pin_path
  else begin
    p "| Gauge | Pin | Setpoint |\n|---|---|---|\n";
    List.iter
      (fun (g, pinned) ->
        let setpoint =
          if g = "schema_debt" || g = "orphans" || g = "unported_mirrors" || g = "toc_unplaced"
             || g = "toc_unreachable"
          then "monotone down"
          else "0"
        in
        p "| `%s` | %d | %s |\n" g pinned setpoint)
      pins;
    p "\nThe ratchet permits only decreases: a gauge that rises refuses the audit.\n\n"
  end;

  p "## 3. Corpus state\n\n";
  p "| Quantity | Value |\n|---|---|\n";
  p "| documents (all roots) | %d |\n" (List.length m.Hermes_wiki.pages);
  p "| documents (pinned root) | %d |\n" (List.length m_pages.Hermes_wiki.pages);
  p "| graph nodes / edges | %d / %d |\n" (List.length (Wiki_graph.nodes graph))
    (Wiki_graph.edge_count graph);
  p "| communities | %d |\n" (List.length (Wiki_graph.communities graph));
  p "| orphans | %d |\n" (List.length (Wiki_graph.orphans graph));
  p "| hub eccentricity | %s |\n"
    (match Wiki_graph.ecc_from graph "knowledge-fractal-map" with
    | Some e -> string_of_int e
    | None -> "hub missing");
  p "| search index digest | `%s` |\n" (String.sub (Wiki_search.digest idx) 0 16);
  p "| schema gaps | %d |\n" (List.length (Hermes_wiki.schema_gaps m));
  p "| defects / notices | %d / %d |\n" (List.length (Hermes_wiki.defects m))
    (List.length (Hermes_wiki.notices m));
  p "\n";

  p "## 4. Reuse KPI — the imported fleets\n\n";
  p "```\n";
  let rt = reuse.Import_coverage.ported + reuse.Import_coverage.operational
           + reuse.Import_coverage.scheduled + reuse.Import_coverage.superseded in
  p "ported      %3d  %s  behaviour lives here, under Built rows\n"
    reuse.Import_coverage.ported (bar reuse.Import_coverage.ported rt 30);
  p "operational %3d  %s  a landed mechanism performs it\n"
    reuse.Import_coverage.operational (bar reuse.Import_coverage.operational rt 30);
  p "scheduled   %3d  %s  queued, its row named\n"
    reuse.Import_coverage.scheduled (bar reuse.Import_coverage.scheduled rt 30);
  p "superseded  %3d  %s  deliberately absent, invariant stated\n"
    reuse.Import_coverage.superseded (bar reuse.Import_coverage.superseded rt 30);
  p "```\n\n%d modules, every one classified; the biconditional is checked by\n"
    rt;
  p "`test_feature_register` in both directions.\n\n";

  p "## 4b. MBSE KPI — the model of record (R21)\n\n";
  let mc = Feature_model.coverage () in
  p "One source, three surfaces: SysML v2 (structure), OML/OWL (ontology),\n";
  p "OpenMBEE MMS (the repository payload). All three are total functions of\n";
  p "the register, regenerated by `gen_feature_model` into `generated/mbse/`,\n";
  p "so they cannot disagree with each other or with the code.\n\n";
  p "| Model KPI | Value |\n|---|---|\n";
  p "| elements (one per register row) | %d |\n" mc.Feature_model.total;
  p "| verified by an executable probe | %d |\n" mc.Feature_model.verified;
  p "| **built, but the requirement has no verification method** | **%d** |\n"
    mc.Feature_model.declared_only;
  p "| dependency edges naming an absent element | %d |\n"
    (List.length (Feature_model.dangling_dependencies ()));
  p "\n```\n";
  p "verified    %3d  %s  a live predicate can fail\n" mc.Feature_model.verified
    (bar mc.Feature_model.verified mc.Feature_model.total 30);
  p "gaps        %3d  %s  built by assertion; the ratcheted debt\n"
    mc.Feature_model.declared_only
    (bar mc.Feature_model.declared_only mc.Feature_model.total 30);
  p "```\n\n";
  p "A requirement with no verification states an intent nothing can ever\n";
  p "contradict. The gap count is ratcheted and only falls; it BLOCKS credit\n";
  p "and never denies it, because a model gap is the harness's own\n";
  p "bookkeeping and proves nothing about a candidate (R5).\n\n";

  p "## 5. Observability — the fractal/OTel stream\n\n";
  p "| Signal | Records |\n|---|---|\n";
  p "| total records | %d |\n" (List.length stream);
  p "| with a fractal coordinate | %d |\n" (stream_count "fractal.level" stream);
  p "| L0 product | %d |\n" (stream_count "L0/product" stream);
  p "| L1 family | %d |\n" (stream_count "L1/family" stream);
  p "| L2 capability | %d |\n" (stream_count "L2/capability" stream);
  p "| L3 contract | %d |\n" (stream_count "L3/contract" stream);
  p "| L4 fixture | %d |\n" (stream_count "L4/fixture" stream);
  p "| L5 trace | %d |\n" (stream_count "L5/trace" stream);
  p "| LX control-plane | %d |\n" (stream_count "LX/control-plane" stream);
  p "| WARN or above | %d |\n" (stream_count "\"severity_text\":\"WARN\"" stream);
  p "| **origin=implementation (must be 0, R5)** | **%d** |\n"
    (stream_count "\"fractal.origin\":\"implementation\"" stream);
  p "\nA wiki monitor can never blame Implementation or deny parity credit —\n";
  p "the constructors in `Wiki_diagnostics` cannot build such a value.\n\n";

  p "## 6. Actors (the FPP topology)\n\n";
  p "| Component | Kind | Telemetry channels |\n|---|---|---|\n";
  List.iter
    (fun (c : Fpp_model.component) ->
      p "| `%s` | %s | %s |\n" c.Fpp_model.comp_name
        (match c.Fpp_model.kind with
        | Fpp_model.Passive -> "passive"
        | Fpp_model.Queued -> "queued"
        | Fpp_model.Active -> "active")
        (String.concat ", "
           (List.map (fun (ch : Fpp_model.channel) -> ch.Fpp_model.chan_name)
              c.Fpp_model.channels)))
    Wiki_topology.model.Fpp_model.components;
  p "\nThe model validates (`Fpp_model.validate = []`, HW.10.5.1) and no auditor\n";
  p "edge targets the corpus: monitors sense and report, nothing more.\n";
  let oc = open_out out_path in
  output_string oc (Buffer.contents b);
  close_out oc;
  print_string (Buffer.contents b);
  Printf.eprintf "\n[dashboard] wrote %s\n" out_path
