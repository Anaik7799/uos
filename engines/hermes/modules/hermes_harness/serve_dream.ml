(* Serve the built site with Dream. R15 unchanged: resolve the Tailscale
   FQDN, refuse without it unless the degradation is disclosed. *)

let () =
  let root = ref "." and port = ref 8790 and allow_no_tailscale = ref false in
  Array.iteri
    (fun i argument ->
      if argument = "--port" && i + 1 < Array.length Sys.argv then
        (match int_of_string_opt Sys.argv.(i + 1) with Some p -> port := p | None -> ())
      else if argument = "--root" && i + 1 < Array.length Sys.argv then
        root := Sys.argv.(i + 1)
      else if argument = "--allow-no-tailscale" then allow_no_tailscale := true)
    Sys.argv;
  (match (Hermes_httpd.tailscale_fqdn (), !allow_no_tailscale) with
  | Some _, _ -> ()
  | None, true -> prerr_endline "R15 DISCLOSED: no tailscale FQDN; degraded mode"
  | None, false ->
      prerr_endline
        "R15: no tailscale FQDN (MagicDNS). Run 'tailscale up' or pass \
         --allow-no-tailscale to serve degraded with it disclosed.";
      exit 1);
  let site = Site_build.build ~root:!root in
  (match site.Site_build.model.Web_read_model.gaps with
  | [] -> ()
  | gaps ->
      prerr_endline "completeness gaps; refusing to serve:";
      List.iter (fun g -> prerr_endline ("  " ^ g)) gaps;
      exit 1);
  let model_json =
    Yojson.Safe.pretty_to_string (Web_read_model.to_json site.Site_build.model)
  in
  print_endline (Hermes_httpd.banner ~port:!port ^ " [dream]");
  Wiki_dream.serve ~pages:site.Site_build.pages ~model_json ~css:"" ~port:!port
