#use "topfind";;
#require "unix,yojson,cryptokit,mtime.clock.os";;
#directory "/tmp/ev-campaign-independent-direct-review-20260909/build/default/.ev_receipts.objs/byte";;
#load "/tmp/ev-campaign-independent-direct-review-20260909/build/default/ev_receipts.cma";;
(* Fixed, private composition recipe. It checks reviewed source equality and
   copies already-reviewed private dependency bytes, never a moving shared build.
   Compile and execution are separate native invocations, bound by bindings.json.
   This is component integration evidence, with no EV admission authority. *)
let require=Receipt_validator.require
let field=Yojson.Basic.Util.member
let str=Yojson.Basic.Util.to_string
let list=Yojson.Basic.Util.to_list
let ()=require(Array.length Sys.argv=4) "usage: WORKSPACE FULL_REVISION FRESH_STAGE"
let workspace=Sys.argv.(1) and candidate=Sys.argv.(2) and target=Sys.argv.(3)
let budget=Receipt_validator.make_budget ~seconds:90. ~bytes:67_108_864 ()
let read=Ev_campaign.read_file budget
let source revision path=Receipt_validator.candidate_bytes ~budget workspace revision path
let sha=Receipt_validator.sha
let binding source staged bytes=`Assoc["source",`String source;"staged",`String staged;"sha256",`String(sha bytes);"bytes",`Int(String.length bytes)]
let write source_name relative bytes=let staged=target^"/"^relative in Ev_campaign.write staged bytes;binding source_name staged bytes
let private_dependency_path path=
 let parts=String.split_on_char '/' path in
 require(path<>"" && String.length path<=1024 && Filename.is_relative path && List.length parts<=8 &&
  List.for_all(fun part->part<>"" && not(List.mem part[".";"..";".git";".jj";".ssh";".gnupg"]) &&
   String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'.'|'@'->true|_->false)part)parts)
  "noncanonical private dependency path"
let graph="ea6cd8e8dcc0775239d49697390d54728e9eded0"
let rete="168c31943c90b0c494b60ca0baff9f25c8cc702c"
let remediation="7375a867c5e86d020805976fb64d014009fac870"
let digest="11eeca9df5c14961ed4b4b8fc990752ad7bccd46"
let gleam_files=[
 graph,"src/cepaf_gleam/knowledge/sheaf_engine.gleam";
 graph,"test/sheaf_engine_test.gleam";
 graph,"test/ev101_graph_integrity_test.gleam";
 rete,"src/cepaf_gleam/knowledge/rete_ul_verifier.gleam";
 rete,"test/rete_ul_verifier_test.gleam";
 rete,"test/ev107_rete_closure_test.gleam";
 remediation,"src/cepaf_gleam/agents/ooda_shruti_copilot.gleam";
 remediation,"src/cepaf_gleam/knowledge/raga_cybernetic_synthesis.gleam";
 remediation,"src/cepaf_gleam/ui/state.gleam";
 remediation,"test/ooda_shruti_copilot_test.gleam"]
let digest_files=["gospel_dispatch_contracts.ml";"gospel_dispatch_contracts.mli";"test_gospel_dispatch_contracts.ml"]
let ()=
 require(Sys.getcwd()=workspace) "child JJ reader cwd must equal selected workspace; invoke adapter with explicit --cwd";
 require(not(Filename.is_relative target) && not(Sys.file_exists target)) "fresh absolute stage required";
 let driver=source candidate "tools/ev_component_composition.ml" in
 require(driver=read Sys.argv.(0)) "running driver differs from candidate";
 let advice=source candidate "docs/reviews/20260909-1831-agy-advice-and-program-recovery-corrected-advice.txt" in
 require(sha advice="a34dde1e0208348f68d2f04c25d5a91ccd16b0f719b75e31d76410e577d7ee2d") "required observed AGY advice differs";
 let approvals=[
  "docs/reviews/20260909-1619-ev101-independent-approval.json","012d27c8902246bdea76bfef70293d96aaa0a3134ed6fe3af4a4240be8546abf";
  "docs/reviews/20260909-1633-ev104-independent-approval.json","ccb1995fbeee765a8bd267b3727946666dc23e6356007c4668e3d4d5807bb2f3";
  "docs/reviews/20260909-1653-ev107-rete-independent-approval.json","027c90ec501ef915d89860d6215fe896f193ae84d2569aff320e533e96cae7f0"] in
 let approval_bindings=List.map(fun(path,expected)->let bytes=source candidate path in
  require(sha bytes=expected)("approval changed: "^path);write("candidate:"^path)("evidence/"^Filename.basename path)bytes)approvals in
 let sources=List.map(fun(reviewed,path)->let path="apps/cepaf_gleam/"^path in
  let bytes=source candidate path in require(bytes=source reviewed path)("composition source differs from review: "^path);
  let relative=String.sub path(String.length "apps/cepaf_gleam/")(String.length path-String.length "apps/cepaf_gleam/")in
  `Assoc["reviewed_candidate",`String reviewed;"binding",write("candidate:"^path)("package/"^relative)bytes])gleam_files in
 let sources=sources@List.map(fun name->let path="engines/hermes/modules/system_engg/"^name in
  let bytes=source candidate path in require(bytes=source digest path)("digest source differs: "^name);
  `Assoc["reviewed_candidate",`String digest;"binding",write("candidate:"^path)("digest/"^name)bytes])digest_files in
 let runner="apps/cepaf_gleam/test/ev_component_composition_runner.gleam"in
 let runner_binding=write("candidate:"^runner)"package/test/ev_component_composition_runner.gleam"(source candidate runner)in
 let remediation_approval=source candidate "docs/reviews/20260909-1633-ev104-independent-approval.json"|>Yojson.Basic.from_string in
 let reviewed_dependencies=remediation_approval|>field "inputs_before_and_after"|>field "dependencies"|>list in
 require(List.length reviewed_dependencies=168) "review dependency inventory changed";
 let private_prefix="/tmp/ev104-independent-review-20260909-1642/lib/"in
 let dependencies=List.map(fun entry->let path=entry|>field "staged"|>str in
  require(String.starts_with ~prefix:private_prefix path) "dependency outside reviewed private tree";
  let relative=String.sub path(String.length private_prefix)(String.length path-String.length private_prefix)in
  (* Gleam BEAM/cache basenames contain @; the repository source-path grammar
     deliberately excludes it. Keep the relaxed grammar local to this fixed,
     hash-approved dependency inventory. *)
  private_dependency_path relative;
  let bytes=read path in require(sha bytes=(entry|>field "sha256"|>str))("private dependency changed: "^path);
  write path ("lib/"^relative)bytes)reviewed_dependencies in
 let profile="name = \"cepaf_gleam\"\nversion = \"1.0.0\"\ntarget = \"erlang\"\n[dependencies]\ngleam_stdlib = \"0.71.0\"\ngleam_erlang = \"1.3.0\"\ngleam_json = \"3.1.0\"\ngleeunit = \"1.9.0\"\n"in
 let dune="(executable (name test_gospel_dispatch_contracts) (modes byte) (link_flags -without-runtime) (modules gospel_dispatch_contracts test_gospel_dispatch_contracts) (libraries unix str cryptokit))\n"in
 let recipes=[write "fixed-private-profile" "package/gleam.toml" profile;
  write "fixed-raw-bytecode-recipe" "digest/dune" dune;
  write "fixed-private-project" "digest/dune-project" "(lang dune 3.0)\n(name ev_component_digest)\n";
  write "candidate:tools/ev_component_composition.ml" "evidence/ev_component_composition.ml" driver;
  write "observed-AGY-advice" "evidence/agy-advice.txt" advice]in
 let manifest=`Assoc["schema",`String "uos.component-composition-stage.v1";"candidate",`String candidate;
  "authority",`String "NONE";"admission",`String "NOT_GRANTED";"observed_at",`Float(Unix.gettimeofday());
  "sources",`List sources;"runner",runner_binding;"dependencies",`List dependencies;
  "approvals",`List approval_bindings;"recipes",`List recipes;
  "expected_gleam_tests",`Int 53;"expected_ocaml_tests",`Int 18;
  "limits",`List(List.map(fun x->`String x)["Reviewed production bytes are unchanged; new runner combines existing53 tests concurrently. No full package, UI, audio or live effect invocation.";"The digest recipe uses only explicit raw .bc bytecode through native ocamlrun; no new assembler/linker shell path is intended. A separate execution trace must establish the observed closure.";"Copied private dependencies avoid concurrent canonical build mutation. Local filesystem, inherited secure config and runtime libraries remain cooperative assumptions.";"No full EV101/104/107 admission, authenticated transitive release closure, mathematical sheaf proof or general Rete refinement."])]in
 Ev_campaign.write(target^"/bindings.json")(Yojson.Basic.pretty_to_string manifest^"\n");
 Printf.printf "Staged %d reviewed source files, 1 combined runner and %d private dependency artifacts; candidate %s\n"(List.length sources)(List.length dependencies)candidate
