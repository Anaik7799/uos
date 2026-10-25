(** Lint Gospel [(*@ ... *)] specifications in OCaml [.mli] files.

    Fractal RCA: a finding is reported at the level where the defect is
    introduced, not where gospel happens to notice it. Gospel collapses almost
    everything to "Syntax error" at a column, which names the symptom.

    - [L1] lexical: a token that cannot be what it is (reserved word as an
      identifier). Root cause: a name drawn from OCaml vocabulary without
      consulting Gospel's keyword table.
    - [L2] syntactic: a clause well-formed but illegal in this block kind, or a
      labelled application in a term. Root cause: clause grammar is per kind.
    - [L3] scope: a name used where it is not bound. Root cause: Gospel's
      scoping is not OCaml's.
    - [L4] type: a term that parses and resolves but cannot type.
    - [L5] environment: the file is fine but cannot be checked here. Never a
      specification defect.

    Stage two runs [gospel check] on a temp copy and is authoritative: the
    static rules name causes, gospel decides truth. A file is never reported OK
    without it.

    Zero dependencies beyond [unix]: no regex engine, so the scanning is
    explicit. That keeps the linter installable in any switch, including ones
    where a ppx or regex library will not build. *)

(* ---------------------------------------------------------------- surface *)

(** Authoritative: gospel 0.3.1 [lib/gospel/ulexer.ml] keyword table. *)
let reserved =
  [ "as"; "axiom"; "coercion"; "else"; "exists"; "false"; "forall"; "function";
    "if"; "in"; "invariant"; "let"; "match"; "not"; "predicate"; "then"; "true";
    "with"; "mutable"; "ensures"; "consumes"; "fun"; "old"; "raises"; "rec";
    "requires"; "variant"; "modifies"; "equivalent"; "checks"; "diverges";
    "pure"; "ephemeral"; "model"; "when" ]

let is_reserved word = List.mem word reserved

(* Clause vocabulary per block kind, from uast.mli (val_spec, type_spec,
   fun_spec). Using a clause outside its kind is the L2 failure. *)
let val_clauses =
  [ "requires"; "checks"; "ensures"; "raises"; "modifies"; "consumes";
    "diverges"; "pure"; "equivalent" ]

let type_clauses = [ "ephemeral"; "model"; "invariant"; "mutable"; "with" ]
let function_clauses = [ "requires"; "ensures"; "variant"; "coercion" ]

(* Words that begin a clause line. The header/clause split uses these
   regardless of block kind, so a clause illegal *for that kind* still lands in
   the clause region where it can be named, instead of being mistaken for a
   header token. "with" and "mutable" are excluded: `with` also occurs inside
   `match ... with` terms. *)
let clause_starters =
  val_clauses @ function_clauses @ [ "invariant"; "model"; "ephemeral" ]

(** Modules gospel resolves with no project context. *)
let stdlib_modules =
  [ "List"; "Array"; "String"; "Bytes"; "Char"; "Int"; "Float"; "Bool";
    "Option"; "Result"; "Seq"; "Set"; "Map"; "Hashtbl"; "Buffer"; "Queue";
    "Stack"; "Sys"; "Fun"; "Either"; "Lazy"; "Printf"; "Format";
    "Gospelstdlib" ]

(* ------------------------------------------------------------------ types *)

type level = L1 | L2 | L3 | L4 | L5

let level_name = function
  | L1 -> "L1" | L2 -> "L2" | L3 -> "L3" | L4 -> "L4" | L5 -> "L5"

type finding = {
  rule : string;
  level : level;
  line : int;
  (* 1-based column of the offending token, or 0 when the defect is a property
     of the whole construct rather than of one token. *)
  column : int;
  (* Caret width, so the excerpt underlines the token itself rather than
     pointing vaguely at a line. *)
  width : int;
  (* What the reader was writing when the rule fired: "val specification for
     `build`", "axiom `f_idem`". A diagnostic that names the construct is
     actionable; one that names only a line number sends you hunting. *)
  context : string;
  message : string;
  cause : string;
  fix : string;
}

let finding ?(column = 0) ?(width = 0) ?(context = "") ~rule ~level ~line ~message
    ~cause ~fix () =
  { rule; level; line; column; width; context; message; cause; fix }

type kind = Val | Type_ | Function_ | Axiom | Ghost | Continuation

let kind_name = function
  | Val -> "val" | Type_ -> "type" | Function_ -> "function"
  | Axiom -> "axiom" | Ghost -> "ghost" | Continuation -> "continuation"

type block = {
  body : string;
  start : int;
  line : int;
  kind : kind;
  header : string;
  clauses : string;
}

type verdict =
  | Verdict_ok
  | Verdict_errors
  | Verdict_not_checkable
  | Verdict_unavailable
  | Verdict_internal

