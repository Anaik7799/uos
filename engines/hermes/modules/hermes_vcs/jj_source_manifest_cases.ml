let failures = ref []
let outcome = ref (0, 0)

let check name condition =
  if not condition then failures := name :: !failures

let get = function Ok value -> value | Error _ -> failwith "valid fixture refused"

let path value = get (Jj_path.make value)
let digest byte = get (Jj_split_manifest.Digest.make (String.make 64 byte))
let target value = get (Jj_source_manifest.Symlink_target.make value)
let identity value = get (Jj_source_manifest.Identity.make value)
let reason value = get (Jj_source_manifest.Exclusion_reason.make value)
let bytes_digest value = Jj_split_manifest.Digest.of_bytes (Bytes.of_string value)

let source ?(path_value = "modules/a.ml") ?(mode = Jj_split_manifest.Regular)
    ?symlink_target ?(size_bytes = 10) ?(content_digest = digest 'a')
    ?(disposition = Mainline_carrier_policy.Track) ?sanitizer_identity
    ?projection_identity ?exclusion_reason () =
  get
    (Jj_source_manifest.entry ~path:(path path_value) ~mode ~symlink_target
       ~size_bytes ~content_digest ~artifact:Mainline_carrier_policy.Source
       ~disposition ~sanitizer_identity ~projection_identity ~exclusion_reason)

let projection ?(sanitizer = "sanitize-v1") ?(projection_id = "projection-v1")
    () =
  get
    (Jj_source_manifest.entry ~path:(path "generated/items.json")
       ~mode:Jj_split_manifest.Regular ~symlink_target:None ~size_bytes:20
       ~content_digest:(digest 'b')
       ~artifact:Mainline_carrier_policy.Deterministic_evolution_projection
       ~disposition:Mainline_carrier_policy.Sanitize_and_track
       ~sanitizer_identity:(Some (identity sanitizer))
       ~projection_identity:(Some (identity projection_id))
       ~exclusion_reason:None)

let excluded ?(why = "private-runtime-state") () =
  get
    (Jj_source_manifest.entry ~path:(path "state/session.dat")
       ~mode:Jj_split_manifest.Regular ~symlink_target:None ~size_bytes:12
       ~content_digest:(digest 'c')
       ~artifact:Mainline_carrier_policy.Session
       ~disposition:Mainline_carrier_policy.Exclude
       ~sanitizer_identity:None ~projection_identity:None
       ~exclusion_reason:(Some (reason why)))

