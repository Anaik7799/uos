(* HW.6.8.1 — the declared navigation tree. See the mli: the tree law is
   carried by ONE line, the claim placed before the descent. *)

type entry = {
  target : string;
  hidden : bool;
  caption : string;
  maxdepth : int option;
  titlesonly : bool;
  numbered : bool;
}

type node = {
  slug : string;
  title : string;
  hidden : bool;
  numbered : bool;  (* the edge that PLACED this node asked for numbering *)
  caption : string;
  children : node list;
}

type t = { root : node; gaps : string list; conflicts : (string * string) list }

let tokens info =
  String.split_on_char ' ' info
  |> List.concat_map (String.split_on_char '\t')
  |> List.filter (fun s -> s <> "")

let strip_key key tok =
  let k = key ^ "=" in
  let nk = String.length k and nt = String.length tok in
  if nt > nk && String.sub tok 0 nk = k then Some (String.sub tok nk (nt - nk)) else None

let parse_fence info body =
  match tokens info with
  | "toctree" :: opts ->
      let hidden = List.mem "hidden" opts in
      let titlesonly = List.mem "titlesonly" opts in
      let numbered = List.mem "numbered" opts in
      let reversed = List.mem "reversed" opts in
      let caption =
        List.fold_left
          (fun acc t -> match strip_key "caption" t with Some v -> v | None -> acc)
          "" opts
      in
      let maxdepth =
        List.fold_left
          (fun acc t ->
            match strip_key "maxdepth" t with
            | Some v -> (
                match int_of_string_opt v with Some n when n > 0 -> Some n | _ -> acc)
            | None -> acc)
          None opts
      in
      let targets =
        body
        |> List.map String.trim
        |> List.filter (fun l ->
               l <> "" && not (String.length l >= 1 && l.[0] = '#'))
        |> List.fold_left
             (* duplicates within ONE fence collapse to the first: the
                author wrote the order once, and a repeat is not a second
                placement *)
             (fun acc t -> if List.mem t acc then acc else t :: acc)
             []
        |> List.rev
      in
      let targets = if reversed then List.rev targets else targets in
      Some
        (List.map
           (fun target -> { target; hidden; caption; maxdepth; titlesonly; numbered })
           targets)
  | _ -> None

let entries_of_page (p : Hermes_wiki.page) =
  Wiki_ast.fences (Wiki_ast.parse p.Hermes_wiki.raw)
  |> List.concat_map (fun (info, body) ->
         match parse_fence info body with Some es -> es | None -> [])

