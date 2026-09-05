(* typed_html.ml — markup whose correctness is a type property.

   WHY THIS EXISTS, and how it relates to the linter. `docs/design/
   HTML_ALGEBRA.md` gave this repository a real tokenizer and a set of rules
   that judge markup AFTER it is written. That is the right tool for documents
   we do not generate — an authored page, a vendored artifact, a journal
   someone edited by hand. It is the WRONG tool for markup we emit ourselves,
   because a generator that can produce a malformed page will eventually
   produce one, and the linter's job is then to notice the damage rather than
   to prevent it.

   TyXML closes that gap for generated markup. Its element constructors carry
   HTML's content model in their types: a `<b>` inside a `<title>` does not
   lint-fail, it does not compile. Attributes are typed, text is escaped by
   construction, and a document that type-checks is well-formed by the same
   argument that makes a well-typed program not go wrong.

   The two are complementary, and the split is exactly the provenance split
   the lint standard already draws:

     AUTHORED artifact   → judged after the fact by Doc_lint (a renderer's
                           leniency is the standard)
     GENERATED artifact  → made unconstructible here (strictness is free,
                           because a machine is doing the writing)

   THE COMPOSITION THAT MATTERS. TyXML types the markup; it has nothing to say
   about whether an `href` points anywhere. `Route_algebra` types the address;
   it has nothing to say about where the address is placed. Composing them —
   an anchor constructor that accepts a ROUTE and never a string — is what
   makes a broken link a compile error. Neither library gives that alone, and
   it is the whole reason both are here.

   SCOPE LIMIT. This module renders markup. It performs no IO, reads no
   database and decides nothing; like the lint projection, it is report-only
   by construction and a source-scan law holds it to that. *)

module H = Tyxml.Html
module R = Route_algebra

(* ---------- links ----------------------------------------------------------
   The ONLY link constructors. There is deliberately no function here taking a
   raw string href: the point of the module is that such a function does not
   exist, so a call site that wants a link must name a route, and a route that
   does not exist is a compile error rather than a 404. *)

let href_of (r : R.t) = H.a_href (R.to_path r)

(** An anchor to a route. The URL is derived, never written. *)
let link ?(attrs = []) (r : R.t) (label : string) =
  H.a ~a:(href_of r :: attrs) [ H.txt label ]

(** An anchor whose content is arbitrary phrasing rather than plain text. *)
let link_to ?(attrs = []) (r : R.t) content = H.a ~a:(href_of r :: attrs) content

(** A form posting to a route. The method comes from the route, so a form
    cannot POST to a GET-only endpoint. *)
let form_to ?(attrs = []) (r : R.t) content =
  let m =
    match R.meth_of r with
    | R.GET -> `Get
    | R.POST | R.PUT | R.PATCH | R.DELETE | R.HEAD -> `Post
  in
  H.form ~a:(H.a_action (R.to_path r) :: H.a_method m :: attrs) content

(* ---------- the page shell -------------------------------------------------
   Self-containment is a standing constraint for everything this repository
   publishes: no CDN, no external stylesheet, no remote font. Expressing it as
   the SHAPE of the constructor — inline CSS as a string, no stylesheet-URL
   parameter — is stronger than a rule that checks for violations, because
   there is no way to express the violation. *)

let page ~(title : string) ?(css = "") ?(lang = "en") (body : [< Html_types.body_content ] H.elt list)
    : H.doc =
  H.html
    ~a:[ H.a_lang lang ]
    (H.head
       (H.title (H.txt title))
       ([ H.meta ~a:[ H.a_charset "utf-8" ] ();
          H.meta
            ~a:[ H.a_name "viewport"; H.a_content "width=device-width, initial-scale=1" ]
            () ]
       @ if css = "" then [] else [ H.style [ H.txt css ] ]))
    (H.body body)

let render (d : H.doc) : string = Format.asprintf "%a" (H.pp ()) d
let render_elt (e : 'a H.elt) : string = Format.asprintf "%a" (H.pp_elt ()) e

(* ---------- an index over the route table ----------------------------------
   A small, real use: the route table rendered as a page. It is also the
   witness the laws use, because a page built from `R.all` exercises every
   constructor's link at once — if a route cannot be linked, this page cannot
   be built. *)

let route_index () : H.doc =
  let row (r : R.t) =
    H.tr
      [ H.td [ H.code [ H.txt (R.meth_to_string (R.meth_of r)) ] ];
        H.td [ link r (R.to_path r) ];
        H.td [ H.code [ H.txt (R.pattern r) ] ] ]
  in
  page ~title:"zigvm — route table"
    ~css:
      "body{font:14px/1.5 system-ui,sans-serif;margin:2rem;max-width:60rem}\n\
       table{border-collapse:collapse;width:100%}\n\
       td,th{border-bottom:1px solid #8883;padding:.35rem .6rem;text-align:left}\n\
       @media (prefers-color-scheme:dark){body{background:#111;color:#eee}a{color:#7ab7ff}}"
    [ H.h1 [ H.txt "Route table" ];
      H.p
        [ H.txt
            "Every address this system serves, derived from the route algebra. Each link \
             below was constructed from a route value, not from a string." ];
      H.table
        ~thead:(H.thead [ H.tr [ H.th [ H.txt "Method" ]; H.th [ H.txt "URL" ]; H.th [ H.txt "Pattern" ] ] ])
        (List.map row R.all) ]
