(** Immutable iteration budget shared by one agent turn lineage.

    A caller carries the returned [budget] into its next transition.  The
    explicit result prevents an exhausted budget from being mistaken for a
    successful consume and keeps parent/child policies composable. *)

type t = { maximum : int; consumed : int }

type consume_result = { allowed : bool; budget : t }

(* Faithful to the frozen IterationBudget: the cap is CARRIED as given (a
   negative cap simply refuses every consume); clamping happens only in the
   remaining REPORT, exactly like the reference's max(0, max_total - used). *)
let create maximum = { maximum; consumed = 0 }
let used budget = budget.consumed
let remaining budget = max 0 (budget.maximum - budget.consumed)

let consume budget =
  if budget.consumed >= budget.maximum then { allowed = false; budget }
  else { allowed = true; budget = { budget with consumed = budget.consumed + 1 } }

let refund budget =
  if budget.consumed = 0 then budget
  else { budget with consumed = budget.consumed - 1 }
