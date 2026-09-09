(** A finite symbolic check for the independent EV98 register-order model.
    This module has no process, network, filesystem, or receipt effects.  It
    is deliberately run only by [ev98_health_smt_child.exe]. *)

module S = Smtml.Solver.Batch (Smtml.Z3_mappings)
open Smtml

type symbolic_register = { sample : Expr.t; logical : Expr.t; writer : Expr.t }

let int_symbol name = Expr.symbol (Symbol.make Ty.Ty_int name)
let int_value value = Expr.value (Value.Int value)
let bool_value value = Expr.value (if value then Value.True else Value.False)
let equal left right = Expr.relop Ty.Ty_bool Ty.Relop.Eq left right
let less_equal left right = Expr.relop Ty.Ty_int Ty.Relop.Le left right
let and_ left right = Expr.binop Ty.Ty_bool Ty.Binop.And left right
let or_ left right = Expr.binop Ty.Ty_bool Ty.Binop.Or left right
let not_ value = Expr.unop Ty.Ty_bool Ty.Unop.Not value
(* Smtml 0.29 encodes ITE through the Boolean constructor even when its
   branches are integer expressions; this is the realized API pattern used by
   hermes_harness/test_smtml_lattice.ml. *)
let ite_int condition when_true when_false =
  Expr.triop Ty.Ty_bool Ty.Triop.Ite condition when_true when_false

let greater left right = not_ (less_equal left right)

let all predicates = List.fold_left and_ (bool_value true) predicates
let any predicates = List.fold_left or_ (bool_value false) predicates

let same_register left right =
  all [ equal left.sample right.sample;
        equal left.logical right.logical;
        equal left.writer right.writer ]

let select left right =
  let left_wins =
    Expr.triop Ty.Ty_bool Ty.Triop.Ite
      (greater left.sample right.sample)
      (bool_value true)
      (Expr.triop Ty.Ty_bool Ty.Triop.Ite
         (greater right.sample left.sample)
         (bool_value false)
         (Expr.triop Ty.Ty_bool Ty.Triop.Ite
            (greater left.logical right.logical)
            (bool_value true)
            (Expr.triop Ty.Ty_bool Ty.Triop.Ite
               (greater right.logical left.logical)
               (bool_value false)
               (greater left.writer right.writer))))
  in
  { sample = ite_int left_wins left.sample right.sample;
    logical = ite_int left_wins left.logical right.logical;
    writer = ite_int left_wins left.writer right.writer }

let select_logical_first left right =
  let left_wins =
    Expr.triop Ty.Ty_bool Ty.Triop.Ite
      (greater left.logical right.logical) (bool_value true)
      (Expr.triop Ty.Ty_bool Ty.Triop.Ite
         (greater right.logical left.logical) (bool_value false)
         (greater left.sample right.sample))
  in
  { sample = ite_int left_wins left.sample right.sample;
    logical = ite_int left_wins left.logical right.logical;
    writer = ite_int left_wins left.writer right.writer }

let select_without_writer left right =
  let left_wins =
    Expr.triop Ty.Ty_bool Ty.Triop.Ite
      (greater left.sample right.sample) (bool_value true)
      (Expr.triop Ty.Ty_bool Ty.Triop.Ite
         (greater right.sample left.sample) (bool_value false)
         (greater left.logical right.logical))
  in
  { sample = ite_int left_wins left.sample right.sample;
    logical = ite_int left_wins left.logical right.logical;
    writer = ite_int left_wins left.writer right.writer }

let bounded field = all [ less_equal (int_value 0) field; less_equal field (int_value 2) ]

let range registers =
  List.concat_map
    (fun register -> [ bounded register.sample; bounded register.logical; bounded register.writer ])
    registers
  |> all

let register prefix =
  { sample = int_symbol (prefix ^ "_sample");
    logical = int_symbol (prefix ^ "_logical");
    writer = int_symbol (prefix ^ "_writer") }

let a = register "a"
let b = register "b"
let c = register "c"
let full_range = range [ a; b; c ]

type outcome = {
  name : string;
  expected : string;
  actual : string;
  query_sha256 : string;
  assignment : string;
  independently_validated : bool;
}

let normalized_query constraints =
  constraints
  |> List.map (Format.asprintf "%a" Expr.pp)
  |> String.concat "\n"

let query_sha256 constraints =
  Cryptokit.transform_string (Cryptokit.Hexa.encode ())
    (Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) (normalized_query constraints))

let int_value_of solver expression =
  let rendered = Format.asprintf "%a" Expr.pp (S.get_value solver expression) in
  try int_of_string rendered with Failure _ -> -1

let concrete_register solver symbolic =
  { Ev98_health_model.sample = int_value_of solver symbolic.sample;
    logical = int_value_of solver symbolic.logical;
    writer = int_value_of solver symbolic.writer;
    payload = 0 }

