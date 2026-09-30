#use "topfind";;
#require "unix,yojson,cryptokit,str";;

(* Execute only the post-receive checker extracted from the bound source text.
   The original HTTP driver's top-level socket/process setup is never evaluated. *)
let read p = let c = open_in_bin p in Fun.protect ~finally:(fun () -> close_in_noerr c) (fun () -> really_input_string c (in_channel_length c))
let write p s = let c = open_out_gen [Open_creat;Open_excl;Open_wronly;Open_binary] 0o600 p in Fun.protect ~finally:(fun () -> close_out_noerr c) (fun () -> output_string c s)
let sha s = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let find s part = Str.search_forward (Str.regexp_string part) s 0
let require p s = if not p then failwith s
let () =
  let source_path = Sys.argv.(1) in
  let source = read source_path in
  let stage = Filename.temp_dir "ev86-capture-fixtures-" "" in
  let checker =
    if String.contains source '\000' then failwith "NUL in checker source"
    else try
      let start = find source "let check_response " and stop = find source "let check name " in
      String.sub source start (stop - start)
    with Not_found ->
      let start = find source "let check name method_ path expected mime=let raw=request method_ path in " in
      let start = start + String.length "let check name method_ path expected mime=let raw=request method_ path in " in
      let stop = find source "let ()=Fun.protect" in
      "let check_response name method_ path expected mime raw = " ^ String.sub source start (stop - start)
  in
  require (not (try ignore (find checker "request "); true with Not_found -> false)) "request execution must not enter fixture projection";
  let prelude = "#use \"topfind\";;\n#require \"unix,yojson,cryptokit,str\";;\nlet run=" ^ Printf.sprintf "%S" stage ^ "\nlet public_base=\"http://nas-1.tail55d152.ts.net:4100\"\nlet require p s=if not p then failwith s\nlet write p b=let c=open_out_bin p in Fun.protect ~finally:(fun()->close_out_noerr c)(fun()->output_string c b)\nlet sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b |> Cryptokit.transform_string(Cryptokit.Hexa.encode())\n" in
  let fixtures = {|
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->really_input_string c(in_channel_length c))
let checks=ref []
let fixture name method_ raw expected mime should_reject =
 let rejected=try ignore(check_response name method_ "/fixture" expected mime raw);false with _->true in
 require(rejected=should_reject)(name^" validation outcome");
 let p=run^"/http-"^name^".response" in
 require(Sys.file_exists p)("EV86_CAPTURE_BEFORE_ASSERT:"^name);
 require(read p=raw)("EV86_CAPTURE_EXACT_BYTES:"^name);
 checks:=`Assoc["case",`String name;"raw_sha256",`String(sha raw);"rejected",`Bool rejected]::!checks
let ()=
 fixture "wrong-status" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 3\r\n\r\na\000b" 404 None true;
 fixture "missing-separator" "GET" "malformed-response\000" 404 None true;
 fixture "malformed-status" "GET" "not-HTTP\r\ncontent-length: 0\r\n\r\n" 404 None true;
 fixture "wrong-mime" "GET" "HTTP/1.1 404 Missing\r\ncontent-length: 3\r\ncontent-type: other\r\n\r\nfoo" 404 (Some "text/plain") true;
 fixture "wrong-length" "GET" "HTTP/1.1 404 Missing\r\ncontent-length: 9\r\n\r\nfoo" 404 None true;
 fixture "head-body" "HEAD" "HTTP/1.1 404 Missing\r\ncontent-length: 3\r\n\r\nfoo" 404 None true;
 fixture "malformed-content-length" "GET" "HTTP/1.1 404 Missing\r\ncontent-length: notanumber\r\n\r\nfoo" 404 None true;
 fixture "player" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 12\r\ncontent-type: text/html; charset=utf-8\r\n\r\nHello World!" 200 (Some "text/html; charset=utf-8") true;
 fixture "player" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 44\r\ncontent-type: text/html; charset=utf-8\r\n\r\n<audio controls><script>alert(1)</script></audio>" 200 (Some "text/html; charset=utf-8") true;
 fixture "player" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 47\r\ncontent-type: text/html; charset=utf-8\r\n\r\n<audio controls src='http://evil.com/media/music/'>" 200 (Some "text/html; charset=utf-8") true;
 fixture "mp3" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 4\r\ncontent-type: audio/mpeg\r\n\r\nbad!" 200 (Some "audio/mpeg") true;
 fixture "wav" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 4\r\ncontent-type: audio/wav\r\n\r\nbad!" 200 (Some "audio/wav") true;
 fixture "valid" "GET" "HTTP/1.1 404 Missing\r\ncontent-length: 3\r\ncontent-type: text/plain\r\n\r\nfoo" 404 (Some "text/plain") false;
 Yojson.Safe.to_file(run^"/checks.json")(`List(List.rev!checks)); print_endline "PASS 13 local static-response capture fixtures"
|} in
  let projected = prelude ^ checker ^ fixtures in
  let test = stage ^ "/capture_fixture.ml" in write test projected;
  let output = stage ^ "/stdout.txt" in let fd=Unix.openfile output [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL] 0o600 in
  let executable="/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocamlrun" in
  let args=[|executable;"/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocaml";test|] in
  let child=Unix.create_process executable args Unix.stdin fd fd in Unix.close fd;
  let status=match snd(Unix.waitpid [] child) with Unix.WEXITED n->n|_->125 in
  let report=`Assoc["scope",`String "Post-receive source projection and local static response fixtures only; no driver setup, HTTP request, listener or live effect";"source_path",`String source_path;"source_sha256",`String(sha source);"checker_sha256",`String(sha checker);"projection_sha256",`String(sha projected);"stage",`String stage;"exit_code",`Int status;"output",`String(read output)] in
  Yojson.Safe.to_file(stage^"/verification.json")report;
  print_endline(stage^"/verification.json"); print_string(read output); exit status
