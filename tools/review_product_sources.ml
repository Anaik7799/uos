#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup,yojson,sqlite3,cryptokit";;
(* @agent_intent: Read-only source and schema survey. Only metadata and
   generated observations enter UOS; no external code or live DB is copied.
   @laws: explicit paths; bounded reads; no secret/config/DB hashing; failures
   stay unavailable; dirty repositories are observations, never frozen pins. *)
let stamp = "20260907-1837"
let utc () = let t = Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (t.tm_year+1900) (t.tm_mon+1) t.tm_mday t.tm_hour t.tm_min t.tm_sec
let s x = `String x
let read path = match Bos.OS.File.read (Fpath.v path) with Ok s -> s | Error (`Msg e) -> failwith e
let sha content = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) content |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let run args = Bos.OS.Cmd.run_out (Bos.Cmd.of_list ("timeout"::"15"::args)) |> Bos.OS.Cmd.out_string
let observed args = match run args with Ok (v,(_,`Exited 0)) -> Some (String.trim v) | _ -> None
let opt = function Some v -> s v | None -> `Null
let zig = "/home/an/dev/ver/zigvm"
let harness = "/home/an/dev/ver/harness-bionic"
let zig_paths = [
 "harness/infranodus_feature.ml";"harness/infranodus_feature.mli";"harness/test_infranodus_feature.ml";
 "harness/infranodus_scenario.ml";"harness/infranodus_artifacts.ml";"harness/docs_wiki.ml";
 "harness/otp_oracle.ml";"harness/oracle_vectors.ml";"harness/oracle_vectors_laws.ml";
 "harness/erl_tests.ml";"harness/evidence_census.ml";"harness/graph_revision.ml";
 "harness/gospel_contract_registry.ml";"harness/gospel_contract_registry.mli";"harness/gospel_contract_runner.ml";
 "harness/db.ml";"harness/db.mli";"harness/sa_plan_preflight.ml";"harness/sa_plan_preflight.mli";
 "harness/sa_plan/sa_plan_store.ml";"harness/sa_plan/sa_plan_control_plane.ml";
 "harness/sa_plan/sa_plan_control_plane_oracle.ml";"harness/zigvm_harness.ml";
 "harness/playwright_authority.ml";"harness/playwright_source_ontology.ml";
 "harness/fractal_closure.ml";"harness/fractal_closure_registry.ml";
 "harness/journal_bundle.ml";"harness/journal_bundle_transaction.ml";
 "harness/replay_control.ml";"harness/solver_sandbox.ml";
 "docs/zk/episodic/zk-feature-db.md";"docs/zk/episodic/zk-feature-algebra.md"]
let harness_paths = List.map (fun p -> "modules/hermes_harness/" ^ p) [
 "feature_catalog.ml";"capability_catalog.ml";"contract_catalog.ml";"fractal_catalog.ml";
 "fractal_parity.ml";"fractal_ontology.ml";"evidence_store.ml";"evidence_rollup.ml";
 "evidence_import.ml";"parity_tracker.ml";"parity_algebra.ml";"parity_normalizer.ml";
 "parity_compare.ml";"reference_capture.ml";"reference_artifacts.ml";"inventory.ml";
 "bootstrap.ml";"blueprint.ml";"blueprint.mli";"harness_config.ml";"gap_plan.ml";
 "converge.ml";"formal_coverage.ml";"runtime_coverage.ml";"receipt_reliability.ml";
 "parity_ledger.ml";"orientation_history.ml";"resource_envelope.ml";
 "test_evidence_store.ml";"test_fractal_catalog.ml";"test_fractal_parity.ml";
 "test_reference_capture.ml";"test_parity_compare.ml";"test_evidence_rollup.ml"] @ [
 "modules/hermes_wiki/src/register/feature_register.ml";"modules/hermes_wiki/src/register/feature_register.mli";
 "modules/hermes_wiki/src/register/feature_register.gospel";"modules/hermes_wiki/src/mbse/feature_model.ml";
 "modules/hermes_wiki/src/mbse/feature_model.mli";"modules/hermes_wiki/src/tools/gen_feature_model.ml";
 "modules/hermes_wiki/test/test_feature_model.ml";"modules/hermes_wiki/src/engine/wiki_datastore.ml";
 "modules/sa_plan/sa_plan_store.ml";"modules/sa_plan/sa_plan_management.ml";
 "modules/sa_plan/sa_plan_temporal.ml";"modules/sa_plan/sa_plan_oban.ml";
 "modules/hermes_ops_dashboard/run_model.ml";"modules/hermes_ops_dashboard/run_assurance.ml";
 "docs/hermes/product-feature-tracking.md";"docs/hermes/feature-ontology.md"]
let inspect root relative =
  let path = root ^ "/" ^ relative in
  if not (Sys.file_exists path) then `Assoc ["locator",s path;"status",s "ABSENT"] else
  let body = read path in
  let local = if root = harness && String.starts_with ~prefix:"modules/" relative
    then "engines/hermes/" ^ relative else
    if root = zig && String.starts_with ~prefix:"harness/" relative then
      "engines/hermes/modules/hermes_wiki/import/zigvm/code/infranodus/" ^ Filename.basename relative
    else "" in
  let counterpart = if local <> "" && Sys.file_exists local then
    let digest = sha (read local) in `Assoc ["path",s local;"sha256",s digest;
      "relation",s (if digest = sha body then "BYTE_IDENTICAL" else "ADAPTED_OR_DIVERGED")]
    else `Null in
  `Assoc ["locator",s path;"relative_path",s relative;"status",s "SOURCE_OBSERVED";
    "sha256",s (sha body);"bytes",`Int (String.length body);
    "lines",`Int (List.length (String.split_on_char '\n' body));"uos_counterpart",counterpart]
let root_observation root paths =
  let head = observed ["git";"-C";root;"rev-parse";"HEAD"] in
  let dirty = observed ["git";"-C";root;"status";"--porcelain=v1";"--untracked-files=no"] in
  `Assoc ["root",s root;"head",opt head;"tracked_dirty_path_count",(match dirty with
    | None -> `Null | Some "" -> `Int 0 | Some d -> `Int (List.length (String.split_on_char '\n' d)));
    "writers_quiesced",`Bool false;"admission",s "READ_ONLY_NOT_INGESTED";
    "files",`List (List.map (inspect root) paths)]
