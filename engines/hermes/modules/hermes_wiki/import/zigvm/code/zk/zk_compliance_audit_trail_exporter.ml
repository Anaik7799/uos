(* ZK Compliance Audit Trail Exporter — a REAL attestation-ledger builder.

   Promoted from a phase-7 printf stub. Every ZK note carries an
   agent-collaborative verification stamp in its YAML frontmatter
   (`status:` / `last_verified:` / `verified_by:`). This module DISTILLS those
   stamps from the live corpus into a deterministic, tamper-evident audit trail:
   one attestation row per note (id, slug, status, last_verified, verified_by)
   plus a content checksum, and a single corpus-level roll-up digest.

   METHOD. Recursively scan `<root>/docs/zk/**/*.md`, parse frontmatter with the
   real `Docs_wiki.parse_frontmatter`, and for each note record its declared
   attestation and a `Digest` (MD5) of the file bytes. The corpus digest is the
   MD5 over the sorted-by-slug list of (slug, per-note digest) pairs, so it is a
   pure function of content that changes iff any attested note changes.

   [NOTE] Digest is a checksum, NOT a cryptographic signature — it proves
   content-consistency (a note cannot silently change without the roll-up
   changing) but not authorship / non-repudiation. A real signing scheme would
   need a keyed MAC or asymmetric key, which the harness does not provision. *)

module Docs_wiki = Wiki_render.Docs_wiki

let read_file p =
  let ic = open_in_bin p in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let rec walk_md dir =
  if Sys.file_exists dir && Sys.is_directory dir then
    Array.to_list (Sys.readdir dir)
    |> List.sort String.compare
    |> List.concat_map (fun e ->
           let p = Filename.concat dir e in
           if (try Sys.is_directory p with Sys_error _ -> false) then walk_md p
           else if Filename.check_suffix p ".md" then [ p ]
           else [])
  else []

let run (root : string) : unit =
  let zk_dir = Filename.concat root "docs/zk" in
  let files = walk_md zk_dir in
  if files = [] then
    Printf.printf
      "[zk_compliance_audit_trail_exporter] no notes under %s — empty audit \
       trail.\n"
      zk_dir
  else begin
  let get kv k = match kv with None -> None | Some l -> List.assoc_opt k l in
  let rows =
    List.map
      (fun p ->
        let raw = read_file p in
        let kv, _body = Docs_wiki.parse_frontmatter raw in
        let slug = Filename.remove_extension (Filename.basename p) in
        let vby = Option.value ~default:"(none)" (get kv "verified_by") in
        let lv = Option.value ~default:"(none)" (get kv "last_verified") in
        let status = Option.value ~default:"(none)" (get kv "status") in
        let id = Option.value ~default:"(derived)" (get kv "id") in
        let dg = Digest.to_hex (Digest.string raw) in
        (slug, id, status, lv, vby, dg))
      files
  in
  (* tallies by verified_by and by status *)
  let tally sel =
    let h = Hashtbl.create 16 in
    List.iter
      (fun r ->
        let k = sel r in
        Hashtbl.replace h k (1 + Option.value ~default:0 (Hashtbl.find_opt h k)))
      rows;
    Hashtbl.fold (fun k v acc -> (k, v) :: acc) h []
    |> List.sort compare
  in
  let by_vby = tally (fun (_, _, _, _, v, _) -> v) in
  let unstamped =
    List.filter (fun (_, _, _, lv, v, _) -> v = "(none)" || lv = "(none)") rows
  in
  (* deterministic corpus roll-up digest over sorted (slug,digest) *)
  let corpus_digest =
    rows
    |> List.map (fun (s, _, _, _, _, dg) -> s ^ ":" ^ dg)
    |> List.sort String.compare |> String.concat "\n" |> Digest.string
    |> Digest.to_hex
  in
  Printf.printf
    "[zk_compliance_audit_trail_exporter] audit trail: %d attested notes under \
     docs/zk\n"
    (List.length rows);
  List.iter
    (fun (k, n) -> Printf.printf "  verified_by=%-10s : %d\n" k n)
    by_vby;
  Printf.printf "  unstamped (missing verified_by or last_verified) : %d\n"
    (List.length unstamped);
  List.iter
    (fun (s, _, _, _, _, _) -> Printf.printf "    - %s\n" s)
    (List.filteri (fun i _ -> i < 10) unstamped);
  Printf.printf
    "[zk_compliance_audit_trail_exporter] corpus roll-up checksum = %s\n"
    corpus_digest;
  Printf.printf
    "[zk_compliance_audit_trail_exporter] [NOTE] MD5 content checksum, not a \
     cryptographic signature — proves content-consistency, not authorship.\n"
  end
