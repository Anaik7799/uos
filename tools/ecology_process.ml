#load "unix.cma";;
(* Isolated process-group guardian for ecology capabilities. No shell expansion.
   @agent_intent: Bound execution time, output and the owned process group.
   @laws: The one-shot elapsed-time deadline never resets; every exit reaps the
   owned child and terminates its group before the PID can be reused.
   Children that create new sessions require the service cgroup boundary;
   this helper alone does not contain deliberately escaping executables. *)
open Unix
let require c m = if not c then failwith m
let () =
  let args=Array.to_list Sys.argv |> List.tl in
  match args with
  | timeout::limit::mode::exe::argv ->
    let ms=int_of_string timeout and maximum=int_of_string limit in
    require(ms>0 && ms<=60000 && maximum>0 && maximum<=1048576) "invalid resource bound";
    require(not(Filename.is_relative exe) && not(String.contains exe '\000')) "invalid executable";
    require(mode="merged" || mode="framed") "invalid output mode";
    let input,output=pipe ~cloexec:true () in
    let pid=fork() in
    if pid=0 then (
      try
        ignore(setsid()); close input; dup2 output stdout;
        if mode="merged" then dup2 output stderr
        else (let null=openfile "/dev/null" [O_WRONLY] 0 in dup2 null stderr;close null);
        close output;
        execve exe (Array.of_list(exe::argv)) (environment())
      with _ -> _exit 127
    );
    close output;
    let killed=ref false in
    let cleanup() = if not !killed then (
      killed:=true;
      (try kill (-pid) Sys.sigkill with Unix_error(ESRCH,_,_)->());
      (try kill pid Sys.sigkill with Unix_error(ESRCH,_,_)->());
      ignore(waitpid [] pid);
      close input
    ) in
    (* One-shot elapsed-time OS alarm; no output resets it. *)
    Sys.set_signal Sys.sigalrm (Sys.Signal_handle(fun _->raise Exit));
    Sys.set_signal Sys.sigterm (Sys.Signal_handle(fun _->raise Exit));
    Sys.set_signal Sys.sighup (Sys.Signal_handle(fun _->raise Exit));
    ignore(setitimer ITIMER_REAL {it_interval=0.;it_value=float_of_int ms /.1000.});
    let bytes=Bytes.create 8192 and count=ref 0 in
    (try
      let rec pump() =
        let n=read input bytes 0 (Bytes.length bytes) in
        if n<>0 then (
          count:= !count+n; require(!count<=maximum) "output_limit";
          let rec emit pos = if pos<n then emit(pos+write stdout bytes pos (n-pos)) in
          emit 0; pump()
        ) in
      pump();
      (* Keep child unreaped until its process group is cleaned. *)
      (try kill (-pid) Sys.sigkill with Unix_error(ESRCH,_,_)->());
      let _,status=waitpid [] pid in killed:=true;close input;
      ignore(setitimer ITIMER_REAL {it_interval=0.;it_value=0.});
      exit(match status with WEXITED n->n|WSIGNALED _|WSTOPPED _->125)
    with
    | Exit -> cleanup(); exit 124
    | _ -> cleanup(); exit 125)
  | _ -> failwith "usage: timeout-ms output-limit merged|framed executable args..."
