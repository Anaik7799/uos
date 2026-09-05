let failures = ref []
let check name condition = if not condition then failures := name :: !failures

let digest text =
  match Jj_split_manifest.Digest.make text with
  | Ok value -> value
  | Error _ -> failwith "literal SHA-256 fixture rejected"

let path text =
  match Jj_path.make text with
  | Ok value -> value
  | Error _ -> failwith ("literal path fixture rejected: " ^ text)

let () =
  let commit =
    match Jj_id.Commit.make "abc123" with
    | Ok value -> value
    | Error _ -> failwith "commit fixture rejected"
  in
  let bookmark =
    match Jj_id.Bookmark.make "main" with
    | Ok value -> value
    | Error _ -> failwith "bookmark fixture rejected"
  in
  let remote =
    match Jj_id.Remote.make "origin" with
    | Ok value -> value
    | Error _ -> failwith "remote fixture rejected"
  in
  let literal = Jj_revset.commit commit in
  let parent =
    match Jj_revset.parent Jj_revset.working_copy with
    | Ok value -> value
    | Error _ -> failwith "bounded parent fixture rejected"
  in
  let combined =
    Jj_revset.union
      [ literal; parent; Jj_revset.remote_bookmark ~remote ~bookmark ]
  in
  check "R1 closed revsets compose deterministically without raw fragments"
    (match combined with
     | Ok value ->
         String.length (Jj_revset.digest value) = 64
         && Jj_revset.equal value value
     | Error _ -> false);
  check "R2 empty, excessive, and nonpositive revset bounds refuse"
    (Result.is_error (Jj_revset.union [])
     && Result.is_error (Jj_revset.union (List.init 65 (fun _ -> literal)))
     && Result.is_error (Jj_revset.limit ~max_count:0 literal)
     && Result.is_error (Jj_revset.limit ~max_count:4097 literal));
  let rec nest count value =
    if count = 0 then Ok value
    else
      match Jj_revset.parent value with
      | Error error -> Error error
      | Ok next -> nest (count - 1) next
  in
  check "R3 globally deep and wide nested revsets refuse before canonicalization"
    (Result.is_ok (nest 63 literal)
     && Result.is_error (nest 65 literal)
     && match nest 63 literal with
        | Error _ -> false
        | Ok deep -> Result.is_error (Jj_revset.union (List.init 64 (fun _ -> deep))));

  check "P1 paths are repository-relative literal paths without traversal or globs"
    (List.for_all
       (fun candidate -> Result.is_error (Jj_path.make candidate))
       [ ""; "/etc/passwd"; "../secret"; "src/../secret"; "src//x";
         "src/*.ml"; "src/[ab].ml"; "src\\x" ]
     && match Jj_path.make "modules/hermes_vcs/jj_path.ml" with
        | Ok value ->
            Jj_path.to_string value = "modules/hermes_vcs/jj_path.ml"
        | Error _ -> false);

  let source_authority =
    digest "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  in
  let blob_a =
    digest "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  in
  let blob_b =
    digest "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  in
  let file_a =
    Jj_split_manifest.file ~path:(path "a.ml") ~base_blob:blob_a
      ~current_blob:blob_a ~base_mode:Jj_split_manifest.Regular
      ~current_mode:Jj_split_manifest.Regular
  in
  let file_b =
    Jj_split_manifest.file ~path:(path "b.ml") ~base_blob:blob_b
      ~current_blob:blob_b ~base_mode:Jj_split_manifest.Regular
      ~current_mode:Jj_split_manifest.Executable
  in
  check "M1 whole-file manifests preserve order and reject duplicate or unknown selections"
    (match file_a, file_b with
     | Ok file_a, Ok file_b ->
         (match
            Jj_split_manifest.whole ~source_authority
              ~files:[ file_a; file_b ] ~selected:[ path "b.ml" ]
          with
          | Ok manifest ->
              Jj_split_manifest.whole_selected manifest = [ path "b.ml" ]
              && Jj_split_manifest.whole_remainder manifest = [ path "a.ml" ]
              && String.length (Jj_split_manifest.whole_digest manifest) = 64
          | Error _ -> false)
         && Result.is_error
              (Jj_split_manifest.whole ~source_authority
                 ~files:[ file_a; file_a ] ~selected:[ path "a.ml" ])
         && Result.is_error
              (Jj_split_manifest.whole ~source_authority
                 ~files:[ file_a; file_b ] ~selected:[ path "missing.ml" ])
     | _ -> false);

  let base_bytes = Bytes.of_string "abcdefgh" in
  let current_bytes = Bytes.of_string "abXYefgh" in
  let base_blob = Jj_split_manifest.Digest.of_bytes base_bytes in
  let current_blob = Jj_split_manifest.Digest.of_bytes current_bytes in
  let range start_offset end_offset =
    match Jj_split_manifest.range ~start_offset ~end_offset with
    | Ok value -> value
    | Error _ -> failwith "range fixture rejected"
  in
  let selected = [ range 2 4 ] in
  let remainder = [ range 0 2; range 4 8 ] in
  check "M2 partition manifests prove exact reconstruction and derived output digests"
    (match
       Jj_split_manifest.partition ~source_authority ~path:(path "shared.ml")
         ~base_blob ~current_blob ~base_mode:Jj_split_manifest.Regular
         ~current_mode:Jj_split_manifest.Regular ~base_bytes ~current_bytes
         ~selected ~remainder
     with
     | Ok manifest ->
         Jj_split_manifest.partition_reconstructs manifest
         && Jj_split_manifest.Digest.to_string
              (Jj_split_manifest.partition_selected_digest manifest)
            = Jj_split_manifest.Digest.to_string
                (Jj_split_manifest.Digest.of_bytes (Bytes.of_string "XY"))
         && Jj_split_manifest.Digest.to_string
              (Jj_split_manifest.partition_remainder_digest manifest)
            = Jj_split_manifest.Digest.to_string
                (Jj_split_manifest.Digest.of_bytes (Bytes.of_string "abefgh"))
     | Error _ -> false);
  check "M3 stale blobs, overlaps, gaps, duplicates, and unbounded ranges refuse"
    (Result.is_error
       (Jj_split_manifest.partition ~source_authority ~path:(path "shared.ml")
          ~base_blob ~current_blob:blob_a ~base_mode:Jj_split_manifest.Regular
          ~current_mode:Jj_split_manifest.Regular ~base_bytes ~current_bytes
          ~selected ~remainder)
     && Result.is_error
          (Jj_split_manifest.partition ~source_authority ~path:(path "shared.ml")
             ~base_blob ~current_blob ~base_mode:Jj_split_manifest.Regular
             ~current_mode:Jj_split_manifest.Regular ~base_bytes ~current_bytes
             ~selected:[ range 2 5 ] ~remainder:[ range 0 3; range 5 8 ])
     && Result.is_error
          (Jj_split_manifest.partition ~source_authority ~path:(path "shared.ml")
             ~base_blob ~current_blob ~base_mode:Jj_split_manifest.Regular
             ~current_mode:Jj_split_manifest.Regular ~base_bytes ~current_bytes
             ~selected ~remainder:[ range 0 2; range 5 8 ])
     && Result.is_error
          (Jj_split_manifest.partition ~source_authority ~path:(path "shared.ml")
             ~base_blob ~current_blob ~base_mode:Jj_split_manifest.Regular
             ~current_mode:Jj_split_manifest.Regular ~base_bytes ~current_bytes
             ~selected:[ range 2 4; range 2 4 ] ~remainder));

  check "D1 revset path and split-manifest authorities expose distinct SHA-256 digests"
    (Jj_revset.source_digest
       = "5bd679d1f981821c422becdb463eda8e8055041786d406efd7b35d770c8596fb"
     && Jj_path.source_digest
        = "fb0a4b7dab12c324237583a519b6370945892a7b6e9e78dcb98ac18485409332"
     && Jj_split_manifest.source_digest
        = "656c54b41bdaa464a0a028ad54d378d6dbc2096cd35675494f6a99167bc931ed"
     && List.length
          (List.sort_uniq String.compare
             [ Jj_revset.source_digest; Jj_path.source_digest;
               Jj_split_manifest.source_digest ]) = 3);

  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 8 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_revset_manifest"
    ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vcs ]);
  Printf.printf "Jujutsu revset source digest: %s\n" Jj_revset.source_digest;
  Printf.printf "Jujutsu path source digest: %s\n" Jj_path.source_digest;
  Printf.printf "Jujutsu split-manifest source digest: %s\n"
    Jj_split_manifest.source_digest;
  exit (Suite_telemetry.exit_code self)
