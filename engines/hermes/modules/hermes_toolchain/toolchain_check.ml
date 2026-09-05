(* The toolchain as a CHECKED artifact — the IO shell. The derivation
   lives in Toolchain_core, which the test links directly.

   Before this existed, "the switch is broken" was folklore: an agent
   discovered it by running a build, watching it fail, and switching to a
   workaround switch whose name lived only in a handover document. The
   repository's own sync gate named a switch that PROVABLY cannot build
   this workspace.

   WHY OCAML 5.5 NEEDS PINS. The Jane Street v0.18 preview stack does not
   compile against 5.5 unpatched — `ppxlib_jane` fails first, measured.
   The working switch carries 31 pins to locally patched sources
   (`vendor/ocaml-5.5-patches` records every base commit and expected git
   TREE). A switch without those pins resolves upstream and cannot build.

   FAIL CLOSED, INCLUDING ON ITSELF. An unknown state is a failure, never
   a pass — and "I scanned nothing" is an unknown state, not a clean bill
   of health. The first cut exited 0 with "OK — this switch can build the
   workspace" whenever it was run from a directory without `modules/`. *)

let repo_root = Sys.getcwd ()

let read_file path =
  try
    let ic = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Some (really_input_string ic (in_channel_length ic)))
  with _ -> None

let rec dune_files dir acc =
  match Sys.readdir dir with
  | entries ->
      Array.to_list entries |> List.sort compare
      |> List.fold_left
           (fun acc e ->
             let p = Filename.concat dir e in
             if e = "_build" || e = ".git" then acc
             else if (try Sys.is_directory p with _ -> false) then dune_files p acc
             else if e = "dune" then p :: acc
             else acc)
           acc
  | exception _ -> acc

(* TOTAL, and the child is always reaped. `match Unix.open_process_in c
   with | ic -> BODY | exception _` guards the SCRUTINEE only: a Sys_error
   from the read, or a Unix_error from close, escaped — leaking the
   descriptor and killing the gate with a bare backtrace. Returns the
   output, whether the command succeeded, and whether it ran at all. *)
let run_capture cmd =
  match Unix.open_process_in cmd with
  | exception _ -> None
  | ic ->
      let buf = Buffer.create 256 in
      let ok =
        try
          (try
             while true do
               Buffer.add_channel buf ic 1
             done
           with End_of_file -> ());
          true
        with _ -> false
      in
      let status = try Unix.close_process_in ic with _ -> Unix.WEXITED 127 in
      if ok then Some (String.trim (Buffer.contents buf), status = Unix.WEXITED 0) else None

let probe cmd = match run_capture cmd with Some (v, true) -> v | _ -> ""

let refuse fmt =
  Printf.ksprintf
    (fun s ->
      print_string s;
      print_endline "toolchain_check: REFUSED";
      exit 1)
    fmt

