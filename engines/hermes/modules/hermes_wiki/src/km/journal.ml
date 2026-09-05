(* KM journal integrity — see journal.mli. Ported laws from the imported
   journal_bundle model: the privacy trio with Secret rejection, plus the
   house R16 naming and append-only disciplines. *)

let is_digit c = c >= '0' && c <= '9'

let int_at value offset length =
  int_of_string (String.sub value offset length)

let leap_year year =
  year mod 400 = 0 || (year mod 4 = 0 && year mod 100 <> 0)

let days_in_month year = function
  | 1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
  | 4 | 6 | 9 | 11 -> 30
  | 2 -> if leap_year year then 29 else 28
  | _ -> 0

let valid_name name =
  Filename.check_suffix name ".md"
  &&
  let stem = Filename.chop_suffix name ".md" in
  String.length stem >= 15
  && List.for_all (fun i -> is_digit stem.[i])
       [ 0; 1; 2; 3; 4; 5; 6; 7; 9; 10; 11; 12 ]
  && stem.[8] = '-'
  && stem.[13] = '-'
  &&
  let year = int_at stem 0 4 in
  let month = int_at stem 4 2 in
  let day = int_at stem 6 2 in
  let hour = int_at stem 9 2 in
  let second = int_at stem 11 2 in
  let slug = String.sub stem 14 (String.length stem - 14) in
  month >= 1 && month <= 12
  && day >= 1 && day <= days_in_month year month
  && hour >= 0 && hour <= 23
  && second >= 0 && second <= 59
  && slug <> ""
  && String.for_all
       (fun c -> c = '-' || is_digit c || (c >= 'a' && c <= 'z'))
       slug

type privacy = Public_data | Personal_identifier | Secret

let privacy_of_string = function
  | "public_data" -> Ok Public_data
  | "personal_identifier" -> Ok Personal_identifier
  | "secret" -> Ok Secret
  | other -> Error ("unknown privacy class (the trio is closed): " ^ other)

(* the imported model's own law: a Secret artifact is REJECTED, never
   bundled. Not a knob. *)
let admissible = function Secret -> false | Public_data | Personal_identifier -> true

let append_violation ~old_content ~new_content =
  let ol = String.length old_content in
  if String.length new_content >= ol && String.sub new_content 0 ol = old_content then None
  else begin
    let old_lines = String.split_on_char '\n' old_content in
    let new_lines = String.split_on_char '\n' new_content in
    let rec first_diff i = function
      | o :: os, n :: ns -> if String.equal o n then first_diff (i + 1) (os, ns) else Some i
      | _ :: _, [] -> Some i
      | [], _ -> None
    in
    match first_diff 1 (old_lines, new_lines) with
    | Some i -> Some (Printf.sprintf "history rewritten at line %d (append-only, R16)" i)
    | None -> Some "journal shrunk (append-only, R16)"
  end
