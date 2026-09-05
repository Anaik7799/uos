(* The ffmpeg controller: declarative intent in, real process out, and a
   probe for every stage of the ontology.

   -------------------------------------------------------------------
   WHAT THIS REPLACES

   The previous controller was thirteen lines. It compiled an intent to a
   shell STRING, ran `Unix.system (cmd ^ " > /dev/null 2>&1 &")`, and
   mapped WEXITED 0 to Ok (). Because the command was backgrounded by the
   shell, the exit code it read was the SHELL's — which is zero whenever
   the shell managed to fork, regardless of whether ffmpeg then died
   instantly. It reported success for a pipeline that never produced a
   frame, and it discarded the output that would have said why.

   Here the process is started with execvp and no shell, its pid is kept,
   its output is captured to a log, and liveness is a QUESTION ASKED OF
   THE ARTEFACTS rather than of the spawn.

   -------------------------------------------------------------------
   THREE VERDICTS, AND THE THIRD IS THE POINT

   A probe answers Live, Absent, or Unknown. [Unknown] is what a probe
   returns when it could not look — the directory is not there yet, the
   port refused the connection, the oracle is not installed. It is never
   folded into Absent, because "I could not measure" and "I measured, and
   there is nothing" demand opposite responses, and never into Live. *)

type verdict =
  | Live of string      (* measured, and the stage's law holds *)
  | Absent of string    (* measured, and the law does not hold *)
  | Unknown of string   (* could not measure; nothing is proved either way *)

type observation = {
  stage : Vision_ontology.stage;
  verdict : verdict;
  level : Fractal_diagnostic.fractal_level;
  origin : Fractal_diagnostic.origin;
  detail : string;
  elapsed_ms : float;
}

val verdict_name : verdict -> string
val is_live : observation -> bool

(* A running pipeline. Holding one is the only way to stop it, so a
   caller cannot lose track of a process it started. *)
type handle

val pid : handle -> int
val log_path : handle -> string
val intent_of : handle -> Vision_intent.intent

(* Start ffmpeg with execvp — NO SHELL, so no field of the intent can be
   read as syntax. The intent is validated first; an invalid one never
   reaches a process. [Error] when ffmpeg is not on PATH or the sink
   directory cannot be created. *)
val start : Vision_intent.intent -> (handle, string) result

(* Has the process not yet exited? A false answer here is not itself a
   failure verdict — the stage probes decide that — but a process that
   died is why they will. *)
val running : handle -> bool

(* SIGTERM, then SIGKILL if it does not go. Idempotent: stopping a
   stopped handle is not an error, because the alternative is callers
   that skip cleanup to avoid one. *)
val stop : handle -> unit

(* ------------------------------------------------------------ probes

   Each probe is written against the ONE-LINE LAW its stage declares in
   Vision_ontology, and each is a pure function of something it reads
   from the world, so a test can drive it with a fabricated world. *)

(* Source and Encode are read from the process's own log and liveness:
   ffmpeg reports decode and encode failure there, and silence plus a
   live pid is the only evidence available before segments appear. *)
val probe_source : handle -> observation
val probe_encode : handle -> observation

(* Package reads the playlist and checks that every segment it names
   EXISTS AND IS NON-EMPTY. A playlist naming deleted segments is the
   stage's declared hazard, so the probe must open the files rather than
   trust the listing. *)
val probe_package : dir:string -> observation

(* Serve fetches the playlist over HTTP and then fetches the first
   segment it names. Fetching only the playlist is what lets a stalled
   player look like a working server. *)
val probe_serve : host:string -> port:int -> path:string -> observation

(* Play and Observe are answered by the BROWSER ORACLE, which lives
   outside this process. These take the oracle's report as data so the
   verdict is computed by the same rules as the others, and a missing
   oracle becomes Unknown rather than a silent pass. *)
val probe_play : frames_painted:int option -> observation
val probe_observe :
  source_ordinals:int list -> captured_ordinals:int list -> observation

(* The whole battery in ontology order, plus the coverage those
   observations establish. The segment is derived from which stages came
   back Live, so a stage that was Unknown cannot contribute coverage. *)
val probe_all :
  handle -> dir:string -> host:string -> port:int -> path:string ->
  frames_painted:int option -> source_ordinals:int list -> captured_ordinals:int list ->
  observation list * (Vision_algebra.segment, string) result

val render : observation list -> string

(* Minimal HTTP GET over Unix sockets, exposed so a health gate can ask
   an instance to identify itself. Never raises. *)
val http_get : host:string -> port:int -> path:string -> (string * string, string) result

(* Is this pid one of ours? A pid may be REUSED, and signalling one we
   no longer own kills an unrelated process. Exposed because the STPA
   names it as a safety constraint, so it needs a test. *)
val owns_pid : int -> bool

(* The pid holding the output directory, if a live one does. One
   pipeline owns a directory at a time: two encoders writing one
   playlist corrupts the stream. A lock whose pid is dead or not ours is
   stale and may be taken. *)
val lock_holder : string -> int option
