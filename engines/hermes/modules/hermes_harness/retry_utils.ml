(* Retry-After parsing: candidate for model_routing.rate_and_retry.

   parse_retry_after_seconds mirrors the frozen function's deterministic branches;
   the HTTP-date branch (datetime.now) is out of scope, so date-like inputs are
   excluded from scenarios. A negative value clamps to 0.; None/bool and empty or
   non-numeric strings are None. Faithful for the deterministic surface, proven by
   the differential fixtures. *)

let parse_retry_after_seconds (value : Yojson.Safe.t) : float option =
  let clamp f = if f < 0.0 then 0.0 else f in
  let of_text text =
    let trimmed = String.trim text in
    if trimmed = "" then None
    else match float_of_string_opt trimmed with Some f -> Some (clamp f) | None -> None
  in
  match value with
  | `Null | `Bool _ -> None
  | `Int n -> Some (clamp (float_of_int n))
  | `Float f -> Some (clamp f)
  | `Intlit s -> ( match float_of_string_opt s with Some f -> Some (clamp f) | None -> None)
  | `String s -> of_text s
  | `Assoc _ | `List _ -> None
