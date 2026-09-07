(* Unified Operational System (UOS) - Hermes Mirage CLI Runner Executable *)
(* Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001 *)

let print_json json =
  Yojson.Safe.pretty_to_channel stdout json;
  print_newline ()

let run_catalog () =
  let json = Mirage_migration_catalog.catalog_to_json () in
  print_json json

let run_dns domain =
  let state = Mirage_dns_resolver.create_resolver () in
  match Mirage_dns_resolver.resolve_query state domain Mirage_dns_resolver.A with
  | Ok resp ->
      print_json (Mirage_dns_resolver.response_to_json resp)
  | Error `Blocked_domain ->
      let json = `Assoc [("error", `String "BLOCKED_DOMAIN"); ("domain", `String domain)] in
      print_json json;
      exit 1
  | Error `NXDOMAIN ->
      let json = `Assoc [("error", `String "NXDOMAIN"); ("domain", `String domain)] in
      print_json json;
      exit 2
  | Error _ ->
      let json = `Assoc [("error", `String "RESOLUTION_ERROR"); ("domain", `String domain)] in
      print_json json;
      exit 3

let run_ingress sni path =
  let config = Mirage_tls_ingress.default_ingress_config () in
  let req = {
    Mirage_tls_ingress.method_name = "GET";
    path;
    sni_hostname = sni;
    alpn_negotiated = Mirage_tls_ingress.HTTP_1_1;
    client_ip = "100.87.7.78";
    headers = [("Host", sni); ("User-Agent", "UOS-Mirage/1.0"); ("Connection", "keep-alive")];
    body_length = 0;
  } in
  match Mirage_tls_ingress.evaluate_request config req with
  | Mirage_tls_ingress.Forward_to_upstream { target_host; target_port; sanitized_headers } ->
      let headers_json = `List (List.map (fun (k, v) -> `Assoc [("name", `String k); ("value", `String v)]) sanitized_headers) in
      let json = `Assoc [
        ("decision", `String "FORWARD");
        ("target_host", `String target_host);
        ("target_port", `Int target_port);
        ("sanitized_headers", headers_json);
      ] in
      print_json json
  | Mirage_tls_ingress.Terminate_with_error { status_code; message } ->
      let json = `Assoc [
        ("decision", `String "TERMINATE");
        ("status_code", `Int status_code);
        ("message", `String message);
      ] in
      print_json json;
      exit 3

let run_tender id =
  let tender = Mirage_solo5_tender.default_tender_config id in
  let manifest_str = Mirage_solo5_tender.generate_manifest_json tender in
  print_endline manifest_str

let run_selftest () =
  Printf.printf "=== HERMES MIRAGE RUNNER SELF-TEST ===\n";
  (* 1. Migration catalog *)
  let candidates = Mirage_migration_catalog.all_candidates () in
  let count = List.length candidates in
  assert (count = 7);
  let ram_sav = Mirage_migration_catalog.total_ram_savings_mb () in
  assert (ram_sav = 1092);
  Printf.printf "  [PASS] Migration Catalog: %d candidates, %d MB RAM savings\n" count ram_sav;

  (* 2. DNS resolver *)
  let dns_state = Mirage_dns_resolver.create_resolver () in
  (match Mirage_dns_resolver.resolve_query dns_state "nas-1.tail55d152.ts.net" Mirage_dns_resolver.A with
   | Ok r ->
       assert (r.authoritative);
       assert ((List.hd r.answers).rdata = "100.87.7.78");
       Printf.printf "  [PASS] Pure OCaml DNS Resolver: %s -> %s (authoritative=%b, %dus)\n"
         r.query_domain (List.hd r.answers).rdata r.authoritative r.resolver_latency_us
   | Error _ -> failwith "DNS resolution failed for nas-1");

  (* 3. Ingress evaluation *)
  let ingress_cfg = Mirage_tls_ingress.default_ingress_config () in
  let good_req = {
    Mirage_tls_ingress.method_name = "GET";
    path = "/api/health";
    sni_hostname = "nas-1.tail55d152.ts.net";
    alpn_negotiated = Mirage_tls_ingress.HTTP_1_1;
    client_ip = "100.87.7.78";
    headers = [("Host", "nas-1.tail55d152.ts.net"); ("Connection", "close")];
    body_length = 0;
  } in
  (match Mirage_tls_ingress.evaluate_request ingress_cfg good_req with
   | Mirage_tls_ingress.Forward_to_upstream { target_port; _ } ->
       assert (target_port = 4100);
       Printf.printf "  [PASS] TLS 1.3 Ingress Proxy: forwarded valid SNI to upstream port %d\n" target_port
   | Mirage_tls_ingress.Terminate_with_error _ -> failwith "Valid ingress request rejected");

  (* 4. Ingress NUL attack trap *)
  let attack_req = { good_req with path = "/admin\x00/exploit" } in
  (match Mirage_tls_ingress.evaluate_request ingress_cfg attack_req with
   | Mirage_tls_ingress.Terminate_with_error { status_code; _ } ->
       assert (status_code = 400);
       Printf.printf "  [PASS] TLS 1.3 Ingress Trapper: intercepted NUL byte attack (HTTP 400)\n"
   | Mirage_tls_ingress.Forward_to_upstream _ -> failwith "NUL attack leaked through");

  (* 5. Solo5 tender profile *)
  let tender = Mirage_solo5_tender.default_tender_config "MIG-02-SANDBOX" in
  assert (Mirage_solo5_tender.verify_sandbox_safety tender = Ok ());
  let est_ms = Mirage_solo5_tender.cold_start_estimate_ms tender in
  assert (est_ms < 20.0);
  Printf.printf "  [PASS] Solo5 Tender Manifest: sandbox verified (cold-start estimate: %.2fms)\n" est_ms;

  Printf.printf "=== ALL 5 MIRAGE SUBSYSTEM TESTS PASSED (100%% GREEN) ===\n"

let () =
  let args = Array.to_list Sys.argv in
  match args with
  | _ :: "catalog" :: _ -> run_catalog ()
  | _ :: "dns" :: domain :: _ -> run_dns domain
  | _ :: "ingress" :: sni :: path :: _ -> run_ingress sni path
  | _ :: "tender" :: id :: _ -> run_tender id
  | _ :: "selftest" :: _ -> run_selftest ()
  | _ ->
      Printf.eprintf "Usage: hermes_mirage_runner <command> [args...]\n";
      Printf.eprintf "Commands:\n";
      Printf.eprintf "  catalog                - Dump 7 migration candidate subsystems in JSON\n";
      Printf.eprintf "  dns <domain>           - Pure OCaml DNS lookup with sub-microsecond latency\n";
      Printf.eprintf "  ingress <sni> <path>   - Evaluate TLS 1.3 ingress routing and security policies\n";
      Printf.eprintf "  tender <id>            - Dump Solo5 tender sandbox manifest\n";
      Printf.eprintf "  selftest               - Run internal battery of all Mirage components\n";
      exit 1
