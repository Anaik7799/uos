module S = Km_forensic_scan
module V = Km_forensic_schema
let checks=ref 0
let check n b = incr checks; if not b then failwith n
let ok = function Ok x -> x | Error e -> failwith ("unexpected schema refusal: " ^ e)
let json j = Yojson.Safe.to_string j
let accepted j = match V.validate (json j) with Ok _ -> true | Error _ -> false
let rejected n j = check n (not(accepted j))
let fields = function `Assoc f -> f | _ -> failwith "fixture object"
let set k v j = `Assoc (List.map(fun(key,old)->key,if key=k then v else old)(fields j))
let remove k j = `Assoc(List.remove_assoc k (fields j))
let get k j = List.assoc k (fields j)
let items = function `List xs -> xs | _ -> failwith "fixture array"
let first_claim f j = match items(get "claims" j) with
  | x::xs -> set "claims" (`List(f x::xs)) j | [] -> failwith "claims"
let first_code f c = match items(get "code" c) with
  | x::xs -> set "code" (`List(f x::xs)) c | [] -> failwith "code"
let cand=String.make 40 'a'
let code : S.source = {path="apps/fixture/src/shared.gleam";sha256=S.hash "fixture code";binding=S.Candidate_bound}
let document adr : S.source = {path=Printf.sprintf "docs/zk/20261031-1614-adr-%03d-fixture.md" adr;
  sha256=S.hash(string_of_int adr);binding=S.Candidate_bound}
let fixture : S.report =
  let docs=List.init 16(fun i->document(71+i)) in
  let sources=S.canonical_sources(code::docs) in
  {origin=S.Synthetic_fixture;candidate=Some cand;ancestry=[cand;String.make 40 'b'];
   sources;source_map_sha256=S.source_map_hash ~candidate:cand sources;
   claims=List.init 16(fun i-> {S.ev=94+i;adr=71+i;document=Some(List.nth docs i);
     code=[code];receipts=[];recommendation=Some "CODE_PRESENT_REQUIRES_FRESH_TWO_KEY_REBIND";
     gaps=[Printf.sprintf "%s/EV-%03d" S.receipt_dir (94+i),S.Unrun]});
   quarantine_presence=[S.quarantine_dir ^ "/0000000422.json"];
   gaps=[S.receipt_dir,S.Unrun]}
