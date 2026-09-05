(* The static site. See site_build.mli.

   One hub (index.html) reaching every component, use case, operational
   surface, KPI, wiki/ZK note and analytic. Pure: a function of the read
   model and the doc tree. Self-contained: inline CSS, inline SVG charts,
   no external hosts, no scripts, no forms — the read-only law made
   structural (a site that cannot POST cannot write evidence). *)

type t = {
  model : Web_read_model.t;
  wiki : Hermes_wiki.model;
  pages : (string * string) list;
}

let esc = Printf.sprintf

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

let style =
  "<style>\
   :root{--bg:#0f1216;--panel:#171b21;--line:#232a33;--ink:#e6edf3;--dim:#8b97a6;\
   --ok:#3fb950;--warn:#d29922;--bad:#f85149;--acc:#58a6ff}\
   *{box-sizing:border-box}\
   body{margin:0;background:var(--bg);color:var(--ink);\
   font:14px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace}\
   header{padding:18px 24px;border-bottom:1px solid var(--line);\
   display:flex;gap:18px;align-items:baseline;flex-wrap:wrap}\
   header h1{font-size:16px;margin:0;letter-spacing:.02em}\
   header nav a{color:var(--dim);text-decoration:none;margin-right:14px}\
   header nav a:hover{color:var(--acc)}\
   main{padding:24px;max-width:1180px}\
   h2{font-size:14px;color:var(--dim);text-transform:uppercase;\
   letter-spacing:.08em;margin:28px 0 12px;font-weight:600}\
   .kpi{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}\
   .kpi div{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:14px}\
   .kpi b{display:block;font-size:26px;line-height:1.15;overflow-wrap:anywhere;word-break:break-word}\
   .kpi span{color:var(--dim);font-size:11px;text-transform:uppercase;letter-spacing:.06em}\
   .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:10px}\
   .card{background:var(--panel);border:1px solid var(--line);border-radius:8px;\
   padding:12px;display:block;color:inherit;text-decoration:none}\
   .card:hover{border-color:var(--acc)}\
   .card b{display:block;margin-bottom:4px}\
   .card small{color:var(--dim)}\
   table{border-collapse:collapse;width:100%;font-size:13px;overflow-x:auto;display:block}\
   th,td{border-bottom:1px solid var(--line);padding:7px 10px;text-align:left;vertical-align:top}\
   th{color:var(--dim);font-weight:600;font-size:11px;text-transform:uppercase}\
   .ok{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad)}\
   a{color:var(--acc)}.missing{color:var(--bad);border-bottom:1px dotted var(--bad)}\
   pre{background:var(--panel);border:1px solid var(--line);border-radius:8px;\
   padding:12px;overflow-x:auto}code{color:#a5d6ff}\
   blockquote{border-left:3px solid var(--line);margin:0;padding-left:12px;color:var(--dim)}\
   svg{background:var(--panel);border:1px solid var(--line);border-radius:8px}\
   .tag{display:inline-block;background:var(--line);border-radius:99px;\
   padding:1px 9px;font-size:11px;margin-right:5px;color:var(--dim)}\
   footer{padding:20px 24px;color:var(--dim);border-top:1px solid var(--line);font-size:12px}\
   </style>"

let shell ~title ~body =
  esc
    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">\
     <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\
     <title>%s — Hermes harness</title>%s</head><body>\
     <header><h1>Hermes harness</h1><nav>\
     <a href=\"index.html\">index</a><a href=\"dashboard.html\">dashboard</a>\
     <a href=\"components.html\">components</a><a href=\"usecases.html\">use cases</a>\
     <a href=\"operations.html\">operations</a><a href=\"analytics.html\">analytics</a>\
     <a href=\"wiki.html\">wiki</a><a href=\"zk.html\">zk graph</a>\
     <a href=\"atlas.html\">atlas</a><a href=\"plan.html\">plan</a>\
     </nav></header><main>%s</main>\
     <footer>Derived from the live registries and the evidence store. \
     Read-only by construction: no forms, no writes, no external assets.</footer>\
     </body></html>"
    (escape title) style body

let grade_name = function
  | 5 -> "machine-checked" | 4 -> "solver-proved" | 3 -> "differential"
  | 2 -> "property" | 1 -> "contracted" | _ -> "declared"

let grade_class g = if g >= 4 then "ok" else if g >= 2 then "warn" else "bad"

(* ------------------------------------------------------------- charts *)

