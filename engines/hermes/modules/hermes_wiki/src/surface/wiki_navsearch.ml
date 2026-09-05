(* HW.6.4.1 / HW.6.4.3 / HW.6.3.3 / HW.6.3.4 / HW.6.11.1 / HW.6.6.1 — the
   navigation and search surfaces. See wiki_navsearch.mli for the laws;
   this file holds only their enforcement.

   R14 REUSE, stated once here and never worked around below: the
   tokeniser is Wiki_search.tokens, the fence grammar is Wiki_ast.fences,
   the ranking kernel is Wiki_graph.pagerank (itself the mirror of
   zigvm's zk_page_rank_calculator), the declared tree is Wiki_toc. This
   module contains no tokeniser, no fence walker for the code index, and
   no power iteration. The only mirrored-rather-than-reused grammars are
   the two todo marks, and the reason is a library boundary this file
   does not own — Wiki_directive and Wiki_callout are both named at the
   mirror site. *)

(* ------------------------------------------------------------ shared *)

let starts_with ~prefix s =
  let np = String.length prefix and ns = String.length s in
  np <= ns && String.sub s 0 np = prefix

let index_of_sub hay needle from =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = if i + nn > nh then None else if String.sub hay i nn = needle then Some i else go (i + 1) in
  if nn = 0 then None else go from

let contains hay needle =
  match index_of_sub hay needle 0 with Some _ -> true | None -> needle = ""

(* pat is a SUBSEQUENCE of s: every character of pat appears in s, in
   order, not necessarily adjacently. The fuzzy matcher, and nothing
   cleverer: a scoring heuristic nobody can predict is a finder whose
   results a reader cannot learn. *)
let subsequence pat s =
  let np = String.length pat and ns = String.length s in
  let rec go i j = if i >= np then true else if j >= ns then false
                   else if pat.[i] = s.[j] then go (i + 1) (j + 1) else go i (j + 1)
  in
  go 0 0

let page_of (m : Hermes_wiki.model) slug =
  List.find_opt (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug = slug) m.Hermes_wiki.pages

let title_of m slug =
  match page_of m slug with Some p -> p.Hermes_wiki.title | None -> ""

let is_page m slug = page_of m slug <> None
let href_of slug = slug ^ ".html"

(* Pages in SLUG order. Hermes_wiki.build hands back the caller's input
   order, so every entry point in this file starts here and never walks
   model.pages directly. *)
let sorted_pages (m : Hermes_wiki.model) =
  List.sort
    (fun (a : Hermes_wiki.page) (b : Hermes_wiki.page) ->
      compare a.Hermes_wiki.slug b.Hermes_wiki.slug)
    m.Hermes_wiki.pages

(* ----------------------------------------------------------- HW.6.4.1 *)

type crumb = { slug : string; title : string; href : string }

let breadcrumb_slugs m t slug =
  match Wiki_toc.path_to t slug with
  | Some path -> path
  | None -> if is_page m slug then [ slug ] else []

let breadcrumb m t slug =
  breadcrumb_slugs m t slug
  |> List.map (fun s -> { slug = s; title = title_of m s; href = href_of s })

let breadcrumb_gaps m t =
  Wiki_toc.placed t
  |> List.concat_map (fun s -> breadcrumb_slugs m t s)
  |> List.sort_uniq compare
  |> List.filter (fun c -> not (is_page m c))
  |> List.map (fun c -> "breadcrumb crumb unresolved: " ^ c)

(* ----------------------------------------------------------- HW.6.3.3 *)

type code_hit = { slug : string; lang : string; fence : int; line : int; text : string }

(* slug, fence ordinal, line ordinal, lang, text, sorted token set *)
type posting = string * int * int * string * string * string list

type index = {
  s : Wiki_search.index;
  code : posting list;             (* sorted by (slug, fence, line) *)
  pages : (string * string) list;  (* slug -> title, sorted by slug *)
}

let build (m : Hermes_wiki.model) =
  let code =
    sorted_pages m
    |> List.concat_map (fun (p : Hermes_wiki.page) ->
           (* the corpus's ONE fence grammar — never a second walk *)
           Wiki_ast.fences (Wiki_ast.parse p.Hermes_wiki.raw)
           |> List.mapi (fun fi (info, body) ->
                  let lang = match Wiki_ast.lang_of_info info with Some l -> l | None -> "" in
                  List.mapi
                    (fun li text ->
                      ( p.Hermes_wiki.slug, fi, li, lang, text,
                        (* the SAME tokeniser prose is indexed with *)
                        List.sort_uniq compare (Wiki_search.tokens text) ))
                    body)
           |> List.concat)
    |> List.sort (fun (a, b, c, _, _, _) (d, e, f, _, _, _) -> compare (a, b, c) (d, e, f))
  in
  let pages =
    sorted_pages m
    |> List.map (fun (p : Hermes_wiki.page) -> (p.Hermes_wiki.slug, p.Hermes_wiki.title))
  in
  { s = Wiki_search.build m; code; pages }

let search_index idx = idx.s

let canonical idx =
  let b = Buffer.create 4096 in
  List.iter (fun (slug, title) -> Buffer.add_string b (Printf.sprintf "P %s\t%s\n" slug title)) idx.pages;
  List.iter
    (fun (slug, fi, li, lang, text, ts) ->
      Buffer.add_string b
        (Printf.sprintf "C %s\t%d\t%d\t%s\t%s\t%s\n" slug fi li lang (String.concat "," ts) text))
    idx.code;
  Buffer.add_string b ("S " ^ Wiki_search.digest idx.s ^ "\n");
  Buffer.contents b

let digest idx = Digest.to_hex (Digest.string (canonical idx))

let code_search idx q =
  match Wiki_search.tokens q with
  | [] -> []
  | qs ->
      idx.code
      |> List.filter_map (fun (slug, fi, li, lang, text, ts) ->
             if List.for_all (fun t -> List.mem t ts) qs then
               Some { slug; lang; fence = fi; line = li; text }
             else None)

let code_slugs idx q = List.sort_uniq compare (List.map (fun h -> h.slug) (code_search idx q))

(* ----------------------------------------------------------- HW.6.4.3 *)

type find_hit = { slug : string; title : string; score : int; why : string }

(* The bands. They do not overlap, and a full-text score is clamped
   INSIDE its band so a page that repeats a word cannot climb out of it. *)
let band_exact_slug = 1000
let band_exact_title = 900
let band_slug_prefix = 800
let band_title_prefix = 700
let band_slug_substr = 600
let band_title_substr = 500
let band_slug_subseq = 400
let band_title_subseq = 300
let band_fulltext = 50 (* + 1..49 *)
let band_code = 40

let reason_of idx q =
  let qslug = Hermes_wiki.slugify q in
  let qlow = String.lowercase_ascii (String.trim q) in
  if qslug = "" then fun _ -> None
  else begin
    let ft = Wiki_search.search idx.s q in
    let cs = code_slugs idx q in
    fun (slug, title) ->
      let tlow = String.lowercase_ascii title in
      let tslug = Hermes_wiki.slugify title in
      let cands =
        [ (slug = qslug, band_exact_slug, "exact slug");
          (tslug = qslug && tslug <> "", band_exact_title, "exact title");
          (starts_with ~prefix:qslug slug, band_slug_prefix, "slug prefix");
          (starts_with ~prefix:qlow tlow, band_title_prefix, "title prefix");
          (contains slug qslug, band_slug_substr, "slug substring");
          (contains tlow qlow, band_title_substr, "title substring");
          (subsequence qslug slug, band_slug_subseq, "slug subsequence");
          (subsequence qlow tlow, band_title_subseq, "title subsequence");
          ( List.mem_assoc slug ft,
            band_fulltext + min 49 (max 1 (Option.value ~default:0 (List.assoc_opt slug ft))),
            "full text" );
          (List.mem slug cs, band_code, "code") ]
      in
      List.fold_left
        (fun acc (ok, sc, why) ->
          match acc with
          | Some (best, _) when best >= sc -> acc
          | _ -> if ok then Some (sc, why) else acc)
        None cands
  end

let quick_find idx q =
  let reason = reason_of idx q in
  idx.pages
  |> List.filter_map (fun (slug, title) ->
         match reason (slug, title) with
         | None -> None
         | Some (score, why) -> Some { slug; title; score; why })
  |> List.sort (fun a b -> if a.score = b.score then compare a.slug b.slug else compare b.score a.score)

let exact_matches idx q =
  if Hermes_wiki.slugify q = "" then []
  else begin
    let qslug = Hermes_wiki.slugify q in
    let named =
      idx.pages
      |> List.filter_map (fun (slug, title) ->
             if slug = qslug || (Hermes_wiki.slugify title = qslug && title <> "") then Some slug
             else None)
    in
    List.sort_uniq compare (named @ List.map fst (Wiki_search.search idx.s q))
  end

(* ----------------------------------------------------------- HW.6.3.4 *)

type ranking = {
  rows : (string * float) list;
  seeds_used : string list;
  seeds_unknown : string list;
}

(* THE one call into the kernel in this file. Grep it: there is exactly
   one occurrence of Wiki_graph.pagerank below, and both consumers reach
   it through [rank]. *)
let rank ?(seeds = []) g =
  let ns = Wiki_graph.nodes g in
  let declared = List.sort_uniq compare seeds in
  { rows = Wiki_graph.pagerank ~seeds g;
    seeds_used = List.filter (fun s -> List.mem s ns) declared;
    seeds_unknown = List.filter (fun s -> not (List.mem s ns)) declared }

let rank_global g = rank ~seeds:[] g
let rank_personal ~seeds g = rank ~seeds g

let related g slug =
  let r = rank ~seeds:[ slug ] g in
  if r.seeds_used = [] then { r with rows = [] }
  else { r with rows = List.filter (fun (s, _) -> s <> slug) r.rows }

let rank_canonical r =
  let b = Buffer.create 256 in
  List.iter (fun (s, x) -> Buffer.add_string b (Printf.sprintf "%s %h\n" s x)) r.rows;
  Buffer.contents b

let rank_mass r slugs =
  (* ascending, deduplicated: a function of the SET, so the last bit of
     the sum cannot depend on the order the caller listed them in *)
  List.sort_uniq compare slugs
  |> List.fold_left
       (fun acc s -> acc +. Option.value ~default:0.0 (List.assoc_opt s r.rows))
       0.0

(* ---------------------------------------------------------- HW.6.11.1 *)

type todo_form = Directive | Callout

type todo = {
  slug : string;
  line : int;
  form : todo_form;
  text : string;
  body : string list;
}

let is_blank s = String.trim s = ""
let is_indented s = String.length s > 0 && (s.[0] = ' ' || s.[0] = '\t')

let leading_spaces s =
  let n = String.length s in
  let rec go i = if i < n && (s.[i] = ' ' || s.[i] = '\t') then go (i + 1) else i in
  go 0

(* de-indent by the MINIMUM leading run over the non-blank lines, so
   nested indentation inside a todo body survives *)
let deindent lines =
  let mins =
    List.filter_map (fun l -> if is_blank l then None else Some (leading_spaces l)) lines
  in
  let cut = List.fold_left min max_int mins in
  let cut = if cut = max_int then 0 else cut in
  List.map
    (fun l ->
      let n = String.length l in
      if is_blank l then "" else if n >= cut then String.sub l cut (n - cut) else String.trim l)
    lines

let trim_edges lines =
  let rec drop = function x :: tl when is_blank x -> drop tl | l -> l in
  List.rev (drop (List.rev (drop lines)))

(* MIRROR of Wiki_directive's column-zero grammar: `.. name:: argument`.
   Not imported — the dune stanza owning this library does not depend on
   hermes_wiki_directive. Because the marker must be at column zero, an
   occurrence inside inline backticks is excluded by construction, which
   is the same argument Wiki_directive makes. *)
let directive_marker line =
  if not (starts_with ~prefix:".. " line) then None
  else
    match index_of_sub line "::" 3 with
    | None -> None
    | Some j ->
        let name = String.lowercase_ascii (String.trim (String.sub line 3 (j - 3))) in
        let arg = String.trim (String.sub line (j + 2) (String.length line - j - 2)) in
        Some (name, arg)

(* MIRROR of Wiki_callout.parse_header restricted to `todo`, which that
   module admits under exactly one spelling and no aliases — so the
   restriction loses nothing. `>` at column zero, optional space,
   `[!todo]`, optional fold `+`/`-`, optional title. *)
let callout_todo line =
  if not (starts_with ~prefix:">" line) then None
  else begin
    let rest = String.sub line 1 (String.length line - 1) in
    let rest = if starts_with ~prefix:" " rest then String.sub rest 1 (String.length rest - 1) else rest in
    let low = String.lowercase_ascii rest in
    if not (starts_with ~prefix:"[!todo]" low) then None
    else begin
      let tail = String.sub rest 7 (String.length rest - 7) in
      let tail =
        if starts_with ~prefix:"+" tail || starts_with ~prefix:"-" tail then
          String.sub tail 1 (String.length tail - 1)
        else tail
      in
      Some (String.trim tail)
    end
  end

let scan_todos slug raw =
  let lines = Array.of_list (String.split_on_char '\n' raw) in
  let n = Array.length lines in
  let body_from i pred =
    let rec go j acc = if j >= n || not (pred lines.(j)) then List.rev acc else go (j + 1) (lines.(j) :: acc) in
    go i []
  in
  let out = ref [] in
  let in_fence = ref false in
  for i = 0 to n - 1 do
    let l = lines.(i) in
    let t = String.trim l in
    if String.length t >= 3 && String.sub t 0 3 = "```" then in_fence := not !in_fence
    else if not !in_fence then begin
      match directive_marker l with
      | Some ("todo", arg) ->
          let body = trim_edges (deindent (trim_edges (body_from (i + 1) (fun x -> is_blank x || is_indented x)))) in
          out := { slug; line = i; form = Directive; text = arg; body } :: !out
      | _ -> (
          match callout_todo l with
          | Some title ->
              let raw_body = body_from (i + 1) (fun x -> starts_with ~prefix:">" x) in
              let body =
                trim_edges
                  (List.map
                     (fun x ->
                       let r = String.sub x 1 (String.length x - 1) in
                       if starts_with ~prefix:" " r then String.sub r 1 (String.length r - 1) else r)
                     raw_body)
              in
              out := { slug; line = i; form = Callout; text = title; body } :: !out
          | None -> ())
    end
  done;
  List.rev !out

let todos (m : Hermes_wiki.model) =
  sorted_pages m
  |> List.concat_map (fun (p : Hermes_wiki.page) -> scan_todos p.Hermes_wiki.slug p.Hermes_wiki.raw)

let todos_of m slug = List.filter (fun t -> t.slug = slug) (todos m)

(* ----------------------------------------------------------- HW.6.6.1 *)

type revision = { commit : string; order : int; files : (string * string) list }

type history = {
  revs : (string * (string * string) list) list;  (* commit order *)
  dups : string list;
}

let history_of rs =
  let ordered =
    List.stable_sort
      (fun a b -> if a.order = b.order then compare a.commit b.commit else compare a.order b.order)
      rs
  in
  let seen = Hashtbl.create 16 in
  let dups = ref [] in
  let kept =
    List.filter_map
      (fun r ->
        if Hashtbl.mem seen r.commit then begin
          dups := r.commit :: !dups;
          None
        end
        else begin
          Hashtbl.replace seen r.commit ();
          (* the snapshot is CANONICAL: sorted by path, so a revision is
             a function of its file SET and not of the caller's listing *)
          Some (r.commit, List.stable_sort (fun (a, _) (b, _) -> compare a b) r.files)
        end)
      ordered
  in
  { revs = kept; dups = List.sort_uniq compare !dups }

let commits h = List.map fst h.revs
let duplicate_commits h = h.dups
let checkout h c = List.assoc_opt c h.revs

(* THE identity, spelled out: as_of(c) = build(checkout c). Re-derived on
   every call — never cached, so an as-of answer cannot be stale. *)
let as_of h c = Option.map Hermes_wiki.build (checkout h c)
let index_as_of h c = Option.map build (as_of h c)