let exit_code = function
  | Verdict_ok -> 0
  | Verdict_errors -> 1
  | Verdict_not_checkable -> 2
  | Verdict_unavailable -> 3
  | Verdict_internal -> 4

(* A diagnostic is only useful if the reader can see what it is pointing at.
   gospel's own output is a bare "Syntax error" plus a column, which is the
   symptom with no construct and no excerpt. This shows the offending line,
   underlines the token, names the construct it sits in, and separates the
   root cause from the fix. *)
let render_finding ?source path (finding : finding) =
  let header =
    if finding.column > 0 then
      Printf.sprintf "%s:%d:%d: [%s/%s] %s" path finding.line finding.column
        (level_name finding.level) finding.rule finding.message
    else
      Printf.sprintf "%s:%d: [%s/%s] %s" path finding.line
        (level_name finding.level) finding.rule finding.message
  in
  let excerpt =
    match source with
    | None -> ""
    | Some text -> (
        let lines = String.split_on_char '\n' text in
        match List.nth_opt lines (finding.line - 1) with
        | None -> ""
        | Some line ->
            let gutter = Printf.sprintf "%4d | " finding.line in
            let blank = String.make (String.length gutter - 2) ' ' ^ "| " in
            if finding.column <= 0 then Printf.sprintf "\n%s%s" gutter line
            else
              let pad = String.make (max 0 (finding.column - 1)) ' ' in
              let caret = String.make (max 1 finding.width) '^' in
              Printf.sprintf "\n%s%s\n%s%s%s" gutter line blank pad caret)
  in
  let context =
    if finding.context = "" then "" else Printf.sprintf "\n    in: %s" finding.context
  in
  Printf.sprintf "%s%s%s\n    root cause: %s\n    fix: %s" header excerpt context
    finding.cause finding.fix

(* -------------------------------------------------------------- scanning *)

let is_ident_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '_' || c = '\''

let is_ident_start c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'

let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r'

(** Does [text] contain [pattern] starting exactly at [index]? *)
let matches_at text index pattern =
  let length = String.length pattern in
  index >= 0
  && index + length <= String.length text
  && String.sub text index length = pattern

(** A word occurrence is one not glued to a neighbouring identifier
    character, so "pure" does not match inside "purely". *)
let is_word_boundary text index word =
  let before = index = 0 || not (is_ident_char text.[index - 1]) in
  let stop = index + String.length word in
  let after = stop >= String.length text || not (is_ident_char text.[stop]) in
  before && after

let find_word text word ~from =
  let limit = String.length text - String.length word in
  let rec loop index =
    if index > limit then None
    else if matches_at text index word && is_word_boundary text index word then
      Some index
    else loop (index + 1)
  in
  if String.length word = 0 then None else loop (max 0 from)

let contains_word text word = find_word text word ~from:0 <> None

(** All identifiers in [text], in order. *)
let identifiers text =
  let length = String.length text in
  let rec loop index acc =
    if index >= length then List.rev acc
    else if is_ident_start text.[index] then begin
      let stop = ref index in
      while !stop < length && is_ident_char text.[!stop] do incr stop done;
      loop !stop (String.sub text index (!stop - index) :: acc)
    end
    else loop (index + 1) acc
  in
  loop 0 []

let line_of text index =
  let bound = min index (String.length text) in
  let count = ref 1 in
  for position = 0 to bound - 1 do
    if text.[position] = '\n' then incr count
  done;
  !count

(** 1-based column of a byte offset. *)
let column_of text offset =
  let bound = min offset (String.length text) in
  let rec back index = if index <= 0 then 0 else if text.[index - 1] = '\n' then index else back (index - 1) in
  bound - back bound + 1

let split_lines text = String.split_on_char '\n' text

let trim = String.trim

(** Scan [(*@ ... *)] blocks.

    A naive search for the closing delimiter mis-handles one that appears
    inside a string literal, which [equivalent "a ... b"] makes reachable, so
    this tracks string state and nested comment depth. *)
let scan_blocks text =
  let length = String.length text in
  let blocks = ref [] in
  let index = ref 0 in
  while !index < length - 2 do
    if matches_at text !index "(*@" then begin
      let start = !index + 3 in
      let cursor = ref start in
      let depth = ref 1 in
      let in_string = ref false in
      let finished = ref false in
      while (not !finished) && !cursor < length do
        let char = text.[!cursor] in
        if !in_string then
          if char = '\\' then cursor := !cursor + 2
          else begin
            if char = '"' then in_string := false;
            incr cursor
          end
        else if char = '"' then begin
          in_string := true;
          incr cursor
        end
        else if matches_at text !cursor "(*" then begin
          incr depth;
          cursor := !cursor + 2
        end
        else if matches_at text !cursor "*)" then begin
          decr depth;
          if !depth = 0 then finished := true else cursor := !cursor + 2
        end
        else incr cursor
      done;
      let stop = min !cursor length in
      blocks := (String.sub text start (stop - start), start) :: !blocks;
      index := stop + 2
    end
    else incr index
  done;
  List.rev !blocks

