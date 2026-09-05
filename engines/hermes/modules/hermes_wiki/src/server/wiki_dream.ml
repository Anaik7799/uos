(* The Dream server. See wiki_dream.mli.

   Dream replaces the hand-rolled Unix socket loop, but nothing about the
   authority model changes: the router is derived from the typed route
   list, only Dream.get is called, and the page table is still the route
   table — a target that does not parse to a route can never become a
   filesystem path. *)

let security_headers =
  [ ("Content-Security-Policy",
     "default-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; \
      base-uri 'none'; form-action 'none'");
    ("X-Content-Type-Options", "nosniff");
    ("X-Frame-Options", "DENY");
    ("Referrer-Policy", "no-referrer");
    ("Cache-Control", "no-store") ]

let html_type = "text/html; charset=utf-8"

type resolution =
  | Page of string * string
  | Not_found

let resolve ~pages ~model_json ~css ~target =
  match Wiki_routes.of_path target with
  | None -> Not_found
  | Some Wiki_routes.Model_json -> Page ("application/json", model_json)
  | Some Wiki_routes.Stylesheet -> Page ("text/css; charset=utf-8", css)
  | Some route -> (
      match Wiki_routes.page_name route with
      | None -> Not_found
      | Some name -> (
          match List.assoc_opt name pages with
          | Some body -> Page (html_type, body)
          | None -> Not_found))

let with_headers ~content_type response =
  List.iter (fun (k, v) -> Dream.add_header response k v) security_headers;
  Dream.set_header response "Content-Type" content_type;
  response

let respond ~pages ~model_json ~css request =
  let target = Dream.target request in
  match resolve ~pages ~model_json ~css ~target with
  | Page (content_type, body) ->
      Lwt.bind (Dream.respond body) (fun response ->
          Lwt.return (with_headers ~content_type response))
  | Not_found ->
      Lwt.bind
        (Dream.respond ~status:`Not_Found
           "<h1>404</h1><p>No such page. <a href=\"/\">index</a></p>")
        (fun response -> Lwt.return (with_headers ~content_type:html_type response))

let handler ~pages ~model_json ~css =
  (* Dream's [:param] matches a WHOLE path segment, so a pattern like
     "/component-:slug.html" never matches — the first cut registered
     exactly that and every component page 404'd live while the unit
     tests (which exercised [resolve], not the router) stayed green.

     The fix is also the better design: Wiki_routes.of_path is the
     decision-maker, and Dream contributes transport only. Only
     Dream.get is registered, so there is still no write verb; the
     typed parser still rejects anything outside the slug alphabet, so
     a target can never become a filesystem path. *)
  Dream.router
    [ Dream.get "/" (fun request -> respond ~pages ~model_json ~css request);
      Dream.get "/**" (fun request -> respond ~pages ~model_json ~css request) ]

let serve ~pages ~model_json ~css ~port =
  Dream.run ~interface:"0.0.0.0" ~port ~error_handler:Dream.debug_error_handler
    (Dream.logger @@ handler ~pages ~model_json ~css)
