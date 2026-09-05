(* wiki_find — recall, executable (R18). The c3i mandate said "search
   before starting"; this is the tool that makes it a habit instead of a
   sermon: page hits, block hits (addressable as [[Page#^id]]), and the
   hub's backlink neighbourhood, over the live corpus. Read-only. *)

let () =
  let query = String.concat " " (List.tl (Array.to_list Sys.argv)) in
  if String.trim query = "" then begin
    print_endline "usage: wiki_find <query terms>";
    exit 2
  end;
  let files =
    Hermes_wiki.read_tracked "modules/hermes_wiki/pages" @ Hermes_wiki.read_tracked "docs/hermes"
  in
  let m = Hermes_wiki.build ~read_source:Hermes_wiki.read_source_file files in
  let idx = Wiki_search.build m in
  let hits = Wiki_search.search idx query in
  let blocks = Wiki_search.block_hits idx query in
  Printf.printf "%d page hit(s) for %S\n" (List.length hits) query;
  List.iteri
    (fun i (slug, score) -> if i < 15 then Printf.printf "  %3d  %s\n" score slug)
    hits;
  if blocks <> [] then begin
    print_endline "block hits (citable as [[Page#^id]]):";
    List.iter (fun (slug, id) -> Printf.printf "  [[%s#%s]]\n" slug id) blocks
  end;
  if hits = [] then print_endline "  (nothing — write the note after the work: R18)"
