(* Fractal ontology of OBS Studio.

   The four tools already modelled are a transform (ffmpeg), a state
   machine (GStreamer), a capability lattice (the browser) and a
   forgiving oracle (VLC). OBS is none of those: it is a COMPOSITOR with
   a live output. Sources are composited into a scene at a fixed frame
   rate, and the composite is encoded and shipped while the operator
   watches. Nothing waits for anything.

   That changes what can go wrong. In a transform, a frame that cannot be
   produced stops the pipeline. In a compositor, it is DROPPED and the
   show goes on — which is right for broadcast and disastrous for
   evidence, because the output remains continuous, plausible and
   incomplete.

   -------------------------------------------------------------------
   THREE COUNTERS, THREE DIFFERENT FAULTS

   OBS loses frames in three independent places, and collapsing them
   into "dropped frames" makes the fault undiagnosable:

     - RENDER lag: the compositor could not draw the scene in time (GPU);
     - ENCODING lag: the encoder could not keep up, so frames were
       SKIPPED before they were ever encoded (CPU);
     - NETWORK drop: frames were encoded and then discarded because the
       output could not ship them (link).

   A run is only evidence if all three are zero. Each is attributed to a
   different RCA origin below, because each demands a different response.

   -------------------------------------------------------------------
   OBS NEEDS A GPU, AND THIS HOST DOES NOT HAVE ONE

   OBS composites through OpenGL. Measured on this machine: Chromium's
   viz compositor exits under Xvfb because no usable GL implementation is
   allowed, and OBS depends on the same substrate. Any OBS capability
   here is therefore expected to be UNAVAILABLE rather than failing, and
   [gl_required] marks exactly which ones — so a missing GPU is disclosed
   as an environment gap and never recorded as a defect. *)

(* -------------------------------------------------------- the graph *)

type source_kind =
  | Media_file        (* a file played into the scene *)
  | Display_capture   (* a whole screen *)
  | Window_capture    (* one window — black when it is minimised *)
  | Video_device      (* v4l2 camera *)
  | Browser_source    (* an embedded CEF page *)
  | Image_source      (* a still *)

type output_kind =
  | Stream_rtmp       (* live to an ingest *)
  | Record_file       (* to disk *)
  | Virtual_camera    (* to a v4l2 loopback for other programs *)

type capability =
  | Scene_composite
  | Source of source_kind
  | Output of output_kind
  | Encoder_x264
  | Stats_counters
  | Websocket_control  (* obs-websocket: the remote control surface *)

val capabilities : capability list
val name : capability -> string
val level : capability -> Fractal_diagnostic.fractal_level
val origin : capability -> Fractal_diagnostic.origin
val law : capability -> string
val hazard : capability -> string
val serves : capability -> Vision_ontology.stage

(* Does this capability need a working OpenGL context? On a host without
   one the answer decides UNAVAILABLE versus a real verdict. *)
val gl_required : capability -> bool

(* ------------------------------------------------- the three counters *)

type loss = Render_lag | Encoding_lag | Network_drop

val losses : loss list
val loss_name : loss -> string

(* Where the fault lives. Render is the GPU, encoding is this host's CPU
   budget, network is the link — Environment, Control and Environment
   respectively, and none of them Implementation: a frame OBS could not
   composite says nothing about whether our pipeline is correct (R5). *)
val loss_origin : loss -> Fractal_diagnostic.origin
val loss_meaning : loss -> string

type stats = { rendered : int; render_missed : int; encoded : int; skipped : int; dropped : int }

(* Frames that reached the output intact. NOT [encoded]: encoded frames
   may still be dropped by the network stage afterwards. *)
val delivered : stats -> int

(* Every loss that actually occurred, with its count. Empty means the run
   is usable as evidence; non-empty means the output is continuous but
   incomplete, which is the state a compositor produces and a transform
   never does. *)
val losses_observed : stats -> (loss * int) list

(* A run is evidence only when nothing was lost anywhere. *)
val intact : stats -> bool

val render : unit -> string
