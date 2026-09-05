(* Machine-checked formal specifications for the critical components.

   "Critical" is defined by the hazard analysis: a component is critical when
   its failure realises H-1 (parity credit granted without proof). Two
   components sit at that point and have state spaces small enough to verify
   exhaustively by SMT rather than by sampling:

     parity_algebra      the roll-up law -- if its lattice is wrong, every
                         verdict above L6 is wrong
     fractal_diagnostic  the credit rule -- if a non-Implementation origin can
                         deny credit, a tooling gap becomes a recorded defect

   The encoding style is deliberate: each OCaml function is translated to an
   SMT function over an enumerated datatype, and each law is asserted NEGATED.
   z3 then searches for a counterexample; `unsat` means none exists, which is a
   proof over the whole domain, not a test over samples. `sat` would come with
   a model naming the exact inputs that break the law.

   The translation is the trust boundary and it is kept honest mechanically:
   the OCaml side exhaustively enumerates its own functions and emits their
   value tables into the SMT script, so the solver reasons about the functions
   as they ARE, not as this file believes them to be. A hand-written table
   could drift from the code; an emitted one cannot. *)

type verdict_result = Proved | Refuted of string | Unavailable of string

let describe = function
  | Proved -> "proved: no counterexample exists"
  | Refuted model -> "REFUTED: " ^ model
  | Unavailable reason -> "solver unavailable: " ^ reason

(* ------------------------------------------------------------- emission *)

let verdicts =
  [ Parity_algebra.Unmapped; Parity_algebra.Blocked; Parity_algebra.Verified;
    Parity_algebra.Divergent ]

let verdict_symbol = function
  | Parity_algebra.Unmapped -> "Unmapped"
  | Parity_algebra.Blocked -> "Blocked"
  | Parity_algebra.Verified -> "Verified"
  | Parity_algebra.Divergent -> "Divergent"

let origins =
  [ Fractal_diagnostic.Specification; Fractal_diagnostic.Implementation;
    Fractal_diagnostic.Environment; Fractal_diagnostic.Evidence;
    Fractal_diagnostic.Control ]

let origin_symbol = function
  | Fractal_diagnostic.Specification -> "Specification"
  | Fractal_diagnostic.Implementation -> "Implementation"
  | Fractal_diagnostic.Environment -> "Environment"
  | Fractal_diagnostic.Evidence -> "Evidence"
  | Fractal_diagnostic.Control -> "Control"

let impacts =
  [ Fractal_diagnostic.Blocks_credit; Fractal_diagnostic.Denies_credit;
    Fractal_diagnostic.No_effect ]

let impact_symbol = function
  | Fractal_diagnostic.Blocks_credit -> "Blocks_credit"
  | Fractal_diagnostic.Denies_credit -> "Denies_credit"
  | Fractal_diagnostic.No_effect -> "No_effect"

(* Emit the ACTUAL value table of a binary function as SMT assertions. The
   solver reasons about the function as implemented, because the table is
   computed by calling it. *)
let emit_combine_table buffer =
  List.iter
    (fun left ->
      List.iter
        (fun right ->
          Buffer.add_string buffer
            (Printf.sprintf "(assert (= (combine %s %s) %s))\n" (verdict_symbol left)
               (verdict_symbol right)
               (verdict_symbol (Parity_algebra.combine left right))))
        verdicts)
    verdicts

let emit_credit_table buffer =
  List.iter
    (fun verdict ->
      Buffer.add_string buffer
        (Printf.sprintf "(assert (= (grants_credit %s) %b))\n" (verdict_symbol verdict)
           (Parity_algebra.grants_credit verdict)))
    verdicts

(* The classification actually used for capture failures: enumerate the real
   constructor list and record (origin, impact) pairs the code produces. *)
let capture_classifications =
  List.map
    (fun failure ->
      let d = Capture_diagnostic.of_capture_failure failure in
      (d.Fractal_diagnostic.origin, d.Fractal_diagnostic.impact))
    [ Reference_capture.Interpreter_missing "p"; Reference_capture.Adapter_missing "a";
      Reference_capture.Reference_missing "r"; Reference_capture.Timed_out;
      Reference_capture.Exited (1, ""); Reference_capture.Unreadable "u";
      Reference_capture.Reference_error "e" ]

