(* Provisions a jj workspace with the gitignored state a trustworthy test run
   needs (INV-WS-08/09). Nothing here is tracked; every step is checked.

   1. toolchains/<entry>            -> symlinks to the canonical toolchains
   2. services/inference/max/.pixi/envs -> symlink to the canonical pixi envs
   3. apps/cepaf_gleam/priv/<nif>.so -> copied from the first candidate whose
      sha256 equals priv/<nif>.sha256: the workspace's own build output, the
      content-addressed store var/recovery-runtime/nif-artifacts/<sha256>/, then
      the canonical priv. A NIF with no matching candidate is reported, never
      substituted.
   4. var/recovery-runtime/test-fixtures/ecology_budget.exe -> built by
      tools/validation/build_ecology_budget_exe.ml when absent.

   Usage: ocaml -I +unix unix.cma tools/provision_workspace.ml [--build] <workspace_root>
   --build compiles a NIF from tracked source when no existing artifact matches
   its pin. Exit 0 only when every step is satisfied. *)

let canonical = "/home/an/NAS-setup/uos"

let nif_sources = [
  "c3i_nif", "apps/cepaf_gleam/native/c3i_nif";
  "rule_engine_nif", "apps/cepaf_gleam/native/rule_engine_nif";
  "planning_nif", "apps/cepaf_gleam/native/planning_nif";
  "rusty_vault_nif", "apps/cepaf_gleam/native/rusty_vault_nif";
  "ferriskey_nif", "native/nifs/rust/ferriskey_nif";
  "cortex_nif", "native/nifs/rust/cortex_nif";
  "zenoh_nif", "native/nifs/rust/zenoh_nif";
]

let failures = ref 0
let report ok msg =
  Printf.printf "%s %s\n" (if ok then "OK  " else "FAIL") msg;
  if not ok then incr failures

let exists p = Sys.file_exists p
let is_symlink p = try (Unix.lstat p).Unix.st_kind = Unix.S_LNK with Unix.Unix_error _ -> false

let read_file p =
  let ic = open_in_bin p in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic; s