let () =
  let scanned_root = Filename.concat repo_root "modules" in
  let files = dune_files scanned_root [] in
  Printf.printf "toolchain_check — %d dune files scanned under %s\n" (List.length files)
    scanned_root;
  (* A VACUOUS PASS IS THE ONE FAILURE A FAIL-CLOSED GATE MUST NOT HAVE.
     Scanning nothing used to print OK and exit 0. *)
  if files = [] then
    refuse
      "  [L0/product environment] REFUSED: no dune files found under %s\n\
      \    cause: the gate scanned nothing, which is an UNKNOWN state, not a clean one\n\
      \    fix:   run from the repository root (the gate resolves modules/ relative to cwd)\n"
      scanned_root;
  let used, defined =
    List.fold_left
      (fun (u, d) f ->
        match read_file f with
        | None ->
            (* an unreadable dune file means the derivation is INCOMPLETE *)
            refuse "  [L0/product environment] REFUSED: cannot read %s\n" f
        | Some text ->
            ( Toolchain_core.libraries_of_dune text @ Toolchain_core.pps_of_dune text @ u,
              Toolchain_core.defined_in_dune text @ d ))
      ([], []) files
  in
  let used = List.sort_uniq compare used and defined = List.sort_uniq compare defined in
  let required = Toolchain_core.external_libraries ~used ~defined in
  if required = [] then
    refuse
      "  [L0/product environment] REFUSED: derived ZERO external libraries from %d dune files\n\
      \    cause: this workspace demonstrably uses external libraries, so an empty\n\
      \           derivation means the parse failed, not that nothing is needed\n"
      (List.length files);
  let ocaml_version = probe "ocamlfind ocamlopt -version 2>/dev/null" in
  let dune_version = probe "dune --version 2>/dev/null" in
  (* `opam switch show` blocks on opam's global lock, and stderr is
     discarded, so a held lock hung the gate SILENTLY. It is display-only
     information, so it is not worth waiting for. *)
  let switch = probe "opam switch show --safe 2>/dev/null" in
  Printf.printf "  switch  %s\n  ocaml   %s\n  dune    %s\n"
    (if switch = "" then "(undetermined — not part of the verdict)" else switch)
    (if ocaml_version = "" then "UNDETERMINED" else ocaml_version)
    (if dune_version = "" then "UNDETERMINED" else dune_version);
  (* Is findlib itself present? Without this, every library is reported
     missing and all 14 diagnostics blame the Jane Street pin set for
     what is actually "ocamlfind is not installed". *)
  let findlib = run_capture "ocamlfind list 2>/dev/null" in
  if findlib = None || probe "ocamlfind printconf destdir 2>/dev/null" = "" then
    refuse
      "  [L0/product environment] REFUSED: ocamlfind is absent or not configured\n\
      \    cause: without findlib no library can be located, so every answer below\n\
      \           would be a guess dressed as a measurement\n\
      \    fix:   activate a switch (see docs/hermes/toolchain.md)\n";
  let missing =
    List.filter
      (fun lib ->
        match run_capture (Printf.sprintf "ocamlfind query %s 2>/dev/null" (Filename.quote lib)) with
        | Some (_, true) -> false
        | _ -> true)
      required
  in
  Printf.printf "  required external libraries: %d\n" (List.length required);
  List.iter
    (fun lib ->
      Printf.printf
        "  [L0/product environment] MISSING %s\n\
        \    cause: the active switch does not provide it; on OCaml 5.5 the Jane Street\n\
        \           stack needs the patched pins recorded in vendor/ocaml-5.5-patches\n\
        \    fix:   build with a switch carrying those pins (docs/hermes/toolchain.md)\n"
        lib)
    missing;
  let approval_crypto_manifest_path =
    Filename.concat repo_root
      "vendor/ocaml-dependency-provenance/mirage-crypto-ec-2.2.0.sexp"
  in
  let installed_approval_crypto_version =
    match
      run_capture
        "ocamlfind query -format '%v' mirage-crypto-ec 2>/dev/null"
    with
    | Some (version, true) when version <> "" -> Some version
    | _ -> None
  in
  let approval_crypto_self_test =
    try Some (Dependability_approval_crypto.provider_self_test ())
    with _ -> None
  in
  begin
    match
      Toolchain_core.validate_approval_crypto_supply_chain
        ~derived_packages:required
        ~installed_version:installed_approval_crypto_version
        ~provenance_manifest:(read_file approval_crypto_manifest_path)
        ~provider_self_test:approval_crypto_self_test
    with
    | Ok () ->
        print_endline
          "  approval crypto: mirage-crypto-ec 2.2.0 provenance and self-test OK"
    | Error refusals ->
        List.iter
          (fun refusal ->
            Printf.printf
              "  [L2/adapterAuthority environment] APPROVAL-CRYPTO REFUSED\n\
              \    cause: %s\n\
              \    fix:   restore the checked manifest or activate the exact pre-provisioned switch; this gate never installs, pins, downloads, or signs\n"
              (Toolchain_core.string_of_approval_crypto_refusal refusal))
          refusals;
        refuse "  approval-crypto supply-chain evidence refused (%d finding%s)\n"
          (List.length refusals)
          (if List.length refusals = 1 then "" else "s")
  end;
  if ocaml_version <> "5.5.0" then
    refuse
      "  [L0/product environment] REFUSED: ocaml is %s, the workspace declares 5.5.0\n"
      (if ocaml_version = "" then "UNDETERMINED" else ocaml_version);
  (* dune was captured and printed but never checked: a PATH without dune
     printed UNDETERMINED and then OK. *)
  if dune_version = "" then
    refuse
      "  [L0/product environment] REFUSED: dune is UNDETERMINED\n\
      \    cause: the workspace declares dune >= 3.0 and the build cannot run without it\n";
  if missing <> [] then
    refuse "  %d required librar%s missing\n" (List.length missing)
      (if List.length missing = 1 then "y is" else "ies are");
  print_endline "toolchain_check: OK — this switch provides every derived dependency"
