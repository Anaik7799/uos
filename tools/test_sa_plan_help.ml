#!/usr/bin/env ocaml
#use "topfind";;
#require "unix,yojson,cryptokit,mtime.clock.os";;
(* Private process regressions: help must never open or initialize the task
   store. Existing stores, malformed help and actual claim/release are covered.
   All generated files and databases remain inside a fresh /tmp directory. *)
let root = "/home/an/NAS-setup/uos"
let workspace = Filename.dirname (Filename.dirname (Unix.realpath Sys.argv.(0)))
let tc = root ^ "/toolchains/opam-ocaml/bin/"
let temp = Filename.temp_file "uos-sa-plan-help-" ""
let () = Unix.unlink temp; Unix.mkdir temp 0o700
let read path = let ch = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
    let size = in_channel_length ch in
    if size > 4_194_304 then failwith "file bound";
    really_input_string ch size)
let hash bytes = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) bytes
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let hash_file path =
  let ch = open_in_bin path and digest = Cryptokit.Hash.sha256 () in
  Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
    let bytes = Bytes.create 65536 in
    let rec add () = let size = input ch bytes 0 (Bytes.length bytes) in
      if size > 0 then (digest#add_substring bytes 0 size; add ()) in
    add (); Cryptokit.transform_string (Cryptokit.Hexa.encode ()) digest#result)
let write path bytes =
  let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL] 0o600 in
  let ch = Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr ch) (fun () ->
    output_string ch bytes; flush ch; Unix.fsync fd)
let mono () = Mtime.Span.to_float_ns (Mtime_clock.elapsed ()) /. 1e9
let count = ref 0
let contains text part =
  let rec at index = index + String.length part <= String.length text &&
    (String.sub text index (String.length part) = part || at (index + 1)) in at 0
let environment database =
  let overrides = ["UOS_SA_PLAN_DB", database;
    "PATH", tc ^ ":" ^ root ^ "/toolchains/nix-profile/bin:/usr/bin:/bin";
    "OCAMLPATH", root ^ "/toolchains/opam-ocaml/lib";
    "DUNE_CACHE", "disabled"] in
  let inherited = Unix.environment () |> Array.to_list |> List.filter (fun entry ->
    not (List.exists (fun (key, _) -> String.starts_with ~prefix:(key ^ "=") entry) overrides)) in
  Array.of_list (List.map (fun (key, value) -> key ^ "=" ^ value) overrides @ inherited)
