module Adjudicator = struct
  type recommendation =
    | Rejected_fabrication
    | Code_present_requires_fresh_two_key_rebind
    | Superseded_by_sa_plan

  exception Input_error of string

  let err m = Error m
  let ok x = Ok x

  let max_input = 262144
  let max_claims = 16
  let max_evidence = 16
  let max_clock_digits = 16
  let max_locator_bytes = 1024

  let is_hex_lower c =
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')

  let is_lower_hex_len s n =
    String.length s = n &&
    let rec go i =
      if i = n then true
      else if is_hex_lower s.[i] then go (i+1)
      else false
    in go 0

  let is_commit s = is_lower_hex_len s 40
  let is_sha256 s = is_lower_hex_len s 64

  let is_canonical_clock s =
    let l = String.length s in
    l > 0 && l <= max_clock_digits &&
    if l = 1 then s.[0] >= '0' && s.[0] <= '9'
    else s.[0] >= '1' && s.[0] <= '9' &&
         let rec go i =
           if i = l then true
           else if s.[i] >= '0' && s.[i] <= '9' then go (i+1)
           else false
         in go 1

  (* Strict UTF-8 scalar validation over raw input bytes (RFC 3629), linear,
     run before the JSON parser. Refuses stray continuation bytes, truncated
     and overlong forms, raw surrogate encodings (ED A0..BF), code points
     above U+10FFFF and invalid lead bytes (C0, C1, F5..FF). Pure byte
     inspection: no filesystem access is implied by any character. *)
  let validate_utf8 s =
    let n = String.length s in
    let bad i = raise (Input_error ("invalid utf-8 at byte " ^ string_of_int i)) in
    let cont i = i < n && (Char.code s.[i]) land 0xC0 = 0x80 in
    let in_range i lo hi = i < n && (let b = Char.code s.[i] in b >= lo && b <= hi) in
    let i = ref 0 in
    while !i < n do
      let b = Char.code s.[!i] in
      if b < 0x80 then incr i
      else if b >= 0xC2 && b <= 0xDF then begin
        if cont (!i + 1) then i := !i + 2 else bad !i
      end else if b >= 0xE0 && b <= 0xEF then begin
        let ok1 =
          if b = 0xE0 then in_range (!i + 1) 0xA0 0xBF
          else if b = 0xED then in_range (!i + 1) 0x80 0x9F
          else cont (!i + 1) in
        if ok1 && cont (!i + 2) then i := !i + 3 else bad !i
      end else if b >= 0xF0 && b <= 0xF4 then begin
        let ok1 =
          if b = 0xF0 then in_range (!i + 1) 0x90 0xBF
          else if b = 0xF4 then in_range (!i + 1) 0x80 0x8F
          else cont (!i + 1) in
        if ok1 && cont (!i + 2) && cont (!i + 3) then i := !i + 4 else bad !i
      end else bad !i
    done

  let bound_nesting s =
    let len = String.length s in
    if len > max_input then raise (Input_error "input exceeds 262144 bytes");
    let depth = ref 0 in
    let in_str = ref false in
    let esc = ref false in
    let i = ref 0 in
    while !i < len do
      let c = s.[!i] in
      if !in_str then begin
        if !esc then esc := false
        else if c = '\\' then esc := true
        else if c = '"' then in_str := false
      end else begin
        if c = '"' then in_str := true
        else if c = '{' || c = '[' then begin
          incr depth;
          if !depth > 64 then raise (Input_error "json nesting exceeds 64")
        end else if c = '}' || c = ']' then begin
          if !depth = 0 then raise (Input_error "unbalanced json nesting");
          decr depth
        end
      end;
      incr i
    done;
    if !depth <> 0 || !in_str then raise (Input_error "unbalanced json nesting")

  type evidence_kind =
    | Code_present
    | Fabrication
    | Superseded
    | Incident_presence

  type evidence = {
    e_kind : evidence_kind;
    e_locator : string;
    e_candidate : string option;
    e_sha : string option;
    e_tick : string option;
    e_utc : string option;
  }

  type claim = {
    ev : int;
    adr : int;
    evidence : evidence list;
  }

  type report = {
    candidate_commit : string;
    source_map_sha256 : string;
    claims : claim list;
  }

  let assoc_opt_str k obj =
    match List.assoc_opt k obj with
    | Some (`String s) -> s
    | Some _ -> raise (Input_error ("field " ^ k ^ " must be string"))
    | None -> raise (Input_error ("missing field " ^ k))

  let assoc_opt_int k obj =
    match List.assoc_opt k obj with
    | Some (`Int i) -> i
    | Some _ -> raise (Input_error ("field " ^ k ^ " must be int"))
    | None -> raise (Input_error ("missing field " ^ k))

  let null_ok_string k obj =
    match List.assoc_opt k obj with
    | Some `Null -> None
    | Some (`String s) -> Some s
    | Some _ -> raise (Input_error ("field " ^ k ^ " must be null or string"))
    | None -> raise (Input_error ("missing field " ^ k))

  let rec check_duplicate_keys obj path =
    match obj with
    | `Assoc pairs ->
        let seen = Hashtbl.create (List.length pairs) in
        List.iter (fun (k,_) ->
          if Hashtbl.mem seen k then
            raise (Input_error ("duplicate key " ^ k ^ " at " ^ path))
          else Hashtbl.add seen k ();
        ) pairs;
        List.iter (fun (k,v) ->
          check_duplicate_keys v (path ^ "." ^ k)
        ) pairs
    | `List items ->
        List.iteri (fun i v ->
          check_duplicate_keys v (path ^ "[" ^ string_of_int i ^ "]")
        ) items
    | _ -> ()