let j=S.to_json fixture
let () =
  let s = ok (V.validate(json j)) in
  check "synthetic coherent baseline" (s.claims=16 && s.sources=17 && s.candidate_bound_sources=17 && s.pending_claims=0);
  check "summary never authenticates origin" (get "origin_authenticated" (V.summary_to_json s)=`Bool false);
  check "summary never verifies source readback" (get "readback_verified" (V.summary_to_json s)=`Bool false);
  check "summary never admits" (get "application_admitted" (V.summary_to_json s)=`Bool false && get "system_admitted" (V.summary_to_json s)=`Bool false);
  List.iter(fun label->check("closed advisory label "^label)(accepted(first_claim(set "recommendation" (`String label))j)))
    ["REJECTED_FABRICATION";"CODE_PRESENT_REQUIRES_FRESH_TWO_KEY_REBIND";"SUPERSEDED_BY_SA_PLAN"];
  List.iter(fun label->rejected("unknown recommendation "^label)(first_claim(set "recommendation" (`String label))j))
    ["ADMITTED";"UNKNOWN";"REJECTED";"SOVEREIGN_APPROVED";"";"code_present_requires_fresh_two_key_rebind"];
  rejected "null only if code insufficient" (first_claim(set "recommendation" `Null)j);
  let pending=first_claim(fun c->set "code" (`List[])c |> set "recommendation" `Null)j in
  check "pending without code remains null" (accepted pending);
  let empty_sources=[] in
  let missing : S.report = {fixture with sources=empty_sources;
    source_map_sha256=S.source_map_hash ~candidate:cand empty_sources;
    claims=List.map(fun(c:S.claim)->{c with document=None;code=[];recommendation=None;
      gaps=[Printf.sprintf "docs/zk/ADR-%03d" c.adr,S.Missing]}) fixture.claims} in
  let missing_summary=ok(V.validate(json(S.to_json missing))) in
  check "all missing observations stay pending" (missing_summary.pending_claims=16 && missing_summary.sources=0);
  List.iter(fun label->rejected "no opinion synthesized from missing evidence"
    (first_claim(set "recommendation" (`String label))(S.to_json missing)))
    ["REJECTED_FABRICATION";"CODE_PRESENT_REQUIRES_FRESH_TWO_KEY_REBIND";"SUPERSEDED_BY_SA_PLAN"];
  let dirty={code with S.binding=S.Dirty_binding} in
  let sources=S.canonical_sources(dirty::List.init 16(fun i->document(71+i))) in
  let dirty_fixture={fixture with sources;source_map_sha256=S.source_map_hash ~candidate:cand sources;
    claims=List.map(fun(c:S.claim)->{c with code=[dirty];gaps=(dirty.path,S.Unbound)::c.gaps})fixture.claims} in
  let ds=ok(V.validate(json(S.to_json dirty_fixture))) in
  check "dirty observations are coherent but not verified" (ds.dirty_sources=1 && get "readback_verified" (V.summary_to_json ds)=`Bool false);
  check "dirty evidence may remain unknown" (accepted(first_claim(set "recommendation" `Null)(S.to_json dirty_fixture)));
  let receipt:S.source={path=S.receipt_dir ^ "/20261031-1614-ev-094-runtime.receipt.json";
    sha256=S.hash "unsigned fixture receipt";binding=S.Candidate_bound} in
  let receipt_sources=S.canonical_sources(receipt::fixture.sources) in
  let receipt_fixture={fixture with sources=receipt_sources;
    source_map_sha256=S.source_map_hash ~candidate:cand receipt_sources;
    claims=List.map(fun(c:S.claim)->if c.ev=94 then
      {c with receipts=[receipt];gaps=(receipt.path,S.Unverified_signature)::c.gaps} else c)fixture.claims} in
  let unverified=ok(V.validate(json(S.to_json receipt_fixture))) in
  check "unsigned receipt shape never verifies two keys"
    (get "two_key_verified" (V.summary_to_json unverified)=`Bool false);
  rejected "unsigned receipt cannot omit its explicit gap"
    (first_claim(set "gaps" (get "gaps" (List.hd(items(get "claims" j)))))(S.to_json receipt_fixture));
  let no_candidate={missing with candidate=None;ancestry=[];
    source_map_sha256=S.source_map_hash [];gaps=["jj:ancestry",S.Process_failure]} in
  let nc=ok(V.validate(json(S.to_json no_candidate))) in
  check "missing candidate coherent failure report stays none" (nc.candidate=None);
  rejected "missing candidate cannot claim bound sources" (set "candidate_commit" `Null j);
  rejected "missing candidate needs ancestry failure gap" (set "gaps" (`List[])(S.to_json no_candidate));
  List.iter(fun k->rejected("missing root key "^k)(remove k j))(List.map fst(fields j));
  List.iter(fun k->rejected("missing claim key "^k)(first_claim(remove k)j))
    (List.map fst(fields(List.hd(items(get "claims" j)))));
  let cs=items(get "claims" j) in
  rejected "missing claim" (set "claims" (`List(List.tl cs))j);
  rejected "17 claims" (set "claims" (`List(List.hd cs::cs))j);
  rejected "duplicate claim" (set "claims" (`List(List.hd cs::List.hd cs::List.tl(List.tl cs)))j);
  List.iter(fun ev->rejected "out of range EV" (first_claim(set "ev" (`Int ev))j))[93;110];
  rejected "wrong ADR" (first_claim(set "adr" (`Int 72))j);
  rejected "EV wrong scalar type" (first_claim(set "ev" (`Float 94.0))j);
  rejected "claim promotion" (first_claim(set "historical_status" (`String "ADMITTED"))j);
  List.iter(fun key->rejected("true authority flag "^key)(set key (`Bool true)j))
    ["two_key_verified";"application_admitted";"system_admitted";"readback_verified"];
  List.iter(fun(key,value)->rejected("closed root field "^key)(set key value j))
    ["status",`String "PASS";"authority",`String "SOVEREIGN";"admitted_ev_ceiling",`Int 109;
     "historical_status",`String "ADMITTED";"origin",`String "TRUSTED";
     "trusted_receipt_verifier",`String "VERIFIED";"receipt_namespace",`String "var/transcripts"];
  List.iter(fun value->rejected "invalid candidate SHA" (set "candidate_commit" value j))
    [`String(String.make 39 'a');`String(String.make 40 'A');`String(String.make 40 'g');`Int 40];
  rejected "source map tamper" (set "source_map_sha256" (`String(String.make 64 '0'))j);
  rejected "missing source map" (remove "source_map_sha256" j);
  rejected "source map malformed" (set "source_map_sha256" (`String "bad")j);
  rejected "nested missing sha" (first_claim(first_code(remove "sha256"))j);
  rejected "source binding mismatch" (first_claim(first_code(set "binding" (`String "DIRTY_BINDING")))j);
  rejected "source digest mismatch" (first_claim(first_code(set "sha256" (`String(String.make 64 '0'))))j);
  rejected "unknown binding" (first_claim(first_code(set "binding" (`String "VERIFIED")))j);
  let ss=items(get "sources" j) in
  rejected "duplicate source path" (set "sources" (`List(List.hd ss::ss))j);
  rejected "missing global source" (set "sources" (`List(List.tl ss))j);
  rejected "unsafe source traversal" (first_claim(first_code(set "path" (`String "apps/f/src/../../private.gleam")))j);
  rejected "unsafe receipt path" (first_claim(set "receipts" (`List[List.hd ss]))j);
  rejected "unsafe absolute quarantine" (set "quarantine_presence" (`List[`String "/proc/1/environ"])j);
  rejected "unsafe quarantine traversal" (set "quarantine_presence" (`List[`String(S.quarantine_dir^"/../secret.json")])j);
  rejected "duplicate quarantine" (set "quarantine_presence" (`List[`String(List.hd fixture.quarantine_presence);`String(List.hd fixture.quarantine_presence)])j);
  rejected "missing quarantine needs explicit gap" (set "quarantine_presence" (`List[])j);
  check "missing quarantine remains a coherent failure"
    (accepted(set "quarantine_presence" (`List[])j |> set "gaps"
      (`List[`Assoc["locator",`String S.quarantine_dir;"status",`String "MISSING"]])));
  rejected "duplicate ancestry" (set "ancestry" (`List[`String cand;`String cand])j);
  rejected "candidate ancestry mismatch" (set "ancestry" (`List[`String(String.make 40 'b')])j);
  rejected "unknown gap status" (set "gaps" (`List[`Assoc["locator",`String S.receipt_dir;"status",`String "PASS"]])j);
  rejected "unsafe gap locator" (set "gaps" (`List[`Assoc["locator",`String "var/private-key";"status",`String "MISSING"]])j);
  let duplicated=`Assoc(("schema",`String "uos-forensic-scan-v1")::fields j) in
  rejected "duplicate root key" duplicated;
  rejected "duplicate nested key" (first_claim(fun c->`Assoc(("ev",`Int 94)::fields c))j);
  let raw=json j in
  let rejects_raw name s=check name (match V.validate s with Error _->true|Ok _->false) in
  List.iter(fun(name,s)->rejects_raw name s)
    ["corrupt JSON","{";"JSON extension","/*comment*/"^raw;"nonRFC NaN","NaN";
     "nonRFC tuple","(1,2)";"trailing payload",raw^"false";
     "invalid UTF8",raw^"\192\128";"oversize",String.make 262145 ' ';
     "escaped lone surrogate","\"\\ud800\"";
     "excess nesting",String.make 65 '[' ^ "0" ^ String.make 65 ']'];
  rejects_raw "escaped unicode duplicate key"
    ("{\"\\u0073chema\":\"uos-forensic-scan-v1\"," ^ String.sub raw 1 (String.length raw-1));
  List.iter(fun seed->let random=Random.State.make[|seed|] in
    for _=1 to 32 do
      let shuffled=List.map(fun c->Random.State.bits random,c) cs |> List.sort compare |> List.map snd in
      check "claim order invariance" (accepted(set "claims" (`List shuffled)j))
    done)[71;109];
  (* Operational artifacts are validated explicitly by the CLI integration gate.
     Unit coverage must not depend on an optional private session receipt. *)
  Printf.printf "km_forensic_schema: %d checks passed\n" !checks
