(** Test suite for gospel-lint.

    Six layers, each answering a different question:

    - TDD: does each rule fire on its own defect, and stay silent otherwise?
    - BDD: does a user-visible scenario produce the promised outcome?
    - SURFACE: is every Gospel construct accepted? This is coverage of the
      *language*, verified against the real checker, not of the linter's code.
    - PROPERTY: do the invariants hold across the corpus?
    - CHAOS: does the linter survive hostile input without crashing or silently
      passing?
    - STRUCTURE: is every rule, verdict, level and block kind exercised? This
      replaces a line-coverage tool: it cannot drift, because adding a rule
      without a fixture fails the suite.

    The load-bearing invariant is differential: if the linter reports OK, gospel
    must agree. A linter that passes a file gospel rejects is worse than none. *)

open Gospel_lint

let passed = ref 0
let failures = ref []
let skipped = ref 0

let check condition label detail =
  if condition then incr passed
  else
    failures :=
      (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

let rules_for source =
  List.sort_uniq compare
    (List.map (fun (finding : finding) -> finding.rule) (static_findings source))

let levels_for source =
  List.sort_uniq compare
    (List.map (fun (finding : finding) -> finding.level) (static_findings source))

let write_temp ?(suffix = ".mli") source =
  let path = Filename.temp_file "gospel-lint-test-" suffix in
  let channel = open_out_bin path in
  output_string channel source;
  close_out channel;
  path

let with_temp source f =
  let path = write_temp source in
  Fun.protect ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () -> f path)

let quiet path = lint ~emit:(fun _ -> ()) path
let gospel_available () = find_gospel () <> None

(* ------------------------------------------------------------- TDD layer *)
(* One defective fixture per rule, plus the corrected form that must be clean. *)

let rule_fixtures =
  [ ("reserved-label",
     "val f : model:string -> bool\n(*@ r = f ~model x *)\n",
     "val f : model_id:string -> bool\n(*@ r = f ~model_id x *)\n");
    ("reserved-identifier",
     "val f : string -> bool\n(*@ r = f model *)\n",
     "val f : string -> bool\n(*@ r = f name *)\n");
    ("self-reference",
     "val f : int -> int\n(*@ r = f x\n    pure\n    ensures f r = r *)\n",
     "val f : int -> int\n(*@ r = f x\n    pure *)\n\
      (*@ axiom f_idem: forall x: int. f (f x) = f x *)\n");
    ("labelled-application",
     "val f : keep:bool -> int -> int\n\
      (*@ r = f ~keep x\n    ensures f ~keep:true x = x *)\n",
     "val f : keep:bool -> int -> int\n(*@ r = f ~keep x\n    pure *)\n");
    ("public-invariant",
     "type t = { a : int }\n(*@ with x invariant x.a >= 0 *)\n",
     "type t\n(*@ model a : integer *)\n(*@ with x invariant x.a >= 0 *)\n");
    ("clause-not-in-kind",
     "val f : int -> int\n(*@ r = f x\n    variant x *)\n",
     "val f : int -> int\n(*@ r = f x\n    requires x > 0 *)\n");
    ("integer-over-int",
     "val f : int -> int\n(*@ r = f x\n    pure *)\n\
      (*@ axiom a: forall x: integer. f x = x *)\n",
     "val f : int -> int\n(*@ r = f x\n    pure *)\n\
      (*@ axiom a: forall x: int. f x = x *)\n");
    ("consumes-unit",
     "type t\nval use : t -> unit\n(*@ use s\n    consumes s *)\n",
     "type t\nval use : t -> bool\n(*@ r = use s\n    consumes s *)\n") ]

let tdd_layer () =
  List.iter
    (fun (rule, bad, good) ->
      check (List.mem rule (rules_for bad)) ("TDD " ^ rule ^ " fires")
        (String.concat "," (rules_for bad));
      check
        (not (List.mem rule (rules_for good)))
        ("TDD " ^ rule ^ " silent when correct")
        (String.concat "," (rules_for good)))
    rule_fixtures

(* ------------------------------------------------------------- BDD layer *)

