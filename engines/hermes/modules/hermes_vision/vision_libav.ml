(* libav* bound through Ctypes — no shell, no subprocess.

   The point is not speed. It is that a version read from the LINKED
   library is a fact about the code that will actually decode frames,
   whereas `ffmpeg -version` is a fact about whatever binary happened to
   be first on PATH. Those can differ, and when they do, every
   CLI-derived capability claim is about the wrong library.

   Headers are NOT at /usr/include/libavcodec on Debian multiarch; they
   are under /usr/include/x86_64-linux-gnu. Nothing here hardcodes that:
   dune takes the flags from pkg-config. *)

open Ctypes
open Foreign

(* Bound by explicit dlopen rather than link flags. Two reasons: dune
   c_library_flags on a library do not propagate to every consumer, so a
   test executable failed at load with an undefined symbol; and an
   ABSENT library should be a catchable condition the probes report as
   Unknown, not a link error nobody can handle. *)
let handle =
  lazy
    (let rec first = function
       | [] -> None
       | soname :: rest -> (
           match Dl.dlopen ~filename:soname ~flags:[ Dl.RTLD_NOW ] with
           | h -> Some h
           | exception _ -> first rest)
     in
     first
       [ "libavformat.so.61"; "libavformat.so.60"; "libavformat.so.59"; "libavformat.so" ])

let available () = Lazy.force handle <> None

let sym name =
  match Lazy.force handle with
  | None -> None
  | Some from -> (
      match foreign ~from name (void @-> returning uint32_t) with
      | f -> Some f
      | exception _ -> None)

let avformat_version () = match sym "avformat_version" with Some f -> f () | None -> Unsigned.UInt32.zero
let avcodec_version () = match sym "avcodec_version" with Some f -> f () | None -> Unsigned.UInt32.zero
let avutil_version () = match sym "avutil_version" with Some f -> f () | None -> Unsigned.UInt32.zero

(* libav packs version as (major << 16 | minor << 8 | micro) *)
let decode v =
  let n = Unsigned.UInt32.to_int v in
  ((n lsr 16) land 0xff, (n lsr 8) land 0xff, n land 0xff)

let version_string f =
  let ma, mi, mc = decode (f ()) in
  Printf.sprintf "%d.%d.%d" ma mi mc

let avformat () = version_string avformat_version
let avcodec () = version_string avcodec_version
let avutil () = version_string avutil_version

(* Linked-vs-CLI agreement. A DISAGREEMENT is a real finding, not a
   nuisance: it means the pipeline's shell probes and its in-process
   decoding are talking about two different libraries. *)
let linked_report () =
  Printf.sprintf "libavformat %s, libavcodec %s, libavutil %s" (avformat ()) (avcodec ())
    (avutil ())

(* ------------------------------------------------- lifetime probes

   The libav hazards are the only ones in this repository that cannot be
   parsed from a report or watched from outside, because libav runs
   INSIDE us. A leaked context is invisible to the OCaml GC; a
   use-after-free surfaces as a segfault somewhere unrelated. So these
   probes actually open and close real media and watch the process. *)

let open_input_sym =
  lazy
    (match Lazy.force handle with
     | None -> None
     | Some from -> (
         match
           foreign ~from "avformat_open_input"
             (ptr (ptr void) @-> string @-> ptr void @-> ptr void @-> returning int)
         with
         | f -> Some f
         | exception _ -> None))

let close_input_sym =
  lazy
    (match Lazy.force handle with
     | None -> None
     | Some from -> (
         match foreign ~from "avformat_close_input" (ptr (ptr void) @-> returning void) with
         | f -> Some f
         | exception _ -> None))

(* Resident set size in kB, from /proc/self/statm. The OCaml GC cannot
   see a libav allocation, so heap words would report nothing; RSS is
   the only place a leaked AVFormatContext shows up. *)
let rss_kb () =
  try
    let ic = open_in "/proc/self/statm" in
    Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
        match String.split_on_char ' ' (input_line ic) with
        | _ :: resident :: _ -> int_of_string_opt resident |> Option.map (fun p -> p * 4)
        | _ -> None)
  with _ -> None

let open_close path =
  match (Lazy.force open_input_sym, Lazy.force close_input_sym) with
  (* a very negative code no libav AVERROR uses, so an absent library is
     never mistaken for EAGAIN or EOF *)
  | None, _ | _, None -> min_int
  | Some op, Some cl ->
      let ctx = allocate (ptr void) null in
      let code = op ctx path null null in
      if code >= 0 then cl ctx;
      code

(* THE LEAK PROBE. One open/close proves nothing — a context that is
   never freed still opens fine. Repeating it and watching RSS is what
   makes the Open_input hazard observable at all. *)
let open_close_leaks ?(iterations = 60) path =
  match rss_kb () with
  | None -> Error "cannot read /proc/self/statm"
  | Some _ ->
      for _ = 1 to 5 do ignore (open_close path) done;  (* settle allocator *)
      (match rss_kb () with
       | None -> Error "cannot read /proc/self/statm"
       | Some before ->
           for _ = 1 to iterations do ignore (open_close path) done;
           (match rss_kb () with
            | None -> Error "cannot read /proc/self/statm"
            | Some after -> Ok (before, after)))