let bar_chart ~title ~items ~width =
  let n = List.length items in
  if n = 0 then "" else
  let max_value =
    List.fold_left (fun acc (_, v) -> max acc v) 1 items |> float_of_int
  in
  let row_h = 20 in
  let height = (n * row_h) + 34 in
  let label_w = 210 in
  let buffer = Buffer.create 4096 in
  Buffer.add_string buffer
    (esc "<svg viewBox=\"0 0 %d %d\" width=\"100%%\" height=\"%d\" role=\"img\" aria-label=\"%s\">"
       width height height (escape title));
  Buffer.add_string buffer
    (esc "<text x=\"12\" y=\"20\" fill=\"#8b97a6\" font-size=\"12\">%s</text>" (escape title));
  List.iteri
    (fun i (label, value) ->
      let y = 32 + (i * row_h) in
      let w =
        int_of_float (float_of_int value /. max_value *. float_of_int (width - label_w - 60))
      in
      Buffer.add_string buffer
        (esc "<text x=\"12\" y=\"%d\" fill=\"#e6edf3\" font-size=\"11\">%s</text>"
           (y + 12) (escape label));
      Buffer.add_string buffer
        (esc "<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"11\" rx=\"3\" fill=\"#58a6ff\" opacity=\"0.75\"/>"
           label_w (y + 3) (max w 1));
      Buffer.add_string buffer
        (esc "<text x=\"%d\" y=\"%d\" fill=\"#8b97a6\" font-size=\"11\">%d</text>"
           (label_w + max w 1 + 8) (y + 12) value))
    items;
  Buffer.add_string buffer "</svg>";
  Buffer.contents buffer

let stacked_levels levels =
  let n = List.length levels in
  (* The width must FIT the widest row: a level with many components used
     to overflow the viewBox and clip its own count (found by rendering
     the page in a real browser, not by reading the markup). *)
  let unit = 26 in
  let widest = List.fold_left (fun acc (_, total, _) -> max acc total) 1 levels in
  let width = 200 + (widest * unit) + 90 in
  if n = 0 then "" else
  let height = (n * 22) + 34 in
  let buffer = Buffer.create 2048 in
  Buffer.add_string buffer
    (esc "<svg viewBox=\"0 0 %d %d\" width=\"100%%\" height=\"%d\" role=\"img\" aria-label=\"level coverage\">"
       width height height);
  Buffer.add_string buffer
    "<text x=\"12\" y=\"20\" fill=\"#8b97a6\" font-size=\"12\">fractal level coverage (covered / total)</text>";
  List.iteri
    (fun i (level, total, covered) ->
      let y = 30 + (i * 22) in
      Buffer.add_string buffer
        (esc "<text x=\"12\" y=\"%d\" fill=\"#e6edf3\" font-size=\"11\">%s</text>" (y + 12)
           (escape level));
      for k = 0 to total - 1 do
        let color = if k < covered then "#3fb950" else "#f85149" in
        Buffer.add_string buffer
          (esc "<rect x=\"%d\" y=\"%d\" width=\"20\" height=\"12\" rx=\"2\" fill=\"%s\"/>"
             (200 + (k * unit)) (y + 2) color)
      done;
      Buffer.add_string buffer
        (esc "<text x=\"%d\" y=\"%d\" fill=\"#8b97a6\" font-size=\"11\">%d/%d</text>"
           (200 + (total * unit) + 8) (y + 12) covered total))
    levels;
  Buffer.add_string buffer "</svg>";
  Buffer.contents buffer

let donut ~verified ~divergent ~blocked ~unmapped =
  let total = max 1 (verified + divergent + blocked + unmapped) in
  let segments =
    [ ("verified", verified, "#3fb950"); ("divergent", divergent, "#f85149");
      ("blocked", blocked, "#d29922"); ("unmapped", unmapped, "#8b97a6") ]
  in
  let cx = 90. and cy = 90. and r = 62. in
  let buffer = Buffer.create 2048 in
  Buffer.add_string buffer
    "<svg viewBox=\"0 0 380 180\" width=\"100%\" height=\"180\" role=\"img\" aria-label=\"parity mix\">";
  let angle = ref (-.Float.pi /. 2.) in
  List.iter
    (fun (label, value, color) ->
      if value > 0 then begin
        let sweep = 2. *. Float.pi *. (float_of_int value /. float_of_int total) in
        let x1 = cx +. (r *. cos !angle) and y1 = cy +. (r *. sin !angle) in
        let a2 = !angle +. sweep in
        let x2 = cx +. (r *. cos a2) and y2 = cy +. (r *. sin a2) in
        let large = if sweep > Float.pi then 1 else 0 in
        Buffer.add_string buffer
          (esc
             "<path d=\"M %.2f %.2f L %.2f %.2f A %.2f %.2f 0 %d 1 %.2f %.2f Z\" fill=\"%s\" opacity=\"0.85\"/>"
             cx cy x1 y1 r r large x2 y2 color);
        angle := a2;
        ignore label
      end)
    segments;
  Buffer.add_string buffer
    (esc "<circle cx=\"%.0f\" cy=\"%.0f\" r=\"36\" fill=\"#171b21\"/>" cx cy);
  Buffer.add_string buffer
    (esc "<text x=\"%.0f\" y=\"%.0f\" fill=\"#e6edf3\" font-size=\"18\" text-anchor=\"middle\">%d</text>"
       cx (cy +. 2.) verified);
  Buffer.add_string buffer
    (esc "<text x=\"%.0f\" y=\"%.0f\" fill=\"#8b97a6\" font-size=\"10\" text-anchor=\"middle\">verified</text>"
       cx (cy +. 18.));
  List.iteri
    (fun i (label, value, color) ->
      let y = 40 + (i * 24) in
      Buffer.add_string buffer
        (esc "<rect x=\"196\" y=\"%d\" width=\"12\" height=\"12\" rx=\"2\" fill=\"%s\"/>" y color);
      Buffer.add_string buffer
        (esc "<text x=\"216\" y=\"%d\" fill=\"#e6edf3\" font-size=\"12\">%s %d</text>"
           (y + 11) (escape label) value))
    segments;
  Buffer.add_string buffer "</svg>";
  Buffer.contents buffer

