(* notion.ml — Notion's feature model implemented in OCaml with a pure
   Model-to-View projection.

   Notion is a fractal of ONE pattern — a container of typed, linkable units — at
   ascending scales: BLOCK → PAGE → DATABASE. This module implements that pattern
   natively: the block algebra (L0), and the database-view engine (L2, Notion's
   signature: Table / Board / Gallery / List views with grouping over a typed
   schema). The Model is plain data (built from the SQLite ledger by the driver);
   the View is a pure render function. Interactive browser components are
   authored in OCaml and compiled with js_of_ocaml.

   Everything here is a total function; no I/O, no mutation. *)

let esc s = let b = Buffer.create (String.length s) in
  String.iter (fun c -> match c with
    | '<' -> Buffer.add_string b "&lt;" | '>' -> Buffer.add_string b "&gt;"
    | '&' -> Buffer.add_string b "&amp;" | '"' -> Buffer.add_string b "&quot;"
    | c -> Buffer.add_char b c) s; Buffer.contents b

(* ── L0: the BLOCK algebra (Notion "everything is a block") ─────────────── *)
type block =
  | Heading of int * string           (* # / ## / ### *)
  | Text of string
  | Bullet of string list             (* • list *)
  | Numbered of string list           (* 1. list *)
  | Todo of (bool * string) list      (* ☐/☑ checkbox list *)
  | Toggle of string * block list     (* ▸ collapsible (native <details>) *)
  | Callout of string * string        (* emoji + text *)
  | Quote of string
  | Code of string                    (* fenced code *)
  | Divider
  | TableB of string list * string list list  (* header row + body rows *)
  | Image of string * string          (* src, alt *)
  | Bookmark of string * string * string  (* url, title, description — a link card *)
  | Embed of string                   (* an iframe embed (url) *)
  | Columns of block list list        (* multi-column layout *)
  | Toc of (int * string) list        (* table of contents: (level, heading) *)

let rec render_block = function
  | Heading (n, t) -> Printf.sprintf "<h%d>%s</h%d>" n (esc t) n
  | Text t -> Printf.sprintf "<p>%s</p>" (esc t)
  | Bullet xs -> "<ul>" ^ String.concat "" (List.map (fun x -> "<li>" ^ esc x ^ "</li>") xs) ^ "</ul>"
  | Numbered xs -> "<ol>" ^ String.concat "" (List.map (fun x -> "<li>" ^ esc x ^ "</li>") xs) ^ "</ol>"
  | Todo xs -> "<ul class=todo>" ^ String.concat "" (List.map (fun (d,x) ->
      Printf.sprintf "<li>%s %s</li>" (if d then "☑" else "☐") (esc x)) xs) ^ "</ul>"
  | Toggle (summary, body) ->
      Printf.sprintf "<details><summary>%s</summary>%s</details>" (esc summary)
        (String.concat "" (List.map render_block body))
  | Callout (emoji, t) -> Printf.sprintf "<div class=callout><span class=ci>%s</span><span>%s</span></div>" (esc emoji) (esc t)
  | Quote t -> Printf.sprintf "<blockquote>%s</blockquote>" (esc t)
  | Code t -> Printf.sprintf "<pre><code>%s</code></pre>" (esc t)
  | Divider -> "<hr>"
  | TableB (hd, rows) ->
      let th = String.concat "" (List.map (fun h -> "<th>" ^ esc h ^ "</th>") hd) in
      let body = String.concat "" (List.map (fun r ->
        "<tr>" ^ String.concat "" (List.map (fun c -> "<td>" ^ esc c ^ "</td>") r) ^ "</tr>") rows) in
      Printf.sprintf "<div class=tw><table><tr>%s</tr>%s</table></div>" th body
  | Image (src, alt) ->
      Printf.sprintf "<figure class=nimg><img src=\"%s\" alt=\"%s\" loading=lazy><figcaption>%s</figcaption></figure>" (esc src) (esc alt) (esc alt)
  | Bookmark (url, title, desc) ->
      Printf.sprintf "<a class=bookmark href=\"%s\"><div class=bm-t>%s</div><div class=bm-d>%s</div><div class=bm-u>%s</div></a>" (esc url) (esc title) (esc desc) (esc url)
  | Embed url ->
      Printf.sprintf "<div class=embed><iframe src=\"%s\" loading=lazy referrerpolicy=no-referrer sandbox=\"allow-scripts allow-same-origin\"></iframe></div>" (esc url)
  | Columns cols ->
      Printf.sprintf "<div class=cols style=\"grid-template-columns:repeat(%d,1fr)\">%s</div>"
        (max 1 (List.length cols))
        (String.concat "" (List.map (fun col -> "<div class=col>" ^ String.concat "" (List.map render_block col) ^ "</div>") cols))
  | Toc entries ->
      "<nav class=toc><div class=toc-h>On this page</div>" ^
      String.concat "" (List.map (fun (lvl, h) ->
        Printf.sprintf "<a class=toc-l%d href=\"#\">%s</a>" (min 3 (max 1 lvl)) (esc h)) entries) ^ "</nav>"

let render_page (blocks : block list) = String.concat "\n" (List.map render_block blocks)

(* ── L2: the DATABASE model (typed schema + rows + multiple views) ──────── *)
(* Notion property kinds that change rendering (Select/Status → colored pills). *)
type prop_kind =
  | Title | Text_ | Number | Select | Status | Checkbox | Date | Url
  | Relation    (* links to other database pages — rendered as chip-links *)
  | Formula     (* a computed value — rendered with an ƒ marker *)
  | Person      (* people — rendered as avatar (initials) + name *)
type schema = (string * prop_kind) list       (* ordered columns *)
type row = (string * string) list              (* prop_name → value (from SQLite) *)
type view =
  | TableV | BoardV of string | GalleryV | ListV
  | CalendarV of string        (* month grid laid out by a date property *)
  | TimelineV of string        (* chronological timeline by a date property *)

(* ── date handling (a real Date property, for Calendar/Timeline) ────────── *)
(* Notion dates come in as ISO strings; we tolerate "YYYY-MM-DD" and
   "YYYY-MM-DDThh:mm..." (SQLite strftime), extracting the date part. *)
let date_part v =
  if String.length v >= 10
     && v.[4] = '-' && v.[7] = '-'
     && (let ok = ref true in String.iteri (fun i c -> if i < 10 && i <> 4 && i <> 7 && not (c >= '0' && c <= '9') then ok := false) v; !ok)
  then Some (String.sub v 0 10) else None
let ymd d = (int_of_string (String.sub d 0 4), int_of_string (String.sub d 5 2), int_of_string (String.sub d 8 2))
let leap y = (y mod 4 = 0 && y mod 100 <> 0) || y mod 400 = 0
let days_in y m = match m with
  | 2 -> if leap y then 29 else 28
  | 4 | 6 | 9 | 11 -> 30 | _ -> 31
(* weekday (0=Sun) via Unix.mktime — a real calendar, not a guess. *)
let weekday y m d =
  let tm = Unix.{ tm_sec=0; tm_min=0; tm_hour=12; tm_mday=d; tm_mon=m-1; tm_year=y-1900;
                  tm_wday=0; tm_yday=0; tm_isdst=false } in
  let (_, tm2) = Unix.mktime tm in tm2.Unix.tm_wday
let month_name m = [|"January";"February";"March";"April";"May";"June";"July";"August";"September";"October";"November";"December"|].(m-1)

(* a deterministic pill colour class from the value (Notion assigns stable
   colours to select/status options). *)
let pill_class v =
  let h = String.fold_left (fun a c -> (a * 31 + Char.code c) land 0xffff) 7 v in
  Printf.sprintf "pill p%d" (h mod 8)

let cell schema name v =
  match List.assoc_opt name schema with
  | Some Select | Some Status -> Printf.sprintf "<span class=\"%s\">%s</span>" (pill_class v) (esc v)
  | Some Checkbox -> if v = "1" || v = "true" then "☑" else "☐"
  | Some Number -> Printf.sprintf "<span class=num>%s</span>" (esc v)
  | Some Url -> Printf.sprintf "<a href=\"%s\">%s</a>" (esc v) (esc v)
  | Some Title -> Printf.sprintf "<b>%s</b>" (esc v)
  | Some Date -> (match date_part v with
      | Some d -> Printf.sprintf "<span class=date>📅 %s</span>" (esc d)
      | None -> if v = "" then "" else Printf.sprintf "<span class=date>📅 %s</span>" (esc v))
  | Some Relation ->
      (* comma-separated related pages → chip-links (to the docs/notion surface) *)
      if v = "" then "" else
        String.concat " " (List.filter_map (fun r ->
          let r = String.trim r in if r = "" then None else
          Some (Printf.sprintf "<a class=rel href=\"#%s\">%s</a>" (esc r) (esc r)))
          (String.split_on_char ',' v))
  | Some Formula -> if v = "" then "" else Printf.sprintf "<span class=formula><span class=fx>ƒ</span> %s</span>" (esc v)
  | Some Person ->
      if v = "" then "" else
        String.concat " " (List.filter_map (fun p ->
          let p = String.trim p in if p = "" then None else
          let initials = (let up = String.uppercase_ascii p in
            match String.split_on_char ' ' up with
            | a :: b :: _ when String.length a > 0 && String.length b > 0 -> Printf.sprintf "%c%c" a.[0] b.[0]
            | _ -> if String.length up >= 2 then String.sub up 0 2 else up) in
          Some (Printf.sprintf "<span class=person><span class=\"%s pav\">%s</span>%s</span>"
                  (pill_class p) (esc initials) (esc p)))
          (String.split_on_char ',' v))
  | _ -> esc v

let get name r = match List.assoc_opt name r with Some v -> v | None -> ""

let render_table schema rows =
  let cols = List.map fst schema in
  let th = String.concat "" (List.map (fun c -> "<th>" ^ esc c ^ "</th>") cols) in
  let body = String.concat "" (List.map (fun r ->
    "<tr>" ^ String.concat "" (List.map (fun c -> "<td>" ^ cell schema c (get c r) ^ "</td>") cols) ^ "</tr>") rows) in
  Printf.sprintf "<div class=tw><table class=db><tr>%s</tr>%s</table></div>" th body

let card schema r =
  let title = match schema with (t,_) :: _ -> Printf.sprintf "<div class=ct>%s</div>" (cell schema t (get t r)) | [] -> "" in
  let props = String.concat "" (List.filteri (fun i _ -> i > 0) schema
    |> List.map (fun (name,_) -> let v = get name r in if v="" then "" else
        Printf.sprintf "<div class=cp><span class=cl>%s</span>%s</div>" (esc name) (cell schema name v))) in
  Printf.sprintf "<div class=card>%s%s</div>" title props

let render_gallery schema rows =
  "<div class=gallery>" ^ String.concat "" (List.map (card schema) rows) ^ "</div>"

let render_list schema rows =
  "<div class=vlist>" ^ String.concat "" (List.map (fun r ->
    let title = match schema with (t,_)::_ -> cell schema t (get t r) | [] -> "" in
    Printf.sprintf "<div class=vi>%s</div>" title) rows) ^ "</div>"

(* Board (kanban): group rows by a property's value into columns. *)
let render_board schema rows group =
  let vals = List.sort_uniq compare (List.map (get group) rows) in
  let cols = List.map (fun g ->
    let members = List.filter (fun r -> get group r = g) rows in
    let cards = String.concat "" (List.map (card schema) members) in
    Printf.sprintf "<div class=bcol><div class=bh><span class=\"%s\">%s</span><span class=bn>%d</span></div>%s</div>"
      (pill_class g) (esc (if g="" then "—" else g)) (List.length members) cards) vals in
  "<div class=board>" ^ String.concat "" cols ^ "</div>"

(* Calendar (month grid): lay each dated row on its day, one 7-col grid per
   month present. Rows whose date property doesn't parse are collected below. *)
let render_calendar schema rows dprop =
  let dated = List.filter_map (fun r -> match date_part (get dprop r) with Some d -> Some (d, r) | None -> None) rows in
  let months = List.sort_uniq compare (List.map (fun (d,_) -> String.sub d 0 7) dated) in
  let dow = [|"Su";"Mo";"Tu";"We";"Th";"Fr";"Sa"|] in
  let b = Buffer.create 4096 in
  if months = [] then Buffer.add_string b "<p class=cal-empty>No parseable dates in this property.</p>";
  List.iter (fun ym ->
    let y = int_of_string (String.sub ym 0 4) and m = int_of_string (String.sub ym 5 2) in
    Buffer.add_string b (Printf.sprintf "<div class=cal><div class=cal-h>%s %d</div><div class=cal-grid>" (month_name m) y);
    Array.iter (fun d -> Buffer.add_string b (Printf.sprintf "<div class=cal-dow>%s</div>" d)) dow;
    let lead = weekday y m 1 in
    for _ = 1 to lead do Buffer.add_string b "<div class=cal-cell cal-blank></div>" done;
    for day = 1 to days_in y m do
      let ds = Printf.sprintf "%04d-%02d-%02d" y m day in
      let here = List.filter_map (fun (d,r) -> if d = ds then Some r else None) dated in
      Buffer.add_string b (Printf.sprintf "<div class=cal-cell><div class=cal-day>%d</div>" day);
      List.iter (fun r -> let t = match schema with (tt,_)::_ -> get tt r | [] -> "" in
        Buffer.add_string b (Printf.sprintf "<div class=cal-ev>%s</div>" (esc t))) here;
      Buffer.add_string b "</div>"
    done;
    Buffer.add_string b "</div></div>")
    months;
  Buffer.contents b

(* Timeline: rows sorted chronologically by the date property, as a vertical
   dated track (a Gantt-lite for arbitrary dates). *)
let render_timeline schema rows dprop =
  let dated = List.filter_map (fun r -> match date_part (get dprop r) with Some d -> Some (d, r) | None -> None) rows in
  let sorted = List.sort (fun (a,_) (b,_) -> compare a b) dated in
  let b = Buffer.create 2048 in
  Buffer.add_string b "<div class=timeline>";
  List.iter (fun (d, r) ->
    Buffer.add_string b (Printf.sprintf "<div class=tl-row><div class=tl-date>📅 %s</div><div class=tl-dot></div><div class=tl-card>%s</div></div>"
      (esc d) (card schema r)))
    sorted;
  Buffer.add_string b "</div>";
  Buffer.contents b

let render_view schema rows = function
  | TableV -> render_table schema rows
  | BoardV g -> render_board schema rows g
  | GalleryV -> render_gallery schema rows
  | ListV -> render_list schema rows
  | CalendarV d -> render_calendar schema rows d
  | TimelineV d -> render_timeline schema rows d

let view_name = function TableV -> "Table" | BoardV _ -> "Board" | GalleryV -> "Gallery" | ListV -> "List" | CalendarV _ -> "Calendar" | TimelineV _ -> "Timeline"
let view_icon = function TableV -> "▦" | BoardV _ -> "▤" | GalleryV -> "▣" | ListV -> "☰" | CalendarV _ -> "▧" | TimelineV _ -> "▭"

(* a database = a title + schema + rows + several views, rendered with pure-CSS
   radio tabs (Notion's "multiple views per database", no JS). *)
let render_database ~id ~title ~schema ~rows ~(views : view list) =
  let b = Buffer.create 4096 in
  Buffer.add_string b (Printf.sprintf "<div class=db-block><div class=db-title>%s <span class=db-count>%d</span></div>" (esc title) (List.length rows));
  (* radio inputs + tab labels *)
  List.iteri (fun i _v ->
    Buffer.add_string b (Printf.sprintf "<input type=radio name=\"vt-%s\" id=\"vt-%s-%d\"%s class=vt-radio>"
      id id i (if i=0 then " checked" else ""))) views;
  Buffer.add_string b "<div class=vtabs>";
  List.iteri (fun i v ->
    Buffer.add_string b (Printf.sprintf "<label for=\"vt-%s-%d\" class=vtab><span class=vi2>%s</span>%s</label>"
      id i (view_icon v) (view_name v))) views;
  Buffer.add_string b "</div>";
  List.iteri (fun i v ->
    Buffer.add_string b (Printf.sprintf "<div class=\"vpanel vp-%d\">%s</div>" i (render_view schema rows v))) views;
  Buffer.add_string b "</div>";
  Buffer.contents b

(* the CSS for the whole Notion surface (blocks + database views + tabs). *)
let css = {css|
:root{--bg:#0f1417;--pn:#161f24;--el:#1b262c;--ln:#25343b;--ink:#dce4e6;--mu:#87979d;--dim:#5e7178;--ac:#3cc9ae;--bl:#5c9dd0;--code:#101a1e;--rd:#dc6a5c}
:root[data-theme=light]{--bg:#f7f6f2;--pn:#fff;--el:#efece5;--ln:#e5e0d7;--ink:#1e2529;--mu:#586268;--dim:#8a9098;--ac:#0c8a76;--bl:#2c72a8;--code:#f2f0eb;--rd:#c04a3c}
@media(prefers-color-scheme:light){:root:not([data-theme=dark]){--bg:#f7f6f2;--pn:#fff;--el:#efece5;--ln:#e5e0d7;--ink:#1e2529;--mu:#586268;--dim:#8a9098;--ac:#0c8a76;--bl:#2c72a8;--code:#f2f0eb;--rd:#c04a3c}}
*{box-sizing:border-box}html{background:var(--bg)}
body{margin:0;color:var(--ink);background:var(--bg);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;font-size:15px;line-height:1.6;-webkit-font-smoothing:antialiased;font-variant-numeric:tabular-nums}
.wrap{max-width:1080px;margin:0 auto;padding:34px 22px 80px}
code,pre{font-family:ui-monospace,Menlo,Consolas,monospace}
h1{font-size:32px;margin:0 0 6px;letter-spacing:-.02em}h2{font-size:22px;margin:36px 0 6px}h3{font-size:17px;margin:22px 0 4px}
p{color:var(--ink)}.mu{color:var(--mu)}
.callout{display:flex;gap:10px;padding:11px 14px;border:1px solid var(--ln);border-radius:8px;background:var(--pn);margin:14px 0}
.callout .ci{font-size:16px}
blockquote{margin:14px 0;padding:9px 14px;border-left:3px solid var(--ac);background:var(--pn);border-radius:0 8px 8px 0;color:var(--mu)}
pre{background:var(--code);border:1px solid var(--ln);border-radius:8px;padding:13px 15px;overflow-x:auto;font-size:12.7px}
hr{border:none;border-top:1px solid var(--ln);margin:22px 0}
ul.todo{list-style:none;padding-left:4px}details{margin:10px 0;border:1px solid var(--ln);border-radius:8px;padding:8px 12px;background:var(--pn)}summary{cursor:pointer;font-weight:600}
.tw{overflow-x:auto;margin:12px 0}table{border-collapse:collapse;width:100%;font-size:13px;min-width:480px}
th{text-align:left;font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:var(--dim);padding:8px 12px;background:var(--el);border-bottom:1px solid var(--ln)}
td{padding:8px 12px;border-bottom:1px solid var(--ln);vertical-align:top;color:var(--mu)}td b{color:var(--ink)}
.num{font-variant-numeric:tabular-nums}
/* database block */
.db-block{border:1px solid var(--ln);border-radius:12px;background:var(--pn);padding:0;margin:18px 0;overflow:hidden}
.db-title{font-size:15px;font-weight:700;padding:13px 16px 6px;display:flex;gap:8px;align-items:center}
.db-count{font-family:ui-monospace,monospace;font-size:11px;color:var(--dim);background:var(--el);padding:1px 7px;border-radius:20px}
.vt-radio{display:none}
.vtabs{display:flex;gap:2px;padding:0 12px;border-bottom:1px solid var(--ln)}
.vtab{font-size:12.5px;color:var(--mu);padding:7px 11px;cursor:pointer;border-bottom:2px solid transparent;display:inline-flex;gap:6px;align-items:center}
.vtab .vi2{color:var(--dim)}
.vpanel{display:none;padding:12px 16px 16px}
/* pure-CSS tabs: radio i checked → show panel i (up to 4 views) */
.vt-radio:nth-of-type(1):checked ~ .vpanel.vp-0{display:block}
.vt-radio:nth-of-type(2):checked ~ .vpanel.vp-1{display:block}
.vt-radio:nth-of-type(3):checked ~ .vpanel.vp-2{display:block}
.vt-radio:nth-of-type(4):checked ~ .vpanel.vp-3{display:block}
.vt-radio:nth-of-type(5):checked ~ .vpanel.vp-4{display:block}
.vt-radio:nth-of-type(6):checked ~ .vpanel.vp-5{display:block}
.vt-radio:nth-of-type(1):checked ~ .vtabs label:nth-child(1),.vt-radio:nth-of-type(2):checked ~ .vtabs label:nth-child(2),.vt-radio:nth-of-type(3):checked ~ .vtabs label:nth-child(3),.vt-radio:nth-of-type(4):checked ~ .vtabs label:nth-child(4),.vt-radio:nth-of-type(5):checked ~ .vtabs label:nth-child(5),.vt-radio:nth-of-type(6):checked ~ .vtabs label:nth-child(6){color:var(--ac);border-bottom-color:var(--ac)}
/* date chip */
.date{font-size:11.5px;color:var(--bl);white-space:nowrap}
/* relation chip-links */
.rel{display:inline-block;font-size:11px;padding:1px 8px;border-radius:20px;background:color-mix(in srgb,var(--bl) 14%,transparent);color:var(--bl);text-decoration:none;border:1px solid color-mix(in srgb,var(--bl) 30%,transparent);margin:1px 2px 1px 0}
.rel:hover{background:color-mix(in srgb,var(--bl) 24%,transparent)}
/* formula */
.formula{font-family:ui-monospace,monospace;font-size:12px;color:var(--ink)}.fx{color:var(--ac);font-weight:700}
/* person avatar + name */
.person{display:inline-flex;align-items:center;gap:6px;font-size:12.5px;margin:1px 6px 1px 0}
.pav{width:18px;height:18px;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;font-size:9px;font-weight:700;flex:none}
/* calendar (month grid) */
.cal{margin:6px 0 14px}.cal-h{font-weight:600;font-size:14px;margin-bottom:8px}
.cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:4px}
.cal-dow{font-size:9.5px;text-transform:uppercase;letter-spacing:.05em;color:var(--dim);text-align:center;padding:2px}
.cal-cell{min-height:62px;border:1px solid var(--ln);border-radius:6px;padding:4px;background:var(--pn);font-size:11px}
.cal-blank{background:transparent;border-color:transparent}
.cal-day{color:var(--dim);font-family:ui-monospace,monospace;font-size:10.5px;margin-bottom:2px}
.cal-ev{background:color-mix(in srgb,var(--ac) 16%,transparent);color:var(--ink);border-radius:4px;padding:1px 5px;margin:2px 0;font-size:10.5px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cal-empty{color:var(--mu);font-size:13px}
/* timeline */
.timeline{position:relative;margin:8px 0 4px;padding-left:8px;border-left:2px solid var(--ln)}
.tl-row{display:grid;grid-template-columns:96px 16px 1fr;align-items:start;gap:8px;margin:4px 0 12px;position:relative}
.tl-date{font-size:11px;color:var(--bl);padding-top:9px;white-space:nowrap}
.tl-dot{width:9px;height:9px;border-radius:50%;background:var(--ac);margin:12px 0 0 -13px;box-shadow:0 0 0 3px var(--bg)}
.tl-card{min-width:0}
table.db td{color:var(--ink)}
/* pills (select/status) */
.pill{display:inline-block;font-size:11px;font-weight:600;padding:2px 9px;border-radius:20px}
.pill.p0{background:#3cc9ae22;color:#3cc9ae}.pill.p1{background:#5c9dd022;color:#5c9dd0}.pill.p2{background:#e0a24a22;color:#e0a24a}.pill.p3{background:#dc6a5c22;color:#dc6a5c}
.pill.p4{background:#a982d822;color:#a982d8}.pill.p5{background:#54b48722;color:#54b487}.pill.p6{background:#d873b022;color:#d873b0}.pill.p7{background:#7d909622;color:#86989e}
/* board (kanban) */
.board{display:flex;gap:12px;overflow-x:auto;padding-bottom:4px}
.bcol{flex:0 0 220px;background:var(--el);border-radius:9px;padding:9px}
.bh{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;font-size:12px}.bn{font-family:ui-monospace,monospace;color:var(--dim);font-size:11px}
/* cards (gallery + board) */
.card{background:var(--pn);border:1px solid var(--ln);border-radius:8px;padding:10px 12px;margin-bottom:8px}
.ct{font-weight:600;font-size:13.5px;margin-bottom:6px}
.cp{font-size:11.5px;color:var(--mu);margin:3px 0;display:flex;gap:6px;align-items:baseline}
.cl{color:var(--dim);min-width:70px;font-size:10px;text-transform:uppercase;letter-spacing:.04em}
.gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px}
.vlist .vi{padding:7px 4px;border-bottom:1px solid var(--ln);font-size:14px}
/* image / bookmark / embed / columns / toc blocks */
.nimg{margin:14px 0}.nimg img{max-width:100%;border-radius:8px;border:1px solid var(--ln);display:block}
.nimg figcaption{font-size:12px;color:var(--dim);margin-top:5px}
.bookmark{display:block;border:1px solid var(--ln);border-radius:9px;padding:12px 14px;margin:12px 0;background:var(--pn);text-decoration:none}
.bookmark:hover{border-color:var(--ac)}.bm-t{font-weight:600;color:var(--ink);font-size:14px}.bm-d{color:var(--mu);font-size:12.5px;margin:3px 0}.bm-u{color:var(--dim);font-size:11px;font-family:ui-monospace,monospace}
.embed{margin:14px 0;border:1px solid var(--ln);border-radius:9px;overflow:hidden;aspect-ratio:16/9}.embed iframe{width:100%;height:100%;border:0}
.cols{display:grid;gap:16px;margin:14px 0}@media(max-width:640px){.cols{grid-template-columns:1fr!important}}
.toc{border:1px solid var(--ln);border-radius:9px;padding:11px 14px;margin:14px 0;background:var(--pn)}
.toc-h{font-size:10px;text-transform:uppercase;letter-spacing:.08em;color:var(--dim);font-weight:700;margin-bottom:6px}
.toc a{display:block;color:var(--bl);text-decoration:none;font-size:13px;padding:2px 0}.toc-l2{padding-left:14px!important;font-size:12.5px}.toc-l3{padding-left:28px!important;font-size:12px}
.foot{margin-top:40px;padding-top:16px;border-top:1px solid var(--ln);font-size:12px;color:var(--dim)}.foot a{color:var(--bl)}
.nav{display:flex;gap:16px;margin-bottom:20px;font-family:ui-monospace,monospace;font-size:12px}.nav a{color:var(--bl);text-decoration:none}
/* editor */
.ed-bar{display:flex;gap:8px;align-items:center;margin:14px 0}
.ed-btn{font-size:12.5px;font-family:inherit;color:var(--ink);background:var(--pn);border:1px solid var(--ln);border-radius:7px;padding:6px 12px;cursor:pointer}
.ed-btn:hover{border-color:var(--ac);color:var(--ac)}
.ed-status{font-size:12px;color:var(--ac);font-family:ui-monospace,monospace}
.ed-table td.ed-cell{cursor:text;outline:none}
.ed-table td.ed-cell:focus{background:color-mix(in srgb,var(--ac) 10%,transparent);box-shadow:inset 0 0 0 1px var(--ac)}
.ed-del{background:none;border:none;color:var(--dim);cursor:pointer;font-size:12px;padding:2px 6px;border-radius:4px}
.ed-del:hover{color:var(--rd);background:color-mix(in srgb,var(--rd) 12%,transparent)}
.rd{color:var(--rd)}
#ed-export{background:var(--code);border:1px solid var(--ln);border-radius:8px;padding:12px;font-size:11.5px;max-height:340px;overflow:auto;margin-top:10px}
/* typed js_of_ocaml editor */
.b-mount{margin-top:8px}
.b-table{border-collapse:collapse;width:100%;font-size:13px;margin:6px 0}
.b-table th{text-align:left;font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:var(--dim);padding:8px 10px;background:var(--el);border-bottom:1px solid var(--ln)}
.b-table td{padding:3px 4px;border-bottom:1px solid var(--ln)}
.b-cell{width:100%;background:transparent;border:1px solid transparent;border-radius:5px;padding:5px 8px;color:var(--ink);font:inherit;font-size:13px}
.b-cell:focus{outline:none;border-color:var(--ac);background:color-mix(in srgb,var(--ac) 8%,transparent)}
.b-del{background:none;border:none;color:var(--dim);cursor:pointer;font-size:12px;padding:3px 7px;border-radius:4px}
.b-del:hover{color:var(--rd);background:color-mix(in srgb,var(--rd) 12%,transparent)}
.b-add{margin-top:8px;font:inherit;font-size:12.5px;color:var(--ink);background:var(--pn);border:1px solid var(--ln);border-radius:7px;padding:6px 12px;cursor:pointer}
.b-add:hover{border-color:var(--ac);color:var(--ac)}
|css}

let frame ~title ~body =
  Printf.sprintf "<title>%s</title><style>%s</style><div class=wrap>%s</div>" (esc title) css body

(* ── interactive editing (Model -> Action -> View, client-side) ────────────
   The editor uses an immutable Model, typed Actions, a pure View, and a
   reduce/dispatch loop. It is CLIENT-SIDE ONLY (edits live
   in localStorage; no ledger writes) so it cannot violate the read-only-
   projection / no-fabricated-data integrity of the served surfaces. *)

(* JSON-encode the seed Model (rows) — <, & escaped so it can't break the
   inline <script type=application/json> that carries it. *)
let json_str s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (fun c -> match c with
    | '"' -> Buffer.add_string b "\\\"" | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n" | '<' -> Buffer.add_string b "\\u003c"
    | '&' -> Buffer.add_string b "\\u0026" | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"'; Buffer.contents b

let json_model schema rows =
  let sch = String.concat "," (List.map (fun (n,_) -> json_str n) schema) in
  let rws = String.concat "," (List.map (fun r ->
    "[" ^ String.concat "," (List.map (fun (n,_) -> json_str (get n r)) schema) ^ "]") rows) in
  Printf.sprintf "{\"schema\":[%s],\"rows\":[%s]}" sch rws

let render_editor ~title ~schema ~rows =
  let seed = json_model schema rows in
  let body = Printf.sprintf {edit|
<h1>%s <span class=db-count>editable</span></h1>
<p class=mu>An interactive Notion database editor — click a cell to edit, toggle checkboxes, add or delete rows. State lives in your browser (localStorage); nothing is written to the ledger.</p>
<div class=ed-bar>
  <button class=ed-btn onclick="dispatch({t:'addRow'})">+ New row</button>
  <button class=ed-btn onclick="dispatch({t:'reset'})">Reset</button>
  <button class=ed-btn onclick="exportJson()">Export JSON</button>
  <span id=ed-status class=ed-status></span>
</div>
<div id=notion-edit-root></div>
<pre id=ed-export style="display:none"></pre>
<div class=nav><a href="/notion">← Notion databases</a><a href="/docs">docs</a><a href="/wiki">live wiki</a></div>
<div class=foot>Client-side reducer emitted by notion.ml. Client-only state; no ledger writes.</div>
<script type="application/json" id="seed">%s</script>
<script>
// Model/Action/View loop, client-side.
// Model (immutable snapshot in localStorage), Action (typed), View (pure fn of
// Model), reduce (Model×Action→Model), dispatch (reduce then re-render).
const KEY='zigvm-notion-edit';
const seed=JSON.parse(document.getElementById('seed').textContent);
function loadModel(){try{const s=localStorage.getItem(KEY);if(s)return JSON.parse(s);}catch(e){} return JSON.parse(JSON.stringify(seed));}
let model=loadModel();
function persist(){try{localStorage.setItem(KEY,JSON.stringify(model));}catch(e){}}
function reduce(m,a){
  const n={schema:m.schema.slice(),rows:m.rows.map(r=>r.slice())};
  switch(a.t){
    case 'edit': n.rows[a.r][a.c]=a.v; break;
    case 'toggle': n.rows[a.r][a.c]=(n.rows[a.r][a.c]==='1'||n.rows[a.r][a.c]==='true')?'0':'1'; break;
    case 'addRow': n.rows.push(n.schema.map(()=>'')); break;
    case 'delRow': n.rows.splice(a.r,1); break;
    case 'reset': return JSON.parse(JSON.stringify(seed));
  }
  return n;
}
function dispatch(a){model=reduce(model,a);persist();view();flash(a.t);}
function flash(t){const s=document.getElementById('ed-status');s.textContent='✓ '+t;setTimeout(()=>{s.textContent='';},900);}
function esc(s){return String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));}
// pure View: render the Model to the DOM, wiring events → dispatch
function view(){
  const root=document.getElementById('notion-edit-root');
  let h='<div class=tw><table class="db ed-table"><tr>';
  model.schema.forEach(c=>h+='<th>'+esc(c)+'</th>');h+='<th></th></tr>';
  model.rows.forEach((row,r)=>{
    h+='<tr>';
    row.forEach((v,c)=>{
      const name=model.schema[c].toLowerCase();
      if(name==='checkbox'||name==='done'){
        h+='<td><input type=checkbox '+((v==='1'||v==='true')?'checked':'')+' onchange="dispatch({t:\'toggle\',r:'+r+',c:'+c+'})"></td>';
      }else{
        h+='<td class=ed-cell contenteditable=true data-r='+r+' data-c='+c+' onblur="onEdit(this)">'+esc(v)+'</td>';
      }
    });
    h+='<td><button class=ed-del onclick="dispatch({t:\'delRow\',r:'+r+'})" title=Delete>✕</button></td>';
    h+='</tr>';
  });
  h+='</table></div>';
  root.innerHTML=h;
}
function onEdit(td){const r=+td.dataset.r,c=+td.dataset.c,v=td.textContent;if(v!==model.rows[r][c])dispatch({t:'edit',r,c,v});}
function exportJson(){const p=document.getElementById('ed-export');p.style.display=p.style.display==='none'?'block':'none';p.textContent=JSON.stringify(model,null,2);}
view();
</script>
|edit} (esc title) seed in
  frame ~title:(title ^ " · editor") ~body

(* ── self-test (a law: total + injection-safe + structurally correct) ──── *)
let has s sub = let re = Str.regexp_string sub in try ignore (Str.search_forward re s 0); true with Not_found -> false
let selftest () =
  (* blocks *)
  assert (render_block (Heading (2, "Hi")) = "<h2>Hi</h2>");
  assert (has (render_block (Callout ("💡", "note"))) "class=callout");
  assert (has (render_block (Todo [(true,"a");(false,"b")])) "☑");
  assert (has (render_block (Code "x<y")) "x&lt;y");           (* injection-safe *)
  assert (has (render_block (Toggle ("t",[Text "x"]))) "<details>");
  (* the key content blocks *)
  assert (has (render_block (Image ("/a.png","alt"))) "<img");
  assert (has (render_block (Bookmark ("u","T","d"))) "class=bookmark");
  assert (has (render_block (Embed "u")) "<iframe");
  assert (has (render_block (Columns [[Text "a"];[Text "b"]])) "class=cols");
  assert (has (render_block (Toc [(1,"A");(2,"B")])) "class=toc");
  assert (has (render_block (Image ("x\"onerror=y","<a>"))) "&lt;a&gt;");  (* attrs escaped *)
  (* database views *)
  let schema = [ ("Name", Title); ("Verdict", Status); ("Sev", Number) ] in
  let rows = [ [("Name","a");("Verdict","EQ");("Sev","5")]; [("Name","b");("Verdict","EQUIV");("Sev","3")] ] in
  assert (has (render_view schema rows TableV) "<table");
  assert (has (render_view schema rows (BoardV "Verdict")) "class=board");   (* kanban *)
  assert (has (render_view schema rows (BoardV "Verdict")) "class=bcol");
  assert (has (render_view schema rows GalleryV) "class=gallery");
  assert (has (render_view schema rows ListV) "class=vlist");
  (* Calendar + Timeline + Date rendering *)
  let dschema = [ ("Slice", Title); ("When", Date) ] in
  let drows = [ [("Slice","a");("When","2026-07-25")]; [("Slice","b");("When","2026-07-19T22:10")]; [("Slice","c");("When","")] ] in
  assert (has (render_view dschema drows (CalendarV "When")) "class=cal-grid");   (* month grid *)
  assert (has (render_view dschema drows (CalendarV "When")) "class=cal-day");
  assert (has (render_view dschema drows (TimelineV "When")) "class=timeline");   (* chronological track *)
  assert (has (render_view dschema drows (TimelineV "When")) "class=tl-date");
  assert (has (render_table dschema drows) "class=date");                          (* Date property chip *)
  assert (has (render_table dschema drows) "2026-07-19");                          (* ISO time part stripped to the date *)
  (* Relation / Formula / Person property rendering *)
  let pschema = [ ("Item", Title); ("Links", Relation); ("Weight", Formula); ("Owner", Person) ] in
  let prows = [ [("Item","a");("Links","x, y");("Weight","4.2");("Owner","Ada Lovelace, an")] ] in
  assert (has (render_table pschema prows) "class=rel");            (* relation chip-link *)
  assert (has (render_table pschema prows) "#x");                   (* two related items *)
  assert (has (render_table pschema prows) "#y");
  assert (has (render_table pschema prows) "class=formula");        (* formula with ƒ marker *)
  assert (has (render_table pschema prows) "ƒ");
  assert (has (render_table pschema prows) "class=person");         (* person avatar + name *)
  assert (has (render_table pschema prows) "AL");                   (* initials of "Ada Lovelace" *)
  assert (has (render_table pschema prows) "Ada Lovelace");
  assert (has (render_table [("P",Person)] [[("P","<x>")]]) "&lt;x&gt;");  (* escaped *)
  assert (has (render_table [("R",Relation)] [[("R","<a>")]]) "&lt;a&gt;");
  (* date parsing correctness *)
  assert (date_part "2026-07-25" = Some "2026-07-25");
  assert (date_part "2026-07-19T22:10:03Z" = Some "2026-07-19");
  assert (date_part "not a date" = None);
  assert (weekday 2026 7 25 = 6);  (* 2026-07-25 is a Saturday *)
  assert (days_in 2024 2 = 29 && days_in 2026 2 = 28);  (* leap-year *)
  (* status renders a coloured pill; a raw < in a value is escaped *)
  assert (has (render_view schema rows TableV) "class=\"pill");
  assert (has (render_table schema [ [("Name","<x>")] ]) "&lt;x&gt;");
  (* a full database block has tabs for each view *)
  let h = render_database ~id:"t" ~title:"T" ~schema ~rows ~views:[TableV; BoardV "Verdict"; GalleryV] in
  assert (has h "class=vtabs"); assert (has h "class=db-block");
  (* interactive EDITOR: the Model→Action→View reducer + a JSON-safe seed *)
  let e = render_editor ~title:"Edit" ~schema ~rows in
  assert (has e "notion-edit-root");             (* the mount point *)
  assert (has e "function dispatch");            (* the dispatch loop *)
  assert (has e "function reduce");              (* Model×Action→Model *)
  assert (has e "contenteditable");              (* editable cells *)
  assert (has e "id=\"seed\"");                 (* the injected Model *)
  (* the seed JSON escapes < so it cannot break out of the inline script *)
  assert (json_str "a<b" = "\"a\\u003cb\"");
  assert (not (has (json_model schema [ [("Name","</script>")] ]) "</script>"))