let check_exact_keys expected pairs =
  let actual = List.map fst pairs in
  let rec has_dup = function [] -> false | x::xs -> List.mem x xs || has_dup xs in
  if has_dup actual then raise (Input_error "duplicate object key");
  let s = List.sort compare actual in
  let e = List.sort compare expected in
  if s <> e then raise (Input_error "unknown or missing object key")

let parse_evidence obj =
  match obj with
  | `Assoc pairs ->
      check_exact_keys ["kind";"locator";"candidate_commit";"source_map_sha256";"tick_us";"utc_us"] pairs;
      let kind_str = assoc_opt_str "kind" pairs in
      let kind = match kind_str with
        | "code_present" -> Code_present
        | "fabrication" -> Fabrication
        | "superseded" -> Superseded
        | "incident_presence" -> Incident_presence
        | _ -> raise (Input_error "invalid evidence kind") in
      let locator = assoc_opt_str "locator" pairs in
      if String.length locator = 0 || String.length locator > max_locator_bytes then raise (Input_error "locator must be 1..1024 bytes");
      if String.contains locator '\x00' then raise (Input_error "locator contains NUL");
      let cand = null_ok_string "candidate_commit" pairs in
      let sha = null_ok_string "source_map_sha256" pairs in
      (match cand with Some c -> if not (is_commit c) then raise (Input_error "bad evidence candidate_commit") | None -> ());
      (match sha with Some s -> if not (is_sha256 s) then raise (Input_error "bad evidence source_map_sha256") | None -> ());
      let tick = null_ok_string "tick_us" pairs in
      let utc = null_ok_string "utc_us" pairs in
      (match tick with Some t -> if not (is_canonical_clock t) then raise (Input_error "bad tick_us") | None -> ());
      (match utc with Some u -> if not (is_canonical_clock u) then raise (Input_error "bad utc_us") | None -> ());
      { e_kind = kind; e_locator = locator; e_candidate = cand; e_sha = sha; e_tick = tick; e_utc = utc }
  | _ -> raise (Input_error "evidence must be object")

let parse_claim obj =
  match obj with
  | `Assoc pairs ->
      check_exact_keys ["ev";"adr";"evidence"] pairs;
      let ev = assoc_opt_int "ev" pairs in
      let adr = assoc_opt_int "adr" pairs in
      if ev < 94 || ev > 109 then raise (Input_error "ev out of range 94..109");
      if adr < 71 || adr > 86 then raise (Input_error "adr out of range 71..86");
      if adr <> ev - 23 then raise (Input_error "adr must equal ev-23");
      let ev_list = match List.assoc_opt "evidence" pairs with
        | Some (`List l) -> l
        | Some _ -> raise (Input_error "evidence must be list")
        | None -> raise (Input_error "missing evidence") in
      if List.length ev_list > max_evidence then raise (Input_error "evidence list too long");
      let evidence = List.map parse_evidence ev_list in
      { ev; adr; evidence }
  | _ -> raise (Input_error "claim must be object")

let parse_report json =
  match json with
  | `Assoc pairs ->
      check_exact_keys ["candidate_commit";"source_map_sha256";"claims"] pairs;
      let candidate = assoc_opt_str "candidate_commit" pairs in
      if not (is_commit candidate) then raise (Input_error "bad candidate_commit");
      let sha = assoc_opt_str "source_map_sha256" pairs in
      if not (is_sha256 sha) then raise (Input_error "bad source_map_sha256");
      let claims_json = match List.assoc_opt "claims" pairs with
        | Some (`List l) -> l
        | Some _ -> raise (Input_error "claims must be list")
        | None -> raise (Input_error "missing claims") in
      if List.length claims_json <> max_claims then raise (Input_error "claims must have exactly 16 items");
      let claims = List.map parse_claim claims_json in
      let seen_ev = Hashtbl.create 16 in
      let seen_adr = Hashtbl.create 16 in
      List.iter (fun c ->
        if Hashtbl.mem seen_ev c.ev then raise (Input_error "duplicate EV");
        Hashtbl.add seen_ev c.ev ();
        if Hashtbl.mem seen_adr c.adr then raise (Input_error "duplicate ADR");
        Hashtbl.add seen_adr c.adr ();
      ) claims;
      List.iter (fun ev -> if not (Hashtbl.mem seen_ev ev) then raise (Input_error "missing EV")) (List.init 16 (fun i -> i+94));
      List.iter (fun adr -> if not (Hashtbl.mem seen_adr adr) then raise (Input_error "missing ADR")) (List.init 16 (fun i -> i+71));
      { candidate_commit = candidate; source_map_sha256 = sha; claims }
  | _ -> raise (Input_error "top-level must be object")
  let advisory_findings claim report_json =
    let top_commit = report_json.candidate_commit in
    let top_sha = report_json.source_map_sha256 in
    let findings = ref [] in
    List.iter (fun e ->
      (match e.e_candidate with
       | Some c when c <> top_commit ->
           findings := "evidence candidate_commit differs from top-level candidate_commit" :: !findings
       | _ -> ());
      (match e.e_sha with
       | Some s when s <> top_sha ->
           findings := "evidence source_map_sha256 differs from top-level source_map_sha256" :: !findings
       | _ -> ());
      (match e.e_tick, e.e_utc with
       | Some t, Some u when t = u ->
           findings := "forged_clock_evidence: tick_us equals utc_us" :: !findings
       | _ -> ());
      if e.e_kind = Fabrication then
        findings := "caller asserts fabrication (cannot prove)" :: !findings;
      if e.e_kind = Incident_presence then
        findings := "incident_presence locator presence-only (not read/hashed)" :: !findings;
      if e.e_kind = Code_present then
        findings := "code_present assertion unverified" :: !findings;
      if e.e_kind = Superseded then
        findings := "superseded assertion unverified" :: !findings;
    ) claim.evidence;
    List.rev !findings

  let claim_to_json c report =
    let findings = advisory_findings c report in
    `Assoc [
      ("ev", `Int c.ev);
      ("adr", `Int c.adr);
      ("historical_status", `String "NOT_ADMITTED");
      ("recommendation", `Null);
      ("forensic_state", `String "pending_forensic_analysis");
      ("evidence_status", `String "caller_assertion_unverified");
      ("advisory_findings", `List (List.map (fun s -> `String s) findings));
      ("secret_bytes_read", `Bool false);
      ("secret_bytes_hashed", `Bool false);
    ]

  let report_to_json r =
    `Assoc [
      ("schema", `String "uos.provenance-adjudication.v1");
      ("authority", `String "REPORT_ONLY_CALLER_ASSERTIONS");
      ("sovereignty_authority", `Bool false);
      ("admitted_ev_ceiling", `Int 93);
      ("application_admitted", `Bool false);
      ("system_admitted", `Bool false);
      ("freshness", `String "UNVERIFIED");
      ("readback_verified", `Bool false);
      ("candidate_commit_asserted", `String r.candidate_commit);
      ("source_map_sha256_asserted", `String r.source_map_sha256);
      ("claims", `List (List.map (fun c -> claim_to_json c r) r.claims));
    ]

  (* Strict RFC 8259 grammar check, run before Yojson. Yojson alone accepts
     comments, NaN/Infinity, tuples, variants and similar extensions; those
     are refused here so only standard JSON reaches the parser. *)
  let strict_validate s =
    let n = String.length s in
    let fail m = raise (Input_error ("nonstandard json: " ^ m)) in
    let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' in
    let is_digit c = c >= '0' && c <= '9' in
    let is_hex c = is_digit c || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') in
    let rec skip i = if i < n && is_ws s.[i] then skip (i + 1) else i in
    let rec digits i = if i < n && is_digit s.[i] then digits (i + 1) else i in
    let lit i w =
      let l = String.length w in
      if i + l <= n && String.sub s i l = w then i + l else fail "bad literal" in
    let uhex j = j + 6 <= n && is_hex s.[j+2] && is_hex s.[j+3]
                 && is_hex s.[j+4] && is_hex s.[j+5] in
    let hex4 k = int_of_string ("0x" ^ String.sub s k 4) in
    let rec str j =
      if j >= n then fail "unterminated string"
      else
        let c = s.[j] in
        if c = '"' then j + 1
        else if Char.code c < 0x20 then fail "control character in string"
        else if c = '\\' then begin
          if j + 1 >= n then fail "bad escape"
          else match s.[j + 1] with
            | '"' | '\\' | '/' | 'b' | 'f' | 'n' | 'r' | 't' -> str (j + 2)
            | 'u' ->
                if not (uhex j) then fail "bad unicode escape"
                else begin
                  let cp = hex4 (j + 2) in
                  if cp >= 0xD800 && cp <= 0xDBFF then begin
                    if j + 12 <= n && s.[j+6] = '\\' && s.[j+7] = 'u' && uhex (j + 6)
                       && (let lo = hex4 (j + 8) in lo >= 0xDC00 && lo <= 0xDFFF)
                    then str (j + 12) else fail "unpaired high surrogate escape"
                  end else if cp >= 0xDC00 && cp <= 0xDFFF then fail "unpaired low surrogate escape"
                  else str (j + 6)
                end
            | _ -> fail "bad escape"
        end else str (j + 1) in
    let number i =
      let i = if i < n && s.[i] = '-' then i + 1 else i in
      if i >= n || not (is_digit s.[i]) then fail "bad number";
      let i = if s.[i] = '0' then i + 1 else digits i in
      let i =
        if i < n && s.[i] = '.' then begin
          let j = digits (i + 1) in
          if j = i + 1 then fail "bad fraction" else j
        end else i in
      if i < n && (s.[i] = 'e' || s.[i] = 'E') then begin
        let j = if i + 1 < n && (s.[i+1] = '+' || s.[i+1] = '-') then i + 2 else i + 1 in
        let k = digits j in
        if k = j then fail "bad exponent" else k
      end else i in
    let rec value d i =
      if d > 64 then raise (Input_error "json nesting exceeds 64");
      let i = skip i in
      if i >= n then fail "unexpected end"
      else match s.[i] with
        | '{' ->
            let j = skip (i + 1) in
            if j < n && s.[j] = '}' then j + 1 else members d j
        | '[' ->
            let j = skip (i + 1) in
            if j < n && s.[j] = ']' then j + 1 else elements d j
        | '"' -> str (i + 1)
        | 't' -> lit i "true"
        | 'f' -> lit i "false"
        | 'n' -> lit i "null"
        | '-' | '0' .. '9' -> number i
        | _ -> fail "unexpected token"
    and members d i =
      let i = skip i in
      if i >= n || s.[i] <> '"' then fail "expected object key"
      else
        let i = skip (str (i + 1)) in
        if i >= n || s.[i] <> ':' then fail "expected colon"
        else
          let i = skip (value (d + 1) (i + 1)) in
          if i >= n then fail "unterminated object"
          else if s.[i] = ',' then members d (i + 1)
          else if s.[i] = '}' then i + 1
          else fail "bad object"
    and elements d i =
      let i = skip (value (d + 1) i) in
      if i >= n then fail "unterminated array"
      else if s.[i] = ',' then elements d (i + 1)
      else if s.[i] = ']' then i + 1
      else fail "bad array" in
    let e = skip (value 1 0) in
    if e <> n then fail "trailing data"

  let adjudicate input =
    try
      if String.length input > max_input then raise (Input_error "input exceeds 262144 bytes");
      validate_utf8 input;
      bound_nesting input;
      strict_validate input;
      let json = Yojson.Safe.from_string input in
      check_duplicate_keys json "root";
      let report = parse_report json in
      Ok (report_to_json report)
    with
    | Input_error msg -> err msg
    | Yojson.Json_error msg -> err ("malformed json: " ^ msg)

