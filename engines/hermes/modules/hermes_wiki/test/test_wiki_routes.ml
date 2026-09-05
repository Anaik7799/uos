(* The typed route algebra and the Dream resolution layer. The laws that
   the type is supposed to buy: enumeration is total, every route round
   trips, no write verb is expressible, and a target that does not parse
   to a route can never reach a page. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed; print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let pages =
  [ ("index.html", "<h1>hub</h1>"); ("wiki.html", "<h1>wiki</h1>");
    ("component-evidence_store.html", "<h1>store</h1>");
    ("mandatory-rules.html", "<h1>rules</h1>") ]

let resolve target = Wiki_dream.resolve ~pages ~model_json:"{}" ~css:"body{}" ~target

let () =
  check "every route round trips through to_path / of_path" (fun () ->
      List.for_all
        (fun route -> Wiki_routes.of_path (Wiki_routes.to_path route) = Some route)
        Wiki_routes.all);
  check "the enumeration covers every constructor (14)" (fun () ->
      List.length Wiki_routes.all = 14);
  check "patterns are unique per shape and parameterized where needed" (fun () ->
      Wiki_routes.pattern (Wiki_routes.Component "x") = "/component-:slug.html"
      && Wiki_routes.pattern (Wiki_routes.Wiki_page "x") = "/:slug.html"
      && Wiki_routes.pattern Wiki_routes.Index = "/");
  check "page_name is None exactly for the non-page routes" (fun () ->
      Wiki_routes.page_name Wiki_routes.Model_json = None
      && Wiki_routes.page_name Wiki_routes.Stylesheet = None
      && Wiki_routes.page_name Wiki_routes.Index = Some "index.html");
  check "a query string does not change the route" (fun () ->
      Wiki_routes.of_path "/wiki.html?x=1" = Some Wiki_routes.Wiki_index)

let () =
  check "the index resolves to the hub page" (fun () ->
      match resolve "/" with Wiki_dream.Page (_, body) -> body = "<h1>hub</h1>" | _ -> false);
  (* Real component ids carry UNDERSCORES (evidence_store). The first
     cut of this test used a hyphen and passed while every component
     page 404d live. *)
  check "a component route resolves through its slug (underscores included)" (fun () ->
      match resolve "/component-evidence_store.html" with
      | Wiki_dream.Page (_, body) -> body = "<h1>store</h1>"
      | _ -> false);
  check "a wiki page resolves through its slug" (fun () ->
      match resolve "/mandatory-rules.html" with
      | Wiki_dream.Page (_, body) -> body = "<h1>rules</h1>"
      | _ -> false);
  check "model.json is served as json, not html" (fun () ->
      match resolve "/model.json" with
      | Wiki_dream.Page (ct, body) -> ct = "application/json" && body = "{}"
      | _ -> false);
  check "the stylesheet is served as css" (fun () ->
      match resolve "/site.css" with
      | Wiki_dream.Page (ct, _) -> ct = "text/css; charset=utf-8"
      | _ -> false);
  check "a route with no built page is Not_found, never a disk read" (fun () ->
      resolve "/zk.html" = Wiki_dream.Not_found);
  check "traversal cannot be EXPRESSED as a route" (fun () ->
      List.for_all
        (fun target -> Wiki_routes.of_path target = None)
        [ "/../dune"; "/etc/passwd"; "//etc/hostname"; "/./../secrets";
          "/a/b.html"; "/UPPER.html"; "/with space.html" ]);
  check "and therefore never resolves to a page" (fun () ->
      List.for_all
        (fun target -> resolve target = Wiki_dream.Not_found)
        [ "/../dune"; "/etc/passwd"; "/a/b.html" ]);
  check "resolution is deterministic" (fun () -> resolve "/" = resolve "/")

let () =
  check "every response carries the security headers" (fun () ->
      let has key = List.mem_assoc key Wiki_dream.security_headers in
      has "Content-Security-Policy" && has "X-Content-Type-Options"
      && has "X-Frame-Options" && has "Referrer-Policy" && has "Cache-Control");
  check "the CSP forbids scripts and forms by default" (fun () ->
      match List.assoc_opt "Content-Security-Policy" Wiki_dream.security_headers with
      | Some policy ->
          let contains needle =
            let n = String.length needle and h = String.length policy in
            let rec go i = i + n <= h && (String.sub policy i n = needle || go (i + 1)) in
            go 0
          in
          contains "default-src 'none'" && contains "form-action 'none'"
      | None -> false);
  check "the handler builds (the router is derived from the route type)"
    (fun () ->
      let handler : Dream.handler = Wiki_dream.handler ~pages ~model_json:"{}" ~css:"" in
      ignore handler;
      true)


(* ------------------------------------------------- through the ROUTER *)

(* The unit checks above exercise [resolve]. They stayed green while every
   component page 404'd live, because Dream's [:param] matches a whole
   path segment and "/component-:slug.html" therefore never matched. This
   block drives the real Dream handler with Dream.test, so a routing
   defect fails here instead of in production. *)
let status_of target =
  let handler = Wiki_dream.handler ~pages ~model_json:"{}" ~css:"body{}" in
  let request = Dream.request ~method_:`GET ~target "" in
  let response = Dream.test handler request in
  Dream.status_to_int (Dream.status response)

let () =
  check "ROUTER: the index answers 200" (fun () -> status_of "/" = 200);
  check "ROUTER: a component page with an UNDERSCORE slug answers 200"
    (fun () -> status_of "/component-evidence_store.html" = 200);
  check "ROUTER: a wiki page answers 200" (fun () ->
      status_of "/mandatory-rules.html" = 200);
  check "ROUTER: model.json answers 200" (fun () -> status_of "/model.json" = 200);
  check "ROUTER: an unbuilt page answers 404" (fun () -> status_of "/zk.html" = 404);
  check "ROUTER: traversal answers 404" (fun () ->
      status_of "/../dune" = 404 && status_of "/etc/passwd" = 404)

let () =
  Printf.printf "wiki_routes: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_routes" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
