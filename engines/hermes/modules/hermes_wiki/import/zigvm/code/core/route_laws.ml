(* route_laws.ml — the executable specification of the route algebra.

   Shared by the standalone test executable and the harness's formal stage, so
   there is one implementation of the laws and not two that can disagree.

   The laws are ordered by what they buy:

     TOTALITY-OF-WITNESSES  makes every other law a quantification over the
                            route TYPE rather than over a sample
     ROUND-TRIP             the URL is a faithful encoding of the route
     ORACLE≡FINAL           the fast parser agrees with the obvious one — the
                            only law that can see a shadowed branch
     INJECTIVITY            no two routes share an address
     CANONICITY             a rendered path is already normal form
     ENCODING               adversarial identifiers survive the round trip
     TOTALITY               the parser never raises on bytes from a peer
     QUERY-TYPED            an unrecognised query value is rejected, never
                            silently defaulted
     COVERAGE               the algebra has not drifted from the live router

   COVERAGE is the one that keeps the rest honest. Every other law is a
   statement about the algebra in isolation, and an algebra that no longer
   describes the running server is worse than no algebra, because it reads
   like evidence. *)

module R = Route_algebra

let failures = ref 0
let laws = ref 0

let check name ok =
  incr laws;
  if ok then Printf.printf "  PASS  %s\n" name
  else begin
    incr failures;
    Printf.printf "  FAIL  %s\n" name
  end

let read_file path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

let contains hay needle =
  let nl = String.length needle and hl = String.length hay in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl > 0 && go 0

(* Every occurrence of `Dream.<verb> "<pattern>"` in a source file: the
   router's own view of what it serves, read from the source of truth rather
   than from a list someone maintains by hand. *)
let served_patterns (src : string) : (string * string) list =
  let verbs = [ "get"; "post"; "put"; "patch"; "delete"; "head" ] in
  let out = ref [] in
  List.iter
    (fun verb ->
      let needle = "Dream." ^ verb ^ " \"" in
      let nl = String.length needle in
      let n = String.length src in
      let i = ref 0 in
      while !i + nl <= n do
        if String.sub src !i nl = needle then begin
          let j = ref (!i + nl) in
          while !j < n && src.[!j] <> '"' do incr j done;
          if !j < n then
            out := (String.uppercase_ascii verb, String.sub src (!i + nl) (!j - !i - nl)) :: !out;
          i := !j
        end
        else incr i
      done)
    verbs;
  List.sort_uniq compare !out

