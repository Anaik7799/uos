(* ZK SQLite DB "Encryption" Wrapper — an HONEST at-rest posture report.

   Promoted from a phase-7 printf stub whose claim ("cipher barriers on the
   SQLite ledger") was fiction: this repo links plain sqlite3, with NO SQLCipher
   / SEE / cipher VFS in the build, so the evidence store is plaintext on disk.

   WHAT IT REALLY DOES.  For the live ledger and its sidecars (`-wal`, `-shm`,
   `-journal`) under [root] it reports the real at-rest facts:
     - the 16-byte SQLite header magic ("SQLite format 3\000") — i.e. whether the
       bytes on disk are a recognisable plaintext SQLite file (an encrypted DB
       would NOT carry this magic);
     - each file's size and a Stdlib.Digest (MD5) fingerprint — an at-rest
       INTEGRITY tamper-fingerprint, computed with the DB opened READONLY so the
       report never mutates the store.

   [LIMITATION] No SMT/crypto/SQLCipher is wired into this harness build; there
   is no confidentiality layer to assert. This is an at-rest posture + integrity
   fingerprint report, NOT encryption.
   [NOTE] The Digest is a plain MD5 checksum for tamper-detection, NOT a
   cryptographic signature and NOT confidentiality. *)

let read_prefix p n =
  try
    let ic = open_in_bin p in
    let len = min n (in_channel_length ic) in
    let s = really_input_string ic len in
    close_in ic;
    Some s
  with _ -> None

let sqlite_magic = "SQLite format 3\000"

let report_file path =
  if not (Sys.file_exists path) then
    Printf.printf "  %-40s : absent\n" (Filename.basename path)
  else begin
    let size = (try (Unix.stat path).Unix.st_size with _ -> -1) in
    let plaintext =
      match read_prefix path (String.length sqlite_magic) with
      | Some hdr -> hdr = sqlite_magic
      | None -> false
    in
    let digest = try Digest.to_hex (Digest.file path) with _ -> "?" in
    Printf.printf "  %-40s : %d bytes  header=%s  md5=%s\n"
      (Filename.basename path) size
      (if plaintext then "PLAINTEXT-SQLite" else "not-plain-sqlite")
      digest
  end

let run (root : string) : unit =
  Printf.printf
    "[zk_sqlite_db_encryption_wrapper] at-rest posture of the evidence store (READONLY)...\n";
  let db = Filename.concat root "harness/state/zigvm_harness.sqlite3" in
  List.iter
    (fun sfx -> report_file (db ^ sfx))
    [ ""; "-wal"; "-shm"; "-journal" ];
  Printf.printf
    "  [LIMITATION] no SQLCipher/cipher VFS in this build — the ledger is \
     plaintext at rest; this is a posture + integrity report, NOT encryption\n";
  Printf.printf
    "  [NOTE] md5 above is a tamper-detection checksum, NOT a cryptographic \
     signature and NOT confidentiality\n"
