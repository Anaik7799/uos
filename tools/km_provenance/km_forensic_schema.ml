(* OI01 observed-artifact schema. Pure decoder, no filesystem/process effects.
   Laws: exactly16 EV/ADR pairs; closed report-only flags and recommendation
   labels; unique safe source paths; exact per-claim references; recomputed
   candidate/path/byte-digest map. Missing observations remain pending.
   A coherent JSON artifact DOES NOT authenticate local origin, source bytes,
   signer identity, clock truth or sovereign review. Those remain external.
   Null candidate is a coherent FAILURE report only, not a valid SHA binding. *)
module A = Km_adjudication.Adjudicator
module S = Km_forensic_scan

type recommendation = A.recommendation =
  | Rejected_fabrication
  | Code_present_requires_fresh_two_key_rebind
  | Superseded_by_sa_plan
type summary = {
  candidate : string option;
  source_map_sha256 : string;
  claims : int;
  sources : int;
  candidate_bound_sources : int;
  dirty_sources : int;
  pending_claims : int;
  recommendations : (recommendation * int) list;
  origin : S.origin;
}
exception Invalid of string
let refuse label = raise (Invalid label)
let require b label = if not b then refuse label
let object_fields keys = function
  | `Assoc fields -> A.check_exact_keys keys fields; fields
  | _ -> refuse "expected_object"
let field k f = match List.assoc_opt k f with Some x -> x | None -> refuse "missing_field"
let text = function `String x -> x | _ -> refuse "expected_string"
let integer = function `Int x -> x | _ -> refuse "expected_integer"
let array max = function `List xs when List.length xs <= max -> xs
  | _ -> refuse "expected_bounded_array"
let exact value json label = require (value=json) label
let unique key xs label =
  let keys=List.map key xs in
  require (List.length keys=List.length (List.sort_uniq compare keys)) label
let basename_in dir p =
  let prefix=dir ^ "/" in
  if String.starts_with ~prefix p then
    let name=String.sub p (String.length prefix) (String.length p-String.length prefix) in
    if not (String.contains name '/') then Some name else None
  else None
let any_adr name = List.exists (fun i -> S.adr_filename (71+i) name) (List.init 16 Fun.id)
let any_receipt name = List.exists (fun i -> S.receipt_filename (94+i) name) (List.init 16 Fun.id)
let quarantine_path p =
  match basename_in S.quarantine_dir p with
  | Some name -> String.length name>=10 && String.length name<=180 &&
      S.valid_relative name &&
      String.for_all (function '0'..'9' -> true | _ -> false) (String.sub name 0 10) &&
      (String.ends_with ~suffix:".json" name || String.ends_with ~suffix:".txt" name)
  | None -> false
let source_path p = S.valid_relative p &&
  (S.allowed_code p ||
   (match basename_in "docs/zk" p with Some n -> any_adr n | None -> false) ||
   (match basename_in S.receipt_dir p with Some n -> any_receipt n | None -> false))
let gap_path p =
  source_path p || quarantine_path p ||
  List.mem p ["jj:ancestry";"docs/zk";S.receipt_dir;S.quarantine_dir] ||
  List.exists (fun i -> p=Printf.sprintf "docs/zk/ADR-%03d" (71+i) ||
    List.exists (fun ending -> p=Printf.sprintf "%s/EV-%03d%s" S.receipt_dir (94+i) ending)
      ["";"/runtime";"/formal"]) (List.init 16 Fun.id)
let gap_status = function
  | "MISSING" -> S.Missing | "UNSAFE" -> S.Unsafe | "CHANGED" -> S.Changed
  | "BOUND_EXCEEDED" -> S.Too_large | "AMBIGUOUS" -> S.Ambiguous
  | "DIRTY_BINDING" -> S.Unbound | "UNRUN" -> S.Unrun
  | "INVALID_RECEIPT" -> S.Invalid_receipt
  | "UNVERIFIED_SIGNATURE" -> S.Unverified_signature
  | "PROCESS_FAILURE" -> S.Process_failure
  | _ -> refuse "unknown_gap_status"
let gaps max json =
  let xs=array max json |> List.map (fun j ->
    let f=object_fields ["locator";"status"] j in
    let p=text (field "locator" f) in require (gap_path p) "unsafe_gap_locator";
    p,gap_status (text (field "status" f))) in
  unique Fun.id xs "duplicate_gap"; xs
let source json : S.source =
  let f=object_fields ["path";"sha256";"binding"] json in
  let path=text (field "path" f) and sha256=text (field "sha256" f) in
  require (source_path path) "unsafe_source_path";
  require (A.is_sha256 sha256) "invalid_source_sha256";
  let binding=match text (field "binding" f) with
    | "CANDIDATE_BOUND" -> S.Candidate_bound | "DIRTY_BINDING" -> S.Dirty_binding
    | _ -> refuse "unknown_source_binding" in
  {path;sha256;binding}