(* The ZK / ontology graph, laid out on a circle (deterministic geometry —
   no randomness, no clock: the determinism law covers the charts too). *)
let graph_svg ~nodes ~edges =
  let n = List.length nodes in
  if n = 0 then "" else
  let size = 760. in
  let cx = size /. 2. and cy = size /. 2. and r = (size /. 2.) -. 90. in
  let position i =
    let a = 2. *. Float.pi *. (float_of_int i /. float_of_int n) -. (Float.pi /. 2.) in
    (cx +. (r *. cos a), cy +. (r *. sin a))
  in
  let index_of name =
    let rec go i = function
      | [] -> None
      | x :: rest -> if x = name then Some i else go (i + 1) rest
    in
    go 0 nodes
  in
  let buffer = Buffer.create 16384 in
  Buffer.add_string buffer
    (esc "<svg viewBox=\"0 0 %.0f %.0f\" width=\"100%%\" height=\"720\" role=\"img\" aria-label=\"graph\">"
       size size);
  List.iter
    (fun (a, b, kind) ->
      match (index_of a, index_of b) with
      | Some ia, Some ib ->
          let x1, y1 = position ia and x2, y2 = position ib in
          let color =
            match kind with
            | "derives_from" -> "#58a6ff" | "governs" -> "#3fb950"
            | "constrains" -> "#d29922" | _ -> "#8b97a6"
          in
          Buffer.add_string buffer
            (esc
               "<line x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\" stroke=\"%s\" stroke-width=\"1\" opacity=\"0.45\"/>"
               x1 y1 x2 y2 color)
      | _ -> ())
    edges;
  List.iteri
    (fun i name ->
      let x, y = position i in
      Buffer.add_string buffer
        (esc "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"5\" fill=\"#58a6ff\"/>" x y);
      let anchor = if x < cx then "end" else "start" in
      let dx = if x < cx then -9. else 9. in
      Buffer.add_string buffer
        (esc
           "<text x=\"%.1f\" y=\"%.1f\" fill=\"#e6edf3\" font-size=\"10\" text-anchor=\"%s\">%s</text>"
           (x +. dx) (y +. 3.) anchor (escape name)))
    nodes;
  Buffer.add_string buffer "</svg>";
  Buffer.contents buffer

(* --------------------------------------------------------------- pages *)

let kpi_band (m : Web_read_model.t) =
  let parity_cells =
    match m.Web_read_model.parity with
    | Some p ->
        [ (string_of_int p.Web_read_model.verified, "verified nodes");
          (string_of_int p.Web_read_model.divergent, "open divergences");
          (p.Web_read_model.snapshot, "snapshot") ]
    | None -> [ ("no store", "parity evidence") ]
  in
  let cells =
    parity_cells
    @ [ (string_of_int m.Web_read_model.components, "components");
        (string_of_int m.Web_read_model.edges, "atlas edges");
        (string_of_int m.Web_read_model.scenarios, "use cases");
        (grade_name m.Web_read_model.system_grade, "formal floor");
        (string_of_int m.Web_read_model.wiki_pages, "wiki notes");
        (string_of_int (List.length m.Web_read_model.gaps), "open gaps") ]
  in
  "<div class=\"kpi\">"
  ^ String.concat ""
      (List.map (fun (v, l) -> esc "<div><b>%s</b><span>%s</span></div>" (escape v) (escape l)) cells)
  ^ "</div>"

