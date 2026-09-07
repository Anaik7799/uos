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

type resolver_state = {
  static_records : (string * record_type, dns_answer) Hashtbl.t;
  cache : (string * record_type, dns_answer * float) Hashtbl.t;
}

let create_resolver () =
  let state = {
    static_records = Hashtbl.create 32;
    cache = Hashtbl.create 64;
  } in
  (* Prepopulate canonical Tailscale mesh endpoints *)
  Hashtbl.add state.static_records ("nas-1.tail55d152.ts.net", A)
    { domain = "nas-1.tail55d152.ts.net"; rtype = A; ttl_seconds = 3600; rdata = "100.87.7.78" };
  Hashtbl.add state.static_records ("vm-1.tail55d152.ts.net", A)
    { domain = "vm-1.tail55d152.ts.net"; rtype = A; ttl_seconds = 3600; rdata = "100.78.98.18" };
  Hashtbl.add state.static_records ("localhost", A)
    { domain = "localhost"; rtype = A; ttl_seconds = 86400; rdata = "127.0.0.1" };
  Hashtbl.add state.static_records ("localhost", AAAA)
    { domain = "localhost"; rtype = AAAA; ttl_seconds = 86400; rdata = "::1" };
  state

let add_static_record state domain rtype ttl rdata =
  let ans = { domain; rtype; ttl_seconds = ttl; rdata } in
  Hashtbl.replace state.static_records (domain, rtype) ans

let clear_cache state =
  Hashtbl.clear state.cache

let cache_size state =
  Hashtbl.length state.cache

let is_valid_domain domain =
  String.length domain > 0 && String.length domain <= 253 &&
  not (String.contains domain ' ') &&
  not (String.contains domain '\x00')

let is_blocked domain =
  let lower = String.lowercase_ascii domain in
  String.ends_with ~suffix:".internal.threat" lower ||
  String.contains lower ';' ||
  String.contains lower '\'' ||
  String.contains lower '"'

let resolve_query state domain rtype =
  if not (is_valid_domain domain) || is_blocked domain then
    Error `Blocked_domain
  else
    let t_start = Unix.gettimeofday () in
    (* Check static authoritative records first *)
    match Hashtbl.find_opt state.static_records (domain, rtype) with
    | Some ans ->
        let t_end = Unix.gettimeofday () in
        let lat = int_of_float ((t_end -. t_start) *. 1_000_000.0) in
        Ok {
          query_domain = domain;
          answers = [ans];
          authoritative = true;
          resolver_latency_us = max 1 lat;
          cached = false;
        }
    | None ->
        (* Check cache with TTL *)
        let now = Unix.gettimeofday () in
        match Hashtbl.find_opt state.cache (domain, rtype) with
        | Some (ans, expiry) when now < expiry ->
            let lat = int_of_float ((now -. t_start) *. 1_000_000.0) in
            Ok {
              query_domain = domain;
              answers = [ans];
              authoritative = false;
              resolver_latency_us = max 1 lat;
              cached = true;
            }
        | _ ->
            (* Synthetic Tailscale mesh synthesis for testing/resolution *)
            if String.ends_with ~suffix:".tail55d152.ts.net" domain then
              let synthetic_ans = {
                domain;
                rtype;
                ttl_seconds = 300;
                rdata = (match rtype with A -> "100.87.7.99" | AAAA -> "fd7a:115c:a1e0::99" | _ -> "synth");
              } in
              Hashtbl.replace state.cache (domain, rtype) (synthetic_ans, now +. 300.0);
              let t_end = Unix.gettimeofday () in
              let lat = int_of_float ((t_end -. t_start) *. 1_000_000.0) in
              Ok {
                query_domain = domain;
                answers = [synthetic_ans];
                authoritative = false;
                resolver_latency_us = max 1 lat;
                cached = false;
              }
            else
              Error `NXDOMAIN

let rtype_to_string = function
  | A -> "A"
  | AAAA -> "AAAA"
  | TXT -> "TXT"
  | SRV -> "SRV"

let answer_to_json (a : dns_answer) : Yojson.Safe.t =
  `Assoc [
    ("domain", `String a.domain);
    ("rtype", `String (rtype_to_string a.rtype));
    ("ttl_seconds", `Int a.ttl_seconds);
    ("rdata", `String a.rdata);
  ]

let response_to_json (r : dns_response) : Yojson.Safe.t =
  `Assoc [
    ("query_domain", `String r.query_domain);
    ("answers", `List (List.map answer_to_json r.answers));
    ("authoritative", `Bool r.authoritative);
    ("resolver_latency_us", `Int r.resolver_latency_us);
    ("cached", `Bool r.cached);
  ]
