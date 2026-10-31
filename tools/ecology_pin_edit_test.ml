#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup,yojson,cryptokit";;
#mod_use "km_provenance/km_adjudication.ml";;
#mod_use "ecology_pin_edit.ml";;

(* Pure synthetic bytes only. No configuration files, services or credentials
   are read/written. Failure messages contain case names, never fixture values. *)
module P=Ecology_pin_edit.Pin
let checks=ref 0
let check name b=if not b then failwith("pin test: "^name) else incr checks
let oldcap="/home/an/NAS-setup/uos/var/releases/ecology/20261031-1214-"^String.make 64 'a'
let capsule="/home/an/NAS-setup/uos/var/releases/ecology/20261031-1711-"^String.make 64 'b'
let oldpayload=String.make 64 'c'
let payload_sha256=String.make 64 'd'
let ok=function Ok x->x|Error reason->failwith("unexpected pin refusal: "^reason)
let hold name=function Error _->check name true|Ok _->check name false
let replace_first text old fresh=
  let limit=String.length text-String.length old in
  let rec find i=if i>limit then failwith "test anchor" else
    if String.sub text i(String.length old)=old then i else find(i+1) in
  let i=find 0 in String.sub text 0 i^fresh^
    String.sub text(i+String.length old)(String.length text-i-String.length old)
let json_fixture cap digest=
  "{\n  \"opaque\": {\"auth\":\"SYNTHETIC_DO_NOT_REPORT\", \"copy\":\""^oldcap^"\"},\n"^
  "  \"mcpServers\": {\n"^
  "    \"uos-harness\": {\"enabled\":true, \"env\": { \"UOS_COCKPIT_RELEASE\" : \""^cap^
  "\", \"UOS_MCP_EXPECTED_PAYLOAD_SHA256\":\""^digest^"\",\"OTHER\":\"opaque\\u0041\"}},\n"^
  "    \"uos-harness-dev\": {\"enabled\":false,\"env\": {\"UOS_COCKPIT_RELEASE\":\""^cap^
  "\",\"UOS_MCP_EXPECTED_PAYLOAD_SHA256\":\""^digest^"\"}},\n"^
  "    \"foreign\": {\"env\":{\"UOS_COCKPIT_RELEASE\":\""^oldcap^"\"}}\n  }\n}\n"
let json_servers=["uos-harness";"uos-harness-dev"]
let edit_json body=P.json ~servers:json_servers ~capsule ~payload_sha256 body
let j=json_fixture oldcap oldpayload
let ()=
  let prepared=ok(edit_json j) in
  let bytes=P.bytes_for_private_commit prepared in
  check "JSON only exact literal spans change; unrelated/dev fields byte-identical"
    (bytes=json_fixture capsule payload_sha256);
  check "JSON idempotence" (P.bytes_for_private_commit(ok(edit_json bytes))=bytes);
  let metadata=P.owned_metadata prepared in
  check "metadata contains only selected own new bindings" (List.length metadata=2 &&
    List.for_all(fun(s:P.metadata)->List.mem s.server json_servers && s.capsule=capsule && s.payload_sha256=payload_sha256)metadata);
  let public=replace_first(replace_first j "uos-harness-dev" "not-owned")"uos-harness""uos-gleam" in
  check "explicit single JSON server selection" (match P.json ~servers:["uos-gleam"] ~capsule ~payload_sha256 public with Ok _->true|_->false);
  hold "missing explicit server" (P.json ~servers:["uos-gleam"] ~capsule ~payload_sha256 j);
  hold "invalid alias server" (P.json ~servers:["uos_gleam"] ~capsule ~payload_sha256 j);
  hold "duplicate server selection" (P.json ~servers:["uos-harness";"uos-harness"] ~capsule ~payload_sha256 j);
  hold "empty server selection" (P.json ~servers:[] ~capsule ~payload_sha256 j);
  hold "missing exact pin key" (edit_json(replace_first j "UOS_COCKPIT_RELEASE" "UOS_COCKPIT_RELEASE_ALIAS"));
  hold "nonstring pin" (edit_json(replace_first j ("\""^oldcap^"\", \"UOS_MCP_EXPECTED") "1, \"UOS_MCP_EXPECTED"));
  hold "duplicate owned JSON key" (edit_json(replace_first j "\"UOS_COCKPIT_RELEASE\" :" "\"UOS_COCKPIT_RELEASE\":\"x\",\"UOS_COCKPIT_RELEASE\":"));
  hold "duplicate nonowned key" (edit_json(replace_first j "\"opaque\": {" "\"opaque\":0,\"opaque\": {"));
  hold "escaped duplicate key alias" (edit_json(replace_first j "\"opaque\": {" "\"opaq\\u0075e\":0,\"opaque\": {"));
  let escaped=replace_first j "\"mcpServers\"" "\"mcp\\u0053ervers\"" in
  check "JSON escaped property retains original bytes" (P.bytes_for_private_commit(ok(edit_json escaped))=
    replace_first(json_fixture capsule payload_sha256)"\"mcpServers\"""\"mcp\\u0053ervers\"");
  List.iter(fun(name,raw)->hold name(edit_json raw))[
    "JSON trailing payload",j^"false";"JSON comment","/*x*/"^j;
    "JSON invalid syntax","{";"JSON invalid UTF8",j^"\192\128";
    "JSON lone surrogate","\"\\ud800\"";"JSON NUL",j^"\000";
    "JSON oversize",String.make 262145 ' ';"JSON depth",String.make 65 '['^"0"^String.make 65 ']'];
  let capped=j^String.make(262144-String.length j)' ' in
  check "inclusive JSON byte bound" (String.length(P.bytes_for_private_commit(ok(edit_json capped)))=262144);
  let shortcap="/x/20261031-1214-"^String.make 64 'a' in
  let short=json_fixture shortcap oldpayload in
  check "JSON replacements may grow without shifting nonowned spans"
    (P.bytes_for_private_commit(ok(edit_json short))=json_fixture capsule payload_sha256);
  hold "output growth bound" (edit_json(short^String.make(262144-String.length short)' '))

