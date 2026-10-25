#use "topfind";;
#require "unix,bos,cryptokit,yojson";;

(* TEST ONLY: Bounded native OCaml builder for telegram store recovery test fixtures.
   Spec: uos.telegram-durable-store-corrected-development-spec.v1
   Plan: uos/telegram-runtime/20261001-1150

   Compiles only trusted repository test fixture sources into an isolated cache.
   Does not pollute source directories and performs no package installs.

   Compilation Timeout Architecture Note:
   Process execution via Unix.create_process/waitpid relies on the external timeout
   enforced by the Gleam bounded supervisor launcher (`gleam-bound` or supervisor
   child budget) rather than an intrinsic timeout in Unix.waitpid. *)

let root = "/home/an/NAS-setup/uos"

let read p = match Bos.OS.File.read (Fpath.v p) with
  | Ok s -> s
  | Error _ -> failwith ("cannot read " ^ p)

let file_sha256 p =
  let content = read p in
  Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) content
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())

let expected_guardian_sha = "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab"

let publish_atomically ~dest ~content ~mode =
  let dir = Filename.dirname dest in
  let prefix = "." ^ Filename.basename dest ^ ".tmp" in
  let temp_file = Filename.temp_file ~temp_dir:dir prefix ".tmp" in
  let out = open_out_bin temp_file in
  output_string out content;
  close_out out;
  Unix.chmod temp_file mode;
  Unix.rename temp_file dest

let () =
  let tool = root ^ "/toolchains/opam-ocaml/bin/ocamlfind" in

  let guardian_exe = root ^ "/tools/validation/telegram_store_transport_guardian.exe" in
  let guardian_src = root ^ "/tools/telegram_store_transport_guardian.ml" in
  let store_src = root ^ "/native/ocaml/telegram_store/telegram_store.ml" in
  let worker_src = root ^ "/tools/validation/telegram_store_recovery_worker.ml" in
  let worker_exe = root ^ "/tools/validation/telegram_store_recovery_worker.exe" in
  let manifest_path = root ^ "/tools/validation/telegram_store_recovery_manifest.json" in

  (* 1. Verify existing guardian or build from accepted source into private cache *)
  let guardian_sha =
    if Sys.file_exists guardian_exe then (
      let sha = file_sha256 guardian_exe in
      if sha <> expected_guardian_sha then
        failwith ("existing guardian binary sha mismatch: " ^ sha ^ " expected " ^ expected_guardian_sha);
      Printf.printf "Verified %s (%s)\n" guardian_exe sha;
      sha
    ) else (
      let material_g = "guardian\000" ^ read guardian_src in
      let hash_g = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) material_g
                   |> Cryptokit.transform_string (Cryptokit.Hexa.encode ()) in
      let scratch_g = "/tmp/uos-guardian-" ^ hash_g in
      if not (Sys.file_exists scratch_g) then Unix.mkdir scratch_g 0o700;
      let stat_g = Unix.lstat scratch_g in
      if stat_g.Unix.st_kind <> Unix.S_DIR || stat_g.st_uid <> Unix.getuid () || stat_g.st_perm land 0o077 <> 0 then
        failwith "unsafe guardian build directory";
      let scratch_g_src = scratch_g ^ "/telegram_store_transport_guardian.ml" in
      let out_g = open_out_bin scratch_g_src in
      output_string out_g (read guardian_src);
      close_out out_g;
      let target_scratch = scratch_g ^ "/guardian.exe" in
      let prev_cwd = Sys.getcwd () in
      Sys.chdir scratch_g;
      let pid = Unix.create_process tool
        [| tool; "ocamlopt"; "-package"; "unix,mtime.clock"; "-linkpkg";
           "telegram_store_transport_guardian.ml"; "-o"; "guardian.exe" |]
        Unix.stdin Unix.stdout Unix.stderr in
      let status = snd (Unix.waitpid [] pid) in
      Sys.chdir prev_cwd;
      (match status with
       | Unix.WEXITED 0 -> ()
       | _ -> failwith "guardian compilation failed");
      let sha = file_sha256 target_scratch in
      if sha <> expected_guardian_sha then
        failwith ("compiled guardian sha mismatch: " ^ sha ^ " expected " ^ expected_guardian_sha);
      let content = read target_scratch in
      publish_atomically ~dest:guardian_exe ~content ~mode:0o755;
      Printf.printf "Built %s from source (%s)\n" guardian_exe sha;
      sha
    )
  in

  (* 2. Build recovery worker into isolated scratch directory using source basenames *)
  let material = String.concat "\000" [
    "store\000" ^ read store_src;
    "worker\000" ^ read worker_src;
    "guardian_sha\000" ^ guardian_sha;
  ] in
  let hash = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) material
             |> Cryptokit.transform_string (Cryptokit.Hexa.encode ()) in
  let scratch = "/tmp/uos-tg-recovery-" ^ hash in
  if not (Sys.file_exists scratch) then Unix.mkdir scratch 0o700;
  let stat = Unix.lstat scratch in
  if stat.Unix.st_kind <> Unix.S_DIR || stat.st_uid <> Unix.getuid () || stat.st_perm land 0o077 <> 0 then
    failwith "unsafe recovery build directory";

  (* Copy sources with standard basenames into scratch *)
  let scratch_store_src = scratch ^ "/telegram_store.ml" in
  let scratch_worker_src = scratch ^ "/telegram_store_recovery_worker.ml" in
  let out_store = open_out_bin scratch_store_src in
  output_string out_store (read store_src);
  close_out out_store;
  let out_worker = open_out_bin scratch_worker_src in
  output_string out_worker (read worker_src);
  close_out out_worker;

  (* Compile in scratch directory using relative source basenames *)
  let prev_cwd = Sys.getcwd () in
  Sys.chdir scratch;
  let pid = Unix.create_process tool
    [| tool; "ocamlopt"; "-package"; "cryptokit,sqlite3,yojson,unix"; "-linkpkg";
       "telegram_store.ml"; "telegram_store_recovery_worker.ml";
       "-o"; "telegram_store_recovery_worker.exe" |]
    Unix.stdin Unix.stdout Unix.stderr in
  let status = snd (Unix.waitpid [] pid) in
  Sys.chdir prev_cwd;
  (match status with
   | Unix.WEXITED 0 -> ()
   | _ -> failwith "recovery worker compilation failed");

  let scratch_worker_exe = scratch ^ "/telegram_store_recovery_worker.exe" in
  let worker_content = read scratch_worker_exe in
  publish_atomically ~dest:worker_exe ~content:worker_content ~mode:0o755;

  let worker_sha = file_sha256 worker_exe in

  (* 3. Write manifest atomically *)
  let manifest_json = Printf.sprintf "{\n  \"guardian\": {\n    \"path\": \"tools/validation/telegram_store_transport_guardian.exe\",\n    \"sha256\": \"%s\"\n  },\n  \"recovery_worker\": {\n    \"path\": \"tools/validation/telegram_store_recovery_worker.exe\",\n    \"sha256\": \"%s\"\n  }\n}\n"
    guardian_sha worker_sha in
  publish_atomically ~dest:manifest_path ~content:manifest_json ~mode:0o644;

  Printf.printf "Built %s (%s)\n" worker_exe worker_sha
