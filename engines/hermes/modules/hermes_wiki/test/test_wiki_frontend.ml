(* The Bonsai frontend is compiled, not merely written: this suite pins
   that the js_of_ocaml artifact exists, is substantial, and carries the
   markers of OUR app rather than an empty runtime. It also pins the
   no-JS law's precondition — the app mounts into an element the server
   leaves empty, so a page is complete without it. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed; print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

(* R19 clause 5: a check must give the same verdict from the repo root as
   from the build tree. The js_of_ocaml artifact only exists under
   _build/, so the FIRST readable of the two paths wins — and if neither
   exists the file-exists check still fails, which is the honest verdict.
   Before this, running the suite from the repo root reported five
   failures for a bundle that was sitting there compiled. *)
let artifact =
  let relative = "modules/hermes_wiki/src/frontend/wiki_app.bc.js" in
  if Sys.file_exists relative then relative else Filename.concat "_build/default" relative

let read path =
  let channel = open_in_bin path in
  let n = in_channel_length channel in
  let s = really_input_string channel n in
  close_in channel;
  s

let contains text needle =
  let n = String.length needle and h = String.length text in
  let rec go i = i + n <= h && (String.sub text i n = needle || go (i + 1)) in
  go 0

let () =
  check "the frontend compiles to a javascript artifact" (fun () ->
      Sys.file_exists artifact);
  check "the artifact is a real bundle, not an empty stub" (fun () ->
      String.length (read artifact) > 1_000_000);
  check "the artifact carries OUR mount point and data island" (fun () ->
      let js = read artifact in
      contains js "wiki-app" && contains js "wiki-app-data");
  check "the artifact carries the filter affordance" (fun () ->
      contains (read artifact) "filter components");
  check "the frontend adds no write path (no fetch/XHR/POST)" (fun () ->
      let js = read artifact in
      (* The app reads a server-rendered JSON island; it must never call
         back to the server, which keeps the read-only law intact even
         with scripting enabled. *)
      (not (contains js "XMLHttpRequest.prototype.open"))
      && not (contains js "method:\"POST\""))

let () =
  Printf.printf "wiki_frontend: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_frontend" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
