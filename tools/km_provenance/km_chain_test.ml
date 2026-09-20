let need b m = if not b then failwith m
let fixture f =
  let db = Sqlite3.db_open ":memory:" in
  Fun.protect ~finally:(fun () -> Km_chain.close db) (fun () ->
    Km_chain.ok (Sqlite3.exec db Km_chain.schema);
    f db)
let append db id = Km_chain.append db ~cycle_id:id ~plan_id:"fixture-plan"
  ~task_id:"fixture-task" ~kind:"test" ~title:"fixture" ~body:"original"
  ~observed:"2026-09-30T00:00:00Z" ~evidence:"[]"
let rejected f = try f (); false with Km_chain.Invalid _ -> true
let () =
  fixture (fun db ->
    ignore (append db "A"); ignore (append db "B");
    need (Km_chain.verify db = (2, [])) "positive chain control";
    let rc = Sqlite3.exec db
      "INSERT OR REPLACE INTO cycle SELECT 3,cycle_id,plan_id,task_id,kind,title,body,observed_utc,evidence_json,(SELECT digest FROM cycle WHERE sequence=2),'replacement' FROM cycle WHERE sequence=1" in
    need (rc <> Sqlite3.Rc.OK) "REPLACE must not delete a historical cycle";
    need (Km_chain.verify db = (2, [])) "rejected replace preserves full chain");
  fixture (fun db ->
    ignore (append db "A");
    Km_chain.ok (Sqlite3.exec db "DROP TRIGGER cycle_no_update; UPDATE cycle SET body='corrupt' WHERE sequence=1");
    need (rejected (fun () -> ignore (append db "B"))) "append must refuse corrupt history";
    need (Km_chain.head db = 1) "failed append must not insert a row");
  fixture (fun db ->
    ignore (append db "A");
    need (rejected (fun () -> ignore (append db "A"))) "duplicate append must fail";
    ignore (append db "B");
    need (Km_chain.verify db = (2, [])) "failed append rolls back and releases transaction");
  print_endline "PASS: cycle append, corruption refusal, REPLACE refusal and rollback controls"