let of_model (m : Hermes_wiki.model) =
  (* the engine's OWN key space, two passes, identity before alias *)
  let keys : (string, string) Hashtbl.t = Hashtbl.create 512 in
  let add k slug = if k <> "" && not (Hashtbl.mem keys k) then Hashtbl.replace keys k slug in
  List.iter
    (fun (p : Hermes_wiki.page) ->
      List.iter (fun k -> add k p.Hermes_wiki.slug) (Hermes_wiki.resolver_keys p))
    m.Hermes_wiki.pages;
  List.iter
    (fun (p : Hermes_wiki.page) ->
      List.iter (fun k -> add k p.Hermes_wiki.slug) (Hermes_wiki.alias_keys p))
    m.Hermes_wiki.pages;
  let title_of slug =
    match
      List.find_opt (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug = slug) m.Hermes_wiki.pages
    with
    | Some p -> p.Hermes_wiki.title
    | None -> ""
  in
  let gaps = ref [] and conflicts = ref [] in
  (* declarations in SLUG order — input order cannot matter *)
  let decls =
    m.Hermes_wiki.pages
    |> List.filter_map (fun (p : Hermes_wiki.page) ->
           match entries_of_page p with [] -> None | es -> Some (p.Hermes_wiki.slug, es))
    |> List.sort (fun (a, _) (b, _) -> compare a b)
  in
  let edges : (string, (string * entry) list) Hashtbl.t = Hashtbl.create 64 in
  let inbound : (string, unit) Hashtbl.t = Hashtbl.create 64 in
  List.iter
    (fun (declarer, es) ->
      let resolved =
        List.filter_map
          (fun e ->
            let key = Hermes_wiki.slugify e.target in
            match Hashtbl.find_opt keys key with
            | None ->
                gaps :=
                  Printf.sprintf "toc target unresolved: [[%s]] in %s" e.target declarer :: !gaps;
                None
            | Some target when target = declarer ->
                gaps := Printf.sprintf "toc self-reference: %s names itself" declarer :: !gaps;
                None
            | Some target ->
                Hashtbl.replace inbound target ();
                Some (target, e))
          es
      in
      Hashtbl.replace edges declarer resolved)
    decls;
  let claimed : (string, unit) Hashtbl.t = Hashtbl.create 64 in
  let children_of slug = match Hashtbl.find_opt edges slug with Some l -> l | None -> [] in
  let rec node_of ~hidden ~numbered ~caption slug =
    (* PRECONDITION: slug is already claimed. *)
    let children =
      children_of slug
      (* the annotation matters: `node` and `entry` share the field names
         `hidden` and `caption`, and the LAST definition wins inference *)
      |> List.filter_map (fun (target, (e : entry)) ->
             if Hashtbl.mem claimed target then (
               conflicts := (slug, target) :: !conflicts;
               None)
             else begin
               (* THE line the whole tree law rests on: claim BEFORE
                  descending, so "created" and "newly claimed" are one
                  event and a cycle cannot re-enter. *)
               Hashtbl.replace claimed target ();
               (* numbering is INHERITED downward: a numbered section's
                  subsections are numbered too *)
               Some
                 (node_of ~hidden:e.hidden ~numbered:(numbered || e.numbered)
                    ~caption:e.caption target)
             end)
    in
    { slug; title = title_of slug; hidden; numbered; caption; children }
  in
  (* Seeds in two segments: the natural forest tops first, then EVERY
     declarer. The tail is the cycle breaker — in a pure cycle a <-> b
     both have inbound edges, so without it neither would be placed and
     both would vanish silently. The tail opens the cycle at its smallest
     slug, deterministically. *)
  let seeds =
    List.filter (fun (s, _) -> not (Hashtbl.mem inbound s)) decls
    @ decls
    |> List.map fst
  in
  let roots =
    List.filter_map
      (fun s ->
        if Hashtbl.mem claimed s then None
        else begin
          Hashtbl.replace claimed s ();
          Some (node_of ~hidden:false ~numbered:false ~caption:"" s)
        end)
      seeds
  in
  { root = { slug = ""; title = ""; hidden = false; numbered = false; caption = ""; children = roots };
    gaps = List.sort_uniq compare !gaps;
    conflicts = List.sort_uniq compare !conflicts }

let root t = t.root
let gaps t = t.gaps
let conflicts t = t.conflicts

let walk t =
  let rec go depth n =
    List.concat_map
      (fun c -> (c.slug, depth, c.hidden) :: go (depth + 1) c)
      n.children
  in
  go 1 t.root

let placed t = List.sort_uniq compare (List.map (fun (s, _, _) -> s) (walk t))

let unplaced (m : Hermes_wiki.model) t =
  let p = placed t in
  m.Hermes_wiki.pages
  |> List.filter_map (fun (pg : Hermes_wiki.page) ->
         if List.mem pg.Hermes_wiki.slug p then None else Some pg.Hermes_wiki.slug)
  |> List.sort_uniq compare

(* HW.6.8.2 — the verdict: unplaced MINUS the pages that disclosed it. *)
let unreachable (m : Hermes_wiki.model) t =
  let p = placed t in
  m.Hermes_wiki.pages
  |> List.filter_map (fun (pg : Hermes_wiki.page) ->
         if List.mem pg.Hermes_wiki.slug p then None
         else if pg.Hermes_wiki.meta.Hermes_wiki.orphan then None
         else Some pg.Hermes_wiki.slug)
  |> List.sort_uniq compare

let disclosed_orphans (m : Hermes_wiki.model) =
  m.Hermes_wiki.pages
  |> List.filter_map (fun (p : Hermes_wiki.page) ->
         if p.Hermes_wiki.meta.Hermes_wiki.orphan then Some p.Hermes_wiki.slug else None)
  |> List.sort_uniq compare

(* HW.6.8.3 — numbering as a function of POSITION. A node's label is its
   1-based index among its numbered siblings, prefixed by its parent's
   label; only subtrees introduced by a `numbered` entry are labelled, and
   the flag is inherited downward because a numbered section's
   subsections are numbered too. *)
let numbering t =
  let out = ref [] in
  let rec go prefix children =
    (* the counter advances only on NUMBERED siblings, so an unnumbered
       neighbour never consumes a number *)
    let i = ref 0 in
    List.iter
      (fun c ->
        if c.numbered then begin
          incr i;
          let label = if prefix = "" then string_of_int !i else prefix ^ "." ^ string_of_int !i in
          out := (c.slug, label) :: !out;
          go label c.children
        end
        else go prefix c.children)
      children
  in
  go "" t.root.children;
  List.rev !out

let path_to t slug =
  let rec go prefix n =
    if n.slug = slug && n.slug <> "" then Some (List.rev (n.slug :: prefix))
    else
      let prefix = if n.slug = "" then prefix else n.slug :: prefix in
      List.fold_left
        (fun acc c -> match acc with Some _ -> acc | None -> go prefix c)
        None n.children
  in
  go [] t.root
