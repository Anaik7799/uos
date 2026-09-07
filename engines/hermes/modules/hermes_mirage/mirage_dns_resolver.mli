(* Unified Operational System (UOS) - MirageOS Pure OCaml DNS Resolver *)
(* Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001 *)

type record_type = A | AAAA | TXT | SRV

type dns_answer = {
  domain : string;
  rtype : record_type;
  ttl_seconds : int;
  rdata : string;
}

type dns_response = {
  query_domain : string;
  answers : dns_answer list;
  authoritative : bool;
  resolver_latency_us : int;
  cached : bool;
}

type resolver_state

val create_resolver : unit -> resolver_state
val resolve_query : resolver_state -> string -> record_type -> (dns_response, [ `Blocked_domain | `Resolution_timeout | `NXDOMAIN ]) result
val add_static_record : resolver_state -> string -> record_type -> int -> string -> unit
val clear_cache : resolver_state -> unit
val cache_size : resolver_state -> int
val response_to_json : dns_response -> Yojson.Safe.t
