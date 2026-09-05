(* Serve the site read-only. The site is BUILT IN MEMORY at startup, so
   the server never reads the filesystem per request and always reflects
   the live registries at launch time. *)

let () =
  let root = ref "." and port = ref 8790 and allow_no_tailscale = ref false in
  Array.iteri
    (fun i argument ->
      if argument = "--port" && i + 1 < Array.length Sys.argv then
        match int_of_string_opt Sys.argv.(i + 1) with Some p -> port := p | None -> ()
      else if argument = "--root" && i + 1 < Array.length Sys.argv then
        root := Sys.argv.(i + 1)
      else if argument = "--allow-no-tailscale" then allow_no_tailscale := true)
    Sys.argv;
  (* R15, fail-closed: the surface must be reachable over Tailscale BY
     FQDN — an address can change when a node re-registers, the MagicDNS
     name does not. A missing fabric is Environment origin and blocks
     credit: it proves nothing about the candidate (R5), so it can never
     touch parity. *)
  (match (Hermes_httpd.tailscale_fqdn (), !allow_no_tailscale) with
  | Some _, _ -> ()
  | None, true ->
      prerr_endline
        "R15 DISCLOSED: no tailscale FQDN; serving in degraded mode"
  | None, false ->
      prerr_endline
        (Fractal_diagnostic.render
           { Fractal_diagnostic.hazard = "HZ-NET-01";
             level = Fractal_diagnostic.LX_control;
             origin = Fractal_diagnostic.Environment;
             impact = Fractal_diagnostic.Blocks_credit;
             node = "hermes_httpd";
             subject = "tailscale";
             message = "no tailscale FQDN (MagicDNS name) on this host";
             cause =
               "R15 requires the web surface to be reachable over tailscale by \
                FQDN; the fabric is absent, MagicDNS is off, or the node is \
                not logged in";
             fix =
               "run: tailscale up (and enable MagicDNS), or pass \
                --allow-no-tailscale to serve degraded with it disclosed" });
      exit 1);
  let site = Site_build.build ~root:!root in
  (match site.Site_build.model.Web_read_model.gaps with
  | [] -> ()
  | gaps ->
      prerr_endline "completeness gaps; refusing to serve:";
      List.iter (fun g -> prerr_endline ("  " ^ g)) gaps;
      exit 1);
  Hermes_httpd.serve ~pages:site.Site_build.pages ~port:!port
