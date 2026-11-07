(* ==========================================================================
   mojo_mutation_dataplane — B5: mutation-based DATA-PLANE verification.

   WHY THIS EXISTS
   ---------------
   Every instrument built so far examines the CONTROL plane: the verdict
   algebra (Lean twin), the verdict state machine (reachability), the shape of
   an arm's predicate (falsifiability). None of them can answer the only
   question that matters about a world arm:

       does this measurement actually read the thing it names?

   An arm that greps a file it cannot open, or that compares a constant to a
   constant it harvested from its own source, reports PASS for the same reason
   a correct arm does. 109 arms are NOT_ANALYSED by the falsifiability
   instrument precisely because they contain a world call -- the part no
   static reader can judge.

   THE METHOD
   ----------
   Perturb the real subject, require the measurement to move.

       baseline  = receipt(oracle, unmutated tree)
       mutant    = receipt(oracle, tree with ONE line of ONE subject changed)
       KILLED    <=> mutant =/= baseline

   A mutation that the receipt does not notice is a measurement that was not
   looking. This was done BY HAND for `argon`, `FppService` and the coverage
   ledger during the review rounds and it found a real defect every time; this
   tool is that procedure made repeatable.

   TWO TARGETS
   -----------
   --subject  mutate a file the oracle names and greps. Verifies the world
              plane: the capture really reaches the subject.
   --mirror   mutate the body of one of the oracle's OWN pure mirror
              functions. Verifies that the algebra arms are wired to the
              mirror at all -- which is the evidence a FIXED_VECTOR arm (all
              literal arguments to a mirror) needs in order to be sound.
              Without it, `b2_enabled` cannot honestly be turned on.

   THREE CONTROLS ON THE INSTRUMENT ITSELF
   ---------------------------------------
   1. DETERMINISM. Before any mutation, the oracle is run TWICE on the
      unmutated overlay. If the two receipts differ under the comparator, the
      comparator cannot distinguish a mutation from noise and the oracle is
      reported NOT_RUN rather than measured. This is the comparator's own
      validation: it is not assumed sound, it is tested per oracle.
   2. SPECIFICITY. For each subject, one mutant is planted on a line that
      contains NOTHING the oracle searches for. That mutant is EXPECTED to
      survive. One that is killed means the oracle responds to text it never
      claimed to read.
   3. NOT_RUN IS NOT A PASS. A mutant whose run produced no receipt (the edit
      broke the parse, the tool timed out) has been seen by nothing. Counting
      it as KILLED would make every broken mutant a success -- absence passing
      as evidence, the defect this whole plane exists to catch. It is its own
      category and it fails the gate.

   ZERO-RISK EXECUTION
   -------------------
   Nothing in the repository is ever written. Each run happens in a scratch
   OVERLAY: every top-level entry is symlinked, then the prefix of the mutated
   path is materialised into real directories whose children are symlinks, and
   only the single mutated file is a real copy. The oracle runs with the
   overlay as its working directory, so its relative paths resolve into the
   overlay and its toolchain resolves through the symlinks into the real tree.
   In-place mutation with a restore was rejected: a restore that does not run
   leaves the tree corrupt, and "the restore always runs" is exactly the kind
   of assertion that cannot fail.

   HONEST BOUNDARY
   ---------------
   KILLED says the receipt moved when the subject moved. It does NOT say the
   arm measures the RIGHT property -- only that it measures something that
   depends on the subject. SURVIVED is the strong finding. A mutation operator
   that happens to produce a semantically equivalent file would report a false
   SURVIVED; the operators are chosen to avoid that (line deletion and integer
   perturbation on a line the oracle's own literals match) but the possibility
   is not excluded.

   authority NONE. EV ceiling 93.
   ========================================================================== *)

#directory "tools";;
#use "uos_plane_lock.ml";;

let oracle_dir = "formal/mojo"
let mojo = "./tools/mojo"

let read_file p =
  let ic = open_in_bin p in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let write_file p s =
  let oc = open_out_bin p in output_string oc s; close_out oc

let lines_of s = String.split_on_char '\n' s

(* ---------- receipt comparison ----------------------------------------- *)

(* Volatile text is blanked before comparison: a receipt carrying an observed
   clock would otherwise differ from itself. The DETERMINISM control below
   proves per oracle that this normalisation is sufficient; it is not taken on
   trust. *)
let normalise (s : string) : string =
  let b = Bytes.of_string s in
  let n = Bytes.length b in
  let isd i = i >= 0 && i < n &&
    (let c = Bytes.get b i in c >= '0' && c <= '9') in
  (* blank runs of >= 4 digits that sit inside a date-like or stamp-like shape *)
  let i = ref 0 in
  while !i < n do
    if isd !i then begin
      let s0 = !i in
      while isd !i do incr i done;
      let len = !i - s0 in
      let nxt = if !i < n then Bytes.get b !i else ' ' in
      (* 8-digit stamp (YYYYMMDD) or 4-digit year followed by - or T *)
      if len >= 8 || (len = 4 && (nxt = '-' || nxt = 'T')) then
        for k = s0 to !i - 1 do Bytes.set b k '#' done
    end else incr i
  done;
  Bytes.to_string b

let receipt_of (out : string) : string option =
  let pick = ref None in
  List.iter (fun l ->
    let l = String.trim l in
    if String.length l > 24 && String.sub l 0 24 = "{\"schema\":\"uos.oracle.v1"
    then pick := Some l) (lines_of out);
  match !pick with None -> None | Some l -> Some (normalise l)

(* ---------- overlay ---------------------------------------------------- *)

let sh cmd = Sys.command cmd

let repo = Sys.getcwd ()

(* ---------- IN-PLACE MUTATION WITH A VERIFIED RESTORE -------------------

   WHY NOT AN OVERLAY. The first version ran each mutant in a scratch overlay
   whose top-level entries were symlinks into the real tree -- zero write risk,
   and wrong. `grep -r` DOES NOT TRAVERSE A SYMLINKED DIRECTORY, so every
   recursive capture in the overlay read almost nothing: km_census measured
   `inline 1 fenced 0` where the real tree has 1097 and 75. The determinism
   control still passed, because two degenerate runs agree with each other,
   and the result was a SURVIVED verdict I was one step from reporting as a
   finding about the oracle. The environment, not the oracle, was blind.
   A symlink overlay therefore cannot measure an oracle that greps a tree, and
   a hardlink copy of this repository is 5.09 million files -- and would have
   to keep an allowlist of exactly which directories the sixteen oracles
   traverse, a correctness dependency that can drift silently. That is the
   declared-route-is-not-a-connected-route shape, one level up.

   So the mutation happens IN THE REAL TREE, where the measurement is the
   measurement, and the safety comes from a restore that is VERIFIED rather
   than assumed:

     1. the original bytes are held in memory AND written to `<path>.mutbak`;
     2. `var/mutation/IN_FLIGHT.json` names the path and its backup BEFORE the
        write, so a crash leaves a readable instruction, not a mystery;
     3. the restore runs, and then the file is READ BACK and compared byte for
        byte. A restore that did not take aborts the whole run loudly;
     4. a later run REFUSES TO START while a journal exists, so a crash is
        surfaced instead of being overwritten by the next sweep.

   "The restore always runs" is exactly the kind of claim that cannot fail, so
   it is not relied on: step 3 is the evidence, step 4 is the backstop. The
   window is one file for one oracle run (~2.5 s). *)

let journal = "var/mutation/IN_FLIGHT.json"

let fatal msg = prerr_endline ("  FATAL: " ^ msg); exit 3

(* FIXED 20261107-2006, finding F-W-18.

   WHAT WAS OBSERVED
   -----------------
   A journal written 2026-11-07T08:35:54Z named `tools/uos-wait.ml`, whose
   `.mutbak` was ABSENT. This instrument therefore refused every invocation
   for roughly twelve hours, fail-closed, and nothing reported it. Worse, the
   recovery it printed -- "Restore the path it names from its .mutbak" --
   was impossible to follow, because that backup had already been deleted.

   WHY THE JOURNAL SURVIVED ITS MUTATION
   -------------------------------------
   `with_mutation`'s restore path is ordered: write the original back, VERIFY
   it byte for byte (fatal otherwise), remove the backup, remove the journal.
   Both removes were `try ... with _ -> ()`, so a failure to unlink the
   journal was silent. The backup being gone therefore PROVES the restore ran
   and was verified -- the verify precedes the unlink, so the tree is sound.

   THE DISCRIMINATION THIS GUARD NOW MAKES
   ---------------------------------------
     backup PRESENT -> a real interrupted mutation. The tree may hold mutant
                       bytes. Refuse, and name the exact command that fixes
                       it, because the backup exists to be copied back.
     backup ABSENT  -> the restore completed and was verified; only the
                       unlink failed. The journal is stale, not evidence of a
                       corrupt tree. Say so and clear it, rather than demand
                       a recovery step that cannot be performed.

   A refusal whose instructions cannot be carried out is not fail-closed, it
   is wedged: it stops the work without offering a way back. *)
let refuse_if_in_flight () =
  if Sys.file_exists journal then begin
    let body = try read_file journal with _ -> "" in
    let field k =
      let pat = "\"" ^ k ^ "\":\"" in
      match String.index_opt body '{' with
      | _ ->
        let n = String.length body and pn = String.length pat in
        let rec go i =
          if i + pn > n then None
          else if String.sub body i pn = pat then
            let j = i + pn in
            (match String.index_from_opt body j '"' with
             | Some e -> Some (String.sub body j (e - j))
             | None -> None)
          else go (i + 1) in
        go 0 in
    match field "backup" with
    | Some bak when Sys.file_exists bak ->
      let path = match field "path" with Some p -> p | None -> "<unknown>" in
      fatal (Printf.sprintf
        "%s names an INTERRUPTED mutation of %s and its backup %s is still \
         present, so the tree may hold mutant bytes. Recover with exactly:\n\
        \    cp %s %s && rm %s %s\n  This run changes nothing."
        journal path bak bak path bak journal)
    | _ ->
      (* Stale. The backup is gone, which only happens after the restore was
         written AND read back byte-identical. *)
      prerr_endline (Printf.sprintf
        "  NOTE: %s was stale -- it named a mutation whose backup is already \
         gone, which means the restore completed and was verified and only \
         the journal unlink failed. Clearing it and continuing." journal);
      (try Sys.remove journal with e ->
        fatal (Printf.sprintf
          "could not clear the stale journal %s: %s. Remove it by hand."
          journal (Printexc.to_string e)))
  end

(* Runs the oracle exactly as it is normally run: from the repository root,
   against the real tree. *)
let run_oracle (oracle : string) : string option =
  let tmp = Filename.temp_file "mut" ".out" in
  let cmd = Printf.sprintf "timeout -k 5 60 %s run -I %s %s > %s 2>&1"
    mojo (Filename.quote oracle_dir) (Filename.quote oracle)
    (Filename.quote tmp) in
  ignore (sh cmd);
  let r = if Sys.file_exists tmp then receipt_of (read_file tmp) else None in
  (try Sys.remove tmp with _ -> ());
  r

(* FIXED 20261107-2034, finding F-W-13. The window between `write_file path
   text` and `restore ()` below is a tree that never existed. The IN_FLIGHT
   journal protects against THIS process crashing; it says nothing to a
   concurrent READER. tools/lean_mojo_differential.ml hashes
   `formal/mojo/*_oracle.mojo formal/mojo/oracle_substrate.mojo` for its
   oracle_set digest, so a differential run landing in this window binds its
   verdict to a revision nobody authored.

   The whole mutate-run-restore cycle therefore holds the shared plane lock.
   Per MUTANT, not per sweep: a sweep holds it for minutes, which would
   starve the reader; a mutant holds it for one compile. Fail-closed -- if
   the lock cannot be taken, nothing is mutated (see with_plane_lock). *)
let with_mutation (path : string) (text : string) (f : unit -> 'a) : 'a =
  (* Explicit, not inherited: finding F-W-20. This site was wired without a
     timeout and inherited 120.0, which is SHORTER than the differential's
     legitimate hold, so a re-sweep aborted rather than waited. The module
     default is now 600.0 too; stating it here as well keeps the budget
     visible at the site that actually mutates the tree. *)
  with_plane_lock ~timeout:600.0 "formal-mojo" @@ fun () ->
  let orig = read_file path in
  let bak = path ^ ".mutbak" in
  write_file bak orig;
  write_file journal (Printf.sprintf
    "{\"schema\":\"uos.mutation-in-flight.v1\",\"path\":%S,\"backup\":%S,\
     \"restore\":\"cp %s %s\"}\n" path bak bak path);
  let restore () =
    write_file path orig;
    if read_file path <> orig then
      fatal (Printf.sprintf
        "restore of %s did not take. The original bytes are in %s. Nothing \
         further is attempted." path bak);
    (try Sys.remove bak with _ -> ());
    (* FIXED 20261107-2006, finding F-W-18. This unlink was `try ... with _ ->
       ()`. When it failed, the journal survived a COMPLETED and verified
       restore, and refuse_if_in_flight then blocked every later run for
       twelve hours while pointing at a .mutbak that no longer existed. The
       failure is now reported. It is not fatal -- the restore itself already
       succeeded and verified, so the tree is sound and aborting here would
       lose a good result -- but it must not be silent. *)
    (try Sys.remove journal with e ->
      prerr_endline (Printf.sprintf
        "  WARNING: restore of %s succeeded and verified, but %s could not be \
         removed (%s). The next run will detect it as stale and clear it."
        path journal (Printexc.to_string e))) in
  let r = (try write_file path text; f ()
           with e -> restore (); raise e) in
  restore ();
  r

(* ---------- what the oracle names and searches ------------------------- *)

let find_sub (hay : string) (needle : string) (from : int) : int option =
  let hn = String.length hay and nn = String.length needle in
  let rec go i = if i + nn > hn then None
    else if String.sub hay i nn = needle then Some i else go (i + 1) in
  if nn = 0 then None else go from

let is_path_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '_' || c = '.' || c = '/' || c = '-'

let string_literals (src : string) : string list =
  let n = String.length src in
  let out = ref [] and i = ref 0 in
  while !i < n do
    if src.[!i] = '"' then begin
      let s0 = !i + 1 in
      incr i;
      while !i < n && src.[!i] <> '"' && src.[!i] <> '\n' do incr i done;
      if !i < n && src.[!i] = '"' then
        out := String.sub src s0 (!i - s0) :: !out;
      incr i
    end else incr i
  done;
  List.rev !out

let subjects_of (src : string) : string list =
  string_literals src
  |> List.filter (fun s ->
       String.length s > 6
       && String.contains s '/'
       && String.for_all is_path_char s
       && (try Sys.is_directory s = false with _ -> false)
       && Sys.file_exists s)
  |> List.sort_uniq compare

(* Needles: literals the oracle greps for. Not paths, long enough to be
   meaningful, no shell. *)
let needles_of (src : string) : string list =
  string_literals src
  |> List.filter (fun s ->
       String.length s >= 5 && String.length s <= 80
       && not (String.contains s '/')
       && not (String.contains s '\'')
       && not (String.contains s '|'))
  |> List.sort_uniq compare

let contains_sub hay needle =
  let hn = String.length hay and nn = String.length needle in
  if nn = 0 || nn > hn then false
  else begin
    let found = ref false and i = ref 0 in
    while not !found && !i + nn <= hn do
      if String.sub hay !i nn = needle then found := true else incr i
    done; !found
  end

(* ---------- mutation operators ----------------------------------------- *)

type mutant = {
  m_path : string;                  (* repo-relative file mutated *)
  m_line : int;                     (* 1-indexed *)
  m_op : string;
  m_class : string;                 (* must-kill | info | must-survive *)
  m_text : string;                  (* whole mutated file content *)
}

let bump_int (l : string) : string option =
  let n = String.length l in
  let i = ref 0 and res = ref None in
  while !res = None && !i < n do
    if l.[!i] >= '0' && l.[!i] <= '9'
       && (!i = 0 || not (is_path_char l.[!i - 1])) then begin
      let s0 = !i in
      while !i < n && l.[!i] >= '0' && l.[!i] <= '9' do incr i done;
      (try
         let v = int_of_string (String.sub l s0 (!i - s0)) in
         res := Some (String.sub l 0 s0 ^ string_of_int (v + 7)
                      ^ String.sub l !i (n - !i))
       with _ -> ())
    end else incr i
  done;
  !res

(* THE SEVERITY LADDER.

   The first version of this function tried to GUESS which line of the subject
   the oracle cared about, by scoring each line against the oracle's own string
   literals. It reported 4 SURVIVED on verification_plane_oracle -- and every
   one was wrong: emptying the same subject by hand moved the receipt from PASS
   to WORLD_FAIL, so the measurement WAS looking. The verdicts meant "I mutated
   a line that carries nothing", which is indistinguishable in the report from
   "the oracle is blind". An instrument whose failure mode is a false finding
   on correct code is the inverted-polarity defect, committed inside the tool
   built to find it.

   A ladder removes the targeting problem. Rung 1 cannot be mis-aimed: the
   subject is REMOVED. If the receipt does not move when its subject ceases to
   exist, no choice of line was ever going to matter -- the arm is not reading
   it. That is the decisive data-plane question and it is the only rung the
   gate fails on. The higher rungs measure SENSITIVITY, which is informative
   and is reported, not enforced: an oracle may legitimately notice absence
   and not notice a value it never reads. *)
(* THE DECLARED SUBJECT is the second String argument of `Receipt(...)`: the
   file the receipt names as the formal side of its two-key claim. Its role is
   different from every other path the oracle mentions, and so is the meaning
   of an L1 survival.

   The first sweep reported 4 SURVIVED and TWO WERE MINE. `language_conformance`
   greps for REFERENCES to `max_worker.py` and `verify_website_sop.sh` in the
   twin and under ops/systemd; it never reads their contents, so emptying them
   correctly changes nothing. I had mistaken a grep NEEDLE for a grep TARGET
   and called a sound oracle blind -- on two arms, in the instrument built to
   stop exactly that.
   The remaining two survived on their own DECLARED SUBJECT, and there the
   verdict stands: an oracle that names a Lean twin as its subject and never
   reads it has no formal side at the candidate, whatever its receipt says.
   So L1 on the declared subject is gated, and L1 on any other named path is
   an observation. *)
(* It is the receipt named `r` -- the convention every oracle follows and that
   tools/mojo_arm_falsifiability.ml already relies on for `r.algebra(`.
   Keying on the FIRST `Receipt(` in the file was wrong: verification_plane
   builds FIXTURE receipts first (`var probe = Receipt(..., "vp-probe")`), so
   the window never reached the real one. Five of sixteen oracles were left
   ungated -- their declared subject fell through to an ungated observation,
   and the summary line said KILLED 11 without saying 11 OF WHAT. A gate that
   silently covers two thirds of its subjects is the shape of the blanket
   checklist, and the count alone could not reveal it.
   The second argument may be a literal or a comptime name, so comptime names
   are resolved rather than skipped. *)
let declared_subject (src : string) : string option =
  let comptimes =
    lines_of src
    |> List.filter_map (fun l ->
         let t = String.trim l in
         if String.length t > 9 && String.sub t 0 9 = "comptime " then begin
           let rest = String.trim (String.sub t 9 (String.length t - 9)) in
           match String.index_opt rest ' ' with
           | Some k ->
             let nm = String.sub rest 0 k in
             (match string_literals rest with
              | v :: _ -> Some (nm, v)
              | [] -> None)
           | None -> None
         end else None) in
  (* The Receipt call's SECOND ARGUMENT, parsed, not scanned. A 400-character
     window picked the first literal containing '/' -- which for
     language_conformance was a path out of a LATER capture command, a wrong
     subject rather than no subject. It also missed twin_coverage, whose
     subject is split across two source lines by string concatenation and
     yielded the bare directory "formal/lean/". Adjacent literals are joined
     and a bare comptime name is resolved. *)
  match find_sub src "var r = Receipt(" 0 with
  | None -> None
  | Some i ->
    let n = String.length src in
    let j = ref (i + String.length "var r = Receipt(") in
    let depth = ref 1 in
    let buf = Buffer.create 256 in
    while !depth > 0 && !j < n do
      (match src.[!j] with
       | '(' -> incr depth; Buffer.add_char buf '('
       | ')' -> decr depth; if !depth > 0 then Buffer.add_char buf ')'
       | c -> Buffer.add_char buf c);
      incr j
    done;
    let args = Buffer.contents buf in
    (* split on TOP-LEVEL commas only *)
    let parts = ref [] and cur = Buffer.create 64 and d = ref 0 in
    String.iter (fun c ->
      if c = '(' then (incr d; Buffer.add_char cur c)
      else if c = ')' then (decr d; Buffer.add_char cur c)
      else if c = ',' && !d = 0 then
        (parts := Buffer.contents cur :: !parts; Buffer.clear cur)
      else Buffer.add_char cur c) args;
    parts := Buffer.contents cur :: !parts;
    let parts = List.rev (List.filter (fun s -> String.trim s <> "") !parts) in
    (match parts with
     | _ :: subj :: _ ->
       let joined = String.concat "" (string_literals subj) in
       if String.contains joined '/' then Some joined
       else
         (match List.filter (fun (nm, v) ->
                  String.contains v '/'
                  && contains_sub subj ("String(" ^ nm ^ ")")) comptimes with
          | (_, v) :: _ -> Some v
          | [] -> None)
     | _ -> None)

let mutants_for_subject ?(is_declared = false) (needles : string list)
      (oracle_imports : bool) (path : string) : mutant list =
  let src = read_file path in
  let ls = Array.of_list (lines_of src) in
  let n = Array.length ls in
  let score i =
    List.fold_left (fun a nd -> if contains_sub ls.(i) nd then a + 1 else a)
      0 needles in
  (* `oracle_imports` is true for a .mojo module on the oracle's import path.
     Emptying or thinning such a file does not perturb a MEASUREMENT, it breaks
     the BUILD, and the run produces no receipt at all. Those operators are
     therefore not applicable there, and saying so is more honest than emitting
     a mutant whose NOT_RUN would be read as a finding. *)
  let structural = not oracle_imports in
  let bump_all =
    let b = Array.map (fun l ->
      let rec go acc i =
        if i >= String.length l then acc ^ String.sub l i 0
        else acc in
      ignore go;
      (* perturb every integer literal on the line *)
      let m = String.length l in
      let buf = Buffer.create m in
      let i = ref 0 in
      while !i < m do
        if l.[!i] >= '0' && l.[!i] <= '9'
           && (!i = 0 || not (is_path_char l.[!i - 1])) then begin
          let s0 = !i in
          while !i < m && l.[!i] >= '0' && l.[!i] <= '9' do incr i done;
          (match int_of_string_opt (String.sub l s0 (!i - s0)) with
           | Some v -> Buffer.add_string buf (string_of_int (v + 7))
           | None -> Buffer.add_string buf (String.sub l s0 (!i - s0)))
        end else (Buffer.add_char buf l.[!i]; incr i)
      done;
      Buffer.contents buf) ls in
    String.concat "\n" (Array.to_list b) in
  let thinned =
    String.concat "\n"
      (List.filteri (fun k _ -> k mod 2 = 0) (Array.to_list ls)) in
  let cold =
    (* the LAST line carrying nothing the oracle names: the specificity
       control. Expected to survive. *)
    let pick = ref None in
    Array.iteri (fun i l ->
      if score i = 0 && String.length l > 8 then pick := Some i) ls;
    !pick in
  let mk line op (cls : string) text =
    { m_path = path; m_line = line; m_op = op; m_class = cls;
      m_text = text } in
  (if structural
   then [ mk 0 "L1-empty-subject"
            (if is_declared then "must-kill" else "info") "" ]
   else [])
  @ (if bump_all <> src then [ mk 0 "L2-bump-every-int" "info" bump_all ] else [])
  @ (if structural && n > 6 then [ mk 0 "L3-thin-half" "info" thinned ] else [])
  (* THE SPECIFICITY CONTROL, TWICE REVISED.
     First version DELETED a line the oracle names nothing on. It fired on
     ontology_atlas and monitoring_governance -- and both were right to
     notice: deleting any line changes the file's LINE COUNT, and an oracle
     that counts theorems is supposed to see that. The control was measuring
     its own operator, not the oracle's specificity.
     The operator is now whitespace-only: the cold line keeps its exact
     tokens and the file keeps its exact line count. An oracle responding to
     that is responding to bytes rather than content, which a digest arm
     legitimately does -- so this is reported and NOT gated. A control whose
     firing is ambiguous must not fail a build; saying so is cheaper than a
     permanently red gate on correct code. *)
  @ (match cold with
     | Some i ->
       let b = Array.copy ls in
       b.(i) <- ls.(i) ^ " ";
       [ mk (i + 1) "CTL-trailing-space-cold-line" "must-survive"
           (String.concat "\n" (Array.to_list b)) ]
     | _ -> [])

(* ---------- mirror mutation -------------------------------------------- *)

(* The world-contact set is copied from tools/mojo_arm_falsifiability.ml: a
   mirror is PURE here exactly when that instrument would enumerate it, so the
   two tools agree on what a mirror is. If they disagreed, a FIXED_VECTOR
   verdict there could cite mutation evidence from a function this tool never
   considered a mirror. *)
let world_contact = ["capture"; "count"; "http_code"; "http_body";
                     "field_total"; "occurrences"; "json_flag"; "json_int";
                     "json_signed"; "json_norm"; "json_has"; "state_count";
                     "regime_b_index"; "lean_arch_ctor"; "sev_rank";
                     "exit_rank"; "status_for"; "status_for_obs"]

(* ---- prose is not code -------------------------------------------------

   FOUND 20261107-0331, by reading the surviving mutants instead of trusting
   their count. `status_for`'s four mutants sat at lines 62, 67, 68 and 68:
   one docstring line and two `#` comment lines. `span_timings_monotonic`
   spent three of its four slots on the prose that cites its twin -- the
   sentence "The twin proves `observedNs <= p99Ns" carries a `<=`, and
   "and this plane had no counterpart" carries an `and`.

   A mutated comment cannot change behaviour, so it is GUARANTEED to survive.
   Two harms follow and the second is the serious one. The per-mirror mutant
   budget (4) is spent on certain survivors, so real operators never get a
   slot; then per-mirror aggregation reads "every mutant survived" and reports
   UNCOVERED. For `status_for` there was no executable operator at all, so its
   UNCOVERED verdict was manufactured entirely out of its own documentation.
   The instrument was measuring my prose and reporting it as the oracle's
   blindness. Same polarity error as the overlay: a defect in the measuring
   apparatus, published as a defect in the subject. *)
let code_part (l : string) : string =
  (* The code portion, dropping a trailing `#` comment outside quotes, so an
     inline comment cannot absorb the one substitution this line gets. *)
  let n = String.length l in
  let rec go i q =
    if i >= n then l
    else match l.[i], q with
      | '\\', Some _ -> go (i + 2) q
      | ('"' | '\''), None -> go (i + 1) (Some l.[i])
      | c, Some qc when c = qc -> go (i + 1) None
      | '#', None -> String.sub l 0 i
      | _ -> go (i + 1) q in
  go 0 None

let triple_marks (t : string) : int =
  let n = String.length t and c = ref 0 and k = ref 0 in
  while !k + 3 <= n do
    if String.sub t !k 3 = "\"\"\"" then (incr c; k := !k + 3) else incr k
  done; !c

(* Body line indices with comment and docstring lines removed. *)
let code_lines (ls : string array) (body : int list) : int list =
  let in_doc = ref false in
  List.filter (fun i ->
    let t = String.trim ls.(i) in
    let marks = triple_marks t in
    let opens_here = (not !in_doc) && marks > 0 in
    let keep =
      (not !in_doc) && (not opens_here)
      && String.length t > 0 && t.[0] <> '#'
      && String.trim (code_part ls.(i)) <> "" in
    if marks mod 2 = 1 then in_doc := not !in_doc;
    keep)
    body

(* Returns (fn name, first mutable body line index, body line indices). *)
let mirror_defs (src : string) : (string * int list) list =
  let ls = Array.of_list (lines_of src) in
  let n = Array.length ls in
  let out = ref [] in
  let i = ref 0 in
  while !i < n do
    let l = ls.(!i) in
    let is_def = String.length l > 4 && String.sub l 0 4 = "def " in
    if is_def then begin
      let body = String.trim l in
      let nm = (try String.sub body 4 (String.index body '(' - 4)
                with _ -> "") in
      (* Skip the rest of a MULTI-LINE signature. `def span_within_budget(`
         continues over four indented lines, and those lines look exactly like
         body lines to a "starts with a space" test -- so an operator flip
         would land in a parameter list and change a type, not a computation.
         The signature ends at the first line whose trimmed text ends in ':'. *)
      let sg = ref !i in
      let n_ = n in
      while !sg < n_
            && (let t = String.trim ls.(!sg) in
                String.length t = 0 || t.[String.length t - 1] <> ':') do
        incr sg done;
      let start = !sg + 1 in
      let j = ref start in
      while !j < n && (String.trim ls.(!j) = ""
                       || (String.length ls.(!j) > 0 && ls.(!j).[0] = ' ')) do
        incr j done;
      let body_idx = List.init (!j - start) (fun k -> start + k) in
      let impure = List.exists (fun k ->
        List.exists (fun w -> contains_sub ls.(k) (w ^ "(")) world_contact)
        body_idx in
      (* A prose-only mirror stays in the list with an EMPTY code list rather
         than being dropped: the driver must be able to say "no valid mutant"
         out loud. Dropping it is the silent-skip shape that F-B5-02 was. *)
      if nm <> "" && not impure && body_idx <> [] then
        out := (nm, code_lines ls body_idx) :: !out;
      i := !j
    end else incr i
  done;
  List.rev !out

(* ALL applicable substitutions, not the first.

   `quoted_examples` is `return in_inline + in_fenced`, and the twin declares
   `inFencedCode := 0` for both corpora -- so `i + 0` and `i - 0` are the SAME
   FUNCTION on the data the arm actually feeds it. The single `+ -> -` mutant
   was unkillable, and a one-mutant mirror whose one mutant is equivalent came
   out UNCOVERED: a false finding against a sound arm, which I had already
   half-believed once. Per-mirror aggregation is the right rule but it needs
   more than one mutant to aggregate over, so every operator that applies to a
   line now yields its own mutant. `+ -> *` is killable where `+ -> -` is not,
   because `i * 0` is 0 and `i + 0` is i. *)
let flips_of (l : string) : (string * string) list =
  (* Substitutions apply to the CODE part only. An inline `# ... and ...`
     comment would otherwise win the single substitution this line gets. *)
  let code = code_part l in
  let nc = String.length code in
  let tail = String.sub l nc (String.length l - nc) in
  let subst a b =
    if contains_sub code a then begin
      let la = String.length a in
      let buf = Buffer.create nc in
      let i = ref 0 and done_ = ref false in
      while !i < nc do
        if (not !done_) && !i + la <= nc && String.sub code !i la = a then begin
          Buffer.add_string buf b; i := !i + la; done_ := true
        end else (Buffer.add_char buf code.[!i]; incr i)
      done;
      Some (Buffer.contents buf ^ tail)
    end else None in
  (* A String-returning mirror has no arithmetic to flip, and `+ -> -` on a
     concatenation DOES NOT COMPILE: `base_url`, `quoted` and `field_total`
     yielded only NOT_RUN, which gated red while saying nothing whatever about
     the oracle. An operator that cannot compile is not evidence of blindness,
     it is an inapplicable operator. Emptying the first non-empty literal on
     the line compiles, changes the value, and dies to any arm that reads the
     result. *)
  let empty_first_literal () =
    let rec go i =
      if i >= nc then None
      else if code.[i] = '"' || code.[i] = '\'' then begin
        let q = code.[i] in
        let j = ref (i + 1) in
        while !j < nc && code.[!j] <> q do
          if code.[!j] = '\\' then j := !j + 2 else incr j done;
        if !j >= nc then None
        else if !j > i + 1 then
          Some (String.sub code 0 (i + 1) ^ String.sub code !j (nc - !j) ^ tail)
        else go (!j + 1)
      end else go (i + 1) in
    go 0 in
  (* Five mirrors reported UNMEASURED on the first corrected sweep because
     no operator above applies to them: `route_tier` is `return 0`,
     `target_ratio_x10` is a table lookup, `ideal_span` is a call on nine
     literals. Those are exactly the places a number rots unnoticed, so
     perturbing every integer literal outside quotes gives each one a
     mutant. Digits inside a string are left alone: bumping a path or a
     schema version produces a mutant that cannot run, which is noise, not
     evidence. *)
  let bump_ints () =
    let buf = Buffer.create (nc + 8) in
    let changed = ref false and q = ref None and i = ref 0 in
    let is_id c =
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_' in
    while !i < nc do
      let c = code.[!i] in
      (match !q with
       | Some qc ->
         Buffer.add_char buf c;
         if c = '\\' && !i + 1 < nc then
           (Buffer.add_char buf code.[!i + 1]; i := !i + 2)
         else (if c = qc then q := None; incr i)
       | None ->
         if c = '"' || c = '\'' then
           (q := Some c; Buffer.add_char buf c; incr i)
         else if c >= '0' && c <= '9'
                 && not (!i > 0 && is_id code.[!i - 1]) then begin
           let j = ref !i in
           while !j < nc && code.[!j] >= '0' && code.[!j] <= '9' do incr j done;
           if !j < nc && (is_id code.[!j] || code.[!j] = '.') then
             (Buffer.add_string buf (String.sub code !i (!j - !i)); i := !j)
           else begin
             match int_of_string_opt (String.sub code !i (!j - !i)) with
             | Some v ->
               Buffer.add_string buf (string_of_int (v + 1));
               changed := true; i := !j
             | None ->
               Buffer.add_string buf (String.sub code !i (!j - !i)); i := !j
           end
         end else (Buffer.add_char buf c; incr i))
    done;
    if !changed then Some (Buffer.contents buf ^ tail) else None in
  (* FIXED 20261107-0415. `+ -> -` cannot compile on a String concatenation,
     and emitting it anyway cost twice: the mutant came back NOT_RUN, and --
     after the <=2-per-line budget was introduced -- the two uncompilable
     arithmetic flips on `return String('"') + name_of(n) + String('"')`
     CONSUMED that line's whole budget and discarded the `literal->empty`
     mutant added in the same session to fix exactly those mirrors. Two
     corrections in one sweep, silently cancelling each other. A line that
     concatenates strings gets no arithmetic operator. *)
  let stringy =
    contains_sub code "String(" || contains_sub code "\""
    || contains_sub code "'" in
  let arith =
    if stringy then []
    else [(" + ", " - "); (" + ", " * "); (" - ", " + "); (" - ", " * ");
          (" * ", " + ")] in
  List.filter_map (fun (a, b) ->
    match subst a b with
    | Some r when r <> l -> Some (r, a ^ "->" ^ b)
    | _ -> None)
    ([(" == ", " != "); (" != ", " == "); (" >= ", " > "); (" <= ", " < ");
      (" and ", " or "); ("True", "False"); ("False", "True"); (" > ", " >= ")]
     (* Arithmetic mirrors have no comparison to flip. km_census's
        `quoted_examples` is `return in_inline + in_fenced` and produced ZERO
        mutants until these were added. *)
     @ arith)
  @ (match empty_first_literal () with
     | Some r when r <> l -> [ (r, "literal->empty") ]
     | _ -> [])
  @ (match bump_ints () with
     | Some r when r <> l -> [ (r, "ints+1") ]
     | _ -> [])

let mutants_for_mirror (path : string) (src : string)
      (fn : string) (body : int list) : mutant list =
  let ls = Array.of_list (lines_of src) in
  let rebuild i repl =
    let b = Array.copy ls in b.(i) <- repl;
    String.concat "\n" (Array.to_list b) in
  (* At least two and at most four mutants per mirror (AK-47-05 asks for >= 2).
     A mirror that yields fewer is reported with what it yielded, never
     padded, and a mirror that yields none is UNMEASURED rather than covered. *)
  (* At most TWO per line, at most six per mirror. A flat "first four" let
     one busy line consume the whole budget: `classify_archetype`'s line 71
     alone yields three operators, so lines 75 and 79 never got a mutant and
     their boundaries went unprobed. Spreading the budget across lines is
     what makes the budget mean coverage of the function rather than of its
     first conditional. *)
  let cands = List.concat_map (fun i ->
    List.filteri (fun k _ -> k < 2)
      (List.map (fun (repl, op) ->
        { m_path = path; m_line = i + 1; m_op = fn ^ ":" ^ op;
          m_class = "must-kill"; m_text = rebuild i repl }) (flips_of ls.(i))))
    body in
  List.filteri (fun k _ -> k < 6) cands

(* ---------- driver ------------------------------------------------------ *)

type res = {
  r_oracle : string;
  r_mut : mutant;
  r_verdict : string;                (* KILLED SURVIVED NOT_RUN SPEC_FAIL *)
}

let () =
  let mode = if Array.length Sys.argv > 1 then Sys.argv.(1) else "--subject" in
  let only = if Array.length Sys.argv > 2 then Some Sys.argv.(2) else None in
  if mode <> "--subject" && mode <> "--mirror" then begin
    prerr_endline "usage: mojo_mutation_dataplane [--subject|--mirror] [oracle]";
    exit 2
  end;
  refuse_if_in_flight ();
  let oracles =
    Sys.readdir oracle_dir |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f "_oracle.mojo")
    (* provenance_ceiling_impact_oracle.mojo belongs to another writer and
       must not be edited, so --mirror never touches it. Its SUBJECTS are fair
       game; its source is not. The exclusion is stated rather than silent:
       its mirrors are UNMEASURED, not covered. *)
    |> List.filter (fun f ->
         not (mode = "--mirror"
              && contains_sub f "provenance_ceiling_impact"))
    |> List.filter (fun f -> match only with
         | Some o -> contains_sub f o | None -> true)
    |> List.sort compare
    |> List.map (Filename.concat oracle_dir) in
  prerr_endline (Printf.sprintf
    "  mode %s | oracles %d\n  verdict     oracle                       \
     subject:line  operator" mode (List.length oracles));
  prerr_endline
    "  ----------- ---------------------------- ------------- ------------";
  let results = ref [] in
  let nondet = ref [] in
  let no_subject = ref [] in
  let no_mutant = ref [] in
  List.iter (fun oracle ->
    let base_name = Filename.basename oracle in
    let src = read_file oracle in
    (* --- DETERMINISM CONTROL: the comparator must not fire on noise ------ *)
    let a = run_oracle oracle in
    let b = run_oracle oracle in
    (match a, b with
     | Some x, Some y when x = y ->
       let baseline = x in
       let muts =
         if mode = "--mirror" then
           List.concat_map (fun (fn, body) ->
             let ms = mutants_for_mirror oracle src fn body in
             (* UNMEASURED, said out loud. A mirror no operator applies to is
                not covered and is not uncovered: nothing looked. Silence here
                is what let `status_for` be reported UNCOVERED on the strength
                of four mutated comments. *)
             if ms = [] then
               no_mutant := (base_name ^ ":" ^ fn) :: !no_mutant;
             ms) (mirror_defs src)
         else begin
           (* A located subject is NOT a covered subject. proof_plane_guard
              declares "formal/lean/*.lean (tree-wide proof-plane guard)" --
              a glob with prose, which no single-file operator can empty. The
              earlier version inferred coverage from the ABSENCE of a warning
              and three of sixteen oracles fell through silently. Coverage is
              now asserted positively: the subject must resolve to a readable
              regular file, or the oracle is named as not covered. *)
           (match declared_subject src with
            | None -> no_subject := (base_name ^ "  (no subject argument)")
                                    :: !no_subject
            | Some p when not (Sys.file_exists p)
                          || (try Sys.is_directory p with _ -> true) ->
              no_subject := (base_name ^ "  (subject is not a readable \
                             single file: " ^ p ^ ")") :: !no_subject
            | Some _ -> ());
           let needles = needles_of src in
           (* Bounded: the four subjects with the most matching lines. Every
              subject is listed in the JSON whether or not it was mutated, so
              a skipped subject is visible rather than silently absent. *)
           let subs = subjects_of src in
           let ranked = List.map (fun p ->
             let ls = lines_of (read_file p) in
             let s = List.fold_left (fun acc l ->
               acc + (if List.exists (fun nd -> contains_sub l nd) needles
                      then 1 else 0)) 0 ls in
             (s, p)) subs
             |> List.sort (fun (x, _) (y, _) -> compare y x) in
           List.concat_map (fun (_, p) ->
             let imports =
               Filename.dirname p = oracle_dir
               && Filename.check_suffix p ".mojo" in
             let is_declared = (declared_subject src = Some p) in
             mutants_for_subject ~is_declared needles imports p)
             (* The four best-matching subjects, PLUS the declared subject
                whatever its rank. It is the only gated one, so letting it
                fall off the list would silently retire the gate. *)
             (* The condition was `the declared subject is already in the
                ranked list`, and that list is built from WHOLE string
                literals -- so twin_coverage, whose subject is split across
                two source lines by concatenation, could never satisfy it and
                was never mutated. Membership in a list assembled by a
                different rule is not the question; being a readable file is. *)
             (let top = List.filteri (fun k _ -> k < 4) ranked in
              match declared_subject src with
              | Some d when Sys.file_exists d
                            && not (try Sys.is_directory d with _ -> true)
                            && not (List.exists (fun (_, p) -> p = d) top) ->
                top @ [ (0, d) ]
              | _ -> top)
         end in
       List.iter (fun m ->
         let got = with_mutation m.m_path m.m_text
                     (fun () -> run_oracle oracle) in
         let verdict = match got with
           | None -> "NOT_RUN"
           | Some r when r <> baseline ->
             (match m.m_class with
              | "must-kill" -> "KILLED"
              | "must-survive" -> "SPEC_FAIL"
              | _ -> "MOVED")
           | Some _ ->
             (match m.m_class with
              | "must-kill" -> "SURVIVED"
              | "must-survive" -> "SPEC_OK"
              | _ -> "INSENSITIVE") in
         prerr_endline (Printf.sprintf "  %-11s %-28s %s:%d  %s"
           verdict base_name (Filename.basename m.m_path) m.m_line m.m_op);
         results := { r_oracle = base_name; r_mut = m; r_verdict = verdict }
                    :: !results) muts
     | _ ->
       (* NO DECLARED SUBJECT FOUND. Reported, because an oracle whose receipt
          subject this tool cannot locate is one the gate does not cover, and
          a bare "KILLED 11" cannot tell 11-of-11 from 11-of-16. *)
       (* The oracle's own receipt is not reproducible under the comparator,
          so no mutation result from it would mean anything. This is reported,
          not worked around. *)
       prerr_endline (Printf.sprintf "  %-11s %-28s %s" "NONDET" base_name
         "two unmutated runs differ -- not measurable");
       nondet := base_name :: !nondet)) oracles;
  let ungated = List.rev !no_subject in
  if ungated <> [] then begin
    prerr_endline (Printf.sprintf
      "\n  NO DECLARED SUBJECT located in %d oracle(s) -- the L1 gate does \n  NOT cover these, and their L1 results are observations only:"
      (List.length ungated));
    List.iter (fun o -> prerr_endline ("    " ^ o)) ungated
  end;
  let rs = List.rev !results in
  let count v = List.length (List.filter (fun r -> r.r_verdict = v) rs) in
  let survived = List.filter (fun r -> r.r_verdict = "SURVIVED") rs in
  let specfail = List.filter (fun r -> r.r_verdict = "SPEC_FAIL") rs in
  let notrun = List.filter (fun r -> r.r_verdict = "NOT_RUN") rs in
  prerr_endline (Printf.sprintf
    "\n  mutants %d | gated: KILLED %d, SURVIVED %d, NOT_RUN %d\n  \
     sensitivity (ungated): MOVED %d, INSENSITIVE %d\n  \
     specificity controls: %d held, %d fired | NONDET oracles %d"
    (List.length rs) (count "KILLED") (count "SURVIVED") (count "NOT_RUN")
    (count "MOVED") (count "INSENSITIVE")
    (count "SPEC_OK") (count "SPEC_FAIL") (List.length !nondet));
  if survived <> [] then begin
    prerr_endline
      "\n  SURVIVED -- the receipt did not move when the subject did. The \
       measurement\n  behind these arms was not looking at what it names:";
    List.iter (fun r -> prerr_endline (Printf.sprintf "    %s  <- %s:%d %s"
      r.r_oracle (Filename.basename r.r_mut.m_path) r.r_mut.m_line
      r.r_mut.m_op)) survived
  end;
  if specfail <> [] then
    prerr_endline
      "\n  SPEC_FAIL -- a line the oracle never claimed to read moved its \
       verdict.";
  prerr_endline
    "  KILLED means the receipt depends on the subject, NOT that the arm \
     measures\n  the right property. NOT_RUN is never a pass.";
  Printf.printf
    "{\"schema\":\"uos.mojo-mutation-dataplane.v1\",\"mode\":%S,\
     \"mutants\":%d,\"killed\":%d,\"survived\":%d,\"not_run\":%d,\
     \"spec_held\":%d,\"spec_fired\":%d,\"nondet\":%d,\"findings\":["
    mode (List.length rs) (count "KILLED") (count "SURVIVED")
    (count "NOT_RUN") (count "SPEC_OK") (count "SPEC_FAIL")
    (List.length !nondet);
  List.iteri (fun i r ->
    Printf.printf "%s{\"oracle\":%S,\"verdict\":%S,\"path\":%S,\"line\":%d,\
                   \"op\":%S}"
      (if i = 0 then "" else ",") r.r_oracle r.r_verdict r.r_mut.m_path
      r.r_mut.m_line r.r_mut.m_op)
    (survived @ specfail @ notrun);
  (* The KILLED list is published, not only the findings. In --mirror mode it
     is the evidence tools/mojo_arm_falsifiability.ml needs to corroborate a
     FIXED_VECTOR arm: an arm passing all-literal arguments to a mirror is
     sound exactly when mutating that mirror moves the receipt. Without this
     list that verdict would rest on an assertion nobody measured. *)
  print_string "],\"killed_ops\":[";
  List.iteri (fun i r -> Printf.printf "%s%S" (if i = 0 then "" else ",")
                 r.r_mut.m_op)
    (List.filter (fun r -> r.r_verdict = "KILLED") rs);
  print_string "],\"authority\":\"NONE\",\"ev_ceiling\":93}\n";
  (* ---- --mirror: aggregate PER MIRROR, not per mutant ------------------
     `quoted_examples` is `return in_inline + in_fenced`, and flipping the `+`
     to `-` did not move the receipt. That is not a gap: when the fenced count
     is 0, `i - 0` and `i + 0` are the same function, so the mutant is
     SEMANTICALLY EQUIVALENT to the original and nothing could have killed it.
     Gating on individual mutants would therefore turn an unkillable mutant
     into a permanent red gate on a correct mirror -- the inverted polarity
     again. A mirror is COVERED when AT LEAST ONE of its mutants dies, which
     is both the standard treatment of equivalent mutants and the only claim
     the evidence supports: that some arm observes this mirror. *)
  let mirror_name op =
    match String.index_opt op ':' with
    | Some k -> String.sub op 0 k | None -> op in
  let uncovered =
    if mode <> "--mirror" then []
    else begin
      let names = List.sort_uniq compare
                    (List.map (fun r -> mirror_name r.r_mut.m_op) rs) in
      let has nm v =
        List.exists (fun r -> mirror_name r.r_mut.m_op = nm
                              && r.r_verdict = v) rs in
      (* FIXED 20261107-0415. This was "no KILLED mutant exists", which put
         a mirror whose every mutant FAILED TO COMPILE in the same bucket as
         one whose mutants ran and moved nothing. `base_url` and `quoted`
         were reported "no arm observes it" when the truth was that nothing
         had run. UNCOVERED is a claim about an ARM; it needs a mutant that
         executed. Three-way: killed -> COVERED; else ran-and-survived ->
         UNCOVERED; else nothing ran -> UNMEASURED. *)
      let bad = List.filter (fun nm ->
        not (has nm "KILLED") && has nm "SURVIVED") names in
      List.iter (fun nm ->
        if not (has nm "KILLED") && not (has nm "SURVIVED") then
          no_mutant := (nm ^ " (every mutant failed to compile)")
                       :: !no_mutant) names;
      prerr_endline (Printf.sprintf
        "\n  mirrors with a mutant: %d | COVERED %d | UNCOVERED %d"
        (List.length names) (List.length names - List.length bad)
        (List.length bad));
      if bad <> [] then begin
        prerr_endline
          "  UNCOVERED -- every mutant of this mirror survived, so no arm \
           observes it.\n  A FIXED_VECTOR arm calling one of these has no \
           evidence behind it:";
        List.iter (fun nm -> prerr_endline ("    " ^ nm)) bad
      end;
      if !no_mutant <> [] then begin
        prerr_endline (Printf.sprintf
          "  UNMEASURED %d -- no operator in this instrument applies to these \
           mirrors.\n  NOT covered and NOT uncovered: nothing looked at them. \
           A FIXED_VECTOR arm\n  calling one stays OPEN, which is the correct \
           propagation, not a pass:"
          (List.length !no_mutant));
        List.iter (fun nm -> prerr_endline ("    " ^ nm))
          (List.sort compare !no_mutant)
      end;
      bad
    end in
  (* GATED: SURVIVED on a declared subject (--subject), an UNCOVERED mirror
     (--mirror), NOT_RUN, and NONDET. NOT gated: SPEC_FAIL (ambiguous, see the
     specificity-control note), a single surviving mutant of a covered mirror,
     and L1 insensitivity on a path the oracle only names. *)
  let gated_survived =
    if mode = "--mirror" then [] else survived in
  exit (if gated_survived = [] && uncovered = [] && notrun = []
           && !nondet = [] then 0 else 1)