let index_page (m : Web_read_model.t) (wiki : Hermes_wiki.model) =
  let health =
    if m.Web_read_model.gaps = [] && m.Web_read_model.intent_drift = [] then
      "<p class=\"ok\">All completeness laws hold and declared intent reconciles clean.</p>"
    else
      "<p class=\"bad\">Open gaps or intent drift — see the plan page.</p>"
  in
  let section title cards =
    esc "<h2>%s</h2><div class=\"grid\">%s</div>" title (String.concat "" cards)
  in
  let card href title sub =
    esc "<a class=\"card\" href=\"%s\"><b>%s</b><small>%s</small></a>" href (escape title)
      (escape sub)
  in
  let component_cards =
    List.map
      (fun (c : Fractal_ontology.component) ->
        let grade =
          match List.assoc_opt c.Fractal_ontology.id m.Web_read_model.grades with
          | Some g -> grade_name g
          | None -> "unregistered"
        in
        card
          ("component-" ^ c.Fractal_ontology.id ^ ".html")
          c.Fractal_ontology.id
          (Fractal_ontology.level_name c.Fractal_ontology.level ^ " · " ^ grade))
      Fractal_ontology.components
  in
  shell ~title:"index"
    ~body:
      (esc
         "<h2>System state</h2>%s%s\
          %s%s%s%s"
         (kpi_band m) health
         (section "Surfaces"
            [ card "dashboard.html" "Parity dashboard" "verdicts derived from the store";
              card "operations.html" "Operations" "every command, exit code, runbook";
              card "usecases.html" "Use cases"
                (string_of_int m.Web_read_model.scenarios ^ " executable scenarios");
              card "analytics.html" "Analytics" "coverage, census, level charts";
              card "wiki.html" "Wiki"
                (string_of_int m.Web_read_model.wiki_pages ^ " notes");
              card "zk.html" "ZK graph" "notes, links, backlinks";
              card "atlas.html" "Atlas" "FPP model, dictionary, coverage";
              card "plan.html" "Plan" "gap items and their status" ])
         (section "Components" component_cards)
         (esc "<h2>Recent notes</h2><div class=\"grid\">%s</div>"
            (String.concat ""
               (List.filteri
                  (fun i _ -> i < 8)
                  (List.map
                     (fun (p : Hermes_wiki.page) ->
                       card (p.Hermes_wiki.slug ^ ".html") p.Hermes_wiki.title
                         (p.Hermes_wiki.group ^ " · " ^ p.Hermes_wiki.meta.Hermes_wiki.ntype))
                     wiki.Hermes_wiki.pages))))
         (esc "<h2>Revision</h2><pre>%s</pre>" (escape m.Web_read_model.revision)))

let dashboard_page (m : Web_read_model.t) =
  let body =
    match m.Web_read_model.parity with
    | None ->
        "<h2>Parity</h2><p class=\"warn\">No evidence store present. The \
         dashboard follows the store; with no store it reports absence \
         rather than a number.</p>"
    | Some p ->
        let unmapped =
          p.Web_read_model.total
          - (p.Web_read_model.verified + p.Web_read_model.divergent + p.Web_read_model.blocked)
        in
        esc
          "<h2>Parity mix (derived)</h2>%s\
           <h2>Numbers</h2><table><tr><th>metric</th><th>value</th></tr>\
           <tr><td>verified nodes</td><td class=\"ok\">%d</td></tr>\
           <tr><td>divergent</td><td class=\"bad\">%d</td></tr>\
           <tr><td>blocked</td><td class=\"warn\">%d</td></tr>\
           <tr><td>unmapped</td><td>%d</td></tr>\
           <tr><td>total nodes</td><td>%d</td></tr>\
           <tr><td>snapshot</td><td>%s</td></tr></table>"
          (donut ~verified:p.Web_read_model.verified ~divergent:p.Web_read_model.divergent
             ~blocked:p.Web_read_model.blocked ~unmapped:(max unmapped 0))
          p.Web_read_model.verified p.Web_read_model.divergent p.Web_read_model.blocked
          (max unmapped 0) p.Web_read_model.total (escape p.Web_read_model.snapshot)
  in
  shell ~title:"dashboard" ~body:(kpi_band m ^ body)

let components_page (m : Web_read_model.t) =
  let rows =
    List.map
      (fun (c : Fractal_ontology.component) ->
        let grade =
          match List.assoc_opt c.Fractal_ontology.id m.Web_read_model.grades with
          | Some g -> g
          | None -> 0
        in
        esc
          "<tr><td><a href=\"component-%s.html\">%s</a></td><td>%s</td>\
           <td class=\"%s\">%s</td><td>%s</td></tr>"
          c.Fractal_ontology.id c.Fractal_ontology.id
          (Fractal_ontology.level_name c.Fractal_ontology.level)
          (grade_class grade) (grade_name grade)
          (escape c.Fractal_ontology.module_path))
      Fractal_ontology.components
  in
  shell ~title:"components"
    ~body:
      (esc
         "<h2>Every fractal component</h2><table>\
          <tr><th>component</th><th>level</th><th>formal grade</th><th>module</th></tr>%s</table>"
         (String.concat "" rows))

