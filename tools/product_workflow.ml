#!/usr/bin/env -S opam exec -- ocaml
#use "product_catalog.ml";;
#require "mtime.clock.os,str";;
#mod_use "product_workflow_core.ml";;
#mod_use "product_oracle.ml";;
module W=Product_workflow_core
module O=Product_oracle
let database="data/sqlite/uos_verification_tracking.sqlite3"
let native_case="native.eligibility.case"
let normalizer="exact-lines/v1:trim-line-edges;drop-empty-lines;preserve-line-order"
let source_paths=["tools/product_catalog.ml";"tools/product_workflow.ml";"tools/product_workflow_core.ml";
 "tools/product_workflow_core.mli";"tools/product_oracle.ml";"tools/test_product_catalog.ml";"tools/test_product_workflow_core.ml";
 "tools/test_product_workflow.ml";"tools/test_product_oracles.ml";"tools/product_workflow_view.ml"]
let json_string value=`String value
let json_strings xs=`List(List.map json_string xs)
let data_text=function Sqlite3.Data.TEXT value->value | _->fail "expected database text"
let workflow_schema={|
CREATE TABLE IF NOT EXISTS product_workflow_candidates(
 id TEXT PRIMARY KEY, spec_id TEXT NOT NULL, revision TEXT NOT NULL,
 manifest TEXT NOT NULL CHECK(json_valid(manifest)), sha256 TEXT NOT NULL,
 created_at REAL NOT NULL,
 FOREIGN KEY(spec_id,revision) REFERENCES product_specifications(id,revision));
CREATE TABLE IF NOT EXISTS product_workflow_nodes(
 candidate_id TEXT NOT NULL, id TEXT NOT NULL, parent TEXT,
 level INTEGER NOT NULL CHECK(level BETWEEN 0 AND 3), required INTEGER NOT NULL CHECK(required IN(0,1)),
 owner TEXT NOT NULL, task_ref TEXT NOT NULL, payload TEXT NOT NULL CHECK(json_valid(payload)),
 PRIMARY KEY(candidate_id,id), FOREIGN KEY(candidate_id) REFERENCES product_workflow_candidates(id),
 FOREIGN KEY(candidate_id,parent) REFERENCES product_workflow_nodes(candidate_id,id) DEFERRABLE INITIALLY DEFERRED);
CREATE TABLE IF NOT EXISTS product_workflow_receipts(
 sequence INTEGER PRIMARY KEY AUTOINCREMENT, candidate_id TEXT NOT NULL, case_id TEXT NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN('runtime','formal')), binding TEXT NOT NULL CHECK(json_valid(binding)),
 artifact_id TEXT NOT NULL, artifact_revision TEXT NOT NULL, observed REAL NOT NULL, expires REAL NOT NULL,
 FOREIGN KEY(candidate_id,case_id) REFERENCES product_workflow_nodes(candidate_id,id),
 FOREIGN KEY(artifact_id,artifact_revision) REFERENCES product_artifacts(id,revision));
|}
let workflow_protect db =
 exec db workflow_schema;
 List.iter(fun(table,keys)->
  reject_replace db table keys;
  List.iter(fun action->exec db ("CREATE TRIGGER IF NOT EXISTS "^table^"_no_"^String.lowercase_ascii action^
   " BEFORE "^action^" ON "^table^" BEGIN SELECT RAISE(ABORT,'workflow evidence is append-only'); END")) ["UPDATE";"DELETE"])
  ["product_workflow_candidates",["id"];"product_workflow_nodes",["candidate_id";"id"];"product_workflow_receipts",["sequence"]]
let sources ()=`List(List.map(fun path->`Assoc["path",json_string path;"sha256",json_string(sha(read path))])source_paths)
let binary_manifest ()=`List(List.map(fun oracle ->
 `Assoc["path",json_string(O.binary oracle);"identity",`List(List.map(fun(path,digest)->`Assoc["path",json_string path;"sha256",json_string digest])(O.identity oracle))]) [O.Sha256;O.Z3])