let db_observation path =
  if not (Sys.file_exists path) then `Assoc ["path",s path;"status",s "ABSENT"] else
  try
    let db = Sqlite3.db_open ~mode:`READONLY path in
    Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () ->
      Sqlite3.busy_timeout db 750;
      let check rc = if rc <> Sqlite3.Rc.OK then failwith (Sqlite3.errmsg db) in
      check (Sqlite3.exec db "PRAGMA query_only=ON"); check (Sqlite3.exec db "BEGIN");
      let tables = ref [] in
      check (Sqlite3.exec db ~cb:(fun row _ -> match row.(0) with Some name -> tables := name::!tables | _ -> ())
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
      let selected = List.filter (fun n -> List.mem n ["feature_catalog";"feature_history";"source_snapshot";
        "fractal_node";"artifact_catalog";"capability_contract";"capability_contract_receipt";
        "parity_scenario";"parity_trace_pair";"parity_verification";"sa_plan_plan";"sa_plan_task";
        "otp_pin";"otp_pins";"compat_verdicts";"compat_baselines";"harness_runs"] ) !tables in
      let counts = List.map (fun name ->
        let count = ref `Null in
        check (Sqlite3.exec db ~cb:(fun row _ -> match row.(0) with
          Some v -> count := `Int (int_of_string v) | None -> ()) ("SELECT count(*) FROM " ^ name));
        name,!count) selected in
      check (Sqlite3.exec db "ROLLBACK");
      `Assoc ["path",s path;"mode",s "READONLY";"table_count",`Int (List.length !tables);
        "tables",`List (List.map s (List.rev !tables));"selected_row_counts",`Assoc counts;
        "scope",s "Schema names and aggregate counts only; no DB bytes copied or hashed; counts confer no verification."])
  with exn -> `Assoc ["path",s path;"status",s "UNAVAILABLE";"error",s (Printexc.to_string exn)]
let oracle_observation o =
  let open Yojson.Basic.Util in
  let get k = o |> member k |> to_string in
  let locator = get "locator" in
  let head = observed ["git";"-C";locator;"rev-parse";"HEAD"] in
  let license = locator ^ "/" ^ get "license_file" in
  let license_hash = if Sys.file_exists license then Some (sha (read license)) else None in
  let dirty = observed ["git";"-C";locator;"status";"--porcelain=v1";"--untracked-files=no"] in
  `Assoc (("id",s (get "name"))::("observed_head",opt head)::("observed_license_sha256",opt license_hash)::
    ("working_tree_clean",`Bool (dirty = Some ""))::
    ("pin_status",s (if head = Some (get "head") && license_hash = Some (get "license_sha256") && dirty = Some ""
      then "PIN_METADATA_MATCH" else "NEEDS_EVIDENCE"))::
    ("execution_status",s "UNRUN")::(match o with `Assoc fields -> fields | _ -> []))
let () =
  let oracles = Yojson.Basic.from_string (read "governance/sources/20260907-1756-agentic-infra-third-party-oracle-registry.json")
    |> Yojson.Basic.Util.member "oracles" |> Yojson.Basic.Util.to_list |> List.map oracle_observation in
  let report = `Assoc ["schema",s "uos.product-source-review/v1";"observed_at",s (utc ());
    "scope",s "Product/specification/feature/oracle management source and metadata; no external source execution or admission.";
    "sources",`List [root_observation zig zig_paths;root_observation harness harness_paths];
    "oracles",`List oracles;
    "databases",`List (List.map db_observation [zig^"/harness/state/zigvm_harness.sqlite3";
      zig^"/harness/state/sa_plan.sqlite3";harness^"/state/evidence_store.sqlite";
      harness^"/state/hermes_harness.sqlite3";harness^"/state/evidence.sqlite";harness^"/state/sa_plan.sqlite3"])] in
  let output = "docs/reviews/" ^ stamp ^ "-product-management-source-observations.json" in
  match Bos.OS.File.write (Fpath.v output) (Yojson.Basic.pretty_to_string report ^ "\n") with
  | Ok () -> Printf.printf "saved=%s sources=2 scoped_files=%d oracles=%d\n" output
      (List.length zig_paths + List.length harness_paths) (List.length oracles)
  | Error (`Msg e) -> prerr_endline e; exit 1
