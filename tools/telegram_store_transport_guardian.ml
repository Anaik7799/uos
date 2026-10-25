(* Storage-only compiled guardian. No shell, no runtime compiler.
   Cooperative Unix boundary: descendants that escape the owned session require
   the service cgroup. Exit126 means cleanup was not observed, never safe retry. *)
open Unix
let maximum=1048576
let now()=Mtime.Span.to_float_ns(Mtime_clock.elapsed())/.1e9
exception Deadline
let close_noerr fd=try close fd with _->()
let fail()=raise(Failure "transport")
let length b=let n=ref 0L in for i=0 to 3 do n:=Int64.logor(Int64.shift_left !n 8)(Int64.of_int(Char.code(Bytes.get b i)))done; !n
let ()=
 let child=ref None and input=ref None and output=ref None in
 let cleanup()=
  (match !input with Some fd->close_noerr fd|_->());
  (match !output with Some fd->close_noerr fd|_->());
  match !child with None->true|Some pid->
   (try kill(-pid)Sys.sigkill with _->());(try kill pid Sys.sigkill with _->());
   let until=now()+.0.5 in
   let rec reap()=try match waitpid[WNOHANG]pid with
    |0,_->if now()>=until then false else(sleepf 0.002;reap())
    |_->true
   with Unix_error(EINTR,_,_)->reap()|Unix_error(ECHILD,_,_)->true in reap() in
 let deadline=ref(now()+.5.)in
 let check()=if now()>= !deadline then raise Deadline in
 let select_io reads writes=
  check();select reads writes [] (max 0. (min 0.01 (!deadline-.now())))in
 let exact fd b off count=
  let rec loop pos=if pos<count then(
   let r,_,_=select_io[fd][]in
   if r<>[]then(let n=read fd b(off+pos)(count-pos)in if n=0 then fail();loop(pos+n))
   else loop pos)in loop 0 in
 try
  if Array.length Sys.argv<>4 then fail();
  let ms=int_of_string Sys.argv.(3)in if ms<=0||ms>5000 then fail();
  deadline:=now()+.float_of_int ms/.1000.;
  List.iter(fun signal->Sys.set_signal signal(Sys.Signal_handle(fun _->raise Deadline)))
   [Sys.sigterm;Sys.sighup;Sys.sigpipe];
  let header=Bytes.create 4 in exact stdin header 0 4;
  let n64=length header in if n64<=0L||n64>1048572L then fail();
  let n=Int64.to_int n64 in
  let frame=Bytes.create(n+4)in Bytes.blit header 0 frame 0 4;exact stdin frame 4 n;
  let r,_,_=select[stdin][][]0. in if r<>[]then fail();
  check();
  let child_in,parent_in=pipe ~cloexec:true()in
  let parent_out,child_out=pipe ~cloexec:true()in
  let pid=fork()in
  if pid=0 then(try
   ignore(setsid());close parent_in;close parent_out;
   dup2 child_in stdin;dup2 child_out stdout;
   let null=openfile "/dev/null"[O_WRONLY]0 in dup2 null stderr;
   close_noerr null;close_noerr child_in;close_noerr child_out;
   execve Sys.argv.(1)[|Sys.argv.(1);Sys.argv.(2)|](environment())
  with _->_exit 127);
  child:=Some pid;close child_in;close child_out;
  input:=Some parent_in;output:=Some parent_out;
  set_nonblock parent_in;set_nonblock parent_out;
  let sent=ref 0 and eof=ref false and chunks=Buffer.create 8192 and buf=Bytes.create 8192 in
  let group_stopped=ref false in
  let stop_if_exited()=if not !group_stopped then(
   let ch=open_in_bin(Printf.sprintf "/proc/%d/stat"pid)in
   let line=Fun.protect(fun()->input_line ch)~finally:(fun()->close_in_noerr ch)in
   let boundary=String.rindex line ')'in
   if line.[boundary+2]='Z'then((try kill(-pid)Sys.sigkill with Unix_error(ESRCH,_,_)->());group_stopped:=true))in
  let rec pump()=
   check();stop_if_exited();
   let reads=stdin::(if !eof then[]else[parent_out])in
   let writes=if !sent<Bytes.length frame then[parent_in]else[]in
   let ready,writable,_=select_io reads writes in
   if List.mem stdin ready then raise Deadline;
   if List.mem parent_in writable then(
    let n=try write parent_in frame !sent(Bytes.length frame- !sent)with Unix_error((EAGAIN|EWOULDBLOCK),_,_)->0 in
    sent:= !sent+n;
    if !sent=Bytes.length frame then(close parent_in;input:=None));
   if List.mem parent_out ready then(
    let n=try read parent_out buf 0 8192 with Unix_error((EAGAIN|EWOULDBLOCK),_,_)-> -1 in
    if n=0 then(eof:=true;close parent_out;output:=None)
    else if n>0 then(
     if Buffer.length chunks+n>maximum then fail();
     Buffer.add_subbytes chunks buf 0 n));
   if not !eof then pump()
  in pump();
  (* Keep PID unreaped while cleaning its process group, even normal exits. *)
  let rec exited()=
   check();
   let ch=open_in_bin(Printf.sprintf "/proc/%d/stat"pid)in
   let line=Fun.protect(fun()->input_line ch)~finally:(fun()->close_in_noerr ch)in
   let boundary=String.rindex line ')'in
   if line.[boundary+2]<>'Z'then(sleepf 0.002;exited())in exited();
  (try kill(-pid)Sys.sigkill with Unix_error(ESRCH,_,_)->());
  let _,status=waitpid[]pid in child:=None;
  (match status with WEXITED 0->()|_->fail());
  let response=Buffer.to_bytes chunks in
  if Bytes.length response<4 then fail();
  let body=length response in
  if body<=0L||body<>Int64.of_int(Bytes.length response-4)then fail();
  set_nonblock stdout;
  let rec emit pos=if pos<Bytes.length response then(
   let _,ready,_=select_io[][stdout]in
   if ready=[]then emit pos else
   let n=try write stdout response pos(Bytes.length response-pos)with Unix_error((EAGAIN|EWOULDBLOCK),_,_)->0 in emit(pos+n))in
  emit 0;check();exit 0
 with
 |Deadline->exit(if cleanup()then 124 else 126)
 |_->exit(if cleanup()then 125 else 126)