let component_page (m : Web_read_model.t) (c : Fractal_ontology.component) =
  let entry = Formal_coverage.entry_for c.Fractal_ontology.id in
  let edges_from =
    List.filter (fun (e : Fractal_ontology.edge) -> e.Fractal_ontology.source = c.Fractal_ontology.id)
      Fractal_ontology.atlas
  in
  let edges_to =
    List.filter (fun (e : Fractal_ontology.edge) -> e.Fractal_ontology.target = c.Fractal_ontology.id)
      Fractal_ontology.atlas
  in
  let relation_name = function
    | Fractal_ontology.Derives_from -> "derives from"
    | Fractal_ontology.Governs -> "governs"
    | Fractal_ontology.Constrains -> "constrains"
    | Fractal_ontology.Observes -> "observes"
  in
  let aspects =
    String.concat ""
      (List.map
         (fun (aspect, coverage) ->
           let name = Fractal_ontology.aspect_name aspect in
           let text =
             match coverage with
             | Fractal_ontology.Addressed s -> esc "<td>%s</td>" (escape s)
             | Fractal_ontology.Not_applicable s ->
                 esc "<td class=\"warn\">n/a — %s</td>" (escape s)
           in
           esc "<tr><th>%s</th>%s</tr>" name text)
         c.Fractal_ontology.coverage)
  in
  let formal =
    match entry with
    | None -> "<p class=\"bad\">No coverage-registry entry.</p>"
    | Some e ->
        esc "<p>Grade: <b class=\"%s\">%s</b></p><ul>%s</ul>"
          (grade_class (Formal_coverage.grade e))
          (grade_name (Formal_coverage.grade e))
          (String.concat ""
             (List.map
                (fun a -> esc "<li>%s</li>" (escape (Formal_coverage.cite a)))
                e.Formal_coverage.artifacts))
  in
  let edge_list label edges pick =
    esc "<h2>%s</h2><ul>%s</ul>" label
      (String.concat ""
         (List.map
            (fun (e : Fractal_ontology.edge) ->
              esc "<li>%s <a href=\"component-%s.html\">%s</a></li>"
                (relation_name e.Fractal_ontology.relation) (pick e) (pick e))
            edges))
  in
  shell ~title:c.Fractal_ontology.id
    ~body:
      (esc
         "<h2>%s</h2><p>%s · <code>%s</code></p>\
          <h2>Purpose</h2><p>%s</p>\
          <h2>Algebra</h2><table>\
          <tr><th>carrier</th><td>%s</td></tr>\
          <tr><th>operation</th><td>%s</td></tr>\
          <tr><th>identity</th><td>%s</td></tr>\
          <tr><th>absorbing</th><td>%s</td></tr>\
          <tr><th>laws</th><td><ul>%s</ul></td></tr></table>\
          <h2>Formal backing</h2>%s\
          <h2>Aspect coverage</h2><table>%s</table>%s%s"
         (escape c.Fractal_ontology.id)
         (Fractal_ontology.level_name c.Fractal_ontology.level)
         (escape c.Fractal_ontology.module_path)
         (escape c.Fractal_ontology.purpose)
         (escape c.Fractal_ontology.algebra.Fractal_ontology.carrier)
         (escape c.Fractal_ontology.algebra.Fractal_ontology.operation)
         (escape c.Fractal_ontology.algebra.Fractal_ontology.identity)
         (escape c.Fractal_ontology.algebra.Fractal_ontology.absorbing)
         (String.concat ""
            (List.map (fun l -> esc "<li>%s</li>" (escape l))
               c.Fractal_ontology.algebra.Fractal_ontology.laws))
         formal aspects
         (edge_list "Outgoing" edges_from (fun e -> e.Fractal_ontology.target))
         (edge_list "Incoming" edges_to (fun e -> e.Fractal_ontology.source)))
  |> fun html -> ignore m; html

let usecases_page (m : Web_read_model.t) =
  let family label scenarios =
    esc "<h2>%s (%d)</h2><table><tr><th>scenario</th><th>given</th><th>steps</th></tr>%s</table>"
      label (List.length scenarios)
      (String.concat ""
         (List.map
            (fun (s : Fpp_usecases.scenario) ->
              esc "<tr><td>%s</td><td>%s</td><td>%d</td></tr>" (escape s.Fpp_usecases.name)
                (escape s.Fpp_usecases.given) (List.length s.Fpp_usecases.steps))
            scenarios))
  in
  shell ~title:"use cases"
    ~body:
      (kpi_band m
      ^ family "Generic F Prime use cases" Fpp_usecases.generic
      ^ family "Harness workflows" Fpp_usecases.workflows
      ^ family "Code generation" Fpp_usecases.codegen)

let operations_page (m : Web_read_model.t) =
  let row command purpose exits =
    esc "<tr><td><code>%s</code></td><td>%s</td><td>%s</td></tr>" (escape command)
      (escape purpose) (escape exits)
  in
  shell ~title:"operations"
    ~body:
      (kpi_band m
      ^ esc
          "<h2>Operator commands</h2><table>\
           <tr><th>command</th><th>what it does</th><th>exit codes</th></tr>%s</table>\
           <h2>Exit-code contract</h2><table>\
           <tr><th>code</th><th>meaning</th><th>operator action</th></tr>\
           <tr><td>0</td><td>honest result recorded</td><td>none</td></tr>\
           <tr><td>1</td><td>refusal (R13 preflight, invalid intent)</td>\
           <td>fix the environment or the blueprint, rerun</td></tr>\
           <tr><td>exit 2</td><td>control P0 or converge anomaly — stop the line</td>\
           <td>every verdict suspect; read the sweep leg, human reset</td></tr></table>\
           <h2>Mesh topics</h2><ul>%s</ul>"
          (String.concat ""
             [ row "run_config" "declarative pipeline: plan, execute, sweep, publish" "0 / 1 / 2";
               row "auto_converge" "OODA convergence loop with R13 preflight" "0 / 1 / 2";
               row "compare_reference_traces" "differential compare, records receipts" "0 / 2";
               row "render_fprime_atlas" "regenerate .fpp + dictionary (fail-closed)" "0 / 1";
               row "render_formal_coverage" "regenerate the coverage page (fail-closed)" "0 / 1";
               row "render_site" "regenerate this site" "0 / 1";
               row "serve_site --port 8790" "serve read-only over tailscale FQDN (R15)" "0 / 1";
               row "serve_site --port 8790" "serve read-only over tailscale FQDN (R15)" "0 / 1" ])
          (String.concat ""
             (List.map
                (fun t -> esc "<li><code>%s</code></li>" (escape t))
                Formal_coverage.zenoh_live_topics)))

