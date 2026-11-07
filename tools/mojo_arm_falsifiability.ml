(* ==========================================================================
   mojo_arm_falsifiability — L5 instrument: does each oracle arm have a
   falsifying assignment?

   WHY THIS EXISTS
   ---------------
   The previous repair round certified "0 unfalsifiable algebra arms" using a
   scanner that detected only LITERAL tautologies: predicates whose free
   identifiers are empty or drawn from the file's own `comptime` constants. It
   therefore blessed exactly the class it was built to measure and was
   structurally blind to the class the repair created — predicates that MENTION
   a derived variable which then cancels out:

     x != 3 - x          is  2x != 3     — no integer solution
     3 - (3 - x) == x    is  an identity
     (3 - x) != x        holds because 3 is odd
     v + b >= 0          under a non-negativity guard
     a + b > a           is  b > 0
     n >= 0              where the producer can only return a non-negative n

   Every one passes the literal scan and fails the actual requirement. The
   instrument was inside the system it measured. This tool is outside it.

   WHAT IT DOES
   ------------
   Extracts each `r.algebra(...)` / `r.mutation_probe(...)` predicate, and for
   those that are pure arithmetic/boolean expressions, ENUMERATES their free
   identifiers over a bounded domain and counts assignments where the predicate
   is FALSE. No falsifying assignment over the whole domain => UNFALSIFIABLE.

   HONEST BOUNDARY
   ---------------
   Bounded enumeration CANNOT PROVE falsifiability. `FALSIFIABLE` is evidence
   from the sampled domain, not a theorem. `UNFALSIFIABLE` over that domain is
   a strong signal and is treated as a failure. An arm containing a function
   call, field access or indexing is reported NOT_ANALYSED — an open question,
   never a pass. This tool does not claim a proof, which is the same discipline
   the oracles are held to.

   authority NONE. EV ceiling 93.
   ========================================================================== *)

let oracle_dir = "formal/mojo"

(* ---------- source hygiene: strip comments and string literals ---------- *)

(* LENGTH-PRESERVING. Comment and string-literal characters become spaces, so
   every offset into the result maps 1:1 onto the original source. The first
   version of this function DELETED them, which made offsets drift and reported
   every arm as `<unnamed>` at a wrong line -- the verdicts were right and
   unusable. A reader that cannot say WHERE it found something is not much of a
   reader. *)
let strip_noise (s : string) : string =
  let n = String.length s in
  let b = Bytes.of_string s in
  let i = ref 0 in
  let in_str = ref false and in_cmt = ref false in
  while !i < n do
    let c = Bytes.get b !i in
    if !in_cmt then begin
      if c = '\n' then in_cmt := false else Bytes.set b !i ' ';
      incr i
    end else if !in_str then begin
      if c = '\\' && !i + 1 < n then begin
        Bytes.set b !i ' '; Bytes.set b (!i + 1) ' '; i := !i + 2
      end else begin
        if c = '"' then in_str := false else Bytes.set b !i ' ';
        incr i
      end
    end else begin
      if c = '#' then (in_cmt := true; Bytes.set b !i ' '; incr i)
      else (if c = '"' then in_str := true; incr i)
    end
  done;
  Bytes.to_string b

(* ---------- extract (name, predicate) pairs by paren balance ----------- *)

type arm = {
  file : string;
  line : int;
  kind : string;                        (* algebra | mutation_probe *)
  name : string;
  pred : string;
}

let find_sub (hay : string) (needle : string) (from : int) : int option =
  let hn = String.length hay and nn = String.length needle in
  let rec go i = if i + nn > hn then None
    else if String.sub hay i nn = needle then Some i else go (i + 1) in
  if nn = 0 then None else go from

(* A multi-line `r.algebra(name,\n  pred,\n)` call leaves a TRAILING COMMA on
   the extracted predicate, and `(pred,)` is a one-element tuple in Mojo, not a
   Bool: every such probe died with "'Tuple[Bool]' does not implement
   '__bool__'". The defect was present from the start and invisible, because
   every arm it affected contained a mirror call and was therefore
   NOT_ANALYSED -- the enumerator never tried to compile one. Enabling B2 made
   37 arms analysable and all 37 failed to run at once. An open question can
   hide a broken reader indefinitely. *)
let strip_trailing_comma (s : string) : string =
  let s = ref (String.trim s) in
  let changed = ref true in
  while !changed do
    changed := false;
    let n = String.length !s in
    if n > 0 && !s.[n - 1] = ',' then begin
      s := String.trim (String.sub !s 0 (n - 1)); changed := true
    end
  done;
  !s

let line_of (src : string) (off : int) : int =
  let c = ref 1 in
  String.iteri (fun i ch -> if i < off && ch = '\n' then incr c) src;
  !c

(* The call shape is: r.<kind>(String("<name>"), <pred>) — pred runs to the
   matching close paren of the call itself. *)
