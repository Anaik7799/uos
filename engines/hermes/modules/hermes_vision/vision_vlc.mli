(* Fractal ontology of VLC.

   VLC's role here is not to be a third way of transcoding. It is an
   INDEPENDENT DECODER, and that is its whole evidentiary value: with
   only one decoder in the system, "the browser shows nothing" and "the
   stream is broken" are the same observation. With a second, they
   separate — which is the difference between a diagnosis and a guess.

   -------------------------------------------------------------------
   VLC'S CHARACTER IS FORGIVENESS, AND THAT IS THE HAZARD

   ffmpeg is a transform and GStreamer is a state machine. VLC is a
   CONSUMER PLAYER, engineered so that a person watching a damaged file
   still sees a picture. It skips corrupt frames, falls back through
   demuxers, drops a missing element from a stream-output chain and
   carries on, and reports `Ended` where a harness wanted `Error`.

   Every one of those behaviours is correct for a media player and
   actively hostile to a harness, because each converts a defect into a
   successful-looking playback. So the laws below are written against
   VLC's forgiveness rather than against its failures: the question is
   never "did VLC play it" but "did VLC play it WITHOUT having to
   forgive anything". *)

(* --------------------------------------------------------- the states *)

(* libvlc's player states. [Ended] and [Error] are BOTH terminal, and
   telling them apart matters: VLC frequently reaches [Ended] on input
   it could not fully decode, so [Ended] alone is not evidence the media
   was intact. *)
type state =
  | Nothing_special
  | Opening
  | Buffering
  | Playing
  | Paused
  | Stopped
  | Ended
  | Error

val states : state list
val state_name : state -> string
val terminal : state -> bool

(* Has playback demonstrably produced pictures? [Playing] alone does not
   qualify — VLC enters [Playing] while still buffering, so a caller
   that treats it as proof of decode is reading an intention, not an
   outcome. Requires the decoded-picture counter to have advanced. *)
val decoded : state -> pictures:int -> bool

(* ---------------------------------------------------- the forgiveness *)

(* The ways VLC succeeds while hiding a defect. Each is a real behaviour
   of the player, and each must be REPORTED rather than enjoyed: a run
   in which any of these fired is a run whose success is qualified. *)
type leniency =
  | Skipped_frames        (* corrupt frames dropped; playback continued *)
  | Demuxer_fallback      (* the chosen demuxer is not the declared one *)
  | Codec_fallback        (* a software decoder replaced the expected one *)
  | Sout_stage_dropped    (* a stream-output module was missing and skipped *)
  | Ended_without_error   (* terminal Ended after an input it could not fully read *)

val leniencies : leniency list
val leniency_name : leniency -> string
val why_it_hides : leniency -> string

(* A clean run is one in which VLC forgave NOTHING. This is the only
   verdict a harness may treat as evidence about the media. *)
val clean : leniency list -> bool

(* ------------------------------------------------------- capabilities *)

type capability =
  | Play_url          (* open and decode a network URL *)
  | Play_file         (* open and decode a local file *)
  | Sout_transcode    (* #transcode{...} *)
  | Sout_standard     (* :standard{access=...,mux=...,dst=...} *)
  | Snapshot          (* write a decoded frame to disk — the oracle path *)
  | Stats             (* decoded/lost picture counters *)

val capabilities : capability list
val capability_name : capability -> string
val level : capability -> Fractal_diagnostic.fractal_level
val origin : capability -> Fractal_diagnostic.origin
val law : capability -> string
val hazard : capability -> string
val serves : capability -> Vision_ontology.stage

(* ---------------------------------------------------- declared intent *)

type intent = {
  input : string;
  snapshot_to : string option;  (* None = decode without capturing *)
  run_seconds : int;
  verbose : bool;
}

(* An argument vector for `cvlc`, no shell anywhere.

   ALWAYS emits --play-and-exit. Without it VLC never terminates on
   end-of-input, and a harness step that "hangs" is indistinguishable
   from one still working — the same failure mode that made ops verify
   hang on its loudest suite. *)
val argv : intent -> string list

val validate : intent -> (intent, string) result
val render : unit -> string
