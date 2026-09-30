#use "topfind";;
#require "yojson,cryptokit,unix,mtime.clock.os";;
#directory "/tmp/ev-campaign-independent-direct-review-20260909/build/default/.ev_receipts.objs/byte";;
#load "/tmp/ev-campaign-independent-direct-review-20260909/build/default/ev_receipts.cma";;
let root="/home/an/NAS-setup/uos"
let ws=root^"/.uos-workspaces/ev98-wire-codec-20260909"
let rev="11eeca9df5c14961ed4b4b8fc990752ad7bccd46"
let evidence="725aa3d18813280554964885ddeba9820ac171a7"
let stage="/tmp/ev107-independent-1625"
let budget=Receipt_validator.make_budget ~seconds:180. ~bytes:134217728 ()
let read=Ev_campaign.read_file budget
let sha=Receipt_validator.sha
let require=Receipt_validator.require
let write=Ev_campaign.write
let refs=ref []
let bind path bytes=refs:=Ev_campaign.reference path bytes::!refs
let adapter=root^"/.uos-workspaces/codex-ev-admission-20260909-0210/tools/ev_native.ml"
let run name cwd args=
 let receipt=stage^"/"^name^".json" in
 ignore(Receipt_validator.run ~seconds:65. ~limit:1048576 (root^"/toolchains/opam-ocaml/bin/ocamlrun")([root^"/toolchains/opam-ocaml/bin/ocaml";adapter;"--cwd";cwd;"--seconds";"60";"--receipt";receipt;"--"]@args));
 bind receipt(read receipt)
let replace src old neu=
 let positions=ref [] in
 for i=0 to String.length src-String.length old do
 if String.sub src i(String.length old)=old then positions:=i::!positions done;
 match !positions with[i]->String.sub src 0 i^neu^String.sub src(i+String.length old)(String.length src-i-String.length old)|_->failwith "mutation anchor count"
let probe={probe|
open Gospel_dispatch_contracts
let total=ref 0
let check label yes=incr total;if not yes then failwith label;Printf.printf "INDEPENDENT PASS %s\n%!"label
let reject=function Error _->true|_->false
let agree p h=bounded_differential_oracle p h=Ok true
let code p=match validate_dispatch_contract p with FailClosed{error_code;_}->error_code|Pass _->0
let ()=
 let vectors=["abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq","248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1";"The quick brown fox jumps over the lazy dog","d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592";String.make 1000000 'a',"cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"]in
 List.iteri(fun i(p,h)->check("known-vector-"^string_of_int i)(sha256_digest p=h && agree p h))vectors;
 let p="raw\000; DROP TABLE example"in
 check "nul-sql-precedence"(code p = -2);
 check "matched-rejection-is-agreement"(agree p(sha256_digest p));
 check "rejected-wrong-expectation"(reject(bounded_differential_oracle p(String.make 64 '0')));
 let p="\195\169\n\255"in let h=sha256_digest p in
 check "arbitrary-byte-agreement"(agree p h);
 check "newline-alters-expectation"(reject(bounded_differential_oracle(p^"\n")h));
 List.iteri(fun i h->check("grammar-"^string_of_int i)(reject(bounded_differential_oracle "abc" h)))[String.make 64 '\000';String.make 128 'a';String.make 64 'A';String.make 63 'a'^" ";String.make 63 'a'^"\n"];
 check "sql-rejection-not-dispatch"(code "; drop table x" = -3 && agree "; drop table x"(sha256_digest "; drop table x"));
 Printf.printf "INDEPENDENT SUMMARY %d PASS\n" !total
|probe}
let ()=
 let base="engines/hermes/modules/system_engg/"in
 let names=[base^"gospel_dispatch_contracts.ml";base^"gospel_dispatch_contracts.mli";base^"test_gospel_dispatch_contracts.ml";"tools/test_ev107_digest.ml"]in
 let sources=List.map(fun p->let b=Receipt_validator.candidate_bytes ws rev p in require(b=read(ws^"/"^p))"frozen source differs";bind p b;p,b)names in
 let manifest_path="docs/reviews/20260909-1542-ev107-digest-final-verification.json"in
 let manifest=Receipt_validator.candidate_bytes ws evidence manifest_path in
 require(sha manifest="b121fcd1996ca360e86290693f3af9b73f29404554873824b33aed501c41b1a5")"author manifest binding";
 write(stage^"/author-manifest.json")manifest;
 List.iter(fun(p,b)->write(stage^"/source/"^Filename.basename p)b)sources;
 let src=List.assoc(base^"gospel_dispatch_contracts.ml")sources and mli=List.assoc(base^"gospel_dispatch_contracts.mli")sources in
 let variants=["positive",src,probe;
 "primary-digest",replace src "digest = sha256_digest payload;\n      timestamp" "digest = String.make 64 '0';\n      timestamp","";
 "reference-digest",replace src "Pass { digest = sha256_digest payload; timestamp = \"REF_OK\" }" "Pass { digest = String.make 64 '0'; timestamp = \"REF_OK\" }","";
 "reference-code",replace src "reason = \"RefOracle: NUL byte\"; error_code = -2" "reason = \"RefOracle: NUL byte\"; error_code = -3","";
 "reference-kind",replace src "Pass { digest = sha256_digest payload; timestamp = \"REF_OK\" }" "FailClosed { reason = \"independent forced refusal\"; error_code = -3 }","";
 "diagnostics-only",replace src "reason = \"RefOracle: NUL byte\"" "reason = \"different prose is intentionally immaterial\"",probe]in
 List.iter(fun(name,ml,driver)->
 let dir=stage^"/"^name in write(dir^"/gospel_dispatch_contracts.ml")ml;write(dir^"/gospel_dispatch_contracts.mli")mli;
 let driver=if driver<>""then driver else Printf.sprintf "open Gospel_dispatch_contracts\nlet () = let payload=%S in match bounded_differential_oracle payload (sha256_digest payload) with Error _ -> print_endline \"INDEPENDENT DISAGREEMENT REFUSED\" | _ -> failwith \"unexpected agreement\"\n"(if name="reference-code"then "a\000b"else "abc")in
 write(dir^"/independent_probe.ml")driver;
 write(dir^"/test_gospel_dispatch_contracts.ml")(List.assoc(base^"test_gospel_dispatch_contracts.ml")sources);
 write(dir^"/dune-project")"(lang dune 3.0)\n(name independent_ev107)\n";
 write(dir^"/dune")"(library (name gospel_dispatch_contracts) (wrapped false) (modules gospel_dispatch_contracts) (libraries unix str cryptokit))\n(executables (names independent_probe test_gospel_dispatch_contracts) (modules independent_probe test_gospel_dispatch_contracts) (libraries gospel_dispatch_contracts))\n";
 run(name^"-build")dir["dune";"build";"--root";dir;"--build-dir";dir^"/build";"independent_probe.exe";"test_gospel_dispatch_contracts.exe"];
 run(name^"-probe")dir["native";dir^"/build/default/independent_probe.exe"];
 if name="positive"then run "author18"dir["native";dir^"/build/default/test_gospel_dispatch_contracts.exe"];
 List.iter(fun p->bind p(read p))[dir^"/gospel_dispatch_contracts.ml";dir^"/independent_probe.ml";dir^"/build/default/independent_probe.exe"]
 )variants;
 List.iter(fun(p,b)->require(read(ws^"/"^p)=b)"post source drift")sources;
 write(stage^"/bindings.json")(Yojson.Basic.pretty_to_string(`List(List.rev !refs)));
 print_endline stage
