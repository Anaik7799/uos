(* The dependency sheaf. See dep_sheaf.mli for the site, the law and the
   adaptations. Implementation notes:

   - The resolver key table is built ONCE per Env from
     Hermes_wiki.resolver_keys, in corpus order with first-registration-wins
     — the same policy as Hermes_wiki.build, from the same source of truth.
   - [section] renders through Hermes_wiki.render_markdown with a resolve
     function derived from the VIEW's [observe]; the view is the only thing
     it closes over, so the restriction law is a property of this module's
     construction, not a runtime check.
   - Perturbation for [dead_cover_elements] is the existence flip described
     in the .mli: drop the page if present, add a stub if absent, rebuild
     the model, re-derive the environment, compare bytes. *)

module StringSet = Set.Make (String)
module StringMap = Map.Make (String)

module Cover = struct
  type t = StringSet.t

  let empty = StringSet.empty
  let of_list xs = StringSet.of_list xs
  let union = StringSet.union
  let inter = StringSet.inter
  let mem t x = StringSet.mem x t
  let elements = StringSet.elements (* sorted: L27.6 *)
  let equal = StringSet.equal
end

module Observable = struct
  type t = { exists : bool; title : string; anchors : string list }
end

module Env = struct
  type t = {
    observables : Observable.t StringMap.t;
    canonical : string StringMap.t; (* resolver key -> slug, first wins *)
  }

  type view = { env : t; cover : Cover.t }

  let of_model (m : Hermes_wiki.model) =
    let observables =
      List.fold_left
        (fun acc (p : Hermes_wiki.page) ->
          StringMap.add p.Hermes_wiki.slug
            { Observable.exists = true;
              title = p.Hermes_wiki.title;
              anchors = List.map (fun (_, _, a) -> a) p.Hermes_wiki.headings }
            acc)
        StringMap.empty m.Hermes_wiki.pages
    in
    let canonical =
      (* pass 1: identity keys, corpus order, first wins — build's policy;
         pass 2: ALIAS keys after every identity key, so an alias can never
         shadow a slug/title/basename (HW.1.2.7). Same two-pass shape as
         build, from the same exported key functions. *)
      let pass1 =
        List.fold_left
          (fun table (p : Hermes_wiki.page) ->
            List.fold_left
              (fun table key ->
                if key = "" || StringMap.mem key table then table
                else StringMap.add key p.Hermes_wiki.slug table)
              table (Hermes_wiki.resolver_keys p))
          StringMap.empty m.Hermes_wiki.pages
      in
      List.fold_left
        (fun table (p : Hermes_wiki.page) ->
          List.fold_left
            (fun table key ->
              if key = "" || StringMap.mem key table then table
              else StringMap.add key p.Hermes_wiki.slug table)
            table (Hermes_wiki.alias_keys p))
        pass1 m.Hermes_wiki.pages
    in
    { observables; canonical }

  let restrict env cover = { env; cover }
  let narrow v c = { v with cover = Cover.inter v.cover c } (* L27.2 *)

  let observe v slug =
    if Cover.mem v.cover slug then StringMap.find_opt slug v.env.observables
    else None (* outside the cover a page is invisible: the restriction *)

  let cover_of v = v.cover
end

module Section = struct
  type t = string

  let empty = ""
  let append = ( ^ )
  let bytes s = s
end

(* the canonical slug a link target resolves to, through the env's table;
   a miss falls back to the slugified target (which then observes to None,
   rendering as visibly missing — the same behaviour either side of a
   restriction, so misses cannot break L27.1) *)
let canonical_slug (env : Env.t) target =
  let key = Hermes_wiki.slugify (Hermes_wiki.strip_fragment target) in
  match StringMap.find_opt key env.Env.canonical with Some s -> s | None -> key

(* What a document's render OBSERVES: the canonical slugs of the wikilink
   payload targets in its RAW body. Raw, not the curated outlinks — see the
   .mli header for why (allow_example_links). *)
let deps_in (env : Env.t) (p : Hermes_wiki.page) =
  Hermes_wiki.raw_link_targets p.Hermes_wiki.raw
  |> List.map (canonical_slug env)
  |> Cover.of_list

