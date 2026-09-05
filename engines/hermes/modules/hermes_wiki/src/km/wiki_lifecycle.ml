(* Lifecycle / governance laws. See wiki_lifecycle.mli for the laws and
   the reasons; this file only has to hold them. PURE throughout. *)

(* ------------------------------------------------------------ shared *)

(* The fence idiom, mirrored from wiki_transclude.ml so the two agree on
   what "inside a code fence" means (R14: mirror, never reinvent). *)
let is_fence line =
  let t = String.trim line in
  String.length t >= 3 && String.sub t 0 3 = "```"

let sorted_uniq l = List.sort_uniq String.compare l

let starts_at s i needle =
  let n = String.length s and m = String.length needle in
  i + m <= n && String.sub s i m = needle

(* Walk a body line by line, calling [f] on every line that is PROSE:
   outside a fence. Fence delimiter lines are prose to nobody. *)
let fold_prose_lines f init body =
  String.split_on_char '\n' body
  |> List.fold_left
       (fun (in_fence, acc) line ->
         if is_fence line then (not in_fence, acc)
         else if in_fence then (in_fence, acc)
         else (in_fence, f acc line))
       (false, init)
  |> snd

(* ==================================================== HW.8.1.5 last_update *)

type stamp = Known of string | Malformed of string | Unknown
type origin = From_git | From_frontmatter | Absent
type last_update = { stamp : stamp; origin : origin }

let parse_date raw =
  let s = String.trim raw in
  if s = "" then Unknown
  else
    let digits i n =
      let rec go k = k >= n || (i + k < String.length s
                                && s.[i + k] >= '0' && s.[i + k] <= '9' && go (k + 1)) in
      go 0
    in
    let two i =
      if i + 1 < String.length s then (Char.code s.[i] - 48) * 10 + (Char.code s.[i + 1] - 48)
      else -1
    in
    if String.length s = 10 && s.[4] = '-' && s.[7] = '-'
       && digits 0 4 && digits 5 2 && digits 8 2
    then
      let m = two 5 and d = two 8 in
      if m >= 1 && m <= 12 && d >= 1 && d <= 31 then Known s else Malformed raw
    else Malformed raw

let last_update ~git ~frontmatter =
  match git with
  | Some g when String.trim g <> "" -> { stamp = parse_date g; origin = From_git }
  | Some _ | None -> (
      match parse_date frontmatter with
      | Unknown -> { stamp = Unknown; origin = Absent }
      | s -> { stamp = s; origin = From_frontmatter })

let render_stamp = function
  | Known d -> d
  | Malformed s -> "malformed: " ^ s
  | Unknown -> "unknown"

let origin_name = function
  | From_git -> "git"
  | From_frontmatter -> "frontmatter"
  | Absent -> "absent"

let last_update_report entries =
  List.map
    (fun (slug, git, frontmatter) ->
      let u = last_update ~git ~frontmatter in
      Printf.sprintf "%s: %s [%s]" slug (render_stamp u.stamp) (origin_name u.origin))
    entries
  |> List.sort String.compare

(* ============================================== HW.8.2.5 external links *)

let url_schemes = [ "https://"; "http://" ]

(* Where a URL token stops. `)` and `>` close the markdown forms; the
   quote characters and the backtick close their own contexts. *)
let is_url_stop c =
  match c with
  | ' ' | '\t' | '\r' | '<' | '>' | '"' | '\'' | ')' | ']' | '`' | '|' -> true
  | _ -> false

let strip_trailing_punct s =
  let rec go n =
    if n = 0 then 0
    else
      match s.[n - 1] with '.' | ',' | ';' | ':' | '!' | '?' -> go (n - 1) | _ -> n
  in
  String.sub s 0 (go (String.length s))

(* Scan one prose line for URLs, honouring inline backticks: CODE IS NOT
   PROSE inline as well as fenced. *)
let urls_of_line acc line =
  let n = String.length line in
  let out = ref acc in
  let in_code = ref false in
  let i = ref 0 in
  while !i < n do
    if line.[!i] = '`' then (
      in_code := not !in_code;
      incr i)
    else if !in_code then incr i
    else
      match List.find_opt (fun s -> starts_at line !i s) url_schemes with
      | None -> incr i
      | Some scheme ->
          let start = !i in
          let j = ref (start + String.length scheme) in
          while !j < n && not (is_url_stop line.[!j]) do
            incr j
          done;
          let raw = String.sub line start (!j - start) in
          let u = strip_trailing_punct raw in
          if String.length u > String.length scheme then out := u :: !out;
          i := !j
  done;
  !out

let external_urls body = sorted_uniq (fold_prose_lines urls_of_line [] body)

type probe = Reachable | Dead of string
type verdict = Live of string | Broken of string * string | Unchecked of string

let classify ~evidence urls =
  List.map
    (fun u ->
      match List.assoc_opt u evidence with
      | Some Reachable -> Live u
      | Some (Dead reason) -> Broken (u, reason)
      | None -> Unchecked u)
    urls

