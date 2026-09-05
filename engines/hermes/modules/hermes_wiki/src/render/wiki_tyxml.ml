(* Typed page generation. See wiki_tyxml.mli.

   The point of TyXML here is not aesthetics: it is that malformed markup
   becomes a TYPE ERROR and escaping stops being a function anyone can
   forget to call. Text is a node in a tree; it is never spliced into a
   string, so there is no place for an injection to enter. *)

module H = Tyxml.Html

type element = Html_types.flow5 H.elt

let to_string element = Format.asprintf "%a" (H.pp_elt ()) element

let text_node text = H.txt text

let kpi_card ~value ~label =
  H.div [ H.b [ H.txt value ]; H.span [ H.txt label ] ]

let kpi_band pairs =
  H.div
    ~a:[ H.a_class [ "kpi" ] ]
    (List.map (fun (value, label) -> kpi_card ~value ~label) pairs)

let card ~href ~title ~subtitle =
  H.a
    ~a:[ H.a_class [ "card" ]; H.a_href href ]
    [ H.b [ H.txt title ]; H.small [ H.txt subtitle ] ]

let grid children = H.div ~a:[ H.a_class [ "grid" ] ] children

let section heading children = H.h2 [ H.txt heading ] :: children

let table ~headers ~rows =
  let header_row = H.tr (List.map (fun h -> H.th [ H.txt h ]) headers) in
  let body_rows =
    List.map (fun cells -> H.tr (List.map (fun c -> H.td [ H.txt c ]) cells)) rows
  in
  H.table (header_row :: body_rows)

(* The chrome every page carries. Kept here so the nav can never drift
   between pages: there is exactly one definition. *)
let nav_links =
  [ ("index.html", "index"); ("dashboard.html", "dashboard");
    ("components.html", "components"); ("usecases.html", "use cases");
    ("operations.html", "operations"); ("analytics.html", "analytics");
    ("wiki.html", "wiki"); ("zk.html", "zk graph"); ("atlas.html", "atlas");
    ("plan.html", "plan") ]

let shell ~title body =
  H.html
    (H.head
       (H.title (H.txt (title ^ " — Hermes harness")))
       [ H.meta ~a:[ H.a_charset "utf-8" ] ();
         H.meta
           ~a:
             [ H.a_name "viewport";
               H.a_content "width=device-width,initial-scale=1" ]
           ();
         H.link ~rel:[ `Stylesheet ] ~href:"site.css" () ])
    (H.body
       [ H.header
           [ H.h1 [ H.txt "Hermes harness" ];
             H.nav
               (List.map (fun (href, label) -> H.a ~a:[ H.a_href href ] [ H.txt label ])
                  nav_links) ];
         H.main body;
         H.footer
           [ H.txt
               "Derived from the live registries and the evidence store. Read-only \
                by construction: no forms, no writes, no external assets." ] ])

let page_to_string ~title body =
  Format.asprintf "%a" (H.pp ()) (shell ~title body)