let run ~(root : string) : int =
  failures := 0;
  laws := 0;
  print_endline "route-algebra laws";

  let ids = List.filter_map R.Id.of_string [ "w"; "w2" ] in
  let id = match ids with i :: _ -> i | [] -> assert false in
  ignore id;

  (* LAW TOTALITY-OF-WITNESSES — `all` covers every constructor exactly once.
     Without this, every law below silently narrows to whatever happens to be
     in the list, which is how a new route gets shipped unverified. *)
  let indices = List.map R.constructor_index R.all in
  let sorted = List.sort compare indices in
  check "LAW TOTALITY-OF-WITNESSES: every constructor has exactly one witness"
    (List.length R.all = R.constructor_count
    && sorted = List.init R.constructor_count (fun i -> i));

  (* LAW ROUND-TRIP — parsing the denotation returns the route. *)
  check "LAW ROUND-TRIP: of_target (denote r) = Some r, for every route"
    (List.for_all
       (fun r ->
         match R.of_target (R.denote r) with
         | Some r' -> R.constructor_index r' = R.constructor_index r && R.to_path r' = R.to_path r
         | None -> false)
       R.all);

  (* LAW ROUND-TRIP-URL — the same through the rendered URL and the raw
     parser, which is the path an actual request takes. *)
  check "LAW ROUND-TRIP-URL: parse (to_path r) = Some r, through the wire form"
    (List.for_all
       (fun r ->
         let m = R.meth_to_string (R.meth_of r) in
         match R.parse ~meth:m ~path:(R.to_path r) with
         | Some r' -> R.to_path r' = R.to_path r && R.constructor_index r' = R.constructor_index r
         | None -> false)
       R.all);

  (* LAW ORACLE≡FINAL — the shipped matcher agrees with the table scan, over
     the witnesses and over generated traffic. A misordered branch in the
     final encoding is invisible to every other law here. *)
  let agree d =
    match (R.of_target_oracle d, R.of_target d) with
    | None, None -> true
    | Some a, Some b -> R.constructor_index a = R.constructor_index b && R.to_path a = R.to_path b
    | _ -> false
  in
  check "LAW ORACLE-FINAL: the two encodings agree on every witness"
    (List.for_all (fun r -> agree (R.denote r)) R.all);

  let st = Random.State.make [| 20260805 |] in
  let words = [| "api"; "v1"; "projects"; "views"; "notes"; "share"; "graphs"; "jobs";
                 "export"; "analytics"; "preview"; "commands"; "bonsai"; "health";
                 "assets"; "duplicate"; "7"; "x"; ""; "events"; "zigvm-bonsai.js" |] in
  let meths = [| R.GET; R.POST; R.PUT; R.PATCH; R.DELETE; R.HEAD |] in
  let generated = ref [] in
  for _ = 1 to 4000 do
    let k = Random.State.int st 7 in
    let segs = List.init k (fun _ -> words.(Random.State.int st (Array.length words))) in
    let q =
      if Random.State.bool st then [ ("format", [| "json"; "dot"; "graphml"; "bogus" |].(Random.State.int st 4)) ]
      else []
    in
    generated := { R.meth = meths.(Random.State.int st 6); segments = segs; query = q } :: !generated
  done;
  check "LAW ORACLE-FINAL: the two encodings agree on 4000 generated targets"
    (List.for_all agree !generated);

  (* Non-vacuity: a law that never sees a match proves nothing. *)
  let hits = List.length (List.filter (fun d -> R.of_target d <> None) !generated) in
  check "GUARD NON-VACUOUS: the generated traffic actually reaches routes"
    (hits > 50);

  (* LAW INJECTIVITY — no two routes share a (method, path). Two routes at one
     address means one of them is unreachable, and which one depends on
     declaration order. *)
  let addrs = List.map (fun r -> (R.meth_to_string (R.meth_of r), R.to_path r)) R.all in
  check "LAW INJECTIVITY: distinct routes have distinct addresses"
    (List.length (List.sort_uniq compare addrs) = List.length addrs);

  (* LAW NO-SHADOWING — a concrete path built from one route never parses to a
     different one, across many identifier shapes. This is the dynamic
     counterpart of injectivity: it tests the matcher, not the renderer. *)
  (* The escape-shaped identifiers are the discriminating ones, and they are
     here because a mutant that treated '%' as safe-to-pass-through SURVIVED
     an earlier version of this list: `a%b` is a MALFORMED escape, which the
     lenient decoder returns unchanged, so it round-trips either way. A
     WELL-FORMED escape does not — `a%41b` would come back as `aAb`, and
     `%2F` would come back as a segment separator. A law is only as strong as
     its most discriminating input. *)
  let sample_ids = List.filter_map R.Id.of_string
      [ "a"; "abc"; "7"; "duplicate"; "views"; "notes"; "share"; "export"; "analytics";
        "with space"; "a%b"; "a%41b"; "%2F"; "100%25"; "%%"; "a?b"; "a#b"; "üñî"; "-"; "~";
        String.make 40 'z' ] in
  let reshape r i =
    match r with
    | R.Project _ -> Some (R.Project i)
    | R.Project_update _ -> Some (R.Project_update i)
    | R.Project_delete _ -> Some (R.Project_delete i)
    | R.Project_duplicate _ -> Some (R.Project_duplicate i)
    | R.Project_views _ -> Some (R.Project_views i)
    | R.Project_view_create _ -> Some (R.Project_view_create i)
    | R.Project_view_delete (_, v) -> Some (R.Project_view_delete (i, v))
    | R.Project_notes _ -> Some (R.Project_notes i)
    | R.Project_note_create _ -> Some (R.Project_note_create i)
    | R.Project_share _ -> Some (R.Project_share i)
    | R.Project_share_set _ -> Some (R.Project_share_set i)
    | R.Graph _ -> Some (R.Graph i)
    | R.Graph_analytics _ -> Some (R.Graph_analytics i)
    | R.Graph_export (_, f) -> Some (R.Graph_export (i, f))
    | R.Command _ -> Some (R.Command i)
    | _ -> None
  in
  let shaped =
    List.concat_map (fun r -> List.filter_map (reshape r) sample_ids) R.all
  in
  check "LAW NO-SHADOWING: a route's own URL parses back to that route, over 21 identifier shapes"
    (shaped <> []
    && List.for_all
         (fun r ->
           match R.parse ~meth:(R.meth_to_string (R.meth_of r)) ~path:(R.to_path r) with
           | Some r' -> R.constructor_index r' = R.constructor_index r
           | None -> false)
         shaped);

  (* LAW ENCODING — the captured value survives the URL unchanged. The
     identifiers above include the characters that break a naive renderer:
     the query separator, the fragment separator, the escape character
     itself, whitespace and non-ASCII. *)
  check "LAW ENCODING: the captured identifier survives rendering and parsing"
    (List.for_all
       (fun i ->
         match R.parse ~meth:"GET" ~path:(R.to_path (R.Project i)) with
         | Some (R.Project i') -> R.Id.equal i i'
         | _ -> false)
       sample_ids);

  (* LAW CANONICITY — a rendered path is already in normal form, so no
     downstream normaliser can change its meaning. *)
  check "LAW CANONICITY: rendered paths are normal — rooted, no empty or dot segment"
    (List.for_all
       (fun r ->
         let p = R.to_path r in
         let path = match String.index_opt p '?' with Some i -> String.sub p 0 i | None -> p in
         String.length path > 0
         && path.[0] = '/'
         && (not (contains path "//"))
         && (path = "/" || path.[String.length path - 1] <> '/')
         && List.for_all
              (fun s -> s <> "." && s <> "..")
              (String.split_on_char '/' path |> List.filter (fun s -> s <> "")))
       R.all);

  (* LAW TOTALITY — the parser reads bytes from a peer we do not control. A
     decoder that raises turns a hostile client into a harness crash. *)
  let alphabet = "/%.:?&=#abc019 \x00\xff+" in
  let raised = ref 0 in
  for _ = 1 to 5000 do
    let len = Random.State.int st 48 in
    let b = Buffer.create len in
    for _ = 1 to len do
      Buffer.add_char b alphabet.[Random.State.int st (String.length alphabet)]
    done;
    let m = [| "GET"; "POST"; "BREW"; ""; "get" |].(Random.State.int st 5) in
    match R.parse ~meth:m ~path:(Buffer.contents b) with
    | _ -> ()
    | exception _ -> incr raised
  done;
  check "LAW TOTALITY: the parser never raises on 5000 adversarial requests" (!raised = 0);

  (* LAW QUERY-TYPED — a query value outside the closed variant is REJECTED.
     A silent default is how `?format=grapml` quietly returns JSON and the
     caller believes it received GraphML. *)
  let export_path f =
    "/api/v1/graphs/g/export?format=" ^ f
  in
  check "LAW QUERY-TYPED: every admitted format parses to its variant"
    (List.for_all
       (fun f ->
         match R.parse ~meth:"GET" ~path:(export_path (R.export_format_to_string f)) with
         | Some (R.Graph_export (_, f')) -> f' = f
         | _ -> false)
       R.export_formats);
  check "LAW QUERY-TYPED: an unrecognised format is rejected, not defaulted"
    (R.parse ~meth:"GET" ~path:(export_path "grapml") = None
    && R.parse ~meth:"GET" ~path:(export_path "") = None);
  check "LAW QUERY-DEFAULT: an absent format is the declared default"
    (match R.parse ~meth:"GET" ~path:"/api/v1/graphs/g/export" with
     | Some (R.Graph_export (_, R.Json)) -> true
     | _ -> false);

  (* LAW PATTERN-AGREEMENT — the router pattern and the rendered path agree on
     shape. This is what makes it safe to generate the router from the route
     value: same arity, and the literal segments are literally equal. *)
  check "LAW PATTERN-AGREEMENT: pattern and path share arity and literal segments"
    (List.for_all
       (fun r ->
         let segs p =
           let p = match String.index_opt p '?' with Some i -> String.sub p 0 i | None -> p in
           String.split_on_char '/' p |> List.filter (fun s -> s <> "")
         in
         let ps = segs (R.pattern r) and rs = segs (R.to_path r) in
         List.length ps = List.length rs
         && List.for_all2
              (fun a b -> (String.length a > 0 && a.[0] = ':') || String.equal a b)
              ps rs)
       R.all);

  (* ================= the GENERATED router =================================
     The server installs `dispatch_table` rather than a hand-written list, so
     "served" and "named" are the same set by construction. These laws pin the
     formal spec written in route_algebra.ml. *)

  (* LAW DISPATCH-COMPLETE — one entry per constructor, and no two entries
     share an address. Both halves matter: fewer entries means a route nobody
     can reach, duplicates mean an entry that can never be selected. *)
  check "LAW DISPATCH-COMPLETE: exactly one table entry per route, all distinct"
    (List.length R.dispatch_table = R.constructor_count
    && List.length (List.sort_uniq compare R.dispatch_table) = R.constructor_count);

  (* LAW DISPATCH-UNAMBIGUOUS — the property that makes installation ORDER
     irrelevant, and therefore the property that makes generation safe. A
     hand-written Dream router is first-match-wins, so `/api/v1/projects/:id`
     placed before `/api/v1/projects/new` silently swallows it. Here no
     concrete target can match two entries at all. *)
  let one_at_most d = List.length (R.matching_entries d) <= 1 in
  check "LAW DISPATCH-UNAMBIGUOUS: no witness target matches two entries"
    (List.for_all (fun r -> one_at_most (R.denote r)) R.all);
  check "LAW DISPATCH-UNAMBIGUOUS: no generated target matches two entries (4000)"
    (List.for_all one_at_most !generated);

  (* LAW DISPATCH-FAITHFUL — the entry that matches is the one belonging to
     the route `classify` returns. Without this, the table could be complete
     and unambiguous and still send a request to the wrong handler. *)
  check "LAW DISPATCH-FAITHFUL: the matching entry is the classified route's own"
    (List.for_all
       (fun d ->
         match R.classify_target d with
         | R.Matched r -> R.matching_entries d = [ (R.meth_of r, R.pattern r) ]
         | R.Bad_input -> List.length (R.matching_entries d) = 1
         | R.No_route -> R.matching_entries d = [])
       (List.map R.denote R.all @ !generated));

  (* CHAOS — installation order is scrambled and every routing decision must
     be identical. This is the operational form of UNAMBIGUOUS: a server that
     installs the table in any order behaves the same. Seeded, so a failure is
     reproducible. *)
  let shuffle seed l =
    let st = Random.State.make [| seed |] in
    List.map (fun x -> (Random.State.bits st, x)) l
    |> List.sort compare |> List.map snd
  in
  check "CHAOS DISPATCH-ORDER-INVARIANT: 20 scrambled installations route identically"
    (List.for_all
       (fun seed ->
         let scrambled = shuffle seed R.dispatch_table in
         List.for_all
           (fun d ->
             let pick tbl = List.find_opt (fun e -> R.pattern_matches e d) tbl in
             pick scrambled = pick R.dispatch_table)
           (List.map R.denote R.all @ !generated))
       (List.init 20 (fun i -> i + 1)));

  (* FUZZ — raw byte targets, not structured ones, through the same decision
     path a server takes. The property is that nothing raises and nothing is
     ambiguous, whatever arrives. *)
  let fuzz_raised = ref 0 and fuzz_ambiguous = ref 0 and fuzz_matched = ref 0 in
  let falphabet = "/abc019:.%?&=-_ \x00\xffapiv1projectsgraphs" in
  for _ = 1 to 5000 do
    let len = Random.State.int st 40 in
    let b = Buffer.create len in
    for _ = 1 to len do
      Buffer.add_char b falphabet.[Random.State.int st (String.length falphabet)]
    done;
    let m = [| "GET"; "POST"; "PUT"; "PATCH"; "DELETE"; "HEAD"; "BREW" |].(Random.State.int st 7) in
    match R.meth_of_string m with
    | None -> ()
    | Some meth -> (
        match R.target_of_request ~meth ~path:(Buffer.contents b) with
        | d ->
            let ms = R.matching_entries d in
            if List.length ms > 1 then incr fuzz_ambiguous;
            if ms <> [] then incr fuzz_matched
        | exception _ -> incr fuzz_raised)
  done;
  check "FUZZ DISPATCH: 5000 raw targets — none raise, none are ambiguous"
    (!fuzz_raised = 0 && !fuzz_ambiguous = 0);

  (* BDD — the scenarios a reviewer actually wants to read, in the vocabulary
     of the system rather than of the implementation. *)
  let target meth path =
    R.target_of_request ~meth:(match R.meth_of_string meth with Some m -> m | None -> R.GET) ~path
  in
  check "GIVEN a project id WHEN DELETE /api/v1/projects/:id THEN it routes to Project_delete"
    (match R.classify_target (target "DELETE" "/api/v1/projects/p1") with
     | R.Matched (R.Project_delete _) -> true
     | _ -> false);
  check "GIVEN the same path WHEN the verb differs THEN a different route is selected"
    (let g = R.classify_target (target "GET" "/api/v1/projects/p1") in
     let p = R.classify_target (target "PATCH" "/api/v1/projects/p1") in
     match (g, p) with
     | R.Matched (R.Project _), R.Matched (R.Project_update _) -> true
     | _ -> false);
  check "GIVEN an unserved path WHEN requested THEN no entry matches and it is No_route"
    (R.matching_entries (target "GET" "/api/v1/nonesuch") = []
    && R.classify_target (target "GET" "/api/v1/nonesuch") = R.No_route);
  check "GIVEN a served path WHEN the query is rejected THEN an entry still matches (a 400, not a 404)"
    (let d = target "GET" "/api/v1/graphs/g/export?format=grapml" in
     List.length (R.matching_entries d) = 1 && R.classify_target d = R.Bad_input);
  (* ---- The router is GENERATED, so coverage is STRUCTURAL ----------------
     Two laws used to live here, comparing the patterns the server serves
     against the routes the algebra names and requiring both directions to
     agree. That comparison is now the WRONG QUESTION: the server installs
     `dispatch_table`, so the two sets are the same object and the comparison
     could only ever be vacuous.

     What still needs protecting is that nobody adds a route the OLD way. A
     hand-written `Dream.get "..."` beside the generated table is exactly the
     drift the comparison used to catch, so the law scans for one.
     Completeness is covered by DISPATCH-COMPLETE; handler totality is not a
     law at all, because a missing handler is a compile error. *)
  let app = Filename.concat root "harness/dream_backend_app.ml" in
  if Sys.file_exists app then begin
    let src_app = read_file app in
    let literals = served_patterns src_app in
    List.iter
      (fun (m, p) -> Printf.printf "        hand-written route literal: %s %s\n" m p)
      literals;
    Printf.printf "        router: GENERATED from %d table entries; %d hand-written literal(s)\n"
      (List.length R.dispatch_table) (List.length literals);
    (* Non-vacuity: zero literals is also true of a file that stopped serving
       anything at all. The app must actually install the generated router. *)
    check "GUARD NON-VACUOUS: the app installs the generated router"
      (contains src_app ("Dream_web." ^ "router"));
    check "LAW ROUTER-GENERATED: no route is installed by hand beside the table"
      (literals = [])
  end;


  (* ---- The residual, measured rather than asserted away ------------------
     The Bonsai client still builds URLs by concatenation. That is the defect
     class this algebra exists to remove, and it is NOT removed until those
     call sites go through a route value. The ceiling is a ratchet: it may
     fall, never rise. Reporting the number is the honest alternative to
     either claiming the problem is solved or leaving it invisible. *)
  let client = Filename.concat root "harness/ui_web/main.ml" in
  if Sys.file_exists client then begin
    let src = read_file client in
    let needle = "\"/api/" in
    let n = String.length src and nl = String.length needle in
    let count = ref 0 in
    for i = 0 to n - nl do
      if String.sub src i nl = needle then incr count
    done;
    (* ZERO. Every client URL is now derived from a route value, so this is a
       guarantee rather than a ratchet: reintroducing a hand-written API URL
       fails the gate on the commit that does it. *)
    let ceiling = 0 in
    (* Non-vacuity: zero literals would also be true of an empty or renamed
       file. The client must actually be USING the algebra. *)
    let derived =
      let needle = "route_" ^ "with_id" in
      let n = String.length src and nl = String.length needle in
      let c = ref 0 in
      for i = 0 to n - nl do
        if String.sub src i nl = needle then incr c
      done;
      !c
    in
    Printf.printf "        client URL literals: %d (ceiling %d); routes derived at %d call site(s)\n"
      !count ceiling derived;
    check "GUARD NON-VACUOUS: the client actually derives URLs from route values"
      (derived >= 5 && contains src "Route_algebra");
    check "LAW CLIENT-LINK-ZERO: the client contains no hand-written API URL"
      (!count <= ceiling)
  end;

  Printf.printf "\nroute-algebra: %d law(s), %d failure(s)\n" !laws !failures;
  if !failures > 0 then failwith "route-algebra laws FAILED";
  !laws