(** First word of a block body, used to classify it. *)
let first_word body =
  match identifiers body with [] -> "" | word :: _ -> word

(** Index of the earliest clause keyword that begins a line. *)
let earliest_clause body =
  let length = String.length body in
  let best = ref length in
  List.iter
    (fun word ->
      let rec loop from =
        match find_word body word ~from with
        | None -> ()
        | Some index ->
            (* Anchored to a line start, modulo leading blanks. *)
            let rec back position =
              if position = 0 then true
              else if body.[position - 1] = '\n' then true
              else if body.[position - 1] = ' ' || body.[position - 1] = '\t' then
                back (position - 1)
              else false
            in
            if back index then (if index < !best then best := index)
            else loop (index + 1)
      in
      loop 0)
    clause_starters;
  !best

let classify body =
  let word = first_word body in
  if word = "axiom" then (Axiom, trim body, "")
  else if word = "val" || word = "type" || word = "open" then
    (Ghost, trim body, "")
  else
    let kind =
      if word = "function" || word = "predicate" then Function_
      else if word = "with" || word = "model" || word = "mutable"
              || word = "ephemeral" then Type_
      else if is_reserved word then Continuation
      else Val
    in
    match kind with
    | Continuation -> (Continuation, "", body)
    | _ ->
        let cut = earliest_clause body in
        (kind, String.sub body 0 cut, String.sub body cut (String.length body - cut))

let parse text =
  List.map
    (fun (body, start) ->
      let kind, header, clauses = classify body in
      { body; start; line = line_of text start; kind; header; clauses })
    (scan_blocks text)

(** Name the construct a finding sits in, e.g. "val specification for `build`".
    Naming the subject is what turns a location into a diagnostic. *)
let describe_block block =
  let subject =
    match block.kind with
    | Axiom -> (
        (* "axiom name: term" -- the identifier after the keyword. *)
        match identifiers block.header with _ :: name :: _ -> name | _ -> "")
    | Function_ ->
        (* "function rec f (x: t) = ..." -- the name is the first identifier
           that is not one of the leading keywords. *)
        let rec first = function
          | word :: rest
            when word = "function" || word = "predicate" || word = "rec" ->
              first rest
          | word :: _ -> word
          | [] -> ""
        in
        first (identifiers block.header)
    | Val -> (
        match String.index_opt block.header '=' with
        | Some position -> (
            let after =
              String.sub block.header (position + 1)
                (String.length block.header - position - 1)
            in
            match identifiers after with name :: _ -> name | [] -> "")
        | None -> ( match identifiers block.header with name :: _ -> name | [] -> ""))
    | Type_ | Ghost | Continuation -> ""
  in
  let what =
    match block.kind with
    | Val -> "val specification"
    | Type_ -> "type specification"
    | Function_ -> "function specification"
    | Axiom -> "axiom"
    | Ghost -> "ghost declaration"
    | Continuation -> "clause block"
  in
  if subject = "" then what
  else if block.kind = Axiom then Printf.sprintf "axiom `%s`" subject
  else Printf.sprintf "%s for `%s`" what subject

(* ------------------------------------------------------- declaration reads *)

(** Split "val name : type" into (name, type) when the line is one. *)
let val_declaration line =
  let trimmed = trim line in
  if not (matches_at trimmed 0 "val") then None
  else if String.length trimmed <= 3 || is_ident_char trimmed.[3] then None
  else
    match String.index_opt trimmed ':' with
    | None -> None
    | Some colon ->
        let between = String.sub trimmed 3 (colon - 3) in
        (match identifiers between with
        | [ name ] ->
            Some (name, String.sub trimmed (colon + 1)
                          (String.length trimmed - colon - 1))
        | _ -> None)

