#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup,yojson,cryptokit";;
#mod_use "km_provenance/km_adjudication.ml";;
#mod_use "ecology_pin_edit.ml";;
module P=Ecology_pin_edit.Pin
let checks=ref 0
let check name b=incr checks;if not b then failwith("pin audit: "^name)
let ok=function Ok x->x|Error _->failwith "unexpected pin audit refusal"
let hold name=function Error _->check name true|Ok _->check name false
let cap="/private/releases/20261031-1214-"^String.make 64 'a'
let sha=String.make 64 'b'
let doc=`Assoc["mcpServers",`Assoc["uos-gleam",`Assoc[
 "command",`String "keep-command";"env",`Assoc[
 "UOS_COCKPIT_RELEASE",`String cap;"UOS_MCP_EXPECTED_PAYLOAD_SHA256",`String sha;
 "PRIVATE_UNOWNED",`String "synthetic-do-not-emit"]]]]
let json=Yojson.Safe.to_string doc
let ()=let m=ok(P.inspect_json ~servers:["uos-gleam"] json)in
 check "JSON exact observed capsule"(List.map(fun (m:P.metadata)->m.capsule)m=[cap]);
 check "JSON exact observed digest"(List.map(fun (m:P.metadata)->m.payload_sha256)m=[sha]);
 check "JSON exact selected server"(List.map(fun (m:P.metadata)->m.server)m=["uos-gleam"])
let toml="[mcp_servers.uos_gleam]\ncommand = 'keep-command'\n[mcp_servers.uos_gleam.env]\nUOS_COCKPIT_RELEASE = '"^cap^"'\nUOS_MCP_EXPECTED_PAYLOAD_SHA256 = \""^sha^"\"\nPRIVATE_UNOWNED = 'synthetic-do-not-emit'\n"
let ()=let m=ok(P.inspect_toml ~servers:["uos_gleam"] toml)in
 check "TOML exact metadata"(List.map(fun (m:P.metadata)->m.server,m.capsule,m.payload_sha256)m=["uos_gleam",cap,sha]);
 hold "unknown JSON selection"(P.inspect_json ~servers:["unowned"] json);
 hold "unknown TOML selection"(P.inspect_toml ~servers:["unowned"] toml);
 hold "duplicate decoded JSON keys"(P.inspect_json ~servers:["uos-gleam"] "{\"mcpServers\":{},\"mcpServers\":{}}");
 hold "missing selected JSON pins"(P.inspect_json ~servers:["uos-harness"] json);
 hold "unbounded bytes"(P.inspect_json ~servers:["uos-gleam"] (String.make 262145 ' '));
 hold "unsupported TOML syntax"(P.inspect_toml ~servers:["uos_gleam"] "quoted.key = 2\n")
let replace a b s=Astring.String.cuts ~sep:a s|>String.concat b
let ()=hold "invalid current capsule is not disclosed"(P.inspect_json ~servers:["uos-gleam"](replace cap "/untrusted/value" json));
 hold "invalid current digest"(P.inspect_toml ~servers:["uos_gleam"](replace sha "bad" toml));
 let target="/private/releases/20261031-1555-"^String.make 64 'c' in
 let targetsha=String.make 64 'd' in
 let edited=ok(P.json ~servers:["uos-gleam"] ~capsule:target ~payload_sha256:targetsha json)in
 let observed=ok(P.inspect_json ~servers:["uos-gleam"](P.bytes_for_private_commit edited))in
 check "edit then inspect actual new pins"(List.map(fun (m:P.metadata)->m.capsule,m.payload_sha256)observed=[target,targetsha]);
  print_endline(Printf.sprintf "pin inspect %d checks PASS" !checks);;

