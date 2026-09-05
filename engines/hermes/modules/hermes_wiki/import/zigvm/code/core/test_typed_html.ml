(* Laws for the typed-markup layer.

   Two of these are worth stating plainly, because they are the reason the
   module exists rather than a wrapper someone thought was tidy:

     LINK-FROM-ROUTE  the href a page carries is exactly the route's path, for
                      every route — so link rot cannot be introduced by a
                      renderer that "helpfully" adjusts a URL
     ESCAPING         hostile text and hostile identifiers cannot escape their
                      context, in element content and in attribute values

   The type-level guarantees (a `<b>` cannot appear inside a `<title>`, a
   `<td>` cannot appear outside a row) are NOT tested here, and deliberately
   so: they are enforced by the compiler, and a test that asserts a compile
   error is weaker than the compile error. *)

module H = Tyxml.Html
module R = Route_algebra
module T = Typed_html

let failures = ref 0
let laws = ref 0

let check name ok =
  incr laws;
  if ok then Printf.printf "  PASS  %s\n" name
  else begin
    incr failures;
    Printf.printf "  FAIL  %s\n" name
  end

let contains hay needle =
  let nl = String.length needle and hl = String.length hay in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl > 0 && go 0

let () =
  print_endline "typed-html laws";

  (* LAW LINK-FROM-ROUTE — the rendered href is the route's path, for every
     route in the algebra. The witness is a page built from `R.all`, so a
     route that cannot be linked makes this law fail to BUILD, which is the
     strongest failure mode available. *)
  let index = T.render (T.route_index ()) in
  check "LAW LINK-FROM-ROUTE: every route's path appears as a rendered href"
    (List.for_all
       (fun r ->
         let p = R.to_path r in
         (* the query separator is escaped as an entity in attribute context,
            which is correct HTML and must be accounted for rather than
            worked around *)
         let expect =
           String.concat "&amp;" (String.split_on_char '&' p)
         in
         contains index ("href=\"" ^ expect ^ "\""))
       R.all);

  (* Non-vacuity: the page must actually contain every route, or the law above
     is quantifying over an empty rendering. *)
  check "GUARD NON-VACUOUS: the index renders one row per route"
    (let n = ref 0 in
     let needle = "<tr>" in
     let nl = String.length needle in
     for i = 0 to String.length index - nl do
       if String.sub index i nl = needle then incr n
     done;
     (* one header row plus one per route *)
     !n >= List.length R.all);

  (* LAW ESCAPING-CONTENT — text is data, never markup. *)
  let evil = "<script>alert('x')</script> & \"quotes\" < >" in
  let rendered = T.render_elt (H.p [ H.txt evil ]) in
  check "LAW ESCAPING-CONTENT: hostile text cannot open a tag"
    ((not (contains rendered "<script>")) && contains rendered "&lt;script&gt;");

  (* LAW ESCAPING-ATTRIBUTE — a captured identifier reaches the href through
     percent-encoding and HTML attribute escaping, and neither is allowed to
     let it break out. The identifiers here are the ones that break a naive
     renderer: the attribute delimiter, a tag opener, an entity opener. *)
  let hostile_ids =
    List.filter_map R.Id.of_string
      [ "a\"onmouseover=alert(1)"; "<img src=x>"; "&amp;"; "a'b"; "a b"; "%3Cscript%3E" ]
  in
  (* The property is BREAKOUT, not the absence of a scary substring: after
     percent-encoding, "onmouseover" survives as inert path text, and
     asserting it is gone would test the wrong thing. What must hold is that
     the attribute value carries no character able to terminate the attribute
     or open a tag — and that the identifier still round-trips, so safety was
     bought by encoding rather than by silently dropping input. *)
  let href_value html =
    let key = "href=\"" in
    let kl = String.length key and n = String.length html in
    let rec find i = if i + kl > n then None
      else if String.sub html i kl = key then Some (i + kl)
      else find (i + 1)
    in
    match find 0 with
    | None -> None
    | Some s ->
        let j = ref s in
        while !j < n && html.[!j] <> '"' do incr j done;
        Some (String.sub html s (!j - s))
  in
  check "LAW ESCAPING-ATTRIBUTE: a hostile identifier cannot break out of href"
    (hostile_ids <> []
    && List.for_all
         (fun i ->
           let html = T.render_elt (T.link (R.Project i) "x") in
           match href_value html with
           | None -> false
           | Some v ->
               (* no delimiter, no tag opener, and still the right route *)
               (not (String.exists (fun c -> c = '"' || c = '<' || c = '>' || c = '\'') v))
               && v = R.to_path (R.Project i)
               && (match R.parse ~meth:"GET" ~path:v with
                   | Some (R.Project i') -> R.Id.equal i i'
                   | _ -> false))
         hostile_ids);

  (* LAW SELF-CONTAINED — no page may reference a remote asset. The property
     is about REFERENCES: TyXML emits the XHTML namespace as an `xmlns`
     attribute, which is an identifier and not something a browser fetches,
     so the law reads href/src values rather than scanning for a scheme. *)
  check "LAW SELF-CONTAINED: no href or src resolves off-host"
    (let remote v =
       let pre p = String.length v >= String.length p && String.sub v 0 (String.length p) = p in
       pre "http://" || pre "https://" || pre "//"
     in
     let scan key =
       let kl = String.length key and n = String.length index in
       let bad = ref false in
       for i = 0 to n - kl do
         if String.sub index i kl = key then begin
           let s = i + kl in
           let j = ref s in
           while !j < n && index.[!j] <> '"' do incr j done;
           if remote (String.sub index s (!j - s)) then bad := true
         end
       done;
       not !bad
     in
     scan "href=\"" && scan "src=\"");

  (* LAW DOCTYPE — a rendered document declares standards mode. Quirks mode
     silently changes layout and is exactly the class of defect a generated
     page should not be able to have. *)
  check "LAW DOCTYPE: a rendered document is in standards mode"
    (String.length index > 15 && String.sub index 0 15 = "<!DOCTYPE html>");

  (* LAW REPORT-ONLY — the markup layer may not carry an effectful or
     gate-minting token. Tokens are concatenation-split so this scanner does
     not itself trip the honesty guards that hunt the same patterns. *)
  let src =
    let ic = open_in_bin "harness/typed_html.ml" in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic;
    s
  in
  check "LAW REPORT-ONLY: the markup module carries no effect or verdict token"
    (List.for_all
       (fun t -> not (contains src t))
       [ "open_" ^ "out"; "Sys." ^ "command"; "Unix."; "Sqlite" ^ "3";
         "record_" ^ "cycle"; "fail" ^ "with" ]);

  Printf.printf "\ntyped-html: %d law(s), %d failure(s)\n" !laws !failures;
  if !failures > 0 then exit 1
