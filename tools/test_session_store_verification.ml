#use "topfind";;
#require "unix,yojson,cryptokit,sqlite3";;

(* Native bounded private verification: no live journal/database is an input.
   The reviewed adapter bounds child runtime, output and receipt persistence. *)
let root = "/home/an/NAS-setup/uos"
let workspace = Sys.getcwd ()
let adapter = workspace ^ "/tools/ev_native.ml"
let ocaml = root ^ "/toolchains/opam-ocaml/bin/ocaml"
let ocamlrun = root ^ "/toolchains/opam-ocaml/bin/ocamlrun"
let read p = let ch = open_in_bin p in
  Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
    let n = in_channel_length ch in if n > 4_194_304 then failwith "file bound";
    really_input_string ch n)
let hash text = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) text
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let write path bytes =
  let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL] 0o600 in
  let ch = Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr ch) (fun () ->
    output_string ch bytes; flush ch; Unix.fsync fd)
let directory = Filename.temp_dir "uos-store-verification-run-" ""
let package = directory ^ "/package"
let built = directory ^ "/compiled"
let manifests = ref []
let record relative bytes = manifests := (relative, hash bytes) :: !manifests
let rec copy_sources relative destination =
  Unix.mkdir destination 0o700;
  Sys.readdir (workspace ^ "/" ^ relative) |> Array.to_list |> List.sort String.compare
  |> List.iter (fun name ->
    let rel = relative ^ "/" ^ name in
    let stat = Unix.lstat (workspace ^ "/" ^ rel) in
    match stat.Unix.st_kind with
    | Unix.S_DIR -> copy_sources rel (destination ^ "/" ^ name)
    | Unix.S_REG when Filename.check_suffix name ".gleam" || Filename.check_suffix name ".erl" ->
      let bytes = read (workspace ^ "/" ^ rel) in record rel bytes;
      write (destination ^ "/" ^ name) bytes
    | _ -> ())
let command label expect tool_args =
  let receipt = directory ^ "/" ^ label ^ ".json" in
  let argv = [ocamlrun; ocaml; adapter; "--cwd"; directory; "--seconds"; "60";
    "--receipt"; receipt; "--"] @ tool_args in
  let child = Unix.create_process ocamlrun (Array.of_list argv)
    Unix.stdin Unix.stdout Unix.stderr in
  let _, status = Unix.waitpid [] child in
  let code = match status with Unix.WEXITED n -> n | _ -> 125 in
  Printf.printf "%s: observed=%d expected=%d\n%!" label code expect;
  if code <> expect then failwith ("unexpected process outcome: " ^ label);
  Yojson.Safe.from_file receipt
let old_tests = [
  "open_creates_schema_and_meta_test";
  "open_refuses_incompatible_schema_marker_test";
  "append_round_trip_matches_direct_apply_oracle_test";
  "duplicate_operation_id_returns_duplicate_true_and_no_new_row_test";
  "raw_update_and_delete_are_rejected_by_triggers_test";
  "insert_or_replace_cannot_delete_history_test";
  "raw_insert_with_wrong_sequence_or_wrong_previous_digest_is_rejected_test";
  "verify_passes_on_a_good_store_test";
  "verify_reports_the_exact_failure_on_a_tampered_copy_test";
  "migrate_from_journal_replay_verify_and_export_parity_test";
  "migration_refuses_a_non_empty_store_test"]
let beam args = ["beam"; built] @ args
let sql path statement =
  let db = Sqlite3.db_open path in
  let result = Sqlite3.exec db statement in
  let closed = Sqlite3.db_close db in
  if result <> Sqlite3.Rc.OK || not closed then failwith "private fixture SQL failed"
let () =
  Printf.printf "PRIVATE_EVIDENCE=%s\n%!" directory;
  Unix.mkdir package 0o700;
  copy_sources "apps/uos_swarm/src" (package ^ "/src");
  let manifest = read (workspace ^ "/apps/uos_swarm/gleam.toml") in
  record "apps/uos_swarm/gleam.toml" manifest;
  write (package ^ "/gleam.toml")
    (String.split_on_char '\n' manifest |> List.filter ((<>) "[dev-dependencies]") |> String.concat "\n");
  List.iter (fun name ->
    let relative = "apps/uos_swarm/test/" ^ name in
    let bytes = read (workspace ^ "/" ^ relative) in record relative bytes;
    write (package ^ "/src/" ^ name) bytes)
    ["session_store_test.gleam"; "session_store_test_ffi.erl"; "session_store_verification_test.gleam"];
  write (package ^ "/src/ev_store_verification_runner.gleam")
    ("import session_store_test\nimport session_store_verification_test\nimport gleam/io\npub fn main() {\n"
     ^ String.concat "" (List.map (fun test -> "  let _ = session_store_test." ^ test ^ "()\n") old_tests)
     ^ "  session_store_verification_test.main()\n  io.println(\"20 store verification cases passed\")\n}\n");
  ignore (command "compile" 0 ["gleam"; "compile-package"; "--target"; "erlang";
    "--package"; package; "--out"; built; "--lib"; root ^ "/apps/uos_swarm/build/dev/erlang"]);
  ignore (command "unit-tests" 0 (beam ["ev_store_verification_runner"]));
  let cli label expect args = command label expect (beam ("session_store_cli" :: args)) in
  let db = directory ^ "/cli.sqlite3" in
  ignore (cli "cli-register" 0 [db; "register"; "codex-fixture"; "codex";
    directory; "private-fixture"; "-"; "op-register"]);
  ignore (cli "cli-valid" 0 ["verify"; db]);
  let before = hash (read db) in
  ignore (cli "cli-valid-unchanged" 0 ["verify"; db]);
  assert (before = hash (read db));
  sql db "DROP TRIGGER events_no_update; UPDATE events SET body_json = body_json || ' ' WHERE sequence = 1;";
  let before = hash (read db) in
  let tampered = cli "cli-tampered" 1 ["verify"; db] in
  assert (before = hash (read db));
  let output = Yojson.Safe.Util.(member "output" tampered |> to_string) in
  let report = Yojson.Safe.from_string (String.trim output) in
  assert (Yojson.Safe.Util.member "digest_ok" report = `Bool false);
  assert (Yojson.Safe.Util.member "triggers_present" report = `Bool false);
  let absent = directory ^ "/absent.sqlite3" in
  ignore (cli "cli-absent" 1 ["verify"; absent]); assert (not (Sys.file_exists absent));
  let empty = directory ^ "/empty.sqlite3" in write empty "";
  ignore (cli "cli-empty" 1 ["verify"; empty]); assert (read empty = "");
  List.iter (fun (relative, digest) ->
    assert (hash (read (workspace ^ "/" ^ relative)) = digest)) !manifests;
  write (directory ^ "/source-manifest.json")
    (Yojson.Safe.pretty_to_string (`Assoc ["authority", `String "NONE";
      "scope", `String "Private component and process verification; no live cutover or admission";
      "observed_at_unix", `Float (Unix.gettimeofday ());
      "unit_tests_passed", `Int 20; "cli_process_cases_passed", `Int 6;
      "source_manifest", `List (List.map (fun (path, digest) ->
        `Assoc ["path", `String path; "sha256", `String digest]) !manifests)]));
  Printf.printf "VERIFIED_PRIVATE_EVIDENCE=%s\n%!" directory
