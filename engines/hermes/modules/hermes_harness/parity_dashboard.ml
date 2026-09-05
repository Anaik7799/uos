(* Generate the parity KPI dashboard as a self-contained HTML page.

   The dashboard is the OBSERVE surface of the harness's OODA loop: at a glance,
   how much parity is proven, where the evidence sits on the fractal chain, and
   what is still uncovered. It is generated from the harness's own data -- the
   capability catalog, the hazard analysis, the ontology, the countermeasures,
   and the static analysis of the frozen reference -- so it cannot drift from the
   code the way a hand-maintained status page would.

   [render] is pure over a [kpi] record so it is testable without touching the
   filesystem; [generate] does the IO to assemble the record, then renders. The
   HTML is assembled with a Buffer, not Printf, because the CSS is full of literal
   percent signs that a format string would try to interpret. *)

type kpi = {
  hermes : Hermes_analysis.summary;
  fixtures : int;
  verified : int;
  total_scenarios : int;
  covered_slices : int;
  families_verified : int;   (* L1 families verified end to end -- strict parity *)
  snapshot : string;
  slice_verdicts : (string * Parity_algebra.verdict) list;  (* per covered L2 node *)
  contracts_declared : int;  (* L3 obligations in the contract catalog *)
  control : string list;  (* rendered control-plane sweep lines (may be empty) *)
}

(* --------------------------------------------------------- pure KPI maths *)

let families () =
  List.fold_left
    (fun acc (capability : Capability_catalog.capability) ->
      if List.mem_assoc capability.family_id acc then
        List.map
          (fun (family, count) ->
            if family = capability.family_id then (family, count + 1) else (family, count))
          acc
      else acc @ [ (capability.family_id, 1) ])
    [] Capability_catalog.all

let percent numerator denominator =
  if denominator = 0 then 0 else numerator * 100 / denominator

(* Derive every KPI from the store's latest (contract_id, passed) rows -- the
   dashboard follows the evidence, never leads it. (The F-SW-1/F-OH-2/F-L0-1
   fix: the previous hand-frozen constants could keep showing green through a
   candidate regression.) Pure, so the derivation is differentially testable:
   different evidence MUST yield different numbers. *)
let kpi_of_rows ~hermes ~fixtures ~snapshot ~contracts_declared ~control ~rows =
  let slice_verdicts = Evidence_rollup.per_node rows in
  let family_verdicts =
    Evidence_rollup.family_verdicts ~catalog:Parity_intent.family_catalog
      ~nodes:slice_verdicts
  in
  let families_verified =
    List.length
      (List.filter
         (fun (node, verdict) ->
           node <> "hermes" && verdict = Parity_algebra.Verified)
         family_verdicts)
  in
  { hermes; fixtures;
    verified = List.length (List.filter snd rows);
    total_scenarios = List.length rows;
    covered_slices = List.length slice_verdicts;
    families_verified; snapshot; slice_verdicts; contracts_declared; control }

(* ------------------------------------------------------------- rendering *)

let escape text =
  let buffer = Buffer.create (String.length text) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string buffer "&amp;"
      | '<' -> Buffer.add_string buffer "&lt;"
      | '>' -> Buffer.add_string buffer "&gt;"
      | '"' -> Buffer.add_string buffer "&quot;"
      | c -> Buffer.add_char buffer c)
    text;
  Buffer.contents buffer

let card ~label ~value ~note =
  "<div class=\"card\"><div class=\"card-label\">" ^ escape label
  ^ "</div><div class=\"card-value\">" ^ escape value ^ "</div><div class=\"card-note\">"
  ^ escape note ^ "</div></div>"

let fractal_strip kpi =
  let slices = List.length Capability_catalog.all in
  let levels =
    [ ("L0", "product", "1");
      ("L1", "family", string_of_int (List.length (families ())));
      ("L2", "capability", string_of_int slices);
      ("L3", "contract", string_of_int kpi.contracts_declared ^ " declared");
      ("L4", "fixture", string_of_int kpi.fixtures);
      ("L5", "trace", "normalized");
      ("L6", "receipt", string_of_int kpi.verified) ]
  in
  let chip (level, name, count) =
    "<div class=\"level\"><div class=\"level-id\">" ^ level ^ "</div><div class=\"level-name\">"
    ^ name ^ "</div><div class=\"level-count\">" ^ count ^ "</div></div>"
  in
  "<div class=\"strip\">"
  ^ String.concat "<div class=\"arrow\">\xe2\x86\x92</div>" (List.map chip levels)
  ^ "</div>"

