type t = Turn_budget.t = { maximum : int; consumed : int }
type consume_result = Turn_budget.consume_result = { allowed : bool; budget : t }

let create = Turn_budget.create
let used = Turn_budget.used
let remaining = Turn_budget.remaining
let consume = Turn_budget.consume
let refund = Turn_budget.refund

let process ~model_id ~messages =
  let b = Turn_budget.create 10 in
  let res = Turn_budget.consume b in
  (`Assoc [
    ("model_id", `String model_id);
    ("allowed", `Bool res.allowed);
    ("remaining", `Int (Turn_budget.remaining res.budget));
    ("messages_count", `Int (List.length messages))
  ] : Yojson.Safe.t)