type link_summary = { live : int; broken : int; unchecked : int }

let summarise verdicts =
  List.fold_left
    (fun s v ->
      match v with
      | Live _ -> { s with live = s.live + 1 }
      | Broken _ -> { s with broken = s.broken + 1 }
      | Unchecked _ -> { s with unchecked = s.unchecked + 1 })
    { live = 0; broken = 0; unchecked = 0 }
    verdicts

(* ============================================== HW.8.3.1 page templates *)

type template = { name : string; body : string; placeholders : string list }
type fill_error = Unfilled of string | Unknown_placeholder of string

let show_fill_error = function
  | Unfilled k -> "unfilled placeholder: " ^ k
  | Unknown_placeholder k -> "unknown placeholder: " ^ k

(* One walk serves both the scan and the substitution: [emit] receives
   either a literal chunk or a placeholder name, and decides. Fenced and
   backticked regions are literal by construction, so a documented
   `{{x}}` is neither declared nor substituted. *)
let walk_template ~on_literal ~on_placeholder body =
  let lines = String.split_on_char '\n' body in
  let n_lines = List.length lines in
  let _ =
    List.fold_left
      (fun (in_fence, idx) line ->
        let last = idx = n_lines - 1 in
        let emit_nl () = if not last then on_literal "\n" in
        if is_fence line then (
          on_literal line;
          emit_nl ();
          (not in_fence, idx + 1))
        else if in_fence then (
          on_literal line;
          emit_nl ();
          (in_fence, idx + 1))
        else (
          let n = String.length line in
          let in_code = ref false in
          let i = ref 0 in
          while !i < n do
            if line.[!i] = '`' then (
              in_code := not !in_code;
              on_literal "`";
              incr i)
            else if !in_code then (
              on_literal (String.make 1 line.[!i]);
              incr i)
            else if starts_at line !i "{{" then (
              let rec close k =
                if k + 1 < n then if starts_at line k "}}" then Some k else close (k + 1)
                else None
              in
              match close (!i + 2) with
              | None ->
                  on_literal (String.make 1 line.[!i]);
                  incr i
              | Some k ->
                  let name = String.trim (String.sub line (!i + 2) (k - !i - 2)) in
                  if name = "" then (
                    (* `{{}}` names nothing and is therefore not a slot *)
                    on_literal (String.sub line !i (k + 2 - !i));
                    i := k + 2)
                  else (
                    on_placeholder name;
                    i := k + 2))
            else (
              on_literal (String.make 1 line.[!i]);
              incr i)
          done;
          emit_nl ();
          (in_fence, idx + 1)))
      (false, 0) lines
  in
  ()

let template ~name body =
  let found = ref [] in
  walk_template ~on_literal:(fun _ -> ()) ~on_placeholder:(fun k -> found := k :: !found) body;
  { name; body; placeholders = sorted_uniq !found }

let instantiate t fills =
  let keys = sorted_uniq (List.map fst fills) in
  let unfilled =
    List.filter (fun k -> not (List.mem k keys)) t.placeholders |> List.map (fun k -> Unfilled k)
  in
  let unknown =
    List.filter (fun k -> not (List.mem k t.placeholders)) keys
    |> List.map (fun k -> Unknown_placeholder k)
  in
  match unfilled @ unknown with
  | [] ->
      let buf = Buffer.create (String.length t.body) in
      walk_template
        ~on_literal:(Buffer.add_string buf)
        ~on_placeholder:(fun k ->
          match List.assoc_opt k fills with
          | Some v -> Buffer.add_string buf v
          | None -> ())
        t.body;
      Ok (Buffer.contents buf)
  | errors -> Error errors

(* ================================== HW.8.5.3 ontology / concept model *)

type axis = Ktype | Maturity | Status | Ntype | Visibility | Domain

let axes = [ Ktype; Maturity; Status; Ntype; Visibility; Domain ]

let axis_name = function
  | Ktype -> "ktype"
  | Maturity -> "maturity"
  | Status -> "status"
  | Ntype -> "type"
  | Visibility -> "visibility"
  | Domain -> "domain"

(* Verbatim from the `meta` comments in hermes_wiki.mli. *)
let vocabulary = function
  | Ktype -> [ "atomic"; "moc"; "source"; "journal" ]
  | Maturity -> [ "seed"; "incubating"; "evergreen"; "archived" ]
  | Status -> [ "draft"; "published"; "flagged_for_review" ]
  (* the two trailing terms were admitted deliberately at the parse site
     in hermes_wiki.ml; omitting them here reported two correct documents
     as vocabulary gaps, which is how a stale comment becomes a false
     defect *)
  | Ntype ->
      [ "note"; "question"; "claim"; "evidence"; "decision"; "reference"; "policy"; "playbook" ]
  | Visibility -> [ "draft"; "unlisted"; "listed" ]
  | Domain -> []

let is_open = function Domain -> true | Ktype | Maturity | Status | Ntype | Visibility -> false

type requirement = Required | Optional

