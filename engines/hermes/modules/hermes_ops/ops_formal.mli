(* Gates for the formal services — Gospel, Rocq/Coq, Quint, Lean, Z3.

   The dossier's formal-technology table said these artifacts were present
   and run by nothing. That is the state R10 warns about: a `.v` file on
   disk is not a proof discharged, and a repository that mistakes the two
   comes to believe it is verified. This module closes the gap by actually
   invoking the checkers.

   ---------------------------------------------------------------------
   THREE VERDICTS, AND THE THIRD IS THE ONE THE RULES ARE ABOUT

   [Discharged]   the checker ran and accepted.
   [Refuted]      the checker ran and rejected — a real finding, and the
                  most valuable outcome this module can produce.
   [Unavailable]  the checker could not be run, or there was nothing to
                  check.

   **A missing external tool is UNAVAILABLE, never Discharged.** That is
   not a convenience, it is the repository's standing rule: external tools
   are oracles, not authors, and missing external evidence is unavailable
   or blocked — never passing (R2). A gate that reports green when the
   prover is absent is worse than no gate, because it converts silence
   into a claim.

   **A service with NO ARTIFACTS is Unavailable, never vacuously
   discharged.** This is a mistake this repository has already made and
   paid for: `toolchain_check` once passed vacuously on zero dune files,
   reporting health it had not measured. Zero artifacts means the question
   was not asked, and "not asked" is not "answered yes".

   ---------------------------------------------------------------------
   ARTIFACTS ARE DISCOVERED, NOT LISTED

   A hand-kept list stops covering a file the moment someone adds one, and
   nobody notices because the count still looks healthy. Each service
   declares an extension and a root; the files are found by walking. *)

type verdict =
  | Discharged
  | Refuted of string     (* the checker's own words, trimmed *)
  | Unavailable of string (* why — absent tool, or nothing to check *)

type service = {
  sname : string;
  tool : string;              (* the binary probed for availability *)
  extension : string;         (* the artifact extension, e.g. ".gospel" *)
  roots : string list;        (* where to look *)
}

type check = {
  service : string;
  artifact : string;
  verdict : verdict;
  duration_ms : float;
}

type report = {
  checks : check list;
  discharged : int;
  refuted : int;
  unavailable : int;
}

val string_of_verdict : verdict -> string

(* The services this repository declares. Extending it is the way to add a
   formal technology to the gate. *)
val services : service list

(* Artifacts found for a service, sorted. Empty is a meaningful answer and
   the caller must treat it as [Unavailable], not as success. *)
val artifacts_of : service -> string list

(* Is the checker on PATH? Probed rather than assumed — the switch that
   builds this workspace is not the one an operator's shell defaults to. *)
val tool_available : service -> bool

(** Check one artifact using the service's safe invocation. Gospel inputs are
    mirrored into a private temporary directory because Gospel writes sidecars
    beside its input. *)
val check_artifact : service -> string -> check

(* Run every service over every artifact it finds. TOTAL: a checker that
   crashes, times out or is absent yields [Unavailable] or [Refuted],
   never an exception. *)
val run : ?only:string -> unit -> report

(* Per-service summary, then the total. Refutations print the checker's
   own output — the finding is the point, and paraphrasing a prover is how
   a real refutation gets softened into a warning. Returns the exit code:
   non-zero if anything was refuted OR unavailable, because an ungated
   formal artifact is exactly the state this module exists to end. *)
val render : report -> string * int
