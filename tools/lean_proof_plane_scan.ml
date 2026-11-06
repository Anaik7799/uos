(* ==========================================================================
   lean_proof_plane_scan — lex Lean source well enough to tell CODE from PROSE.

   WHY THIS EXISTS
   ---------------
   The tree-wide proof-plane guard was a pile of greps, and greps cannot read.
   Twice now a file was reported as a BOUNDARY VIOLATION because its own
   documentation said what it no longer does:

     formal/lean/UosCoreEvoUnifiedDigitalTwin.lean
       "This file has no `def main`, no `IO.Process`"        -> flagged
     formal/lean/BionicMojoLeanHighPerformanceInterception.lean
       "(5 `IO.Process.output` calls ... `IO.FS.writeFile`)"  -> flagged

   The first time this was patched by tightening the pattern to require the
   trailing member-access dot. That is not a fix, it is a narrower guess: the
   second case has the dot, inside a comment, and tripped anyway. A guard that
   punishes a file for explaining itself teaches authors to stop explaining,
   which is the opposite of what it is for.

   So the lexing is done properly, once, here: nested `/- -/` block comments,
   `--` line comments, string literals with escapes, and Lean's `/-! -/`
   module docstrings are all removed before anything is matched.

   WHAT IT REPORTS, AND WHY ORDER IS THE WHOLE POINT
   -------------------------------------------------
   Lean requires declaration before use. A theorem at line 205 therefore
   CANNOT reference a definition at line 266. That makes one syntactic fact
   sound evidence for the property that actually matters:

     if every IO declaration in a file sits AFTER the last theorem,
     then no observation in that file can be an input to any proof in it.

   This is why the guard is not "no IO in proof files" (which would bar the
   contract-sanctioned generator that writes CLAUDE.md) and not a name
   allowlist (which is an exemption wearing a sanction's clothes). It is:

     G3a  HARD, no exemption: no IO and no `def main` BEFORE the last
          theorem. An observation positioned where a proof can consume it.
     G3b  a file whose IO sits after its theorems is a TRAILING RENDERER.
          It must be declared in the renderer manifest with a stated
          sanction, and an undeclared one fails the guard -- so the set
          cannot grow quietly.

   Output: one JSON object per .lean file on stdout, consumed by
   formal/mojo/proof_plane_guard_oracle.mojo. This tool reports; it does not
   decide. authority NONE. EV ceiling 93.
   ========================================================================== *)

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

(* Replace every comment and string-literal byte with a space, keeping the
   file's length and newline positions intact so offsets stay comparable and
   line numbers stay reportable. *)
let strip_comments_and_strings (s : string) : string =
  let n = String.length s in
  let out = Bytes.of_string s in
  let blank i = if s.[i] <> '\n' then Bytes.set out i ' ' in
  let i = ref 0 in
  let depth = ref 0 in
  while !i < n do
    if !depth > 0 then begin
      (* inside a (possibly nested) block comment *)
      if !i + 1 < n && s.[!i] = '-' && s.[!i + 1] = '/' then begin
        blank !i; blank (!i + 1); decr depth; i := !i + 2
      end else if !i + 1 < n && s.[!i] = '/' && s.[!i + 1] = '-' then begin
        blank !i; blank (!i + 1); incr depth; i := !i + 2
      end else begin blank !i; incr i end
    end else if !i + 1 < n && s.[!i] = '/' && s.[!i + 1] = '-' then begin
      (* covers /- , /-- doc comments and /-! module docstrings alike *)
      blank !i; blank (!i + 1); depth := 1; i := !i + 2
    end else if !i + 1 < n && s.[!i] = '-' && s.[!i + 1] = '-' then begin
      while !i < n && s.[!i] <> '\n' do blank !i; incr i done
    end else if s.[!i] = '\'' && !i + 2 < n
                && (s.[!i + 2] = '\''
                    || (s.[!i + 1] = '\\' && !i + 3 < n && s.[!i + 3] = '\''))
    then begin
      (* CHARACTER LITERAL. Codex finding, 20261106: the stripper handled
         string literals but not char literals, so Lean's `'"'` -- a
         perfectly ordinary character -- opened a phantom string that
         swallowed the rest of the file. Everything after it would have been
         blanked, which would SILENTLY SHRINK every count in the report and
         make a violating file read as clean.

         That is the worst failure mode available to this tool: it does not
         error, it under-reports. The guard would have gone green.

         Guarded by lookahead so a prime in an identifier (`h'`, `xs'`), which
         is idiomatic Lean and far more common than a char literal, is not
         mistaken for one. *)
      let len = if s.[!i + 1] = '\\' then 4 else 3 in
      for k = !i to !i + len - 1 do if k < n then blank k done;
      i := !i + len
    end else if s.[!i] = '"' then begin
      blank !i; incr i;
      let fin = ref false in
      while not !fin && !i < n do
        if s.[!i] = '\\' && !i + 1 < n then begin
          blank !i; blank (!i + 1); i := !i + 2
        end else if s.[!i] = '"' then begin blank !i; incr i; fin := true end
        else begin blank !i; incr i end
      done
    end else incr i
  done;
  Bytes.to_string out

(* ---------- offset search ---------------------------------------------- *)

let find_all (hay : string) (needle : string) : int list =
  let nh = String.length hay and nn = String.length needle in
  if nn = 0 || nn > nh then []
  else begin
    let acc = ref [] in
    for i = nh - nn downto 0 do
      if String.sub hay i nn = needle then acc := i :: !acc
    done;
    !acc
  end

(* Offsets of a token that must start a line (possibly after whitespace). *)
let find_line_starts (hay : string) (needle : string) : int list =
  List.filter
    (fun i ->
       let rec back j =
         if j < 0 then true
         else match hay.[j] with
           | '\n' -> true
           | ' ' | '\t' -> back (j - 1)
           | _ -> false
       in
       back (i - 1))
    (find_all hay needle)

let line_of (s : string) (off : int) : int =
  let l = ref 1 in
  for i = 0 to min off (String.length s - 1) - 1 do
    if s.[i] = '\n' then incr l
  done;
  !l

let io_tokens =
  [ "IO.Process."; "IO.FS."; "IO.getEnv"; "System.FilePath"; "IO.Process.exit" ]

let min_opt = function [] -> None | l -> Some (List.fold_left min max_int l)
let max_opt = function [] -> None | l -> Some (List.fold_left max min_int l)

(* ---------- the other guard arms, measured on CODE not prose ------------
   G2, G4a, G4b and G5 were greps over raw source for the same reason G3
   was, and they carry the same prose hazard: this very file's comments
   contain the strings `def observationNow` and `_aligned_now`. Measuring
   them here means every arm of the guard reads the same stripped source,
   from one scanner, instead of four independently-wrong regexes. *)

(* A frozen present-tense fixture: `def observationNow ...` or any
   `def <name>Now :`. The defect is a record that CLAIMS to be the present
   and is then decided over, so the kernel re-verifies the arithmetic
   forever and never re-verifies the fact. Historical names are fine --
   `observationDuringOutage` makes no claim about now. *)
let count_frozen_fixtures code =
  let offs = find_line_starts code "def " in
  List.length
    (List.filter
       (fun o ->
          (* read the identifier after "def " *)
          let n = String.length code in
          let i = ref (o + 4) in
          let b = Buffer.create 32 in
          while !i < n
                && (match code.[!i] with
                    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '\'' -> true
                    | _ -> false)
          do Buffer.add_char b code.[!i]; incr i done;
          let id = Buffer.contents b in
          let ln = String.length id in
          ln >= 3 && String.sub id (ln - 3) 3 = "Now")
       offs)

(* A theorem asserting a verdict about NOW. Same defect, stated as a proof. *)
let count_frozen_theorems code =
  let offs = find_line_starts code "theorem " in
  List.length
    (List.filter
       (fun o ->
          let n = String.length code in
          let i = ref (o + 8) in
          let b = Buffer.create 64 in
          while !i < n
                && (match code.[!i] with
                    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '\'' -> true
                    | _ -> false)
          do Buffer.add_char b code.[!i]; incr i done;
          let id = Buffer.contents b in
          let ends_with suf =
            let ls = String.length suf and li = String.length id in
            li >= ls && String.sub id (li - ls) ls = suf
          in
          ends_with "_now" || ends_with "_today")
       offs)

(* An unconditional `=PASS` banner. A Lean file's only evidence is that it
   typechecks; printing a literal PASS makes a typecheck read as a system
   verdict. A CONDITIONAL result is fine and is not counted, because the
   literal then sits inside an if/then/else rather than alone in a string.
   Detected on the RAW source, since the banner lives in a string literal
   the stripper blanks -- but only where the line also prints. *)
let count_pass_banners raw =
  let lines = String.split_on_char '\n' raw in
  List.length
    (List.filter
       (fun l ->
          let has sub =
            let nl = String.length l and ns = String.length sub in
            let rec go i = i + ns <= nl && (String.sub l i ns = sub || go (i + 1)) in
            ns <= nl && go 0
          in
          has "IO.println" && has "=PASS" && not (has "if ") && not (has "then "))
       lines)

(* ---------- naming / ontology conformance -------------------------------
   Measured, not assumed. Two earlier premises about naming drift in this
   tree were my own measurement artifacts, so these arms report counts and
   let the manifest decide what is admitted:

   * 1,492 theorems carry a name. ZERO are a bare index: every `t25_...`,
     `T12_...` and `c3_...` is followed by its claim. Only 185 (12.4%) use
     `THM_<FAM>_<nn>_<claim>`; the other ~1,300 are claim-first snake_case,
     which is the mathlib norm and the MAJORITY regime here. A mass rename
     toward THM_FAM_nn would therefore be churn toward the minority style,
     and toward putting an opaque family code where a claim already is.
     So the enforced rule is the one both regimes already satisfy:
     A THEOREM NAME STATES ITS CLAIM. `index_only_theorems` is the
     regression guard for that, and it currently reads 0.

   * Namespace roots: `UOS.*` is canonical. `Ruliad.*` is a sanctioned
     second root (a self-contained ruliology library, 16 files). Four flat
     roots are cited by immutable journals and ZK notes, so renaming them
     would dangle those references, which INV-PROV-03 forbids; they are
     DECLARED in the ontology manifest instead of rewritten. *)

let namespace_root code =
  let offs = find_line_starts code "namespace " in
  match offs with
  | [] -> ""
  | o :: _ ->
    let n = String.length code in
    let i = ref (o + 10) in
    let b = Buffer.create 48 in
    while !i < n
          && (match code.[!i] with
              | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '.' | '\'' -> true
              | _ -> false)
    do Buffer.add_char b code.[!i]; incr i done;
    let full = Buffer.contents b in
    (match String.index_opt full '.' with
     | None -> full
     | Some k -> String.sub full 0 k)

(* A name that is ONLY an index -- `t25`, `T12`, `c3`, `math4` -- states no
   claim, so the theorem cannot be read without opening the file. Distinct
   from `t25_dual_plane_..._verified`, which carries its claim after a short
   index and is admitted. *)
let count_index_only_theorems code =
  let offs = find_line_starts code "theorem " @ find_line_starts code "lemma " in
  List.length
    (List.filter
       (fun o ->
          let n = String.length code in
          let i = ref o in
          while !i < n && code.[!i] <> ' ' do incr i done;
          incr i;
          let b = Buffer.create 64 in
          while !i < n
                && (match code.[!i] with
                    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '\'' -> true
                    | _ -> false)
          do Buffer.add_char b code.[!i]; incr i done;
          let id = Buffer.contents b in
          (* index-only = letters then digits, nothing after *)
          let ln = String.length id in
          ln > 0
          && (let j = ref 0 in
              while !j < ln
                    && (match id.[!j] with 'a' .. 'z' | 'A' .. 'Z' -> true
                                         | _ -> false)
              do incr j done;
              let letters = !j in
              while !j < ln
                    && (match id.[!j] with '0' .. '9' -> true | _ -> false)
              do incr j done;
              letters > 0 && !j = ln && !j > letters))
       offs)

(* ---------- ARGUMENT-DISCARDING DEFINITIONS ----------------------------
   A new vacuity shape, found 20261106 by a delegated census and verified:

     def fractalCellCovered (l : …) (d : …) (a : …) (c : …) (h : …) : Bool :=
       let _ := (l, d, a, c, h)
       true

     theorem THM_HFB_ONT_05_full_fractal_coverage_10x10x17x13x5_complete :
       … (allLayers.all (fun l => … allHarnesses.all (fun h =>
             fractalCellCovered l d a c h))) = true := by decide

   The `decide` genuinely enumerates 110,500 combinations. Every one is
   `true` BY CONSTRUCTION, because the function throws its arguments away.
   The theorem's name claims "110,500 verified fractal cells with zero
   gaps"; what it establishes is that `true` is `true` 110,500 times.

   This is a DIFFERENT shape from the frozen-observation defect G4 catches.
   There, a real value was recorded and went stale. Here no value is ever
   consulted, so there is nothing to go stale and nothing to be right
   either. It is the vacuity `THM_VAC_01` denies, expressed as a kernel
   computation large enough to look like work.

   `let _ := (args)` is the idiom Lean authors use to silence unused-variable
   warnings, which is exactly why it is dangerous: it is a deliberate,
   legible marker that the arguments are not consulted, and it reads as
   tidiness. The guard counts it and the operator decides; a definition may
   legitimately ignore its arguments, but a THEOREM quantifying over them
   and discharging by `decide` cannot then claim coverage.

   Measured on stripped code, so a comment describing the pattern does not
   trip it -- the same discipline every other arm now follows. *)
let count_arg_discarding_defs code =
  let offs = find_all code "let _ := (" in
  (* Require the discard to sit inside a `def` body: the nearest preceding
     line-start keyword must be `def`, not `theorem` or `example`. A discard
     in a proof script is ordinary and not this defect. *)
  List.length
    (List.filter
       (fun o ->
          let rec back j last =
            if j < 0 then last
            else if j + 4 <= String.length code && String.sub code j 4 = "def "
                    && (j = 0 || code.[j - 1] = '\n')
            then "def"
            else if j + 8 <= String.length code && String.sub code j 8 = "theorem "
                    && (j = 0 || code.[j - 1] = '\n')
            then "theorem"
            else back (j - 1) last
          in
          back (o - 1) "none" = "def")
       offs)

let scan path =
  let raw = read_file path in
  let code = strip_comments_and_strings raw in
  (* `theorem` and `lemma` both make a file proof-bearing. Accept the
     `private`/`protected`/`@[...]` forms by searching the keyword at a line
     start only, which is how every file in this tree writes them. *)
  let thm_offs =
    find_line_starts code "theorem " @ find_line_starts code "lemma " in
  let main_offs = find_line_starts code "def main" in
  let io_offs =
    List.concat_map (fun t -> find_all code t) io_tokens in
  let last_thm = max_opt thm_offs in
  let n_thm = List.length thm_offs in
  (* The hard arm: IO or `def main` positioned where a proof could use it. *)
  let before_last_thm offs =
    match last_thm with
    | None -> []   (* no theorems: nothing in this file can be a proof input *)
    | Some lt -> List.filter (fun o -> o < lt) offs
  in
  let io_pre = before_last_thm io_offs in
  let main_pre = before_last_thm main_offs in
  let trailing = n_thm > 0 && (io_offs <> [] || main_offs <> []) in
  Printf.printf
    "{\"file\":%S,\"theorems\":%d,\"io_total\":%d,\"main_total\":%d,\
     \"io_before_last_theorem\":%d,\"main_before_last_theorem\":%d,\
     \"first_offending_line\":%d,\"trailing_io_section\":%b,\
     \"axioms\":%d,\"frozen_fixtures\":%d,\"frozen_theorems\":%d,\
     \"pass_banners\":%d,\"namespace_root\":%S,\"index_only_theorems\":%d,\"arg_discarding_defs\":%d}\n"
    path n_thm (List.length io_offs) (List.length main_offs)
    (List.length io_pre) (List.length main_pre)
    (match min_opt (io_pre @ main_pre) with
     | None -> 0 | Some o -> line_of raw o)
    trailing
    (List.length (find_line_starts code "axiom "))
    (count_frozen_fixtures code)
    (count_frozen_theorems code)
    (count_pass_banners raw)
    (namespace_root code)
    (count_index_only_theorems code)
    (count_arg_discarding_defs code)

let rec lean_files dir acc =
  let entries = try Sys.readdir dir with _ -> [||] in
  Array.fold_left
    (fun acc e ->
       if e = ".lake" then acc
       else
         let p = Filename.concat dir e in
         if Sys.is_directory p then lean_files p acc
         else if Filename.check_suffix e ".lean" then p :: acc
         else acc)
    acc entries

let () =
  (* Accepts a directory (scan every .lean under it) or a single .lean file,
     so the differential driver can ask about one subject without scanning
     the whole tree on every pair. *)
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "formal/lean" in
  let files =
    if Sys.file_exists root && not (Sys.is_directory root) then [ root ]
    else List.sort compare (lean_files root [])
  in
  List.iter scan files
