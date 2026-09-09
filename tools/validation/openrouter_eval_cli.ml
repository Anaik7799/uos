open Openrouter_eval_expr
open Openrouter_eval_catalog
open Openrouter_eval_validate
module Native=Openrouter_eval_native
let source_files=["openrouter_eval_expr.mli";"openrouter_eval_expr.ml";"openrouter_eval_catalog.ml";"openrouter_eval_validate.ml";"openrouter_eval_native.ml";"openrouter_eval_test.ml";"openrouter_eval_cli.ml"]
let digest bytes=Cryptokit.hash_string(Cryptokit.Hash.sha256())bytes |> Cryptokit.transform_string(Cryptokit.Hexa.encode())
let suite_sha()=digest(String.concat "\000"(List.map(fun p->p^"\000"^Native.read(Native.root^"/tools/validation/"^p))source_files @ ["guardian\000"^Native.read(Native.root^"/tools/ecology_process.ml");"builder\000"^Native.read(Native.root^"/tools/validation/openrouter_eval_build.ml")]))
let safe_read path maximum=
 let st=Unix.lstat path in require(st.Unix.st_kind=Unix.S_REG && st.st_size<=maximum)"answer must be a bounded regular file";
 let input=open_in_bin path in Fun.protect(fun()->really_input_string input st.st_size)~finally:(fun()->close_in_noerr input)
let score c answer =
 let base=["schema_version",`Int 1;"suite_id",`String suite_id;"case_id",`String c.id;"domain",`String(domain_name c.domain);"seed",`Int seed;"answer_sha256",`String(digest answer);"suite_sha256",`String(suite_sha());"effect_authority",`Bool false;"scope",`String "constrained semantic repair or decision case; not language-wide or repository-wide proficiency"] in
 try
  let validation=validate c answer in
  let native=Native.run_case c validation in
  let status=if not(passed validation)then"failed"else match native.Native.status with Native.Passed|Native.Not_required->"passed"|Native.Failed->"failed"|Native.Unsupported->"unsupported"|Native.Unrun->"unrun"in
  `Assoc(base@["status",`String status;"checks",checks_json validation.checks;"native",Native.evidence_json native])
 with Invalid reason -> `Assoc(base@["status",`String "invalid";"reason",`String reason;"checks",`List[];"native",Native.evidence_json(Native.none Native.Unrun "Invalid answer cannot execute")])
let emit json=print_endline(Yojson.Safe.pretty_to_string json)
let emit_outcome json =
 emit json;
 match field "status" json |> string with
 | "passed"->()
 | "invalid"->exit 2
 | "unsupported"|"unrun"->exit 3
 | _->exit 1
let () =
 try
 require(suite_sha()=Openrouter_eval_build_id.expected_suite_sha)"evaluator source changed since compilation; rebuild before use";
 match Array.to_list Sys.argv |> List.tl with
 | ["list"] -> emit(`Assoc["suite_id",`String suite_id;"suite_sha256",`String(suite_sha());"cases",all_json()])
 | ["request";id] -> emit(request(get id))
 | ["score";id;path] -> emit_outcome(score(get id)(safe_read path 16384))
 | ["fixture";id] -> let c=get id in emit(envelope c(golden_solution c.domain))
 | ["selftest"] -> emit_outcome(Openrouter_eval_test.selftest())
 | ["native-selftest"] -> emit_outcome(Openrouter_eval_test.native_selftest())
 | _ -> reject "usage: list | request CASE | score CASE ANSWER_FILE | fixture CASE | selftest | native-selftest"
 with
 | Invalid reason -> emit(`Assoc["status",`String "invalid";"reason",`String reason;"effect_authority",`Bool false]);exit 2
 | exn -> emit(`Assoc["status",`String "failed";"reason",`String(Printexc.to_string exn);"effect_authority",`Bool false]);exit 1
