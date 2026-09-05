(* HW.1.3.10–14 — ordering and labelling. See the mli: one question asked
   five ways, and the answers must compose into a TOTAL order. *)

type entry = { slug : string; position : int option; label : string; keywords : string list }

(* An ordinal is a SEQUENCE NUMBER, so it is short. Four or more leading
   digits is a date or an identifier — `2026-08-09-notes`, `20260807-adr`
   — and reading one as a position silently reorders a whole directory
   and collides every document that shares the year. The live corpus
   proved it: applying the rule without this bound reported 23 position
   conflicts, every one of them a dated filename and not one of them an
   authoring mistake. Three digits allows 1–999 siblings; a set larger
   than that is not being ordered by hand-typed prefixes, and explicit
   `sidebar_position` is always available with no bound at all. *)
let max_prefix_digits = 3

let number_prefix s =
  let n = String.length s in
  let rec digits i = if i < n && s.[i] >= '0' && s.[i] <= '9' then digits (i + 1) else i in
  let d = digits 0 in
  if d = 0 || d >= n || d > max_prefix_digits then (None, s)
  else if s.[d] = '-' || s.[d] = '_' || s.[d] = '.' then
    match int_of_string_opt (String.sub s 0 d) with
    | Some p -> (Some p, String.sub s (d + 1) (n - d - 1))
    | None -> (None, s)
  else (None, s)

let entry_of (p : Hermes_wiki.page) =
  let m = p.Hermes_wiki.meta in
  let prefix_pos, _ = number_prefix p.Hermes_wiki.slug in
  let position =
    match m.Hermes_wiki.sidebar_position with
    | Some n -> Some n (* EXPLICIT DOMINATES: one mechanism must win *)
    | None -> prefix_pos
  in
  let label =
    match m.Hermes_wiki.sidebar_label with
    | "" ->
        (* A fallback, not an override. The prefix is stripped only when
           the title IS the filename — an authored `# 2026 Roadmap` keeps
           its number, because there the digits are the subject, not a
           position. *)
        let from_filename =
          Filename.remove_extension (Filename.basename p.Hermes_wiki.path)
        in
        if p.Hermes_wiki.title = from_filename then snd (number_prefix p.Hermes_wiki.title)
        else p.Hermes_wiki.title
    | l -> l
  in
  { slug = p.Hermes_wiki.slug; position; label; keywords = m.Hermes_wiki.keywords }

(* TOTAL: positioned documents first in position order, then the rest by
   slug. Ties among equal positions break by slug, so the order is a
   function of the corpus and never of the filesystem. *)
let compare_entries a b =
  match (a.position, b.position) with
  | Some x, Some y -> if x = y then compare a.slug b.slug else compare x y
  | Some _, None -> -1
  | None, Some _ -> 1
  | None, None -> compare a.slug b.slug

let ordered (m : Hermes_wiki.model) =
  m.Hermes_wiki.pages |> List.map entry_of |> List.sort compare_entries

let rec next entries slug =
  match entries with
  | a :: (b :: _ as rest) -> if a.slug = slug then Some b.slug else next rest slug
  | _ -> None

let prev entries slug =
  let rec go = function
    | a :: (b :: _ as rest) -> if b.slug = slug then Some a.slug else go rest
    | _ -> None
  in
  go entries

let position_conflicts (m : Hermes_wiki.model) =
  let positioned =
    m.Hermes_wiki.pages
    |> List.filter_map (fun (p : Hermes_wiki.page) ->
           match (entry_of p).position with
           | Some n -> Some (p.Hermes_wiki.group, n, p.Hermes_wiki.slug)
           | None -> None)
    |> List.sort compare
  in
  let rec dups = function
    | (g1, n1, s1) :: ((g2, n2, s2) :: _ as rest) ->
        (if g1 = g2 && n1 = n2 then
           [ Printf.sprintf "sidebar_position %d claimed twice in %s: %s and %s" n1
               (if g1 = "" then "(root)" else g1)
               s1 s2 ]
         else [])
        @ dups rest
    | _ -> []
  in
  List.sort_uniq compare (dups positioned)

(* HW.6.4.4 — see the mli. Defined over next/prev alone, so the rendered
   nav cannot disagree with the relation it renders. *)

let escape s =
  let b = Buffer.create (String.length s + 8) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let label_of entries slug =
  match List.find_opt (fun e -> e.slug = slug) entries with
  | Some e -> if e.label = "" then e.slug else e.label
  | None -> slug

let nav_targets entries slug =
  (match prev entries slug with Some p -> [ p ] | None -> [])
  @ match next entries slug with Some n -> [ n ] | None -> []

let nav_html entries slug =
  let link rel target =
    Printf.sprintf "<a class=\"pager-%s\" rel=\"%s\" href=\"%s.html\">%s</a>" rel rel
      (escape target) (escape (label_of entries target))
  in
  let parts =
    (match prev entries slug with Some p -> [ link "prev" p ] | None -> [])
    @ match next entries slug with Some n -> [ link "next" n ] | None -> []
  in
  (* an empty nav is an empty nav, not a <nav> holding nothing: a
     one-page sequence has no pagination to show *)
  if parts = [] then ""
  else "<nav class=\"pager\">" ^ String.concat "" parts ^ "</nav>"