(* Family evidence derived from the per-slice verdicts, never asserted: the
   pill is ok only when EVERY slice of the family is Verified (the same
   vacuous-truth guard the roll-up applies), and partial coverage says exactly
   how partial it is. *)
let family_rows kpi =
  List.map
    (fun (family, capability_nodes) ->
      let total = List.length capability_nodes in
      let verdict_of node = List.assoc_opt node kpi.slice_verdicts in
      let verified_count =
        List.length
          (List.filter
             (fun node -> verdict_of node = Some Parity_algebra.Verified)
             capability_nodes)
      in
      let short node =
        match String.rindex_opt node '.' with
        | Some i -> String.sub node (i + 1) (String.length node - i - 1)
        | None -> node
      in
      (* Name every covered capability; a covered-but-unverified slice is
         marked so a regression is visible by name, not just by count. *)
      let covered_names =
        List.filter_map
          (fun node ->
            match verdict_of node with
            | Some Parity_algebra.Verified -> Some (short node)
            | Some _ -> Some (short node ^ " !")
            | None -> None)
          capability_nodes
      in
      let names = String.concat ", " covered_names in
      let evidence, cls =
        if total > 0 && verified_count = total then
          ("VERIFIED \xe2\x80\x94 all " ^ string_of_int total ^ " slices: " ^ names,
           "pill ok")
        else if covered_names <> [] then
          (string_of_int verified_count ^ "/" ^ string_of_int total
           ^ " slices verified: " ^ names, "pill none")
        else ("no differential evidence", "pill none")
      in
      "<tr><td class=\"fam\">" ^ escape family ^ "</td><td class=\"num\">"
      ^ string_of_int total ^ "</td><td><span class=\"" ^ cls ^ "\">" ^ evidence
      ^ "</span></td></tr>")
    Parity_intent.family_catalog

