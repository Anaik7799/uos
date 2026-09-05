module B = Journal_bundle_core.Journal_bundle

let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let contains_violation predicate = function
  | Error violations -> List.exists predicate violations
  | Ok _ -> false

let valid_json =
  {|{
    "version": 1,
    "title": "Bundle",
    "root": "/repo",
    "input": "docs/journal.md",
    "outputs": ["docs/journal.html", "/dashboard/journal.html"],
    "report": "docs/evidence/report.json",
    "dashboard": "/dashboard/bundle-status.html",
    "otel_log": "docs/evidence/otel.json",
    "prompt_ledgers": ["docs/prompts-a.jsonl", "docs/prompts-b.jsonl"],
    "text_artifacts": ["docs/spec.md"],
    "image_artifacts": [
      {"path":"docs/evidence/research.png", "source":"/capture/research.png"}
    ]
  }|}

let read_contiguous path =
  if String.equal path "/repo/docs/prompts-a.jsonl" then
    Ok "{\"ordinal\":1,\"text\":\"a\"}\n{\"ordinal\":2,\"text\":\"b\"}\n{\"ordinal\":3,\"base_ordinal\":2,\"suffix\":\" c\"}\n"
  else if String.equal path "/repo/docs/prompts-b.jsonl" then
    Ok "{\"session_id\":\"legacy\",\"ts\":100,\"text\":\"c\"}\n{\"session_id\":\"legacy\",\"ts\":101,\"text\":\"d\"}\n"
  else Error "unexpected read"

let exists_valid path =
  not (String.equal path "/repo/docs/evidence/research.png")

let decode_valid () =
  match B.decode valid_json with
  | Ok raw -> raw
  | Error message -> failwith message

