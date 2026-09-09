#use "topfind";;
#require "yojson,cryptokit,unix,mtime.clock.os";;
#directory "/tmp/ev-campaign-independent-direct-review-20260909/build/default/.ev_receipts.objs/byte";;
#load "/tmp/ev-campaign-independent-direct-review-20260909/build/default/ev_receipts.cma";;
(* Private immutable staging using the already-reviewed bounded JJ reader.
   No tool discovery, source-tree mutations, network calls or package fetching. *)
let ws=Sys.argv.(1) and rev=Sys.argv.(2) and target=Sys.argv.(3)
let require=Receipt_validator.require
let budget=Receipt_validator.make_budget ~seconds:30. ~bytes:67108864 ()
let read=Ev_campaign.read_file budget
let bound source staged bytes=`Assoc["source",`String source;"staged",`String staged;"sha256",`String(Receipt_validator.sha bytes);"bytes",`Int(String.length bytes)]
let () =
 require(not(Sys.file_exists target) && not(Filename.is_relative target)) "fresh private target required";
 let paths=["src/cepaf_gleam/knowledge/sheaf_engine.gleam";"test/sheaf_engine_test.gleam";"test/ev101_graph_integrity_test.gleam";"test/ev101_graph_runner.gleam"]in
 let sources=List.map(fun path->let source="apps/cepaf_gleam/"^path in let bytes=Receipt_validator.candidate_bytes ws rev source in let dest=target^"/package/"^path in Ev_campaign.write dest bytes;bound("candidate:"^source)dest bytes)paths in
 let profile="name = \"cepaf_gleam\"\nversion = \"1.0.0\"\ntarget = \"erlang\"\n[dependencies]\ngleam_stdlib = \"0.71.0\"\ngleam_erlang = \"1.3.0\"\ngleeunit = \"1.9.0\"\n"in
 Ev_campaign.write(target^"/package/gleam.toml")profile;
 let root="/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang"in
 let dependencies=List.concat_map(fun name->Ev_campaign.file_names root name)["gleam_stdlib";"gleam_erlang";"gleeunit"]|>List.map(fun path->let source=root^"/"^path in let bytes=read source in let staged=target^"/lib/"^path in Ev_campaign.write staged bytes;bound source staged bytes)in
 Ev_campaign.write(target^"/bindings.json")(Yojson.Basic.pretty_to_string(`Assoc["candidate",`String rev;"authority",`String "NONE";"observed_at",`Float(Unix.gettimeofday());"sources",`List sources;"dependencies",`List dependencies;"profile",bound "review-fixed-profile"(target^"/package/gleam.toml")profile]));
 Printf.printf "Staged4 immutable inputs and%d realized dependency artifacts\n"(List.length dependencies)