let toml_fixture cap digest=
  "# opaque comment: UOS_COCKPIT_RELEASE unchanged\r\nmodel = \"SYNTHETIC_DO_NOT_REPORT\"\r\n"^
  "approval_flags = [true, false, {level = 2}] # unchanged\r\n"^
  "[mcp_servers.uos_gleam]\r\nenabled = true\r\nargs = []\r\n"^
  "[mcp_servers.uos_gleam.env] # owned\r\nUOS_COCKPIT_RELEASE  = \""^cap^"\"  # release\r\n"^
  "UOS_MCP_EXPECTED_PAYLOAD_SHA256=\""^digest^"\"\r\nOTHER = 'opaque\\literal'\r\n"^
  "[mcp_servers.uos_gleam.tools.read_file]\r\napproval_policy = \"approve\"\r\n"^
  "[mcp_servers.uos_development]\r\nenabled = false\r\n"^
  "[mcp_servers.uos_development.env]\r\nUOS_COCKPIT_RELEASE=\""^cap^"\"\r\n"^
  "UOS_MCP_EXPECTED_PAYLOAD_SHA256 = \""^digest^"\" # digest\r\n"
let toml_servers=["uos_gleam";"uos_development"]
let edit_toml body=P.toml ~servers:toml_servers ~capsule ~payload_sha256 body
let t=toml_fixture oldcap oldpayload
let ()=
  let bytes=P.bytes_for_private_commit(ok(edit_toml t)) in
  check "TOML only exact literal spans change; CRLF/comments/approval/disabled opaque bytes identical"
    (bytes=toml_fixture capsule payload_sha256);
  check "TOML idempotence" (P.bytes_for_private_commit(ok(edit_toml bytes))=bytes);
  let shortcap="/x/20261031-1214-"^String.make 64 'a' in
  check "TOML replacements may grow without shifting nonowned spans"
    (P.bytes_for_private_commit(ok(edit_toml(toml_fixture shortcap oldpayload)))=bytes);
  let literal=replace_first t ("\""^oldcap^"\"  # release") ("'"^oldcap^"'  # release") in
  check "TOML literal-string pin edits exact literal span" (P.bytes_for_private_commit(ok(edit_toml literal))=bytes);
  hold "missing TOML pin" (edit_toml(replace_first t "UOS_COCKPIT_RELEASE  =" "OTHER_RELEASE  ="));
  hold "quoted TOML section alias" (edit_toml(replace_first t "[mcp_servers.uos_gleam.env]" "[mcp_servers.\"uos_gleam\".env]"));
  hold "quoted TOML pin alias" (edit_toml(replace_first t "UOS_COCKPIT_RELEASE  =" "\"UOS_COCKPIT_RELEASE\" ="));
  hold "dotted TOML key alias" (edit_toml(replace_first t "UOS_COCKPIT_RELEASE  =" "prefix.UOS_COCKPIT_RELEASE ="));
  hold "duplicate TOML section" (edit_toml(t^"[mcp_servers.uos_gleam.env]\n"));
  hold "duplicate TOML owned key" (edit_toml(replace_first t "OTHER =" "UOS_COCKPIT_RELEASE ="));
  hold "duplicate TOML unowned key" (edit_toml("model=\"duplicate\"\n"^t));
  hold "TOML nonstring pin" (edit_toml(replace_first t ("\""^oldcap^"\"  # release") "true # release"));
  hold "TOML table/scalar namespace collision" (edit_toml("mcp_servers=\"scalar\"\n"^t));
  hold "TOML array table unsupported" (edit_toml("[[other]]\n"^t));
  hold "TOML multiline array rejected before header recognition" (edit_toml("bad=[\n"^t));
  hold "TOML multiline basic string unsupported" (edit_toml("bad=\"\"\"multi\n"^t));
  hold "TOML multiline literal unsupported" (edit_toml("bad='''multi\n"^t));
  hold "TOML invalid slash escape" (edit_toml("bad=\"\\/\"\n"^t));
  hold "TOML surrogate pairs are not scalar escapes" (edit_toml("bad=\"\\ud83d\\ude00\"\n"^t));
  hold "TOML unsupported 8-digit escape" (edit_toml("bad=\"\\U0001F600\"\n"^t));
  hold "TOML unsupported floating point" (edit_toml("bad=0.25\n"^t));
  hold "TOML unsupported date" (edit_toml("bad=2026-10-31\n"^t));
  hold "TOML leading zero integer" (edit_toml("bad=01\n"^t));
  hold "TOML integer overflow" (edit_toml("bad=9223372036854775808\n"^t));
  hold "TOML inline duplicate key" (edit_toml("bad={x=1,x=2}\n"^t));
  hold "TOML inline trailing comma" (edit_toml("bad={x=1,}\n"^t));
  hold "TOML trailing value junk" (edit_toml("bad=true junk\n"^t));
  hold "TOML raw invalid UTF8" (edit_toml(t^"\192\128"));
  hold "TOML NUL" (edit_toml(t^"\000"));
  hold "TOML DEL control" (edit_toml(t^"#\127"));
  hold "TOML oversize" (edit_toml(String.make 262145 ' '));
  let reason name expected body=match edit_toml body with
    | Error actual->check name(actual=expected)|Ok _->check name false in
  reason "TOML bare CR at EOF rejected" "bare_cr_toml" (t^"# opaque\r");
  reason "TOML bare CR in comment rejected" "bare_cr_toml" (t^"# opaque\rcontinued\n");
  reason "TOML raw CR inside literal rejected" "bare_cr_toml"
    (replace_first t "OTHER = 'opaque\\literal'" "OTHER = 'opaque\rliteral'");
  reason "TOML section count bound" "toml_structure_bound"
    (String.concat ""(List.init 257(fun i->Printf.sprintf "[section%d]\n" i))^t);
  reason "TOML section depth bound" "toml_structure_bound"
    ("["^String.concat "."(List.init 33(fun _->"nested"))^"]\n"^t);
  reason "TOML assignment count bound" "toml_structure_bound"
    (String.concat ""(List.init 2049(fun i->Printf.sprintf "field%d=true\n" i))^t);
  reason "TOML value node bound" "toml_value_node_bound"
    ("large=["^String.concat ","(List.init 4097(fun _->"0"))^"]\n"^t);
  reason "TOML inline key bound" "toml_inline_key_bound"
    ("large={"^String.concat ","(List.init 257(fun i->Printf.sprintf "k%d=true" i))^"}\n"^t);
  reason "TOML value depth bound" "toml_depth_bound"
    ("deep="^String.make 33 '['^"0"^String.make 33 ']'^"\n"^t);
  hold "TOML server spelling alias refused"
    (P.toml ~servers:["uos-gleam"] ~capsule ~payload_sha256 t);
  let allowed="unicode=\"\\u0041\"\nbounds=[-9223372036854775808,+9223372036854775807,]\n" in
  check "finite TOML supported scalars/arrays preserve opaque bytes"
    (P.bytes_for_private_commit(ok(edit_toml(allowed^t)))=allowed^bytes)

let ()=
  List.iter(fun cap->hold "invalid capsule lexical binding"
    (P.json ~servers:json_servers ~capsule:cap ~payload_sha256 j))
    ["relative";capsule^"/";"/tmp/../"^Filename.basename capsule;
     "/tmp//"^Filename.basename capsule;"/tmp/./"^Filename.basename capsule;
     "/tmp/space dir/"^Filename.basename capsule;"/tmp/$(bad)/"^Filename.basename capsule;
     "/tmp/"^String.make 64 'b';"/tmp/20261031-1711-"^String.make 64 'B';capsule^"\000"];
  List.iter(fun digest->hold "invalid payload digest"
    (P.json ~servers:json_servers ~capsule ~payload_sha256:digest j))
    ["";String.make 63 'a';String.make 64 'A';String.make 64 'g';"sha256:"^payload_sha256];
  Printf.printf "{\"status\":\"PASS_SCOPED\",\"checks\":%d,\"authority\":\"NONE\",\"scope\":\"pure synthetic byte-span editor; no configuration IO\"}\n" !checks
