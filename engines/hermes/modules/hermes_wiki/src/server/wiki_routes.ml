(* The typed route algebra. See wiki_routes.mli. *)

type t =
  | Index
  | Dashboard
  | Components
  | Component of string
  | Usecases
  | Operations
  | Analytics
  | Wiki_index
  | Wiki_page of string
  | Zk_graph
  | Atlas
  | Plan
  | Model_json
  | Stylesheet

let all =
  [ Index; Dashboard; Components; Component "sample"; Usecases; Operations;
    Analytics; Wiki_index; Wiki_page "sample"; Zk_graph; Atlas; Plan;
    Model_json; Stylesheet ]

let to_path = function
  | Index -> "/"
  | Dashboard -> "/dashboard.html"
  | Components -> "/components.html"
  | Component slug -> "/component-" ^ slug ^ ".html"
  | Usecases -> "/usecases.html"
  | Operations -> "/operations.html"
  | Analytics -> "/analytics.html"
  | Wiki_index -> "/wiki.html"
  | Wiki_page slug -> "/" ^ slug ^ ".html"
  | Zk_graph -> "/zk.html"
  | Atlas -> "/atlas.html"
  | Plan -> "/plan.html"
  | Model_json -> "/model.json"
  | Stylesheet -> "/site.css"

let pattern = function
  | Component _ -> "/component-:slug.html"
  | Wiki_page _ -> "/:slug.html"
  | route -> to_path route

let page_name = function
  | Model_json | Stylesheet -> None
  | Index -> Some "index.html"
  | route ->
      let path = to_path route in
      Some (String.sub path 1 (String.length path - 1))

let strip_query path =
  match String.index_opt path '?' with
  | Some i -> String.sub path 0 i
  | None -> path

let of_path raw =
  let path = strip_query raw in
  let named =
    List.filter_map
      (fun route ->
        match route with
        | Component _ | Wiki_page _ -> None
        | route -> if to_path route = path then Some route else None)
      all
  in
  match named with
  | route :: _ -> Some route
  | [] ->
      (* Parameterized routes. A slug is [a-z0-9-]+ by construction (the
         wiki's slugify alphabet), so a path that is not exactly that
         cannot match — traversal is unexpressible rather than filtered. *)
      let is_slug s =
        s <> ""
        && String.for_all
             (* The wiki's slugify alphabet is [a-z0-9_-] — component ids
                like evidence_store carry underscores, and a parser that
                omitted them made every component page unreachable (found
                live, not in review). Crucially this alphabet still has
                no '/', no '.', so traversal stays unexpressible. *)
             (fun c ->
               (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-' || c = '_')
             s
      in
      if String.length path > 1 && path.[0] = '/' && Filename.check_suffix path ".html"
      then begin
        let body =
          String.sub path 1 (String.length path - 1 - String.length ".html")
        in
        let component_prefix = "component-" in
        let has_prefix =
          String.length body > String.length component_prefix
          && String.sub body 0 (String.length component_prefix) = component_prefix
        in
        if has_prefix then
          let slug =
            String.sub body (String.length component_prefix)
              (String.length body - String.length component_prefix)
          in
          if is_slug slug then Some (Component slug) else None
        else if is_slug body then Some (Wiki_page body)
        else None
      end
      else None