(** Split "type name rest" into (name, rest) when the line is one. *)
let type_declaration line =
  let trimmed = trim line in
  if not (matches_at trimmed 0 "type") then None
  else if String.length trimmed <= 4 || is_ident_char trimmed.[4] then None
  else
    let rest = String.sub trimmed 4 (String.length trimmed - 4) in
    (* Skip type parameters such as 'a. *)
    let cursor = ref 0 in
    let length = String.length rest in
    let continue_ = ref true in
    while !continue_ do
      while !cursor < length && is_space rest.[!cursor] do incr cursor done;
      if !cursor < length && rest.[!cursor] = '\'' then begin
        incr cursor;
        while !cursor < length && is_ident_char rest.[!cursor] do incr cursor done
      end
      else continue_ := false
    done;
    if !cursor >= length || not (is_ident_start rest.[!cursor]) then None
    else begin
      let start = !cursor in
      while !cursor < length && is_ident_char rest.[!cursor] do incr cursor done;
      Some (String.sub rest start (!cursor - start),
            String.sub rest !cursor (length - !cursor))
    end

(** Labels in a val's type: bare ("model:string") in a declaration, or carrying
    ~ / ? at a call site. All three forms are matched so a reserved label is
    caught where it is declared. *)
let labels_in_type text =
  let length = String.length text in
  let found = ref [] in
  let index = ref 0 in
  while !index < length do
    if text.[!index] = ':' then begin
      (* Walk back over the identifier preceding the colon. *)
      let stop = ref !index in
      while !stop > 0 && is_space text.[!stop - 1] do decr stop done;
      let finish = !stop in
      while !stop > 0 && is_ident_char text.[!stop - 1] do decr stop done;
      if finish > !stop && is_ident_start text.[!stop] then
        found := String.sub text !stop (finish - !stop) :: !found
    end;
    incr index
  done;
  List.rev !found

(** Names bound by forall/exists, i.e. the "x" in "forall x: t." *)
let quantifier_binders body =
  let found = ref [] in
  List.iter
    (fun quantifier ->
      let rec loop from =
        match find_word body quantifier ~from with
        | None -> ()
        | Some index ->
            let start = index + String.length quantifier in
            let stop =
              match String.index_from_opt body start '.' with
              | None -> String.length body
              | Some position -> position
            in
            let segment = String.sub body start (stop - start) in
            List.iter
              (fun name -> found := name :: !found)
              (labels_in_type segment);
            loop stop
      in
      loop 0)
    [ "forall"; "exists" ];
  List.rev !found

(** Does a clause keyword begin a line of [clauses]? *)
let clause_present clauses word =
  let rec loop from =
    match find_word clauses word ~from with
    | None -> false
    | Some index ->
        let rec back position =
          if position = 0 then true
          else if clauses.[position - 1] = '\n' then true
          else if clauses.[position - 1] = ' ' || clauses.[position - 1] = '\t'
          then back (position - 1)
          else false
        in
        if back index then true else loop (index + 1)
  in
  loop 0

(* ------------------------------------------------------------------ rules *)

let rule_reserved_label text _blocks =
  let findings = ref [] in
  List.iteri
    (fun offset line ->
      match val_declaration line with
      | None -> ()
      | Some (name, type_text) ->
          List.iter
            (fun label ->
              if is_reserved label then
                let column =
                  match find_word line label ~from:0 with
                  | Some index -> index + 1
                  | None -> 0
                in
                findings :=
                  finding ~rule:"reserved-label" ~level:L1 ~line:(offset + 1)
                    ~column ~width:(String.length label)
                    ~context:(Printf.sprintf "declaration of `%s`" name)
                    ~message:
                      (Printf.sprintf
                         "OCaml label ~%s is a Gospel keyword, so this value can \
                          never carry a specification" label)
                    ~cause:
                      "Gospel's lexer tokenises the keyword before it can be an \
                       identifier; there is no escaping syntax"
                    ~fix:(Printf.sprintf "rename the label, e.g. ~%s_id" label)
                    ()
                  :: !findings)
            (labels_in_type type_text))
    (split_lines text);
  List.rev !findings

let rule_reserved_identifier text blocks =
  let findings = ref [] in
  List.iter
    (fun block ->
      (* Only a val spec header binds parameter names. A function or predicate
         block uses definition syntax where `rec` is legitimate. *)
      if block.kind = Val then begin
        let subject =
          match String.index_opt block.header '=' with
          | None -> block.header
          | Some position ->
              String.sub block.header (position + 1)
                (String.length block.header - position - 1)
        in
        match identifiers subject with
        | [] -> ()
        | _ :: arguments ->
            List.iter
              (fun token ->
                if is_reserved token then
                  let offset =
                    match find_word block.body token ~from:0 with
                    | Some index -> block.start + index
                    | None -> block.start
                  in
                  findings :=
                    finding ~rule:"reserved-identifier" ~level:L1
                      ~line:(line_of text offset) ~column:(column_of text offset)
                      ~width:(String.length token) ~context:(describe_block block)
                      ~message:
                        (Printf.sprintf
                           "'%s' is a Gospel keyword and cannot name a \
                            specification parameter" token)
                      ~cause:
                        "the spec header binds names in Gospel's namespace, not \
                         OCaml's"
                      ~fix:
                        "rename the parameter in both the spec header and the val"
                      ()
                    :: !findings)
              arguments
      end;
      (* Quantifiers bind names in every block kind, axioms included. *)
      List.iter
        (fun name ->
          if is_reserved name then
            let offset =
              match find_word block.body name ~from:0 with
              | Some index -> block.start + index
              | None -> block.start
            in
            findings :=
              finding ~rule:"reserved-identifier" ~level:L1
                ~line:(line_of text offset) ~column:(column_of text offset)
                ~width:(String.length name) ~context:(describe_block block)
                ~message:
                  (Printf.sprintf
                     "'%s' is a Gospel keyword and cannot be a quantifier binder"
                     name)
                ~cause:"quantifier binders share the keyword namespace"
                ~fix:"rename the bound variable" ()
              :: !findings)
        (quantifier_binders block.body))
    blocks;
  List.rev !findings

let rule_clause_kind text blocks =
  let findings = ref [] in
  List.iter
    (fun block ->
      let permitted =
        match block.kind with
        | Val -> Some val_clauses
        | Function_ -> Some function_clauses
        | Type_ -> Some type_clauses
        | Axiom | Ghost | Continuation -> None
      in
      match permitted with
      | None -> ()
      | Some permitted ->
          List.iter
            (fun word ->
              if (not (List.mem word permitted)) && clause_present block.clauses word
              then
                let offset =
                  match find_word block.body word ~from:0 with
                  | Some index -> block.start + index
                  | None -> block.start
                in
                let accepted =
                  List.filter
                    (fun (name, clauses) -> ignore name; List.mem word clauses)
                    [ ("val", val_clauses); ("type", type_clauses);
                      ("function", function_clauses) ]
                  |> List.map fst
                in
                findings :=
                  finding ~rule:"clause-not-in-kind" ~level:L2
                    ~line:(line_of text offset) ~column:(column_of text offset)
                    ~width:(String.length word) ~context:(describe_block block)
                    ~message:
                      (Printf.sprintf "'%s' is not a clause of a %s specification"
                         word (kind_name block.kind))
                    ~cause:
                      (Printf.sprintf
                         "Gospel's clause vocabulary is per block kind; '%s' \
                          belongs to %s" word
                         (if accepted = [] then "no block kind"
                          else String.concat " or " accepted ^ " specifications"))
                    ~fix:
                      (Printf.sprintf
                         "move it to a block kind that accepts '%s', or drop it"
                         word)
                    ()
                  :: !findings)
            clause_starters)
    blocks;
  List.rev !findings

let rule_self_reference text blocks =
  let findings = ref [] in
  List.iter
    (fun block ->
      if block.kind = Val && String.contains block.header '=' then
        let position = String.index block.header '=' in
        let subject =
          String.sub block.header (position + 1)
            (String.length block.header - position - 1)
        in
        match identifiers subject with
        | [] -> ()
        | name :: _ ->
            if contains_word block.clauses name then
              let offset =
                match find_word block.clauses name ~from:0 with
                | Some index ->
                    block.start + (String.length block.body - String.length block.clauses)
                    + index
                | None -> block.start
              in
              findings :=
                finding ~rule:"self-reference" ~level:L3 ~line:(line_of text offset)
                  ~column:(column_of text offset) ~width:(String.length name)
                  ~context:(describe_block block)
                  ~message:
                    (Printf.sprintf
                       "'%s' is referenced inside its own specification, where it \
                        is not bound" name)
                  ~cause:
                    "Gospel adds a value to the logical namespace only after its \
                     specification is closed"
                  ~fix:
                    (Printf.sprintf
                       "mark it `pure`, then state the property as a top-level \
                        axiom after the val: (*@ axiom %s_prop: forall ... *)" name)
                  ()
                :: !findings)
    blocks;
  List.rev !findings

let rule_labelled_application text blocks =
  let findings = ref [] in
  List.iter
    (fun block ->
      let clauses = block.clauses in
      let base = block.start + String.length block.body - String.length clauses in
      let length = String.length clauses in
      for index = 0 to length - 1 do
        if
          clauses.[index] = '~'
          && index + 1 < length
          && is_ident_start clauses.[index + 1]
        then begin
          let stop = ref (index + 1) in
          while !stop < length && is_ident_char clauses.[!stop] do incr stop done;
          let after = ref !stop in
          while !after < length && (clauses.[!after] = ' ' || clauses.[!after] = '\t')
          do incr after done;
          if !after < length && clauses.[!after] = ':' then
            let label = String.sub clauses (index + 1) (!stop - index - 1) in
            findings :=
              finding ~rule:"labelled-application" ~level:L2
                ~line:(line_of text (base + index))
                ~column:(column_of text (base + index))
                ~width:(!stop - index + 1) ~context:(describe_block block)
                ~message:
                  (Printf.sprintf "~%s: applies a labelled function inside a term"
                     label)
                ~cause:
                  "Gospel's term grammar has no labelled-application production; \
                   labels exist only in the spec header"
                ~fix:
                  "state the obligation as a property test and say so in the doc \
                   comment rather than dropping it silently"
                ()
              :: !findings
        end
      done)
    blocks;
  List.rev !findings

let rule_integer_over_int text blocks =
  let int_valued =
    List.filter_map
      (fun line ->
        match val_declaration line with
        | Some (name, type_text) when contains_word type_text "int" -> Some name
        | _ -> None)
      (split_lines text)
  in
  if int_valued = [] then []
  else
    let findings = ref [] in
    List.iter
      (fun block ->
        if block.kind = Axiom && contains_word block.body "integer" then begin
          let applied = identifiers block.body in
          let overlap =
            List.sort_uniq compare
              (List.filter (fun name -> List.mem name applied) int_valued)
          in
          if overlap <> [] then
            findings :=
              (let offset =
                 match find_word block.body "integer" ~from:0 with
                 | Some index -> block.start + index
                 | None -> block.start
               in
               finding ~rule:"integer-over-int" ~level:L4
                 ~line:(line_of text offset) ~column:(column_of text offset)
                 ~width:(String.length "integer") ~context:(describe_block block)
                 ~message:
                   (Printf.sprintf
                      "quantifies with `integer` over %s, which take OCaml `int`"
                      (String.concat ", " overlap))
                 ~cause:
                   "`integer` is Gospel's unbounded arithmetic type; it does not \
                    unify with the machine `int` in the val's OCaml type"
                 ~fix:"quantify with `int`, or restate the val over `integer`" ())
              :: !findings
        end)
      blocks;
    List.rev !findings

(** Does the type end in "-> unit"? *)
let returns_unit type_text =
  let trimmed = trim type_text in
  let length = String.length trimmed in
  length >= 4
  && String.sub trimmed (length - 4) 4 = "unit"
  && (length = 4 || not (is_ident_char trimmed.[length - 5]))

let rule_consumes_unit text blocks =
  let unit_valued =
    List.filter_map
      (fun line ->
        match val_declaration line with
        | Some (name, type_text) when returns_unit type_text -> Some name
        | _ -> None)
      (split_lines text)
  in
  let findings = ref [] in
  List.iter
    (fun block ->
      if block.kind = Val && clause_present block.clauses "consumes" then
        let subject =
          match String.index_opt block.header '=' with
          | None -> block.header
          | Some position ->
              String.sub block.header (position + 1)
                (String.length block.header - position - 1)
        in
        match identifiers subject with
        | name :: _ when List.mem name unit_valued ->
            findings :=
              (let offset =
                 match find_word block.body "consumes" ~from:0 with
                 | Some index -> block.start + index
                 | None -> block.start
               in
               finding ~rule:"consumes-unit" ~level:L4 ~line:(line_of text offset)
                 ~column:(column_of text offset) ~width:(String.length "consumes")
                 ~context:(describe_block block)
                 ~message:
                   (Printf.sprintf "`consumes` on '%s', which returns unit" name)
                 ~cause:"gospel rejects this with 'The function ... returns unit'"
                 ~fix:"drop `consumes`, or give the value a non-unit result" ())
              :: !findings
        | _ -> ())
    blocks;
  List.rev !findings

let rule_public_invariant text blocks =
  let lines = Array.of_list (split_lines text) in
  let findings = ref [] in
  List.iter
    (fun block ->
      if contains_word block.body "invariant" then begin
        let index = ref (block.line - 2) in
        let settled = ref false in
        while (not !settled) && !index >= 0 do
          (match type_declaration lines.(!index) with
          | Some (_, rest) ->
              settled := true;
              if String.contains rest '=' then
                findings :=
                  (let offset =
                     match find_word block.body "invariant" ~from:0 with
                     | Some index -> block.start + index
                     | None -> block.start
                   in
                   let type_name =
                     match type_declaration lines.(!index + 1) with
                     | Some (name, _) -> name
                     | None -> ""
                   in
                   finding ~rule:"public-invariant" ~level:L4
                     ~line:(line_of text offset) ~column:(column_of text offset)
                     ~width:(String.length "invariant")
                     ~context:
                       (if type_name = "" then "type specification"
                        else Printf.sprintf "invariant on type `%s`" type_name)
                     ~message:
                       (if type_name = "" then "invariant attached to a public type"
                        else
                          Printf.sprintf
                            "invariant attached to `%s`, whose representation is \
                             public" type_name)
                     ~cause:
                       "gospel can only attach an invariant where the \
                        representation is hidden, so it reports 'Invariant on \
                        public type'"
                     ~fix:"make the type abstract and expose a (*@ model ... *)" ())
                  :: !findings
          | None -> ());
          decr index
        done
      end)
    blocks;
  List.rev !findings

(* A ref, not a constant: the test suite injects a deliberately crashing rule
   to prove that a linter failure surfaces as an unreliable verdict rather than
   a silent pass. *)
let rules : (string * (string -> block list -> finding list)) list ref =
  ref
  [ ("reserved-label", rule_reserved_label);
    ("reserved-identifier", rule_reserved_identifier);
    ("clause-not-in-kind", rule_clause_kind);
    ("self-reference", rule_self_reference);
    ("labelled-application", rule_labelled_application);
    ("integer-over-int", rule_integer_over_int);
    ("consumes-unit", rule_consumes_unit);
    ("public-invariant", rule_public_invariant) ]

(** Run every rule. A rule that raises is reported, never swallowed: a linter
    whose own verdict is unreliable must say so. *)
let static_findings text =
  let blocks = parse text in
  List.concat_map
    (fun (name, rule) ->
      match rule text blocks with
      | findings -> findings
      | exception exn ->
          [ finding ~rule:"linter-internal" ~level:L5 ~line:1
              ~context:"the linter itself"
              ~message:
                (Printf.sprintf "rule %s raised %s" name (Printexc.to_string exn))
              ~cause:
                "the linter itself failed; its verdict on this file is unreliable"
              ~fix:"report this input as a linter bug" () ])
    !rules

let external_modules text =
  let modules = ref [] in
  List.iter
    (fun line ->
      match val_declaration line with
      | None -> ()
      | Some (_, type_text) ->
          let length = String.length type_text in
          for index = 0 to length - 1 do
            if
              type_text.[index] >= 'A'
              && type_text.[index] <= 'Z'
              && (index = 0
                  || (type_text.[index - 1] <> '.'
                      && not (is_ident_char type_text.[index - 1])))
            then begin
              let stop = ref index in
              while !stop < length && is_ident_char type_text.[!stop] do incr stop done;
              if !stop < length && type_text.[!stop] = '.' then
                let name = String.sub type_text index (!stop - index) in
                if not (List.mem name stdlib_modules) then
                  modules := name :: !modules
            end
          done)
    (split_lines text);
  List.sort_uniq compare !modules

(* -------------------------------------------------------------- authority *)

let executable_exists path =
  match Unix.access path [ Unix.X_OK ] with
  | () -> true
  | exception Unix.Unix_error _ -> false

(* Split out so the unset-PATH case is directly testable: OCaml cannot remove a
   variable from the environment, only blank it. *)
let search_path path_value name =
  match path_value with
  | None -> None
  | Some path ->
      List.find_opt
        (fun directory -> executable_exists (Filename.concat directory name))
        (String.split_on_char ':' path)
      |> Option.map (fun directory -> Filename.concat directory name)

let find_in_path name = search_path (Sys.getenv_opt "PATH") name

let find_gospel () =
  let configured =
    List.find_map
      (fun variable ->
        match Sys.getenv_opt variable with
        | Some value when trim value <> "" && executable_exists value -> Some value
        | _ -> None)
      [ "HERMES_GOSPEL"; "GOSPEL_BIN" ]
  in
  match configured with
  | Some path -> Some path
  | None -> (
      match find_in_path "gospel" with
      | Some path -> Some path
      | None ->
          let fallback =
            Filename.concat (Sys.getenv_opt "HOME" |> Option.value ~default:"")
              ".opam/gospel-check/bin/gospel"
          in
          if executable_exists fallback then Some fallback else None)

(** Directories passed to gospel as [-L]. GOSPEL_LOAD_PATH holds checking-only
    stubs for modules gospel cannot resolve on its own. A stub must be weaker
    than the interface it stands in for -- an abstract type gives gospel fewer
    facts -- so it can cause a false rejection but never a false acceptance. *)
let load_path () =
  match Sys.getenv_opt "GOSPEL_LOAD_PATH" with
  | None -> []
  | Some value ->
      String.split_on_char ':' value
      |> List.filter (fun directory ->
             trim directory <> "" && Sys.file_exists directory)

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let copy_file source target =
  let contents = read_file source in
  let channel = open_out_bin target in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel contents)

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Array.iter (fun name -> remove_tree (Filename.concat path name))
        (Sys.readdir path);
      Unix.rmdir path
    end
    else Sys.remove path

