(* Repository verification as a DECLARATIVE INTENT executed by the swarm.

   The purpose is offload. A verification pass used to be an agent looping
   `dune exec` over ~40 executables and pulling every result into its own
   context to conclude "37/37". The conclusion is one line; the evidence
   was tens of thousands of bytes of scrollback. This module runs the same
   pass as a `Sop_execution` DAG and returns the line, keeping the bytes
   out of any agent's context unless something actually failed.

   Two properties make that safe rather than merely quieter:

   FAILURE IS LOUD. A passing run prints one summary line. A failing run
   prints the failing suite's own output in full. Suppressing detail on
   success is economy; suppressing it on failure would be the thing this
   repository exists to prevent.

   THE VERDICT IS THE EXIT CODE. Every suite's REAL exit status is
   captured — never a pipeline's, which is the mistake that once let
   `dune build | head -3 && echo BUILD_OK` report success for a failed
   build (R19 clause 4).

   ---------------------------------------------------------------------
   R14 — this mirrors zigvm's `suite_runner`

   Deliberately the same shape: a three-valued verdict, one result record
   per case carrying its own output and a detail string, and a runner that
   is PURE ORCHESTRATION holding no domain semantics. The third verdict is
   the load-bearing one. zigvm called it UNTESTED; here it is [Skipped],
   and it exists because a suite that could not be run must never be
   counted as one that passed (R2). A binary that is absent is unavailable,
   never green.

   ---------------------------------------------------------------------
   WHY A SWARM DAG AND NOT A LOOP

   `Sop_execution` spawns an OCaml 5 Domain per ready step, wave by wave,
   respecting the dependency graph — so the build runs first, once, and
   the suites then run in parallel. It also carries the fractal telemetry
   and the job/temporal record for free. A hand-written loop would have to
   reimplement all three, which is what R14 exists to stop.

   ---------------------------------------------------------------------
   AN HONEST NON-MEASUREMENT

   `Sop_execution`'s step actions report a token pair, and this module
   passes (0, 0) for every step. That is not an oversight: nothing here
   measures tokens, and filling the field with a plausible number would
   put an invented measurement into a dashboard that reports it as fact
   (R16). What IS measured is reported: suites run, and the bytes of
   output that did not have to enter an agent's context. *)

type verdict =
  | Passed
  | Failed
  | Skipped  (* could not be run — disclosed and counted, never green *)

type profile =
  | Fast
  | Full

type monitoring_path = Control_path | Data_path

type capture_observation = {
  deadline_expired : bool;
  residual_group_terminated : bool;
  direct_child_reaped : bool;
  bytes : int;
}

type monitoring_metric = {
  id : string;
  channel : string;
  path : monitoring_path;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  value : int64;
}

type case_result = {
  name : string;
  verdict : verdict;
  exit_code : int;
  output : string;      (* the suite's own bytes, kept for the failure path *)
  detail : string;      (* one line: the summary the suite printed, or why it was skipped *)
  duration_ms : float;
  capture : capture_observation option;
}

type report = {
  profile : profile;
  cases : case_result list;
  passed : int;
  failed : int;
  skipped : int;
  bytes_captured : int;   (* output that stayed out of context on success *)
  wall_ms : float;
  monitoring : monitoring_metric list;
}

val string_of_verdict : verdict -> string
val string_of_profile : profile -> string

(* The suites this repository verifies with, DERIVED from the filesystem
   rather than listed here — a hand-maintained list silently stops
   covering a suite the moment someone adds one, which is the failure mode
   `toolchain_check` was rebuilt to remove. Returns (name, executable
   path) pairs, sorted. *)
(* Run a command, returning its REAL exit code and its combined output.

   LAW — IT MUST NOT DEADLOCK ON A LARGE REPORT. A child that writes more
   than one pipe buffer must still terminate and be captured. The earlier
   implementation drained stdout and stderr in sequence and hung forever
   on a suite that emitted ~169 KB, which is to say it hung on exactly the
   suites that had a failure to report. Exposed so that law is tested
   rather than assumed. *)
val run_capture : ?timeout_seconds:int -> string -> int * string
val capture_command : ?timeout_seconds:int -> string -> int * string * capture_observation

val discover_suites : profile -> (string * string) list

(* The exact bounded invocation for a discovered suite.  Suite-specific
   admission arguments are declared here rather than silently omitted by the
   generic runner. *)
val suite_command : ?z3:string -> name:string -> exe:string -> unit -> string

(* The counts DERIVED from the cases. Exposed because a report whose
   summary disagrees with its own case list is a lie waiting to be read,
   and because the arithmetic is only testable if it can be called with
   cases a real run would not produce. TOTAL. *)
val summarise : ?profile:profile -> ?wall_ms:float -> case_result list -> report
val monitoring_gaps : report -> string list

(* Run the pass. [build] runs `dune build` as a dependency of every suite,
   so a broken tree fails once and loudly instead of ~40 times. *)
val run : ?profile:profile -> ?build:bool -> unit -> report

(* One line on success; the full output of every failing suite first, on
   failure. Returns the process exit code the caller should use. *)
val render : ?require_complete:bool -> report -> string * int
