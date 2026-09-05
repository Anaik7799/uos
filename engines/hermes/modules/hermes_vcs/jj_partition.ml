type restored = {
  path : Jj_path.t;
  mode : Jj_split_manifest.file_mode;
  blob : Jj_split_manifest.Digest.t;
}

type error =
  | Invalid_symlink_target
  | Restored_payload_too_large
  | Physical_restoration_not_required
  | Partition_does_not_reconstruct
  | Path_mismatch
  | Mode_mismatch
  | Byte_mismatch
  | Symlink_target_mismatch

let maximum_payload_bytes = 16 * 1024 * 1024
let maximum_symlink_target_bytes = 4096

let payload ~path ~mode bytes =
  if Bytes.length bytes > maximum_payload_bytes then
    Error Restored_payload_too_large
  else
    Ok
      { path; mode;
        blob = Jj_split_manifest.Digest.of_bytes bytes }

let regular ~path bytes =
  payload ~path ~mode:Jj_split_manifest.Regular bytes

let executable ~path bytes =
  payload ~path ~mode:Jj_split_manifest.Executable bytes

let symlink ~path ~target =
  let length = Bytes.length target in
  if length = 0 || length > maximum_symlink_target_bytes
     || Bytes.exists (fun byte -> byte = '\000') target
  then Error Invalid_symlink_target
  else payload ~path ~mode:Jj_split_manifest.Symlink target

type proof = {
  path : Jj_path.t;
  mode : Jj_split_manifest.file_mode;
  manifest_digest : string;
  restored_blob : Jj_split_manifest.Digest.t;
  digest : string;
}

let proof_path proof = proof.path
let proof_mode proof = proof.mode
let proof_manifest_digest proof = proof.manifest_digest
let proof_restored_blob proof = proof.restored_blob
let proof_digest proof = proof.digest

let mode_key = function
  | Jj_split_manifest.Regular -> "regular"
  | Jj_split_manifest.Executable -> "executable"
  | Jj_split_manifest.Symlink -> "symlink"

let disposition_key = function
  | Jj_recovery_schema.No_source_effect -> "no-source-effect"
  | Jj_recovery_schema.Restore_operation_only -> "restore-operation-only"
  | Jj_recovery_schema.Restore_operation_and_partition ->
      "restore-operation-and-partition"
  | Jj_recovery_schema.Forward_complete_exact -> "forward-complete-exact"
  | Jj_recovery_schema.Diverged -> "diverged"

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let prove ~branch ~partition ~(restored : restored) =
  if not (Jj_recovery_schema.b_requires_physical_restoration branch) then
    Error Physical_restoration_not_required
  else if not (Jj_split_manifest.partition_reconstructs partition) then
    Error Partition_does_not_reconstruct
  else
    let expected_path = Jj_split_manifest.partition_path partition in
    let expected_mode = Jj_split_manifest.partition_current_mode partition in
    let expected_blob = Jj_split_manifest.partition_current_blob partition in
    if not (Jj_path.equal expected_path restored.path) then Error Path_mismatch
    else if expected_mode <> restored.mode then Error Mode_mismatch
    else if
      not
        (String.equal
           (Jj_split_manifest.Digest.to_string expected_blob)
           (Jj_split_manifest.Digest.to_string restored.blob))
    then
      if expected_mode = Jj_split_manifest.Symlink then
        Error Symlink_target_mismatch
      else Error Byte_mismatch
    else
      let manifest_digest = Jj_split_manifest.partition_digest partition in
      let canonical =
        Jj_id.length_frame
          [ "jj-partition-proof-v1"; Jj_recovery_schema.source_digest;
            disposition_key (Jj_recovery_schema.b_disposition branch);
            manifest_digest; Jj_path.to_string expected_path;
            mode_key expected_mode;
            Jj_split_manifest.Digest.to_string expected_blob;
            Jj_split_manifest.Digest.to_string
              (Jj_split_manifest.partition_selected_digest partition);
            Jj_split_manifest.Digest.to_string
              (Jj_split_manifest.partition_remainder_digest partition) ]
      in
      Ok
        { path = expected_path; mode = expected_mode; manifest_digest;
          restored_blob = restored.blob; digest = sha256 canonical }

let source_digest =
  Jj_id.length_frame
    [ "jj-partition-schema-v1"; Jj_recovery_schema.source_digest;
      "partition-reconstructs"; "path"; "full-byte-digest"; "mode";
      "symlink-target"; "selected-digest"; "remainder-digest" ]
  |> sha256
