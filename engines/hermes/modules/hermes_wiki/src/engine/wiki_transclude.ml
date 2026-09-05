(* HW.3.5.1 — note transclusion. See the mli: expansion is text-to-text
   at build time, termination is by construction, every failure is loud. *)

type outcome = {
  text : string;
  embedded : string list;
  cycles : string list;
  missing : string list;
  truncated : string list;
}

let default_depth = 3

let has_embed raw =
  let n = String.length raw in
  let rec go i = i + 3 <= n && (String.sub raw i 3 = "![[" || go (i + 1)) in
  go 0

(* Embeds are found on a FENCE-AWARE walk: `![[x]]` inside a code fence
   is an example of the grammar, not a use of it — the same distinction
   the reference scanner makes, and for the same reason. *)
let is_fence line =
  let t = String.trim line in
  String.length t >= 3 && String.sub t 0 3 = "```"

(* HW.3.5.2 — the block a `^id` addresses. Fence-aware, because a `^id`
   inside a code fence is an example. The marker is stripped: the id
   ADDRESSES the block, it is not part of what the block says. *)
let block ~id body =
  let want = "^" ^ id in
  let n = String.length want in
  let ends_with_marker t =
    let tn = String.length t in
    tn > n && String.sub t (tn - n) n = want && t.[tn - n - 1] = ' '
  in
  let rec go in_fence = function
    | [] -> None
    | line :: rest ->
        if is_fence line then go (not in_fence) rest
        else if in_fence then go in_fence rest
        else
          let t = String.trim line in
          if ends_with_marker t then Some (String.trim (String.sub t 0 (String.length t - n)))
          else go in_fence rest
  in
  go false (String.split_on_char '\n' body)

let expand ?(depth = default_depth) ~lookup ~self raw =
  let embedded = ref [] and cycles = ref [] and missing = ref [] and truncated = ref [] in
  (* the PATH, not a visited set: a diamond (two siblings embedding one
     target) is legitimate and expands twice; only a target already on
     the current path is a cycle *)
  let rec expand_text path level text =
    String.split_on_char '\n' text
    |> List.fold_left
         (fun (in_fence, acc) line ->
           if is_fence line then (not in_fence, line :: acc)
           else if in_fence then (in_fence, line :: acc)
           else (in_fence, expand_line path level line :: acc))
         (false, [])
    |> snd |> List.rev |> String.concat "\n"
  and expand_line path level line =
    let n = String.length line in
    let buf = Buffer.create (String.length line) in
    let i = ref 0 in
    (* CODE IS NOT PROSE, inline as well as fenced. Every document that
       DESCRIBES this grammar writes `![[x]]` in backticks; counting
       those as embeds reported 25 unresolvable targets in a corpus with
       no real embeds at all. Per-line pairing, the same bound the
       reference scanner documents. *)
    let in_code = ref false in
    while !i < n do
      if line.[!i] = '`' then (
        in_code := not !in_code;
        Buffer.add_char buf line.[!i];
        incr i)
      else if !in_code then (
        Buffer.add_char buf line.[!i];
        incr i)
      else if !i + 3 <= n && String.sub line !i 3 = "![[" then (
        let rec close k =
          if k + 1 < n then if line.[k] = ']' && line.[k + 1] = ']' then Some k else close (k + 1)
          else None
        in
        match close (!i + 3) with
        | None ->
            Buffer.add_char buf line.[!i];
            incr i
        | Some k ->
            let target = String.trim (String.sub line (!i + 3) (k - !i - 3)) in
            Buffer.add_string buf (expand_target path level target);
            i := k + 2)
      else (
        Buffer.add_char buf line.[!i];
        incr i)
    done;
    Buffer.contents buf
  and expand_target path level target =
    (* HW.3.5.2 — `Note#^id` addresses ONE block. Split first, so the
       page lookup never sees the fragment. *)
    let page_part, block_id =
      match String.index_opt target '#' with
      | Some i when i + 1 < String.length target && target.[i + 1] = '^' ->
          ( String.sub target 0 i,
            Some (String.sub target (i + 2) (String.length target - i - 2)) )
      | _ -> (target, None)
    in
    match (lookup page_part, block_id) with
    | Some (slug, body), Some id -> (
        match block ~id body with
        | Some text ->
            embedded := slug :: !embedded;
            (* a block embed cites the BLOCK, so its provenance names the
               block, not merely the page *)
            Printf.sprintf "%s\n\n*— embedded from [[%s#^%s]]*" text slug id
        | None ->
            (* NEVER widen to the whole page: a citation that quietly
               quotes more than it claimed is worse than one that fails *)
            missing :=
              Printf.sprintf "embed unresolved: ![[%s#^%s]] in %s (page exists, block does not)"
                page_part id self
              :: !missing;
            Printf.sprintf "**[embed unresolved: %s#^%s]**" page_part id)
    | _ -> expand_page path level page_part
  and expand_page path level target =
    match lookup target with
    | None ->
        missing := Printf.sprintf "embed unresolved: ![[%s]] in %s" target self :: !missing;
        Printf.sprintf "**[embed unresolved: %s]**" target
    | Some (slug, body) ->
        if List.mem slug path then begin
          cycles :=
            Printf.sprintf "embed cycle broken: %s -> %s (already on the path)"
              (String.concat " -> " (List.rev path)) slug
            :: !cycles;
          Printf.sprintf "**[embed cycle: %s]**" slug
        end
        else if level >= depth then begin
          truncated :=
            Printf.sprintf "embed depth %d reached at %s (bound REPORTED, not silent)" depth slug
            :: !truncated;
          Printf.sprintf "**[embed depth %d reached: %s]**" depth slug
        end
        else begin
          embedded := slug :: !embedded;
          (* the PROVENANCE CHIP: an embed always says where it came
             from, so a reader can reach the source that governs it *)
          Printf.sprintf "%s\n\n*— embedded from [[%s]]*"
            (expand_text (slug :: path) (level + 1) body)
            slug
        end
  in
  let text = if has_embed raw then expand_text [ self ] 0 raw else raw in
  { text;
    embedded = List.sort_uniq compare !embedded;
    cycles = List.sort_uniq compare !cycles;
    missing = List.sort_uniq compare !missing;
    truncated = List.sort_uniq compare !truncated }