let bdd_layer () =
  (* Given a spec whose only problem is an unresolvable module,
     when linted, then it is not-checkable, never rejected. *)
  with_temp "val f : Yojson.Safe.t -> Yojson.Safe.t\n(*@ r = f v *)\n" (fun path ->
      check (quiet path = Verdict_not_checkable)
        "BDD external module -> not checkable" "");

  if gospel_available () then begin
    (* Given a clean spec, when linted, then OK. *)
    with_temp "val f : int -> int\n(*@ r = f x\n    requires x > 0 *)\n"
      (fun path -> check (quiet path = Verdict_ok) "BDD clean spec -> OK" "");
    (* Given a defect the linter does not model, gospel must still fail it. *)
    with_temp "val f : int -> int\n(*@ r = f x\n    ensures nope r *)\n"
      (fun path ->
        check (quiet path = Verdict_errors)
          "BDD unmodelled defect -> caught by gospel" "")
  end
  else skipped := !skipped + 2;

  (* Given no gospel binary, a statically clean file is UNAVAILABLE, never OK. *)
  let saved_home = Sys.getenv_opt "HOME" in
  let saved_path = Sys.getenv_opt "PATH" in
  Unix.putenv "HERMES_GOSPEL" "/nonexistent";
  Unix.putenv "GOSPEL_BIN" "/nonexistent";
  Unix.putenv "PATH" "/nonexistent";
  Unix.putenv "HOME" "/nonexistent";
  with_temp "val f : int -> int\n(*@ r = f x *)\n" (fun path ->
      check (quiet path = Verdict_unavailable)
        "BDD no gospel -> unavailable, not OK" "");
  Unix.putenv "HERMES_GOSPEL" "";
  Unix.putenv "GOSPEL_BIN" "";
  Unix.putenv "PATH" (Option.value saved_path ~default:"");
  Unix.putenv "HOME" (Option.value saved_home ~default:"");

  (* Given a missing file, then error, not pass. *)
  check (main [| "gospel-lint"; "/nonexistent/file.mli" |] = 4)
    "BDD missing file -> error" "";
  (* Given no arguments, then usage. *)
  check (main [| "gospel-lint" |] = 64) "BDD no args -> usage" ""

(* --------------------------------------------------------- SURFACE layer *)
(* Every construct in the Gospel language, from the installed grammar. *)

let surface =
  [ ("val requires/ensures",
     "val f : int -> int\n(*@ r = f x\n    requires x > 0\n    ensures r > 0 *)\n");
    ("val checks", "val f : int list -> int\n(*@ r = f l\n    checks l <> [] *)\n");
    ("val raises",
     "exception E\nval f : int -> int\n(*@ r = f x\n    raises E -> x < 0 *)\n");
    ("val modifies/old",
     "type t = { mutable a : int }\nval b : t -> unit\n\
      (*@ b s\n    modifies s\n    ensures s.a = old s.a + 1 *)\n");
    ("val consumes", "type t\nval use : t -> bool\n(*@ r = use s\n    consumes s *)\n");
    ("val diverges", "val loop : int -> int\n(*@ r = loop x\n    diverges *)\n");
    ("val pure", "val f : int -> int\n(*@ r = f x\n    pure *)\n");
    ("val equivalent",
     "val f : int -> int\n(*@ r = f x\n    equivalent \"x\" *)\n");
    ("type ephemeral", "type t\n(*@ ephemeral *)\n");
    ("type model", "type t\n(*@ model v : integer *)\n");
    ("type mutable model", "type t\n(*@ mutable model v : integer *)\n");
    ("type invariant",
     "type t\n(*@ model v : integer *)\n(*@ with x invariant x.v >= 0 *)\n");
    ("function", "(*@ function double (x: integer) : integer = 2 * x *)\n");
    ("function rec + variant",
     "(*@ function rec f (x: integer) : integer = if x <= 0 then 0 else f (x-1) *)\n\
      (*@ variant x *)\n");
    ("predicate", "(*@ predicate nonneg (x: integer) = x >= 0 *)\n");
    ("predicate rec",
     "(*@ predicate rec even (x: integer) = if x = 0 then true else not (even (x-1)) *)\n\
      (*@ variant x *)\n");
    ("coercion",
     "type t\n(*@ model v : integer *)\n\
      (*@ function to_int (x: t) : integer = x.v *)\n(*@ coercion *)\n");
    ("axiom",
     "val f : int -> int\n(*@ r = f x\n    pure *)\n\
      (*@ axiom a: forall x: int. f x = x *)\n");
    ("ghost val", "val f : int -> int\n(*@ r = f x *)\n(*@ val g : int *)\n");
    ("ghost type", "(*@ type gseq *)\n");
    ("ghost open", "(*@ open List *)\n");
    ("term let/in",
     "val f : int -> int\n(*@ r = f x\n    ensures let y = x in r >= y *)\n");
    ("term if/then/else",
     "val f : int -> int\n(*@ r = f x\n    ensures r = if x > 0 then x else 0 *)\n");
    ("term match/with/as",
     "val f : int option -> int\n\
      (*@ r = f o\n    ensures match o with (Some v) as w -> w = o | None -> true *)\n");
    ("term forall",
     "val f : int -> int\n(*@ r = f x\n    ensures forall y: int. y = y *)\n");
    ("term exists",
     "val f : int -> int\n(*@ r = f x\n    ensures exists y: int. y = r *)\n");
    ("term fun",
     "val f : int -> int\n(*@ r = f x\n    ensures (fun y -> y) r = r *)\n");
    ("term not/true/false",
     "val f : int -> bool\n\
      (*@ r = f x\n    ensures not (r = true) -> r = false *)\n");
    ("tuple result",
     "val f : int -> int * int\n(*@ a, b = f x\n    ensures a <= b *)\n");
    ("option result",
     "val f : int -> int option\n(*@ r = f x\n    ensures r = None -> x < 0 *)\n");
    ("labelled arg", "val f : keep:bool -> int -> int\n(*@ r = f ~keep x *)\n");
    ("optional arg", "val f : ?limit:int -> int -> int\n(*@ r = f ?limit x *)\n");
    ("string with delimiter inside",
     "val f : int -> int\n(*@ r = f x\n    equivalent \"a *) b\" *)\n") ]