let extract_arms (file : string) (src : string) : arm list =
  let clean = strip_noise src in
  let out = ref [] in
  List.iter (fun kind ->
    (* `r.` specifically, not any `.algebra(`. The oracle's own receipt is
       `r` by convention across all 16 oracles; a differently-named receipt is
       FIXTURE CONSTRUCTION -- a synthetic state built to drive the substrate,
       asserting nothing. Without this the detector reported a driver's
       `r.algebra(String("x"), True)` as a literal tautology: right about the
       literal, wrong about the role. The convention is checked rather than
       assumed: see the arms-on-r census printed below. *)
    let tag = "r." ^ kind ^ "(" in
    let pos = ref 0 in
    let continue_ = ref true in
    while !continue_ do
      match find_sub clean tag !pos with
      | None -> continue_ := false
      | Some i ->
        let open_at = i + String.length tag in
        (* walk to the matching close paren *)
        let n = String.length clean in
        let depth = ref 1 and j = ref open_at in
        while !depth > 0 && !j < n do
          (match clean.[!j] with
           | '(' -> incr depth
           | ')' -> decr depth
           | _ -> ());
          if !depth > 0 then incr j
        done;
        if !depth = 0 then begin
          let body = String.sub clean open_at (!j - open_at) in
          (* name is the first String("") placeholder; we recover the real name
             from the ORIGINAL source at the same offset *)
          let real = String.sub src open_at (!j - open_at) in
          let name =
            match find_sub real "\"" 0 with
            | None -> "<unnamed>"
            | Some a ->
              (match find_sub real "\"" (a + 1) with
               | None -> "<unnamed>"
               | Some z -> String.sub real (a + 1) (z - a - 1)) in
          (* predicate = everything after the first top-level comma *)
          let pred =
            let n2 = String.length body in
            let d = ref 0 and k = ref 0 and cut = ref (-1) in
            while !k < n2 && !cut < 0 do
              (match body.[!k] with
               | '(' | '[' -> incr d
               | ')' | ']' -> decr d
               | ',' when !d = 0 -> cut := !k
               | _ -> ());
              incr k
            done;
            if !cut < 0 then "" else String.sub body (!cut + 1) (n2 - !cut - 1) in
          out := { file; line = line_of src i; kind; name;
                   pred = strip_trailing_comma pred } :: !out
        end;
        pos := open_at
    done) ["algebra"; "mutation_probe"];
  List.rev !out

(* ---------- B2: locally-defined PURE mirror functions ------------------
   87 of the previously NOT_ANALYSED arms call only PURE mirror functions --
   `runtime_aligned`, `gateway_aligned`, `aligned`, `span_within_budget`,
   `owned_in`, `quoted_examples`, `immune_breaker`, `live`, `status_for`.
   Those are deterministic functions over Ints and Bools, so they can be
   ENUMERATED: a generated probe imports them from the oracle's own module
   and calls them over the domain. Feasibility was proven first with a
   hand-written probe (span_timings_monotonic: 55 falsifying assignments,
   span_within_budget: 9) before any of this was written.

   A function is PURE here if its body contains no world contact. The
   world-contact set is explicit rather than inferred, because a wrong guess
   in either direction is worse than a short list: including a world call
   would make the probe hang or lie, and excluding a pure function only
   leaves an arm NOT_ANALYSED, which is already its state. *)
let world_contact = ["capture"; "count"; "http_code"; "http_body";
                     "field_total"; "occurrences"; "json_flag"; "json_int";
                     "json_signed"; "json_norm"; "json_has"; "state_count";
                     "regime_b_index"; "lean_arch_ctor"; "sev_rank";
                     "exit_rank"; "status_for"; "status_for_obs"]

let pure_defs_of (src : string) : string list =
  let lines = String.split_on_char '\n' src in
  let rec collect acc cur name = function
    | [] -> (match name with Some n when cur -> n :: acc | _ -> acc)
    | l :: tl ->
      let is_def =
        String.length l > 4 && String.sub l 0 4 = "def "
        || (String.length l > 8 && String.sub l 0 8 = "    def ") in
      if is_def then begin
        let acc = (match name with Some n when cur -> n :: acc | _ -> acc) in
        let body = String.trim l in
        let body = if String.length body > 4 then String.sub body 4
                     (String.length body - 4) else "" in
        let nm = try String.sub body 0 (String.index body '(')
                 with Not_found -> "" in
        collect acc true (if nm = "" then None else Some nm) tl
      end else begin
        let impure =
          List.exists (fun w ->
            let pat = w ^ "(" in
            let ln = String.length l and pn = String.length pat in
            let rec go i = if i + pn > ln then false
              else if String.sub l i pn = pat then true else go (i+1) in
            go 0) world_contact in
        if impure then collect acc false name tl else collect acc cur name tl
      end in
  List.sort_uniq compare (collect [] false None lines)