let get_catalog db spec revision =
 match query db "SELECT manifest,manifest_sha256 FROM product_imports WHERE spec_id=? AND revision=?" [s spec;s revision] with
 | [[Sqlite3.Data.TEXT body;Sqlite3.Data.TEXT digest]] -> require(sha body=digest) "catalog digest mismatch";Yojson.Basic.from_string body
 | _->fail "exact catalog revision not found"
let get_candidate db id =
 match query db "SELECT manifest,sha256 FROM product_workflow_candidates WHERE id=?" [s id] with
 | [[Sqlite3.Data.TEXT body;Sqlite3.Data.TEXT digest]] -> require(sha body=digest && id=digest) "candidate digest mismatch";Yojson.Basic.from_string body
 | _->fail "candidate not found"
let source_current manifest = try encoded(member "sources" manifest)=encoded(sources ()) &&
 encoded(member "executables" manifest)=encoded(binary_manifest ()) && text "normalizer" manifest=normalizer with _->false
let binding manifest id = W.{candidate=id;specification=text "catalog_sha256" manifest;
 oracle=sha(encoded(member "executables" manifest));executable=sha(encoded(member "executables" manifest));
 normalizer=sha normalizer;checker=sha(encoded(member "sources" manifest))}
let binding_json (b:W.binding)=`Assoc["candidate",json_string b.candidate;"specification",json_string b.specification;
 "oracle",json_string b.oracle;"executable",json_string b.executable;"normalizer",json_string b.normalizer;"checker",json_string b.checker]
let decode_binding j = W.{candidate=text "candidate" j;specification=text "specification" j;oracle=text "oracle" j;
 executable=text "executable" j;normalizer=text "normalizer" j;checker=text "checker" j}
let validate_candidate_authority manifest ~plan ~task ~owner =
 require(text "owner" manifest=owner && text "sa_plan_ref" manifest=plan^"#"^task)
   "candidate owner/task differs from current Sa-plan authority"
let authorize_candidate manifest () =
 let env name=Option.value(Sys.getenv_opt name)~default:"" in
 validate_candidate_authority manifest ~plan:(env "UOS_PRODUCT_PLAN") ~task:(env "UOS_PRODUCT_TASK") ~owner:(env "UOS_PRODUCT_WORKER");
 authorize()
let node_row candidate owner task (n:W.node) payload =
 [s candidate;s n.id;(match n.parent with None->Sqlite3.Data.NULL|Some p->s p);Sqlite3.Data.INT(Int64.of_int(W.rank_level n.level));
 Sqlite3.Data.INT(if n.required then 1L else 0L);s owner;s task;s(encoded payload)]
let init db spec revision owner task ~authorize =
 require(String.trim owner<>"" && String.trim task<>"") "owner and Sa-plan reference required";
 let catalog=get_catalog db spec revision in
 require (match String.split_on_char '#' task with [plan;task_id]->
   plan=text "sa_plan_plan" (member "specification" catalog) && String.trim task_id<>"" | _->false)
   "workflow task reference differs from catalog plan";
 let root="product:"^spec in
 let node id parent level required payload=W.{id;parent;level;required},payload in
 let nodes = node root None W.Product true (member "specification" catalog) ::
  List.concat_map(fun feature ->
   let id=text "id" feature and requirements=items "requirements" feature in
   require(requirements<>[]) "feature has no requirements";
   node id (Some root) W.Feature true feature ::
   (List.map(fun r->node(text "id" r)(Some id)W.Requirement true r) requirements) @
   (List.map(fun a ->
     let parent=match member "requirement_id" a,requirements with
      | `String rid,_->require(List.exists(fun r->text "id" r=rid)requirements) "case requirement not in feature";rid
      | `Null,[r]->text "id" r | _->fail "ambiguous acceptance parent; require explicit requirement_id" in
     node(text "id" a)(Some parent)W.Acceptance true a)(items "acceptance" feature))) (items "features" catalog) @
  [node "native.eligibility" (Some root) W.Feature false (`Assoc["name",json_string "Native evidence eligibility (internal check)"]);
   node "native.eligibility.requirement" (Some "native.eligibility") W.Requirement false (`Assoc["shall",json_string "The full receipt gate accepts exactly the all-true combination in 512 representative configurations of nine conditions."]);
   node native_case (Some "native.eligibility.requirement") W.Acceptance false (`Assoc["assertion",json_string "Compare the observed evaluate_case truth table to independent Z3 conjunction with SAT controls. This covers only these finite representative configurations, not every possible receipt or the 138 infrastructure cases."])] in
 (match W.validate_nodes(List.map fst nodes)with Ok()->()|Error e->fail e);
 let manifest=`Assoc["schema",json_string "uos.product-workflow-candidate/v1";"spec_id",json_string spec;"revision",json_string revision;
  "catalog_sha256",json_string(sha(encoded catalog));"sources",sources();"executables",binary_manifest();"normalizer",json_string normalizer;
  "owner",json_string owner;"sa_plan_ref",json_string task;
  "scope",json_string "Selected-source fingerprint; no whole-repository admission"] in
 let body=encoded manifest in let id=sha body in
 transaction db(fun()->authorize();protect_history db;workflow_protect db;
  insert_absent db ~table:"product_workflow_candidates" ~columns:["id";"spec_id";"revision";"manifest";"sha256";"created_at"]
    ~values:[s id;s spec;s revision;s body;s id;Sqlite3.Data.FLOAT(Unix.gettimeofday())] ~keys:["id"] ~key_values:[s id];
  List.iter(fun(n,payload)->insert_absent db ~table:"product_workflow_nodes" ~columns:["candidate_id";"id";"parent";"level";"required";"owner";"task_ref";"payload"]
   ~values:(node_row id owner task n payload) ~keys:["candidate_id";"id"] ~key_values:[s id;s n.W.id])nodes;
  require(query db "PRAGMA foreign_key_check" []=[]) "workflow foreign keys";
  require(source_current manifest) "candidate changed during initialization";authorize());id
let read_nodes db candidate = query db "SELECT id,parent,level,required,payload FROM product_workflow_nodes WHERE candidate_id=? ORDER BY level,id" [s candidate]
 |>List.map(function [Sqlite3.Data.TEXT id;parent;Sqlite3.Data.INT level;Sqlite3.Data.INT required;Sqlite3.Data.TEXT payload]->
   W.{id;parent=(match parent with Sqlite3.Data.NULL->None|Sqlite3.Data.TEXT p->Some p|_->fail "invalid parent");
   level=(match level with 0L->Product|1L->Feature|2L->Requirement|3L->Acceptance|_->fail "invalid level");required=required=1L},Yojson.Basic.from_string payload
  |_->fail "invalid hierarchy row")
let execution_json (r:O.execution)=`Assoc["input",json_string r.input;"output",json_string r.output;"stderr",json_string r.error;
 "input_sha256",json_string(sha r.input);"output_sha256",json_string(sha r.output);"exit_code",`Int r.exit_code;"elapsed_seconds",`Float r.elapsed;
 "fault",(match r.fault with None->`Null|Some e->json_string e);"argv",json_strings r.argv;
 "identity",`List(List.map(fun(path,digest)->`Assoc["path",json_string path;"sha256",json_string digest])r.identity)]
let successful (r:O.execution)=r.exit_code=0 && r.fault=None && r.elapsed<=10. && String.trim r.error=""
let lines body=String.split_on_char '\n' body |>List.map String.trim |>List.filter((<>)"")
let actual_gate bits =
 require (List.length bits=9) "nine representative receipt conditions required";
 let flag=List.nth bits in
 let expected=W.{candidate="candidate";specification="spec";oracle="oracle";executable="exe";normalizer="normalizer";checker="checker"} in
 let runtime=W.{case_id="case";kind=Runtime;binding=(if flag 0 then expected else {expected with candidate="wrong"});
  sequence=(if flag 6 then 1 else 0);observed=(if flag 2 then 10. else 16.);expires=(if flag 3 then 20. else 12.);
  passed=flag 7;artifact_valid=flag 4;invocation_valid=flag 5} in
 let formal=W.{runtime with kind=Formal;binding=expected;sequence=2;observed=10.;expires=20.;passed=true;artifact_valid=true;invocation_valid=true} in
 let receipts=if flag 1 then [runtime;formal] else [runtime;runtime;formal] in
 (W.evaluate_case ~now:15. ~source_current:(flag 8) ~expected ~case_id:"case" receipts).state=W.Passed
let truth_query () =
 let accepted=List.init 512(fun mask->mask,List.init 9(fun bit->mask land (1 lsl bit)<>0))
  |>List.filter(fun(_,bits)->actual_gate bits) in
 let term(_,bits)="(and "^String.concat " " (List.mapi(fun i b ->if b then "b"^string_of_int i else "(not b"^string_of_int i^")")bits)^")" in
 let candidate=if accepted=[] then "false" else "(or "^String.concat " " (List.map term accepted)^")" in
 String.concat "\n" ((List.init 9(fun i->"(declare-const b"^string_of_int i^" Bool)")) @
 ["(define-fun spec () Bool (and b0 b1 b2 b3 b4 b5 b6 b7 b8))";
  "(define-fun candidate () Bool "^candidate^")";"(check-sat)";"(push)";"(assert (xor candidate spec))";
  "(check-sat)";"(pop)";"(assert spec)";"(check-sat)";"(exit)";""])
let append_observation db candidate kind payload ~authorize =
 let manifest=get_candidate db candidate in let expected=binding manifest candidate in
 let body=encoded payload in let digest=sha body in
 let id="native-oracle:"^kind^":"^digest in
 let artifact=`Assoc["id",json_string id;"revision",json_string digest;"kind",json_string "bounded-oracle-observation";
  "locator",json_string "native:product-workflow";"sha256",json_string digest;"content",json_string body] in
 let observed=member "observed" payload |>to_number in
 transaction db(fun()->authorize();require(source_current manifest) "candidate changed during oracle execution";
  store_artifact db artifact;
  ignore(query db "INSERT INTO product_workflow_receipts(candidate_id,case_id,kind,binding,artifact_id,artifact_revision,observed,expires) VALUES(?,?,?,?,?,?,?,?)"
   [s candidate;s native_case;s kind;s(encoded(binding_json expected));s id;s digest;Sqlite3.Data.FLOAT observed;Sqlite3.Data.FLOAT(observed+.3600.)]);
  require(query db "PRAGMA foreign_key_check" []=[]) "receipt foreign keys";authorize())
let run_oracles db candidate ~authorize =
 let manifest=get_candidate db candidate in require(source_current manifest) "candidate is stale";authorize();
 let sha_version=O.run O.Sha256 ~version:true "" and z3_version=O.run O.Z3 ~version:true "" in
 let fixtures=["";"abc";"O'Brien\n";"\000\001\255";String.make 4096 'a'] in
 let hashes=List.map(fun input->let r=O.run O.Sha256 ~version:false input in
  let expected=sha input^"  -" in successful r && lines r.output=[expected],execution_json r)fixtures in
 let table=List.init 512(fun mask->let bits=List.init 9(fun bit->mask land (1 lsl bit)<>0) in
  `Assoc["mask",`Int mask;"accepted",`Bool(actual_gate bits)]) in
 let runtime_pass=successful sha_version && successful z3_version && List.for_all fst hashes &&
  List.for_all(fun row->member "accepted" row=`Bool(member "mask" row=`Int 511))table in
 let now=Unix.gettimeofday() in
 let runtime=`Assoc["schema",json_string "uos.native-eligibility-runtime/v1";"observed",`Float now;"passed",`Bool runtime_pass;
  "case_id",json_string native_case;"vectors",`List table;"hash_comparisons",`List(List.map snd hashes);
  "versions",`List[execution_json sha_version;execution_json z3_version];
  "scope",json_string "512 representative evaluate_case executions plus five executable SHA256 comparisons; no infrastructure acceptance credit"] in
 append_observation db candidate "runtime" runtime ~authorize;
 let proof=O.run O.Z3 ~version:false (truth_query()) in
 let formal_pass=successful proof && lines proof.output=["sat";"unsat";"sat"] in
 let formal=`Assoc["schema",json_string "uos.native-eligibility-formal/v1";"observed",`Float(Unix.gettimeofday());"passed",`Bool formal_pass;
  "case_id",json_string native_case;"execution",execution_json proof;
  "scope",json_string "Finite equivalence of 512 representative evaluate_case configurations to independent conjunction; two SAT controls; not a universal proof of all receipts, selectors or the full system"] in
 append_observation db candidate "formal" formal ~authorize;
 require(runtime_pass && formal_pass) "native oracle comparison failed; failure observations retained"
let observed_success e =
 member "exit_code" e=`Int 0 && member "fault" e=`Null && String.trim(text "stderr" e)="" &&
 let elapsed=member "elapsed_seconds" e |>to_number in Float.is_finite elapsed && elapsed>=0. && elapsed<=10. &&
 text "input_sha256" e=sha(text "input" e) && text "output_sha256" e=sha(text "output" e)
let payload_result kind payload =
 match kind with
 | "runtime" ->
   text "schema" payload="uos.native-eligibility-runtime/v1" &&
   List.length(items "vectors" payload)=512 &&
   List.mapi(fun mask row -> member "mask" row=`Int mask && member "accepted" row=`Bool(mask=511))(items "vectors" payload) |>List.for_all Fun.id
 | "formal" ->text "schema" payload="uos.native-eligibility-formal/v1" &&
   text "input" (member "execution" payload)=truth_query() && observed_success(member "execution" payload) &&
   lines(text "output" (member "execution" payload))=["sat";"unsat";"sat"]
 | _->false
let runtime_invocations payload =
 let runs=items "hash_comparisons" payload and versions=items "versions" payload in
 let inputs=["";"abc";"O'Brien\n";"\000\001\255";String.make 4096 'a'] in
 List.length runs=5 && List.length versions=2 && List.for_all observed_success versions &&
 List.for_all2(fun e input -> observed_success e && text "input" e=input && lines(text "output" e)=[sha input^"  -"])runs inputs
let receipts db candidate =
 let manifest=get_candidate db candidate in
 let checked_execution oracle ~version e =
  let expected=items "executables" manifest |>List.find(fun j->text "path" j=O.binary oracle) in
  member "identity" e=member "identity" expected && member "argv" e=json_strings(O.command oracle ~version) in
 query db "SELECT r.sequence,r.case_id,r.kind,r.binding,r.observed,r.expires,a.content,a.sha256 FROM product_workflow_receipts r JOIN product_artifacts a ON a.id=r.artifact_id AND a.revision=r.artifact_revision WHERE r.candidate_id=? ORDER BY r.sequence" [s candidate]
 |>List.map(function [Sqlite3.Data.INT seq;Sqlite3.Data.TEXT case_id;Sqlite3.Data.TEXT kind;Sqlite3.Data.TEXT b;observed;expires;Sqlite3.Data.TEXT content;Sqlite3.Data.TEXT digest]->
  let float=function Sqlite3.Data.FLOAT f->f | Sqlite3.Data.INT n->Int64.to_float n | _->Float.nan in
  let invalid=W.{case_id;kind=(if kind="runtime" then Runtime else Formal);binding=binding manifest candidate;
   sequence=Int64.to_int seq;observed=float observed;expires=float expires;passed=false;artifact_valid=false;invocation_valid=false} in
  (try
  require(String.length content<=8*1024*1024) "receipt body too large";
  let payload=Yojson.Basic.from_string content in
  ignore(canonical payload);
  ignore(canonical(Yojson.Basic.from_string b));
  let artifact_valid=sha content=digest && text "case_id" payload=case_id &&
   to_number(member "observed" payload)=float observed && float expires=float observed+.3600. in
  let invocation_valid=case_id=native_case && (match kind with
   | "runtime" -> text "schema" payload="uos.native-eligibility-runtime/v1" && List.length(items "vectors" payload)=512 &&
     List.for_all(checked_execution O.Sha256 ~version:false)(items "hash_comparisons" payload) &&
     (match items "versions" payload with [a;b]->checked_execution O.Sha256 ~version:true a && checked_execution O.Z3 ~version:true b|_->false)
   | "formal" -> text "schema" payload="uos.native-eligibility-formal/v1" && text "input" (member "execution" payload)=truth_query() && checked_execution O.Z3 ~version:false (member "execution" payload)
   | _->false) in
  let measured_pass=payload_result kind payload && (kind<>"runtime" || runtime_invocations payload) in
  W.{case_id;kind=(if kind="runtime" then Runtime else Formal);binding=decode_binding(Yojson.Basic.from_string b);
   sequence=Int64.to_int seq;observed=float observed;expires=float expires;passed=measured_pass && member "passed" payload=`Bool true;artifact_valid;invocation_valid}
  with _ -> invalid)
  |_->fail "invalid receipt row")
let report db candidate =
 let manifest=get_candidate db candidate in let nodes=read_nodes db candidate in
 (match W.validate_nodes(List.map fst nodes)with Ok()->()|Error e->fail e);
 let expected=binding manifest candidate and source_current=source_current manifest and now=Unix.gettimeofday() in
 let receipts=receipts db candidate in
 let rec verdict (node:W.node)=if node.level=W.Acceptance then W.evaluate_case ~now ~source_current ~expected ~case_id:node.id receipts
  else let children=List.filter(fun(child,_)->child.W.parent=Some node.id)nodes in
   let required=List.filter(fun(child,_)->child.W.required)children in
   let selected=if required=[] && not node.required then children else required in
   selected |>List.map(fun(child,_)->verdict child) |>W.roll_up in
 let root=List.find(fun(node,_)->node.W.level=W.Product)nodes |>fst in
 let node_json(n,payload)=let v=verdict n in
  `Assoc["id",json_string n.W.id;"parent",(match n.parent with None->`Null|Some p->json_string p);"level",`Int(W.rank_level n.level);
   "required",`Bool n.required;"state",json_string(W.state_name v.state);"reasons",json_strings v.reasons;"definition",payload] in
 `Assoc["schema",json_string "uos.product-workflow-report/v1";"candidate",json_string candidate;"observed",`Float now;
  "owner",member "owner" manifest;"sa_plan_ref",member "sa_plan_ref" manifest;"source_current",`Bool source_current;
  "state",json_string(W.state_name(verdict root).state);"admission",json_string "NOT_ADMITTED";
  "native_eligibility",json_string(W.state_name(W.evaluate_case ~now ~source_current ~expected ~case_id:native_case receipts).state);
  "required_cases",`Int(List.length(List.filter(fun(n,_)->n.W.level=W.Acceptance && n.required)nodes));
  "receipt_count",`Int(List.length receipts);"nodes",`List(List.map node_json nodes);
  "scope",json_string "Required-child rollup; internal finite oracle is separate from original infrastructure acceptance"]
let run_workflow ()=match Array.to_list Sys.argv with
 | [_;"init";spec;revision;owner;task]->
   require(Some owner=Sys.getenv_opt "UOS_PRODUCT_WORKER" &&
    Some task=Option.bind (Sys.getenv_opt "UOS_PRODUCT_PLAN") (fun p->Option.map(fun t->p^"#"^t)(Sys.getenv_opt "UOS_PRODUCT_TASK")))
    "candidate owner/task differs from current Sa-plan authority";
   with_db ~readonly:false database(fun db->print_endline(init db spec revision owner task ~authorize))
 | [_;"oracle";candidate]->with_db ~readonly:false database(fun db->
   let authorize=authorize_candidate(get_candidate db candidate) in
   run_oracles db candidate ~authorize;print_endline(encoded(report db candidate)))
 | [_;"report";candidate]->with_db ~readonly:true database(fun db->print_endline(Yojson.Basic.pretty_to_string(report db candidate)))
 | _->fail "usage: product_workflow.ml init SPEC REV OWNER SA_PLAN_REF | oracle CANDIDATE | report CANDIDATE"
let ()=if not !Sys.interactive && Filename.basename Sys.argv.(0)="product_workflow.ml" then
 try run_workflow() with e->prerr_endline("product-workflow: "^Printexc.to_string e);exit 1