(* CSS lives in a raw string (literal % is fine here -- it never goes through a
   format string). Token-driven so both themes get equal care: media query for
   the OS default, [data-theme] overrides for the viewer's explicit toggle. *)
let style =
  {|
:root{
  --bg:#f4f7f8; --panel:#ffffff; --ink:#0d1417; --muted:#5b6b70; --line:#dbe4e6;
  --accent:#0f8b8b; --accent-weak:#e2f1f0;
  --ok:#2f9e6b; --none:#8a999e;
  --shadow:0 1px 2px rgba(13,20,23,.06),0 2px 8px rgba(13,20,23,.05);
}
@media (prefers-color-scheme:dark){:root{
  --bg:#0d1417; --panel:#141d21; --ink:#e8eef0; --muted:#8ea1a6; --line:#243136;
  --accent:#34c3c0; --accent-weak:#0f2a2b; --ok:#3fbb84; --none:#5d6f74;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 2px 10px rgba(0,0,0,.3);
}}
:root[data-theme="light"]{
  --bg:#f4f7f8; --panel:#ffffff; --ink:#0d1417; --muted:#5b6b70; --line:#dbe4e6;
  --accent:#0f8b8b; --accent-weak:#e2f1f0; --ok:#2f9e6b; --none:#8a999e;
  --shadow:0 1px 2px rgba(13,20,23,.06),0 2px 8px rgba(13,20,23,.05);
}
:root[data-theme="dark"]{
  --bg:#0d1417; --panel:#141d21; --ink:#e8eef0; --muted:#8ea1a6; --line:#243136;
  --accent:#34c3c0; --accent-weak:#0f2a2b; --ok:#3fbb84; --none:#5d6f74;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 2px 10px rgba(0,0,0,.3);
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
  font-family:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
  line-height:1.5;-webkit-font-smoothing:antialiased}
.wrap{max-width:1040px;margin:0 auto;padding:2.5rem 1.5rem 4rem}
.eyebrow{text-transform:uppercase;letter-spacing:.14em;font-size:.72rem;font-weight:600;color:var(--accent)}
h1{font-size:clamp(1.6rem,3vw,2.2rem);margin:.2rem 0 .3rem;letter-spacing:-.02em;text-wrap:balance}
.sub{color:var(--muted);margin:0 0 2rem;max-width:60ch}
.mono{font-family:ui-monospace,"SF Mono",Menlo,Consolas,monospace}
.num{font-variant-numeric:tabular-nums}
.band{display:grid;grid-template-columns:1fr 1fr;gap:1rem;margin-bottom:1.5rem}
@media (max-width:640px){.band{grid-template-columns:1fr}}
.hero{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:1.5rem;box-shadow:var(--shadow)}
.hero .big{font-size:2.8rem;font-weight:700;letter-spacing:-.03em;line-height:1;font-variant-numeric:tabular-nums}
.hero .cap{color:var(--muted);font-size:.9rem;margin-top:.5rem}
.hero.good .big{color:var(--ok)}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:1rem;margin:1.5rem 0}
@media (max-width:760px){.grid{grid-template-columns:repeat(2,1fr)}}
@media (max-width:460px){.grid{grid-template-columns:1fr}}
.card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:1.1rem;box-shadow:var(--shadow)}
.card-label{text-transform:uppercase;letter-spacing:.08em;font-size:.68rem;color:var(--muted);font-weight:600}
.card-value{font-size:1.7rem;font-weight:650;margin:.35rem 0 .1rem;letter-spacing:-.02em;font-variant-numeric:tabular-nums}
.card-note{font-size:.82rem;color:var(--muted)}
h2{font-size:.8rem;text-transform:uppercase;letter-spacing:.1em;color:var(--muted);margin:2.2rem 0 .8rem;font-weight:600}
.strip{display:flex;align-items:stretch;gap:.4rem;overflow-x:auto;padding:.4rem 0}
.level{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:.7rem .9rem;min-width:96px;flex:1}
.level-id{font-weight:700;color:var(--accent);font-size:1rem}
.level-name{font-size:.72rem;color:var(--muted);text-transform:uppercase;letter-spacing:.06em}
.level-count{font-size:1.1rem;margin-top:.25rem;font-variant-numeric:tabular-nums}
.arrow{display:flex;align-items:center;color:var(--muted);font-size:1.1rem;flex:0 0 auto}
.tablewrap{overflow-x:auto;border:1px solid var(--line);border-radius:12px;background:var(--panel);box-shadow:var(--shadow)}
table{border-collapse:collapse;width:100%;font-size:.9rem}
th,td{text-align:left;padding:.6rem .9rem;border-bottom:1px solid var(--line)}
th{font-size:.7rem;text-transform:uppercase;letter-spacing:.08em;color:var(--muted);font-weight:600}
tr:last-child td{border-bottom:none}
td.fam{font-weight:550}
td.num{font-variant-numeric:tabular-nums;color:var(--muted);width:5rem}
.pill{display:inline-block;padding:.15rem .6rem;border-radius:999px;font-size:.76rem;font-weight:600}
.pill.ok{background:var(--accent-weak);color:var(--accent)}
.pill.none{background:transparent;color:var(--none);border:1px solid var(--line)}
.controlpre{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:1rem;overflow-x:auto;font-size:.85rem;line-height:1.5;box-shadow:var(--shadow)}
.foot{margin-top:2.5rem;color:var(--muted);font-size:.8rem;border-top:1px solid var(--line);padding-top:1rem}
.foot .mono{color:var(--ink)}
|}

