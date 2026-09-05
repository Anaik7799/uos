(* Graceful restart.

   The existing [Vision_control.restart] is stop-then-start. For a test
   pipeline that is adequate; for a media server it is wrong twice over.
   Every viewer sees a refused connection, and it reports success as
   long as the START half worked — so a replacement that comes up and
   immediately fails is indistinguishable from one that works.

   -------------------------------------------------------------------
   THE ORDER IS THE WHOLE DESIGN

   Drain, start, GATE, and only then retire the old instance. The old
   one keeps serving until the new one has been shown to work, so a bad
   image costs nothing. Reversing the last two steps — retire, then
   check — is the ordinary way a "graceful" restart takes a service down
   and cannot get it back.

   And "the process is running" is not the gate. That is precisely the
   Play hazard in another costume: a media server can be running,
   listening, and serving nothing. The gate must ask the same questions
   the stage probes ask.

   -------------------------------------------------------------------
   TRIGGER ON A DIGEST, NOT A TIMESTAMP

   An mtime changes on every rebuild even when the output is identical,
   so an mtime trigger restarts a live service for nothing. A digest
   changes only when the image does. And when the digest CANNOT be
   computed the answer is "do not restart": acting on unknown state is
   worse than not acting, because the running instance is known to
   work. *)

type phase =
  | Draining              (* stopped accepting; in-flight responses finishing *)
  | Starting              (* the replacement is coming up *)
  | Gating                (* the replacement is being health-checked *)
  | Promoted              (* the replacement passed; the old one is retired *)
  | Rolled_back of string (* the replacement failed; the OLD one still serves *)

val phase_name : phase -> string

(* Draining -> Starting -> Gating -> (Promoted | Rolled_back). Nothing
   else. In particular there is no transition from Starting straight to
   Promoted: a replacement that was never gated has not been shown to
   work, and allowing that edge is how the gate gets skipped under time
   pressure. *)
val legal_transition : phase -> phase -> bool
val well_formed : phase list -> bool
val terminal : phase -> bool

(* The operations a restart needs, injected so the FAILURE paths can be
   tested without processes, ports or a real service. A restart whose
   rollback has never been exercised is a rollback that does not work. *)
type ops = {
  drain : unit -> unit;
      (* stop accepting and let in-flight responses finish, bounded *)
  start : unit -> (int, string) result;   (* the replacement's pid *)
  health : int -> bool;
      (* Gate the REPLACEMENT. Must ask what the stage probes ask, not
         merely whether the process exists. *)
  retire : unit -> unit;                  (* stop the OLD instance *)
  kill_new : int -> unit;                 (* rollback: stop the replacement *)
}

type outcome = { trace : phase list; final : phase; old_retired : bool; new_pid : int option }

val succeeded : outcome -> bool

(* Run the restart.

   LAW 1 — THE OLD INSTANCE IS RETIRED ONLY AFTER THE GATE PASSES. On
   any failure [retire] is never called and the old instance keeps
   serving.

   LAW 2 — A FAILED GATE ROLLS BACK. [kill_new] is called so a broken
   replacement does not linger holding resources beside the instance
   that is still working.

   LAW 3 — THE TRACE IS WELL-FORMED ON BOTH PATHS, and carries the cause
   on the failing one. *)
val execute : ops -> outcome

(* ------------------------------------------------------ the trigger *)

(* MD5 of the file, or None when it cannot be read. *)
val digest_of_file : string -> string option

(* Should a restart happen? True only when both digests are known AND
   differ. Unknown on either side answers FALSE: the running instance is
   known to work, and restarting on an unreadable image trades a working
   service for a guess. *)
val image_changed : running:string option -> current:string option -> bool

val render : outcome -> string

(* THE SUPERVISOR STEP (restart / Not_provided). A digest change must
   EVENTUALLY produce a restart, or a fix never reaches production while
   everything reports healthy. One tick: compare the running digest
   against the image on disk and restart when they differ.

   [None] means no restart was called for — which is the normal answer
   and must not be confused with a restart that failed. Returns the new
   digest on success so the caller can carry it forward; a caller that
   forgets would restart forever. *)
val supervise_once :
  running:string option -> image:string -> restart:(unit -> (string, string) result) ->
  (string * string, string) result option
