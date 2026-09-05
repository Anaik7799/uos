(* Standalone driver for the wiki rendering laws — the dev loop's view.

   The laws themselves live in `Wiki_render.Wiki_render_laws` so that this
   executable and the harness gate (`typed_html_laws`) run the SAME
   definitions. Previously they lived here, and here alone, which meant
   nothing ever ran them. *)

let () =
  print_endline "wiki-render laws";
  let results =
    Wiki_render.Wiki_render_laws.run () @ Wiki_render.Markdown_ast_laws.run ()
  in
  List.iter
    (fun (name, ok) -> Printf.printf "  %s  %s\n" (if ok then "PASS" else "FAIL") name)
    results;
  let cases = List.length results in
  let failures = List.length (List.filter (fun (_, ok) -> not ok) results) in
  Printf.printf "\nwiki-render: %d case(s), %d failure(s)\n" cases failures;
  if failures > 0 then exit 1
