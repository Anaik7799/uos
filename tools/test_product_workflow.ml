#use "test_product_catalog.ml";;
#use "product_workflow.ml";;
let workflow_count=ref 0
let test name f = f();incr workflow_count;Printf.printf "ok workflow %s\n" name
let () =
 let path=Filename.temp_file "uos-workflow-test-" ".sqlite3" in
 Fun.protect ~finally:(fun()->Sys.remove path) (fun()->with_db ~readonly:false path(fun db->
  import db (fixture()) ~authorize:(fun()->());
  let id=init db "test" "v1" "test-worker" "isolated#test" ~authorize:(fun()->()) in
  test "hierarchy has exact required containment" (fun()->
   require(query db "SELECT count(*) FROM product_workflow_nodes" []=[[Sqlite3.Data.INT 7L]]) "wrong hierarchy size";
   let r=report db id in require(member "required_cases" r=`Int 1 && member "state" r=`String "UNRUN") "vacuous completion");
  test "candidate replay is idempotent" (fun()->
   require(init db "test" "v1" "test-worker" "isolated#test" ~authorize:(fun()->())=id) "candidate changed";
   require(query db "SELECT count(*) FROM product_workflow_nodes" []=[[Sqlite3.Data.INT 7L]]) "replay duplication");
  test "owner change gives a new immutable candidate" (fun()->
   let next=init db "test" "v1" "other-worker" "isolated#test" ~authorize:(fun()->()) in
   require(next<>id) "owner not bound";
   require(query db "SELECT count(*) FROM product_workflow_candidates" []=[[Sqlite3.Data.INT 2L]]) "history not retained");
  test "cross-plan candidate is rejected" (fun()->
   require(rejects(fun()->ignore(init db "test" "v1" "test-worker" "other#test" ~authorize:(fun()->())))) "cross-plan accepted");
  test "oracle mutation requires the candidate owner and exact task" (fun()->
   let manifest=get_candidate db id in
   validate_candidate_authority manifest ~plan:"isolated" ~task:"test" ~owner:"test-worker";
   List.iter(fun(plan,task,owner)->require(rejects(fun()->
    validate_candidate_authority manifest ~plan ~task ~owner)) "foreign task can write candidate receipts")
    ["other","test","test-worker";"isolated","other","test-worker";"isolated","test","other-worker"]);
  test "representative vectors execute the full receipt gate" (fun()->
   List.init 512 Fun.id |>List.iter(fun mask->
    let bits=List.init 9(fun bit->mask land(1 lsl bit)<>0) in
    require(actual_gate bits=(mask=511)) "receipt gate disagrees with independent conjunction"));
  test "replacement cannot destroy candidate or nodes" (fun()->
   exec db "PRAGMA recursive_triggers=OFF";
   require(rejects(fun()->exec db "INSERT OR REPLACE INTO product_workflow_candidates SELECT * FROM product_workflow_candidates")) "candidate replacement";
   require(rejects(fun()->exec db "INSERT OR REPLACE INTO product_workflow_nodes SELECT * FROM product_workflow_nodes")) "node replacement");
  test "lease loss rolls back a candidate and its whole hierarchy" (fun()->
   let calls=ref 0 in
   require(rejects(fun()->ignore(init db "test" "v1" "aborted-owner" "isolated#test" ~authorize:(fun()->incr calls;if !calls=2 then fail "lost lease")))) "lease bypass";
   require(query db "SELECT count(*) FROM product_workflow_candidates" []=[[Sqlite3.Data.INT 2L]]) "partial candidate";
   require(query db "PRAGMA foreign_key_check" []=[]) "dangling hierarchy");
  test "malformed receipt cannot manufacture a passing predicate" (fun()->
   let payload=`Assoc["schema",`String "uos.native-eligibility-runtime/v1";"observed",`Float(Unix.gettimeofday());"passed",`Bool true;
    "case_id",`String native_case;"vectors",`List(List.init 512(fun n->`Assoc["mask",`Int n;"accepted",`Bool true]));
    "hash_comparisons",`List [];"versions",`List []] in
   append_observation db id "runtime" payload ~authorize:(fun()->());
   let r=report db id in require(member "native_eligibility" r=`String "BLOCKED") "forged pass accepted";
   require(member "state" r=`String "UNRUN") "internal evidence leaked to product acceptance");
  test "receipt and artifact update are atomic under ownership loss" (fun()->
   let calls=ref 0 in
   let payload=`Assoc["schema",`String "bad";"observed",`Float(Unix.gettimeofday());"case_id",`String native_case;"passed",`Bool false] in
   require(rejects(fun()->append_observation db id "formal" payload ~authorize:(fun()->incr calls;if !calls=2 then fail "lease lost"))) "receipt lease bypass";
   require(query db "SELECT count(*) FROM product_workflow_receipts" []=[[Sqlite3.Data.INT 1L]]) "partial receipt committed");
  test "unparseable and incomplete latest receipts block only their case" (fun()->
   List.iteri(fun i content->
    let digest=sha content and now=Unix.gettimeofday() in
    let artifact_id="malformed:"^string_of_int i in
    let artifact=`Assoc["id",`String artifact_id;"revision",`String digest;"kind",`String "test";
     "locator",`String "isolated-test";"sha256",`String digest;"content",`String content] in
    transaction db(fun()->store_artifact db artifact;
     ignore(query db "INSERT INTO product_workflow_receipts(candidate_id,case_id,kind,binding,artifact_id,artifact_revision,observed,expires) VALUES(?,?,?,?,?,?,?,?)"
      [s id;s native_case;s "formal";s "{}";s artifact_id;s digest;Sqlite3.Data.FLOAT now;Sqlite3.Data.FLOAT(now+.3600.)]));
    let r=report db id in
    require(member "native_eligibility" r=`String "BLOCKED" && member "state" r=`String "UNRUN") "malformed receipt crashed or passed"
   )["not JSON";"null";"{\"case_id\":12}"]);
  test "bad hierarchy is rejected on read" (fun()->
   require(rejects(fun()->transaction db(fun()->
    ignore(query db "INSERT INTO product_workflow_nodes VALUES(?,?,?,?,?,?,?,?)" [s id;s "rogue";s "f1";Sqlite3.Data.INT 3L;Sqlite3.Data.INT 1L;s "test";s "isolated#test";s "{}"]);
    ignore(report db id)))) "invalid containment passed";
   require(query db "PRAGMA integrity_check" []=[[s "ok"]]) "integrity failure")));
 Printf.printf "product-workflow integration tests: %d passed\n" !workflow_count