let emit_classification_table buffer =
  List.iteri
    (fun index (origin, impact) ->
      Buffer.add_string buffer
        (Printf.sprintf "(assert (= (origin_of f%d) %s))\n" index (origin_symbol origin));
      Buffer.add_string buffer
        (Printf.sprintf "(assert (= (impact_of f%d) %s))\n" index (impact_symbol impact)))
    capture_classifications

(* ---------------------------------------------------------------- specs *)

let algebra_spec () =
  let buffer = Buffer.create 4096 in
  Buffer.add_string buffer
    ";; Formal spec: the parity roll-up lattice.\n\
     ;; Laws are asserted NEGATED; unsat = proved over the whole domain.\n\
     (declare-datatype Verdict ((Unmapped) (Blocked) (Verified) (Divergent)))\n\
     (declare-fun combine (Verdict Verdict) Verdict)\n\
     (declare-fun grants_credit (Verdict) Bool)\n";
  emit_combine_table buffer;
  emit_credit_table buffer;
  Buffer.add_string buffer
    "(declare-const a Verdict)\n(declare-const b Verdict)\n(declare-const c Verdict)\n\
     ;; Negation of: commutativity AND associativity AND idempotence AND\n\
     ;; Divergent-absorption AND (credit only from Verified) AND\n\
     ;; (combining with any non-Verified never yields credit).\n\
     (assert (or\n\
     \  (not (= (combine a b) (combine b a)))\n\
     \  (not (= (combine (combine a b) c) (combine a (combine b c))))\n\
     \  (not (= (combine a a) a))\n\
     \  (not (= (combine Divergent a) Divergent))\n\
     \  (and (grants_credit a) (not (= a Verified)))\n\
     \  (and (grants_credit (combine a b)) (not (and (grants_credit a) (grants_credit b))))))\n\
     (check-sat)\n";
  Buffer.contents buffer

let diagnostic_spec () =
  let buffer = Buffer.create 4096 in
  Buffer.add_string buffer
    ";; Formal spec: only an Implementation origin may deny parity credit.\n\
     ;; The classification table is emitted from the code under test.\n\
     (declare-datatype Origin ((Specification) (Implementation) (Environment) (Evidence) (Control)))\n\
     (declare-datatype Impact ((Blocks_credit) (Denies_credit) (No_effect)))\n\
     (declare-datatype Failure (";
  List.iteri
    (fun index _ -> Buffer.add_string buffer (Printf.sprintf "(f%d) " index))
    capture_classifications;
  Buffer.add_string buffer
    "))\n\
     (declare-fun origin_of (Failure) Origin)\n\
     (declare-fun impact_of (Failure) Impact)\n";
  emit_classification_table buffer;
  Buffer.add_string buffer
    "(declare-const f Failure)\n\
     ;; Negation of R5: some failure denies credit from a non-Implementation origin.\n\
     (assert (and (= (impact_of f) Denies_credit)\n\
     \             (not (= (origin_of f) Implementation))))\n\
     (check-sat)\n";
  Buffer.contents buffer

(* --------------------------------------------------------------- runner *)

