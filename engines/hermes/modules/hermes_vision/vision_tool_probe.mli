(* Probes for the GStreamer and VLC hazards.

   The FMEA reported 45 undetected failure modes — hazards declared with
   nothing in the system that would notice them. Sixteen of those are
   GStreamer's and VLC's, and this closes them.

   -------------------------------------------------------------------
   PRESENCE IS NOT THE HAZARD

   `gst-inspect-1.0 x264enc` tells you the plugin exists. Every hazard
   in the GStreamer ontology is about a pipeline that RUNS and emits
   nothing: a decodebin that never links its dynamic pad, an encoder
   that buffers and never flushes, a udpsink shipping into a black hole.
   None of those is an absent plugin, and a probe that checks for one
   would report health while the pipeline hangs.

   So each probe runs a BOUNDED pipeline and asks whether an artefact
   appeared. A timeout with no output is the hazard, caught; a timeout
   with output is a slow machine, and the two are distinguished.

   -------------------------------------------------------------------
   VLC'S HAZARD IS ITS OWN GENEROSITY

   VLC will play a damaged file to completion. Asking "did it play"
   therefore proves nothing. [leniencies_in] reads VLC's own verbose
   output for the moments it forgave something, and a run that forgave
   anything is not evidence about the media (see {!Vision_vlc.clean}). *)

(* Both tools are ORACLES. If one is absent the probe is Unknown, never
   Absent: a missing binary says nothing about our pipeline (R5). *)
val gst_available : unit -> bool
val vlc_available : unit -> bool

(* Run a bounded GStreamer pipeline and report whether it produced the
   artefact it was asked for. [Absent] when the run completed and
   nothing appeared — the silent-hang hazard, caught. *)
val gst_produces :
  ?seconds:int -> pipeline:Vision_gstreamer.pipeline -> expect:string -> unit ->
  Vision_controller.observation

(* The decodebin hazard specifically: a dynamic pad that never links, so
   no data flows and no error is posted. Probed by decoding [path] into
   a counting sink and requiring buffers to have arrived. *)
val gst_decodes : ?seconds:int -> path:string -> unit -> Vision_controller.observation

(* Every leniency VLC's verbose output admits to. Pure: it reads text, so
   the classifier is testable without running VLC. *)
val leniencies_in : string -> Vision_vlc.leniency list

(* Decode [path] with VLC, bounded. [Live] only when VLC exited on its
   own AND forgave nothing. A run that hung is Absent — the Play_url
   hazard — and a run that forgave something is Absent with the
   leniencies named. *)
val vlc_decodes : ?seconds:int -> path:string -> unit -> Vision_controller.observation

(* Every probe here, for the artefacts a caller has. Used by the FMEA to
   report these hazards as detected rather than silent. *)
val all : dir:string -> path:string -> Vision_controller.observation list

(* ------------------------------------------------- OBS and JMeter

   Both are probed differently from GStreamer and VLC, because neither
   can be usefully run in a bounded shot here. OBS needs an OpenGL
   context this host does not have; JMeter needs a target and a plan.
   What both DO produce is a report, and their hazards are visible in
   it — so the probes are PARSERS, pure and testable without either tool
   installed, plus an availability check that answers Unknown rather
   than guessing. *)

val obs_available : unit -> bool
val jmeter_available : unit -> bool

(* OBS writes its three loss counters to its log at the end of an
   output. Parsed rather than summed by us, because the whole point of
   keeping them separate is that each names a different constraint. *)
val losses_in_log : string -> (Vision_obs.loss * int) list

(* OBS's compositing capabilities need GL. On a host without one they
   are UNAVAILABLE, not broken — measured here, where Chromium's
   compositor already exits under Xvfb for the same reason. *)
val obs_capability : Vision_obs.capability -> Vision_controller.observation

(* An OBS log, as a stage observation. [Live] only when the log shows an
   output ran AND all three counters are zero: a compositor's output
   stays continuous while it drops frames, so "it ran" proves nothing. *)
val obs_log : string -> Vision_controller.observation

(* The contaminants a JMeter report betrays. A JTL with no assertion
   columns means every 200 passed unexamined; a summary whose max is far
   beyond its p99 is a generator pause. Pure. *)
val contaminants_in_report : string -> Vision_jmeter.contaminant list

(* A JMeter report, as a stage observation. [Live] requires zero errors
   AND no contaminant: a green report from a contaminated run measures
   the generator, not the server. *)
val jmeter_report : string -> Vision_controller.observation

(* --------------------------------------------------------- libav

   The odd ones out. Every other tool's hazards can be parsed from a
   report or watched from outside; libav runs INSIDE us, so a leaked
   context is invisible to the OCaml GC and a use-after-free surfaces as
   a segfault somewhere unrelated. These probes therefore open and close
   real media and watch the process itself. *)

(* Does the LINKED library agree with the CLI on PATH? A disagreement
   means every ffmpeg-derived capability claim is about a different
   library from the one that will decode our frames. *)
val libav_version_skew : cli_version:string option -> Vision_controller.observation

(* THE LEAK PROBE. One open/close proves nothing — a context that is
   never freed still opens fine. This repeats it and watches RSS, which
   is the only place a leaked AVFormatContext shows up. [Absent] when
   RSS grows past the tolerance; [Unknown] when the process cannot be
   measured. *)
val libav_leaks : ?iterations:int -> ?tolerance_kb:int -> path:string -> unit ->
  Vision_controller.observation

(* The return-code protocol, exercised against the real library: opening
   a real file must classify as success and opening a directory must
   classify as a genuine failure rather than EAGAIN or EOF. *)
val libav_codes : path:string -> Vision_controller.observation
