#use "topfind";;
#require "bos,unix,yojson,cryptokit";;

(* Native, private EV107 component campaign. Caller selects only workspace and
   immutable revision. Recipes and disagreement controls are fixed below.
   This observes local comparisons; it grants no dispatch or admission authority. *)
let root = "/home/an/NAS-setup/uos"
let adapter = root ^ "/.uos-workspaces/codex-ev-admission-20260909-0210/tools/ev_native.ml"
let tc = root ^ "/toolchains/opam-ocaml/bin/"
let jj = "/nix/store/vzrnnii3369cn2a2bgdlkx9gh6m297fj-jujutsu-0.44.0/bin/jj"
let baseline = "52e013cfe8c32d6c8d4353c27cfdf0a23f225124"
let scope = "engines/hermes/modules/system_engg/"
let files = ["gospel_dispatch_contracts.ml"; "gospel_dispatch_contracts.mli"; "test_gospel_dispatch_contracts.ml"]
let read p = let c = open_in_bin p in Fun.protect ~finally:(fun () -> close_in_noerr c) (fun () -> really_input_string c (in_channel_length c))
let write p b = let c = open_out_bin p in Fun.protect ~finally:(fun () -> close_out_noerr c) (fun () -> output_string c b)
let sha b = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) b |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let require b message = if not b then failwith message
let text s = `String s
let list xs = `List xs
let field k j = Yojson.Safe.Util.member k j
let value j = Yojson.Safe.Util.to_string j
let bindings = ref []
let bind kind path = let hash = sha (read path) in
 bindings := `Assoc ["kind",text kind;"path",text path;"sha256",text hash] :: !bindings; hash
let native args = Bos.Cmd.(v (tc^"ocamlrun") % (tc^"ocaml") % adapter %% of_list args)
let invoke cmd = match Bos.OS.Cmd.run_status cmd with
 | Ok (`Exited code) -> code | Ok (`Signaled signal) -> failwith ("child signal "^string_of_int signal)
 | Error (`Msg message) -> failwith message
