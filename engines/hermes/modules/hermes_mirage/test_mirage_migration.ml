(* Unified Operational System (UOS) - MirageOS Migration & Unikernel Subsystem Tests *)
(* Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001 *)

open Mirage_migration_catalog
open Mirage_dns_resolver
open Mirage_tls_ingress

let test_migration_catalog () =
  Printf.printf "=== Running Mirage Migration Catalog Tests ===\n";
  let candidates = all_candidates () in
  assert (List.length candidates = 7);
  Printf.printf "[PASS] All 7 migration candidates verified in catalog\n";

  let ram_saved = total_ram_savings_mb () in
  assert (ram_saved >= 1000);
  Printf.printf "[PASS] Total RAM savings verified: %d MB\n" ram_saved;

  let speedup = average_speedup_ratio () in
  assert (speedup >= 90.0);
  Printf.printf "[PASS] Average cold-start speedup verified: %.1f%%\n" speedup;

  (* Verify non-negotiable forbidden targets fail closed *)
  assert (is_non_negotiable_forbidden "BEAM OTP 29 Supervisor Tree");
  assert (is_non_negotiable_forbidden "uos_sup.gleam");
  assert (is_non_negotiable_forbidden "Modular MAX max_worker.py");
  assert (is_non_negotiable_forbidden "HARD_DENIED_SYSTEM_OS_SERIAL 25503L801736");
  assert (is_non_negotiable_forbidden "Standalone Jujutsu Monorepo");
  Printf.printf "[PASS] Non-negotiable safety boundaries strictly fail closed\n";

  let c1 = find_candidate "MIG-01-INGRESS" in
  assert (Option.is_some c1);
  Printf.printf "[PASS] Subsystem candidate lookup successful\n"

let test_dns_resolver () =
  Printf.printf "=== Running Mirage Pure OCaml DNS Resolver Tests ===\n";
  let res = create_resolver () in

  (* Test static authoritative resolution *)
  (match resolve_query res "nas-1.tail55d152.ts.net" A with
   | Ok r ->
       assert (r.authoritative);
       assert (not r.cached);
       assert (List.length r.answers = 1);
       assert (String.equal (List.hd r.answers).rdata "100.87.7.78");
       Printf.printf "[PASS] Authoritative Tailscale DNS resolution: %s -> %s (latency: %dus)\n"
         r.query_domain (List.hd r.answers).rdata r.resolver_latency_us
   | Error _ -> assert false);

  (* Test cache behavior *)
  (match resolve_query res "nas-1.tail55d152.ts.net" A with
   | Ok r ->
       assert (r.authoritative);
       Printf.printf "[PASS] Static authoritative query fast-path verified\n"
   | Error _ -> assert false);

  (* Test synthetic mesh resolution & cache insertion *)
  (match resolve_query res "node-42.tail55d152.ts.net" A with
   | Ok r ->
       assert (not r.authoritative);
       assert (not r.cached);
       assert (cache_size res = 1);
       Printf.printf "[PASS] Synthetic Tailscale mesh resolution successful\n"
   | Error _ -> assert false);

  (* Test subsequent cached resolution *)
  (match resolve_query res "node-42.tail55d152.ts.net" A with
   | Ok r ->
       assert (r.cached);
       Printf.printf "[PASS] Cached DNS query verified (latency: %dus)\n" r.resolver_latency_us
   | Error _ -> assert false);

  (* Test blocked malicious domains *)
  (match resolve_query res "evil.internal.threat" A with
   | Error `Blocked_domain ->
       Printf.printf "[PASS] Malicious threat domain blocked fail-closed\n"
   | _ -> assert false);

  (match resolve_query res "attack;drop table users;" A with
   | Error `Blocked_domain ->
       Printf.printf "[PASS] SQL-injection domain pattern blocked fail-closed\n"
   | _ -> assert false)

let test_tls_ingress () =
  Printf.printf "=== Running Mirage TLS Ingress Proxy Tests ===\n";
  let cfg = default_ingress_config () in

  (* Test valid request forwarding *)
  let valid_req : ingress_request = {
    method_name = "GET";
    path = "/api/health";
    sni_hostname = "nas-1.tail55d152.ts.net";
    alpn_negotiated = H2;
    client_ip = "100.78.98.18";
    headers = [
      ("Host", "nas-1.tail55d152.ts.net");
      ("User-Agent", "C3I-Mesh-Client");
      ("Connection", "keep-alive");
      ("Upgrade", "websocket");
    ];
    body_length = 0;
  } in
  (match evaluate_request cfg valid_req with
   | Forward_to_upstream { target_host; target_port; sanitized_headers } ->
       assert (String.equal target_host "127.0.0.1");
       assert (target_port = 4100);
       (* Verify hop-by-hop headers removed *)
       assert (not (List.exists (fun (k, _) -> String.equal (String.lowercase_ascii k) "connection") sanitized_headers));
       assert (not (List.exists (fun (k, _) -> String.equal (String.lowercase_ascii k) "upgrade") sanitized_headers));
       (* Verify security headers added *)
       assert (List.exists (fun (k, v) -> String.equal k "x-forwarded-proto" && String.equal v "https") sanitized_headers);
       assert (List.exists (fun (k, v) -> String.equal k "x-mirage-unikernel" && String.equal v "Solo5-SPT") sanitized_headers);
       Printf.printf "[PASS] Valid request successfully sanitized and forwarded to upstream %s:%d\n" target_host target_port
   | Terminate_with_error _ -> assert false);

  (* Test oversized body rejection *)
  let oversized_req : ingress_request = {
    valid_req with body_length = 20_000_000; (* 20MB exceeds 10MB *)
  } in
  (match evaluate_request cfg oversized_req with
   | Terminate_with_error { status_code; message } ->
       assert (status_code = 413);
       Printf.printf "[PASS] Oversized payload rejected: HTTP %d (%s)\n" status_code message
   | Forward_to_upstream _ -> assert false);

  (* Test NUL byte URI rejection *)
  let nul_req : ingress_request = {
    valid_req with path = "/api/\x00malicious";
  } in
  (match evaluate_request cfg nul_req with
   | Terminate_with_error { status_code; message } ->
       assert (status_code = 400);
       Printf.printf "[PASS] NUL byte URI injection rejected: HTTP %d (%s)\n" status_code message
   | Forward_to_upstream _ -> assert false);

  (* Test untrusted SNI rejection *)
  let untrusted_sni_req : ingress_request = {
    valid_req with sni_hostname = "untrusted-attacker.com";
  } in
  (match evaluate_request cfg untrusted_sni_req with
   | Terminate_with_error { status_code; message } ->
       assert (status_code = 403);
       Printf.printf "[PASS] Untrusted SNI hostname rejected: HTTP %d (%s)\n" status_code message
   | Forward_to_upstream _ -> assert false)

let () =
  Printf.printf "Starting UOS MirageOS Migration Test Suite...\n";
  test_migration_catalog ();
  test_dns_resolver ();
  test_tls_ingress ();
  Printf.printf "All MirageOS Migration tests PASSED (100%% green).\n"