let temp_directory () =
  let path = Filename.temp_file "gospel-lint-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

(** Check a copy: gospel writes a [.gospel] sidecar beside its input, so an
    in-tree interface must never be handed to it directly. *)
let run_gospel path =
  match find_gospel () with
  | None -> Error "gospel binary not found (set HERMES_GOSPEL or GOSPEL_BIN)"
  | Some binary -> (
      let staging = temp_directory () in
      Fun.protect
        ~finally:(fun () -> remove_tree staging)
        (fun () ->
          try
            let base =
              let name = Filename.basename path in
              if name = "" then "input.mli" else name
            in
            let staged = Filename.concat staging base in
            copy_file path staged;
            let output_path = Filename.concat staging "gospel.out" in
            let output =
              Unix.openfile output_path [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o600
            in
            let devnull = Unix.openfile Filename.null [ Unix.O_RDONLY ] 0o400 in
            let arguments =
              Array.of_list
                ([ binary; "check" ]
                @ List.concat_map (fun directory -> [ "-L"; directory ]) (load_path ())
                @ [ staged ])
            in
            let pid = Unix.create_process binary arguments devnull output output in
            Unix.close output;
            Unix.close devnull;
            let _, status = Unix.waitpid [] pid in
            let text = try read_file output_path with _ -> "" in
            let code =
              match status with
              | Unix.WEXITED code -> code
              | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> 128 + signal
            in
            Ok (code, trim text)
          with
          | Unix.Unix_error (error, _, _) ->
              Error
                (Printf.sprintf "gospel could not be executed: %s"
                   (Unix.error_message error))
          | Sys_error message ->
              Error (Printf.sprintf "gospel could not be executed: %s" message)))

(* ------------------------------------------------------------------- lint *)

let lint ?(emit = print_endline) path =
  match read_file path with
  | exception Sys_error message ->
      emit (Printf.sprintf "%s: cannot read: %s" path message);
      Verdict_internal
  | text ->
      let findings =
        List.stable_sort
          (fun (left : finding) (right : finding) ->
            match compare left.line right.line with
            | 0 -> compare left.rule right.rule
            | order -> order)
          (static_findings text)
      in
      List.iter (fun finding -> emit (render_finding ~source:text path finding)) findings;
      if List.exists (fun finding -> finding.rule = "linter-internal") findings
      then begin
        emit (Printf.sprintf "\n%s: LINTER ERROR - verdict unreliable" path);
        Verdict_internal
      end
      else if findings <> [] then begin
        emit
          (Printf.sprintf "\n%d error(s). Not run through gospel."
             (List.length findings));
        Verdict_errors
      end
      else
        match (if load_path () = [] then external_modules text else []) with
        | _ :: _ as modules ->
            emit
              (Printf.sprintf
                 "%s: NOT CHECKABLE in isolation - unresolvable module(s): %s" path
                 (String.concat ", " modules));
            emit
              "    root cause: gospel resolves a single file. This is a tooling \
               gap, not a specification defect; do not record it as rejected.";
            emit
              "    remedy: put a checking-only stub on GOSPEL_LOAD_PATH. Keep it \
               weaker than the real interface, so it can only reject, never \
               falsely accept.";
            Verdict_not_checkable
        | [] -> (
            match run_gospel path with
            | Error message ->
                emit (Printf.sprintf "%s: gospel UNAVAILABLE - %s" path message);
                emit
                  "    static checks passed, but nothing was authoritatively \
                   verified.";
                Verdict_unavailable
            | Ok (0, _) ->
                emit (Printf.sprintf "%s: OK" path);
                Verdict_ok
            | Ok (_, output)
              when find_word output "No" ~from:0 <> None
                   && contains_word output "module" && contains_word output "name" ->
                emit
                  (Printf.sprintf
                     "%s: NOT CHECKABLE in isolation - gospel could not resolve a \
                      module\n%s" path output);
                emit
                  "    root cause: an interface outside this file. Add a \
                   checking-only stub to GOSPEL_LOAD_PATH; do not record this as \
                   rejected.";
                Verdict_not_checkable
            | Ok (_, output) ->
                emit (Printf.sprintf "%s: gospel REJECTED\n%s" path output);
                Verdict_errors)

let usage =
  "usage: gospel-lint FILE.mli [FILE.mli ...]\n\n\
   Exit codes:\n\
  \  0  OK                     3  gospel binary unavailable\n\
  \  1  errors found           4  internal linter error\n\
  \  2  not checkable here"

let main argv =
  if Array.length argv < 2 then begin
    print_endline usage;
    64
  end
  else begin
    let worst = ref 0 in
    Array.iteri
      (fun index path ->
        if index > 0 then
          if not (Sys.file_exists path) then begin
            print_endline (Printf.sprintf "%s: no such file" path);
            worst := max !worst 4
          end
          else worst := max !worst (exit_code (lint path)))
      argv;
    !worst
  end
