(* HW.5.3.1–6 — the query view family. See wiki_view.mli for the laws.

   The organising decision: there is ONE result ([t], carrying
   Wiki_query.group's buckets verbatim) and five total renderers over it,
   plus one aggregate. Every renderer walks the SAME bucket list in the
   SAME order and marks each row with `data-row`, so the set law holds by
   construction and is then checked against the finished bytes by
   [row_ids] rather than argued.

   R14 mirrors: the table's shape, the `zq-*` classes and the "%d row%s"
   footer come from `render_zkquery_results_elts` in the imported zigvm
   `docs_wiki.ml` (~§2430); the chart mirrors `bar_chart` in
   `modules/hermes_harness/site_build.ml`.

   No IO, no clock, no randomness, no float. *)

type t = {
  source : string;
  grouped : bool;
  buckets : (string * Hermes_wiki.page list) list;
}

(* ------------------------------------------------------------- escaping *)

(* A byte-for-byte mirror of the core renderer's escape (hermes_wiki.ml
   §89), which the core does not export. The same four characters, in the
   same order, so a view and a page agree on what author text looks like.
   `'` needs no entity because every attribute here is double-quoted. *)
let escape_html text =
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

(* ---------------------------------------------------------- constructors *)

let of_query ~source pages q =
  { source; grouped = q.Wiki_query.group_by <> None; buckets = Wiki_query.group pages q }

let of_source pages src =
  match Wiki_query.parse src with
  | Error e -> Error e
  | Ok q -> Ok (of_query ~source:src pages q)

let rows t = List.concat_map snd t.buckets
let row_count t = List.length (rows t)

(* ------------------------------------------------------------- labelling *)

let unbucketed_label = "(all)"
let absent_key_label = "(none)"

let bucket_label t key =
  if not t.grouped then unbucketed_label else if key = "" then absent_key_label else key

(* An absent derived value is NAMED, never left blank: a blank cell reads
   as "not applicable", which is a different claim from "empty". *)
let field value = if value = "" then absent_key_label else value

let count_label n = Printf.sprintf "%d row%s" n (if n = 1 then "" else "s")

(* ----------------------------------------------------------- projections *)

let columns = [ "title"; "type"; "status"; "group"; "tags"; "links"; "backlinks" ]

(* One projection per column, in column order. DERIVED at render time —
   HW.5.3.1's "rows derived, never stored" is this function existing and
   no row record existing beside it. *)
let cells (p : Hermes_wiki.page) =
  [ p.Hermes_wiki.title;
    p.Hermes_wiki.meta.Hermes_wiki.ntype;
    p.Hermes_wiki.meta.Hermes_wiki.status;
    p.Hermes_wiki.group;
    String.concat " " p.Hermes_wiki.tags;
    string_of_int (List.length p.Hermes_wiki.outlinks);
    string_of_int (List.length p.Hermes_wiki.backlinks) ]

let row_id (p : Hermes_wiki.page) = escape_html p.Hermes_wiki.slug

let root_attrs kind t =
  Printf.sprintf " class=\"zq zq-%s%s\" data-view=\"%s\" data-rows=\"%d\"" kind
    (if row_count t = 0 then " zq-empty" else "")
    kind (row_count t)

(* ------------------------------------------------- HW.5.3.1 table view *)

let tr (p : Hermes_wiki.page) =
  Printf.sprintf "<tr data-row=\"%s\">%s</tr>" (row_id p)
    (String.concat ""
       (List.map (fun c -> Printf.sprintf "<td>%s</td>" (escape_html (field c))) (cells p)))

let table t =
  let head =
    String.concat "" (List.map (fun c -> Printf.sprintf "<th>%s</th>" (escape_html c)) columns)
  in
  let body =
    String.concat ""
      (List.map
         (fun (key, ps) ->
           let label = bucket_label t key in
           Printf.sprintf "<tbody data-bucket=\"%s\">%s%s</tbody>" (escape_html label)
             (if t.grouped then
                Printf.sprintf "<tr class=\"zq-bucket\"><th colspan=\"%d\">%s</th></tr>"
                  (List.length columns) (escape_html label)
              else "")
             (String.concat "" (List.map tr ps)))
         t.buckets)
  in
  Printf.sprintf "<table%s><thead><tr>%s</tr></thead>%s<tfoot><tr><td colspan=\"%d\">%s</td></tr></tfoot></table>"
    (root_attrs "table" t) head body (List.length columns) (count_label (row_count t))

(* -------------------------------- HW.5.3.2 board / HW.5.3.3 kanban *)

(* One card. Board and kanban share it deliberately: they are the same
   rendering of the same result, and HW.5.3.3's difference is PROVENANCE
   (below), not a different set of rows. *)
let article (p : Hermes_wiki.page) =
  Printf.sprintf
    "<article class=\"zq-card\" data-row=\"%s\"><h4>%s</h4><p class=\"zq-meta\">%s / %s</p></article>"
    (row_id p)
    (escape_html (field p.Hermes_wiki.title))
    (escape_html (field p.Hermes_wiki.meta.Hermes_wiki.ntype))
    (escape_html (field p.Hermes_wiki.meta.Hermes_wiki.status))

(* Every bucket becomes a column, INCLUDING an empty one: a column that
   disappears when it empties tells a reader the category is gone. *)
let column_html t (key, ps) =
  let label = bucket_label t key in
  Printf.sprintf
    "<section class=\"zq-col\" data-bucket=\"%s\"><h3>%s</h3><div class=\"zq-col-body\">%s</div><p class=\"zq-n\">%s</p></section>"
    (escape_html label) (escape_html label)
    (String.concat "" (List.map article ps))
    (count_label (List.length ps))

