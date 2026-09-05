(* ZK Frontmatter Schema Enforcer — a REAL YAML-frontmatter validator.

   Promoted from a phase-7 printf stub. Every ZK note is expected to open with a
   `---` fenced YAML frontmatter block carrying the harness's self-model schema.
   Reading the live corpus (docs/zk/**/*.md) the OBSERVED universal fields are:
     id            : a note identity (UUID-shaped)
     status        : draft | ...    (a controlled vocabulary)
     last_verified : an ISO date YYYY-MM-DD
     verified_by   : who/what last verified the note (e.g. "harness")

   This module parses the leading frontmatter of each note (a deliberately small,
   line-based YAML subset — `key: value` pairs between the first two `---`
   fences) and enforces:
     PRESENCE   : the four required keys exist
     STATUS     : status ∈ {draft, active, deprecated, stub, review}
     DATE-SHAPE : last_verified matches YYYY-MM-DD (10 chars, digits+dashes)
     ID-SHAPE   : id is non-empty and hex/dash only
   It reports per-file violations and a corpus summary. Fail-closed: a missing
   frontmatter block is a violation, never a silent pass.

   [LIMITATION] This is a line-based `key: value` parser for the flat schema the
   corpus actually uses — it is NOT a general YAML parser (no nested maps, block
   scalars, or flow lists). That is sufficient for the observed frontmatter and
   is honest about its scope. *)

let required = [ "id"; "status"; "last_verified"; "verified_by" ]
let status_vocab = [ "draft"; "active"; "deprecated"; "stub"; "review"; "final" ]

let read_lines path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let rec loop acc = match input_line ic with
        | l -> loop (l :: acc)
        | exception End_of_file -> List.rev acc
      in loop [])

let rec md_files dir acc =
  match Sys.readdir dir with
  | entries ->
      Array.fold_left
        (fun acc e ->
          let p = Filename.concat dir e in
          if Sys.is_directory p then md_files p acc
          else if Filename.check_suffix p ".md" then p :: acc
          else acc)
        acc entries
  | exception Sys_error _ -> acc

(* parse the leading --- ... --- block into (key,value) pairs; None if absent *)
let parse_frontmatter lines =
  match lines with
  | first :: rest when String.trim first = "---" ->
      let rec collect acc = function
        | [] -> None (* unterminated block *)
        | l :: _ when String.trim l = "---" -> Some (List.rev acc)
        | l :: tl -> (
            match String.index_opt l ':' with
            | Some i ->
                let k = String.trim (String.sub l 0 i)
                and v = String.trim (String.sub l (i + 1) (String.length l - i - 1)) in
                collect ((k, v) :: acc) tl
            | None -> collect acc tl)
      in
      collect [] rest
  | _ -> None

let is_iso_date s =
  String.length s = 10
  && s.[4] = '-' && s.[7] = '-'
  && (let ok = ref true in
      String.iteri (fun i c ->
        if i <> 4 && i <> 7 && not (c >= '0' && c <= '9') then ok := false) s;
      !ok)

let is_id_shape s =
  s <> ""
  && String.for_all
       (fun c -> (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || c = '-')
       s

let run (root : string) : unit =
  Printf.printf "[zk_frontmatter_schema_enforcer] validating ZK frontmatter schema\n";
  let zk_dir = Filename.concat root "docs/zk" in
  let files = if Sys.file_exists zk_dir then md_files zk_dir [] else [] in
  let total = List.length files in
  let bad_files = ref 0 and total_viol = ref 0 in
  List.iter
    (fun f ->
      let name = Filename.basename f in
      let viol = ref [] in
      (match parse_frontmatter (try read_lines f with _ -> []) with
       | None -> viol := "no frontmatter block" :: !viol
       | Some fm ->
           List.iter
             (fun k -> if not (List.mem_assoc k fm) then
                 viol := ("missing key: " ^ k) :: !viol)
             required;
           (match List.assoc_opt "status" fm with
            | Some s when not (List.mem s status_vocab) ->
                viol := ("status not in vocabulary: " ^ s) :: !viol
            | _ -> ());
           (match List.assoc_opt "last_verified" fm with
            | Some d when not (is_iso_date d) ->
                viol := ("last_verified not YYYY-MM-DD: " ^ d) :: !viol
            | _ -> ());
           (match List.assoc_opt "id" fm with
            | Some i when not (is_id_shape i) ->
                viol := ("id not hex/dash shape: " ^ i) :: !viol
            | _ -> ()));
      if !viol <> [] then begin
        incr bad_files;
        total_viol := !total_viol + List.length !viol;
        List.iter (fun m -> Printf.printf "  [SCHEMA] %s: %s\n" name m) (List.rev !viol)
      end)
    files;
  Printf.printf
    "[zk_frontmatter_schema_enforcer] %d note(s) checked, %d non-conforming, %d violation(s)\n"
    total !bad_files !total_viol