let () =
  let valid =
    B.validate ~exists:exists_valid ~read:read_contiguous (decode_valid ())
  in
  require "LAW BUNDLE-SMART-CONSTRUCTOR-ACCEPTS-TOTAL-SPEC"
    (match valid with
     | Ok bundle ->
         B.outputs bundle =
           [ "/repo/docs/journal.html"; "/dashboard/journal.html" ] &&
         B.report bundle = Some "/repo/docs/evidence/report.json" &&
         B.dashboard bundle = Some "/dashboard/bundle-status.html" &&
         B.otel_log bundle = Some "/repo/docs/evidence/otel.json" &&
         List.length (B.image_artifacts bundle) = 1
     | Error _ -> false);

  let duplicate_output =
    String.concat ""
      [ "{\"version\":1,\"title\":\"B\",\"root\":\"/repo\",";
        "\"input\":\"docs/journal.md\",\"outputs\":[\"out.html\",\"out.html\"],";
        "\"prompt_ledgers\":[\"docs/prompts-a.jsonl\"],";
        "\"text_artifacts\":[],\"image_artifacts\":[]}" ]
  in
  let duplicate_result =
    match B.decode duplicate_output with
    | Error message -> failwith message
    | Ok raw -> B.validate ~exists:(fun _ -> true) ~read:read_contiguous raw
  in
  require "MUT-BUNDLE-DUPLICATE-OUTPUT"
    (contains_violation
       (function B.Duplicate_output _ -> true | _ -> false)
       duplicate_result);

  let ephemeral =
    String.concat ""
      [ "{\"version\":1,\"title\":\"B\",\"root\":\"/repo\",";
        "\"input\":\"docs/journal.md\",\"outputs\":[\"out.html\"],";
        "\"prompt_ledgers\":[\"docs/prompts-a.jsonl\"],\"text_artifacts\":[],";
        "\"image_artifacts\":[{\"path\":\"/tmp/evidence.png\"}]}" ]
  in
  let ephemeral_result =
    match B.decode ephemeral with
    | Error message -> failwith message
    | Ok raw -> B.validate ~exists:(fun _ -> true) ~read:read_contiguous raw
  in
  require "MUT-BUNDLE-EPHEMERAL-DURABLE-PATH"
    (contains_violation
       (function B.Ephemeral_durable_path _ -> true | _ -> false)
       ephemeral_result);

  let missing_result =
    B.validate ~exists:(fun path -> not (String.contains path 'e'))
      ~read:read_contiguous (decode_valid ())
  in
  require "MUT-BUNDLE-MISSING-ARTIFACT"
    (contains_violation
       (function B.Missing_artifact _ -> true | _ -> false)
       missing_result);

  let read_gap path =
    if String.equal path "/repo/docs/prompts-a.jsonl" then
      Ok "{\"ordinal\":1,\"text\":\"a\"}\n{\"ordinal\":3,\"text\":\"c\"}\n"
    else read_contiguous path
  in
  let gap_result =
    B.validate ~exists:exists_valid ~read:read_gap (decode_valid ())
  in
  require "MUT-PROMPT-ORDINAL-GAP"
    (contains_violation
       (function B.Prompt_ordinal_gap { expected = 2; actual = 3; _ } -> true | _ -> false)
       gap_result);

  let read_bad_derivation path =
    if String.equal path "/repo/docs/prompts-a.jsonl" then
      Ok "{\"ordinal\":1,\"text\":\"a\"}\n{\"ordinal\":2,\"base_ordinal\":2,\"suffix\":\"\"}\n"
    else read_contiguous path
  in
  let derivation_result =
    B.validate ~exists:exists_valid ~read:read_bad_derivation (decode_valid ())
  in
  require "MUT-PROMPT-DERIVATION-NONLOSS"
    (contains_violation
       (function B.Prompt_derivation_error _ -> true | _ -> false)
       derivation_result);

  require "LAW BUNDLE-FINGERPRINT-DETERMINISM"
    (String.equal (B.fingerprint "same") (B.fingerprint "same") &&
     not (String.equal (B.fingerprint "same") (B.fingerprint "different")));
  require "LAW BUNDLE-CACHE-FINGERPRINT-READBACK"
    (B.report_input_fingerprint
       "{\"input_fingerprint_sha256\":\"new-sha\",\"render_count\":1}" =
     Some "new-sha" &&
     B.report_input_fingerprint
       "{\"input_fingerprint_md5\":\"abc123\",\"render_count\":1}" =
     Some "abc123" &&
     B.report_input_fingerprint "{\"render_count\":1}" = None);

  let v2 audience privacy =
    Printf.sprintf
      {|{"version":2,"title":"portable","root":".","root_policy":"invocation_root","audience":"%s","input":"journal.md","outputs":[{"path":"archive.html","role":"archive"}],"prompt_ledgers":["prompt.jsonl"],"text_artifacts":[],"image_artifacts":[],"artifacts":[{"path":"journey.webm","kind":"video","mime_type":"video/webm","label":"journey","privacy":"%s"},{"path":"trace.zip","kind":"binary","mime_type":"application/zip","label":"trace","privacy":"public_data"}]}|}
      audience privacy
  in
  let validate_root root text =
    let raw = match B.decode text with Ok value -> value | Error message -> failwith message in
    B.validate_at ~invocation_root:root ~manifest_directory:"/manifest"
      ~exists:(fun _ -> true)
      ~read:(fun path ->
        if Filename.basename path = "prompt.jsonl" then
          Ok "{\"ordinal\":1,\"text\":\"operator\"}\n"
        else Ok "") raw
  in
  let first_root = match validate_root "/checkout-a" (v2 "tailnet" "personal_identifier") with
    | Ok value -> value | Error _ -> failwith "v2-a" in
  let second_root = match validate_root "/checkout-b" (v2 "tailnet" "personal_identifier") with
    | Ok value -> value | Error _ -> failwith "v2-b" in
  require "LAW MANIFEST-TWO-ROOT-PORTABILITY"
    (List.map Filename.basename (B.outputs first_root) =
     List.map Filename.basename (B.outputs second_root));
  require "LAW MANIFEST-MEDIA-TOTALITY"
    (match B.media_artifacts first_root with
     | [ video; binary ] -> video.B.kind = B.Video && binary.B.kind = B.Binary
     | _ -> false);
  let public_raw = match B.decode (v2 "public" "personal_identifier") with
    | Ok value -> value | Error message -> failwith message in
  let public_result =
    B.validate_at ~invocation_root:"/checkout" ~manifest_directory:"/manifest"
      ~exists:(fun _ -> true)
      ~read:(fun path ->
        if Filename.basename path = "prompt.jsonl" then
          Ok "{\"ordinal\":1,\"text\":\"captured user@example.com\"}\n"
        else Ok "") public_raw
  in
  require "MUT-PRIVACY-1-PUBLIC-PII-REJECTION"
    (contains_violation
       (function B.Personal_identifier_requires_private_audience _ -> true | _ -> false)
       public_result);
  let secret_result = validate_root "/checkout" (v2 "private" "secret") in
  require "LAW MANIFEST-SECRET-REJECTION"
    (contains_violation (function B.Secret_artifact_rejected _ -> true | _ -> false)
       secret_result);
  require "MUT-MANIFEST-1-ROOT-POLICY" (B.root_policy first_root = B.Invocation_root);

  require "LAW CTRL-TIME-HUMAN-FORMAT"
    (B.valid_human_timestamp "2026-08-04-0707" &&
     B.valid_human_timestamp "2024-02-29-2360" &&
     not (B.valid_human_timestamp "2026-08-04-07:07") &&
     not (B.valid_human_timestamp "2026-13-04-0707") &&
     not (B.valid_human_timestamp "2026-02-30-0707") &&
     not (B.valid_human_timestamp "2026-08-04-2407"));

  require "PROPERTY CTRL-TIME-FORMAT-ROUNDTRIP"
    (List.for_all
       (fun epoch ->
         B.valid_human_timestamp (B.format_human_timestamp epoch))
       [ 0.; 951_782_400.; 1_785_821_767.; 4_102_444_799. ])