let render kpi =
  let slices = List.length Capability_catalog.all in
  let family_count = List.length (families ()) in
  let hazards = List.length Fractal_diagnostic.hazards in
  let h1 = List.length (Fractal_diagnostic.realising_h1 ()) in
  let components = List.length Fractal_ontology.components in
  let aspects = List.length Fractal_ontology.aspects in
  let countermeasures = List.length Fractal_countermeasures.countermeasures in
  let strict_pct = percent kpi.families_verified family_count in
  let scenario_pct = percent kpi.verified kpi.total_scenarios in
  let h = kpi.hermes in
  let b = Buffer.create 16384 in
  let add = Buffer.add_string b in
  add "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n";
  add "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  add "<title>Hermes Parity Harness \xe2\x80\x94 KPI Dashboard</title>\n<style>";
  add style;
  add "</style>\n</head>\n<body>\n<div class=\"wrap\">\n";
  add "<div class=\"eyebrow\">Hermes parity harness</div>\n";
  add "<h1>Differential parity, on the fractal evidence chain</h1>\n";
  add "<p class=\"sub\">Proving an OCaml candidate matches the frozen Python reference. \
       Only L4\xe2\x80\x93L6 differential evidence grants parity \xe2\x80\x94 catalogs, \
       contracts and source presence do not.</p>\n";
  add "<div class=\"band\">\n";
  add ("<div class=\"hero\"><div class=\"big num\">" ^ string_of_int strict_pct
       ^ "%</div><div class=\"cap\">Strict parity: " ^ string_of_int kpi.families_verified ^ " of "
       ^ string_of_int family_count
       ^ " L1 families verified end to end. Parity moves only when a whole family does.</div></div>\n");
  add ("<div class=\"hero good\"><div class=\"big num\">" ^ string_of_int kpi.verified ^ "/"
       ^ string_of_int kpi.total_scenarios
       ^ "</div><div class=\"cap\">Differential scenarios verified against the frozen \
          reference, " ^ string_of_int scenario_pct
       ^ "% across " ^ string_of_int kpi.covered_slices ^ " covered slices, "
       ^ string_of_int (kpi.total_scenarios - kpi.verified)
       ^ " open divergences. " ^ string_of_int kpi.families_verified ^ " of "
       ^ string_of_int family_count ^ " families fully verified.</div></div>\n");
  add "</div>\n<div class=\"grid\">\n";
  add (card ~label:"Capability coverage"
         ~value:(string_of_int kpi.covered_slices ^ " / " ^ string_of_int slices)
         ~note:("L2 slices with evidence, across " ^ string_of_int family_count ^ " families"));
  add (card ~label:"Differential fixtures" ~value:(string_of_int kpi.fixtures)
         ~note:"pinned reference traces (L4)");
  add (card ~label:"Hazards analysed" ~value:(string_of_int hazards)
         ~note:(string_of_int h1 ^ " realise H-1 (false-parity)"));
  add (card ~label:"Countermeasures" ~value:(string_of_int countermeasures)
         ~note:"one per H-1-adjacent & resource hazard");
  add (card ~label:"Ontology" ~value:(string_of_int components ^ " \xc3\x97 " ^ string_of_int aspects)
         ~note:"components x engineering aspects");
  add (card ~label:"Frozen reference" ~value:(string_of_int h.Hermes_analysis.files ^ " files")
         ~note:(string_of_int h.Hermes_analysis.lines ^ " lines, "
               ^ string_of_int h.Hermes_analysis.defs ^ " defs, "
               ^ string_of_int h.Hermes_analysis.classes ^ " classes"));
  add "</div>\n<h2>Fractal evidence chain</h2>\n";
  add (fractal_strip kpi);
  add "\n<h2>Capability coverage by family</h2>\n";
  add "<div class=\"tablewrap\"><table><thead><tr><th>Family</th><th>Slices</th>\
       <th>Differential evidence</th></tr></thead><tbody>\n";
  List.iter (fun row -> add row; add "\n") (family_rows kpi);
  add "</tbody></table></div>\n";
  if kpi.control <> [] then begin
    add "<h2>Control plane (fractal sweep)</h2>\n<pre class=\"controlpre\">";
    List.iter (fun line -> add (escape line); add "\n") kpi.control;
    add "</pre>\n"
  end;
  add "<div class=\"foot\">Generated by <span class=\"mono\">parity_dashboard.ml</span> from \
       the harness's own data \xe2\x80\x94 capability catalog, hazard analysis, ontology, \
       countermeasures, and static analysis of the frozen reference.<br>";
  add ("Frozen snapshot <span class=\"mono\">" ^ escape kpi.snapshot ^ "</span>. "
       ^ string_of_int kpi.covered_slices ^ " covered of " ^ string_of_int slices
       ^ " L2 slices.</div>\n");
  add "</div>\n</body>\n</html>\n";
  Buffer.contents b

