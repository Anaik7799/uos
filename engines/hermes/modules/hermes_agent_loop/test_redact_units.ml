(* Hand-written invariants over the redaction units -- the backstop the
   parity fixture cannot be. Every law carries a negative control
   (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let redact = Redact_units.redact_sensitive_text ~redact_url_credentials:true

let contains needle haystack =
  let n = String.length needle in
  let h = String.length haystack in
  let rec at i = i + n <= h && (String.sub haystack i n = needle || at (i + 1)) in
  at 0

let () =
  (* ANCHOR: the head-6/tail-4 mask with the 18-char floor. *)
  check
    (Redact_units.mask_token "sk-proj-A1b2C3d4E5f6G7h8" = "sk-pro...G7h8")
    "ANCHOR a 24-char token masks to head-6/tail-4";
  check (Redact_units.mask_token "sk-abcdefghij" = "***")
    "ANCHOR a sub-18-char token is fully floored";
  check (Redact_units.mask_token "" = "***") "ANCHOR the empty token is three stars";

  (* NO LEAK: after redaction, no case's secret body survives. *)
  let secrets_gone input secret label =
    check (not (contains secret (redact input))) label
  in
  secrets_gone "key sk-proj-A1b2C3d4E5f6G7h8 used" "A1b2C3d4E5f6"
    "LEAK the OpenAI key body is gone";
  secrets_gone "postgresql://svc:hunter2pass@db/x" "hunter2pass"
    "LEAK the DB password is gone";
  secrets_gone "https://alice:s3cret@example.com/x" "s3cret"
    "LEAK the userinfo password is gone";
  secrets_gone "https://x/cb?token=deadbeefcafe" "deadbeefcafe"
    "LEAK the sensitive query value is gone";
  check (contains "no secrets" (redact "no secrets in this line"))
    "CONTROL clean prose passes through";

  (* IDENTITY on clean text: the redactor never rewrites what it should not. *)
  check
    (redact "the quick brown fox reads a file" = "the quick brown fox reads a file")
    "LAW clean text is byte-identical";

  (* IDEMPOTENCE holds for the token/URL shapes: a masked token's head is
     too short to rematch its pattern, a starred password stays starred. *)
  let stable_cases =
    [ "key sk-proj-A1b2C3d4E5f6G7h8 used";
      "postgresql://svc:hunter2pass@db.internal:5432/app";
      "https://ghtokenvalue123@github.com/org/repo.git";
      "https://api.example.com/cb?code=abc123&state=xyz" ]
  in
  check
    (List.for_all (fun input -> redact (redact input) = redact input) stable_cases)
    "LAW redaction is idempotent on token and URL shapes";
  check
    (List.exists (fun input -> redact input <> input) stable_cases)
    "CONTROL the cases actually change (idempotence is not vacuous)";
  (* ...but NOT for header shapes, by the frozen unit's own arithmetic: the
     header pass masks WHATEVER value follows the scheme, so a re-pass sees
     the 13-char mask, floors it to three stars, and only THEN reaches a
     fixed point. Pinned as documented behaviour, not patched away -- the
     frozen does exactly the same. *)
  let header = "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln x" in
  let once = redact header in
  let twice = redact once in
  check (twice <> once && contains "Bearer ***" twice)
    "LAW a re-redacted header floors its own mask to three stars";
  check (redact twice = twice) "LAW the header shape stabilizes on the second pass";

  (* STRUCTURE PRESERVED: the non-secret surroundings survive. *)
  let redacted = redact "https://api.example.com/cb?code=abc123&state=xyz&api-key=zzz#frag" in
  check
    (contains "state=xyz" redacted && contains "#frag" redacted
    && contains "api.example.com" redacted)
    "LAW non-sensitive params, host and fragment are preserved";
  check (contains "code=***" redacted && contains "api-key=***" redacted)
    "LAW sensitive params are starred with their keys intact";

  (* FLAG SEMANTICS: url-credential redaction is opt-in. *)
  let off =
    Redact_units.redact_sensitive_text ~redact_url_credentials:false
      "https://api.example.com/cb?code=abc123&state=xyz"
  in
  check (contains "code=abc123" off) "LAW query params pass through when the flag is off";

  (* ORDER: a JWT inside a Bearer header is masked once by the header pass;
     the masked head is too short for the JWT pass to rematch. *)
  let bearer = redact "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln x" in
  check
    (contains "Bearer eyJhbG" bearer && not (contains "eyJhbGciOiJIUzI1NiJ9" bearer))
    "LAW the header pass masks the JWT exactly once";

  Printf.printf "redact units: %d passed, %d failed\n" !passed
    (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_redact_units" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_redact_units ]);
  exit (Suite_telemetry.exit_code self)
