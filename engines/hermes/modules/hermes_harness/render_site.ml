(* Write the site to disk. Fail-closed on the completeness laws the site
   itself reports: a hub that links a page that cannot exist is worse than
   no hub. *)

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "." in
  let out_dir =
    if Array.length Sys.argv > 2 then Sys.argv.(2) else Filename.concat root "state/site"
  in
  let site = Site_build.build ~root in
  (match site.Site_build.model.Web_read_model.gaps with
  | [] -> ()
  | gaps ->
      prerr_endline "completeness gaps; refusing to render the site:";
      List.iter (fun g -> prerr_endline ("  " ^ g)) gaps;
      exit 1);
  (match Hermes_wiki.defects site.Site_build.wiki with
  | [] -> ()
  | anomalies ->
      prerr_endline "wiki anomalies; refusing to render the site:";
      List.iter (fun a -> prerr_endline ("  " ^ a)) anomalies;
      exit 1);
  (* HW.3.4.3 — a fragment whose document resolves but whose anchor does
     not. Reported, not refused: unlike a dead link it does not produce a
     page that cannot exist, and a gate that refuses on the day it is
     introduced blocks every unrelated change until the backlog is clear.
     The suite pins the behaviour; this surfaces the corpus's own debt. *)
  (match Hermes_wiki.broken_anchors site.Site_build.wiki with
  | [] -> ()
  | broken ->
      Printf.eprintf "broken anchors (%d):\n" (List.length broken);
      List.iter (fun a -> prerr_endline ("  " ^ a)) broken);
  (* PKM schema conformance (spec §3) — reported, not refused, and COUNTED
     rather than listed: 233 pre-schema documents would otherwise flood
     every render. The ratchet (HW.10.2.1) is what will drive this down. *)
  (match Hermes_wiki.schema_gaps site.Site_build.wiki with
  | [] -> ()
  | gaps -> Printf.eprintf "schema gaps: %d field(s) missing across the corpus\n" (List.length gaps));
  let rec mkdir_p dir =
    if not (Sys.file_exists dir) then begin
      mkdir_p (Filename.dirname dir);
      try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
    end
  in
  mkdir_p out_dir;
  List.iter
    (fun (name, html) ->
      let channel = open_out_bin (Filename.concat out_dir name) in
      output_string channel html;
      close_out channel)
    site.Site_build.pages;
  let channel = open_out_bin (Filename.concat out_dir "model.json") in
  output_string channel
    (Yojson.Safe.pretty_to_string (Web_read_model.to_json site.Site_build.model) ^ "\n");
  close_out channel;
  Printf.printf "wrote %d pages + model.json to %s\n" (List.length site.Site_build.pages) out_dir
