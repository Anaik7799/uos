(* The server's behavior is a pure function of (pages, method, path) —
   tested without a socket — plus one LIVE loopback leg proving the real
   server answers. Read-only laws: no method but GET/HEAD, no traversal,
   unknown paths 404 rather than touching the filesystem. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed; print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let pages = [ ("index.html", "<h1>hub</h1>"); ("wiki.html", "<h1>wiki</h1>") ]
let get path = Hermes_httpd.respond ~pages ~meth:"GET" ~path

let () =
  check "root serves the index" (fun () ->
      let r = get "/" in
      r.Hermes_httpd.status = 200 && r.Hermes_httpd.body = "<h1>hub</h1>");
  check "a known page serves with html content type" (fun () ->
      let r = get "/wiki.html" in
      r.Hermes_httpd.status = 200 && r.Hermes_httpd.content_type = "text/html; charset=utf-8");
  check "a query string is ignored" (fun () -> (get "/wiki.html?x=1").Hermes_httpd.status = 200);
  check "an unknown page is 404, not a disk read" (fun () ->
      let r = get "/etc/passwd" in
      r.Hermes_httpd.status = 404);
  check "traversal is refused" (fun () ->
      List.for_all
        (fun p -> (get p).Hermes_httpd.status = 404)
        [ "/../dune"; "/..%2fdune"; "//etc/hostname"; "/./../../secrets" ]);
  check "HEAD is allowed with an empty body" (fun () ->
      let r = Hermes_httpd.respond ~pages ~meth:"HEAD" ~path:"/index.html" in
      r.Hermes_httpd.status = 200 && r.Hermes_httpd.body = "");
  check "writes are refused (405), never attempted" (fun () ->
      List.for_all
        (fun m -> (Hermes_httpd.respond ~pages ~meth:m ~path:"/index.html").Hermes_httpd.status = 405)
        [ "POST"; "PUT"; "DELETE"; "PATCH" ]);
  check "request-line parsing accepts a normal line" (fun () ->
      Hermes_httpd.parse_request_line "GET /wiki.html HTTP/1.1" = Some ("GET", "/wiki.html"));
  check "request-line parsing refuses garbage" (fun () ->
      Hermes_httpd.parse_request_line "garbage" = None
      && Hermes_httpd.parse_request_line "" = None);
  check "responses are deterministic" (fun () -> get "/index.html" = get "/index.html")

(* --------------------------------------------------------- the live leg *)

let () =
  let port = 8791 in
  match Unix.fork () with
  | 0 ->
      (try Hermes_httpd.serve ~pages ~port with _ -> ());
      exit 0
  | child ->
      let rec attempt n =
        if n = 0 then None
        else
          try
            let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
            Unix.connect socket (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
            Some socket
          with _ -> ignore (Unix.select [] [] [] 0.05); attempt (n - 1)
      in
      (match attempt 40 with
      | None -> check "LIVE: the server accepts a loopback connection" (fun () -> false)
      | Some socket ->
          let request = "GET /wiki.html HTTP/1.1\r\nHost: localhost\r\n\r\n" in
          ignore (Unix.write_substring socket request 0 (String.length request));
          let buffer = Bytes.create 4096 in
          let n = Unix.read socket buffer 0 4096 in
          Unix.close socket;
          let text = Bytes.sub_string buffer 0 n in
          let has needle =
            let l = String.length needle and h = String.length text in
            let rec go i = i + l <= h && (String.sub text i l = needle || go (i + 1)) in
            go 0
          in
          check "LIVE: the real server answers 200 with the page body" (fun () ->
              has "200 OK" && has "<h1>wiki</h1>"));
      (try Unix.kill child Sys.sigterm with _ -> ());
      ignore (try Unix.waitpid [] child with _ -> (0, Unix.WEXITED 0))



(* ------------------------------------------------- R15: Tailscale reach *)

let () =
  check "the resolver parses a Tailscale address from interface output" (fun () ->
      Hermes_httpd.parse_tailscale
        "1: lo inet 127.0.0.1/8\n2: eth0 inet 192.168.1.5/24\n5: tailscale0 inet 100.78.98.18/32\n"
      = Some "100.78.98.18");
  check "a non-Tailscale 100.x address on a normal interface is not accepted"
    (fun () ->
      (* 100.64/10 is the CGNAT range Tailscale uses; anything outside it is
         not a Tailscale address, and neither is a private LAN address. *)
      Hermes_httpd.parse_tailscale "2: eth0 inet 100.200.0.1/24\n" = None
      && Hermes_httpd.parse_tailscale "2: eth0 inet 10.0.0.5/24\n" = None);
  check "no Tailscale interface yields None (the refusal case)" (fun () ->
      Hermes_httpd.parse_tailscale "1: lo inet 127.0.0.1/8\n" = None);
  check "the parser is total on garbage" (fun () ->
      Hermes_httpd.parse_tailscale "" = None
      && Hermes_httpd.parse_tailscale "inet inet inet" = None);
  check "the banner names the Tailscale URL when the fabric is present" (fun () ->
      let text = Hermes_httpd.banner ~port:8790 in
      let has needle =
        let l = String.length needle and h = String.length text in
        let rec go i = i + l <= h && (String.sub text i l = needle || go (i + 1)) in
        go 0
      in
      (* The canonical handle is the FQDN; the raw address is only the
         disclosed fallback when MagicDNS is absent. *)
      has "8790"
      &&
      match (Hermes_httpd.tailscale_fqdn (), Hermes_httpd.tailscale_address ()) with
      | Some fqdn, _ -> has fqdn
      | None, Some address -> has address && has "DEGRADED"
      | None, None -> has "DEGRADED");
  check "this host resolves a Tailscale address (R15 precondition, live)"
    (fun () -> Hermes_httpd.tailscale_address () <> None)


(* ------------------------------------------- R15: the FQDN is canonical *)

let () =
  check "the FQDN parser reads DNSName and strips the trailing dot" (fun () ->
      Hermes_httpd.parse_fqdn "{\"Self\":{\"DNSName\":\"vm-1.tail55d152.ts.net.\"}}"
      = Some "vm-1.tail55d152.ts.net");
  check "a non-MagicDNS value is refused (cannot masquerade as an FQDN)" (fun () ->
      Hermes_httpd.parse_fqdn "{\"DNSName\":\"localhost\"}" = None
      && Hermes_httpd.parse_fqdn "{\"DNSName\":\"host.example.com.\"}" = None);
  check "the FQDN parser is total on garbage" (fun () ->
      Hermes_httpd.parse_fqdn "" = None
      && Hermes_httpd.parse_fqdn "{\"DNSName\":" = None
      && Hermes_httpd.parse_fqdn "not json at all" = None);
  check "the banner prefers the FQDN over the raw address" (fun () ->
      let text = Hermes_httpd.banner ~port:8790 in
      let has needle =
        let l = String.length needle and h = String.length text in
        let rec go i = i + l <= h && (String.sub text i l = needle || go (i + 1)) in
        go 0
      in
      match Hermes_httpd.tailscale_fqdn () with
      | Some fqdn -> has fqdn && has "FQDN"
      | None -> has "DEGRADED");
  check "this host resolves a Tailscale FQDN (R15 precondition, live)" (fun () ->
      Hermes_httpd.tailscale_fqdn () <> None)

let () =
  Printf.printf "hermes_httpd: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_hermes_httpd" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
