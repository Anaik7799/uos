type verdict = Proved | Refuted of string | Unavailable of string
val validate_output : string -> verdict
val run : unit -> verdict
val string_of_verdict : verdict -> string