end

(* Explicit, pure, typed ADVISORY API mirroring formal/lean/ProvenanceAdjudication.lean.
   Lean correspondence: Claim/mkClaim? -> Claim.make; Claim.adr -> Claim.adr;
   Dossier/initial -> dossier/initial; Dossier.addRecommendation ->
   add_recommendation (append-only); Dossier.recordClock -> record_clock (never
   touches recs); ClockEvidence.status -> clock_status; Inv -> invariant_holds.
   No JSON is accepted here: a recommendation can only be supplied as a typed
   value by the caller, is advisory only, and never changes admission state.
   The Lean model is a candidate; this module is not proven to conform to it. *)
module Advisory : sig
  type recommendation = Adjudicator.recommendation =
    | Rejected_fabrication
    | Code_present_requires_fresh_two_key_rebind
    | Superseded_by_sa_plan

  type historical_status = Not_admitted

  val status_label : historical_status -> string
  val recommendation_label : recommendation -> string
  val all_recommendations : recommendation list

  module Claim : sig
    type t = private { ev : int }
    val make : int -> (t, string) result
    val ev : t -> int
    val adr : t -> int
  end

  type utc = Utc of int
  type monotonic = Monotonic of int
  type clock_evidence = { utc : utc; mono : monotonic }
  type clock_status = Valid | Invalid_clock_evidence

  val clock_status : clock_evidence -> clock_status
  val clock_status_label : clock_status -> string

  (* ABSTRACT: the control state (ceiling, admission flags, history, claims,
     recs, clocks) cannot be forged by record construction or record update
     outside this module. Values arise only from [initial], [dossier_of_evs],
     [add_recommendation] and [record_clock], matching Lean reachability. *)
  type dossier

  val initial : dossier
  val dossier_of_evs : int list -> (dossier, string) result
  val add_recommendation : dossier -> int -> recommendation -> (dossier, string) result
  val record_clock : dossier -> int -> clock_evidence -> (dossier, string) result
  val invariant_holds : dossier -> bool
  val to_json : dossier -> Yojson.Safe.t

  (* read-only getters *)
  val ceiling : dossier -> int
  val application_admitted : dossier -> bool
  val system_admitted : dossier -> bool
  val history : dossier -> historical_status
  val claims : dossier -> Claim.t list
  val recs : dossier -> (Claim.t * recommendation) list
  val clocks : dossier -> (Claim.t * clock_evidence) list