let surface_layer () =
  List.iter
    (fun (name, source) ->
      check (rules_for source = []) ("SURFACE " ^ name ^ " not falsely flagged")
        (String.concat "," (rules_for source));
      if gospel_available () then
        with_temp source (fun path ->
            match run_gospel path with
            | Ok (0, _) -> incr passed
            | Ok (_, output) ->
                failures :=
                  ("SURFACE " ^ name ^ " rejected by gospel :: " ^ output)
                  :: !failures
            | Error message ->
                failures :=
                  ("SURFACE " ^ name ^ " gospel error :: " ^ message) :: !failures)
      else incr skipped)
    surface

(* -------------------------------------------------------- PROPERTY layer *)

let property_layer () =
  (* P1, load-bearing: linter OK implies gospel OK. *)
  if gospel_available () then begin
    let violations = ref 0 in
    List.iter
      (fun (_, source) ->
        with_temp source (fun path ->
            if quiet path = Verdict_ok then
              match run_gospel path with
              | Ok (0, _) -> ()
              | _ -> incr violations))
      surface;
    check (!violations = 0) "PROPERTY linter-OK implies gospel-OK"
      (string_of_int !violations ^ " violation(s)");

    (* P2: each defective fixture is rejected by the linter, and gospel
       independently agrees it is bad, so no rule is merely stricter. *)
    let disagreements = ref [] in
    List.iter
      (fun (rule, bad, _) ->
        with_temp bad (fun path ->
            if quiet path = Verdict_ok then
              disagreements := (rule ^ ": linter passed a defect") :: !disagreements;
            match run_gospel path with
            | Ok (0, _) ->
                disagreements :=
                  (rule ^ ": gospel accepts it, rule is too strict") :: !disagreements
            | _ -> ()))
      rule_fixtures;
    check (!disagreements = []) "PROPERTY defects rejected by both"
      (String.concat "; " !disagreements)
  end
  else skipped := !skipped + 2;

  (* P3: findings are deterministic. *)
  let unstable = ref 0 in
  List.iter
    (fun source ->
      let first = rules_for source and second = rules_for source in
      if first <> second then incr unstable)
    (List.map snd surface @ List.map (fun (_, bad, _) -> bad) rule_fixtures);
  check (!unstable = 0) "PROPERTY findings deterministic" "";

  (* P4: every finding carries the full RCA contract. *)
  let incomplete = ref [] in
  List.iter
    (fun (_, bad, _) ->
      List.iter
        (fun (finding : finding) ->
          if
            finding.message = "" || finding.cause = "" || finding.fix = ""
            || finding.line < 1
          then incomplete := finding.rule :: !incomplete)
        (static_findings bad))
    rule_fixtures;
  check (!incomplete = []) "PROPERTY findings carry full RCA"
    (String.concat "," !incomplete);

  (* P5: prose comments outside Gospel blocks never produce findings. *)
  let prose =
    "(* Discusses the invariant and the model and requires care. *)\n\
     val f : int -> int\n(*@ r = f x *)\n"
  in
  check (rules_for prose = []) "PROPERTY prose comments ignored"
    (String.concat "," (rules_for prose));

  (* P6: the scanner survives a block delimiter inside a string literal. *)
  let tricky = "val f : int -> int\n(*@ r = f x\n    equivalent \"a *) b\" *)\n" in
  check
    (List.length (parse tricky) = 1)
    "PROPERTY scanner handles delimiter in string"
    (string_of_int (List.length (parse tricky)));

  (* P7: an integer axiom that touches no int-valued val is allowed. *)
  let disjoint =
    "val f : int -> int\n(*@ r = f x *)\n\
     (*@ function g (x: integer) : integer = x *)\n\
     (*@ axiom a: forall y: integer. g y = y *)\n"
  in
  check
    (not (List.mem "integer-over-int" (rules_for disjoint)))
    "PROPERTY integer axiom over non-int symbols allowed" "";

  (* P8: a stdlib module is not an external dependency. *)
  check
    (external_modules "val f : Int.t -> Int.t\n" = [])
    "PROPERTY stdlib module is not external" ""

