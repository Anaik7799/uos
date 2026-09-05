(* KM journal integrity laws. Mutants (killers named):
     J-M1 append check accepts any superset   (killed: mid-edit leg)
     J-M2 Secret admitted                     (killed: rejection law) *)
let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed; print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let () =
  check "R16 name law: YYYYMMDD-HHSS-<slug>.md accepted, everything else refused" (fun () ->
      Journal.valid_name "20260812-1830-features-audit.md"
      && (not (Journal.valid_name "2026-08-12-features-audit.md"))
      && (not (Journal.valid_name "20260812-183-features-audit.md"))
      && (not (Journal.valid_name "20261312-1830-features-audit.md"))
      && (not (Journal.valid_name "20260230-1830-features-audit.md"))
      && (not (Journal.valid_name "20260812-2430-features-audit.md"))
      && (not (Journal.valid_name "20260812-1860-features-audit.md"))
      && (not (Journal.valid_name "notes.md"))
      && (not (Journal.valid_name "20260812-1830-.md"))
      && (not (Journal.valid_name "20260812-1830-CAPS.md"))
      && not (Journal.valid_name "20260812-1830-ok.txt"));
  check "privacy parses the bundle trio and nothing else" (fun () ->
      Journal.privacy_of_string "public_data" = Ok Journal.Public_data
      && Journal.privacy_of_string "personal_identifier" = Ok Journal.Personal_identifier
      && Journal.privacy_of_string "secret" = Ok Journal.Secret
      && match Journal.privacy_of_string "whatever" with Error _ -> true | Ok _ -> false);
  check "THE REJECTION LAW: Secret is never admissible; the other two are" (fun () ->
      (not (Journal.admissible Journal.Secret))
      && Journal.admissible Journal.Public_data
      && Journal.admissible Journal.Personal_identifier);
  check "append-only: appending is honest; rewriting history is named" (fun () ->
      Journal.append_violation ~old_content:"a\nb\n" ~new_content:"a\nb\nc\n" = None
      && Journal.append_violation ~old_content:"a\nb\n" ~new_content:"a\nb\n" = None
      && Journal.append_violation ~old_content:"a\nb\n" ~new_content:"a\nX\nc\n" <> None);
  check "append-only: a SHRUNK journal is a violation too" (fun () ->
      Journal.append_violation ~old_content:"a\nb\n" ~new_content:"a\n" <> None)

let () =
  Printf.printf "km_journal: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_km_journal" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