let run ?(seconds=60.) ~database name executable arguments =
  let output_path = temp ^ "/" ^ name ^ ".txt" in
  let fd = Unix.openfile output_path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL] 0o600 in
  let started = Unix.gettimeofday () and clock = mono () in
  let pid = Unix.fork () in
  if pid = 0 then begin
    ignore (Unix.setsid ()); Unix.chdir temp;
    Unix.dup2 fd Unix.stdout; Unix.dup2 fd Unix.stderr; Unix.close fd;
    let input = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
    Unix.dup2 input Unix.stdin; Unix.close input;
    Unix.execve executable (Array.of_list (executable :: arguments)) (environment database)
  end;
  Unix.close fd;
  let rec await () = match Unix.waitpid [Unix.WNOHANG] pid with
    | 0, _ when mono () -. clock < seconds && (Unix.stat output_path).st_size <= 4_194_304 ->
        Unix.sleepf 0.02; await ()
    | 0, _ -> Unix.kill (-pid) Sys.sigkill; ignore (Unix.waitpid [] pid);
        failwith (name ^ " exceeded process bound")
    | _, Unix.WEXITED code -> code
    | _ -> failwith (name ^ " abnormal process exit") in
  let code = await () in
  let output = read output_path in
  write (temp ^ "/" ^ name ^ ".json") (Yojson.Safe.pretty_to_string (`Assoc [
    "argv", `List (List.map (fun s -> `String s) (executable :: arguments));
    "database", `String database; "utc_started", `Float started;
    "utc_finished", `Float (Unix.gettimeofday ()); "exit_code", `Int code;
    "output", `String output; "output_sha256", `String (hash output);
    "authority", `String "NONE" ]) ^ "\n");
  code, output
let sources = ref []
let copy relative target =
  let bytes = read (workspace ^ "/" ^ relative) in
  write target bytes;
  sources := `Assoc ["path", `String relative; "sha256", `String (hash bytes)] :: !sources
let () =
  Unix.mkdir (temp ^ "/lib") 0o700; Unix.mkdir (temp ^ "/cli") 0o700;
  let base = "engines/hermes/modules/sa_plan" in
  Sys.readdir (workspace ^ "/" ^ base) |> Array.to_list |> List.sort String.compare
  |> List.iter (fun name -> if Filename.check_suffix name ".ml" || Filename.check_suffix name ".mli"
    then copy (base ^ "/" ^ name) (temp ^ "/lib/" ^ name));
  List.iter (fun name -> copy (base ^ "/test/" ^ name) (temp ^ "/cli/" ^ name))
    ["sa_plan_main.ml"; "sa_plan_cli.ml"; "sa_plan_work.ml";
     "sa_plan_manual.ml"; "journal_markdown_html.ml"; "test_sa_plan_cli.ml"];
  write (temp ^ "/dune-project") "(lang dune 3.20)\n(name ev_sa_plan_help)\n";
  write (temp ^ "/lib/dune")
    "(library (name sa_plan) (libraries core digestif sqlite3 yojson) (preprocess (pps ppx_jane)))\n";
  write (temp ^ "/cli/dune")
    "(executable (name sa_plan_main) (modules sa_plan_main sa_plan_cli sa_plan_work sa_plan_manual journal_markdown_html) (libraries bos core core_unix time_now yojson sa_plan))\n(executable (name test_sa_plan_cli) (modules test_sa_plan_cli sa_plan_cli))\n"
let checks = ref 0
let check name condition =
  if not condition then failwith ("FAIL " ^ name);
  incr checks; Printf.printf "PASS %s\n%!" name
let missing_db = temp ^ "/never-created/store.sqlite3"
let () =
  let code, output = run ~seconds:180. ~database:missing_db "build" (tc ^ "dune")
    ["build"; "--root"; temp; "-j"; "2"; "cli/sa_plan_main.exe"; "cli/test_sa_plan_cli.exe"] in
  if code <> 0 then failwith ("build: " ^ output);
  let code, _ = run ~database:missing_db "unit" (temp ^ "/_build/default/cli/test_sa_plan_cli.exe") [] in
  check "native argument regressions" (code = 0)
let executable = temp ^ "/_build/default/cli/sa_plan_main.exe"
let requests = [
  ["task"; "claim"; "--help"];
  ["task"; "claim"; "worker"; "-h"];
  ["--claim"; "--help"];
  ["task"; "claim"; "worker"; "--format"; "--help"];
  ["--format"; "json"; "task"; "claim"; "--help"];
  ["job"; "claim"; "queue"; "--help"];
  ["workflow"; "start"; "--help"];
  ["task"; "complete"; "p"; "t"; "w"; "1"; "--help"];
  ["help"; "task"]; ["--help"]; ["--version"] ]
let () = List.iteri (fun index args ->
  let code, output = run ~database:missing_db (Printf.sprintf "missing-%02d" index) executable args in
  check "help/version leave absent store and parent absent"
    (code = 0 && not (Sys.file_exists (Filename.dirname missing_db))
      && not (contains output "store_open"))) requests
let database = temp ^ "/private.sqlite3"
let must name args = let code, output = run ~database name executable args in
  if code <> 0 then failwith (name ^ ": " ^ output); output
let () =
  List.iteri (fun index args ->
    let code, output = run ~database:missing_db (Printf.sprintf "job-invalid-%02d" index) executable args in
    check "job and Oban option workers refuse before store initialization"
      (code = 2 && contains output "WORKER" && not (contains output "store_open")
        && not (Sys.file_exists (Filename.dirname missing_db))))
    [["job";"claim";"q";"--version"];["job";"run";"q";"--unknown"];
     ["oban";"claim";"q";""];["oban";"run";"q";" "];
     ["--job-claim";"q";"--unknown"]];
  ignore (must "create-plan" ["plan"; "create"; "private"; "private/help"; "Private help regression"]);
  ignore (must "create-task" ["task"; "create"; "private"; "t"; "private/help/task"; "Private task"]);
  let before = hash (read database) in
  List.iteri (fun index args ->
    let code, output = run ~database (Printf.sprintf "existing-%02d" index) executable args in
    check "help/version leave existing database bytes unchanged"
      (code = 0 && hash (read database) = before && not (contains output "store_open"))) requests;
  let state = must "available" ["--format"; "json"; "task"; "show"; "private"; "t"] in
  check "help did not claim private task" (contains state "\"state\":\"available\"" && contains state "\"attempt\":\"0\"");
  let invalid_code, invalid_output = run ~database:missing_db "invalid-worker" executable
    ["task"; "claim"; "--unknown"] in
  check "option worker refuses before store initialization"
    (invalid_code = 2 && contains invalid_output "WORKER" && not (Sys.file_exists (Filename.dirname missing_db)));
  let claimed = must "positive-claim" ["task"; "claim"; "private-worker"; "private"; "60000000000"; "t"] in
  check "explicit claim still executes in private database" (contains claimed "claimed=true" && contains claimed "attempt=1");
  ignore (must "positive-release" ["task"; "release"; "private"; "t"; "private-worker"; "1"]);
  let state = must "released" ["--format"; "json"; "task"; "show"; "private"; "t"] in
  check "fenced private release restores available state" (contains state "\"state\":\"available\"" && contains state "\"attempt\":\"1\"");
  ignore (must "enqueue-private-job" ["job";"enqueue";"j";"private/help/job";"q";"worker";"{}"]);
  let before = hash (read database) in
  let invalid_code, _ = run ~database "existing-job-invalid" executable ["oban";"run";"q";"--version"] in
  check "invalid job worker leaves an existing queued job unchanged" (invalid_code = 2 && hash (read database) = before);
  let claimed = must "positive-job-claim" ["job";"claim";"q";"private-worker"] in
  check "ordinary private job claim remains executable" (contains claimed "lease_owner=private-worker" && contains claimed "attempt=1");
  write (temp ^ "/source-observation.json") (Yojson.Safe.pretty_to_string (`Assoc [
    "sources", `List (List.rev !sources); "checks_passed", `Int !checks;
    "executable_sha256", `String (hash_file executable); "authority", `String "NONE";
    "scope", `String "Private CLI behavior; no live binary replacement" ]) ^ "\n");
  Printf.printf "%d checks passed; private evidence %s\n" !checks temp
