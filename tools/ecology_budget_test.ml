#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
let () = match Array.to_list Sys.argv with
  | [_; "oracle-selftest"] -> ()
  | _ -> prerr_endline "usage: ocaml tools/ecology_budget_test.ml oracle-selftest"; exit 2;;
#use "ecology_budget.ml";;

(* @agent_intent: bounded PRIVATE SQLite fixtures only, no canonical ledger.
   Run this file with the sole argument oracle-selftest: loading the exact
   product source first executes its memory-only CLI test, then these tests.
   @laws: historical rows/meta/liabilities survive exact legacy upgrade;
   admission/cap/append-only/clock fences survive; precommit faults roll back. *)

let checks=ref 0
let check name yes=if not yes then failwith("TEST FAILED: "^name) else incr checks
let ok=function Ok value->value|Error e->failwith("unexpected "^error_label e)
let fixture_root=Fpath.v (Unix.realpath(Filename.get_temp_dir_name()))
let ()=match Bos.OS.Dir.create fixture_root with Ok _->()|Error(`Msg e)->failwith e
let run_dir=Fpath.(fixture_root / ("uos-ecology-budget-test-"^string_of_int(Unix.getpid())))
let ()=match Bos.OS.Dir.create run_dir with Ok true->()|Ok false->failwith "fixture directory exists"|Error(`Msg e)->failwith e
let fixture_path name=Fpath.to_string Fpath.(run_dir / name)
let with_fixture path f=
  let db=Sqlite3.db_open ~mode:`NO_CREATE ~uri:false path in
  Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db))(fun()->f db)
let expected_models=["z-ai/glm-5.3",(1400,4400);"moonshotai/kimi-k3",(3000,15000);
  "deepseek/deepseek-v4-pro-0813",(1320,3960);"deepseek/deepseek-v4-flash-0731",(65,180);
  "google/gemma-4-31b-it",(90,340);"google/gemma-4-26b-a4b-it",(90,340)]
let now=host_now()
let day_us=86_400_000_000L
let initialized=Int64.sub now(Int64.mul 4L day_us)
let insert db ~id ~at ~model =
  let day=(ok(time at)).day in
  let prompt,completion=List.assoc model expected_models in
  let worst=Int64.of_int((32+2048)*prompt+128*completion) in
  statement db "INSERT INTO reservations VALUES(?,?,?,?,?,?,?,?,?)"
    [Sqlite3.Data.TEXT id;Sqlite3.Data.TEXT day;Sqlite3.Data.INT at;Sqlite3.Data.TEXT model;
     Sqlite3.Data.INT 128L;Sqlite3.Data.INT 32L;Sqlite3.Data.INT 64L;Sqlite3.Data.INT worst;
     Sqlite3.Data.INT reservation](fun stmt->sql_ok(Sqlite3.step stmt))
let legacy_fixture name=
  let path=fixture_path name in
  let fd=Unix.openfile path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
  Unix.close fd;
  with_fixture path(fun db->
    exec db "PRAGMA journal_mode=WAL";
    exec db "PRAGMA recursive_triggers=ON";
    List.iter(fun(_,sql)->exec db sql)(schema_for expected_models);
    statement db "INSERT INTO budget_meta VALUES(1,1,?,10000000000,250000000)"
      [Sqlite3.Data.INT initialized](fun stmt->sql_ok(Sqlite3.step stmt));
    for i=0 to 9 do
      let ago=if i<5 then Int64.mul 2L day_us else day_us in
      let at=Int64.add(Int64.sub now ago)(Int64.of_int i) in
      let model,_=List.nth expected_models(i mod List.length expected_models) in
      insert db ~id:("history:"^string_of_int i) ~at ~model
    done;
    check "fixture-exact-six-model-legacy" (schema_version db=Legacy));
  path
let dump path=with_fixture path(fun db->
  rows db "SELECT * FROM reservations ORDER BY call_id" [],
  rows db "SELECT * FROM budget_meta" [])
let version path=with_fixture path schema_version
let request id model=ok(Request.make ~call_id:id ~model ~max_tokens:4096 ~input_bytes:16384 ~body_bytes:20000)
let old id=request id "moonshotai/kimi-k3"
let argon id=request id "google/gemini-4-argon"
let argon_refused=function Error(Invalid_request "argon_schema_upgrade_required")->true|_->false

let path=legacy_fixture "legacy-ten.db"
let ()=
  check "legacy-ten-cross-day-rows" (List.length(fst(dump path))=10);
  check "legacy-cross-day-two-groups" (with_fixture path(fun db->List.length(rows db "SELECT utc_day FROM reservations GROUP BY utc_day" [])=2));
  check "legacy-status-accepted" (match Persistent.observe ~now path with Ok _->true|_->false);
  let state,observation=ok(Persistent.reserve ~now path(old "old-before-upgrade")) in
  check "legacy-old-model-reserve" (state=path && observation.count=1);
  let before=dump path in
  check "legacy-Argon-explicit-upgrade-refusal" (argon_refused(Persistent.reserve ~now path(argon "argon-before")));
  check "legacy-Argon-refusal-no-mutation" (dump path=before);
  let actual,changed,totals=ok(upgrade_argon path) in
  check "upgrade-in-place" (actual=path && changed && version path=Current);
  check "upgrade-full-rows-and-meta-equality" (dump path=before);
  check "upgrade-exact-count-and-liability" (totals=[Sqlite3.Data.INT 11L;Sqlite3.Data.INT 2_750_000_000L]);
  check "upgrade-no-new-schema-objects" (with_fixture path(fun db->List.length(rows db "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'" [])=List.length schema));
  let _,changed_again,totals_again=ok(upgrade_argon path) in
  check "upgrade-idempotent" (not changed_again && totals_again=totals && dump path=before);
  let _,after_argon=ok(Persistent.reserve ~now:(Int64.add now 1L) path(argon "argon-after")) in
  check "upgraded-Argon-admitted-fixed-liability" (after_argon.count=2 && after_argon.reserved=500_000_000L);
  for i=3 to 40 do
    let _,s=ok(Persistent.reserve ~now:(Int64.add now(Int64.of_int i)) path(old("fill:"^string_of_int i))) in
    check "daily-fixed-reservation" (s.count=i && s.reserved=Int64.mul(Int64.of_int i)reservation)
  done;
  check "forty-first-blocked" (match Persistent.reserve ~now:(Int64.add now 41L) path(argon "over-cap") with Error Exhausted->true|_->false);
  check "duplicate-before-budget" (match Persistent.reserve ~now:(Int64.add now 42L) path(old "old-before-upgrade") with Error Duplicate_call_id->true|_->false);
  check "cross-day-duplicate-still-blocked" (match Persistent.reserve ~now:(Int64.add now day_us) path(old "history:0") with Error Duplicate_call_id->true|_->false);
  check "clock-rollback-still-blocked" (match Persistent.observe ~now path with Error Clock_rollback->true|_->false);
  let protected=dump path in
  with_fixture path(fun db->
    let refusal sql label=
      let rc=Sqlite3.exec db sql in
      check label (rc<>Sqlite3.Rc.OK && rc<>Sqlite3.Rc.DONE && Sqlite3.errmsg db="append_only") in
    refusal "UPDATE reservations SET amount_nd=0 WHERE call_id='history:0'" "reservation-update-blocked";
    refusal "DELETE FROM reservations WHERE call_id='history:0'" "reservation-delete-blocked";
    refusal "UPDATE budget_meta SET reservation_nd=1" "meta-update-blocked";
    refusal "DELETE FROM budget_meta" "meta-delete-blocked";
    let direct id at expected=
      try insert db ~id ~at ~model:"moonshotai/kimi-k3";false
      with Budget_error Ledger_io->Sqlite3.errmsg db=expected in
    check "SQL-cap-trigger-blocked" (direct "sql-overcap" (Int64.add now 43L) "budget_exhausted");
    check "SQL-clock-trigger-blocked" (direct "sql-clock" (Int64.sub now day_us) "clock_rollback");
    check "SQL-duplicate-trigger-blocked" (direct "history:0" (Int64.add now day_us) "duplicate_call_id"));
  check "all-denials-preserve-history" (dump path=protected)

let rollback_path=legacy_fixture "precommit-fault.db"
let ()=
  let before=dump rollback_path in
  let failed=safe_result(fun()->with_db ~write:true rollback_path(fun db->
    let changed,_=upgrade_argon_db db in
    check "precommit-fault-reached-after-rebuild" changed;
    fail Corrupt_ledger)) in
  check "injected-precommit-failure-returned" (failed=Error Corrupt_ledger);
  check "precommit-failure-restores-exact-legacy-schema" (version rollback_path=Legacy);
  check "precommit-failure-restores-all-rows-meta" (dump rollback_path=before);
  check "rollback-legacy-still-operable" (match Persistent.observe ~now rollback_path with Ok _->true|_->false)

let corrupt_path=legacy_fixture "corrupt-trigger.db"
let ()=
  with_fixture corrupt_path(fun db->exec db "DROP TRIGGER reservations_cap");
  let before=dump corrupt_path in
  check "corrupt-trigger-upgrade-denied" (upgrade_argon corrupt_path=Error Corrupt_ledger);
  check "corrupt-trigger-status-denied" (Persistent.observe ~now corrupt_path=Error Corrupt_ledger);
  check "corrupt-trigger-reserve-denied" (Persistent.reserve ~now corrupt_path(old "corrupt")=Error Corrupt_ledger);
  check "corrupt-trigger-failed-upgrade-no-row-mutation" (dump corrupt_path=before)

let extra_path=legacy_fixture "unknown-schema.db"
let ()=
  with_fixture extra_path(fun db->exec db "CREATE TABLE unapproved (x INTEGER)");
  let before=dump extra_path in
  check "extra-schema-upgrade-denied" (upgrade_argon extra_path=Error Corrupt_ledger);
  check "extra-schema-no-row-mutation" (dump extra_path=before);
  check "limit-still-ten-dollars" (daily_limit=10_000_000_000L && reservation=250_000_000L)

(* A genuine near-bound database with only ten reservations: test-only trailing
   SQL whitespace occupies schema overflow pages while String.trim still sees
   the exact six-model legacy schema. No arbitrary production schema is added.
   max_page_count bounds the initial fixture; a rebuild may allocate past that
   size after reopening because max_page_count is a connection-local limit. *)
let near_path=legacy_fixture "near-bound.db"
let ()=
  with_fixture near_path(fun db->
    let page_size=db_int (one db "PRAGMA page_size" []).(0) |> Int64.to_int in
    let maximum=max_ledger_bytes/page_size in
    exec db ("PRAGMA max_page_count="^string_of_int maximum);
    exec db "PRAGMA writable_schema=ON";
    let original=List.assoc "reservations" legacy_schema in
    let pad length=
      (* Free the previous trial's overflow chain first; otherwise replacing
         one large value with another tests transient double allocation. *)
      statement db "UPDATE sqlite_master SET sql=? WHERE name='reservations'"
        [Sqlite3.Data.TEXT original](fun stmt->sql_ok(Sqlite3.step stmt));
      let stmt=Sqlite3.prepare db "UPDATE sqlite_master SET sql=? || printf('%*s',?,'') WHERE name='reservations'" in
      Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize stmt))(fun()->
        sql_ok(Sqlite3.bind_values stmt [Sqlite3.Data.TEXT original;Sqlite3.Data.INT(Int64.of_int length)]);
        match Sqlite3.step stmt with
        | Sqlite3.Rc.DONE->true
        | Sqlite3.Rc.FULL->false
        | rc->sql_ok rc;false) in
    let rec largest low high=
      if low=high then low else
      let middle=low+(high-low+1)/2 in
      if pad middle then largest middle high else largest low (middle-1) in
    let padding=largest 0 (max_ledger_bytes-page_size) in
    check "near-bound-padding-fits" (pad padding);
    exec db "PRAGMA writable_schema=OFF";
    let pages=db_int (one db "PRAGMA page_count" []).(0) in
    Printf.printf "near_bound_initial_pages=%Ld page_size=%d padding=%d maximum_pages=%d\n%!" pages page_size padding maximum;
    check "near-bound-initial-logical-size" (pages=Int64.of_int maximum));
  let initial_size=(Unix.stat near_path).Unix.st_size in
  check "near-bound-initial-file-at-most32MiB" (initial_size<=max_ledger_bytes);
  let before=dump near_path in
  let before_schema=with_fixture near_path(fun db->rows db "SELECT name,sql FROM sqlite_master ORDER BY name" []) in
  check "near-bound-valid-exact-legacy" (version near_path=Legacy && List.length(fst before)=10);
  let rebuilt_pages=ref 0L and rebuilt_page_size=ref 0L and rebuilt_current=ref false in
  let refused=safe_result(fun()->with_db ~write:true near_path(fun db->
    try upgrade_argon_db db with Budget_error Resource_bound as error->
      rebuilt_pages:=db_int (one db "PRAGMA page_count" []).(0);
      rebuilt_page_size:=db_int (one db "PRAGMA page_size" []).(0);
      rebuilt_current:=schema_version db=Current;
      raise error)) in
  check "near-bound-refused-resource-bound" (refused=Error Resource_bound);
  check "near-bound-refusal-after-complete-current-rebuild" !rebuilt_current;
  check "near-bound-actual-rebuilt-image-over-cap" (!rebuilt_page_size>0L &&
    !rebuilt_pages>Int64.div(Int64.of_int max_ledger_bytes)!rebuilt_page_size);
  Printf.printf "near_bound_rebuilt_pages=%Ld page_size=%Ld limit_bytes=%d\n%!"
    !rebuilt_pages !rebuilt_page_size max_ledger_bytes;
  check "near-bound-rollback-all-rows-meta" (dump near_path=before);
  check "near-bound-rollback-exact-raw-schema" (with_fixture near_path(fun db->rows db "SELECT name,sql FROM sqlite_master ORDER BY name" [])=before_schema);
  check "near-bound-rollback-keeps-file-bound" ((Unix.stat near_path).Unix.st_size<=max_ledger_bytes);
  check "near-bound-rollback-legacy-status" (match Persistent.observe ~now near_path with Ok _->true|_->false);
  print_endline(Yojson.Safe.to_string(`Assoc["status",`String"PASS";"checks",`Int !checks;
    "scope",`String"private SQLite fixtures only";"fixture_dir",`String(Fpath.to_string run_dir);
    "network_calls",`Int 0;"canonical_db_writes",`Int 0]))
