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

val default_ingress_config : unit -> ingress_config
val evaluate_request : ingress_config -> ingress_request -> ingress_decision
val sanitize_headers : (string * string) list -> string -> (string * string) list
val config_to_json : ingress_config -> Yojson.Safe.t