let output cmd = match Bos.OS.Cmd.run_out cmd |> Bos.OS.Cmd.out_string ~trim:false with
 | Ok (bytes, (_,`Exited 0)) -> bytes
 | _ -> failwith "immutable JJ read failed"
let revision workspace rev =
 require (String.length rev = 40 && String.for_all (function '0'..'9'|'a'..'f' -> true|_->false) rev) "full commit ID required";
 let expression = "commit_id(\""^rev^"\")" in
 let actual = output Bos.Cmd.(v jj % "--ignore-working-copy" % "-R" % workspace % "log" % "-r" % expression % "--no-graph" % "-T" % "self.commit_id()") |> String.trim in
 require (actual=rev) "exact commit ID mismatch"; expression
let source workspace rev name = output Bos.Cmd.(v jj % "--ignore-working-copy" % "-R" % workspace % "file" % "show" % "-r" % rev % ("root:"^scope^name))
let replace_once bytes needle replacement =
 let occurrences = ref [] in
 for i=0 to String.length bytes - String.length needle do
  if String.sub bytes i (String.length needle)=needle then occurrences:=i::!occurrences
 done;
 match !occurrences with
 | [i] -> String.sub bytes 0 i ^ replacement ^ String.sub bytes (i+String.length needle) (String.length bytes-i-String.length needle)
 | _ -> failwith "mutation anchor must occur exactly once"
let probe payload = Printf.sprintf
 "let () = let payload = %S in let expected = Gospel_dispatch_contracts.sha256_digest payload in match Gospel_dispatch_contracts.bounded_differential_oracle payload expected with Error _ -> print_endline \"DESIGNATED_DISAGREEMENT_REFUSED\" | Ok _ -> failwith \"DESIGNATED_DISAGREEMENT_ACCEPTED\"\n" payload
let dune_recipe = "(executable (name test_gospel_dispatch_contracts) (modules gospel_dispatch_contracts test_gospel_dispatch_contracts) (libraries unix str cryptokit))\n"
let controls = [
 "primary_digest", "digest = sha256_digest payload;\n      timestamp = get_iso_timestamp ();", "digest = String.make 64 '0';\n      timestamp = get_iso_timestamp ();", "abc", 2;
 "reference_digest", "Pass { digest = sha256_digest payload; timestamp = \"REF_OK\" }", "Pass { digest = String.make 64 '0'; timestamp = \"REF_OK\" }", "abc", 2;
 "rejection_code", "FailClosed { reason = \"RefOracle: NUL byte\"; error_code = -2 }", "FailClosed { reason = \"RefOracle: NUL byte\"; error_code = -3 }", "\x00", 0;
 "verdict_kind", "Pass { digest = sha256_digest payload; timestamp = \"REF_OK\" }", "FailClosed { reason = \"Designated reference disagreement\"; error_code = -3 }", "abc", 0;
]
let () =
 require (Array.length Sys.argv=3) "usage: ocamlrun ocaml test_ev107_digest.ml WORKSPACE FULL_REVISION";
 let workspace = Sys.argv.(1) and candidate = Sys.argv.(2) in
 let target = Filename.temp_dir "uos-ev107-digest-" "" in
 print_endline ("ARTIFACTS "^target);
 let before_adapter = bind "native_adapter" adapter in
 List.iter (fun p -> ignore(bind "tool" p)) [jj;tc^"ocamlrun";tc^"ocaml";tc^"ocamlopt";tc^"dune"];
 let current = revision workspace candidate and old = revision workspace baseline in
 let helper_bytes = output Bos.Cmd.(v jj % "--ignore-working-copy" % "-R" % workspace % "file" % "show" % "-r" % current % "root:tools/test_ev107_digest.ml") in
 require (helper_bytes = read Sys.argv.(0)) "executed driver differs from candidate bytes";
 ignore(bind "candidate_driver" Sys.argv.(0));
 let acceptance = source workspace current "test_gospel_dispatch_contracts.ml" in
 let invocations = ref [] in
 let run id implementation mutation expected_exit =
  let directory = target^"/"^id in Unix.mkdir directory 0o700;
  List.iter (fun name ->
   let bytes = if name="test_gospel_dispatch_contracts.ml" then
      (match mutation with None->acceptance | Some (_,_,payload)->probe payload)
    else source workspace implementation name in
   let bytes = match name,mutation with "gospel_dispatch_contracts.ml",Some (needle,replacement,_) -> replace_once bytes needle replacement | _ -> bytes in
   let path = directory^"/"^name in write path bytes; ignore(bind "staged_source" path)) files;
  write (directory^"/dune-project") "(lang dune 3.0)\n(name ev107_digest_probe)\n";
  write (directory^"/dune") dune_recipe;
  List.iter (fun p->ignore(bind "build_recipe" (directory^"/"^p))) ["dune";"dune-project"];
  let build = directory^"/build" and receipt = directory^"/compile.json" in
  let code = invoke (native ["--cwd";directory;"--seconds";"60";"--receipt";receipt;"--";"dune";"build";"--root";directory;"--build-dir";build;"test_gospel_dispatch_contracts.exe"]) in
  ignore(bind "compile_receipt" receipt); require (code=0) (id^": compile failed, not a semantic result");
  let executable = build^"/default/test_gospel_dispatch_contracts.exe" in ignore(bind "native_test_executable" executable);
  let receipt = directory^"/run.json" in
  let code = invoke (native ["--cwd";directory;"--seconds";"60";"--receipt";receipt;"--";"native";executable]) in
  ignore(bind "execution_receipt" receipt);
  let observation = Yojson.Safe.from_file receipt in
  require (field "failure" observation=`Null) (id^": abnormal outcome");
  require (field "kind" (field "child_termination" observation)=text "EXITED") (id^": not a normal exit");
  require (code=expected_exit) (id^": unexpected semantic outcome");
  let transcript = value (field "output" observation) in
  let contains needle = let n=String.length needle in
   let rec search i = i+n<=String.length transcript && (String.sub transcript i n=needle || search(i+1)) in search 0 in
  require (match mutation with
    | None -> contains (if expected_exit=0 then "SUMMARY total=18 failed=0" else "SUMMARY total=18 failed=11")
    | Some _ -> contains (if expected_exit=0 then "DESIGNATED_DISAGREEMENT_REFUSED" else "DESIGNATED_DISAGREEMENT_ACCEPTED")) (id^": designated assertion absent");
  invocations := `Assoc ["id",text id;"implementation_revision",text (if implementation=current then candidate else baseline);"acceptance_revision",text candidate;"expected_exit",`Int expected_exit;"actual_exit",`Int code;"receipt",text receipt] :: !invocations
 in
 run "baseline_expected_digest_red" old None 1;
 run "candidate_positive" current None 0;
 List.iter (fun (name,needle,replacement,payload,baseline_exit) ->
  run ("baseline_"^name) old (Some(needle,replacement,payload)) baseline_exit;
  run ("candidate_"^name) current (Some(needle,replacement,payload)) 0) controls;
 require (before_adapter=sha(read adapter)) "adapter changed during observations";
 List.iter (fun binding -> let path=value(field "path" binding) and expected=value(field "sha256" binding) in require (sha(read path)=expected) ("artifact changed: "^path)) !bindings;
 let clock = Unix.gmtime (Unix.gettimeofday ()) in
 let stamp = Printf.sprintf "%04d%02d%02d-%02d%02d" (clock.tm_year+1900) (clock.tm_mon+1) clock.tm_mday clock.tm_hour clock.tm_sec in
 let manifest = target^"/"^stamp^"-ev107-digest-verification.json" in
 Yojson.Safe.to_file manifest (`Assoc ["schema",text "uos.ev107.digest-campaign.v1";"authority",text "NONE";"candidate",text candidate;"baseline",text baseline;"positive_cases",`Int 18;"baseline_expected_digest_failures",`Int 11;"disagreement_pairs",`Int 4;"invocations",list(List.rev !invocations);"bindings",list(List.rev !bindings);"limits",list(List.map text ["Private component tests only; no runtime dispatch, Rete, solver or admission";"Shared digest/SQL helpers are not independently verified";"Inherited linker paths are not a hermetic release closure";"Local host and pinned tool execution assume a cooperative filesystem"])]);
 print_endline ("PASS MANIFEST "^manifest^" SHA256 "^sha(read manifest))
