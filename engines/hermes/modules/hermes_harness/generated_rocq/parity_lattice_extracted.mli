
module Nat :
 sig
 end

type verdict =
| Unmapped
| Blocked
| Verified
| Divergent

val rank : verdict -> int

val combine : verdict -> verdict -> verdict

val grants_credit : verdict -> bool

val gate : verdict -> verdict -> verdict
