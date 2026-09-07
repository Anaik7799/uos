(* Unified Operational System (UOS) - MirageOS Pure OCaml TLS Ingress Proxy *)
(* Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001 *)

type tls_version = TLS_1_3

type cipher_suite =
  | TLS_AES_256_GCM_SHA384
  | TLS_CHACHA20_POLY1305_SHA256

type alpn_protocol = H2 | HTTP_1_1

type ingress_config = {
  listen_port : int;
  upstream_host : string;
  upstream_port : int;
  tls_version : tls_version;
  ciphers : cipher_suite list;
  alpn : alpn_protocol list;
  hsts_enabled : bool;
  max_header_size_bytes : int;
  max_body_size_bytes : int;
}

type ingress_request = {
  method_name : string;
  path : string;
  sni_hostname : string;
  alpn_negotiated : alpn_protocol;
  client_ip : string;
  headers : (string * string) list;
  body_length : int;
}

type ingress_decision =
  | Forward_to_upstream of { target_host: string; target_port: int; sanitized_headers: (string * string) list }
  | Terminate_with_error of { status_code: int; message: string }

let default_ingress_config () = {
  listen_port = 8443;
  upstream_host = "127.0.0.1";
  upstream_port = 4100;
  tls_version = TLS_1_3;
  ciphers = [TLS_AES_256_GCM_SHA384; TLS_CHACHA20_POLY1305_SHA256];
  alpn = [H2; HTTP_1_1];
  hsts_enabled = true;
  max_header_size_bytes = 16384;
  max_body_size_bytes = 10485760;
}

let hop_by_hop_headers = [
  "connection";
  "keep-alive";
  "proxy-authenticate";
  "proxy-authorization";
  "te";
  "trailers";
  "transfer-encoding";
  "upgrade";
]

let sanitize_headers raw_headers client_ip =
  let filtered = List.filter (fun (k, _) ->
    not (List.mem (String.lowercase_ascii k) hop_by_hop_headers)
  ) raw_headers in
  ("x-forwarded-for", client_ip) ::
  ("x-forwarded-proto", "https") ::
  ("x-mirage-unikernel", "Solo5-SPT") ::
  filtered

let is_valid_sni sni =
  let lower = String.lowercase_ascii sni in
  String.equal lower "nas-1.tail55d152.ts.net" ||
  String.equal lower "vm-1.tail55d152.ts.net" ||
  String.equal lower "localhost" ||
  String.equal lower "127.0.0.1" ||
  String.ends_with ~suffix:".tail55d152.ts.net" lower

let evaluate_request config req =
  if req.body_length > config.max_body_size_bytes then
    Terminate_with_error { status_code = 413; message = "Payload Too Large: exceeds 10MB limit" }
  else if String.contains req.path '\x00' then
    Terminate_with_error { status_code = 400; message = "Bad Request: Malformed URI containing NUL byte" }
  else if not (is_valid_sni req.sni_hostname) then
    Terminate_with_error { status_code = 403; message = "Forbidden: Untrusted SNI hostname" }
  else
    let sanitized = sanitize_headers req.headers req.client_ip in
    Forward_to_upstream {
      target_host = config.upstream_host;
      target_port = config.upstream_port;
      sanitized_headers = sanitized;
    }

let cipher_to_string = function
  | TLS_AES_256_GCM_SHA384 -> "TLS_AES_256_GCM_SHA384"
  | TLS_CHACHA20_POLY1305_SHA256 -> "TLS_CHACHA20_POLY1305_SHA256"

let alpn_to_string = function
  | H2 -> "h2"
  | HTTP_1_1 -> "http/1.1"

let config_to_json (c : ingress_config) : Yojson.Safe.t =
  `Assoc [
    ("listen_port", `Int c.listen_port);
    ("upstream_host", `String c.upstream_host);
    ("upstream_port", `Int c.upstream_port);
    ("tls_version", `String "TLSv1.3");
    ("ciphers", `List (List.map (fun cip -> `String (cipher_to_string cip)) c.ciphers));
    ("alpn", `List (List.map (fun a -> `String (alpn_to_string a)) c.alpn));
    ("hsts_enabled", `Bool c.hsts_enabled);
    ("max_header_size_bytes", `Int c.max_header_size_bytes);
    ("max_body_size_bytes", `Int c.max_body_size_bytes);
  ]
