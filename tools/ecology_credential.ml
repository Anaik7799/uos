#!/usr/bin/env -S opam exec -- ocaml
#directory "+unix";;
#load "unix.cma";;

(* Provision one service-private encrypted credential from the approved process
   environment. No plaintext file, argv value, digest, or log is produced. The
   systemd user manager decrypts it at service start. No existing file is replaced.
   Commands: provision | status. Requires an already installed systemd-creds. *)
let require b message = if not b then failwith message
let root = "/home/an/.config/uos-ecology"
let directory = root ^ "/credentials"
let destination = directory ^ "/openrouter_api_key.cred"
let valid_key k = String.length k > 0 && String.length k <= 8192 &&
  String.for_all (fun c -> let n=Char.code c in n>=33 && n<=126) k
let private_dir path =
  if not (Sys.file_exists path) then Unix.mkdir path 0o700;
  let st=Unix.lstat path in
  require (st.st_kind=Unix.S_DIR && st.st_uid=Unix.getuid() && st.st_perm land 0o077=0)
    "credential directory must be private and owned by this user"
let encrypt key =
  let input_r,input_w=Unix.pipe ~cloexec:true () in
  let output_r,output_w=Unix.pipe ~cloexec:true () in
  let env=Unix.environment() |> Array.to_list
    |> List.filter (fun v -> not (String.starts_with ~prefix:"OPENROUTER_API_KEY=" v))
    |> Array.of_list in
  let pid=Unix.create_process_env "/usr/bin/systemd-creds"
    [|"systemd-creds";"encrypt";"--user";"--name=openrouter_api_key";"-";"-"|]
    env input_r output_w Unix.stderr in
  Unix.close input_r;Unix.close output_w;
  let timed_out=ref false and reaped=ref false in
  let old=Sys.signal Sys.sigalrm (Sys.Signal_handle(fun _ ->
    timed_out:=true;try Unix.kill pid Sys.sigkill with Unix.Unix_error _->())) in
  ignore(Unix.setitimer Unix.ITIMER_REAL {Unix.it_interval=0.;it_value=15.});
  Fun.protect (fun () ->
    let oc=Unix.out_channel_of_descr input_w in
    Fun.protect (fun()->output_string oc key;flush oc) ~finally:(fun()->close_out_noerr oc);
    let ic=Unix.in_channel_of_descr output_r and b=Buffer.create 4096 in
    Fun.protect (fun()->try while true do
      let c=input_char ic in require(Buffer.length b < 32768) "encrypted output bound";
      Buffer.add_char b c done with End_of_file->()) ~finally:(fun()->close_in_noerr ic);
    let _,status=Unix.waitpid [] pid in
    reaped:=true;
    require(not !timed_out && status=Unix.WEXITED 0) "systemd credential encryption unavailable";
    require(Buffer.length b>100) "empty encrypted credential";Buffer.contents b)
    ~finally:(fun()->ignore(Unix.setitimer Unix.ITIMER_REAL {Unix.it_interval=0.;it_value=0.});
      ignore(Sys.signal Sys.sigalrm old);
      if not !reaped then (
        (try Unix.kill pid Sys.sigkill with Unix.Unix_error _->());
        (try ignore(Unix.waitpid [] pid) with Unix.Unix_error _->())))
let provision () =
  require(not(Sys.file_exists destination)) "credential already exists; explicit rotation required";
  let key=match Sys.getenv_opt "OPENROUTER_API_KEY" with Some k when valid_key k->k
    |_ -> failwith "approved environment credential missing or invalid" in
  let ciphertext=encrypt key in
  private_dir root;private_dir directory;
  let fd=Unix.openfile destination [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC] 0o600 in
  let oc=Unix.out_channel_of_descr fd in
  Fun.protect(fun()->output_string oc ciphertext;flush oc;Unix.fsync fd)
    ~finally:(fun()->close_out_noerr oc);
  print_endline "{\"encrypted_credential_provisioned\":true,\"plaintext_persisted\":false}"
let () = try
  match Array.to_list Sys.argv with
  | [_;"provision"] -> provision()
  | [_;"status"] -> Printf.printf "{\"encrypted_credential_present\":%b}\n" (Sys.file_exists destination)
  | _ -> failwith "usage: ecology_credential.ml provision | status"
  with Failure message -> prerr_endline message;exit 1