let requirement = function
  | Ktype | Maturity | Domain -> Required
  | Status | Ntype | Visibility -> Optional

type value_verdict = Unset | In_vocabulary | Open_term | Outside

let classify_value axis value =
  let v = String.trim value in
  if v = "" then Unset
  else if is_open axis then Open_term
  else if List.mem v (vocabulary axis) then In_vocabulary
  else Outside

let axis_value (m : Hermes_wiki.meta) = function
  | Ktype -> m.Hermes_wiki.ktype
  | Maturity -> m.Hermes_wiki.maturity
  | Status -> m.Hermes_wiki.status
  | Ntype -> m.Hermes_wiki.ntype
  | Visibility -> m.Hermes_wiki.visibility
  | Domain -> m.Hermes_wiki.domain

let vocabulary_gaps (model : Hermes_wiki.model) =
  List.concat_map
    (fun (p : Hermes_wiki.page) ->
      List.filter_map
        (fun axis ->
          let v = axis_value p.Hermes_wiki.meta axis in
          match classify_value axis v with
          | Outside ->
              Some
                (Printf.sprintf "%s: %s outside vocabulary: %s" p.Hermes_wiki.slug (axis_name axis) v)
          | Unset | In_vocabulary | Open_term -> None)
        axes)
    model.Hermes_wiki.pages
  |> List.sort String.compare

(* ========================================== HW.1.2.6 slug override *)

type slug_claim = { path : string; declared : string option; derived : string }
type slug_source = Declared_slug | Derived_slug | Declared_malformed
type slug_resolution = { path : string; slug : string; source : slug_source }

let resolve_slug c =
  match c.declared with
  | None -> { path = c.path; slug = c.derived; source = Derived_slug }
  | Some d -> (
      match Hermes_wiki.slugify (String.trim d) with
      | "" -> { path = c.path; slug = c.derived; source = Declared_malformed }
      | s -> { path = c.path; slug = s; source = Declared_slug })

let resolve_slugs claims = List.map resolve_slug claims

let slug_overrides claims =
  List.filter_map
    (fun c ->
      match c.declared with
      | None -> None
      | Some d -> (
          let r = resolve_slug c in
          match r.source with
          | Declared_slug ->
              Some (Printf.sprintf "slug override: %s -> %s (%s)" c.derived r.slug c.path)
          | Declared_malformed ->
              Some
                (Printf.sprintf "slug override malformed: %S kept %s (%s)" d c.derived c.path)
          | Derived_slug -> None))
    claims
  |> List.sort String.compare

let slug_collisions claims =
  let resolutions = resolve_slugs claims in
  let slugs = sorted_uniq (List.map (fun r -> r.slug) resolutions) in
  List.filter_map
    (fun s ->
      let group = List.filter (fun r -> r.slug = s) resolutions in
      match group with
      | [] | [ _ ] -> None
      | _ ->
          let explicit = List.exists (fun r -> r.source = Declared_slug) group in
          let paths = List.sort String.compare (List.map (fun r -> r.path) group) in
          Some
            (Printf.sprintf "%s slug collision: %s (%s)"
               (if explicit then "explicit" else "derived")
               s (String.concat ", " paths)))
    slugs
  |> List.sort String.compare

(* ============================================ HW.1.3.9 description *)

type desc_origin = Declared_desc | Derived_desc | No_desc
type description = { text : string; origin : desc_origin; truncated : bool }

let max_description = 200

let is_heading line =
  let t = String.trim line in
  String.length t > 0 && t.[0] = '#'

(* The first run of consecutive prose lines: fences skipped entirely,
   blanks and headings terminate or precede the run. *)
let first_paragraph body =
  let collected, _ =
    fold_prose_lines
      (fun (acc, closed) line ->
        if closed then (acc, closed)
        else
          let t = String.trim line in
          if t = "" || is_heading line then (acc, acc <> []) else (t :: acc, false))
      ([], false) body
  in
  String.concat " " (List.rev collected)

let cut text =
  if String.length text > max_description then (String.sub text 0 max_description, true)
  else (text, false)

let describe ~declared ~body =
  let d = String.trim declared in
  if d <> "" then
    let text, truncated = cut d in
    { text; origin = Declared_desc; truncated }
  else
    match first_paragraph body with
    | "" -> { text = ""; origin = No_desc; truncated = false }
    | p ->
        let text, truncated = cut p in
        { text; origin = Derived_desc; truncated }

let description_terms d =
  let buf = Buffer.create 16 in
  let out = ref [] in
  let flush () =
    if Buffer.length buf > 0 then (
      out := Buffer.contents buf :: !out;
      Buffer.clear buf)
  in
  String.iter
    (fun c ->
      match c with
      | 'a' .. 'z' | '0' .. '9' -> Buffer.add_char buf c
      | 'A' .. 'Z' -> Buffer.add_char buf (Char.lowercase_ascii c)
      | _ -> flush ())
    d.text;
  flush ();
  sorted_uniq !out

let ranking_terms d ~body_terms = sorted_uniq (body_terms @ description_terms d)