let deps (m : Hermes_wiki.model) (p : Hermes_wiki.page) =
  deps_in (Env.of_model m) p

let section (v : Env.view) (p : Hermes_wiki.page) =
  let resolve target =
    let slug = canonical_slug v.Env.env target in
    match Env.observe v slug with
    | Some o when o.Observable.exists -> Some (slug ^ ".html")
    | _ -> None
  in
  Hermes_wiki.render_markdown ~resolve p.Hermes_wiki.raw

let render v p = Section.bytes (section v p)

let build (env : Env.t) (m : Hermes_wiki.model) =
  List.map
    (fun (p : Hermes_wiki.page) ->
      (p.Hermes_wiki.slug, section (Env.restrict env (deps_in env p)) p))
    m.Hermes_wiki.pages

(* slug order: ONE serialisation, so gluing is family-order- and
   partition-independent (L27.3) *)
let glue family =
  List.sort (fun (a, _) (b, _) -> compare a b) family
  |> List.fold_left (fun acc (_, s) -> Section.append acc s) Section.empty

let dependents (m : Hermes_wiki.model) slug =
  let env = Env.of_model m in
  List.filter_map
    (fun (p : Hermes_wiki.page) ->
      if Cover.mem (deps_in env p) slug then Some p.Hermes_wiki.slug else None)
    m.Hermes_wiki.pages

let rebuild ~previous (env : Env.t) ~changed (m : Hermes_wiki.model) =
  let dirty (p : Hermes_wiki.page) =
    Cover.mem changed p.Hermes_wiki.slug
    || not (Cover.equal (Cover.inter (deps_in env p) changed) Cover.empty)
  in
  List.map
    (fun (p : Hermes_wiki.page) ->
      let slug = p.Hermes_wiki.slug in
      if dirty p then (slug, section (Env.restrict env (deps_in env p)) p)
      else
        match List.assoc_opt slug previous with
        | Some s -> (slug, s)
        | None -> (slug, section (Env.restrict env (deps_in env p)) p))
    m.Hermes_wiki.pages

let dead_cover_elements ?(widen_with = []) (m : Hermes_wiki.model)
    (p : Hermes_wiki.page) =
  let baseline_files =
    List.map (fun (q : Hermes_wiki.page) -> (q.Hermes_wiki.path, q.Hermes_wiki.raw))
      m.Hermes_wiki.pages
  in
  let base_cover = Cover.union (deps m p) (Cover.of_list widen_with) in
  let render_in files =
    let m' = Hermes_wiki.build files in
    match
      List.find_opt
        (fun (q : Hermes_wiki.page) -> q.Hermes_wiki.slug = p.Hermes_wiki.slug)
        m'.Hermes_wiki.pages
    with
    | None -> None
    | Some p' ->
        let env' = Env.of_model m' in
        let all' =
          Cover.of_list
            (List.map (fun (q : Hermes_wiki.page) -> q.Hermes_wiki.slug)
               m'.Hermes_wiki.pages)
        in
        Some (render (Env.restrict env' all') p')
  in
  match render_in baseline_files with
  | None -> []
  | Some before ->
      List.filter
        (fun y ->
          if y = p.Hermes_wiki.slug then false
          else
            let exists =
              List.exists
                (fun (q : Hermes_wiki.page) -> q.Hermes_wiki.slug = y)
                m.Hermes_wiki.pages
            in
            let perturbed =
              if exists then
                List.filter
                  (fun (path, _) ->
                    match
                      List.find_opt
                        (fun (q : Hermes_wiki.page) -> q.Hermes_wiki.path = path)
                        m.Hermes_wiki.pages
                    with
                    | Some q -> q.Hermes_wiki.slug <> y
                    | None -> true)
                  baseline_files
              else
                baseline_files
                @ [ ("docs/hermes/zk/" ^ y ^ ".md", "# " ^ y ^ "\n\nStub.\n") ]
            in
            match render_in perturbed with
            | None -> true (* cannot even perturb: dead by vacuity, report it *)
            | Some after -> String.equal before after)
        (Cover.elements base_cover)