(* OCaml's stdlib has no SHA-256; use the host coreutils binary. *)
let sha256 p =
  let ic = Unix.open_process_args_in "/usr/bin/sha256sum" [| "sha256sum"; p |] in
  let line = try input_line ic with End_of_file -> "" in
  ignore (Unix.close_process_in ic);
  match String.index_opt line ' ' with Some i -> String.sub line 0 i | None -> ""

let pin_of p =
  let s = String.trim (read_file p) in
  match String.index_opt s ' ' with Some i -> String.sub s 0 i | None -> s

let copy src dst =
  let data = read_file src in
  let oc = open_out_gen [Open_wronly; Open_creat; Open_trunc; Open_binary] 0o755 dst in
  output_string oc data; close_out oc

let link_entry ws rel target =
  let path = Filename.concat ws rel in
  if exists path || is_symlink path then report (exists path) ("present " ^ rel)
  else begin
    (try Unix.symlink target path with Unix.Unix_error (e, _, _) ->
       report false (rel ^ ": " ^ Unix.error_message e));
    report (exists path) ("linked " ^ rel ^ " -> " ^ target)
  end

(* Builds one NIF from tracked source with the in-project toolchains. Rust uses
   the in-project CARGO_HOME and the tracked Cargo.lock (--offline --locked,
   after a checksum-verified fetch); OCaml and Mojo use their tracked scripts. *)
let build_nif ws n =
  let env = Printf.sprintf
      "export UOS_ROOT=%s; . %s/tools/lib/uos-toolchain.sh >/dev/null 2>&1; uos_env >/dev/null 2>&1; \
       export CARGO_HOME=$UOS_ROOT/toolchains/cargo RUSTUP_HOME=$UOS_ROOT/toolchains/rustup PATH=$UOS_ROOT/toolchains/cargo/bin:$PATH; "
      canonical canonical in
  let cmd = match List.assoc_opt n nif_sources, n with
    | Some src, _ ->
      Printf.sprintf "cd %s && cargo fetch --locked && cargo build --release --offline --locked --lib"
        (Filename.quote (Filename.concat ws src))
    | None, "c3i_ocaml_nif" ->
      Printf.sprintf "bash %s" (Filename.quote (Filename.concat ws "apps/cepaf_gleam/native/ocaml_nif/build.sh"))
    | None, ("uos_km_nif" | "uos_km_nif_otp29" | "libuos_km_kernel") ->
      Printf.sprintf "cd %s && make all otp29" (Filename.quote (Filename.concat ws "native/nifs/mojo"))
    | None, _ -> "false" in
  Printf.printf "BUILD %s\n%!" n;
  ignore (Sys.command ("bash -c " ^ Filename.quote (env ^ cmd ^ " >/dev/null 2>&1")))

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  let build = List.mem "--build" args in
  let ws = match List.filter (fun a -> a <> "--build") args with
    | w :: _ -> w | [] -> Sys.getcwd () in
  if ws = canonical then (prerr_endline "refusing to provision the canonical checkout"; exit 2);
  (* 1. toolchains *)
  let tc = Filename.concat ws "toolchains" in
  if not (exists tc) then Unix.mkdir tc 0o755;
  Array.iter (fun e -> link_entry ws ("toolchains/" ^ e) (Filename.concat (canonical ^ "/toolchains") e))
    (Sys.readdir (canonical ^ "/toolchains"));
  (* 2. pixi envs *)
  let pixi = Filename.concat ws "services/inference/max/.pixi" in
  if not (exists pixi) then Unix.mkdir pixi 0o755;
  link_entry ws "services/inference/max/.pixi/envs" (canonical ^ "/services/inference/max/.pixi/envs");
  (* 3. NIFs by pin *)
  let priv = Filename.concat ws "apps/cepaf_gleam/priv" in
  Array.iter (fun f ->
      if Filename.check_suffix f ".sha256" then begin
        let n = Filename.chop_suffix f ".sha256" in
        let want = pin_of (Filename.concat priv f) in
        let dst = Filename.concat priv (n ^ ".so") in
        if exists dst && sha256 dst = want then report true ("pinned " ^ n)
        else begin
          let built = match List.assoc_opt n nif_sources with
            | Some src -> [Filename.concat ws (src ^ "/target/release/lib" ^ n ^ ".so")]
            | None -> [] in
          (* The content-addressed store holds every pinned build; it is the only
             source for crates whose builds embed compile-time randomness
             (rusty_vault_nif) and so cannot be rebuilt byte-identically. *)
          let store = Printf.sprintf "%s/var/recovery-runtime/nif-artifacts/%s/%s.so" canonical want n in
          let candidates = built @ [store; Filename.concat (canonical ^ "/apps/cepaf_gleam/priv") (n ^ ".so")] in
          let pick () = List.find_opt (fun c -> exists c && sha256 c = want) candidates in
          let found = match pick () with
            | Some c -> Some c
            | None when build -> build_nif ws n; pick ()
            | None -> None in
          match found with
          | Some c -> copy c dst; report (sha256 dst = want) ("installed " ^ n ^ " from " ^ c)
          | None ->
            (* OCaml and Mojo builds install into priv directly. *)
            if exists dst && sha256 dst = want then report true ("built " ^ n)
            else report false ("no candidate matches pin for " ^ n ^ " (rerun with --build)")
        end
      end)
    (Sys.readdir priv);
  (* 4. budget fixture *)
  let exe = canonical ^ "/var/recovery-runtime/test-fixtures/ecology_budget.exe" in
  if not (exists exe) then
    ignore (Sys.command (Printf.sprintf "ocaml %s %s"
              (Filename.quote (Filename.concat ws "tools/validation/build_ecology_budget_exe.ml"))
              (Filename.quote ws)));
  report (exists exe) ("fixture " ^ exe);
  if !failures > 0 then (Printf.printf "%d step(s) unprovisioned\n" !failures; exit 1)
  else print_endline "workspace provisioned"
