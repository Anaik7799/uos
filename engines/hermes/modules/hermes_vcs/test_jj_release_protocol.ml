let failures = ref []
let check name condition = if not condition then failures := name :: !failures

let digest text =
  match Jj_release_protocol.Digest.make text with
  | Ok value -> value
  | Error _ -> failwith "digest fixture refused"

let hex character = String.make 64 character

let () =
  let open Jj_release_protocol in
  check "R1 release digests require canonical lowercase SHA-256"
    (Result.is_ok (Digest.make (hex 'a'))
     && Result.is_error (Digest.make (String.uppercase_ascii (hex 'a')))
     && Result.is_error (Digest.make "abc"));
  let release_id =
    match Jj_id.Request.make "release-observation-1" with
    | Ok value -> value
    | Error _ -> failwith "request fixture refused"
  in
  let tag = digest (hex '1') and commit = digest (hex '2') in
  let tree = digest (hex '3') and archive = digest (hex '4') in
  let documentation = digest (hex '5') and executable = digest (hex '6') in
  let config = digest (hex '7') in
  let pinned = pin ~release_id ~tag ~commit ~tree ~archive ~documentation
      ~executable ~config in
  check "R2 pin is canonical and binds all declared identities"
    (String.length (pin_digest pinned) = 64);
  let observed = observe ~pin:pinned ~tag ~commit ~tree ~archive ~documentation
      ~executable ~config in
  check "R3 an exact observation creates a non-authorizing bundle"
    (match observed with
     | Ok bundle -> String.length (bundle_digest bundle) = 64
     | Error _ -> false);
  let mismatch = observe ~pin:pinned ~tag ~commit ~tree
      ~archive:(digest (hex '8')) ~documentation ~executable ~config in
  check "R4 a mismatched artifact refuses with its typed field"
    (mismatch = Error [ Archive_mismatch ]);
  let multiple = observe ~pin:pinned ~tag:(digest (hex '8')) ~commit ~tree
      ~archive ~documentation ~executable:(digest (hex '9')) ~config in
  check "R5 mismatch order is deterministic"
    (multiple = Error [ Tag_mismatch; Executable_mismatch ]);
  check "R6 release protocol authority digest is SHA-256 shaped"
    (String.length source_digest = 64);
  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 6 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_release_protocol"
    ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_jj_protocol ]);
  exit (Suite_telemetry.exit_code self)
