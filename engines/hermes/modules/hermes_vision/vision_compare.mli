(* Frame-by-frame comparison, as a probe that can fail.

   The 54.80 dB result was, until now, a number in a document. Nothing
   re-ran it, so a regression in the capture path would not have failed a
   build — the one claim in this module not backed by something that can
   say no. This is that something.

   -------------------------------------------------------------------
   A SIMILARITY SCORE IS NOT EVIDENCE WITHOUT A CONTROL

   A high score only shows the metric agreeing with whatever it was
   handed. The measured separation is what makes it a verdict:

     browser capture vs the source   54.80 dB
     browser capture vs a decoy       9.06 dB   at every offset tried

   [default_threshold] sits at 30 dB — far above the decoy and far below
   the match, so it is not tuned to either. [discriminates] runs BOTH
   comparisons and requires the control to fail, because a threshold
   that only ever sees matching input has never been shown to reject
   anything.

   -------------------------------------------------------------------
   ALIGNMENT IS PART OF THE MEASUREMENT

   A recording of a live stream starts at an arbitrary point in it, so
   comparing from t=0 scores two identical videos as different. The
   probe searches a bounded window of offsets and takes the best, and
   reports WHICH offset won — an offset at the edge of the window means
   the true alignment is probably outside it and the score is suspect. *)

type verdict =
  | Matches of { psnr : float; offset : float }
  | Differs of { psnr : float; offset : float }
  | Unmeasurable of string   (* a file is missing, ffmpeg is absent, output unparsable *)

val verdict_name : verdict -> string

(* dB. Above this two clips are the same content; below, they are not.
   Chosen from the measured separation, not tuned to a run. *)
val default_threshold : float

(* Compare [candidate] against [reference], searching [offsets] seconds
   into the reference for the best alignment.

   NEVER RAISES, and never reports a match it could not measure: a
   missing file, an absent ffmpeg or output it cannot parse is
   [Unmeasurable], which is the third verdict and not a failure of the
   candidate. *)
val compare :
  ?threshold:float -> ?offsets:float list -> ?duration:float -> ?skip:float ->
  reference:string -> candidate:string -> unit -> verdict

(* The gate. Requires the candidate to MATCH the reference AND to DIFFER
   from the control — so a probe that would accept anything fails here
   rather than passing quietly. [Error] names which half failed. *)
val discriminates :
  ?threshold:float -> reference:string -> candidate:string -> control:string -> unit ->
  (string, string) result

(* As a stage observation, so a comparison joins the same three-verdict
   accounting as every other probe and can contribute to coverage. *)
val observe :
  ?threshold:float -> reference:string -> candidate:string -> unit ->
  Vision_controller.observation