let bounded record =
  record.Ev98_health_model.sample >= 0 && record.sample <= 2
  && record.logical >= 0 && record.logical <= 2
  && record.writer >= 0 && record.writer <= 2

let assignment left right =
  Printf.sprintf "a=(%d,%d,%d);b=(%d,%d,%d)"
    left.Ev98_health_model.sample left.logical left.writer
    right.Ev98_health_model.sample right.logical right.writer

let select_logical_first_independent
    (left : Ev98_health_model.register)
    (right : Ev98_health_model.register) =
  if left.Ev98_health_model.logical > right.logical then left
  else if left.logical < right.logical then right
  else if left.sample > right.sample then left
  else right

let select_without_writer_independent
    (left : Ev98_health_model.register)
    (right : Ev98_health_model.register) =
  if left.Ev98_health_model.sample > right.sample then left
  else if left.sample < right.sample then right
  else if left.logical > right.logical then left
  else if left.logical < right.logical then right
  else right

let unsat_row name constraints =
  let actual =
    match S.check (S.create ()) constraints with
    | `Sat -> "SAT" | `Unsat -> "UNSAT" | `Unknown -> "UNKNOWN"
  in
  { name; expected = "UNSAT"; actual; query_sha256 = query_sha256 constraints;
    assignment = "none"; independently_validated = actual = "UNSAT" }

let sat_row name constraints validate =
  let solver = S.create () in
  match S.check solver constraints with
  | `Sat ->
    let left = concrete_register solver a and right = concrete_register solver b in
    { name; expected = "SAT"; actual = "SAT"; query_sha256 = query_sha256 constraints;
      assignment = assignment left right;
      independently_validated = bounded left && bounded right && validate left right }
  | `Unsat ->
    { name; expected = "SAT"; actual = "UNSAT"; query_sha256 = query_sha256 constraints;
      assignment = "none"; independently_validated = false }
  | `Unknown ->
    { name; expected = "SAT"; actual = "UNKNOWN"; query_sha256 = query_sha256 constraints;
      assignment = "none"; independently_validated = false }

let negated_sample_dominance =
  all [ greater a.sample b.sample; not_ (same_register (select a b) a) ]

let negated_logical_tiebreak =
  all [ equal a.sample b.sample; greater a.logical b.logical;
        not_ (same_register (select a b) a) ]

let negated_writer_tiebreak =
  all [ equal a.sample b.sample; equal a.logical b.logical;
        greater a.writer b.writer; not_ (same_register (select a b) a) ]

let negated_commutativity = not_ (same_register (select a b) (select b a))
let negated_idempotence = not_ (same_register (select a a) a)
let negated_associativity =
  not_ (same_register (select (select a b) c) (select a (select b c)))

let logical_first_mutant_is_caught =
  all [ greater a.sample b.sample;
        not_ (same_register (select_logical_first a b) a) ]

let no_writer_mutant_is_caught =
  not_ (same_register (select_without_writer a b) (select_without_writer b a))

let finite_witness () =
  List.exists
    (fun (left, right) ->
       left.Ev98_health_model.sample = 2
       && right.Ev98_health_model.sample = 0
       && Ev98_health_model.select left right = left)
    (Ev98_health_model.all_well_formed_pairs ())

let rows () =
  [ unsat_row "sample_dominance" [ full_range; negated_sample_dominance ];
    unsat_row "logical_tiebreak" [ full_range; negated_logical_tiebreak ];
    unsat_row "writer_tiebreak" [ full_range; negated_writer_tiebreak ];
    unsat_row "commutativity" [ full_range; negated_commutativity ];
    unsat_row "idempotence" [ full_range; negated_idempotence ];
    unsat_row "associativity" [ full_range; negated_associativity ];
    sat_row "sanity_sample_witness"
      [ full_range; equal a.sample (int_value 2); equal b.sample (int_value 0);
        same_register (select a b) a ]
      (fun left right ->
         left.Ev98_health_model.sample = 2 && right.sample = 0
         && Ev98_health_model.select left right = left);
    sat_row "mutant_logical_first"
      [ full_range; logical_first_mutant_is_caught ]
      (fun left right ->
         left.Ev98_health_model.sample > right.sample
         && select_logical_first_independent left right <> left);
    sat_row "mutant_no_writer"
      [ full_range; no_writer_mutant_is_caught ]
      (fun left right ->
         left.Ev98_health_model.sample = right.sample
         && left.logical = right.logical && left.writer <> right.writer
         && select_without_writer_independent left right
            <> select_without_writer_independent right left) ]

let rows_hold rows =
  rows
  |> List.for_all (fun row ->
    row.expected = row.actual && row.independently_validated)

let emitted_rows_hold rows =
  Ev98_health_model.laws_hold_by_enumeration ()
  && finite_witness ()
  && rows_hold rows

let all_laws_hold () =
  emitted_rows_hold (rows ())