let analytics_page (m : Web_read_model.t) =
  let grade_items =
    List.map (fun (name, g) -> (name, g)) m.Web_read_model.grades
  in
  let census_items = m.Web_read_model.census in
  shell ~title:"analytics"
    ~body:
      (kpi_band m
      ^ esc "<h2>Formal grade by component</h2>%s"
          (bar_chart ~title:"coverage rank (5 = machine-checked)" ~items:grade_items ~width:860)
      ^ esc "<h2>Fractal level coverage</h2>%s" (stacked_levels m.Web_read_model.levels)
      ^ esc "<h2>Atlas element census</h2>%s"
          (bar_chart ~title:"instances of each atlas element" ~items:census_items ~width:860))

let wiki_index_page (m : Web_read_model.t) (wiki : Hermes_wiki.model) =
  let groups = Hermes_wiki.moc wiki in
  let group_block (group, slugs) =
    esc "<h2>%s (%d)</h2><div class=\"grid\">%s</div>"
      (escape (if group = "" then "root" else group))
      (List.length slugs)
      (String.concat ""
         (List.map
            (fun slug ->
              match Hermes_wiki.page wiki slug with
              | Some p ->
                  esc "<a class=\"card\" href=\"%s.html\"><b>%s</b><small>%s · %d links</small></a>"
                    slug (escape p.Hermes_wiki.title) (escape p.Hermes_wiki.meta.Hermes_wiki.ntype)
                    (List.length p.Hermes_wiki.outlinks)
              | None -> "")
            slugs))
  in
  shell ~title:"wiki"
    ~body:(kpi_band m ^ String.concat "" (List.map group_block groups))

