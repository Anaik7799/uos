type t = string
type error = Empty | Too_long | Absolute | Invalid_segment | Glob_ambiguous

let maximum_path_length = 4096
let maximum_segment_length = 255

let is_glob_character = function
  | '*' | '?' | '[' | ']' | '{' | '}' | '!' -> true
  | _ -> false

let invalid_character character =
  let code = Char.code character in
  code < 32 || code = 127 || code > 126 || character = '\\'
  || character = ':' || character = '~'

let make value =
  let length = String.length value in
  if length = 0 then Error Empty
  else if length > maximum_path_length then Error Too_long
  else if value.[0] = '/' then Error Absolute
  else if String.exists is_glob_character value then Error Glob_ambiguous
  else
    let segments = String.split_on_char '/' value in
    if
      List.exists
        (fun segment ->
          segment = "" || segment = "." || segment = ".."
          || String.length segment > maximum_segment_length
          || String.exists invalid_character segment)
        segments
    then Error Invalid_segment
    else Ok value

let to_string value = value
let equal = String.equal
let compare = String.compare

let source_digest =
  let length_frame values =
    values
    |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
    |> String.concat "|"
  in
  length_frame
    [ "jj-path-authority-v1";
      "bounds"; string_of_int maximum_path_length;
      string_of_int maximum_segment_length;
      "glob-characters"; "*,?,[,],{,},!";
      "invalid-bytes"; "0-31,127,non-ascii,backslash,colon,tilde";
      "invalid-segments"; "empty,dot,dot-dot";
      "errors";
      length_frame
        [ "empty"; "too-long"; "absolute"; "invalid-segment";
          "glob-ambiguous" ] ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
