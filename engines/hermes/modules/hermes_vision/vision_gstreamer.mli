(* Fractal ontology of GStreamer.

   GStreamer is not a second ffmpeg with different flags. ffmpeg is a
   transform — arguments in, process runs, exit code out — and its
   ontology is the six pipeline stages. GStreamer is a STATE MACHINE with
   asynchronous transitions, and almost everything that goes wrong with
   it goes wrong in a transition that reported success.

   That is why this module is shaped around states rather than stages:
   the failures worth catching are `ASYNC` changes that never complete,
   dynamic pads that never link, and live sources that return
   `NO_PREROLL` where a caller expected `SUCCESS`. None of those is an
   error; all of them are a pipeline that runs forever and emits
   nothing. *)

(* -------------------------------------------------------- the states *)

type state = Null | Ready | Paused | Playing

val states : state list
val state_name : state -> string

(* Adjacent transitions only. GStreamer refuses a jump from NULL to
   PLAYING as a single change; modelling it as legal here would let a
   caller believe a pipeline reached PLAYING without ever prerolling. *)
val legal_transition : state -> state -> bool

(* The result of asking for a state change. THE THIRD AND FOURTH ARE THE
   POINT: [Async] means the change was accepted and has NOT happened
   yet, and [No_preroll] means it will never preroll because the source
   is live. Treating either as success is the single most common way a
   GStreamer pipeline is reported working while producing nothing. *)
type change = Success | Async | No_preroll | Failure of string

val change_name : change -> string

(* Has the pipeline actually reached the state? [Async] answers NO — the
   caller must wait for the transition to complete before claiming it.
   This is the function that makes the distinction unavoidable. *)
val reached : change -> bool

(* ------------------------------------------------------ capabilities *)

type element =
  | Src_file        (* filesrc *)
  | Src_test        (* videotestsrc *)
  | Src_udp         (* udpsrc *)
  | Decode_bin      (* decodebin: DYNAMIC pads *)
  | Convert         (* videoconvert *)
  | Encode_h264     (* x264enc *)
  | Encode_vp8      (* vp8enc *)
  | Sink_hls        (* hlssink2 *)
  | Sink_udp        (* udpsink *)
  | Sink_app        (* appsink: buffers leave the graph into our code *)

val elements : element list
val element_name : element -> string   (* the GStreamer factory name *)

val level : element -> Fractal_diagnostic.fractal_level
val origin : element -> Fractal_diagnostic.origin

(* What must be true for the element to be doing its job. *)
val law : element -> string

(* The way it reports success while delivering nothing — the state a
   probe must be written against. *)
val hazard : element -> string

(* Which pipeline stage this element serves, joining this ontology to
   Vision_ontology so a GStreamer fault names a stage rather than an
   element nobody outside GStreamer recognises. *)
val serves : element -> Vision_ontology.stage

(* --------------------------------------------------- declared intent *)

(* A pipeline as data, not as a gst-launch string. [description] renders
   the canonical `a ! b ! c` form, and [argv] produces an argument vector
   for gst-launch-1.0 with no shell anywhere — the same discipline as
   Vision_intent, for the same reason. *)
type pipeline = { elements : element list; properties : (string * string) list }

val description : pipeline -> string
val argv : pipeline -> string list

(* Linkable iff adjacent elements can negotiate: a source must come
   first, a sink last, and an encoder must be preceded by something that
   produces raw video. A pipeline that cannot link is refused HERE rather
   than at runtime, where it manifests as a hang. *)
val well_formed : pipeline -> (pipeline, string) result

(* The reference pipelines this repository uses. *)
val test_to_hls : dir:string -> pipeline
val file_to_hls : path:string -> dir:string -> pipeline

val render : unit -> string
