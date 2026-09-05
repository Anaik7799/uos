(* YOLO object detection: the semantic check PSNR cannot make.

   -------------------------------------------------------------------
   A DIFFERENT QUESTION FROM THE ONE ALREADY ANSWERED

   Vision_compare asks "is this the same video" and answers it with
   PSNR. That question is answerable only because the source carries a
   burned-in ordinal and the capture is nearly lossless. It fails on
   exactly the cases a real deployment cares about: a stream re-encoded
   at a lower bitrate is the SAME CONTENT and scores terribly, while two
   different scenes at the same bitrate can score similarly.

   Detection asks "is the expected content present", which survives
   re-encoding and distinguishes content rather than pixels. The two are
   complementary and neither replaces the other, which is why this is a
   separate stage predicate rather than a new PSNR threshold.

   -------------------------------------------------------------------
   ULTRALYTICS IS AN ORACLE, NOT AN AUTHORED DEPENDENCY

   It is Python, and R1 forbids authoring Python in this repository. So
   it is invoked the way ffmpeg, VLC, z3 and stanc are invoked: as a
   binary we RUN and never write. Its absence is [Unavailable] — an
   absent detector proves nothing about the stream, and under R5 may
   block credit but never deny it.

   The FFI request is answered honestly below: there is no C ABI to bind
   here. See [integration] for what binding actually means for a Python
   package and why the CLI boundary is the sound one. *)

(* ------------------------------------------------------ ontology *)

type capability =
  | Detect          (* objects present in one image *)
  | Track           (* the same object across frames *)
  | Segment         (* per-pixel masks *)
  | Classify        (* whole-image label *)

val capabilities : capability list
val name : capability -> string
val level : capability -> Fractal_diagnostic.fractal_level
val origin : capability -> Fractal_diagnostic.origin
val law : capability -> string
val hazard : capability -> string
val serves : capability -> Vision_ontology.stage

(* ------------------------------------------------------- algebra *)

(* A detection set, compared as a MULTISET of labels rather than boxes:
   two captures of one scene rarely agree on coordinates and always
   agree on what is present. *)
type detection = { label : string; confidence : float }
type detections = detection list

(* Labels present above [floor], as a sorted multiset. *)
val labels : ?floor:float -> detections -> string list

(* Jaccard agreement over label multisets, in [0,1]. Total: two empty
   sets agree completely, which is why [agrees] requires evidence as
   well as agreement. *)
val agreement : ?floor:float -> detections -> detections -> float

(* THE LAW THAT MATTERS. Two empty detection sets are perfectly similar
   and prove nothing — a detector that found nothing in either image
   agrees with itself. [agrees] therefore requires a non-empty
   reference: no evidence is not agreement. *)
val agrees : ?floor:float -> ?threshold:float -> detections -> detections -> bool

(* ---------------------------------------------- declarative intent *)

type intent = {
  image : string;
  weights : string;        (* e.g. yolo11n.pt *)
  confidence : float;
  capability : capability;
}

val validate : intent -> (intent, string) result

(* An argument VECTOR for the yolo CLI. No shell, so no field can be
   read as syntax — the same discipline as Vision_intent. *)
val argv : intent -> string list

(* ------------------------------------------------------- oracle *)

val available : unit -> bool

(* Run the detector. [Unavailable] when ultralytics is absent, when the
   weights cannot be fetched, or when the output cannot be parsed —
   never an empty detection set standing in for a failed run, because
   "found nothing" and "could not look" are the two answers this
   repository keeps insisting are different. *)
val detect : intent -> (detections, string) result

(* Compare source and capture semantically, as a stage observation. *)
val observe :
  reference:string -> candidate:string -> weights:string -> Vision_controller.observation

(* Why the boundary is the CLI and not a C ABI. Stated in the interface
   because a reader who was told "wire it via FFI" deserves the reason
   in the same place as the code. *)
val integration : string