let wiki_page (wiki : Hermes_wiki.model) (p : Hermes_wiki.page) =
  let backlinks =
    if p.Hermes_wiki.back_ctx = [] then "<p>None yet.</p>"
    else
      esc "<table><tr><th>from</th><th>context</th></tr>%s</table>"
        (String.concat ""
           (List.map
              (fun (source, line) ->
                esc "<tr><td><a href=\"%s.html\">%s</a></td><td>%s</td></tr>" source source
                  (escape line))
              p.Hermes_wiki.back_ctx))
  in
  let outlinks =
    String.concat ""
      (List.map
         (fun slug ->
           match Hermes_wiki.page wiki slug with
           | Some _ -> esc "<li><a href=\"%s.html\">%s</a></li>" slug slug
           | None -> esc "<li><span class=\"missing\">%s</span></li>" (escape slug))
         p.Hermes_wiki.outlinks)
  in
  let tags =
    String.concat ""
      (List.map (fun t -> esc "<span class=\"tag\">#%s</span>" (escape t)) p.Hermes_wiki.tags)
  in
  (* Every slug and element type the model carries is now VISIBLE on the
     page: identity (page slug, stable id, discourse type, status),
     navigation (anchors as a table of contents), semantic correlation
     (typed [[T|@rel]] edges, both directions), and tags as links. A
     relation captured but never shown is a relation nobody can use. *)
  let identity =
    let meta = p.Hermes_wiki.meta in
    esc
      "<h2>Identity</h2><table>\
       <tr><th>page slug</th><td><code>%s</code></td></tr>\
       <tr><th>stable id</th><td><code>%s</code></td></tr>\
       <tr><th>discourse type</th><td>%s</td></tr>\
       <tr><th>status</th><td>%s</td></tr>\
       <tr><th>group</th><td>%s</td></tr>\
       <tr><th>source</th><td><code>%s</code></td></tr>%s</table>"
      (escape p.Hermes_wiki.slug) (escape meta.Hermes_wiki.id)
      (escape meta.Hermes_wiki.ntype) (escape meta.Hermes_wiki.status)
      (escape (if p.Hermes_wiki.group = "" then "(root)" else p.Hermes_wiki.group))
      (escape p.Hermes_wiki.path)
      (match meta.Hermes_wiki.migrated_from with
       | Some origin ->
           esc "<tr><th>migrated from</th><td><code>%s</code></td></tr>" (escape origin)
       | None -> "")
  in
  let toc =
    if List.length p.Hermes_wiki.headings < 2 then ""
    else
      esc "<h2>Sections</h2><ul>%s</ul>"
        (String.concat ""
           (List.map
              (fun (level, text, anchor) ->
                esc "<li style=\"margin-left:%dpx\"><a href=\"#%s\">%s</a></li>"
                  ((level - 1) * 14) anchor (escape text))
              p.Hermes_wiki.headings))
  in
  let semantic_out =
    if p.Hermes_wiki.typed = [] then ""
    else
      esc "<h2>Semantic links (outgoing)</h2><table><tr><th>relation</th><th>target</th></tr>%s</table>"
        (String.concat ""
           (List.map
              (fun (target, relation) ->
                esc "<tr><td><code>@%s</code></td><td><a href=\"%s.html\">%s</a></td></tr>"
                  (escape relation) target target)
              p.Hermes_wiki.typed))
  in
  let semantic_in =
    let incoming =
      List.concat_map
        (fun (other : Hermes_wiki.page) ->
          List.filter_map
            (fun (target, relation) ->
              if target = p.Hermes_wiki.slug then Some (other.Hermes_wiki.slug, relation)
              else None)
            other.Hermes_wiki.typed)
        wiki.Hermes_wiki.pages
    in
    if incoming = [] then ""
    else
      esc "<h2>Semantic links (incoming)</h2><table><tr><th>source</th><th>relation</th></tr>%s</table>"
        (String.concat ""
           (List.map
              (fun (source, relation) ->
                esc "<tr><td><a href=\"%s.html\">%s</a></td><td><code>@%s</code></td></tr>"
                  source source (escape relation))
              incoming))
  in
  let related =
    let shared (other : Hermes_wiki.page) =
      List.length
        (List.filter (fun t -> List.mem t p.Hermes_wiki.tags) other.Hermes_wiki.tags)
    in
    let candidates =
      List.filter_map
        (fun (other : Hermes_wiki.page) ->
          if other.Hermes_wiki.slug = p.Hermes_wiki.slug then None
          else
            let n = shared other in
            if n > 0 then Some (n, other) else None)
        wiki.Hermes_wiki.pages
    in
    let ranked = List.sort (fun (a, _) (b, _) -> compare b a) candidates in
    if ranked = [] then ""
    else
      esc "<h2>Correlated notes (shared tags)</h2><ul>%s</ul>"
        (String.concat ""
           (List.map
              (fun (n, (other : Hermes_wiki.page)) ->
                esc "<li><a href=\"%s.html\">%s</a> <small>%d shared tag(s)</small></li>"
                  other.Hermes_wiki.slug (escape other.Hermes_wiki.title) n)
              ranked))
  in
  let mentions =
    if p.Hermes_wiki.mentions = [] then ""
    else
      esc "<h2>Unlinked mentions</h2><ul>%s</ul>"
        (String.concat ""
           (List.map
              (fun slug -> esc "<li><a href=\"%s.html\">%s</a></li>" slug slug)
              p.Hermes_wiki.mentions))
  in
  let currency =
    let meta = p.Hermes_wiki.meta in
    if meta.Hermes_wiki.last_verified = "" && meta.Hermes_wiki.next_review = "" then ""
    else
      esc
        "<h2>Currency</h2><table><tr><th>last verified</th><td>%s%s</td></tr>\
         <tr><th>next review</th><td>%s</td></tr></table>"
        (escape meta.Hermes_wiki.last_verified)
        (if meta.Hermes_wiki.verified_by = "" then ""
         else esc " (by %s)" (escape meta.Hermes_wiki.verified_by))
        (escape meta.Hermes_wiki.next_review)
  in
  shell ~title:p.Hermes_wiki.title
    ~body:
      (esc
         "<h2>%s</h2><p>%s · %s · <code>%s</code></p><p>%s</p>%s\
          %s%s<h2>Outgoing links</h2><ul>%s</ul>\
          <h2>Backlinks (with citation context)</h2>%s%s%s%s%s%s"
         (escape p.Hermes_wiki.title)
         (escape p.Hermes_wiki.group)
         (escape p.Hermes_wiki.meta.Hermes_wiki.ntype)
         (escape p.Hermes_wiki.path) tags p.Hermes_wiki.html identity toc outlinks
         backlinks mentions semantic_out semantic_in related currency)

let zk_page (m : Web_read_model.t) (wiki : Hermes_wiki.model) =
  let nodes = List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug) wiki.Hermes_wiki.pages in
  let edges =
    List.concat_map
      (fun (p : Hermes_wiki.page) ->
        List.filter_map
          (fun target ->
            if List.mem target nodes then Some (p.Hermes_wiki.slug, target, "link") else None)
          p.Hermes_wiki.outlinks)
      wiki.Hermes_wiki.pages
  in
  let orphans =
    List.filter
      (fun (p : Hermes_wiki.page) ->
        p.Hermes_wiki.outlinks = [] && p.Hermes_wiki.backlinks = [])
      wiki.Hermes_wiki.pages
  in
  let anomalies =
    if wiki.Hermes_wiki.anomalies = [] then "<p class=\"ok\">No anomalies.</p>"
    else
      esc "<ul>%s</ul>"
        (String.concat ""
           (List.map (fun a -> esc "<li class=\"bad\">%s</li>" (escape a)) wiki.Hermes_wiki.anomalies))
  in
  shell ~title:"zk graph"
    ~body:
      (kpi_band m
      ^ esc "<h2>Note graph (%d notes, %d resolved links)</h2>%s"
          (List.length nodes) (List.length edges) (graph_svg ~nodes ~edges)
      ^ esc "<h2>Anomalies</h2>%s" anomalies
      ^ esc "<h2>Unlinked notes (%d)</h2><ul>%s</ul>" (List.length orphans)
          (String.concat ""
             (List.map
                (fun (p : Hermes_wiki.page) ->
                  esc "<li><a href=\"%s.html\">%s</a></li>" p.Hermes_wiki.slug
                    (escape p.Hermes_wiki.title))
                orphans)))