let columns_html t = String.concat "" (List.map (column_html t) t.buckets)

let board t = Printf.sprintf "<div%s>%s</div>" (root_attrs "board" t) (columns_html t)

(* HW.5.3.3 — "query-defined, not file-defined". Obsidian's Kanban stores
   the board in a markdown file, so the board and the notes can disagree;
   here the board IS the query, and it carries the query text so a reader
   can see what defines it. The declaration is a constant: there is no
   code path in this module that can emit any other definition source. *)
let kanban t =
  Printf.sprintf "<div%s data-defined-by=\"query\" data-query=\"%s\">%s</div>"
    (root_attrs "kanban" t) (escape_html t.source) (columns_html t)

(* ----------------------------------------------- HW.5.3.4 gallery view *)

let figure (p : Hermes_wiki.page) =
  Printf.sprintf
    "<figure class=\"zq-card\" data-row=\"%s\"><figcaption>%s</figcaption><p class=\"zq-meta\">%s</p><p class=\"zq-tags\">%s</p></figure>"
    (row_id p)
    (escape_html (field p.Hermes_wiki.title))
    (escape_html (field p.Hermes_wiki.meta.Hermes_wiki.ntype))
    (escape_html (field (String.concat " " p.Hermes_wiki.tags)))

let gallery t =
  let section (key, ps) =
    let label = bucket_label t key in
    Printf.sprintf "<section class=\"zq-grid\" data-bucket=\"%s\">%s%s</section>" (escape_html label)
      (if t.grouped then Printf.sprintf "<h3>%s</h3>" (escape_html label) else "")
      (String.concat "" (List.map figure ps))
  in
  Printf.sprintf "<div%s>%s</div>" (root_attrs "gallery" t)
    (String.concat "" (List.map section t.buckets))

(* -------------------------------------------------- HW.5.3.5 list view *)

(* COMPACT is the claim, so the item carries the identifier and the label
   and nothing else. Every per-row byte added here weakens HW.5.3.5. *)
let li (p : Hermes_wiki.page) =
  Printf.sprintf "<li data-row=\"%s\">%s</li>" (row_id p)
    (escape_html (field p.Hermes_wiki.title))

let list_view t =
  let section (key, ps) =
    let label = bucket_label t key in
    Printf.sprintf "%s<ul data-bucket=\"%s\">%s</ul>"
      (if t.grouped then Printf.sprintf "<h3>%s</h3>" (escape_html label) else "")
      (escape_html label)
      (String.concat "" (List.map li ps))
  in
  Printf.sprintf "<div%s>%s</div>" (root_attrs "list" t)
    (String.concat "" (List.map section t.buckets))

(* ------------------------------------------------------ HW.5.3.6 charts *)

let chart_counts t = List.map (fun (key, ps) -> (bucket_label t key, List.length ps)) t.buckets

(* Integer geometry only. Every coordinate below is an int and every
   division is integer division, so the emitted bytes cannot drift with a
   float printer, a locale, or a rounding mode. *)
let chart_width = 480
let chart_label_w = 160
let chart_row_h = 20
let chart_bar_max = 280

let chart t =
  let items = chart_counts t in
  let height = (List.length items * chart_row_h) + 24 in
  let maxv = List.fold_left (fun acc (_, v) -> max acc v) 0 items in
  let bar i (label, v) =
    let y = 20 + (i * chart_row_h) in
    (* maxv = 0 is the empty result: no division, no bar, no fabricated
       minimum width that would draw a row that does not exist. *)
    let w = if maxv = 0 then 0 else v * chart_bar_max / maxv in
    Printf.sprintf
      "<g data-bucket=\"%s\" data-count=\"%d\"><title>%s: %d</title><text x=\"8\" y=\"%d\" font-size=\"11\">%s</text><rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"12\"/><text x=\"%d\" y=\"%d\" font-size=\"11\">%d</text></g>"
      (escape_html label) v (escape_html label) v (y + 10) (escape_html label) chart_label_w (y + 1)
      w
      (chart_label_w + w + 6)
      (y + 10) v
  in
  Printf.sprintf
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %d %d\" width=\"%d\" height=\"%d\" role=\"img\" aria-label=\"query result by bucket\"%s>%s</svg>"
    chart_width height chart_width height (root_attrs "chart" t)
    (String.concat "" (List.mapi bar items))

(* ---------------------------------------------------------- the set law *)

let renderers =
  [ ("table", table); ("board", board); ("kanban", kanban); ("gallery", gallery);
    ("list", list_view) ]

let matches_at s i pat =
  let m = String.length pat in
  i + m <= String.length s
  &&
  let rec go k = k >= m || (s.[i + k] = pat.[k] && go (k + 1)) in
  go 0

(* Read back what a view ACTUALLY emitted. `data-rows="N"` on the root
   cannot match: the byte after `data-row` there is `s`, not a quote. *)
let row_ids html =
  let marker = "data-row=\"" in
  let n = String.length html in
  let rec go i acc =
    if i >= n then List.rev acc
    else if matches_at html i marker then begin
      let j = i + String.length marker in
      let rec fin k = if k >= n || html.[k] = '"' then k else fin (k + 1) in
      let e = fin j in
      go e (String.sub html j (e - j) :: acc)
    end
    else go (i + 1) acc
  in
  go 0 []
