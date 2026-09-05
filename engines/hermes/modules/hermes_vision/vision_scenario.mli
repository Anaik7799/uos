(* Synthetic security scenarios with KNOWN GROUND TRUTH.

   A detector cannot be evaluated against footage nobody has labelled,
   and hand-labelling is slow, subjective and unrepeatable. These
   scenarios are declared as motion laws, so the ground truth is
   DERIVED from the declaration rather than recorded beside it — the
   generator and the expected answer are computed from one description
   and cannot disagree.

   Same discipline that made the PSNR work tractable: the test pattern
   beat Big Buck Bunny because its frame ordinals were known. Here the
   event frames are known for the same reason.

   -------------------------------------------------------------------
   THREE SCENARIOS, EACH WITH A DIFFERENT FAILURE TO CATCH

   INTRUSION — an object crosses a zone boundary at a computable frame.
   Catches a detector that fires on every frame, which is
   indistinguishable from one that works unless you know WHEN the
   crossing happened.

   LOITERING — an object enters, stops, and dwells. Catches a detector
   that alerts on presence rather than dwell time; presence is true from
   the moment it enters, dwell only after the threshold.

   ABANDONED OBJECT — two objects enter, one leaves, one remains.
   Catches a tracker that reassigns identities, because the alert
   depends on telling the departed object from the stationary one. *)

type point = { x : int; y : int }

type scenario =
  | Intrusion of { start_x : int; speed_px_per_frame : int; boundary_x : int }
  | Loitering of { enter_x : int; speed_px_per_frame : int; stop_x : int; dwell_frames : int }
  | Abandoned of { speed_px_per_frame : int; drop_x : int; leaver_exits_x : int }

val name : scenario -> string

(* The event the scenario stages, and the frame it must be detected at.
   Derived from the motion law, so a change to the law moves the
   expected answer with it. *)
type event = { label : string; at_frame : int; at : point }

val ground_truth : scenario -> event list

(* The generator, as an argument vector for ffmpeg. No shell. Frames
   carry their ordinal burned in, so a detection can be located in time
   without trusting the caller's clock. *)
val argv : scenario -> out:string -> frames:int -> string list

(* A scenario whose event never occurs within [frames] is unusable — it
   would be a video in which the right answer is "nothing happened",
   which every broken detector also produces. Refused. *)
val validate : scenario -> frames:int -> (scenario, string) result

val render : scenario -> string