(* ----------------------------------------------------------- CHAOS layer *)

let chaos_layer () =
  Random.init 20260807;
  (* Deterministic: a chaos failure must reproduce. *)
  let corpus =
    Array.of_list (List.map snd surface @ List.map (fun (_, bad, _) -> bad) rule_fixtures)
  in
  let alphabet =
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \n\t()*@\"'~:.,;=<>-|[]{}\\/!?#$%^&+"
  in
  let noise length =
    String.init length (fun _ -> alphabet.[Random.int (String.length alphabet)])
  in
  let crashes = ref [] in
  for iteration = 0 to 599 do
    let source = corpus.(Random.int (Array.length corpus)) in
    let mutated =
      match iteration mod 6 with
      | 0 -> String.sub source 0 (Random.int (String.length source + 1))
      | 1 ->
          let cut = Random.int (String.length source + 1) in
          String.sub source 0 cut ^ noise (1 + Random.int 30)
          ^ String.sub source cut (String.length source - cut)
      | 2 ->
          String.concat "" (String.split_on_char '*' source)
      | 3 -> source ^ source ^ source
      | 4 ->
          String.concat "" (List.init (1 + Random.int 40) (fun _ -> "(*@ ")) ^ source
      | _ -> noise (Random.int 400)
    in
    match
      let findings = static_findings mutated in
      let internal =
        List.exists (fun (f : finding) -> f.rule = "linter-internal") findings
      in
      ignore (parse mutated);
      ignore (external_modules mutated);
      internal
    with
    | false -> ()
    | true -> crashes := "rule raised on a mutation" :: !crashes
    | exception exn ->
        crashes := Printexc.to_string exn :: !crashes
  done;
  check (!crashes = []) "CHAOS no crashes over 600 mutations"
    (String.concat "; " (List.filteri (fun i _ -> i < 3) !crashes));

  (* Chaos must never become a silent pass. *)
  with_temp "!!! not ocaml at all (((\n" (fun path ->
      let verdict = quiet path in
      if gospel_available () then
        check (verdict <> Verdict_ok) "CHAOS junk file not reported OK" ""
      else incr skipped);

  (* Pathological size must not hang. *)
  let huge =
    String.concat "" (List.init 4000 (fun _ -> "val f : int -> int\n(*@ r = f x *)\n"))
  in
  check (List.length (parse huge) = 4000) "CHAOS 4000 blocks parsed"
    (string_of_int (List.length (parse huge)));

  (* Undecodable bytes must not crash the reader or the checker. *)
  let path = write_temp "val f : int -> int\n(*@ r = f \xff\xfe x *)\n" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      match quiet path with
      | _ -> incr passed
      | exception exn ->
          failures := ("CHAOS undecodable bytes :: " ^ Printexc.to_string exn)
                      :: !failures)