let same_source (a:S.source) (b:S.source) =
  a.path=b.path && a.sha256=b.sha256 && a.binding=b.binding
let recommendation = function
  | `Null -> None
  | `String "REJECTED_FABRICATION" -> Some Rejected_fabrication
  | `String "CODE_PRESENT_REQUIRES_FRESH_TWO_KEY_REBIND" -> Some Code_present_requires_fresh_two_key_rebind
  | `String "SUPERSEDED_BY_SA_PLAN" -> Some Superseded_by_sa_plan
  | _ -> refuse "unknown_recommendation"
type decoded_claim = { ev:int; refs:S.source list; rec_:recommendation option }
let claim sources json =
  let f=object_fields ["ev";"adr";"historical_status";"document";"code";"receipts";"recommendation";"gaps"] json in
  let ev=integer (field "ev" f) and adr=integer (field "adr" f) in
  require (ev>=94 && ev<=109 && adr=ev-23) "invalid_ev_adr_pair";
  exact (`String "NOT_ADMITTED") (field "historical_status" f) "historical_status_promoted";
  let gs=gaps 64 (field "gaps" f) in
  let document=match field "document" f with `Null -> None | j -> Some(source j) in
  (match document with None -> () | Some d ->
    require (match basename_in "docs/zk" d.path with Some n -> S.adr_filename adr n | None -> false)
      "wrong_claim_document");
  let code=array S.max_refs (field "code" f) |> List.map source in
  require (List.for_all (fun (s:S.source) -> S.allowed_code s.path) code) "wrong_claim_code_path";
  require (code=[] || document<>None) "code_without_document";
  let receipts=array 2 (field "receipts" f) |> List.map source in
  require (List.for_all (fun (s:S.source) -> match basename_in S.receipt_dir s.path with
    Some n -> S.receipt_filename ev n | None -> false) receipts) "wrong_claim_receipt";
  let refs=(match document with None -> [] | Some d -> [d]) @ code @ receipts in
  unique (fun (s:S.source) -> s.path) refs "duplicate_claim_source";
  List.iter (fun s ->
    require (List.exists (same_source s) sources) "source_reference_mismatch";
    if s.S.binding=S.Dirty_binding then require (List.mem (s.path,S.Unbound) gs) "dirty_source_gap_missing") refs;
  List.iter (fun (s:S.source) -> require
    (List.exists (fun (p,g) -> p=s.path && (g=S.Invalid_receipt || g=S.Unverified_signature)) gs)
    "unverified_receipt_gap_missing") receipts;
  let rec_=recommendation (field "recommendation" f) in
  (match rec_ with
    | None -> require (List.for_all (fun s -> s.S.binding=S.Dirty_binding) code)
        "pending_despite_candidate_bound_code"
    | Some Code_present_requires_fresh_two_key_rebind -> require (code<>[]) "rebind_without_code"
    | Some (Rejected_fabrication|Superseded_by_sa_plan) ->
      (* These are CLOSED ADVISORY labels, not a finding inferred by validation.
         A factual classification still needs independent forensic review. *)
      require (document<>None || receipts<>[]) "opinion_without_observed_evidence");
  {ev;refs;rec_}

let validate input =
  try
    require (String.length input<=A.max_input) "input_bound";
    A.validate_utf8 input; A.bound_nesting input; A.strict_validate input;
    let j=Yojson.Safe.from_string input in A.check_duplicate_keys j "root";
    let f=object_fields ["schema";"status";"authority";"historical_status";"two_key_verified";
      "admitted_ev_ceiling";"application_admitted";"system_admitted";"readback_verified";
      "origin";"ancestry_scope";"receipt_namespace";"trusted_receipt_verifier";
      "candidate_commit";"ancestry";"source_map_sha256";"sources";"quarantine_presence";"gaps";"claims"] j in
    List.iter (fun (key,value) -> exact (`String value) (field key f) ("invalid_" ^ key))
      ["schema","uos-forensic-scan-v1";"status","HOLD";"authority","NONE";
       "historical_status","NOT_ADMITTED";
       "ancestry_scope","ONE_DIRECT_PARENT_AND_AT_MOST_SIX_ANCESTORS";
       "receipt_namespace",S.receipt_dir;"trusted_receipt_verifier","UNAVAILABLE"];
    List.iter (fun key -> exact (`Bool false) (field key f) ("forbidden_" ^ key))
      ["two_key_verified";"application_admitted";"system_admitted";"readback_verified"];
    exact (`Int 93) (field "admitted_ev_ceiling" f) "ceiling_changed";
    let origin=match text (field "origin" f) with
      | "LOCAL_OBSERVATION" -> S.Local_observation | "SYNTHETIC_FIXTURE" -> S.Synthetic_fixture
      | _ -> refuse "invalid_origin" in
    let candidate=match field "candidate_commit" f with `Null -> None
      | `String c when A.is_commit c -> Some c | _ -> refuse "invalid_candidate_commit" in
    let ancestry=array 6 (field "ancestry" f) |> List.map text in
    require (List.for_all A.is_commit ancestry) "invalid_ancestry_commit";
    unique Fun.id ancestry "duplicate_ancestry";
    let global_gaps=gaps 8192 (field "gaps" f) in
    (match candidate,ancestry with
      | Some c,first::_ when first=c -> ()
      | None,[] -> require (List.exists (fun (p,_) -> p="jj:ancestry") global_gaps) "missing_candidate_failure_gap"
      | _ -> refuse "candidate_ancestry_mismatch");
    let sources=array 176 (field "sources" f) |> List.map source in
    unique (fun (s:S.source) -> s.path) sources "duplicate_source_path";
    require (candidate<>None || List.for_all (fun s -> s.S.binding=S.Dirty_binding) sources)
      "bound_source_without_candidate";
    let source_map_sha256=text (field "source_map_sha256" f) in
    require (A.is_sha256 source_map_sha256) "invalid_source_map_sha256";
    require (source_map_sha256=S.source_map_hash ?candidate sources) "source_map_mismatch";
    let quarantine=array S.max_entries (field "quarantine_presence" f) |> List.map text in
    require (List.for_all quarantine_path quarantine) "unsafe_quarantine_locator";
    unique Fun.id quarantine "duplicate_quarantine_locator";
    require (quarantine<>[] || List.exists (fun(p,_) -> p=S.quarantine_dir) global_gaps)
      "missing_quarantine_gap";
    let claims=array 16 (field "claims" f) |> List.map (claim sources) in
    require (List.length claims=16) "claim_count";
    unique (fun c -> c.ev) claims "duplicate_claim";
    let used=List.concat_map (fun c -> c.refs) claims in
    require (List.for_all (fun s -> List.exists (same_source s) used) sources) "unreferenced_source";
    let pending_claims=List.fold_left (fun n c -> n + if c.rec_=None then 1 else 0) 0 claims in
    let candidate_bound_sources=List.length (List.filter (fun s -> s.S.binding=S.Candidate_bound) sources) in
    let recommendations=List.map (fun r -> r,List.length (List.filter (fun c -> c.rec_=Some r) claims))
      [Rejected_fabrication;Code_present_requires_fresh_two_key_rebind;Superseded_by_sa_plan] in
    Ok {candidate;source_map_sha256;claims=16;sources=List.length sources;
      candidate_bound_sources;dirty_sources=List.length sources-candidate_bound_sources;
      pending_claims;recommendations;origin}
  with
  | Invalid label -> Error label
  | A.Input_error _ | Yojson.Json_error _ -> Error "invalid_strict_json_or_fields"

let summary_to_json (s:summary) =
  let label = function Rejected_fabrication -> "REJECTED_FABRICATION"
    | Code_present_requires_fresh_two_key_rebind -> "CODE_PRESENT_REQUIRES_FRESH_TWO_KEY_REBIND"
    | Superseded_by_sa_plan -> "SUPERSEDED_BY_SA_PLAN" in
  `Assoc ["schema",`String "uos-forensic-schema-validation-v1";
    "status",`String "SCHEMA_COHERENT_REPORT_ONLY";"authority",`String "NONE";
    "schema_valid",`Bool true;"origin_authenticated",`Bool false;
    "readback_verified",`Bool false;"signatures_verified",`Bool false;
    "two_key_verified",`Bool false;"admitted_ev_ceiling",`Int 93;
    "application_admitted",`Bool false;"system_admitted",`Bool false;
    "historical_status",`String "NOT_ADMITTED";
    "candidate_commit",(match s.candidate with None -> `Null | Some c -> `String c);
    "source_map_sha256",`String s.source_map_sha256;
    "claims",`Int s.claims;"sources",`Int s.sources;
    "candidate_bound_sources",`Int s.candidate_bound_sources;
    "dirty_sources",`Int s.dirty_sources;"pending_claims",`Int s.pending_claims;
    "recommendation_counts",`List(List.map(fun(r,n)->`Assoc["recommendation",`String(label r);"count",`Int n])s.recommendations);
    "origin_claimed",`String(match s.origin with S.Local_observation -> "LOCAL_OBSERVATION" | S.Synthetic_fixture -> "SYNTHETIC_FIXTURE");
    "limitation",`String "Artifact shape and coherence only; local origin, source bytes, signatures and sovereign review are not authenticated"]