let run_query query =
  let solver =
    match Sys.getenv_opt "HERMES_Z3" with
    | Some value when String.trim value <> "" -> String.trim value
    | _ -> (
        let from_path =
          Option.bind (Sys.getenv_opt "PATH") (fun path ->
              List.find_opt
                (fun directory ->
                  let candidate = Filename.concat directory "z3" in
                  match Unix.access candidate [ Unix.X_OK ] with
                  | () -> true
                  | exception Unix.Unix_error _ -> false)
                (String.split_on_char ':' path))
        in
        match from_path with
        | Some directory -> Filename.concat directory "z3"
        | None ->
            Filename.concat
              (Option.value (Sys.getenv_opt "HOME") ~default:"")
              ".opam/ocaml-5.5.0/bin/z3")
  in
  match Unix.access solver [ Unix.X_OK ] with
  | exception Unix.Unix_error _ -> Unavailable ("no z3 at " ^ solver)
  | () -> (
      let path = Filename.temp_file "hermes-spec-" ".smt2" in
      let output_path = Filename.temp_file "hermes-spec-out-" ".txt" in
      Fun.protect
        ~finally:(fun () ->
          List.iter (fun p -> if Sys.file_exists p then Sys.remove p) [ path; output_path ])
        (fun () ->
          let channel = open_out_bin path in
          output_string channel query;
          close_out channel;
          let output =
            Unix.openfile output_path [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o600
          in
          let devnull = Unix.openfile Filename.null [ Unix.O_RDONLY ] 0o400 in
          let pid =
            Unix.create_process solver [| solver; "-model"; path |] devnull output output
          in
          Unix.close output;
          Unix.close devnull;
          let _, _ = Unix.waitpid [] pid in
          let channel = open_in_bin output_path in
          let raw =
            Fun.protect
              ~finally:(fun () -> close_in_noerr channel)
              (fun () -> really_input_string channel (in_channel_length channel))
          in
          let text = String.trim raw in
          if String.length text >= 5 && String.sub text 0 5 = "unsat" then Proved
          else if String.length text >= 3 && String.sub text 0 3 = "sat" then
            Refuted text
          else Unavailable ("unexpected solver output: " ^ text)))

(* The two critical-component specifications, named for reporting. *)
(* The Gate combinator of the configuration grammar (Harness_config): fail-closed
   sequencing. The table is emitted from the code under test -- gate_verdict
   applied over the whole 4x4 domain with a constant thunk -- and the law is
   asserted negated: a no-credit condition must stand unchanged (the guarded arm
   contributes nothing), and a credited condition must fold with the guarded
   verdict under combine. Laziness (the thunk not RUNNING) is a behavioural
   property covered by the chaos/behaviour tests; the VALUE law is discharged
   here. *)
let emit_gate_table buffer =
  List.iter
    (fun condition ->
      List.iter
        (fun guarded ->
          Buffer.add_string buffer
            (Printf.sprintf "(assert (= (gate %s %s) %s))\n" (verdict_symbol condition)
               (verdict_symbol guarded)
               (verdict_symbol (Harness_config.gate_verdict condition (fun () -> guarded)))))
        verdicts)
    verdicts

let gate_spec () =
  let buffer = Buffer.create 4096 in
  Buffer.add_string buffer
    ";; Formal spec: the configuration grammar's Gate is fail-closed.\n\
     ;; Laws are asserted NEGATED; unsat = proved over the whole domain.\n\
     (declare-datatype Verdict ((Unmapped) (Blocked) (Verified) (Divergent)))\n\
     (declare-fun combine (Verdict Verdict) Verdict)\n\
     (declare-fun grants_credit (Verdict) Bool)\n\
     (declare-fun gate (Verdict Verdict) Verdict)\n";
  emit_combine_table buffer;
  emit_credit_table buffer;
  emit_gate_table buffer;
  Buffer.add_string buffer
    "(declare-const a Verdict)\n(declare-const b Verdict)\n\
     ;; Negation of: (no credit -> gate a b = a) AND (credit -> gate a b = combine a b)\n\
     ;; AND (a gate never grants credit its condition lacked).\n\
     (assert (or\n\
     \  (and (not (grants_credit a)) (not (= (gate a b) a)))\n\
     \  (and (grants_credit a) (not (= (gate a b) (combine a b))))\n\
     \  (and (grants_credit (gate a b)) (not (grants_credit a)))))\n\
     (check-sat)\n";
  Buffer.contents buffer

let specifications =
  [ ("parity-algebra-lattice", algebra_spec);
    ("diagnostic-credit-rule", diagnostic_spec);
    ("config-gate-fail-closed", gate_spec) ]

let verify_all () =
  List.map (fun (name, spec) -> (name, run_query (spec ()))) specifications
