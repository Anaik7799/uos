#use "topfind";;
#require "unix,yojson,cryptokit,str";;
let stage=Sys.argv.(1) and content=Sys.argv.(2)
let require c s=if not c then failwith s
let ()=require(String.starts_with ~prefix:"/tmp/" stage && String.starts_with ~prefix:"/tmp/" content)"private paths required"
let write p b=let c=open_out_bin p in Fun.protect ~finally:(fun()->close_out_noerr c)(fun()->output_string c b)
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b |> Cryptokit.transform_string(Cryptokit.Hexa.encode())
let listen=Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0
let ()=Unix.bind listen(Unix.ADDR_INET(Unix.inet_addr_loopback,0))
let port=match Unix.getsockname listen with Unix.ADDR_INET(_,p)->p|_->assert false
let ()=Unix.close listen
let elf="/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang/erts-17.0.5/bin/erlexec"
let libs=Sys.readdir(stage^"/full-lib") |> Array.to_list |> List.sort String.compare |> List.map(fun n->stage^"/full-lib/"^n^"/ebin") |> List.filter Sys.file_exists
let argv=Array.of_list([elf;"-noshell";"-noinput";"-pa"]@libs@[stage^"/full-compiled/ebin";"-s";"music_http_probe";"main";"-s";"init";"stop"])
let run=Filename.temp_dir "ev86-http-observation-" ""
let log=Unix.openfile(run^"/http-server.log")[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600
let pid=Unix.fork()
let ()=if pid=0 then(try ignore(Unix.setsid());Unix.chdir stage;Unix.dup2 log Unix.stdout;Unix.dup2 log Unix.stderr;Unix.close log;Unix.execve elf argv(Array.append(Unix.environment())[|"UOS_MUSIC_ROOT="^content;"UOS_MUSIC_TEST_PORT="^string_of_int port|])with _->Unix._exit 127)else Unix.close log
let connect()=let fd=Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in Unix.set_close_on_exec fd;try Unix.connect fd(Unix.ADDR_INET(Unix.inet_addr_loopback,port));fd with e->Unix.close fd;raise e
let rec wait until=try let fd=connect()in Unix.close fd with Unix.Unix_error(Unix.ECONNREFUSED,_,_)->require(Unix.gettimeofday()<until)"HTTP startup deadline";ignore(Unix.select[][][]0.05);wait until
let request method_ path=let fd=connect()in Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
let text=method_^" "^path^" HTTP/1.1\r\nHost: nas-1.tail55d152.ts.net:"^string_of_int port^"\r\nConnection: close\r\n\r\n"in
let rec send i=if i<String.length text then let n=Unix.write_substring fd text i(String.length text-i)in require(n>0)"write closed";send(i+n)in send 0;
let b=Buffer.create 4096 and tmp=Bytes.create 65536 in let until=Unix.gettimeofday()+.5. in
let complete()=try let bytes=Buffer.contents b in let at=Str.search_forward(Str.regexp_string"\r\n\r\n")bytes 0 in let headers=String.sub bytes 0 at |> String.split_on_char '\n' in
let length=if method_="HEAD"then 0 else let line=List.find(fun l->String.starts_with ~prefix:"content-length:"(String.lowercase_ascii l))headers in int_of_string(String.trim(String.sub line 15(String.length line-15)))in Buffer.length b>=at+4+length with Not_found->false in
let rec recv()=if not(complete())then(let ready,_,_=Unix.select[fd][][](max 0. (until-.Unix.gettimeofday()))in if ready=[]then(write(run^"/failed-partial.response")(Buffer.contents b);failwith"HTTP receive deadline");let n=Unix.read fd tmp 0 65536 in if n<>0 then(require(Buffer.length b+n<=16777216)"HTTP output bound";Buffer.add_subbytes b tmp 0 n;recv()))in recv();Buffer.contents b)
let check name method_ path expected mime=let raw=request method_ path in let i=Str.search_forward(Str.regexp_string"\r\n\r\n")raw 0 in let head=String.sub raw 0 i and body=String.sub raw(i+4)(String.length raw-i-4)in
let lines=String.split_on_char '\n' head |> List.map String.trim in let status=Scanf.sscanf(List.hd lines)"HTTP/1.1 %d"(fun x->x)in require(status=expected)(name^" status");
let header k=let prefix=String.lowercase_ascii k^":"in List.find_map(fun l->let low=String.lowercase_ascii l in if String.starts_with ~prefix low then Some(String.trim(String.sub l(String.length prefix)(String.length l-String.length prefix)))else None)lines in
Option.iter(fun m->require(header"content-type"=Some m)(name^" MIME"))mime;
let length=Option.map int_of_string(header"content-length")in if method_<>"HEAD"then require(length=Some(String.length body))(name^" length");
if name="player"||name="studio"then(require(try ignore(Str.search_forward(Str.regexp_string"<audio controls")body 0);true with Not_found->false)"audio missing";require(not(try ignore(Str.search_forward(Str.regexp_string"<script")body 0);true with Not_found->false))"script active");
if name="mp3"then require(sha body="d5e2e97ae5787b60bc0ec8adf3dbde0e2a08484d4e81a203130ef41da4f32d9a")"MP3 exact source bytes";
if name="wav"then require(sha body="b281fc8bd0b681603de1c15a37e1d1b3fe863181214119b2f8d8238b5baa1ef6")"WAV exact source bytes";
write(run^"/http-"^name^".response")raw;`Assoc["case",`String name;"method",`String method_;"path",`String path;"status",`Int status;"content_type",(match header"content-type"with Some s->`String s|None->`Null);"body_bytes",`Int(String.length body);"body_sha256",`String(sha body);"raw_sha256",`String(sha raw)]
let ()=Fun.protect ~finally:(fun()->(try Unix.kill(-pid)Sys.sigterm with _->());ignore(Unix.waitpid[]pid))(fun()->wait(Unix.gettimeofday()+.5.);
let cases=["player","GET","/docs/music/player",200,Some"text/html; charset=utf-8";"studio","GET","/docs/music/studio",200,Some"text/html; charset=utf-8";"mp3","GET","/media/music/historical-enhanced.mp3",200,Some"audio/mpeg";"wav","GET","/media/music/historical-mix.wav",200,Some"audio/wav";"head","HEAD","/media/music/historical-enhanced.mp3",200,Some"audio/mpeg";"missing","GET","/docs/music/absent",404,None;"traversal","GET","/docs/music/../design/private",404,None;"percent","GET","/docs/%6dusic/player",404,None;"backslash","GET","/docs/music%5cplayer",404,None;"method","POST","/docs/music/player",405,None]in
let rows=List.map(fun(n,m,p,s,c)->check n m p s c)cases in
let j=`Assoc["scope",`String"Private native HTTP bytes only; no playback/deploy/admission";"host",`String"nas-1.tail55d152.ts.net";"private_resolver_mapping",`String"127.0.0.1";"port",`Int port;"child_argv",`List(Array.to_list argv |> List.map(fun s->`String s));"checks",`List rows]in Yojson.Safe.to_file(run^"/http-verification.json")j;print_endline("PASS "^string_of_int(List.length rows)^" actual HTTP cases "^run))
