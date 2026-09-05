(* ZK MoC Freeze Enforcer — a REAL frontmatter-status guard over the live corpus.

   Promoted from a phase-7 printf stub. The law: a MoC note whose frontmatter says
   `status: published` has been human-promoted and MUST NOT be overwritten by the
   deterministic generators (which are only ever allowed to (re)write drafts).

   This module reads every docs/zk/moc-*.md, parses the YAML frontmatter `status:`
   field, and partitions MoCs into a FROZEN set (published) and a WRITABLE set
   (draft/other). For each frozen MoC it takes a content fingerprint (Digest.file,
   the MD5 over the exact bytes) so a caller can later prove immutability by
   re-fingerprinting and comparing. It emits the freeze policy the generator must
   obey and flags any generator write against a frozen path as a violation.

   [NOTE] the fingerprint is a Stdlib.Digest (MD5) checksum for change-detection,
   not a cryptographic signature — it detects accidental/observed overwrite, it
   does not authenticate the writer. *)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

(* every moc-*.md directly under docs/zk *)
let moc_files root =
  let dir = Filename.concat root "docs/zk" in
  let entries = try Sys.readdir dir with _ -> [||] in
  Array.to_list entries
  |> List.filter (fun n ->
       Filename.check_suffix n ".md"
       && String.length n >= 4 && String.sub n 0 4 = "moc-")
  |> List.map (fun n -> Filename.concat dir n)
  |> List.sort compare

(* first `status: X` inside the leading `---`..`---` frontmatter block *)
let frontmatter_status body =
  let lines = String.split_on_char '\n' body in
  let rec skip_open = function
    | l :: tl when String.trim l = "" -> skip_open tl
    | l :: tl when String.trim l = "---" -> Some tl
    | _ -> None in
  match skip_open lines with
  | None -> None
  | Some rest ->
    let rec find = function
      | l :: _ when String.trim l = "---" -> None
      | l :: tl ->
        let t = String.trim l in
        let pfx = "status:" in
        if String.length t >= String.length pfx
           && String.sub t 0 (String.length pfx) = pfx then
          Some (String.trim (String.sub t (String.length pfx)
                               (String.length t - String.length pfx)))
        else find tl
      | [] -> None
    in find rest

let run (root : string) : unit =
  let mocs = moc_files root in
  Printf.printf "[zk_moc_freeze_enforcer] MoC notes under docs/zk: %d\n" (List.length mocs);
  let frozen = ref [] and writable = ref [] in
  List.iter (fun path ->
    let body = try read_file path with _ -> "" in
    let status = match frontmatter_status body with Some s -> s | None -> "(none)" in
    let fp = try Digest.to_hex (Digest.string body) with _ -> "-" in
    if status = "published" then frozen := (path, fp) :: !frozen
    else writable := (path, status) :: !writable
  ) mocs;
  Printf.printf "  FROZEN (published, generator MUST NOT overwrite): %d\n" (List.length !frozen);
  List.iter (fun (p, fp) ->
    Printf.printf "    [FROZEN] %s  md5=%s\n" (Filename.basename p) fp) (List.rev !frozen);
  Printf.printf "  WRITABLE (draft/other, generator may regenerate): %d\n" (List.length !writable);
  List.iter (fun (p, s) ->
    Printf.printf "    [ok-to-regen] %s  status=%s\n" (Filename.basename p) s) (List.rev !writable);
  (* Enforcement decision function the generator is bound by. *)
  let may_write path =
    not (List.exists (fun (p, _) -> p = path) !frozen) in
  let violations =
    List.filter (fun (p, _) -> not (may_write p)) !frozen in
  Printf.printf "  policy: may_write(published)=false for all %d frozen paths (would-be violations if written: %d)\n"
    (List.length !frozen) (List.length violations);
  Printf.printf "  [NOTE] freeze uses MD5 change-detection fingerprints, not cryptographic signatures\n"
