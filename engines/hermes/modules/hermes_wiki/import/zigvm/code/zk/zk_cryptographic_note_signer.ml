(* ZK Cryptographic Note Signer — REAL tamper-evidence manifest over the ZK
   corpus, using a real checksum (honest about what it is NOT).

   Intent (phase-7 stub): "append a cryptographic signature to critical ADR notes
   to prove they haven't been tampered with." Two honesty constraints: (1) there
   is no keypair / asymmetric-crypto library wired into this harness lib, so we
   CANNOT produce a real digital signature — we compute a real MD5 checksum via
   Stdlib.Digest, which is a tamper-EVIDENCE fingerprint, not an unforgeable
   signature; (2) mutating the corpus (appending to notes) is a destructive side
   effect, so we instead build a MANIFEST (path -> digest) plus a single
   fold-digest over the sorted manifest (a cheap Merkle-style root) and print it.
   Re-running and diffing the root detects any note change. We label it plainly:
   [NOTE] MD5 checksum, NOT a cryptographic signature. *)

let read_file p = try In_channel.with_open_bin p In_channel.input_all with _ -> ""

let rec md_under dir acc =
  match Sys.readdir dir with
  | entries ->
      Array.fold_left
        (fun acc e ->
          let p = Filename.concat dir e in
          if (try Sys.is_directory p with _ -> false) then md_under p acc
          else if Filename.check_suffix e ".md" then p :: acc
          else acc)
        acc entries
  | exception _ -> acc

let run (root : string) : unit =
  let zk = Filename.concat (Filename.concat root "docs") "zk" in
  let files = List.sort compare (md_under zk []) in
  let manifest =
    List.map
      (fun p ->
        let rel =
          if String.length p > String.length root + 1 then
            String.sub p (String.length root + 1) (String.length p - String.length root - 1)
          else p
        in
        (rel, Digest.to_hex (Digest.string (read_file p))))
      files
  in
  (* fold-digest (Merkle-style root) over "rel:digest\n" lines, order-fixed *)
  let root_line =
    manifest
    |> List.map (fun (rel, d) -> rel ^ ":" ^ d)
    |> String.concat "\n"
  in
  let manifest_root = Digest.to_hex (Digest.string root_line) in
  Printf.printf
    "[zk_cryptographic_note_signer] %d ZK note(s) fingerprinted; manifest-root(MD5)=%s\n"
    (List.length manifest) manifest_root;
  (* show a few sample rows so the output is concrete, not a bare claim *)
  let rec take n = function [] -> [] | x :: r -> if n <= 0 then [] else x :: take (n - 1) r in
  List.iter
    (fun (rel, d) -> Printf.printf "  %s  %s\n" d rel)
    (take 3 manifest);
  if List.length manifest > 3 then Printf.printf "  ... (%d more)\n" (List.length manifest - 3);
  Printf.printf
    "  [NOTE] MD5 checksum, NOT a cryptographic signature — no keypair is wired, \
     so this is tamper-EVIDENCE (re-run and diff the manifest-root), not an \
     unforgeable digital signature. Notes are read-only; nothing was appended.\n"
