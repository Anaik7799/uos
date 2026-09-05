(* libav* through Ctypes: versions read from the LINKED library rather
   than from whichever ffmpeg binary is first on PATH. Total; no
   subprocess; never raises. *)
val avformat : unit -> string
val avcodec : unit -> string
val avutil : unit -> string
val linked_report : unit -> string

(* Open and immediately close a media file through libav. Returns
   libav's raw code: negative is not success, and two negatives are not
   failures (see Vision_libav_ontology.classify). *)
val open_close : string -> int

(* Resident set size in kB. The OCaml GC cannot see a libav allocation,
   so this is the only place a leaked AVFormatContext appears. *)
val rss_kb : unit -> int option

(* THE LEAK PROBE. One open/close proves nothing — a context that is
   never freed still opens fine. Repeating it and watching RSS is what
   makes the Open_input hazard observable at all. Returns RSS before and
   after, or an error when the process cannot be measured. *)
val open_close_leaks : ?iterations:int -> string -> (int * int, string) result

(* Is the shared library present and loadable? Everything else answers
   a sentinel when it is not, so a missing libav is Unknown rather than
   a crash. *)
val available : unit -> bool
