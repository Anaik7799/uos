(* Declarative intent for the vision pipeline.

   An intent says WHAT signal should exist, never how to spell an ffmpeg
   command line. [argv] is the only thing that knows ffmpeg's syntax, and
   it is a total function from the intent — so a pipeline is reviewed as
   data, and two intents that differ produce commands that differ.

   -------------------------------------------------------------------
   WHY argv IS A LIST AND NOT A STRING

   The existing Ffmpeg_intent.compile_intent builds a single shell
   string, which the controller then hands to Unix.system. That means
   every field is concatenated into a shell, so a source path containing
   a space, a quote or a semicolon is a command-injection, and the
   caller cannot exec the result without a shell in the middle. Here the
   compiled form is an ARGUMENT VECTOR: it is passed to execvp with no
   shell anywhere, so no value in an intent can ever be interpreted as
   syntax. [argv_is_shell_free] states that as a checkable property. *)

type codec = H264 | H265 | VP8 | Copy

type source =
  | Test_pattern of { width : int; height : int; rate : int; label : string }
      (* A synthesised signal. [label] is burned into every frame together
         with the frame number, which is what makes "is the browser
         showing THIS stream" a decidable question rather than a visual
         impression. *)
  | Loop_file of { path : string }
  | Udp_ingest of { port : int }

type sink =
  | Hls of { dir : string; segment_seconds : int; window : int }
  | Udp_out of { host : string; port : int }
  | Mp4_file of { path : string }
      (* A finite, seekable file. This is what a browser <video loop> can
         decode NATIVELY: Chromium has no HLS demuxer, so serving a
         playlist to it produces a player that reports readiness and
         paints nothing -- the Play stage hazard, exactly. *)
  | Discard  (* -f null: the signal is produced and measured, not kept *)

type intent = {
  source : source;
  codec : codec;
  sink : sink;
  loop : bool;              (* restart the source forever when it ends *)
  realtime : bool;          (* -re: pace at wall clock, as a live source *)
  duration_s : int option;  (* None = unbounded *)
}

val codec_name : codec -> string
val source_name : source -> string
val sink_name : sink -> string

(* Reject an intent that cannot describe a real signal BEFORE any process
   is started: non-positive geometry or rate, a port outside 1..65535, an
   empty path, a segment window that cannot hold a segment. Returning the
   intent rather than unit means a validated intent is a distinct value a
   caller can be required to hold. *)
val validate : intent -> (intent, string) result

(* The argument vector, argv.(0) = "ffmpeg". TOTAL: every intent compiles.
   Deterministic: equal intents give equal vectors. *)
val argv : intent -> string list

(* No element of [argv] needs shell quoting to survive execvp — there is
   no shell, so this is a property of the VALUES, asserting that none of
   them smuggles syntax. Checked in the tests against hostile inputs. *)
val argv_is_shell_free : intent -> bool

(* One line for an operator, derived from the intent, never authored
   beside it. *)
val describe : intent -> string

(* The reference pipeline this repository ships: a frame-numbered test
   pattern, encoded H264, packaged as HLS into [dir], looping forever.
   Used by the simulated-signal stage probes and by the end-to-end run,
   so both measure the same declaration. *)
val looping_test_pattern : dir:string -> intent

(* The same pipeline, but fed from a real encoded file (the Big Buck
   Bunny sample) instead of a generated pattern. NOTE: a file carries no
   burned-in ordinal, so Observe cannot compare ordinals for this source
   until an overlay filter is added — it will report Unknown rather than
   pretend. *)
val looping_source_file : path:string -> dir:string -> intent
