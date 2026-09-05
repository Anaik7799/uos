(* Safeties around ONNX Runtime, which must all pass BEFORE any call.

   Every other oracle in this repository runs in its own process. ffmpeg,
   VLC, GStreamer, z3, stanc and the yolo CLI can all crash without
   taking the harness with them, and their failures arrive as exit
   codes we read. ORT is different: it is bound in-process, so a fault
   is OUR segfault, in the address space that holds the evidence store.

   The mandatory rules already say a signal or exit 139 is a BLOCKING
   crash observation whose bytes and coordinate must be preserved, and
   which later passing runs do not resolve. This module exists so that
   observation is made in a child rather than in us.

   -------------------------------------------------------------------
   FOUR GATES, AND THE FOURTH IS THE ONE THAT MATTERS

   1. THE .so AND THE HEADER MUST BE THE SAME VERSION. OrtApi is a
      400-entry vtable and its ordinals are NOT stable across releases.
      A header that drifts from the library gives a table that looks
      right and calls the wrong function pointer.

   2. THE ORDINAL TABLE MUST MATCH THE HEADER IT CAME FROM, by digest.
      A regenerated header with a stale table is the same failure with
      one more step.

   3. AN ORDINAL BEYOND THE TABLE IS REFUSED. Indexing past the vtable
      reads whatever follows it in memory and calls that.

   4. THE FIRST CALL HAPPENS IN A SUBPROCESS. If the binding is wrong,
      the child dies and we read exit 139 — an observation. In-process
      it is our death, and nothing records why. Nothing may call ORT
      in-process until the child has survived. *)

type gate =
  | Version_match of { so : string; header : string }
  | Table_integrity of { digest : string }
  | Ordinal_bounds of { max_ordinal : int }
  | Child_survives of { exit_code : int }

type verdict = Passed of gate | Failed of gate * string | Unavailable of string

val verdict_name : verdict -> string
val gate_name : gate -> string

val so_path : string
val header_path : string
val table_path : string

(* Version parsed from the .so soname and from the header's
   ORT_API_VERSION. Mismatch is gate 1. *)
val so_version : unit -> string option
val header_version : unit -> string option

val check_version : unit -> verdict
val check_table : unit -> verdict

(* Refuses an ordinal at or beyond the table length. Total: a negative
   or oversized index is a refusal, never a clamp — clamping would call
   a real but WRONG function. *)
val check_ordinal : int -> verdict

(* Run [argv] as a child and classify how it died. A signal is preserved
   as a crash observation with its number, never folded into "failed".
   This is what gate 4 uses, and it is the reason the binary it runs
   must be a standalone probe rather than this process. *)
val run_isolated : string list -> verdict

(* Every gate, in order, stopping at the first failure. ORT MUST NOT BE
   CALLED IN-PROCESS UNLESS THIS RETURNS ALL-PASSED. *)
val preflight : ?probe:string list -> unit -> verdict list
val all_passed : verdict list -> bool

val render : verdict list -> string
