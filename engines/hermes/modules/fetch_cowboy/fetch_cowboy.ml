(* fetch_cowboy.ml — orchestrate the cowboy / ranch / cowlib dependency fetch so
   zigvm can boot a stock Cowboy tree (unblocks http-laneC-cowboy-bif-subset).

   OCaml is the project's orchestration language (harness/ is OCaml-only); this
   is an ISOLATED executable (its own dune) so it never perturbs the main
   zigvm_harness build. It shells out to `rebar3`, compiling the deps with the
   PINNED OTP-30 toolchain (third_party/otp/bin) so the emitted .beam files match
   zigvm's loader, then copies the ebin trees into third_party/ for `--pa` loading.

   NETWORK: `rebar3 compile` pulls cowboy/ranch/cowlib from hex.pm — run this on a
   machine WITH network (the zigvm sandbox has none). Idempotent: re-running
   refreshes the copied trees.

   Run:  dune exec ./harness/fetch_cowboy/fetch_cowboy.exe -- [REPO_ROOT] [COWBOY_VSN]
   e.g.  dune exec ./harness/fetch_cowboy/fetch_cowboy.exe -- "$PWD" 2.12.0 *)

let run fmt =
  Printf.ksprintf
    (fun cmd ->
      Printf.eprintf "+ %s\n%!" cmd;
      match Sys.command cmd with
      | 0 -> ()
      | n ->
          Printf.eprintf "\nFAILED (exit %d): %s\n%!" n cmd;
          exit n)
    fmt

let write path contents =
  let oc = open_out path in
  output_string oc contents;
  close_out oc

let () =
  let arg i default = if Array.length Sys.argv > i then Sys.argv.(i) else default in
  let root = arg 1 (try Sys.getenv "PWD" with Not_found -> ".") in
  let cowboy_vsn = arg 2 "2.12.0" in
  let otp_bin = Filename.concat root "third_party/otp/bin" in
  let work = "/tmp/cowboy_deps" in
  let dest = Filename.concat root "third_party" in

  (* fail fast if the pinned toolchain isn't there — the beams MUST be OTP-30 *)
  if not (Sys.file_exists otp_bin) then (
    Printf.eprintf "no pinned OTP at %s — pass the repo root as arg 1\n%!" otp_bin;
    exit 2);

  (* pin the toolchain on PATH so rebar3's erlc emits OTP-30 bytecode *)
  Unix.putenv "PATH" (otp_bin ^ ":" ^ (try Sys.getenv "PATH" with Not_found -> ""));

  (* a minimal rebar3 project whose sole dep is cowboy (pulls ranch + cowlib) *)
  run "mkdir -p %s/src" work;
  write (Filename.concat work "rebar.config")
    (Printf.sprintf "{deps, [{cowboy, \"%s\"}]}.\n" cowboy_vsn);
  write (Filename.concat work "src/cowboy_deps.app.src")
    "{application, cowboy_deps,\n [{vsn,\"0.1.0\"},{applications,[kernel,stdlib]}]}.\n";

  run "%s/erl -version" otp_bin;
  (* THE NETWORK FETCH + compile (cowboy/ranch/cowlib from hex.pm) *)
  run "cd %s && rebar3 compile" work;

  (* copy the compiled ebin trees into third_party/ for zigvm `--pa` loading *)
  List.iter
    (fun dep -> run "rm -rf %s/%s && cp -r %s/_build/default/lib/%s %s/" dest dep work dep dest)
    [ "cowboy"; "ranch"; "cowlib" ];

  Printf.printf
    "\nOK — beams at %s/{cowboy,ranch,cowlib}/ebin/\nNext: boot a minimal cowboy app on zigvm via `zigvm run … --pa <those beams>` and curate undefs vs OTP-30.\n%!"
    dest
