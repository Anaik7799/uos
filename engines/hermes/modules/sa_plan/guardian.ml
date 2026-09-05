open Core

type proposal = {
  diff : string;
  payload : string;
}

let validate_proposal p =
  let content = p.diff ^ " " ^ p.payload in
  let content_lower = String.lowercase content in
  if String.is_substring content_lower ~substring:"continuation-stays" ||
     String.is_substring content_lower ~substring:"memory bound" then
    Error "Safety Violation"
  else
    Ok ()
