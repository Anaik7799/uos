module S = Smtml.Solver.Batch (Smtml.Z3_mappings)
open Smtml

let int_sym name = Expr.symbol (Symbol.make Ty.Ty_int name)
let int_val value = Expr.value (Value.Int value)
let eq left right = Expr.relop Ty.Ty_bool Ty.Relop.Eq left right
let le left right = Expr.relop Ty.Ty_int Ty.Relop.Le left right
let lt left right = Expr.relop Ty.Ty_int Ty.Relop.Lt left right
let band left right = Expr.binop Ty.Ty_bool Ty.Binop.And left right
let bor left right = Expr.binop Ty.Ty_bool Ty.Binop.Or left right
let bnot item = Expr.unop Ty.Ty_bool Ty.Unop.Not item
let add left right = Expr.binop Ty.Ty_int Ty.Binop.Add left right
let ite condition when_true when_false =
  Expr.triop Ty.Ty_bool Ty.Triop.Ite condition when_true when_false
let implies left right = bor (bnot left) right

let bool_int value = band (le (int_val 0) value) (le value (int_val 1))
let is_true value = eq value (int_val 1)

let checks = ref 0
let failures = ref 0

let check name constraints query expected =
  incr checks;
  let solver = S.create () in
  let got = S.check solver (query :: constraints) in
  if got = expected then Printf.printf "PASS %s\n" name
  else begin
    incr failures;
    Printf.eprintf "FAIL %s expected=%s got=%s\n" name
      (match expected with `Sat -> "sat" | `Unsat -> "unsat" | `Unknown -> "unknown")
      (match got with `Sat -> "sat" | `Unsat -> "unsat" | `Unknown -> "unknown")
  end

let () =
  let validated = int_sym "ea_validated" in
  let authorized = int_sym "ea_authorized" in
  let admitted = int_sym "ea_admitted" in
  let prepared = int_sym "ea_prepared" in
  let executed = int_sym "ea_executed" in
  let lifecycle =
    [ bool_int validated; bool_int authorized; bool_int admitted;
      bool_int prepared; bool_int executed;
      eq admitted (ite (band (is_true validated) (is_true authorized))
                     (int_val 1) (int_val 0));
      eq prepared admitted; eq executed prepared ]
  in
  check "EA-Z3-01 executed implies validated"
    lifecycle (bnot (implies (is_true executed) (is_true validated))) `Unsat;
  check "EA-Z3-02 executed implies authorized"
    lifecycle (bnot (implies (is_true executed) (is_true authorized))) `Unsat;
  check "EA-Z3-03 executed implies admitted and prepared"
    lifecycle
    (bnot (implies (is_true executed)
             (band (is_true admitted) (is_true prepared)))) `Unsat;
  check "EA-Z3-CONTROL-01 authorization-bypass mutant is reachable without the law"
    [ bool_int authorized; bool_int executed ]
    (band (is_true executed) (eq authorized (int_val 0))) `Sat;

  let depth = int_sym "ea_mailbox_depth" in
  let capacity = int_sym "ea_mailbox_capacity" in
  let next_depth =
    ite (lt depth capacity) (add depth (int_val 1)) depth
  in
  let mailbox = [ le (int_val 0) depth; lt (int_val 0) capacity; le depth capacity ] in
  check "EA-Z3-04 bounded enqueue never exceeds capacity"
    mailbox (bnot (le next_depth capacity)) `Unsat;
  let mutant_next = add depth (int_val 1) in
  check "EA-Z3-CONTROL-02 unbounded enqueue mutant overflows"
    mailbox (band (eq depth capacity) (lt capacity mutant_next)) `Sat;

  let failures_in_window = int_sym "ea_failures_in_window" in
  let max_restarts = int_sym "ea_max_restarts" in
  let restart_allowed =
    ite (lt failures_in_window max_restarts) (int_val 1) (int_val 0)
  in
  let restart = [ le (int_val 0) failures_in_window; lt (int_val 0) max_restarts ] in
  check "EA-Z3-05 restart intensity absorbs a storm"
    restart
    (band (le max_restarts failures_in_window) (is_true restart_allowed)) `Unsat;
  check "EA-Z3-CONTROL-03 always-restart mutant permits a storm"
    restart (band (le max_restarts failures_in_window) (is_true (int_val 1))) `Sat;

  let semantic_credit = int_sym "ea_semantic_credit" in
  let transport_success = int_sym "ea_transport_success" in
  let granted_credit = semantic_credit in
  let credit = [ bool_int semantic_credit; bool_int transport_success ] in
  check "EA-Z3-06 transport cannot escalate semantic credit"
    credit
    (band (eq semantic_credit (int_val 0)) (is_true granted_credit)) `Unsat;
  check "EA-Z3-CONTROL-04 transport-credit mutant escalates"
    credit
    (band (eq semantic_credit (int_val 0)) (is_true transport_success)) `Sat;

  let recommendation = int_sym "ea_recommendation" in
  let effect_authority = int_sym "ea_prediction_effect_authority" in
  let prediction =
    [ bool_int recommendation; bool_int effect_authority;
      eq effect_authority (int_val 0) ]
  in
  check "EA-Z3-07 prediction has no effect authority"
    prediction (band (is_true recommendation) (is_true effect_authority)) `Unsat;
  check "EA-Z3-CONTROL-05 auto-tuning mutant is satisfiable"
    [ bool_int recommendation; bool_int effect_authority ]
    (band (is_true recommendation) (is_true effect_authority)) `Sat;

  let self = Suite_telemetry.observe ~suite:"test_external_access_smt"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0 in
  Printf.printf "SUMMARY %d passed, %d failed, 0 skipped\n"
    (!checks - !failures) !failures;
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
