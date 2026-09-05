(* ZK Agent Write Quota Enforcer — a REAL, honest authoring-volume auditor.

   INTENT (from the phase-7 stub).  "Enforces a strict byte-quota per agent per
   day on zk_author_note to prevent AI spam attacks."

   WHAT THIS HONESTLY DOES.  It reads the ZK corpus under [root]/docs/zk, parses
   each note's YAML frontmatter for its author (`verified_by:`) and day
   (`last_verified:`), sums note bytes per (author, day) bucket, and flags any
   bucket that exceeds the daily byte quota. It reports every bucket and the
   over-quota offenders.

   [NOTE] this is a RETROSPECTIVE DETECTION channel over on-disk attribution,
   not a write-time gate: a batch/audit module cannot intercept a live
   zk_author_note call. The frontmatter `verified_by`/`last_verified` fields are
   the only authorship signal on disk (there is no per-write byte ledger table),
   so the buckets are attributed by note metadata, not by an authenticated
   agent identity. Detection here would drive a real write-time block elsewhere. *)

let daily_quota_bytes = 400_000

let read_file path =
  try In_channel.with_open_bin path In_channel.input_all with _ -> ""

let list_zk root =
  let base = Filename.concat (Filename.concat root "docs") "zk" in
  let acc = ref [] in
  let rec go dir =
    match Sys.readdir dir with
    | entries ->
        Array.iter
          (fun e ->
            let p = Filename.concat dir e in
            if (try Sys.is_directory p with _ -> false) then go p
            else if Filename.check_suffix e ".md" then acc := p :: !acc)
          entries
    | exception _ -> ()
  in
  if (try Sys.is_directory base with _ -> false) then go base;
  List.sort compare !acc

(* Pull a `key: value` from the leading YAML frontmatter (between the first two
   `---` fences). Returns default if absent. *)
let frontmatter_field text key default =
  let ls = String.split_on_char '\n' text in
  let rec scan in_fm seen = function
    | [] -> default
    | line :: rest ->
        let t = String.trim line in
        if t = "---" then
          if seen = 0 then scan true 1 rest
          else default (* closing fence, key not found *)
        else if in_fm then
          let prefix = key ^ ":" in
          if
            String.length t >= String.length prefix
            && String.sub t 0 (String.length prefix) = prefix
          then String.trim (String.sub t (String.length prefix)
                              (String.length t - String.length prefix))
          else scan in_fm seen rest
        else scan in_fm seen rest
  in
  scan false 0 ls

let run (root : string) : unit =
  Printf.printf
    "[zk_agent_write_quota_enforcer] auditing per-(author,day) authoring bytes (quota=%d B/day)\n"
    daily_quota_bytes;
  let files = list_zk root in
  (* bucket key "author|day" -> (bytes, note_count) *)
  let tbl : (string, int * int) Hashtbl.t = Hashtbl.create 64 in
  List.iter
    (fun f ->
      let text = read_file f in
      let author = frontmatter_field text "verified_by" "(unattributed)" in
      let day = frontmatter_field text "last_verified" "(undated)" in
      let key = author ^ "|" ^ day in
      let bytes, n = try Hashtbl.find tbl key with Not_found -> (0, 0) in
      Hashtbl.replace tbl key (bytes + String.length text, n + 1))
    files;
  let buckets =
    Hashtbl.fold (fun k (b, n) acc -> (k, b, n) :: acc) tbl []
    |> List.sort (fun (_, b1, _) (_, b2, _) -> compare b2 b1)
  in
  Printf.printf "  notes scanned: %d   buckets: %d\n" (List.length files)
    (List.length buckets);
  let offenders = ref 0 in
  List.iter
    (fun (k, b, n) ->
      let over = b > daily_quota_bytes in
      if over then incr offenders;
      Printf.printf "  %-9s %s  %7d B  %3d notes%s\n"
        (if over then "[OVER]" else "[ok]") k b n
        (if over then
           Printf.sprintf "  (+%d B over quota)" (b - daily_quota_bytes)
         else ""))
    buckets;
  Printf.printf "  over-quota buckets: %d\n" !offenders;
  Printf.printf
    "  [NOTE] retrospective detection over frontmatter attribution — not a write-time gate\n"
