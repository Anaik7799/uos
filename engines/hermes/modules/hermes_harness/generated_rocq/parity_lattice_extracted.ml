
module Nat =
 struct
 end

type verdict =
| Unmapped
| Blocked
| Verified
| Divergent

(** val rank : verdict -> int **)

let rank = function
| Unmapped -> Stdlib.Int.succ 0
| Blocked -> Stdlib.Int.succ (Stdlib.Int.succ 0)
| Verified -> 0
| Divergent -> Stdlib.Int.succ (Stdlib.Int.succ (Stdlib.Int.succ 0))

(** val combine : verdict -> verdict -> verdict **)

let combine a b =
  if (<=) (rank b) (rank a) then a else b

(** val grants_credit : verdict -> bool **)

let grants_credit = function
| Verified -> true
| _ -> false

(** val gate : verdict -> verdict -> verdict **)

let gate a b =
  if grants_credit a then combine a b else a