(* ------------------------------------------------------------------- IO *)

let count_fixtures ~root =
  let dir = Filename.concat root "modules/hermes_harness/fixtures/reference_traces" in
  match Sys.readdir dir with
  | exception Sys_error _ -> 0
  | entries ->
      Array.fold_left
        (fun n name -> if Filename.check_suffix name ".json" then n + 1 else n)
        0 entries

let git_revision root =
  let command = "git -C " ^ Filename.quote root ^ " rev-parse HEAD" in
  try
    let channel = Unix.open_process_in command in
    Fun.protect
      ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> String.trim (input_line channel))
  with _ -> "unknown"

let generate ~root =
  let hermes = Hermes_analysis.analyze ~root:(Filename.concat root "external/hermes_source") in
  let fixtures = count_fixtures ~root in
  (* Every KPI is read from the evidence store's latest receipts -- the
     dashboard can no longer assert what the store has not granted (R10 at the
     reporting layer). An unreadable store refuses instead of rendering. *)
  let store_path = Filename.concat root "state/hermes_harness.sqlite3" in
  match Evidence_store.open_db ~path:store_path with
  | Error message -> Error ("dashboard: " ^ message)
  | Ok store ->
      let outcome =
        match Evidence_store.latest_snapshot store with
        | Error message -> Error ("dashboard: " ^ message)
        | Ok snapshot_opt -> (
            let rows_result =
              match snapshot_opt with
              | None -> Ok []
              | Some digest -> Evidence_store.parity_results store ~snapshot_digest:digest
            in
            match rows_result with
            | Error message -> Error ("dashboard: " ^ message)
            | Ok rows ->
                let snapshot =
                  match snapshot_opt with
                  | Some digest -> digest
                  | None -> "(no snapshot recorded)"
                in
                (* Store-only control sweep: the legs derivable from receipts
                   alone; the run-command-owned legs are listed unsensed --
                   never silently omitted. *)
                let history =
                  match snapshot_opt with
                  | None -> []
                  | Some digest -> (
                      match Evidence_store.parity_history store ~snapshot_digest:digest with
                      | Ok h -> h
                      | Error _ -> [])
                in
                let frontier_counts =
                  match snapshot_opt with
                  | None -> []
                  | Some digest -> (
                      match Evidence_store.evolution_history store ~snapshot_digest:digest with
                      | Error _ -> []
                      | Ok entries ->
                          List.map
                            (fun (row : Evidence_store.evolution) ->
                              let s = row.Evidence_store.satisfied in
                              if s = "" then 0
                              else List.length (String.split_on_char ',' s))
                            entries)
                in
                let receipts_revision =
                  match snapshot_opt with
                  | None -> None
                  | Some digest -> (
                      match
                        Evidence_store.latest_receipt_revision store ~snapshot_digest:digest
                      with
                      | Ok revision -> revision
                      | Error _ -> None)
                in
                let sweep =
                  Control_plane.
                    { legs =
                        [ l0_frontier ~counts:frontier_counts
                            ~total:(List.length Parity_intent.blueprint);
                          l1_regressions ~history;
                          l2_flaps ~history;
                          l4_receipt_currency ~receipts_revision
                            ~current:(git_revision root) ];
                      unsensed =
                        [ ("L3 contract", "oracle probed by the run commands");
                          ("L5 trace", "normalizer-version sensor queued");
                          ("L6 receipt", "corpus size is a run-command input");
                          ("LX control", "preflight belongs to the run commands") ] }
                in
                Ok
                  (render
                     (kpi_of_rows ~hermes ~fixtures ~snapshot
                        ~contracts_declared:(List.length Contract_catalog.all)
                        ~control:(Control_plane.render sweep)
                        ~rows)))
      in
      Evidence_store.close store;
      outcome
