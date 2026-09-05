(* Forward-chaining production-rule engine -- the drift-diagnosis rule gate.

   MIRRORED from the prior zigvm harness's rete.ml (R14), preserving its honest
   naming note: this is a NAIVE forward-chaining matcher, not the Rete algorithm
   (no alpha/beta network, no token memories, no unlinking). At this fact/rule
   volume the naive re-match is correct and fast; the load-bearing property is
   the ZERO-TRUST GATE discipline -- an Error action rejects the run, fail
   closed. A genuine Rete network is worth building only if volume grows. *)

module Value = struct
  type t = Int of int | String of string | Bool of bool

  let to_string = function
    | Int i -> string_of_int i
    | String s -> s
    | Bool b -> string_of_bool b

  let equals a b =
    match (a, b) with
    | Int x, Int y -> x = y
    | String x, String y -> String.equal x y
    | Bool x, Bool y -> x = y
    | _ -> false
end

type fact = { fact_kind : string; attrs : (string * Value.t) list }

type operator = Eq | Neq | StartsWith | EndsWith

let eval_op op v1 v2 =
  match (op, v1, v2) with
  | Eq, a, b -> Value.equals a b
  | Neq, a, b -> not (Value.equals a b)
  | StartsWith, Value.String a, Value.String b -> String.starts_with ~prefix:b a
  | EndsWith, Value.String a, Value.String b -> String.ends_with ~suffix:b a
  | _, _, _ -> false

type condition =
  | FieldCmp of string * operator * Value.t
  | VarBind of string * string
  | VarCmp of string * operator * string

type pattern = { pat_kind : string; conds : condition list; bind_name : string option }

module WM = struct
  type t = { mutable facts : fact list }

  let create () = { facts = [] }

  let insert wm fact_kind attrs =
    let f = { fact_kind; attrs } in
    wm.facts <- f :: wm.facts

  let get_by_kind wm kind = List.filter (fun f -> String.equal f.fact_kind kind) wm.facts
end

type rule = {
  name : string;
  patterns : pattern list;
  action : WM.t -> (string * fact) list -> (unit, string) result;
}

let rec match_patterns wm bindings remaining_patterns matched_facts =
  match remaining_patterns with
  | [] -> [ (bindings, matched_facts) ]
  | pat :: rest ->
      let candidates = WM.get_by_kind wm pat.pat_kind in
      let valid_facts =
        List.filter
          (fun f ->
            List.for_all
              (fun cond ->
                match cond with
                | FieldCmp (field, op, expected) -> (
                    try eval_op op (List.assoc field f.attrs) expected
                    with Not_found -> false)
                | VarBind _ -> true
                | VarCmp (field, op, var) -> (
                    try
                      let f_val = List.assoc field f.attrs in
                      let v_val = List.assoc var bindings in
                      eval_op op f_val v_val
                    with Not_found -> false))
              pat.conds)
          candidates
      in
      List.concat_map
        (fun f ->
          let new_bindings =
            List.fold_left
              (fun acc cond ->
                match cond with
                | VarBind (var, field) -> (
                    try (var, List.assoc field f.attrs) :: acc with Not_found -> acc)
                | _ -> acc)
              bindings pat.conds
          in
          let named_match = match pat.bind_name with Some n -> [ (n, f) ] | None -> [] in
          match_patterns wm new_bindings rest (named_match @ matched_facts))
        valid_facts

let fire_rules wm rules =
  let rec run_rules = function
    | [] -> Ok ()
    | rule :: rest ->
        let matches = match_patterns wm [] rule.patterns [] in
        let rec process_matches = function
          | [] -> run_rules rest
          | (_, named_facts) :: m_rest -> (
              match rule.action wm named_facts with
              | Ok () -> process_matches m_rest
              | Error e -> Error (Printf.sprintf "Rule '%s' violated: %s" rule.name e))
        in
        process_matches matches
  in
  run_rules rules
