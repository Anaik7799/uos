(* Compression skill-marker units, reproduced faithfully from the frozen
   agent/context_compressor.py (read completely before writing; parity is
   measured by the compress.* scenarios, never assumed).

   Scope: the marker round-trip — emit, extract, reinject. The frozen
   reinjection routes its appended block through _redact_compaction_text,
   whose redaction is identity on text carrying no secrets; the scenario
   domain is clean text, so the redaction layer is disclosed as unmeasured
   rather than reproduced here. *)

let skill_pruned_marker_prefix = "[SKILL_PRUNED:"

(* _skill_pruned_marker: the ONE canonical string both the emit sites and the
   survival check share. *)
let skill_pruned_marker skill_name =
  skill_pruned_marker_prefix ^ " content lost in compression; reload with skill_view(name='"
  ^ skill_name ^ "')]"

let contains ~needle haystack =
  let n = String.length needle in
  let h = String.length haystack in
  let rec at i = i + n <= h && (String.sub haystack i n = needle || at (i + 1)) in
  n = 0 || at 0

(* _extract_pruned_skill_names: the frozen regex is
     escape(PREFIX) [^\]]*? reload with skill_view\(name='([^']+)'\)
   — after the prefix, a lazy run of non-']' characters, then the literal
   reload text, then the name (1+ non-quote), then ')'. Names dedupe in
   first-seen order. *)
let extract_pruned_skill_names text =
  let n = String.length text in
  let literal = "reload with skill_view(name='" in
  let names = ref [] in
  let add name = if not (List.mem name !names) then names := name :: !names in
  let starts_at prefix i =
    i + String.length prefix <= n && String.sub text i (String.length prefix) = prefix
  in
  let i = ref 0 in
  while !i < n do
    if starts_at skill_pruned_marker_prefix !i then begin
      (* lazy [^\]]*? then the literal: the FIRST occurrence of the literal
         before any ']' *)
      let scan_from = !i + String.length skill_pruned_marker_prefix in
      let rec hunt j =
        if j >= n || text.[j] = ']' then None
        else if starts_at literal j then Some (j + String.length literal)
        else hunt (j + 1)
      in
      (match hunt scan_from with
       | None -> incr i
       | Some name_start ->
           let rec close j =
             if j >= n then None else if text.[j] = '\'' then Some j else close (j + 1)
           in
           (match close name_start with
            | Some quote_end
              when quote_end > name_start && quote_end + 1 < n && text.[quote_end + 1] = ')' ->
                add (String.sub text name_start (quote_end - name_start));
                i := quote_end + 2
            | _ -> incr i))
    end
    else incr i
  done;
  List.rev !names

(* _reinject_pruned_skill_markers: for every name whose CANONICAL marker is
   absent from the summary, append the Pruned Skills section. Presence is a
   plain substring check against the same canonical string the emitter
   produces. *)
let pruned_skills_section_heading = "## Pruned Skills"

let reinject_pruned_skill_markers summary skill_names =
  if skill_names = [] then summary
  else
    let missing =
      List.filter
        (fun name -> not (contains ~needle:(skill_pruned_marker name) summary))
        skill_names
    in
    if missing = [] then summary
    else
      let lines = String.concat "\n" (List.map skill_pruned_marker missing) in
      summary ^ "\n\n" ^ pruned_skills_section_heading ^ "\n" ^ lines
      ^ "\n(The listed skills' instructions were pruned during context \
         compression. Reload with the skill_view call in each marker before \
         relying on that skill; one reload per skill is enough — ignore any \
         older markers for the same skill.)"
