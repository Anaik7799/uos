(* Checking-only stub of Turn_budget for `gospel check`. *)

type t = { maximum : int; consumed : int }
type consume_result = { allowed : bool; budget : t }
