#!/usr/bin/env -S opam exec -- ocaml
#use "product_catalog.ml";;
(* Transaction, hostile-input and history tests against an isolated database.
   No production catalog or Sa-plan task is modified by this test file. *)
let count = ref 0
let check name f = f (); incr count; Printf.printf "ok %s\n" name
let rejects f = try f (); false with Failure _ | Sqlite3.Error _ -> true
let set k v = function `Assoc xs -> `Assoc ((k,v)::List.remove_assoc k xs) | _ -> fail "not object"
let fixture () =
  `Assoc ["schema",`String "uos.product-catalog/v1";
    "specification",`Assoc ["id",`String "test";"revision",`String "v1";"title",`String "O'Brien; DROP TABLE sentinel;";
      "created_at",`String "2026-09-07T19:00:00Z";"sa_plan_plan",`String "isolated";"admission_status",`String "NOT_ADMITTED"];
    "features",`List [`Assoc ["id",`String "f1";"name",`String "Feature";"category",`String "test";
      "status",`String "MAPPED";"use_case",`String "Test";"gap",`String "Runtime UNRUN";
      "implementation",`String "Native";"mappings",`List [];"oracle_ids",`List [];
      "requirements",`List [`Assoc ["id",`String "r1";"shall",`String "Shall preserve history"]];
      "acceptance",`List [`Assoc ["id",`String "a1";"assertion",`String "Reject conflict";"status",`String "UNRUN"]]]];
    "oracles",`List [];"findings",`List [];
    "artifacts",`List [`Assoc ["id",`String "doc";"revision",`String "1";"kind",`String "user_source";
      "locator",`String "input";"content",`String "O'Brien\nsource";"sha256",`String (sha "O'Brien\nsource")]];
    "artifact_links",`List [`Assoc ["artifact_id",`String "doc";"artifact_revision",`String "1";"role",`String "source"]]]
let () =
  let path = Filename.temp_file "uos-product-test-" ".sqlite3" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    with_db ~readonly:false path (fun db ->
      exec db "CREATE TABLE sentinel(value TEXT); INSERT INTO sentinel VALUES('preserve me')";
      let j = fixture () in
      check "first import and SQL metacharacters" (fun () -> import db j ~authorize:(fun () -> ());
        require (query db "SELECT value FROM sentinel" [] = [[s "preserve me"]]) "sentinel changed");
      check "identical replay is idempotent" (fun () -> import db j ~authorize:(fun () -> ());
        require (query db "SELECT count(*) FROM product_features" [] = [[Sqlite3.Data.INT 1L]]) "duplicate feature");
      check "conflicting version rejected" (fun () ->
        let changed = set "specification" (set "title" (`String "changed") (member "specification" j)) j in
        require (rejects (fun () -> import db changed ~authorize:(fun () -> ()))) "conflict accepted");
      check "artifact tampering rejected" (fun () ->
        let a = List.hd (items "artifacts" j) |> set "content" (`String "tampered") in
        require (rejects (fun () -> validate (set "artifacts" (`List [a]) j))) "tamper accepted");
      check "dangling oracle rejected" (fun () ->
        let f = List.hd (items "features" j) |> set "oracle_ids" (`List [`String "missing"]) in
        require (rejects (fun () -> validate (set "features" (`List [f]) j))) "dangling accepted");
      check "catalog cannot fabricate acceptance pass" (fun () ->
        let f = List.hd (items "features" j) in
        let a = List.hd (items "acceptance" f) |> set "status" (`String "PASS") in
        let f = set "acceptance" (`List [a]) f in
        require (rejects (fun () -> validate (set "features" (`List [f]) j))) "pass accepted");
      check "empty product rejected" (fun () ->
        require (rejects (fun () -> validate (set "features" (`List []) j))) "empty accepted");
      check "duplicate JSON keys rejected" (fun () ->
        require (rejects (fun () -> ignore (canonical (`Assoc ["x",`Int 1;"x",`Int 2])))) "duplicate accepted");
      check "direct history update rejected" (fun () ->
        require (rejects (fun () -> exec db "UPDATE product_artifacts SET content='corrupt'")) "update accepted");
      check "direct history deletion rejected" (fun () ->
        require (rejects (fun () -> exec db "DELETE FROM product_features")) "delete accepted");
      check "lease loss rolls back entire import" (fun () ->
        let calls = ref 0 in
        let changed = set "specification" (set "revision" (`String "v2") (member "specification" j)) j in
        let authorize () = incr calls; if !calls = 2 then fail "lease lost" in
        require (rejects (fun () -> import db changed ~authorize)) "late failure ignored";
        require (query db "SELECT count(*) FROM product_specifications" [] = [[Sqlite3.Data.INT 1L]]) "partial write survived");
      check "artifact round trip preserves bytes" (fun () ->
        require (query db "SELECT content,sha256 FROM product_artifacts" [] = [[s "O'Brien\nsource";s (sha "O'Brien\nsource")]]) "roundtrip mismatch");
      check "relational projections and integrity" (fun () ->
        require (query db "SELECT requirement FROM product_requirement_list" [] = [[s "Shall preserve history"]]) "bad requirement";
        require (query db "PRAGMA integrity_check" [] = [[s "ok"]]) "integrity";
        require (query db "PRAGMA foreign_key_check" [] = []) "foreign keys");
      let updated = List.hd (items "artifacts" j) |> set "revision" (`String "2")
        |> set "content" (`String "new version") |> set "sha256" (`String (sha "new version")) in
      let packet = `Assoc ["schema",`String "uos.product-artifact-append/v1";
        "spec_id",`String "test";"revision",`String "v1";"sa_plan_plan",`String "isolated";
        "artifacts",`List [updated]] in
      check "external source bytes cannot enter reference artifacts" (fun () ->
        require (rejects (fun () -> validate_artifact (set "kind" (`String "external-source-reference") updated)))
          "external source body accepted");
      check "artifact append preserves both versions and replays once" (fun () ->
        append_artifacts db packet ~authorize:(fun () -> ());
        append_artifacts db packet ~authorize:(fun () -> ());
        require (query db "SELECT revision,content FROM product_artifacts ORDER BY revision" [] =
          [[s "1";s "O'Brien\nsource"];[s "2";s "new version"]]) "artifact history lost");
      check "artifact cannot cross plan authority" (fun () ->
        require (rejects (fun () -> append_artifacts db (set "sa_plan_plan" (`String "wrong") packet)
          ~authorize:(fun () -> ()))) "wrong plan accepted");
      check "artifact append rolls back after ownership loss" (fun () ->
        let calls = ref 0 in
        let packet = set "artifacts" (`List [set "revision" (`String "3") updated]) packet in
        let authorize () = incr calls; if !calls = 2 then fail "lease lost" in
        require (rejects (fun () -> append_artifacts db packet ~authorize)) "late append failure ignored";
        require (query db "SELECT count(*) FROM product_artifacts" [] = [[Sqlite3.Data.INT 2L]]) "append partially committed")));
  Printf.printf "product-catalog tests: %d passed\n" !count
