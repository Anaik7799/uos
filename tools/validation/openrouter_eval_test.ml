open Openrouter_eval_expr
open Openrouter_eval_catalog
open Openrouter_eval_validate
module Native=Openrouter_eval_native
let json=Yojson.Safe.to_string
let assert_that b message=if not b then failwith message
let replace name value object_= `Assoc((name,value)::List.remove_assoc name(object_fields object_))
let rejects operation = try ignore(operation());false with Invalid _->true
let wrong c = match c.domain with
 | Gleam_case -> `Assoc["expression",`String "True"]
 | Ocaml_case -> `Assoc["expression",`String "token > 0 && epoch > 0 && token = epoch && expected = version && version > 0 && now >= 0 && now <= expires"]
 | Mojo_case -> `Assoc["expression",`String "value"]
 | Lean_case -> `Assoc["proof",`String "by sorry"]
 | Quint_case -> `Assoc["expression",`String "false"]
 | Stm_case -> replace "committed" (`List(List.init 5(fun _->`Bool true)))(golden_solution c.domain)
 | Bayesian_case -> replace "alpha" (`Int 6)(golden_solution c.domain)
 | Rete_case -> let golden=golden_solution c.domain in replace "after" (field "before" golden)golden
 | Stpa_case -> replace "execute" (`Bool true)(golden_solution c.domain)
 | Fmea_case -> replace "selected" (`String "cosmetic")(golden_solution c.domain)
let selftest() =
 let checks=ref[] in let verify name condition=assert_that condition name;checks:=name::!checks in
 verify "ten-distinct-cases" (List.length cases=10 && List.length(List.sort_uniq String.compare(List.map(fun c->c.id)cases))=10);
 List.iter(fun c->
  let answer=envelope c(golden_solution c.domain)|>json in
  let validated=validate c answer in verify(c.id^":golden") (passed validated);
  let mutant=envelope c(wrong c)|>json in
  verify(c.id^":semantic-mutant") (try not(passed(validate c mutant))with Invalid _->true);
  verify(c.id^":markdown-refused") (rejects(fun()->validate c("```json\n"^answer^"\n```")));
  verify(c.id^":case-mismatch") (rejects(fun()->validate c(json(replace "case_id" (`String "wrong") (envelope c(golden_solution c.domain))))));
  (match language c.domain,validated.fragment with
   | Some language,Expression expression ->
     let reparsed=parse language(variables c.domain)(render language expression)in
     verify(c.id^":render-homomorphism") (List.for_all(fun(env,expected)->same(observe env reparsed)expected)(samples c))
   | _ -> ()))cases;
 let c=get "gleam-admission-v1" in
 verify "duplicate-envelope-key" (rejects(fun()->validate c "{\"schema_version\":1,\"schema_version\":1,\"case_id\":\"gleam-admission-v1\",\"solution\":{\"expression\":\"True\"}}"));
 List.iter(fun source->verify("rejected-fragment:"^source)(rejects(fun()->parse Gleam(variables c.domain)source)))
  ["os.execute(1)";"requested; True";"unknown";"True\n#eval x";"requested >= 0 // comment"];
 verify "expression-byte-bound" (rejects(fun()->parse Ocaml["x"](String.make 1025 'x')));
 verify "expression-depth-bound" (rejects(fun()->parse Ocaml["x"](String.make 30 '('^"x"^String.make 30 ')')));
 verify "expression-left-chain-depth-bound" (rejects(fun()->parse Ocaml["x"](String.concat " + "(List.init 25(fun _->"x")))));
 verify "type-mismatch" (rejects(fun()->validate c(json(envelope c(`Assoc["expression",`String "requested && True"])))));
 verify "lean-effect-injection" (rejects(fun()->normalize_proof "by omega\n#eval IO.println 1"));
 verify "quint-empty-not-witnessed" (not(Native.witness Quint_case "0 passing"));
 verify "lean-undeclared-axiom-not-witnessed" (not(Native.witness Lean_case "'stale_after_commit' depends on axioms: [propext, sorryAx]"));
 verify "missing-tool-unsupported" (match Native.availability "/nonexistent/uos-evaluation-tool" with Some e->e.Native.status=Native.Unsupported|None->false);
 let left=Random.State.make[|seed|] and right=Random.State.make[|seed|] in
 for index=0 to 127 do
  let build random =let a=Random.State.int random 100 and b=Random.State.int random 100 in parse Ocaml["x"]("x + "^string_of_int a^" - "^string_of_int b) in
  let initial=build left and final=build right in
  let environment=["x",Number(index-64)] in
  verify("twin-seed-"^string_of_int index)(same(observe environment initial)(compile final environment))
 done;
 `Assoc["status",`String "passed";"checks",`Int(List.length !checks);"seed",`Int seed;"laws",`List(List.map(fun n->`String n)(List.rev !checks));"limit",`String "Expression interpretations share primitive operations; separate case oracles and native outputs establish semantic checks"]
let native_selftest() =
 let observations=List.map(fun c->
  let validated=validate c(json(envelope c(golden_solution c.domain)))in
  let evidence=Native.run_case c validated in
  `Assoc["case_id",`String c.id;"native",Native.evidence_json evidence])cases in
 let controls=ref[] in
 let add name passes detail=controls:=`Assoc["control",`String name;"passed",`Bool passes;"detail",detail]::!controls in
 List.iter(fun(id,solution)->let c=get id in
  let valid=validate c(json(envelope c solution))in
  let deliberately_wrong={valid with checks=[check "negative-control-bypass" true "Exercise native oracle independently of semantic precheck"]}in
  let result=Native.run_case c deliberately_wrong in
  add(id^":wrong-native-result")(result.Native.status=Native.Failed)(Native.evidence_json result))[
   "gleam-admission-v1",`Assoc["expression",`String "True"];
   "lean-stale-v1",`Assoc["proof",`String "by rfl"]];
 let directory=Native.scratch()in
 let consumer_fixture case answer expected_status expected_exit name =
  let path=directory^"/"^name^".json"in Native.write path answer;
  let result=Native.run directory Sys.executable_name["score";case.id;path]in
  let observed=try result.Native.output |> Yojson.Safe.from_string |> field "status" |> string with _->"missing"in
  add name (result.code=expected_exit && observed=expected_status)
   (`Assoc["exit_code",`Int result.code;"json_status",`String observed]) in
 let admission=get "gleam-admission-v1" and stm=get "stm-cas-v1"in
 consumer_fixture admission (json(envelope admission(wrong admission))) "failed" 1 "consumer-rejects-wrong-answer";
 consumer_fixture admission ("```json\n"^json(envelope admission(golden_solution admission.domain))^"\n```") "invalid" 2 "consumer-rejects-markdown";
 consumer_fixture stm (json(envelope stm(golden_solution stm.domain))) "passed" 0 "consumer-accepts-verified-answer";
 let missing=Native.run directory "/nonexistent/uos-evaluation-tool" []in
 add "missing-executable-refused" (missing.Native.code=127) (`Assoc["exit_code",`Int missing.code]);
 let timeout=Native.run~milliseconds:20 directory "/usr/bin/sleep"["1"]in
 add "deadline" (timeout.Native.code=124) (`Assoc["exit_code",`Int timeout.code;"elapsed_seconds",`Float timeout.elapsed]);
 let quint=Native.tool Quint_case in
 if Sys.file_exists quint then (
  Native.write(directory^"/empty.qnt")"module empty_eval { val harmless = true }\n";
  let empty=Native.run directory quint["test";directory^"/empty.qnt";"--backend=typescript";"--seed=1";"--max-samples=1"]in
  add "quint-zero-tests" (empty.code=0 && not(Native.witness Quint_case empty.output)) (`Assoc["exit_code",`Int empty.code;"output",`String empty.output]));
 let native_ok=List.for_all(fun row->let state=row|>field "native"|>field "status"|>string in state="passed"||state="not_required")observations in
 let controls_ok=List.for_all(fun row->bool(field "passed" row))!controls in
 `Assoc["status",`String(if native_ok && controls_ok then"passed"else"failed_or_unsupported");"cases",`List observations;"controls",`List(List.rev !controls);"seed",`Int seed]
