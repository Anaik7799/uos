(* Fixed local executable oracle adapter. No caller-selected shell or command.
   The Linux namespace and process/resource bounds are exercised, not inferred
   from a trace. This is not a generic hostile-code execution service. *)
let oracle_sha text = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) text
 |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let hash_file path =
 let ic=open_in_bin path in
 Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
  let before=Unix.fstat (Unix.descr_of_in_channel ic) in
  if before.Unix.st_kind<>Unix.S_REG || before.st_size>128*1024*1024 then failwith "oracle identity file bound";
  let digest=Cryptokit.Hash.sha256 () and bytes=Bytes.create 65536 in
  let rec loop n = let got=input ic bytes 0 (Bytes.length bytes) in
   if n+got>128*1024*1024 then failwith "oracle identity grew";
   if got>0 then (digest#add_substring bytes 0 got;loop(n+got)) in
  loop 0;
  let after=Unix.fstat (Unix.descr_of_in_channel ic) in
  if (before.st_dev,before.st_ino,before.st_kind,before.st_size,before.st_mtime,before.st_ctime)<>
     (after.st_dev,after.st_ino,after.st_kind,after.st_size,after.st_mtime,after.st_ctime)
  then failwith "oracle executable changed while hashing";
  digest#result |> Cryptokit.transform_string (Cryptokit.Hexa.encode ()))
type oracle = Sha256 | Z3
let binary = function Sha256 -> "/usr/bin/sha256sum" | Z3 -> "/home/an/dev/ver/zigvm/_opam/bin/z3"
let support = ["/usr/bin/bwrap";"/usr/bin/prlimit";"/lib64/ld-linux-x86-64.so.2";
 "/usr/lib/x86_64-linux-gnu/libc.so.6";"/usr/lib/x86_64-linux-gnu/libstdc++.so.6";
 "/usr/lib/x86_64-linux-gnu/libm.so.6";"/usr/lib/x86_64-linux-gnu/libgcc_s.so.1";
 "/usr/lib/x86_64-linux-gnu/libselinux.so.1";"/usr/lib/x86_64-linux-gnu/libpcre2-8.so.0";
 "/usr/lib/x86_64-linux-gnu/libcap.so.2";"/usr/lib/x86_64-linux-gnu/libsmartcols.so.1"]
(* Observed ELF dependency closure of these four fixed binaries on this host.
   A different host/toolchain must revise this list and invalidate candidates.
   This fingerprints the executable closure, not the host kernel or all /usr. *)
let identity oracle = List.map(fun p -> p,hash_file p) (binary oracle::support)
type execution = { input:string; output:string; error:string; exit_code:int;
 elapsed:float; fault:string option; identity:(string*string) list; argv:string list }
let command oracle ~version =
 let local=binary oracle in
 let target=match oracle with Sha256 -> local | Z3 -> "/oracle/z3" in
 let args=if version then ["--version"] else match oracle with Sha256 -> ["-"] | Z3 -> ["-in";"-smt2";"-T:3"] in
 let argv=["/usr/bin/prlimit";"--as=268435456";"--cpu=5";"--nofile=64";"--core=0";"--";
  "/usr/bin/bwrap";"--unshare-all";"--die-with-parent";"--new-session";"--clearenv";
  "--ro-bind";"/usr";"/usr";"--ro-bind";"/lib";"/lib";"--ro-bind";"/lib64";"/lib64";
  "--proc";"/proc";"--dev";"/dev";"--tmpfs";"/tmp";"--chdir";"/tmp";
  "--setenv";"LC_ALL";"C"] @
  (match oracle with Sha256 -> [] | Z3 -> ["--dir";"/oracle";"--ro-bind";local;target]) @ [target] @ args in argv
let run oracle ~version input =
 if String.length input>65536 then failwith "oracle input exceeds 64 KiB";
 let identity_before=identity oracle in
 let argv=command oracle ~version in
 let temp=Filename.temp_file "uos-fixed-oracle-" ".input" in
 let oc=open_out_bin temp in output_string oc input;close_out oc;
 let input_fd=Unix.openfile temp [Unix.O_RDONLY;Unix.O_CLOEXEC] 0 in
 Sys.remove temp;
 let out_r,out_w=Unix.pipe ~cloexec:true () and err_r,err_w=Unix.pipe ~cloexec:true () in
 let started=Mtime_clock.counter () in
 let elapsed ()=Mtime.Span.to_float_ns(Mtime_clock.count started)/.1e9 in
 let pid=try Unix.fork () with e -> List.iter Unix.close [input_fd;out_r;out_w;err_r;err_w];raise e in
 if pid=0 then (try
  ignore(Unix.setsid());Unix.dup2 input_fd Unix.stdin;Unix.dup2 out_w Unix.stdout;Unix.dup2 err_w Unix.stderr;
  List.iter Unix.close [input_fd;out_r;out_w;err_r;err_w];
  Unix.execve "/usr/bin/prlimit" (Array.of_list argv) [|"PATH=/usr/bin:/bin";"LC_ALL=C"|]
 with _ -> Unix._exit 127);
 List.iter Unix.close [input_fd;out_w;err_w];
 Unix.set_nonblock out_r;Unix.set_nonblock err_r;
 let streams=ref [out_r;err_r] and output=Buffer.create 256 and error=Buffer.create 256 in
 let fault=ref None and status=ref None in
 let kill () = List.iter(fun p -> try Unix.kill p Sys.sigkill with Unix.Unix_error(Unix.ESRCH,_,_)->()) [-pid;pid] in
 let stop why=if !fault=None then (fault:=Some why;kill()) in
 let reap () = if !status=None then match Unix.waitpid [Unix.WNOHANG] pid with 0,_ -> () | _,st -> status:=Some st in
 let close fd=try Unix.close fd with Unix.Unix_error(Unix.EBADF,_,_)->() in
 Fun.protect ~finally:(fun () ->
  List.iter close !streams;
  if !status=None then (kill();ignore(Unix.waitpid [] pid))) (fun () ->
  let bytes=Bytes.create 4096 in
  while !streams<>[] || !status=None do
   if elapsed()>8. then stop "deadline";
   if elapsed()>10. then (List.iter close !streams;streams:=[]);
   let readable,_,_=Unix.select !streams [] [] 0.02 in
   List.iter (fun fd ->
    try let n=Unix.read fd bytes 0 (Bytes.length bytes) in
     if n=0 then (close fd;streams:=List.filter ((<>)fd) !streams)
     else let b=if fd=out_r then output else error in
       if Buffer.length output+Buffer.length error+n>65536 then stop "output_limit"
       else Buffer.add_subbytes b bytes 0 n
    with Unix.Unix_error((Unix.EAGAIN|Unix.EWOULDBLOCK),_,_)->()) readable;
   reap ()
  done);
 let exit_code=match !status with Some(Unix.WEXITED n)->n | Some(Unix.WSIGNALED n)|Some(Unix.WSTOPPED n)->128+n | None->255 in
 let identity_after=identity oracle in
 if identity_after<>identity_before then fault:=Some "executable_identity_changed";
 {input;output=Buffer.contents output;error=Buffer.contents error;exit_code;elapsed=elapsed();fault= !fault;identity=identity_before;argv}
