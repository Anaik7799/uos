#use "topfind";;
#require "yojson,cryptokit,unix,mtime.clock.os";;
#directory "/tmp/ev-campaign-independent-direct-review-20260909/build/default/.ev_receipts.objs/byte";;
#load "/tmp/ev-campaign-independent-direct-review-20260909/build/default/ev_receipts.cma";;
(* Stage immutable candidate bytes and private copies of realized dependencies.
   The package and entrypoints are fixed; no network, package fetch or shell. *)
let require = Receipt_validator.require
let () = require (Array.length Sys.argv = 4) "usage: WORKSPACE FULL_REVISION FRESH_TARGET"
let workspace = Sys.argv.(1) and revision = Sys.argv.(2) and target = Sys.argv.(3)
let budget = Receipt_validator.make_budget ~seconds:30. ~bytes:67_108_864 ()
let binding source staged bytes = `Assoc ["source",`String source;"staged",`String staged;"sha256",`String(Receipt_validator.sha bytes);"bytes",`Int(String.length bytes)]
let () =
 require (not(Filename.is_relative target) && not(Sys.file_exists target)) "fresh absolute target required";
 let paths = ["src/cepaf_gleam/knowledge/rete_ul_verifier.gleam";"test/rete_ul_verifier_test.gleam";"test/ev107_rete_closure_test.gleam";"test/ev107_rete_runner.gleam"] in
 let sources = List.map (fun path -> let source="apps/cepaf_gleam/"^path in
  let bytes=Receipt_validator.candidate_bytes workspace revision source in
  let staged=target^"/package/"^path in Ev_campaign.write staged bytes;binding ("candidate:"^source) staged bytes) paths in
 let profile="name = \"cepaf_gleam\"\nversion = \"1.0.0\"\ntarget = \"erlang\"\n[dependencies]\ngleam_stdlib = \"0.71.0\"\ngleam_erlang = \"1.3.0\"\ngleeunit = \"1.9.0\"\n" in
 Ev_campaign.write (target^"/package/gleam.toml") profile;
 let root="/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang" in
 let dependencies=List.concat_map(Ev_campaign.file_names root)["gleam_stdlib";"gleam_erlang";"gleeunit"] |> List.map(fun path ->
  let source=root^"/"^path in let bytes=Ev_campaign.read_file budget source in let staged=target^"/lib/"^path in
  Ev_campaign.write staged bytes;binding source staged bytes) in
 Ev_campaign.write (target^"/bindings.json") (Yojson.Basic.pretty_to_string (`Assoc ["candidate",`String revision;"authority",`String "NONE";"observed_at",`Float(Unix.gettimeofday());"sources",`List sources;"dependencies",`List dependencies;"profile",binding "fixed-private-profile" (target^"/package/gleam.toml") profile]));
 Printf.printf "Staged %d immutable inputs and %d realized dependency artifacts\n" (List.length sources) (List.length dependencies)
