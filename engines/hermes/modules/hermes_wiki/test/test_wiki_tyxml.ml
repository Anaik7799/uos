(* TyXML typed generation: the laws that string building could not give
   us. Markup cannot be malformed (it is a typed tree), escaping is by
   construction (text is a node, never spliced), and the shim renders the
   same shapes the string builder produces today. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed; print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let contains text needle =
  let n = String.length needle and h = String.length text in
  let rec go i = i + n <= h && (String.sub text i n = needle || go (i + 1)) in
  go 0

let () =
  check "a text node is ESCAPED by construction, never spliced" (fun () ->
      let html = Wiki_tyxml.to_string (Wiki_tyxml.text_node "<script>alert(1)</script>&\"") in
      contains html "&lt;script&gt;"
      && (not (contains html "<script>"))
      && contains html "&amp;");
  check "a kpi card carries its value and label" (fun () ->
      let html = Wiki_tyxml.to_string (Wiki_tyxml.kpi_card ~value:"33" ~label:"components") in
      contains html "33" && contains html "components" && contains html "<div");
  check "a kpi band renders every pair" (fun () ->
      let html =
        Wiki_tyxml.to_string
          (Wiki_tyxml.kpi_band [ ("9", "verified"); ("0", "gaps"); ("48", "notes") ])
      in
      contains html "verified" && contains html "gaps" && contains html "48"
      && contains html "class=\"kpi\"");
  check "a card is a link with title and subtitle" (fun () ->
      let html =
        Wiki_tyxml.to_string
          (Wiki_tyxml.card ~href:"zk.html" ~title:"ZK graph" ~subtitle:"48 notes")
      in
      contains html "href=\"zk.html\"" && contains html "ZK graph" && contains html "48 notes");
  check "a card's title is escaped too (no injection through data)" (fun () ->
      let html =
        Wiki_tyxml.to_string
          (Wiki_tyxml.card ~href:"x.html" ~title:"<b>bold</b>" ~subtitle:"s")
      in
      contains html "&lt;b&gt;" && not (contains html "<b>bold</b>"));
  check "a table renders headers and every row cell" (fun () ->
      let html =
        Wiki_tyxml.to_string
          (Wiki_tyxml.table ~headers:[ "id"; "status" ]
             ~rows:[ [ "F-CO-2"; "open" ]; [ "W1"; "closed" ] ])
      in
      contains html "<th>" && contains html "id" && contains html "F-CO-2"
      && contains html "closed");
  check "a grid wraps its children" (fun () ->
      let html =
        Wiki_tyxml.to_string
          (Wiki_tyxml.grid [ Wiki_tyxml.text_node "a"; Wiki_tyxml.text_node "b" ])
      in
      contains html "class=\"grid\"" && contains html "a" && contains html "b");
  check "a section emits a heading followed by its body" (fun () ->
      let html =
        String.concat ""
          (List.map Wiki_tyxml.to_string
             (Wiki_tyxml.section "Surfaces" [ Wiki_tyxml.text_node "body" ]))
      in
      contains html "<h2>" && contains html "Surfaces" && contains html "body");
  check "the shell is a complete document with nav and footer" (fun () ->
      let html = Wiki_tyxml.page_to_string ~title:"index" [ Wiki_tyxml.text_node "x" ] in
      contains html "<!DOCTYPE html>" && contains html "<title>"
      && contains html "index.html" && contains html "</html>");
  check "the shell title is escaped" (fun () ->
      let html = Wiki_tyxml.page_to_string ~title:"a<b>c" [] in
      contains html "a&lt;b&gt;c" && not (contains html "a<b>c"));
  check "rendering is deterministic" (fun () ->
      Wiki_tyxml.page_to_string ~title:"t" [ Wiki_tyxml.text_node "x" ]
      = Wiki_tyxml.page_to_string ~title:"t" [ Wiki_tyxml.text_node "x" ]);
  check "every emitted document is well-formed (tags balanced)" (fun () ->
      (* A typed tree cannot emit an unbalanced tag; this counts opens
         against closes on a realistic page as the observable proof. *)
      let html =
        Wiki_tyxml.page_to_string ~title:"t"
          [ Wiki_tyxml.kpi_band [ ("1", "a") ];
            Wiki_tyxml.grid [ Wiki_tyxml.card ~href:"h" ~title:"t" ~subtitle:"s" ];
            Wiki_tyxml.table ~headers:[ "h" ] ~rows:[ [ "r" ] ] ]
      in
      let count needle =
        let n = String.length needle and h = String.length html in
        let rec go i acc =
          if i + n > h then acc
          else if String.sub html i n = needle then go (i + 1) (acc + 1)
          else go (i + 1) acc
        in
        go 0 0
      in
      count "<div" = count "</div>" && count "<table" = count "</table>"
      && count "<tr" = count "</tr>")

let () =
  Printf.printf "wiki_tyxml: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_tyxml" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
