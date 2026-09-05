(* Mutation testing as a swarm DAG — the second offload, and the larger one.

   Every agent this session spent thousands of tokens on the same loop:
   copy the file, apply a textual mutant, rebuild, re-run the suite, read
   the output, restore, repeat. None of that is reasoning. It is a
   deterministic procedure whose only interesting output is one line per
   mutant, and it belongs in OCaml rather than in a context window.

   ---------------------------------------------------------------------
   THREE VERDICTS, AND THE THIRD IS THE POINT

   [Killed]    the named killer test failed, as predicted.
   [Survived]  the mutant took, the suite stayed green.
   [Void]      the edit did not apply, or the tree did not compile.

   A [Void] run is NOT a result — a perl pattern that silently matched
   nothing, or a mutant that fails to typecheck, tells you nothing about
   your tests, and every agent this session that reported one recorded it
   as void rather than counting it. The runner enforces that distinction
   by checking the file actually CHANGED before it builds.

   THE RUNNER NEVER CLASSIFIES A SURVIVOR. It reports [Survived] and
   stops. Whether a survivor is an equivalent mutant or a weak test is a
   judgment about intent, and this session produced both kinds within an
   hour of each other — one provably equivalent (a filter over a range
   that could never fire), one a genuinely weak test (a check that
   compared against the constant it was meant to verify). Automating that
   call would launder the second into the first, which is the exact
   failure the whole discipline exists to prevent.

   ---------------------------------------------------------------------
   RESTORATION IS THE SAFETY PROPERTY

   The mutant is applied to a real source file. A runner that leaves a
   mutated file behind has corrupted the repository, and these files are
   untracked while an agent is writing them, so `git restore` cannot save
   it. Every run therefore takes a gold copy first, restores from it in a
   [Fun.protect] finaliser, and VERIFIES the restored bytes equal the
   gold bytes. A restoration that cannot be verified is reported as a
   hard failure, not a warning. *)

type verdict =
  | Killed of string   (* the named killer that fired *)
  | Survived
  | Void of string     (* why this run produced no result *)

type mutant = {
  name : string;
  file : string;          (* the source file to mutate *)
  find : string;          (* literal text to replace — not a regex, so a
                             pattern cannot silently match nothing *)
  replace : string;
  expect_killer : string; (* substring of the killer test's name *)
}

type outcome = {
  mutant : string;
  verdict : verdict;
  failures : string list;  (* the check names that failed under the mutant *)
  duration_ms : float;
}

type report = { outcomes : outcome list; killed : int; survived : int; void : int }

val string_of_verdict : verdict -> string

(* Run one mutant: gold-copy, apply, build, run the suite, restore,
   verify restoration. [suite] is the test executable's dune path. TOTAL —
   every failure path yields a [Void] or a [Survived], never an exception
   and never a mutated file left on disk. *)
val run_one : suite:string -> mutant -> outcome

(* Run a table. Sequential BY DESIGN, unlike the verification DAG: the
   mutants edit files in a shared tree, so running two at once would have
   them overwrite each other's gold copies. The offload here is context,
   not wall-clock. *)
val run : suite:string -> mutant list -> report

(* One line per mutant, then the summary. A survivor is stated as a
   survivor and never softened — it is the finding, not the failure. *)
val render : report -> string * int
