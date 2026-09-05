(* An independent proof that the L2 dependency graph admits a build order.

   `test_capability_catalog` already checks acyclicity, but it does so by
   running the same depth-first traversal the harness uses to produce the
   order. That is a test of the implementation against itself: if the traversal
   has a bug that silently drops an edge, both the order and the test agree.

   This asks a different question, of a different tool. Encode the graph as
   integer ranks and assert `rank(dependent) > rank(dependency)` for every
   edge. Such a ranking exists exactly when the graph is acyclic, so:

     sat    a ranking exists  -> acyclic, a build order is possible
     unsat  no ranking exists -> a cycle, and z3 has proved it

   Nothing here shares code with the traversal, so agreement between the two is
   evidence rather than tautology. The encoding is small and total: the
   correspondence between "ranking exists" and "acyclic" is a standard result,
   not a heuristic. *)

type outcome =
  | Acyclic
  | Cyclic
  | Solver_missing of string
  | Solver_failed of string

let describe = function
  | Acyclic -> "acyclic: a topological build order exists"
  | Cyclic -> "cyclic: no build order exists"
  | Solver_missing path -> "solver not found: " ^ path
  | Solver_failed reason -> "solver failed: " ^ reason

let solver_path () =
  match Sys.getenv_opt "HERMES_Z3" with
  | Some value when String.trim value <> "" -> String.trim value
  | _ -> (
      match Sys.getenv_opt "PATH" with
      | None -> "z3"
      | Some path -> (
          let candidates =
            List.map (fun directory -> Filename.concat directory "z3")
              (String.split_on_char ':' path)
          in
          match
            List.find_opt
              (fun candidate ->
                match Unix.access candidate [ Unix.X_OK ] with
                | () -> true
                | exception Unix.Unix_error _ -> false)
              candidates
          with
          | Some found -> found
          | None ->
              Filename.concat
                (Option.value (Sys.getenv_opt "HOME") ~default:"")
                ".opam/ocaml-5.5.0/bin/z3"))

(* SMT-LIB identifiers: the semantic keys contain dots, which are legal in a
   quoted symbol but easier to read escaped. *)
let symbol key =
  String.map (fun c -> if c = '.' || c = '-' then '_' else c) key

let encode capabilities dependencies =
  let buffer = Buffer.create 4096 in
  Buffer.add_string buffer "(set-logic QF_LIA)\n";
  Buffer.add_string buffer
    ";; One integer rank per capability slice. An edge constrains the order.\n";
  List.iter
    (fun key -> Buffer.add_string buffer (Printf.sprintf "(declare-const r_%s Int)\n" (symbol key)))
    capabilities;
  List.iter
    (fun (dependent, dependency) ->
      Buffer.add_string buffer
        (Printf.sprintf "(assert (> r_%s r_%s)) ; %s depends on %s\n" (symbol dependent)
           (symbol dependency) dependent dependency))
    dependencies;
  Buffer.add_string buffer "(check-sat)\n";
  Buffer.contents buffer

let run_solver ~solver ~query =
  let path = Filename.temp_file "hermes-smt-" ".smt2" in
  let output_path = Filename.temp_file "hermes-smt-out-" ".txt" in
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
      match Unix.create_process solver [| solver; path |] devnull output output with
      | exception Unix.Unix_error (error, _, _) ->
          Unix.close output;
          Unix.close devnull;
          Solver_failed (Unix.error_message error)
      | pid ->
          Unix.close output;
          Unix.close devnull;
          let _, status = Unix.waitpid [] pid in
          let channel = open_in_bin output_path in
          let raw =
            Fun.protect
              ~finally:(fun () -> close_in_noerr channel)
              (fun () -> really_input_string channel (in_channel_length channel))
          in
          let text = String.trim raw in
          let starts_with prefix =
            String.length text >= String.length prefix
            && String.sub text 0 (String.length prefix) = prefix
          in
          (match status with
          | Unix.WEXITED 0 | Unix.WEXITED 1 ->
              if starts_with "sat" then Acyclic
              else if starts_with "unsat" then Cyclic
              else Solver_failed ("unexpected solver output: " ^ text)
          | Unix.WEXITED code -> Solver_failed (Printf.sprintf "exit %d: %s" code text)
          | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
              Solver_failed (Printf.sprintf "signal %d" signal)))

let check ~capabilities ~dependencies =
  let solver = solver_path () in
  match Unix.access solver [ Unix.X_OK ] with
  | exception Unix.Unix_error _ -> Solver_missing solver
  | () -> run_solver ~solver ~query:(encode capabilities dependencies)

(* The real graph, taken from the catalog rather than restated here: a proof
   about a copy of the data would prove nothing about the data in use. *)
let check_catalog () =
  let capabilities = List.map Capability_catalog.semantic_key Capability_catalog.all in
  let dependencies =
    List.concat_map
      (fun capability ->
        List.map
          (fun dependency -> (Capability_catalog.semantic_key capability, dependency))
          (Capability_catalog.depends_on capability))
      Capability_catalog.all
  in
  (check ~capabilities ~dependencies, List.length capabilities, List.length dependencies)
