(* Fractal ontology of libav* used IN-PROCESS through Ctypes.

   This is the odd one out, and the reason is not the codec work. Every
   other tool in this set runs as a subprocess: when ffmpeg, GStreamer,
   VLC, OBS or JMeter goes wrong, it dies in its own address space and we
   read an exit code. libav runs INSIDE the harness. When it goes wrong
   it takes the harness with it, and it does not raise — it segfaults.

   The repository already treats a signal or exit 139 as a blocking
   crash observation whose bytes and coordinate must be preserved, and
   which later passing runs do not resolve. Binding libav in-process is
   the most likely way this harness will ever produce one. So this
   ontology is about MEMORY AND LIFETIME, not about pixels.

   -------------------------------------------------------------------
   ZERO-COPY IS THE POINT AND ALSO THE DANGER

   The reason to bind libav rather than shell out is zero-copy access to
   frames. But an OCaml Bigarray built over an AVFrame's buffer ALIASES
   memory that libav owns and will free. Once `av_frame_unref` runs, that
   Bigarray is a live OCaml value pointing at freed memory. Reading it is
   undefined behaviour, and the failure is a segfault in a later,
   unrelated part of the program — the hardest class of bug this
   repository can acquire.

   Every hazard below is of that character: correct-looking code, no
   exception, and a fault that appears somewhere else. *)

(* -------------------------------------------------------- the surface *)

type call =
  | Version_query        (* avformat_version etc: pure, no allocation *)
  | Open_input           (* avformat_open_input: allocates a context we must close *)
  | Find_stream_info     (* may read and allocate *)
  | Send_packet          (* avcodec_send_packet *)
  | Receive_frame        (* avcodec_receive_frame: the EAGAIN protocol *)
  | Frame_buffer_access  (* the zero-copy window onto pixel data *)
  | Unref_frame          (* av_frame_unref: the moment aliases become invalid *)
  | Close_input          (* avformat_close_input *)

val calls : call list
val name : call -> string
val level : call -> Fractal_diagnostic.fractal_level
val origin : call -> Fractal_diagnostic.origin
val law : call -> string
val hazard : call -> string

(* Does this call allocate something the caller must later release? A
   binding that gets this wrong leaks memory the OCaml GC cannot see, so
   the process grows without any OCaml heap growth to explain it. *)
val allocates : call -> bool

(* Must the OCaml runtime lock be released around this call? A blocking
   libav call made while holding it stops EVERY domain, so a decode of a
   slow network input freezes the whole harness — including the probes
   that would have reported it. *)
val releases_runtime_lock : call -> bool

(* Does this call invalidate previously handed-out zero-copy views? The
   answer is the safety obligation of the whole binding. *)
val invalidates_aliases : call -> bool

(* --------------------------------------------------- the return codes *)

(* libav returns a negative int for everything that is not success, and
   two of those are NOT failures. Treating "negative means error" is the
   classic libav bug: it aborts a working decode at the first EAGAIN. *)
type code = Ok_zero | Again | End_of_file | Real_error of int

val classify : int -> code
val code_name : code -> string

(* Is this a reason to stop? [Again] never is — it means "feed more
   input". [End_of_file] ends the loop normally. Only [Real_error] is a
   failure. *)
val is_failure : code -> bool

(* Should the caller supply more input and retry? *)
val wants_more_input : code -> bool

(* ------------------------------------------------------- the lifetime *)

(* A zero-copy view's state. The point of modelling it is that [Expired]
   is reachable and readable in C, so it must be unrepresentable in the
   OCaml API that wraps it. *)
type view = Live | Expired

(* May the caller read the pixels? Only when the view is live. The
   binding's obligation is to make an expired view impossible to hold,
   not merely to document that reading one is wrong. *)
val readable : view -> bool

(* The state after the given call. [Unref_frame] and [Close_input] expire
   every outstanding view. *)
val after : call -> view -> view

val render : unit -> string
