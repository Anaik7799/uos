#use "topfind";;
#require "yojson,cryptokit";;
#load "unix.cma";;

let workspace = "/home/an/NAS-setup/uos/.uos-workspaces/ev98-health-formal-20260909"
let out = workspace ^ "/docs/reviews"
let exe = workspace ^ "/tools/km_provenance/_build/default/km_gate.exe"
let policy = workspace ^ "/tools/ev02_governance/policy_surface_gate.ml"
let mapping_gate = workspace ^ "/tools/ev02_governance/directive_mapping_gate.ml"
let mapping = workspace ^ "/governance/agents/policy/20260909-1836-ev02-current-directive-rule-amendment.json"
let ocamlrun = "/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocamlrun"
let ocaml = "/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocaml"
let bound = 1_048_576
let sha bytes = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) bytes |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let escape = Yojson.Safe.to_string
let read_bound channel =
  let bytes = Bytes.create bound in
  let n = Unix.read channel bytes 0 bound in
  Bytes.sub_string bytes 0 n
let run argv =
  let r,w = Unix.pipe () in
  let pid = Unix.create_process argv.(0) argv Unix.stdin w w in
  Unix.close w;
  let output = read_bound r in
  Unix.close r;
  let _, status = Unix.waitpid [] pid in
  let code = match status with Unix.WEXITED n -> n | Unix.WSIGNALED n -> 128+n | Unix.WSTOPPED n -> 256+n in
  code, output
let write path bytes = let c = open_out_bin path in Fun.protect ~finally:(fun () -> close_out_noerr c) (fun () -> output_string c bytes)
let one id expected argv =
  let exit_code, output = run argv in
  let output_path = out ^ "/20260909-1842-ev02-" ^ id ^ ".out" in
  write output_path output;
  `Assoc ["id", `String id; "argv", `List (Array.to_list argv |> List.map (fun s -> `String s));
          "exit_code", `Int exit_code; "expected_exit_code", `Int expected;
          "control_pass", `Bool (exit_code = expected); "output_path", `String output_path;
          "output_sha256", `String (sha output)]
let () =
  if Array.length Sys.argv <> 3 || Sys.argv.(1) <> "--source-commit" then
    failwith "usage: run_checks.ml --source-commit COMMIT";
  let source_commit = Sys.argv.(2) in
  let rows = [
    one "policy-selftest" 0 [|ocamlrun; ocaml; policy; "--selftest"|];
    one "policy-observation" 1 [|ocamlrun; ocaml; policy; "--observe"; workspace|];
    one "mapping-selftest" 0 [|ocamlrun; ocaml; mapping_gate; "--selftest"|];
    one "mapping-observation" 1 [|ocamlrun; ocaml; mapping_gate; "--observe"; workspace; mapping|];
    one "km-gate" 1 [|exe; "--gate"|];
    one "km-ev-selftest" 0 [|exe; "--ev-selftest"|]
  ] in
  let doc = (`Assoc ["schema", `String "uos.ev02-governance-checks/v1";
                    "authority", `String "REPORT_ONLY"; "admission", `String "NOT_GRANTED";
                    "source_commit", `String source_commit;
                    "rows", `List rows] |> Yojson.Safe.pretty_to_string) ^ "\n" in
  write (out ^ "/20260909-1842-ev02-governance-checks.json") doc