let atlas_page (m : Web_read_model.t) =
  let nodes = List.map (fun (c : Fractal_ontology.component) -> c.Fractal_ontology.id)
      Fractal_ontology.components in
  let relation_key = function
    | Fractal_ontology.Derives_from -> "derives_from"
    | Fractal_ontology.Governs -> "governs"
    | Fractal_ontology.Constrains -> "constrains"
    | Fractal_ontology.Observes -> "observes"
  in
  let edges =
    List.map
      (fun (e : Fractal_ontology.edge) ->
        (e.Fractal_ontology.source, e.Fractal_ontology.target,
         relation_key e.Fractal_ontology.relation))
      Fractal_ontology.atlas
  in
  shell ~title:"atlas"
    ~body:
      (kpi_band m
      ^ esc "<h2>Fractal atlas (%d components, %d typed edges)</h2>%s"
          (List.length nodes) (List.length edges) (graph_svg ~nodes ~edges)
      ^ "<h2>Generated artifacts</h2><ul>\
         <li><code>docs/hermes/atlas/hermes-harness.fpp</code> — the deployment as FPP source</li>\
         <li><code>docs/hermes/atlas/hermes-harness-dictionary.json</code> — the ground dictionary</li>\
         <li><code>docs/hermes/atlas/formal-coverage.md</code> — coverage grid, census, intent</li>\
         </ul>")

let plan_page (m : Web_read_model.t) =
  let rows =
    List.map
      (fun (item : Gap_plan.item) ->
        let status, css =
          match Gap_plan.status item with
          | Gap_plan.Closed -> ("closed", "ok")
          | Gap_plan.Partial -> ("partial", "warn")
          | Gap_plan.Open -> ("open", "bad")
        in
        esc "<tr><td>%s</td><td>%s</td><td>%s</td><td class=\"%s\">%s</td><td>%s</td></tr>"
          (escape item.Gap_plan.id) (escape item.Gap_plan.phase)
          (escape item.Gap_plan.title) css status (escape item.Gap_plan.evidence))
      Gap_plan.items
  in
  let counts = Gap_plan.summary () in
  let drift =
    if m.Web_read_model.intent_drift = [] then "<p class=\"ok\">No intent drift.</p>"
    else
      esc "<ul>%s</ul>"
        (String.concat ""
           (List.map (fun d -> esc "<li class=\"bad\">%s</li>" (escape d)) m.Web_read_model.intent_drift))
  in
  shell ~title:"plan"
    ~body:
      (kpi_band m
      ^ esc
          "<h2>Gap plan (%d items: %d closed, %d partial, %d open)</h2>\
           <p>Status is DERIVED where a live predicate exists — closing an item \
           flips this page, no hand edit.</p>\
           <table><tr><th>id</th><th>phase</th><th>item</th><th>status</th>\
           <th>evidence / approach</th></tr>%s</table>\
           <h2>Declared intent</h2>%s"
          (List.length Gap_plan.items) counts.Gap_plan.closed counts.Gap_plan.partial
          counts.Gap_plan.open_ (String.concat "" rows) drift)

(* --------------------------------------------------------------- build *)

let build ~root =
  let model = Web_read_model.load ~root in
  (* G-STR-1: during the migration the corpus spans BOTH roots —
     hermes_wiki/pages (moved) and docs/hermes (not yet). Reading one
     silently dropped every moved note and left its page stale. *)
  let wiki =
    Hermes_wiki.build
      (Hermes_wiki.read_tracked (Filename.concat root "modules/hermes_wiki/pages")
      @ Hermes_wiki.read_tracked (Filename.concat root "docs/hermes"))
  in
  let pages =
    [ ("index.html", index_page model wiki);
      ("dashboard.html", dashboard_page model);
      ("components.html", components_page model);
      ("usecases.html", usecases_page model);
      ("operations.html", operations_page model);
      ("analytics.html", analytics_page model);
      ("wiki.html", wiki_index_page model wiki);
      ("zk.html", zk_page model wiki);
      ("atlas.html", atlas_page model);
      ("plan.html", plan_page model) ]
    @ List.map
        (fun (c : Fractal_ontology.component) ->
          ("component-" ^ c.Fractal_ontology.id ^ ".html", component_page model c))
        Fractal_ontology.components
    @ List.map
        (fun (p : Hermes_wiki.page) -> (p.Hermes_wiki.slug ^ ".html", wiki_page wiki p))
        wiki.Hermes_wiki.pages
  in
  { model; wiki; pages }