let ()=
 let quoted_projects="[projects.\"/private/a.b#x]=q\"]\ntrust_level = 'trusted'\n"^toml in
 let p=ok(P.inspect_toml ~servers:["uos_gleam"]quoted_projects)in
 check "quoted unrelated table supported"(List.length p=1);
 let literal_projects="[projects.'/private/a.b#x]=q']\ntrust_level = 'trusted'\n"^toml in
 check "literal unrelated table supported"(List.length(ok(P.inspect_toml ~servers:["uos_gleam"]literal_projects))=1);
 let quoted_owned=replace "mcp_servers.uos_gleam.env" "\"mcp_servers\" . 'uos_gleam' . env"toml in
 check "quoted and whitespace owned header"(List.length(ok(P.inspect_toml ~servers:["uos_gleam"]quoted_owned))=1);
 let quoted_key=replace "UOS_COCKPIT_RELEASE =" "\"UOS_COCKPIT_RELEASE\" ="toml in
 check "quoted owned key has canonical identity"(List.length(ok(P.inspect_toml ~servers:["uos_gleam"]quoted_key))=1);
 let unowned_key="[notice.model_migrations]\n\"model.name=one\" = 'model-two'\n"^toml in
 check "quoted unowned key includes equals"(List.length(ok(P.inspect_toml ~servers:["uos_gleam"]unowned_key))=1);
 hold "decoded quoted duplicate assignment"(P.inspect_toml ~servers:["uos_gleam"](toml^"\"UOS_COCKPIT_RELEASE\" = '"^cap^"'\n"));
 let duplicate="[projects.\"same.name\"]\nx = 1\n[projects.'same.name']\ny = 2\n"^toml in
 hold "decoded duplicate quoted table"(P.inspect_toml ~servers:["uos_gleam"]duplicate);
 hold "array tables remain explicit unsupported"(P.inspect_toml ~servers:["uos_gleam"]("[[unowned]]\nx = 1\n"^toml));;

let ()=List.iter(fun number->
 check "finite opaque float supported"(List.length(ok(P.inspect_toml ~servers:["uos_gleam"]("opaque_number = "^number^"\n"^toml)))=1))
 ["0.5";"-0.0";"+1.25";"1e2";"0e+2";"1_000.0_25";"1.0e-03"];
 List.iter(fun number->hold "invalid or unbounded float refuses"(P.inspect_toml ~servers:["uos_gleam"]("opaque_number = "^number^"\n"^toml)))
 [".5";"1.";"01.5";"1._0";"1.0_";"1e";"1e_2";"1e309";"nan";"inf"];;

#mod_use "ecology_pin_audit.ml";;
module A=Ecology_pin_audit.Audit
let root=Filename.temp_file "uos-pin-audit-" ""
let ()=Unix.unlink root;Unix.mkdir root 0o700
let path name=Filename.concat root name
let write name body=let fd=Unix.openfile(path name)[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in
 let out=Unix.out_channel_of_descr fd in output_string out body;close_out out
let observe name=A.observe ~root ~relative:name ~format:A.Json
let ()=write "config.json" json;
 let before=(Unix.stat(path"config.json")).Unix.st_perm in
 (match observe "config.json"with A.Observed m->check "actual private file observed"(List.length m=1)|_->check "actual private file observed"false);
 check "read-only mode"((Unix.stat(path"config.json")).Unix.st_perm=before);
 let ic=open_in_bin(path"config.json")in let after=really_input_string ic(in_channel_length ic)in close_in ic;
 check "read-only bytes"(after=json);
 check "absent observed without creation"(observe "missing.json"=A.Absent && not(Sys.file_exists(path"missing.json")));
 Unix.symlink(path"config.json")(path"symlink.json");
 check "symlink refuses before read"(observe "symlink.json"=A.Held A.UnsafePath);
 Unix.link(path"config.json")(path"hardlink.json");
 check "hardlink alias refuses"(observe "hardlink.json"=A.Held A.UnsafePath);
 Unix.unlink(path"hardlink.json");
 Unix.mkfifo(path"fifo.json")0o600;
 check "FIFO refuses before blocking open"(observe "fifo.json"=A.Held A.UnsafePath);
 write "oversize.json"(String.make 262145 'x');
 check "read allocation bound"(observe "oversize.json"=A.Held A.ResourceBound);
 check "parent traversal refuses"(observe "../config.json"=A.Held A.UnsafePath);
 write "bad.json""{\"mcpServers\":{},\"mcpServers\":{}}";
 check "bad config cannot observe"(match observe "bad.json"with A.Held _->true|_->false);
 let report=A.export[A.item "fixture"(observe "config.json")]in
 let report=Yojson.Safe.to_string report in
 check "unowned synthetic credential not emitted"(not(Astring.String.is_infix ~affix:"synthetic-do-not-emit"report));
 check "unowned field not emitted"(not(Astring.String.is_infix ~affix:"PRIVATE_UNOWNED"report));
 let metadata=ok(P.inspect_json ~servers:["uos-gleam"]json)in
 let forged=A.export(List.init 11(fun _->A.item "duplicate"(A.Observed metadata)))in
 check "equal count is not exact catalog"(Yojson.Safe.Util.member "all_configuration_targets_observed"forged=`Bool false);
 List.iter(fun name->Unix.unlink(path name))["config.json";"symlink.json";"fifo.json";"oversize.json";"bad.json"];
 Unix.rmdir root;
 print_endline(Printf.sprintf "pin audit %d total checks PASS" !checks)
