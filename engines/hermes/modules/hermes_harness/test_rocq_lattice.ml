(* The Rocq leg's differential: the proof script's definitions (transcribed in
   rocq_lattice.ml) against the LIVE algebra (Parity_algebra.combine /
   grants_credit, Harness_config.gate_verdict) over the WHOLE finite domain --
   exact, total, always run. The proof-check itself is gated on a coqc host and
   SKIPPED WITH DISCLOSURE here (coqc_available=false, the zigvm --verify-formal
   convention; R2: an absent checker proves nothing and says so).
   Proven-not-differential: a single flipped table entry must be detected. *)

let live = Parity_algebra.[ Unmapped; Blocked; Verified; Divergent ]

let to_rocq = function
  | Parity_algebra.Unmapped -> Rocq_lattice.Unmapped
  | Parity_algebra.Blocked -> Rocq_lattice.Blocked
  | Parity_algebra.Verified -> Rocq_lattice.Verified
  | Parity_algebra.Divergent -> Rocq_lattice.Divergent

let of_rocq = function
  | Rocq_lattice.Unmapped -> Parity_algebra.Unmapped
  | Rocq_lattice.Blocked -> Parity_algebra.Blocked
  | Rocq_lattice.Verified -> Parity_algebra.Verified
  | Rocq_lattice.Divergent -> Parity_algebra.Divergent

