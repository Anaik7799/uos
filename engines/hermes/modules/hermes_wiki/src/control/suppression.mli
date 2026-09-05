(* HW.10.2.2 — selective, TYPED suppression: a suppression names a
   diagnostic kind AND a key, never a file, never a blanket. The law:
   suppressing (kind, key) leaves every other diagnostic active. Every
   suppression is disclosed in every audit output (R2), and expiry makes
   the exception temporary by default.

   File format, one per line:  kind|key|reason|YYYY-MM-DD
   (expiry optional: omit the last field for a standing suppression;
   '#' begins a comment line.) *)

type t = { kind : string; key : string; reason : string; expires : string option }

(* Total: malformed lines are NAMED errors; an empty reason is refused —
   an unexplained exception is not an exception, it is a hole. *)
val parse : string list -> (t list, string) result

val serialize : t list -> string list

(* Exact (kind, key) match — the typed law lives here. *)
val applies : t list -> kind:string -> key:string -> bool

(* Partition by expiry against a caller-supplied date (R16: the clock is
   read by the caller from the environment, never invented here). *)
val active : t list -> today:string -> t list
val expired : t list -> today:string -> t list

(* R2: every suppression, rendered for the audit report. *)
val disclose : t list -> string list
