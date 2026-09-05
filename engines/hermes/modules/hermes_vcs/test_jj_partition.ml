let failures = ref []
let check name condition = if not condition then failures := name :: !failures

let path value =
  match Jj_path.make value with
  | Ok path -> path
  | Error _ -> failwith ("invalid path fixture: " ^ value)

let range start_offset end_offset =
  match Jj_split_manifest.range ~start_offset ~end_offset with
  | Ok range -> range
  | Error _ -> failwith "invalid range fixture"

let partition ~path_value ~mode bytes =
  let blob = Jj_split_manifest.Digest.of_bytes bytes in
  let length = Bytes.length bytes in
  match
    Jj_split_manifest.partition
      ~source_authority:
        (Jj_split_manifest.Digest.of_bytes (Bytes.of_string "source"))
      ~path:(path path_value) ~base_blob:blob ~current_blob:blob
      ~base_mode:mode ~current_mode:mode ~base_bytes:bytes
      ~current_bytes:bytes ~selected:[ range 0 2 ]
      ~remainder:[ range 2 length ]
  with
  | Ok partition -> partition
  | Error _ -> failwith "valid partition fixture refused"

let physical_branch () =
  let prefix =
    match Jj_recovery_schema.partial_prefix ~completed:1 ~total:2 with
    | Ok prefix -> prefix
    | Error _ -> failwith "valid prefix fixture refused"
  in
  let schema =
    Jj_recovery_schema.schema
      (Jj_recovery_schema.B_success
         (Jj_recovery_schema.After_action
            (Jj_recovery_schema.B_write_partition_partial prefix),
          Jj_recovery_schema.In_process))
  in
  match
    List.find_opt Jj_recovery_schema.b_requires_physical_restoration
      (Jj_recovery_schema.b_branches schema)
  with
  | Some branch -> branch
  | None -> failwith "physical recovery branch missing"

let operation_only_branch () =
  let schema =
    Jj_recovery_schema.schema
      (Jj_recovery_schema.B_success
         (Jj_recovery_schema.After_action Jj_recovery_schema.B_bookmark_set,
          Jj_recovery_schema.In_process))
  in
  match
    List.find_opt
      (fun branch ->
        Jj_recovery_schema.b_disposition branch
        = Jj_recovery_schema.Restore_operation_only)
      (Jj_recovery_schema.b_branches schema)
  with
  | Some branch -> branch
  | None -> failwith "operation-only branch missing"

let regular path bytes =
  match Jj_partition.regular ~path bytes with
  | Ok restored -> restored
  | Error _ -> failwith "valid regular snapshot refused"

let executable path bytes =
  match Jj_partition.executable ~path bytes with
  | Ok restored -> restored
  | Error _ -> failwith "valid executable snapshot refused"

let () =
  let bytes = Bytes.of_string "abcdefgh" in
  let manifest =
    partition ~path_value:"shared.ml" ~mode:Jj_split_manifest.Regular bytes
  in
  let branch = physical_branch () in
  let restored = regular (path "shared.ml") bytes in
  check "P1 exact bytes mode path and schema produce a physical-restoration proof"
    (match Jj_partition.prove ~branch ~partition:manifest ~restored with
     | Error _ -> false
     | Ok proof ->
         Jj_path.equal (Jj_partition.proof_path proof) (path "shared.ml")
         && Jj_partition.proof_mode proof = Jj_split_manifest.Regular
         && Jj_partition.proof_manifest_digest proof
            = Jj_split_manifest.partition_digest manifest
         && String.length (Jj_partition.proof_digest proof) = 64);

  check "P2 a nonphysical B disposition cannot authorize partition restoration"
    (match
       Jj_partition.prove ~branch:(operation_only_branch ())
         ~partition:manifest ~restored
     with
     | Error Jj_partition.Physical_restoration_not_required -> true
     | _ -> false);

  check "P3 path mismatch refuses"
    (match
       Jj_partition.prove ~branch ~partition:manifest
         ~restored:(regular (path "other.ml") bytes)
     with
     | Error Jj_partition.Path_mismatch -> true
     | _ -> false);

  check "P4 byte mismatch refuses"
    (match
       Jj_partition.prove ~branch ~partition:manifest
         ~restored:
           (regular (path "shared.ml") (Bytes.of_string "abcdEfgh"))
     with
     | Error Jj_partition.Byte_mismatch -> true
     | _ -> false);

  check "P5 executable versus regular mode mismatch refuses"
    (match
       Jj_partition.prove ~branch ~partition:manifest
         ~restored:(executable (path "shared.ml") bytes)
     with
     | Error Jj_partition.Mode_mismatch -> true
     | _ -> false);

  let target = Bytes.of_string "../target" in
  let symlink_manifest =
    partition ~path_value:"shared.link" ~mode:Jj_split_manifest.Symlink target
  in
  let symlink value =
    match Jj_partition.symlink ~path:(path "shared.link") ~target:value with
    | Ok restored -> restored
    | Error _ -> failwith "valid symlink fixture refused"
  in
  check "P6 exact symlink target is compatible"
    (Result.is_ok
       (Jj_partition.prove ~branch ~partition:symlink_manifest
          ~restored:(symlink target)));
  check "P7 changed symlink target is distinguished from ordinary bytes"
    (match
       Jj_partition.prove ~branch ~partition:symlink_manifest
         ~restored:(symlink (Bytes.of_string "../otherx"))
     with
     | Error Jj_partition.Symlink_target_mismatch -> true
     | _ -> false);
  check "P8 empty NUL and unbounded symlink targets refuse before proof"
    (Result.is_error
       (Jj_partition.symlink ~path:(path "shared.link") ~target:Bytes.empty)
     && Result.is_error
          (Jj_partition.symlink ~path:(path "shared.link")
             ~target:(Bytes.of_string "bad\000target"))
     && Result.is_error
          (Jj_partition.symlink ~path:(path "shared.link")
             ~target:(Bytes.make 4097 'x')));

  List.iter (fun name -> Printf.printf "FAILED: %s\n" name)
    (List.rev !failures);
  let failed = List.length !failures in
  let passed = 8 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_partition"
    ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vcs ]);
  exit (Suite_telemetry.exit_code self)
