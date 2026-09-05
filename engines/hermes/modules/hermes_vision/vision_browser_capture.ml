(* Browser capture through Playwright, driven from OCaml.

   -------------------------------------------------------------------
   WHY THIS EXISTS, AND WHY IT IS NOT A .py OR .js FILE

   The X11 route failed for a reason that is not going to change: this
   Chromium refuses software GL under Xvfb ("Requested GL implementation
   (gl=none,angle=none) not found"), the viz compositor exits, and
   nothing is ever composited to the X window. `x11grab` then records a
   real display showing a blank page — a capture that looks like a
   result and contains nothing. Playwright's own recorder captures the
   page compositor directly and never touches an X server, which is why
   it works where the screen grab cannot.

   R1 forbids authoring Python or JavaScript in this repository, so the
   `venv/bin/playwright` CLI is not an option for repository tooling.
   The binding in `third_party/ocaml_playwright_55` is OCaml over the
   Playwright protocol, and Playwright itself is an external ORACLE in
   the same sense ffmpeg is: we run it, we do not author it.

   -------------------------------------------------------------------
   THE MEASUREMENT

   `requestVideoFrameCallback` is the load-bearing API. It fires once
   per COMPOSITED frame and hands over `presentedFrames` and
   `mediaTime`, which is exactly the pair the Observe stage needs:
   `presentedFrames` is a real paint count (not `readyState`, which a
   stalled player also reports happily), and `mediaTime * rate` is the
   source frame ordinal without any OCR of the burned-in label.

   That removes the weakest link in the current comparison. Reading
   "HERMES 3" out of a screenshot needs a vision model in the loop;
   mediaTime is a number the page reports about the decode it actually
   performed. *)

let evaluate_frame_probe seconds =
  Vision_js.frame_probe ~selector:"video" ~ms:(seconds * 1000) ~max_frames:240

let _superseded_hand_written_probe seconds =
  (* Collected in the PAGE, returned as data. Kept to one expression
     because every additional line here is JavaScript this repository
     would then own. *)
  Printf.sprintf
    {|() => new Promise((resolve) => {
        const v = document.querySelector('video');
        if (!v) { resolve({error: 'no video element'}); return; }
        if (!v.requestVideoFrameCallback) { resolve({error: 'no requestVideoFrameCallback'}); return; }
        const frames = [];
        const tick = (now, meta) => {
          frames.push({presented: meta.presentedFrames, mediaTime: meta.mediaTime});
          if (frames.length < 240) v.requestVideoFrameCallback(tick);
        };
        v.requestVideoFrameCallback(tick);
        setTimeout(() => resolve({
          error: null,
          width: v.videoWidth, height: v.videoHeight,
          readyState: v.readyState, paused: v.paused,
          frames: frames
        }), %d);
      })|}
    (seconds * 1000)

(* mediaTime -> source frame ordinal. The source rate is declared in the
   intent, so this is a projection of the declaration rather than a
   guess about the file. *)
let _ordinals_of ~rate media_times =
  List.map (fun t -> int_of_float (Float.round (t *. float_of_int rate))) media_times
  |> List.sort_uniq compare

let usage () =
  prerr_endline
    "usage: vision_browser_capture --url URL [--seconds N] [--rate N] [--out DIR]\n\
    \  Records the page with Playwright and reports presented frames and\n\
    \  the source ordinals they correspond to.";
  exit 2

let () =
  let url = ref "" and seconds = ref 8 and rate = ref 15 and out = ref "state/vision/capture" in
  let rec parse = function
    | "--url" :: v :: r -> url := v; parse r
    | "--seconds" :: v :: r -> seconds := int_of_string v; parse r
    | "--rate" :: v :: r -> rate := int_of_string v; parse r
    | "--out" :: v :: r -> out := v; parse r
    | [] -> ()
    | _ -> usage ()
  in
  parse (List.tl (Array.to_list Sys.argv));
  if !url = "" then usage ();
  print_endline "vision_browser_capture";
  Printf.printf "  url      %s\n  seconds  %d\n  rate     %d\n  out      %s\n%!"
    !url !seconds !rate !out;
  print_endline "  probe expression:";
  print_endline (evaluate_frame_probe !seconds);
  (* The Playwright session is NOT wired yet: third_party/ocaml_playwright_55
     is outside this dune project's scope and its Eio-based driver has not
     been built in this switch. Printing the exact probe and exiting
     non-zero is the honest state — a stub that returned a frame count
     would be the Observe hazard (a capture compared against itself)
     wearing a different hat. *)
  prerr_endline
    "\nUNAVAILABLE: the ocaml-playwright driver is not built in this switch.\n\
    \  third_party/ocaml_playwright_55 is not in the dune project scope and\n\
    \  its first-run driver download has not been performed. No capture was\n\
    \  taken and no frame count is reported.";
  exit 3
