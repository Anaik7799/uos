(* Fractal ontology of the browser video surface.

   The pipeline's last two stages live in a browser, and a browser is not
   one capability — it is a dozen, each independently present or absent,
   each with its own way of appearing to work. `<video>` exists
   everywhere and decodes nothing without a codec; `readyState` reports
   readiness for a player that never paints; `captureStream` exists on
   the element but yields no track when the decoder never started.

   So the browser gets the same treatment as the pipeline: every
   capability declares the LAW that makes it usable, the HAZARD by which
   it reports success while delivering nothing, and the fractal level and
   RCA origin its failures belong to. A probe is then written against the
   hazard rather than against the presence of the symbol — because
   `typeof v.requestVideoFrameCallback === 'function'` is exactly the
   check that passes on a browser which will never call it. *)

type capability =
  | Media_element        (* <video>: the element itself *)
  | Codec_support        (* canPlayType / MediaCapabilities: will it DECODE *)
  | Frame_callback       (* requestVideoFrameCallback *)
  | Playback_quality     (* getVideoPlaybackQuality *)
  | Capture_stream       (* HTMLMediaElement.captureStream *)
  | Media_recorder       (* MediaRecorder *)
  | Media_source         (* MSE: MediaSource / SourceBuffer *)
  | Web_codecs           (* VideoDecoder / VideoFrame *)
  | Web_rtc              (* RTCPeerConnection *)

val capabilities : capability list
val name : capability -> string

(* Where a capability's failures sit, and who owns them. No browser
   capability is Implementation origin: a browser that lacks a decoder
   says nothing about whether our pipeline is correct, so under R5 an
   absent capability BLOCKS credit and can never deny it. *)
val level : capability -> Fractal_diagnostic.fractal_level
val origin : capability -> Fractal_diagnostic.origin

(* What must be true for the capability to be usable, in one line. *)
val law : capability -> string

(* The way it reports success while delivering nothing. Every probe is
   written against this, never against symbol presence. *)
val hazard : capability -> string

(* A JavaScript expression, GENERATED (see {!Vision_js}), that answers
   the capability's law rather than merely testing that the symbol
   exists. Returns a JSON-shaped object the caller parses. *)
val probe_expression : capability -> string

(* Which pipeline stage a capability serves. This is the join between the
   two ontologies: a missing capability is not an abstract gap, it is a
   named stage that cannot be observed. *)
val serves : capability -> Vision_ontology.stage

(* Capabilities without which a stage cannot be measured at all. If any
   is absent the stage is Unknown, never Absent — nothing was proved. *)
val required_for : Vision_ontology.stage -> capability list

(* -------------------------------------------------------- the engines *)

type engine = Chrome | Edge | Chromium_oss | Firefox | Safari

val engines : engine list
val engine_name : engine -> string

(* Declared support, from vendor documentation — an ORACLE claim, not a
   measurement. [probe_expression] is what measures; this is what we
   expect, and a disagreement between the two is the finding. *)
val declared : engine -> capability -> bool

(* Codecs the engine is documented to decode. The split that matters
   here: open-source Chromium builds frequently ship without H.264, and
   that failure presents exactly as the Play hazard. *)
val codecs : engine -> string list

(* Codecs playable on every listed engine — the safe set for a page that
   must work everywhere without negotiation. *)
val universal_codecs : unit -> string list

val render : unit -> string