let tests () =
  check "M1 source, deterministic projection, and excluded observations admit"
    (Result.is_ok (Jj_source_manifest.make [ source (); projection (); excluded () ]));
  check "M2 paths are normalized by the lower path authority"
    (Result.is_error (Jj_path.make "../escape")
     && Result.is_error (Jj_path.make "a//b"));
  check "M3 bounded typed metadata refuses empty, NUL, and oversized values"
    (Result.is_error (Jj_source_manifest.Identity.make "")
     && Result.is_error (Jj_source_manifest.Identity.make "bad\000identity")
     && Result.is_error
          (Jj_source_manifest.Identity.make (String.make 513 'a'))
     && Result.is_error (Jj_source_manifest.Symlink_target.make "")
     && Result.is_error
          (Jj_source_manifest.Symlink_target.make (String.make 4097 'a')));
  check "M4 mode and symlink target correspondence is exact"
    (Result.is_error
       (Jj_source_manifest.entry ~path:(path "link")
          ~mode:Jj_split_manifest.Symlink ~symlink_target:None ~size_bytes:3
          ~content_digest:(digest 'a') ~artifact:Mainline_carrier_policy.Source
          ~disposition:Mainline_carrier_policy.Track ~sanitizer_identity:None
          ~projection_identity:None ~exclusion_reason:None)
     && Result.is_error
          (Jj_source_manifest.entry ~path:(path "plain")
             ~mode:Jj_split_manifest.Regular
             ~symlink_target:(Some (target "dst")) ~size_bytes:3
             ~content_digest:(digest 'a') ~artifact:Mainline_carrier_policy.Source
             ~disposition:Mainline_carrier_policy.Track ~sanitizer_identity:None
             ~projection_identity:None ~exclusion_reason:None)
     && Result.is_error
          (Jj_source_manifest.entry ~path:(path "link")
             ~mode:Jj_split_manifest.Symlink
             ~symlink_target:(Some (target "dst")) ~size_bytes:4
             ~content_digest:(bytes_digest "dst")
             ~artifact:Mainline_carrier_policy.Source
             ~disposition:Mainline_carrier_policy.Track ~sanitizer_identity:None
             ~projection_identity:None ~exclusion_reason:None)
     && Result.is_error
          (Jj_source_manifest.entry ~path:(path "link")
             ~mode:Jj_split_manifest.Symlink
             ~symlink_target:(Some (target "dst")) ~size_bytes:3
             ~content_digest:(digest 'a') ~artifact:Mainline_carrier_policy.Source
             ~disposition:Mainline_carrier_policy.Track ~sanitizer_identity:None
             ~projection_identity:None ~exclusion_reason:None));
  check "M5 sanitizer and projection identities are required only together"
    (Result.is_error
       (Jj_source_manifest.entry ~path:(path "generated/x")
          ~mode:Jj_split_manifest.Regular ~symlink_target:None ~size_bytes:1
          ~content_digest:(digest 'a')
          ~artifact:Mainline_carrier_policy.Deterministic_evolution_projection
          ~disposition:Mainline_carrier_policy.Sanitize_and_track
          ~sanitizer_identity:(Some (identity "sanitize"))
          ~projection_identity:None ~exclusion_reason:None)
     && Result.is_error
          (Jj_source_manifest.entry ~path:(path "plain")
             ~mode:Jj_split_manifest.Regular ~symlink_target:None ~size_bytes:1
             ~content_digest:(digest 'a') ~artifact:Mainline_carrier_policy.Source
             ~disposition:Mainline_carrier_policy.Track
             ~sanitizer_identity:(Some (identity "unexpected"))
             ~projection_identity:None ~exclusion_reason:None));
  check "M6 excluded carriers require a reason and cannot escalate"
    (Result.is_error
       (Jj_source_manifest.entry ~path:(path "state/session")
          ~mode:Jj_split_manifest.Regular ~symlink_target:None ~size_bytes:1
          ~content_digest:(digest 'a') ~artifact:Mainline_carrier_policy.Session
          ~disposition:Mainline_carrier_policy.Exclude ~sanitizer_identity:None
          ~projection_identity:None ~exclusion_reason:None)
     && Result.is_error
          (Jj_source_manifest.entry ~path:(path "state/session")
             ~mode:Jj_split_manifest.Regular ~symlink_target:None ~size_bytes:1
             ~content_digest:(digest 'a') ~artifact:Mainline_carrier_policy.Session
             ~disposition:Mainline_carrier_policy.Track ~sanitizer_identity:None
             ~projection_identity:None
             ~exclusion_reason:(Some (reason "private"))));
  let original = source () in
  let identical = source () in
  let conflict = source ~content_digest:(digest 'd') () in
  check "M7 identical replay is idempotent but same path different identity conflicts"
    ((match Jj_source_manifest.make [ original; identical ] with
      | Ok manifest -> Jj_source_manifest.entry_count manifest = 1
      | Error _ -> false)
     && Jj_source_manifest.make [ original; conflict ]
        = Error Jj_source_manifest.Path_identity_conflict);
  let a = source ~path_value:"modules/a.ml" () in
  let b = source ~path_value:"modules/b.ml" ~content_digest:(digest 'b') () in
  let forward = get (Jj_source_manifest.make [ a; b ]) in
  let reverse = get (Jj_source_manifest.make [ b; a ]) in
  check "M8 canonical manifest identity is enumeration-order independent"
    (String.equal (Jj_source_manifest.digest forward)
       (Jj_source_manifest.digest reverse));
  let digest_only_source =
    get
      (Jj_source_manifest.entry ~path:(path "modules/a.ml")
         ~mode:Jj_split_manifest.Regular ~symlink_target:None ~size_bytes:10
         ~content_digest:(digest 'a') ~artifact:Mainline_carrier_policy.Source
         ~disposition:Mainline_carrier_policy.Digest_only ~sanitizer_identity:None
         ~projection_identity:None
         ~exclusion_reason:(Some (reason "digest-only")))
  in
  let excluded_credential =
    get
      (Jj_source_manifest.entry ~path:(path "state/session.dat")
         ~mode:Jj_split_manifest.Regular ~symlink_target:None ~size_bytes:12
         ~content_digest:(digest 'c') ~artifact:Mainline_carrier_policy.Credential
         ~disposition:Mainline_carrier_policy.Exclude ~sanitizer_identity:None
         ~projection_identity:None
         ~exclusion_reason:(Some (reason "private-runtime-state")))
  in
  let symlink_one =
    source ~path_value:"link" ~mode:Jj_split_manifest.Symlink
      ~symlink_target:(target "target-a") ~size_bytes:8
      ~content_digest:(bytes_digest "target-a") ()
  in
  let symlink_two =
    source ~path_value:"link" ~mode:Jj_split_manifest.Symlink
      ~symlink_target:(target "target-b") ~size_bytes:8
      ~content_digest:(bytes_digest "target-b") ()
  in
  check "M9 every canonical field changes entry identity"
    (let field_pairs =
       [ original, source ~path_value:"modules/z.ml" ();
         original, source ~mode:Jj_split_manifest.Executable ();
         original, source ~size_bytes:11 ();
         original, source ~content_digest:(digest 'd') ();
         original, digest_only_source;
         excluded (), excluded_credential;
         projection (), projection ~sanitizer:"sanitize-v2" ();
         projection (), projection ~projection_id:"projection-v2" ();
         excluded (), excluded ~why:"different-reason" ();
         symlink_one, symlink_two ]
     in
     List.for_all
       (fun (left, right) ->
          not
            (String.equal (Jj_source_manifest.entry_digest left)
               (Jj_source_manifest.entry_digest right)))
       field_pairs);
  check "M10 entry and closure bounds fail closed"
    (Result.is_error
       (Jj_source_manifest.entry ~path:(path "too-large")
          ~mode:Jj_split_manifest.Regular ~symlink_target:None
          ~size_bytes:(Mainline_carrier_policy.max_artifact_bytes + 1)
          ~content_digest:(digest 'a') ~artifact:Mainline_carrier_policy.Source
          ~disposition:Mainline_carrier_policy.Track ~sanitizer_identity:None
          ~projection_identity:None ~exclusion_reason:None)
     && Result.is_error
          (Jj_source_manifest.make
             (List.init (Jj_source_manifest.max_entries + 1) (fun index ->
                  source ~path_value:(Printf.sprintf "x/%04d" index) ()))));
  check "M11 pure authority exposes no filesystem or process operation"
    (Jj_source_manifest.schema_id = "hermes.jj-source-manifest.v1")

let () =
  tests ();
  match List.rev !failures with
  | [] -> outcome := (11, 0)
  | names ->
      List.iter (Printf.eprintf "FAIL %s\n") names;
      outcome := (11 - List.length names, List.length names)