(* ------------------------------------------------------ ROBUSTNESS layer *)

let robustness_layer () =
  (* A rule that raises must surface as linter-internal and never as OK. *)
  let original = !rules in
  rules := original @ [ ("exploding", fun _ _ -> failwith "synthetic failure") ];
  Fun.protect
    ~finally:(fun () -> rules := original)
    (fun () ->
      let findings = static_findings "val f : int -> int\n(*@ r = f x *)\n" in
      check
        (List.exists (fun (f : finding) -> f.rule = "linter-internal") findings)
        "ROBUST crashing rule surfaces as linter-internal" "";
      with_temp "val f : int -> int\n(*@ r = f x *)\n" (fun path ->
          check (quiet path = Verdict_internal)
            "ROBUST crashing rule yields internal error, not OK" ""));

  (* A reserved word as a quantifier binder, inside an axiom block. *)
  let binder =
    "val f : int -> int\n(*@ r = f x\n    pure *)\n\
     (*@ axiom a: forall model: int. f model = model *)\n"
  in
  check
    (List.mem "reserved-identifier" (rules_for binder))
    "ROBUST reserved quantifier binder caught"
    (String.concat "," (rules_for binder));

  (* gospel discovered via PATH rather than the env vars. *)
  let staging = Filename.temp_file "gospel-lint-path-" "" in
  Sys.remove staging;
  Unix.mkdir staging 0o700;
  Fun.protect
    ~finally:(fun () ->
      Array.iter (fun n -> Sys.remove (Filename.concat staging n)) (Sys.readdir staging);
      Unix.rmdir staging)
    (fun () ->
      let fake = Filename.concat staging "gospel" in
      let channel = open_out fake in
      output_string channel "#!/bin/sh\nexit 0\n";
      close_out channel;
      Unix.chmod fake 0o755;
      let saved_path = Sys.getenv_opt "PATH" in
      Unix.putenv "HERMES_GOSPEL" "";
      Unix.putenv "GOSPEL_BIN" "";
      Unix.putenv "PATH" staging;
      check (find_gospel () = Some fake) "ROBUST gospel found on PATH"
        (Option.value (find_gospel ()) ~default:"none");
      Unix.putenv "PATH" (Option.value saved_path ~default:""));

  (* A blank env var must not be mistaken for a configured binary. *)
  Unix.putenv "HERMES_GOSPEL" "   ";
  check (find_gospel () <> Some "   ") "ROBUST blank env var ignored" "";
  Unix.putenv "HERMES_GOSPEL" "";

  (* A binary that cannot be executed must degrade, not crash. *)
  let directory = Filename.temp_file "gospel-lint-dir-" "" in
  Sys.remove directory;
  Unix.mkdir directory 0o700;
  Fun.protect
    ~finally:(fun () -> Unix.rmdir directory)
    (fun () ->
      Unix.putenv "HERMES_GOSPEL" directory;
      with_temp "val f : int -> int\n(*@ r = f x *)\n" (fun path ->
          let verdict = quiet path in
          check
            (verdict = Verdict_unavailable || verdict = Verdict_errors)
            "ROBUST unexecutable gospel degrades, no crash" "");
      Unix.putenv "HERMES_GOSPEL" "");

  (* A stub on GOSPEL_LOAD_PATH turns a not-checkable file into a real verdict,
     and the stub directory is only consulted when configured. *)
  let stubs = Filename.temp_file "gospel-lint-stub-" "" in
  Sys.remove stubs;
  Unix.mkdir stubs 0o700;
  Fun.protect
    ~finally:(fun () ->
      Array.iter (fun n -> Sys.remove (Filename.concat stubs n)) (Sys.readdir stubs);
      Unix.rmdir stubs)
    (fun () ->
      let channel = open_out (Filename.concat stubs "yojson.mli") in
      output_string channel "module Safe : sig\n  type t\nend\n";
      close_out channel;
      let source = "val f : Yojson.Safe.t -> Yojson.Safe.t\n(*@ r = f v *)\n" in
      Unix.putenv "GOSPEL_LOAD_PATH" "";
      with_temp source (fun path ->
          check (quiet path = Verdict_not_checkable)
            "ROBUST unresolvable module without a stub is not checkable" "");
      Unix.putenv "GOSPEL_LOAD_PATH" stubs;
      check (load_path () = [ stubs ]) "ROBUST load path read from env" "";
      if gospel_available () then
        with_temp source (fun path ->
            check (quiet path = Verdict_ok)
              "ROBUST stub on load path yields a real verdict" "")
      else incr skipped;
      (* A module with no stub is still not-checkable, now via gospel's own
         report rather than the static scan. *)
      if gospel_available () then
        with_temp "val f : Nosuchlib.t -> int\n(*@ r = f v *)\n" (fun path ->
            check (quiet path = Verdict_not_checkable)
              "ROBUST missing module under a load path is not checkable" "")
      else incr skipped;
      Unix.putenv "GOSPEL_LOAD_PATH" "");

  (* A blank or absent load path entry is ignored. *)
  Unix.putenv "GOSPEL_LOAD_PATH" " :/nonexistent-dir";
  check (load_path () = []) "ROBUST blank and missing load path entries dropped"
    (String.concat "," (load_path ()));
  Unix.putenv "GOSPEL_LOAD_PATH" "";

  (* main over a real file returns that file's verdict. *)
  with_temp "val f : int -> int\n(*@ r = f x *)\n" (fun path ->
      let expected = if gospel_available () then 0 else 3 in
      check (main [| "gospel-lint"; path |] = expected)
        "ROBUST main lints an existing file" "")

(* ------------------------------------------------------- EDGES layer *)
(* Paths reachable only through unusual input or a failing environment. Each is
   real behaviour the linter promises, so each earns a test rather than an
   exclusion. *)

let edges_layer () =
  (* A parameterised type declaration: the scanner must skip 'a and land on the
     type name. *)
  let parameterised = "type 'a box = { a : 'a }\n(*@ with x invariant true *)\n" in
  check
    (List.mem "public-invariant" (rules_for parameterised))
    "EDGE parameterised type declaration parsed"
    (String.concat "," (rules_for parameterised));

  (* A quantifier with no terminating dot must not run off the end. *)
  let dotless = "val f : int -> int\n(*@ r = f x\n    ensures forall model: int *)\n" in
  check
    (List.mem "reserved-identifier" (rules_for dotless))
    "EDGE quantifier without a dot still scanned"
    (String.concat "," (rules_for dotless));

  (* A clause keyword mid-line is not a clause; at a line start after blanks it
     is. Both walks through `back` must be exercised. *)
  let midline = "val f : int -> int\n(*@ r = f x\n    ensures r = 0 && variant x *)\n" in
  check
    (not (List.mem "clause-not-in-kind" (rules_for midline)))
    "EDGE clause word mid-line is not a clause"
    (String.concat "," (rules_for midline));
  let indented = "val f : int -> int\n(*@ r = f x\n\t variant x *)\n" in
  check
    (List.mem "clause-not-in-kind" (rules_for indented))
    "EDGE clause word after a tab is a clause"
    (String.concat "," (rules_for indented));

  (* Whitespace between a label and its colon still reads as an application. *)
  let spaced =
    "val f : keep:bool -> int -> int\n(*@ r = f ~keep x\n    ensures f ~keep  : true *)\n"
  in
  check
    (List.mem "labelled-application" (rules_for spaced))
    "EDGE labelled application with spaces before colon"
    (String.concat "," (rules_for spaced));

  (* Two findings on one line exercise the rule tie-break in the sort. *)
  let same_line = "val f : string -> bool\n(*@ r = f model\n    ensures f model *)\n" in
  let ordered = static_findings same_line in
  check (List.length ordered >= 2) "EDGE two findings on one line"
    (string_of_int (List.length ordered));
  with_temp same_line (fun path ->
      check (quiet path = Verdict_errors) "EDGE same-line findings sort cleanly" "");

  (* PATH genuinely unset. OCaml can blank a variable but not remove it, so the
     lookup is exercised through its parameterised form. *)
  check (search_path None "gospel" = None) "EDGE unset PATH yields no binary" "";

  (* run_gospel on a path it cannot copy reports a Sys_error, not a crash. *)
  (match run_gospel "/nonexistent/interface.mli" with
  | Error message ->
      check
        (String.length message > 0)
        "EDGE run_gospel on a missing path degrades" message
  | Ok _ -> check false "EDGE run_gospel on a missing path degrades" "returned Ok");

  (* lint on an unreadable path is an internal error, never a pass. *)
  let directory = Filename.temp_file "gospel-lint-unreadable-" "" in
  Sys.remove directory;
  Unix.mkdir directory 0o700;
  Fun.protect
    ~finally:(fun () -> Unix.rmdir directory)
    (fun () ->
      check (quiet directory = Verdict_internal)
        "EDGE unreadable path yields internal error" "");

  (* Identifiers may start with an underscore. *)
  check
    (List.mem "reserved-identifier"
       (rules_for "val f : int -> int\n(*@ _r = f model *)\n"))
    "EDGE underscore-led identifier scanned" "";

  (* Carriage returns and tabs count as whitespace when skipping type params. *)
  let crlf = "type\r 'a\tbox = { a : 'a }\n(*@ with x invariant true *)\n" in
  check
    (List.mem "public-invariant" (rules_for crlf))
    "EDGE CR and tab treated as whitespace" (String.concat "," (rules_for crlf));

  (* An empty needle never matches, and never loops. *)
  check (not (contains_word "anything" "")) "EDGE empty word never matches" "";

  (* Degenerate type declarations must not be mistaken for real ones. *)
  check (type_declaration "type" = None) "EDGE bare `type` is not a declaration" "";
  check (type_declaration "typed x" = None) "EDGE `typed` is not `type`" "";
  check (type_declaration "type 'a" = None) "EDGE type params without a name" "";
  check (type_declaration "type   " = None) "EDGE type with only blanks" "";
  (match type_declaration "type 'a box = { a : 'a }" with
  | Some (name, rest) ->
      check (name = "box" && String.contains rest '=')
        "EDGE parameterised type name extracted" name
  | None -> check false "EDGE parameterised type name extracted" "none");

  (* A value returning exactly `unit`, with no arrow before it. *)
  check (returns_unit "unit") "EDGE bare unit return" "";
  check (not (returns_unit "reunit")) "EDGE unit must be a whole word" "";

  (* An explicitly configured binary wins over PATH. *)
  (match find_in_path "gospel" with
  | Some real ->
      Unix.putenv "HERMES_GOSPEL" real;
      check (find_gospel () = Some real) "EDGE configured binary preferred" "";
      Unix.putenv "HERMES_GOSPEL" ""
  | None -> incr skipped);

  (* A diagnostic must show the offending token, not merely a line number. *)
  let source = "val f : model:string -> bool\n(*@ r = f ~model x *)\n" in
  (match static_findings source with
  | [] -> check false "EDGE rendered diagnostic has context" "no findings"
  | first :: _ ->
      let rendered = render_finding ~source "demo.mli" first in
      let has needle =
        let rec loop index =
          index + String.length needle <= String.length rendered
          && (String.sub rendered index (String.length needle) = needle
             || loop (index + 1))
        in
        loop 0
      in
      check (has "demo.mli:1:9:") "EDGE diagnostic carries line and column" rendered;
      check (has "^") "EDGE diagnostic underlines the token" rendered;
      check (has "in: declaration of `f`") "EDGE diagnostic names the construct"
        rendered;
      check
        (has "root cause:" && has "fix:")
        "EDGE diagnostic separates cause from fix" rendered;
      (* Without source there is no excerpt, but the finding still renders. *)
      let bare = render_finding "demo.mli" first in
      check
        (String.length bare > 0 && not (String.contains bare '^'))
        "EDGE diagnostic renders without source" bare);

  (* Constructs are named by kind and subject. *)
  (match parse "(*@ axiom f_idem: forall x: int. f x = x *)\n" with
  | [ block ] ->
      check (describe_block block = "axiom `f_idem`") "EDGE axiom named"
        (describe_block block)
  | _ -> check false "EDGE axiom named" "unexpected block count");
  (match parse "(*@ function rec fact (x: integer) : integer = x *)\n" with
  | [ block ] ->
      check
        (describe_block block = "function specification for `fact`")
        "EDGE function named" (describe_block block)
  | _ -> check false "EDGE function named" "unexpected block count");
  (match parse "(*@ type ghosty *)\n" with
  | [ block ] ->
      check (describe_block block = "ghost declaration") "EDGE ghost named"
        (describe_block block)
  | _ -> check false "EDGE ghost named" "unexpected block count");

  (* Columns are 1-based and reset on each line. *)
  check (column_of "ab\ncd" 0 = 1) "EDGE column at start of file" "";
  check (column_of "ab\ncd" 3 = 1) "EDGE column resets after newline" "";
  check (column_of "ab\ncd" 4 = 2) "EDGE column counts within a line" "";

  (* A checker killed by a signal is a failure, not a pass. *)
  let staging = Filename.temp_file "gospel-lint-signal-" "" in
  Sys.remove staging;
  Unix.mkdir staging 0o700;
  Fun.protect
    ~finally:(fun () ->
      Array.iter (fun n -> Sys.remove (Filename.concat staging n)) (Sys.readdir staging);
      Unix.rmdir staging)
    (fun () ->
      let suicidal = Filename.concat staging "gospel" in
      let channel = open_out suicidal in
      output_string channel "#!/bin/sh\nkill -9 $$\n";
      close_out channel;
      Unix.chmod suicidal 0o755;
      Unix.putenv "HERMES_GOSPEL" suicidal;
      with_temp "val f : int -> int\n(*@ r = f x *)\n" (fun path ->
          check (quiet path <> Verdict_ok) "EDGE signalled checker is not a pass" "");
      Unix.putenv "HERMES_GOSPEL" "")

(* ------------------------------------------------------- STRUCTURE layer *)
(* Replaces a line-coverage tool. Every rule, verdict, level and block kind
   must be exercised by the fixtures above, so a new rule without a test fails
   the suite instead of silently lowering coverage. *)

let structure_layer () =
  let fixture_rules =
    List.sort_uniq compare
      (List.concat_map (fun (_, bad, _) -> rules_for bad) rule_fixtures)
  in
  let declared = List.sort_uniq compare (List.map fst !rules) in
  let missing = List.filter (fun r -> not (List.mem r fixture_rules)) declared in
  check (missing = []) "STRUCTURE every declared rule has a fixture"
    (String.concat "," missing);

  let levels =
    List.sort_uniq compare (List.concat_map (fun (_, bad, _) -> levels_for bad) rule_fixtures)
  in
  check
    (List.for_all (fun l -> List.mem l levels) [ L1; L2; L3; L4 ])
    "STRUCTURE levels L1-L4 all exercised" "";

  (* L5 is the environment level: produced by linter-internal and by the
     not-checkable path, both exercised above. *)
  let internal =
    let original = !rules in
    rules := [ ("boom", fun _ _ -> failwith "x") ];
    let result = levels_for "val f : int -> int\n(*@ r = f x *)\n" in
    rules := original;
    result
  in
  check (List.mem L5 internal) "STRUCTURE level L5 exercised" "";

  let kinds =
    List.sort_uniq compare
      (List.concat_map
         (fun (_, source) -> List.map (fun (b : block) -> b.kind) (parse source))
         surface)
  in
  check
    (List.for_all (fun k -> List.mem k kinds)
       [ Val; Type_; Function_; Axiom; Ghost; Continuation ])
    "STRUCTURE every block kind exercised"
    (String.concat "," (List.map kind_name kinds));

  let verdicts = [ Verdict_ok; Verdict_errors; Verdict_not_checkable;
                   Verdict_unavailable; Verdict_internal ] in
  check
    (List.sort_uniq compare (List.map exit_code verdicts) = [ 0; 1; 2; 3; 4 ])
    "STRUCTURE every verdict has a distinct exit code" ""

let () =
  print_endline "gospel-lint test suite (OCaml)";
  Printf.printf "gospel binary: %s\n\n"
    (Option.value (find_gospel ()) ~default:"NOT FOUND (some layers skipped)");
  List.iter
    (fun (name, layer) ->
      layer ();
      Printf.printf "  %-18s done\n" name)
    [ ("tdd", tdd_layer); ("bdd", bdd_layer); ("surface", surface_layer);
      ("property", property_layer); ("chaos", chaos_layer);
      ("robustness", robustness_layer); ("edges", edges_layer);
      ("structure", structure_layer) ];
  Printf.printf "\npassed: %d   failed: %d   skipped: %d\n" !passed
    (List.length !failures) !skipped;
  List.iter (fun failure -> print_endline ("  FAIL  " ^ failure)) (List.rev !failures);
  if !failures <> [] then exit 1
