(* Raven/Nx: the comparison metric, computed independently of ffmpeg.

   Vision_compare asks ffmpeg's psnr filter whether two clips match.
   That is a closed loop: ffmpeg produced the stream, ffmpeg encoded the
   capture, and ffmpeg then judges whether they agree. A systematic
   error anywhere in that chain is invisible, because the same code is
   on both sides of the question.

   Here ffmpeg still DECODES — it is the decoder, and pretending
   otherwise would mean reimplementing codecs — but the arithmetic that
   produces the verdict is Nx. Two independent implementations that
   agree is evidence; one implementation agreeing with itself is not.

   The two figures should be close. [agrees_with] states how close, and
   a DISAGREEMENT is a finding about the comparison rather than about
   the video. *)

(* PSNR in dB between two raw 8-bit grayscale planes of the given
   geometry. [None] when a plane cannot be read or the sizes disagree —
   never a score computed from a partial read. *)
val psnr_gray : ref_plane:string -> cand_plane:string -> width:int -> height:int ->
  (float, string) result

(* Extract one frame as a raw grayscale plane. ffmpeg decodes; nothing
   here judges. *)
val extract_gray : video:string -> at:float -> out:string -> width:int -> height:int ->
  (unit, string) result

(* Compare two videos at a given offset, decoding with ffmpeg and
   scoring with Nx. *)
val compare_at : reference:string -> candidate:string -> ref_at:float -> cand_at:float ->
  width:int -> height:int -> (float, string) result

(* Do the independent figure and ffmpeg's agree within [tolerance] dB?
   A disagreement is a finding about the COMPARISON, not the video —
   which is the whole reason for computing it twice. *)
val agrees_with : nx:float -> ffmpeg:float -> tolerance:float -> bool
