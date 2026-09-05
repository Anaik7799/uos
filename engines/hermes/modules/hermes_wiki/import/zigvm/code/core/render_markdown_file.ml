let escape_html value =
  value |> String.to_seq |> Seq.map (function
    | '&' -> "&amp;" | '<' -> "&lt;" | '>' -> "&gt;"
    | '"' -> "&quot;" | c -> String.make 1 c)
  |> List.of_seq |> String.concat ""

let () =
  if Array.length Sys.argv <> 4 then begin
    prerr_endline "usage: render_markdown_file INPUT OUTPUT TITLE";
    exit 2
  end;
  let input = Sys.argv.(1) and output = Sys.argv.(2) and title = Sys.argv.(3) in
  let markdown = In_channel.with_open_bin input In_channel.input_all in
  (* Standalone rendering has no wiki to resolve `[[targets]]` against, so an
     unresolvable target renders as the missing-link chip — which is the honest
     result, not a degraded one. *)
  let body =
    Wiki_render.Docs_wiki.render_markdown_typed ~resolve:(fun _ -> None) markdown
  in
  let html =
    Printf.sprintf
      {|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>%s</title><style>body{font:16px/1.55 system-ui,sans-serif;max-width:1100px;margin:auto;padding:2rem;color:#17202a}pre,code{font-family:ui-monospace,monospace}pre{background:#f3f5f7;padding:1rem;overflow:auto;border-radius:6px}table{border-collapse:collapse;width:100%%}th,td{border:1px solid #ccd6e0;padding:.5rem;vertical-align:top}h1,h2,h3{color:#174a7c}blockquote{border-left:4px solid #6989a8;padding-left:1rem;color:#3d5266}a{color:#075ea8}</style></head><body>%s</body></html>|}
      (escape_html title) body
  in
  Out_channel.with_open_bin output (fun channel -> output_string channel html)
