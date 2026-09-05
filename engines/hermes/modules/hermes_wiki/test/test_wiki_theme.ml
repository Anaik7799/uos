(* HW.7.1.1 — design tokens to generated CSS, across the full functional
   envelope. Each law names the mutant that kills it:

     N1 annotation      M1  emit the declaration without its token path
     N2 purity          M2  drop the sort, let input order leak
     N3 banner          M3  omit the GENERATED banner
     S1 unknown token   M4  skip an unresolved binding instead of erroring
     S2 mode names      M5  stop requiring modes to bind the same names
     A1 unsafe value    M6  emit a value containing CSS syntax
     A2 duplicate       M7  let the first definition silently win
     C  consistency     M8  emit despite check reporting an error *)

let passed = ref 0
let failed = ref 0

let check_ name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

open Wiki_theme

let tokens =
  [ { path = "color/neutral/000"; value = "#ffffff" };
    { path = "color/neutral/900"; value = "#1a1a1a" };
    { path = "color/accent/500"; value = "#2b6cb0" } ]

let light =
  { mode = "light";
    bindings = [ ("--bg", "color/neutral/000"); ("--fg", "color/neutral/900");
                 ("--accent", "color/accent/500") ] }

let dark =
  { mode = "dark";
    bindings = [ ("--bg", "color/neutral/900"); ("--fg", "color/neutral/000");
                 ("--accent", "color/accent/500") ] }

let ok r = match r with Ok s -> s | Error _ -> ""

(* ------------------------------------------------------------ nominal *)

let () =
  check_ "N1 EVERY declaration is annotated with the token path it came from"
    (fun () ->
      let s = ok (css ~tokens ~themes:[ light ]) in
      contains s "--bg: #ffffff; /* color/neutral/000 */"
      && contains s "--fg: #1a1a1a; /* color/neutral/900 */"
      && contains s "--accent: #2b6cb0; /* color/accent/500 */");
  check_ "N2 PURE: token and theme order cannot change one byte of output" (fun () ->
      let a = css ~tokens ~themes:[ light; dark ] in
      let b = css ~tokens:(List.rev tokens) ~themes:[ dark; light ] in
      a = b && a <> Ok "");
  check_ "N3 the output opens with a GENERATED banner (the hand-edit detector)"
    (fun () ->
      let s = ok (css ~tokens ~themes:[ light ]) in
      String.length s > String.length banner
      && String.sub s 0 (String.length banner) = banner
      && contains banner "do not hand-edit");
  check_ "N4 light is :root; another mode is selected by data-theme" (fun () ->
      let s = ok (css ~tokens ~themes:[ light; dark ]) in
      contains s "\n:root {\n" && contains s ":root[data-theme=\"dark\"] {");
  check_ "N5 REGENERATION IS THE DETECTOR: same input, byte-identical output"
    (fun () ->
      css ~tokens ~themes:[ light; dark ] = css ~tokens ~themes:[ light; dark ])

(* -------------------------------------------------------------- stuck *)

let () =
  check_ "S1 a binding to an UNKNOWN token is a named error, never a dropped line"
    (fun () ->
      let bad = { mode = "light"; bindings = [ ("--bg", "color/ghost/000") ] } in
      match css ~tokens ~themes:[ bad ] with
      | Error [ Unknown_token { mode = "light"; variable = "--bg"; path = "color/ghost/000" } ] ->
          contains (describe (Unknown_token { mode = "l"; variable = "v"; path = "p" })) "inherit"
      | _ -> false);
  check_ "S2 every mode must bind the SAME names (HW.7.1.2's precondition)" (fun () ->
      let partial = { mode = "dark"; bindings = [ ("--bg", "color/neutral/900") ] } in
      match css ~tokens ~themes:[ light; partial ] with
      | Error errs ->
          List.exists
            (function Mode_name_mismatch { mode = "dark"; missing } ->
                        List.mem "--fg" missing && List.mem "--accent" missing
                    | _ -> false)
            errs
      | Ok _ -> false);
  check_ "S3 no tokens and no themes yields a banner-only stylesheet, not an error"
    (fun () ->
      match css ~tokens:[] ~themes:[] with Ok s -> s = banner | Error _ -> false)

(* ------------------------------------------------------------ anomaly *)

let () =
  check_ "A1 a token value carrying CSS syntax is REFUSED, not escaped" (fun () ->
      List.for_all
        (fun v ->
          let t = [ { path = "color/x"; value = v } ] in
          let th = [ { mode = "light"; bindings = [ ("--x", "color/x") ] } ] in
          match css ~tokens:t ~themes:th with
          | Error errs -> List.exists (function Unsafe_value _ -> true | _ -> false) errs
          | Ok _ -> false)
        [ "#fff; } :root { --evil: 1"; "red}"; "a<b"; "/* comment"; "a\nb" ]);
  check_ "A1b a legitimate value with punctuation is NOT refused" (fun () ->
      let t = [ { path = "font/body"; value = "-apple-system, 'Segoe UI', sans-serif" } ] in
      let th = [ { mode = "light"; bindings = [ ("--font", "font/body") ] } ] in
      match css ~tokens:t ~themes:th with Ok _ -> true | Error _ -> false);
  check_ "A2 a DUPLICATE token path is an error — which value wins would be luck"
    (fun () ->
      let t = { path = "color/x"; value = "#111" } in
      match css ~tokens:[ t; { t with value = "#222" } ] ~themes:[] with
      | Error errs -> List.exists (function Duplicate_token _ -> true | _ -> false) errs
      | Ok _ -> false);
  check_ "A3 an empty variable name or path is still handled totally (no raise)"
    (fun () ->
      let th = [ { mode = ""; bindings = [ ("", "") ] } ] in
      match css ~tokens:[] ~themes:th with _ -> true)

(* --------------------------------------------------- the consistency *)

let () =
  check_ "C check and css AGREE: css succeeds exactly when check is empty" (fun () ->
      let cases =
        [ (tokens, [ light ]); (tokens, [ light; dark ]); ([], []);
          (tokens, [ { mode = "x"; bindings = [ ("--a", "nope") ] } ]);
          ([ { path = "p"; value = "a;b" } ], [ { mode = "x"; bindings = [ ("--a", "p") ] } ]) ]
      in
      List.for_all
        (fun (tokens, themes) ->
          let empty = check ~tokens ~themes = [] in
          match css ~tokens ~themes with Ok _ -> empty | Error _ -> not empty)
        cases);
  check_ "C2 every error describes the artifact AND why it matters" (fun () ->
      List.for_all
        (fun e -> String.length (describe e) > 40)
        [ Unknown_token { mode = "m"; variable = "v"; path = "p" };
          Unsafe_value { path = "p"; value = "v" };
          Mode_name_mismatch { mode = "m"; missing = [ "a" ] };
          Duplicate_token { path = "p" } ])

let () =
  Printf.printf "wiki_theme: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_theme" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_theme ]);
  exit (Wiki_suite_telemetry.exit_code self)