(* ---------- classify: analysable pure expression? ---------------------- *)

let is_ident_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '_'

let keywords = ["and"; "or"; "not"; "True"; "False"; "if"; "else"]

let idents_of (p : string) : string list =
  let n = String.length p in
  let acc = ref [] and i = ref 0 in
  while !i < n do
    if is_ident_char p.[!i] && not (p.[!i] >= '0' && p.[!i] <= '9') then begin
      let s = !i in
      while !i < n && is_ident_char p.[!i] do incr i done;
      let w = String.sub p s (!i - s) in
      if not (List.mem w keywords) && not (List.mem w !acc) then acc := w :: !acc
    end else incr i
  done;
  List.rev !acc

(* A predicate is ANALYSABLE when every character is in the allowed set and no
   identifier is immediately followed by '(' (a call) or '.' / '[' (field or
   index access). *)
let analysable ?(pure : string list = []) (p : string) : bool =
  let n = String.length p in
  if n = 0 then false else begin
    let ok = ref true in
    String.iter (fun c ->
      if not (is_ident_char c || c = ' ' || c = '\n' || c = '\t'
              || c = '(' || c = ')' || c = '+' || c = '-' || c = '*'
              || c = '/' || c = '=' || c = '!' || c = '<' || c = '>'
              || c = ',')
      then ok := false) p;
    (* reject calls / field access / indexing *)
    let i = ref 0 in
    while !i < n do
      if is_ident_char p.[!i] then begin
        let s = !i in
        while !i < n && is_ident_char p.[!i] do incr i done;
        let w = String.sub p s (!i - s) in
        (* skip whitespace *)
        let k = ref !i in
        while !k < n && (p.[!k] = ' ' || p.[!k] = '\n' || p.[!k] = '\t') do incr k done;
        if !k < n && p.[!k] = '(' && not (List.mem w keywords)
           && not (List.mem w pure) then ok := false
      end else begin
        if p.[!i] = '.' || p.[!i] = '[' then ok := false;
        incr i
      end
    done;
    !ok
  end

(* ---------- emit a Mojo enumerator ------------------------------------- *)

(* Two domains. Narrow arms get the full sweep; wide arms get a reduced one so
   the enumeration stays bounded. 23^3 = 12k; 11^5 = 161k. Raising the cap from
   3 to 5 was necessary, not cosmetic: the three arms that MOTIVATED this tool
   (`ontology_atlas` atlas06/08/09) have four free identifiers each, so a cap of
   3 reported them NOT_ANALYSED -- the detector was blind to its own reason for
   existing. *)
let domain = [-8;-7;-6;-5;-4;-3;-2;-1;0;1;2;3;4;5;6;7;8;11;40;93;101;239;1015]
let domain_wide = [-3;-2;-1;0;1;2;3;4;40;93;239]
let max_vars = 5

(* Every integer literal in the predicate must be IN that arm's domain, plus
   its neighbours. Without this the tool produces FALSE POSITIVES: the arms
   `declared != 104 and observed != 104` and `104 != observed` were reported
   UNFALSIFIABLE purely because 104 was absent from the sweep, so no assignment
   could falsify them. Both arms are correct and the instrument was wrong.
   Trusting that verdict would have "fixed" two sound arms -- the round-two
   failure mode, committed by the tool built to prevent it. It was caught only
   by reading the arms instead of the report. *)
let literals_of (p : string) : int list =
  let n = String.length p in
  let acc = ref [] and i = ref 0 in
  while !i < n do
    if p.[!i] >= '0' && p.[!i] <= '9'
       && (!i = 0 || not (is_ident_char p.[!i - 1])) then begin
      let s0 = !i in
      while !i < n && p.[!i] >= '0' && p.[!i] <= '9' do incr i done;
      (try
         let v = int_of_string (String.sub p s0 (!i - s0)) in
         List.iter (fun d -> if not (List.mem d !acc) then acc := d :: !acc)
           [v - 1; v; v + 1]
       with _ -> ())
    end else incr i
  done;
  !acc