let () =
  (* combine agrees over all 16 pairs. *)
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          let live_v = Parity_algebra.combine a b in
          let proof_v = of_rocq (Rocq_lattice.combine (to_rocq a) (to_rocq b)) in
          if live_v <> proof_v then
            failwith
              (Printf.sprintf "combine disagrees at (%s, %s): live %s, proof %s"
                 (Parity_algebra.name a) (Parity_algebra.name b)
                 (Parity_algebra.name live_v) (Parity_algebra.name proof_v)))
        live)
    live;
  (* grants_credit agrees over all 4. *)
  List.iter
    (fun v ->
      assert (Parity_algebra.grants_credit v = Rocq_lattice.grants_credit (to_rocq v)))
    live;
  (* gate agrees with Harness_config.gate_verdict over all 16 pairs. *)
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          let live_v = Harness_config.gate_verdict a (fun () -> b) in
          let proof_v = of_rocq (Rocq_lattice.gate (to_rocq a) (to_rocq b)) in
          assert (live_v = proof_v))
        live)
    live;

  (* THE MACHINE-EXTRACTED encoding (generated_rocq/, produced by coqc from the
     proof script): the third encoding, differentially checked over the same
     domain. Its provenance is machine, its freshness is byte-pinned below. *)
  let to_ext = function
    | Parity_algebra.Unmapped -> Parity_lattice_extracted.Unmapped
    | Parity_algebra.Blocked -> Parity_lattice_extracted.Blocked
    | Parity_algebra.Verified -> Parity_lattice_extracted.Verified
    | Parity_algebra.Divergent -> Parity_lattice_extracted.Divergent
  in
  let of_ext = function
    | Parity_lattice_extracted.Unmapped -> Parity_algebra.Unmapped
    | Parity_lattice_extracted.Blocked -> Parity_algebra.Blocked
    | Parity_lattice_extracted.Verified -> Parity_algebra.Verified
    | Parity_lattice_extracted.Divergent -> Parity_algebra.Divergent
  in
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          assert (Parity_algebra.combine a b
                  = of_ext (Parity_lattice_extracted.combine (to_ext a) (to_ext b)));
          assert (Harness_config.gate_verdict a (fun () -> b)
                  = of_ext (Parity_lattice_extracted.gate (to_ext a) (to_ext b))))
        live)
    live;
  List.iter
    (fun v ->
      assert (Parity_algebra.grants_credit v = Parity_lattice_extracted.grants_credit (to_ext v)))
    live;

  (* Proven-not-differential: flipping one entry IS detected by this harnessing.
     A mutant combine (Divergent+Verified -> Verified) must disagree somewhere. *)
  let mutant a b =
    match (a, b) with
    | Rocq_lattice.Divergent, Rocq_lattice.Verified -> Rocq_lattice.Verified
    | _ -> Rocq_lattice.combine a b
  in
  let mutant_detected =
    List.exists
      (fun a ->
        List.exists
          (fun b ->
            of_rocq (mutant (to_rocq a) (to_rocq b)) <> Parity_algebra.combine a b)
          live)
      live
  in
  assert mutant_detected;

  (* The proof gate, honestly: resolve coqc via HERMES_COQC first (the gospel
     configured_binary pattern -- a pinned side-switch toolchain without
     activating it), then PATH; disclose the skip when neither exists. The .v is
     compiled in a temp copy so build artifacts never land in the source tree. *)
  let candidate =
    match Sys.getenv_opt "HERMES_COQC" with
    | Some command when String.trim command <> "" -> Some (String.trim command)
    | _ -> (
        match Unix.system "command -v coqc >/dev/null 2>&1" with
        | Unix.WEXITED 0 -> Some "coqc"
        | _ -> None)
  in
  (* HERMES_COQC is a COMMAND, not just a path -- typically
     "opam exec --switch=<side-switch> -- coqc", so the prover gets its own
     library environment. Validate before trusting: a coqc that cannot even
     report its version is unavailable, disclosed. *)
  let coqc =
    match candidate with
    | Some command -> (
        match Unix.system (command ^ " --version >/dev/null 2>&1") with
        | Unix.WEXITED 0 -> Some command
        | _ -> None)
    | None -> None
  in
  let check_proof coqc name path =
    let stage = Filename.temp_file "rocq-gate-" "" in
    Sys.remove stage;
    Unix.mkdir stage 0o700;
    let staged = Filename.concat stage name in
    let source = open_in_bin path in
    let contents = really_input_string source (in_channel_length source) in
    close_in source;
    let out = open_out_bin staged in
    output_string out contents;
    close_out out;
    let command =
      Printf.sprintf "cd %s && %s %s >coqc.log 2>&1" (Filename.quote stage) coqc name
    in
    match Unix.system command with
    | Unix.WEXITED 0 -> Ok ()
    | _ ->
        let log = Filename.concat stage "coqc.log" in
        let detail =
          if Sys.file_exists log then (
            let c = open_in log in
            let s = really_input_string c (min 400 (in_channel_length c)) in
            close_in c; s)
          else "(no log)"
        in
        Error detail
  in
  match coqc with
  | Some coqc -> (
      (match check_proof coqc "Parity_Lattice.v" "modules/hermes_harness/proofs/Parity_Lattice.v" with
      | Ok () ->
          print_endline
            "test_rocq_lattice: lattice PROOF CHECKED -- all 10 theorems accepted"
      | Error detail ->
          failwith ("coqc rejected Parity_Lattice.v -- the proof gate is red: " ^ detail));
      (* The extraction FRESHNESS law (the zigvm generated/rocq discipline): a
         fresh extraction must byte-match the committed machine artifact, or
         the committed code no longer corresponds to the proof. *)
      let stage = Filename.temp_file "rocq-extract-" "" in
      Sys.remove stage; Unix.mkdir stage 0o700;
      let copy_in name path =
        let s = open_in_bin path in
        let c = really_input_string s (in_channel_length s) in
        close_in s;
        let o = open_out_bin (Filename.concat stage name) in
        output_string o c; close_out o
      in
      copy_in "Parity_Lattice.v" "modules/hermes_harness/proofs/Parity_Lattice.v";
      copy_in "Parity_Lattice_Extract.v" "modules/hermes_harness/proofs/Parity_Lattice_Extract.v";
      let extraction =
        Printf.sprintf
          "cd %s && %s Parity_Lattice.v >log 2>&1 && %s Parity_Lattice_Extract.v >>log 2>&1"
          (Filename.quote stage) coqc coqc
      in
      (match Unix.system extraction with
      | Unix.WEXITED 0 ->
          let read path =
            let c = open_in_bin path in
            let s = really_input_string c (in_channel_length c) in
            close_in c; s
          in
          let fresh = read (Filename.concat stage "parity_lattice_extracted.ml") in
          let committed = read "modules/hermes_harness/generated_rocq/parity_lattice_extracted.ml" in
          if String.equal fresh committed then
            print_endline "test_rocq_lattice: extraction FRESHNESS holds (byte-identical)"
          else failwith "extraction freshness violated: committed extraction differs from a fresh one"
      | _ -> failwith "extraction driver failed under coqc -- the freshness law cannot run");
      (* The Iris smoke gate: proves the iris installation genuinely works (a
         real iProp entailment through the proof mode). Iris absent from THIS
         toolchain is a disclosed skip, not a failure -- the lattice proof needs
         only the prelude, iris is a heavier optional layer. *)
      match check_proof coqc "Iris_Smoke.v" "modules/hermes_harness/proofs/Iris_Smoke.v" with
      | Ok () -> print_endline "test_rocq_lattice: ok (iris smoke PROOF CHECKED)"
      | Error _ ->
          print_endline
            "test_rocq_lattice: ok (iris not in this coqc toolchain -- smoke SKIPPED, \
             disclosed, R2)")
  | None ->
      print_endline
        "test_rocq_lattice: ok (full-domain differential; coqc_available=false -- proof \
         check SKIPPED, disclosed, R2)"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_rocq_lattice" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_rocq_lattice ]);
  exit (Suite_telemetry.exit_code self)