end = struct
  type recommendation = Adjudicator.recommendation =
    | Rejected_fabrication
    | Code_present_requires_fresh_two_key_rebind
    | Superseded_by_sa_plan

  type historical_status = Not_admitted

  let status_label Not_admitted = "NOT_ADMITTED"

  let recommendation_label = function
    | Rejected_fabrication -> "rejectedFabrication"
    | Code_present_requires_fresh_two_key_rebind -> "codePresentRequiresFreshTwoKeyRebind"
    | Superseded_by_sa_plan -> "supersededBySaPlan"

  let all_recommendations =
    [Rejected_fabrication; Code_present_requires_fresh_two_key_rebind; Superseded_by_sa_plan]

  module Claim : sig
    type t = private { ev : int }
    val make : int -> (t, string) result
    val ev : t -> int
    val adr : t -> int
  end = struct
    type t = { ev : int }
    let make n =
      if n >= 94 && n <= 109 then Ok { ev = n }
      else Error ("invalid EV " ^ string_of_int n ^ ": outside 94..109")
    let ev c = c.ev
    let adr c = c.ev - 23
  end

  type utc = Utc of int
  type monotonic = Monotonic of int
  type clock_evidence = { utc : utc; mono : monotonic }
  type clock_status = Valid | Invalid_clock_evidence

  let clock_status e =
    match e.utc, e.mono with
    | Utc u, Monotonic m -> if u = m then Invalid_clock_evidence else Valid

  let clock_status_label = function
    | Valid -> "valid"
    | Invalid_clock_evidence -> "invalidClockEvidence"

  type dossier = {
    ceiling : int;
    application_admitted : bool;
    system_admitted : bool;
    history : historical_status;
    claims : Claim.t list;
    recs : (Claim.t * recommendation) list;
    clocks : (Claim.t * clock_evidence) list;
  }

  let all_claims =
    List.filter_map (fun n -> Result.to_option (Claim.make n)) (List.init 16 (fun i -> 94 + i))

  let initial = {
    ceiling = 93; application_admitted = false; system_admitted = false;
    history = Not_admitted; claims = all_claims; recs = []; clocks = [];
  }

  (* A dossier restricted to a caller-chosen claim subset, so that a claim
     can be unknown to a dossier. Every EV must be valid and unique. *)
  let dossier_of_evs evs =
    let rec go acc = function
      | [] -> Ok { initial with claims = List.rev acc }
      | n :: rest ->
          (match Claim.make n with
           | Error m -> Error m
           | Ok c ->
               if List.mem c acc then Error ("duplicate EV " ^ string_of_int n)
               else go (c :: acc) rest) in
    go [] evs

  let find_claim d ev =
    match Claim.make ev with
    | Error m -> Error m
    | Ok c ->
        if List.mem c d.claims then Ok c
        else Error ("unknown EV " ^ string_of_int ev ^ ": not a claim of this dossier")

  (* Lean addRecommendation: append-only; only recs changes. *)
  let add_recommendation d ev r =
    match find_claim d ev with
    | Error m -> Error m
    | Ok c -> Ok { d with recs = d.recs @ [ (c, r) ] }

  (* Lean recordClock: only clocks changes; recs and admission state untouched. *)
  let record_clock d ev e =
    match find_claim d ev with
    | Error m -> Error m
    | Ok c -> Ok { d with clocks = d.clocks @ [ (c, e) ] }

  let ceiling d = d.ceiling
  let application_admitted d = d.application_admitted
  let system_admitted d = d.system_admitted
  let history d = d.history
  let claims d = d.claims
  let recs d = d.recs
  let clocks d = d.clocks

  let invariant_holds d =
    d.ceiling = 93 && not d.application_admitted && not d.system_admitted
    && d.history = Not_admitted
    && List.for_all (fun (c, _) -> List.mem c d.claims) d.recs

  let to_json d =
    `Assoc [
      ("schema", `String "uos.provenance-adjudication-advisory.v1");
      ("authority", `String "REPORT_ONLY_ADVISORY_RECOMMENDATIONS");
      ("sovereignty_authority", `Bool false);
      ("admitted_ev_ceiling", `Int d.ceiling);
      ("application_admitted", `Bool d.application_admitted);
      ("system_admitted", `Bool d.system_admitted);
      ("readback_verified", `Bool false);
      ("claims", `List (List.map (fun c ->
        `Assoc [
          ("ev", `Int (Claim.ev c));
          ("adr", `Int (Claim.adr c));
          ("historical_status", `String (status_label d.history));
          ("recommendation_authority", `String "ADVISORY_ONLY");
          ("advisory_recommendations",
           `List (List.filter_map (fun (c2, r) ->
             if c2 = c then Some (`String (recommendation_label r)) else None) d.recs));
          ("clock_statuses",
           `List (List.filter_map (fun (c2, e) ->
             if c2 = c then Some (`String (clock_status_label (clock_status e))) else None) d.clocks));
        ]) d.claims));
    ]
end