let emit_mojo ?(imports : (string * string list) list = [])
      ?(consts : string list = [])
      ?(offset : int = 0) (arms : arm list) (path : string) : unit =
  let oc = open_out path in
  (* Import each file's pure mirror functions from its own module. *)
  List.iter (fun (modname, fns) ->
    if fns <> [] then
      output_string oc (Printf.sprintf "from %s import %s\n" modname
        (String.concat ", " fns))) imports;
  output_string oc
    "# GENERATED by tools/mojo_arm_falsifiability.ml -- do not edit.\n\
     # Enumerates each analysable oracle arm over a bounded integer domain and\n\
     # prints the number of FALSIFYING assignments. 0 => UNFALSIFIABLE.\n\n\
     def main():\n\
     \    var dom = [";
  List.iteri (fun i v ->
    output_string oc (if i = 0 then "" else ", ");
    output_string oc (string_of_int v)) domain;
  output_string oc "]\n    var domw = [";
  List.iteri (fun i v ->
    output_string oc (if i = 0 then "" else ", ");
    output_string oc (string_of_int v)) domain_wide;
  output_string oc "]\n";
  List.iteri (fun i0 a ->
    let idx = i0 + offset in
    (* A comptime constant keeps its own value: it is excluded from the loop
       variables, so the arm is enumerated over what actually varies. Looping
       over it shadows the real constant and widens the arm into a question it
       never asked. *)
    let vars = List.filter (fun v ->
      not (List.exists (fun (_, fns) -> List.mem v fns) imports)
      && not (List.mem v consts))
      (idents_of a.pred) in
    let nv = List.length vars in
    if nv <= max_vars then begin
      let base = if nv <= 3 then domain else domain_wide in
      let extra = List.filter (fun v -> not (List.mem v base))
                    (literals_of a.pred) in
      let dom_vals = base @ extra in
      let dom = Printf.sprintf "d%d" idx in
      output_string oc (Printf.sprintf "    var %s = [" dom);
      List.iteri (fun i v ->
        output_string oc (if i = 0 then "" else ", ");
        output_string oc (string_of_int v)) dom_vals;
      output_string oc "]\n";
      output_string oc (Printf.sprintf "    var false_%d = 0\n" idx);
      (* nested loops, one per free identifier *)
      List.iteri (fun k v ->
        let ind = String.make (4 + 4 * k) ' ' in
        output_string oc
          (Printf.sprintf "%sfor i%d in range(len(%s)):\n" ind k dom);
        output_string oc
          (Printf.sprintf "%s    var %s = %s[i%d]\n" ind v dom k)) vars;
      let ind = String.make (4 + 4 * nv) ' ' in
      output_string oc (Printf.sprintf "%sif not (%s):\n" ind
                          (String.concat " " (String.split_on_char '\n' a.pred)));
      output_string oc (Printf.sprintf "%s    false_%d += 1\n" ind idx);
      output_string oc
        (Printf.sprintf "    print(\"ARM\", %d, false_%d)\n" idx idx)
    end else begin
      (* WIDE ARM: a full cross-product is infeasible, so sweep ONE
         identifier at a time from each of several baselines. This
         UNDER-approximates -- it can miss a falsifying assignment that needs
         two identifiers moved together -- so finding none leaves the arm
         NOT_ANALYSED and never promotes it to UNFALSIFIABLE. Without this,
         an 8-identifier arm like `a != b and c != d and ...` was simply
         unexamined, which is how the detector would have gone quiet about
         the very arms it was built for once they were widened. *)
      (* SAME exclusion as the narrow path. It was missing here, and the wide
         path emitted `var quoted_examples = wdom[q]` -- shadowing the imported
         mirror with an Int, so every wide arm calling a mirror died with
         "'Int' does not implement '__call__'". The branch had never been
         travelled by an arm containing a mirror call, because all of those
         were NOT_ANALYSED until B2. Two code paths, one of them unexercised,
         and the exclusion written in only one: the same shape as the missing
         offset increment. *)
      let vars_w = List.filter (fun v ->
        not (List.exists (fun (_, fns) -> List.mem v fns) imports)
        && not (List.mem v consts)) (idents_of a.pred) in
      let lits = literals_of a.pred in
      let base = [0; 1; 3] @ lits in
      output_string oc (Printf.sprintf "    var wfalse_%d = 0\n" idx);
      output_string oc (Printf.sprintf "    var wdom_%d = [" idx);
      List.iteri (fun i v ->
        output_string oc (if i = 0 then "" else ", ");
        output_string oc (string_of_int v)) (domain_wide @ lits);
      output_string oc "]\n";
      List.iter (fun bv ->
        List.iter (fun moved ->
          output_string oc
            (Printf.sprintf "    for q in range(len(wdom_%d)):\n" idx);
          List.iter (fun v ->
            output_string oc
              (if v = moved
               then Printf.sprintf "        var %s = wdom_%d[q]\n" v idx
               else Printf.sprintf "        var %s = %d\n" v bv)) vars_w;
          output_string oc
            (Printf.sprintf "        if not (%s):\n"
               (String.concat " " (String.split_on_char '\n' a.pred)));
          output_string oc
            (Printf.sprintf "            wfalse_%d += 1\n" idx)) vars_w) base;
      output_string oc
        (Printf.sprintf "    print(\"WIDE\", %d, wfalse_%d)\n" idx idx)
    end) arms;
  output_string oc "    print(\"DONE\")\n";
  close_out oc

(* ---------- main ------------------------------------------------------- *)

let read_file p =
  let ic = open_in_bin p in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let () =
  let only = if Array.length Sys.argv > 1 then Some Sys.argv.(1) else None in
  let files =
    match only with
    | Some f when Sys.file_exists f -> [f]
    | _ ->
      Sys.readdir oracle_dir |> Array.to_list
      |> List.filter (fun f ->
           Filename.check_suffix f "_oracle.mojo"
           || Filename.check_suffix f "_falsify_probe.mojo")
      |> List.sort compare
      |> List.map (Filename.concat oracle_dir) in
  (* Per file, so an arm is judged against ITS OWN module's pure functions.
     A probe is also generated per file: two oracles may both define
     `aligned`, and one probe importing both would collide. *)
  let per_file = List.map (fun f ->
    let src = read_file f in
    (f, pure_defs_of src, extract_arms f src)) files in
  let arms = List.concat_map (fun (_, _, a) -> a) per_file in
  (* B2 STAGED, NOT SHIPPED, 20261106-1230.
     Relaxing `analysable` to accept calls to locally-defined pure mirror
     functions WORKS -- enumerated rose 81 -> 148 and NOT_ANALYSED fell
     109 -> 42, and a hand-written probe confirmed the technique
     (span_timings_monotonic: 55 falsifying assignments). The pure-def
     discovery, the per-file probe generation and the module imports are all
     in this file and all function.
     It is NOT ENABLED because it produced 38 FALSE POSITIVES. Arms like
     `span_within_budget(1001, 200, 1000, 16, 16, 9, 1, 0, 64)` and
     `route_tier(True, False) == 0` pass ALL-LITERAL arguments to a mirror:
     they have no free variables, so enumeration finds no witness and the
     report called them unfalsifiable. They are sound -- conjunct-isolation
     tests, falsifiable by MUTATING THE MIRROR rather than by varying its
     inputs, which is what `mutation_probe` covers.
     Enabling it would make the gate permanently red on correct code, which
     is the inverted-polarity defect this instrument exists to find. The
     missing piece is a FIXED_VECTOR class: all-literal args to a mirror is
     a distinct verdict, neither falsifiable-by-enumeration nor a defect.
     Set `b2_enabled` to true once that class exists.

     20261106-1848: THAT CLASS NOW EXISTS, below, and B2 IS ENABLED. An arm
     whose predicate has NO free identifier once the mirror names are removed
     is never handed to the enumerator -- there is nothing to vary, so a
     witness count of 0 carries no information and calling it UNFALSIFIABLE
     was the instrument reporting its own inapplicability as the subject's
     defect. It is classified FIXED_VECTOR instead, and its soundness is
     referred to the evidence that actually bears on it: mutating the mirror.
     A FIXED_VECTOR arm is CORROBORATED only when
     var/mutation/mirror.json records a KILLED mutant for a mirror it calls;
     otherwise it stays an open question under a more precise name than
     NOT_ANALYSED. It is not promoted to a pass by the absence of evidence. *)
  let b2_enabled = true in
  (* ---- FIXED_VECTOR ---------------------------------------------------
     `free_idents` must be computed exactly as the emitter computes the loop
     variables, or an arm could be routed to the enumerator with zero loops
     (counting 0 witnesses, reported UNFALSIFIABLE) or held back from an
     enumeration that would have worked. The two formulas are the same
     expression deliberately. *)
  (* A `comptime` name is not a free variable: it is a literal with a name.
     Enumerating one asks "would this arm still hold if the expected catalog
     size were 3?", which is not a question the arm makes. Eleven
     conjunct-isolation arms in mcp_gateway_oracle read UNFALSIFIABLE for
     exactly that reason -- and over the varied domain the report was
     literally true, which is what makes it dangerous: `not
     gateway_aligned(True, True, True, 1, EXP_CATALOG_TARGETS, ...)` IS true
     for every value of EXP_CATALOG_TARGETS, by design, because the arm
     isolates a different conjunct. Acting on that verdict would have damaged
     eleven correct arms. A comptime-named literal therefore counts toward
     FIXED_VECTOR, not toward enumeration. *)
  let comptime_of (src : string) : string list =
    String.split_on_char '\n' src
    |> List.filter_map (fun l ->
         let t = String.trim l in
         if String.length t > 9 && String.sub t 0 9 = "comptime " then
           let rest = String.trim (String.sub t 9 (String.length t - 9)) in
           match String.index_opt rest ' ' with
           | Some k -> Some (String.sub rest 0 k)
           | None -> None
         else None)
    |> List.sort_uniq compare in
  (* ---- a mirror is ENUMERABLE only over Int and Bool -------------------
     `owned_in(name: Int, allowlist: String)` is pure, and the enumerator can
     only supply integers, so the generated probe died with "value passed to
     'allowlist' cannot be converted from 'Int' to 'String'". Five arms read
     NOT_RUN for that reason. The honest verdict is NOT_ANALYSED: this
     instrument cannot examine the arm, which is an open question about the
     arm and a stated limit of the tool -- not a failure of either. Reporting
     a tool's inapplicability as a subject's defect is the error this whole
     plane was built after. *)
  let enumerable_sig (src : string) (name : string) : bool =
    match find_sub src ("def " ^ name ^ "(") 0 with
    | None -> false
    | Some i ->
      let n = String.length src in
      let j = ref (i + String.length ("def " ^ name)) in
      let depth = ref 0 and stop = ref false in
      let buf = Buffer.create 128 in
      while not !stop && !j < n do
        (match src.[!j] with
         | '(' -> incr depth
         | ')' -> decr depth; if !depth = 0 then stop := true
         | c -> if !depth > 0 then Buffer.add_char buf c);
        incr j
      done;
      let params = Buffer.contents buf in
      (* every type annotation must be Int or Bool *)
      String.split_on_char ',' params
      |> List.for_all (fun p ->
           match String.index_opt p ':' with
           | None -> String.trim p = ""
           | Some k ->
             let t = String.trim (String.sub p (k + 1)
                                    (String.length p - k - 1)) in
             t = "Int" || t = "Bool") in
  let per_file =
    List.map (fun (f, pure, a) ->
      let src = read_file f in
      (f, List.filter (enumerable_sig src) pure, a)) per_file in
  let comptime_by_file =
    List.map (fun (f, _, _) -> (f, comptime_of (read_file f))) per_file in
  let consts_of (f : string) =
    try List.assoc f comptime_by_file with Not_found -> [] in
  let free_idents ?(file = "") (pure : string list) (pred : string)
    : string list =
    let consts = consts_of file in
    List.filter (fun v -> not (List.mem v pure) && not (List.mem v consts))
      (idents_of pred) in
  let calls_mirror (pure : string list) (pred : string) : string list =
    List.filter (fun fn -> List.mem fn (idents_of pred)) pure in
  let fixed_vector =
    List.concat_map (fun (f, pure, a) ->
      let pure = if b2_enabled then pure else [] in
      List.filter_map (fun x ->
        if analysable ~pure x.pred
           && free_idents ~file:f pure x.pred = []
           && calls_mirror pure x.pred <> []
        then Some (x, calls_mirror pure x.pred) else None) a) per_file in
  let is_fixed x = List.exists (fun (y, _) -> y == x) fixed_vector in
  let analysable_arms =
    List.concat_map (fun (_, pure, a) ->
      let pure = if b2_enabled then pure else [] in
      List.filter (fun x -> analysable ~pure x.pred && not (is_fixed x)) a)
      per_file in
  let unanalysed =
    List.concat_map (fun (_, pure, a) ->
      let pure = if b2_enabled then pure else [] in
      List.filter (fun x -> not (analysable ~pure x.pred)) a) per_file in
  ignore arms;
  (* arms with more than 3 free identifiers are not enumerated (combinatorial);
     reported as NOT_ANALYSED rather than passed *)
  let enumerable = analysable_arms in
  let too_wide = [] in
  (* One probe per source file. The arm indices are global, so the parsed
     results merge cleanly across probes. *)
  let tmp = Filename.temp_file "falsify" ".out" in
  let rc = ref 0 in
  let buf = Buffer.create 4096 in
  let base = ref 0 in
  List.iter (fun (f, pure, _) ->
    let mine = List.filter (fun a -> a.file = f)
                 (List.filteri (fun _ _ -> true) enumerable) in
    if mine <> [] then begin
      let modname = Filename.remove_extension (Filename.basename f) in
      (* only import the pure functions this file's arms actually call *)
      let used = List.filter (fun fn ->
        List.exists (fun a ->
          List.mem fn (idents_of a.pred)) mine) pure in
      let gen = Filename.concat oracle_dir
                  (Printf.sprintf "generated_falsify_%s.mojo" modname) in
      (* The comptime constants the arms actually mention are IMPORTED, so
         they carry their real values instead of being shadowed by a loop
         variable. Verified importable before relying on it:
         `from km_census_oracle import quoted_examples, DECLARED_WIKI_RAW`
         prints 1015. Excluding them from the loop without importing them is
         what left seven axis_registry arms at "use of unknown declaration
         'CASCADE_WIDTH'" -- a half-done fix is its own defect. *)
      let used_consts = List.filter (fun c ->
        List.exists (fun a -> List.mem c (idents_of a.pred)) mine)
        (consts_of f) in
      emit_mojo ~imports:[(modname, used @ used_consts)]
        ~consts:(consts_of f) ~offset:!base mine gen;
      let cmd = Printf.sprintf
        "./tools/mojo run -I %s %s > %s 2>&1"
        (Filename.quote oracle_dir) (Filename.quote gen)
        (Filename.quote tmp) in
      let r = Sys.command cmd in
      if r <> 0 then rc := r;
      if Sys.file_exists tmp then Buffer.add_string buf (read_file tmp);
      (* ADVANCE THE OFFSET. Without this every per-file probe emitted
         `ARM 0, ARM 1, ...` and the merged table kept only the last file's
         results -- which silently zeroed the six planted controls and made
         the detector report UNFALSIFIABLE 0 on a tree that still contained
         them. The detector's own negative control going quiet is the one
         failure it must never have, and it was caused by a missing
         increment. *)
      base := !base + List.length mine;
      (try Sys.remove gen with _ -> ())
    end) per_file;
  let rc = !rc in
  let out = Buffer.contents buf in
  (* parse "ARM <idx> <count>" *)
  let counts = Hashtbl.create 64 in
  String.split_on_char '\n' out
  |> List.iter (fun l ->
       match String.split_on_char ' ' (String.trim l)
             |> List.filter (fun x -> x <> "") with
       | ["ARM"; i; c] | ["WIDE"; i; c] ->
         (try Hashtbl.replace counts (int_of_string i) (int_of_string c)
          with _ -> ())
       | _ -> ());
  (* ---- SC-VP-04: probes that PIN a subject value ---------------------
     A control must survive a legitimate change in the subject. A probe whose
     predicate equates a DERIVED variable to a literal fails the moment the
     subject moves, which sets `vacuous` and makes the receipt VACUOUS -- the
     verdict that outranks every other -- so a reader sees "the oracle cannot
     discriminate" when the truth is "the subject moved and the oracle
     noticed". Worse, a genuine DIVERGENT is overwritten, because vacuity is
     tested first.
     Measured as FM-04, RPN 60, and detected by no instrument until now. This
     is a STATIC check: it reads the predicate's shape, because the defect is
     in the shape and not in any value. *)
  let pins_a_value (a : arm) : bool =
    a.kind = "mutation_probe"
    && (let p = a.pred in
        let n = String.length p in
        let rec go i =
          if i + 1 >= n then false
          else if p.[i] = '=' && p.[i+1] = '=' then begin
            (* a literal on either side of == is a pin *)
            let rec digits_from k dir =
              let k = ref k in
              let saw = ref false in
              (try
                 while !k >= 0 && !k < n do
                   let c = p.[!k] in
                   if c = ' ' then (k := !k + dir)
                   else if c >= '0' && c <= '9' then (saw := true; raise Exit)
                   else raise Exit
                 done
               with Exit -> ());
              !saw in
            if digits_from (i + 2) 1 || digits_from (i - 1) (-1) then true
            else go (i + 2)
          end else go (i + 1) in
        go 0) in
  let pinned = List.filter pins_a_value arms in
  (* These are CANDIDATES, not failures, and the exit code does not count
     them. Pinning a value is a defect only when the value comes from the
     SUBJECT; pinning a value derived from a FIXTURE THE ORACLE PLANTED
     ITSELF is correct, because a planted file's content cannot legitimately
     move. `proof_plane_guard`'s four probes assert `p_fix == 1` on a scratch
     tree it writes in the same function, and those are sound.
     The predicate's SHAPE cannot distinguish the two -- that needs the
     provenance of the variable -- so the honest output is a candidate list
     requiring adjudication. Failing the gate on them would make it
     permanently red on correct code, which is the inverted-polarity defect
     this instrument exists to find. *)
  if pinned <> [] then begin
    prerr_endline
      "  SC-VP-04 CANDIDATES -- probes pinning a value (adjudicate: fixture \
       pin = sound, subject pin = defect):";
    List.iter (fun a ->
      prerr_endline (Printf.sprintf "    %s:%d  %s"
        (Filename.basename a.file) a.line a.name)) pinned
  end;

  (* ---- SC-VP-06: bare r.world() calls without world_or_blind ----------
     A bare r.world() call has no presence predicate, so an absent file or
     unreadable command output cannot degrade to BLIND (FM-06b). Count every
     r.world( call across the inspected files so verification_plane_simulate
     and CI gates can detect bare world arms statically. *)
  let bare_world_count =
    List.fold_left (fun acc f ->
      let lines = String.split_on_char '\n' (read_file f) in
      let n = List.fold_left (fun k l ->
        match find_sub l "r.world(" 0 with
        | Some _ -> k + 1
        | None -> k) 0 lines in
      acc + n) 0 files in
  if bare_world_count > 0 then
    prerr_endline (Printf.sprintf
      "  SC-VP-06 BARE_WORLD -- %d bare r.world() arm(s) without world_or_blind"
      bare_world_count);

  let unfalsifiable = ref [] in
  let wide_unconfirmed = ref [] in
  let not_run = ref [] in
  List.iteri (fun idx a ->
    let narrow = List.length (idents_of a.pred) <= max_vars in
    match Hashtbl.find_opt counts idx with
    | Some 0 ->
      if narrow then unfalsifiable := a :: !unfalsifiable
      else wide_unconfirmed := a :: !wide_unconfirmed
    | Some _ -> ()
    (* NOT_RUN is its OWN category. Counting it as FALSIFIABLE was the
       absence-passes defect, inside the instrument built to find it: an arm
       whose probe never produced a result had been seen by nothing, and the
       report called it sound. *)
    | None -> not_run := a :: !not_run) enumerable;
  let unf = List.rev !unfalsifiable in
  (* ---- FIXED_VECTOR corroboration from mirror-mutation evidence --------
     The evidence file is read, never assumed. If it is missing, every
     FIXED_VECTOR arm is UNCORROBORATED -- which is the state they were in
     before this class existed, under the name NOT_ANALYSED. Treating a
     missing file as corroboration would be absence passing as evidence. *)
  let killed_mirrors =
    let p = "var/mutation/mirror.json" in
    if not (Sys.file_exists p) then []
    else begin
      let s = read_file p in
      match find_sub s "\"killed_ops\":[" 0 with
      | None -> []
      | Some i ->
        let j0 = i + String.length "\"killed_ops\":[" in
        (match find_sub s "]" j0 with
         | None -> []
         | Some j1 ->
           String.sub s j0 (j1 - j0)
           |> String.split_on_char ','
           |> List.filter_map (fun tok ->
                let tok = String.trim tok in
                let tok = String.concat "" (String.split_on_char '"' tok) in
                match String.index_opt tok ':' with
                | Some k -> Some (String.sub tok 0 k)
                | None -> if tok = "" then None else Some tok)
           |> List.sort_uniq compare)
    end in
  let fv_corrob, fv_open =
    List.partition (fun (_, mirrors) ->
      List.exists (fun m -> List.mem m killed_mirrors) mirrors) fixed_vector in
  if fixed_vector <> [] then begin
    prerr_endline (Printf.sprintf
      "  FIXED_VECTOR %d arms (all-literal args to a mirror: nothing to \
       enumerate)\n    corroborated by mirror mutation: %d | open: %d \
       (evidence lists %d killed mirrors)"
      (List.length fixed_vector) (List.length fv_corrob)
      (List.length fv_open) (List.length killed_mirrors));
    List.iter (fun (a, ms) ->
      prerr_endline (Printf.sprintf "    OPEN  %s:%d  %s  [%s]"
        (Filename.basename a.file) a.line a.name (String.concat " " ms)))
      fv_open
  end;
  (* report *)
  prerr_endline "  verdict        file:line  arm";
  prerr_endline "  -------------- ---------- ---------------------------------";
  List.iteri (fun idx a ->
    let v = match Hashtbl.find_opt counts idx with
      | Some 0 -> "UNFALSIFIABLE"
      | Some _ -> "FALSIFIABLE"
      | None -> "NOT_RUN" in
    if v <> "FALSIFIABLE" then
      prerr_endline (Printf.sprintf "  %-14s %s:%d  %s" v
        (Filename.basename a.file) a.line a.name)) enumerable;
  prerr_endline (Printf.sprintf
    "\n  enumerated %d | FALSIFIABLE %d | UNFALSIFIABLE %d | NOT_RUN %d\n  \
     NOT_ANALYSED %d (call/field/index) + %d (wide, no witness)\n  \
     mojo exit %d"
    (List.length enumerable)
    (List.length enumerable - List.length unf
       - List.length !wide_unconfirmed - List.length !not_run)
    (List.length unf) (List.length !not_run) (List.length unanalysed)
    (List.length !wide_unconfirmed) rc);
  ignore too_wide;
  prerr_endline
    "  NOT_ANALYSED is an OPEN QUESTION, never a pass. Bounded enumeration is \
     evidence, not a proof.";
  Printf.printf
    "{\"schema\":\"uos.mojo-arm-falsifiability.v1\",\"enumerated\":%d,\
     \"unfalsifiable\":%d,\"pinned_probes\":%d,\"bare_world_arms\":%d,\
     \"fixed_vector\":%d,\"fixed_vector_corroborated\":%d,\
     \"fixed_vector_open\":%d,\
     \"not_analysed_call\":%d,\"not_analysed_wide\":%d,\
     \"arms\":["
    (List.length enumerable) (List.length unf) (List.length pinned) bare_world_count
    (List.length fixed_vector) (List.length fv_corrob) (List.length fv_open)
    (List.length unanalysed)
    (List.length too_wide + List.length !not_run);
  List.iteri (fun i a ->
    Printf.printf "%s{\"file\":%S,\"line\":%d,\"kind\":%S,\"name\":%S}"
      (if i = 0 then "" else ",") a.file a.line a.kind a.name) unf;
  print_string "],\"authority\":\"NONE\",\"ev_ceiling\":93}\n";
  (try Sys.remove tmp with _ -> ());
  exit (if unf = [] && !not_run = [] then 0 else 1)
