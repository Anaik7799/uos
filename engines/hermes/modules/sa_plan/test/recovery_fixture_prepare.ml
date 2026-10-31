(* NON-SECRET FIXTURE KEY VECTORS. This executable is test-only, owns no real
   signer custody, and is never linked into the production worker/library. *)
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let sha p=Recovery_kernel.sha256(read p)
let hex s=String.concat""(List.init(String.length s)(fun i->Printf.sprintf"%02x"(Char.code s.[i])))
let key seed=match Mirage_crypto_ec.Ed25519.priv_of_octets(String.make 32 seed)with Ok k->k|_->failwith"fixture seed"
let signer subject session kid seed=`Assoc["subject",`String subject;"session",`String session;"kid",`String kid;"public_key_hex",`String(hex(Mirage_crypto_ec.Ed25519.pub_to_octets(Mirage_crypto_ec.Ed25519.pub_of_priv(key seed))))]
let ()=
 if Array.length Sys.argv<>4 then failwith"fixture prepare args";
 let worker=Unix.realpath Sys.argv.(1)and guardian=Unix.realpath Sys.argv.(2)and source=Unix.realpath Sys.argv.(3)in
 let clock=match Recovery_kernel.native_clock()with Ok c->c|_->failwith"actual clock"in
 let json=`Assoc["domain",`String"uos.sa-plan.recovery-launcher-data.v1";"profile",`String Recovery_kernel.profile;
  "host",`String(clock.host^".tail55d152.ts.net");"boot",`String clock.boot;"epoch",`String"1";
  "source_sha256",`String(sha source);"worker_sha256",`String(sha worker);"guardian_sha256",`String(sha guardian);
  "reviewer",signer"fixture-reviewer""fixture-review-session""fixture-review-key"'R';
  "issuer",signer"fixture-issuer""fixture-issuer-session""fixture-issuer-key"'I']in
 let bytes=Yojson.Basic.to_string json in
 (* Embed exact fixture bytes/pin, not a Dune sandbox pathname that disappears.
    The private driver creates its own O_EXCL fixture directory at runtime. *)
 Printf.printf"(* TEST-ONLY compiled fixture bytes/pin, never production. *)\nlet bytes=%S\nlet sha=%S\n"bytes(Recovery_kernel.sha256 bytes);
 print_string {|let directory=let p=Filename.temp_file "uos-recovery-cap-fixture-" "" in Sys.remove p;Unix.mkdir p 0o700;p
let path=Filename.concat directory "launcher-data.json"
let database=Filename.concat directory "fixture.sqlite3"
let ()=let fd=Unix.openfile path[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect ~finally:(fun()->close_out c)(fun()->output_string c bytes)
let own=Filename.dirname Sys.executable_name
let worker=Unix.realpath(Filename.concat own "recovery_kernel_fixture_port.exe")
let guardian=Unix.realpath(Filename.concat own "recovery_fixture_guardian.exe")
let production=Unix.realpath(Filename.concat own "../recovery_port.exe")
|}
